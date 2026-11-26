"""
Search, Get and Sources in the redesign's look (slice R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources
(2026-11-25)"; the drawings Search.dc.html, Get.dc.html, iSearch.dc.html, iGet.dc.html and iSources.dc.html): the Mac's
grouped table and its Get page with Sources in the side panel, the phone's flat list, Get page and sheet.

The app's Swift read as text, as the other look tests read it, and the phone's numbers held to dw.css as the cascade
resolves it:

- The kinds narrow the QUERY, never the results (CLAUDE.md's "The search type filter narrows the QUERY"): the phone's
  strip, the Mac's segments, its folded pop-up and a section's See all each call `search.choose`, and each draws the
  kind in use.
- Every play is in the tap: a song's ▶ (the phone) and Play (the Mac) are PlayerModel's own call with nothing awaited.
- Get on the Mac opens the side panel's Sources tab, never the sheet; the phone's is the sheet as it was. The tab goes
  when its Get page leaves the front (AppNavigation.frontMoved, Core's MacDock.getLasts), and (R7's review) when another
  pressing is chosen on it (AppNavigation.pressingChosen, MacDock.getStands); each Get a number of its own for the run.
- "Search Soulseek by hand…" (the Mac's toolbar) is Requests' toolbar, its Artist field with the cursor.
- The phone is flat: only what the drawings give a face or a line - the page's black, the hairlines, the chosen line
  and the song's bar in the accent, the maybe's dashed edge, Search's field's well and Sources' query's own box (R1c's
  typing rule).
- (R7's review) Search's field on the phone is the look's sunken square box (iSearch's `.well.sfield`), every behaviour
  of iOS's field it replaced kept; the Mac's is the sidebar's, unchanged.
- The Mac's tables take View > Row Size; a row is one element for VoiceOver, its buttons its actions and its own action
  the first's; its keys, its clicks and its stripes are MacColumnList's.
- (R7's review) Sources: Sample rate ▾ beside the sort, the count of the folders shown of those found, the Mac's foot.
- Tokens only, in every file this slice redrew: no colour, radius, opacity or font of its own; "Queue", never "Up Next".
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_search_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
mac_look = _load("test_ios_mac_look")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def kept(text: str) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def body(code: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = code.index(start)
    opened = code.index("{", at)
    return code[at:reader.closing(code, opened) + 1]


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


SCREEN = "Search/SearchScreen.swift"
GROUP = "Search/GroupView.swift"
PICKER = "Search/PressingPickerSheet.swift"
SHEET = "Get/SourcesSheet.swift"
CARD = "Get/SourceCardView.swift"
STORE = "Get/StoreLineView.swift"
MAC_SEARCH = "Mac/Search/MacSearchPage.swift"
MAC_GET = "Mac/Search/MacGetPage.swift"
MAC_TAB = "Mac/Search/MacSourcesTab.swift"
ROUTER = "Mac/Search/MacSearch.swift"
ROUTES = "Shared/Routes.swift"
PHONE_FILES = (SCREEN, GROUP, PICKER, SHEET, CARD, STORE)
MAC_FILES = (MAC_SEARCH, MAC_GET, MAC_TAB)


# ----------------------------------------------------------------------------- the kinds narrow the query

def test_each_kind_narrows_the_query_and_the_kind_in_use_is_shown():
    screen = flat(bare(source(SCREEN)))
    # the phone's strip: the kinds, the one in use the state's own view, a tap `search.choose`
    chips = body(screen, "private var chips: some View {")
    assert ("PhoneStrip(options: SearchView.allCases, words: SearchWords.chip, shown: Binding(get: { search.state.view }, "
            "set: { (view: SearchView) -> Void in search.choose(view) }), spoken: SearchWords.chipsLabel)") in chips
    # drawn while there are words, over the list
    phone = body(screen, "private var phone: some View {")
    assert "if !state.query.isEmpty { chips } SearchContent()" in phone
    # the Mac's: the segments and, folded, the pop-up named for the kind in use - both the one binding
    page = flat(bare(source(MAC_SEARCH)))
    assert ("private var kind: Binding<SearchView> { Binding(get: { search.state.view }, "
            "set: { (view: SearchView) -> Void in search.choose(view) }) }") in page
    tools = body(page, "@ViewBuilder private func tools(_ fit: Fit) -> some View {")
    assert ("DWSegmented(options: SearchView.allCases, words: SearchWords.chip, chosen: kind, "
            "spoken: SearchWords.chipsLabel, large: true)") in tools
    assert "DWPopUp(words: SearchWords.chip(state.view)) { Picker(SearchWords.chipsLabel, selection: kind) {" in tools
    assert ".accessibilityValue(SearchWords.chip(state.view))" in tools
    # a section's See all (the phone's) is the same call, never a filter of the rows
    head = body(screen, "private struct SectionHead: View {")
    assert "Button { search.choose(SearchView(kind)) } label: { Text(SearchWords.seeAll)" in head
    assert ".accessibilityLabel(SearchWords.seeAllLabel(kind))" in head
    # and nothing here narrows the rows itself: every list drawn is the model's
    for name in (SCREEN, MAC_SEARCH):
        code = bare(source(name))
        assert "state.view = " not in code and ".filter { (row: SearchRow) -> Bool in row.kind" not in code, name
    assert bare(source(SCREEN)).count("search.choose(") == 2
    assert bare(source(MAC_SEARCH)).count("search.choose(") == 1


# ----------------------------------------------------------------------------- every play is in the tap

def test_a_songs_play_is_in_the_tap():
    code = bare(source(SCREEN))
    tapped = flat(body(code, "private func tapped(_ song: Song) {"))
    call = tapped.index("player.play(songs: plays.songs, album: plays.album, at: plays.at)")
    assert "await" not in tapped and "Task" not in tapped
    assert tapped.index("if let plays = playable(song) {") < call
    # the phone's row: its tap is the call; the Mac's: its Play button's
    song = flat(body(code, "@ViewBuilder private func songRow(_ song: Song, _ line: SearchList.Line) -> some View {"))
    assert "Button { tapped(song) } label: {" in song
    assert "switch action { case .play: tapped(song) default: openAlbum(of: song) }" in song
    # and the Mac's row does what it is handed, in the click, nothing awaited
    row = flat(body(bare(source(MAC_SEARCH)), "struct MacSearchRow<Name: View>: View {"))
    assert "await" not in row and "Task" not in row
    # the ▶ the phone shows is the row's own first action - drawn only for a song that plays
    assert "trailing(actions(plays: plays).first)" in code
    assert "face(line, round: false, cover: song.coverArt, plays: plays && !dimmed)" in code
    actions = flat(body(core("SearchTable.swift"), "public static func actions("))
    assert "plays" in actions


# ----------------------------------------------------------------------------- Get: the tab on the Mac, the sheet on the phone

def test_get_opens_the_side_panels_sources_on_the_mac_and_the_sheet_on_the_phone():
    view = flat(bare(source(GROUP)))
    get = body(view, "private func get(_ page: GroupPage) {")
    assert get.endswith("if Platform.mac { navigation.getSources(request, from: route) } else { getting = request } }")
    # the sheet stays the phone's: Choose a source over the page, its search let go with it
    assert "if next == nil { getting?.search.close() }" in view and "SourcesSheet(request: request) {" in view
    # the dock's Sources tab is the Get's - SourcesPage, its chips and sort kept with the Get
    tab = flat(bare(source(MAC_TAB)))
    assert "if let get = navigation.macSources {" in tab
    assert "SourcesPage(request: get.request, pushed: false, kept: get.choices) { navigation.sourcesQueued(get.request.id) }" in tab
    assert ".id(get.request.id)" in tab
    assert "case .sources: MacSourcesTab()" in flat(bare(source("Player/MacPanels.swift")))
    # (R7's review) a number no Get has had in this run: never a page's own count, which starts again on every page
    assert "let request = GetRequest(id: GetRequest.numbered(), release: release," in get
    assert "gets" not in view
    numbered = body(sheet_code(), "@MainActor static func numbered() -> Int {")
    assert numbered == "@MainActor static func numbered() -> Int { issued += 1 return issued }"
    assert "@MainActor private static var issued = 0" in sheet_code()
    routes = flat(bare(source(ROUTES)))
    sources = body(routes, "func getSources(_ request: GetRequest, from page: GroupRoute) {")
    assert ("macSources?.request.search.close() macSources = MacSourcesGet(page: page, request: request) "
            "showPanel(.sources)") in sources
    ended = body(routes, "func endSources() {")
    assert "macSources = nil ended.request.search.close()" in ended
    assert "struct MacSourcesGet { let page: GroupRoute let request: GetRequest let choices = SourcesChoices() }" in routes


def sheet_code() -> str:
    return flat(bare(source(SHEET)))


def test_another_pressing_chosen_ends_the_docks_get():
    """(R7's review) A pressing chosen with the dock open: the dock's Get - its cards, its Get - were for the pressing it
    asked, so it ends, never left to download one the page no longer shows."""
    view = flat(bare(source(GROUP)))
    assert ".onChange(of: page.chosenId) { _, chosen in navigation.pressingChosen(chosen, on: route) }" in view
    routes = flat(bare(source(ROUTES)))
    chosen = body(routes, "func pressingChosen(_ chosen: String?, on page: GroupRoute) {")
    assert chosen == ("func pressingChosen(_ chosen: String?, on page: GroupRoute) { guard let get = macSources, "
                      "get.page == page, !MacDock.getStands(asked: get.request.release.releaseMbid, chosen: chosen) "
                      "else { return } endSources() }")
    stands = body(flat(bare(core("MacDock.swift"))), "public static func getStands(asked: String?, chosen: String?)")
    assert "asked != nil && asked == chosen" in stands


def test_the_tab_goes_when_its_get_page_is_left():
    routes = flat(bare(source(ROUTES)))
    # every move of the front - a tab, any tab's stack - asks whether the Get's page is still in front
    for line in ("private(set) var tab: AppTab = .library { didSet { frontMoved() } }",
                 "var library: [AppRoute] = [] { didSet { frontMoved() } }",
                 "var search: [AppRoute] = [] { didSet { frontMoved() } }",
                 "var requests: [AppRoute] = [] { didSet { frontMoved() } }",
                 "var you: [AppRoute] = [] { didSet { frontMoved() } }"):
        assert line in routes, line
    moved = body(routes, "private func frontMoved() {")
    assert ("guard let get = macSources, !MacDock.getLasts(AppRoute.group(get.page), front: shownStack.last) "
            "else { return } endSources()") in moved
    lasts = flat(bare(core("MacDock.swift")))
    assert "public static func getLasts<Page: Equatable>(_ page: Page, front: Page?) -> Bool { front == page }" in lasts
    # a download asked for from it hands over to Requests, as the sheet's does; the dock's Close ends the Get
    queued = body(routes, "func sourcesQueued(_ id: Int) {")
    assert "guard macSources?.request.id == id else { return } endSources() showRequestsRoot()" in queued
    sheet = flat(bare(source(SHEET)))
    assert "guard !docked else { return closeDock() }" in sheet
    assert "navigation.endSources()" in body(sheet, "private func closeDock() {")
    # the dock's page is let go with the Get, never as the tab is switched away from (its search outlives the tab)
    assert ".onDisappear { if !docked { model.close() } }" in sheet
    # (R7's review) and drawn again as its tab comes back, its Get as it was - never searched afresh
    appeared = sheet[sheet.index(".onAppear {"):]
    assert appeared.startswith(".onAppear { guard !docked || model.search == nil else { return } "
                               "filters = GetSettings.floorFilters(floor) begin(request.release) }")
    # (R7's review) a person changing ends the dock's Get before the panel is put away: nothing picked for the next
    reset = body(routes, "func reset() {")
    assert "manualSearchWanted = false macLibraryPage = nil endSources() macPanel = nil" in reset


def test_each_sources_chip_reaches_its_filter_and_the_cards():
    sheet = flat(bare(source(SHEET)))
    # the page's strip: each chip toggles its own filter (the dock's Get's own, kept, or the page's), pressing one marks
    # the chips touched (so a floor landing later doesn't put them back)
    chips = body(sheet, "private var chips: some View {")
    assert ("FilterStrip(chips: GetSettings.chips(floor, filters, manual: request.release.manual)) "
            "{ (key: SourceFilters.Key) in touched = true filters[key].toggle() }") in chips
    assert "nonmutating set { choices.filters = newValue }" in sheet and "private var choices: SourcesChoices { kept ?? own }" in sheet
    # each device's chip calls it with its own key, and says whether it is on
    strip = body(sheet, "private struct FilterStrip: View {")
    assert "Button(chip.label) { toggle(chip.key) } .buttonStyle(DWButtonStyle(kind: chip.on ? .on : .normal, size: .small))" in strip
    assert "Button { toggle(chip.key) } label: {" in strip
    assert strip.count(".accessibilityAddTraits(chip.on ? .isSelected : [])") == 2
    # and the cards drawn are the ones through the chips as they are now
    passing = body(sheet, "private func passing(_ answer: FindCandidatesAnswer?) -> [Candidate] {")
    assert "let chosen = chosenFilters return (answer?.candidates ?? []).filter { Sources.passes($0, chosen) }" in passing
    # (R7's review) the chips and the sample-rate floor, one set of filters for the cards, the best match and a pick
    assert ("private var chosenFilters: CandidateFilters { SourcesLook.filters(filters, minSampleRate: minSampleRate) }"
            in sheet)
    assert "filters: { chosenFilters }," in sheet
    assert "GetSettings.candidateFilters(" not in sheet
    # a pressed filter is white over the accent's line, an unpressed one in the second colour
    word = body(sheet, "private func word(_ chip: GetSettings.Chip) -> some View {")
    assert (".font(Typeface.Phone.text(.strip).weight(chip.on ? .semibold : .medium)) "
            ".foregroundStyle(chip.on ? DWPalette.text : DWPalette.t2)") in word
    assert "if chip.on { Rectangle() .fill(DWPalette.acc)" in word


def test_the_sort_and_the_sample_rate_set_what_they_say():
    """(R7's review) Each pop-up sets its own choice; Clear filters clears the floor with the chips; the count says how
    many are shown of those found."""
    sheet = sheet_code()
    choices = body(sheet, "@ViewBuilder private var sortChoices: some View {")
    assert ("DWPopUp(words: sort.label, size: .small) { Picker(SourcesWords.sortLabel, selection: Binding(get: { sort }, "
            "set: { (order: CandidateSort) in sort = order })) {") in choices
    assert ("DWPopUp(words: SourcesLook.sampleRate(minSampleRate).chip, size: .small) { "
            "Picker(SourcesLook.sampleRateLabel, selection: Binding(get: { minSampleRate }, "
            "set: { (rate: Double) in minSampleRate = rate })) { ForEach(SourcesLook.sampleRates) "
            "{ (floor: SourcesLook.SampleRate) in Text(floor.label).tag(floor.value) } }") in choices
    assert ".accessibilityLabel(SourcesLook.sampleRateLabel) .accessibilityValue(SourcesLook.sampleRate(minSampleRate).label)" \
        in choices
    # the floor kept with the Get's chips and sort (the dock's outlasts its tab)
    assert "nonmutating set { choices.minSampleRate = newValue }" in sheet
    assert "var minSampleRate: Double = 0" in body(sheet, "final class SourcesChoices {")
    # Clear filters shows for the floor too, and clears it
    assert ("if SourcesLook.pressed(filters, minSampleRate: minSampleRate) > 0 { Button(SourcesWords.clearFilters) "
            "{ touched = true filters = .none minSampleRate = 0 }") in sheet
    # the count: every folder found, and those through the filters - the foot's two numbers
    found = body(sheet, "private var foundCount: (all: Int, shown: Int)? {")
    assert found.endswith("return (answer.candidates.count, passing(answer).count) }")
    line = body(sheet, "private var sortLine: some View {")
    assert line.count("Text(SourcesLook.found(found.all, shown: found.shown))") == 2
    assert "Text(Sources.searchedLine(answer, shown: shown.count))" in sheet
    # one line where it fits, the count under the pop-ups where it doesn't; capped as the strip is
    assert line.startswith("private var sortLine: some View { ViewThatFits(in: .horizontal) { "
                           "HStack(alignment: .firstTextBaseline, spacing: SourcesPageLook.sortGap) { sortChoices")
    assert line.endswith(".dynamicTypeSize(...DynamicTypeSize.xxxLarge) }")


def test_the_macs_foot_says_what_the_speeds_are():
    sheet = sheet_code()
    assert "if Platform.mac { if let shown = shownCards { speedsFoot(shown) } }" in sheet
    foot = body(sheet, "private func speedsFoot(_ shown: [Candidate]) -> some View {")
    assert "Text(SourcesLook.speeds(shown))" in foot and ".help(SourcesLook.speeds(shown))" in foot
    assert ".lookHeight(SourcesPageLook.foot) .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }" in foot
    assert "static let foot: Double = 34" in sheet and "static let footSide: CGFloat = 12" in sheet
    # only while cards are shown: the cards through the filters, never the store's box or none passing
    cards = body(sheet, "private var shownCards: [Candidate]? {")
    assert "storeBox(answer) == nil" in cards and "return shown.isEmpty ? nil : shown" in cards


# ----------------------------------------------------------------------------- by hand

def test_search_soulseek_by_hand_is_requests_toolbar():
    page = flat(bare(source(MAC_SEARCH)))
    tools = body(page, "@ViewBuilder private func tools(_ fit: Fit) -> some View {")
    assert ("if server.access.can(.request) { Button(SearchTable.byHand) { navigation.manualSearch() } "
            ".buttonStyle(DWButtonStyle()) .fixedSize() }") in tools
    assert 'public static let byHand = "Search Soulseek by hand…"' in core("SearchTable.swift") \
        or 'byHand = "Search Soulseek by hand\\u{2026}"' in core("SearchTable.swift")
    routes = flat(bare(source(ROUTES)))
    manual = body(routes, "func manualSearch() {")
    assert manual == ("func manualSearch() { nowPlayingShown = false tab = .requests backToRoot(&requests) "
                      "manualSearchWanted = true }")
    requests = flat(bare(source("Mac/Requests/MacRequestsPage.swift")))
    # (R7's review) from the Artist field's own change - drawn with the ask, or asked while drawn - never a timer, and
    # the ask taken whatever happens
    field = body(requests, "private func field(_ prompt: String, text: Binding<String>, _ which: Field, width: Double)")
    assert (".onChange(of: navigation.manualSearchWanted, initial: true) { (_: Bool, wanted: Bool) -> Void in "
            "guard wanted, which == .artist else { return } defer { navigation.manualSearchTaken() } "
            "focused = .artist }") in field
    assert requests.count("manualSearchWanted") == 1 and "Task.sleep" not in requests
    # the phone's is Requests' own Search Soulseek… row, as it was: nothing here asks for it
    assert "manualSearch" not in bare(source(SCREEN)) and "manualSearch" not in bare(source(GROUP))


# ----------------------------------------------------------------------------- the phone is flat

def phone_code(name: str) -> str:
    """The file's code as the phone runs it: each Mac half and each `Platform.mac ? a : b`'s a gone, `if !Platform.mac`'s
    half kept, and the Mac's own parts of a shared file (MAC_PARTS) cut."""
    code = bare(source(name))
    for start in MAC_PARTS.get(name, []):
        code = phone_look.cut(code, start)
    code = re.sub(MAC_HALF, r"if Platform.mac {", code)
    code = re.sub(r"\bif !Platform\.mac \{", "if true {", code)
    code = re.sub(rf"Platform\.mac \? {CHAIN} : ", "", code)
    code = phone_look.phone_path(code)
    assert "Platform.mac" not in code, (name, code[code.index("Platform.mac") - 80:code.index("Platform.mac") + 80])
    return code


#? a value's chain, as a ternary hands one: `Typeface.Mac.text(.base).weight(.semibold)`
CHAIN = r"[\w.]+(?:\([^()]*\))?(?:\.\w+(?:\([^()]*\))?)*"

#? a Mac half's opening: `if Platform.mac {`'s, with a desk in hand (`if let desk, Platform.mac {`, `if table != nil, ...`)
MAC_HALF = r"\bif (?:let \w+|\w+ != nil), Platform\.mac \{"

#? the Mac's own parts of the phone's files, run only from inside a Mac half (each named here held below): a search row
#? as the Mac's table is handed it (SearchTableRow - the drawing is MacSearchPage's); (R7's review) Sources' foot under
#? the cards, Get.dc.html's panel's alone
MAC_PARTS = {
    SCREEN: [r"private func tableRow\("],
    SHEET: [r"private func speedsFoot\("],
}

#? what the phone draws of each, in the file's order - iSearch, iGet and iSources flat on the page's black:
FLAT = {
    # the list's black; (R7's review) the field's well (iSearch's .well.sfield) on the black under the bar; the thin line
    # under each row (a song's disclosure's too)
    SCREEN: ["background: DWPalette.page", "DWWell: focused: fieldFocused", "background: DWPalette.page",
             "DWRule: DWPalette.rowRule", "DWRule: DWPalette.rowRule"],
    # the page's black, the maybe's dashed edge (the meta line plain, iGet's .s.q), the pressing row's line, the song's
    # bar in the accent and the line under each track
    GROUP: ["background: DWPalette.page", "strokeBorder: DWPalette.t2", "DWRule: DWPalette.rowRule",
            "fill: DWPalette.acc", "DWRule: DWPalette.rowRule"],
    # the page's black, the query's own box (R1c's typing rule - its field keeps a face: its well, which R10's wider
    # reading sees, and its edge), the filters' strip's hairline and the chosen filter's line in the accent
    SHEET: ["background: DWPalette.page", "background: Palette.well", "strokeBorder: Palette.border", "DWRule: DWPalette.stripRule",
            "fill: DWPalette.acc"],
    # the cards: PhoneCard's line under each, nothing of their own; the picker iOS's list; the store line words alone
    CARD: [], PICKER: [], STORE: [],
}


def test_the_phone_is_flat_in_search_get_and_sources():
    found = {name: phone_look.drawn(phone_code(name)) for name in PHONE_FILES}
    assert found == FLAT, {name: draws for name, draws in found.items() if draws != FLAT[name]}
    # the dashed edge is the maybe's alone, and the bar the song's
    group = flat(phone_code(GROUP))
    assert group.count("StrokeStyle(lineWidth: 1, dash:") == 1 or group.count("dash:") == 1
    # (R7's review) the pressing's row a flat button: its words and its caret in the accent, Pressing in the second
    # colour; its hint the facts line, the pressings' count with it
    row = body(group, "private func pressingRow(_ view: PressingsView, facts: String) -> some View {")
    assert "Text(Pressings.picker) .foregroundStyle(DWPalette.t2)" in row
    assert "Text(view.chosen?.label ?? \"\") .foregroundStyle(DWPalette.acc)" in row
    assert "DWCaret(colour: DWPalette.acc)" in row and ".accessibilityHint(facts)" in row
    assert "pressingRow(view, facts: factsLine(page))" in group
    assert body(group, "private func factsLine(_ page: GroupPage) -> String {") == (
        "private func factsLine(_ page: GroupPage) -> String { "
        "GetPageWords.factsLine(page.facts, pressings: model.answer?.releases.count ?? 0) }")
    # Get the album the phone's one primary button, its words alone - no chevron beside it
    get = group[group.index("Button { get(page) } label: {"):]
    assert get.startswith("Button { get(page) } label: { Text(SourcesWords.getTheAlbum) } "
                          ".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))")
    assert group.count("kind: .pri") == 1 and "PhoneChevron" not in group and "chevron" not in group
    # a search row's Get is the accent's words alone; › only for a page
    screen = flat(phone_code(SCREEN))
    trailing = body(screen, "@ViewBuilder private func trailing(_ action: SearchTable.Action?) -> some View {")
    assert ("case .get?: Text(SearchTable.Action.get.words) .font(Typeface.Look.text(.smallButton).weight(.semibold)) "
            ".foregroundStyle(DWPalette.acc) .accessibilityHidden(true) case .open?: PhoneChevron() case nil:") in trailing
    assert screen.count("PhoneChevron()") == 1
    # the cards are PhoneCards; the Mac's keep their box
    card = bare(source(CARD))
    assert phone_code(CARD).count("PhoneCard") >= 1
    mac, _ = phone_look.halves(flat(card), "if Platform.mac {")
    assert "DWPalette.card" in mac and "DWCorners.boxShape" in mac
    # and the planted face is caught on the phone's path, never on the Mac's
    for opening in ("if let desk, Platform.mac {", "if table != nil, Platform.mac {"):
        planted = bare(opening + " x.background(DWPalette.buttonFace) } else { x.background(DWPalette.page) }")
        code = re.sub(MAC_HALF, r"if Platform.mac {", planted)
        assert phone_look.drawn(phone_look.phone_path(code)) == ["background: DWPalette.page"], opening


def test_the_macs_parts_cut_are_run_only_from_its_halves():
    for file, parts in MAC_PARTS.items():
        code = bare(source(file))
        phone = phone_look.phone_path(re.sub(rf"Platform\.mac \? {CHAIN} : ", "",
                                             re.sub(MAC_HALF, r"if Platform.mac {", code)))
        for start in parts:
            declared = re.search(start, phone)
            assert declared, start
            name = re.search(r"(?:func|var) (\w+)", declared.group(0)).group(1)
            # outside its own declarations, never called on the phone's path
            rest = phone
            for each in parts:
                rest = phone_look.cut(rest, each)
            assert not re.search(rf"\b{name}\b", rest), (file, name)


def test_the_facts_line_and_the_strips_at_the_largest_sizes():
    """(R7's review) The facts line: two lines held, and as many as it takes at the accessibility sizes. The filters'
    strip: capped at xxxLarge, each word's whole target inside its scroll view where it scrolls. See all: a finger's 44,
    the heading its 38."""
    group = flat(bare(source(GROUP)))
    assert ".multilineTextAlignment(.center) .modifier(FactsLines(lifted: typeSize.isAccessibilitySize))" in group
    lines = body(group, "private struct FactsLines: ViewModifier {")
    assert "if lifted { content.lineLimit(2...) } else { content.lineLimit(2, reservesSpace: true) }" in lines
    assert "@Environment(\\.dynamicTypeSize) private var typeSize" in group
    sheet = sheet_code()
    strip = body(sheet, "private struct FilterStrip: View {")
    assert ("ViewThatFits(in: .horizontal) { row ScrollView(.horizontal, showsIndicators: false) { "
            "row .padding(.vertical, reach) } .padding(.vertical, -reach) }") in strip
    assert "CGFloat(DWLook.here.reach(PhoneLook.strip))" in strip
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in body(strip, "var body: some View {")
    screen = flat(bare(source(SCREEN)))
    head = body(screen, "private struct SectionHead: View {")
    assert ("Text(SearchWords.seeAll) .font(Typeface.Phone.text(.small).weight(.semibold)) "
            ".foregroundStyle(DWPalette.acc) .contentShape(DWTarget(face: Rectangle()))") in head
    assert "minHeight" not in head
    heading = body(screen, "private struct SearchHeading<Trailing: View>: View {")
    assert ".lookHeight(DWLook.here.groupRowHeight) .frame(maxWidth: .infinity, alignment: .bottomLeading) .zIndex(1)" \
        in heading


def test_the_phones_numbers_are_the_drawings():
    screen = flat(bare(source(SCREEN)))
    look = body(screen, "enum SearchLook {")
    # a row 60 tall (dw.ph's .row.tall), its line the row's (#1c1b22), its bare ▶ 28 with a 14 glyph - footnote's
    assert phone_look.px(phone_look.css(".row.tall", "height")) == 60
    assert "lookHeight(DWLook.here.tallRowHeight)" in screen
    assert phone_look.css(".row", "border-bottom-color") == "#1c1b22"
    assert phone_look.px(phone_look.css(".key.bare", "width")) == 28 and "static let play: CGFloat = 28" in look
    assert phone_look.px(phone_look.css(".key.bare svg", "width")) == 14 and phone_look.nearest(14) == "footnote"
    assert "SharpSymbol(.play) .font(Typeface.symbol(.footnote)) .foregroundStyle(DWPalette.t3)" in screen
    assert phone_look.css(".key.bare", "color") == "var(--t3)" or phone_look.css(".key.bare", "color") == "#8e8ea3"
    # a heading's row: 38 tall, its words at its foot 6 up, 15 semibold in the heading's colour (subheadline's)
    assert phone_look.px(phone_look.css(".row.grp", "height")) == 38
    assert phone_look.px(phone_look.css(".row.grp", "padding-bottom")) == 6
    assert phone_look.px(phone_look.css(".row.grp", "font-size")) == 15 and phone_look.nearest(15) == "subheadline"
    assert "static let headingFoot: CGFloat = 6" in look
    heading = body(screen, "private struct SearchHeading<Trailing: View>: View {")
    assert ".font(Typeface.subheadline.weight(.semibold)) .foregroundStyle(DWPalette.head)" in heading
    assert ".lookHeight(DWLook.here.groupRowHeight)" in heading
    group = flat(bare(source(GROUP)))
    assert "static let headingFoot: CGFloat = 6" in body(group, "enum GroupPageLook {")
    assert ".font(Typeface.subheadline.weight(.semibold)) .foregroundStyle(DWPalette.head)" in group
    # the strip's sides are its own 16 (.chips padding 0 16px): drawn out to the list's edges
    assert phone_look.px(phone_look.css(".chips", "padding-left")) == 16
    assert "static let phoneSide: CGFloat = 16" in look
    assert ".padding(.horizontal, -SearchLook.side)" in body(screen, "private var chips: some View {")
    # every number in the looks says where it is from
    for name, enum in ((SCREEN, "enum SearchLook {"), (GROUP, "enum GroupPageLook {"), (MAC_SEARCH, "enum MacSearchLook {")):
        text = source(name)
        block = text[text.index(enum):reader.closing(text, text.index("{", text.index(enum))) + 1]
        for line in re.findall(r"static let \w+: CGFloat = [\d.]+.*", block):
            assert re.search(r"// (drawn|own):", line), (name, line)


def test_the_search_field_is_the_looks_box():
    """(R7's review) Search's field on the phone is the look's sunken square box (iSearch's .well.sfield, 40 tall) where
    iOS's rounded .searchable was - every behaviour kept - and the Mac's is the sidebar's, as it was."""
    code = bare(source(SCREEN))
    screen = flat(code)
    # no field of iOS's, nor Platform's: the page's own, once, drawn on the phone alone over its list
    assert ".searchField(" not in code and ".searchable(" not in code and ".findField(" not in code
    assert code.count("TextField(") == 1 and ".onSubmit(of: .search)" not in code
    phone = body(screen, "private var phone: some View {")
    assert ".safeAreaInset(edge: .top, spacing: 0) { field }" in phone
    assert "if let desk, Platform.mac { desk() } else { phone }" in screen
    field = body(flat(kept(source(SCREEN))), "private var field: some View {")
    # the glyph, the words - each keystroke the model's, as the drawer's binding was - the prompt in the third colour
    assert ("HStack(spacing: SearchLook.fieldGap) { Image(systemName: \"magnifyingglass\") .foregroundStyle(DWPalette.t3) "
            ".accessibilityHidden(true) TextField(SearchWords.prompt, text: Binding(get: { search.text }, "
            "set: { (typed: String) -> Void in search.type(typed) }), prompt: Text(SearchWords.prompt)"
            ".foregroundStyle(DWPalette.t3))") in field
    # the look's field: plain, its font and white, the cursor its own; no correcting, no capitals; the Search key
    # searching and putting the keyboard away
    assert (".textFieldStyle(.plain) .font(Typeface.Look.text(.field)) .foregroundStyle(DWPalette.fieldText) "
            ".focused($fieldFocused) .autocorrectionDisabled() .textInputAutocapitalization(.never) "
            ".submitLabel(.search) .onSubmit { search.submitted() fieldFocused = false } "
            ".accessibilityLabel(SearchWords.label)") in field
    # ✕ while there are words: emptied as the drawer's clear button did, a finger's target, named for VoiceOver
    assert ("if !search.text.isEmpty { Button { search.type(\"\") } label: { Image(systemName: \"xmark\")") in field
    assert ".contentShape(DWTarget(face: Rectangle())) } .buttonStyle(.plain) .accessibilityLabel(SearchWords.clear) }" \
        in field
    # its box: 12 in, 40 tall, the well (square on the phone, its edge the accent's with the cursor), 16 from the edges
    # and 10 over the strip, on the page's black
    assert (".padding(.horizontal, SearchLook.fieldInside) .lookHeight(SearchLook.field) .background { "
            "DWWell(focused: fieldFocused) } .padding(.horizontal, SearchLook.side) .padding(.bottom, SearchLook.fieldFoot) "
            ".background(DWPalette.page)") in field
    look = body(screen, "enum SearchLook {")
    assert phone_look.px(phone_look.css(".sfield", "height")) == 40 and "static let field: Double = 40" in look
    assert phone_look.px(phone_look.css(".sfield", "padding-left")) == 12 and "static let fieldInside: CGFloat = 12" in look
    assert phone_look.px(phone_look.css(".sfield", "gap")) == 8 and "static let fieldGap: CGFloat = 8" in look
    assert phone_look.px(phone_look.css(".sfield", "margin-bottom")) == 10 and "static let fieldFoot: CGFloat = 10" in look
    assert 'public static let clear = "Clear text"' in core("SearchTable.swift")
    # the cursor only where a finger puts it, as before: nothing asks for it
    assert code.count("fieldFocused = ") == 1
    # every behaviour round it kept: the stand-down and resume, the scroll to the top, the keyboard put away by a scroll
    for kept_ in (".onAppear { search.shown() }", "if tab == .search { search.shown() } else { search.standDown() }",
                  ".scrollDismissesKeyboard(.interactively)",
                  "withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }",
                  ".onChange(of: state.view) { _, _ in jump(proxy) }",
                  ".onChange(of: state.drawn?.text) { _, _ in jump(proxy) }"):
        assert kept_ in screen, kept_
    # the Mac's field is the sidebar's, unchanged
    sidebar = flat(bare(source("Root/MacSidebarView.swift")))
    assert "search.type(typed)" in sidebar and "search.submitted()" in sidebar
    # Get and the Mac's pages type nowhere; the picker's filter is iOS's own .searchable, as it was
    for name in (GROUP, STORE, CARD) + MAC_FILES:
        assert not phone_look.TYPING.search(bare(source(name))), name
    assert bare(source(PICKER)).count(".searchable(") == 1
    # Sources' query keeps its own box, in its block
    sheet = flat(bare(source(SHEET)))
    assert ".background(Palette.well, in: Corners.controlShape) .overlay(Corners.controlShape.strokeBorder(Palette.border))" \
        in sheet


# ----------------------------------------------------------------------------- the Mac's tables

def test_the_macs_tables_take_the_row_size():
    page = flat(bare(source(MAC_SEARCH)))
    row = body(page, "struct MacSearchRow<Name: View>: View {")
    assert ".frame(height: CGFloat(rowSize.requestRowHeight))" in row
    assert "@Environment(\\.macRowSize) private var rowSize" in source(MAC_SEARCH)
    # the columns, their widths and the table's width are Core's, by the row size (its cover's growth)
    listed = body(page, "private var list: some View {")
    for part in ("SearchTable.columns(total, size: rowSize)", "SearchTable.widths(columns, total, size: rowSize)",
                 "SearchTable.tableWidth(columns, total, size: rowSize)"):
        assert part in listed, part
    # a row's cover is the row size's, in the one name cell every search row is drawn with on the Mac (its desk's)
    named = flat(body(bare(source(MAC_SEARCH)), "struct MacSearchTableRow: View {"))
    assert "@Environment(\\.macRowSize) private var rowSize" in named
    assert "let side = CGFloat(rowSize.requestCover)" in named
    assert named.count(".frame(width: side, height: side)") == 2 and "ArtistPicture(id: cover, side: side," in named
    # Top results' empty place a row's height there too; SearchScreen itself names no row size of the Mac's
    assert "rowHeight: rowSize.requestRowHeight, indent: MacSearchLook.indent)" in page
    assert ".lookHeight(table?.rowHeight ?? DWLook.here.tallRowHeight)" in flat(bare(source(SCREEN)))
    assert "rowSize" not in bare(source(SCREEN))
    # Get's tracklist is MacColumnList (the row size its own), its box added up from it
    get = flat(bare(source(MAC_GET)))
    assert "MacColumnList(columns: Self.columns, rows: rows, lines: drawn, selected: $selected," in get
    assert "@Environment(\\.macRowSize) private var rowSize" in source(MAC_GET)
    assert "let tall = CGFloat(rowSize.boxHeight(rows: rows.count, headings: headings))" in get
    assert "let least = CGFloat(rowSize.boxLeast(rows: rows.count, headings: headings, room: boxRoom))" in get
    # nothing scrolls sideways at the widths the window opens at: the table's width is the page's when it fits
    assert ".scrollDisabled(width <= total)" in page


def test_a_row_is_one_element_for_voiceover_its_buttons_its_actions():
    row = flat(bare(source(MAC_SEARCH)))
    row = body(row, "struct MacSearchRow<Name: View>: View {")
    assert (".accessibilityElement(children: .ignore) .accessibilityLabel(spoken) "
            ".accessibilityValue(busy ? SearchWords.loading : \"\") "
            ".accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton) .accessibilityAction { main() } "
            ".accessibilityActions {") in row
    assert "ForEach(actions" in row[row.index(".accessibilityActions {"):]
    # (R7's review) its own action its first button's, as MacColumnList's rows open on theirs
    assert ".accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton) .accessibilityAction { main() }" in row
    assert "private func main() { guard !disabled, let first = actions.first else { return } act(first) }" in row
    # a cut name shows whole under the pointer
    assert ".help(" in row
    # a MusicBrainz song's disclosure is its row's action too, as the triangle is the click's
    named = flat(body(bare(source(MAC_SEARCH)), "struct MacSearchTableRow: View {"))
    assert (".accessibilityActions { if let disclosure = row.disclosure { "
            "Button(SongSearch.disclosureHint(open: disclosure.open)) { disclosure.toggle() } } }") in named
    assert "Button { disclosure.toggle() } label: {" in named
    # the phone's rows read as one
    screen = flat(bare(source(SCREEN)))
    assert screen.count(".accessibilityElement(children: .combine) .accessibilityLabel(spoken(line))") >= 4
    # the one right-click of a song's, the one of an album's
    code = bare(source(SCREEN))
    assert code.count(".macContextMenu { QueueMenuItems(request: menu(song)) }") == 1
    assert code.count(".albumRightClick(") == 1


def test_the_macs_table_draws_search_screens_own_rows():
    """SearchScreen's rows say what they are and do (SearchTableRow); MacSearchPage draws them (SearchTableDesk) - the
    one list for both, its every action the phone's own call, and nothing of the Mac's own named in a shared file
    (test_ios_mac_reach's zones)."""
    page = flat(bare(source(MAC_SEARCH)))
    assert "SearchContent() .environment(\\.searchTable, desk)" in page
    desk = body(page, "private var desk: SearchTableDesk {")
    assert "row: { (row: SearchTableRow) -> AnyView in AnyView(MacSearchTableRow(row: row)) }" in desk
    assert "heading: { (title: String) -> AnyView in AnyView(MacSearchGroupLine(title: title)) }" in desk
    named = body(page, "struct MacSearchTableRow: View {")
    assert ("MacSearchRow(id: row.id, title: row.title, cells: row.cells, actions: row.actions, spoken: row.spoken, "
            "striped: striped, dimmed: row.dimmed, busy: row.busy, disabled: row.disabled, act: row.act) {") in named
    assert ".padding(.leading, row.indented ? MacSearchLook.indent : 0)" in named
    screen = flat(bare(source(SCREEN)))
    assert "@Entry var searchTable: SearchTableDesk? = nil" in screen
    # every row of the list on the Mac is the desk's: a library row, MusicBrainz's three, a song's disclosure and its albums
    assert screen.count("table.row(") == 7
    assert "if let table, Platform.mac { table.heading(title) } else {" in screen
    # what each does is the phone's tap's own call
    for call in ("search.open(group) })", "search.openArtist(match) })", "search.openSongAlbum(song, album) })",
                 "navigation.open(route) })"):
        assert call in screen, call
    assert "disclosure: (open, { search.toggleSong(song.key) })" in screen
    assert "indented: true) { (_: SearchTable.Action) -> Void in search.openSongAlbum(song, album) })" in screen


def test_the_macs_table_keys_clicks_stripes_and_top():
    """(R7's review) MacColumnList's own: its keys (MacListKeys), a double-click on a button the button's (MacTable.opens),
    the keyboard the table's once clicked; striped through the table, starting again under a heading; back to the top
    as the phone's list goes."""
    page = flat(bare(source(MAC_SEARCH)))
    pressed = body(page, "private func pressed(_ key: ListKey) -> KeyPress.Result {")
    assert ("switch MacListKeys.pressed(key, selected: table.selected, in: rows) { case .moved(let now): "
            "guard !rows.isEmpty else { return .ignored } table.selected = now return .handled "
            "case .open(let id): table.open(id) return .handled case .ignored: return .ignored }") in pressed
    assert ".focusable() .focused($focused) .focusEffectDisabled() .listKeys { (key: ListKey) -> KeyPress.Result in pressed(key) }" \
        in page
    assert ".onChange(of: table.clicks) { (_: Int, _: Int) -> Void in focused = true }" in page
    row = body(page, "struct MacSearchRow<Name: View>: View {")
    assert (".onTapGesture { clicked(count: 1) } .simultaneousGesture(SpatialTapGesture(count: 2).onEnded "
            "{ (tap: SpatialTapGesture.Value) -> Void in guard MacTable.opens(at: Double(tap.location.x), widths: widths, "
            "controls: controls) else { return } clicked(count: 2) })") in row
    assert "let controls = Set(columns.firstIndex(of: .actions).map { [$0] } ?? [])" in row
    assert "onTapGesture(count: 2)" not in row
    clicked = body(row, "private func clicked(count: Int) {")
    assert ("switch MacTable.clicked(id, count: count) { case .select: table?.clicked(id) case .open: table?.clicked(id) "
            "main() }") in clicked
    # Return: the selected row's first button's
    assert ".onChange(of: table?.opened?.ask) { (_: Int?, _: Int?) -> Void in if table?.opened?.id == id { main() } }" in row
    # the stripes: the table's, by each line's place in it (a song's album by its song's)
    assert "MacSearchColumns(columns: columns, widths: widths, striped: striped)" in page
    named = body(page, "struct MacSearchTableRow: View {")
    assert "let striped = layout?.striped.contains(row.stripedAs ?? row.id) ?? false" in named
    stripes = body(page, "private var striped: Set<String> {")
    assert "SearchTable.striped($0, online: reachability.online)" in stripes and stripes.count("SearchTable.striped(") == 2
    screen = flat(bare(source(SCREEN)))
    assert "% 2" not in screen and not re.search(r"\bstriped\b", screen)
    assert "stripedAs: SearchTable.lineID(.mbSong(song), top: false)" in screen
    lines = flat(bare(core("SearchTable.swift")))
    assert "for (line, stripe) in zip(lines, MacTable.stripes(lines))" in lines
    # back to the top: a top anchor, and the phone's three
    listed = body(page, "private var list: some View {")
    assert "LazyVStack(alignment: .leading, spacing: 0) { Color.clear .frame(height: 0) .id(ShelfAnchor.top) SearchContent()" in listed
    for change in (".onChange(of: navigation.searchScrollToTop) { (_: Int, _: Int) -> Void in withAnimation "
                   "{ proxy.scrollTo(ShelfAnchor.top, anchor: .top) } }",
                   ".onChange(of: state.view) { (_: SearchView, _: SearchView) -> Void in jump(proxy) }",
                   ".onChange(of: state.drawn?.text) { (_: String?, _: String?) -> Void in jump(proxy) }"):
        assert change in listed, change
    assert "withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }" in body(
        page, "private func jump(_ proxy: ScrollViewProxy) {")


def test_get_pages_toolbar_is_the_drawings():
    page = flat(bare(source(MAC_GET)))
    # Get the album the primary button, for whoever may get albums; Pressing ▾ today's picker; "N pressings"
    assert "Button(SourcesWords.getTheAlbum, action: desk.get) .buttonStyle(DWButtonStyle(kind: .pri))" in page
    assert "desk.pick" in page
    assert "GetPageWords.pressings(" in page
    assert "DWCaret(" in page
    # the facts in the status bar, the drawing's
    assert ".macStatus(" in page and "GetPageWords.status(page.tracks, pressing:" in page


# ----------------------------------------------------------------------------- tokens only

PHONE_FONT = re.compile(r"Typeface\.(?:Phone\.(?:text|mono)|symbol|Look\.text)\(")
#? iOS's own text styles the phone's rows keep: a title's body, a heading's subheadline (dw.ph's .row.grp, 15), the
#? picker's and the store line's footnotes, captions and headline as they were
PHONE_STYLES = re.compile(r"Typeface\.(body|subheadline|footnote|caption|headline|title2|title3)"
                          r"(\.weight\(\.\w+\)|\.bold\(\))?$")


def choices(font: str) -> list[str]:
    """A font argument's values: both of a ternary's (the album's title, title3 past 60 characters), else itself."""
    found = re.fullmatch(r"[^?()]+ \? (\S+) : (\S+)", font)
    return list(found.groups()) if found else [font]


def test_search_get_and_sources_draw_no_value_of_their_own():
    left = []
    for name in PHONE_FILES + MAC_FILES:
        code = bare(source(name))
        for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b"),
                              ("a font of its own", r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\.monospaced")):
            if re.search(pattern, code):
                left.append(f"{name}: {what}")
        # a named colour - an enum's own case aside (Sources' `case .red:` band) - on the phone's path (the Mac's store
        # box keeps its Color.primary)
        named = re.sub(r"\bcase \.\w+:", "", phone_code(name) if name in PHONE_FILES else code)
        if mac_look.NAMED_COLOUR.search(named):
            left.append(f"{name}: a named colour ({mac_look.NAMED_COLOUR.search(named).group(0)})")
    assert not left, left
    # the old palette only where it was kept: the Mac's store box and its pill, Sources' query's box, and its dimming
    olds = {name: sorted(set(re.findall(r"(?<![\w.])Palette\.\w+", phone_code(name)))) for name in PHONE_FILES}
    assert olds == {SCREEN: [], GROUP: [], PICKER: [], CARD: [], STORE: ["Palette.busy", "Palette.danger"],
                    SHEET: ["Palette.border", "Palette.dimmed", "Palette.well"]}, olds
    # the phone's fonts: Typeface.Phone's, the look's, the symbols' and iOS's text styles
    for name in PHONE_FILES:
        fonts = mac_look.font_arguments(phone_code(name))
        odd = [f for font in fonts for f in choices(font) if not PHONE_FONT.match(f) and not PHONE_STYLES.match(f)
               and not re.match(r"SourceCardLook\.\w+(\.weight\(\.\w+\))?$", f)]
        assert not odd, (name, odd)
    # the cards' own table of faces: each the phone's or the Mac's
    faces = re.findall(r"static var \w+: Font \{ (.+?) \}", phone_code(CARD))
    assert len(faces) >= 3 and all(PHONE_FONT.match(f) or PHONE_STYLES.match(f) for f in faces), faces
    faces = re.findall(r"static var \w+: Font \{ Platform\.mac \? (.+?) : ", flat(bare(source(CARD))))
    assert faces and all(mac_look.MAC_FONT.match(f) for f in faces), faces
    # the Mac's own pages: the Mac's faces
    for name in MAC_FILES:
        fonts = mac_look.font_arguments(bare(source(name)))
        assert not [f for f in fonts if not mac_look.MAC_FONT.match(f)], name
    # never the readouts' digits by another way
    for name in PHONE_FILES + MAC_FILES:
        assert ".monospacedDigit()" not in bare(source(name)), name


def test_the_queue_is_the_queue():
    for name in PHONE_FILES + MAC_FILES:
        assert "Up Next" not in kept(source(name)), name


def test_the_router_draws_the_macs_pages():
    router = flat(bare(source(ROUTER)))
    assert "static func root() -> some View { SearchScreen { MacSearchPage() } }" in router
    assert "case .group(let group): GroupView(route: group) { (desk: GroupDesk) in MacGetPage(desk: desk) }" in router
    # the phone's pages are as appRoutes drew them
    assert "GroupView(route: group).readableOnMac()" in bare(source(ROUTES))
