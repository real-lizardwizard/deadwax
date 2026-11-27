"""(25 Nov, after review) A readout beside words sits on their first text baseline.

Courier Prime's line is shorter than Libre Franklin's - 1.123 of an em to 1.212 - and its baseline nearer its centre
(0.22 of an em under it, to 0.36): Noto Sans Mono had Noto Sans's own metrics, so a row that centred the two set them on
one baseline, and with Courier Prime the same row sets the readout 1 to 2 points high (measured with a Catalyst
ImageRenderer: 2 px at 17 points in an HStack or a LabeledContent, 1 to 2 at 11.5 and 12). So every readout - the
readout face, `Typeface.readout` or a slice's `mono` - is followed from where its font is set, through the blocks it is
in (a branch, a group, a loop, a button's label, a helper's call), to what lays it out beside anything else:

- an HStack: set on the first (or last) text baseline - beside one line of words only, where a row centres a readout
  on a block of two lines as its drawing does (`line.isEmpty ? .firstTextBaseline : .center`);
- a LabeledContent: given the `.readout` style (Typeface.swift's ReadoutLabeledContentStyle), on it or on what holds it;
- a VStack, a section or a list: a line of its own;
- a stack every word of which is the readout's (`HStack { ... }.font(readout)`): nothing beside it to sit off.

The rest are said here one by one, with why (ALONE), and the Mac's tables are MacColumnList's row, checked below.
notes/ios.md, "The app's fonts: Libre Franklin and Courier Prime (2026-11-25)", has the measurements.
"""

import importlib.util
import re
from pathlib import Path


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_readout_rows_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


swift = _load("ios_swift")
fonts = _load("ios_fonts")
blocks_around, chain_end, code_only, opener_before = (swift.blocks_around, swift.chain_end, swift.code_only,
                                                      swift.opener_before)

REPO = Path(__file__).resolve().parents[1]
APP = REPO / "ios" / "App"

READOUT = re.compile(r"Typeface\.readout\(|Typeface\.(?:Mac|Phone|Look)\.mono\(")
BASELINE = re.compile(r"alignment:\s*[^,{]*\.(?:first|last)TextBaseline")
STYLED = ".labeledContentStyle(.readout)"
#? what lays nothing out: a branch, a group, a loop, a switch, a button's or a link's label, a timeline, a cell's
#? padding and width (MacRequestsPage's cell(_:alignment:content:)), a ViewThatFits's choice
PASS_THROUGH = re.compile(r"^(?:\}\s*)?(?:if\b|else\b|Group\b|ForEach\b|switch\b|Button\b|NavigationLink\b|label:|"
                          r"TimelineView\b|cell\(|ViewThatFits\b)")
HSTACK = re.compile(r"^(?:return\s+)?(?:Lazy)?HStack\b")
LINES = re.compile(r"^(?:return\s+)?(?:(?:Lazy)?VStack\b|Section\b|Form\b|List\b)")
LABELED = re.compile(r"^(?:return\s+)?LabeledContent\b")
FUNC = re.compile(r"\bfunc (\w+)\s*[(<]")
VIEW_VAR = re.compile(r"\bvar (\w+): some View$")
STRUCT = re.compile(r"\bstruct (\w+)\b")
TABLE = re.compile(r"^(?:return\s+)?MacColumnList\b")

#? The readouts with nothing beside them on a line, or set as their drawings set them - (file, the code that sets the
#? font, why). The code is the readout's own place: it must still be there, span the readout, and the readout still be
#? none of the cases above.
ALONE = [
    ("EQ/EQCurveView.swift",
     "private var labelFont: Font { well ? Typeface.Phone.mono(.extraSmall) : Typeface.caption2 }",
     "the curve's axis: a row of its labels only, each in that font"),
    ("EQ/EQSliders.swift",
     "static var labelFont: Font { phone ? Typeface.Phone.mono(.extraSmall) : Typeface.caption2 }",
     "the bands' frequencies, each alone under its slider"),
    ("EQ/EQSliders.swift",
     ".font(EQSliders.phone ? Typeface.Phone.mono(.extraSmall).weight(.semibold)\n"
     "                                          : Typeface.readout(.caption).weight(.semibold))",
     "a held slider's value, alone on its chip over the knob"),
    ("Look/DWChip.swift", "Text(count)\n            .font(Typeface.Look.mono(.count).weight(.semibold))",
     "a count's badge: a box of its own, centred in its row as .count is"),
    ("Player/MiniPlayerView.swift", "Text(words)\n            .font(Typeface.Phone.mono(.extraSmall))",
     "the time over the finger: a tag of its own above the held line"),
    ("Requests/RequestCards.swift", "DisclosureGroup {\n                    Text(detail)\n"
                                    "                        .font(Typeface.Phone.mono(.extraSmall))",
     "a disclosure's detail, a line of its own"),
    ("UpNext/UpNextScreen.swift", "Text(AboutCard.trackTime(playing.duration))\n                .font(Typeface.Phone.mono(.small))",
     "the song playing's length, centred on its cover and two lines as iQueue draws it"),
    ("UpNext/UpNextScreen.swift", ".font(Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.mono(.extraSmall))",
     "the time left on the phone, beside the Shuffle and Repeat buttons' boxes, centred on them as iQueue draws it"),
    # (R9) on the Mac an address typed in its well beside Check's faced button: two boxes, centred on each other as
    # SignIn draws them - the words inside each box centred in it. (R9's review) The phone's Check is flat words, no box:
    # it sits on the address's first text baseline (SignInView, ServerAddressView), so neither is said here
    ("Mac/Settings/MacSignIn.swift", ".onSubmit { check() }\n                        .font(Typeface.Mac.mono(.base))",
     "the address typed in its well, beside Check's button (SignIn's Where deadwax is)"),
    ("Mac/Settings/MacSignIn.swift", "Text(server.address?.description ?? \"\")\n                .font(Typeface.Mac.mono(.small))",
     "over the app, the address in use said alone in Where deadwax is: nothing beside it"),
    # (R10) Edit album's Release on the Mac: the search and the years typed in their wells - each box centred on its
    # label as DWFieldRow lays every field, and the search's on Find releases' faced button (Main.dc.html's .fr), the
    # words inside each box centred in it, as R9's address beside Check
    ("Mac/Edit/MacReleaseTab.swift", "input.font(Typeface.Mac.mono(.label))",
     "the search and the years typed in their wells, beside their labels and Find releases' button"),
    # (R10's review) Edit album's Release on the phone: the years typed in their wells (iEdit's `.in.mono`), each well
    # centred on its label in the field's row and the words centred in the well, as the Mac's above
    ("Edit/ReleasePage.swift", "content.font(Typeface.Look.mono(.field))",
     "the years typed in their wells, beside their labels in Release's Fields"),
    # (R14) a setting's field: the modifier's font, on SettingControl's TextField and SecureField, each the control's
    # whole line at the top of SettingCard's and MacSettingBox's VStacks
    ("Manage/ServerSettingsGroupScreen.swift", "            .textFieldStyle(.plain)\n            .font(Typeface.Look.mono(.field))",
     "a setting's field in its own well (SettingWell): a line of its own in its card's or box's VStack"),
    # (R14) Remove a person's typed name: PeopleSheetPage sets its parts down a VStack, the field one of them
    ("Manage/PeopleSheets.swift", "TextField(People.typeTheName, text: people.typing(\\.removeTyped, at: .remove(id)))\n"
                                  "                    .font(Typeface.Look.mono(.field))",
     "the name typed to remove someone, in its own box: a line of its own in PeopleSheetPage's VStack"),
    # (R14) a Mac setting box's legend on its edge (.legend.mono), as the drawing sets it
    ("Mac/Manage/MacServerSettingsPage.swift", "Text(setting.key)\n                .font(Typeface.Mac.mono(.label).weight(.bold))",
     "a setting box's name on its top edge: an overlay of its own, nothing beside it"),
    # (R11) the Mac's Tags: the track and disc numbers and the years typed in their wells, each box centred on its label
    # as DWFieldRow lays every field, the words inside it centred in it - as Release's years above
    ("Mac/Edit/MacTagsTab.swift", "input.font(Typeface.Mac.mono(.label))",
     "the numbers and the years typed in their wells, beside their labels in the Tags editor"),
    # (R11) a track's page on the phone: the file's name, the last line of its every-tag group (PhoneGroup stacks its
    # rows), nothing beside it
    ("Edit/TagsPages.swift", "Text(file.filename)\n                .font(Typeface.Phone.mono(.extraSmall))",
     "the file's name, a line of its own under every tag in the track's page"),
    # (R11) the phone's faces handed to TagFileChanges (both devices' preview): each readout in it a line of its own in
    # its VStacks - the file's name, what a tag says now and what it would say
    ("Edit/TagsPages.swift",
     "self.init(file: file, mono: Typeface.Phone.mono(.extraSmall), words: Typeface.Phone.text(.small))",
     "a file's changes in Edit tags' preview, each readout a line of its own in TagFileChanges' VStacks"),
    # (R18) the sheets' readout face, defined once (SheetLook): read at Choose the folder's path, the last line of
    # FolderRow's VStack, and Can't reach deadwax's address, a line of its own down UnreachableView's VStack - nothing
    # beside either
    ("Shared/SheetLook.swift",
     "static var mono: Font { Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small) }",
     "the folder's path and the address unreached, each a line of its own in a VStack"),
]


def walk(code: str, at: int, labeled: bool, seen: set) -> list[str]:
    """Why the readout at `at` isn't on its neighbours' baseline - nothing, if it is. `labeled`: inside a LabeledContent,
    looking up for its style."""
    for head, _, close in blocks_around(code, at):
        after = code[close + 1:chain_end(code, close + 1)]
        if labeled:
            if STYLED in after:
                return []
        elif LABELED.match(head):
            if STYLED in after:
                return []
            labeled = True
        elif PASS_THROUGH.match(head):
            continue
        elif HSTACK.match(head):
            return [] if BASELINE.search(head) else [f"centred in {head}"]
        elif LINES.match(head):
            return []
        elif head == "layout":
            made = re.search(r"let layout = [^\n]*\n[^\n]*", code[:at][-2000:])
            return [] if made and BASELINE.search(made.group(0).replace("HStackLayout(", "HStack(")) else ["layout"]
        elif TABLE.match(head):
            # a Mac table's cell: MacColumnList lays its row out (test_the_macs_tables_and_status_bar_are_set_on_one_baseline)
            return []
        helper, view = FUNC.search(head), VIEW_VAR.search(head)
        if helper:
            return follow(code, helper.group(1), "call", labeled, seen)
        if view and view.group(1) != "body":
            return follow(code, view.group(1), "statement", labeled, seen)
        if view:
            # a view's body: on to where the view is made, in this file
            continue
        made = STRUCT.search(head)
        if made:
            return follow(code, made.group(1), "made", labeled, seen)
        if not labeled:
            return [f"in {head}"]
    return ["at the file's top"]


def follow(code: str, name: str, how: str, labeled: bool, seen: set) -> list[str]:
    """On from a helper (`call`), a view property (`statement`) or a view (`made`) to each place this file uses it."""
    if name in seen:
        return []
    seen = seen | {name}
    if how == "statement":
        uses = [m.start(1) for m in re.finditer(rf"(?m)^\s*({name})\s*(?:$|\.)", code)]
    else:
        defined = "struct " if how == "made" else "func "
        uses = [m.start() for m in re.finditer(rf"(?<![\w.]){name}\s*[(<]", code)
                if not code[:m.start()].endswith(defined)]
    if not uses:
        return [f"{name} is used nowhere in its file"]
    why = []
    for use in uses:
        why += walk(code, use, labeled, seen)
    return why


def readouts():
    """Every readout's font in the app: (file, its text, its code, where, the line it is on)."""
    for path in sorted(APP.rglob("*.swift")):
        name = str(path.relative_to(APP))
        if name == "Shared/Typeface.swift":
            continue
        text = path.read_text(encoding="utf-8")
        code = code_only(text)
        for found in READOUT.finditer(code):
            start = code.rfind("\n", 0, found.start()) + 1
            end = code.find("\n", found.start())
            yield name, text, code, found.start(), text[start:end].strip()


def said_alone(name: str, text: str, at: int) -> list[tuple[str, str]]:
    """The ALONE entries whose code spans the readout at `at`."""
    spans = []
    for file, place, _ in ALONE:
        if file != name:
            continue
        for found in re.finditer(re.escape(place), text):
            if found.start() <= at < found.end():
                spans.append((file, place))
    return spans


def whole_row_in_readout(code: str, at: int) -> bool:
    """The readout is `.font(...)` on a stack whose every word takes it: nothing in it beside it."""
    call = opener_before(code, at, "(")
    if call < 0 or not code[:call].rstrip().endswith(".font"):
        return False
    before = code[:call].rstrip()[:-len(".font")].rstrip()
    if not before.endswith("}"):
        return False
    depth, i = 0, len(before) - 1
    while i >= 0:
        depth += {"}": 1, "{": -1}.get(before[i], 0)
        if depth == 0:
            break
        i -= 1
    head = before[max(before.rfind("\n", 0, i), 0):i].strip()
    inside = before[i:]
    return bool(re.match(r"^(?:return\s+)?[HV]Stack\b", head)) and ".font(" not in inside


def test_every_readout_beside_words_sits_on_their_baseline():
    unexplained, explained, checked = [], set(), 0
    for name, text, code, at, line in readouts():
        checked += 1
        if whole_row_in_readout(code, at):
            continue
        why = walk(code, at, False, set())
        if not why:
            continue
        alone = said_alone(name, text, at)
        if alone:
            explained.update(alone)
            continue
        unexplained.append(f"{name}: {line} - {'; '.join(why)}")
    assert not unexplained, "\n".join(unexplained)
    # nothing said alone that is gone, or is on a baseline after all
    assert explained == {(file, place) for file, place, _ in ALONE}, {(f, p) for f, p, _ in ALONE} - explained
    # every readout in the app went through it (the Mac's tables, the EQ, Info, Debug, the bars...)
    assert checked > 60, checked


def test_the_walk_finds_a_centred_row():
    # the rule, rehearsed: a readout centred beside words is found, through a branch and a helper; on the baseline, not
    code = code_only("struct A: View {\n    var body: some View {\n        HStack(spacing: 4) {\n"
                     "            Text(\"a\")\n            stamp\n        }\n    }\n"
                     "    private var stamp: some View {\n        Group {\n            if on {\n"
                     "                Text(\"1\").font(Typeface.readout(.body))\n            }\n        }\n    }\n}\n")
    at = code.index("Typeface.readout(")
    assert walk(code, at, False, set()) == ["centred in HStack(spacing: 4)"]
    fixed = code.replace("HStack(spacing: 4)", "HStack(alignment: .firstTextBaseline, spacing: 4)")
    assert walk(fixed, at + len("alignment: .firstTextBaseline, "), False, set()) == []
    labeled = code_only("struct B: View {\n    var body: some View {\n        Form {\n"
                        "            LabeledContent(\"a\") {\n                Text(\"1\").font(Typeface.readout(.body))\n"
                        "            }\n        }\n    }\n}\n")
    at = labeled.index("Typeface.readout(")
    assert walk(labeled, at, False, set())
    styled = labeled.replace("        }\n    }\n}\n", "        }\n        .labeledContentStyle(.readout)\n    }\n}\n")
    assert walk(styled, styled.index("Typeface.readout("), False, set()) == []


def test_the_macs_tables_and_status_bar_are_set_on_one_baseline():
    # the Mac's tables: every cell of MacColumnList's row (Albums, Artists, Playlists, an album, a playlist) and of
    # Requests' own on one first text baseline, a cover centred on its title as before; Requests' meter centred on the
    # row's words; the status bar's facts on one, its dividers centred on the words' line
    table = code_only((APP / "Mac" / "Components" / "MacColumnList.swift").read_text(encoding="utf-8"))
    row = table[table.index("private func line(_ row: Row, striped: Bool, widths: [Double]) -> some View {"):]
    assert row[:row.index("ForEach(")].count("return HStack(alignment: .firstTextBaseline, spacing: 0) {") == 1
    requests = code_only((APP / "Mac" / "Requests" / "MacRequestsPage.swift").read_text(encoding="utf-8"))
    line = requests[requests.index("private func rowLine(_ row: RequestRow, widths: [CGFloat], striped: Bool)"):]
    assert "return HStack(alignment: .firstTextBaseline, spacing: 0) {" in line[:line.index("cell(widths[0])")]
    progress = requests[requests.index("@ViewBuilder private func progressCell(_ row: RequestRow)"):]
    progress = progress[:progress.index("case .waiting:")]
    assert "HStack(alignment: .firstTextBaseline, spacing: 8) {" in progress
    assert ".frame(minWidth: CGFloat(RequestColumns.meterLeast))" in progress
    assert ".centredOnWords(CGFloat(Typeface.Mac.Size.base.rawValue))" in progress
    bar = code_only((APP / "Mac" / "Components" / "MacStatusBar.swift").read_text(encoding="utf-8"))
    assert "HStack(alignment: .firstTextBaseline, spacing: 0) {\n            facts(items.leading)" in bar
    assert ".frame(height: 14)\n                    .centredOnWords(CGFloat(Typeface.Mac.Size.label.rawValue))" in bar
    # the walk reaches every cell through the page's cell(...) and MacColumnList's closure: these are its pages
    pages = sorted(str(path.relative_to(APP)) for path in APP.rglob("*.swift") if "MacColumnList(" in path.read_text(
        encoding="utf-8") and path.name != "MacColumnList.swift")
    assert pages == ["Mac/Album/MacAlbumPage.swift", "Mac/Album/MacPlaylistPage.swift", "Mac/Artist/MacArtistPage.swift",
                     # (R10) Edit album's folder list
                     "Mac/Edit/MacFolderList.swift",
                     # (R11) Edit album's Tags, its tracks
                     "Mac/Edit/MacTagsTab.swift",
                     "Mac/Library/MacAlbumsPage.swift", "Mac/Library/MacArtistsPage.swift",
                     "Mac/Library/MacPlaylistsPage.swift",
                     # (R12) Needs a look's queue
                     "Mac/Manage/MacNeedsALook.swift",
                     # (R14) People's list
                     "Mac/Manage/MacPeoplePage.swift",
                     # (R7) Get's tracklist
                     "Mac/Search/MacGetPage.swift",
                     # (R9) Downloaded's albums and playlists
                     "Mac/Settings/MacDownloadedPage.swift"]
    # (R7) Search's table draws its own row (MacSearchRow): its cells on one first text baseline too
    search = code_only((APP / "Mac" / "Search" / "MacSearchPage.swift").read_text(encoding="utf-8"))
    row = search[search.index("struct MacSearchRow<Name: View>: View {"):]
    assert row[:row.index("ForEach(columns")].count("HStack(alignment: .firstTextBaseline, spacing: 0) {") == 1


#? the covers a Mac table's cell draws (Row Size grows them: 20, 28, 40; Requests' 22, 28, 40)
COVERS = re.compile(r"\b(?:LibraryCover|ArtistPicture|PlaylistCover|ArchiveCover|CoverImage|FolderCover)\(")
#? where each page builds its cells
CELL_BUILDERS = {"Mac/Library/MacAlbumsPage.swift": "private func cell(", "Mac/Library/MacArtistsPage.swift":
                 "private func cell(", "Mac/Library/MacPlaylistsPage.swift": "private func cell(",
                 "Mac/Album/MacAlbumPage.swift": "private func cell(", "Mac/Album/MacPlaylistPage.swift":
                 "private func cell(", "Mac/Requests/MacRequestsPage.swift": "private func albumCell(",
                 # (R9) Downloaded's album cell (its playlist cell, the same, is test_ios_settings_look's)
                 "Mac/Settings/MacDownloadedPage.swift": "private func cell(_ row: AlbumRow",
                 # (R12's review) Needs a look's album cell: the folder's cover beside the title and its chips
                 "Mac/Manage/MacNeedsALook.swift": "private func cell("}


def test_a_tables_cover_rides_on_its_title():
    # (Rebased onto the Mac's Row Size, 25 Nov) A piece with no words of its own in a row set on the first text
    # baseline stands its foot on it, so a cover in a cell of its own would sit high in the row - more the taller Row
    # Size makes it. Each one is beside its title in a centred stack instead: the cell's baseline is the title's, the
    # cover centred on its line, and the row's words in its middle at Small, Medium and Large (measured, a Catalyst
    # ImageRenderer at 2x: Albums' and Requests' words and cover exactly where a centred row has them at all three).
    # A song's ▶ and its ••• (SharpSymbol's and the menu's SF Symbols) report a text baseline of their own and ride it,
    # as near the words as the centred row had them.
    covers = 0
    for name, builder in CELL_BUILDERS.items():
        code = code_only((APP / name).read_text(encoding="utf-8"))
        start = code.index(builder)
        brace = code.index("{", start)
        cells = code[start:swift.closer(code, brace) + 1]
        for found in COVERS.finditer(cells):
            covers += 1
            head, opened, closed = blocks_around(cells, found.start())[0]
            # its spacing a number or a look's constant (Needs a look's MacNeedsLookLook.gap)
            assert re.match(r"HStack\(spacing: (?:\d+|\w+\.\w+)\)$", head), (name, head)
            assert "Text(" in cells[opened:closed], (name, "a cover with no title beside it")
        if "MacAlbumPage" in name or "MacPlaylistPage" in name:
            assert "SharpSymbol(.play)" in cells, name
        if "MacAlbumPage" in name:
            assert 'Image(systemName: "ellipsis")' in (APP / name).read_text(encoding="utf-8")
            assert "QueueMenu(request: desk.row(song, album)) { Image(systemName: " in re.sub(r"\s+", " ", cells)
    assert covers == 6, covers  # (R9) Downloaded's album cover the fifth, (R12) Needs a look's the sixth
    # the rehearsal: a cover alone in its cell, and a cover in a stack on the foot, are each seen
    alone = "func cell() -> some View { switch column { case 0: LibraryCover(id: x) default: Text(y) } }"
    head = blocks_around(alone, alone.index("LibraryCover("))[0][0]
    assert not re.match(r"HStack\(spacing: \d+\)$", head)
    footed = "func cell() -> some View { HStack(alignment: .bottom, spacing: 8) { LibraryCover(id: x) Text(y) } }"
    assert not re.match(r"HStack\(spacing: \d+\)$", blocks_around(footed, footed.index("LibraryCover("))[0][0])


def test_a_piece_without_words_is_centred_on_the_words_line():
    # centredOnWords lifts a divider or a meter from the baseline by Libre Franklin's baseline-under-centre - 0.36 of
    # an em, the font's own ascender and descender (test_ios_palette.py's fonts) - so it is where the centred row had it
    source = (APP / "Shared" / "Typeface.swift").read_text(encoding="utf-8")
    assert "static let wordsBaselineUnderCentre: CGFloat = 0.36" in source
    assert ("alignmentGuide(.firstTextBaseline) { (piece: ViewDimensions) -> CGFloat in\n"
            "            piece[VerticalAlignment.center] + size * Typeface.wordsBaselineUnderCentre") in source
    ascender, descender, gap = fonts.vertical("LibreFranklin-Regular")
    assert gap == 0 and round((ascender + descender) / 2, 4) == 0.36
    # the style: label and value on the first text baseline, the value under the label where they don't fit side by side
    style = source[source.index("struct ReadoutLabeledContentStyle: LabeledContentStyle {"):]
    style = style[:style.index("\n}\n")]
    assert "ViewThatFits(in: .horizontal) {\n            HStack(alignment: .firstTextBaseline, spacing: 8) {" in style
    assert "VStack(alignment: .leading, spacing: 2) {" in style and ".accessibilityElement(children: .combine)" in style
    assert "static var readout: ReadoutLabeledContentStyle { ReadoutLabeledContentStyle() }" in source
