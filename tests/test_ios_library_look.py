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
tap goes to; Downloaded is the •••'s again. (R1c, notes/ios.md "The redesign, slice R1c: the phone is flat
(2026-11-25)") Find and the ••• are bare white glyphs now, and the switch words over a hairline, the chosen one over the
accent's line. (27 Nov, notes/ios.md "The Library's line underlines what is chosen (27 Nov)" - James: "Yeah I like the
underline") The line's Grid, List, Yours and All too: grey until chosen, the chosen one white over the switch's own lit
line, with no hairline between Yours and All, and purple words left to what opens something - the order, New
playlist…. The row and the line fit a 375 pt phone at every text size - the line
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
fonts = _load("ios_fonts")
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


def test_the_rows_circles_are_bare_white_glyphs():
    # (R1c; James, 25 Nov: "get rid of all the grey boxes") .circ has no face: no edge, no fill, no sheen - its glyph
    # white (`.dw.ph .circ`'s #fff), 21 (`.circ svg`), centred in the 36 x 34 the circle was, in a 44 target
    assert phone_look.resolved(".circ")["border-top-width"] == "0" and css(".circ", "background") == "none"
    assert css(".circ", "box-shadow") == "none" and css(".circ", "color") == "#fff"
    assert px(css(".circ svg", "width")) == 21 == px(css(".circ svg", "height"))
    face = flat(body(bare(source("Phone/PhoneTop.swift")), "private struct PhoneCircleFace<"))
    assert "DWRaised" not in face and ".background" not in face and ".fill(" not in face
    assert ".foregroundStyle(DWPalette.text)" in face and ".opacity(enabled && !pressed ? 1 : DWPalette.off)" in face
    assert ("let face = CGFloat(PhoneLook.circle) let tall = CGFloat(PhoneLook.circleHeight) "
            "let target = max(face, CGFloat(DWLook.here.target))") in face
    order = [face.index(part) for part in (".frame(width: face, height: tall)", ".frame(width: target, height: target)",
                                           ".contentShape(Rectangle())")]
    assert order == sorted(order)
    # the glyph grows with the text (to the row's cap) - 21 scales with title3, the nearest of iOS's styles (20) - in the
    # box drawn at its size
    assert phone_look.nearest(21) == "title3" and ".font(Typeface.symbol(.title3))" in face
    # the ••• isn't drawn in the accent while open (`.circ.on`): SwiftUI's Menu tells its label nothing of it - said
    top = source("Phone/PhoneTop.swift")
    assert "The ••• isn't drawn in the accent while its menu is open" in top
    assert css(".circ.on", "color") == "#c084fc"


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
    assert 'glyph(.grid, symbol: "square.grid.2x2", words: LibrarySwitchWords.grid, after: half)' in raw
    assert 'glyph(.list, symbol: "list.bullet", words: LibrarySwitchWords.list, before: half)' in raw
    switch = flat(bare((CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")))
    assert "public static func layouts(on page: LibraryPage) -> Bool { page == .albums }" in switch
    # Yours | All: only with a choice handed in - LibraryView hands one only where R2's switch showed (LibraryPages.sides)
    sides = line[line.index("if let sides {"):]
    # (27 Nov) the two words side by side, each holding half the pair's room - no hairline between them now
    assert ("HStack(spacing: 0) { word(.yours, sides, after: half) word(.all, sides, before: half) } "
            ".accessibilityElement(children: .contain) .accessibilityLabel(LibrarySwitchWords.sidesLabel)") in sides
    assert "glyph(" not in sides and "word(" not in layouts
    # (27 Nov) iLibrary's first .pair's margin before Yours | All, only where Yours | All follows - on the line's 6
    assert ("HStack(spacing: 0) { glyph(.grid, symbol: \" \", words: LibrarySwitchWords.grid, after: half) "
            "glyph(.list, symbol: \" \", words: LibrarySwitchWords.list, before: half) } "
            ".padding(.trailing, sides == nil ? 0 : CGFloat(PhoneLook.pairAfter))") in layouts, layouts
    assert line.startswith("var body: some View { HStack(spacing: CGFloat(PhoneLook.metaGap)) {"), line
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
    # (27 Nov) each choice holds half the pair's room (.pair's gap) inside its target, so every point of a pair takes a
    # tap and the pair is as wide as drawn - the room on the inner side alone
    assert "private var half: CGFloat { CGFloat(PhoneLook.pairGap) / 2 }" in end
    assert end.count("after: half)") == 2 and end.count("before: half)") == 2
    assert "@ScaledMetric" not in end, "no hairline to grow with the words"


def test_the_chosen_one_is_underlined_and_purple_words_only_open_something():
    # (27 Nov - notes/ios.md "The Library's line underlines what is chosen (27 Nov)"; James: "it's not immediately clear
    # which of 'yours' or 'all' is selected", then "Yeah I like the underline") dw.css's block for it: a choice (.opt)
    # grey, the line's third colour, until chosen; chosen (.opt.on) white and semibold over the accent's 2 pt line -
    # the very line of the switch above it (.seg button.on) - and purple words left to the order and New playlist…
    accent, grey = css(".meta .link", "color"), css(".meta .opt", "color")
    assert accent == "#c084fc" and grey == css(".meta", "color") == css(".dw", "--t3")
    assert css(".meta .opt.on", "color") == "#fff" and css(".meta .opt.on", "font-weight") == "600"
    assert css(".meta .opt.on", "box-shadow") == css(".seg button.on", "box-shadow") == "inset 0 -2px 0 #c084fc"
    assert "font-weight" not in phone_look.resolved(".meta .opt"), "unchosen, the line's own weight"
    palette = source("Look/DWPalette.swift")
    assert "static let text = hex(0xffffff)" in palette and "static let acc = hex(0xc084fc)" in palette
    t3 = re.search(r"static let t3 = hex\(0x([0-9a-f]{6})\)", palette)
    assert t3 and f"#{t3.group(1)}" == grey, (t3, grey)
    code = bare(source("Library/LibraryLine.swift"))
    # each choice: its colour, its room, its height, the switch's lit line under it when chosen - one modifier, the
    # glyphs' and the words' alike, in that order: the line as wide as the words and their room, the pair's half outside
    choice = flat(body(code, "private struct LineChoice: ViewModifier {"))
    assert flat(body(choice, "func body(content: Content) -> some View {")) == (
        "func body(content: Content) -> some View { content .foregroundStyle(on ? DWPalette.text : DWPalette.t3) "
        ".padding(.horizontal, CGFloat(PhoneLook.optPadding)) .lookHeight(PhoneLook.opt) .modifier(DWChosenLine(on: on)) "
        ".padding(.leading, before) .padding(.trailing, after) .contentShape(DWTarget(face: Rectangle())) }")
    glyph = flat(body(code, "private func glyph("))
    assert "let on = library.layout == layout" in glyph
    assert (".font(Typeface.symbol(.body).weight(.medium)) .lookSquare(PhoneLook.optGlyph) "
            ".modifier(LineChoice(on: on, before: before, after: after))") in glyph
    assert ".accessibilityAddTraits(on ? .isSelected : [])" in glyph and ".accessibilityLabel(words)" in glyph
    word = flat(body(code, "private func word("))
    assert "let on = each == sides.side" in word
    assert (".font(Typeface.Phone.text(.meta).weight(on ? .semibold : .regular)) .lineLimit(1) "
            ".modifier(LineChoice(on: on, before: before, after: after))") in word
    assert ".accessibilityAddTraits(on ? .isSelected : [])" in word
    # VoiceOver hears the chosen one selected - the line is decoration, unheard, and never the only cue: the words are
    # white (and semibold) besides
    assert code.count(".accessibilityAddTraits(on ? .isSelected : [])") == 2
    # the line is the switch's own piece, not a second one drawn here: DWChosenLine, the accent's DWFlat.chosenLine at
    # the foot of what it marks, hidden from VoiceOver - and DWSegmented's phone segments draw it too
    seg = bare(source("Look/DWSegmented.swift"))
    chosen = flat(body(seg, "struct DWChosenLine: ViewModifier {"))
    assert chosen == ("struct DWChosenLine: ViewModifier { let on: Bool func body(content: Content) -> some View { content "
                      ".overlay(alignment: .bottom) { if on { Rectangle() .fill(DWPalette.acc) "
                      ".frame(height: CGFloat(DWFlat.chosenLine)) .accessibilityHidden(true) } } } }"), chosen
    assert ".modifier(DWChosenLine(on: on))" in flat(body(seg, "private func phoneSegment("))
    assert seg.count("DWFlat.chosenLine") == 1 and ".fill(" not in code and "chosenLine" not in code
    assert re.search(r"public static let chosenLine: Double = 2\s+// dw\.ph: \.seg button\.on box-shadow",
                     (CORE / "DWLook.swift").read_text(encoding="utf-8"))
    # the one rule, and no other colour in the line's end; the count keeps the line's third colour (PhoneMeta's)
    assert set(re.findall(r"DWPalette\.(\w+)", code)) == {"text", "t3"}
    assert ".foregroundStyle(DWPalette.t3)" in bare(source("Phone/PhoneMeta.swift"))
    # no hairline between Yours and All: no rule drawn in the line's end, and its colour gone from the palette
    assert not re.search(r"DWRule|Divider\(|metaRule|sidesRule|ScaledMetric", code)
    assert "metaRule" not in palette and "sidesRule" not in (CORE / "DWLook.swift").read_text(encoding="utf-8")
    # nothing boxed: no face, edge or fill behind a glyph or a word
    assert not re.search(r"DWRaised|DWToggleStyle|DWButtonStyle|\.background|strokeBorder|selbg", code)
    # purple words are for what opens or goes somewhere: the order's link with its caret (PhoneMetaLink, a Menu's label
    # on Albums and Artists), and Playlists' New playlist…, which opens its sheet
    link = flat(body(bare(source("Phone/PhoneMeta.swift")), "struct PhoneMetaLink: View {"))
    assert "DWCaret(colour: DWPalette.acc)" in link and ".foregroundStyle(DWPalette.acc)" in link
    for name in ("Library/AlbumsScreen.swift", "Library/ArtistsScreen.swift"):
        meta = flat(body(bare(source(name)), "private func meta("))
        assert re.search(r"\} label: \{ PhoneMetaLink\(words: \w+\.\w+\.label\) \} \.menuIndicator\(\.hidden\)", meta), name
    playlists = flat(body(bare(source("Playlists/PlaylistsScreen.swift")), "private func meta("))
    assert ("Text(PlaylistWords.newPlaylistRow) .font(Typeface.Phone.text(.meta)) .foregroundStyle(DWPalette.acc)"
            in playlists), playlists


def test_the_lines_choices_are_drawn_at_iLibrarys_sizes_as_tokens():
    # (27 Nov) each choice 28 tall, 13 pt, 3 either side of its words or its 17 pt glyph; 6 between the two of a pair;
    # Grid and List's pair 14 before Yours | All (iLibrary's inline margin), on the line's own 6; the line 32, as
    # iLibrary, iArtists and iPlaylists still draw it (iLibraryLine's sketches of the three ways alone draw 34)
    assert [phone_number(n) for n in ("opt", "optPadding", "optGlyph", "pairGap", "pairAfter", "meta", "metaGap")] == [
        28, 3, 17, 6, 14, 32, 6]
    assert px(css(".meta .opt", "height")) == 28 and px(css(".meta .opt", "padding-left")) == 3 == px(
        css(".meta .opt", "padding-right"))
    assert px(css(".meta .opt svg", "width")) == 17 == px(css(".meta .opt svg", "height"))
    assert px(css(".meta .pair", "gap")) == 6 and px(css(".meta", "gap")) == 6
    assert px(css(".meta .opt", "font-size")) == 13 == px(css(".meta", "font-size"))
    assert re.search(r"case \.meta: return \(13, \.footnote\)\s+// dw\.ph: \.meta font-size", source("Shared/Typeface.swift"))
    # the 14 and the 32 are the drawings' inline styles, held by test_ios_phone_look.py's PHONE_FROM_DRAWINGS
    assert phone_look.PHONE_FROM_DRAWINGS["pairAfter"] == 14 and phone_look.PHONE_FROM_DRAWINGS["meta"] == 32
    # each a token: no size of its own in the line's end - only none (the two pairs' HStacks, no margin without Yours
    # | All, the four defaults of a choice's half), the halving of the pair's room, and a word's one line
    code = bare(source("Library/LibraryLine.swift"))
    numbers = re.findall(r"(?<![\w.])\d+(?:\.\d+)?(?![\w.])", code)
    assert numbers == ["0", "0", "0", "2"] + ["0"] * 4 + ["1"], numbers
    assert flat(code).count("HStack(spacing: 0)") == 2


# ----------------------------------------------------------------------------- the row and the line fit, by arithmetic

#? Dynamic Type's footnote and body at each size (Apple's table): the row and the line are capped at xxxLarge, so every
#? accessibility size draws them as xxxLarge does
FOOTNOTE = {"xSmall": 12, "small": 12, "medium": 12, "large": 13, "xLarge": 15, "xxLarge": 17, "xxxLarge": 19}
#? (R1c) iOS's subheadline at each standard size, as FOOTNOTE: what the flat switch's 15 pt words scale with
SUBHEADLINE = {"xSmall": 12, "small": 13, "medium": 14, "large": 15, "xLarge": 17, "xxLarge": 19, "xxxLarge": 21}
BODY = {"xSmall": 14, "small": 15, "medium": 16, "large": 17, "xLarge": 19, "xxLarge": 21, "xxxLarge": 23}
#? an SF Symbol's width at its size, taken wide (square.grid.2x2 and list.bullet are about 1.1-1.2 of it)
SYMBOL = 1.3
#? the caret after an order's words (DWCaret, DWPopUp.swift's 8 x 4)
CARET = 8
#? the narrowest phone the app draws on: an iPhone SE's and a 13 mini's 375
NARROW = 375


def words_width(words: str, points: float, weight: str = "Regular") -> float:
    """`words`' width at `points` in the app's words face, "Regular" or "SemiBold": the bundled face's advances, read by
    tests/ios_fonts.py (Libre Franklin since 25 Nov - R2b measured in Noto Sans, the face before it)."""
    return fonts.words(words, points, weight.lower())


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
    # (R1c) the glyphs' boxes 36 wide (`.dw.ph .circ`), the circles' 34 before
    assert (room, folded) == (247, 343)
    # what the switch needs: the widest page's words in each equal segment (DWSegmented's 15 semibold since R1c, scaled
    # with the subheadline; .seg.lg's padding 0 on the phone), DWFlat's room of 6 either side of them (R1c: with no well
    # between them, so two neighbours never come closer than 12 beside the circles), and the 1 pt either end -
    # DWSegmentedNeed's very parts
    need = flat(body(bare(source("Look/DWSegmented.swift")), "struct DWSegmentedNeed: View {"))
    seg = flat(body(bare(source("Look/DWSegmented.swift")), "private func phoneSegment("))
    # (R2b's review) every segment as wide as the widest word - a ZStack of every word in each - and the whole of it
    # hidden, untouchable and unheard, at its own size
    assert need == ("struct DWSegmentedNeed: View { let words: [String] var body: some View { HStack(spacing: 0) { "
                    "ForEach(words.indices, id: \\.self) { (_: Int) in ZStack { ForEach(words.indices, id: \\.self) { "
                    "(at: Int) in Text(words[at]) .font(Typeface.Look.text(.largeSegment).weight(.semibold)) .lineLimit(1) "
                    ".padding(.horizontal, CGFloat(DWLook.here.largeSegmentPadding)) } } "
                    ".padding(.horizontal, CGFloat(DWFlat.segmentRoom)) } } .padding(1) .fixedSize() "
                    ".hidden() .allowsHitTesting(false) .accessibilityHidden(true) } }"), need
    assert ".font(Typeface.Look.text(.largeSegment).weight(.semibold))" in need
    assert ".font(Typeface.Look.text(large ? .largeSegment : .segment).weight(.semibold))" in seg
    assert ".padding(.horizontal, CGFloat(DWLook.here.largeSegmentPadding))" in need and ".padding(1)" in need
    assert re.search(r"largeSegmentPadding: 0,\s+// dw\.ph: \.seg\.lg button padding-left",
                     (CORE / "DWLook.swift").read_text(encoding="utf-8"))
    assert re.search(r"case \.largeSegment: return \(15, \.subheadline\)", source("Shared/Typeface.swift"))
    inside = phone_number("segmentRoom")
    assert inside == 6
    titles = {"albums": "Albums", "playlists": "Playlists", "artists": "Artists", "songs": "Songs"}
    orders = {"yours": ["albums", "playlists", "artists"], "all": ["albums", "artists", "songs"],
              "no library of your own": ["albums", "playlists", "artists", "songs"]}
    found, closest = {}, {}
    for size, subheadline in SUBHEADLINE.items():
        points = 15 * subheadline / 15
        for whose, pages in orders.items():
            widths = [words_width(titles[p], points, "SemiBold") for p in pages]
            needs = len(pages) * (max(widths) + 2 * inside) + 2
            folds = needs > room
            found[(whose, size)] = folds
            # beside the circles with its room; folded, its words alone fit the page's width less its sides at every
            # size, the room between them what the width leaves
            assert needs <= room or len(pages) * max(widths) + 2 <= folded, (whose, size, needs)
            segment = ((folded if folds else room) - 2) / len(pages)
            closest[(whose, size)] = min(segment - (a + b) / 2 for a, b in zip(widths, widths[1:]))
    # in Libre Franklin (25 Nov): Yours' three pages fold from xxLarge, All's at xxxLarge alone (245.8 of 247 at
    # xxLarge); the four of logins off and the break-glass sign-in fold from small (the standard size, large, among
    # them) - the room either side of each word R1c's, the 15 pt type the flat block's
    assert [size for (whose, size), folds in found.items() if folds and whose == "yours"] == ["xxLarge", "xxxLarge"]
    assert [size for (whose, size), folds in found.items() if folds and whose == "all"] == ["xxxLarge"]
    assert [size for (whose, size), folds in found.items() if folds and whose == "no library of your own"] == [
        "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge"]
    # beside the circles two neighbours' words never come closer than 12; folded, never touch - the four at xxxLarge
    # the closest, 4.4 apart
    assert min(gap for key, gap in closest.items() if not found[key]) >= 2 * inside
    assert min(closest.values()) == closest[("no library of your own", "xxxLarge")]
    assert round(closest[("no library of your own", "xxxLarge")], 1) == 4.4
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
    # (27 Nov) the end's choices: each its words or glyph (a box of 17 at least) and 3 either side, 6 apart in a pair,
    # and Grid and List's pair 14 before Yours | All, on the line's 6 - Core's MetaLine.end, held here word for word
    glyph, pad, pair, after = (phone_number(n) for n in ("optGlyph", "optPadding", "pairGap", "pairAfter"))
    assert NARROW - lead - trail == 343
    core = flat(bare((CORE / "DWLook.swift").read_text(encoding="utf-8")))
    assert ("public static func end(_ pairs: [[Double]]) -> Double { let drawn = pairs.filter { (pair: [Double]) -> Bool "
            "in !pair.isEmpty } let each = drawn.map { (pair: [Double]) -> Double in pair.reduce(0) { (sum: Double, "
            "choice: Double) -> Double in sum + choice + 2 * PhoneLook.optPadding } + Double(pair.count - 1) * "
            "PhoneLook.pairGap } return each.reduce(0, +) + Double(max(0, drawn.count - 1)) * (PhoneLook.metaGap + "
            "PhoneLook.pairAfter) }") in core

    def end_of(*pairs: list) -> float:
        """MetaLine.end, as Core says it: each choice and its room either side, a pair's two apart, the pairs apart."""
        drawn = [p for p in pairs if p]
        return (sum(sum(c + 2 * pad for c in p) + (len(p) - 1) * pair for p in drawn)
                + max(0, len(drawn) - 1) * (gap + after))

    def fit(full: float, short: float, end: float, room: float) -> str:
        """MetaLine.fit, as Core says it (the test above holds it): the first of its ways whose width fits."""
        for way, cut, folded in (("F", False, False), ("S", True, False), ("f", False, True), ("s", True, True)):
            words = short if cut else full
            width = max(words, end) if folded else (words + 2 * gap + end if end > 0 else words)
            if width <= room:
                return way
        return "s"

    def ends(points: float, size: str) -> dict:
        """Each line's end at a size, MetaLine.end's (27 Nov): Grid and List (bare glyphs, each its box or the symbol's
        width, the wider), then Yours | All - the side shown semibold, whichever is wider - with no hairline."""
        glyphs = [max(glyph, SYMBOL * BODY[size])] * 2
        yours = max((words_width("Yours", points, "SemiBold"), words_width("All", points)),
                    (words_width("Yours", points), words_width("All", points, "SemiBold")), key=sum)
        return {"albums": end_of(glyphs, list(yours)), "artists": end_of(list(yours)), "playlists": end_of(list(yours)),
                "songs": end_of(list(yours))}

    # the end as Core's unit test has it: 17 pt glyphs and words 30 and 15 - 52, then 20, then 63
    assert end_of([17, 17], [30, 15]) == 135 and end_of([], [30, 15]) == 63 and end_of([17, 17], []) == 52 and not end_of()

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
    # own (no thousands separator). In Libre Franklin (25 Nov), the face drawn today: another face moves these, and this
    # table with it - Libre Franklin moved two from R2b's Noto Sans, said beside them. (27 Nov) The end at the new
    # spacing moved seven more, said beside them with R2b's: on Albums it is 5.2 wider at the standard size here (152.7
    # of 147.5; 166.0 of 155.6 at xLarge) - Grid and List 6 apart where they were 2, and 20 before Yours where they were
    # 16, less the 3 the hairline's room gave back - with the glyphs taken at 1.3 of the symbol's size, the widest; at
    # their likelier 1.2 it is under 2 wider. Every other page's end is 3 narrower
    expected = {
        "large": {"140 albums": ("FFF", "SFF", "SSF"),
                  "2318 albums": ("FFF", "SSF", "SSS"),  # R2b: "SFF" - 393 held it whole
                  "12 of 140 albums": ("FFF", "SSS", "fSS"),
                  "12 of 2318 albums": ("FFF", "fSS", "ffS"),  # R2b: "fSS" - 393 held it on one line
                  "1234 of 2318 albums": ("SFF", "ffS", "fff")},  # Noto Sans: "fSS" - 393 held it
        "xLarge": {"140 albums": ("FFF", "SSS", "fSS"),  # Noto Sans: "SSS" - 375 held it
                   "2318 albums": ("FFF", "fSS", "ffS"),  # R2b: "SSS" and "fSS"
                   "12 of 140 albums": ("SSF", "fff", "fff"),  # R2b: "SFF" and "ffS"
                   "12 of 2318 albums": ("SSS", "fff", "fff"),  # R2b: "SSF"
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
    # "140 albums · Recently added" (352 of 343 on 375; 351 in Noto Sans) now "140 · Recently added"; on 402 Find's
    # first keystroke never folds it either but for a four-figure find under the longest order, on 393 under "Recently
    # added" too - and (27 Nov, the end at its new spacing) a four-figure library's find under the longest; on 375,
    # with "Recently added", only in a four-figure library (notes/ios.md "The redesign, slice R2b": what is left)
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
