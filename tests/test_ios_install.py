"""
The iPhone app's Mac-side scripts, checked on Linux (notes/ios.md):

  - ios/scripts/install_helper.py, what install.sh reads Apple's and GitHub's answers with: whether
    ios.yml passed on a commit, the teams Xcode knows (a free Personal Team first), the paired iPhones
    (iPads and unpaired phones left out, the one used last first), a provisioning profile's expiry,
    and a setting in an xcconfig;
  - ios/scripts/check_project.py, the project files read without Xcode: it passes on the tree as it
    is, and its old-style plist parser reads the real .pbxproj and refuses what isn't one.
"""

import importlib.util
import json
import plistlib
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent / "ios" / "scripts"


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


helper = load("install_helper")
project = load("check_project")


def write(tmp_path: Path, name: str, data) -> str:
    path = tmp_path / name
    if isinstance(data, bytes):
        path.write_bytes(data)
    else:
        path.write_text(json.dumps(data) if not isinstance(data, str) else data, encoding="utf-8")
    return str(path)


# ----------------------------------------------------------------- CI

@pytest.mark.parametrize("runs, said", [
    ([{"status": "completed", "conclusion": "success", "html_url": "u"}], "success"),
    ([{"status": "completed", "conclusion": "failure", "html_url": "https://x/1"}], "failure https://x/1"),
    ([{"status": "completed", "conclusion": "cancelled", "html_url": "https://x/2"}], "failure https://x/2"),
    ([{"status": "in_progress", "conclusion": None, "html_url": "https://x/3"}], "running https://x/3"),
    ([], "none"),
])
def test_what_ci_said_about_the_commit(tmp_path, runs, said):
    assert helper.ci(write(tmp_path, "runs.json", {"total_count": len(runs), "workflow_runs": runs})) == said


def test_an_unreadable_answer_is_unknown(tmp_path):
    assert helper.ci(write(tmp_path, "runs.json", "<html>rate limited</html>")) == "unknown"
    assert helper.ci(str(tmp_path / "missing.json")) == "unknown"


# ----------------------------------------------------------------- teams

def test_the_free_personal_team_comes_first(tmp_path):
    prefs = {"IDEProvisioningTeamByIdentifier": {
        "acct-1": [{"teamID": "ZZ99ZZ99ZZ", "teamName": "Acme Ltd", "isFreeProvisioningTeam": False},
                   {"teamID": "AB12CD34EF", "teamName": "James Barnett (Personal Team)", "teamType": "Personal Team"}],
        "acct-2": [{"teamID": "not-an-id", "teamName": "broken"}]},
        "SomethingElse": b"\x00\x01"}
    path = write(tmp_path, "xcode.xml", plistlib.dumps(prefs))
    # the free one first, though "Acme" sorts before it by name
    assert helper.teams(path) == ["AB12CD34EF\tJames Barnett (Personal Team)\tfree", "ZZ99ZZ99ZZ\tAcme Ltd\tpaid"]


def test_older_xcodes_key_and_no_teams(tmp_path):
    old = {"IDEProvisioningTeams": {"me@example.com": [{"teamID": "QQ11QQ11QQ", "teamName": "Me", "isFreeProvisioningTeam": True}]}}
    assert helper.teams(write(tmp_path, "old.xml", plistlib.dumps(old))) == ["QQ11QQ11QQ\tMe\tfree"]
    assert helper.teams(write(tmp_path, "none.xml", plistlib.dumps({}))) == []
    assert helper.teams(write(tmp_path, "junk.xml", "not a plist")) == []


# ----------------------------------------------------------------- devices

DEVICES = {"info": {"outcome": "success"}, "result": {"devices": [
    {"identifier": "IPAD", "deviceProperties": {"name": "iPad"}, "hardwareProperties": {"platform": "iOS", "deviceType": "iPad"},
     "connectionProperties": {"pairingState": "paired"}},
    {"identifier": "MAC", "deviceProperties": {"name": "Mac"}, "hardwareProperties": {"platform": "macOS"}},
    {"identifier": "A", "deviceProperties": {"name": "James's iPhone", "osVersionNumber": "27.0"},
     "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone"}, "connectionProperties": {"pairingState": "paired"}},
    {"identifier": "B", "deviceProperties": {"name": "Spare iPhone", "osVersionNumber": "26.4"},
     "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone"}, "connectionProperties": {"pairingState": "paired"}},
    {"identifier": "C", "deviceProperties": {"name": "Unpaired"}, "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone"},
     "connectionProperties": {"pairingState": "unpaired"}},
    {"identifier": "D", "deviceProperties": {"name": "Away iPhone", "osVersionNumber": "27.0"},
     "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone"},
     "connectionProperties": {"pairingState": "paired", "tunnelState": "unavailable"}},
]}}


def test_paired_iphones_only_and_the_saved_one_first(tmp_path):
    path = write(tmp_path, "devices.json", DEVICES)
    assert helper.devices(path) == ["A\tJames's iPhone\t27.0", "B\tSpare iPhone\t26.4"]
    assert helper.devices(path, "Spare iPhone")[0] == "B\tSpare iPhone\t26.4"


def test_a_paired_iphone_out_of_reach_is_not_found(tmp_path):
    # paired once, but no cable and not on the network: not found, so install.sh says to connect it
    assert helper.devices(write(tmp_path, "devices.json", DEVICES), "Away iPhone")[0] == "A\tJames's iPhone\t27.0"
    reachable = {"pairingState": "paired", "tunnelState": "disconnected"}     # devicectl connects on demand
    one = {"result": {"devices": [
        {"identifier": "D", "deviceProperties": {"name": "Away iPhone"}, "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone"},
         "connectionProperties": {"pairingState": "paired", "tunnelState": "unavailable"}}]}}
    assert helper.devices(write(tmp_path, "away.json", one)) == []
    one["result"]["devices"][0]["connectionProperties"] = reachable
    assert helper.devices(write(tmp_path, "near.json", one)) == ["D\tAway iPhone\t?"]


def test_no_devices_answer_is_no_phones(tmp_path):
    assert helper.devices(write(tmp_path, "empty.json", {"result": {"devices": []}})) == []
    assert helper.devices(write(tmp_path, "error.json", {"error": {"code": 1}})) == []
    assert helper.devices(str(tmp_path / "missing.json")) == []


# ----------------------------------------------------------------- the profile and settings

def test_the_install_runs_until(tmp_path, monkeypatch):
    monkeypatch.setenv("TZ", "Europe/London")
    time.tzset()
    try:
        profile = {"ExpirationDate": datetime(2026, 10, 30, 13, 2, tzinfo=timezone.utc), "Name": "x"}
        assert helper.expiry(write(tmp_path, "p.plist", plistlib.dumps(profile))) == "Fri 30 Oct, 13:02"
        summer = {"ExpirationDate": datetime(2026, 7, 3, 9, 0, tzinfo=timezone.utc)}
        assert helper.expiry(write(tmp_path, "s.plist", plistlib.dumps(summer))) == "Fri 3 Jul, 10:00"
        assert helper.expiry(write(tmp_path, "n.plist", plistlib.dumps({}))) == ""
    finally:
        monkeypatch.delenv("TZ")
        time.tzset()


def test_a_setting_in_an_xcconfig(tmp_path):
    path = write(tmp_path, "Base.xcconfig", "// a comment\nPRODUCT_BUNDLE_IDENTIFIER = io.x.y // the id\nMARKETING_VERSION=0.1\n")
    assert helper.setting(path, "PRODUCT_BUNDLE_IDENTIFIER") == "io.x.y"
    assert helper.setting(path, "MARKETING_VERSION") == "0.1"
    assert helper.setting(path, "DEVELOPMENT_TEAM") == ""
    real = str(SCRIPTS.parent / "Config" / "Base.xcconfig")
    assert helper.setting(real, "PRODUCT_BUNDLE_IDENTIFIER") == "net.lizardlounge.deadwax"
    assert helper.setting(real, "MARKETING_VERSION") == "0.1"
    assert helper.setting(real, "CURRENT_PROJECT_VERSION") == "1"


# ----------------------------------------------------------------- the project files

def test_the_project_files_check_out(capsys):
    assert project.main() == 0, capsys.readouterr().out


def test_the_old_style_plist_parser():
    parsed = project.parse_openstep('// !$*UTF8*$!\n{ a = 1; /* c */ b = ( x, "y z", ); c = { d = "q\\"r"; }; }')
    assert parsed == {"a": "1", "b": ["x", "y z"], "c": {"d": 'q"r'}}
    for broken in ("{ a = 1 }", "{ a = ( x y ); }", "{ a = 1; } extra", "{ /* open"):
        with pytest.raises((project.OpenStepError, IndexError)):
            project.parse_openstep(broken)


# ----------------------------------------------------------------- install.sh, against stand-ins for Apple's tools

def fake_mac(tmp_path: Path):
    """A copy of ios/scripts and ios/Config in a git repo of its own, and stand-ins for xcodebuild,
    xcrun, defaults, plutil and curl that log what they are asked."""
    import shutil
    import subprocess
    import sys

    repo = tmp_path / "repo"
    shutil.copytree(SCRIPTS, repo / "ios" / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(SCRIPTS.parent / "Config", repo / "ios" / "Config",
                    ignore=shutil.ignore_patterns("Local.xcconfig", "device"))
    (repo / "ios" / "Deadwax.xcodeproj").mkdir(parents=True)
    (repo / "ios" / "Deadwax.xcodeproj" / "project.pbxproj").write_text("// !$*UTF8*$!\n{}\n", encoding="utf-8")
    git = ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t"]
    subprocess.run(git[:3] + ["init", "-q"], check=True)
    subprocess.run(git + ["add", "ios/scripts", "ios/Deadwax.xcodeproj"], check=True)
    subprocess.run(git + ["commit", "-qm", "x"], check=True)

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "calls"
    prefs = tmp_path / "xcode.plist"
    prefs.write_bytes(plistlib.dumps({"IDEProvisioningTeamByIdentifier": {"a": [
        {"teamID": "AB12CD34EF", "teamName": "James Barnett (Personal Team)", "isFreeProvisioningTeam": True}]}}))
    stubs = {
        "xcodebuild": f'echo "xcodebuild $*" >> {calls}\n'
                      'if [ "$1" = -version ]; then echo "Xcode 27.1"; echo "Build version 27B1"; fi',
        "xcrun": f'echo "xcrun $*" >> {calls}\n'
                 f'if [ "$1" = --find ] && [ "$2" = python3 ]; then echo {sys.executable}; exit 0; fi\nexit 1',
        "defaults": f'echo "defaults $*" >> {calls}\ncp {prefs} "$3"',
        "plutil": f'echo "plutil $*" >> {calls}\ncp "$5" "$4"',
        "curl": f'echo "curl $*" >> {calls}\nexit 7',
    }
    for name, body in stubs.items():
        (bin_dir / name).write_text("#!/bin/bash\n" + body + "\n", encoding="utf-8")
        (bin_dir / name).chmod(0o755)
    return repo, bin_dir, calls


def run_install(repo: Path, bin_dir: Path, tmp_path: Path, *args: str):
    import os
    import subprocess

    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", HOME=str(tmp_path), TMPDIR=str(tmp_path))
    env.pop("DEVELOPER_DIR", None)
    return subprocess.run(["bash", str(repo / "ios" / "scripts" / "install.sh"), *args], env=env,
                          capture_output=True, text=True, timeout=60)


def test_the_first_run_saves_the_team_and_stops_before_a_build(tmp_path):
    repo, bin_dir, calls = fake_mac(tmp_path)
    ran = run_install(repo, bin_dir, tmp_path, "--yes", "--no-pull")
    assert ran.returncode == 0, ran.stdout + ran.stderr
    assert "DEVELOPMENT_TEAM = AB12CD34EF" in (repo / "ios" / "Config" / "Local.xcconfig").read_text()
    assert "first install from Xcode" in ran.stdout
    # no build: a free team has no iPhone registered before Xcode's first install, so it could only fail
    assert not [line for line in calls.read_text().splitlines() if line.startswith("xcodebuild") and "build" in line.split()]


def test_a_team_xcode_wrote_into_the_project_is_named_before_the_pull(tmp_path):
    repo, bin_dir, calls = fake_mac(tmp_path)
    (repo / "ios" / "Config" / "Local.xcconfig").write_text("DEVELOPMENT_TEAM = AB12CD34EF\n", encoding="utf-8")
    pbxproj = repo / "ios" / "Deadwax.xcodeproj" / "project.pbxproj"
    pbxproj.write_text(pbxproj.read_text() + "// DEVELOPMENT_TEAM = AB12CD34EF;\n", encoding="utf-8")
    ran = run_install(repo, bin_dir, tmp_path, "--yes")
    assert ran.returncode == 1
    assert "git checkout ios/Deadwax.xcodeproj" in ran.stderr
    assert "Signing" in ran.stderr and "git pull couldn't" not in ran.stderr


# ----------------------------------------------------------------- the test album

def test_the_test_album_is_ten_flacs_of_beeps_at_known_times_and_a_tone_across_a_join(tmp_path):
    soundfile = pytest.importorskip("soundfile")
    import hashlib

    import numpy as np
    from mutagen.flac import FLAC

    album = load("make-test-album")
    assert album.crc8(b"123456789") == 0xF4 and album.crc16(b"123456789") == 0xFEE8     # FLAC's two CRCs
    assert album.main(["make-test-album.py", str(tmp_path)]) == 0
    files = sorted((tmp_path / "deadwax test" / "Start test (2026)").glob("*.flac"))
    assert [f.name[:2] for f in files] == ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10"]
    tone = []
    for n, path in enumerate(files, 1):
        samples, rate = soundfile.read(str(path), dtype="int16")
        tags = FLAC(str(path))
        assert rate == 44100 and samples.shape[1] == 2 and tags.info.bits_per_sample == 16
        assert tags["artist"] == ["deadwax test"] and tags["album"] == ["Start test"] and tags["date"] == ["2026"]
        assert tags["tracknumber"] == [str(n)] and tags["tracktotal"] == ["10"]
        assert tags.info.md5_signature == int(hashlib.md5(samples.astype("<i2").tobytes()).hexdigest(), 16)
        sound = np.flatnonzero(np.abs(samples[:, 0]) > 100) / rate
        if n <= 6:
            first = (0.0, 0.1, 0.2, 0.3, 0.5, 1.0)[n - 1]
            assert abs(sound[0] - first) < 0.005 and sound[-1] < first + 2.1     # three beeps, a second apart
            assert not samples[: int(first * rate)].any()                          # exact zeros before
        elif n >= 9:
            tone.append(samples[:, 0].astype(np.int64))
        else:
            assert abs(sound[0] - 1.0) < 0.005 and abs(sound[sound > 2][0] - 21.0) < 0.005
            quiet = samples[int(1.1 * rate):int(21 * rate)]
            assert not quiet.any() if n == 7 else 0 < np.abs(quiet).max() < 10
        assert np.abs(samples).max() <= round(32767 * 10 ** (-12 / 20)) + 1        # peak -12 dBFS
    # 9 and 10: one tone cut in two, so a gap or a dropped sample at the join is a click (check 5)
    first, second = tone
    join = len(first)
    assert abs(first[-1]) > 7000 and abs(second[0]) > 7000           # the join near a peak, not in silence
    assert first[0] == 0 and abs(second[-1]) < 100                   # faded in, faded out
    whole = np.concatenate([first, second])
    steady = np.abs(np.diff(whole[2 * 44100:8 * 44100], 2)).max()  # the tone's own curvature, mid-tone
    assert np.abs(np.diff(whole[join - 2:join + 2], 2)).max() <= steady   # the join is no different
    i = np.arange(join - 200, join + 200)
    expected = np.round(np.sin(2 * np.pi * 440 * i / 44100) * 10 ** (-12 / 20) * 32767)
    assert np.abs(whole[join - 200:join + 200] - expected).max() <= 1   # the very next sample of one tone
