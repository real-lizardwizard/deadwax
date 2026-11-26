"""
The iPhone and Mac app's Last.fm on an artist's page, slice A2 (notes/ios.md "Last.fm, slice A2"; deadwax-plans/lastfm.md
3.3, 3.4): the albums' order - the Albums heading's menu, "Newest first" or "Most played", kept per device, judged once
for the visit - and Similar Artists, round tiles under the albums with See All's grid past four.

Read from the Swift source, as the other ios tests read theirs: the menu's choice is the device's, written where it is
read; Most played is offered only with albums by plays, its room held while an answer may bring them; the visit is
judged as the albums are first drawn, again on a pull, at once on a choice; a tile opens their page (yours) or their
MusicBrainz page (theirs), one VoiceOver element, dimmed offline for theirs, with no right-click; See All pushes the
grid; the phone's pieces flat; what the Mac reaches draws at the Mac's sizes; four tiles in view at the narrowest page.
Core's rules (AlbumPlays, SimilarArtists, LastfmWords) are the Swift tests under DeadwaxKit (AlbumPlaysTests,
SimilarArtistsTests, LastfmDecodeTests).
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"

VIEW = "Artist/ArtistView.swift"
MENU = "Artist/AlbumOrderMenu.swift"
SECTION = "Artist/SimilarArtistsSection.swift"
SCREEN = "Artist/SimilarArtistsScreen.swift"
MAC_PAGE = "Mac/Artist/MacArtistPage.swift"
PAGE_MODEL = "Models/ArtistPageModel.swift"
ARTISTS = "Models/ArtistsModel.swift"
NEW = (MENU, SECTION, SCREEN)


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_lastfm_a2_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def code(name: str) -> str:
    """A file as code alone (comments and literals' contents blanked), its spacing made one."""
    return flat(phone_look.bare(source(name)))


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


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


def inner(text: str, opening: str) -> str:
    """Only what the braces hold, flattened and trimmed."""
    whole = body(text, opening)
    return whole[whole.index("{", len(opening) - 1) + 1:-1].strip()


# ----------------------------------------------------------------------------- the menu's choice, kept per device

def test_the_order_is_the_devices_written_where_it_is_read():
    artists = code(ARTISTS)
    assert ("var albumOrder: AlbumOrder = AlbumOrder(saved: UserDefaults.standard.string(forKey: AlbumOrder.storageKey)) "
            "{ didSet { UserDefaults.standard.set(albumOrder.rawValue, forKey: AlbumOrder.storageKey) } }") in artists
    order = core("AlbumPlays.swift")
    assert 'public static let storageKey = "deadwax-artist-album-order"' in order
    assert "self = saved == AlbumOrder.played.rawValue ? .played : .newest" in order
    # a choice in the menu, in the tap: kept, and Most played ordering by the answer in hand at once
    view = code(VIEW)
    assert inner(view, "private func chooseOrder(_ order: AlbumOrder) {") == (
        "artists.albumOrder = order if order == .played { model.choseMostPlayed() }")
    assert inner(code(PAGE_MODEL), "func choseMostPlayed() {") == "arrival?.visit.chose(lastfm)"
    # (A2's review) every item's tap chooses its order - the ticked one's too: a Picker never sets the value it shows,
    # so Newest first couldn't be chosen while the visit drew it with Most played stored
    menu = code(MENU)
    assert inner(menu, "struct AlbumOrderItems: View {") == (
        "let choice: AlbumOrderChoice var body: some View { ForEach(AlbumOrder.allCases, id: \\.self) { (order: "
        "AlbumOrder) in Toggle(order.words, isOn: Binding(get: { choice.shown == order }, set: { (_: Bool) -> Void in "
        "choice.choose(order) })) } }")
    assert "Picker(" not in menu
    # the menu's choice the order drawn from, only with Last.fm on: else newest first
    assert ("let shown = model.albumsShown(rows, chosen: lastfmOn ? artists.albumOrder : .newest, page: taskKey, "
            "kept: kept, albums: albums)") in view
    assert ("let choice = AlbumOrderChoice(shown: shown.order, offered: order.offered, room: order.room, choose: { "
            "(chosen: AlbumOrder) -> Void in chooseOrder(chosen) })") in view


def test_most_played_is_offered_only_with_albums_by_plays_and_its_room_held():
    view = code(VIEW)
    assert inner(view, "private func albumOrder(_ lastfm: LastfmPage.Shown, kept: LastfmPage.Kept.Entry?) -> (offered: "
                       "Bool, room: Bool) {") == (
        "let offered = lastfmOn && model.albumsOffered(page: taskKey, kept: kept) return (offered, !offered && "
        "lastfm.heroLine)")
    assert "let order = albumOrder(lastfm, kept: kept)" in view
    # (A2's review) offered read as the order drawn is: the visit's (its albums, or the answer in hand's) once begun,
    # else the session's answer - the same two sources as visitAlbums
    model = code(PAGE_MODEL)
    assert inner(model, "func albumsOffered(page: String, kept: LastfmPage.Kept.Entry?) -> Bool {") == (
        "if let arrival, arrival.page == page { return arrival.visit.albums.offers(lastfm) } return "
        "AlbumPlays.offered(kept?.held.answer)")
    assert ("public func offers(_ answer: LastfmArtist?) -> Bool { albums != nil || AlbumPlays.offered(answer) }"
            in flat(core("AlbumPlays.swift")))
    assert inner(view, "private var lastfmOn: Bool") == (
        "LastfmPage.state(me: server.access.lastfm, answer: model.lastfm) == .on")
    menu = code(MENU)
    # with it not offered, the menu's room held, hidden and inert - else nothing
    assert inner(menu, "@ViewBuilder func albumOrderRoom(_ choice: AlbumOrderChoice) -> some View {") == (
        "if choice.offered { self } else if choice.room { self .hidden() .disabled(true) .accessibilityHidden(true) }")
    # the phone's: the glyph at the heading's end, a flat button with a finger's target, "Sort albums" and its value
    assert inner(menu, "struct AlbumOrderMenu: View {") == (
        "let choice: AlbumOrderChoice var body: some View { Menu { AlbumOrderItems(choice: choice) } label: { "
        "Text(Image(systemName: \" \")) } .menuStyle(.button) .menuIndicator(.hidden) "
        ".buttonStyle(DWButtonStyle(size: .small)) .fixedSize() .accessibilityLabel(LastfmWords.sortAlbums) "
        ".accessibilityValue(choice.shown.words) .albumOrderRoom(choice) }")
    assert 'Text(Image(systemName: "arrow.up.arrow.down"))' in source(MENU)
    head = code(VIEW)
    assert inner(head, "private func albumsHead(_ counts: ArtistPageFacts.Counts, choice: AlbumOrderChoice) -> some View {") == (
        "ArtistSectionHead(words: ArtistWords.albumsHeading, count: ArtistPageFacts.heading(counts), spoken: "
        "ArtistPageFacts.headingSpoken(counts)) { AlbumOrderMenu(choice: choice) } .padding(.top, 4)")
    # the Mac's: a pop-up showing the order drawn, the same items, its room the same rule
    mac = code(MAC_PAGE)
    assert inner(mac, "private var albumsHead: some View {") == (
        "sectionHead(ArtistWords.albumsHeading) { DWPopUp(words: desk.albumOrder.shown.words, size: .small) { "
        "AlbumOrderItems(choice: desk.albumOrder) } .help(LastfmWords.sortAlbums) "
        ".accessibilityLabel(LastfmWords.sortAlbums) .accessibilityValue(desk.albumOrder.shown.words) "
        ".albumOrderRoom(desk.albumOrder) }")
    # the menu's words Core's, one place each
    words = core("LastfmWords.swift")
    for line in ('public static let sortAlbums = "Sort albums"', 'public static let newestFirst = "Newest first"',
                 'public static let mostPlayed = "Most played"'):
        assert line in words, line


def test_the_rows_are_the_order_drawn_with_their_plays():
    view = code(VIEW)
    listed = body(view, "private func albumsList(")
    assert "let rows = shown.rows" in listed and "albumsHead(ArtistPageFacts.counts(rows, personal: personal), choice: choice)" in listed
    assert ("ArtistAlbumRow(row: mine, line: shown.line(row, ArtistPage.line(mine, personal: personal)), lines: "
            "shown.lines(row, accessibility: accessibility),") in listed
    assert ("ArtistTheirRow(row: other, line: shown.line(row, MBArtistPage.line(other, personal: personal)), lines: "
            "shown.lines(row, accessibility: accessibility),") in listed
    assert "let accessibility = typeSize.isAccessibilitySize" in listed
    # each row's own LibraryListRow takes the lines (LibraryTiles untouched)
    for name in ("private struct ArtistAlbumRow: View {", "private struct ArtistTheirRow: View {"):
        assert "LibraryListRow(title: row.title, line: line, lines: lines) {" in body(view, name), name
    # the desk handed the same order and plays
    desk = body(view, "private func artistDesk(")
    assert "rows: shown.rows, plays: shown.plays, albumOrder: choice," in desk
    # the Mac's: the plays at the In your library cell's end, whole while the format gives way - and in what VoiceOver
    # reads of the row
    mac = code(MAC_PAGE)
    cell = body(mac, "private func cell(_ row: ArtistJoin.Row")
    assert ("case 3: if let plays = desk.plays[row.key] { HStack(alignment: .firstTextBaseline, spacing: 8) { held(row) "
            "Text(plays) .font(Typeface.Mac.mono(.small)) .foregroundStyle(DWPalette.t2) .layoutPriority(1) "
            ".help(plays) } } else { held(row) } default:") in cell
    voice = body(mac, "private func voice(_ row: ArtistJoin.Row) -> MacRowVoice {")
    assert ("let spoken = ArtistPageFacts.spoken(row, personal: desk.personal, format: format) let label = "
            'desk.plays[row.key].map { (plays: String) -> String in "\\(spoken) \\(plays)" } ?? spoken return '
            "MacRowVoice(label: label, actions: actions) }") in voice
    assert '"\\(spoken), \\(plays)"' in source(MAC_PAGE)
    # the plays words fit the cell beside the widest chip on a page of 660 (the window at its smallest); beside a side
    # panel (589) they are cut, whole in .help and VoiceOver
    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    smallest = number(frame, "smallestWidth") - number(look, "sidebarWidth")
    fixed = 56 + 60 + 140
    flexible = (smallest - fixed) / 2
    chip = max(fonts.words(words, 11.5, "semibold") + 2 * 7 for words in ("In your library", "In the collection"))
    assert chip + 8 + fonts.readout("4.1M plays", 12) + 2 * 10 <= flexible, (chip, flexible)


#? Apple's .footnote at the sizes A2's review measured at - the default (large), xxxLarge, AX3 and AX5 - which the
#? phone's row's line (Typeface.Phone.text(.small): 13, relative to footnote) grows with
FOOTNOTE = {"large": 13, "xxxLarge": 19, "AX3": 33, "AX5": 44}
#? the widest plays words LastfmWords.plays makes (`short`: a decimal only under 10 of a unit, so "65.3M" is "65M")
WIDEST_PLAYS = ("999K plays", "9.9M plays", "999M plays", "9.9B plays", "999K listeners", "9.9M listeners",
                "999M listeners")


def test_most_played_plays_are_never_the_part_cut():
    # (A2's review) a phone's row draws its line in one line (LibraryListRow's .lineLimit(lines)), cut at its end: the
    # plays at the end were cut from the reviewed worst lines at the default size, and from nearly every row at xxxLarge.
    # Now they lead the line - only a line's tail is ever cut - and at the accessibility sizes the row takes two lines
    words = core("AlbumPlays.swift")
    assert 'return line.isEmpty ? plays : "\\(plays) · \\(line)"' in words
    assert "accessibility && plays[row.key] != nil ? 2 : 1" in flat(words)
    tiles = (APP / "Library" / "LibraryTiles.swift").read_text(encoding="utf-8")
    look = {name: float(re.search(rf"static let {name}: CGFloat = (\d+)", tiles).group(1))
            for name in ("rowCover", "rowTextSide", "side")}
    assert ".lineLimit(lines)" in flat(body(tiles, "struct LibraryListRow<"))

    def room(points: float) -> float:
        # a 375-point phone: the page's sides, the cover, the text's sides, and the chevron (a footnote symbol)
        return 375 - 2 * look["side"] - look["rowCover"] - 2 * look["rowTextSide"] - 0.62 * points

    worst = ("2012 · in the collection · 2 pressings", "2012 · EP · in the collection · 2 pressings")
    ellipsis = "\u2026"
    for size in ("large", "xxxLarge", "AX3"):
        # what the change stops: at the end of a one-line row, the plays of the reviewed worst lines are past the room
        for line in worst:
            assert fonts.words(f"{line} · 65M plays", FOOTNOTE[size]) > room(FOOTNOTE[size]), (size, line)
    for size in ("large", "xxxLarge"):
        # one line: led by them, the line's cut leaves them whole, the ellipsis after
        for plays in WIDEST_PLAYS:
            assert fonts.words(plays, FOOTNOTE[size]) + fonts.words(ellipsis, FOOTNOTE[size]) <= room(FOOTNOTE[size]), (
                size, plays)
    # the accessibility sizes: two lines (Shown.lines), the plays leading the first. At AX3 they fit it whole; at AX5
    # even "9.9M listeners" outgrows it, so each word takes a line, the second's tail the part cut
    for plays in WIDEST_PLAYS:
        assert fonts.words(plays, FOOTNOTE["AX3"]) <= room(FOOTNOTE["AX3"]), plays
        for word in plays.split():
            assert fonts.words(word, FOOTNOTE["AX5"]) + fonts.words(ellipsis, FOOTNOTE["AX5"]) <= room(FOOTNOTE["AX5"]), (
                plays, word)
    assert fonts.words("9.9M listeners", FOOTNOTE["AX5"]) > room(FOOTNOTE["AX5"])
    view = code(VIEW)
    assert "let accessibility = typeSize.isAccessibilitySize" in body(view, "private func albumsList(")


def number(text: str, name: str) -> float:
    found = re.search(rf"public static let {name}: Double = (\d+)", text)
    assert found, name
    return float(found.group(1))


# ----------------------------------------------------------------------------- the visit, judged once

def test_the_visit_is_judged_as_the_albums_are_first_drawn():
    # (A2's review) the visit's timing is Core's LastfmVisit, event by event (AlbumPlaysTests drives it): the model only
    # tells it what happened, where it happened
    model = flat(phone_look.bare(source(PAGE_MODEL)))
    assert "struct LastfmArrival { let page: String var visit: LastfmVisit }" in model
    assert "private var visit" not in model and "AlbumPlays.Visit()" not in model
    begin = body(model, "private func beginLastfm(")
    # begun: with an answer kept, nothing waits and the albums are drawn by it at once (LastfmVisit's init)
    assert ("let first = Self.firstArrival(state: state, online: online, kept: kept) arrival = LastfmArrival(page: page, "
            "visit: LastfmVisit(arrival: first, answer: kept?.held.answer)) lastfm = kept?.held.answer") in begin
    assert "playsMade = AlbumPlays.Made()" in begin
    ask = body(model, "func askLastfm(")
    # not on, or out of reach: the albums drawn now, by what is in hand
    assert "guard state == .on, online, let client else { arrival?.visit.unasked(lastfm) return }" in ask
    # a pull judges again - the pull's own `again`, not the Top Songs page's retry - and only an ask that goes
    assert "let pulled = again let again = again || (retryFailed && lastfm == nil)" in ask
    assert "guard let ask, again || ask.key != lastfmAsked else { return } arrival?.visit.asking(pulled: pulled)" in ask
    # an answer: kept part by part over the one in hand (a later answer's missing part never takes one away), kept so
    # for the session too, then the visit told
    assert ("if let found { let kept = found.keeping(self.lastfm) self.lastfm = kept self.lastfmAsked = ask.key "
            "self.lastfmFailure = nil artists.keepLastfm(id, kept, asked: ask.key) }") in ask
    assert ask.rstrip().endswith("self.keepLine(page: page, state: state, online: true) "
                                 "self.arrival?.visit.answered(self.lastfm) } }"), ask[-200:]
    wait = body(model, "private func wait(page: String) {")
    assert "guard waitBegun != page, arrival?.visit.arrival.holding == true else { return }" in wait
    assert "guard let self, self.arrival?.page == page else { return } self.arrival?.visit.waited(self.lastfm) }" in wait
    # A1's arrival is the visit's: what lies below Play reads it
    assert inner(model, "func arrival(page: String, state: LastfmState, online: Bool, kept: LastfmPage.Kept.Entry?) -> "
                        "LastfmPage.Arrival {") == (
        "if let arrival, arrival.page == page { return arrival.visit.arrival } return Self.firstArrival(state: state, "
        "online: online, kept: kept)")
    # before the page is begun, the albums it begins with: the session's answer (with one, nothing waits)
    assert inner(model, "func visitAlbums(page: String, kept: LastfmPage.Kept.Entry?) -> [LastfmAlbum]? {") == (
        "if let arrival, arrival.page == page { return arrival.visit.albums.albums } return "
        "AlbumPlays.counted(kept?.held.answer)")
    assert "playsMade.shown(rows, chosen: chosen, visit: visitAlbums(page: page, kept: kept), albums: albums)" in model
    # Core's: once judged, an answer leaves the visit as it is; a pull reopens it with the albums in hand; a choice
    # takes the answer at once; an answer is kept part by part
    rule = flat(core("AlbumPlays.swift"))
    assert ("public mutating func drawn(_ answer: LastfmArtist?) { guard !judged else { return } judged = true albums = "
            "AlbumPlays.counted(answer) }") in rule
    assert "public mutating func reopen() { judged = false }" in rule
    assert "public mutating func chose(_ answer: LastfmArtist?) { judged = true albums = AlbumPlays.counted(answer) }" in rule
    kept = flat(core("Lastfm.swift"))
    assert ("guard enabled, let earlier, earlier.enabled else { return self } return LastfmArtist(enabled: true, "
            "unavailable: unavailable, why: why, url: url ?? earlier.url, listeners: listeners ?? earlier.listeners, "
            "topSongs: topSongs ?? earlier.topSongs, similar: similar ?? earlier.similar, topAlbums: topAlbums ?? "
            "earlier.topAlbums) }") in kept
    # the shown order made again when the visit's albums change, not only its rows
    assert ("if let made, made.chosen == chosen, made.visit == visit, made.rows == rows, made.albums == albums { "
            "return made.shown }") in rule


# ----------------------------------------------------------------------------- Similar Artists

def test_a_tile_opens_their_page_or_their_musicbrainz_page():
    section = code(SECTION)
    assert inner(section, "var route: AppRoute {") == (
        "switch opens { case .artist(let artist): return .artist(ArtistRoute(artist)) case .musicBrainz(let mbid, let "
        "name): return .mbArtist(MBArtistRoute(mbid: mbid, name: name)) }")
    # each tile's tap opens it: the phone's row, See All's grid, the Mac's row (ArtistView's own call)
    assert "SimilarArtistTile(tile: tile, side: side, lines: lines) { navigation.open(tile.route) }" in section
    assert "SimilarArtistTile(tile: tile, side: side, lines: lines) { navigation.open(tile.route) }" in code(SCREEN)
    view = code(VIEW)
    assert "openSimilar: { (tile: SimilarArtists.Tile) -> Void in navigation.open(tile.route) }," in view
    mac = code(MAC_PAGE)
    assert ("SimilarArtistTile(tile: tile, side: side, name: MacSimilarDrawn.name, line: MacSimilarDrawn.line) { "
            "desk.openSimilar(tile) }") in mac
    # theirs need deadwax (their MusicBrainz page): dimmed and doing nothing while it can't be reached; yours open
    tile = body(section, "struct SimilarArtistTile: View {")
    assert "let dimmed = !tile.yours && !reachability.online" in tile
    assert "Button(action: open) {" in tile and ".disabled(dimmed)" in tile and ".opacity(dimmed ? DWPalette.off : 1)" in tile


def test_a_tile_is_one_element_with_no_right_click():
    section = code(SECTION)
    tile = body(section, "struct SimilarArtistTile: View {")
    tile_body = body(tile, "var body: some View {")
    # (A2's review) a dimmed tile of theirs says why it does nothing: "Opens once deadwax is back", Core's words
    assert tile_body.endswith(
        ".buttonStyle(.plain) .disabled(dimmed) .help(tile.name) .accessibilityElement(children: .ignore) "
        ".accessibilityLabel(tile.spoken) .accessibilityValue(dimmed ? LastfmWords.opensOnceBack : \"\") "
        ".accessibilityAddTraits(dimmed ? [] : .isButton) .accessibilityAction { if !dimmed { open() } } }"), tile_body
    assert 'public static let opensOnceBack = "Opens once deadwax is back"' in core("LastfmWords.swift")
    assert tile_body.count(".accessibilityElement(") == 1
    # "GUM, Not in your library": Core's words
    assert 'public var spoken: String { yours ? name : "\\(name), \\(line)" }' in core("SimilarArtists.swift")
    # no right-click anywhere a tile is drawn: a tile has no •••
    for name in (SECTION, SCREEN, MAC_PAGE):
        text = code(name)
        part = text if name != MAC_PAGE else body(text, "@ViewBuilder private var similarArtists: some View {")
        assert not re.search(r"contextMenu|macContextMenu|RightClick|QueueMenu", part), name
    # the room held while the library's artists are asked: hidden, read by nothing
    room = body(tile, "static func room(")
    assert room.endswith(".hidden() .accessibilityHidden(true) }")


def test_see_all_pushes_the_grid_past_four():
    section = code(SECTION)
    head = body(body(section, "struct SimilarArtistsSection: View {"), "ArtistSectionHead(words: LastfmWords.similarArtists) {")
    assert head == ("ArtistSectionHead(words: LastfmWords.similarArtists) { if shown.seesAll { Button(LastfmWords.seeAll) "
                    "{ navigation.open(.similarArtists(route)) } .buttonStyle(DWButtonStyle(size: .small)) } }")
    assert inner(section, "var seesAll: Bool") == "drawn && SimilarArtists.seesAll(tiles)"
    assert "public static func seesAll(_ tiles: [Tile]) -> Bool { tiles.count > seeAllPast }" in flat(core("SimilarArtists.swift"))
    assert "public static let seeAllPast = 4" in core("SimilarArtists.swift")
    view = code(VIEW)
    assert "seeAllSimilar: { navigation.open(.similarArtists(route)) })" in view
    mac = code(MAC_PAGE)
    assert ("sectionHead(LastfmWords.similarArtists) { if similar.seesAll { Button(LastfmWords.seeAll, action: "
            "desk.seeAllSimilar) .buttonStyle(DWButtonStyle(size: .small)) } }") in mac
    # the route: the grid at the readable width, on both devices
    routes = code("Shared/Routes.swift")
    assert "case similarArtists(ArtistRoute)" in routes
    assert "case .similarArtists(let artist): SimilarArtistsScreen(route: artist).readableOnMac()" in routes
    area = code("Mac/Artist/MacArtist.swift")
    assert "case .similarArtists(let artist): SimilarArtistsScreen(route: artist).readableOnMac()" in area
    assert "case .similarArtists(let artist): MacArtist.page(for: .similarArtists(artist))" in code("Mac/Frame/MacRoutes.swift")
    # the grid: adaptive columns as wide as a tile at least, growing with the text
    screen = code(SCREEN)
    assert ("LazyVGrid(columns: [GridItem(.adaptive(minimum: side), spacing: SimilarArtistsDrawn.gap, alignment: .top)], "
            "alignment: .leading, spacing: 18)") in screen
    assert "@ScaledMetric(relativeTo: .footnote) private var scaled = SimilarArtistsDrawn.side" in screen
    assert ".navigationTitle(LastfmWords.similarArtists)" in screen
    # the page's own tiles: met with the library's artists - the same id the artist page meets them with
    assert ("let tiles = listed ? SimilarArtists.tiles(model.lastfm?.similar, library: artists.similarLibrary(), page: "
            "route.id, mbid: mbid) : []") in screen
    assert "let drawn = SimilarArtists.drawsTiles(listKnown: artists.listKnown, waited: waited)" in screen
    # (A2's review) the library's artists asked by the page itself, and its wait counted from that ask, in one task:
    # with nothing to ask (in hand, or out of reach), no wait
    assert ('.task(id: "\\(taskKey) \\(online)") { guard online, artists.list == nil else { waited = true return } let '
            "artists = self.artists async let asked: Void = artists.ask() try? await Task.sleep(nanoseconds: "
            "UInt64(SearchPacing.ownedWaitMs) * 1_000_000) if !Task.isCancelled { waited = true } await asked }") in screen
    assert screen.count("SearchPacing.ownedWaitMs") == 1 and screen.count("artists.ask()") == 1


def test_similar_artists_sits_under_the_albums_on_both():
    view = flat(phone_look.bare(source(VIEW)))
    held = body(body(view, "var body: some View {"), "if !arrival.holding {")
    order = [held.index(part) for part in ("albumsList(shown,", "if !top.isEmpty && arrival.place != .inPlace { topSongs(top) }",
                                           "if similar.shows { similarArtists(similar) }")]
    assert order == sorted(order) and held.rstrip().endswith("if similar.shows { similarArtists(similar) } }")
    mac = code(MAC_PAGE)
    held = body(body(mac, "@ViewBuilder private var page: some View {"), "if !desk.arrival.holding {")
    assert held.endswith("if !desk.mostPlayed.isEmpty { mostPlayed } if desk.similar.shows { similarArtists } }"), held
    # what both draw: Core's tiles met with the library's artists, drawn once they are known or waited for
    assert inner(view, "private func similarShown() -> SimilarShown {") == (
        "guard similarListed else { return .none } return SimilarShown(listed: true, drawn: "
        "SimilarArtists.drawsTiles(listKnown: artists.listKnown, waited: similarWaited), tiles: "
        "SimilarArtists.tiles(model.lastfm?.similar, library: artists.similarLibrary(), page: route.id, mbid: mbid))")
    assert "let similar = similarShown()" in view and "similar: similar," in body(view, "private func artistDesk(")
    # (A2's review) the library's artists asked if they aren't in hand - only online, and only with similar artists to
    # meet - and the tiles' own wait counted from that ask (R6's ownedWaited counts from the page's opening, so a list
    # Last.fm brought late found it long over); with nothing to ask, no wait
    assert ('.task(id: "\\(taskKey) \\(similarListed) \\(reachability.online)") { guard similarListed else { return } '
            "guard reachability.online, artists.list == nil else { similarWaited = true return } let artists = "
            "self.artists async let asked: Void = artists.ask() try? await Task.sleep(nanoseconds: "
            "UInt64(SearchPacing.ownedWaitMs) * 1_000_000) if !Task.isCancelled { similarWaited = true } await asked }"
            ) in view
    assert '.task(id: "\\(taskKey)|\\(similarListed)|\\(reachability.online)")' in source(VIEW)
    assert view.count("similarWaited = true") == 2 and "@State private var similarWaited = false" in view
    artists = code(ARTISTS)
    assert "var listKnown: Bool { list != nil || failure != nil }" in artists
    assert "similarMade = nil" in body(artists, "func reset() {")
    # (A2's review) the library made once per list: made again whenever the list's serial moves
    assert inner(artists, "func similarLibrary() -> SimilarArtists.Library? {") == (
        "guard let list else { return nil } if let made = similarMade, made.serial == serial { return made.library } "
        "let library = SimilarArtists.Library(list) similarMade = (serial, library) return library")
    # (A2's review) keyed by FoldKey - UTF-16 units, as the rest of Core compares fold keys
    similar = flat(core("SimilarArtists.swift"))
    assert "let byMbid: [FoldKey: Artist] let byName: [FoldKey: [Artist]]" in similar
    plays = flat(core("AlbumPlays.swift"))
    assert "var byMbid: [FoldKey: Int] = [:] var byTitle: [FoldKey: Int] = [:]" in plays
    assert "var release: [String: FoldKey] = [:]" in plays
    for text in (similar, plays):
        # (the rows' own maps are keyed by row key, not a fold key)
        assert not re.search(r"\b(?:byMbid|byTitle|byName): \[String\b", text)


def test_the_phones_pieces_are_flat_and_round():
    found = {}
    for name in NEW:
        draws = phone_look.drawn(phone_look.phone_path(phone_look.bare(source(name))))
        if draws:
            found[name] = draws
    assert found == {}, found
    for name in NEW:
        text = phone_look.phone_path(phone_look.bare(source(name)))
        assert not re.search(r"\.bordered|\.borderedProminent|\bDivider\(\)|\bDWRaised\b|\bDWWell\b|\bPhoneCard\b"
                             r"|cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b|\.shadow\(", text), name
    # a tile is a round picture: ArtistPicture's circle, the person glyph for theirs
    face = code(SECTION)
    face = body(face, "private struct SimilarArtistFace: View {")
    assert "ArtistPicture(id: coverArt, side: side, pixels: CoverSize.tile)" in face
    picture = code("Library/ArtistsScreen.swift")
    picture = body(picture, "struct ArtistPicture: View {")
    assert ".frame(width: side, height: side) .clipShape(Circle())" in picture
    assert 'Image(systemName: "person.fill")' in source("Library/ArtistsScreen.swift")
    # (the mutation's guard) a face given back to a tile is found
    planted = source(SECTION).replace(".contentShape(Rectangle())\n    }\n}",
                                      ".contentShape(Rectangle())\n        .background(DWPalette.card)\n    }\n}", 1)
    assert planted != source(SECTION)
    assert phone_look.drawn(phone_look.phone_path(phone_look.bare(planted))) == ["background: DWPalette.card"]


def test_the_new_views_hold_only_tokens_and_core_words():
    left = []
    for name in NEW:
        text = phone_look.bare(source(name))
        for what, pattern in (("a colour made", r"\bColor\s*\((?!\))|\bUIColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a system colour", r"\.foregroundStyle\(\.(primary|secondary|tertiary|red|white)\)"),
                              ("a font of its own", r"\.system\(|Font\.(system|custom)|\.monospaced\(\)"),
                              ("the old palette", r"\bPalette\.\w+|(?<!DW)\bCorners\.\w+")):
            if re.search(pattern, text):
                left.append(f"{name}: {what} - {re.search(pattern, text).group(0)}")
        # the words are Core's: no literal of its own, and the word is Queue
        assert not re.search(r'(?:Text|Button|Label|Picker)\("', source(name)), name
        assert "Up Next" not in source(name), name
        # they play nothing
        assert "player." not in source(name), name
    assert not left, left


def test_what_the_mac_reaches_draws_at_the_macs_sizes():
    # the Mac reaches the order's items, See All's grid and the tile: none of the phone's own pieces (on the Mac
    # DWLook's target is 0 and a phone height exact), the text styles and the look's alone
    for name in NEW:
        text = phone_look.bare(source(name))
        assert not re.search(r"\bTypeface\.Phone\b|\bPhoneLook\b|\blookHeight\b|\bDWLook\b|\bPhone[A-Z]\w*", text), name
    # the grid's credit in the text styles, not LastfmCredit's phone default
    assert "LastfmCredit(lastfmPage: model.lastfm?.url, font: Typeface.footnote, above: 16)" in code(SCREEN)
    # the Mac's row in its own faces, a tile as wide as the grid's least - four in view at the narrowest page, beside a
    # side panel, with the page's 22 either side
    mac = code(MAC_PAGE)
    row = body(mac, "@ViewBuilder private var similarArtists: some View {")
    assert "let side = CGFloat(SimilarArtists.gridMin)" in row
    assert "ScrollView(.horizontal) { LazyHStack(alignment: .top, spacing: MacSimilarDrawn.gap) {" in row
    assert ".padding(.horizontal, Drawn.side) }" in row
    drawn = code(MAC_PAGE)
    assert ("private enum MacSimilarDrawn { static let gap: CGFloat = 16 static let name = "
            "Typeface.Mac.text(.base).weight(.semibold) static let line = Typeface.Mac.text(.small) }") in drawn
    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    narrowest = number(frame, "columnMin") - number(look, "sidebarWidth") - max(number(look, "panelWidth"),
                                                                              number(frame, "panelWidth")) - 1
    tile = number(core("SimilarArtists.swift"), "gridMin")
    assert 2 * 22 + 4 * tile + 3 * 16 <= narrowest, narrowest
    # "Not in your library" fits a tile: the phone's footnote (13 at the default size, the side growing with it) and
    # the Mac's small (12)
    notin = re.search(r'public static let notInLibrary = "([^"]+)"', core("LastfmWords.swift")).group(1)
    assert fonts.words(notin, 13) <= tile and fonts.words(notin, 12) <= tile
    assert "@ScaledMetric(relativeTo: .footnote) private var scaled = SimilarArtistsDrawn.side" in code(SECTION)
    assert "static let side = CGFloat(SimilarArtists.gridMin)" in code(SECTION)


def test_a_tile_is_never_wider_than_the_page():
    # (A2's review) the side grows with the text - 112 at the default size, some 379 at AX5 - and a 375-point phone's
    # page is 343: each place a tile is drawn measures its width and draws no tile wider (Core's SimilarArtists.side)
    tile = number(core("SimilarArtists.swift"), "gridMin")
    assert tile * FOOTNOTE["AX5"] / FOOTNOTE["large"] > 375 - 2 * 16
    assert ("public static func side(_ scaled: Double, page: Double?) -> Double { guard let page, page > 0 else { return "
            "scaled } return min(scaled, page) }") in flat(core("SimilarArtists.swift"))
    for name, measured in ((SECTION, "drawn"), (SCREEN, "grid")):
        text = code(name)
        assert "let side = CGFloat(SimilarArtists.side(Double(scaled), page: page.map(Double.init)))" in text, name
        assert "@State private var page: CGFloat?" in text, name
        assert (f".onGeometryChange(for: CGFloat.self) {{ ({measured}: GeometryProxy) -> CGFloat in {measured}.size.width "
                "} action: { (width: CGFloat) -> Void in page = width }") in text, name
        # `scaled` is read only through the clamp
        assert text.count("scaled") == 2, name
    # the grid's page measured inside its sides, the row's page as wide as the section
    screen = code(SCREEN)
    assert screen.index(".onGeometryChange(") < screen.index(".padding(.horizontal, SimilarArtistsDrawn.edge) "
                                                              ".padding(.bottom, 24)")


def test_a_tile_grows_with_the_text():
    face = body(code(SECTION), "private struct SimilarArtistFace: View {")
    assert face.count(".lineLimit(lines, reservesSpace: true)") == 2
    for name in (SECTION, SCREEN):
        assert "let lines = typeSize.isAccessibilitySize ? 3 : 1" in code(name), name


def test_the_macs_songs_section_is_your_most_played():
    mac = code(MAC_PAGE)
    assert "sectionHead(ArtistPageFacts.Words.yourMostPlayed)" in body(mac, "@ViewBuilder private var mostPlayed: some View {")
    assert 'public static let yourMostPlayed = "Your most played"' in core("ArtistPageFacts.swift")
    # the old name is gone from every file of the app's
    for path in sorted(APP.rglob("*.swift")):
        assert "Words.mostPlayed" not in path.read_text(encoding="utf-8"), path.name
