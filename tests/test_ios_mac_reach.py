"""
The Mac redesign keeps each device to its own drawing (slice R1, the build plan's section 1; notes/ios.md "The Mac
redesign, slice R1: the frame and the shared pieces", and since R1b "The redesign, slice R1b: the shared look, and the
phone's pieces"). App/Mac's, App/Look's and App/Phone's views all compile into both builds (one target), so what keeps
each device's look on its own device is who names them - three zones (the build plan's section 1, from R1b):

  - The Mac's: App/Mac's types, and the modifiers it declares, are named only from App/Mac and the Mac's frame files -
    DesktopFrame, MacSidebarView, PlayerBar, MacPanels, and Platform's Mac half. A phone file that named one would put
    the Mac's look on the phone. So are the redesign's Mac pieces declared elsewhere: Typeface's Mac namespace,
    DWCorners' Mac half, and Core's MacLook (the sizes), MacTable (the lists) and MacInFront (the page in front).
    App/Look, both devices', names none of them either: what it draws on the phone would be the Mac's.
  - The phone's: App/Phone's types and modifiers - and Typeface's Phone namespace, DWCorners' phone half and Core's
    PhoneLook and PhonePieceWords - are never named from App/Mac, the Mac's frame files, Platform's Mac half or
    App/Look.
  - The look's: App/Look's types (and Core's DWLook, Typeface's Look namespace) may be named from anywhere: each draws
    its own device's sizes, corners and type.
  - Platform's iPhone half is `self` or nothing in every helper but the few that were the iPhone's own before the Mac
    (pull to refresh, Search's field, the dialogs' Cancel, the battery, the idle timer): a helper given a body there
    would change the phone.
  - The Mac's own routes: DesktopFrame's four stacks are MacTabStack, a NavigationStack with `.macRoutes()` and never
    the phone's appRoutes; MacRoutes says every AppRoute once, each to the area that owns it, and each area's page is
    still the phone's own (as appRoutes draws it) until its slice redraws it - so MainTabs, TabStack and appRoutes keep
    no diff.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
MAC = APP / "Mac"
PLATFORM = "Shared/Platform.swift"
#? the Mac's frame: the files that may name App/Mac's types (Platform's Mac half too - read apart, below)
FRAME_FILES = {"Root/DesktopFrame.swift", "Root/MacSidebarView.swift", "Player/PlayerBar.swift", "Player/MacPanels.swift"}


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_reach_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def app_sources() -> dict[str, str]:
    return {path.relative_to(APP).as_posix(): path.read_text(encoding="utf-8") for path in sorted(APP.rglob("*.swift"))}


def halves(code: str | None = None) -> tuple[str, str]:
    """Platform.swift's Mac half and iPhone half."""
    code = bare(app_sources()[PLATFORM]) if code is None else code
    mac = code.split("\n#if targetEnvironment(macCatalyst)\n", 1)[1].split("\n#else\n")[0]
    return mac, code.split("\n#else\n", 1)[1].split("\n#endif\n")[0]


def body(code: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = code.index(start)
    opened = code.index("{", at)
    depth = 0
    for i in range(opened, len(code)):
        depth += {"{": 1, "}": -1}.get(code[i], 0)
        if depth == 0:
            return code[at:i + 1]
    raise AssertionError(f"unclosed: {start}")


LOOK = APP / "Look"
PHONE = APP / "Phone"


def mac_names(folder: Path = MAC) -> set[str]:
    """What a folder (App/Mac, unless said) declares that another file could name: its types, and the modifiers and
    styles it adds in its extensions."""
    names = set()
    for path in sorted(folder.rglob("*.swift")):
        code = bare(path.read_text(encoding="utf-8"))
        names |= set(re.findall(r"^(?:@MainActor\s+)?(?:final\s+)?(?:struct|enum|class|protocol|typealias)\s+(\w+)",
                                code, re.M))
        for extension in re.finditer(r"^extension \w+\b[^{]*\{", code, re.M):
            names |= set(re.findall(r"\b(?:func|var) (\w+)\b", body(code, extension.group(0))))
    return names


#? the redesign's own Mac pieces declared outside App/Mac: Core's sizes, lists and page in front - and Typeface's and
#? DWCorners' Mac halves, matched as `Typeface.Mac` and `DWCorners.Mac` (Typeface and DWCorners are the phone's too)
REDESIGN_ELSEWHERE = {"MacLook", "MacTable", "MacInFront"}
#? the phone's own pieces declared outside App/Phone: Core's sizes - and Typeface's and DWCorners' phone halves
PHONE_ELSEWHERE = {"PhoneLook", "PhonePieceWords"}


def reach_pattern(names: set[str]) -> re.Pattern:
    """A use of one of the redesign's Mac names: App/Mac's, the Core pieces', Typeface.Mac or DWCorners.Mac."""
    every = sorted(names | REDESIGN_ELSEWHERE, key=len, reverse=True)
    return re.compile(r"\bTypeface\.Mac\b|\bDWCorners\.Mac\b|\b(" + "|".join(every) + r")\b")


def phone_pattern(names: set[str]) -> re.Pattern:
    """A use of one of the phone's own names: App/Phone's, PhoneLook, PhonePieceWords, Typeface.Phone or
    DWCorners.Phone."""
    every = sorted(names | PHONE_ELSEWHERE, key=len, reverse=True)
    return re.compile(r"\bTypeface\.Phone\b|\bDWCorners\.Phone\b|\b(" + "|".join(every) + r")\b")


def the_macs(name: str) -> bool:
    """Whether a file is the Mac's own: App/Mac's, or a frame file."""
    return name.startswith("Mac/") or name in FRAME_FILES


def reach_problems(sources: dict[str, str]) -> list[str]:
    """Every name used outside its zone: a Mac name anywhere but the Mac's own files (and Platform's Mac half) - App/Look
    included; a phone name in the Mac's own files, Platform's Mac half or App/Look."""
    mac, phone = reach_pattern(mac_names()), phone_pattern(mac_names(PHONE))
    left = []
    for name, text in sources.items():
        code = bare(text)
        if name == PLATFORM:
            outside, mac_half = code.split("\n#if targetEnvironment(macCatalyst)\n", 1)[0] + halves(code)[1], halves(code)[0]
            left += [f"{name}: {found.group(0)}" for found in mac.finditer(outside)]
            left += [f"{name} (its Mac half): {found.group(0)}" for found in phone.finditer(mac_half)]
            continue
        if not the_macs(name):
            left += [f"{name}: {found.group(0)}" for found in mac.finditer(code)]
        if the_macs(name) or name.startswith("Look/"):
            left += [f"{name}: {found.group(0)}" for found in phone.finditer(code)]
    return left


def test_app_mac_is_named_only_from_the_macs_frame():
    names = mac_names()
    # what R1 declares, read: the look, the components, the frame's parts, the areas - and the modifiers (since R1b
    # the shared look's are App/Look's, below)
    for name in ("MacPalette", "MacTitleStrip", "MacToolbar", "MacCheckbox", "MacFolderTabs", "MacGroupBox",
                 "MacStatusBar", "MacKeyStyle", "MacDisplay", "MacOutput", "MacTabStack", "MacRoutes", "MacPage",
                 "MacTitle", "MacSelection", "MacStatusItems", "MacLibrary", "MacAlbum", "MacArtist", "MacSearch",
                 "MacRequests", "MacSettings", "MacEdit", "MacManage", "macRoutes", "macStatus", "macSelects"):
        assert name in names, name
    # R1's shared pieces left App/Mac in R1b, for App/Look under DW names
    for gone in ("MacCorners", "MacButtonStyle", "MacField", "MacSegmented", "MacPopUp", "MacRaised", "MacRule",
                 "MacWell", "MacFieldRow", "MacChip", "MacCount", "MacCaret", "MacToggleStyle"):
        assert gone not in names, gone
    left = reach_problems(app_sources())
    assert not left, left


def test_the_three_zones_are_read():
    look, phone = mac_names(LOOK), mac_names(PHONE)
    assert {"DWPalette", "DWCorners", "DWRaised", "DWRule", "DWButtonStyle", "DWWell", "DWField", "DWFieldRow", "DWChip",
            "DWCount", "DWSegmented", "DWPopUp", "DWCaret", "DWToggleStyle", "DWTarget", "lookHeight",
            "lookSquare"} <= look, look
    assert {"PhoneStrip", "PhoneTop", "PhoneBack", "PhoneBigTitle", "PhoneTabItem", "PhoneLitLine", "PhoneMiniGround",
            "PhoneSeekLine", "PhoneCard", "PhoneGroup", "PhoneKV", "PhoneGo", "PhoneChevron", "PhoneSwitchStyle",
            "phoneSwitch", "PhoneFoot", "phoneFoot", "PhoneMeta", "PhoneMetaLink"} <= phone, phone
    # no name in two zones
    assert not (look & phone) and not (look & mac_names()) and not (phone & mac_names())
    # the look's pieces may be named from anywhere: the Mac's patterns and the phone's take none of them
    for planted in ("Text(x).foregroundStyle(DWPalette.t2)", "Button(x) { }.buttonStyle(DWButtonStyle(kind: .pri))",
                    "DWChip(words: w)", "view.lookHeight(DWLook.here.rowHeight)", "Text(x).font(Typeface.Look.text(.chip))",
                    "DWCorners.buttonShape"):
        code = bare(planted + "\n")
        assert not reach_pattern(mac_names()).search(code) and not phone_pattern(phone).search(code), planted


def test_the_reach_matcher_catches_a_phone_file_naming_the_mac():
    names = mac_names()
    pattern = reach_pattern(names)
    for planted in ("Text(x).foregroundStyle(MacPalette.t2)", "view.macStatus(items)", "MacToolbar { }",
                    "Text(x).font(Typeface.Mac.text(.base))", ".frame(height: CGFloat(MacLook.rowHeight))",
                    "let striped = MacTable.stripes(lines)", "var front = MacInFront<UUID, Int>()"):
        assert pattern.search(bare(planted + "\n")), planted
    # a phone file planted with one is caught by the test itself
    sources = app_sources()
    playing = bare(sources["Player/NowPlayingView.swift"])
    assert not pattern.search(playing)
    for planted in ("Typeface.Mac.text(.base)", "MacLook.rowHeight"):
        assert pattern.search(playing + f"\nlet planted = {planted}\n"), planted
    # the phone's own Typeface is not the Mac's
    assert not pattern.search(bare("Text(x).font(Typeface.body)\nTypeface.symbol(size: 11)\nTypeface.family\n"))
    # a word in a comment or a string is never a use
    assert not pattern.search(bare('// MacPalette\nlet s = "MacToolbar"\n'))
    # the iPhone's own names that only start alike are not the Mac's
    assert not pattern.search(bare("MacFrame.sidebarWidth\nMacSidebar.label(row)\nMacPanel(panel: p)\n"))
    # DWCorners' Mac half is the Mac's; the corners the look takes on either device are not
    assert pattern.search(bare("let r = DWCorners.Mac.button\n")) and not pattern.search(bare("DWCorners.button\n"))


def test_the_reach_catches_each_zone_out_of_place():
    sources = app_sources()
    assert not reach_problems(sources)
    phone = phone_pattern(mac_names(PHONE))
    for planted in ("PhoneStrip(options: o, words: w, shown: $s, spoken: x)", "Text(x).font(Typeface.Phone.text(.strip))",
                    ".frame(minHeight: CGFloat(PhoneLook.strip))", "let r = DWCorners.Phone.button",
                    "Toggle(isOn: $on) { }.toggleStyle(.phoneSwitch)", "page.phoneFoot { }"):
        assert phone.search(bare(planted + "\n")), planted
    # a phone piece in App/Mac, in a frame file, in Platform's Mac half or in App/Look; a Mac piece in App/Look
    for name, planted in (("Mac/Components/MacToolbar.swift", "PhoneChevron()"),
                          ("Root/MacSidebarView.swift", "PhoneLook.strip"),
                          ("Look/DWChip.swift", "PhoneLook.strip"),
                          ("Look/DWChip.swift", "MacPalette.titleFace"),
                          ("Look/DWButtonStyle.swift", "Typeface.Mac.text(.base)"),
                          ("Look/DWSegmented.swift", "MacLook.segmentHeight")):
        planted_sources = dict(sources)
        planted_sources[name] = sources[name] + f"\nlet planted = {planted}\n"
        assert reach_problems(planted_sources), (name, planted)
    mac_half = sources[PLATFORM].replace("\n#else\n", "\n    let planted = PhoneLook.strip\n#else\n", 1)
    assert reach_problems({**sources, PLATFORM: mac_half})
    # a phone piece on a phone screen, or the look anywhere, is no problem of the reach's (drawn nowhere yet is
    # test_ios_phone_look.py's)
    for name, planted in (("Player/NowPlayingView.swift", "PhoneLook.strip"), ("Library/LibraryView.swift", "DWPalette.t2"),
                          ("Mac/Components/MacToolbar.swift", "DWChip(words: w)")):
        assert not reach_problems({**sources, name: sources[name] + f"\nlet planted = {planted}\n"}), (name, planted)


#? Platform's iPhone half: the helpers that were the iPhone's own before the Mac, each with its body as it was
#? (test_ios_mac.py holds each exactly); every other is `self`, or does nothing
PHONE_BODIES = {"pullToRefresh", "searchField", "dialogCancel", "power", "keepDisplayOn"}


def test_platforms_iphone_half_does_nothing_new():
    _, phone = halves()
    funcs = list(re.finditer(r"\bfunc (\w+)(?:<[^>]*>)?\(", phone))
    assert len(funcs) > 25, "the iPhone half is read"
    loose = []
    for found in funcs:
        name = found.group(1)
        text = body(phone, phone[found.start():].split("\n", 1)[0].strip())
        inside = text[text.index("{") + 1:text.rindex("}")].strip()
        if name in PHONE_BODIES:
            continue
        if inside not in ("", "self"):
            loose.append(f"{name}: {inside[:60]}")
    assert not loose, loose
    # R1's two: the window's name and a dialog's Return, nothing on the phone
    assert re.search(r"@MainActor static func nameWindow\(_ name: String\) \{\}", phone)
    assert re.search(r"func returnPresses\(\) -> some View \{\s*self\s*\}", phone)
    mac, _ = halves()
    assert re.search(r"func returnPresses\(\) -> some View \{\s*keyboardShortcut\(\.defaultAction\)\s*\}", mac)
    name = body(mac, "@MainActor static func nameWindow(_ name: String) {")
    assert "windowName = name" in name and "scene.title = name" in name and "mainScenes.allObjects" in name
    # a window shaped after it is named is named too: shape() sets the name last asked
    shape = body(mac, "@MainActor private static func shape(_ scene: UIWindowScene) {")
    assert "if !windowName.isEmpty { scene.title = windowName }" in shape
    assert "titlebar?.titleVisibility = .hidden" in shape, "the title strip draws the title: the bar shows none"


# ----------------------------------------------------------------------------- the page in front, and the window's name

def test_the_frames_stores_keep_the_page_in_front_by_core():
    # the status bar's facts and Info's selection: the page in front's, kept by Core's MacInFront (tested there) - a
    # page's change made where it is, never putting a page off the screen in front (R1's review, finding 5)
    app = app_sources()
    status, selection = bare(app["Mac/Frame/MacStatusItems.swift"]), bare(app["Mac/Frame/MacSelection.swift"])
    assert "private var pages = MacInFront<UUID, Items>()" in status
    assert "private var pages = MacInFront<UUID, Subject?>()" in selection
    for code, said, changed, gone in ((status, r"func say\(_ items: Items, from page: UUID\) \{\s*pages\.appeared\(page, saying: items\)",
                                       r"func change\(_ items: Items, from page: UUID\) \{\s*pages\.changed\(page, to: items\)\s*\}",
                                       r"func forget\(_ page: UUID\) \{\s*pages\.gone\(page\)\s*\}"),
                                      (selection, r"func appeared\(_ page: UUID, selecting subject: Subject\?\) \{\s*"
                                                  r"pages\.appeared\(page, saying: subject\)",
                                       r"func select\(_ subject: Subject\?, by page: UUID\) \{\s*pages\.changed\(page, to: subject\)\s*\}",
                                       r"func letGo\(by page: UUID\) \{\s*pages\.gone\(page\)\s*\}")):
        assert re.search(said, code) and re.search(changed, code) and re.search(gone, code)
    # each page says it as it comes on, changes it while it's there, and lets it go as it leaves
    assert re.search(r"\.onAppear \{ status\?\.say\(items, from: page\) \}\s*\.onChange\(of: items\) \{[^}]*"
                     r"status\?\.change\(now, from: page\)\s*\}\s*\.onDisappear \{ status\?\.forget\(page\) \}", status)
    assert re.search(r"\.onAppear \{ selection\?\.appeared\(page, selecting: subject\) \}\s*\.onChange\(of: subject\) \{[^}]*"
                     r"selection\?\.select\(now, by: page\)\s*\}\s*\.onDisappear \{ selection\?\.letGo\(by: page\) \}",
                     selection)
    assert "subject = " not in selection and "owner" not in selection, "the selection is MacInFront's, kept nowhere else"


def test_the_window_is_named_for_what_is_up():
    app = app_sources()
    # a playlist's page by the list as it is now - a rename in Edit renames the window - its preview only until then
    page = bare(app["Mac/Frame/MacPage.swift"])
    named = body(page, "static func named(_ route: AppRoute, playlists: [Playlist]) -> String? {")
    assert re.search(r"case \.playlist\(let playlist\):\s*name = playlists\.first \{ \(listed: Playlist\) -> Bool in "
                     r"listed\.id == playlist\.id \}\?\.name \?\? playlist\.preview\?\.name", named)
    assert "playlists: playlists ?? []" in body(page, "static func title(_ navigation: AppNavigation")
    assert "named(top, playlists: playlists)" in page
    # a launch screen in place of the app names it too: Sign in after a sign-out; none with the app up
    root = bare(app["Root/RootView.swift"])
    assert ".shapesWindow()\n        // " in app["Root/RootView.swift"] and ".namesWindow(gateName)" in root
    gate = body(root, "private var gateName: String? {")
    assert re.search(r"case \.ready: return nil\s*case \.signedOut: return SignInWords\.signIn\s*"
                     r"case \.needsAddress, \.checking, \.unreachable: return SignInWords\.title", gate)
    mac, phone = halves()
    assert re.search(r"func namesWindow\(_ name: String\?\) -> some View \{\s*self\s*\}", phone)
    assert re.search(r"func namesWindow\(_ name: String\?\) -> some View \{\s*onChange\(of: name, initial: true\) "
                     r"\{ \(_: String\?, now: String\?\) -> Void in\s*if let now \{ Platform\.nameWindow\(now\) \}\s*\}\s*\}", mac)


# ----------------------------------------------------------------------------- the Mac's own routes

def app_route_cases() -> list[str]:
    routes = bare(app_sources()["Shared/Routes.swift"])
    enum = body(routes, "enum AppRoute: Hashable {")
    return re.findall(r"^\s*case (\w+)", enum, re.M)


def test_the_frame_stacks_are_the_macs_with_its_own_routes():
    app = app_sources()
    stack = bare(app["Mac/Frame/MacTabStack.swift"])
    assert ".macRoutes()" in stack and "appRoutes" not in stack
    assert re.search(r"NavigationStack\(path: \$path\) \{\s*root\s*\.clearsPlayer\(\)\s*\.showsOfflineBanner\(!ownTop\)\s*"
                     r"\.toolbar\(\.hidden, for: \.tabBar\)\s*\.macRoutes\(\)\s*\}", stack)
    assert stack.count(".toolbar(.hidden, for: .tabBar)") == 2, "the system's bar hidden on the stack and every page"
    frame = bare(app["Root/DesktopFrame.swift"])
    page = body(frame, "private var page: some View {")
    assert page.count("MacTabStack(") == 4 and not re.search(r"(?<!Mac)TabStack\(", page)
    for tab, root in (("library", "MacLibrary.root()"), ("search", "MacSearch.root()"),
                      ("requests", "MacRequests.root()"), ("you", "MacSettings.root()")):
        assert re.search(r"MacTabStack\(path: paths\." + tab + r"(, ownTop: true)?\) \{ " + re.escape(root) +
                         r" \}\s*\.tag\(AppTab\." + tab + r"\)", page), tab
    # each root the phone's own, as MainTabs draws it
    for area, view in (("Library/MacLibrary.swift", "LibraryView()"), ("Search/MacSearch.swift", "SearchScreen()"),
                       ("Requests/MacRequests.swift", "RequestsScreen()"), ("Settings/MacSettings.swift", "YouView()")):
        assert re.search(r"static func root\(\) -> some View \{\s*" + re.escape(view) + r"\s*\}", bare(app["Mac/" + area]))
    # macRoutes: what appRoutes gives every page - the room for the notice, the offline banner, iOS's tab bar hidden
    routes = bare(app["Mac/Frame/MacRoutes.swift"])
    assert re.search(r"navigationDestination\(for: AppRoute\.self\) \{ \(route: AppRoute\) in\s*MacRoutes\.page\(for: route\)"
                     r"\s*\.clearsPlayer\(\)\s*\.showsOfflineBanner\(\)\s*\.toolbar\(\.hidden, for: \.tabBar\)\s*\}", routes)
    # the iPhone's are as they were: MainTabs' stacks are TabStack's, on appRoutes
    tabs = bare(app["Root/MainTabs.swift"])
    assert "MacTabStack" not in tabs and "macRoutes" not in tabs
    assert body(tabs, "struct TabStack").count(".appRoutes()") == 1


def test_mac_routes_says_every_route_once_each_to_its_area():
    cases = app_route_cases()
    assert len(cases) == 30, cases
    routes = bare(app_sources()["Mac/Frame/MacRoutes.swift"])
    switch = body(routes, "switch route {")
    said = re.findall(r"^\s*case \.(\w+)\b[^:]*: (Mac\w+)\.page\(for: \.(\w+)\b", switch, re.M)
    assert sorted(case for case, _, _ in said) == sorted(cases), set(cases) ^ {case for case, _, _ in said}
    assert len(said) == len(set(case for case, _, _ in said)), "each once"
    for case, area, page in said:
        assert page == case, f".{case} is the area's .{page}: one name for one page"
    assert "default:" not in switch, "every route said: a new one is a build error until the Mac places it"


#? The routes R1 leaves as the phone's pages, each exactly as appRoutes draws it. A slice that redraws a page takes its
#? route off this list.
PHONES_PAGES = {"album", "albums", "downloaded", "downloads", "serverAddress", "debug", "eq", "gettingAlbums", "playback",
                "account", "thisPhone", "about", "playlist", "downloadedPlaylists", "artist", "artists", "allSongs",
                "group", "mbArtist", "topSongs", "chooseFolder", "needsALook", "libraryCare", "heldByNobody",
                "serverSettings", "serverSettingsGroup", "eventLog", "changePassword", "people", "person"}


def normalised(line: str) -> tuple[str, str]:
    """A switch case's pattern and its page, with the binding's name made one: `case .x(let y): Page(route: y)`."""
    found = re.match(r"case \.(\w+)(?:\(let (\w+)\))?: (.+)$", line.strip())
    assert found, line
    case, binding, page = found.groups()
    if binding:
        page = re.sub(rf"\b{binding}\b", "_", page)
    return case, page.strip()


def test_every_area_page_is_still_the_phones_own():
    app = app_sources()
    routes = bare(app["Shared/Routes.swift"])
    destinations = body(routes, "func appRoutes() -> some View {")
    phone = dict(normalised(line) for line in re.findall(r"^\s*case \.\w+[^\n]*: [^\n]+$", body(destinations, "switch route {"), re.M))
    assert set(phone) == set(app_route_cases())
    areas = {}
    for path in sorted(MAC.rglob("*.swift")):
        code = bare(path.read_text(encoding="utf-8"))
        if "static func page(for page: Page) -> some View {" not in code:
            continue
        switch = body(body(code, "static func page(for page: Page) -> some View {"), "switch page {")
        areas[path.relative_to(MAC).as_posix()] = dict(
            normalised(line) for line in re.findall(r"^\s*case \.\w+[^\n]*: [^\n]+$", switch, re.M))
    assert set(areas) == {"Library/MacLibrary.swift", "Album/MacAlbum.swift", "Artist/MacArtist.swift",
                          "Search/MacSearch.swift", "Settings/MacSettings.swift", "Edit/MacEdit.swift",
                          "Manage/MacManage.swift"}
    drawn = {}
    for area, pages in areas.items():
        for case, page in pages.items():
            assert case not in drawn, f".{case} in two areas"
            drawn[case] = page
    assert set(drawn) == set(phone), set(drawn) ^ set(phone)
    for case in sorted(PHONES_PAGES):
        assert drawn[case] == phone[case], f".{case}: the Mac's {drawn[case]} is not the phone's {phone[case]}"
