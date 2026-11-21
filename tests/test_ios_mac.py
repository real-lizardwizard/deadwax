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
                   r"findField\(_ focused: FocusState<Bool>\.Binding\)",
                   r"oneWindow\(\)", r"macSheet\(\)", r"keepsWindowOpen\(_ on: @autoclosure \(\) -> Bool\)",
                   r"readableOnMac\(\)", r"shapesWindow\(\)"):
        assert re.search(r"func " + helper + r" -> some View \{\s*self\s*\}", phone), helper
        assert re.search(r"func " + helper + r" -> some View \{", mac), helper
    assert re.search(r"static func dialogCancel\(\) -> some View \{\s*EmptyView\(\)\s*\}", phone)
    # (slice 3) Search's field: the navigation bar's, always drawn, exactly as SearchScreen had it - none on the Mac
    assert re.search(r"func searchField\(text: Binding<String>, prompt: String\) -> some View \{\s*"
                     r"searchable\(text: text, placement: \.navigationBarDrawer\(displayMode: \.always\), "
                     r"prompt: Text\(prompt\)\)\s*\}", phone)
    assert re.search(r"func searchField\(text: Binding<String>, prompt: String\) -> some View \{\s*self\s*\}", mac)
    assert "keyboardShortcut" not in phone and "contextMenu" not in phone and "commands" not in phone
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
    assert root.count(".macWindow(MacCommands(player: player, navigation: navigation, server: server, lyrics: lyrics))") == 1, \
        "the scene's Mac window and (slice 2) its menus - (slice 3) the lyrics' state for View > Lyrics"
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
    assert commands.count(".onAppear { MacRefresh.shared.appeared(page) }") == 2, "a page with a Refresh, a sheet's root"
    assert commands.count(".onDisappear { MacRefresh.shared.went(page) }") == 2
    run = commands[commands.index("func run() {"):]
    run = run[:run.index("\n    }\n")]
    assert "guard !running, let page = front, page.action != nil else { return }" in run
    assert run.index("running = true") < run.index("await page.action?()") < run.index("running = false")
    # (the review) the page in front is the latest page as many sheets deep as the deepest thing showing: a sheet with no
    # Refresh dims it; a page inside a sheet that has one is the page in front
    assert "pages.last { (page: Page) -> Bool in !page.sheet && page.level == deepest }" in commands
    assert "var sheetUp: Bool { deepest > 0 }" in commands
    refreshing = commands[commands.index("struct MacRefreshing: ViewModifier {"):commands.index("struct MacSheet: ViewModifier {")]
    assert "@Environment(\\.macSheetLevel) private var level" in refreshing and "page.level = level" in refreshing
    sheet = commands[commands.index("struct MacSheet: ViewModifier {"):commands.index("final class WindowWork")]
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
    for name in ("MacRefreshing", "MacSheet"):
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
                 "sidebarShown: navigation.macSidebarShown", "panel: navigation.macPanel", "lyrics: lyrics.have"):
        assert read in state, read
    # each click as the player's button makes it, read again as it lands
    perform = commands[commands.index("private func perform("):commands.index("static func shortcut(")]
    assert "let now = MacMenu.item(command, state)\n        guard now.enabled else { return }" in perform
    for call in ("navigation.showSettings()", "navigation.find()", "MacRefresh.shared.run()", "player.toggle()",
                 "player.next()", "player.previous()",
                 "MacMenu.skip(command, from: player.shownPosition, length: player.duration) { player.seek(to: to) }",
                 "player.toggleShuffle()", "player.setRepeat(mode)", "navigation.openAlbum(route)",
                 "navigation.macSidebarShown.toggle()", "if let panel = command.panel { navigation.togglePanel(panel) }"):
        assert call in perform, call
    # no volume of deadwax's own (audio fidelity first), and nothing of the engine's
    assert not re.search(r"(?i)volume|gain", code)
    # every MacMenu command is drawn once
    core = (CORE / "MacMenu.swift").read_text(encoding="utf-8")
    cases = re.findall(r"^\s*case ([a-z][\w, ]*)$", bare(core[core.index("public enum Command"):core.index("public static let repeats")]), re.M)
    every = [name.strip() for line in cases for name in line.split(",")]
    assert every == ["settings", "find", "refresh", "playPause", "next", "previous", "forward", "back", "shuffle",
                     "repeatOff", "repeatAll", "repeatOne", "goToCurrentSong", "sidebar", "upNext", "lyrics", "info"]
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
             "Search/SearchScreen.swift": 1}
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
    "Get/SourcesSheet.swift": 1, "Info/InfoView.swift": 1, "Library/LibraryView.swift": 1,
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
    "Player/NowPlayingView.swift": 4, "Playlists/PlaylistsScreen.swift": 1, "Root/MainTabs.swift": 3,
    "Search/GroupView.swift": 2, "Shared/MacRightClick.swift": 1,
    #? (slice 3) the desktop frame's: MainTabs' three over the frame - (its review) the EQ the bar's too, never a second
    "Root/DesktopFrame.swift": 3,
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
                                           ".padding(.trailing, MacFrame.makesRoom(style, panel) ? "
                                           "CGFloat(MacFrame.panelWidth) + hairline : 0)",
                                           ".overlay(alignment: .trailing) {", "if panel != .none {",
                                           "MacPanel(panel: panel)", "PlayerBar()")]
    assert order == sorted(order)
    #? (slice 3's review) the panel drawn in one place, a drawer's or a column's - crossing 1280 never draws it afresh
    assert frame.count("MacPanel(") == 1 and "if MacFrame.liesOver(style, panel) {" not in frame
    assert "MacFrame.liesOver(style, panel) ? Palette.well : Color.clear" in body
    assert ".frame(width: CGFloat(MacFrame.sidebarWidth))" in body
    assert "private var style: MacFrame.PanelStyle { MacFrame.panelStyle(width: width) }" in frame
    assert ("navigation.macPanelStyle = now" in frame
            and ".onChange(of: style, initial: true) { (_: MacFrame.PanelStyle, now: MacFrame.PanelStyle) -> Void in" in frame)
    #? the page: the tab the sidebar leads to, as its stack stands - (slice 3's review) in the iPhone's TabView, its
    #? bar hidden, so every tab's pages are kept as the tabs keep them and only the one showing is on screen
    page = frame[frame.index("private var page: some View {"):frame.index("private var watching: Watching {")]
    assert ("TabView(selection: Binding(get: { navigation.tab }, set: { (tab: AppTab) -> Void in navigation.select(tab) })) {"
            in page)
    for tab, tag in (("TabStack(path: paths.library, ownTop: true) { LibraryView() }", "library"),
                     ("TabStack(path: paths.search) { SearchScreen() }", "search"),
                     ("TabStack(path: paths.requests) { RequestsScreen() }", "requests"),
                     ("TabStack(path: paths.you) { YouView() }", "you")):
        assert re.search(re.escape(tab) + r"\s*\.tag\(AppTab\." + tag + r"\)", page), tab
    assert "switch navigation.tab {" not in page and page.count("TabStack(") == 4
    tabs = bare(app_sources()["Root/MainTabs.swift"])
    stack = tabs[tabs.index("struct TabStack"):]
    assert stack.count(".toolbar(.hidden, for: .tabBar)") == 2, "the system's bar hidden on every stack, root and pages"
    #? Search's own stand-down hears the tab change (SearchScreen), as on the iPhone: the frame's own went with the switch
    assert "standDown" not in frame
    # what MainTabs watches, this watches
    for line in (".onChange(of: watching, initial: true)", ".onAppear { requests.watch(watching) }",
                 ".onDisappear { requests.watch(.hidden) }", "queueCount.changed()", "queueCount.scene(phase)",
                 "if !queued { navigation.queueEnded() }", "sheetOpen: false)"):
        assert line in frame, line
    # MainTabs' sheets, over the frame
    for sheet in (".appSheet(isPresented: $navigation.eqImportSheet) {", ".appSheet(item: $navigation.playlistPick) {",
                  ".appSheet(item: $navigation.albumEdit, onDismiss: { navigation.editorDismissed() }) {"):
        assert sheet in frame, sheet


def test_the_panels_are_one_at_a_time_and_never_modal():
    app = app_sources()
    panels = bare(app["Player/MacPanels.swift"])
    panel = panels[panels.index("struct MacPanel: View {"):panels.index("extension EnvironmentValues")]
    for page in ("case .upNext:\n                UpNextScreen()", "case .lyrics:\n                LyricsPanel()",
                 "case .info:\n                InfoView()"):
        assert page in panel, page
    assert ".environment(\\.inSidePanel, true)" in panel and ".frame(width: CGFloat(MacFrame.panelWidth))" in panel
    assert "@Entry var inSidePanel = false" in panels
    assert "isModal" not in panels and "appSheet" not in panels
    lyrics = panels[panels.index("struct LyricsPanel: View {"):]
    assert ".onAppear {\n            lyrics.showing = true" in lyrics and ".onDisappear { lyrics.showing = false }" in lyrics
    assert "LyricsView(lyrics: shown, covered: false)" in lyrics and "LyricsWords.nothingPlaying" in lyrics
    # Up Next's and Info's Done put the panel away there, and dismiss their sheet as before on the iPhone
    for name in ("UpNext/UpNextScreen.swift", "Info/InfoView.swift"):
        code = bare(app[name])
        assert "@Environment(\\.inSidePanel) private var inSidePanel" in code, name
        assert "if inSidePanel { navigation.closePanel() } else { dismiss() }" in code, name
    routes = bare(app["Shared/Routes.swift"])
    assert "private(set) var macPanel: MacFrame.Panel = .none" in routes
    assert "macPanel = MacFrame.toggled(macPanel, panel)" in routes and "macPanel = MacFrame.afterQueueEnds(macPanel)" in routes
    album = routes[routes.index("func openAlbum(_ album: AlbumRoute) {"):]
    assert "if MacFrame.liesOver(macPanelStyle, macPanel) { macPanel = .none }" in album[:album.index("\n    }\n")]
    reset = routes[routes.index("func reset() {"):]
    assert "macPanel = .none" in reset[:reset.index("\n    }\n")]


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
    assert readable == ["album", "artist", "group", "mbArtist"]
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
