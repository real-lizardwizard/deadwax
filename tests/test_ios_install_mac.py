"""
The Mac app's install and its project rules (the Mac app, slice 1 - notes/ios.md "The Mac app, slice 1: it runs and
plays"), checked on Linux as on a Mac:

  - ios/scripts/install-mac.sh, run under bash with stand-ins on PATH for Apple's tools (xcodebuild, xcrun, codesign,
    osascript, ditto, open, security), curl, df and sleep, in a temporary HOME: its flags and --dry-run, the team's
    three cases, too little space, what GitHub's checks said (--yes), the build and the checks on what it made, a
    provisioning profile refused unless --allow-profile, deadwax open (asked before it is quit unless --quit - never
    --yes - and never forced), the swap into ~/Applications (an old app kept when the copy fails), and that it never
    names /Applications as a place to install, sudo or kill;
  - install_helper.py's two readers it adds: a plist's value, and the entitlements the Mac app is signed with;
  - check_project.py's Mac rules: it passes on the tree, and fails on an Info-Mac.plist that drifts from Info.plist, a
    Mac setting changed or missing, a conditional setting it doesn't name, a MACOSX_DEPLOYMENT_TARGET, and an icon
    that isn't the Mac's.
"""

import importlib.util
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent / "ios" / "scripts"
INSTALL_MAC = SCRIPTS / "install-mac.sh"
BUNDLE_ID = "net.lizardlounge.deadwax"


def load(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_{name}", SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


helper = load("install_helper")
project = load("check_project")

GOOD_ENTITLEMENTS = {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True,
                     "com.apple.security.files.user-selected.read-write": True,
                     "com.apple.security.get-task-allow": True}
#? (slice 6) what install-mac.sh says is missing without the read-write one: the EQ's Open panel and its Save panel
NO_FILES = "no reading a file chosen in the Open panel and writing one saved in the Save panel"


# ----------------------------------------------------------------------------- a Mac of stand-ins

class FakeMac:
    """A copy of ios/scripts and ios/Config in a git repo of its own, a HOME, and stand-ins that log what they're
    asked. `env` sets how they answer (FAKE_*), `running` whether deadwax is open."""

    def __init__(self, tmp_path: Path, team: str | None = "AB12CD34EF"):
        self.tmp = tmp_path
        self.repo = tmp_path / "repo"
        shutil.copytree(SCRIPTS, self.repo / "ios" / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copytree(SCRIPTS.parent / "Config", self.repo / "ios" / "Config",
                        ignore=shutil.ignore_patterns("Local.xcconfig", "device"))
        if team is not None:
            (self.repo / "ios" / "Config" / "Local.xcconfig").write_text(f"DEVELOPMENT_TEAM = {team}\n", encoding="utf-8")
        (self.repo / "ios" / "Deadwax.xcodeproj").mkdir(parents=True)
        (self.repo / "ios" / "Deadwax.xcodeproj" / "project.pbxproj").write_text("// !$*UTF8*$!\n{}\n", encoding="utf-8")
        git = ["git", "-C", str(self.repo), "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git[:3] + ["init", "-q"], check=True)
        subprocess.run(git + ["add", "ios/scripts", "ios/Deadwax.xcodeproj"], check=True)
        subprocess.run(git + ["commit", "-qm", "the Mac app"], check=True)

        self.home = tmp_path / "home"
        self.home.mkdir()
        self.bin = tmp_path / "bin"
        self.bin.mkdir()
        self.calls = tmp_path / "calls"
        self.calls.write_text("", encoding="utf-8")
        self.state = tmp_path / "running"
        self.state.write_text("false", encoding="utf-8")
        self.entitlements = tmp_path / "entitlements.plist"
        self.entitlements.write_bytes(plistlib.dumps(GOOD_ENTITLEMENTS))
        self.env: dict = {}
        log = f'echo "$(basename "$0") $*" >> {self.calls}'
        stubs = {
            "xcodebuild": f"""{log}
if [ "$1" = -version ]; then echo "Xcode 27.2"; echo "Build version 27B52"; exit 0; fi
config=Release; derived=""
while [ $# -gt 0 ]; do
    case "$1" in -configuration) config="$2"; shift ;; -derivedDataPath) derived="$2"; shift ;; esac
    shift
done
if [ -n "${{FAKE_BUILD_FAILS:-}}" ]; then echo "error: the build failed here"; exit 65; fi
app="$derived/Build/Products/$config-maccatalyst/Deadwax.app"
mkdir -p "$app/Contents/MacOS"
echo "the new build" > "$app/Contents/MacOS/Deadwax"
{sys.executable} -c 'import plistlib, sys; sys.stdout.buffer.write(plistlib.dumps({{"CFBundleIdentifier": sys.argv[1]}}))' \\
    "${{FAKE_BUNDLE_ID:-{BUNDLE_ID}}}" > "$app/Contents/Info.plist"
if [ -n "${{FAKE_PROFILE:-}}" ]; then echo profile > "$app/Contents/embedded.provisionprofile"; fi
echo "** BUILD SUCCEEDED **"
""",
            "xcrun": f'{log}\nif [ "$1" = --find ] && [ "$2" = python3 ]; then echo {sys.executable}; exit 0; fi\nexit 1',
            "codesign": f"""{log}
if [ "$1" = --verify ]; then
    if [ -n "${{FAKE_UNSIGNED:-}}" ]; then echo "code object is not signed at all" >&2; exit 1; fi
    exit 0
fi
cat {self.entitlements}
""",
            "osascript": f"""{log}
case "$2" in
    *"is running") cat {self.state} ;;
    *"to quit")
        if [ -n "${{FAKE_QUIT_REFUSED:-}}" ]; then echo "Not authorized to send Apple events to deadwax. (-1743)" >&2; exit 1; fi
        if [ -z "${{FAKE_WONT_QUIT:-}}" ]; then echo false > {self.state}; fi ;;
esac
""",
            "ditto": f'{log}\nif [ -n "${{FAKE_DITTO_FAILS:-}}" ]; then echo "ditto: No space left on device" >&2; exit 1; fi\n'
                     'cp -R "$1" "$2"',
            "open": log,
            "sleep": log,
            "curl": f"""{log}
[ -n "${{FAKE_CI:-}}" ] || exit 7
out=""
while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
cp "$FAKE_CI" "$out"
""",
            "df": f"""{log}
echo "Filesystem 1K-blocks Used Available Capacity Mounted"
if [ "$1" = -k ]; then echo "/dev/disk3s5 239000000 200000000 ${{FAKE_FREE_KB:-20000000}} 90% /"
else echo "/dev/disk3s5 228Gi 190Gi 19Gi 90% /"; fi
""",
            "security": f"""{log}
out=""
while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
{sys.executable} -c 'import plistlib, sys, datetime
sys.stdout.buffer.write(plistlib.dumps({{"ExpirationDate": datetime.datetime(2026, 11, 24, 12, 0),
                                         "UUID": "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"}}))' > "$out"
""",
        }
        for name, body in stubs.items():
            (self.bin / name).write_text("#!/bin/bash\n" + body + "\n", encoding="utf-8")
            (self.bin / name).chmod(0o755)

    @property
    def installed(self) -> Path:
        return self.home / "Applications" / "deadwax.app"

    def run(self, *args: str, answers: str = "", **fake):
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", HOME=str(self.home), TMPDIR=str(self.tmp),
                   **self.env, **{f"FAKE_{key.upper()}": str(value) for key, value in fake.items()})
        env.pop("DEVELOPER_DIR", None)
        return subprocess.run(["bash", str(self.repo / "ios" / "scripts" / "install-mac.sh"), *args], env=env,
                              input=answers, capture_output=True, text=True, timeout=60)

    def called(self, tool: str) -> list[str]:
        return [line for line in self.calls.read_text(encoding="utf-8").splitlines() if line.split(" ", 1)[0] == tool]

    def builds(self) -> list[str]:
        return [line for line in self.called("xcodebuild") if line.endswith(" build")]

    def open_deadwax(self):
        self.state.write_text("true", encoding="utf-8")

    def old_app(self) -> Path:
        (self.installed / "Contents" / "MacOS").mkdir(parents=True)
        (self.installed / "Contents" / "MacOS" / "Deadwax").write_text("the old build\n", encoding="utf-8")
        return self.installed / "Contents" / "MacOS" / "Deadwax"


def said(ran) -> str:
    return ran.stdout + ran.stderr


# ----------------------------------------------------------------------------- the flags

def test_its_help_and_an_unknown_flag(tmp_path):
    mac = FakeMac(tmp_path)
    ran = mac.run("--help")
    assert ran.returncode == 0
    for flag in ("--no-pull", "--yes", "--quit", "--debug", "--dry-run", "--allow-profile"):
        assert f"  {flag} " in ran.stdout and f"[{flag}]" in ran.stdout, flag
    assert "/bin/bash on macOS is 3.2" in ran.stdout, "the whole header"
    assert "~/Applications/deadwax.app" in ran.stdout and "#" not in ran.stdout.splitlines()[0]
    ran = mac.run("--install-everywhere")
    assert ran.returncode == 2 and "Unknown option" in ran.stderr


def test_a_dry_run_says_what_it_would_do_and_does_none_of_it(tmp_path):
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    mac.old_app()
    ran = mac.run("--dry-run")
    assert ran.returncode == 0, said(ran)
    out = ran.stdout
    assert "would run: git pull --ff-only" in out
    assert "would run: xcodebuild -project" in out and "-configuration Release" in out
    assert "-destination 'generic/platform=macOS,variant=Mac Catalyst' ARCHS=arm64" in out
    assert f"-derivedDataPath {mac.home}/Library/Caches/deadwax-build-mac -allowProvisioningUpdates build" in out
    assert "would ask GitHub" in out
    assert 'would ask "deadwax is open - quit it to install the new one?"' in out
    assert f"would copy the new app to {mac.home}/Applications/.deadwax.app.new (ditto), then move it to {mac.installed}" in out
    assert "would move the deadwax.app there now aside first" in out
    assert f"would open {mac.installed}" in out
    assert "Dry run: nothing was built, quit, copied or opened." in out
    assert "no provisioning profile in it" in out and "--allow-profile installs it anyway" in out
    # it looked (the version, the space, the team, whether deadwax is open) and did nothing
    assert mac.builds() == [] and mac.called("ditto") == [] and mac.called("open") == [] and mac.called("curl") == []
    assert not [line for line in mac.called("osascript") if "quit" in line]
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the old build\n"
    assert not (mac.home / "Library").exists()
    # --quit and --allow-profile, said as they'd be done
    ran = mac.run("--dry-run", "--no-pull", "--quit", "--allow-profile")
    assert ran.returncode == 0, said(ran)
    assert "would tell it to quit without asking (--quit) - never by force" in ran.stdout
    assert "installed anyway: --allow-profile" in ran.stdout
    assert not [line for line in mac.called("osascript") if "quit" in line]


def test_debug_builds_debug(tmp_path):
    mac = FakeMac(tmp_path)
    ran = mac.run("--yes", "--no-pull", "--debug")
    assert ran.returncode == 0, said(ran)
    assert "-configuration Debug" in mac.builds()[0]
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the new build\n"


# ----------------------------------------------------------------------------- before the build

@pytest.mark.parametrize("team, words", [
    (None, "Run\nios/scripts/install.sh once"),
    ("XXXXXXXXXX", "has no team id in it"),
    ("", "has no team id in it"),
])
def test_the_team_comes_from_local_xcconfig(tmp_path, team, words):
    mac = FakeMac(tmp_path, team=team)
    ran = mac.run("--yes", "--no-pull")
    assert ran.returncode == 1 and words in ran.stderr
    assert mac.builds() == []


def test_a_team_is_used_and_said(tmp_path):
    mac = FakeMac(tmp_path, team="AB12CD34EF")
    ran = mac.run("--dry-run", "--no-pull")
    assert ran.returncode == 0, said(ran)
    assert "Signing with team AB12CD34EF, with no provisioning profile" in ran.stdout


def test_too_little_space_stops_before_anything(tmp_path):
    mac = FakeMac(tmp_path)
    ran = mac.run("--yes", "--no-pull", free_kb=4 * 1024 * 1024 - 1)
    assert ran.returncode == 1
    assert "needs about 4 GB free" in ran.stderr and "deadwax-build-mac" in ran.stderr
    assert mac.builds() == []
    # and the space is said before the build when there's enough
    ran = mac.run("--yes", "--no-pull", free_kb=4 * 1024 * 1024)
    assert ran.returncode == 0, said(ran)
    assert "19Gi free of 228Gi before the build" in ran.stdout


def test_xcodes_changes_to_the_project_stop_the_pull(tmp_path):
    mac = FakeMac(tmp_path)
    pbxproj = mac.repo / "ios" / "Deadwax.xcodeproj" / "project.pbxproj"
    pbxproj.write_text(pbxproj.read_text() + "// DEVELOPMENT_TEAM = AB12CD34EF;\n", encoding="utf-8")
    ran = mac.run("--yes")
    assert ran.returncode == 1 and "git checkout ios/Deadwax.xcodeproj" in ran.stderr
    assert mac.builds() == []


@pytest.mark.parametrize("run, args, answers, builds, words", [
    ({"status": "completed", "conclusion": "success"}, (), "", True, "passed on this commit"),
    ({"status": "completed", "conclusion": "failure", "html_url": "https://x/1"}, (), "n\n", False, "Not built."),
    ({"status": "completed", "conclusion": "failure", "html_url": "https://x/1"}, ("--yes",), "", True, ""),
    ({"status": "completed", "conclusion": "failure", "html_url": "https://x/1"}, (), "y\n", True, "Installed deadwax"),
    ({"status": "in_progress", "html_url": "https://x/2"}, (), "n\n", False, "Wait for the checks"),
    (None, (), "", True, "has no ios.yml run"),
])
def test_what_githubs_checks_said(tmp_path, run, args, answers, builds, words):
    import json

    mac = FakeMac(tmp_path)
    runs = tmp_path / "runs.json"
    runs.write_text(json.dumps({"workflow_runs": [run] if run else []}), encoding="utf-8")
    ran = mac.run("--no-pull", *args, answers=answers, ci=runs)
    assert ran.returncode == (0 if builds else 1), said(ran)
    assert words in said(ran)
    assert bool(mac.builds()) == builds


def test_github_out_of_reach_builds_anyway(tmp_path):
    mac = FakeMac(tmp_path)
    ran = mac.run("--no-pull")
    assert ran.returncode == 0, said(ran)
    assert "Couldn't ask GitHub" in ran.stdout


# ----------------------------------------------------------------------------- the build and what it made

def test_an_install_builds_checks_copies_and_opens(tmp_path):
    mac = FakeMac(tmp_path)
    ran = mac.run("--yes", "--no-pull")
    assert ran.returncode == 0, said(ran)
    repo, home = mac.repo, mac.home
    assert mac.builds() == [
        f"xcodebuild -project {repo}/ios/Deadwax.xcodeproj -scheme Deadwax -configuration Release "
        "-destination generic/platform=macOS,variant=Mac Catalyst ARCHS=arm64 "
        f"-derivedDataPath {home}/Library/Caches/deadwax-build-mac -allowProvisioningUpdates build"]
    app = f"{home}/Library/Caches/deadwax-build-mac/Build/Products/Release-maccatalyst/Deadwax.app"
    assert mac.called("codesign") == [f"codesign --verify --strict {app}", f"codesign -d --entitlements - --xml {app}"]
    assert mac.called("ditto") == [f"ditto {app} {home}/Applications/.deadwax.app.new"]
    assert mac.called("open") == [f"open {mac.installed}"]
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the new build\n"
    assert sorted(p.name for p in (home / "Applications").iterdir()) == ["deadwax.app"], "nothing left beside it"
    assert (home / "Library" / "Caches" / "deadwax-build-mac" / "last-build.log").is_file()
    out = ran.stdout
    assert "Signed, sandboxed, allowed out to the network and to open and save a file you choose; net.lizardlounge.deadwax." in out
    assert "Installed deadwax 0.13 (13) in ~/Applications - it doesn't run out" in out
    assert re.search(r"Built in \d+ min \d+ s\.", out) and re.search(r"Took \d+ min \d+ s\. Space: .* before, .* now\.", out)
    # nothing asked of deadwax but whether it's open
    assert [line for line in mac.called("osascript") if "quit" in line] == []


def test_over_an_old_one_the_old_goes_once_the_new_is_in(tmp_path):
    mac = FakeMac(tmp_path)
    mac.old_app()
    (mac.installed / "Contents" / "old-only").write_text("x", encoding="utf-8")
    ran = mac.run("--yes", "--no-pull")
    assert ran.returncode == 0, said(ran)
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the new build\n"
    assert not (mac.installed / "Contents" / "old-only").exists(), "the old app replaced whole, not merged"
    assert sorted(p.name for p in (mac.home / "Applications").iterdir()) == ["deadwax.app"]


def test_a_failed_copy_keeps_the_old_app(tmp_path):
    mac = FakeMac(tmp_path)
    old = mac.old_app()
    ran = mac.run("--yes", "--no-pull", ditto_fails=1)
    assert ran.returncode == 1
    assert "the deadwax.app there is as it was" in ran.stderr
    assert old.read_text() == "the old build\n"
    assert sorted(p.name for p in (mac.home / "Applications").iterdir()) == ["deadwax.app"]
    assert mac.called("open") == []


def test_a_run_stopped_midway_gets_its_old_app_back(tmp_path):
    """The old app moved aside, and the run stopped before the new one went in: the next run puts it back first - so a
    copy that fails then still leaves deadwax in ~/Applications."""
    mac = FakeMac(tmp_path)
    mac.old_app()
    mac.installed.rename(mac.home / "Applications" / ".deadwax.app.old")
    ran = mac.run("--yes", "--no-pull", ditto_fails=1)
    assert ran.returncode == 1
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the old build\n"


@pytest.mark.parametrize("fake, words", [
    ({"build_fails": 1}, "The build failed; the whole log is"),
    ({"unsigned": 1}, "signature doesn't check out"),
    ({"bundle_id": "maccatalyst.net.lizardlounge.deadwax"}, "it would be another,\nempty app"),
])
def test_a_build_that_isnt_right_isnt_installed(tmp_path, fake, words):
    mac = FakeMac(tmp_path)
    old = mac.old_app()
    ran = mac.run("--yes", "--no-pull", **fake)
    assert ran.returncode == 1 and words in ran.stderr, said(ran)
    assert old.read_text() == "the old build\n" and mac.called("ditto") == [] and mac.called("open") == []


@pytest.mark.parametrize("entitlements, words", [
    ({"com.apple.security.network.client": True}, "no App Sandbox"),
    ({"com.apple.security.app-sandbox": True}, "no outgoing network connections"),
    ({key: value for key, value in GOOD_ENTITLEMENTS.items() if "user-selected" not in key}, NO_FILES),
    #? (slice 6) read-only alone isn't enough: the Save panel's file couldn't be written
    (dict({key: value for key, value in GOOD_ENTITLEMENTS.items() if "user-selected" not in key},
          **{"com.apple.security.files.user-selected.read-only": True}), NO_FILES),
    (dict(GOOD_ENTITLEMENTS, **{"com.apple.security.files.user-selected.read-write": False}), NO_FILES),
    (dict(GOOD_ENTITLEMENTS, **{"keychain-access-groups": ["X.net.lizardlounge.deadwax"]}), "need a provisioning profile"),
])
def test_the_entitlements_it_was_signed_with_are_checked(tmp_path, entitlements, words):
    mac = FakeMac(tmp_path)
    mac.entitlements.write_bytes(plistlib.dumps(entitlements))
    ran = mac.run("--yes", "--no-pull")
    assert ran.returncode == 1 and words in ran.stderr, said(ran)
    assert mac.called("ditto") == []


def test_a_profile_xcode_embedded_after_all_isnt_installed(tmp_path):
    """The 7-day app James decided against (17 Nov): stopped before deadwax is quit or anything copied, saying when it
    would run out and how to be rid of it - and --yes, which answers GitHub's checks, isn't enough."""
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    old = mac.old_app()
    for args in (("--no-pull",), ("--no-pull", "--yes"), ("--no-pull", "--yes", "--quit")):
        ran = mac.run(*args, answers="y\n", profile=1)
        assert ran.returncode == 1, args
        words = ran.stderr
        assert "Not installed: Xcode signed this build with a provisioning profile, which runs out on" in words
        assert "24 Nov" in words and "the Mac app is meant to need none" in words
        assert "xcrun python3\nios/scripts/check_project.py" in words
        assert "(0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0.provisionprofile)" in words
        assert "~/Library/Developer/Xcode/UserData/Provisioning Profiles" in words
        assert "--allow-profile to install this build anyway (--yes isn't enough)" in words
    assert [line for line in mac.called("osascript") if "quit" in line] == [], "deadwax left playing"
    assert mac.called("ditto") == [] and mac.called("open") == [] and old.read_text() == "the old build\n"


def test_a_profile_is_installed_only_with_allow_profile(tmp_path):
    mac = FakeMac(tmp_path)
    ran = mac.run("--no-pull", "--allow-profile", profile=1)
    assert ran.returncode == 0, said(ran)
    assert "Note: Xcode signed this one with a provisioning profile, which runs out on" in ran.stdout
    assert "24 Nov" in ran.stdout and "installing\n      it anyway (--allow-profile)" in ran.stdout
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the new build\n"


# ----------------------------------------------------------------------------- deadwax open

def test_deadwax_open_is_asked_about_and_left_open_on_no(tmp_path):
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    old = mac.old_app()
    ran = mac.run("--no-pull", answers="n\n")
    assert ran.returncode == 1
    # (read -p shows its question only on a terminal, as install.sh's: the script's text holds it)
    assert "deadwax is open - quit it to install the new one? (If it's playing, the music stops.)" in \
        INSTALL_MAC.read_text(encoding="utf-8")
    assert "Not installed: deadwax is still open" in ran.stderr
    assert [line for line in mac.called("osascript") if "quit" in line] == []
    assert old.read_text() == "the old build\n"


def quits(mac) -> list[str]:
    return [line for line in mac.called("osascript") if "quit" in line]


@pytest.mark.parametrize("answer", ["y\n", "\n"])
def test_deadwax_open_is_asked_to_quit_and_enter_is_yes(tmp_path, answer):
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    mac.old_app()
    ran = mac.run("--no-pull", answers=answer)
    assert ran.returncode == 0, said(ran)
    assert quits(mac) == [f'osascript -e tell application id "{BUNDLE_ID}" to quit']
    assert "deadwax quit." in ran.stdout
    assert (mac.installed / "Contents" / "MacOS" / "Deadwax").read_text() == "the new build\n"


def test_yes_never_stops_the_music_quit_does(tmp_path):
    """--yes answers GitHub's checks alone: with deadwax open it still asks, and with no answer (not a terminal) it
    leaves deadwax playing. --quit quits it without asking."""
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    old = mac.old_app()
    ran = mac.run("--no-pull", "--yes")
    assert ran.returncode == 1 and "Not installed: deadwax is still open" in ran.stderr
    assert "with --quit to quit it without asking" in ran.stderr
    assert quits(mac) == [] and old.read_text() == "the old build\n"
    ran = mac.run("--no-pull", "--quit")
    assert ran.returncode == 0, said(ran)
    assert "Quitting deadwax (--quit)." in ran.stdout and "deadwax quit." in ran.stdout
    assert quits(mac) == [f'osascript -e tell application id "{BUNDLE_ID}" to quit']
    assert old.read_text() == "the new build\n"


def test_deadwax_that_wont_quit_is_left_open_never_forced(tmp_path):
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    old = mac.old_app()
    ran = mac.run("--no-pull", "--quit", wont_quit=1)
    assert ran.returncode == 1
    assert "deadwax didn't quit within 20 seconds" in ran.stderr and "never quit by force" in ran.stderr
    assert len(mac.called("sleep")) == 20
    assert old.read_text() == "the old build\n" and mac.called("ditto") == []


def test_a_quit_macos_wont_send_says_where_to_allow_it(tmp_path):
    mac = FakeMac(tmp_path)
    mac.open_deadwax()
    ran = mac.run("--no-pull", "--quit", quit_refused=1)
    assert ran.returncode == 1
    assert "Not authorized to send Apple events" in ran.stderr and "Privacy & Security > Automation" in ran.stderr
    assert mac.called("ditto") == []


def test_the_script_never_installs_system_wide_nor_forces_a_quit():
    lines = INSTALL_MAC.read_text(encoding="utf-8").splitlines()
    assert lines[0] == "#!/bin/bash"
    code = [line.split("#", 1)[0] if line.lstrip().startswith("#") else line for line in lines[1:]]
    code = [line for line in code if line.strip()]
    for line in code:
        assert not re.search(r"\bsudo\b", line), line
        assert not re.search(r"\b(kill|killall|pkill)\b", line), line
        # /Applications only as Xcode's own folder; deadwax goes to $HOME/Applications (said ~/Applications)
        for found in re.finditer(r"/Applications\b", line):
            before = line[:found.start()]
            assert before.endswith(("$HOME", "~")) or line[found.start():].startswith("/Applications/Xcode.app"), line
    assert 'applications="$HOME/Applications"' in code
    assert 'installed="$applications/deadwax.app"' in code
    assert os.access(INSTALL_MAC, os.X_OK), "executable, as install.sh is"
    assert subprocess.run(["bash", "-n", str(INSTALL_MAC)]).returncode == 0


# ----------------------------------------------------------------------------- install_helper.py's two readers

def test_the_helper_reads_the_entitlements(tmp_path):
    path = tmp_path / "e.plist"
    path.write_bytes(plistlib.dumps(GOOD_ENTITLEMENTS))
    assert helper.entitlements(str(path)) == "ok"
    path.write_bytes(plistlib.dumps({}))
    assert helper.entitlements(str(path)) == ("no App Sandbox (com.apple.security.app-sandbox); no outgoing network "
                                              "connections (com.apple.security.network.client); no reading a file "
                                              "chosen in the Open panel and writing one saved in the Save panel "
                                              "(com.apple.security.files.user-selected.read-write)")
    path.write_bytes(plistlib.dumps(dict(GOOD_ENTITLEMENTS, **{"com.apple.security.application-groups": ["g"]})))
    assert "provisioning profile" in helper.entitlements(str(path))
    path.write_bytes(plistlib.dumps(dict(GOOD_ENTITLEMENTS, **{"com.apple.security.app-sandbox": False})))
    assert "App Sandbox" in helper.entitlements(str(path))
    path.write_text("Executable=/x\n", encoding="utf-8")
    assert "couldn't be read" in helper.entitlements(str(path))
    assert "couldn't be read" in helper.entitlements(str(tmp_path / "missing.plist"))


def test_the_helper_reads_a_plists_value(tmp_path):
    path = tmp_path / "Info.plist"
    path.write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE_ID, "LSRequiresIPhoneOS": True, "N": 3}))
    assert helper.plist(str(path), "CFBundleIdentifier") == BUNDLE_ID
    assert helper.plist(str(path), "LSRequiresIPhoneOS") == "true"
    assert helper.plist(str(path), "N") == "3"
    assert helper.plist(str(path), "CFBundleName") == ""
    assert helper.plist(str(tmp_path / "missing.plist"), "CFBundleIdentifier") == ""
    # a conditional setting is never the phone's own
    xcconfig = SCRIPTS.parent / "Config" / "Base.xcconfig"
    assert helper.setting(str(xcconfig), "INFOPLIST_FILE") == "Config/Info.plist"
    assert helper.setting(str(xcconfig), "TARGETED_DEVICE_FAMILY") == "1"


# ----------------------------------------------------------------------------- check_project.py's Mac rules

def test_the_project_with_the_mac_checks_out(capsys):
    assert project.main() == 0, capsys.readouterr().out
    base = project.xcconfig("Base.xcconfig")
    # a conditional setting is a key of its own: the phone's are as they were
    assert base["TARGETED_DEVICE_FAMILY"] == "1" and base["TARGETED_DEVICE_FAMILY[sdk=macosx*]"] == "6"
    assert base["INFOPLIST_FILE"] == "Config/Info.plist"
    assert base["INFOPLIST_FILE[sdk=macosx*]"] == "Config/Info-Mac.plist"
    assert base["PRODUCT_BUNDLE_IDENTIFIER"] == BUNDLE_ID and base["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER"] == "NO"


@pytest.fixture
def config(tmp_path, monkeypatch):
    """ios/ copied - Config and the icon - with check_project.py pointed at it."""
    shutil.copytree(SCRIPTS.parent / "Config", tmp_path / "Config", ignore=shutil.ignore_patterns("Local.xcconfig", "device"))
    (tmp_path / "App" / "Icon").mkdir(parents=True)
    shutil.copy(SCRIPTS.parent / "App" / "Icon" / "AppIcon.icns", tmp_path / "App" / "Icon")
    monkeypatch.setattr(project, "IOS", tmp_path)
    return tmp_path


def mac_problems(root: Path) -> list:
    found: list = []
    project.check_mac_settings(project.xcconfig("Base.xcconfig"), found)
    project.check_mac_plist(found)
    project.check_mac_icon(found)
    return found


def edit_plist(path: Path, change) -> None:
    info = plistlib.loads(path.read_bytes())
    change(info)
    path.write_bytes(plistlib.dumps(info))


def test_the_mac_plist_cant_drift_from_the_phones(config):
    assert mac_problems(config) == []
    phone, mac = config / "Config" / "Info.plist", config / "Config" / "Info-Mac.plist"
    original_phone, original_mac = phone.read_bytes(), mac.read_bytes()
    cases = [
        (phone, lambda i: i.update(NSBluetoothAlwaysUsageDescription="x"), "no NSBluetoothAlwaysUsageDescription"),
        (mac, lambda i: i.update(NSBluetoothAlwaysUsageDescription="x"), "NSBluetoothAlwaysUsageDescription isn't in Info.plist"),
        (mac, lambda i: i.pop("UIBackgroundModes"), "no UIBackgroundModes"),
        (mac, lambda i: i.update(UIBackgroundModes=["audio"]), "UIBackgroundModes is ['audio']"),
        (phone, lambda i: i["NSAppTransportSecurity"].update(NSAllowsArbitraryLoads=False), "NSAppTransportSecurity is"),
        (mac, lambda i: i.update(LSSupportsOpeningDocumentsInPlace=False), "LSSupportsOpeningDocumentsInPlace isn't in"),
        (mac, lambda i: i.pop("NSSupportsSuddenTermination"), "no NSSupportsSuddenTermination"),
        (mac, lambda i: i.update(NSSupportsAutomaticTermination=True), "NSSupportsAutomaticTermination is True"),
        (mac, lambda i: i.update(CFBundleName="$(PRODUCT_NAME)"), "CFBundleName is '$(PRODUCT_NAME)', not 'deadwax'"),
        (mac, lambda i: i.update(LSApplicationCategoryType="public.app-category.utilities"), "LSApplicationCategoryType"),
        (mac, lambda i: i.pop("CFBundleIconFile"), "no CFBundleIconFile"),
        # (slice 2) the scene manifest: the Mac's many scenes, and otherwise the phone's dictionary, key for key
        (mac, lambda i: i["UIApplicationSceneManifest"].update(UIApplicationSupportsMultipleScenes=False),
         "UIApplicationSceneManifest is {'UIApplicationSupportsMultipleScenes': False}, not "
         "{'UIApplicationSupportsMultipleScenes': True} as Info.plist has it, with the Mac's values within it"),
        (mac, lambda i: i["UIApplicationSceneManifest"].update(UISceneConfigurations={}), "UIApplicationSceneManifest is"),
        (phone, lambda i: i["UIApplicationSceneManifest"].update(UISceneConfigurations={}), "UIApplicationSceneManifest is"),
        (mac, lambda i: i.pop("UIApplicationSceneManifest"), "no UIApplicationSceneManifest"),
    ]
    for path, change, words in cases:
        edit_plist(path, change)
        found = mac_problems(config)
        assert len(found) == 1 and words in found[0] and "drifted" in found[0], (words, found)
        phone.write_bytes(original_phone)
        mac.write_bytes(original_mac)
    # the iPhone keeps its one scene: never loosened to match the Mac's
    edit_plist(phone, lambda i: i["UIApplicationSceneManifest"].update(UIApplicationSupportsMultipleScenes=True))
    found = mac_problems(config)
    assert found == ["Info.plist: UIApplicationSceneManifest's UIApplicationSupportsMultipleScenes is True, not False - "
                     "the iPhone's, as before"], found
    phone.write_bytes(original_phone)
    edit_plist(phone, lambda i: i.update(UIApplicationSceneManifest=[]))
    assert any("isn't a dictionary" in p for p in mac_problems(config))
    phone.write_bytes(original_phone)
    assert plistlib.loads(mac.read_bytes())["UIApplicationSceneManifest"] == {"UIApplicationSupportsMultipleScenes": True}
    assert plistlib.loads(phone.read_bytes())["UIApplicationSceneManifest"] == {"UIApplicationSupportsMultipleScenes": False}
    mac.write_text("not a plist", encoding="utf-8")
    assert any("doesn't parse" in p for p in mac_problems(config))


@pytest.mark.parametrize("old, new, words", [
    ("SUPPORTS_MACCATALYST = YES", "SUPPORTS_MACCATALYST = NO", "SUPPORTS_MACCATALYST is 'NO'"),
    ("DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO", "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = YES",
     "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER is 'YES'"),
    ("TARGETED_DEVICE_FAMILY[sdk=macosx*] = 6", "TARGETED_DEVICE_FAMILY[sdk=macosx*] = 2", "is '2', not '6'"),
    ("TARGETED_DEVICE_FAMILY = 1\n", "TARGETED_DEVICE_FAMILY = 1,2\n", "not '1' (the iPhone)"),
    ("ENABLE_APP_SANDBOX[sdk=macosx*] = YES\n", "", "ENABLE_APP_SANDBOX[sdk=macosx*] is None"),
    ("ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*] = YES", "ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES",
     "ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*] is None"),
    ("INFOPLIST_FILE[sdk=macosx*] = Config/Info-Mac.plist", "INFOPLIST_FILE[sdk=macosx*] = Config/Info.plist",
     "INFOPLIST_FILE[sdk=macosx*] is 'Config/Info.plist'"),
    #? (slice 6) read and write: the EQ's Save panel writes - read only is refused, as is none
    ("ENABLE_USER_SELECTED_FILES[sdk=macosx*] = readwrite", "ENABLE_USER_SELECTED_FILES[sdk=macosx*] = readonly",
     "ENABLE_USER_SELECTED_FILES[sdk=macosx*] is 'readonly', not 'readwrite'"),
    ("ENABLE_USER_SELECTED_FILES[sdk=macosx*] = readwrite\n", "",
     "ENABLE_USER_SELECTED_FILES[sdk=macosx*] is None"),
    ("SUPPORTS_MACCATALYST = YES\n", "SUPPORTS_MACCATALYST = YES\nCODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = x.plist\n",
     "a conditional setting the Mac app's rules don't name"),
    ("SUPPORTS_MACCATALYST = YES\n", "SUPPORTS_MACCATALYST = YES\nMACOSX_DEPLOYMENT_TARGET[sdk=macosx*] = 15.0\n",
     "sets MACOSX_DEPLOYMENT_TARGET"),
    # a KEY = after KEY[sdk=...] hides it - the first Mac build read Info.plist so, and macOS refused it
    ("ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*] = YES\n",
     "ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*] = YES\nINFOPLIST_FILE = Config/Info.plist\n",
     "sets INFOPLIST_FILE after INFOPLIST_FILE[...]"),
    ("ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*] = YES\n",
     "ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*] = YES\nTARGETED_DEVICE_FAMILY = 1\n",
     "sets TARGETED_DEVICE_FAMILY after TARGETED_DEVICE_FAMILY[...]"),
])
def test_each_mac_setting_is_held(config, old, new, words):
    base = config / "Config" / "Base.xcconfig"
    text = base.read_text(encoding="utf-8")
    assert text.count(old) == 1
    base.write_text(text.replace(old, new), encoding="utf-8")
    found = mac_problems(config)
    assert any(words in p for p in found), found


def test_debug_or_release_cant_hide_a_mac_setting(config):
    debug = config / "Config" / "Debug.xcconfig"
    debug.write_text(debug.read_text(encoding="utf-8") + "ENABLE_APP_SANDBOX = NO\n", encoding="utf-8")
    assert any("Debug.xcconfig sets ENABLE_APP_SANDBOX, which hides" in p for p in mac_problems(config))


def icns_of(images: dict) -> bytes:
    body = b"".join(kind.encode() + (8 + len(image)).to_bytes(4, "big") + image for kind, image in images.items())
    return b"icns" + (8 + len(body)).to_bytes(4, "big") + body


def rgba_png(size: int, alpha) -> bytes:
    """An unfiltered 8-bit RGBA PNG, as make-icon.py writes, its alpha at (x, y) from `alpha`."""
    import zlib

    def chunk(kind: bytes, data: bytes) -> bytes:
        return len(data).to_bytes(4, "big") + kind + data + zlib.crc32(kind + data).to_bytes(4, "big")

    rows = b"".join(b"\x00" + b"".join(bytes((18, 16, 22, alpha(x, y))) for x in range(size)) for y in range(size))
    header = size.to_bytes(4, "big") * 2 + bytes((8, 6, 0, 0, 0))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def test_the_macs_icon_is_checked(config):
    icns = config / "App" / "Icon" / "AppIcon.icns"
    data = icns.read_bytes()
    images = project.icns_images(data)
    assert sorted(images) == sorted(["icp4", "ic11", "icp5", "ic12", "ic07", "ic13", "ic08", "ic14", "ic09", "ic10"])
    assert project.png_size(images["ic10"])[:2] == (1024, 1024)
    assert project.png_pixel(images["ic10"], 512, 512)[3] == 255 and project.png_pixel(images["ic10"], 0, 0)[3] == 0
    assert icns_of(images) == data, "read back as written"
    # none
    icns.unlink()
    assert any("AppIcon.icns is missing" in p for p in mac_problems(config))
    # not an icns, or cut short
    icns.write_bytes(b"\x89PNG not an icns")
    assert any("isn't an icns" in p for p in mac_problems(config))
    icns.write_bytes(data[:-10])
    assert any("isn't an icns" in p for p in mac_problems(config))
    # without its 1024
    icns.write_bytes(icns_of({kind: image for kind, image in images.items() if kind != "ic10"}))
    assert any("no 1024-pixel image" in p for p in mac_problems(config))
    # an image at the wrong size, and a type make-icon.py doesn't write
    icns.write_bytes(icns_of(dict(images, ic07=images["ic08"])))
    assert any("its ic07 isn't a 128x128 PNG" in p for p in mac_problems(config))
    icns.write_bytes(icns_of(dict(images, it32=images["ic07"])))
    assert any("'it32', which make-icon.py doesn't write" in p for p in mac_problems(config))
    # the phone's opaque RGB PNG where the 1024 should be
    phone_png = (SCRIPTS.parent / "App" / "Icon" / "AppIcon60x60@3x.png").read_bytes()
    icns.write_bytes(icns_of(dict(images, ic10=phone_png)))
    assert any("its ic10 isn't a 1024x1024 PNG" in p for p in mac_problems(config))
    # a square drawn edge to edge (macOS would show it as a square inside its own), and one with a hole in the middle
    icns.write_bytes(icns_of(dict(images, ic10=rgba_png(1024, lambda x, y: 255))))
    assert any("isn't transparent at its corners" in p for p in mac_problems(config))

    def holed(x: int, y: int) -> int:
        inside = 100 <= x < 924 and 100 <= y < 924
        return 0 if (500 < x < 524 and 500 < y < 524) or not inside else 255

    icns.write_bytes(icns_of(dict(images, ic10=rgba_png(1024, holed))))
    assert any("isn't opaque at its centre" in p for p in mac_problems(config))
