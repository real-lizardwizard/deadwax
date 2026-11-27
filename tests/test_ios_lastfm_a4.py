"""
The iPhone and Mac app's About, Last.fm's slice A4 (notes/ios.md "Last.fm, slice A4"; deadwax-plans/lastfm.md 3.9): at
the foot of the artist page and the album page, "About" - deadwax's description (GET /deadwax/describe/artist|album:
Last.fm's words first, else Wikipedia's, else Navidrome's), Wikidata's subtitle, the paragraph at four lines with More
/ Less, and the link ("More on Last.fm", "From Wikipedia") opening beside the app.

Read from the Swift source, as the other ios tests read theirs: where each page draws it on each device; what each page
asks by, and when, keyed on the page so only the newest answer draws; the session's answers shared, one ask out per
question; the words one VoiceOver element, the heading a header outside it; the link a borderless Link (and
VoiceOver's action), only AboutBlock.url's, and Wikipedia's credit as words without one; flat on the phone, in the Mac's
own section style and sizes on the Mac - on its album page, which doesn't scroll, the four lines or one row in what the
songs' least leaves, More opening the whole words in a popover (A4's review); the words fitting a 375-point phone at the
largest text sizes. Core's
rules (AboutBlock, AboutWords: the kept minute, the newest answer, the words, the link only to its own host, the
questions) are DeadwaxKit's AboutBlockTests; the routes and the answer are test_ios_contract.py's
test_abouts_routes_are_the_servers_and_their_answers_what_the_app_decodes.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"

SECTION = "Shared/AboutSection.swift"
MODEL = "Models/AboutModel.swift"
ARTIST = "Artist/ArtistView.swift"
ALBUM = "Album/AlbumView.swift"
MAC_ARTIST = "Mac/Artist/MacArtistPage.swift"
MAC_ALBUM = "Mac/Album/MacAlbumPage.swift"
ARTIST_MODEL = "Models/ArtistPageModel.swift"
ALBUM_MODEL = "Models/AlbumModel.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_lastfm_a4_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def code(name: str) -> str:
    """A file as code alone (comments and literals' contents blanked), its spacing made one."""
    return flat(phone_look.bare(source(name)))


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


def body(text: str, opening: str) -> str:
    """What `opening`'s braces hold, with `opening`: `opening` ends at, or just before, its `{`."""
    start = text.index(opening)
    brace = text.index("{", start + len(opening) - 1)
    depth = 0
    for end in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[end], 0)
        if depth == 0:
            return text[start:end + 1]
    raise AssertionError(f"{opening}: never closed")


# ----------------------------------------------------------------------------- where it is drawn

def test_about_is_the_foot_of_both_pages_on_both_devices():
    # the artist page: after the albums and Similar Artists (the holding block's last), before the foot line - and only
    # once what lies above it is drawn, so it never stands under Play while the albums wait
    view = code(ARTIST)
    page = body(view, "var body: some View {")
    assert ("if similar.shows { similarArtists(similar) } } if !arrival.holding, let about = "
            "model.about.drawn(for: taskKey) { AboutSection(drawn: about) } if let foot = lastfm.foot { lastfmFoot(foot) "
            "} } } .padding(.horizontal, ArtistDrawn.edge)") in page
    assert page.count("AboutSection(") == 1
    mac = code(MAC_ARTIST)
    held = body(mac, "@ViewBuilder private var page: some View {")
    assert ("if desk.similar.shows { similarArtists } } if !desk.arrival.holding, let about = desk.about { "
            "aboutSection(about) } if let foot = desk.lastfm.foot { lastfmFoot(foot) } Color.clear") in held
    # the album page: under the songs' line, the List's last row; the Mac's under Properties, the page's last
    album = body(code(ALBUM), "private func page(download: AlbumDownload,")
    assert (".listRowSeparator(.hidden, edges: .bottom) .listRowBackground(Color.clear) if let about = "
            "model.about.drawn(for: taskKey) { AboutSection(drawn: about) .listRowSeparator(.hidden) "
            ".listRowBackground(Color.clear) } } } .listStyle(.plain)") in album
    assert album.count("AboutSection(") == 1
    measured = ("onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in Double(frame.size.height) } "
                "action: { (now: Double) -> Void in ")
    mac_album = code(MAC_ALBUM)
    # (A4's review) laid out before the songs' box (its priority 1): offered what the box's least leaves
    assert (f"properties(album) .{measured}propertiesTall = now }} if let about = desk.about {{ About(drawn: about) "
            ".layoutPriority(2) } } else {") in mac_album
    assert "songs(album) .padding(.top, Drawn.boxAbove) .layoutPriority(1)" in mac_album
    assert mac_album.count(".layoutPriority(") == 2
    # each Mac page handed the words its phone page draws: the desk's, made for the same page
    assert "about: model.about.drawn(for: taskKey)," in body(view, "private func artistDesk(")
    assert "about: model.about.drawn(for: taskKey)))" in code(ALBUM)
    assert "let about: AboutBlock.Drawn?" in body(view, "struct ArtistDesk {")
    assert "let about: AboutBlock.Drawn?" in body(code(ALBUM), "struct AlbumDesk {")


# ----------------------------------------------------------------------------- what each page asks, and when

def test_each_page_asks_by_its_ids_keyed_on_the_page():
    artist = code(ARTIST)
    assert body(artist, "private var aboutQuestion: AboutBlock.Question {") == (
        "private var aboutQuestion: AboutBlock.Question { AboutBlock.artist(answered: model.answer != nil, gone: "
        "model.gone, navidromeId: route.id, mbid: mbid, indexKnown: search.ownedIndex != nil, waited: ownedWaited, "
        "factsSettled: model.factsSettled(for: mbid)) }")
    album = code(ALBUM)
    # (A4's review) the bridge's release group first - the web's own source, its word waited for when it is asked - else
    # the library's folders', once /library/owned has answered or failed since the page asked: never a fixed wait
    assert body(album, "private var aboutQuestion: AboutBlock.Question {") == (
        "private var aboutQuestion: AboutBlock.Question { AboutBlock.album(answered: model.album != nil && "
        "model.bridgeSettled, gone: model.gone || model.goneButHere, navidromeId: route.id, release: "
        "model.album?.musicBrainzId, storeGroup: model.store?.releaseGroupMbid, index: search.ownedIndex, "
        "ownedSettled: ownedSettled) }")
    # the ask's task keyed on the page (its taskKey: who, and which artist or album), the question (its ids) and
    # whether deadwax can be reached - each change asks again, and only the newest draws
    for name in (ARTIST, ALBUM):
        text = source(name)
        assert 'private var aboutKey: String { "\\(taskKey)|\\(aboutQuestion.token)|\\(reachability.online)" }' in text
        assert (".task(id: aboutKey) { model.about.ask(page: taskKey, person: server.person, question: aboutQuestion, "
                "client: server.client, online: reachability.online) }") in code(name), name
        # the page drawn from what the model says of THIS page
        assert code(name).count("model.about.drawn(for: taskKey)") == 2, name
    # the album page's release group, without the bridge's, is the library's folders' word: asked if it isn't in hand -
    # as the page opens, again as deadwax (or the client) comes back - and waited for until its ask ends, however long
    assert ("@Environment(SearchModel.self) private var search" in album
            and "@State private var ownedSince: Int?" in album)
    assert "ownedWaited" not in album and "SearchPacing.ownedWaitMs" not in album and "Task.sleep" not in album
    assert body(album, "private var ownedSettled: Bool {") == (
        "private var ownedSettled: Bool { ownedSince.map { (since: Int) -> Bool in search.ownedAnswers > since } ?? "
        "false }")
    assert ('private var ownedKey: String { "\\(taskKey)|\\(reachability.online)|\\(server.client != nil)" }'
            in source(ALBUM))
    assert body(album, ".task(id: ownedKey) {") == (
        ".task(id: ownedKey) { guard reachability.online, server.client != nil, search.ownedIndex == nil else { return "
        "} ownedSince = search.ownedAnswers search.refreshOwned() }")
    assert album.count("search.refreshOwned()") == 1 and album.count("ownedSince = ") == 1
    # every end of /library/owned's ask counted - answered, the same, or failed - after the index it brings
    search = code("Models/SearchModel.swift")
    assert "private(set) var ownedAnswers = 0" in search and search.count("ownedAnswers += 1") == 1
    asked = body(search, "private func askOwned() {")
    assert ("guard let self, epoch == self.epoch else { return } self.askingOwned = false defer { self.ownedAnswers "
            "+= 1 } guard case .fresh(let answer, let etag)? = fetched else { return }") in asked
    # the bridge's word: in (answered or failed), or not asked at all - no library of your own
    assert "var bridgeSettled: Bool { !personal || store != nil || storeFailed }" in code(ALBUM_MODEL)
    # the artist's facts settled for the id asked - a task let go for another id settles nothing
    model = code(ARTIST_MODEL)
    assert body(model, "func theirFacts(") == (
        "func theirFacts(client: DeadwaxClient?, online: Bool) async { let mbid = discography?.route.mbid await "
        "discography?.loadFacts(client: client, online: online) if !Task.isCancelled { factsFor = mbid } }")
    assert "func factsSettled(for mbid: String?) -> Bool { mbid != nil && factsFor == mbid }" in model
    assert "private(set) var factsFor: String?" in model
    # one About per page, its model's
    assert "let about = AboutModel()" in model and "let about = AboutModel()" in code(ALBUM_MODEL)


def test_only_the_newest_answer_draws_and_the_session_shares_each_ask():
    model = code(MODEL)
    ask = body(model, "func ask(page: String, person: Int,")
    # drawn from the session at once; asked only online, with a question settled and nothing kept for it
    assert ("Self.belong(to: person) asks += 1 let asked = asks let now = Self.now() showing.update(page: page, question: "
            "question, kept: &Self.session.kept, own: own, now: now) guard online, let client, let ask = "
            "AboutBlock.asks(question, kept: &Self.session.kept, now: now) else { return }") in ask
    # one question out per key, shared; its answer lands only for the newest ask
    assert "let out = Self.session.out[ask.key] ?? Self.begin(ask, client: client, person: person)" in ask
    assert ("Task { [weak self] in let found = await out.value guard let self, asked == self.asks else { return } "
            "self.own = (ask.key, found) self.showing.update(page: page, question: question, kept: &Self.session.kept, "
            "own: self.own, now: Self.now()) }") in ask
    assert model.count("asks += 1") == 1
    assert "func drawn(for page: String) -> AboutBlock.Drawn? { showing.drawn(for: page) }" in model
    # the one ask out: never called off, kept when it comes for the person who asked - a failure as none, a moment
    begin = body(model, "private static func begin(")
    assert ("do { let answer = try await client.describe(ask) found = AboutBlock.of(answer) unsure = answer.unavailable } "
            "catch { found = nil unsure = true } if session.person == person { session.kept.keep(key, found, unsure: "
            "unsure, now: now()) session.out[key] = nil } return found") in begin
    assert "session.out[key] = question return question" in begin
    assert ".cancel()" not in model
    # another person's session let go; the clock the engine's monotonic one, in ms
    assert "if session.person != person { session = Session(person: person) }" in model
    assert "private static func now() -> Double { Monotonic.seconds() * 1000 }" in model
    # what draws is the page's: Core's Showing, read for the page asking
    showing = flat(core("AboutBlock.swift"))
    assert "public func drawn(for page: String) -> Drawn? { self.page == page ? drawn : nil }" in showing


# ----------------------------------------------------------------------------- what it draws

def test_the_words_are_one_voiceover_element_and_the_heading_a_header_outside_it():
    section = code(SECTION)
    spoken = body(section, "struct AboutSpoken: ViewModifier {")
    assert spoken == (
        "struct AboutSpoken: ViewModifier { let drawn: AboutBlock.Drawn let more: String? let toggle: () -> Void "
        "@Environment(\\.openURL) private var openURL func body(content: Content) -> some View { let link = "
        "AboutBlock.url(drawn.paragraph) content .accessibilityElement(children: .ignore) "
        ".accessibilityLabel(AboutWords.spoken(drawn)) .accessibilityActions { if let more { Button(more, action: "
        "toggle) } if let link, let paragraph = drawn.paragraph { Button(AboutWords.source(paragraph.source)) { "
        "openURL(link) } } } } }")
    # (A4's review) the words alone are the element, made before the page's frame lays its heading beside them - so
    # .ignore swallows no heading's .isHeader, and the headings rotor stops at About
    view = body(section, "struct AboutBlockView<Frame: View>: View {")
    assert ("frame(AboutWordsView(drawn: drawn, faces: faces, open: open, overflows: $overflows, toggle: toggle) "
            ".modifier(AboutSpoken(drawn: drawn, more: more, toggle: toggle))) .onChange(of: text)") in view
    assert "typealias AboutWordsElement = ModifiedContent<AboutWordsView, AboutSpoken>" in section
    assert "@ViewBuilder let frame: (AboutWordsElement) -> Frame" in view
    assert section.count(".accessibilityElement(") == 1 and section.count(".accessibilityLabel(") == 1
    # More or Less while the words run past their lines - or More alone, where More opens them elsewhere (`opens`)
    assert ("let open = opens == nil && text != nil && openFor == text let toggle: () -> Void = opens ?? { () -> Void "
            "in openFor = open ? nil : text } let more: String? = overflows || open ? (open ? AboutWords.less : "
            "AboutWords.more) : nil") in view
    assert "var opens: (() -> Void)? = nil" in view
    # opened only for these words: other words start closed
    assert ".onChange(of: text) { (_: String?, _: String?) -> Void in openFor = nil }" in view
    # every page's heading outside the element, a header: the phone's section head, the Mac artist page's, the Mac
    # album page's legend (MacGroupBox's own .isHeader) and its row's heading
    assert "ArtistSectionHead(words: AboutWords.heading) { EmptyView() } words" in section
    assert ".accessibilityAddTraits(.isHeader)" in body(code("Artist/TopSongsSection.swift"),
                                                        "struct ArtistSectionHead<Trailing: View>: View {")
    mac_artist = code(MAC_ARTIST)
    assert ".accessibilityAddTraits(.isHeader)" in body(
        mac_artist, "private func sectionHead<Trailing: View>(_ words: String, @ViewBuilder trailing: () -> Trailing)")
    box = code("Mac/Components/MacGroupBox.swift")
    assert ".accessibilityAddTraits(.isHeader) } .accessibilityElement(children: .contain)" in box
    # (A4's review) both Mac About views whole: the artist page's heading over its words, padded as a section is; the
    # album page's legend over its words in a box 22 under Properties, or its row
    assert body(mac_artist, "private func aboutSection(") == (
        "private func aboutSection(_ about: AboutBlock.Drawn) -> some View { AboutBlockView(drawn: about, faces: "
        "MacAboutDrawn.faces) { (words: AboutWordsElement) in VStack(alignment: .leading, spacing: 0) { "
        "sectionHead(AboutWords.heading) words .padding(.horizontal, Drawn.side) .padding(.bottom, Drawn.below) } } }")
    assert body(code(MAC_ALBUM), "private struct About: View {") == (
        "private struct About: View { let drawn: AboutBlock.Drawn @State private var whole = false var body: some View "
        "{ ViewThatFits(in: .vertical) { AboutBlockView(drawn: drawn, faces: MacAlbumAboutDrawn.faces, opens: { () -> "
        "Void in whole = true }) { (words: AboutWordsElement) in MacGroupBox(legend: AboutWords.heading, ground: "
        "DWPalette.bg) { words } .padding(.top, Drawn.propertiesAbove) } .fixedSize(horizontal: false, vertical: true) "
        "row } .appPopover(isPresented: $whole) { AboutWhole(drawn: drawn, faces: MacAlbumAboutDrawn.faces) } "
        ".onChange(of: drawn) { (_: AboutBlock.Drawn, _: AboutBlock.Drawn) -> Void in whole = false } } private var "
        "row: some View { HStack(alignment: .center, spacing: AboutDrawn.macRowGap) { Text(AboutWords.heading) "
        ".font(Typeface.Mac.text(.label).weight(.semibold)) .foregroundStyle(DWPalette.label) .lineLimit(1) "
        ".accessibilityAddTraits(.isHeader) Button(AboutWords.moreWords) { whole = true } "
        ".buttonStyle(DWButtonStyle(size: .small)) Spacer(minLength: 0) } .padding(.top, AboutDrawn.macRowAbove) } }")
    # the row's heading as the legend draws it
    assert ("Text(legend) .font(Typeface.Mac.text(.label).weight(.semibold)) .foregroundStyle(DWPalette.label) "
            ".lineLimit(1)") in box
    # what VoiceOver reads: no heading - it has its own element - and Wikipedia's credit when it is words
    words = flat(core("AboutWords.swift"))
    assert ("public static func spoken(_ drawn: AboutBlock.Drawn) -> String { let plain = "
            "AboutBlock.credited(drawn.paragraph).flatMap { (credit: AboutBlock.Source) -> String? in "
            "AboutBlock.url(drawn.paragraph) == nil ? source(credit) : nil } return [drawn.subtitle, "
            'drawn.paragraph?.text, plain].compactMap { $0 }.joined(separator: ", ") }') in words
    assert "heading" not in words[words.index("public static func spoken("):]


def test_four_lines_more_or_less_and_the_link_beside_the_app():
    words = code(SECTION)
    assert "public static let lines = 4" in core("AboutBlock.swift")
    # the four lines, and the credit's line (three at the accessibility sizes), its words' and its link's
    assert ".lineLimit(AboutBlock.lines)" in words and words.count(".lineLimit(") == 3
    assert words.count(".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)") == 2
    # More only while the words run past their lines - the four lines measured against the whole, unseen; (A4's
    # review) each height measured at once, exactly as it lands
    shown = body(words, "@ViewBuilder private func words(")
    assert ("paragraph(text) .lineLimit(AboutBlock.lines) .frame(maxWidth: .infinity, alignment: .leading) "
            ".onGeometryChange(for: CGFloat.self) { (drawn: GeometryProxy) -> CGFloat in drawn.size.height } action: { "
            "(height: CGFloat) -> Void in clamped = height measure() } .background(alignment: .topLeading) { "
            "paragraph(text) .fixedSize(horizontal: false, vertical: true) .hidden() .onGeometryChange(for: "
            "CGFloat.self) { (laid: GeometryProxy) -> CGFloat in laid.size.height } action: { (height: CGFloat) -> "
            "Void in whole = height measure() } }") in shown
    assert shown.count("clamped = height measure() }") == 1 and shown.count("whole = height measure() }") == 1
    # opened in place, whole, the page scrolling (the phone, the Mac's artist page): no bound, no scroll of its own
    assert ("if open { paragraph(text) .fixedSize(horizontal: false, vertical: true) } else {") in shown
    assert "ScrollView" not in shown and "ViewThatFits" not in shown
    assert ("private func measure() { guard !open, clamped > 0, whole > 0 else { return } let runs = whole > clamped + "
            "1 if runs != overflows { overflows = runs } }") in words
    foot = body(words, "@ViewBuilder private func foot(")
    assert foot == (
        "@ViewBuilder private func foot() -> some View { let more = overflows || open if let least = faces.footLeast { "
        "footParts(more: more) .frame(minHeight: least) } else if more || AboutBlock.credited(drawn.paragraph) != nil "
        "{ footParts(more: more) } }")
    parts = body(words, "@ViewBuilder private func footParts(")
    assert ("Button(open ? AboutWords.less : AboutWords.more, action: toggle) .buttonStyle(DWButtonStyle(size: .small))"
            in parts)
    assert "AboutCredit(drawn: drawn, faces: faces)" in parts
    # stacked at the accessibility sizes, beside each other otherwise
    assert ("if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 0) { parts } } else { "
            "HStack(alignment: .center, spacing: AboutDrawn.footGap) { parts } }") in parts
    # the link: a Link, so the system's browser opens it beside the app (Safari, the Mac's own) - never a web view
    credit = body(words, "struct AboutCredit: View {")
    assert ("let link = AboutBlock.url(drawn.paragraph) if let link, let paragraph = drawn.paragraph { "
            "Link(AboutWords.source(paragraph.source), destination: link) .font(faces.credit) "
            ".foregroundStyle(DWPalette.acc) .buttonStyle(.borderless) .lineLimit(typeSize.isAccessibilitySize ? 3 : 1) "
            ".fixedSize(horizontal: false, vertical: true) .frame(minHeight: faces.target) .contentShape(Rectangle()) }"
            ) in credit
    for text in (source(SECTION), source(MODEL)):
        assert not re.search(r"\bWKWebView\b|\bWebView\b|SFSafariViewController|import\s+WebKit|import\s+SafariServices",
                             text)
    # the subtitle quiet, the paragraph in the second colour
    assert "Text(subtitle) .font(faces.subtitle) .foregroundStyle(DWPalette.t3)" in words
    assert "Text(text) .font(faces.words) .foregroundStyle(DWPalette.t2)" in words


def test_the_link_keeps_its_own_target_in_the_phones_list_row():
    # (A4's review) the album page's About is a List row: a Link of the automatic style there takes the whole row as
    # its target. Borderless, as RequestCards', UpNextScreen's and OfflineBanner's buttons in List rows are
    credit = body(code(SECTION), "struct AboutCredit: View {")
    assert credit.count(".buttonStyle(.borderless)") == 1
    assert "destination: link) .font(faces.credit) .foregroundStyle(DWPalette.acc) .buttonStyle(.borderless)" in credit
    for name in ("Requests/RequestCards.swift", "UpNext/UpNextScreen.swift"):
        assert ".buttonStyle(.borderless)" in code(name), name
    # (R18) OfflineBanner's Try again is the look's button now - a ButtonStyle of its own, which keeps its target too
    assert ".buttonStyle(DWButtonStyle())" in code("Root/OfflineBanner.swift")
    # the row the phone's album page puts it in: the List's last
    assert ("if let about = model.about.drawn(for: taskKey) { AboutSection(drawn: about) .listRowSeparator(.hidden) "
            ".listRowBackground(Color.clear) } } } .listStyle(.plain)") in code(ALBUM)
    # More's own style is the app's (a ButtonStyle of its own keeps its target in a row too)
    assert "struct DWButtonStyle: ButtonStyle" in code("Look/DWButtonStyle.swift")


def test_wikipedias_credit_is_drawn_as_words_without_a_link():
    # (A4's review) the credit is AboutBlock.credited's: Wikipedia's ALWAYS - plain words in the second colour, as
    # LastfmCredit draws its own, when its link wouldn't go where it says - Last.fm's only with its link
    credit = body(code(SECTION), "struct AboutCredit: View {")
    assert ("} else if let credit = AboutBlock.credited(drawn.paragraph) { Text(AboutWords.source(credit)) "
            ".font(faces.credit) .foregroundStyle(DWPalette.t2) .lineLimit(typeSize.isAccessibilitySize ? 3 : 1) "
            ".fixedSize(horizontal: false, vertical: true) }") in credit
    assert "Text(LastfmWords.credit) .foregroundStyle(DWPalette.t2)" in code("Artist/TopSongsSection.swift")
    block = flat(core("AboutBlock.swift"))
    assert ("public static func credited(_ paragraph: Paragraph?) -> Source? { guard let paragraph else { return nil } "
            "return paragraph.source == .wikipedia || url(paragraph) != nil ? paragraph.source : nil }") in block
    # the foot drawn for it: with More, or a credit to show
    assert "} else if more || AboutBlock.credited(drawn.paragraph) != nil {" in code(SECTION)


def test_the_mac_album_pages_more_opens_the_whole_words_beside_it():
    # (A4's review) the page doesn't scroll, so the words never grow in place there: More (in the block or the row)
    # opens them whole in a popover - the subtitle, every word, the credit - 440 wide, scrolling past 360
    section = code(SECTION)
    assert body(section, "struct AboutWhole: View {") == (
        "struct AboutWhole: View { let drawn: AboutBlock.Drawn let faces: AboutFaces var body: some View { ScrollView { "
        "VStack(alignment: .leading, spacing: faces.gap) { if let subtitle = drawn.subtitle { Text(subtitle) "
        ".font(faces.subtitle) .foregroundStyle(DWPalette.t3) .fixedSize(horizontal: false, vertical: true) } if let "
        "paragraph = drawn.paragraph { Text(paragraph.text) .font(faces.words) .foregroundStyle(DWPalette.t2) "
        ".fixedSize(horizontal: false, vertical: true) .textSelection(.enabled) AboutCredit(drawn: drawn, faces: "
        "faces) } } .padding(AboutDrawn.wholeEdge) .frame(width: AboutDrawn.wholeWidth, alignment: .leading) } "
        ".frame(maxHeight: AboutDrawn.wholeMost) .fixedSize() .presentationBackground(DWPalette.panel) } }")
    assert ("static let wholeWidth: CGFloat = 440 static let wholeEdge: CGFloat = 16 static let wholeMost: CGFloat = 360"
            in body(section, "enum AboutDrawn {"))
    # presented through the app's own wrapper, its models carried on the Mac as a sheet's are
    presenting = code("Shared/Presenting.swift")
    assert ("func appPopover<Shown: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Shown) -> "
            "some View { modifier(CarriedPopover(isPresented: isPresented, shown: content)) }") in presenting
    carried = body(presenting, "private struct CarriedPopover<Shown: View>: ViewModifier {")
    assert ("content.popover(isPresented: isPresented) { shown() .carryingApp(carried) .onDisappear(perform: gone(nil)) "
            "}") in carried
    # the Mac album page alone presents it; the phone's pages never do
    uses = {name: code(name).count(".appPopover(") for name in (SECTION, ALBUM, ARTIST, MAC_ARTIST, MAC_ALBUM)}
    assert uses == {SECTION: 0, ALBUM: 0, ARTIST: 0, MAC_ARTIST: 0, MAC_ALBUM: 1}, uses
    assert code(MAC_ALBUM).count("whole = true") == 2


def test_the_phones_section_is_flat():
    drawn = phone_look.drawn(phone_look.phone_path(phone_look.bare(source(SECTION))))
    assert drawn == [], drawn
    text = phone_look.phone_path(phone_look.bare(source(SECTION)))
    assert not re.search(r"\.bordered|\.borderedProminent|\bDivider\(\)|\bDWRaised\b|\bDWWell\b|\bPhoneCard\b"
                         r"|\bPhoneGroup\b|cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b|\.shadow\(", text)
    assert "MacGroupBox" not in text
    # (the mutation's guard) a face given the phone's section is found
    planted = source(SECTION).replace("        .padding(.top, AboutDrawn.above)\n",
                                      "        .padding(.top, AboutDrawn.above)\n        .background(DWPalette.card)\n", 1)
    assert planted != source(SECTION)
    assert phone_look.drawn(phone_look.phone_path(phone_look.bare(planted))) == ["background: DWPalette.card"]
    assert SECTION in phone_look.A4_PAGES and phone_look.A4_PAGES <= phone_look.SLICES


def test_each_device_draws_the_words_in_its_own_faces():
    # the words both draw name none of the phone's pieces: the phone's faces are AboutFaces.phone's alone, the Mac's
    # its pages' own (Typeface's Mac sizes, no target, the drawings' measure)
    section = code(SECTION)
    phone_only = re.compile(r"\bTypeface\.Phone\b|\bPhoneLook\b|\blookHeight\b|\bDWLook\b|\bPhone[A-Z]\w*")
    for opening in ("struct AboutBlockView<Frame: View>: View {", "struct AboutSpoken: ViewModifier {",
                    "struct AboutWordsView: View {", "struct AboutCredit: View {", "struct AboutWhole: View {"):
        assert not phone_only.search(body(section, opening)), opening
    assert body(section, "static var phone: AboutFaces {") == (
        "static var phone: AboutFaces { AboutFaces(subtitle: Typeface.Phone.text(.small), words: Typeface.subheadline, "
        "credit: Typeface.Phone.text(.small), gap: AboutDrawn.gap, target: CGFloat(DWLook.here.target), measure: nil) }")
    assert len(phone_only.findall(section)) == 3
    assert "var footLeast: CGFloat? = nil" in body(section, "struct AboutFaces {")
    assert body(code(MAC_ARTIST), "private enum MacAboutDrawn {") == (
        "private enum MacAboutDrawn { static let faces = AboutFaces(subtitle: Typeface.Mac.text(.small), words: "
        "Typeface.Mac.text(.base), credit: Typeface.Mac.text(.small), gap: AboutDrawn.gap, target: 0, measure: "
        "AboutDrawn.macMeasure) }")
    # (A4's review) the Mac album page's foot always drawn, a small button tall, so the four lines' height never waits
    # on a measure; its row the same button tall, 12 under Properties
    assert body(code(MAC_ALBUM), "private enum MacAlbumAboutDrawn {") == (
        "private enum MacAlbumAboutDrawn { static let faces = AboutFaces(subtitle: Typeface.Mac.text(.small), words: "
        "Typeface.Mac.text(.base), credit: Typeface.Mac.text(.small), gap: AboutDrawn.gap, target: 0, measure: "
        "AboutDrawn.macMeasure, footLeast: CGFloat(MacLook.smallButtonHeight)) static let rowTall = "
        "Double(AboutDrawn.macRowAbove) + MacLook.smallButtonHeight }")
    for name in (MAC_ARTIST, MAC_ALBUM):
        assert "AboutSection(" not in code(name) and "faces: .phone" not in code(name), name
    assert body(section, "enum AboutDrawn {") == (
        "enum AboutDrawn { static let above: CGFloat = 20 static let gap: CGFloat = 6 static let footGap: CGFloat = 16 "
        "static let macMeasure: CGFloat = 640 static let macRowAbove: CGFloat = 12 static let macRowGap: CGFloat = 12 "
        "static let wholeWidth: CGFloat = 440 static let wholeEdge: CGFloat = 16 static let wholeMost: CGFloat = 360 }")
    for text in (section, code(MAC_ALBUM), code(MAC_ARTIST)):
        assert "openMost:" not in text and "macOpenMost" not in text and "faces.openMost" not in text
    # the Mac album page: About's least - its row - counted in what the songs' box has left, never its drawn height
    page = code(MAC_ALBUM)
    assert "+ propertiesTall + aboutLeast)" in page and "aboutTall" not in page
    assert ("private var aboutLeast: Double { desk.about == nil ? 0 : MacAlbumAboutDrawn.rowTall }" in page)


# ----------------------------------------------------------------------------- the Mac album page's arithmetic

#? the page, measured from the bottom of the window (Platform's Window): the smallest window's 600 and the opening
#? window's 820, less the toolbar and the status bar - the reviewer's 442 and 662
PAGES = (442, 662)
#? Properties as drawn: its box at four lines and at five (a folder)
PROPERTIES = (100, 112)
#? the hero: the cover, 132 - its words as tall or shorter
HERO = 132


def line(points: float, name: str = "LibreFranklin-Regular") -> float:
    """One line of Libre Franklin at `points`, as CoreText lays it (hhea's ascender, descender and gap)."""
    ascender, descender, gap = fonts.vertical(name)
    return (ascender - descender + gap) * points


def test_the_mac_album_page_keeps_the_songs_least_and_about_on_it():
    # (A4's review) The page doesn't scroll and its songs' box has priority 1; at e3d8dc88 About had none, its four
    # lines no height of their own and its opened words a ScrollView's least of 0 - 16 points closed, 0 opened, at a
    # 662 page of 20 songs. Now: About laid out first (priority 2) in what the songs' box's least leaves it, its four
    # lines at their own height or - not fitting - one row; the box's least taken less that row's height (aboutLeast).
    # Worked here with the bundled faces, as the page draws them:
    rows = {"small": 30, "medium": 40, "large": 52}
    header, edge = 24, 2
    rowsize = flat(core("MacRowSize.swift"))
    assert ("public func boxLeast(rows: Int, headings: Int) -> Double { min(MacLook.headerHeight + rowHeight * 3, "
            "boxHeight(rows: rows, headings: headings)) }") in rowsize
    assert ("MacLook.headerHeight + rowHeight * Double(max(rows, 0)) + MacLook.groupRowHeight * Double(max(headings, "
            "0)) + 2") in rowsize
    looks = flat(core("MacLook.swift"))
    assert "public static let headerHeight: Double = 24" in looks
    assert "public static let smallButtonHeight: Double = 22" in looks
    for name, points in rows.items():
        assert f"case .{name}: return {'MacLook.rowHeight' if name == 'small' else points}" in rowsize, name
    assert "public static let rowHeight: Double = 30" in looks
    # the page's own numbers: 20 above, 16 below, 18 over the box, Properties and the block 22 under what's above
    page = code(MAC_ALBUM)
    for name, points in (("top", 20), ("bottom", 16), ("boxAbove", 18), ("cover", 132), ("propertiesAbove", 22)):
        assert f"static let {name}: CGFloat = {points}" in page, name
    edges = 20 + 16 + 18
    # the block: the group box's 14 above and 12 below its words; the subtitle's line (12), 6, four lines of the
    # paragraph (13), 6, the foot a small button tall (22, always drawn) - 22 under Properties
    box = code("Mac/Components/MacGroupBox.swift")
    assert ".padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))" in box
    assert "case base = 13" in code("Shared/Typeface.swift") and "case small = 12" in code("Shared/Typeface.swift")
    block = 22 + 14 + line(12) + 6 + 4 * line(13) + 6 + 22 + 12
    # the row: 12 under Properties, a small button tall (its heading, 11.5, shorter)
    row = 12 + 22
    assert line(11.5, "LibreFranklin-SemiBold") < 22
    assert round(block, 1) == 159.6 and row == 34
    for tall in PAGES:
        for songs in (3, 20):
            for size, height in rows.items():
                for properties in PROPERTIES:
                    room = tall - edges - HERO - properties
                    whole = header + height * songs + edge
                    least = min(min(header + height * 3, whole), max(room - row, 0))
                    offered = room - least
                    about = block if block <= offered else row
                    box = min(whole, room - about)
                    said = (tall, songs, size, properties)
                    # the songs' least always wins, and About is never 0 nor a sliver: its block or its row
                    assert box >= least and about >= row, said
                    assert edges + HERO + box + properties + about <= tall + 0.01, said
                    # at the opening window's height, the four lines at every size, the box's least untouched; at
                    # the smallest, the row - the box's least then 110 to 122, Small's 114 kept with four-line
                    # Properties (the row taken from it as Properties is: at most 34 under the least without About)
                    if tall == 662:
                        assert about == block, said
                        assert least == min(header + height * 3, whole), said
                    else:
                        assert about == row, said
                        assert 110 <= least <= 122, said
                        assert least >= min(header + height * 3, whole, room) - row, said
                        if size == "small" and properties == 100:
                            assert least == header + 3 * 30, said
    # the least as the page takes it: the room less About's row, Core's clamp
    assert ("let least = CGFloat(rowSize.boxLeast(rows: rows.count, headings: headings, room: boxRoom))" in
            body(page, "private func songs("))


def test_the_new_views_hold_only_tokens_and_core_words():
    left = []
    for name in (SECTION, MODEL):
        text = phone_look.bare(source(name))
        for what, pattern in (("a colour made", r"\bColor\s*\((?!\))|\bUIColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a system colour", r"\.foregroundStyle\(\.(primary|secondary|tertiary|red|white)\)"),
                              ("a font of its own", r"\.system\(|Font\.(system|custom)|\.monospaced\(\)"),
                              ("the old palette", r"\bPalette\.\w+|(?<!DW)\bCorners\.\w+"),
                              ("a view erased", r"\bAnyView\b"), ("a device branch", r"#if\b"),
                              ("digits drawn alike", r"\.monospacedDigit\(\)")):
            if re.search(pattern, text):
                left.append(f"{name}: {what} - {re.search(pattern, text).group(0)}")
        # the words are Core's: no literal of its own; the block plays nothing
        assert not re.search(r'(?:Text|Button|Label|Link)\("', source(name)), name
        assert "player." not in source(name), name
    assert not left, left


# ----------------------------------------------------------------------------- at the largest text sizes

#? the phone's text sizes, by Dynamic Type's size: the footnote's (the subtitle, the link), the subheadline's (the
#? heading, the paragraph) - Apple's table, as A2's tests read it
FOOTNOTE = {"large": 13, "xxxLarge": 19, "AX3": 33, "AX5": 44}
SUBHEADLINE = {"large": 15, "xxxLarge": 21, "AX3": 36, "AX5": 49}
#? the narrowest phone's page: 375 points less the artist page's 16 either side (the album page's List rows the same)
PAGE = 375 - 2 * 16


def number(text: str, name: str) -> float:
    """A size DWLook's phone is made with (`name: 6,`)."""
    return float(re.search(rf"\b{name}:\s*([\d.]+),", text).group(1))


def test_the_foot_fits_a_375_point_phone_at_every_text_size():
    look = core("DWLook.swift")
    phone = look[look.index("static let onPhone = DWLook("):]
    padding = number(phone, "smallButtonPadding")
    target = number(phone, "target")
    assert (padding, target) == (6, 44)
    small_button = 13.5  # Typeface.Look's .smallButton on the phone, relative to the footnote
    assert "case .smallButton: return (13.5, .footnote)" in source("Shared/Typeface.swift")
    links = [re.search(rf'case \.{kind}: return "([^"]+)"', core("AboutWords.swift")).group(1)
             for kind in ("wikipedia", "lastfm")]
    assert links == ["From Wikipedia", "More on Last.fm"]
    buttons = [re.search(rf'public static let {kind} = "([^"]+)"', core("AboutWords.swift")).group(1)
               for kind in ("more", "less")]
    # up to xxxLarge, side by side on one line: the button (44 wide at least), the gap, the link
    footnote = FOOTNOTE["xxxLarge"]
    button = max(target, max(fonts.words(word, small_button * footnote / 13, "medium") for word in buttons) + 2 * padding)
    for link in links:
        assert button + 16 + fonts.words(link, footnote) <= PAGE, link
    # at the accessibility sizes, stacked: the button on its one line, the link within its three
    for size in ("AX3", "AX5"):
        footnote = FOOTNOTE[size]
        for word in buttons:
            assert fonts.words(word, small_button * footnote / 13, "medium") + 2 * padding <= PAGE, (size, word)
        for link in links:
            assert fonts.words(link, footnote) <= 3 * PAGE, (size, link)
            # no word of it wider than the page: it wraps between words, never inside one
            assert max(fonts.words(part, footnote) for part in link.split()) <= PAGE, (size, link)
    # the heading on its line at AX5 (ArtistSectionHead: the subheadline, semibold)
    heading = re.search(r'public static let heading = "([^"]+)"', core("AboutWords.swift")).group(1)
    assert fonts.words(heading, SUBHEADLINE["AX5"], "semibold") <= PAGE
    # the four lines are lines of the paragraph's own size: they grow with it (no height of their own)
    words = body(code(SECTION), "struct AboutWordsView: View {")
    assert not re.search(r"\.frame\((?:min|max)?[hH]eight: (?!least\b)", words), words
    assert "if let least = faces.footLeast {" in words
    # the Mac: the link on one line in the measure, at its small (12)
    for link in links:
        assert fonts.words(link, 12) <= 640
