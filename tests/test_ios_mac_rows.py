"""The Mac's Row Size (notes/ios.md "The Mac's Row Size (2026-11-25)"): View > Row Size's Small, Medium and Large, ⌘+
and ⌘− a size at a time, kept on this Mac - and every Mac list drawing its rows at the size chosen: Albums and Artists,
an album's songs, Playlists and a playlist (MacColumnList's rows, and the covers their pages draw in them), and
Requests' own table (34 at Small, its drawing's). The header strip (24) and a heading's row (26) never change; the
iPhone draws none of it.

Read from the source, as every test of the app's look is: nothing here builds or runs the app (the builds and the
device checks 608 and 609 do). Core's rules - the sizes, the steps and their ends, the menu's items, the box added up,
Large's fit at every page - are DeadwaxKit's MacRowSizeTests."""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"

COLUMN_LIST = "Mac/Components/MacColumnList.swift"
ALBUMS = "Mac/Library/MacAlbumsPage.swift"
ARTISTS = "Mac/Library/MacArtistsPage.swift"
PLAYLISTS = "Mac/Library/MacPlaylistsPage.swift"
ALBUM = "Mac/Album/MacAlbumPage.swift"
PLAYLIST = "Mac/Album/MacPlaylistPage.swift"
REQUESTS = "Mac/Requests/MacRequestsPage.swift"
SIZING = "Mac/Components/MacRowSizing.swift"
FRAME = "Root/DesktopFrame.swift"
COMMANDS = "Shared/MacCommands.swift"
READER = "@Environment(\\.macRowSize) private var rowSize"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_rows_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def flat(code: str) -> str:
    return re.sub(r"\s+", " ", code)


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


def number(text: str, name: str) -> float:
    return float(re.search(rf"public static let {name}: Double = (\d+)", text).group(1))


def sizes() -> dict[str, dict[str, float]]:
    """MacRowSize's row and cover at each size, read from its two switches - Small's row MacLook's own."""
    code = bare(core("MacRowSize.swift"))
    out = {}
    for field in ("rowHeight", "cover"):
        switch = body(code, f"public var {field}: Double {{")
        for case, value in re.findall(r"case \.(small|medium|large): return ([\w.]+)", switch):
            if value == "MacLook.rowHeight":
                value = number(core("MacLook.swift"), "rowHeight")
            out.setdefault(case, {})[field] = float(value)
    return out


def calls(code: str, name: str) -> list[str]:
    """Each `name(...)`'s arguments in `code`, flattened - `.frame(` say - read to its own closing parenthesis."""
    found = []
    for start in [m.end() for m in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\(", code)]:
        depth = 1
        for end in range(start, len(code)):
            depth += {"(": 1, ")": -1}.get(code[end], 0)
            if depth == 0:
                found.append(flat(code[start:end]).strip())
                break
    return found


def heights(code: str) -> list[str]:
    """The `.frame(...)`s in `code` that set a height, a least or a most."""
    return [args for args in calls(code, ".frame") if re.search(r"\b(?:min|max)?[hH]eight:", args)]


# A vertical alignment that isn't the middle: a cell or a row drawn with one sits its words at the row's top or foot
# once the rows grow. Overlays (`.overlay(alignment: .bottom)`, the row line's rule) are a row's own and allowed.
OFF_CENTRE = re.compile(r"alignment: \.(?:top|bottom|topLeading|topTrailing|bottomLeading|bottomTrailing)\b")


def off_centre(code: str) -> list[str]:
    """What in `code` aligns other than to the middle - in a frame or a stack, never an overlay's own."""
    out = [args for args in calls(code, ".frame") if OFF_CENTRE.search(args)]
    for stack in ("HStack", "ZStack"):
        out += [args for args in calls(code, stack) if OFF_CENTRE.search(args)]
    return out


def chain(code: str, start: str, end: str = ".accessibilityHidden(true)") -> str:
    """A view and the modifiers after it, from `start` to the end of `end`, flattened."""
    at = code.index(start)
    return flat(code[at:code.index(end, at) + len(end)])


# ----------------------------------------------------------------------------- the sizes

def test_three_sizes_small_the_default():
    # Small 30 with a 20 cover (today's, and the default), Medium 40 with 28 (the drawing's), Large 52 with 40
    assert sizes() == {"small": {"rowHeight": 30, "cover": 20}, "medium": {"rowHeight": 40, "cover": 28},
                       "large": {"rowHeight": 52, "cover": 40}}
    code = flat(bare(core("MacRowSize.swift")))
    assert "public enum MacRowSize: String, CaseIterable, Sendable, Hashable { case small, medium, large" in code
    assert "public static let standard: MacRowSize = .small" in code
    assert "case .small: return MacLook.rowHeight" in code, "Small's row is MacLook's own, never a copy"
    # an unknown or missing saved value reads as the default; the steps stop at the ends
    assert "MacRowSize(rawValue: raw) } ?? Self.standard" in code
    assert "public var bigger: MacRowSize? { switch self { case .small: return .medium case .medium: return .large case .large: return nil" in code
    assert "public var smaller: MacRowSize? { switch self { case .small: return nil case .medium: return .small case .large: return .medium" in code
    # Requests: Small its drawing's 34 with a 22 cover; Medium and Large every list's own
    assert "self == .small ? RequestColumns.rowHeight : rowHeight" in code
    assert "self == .small ? RequestColumns.cover : cover" in code
    requests = core("RequestFilter.swift")
    assert number(requests, "rowHeight") == 34 and number(requests, "cover") == 22
    # the header and a heading's row aren't the rows', and keep their heights
    look = core("MacLook.swift")
    assert number(look, "headerHeight") == 24 and number(look, "groupRowHeight") == 26
    # kept on this Mac alone, in UserDefaults (MacCommands' MacRowSizeStore)
    assert 'public static let storageKey = "deadwax-mac-row-size"' in core("MacRowSize.swift")


# ----------------------------------------------------------------------------- every list reads it

def test_every_mac_list_reads_the_size_chosen():
    for name in (COLUMN_LIST, ALBUMS, ARTISTS, PLAYLISTS, ALBUM, REQUESTS):
        assert READER in bare(source(name)), name
    # MacColumnList's rows - Albums', Artists', an album's songs, Playlists', a playlist's songs
    columns = flat(bare(source(COLUMN_LIST)))
    assert ".frame(height: CGFloat(rowSize.rowHeight))" in columns
    heading = flat(body(bare(source(COLUMN_LIST)), "private func heading("))
    assert "MacLook.groupRowHeight" in heading and "rowSize" not in heading, "a heading's row keeps its 26"
    for name in (ALBUMS, ARTISTS, PLAYLISTS, ALBUM, PLAYLIST):
        assert "MacColumnList(" in bare(source(name)), name
    # the covers in the rows
    assert ("LibraryCover(id: album.coverArt, pixels: CoverSize.row) .frame(width: CGFloat(rowSize.cover), "
            "height: CGFloat(rowSize.cover))") in flat(bare(source(ALBUMS)))
    assert "ArtistPicture(id: artist.coverArt, side: CGFloat(rowSize.cover), pixels: CoverSize.row)" in flat(
        bare(source(ARTISTS)))
    playlists = flat(bare(source(PLAYLISTS)))
    assert ("PlaylistCover(id: playlist.coverArt, side: CGFloat(rowSize.cover), pixels: CoverSize.row) "
            ".frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))") in playlists
    # Playlists' columns fitted at the size's least
    assert "MacAlbumFacts.playlistColumns(width: Double(room.size.width), size: rowSize)" in playlists
    # an album's songs: the box added up at the size the list draws its rows
    album = flat(bare(source(ALBUM)))
    assert "let tall = CGFloat(rowSize.boxHeight(rows: rows.count, headings: headings))" in album
    assert "let least = CGFloat(rowSize.boxLeast(rows: rows.count, headings: headings, room: boxRoom))" in album
    # Requests' table: its row, its cover, and the album's least at the size
    requests = flat(bare(source(REQUESTS)))
    assert ".frame(height: CGFloat(rowSize.requestRowHeight))" in requests
    assert ".frame(width: CGFloat(rowSize.requestCover), height: CGFloat(rowSize.requestCover))" in requests
    assert "RequestColumns.widths(total, size: rowSize)" in requests
    assert requests.count("RequestColumns.width(total, size: rowSize)") == 2
    assert "RequestColumns.width(total)" not in requests and "RequestColumns.widths(total)" not in requests
    # the meter keeps its height and its words: legible at every size
    assert "rowSize" not in flat(body(bare(source(REQUESTS)), "private func progressCell("))


def test_no_row_height_of_its_own_left_on_the_mac():
    # no list draws a row at a height of its own: no 30 or 34, no MacLook.rowHeight or RequestColumns' Small, no row
    # cover at 20 or 22
    height = re.compile(r"\b(?:min|max)?[hH]eight: (?:CGFloat\()?(?:30|34)\b")
    cover = re.compile(r"\b(?:side|width|height): (?:CGFloat\()?(?:20|22)\b")
    for path in sorted((APP / "Mac").rglob("*.swift")):
        name = path.relative_to(APP).as_posix()
        code = bare(path.read_text(encoding="utf-8"))
        assert not height.search(code), f"{name}: a row height of its own"
        for small in ("MacLook.rowHeight", "RequestColumns.rowHeight", "RequestColumns.cover"):
            assert small not in code, f"{name}: {small} - Small's alone; the rows are View > Row Size's"
        if name in (ALBUMS, ARTISTS, PLAYLISTS, REQUESTS):
            assert not cover.search(code), f"{name}: a row's cover of its own"
    # the planted ones are caught
    for planted in (".frame(height: 30)", ".frame(height: CGFloat(34))", ".frame(minHeight: 30)"):
        assert height.search(bare(planted + "\n")), planted
    for planted in ("Cover(id: x, side: 20)", ".frame(width: 22, height: 22)"):
        assert cover.search(bare(planted + "\n")), planted
    # nor a size by name: a list reads the one chosen (`rowSize`), never Small's, Medium's or Large's own - a frame
    # after the reader's, at a size of its own, would win over it
    named = re.compile(r"\bMacRowSize\.(?:small|medium|large|standard)\b")
    for path in sorted((APP / "Mac").rglob("*.swift")):
        assert not named.search(bare(path.read_text(encoding="utf-8"))), path.relative_to(APP).as_posix()
    assert named.search(".frame(height: CGFloat(MacRowSize.small.rowHeight))")


# ----------------------------------------------------------------------------- one height, one cover, centred

#: Each list's cell function, and the frames setting a height in it: none but its cover's.
CELLS = {
    ALBUMS: ["width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover)"],
    ARTISTS: [],
    PLAYLISTS: ["width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover)"],
    ALBUM: [],
    PLAYLIST: [],
}
#: Requests' cells, and theirs.
REQUEST_CELLS = {
    "private func albumCell(": ["width: CGFloat(rowSize.requestCover), height: CGFloat(rowSize.requestCover)"],
    "@ViewBuilder private func progressCell(": [],
    "private func speedCell(": [],
    "private func buttons(": [],
    "@ViewBuilder private func button(": [],
}


def test_a_row_is_one_height_the_size_chosen():
    # A row's height is one frame, the size chosen's: a second after it - Small's, a number - would win, whatever the
    # first says. MacColumnList's row (every list but Requests) and Requests' own.
    line = bare(body(bare(source(COLUMN_LIST)), "private func line("))
    assert heights(line) == ["height: CGFloat(rowSize.rowHeight)"], heights(line)
    row = bare(body(bare(source(REQUESTS)), "private func rowLine("))
    assert heights(row) == ["height: CGFloat(rowSize.requestRowHeight)"], heights(row)
    # and nothing in a cell sets one: a cell as tall as it likes would stretch the row, or sit off its middle
    cell = body(bare(source(REQUESTS)), "private func cell<")
    assert calls(cell, ".frame") == ["width: width, alignment: alignment"], calls(cell, ".frame")
    for name, covers in CELLS.items():
        drawn = body(bare(source(name)), "private func cell(")
        assert heights(drawn) == covers, (name, heights(drawn))
    requests = bare(source(REQUESTS))
    for opening, covers in REQUEST_CELLS.items():
        assert heights(body(requests, opening)) == covers, (opening, heights(body(requests, opening)))
    # the planted override is seen
    planted = ".frame(height: CGFloat(rowSize.rowHeight)) .frame(height: CGFloat(MacRowSize.small.rowHeight))"
    assert len(heights(planted)) == 2


def test_each_lists_cover_is_one_size_the_size_chosen():
    # Each list's cover from its picture to its last modifier: sized once, at the size chosen - a frame after it at a
    # size of its own would draw that size, whatever the first said
    albums = chain(bare(source(ALBUMS)), "LibraryCover(id: album.coverArt, pixels: CoverSize.row)")
    assert calls(albums, ".frame") == ["width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover)"], albums
    artists = chain(bare(source(ARTISTS)), "ArtistPicture(id: artist.coverArt, side: CGFloat(rowSize.cover)")
    assert calls(artists, ".frame") == [] and calls(artists, "ArtistPicture") == [
        "id: artist.coverArt, side: CGFloat(rowSize.cover), pixels: CoverSize.row"], artists
    playlists = chain(bare(source(PLAYLISTS)), "PlaylistCover(id: playlist.coverArt, side: CGFloat(rowSize.cover)")
    assert calls(playlists, ".frame") == ["width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover)"], playlists
    assert calls(playlists, "PlaylistCover") == [
        "id: playlist.coverArt, side: CGFloat(rowSize.cover), pixels: CoverSize.row"], playlists
    requests = chain(bare(source(REQUESTS)), "ArchiveCover(addresses: addresses, size: ArchiveCoverSize.row)")
    assert calls(requests, ".frame") == [
        "width: CGFloat(rowSize.requestCover), height: CGFloat(rowSize.requestCover)"], requests
    # one cover in each row's cell, and the chain runs to its end: the cover's last modifier is the next view's line
    for name, picture in ((ALBUMS, "LibraryCover("), (ARTISTS, "ArtistPicture("), (PLAYLISTS, "PlaylistCover(")):
        assert body(bare(source(name)), "private func cell(").count(picture) == 1, name
    assert body(bare(source(REQUESTS)), "private func albumCell(").count("ArchiveCover(") == 1
    for each in (albums, artists, playlists, requests):
        assert each.endswith(".accessibilityHidden(true)") and each.count(".accessibilityHidden(") == 1, each
    for name, after in ((ALBUMS, "Text(album.name"), (ARTISTS, "Text(artist.name"), (PLAYLISTS, "Text(playlist.name")):
        cell = flat(body(bare(source(name)), "private func cell("))
        assert ".accessibilityHidden(true) " + after in cell, name
    assert ".accessibilityHidden(true) Text(row.title)" in flat(body(bare(source(REQUESTS)), "private func albumCell("))


def test_the_header_and_a_headings_row_keep_their_heights_at_every_size():
    # The header strip is 24 and a heading's row 26 at every size (MacLook's): the rows grow, never the strip over them
    columns = bare(source(COLUMN_LIST))
    header = body(columns, "private func header(")
    assert heights(header) == ["maxHeight: .infinity", "height: CGFloat(MacLook.headerHeight)"], heights(header)
    assert "rowSize" not in header
    heading = body(columns, "private func heading(")
    assert heights(heading) == ["height: CGFloat(MacLook.groupRowHeight)"] and "rowSize" not in heading
    requests = bare(source(REQUESTS))
    header = body(requests, "private func header(")
    assert heights(header) == ["maxHeight: .infinity", "height: CGFloat(MacLook.headerHeight)"], heights(header)
    assert "rowSize" not in header
    group = body(requests, "private func groupLine(")
    assert heights(group) == ["height: CGFloat(DWLook.here.groupRowHeight)"] and "rowSize" not in group
    assert number(core("MacLook.swift"), "headerHeight") == 24


def test_a_rows_words_sit_in_its_middle():
    # Taller rows keep their words in their middle: no cell, row or stack in one aligns to its top or its foot (the
    # row line's rule, an overlay, is the row's own). MacColumnList's row and its pages' cells; Requests' row, its
    # cell and what each column draws in it.
    columns = bare(source(COLUMN_LIST))
    line = body(columns, "private func line(")
    assert off_centre(line) == [], off_centre(line)
    # the row's own stack and frames: centred - a leading frame leads across, never up or down. (The fonts commit, 25
    # Nov) The cells on one first text baseline - Courier Prime's shorter line, centred, sat a readout 1-2 pt above the
    # words beside it - and the row's frame centres that line in the row's height, whatever the size: never the top or
    # the foot (tests/test_ios_readout_rows.py holds every readout beside words to the baseline)
    assert calls(line, "HStack") == ["alignment: .firstTextBaseline, spacing: 0"], calls(line, "HStack")
    assert calls(line, ".frame") == ["width: CGFloat(index < widths.count ? widths[index] : 0), alignment: .leading",
                                     "height: CGFloat(rowSize.rowHeight)",
                                     "maxWidth: .infinity, alignment: .leading"], calls(line, ".frame")
    for name in CELLS:
        drawn = body(bare(source(name)), "private func cell(")
        assert off_centre(drawn) == [], (name, off_centre(drawn))
        assert "maxHeight" not in drawn and "minHeight" not in drawn, name
    requests = bare(source(REQUESTS))
    row = body(requests, "private func rowLine(")
    assert off_centre(row) == [] and calls(row, "HStack") == ["alignment: .firstTextBaseline, spacing: 0"], off_centre(row)
    # every column's cell through cell(), leading or trailing across and centred up and down
    placed = calls(row, "cell")
    assert len(placed) == 6 and all(not OFF_CENTRE.search(args) for args in placed), placed
    assert sorted({args.split("alignment: ")[1] for args in placed if "alignment: " in args}) == [".trailing"], placed
    cell = body(requests, "private func cell<")
    assert "alignment: Alignment = .leading" in flat(cell) and off_centre(cell) == [], off_centre(cell)
    for opening in REQUEST_CELLS:
        drawn = body(requests, opening)
        assert off_centre(drawn) == [], (opening, off_centre(drawn))
        assert "maxHeight" not in drawn and "minHeight" not in drawn, opening
    # the planted ones are seen: a cell's frame, the row's stack
    assert off_centre(".frame(maxHeight: .infinity, alignment: .top)") and off_centre("HStack(alignment: .bottom) {}")
    assert off_centre(".frame(maxHeight: .infinity, alignment: .topLeading)")
    assert not off_centre(".overlay(alignment: .bottom) { DWRule() }")


def test_a_downloads_meter_sits_in_the_rows_middle():
    # Requests' meter (DWMeter) and its words: one stack in the cell's middle - no frame or stack of theirs pinned to
    # the row's top or foot, nothing as tall as the row, its least width the only frame. (The fonts commit) The words on
    # the row's baseline, and the meter - no words of its own, so its foot would be its baseline - centred on their line
    # by centredOnWords at the row's words' size, where the centred stack had it
    progress = body(bare(source(REQUESTS)), "@ViewBuilder private func progressCell(")
    downloading = progress[progress.index("case .downloading:"):progress.index("case .waiting:")]
    assert calls(downloading, ".frame") == ["minWidth: CGFloat(RequestColumns.meterLeast)"], calls(downloading, ".frame")
    assert calls(downloading, "HStack") == ["alignment: .firstTextBaseline, spacing: 8"], calls(downloading, "HStack")
    assert calls(downloading, ".centredOnWords") == ["CGFloat(Typeface.Mac.Size.base.rawValue)"], downloading
    assert ("DWMeter(fraction: row.progress / 100) .frame(minWidth: CGFloat(RequestColumns.meterLeast)) "
            ".centredOnWords(CGFloat(Typeface.Mac.Size.base.rawValue))") in flat(downloading)
    assert off_centre(downloading) == []
    assert "alignment" not in downloading.replace("HStack(alignment: .firstTextBaseline, spacing: 8)", "HStack(spacing: 8)")
    assert flat(downloading).count("DWMeter(fraction: row.progress / 100)") == 1
    # the cell it sits in is centred too (test_a_rows_words_sit_in_its_middle), and so is the row
    row = flat(body(bare(source(REQUESTS)), "private func rowLine("))
    assert "cell(widths[3]) { progressCell(row) }" in row


def test_a_short_window_keeps_properties_on_the_page():
    # An album's page: the songs' box never asks for more than the page has left - its edges, the gap above it, the
    # hero and Properties as drawn - so a short window at Large keeps Properties on the page (Core's arithmetic:
    # MacRowSizeTests' aShortWindowNeverPushesPropertiesOffThePage). At heights with room, the least is as drawn.
    album = bare(source(ALBUM))
    room = flat(body(album, "private var boxRoom: Double? {"))
    assert ("MacRowSize.boxRoom(page: pageTall, around: Double(Drawn.top + Drawn.bottom + Drawn.boxAbove) + heroTall "
            "+ propertiesTall)") in room
    for name in ("pageTall", "heroTall", "propertiesTall"):
        assert f"@State private var {name}: Double = 0" in album, name
        assert flat(album).count(f"{name} = now") == 1, name
    page = flat(album)
    measured = ("onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in Double(frame.size.height) } "
                "action: { (now: Double) -> Void in ")
    assert f"hero .{measured}heroTall = now }}" in page
    assert f"properties(album) .{measured}propertiesTall = now }}" in page
    assert (".padding(EdgeInsets(top: Drawn.top, leading: Drawn.side, bottom: Drawn.bottom, trailing: Drawn.side)) "
            f".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) .{measured}pageTall = now }}") in page
    # MacPage frames its content the same way, so the page's own frame moves nothing
    assert ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)" in flat(bare(
        source("Mac/Frame/MacPage.swift")))
    songs = flat(body(album, "private func songs("))
    assert "let least = CGFloat(rowSize.boxLeast(rows: rows.count, headings: headings, room: boxRoom))" in songs
    assert ".frame(minHeight: least, maxHeight: tall)" in songs
    # the drawn edges Core's test adds up: 20 above, 16 below, 18 over the box, the cover 132
    for name, points in (("top", 20), ("bottom", 16), ("boxAbove", 18), ("cover", 132)):
        assert f"static let {name}: CGFloat = {points}" in album, name
    rule = flat(bare(core("MacRowSize.swift")))
    assert ("public func boxLeast(rows: Int, headings: Int, room: Double?) -> Double { let least = boxLeast(rows: "
            "rows, headings: headings) guard let room else { return least } return min(least, max(room, 0)) }") in rule
    assert ("public static func boxRoom(page: Double, around: Double) -> Double? { page > 0 ? page - around : nil }"
            in rule)


def test_the_row_selected_stays_in_view_as_the_size_changes():
    # Rows taller or shorter move the one selected: each list brings it back into view, as it does when the keys move it
    columns = flat(bare(source(COLUMN_LIST)))
    assert (".onChange(of: rowSize) { (_: MacRowSize, _: MacRowSize) -> Void in guard let selected else { return } "
            "proxy.scrollTo(selected) }") in columns
    assert ".id(row.id)" in columns
    requests = flat(bare(source(REQUESTS)))
    assert (".onChange(of: rowSize) { (_: MacRowSize, _: MacRowSize) -> Void in if let selected { "
            "proxy.scrollTo(MacTable.Line<String>.row(selected)) } }") in requests
    # inside each list's ScrollViewReader, beside its own selection's
    for code, opening in ((bare(source(COLUMN_LIST)), "ScrollViewReader {"),
                          (bare(source(REQUESTS)), "ScrollViewReader {")):
        reader_ = flat(body(code, opening))
        assert reader_.count(".onChange(of: rowSize)") == 1 and ".onChange(of: selected)" in reader_


def test_the_frame_hands_the_one_choice_down():
    frame = flat(bare(source(FRAME)))
    assert ".environment(\\.macRowSize, MacRowSizeStore.shared.size) .modifier(RowSizeAlternateKey())" in frame
    sources = {path.relative_to(APP).as_posix(): bare(path.read_text(encoding="utf-8"))
               for path in sorted(APP.rglob("*.swift"))}
    handed = [name for name, code in sources.items() if ".environment(\\.macRowSize" in code]
    assert handed == [FRAME], handed
    sizing = flat(bare(source(SIZING)))
    assert "private struct MacRowSizeKey: EnvironmentKey { static let defaultValue: MacRowSize = .standard }" in sizing
    assert "var macRowSize: MacRowSize { get { self[MacRowSizeKey.self] } set { self[MacRowSizeKey.self] = newValue } }" in sizing
    # the iPhone draws none of it: the Mac's files, the frame and the menus alone name it
    for name, code in sources.items():
        if re.search(r"\b(MacRowSize|macRowSize|MacRowSizeStore|RowSizeAlternateKey)\b", code):
            assert name.startswith("Mac/") or name in (FRAME, COMMANDS), name
    # and in Core, the Mac's own files and Requests' columns - and (R7) Search's table and Get's tracklist
    for path in sorted(CORE.glob("*.swift")):
        if re.search(r"\bMacRowSize\b", bare(path.read_text(encoding="utf-8"))):
            assert path.name in ("MacRowSize.swift", "MacMenu.swift", "MacAlbumFacts.swift", "RequestFilter.swift",
                                 "SearchTable.swift"), path


# ----------------------------------------------------------------------------- the menu and the keys

def test_view_row_size_is_three_ticks_and_two_keys():
    words = core("MacMenu.swift")
    for name, said in (("rowSize", "Row Size"), ("smallRows", "Small"), ("mediumRows", "Medium"),
                       ("largeRows", "Large"), ("biggerRows", "Make Bigger"), ("smallerRows", "Make Smaller")):
        assert f'public static let {name} = "{said}"' in words, name
    code = flat(bare(words))
    # its sections: the three sizes, then the two steps
    assert "public static let rowSizes: [Command] = [.smallRows, .mediumRows, .largeRows]" in code
    assert "[Command.rowSizes, [.biggerRows, .smallerRows]].map { $0.map { item($0, state) } }" in code
    # ⌘+ and ⌘−, the sizes none of their own, ⌘= Make Bigger's second key
    key = words[words.index("public static func key("):words.index("public static func alternateKey(")]
    assert 'case .biggerRows: return Shortcut(.character("+"), .command)' in key
    assert 'case .smallerRows: return Shortcut(.character("-"), .command)' in key
    assert "case .smallRows, .mediumRows, .largeRows: return nil" in key
    assert 'command == .biggerRows ? Shortcut(.character("="), .command) : nil' in words
    # no other item has +, - or = - nor Platform's keys
    for char in ("+", "-", "="):
        assert key.count(f'.character("{char}")') == (0 if char == "=" else 1), char
    platform = bare(source("Shared/Platform.swift"))
    assert not re.search(r'keyboardShortcut\("[+=-]"|KeyEquivalent\("[+=-]"\)', platform)
    # the ticks; the steps dimmed at their ends, and nothing else dims them
    enabled = flat(bare(words[words.index("static func enabled("):words.index("static func ticked(")]))
    assert "case .smallRows, .mediumRows, .largeRows: return true" in enabled
    assert "case .biggerRows, .smallerRows: return rowSize(after: command, from: state.rowSize) != nil" in enabled
    ticked = flat(bare(words[words.index("static func ticked("):]))
    assert "case .smallRows, .mediumRows, .largeRows: return state.rowSize == command.rowSize" in ticked


def test_the_menu_draws_row_size_under_refresh():
    code = bare(source(COMMANDS))
    commands = code[code.index("struct MacCommands: Commands {"):code.index("final class TextEditing")]
    view = flat(commands)
    assert ("CommandGroup(after: .toolbar) { item(.refresh, state) Divider() Menu(MacMenu.Words.rowSize) "
            "{ rowSizes(state) } }") in view
    sizes_ = flat(body(commands, "@ViewBuilder private func rowSizes("))
    assert "let sections = MacMenu.rowSize(state)" in sizes_ and "if index > 0 { Divider() }" in sizes_
    assert "if each.command.rowSize != nil { tick(each) } else { button(each) }" in sizes_
    # the state the menus are drawn from reads the store's size; a click is the store's to keep
    assert "rowSize: MacRowSizeStore.shared.size)" in view
    perform = flat(commands[commands.index("private func perform("):commands.index("static func shortcut(")])
    assert ("case .smallRows, .mediumRows, .largeRows, .biggerRows, .smallerRows: "
            "MacRowSizeStore.shared.perform(command) case .saveChanges:") in perform
    # ⌘+ and ⌘− are free: Format goes, and with it the system's Bigger and Smaller (its Font's ⌘+ and ⌘−, as its
    # Italic's ⌘I gave Info its key); View's own places are kept, the toolbar's only added after
    assert "CommandGroup(replacing: .textFormatting) {}" in commands
    assert "replacing: .toolbar" not in commands and "before: .toolbar" not in commands


def test_command_equals_is_make_biggers_second_key():
    code = bare(source(COMMANDS))
    alternate = flat(body(code, "struct RowSizeAlternateKey: ViewModifier {"))
    # the key: a button drawn nowhere, never a Tab stop (focusable(false)), dimmed at Large as the item is, the same
    # step through the same store
    for part in ("let state = MacMenu.State(rowSize: MacRowSizeStore.shared.size)",
                 "Button(action: bigger) { Color.clear } "
                 ".keyboardShortcut(MacCommands.shortcut(MacMenu.alternateKey(.biggerRows))) "
                 ".disabled(!MacMenu.item(.biggerRows, state).enabled) "
                 ".focusable(false) .frame(width: 0, height: 0) .opacity(0) .accessibilityHidden(true)",
                 "private func bigger() { MacRowSizeStore.shared.perform(.biggerRows) }"):
        assert part in alternate, part
    assert "@AppStorage" not in alternate
    # on the main window's frame alone: it answers while that window is the key one
    sources = {path.relative_to(APP).as_posix(): bare(path.read_text(encoding="utf-8"))
               for path in sorted(APP.rglob("*.swift"))}
    worn = [name for name, code_ in sources.items() if "RowSizeAlternateKey()" in code_]
    assert worn == [FRAME], worn
    assert bare(source(FRAME)).count("RowSizeAlternateKey()") == 1
    # the menus' two keys and this one: MacCommands' three, and no other key of its own
    assert code.count(".keyboardShortcut(") == 3


def test_every_tick_carries_its_click_out():
    # View > Row Size's Small, Medium and Large - and Shuffle, Repeat's three and the side panels' ticks with them - are
    # one Toggle: on its own words, ticked as MacMenu says, and its click the very perform the buttons' clicks are. A
    # setter that did nothing would leave every tick unclickable, the menu's ticks never moving.
    commands = bare(source(COMMANDS))
    menus = commands[commands.index("struct MacCommands: Commands {"):commands.index("final class TextEditing")]
    tick = flat(body(menus, "private func tick("))
    assert tick == ("private func tick(_ item: MacMenu.Item) -> some View { Toggle(item.words, isOn: Binding(get: "
                    "{ item.ticked }, set: { (_: Bool) -> Void in perform(item.command) })) "
                    ".keyboardShortcut(Self.shortcut(item.shortcut)) .disabled(!item.enabled) }"), tick
    # the one Toggle and the one Binding: every tick is tick()'s
    assert commands.count("Toggle(") == 1 and commands.count("Binding(") == 1
    # each tick drawn through it: Shuffle, Repeat's three, the panels, the three sizes
    view = flat(menus)
    assert "if each.command == .shuffle { tick(each) } else { button(each) }" in view
    assert "ForEach(repeats, id: \\.command) { (each: MacMenu.Item) in tick(each) }" in view
    assert "if each.command.panel != nil { tick(each) } else { button(each) }" in view
    assert "if each.command.rowSize != nil { tick(each) } else { button(each) }" in view
    # and each click reaches its own call: Shuffle's, Repeat's, a panel's, the size's (the store's, which keeps it -
    # test_row_size_is_kept_in_one_store - and Core's MacMenu.choose, which keeps the size chosen by name)
    perform = flat(menus[menus.index("private func perform("):menus.index("static func shortcut(")])
    for each in ("case .shuffle: player.toggleShuffle()",
                 "case .repeatOff, .repeatAll, .repeatOne: if let mode = command.repeatMode { player.setRepeat(mode) }",
                 "case .upNext, .lyrics, .info, .eq: if let panel = command.panel { navigation.togglePanel(panel) }",
                 "case .smallRows, .mediumRows, .largeRows, .biggerRows, .smallerRows: "
                 "MacRowSizeStore.shared.perform(command)"):
        assert each in perform, each
    # the click read again now, as it lands - dimmed, nothing
    assert perform.startswith("private func perform(_ command: MacMenu.Command) { let now = MacMenu.item(command, "
                              "state) guard now.enabled else { return } switch command {"), perform[:160]
    tests = (IOS / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "MacRowSizeTests.swift").read_text(encoding="utf-8")
    assert "func choosingASizeByNameKeepsThatSize()" in tests


def test_row_size_is_kept_in_one_store():
    # One store (MacRowSizeStore, as TextEditing and MacRefresh are the menus' other state): observed, so a change by
    # the menu, ⌘+, ⌘= or ⌘− redraws the menu's tick and every list at once - read where it is kept, and kept where it
    # is changed
    commands = bare(source(COMMANDS))
    store = flat(body(commands, "final class MacRowSizeStore {"))
    before = flat(commands[:commands.index("final class MacRowSizeStore {")])
    assert before.endswith("@MainActor @Observable "), before[-60:]
    for part in ("static let shared = MacRowSizeStore()",
                 "private(set) var size: MacRowSize",
                 "@ObservationIgnored private let defaults: UserDefaults",
                 # what this Mac kept, read as it opens: nothing, or a value this build doesn't know, reads as Small
                 "init(defaults: UserDefaults = .standard) { self.defaults = defaults "
                 "size = MacRowSize(saved: defaults.string(forKey: MacRowSize.storageKey)) }",
                 # a choice kept as it is made, and drawn; a step with no further to go does nothing
                 "func perform(_ command: MacMenu.Command) { guard let chosen = MacMenu.choose(command, saved: "
                 "defaults.string(forKey: MacRowSize.storageKey)) else { return } "
                 "defaults.set(chosen.keep, forKey: MacRowSize.storageKey) size = chosen.size }"):
        assert part in store, part
    # Core's rule: unknown reads as Small; a size by name keeps itself; a step from what was kept
    rule = flat(bare(core("MacRowSize.swift")))
    assert "MacRowSize(rawValue: raw) } ?? Self.standard" in rule
    menu = flat(bare(core("MacMenu.swift")))
    assert ("public static func choose(_ command: Command, saved: String?) -> (size: MacRowSize, keep: String)? { "
            "guard let to = rowSize(after: command, from: MacRowSize(saved: saved)) else { return nil } "
            "return (to, to.rawValue) }") in menu
    # the key is read and written here alone - no @AppStorage of it anywhere, no second copy of the size
    sources = {path.relative_to(APP).as_posix(): bare(path.read_text(encoding="utf-8"))
               for path in sorted(APP.rglob("*.swift"))}
    keyed = [name for name, code in sources.items() if "MacRowSize.storageKey" in code]
    assert keyed == [COMMANDS], keyed
    assert flat(sources[COMMANDS]).count("MacRowSize.storageKey") == 3
    assert not any("@AppStorage(MacRowSize" in code for code in sources.values())
    # the frame, the menus' state and perform, and the hidden key read it - nothing else
    readers = {name: code.count("MacRowSizeStore.shared") for name, code in sources.items()
               if "MacRowSizeStore.shared" in code}
    assert readers == {FRAME: 1, COMMANDS: 4}, readers


# ----------------------------------------------------------------------------- Large still fits

def test_large_still_fits_where_the_lists_fit_tests_measure():
    drawn = sizes()
    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    sidebar, dock = number(look, "sidebarWidth"), number(look, "panelWidth")
    column, smallest, web = number(frame, "columnMin"), number(frame, "smallestWidth"), number(frame, "panelWidth")
    opening = number(frame, "openingWidth")
    # the smallest window's page (880, the panel a drawer over it), a 1280 window's beside the dock R3 drew (400) and
    # beside the web's panel (470)
    pages = {"smallest": smallest - sidebar, "dock": column - sidebar - dock - 1, "narrowest": column - sidebar - web - 1}
    assert pages == {"smallest": 660, "dock": 659, "narrowest": 589}
    # Playlists: Playlist's least grows with the cover; every column at the smallest window and beside the dock
    facts = core("MacAlbumFacts.swift")
    assert "playlistLeast + size.coverGrowth" in facts
    assert "public var coverGrowth: Double { cover - Self.small.cover }" in core("MacRowSize.swift")
    rule = facts[facts.index("public static func playlistWidth("):facts.index("public static let playlistLeast")]
    fixed = {name: float(points) for name, points in re.findall(r"case \.(\w+): return \.fixed\((\d+)\)", rule)}
    every = sum(fixed.values())
    beside = sum(points for name, points in fixed.items() if name not in ("whose", "changed"))
    for size, drawn_at in drawn.items():
        least = number(facts, "playlistLeast") + drawn_at["cover"] - drawn["small"]["cover"]
        assert every + least <= pages["smallest"] and every + least <= pages["dock"], (size, every, least)
        assert beside + least <= pages["narrowest"], (size, beside, least)
    assert every + number(facts, "playlistLeast") + 20 == 658
    # Requests: the album's least grows with its cover; a window as it first opens scrolls nothing sideways at Large
    requests = core("RequestFilter.swift")
    assert "albumLeast + size.requestCoverGrowth" in requests
    columns = [float(n) for n in re.findall(r"\.fixed\((\d+)\),", requests[requests.index("public static let widths"):])[:5]]
    large = number(requests, "albumLeast") + drawn["large"]["cover"] - number(requests, "cover")
    assert sum(columns) + large == 1020 and sum(columns) + large <= opening - sidebar
    # and the table's own width reads it, so a narrower page scrolls rather than squeeze the album
    assert "return max(total, fixed + albumLeast(size))" in requests
