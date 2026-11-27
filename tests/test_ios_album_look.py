"""The redesign's slice R5 (notes/ios.md "The redesign, slice R5: an album, Playlists, a playlist"): an album's page and
a playlist's on the phone as iAlbum.dc.html and iPlaylist.dc.html draw them, and on the Mac the album's page, Playlists
and a playlist as the Mac's own (Album.dc.html, Playlists.dc.html, Playlist.dc.html) - held to dw.css (ios/design/dw.css)
where it names a value, to the drawings' numbers where only a drawing does, and to the slice's rules: every play an
existing PlayerModel call made in the tap, Download on the page and in the •••, no Play Next or Play Last on the phone,
the pull and the rows' swipe kept, "Played yesterday" read against a `now` taken again at midnight, square and tokens
only on the phone.

Read from the source, as every test of the app's look is: nothing here builds or runs the app (the builds and the
device checks 553-558 do). Core's rules (a nil play count, the size of every disc, the days across midnight) are
DeadwaxKit's MacAlbumFactsTests."""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"

ALBUM_VIEW = "Album/AlbumView.swift"
HERO = "Album/AlbumHero.swift"
TRACK_ROW = "Album/TrackRow.swift"
PLAYLIST_VIEW = "Playlists/PlaylistView.swift"
QUEUE_MENU = "Player/QueueMenu.swift"
DOWNLOADS = "Downloads/DownloadControl.swift"
MAC_ALBUM = "Mac/Album/MacAlbumPage.swift"
MAC_PLAYLIST = "Mac/Album/MacPlaylistPage.swift"
MAC_PLAYLISTS = "Mac/Library/MacPlaylistsPage.swift"
MAC_PAGES = (MAC_ALBUM, MAC_PLAYLIST, MAC_PLAYLISTS)


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_album_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phone_look = _load("test_ios_phone_look")
bare = phone_look.bare
css = phone_look.css
px = phone_look.px


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


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


def constant(code: str, name: str) -> float:
    found = re.search(rf"static let {name}: CGFloat = ([0-9.]+)", code)
    assert found, name
    return float(found.group(1))


#? the parts R5 redrew on the phone: (file, the part's opening)
PHONE_PARTS = ((HERO, "enum AlbumPageLook {"), (HERO, "struct AlbumHero: View {"), (HERO, "struct AlbumPlayPair: View {"),
               (TRACK_ROW, "struct TrackRow: View {"), (TRACK_ROW, "struct DiscHeadingRow: View {"),
               (PLAYLIST_VIEW, "private struct PlaylistHero: View {"),
               (PLAYLIST_VIEW, "private struct PlaylistSongRow: View {"))


# ----------------------------------------------------------------------------- square, and tokens only

def test_the_phones_album_and_playlist_stay_square():
    # binding 5: "Leave the phone square" - no corner, no capsule of its own in what R5 drew on the phone
    for name, opening in PHONE_PARTS:
        part = body(bare(source(name)), opening)
        assert not re.search(r"cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b|\.shadow\(", part), opening
    # the covers flat and square (the drawings' .cover on the phone: no radius)
    hero = body(bare(source(HERO)), "struct AlbumHero: View {")
    assert ".clipShape(Rectangle())" in hero


def test_the_redrawn_parts_hold_only_tokens():
    # no colour made, by number or by name, no opacity, radius or font of their own - and no old Palette in what R5 drew
    left = []
    parts = [(name, body(bare(source(name)), opening)) for name, opening in PHONE_PARTS]
    parts += [(name, bare(source(name))) for name in MAC_PAGES]
    for name, code in parts:
        for what, pattern in (("a colour made", r"\bColor\s*\((?!\))|\bUIColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a system colour", r"\.foregroundStyle\(\.(primary|secondary|tertiary|red|white)\)"),
                              ("a font of its own", r"\.system\(|Font\.(system|custom)|\.monospaced\(\)"),
                              ("a radius of its own", r"cornerRadius|RoundedRectangle\("),
                              ("the old palette", r"\bPalette\.\w+|\bCorners\.\w+")):
            if re.search(pattern, code):
                left.append(f"{name}: {what} - {re.search(pattern, code).group(0)}")
    assert not left, left


# ----------------------------------------------------------------------------- the phone's numbers

def test_the_phones_pages_are_the_drawings_numbers():
    look = body(bare(source(HERO)), "enum AlbumPageLook {")
    # iAlbum.dc.html and iPlaylist.dc.html's own inline numbers (each line's `drawn:` comment says where)
    drawn = {"albumCover": 204, "playlistCover": 150, "heroTop": 6, "heroSide": 16, "titleAbove": 16,
             "playlistTitleAbove": 14, "artistAbove": 2, "metaAbove": 6, "chipsAbove": 10, "chipGap": 6, "playGap": 12,
             "playAbove": 16, "playBelow": 14, "numberWidth": 30, "numberGap": 10, "rowSide": 16, "timeTrail": 4,
             "moreTrail": 16}
    for name, value in drawn.items():
        assert constant(look, name) == value, name
    assert len(re.findall(r"static let \w+: CGFloat = ", look)) == len(drawn), "every number held here"
    # (R5's review) the title at 56, not 62: the drawing's number box is 46 wide holding its own 16 (dw.css's
    # border-box), and the title's cell pads 10 - so 16 + 30 + 10
    assert css(".row div", "box-sizing") == "border-box"
    assert px(css(".row div", "padding-left")) == constant(look, "numberGap")
    assert constant(look, "rowSide") + constant(look, "numberWidth") + constant(look, "numberGap") == 56
    said = body(source(HERO), "enum AlbumPageLook {")
    assert all("// drawn: iAlbum" in line or "// drawn: iPlaylist" in line
               for line in said.splitlines() if "static let" in line), "each number says where it is drawn"
    # Play and Shuffle at 48 (dw.ph's .btn.lg), the songs 48 (.row), a playlist's 60 (.row.tall)
    assert px(css(".dw.ph .btn.lg", "height")) == 48
    dwlook = (CORE / "DWLook.swift").read_text(encoding="utf-8")
    assert re.search(r"largeButtonHeight: 48,\s+// dw\.ph: \.btn\.lg height", dwlook)
    assert re.search(r"rowHeight: 48,\s+// dw\.ph: \.row height", dwlook)
    pair = flat(body(bare(source(HERO)), "struct AlbumPlayPair: View {"))
    assert ".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))" in pair
    assert ".buttonStyle(DWButtonStyle(size: .large, fills: true))" in pair
    assert "SharpSymbol(.play)" in pair, "Play stays a sharp glyph on the phone"
    row = flat(body(bare(source(TRACK_ROW)), "struct TrackRow: View {"))
    assert ".lookHeight(DWLook.here.rowHeight)" in row
    song = flat(body(bare(source(PLAYLIST_VIEW)), "private struct PlaylistSongRow: View {"))
    assert ".lookHeight(DWLook.here.tallRowHeight)" in song
    # the hero: the title 22 bold (20 for a long one), the artist in the accent, the meta and chips under it
    hero = flat(body(bare(source(HERO)), "struct AlbumHero: View {"))
    assert "model.longTitle ? Typeface.title3.bold() : Typeface.title2.bold()" in hero
    assert ".foregroundStyle(DWPalette.acc)" in hero
    assert "DWChip(words: model.mine.badge, tone: model.mine.yours == true ? .good : .plain)" in hero
    assert "AlbumPlayPair(enabled: playable, play: play, shuffle: shuffle)" in hero
    playlist = flat(body(bare(source(PLAYLIST_VIEW)), "private struct PlaylistHero: View {"))
    assert "AlbumPlayPair(enabled: playable && !model.gone, play: play, shuffle: shuffle)" in playlist


def test_a_songs_number_grows_with_the_text_and_is_spoken():
    # (R5's review) the number's room and the gap after it scaled as its words are - Typeface.Phone.mono(.small)
    # scales with .footnote - the drawing's 30 and 10 at the default size, so "999" fits at AX5; never a constant
    row = bare(source(TRACK_ROW))
    typeface = (APP / "Shared/Typeface.swift").read_text(encoding="utf-8")
    assert re.search(r"case \.small: return \(13, \.footnote\)", typeface)
    for name in ("numberWidth", "numberGap"):
        assert (f"@ScaledMetric(relativeTo: .footnote) private var {name}: CGFloat = AlbumPageLook.{name}") in row, name
    part = flat(body(row, "struct TrackRow: View {"))
    assert ("number .fixedSize() .frame(minWidth: numberWidth, alignment: .leading) .padding(.trailing, numberGap)"
            in part), "a number wider still takes its own room"
    assert "Text(AlbumPageLines.number(song)) .font(Typeface.Phone.mono(.small))" in part
    used = part.replace("CGFloat = AlbumPageLook.numberWidth", "").replace("CGFloat = AlbumPageLook.numberGap", "")
    assert "AlbumPageLook.numberWidth" not in used and "AlbumPageLook.numberGap" not in used
    assert not re.search(r"\.frame\(width: (AlbumPageLook\.)?number", part)
    # VoiceOver's one element reads the track number first, then the title - as before R5
    spoken = flat(body(row, "private func spoken(_ artist: String?) -> String {"))
    assert 'var parts = [AlbumPageLines.number(song), song.title ?? ""]' in spoken
    # Add to a playlist… always the one modifier, offered or not inside it (AddToQueueAction's way): no branch
    # between the row and the row with an action, which would make the row again as deadwax comes and goes
    action = flat(body(row, "private struct AddToPlaylistAction: ViewModifier {"))
    assert "content.accessibilityActions { if offered, let request {" in action
    assert "} else {" not in action and "@ViewBuilder" not in action
    queue = flat(body(bare(source("Player/AddToQueueSwipe.swift")), "private struct AddToQueueAction: ViewModifier {"))
    assert "content.accessibilityActions { if offered {" in queue


# ----------------------------------------------------------------------------- the phone's top row and its •••

def test_the_phones_top_row_is_back_edit_and_its_own_menu():
    view = bare(source(ALBUM_VIEW))
    bar = flat(body(view, "@ToolbarContentBuilder private var bar: some ToolbarContent {"))
    # iOS's own back before them (the bar's, never hidden); Edit only for whoever may edit the album; then the •••
    assert "toolbar(.hidden" not in view
    assert "if Managing.albumEdit(server.access.permissions).shown {" in bar
    assert "Button(PlaylistWords.edit) { editAction?() } .disabled(editAction == nil)" in bar
    assert "QueueMenu(request: barMenu) { Image(systemName: \" \") }" in bar
    # the ••• is the album's own, its Edit album the top row's Edit instead - and nothing else left out
    bar_menu = flat(body(view, "private var barMenu: QueueMenuRequest? {"))
    assert "request.editAlbum = nil" in bar_menu and bar_menu.count("request.") == 1
    playlist = bare(source(PLAYLIST_VIEW))
    toolbar = flat(body(playlist, "@ToolbarContentBuilder private func toolbar("))
    assert "if model.editable {" in toolbar
    assert "if let menu = playlistMenu { QueueMenu(request: menu) { Image(systemName: \" \") }" in toolbar
    # (R5's review) a playlist gone, or with no songs to queue, has no queue menu - its ••• still holds the
    # playlist's download items, Remove Download among them while a download of it is here
    fallback = toolbar[toolbar.index("} else { Menu {"):]
    assert "PlaylistDownloadMenuSection(answer: model.gone ? nil : model.answer, id: route.id, titled: true)" in fallback
    assert ".disabled(downloads.playlistState(route.id) == nil || !downloads.isOpen)" in fallback
    # the download controls left the bar - the ••• holds Download in their place - and are gone from the app
    for name, text in ((path, bare(path.read_text(encoding="utf-8"))) for path in APP.rglob("*.swift")):
        assert not re.search(r"\b(AlbumDownloadControl|PlaylistDownloadControl)\b", text), name
    # (R5's review) the title the bar takes once the hero's has gone under it: the album's page and the playlist's
    # agree on the Mac too - the principal outside what only the phone draws, on both
    assert bar.index("ToolbarItem(placement: .principal)") < bar.index("if desk == nil || !Platform.mac {")
    assert toolbar.index("ToolbarItem(placement: .principal)") < toolbar.index("if model.editing {")
    assert bar.count("ToolbarItem(placement: .principal)") == 1 == toolbar.count("ToolbarItem(placement: .principal)")


def test_download_is_on_the_page_and_in_the_dots():
    # the phone's •••: Add to Queue, Add to a playlist…, Download headed with the control's words, Album info, Refresh
    items = flat(body(bare(source(QUEUE_MENU)), "struct QueueMenuItems: View {"))
    order = [items.index(part) for part in ("Button(AddToQueue.words, systemImage: AddToQueue.symbol)",
                                            "Button(PlaylistWords.addToAPlaylistRow, systemImage: PlaylistWords.addSymbol)",
                                            "DownloadMenuSection(songs: request.pick.tracks,",
                                            "Button(AlbumInfoWords.title, systemImage: AlbumInfoWords.symbol)",
                                            "Button(LibrarySwitchWords.refresh, systemImage: \" \")")]
    assert order == sorted(order)
    assert "album: request.pick.queuedAs == .album ? request.album : nil" in items
    assert "PlaylistDownloadMenuSection(answer: playlist, titled: true)" in items
    assert "} else if request.offersDownload {" in items
    # the album's own ••• keeps its Download (nothing sets offersDownload off for it), its end announced
    view = bare(source(ALBUM_VIEW))
    album_menu = flat(body(view, "private var albumMenu: QueueMenuRequest? {"))
    assert "offersDownload" not in album_menu and "offersDownload" not in flat(body(view, "private var barMenu"))
    assert "request.downloadAsked = { askedHere = true }" in album_menu
    # an album's whole: the control's items and words, one rule for both (AlbumDownloadMenu)
    section = flat(body(bare(source(DOWNLOADS)), "struct DownloadMenuSection: View {"))
    assert "AlbumDownloadMenu.items(state, songs: songs, gone: gone, downloads: downloads)" in section
    assert "AlbumDownloadMenu.title(state, songs: songs, album: album, downloads: downloads, server: server)" in section
    assert "downloads.download(album: album) asked?()" in section
    # the Mac's toolbars: Download in words - at once with nothing here, else the control's own items
    mac = flat(body(bare(source(MAC_ALBUM)), "@ViewBuilder private var download: some View {"))
    assert "Button(DownloadWords.controlLabel) { guard let album else { return } downloads.download(album: album) desk.asked() }" in mac
    assert "AlbumDownloadMenu.items(state, songs: songs, gone: gone, downloads: downloads)" in mac
    tools = flat(body(bare(source(MAC_ALBUM)), "@ViewBuilder private func tools(_ fit: Fit) -> some View {"))
    assert tools.index("case .full:") < tools.index("download") < tools.index("case .folded:")
    playlist = flat(body(bare(source(MAC_PLAYLIST)), "@ViewBuilder private var download: some View {"))
    assert "PlaylistDownloadMenuSection(answer: answer, id: id, titled: true)" in playlist
    assert "downloads.download(playlist: answer)" in playlist


def test_no_play_next_or_play_last_on_the_phone():
    # James, 16 Nov: Add to Queue is the phone's one queue item - and the Mac's right-click offers that alone, so the
    # Mac's toolbars match it
    for name in (ALBUM_VIEW, HERO, TRACK_ROW, PLAYLIST_VIEW, QUEUE_MENU, DOWNLOADS, *MAC_PAGES):
        code = bare(source(name))
        assert not re.search(r"\bplayNext\b|\bplayLast\b|Play Next|Play Last|Play next|Play last|\.choose\(\.next",
                             code), name


def test_the_pull_and_the_rows_swipe_stay():
    view = bare(source(ALBUM_VIEW))
    assert ".pullsToShuffle(PullShuffling(state: pull, can: can, on: shown, start: pulled))" in view
    playlist = bare(source(PLAYLIST_VIEW))
    assert ".pullsToShuffle(PullShuffling(state: pull, can: can, on: shown && !editing, start: pulled))" in playlist
    # a row swiped right adds its song to the queue - the List's own leading swipe action
    for name, opening in ((TRACK_ROW, "struct TrackRow: View {"), (PLAYLIST_VIEW, "private struct PlaylistSongRow: View {")):
        row = flat(body(bare(source(name)), opening))
        assert ".addsToQueue(menu, in: .list)" in row, name
        # one VoiceOver element, the •••'s items its actions
        assert ".accessibilityElement(children: .ignore)" in row and ".addToQueueAction(menu)" in row, name
        assert ".addToPlaylistAction(menu)" in row, name


# ----------------------------------------------------------------------------- every play in the tap

def test_every_play_is_an_existing_call_in_the_tap():
    view = bare(source(ALBUM_VIEW))
    play = body(view, "private func play(at index: Int?, shuffle: Bool = false) {")
    call = play.index("player.play(songs: songs, album: album, at: index, shuffle: shuffle)")
    assert "await" not in play and "Task" not in play and call > 0
    row = body(view, "private func play(song: Song) {")
    assert "await" not in row and "Task" not in row and "play(at: index)" in row
    desk = flat(view[view.index("desk(AlbumDesk("):view.index("} else {", view.index("desk(AlbumDesk("))])
    assert "play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) }" in desk
    assert "playFrom: { (song: Song) -> Void in play(song: song) }" in desk
    playlist = bare(source(PLAYLIST_VIEW))
    lists = body(playlist, "private func play(at index: Int?, shuffle: Bool = false) {")
    assert "player.play(playlist: songs, at: index, shuffle: shuffle)" in lists
    assert "await" not in lists and "Task" not in lists
    assert "await" not in body(playlist, "private func play(row: Int) {")
    made = playlist[playlist.index("desk(PlaylistDesk("):playlist.index("} else {", playlist.index("desk(PlaylistDesk("))]
    assert "play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) }" in flat(made)
    # the Mac's pages call the page's own, nothing between
    for name in (MAC_ALBUM, MAC_PLAYLIST):
        code = flat(bare(source(name)))
        assert "Button(action: desk.play) {" in code and "Button(ShuffleWords.shuffle, action: desk.shuffle)" in code, name
    opened = flat(body(bare(source(MAC_ALBUM)), "private func open(_ line: Line) {"))
    assert "desk.playFrom(line.song)" in opened and "await" not in opened and "Task" not in opened
    opened = flat(body(bare(source(MAC_PLAYLIST)), "private func open(_ line: Line) {"))
    assert "desk.playRow(line.index)" in opened and "await" not in opened and "Task" not in opened
    lists = bare(source(MAC_PLAYLISTS))
    for opening, call in (("private func play() {", "player.play(playlist: songs, at: 0, shuffle: false)"),
                          ("private func shuffle() {", "player.play(playlist: songs, at: nil, shuffle: true)")):
        part = body(lists, opening)
        assert call in part and "await" not in part and "Task" not in part, opening
    # the right-click's own calls on the toolbars: Add to Queue, Add to a playlist…
    menu = flat(body(bare(source(QUEUE_MENU)), "struct QueueMenuItems: View {"))
    assert "player.addToQueue(pick, album: request.album)" in menu
    for name in (MAC_ALBUM, MAC_PLAYLIST):
        code = flat(bare(source(name)))
        assert "player.addToQueue(pick, album: desk.menu?.album)" in code, name
        assert "navigation.playlistPick = PlaylistPickRequest(PlaylistPick(request.pick))" in code, name
        assert "AddToQueue.pick(request.pick, online: reachability.online, gone: request.gone, here: downloads.isHere)" in code


# ----------------------------------------------------------------------------- the Mac's pages

def test_the_macs_pages_are_routed_through_the_phones():
    album = bare(source("Mac/Album/MacAlbum.swift"))
    pages = flat(body(album, "static func page(for page: Page) -> some View {"))
    assert "case .album(let album): AlbumView(route: album, desk: MacAlbumPage.init(desk:)).id(album.id)" in pages
    assert "case .playlist(let playlist): PlaylistView(route: playlist, desk: MacPlaylistPage.init(desk:))" in pages
    # the Library's root: Playlists the Mac's own list
    desk = flat(body(bare(source("Mac/Library/MacArtistsPage.swift")), "struct MacLibraryDesk: View {"))
    assert "case .playlists: MacPlaylistsPage()" in desk
    # the desk only on the Mac: the iPhone's pages have none, and draw their own List
    for name, init in ((ALBUM_VIEW, "extension AlbumView where Desk == EmptyView {"),
                       (PLAYLIST_VIEW, "extension PlaylistView where Desk == EmptyView {")):
        code = bare(source(name))
        assert "desk = nil" in body(code, init), name
    assert "if let desk, Platform.mac {" in bare(source(ALBUM_VIEW))
    assert "if let desk, Platform.mac, !editing {" in bare(source(PLAYLIST_VIEW))


def test_the_macs_columns_are_the_drawings():
    column = r"MacListColumn\(title: MacAlbumFacts\.Words\.(\w+(?:\(Platform\.device\))?), width: \.(fixed\(\d+\)|flexible)\)"
    assert re.findall(column, bare(source(MAC_ALBUM))) == [
        ("number", "fixed(46)"), ("title", "flexible"), ("plays", "fixed(70)"), ("length", "fixed(66)"),
        ("more", "fixed(44)")]
    assert re.findall(column, bare(source(MAC_PLAYLIST))) == [
        ("number", "fixed(46)"), ("title", "flexible"), ("album", "fixed(190)"), ("length", "fixed(66)")]
    words = (CORE / "MacAlbumFacts.swift").read_text(encoding="utf-8")
    for name, said in (("number", "#"), ("title", "Title"), ("length", "Length"), ("playlist", "Playlist"),
                       ("whose", "Whose"), ("changed", "Changed"), ("more", "")):
        assert f'public static let {name} = "{said}"' in words, name
    # (R5's review) Playlists' columns are Core's, in the drawing's order, fitted to the page the list is given
    # (test_playlists_columns_fit_beside_the_side_panel) - each cell by its column, never by its place
    assert re.search(r"case playlist, songs, length, whose, changed, onDevice\n", words)
    lists = flat(bare(source(MAC_PLAYLISTS)))
    # (the Mac's Row Size) at the rows' size: Playlist's least grows with its cover
    assert ("GeometryReader { (room: GeometryProxy) in let shown = MacAlbumFacts.playlistColumns(width: Double(room.size.width), size: rowSize)"
            in lists)
    assert "MacColumnList(columns: Self.columns(shown), rows: rows, selected: $selected," in lists
    assert "if shown.indices.contains(column) { cell(playlist, shown[column]) }" in lists
    assert "MacListColumn(title: MacAlbumFacts.playlistTitle(column, device: Platform.device), width: MacAlbumFacts.playlistWidth(column))" in lists
    assert "MacListColumn(title: MacAlbumFacts.Words." not in lists
    # a song's Plays is MacAlbumFacts' (a nil count a blank, never 0); (R5's review) its # the song's own number, a
    # disc's heading row above its first song wherever the phone draws one (more than one disc, or a disc titled)
    cell = flat(body(bare(source(MAC_ALBUM)), "private func cell("))
    assert "Text(MacAlbumFacts.plays(song.playCount))" in cell
    assert "Text(AlbumPageLines.number(song))" in cell
    assert "playCount" not in cell.replace("MacAlbumFacts.plays(song.playCount)", "")
    assert not re.search(r"static func number\(_ song: Song, discs", words), "no \"2-3\" left to draw"
    assert "MacAlbumFacts.number(" not in flat(bare(source(MAC_ALBUM)))
    songs = flat(body(bare(source(MAC_ALBUM)), "private func songs(_ album: Album) -> some View {"))
    assert "let drawn = MacAlbumFacts.songLines(songs, headings: desk.model.headings)" in songs
    assert ("MacColumnList(columns: Self.columns, rows: rows, lines: drawn, controls: [Self.columns.count - 1], "
            "selected: $selected,") in songs
    # the headings the phone's own (AlbumModel's headings, DiscHeadings'), drawn by the list as group rows
    model = flat(bare(source("Models/AlbumModel.swift")))
    assert "DiscHeadings" in model and "headings" in model
    columns = flat(bare(source("Mac/Components/MacColumnList.swift")))
    assert "let drawn = lines ?? rows.map { (row: Row) -> MacTable.Line<String> in .row(row.id) }" in columns
    assert "let stripes = MacTable.stripes(drawn)" in columns
    assert "case .group(let title): heading(title)" in columns
    heading = flat(body(bare(source("Mac/Components/MacColumnList.swift")), "private func heading("))
    assert "MacLook.groupRowHeight" in heading and ".accessibilityAddTraits(.isHeader)" in heading
    # the box as tall as its rows and its headings; never asked to be taller at least than at most - (the Mac's Row
    # Size) its rows added up at the size the list draws them, Core's MacRowSize (MacRowSizeTests adds them up) - and
    # its least never more than the page has left (test_ios_mac_rows' test_a_short_window_keeps_properties_on_the_page)
    assert "let tall = CGFloat(rowSize.boxHeight(rows: rows.count, headings: headings))" in songs
    assert "let least = CGFloat(rowSize.boxLeast(rows: rows.count, headings: headings, room: boxRoom))" in songs
    sizes = (CORE / "MacRowSize.swift").read_text(encoding="utf-8")
    assert ("MacLook.headerHeight + rowHeight * Double(max(rows, 0)) + MacLook.groupRowHeight * Double(max(headings, 0)) + 2"
            in sizes)
    assert "min(MacLook.headerHeight + rowHeight * 3, boxHeight(rows: rows, headings: headings))" in sizes
    assert ".frame(minHeight: least, maxHeight: tall)" in songs


def test_playlists_columns_fit_beside_the_side_panel():
    # (R5's review) the drawing's fixed columns (80 + 110 + 130 + 140 + 150 = 610) left Playlist nothing beside the
    # side panel: Core's narrower ones, and Whose and Changed left out on a page too narrow for Playlist's least beside
    # them all. The narrowest page: a 1280 window beside the panel's column - held, as R8's table is, to MacFrame's
    # 470 (the dock R3 drew is MacLook's 400, a page of 659: every column fits there).
    facts = (CORE / "MacAlbumFacts.swift").read_text(encoding="utf-8")
    rule = facts[facts.index("public static func playlistWidth("):facts.index("public static let playlistLeast")]
    assert "case .playlist: return .flexible" in rule
    fixed = {name: float(points) for name, points in re.findall(r"case \.(\w+): return \.fixed\((\d+)\)", rule)}
    assert sorted(fixed) == ["changed", "length", "onDevice", "songs", "whose"]
    least = float(re.search(r"public static let playlistLeast: Double = (\d+)", facts).group(1))
    dropped = re.search(r"public static let playlistDropped: Set<PlaylistColumn> = \[([^\]]*)\]", facts).group(1)
    dropped = {part.strip().lstrip(".") for part in dropped.split(",")}
    assert least == 160 and dropped == {"whose", "changed"}
    look, frame = (CORE / "MacLook.swift").read_text(encoding="utf-8"), (CORE / "MacFrame.swift").read_text(encoding="utf-8")
    number = lambda text, name: float(re.search(rf"public static let {name}: Double = (\d+)", text).group(1))  # noqa: E731
    sidebar, dock = number(look, "sidebarWidth"), number(look, "panelWidth")
    column, smallest, web = number(frame, "columnMin"), number(frame, "smallestWidth"), number(frame, "panelWidth")
    narrowest = column - sidebar - max(dock, web) - 1
    assert narrowest == 589
    every = sum(fixed.values())
    beside = sum(points for name, points in fixed.items() if name not in dropped)
    # beside the panel, at its narrowest: Playlist keeps its least with Whose and Changed left out
    assert beside + least <= narrowest, (beside, least, narrowest)
    # the smallest window's page (880, the panel a drawer over it) and the dock's own page beside it: every column
    assert every + least <= smallest - sidebar, (every, least)
    assert every + least <= column - sidebar - dock - 1, (every, least)
    # and the rule is the width the list is given, all or the dropped left out (MacAlbumFactsTests runs it)
    # - (the Mac's Row Size) Playlist's least the rows' size's (test_ios_mac_rows checks Large still fits)
    choose = flat(body(facts, "public static func playlistColumns(width: Double, size: MacRowSize = .standard) -> [PlaylistColumn] {"))
    assert "if width - fixedWidth(all) >= playlistLeast(size) { return all }" in choose
    assert "!playlistDropped.contains(column)" in choose


def test_the_macs_album_page_draws_album_infos_folder():
    # (R5's review) Properties' Folder whenever Album info would show it: the same rule (AlbumInfo.server, for
    # whoever may see folders), from the model's bridge answer or - logins off, break-glass - one the page asks
    page = bare(source(MAC_ALBUM))
    properties = flat(body(page, "@ViewBuilder private func properties(_ album: Album) -> some View {"))
    assert "let folder = AlbumInfo.server(store: desk.model.store ?? bridged, folders: server.access.isAdmin).first" in properties
    assert "MacAlbumFacts.properties(album, songs: desk.model.songs, folder: folder)" in properties
    info = flat(bare(source("Album/AlbumInfoView.swift")))
    assert "folders: server.access.isAdmin" in info, "Album info's own rule"
    bridge = flat(body(page, "private func bridge() async {"))
    assert "guard model.store == nil, server.access.isAdmin, reachability.online, let client = server.client else { return }" in bridge
    assert "try? await client.storeAlbum(navidromeID: model.route.id)" in bridge
    assert "guard !Task.isCancelled else { return } bridged = answer" in bridge
    task = flat(page[page.index(".task(id: BridgeKey("):page.index("await bridge()")])
    assert "person: server.person, album: model.route.id, online: reachability.online, modelHasIt: model.store != nil" in task
    # the row's label Album info's own - "Folder" or "Folders" - never a word of the page's
    facts = (CORE / "MacAlbumFacts.swift").read_text(encoding="utf-8")
    assert "Fact(label: folder.label, value: folder.value)" in facts
    assert 'folder = "Folder"' not in facts


def test_playlists_plays_only_a_playlist_shown():
    # (R5's review) Play and Shuffle never play a playlist Find has hidden: the selection let go at the page as soon
    # as its row isn't listed (a list with no rows draws no MacColumnList to let it go), and `playable` the selected
    # playlist's songs only - the one asked for now, and only while its row is listed
    page = bare(source(MAC_PLAYLISTS))
    whole = flat(page)
    assert ("onChange(of: rows.map(\\.id), initial: true) { (_: [String], ids: [String]) -> Void in "
            "let kept = MacTable.kept(selected, in: ids) if kept != selected { selected = kept } }") in whole
    playable = flat(body(page, "private var playable: [Song] {"))
    guard = playable[:playable.index("else { return [] }")]
    for part in ("let chosen, let selected", "chosen.route.id == selected", "!chosen.gone",
                 "rows.contains(where: { (playlist: Playlist) -> Bool in playlist.id == selected })"):
        assert part in guard, part
    for opening in ("private func play() {", "private func shuffle() {"):
        assert "let songs = playable guard !songs.isEmpty else { return }" in flat(body(page, opening)), opening
    # the status: what is listed - Find's, the downloaded shelf offline - and nothing while none is
    assert ".macStatus(MacStatusItems.Items(leading: MacAlbumFacts.playlistsStatus(rows)))" in whole
    status = flat(body((CORE / "MacAlbumFacts.swift").read_text(encoding="utf-8"),
                       "public static func playlistsStatus(_ playlists: [Playlist]) -> [String] {"))
    assert "guard !playlists.isEmpty else { return [] }" in status


def test_the_macs_toolbars_fold():
    for name in (MAC_ALBUM, MAC_PLAYLIST):
        code = flat(bare(source(name)))
        assert "ViewThatFits(in: .horizontal) { tools(.full) tools(.folded) }" in code, name
        tools = flat(body(bare(source(name)), "@ViewBuilder private func tools(_ fit: Fit) -> some View {"))
        # folded: Play, Shuffle and the page's ••• - the right-click's items, nothing lost
        assert "QueueMenu(request: desk.menu) { Image(systemName: \" \") }" in tools, name
    album = flat(body(bare(source(MAC_ALBUM)), "@ViewBuilder private func tools(_ fit: Fit) -> some View {"))
    # Edit for whoever may, at the toolbar's end - the •••'s own Edit album
    assert "if Managing.albumEdit(server.access.permissions).shown { Button(PlaylistWords.edit) { desk.edit?() }" in album
    playlist = flat(body(bare(source(MAC_PLAYLIST)), "@ViewBuilder private func tools(_ fit: Fit) -> some View {"))
    assert "if let edit = desk.edit { Button(PlaylistWords.edit, action: edit)" in playlist
    assert ".disabled(!desk.canEdit)" in playlist


def test_played_and_changed_read_a_now_taken_again_at_midnight():
    midnight = ("@State private var now = ArtistTotals.now()",
                ".onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) "
                "{ _ in now = ArtistTotals.now() }")
    for name in (*MAC_PAGES, "Album/AlbumInfoView.swift"):
        code = flat(bare(source(name)))
        for part in midnight:
            assert part in code, f"{name}: {part}"
    assert "MacAlbumFacts.played(album, now: now)" in flat(bare(source(MAC_ALBUM)))
    assert "MacAlbumFacts.playlistLine(playlist, now: now)" in flat(bare(source(MAC_PLAYLIST)))
    assert "MacAlbumFacts.changed(playlist, now: now)" in flat(bare(source(MAC_PLAYLISTS)))
    # check 555: Albums' Info says the page's words - on the Mac only, the phone's Album info as it was
    info = flat(bare(source("Album/AlbumInfoView.swift")))
    assert "Platform.mac ? MacAlbumFacts.playedRow(album, now: now) : nil" in info
    assert "played: played(whole)" in info
    # and the day's words are R2's, no second set
    facts = (CORE / "MacAlbumFacts.swift").read_text(encoding="utf-8")
    assert "ArtistTotals.lastPlayedWords(ms, now: now, zone: zone)" in facts
    assert '"yesterday"' not in facts and '"today"' not in facts


def test_the_add_to_a_playlist_sheet_takes_the_shared_buttons():
    fields = flat(body(bare(source("Playlists/PlaylistPicker.swift")), "struct NewPlaylistFields: View {"))
    # (R18) each filling the row when stacked through the look's own `fills` (its flat words fill only when it does) -
    # the labels' `.frame(maxWidth: stacked ? .infinity : nil)` gone with it
    assert (".buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))" in fields
            and ".buttonStyle(DWButtonStyle(fills: stacked))" in fields)
    assert ".escapeCloses(" in fields, "Escape still the Playlists sheet's Cancel"
    # (R5's review) Create over Cancel at the accessibility sizes, each across the row - side by side otherwise
    assert "let stacked = typeSize.isAccessibilitySize" in fields
    assert ("let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) "
            ": AnyLayout(HStackLayout())") in fields
    assert "layout {" in fields and "if !stacked { Spacer() }" in fields
    assert ".frame(maxWidth: stacked ? .infinity : nil)" not in fields
