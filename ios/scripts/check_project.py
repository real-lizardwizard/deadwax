#!/usr/bin/env python3
"""
Checks the iPhone app's project files without Xcode - what can be checked on Linux before a push
(ios/scripts/check-linux.sh, and ios.yml's ubuntu job). Standard library only.

  - the .pbxproj parses (an old-style "OpenStep" plist, which plistlib can't read - parsed here),
    every object it names exists, it has one target and it is an app (no extensions: each would be
    another App ID on a free account), its synchronized folder and local package are where it says,
    and the package makes the products the target links;
  - the shared scheme builds that target;
  - the xcconfigs give the bundle id, the app's version and the deployment target, include the
    gitignored Local.xcconfig, and commit no team;
  - Info.plist has the keys the app needs: ATS open for plain http (NSAllowsArbitraryLoads ALONE -
    beside NSAllowsLocalNetworking it is ignored), the Local Network text, background audio, a launch
    screen without a storyboard, and the loose-PNG icons it names, each an opaque PNG of its size;
  - no asset catalog, storyboard, xib or entitlements file anywhere under ios/ (the plan's risk R2: actool
    and ibtool need a Simulator runtime James's Mac doesn't have; and a free account has no use for
    entitlements).

    python3 ios/scripts/check_project.py      # exit 0 and "ok", or every problem and exit 1
"""

import plistlib
import re
import struct
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parent.parent
PROJECT = IOS / "Deadwax.xcodeproj"
BUNDLE_ID = "net.lizardlounge.deadwax"
MARKETING_VERSION = "0.1"
BUILD = "1"
DEPLOYMENT_TARGET = "17.0"
IGNORED_BESIDE_LOCAL = ("NSAllowsLocalNetworking", "NSAllowsArbitraryLoadsForMedia", "NSAllowsArbitraryLoadsInWebContent")


# ----------------------------------------------------------------------------- the OpenStep plist

class OpenStepError(ValueError):
    pass


def parse_openstep(text: str):
    """An old-style plist: dictionaries { k = v; }, arrays ( a, b, ), strings quoted or bare."""
    at = 0

    def skip():
        nonlocal at
        while at < len(text):
            if text[at].isspace():
                at += 1
            elif text.startswith("//", at):
                end = text.find("\n", at)
                at = len(text) if end < 0 else end + 1
            elif text.startswith("/*", at):
                end = text.find("*/", at + 2)
                if end < 0:
                    raise OpenStepError("an unclosed comment")
                at = end + 2
            else:
                return

    def value():
        nonlocal at
        skip()
        if at >= len(text):
            raise OpenStepError("the file ends where a value should be")
        ch = text[at]
        if ch == "{":
            at += 1
            result = {}
            while True:
                skip()
                if text[at] == "}":
                    at += 1
                    return result
                key = value()
                skip()
                if text[at] != "=":
                    raise OpenStepError(f"expected = after {key!r} at {at}")
                at += 1
                result[key] = value()
                skip()
                if text[at] != ";":
                    raise OpenStepError(f"expected ; after the value of {key!r} at {at}")
                at += 1
        if ch == "(":
            at += 1
            result = []
            while True:
                skip()
                if text[at] == ")":
                    at += 1
                    return result
                result.append(value())
                skip()
                if text[at] == ",":
                    at += 1
                elif text[at] != ")":
                    raise OpenStepError(f"expected , or ) at {at}")
        if ch == '"':
            at += 1
            out = []
            while text[at] != '"':
                if text[at] == "\\":
                    at += 1
                    out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(text[at], text[at]))
                else:
                    out.append(text[at])
                at += 1
            at += 1
            return "".join(out)
        match = re.compile(r"[A-Za-z0-9_$+/:.\-<>]+").match(text, at)
        if not match:
            raise OpenStepError(f"unexpected {text[at]!r} at {at}")
        at = match.end()
        return match.group(0)

    result = value()
    skip()
    if at != len(text):
        raise OpenStepError(f"text after the end at {at}")
    return result


# ----------------------------------------------------------------------------- the checks

def check_pbxproj(problems: list) -> dict:
    path = PROJECT / "project.pbxproj"
    try:
        project = parse_openstep(path.read_text(encoding="utf-8"))
    except (OSError, OpenStepError, IndexError) as error:
        problems.append(f"{path}: doesn't parse: {error}")
        return {}
    objects = project.get("objects", {})
    if project.get("objectVersion") != "77":
        problems.append(f"objectVersion is {project.get('objectVersion')}, not 77 (synchronized folders need Xcode 16+)")

    ids = set(objects)
    for oid, obj in objects.items():
        for ref in _references(obj):
            if ref not in ids:
                problems.append(f"{oid} ({obj.get('isa')}) names {ref}, which isn't in the project")

    root = objects.get(project.get("rootObject", ""), {})
    if root.get("isa") != "PBXProject":
        problems.append("rootObject isn't the PBXProject")
        return {}
    targets = [objects.get(t, {}) for t in root.get("targets", [])]
    if len(targets) != 1:
        problems.append(f"{len(targets)} targets; the app is one target, with no extensions")
    natives = [t for t in objects.values() if t.get("isa") in ("PBXNativeTarget", "PBXAggregateTarget", "PBXLegacyTarget")]
    for target in natives:
        if target.get("productType") != "com.apple.product-type.application":
            problems.append(f"target {target.get('name')} is a {target.get('productType')}: only the app itself (each extension is another App ID)")
    target = targets[0] if targets else {}

    groups = [objects.get(g, {}) for g in target.get("fileSystemSynchronizedGroups", [])]
    if [g.get("path") for g in groups] != ["App"]:
        problems.append("the target's synchronized folder isn't App/")
    for group in groups:
        if group.get("isa") != "PBXFileSystemSynchronizedRootGroup" or not (IOS / group.get("path", "")).is_dir():
            problems.append(f"the synchronized folder {group.get('path')} is missing")

    packages = [objects.get(p, {}) for p in root.get("packageReferences", [])]
    local = [p for p in packages if p.get("isa") == "XCLocalSwiftPackageReference"]
    if len(local) != 1 or not (IOS / local[0].get("relativePath", "") / "Package.swift").is_file():
        problems.append("the project doesn't reference the local DeadwaxKit package")
    manifest = (IOS / "DeadwaxKit" / "Package.swift").read_text(encoding="utf-8")
    products = set(re.findall(r'\.library\(name:\s*"([^"]+)"', manifest))
    linked = {objects.get(d, {}).get("productName") for d in target.get("packageProductDependencies", [])}
    if linked != {"DeadwaxCore", "DeadwaxAudio"}:
        problems.append(f"the target links {sorted(n for n in linked if n)}, not DeadwaxCore and DeadwaxAudio")
    for name in linked - products:
        problems.append(f"the target links {name}, which Package.swift doesn't make")

    configs = objects.get(root.get("buildConfigurationList", ""), {}).get("buildConfigurations", [])
    named = {objects[c].get("name"): objects[c] for c in configs if c in objects}
    for name, xcconfig in (("Debug", "Debug.xcconfig"), ("Release", "Release.xcconfig")):
        ref = objects.get(named.get(name, {}).get("baseConfigurationReference", ""), {})
        if ref.get("path") != xcconfig or not (IOS / "Config" / xcconfig).is_file():
            problems.append(f"the project's {name} configuration isn't based on Config/{xcconfig}")
    for obj in objects.values():
        if obj.get("isa") == "XCBuildConfiguration" and "DEVELOPMENT_TEAM" in obj.get("buildSettings", {}):
            problems.append("a team is committed in the .pbxproj: it belongs in the gitignored Config/Local.xcconfig")
    return {"target_id": root.get("targets", [""])[0], "target": target}


def _references(value):
    if isinstance(value, dict):
        for key, inner in value.items():
            if key in ("remoteGlobalIDString",):
                continue
            yield from _references(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from _references(inner)
    elif isinstance(value, str) and re.fullmatch(r"[0-9A-F]{24}", value):
        yield value


def check_scheme(problems: list, target_id: str) -> None:
    path = PROJECT / "xcshareddata" / "xcschemes" / "Deadwax.xcscheme"
    if not path.is_file():
        problems.append("there is no shared Deadwax scheme (xcodebuild -scheme Deadwax needs one)")
        return
    text = path.read_text(encoding="utf-8")
    blueprints = set(re.findall(r'BlueprintIdentifier = "([0-9A-F]{24})"', text))
    if blueprints != {target_id}:
        problems.append(f"the scheme builds {sorted(blueprints)}, not the target {target_id}")
    if 'BuildableName = "Deadwax.app"' not in text:
        problems.append("the scheme's product isn't Deadwax.app")


def xcconfig(name: str) -> dict:
    settings = {}
    for line in (IOS / "Config" / name).read_text(encoding="utf-8").splitlines():
        line = line.split("//", 1)[0].strip()
        if "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            settings[key.strip()] = value.strip()
    return settings


def check_xcconfigs(problems: list) -> dict:
    base = xcconfig("Base.xcconfig")
    wanted = {"PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID, "MARKETING_VERSION": MARKETING_VERSION,
              "CURRENT_PROJECT_VERSION": BUILD, "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
              "PRODUCT_NAME": "Deadwax", "INFOPLIST_FILE": "Config/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
              "SDKROOT": "iphoneos", "CODE_SIGN_STYLE": "Automatic"}
    for key, value in wanted.items():
        if base.get(key) != value:
            problems.append(f"Base.xcconfig: {key} is {base.get(key)!r}, not {value!r}")
    text = (IOS / "Config" / "Base.xcconfig").read_text(encoding="utf-8")
    if '#include? "Local.xcconfig"' not in text:
        problems.append('Base.xcconfig doesn\'t #include? "Local.xcconfig" (where the team id lives)')
    for name in ("Base.xcconfig", "Debug.xcconfig", "Release.xcconfig"):
        if "DEVELOPMENT_TEAM" in xcconfig(name):
            problems.append(f"{name} sets DEVELOPMENT_TEAM: a team belongs in the gitignored Local.xcconfig")
    for name in ("Debug.xcconfig", "Release.xcconfig"):
        if '#include "Base.xcconfig"' not in (IOS / "Config" / name).read_text(encoding="utf-8"):
            problems.append(f"{name} doesn't include Base.xcconfig")
    return base


def png_size(path: Path):
    data = path.read_bytes()
    if data[:8] != bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) or data[12:16] != b"IHDR":
        return None
    width, height, _bits, colour = struct.unpack(">IIBB", data[16:26])
    return width, height, colour


def check_info_plist(problems: list) -> None:
    path = IOS / "Config" / "Info.plist"
    try:
        info = plistlib.loads(path.read_bytes())
    except Exception as error:  # noqa: BLE001 - any failure is the finding
        problems.append(f"Info.plist doesn't parse: {error}")
        return
    ats = info.get("NSAppTransportSecurity", {})
    if ats.get("NSAllowsArbitraryLoads") is not True:
        problems.append("Info.plist: NSAllowsArbitraryLoads isn't YES, so plain http to a dotted name would be refused")
    for key in IGNORED_BESIDE_LOCAL:
        if key in ats:
            problems.append(f"Info.plist: {key} beside NSAllowsArbitraryLoads makes iOS ignore the latter")
    if not str(info.get("NSLocalNetworkUsageDescription", "")).strip():
        problems.append("Info.plist: no NSLocalNetworkUsageDescription - a LAN connection would just fail")
    if "audio" not in info.get("UIBackgroundModes", []):
        problems.append("Info.plist: UIBackgroundModes has no audio - nothing would play locked")
    if "UILaunchScreen" not in info:
        problems.append("Info.plist: no UILaunchScreen (the launch screen without a storyboard)")
    for key in ("UILaunchStoryboardName", "UIMainStoryboardFile", "CFBundleIconName"):
        if key in info:
            problems.append(f"Info.plist: {key} names a storyboard or an asset catalog's icon")
    for key, value in (("CFBundleIdentifier", "$(PRODUCT_BUNDLE_IDENTIFIER)"),
                       ("CFBundleShortVersionString", "$(MARKETING_VERSION)"),
                       ("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)")):
        if info.get(key) != value:
            problems.append(f"Info.plist: {key} isn't {value} (the xcconfig is where it is set)")
    files = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconFiles", [])
    if not files:
        problems.append("Info.plist: no CFBundleIconFiles - the loose-PNG icon isn't named")
    for name in files:
        match = re.fullmatch(r"AppIcon(\d+)x\1", name)
        points = int(match.group(1)) if match else 0
        for scale in (2, 3):
            icon = IOS / "App" / "Icon" / f"{name}@{scale}x.png"
            size = png_size(icon) if icon.is_file() else None
            if size is None:
                problems.append(f"the icon {icon.name} is missing or isn't a PNG")
            elif size[:2] != (points * scale, points * scale) or size[2] != 2:
                problems.append(f"the icon {icon.name} is {size[0]}x{size[1]} colour type {size[2]}, not an opaque RGB {points * scale}x{points * scale}")


def check_no_catalogs(problems: list) -> None:
    for pattern in ("*.xcassets", "*.storyboard", "*.xib", "*.entitlements"):
        for found in IOS.rglob(pattern):
            if ".build" in found.parts:
                continue
            problems.append(f"{found.relative_to(IOS.parent)}: no {pattern[1:]} anywhere under ios/ (risk R2, and a free account)")


def main() -> int:
    problems: list = []
    found = check_pbxproj(problems)
    if found:
        check_scheme(problems, found["target_id"])
    check_xcconfigs(problems)
    check_info_plist(problems)
    check_no_catalogs(problems)
    for problem in problems:
        print("PROBLEM:", problem)
    if problems:
        return 1
    print("ok: the project, the scheme, the xcconfigs, Info.plist and the icons check out")
    return 0


if __name__ == "__main__":
    sys.exit(main())
