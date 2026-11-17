#!/usr/bin/env python3
"""
install.sh's (and install-mac.sh's) reading of what Apple's and GitHub's tools answer - JSON and plists, which a
shell script can't read well and macOS has no jq for. Run with Xcode's own python3 (`xcrun python3`), so
James installs nothing. Standard library only; tested on Linux by tests/test_ios_install.py and
tests/test_ios_install_mac.py.

    install_helper.py ci <runs.json>                  GitHub's ios.yml runs for one commit -> one line:
                                                       "success", "failure <url>", "running <url>" or "none"
    install_helper.py teams <xcode-defaults.xml>       the teams Xcode knows -> "TEAMID<TAB>name<TAB>free|paid" lines
    install_helper.py devices <devicectl.json> [name]  the paired iPhones it can reach now -> "identifier<TAB>name<TAB>iOS"
                                                       lines, the one named first when there is one
    install_helper.py expiry <profile.plist>           a provisioning profile -> "Thu 30 Oct, 14:02"
    install_helper.py setting <file.xcconfig> <KEY>    a setting's value in an xcconfig
    install_helper.py plist <file.plist> <key>         a plist's top-level value, as text ("" when it has none)
    install_helper.py entitlements <entitlements.plist>
                                                       the Mac app's signed entitlements (`codesign -d --entitlements -
                                                       --xml`) -> "ok", or what's wrong with them
"""

from __future__ import annotations

import json
import plistlib
import re
import sys
from datetime import timezone
from pathlib import Path


def ci(path: str) -> str:
    try:
        runs = json.loads(Path(path).read_text(encoding="utf-8")).get("workflow_runs") or []
    except (OSError, ValueError, AttributeError):
        return "unknown"
    if not runs:
        return "none"
    run = runs[0]     # newest first
    url = run.get("html_url") or ""
    if run.get("status") != "completed":
        return f"running {url}".strip()
    if run.get("conclusion") == "success":
        return "success"
    return f"failure {url}".strip()


def teams(path: str) -> list[str]:
    """Xcode's defaults (com.apple.dt.Xcode, as XML): IDEProvisioningTeamByIdentifier (Xcode 15 and
    later) or IDEProvisioningTeams (before) - each account's teams, with teamID, teamName and
    isFreeProvisioningTeam."""
    try:
        prefs = plistlib.loads(Path(path).read_bytes())
    except Exception:  # noqa: BLE001 - nothing readable is no teams
        return []
    found: dict[str, tuple[str, bool]] = {}
    for key in ("IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"):
        accounts = prefs.get(key)
        if not isinstance(accounts, dict):
            continue
        for entries in accounts.values():
            for team in entries if isinstance(entries, list) else []:
                if not isinstance(team, dict):
                    continue
                team_id = str(team.get("teamID", ""))
                if re.fullmatch(r"[A-Z0-9]{10}", team_id):
                    free = bool(team.get("isFreeProvisioningTeam")) or team.get("teamType") == "Personal Team"
                    found[team_id] = (str(team.get("teamName", "")), free)
    # a free Personal Team first: it is the one James has
    ordered = sorted(found.items(), key=lambda item: (not item[1][1], item[1][0]))
    return [f"{team_id}\t{name}\t{'free' if free else 'paid'}" for team_id, (name, free) in ordered]


def devices(path: str, wanted: str = "") -> list[str]:
    """`xcrun devicectl list devices --json-output`: result.devices, each with identifier,
    deviceProperties.name and osVersionNumber, hardwareProperties.platform, and
    connectionProperties.pairingState and tunnelState. devicectl lists every phone ever paired; one
    whose tunnelState is "unavailable" can't be reached now (no cable, and not on the network), so
    it isn't found - install.sh then says to connect it, rather than failing to install."""
    try:
        listed = json.loads(Path(path).read_text(encoding="utf-8"))["result"]["devices"]
    except (OSError, ValueError, KeyError, TypeError):
        return []
    phones = []
    for device in listed if isinstance(listed, list) else []:
        props = device.get("deviceProperties") or {}
        hardware = device.get("hardwareProperties") or {}
        connection = device.get("connectionProperties") or {}
        if hardware.get("platform") not in (None, "iOS") or hardware.get("deviceType") not in (None, "iPhone"):
            continue
        if connection.get("pairingState") not in (None, "paired"):
            continue
        if connection.get("tunnelState") == "unavailable":
            continue
        identifier = device.get("identifier") or hardware.get("udid")
        if not identifier:
            continue
        phones.append((identifier, props.get("name") or identifier, props.get("osVersionNumber") or "?"))
    phones.sort(key=lambda phone: phone[1] != wanted)
    return [f"{identifier}\t{name}\t{version}" for identifier, name, version in phones]


def expiry(path: str) -> str:
    try:
        profile = plistlib.loads(Path(path).read_bytes())
    except Exception:  # noqa: BLE001
        return ""
    end = profile.get("ExpirationDate")
    if end is None:
        return ""
    if end.tzinfo is None:          # plistlib reads dates as naive UTC
        end = end.replace(tzinfo=timezone.utc)
    return end.astimezone().strftime("%a %-d %b, %H:%M")


def setting(path: str, key: str) -> str:
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""
    for line in lines:
        line = line.split("//", 1)[0].strip()
        name, sep, value = line.partition("=")
        if sep and name.strip() == key:
            return value.strip()
    return ""


def plist(path: str, key: str) -> str:
    try:
        value = plistlib.loads(Path(path).read_bytes()).get(key)
    except Exception:  # noqa: BLE001 - nothing readable has no value
        return ""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


# What the Mac app must be signed with (the Mac app, slice 1 - notes/ios.md): the App Sandbox and the outgoing network,
# both made from build settings (ENABLE_APP_SANDBOX, ENABLE_OUTGOING_NETWORK_CONNECTIONS in Base.xcconfig), which need
# no provisioning profile - and no keychain access groups, which would.
MAC_ENTITLEMENTS = {"com.apple.security.app-sandbox": "App Sandbox",
                    "com.apple.security.network.client": "outgoing network connections"}


def entitlements(path: str) -> str:
    try:
        signed = plistlib.loads(Path(path).read_bytes())
    except Exception:  # noqa: BLE001 - nothing readable is the finding
        return "its entitlements couldn't be read (codesign -d --entitlements - --xml said nothing a plist could be read from)"
    if not isinstance(signed, dict):
        return "its entitlements aren't a dictionary"
    problems = [f"no {what} ({key})" for key, what in MAC_ENTITLEMENTS.items() if signed.get(key) is not True]
    if "keychain-access-groups" in signed or "com.apple.security.application-groups" in signed:
        problems.append("it asks for keychain access or app groups, which need a provisioning profile")
    return "; ".join(problems) or "ok"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    command, path, rest = argv[1], argv[2], argv[3:]
    if command == "ci":
        print(ci(path))
    elif command == "teams":
        print("\n".join(teams(path)))
    elif command == "devices":
        print("\n".join(devices(path, rest[0] if rest else "")))
    elif command == "expiry":
        print(expiry(path))
    elif command == "setting" and rest:
        print(setting(path, rest[0]))
    elif command == "plist" and rest:
        print(plist(path, rest[0]))
    elif command == "entitlements":
        print(entitlements(path))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
