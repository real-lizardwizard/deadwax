#!/bin/bash
# deadwax for iPhone: build it and put it on the iPhone - James's one command, every week (a free
# Apple account's install runs 7 days) or whenever a new build is pushed. docs/ios.md has the
# once-only steps that come before the first run.
#
#     ~/Developer/deadwax/ios/scripts/install.sh [--no-pull] [--yes] [--debug]
#
#   --no-pull   build what is checked out, without `git pull`
#   --yes       don't ask: use the one team and the one iPhone there are, build even if CI failed
#   --debug     build Debug instead of Release (Release is what to use day to day)
#
# What it does: pulls; asks GitHub whether ios.yml passed on that commit; builds with xcodebuild
# (Release, automatic signing, which renews the 7-day profile); installs over the app already on
# the phone with devicectl - so its data stays - and opens it. Xcode itself never needs to be
# open, which matters on an 8 GB Mac. No Simulator, nothing installed, no sudo.
#
# /bin/bash on macOS is 3.2: nothing here needs a newer one.
set -euo pipefail

REPO_SLUG="real-lizardwizard/deadwax"
here="$(cd "$(dirname "$0")" && pwd)"
ios="$(dirname "$here")"
repo="$(dirname "$ios")"
config="$ios/Config"
derived="$HOME/Library/Caches/deadwax-build"

pull=1
ask=1
configuration=Release
for argument in "$@"; do
    case "$argument" in
        --no-pull) pull=0 ;;
        --yes) ask=0 ;;
        --debug) configuration=Debug ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $argument (try --help)" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
stop() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }
confirm() {
    # confirm "question" -> yes unless answered n (or --yes, which says yes)
    if [ "$ask" = 0 ]; then return 0; fi
    local answer
    read -r -p "$1 [Y/n] " answer || answer=n
    case "$answer" in [nN]*) return 1 ;; *) return 0 ;; esac
}
free_space() { df -h "$HOME" | awk 'NR==2 {print $4 " free of " $2}'; }

started=$(date +%s)
scratch="$(mktemp -d "${TMPDIR:-/tmp}/deadwax-install.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# ---------------------------------------------------------------- where it runs

case "$repo" in
    "$HOME/Desktop"*|"$HOME/Documents"*|"$HOME/Library/Mobile Documents"*)
        say "Note: the repo is at $repo, which iCloud may sync and evict files from when space runs low."
        say "      Cloning it to ~/Developer/deadwax keeps builds from stalling (docs/ios.md)." ;;
esac

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
command -v xcodebuild >/dev/null 2>&1 || stop "xcodebuild isn't here. Install Xcode from the App Store, open it once, then run this again."
xcode_version="$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}')"
[ -n "$xcode_version" ] || stop "xcodebuild didn't answer. Run: xcodebuild -runFirstLaunch (and accept the licence if asked)."
xcode_major="${xcode_version%%.*}"
if [ "$xcode_major" -lt 16 ] 2>/dev/null; then
    stop "Xcode $xcode_version is too old: the project needs Xcode 16 or later, and an iPhone on iOS 27 needs Xcode 27."
fi
python="$(xcrun --find python3 2>/dev/null || command -v python3 || true)"
[ -n "$python" ] || stop "No python3 came with Xcode here (xcrun --find python3). Run: xcodebuild -runFirstLaunch"
helper() { "$python" "$here/install_helper.py" "$@"; }

step "Xcode $xcode_version (${DEVELOPER_DIR:-as xcode-select has it}) - $(free_space) before the build"
space_before="$(free_space)"

# ---------------------------------------------------------------- the team (once)

if [ ! -f "$config/Local.xcconfig" ]; then
    step "Your Apple team (once)"
    defaults export com.apple.dt.Xcode "$scratch/xcode.plist" 2>/dev/null || true
    plutil -convert xml1 -o "$scratch/xcode.xml" "$scratch/xcode.plist" 2>/dev/null || true
    helper teams "$scratch/xcode.xml" > "$scratch/teams" || true
    count="$(grep -c . "$scratch/teams" || true)"
    if [ "$count" = 0 ]; then
        stop "Xcode knows no Apple ID yet. Open Xcode > Settings > Accounts, press +, add your Apple ID (a
\"Personal Team\" appears), then run this again. Or copy ios/Config/Local.xcconfig.example to
Local.xcconfig and put your team id in it."
    fi
    team="$(head -1 "$scratch/teams" | cut -f1)"
    name="$(head -1 "$scratch/teams" | cut -f2)"
    if [ "$count" -gt 1 ] && [ "$ask" = 1 ]; then
        say "Xcode knows these teams:"
        awk -F'\t' '{printf "  %d. %s  %s (%s)\n", NR, $1, $2, $3}' "$scratch/teams"
        read -r -p "Which one? [1] " pick || pick=1
        pick="${pick:-1}"
        team="$(sed -n "${pick}p" "$scratch/teams" | cut -f1)"
        name="$(sed -n "${pick}p" "$scratch/teams" | cut -f2)"
        [ -n "$team" ] || stop "There's no team $pick."
    fi
    confirm "Sign with team $team ($name)?" || stop "No team chosen. Write ios/Config/Local.xcconfig yourself (Local.xcconfig.example says how)."
    printf '// Your team, written by install.sh (gitignored).\nDEVELOPMENT_TEAM = %s\n' "$team" > "$config/Local.xcconfig"
    say "Wrote ios/Config/Local.xcconfig (DEVELOPMENT_TEAM = $team)."
    # A free team has no iPhone registered until Xcode's first install with the cable, so a build
    # now could only fail on signing: stop here, as the next step, not as an error.
    say ""
    say "Team saved. Next, the first install from Xcode with the cable (docs/ios.md, 'Once' step 5):"
    say "open ios/Deadwax.xcodeproj, choose your iPhone at the top, press Run. Leave Signing &"
    say "Capabilities alone - the team comes from Local.xcconfig. Then run this script again."
    exit 0
fi
team="$(helper setting "$config/Local.xcconfig" DEVELOPMENT_TEAM)"
case "$team" in
    ""|XXXXXXXXXX) stop "ios/Config/Local.xcconfig has no team id in it (DEVELOPMENT_TEAM = your ten-character id)." ;;
esac

# ---------------------------------------------------------------- the code

cd "$repo"
if [ "$pull" = 1 ]; then
    if ! git diff --quiet -- ios/Deadwax.xcodeproj; then
        # Xcode writes a team picked in Signing & Capabilities into the committed project file,
        # which would stop the pull (and must never be committed)
        stop "Xcode has changed ios/Deadwax.xcodeproj here - usually a team picked in Signing &
Capabilities. The team belongs only in ios/Config/Local.xcconfig. Undo Xcode's change with
    git checkout ios/Deadwax.xcodeproj
and run this again (or use --no-pull to build what's here)."
    fi
    step "git pull"
    git pull --ff-only || stop "git pull couldn't fast-forward. Run 'git status' to see why (or use --no-pull to build what's here)."
fi
commit="$(git rev-parse HEAD)"
step "Building $(git rev-parse --abbrev-ref HEAD) at ${commit:0:7}: $(git log -1 --format=%s)"

if curl -fsS -m 15 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO_SLUG/actions/workflows/ios.yml/runs?head_sha=$commit&per_page=5" \
        -o "$scratch/runs.json" 2>/dev/null; then
    ci="$(helper ci "$scratch/runs.json")"
else
    ci="unknown"
fi
case "$ci" in
    success) say "GitHub's checks (ios.yml) passed on this commit." ;;
    none) say "GitHub has no ios.yml run for this commit (nothing under ios/ changed in it, or it isn't pushed)." ;;
    unknown) say "Couldn't ask GitHub about this commit's checks; building anyway." ;;
    running*) confirm "GitHub's checks are still running on this commit (${ci#running }). Build anyway?" || stop "Wait for the checks, then run this again." ;;
    *) confirm "GitHub's checks FAILED on this commit (${ci#failure }). Build anyway?" || stop "Not built." ;;
esac

# ---------------------------------------------------------------- build

step "xcodebuild ($configuration) - a few minutes the first time, less after"
mkdir -p "$derived"
log="$derived/last-build.log"
if ! xcodebuild -project "$ios/Deadwax.xcodeproj" -scheme Deadwax -configuration "$configuration" \
        -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > "$log" 2>&1; then
    grep -E "error:|warning: .*(sign|provision)" "$log" | head -20 >&2 || true
    tail -15 "$log" >&2
    stop "The build failed; the whole log is $log. A signing error the first time usually means the first
install has to be made from Xcode with the cable (docs/ios.md, 'Once')."
fi
app="$derived/Build/Products/$configuration-iphoneos/Deadwax.app"
[ -d "$app" ] || stop "The build said it worked, but there's no $app."
version="$(helper setting "$config/Base.xcconfig" MARKETING_VERSION)"
build="$(helper setting "$config/Base.xcconfig" CURRENT_PROJECT_VERSION)"
bundle="$(helper setting "$config/Base.xcconfig" PRODUCT_BUNDLE_IDENTIFIER)"
until=""
if security cms -D -i "$app/embedded.mobileprovision" -o "$scratch/profile.plist" 2>/dev/null; then
    until="$(helper expiry "$scratch/profile.plist")"
fi

# ---------------------------------------------------------------- the iPhone

step "Finding your iPhone"
saved=""
[ -f "$config/device" ] && saved="$(head -1 "$config/device")"
xcrun devicectl list devices --json-output "$scratch/devices.json" >/dev/null 2>&1 || true
helper devices "$scratch/devices.json" "$saved" > "$scratch/phones" || true
count="$(grep -c . "$scratch/phones" || true)"
[ "$count" != 0 ] || stop "No paired iPhone the Mac can reach now. Connect it with the cable (or turn on 'Connect via
network' in Xcode > Window > Devices, with both on the same Wi-Fi), unlock it, and run this again."
device="$(head -1 "$scratch/phones" | cut -f1)"
phone="$(head -1 "$scratch/phones" | cut -f2)"
if [ "$phone" != "$saved" ] && [ "$count" -gt 1 ] && [ "$ask" = 1 ]; then
    say "Paired iPhones:"
    awk -F'\t' '{printf "  %d. %s (iOS %s)\n", NR, $2, $3}' "$scratch/phones"
    read -r -p "Which one? [1] " pick || pick=1
    pick="${pick:-1}"
    device="$(sed -n "${pick}p" "$scratch/phones" | cut -f1)"
    phone="$(sed -n "${pick}p" "$scratch/phones" | cut -f2)"
    [ -n "$device" ] || stop "There's no iPhone $pick."
fi
printf '%s\n' "$phone" > "$config/device"
say "$phone"

step "Installing over the app on $phone (its downloads and sign-in stay)"
xcrun devicectl device install app --device "$device" "$app" || stop "devicectl couldn't install it. Is the iPhone connected
(by the cable, or on the same Wi-Fi with 'Connect via network' on), unlocked, with Developer Mode on
(Settings > Privacy & Security), and the developer trusted (Settings > General > VPN & Device Management)?"
xcrun devicectl device process launch --device "$device" "$bundle" >/dev/null 2>&1 \
    || say "(Installed; open deadwax on the phone yourself - it couldn't be opened from here, perhaps because the phone is locked.)"

elapsed=$(( $(date +%s) - started ))
step "Installed deadwax $version ($build)${until:+, runs until $until}"
say "Took $((elapsed / 60)) min $((elapsed % 60)) s. Space: $space_before before, $(free_space) now."
