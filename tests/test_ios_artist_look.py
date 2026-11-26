"""The redesign's slice R6 (notes/ios.md "The redesign, slice R6: an artist"): an artist's page on the phone as
iArtist.dc.html draws it - flat - and on the Mac as Artist.dc.html does (MacArtistPage) - held to the slice's rules:
every play an existing PlayerModel call made in the tap, Get only on an album nobody holds, the managers' buttons only as
the page offers them (ArtistManage.offered: each by its permission), the Mac's table and toolbar fitting their pages, a
row one element to VoiceOver, and tokens only.

Read from the source, as every test of the app's look is: nothing here builds or runs the app (the builds and the
device checks 559-563 do). Core's rules - Most played's songs once across their pressings, the albums' count, the
chips, Get's rule - are DeadwaxKit's MostPlayedTests and ArtistPageFactsTests."""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"

VIEW = "Artist/ArtistView.swift"
SECTION = "Artist/TopSongsSection.swift"
STRIP = "Phone/PhoneStrip.swift"
MAC_PAGE = "Mac/Artist/MacArtistPage.swift"
MAC_AREA = "Mac/Artist/MacArtist.swift"
PAGES = (VIEW, SECTION, MAC_PAGE)


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_artist_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")
bare = phone_look.bare


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


def body(code: str, opening: str) -> str:
    """What `opening`'s braces hold, the braces with it: `opening` ends at, or just before, its `{`."""
    start = code.index(opening)
    brace = code.index("{", start + len(opening) - 1)
    depth = 0
    for end in range(brace, len(code)):
        depth += {"{": 1, "}": -1}.get(code[end], 0)
        if depth == 0:
            return code[start:end + 1]
    raise AssertionError(f"{opening}: never closed")


def flat(code: str) -> str:
    return re.sub(r"\s+", " ", code)


def number(text: str, name: str) -> float:
    found = re.search(rf"public static let {name}: Double = (\d+)", text)
    assert found, name
    return float(found.group(1))


# ----------------------------------------------------------------------------- the phone: flat, square, tokens

#? everything the artist's page draws on the phone that has a fill or an edge (test_ios_phone_look.py's reading): the
#? rows' hairlines alone - Get's, under it as under the rest of its row, and the song rows' (ArtistRowRule, the phone's
#? row rule). The pair's purple is AlbumPlayPair's (R5's, the primary button), the strip PhoneStrip's (R2's) - each
#? held where it is drawn. James, 25 Nov: "get rid of all the grey boxes". (R10's wider reading) A song you don't
#? have's blank cover, NoteCover's ZStack ground - a picture's place, which keeps its face.
PHONE_DRAWS = {
    VIEW: ["DWRule: DWPalette.rowRule"],
    SECTION: ["DWRule: DWPalette.rowRule", "ZStack: Palette.coverEmpty"],
}


def test_the_phones_artist_page_is_flat():
    found = {}
    for name in (VIEW, SECTION):
        draws = phone_look.drawn(phone_look.phone_path(bare(source(name))))
        if draws:
            found[name] = draws
    assert found == PHONE_DRAWS, found
    # no face on a button but the primary one: the pair is AlbumPlayPair (its Play the purple); every other button a
    # flat one (DWButtonStyle's .normal and .on draw no face on the phone) or plain - none of the system's grey ones
    view = bare(source(VIEW))
    phone = phone_look.phone_path(view)
    assert "AlbumPlayPair(enabled: playable," in phone and "kind: .pri" not in phone and "kind: .danger" not in phone
    for name in (VIEW, SECTION):
        code = phone_look.phone_path(bare(source(name)))
        assert not re.search(r"\.bordered|\.borderedProminent|\bDivider\(\)|\bDWRaised\b|\bDWWell\b|\bPhoneCard\b",
                             code), name
    # (R6's mutation's guard) the matcher finds a face given back to a flat piece of the page
    planted = phone_look.drawn(phone_look.phone_path(bare("x.background(DWPalette.buttonFace)")))
    assert planted == ["background: DWPalette.buttonFace"]


def test_the_phones_artist_page_stays_square():
    # binding 5: "Leave the phone square" - no corner, capsule or shadow of its own on the page; the covers the
    # look's chip shape (square on the phone), the picture round as their row's
    for name in (VIEW, SECTION):
        code = phone_look.phone_path(bare(source(name)))
        assert not re.search(r"cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b|\.shadow\(", code), name
    view = bare(source(VIEW))
    assert body(view, "private struct ArtistAlbumRow: View {").count(".clipShape(DWCorners.chipShape)") == 1
    assert body(view, "private struct ArtistTheirRow: View {").count(".clipShape(DWCorners.chipShape)") == 1
    assert ".clipShape(DWCorners.chipShape)" in body(bare(source(SECTION)), "struct ArtistSongFace<")


def test_the_redrawn_parts_hold_only_tokens():
    # no colour made, by number or by name, no opacity, radius or font of their own, no digits made even - and none of
    # the old palette but the blank under a cover (Palette.coverEmpty, every cover's, CoverImage's and ArchiveCover's)
    left = []
    for name in PAGES:
        code = bare(source(name))
        for what, pattern in (("a colour made", r"\bColor\s*\((?!\))|\bUIColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a system colour", r"\.foregroundStyle\(\.(primary|secondary|tertiary|red|white)\)"),
                              ("a font of its own", r"\.system\(|Font\.(system|custom)|\.monospaced\(\)"),
                              ("digits made even", r"\.monospacedDigit\(\)"),
                              ("a radius of its own", r"cornerRadius|RoundedRectangle\("),
                              ("the old palette", r"\bPalette\.(?!coverEmpty\b)\w+|(?<!DW)\bCorners\.\w+")):
            if re.search(pattern, code):
                left.append(f"{name}: {what} - {re.search(pattern, code).group(0)}")
    assert not left, left
    assert bare(source(SECTION)).count("Palette.coverEmpty") == 1, "the note's blank cover"


def test_a_readout_beside_words_sits_on_their_baseline():
    # the albums' count beside the heading, a song's plays beside its words, the format beside the chip: Courier Prime
    # on the words' first baseline (the fonts' rule)
    section = flat(bare(source(SECTION)))
    head = body(section, "struct ArtistSectionHead<")
    stack = body(head, "HStack(alignment: .firstTextBaseline, spacing: 8)")
    assert ("if let count { Text(count) .font(Typeface.Phone.mono(.extraSmall)) .foregroundStyle(DWPalette.t3) "
            ".lineLimit(1) .accessibilityLabel(spoken ?? count) }") in stack
    count = flat(body(bare(source(VIEW)), "private func albumsHead("))
    assert ("ArtistSectionHead(words: ArtistWords.albumsHeading, count: ArtistPageFacts.heading(counts), "
            "spoken: ArtistPageFacts.headingSpoken(counts))") in count
    assert "Typeface" not in count, "the count's face is the heading's to set"
    mac = flat(bare(source(MAC_PAGE)))
    held = body(mac, "@ViewBuilder private func held(")
    assert held.count("HStack(alignment: .firstTextBaseline, spacing: 8)") == 2
    assert "Text(format) .font(Typeface.Mac.mono(.label))" in held


# ----------------------------------------------------------------------------- the phone's page, as iArtist draws it

def test_the_phones_page_runs_top_to_foot_as_drawn():
    view = flat(bare(source(VIEW)))
    phone = flat(phone_look.phone_path(body(bare(source(VIEW)), "    var body: some View {")))
    order = [phone.index(part) for part in (
        "phoneHero(managing, lastfm: lastfm, factsRoom: factsAsked || factsRoomFor == taskKey)",
        "plays(rows: mine, online: online, personal: personal)",
        "if !top.isEmpty && arrival.place == .inPlace { topSongs(top) }", "strip(managing, offered, online: online)",
        "albumsList(rows, albums: albums, online: online, personal: personal)",
        "if !top.isEmpty && arrival.place != .inPlace { topSongs(top) }", "if let foot = lastfm.foot { lastfmFoot(foot) }")]
    assert order == sorted(order), order
    # the top: who they are on MusicBrainz under the name, for everyone now - their facts asked whoever looks
    hero = body(view, "private func phoneHero(")
    assert "let facts = MBArtistPage.factsLine(model.facts)" in hero
    assert 'if factsRoom || !facts.isEmpty { Text(facts.isEmpty ? " " : facts)' in hero
    assert view.count("await model.theirFacts(client: server.client, online: reachability.online)") == 2
    assert "if Managing.artistManaging(server.access.permissions).any { await model.theirFacts" not in view
    # the pair R5 drew for an album and a playlist, and the line under it held at its height
    plays = body(view, "private func plays(")
    assert "AlbumPlayPair(enabled: playable," in plays and 'Text(line.isEmpty ? " " : line)' in plays
    # the rows on their hairlines: yours the library's tall row with its chevron, theirs with Get or the chevron
    mine = body(view, "private struct ArtistAlbumRow: View {")
    assert "LibraryListRow(title: row.title, line: line)" in mine and "LibraryChevron()" in mine
    theirs = body(view, "private struct ArtistTheirRow: View {")
    assert "LibraryListRow(title: row.title, line: line)" in theirs
    assert "if busy { ProgressView() } else if !get { LibraryChevron() }" in theirs


def test_the_strip_is_studio_only_and_everything_then_the_managers_two():
    view = flat(bare(source(VIEW)))
    strip = body(view, "private func strip(")
    # the tabs once their discography is asked (online, who they are known), the managers' two pushed after them
    assert "let theirs = online ? model.discography : nil" in strip
    assert "let tabs: [ArtistStripPart] = theirs == nil ? [] : [.studio, .everything]" in strip
    assert "let pushes = ArtistStripPart.pushes(offered, known: managing.known)" in strip
    assert "if !tabs.isEmpty || !pushes.isEmpty { PhoneStrip(options: tabs," in strip
    # (R6's review) its tab bar named for what it holds - the switch's two - and Move albums… said in full
    assert ("spoken: ArtistPageFacts.Words.studioLabel, pushes: pushes, said: { (part: ArtistStripPart) -> String in "
            "part.said(current: managing.current) })") in strip
    assert "stripLabel" not in core("ArtistPageFacts.swift") and "stripLabel" not in view
    said = body(view, "func said(current: String?) -> String {")
    assert "guard self == .move, let current else { return words } return ArtistManageWords.moveItem(current)" in said
    chose = body(view, "private func chose(")
    assert "theirs.toggleStudio(client: server.client, online: reachability.online)" in chose
    assert "case .images: toolSheet = ArtistToolSheet(kind: .images)" in chose
    assert "case .move: toolSheet = ArtistToolSheet(kind: .move)" in chose
    # PhoneStrip's pushes: buttons after the tabs, never shown chosen, outside the tabs' tab bar - and still one
    # button drawn, so the strip's face (test_the_phone_is_flat's) is unchanged
    phone_strip = flat(bare(source(STRIP)))
    assert "var pushes: [Part] = []" in phone_strip
    assert "let on = option == shown && !pushes.contains(option)" in phone_strip
    tabs = body(phone_strip, "if !options.isEmpty {")
    assert ".accessibilityAddTraits(.isTabBar) .accessibilityLabel(spoken)" in tabs and "ForEach(options" in tabs
    # (R6's review) the tab bar the tabs' alone: one in the strip, the pushes after its block, in no tab bar of their own
    assert phone_strip.count(".isTabBar") == 1 and "ForEach(pushes" not in tabs
    row = body(phone_strip, "private var row: some View {")
    assert row.index("ForEach(pushes") > row.index(tabs) + len(tabs)
    assert phone_strip.count("Button {") == 1
    # a part's words in full where the page gives them: its help and VoiceOver's label, nothing else
    assert "var said: ((Part) -> String)? = nil" in phone_strip
    assert ".accessibilityAddTraits(on ? .isSelected : []) .modifier(StripPartSaid(words: said?(option)))" in phone_strip
    part = body(phone_strip, "private struct StripPartSaid: ViewModifier {")
    assert "if let words { content .help(words) .accessibilityLabel(words) } else { content }" in part
    # the bar's ••• keeps Which artist is this? alone - never on the Mac's desk, whose toolbar has all three
    menu = body(view, "private func toolsMenu(")
    assert "if offered.who {" in menu and "kind: .images" not in menu and "kind: .move" not in menu
    assert "if offered.who && !onDesk {" in view
    assert "private var onDesk: Bool { desk != nil && Platform.mac }" in view


def test_the_managers_buttons_only_as_the_page_offers_them():
    # Artist images… and Move albums… - on the phone's strip and the Mac's toolbar - only as ArtistManage.offered says:
    # each by its permission (Managing.artistManaging), deadwax in reach; never for a listener
    view = flat(bare(source(VIEW)))
    pushes = body(view, "static func pushes(_ offered: ArtistManage.Offered, known: Bool) -> [ArtistStripPart] {")
    assert "if offered.images && known { pushes.append(.images) }" in pushes
    assert "if offered.move { pushes.append(.move) }" in pushes
    assert pushes.count("pushes.append(") == 2
    offered = body(view, "private func offered(")
    assert "ArtistManage.offered(may: managing.may, online: online, gone: model.gone," in offered
    assert "let may = Managing.artistManaging(server.access.permissions)" in body(view, "private func managing(")
    mac = flat(bare(source(MAC_PAGE)))
    tools = body(mac, "@ViewBuilder private func tools(_ fit: Fit) -> some View {")
    full = tools[tools.index("case .full:"):tools.index("case .folded:")]
    assert "if desk.offered.images { Button(ArtistPageFacts.Words.images) { desk.tool(.images) }" in full
    # (R6's review) Artist images… dimmed until their folder is known - the sheet asks by it - in the toolbar and the •••
    images = body(full, "if desk.offered.images {")
    assert images.endswith(".buttonStyle(DWButtonStyle()) .disabled(!desk.managing.known) }"), images
    assert "if desk.offered.move, let current = desk.managing.current { Button(ArtistPageFacts.Words.moveAlbums)" in full
    assert "if desk.offered.who { Button(ArtistManageWords.whoItem) { desk.tool(.who) }" in full
    assert full.count("desk.tool(") == 3
    folded = tools[tools.index("case .folded:"):]
    assert "if desk.offered.any { Menu { toolItems }" in folded
    items = body(mac, "@ViewBuilder private var toolItems: some View {")
    assert items.count("if desk.offered.") == 3 and items.count("desk.tool(") == 3
    assert body(items, "if desk.offered.images {").endswith("{ desk.tool(.images) } .disabled(!desk.managing.known) }")
    # Move albums… in full where the toolbar's words are short: its help and VoiceOver's label
    move = body(full, "if desk.offered.move, let current = desk.managing.current {")
    assert ".help(ArtistManageWords.moveItem(current)) .accessibilityLabel(ArtistManageWords.moveItem(current))" in move
    # and Core's rule: each by its permission (ArtistManageTests run it)
    manage = flat(core("ArtistManage.swift"))
    rule = body(manage, "public static func offered(")
    assert "guard online, !gone else { return Offered(images: false, who: false, move: false) }" in rule
    assert "images: may.images &&" in rule and "who: may.whichArtist &&" in rule and "move: may.move &&" in rule


def test_get_is_only_on_an_album_nobody_holds_and_opens_the_album_you_dont_have():
    rule = flat(body(core("ArtistPageFacts.swift"),
                     "public static func offersGet(_ row: MBArtistPage.Row, mayGet: Bool) -> Bool {"))
    assert rule == ("public static func offersGet(_ row: MBArtistPage.Row, mayGet: Bool) -> Bool { mayGet && "
                    "row.held == false }")
    view = flat(bare(source(VIEW)))
    listed = body(view, "private func albumsList(")
    assert ("get: ArtistPageFacts.offersGet(other, mayGet: server.access.can(.request)), "
            "busy: theirs?.opening == other.key)") in listed
    assert "theirs?.open(other, client: server.client, online: reachability.online, navigation: navigation)" in listed
    theirs = body(view, "private struct ArtistTheirRow: View {")
    assert theirs.count("if get && !busy {") == 2, "the button and VoiceOver's action"
    assert theirs.count("Button(ArtistPageFacts.Words.get, action: open)") == 2
    # an album of yours has none: its row and its Mac row's buttons draw no Get
    assert "Words.get" not in body(view, "private struct ArtistAlbumRow: View {")
    mac = flat(bare(source(MAC_PAGE)))
    buttons = body(mac, "@ViewBuilder private func buttons(")
    yours = buttons[buttons.index("case .yours(let mine):"):buttons.index("case .theirs(let other):")]
    assert "Words.get" not in yours
    other = buttons[buttons.index("case .theirs(let other):"):]
    assert ("} else if ArtistPageFacts.offersGet(other, mayGet: desk.mayGet) { Button(ArtistPageFacts.Words.get) "
            "{ open(row) }") in other
    assert "} else { Button(ArtistPageFacts.Words.open) { open(row) }" in other
    # (R6's review) only for someone who may get albums - the request permission, as the album you don't have and
    # Requests hide Get without it: on the phone the row's chevron, on the Mac its Open, and the band's "10 more to get"
    # with it; every call of the rule, on both devices, says who is asking
    assert "mayGet: server.access.can(.request), rows: rows," in body(view, "private func artistDesk(")
    calls = re.findall(r"offersGet\(([^()]*(?:\([^()]*\))?[^()]*)\)", view + mac)
    assert len(calls) == 3 and all("mayGet: " in call and "mayGet: true" not in call for call in calls), calls
    assert "ArtistPageFacts.chips(counts, mayGet: desk.mayGet)" in body(mac, "private func band(")
    assert "let get = ArtistPageFacts.offersGet(other, mayGet: desk.mayGet)" in body(mac, "private func voice(")
    assert "case .theirs(let other): desk.openTheirs(other)" in body(mac, "private func open(_ row: ArtistJoin.Row) {")


# ----------------------------------------------------------------------------- plays

def test_every_play_is_an_existing_call_in_the_tap():
    view = bare(source(VIEW))
    for opening, call in (("private func play(shuffle: Bool, online: Bool, offlineAlbums: [Album]) {",
                           "player.play(artist: albums, shuffle: shuffle)"),
                          ("private func playAlbum(_ id: String, online: Bool) {",
                           "player.play(songs: playable.songs, album: playable.album, at: 0)")):
        part = body(view, opening)
        assert call in part and "await" not in part and "Task" not in part, opening
    found = body(view, "private func playableAlbum(")
    assert "await" not in found and "Task" not in found
    # the desk's calls are the page's own, nothing between
    desk = flat(body(view, "private func artistDesk("))
    for call in ("play: { play(shuffle: false, online: online, offlineAlbums: offlineAlbums) }",
                 "shuffle: { play(shuffle: true, online: online, offlineAlbums: offlineAlbums) }",
                 "playAlbum: { (id: String) -> Void in playAlbum(id, online: online) }"):
        assert call in desk, call
    # a top song's tap (the phone's row) - the list in hand, from the row, nothing awaited
    row = body(bare(source(SECTION)), "struct TopSongRow: View {")
    tap = body(row, "private func play() {")
    assert "TopSongs.play(all, from: row.rank, playable:" in tap and "player.play(playlist: plan.songs, at: plan.at)" in tap
    assert "await" not in tap and "Task" not in tap
    assert flat(row).count("Button { play() }") == 1
    # and the Mac's, ArtistView's own: a top song's (as TopSongRow's) and a most-played one's
    for opening, plan in (("private func playTop(_ rows: [TopSongs.Row], from row: TopSongs.Row) {",
                           "TopSongs.play(rows, from: row.rank, playable:"),
                          ("private func playMost(_ rows: [MostPlayedSongs.Row], from row: MostPlayedSongs.Row) {",
                           "MostPlayedSongs.play(rows, from: row.rank, playable:")):
        tap = body(view, opening)
        assert plan in tap and "player.play(playlist: plan.songs, at: plan.at)" in tap, opening
        assert "await" not in tap and "Task" not in tap, opening
    for call in ("playTop: { (rows: [TopSongs.Row], row: TopSongs.Row) -> Void in playTop(rows, from: row) }",
                 "openTop: { (row: TopSongs.Row) -> Void in openTop(row) }",
                 "playMost: { (rows: [MostPlayedSongs.Row], row: MostPlayedSongs.Row) -> Void in playMost(rows, from: row) }"):
        assert call in desk, call
    # the Mac's toolbar and its rows call the desk's, nothing between
    mac = flat(bare(source(MAC_PAGE)))
    assert "Button(action: desk.play) {" in mac and "Button(ShuffleWords.shuffle, action: desk.shuffle)" in mac
    assert "Button { desk.playAlbum(mine.albumId) } label:" in mac
    top = body(mac, "private func openTop(_ row: TopSongs.Row) {")
    assert "case .have(let song, _): guard plays(song) else { return } desk.playTop(desk.top, row)" in top
    assert "case .missing: desk.openTop(row)" in top and "case .waiting, .unknown: return" in top
    most = body(mac, "private func openMost(_ row: MostPlayedSongs.Row) {")
    assert "guard plays(row.song) else { return } desk.playMost(desk.mostPlayed, row)" in most
    for opened in (top, most):
        assert "await" not in opened and "Task" not in opened
    assert "open: { (line: TopLine) -> Void in openTop(line.row) }" in mac
    assert "open: { (row: MostPlayedSongs.Row) -> Void in openMost(row) }" in mac


# ----------------------------------------------------------------------------- the Mac's page

def test_the_macs_artist_is_drawn_by_the_phones_page():
    area = flat(bare(source(MAC_AREA)))
    assert "case .artist(let artist): ArtistView(route: artist, desk: MacArtistPage.init(desk:))" in area
    view = flat(bare(source(VIEW)))
    assert "if let desk, Platform.mac { desk(artistDesk(rows: rows, albums: albums, mine: mine," in view
    assert "extension ArtistView where Desk == EmptyView {" in view
    assert "init(route: ArtistRoute) { self.route = route desk = nil" in view
    # the page's one sheet and one pull, its asks, all ArtistView's: the Mac's page asks nothing itself
    mac = flat(bare(source(MAC_PAGE)))
    for asked in ("await", "Task", ".task", "client.", ".appSheet", ".pullToRefresh"):
        assert asked not in mac, asked


def test_the_macs_band_toolbar_and_status():
    mac = flat(bare(source(MAC_PAGE)))
    band = body(mac, "private func band(")
    for part in ("ArtistHeroPicture(managing: desk.managing, coverArt: model.coverArt, side: Drawn.picture,",
                 "Text(model.name) .font(Typeface.Mac.text(.h1).weight(.bold))",
                 "let facts = MBArtistPage.factsLine(model.facts)",
                 "ForEach(ArtistPageFacts.chips(counts, mayGet: desk.mayGet)) { (chip: ArtistPageFacts.Chip) in "
                 "DWChip(words: chip.words, tone: chip.yours ? .good : .plain) }"):
        assert part in band, part
    drawn = flat(body(bare(source(MAC_PAGE)), "    enum Drawn {"))
    assert "static let band: CGFloat = 132" in drawn and "static let picture: CGFloat = 88" in drawn
    tools = body(mac, "@ViewBuilder private func tools(_ fit: Fit) -> some View {")
    assert "if let theirs = desk.theirs { MacGroove() DWSegmented(options: [true, false]," in tools
    assert "set: { (studio: Bool) -> Void in desk.studio(studio) }), spoken: ArtistPageFacts.Words.studioLabel" in tools
    assert "ViewThatFits(in: .horizontal) { tools(.full) tools(.folded) }" in mac
    assert ".macStatus(MacStatusItems.Items(leading: ArtistPageFacts.status(counts, songs: desk.songs)))" in mac
    # the page's order under the band: Top Songs (in place), the discography, Top Songs (late), Most played
    page = body(mac, "@ViewBuilder private var page: some View {")
    order = [page.index(part) for part in ("== .inPlace { topSongs }", "discography", "!= .inPlace { topSongs }",
                                           "if !desk.mostPlayed.isEmpty { mostPlayed }")]
    assert order == sorted(order)


def test_the_macs_discography_takes_the_row_size_and_fits_its_pages():
    mac = flat(bare(source(MAC_PAGE)))
    table = body(mac, "@ViewBuilder private var discography: some View {")
    assert ("MacColumnList(columns: Self.columns, rows: rows, controls: [Self.buttonsColumn], voice: { (row: "
            "ArtistJoin.Row) -> MacRowVoice in voice(row) }, flow: flow(.discography), selected: $selected,") in table
    # (R6's review) "Albums" over it, the phone's heading: a row whose end is where A2's albums order will go
    assert "if !rows.isEmpty || desk.theirs != nil { albumsHead }" in table
    assert "private var albumsHead: some View { sectionHead(ArtistWords.albumsHeading) }" in mac
    head = body(mac, "private func sectionHead(")
    assert "HStack(alignment: .firstTextBaseline, spacing: 8) { Text(words)" in head and "Spacer(minLength: 0) }" in head
    assert ".frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))" in body(mac, "private func cell(")
    assert "@Environment(\\.macRowSize) private var rowSize" in source(MAC_PAGE)
    # the columns: Album and In your library flexible, Year, Songs and the buttons fixed
    columns = flat(source(MAC_PAGE))
    columns = columns[columns.index("static let columns = ["):columns.index("]", columns.index("static let columns = ["))]
    assert re.findall(r"width: \.(\w+)", columns) == ["flexible", "fixed", "fixed", "flexible", "fixed"]
    drawn = body(bare(source(MAC_PAGE)), "    enum Drawn {")
    fixed = [float(re.search(rf"static let {name}: Double = (\d+)", drawn).group(1)) for name in ("year", "songs", "actions")]
    assert fixed == [56, 60, 140]
    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    sidebar, dock = number(look, "sidebarWidth"), number(look, "panelWidth")
    opening, smallest = number(frame, "openingWidth"), number(frame, "smallestWidth")
    column, web = number(frame, "columnMin"), number(frame, "panelWidth")
    narrowest = column - sidebar - max(dock, web) - 1
    assert (opening - sidebar, smallest - sidebar, narrowest) == (1060, 660, 589)
    # each flexible column keeps its widest chip and its 10 either side, on the narrowest page - nothing sideways
    flexible = (narrowest - sum(fixed)) / 2
    chip = max(fonts.words(words, 11.5, "semibold") + 2 * 7 for words in ("In your library", "In the collection"))
    assert chip + 2 * 10 <= flexible, (chip, flexible)
    # the buttons column: Play (its glyph and 4) and Open, 6 apart, at .btn.sm's 12 with 8 either side - or Get, or
    # Open - in its 10 either side
    # (the chip's words: Whose.heldLabel's, its phrases capitalised)
    whose = core("Whose.swift")
    assert 'inYourLibrary = "in your library"' in whose and 'inTheCollection = "in the collection"' in whose
    button = lambda words: fonts.words(words, 12, "medium") + 2 * 8  # noqa: E731
    assert button("Play") + 14 + 6 + button("Open") + 2 * 10 <= fixed[2]
    assert button("Get") + 2 * 10 <= fixed[2]


def test_the_macs_top_songs_and_most_played_take_the_row_size_and_fit():
    mac = flat(bare(source(MAC_PAGE)))
    top = body(mac, "private var topSongs: some View {")
    assert "MacColumnList(columns: Self.topColumns, rows: lines, flow: flow(.top), selected: $selectedTop," in top
    assert "LastfmCredit(lastfmPage: desk.model.lastfm?.url, font: Typeface.Mac.text(.small)," in top
    most = body(mac, "private var mostPlayed: some View {")
    assert "MacColumnList(columns: Self.mostColumns, rows: desk.mostPlayed, flow: flow(.most), selected: $selectedMost," in most
    assert ("SongRightClick(menu: QueueMenuRequest(pick: QueuePick.song(row.song, of: row.album), album: row.album))"
            in most)
    cover = body(mac, "private func songCover(")
    assert ".frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))" in cover
    # a top song's right-click its •••, for one you have alone
    line = body(mac, "private struct TopLine: Identifiable {")
    assert "guard case .have(let song, let album) = row.kind else { return nil }" in line
    # the columns: the rank, the song and its album sharing what's left - Most played's Plays at the end
    columns = flat(source(MAC_PAGE))
    top_columns = columns[columns.index("static let topColumns = ["):columns.index("static let mostColumns")]
    assert re.findall(r"width: \.(\w+)", top_columns) == ["fixed", "flexible", "flexible"]
    assert ("static let mostColumns = topColumns + [MacListColumn(title: MacAlbumFacts.Words.plays, "
            "width: .fixed(Drawn.plays))]") in columns
    drawn = body(bare(source(MAC_PAGE)), "    enum Drawn {")
    rank, plays = (float(re.search(rf"static let {name}: Double = (\d+)", drawn).group(1)) for name in ("number", "plays"))
    assert (rank, plays) == (46, 70)
    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    narrowest = number(frame, "columnMin") - number(look, "sidebarWidth") - max(number(look, "panelWidth"),
                                                                              number(frame, "panelWidth")) - 1
    # beside the panel, each of the two shared columns keeps a cover and some of its words, nothing sideways
    assert (narrowest - rank - plays) / 2 >= 160
    # the plays a readout, spoken as words
    cell = body(mac, "private func mostCell(")
    assert "Text(row.playsWords) .font(Typeface.Mac.mono(.small))" in cell
    assert ".accessibilityLabel(ArtistPageFacts.Words.plays(row.plays))" in cell
    # a cover in a table's row rides on its title: beside it in a centred stack, never in a cell of its own (the
    # fonts' rule, test_ios_readout_rows.py's test_a_tables_cover_rides_on_its_title, for this page's three builders)
    for builder, stack in (("private func topCell(", "HStack(spacing: 8) { songCover(Self.cover(row)) Text(row.title)"),
                           ("private func mostCell(", "HStack(spacing: 8) { songCover(row.album.coverArt) Text(row.title)"),
                           ("private func cell(_ row: ArtistJoin.Row", "HStack(spacing: 8) { cover(row) .frame(")):
        cells = body(mac, builder)
        assert stack in cells, builder
        assert len(re.findall(r"(?<![\w.])(?:songCover|cover)\(", cells)) == 1, builder
    assert re.search(r"Text\(ArtistPageFacts\.title\(row\)\)", body(mac, "private func cell(_ row: ArtistJoin.Row"))


def test_the_macs_toolbar_folds_to_every_page():
    # the toolbar as drawn: Play (its glyph and 6), Shuffle, the groove, Studio only | Everything, and the managers'
    # three; folded, the three in a ••• - 6 apart, 12 in either side, .btn's 12.5 with 11 either side, .seg.lg's 10
    words = flat(core("ArtistPageFacts.swift"))
    studio = re.search(r'public static let studioOnly = MBArtistPage\.studioOnly', words)
    assert studio
    studio_words = re.search(r'public static let studioOnly = "([^"]+)"', core("MBArtist.swift")).group(1)
    everything = re.search(r'public static let everything = "([^"]+)"', words).group(1)
    manage = core("ArtistManageFlow.swift")
    images = re.search(r'public static let imagesItem = "([^"]+)"', manage).group(1).replace("\\u{2026}", "…")
    who = re.search(r'public static let whoItem = "([^"]+)"', manage).group(1)
    move = re.search(r'public static let moveAlbums = "([^"]+)"', words).group(1).replace("\\u{2026}", "…")
    control = 12.5
    button = lambda text: fonts.words(text, control, "medium") + 2 * 11  # noqa: E731
    parts = {
        "play": fonts.words("Play", control, "semibold") + 14 + 6 + 2 * 11,
        "shuffle": button("Shuffle"),
        "groove": 2 + 2 * 5,
        "segments": sum(fonts.words(w, control, "semibold") + 2 * 10 for w in (studio_words, everything)) + 2,
        "tools": button(images) + button(move) + button(who) + 2 * 6,
        "more": button("•••"),
    }

    def toolbar(folded: bool) -> float:
        drawn = [parts["play"], parts["shuffle"], parts["groove"], parts["segments"],
                 parts["more"] if folded else parts["tools"]]
        return sum(drawn) + 6 * (len(drawn) - 1) + 2 * 12

    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    sidebar, dock = number(look, "sidebarWidth"), number(look, "panelWidth")
    column, web = number(frame, "columnMin"), number(frame, "panelWidth")
    opening = number(frame, "openingWidth")
    # as drawn in a window as it opens; folded beside a side panel's column - every control in reach on each
    assert toolbar(False) <= opening - sidebar, toolbar(False)
    assert toolbar(True) <= column - sidebar - max(dock, web) - 1, toolbar(True)
    mac = flat(bare(source(MAC_PAGE)))
    assert "case .folded: if desk.offered.any { Menu { toolItems } label: { Image(systemName: \" \") }" in mac
    assert ".accessibilityLabel(ArtistManageWords.more)" in mac


def test_most_played_is_each_song_once_from_the_albums_in_hand():
    view = flat(bare(source(VIEW)))
    most = body(view, "private func mostPlayed(")
    assert "guard !(online && model.answer == nil)," in most
    assert "TopSongs.library(order: ArtistPage.playOrder(mine), asks: model.asks, online: online," in most
    assert "return MostPlayedSongs.rows(library.albums)" in most
    assert "mostPlayed: mostPlayed(mine, online: online)," in body(view, "private func artistDesk(")
    # Core: one row per song (LastfmMatch.key, Top Songs' own), its plays its most-played take's, never a sum
    rule = flat(body(core("MostPlayed.swift"), "public static func rows(_ albums: [Album]) -> [Row] {"))
    assert "LastfmMatch.key(" in rule and "+=" not in rule and "reduce" not in rule


# ----------------------------------------------------------------------------- (R6's review) the facts line, the Mac's lists

def test_the_facts_line_keeps_its_room_once_asked():
    # who they are asked (an MBID, deadwax in reach) or in hand: the line under the name drawn from then on, blank until
    # it comes - and kept for the page's life, so a late line, or none, never moves Play
    rule = flat(body(core("ArtistPageFacts.swift"), "public static func holdsFacts("))
    assert "facts != nil || (online && MBID.of(mbid) != nil)" in rule
    view = flat(bare(source(VIEW)))
    assert view.count("ArtistPageFacts.holdsFacts(") == 1
    assert "let factsAsked = ArtistPageFacts.holdsFacts(mbid: mbid, online: online, facts: model.facts)" in view
    assert view.count("phoneHero(managing, lastfm: lastfm, factsRoom: factsAsked || factsRoomFor == taskKey)") == 1
    assert (".onChange(of: factsAsked, initial: true) { (_: Bool, asked: Bool) -> Void in if asked && factsRoomFor != "
            "taskKey { factsRoomFor = taskKey } }") in view
    hero = body(view, "private func phoneHero(")
    line = body(hero, "if factsRoom || !facts.isEmpty {")
    assert 'Text(facts.isEmpty ? " " : facts)' in line and ".accessibilityHidden(facts.isEmpty)" in line
    assert hero.count("Text(facts") == 1, "the one line, its room and its words"


#? (R6's review) MacColumnList's parts every other list draws through, digested as at 31cab12d (R1c, before R6): the
#? box - the body until R6's review, now `box` - the header, a heading's row, and a row's drawing up to its hit shape.
#? Identical, so Albums, Artists, Playlists, an album's songs and a playlist's draw as before; a change to one is a
#? change to every list, said in its commit.
COLUMN_LIST = "Mac/Components/MacColumnList.swift"
COLUMN_LIST_PARTS = {"box": "a82bb791900d4792", "header": "5ea8a1925d09454d", "heading": "0a5ad7e6350d6dee",
                     "line": "a9d8642816c53a3b"}


def column_list_parts(text: str) -> dict:
    import hashlib
    code = phone_look.bare(text)

    def inner(opening: str) -> str:
        whole = body(code, opening)
        return whole[whole.index("{", len(opening) - 1) + 1:-1]

    def digest(part: str) -> str:
        return hashlib.sha256(re.sub(r"\s+", " ", part.replace("@ViewBuilder", "")).strip().encode("utf-8")).hexdigest()[:16]

    line = code[code.index("private func line(_ row: Row, striped: Bool, widths: [Double]) -> some View {"):]
    line = line[:line.index(".contentShape(Rectangle())") + len(".contentShape(Rectangle())")]
    return {"box": digest(inner("    @ViewBuilder private var box: some View {")),
            "header": digest(inner("private func header(_ widths: [Double]) -> some View {")),
            "heading": digest(inner("private func heading(_ title: String) -> some View {")), "line": digest(line)}


def test_every_other_list_draws_as_before():
    assert column_list_parts(source(COLUMN_LIST)) == COLUMN_LIST_PARTS
    columns = flat(bare(source(COLUMN_LIST)))
    assert "var body: some View { if let flow { flowing(flow) } else { box } }" in columns
    # the three asks are nothing unless a page asks them - and only the artist's page and an album's do
    assert ("var controls: Set<Int> = [] " in columns and "var voice: ((Row) -> MacRowVoice)? = nil " in columns
            and "var flow: MacListFlow? = nil " in columns)
    for path in sorted((APP / "Mac").rglob("*.swift")):
        name = str(path.relative_to(APP))
        if name in (COLUMN_LIST, MAC_PAGE):
            continue
        code = flat(bare(path.read_text(encoding="utf-8")))
        for call in re.findall(r"MacColumnList\(.*?\) \{", code):
            #? (R11) the Mac's Tags asks two: its checkbox column a control (a double-click there ticks twice, never
            #? opens the file's every tag), and the row read as one ("Track 3, Shoot to Thrill, 5:17, checked")
            #? with Select or Deselect and See a file's every tag... its actions - `.combine` would read the checkbox's
            #? words into the row's, as an artist's buttons would theirs
            if name == "Mac/Edit/MacTagsTab.swift":
                assert "controls: [0], voice:" in call and "flow:" not in call, name
                continue
            assert "voice:" not in call and "flow:" not in call, name
            assert "controls:" not in call or name == "Mac/Album/MacAlbumPage.swift", name


def test_the_macs_lists_are_lazy_rows_of_the_pages_own_scroll_view():
    mac = flat(bare(source(MAC_PAGE)))
    # one scroll view, one lazy stack: the band, then each list's header and rows as lines of it - never a list framed
    # to its rows' height with its scroll turned off (every row and cover made at once)
    assert "ScrollView(.vertical) { LazyVStack(alignment: .leading, spacing: 0) { band(counts) page }" in mac
    for gone in ("boxHeight", ".scrollDisabled", "rowSize.boxHeight", "GeometryReader"):
        assert gone not in mac, gone
    for section in ("private var topSongs: some View {", "private var mostPlayed: some View {",
                    "@ViewBuilder private var discography: some View {"):
        part = body(mac, section)
        assert "VStack" not in part and ".frame(height:" not in part and "MacColumnList(" in part, section
        assert "flow: flow(." in part, section
    held = body(body(mac, "@ViewBuilder private var page: some View {"), "if !desk.arrival.holding {")
    assert "VStack" not in held
    # the page's width the columns' (measured inside the scroll view, where the rows are), its keys the list's a click
    # last went to, heard on the scroll view itself
    assert ".onGeometryChange(for: Double.self) { (page: GeometryProxy) -> Double in Double(page.size.width) }" in mac
    assert ("MacListFlow(width: width, name: table.rawValue) { keysFor = table keysHere = true }"
            in body(mac, "private func flow(_ table: Table) -> MacListFlow {"))
    assert (".focusable() .focused($keysHere) .focusEffectDisabled() .listKeys { (key: ListKey) -> KeyPress.Result in "
            "pressed(key) }") in mac
    pressed = body(mac, "private func pressed(_ key: ListKey) -> KeyPress.Result {")
    assert "switch MacListKeys.pressed(key, selected: selection(table), in: ids(table)) {" in pressed
    # Return looks the row up again by its key as it opens, in each list
    assert pressed.count(".first(where:") == 3 and "openTop(row)" in pressed and "openMost(row)" in pressed
    # ↑ and ↓ reach a row through the page's own ScrollViewReader, by the key the list's ForEach is identified by
    assert "proxy.scrollTo(MacListFlow.key(table.rawValue, id))" in body(mac, "private func bring(")
    for state, table in (("selected", "discography"), ("selectedTop", "top"), ("selectedMost", "most")):
        assert (f".onChange(of: {state}) {{ (_: String?, now: String?) -> Void in bring(.{table}, now, proxy) }}"
                in mac), state
        assert f".onChange(of: ids(.{table})) {{ (_: [String], now: [String]) -> Void in keep(.{table}, in: now) }}" in mac
    assert "let kept = MacTable.kept(selection(table), in: ids)" in body(mac, "private func keep(")
    # MacColumnList's section: its header and its lines, no box, no scroll view - each line identified by its key
    columns = flat(bare(source(COLUMN_LIST)))
    flowing = body(columns, "@ViewBuilder private func flowing(_ flow: MacListFlow) -> some View {")
    assert "total: flow.width)" in flowing and "header(widths) ForEach(keyed) {" in flowing
    assert "MacListFlow.Keyed(id: flow.key(item, at: at), at: at, item: item)" in flowing
    for gone in ("ScrollView", "GeometryReader", ".frame(", ".id("):
        assert gone not in flowing, gone
    key = body(columns, "struct MacListFlow {")
    assert 'static func key(_ name: String, _ id: String) -> String { "\\(name):\\(id)" }' in flat(source(COLUMN_LIST))
    assert "case .row(let id): return key(id)" in key
    # the list's own keys and the page's, the one rule
    assert "switch MacListKeys.pressed(key, selected: selected, in: ids) {" in columns
    assert "flow?.clicked()" in body(columns, "private func click(")


def test_a_double_click_on_a_rows_buttons_is_theirs():
    columns = flat(bare(source(COLUMN_LIST)))
    line = body(columns, "private func line(_ row: Row, striped: Bool, widths: [Double]) -> some View {")
    assert ("simultaneousGesture(SpatialTapGesture(count: 2).onEnded { (tap: SpatialTapGesture.Value) -> Void in guard "
            "MacTable.opens(at: Double(tap.location.x), widths: widths, controls: controls) else { return } "
            "click(MacTable.clicked(row.id, count: 2), row: row) })") in line
    assert "TapGesture(count: 2)" not in line.replace("SpatialTapGesture(count: 2)", "")
    # the artist's buttons column, and an album's •••: the only cells with buttons in any Mac list
    mac = flat(bare(source(MAC_PAGE)))
    assert "static let buttonsColumn = 4" in mac
    columns_list = flat(source(MAC_PAGE))
    listed = columns_list[columns_list.index("static let columns = ["):columns_list.index("static let topColumns")]
    assert re.findall(r"title: ([\w.]+)", listed)[4] == "ArtistPageFacts.Words.actions"
    assert "@ViewBuilder private func buttons(" in mac and "default: buttons(row)" in body(mac, "private func cell(_ row: ArtistJoin.Row")
    album = flat(bare(source("Mac/Album/MacAlbumPage.swift")))
    assert "lines: drawn, controls: [Self.columns.count - 1]," in album
    album_columns = flat(source("Mac/Album/MacAlbumPage.swift"))
    album_columns = album_columns[album_columns.index("static let columns = ["):]
    album_columns = album_columns[:album_columns.index("]")]
    assert re.findall(r"title: ([\w.]+)", album_columns)[-1] == "MacAlbumFacts.Words.more"
    assert "default: QueueMenu(request: desk.row(song, album))" in body(album, "private func cell(")
    # every other list's cells hold no button, nor a menu: nothing there for a double-click to land on
    for name in ("Mac/Album/MacPlaylistPage.swift", "Mac/Library/MacAlbumsPage.swift", "Mac/Library/MacArtistsPage.swift",
                 "Mac/Library/MacPlaylistsPage.swift"):
        code = flat(bare(source(name)))
        cells = body(code, "private func cell(")
        assert not re.search(r"\bButton\b|\bMenu\b|QueueMenu\(|\bToggle\b|\bLink\(", cells), name
    # Core's rule (MacTableControlsTests run it)
    rule = flat(body(core("MacTable.swift"), "public static func opens("))
    assert ("guard !controls.isEmpty, let column = column(at: x, widths: widths) else { return true } return "
            "!controls.contains(column)") in rule


def test_voiceover_reads_a_discography_row_as_one_with_its_buttons_its_actions():
    mac = flat(bare(source(MAC_PAGE)))
    table = body(mac, "@ViewBuilder private var discography: some View {")
    assert "voice: { (row: ArtistJoin.Row) -> MacRowVoice in voice(row) }" in table
    voice = body(mac, "private func voice(_ row: ArtistJoin.Row) -> MacRowVoice {")
    assert "MacRowVoice(label: ArtistPageFacts.spoken(row, personal: desk.personal, format: format), actions: actions)" in voice
    for action in ("MacRowAction(words: ArtistPageFacts.Words.play) { desk.playAlbum(mine.albumId) }",
                   "MacRowAction(words: ArtistPageFacts.Words.open) { open(row) }",
                   "MacRowAction(words: get ? ArtistPageFacts.Words.get : ArtistPageFacts.Words.open) { open(row) }"):
        assert action in voice, action
    # each only as its button is drawn: Play while the album plays, none while dimmed, none while it is asked for
    assert "if !dimmed(row) { if desk.playsAlbum(mine.albumId) {" in voice
    assert "if desk.theirs?.opening != other.key {" in voice
    # MacColumnList's: with a voice, one element of its words, its buttons its actions - else its cells, as before
    columns = flat(bare(source(COLUMN_LIST)))
    voiced = body(columns, "private struct MacRowVoicing: ViewModifier {")
    given = voiced[voiced.index("if let voice {"):voiced.index("} else {")]
    for part in (".accessibilityElement(children: .ignore)", ".accessibilityLabel(voice.label)",
                 ".accessibilityAction { open() }",
                 ".accessibilityActions { ForEach(voice.actions) { (action: MacRowAction) in Button(action.words, "
                 "action: action.run) } }"):
        assert part in given, part
    assert ".combine" not in given
    rest = voiced[voiced.index("} else {"):]
    assert ".accessibilityElement(children: .combine)" in rest and ".accessibilityAction { open() }" in rest
    assert ".modifier(MacRowVoicing(voice: voice?(row), selected: on) { open(row) })" in body(
        columns, "private func line(_ row: Row, striped: Bool, widths: [Double]) -> some View {")


# ----------------------------------------------------------------------------- VoiceOver, sizes, words

def test_each_row_is_one_element_and_grows_with_the_text():
    view = flat(bare(source(VIEW)))
    section = flat(bare(source(SECTION)))
    mac = flat(bare(source(MAC_PAGE)))
    rows = [body(view, "private struct ArtistAlbumRow: View {"), body(view, "private struct ArtistTheirRow: View {"),
            body(section, "private func have(")]
    for row in rows:
        assert ".accessibilityElement(children: .ignore)" in row and ".accessibilityLabel(" in row, row[:60]
        assert ".accessibilityAction {" in row, row[:60]
        # (R6's review) one element, and only one: no `.contain` (or `.combine`) laid over the `.ignore`
        assert row.count(".accessibilityElement(") == 1, row[:60]
    # a song you don't have: a plain button, one element, its tap its action
    missing = body(section, "private var missing: some View {")
    assert ".accessibilityElement(children: .ignore) .accessibilityLabel(spoken(line))" in missing
    assert ".accessibilityAddTraits(.isButton)" in missing
    # the Mac's three lists MacColumnList's: a row one element, its cells in order, its action opening it
    assert mac.count("MacColumnList(columns: Self.") == 3
    have = body(section, "private func have(")
    assert ".addToQueueAction(menu) .addToPlaylistAction(menu)" in have
    # a song row's ••• a finger's 44 on the phone; the rows tall rows at least, growing (lookHeight is a least on the
    # phone), the title and its line taking 3 lines at the accessibility sizes
    assert ".frame(minWidth: CGFloat(DWLook.here.target), minHeight: CGFloat(DWLook.here.target))" in have
    face = body(section, "struct ArtistSongFace<")
    assert ".lookHeight(DWLook.here.tallRowHeight)" in face
    assert face.count(".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)") == 2
    hero = body(view, "private func phoneHero(")
    assert "let stacked = typeSize.isAccessibilitySize" in hero and ".lineLimit(3)" in hero


def test_the_word_is_queue():
    for name in PAGES + (STRIP,):
        text = source(name)
        literals = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', text)
        assert not [words for words in literals if "Up Next" in words], name
    for name in ("ArtistPageFacts.swift", "MostPlayed.swift"):
        assert "Up Next" not in core(name), name
