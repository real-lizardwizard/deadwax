"""
The panel review's sheets, faces and banners in the redesign's look (slice R18 - notes/ios.md "The panel review, R18:
sheets, faces and banners (2026-11-26)"; panel-review.md M11-M16, P2, P4-P9). No drawing has these, so each is drawn from
the canvas's pieces (James's answer 4): flat on the phone, the Mac's boxes on the Mac.

The app's Swift read as text, as the other look tests read it:

- The phone is flat (R1c): no List but Edit order's (its drag handles), no Form, no material, no grey cell - Add to a
  playlist's rows on their hairlines (the Mac's in a `.box`), Downloaded playlists' rows on the page, Choose the folder's
  folders down the page, the Navidrome gate and Can't reach deadwax in the look's words.
- New playlist's name is on the look's well on both devices (R1c's typing rule, test_ios_phone_look's TEXT_INPUTS).
- Add to a playlist offers only the playlists you can edit, as it did: Core's PlaylistRules.picker, the one list drawn.
- Every PrimaryFace, SecondaryPill and `.bordered` in these files is the look's button - the purple, or flat words.
- The notice, the offline banner and Edit album's out-of-reach line: no material, a DWPalette ground with a hairline,
  never over another control's target - the notice takes no touch and sits 8 above the tab bar at any size (worked out
  here from MainTabs' placing and Core's TabBarFoot), the banners are safe-area insets with Try again's reach inside.
- The cover viewer's close: a bare glyph on the phone in a 44 target, the Mac's round key on the Mac.
- Tokens only; "Queue", never "Up Next".
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_sheets_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
settings_look = _load("test_ios_settings_look")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def kept(text: str) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def code(name: str) -> str:
    return kept((APP / name).read_text(encoding="utf-8"))


def core(name: str) -> str:
    return kept((CORE / name).read_text(encoding="utf-8"))


def struct(text: str, name: str) -> str:
    return settings_look.struct(text, name)


def declaration(text: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = text.index(start)
    opened = text.index("{", at)
    return text[at:reader.closing(text, opened) + 1]


PICKER = "Playlists/PlaylistPicker.swift"
PLAYLISTS = "Playlists/PlaylistsScreen.swift"
MAC_PLAYLISTS = "Mac/Library/MacPlaylistsPage.swift"
FOLDER = "Edit/ChooseFolderView.swift"
LIBRARY = "Library/LibraryView.swift"
ALBUMS = "Library/AlbumsScreen.swift"
SONGS = "Library/SongsScreen.swift"
MINE = "Album/MineBlock.swift"
UNREACHABLE = "Root/UnreachableView.swift"
NOTICE = "Shared/Notice.swift"
BANNER = "Root/OfflineBanner.swift"
EDIT = "Edit/EditAlbumSheet.swift"
COVER = "Player/CoverViewer.swift"
SHEET = "Shared/SheetLook.swift"

#? the parts this slice drew in files other slices drew before it (R2's Library and Playlists pages, R10's Edit album,
#? the cover viewer): each struct, or for Edit album its out-of-reach line alone
PARTS = {
    LIBRARY: ["EditOrderSheet", "NavidromeGateView"],
    ALBUMS: ["FirstAskCard", "EmptyLibraryNote", "PlaceGroup", "PlaceRow"],
    PLAYLISTS: ["DownloadedPlaylistsScreen", "PlaylistRow"],
    COVER: ["CoverCloseButton", "CoverCloseKey"],
}


def parts() -> dict[str, str]:
    """Every view this slice drew, as code alone: R18's own files whole, and the parts of the others it redrew."""
    found = {name: bare((APP / name).read_text(encoding="utf-8")) for name in sorted(phone_look.R18_PAGES - {COVER})}
    for name, views in PARTS.items():
        source = bare((APP / name).read_text(encoding="utf-8"))
        for view in views:
            found[f"{name}:{view}"] = struct(source, view)
    edit = bare((APP / EDIT).read_text(encoding="utf-8"))
    found[f"{EDIT}:editOutOfReach"] = declaration(edit, "func editOutOfReach(")
    songs = bare((APP / SONGS).read_text(encoding="utf-8"))
    found[f"{SONGS}:shuffleButton"] = declaration(songs, "@ViewBuilder private var shuffleButton")
    return found


# ----------------------------------------------------------------------------- the phone is flat

#? everything R18 draws on the phone's path with a fill, a face, an edge or a rule (R1c's DRAWS): a row's hairline
#? (SheetRows' rows, Choose the folder's, the gate's place row), the new name's well, the notice's black inside the line's
#? edge, the banner's black and its amber hairline - and the empty cover's square, a picture's (as the Library's rows
#? draw it). No grey box: a row is its words on the page.
R18_DRAWS = {
    PICKER: ["ZStack: Palette.coverEmpty", "DWWell: focused: focused"],
    FOLDER: ["DWRule: colour: SheetLook.rule"],
    NOTICE: ["background: DWPalette.card, DWPalette.page", "strokeBorder: DWPalette.line"],
    BANNER: ["fill: DWPalette.page", "fill: DWPalette.amberEdge"],
    SHEET: ["DWRule: colour: SheetLook.rule"],
    f"{ALBUMS}:PlaceRow": ["DWRule: colour: SheetLook.rule"],
}
#? the system's greys and faces, gone from every part (a List kept only for Edit order's drag handles, plain)
GREYS = ("Form {", ".insetGrouped", ".listStyle(.grouped", ".listStyle(.inset", "Material", ".background(.bar",
         "fill(.bar", "PrimaryFace", "SecondaryPill", ".buttonStyle(.bordered", ".buttonStyle(.borderless",
         "ContentUnavailableView", "LabeledContent(", "Section {")


def test_the_sheets_on_the_phone_are_flat():
    found = {}
    for name, part in parts().items():
        draws = phone_look.drawn(phone_look.phone_path(part))
        if draws:
            found[name] = draws
    assert found == R18_DRAWS, found
    for name, part in parts().items():
        for grey in GREYS:
            assert grey not in part, f"{name}: {grey}"
        if name != f"{LIBRARY}:EditOrderSheet":
            assert not re.search(r"\bList\s*[({]", part), name
    # Edit order's List is plain on the page's own ground - only a List in edit mode gives its rows their handles
    order = flat(parts()[f"{LIBRARY}:EditOrderSheet"])
    assert ".listStyle(.plain) .scrollContentBackground(.hidden) .background(SheetLook.ground)" in order
    assert order.count(".listRowBackground(SheetLook.ground)") == 2 and ".listRowSeparatorTint(SheetLook.rule)" in order
    assert ".presentationBackground(SheetLook.ground)" in order
    # the matcher sees a grey given back to a sheet's rows on the phone
    rows = struct(bare(code(SHEET)), "SheetRows")
    _, phone = phone_look.halves(rows, "if Platform.mac {")
    planted = flat(rows).replace(phone, phone.replace(".frame(maxWidth: .infinity, alignment: .leading)",
                                                      ".background(DWPalette.card) .frame(maxWidth: .infinity, "
                                                      "alignment: .leading)", 1), 1)
    assert "background: DWPalette.card" in phone_look.drawn(phone_look.phone_path(planted))
    # every sheet's page the page's own black on the phone, the Mac's window ground - behind its bar too
    sheet = code(SHEET)
    assert "static var ground: Color { Platform.mac ? DWPalette.bg : DWPalette.page }" in sheet
    page = flat(struct(bare(sheet), "SheetPage"))
    assert "ScrollView { VStack(alignment: .leading, spacing: SheetLook.gap) { content }" in page
    assert ".background(SheetLook.ground.ignoresSafeArea())" in page
    for name, count in ((PICKER, 2), (LIBRARY, 1)):
        assert code(name).count(".presentationBackground(SheetLook.ground)") == count, name
    # the phone's sheet rows on their hairlines, at the page's edge; the Mac's in a `.box`
    mac, phone = phone_look.halves(rows, "if Platform.mac {")
    assert ".background(DWPalette.card, in: DWCorners.boxShape)" in mac
    assert ".overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))" in mac
    assert phone == " VStack(spacing: 0) { content } .frame(maxWidth: .infinity, alignment: .leading) ", phone
    row = flat(declaration(bare(sheet), "func sheetRow()"))
    assert ("padding(.horizontal, Platform.mac ? 10 : 0) .frame(maxWidth: .infinity, minHeight: SheetLook.rowHeight, "
            "alignment: .leading) .overlay(alignment: .bottom) { DWRule(colour: SheetLook.rule) }") in row
    assert "static var rule: Color { Platform.mac ? DWPalette.rowline : DWPalette.rowRule }" in sheet
    assert "static var rowHeight: CGFloat { CGFloat(DWLook.here.rowHeight) }" in sheet


def test_add_to_a_playlist_is_rows_on_hairlines_and_the_macs_box():
    picker = bare(code(PICKER))
    body = flat(struct(picker, "PlaylistPicker"))
    assert "NavigationStack { SheetPage {" in body and "List {" not in body
    section = flat(declaration(picker, "@ViewBuilder private func listSection("))
    assert section.count("SheetRows {") == 1
    assert ".padding(.vertical, SheetLook.gap) .sheetRow()" in section
    # each row the phone's Library row (iArtists': its cover, its two lines, its hairline), the Mac's a box row
    row = struct(picker, "PickerRow")
    mac, phone = phone_look.halves(row, "if Platform.mac {")
    assert phone.startswith(" LibraryListRow(title: name, line: line ?? \"\", lines: typeSize.isAccessibilitySize ? 2 : 1) "
                            "{ mark(side: LibraryLook.rowCover) }"), phone
    assert "mark(side: SheetLook.macCover)" in mac and ".font(SheetLook.words) .sheetRow() .help(name)" in mac
    assert "static let macCover: CGFloat = 20" in code(SHEET)
    # VoiceOver hears a row as one: its name and its line
    assert ('.accessibilityElement(children: .ignore) .accessibilityLabel([name, line].compactMap { $0 }'
            '.joined(separator: ", "))') in flat(struct(code(PICKER), "PickerRow"))
    # the question's two buttons the look's: Yes the purple, No flat - across the page at the accessibility sizes
    question = flat(declaration(picker, "private func questionSection("))
    assert "SheetButtons { (stacked: Bool) in" in question
    assert ".buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))" in question
    assert ".buttonStyle(DWButtonStyle(fills: stacked))" in question
    # Try again the look's button
    assert "Button(PlaylistWords.tryAgain) { Task { await playlists.ask(fresh: true) } } .buttonStyle(DWButtonStyle())" in section
    # SheetButtons: side by side, one over the other at the accessibility sizes
    buttons = flat(struct(bare(code(SHEET)), "SheetButtons"))
    assert ("let stacked = typeSize.isAccessibilitySize if stacked { VStack(alignment: .leading, spacing: 10) { "
            "content(true) } } else { HStack(spacing: 12) { content(false) } }") in buttons
    words = flat(struct(bare(code(SHEET)), "SheetButtonWords"))
    assert ".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)" in words


def test_add_to_a_playlist_offers_only_the_playlists_you_can_edit():
    picker = bare(code(PICKER))
    body = flat(struct(picker, "PlaylistPicker"))
    assert "let rows = playlists.list.map(PlaylistRules.picker) ?? []" in body
    assert "listSection(rows)" in body
    section = flat(declaration(picker, "@ViewBuilder private func listSection("))
    # the one list of playlists drawn is `rows`, the picker's
    assert re.findall(r"ForEach\((\w+(?:\.\w+)*(?: \?\? \[\])?)\)", section) == ["rows"], section
    assert "playlists.list ?? []" not in section and "ForEach(playlists" not in section
    # and Core's rule: yours, and editable - as it was
    rule = flat(core("PlaylistChanges.swift"))
    assert ("public static func picker(_ list: [Playlist]) -> [Playlist] { let yours = list.enumerated().filter { "
            "(_: Int, playlist: Playlist) -> Bool in playlist.mine && playlist.editable }") in rule
    # and the Escape guards as they were: no new name thrown away by Escape
    assert ".escapeCloses(!(model.making && nameTyped))" in body
    fields = flat(struct(picker, "NewPlaylistFields"))
    assert ".escapeCloses(escapes && blank)" in fields


def test_the_new_playlists_name_is_on_the_looks_well_on_both_devices():
    picker = bare(code(PICKER))
    fields = struct(picker, "NewPlaylistFields")
    assert "Platform.mac" not in fields, "one field for both devices"
    field = flat(fields[fields.index("TextField("):fields.index("if let failure")])
    for part in (".textFieldStyle(.plain)", ".font(Typeface.Look.text(.field))", ".foregroundStyle(DWPalette.fieldText)",
                 ".focusEffectDisabled()", ".padding(.horizontal, 8)", ".lookHeight(DWLook.here.fieldHeight)",
                 ".background { DWWell(focused: focused) .contentShape(DWTarget(face: DWCorners.buttonShape)) "
                 ".onTapGesture { focused = true } }"):
        assert part in field, part
    assert "prompt: Text(PlaylistWords.nameField).foregroundStyle(DWPalette.t3)" in field
    # R1c's typing test reads it as the look's well
    assert phone_look.TEXT_INPUTS[PICKER] == [phone_look.WELL]
    files = phone_look.typing_files()
    assert [phone_look.box_of(dress, holders) for _, dress, holders in phone_look.boxes(files, PICKER)] == [
        phone_look.WELL]
    # Create the purple, Cancel flat - each across the row at the accessibility sizes
    assert ".buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))" in flat(fields)
    assert ".buttonStyle(DWButtonStyle(fills: stacked))" in flat(fields)
    # the Playlists pages' New playlist sheets the same fields on the sheet's own page, no List - the phone's and the Mac's
    for name in (PLAYLISTS, MAC_PLAYLISTS):
        page = flat(bare(code(name)))
        assert "NewPlaylistSheet { NewPlaylistFields(escapes: true) {" in page, name
        assert "List { NewPlaylistFields" not in page, name
        assert page.count(".macSheet()") >= 1, name
    sheet = flat(struct(picker, "NewPlaylistSheet"))
    assert ("NavigationStack { SheetPage { fields } .navigationTitle(PlaylistWords.newPlaylistTitle) "
            ".navigationBarTitleDisplayMode(.inline) } .presentationBackground(SheetLook.ground)") in sheet
    # the Playlists page's empty state: New playlist the look's flat button, its words the look's
    playlists = flat(bare(code(PLAYLISTS)))
    assert "SecondaryPill" not in playlists and playlists.count(".buttonStyle(DWButtonStyle())") >= 2


def test_downloaded_playlists_and_choose_the_folder_are_down_the_page():
    downloaded = flat(struct(bare(code(PLAYLISTS)), "DownloadedPlaylistsScreen"))
    assert "ScrollView { LazyVStack(alignment: .leading, spacing: 0) {" in downloaded
    assert ".padding(.horizontal, SheetLook.side)" in downloaded
    assert ".foregroundStyle(DWPalette.t2)" in downloaded and "Palette.quiet" not in downloaded
    row = flat(struct(bare(code(PLAYLISTS)), "PlaylistRow"))
    assert "inList" not in row and "LibraryListRow(title: playlist.name," in row and "LibraryChevron()" in row
    assert ".buttonStyle(.plain)" in row
    folder = bare(code(FOLDER))
    view = flat(struct(folder, "ChooseFolderView"))
    assert "ScrollView { LazyVStack(alignment: .leading, spacing: 0) {" in view
    assert ".padding(.horizontal, SheetLook.side)" in view and ".background(SheetLook.ground)" in view
    # what was typed in iOS's own search field in the bar, as before - its own box (R1c's typing test: iOS's)
    assert ".searchable(text: $typed, placement: .navigationBarDrawer(displayMode: .always)" in view
    assert phone_look.TEXT_INPUTS[FOLDER] == [phone_look.SYSTEM]
    # the count over the folders in the small greys, a problem in the amber's words
    assert ".font(SheetLook.small) .foregroundStyle(DWPalette.amberText)" in view
    assert ".font(SheetLook.small) .foregroundStyle(DWPalette.t2)" in view
    # each folder a row on its hairline: the album, the artist in the small greys, the path in Courier Prime
    row = flat(struct(folder, "FolderRow"))
    for part in (".font(SheetLook.words.weight(.semibold))", ".font(SheetLook.small) .foregroundStyle(DWPalette.t2)",
                 ".font(SheetLook.mono) .foregroundStyle(DWPalette.t3)", ".clipShape(DWCorners.chipShape)",
                 ".overlay(alignment: .bottom) { DWRule(colour: SheetLook.rule) }",
                 ".accessibilityElement(children: .ignore) .accessibilityLabel(EditWords.folderRow(album))"):
        assert part in row, part
    # "needs deadwax" in the look's own words, not the system's ContentUnavailableView; still one pull to read again
    screen = flat(struct(folder, "ChooseFolderScreen"))
    assert "FolderNeedsDeadwax()" in screen and "ContentUnavailableView" not in folder
    assert folder.count(".pullToRefresh") == 1
    needs = flat(struct(folder, "FolderNeedsDeadwax"))
    for part in ("Text(EditWords.chooseFolder) .font(SheetLook.title) .foregroundStyle(DWPalette.text)",
                 "Text(EditWords.needsDeadwax) .font(SheetLook.small) .foregroundStyle(DWPalette.t2)",
                 ".background(SheetLook.ground) .accessibilityElement(children: .combine)"):
        assert part in needs, part


def test_every_old_face_in_the_slice_is_the_looks_button():
    for name in (PICKER, PLAYLISTS, MAC_PLAYLISTS, FOLDER, LIBRARY, ALBUMS, SONGS, MINE, UNREACHABLE, NOTICE, BANNER,
                 COVER):
        source = bare(code(name))
        for old in ("PrimaryFace", "SecondaryPill", ".buttonStyle(.bordered", "Material"):
            assert old not in source, f"{name}: {old}"
    # the gate's one button at a time the purple (Try again, or Set up Navidrome - Core never offers both)
    gate = flat(parts()[f"{LIBRARY}:NavidromeGateView"])
    assert gate.count(".buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))") == 2
    assert "ProgressView() .tint(DWPalette.text)" in gate
    rule = flat(core("NavidromeGate.swift"))
    assert "tryAgain: status.configured, setUp: false" in rule and "tryAgain: true, setUp: false" in rule
    assert "tryAgain: false, setUp: access.isAdmin" in rule
    # Can't reach deadwax: Try again the large purple, Change address its large flat one, each across the column
    unreachable = flat(bare(code(UNREACHABLE)))
    assert ".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))" in unreachable
    assert ".buttonStyle(DWButtonStyle(size: .large, fills: true))" in unreachable
    assert ".font(SheetLook.mono) .foregroundStyle(DWPalette.t2)" in unreachable
    assert ".background(SheetLook.ground)" in unreachable
    # Downloaded's first ask: Turn On the purple, Not Now flat; the Mac's card a `.box`, the phone's PhoneCard
    first = flat(parts()[f"{ALBUMS}:FirstAskCard"])
    assert ".buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))" in first
    assert ".buttonStyle(DWButtonStyle(fills: stacked))" in first and "SheetButtons {" in first
    mac, phone = phone_look.halves(first, "if Platform.mac {")
    assert ".background(DWPalette.card, in: DWCorners.boxShape)" in mac and phone.strip().startswith("PhoneCard {")
    # an empty library's See All music, Songs' Shuffle and Try agains: flat words, Shuffle's why in the small greys
    assert ".buttonStyle(DWButtonStyle())" in flat(parts()[f"{ALBUMS}:EmptyLibraryNote"])
    songs = flat(bare(code(SONGS)))
    assert songs.count(".buttonStyle(DWButtonStyle())") == 3
    shuffle = flat(declaration(code(SONGS), "@ViewBuilder private var shuffleButton"))
    assert ("Button(action: shuffleAll) { Label(face.words, systemImage: \"shuffle\") } .buttonStyle(DWButtonStyle()) "
            ".disabled(!face.enabled)") in shuffle
    assert "Text(why) .font(SheetLook.small) .foregroundStyle(DWPalette.t2)" in shuffle
    # the album's Mine: Add the purple, Remove flat, its placeholder the purple's size unseen
    mine = flat(bare(code(MINE)))
    assert ".buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))" in mine
    assert ".buttonStyle(DWButtonStyle(fills: stacked))" in mine
    assert ".buttonStyle(DWButtonStyle(kind: .pri, fills: typeSize.isAccessibilitySize))" in mine
    assert ".foregroundStyle(DWPalette.redChipText)" in mine


# ----------------------------------------------------------------------------- the notice and the banners

def test_the_notice_is_a_ground_and_a_hairline_and_takes_no_touch():
    notice = flat(struct(bare(code(NOTICE)), "Notice"))
    assert ("Text(text) .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.strip)) "
            ".foregroundStyle(DWPalette.text) .multilineTextAlignment(.center) .padding(.horizontal, 16) "
            ".padding(.vertical, 8) .background(Platform.mac ? DWPalette.card : DWPalette.page, in: DWCorners.boxShape) "
            ".overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1)) .allowsHitTesting(false)") in notice
    assert "Material" not in notice and "Corners.cardShape" not in notice
    # its phone words the very face Now Playing measures its longest word in (NoticeWord: Typeface.subheadline) - both
    # Libre Franklin at 15, scaled as the subheadline scales
    typeface = code("Shared/Typeface.swift")
    assert "case .strip: return (15, .subheadline)" in typeface
    assert "static let subheadline = text(15, .subheadline)" in typeface
    assert ".custom(family, size: size, relativeTo: style)" in typeface
    assert ".custom(family, size: size.scaled.points, relativeTo: size.scaled.style)" in typeface
    word = flat(struct(bare(code("Player/NowPlayingView.swift")), "NoticeWord"))
    assert ".font(Typeface.subheadline)" in word


def test_the_notice_sits_above_the_mini_players_target_at_any_size():
    # MainTabs: the notice laid over the stack's foot, `tabBarRoom` up from the safe area's foot, and 8 more of its own
    tabs = flat(bare(code("Root/MainTabs.swift")))
    assert ".overlay(alignment: .bottom) { NoticeInset { noticeHeight = $0 } .padding(.bottom, tabBarRoom) }" in tabs
    inset = flat(struct(bare(code("Root/MainTabs.swift")), "NoticeInset"))
    assert "Notice(text: notice) .transition(.move(edge: .bottom).combined(with: .opacity)) .padding(.horizontal, 8) " \
           ".padding(.bottom, 8)" in inset
    assert ".environment(\\.tabBarRoom, keyboardUp ? 0 : CGFloat(TabBarFoot.room(content: barHeight, home: home)))" in tabs
    # the bar (the play bar and the tabs) measured whole: its height as drawn, the room under it not counted
    assert "AppTabBar(home: home) { (height: CGFloat) -> Void in barHeight = height }" in tabs
    foot = flat(core("TabBarFoot.swift"))
    drop = float(re.search(r"public static let drop = ([0-9.]+)", foot).group(1))
    least = float(re.search(r"public static let least = ([0-9.]+)", foot).group(1))
    assert ("public static func below(home: Double) -> Double { guard home.isFinite, home > 0 else { return least } "
            "return max(home - drop, least) }") in foot
    assert ("public static func room(content: Double, home: Double) -> Double { let indicator = home.isFinite ? "
            "max(home, 0) : 0 return max(content + below(home: home) - indicator, 0) }") in foot

    def below(home: float) -> float:
        return least if home <= 0 else max(home - drop, least)

    def room(content: float, home: float) -> float:
        return max(content + below(home) - max(home, 0), 0)

    # from the screen's foot: the bar's top is its content over the room under it; the notice's foot is the home
    # indicator's room, then `tabBarRoom`, then its own 8. Every bar's height a text size gives (the tabs alone, 49 at
    # the default size, to the play bar and two-line tabs at AX5) on every phone's foot (Home button, Face ID)
    for home in (0.0, 20.0, 21.0, 34.0, 48.0):
        for content in (0.0, 44.0, 49.0, 83.0, 96.0, 120.0, 160.0, 240.0):
            bar_top = content + below(home)
            notice_foot = home + room(content, home) + 8
            assert notice_foot - bar_top >= 8, (home, content, notice_foot, bar_top)
    # and the mini player's seek line, laid over the bar's top edge, takes no touch: its targets are inside the bar
    mini = flat(bare(code("Player/MiniPlayerView.swift")))
    assert ".offset(y: Self.rest / 2 - Self.room / 2) .allowsHitTesting(false)" in mini
    # the Mac's the same drawing over the page's foot; Now Playing's between Close and the look button, taking no touch
    mac = flat(struct(bare(code("Mac/Frame/MacTabStack.swift")), "MacNotice"))
    assert ".padding(.horizontal, 8) .padding(.bottom, 8)" in mac
    playing = flat(declaration(bare(code("Player/NowPlayingView.swift")), "private func topRow("))
    assert ".padding(.leading, middle ? side + topEnds.leading + gap : side)" in playing
    assert ".padding(.trailing, middle ? gap + topEnds.trailing + side : side)" in playing
    assert ".allowsHitTesting(false)" in playing


def test_the_banners_are_solid_grounds_with_the_ambers_hairline_and_cover_nothing():
    banner = bare(code(BANNER))
    ground = struct(banner, "BannerGround")
    mac, phone = phone_look.halves(ground, "if Platform.mac {")
    assert mac == " Rectangle().fill(DWPalette.bg) .overlay(Rectangle().fill(DWPalette.amberFill)) ", mac
    assert phone == " Rectangle().fill(DWPalette.page) ", phone
    assert ".overlay(alignment: .bottom) { Rectangle() .fill(DWPalette.amberEdge) .frame(height: 1 / max(scale, 1)) }" \
           in flat(ground)
    assert "Material" not in banner and ".bar" not in banner and "Palette.amber" not in re.sub(r"DWPalette", "", banner)
    # the strip and Edit album's line on it, in the amber's words, at the banner's measures
    strip = flat(declaration(banner, "private func strip("))
    assert ".padding(.horizontal, BannerLook.side) .padding(.vertical, BannerLook.foot)" in strip
    assert ".background { BannerGround() }" in strip and ".foregroundStyle(DWPalette.amberText)" in strip
    assert ".buttonStyle(DWButtonStyle()) .disabled(reachability.probing)" in strip
    edit = flat(declaration(bare(code(EDIT)), "func editOutOfReach("))
    assert ("safeAreaInset(edge: .top, spacing: 0) {" in edit and ".padding(.horizontal, BannerLook.side) "
            ".padding(.vertical, BannerLook.foot) .background { BannerGround() }") in edit
    assert ".foregroundStyle(DWPalette.amberText)" in edit
    # each a safe-area inset at the page's top, never laid over the page
    assert "func showsOfflineBanner(_ shown: Bool = true) -> some View { safeAreaInset(edge: .top, spacing: 0) {" \
           in flat(banner)
    # Try again's finger's target (DWTarget: a flat button's 36 grown to 44, its reach above and below) stays inside the
    # strip's own room under it
    look = flat(core("DWLook.swift"))
    dwlook = (CORE / "DWLook.swift").read_text(encoding="utf-8")
    height = float(re.search(r"buttonHeight: ([0-9.]+), +// dw\.ph: \.btn height", dwlook).group(1))
    target = float(re.search(r"target: ([0-9.]+),", dwlook[dwlook.index("static let onPhone"):]).group(1))
    assert "public func reach(_ height: Double) -> Double { max(0, (target - height) / 2) }" in look
    foot = float(re.search(r"static let foot: CGFloat = ([0-9.]+)", banner).group(1))
    assert (height, target) == (36.0, 44.0) and foot >= (target - height) / 2, (height, target, foot)


def test_the_covers_close_is_a_bare_glyph_on_the_phone_and_the_macs_round_key():
    viewer = bare(code(COVER))
    close = flat(struct(viewer, "CoverCloseButton"))
    assert ".foregroundStyle(DWPalette.text)" in close and ".buttonStyle(CoverCloseKey())" in close
    assert "Palette.card" not in close and "Corners." not in close.replace("DWCorners.", "")
    key = struct(viewer, "CoverCloseKey")
    mac, phone = phone_look.halves(key, "if Platform.mac {")
    assert ("DWRaised(shape: Circle(), face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen, edge: "
            "DWPalette.buttonEdge, drop: DWPalette.buttonDrop, pressed: configuration.isPressed)") in mac
    assert ".contentShape(Circle()) .frame(minWidth: 44, minHeight: 44)" in mac
    assert phone == (" configuration.label .opacity(configuration.isPressed ? DWPalette.off : 1) "
                     ".frame(minWidth: 44, minHeight: 44) .contentShape(Rectangle()) "), phone
    assert phone_look.drawn(phone_look.phone_path(key)) == []


def test_tokens_only_and_the_queue_is_the_queue():
    for name, part in parts().items():
        for raw in ("Color(", "Color.primary", "Color.red", "Color.gray", ".opacity(0.", ".font(.system", "cornerRadius",
                    "UIColor"):
            assert raw not in part, f"{name}: {raw}"
        # the redesign's palette alone - but the empty cover's square, a picture's own (as the Library's rows draw it)
        olds = set(re.findall(r"(?<![A-Za-z])Palette\.\w+", part))
        assert olds <= {"Palette.coverEmpty"}, f"{name}: {olds}"
        assert not re.search(r"(?<![\w.])(?:Corners|MacCorners)\.", part), name
        assert not re.search(r"\bTypeface\.(?:headline|footnote|subheadline|title|title2|title3|body|callout|caption|"
                             r"caption2|largeTitle)\b", part), name
    for name in sorted(phone_look.R18_PAGES) + [MAC_PLAYLISTS, LIBRARY, ALBUMS, SONGS, PLAYLISTS, EDIT]:
        assert "Up Next" not in code(name), name
