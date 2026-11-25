"""The redesign's slice R2 (notes/ios.md "The redesign, slice R2: Albums and Artists, and the Library's top"): the
Library's top, strip and pages as iLibrary, iArtists and iPlaylists draw them on the phone, and Albums and Artists as the
Mac's own column lists (Albums.dc.html, Artists.dc.html) - held to dw.css (ios/design/dw.css, the canvas's copy) where
it names a value, to the drawings' numbers where only a drawing does, and to James's answer 1 (25 Nov, "Today's
behaviour, new look"): Find kept, the strip in the order kept, Downloaded last and pushed, Songs never beside your own
albums, Yours | All in the All music menu's place, the meta line's sort and Grid | List, and the pager's swipe, the pull
and TopClearance as they were.

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
                 "Library/SongsScreen.swift", "Playlists/PlaylistsScreen.swift"):
        code = bare(source(name))
        assert not re.search(r"cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b", code), name


def test_the_redrawn_files_hold_only_tokens():
    # no colour made, by number or by name, no radius and no font of their own in what R2 drew
    names = ["Library/LibraryTop.swift", "Library/LibraryTiles.swift", "Mac/Library/MacAlbumsPage.swift",
             "Mac/Library/MacArtistsPage.swift", "Mac/Components/MacColumnList.swift", "Mac/Library/MacLibrary.swift"]
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


# ----------------------------------------------------------------------------- the top, Find and the strip

def test_the_librarys_top_is_ilibrarys_with_find_kept():
    top = bare(source("Library/LibraryTop.swift"))
    drawn = body(top, "var body: some View {")
    # "Library" at the left (the titled top), then Yours | All, Find's magnifying glass, the ••• - square small buttons
    assert "PhoneTop(title: AppTab.library.title) {" in drawn
    order = [drawn.index(part) for part in ("sides", "Button(action: openFind)", "more\n")]
    assert order == sorted(order)
    raw = source("Library/LibraryTop.swift")
    assert raw.count('Image(systemName: "magnifyingglass")') == 1
    find = flat(drawn[drawn.index("Button(action: openFind)"):drawn.index("more\n")])
    assert ".buttonStyle(DWButtonStyle(size: .small))" in find and ".accessibilityLabel(findLabel)" in find
    assert ".accessibilityShowsLargeContentViewer {" in find
    # Find's field under the row while it is open
    assert re.search(r"if finding \{\s*find\s*\.padding", drawn)
    view = bare(source("Library/LibraryView.swift"))
    assert re.search(r"LibraryTop\(finding: finding, findLabel: findPrompt\(shownPage\), openFind: \{ openFind\(\) \}\) \{"
                     r"\s*findField\(shownPage\)\s*\} sides: \{\s*sidesControl\s*\} more: \{", view)
    opening = body(view, "private func openFind()")
    assert "finding = true" in opening and "findFocused = true" in opening
    closing = body(view, "private func closeFind()")
    assert "clearFind()" in closing and "finding = false" in closing
    # the ••• is the small square button too, holding only what the meta line, the strip and Yours | All don't
    more = body(view, "private func more(")
    assert "LibraryMenu.topSections(" in more and "LibraryMenu.sections(" not in view
    assert ".buttonStyle(DWButtonStyle(size: .small))" in more and "CircleFace" not in view + top


def test_the_top_still_clears_the_dynamic_island():
    # TopClearance read as before (test_ios_palette.py holds the probe): the row comes down by the room, read in take()
    top = bare(source("Library/LibraryTop.swift"))
    drawn = body(top, "var body: some View {")
    assert ".padding(.top, clearance)" in drawn
    assert re.search(r"TopProbe\(eyes: eyes\) \{ \(sample: TopProbe\.Sample\) -> Void in\s*take\(sample\)\s*\}", drawn)
    take = body(top, "private func take(")
    assert "TopClearance.room(kept: Double(clearance)" in take and "clearance = CGFloat(room)" in take


def test_a_chip_moves_the_pager_and_downloaded_is_pushed():
    view = bare(source("Library/LibraryView.swift"))
    strip = flat(body(view, "private func strip("))
    assert "let items = LibraryStrip.items(order, albumsPage:" in strip
    assert "shown: Binding(get: { LibraryStripItem.page(shownPage) }, set: { (item: LibraryStripItem) -> Void in chose(item) })" in strip
    chose = flat(body(view, "private func chose("))
    assert "case .page(let chosen): withAnimation(reduceMotion ? nil : .snappy) { show(chosen) }" in chose
    assert "case .downloaded: navigation.open(.downloaded)" in chose
    show = flat(body(view, "private func show("))
    assert "page = chosen scrolled = chosen" in show
    # the pager's own swipe: its scroll position, the page following once at rest
    pager = body(view, "private func pager(albums: AlbumList)")
    assert ".scrollPosition(id: $scrolled, anchor: .center)" in pager and ".scrollTargetBehavior(.paging)" in pager
    assert ".pagerPhase(moving: $paging, settled: settled)" in pager
    # the strip under the top, the banner under the strip
    order = [pager.index(part) for part in ("LibraryTop(", "strip(order, albums: list)", "OfflineBanner()")]
    assert order == sorted(order)
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


def test_the_meta_lines_hold_the_sort_and_grid_or_list():
    albums = bare(source("Library/AlbumsScreen.swift"))
    meta = flat(body(albums, "private func meta("))
    assert "PhoneMetaLink(words: library.sort.label)" in meta and "Picker(LibraryWords.sortLabel, selection: $library.sort)" in meta
    assert "layoutToggle(.grid," in meta and "layoutToggle(.list," in meta
    toggle = flat(body(albums, "private func layoutToggle("))
    assert "library.layout = layout" in toggle and ".buttonStyle(DWToggleStyle(on: library.layout == layout))" in toggle
    artists = bare(source("Library/ArtistsScreen.swift"))
    assert "PhoneMetaLink(words: artists.order.label)" in body(artists, "private func meta(")
    playlists = bare(source("Playlists/PlaylistsScreen.swift"))
    assert "newSheet = NewSheet()" in body(playlists, "private func meta(")
    songs = bare(source("Library/SongsScreen.swift"))
    assert re.search(r"if page != nil \{\s*PhoneMeta \{\s*Text\(songs\.paging\.countText\)", songs)


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
    assert "scope: side.artistsScope))" in artists and ".id(side)" in artists, "All's Artists are the collection's"
    assert re.search(r"private var shuffleOf: ShuffleOf \{ side\.shuffle \}", view), "All's Shuffle is All songs'"
    assert "shuffles.take(shuffleOf," in body(view, "private func shuffleNow()")
    switch = (CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")
    assert "self == .all ? .scope(.store) : root" in body(switch, "public func albums(_ root: AlbumList)")
    assert "self == .all ? .store : nil" in body(switch, "public var artistsScope: AlbumScope?")
    assert "self == .all ? .allSongs : .library" in body(switch, "public var shuffle: ShuffleOf")


def test_downloaded_is_a_button_after_the_tab_bar():
    # finding 9: Downloaded pushes a page - VoiceOver hears a button, never a tab
    view = bare(source("Library/LibraryView.swift"))
    strip = flat(body(view, "private func strip("))
    assert "PhoneStrip(options: items.filter { (item: LibraryStripItem) -> Bool in !item.pushes }," in strip
    assert "pushes: items.filter { (item: LibraryStripItem) -> Bool in item.pushes })" in strip
    switch = (CORE / "LibrarySwitch.swift").read_text(encoding="utf-8")
    assert "self == .downloaded" in body(switch, "public var pushes: Bool")
    phone = bare(source("Phone/PhoneStrip.swift"))
    row = body(phone, "private var row: some View")
    tabs = row[row.index("ForEach(options"):row.index("ForEach(pushes")]
    assert ".accessibilityAddTraits(.isTabBar)" in tabs and ".accessibilityLabel(spoken)" in tabs
    after = row[row.index("ForEach(pushes"):]
    assert ".isTabBar" not in after, "the pushes are outside the tab bar"
    assert row.count(".accessibilityAddTraits(.isTabBar)") == 1


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
