"""
The iPhone app's Settings tab, the You tab until 16 Nov (notes/ios.md "Settings, pages like iOS Settings"; James:
"also instead of "you", let's just use settings", "with maybe some better organization, and maybe some dropdowns
instead of big lists", and of the ways shown him, "Pages, like iOS Settings").

Read from the Swift source, as the other ios tests read theirs: the tab is called Settings and drawn with a gear; its
root is the headline, then rows that each push a page - Getting albums, Playback and Downloads; Manage's rows (Edit an
album pushing Choose the folder since Phase 8's slice 1, the rest still opening the web app); Account (logins on), This
phone and About - each page an AppRoute of its own; every choice that
was a list of ticks is one menu Picker row, the chosen choice's own line moved into its footer; Getting albums' three
are asked by their page (as it shows, on a pull, as deadwax comes back), /me by the root (its first show, a pull); the
tab tapped again goes back to the root, then to the top, as every tab does; and no word the app shows calls the tab You.
Core's words (YouWords.title, the departure from the web's You, ServerAddress.host, the lines that name the tab) are
held by ScreenYouTests, GetVectorTests, AddressAndCookieTests and DownloadWordsTests.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
CORE = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
YOU = APP / "You"
ROOT = YOU / "YouView.swift"
GETTING = YOU / "GettingAlbumsSection.swift"
PLAYBACK = YOU / "PlaybackSection.swift"
ACCOUNT = YOU / "AccountSection.swift"
THIS_PHONE = YOU / "ThisPhoneSection.swift"
DOWNLOADS_ROW = YOU / "DownloadsRow.swift"
MANAGE = YOU / "ManageSection.swift"
DOWNLOADS = APP / "Downloads" / "DownloadsScreen.swift"
ROUTES = APP / "Shared" / "Routes.swift"
TABS = APP / "Root" / "MainTabs.swift"

# each new page: its route, its view, and its title
PAGES = [
    ("gettingAlbums", "GettingAlbumsPage", "RequestWords.gettingAlbums", GETTING),
    ("playback", "PlaybackPage", "YouWords.playback", PLAYBACK),
    ("account", "AccountPage", "YouWords.account", ACCOUNT),
    ("thisPhone", "ThisPhonePage", "YouWords.thisPhone", THIS_PHONE),
    ("about", "AboutPage", "YouWords.about", ROOT),
]


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def partner(text: str, opening: int) -> int:
    """Where the brace at `opening` closes."""
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unbalanced braces")


def block(text: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    return text[opening + 1:partner(text, opening)]


def struct(text: str, name: str) -> str:
    found = list(re.finditer(r"\bstruct\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"struct {name} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def body(text: str) -> str:
    """A view's `var body: some View { ... }`."""
    found = list(re.finditer(r"\bvar body: some View\s*\{", text))
    assert len(found) == 1, f"var body is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def in_order(text: str, marks: list[str]) -> list[int]:
    """Where each mark first is, asserting each is there once and after the one before."""
    places = []
    for mark in marks:
        assert text.count(mark) == 1, f"{mark!r} is there {text.count(mark)} times"
        places.append(text.index(mark))
    assert places == sorted(places), f"out of order: {marks}"
    return places


def test_the_tab_is_settings_with_a_gear():
    routes = code(ROUTES)
    tab = block(routes, routes.index("{", routes.index("enum AppTab")))
    title = block(tab, tab.index("{", tab.index("var title: String")))
    symbol = block(tab, tab.index("{", tab.index("var symbol: String")))
    # the case keeps its name; its words are Core's, and nothing in the app spells the tab You
    assert "case .you: return YouWords.title" in title
    assert 'case .you: return "gearshape"' in symbol
    assert '"person.crop.circle"' not in routes
    you_lines = (CORE / "YouLines.swift").read_text(encoding="utf-8")
    assert 'public static let title = "Settings"' in you_lines
    assert 'public static let webTitle = "You"' in you_lines
    # the root's title is the tab's name
    assert ".navigationTitle(YouWords.title)" in code(ROOT)


def test_no_word_the_app_shows_calls_the_tab_you():
    # the App's code - comments off - holds no "You" of its own; Core's words that name where a setting is say Settings
    for path in sorted(APP.rglob("*.swift")):
        assert '"You"' not in code(path), path.relative_to(APP)
    named = re.compile(r"\bYou >|\bin You\b|\bYou, under\b")
    left = []
    for path in sorted(CORE.glob("*.swift")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            text = line.split("//", 1)[0]
            for literal in re.findall(r'"(?:[^"\\]|\\.)*"', text):
                if named.search(literal):
                    left.append(f"{path.name}:{number} {literal}")
    assert not left, left
    assert code(CORE / "DownloadWords.swift").count("- in Settings > Downloads.\"") == 3
    assert "in Settings, under Getting albums.\"" in code(CORE / "Sources.swift")
    assert code(CORE / "LibraryFollowWords.swift").count("in Settings > Downloads") == 2
    # the one line about the web app's own tab keeps the web's name for it
    managing = (CORE / "Managing.swift").read_text(encoding="utf-8")
    assert "Opens the web app's You: Change password is under Account there." in managing


def test_the_root_is_the_headline_then_rows_that_open_pages():
    root = body(struct(code(ROOT), "YouView"))
    in_order(root, [
        "headline(lines)",
        "if let unverified = lines.unverified",
        "NavigationLink(value: AppRoute.gettingAlbums)",
        "NavigationLink(value: AppRoute.playback)",
        "DownloadsRow()",
        "DownloadsFooter()",
        "ManageSection()",
        "if lines.account {",
        "NavigationLink(value: AppRoute.account)",
        "NavigationLink(value: AppRoute.thisPhone)",
        "NavigationLink(value: AppRoute.about)",
    ])
    # Getting albums, Playback and Downloads one group, Downloads last so its footer is under its row
    first = root.index("NavigationLink(value: AppRoute.gettingAlbums)")
    group = root[root.rindex("Section {", 0, first):root.index("ManageSection()")]
    assert "} footer: {" in group and "DownloadsFooter()" in group.split("} footer: {", 1)[1]
    # the values at the right: the server's host, the app's version - both the data face
    this_phone = root[root.index("AppRoute.thisPhone"):root.index("AppRoute.about")]
    assert "LabeledContent(YouWords.thisPhone)" in this_phone and "server.address?.host" in this_phone
    about = root[root.index("AppRoute.about"):]
    assert "LabeledContent(YouWords.about)" in about and "Text(Self.appVersion)" in about
    assert this_phone.count("Typeface.mono(.body)") == 1 and about.count("Typeface.mono(.body)") == 1
    # the sections that moved to pages are drawn nowhere on the root
    for gone in ("GettingAlbumsSection()", "PlaybackSection()", "AccountSection(", "ThisPhoneSection(",
                 "LabeledContent(YouWords.version)", "ErrorNote("):
        assert gone not in root, gone
    # the row's own section is the root's now: DownloadsRow is the row, DownloadsFooter the footer
    row = body(struct(code(DOWNLOADS_ROW), "DownloadsRow"))
    assert "Section" not in row and "NavigationLink(value: AppRoute.downloads)" in row
    footer = body(struct(code(DOWNLOADS_ROW), "DownloadsFooter"))
    assert "DownloadWords.youFooter(" in footer and "DownloadWords.storeUnreadable" in footer


def test_manage_keeps_its_rules_and_opens_the_web_app():
    manage = code(MANAGE)
    section = body(struct(manage, "ManageSection"))
    assert "let tools = Managing.tools(server.access)" in section and "if !tools.isEmpty" in section
    # (Phase 8, slice 1) Edit an album is the app's own - Choose the folder, pushed; the others open the web app
    edit = section.index("if tool == .edit {")
    queue = section.index("} else if tool == .queue {")
    assert "NavigationLink(value: AppRoute.chooseFolder)" in section[edit:queue]
    # (Phase 8, slice 6) Needs a look is the app's own too - the review queue, pushed, its count at the row's right
    care = section.index("} else if tool == .care {")
    assert "NavigationLink(value: AppRoute.needsALook)" in section[queue:care]
    # (Phase 8, slice 7) Library care is the app's own too - Rescan, the runs and In nobody's library, pushed
    assert "NavigationLink(value: AppRoute.libraryCare)" in section[care:section.index("} else if let url")]
    assert section.count("NavigationLink") == 3
    assert "WebAppRow(label: ManagingWords.label(tool), url: url, live: online)" in section
    # the footer is said of the rows drawn: Edit an album opens no Safari
    assert "ManagingWords.footer(loginsOn: server.access.on, online: online, tools: tools)" in section
    assert "openURL.webApp(url, player: player)" in body(struct(manage, "WebAppRow"))


def test_each_page_is_a_route_of_its_own():
    routes = code(ROUTES)
    route = block(routes, routes.index("{", routes.index("enum AppRoute")))
    destinations = block(routes, routes.index("{", routes.index("navigationDestination(for: AppRoute.self)")))
    for case, view, title, path in PAGES:
        assert re.search(rf"\bcase {case}\n", route), case
        assert f"case .{case}: {view}()" in destinations, case
        page = body(struct(code(path), view))
        assert page.lstrip().startswith("let lines") or page.lstrip().startswith("List {"), view
        assert f".navigationTitle({title})" in page, view
    # Downloads, Change address, Debug and the EQ are pushed as before
    for kept in ("case .downloads: DownloadsScreen()", "case .serverAddress: ServerAddressView()",
                 "case .debug: DebugView()", "case .eq(let page): EQDestination(route: page)"):
        assert kept in destinations, kept


def test_each_page_holds_its_section():
    assert "GettingAlbumsSection()" in body(struct(code(GETTING), "GettingAlbumsPage"))
    assert "PlaybackSection()" in body(struct(code(PLAYBACK), "PlaybackPage"))
    account = body(struct(code(ACCOUNT), "AccountPage"))
    assert "if lines.account, let me = server.me {" in account and "AccountSection(user: me.user)" in account
    assert "ThisPhoneSection(debug: lines.debug)" in body(struct(code(THIS_PHONE), "ThisPhonePage"))
    about = body(struct(code(ROOT), "AboutPage"))
    in_order(about, ["LabeledContent(YouWords.version)", "if let logins = lines.logins",
                     "LabeledContent(YouWords.app)", "if lines.failed, let failure = server.meFailure",
                     "ErrorNote(failure)"])
    # Account: Change password, then Sign out; This phone: the address, Change address, Debug for an admin alone
    section = body(struct(code(ACCOUNT), "AccountSection"))
    in_order(section, ["WebAppRow(label: ManagingWords.changePassword", "await server.signOut()"])
    phone = body(struct(code(THIS_PHONE), "ThisPhoneSection"))
    in_order(phone, ["LabeledContent(YouWords.server)", "NavigationLink(value: AppRoute.serverAddress)",
                     "if debug {", "NavigationLink(value: AppRoute.debug)"])
    # the EQ is still a push from Playback
    assert "EQLink(route: .now)" in body(struct(code(PLAYBACK), "PlaybackSection"))
    # a page's own title says what a header did: none is left saying it again
    for path, name in ((ACCOUNT, "AccountSection"), (THIS_PHONE, "ThisPhoneSection"), (PLAYBACK, "PlaybackSection"),
                       (GETTING, "GettingAlbumsSection")):
        assert "} header: {" not in body(struct(code(path), name)), name


def test_who_asks_what_and_when():
    root = code(ROOT)
    view = struct(root, "YouView")
    # the root: /me the first time it shows, and on a pull - and nothing of Getting albums
    assert "@State private var asked = false" in view
    task = block(view, view.index("{", view.index(".task {")))
    assert "guard !asked else { return }" in task and "asked = true" in task and "await server.refreshMe()" in task
    pull = block(view, view.index("{", view.index(".refreshable {")))
    # (Phase 8, slice 6) and Needs a look's count - before it (slice 6's review: Look after the library given by /me's
    # answer then asks it once, not twice)
    assert [line.strip() for line in pull.strip().splitlines() if line.strip() and not line.strip().startswith("//")]         == ["queueCount.pulled()", "await server.refreshMe()"]
    assert "GetSettingsModel" not in view and "getSettings" not in view and "Reachability" not in view
    # Getting albums: as the page shows, on its pull, and as deadwax comes back into reach
    page = struct(code(GETTING), "GettingAlbumsPage")
    assert block(page, page.index("{", page.index(".refreshable {"))).strip() == "await getting.ask().value"
    assert ".onAppear { getting.ask() }" in page
    back = block(page, page.index("{", page.index(".onChange(of: reachability.online)")))
    assert "if back { getting.ask() }" in back
    # About and Account ask /me again on a pull: what they draw is /me's
    for path, name in ((ROOT, "AboutPage"), (ACCOUNT, "AccountPage")):
        page = struct(code(path), name)
        assert block(page, page.index("{", page.index(".refreshable {"))).strip() == "await server.refreshMe()", name


def test_every_choice_is_one_menu_row():
    getting = struct(code(GETTING), "GettingAlbumsSection")
    playback = struct(code(PLAYBACK), "PlaybackSection")
    downloads = struct(code(DOWNLOADS), "DownloadOverSection")
    # no list of ticks is left in any of them, nor anywhere in Settings' own files
    for path in sorted(YOU.glob("*.swift")):
        source = code(path)
        assert '"checkmark"' not in source and ".isSelected" not in source, path.name
    assert '"checkmark"' not in downloads and ".isSelected" not in downloads
    for source, kinds in ((getting, ["GetMode", "QualityFloor", "FormatPreference"]),
                          (playback, ["TurntableSettings.Look", "Normalization"]), (downloads, ["DownloadOver"])):
        assert "ForEach(" in source
        assert source.count(".pickerStyle(.menu)") == (1 if source is getting else len(kinds)), kinds
        assert "Button {" not in source and "Button(action" not in source, kinds
    # Getting albums: one Picker made three times, each choice tagged, nothing shown as chosen before deadwax answers,
    # off while it can't be chosen
    choice = block(getting, getting.index("{", getting.index("private func choice<")))
    assert "Picker(title, selection: Binding<Choice?>" in choice
    assert "guard live, let now, now != chosen else { return }" in choice
    assert 'if chosen == nil {\n                Text(verbatim: "").tag(Choice?.none)' in choice
    assert ".tag(Choice?.some(option))" in choice and ".disabled(!live)" in choice
    for title, cases, chosen in (("GettingWords.modeTitle", "GetMode.allCases", "settings?.mode"),
                                 ("GettingWords.floorTitle", "QualityFloor.allCases", "settings?.floor"),
                                 ("GettingWords.formatTitle", "FormatPreference.youOrder", "settings?.format")):
        assert f"choice({title}, {cases}, chosen: {chosen}, live: live," in getting, title
    # Playback: Now Playing opens as and Normalization, each a Picker; Pause winds the record down stays a Toggle
    in_order(playback, ["LabeledContent(YouWords.gapless, value: YouWords.gaplessOn)",
                        "Picker(TurntableWords.opensAs, selection: Binding<TurntableSettings.Look>",
                        "Toggle(TurntableWords.windDown",
                        "Picker(Normalization.title, selection: Binding<Normalization>",
                        "EQLink(route: .now)"])
    assert "deck.opensAs = look" in playback and "player.normalization = choice" in playback
    # Downloads' Download over: one Picker, as the Storage limit above it already was
    assert "Picker(DownloadWords.downloadOver, selection: Binding<DownloadOver>" in downloads
    assert "downloads.downloadOver = choice" in downloads
    assert "Picker(DownloadWords.storageLimit, selection: $downloads.storageLimit)" in code(DOWNLOADS)


def test_a_choices_own_line_moved_into_its_footer():
    # what each choice's row said under it is said for the chosen one: first in the footer, and as the row's hint
    playback = struct(code(PLAYBACK), "PlaybackSection")
    normalization = playback[playback.index("Picker(Normalization.title"):playback.index("EQLink(route: .now)")]
    assert ".accessibilityHint(player.normalization.note)" in normalization
    footer = normalization.split("} footer: {", 1)[1]
    in_order(footer, ["Text(player.normalization.note)", "Text(YouWords.normalizationNote)", "Text(YouWords.kept)"])
    downloads = struct(code(DOWNLOADS), "DownloadOverSection")
    assert "let chosen = DownloadWords.over(downloads.downloadOver)" in downloads
    assert ".accessibilityHint(chosen.note)" in downloads
    in_order(downloads.split("} footer: {", 1)[1], ["Text(chosen.note)", "DownloadWords.overNow(", "DownloadWords.overKept"])
    # the looks and Getting albums' choices had no line of their own: their footers are as they were
    assert "Text(TurntableWords.lookNote)" in playback
    getting = code(GETTING)
    footer = block(getting, getting.index("{", getting.index("private var footer: some View")))
    in_order(footer, ["Text(StoreLine.offline)", "Text(GettingWords.note)", "GettingWords.unsavedLine(",
                      "Text(problem)", "Notice.announce(said)"])


def test_the_tab_tapped_again_goes_back_then_up():
    routes = code(ROUTES)
    select = block(routes, routes.index("{", routes.index("func select(_ tapped: AppTab)")))
    # as every tab does: pages popped first (a playlist's Edit kept), at the root its list to the top
    for tab in ("library", "search", "requests", "you"):
        assert (f"case .{tab}:\n            if {tab}.isEmpty {{ {tab}ScrollToTop += 1 }} else {{ backToRoot(&{tab}) }}"
                in select), tab
    root = struct(code(ROOT), "YouView")
    assert ".id(Self.top)" in root
    scroll = block(root, root.index("{", root.index(".onChange(of: navigation.youScrollToTop)")))
    assert "proxy.scrollTo(Self.top, anchor: .top)" in scroll
    assert "TabStack(path: paths.you) { YouView() }" in code(TABS)
