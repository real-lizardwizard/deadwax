#!/bin/bash
# What can be checked of the iPhone app without a Mac - run before every push touching ios/
# (ios.yml runs the same on GitHub's ubuntu runner, and compiles the rest on its macOS runner).
#
#   1. DeadwaxKit built and its Core tested with Swift for Linux (the Audio target compiles to
#      nothing here: AVFAudio is Apple's alone);
#   2. the project files checked: the .pbxproj, the scheme, the xcconfigs, Info.plist, the icons,
#      and no asset catalog or storyboard (check_project.py);
#   3. the shell scripts parsed.
#
# Swift is looked for on PATH, then in ~/.local/swift (swift.org's tarball, unpacked there with no
# sudo - notes/ios.md says which one). Nothing here touches the network or the server.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ios="$(dirname "$here")"

if ! command -v swift >/dev/null 2>&1 && [ -x "$HOME/.local/swift/usr/bin/swift" ]; then
    PATH="$HOME/.local/swift/usr/bin:$PATH"
fi
if ! command -v swift >/dev/null 2>&1; then
    echo "No Swift toolchain: install swift.org's Linux tarball into ~/.local/swift (notes/ios.md)." >&2
    exit 1
fi

echo "== swift: $(swift --version 2>&1 | head -1)"
echo "== DeadwaxKit: build and test"
swift test --package-path "$ios/DeadwaxKit"

echo "== the project files"
python3 "$here/check_project.py"

echo "== the scripts parse"
for script in "$here"/*.sh; do
    bash -n "$script"
done
echo "ok"
