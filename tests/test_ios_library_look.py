"""The redesign's slice R2 (notes/ios.md "The redesign, slice R2: Albums and Artists, and the Library's top"): the
Library's top and pages as iLibrary, iArtists and iPlaylists draw them on the phone, and Albums and Artists as the Mac's
own column lists (Albums.dc.html, Artists.dc.html) - held to dw.css (ios/design/dw.css, the canvas's copy) where it
names a value, to the drawings' numbers where only a drawing does, and to James's answer 1 (25 Nov, "Today's behaviour,
new look"): Find kept, the pages in the order kept, Songs never beside your own albums, Yours | All in the All music
menu's place, each page's sort, and the pager's swipe, the pull and TopClearance as they were.

Since slice R2b (notes/ios.md "The redesign, slice R2b: the Library's top, one row again" - James, 25 Nov: "The top of
the library on iOS is actually kinda a mess, can we streamline it a bit?", "lets put the grid/list next to yours/all")
the top is one row - Find's circle, the switch of the pages, the •••'s circle - over one quiet line per page: its count,
its order or New playlist…, then Grid and List (Albums alone) and Yours | All, white where you are and purple what a
tap goes to; Downloaded is the •••'s again. The row and the line fit a 375 pt phone at every text size - the line
giving way inside itself first, its count's noun dropped, then folding - rather than cutting a word short, by the
arithmetic below; where each view goes is Core's (LibraryTopFit, MetaLine), tested in LibrarySwitchTests and
DWLookTests.

Read from the source, as every test of the app's look is: nothing here builds or runs the app (the builds and the
device checks 526-531 do)."""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_library_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
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


# ----------------------------------------------------------------------------- the phone's pieces, as dw.css draws them

def test_the_librarys_tiles_and_rows_are_dw_css():
    tiles = bare(source("Library/LibraryTiles.swift"))
    look = body(tiles, "enum LibraryLook {")
    # .tiles: gap 16px 14px, padding 12px 16px 0 - .tile > .t's margin-top 7, .row > div's padding 0 10px
    row_gap, column_gap = (px(part) for part in css(".tiles", "gap").split())
    assert constant(look, "tileRowGap") == row_gap == 16 and constant(look, "tileColumnGap") == column_gap == 14
    assert constant(look, "tilesTop") == px(css(".tiles", "padding-top")) == 12
    assert constant(look, "side") == px(css(".tiles", "padding-left")) == px(css(".meta", "padding-left")) == 16
    assert constant(look, "tileTitleAbove") == px(css(".tile > .t", "margin-top")) == 7
    assert constant(look, "rowTextSide") == px(css(".row > div", "padding-left")) == 10
    # what only iArtists.dc.html draws (its row's cover 44 wide, 16 in; the chevron 16 from the right)
    assert (constant(look, "rowCover"), constant(look, "rowSide"), constant(look, "rowTrail")) == (44, 16, 16)
    # the tall row: 60 at least (DWLook's), its rule .dw.ph .row's colour
    assert px(css(".row.tall", "height")) == 60
    assert re.search(r"tallRowHeight: 60,\s+// dw\.ph: \.row\.tall height", (CORE / "DWLook.swift").read_text(encoding="utf-8"))
    assert css(".row.tall", "border-bottom-color") == "#1c1b22"
    assert "static let rowRule = hex(0x1c1b22)" in source("Look/DWPalette.swift")
    list_row = body(tiles, "struct LibraryListRow")
    for drawn in (".lookHeight(DWLook.here.tallRowHeight)", "DWRule(colour: DWPalette.rowRule)",
                  ".frame(width: LibraryLook.rowCover, height: LibraryLook.rowCover)",
                  ".padding(.horizontal, LibraryLook.rowTextSide)"):
        assert drawn in list_row, drawn
    # the rows that are iArtists': artists, playlists (on the Library's page), songs
    assert "LibraryListRow(title: artist.name" in source("Library/ArtistsScreen.swift")
    assert "LibraryListRow(title: playlist.name" in source("Playlists/PlaylistsScreen.swift")
    songs = bare(source("Library/SongsScreen.swift"))
    assert ".lookHeight(DWLook.here.tallRowHeight)" in songs and "DWRule(colour: DWPalette.rowRule)" in songs
    # the tile: its title 15 semibold in the text's white, its artist the second colour at 13
    tile = body(tiles, "struct LibraryTile: View {")
    assert ".font(Typeface.subheadline.weight(.semibold))" in tile and "DWPalette.text" in tile
    assert css(".tile > .t", "font-weight") == "600" and px(css(".tile > .a", "font-size")) == 13
    assert ".padding(.top, LibraryLook.tileTitleAbove)" in tile


def test_the_phones_library_corners_stay_square():
    # James, 25 Nov: "keep the phone square as well" - the redrawn pieces' shapes are DWCorners' (0 on the phone)
    for name in ("Library/LibraryTiles.swift", "Library/LibraryTop.swift", "Library/AlbumsScreen.swift",
                 "Library/SongsScreen.swift", "Playlists/PlaylistsScreen.swift", "Library/LibraryLine.swift",
                 "Library/ArtistsScreen.swift"):
        code = bare(source(name))
        assert not re.search(r"cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b", code), name


def test_the_redrawn_files_hold_only_tokens():
    # no colour made, by number or by name, no radius and no font of their own in what R2 drew
    names = ["Library/LibraryTop.swift", "Library/LibraryTiles.swift", "Mac/Library/MacAlbumsPage.swift",
             "Mac/Library/MacArtistsPage.swift", "Mac/Components/MacColumnList.swift", "Mac/Library/MacLibrary.swift",
             "Library/LibraryLine.swift"]
    left = []
    for name in names:
        code = bare(source(name))
        for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b"), ("a colour by number", r"0x[0-9a-fA-F]{6}"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a system colour", r"\.foregroundStyle\(\.(primary|secondary|tertiary)\)"),
                              ("a font of its own", r"\.system\(|Font\.(system|custom)|\.monospaced\(\)")):
            if re.search(pattern, code):
                left.append(f"{name}: {what}")
    # and the parts of the Library's own pages R2 redrew: the top's field, the meta lines, the rows
    view = bare(source("Library/LibraryView.swift"))
    field = body(view, "private func findField(")
    for name, part in (("LibraryView findField", field),
                       ("AlbumsScreen meta", body(bare(source("Library/AlbumsScreen.swift")), "private func meta(")),
                       ("ArtistsScreen meta", body(bare(source("Library/ArtistsScreen.swift")), "private func meta(")),
                       ("ArtistRow", body(bare(source("Library/ArtistsScreen.swift")), "struct ArtistRow: View {")),
                       ("PlaylistsScreen meta", body(bare(source("Playlists/PlaylistsScreen.swift")),
                                                     "private func meta("))):
        if re.search(r"\bColor\s*\(|0x[0-9a-fA-F]{6}|cornerRadius|RoundedRectangle\(|\.foregroundStyle\(\.(primary|"
                     r"secondary|tertiary)\)|Palette\.quiet", part):
            left.append(name)
    assert not left, left
    assert "DWWell(focused: findFocused)" in field and "DWPalette.acc" in field


# ----------------------------------------------------------------------------- the top: one row, and Find

def test_the_librarys_top_is_one_row_with_find_kept():
    # R2b (James, 25 Nov: "can we streamline it a bit?"): no title and no strip - one row, iLibrary's .ltop: Find's
    # circle, the switch of the pages, the •••'s circle, in that order (VoiceOver's too)
    top = bare(source("Library/LibraryTop.swift"))
    drawn = body(top, "var body: some View {")
    row = body(drawn, "LibraryTopRow {")
    order = [row.index(part) for part in ("Button(action: openFind)", "switcher\n", "more\n",
                                          "DWSegmentedNeed(words: pages)")]
    assert order == sorted(order)
    assert "PhoneTop(" not in top and "AppTab.library.title" not in top and "sides" not in drawn
    raw = source("Library/LibraryTop.swift")
    assert raw.count('Image(systemName: "magnifyingglass")') == 1
    find = flat(row[row.index("Button(action: openFind)"):row.index("switcher\n")])
    assert ".buttonStyle(PhoneCircleStyle())" in find and ".accessibilityLabel(findLabel)" in find
    assert ".accessibilityShowsLargeContentViewer {" in find
    # capped at xxxLarge, as the bars are - the row, not Find's field under it
    assert flat(drawn).count(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)") == 1
    assert re.search(r"LibraryTopRow \{.*\}\s*\.dynamicTypeSize\(\.\.\.DynamicTypeSize\.xxxLarge\)\s*if finding",
                     drawn, re.S)
    # Find's field under the row while it is open
    assert re.search(r"if finding \{\s*find\s*\.padding", drawn)
    view = bare(source("Library/LibraryView.swift"))
    assert re.search(r"LibraryTop\(finding: finding, findLabel: findPrompt\(shownPage\), openFind: \{ openFind\(\) \},"
                     r"\s*pages: order\.map \{ \(each: LibraryPage\) -> String in each\.title \}\) \{"
                     r"\s*findField\(shownPage\)\s*\} switcher: \{\s*switcher\(order\)\s*\} more: \{", view)
    # the magnifying glass opens Find where it is closed, and focuses its field (again, where it is open)
    opening = flat(body(view, "private func openFind()"))
    assert opening == ("private func openFind() { if !finding { if reduceMotion { finding = true } else { "
                       "withAnimation(.snappy) { finding = true } } } findFocused = true }"), opening
    closing = body(view, "private func closeFind()")
    assert "clearFind()" in closing and "finding = false" in closing
    # the ••• is the other circle, holding only what each page's line doesn't
    more = body(view, "private func more(")
    assert "LibraryMenu.topSections(" in more and "LibraryMenu.sections(" not in view
    assert ".menuStyle(.button) .buttonStyle(PhoneCircleStyle())" in flat(more)
    assert "DWButtonStyle" not in more and "CircleFace" not in view + top


def test_the_rows_circles_are_the_looks_raised_face_drawn_round():
    # .circ's colours are .btn's - the look's raised face, no new one - without .btn's drop, round, 34 in a 44 target
    for prop in ("border", "background", "color"):
        assert css(".circ", prop) == css(".btn", prop), prop
    assert css(".circ", "box-shadow") == "inset 0 1px 0 rgba(255, 255, 255, 0.08)", "the sheen alone: no drop"
    assert css(".btn", "box-shadow").startswith("inset 0 1px 0 rgba(255, 255, 255, 0.08), ")
    face = flat(body(bare(source("Phone/PhoneTop.swift")), "private struct PhoneCircleFace<"))
    assert ("DWRaised(shape: Circle(), face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen, "
            "edge: DWPalette.buttonEdge, drop: nil, pressed: pressed && enabled)") in face
    assert ".foregroundStyle(DWPalette.buttonText)" in face and ".opacity(enabled ? 1 : DWPalette.off)" in face
    assert "let face = CGFloat(PhoneLook.circle) let target = max(face, CGFloat(DWLook.here.target))" in face
    order = [face.index(part) for part in (".frame(width: face, height: face)", ".background {",
                                           ".frame(width: target, height: target)", ".contentShape(Rectangle())")]
    assert order == sorted(order)
    # the glyph grows with the text (to the row's cap), the face is a mark drawn at its size
    assert ".font(Typeface.symbol(.body).weight(.semibold))" in face


def test_the_row_is_laid_out_where_core_puts_each_view():
    # (R2b's review) LibraryTopRow measures its four views and places each where Core puts it (LibraryTopFit.row and
    # .place - LibrarySwitchTests holds the frames: Find leading, the ••• trailing, the switch between them or folded
    # under them); its need is the fourth view, measured at its own size, and the switch is measured in the room offered
    top = bare(source("Library/LibraryTop.swift"))
    layout = top[top.index("private struct LibraryTopRow: Layout {"):top.index("private struct TopProbe:")]
    assert flat(body(layout, "func sizeThatFits(")) == (
        "func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { guard let row = "
        "placed(proposal.width, subviews) else { return .zero } return CGSize(width: row.width, height: row.height) }")
    assert flat(body(layout, "func placeSubviews(")) == (
        "func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) { guard "
        "let row = placed(bounds.width, subviews) else { return } subviews[0].lookPlace(row.find, in: bounds) "
        "subviews[1].lookPlace(row.switcher, in: bounds) subviews[2].lookPlace(row.more, in: bounds) "
        "subviews[3].lookPlace(row.need, in: bounds) }")
    assert flat(body(layout, "private func placed(")) == (
        "private func placed(_ width: CGFloat?, _ subviews: Subviews) -> LibraryTopFit.Placed? { guard subviews.count == "
        "4 else { assertionFailure(\" \\(subviews.count) \") return nil } let need = LookSize(subviews[3].sizeThatFits("
        ".unspecified)) let row = LibraryTopFit.row(needs: need.width, width: width.map { (given: CGFloat) -> Double in "
        "Double(given) }) let switcher = LookSize(subviews[1].sizeThatFits(ProposedViewSize(width: CGFloat(row.room), "
        "height: nil))) return LibraryTopFit.place(row, find: LookSize(subviews[0].sizeThatFits(.unspecified)), "
        "switcher: switcher, more: LookSize(subviews[2].sizeThatFits(.unspecified)), need: need) }")
    # a view placed where Core put it, given the box's size
    raised = flat(body(bare(source("Look/DWRaised.swift")), "func lookPlace(_ box: LookBox, in bounds: CGRect)"))
    assert raised == ("func lookPlace(_ box: LookBox, in bounds: CGRect) { place(at: CGPoint(x: bounds.minX + CGFloat(box.x), "
                      "y: bounds.minY + CGFloat(box.y)), anchor: .topLeading, proposal: ProposedViewSize(width: "
                      "CGFloat(box.width), height: CGFloat(box.height))) }")
    switch = flat(bare((CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")))
    assert ("public static func row(needs: Double, width: Double?) -> Row { let wide = width ?? needs + 2 * "
            "(PhoneLook.rowSide + PhoneLook.circle + PhoneLook.rowGap) let folds = folds(needs: needs, width: wide) return "
            "Row(width: wide, folds: folds, room: folds ? foldedRoom(width: wide) : room(width: wide)) }") in switch


def test_voiceover_reads_the_row_as_it_is_drawn():
    # (R2b's review) folded, Find and the ••• on the row are read before the switch under them (Core's reading order,
    # LibrarySwitchTests); the row is one container, its fold read back from what was last laid out
    top = bare(source("Library/LibraryTop.swift"))
    row = flat(body(top, "LibraryTopRow {"))
    for part, after in ((".find", "Label(findLabel, systemImage: \" \") }"), (".switcher", "switcher"), (".more", "more")):
        assert f"{after} .accessibilitySortPriority(LibraryTopFit.priority({part}, folds: folds))" in row, part
    assert row.count(".accessibilitySortPriority(") == 3
    drawn = flat(body(top, "var body: some View {"))
    assert re.search(r"needs = width \} \} \.accessibilityElement\(children: \.contain\) \.onGeometryChange\(for: "
                     r"CGFloat\.self\) \{ \(row: GeometryProxy\) -> CGFloat in row\.size\.width \} action: \{ "
                     r"\(width: CGFloat\) -> Void in wide = width \} \.dynamicTypeSize", drawn)
    assert ("DWSegmentedNeed(words: pages) .onGeometryChange(for: CGFloat.self) { (need: GeometryProxy) -> CGFloat in "
            "need.size.width } action: { (width: CGFloat) -> Void in needs = width }") in row
    assert flat(body(top, "private var folds: Bool {")) == (
        "private var folds: Bool { wide > 0 && LibraryTopFit.folds(needs: Double(needs), width: Double(wide)) }")
    switch = flat(bare((CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")))
    assert ("public static func reading(folds: Bool) -> [Part] { folds ? [.find, .more, .switcher] : "
            "[.find, .switcher, .more] }") in switch


def test_the_top_still_clears_the_dynamic_island():
    # TopClearance read as before (test_ios_palette.py holds the probe): the row comes down by the room, read in take()
    top = bare(source("Library/LibraryTop.swift"))
    drawn = body(top, "var body: some View {")
    assert ".padding(.top, clearance)" in drawn
    assert re.search(r"TopProbe\(eyes: eyes\) \{ \(sample: TopProbe\.Sample\) -> Void in\s*take\(sample\)\s*\}", drawn)
    take = body(top, "private func take(")
    assert "TopClearance.room(kept: Double(clearance)" in take and "clearance = CGFloat(room)" in take


def test_the_switch_moves_the_pager_and_downloaded_is_in_the_more():
    view = bare(source("Library/LibraryView.swift"))
    switcher = flat(body(view, "private func switcher("))
    assert ("DWSegmented(options: order, words: { (each: LibraryPage) -> String in each.title }, chosen: Binding(get: "
            "{ shownPage }, set: { (each: LibraryPage) -> Void in chose(each) }), spoken: LibrarySwitchWords.switchLabel, "
            "large: true)") in switcher
    chose = flat(body(view, "private func chose("))
    assert chose == "private func chose(_ chosen: LibraryPage) { withAnimation(reduceMotion ? nil : .snappy) { show(chosen) } }"
    show = flat(body(view, "private func show("))
    assert "page = chosen scrolled = chosen" in show
    # the pager's own swipe: its scroll position, the page following once at rest
    pager = body(view, "private func pager(albums: AlbumList)")
    assert ".scrollPosition(id: $scrolled, anchor: .center)" in pager and ".scrollTargetBehavior(.paging)" in pager
    assert ".pagerPhase(moving: $paging, settled: settled)" in pager
    # the banner straight under the top: no strip of the pages, no chips, nothing pushed from it
    order = [pager.index(part) for part in ("LibraryTop(", "OfflineBanner()")]
    assert order == sorted(order)
    assert "PhoneStrip" not in view and "LibraryStrip" not in view and "func strip(" not in view
    # Downloaded is the •••'s again, pushed on the tab's path as the old •••'s and R2's strip's were - and, while the
    # Albums page is Downloaded, the way back to the albums in its place (Core's topSections)
    item = flat(body(view, "private func menuItem("))
    assert ("case .downloaded: Button { navigation.open(.downloaded) } label: { Label(words, systemImage: "
            "DownloadWords.downloadSymbol) }") in item
    assert "case .albums(let scope): Button { navigation.open(.albums(scope)) }" in item
    switch = flat(bare((CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")))
    assert "sections.append([albumsPage == .downloaded ? .albums(scope) : .downloaded])" in switch
    more = flat(body(view, "private func more("))
    assert "albumsPage: albums == .downloaded ? .downloaded : .albums" in more
    # and each page still pulls to shuffle
    for name in ("Library/AlbumsScreen.swift", "Library/ArtistsScreen.swift", "Library/SongsScreen.swift"):
        assert ".pullsToShuffle(" in bare(source(name)), name


def test_songs_is_never_beside_your_own_albums():
    view = bare(source("Library/LibraryView.swift"))
    assert re.search(r"private var shownOrder: \[LibraryPage\] \{\s*LibraryPages\.shown\(order, personal: "
                     r"server\.access\.hasLibrary, side: side\)\s*\}", view)
    switch = (CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")
    shown = body(switch, "public static func shown(_ order: [LibraryPage], personal: Bool, side: LibrarySide)")
    assert "guard personal, side == .all else { return shown(order, personal: personal) }" in shown
    # Yours | All only where All music was: a library of your own, your scope, deadwax in reach - never on the Mac
    assert re.search(r"!Platform\.mac && LibraryPages\.sides\(personal: server\.access\.hasLibrary, scope: library\.scope,"
                     r"\s*online: reachability\.online, chosen: chosenSide\)", view)
    sides = body(switch, "public static func sides(")
    assert "personal && scope == .yours && (online || chosen == .all)" in sides


def test_each_pages_line_holds_its_own_then_grid_list_and_yours_all():
    # R2b: one quiet line per page - its count, its order (or New playlist…), and at its end LibraryLineEnd's
    albums = bare(source("Library/AlbumsScreen.swift"))
    meta = flat(body(albums, "private func meta("))
    assert "PhoneMetaLink(words: library.sort.label)" in meta and "Picker(LibraryWords.sortLabel, selection: $library.sort)" in meta
    assert "return PhoneMeta(count: count) { Menu {" in meta
    assert meta.endswith("} trailing: { LibraryLineEnd(page: .albums, sides: page?.sides) } }"), meta
    assert "layoutToggle" not in albums and "DWToggleStyle" not in albums, "Grid and List are bare glyphs now"
    artists = bare(source("Library/ArtistsScreen.swift"))
    meta = flat(body(artists, "private func meta("))
    assert "PhoneMetaLink(words: artists.order.label)" in meta and "return PhoneMeta(count: count) { Menu {" in meta
    # the order's menu chooses the order (R2b's review: bound to `.constant(artists.order)` it passed everything)
    assert "Picker(ArtistWords.sortLabel, selection: $artists.order) {" in meta
    assert meta.endswith("} trailing: { LibraryLineEnd(page: .artists, sides: page?.sides) } }"), meta
    playlists = bare(source("Playlists/PlaylistsScreen.swift"))
    meta = flat(body(playlists, "private func meta("))
    words, end = meta.split("} trailing: {")
    assert "return PhoneMeta(count: count) { Button {" in words, "the count, then New playlist…"
    # New playlist… opens its sheet - its tap does nothing else, and nothing stands in its way but deadwax out of reach
    tap = re.search(r"Button \{ (.*?) \} label: \{ Text\(PlaylistWords\.newPlaylistRow\)", words)
    assert tap and tap.group(1) == "newSheet = NewSheet()", words
    assert end.strip() == "LibraryLineEnd(page: .playlists, sides: sides) } }", end
    assert ".disabled(!online) .opacity(online ? 1 : DWPalette.off)" in words, "offered only while deadwax answers"
    songs = flat(bare(source("Library/SongsScreen.swift")))
    assert ("if let page { PhoneMeta(count: songs.paging.countText, trailing: { LibraryLineEnd(page: .songs, "
            "sides: page.sides) }) }") in songs
    # every page is handed Yours | All where it shows, and LibraryView's own choose behind it
    view = bare(source("Library/LibraryView.swift"))
    page = flat(body(view, "private func pageView("))
    # (R2b's review: `sideChoice ?? LibrarySideChoice(...)` passed) the choice as LibraryView makes it, nil where Yours |
    # All doesn't show - nothing in its place
    assert re.findall(r"^ *let sides = .*$", source("Library/LibraryView.swift"), re.M) == ["        let sides = sideChoice"]
    assert page.count("sides: sides") == 4, page
    assert re.search(r"private var sideChoice: LibrarySideChoice\? \{\s*sides \? LibrarySideChoice\(side: side, choose: "
                     r"\{ \(chosen: LibrarySide\) -> Void in choose\(chosen\) \}\) : nil\s*\}", view)
    choose = flat(body(view, "private func choose("))
    assert ("guard chosen != chosenSide else { return } chosenSide = chosen if chosen == .all, reachability.online { "
            "shuffles.shown(.allSongs, library.scope) }") in choose
    assert "sidesControl" not in view


def test_grid_and_list_are_on_albums_alone_and_yours_all_only_where_it_was():
    end = flat(bare(source("Library/LibraryLine.swift")))
    line = end[end.index("var body: some View {"):end.index("private func glyph(")]
    # Grid and List: on the page whose line has a layout - Albums alone (Core's LibraryLine.layouts)
    layouts = line[line.index("if LibraryLine.layouts(on: page) {"):line.index("if let sides {")]
    assert "glyph(.grid, symbol:" in layouts and "glyph(.list, symbol:" in layouts
    raw = source("Library/LibraryLine.swift")
    assert 'glyph(.grid, symbol: "square.grid.2x2", words: LibrarySwitchWords.grid)' in raw
    assert 'glyph(.list, symbol: "list.bullet", words: LibrarySwitchWords.list)' in raw
    switch = flat(bare((CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")))
    assert "public static func layouts(on page: LibraryPage) -> Bool { page == .albums }" in switch
    # Yours | All: only with a choice handed in - LibraryView hands one only where R2's switch showed (LibraryPages.sides)
    sides = line[line.index("if let sides {"):]
    assert "word(.yours, sides, after: CGFloat(PhoneLook.sidesGap))" in sides
    assert "DWRule(colour: DWPalette.metaRule, vertical: true) .frame(height: rule)" in sides
    assert "word(.all, sides, before: CGFloat(PhoneLook.sidesGap))" in sides
    assert ".accessibilityElement(children: .contain) .accessibilityLabel(LibrarySwitchWords.sidesLabel)" in sides
    assert "glyph(" not in sides and "word(" not in layouts
    # .meta .views' margin before Yours | All, only where Yours | All follows
    assert ".padding(.trailing, sides == nil ? 0 : CGFloat(PhoneLook.metaGlyphsAfter))" in layouts
    # the glyphs set the layout, kept per device; a word chooses its own side through the page's choice - the side shown
    # too, never the other (R2b's review), which LibraryView's choose lets be
    tap = r"return Button \{ (.*?) \} label:"
    glyph = flat(body(bare(source("Library/LibraryLine.swift")), "private func glyph("))
    assert re.search(tap, glyph).group(1) == "library.layout = layout"
    word = flat(body(bare(source("Library/LibraryLine.swift")), "private func word("))
    assert re.search(tap, word).group(1) == "sides.choose(each)"
    # the side shown stays a button - enabled, VoiceOver hearing it selected - and nothing at the line's end is disabled
    # or untouchable
    assert ".disabled(" not in end and ".allowsHitTesting(" not in end
    # and the hairline grows with the line's words
    assert "@ScaledMetric(relativeTo: .footnote) private var rule = CGFloat(PhoneLook.sidesRule)" in end


def test_white_is_where_you_are_and_purple_what_a_tap_goes_to():
    # dw.css (R2b's block): .v the accent, .v.on white; .scope > b white and semibold, the other word a .link, the accent
    accent = css(".meta .link", "color")
    assert accent == "#c084fc" and css(".meta .v", "color") == accent
    assert css(".meta .v.on", "color") == "#fff"
    assert css(".meta .scope > b", "color") == "#fff" and css(".meta .scope > b", "font-weight") == "600"
    palette = source("Look/DWPalette.swift")
    assert "static let text = hex(0xffffff)" in palette and "static let acc = hex(0xc084fc)" in palette
    assert re.search(r"--acc: #c084fc;", (IOS / "design" / "dw.css").read_text(encoding="utf-8"))
    code = bare(source("Library/LibraryLine.swift"))
    glyph = flat(body(code, "private func glyph("))
    assert "let on = library.layout == layout" in glyph
    assert ".foregroundStyle(on ? DWPalette.text : DWPalette.acc)" in glyph
    assert ".accessibilityAddTraits(on ? .isSelected : [])" in glyph
    word = flat(body(code, "private func word("))
    assert "let on = each == sides.side" in word
    assert ".font(Typeface.Phone.text(.meta).weight(on ? .semibold : .regular))" in word
    assert ".foregroundStyle(on ? DWPalette.text : DWPalette.acc)" in word
    assert ".accessibilityAddTraits(on ? .isSelected : [])" in word
    # the one rule, and no other colour in the line's end; the count keeps the line's third colour (PhoneMeta's)
    assert set(re.findall(r"DWPalette\.(\w+)", code)) == {"text", "acc", "metaRule"}
    assert ".foregroundStyle(DWPalette.t3)" in bare(source("Phone/PhoneMeta.swift"))
    # nothing boxed: no face, edge or fill behind a glyph or a word
    assert not re.search(r"DWRaised|DWToggleStyle|DWButtonStyle|\.background|strokeBorder|selbg", code)


# ----------------------------------------------------------------------------- the row and the line fit, by arithmetic

FONTS = APP / "Fonts"
#? Dynamic Type's footnote and body at each size (Apple's table): the row and the line are capped at xxxLarge, so every
#? accessibility size draws them as xxxLarge does
FOOTNOTE = {"xSmall": 12, "small": 12, "medium": 12, "large": 13, "xLarge": 15, "xxLarge": 17, "xxxLarge": 19}
BODY = {"xSmall": 14, "small": 15, "medium": 16, "large": 17, "xLarge": 19, "xxLarge": 21, "xxxLarge": 23}
#? an SF Symbol's width at its size, taken wide (square.grid.2x2 and list.bullet are about 1.1-1.2 of it)
SYMBOL = 1.3
#? the caret after an order's words (DWCaret, DWPopUp.swift's 8 x 4)
CARET = 8
#? the narrowest phone the app draws on: an iPhone SE's and a 13 mini's 375
NARROW = 375


def advances(name: str) -> tuple[float, dict[int, int], list[int]]:
    """A TrueType face's units per em, its character map (format 4, Windows Unicode BMP) and its glyphs' advances."""
    data = (FONTS / name).read_bytes()
    u16 = lambda at: int.from_bytes(data[at:at + 2], "big")  # noqa: E731
    tables = {data[12 + 16 * i:16 + 16 * i].decode(): int.from_bytes(data[20 + 16 * i:24 + 16 * i], "big")
              for i in range(u16(4))}
    units = u16(tables["head"] + 18)
    widths = [u16(tables["hmtx"] + 4 * i) for i in range(u16(tables["hhea"] + 34))]
    cmap, chars = tables["cmap"], {}
    for i in range(u16(cmap + 2)):
        record = cmap + 4 + 8 * i
        if (u16(record), u16(record + 2)) != (3, 1):
            continue
        sub = cmap + int.from_bytes(data[record + 4:record + 8], "big")
        count = u16(sub + 6) // 2
        ends, starts = sub + 14, sub + 16 + 2 * count
        deltas, offsets = starts + 2 * count, starts + 4 * count
        for k in range(count):
            for char in range(u16(starts + 2 * k), u16(ends + 2 * k) + 1):
                if char == 0xFFFF:
                    continue
                if u16(offsets + 2 * k) == 0:
                    glyph = (char + u16(deltas + 2 * k)) & 0xFFFF
                else:
                    glyph = u16(offsets + 2 * k + u16(offsets + 2 * k) + 2 * (char - u16(starts + 2 * k)))
                    glyph = (glyph + u16(deltas + 2 * k)) & 0xFFFF if glyph else 0
                chars[char] = glyph
    return units, chars, widths


FACES = {weight: advances(f"NotoSans-{weight}.ttf") for weight in ("Regular", "SemiBold")}


def words_width(words: str, points: float, weight: str = "Regular") -> float:
    units, chars, widths = FACES[weight]
    return sum(widths[min(chars[ord(char)], len(widths) - 1)] for char in words) / units * points


def phone_number(name: str) -> float:
    found = re.search(rf"public static let {name}: Double = (-?[0-9.]+)", (CORE / "DWLook.swift").read_text(encoding="utf-8"))
    assert found, name
    return float(found.group(1))


def test_the_rows_switch_fits_beside_its_circles_or_folds_under_them():
    switch = flat(bare((CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")))
    assert "width - 2 * (PhoneLook.rowSide + PhoneLook.circle + PhoneLook.rowGap)" in switch
    assert "public static func foldedRoom(width: Double) -> Double { width - 2 * PhoneLook.rowSide }" in switch
    assert "public static func folds(needs: Double, width: Double) -> Bool { needs > room(width: width) }" in switch
    side, circle, gap = (phone_number(n) for n in ("rowSide", "circle", "rowGap"))
    room = NARROW - 2 * (side + circle + gap)
    folded = NARROW - 2 * side
    assert (room, folded) == (251, 343)
    # what the switch needs: the widest page's words in each equal segment (DWSegmented's 14 semibold, scaled with the
    # footnote; .seg.lg's padding 0 on the phone), and its well's edge either side - DWSegmentedNeed's very parts
    need = flat(body(bare(source("Look/DWSegmented.swift")), "struct DWSegmentedNeed: View {"))
    seg = flat(body(bare(source("Look/DWSegmented.swift")), "private func segment("))
    # (R2b's review) every segment as wide as the widest word - a ZStack of every word in each - and the whole of it
    # hidden, untouchable and unheard, at its own size
    assert need == ("struct DWSegmentedNeed: View { let words: [String] var body: some View { HStack(spacing: 0) { "
                    "ForEach(words.indices, id: \\.self) { (_: Int) in ZStack { ForEach(words.indices, id: \\.self) { "
                    "(at: Int) in Text(words[at]) .font(Typeface.Look.text(.largeSegment).weight(.semibold)) .lineLimit(1) "
                    ".padding(.horizontal, CGFloat(DWLook.here.largeSegmentPadding)) } } } } .padding(1) .fixedSize() "
                    ".hidden() .allowsHitTesting(false) .accessibilityHidden(true) } }"), need
    assert ".font(Typeface.Look.text(.largeSegment).weight(.semibold))" in need
    assert ".font(Typeface.Look.text(large ? .largeSegment : .segment).weight(.semibold))" in seg
    assert ".padding(.horizontal, CGFloat(DWLook.here.largeSegmentPadding))" in need and ".padding(1)" in need
    assert re.search(r"largeSegmentPadding: 0,\s+// dw\.ph: \.seg\.lg button padding-left",
                     (CORE / "DWLook.swift").read_text(encoding="utf-8"))
    titles = {"albums": "Albums", "playlists": "Playlists", "artists": "Artists", "songs": "Songs"}
    orders = {"yours": ["albums", "playlists", "artists"], "all": ["albums", "artists", "songs"],
              "no library of your own": ["albums", "playlists", "artists", "songs"]}
    found = {}
    for size, footnote in FOOTNOTE.items():
        points = 14 * footnote / 13
        for whose, pages in orders.items():
            needs = len(pages) * max(words_width(titles[p], points, "SemiBold") for p in pages) + 2
            folds = needs > room
            found[(whose, size)] = folds
            # folded, it fits the page's width less the circles' sides at every size
            assert needs <= (folded if folds else room), (whose, size, needs)
    # three pages never fold, up to the row's cap - the four of logins off and the break-glass sign-in fold from xLarge
    assert not [key for key, folds in found.items() if folds and key[0] != "no library of your own"]
    assert [size for (whose, size), folds in found.items() if folds and whose == "no library of your own"] == [
        "xLarge", "xxLarge", "xxxLarge"]
    # the cap the arithmetic takes is the row's (an accessibility size draws as xxxLarge)
    top = flat(bare(source("Library/LibraryTop.swift")))
    assert re.search(r"LibraryTopRow \{.*DWSegmentedNeed\(words: pages\).*\} \.dynamicTypeSize\(\.\.\.DynamicTypeSize\.xxxLarge\) "
                     r"if finding", top)


def test_each_pages_line_gives_way_inside_itself_before_it_folds():
    # (R2b's review) the line tries its ways in Core's order (MetaLine.Fit: one line; one line, the count's noun dropped;
    # its end folded under its words; folded, the noun dropped) and PhoneMeta's ViewThatFits draws the first that fits,
    # each way laid out and measured as it is drawn - so a face of its own moves where it gives way, never whether it cuts
    look = (CORE / "DWLook.swift").read_text(encoding="utf-8")
    fits = re.findall(r"^\s*case (\w+)$", body(bare(look), "public enum Fit: CaseIterable, Sendable, Equatable {"), re.M)
    assert fits == ["full", "short", "folded", "foldedShort"]
    meta = flat(bare(source("Phone/PhoneMeta.swift")))
    assert "ViewThatFits(in: .horizontal) { " + " ".join(f"line(.{fit})" for fit in fits) + " }" in meta
    core = flat(bare(look))
    assert ("public static func fit(full: Double, short: Double, end: Double, room: Double) -> Fit { Fit.allCases.first { "
            "(each: Fit) -> Bool in width(words: each.short ? short : full, end: end, folded: each.folded) <= room } ?? "
            ".foldedShort }") in core
    assert ("public static func width(words: Double, end: Double, folded: Bool) -> Double { if folded { return max(words, "
            "end) } return end > 0 ? words + 2 * PhoneLook.metaGap + end : words }") in core
    assert ("public static func short(_ count: String) -> String { guard let space = count.lastIndex(of: \" \") else { "
            "return count } return String(count[..<space]) }") in core
    # each way's count in full or its noun dropped - VoiceOver hearing it in full whichever is drawn - then the dot,
    # where words follow it
    line = flat(body(bare(source("Phone/PhoneMeta.swift")), "private func line("))
    assert ("PhoneMetaLine(folded: fit.folded) { HStack(spacing: CGFloat(PhoneLook.metaGap)) { if !count.isEmpty { "
            "Text(MetaLine.count(count, fit)) .accessibilityLabel(count) if follows { Text(verbatim: \" \") "
            ".accessibilityHidden(true) } } words } HStack(spacing: CGFloat(PhoneLook.metaGap)) { end } }") in line
    # one way laid out where Core puts its two ends (MetaLine.place - DWLookTests holds the frames), its width asked the
    # way's own (MetaLine.width) - what the ViewThatFits measures
    layout = meta[meta.index("private struct PhoneMetaLine: Layout {"):]
    assert ("func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { guard let line = "
            "placed(proposal.width, subviews) else { return .zero } return CGSize(width: line.width, height: line.height) "
            "}") in layout
    assert ("func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) { guard "
            "let line = placed(bounds.width, subviews) else { return } subviews[0].lookPlace(line.words, in: bounds) "
            "subviews[1].lookPlace(line.end, in: bounds) }") in layout
    assert ("private func placed(_ width: CGFloat?, _ subviews: Subviews) -> MetaLine.Placed? { guard subviews.count == 2 "
            "else { assertionFailure(\" \\(subviews.count) \") return nil } let ideal = LookSize(subviews[0].sizeThatFits("
            ".unspecified)) let end = LookSize(subviews[1].sizeThatFits(.unspecified)) let room = width.map { (given: "
            "CGFloat) -> Double in Double(given) } ?? MetaLine.width(words: ideal.width, end: end.width, folded: folded) let "
            "given = MetaLine.wordsRoom(room, end: end.width, folded: folded) let words = LookSize(subviews[0].sizeThatFits("
            "ProposedViewSize(width: CGFloat(given), height: nil))) return MetaLine.place(words: words, end: end, room: "
            "room, folded: folded) }") in layout
    # the line is capped where the arithmetic stops (PhoneMeta's xxxLarge)
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in meta


#? the phones the arithmetic is done on: an SE's and a 13 mini's 375, a 16's 393, James's 17 Pro's 402
PHONES = (375, 393, 402)


def test_each_pages_line_fits_or_gives_way_without_cutting_a_word():
    lead, trail, gap, link = (phone_number(n) for n in ("metaLead", "metaTrail", "metaGap", "linkGap"))
    glyph, glyph_gap, after = (phone_number(n) for n in ("metaGlyph", "metaGlyphGap", "metaGlyphsAfter"))
    sides_gap = phone_number("sidesGap")
    assert NARROW - lead - trail == 343

    def fit(full: float, short: float, end: float, room: float) -> str:
        """MetaLine.fit, as Core says it (the test above holds it): the first of its ways whose width fits."""
        for way, cut, folded in (("F", False, False), ("S", True, False), ("f", False, True), ("s", True, True)):
            words = short if cut else full
            width = max(words, end) if folded else (words + 2 * gap + end if end > 0 else words)
            if width <= room:
                return way
        return "s"

    def ends(points: float, size: str) -> dict:
        """Each line's end at a size: Grid and List (bare glyphs, each its square or the symbol's width, the wider), the
        room before Yours | All, and Yours | All with its hairline - the side shown semibold, whichever is wider."""
        glyphs = 2 * max(glyph, SYMBOL * BODY[size]) + glyph_gap
        sides = max(words_width("Yours", points, "SemiBold") + words_width("All", points),
                    words_width("Yours", points) + words_width("All", points, "SemiBold")) + 2 * sides_gap + 1
        return {"albums": glyphs + after + gap + sides, "artists": sides, "playlists": sides, "songs": sides}

    def words(points: float, count: str, then: str, linked: bool = True) -> tuple:
        """The line's words, its count in full and its noun dropped (MetaLine.short): the count, the dot, and what
        follows it - an order with its caret, or New playlist…"""
        rest = (gap + words_width("·", points) + gap + words_width(then, points) + (link + CARET if linked else 0)
                if then else 0)
        return words_width(count, points) + rest, words_width(count.rsplit(" ", 1)[0], points) + rest

    # each page's orders, read from Core: the longest is Albums' "Year, newest first"
    shelves = (CORE / "Shelves.swift").read_text(encoding="utf-8")
    album_orders = re.findall(r'case \.\w+: return "([^"]+)"', shelves[shelves.index("enum AlbumSort"):][:1200])
    artists = (CORE / "Artists.swift").read_text(encoding="utf-8")
    artist_orders = re.findall(r'case \.\w+: return "([^"]+)"', artists[artists.index("enum ArtistOrder"):][:900])
    assert max(album_orders, key=lambda o: words_width(o, 13)) == "Year, newest first"
    assert "public static let `default`: AlbumSort = .alphabeticalByArtist" in shelves and album_orders[0] == "Artist"
    assert "Most albums" in artist_orders

    # Albums' line with Yours | All - its fullest - at the standard size and at xLarge, on each phone (F one line, S one
    # line with the count's noun dropped, f folded, s folded with it dropped): a three- and a four-figure library, and
    # Find's "N of M" in each, under the default order ("Artist"), "Recently added" and the longest. Counts are Core's
    # own (no thousands separator). In Noto Sans, the face drawn today: another face moves these, and this table with it
    expected = {
        "large": {"140 albums": ("FFF", "SFF", "SSF"),
                  "2318 albums": ("FFF", "SFF", "SSS"),
                  "12 of 140 albums": ("FFF", "SSS", "fSS"),
                  "12 of 2318 albums": ("FFF", "fSS", "fSS"),
                  "1234 of 2318 albums": ("SFF", "fSS", "fff")},
        "xLarge": {"140 albums": ("FFF", "SSS", "SSS"),
                   "2318 albums": ("FFF", "SSS", "fSS"),
                   "12 of 140 albums": ("SFF", "ffS", "fff"),
                   "12 of 2318 albums": ("SSF", "fff", "fff"),
                   "1234 of 2318 albums": ("SSS", "fff", "fff")},
    }
    for size, counts in expected.items():
        points = FOOTNOTE[size]
        end = ends(points, size)["albums"]
        for count, wants in counts.items():
            for order, want in zip(("Artist", "Recently added", "Year, newest first"), wants):
                full, short = words(points, count, order)
                got = "".join(fit(full, short, end, phone - lead - trail) for phone in PHONES)
                assert got == want, (size, count, order, got)
    # so, at the standard size: a library's count never folds the line on any of them, under any order - the review's
    # "140 albums · Recently added" (351 of 343 on 375) now "140 · Recently added"; on 393 and 402 Find's first keystroke
    # never folds it either but for a four-figure find under the longest order; on 375, with "Recently added", only in a
    # four-figure library (notes/ios.md "The redesign, slice R2b": what is left)
    points = FOOTNOTE["large"]
    for count in ("140 albums", "2318 albums"):
        for order in album_orders:
            full, short = words(points, count, order)
            assert all(fit(full, short, ends(points, "large")["albums"], phone - lead - trail) in "FS" for phone in PHONES)

    # every page at every size up to the line's cap: folded, its end fits a line of its own; no one word - a count's,
    # an order's with its caret, New playlist… - is wider than the line, so a wrap never cuts a word; and Artists',
    # Playlists' and Songs' lines never fold at the standard size or at xLarge
    line = NARROW - lead - trail
    for size, footnote in FOOTNOTE.items():
        points = footnote
        for page, end in ends(points, size).items():
            assert end <= line, (page, size, end)
        longest = max(words_width(w, points) for w in "1234 of 12345 albums Year, newest first".split())
        assert longest + link + CARET <= line and words_width("New playlist…", points) <= line
        if size not in ("large", "xLarge"):
            continue
        end = ends(points, size)
        for count in ("140", "2318", "12 of 140", "12 of 2318", "1234 of 2318"):
            for order in artist_orders:
                assert fit(*words(points, f"{count} artists", order), end["artists"], line) in "FS", (size, count, order)
            playlists = words(points, f"{count} playlists", "New playlist…", linked=False)
            assert fit(*playlists, end["playlists"], line) in "FS", (size, count)
        assert fit(*words(points, "12345 songs", ""), end["songs"], line) == "F", size


def test_the_layout_is_kept_on_each_device_and_bound_on_both():
    # Grid | List kept in this device's own defaults - the Mac's after quitting, the phone's its own (check 527)
    model = bare(source("Models/LibraryModel.swift"))
    assert re.search(r"var layout: LibraryLayout = LibraryLayout\(saved: UserDefaults\.standard\.string\(forKey: "
                     r"LibraryLayout\.storageKey\)\) \{\s*didSet \{ UserDefaults\.standard\.set\(layout\.rawValue, "
                     r"forKey: LibraryLayout\.storageKey\) \}", model)
    assert "NSUbiquitousKeyValueStore" not in "".join(path.read_text(encoding="utf-8") for path in APP.rglob("*.swift"))
    for name in ("Mac/Library/MacAlbumsPage.swift", "Mac/Library/MacArtistsPage.swift"):
        code = flat(bare(source(name)))
        assert "chosen: $library.layout, spoken: LibraryColumnWords.layout, large: true)" in code, name
        assert "if library.layout == .list {" in code, name


# ----------------------------------------------------------------------------- the plays: in the tap, songs in hand

def before_the_play(code: str, function: str) -> str:
    """A function's code up to its first call of the player's play."""
    inside = body(code, function)
    assert "player.play(" in inside, function
    return inside[:inside.index("player.play(")]


def test_every_play_is_in_the_tap_with_the_songs_in_hand():
    for name, functions in (("Mac/Library/MacAlbumsPage.swift", ("private func play()", "private func shuffle()")),
                            ("Mac/Library/MacArtistsPage.swift", ("private func play()", "private func shuffle()")),
                            ("Library/LibraryView.swift", ("private func shuffleNow()",))):
        code = bare(source(name))
        for function in functions:
            ahead = before_the_play(code, function)
            assert not re.search(r"\bawait\b|\bTask\b", ahead), f"{name} {function}"
    albums = bare(source("Mac/Library/MacAlbumsPage.swift"))
    # Play only once the songs are in hand: the selected album's answer, dimmed until it has songs
    assert "let songs = playable" in albums and ".disabled(songs.isEmpty)" in albums
    assert "guard library.layout == .list, let chosen, chosen.route.id == selected else { return [] }" in albums
    assert "player.play(songs: songs, album: album, at: nil)" in body(albums, "private func play()")
    artists = bare(source("Mac/Library/MacArtistsPage.swift"))
    assert ".disabled(!playable)" in artists and "return chosen.asks.playable" in artists
    assert "player.play(artist: chosen.asks.answers, shuffle: false)" in body(artists, "private func play()")
    for code in (albums, artists):
        assert "Button(action: play)" in code and "Button(ShuffleWords.shuffle, action: shuffle)" in code


# ----------------------------------------------------------------------------- the Mac's column lists

def test_the_macs_albums_and_artists_are_its_own_column_lists():
    library = bare(source("Mac/Library/MacLibrary.swift"))
    pages = body(library, "static func page(for page: Page) -> some View {")
    assert "case .albums(let scope): MacAlbumsPage(scope: scope)" in pages
    assert "case .artists(let scope): MacArtistsPage(scope: scope)" in pages
    assert "case .allSongs: SongsScreen()" in pages
    # the root's Albums and Artists too, in the pager's place - never on the iPhone, whose LibraryView has no desk
    view = bare(source("Library/LibraryView.swift"))
    # (R5) and Playlists, whatever the side
    assert re.sub(r"\s+", " ", "let desk = Platform.mac && (list != .downloaded && (shownPage == .albums || shownPage == .artists) "
                  "|| shownPage == .playlists) ? self.desk : nil") in re.sub(r"\s+", " ", view)
    assert re.search(r"extension LibraryView where Desk == EmptyView \{\s*init\(\) \{\s*desk = nil\s*\}", view)
    # the drawings' columns and widths
    albums = bare(source("Mac/Library/MacAlbumsPage.swift"))
    assert re.findall(r"MacListColumn\(title: LibraryColumnWords\.(\w+), width: \.(fixed\(\d+\)|flexible)\)", albums) == [
        ("album", "flexible"), ("artist", "fixed(150)"), ("year", "fixed(54)"), ("songs", "fixed(58)")]
    artists = bare(source("Mac/Library/MacArtistsPage.swift"))
    assert re.findall(r"MacListColumn\(title: LibraryColumnWords\.(\w+), width: \.(fixed\(\d+\)|flexible)\)", artists) == [
        ("artist", "flexible"), ("albums", "fixed(76)"), ("songs", "fixed(76)"), ("plays", "fixed(70)"),
        ("lastPlayed", "fixed(124)")]
    # the counts in the status bar, the selection Info's
    for code, subject in ((albums, ".album(AlbumRoute(album))"), (artists, ".artist(ArtistRoute(artist))")):
        assert ".macStatus(MacStatusItems.Items(leading: status(rows)))" in code
        assert subject in body(code, ".macSelects(")
        assert "ArtistTotals.oneSelected" in code
    # the list: Core's MacTable for its widths, stripes, keys, clicks and the selection kept; Platform's keys
    columns = bare(source("Mac/Components/MacColumnList.swift"))
    for rule in ("MacTable.widths(", "MacTable.stripes(", "MacTable.moved(", "MacTable.kept(", "MacTable.returned(",
                 "MacTable.clicked(row.id, count: 1)", "MacTable.clicked(row.id, count: 2)", ".listKeys {"):
        assert rule in columns, rule
    platform = source("Shared/Platform.swift")
    mac, phone = platform.split("\n#else\n", 1) if "\n#else\n" in platform else (platform, "")
    assert "onKeyPress(keys: [.upArrow, .downArrow, .home, .end, .return])" in mac
    assert re.search(r"func listKeys\(_ press: @escaping \(ListKey\) -> KeyPress\.Result\) -> some View \{\s*self\s*\}",
                     phone)
    # the list's colours: dw.css's, each commented with its rule
    palette = source("Mac/Look/MacPalette.swift")
    for line in ("static let columnsFace = vertical(hex(0x1a1822), hex(0x131219))",
                 "static let columnsRule = hex(0x262430)", "static let rowStripe = rgba(255, 255, 255, 0.018)",
                 "static let coverEdge = hex(0x34323c)"):
        assert line in palette, line


def test_the_artists_totals_are_cores_made_once_per_answer():
    artists = bare(source("Library/ArtistsScreen.swift"))
    assert ("ArtistTotals.rowLine(albums: artist.albumCount, songs: totals[artist.id]?.songs, place: place)"
            in flat(artists))
    mac = bare(source("Mac/Library/MacArtistsPage.swift"))
    for code in (artists, mac):
        task = body(code, ".task(id: ArtistTotalsKey(")
        assert re.search(r"totals = ArtistTotals\.of\(library\.albums\(\w+\)\?\.albums \?\? \[\]\)", task)
        assert code.count("ArtistTotals.of(") == 1, "made in the task alone, never in the body"
    assert "ArtistTotals.lastPlayedWords(total?.lastPlayed, now:" in mac
    assert "ArtistTotals.plays(total?.plays ?? 0)" in mac
    totals = (CORE / "ArtistTotals.swift").read_text(encoding="utf-8")
    of = body(totals, "public static func of(")
    assert "guard let artist = album.artistId, !artist.isEmpty else { continue }" in of and "totals[artist] = total" in of


# ----------------------------------------------------------------------------- R2's review

def test_a_chosen_all_stays_all_when_deadwax_drops_out():
    # finding 1: the switch is put away offline only on Yours - so the side, its pages and the page shown hold
    view = bare(source("Library/LibraryView.swift"))
    sides = flat(body(view, "private var sides: Bool"))
    assert "online: reachability.online, chosen: chosenSide)" in sides
    assert re.search(r"private var side: LibrarySide \{ LibraryPages\.side\(chosenSide, sides: sides\) \}", view)
    # the side changing (a tap of Yours | All, never deadwax dropping out) keeps the page where that side has it
    changed = view[view.index(".onChange(of: side) {"):]
    changed = changed[:changed.index(".onChange(of: server.signInOver")]
    assert "show(LibraryPages.showing(page, in: shownOrder))" in changed
    # deadwax coming back with Yours' Albums still Downloaded: All's Albums is the collection's all the same
    pager = flat(body(view, "private func pager(albums: AlbumList)"))
    assert "let list = side.albums(albums)" in pager
    assert "pageView(each, albums: list, can: can, current: each == shownPage)" in pager


def test_all_is_wired_to_the_collections_albums_artists_and_shuffle():
    # finding 4: each of All's ties, held on its own
    view = bare(source("Library/LibraryView.swift"))
    pager = flat(body(view, "private func pager(albums: AlbumList)"))
    assert "let list = side.albums(albums)" in pager, "All's Albums is the collection's"
    page = flat(body(view, "private func pageView("))
    assert "AlbumsScreen(list: albums," in page and ".id(albums)" in page
    artists = page[page.index("case .artists:"):page.index("case .songs:")]
    assert "scope: side.artistsScope, sides: sides))" in artists and ".id(side)" in artists, "All's Artists are the collection's"
    assert re.search(r"private var shuffleOf: ShuffleOf \{ side\.shuffle \}", view), "All's Shuffle is All songs'"
    assert "shuffles.take(shuffleOf," in body(view, "private func shuffleNow()")
    switch = (CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")
    assert "self == .all ? .scope(.store) : root" in body(switch, "public func albums(_ root: AlbumList)")
    assert "self == .all ? .store : nil" in body(switch, "public var artistsScope: AlbumScope?")
    assert "self == .all ? .allSongs : .library" in body(switch, "public var shuffle: ShuffleOf")


def test_the_macs_grid_selects_nothing():
    # finding 2: a selection is the list's alone - Grid lets it go, and Play has nothing in Grid
    for name, selection in (("Mac/Library/MacAlbumsPage.swift", "private func selectedAlbum("),
                            ("Mac/Library/MacArtistsPage.swift", "private func selectedArtist(")):
        code = bare(source(name))
        changed = flat(body(code, ".onChange(of: library.layout)"))
        assert re.fullmatch(r"\.onChange\(of: library\.layout\) \{ \(_: LibraryLayout, (\w+): LibraryLayout\) -> Void in "
                            r"if \1 != \.list \{ selected = nil \} \}", changed), name
        assert "guard library.layout == .list, let selected else { return nil }" in body(code, selection), name
        assert "library.layout == .list," in body(code, "private var playable:"), name
        tools = flat(body(code, "@ViewBuilder private var tools: some View"))
        assert "LibraryColumnWords.playHelp(list: library.layout == .list, selected: selected != nil," in tools, name
        # Shuffle works in Grid as in List
        shuffle = tools[tools.index("Button(ShuffleWords.shuffle, action: shuffle)"):tools.index("MacGroove()")]
        assert "layout" not in shuffle and ".disabled(!shuffleCan.starts)" in shuffle, name


def test_the_macs_rows_keep_their_right_click():
    # finding 3: MacColumnList takes each row's right-click; Albums' is the album page's •••, as the tiles' is
    columns = bare(source("Mac/Components/MacColumnList.swift"))
    assert "struct MacColumnList<Row: Identifiable, Cell: View, Menu: ViewModifier>: View where Row.ID == String" in columns
    assert "let menu: (Row) -> Menu" in columns
    assert re.search(r"line\(row, striped: at < stripes\.count && stripes\[at\], widths: widths\)\s*"
                     r"\.modifier\(menu\(row\)\)", columns)
    albums = flat(bare(source("Mac/Library/MacAlbumsPage.swift")))
    assert "menu: { (album: IndexAlbum) -> AlbumRightClick in AlbumRightClick(route: AlbumRoute(album)) }" in albums
    # and the tiles' still carry theirs (LibraryTile's own .albumRightClick)
    assert ".albumRightClick(" in bare(source("Library/LibraryTiles.swift"))
    right = bare(source("Shared/MacRightClick.swift"))
    assert "struct AlbumRightClick: ViewModifier" in right
    # an artist's row had no right-click before R2: none now
    artists = flat(bare(source("Mac/Library/MacArtistsPage.swift")))
    assert "menu: { (_: Artist) -> EmptyModifier in EmptyModifier() }" in artists


def test_the_macs_album_rows_mark_playing_new_and_downloaded():
    # finding 9: the playing ▶ (Albums.dc.html's a.playing) read from the player, the New mark and the download mark
    albums = bare(source("Mac/Library/MacAlbumsPage.swift"))
    drawn = flat(body(albums, "var body: some View"))
    assert "let playing = player.current?.track.albumId" in drawn and "cell(album, column, playing: playing)" in drawn
    cell = flat(body(albums, "private func cell("))
    first = cell[cell.index("case 0:"):cell.index("case 1:")]
    assert re.search(r"if playing == album\.id \{ SharpSymbol\(\.play\) \.foregroundStyle\(DWPalette\.acc\) "
                     r"\.accessibilityElement\(children: \.ignore\) \.accessibilityLabel\(LibraryColumnWords\.playing\) \}",
                     first)
    assert "if server.access.hasLibrary && library.marks.isNew(album) { LibraryNewMark() }" in first
    second = cell[cell.index("case 1:"):cell.index("case 2:")]
    assert "if let mark = DownloadWords.mark(download) { DownloadMark(mark: mark," in second
    assert ".opacity(notHere(download) ? DWPalette.off : 1)" in cell
    # nothing here plays: the mark is read, never a call
    assert "player.play(" not in cell


def test_last_played_is_read_against_a_now_that_moves_with_the_day():
    # finding 7: no clock per cell - a `now` read as the page shows and at each significant time change
    artists = bare(source("Mac/Library/MacArtistsPage.swift"))
    assert "Date()" not in artists
    assert "@State private var now = ArtistTotals.now()" in artists
    assert re.search(r"\.onReceive\(NotificationCenter\.default\.publisher\(for: "
                     r"UIApplication\.significantTimeChangeNotification\)\) \{ _ in\s*now = ArtistTotals\.now\(\)\s*\}",
                     artists)
    assert "now = ArtistTotals.now()" in body(artists, ".onAppear {")
    assert "cell(artist, column, now: now)" in artists
    assert "ArtistTotals.lastPlayedWords(total?.lastPlayed, now: now)" in body(artists, "private func cell(")
    totals = (CORE / "ArtistTotals.swift").read_text(encoding="utf-8")
    assert "Int64(Date().timeIntervalSince1970 * 1000)" in body(totals, "public static func now()")


def test_arrow_keys_ask_only_once_the_selection_rests():
    # finding 8: the selected row's model once the selection has rested 200 ms; the album it leaves let go - (R5's
    # review) and Playlists' selected playlist, asked for Play and Shuffle the same way
    for name in ("Mac/Library/MacAlbumsPage.swift", "Mac/Library/MacArtistsPage.swift",
                 "Mac/Library/MacPlaylistsPage.swift"):
        code = bare(source(name))
        assert "private static let rest: UInt64 = 200_000_000" in code, name
        task = flat(body(code, ".task(id: ChosenKey("))
        assert re.search(r"if selected != nil \{ try\? await Task\.sleep\(nanoseconds: Self\.rest\) "
                         r"guard !Task\.isCancelled else \{ return \} \} await choose\(", task), name
    albums = bare(source("Mac/Library/MacAlbumsPage.swift"))
    choose = body(albums, "private func choose(")
    assert choose.count("leave()") == 2, "nothing selected, or another album: the one left let go"
    assert "if chosen !== model { player.albumLeft(id: album.id) }" in choose, "an answer after the selection left"
    leave = body(albums, "private func leave()")
    assert "player.albumLeft(id: chosen.route.id)" in leave and "self.chosen = nil" in leave
    assert "if let chosen { player.albumLeft(id: chosen.route.id) }" in body(albums, ".onDisappear {")
    assert "if let album = chosen?.album { player.albumShown(album) }" in body(albums, ".onAppear {")


def test_command_arrows_are_the_lists_ends_never_an_arrow():
    # finding 9: ⌘↑ ⌘↓ are Home and End; any other press with a modifier held is not the list's
    platform = source("Shared/Platform.swift")
    mac = platform.split("\n#else\n", 1)[0]
    keys = flat(body(mac, "func listKeys("))
    assert "let held = key.modifiers.intersection([.command, .shift, .option, .control])" in keys
    assert re.search(r"if !held\.isEmpty \{ guard held == \.command else \{ return \.ignored \} switch key\.key \{ "
                     r"case \.upArrow: return press\(\.home\) case \.downArrow: return press\(\.end\) "
                     r"default: return \.ignored \} \}", keys)
    # the plain keys after it: an arrow is never reached with a modifier held
    assert keys.index("if !held.isEmpty") < keys.index("case .upArrow: return press(.up)")
    columns = bare(source("Mac/Components/MacColumnList.swift"))
    assert ".listKeys { (key: ListKey) -> KeyPress.Result in pressed(key, ids: ids) }" in columns


def test_the_status_bar_counts_each_album_once():
    # finding 6: the Albums column is Navidrome's albumCount; the status bar the index's distinct albums
    artists = bare(source("Mac/Library/MacArtistsPage.swift"))
    status = flat(body(artists, "private func status("))
    assert "ArtistTotals.albumCount(of: listed, in: library.albums(scope)?.albums ?? [])" in status
    assert "albumCount ?? 0" not in status and "reduce(" not in status
    assert "ArtistTotals.number(artist.albumCount)" in body(artists, "private func cell(")
    totals = bare((CORE / "ArtistTotals.swift").read_text(encoding="utf-8"))
    assert "albums" not in body(totals, "public struct ArtistTotal: Sendable, Equatable"), "no albums total to sum"


def test_a_playlists_row_takes_two_lines_at_the_accessibility_sizes():
    # finding 9: as the row had before R2, so a long name isn't cut
    playlists = flat(bare(source("Playlists/PlaylistsScreen.swift")))
    assert "lines: typeSize.isAccessibilitySize ? 2 : 1)" in playlists
    assert "@Environment(\\.dynamicTypeSize) private var typeSize" in playlists
    row = flat(body(bare(source("Library/LibraryTiles.swift")), "struct LibraryListRow<"))
    assert "var lines = 1" in row and ".lineLimit(lines)" in row
