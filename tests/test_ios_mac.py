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
  - (Slice 3, notes/ios.md "The Mac app, slice 3: the desktop frame") The Mac's window is always the desktop frame - the
    sidebar, the page, the side panels and the player bar - and never opens Now Playing; only the app's own window
    scene is shaped; the iPhone's tabs exactly as they were.
  - (Slice 7, notes/ios.md "The Mac app, slice 7: managing on a big screen") File > Save changes (⌘S) is Server settings'
    own button, from its page in front; the event log's lines selected and copied with the system's Edit > Copy; Edit
    album's sheet sized by the window; Manage's pages readable; Tab between the editor's fields; Return never applying;
    a run under way saying what ⌘Q does - each the iPhone's as before.
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
    assert re.search(r"func macWindow\(_ menus: MacCommands\) -> some Scene \{\s*self\s*\}", phone)
    assert re.search(r"static func launching\(\) \{\}", phone)
    # (slice 2) every helper the Mac's alone: the view itself on the iPhone - no key, no menu, no long press added
    for helper in (r"refreshCommand\(_ action: @escaping @MainActor @Sendable \(\) async -> Void\)",
                   r"macContextMenu<Items: View>\(@ViewBuilder _ items: \(\) -> Items\)",
                   r"albumRightClick\(_ route: AlbumRoute\)", r"playlistRightClick\(_ route: PlaylistRoute\)",
                   r"escapeCloses\(_ on: @autoclosure \(\) -> Bool = true\)", r"returnCancels\(\)",
                   # (the Mac redesign, R1) Return on a redesigned dialog's one action, ← and → on the Mac's own
                   # controls
                   r"returnPresses\(\)", r"arrowKeys\(_ move: @escaping \(Int\) -> KeyPress\.Result\)",
                   # (R1's review) a launch screen's name for the window
                   r"namesWindow\(_ name: String\?\)",
                   r"findField\(_ focused: FocusState<Bool>\.Binding\)",
                   r"oneWindow\(\)", r"macSheet\(\)", r"keepsWindowOpen\(_ on: @autoclosure \(\) -> Bool\)",
                   r"readableOnMac\(\)", r"shapesWindow\(\)",
                   # (slice 6) the EQ's files: no Open panel, Save panel or drop of the Mac's on the iPhone
                   r"eqOpenPanel\(_ shown: Binding<Bool>, chosen: @escaping \(URL\) -> Void\)",
                   r"eqFileDrop\(_ dropped: @escaping \(EQImportItem\) -> Void\)",
                   r"eqSavePanel\(_ file: Binding<EQExportFile\?>\)",
                   # (slice 7) managing: no sheet size, menu page, Tab or Copy of the Mac's on the iPhone
                   r"sizedSheet\(_ size: MacFrame\.Size\)", r"macSettingsPage\(\)",
                   r"tabs<Field: Hashable>\(_ focused: FocusState<Field\?>\.Binding, in order: \[Field\]\)",
                   r"copiesSelection<ID: Hashable>\(_ selection: Binding<Set<ID>>, of ids: \[ID\],\s*"
                   r"text: @escaping \(Set<ID>\) -> String\?\)"):
        assert re.search(r"func " + helper + r" -> some View \{\s*self\s*\}", phone), helper
        assert re.search(r"func " + helper + r" -> some View \{", mac), helper
    assert re.search(r"static func dialogCancel\(\) -> some View \{\s*EmptyView\(\)\s*\}", phone)
    # (slice 3) Search's field: the navigation bar's, always drawn, exactly as SearchScreen had it - none on the Mac
    assert re.search(r"func searchField\(text: Binding<String>, prompt: String\) -> some View \{\s*"
                     r"searchable\(text: text, placement: \.navigationBarDrawer\(displayMode: \.always\), "
                     r"prompt: Text\(prompt\)\)\s*\}", phone)
    assert re.search(r"func searchField\(text: Binding<String>, prompt: String\) -> some View \{\s*self\s*\}", mac)
    assert "keyboardShortcut" not in phone and "contextMenu" not in phone and "commands" not in phone
    # (slice 7) nor a key press, a responder, the clipboard, a sheet's size or a list's selection
    for mac_only in ("onKeyPress", "UIResponder", "UIPasteboard", "canPerformAction", "becomeFirstResponder",
                     "presentationSizing", "List(selection:", "MacSettingsPage"):
        assert mac_only not in phone, mac_only
    # the Mac's: no refresh control at all - (slice 2) the same action on ⌘R - the window phone-shaped, New Window and
    # Help gone, and deadwax's menus
    assert re.search(r"func pullToRefresh\(_ action: @escaping @MainActor @Sendable \(\) async -> Void\) -> some View \{\s*"
                     r"refreshCommand\(action\)\s*\}", mac)
    assert re.search(r"func refreshCommand\([^)]*\)[^{]*\{\s*modifier\(MacRefreshing\(action: action\)\)\s*\}", mac)
    assert re.search(r"func macContextMenu<[^{]*\{\s*contextMenu\(menuItems: items\)\s*\}", mac)
    # (the review) Escape's and the window's conditions are autoclosures: read on the Mac alone, never on the iPhone
    assert re.search(r"func escapeCloses\([^{]*\{\s*keyboardShortcut\(on\(\) \? \.cancelAction : nil\)\s*\}", mac)
    assert re.search(r"func macSheet\(\) -> some View \{\s*modifier\(MacSheet\(\)\)\s*\}", mac)
    assert re.search(r"func keepsWindowOpen\([^{]*\{\s*modifier\(WindowKeptOpen\(on: on\(\)\)\)\s*\}", mac)
    assert re.search(r"func returnCancels\(\) -> some View \{\s*keyboardShortcut\(\.defaultAction\)\s*\}", mac)
    assert re.search(r"func oneWindow\(\) -> some View \{\s*handlesExternalEvents\(preferring: \[\"\*\"\], allowing: \[\"\*\"\]\)\s*\}",
                     app_sources()[PLATFORM].split("\n#else\n")[0])
    assert re.search(r"\.commands \{\s*CommandGroup\(replacing: \.newItem\) \{\}\s*CommandGroup\(replacing: \.help\) \{\}\s*menus\s*\}", mac)
    launching = mac.split("static func launching()")[1].split("\n    }\n")[0]
    for start in ("TextEditing.shared.start()", "WindowWork.shared.start()"):
        assert start in launching, start
    # (the merge of 72079a8) ⌘R's pages aren't let go as a scene comes or goes: on the Mac every sheet is a scene
    assert "MacRefresh" not in launching
    assert "refreshable" not in mac
    assert "CommandGroup(replacing: .newItem) {}" in mac and "CommandGroup(replacing: .help) {}" in mac
    # (slice 3) the desktop frame's window: as large as you like above the least that holds the sidebar, a page and
    # the bar - it was phone-shaped (390 x 640 to 600 wide, opening 430 x 860) until slice 3
    for size in ("static let smallest = CGSize(width: MacFrame.smallestWidth, height: MacFrame.smallestHeight)",
                 "static let widest = CGFloat.greatestFiniteMagnitude",
                 "static let opening = CGSize(width: MacFrame.openingWidth, height: MacFrame.openingHeight)"):
        assert size in mac, size
    assert "390" not in mac and "600" not in mac and "860" not in mac
    assert "sizeRestrictions?.minimumSize" in mac and "sizeRestrictions?.maximumSize" in mac
    assert "titlebar?.titleVisibility = .hidden" in mac
    # a presented page: its presenter's models handed on, the Mac's alone (Presenting.swift)
    assert re.search(r"func carryingApp\(_ carried: AppCarried\) -> some View \{\s*self\s*\}", phone)
    assert re.search(r"func carryingApp\(_ carried: AppCarried\) -> some View \{\s*modifier\(CarriesApp\(carried: carried\)\)\s*\}", mac)


def test_the_app_is_wired_to_platform():
    app = app_sources()
    root = bare(app["DeadwaxApp.swift"])
    assert root.count(".macWindow(MacCommands(player: player, navigation: navigation, server: server, lyrics: lyrics,\n"
                      "                                serverSettings: serverSettings, reachability: reachability))") == 1, \
        "the scene's Mac window and (slice 2) its menus - (slice 3) the lyrics' state for View > Lyrics - (slice 7) " \
        "Server settings' rule and call for File > Save changes"
    assert root.count(".oneWindow()") == 1
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


#? (slice 2) the pages whose phone pull shuffles: ⌘R is their •••'s Refresh, the very action it calls
REFRESH_COMMANDS = {"Library/LibraryView.swift": 1, "Album/AlbumView.swift": 1, "Playlists/PlaylistView.swift": 1}


def test_command_r_is_every_pull_and_every_pages_refresh():
    """⌘R (the Mac app's plan 1.3): wherever the phone has a pull to refresh - through the very helper, so no page can
    have one without the other - and the three pages whose pull shuffles, their •••'s own Refresh."""
    found = {}
    for name, text in app_sources().items():
        if name == PLATFORM:
            continue
        code = bare(text)
        count = code.count(".refreshCommand { refresh() }")
        assert count == code.count(".refreshCommand"), f"{name}: ⌘R is the page's own refresh()"
        if count:
            found[name] = count
            # the same action the •••'s Refresh calls
            assert "request.refresh = { refresh() }" in code or "Button(action: refresh)" in code, name
    assert found == REFRESH_COMMANDS
    commands = bare(app_sources()["Shared/MacCommands.swift"])
    # the page shown is the one that last appeared and hasn't gone; one at a time
    assert commands.count(".onAppear { MacRefresh.shared.appeared(page) }") == 3, \
        "a page with a Refresh, a sheet's root - (slice 7) a page of Server settings"
    assert commands.count(".onDisappear { MacRefresh.shared.went(page) }") == 3
    run = commands[commands.index("func run() {"):]
    run = run[:run.index("\n    }\n")]
    assert "guard !running, let page = front, page.action != nil else { return }" in run
    assert run.index("running = true") < run.index("await page.action?()") < run.index("running = false")
    # (the review) the page in front is the latest page as many sheets deep as the deepest thing showing: a sheet with no
    # Refresh dims it; a page inside a sheet that has one is the page in front
    #? (slice 7) Server settings' pages are ⌘S's, never ⌘R's: Refresh is as it was on them
    front = _body(commands, "private var front: Page? {")
    assert "return pages.last { (page: Page) -> Bool in !page.sheet && !page.settings && page.level == deepest }" in front
    assert "var sheetUp: Bool { deepest > 0 }" in commands
    refreshing = commands[commands.index("struct MacRefreshing: ViewModifier {"):commands.index("struct MacSheet: ViewModifier {")]
    assert "@Environment(\\.macSheetLevel) private var level" in refreshing and "page.level = level" in refreshing
    sheet = commands[commands.index("struct MacSheet: ViewModifier {"):commands.index("struct MacSettingsPage: ViewModifier {")]
    for line in ("page.sheet = true", "page.level = level + 1", ".environment(\\.macSheetLevel, level + 1)"):
        assert line in sheet, line
    # (the review, then the merge of 72079a8) a page that never said it went - its window closed under it - is let go
    # with its view: each page its view's @State, held here weakly, and let go as it goes. Not as a scene comes or goes:
    # on the Mac every sheet is a scene of its own, and that would forget the pages under it
    refresh = commands[commands.index("final class MacRefresh"):commands.index("private struct MacSheetLevel")]
    assert "private var shown: [Shown] = []" in refresh and "weak var page: Page?" in refresh
    assert "private var pages: [Page] { shown.compactMap { (each: Shown) -> Page? in each.page } }" in refresh
    assert "shown.last" not in refresh and "shown.map" not in refresh, "only the pages still there count"
    assert "deinit {\n            if listed { Task { @MainActor in MacRefresh.shared.letGo() } }" in refresh
    assert "UIScene" not in refresh and "forgetAll" not in commands and "func start()" not in refresh
    appeared = refresh[refresh.index("func appeared(_ page: Page) {"):refresh.index("func went(")]
    assert "page.listed = true" in appeared
    went = refresh[refresh.index("func went(_ page: Page) {"):refresh.index("func letGo()")]
    assert "page.listed = false" in went
    for name in ("MacRefreshing", "MacSheet", "MacSettingsPage"):
        modifier = commands[commands.index(f"struct {name}: ViewModifier {{"):]
        assert "@State private var page = MacRefresh.Page()" in modifier[:modifier.index("func body")], name


# ----------------------------------------------------------------------------- the menus and keys (slice 2)

def test_the_menus_are_mac_menus_and_nothing_else():
    """MacCommands draws Core's MacMenu and nothing of its own: every item's words, key, dimming and tick MacMenu's, and
    every click the player's own call - the one its button makes."""
    code = bare(app_sources()["Shared/MacCommands.swift"])
    commands = code[code.index("struct MacCommands: Commands {"):code.index("final class TextEditing")]
    # no words of its own: no string literal in the menus at all (a literal reads "" once its contents are blanked)
    assert '"' not in commands, "a string literal in the menus: their words are MacMenu's"
    assert re.findall(r"\b(Button|Toggle|Menu|CommandMenu)\(([^,){]*)", commands) == [
        ("CommandMenu", "MacMenu.Words.controls"), ("Menu", "MacMenu.Words.repeatMenu"),
        ("Button", "item.words"), ("Toggle", "item.words"),
    ]
    assert commands.count(".keyboardShortcut(Self.shortcut(item.shortcut))") == 2
    assert commands.count(".keyboardShortcut(") == 2 and commands.count(".disabled(!item.enabled)") == 2
    assert "Binding(get: { item.ticked }" in commands
    # the system's menus kept but New Window, Help and Format; Settings…, Find, Refresh in their places; Controls
    for group in ("CommandGroup(replacing: .appSettings) {\n            item(.settings, state)",
                  "CommandGroup(replacing: .textEditing) {\n            item(.find, state)",
                  "CommandGroup(replacing: .textFormatting) {}",
                  "CommandGroup(after: .toolbar) {\n            item(.refresh, state)",
                  "CommandGroup(after: .newItem) {\n            item(.importEQFile, state)\n            Divider()\n"
                  "            item(.saveChanges, state)\n        }",
                  "CommandGroup(replacing: .sidebar) {\n            let sections = MacMenu.view(state)"):
        assert group in commands, group
    #? (slice 3's review, smoke-run) the sidebar place replaced, never added beside: the system's Show Sidebar kept has
    #? ⌃⌘S too, and UIKit throws at launch over the two. View's Enter Full Screen is a place of its own, still there
    assert "after: .sidebar" not in commands and "before: .sidebar" not in commands
    assert "replacing: .windowSize" not in commands and "replacing: .toolbar" not in commands
    # (slice 3) View's frame: Show/Hide Sidebar a button, each panel a tick
    frame = commands[commands.index("private func frameItems("):commands.index("private func item(")]
    assert "if each.command.panel != nil {\n                tick(each)\n            } else {\n                button(each)" in frame
    # the state each time it's drawn, from the player and the window
    state = commands[commands.index("private var state: MacMenu.State {"):commands.index("var body: some Commands {")]
    for read in ("queued: player.hasQueue", "playing: player.isPlaying", "shuffle: player.shuffle",
                 "paged: player.paged?.scope", "repeatMode: player.repeatMode", "length: player.duration",
                 "PlayedAlbum.route($0, player: player)", "typing: TextEditing.shared.typing",
                 "tabs: server.launch == .ready && server.signInOver == nil", "refresh: MacRefresh.shared.state",
                 "nowPlaying: navigation.nowPlayingShown", "sheet: MacRefresh.shared.sheetUp",
                 "sidebarShown: navigation.macSidebarShown", "panel: navigation.macPanel", "lyrics: lyrics.have",
                 # (slice 7) Server settings' page in front, and its button's own rule
                 "serverSettings: MacRefresh.shared.settingsInFront",
                 "saveOpen: serverSettings.saveOpen(online: reachability.online)"):
        assert read in state, read
    # each click as the player's button makes it, read again as it lands
    perform = commands[commands.index("private func perform("):commands.index("static func shortcut(")]
    assert "let now = MacMenu.item(command, state)\n        guard now.enabled else { return }" in perform
    for call in ("navigation.showSettings()", "navigation.find()", "MacRefresh.shared.run()", "player.toggle()",
                 "player.next()", "player.previous()",
                 "MacMenu.skip(command, from: player.shownPosition, length: player.duration) { player.seek(to: to) }",
                 "player.toggleShuffle()", "player.setRepeat(mode)", "navigation.openAlbum(route)",
                 "navigation.macSidebarShown.toggle()", "if let panel = command.panel { navigation.togglePanel(panel) }",
                 "case .saveChanges:\n            serverSettings.save()"):
        assert call in perform, call
    # no volume of deadwax's own (audio fidelity first), and nothing of the engine's
    assert not re.search(r"(?i)volume|gain", code)
    # every MacMenu command is drawn once
    core = (CORE / "MacMenu.swift").read_text(encoding="utf-8")
    cases = re.findall(r"^\s*case ([a-z][\w, ]*)$", bare(core[core.index("public enum Command"):core.index("public static let repeats")]), re.M)
    every = [name.strip() for line in cases for name in line.split(",")]
    assert every == ["settings", "find", "refresh", "playPause", "next", "previous", "forward", "back", "shuffle",
                     "repeatOff", "repeatAll", "repeatOne", "goToCurrentSong", "sidebar", "upNext", "lyrics", "info",
                     #? (R3) View > EQ (⌥⌘E), the side panel's EQ tab
                     "eq", "importEQFile", "saveChanges"]
    for name in every:
        assert f"case .{name}" in perform or f".{name}," in perform or f", .{name}" in perform, name


def test_a_text_field_keeps_its_keys():
    code = bare(app_sources()["Shared/MacCommands.swift"])
    editing = code[code.index("final class TextEditing"):code.index("final class MacRefresh")]
    for notice in ("UITextField.textDidBeginEditingNotification", "UITextField.textDidEndEditingNotification",
                   "UITextView.textDidBeginEditingNotification", "UITextView.textDidEndEditingNotification"):
        assert notice in editing, notice
    assert "NSHashTable<AnyObject>.weakObjects()" in editing and "isFirstResponder == true" in editing
    assert "if typing != now { typing = now }" in editing
    # (the review) and again each time the window comes to the front, so the keys can't stay off
    assert "forName: UIScene.didActivateNotification" in editing
    assert "TextEditing.shared.changed(nil, began: false)" in editing


def test_find_puts_the_cursor_in_the_sidebars_field():
    """(Slice 3) Search's field on the Mac is the desktop frame's sidebar's: Find shows the sidebar and puts the cursor
    there, the page left as it is. Search's page draws its navigation-bar field on the iPhone alone (Platform's
    searchField), and the iPhone's Find path is the slice-2 one, never reached there."""
    app = app_sources()
    search = bare(app["Search/SearchScreen.swift"])
    assert ".findField(" not in search and ".searchable(" not in search
    assert search.index(".searchField(text: Binding(get: { search.text }, set: { (typed: String) -> Void in search.type(typed) }),") \
        < search.index(".onSubmit(of: .search) { search.submitted() }")
    sidebar = bare(app["Root/MacSidebarView.swift"])
    assert sidebar.count(".findField($focused)") == 1
    field = sidebar[sidebar.index("private struct SidebarSearchField"):]
    assert field.index("TextField(MacSidebar.Words.searchPlaceholder") < field.index(".findField($focused)")
    assert "@FocusState private var focused: Bool" in field and ".escapeCloses(focused)" in field
    assert "search.type(typed)" in field and "navigation.showSearch()" in field and "search.submitted()" in field
    assert sum(bare(text).count(".findField(") for name, text in app.items() if name != PLATFORM) == 1
    routes = bare(app["Shared/Routes.swift"])
    find = routes[routes.index("func find() {"):]
    find = find[:find.index("\n    }\n")]
    assert "if MacFrame.drawsDesktop(Platform.device) {\n            macSidebarShown = true\n        } else {" in find
    assert "nowPlayingShown = false" in find and "tab = .search" in find and "backToRoot(&search)" in find
    assert find.index("macSidebarShown = true") < find.index("tab = .search")
    assert "findWanted = true" in find
    show = routes[routes.index("func showSearch() {"):]
    show = show[:show.index("\n    }\n")]
    assert "tab = .search" in show and "if !search.isEmpty { backToRoot(&search) }" in show
    settings = routes[routes.index("func showSettings() {"):]
    settings = settings[:settings.index("\n    }\n")]
    assert "tab = .you" in settings and "nowPlayingShown = false" in settings
    reset = routes[routes.index("func reset() {"):]
    reset = reset[:reset.index("\n    }\n")]
    assert "findWanted = false" in reset and "macLibraryPage = nil" in reset
    focus = bare(app["Shared/MacCommands.swift"])
    focus = focus[focus.index("struct FindFocus: ViewModifier"):]
    assert "content\n            .focused(focused)" in focus and "searchFocused" not in focus and "#available" not in focus
    assert "focused.wrappedValue = true" in focus
    assert "navigation.findTaken()" in focus


def test_the_window_comes_back_on_the_page_it_showed():
    library = bare(app_sources()["Library/LibraryView.swift"])
    assert "if page == nil { show(navigation.macLibraryPage ?? LibraryPages.first(shownOrder)) }" in library
    assert "if Platform.mac { navigation.macLibraryPage = now }" in library
    # (slice 3) a sidebar row's page shown - written only on the Mac, so never on the iPhone
    assert ".onChange(of: navigation.macLibraryPage) { (_: LibraryPage?, asked: LibraryPage?) -> Void in" in library
    assert "if let asked, asked != page { show(LibraryPages.showing(asked, in: shownOrder)) }" in library
    assert library.count("macLibraryPage") == 3, "written only on the Mac: nil on the iPhone, the first page as before"


# ----------------------------------------------------------------------------- right-click (slice 2)

#? a song's row: its own •••'s request, on a right-click
SONG_ROWS = {"Album/TrackRow.swift": 1, "Library/SongsScreen.swift": 1, "Playlists/PlaylistView.swift": 1,
             "Search/SearchScreen.swift": 1, "Artist/TopSongsSection.swift": 1}
#? an album's tile or row: the album page's •••; a playlist's row: its page's
ALBUM_TILES = {"Library/LibraryTiles.swift": 2, "Search/SearchScreen.swift": 1, "Artist/ArtistView.swift": 1}
PLAYLIST_ROWS = {"Playlists/PlaylistsScreen.swift": 1}
#? the phone's own long presses, from before: the EQ's Back to AutoEq and the event log's Copy - a right-click there too
PHONE_LONG_PRESSES = {"EQ/EQScreen.swift": 1, "Manage/EventLogScreen.swift": 1}


def test_a_right_click_is_the_menus_own_items():
    """Built from the ••• menus' own items (QueueMenuItems), never a second list: the ••• draws them, and so does every
    right-click - a song row's from its own request, a tile's from the request its album page's ••• is built by."""
    app = app_sources()
    menu = bare(app["Player/QueueMenu.swift"])
    queue = menu[menu.index("struct QueueMenu<Label: View>: View {"):menu.index("struct QueueMenuItems: View {")]
    assert "QueueMenuItems(request: request)" in queue and "Button(" not in queue, "the ••• draws the items, and only them"
    items = menu[menu.index("struct QueueMenuItems: View {"):]
    assert "Button(AddToQueue.words, systemImage: AddToQueue.symbol)" in items
    # no context menu but these, each with the items - and the phone's own two long presses, exactly as they were
    for name, text in app.items():
        code = bare(text)
        if name == PLATFORM:
            assert code.count("contextMenu(") == 1
        elif name == "Shared/MacRightClick.swift":
            assert code.count(".contextMenu {") == 2 and code.count("QueueMenuItems(request: request)") == 2
        else:
            assert code.count("contextMenu") == PHONE_LONG_PRESSES.get(name, 0), \
                f"{name}: a right-click only through Platform's helpers"
    found = {}
    for name, text in app.items():
        if name == PLATFORM:
            continue
        code = bare(text)
        uses = re.findall(r"\.macContextMenu \{ ([^}]*) \}", code)
        assert len(uses) == code.count(".macContextMenu"), name
        if uses:
            found[name] = len(uses)
            for use in uses:
                assert re.fullmatch(r"QueueMenuItems\(request: menu(\(song\))?\)", use), f"{name}: {use}"
    assert found == SONG_ROWS
    tiles = {name: bare(text).count(".albumRightClick(") for name, text in app.items() if name != PLATFORM}
    assert {name: n for name, n in tiles.items() if n} == ALBUM_TILES
    rows = {name: bare(text).count(".playlistRightClick(") for name, text in app.items() if name != PLATFORM}
    assert {name: n for name, n in rows.items() if n} == PLAYLIST_ROWS
    # the album's and the playlist's ••• are built in one place, for the page's bar and the right-click alike
    album = bare(app["Album/AlbumView.swift"])
    assert "QueueMenuRequest.album(album, gone: model.goneButHere" in album
    playlist = bare(app["Playlists/PlaylistView.swift"])
    assert "QueueMenuRequest.playlist(model.answer, name: model.name, songs: model.songs)" in playlist
    clicks = bare(app["Shared/MacRightClick.swift"])
    # (the review) the album page's gone-but-here carried, never a fixed false
    assert "QueueMenuRequest.album(album, gone: gone," in clicks and "gone: false," not in clicks.split("func request(")[1][:200]
    assert "downloads.keptAlbum(had.id) != nil, downloads.here(had.song ?? []).count > 0" in clicks
    # (the review) asked again at every rest, the answer in hand kept for what it was asked for alone: who, the album's id
    # now (an apply's new one), its writes - a playlist's changes here
    assert "let id = navigation.albumId(route.id)" in clicks
    assert "Stamp(person: server.person, id: id, writes: navigation.albumWrites[id] ?? 0)" in clicks
    assert "Stamp(person: server.person, id: route.id, writes: changes)" in clicks
    assert ".onChange(of: playlists.lastChange)" in clicks and "if change?.id == route.id { changes += 1 }" in clicks
    assert clicks.count(".task(id: Asking(over: over, stamp: stamp)) {") == 2
    assert clicks.count("guard over, !asking else { return }") == 2, "every rest asks again, not only the first"
    assert clicks.count("guard person == server.person, stamp == asked") == 4
    assert clicks.count("let shown = answered == stamp ? ") == 2
    # (the review) Loading whenever an answer can come - not only once the rest is over
    assert clicks.count("} else if shown == nil, !nothing, reachability.online, server.client != nil {") == 2
    assert "asking {" not in clicks.replace("!asking {", "")
    assert "QueueMenuRequest.playlist(shown, name: shown.playlist.name, songs: shown.songs)" in clicks
    assert "navigation.editingPlaylist != route.id" in clicks
    # the page's Refresh stays the page's: a right-click never offers it
    assert "refresh" not in clicks.replace("Refresh", "")


# ----------------------------------------------------------------------------- Escape and Return (slice 2)

#? every sheet's Close, Cancel or Done, Now Playing's chevron, the covers' Close - and playlist Edit's Cancel
ESCAPES = {
    "Album/AlbumInfoView.swift": 1, "Artist/ArtistImagesSheet.swift": 1, "Artist/ArtistMoveSheet.swift": 3,
    "EQ/EQImport.swift": 2, "EQ/EQRoute.swift": 1, "Edit/EditAlbumSheet.swift": 1, "Edit/ReleasePage.swift": 1,
    "Get/ManualSearchSheet.swift": 1, "Get/SourcesSheet.swift": 1, "Info/InfoView.swift": 1, "Library/LibraryView.swift": 1,
    "Manage/PeopleSheets.swift": 3, "Manage/ServerSettingsGroupScreen.swift": 1, "Player/CoverViewer.swift": 1,
    "Player/MacPanels.swift": 1, "Root/MacSidebarView.swift": 1,
    "Player/NowPlayingView.swift": 1, "Playlists/PlaylistPicker.swift": 2, "Playlists/PlaylistView.swift": 1,
    "Search/PressingPickerSheet.swift": 1, "UpNext/UpNextScreen.swift": 1,
}


#? (the review) Escape where a Close or Cancel throws typed words away without asking: only with nothing typed
GUARDED_ESCAPES = {
    "Manage/PeopleSheets.swift": ["flow.add.password.isEmpty && flow.add.again.isEmpty)",
                                  "flow.resetPasswords.password.isEmpty && flow.resetPasswords.again.isEmpty)"],
    "Artist/ArtistMoveSheet.swift": ["model.map { (model: ArtistWhoModel) -> Bool in model.query == name } ?? true)"],
    "Artist/ArtistImagesSheet.swift": ["model.map { (model: ArtistImagesModel) -> Bool in"],
    "Get/SourcesSheet.swift": ["!model.edited)"],
    #? (manual search, slice A1) Search Soulseek's Cancel throws the typed artist and album away
    "Get/ManualSearchSheet.swift": ["artist.isEmpty && album.isEmpty)"],
    "Playlists/PlaylistPicker.swift": ["!(model.making && nameTyped))", "escapes && blank)"],
    #? (slice 3, and its review) the main window's Escape has one owner, MacFrame.escape's: a field with the cursor (the
    #? sidebar's search, a page's), then the side panel's Done, then the page's - a playlist's Edit, its Cancel
    "UpNext/UpNextScreen.swift": ["MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)"],
    "Info/InfoView.swift": ["MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)"],
    "Player/MacPanels.swift": ["MacFrame.escape(typing: TextEditing.shared.typing,"],
    "Playlists/PlaylistView.swift": ["MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .page)"],
    #? the sidebar's clear button: Escape empties the field only while it has the cursor
    "Root/MacSidebarView.swift": ["focused)"],
}


def test_escape_presses_close_and_return_never_confirms():
    app = app_sources()
    found = {}
    for name, text in app.items():
        if name == PLATFORM:
            continue
        code = bare(text)
        # no key of its own anywhere: Escape and Return only through Platform's helpers, the menus only MacCommands'
        if name != "Shared/MacCommands.swift":
            assert "keyboardShortcut" not in code, f"{name}: a key only through Platform's helpers"
        count = code.count(".escapeCloses(")
        if count:
            found[name] = count
        # every toolbar Cancel or Close has Escape (Up Next's is Edit: its Done has it)
        if name != "UpNext/UpNextScreen.swift":
            assert code.count("placement: .cancellationAction") <= count, f"{name}: a sheet's Close without Escape"
        # every dialog's Cancel is pressed by Return - a dialog the system draws a Cancel for gets one on the Mac
        dialogs = code.count(".confirmationDialog(")
        assert dialogs == code.count(".returnCancels()") + code.count("Platform.dialogCancel()"), name
        for at in [m.end() for m in re.finditer(r"\.returnCancels\(\)", code)]:
            line = code[:at].rsplit("\n", 2)[-2]
            assert "role: .cancel)" in line, f"{name}: Return presses a dialog's Cancel only: {line.strip()}"
    assert found == ESCAPES
    # the playlist picker's form inside it: Escape is the picker's own Cancel there, the form's only on its own sheet
    picker = bare(app["Playlists/PlaylistPicker.swift"])
    assert ".escapeCloses(escapes && blank)" in picker and "var escapes = false" in picker
    assert "NewPlaylistFields(escapes: true)" in bare(app["Playlists/PlaylistsScreen.swift"])
    # Escape on Edit album's Close and Artist images' Close: the button itself, before the question it asks
    for name in ("Edit/EditAlbumSheet.swift", "Artist/ArtistImagesSheet.swift"):
        code = bare(app[name])
        assert code.index(".escapeCloses(") < code.index(".confirmationDialog(EditWords.discardTitle")
    platform = bare(app[PLATFORM]).split("\n#else\n")[0]
    assert re.search(r"static func dialogCancel\(\) -> some View \{\s*Button\(QueuePickWords\.cancel, role: \.cancel\) \{\}"
                     r"\s*\.returnCancels\(\)\s*\}", platform), "the app's own Cancel, never retyped"
    # (the review) where Close or Cancel throws typed words away without asking, Escape waits for nothing typed
    for name, guards in GUARDED_ESCAPES.items():
        found = re.findall(r"\.escapeCloses\(([^\n]*)", bare(app[name]))
        for guard in guards:
            assert any(each.startswith(guard) for each in found), f"{name}: {guard}"
    # (slice 3's review) the main window's owners, each through the one rule - the only Escapes not inside a sheet
    rule = "MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == "
    for name, owner in (("UpNext/UpNextScreen.swift", ".panel"), ("Info/InfoView.swift", ".panel"),
                        ("Player/MacPanels.swift", ".panel"), ("Playlists/PlaylistView.swift", ".page")):
        flat = re.sub(r"\s+", " ", bare(app[name]))
        assert flat.count(".escapeCloses(" + rule + owner + ")") == 1, name
    picker = bare(app["Playlists/PlaylistPicker.swift"])
    assert "typed: Platform.mac ? $nameTyped : nil" in picker, "the iPhone's picker told nothing"
    assert ".onChange(of: blank, initial: true) { (_: Bool, now: Bool) -> Void in typed?.wrappedValue = !now }" in picker
    assert "var edited: Bool { !Sources.queryOverride(query, shownQuery).isEmpty }" in bare(app["Models/SourcesSearch.swift"])


# ----------------------------------------------------------------------------- the sign-in

def test_the_session_is_kept_where_the_device_keeps_it():
    app = app_sources()
    store = bare(app["SessionStore.swift"])
    # each of the three: the Mac's file, else the Keychain as before
    for call, mac, phone in (("read", "macFile?.read(server)", "SessionKeychain.read(server)"),
                             ("save", "macFile.save(value, for: server)", "SessionKeychain.save(value, for: server)"),
                             ("delete", "macFile?.delete(server)", "SessionKeychain.delete(server)")):
        body = store[store.index(f"static func {call}("):]
        body = body[:body.index("\n    }\n")]
        assert "Platform.mac" in body and mac in body and phone in body, call
        assert body.index(mac) < body.index(phone), f"{call}: the Mac's branch first, then the iPhone's, unchanged"
    assert "SessionFile(applicationSupport: support)" in store
    # (review) the sessions folder out of Time Machine, after every save - the phone's Keychain item is ThisDeviceOnly
    save = store[store.index("static func save("):]
    save = save[:save.index("\n    }\n")]
    assert save.index("macFile.save(value, for: server)") < save.index("keptOutOfBackups(macFile.folder)")
    kept = store[store.index("private static func keptOutOfBackups("):]
    kept = kept[:kept.index("\n    }\n")]
    assert "values.isExcludedFromBackup = true" in kept and "folder.setResourceValues(values)" in kept
    keychain = bare(app["SessionKeychain.swift"])
    assert "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in keychain, "what the Mac's folder matches"
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
    # an empty server first: its file would be the folder itself
    assert save.index("guard !server.isEmpty else { return false }") < save.index("let manager")
    # made 0600 while still empty, held to it, then written - and only then put in place
    order = [save.index(step) for step in ("contents: nil", "attributes: [.posixPermissions: Self.permissions]",
                                           "Self.ensure(Self.permissions, at: temporary.path)",
                                           "handle.write(contentsOf:", "Self.place(temporary, at: final)")]
    assert order == sorted(order)
    # (review) put in place in one step over an old file, with the new file's own metadata (its 0600); a link or a
    # folder of the name taken away, never written through; and what's in place checked regular and 0600
    place = code[code.index("static func place("):code.index("static func ensure(")]
    assert ("manager.replaceItemAt(final, withItemAt: temporary, backupItemName: nil,\n"
            "                                              options: .usingNewMetadataOnly)") in place
    assert place.index("if let existing, isRegular(existing) {") < place.index("replaceItemAt(")
    assert place.index("try manager.removeItem(at: final)") > place.index("} else {")
    assert "ensure(permissions, at: final.path)" in place
    assert "removeItem(at: final)" not in save, "never removed and then moved: there'd be a moment with no file"
    # read and delete refuse an empty server too
    for call in ("public func read(", "public func delete("):
        body = code[code.index(call):]
        assert body.index("guard !server.isEmpty else { return") < body.index("let manager"), call
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


# ----------------------------------------------------------------------------- a sheet up, the window kept (the review)

#? every sheet's root, and each full-screen cover's - but Now Playing's, whose Find and Settings… close it
SHEET_ROOTS = {
    "Album/AlbumView.swift": 1, "Artist/ArtistView.swift": 1, "EQ/EQImport.swift": 1, "EQ/EQRoute.swift": 1,
    "Edit/ArtworkLyricsPages.swift": 1, "Edit/ReleasePage.swift": 1, "Edit/TagsPages.swift": 1,
    "Library/LibraryView.swift": 2, "Manage/PeopleScreen.swift": 3, "Player/CoverViewer.swift": 1,
    #? (R3) Now Playing's one sheet (its Queue, Info and EQ) and Add to a playlist - its three sheets were one each
    "Player/NowPlayingView.swift": 2, "Playlists/PlaylistsScreen.swift": 1, "Root/MainTabs.swift": 3,
    "Search/GroupView.swift": 2, "Shared/MacRightClick.swift": 1,
    #? (manual search, slice A1) Search Soulseek, from Requests' first row
    "Requests/RequestsScreen.swift": 1,
    #? (slice 3) the desktop frame's: MainTabs' three over the frame - (its review) the EQ the bar's too, never a second.
    #? (R3's review) Two: the EQ is the dock's EQ tab now, a shared file's preview over it (MacPanels' one)
    "Root/DesktopFrame.swift": 2, "Player/MacPanels.swift": 1,
}


def test_a_sheet_keeps_the_page_under_it_out_of_the_menus_reach():
    """A sheet never makes the page under it disappear: each sheet's root says it's up (`.macSheet()`), so ⌘R, Find,
    Settings… and Go to Current Song don't act on the page beneath (MacMenu's `sheet`)."""
    found = {}
    for name, text in app_sources().items():
        if name in (PLATFORM, PRESENTING):
            continue
        code = bare(text)
        # (the merge of 72079a8) every presentation is appSheet / appCover - the test below holds that
        sheets = len(re.findall(r"\bapp(?:Sheet|Cover)\((?:isPresented|item):", code))
        roots = code.count(".macSheet()")
        if roots:
            found[name] = roots
        # every presentation has its root marked (Now Playing's cover aside)
        assert sheets - (1 if name == "Root/MainTabs.swift" else 0) <= roots, f"{name}: a sheet without .macSheet()"
    assert found == SHEET_ROOTS
    tabs = bare(app_sources()["Root/MainTabs.swift"])
    cover = tabs[tabs.index(".appCover(isPresented: $navigation.nowPlayingShown) {"):]
    assert cover[:cover.index("}")].split("{", 1)[1].strip() == "NowPlayingView()", "Now Playing is no sheet"
    viewer = bare(app_sources()["Player/CoverViewer.swift"])
    viewer = viewer[viewer.index("appCover(item: viewing, onDismiss: onDismiss) {"):]
    assert viewer[:viewer.index("\n        }\n")].rstrip().endswith(".macSheet()"), "the cover viewer's root"


def test_the_window_is_kept_open_over_work_a_close_would_lose():
    app = app_sources()
    uses = {name: re.findall(r"\.keepsWindowOpen\(([^\n]*)\)\n", bare(text)) for name, text in app.items() if name != PLATFORM}
    assert {name: found for name, found in uses.items() if found} == {
        "Edit/EditAlbumSheet.swift": ["model?.holdsWork == true"],
        "Playlists/PlaylistView.swift": ["model.editing && model.changed"],
    }
    commands = bare(app["Shared/MacCommands.swift"])
    work = commands[commands.index("final class WindowWork"):commands.index("struct WindowKeptOpen")]
    assert "NSHashTable<Holder>.weakObjects()" in work, "a hold goes with its view"
    assert "deinit {\n            Task { @MainActor in WindowWork.shared.apply() }" in work
    # (the merge of 72079a8) only the windows shut here are opened again: a sheet's own scene, on the Mac, is never made
    # closable by this
    assert "let holding = holders.allObjects.contains { (holder: Holder) -> Bool in holder.on }" in work
    assert "guard let behaviors = scene.windowingBehaviors, behaviors.isClosable else { continue }" in work
    assert work.index("behaviors.isClosable = false") < work.index("shut.add(scene)")
    assert "for scene in shut.allObjects {\n                scene.windowingBehaviors?.isClosable = true" in work
    assert work.count("isClosable = true") == 1 and "shut.removeAllObjects()" in work
    kept = commands[commands.index("struct WindowKeptOpen"):]
    assert ".onAppear { WindowWork.shared.hold(holder, on) }" in kept
    assert ".onChange(of: on) { (_: Bool, now: Bool) -> Void in WindowWork.shared.hold(holder, now) }" in kept


def test_the_mac_has_no_turntable():
    """James's direction for the Mac: no turntable - Now Playing is the cover, with no look button, and Settings >
    Playback hasn't the turntable's two rows. The iPhone exactly as before (Platform.mac is false there)."""
    app = app_sources()
    now = bare(app["Player/NowPlayingView.swift"])
    assert "private var look: TurntableSettings.Look { Platform.mac ? .cover : switched ?? deck.opensAs }" in now
    assert re.search(r"if !Platform\.mac \{\s*LookButton\(showingTurntable: look == \.turntable, action: lookTapped\)\s*\}", now)
    assert now.count("LookButton(") == 1
    playback = bare(app["You/PlaybackSection.swift"])
    block = playback[playback.index("if !Platform.mac {"):playback.index("Picker(Normalization.title")]
    assert "Picker(TurntableWords.opensAs" in block and "Toggle(TurntableWords.windDown" in block
    assert playback.count("TurntableWords.opensAs") == 1 and playback.count("TurntableWords.windDown,") == 1


# ----------------------------------------------------------------------------- every presentation carries the app's models

PRESENTING = "Shared/Presenting.swift"
PRESENTS = re.compile(r"\b(sheet|fullScreenCover|popover|inspector)\s*\(")


def test_every_sheet_and_cover_goes_through_the_carrying_wrappers():
    """On the Mac a presented page starts with an empty environment, and its first @Environment(PlayerModel.self) is a
    crash (17 Nov: opening Now Playing on James's Mac). appSheet and appCover hand the presenter's models on; SwiftUI's
    own are called only inside them, so a sheet added later can't miss it."""
    used = 0
    for name, text in app_sources().items():
        code = bare(text)
        if name == PRESENTING:
            assert [m.group(1) for m in PRESENTS.finditer(code)] == ["sheet", "fullScreenCover", "sheet", "fullScreenCover"]
            assert code.count(".carryingApp(carried)") == 4
            continue
        found = [m.group(0) for m in PRESENTS.finditer(code)]
        assert not found, f"{name}: {found} - present through appSheet / appCover (Shared/Presenting.swift)"
        used += len(re.findall(r"\bapp(?:Sheet|Cover)\((?:isPresented|item):", code))
    assert used >= 23, used


def test_the_carried_models_are_every_model_the_root_shares():
    """A model DeadwaxApp shares but AppModels leaves out would be missing from every sheet on the Mac alone."""
    app = app_sources()
    root = bare(app["DeadwaxApp.swift"])
    group = root[root.index("WindowGroup {"):root.index(".backgroundTask(")]
    shared = re.findall(r"\.environment\((\w+)\)", group)
    assert len(shared) == 23 and len(set(shared)) == 23, shared
    presenting = bare(app[PRESENTING])
    models = presenting[presenting.index("struct AppModels {"):presenting.index("extension EnvironmentValues")]
    fields = re.findall(r"^\s*let (\w+): \w+$", models, re.M)
    assert fields == shared, "AppModels' fields are DeadwaxApp's .environment(...) models, in its order"
    made = group[group.index("AppModels("):]
    assert re.findall(r"(\w+): (\w+)", made[:made.index("))")]) == [(name, name) for name in shared]
    carries = presenting[presenting.index("struct CarriesApp"):presenting.index("private enum PresentationKind")]
    assert re.findall(r"\.environment\(m\.(\w+)\)", carries) == shared
    for value in (".environment(\\.appModels, m)", ".environment(\\.tabBarRoom, carried.tabBarRoom)",
                  ".environment(\\.playerClearance, carried.playerClearance)",
                  ".environment(\\.macSheetLevel, carried.sheetLevel)", ".tint(Palette.accent)", ".font(Typeface.body)"):
        assert value in carries, value
    # (Mac slice 2) every value the presenter reads is put back, in AppCarried's order: the two layout values and how
    # many sheets deep it is (MacSheet counts one on from it - not carried, a sheet over a sheet would be no deeper)
    carried = presenting[presenting.index("struct AppCarried {"):presenting.index("struct CarriesApp")]
    assert re.findall(r"^\s*let (\w+): ", carried, re.M) == ["models", "tabBarRoom", "playerClearance", "sheetLevel"]
    assert re.findall(r"\.environment\(\\\.(\w+), carried\.(\w+)\)", carries) == [
        ("tabBarRoom", "tabBarRoom"), ("playerClearance", "playerClearance"), ("macSheetLevel", "sheetLevel")]
    for kind in ("private struct CarriedPresentation", "private struct CarriedItemPresentation"):
        presenter = presenting[presenting.index(kind):]
        presenter = presenter[:presenter.index("\n}\n")]
        reads = re.findall(r"@Environment\(\\\.(\w+)\) private var (\w+)", presenter)
        assert reads == [("appModels", "models"), ("tabBarRoom", "tabBarRoom"), ("playerClearance", "playerClearance"),
                         ("macSheetLevel", "sheetLevel")], (kind, reads)
        assert ("AppCarried(models: models, tabBarRoom: tabBarRoom, playerClearance: playerClearance,\n"
                "                                 sheetLevel: sheetLevel)") in presenter, kind



# ----------------------------------------------------------------------------- the desktop frame (slice 3)

def test_the_mac_is_always_the_desktop_frame_and_the_iphone_its_tabs():
    """The Mac app's plan decision 3: the Mac's window is the desktop frame whatever its width; the iPhone's tabs exactly
    as before. Core decides (MacFrame.drawsDesktop, held to the device)."""
    root = bare(app_sources()["Root/RootView.swift"])
    app = root[root.index("@ViewBuilder private var app: some View {"):]
    app = app[:app.index("\n    }\n")]
    assert re.search(r"if MacFrame\.drawsDesktop\(Platform\.device\) \{\s*DesktopFrame\(\)\s*\} else \{\s*MainTabs\(\)\s*\}", app)
    assert root.count("MainTabs()") == 1 and root.count("DesktopFrame()") == 1
    gate = root[root.index("case .ready:"):]
    assert gate.index("app\n") < gate.index(".accessibilityHidden(server.signInOver != nil)")
    # no system split view and no inspector: the frame is the app's own drawing, as the web's (an inspector or a split
    # view's column would be a presentation or a column whose environment no smoke run has seen)
    for name, text in app_sources().items():
        code = bare(text)
        assert "NavigationSplitView" not in code and not re.search(r"\binspector\s*\(", code), name


def test_only_the_apps_own_window_is_shaped():
    """Shaping every scene that connects or comes to the front would shape whatever a presentation brings to the front
    with the window's least size (on the Mac a sheet is drawn in a window of its own). Only the scene RootView is drawn
    in is shaped - RootView is never inside a presentation."""
    app = app_sources()
    mac = bare(app[PLATFORM]).split("\n#else\n")[0]
    launching = mac[mac.index("static func launching()"):]
    launching = launching[:launching.index("\n    }\n")]
    assert "willConnectNotification" not in launching, "a scene isn't shaped as it connects - it isn't known yet"
    assert "forName: UIScene.didActivateNotification" in launching
    assert "if mainScenes.contains(scene) { shape(scene) }" in launching
    assert "@MainActor private static let mainScenes = NSHashTable<UIWindowScene>.weakObjects()" in mac
    main = mac[mac.index("static func mainScene(_ scene: UIWindowScene) {"):]
    main = main[:main.index("\n    }\n")]
    assert main.index("mainScenes.add(scene)") < main.index("shape(scene)")
    assert mac.count("shape(scene)") == 2, "as RootView is put in it, and as it comes to the front"
    marker = mac[mac.index("private struct MainWindowMarker: UIViewRepresentable {"):]
    assert "override func didMoveToWindow() {" in marker
    assert "if let scene = window?.windowScene { Platform.mainScene(scene) }" in marker
    assert re.search(r"func shapesWindow\(\) -> some View \{\s*background\(MainWindowMarker\(\)\.accessibilityHidden\(true\)\)\s*\}", mac)
    uses = {name: bare(text).count(".shapesWindow()") for name, text in app.items() if name != PLATFORM}
    assert {name: n for name, n in uses.items() if n} == {"Root/RootView.swift": 1}, "RootView alone: never a sheet's page"
    # the window scene's limits are set only in shape()
    for name, text in app.items():
        if name != PLATFORM:
            assert "sizeRestrictions" not in bare(text), name


def test_the_frame_never_opens_now_playing():
    """Decision 5: no Now Playing on the Mac (and no turntable). The frame draws no Now Playing, no mini player and no
    cover for them; should anything set Now Playing shown, it is put back."""
    frame = bare(app_sources()["Root/DesktopFrame.swift"])
    for absent in ("NowPlayingView", "MiniPlayerView", "AppTabBar", ".tabItem", "appCover(", "nowPlayingShown = true"):
        assert absent not in frame, absent
    assert "if shown && !MacFrame.opensNowPlaying(Platform.device) { navigation.nowPlayingShown = false }" in frame
    bar = bare(app_sources()["Player/PlayerBar.swift"])
    assert "nowPlayingShown" not in bar and "NowPlayingView" not in bar
    # a click on the bar's cover opens it full size - the cover viewer, as Now Playing's cover does
    assert ".opensCoverFullScreen(track, into: $viewing)" in bar and ".coverViewer($viewing, onDismiss: {})" in bar
    for name, text in app_sources().items():
        if "nowPlayingShown = true" in bare(text):
            assert name == "Player/MiniPlayerView.swift", f"{name}: only the iPhone's play bar opens Now Playing"


def test_the_frame_holds_the_sidebar_the_page_a_panel_and_the_bar():
    frame = bare(app_sources()["Root/DesktopFrame.swift"])
    body = frame[frame.index("var body: some View {"):frame.index("private var page: some View {")]
    order = [body.index(part) for part in ("if navigation.macSidebarShown {", "MacSidebarView()", "page\n",
                                           #? (R3) the dock, MacLook's 400 wide, whichever of its tabs shows
                                           ".padding(.trailing, MacDock.makesRoom(style, panel) ? "
                                           "CGFloat(MacLook.panelWidth) + hairline : 0)",
                                           ".overlay(alignment: .trailing) {", "if let panel {",
                                           "MacPanel(tab: panel)", "PlayerBar()")]
    assert order == sorted(order)
    #? (slice 3's review) the panel drawn in one place, a drawer's or a column's - crossing 1280 never draws it afresh
    assert frame.count("MacPanel(") == 1 and "if MacDock.liesOver(style, panel) {" not in frame
    assert "MacDock.liesOver(style, panel) ? Palette.well : Color.clear" in body
    assert "MacFrame.panelWidth" not in frame, "the web's 470 is MacFrame's, unread here"
    #? (R3) what a list on the page in front selects, for the menus: Info opens about it with nothing queued
    assert ("navigation.macSelected = selected" in frame
            and ".onChange(of: selection.subject != nil, initial: true) { (_: Bool, selected: Bool) -> Void in" in frame)
    #? (the Mac redesign, R1) the redesign's sidebar, 220 (MacLook's - the web-held 232 stays MacFrame's, unread here)
    assert ".frame(width: CGFloat(MacLook.sidebarWidth))" in body and "MacFrame.sidebarWidth" not in frame
    assert "private var style: MacFrame.PanelStyle { MacFrame.panelStyle(width: width) }" in frame
    assert ("navigation.macPanelStyle = now" in frame
            and ".onChange(of: style, initial: true) { (_: MacFrame.PanelStyle, now: MacFrame.PanelStyle) -> Void in" in frame)
    #? the page: the tab the sidebar leads to, as its stack stands - (slice 3's review) in the iPhone's TabView, its
    #? bar hidden, so every tab's pages are kept as the tabs keep them and only the one showing is on screen - (the Mac
    #? redesign, R1) each stack the Mac's own, on the Mac's routes, its root its area's (test_ios_mac_reach.py)
    page = frame[frame.index("private var page: some View {"):frame.index("private var strip: CGFloat {")]
    assert ("TabView(selection: Binding(get: { navigation.tab }, set: { (tab: AppTab) -> Void in navigation.select(tab) })) {"
            in page)
    for tab, tag in (("MacTabStack(path: paths.library, ownTop: true) { MacLibrary.root() }", "library"),
                     ("MacTabStack(path: paths.search) { MacSearch.root() }", "search"),
                     ("MacTabStack(path: paths.requests) { MacRequests.root() }", "requests"),
                     ("MacTabStack(path: paths.you) { MacSettings.root() }", "you")):
        assert re.search(re.escape(tab) + r"\s*\.tag\(AppTab\." + tag + r"\)", page), tab
    assert "switch navigation.tab {" not in page and page.count("MacTabStack(") == 4
    tabs = bare(app_sources()["Mac/Frame/MacTabStack.swift"])
    stack = tabs[tabs.index("struct MacTabStack"):]
    assert stack.count(".toolbar(.hidden, for: .tabBar)") == 2, "the system's bar hidden on every stack, root and pages"
    #? (R1) the title strip over it all, the frame laid under the title bar for it, and the status bar under the page
    order = [body.index(part) for part in ("MacTitleStrip(title: title, height: strip)", "if navigation.macSidebarShown {",
                                           "page\n", "if let items = status.shown {", "MacStatusBar(items: items)",
                                           "PlayerBar()", ".ignoresSafeArea(.container, edges: .top)")]
    assert order == sorted(order)
    assert "frame.safeAreaInsets.top" in body and "titleBar = now" in body
    assert "max(CGFloat(MacLook.titleHeight), titleBar)" in frame
    assert ".onChange(of: title, initial: true) { (_: String, now: String) -> Void in\n            Platform.nameWindow(now)" in body
    assert ".environment(status)" in body and ".environment(selection)" in body
    assert "MacTitle.title(navigation, personal: server.access.hasLibrary, savedOrder: savedOrder, playlists: playlists.list)" \
        in frame
    #? Search's own stand-down hears the tab change (SearchScreen), as on the iPhone: the frame's own went with the switch
    assert "standDown" not in frame
    # what MainTabs watches, this watches
    for line in (".onChange(of: watching, initial: true)", ".onAppear { requests.watch(watching) }",
                 ".onDisappear { requests.watch(.hidden) }", "queueCount.changed()", "queueCount.scene(phase)",
                 "if !queued { navigation.queueEnded() }", "sheetOpen: false)"):
        assert line in frame, line
    # MainTabs' sheets, over the frame - (R3's review) but the EQ's: the dock's EQ tab is the Mac's one EQ
    for sheet in (".appSheet(item: $navigation.playlistPick) {",
                  ".appSheet(item: $navigation.albumEdit, onDismiss: { navigation.editorDismissed() }) {"):
        assert sheet in frame, sheet
    assert "eqImportSheet" not in frame


def test_the_panels_are_one_at_a_time_and_never_modal():
    """(R3) The side panel is a dock of folder tabs (MacPanels.swift, notes/ios.md "The redesign, slice R3: the side
    panel's tabs; the Now Playing sheet"): one tab's page at a time, never modal, 400 wide; Core's MacDock decides which
    (MacDockTests)."""
    app = app_sources()
    panels = bare(app["Player/MacPanels.swift"])
    panel = panels[panels.index("struct MacPanel: View {"):panels.index("extension EnvironmentValues")]
    #? the strip: MacFolderTabs over MacDock's tabs (Sources only with a Get page), a click showing its tab
    assert ("MacFolderTabs(tabs: MacDock.tabs(getOpen: navigation.macGetOpen), words: MacDock.Words.tab," in panel
            and "navigation.showPanel(chosen)" in panel and "spoken: MacDock.Words.spoken)" in panel)
    #? one tab's page, the tab chosen's: a switch on it, each page once
    assert panel.count("switch tab {") == 1
    for page in ("case .upNext:\n            UpNextScreen()", "case .lyrics:\n            LyricsPanel()",
                 "case .info:\n            DockInfo()", "case .eq:\n            DockEQ()",
                 "case .sources:"):
        assert page in panel, page
    for page in ("UpNextScreen()", "LyricsPanel()", "DockInfo()", "DockEQ()"):
        assert panels.count(page) == 1, f"{page}: one tab at a time, drawn once"
    assert ".environment(\\.inSidePanel, true)" in panel and ".frame(width: CGFloat(MacLook.panelWidth))" in panel
    assert "MacFrame.panelWidth" not in panels
    assert "@Entry var inSidePanel = false" in panels
    #? (R3's review) one sheet, a shared file's EQ preview over the dock's EQ tab - the panel itself never modal
    assert "isModal" not in panels and panels.count(".appSheet(") == 1
    assert panels.index("private struct DockEQ") < panels.index(".appSheet(") < panels.index("struct LyricsPanel: View {")
    lyrics = panels[panels.index("struct LyricsPanel: View {"):]
    assert ".onAppear {\n            lyrics.showing = true" in lyrics and ".onDisappear { lyrics.showing = false }" in lyrics
    assert "LyricsView(lyrics: shown, covered: false)" in lyrics and "LyricsWords.nothingPlaying" in lyrics
    #? the dock's Done: the panel put away, Escape's through the one rule - Lyrics', the selection's Info, the EQ's
    done = panels[panels.index("struct DockDone: View {"):panels.index("private struct DockInfo")]
    assert "navigation.closePanel()" in done
    assert "DockDone()" in lyrics
    eq = bare(app["EQ/EQRoute.swift"])
    assert "if inSidePanel {" in eq and "DockDone(words: EQWords.Screen.done)" in eq
    #? Info: about the selection, else the song playing, its heading saying which (MacDock's)
    info = panels[panels.index("private struct DockInfo"):panels.index("private struct DockEQ")]
    assert "MacDock.infoSubject(selected: selected.map(Self.kind), playing: player.current != nil)" in info
    assert "MacDock.Words.heading(subject)" in info and "@Environment(MacSelection.self)" in info
    assert "case nil:\n                InfoView()" in info and "AlbumInfoList(album:" in info
    #? the EQ: the EQ page of the output now on the dock's own stack, its pages pushed on it
    dock_eq = panels[panels.index("private struct DockEQ"):panels.index("struct LyricsPanel: View {")]
    assert "NavigationStack(path: $stack.path) {" in dock_eq and "EQScreen(opened: .now)" in dock_eq
    assert ".environment(stack)" in dock_eq and "EQDestination(route: route)" in dock_eq
    #? an EQ link pushes on the dock's stack there; on the Mac elsewhere it shows the tab (Settings > Playback's EQ row)
    link = eq[eq.index("struct EQLink"):eq.index("struct EQDestination")]
    assert "if done != nil || inSidePanel {" in link and "navigation.showPanel(.eq)" in link
    assert "MacFrame.drawsDesktop(Platform.device)" in link
    # Up Next's and Info's Done put the panel away there, and dismiss their sheet as before on the iPhone
    for name in ("UpNext/UpNextScreen.swift", "Info/InfoView.swift"):
        code = bare(app[name])
        assert "@Environment(\\.inSidePanel) private var inSidePanel" in code, name
        assert "if inSidePanel { navigation.closePanel() } else { dismiss() }" in code, name
    routes = bare(app["Shared/Routes.swift"])
    assert "private(set) var macPanel: MacDock.Tab?" in routes
    for rule in ("macPanel = MacDock.toggled(macPanel, tab, getOpen: macGetOpen)",
                 "macPanel = MacDock.shown(macPanel, asked: tab, getOpen: macGetOpen)",
                 "macPanel = MacDock.afterQueueEnds(macPanel, selected: macSelected)",
                 "didSet { macPanel = MacDock.kept(macPanel, getOpen: macGetOpen) }"):
        assert rule in routes, rule
    album = routes[routes.index("func openAlbum(_ album: AlbumRoute) {"):]
    assert "if MacDock.liesOver(macPanelStyle, macPanel) { macPanel = nil }" in album[:album.index("\n    }\n")]
    reset = routes[routes.index("func reset() {"):]
    assert "macPanel = nil" in reset[:reset.index("\n    }\n")]
    #? View's four: a tab's key closes its own and switches from another; ⌥⌘E is the EQ's (MacMenuTests)
    commands = bare(app["Shared/MacCommands.swift"])
    assert "case .upNext, .lyrics, .info, .eq:\n            if let panel = command.panel { navigation.togglePanel(panel) }" in commands
    assert "selected: navigation.macSelected" in commands
    #? the bar's ••• Info and EQ show their tab
    bar = bare(app["Player/PlayerBar.swift"])
    assert "onEQ: { navigation.showPanel(.eq) }" in bar and "navigation.eqImportSheet = true" not in bar


def test_the_bars_actions_are_the_players_own():
    """The bar carries out a click through the very calls Now Playing's buttons make: no engine change, no volume."""
    bar = bare(app_sources()["Player/PlayerBar.swift"])
    for call in ("player.toggle()", "player.previous()", "player.next()", "player.toggleShuffle()",
                 "player.setRepeat(nextRepeat(mode))", "player.seek(to:", "navigation.openAlbum(route)",
                 "navigation.togglePanel(.lyrics)", "navigation.togglePanel(.upNext)", "navigation.togglePanel(.info)",
                 "AirPlayButton()", "NowPlayingMenu(hasAlbum: route != nil",
                 "navigation.playlistPick = PlaylistPickRequest(PlaylistPick(playing: track))", "BarScrubber()",
                 "Text(LyricsWords.nothingPlaying)", "Lyrics.dimmed(lyrics.have, on: lyricsOn)"):
        assert call in bar, call
    assert not re.search(r"(?i)volume|gain", bar), "no volume of deadwax's own"
    assert "engine" not in bar and "deck" not in bar, "nothing of the engine's, and no turntable"
    assert ".frame(height: CGFloat(MacFrame.barHeight))" in bar
    assert "let side = CGFloat(MacFrame.barSide(width: width))" in bar


def test_the_sidebar_is_mac_sidebars_rows():
    sidebar = bare(app_sources()["Root/MacSidebarView.swift"])
    for rule in ("MacSidebar.current(at, listed: listed.map(\\.id))", "MacSidebar.overLibraryView(at)",
                 "MacSidebar.sideShown(current, remembered: MacSidebar.side(saved: savedSide), over: over)",
                 "MacSidebar.folds(saved: savedFolds)", "MacSidebar.manageRows(server.access)",
                 "MacSidebar.rows(side, order: order, personal: personal)", "MacSidebar.sideFlip(current, to: to, over: over)",
                 "navigation.macMove(MacSidebar.move(each, at))", "MacSidebar.foldCurrent(fold, folds, current)",
                 "MacSidebar.manageHeadLabel(folded: folds.manage", "MacSidebar.saved(folds.toggled(fold))",
                 "@AppStorage(MacSidebar.sideKey)", "@AppStorage(MacSidebar.foldedKey)", "@AppStorage(LibraryPages.storageKey)",
                 "RequestWords.badgeText(requests.badgeCount)", "queueCount.count.value",
                 ".onAppear { queueCount.shows(.sidebar) }", ".onDisappear { queueCount.hides(.sidebar) }",
                 ".task(id: server.person) { await playlists.ask(fresh: false) }",
                 ".onChange(of: server.person) { (_: Int, _: Int) -> Void in queueCount.shows(.sidebar) }",
                 "row(.settings, current: current, at: at)"):
        assert rule in sidebar, rule
    #? (the Mac redesign, R1) drawn as the canvas draws it: the wordmark, the well's field, text rows with no glyphs - 26
    #? tall, in the selection's colours where you are - the counts' badges, the Library's switch a segmented control
    for drawn in ("Text(MacSidebar.Words.brand)", ".font(Typeface.Mac.text(.brand).weight(.bold))",
                  ".frame(height: CGFloat(MacLook.navRowHeight))", ".frame(height: CGFloat(MacLook.findHeight))",
                  ".background { DWWell(focused: focused) }", "DWCount(count: badge)",
                  "DWSegmented(options: MacSidebar.Side.allCases", ".background(DWPalette.side)",
                  ".overlay(alignment: .trailing) { DWRule(colour: DWPalette.frame, vertical: true) }"):
        assert drawn in sidebar, drawn
    assert "MacSidebar.symbol(" not in sidebar and "Image(systemName: symbol)" not in sidebar, "no glyph on a row"
    assert "Palette." not in sidebar.replace("MacPalette.", "").replace("DWPalette.", ""), "the redesign's colours alone"
    assert "case sidebar" in bare(app_sources()["Manage/QueueCountModel.swift"])
    routes = bare(app_sources()["Shared/Routes.swift"])
    move = routes[routes.index("func macMove(_ move: MacSidebar.Move) {"):]
    move = move[:move.index("\n    }\n")]
    for case in ("case .tab(let tab):", "case .view(let page):", "case .section(let page):",
                 "case .playlist(let id, let how):", "case .manage(let tool, let how):"):
        assert case in move, case
    #? (slice 3's review) a page put on a stack never replaces nor pops one holding work: Core's put, with the count the
    #? tab tapped again keeps (MacSidebarTests holds the rule)
    assert "MacSidebar.put(AppRoute.playlist(PlaylistRoute(id: id)), how, on: &library, kept: kept(library))" in move
    assert "MacSidebar.put(route, how, on: &you, kept: kept(you))" in move
    assert "Self.put(" not in routes and "private static func put(" not in routes
    kept = routes[routes.index("private func kept(_ stack: [AppRoute]) -> Int {"):]
    kept = kept[:kept.index("\n    }\n")]
    for rule in ("PlaylistEdit.pagesKept(ids, editing: editingPlaylist)",
                 "OwnPassword.pagesKept(password, changing: changingPassword)",
                 "People.pagesKept(people, writing: writingPeople)"):
        assert rule in kept, rule
    assert "stack.removeLast(stack.count - kept(stack))" in routes


def test_the_grids_and_the_readable_pages():
    app = app_sources()
    albums = bare(app["Library/AlbumsScreen.swift"])
    columns = albums[albums.index("private static var columns: [GridItem] {"):]
    columns = columns[:columns.index("\n    }\n")]
    assert ("if Platform.mac {\n            return [GridItem(.adaptive(minimum: CGFloat(MacFrame.tileMin)), spacing: gap, "
            "alignment: .top)]") in columns
    assert ("return [GridItem(.flexible(), spacing: gap, alignment: .top), GridItem(.flexible(), spacing: gap, alignment: .top)]"
            in columns), "the iPhone's two columns as before"
    routes = bare(app["Shared/Routes.swift"])
    destinations = routes[routes.index("func appRoutes() -> some View {"):]
    readable = re.findall(r"case \.(\w+)\(let \w+\): [^\n]*\.readableOnMac\(\)", destinations)
    assert readable == ["album", "artist", "group", "mbArtist", "topSongs", "serverSettingsGroup", "person"]
    mac = bare(app[PLATFORM]).split("\n#else\n")[0]
    #? (slice 3's review) the room either side given to the page's scroll view as its content's margins, never the
    #? scroll view narrowed: the page scrolls anywhere across it, its scroll bar at the page's edge
    assert re.search(r"func readableOnMac\(\) -> some View \{\s*modifier\(ReadableOnMac\(\)\)\s*\}", mac)
    readable = mac[mac.index("private struct ReadableOnMac: ViewModifier {"):mac.index("private struct MainWindowMarker")]
    assert ".contentMargins(.horizontal, margin > 0 ? CGFloat(margin) : nil, for: .scrollContent)" in readable
    assert "MacFrame.readableMargin(width: Double(page.size.width))" in readable
    assert "frame(maxWidth: CGFloat(MacFrame.readableWidth))" not in mac


# ----------------------------------------------------------------------------- the Mac's words (slice 4)

#? (slice 4, notes/ios.md "The Mac app, slice 4: the Mac's words") the words that differ on the Mac are Core's, decided
#? from the device it is handed - DeviceWordsTests holds both devices' words on Linux, the iPhone's against a snapshot
#? of c97a824's - and the App hands it Platform.device: one call of each kind, where the brief named the word
DEVICE_WORDS = {
    "Models/ServerModel.swift": [
        "DeadwaxClient(server: address, session: session, transport: transport, device: Platform.device)",
        "rekey.ended(outcome, device: Platform.device)"],
    "You/YouView.swift": ["LabeledContent(YouWords.thisDevice(Platform.device))"],
    "You/ThisPhoneSection.swift": [".navigationTitle(YouWords.thisDevice(Platform.device))"],
    "EQ/EQImport.swift": ["Label(EQWords.Import.fromFiles(Platform.device), systemImage: \"doc\")"],
    "EQ/EQScreen.swift": ["EQOtherOutputRow(output: other.output(Platform.device),"],
    "Models/DebugModel.swift": [
        "InstallExpiry.line(expiration: Self.profile()?.expiration, now: Date(), device: Platform.device)"],
    "Root/ServerAddressView.swift": ["Text(AddressWords.footer(Platform.device))",
                                     "ForEach(report.lines(Platform.device), id: \\.self)"],
    "Library/PullShuffleView.swift": ["PullShuffleWords.line(phase, can: can, of: of, device: Platform.device)"],
    "You/ChangePasswordScreen.swift": [
        "flow.ended(ticket, outcome, signInOver: server.signInOver != nil, device: Platform.device)"],
    "You/DownloadsRow.swift": ["DownloadWords.storeUnreadable(Platform.device)"],
    "Models/PlayerModel+Engine.swift": ["AudioFailure(DownloadWords.notHereUnreached(Platform.device), kind: .network)"],
}

#? the App's own literals naming a phone: the turntable recording's file name and the user agent written into it (data,
#? read by the bench's replay - and the Mac has no turntable); each as it starts
PHONE_LITERALS = {"Player/Turntable/DeckController.swift": ['"deadwax-turntable-phone-"', '"deadwax iPhone app \\(']}
PHONE_WORD = re.compile(r'"[^"\n]*\bi?[Pp]hones?\b[^"\n]*"')


#? (slice 4's review) a device named in the App, any way: `Device.iPhone` or `Device.mac`, `Device(rawValue:`, or
#? `.iPhone` / `.mac` written as a value anywhere - an argument, labelled or not, a ternary's choice, a return
#? (`Platform.mac`, `x?.mac` and the like are members, not values). Platform.swift alone says which this build is.
NAMES_A_DEVICE = re.compile(r"\bDevice\s*(?:\.\s*(?:iPhone|mac)\b|\(\s*rawValue)|(?<![\w)\]?!])\.(?:iPhone|mac)\b")


def test_the_app_hands_core_the_device_for_its_words():
    app = app_sources()
    for path, calls in DEVICE_WORDS.items():
        for call in calls:
            assert call in app[path], f"{path}: {call}"
    for path, text in app.items():
        if path == PLATFORM:
            continue
        # never a device named in the App: Core is handed this build's, so the iPhone's words are the iPhone's there
        named = NAMES_A_DEVICE.search(bare(text))
        assert not named, (path, named and named.group(0))


def test_no_word_the_app_writes_itself_says_phone():
    for path, text in app_sources().items():
        code = reader.views(text)[0]
        found = PHONE_WORD.findall(code)
        allowed = PHONE_LITERALS.get(path, [])
        assert len(found) == len(allowed) and all(said.startswith(start) for said, start in zip(found, allowed)), (path, found)


def test_nothing_stored_sent_or_keyed_changes_with_the_words():
    outputs = (CORE / "EQOutputs.swift").read_text(encoding="utf-8")
    #? the built-in speaker's key, the EQ's stored settings' - "iPhone speaker" or "Mac speakers" is only its name
    assert 'public static let speakerKey = "speaker"' in outputs
    keys = [path.name for path in sorted(KIT.rglob("*.swift"))
            if re.search(r'"speaker"', reader.views(path.read_text(encoding="utf-8"))[0])]
    assert keys == ["EQOutputs.swift"] and reader.views(outputs)[0].count('"speaker"') == 1, keys
    # the plists ask in words that fit both, and there are no App Intents, Siri or Shortcuts words to say a phone in
    for name in ("Info.plist", "Info-Mac.plist"):
        plist = (IOS / "Config" / name).read_text(encoding="utf-8")
        strings = re.findall(r"<string>([^<]*)</string>", plist)
        assert "deadwax plays your music from your deadwax server on this network." in strings, name
        assert not [s for s in strings if re.search(r"\bi?[Pp]hones?\b|\biOS\b", s)], name
    assert not list(APP.rglob("*.intentdefinition")) and not list(APP.rglob("*.appintents"))
    assert not any(re.search(r"\bimport AppIntents\b|\bAppIntent\b", bare(text)) for text in app_sources().values())


def test_debug_reads_the_macs_profile_where_install_mac_finds_it():
    """(Slice 4's review) Debug's install line reads the build's own provisioning profile: the phone's
    embedded.mobileprovision as before, and on the Mac Contents/embedded.provisionprofile - the file install-mac.sh
    refuses but for --allow-profile - so a Mac build that carries one says its date, not that it never runs out."""
    model = bare(app_sources()["Models/DebugModel.swift"])
    code = reader.views(app_sources()["Models/DebugModel.swift"])[0]
    assert "guard let url = profileURL, let data = try? Data(contentsOf: url) else { return nil }" in model
    url = code[code.index("static var profileURL: URL? {"):]
    url = url[:url.index("\n    }\n")]
    assert ('Platform.mac\n            ? Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")\n'
            '            : Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")') in url
    script = (IOS / "scripts" / "install-mac.sh").read_text(encoding="utf-8")
    assert '"$app/Contents/embedded.provisionprofile"' in script
    core = (CORE / "InstallExpiry.swift").read_text(encoding="utf-8")
    assert 'return device == .mac ? mac : "No install date to show: this build wasn\'t signed for a phone."' in core


# ----------------------------------------------------------------------------- slice 5: sleep, power and downloads
# (notes/ios.md "The Mac app, slice 5: sleep, power and downloads") IOKit's sleep and power, CoreAudio's default output
# and ProcessInfo's activities are the Mac's alone, so they are said only in Platform.swift's Mac half - their imports
# inside the switch - and Core's MacPower holds every rule they follow.

def _halves() -> tuple[str, str]:
    """Platform.swift's Mac half and iPhone half - the switch's own text alone, not what is above or below it."""
    code = bare(app_sources()[PLATFORM])
    mac = code.split("\n#if targetEnvironment(macCatalyst)\n", 1)[1].split("\n#else\n")[0]
    return mac, code.split("\n#else\n", 1)[1].split("\n#endif\n")[0]


def _body(code: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = code.index(start)
    opened = code.index("{", at)
    depth = 0
    for i in range(opened, len(code)):
        depth += {"{": 1, "}": -1}.get(code[i], 0)
        if depth == 0:
            return code[at:i + 1]
    raise AssertionError(f"unclosed: {start}")


MAC_ONLY = re.compile(r"\b(IORegisterForSystemPower|IOAllowPowerChange|IOPS\w+|AudioObject\w+|kAudio\w+|beginActivity|"
                      r"endActivity|import\s+(?:IOKit|CoreAudio)\b)")


def test_the_macs_power_apis_are_said_in_platforms_mac_half_alone():
    mac, phone = _halves()
    for name, text in app_sources().items():
        code = bare(text)
        if name == PLATFORM:
            # neither the iPhone's half nor anything outside the switch (an import above it would be the phone's too)
            outside = code.replace(mac, "")
            assert not MAC_ONLY.search(outside), MAC_ONLY.search(outside).group(0)
            continue
        found = MAC_ONLY.search(code)
        assert not found, (name, found and found.group(0))
    for module in ("import CoreAudio", "import IOKit.ps", "import IOKit.pwr_mgt"):
        assert re.search(rf"^{re.escape(module)}$", mac, re.M), module
    # the engine has no diff: nothing of slice 5's is in DeadwaxAudio
    for path in sorted((KIT / "DeadwaxAudio").rglob("*.swift")):
        code = bare(path.read_text(encoding="utf-8"))
        assert not re.search(r"\b(MacPower|IOKit|IORegisterForSystemPower|beginActivity|WorkAwake|ScreenAwake)\b", code), path.name


def test_will_sleep_pauses_then_allows_and_a_sleep_is_never_refused():
    mac, _ = _halves()
    told = _body(mac, "static func told(_ message: UInt32, _ argument: UnsafeMutableRawPointer?)")
    assert "switch MacPower.answer(to: message) {" in told
    allow = told[told.index("case .allowNow:"):told.index("case .pauseThenAllow:")]
    assert allow.split() == ["case", ".allowNow:", "IOAllowPowerChange(root,", "Int(bitPattern:", "argument))"], allow
    then = told[told.index("case .pauseThenAllow:"):told.index("case .woke:")]
    assert then.index("willSleep?()") < then.index("IOAllowPowerChange(root, Int(bitPattern: argument))"), \
        "the player pauses, then the sleep is allowed"
    woke = told[told.index("case .woke:"):told.index("case .nothing:")]
    assert woke.split() == ["case", ".woke:", "woke?()"]
    # never a refusal, anywhere
    for name, text in {**app_sources(), **kit_sources()}.items():
        assert "IOCancelPowerChange" not in bare(text), name
    # registered once, on the main run loop
    watch = _body(mac, "static func watch(willSleep: @escaping @MainActor () -> Void, woke: @escaping @MainActor () -> Void)")
    assert "IORegisterForSystemPower(nil, &made," in watch and "MainActor.assumeIsolated { MacSleep.told(message, argument) }" in watch
    assert "CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(made).takeUnretainedValue(), .commonModes)" in watch
    assert "guard root == 0 else { return }" in watch and "EngineTrace.note(MacPower.sleepUnwatched)" in watch
    # the player: paused at will-sleep, and the wake only noted - nothing started
    player = bare(app_sources()["Models/PlayerModel.swift"])
    assert ("Platform.watchSleep(willSleep: { [weak self] in self?.willSleep() }, woke: { EngineTrace.note(MacPower.wakeNote) })"
            in player)
    sleep = _body(player, "private func willSleep()")
    assert "let at = MacPower.willSleep(playing: isPlaying, retrying: retrying, interrupted: interrupted)" in sleep
    assert "if at.pause { pause() }" in sleep and "resume" not in sleep.lower().replace("no resume", "")


def test_the_power_messages_are_io_message_hs():
    core = (CORE / "MacPower.swift").read_text(encoding="utf-8")
    # IOMessage.h: iokit_common_msg(n) = sys_iokit | sub_iokit_common | n; sys_iokit = err_system(0x38) = 0x38 << 26
    common = lambda n: ((0x38 & 0x3F) << 26) | 0 | n  # noqa: E731
    for name, n in (("canSystemSleep", 0x270), ("systemWillSleep", 0x280), ("systemHasPoweredOn", 0x300)):
        found = re.search(rf"public static let {name}: UInt32 = (0x[0-9a-f_]+)$", core, re.M)
        assert found, name
        assert int(found.group(1).replace("_", ""), 16) == common(n), name
    assert common(0x270) == 0xE0000270 and common(0x280) == 0xE0000280 and common(0x300) == 0xE0000300
    for case, message in (("allowNow", "canSystemSleep"), ("pauseThenAllow", "systemWillSleep"), ("woke", "systemHasPoweredOn")):
        assert f"case {message}: return .{case}" in core, case


def test_interrupted_is_cleared_at_sleep_and_none_armed_until_the_next_play():
    """The trap: an interruption's end with "should resume" plays again. If macOS posts one around a sleep, the wake
    would start the music - so at will-sleep `interrupted` is cleared, and until the listener plays again no
    interruption sets it (the engine's pause lands a moment after it is asked for, so "playing" alone could)."""
    core = bare((CORE / "MacPower.swift").read_text(encoding="utf-8"))
    assert "AtSleep(pause: playing || retrying, interrupted: false, sleptSincePlay: true)" in core
    assert "(playing || retrying) && !sleptSincePlay" in core
    player = bare(app_sources()["Models/PlayerModel.swift"])
    sleep = _body(player, "private func willSleep()")
    assert sleep.index("interrupted = at.interrupted") < sleep.index("if at.pause { pause() }")
    assert sleep.index("sleptSincePlay = at.sleptSincePlay") < sleep.index("if at.pause { pause() }")
    interruption = _body(player, "private func interruption(began: Bool, shouldResume: Bool)")
    assert ("interrupted = MacPower.interruptionArms(playing: isPlaying, retrying: retrying, sleptSincePlay: sleptSincePlay)"
            in interruption)
    # set at will-sleep alone; let go at the listener's next play - Play, or a new queue
    assert "@ObservationIgnored private var sleptSincePlay = false" in player
    assert len(re.findall(r"(?<!var )\bsleptSincePlay = ", player)) == 3
    assert "sleptSincePlay = false" in _body(player, "func resume()")
    assert "sleptSincePlay = false" in _body(player, "private func startQueue(")


def test_an_output_gone_pauses_as_the_phone_does_and_says_who_said_so():
    player = bare(app_sources()["Models/PlayerModel.swift"])
    assert "session.onOldDeviceGone = { [weak self] in self?.outputGone(.session) }" in player
    assert "Platform.watchOutputs { [weak self] in self?.outputGone(.coreAudio) }" in player
    gone = _body(player, "private func outputGone(_ by: MacPower.OutputGoneBy)")
    assert gone.index("EngineTrace.note(MacPower.outputGoneNote(by, playing: isPlaying || retrying))") < gone.index("pause()")
    # twice is harmless: the engine's pause is nothing while paused
    engine = bare((KIT / "DeadwaxAudio" / "PlaybackEngine.swift").read_text(encoding="utf-8"))
    assert re.search(r"private func pauseNow\(\) \{\s*guard wantsPlay else \{ return \}", engine)
    # CoreAudio's default output, listened to on a queue of its own and judged on the main actor by Core's rule
    mac, _ = _halves()
    outputs = _body(mac, "private enum MacOutputs")
    assert "AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener())" in outputs
    assert "mSelector: kAudioHardwarePropertyDefaultOutputDevice" in outputs and "kAudioHardwarePropertyDevices" in outputs
    assert "nonisolated static let queue = DispatchQueue(label: " in outputs
    assert "DispatchQueue.main.async {" in outputs
    assert "if MacPower.outputGone(previous: previous, now: now.output, devices: devices) { gone?() }" in outputs
    assert "guard let devices = now.devices else { return }" in outputs, "no answer is never a device gone"


def test_only_while_charging_reads_iokit_on_a_mac_and_the_battery_on_the_phone():
    mac, phone = _halves()
    read = _body(mac, "private enum MacPowerSource")
    assert "IOPSCopyPowerSourcesInfo()?.takeRetainedValue()" in read
    assert "IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()" in read
    assert "return MacPower.power(source: type.map { $0 as String })" in read
    assert "guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return MacPower.power(source: nil) }" in read
    assert "IOPSNotificationCreateRunLoopSource(" in read and "CFRunLoopAddSource(CFRunLoopGetMain(), made, .defaultMode)" in read
    # the phone's reading, moved here from DownloadModel word for word
    power = _body(phone, "@MainActor static func power() -> PowerState")
    assert power.split("{", 1)[1].split() == (
        "switch UIDevice.current.batteryState { case .charging: return .charging case .full: return .full "
        "case .unplugged: return .unplugged case .unknown: return .unknown @unknown default: return .unknown } }").split()
    assert re.search(r"static func watchPower\(_ changed: @escaping @MainActor \(\) -> Void\) \{\}", phone)
    downloads = bare(app_sources()["Downloads/DownloadModel.swift"])
    assert downloads.count("Platform.power()") == 2 and "Platform.watchPower { [weak self] in self?.readPower() }" in downloads
    assert "UIDevice.batteryStateDidChangeNotification" in downloads, "the phone's changes as before"
    # UIDevice's battery read nowhere but there: not in DownloadModel, not in the Mac's half, not anywhere else
    battery = re.compile(r"\bbatteryState\b")
    for name, text in app_sources().items():
        code = bare(text) if name != PLATFORM else bare(text).replace(phone, "")
        assert not battery.search(code), name
    assert len(battery.findall(phone)) == 1
    # unknown means plugged in: only the battery and a UPS are unplugged
    core = bare((CORE / "MacPower.swift").read_text(encoding="utf-8"))
    rule = _body(core, "public static func power(source: String?) -> PowerState")
    assert "case batteryPower?, upsPower?: return .unplugged" in rule and "default: return .pluggedIn" in rule


def test_a_care_run_holds_the_display_on_and_work_keeps_app_nap_off():
    mac, phone = _halves()
    display = _body(mac, "@MainActor static func keepDisplayOn(_ on: Bool)")
    assert "options: [.idleDisplaySleepDisabled, .userInitiated]," in display
    assert "if on, MacActivities.display == nil {" in display and "ProcessInfo.processInfo.endActivity(held)" in display
    working = _body(mac, "@MainActor static func keepWorking(_ work: Work, _ on: Bool)")
    runs = working[working.index("case .runs:"):working.index("case .downloads:")]
    downloads = working[working.index("case .downloads:"):]
    assert "options = [.userInitiated]" in runs
    # downloads: out of App Nap, the Mac's idle sleep still allowed (a whole library on battery isn't held awake)
    assert "options = [.userInitiatedAllowingIdleSystemSleep]" in downloads
    assert "if on, MacActivities.work[work] == nil {" in working
    assert "else if !on, let held = MacActivities.work.removeValue(forKey: work) {" in working
    # the phone: the idle timer as ScreenAwake set it, and nothing for App Nap
    assert re.search(r"static func keepDisplayOn\(_ on: Bool\) \{\s*UIApplication\.shared\.isIdleTimerDisabled = on\s*\}", phone)
    assert re.search(r"static func keepWorking\(_ work: Work, _ on: Bool\) \{\}", phone)
    assert re.search(r"static func watchSleep\([^{]*\{\}", phone) and re.search(r"static func watchOutputs\([^{]*\{\}", phone)
    # who wants each: one place each, and ScreenAwake, WorkAwake the only callers
    app = {name: bare(text) for name, text in app_sources().items()}
    awake = app["Manage/ScreenAwake.swift"]
    assert "Platform.keepDisplayOn(!wanted.isEmpty)" in awake
    assert "Platform.keepWorking(.runs, holds > 0 || wanted.contains(.libraryCare) || wanted.contains(.retime))" in awake
    assert "Platform.keepWorking(.downloads, wanted.contains(.downloads))" in awake
    for name, code in app.items():
        if name not in (PLATFORM, "Manage/ScreenAwake.swift"):
            assert "keepDisplayOn" not in code and "keepWorking" not in code, name
    assert "WorkAwake.keep(runs.under != nil, for: .libraryCare)" in _body(app["Manage/CareRunModel.swift"], "private func screen()")
    assert "WorkAwake.keep(retime.running, for: .retime)" in _body(app["Manage/ServerSettingsModel.swift"], "private func screen()")
    assert re.search(r"private var live: \[String: Int\] = \[:\] \{\s*didSet \{ WorkAwake\.keep\(!live\.isEmpty, for: \.downloads\) \}",
                     app["Downloads/DownloadModel.swift"])
    hold = _body(app["Edit/EditAlbumModel.swift"], "final class BackgroundHold")
    init = _body(hold, "init(named name: String)")
    assert init.index("WorkAwake.hold(true)") < init.index("UIApplication.shared.beginBackgroundTask(withName: name)")
    end = _body(hold, "func end()")
    assert "WorkAwake.hold(false)" in end and "working = false" in end
    # iOS running out ends the background task alone - the hold's App Nap activity is the apply's to end
    assert "MainActor.assumeIsolated { self?.endTask() }" in init
    # beginBackgroundTask stays as it is everywhere
    began = {name: code.count("beginBackgroundTask(") for name, code in app.items() if "beginBackgroundTask(" in code}
    assert began == {"Edit/EditAlbumModel.swift": 1, "Downloads/DownloadModel.swift": 1, "Models/PlayerModel+Resume.swift": 1}, began


# ----------------------------------------------------------------------------- EQ files (slice 6)

# (notes/ios.md "The Mac app, slice 6: EQ files") File > Import EQ File… (⌘O)'s Open panel, Finder's Open With, a file
# dropped on the Dock's icon or on the window, all one way in - a shared file's (EQImportReading.file, then
# AppNavigation's share); Export…'s Save panel beside its share; read and write for the files chosen; one window.

def _raw_halves() -> tuple[str, str]:
    """Platform.swift's two halves with their string literals as written (`bare` blanks them: "*" would read "")."""
    text = app_sources()[PLATFORM]
    mac = text.split("\n#if targetEnvironment(macCatalyst)\n", 1)[1].split("\n#else\n")[0]
    return mac, text.split("\n#else\n", 1)[1].split("\n#endif\n")[0]


#? the App's file panels and drops, by file: the EQ page's own Import… (Files on the phone, the Open panel on a Mac), and
#? Platform's Mac half's three - nothing else asks the system for a file, writes one out, or takes a drop
FILE_PANELS = {
    "fileImporter": {"EQ/EQImport.swift": 1, PLATFORM: 1},
    "fileExporter": {PLATFORM: 1},
    "dropDestination": {PLATFORM: 1},
    "onDrop": {},
    "onPasteCommand": {},
    "pasteDestination": {},
}


def test_file_import_eq_file_opens_the_panel_and_takes_a_shared_files_way():
    app = app_sources()
    commands = bare(app["Shared/MacCommands.swift"])
    assert "CommandGroup(after: .newItem) {\n            item(.importEQFile, state)\n            Divider()" in commands
    perform = _body(commands, "private func perform(_ command: MacMenu.Command)")
    assert "case .importEQFile:\n            navigation.openEQFile()" in perform
    routes = bare(app["Shared/Routes.swift"])
    opener = _body(routes, "func openEQFile()")
    assert "guard eqFileChoosing else {\n            eqFileChoosing = true\n            return\n        }" in opener
    # (the review) asked again while it still reads as up (a panel that never came): down, then up a moment later -
    # never left dead until a sign-out
    assert "eqFileChoosing = false" in opener
    assert re.search(r"Task \{ @MainActor \[weak self\] \(\) async -> Void in\s*"
                     r"try\? await Task\.sleep\(for: \.milliseconds\(100\)\)\s*self\?\.openEQFile\(\)\s*\}", opener)
    assert "var eqFileChoosing = false" in routes
    assert "eqFileChoosing = false" in _body(routes, "func reset()"), "a new person: no Open panel left asking"
    assert routes.count("eqFileChoosing = true") == 1, "only the menu asks for it"
    # RootView: the panel's file goes the way a shared file does - read as one, then the preview over what's up
    root = bare(app["Root/RootView.swift"])
    assert root.count(".onOpenURL { (url: URL) -> Void in shared(url) }") == 1
    assert re.search(r"\.eqOpenPanel\(Binding<Bool>\(get: \{ navigation\.eqFileChoosing \}, set: \{ \(up: Bool\) -> Void in\s*"
                     r"navigation\.eqFileChoosing = up\s*\}\)\) \{ \(url: URL\) -> Void in shared\(url\) \}", root)
    shared = _body(root, "private func shared(_ url: URL)")
    assert "guard url.isFileURL else { return }" in shared
    assert shared.index("EQImportReading.file(url, forKey: nil)") < shared.index("navigation.share(item)")
    assert "Task.detached(priority: .userInitiated)" in shared, "read off the main thread"
    # the Mac's Open panel: plain text, one file - the phone has none
    mac, phone = _halves()
    panel = _body(mac, "func eqOpenPanel(_ shown: Binding<Bool>, chosen: @escaping (URL) -> Void) -> some View")
    assert "fileImporter(isPresented: shown, allowedContentTypes: [.plainText], allowsMultipleSelection: false)" in panel
    assert "guard case .success(let urls) = result, let url = urls.first else { return }\n            chosen(url)" in panel
    assert re.search(r"func eqOpenPanel\(_ shown: Binding<Bool>, chosen: @escaping \(URL\) -> Void\) -> some View \{\s*self\s*\}",
                     phone)
    assert "import UniformTypeIdentifiers" in mac and "UniformTypeIdentifiers" not in phone
    # (the menus' state) its words, key and dimming are MacMenu's - drawn by `item`, as Settings… and Find are
    assert commands.count("item(.importEQFile, state)") == 1


def test_export_saves_through_the_save_panel_and_shares_as_before():
    app = app_sources()
    export = bare(app["EQ/EQExport.swift"])
    menu = _body(export, "struct EQExportMenu: View")
    assert '"' not in re.sub(r'systemImage: "\s*"', "", menu), "no words of its own: Core's, by device"
    assert 'Label(EQWords.Export.menu, systemImage: "square.and.arrow.up")' in app["EQ/EQExport.swift"]
    assert "let sections = EQWords.Export.items(Platform.device)" in menu
    assert "if index > 0 { Divider() }" in menu
    assert ".disabled(!item.enabled(hasCorrection: setting.correction != nil))" in menu
    assert "Label(EQWords.Export.menu, systemImage:" in menu
    assert re.search(r"\}\s*\.eqSavePanel\(\$saving\)\s*\}", menu), "the Save panel on the menu itself, not inside it"
    entry = _body(menu, "@ViewBuilder private func entry(_ item: EQWords.Export.Item, name: String) -> some View")
    assert re.search(r"case \.share:\s*ShareLink\(item: file\(item\.whole\), preview: SharePreview\(name\)\) \{\s*"
                     r"Text\(item\.words\)\s*\}", entry)
    assert re.search(r"case \.save:\s*Button\(item\.words\) \{ saving = file\(item\.whole\) \}", entry)
    assert menu.count("saving = ") == 1, "only a Save item sets it"
    assert re.search(r"private func file\(_ whole: Bool\) -> EQExportFile \{\s*"
                     r"EQExportFile\(setting: setting, settings: settings, whole: whole, rate: rate\)\s*\}", menu)
    # one file for both ways: the share's Transferable, plain text
    assert "struct EQExportFile: Transferable, Sendable {" in export
    assert "FileRepresentation(exportedContentType: .plainText)" in export
    # the Mac's Save panel: that file, named as the share names it; the phone's Export… shares, as before
    mac, phone = _halves()
    save = _body(mac, "func eqSavePanel(_ file: Binding<EQExportFile?>) -> some View")
    assert "fileExporter(isPresented: Binding<Bool>(get: { file.wrappedValue != nil }" in save
    assert "item: file.wrappedValue, contentTypes: [.plainText]," in save
    assert "EQWords.Export.fileName(each.setting.shownName)" in save
    assert save.count("file.wrappedValue = nil") == 3, "let go however it ends - saved, cancelled, put away"
    assert re.search(r"func eqSavePanel\(_ file: Binding<EQExportFile\?>\) -> some View \{\s*self\s*\}", phone)


def test_a_file_dropped_on_the_window_comes_the_way_a_shared_one_does():
    app = app_sources()
    mac, phone = _halves()
    drop = _body(mac, "func eqFileDrop(_ dropped: @escaping (EQImportItem) -> Void) -> some View")
    assert "dropDestination(for: EQDroppedFile.self) { (files: [EQDroppedFile], _: CGPoint) -> Bool in" in drop
    assert "guard let file = files.first else { return false }\n            dropped(file.item)\n            return true" in drop
    assert re.search(r"func eqFileDrop\(_ dropped: @escaping \(EQImportItem\) -> Void\) -> some View \{\s*self\s*\}", phone)
    # read inside the import, the way a file opened with deadwax is - asked for where it is, only read
    imported = bare(app["EQ/EQImport.swift"])
    dropped = _body(imported, "struct EQDroppedFile: Transferable, Sendable")
    assert "FileRepresentation(importedContentType: .plainText, shouldAttemptToOpenInPlace: true)" in dropped
    assert "EQDroppedFile(item: EQImportReading.file(received.file, forKey: nil))" in dropped
    assert "import CoreTransferable" in imported
    # on the window and on the EQ sheet (on the Mac a window of its own), each to AppNavigation's share
    uses = {name: bare(text).count(".eqFileDrop {") for name, text in app.items() if name != PLATFORM}
    assert {name: n for name, n in uses.items() if n} == {"Root/RootView.swift": 1, "EQ/EQRoute.swift": 1}
    for name in ("Root/RootView.swift", "EQ/EQRoute.swift"):
        assert ".eqFileDrop { (item: EQImportItem) -> Void in navigation.share(item) }" in bare(app[name]), name
    sheet = _body(bare(app["EQ/EQRoute.swift"]), "struct EQSheet: View")
    assert sheet.index(".eqFileDrop {") < sheet.index(".appSheet(isPresented:"), "on the sheet's own page, under its preview"


def test_every_file_panel_and_drop_is_one_of_the_apps_own():
    found = {kind: {} for kind in FILE_PANELS}
    for name, text in app_sources().items():
        code = bare(text)
        for kind in FILE_PANELS:
            n = len(re.findall(rf"\b{kind}\s*\(", code))
            if n:
                found[kind][name] = n
    assert found == FILE_PANELS, found
    # Platform's three are in its Mac half, none outside the switch
    mac, phone = _halves()
    for kind in ("fileImporter", "fileExporter", "dropDestination"):
        assert re.search(rf"\b{kind}\s*\(", mac) and not re.search(rf"\b{kind}\s*\(", phone), kind
    # Paste stays the EQ page's PasteButton - drawn on the Mac too (Catalyst has it from 16): one, beside Import…
    rows = bare(app_sources()["EQ/EQImport.swift"])
    rows = _body(rows, "struct EQImportRows: View")
    assert "PasteButton(payloadType: String.self) { (strings: [String]) -> Void in" in rows
    assert "read { EQImportReading.pasted(text, forKey: key) }" in rows
    assert sum(bare(text).count("PasteButton(") for text in app_sources().values()) == 1


def test_a_file_opened_with_deadwax_comes_to_the_one_window_and_stays_where_it_was():
    mac, phone = _raw_halves()
    # the open window takes every file or link opened with deadwax; with none open, this one window opens for it
    assert re.search(r"func oneWindow\(\) -> some View \{\s*handlesExternalEvents\(preferring: \[\"\*\"\], allowing: \[\"\*\"\]\)\s*\}", mac)
    window = _body(bare(mac), "func macWindow(_ menus: MacCommands) -> some Scene")
    assert re.search(r"\.commands \{.*?\}\s*\.handlesExternalEvents\(matching: \[\"\s*\"\]\)\s*\}$", window, re.S)
    assert '.handlesExternalEvents(matching: ["*"])' in mac
    assert "handlesExternalEvents" not in phone and re.search(r"func macWindow\(_ menus: MacCommands\) -> some Scene \{\s*self\s*\}", phone)
    for name, text in app_sources().items():
        if name != PLATFORM:
            assert "handlesExternalEvents" not in bare(text), name
    assert bare(app_sources()["DeadwaxApp.swift"]).count(".oneWindow()") == 1
    # offered for a .txt, never the Mac's default for one - and opened where it is (no Inbox copy on a Mac)
    import plistlib
    plist = plistlib.loads((IOS / "Config" / "Info-Mac.plist").read_bytes())
    assert plist["CFBundleDocumentTypes"] == [{"CFBundleTypeName": "Equalizer APO file", "CFBundleTypeRole": "Viewer",
                                               "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.plain-text"]}]
    assert "LSSupportsOpeningDocumentsInPlace" not in plist
    # the file is only read: the one delete is the phone's own Inbox copy, and nothing in an import writes or moves
    imported = bare(app_sources()["EQ/EQImport.swift"])
    inbox = _body(imported, "private static func deleteIfInbox(_ url: URL)")
    assert re.search(r'let inbox = documents\.appendingPathComponent\("\s*", isDirectory: true\)\.resolvingSymlinksInPath\(\)\.path',
                     inbox)
    assert "let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path" in inbox
    assert "if folder == inbox { try? FileManager.default.removeItem(at: url) }" in inbox
    assert 'appendingPathComponent("Inbox", isDirectory: true)' in app_sources()["EQ/EQImport.swift"]
    assert len(re.findall(r"\bremoveItem\(", imported)) == 1
    for call in (r"\bmoveItem\(", r"\breplaceItem", r"\bcopyItem\(", r"\.write\(to:", r"\bcreateFile\(",
                 r"FileHandle\(forWritingTo", r"FileHandle\(forUpdating", r"\btrashItem\("):
        assert not re.search(call, imported), call
    reading = _body(imported, "static func file(_ url: URL, forKey: String?) -> EQImportItem")
    assert "let scoped = url.startAccessingSecurityScopedResource()" in reading
    assert "if scoped { url.stopAccessingSecurityScopedResource() }\n            deleteIfInbox(url)" in reading
    assert "FileHandle(forReadingFrom: url)" in reading


def test_the_files_chosen_are_read_and_written_and_nothing_else():
    """Read and write for the file the person chooses (the Open panel and the Save panel), from a build setting - no
    entitlements file, no profile; install-mac.sh refuses a build signed read-only."""
    base = (IOS / "Config" / "Base.xcconfig").read_text(encoding="utf-8")
    assert re.findall(r"^ENABLE_USER_SELECTED_FILES\S*\s*=\s*(\S+)$", base, re.M) == ["readwrite"]
    assert "ENABLE_USER_SELECTED_FILES[sdk=macosx*] = readwrite" in base
    project = _load_script("check_project")
    assert project.MAC_SETTINGS["ENABLE_USER_SELECTED_FILES[sdk=macosx*]"] == "readwrite"
    helper = _load_script("install_helper")
    assert "com.apple.security.files.user-selected.read-write" in helper.MAC_ENTITLEMENTS
    assert not any("read-only" in key for key in helper.MAC_ENTITLEMENTS)
    for path in IOS.rglob("*.entitlements"):
        raise AssertionError(f"{path}: the Mac's entitlements are build settings")

# ----------------------------------------------------------------------------- managing on a big screen (slice 7)

#? (slice 7) Manage's pages, each at the readable width - and Change password, You's, the phone's page as it was
MANAGE_PAGES = {
    "chooseFolder": "ChooseFolderScreen()", "needsALook": "NeedsLookScreen()", "libraryCare": "LibraryCareScreen()",
    "heldByNobody": "HeldByNobodyScreen()", "serverSettings": "ServerSettingsScreen()",
    "serverSettingsGroup(let id)": "ServerSettingsGroupScreen(id: id)", "eventLog": "EventLogScreen()",
    "people": "PeopleScreen()", "person(let id)": "PersonScreen(id: id)",
}


def test_file_save_changes_is_server_settings_own_button_from_its_page():
    """⌘S (the Mac app's plan, slice 7): Server settings' Save changes - its words, its rule and its very call - from a
    page of it in front, as deep as it is drawn; never a second way round the save bar."""
    app = app_sources()
    commands = bare(app["Shared/MacCommands.swift"])
    # drawn by `item`, as every other item: MacMenu's words, key and dimming - in File, under Import EQ File…
    assert commands.count("item(.saveChanges, state)") == 1
    perform = _body(commands, "private func perform(_ command: MacMenu.Command)")
    assert "case .saveChanges:\n            serverSettings.save()\n        case" not in perform
    assert perform.rstrip().endswith("case .saveChanges:\n            serverSettings.save()\n        }\n    }")
    # the save bar's button calls the same, under the same rule
    screen = bare(app["Manage/ServerSettingsScreen.swift"])
    bar = _body(screen, "@ViewBuilder private func buttons(_ flow: SettingsFlow) -> some View")
    assert "settings.save()\n            }" in bar and ".disabled(!settings.saveOpen(online: reachability.online))" in bar
    model = bare(app["Manage/ServerSettingsModel.swift"])
    assert model.count("func save() {") == 1 and "flow.save(online: reachability.online, allowed: parts.page)" in model
    assert "flow.saveOpen(online: online, allowed: parts.page)" in _body(model, "func saveOpen(online: Bool) -> Bool")
    # every page of Server settings known to the menus, through its one frame - the root and each group, and so the
    # Connections page in Set up Navidrome's sheet
    frame = _body(screen, "private struct ServerSettingsPageFrame: ViewModifier")
    assert frame.count(".macSettingsPage()") == 1
    assert sum(bare(text).count(".macSettingsPage()") for name, text in app.items() if name != PLATFORM) == 1
    group = bare(app["Manage/ServerSettingsGroupScreen.swift"])
    assert screen.count(".serverSettingsPage(") == 1 and group.count(".serverSettingsPage(") == 1
    assert "ServerSettingsGroupScreen(id: ServerSettings.connectionsGroup)" in group
    mac, phone = _halves()
    assert re.search(r"func macSettingsPage\(\) -> some View \{\s*modifier\(MacSettingsPage\(\)\)\s*\}", mac)
    # the page in front: the latest page as deep as the deepest thing showing, one of Server settings' own
    refresh = commands[commands.index("final class MacRefresh"):commands.index("private struct MacSheetLevel")]
    settings = _body(refresh, "var settingsInFront: Bool {")
    assert "return pages.last { (page: Page) -> Bool in !page.sheet && page.level == deepest }?.settings == true" in settings
    page = _body(commands, "struct MacSettingsPage: ViewModifier {")
    for line in ("@Environment(\\.macSheetLevel) private var level", "page.settings = true", "page.level = level\n"):
        assert line in page, line
    assert "page.sheet" not in page and ".environment(\\.macSheetLevel" not in page, "a page, never a sheet's root"


#? The keys UIKit's own Catalyst menu was seen to carry (UIKitMacHelper's MainMenu.nib, read on macOS 27.2.1, and
#? UIKitCore's MACMENUITEM strings - no Save among them): deadwax adds none of them, so UIKit never meets one key twice
SYSTEM_KEYS = {"q", "h", "w", "m", "z", "x", "c", "v", "a", "t", "b", "i", "u", ";", ":"}
#? (Slice 7's review) the system's keys with more than ⌘, read from the same MainMenu.nib (macOS 27.2): ⇧⌘Z Redo,
#? ⌥⌘H Hide Others, ⌃⌘F Full Screen, ⌥⇧⌘V Paste and Match Style, ⇧⌘C and ⌥⌘C, ⌥⌘V
SYSTEM_MODIFIED_KEYS = {("z", frozenset({"shift"})), ("h", frozenset({"option"})), ("f", frozenset({"control"})),
                        ("v", frozenset({"option", "shift"})), ("c", frozenset({"shift"})), ("c", frozenset({"option"})),
                        ("v", frozenset({"option"}))}


def test_no_key_of_deadwaxs_is_one_the_systems_menus_have():
    core = bare((CORE / "MacMenu.swift").read_text(encoding="utf-8"))
    keys = _body(core, "public static func key(_ command: Command) -> Shortcut? {")
    found = re.findall(r'case \.(\w+): return Shortcut\(\.character\("\s*"\), (\.command|\[[^\]]*\])\)', keys)
    raw = (CORE / "MacMenu.swift").read_text(encoding="utf-8")
    chars = dict(re.findall(r'case \.(\w+): return Shortcut\(\.character\("(.)"\), \.command\)', raw))
    assert chars["saveChanges"] == "s" and chars["importEQFile"] == "o"
    for command, char in chars.items():
        if command == "info":
            #? ⌘I is Format's Italic in the base menu - Format is emptied (CommandGroup(replacing: .textFormatting))
            continue
        assert char not in SYSTEM_KEYS, (command, char)
    assert found, "the keys are read"
    # and every key of deadwax's with more than ⌘ against the system's with more than ⌘
    modified = re.findall(r'case \.(\w+): return Shortcut\(\.character\("(.)"\), \[([^\]]*)\]\)', raw)
    assert len(modified) >= 3, modified
    for command, char, mods in modified:
        others = frozenset(m.strip().lstrip(".") for m in mods.split(",")) - {"command"}
        assert others and (char, others) not in SYSTEM_MODIFIED_KEYS, (command, char, others)
    commands = bare(app_sources()["Shared/MacCommands.swift"])
    assert "CommandGroup(replacing: .textFormatting) {}" in commands
    # Copy and Select All are the system's own items: deadwax draws no ⌘C or ⌘A of its own anywhere
    for name, text in app_sources().items():
        assert not re.search(r'KeyEquivalent\("[ca]"\)|keyboardShortcut\("[ca]"', text), name


def test_the_event_logs_lines_are_selected_and_copied_with_the_systems_copy():
    app = app_sources()
    screen = bare(app["Manage/EventLogScreen.swift"])
    lines = _body(screen, "@ViewBuilder private func lines(_ feed: EventStream.Feed) -> some View")
    # the list selects on the Mac (List(selection:)) and is the List it was on the iPhone
    assert lines.count("SelectingList(selection: $selected) {") == 1 and "List {" not in lines
    assert "@State private var selected: Set<EventLog.Line.ID> = []" in screen
    assert ("ForEach(feed.log.lines) { (line: EventLog.Line) in" in lines), "rows tagged by their own identities"
    # Edit > Copy: the lines selected, as Core says them; Select All every line listed
    assert re.search(r"\.copiesSelection\(\$selected, of: feed\.log\.lines\.map\(\\\.id\)\) \{ \(chosen: Set<EventLog\.Line\.ID>\) "
                     r"-> String\? in\s*EventLog\.copyText\(chosen, of: log\.feed\.log\.lines\)\s*\}", lines)
    # a line's right-click Copy (the phone's long press) stays as it was
    row = screen[screen.index("private struct LogRow"):]
    assert ".contextMenu {" in row and "UIPasteboard.general.string = EventLog.copyText(line)" in row
    mac, phone = _halves()
    # the Mac's list: selection, no Edit button; the iPhone's: List(content:), its selection never read
    listing = _body(mac, "struct SelectingList<ID: Hashable, Content: View>: View {")
    assert "List(selection: selection, content: content)" in listing
    phone_list = _body(phone, "struct SelectingList<ID: Hashable, Content: View>: View {")
    assert "List(content: content)" in phone_list and "selection:" not in phone_list.split("var body")[1]
    # the system's Copy and Select All, through the responder chain - never a key of deadwax's
    copier = _body(mac, "private struct SelectionCopier: UIViewRepresentable {")
    assert "override var canBecomeFirstResponder: Bool { true }" in copier
    # asked cheaply - a selected row still listed - the text made only for the copy itself (slice 7's review)
    assert "if action == #selector(UIResponderStandardEditActions.copy(_:)) { return copies() }" in copier
    assert "if action == #selector(UIResponderStandardEditActions.selectAll(_:)) { return selectingAll != nil }" in copier
    assert "return super.canPerformAction(action, withSender: sender)" in copier, "every other action up the chain"
    copy = _body(copier, "override func copy(_ sender: Any?) {")
    assert "guard let text = copied() else { return }\n            UIPasteboard.general.string = text" in copy
    assert "selectingAll?()" in _body(copier, "override func selectAll(_ sender: Any?) {")
    # the focus taken as a selection is made - after the update, never from a field with the cursor
    update = _body(copier, "func updateUIView(_ copier: Copier, context: Context) {")
    assert "guard copier.asked != asked else { return }" in update
    assert "guard copier.window != nil, !copier.isFirstResponder, !TextEditing.shared.typing else { return }" in update
    assert update.index("Task { @MainActor in") < update.index("copier.becomeFirstResponder()")
    copying = _body(mac, "private struct SelectionCopying<ID: Hashable>: ViewModifier {")
    assert "if !now.isEmpty { asked += 1 }" in copying
    assert "copies: { () -> Bool in !selection.wrappedValue.isDisjoint(with: ids) }" in copying
    # asked again as a field lets the cursor go with rows selected: a click that landed while the search had it
    # changes no selection when repeated (slice 7's review)
    assert re.search(r"\.onChange\(of: TextEditing\.shared\.typing\) \{ \(_: Bool, typing: Bool\) -> Void in\s*"
                     r"if !typing, !selection\.wrappedValue\.isEmpty \{ asked \+= 1 \}\s*\}", copying)
    assert "selectAll: ids.isEmpty ? nil : { selection.wrappedValue = Set(ids) }" in copying
    assert "keyboardShortcut" not in copier + copying and "UIKeyCommand" not in mac
    for name, text in app.items():
        if name != PLATFORM:
            assert "canPerformAction" not in bare(text) and "UIResponderStandardEditActions" not in bare(text), name


def test_edit_albums_sheet_is_sized_by_the_window_and_managings_pages_are_readable():
    app = app_sources()
    frame = bare(app["Root/DesktopFrame.swift"])
    edit = frame[frame.index(".appSheet(item: $navigation.albumEdit"):]
    edit = edit[:edit.index("\n        }\n")]
    assert re.search(r"EditAlbumSheet\(request: request\)\s*\.macSheet\(\)\s*\.sizedSheet\(MacFrame\.sheetSize\(width: width, "
                     r"height: height\)\)$", edit.strip())
    assert "@State private var height: Double = MacFrame.openingHeight" in frame
    #? (the Mac redesign, R1) the frame is laid under the title bar: the height under it is the frame's less the strip's
    assert re.search(r"\.onGeometryChange\(for: Double\.self\) \{ \(frame: GeometryProxy\) -> Double in\s*"
                     r"Double\(frame\.size\.height - max\(CGFloat\(MacLook\.titleHeight\), frame\.safeAreaInsets\.top\)\)"
                     r"\s*\} action: \{ \(now: Double\) -> Void in\s*height = now\s*\}", frame)
    # only Edit album's: the other sheets keep the system's own size
    assert sum(bare(text).count(".sizedSheet(") for name, text in app.items() if name != PLATFORM) == 1
    mac, phone = _halves()
    sized = _body(mac, "@ViewBuilder func sizedSheet(_ size: MacFrame.Size) -> some View {")
    assert re.search(r"if #available\(iOS 18\.0, \*\) \{\s*presentationSizing\(WindowSheetSizing\(size: size\)\)\s*\} else \{\s*"
                     r"self\s*\}", sized), "macOS 14: the system's size, as it was"
    sizing = _body(mac, "private struct WindowSheetSizing: PresentationSizing {")
    assert "ProposedViewSize(width: CGFloat(size.width), height: CGFloat(size.height))" in sizing
    assert "@available(iOS 18.0, *)\nprivate struct WindowSheetSizing" in mac
    # Manage's pages at the readable width - by the rule the album's page has; Change password as it was
    routes = bare(app["Shared/Routes.swift"])
    destinations = _body(routes, "func appRoutes() -> some View {")
    for case, page in MANAGE_PAGES.items():
        assert f"case .{case}: {page}.readableOnMac()\n" in destinations, case
    assert "case .changePassword: ChangePasswordScreen()\n" in destinations


def test_tab_moves_between_the_fields_and_return_in_one_never_applies():
    app = app_sources()
    #? every page or sheet of the editor and Manage whose fields have an order: Tab follows it, through Platform's one
    #? helper (MacMenu.tab), each field's own
    TABS = {"Edit/ReleasePage.swift": 1, "Edit/TagsPages.swift": 1, "Manage/PeopleSheets.swift": 6,
            #? (manual search, slice A1) Search Soulseek's Artist and Album
            "Get/ManualSearchSheet.swift": 2}
    found = {}
    for name, text in app.items():
        if name == PLATFORM:
            continue
        code = bare(text)
        assert "onKeyPress" not in code, f"{name}: a key only through Platform's helpers"
        count = code.count(".tabs($focused, in: Self.order)")
        if count:
            found[name] = count
            # each right after its field's own focus
            assert count == len(re.findall(r"\.focused\(\$focused, equals: [\w.]+\)\n\s*\.tabs\(\$focused, in: Self\.order\)",
                                            code)), name
    assert found == TABS
    release = bare(app["Edit/ReleasePage.swift"])
    assert "private static let order: [Field] = [.artist, .album, .year, .originalYear, .edition]" in release
    fields = _body(release, "private var fieldsSection: some View {")
    assert re.findall(r"field\(EditWords\.\w+, \\\.\w+, \.(\w+)", fields) == ["artist", "album", "year", "originalYear", "edition"]
    tags = bare(app["Edit/TagsPages.swift"])
    assert "private static let order = TagEdit.sections.flatMap" in tags
    assert "ForEach(TagEdit.sections, id: \\.title)" in tags, "drawn in the sections' order, Tab's order"
    people = bare(app["Manage/PeopleSheets.swift"])
    assert "private static let order: [Field] = [.user, .name, .password, .again]" in people
    assert "private static let order: [Field] = [.password, .again]" in people
    manual = bare(app["Get/ManualSearchSheet.swift"])
    assert "private static let order: [Field] = [.artist, .album]" in manual
    assert manual.index("TextField(ManualSearch.artistField") < manual.index("TextField(ManualSearch.albumField")
    mac, phone = _halves()
    tab = _body(mac, "func tabs<Field: Hashable>(_ focused: FocusState<Field?>.Binding, in order: [Field]) -> some View {")
    assert "onKeyPress(keys: [.tab, Platform.backTab])" in tab
    assert "let back = press.key == Platform.backTab || press.modifiers.contains(.shift)" in tab
    assert "guard let next = MacMenu.tab(order, from: focused.wrappedValue, back: back) else { return .ignored }" in tab
    assert tab.index("focused.wrappedValue = next") < tab.index("return .handled")
    assert "static let backTab = KeyEquivalent(Character(Unicode.Scalar(UInt8(0x19))))" in mac
    # Return in a field never applies, deletes or saves: in the editor and Manage's pages a field's Return moves to the
    # next field, puts the keyboard away, searches or unlocks People (a password checked, nothing written) - nothing else
    allowed = re.compile(r"\.onSubmit(?: \{ focused = (?:\.\w+|nil|false) \}| \{ people\.unlock\(\) \}|\(of: \.search\) \{)")
    for name, text in app.items():
        if not (name.startswith("Edit/") or name.startswith("Manage/")):
            continue
        code = bare(text)
        for submit in re.finditer(r"\.onSubmit\b[^\n]*", code):
            assert allowed.match(submit.group(0)), f"{name}: {submit.group(0)}"
        assert "defaultAction" not in code and "keyboardShortcut" not in code, name
    search = _body(bare(app["Edit/ReleasePage.swift"]), ".onSubmit(of: .search) {")
    assert "apply" not in search.lower() and "write" not in search.lower(), "Choose a release's Return searches"
    # (manual search, slice A1) Search Soulseek: Return in Artist moves to Album, Return in Album searches - never a Get
    manual = bare(app["Get/ManualSearchSheet.swift"])
    assert re.findall(r"\.onSubmit\b[^\n]*", manual) == [".onSubmit { focused = .album }", ".onSubmit { search() }"]
    assert "defaultAction" not in manual and "keyboardShortcut" not in manual
    searched = _body(manual, "private func search() {")
    assert searched.split("\n", 1)[1].lstrip().startswith("guard searchable, !showing else { return }")
    assert "download" not in searched and "onQueued" not in searched, "Search pushes the results; only a card's Get gets"


def test_a_run_under_way_says_what_quitting_does_on_the_mac():
    app = app_sources()
    care = bare(app["Manage/LibraryCareScreen.swift"])
    kind = _body(care, "private func kindSection(_ kind: BulkTargets.Kind, online: Bool) -> some View {")
    running = kind[kind.index("if let stop = runs.stopLabel(kind) {"):kind.index("} else if let targets, !targets.isEmpty {")]
    assert running.index("Text(LibraryCare.screenOnNote)") < running.index(
        "if let quit = LibraryCare.quitNote(Platform.device, kind: kind) {\n                    Text(quit)")
    group = bare(app["Manage/ServerSettingsGroupScreen.swift"])
    retime = group[group.index("if run.running {"):]
    retime = retime[:retime.index("} else {")]
    assert retime.index("Text(RetimeRun.screenOnNote)") < retime.index(
        "if let quit = RetimeRun.quitNote(Platform.device) {\n                    Text(quit)")
    #? no veto of a quit: Catalyst has no applicationShouldTerminate, and a run is the app's own - so it says, never asks
    for name, text in app.items():
        code = bare(text)
        assert "applicationShouldTerminate" not in code and "terminate(" not in code, name
    # the words are Core's, by the device: nothing on the iPhone
    words = (CORE / "LibraryCare.swift").read_text(encoding="utf-8")
    assert 'device == .mac ? "Quitting deadwax stops the run - open deadwax again, and \\(label(kind)) carries on." : nil' in words
    retimed = (CORE / "ServerSettings.swift").read_text(encoding="utf-8")
    assert 'device == .mac ? "Quitting deadwax stops it - open deadwax again, and running it again carries on." : nil' in retimed


def _load_script(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_script_{name}", IOS / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
