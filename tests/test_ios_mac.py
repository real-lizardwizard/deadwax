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
    assert re.search(r"func macWindow\(_ menus: MacCommands\) -> some Scene \{\s*self\s*\}", phone)
    assert re.search(r"static func launching\(\) \{\}", phone)
    # (slice 2) every helper the Mac's alone: the view itself on the iPhone - no key, no menu, no long press added
    for helper in (r"refreshCommand\(_ action: @escaping @MainActor @Sendable \(\) async -> Void\)",
                   r"macContextMenu<Items: View>\(@ViewBuilder _ items: \(\) -> Items\)",
                   r"albumRightClick\(_ route: AlbumRoute\)", r"playlistRightClick\(_ route: PlaylistRoute\)",
                   r"escapeCloses\(_ on: Bool = true\)", r"returnCancels\(\)", r"findField\(\)", r"oneWindow\(\)"):
        assert re.search(r"func " + helper + r" -> some View \{\s*self\s*\}", phone), helper
        assert re.search(r"func " + helper + r" -> some View \{", mac), helper
    assert re.search(r"static func dialogCancel\(\) -> some View \{\s*EmptyView\(\)\s*\}", phone)
    assert "keyboardShortcut" not in phone and "contextMenu" not in phone and "commands" not in phone
    # the Mac's: no refresh control at all - (slice 2) the same action on ⌘R - the window phone-shaped, New Window and
    # Help gone, and deadwax's menus
    assert re.search(r"func pullToRefresh\(_ action: @escaping @MainActor @Sendable \(\) async -> Void\) -> some View \{\s*"
                     r"refreshCommand\(action\)\s*\}", mac)
    assert re.search(r"func refreshCommand\([^)]*\)[^{]*\{\s*modifier\(MacRefreshing\(action: action\)\)\s*\}", mac)
    assert re.search(r"func macContextMenu<[^{]*\{\s*contextMenu\(menuItems: items\)\s*\}", mac)
    assert re.search(r"func escapeCloses\([^{]*\{\s*keyboardShortcut\(on \? \.cancelAction : nil\)\s*\}", mac)
    assert re.search(r"func returnCancels\(\) -> some View \{\s*keyboardShortcut\(\.defaultAction\)\s*\}", mac)
    assert re.search(r"func oneWindow\(\) -> some View \{\s*handlesExternalEvents\(preferring: \[\"\*\"\], allowing: \[\"\*\"\]\)\s*\}",
                     app_sources()[PLATFORM].split("\n#else\n")[0])
    assert re.search(r"\.commands \{\s*CommandGroup\(replacing: \.newItem\) \{\}\s*CommandGroup\(replacing: \.help\) \{\}\s*menus\s*\}", mac)
    assert "TextEditing.shared.start()" in mac.split("static func launching()")[1].split("\n    }\n")[0]
    assert "refreshable" not in mac
    assert "CommandGroup(replacing: .newItem) {}" in mac and "CommandGroup(replacing: .help) {}" in mac
    for size in ("CGSize(width: 390, height: 640)", "widest: CGFloat = 600", "CGSize(width: 430, height: 860)"):
        assert size in mac
    assert "sizeRestrictions?.minimumSize" in mac and "sizeRestrictions?.maximumSize" in mac
    assert "titlebar?.titleVisibility = .hidden" in mac


def test_the_app_is_wired_to_platform():
    app = app_sources()
    root = bare(app["DeadwaxApp.swift"])
    assert root.count(".macWindow(MacCommands(player: player, navigation: navigation, server: server))") == 1, \
        "the scene's Mac window and (slice 2) its menus"
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
    assert ".onAppear { MacRefresh.shared.appeared(page) }" in commands
    assert ".onDisappear { MacRefresh.shared.went(page) }" in commands
    run = commands[commands.index("func run() {"):]
    run = run[:run.index("\n    }\n")]
    assert "guard !running, let page = shown.last, page.action != nil else { return }" in run
    assert run.index("running = true") < run.index("await page.action?()") < run.index("running = false")


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
                  "CommandGroup(after: .toolbar) {\n            item(.refresh, state)"):
        assert group in commands, group
    # the state each time it's drawn, from the player and the window
    state = commands[commands.index("private var state: MacMenu.State {"):commands.index("var body: some Commands {")]
    for read in ("queued: player.hasQueue", "playing: player.isPlaying", "shuffle: player.shuffle",
                 "paged: player.paged?.scope", "repeatMode: player.repeatMode", "length: player.duration",
                 "PlayedAlbum.route($0, player: player)", "typing: TextEditing.shared.typing",
                 "tabs: server.launch == .ready && server.signInOver == nil", "refresh: MacRefresh.shared.state",
                 "nowPlaying: navigation.nowPlayingShown"):
        assert read in state, read
    # each click as the player's button makes it, read again as it lands
    perform = commands[commands.index("private func perform("):commands.index("static func shortcut(")]
    assert "let now = MacMenu.item(command, state)\n        guard now.enabled else { return }" in perform
    for call in ("navigation.showSettings()", "navigation.find()", "MacRefresh.shared.run()", "player.toggle()",
                 "player.next()", "player.previous()",
                 "MacMenu.skip(command, from: player.shownPosition, length: player.duration) { player.seek(to: to) }",
                 "player.toggleShuffle()", "player.setRepeat(mode)", "navigation.openAlbum(route)"):
        assert call in perform, call
    # no volume of deadwax's own (audio fidelity first), and nothing of the engine's
    assert not re.search(r"(?i)volume|gain", code)
    # every MacMenu command is drawn once
    core = (CORE / "MacMenu.swift").read_text(encoding="utf-8")
    cases = re.findall(r"^\s*case ([a-z][\w, ]*)$", bare(core[core.index("public enum Command"):core.index("public static let repeats")]), re.M)
    every = [name.strip() for line in cases for name in line.split(",")]
    assert every == ["settings", "find", "refresh", "playPause", "next", "previous", "forward", "back", "shuffle",
                     "repeatOff", "repeatAll", "repeatOne", "goToCurrentSong"]
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


def test_find_puts_the_cursor_in_searchs_field():
    app = app_sources()
    search = bare(app["Search/SearchScreen.swift"])
    assert search.count(".findField()") == 1
    assert search.index(".searchable(") < search.index(".findField()") < search.index(".onSubmit(of: .search)")
    assert sum(bare(text).count(".findField()") for name, text in app.items() if name != PLATFORM) == 1
    routes = bare(app["Shared/Routes.swift"])
    find = routes[routes.index("func find() {"):]
    find = find[:find.index("\n    }\n")]
    assert "nowPlayingShown = false" in find and "tab = .search" in find and "backToRoot(&search)" in find
    assert "findWanted = true" in find
    settings = routes[routes.index("func showSettings() {"):]
    settings = settings[:settings.index("\n    }\n")]
    assert "tab = .you" in settings and "nowPlayingShown = false" in settings
    reset = routes[routes.index("func reset() {"):]
    reset = reset[:reset.index("\n    }\n")]
    assert "findWanted = false" in reset and "macLibraryPage = nil" in reset
    focus = bare(app["Shared/MacCommands.swift"])
    focus = focus[focus.index("struct FindFocus: ViewModifier"):]
    assert "content.searchFocused($focused)" in focus and "if #available(iOS 18.0, *) {" in focus
    assert "navigation.findTaken()" in focus


def test_the_window_comes_back_on_the_page_it_showed():
    library = bare(app_sources()["Library/LibraryView.swift"])
    assert "if page == nil { show(navigation.macLibraryPage ?? LibraryPages.first(shownOrder)) }" in library
    assert "if Platform.mac { navigation.macLibraryPage = now }" in library
    assert library.count("macLibraryPage") == 2, "written only on the Mac: nil on the iPhone, the first page as before"


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
    assert "QueueMenuRequest.album(album, gone: false" in clicks
    assert "QueueMenuRequest.playlist(answer, name: answer.playlist.name, songs: answer.songs)" in clicks
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
    "Player/NowPlayingView.swift": 1, "Playlists/PlaylistPicker.swift": 2, "Playlists/PlaylistView.swift": 1,
    "Search/PressingPickerSheet.swift": 1, "UpNext/UpNextScreen.swift": 1,
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
    assert ".escapeCloses(escapes)" in picker and "var escapes = false" in picker
    assert "NewPlaylistFields(escapes: true)" in bare(app["Playlists/PlaylistsScreen.swift"])
    # Escape on Edit album's Close and Artist images' Close: the button itself, before the question it asks
    for name in ("Edit/EditAlbumSheet.swift", "Artist/ArtistImagesSheet.swift"):
        code = bare(app[name])
        assert code.index(".escapeCloses()") < code.index(".confirmationDialog(EditWords.discardTitle")
    platform = bare(app[PLATFORM]).split("\n#else\n")[0]
    assert re.search(r"static func dialogCancel\(\) -> some View \{\s*Button\(MacMenu\.Words\.cancel, role: \.cancel\) \{\}"
                     r"\s*\.returnCancels\(\)\s*\}", platform)


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
