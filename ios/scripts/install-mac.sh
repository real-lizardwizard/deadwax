#!/bin/bash
# deadwax for the Mac: build the iPhone app for this Mac (Mac Catalyst) and put it in ~/Applications - James's one
# command, as install.sh is for the phone. docs/ios.md "The Mac app" has what comes first: install.sh run once (it
# writes ios/Config/Local.xcconfig, the team this signs with).
#
#     ~/Developer/deadwax/ios/scripts/install-mac.sh [--no-pull] [--yes] [--debug] [--dry-run]
#
#   --no-pull   build what is checked out, without `git pull`
#   --yes       don't ask: build even if CI failed, and quit deadwax if it's open (which stops the music)
#   --debug     build Debug instead of Release (Release is what to use day to day)
#   --dry-run   say what it would do - build, quit, copy, open - and do none of it
#
# What it does: pulls; asks GitHub whether ios.yml passed on that commit; builds Release for this Mac (arm64) with
# xcodebuild, signed with your team and no provisioning profile, so the install never runs out; checks what it made
# (signed, sandboxed, allowed out to the network, the right bundle id); quits deadwax if it's open - asking first, and
# never by force; copies the new app to ~/Applications/deadwax.app (never /Applications), keeping the old one until
# the new one is in place; and opens it. Its sign-in, settings, downloads and EQ are in its container
# (~/Library/Containers/net.lizardlounge.deadwax), so every install keeps them. Xcode itself never needs to be open.
# No Simulator, nothing installed system-wide, no sudo.
#
# /bin/bash on macOS is 3.2: nothing here needs a newer one.
set -euo pipefail

REPO_SLUG="real-lizardwizard/deadwax"
BUNDLE_ID="net.lizardlounge.deadwax"
# the space a Release build of the Mac app needs: its derived data (about 1 GB, kept in $derived) and Xcode's working
# room on the way there
NEEDS_GB=4
QUIT_WAIT=20
here="$(cd "$(dirname "$0")" && pwd)"
ios="$(dirname "$here")"
repo="$(dirname "$ios")"
config="$ios/Config"
derived="$HOME/Library/Caches/deadwax-build-mac"
applications="$HOME/Applications"
installed="$applications/deadwax.app"

pull=1
ask=1
dry=0
configuration=Release
for argument in "$@"; do
    case "$argument" in
        --no-pull) pull=0 ;;
        --yes) ask=0 ;;
        --debug) configuration=Debug ;;
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $argument (try --help)" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
stop() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }
would() { say "   (dry run) would $*"; }
confirm() {
    # confirm "question" -> yes unless answered n (or --yes, which says yes)
    if [ "$ask" = 0 ]; then return 0; fi
    local answer
    read -r -p "$1 [Y/n] " answer || answer=n
    case "$answer" in [nN]*) return 1 ;; *) return 0 ;; esac
}
free_space() { df -h "$HOME" | awk 'NR==2 {print $4 " free of " $2}'; }
free_kb() { df -k "$HOME" | awk 'NR==2 {print $4}'; }
# whether deadwax is open now: asking AppleScript whether it is running neither opens nor asks it anything
running() {
    [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || true)" = true ]
}

started=$(date +%s)
scratch="$(mktemp -d "${TMPDIR:-/tmp}/deadwax-install-mac.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# ---------------------------------------------------------------- where it runs

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
command -v xcodebuild >/dev/null 2>&1 || stop "xcodebuild isn't here. Install Xcode from the App Store, open it once, then run this again."
xcode_version="$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}')"
[ -n "$xcode_version" ] || stop "xcodebuild didn't answer. Run: xcodebuild -runFirstLaunch (and accept the licence if asked)."
xcode_major="${xcode_version%%.*}"
if [ "$xcode_major" -lt 16 ] 2>/dev/null; then
    stop "Xcode $xcode_version is too old: the project needs Xcode 16 or later."
fi
python="$(xcrun --find python3 2>/dev/null || command -v python3 || true)"
[ -n "$python" ] || stop "No python3 came with Xcode here (xcrun --find python3). Run: xcodebuild -runFirstLaunch"
helper() { "$python" "$here/install_helper.py" "$@"; }

space_before="$(free_space)"
step "Xcode $xcode_version (${DEVELOPER_DIR:-as xcode-select has it}) - $space_before before the build"
free="$(free_kb)"
case "$free" in
    ''|*[!0-9]*) say "Couldn't tell how much space is free; building anyway." ;;
    *)
        if [ "$free" -lt $((NEEDS_GB * 1024 * 1024)) ]; then
            stop "Only $(free_space). A build of the Mac app needs about $NEEDS_GB GB free: its derived data (about 1 GB,
kept in $derived) and Xcode's working room. Free some space - emptying the Trash, or deleting
~/Library/Caches/deadwax-build-mac to start the Mac's build afresh - then run this again."
        fi ;;
esac

# ---------------------------------------------------------------- the team

[ -f "$config/Local.xcconfig" ] || stop "There's no ios/Config/Local.xcconfig, which names the team this signs with. Run
ios/scripts/install.sh once (it offers to write it from the teams Xcode knows), or copy
ios/Config/Local.xcconfig.example to Local.xcconfig and put your team id in it."
team="$(helper setting "$config/Local.xcconfig" DEVELOPMENT_TEAM)"
case "$team" in
    ""|XXXXXXXXXX) stop "ios/Config/Local.xcconfig has no team id in it (DEVELOPMENT_TEAM = your ten-character id)." ;;
esac
say "Signing with team $team, with no provisioning profile: the install doesn't run out."

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
    if [ "$dry" = 1 ]; then
        would "run: git pull --ff-only"
    else
        git pull --ff-only || stop "git pull couldn't fast-forward. Run 'git status' to see why (or use --no-pull to build what's here)."
    fi
fi
commit="$(git rev-parse HEAD)"
step "Building $(git rev-parse --abbrev-ref HEAD) at ${commit:0:7}: $(git log -1 --format=%s)"

if [ "$dry" = 1 ]; then
    would "ask GitHub whether ios.yml passed on ${commit:0:7}, and ask you before building if it failed or is running"
else
    if curl -fsS -m 15 -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$REPO_SLUG/actions/workflows/ios.yml/runs?head_sha=$commit&per_page=5" \
            -o "$scratch/runs.json" 2>/dev/null; then
        ci="$(helper ci "$scratch/runs.json")"
    else
        ci="unknown"
    fi
    case "$ci" in
        success) say "GitHub's checks (ios.yml, the Mac build among them) passed on this commit." ;;
        none) say "GitHub has no ios.yml run for this commit (nothing under ios/ changed in it, or it isn't pushed)." ;;
        unknown) say "Couldn't ask GitHub about this commit's checks; building anyway." ;;
        running*) confirm "GitHub's checks are still running on this commit (${ci#running }). Build anyway?" || stop "Wait for the checks, then run this again." ;;
        *) confirm "GitHub's checks FAILED on this commit (${ci#failure }). Build anyway?" || stop "Not built." ;;
    esac
fi

# ---------------------------------------------------------------- build

app="$derived/Build/Products/$configuration-maccatalyst/Deadwax.app"
log="$derived/last-build.log"
step "xcodebuild ($configuration, this Mac) - a few minutes the first time, less after"
if [ "$dry" = 1 ]; then
    would "run: xcodebuild -project $ios/Deadwax.xcodeproj -scheme Deadwax -configuration $configuration"
    would "     -destination 'generic/platform=macOS,variant=Mac Catalyst' ARCHS=arm64"
    would "     -derivedDataPath $derived -allowProvisioningUpdates build"
    would "     (its log to $log)"
    would "check $app: signed (codesign --verify --strict), sandboxed and allowed out to the network, no keychain"
    would "      groups, bundle id $BUNDLE_ID"
else
    mkdir -p "$derived"
    built_at=$(date +%s)
    if ! xcodebuild -project "$ios/Deadwax.xcodeproj" -scheme Deadwax -configuration "$configuration" \
            -destination 'generic/platform=macOS,variant=Mac Catalyst' ARCHS=arm64 -derivedDataPath "$derived" \
            -allowProvisioningUpdates build > "$log" 2>&1; then
        grep -E "error:|warning: .*(sign|provision)" "$log" | head -20 >&2 || true
        tail -15 "$log" >&2
        stop "The build failed; the whole log is $log. A signing error usually means Xcode has no Apple Development
certificate for your team yet: open Xcode > Settings > Accounts, select your Apple ID, Manage Certificates, + Apple
Development - then run this again."
    fi
    built=$(( $(date +%s) - built_at ))
    say "Built in $((built / 60)) min $((built % 60)) s."

    # ---------------------------------------------------------------- what it made

    step "Checking what it made"
    [ -d "$app" ] || stop "The build said it worked, but there's no $app."
    codesign --verify --strict "$app" 2>"$scratch/verify" || stop "The new app's signature doesn't check out:
$(cat "$scratch/verify")"
    codesign -d --entitlements - --xml "$app" > "$scratch/entitlements.plist" 2>/dev/null || true
    entitled="$(helper entitlements "$scratch/entitlements.plist")"
    [ "$entitled" = ok ] || stop "The new app wasn't signed as the Mac app must be: $entitled"
    made="$(helper plist "$app/Contents/Info.plist" CFBundleIdentifier)"
    [ "$made" = "$BUNDLE_ID" ] || stop "The new app's bundle id is '$made', not $BUNDLE_ID - it would be another,
empty app. Base.xcconfig's PRODUCT_BUNDLE_IDENTIFIER and DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER say why."
    say "Signed, sandboxed, allowed out to the network; $made."
    if [ -e "$app/Contents/embedded.provisionprofile" ]; then
        until=""
        if security cms -D -i "$app/Contents/embedded.provisionprofile" -o "$scratch/profile.plist" 2>/dev/null; then
            until="$(helper expiry "$scratch/profile.plist")"
        fi
        say "Note: Xcode signed this one with a provisioning profile${until:+, which runs out on $until}. The Mac app"
        say "      isn't meant to need one; after that date it won't open until this runs again (docs/ios.md)."
    fi
fi

# ---------------------------------------------------------------- deadwax open

if running; then
    step "deadwax is open"
    if [ "$dry" = 1 ]; then
        would "ask \"deadwax is open - quit it to install the new one?\" and, on yes, tell it to quit (never by force)"
    else
        confirm "deadwax is open - quit it to install the new one? (If it's playing, the music stops.)" \
            || stop "Not installed: deadwax is still open. The new build is in $app; quit deadwax and run this
again with --no-pull when you're ready."
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>"$scratch/quit" \
            || stop "deadwax couldn't be asked to quit: $(cat "$scratch/quit")
macOS may not have let this Terminal control deadwax (System Settings > Privacy & Security > Automation).
Quit deadwax yourself (deadwax > Quit deadwax), then run this again with --no-pull."
        waited=0
        while running; do
            if [ "$waited" -ge "$QUIT_WAIT" ]; then
                stop "deadwax didn't quit within $QUIT_WAIT seconds (is it asking something in its window?). It was left
open - never quit by force. Quit it yourself, then run this again with --no-pull."
            fi
            sleep 1
            waited=$((waited + 1))
        done
        say "deadwax quit."
    fi
fi

# ---------------------------------------------------------------- into place

step "Installing in ~/Applications/deadwax.app (its sign-in, settings and downloads stay)"
new="$applications/.deadwax.app.new"
old="$applications/.deadwax.app.old"
if [ "$dry" = 1 ]; then
    would "copy the new app to $new (ditto), then move it to $installed"
    if [ -e "$installed" ]; then
        would "move the deadwax.app there now aside first, and delete it once the new one is in place"
    fi
    would "open $installed"
    step "Dry run: nothing was built, quit, copied or opened."
    exit 0
fi
mkdir -p "$applications"
# a run stopped between moving the old app aside and moving the new one in: the old one back first
if [ ! -e "$installed" ] && [ -e "$old" ]; then mv "$old" "$installed"; fi
rm -rf "$new" "$old"
ditto "$app" "$new" || { rm -rf "$new"; stop "Couldn't copy the new app into ~/Applications; the deadwax.app there is as it was."; }
if [ -e "$installed" ]; then
    mv "$installed" "$old" || { rm -rf "$new"; stop "Couldn't move the old deadwax.app aside; it is as it was."; }
fi
if ! mv "$new" "$installed"; then
    [ -e "$old" ] && mv "$old" "$installed"
    rm -rf "$new"
    stop "Couldn't put the new app in place; the old deadwax.app is back as it was."
fi
rm -rf "$old"

version="$(helper setting "$config/Base.xcconfig" MARKETING_VERSION)"
build="$(helper setting "$config/Base.xcconfig" CURRENT_PROJECT_VERSION)"
open "$installed" || say "(Installed; open deadwax from ~/Applications yourself - it couldn't be opened from here.)"

elapsed=$(( $(date +%s) - started ))
step "Installed deadwax $version ($build) in ~/Applications - it doesn't run out"
say "Took $((elapsed / 60)) min $((elapsed % 60)) s. Space: $space_before before, $(free_space) now."
