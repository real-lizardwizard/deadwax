"""
The Mac app, slice 1 (notes/ios.md "The Mac app, slice 1: it runs and plays"): the iPhone app's own code built for the
Mac through Mac Catalyst. What the App's sources must hold for it, read as Swift reads them (tests/test_ios_no_web_app.py's
reading: comments and string literals blanked, so a word in either is never code).

  - One switch, said once (the Mac app's plan 3.3): `#if targetEnvironment(macCatalyst)` in one App file,
    App/Shared/Platform.swift, and nowhere else; never `os(macOS)` (false on Catalyst - DeadwaxAudio's two picks of the
    macOS SDK's API for the package's own `swift test` on a Mac aside), `canImport(AppKit)` or AppKit (true there, and
    unusable), nor the Mac idiom asked; and no platform condition in DeadwaxCore, which takes the device as a value.
  - Pull to refresh only on the iPhone: every `.refreshable` through Platform.swift's one helper, which is SwiftUI's own
    on the iPhone and nothing in the Mac idiom (where UIKit refuses the refresh control with an exception).
  - The sign-in: the Keychain on the iPhone exactly as before, a file on the Mac (Core's SessionFile), through one
    SessionStore - read, saved and removed where the Keychain's was, and nothing about it logged.
  - The Mac's Now Playing says paused when it is (playbackState), the Mac is "Mac" to another device as the web calls
    it, and the window and menus are the Mac's alone.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
KIT = IOS / "DeadwaxKit" / "Sources"
CORE = KIT / "DeadwaxCore"
PLATFORM = "Shared/Platform.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def app_sources() -> dict[str, str]:
    return {path.relative_to(APP).as_posix(): path.read_text(encoding="utf-8") for path in sorted(APP.rglob("*.swift"))}


def kit_sources() -> dict[str, str]:
    return {path.relative_to(IOS).as_posix(): path.read_text(encoding="utf-8") for path in sorted(KIT.rglob("*.swift"))}


# ----------------------------------------------------------------------------- one switch, said once

#? DeadwaxAudio's two: an API the macOS SDK has and the iOS SDK hasn't (or the other way), so the package builds for
#? its own `swift test` on a Mac. False on Catalyst, which builds against iOS's API - neither is a Mac decision.
OS_MACOS_ALLOWED = {
    "DeadwaxKit/Sources/DeadwaxAudio/StreamFetch.swift": 1,     # #if !os(macOS): the file protection class, iOS's
    "DeadwaxKit/Sources/DeadwaxAudio/EQUnit.swift": 1,          # #if os(macOS): .loadInProcess, macOS's alone
}
NEVER = {
    "canImport(AppKit)": re.compile(r"canImport\s*\(\s*AppKit\s*\)"),
    "import AppKit": re.compile(r"\bimport\s+AppKit\b"),
    "the Mac idiom asked": re.compile(r"userInterfaceIdiom\b[^\n]*\.mac\b|\.mac\b[^\n]*userInterfaceIdiom"),
    "isMacCatalystApp": re.compile(r"\bisMacCatalystApp\b"),
    "isiOSAppOnMac": re.compile(r"\bisiOSAppOnMac\b"),
}
CATALYST = re.compile(r"targetEnvironment\s*\(\s*macCatalyst\s*\)")
OS_MACOS = re.compile(r"\bos\s*\(\s*macOS\s*\)")


def test_one_switch_said_once_in_one_app_file():
    app = {name: bare(text) for name, text in app_sources().items()}
    kit = {name: bare(text) for name, text in kit_sources().items()}
    said = {name: len(CATALYST.findall(code)) for name, code in {**app, **kit}.items() if CATALYST.search(code)}
    assert said == {PLATFORM: 1}, f"targetEnvironment(macCatalyst) only in App/{PLATFORM}, once: {said}"
    platform = app[PLATFORM]
    assert re.search(r"^#if targetEnvironment\(macCatalyst\)$", platform, re.M)
    assert platform.count("\n#else\n") == 1 and platform.count("\n#endif\n") == 1
    assert len(re.findall(r"^\s*#if\b", platform, re.M)) == 1, "Platform.swift's one #if is the switch"
    # never another way of asking
    for name, code in {**app, **kit}.items():
        for what, pattern in NEVER.items():
            assert not pattern.search(code), f"{name}: {what} - the Mac is asked only through Platform.mac"
        found = len(OS_MACOS.findall(code))
        assert found == OS_MACOS_ALLOWED.get(name, 0), f"{name}: os(macOS) is false on Catalyst - use Platform.mac"
    # the App has no other compile condition of its own
    for name, code in app.items():
        if name != PLATFORM:
            assert not re.search(r"^\s*#if\b", code, re.M), f"{name}: an #if in the App outside Platform.swift"


def test_core_takes_the_device_as_a_value():
    for path in sorted(CORE.rglob("*.swift")):
        code = bare(path.read_text(encoding="utf-8"))
        conditions = re.findall(r"^\s*#(?:if|elseif)\b(.*)$", code, re.M)
        # DeckMaths' libc for its maths, on each platform the package builds - no rule depends on it
        allowed = {" canImport(Darwin)", " canImport(Glibc)", " canImport(Musl)"} if path.name == "DeckMaths.swift" else set()
        assert set(conditions) <= allowed, f"{path.name}: {conditions} - Core takes the device as a value (Device)"
    device = (CORE / "Device.swift").read_text(encoding="utf-8")
    assert "public enum Device: String, Sendable, CaseIterable {" in device
    assert re.findall(r"^\s*case (\w+)$", bare(device), re.M) == ["iPhone", "mac"]
    platform = app_sources()[PLATFORM]
    assert "static var device: Device { mac ? .mac : .iPhone }" in platform


def test_platform_is_the_iphones_exactly_as_before_on_the_iphone():
    """Platform.swift's iPhone side: nothing of the Mac's - SwiftUI's own pull to refresh, the scene as it was, nothing
    done at launch."""
    code = bare(app_sources()[PLATFORM])
    mac, phone = code.split("\n#else\n")
    phone = phone.split("\n#endif\n")[0]
    assert "static let mac = false" in phone and "static let mac = true" in mac
    assert re.search(r"func pullToRefresh\(_ action: @escaping @MainActor @Sendable \(\) async -> Void\) -> some View \{\s*"
                     r"refreshable\(action: action\)\s*\}", phone)
    assert re.search(r"func macWindow\(\) -> some Scene \{\s*self\s*\}", phone)
    assert re.search(r"static func launching\(\) \{\}", phone)
    # the Mac's: no refresh control at all, the window phone-shaped, New Window and Help gone
    assert re.search(r"func pullToRefresh\(_ action: @escaping @MainActor @Sendable \(\) async -> Void\) -> some View \{\s*self\s*\}", mac)
    assert "refreshable" not in mac
    assert "CommandGroup(replacing: .newItem) {}" in mac and "CommandGroup(replacing: .help) {}" in mac
    for size in ("CGSize(width: 390, height: 640)", "widest: CGFloat = 600", "CGSize(width: 430, height: 860)"):
        assert size in mac
    assert "sizeRestrictions?.minimumSize" in mac and "sizeRestrictions?.maximumSize" in mac
    assert "titlebar?.titleVisibility = .hidden" in mac


def test_the_app_is_wired_to_platform():
    app = app_sources()
    root = bare(app["DeadwaxApp.swift"])
    assert ".macWindow()" in root, "the scene's Mac window and menus"
    assert root.count("Platform.launching()") == 1
    delegate = root[root.index("final class AppDelegate"):]
    assert "Platform.launching()" in delegate, "at launch, before the first window connects"
    player = bare(app["Models/PlayerModel.swift"])
    assert "label: Resume.label(for: Platform.device)" in player
    for name, text in app.items():
        assert not re.search(r"Resume\.label\b(?!\(for:)", bare(text)), f"{name}: the label goes by the device"
    # DeckVoiceHost's one import more: CoreAudio brings UnsafeMutableAudioBufferListPointer on Catalyst
    host = (KIT / "DeadwaxAudio" / "DeckVoiceHost.swift").read_text(encoding="utf-8")
    assert re.findall(r"^import (\w+)$", host, re.M) == ["AVFAudio", "AudioToolbox", "CAudioRing", "CoreAudio", "DeadwaxCore"]


# ----------------------------------------------------------------------------- pull to refresh, the iPhone's alone

#? every page with a pull to refresh (17 pulls in 15 files): each through the one helper
PULLS = {
    "Artist/ArtistView.swift": 1, "Downloads/DownloadsScreen.swift": 1, "Edit/ChooseFolderView.swift": 1,
    "Edit/ReleasePage.swift": 1, "Library/AlbumsScreen.swift": 1, "Library/ArtistsScreen.swift": 1,
    "Library/LibraryView.swift": 1, "Library/SongsScreen.swift": 1, "Manage/HeldByNobodyScreen.swift": 1,
    "Manage/NeedsLookScreen.swift": 1, "Manage/PeopleScreen.swift": 2, "Playlists/PlaylistsScreen.swift": 1,
    "You/AccountSection.swift": 1, "You/GettingAlbumsSection.swift": 1, "You/YouView.swift": 2,
}


def test_every_pull_to_refresh_goes_through_the_one_helper():
    found = {}
    for name, text in app_sources().items():
        code = bare(text)
        if name == PLATFORM:
            assert code.count("refreshable(action: action)") == 1 and len(re.findall(r"\brefreshable\b", code)) == 1
            continue
        assert not re.search(r"\brefreshable\b", code), f"{name}: .refreshable directly - UIKit refuses it on the Mac"
        assert "UIRefreshControl" not in code, name
        count = code.count(".pullToRefresh {")
        if count:
            found[name] = count
    assert found == PULLS


# ----------------------------------------------------------------------------- the sign-in

def test_the_session_is_kept_where_the_device_keeps_it():
    app = app_sources()
    store = bare(app["SessionStore.swift"])
    # each of the three: the Mac's file, else the Keychain as before
    for call, mac, phone in (("read", "macFile?.read(server)", "SessionKeychain.read(server)"),
                             ("save", "macFile?.save(value, for: server)", "SessionKeychain.save(value, for: server)"),
                             ("delete", "macFile?.delete(server)", "SessionKeychain.delete(server)")):
        body = store[store.index(f"static func {call}("):]
        body = body[:body.index("\n    }\n")]
        assert "Platform.mac" in body and mac in body and phone in body, call
        assert body.index(mac) < body.index(phone), f"{call}: the Mac's branch first, then the iPhone's, unchanged"
    assert "SessionFile(applicationSupport: support)" in store
    assert ".applicationSupportDirectory, in: .userDomainMask" in store
    # the Keychain is reached only through the store; the model only through the store
    for name, text in app.items():
        if name not in ("SessionStore.swift", "SessionKeychain.swift"):
            assert "SessionKeychain" not in bare(text), f"{name}: the session goes through SessionStore"
    server = bare(app["Models/ServerModel.swift"])
    # where the Keychain was read, saved and cleared before - the launch and another address; a sign-in and Change
    # password; and sign-out, the one place a session is forgotten
    assert server.count("SessionStore.read(") == 2
    assert server.count("SessionStore.save(cookie, for: address.key)") == 2
    assert server.count("SessionStore.delete(") == 1
    sign_out = server[server.index("func signOut() async {"):]
    sign_out = sign_out[:sign_out.index("\n    }\n")]
    assert "SessionStore.delete(address.key)" in sign_out


LOGS = re.compile(r"\b(?:print|debugPrint|dump|NSLog|os_log|Logger|EngineTrace)\b|\.(?:info|debug|notice|error|fault|log)\(")


def test_nothing_about_the_session_is_logged():
    for path in (APP / "SessionStore.swift", APP / "SessionKeychain.swift", CORE / "SessionFile.swift"):
        assert not LOGS.search(bare(path.read_text(encoding="utf-8"))), f"{path.name} logs"
    # and no line of the App that logs mentions the session or a cookie
    for name, text in app_sources().items():
        for line in bare(text).splitlines():
            if LOGS.search(line):
                assert not re.search(r"(?i)session|cookie", line), f"{name}: {line.strip()}"


def test_the_session_file_is_made_for_this_user_alone():
    source = (CORE / "SessionFile.swift").read_text(encoding="utf-8")
    code = bare(source)
    assert "public static let permissions = 0o600" in code and "public static let folderPermissions = 0o700" in code
    save = code[code.index("public func save("):code.index("public func delete(")]
    # made 0600 while still empty, held to it, then written - and only then moved into place
    order = [save.index(step) for step in ("contents: nil", "attributes: [.posixPermissions: Self.permissions]",
                                           "Self.ensure(Self.permissions, at: temporary.path)",
                                           "handle.write(contentsOf:", "manager.moveItem(at: temporary, to: final)")]
    assert order == sorted(order)
    assert "import Foundation" in source and not re.search(r"^import (?!Foundation)", source, re.M)


# ----------------------------------------------------------------------------- Now Playing and the label

def test_the_macs_now_playing_says_whether_it_plays():
    code = bare((APP / "NowPlayingController.swift").read_text(encoding="utf-8"))
    sets = re.findall(r"^\s*(.*playbackState = [^\n]*)$", code, re.M)
    assert [line.strip() for line in sets] == [
        "if Platform.mac { MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused }",
        "if Platform.mac { MPNowPlayingInfoCenter.default().playbackState = .stopped }",
        "if Platform.mac { center.playbackState = .paused }",
    ], "on the Mac only: iOS works it out from the audio session, as before"


def test_the_mac_is_called_what_the_web_calls_it():
    web = (REPO / "ui" / "src" / "lib" / "resume.ts").read_text(encoding="utf-8")
    assert "if (/Macintosh|Mac OS X/.test(userAgent)) return 'Mac'" in web
    core = (CORE / "Resume.swift").read_text(encoding="utf-8")
    assert 'case .mac: return "Mac"' in core and "case .iPhone: return label" in core
    from src.play_queue import LABEL
    assert LABEL.match("Mac") and LABEL.match("iPhone")
