"""
The panel review's R19 - Get, and old type left in redrawn pages (notes/ios.md "The panel review, R19: Get, and old type
left in redrawn pages (2026-11-27)"; panel-review.md's checks 639-644). James chose to have Get's store line redrawn,
though R7 had kept it; the Mac's Sources still sat under a system bar; and pages already redrawn kept the old Palette and
the system's text styles in corners no drawing showed. This holds what R19 drew:

- The Mac's Sources has no system bar: its Search again is in R16's DockHeader - one button, one toggle, no row while
  it would hold nothing - and its Close is the dock's own (Escape, or a click on its open folder tab: Sources has no
  View key), the panel put away the Get over, as Close was. While the words to search with are edited the tab holds
  Escape, as Close's Escape did, and a click on its open tab does nothing; a field with the cursor gets Escape first.
- (R19's review, James's decision 1) A click on a folder tab is a tab's key: the open one puts the panel away, another
  is switched to (MacDock.clicked, toggled's rule); `shown` stays for the bar's ••• Info and EQ and Settings' EQ.
- Get's store line is Get.dc.html's box on the Mac (the look's 5 corners, the card and its line) and flat on the phone,
  its buttons the look's; Manual search's Search the look's primary.
- The old Palette, Corners and the system's text styles are gone from the parts R19 names, each moved to a Typeface and
  DWPalette token; the 20, 22 and 28 the phone has no size of its own for are kept where they were, counted.
- Server settings' choice setting and Downloads' two choices are the look's pop-up on the Mac, their menus the very
  Pickers they were - the same bindings and tags, so a choice sends exactly what it sent.
- The desktop frame's hairline is DWPalette's and its drawer shadow black at 0.2, as it always was, named in the
  frame; it hands View > Row Size into Add to a playlist's sheet, whose Mac rows read it.
- Every word each file draws is as it was: pinned here as the set of word expressions each draws.
"""
import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_get_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
settings_look = _load("test_ios_settings_look")

SOURCES = "Get/SourcesSheet.swift"
SOURCES_TAB = "Mac/Search/MacSourcesTab.swift"
PANELS = "Player/MacPanels.swift"
STORE = "Get/StoreLineView.swift"
MANUAL = "Get/ManualSearchSheet.swift"
MB_ARTIST = "Search/MBArtistView.swift"
DOWNLOADS = "Downloads/DownloadsScreen.swift"
HERO = "Album/AlbumHero.swift"
PLAYLIST = "Playlists/PlaylistView.swift"
PRESSINGS = "Search/PressingPickerSheet.swift"
ERROR = "Shared/ErrorNote.swift"
SETTINGS = "Manage/ServerSettingsGroupScreen.swift"
FRAME = "Root/DesktopFrame.swift"
ROOT = "Root/RootView.swift"
PICKER = "Playlists/PlaylistPicker.swift"
PEOPLE = "Manage/PeopleScreen.swift"


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def code(name: str) -> str:
    """Swift as code: its comments blanked, its literals kept."""
    return reader.views(source(name))[0]


def bare(name: str) -> str:
    """Swift as code alone: its comments and its literals' contents blanked."""
    return reader.views(source(name))[1]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def member(text: str, declaration: str) -> str:
    """The text of the one member declared as `declaration`, through its closing brace."""
    edge = r"\b" if declaration[-1].isalnum() else ""
    found = list(re.finditer(r"(?<![\w.])" + re.escape(declaration) + edge + r"[^{]*\{", text))
    assert len(found) == 1, f"{declaration} is declared {len(found)} times"
    opened = found[0].end() - 1
    return text[found[0].start():reader.closing(text, opened) + 1]


# ----------------------------------------------------------------------------- the Mac's Sources, in the dock

def test_the_macs_sources_has_no_bar_and_one_search_again_in_the_dock_header():
    page = code(SOURCES)
    body = flat(member(member(page, "struct SourcesPage: View"), "var body: some View"))
    # the dock's header in the bar's place: the subtitle, and Search again at its right
    assert ("if kept != nil, Platform.mac { if !request.subtitle.isEmpty || foundFolders { dockHeader } } "
            "else if !request.subtitle.isEmpty {") in body
    assert ".toolbar(docked ? .hidden : .automatic, for: .navigationBar)" in body
    # no Close and no bar's Search again in the dock: both only where there is a bar
    assert "if !pushed && !docked { ToolbarItem(placement: .cancellationAction) { Button(SourcesLook.close) {" in body
    assert "if foundFolders && !docked { ToolbarItem(placement: .topBarTrailing) { againInBar } }" in body
    assert "private var docked: Bool { kept != nil }" in flat(page)
    assert "closeDock" not in page
    header = flat(member(page, "private var dockHeader: some View"))
    assert header.startswith("private var dockHeader: some View { DockHeader { if !request.subtitle.isEmpty {")
    assert ("} trailing: { if foundFolders { Button(SourcesWords.searchAgain) { toggleAgain(.top) } "
            ".buttonStyle(DWButtonStyle(kind: again == .top ? .on : .normal, size: .small)) .fixedSize() "
            ".accessibilityValue(again == .top ? SourcesWords.expanded : SourcesWords.collapsed) } } }") in header
    # one button, one toggle: Search again sent once, and only from here or its own two places
    assert header.count("Button(") == 1 and header.count("toggleAgain(") == 1
    assert flat(page).count("toggleAgain(.top)") == 2  # the bar's (phone, and a sheet's) and the dock header's
    assert "Text(request.subtitle) .font(Typeface.Look.text(.smallButton)) .foregroundStyle(DWPalette.t2)" in header


def test_the_docks_close_is_the_docks_own_and_a_field_gets_escape_first():
    tab = flat(code(SOURCES_TAB))
    assert ("SourcesPage(request: get.request, pushed: false, kept: get.choices) { "
            "navigation.sourcesQueued(get.request.id) }") in tab
    # edited words hold Escape, as Close's `.escapeCloses(!model.edited)` did; the panel put away ends the Get
    assert (".id(get.request.id) .dockHoldsEscape(get.request.search.edited) .onDisappear { if navigation.macPanel == nil "
            "{ navigation.endSources() } }") in tab
    assert tab.count("dockHoldsEscape") == 1 and tab.count("endSources") == 1
    # R16's hold on the whole tab is gone: Sources holds Escape only while its words are edited
    page = flat(member(code(PANELS), "var page: some View"))
    assert "case .sources: MacSourcesTab() }" in page and "MacSourcesTab() .dockHoldsEscape" not in page
    # the panel's one key, through the one owner - which answers a field with the cursor first
    key = flat(member(code(PANELS), "struct DockEscapeKey: View"))
    assert ("Button(action: { navigation.closePanel() }) { DWPalette.panel } .escapeCloses(!held && "
            "MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)") in key
    dock = flat((CORE / "MacDock.swift").read_text(encoding="utf-8"))
    assert ("public static func escape(typing: Bool, shown: Tab?) -> MacFrame.Escape { if typing { return .field } "
            "return shown == nil ? .page : .panel }") in dock
    assert ("public static func escape(typing: Bool, panel: MacDock.Tab?) -> Escape { "
            "MacDock.escape(typing: typing, shown: panel) }") in dock


def test_a_click_on_the_open_folder_tab_closes_the_dock_and_never_loses_edited_words():
    # (R19's review - James's decision 1, 26 Nov: "a click on the open tab") the folder tab's click is a tab's key
    panel = flat(member(code(PANELS), "struct MacPanel: View"))
    assert "chosen: Binding(get: { tab }, set: { (chosen: MacDock.Tab) -> Void in clicked(chosen) })," in panel
    assert ("private func clicked(_ chosen: MacDock.Tab) { let edited = navigation.macSources?.request.search.edited "
            "?? false if let now = MacDock.clicked(tab, chosen, getOpen: navigation.macGetOpen, sourcesEdited: edited) "
            "{ navigation.showPanel(now) } else { navigation.closePanel() } }") in panel
    # the click never shows the asked tab outright: that is `shown`'s, kept for the bar's ••• and Settings' EQ
    assert "showPanel(chosen)" not in panel and "MacDock.shown(" not in panel
    dock = flat((CORE / "MacDock.swift").read_text(encoding="utf-8"))
    assert ("public static func clicked(_ shown: Tab?, _ asked: Tab, getOpen: Bool, sourcesEdited: Bool) -> Tab? { "
            "if asked == shown && asked == .sources && sourcesEdited { return shown } "
            "return toggled(shown, asked, getOpen: getOpen) }") in dock
    # the Get's own `edited` - the very one the tab holds Escape by
    assert "navigation.macSources?.request.search.edited" in panel
    assert ".dockHoldsEscape(get.request.search.edited)" in flat(code(SOURCES_TAB))


def test_the_sources_states_and_query_field_are_in_the_looks_type():
    page = code(SOURCES)
    whole = flat(page)
    # searching, none, refused: the state's line the card row's words (the phone's 16, the Mac's 13) in white, what goes
    # with it the small size in the second colour - on both devices
    words, small = "Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row)", "Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small)"
    for line in ("Text(Sources.searchingLine(search.release))", "private func stateText(_ words: String) -> some View { "
                 "Text(words)"):
        assert f"{line} .font({words}) .foregroundStyle(DWPalette.text)" in whole, line
    for line in ("Text(Sources.searchTakes)", "Text(notPicked)", "Text(Sources.nothingLosslessNote)",
                 "Text(Sources.searchedLine(answer, shown: shown.count))"):
        assert f"{line} .font({small}) .foregroundStyle(DWPalette.t2)" in whole, line
    for state in ("nothingLosslessLine(answer)", "nothingFoundLine(answer)", "noneMatchLine(answer.candidates.count)"):
        assert f"stateText(Sources.{state})" in whole, state
    # the query field: the look's well - square on the phone, `.in`'s radius on the Mac (DWWell's own shape) - its
    # words in the field's type, the system's ring off
    form = flat(member(page, "private func queryForm"))
    assert (".textFieldStyle(.plain) .font(Typeface.Look.text(.field)) .foregroundStyle(DWPalette.fieldText) "
            ".focused($againFocused) .focusEffectDisabled()") in form
    assert (".lookHeight(DWLook.here.fieldHeight) .background { DWWell(focused: againFocused) "
            ".contentShape(DWTarget(face: DWCorners.buttonShape)) .onTapGesture { againFocused = true } }") in form
    assert "static let fieldInside: CGFloat = 8" in flat(page)
    # Search again under the folders: the look's button
    again = flat(member(page, "@ViewBuilder private var searchAgain: some View"))
    assert "Button(SourcesWords.searchAgain) { toggleAgain(.bottom) } .buttonStyle(DWButtonStyle())" in again


# ----------------------------------------------------------------------------- the store line, Manual search

def test_the_store_line_is_gets_box_on_the_mac_and_flat_on_the_phone():
    store = code(STORE)
    # the Mac's: Get.dc.html's .box - the card, its 5 corners (DWCorners.box) and its hairline, 12 inside
    mac = flat(settings_look.mac_path(store))
    assert (".padding(StoreLineLook.inside) .frame(maxWidth: .infinity, alignment: .leading) "
            ".background(DWPalette.card, in: DWCorners.boxShape) "
            ".overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))") in mac
    assert "static let inside: CGFloat = 12" in flat(store)
    look = flat((APP / "Look" / "DWCorners.swift").read_text(encoding="utf-8"))
    assert re.search(r"static let box: CGFloat = 5\b", look) or re.search(r"box\s*=\s*5\b", look), "the box's 5"
    assert re.search(r"static var boxShape: \w+ \{[^}]*\bbox\b", look), "boxShape draws the box's corners"
    # the phone's: no box, no ground, no corner
    phone = flat(phone_look.phone_path(store))
    assert "DWCorners.boxShape" not in phone and "strokeBorder" not in phone and "DWPalette.card" not in phone
    # its buttons the look's; the old faces gone from every file R19 redrew
    assert ".buttonStyle(DWButtonStyle()) .opacity(phase == .busy ? DWPalette.off : 1)" in flat(store)
    for name in (STORE, SOURCES, MANUAL, MB_ARTIST, DOWNLOADS, PLAYLIST, ERROR):
        assert not re.search(r"\b(PrimaryFace|SecondaryPill)\b|\.bordered|\.borderless", code(name)), name


def test_manual_searchs_search_is_the_looks_primary():
    manual = flat(code(MANUAL))
    assert ("Button(ManualSearch.search, action: search) .buttonStyle(DWButtonStyle(kind: .pri, size: .large, "
            "fills: true)) .disabled(!searchable) .padding(.top, 20)") in manual
    assert "Text(ManualSearch.footer) .font(Typeface.Phone.text(.small)) .foregroundStyle(DWPalette.t2)" in manual


# ----------------------------------------------------------------------------- the old type and Palette

#? Typeface.body is not among them: Libre Franklin's 17 scaled with body, the phone's row title (LibraryListRow's, R2's
#? iArtists' row) - the rows R19 gave a font where they had none take it, the very size and style they inherited
OLD_LOOK = re.compile(r"(?<![\w.])Palette\.|(?<![\w.])Corners\.|Typeface\.(?:headline|footnote|subheadline|"
                      r"title\d?|caption2?|callout|mono(?=\())\b|\.foregroundStyle\(\.(?:primary|secondary|tertiary|"
                      r"red|white)\b|Color\(\.system\w+\)|\.tint\(\.red\)|\(\.white, \.red\)")

#? where each file is held to it, and what is kept: the 20, 22 and 28 the phone has no size of its own for, where the
#? drawings set them (an album's and a playlist's title 22 bold or 20, the artist 20; iArtist's name 28; the Storage
#? bar's amount 22), counted
WHOLE_FILES = {
    SOURCES: {}, SOURCES_TAB: {}, STORE: {}, MANUAL: {}, ERROR: {}, SETTINGS: {}, FRAME: {}, ROOT: {}, PRESSINGS: {},
    MB_ARTIST: {"Typeface.title": 1},
    DOWNLOADS: {"Typeface.title2": 2},
    HERO: {"Typeface.title3": 2, "Typeface.title2": 1},
}
#? PlaylistView's edit sections and its quiet line: the rest of the page is R5's
PARTS = {PLAYLIST: ("@ViewBuilder private func editSections()", "private func editRow(", "private struct QuietLine: View")}


def old_look(text: str) -> dict[str, int]:
    found: dict[str, int] = {}
    for hit in OLD_LOOK.finditer(text):
        found[hit.group(0)] = found.get(hit.group(0), 0) + 1
    return found


def test_no_old_palette_or_system_type_left_where_r19_drew():
    for name, kept in WHOLE_FILES.items():
        assert old_look(bare(name)) == kept, name
    for name, parts in PARTS.items():
        for part in parts:
            assert old_look(flat(member(bare(name), part))) == {}, (name, part)


def test_the_old_type_each_moved_to_its_very_size():
    # an album's download line: `.xs` semibold, caption's 12; the second colour, amber's words for didn't
    line = flat(member(code(HERO), "struct DownloadLine: View"))
    assert (".font(Typeface.Phone.text(.extraSmall).weight(.semibold)) "
            ".foregroundStyle(failed ? DWPalette.amberText : DWPalette.t2)") in line
    # an error's line the card row's 16 on the phone, its detail the small words (the system's monospace was: the
    # readout face is for numbers that tick)
    note = flat(code(ERROR))
    assert "Text(line.said) .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row))" in note
    assert ("Text(detail) .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small)) "
            ".foregroundStyle(DWPalette.t2)") in note and "mono" not in note
    # a pressing's facts and note the sheet's small words, its "In your library" `.xs` semibold green
    row = flat(code(PRESSINGS))
    assert row.count(".font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))") == 2
    assert ("Text(row.heldLabel) .font(Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.text(.extraSmall)) "
            ".fontWeight(.semibold) .foregroundStyle(DWPalette.greenText)") in row
    # Downloads' headline the phone's 17 semibold (headline's very size and style), its rows' titles LibraryListRow's,
    # its error's detail the small words, its swipe's red the look's
    downloads = flat(code(DOWNLOADS))
    assert "Text(DownloadWords.nothingYetHeadline) .font(Typeface.Phone.text(.topName).weight(.semibold))" in downloads
    assert downloads.count(".font(Typeface.body)") == 3
    assert "Text(detail) .font(Typeface.Phone.text(.small))" in downloads and ".tint(DWPalette.redChipText)" in downloads
    # an MB artist's rows on the look's hairline, at the look's corners, no shadow under the picture
    artist = flat(code(MB_ARTIST))
    assert "DWRule(colour: Platform.mac ? DWPalette.rowline : DWPalette.rowRule) .padding(.leading, LibraryRow.textInset)" in artist
    assert "Divider()" not in artist and ".shadow(" not in artist and ".clipShape(DWCorners.chipShape)" in artist
    assert (".toggleStyle(.button) .buttonStyle(DWButtonStyle(kind: model.studioOnly ? .on : .normal, size: .small))"
            in artist)
    # the playlist's (-) the red button's face and words, not the system's red
    edit = flat(member(code(PLAYLIST), "private func editRow("))
    assert ".foregroundStyle(DWPalette.redText, DWPalette.redFace)" in edit and ".buttonStyle(.plain)" in edit
    # the sign-in's ground the page's, not the system's
    assert ".background((Platform.mac ? DWPalette.bg : DWPalette.page).ignoresSafeArea())" in flat(code(ROOT))
    assert not any("systemBackground" in path.read_text(encoding="utf-8") for path in APP.rglob("*.swift"))


# ----------------------------------------------------------------------------- the Mac's pop-ups

def picker_block(text: str) -> str:
    """The `Picker(selection: value) { ... } label: { ... }` a choice setting draws, flattened."""
    at = text.index("Picker(selection: value)")
    opened = text.index("{", at)
    end = reader.closing(text, opened)
    label = text.index("{", end + 1)
    return flat(text[at:reader.closing(text, label) + 1])


def test_a_choice_setting_sends_exactly_what_the_system_picker_sent():
    control = settings_look.struct(code(SETTINGS), "SettingControl")
    mac = settings_look.mac_path(control)
    phone = phone_look.phone_path(control)
    # the Mac's: the look's pop-up, the chosen choice its words, its menu the Picker - inline, as the phone's menu holds it
    assert re.search(r"DWPopUp\(words: Self\.chosen\(choices, value: row\.value\)\) \{ Picker\(selection: value\)",
                     flat(mac))
    assert ".pickerStyle(.inline) } .frame(maxWidth: .infinity, alignment: .leading) .accessibilityLabel(setting.key)" in flat(mac)
    assert ".pickerStyle(.menu)" not in mac and ".tint(" not in mac
    # the very Picker the phone's menu holds (and the Mac's system pop-up was): the same binding, choices and tags
    assert picker_block(mac) == picker_block(phone)
    assert picker_block(mac) == ("Picker(selection: value) { ForEach(choices) { (choice: ServerSettings.Choice) in "
                                 "Text(choice.label).tag(choice.value) } } label: { Text(setting.key) }")
    # and `value` writes what is chosen through the model's edit, as it did
    assert ("let value = Binding( get: { settings.flow.row(setting).value }, set: { (typed: String) -> Void in "
            "settings.edit(setting.key, typed) } )") in flat(control)


def test_downloads_choices_are_the_looks_pop_up_on_the_mac_the_same_pickers():
    downloads = code(DOWNLOADS)
    mac = flat(settings_look.mac_path(downloads))
    phone = flat(phone_look.phone_path(downloads))
    assert "DWPopUp(words: downloads.storageLimit.label) { storageLimitPicker .pickerStyle(.inline) }" in mac
    assert "DWPopUp(words: chosen.name) { overPicker .pickerStyle(.inline) }" in mac
    assert "storageLimitPicker .pickerStyle(.menu)" in phone
    assert "overPicker .pickerStyle(.menu) .accessibilityHint(chosen.note)" in phone
    assert "DWPopUp" not in phone
    # each Picker once, both devices': Storage limit's binding the setting itself, Download over's set as it was
    whole = flat(downloads)
    assert ("private var storageLimitPicker: some View { @Bindable var downloads = downloads return "
            "Picker(DownloadWords.storageLimit, selection: $downloads.storageLimit) { ForEach(StorageLimit.allCases, "
            "id: \\.self) { choice in Text(choice.label).tag(choice) } } }") in whole
    assert ("Picker(DownloadWords.downloadOver, selection: Binding<DownloadOver>(get: { downloads.downloadOver }, "
            "set: { (choice: DownloadOver) -> Void in downloads.downloadOver = choice })) { "
            "ForEach(DownloadOver.allCases, id: \\.self) { (choice: DownloadOver) in "
            "Text(DownloadWords.over(choice, device: Platform.device).name).tag(choice) } }") in whole
    assert whole.count("Picker(DownloadWords.storageLimit") == 1 and whole.count("Picker(DownloadWords.downloadOver") == 1


# ----------------------------------------------------------------------------- the frame and Row Size

def test_the_frames_tokens_and_row_size_handed_into_add_to_a_playlist():
    frame = flat(code(FRAME))
    assert "Palette." not in re.sub(r"DWPalette\.", "", frame)
    # (R19's review) the drawer's shadow black at 0.2, as before R19, named in the frame - not buttonDrop's 0.45
    assert ".shadow(color: MacDock.liesOver(style, panel) ? Self.drawerDrop : Color.clear," in frame
    assert "private static let drawerDrop = Color.black.opacity(0.2)" in frame and "buttonDrop" not in frame
    assert "private var rule: some View { DWPalette.frame .frame(width: hairline)" in frame
    # Row Size read once, handed to the frame's lists and, as plain numbers, into the sheet it puts up over itself
    assert "private var rowSize: MacRowSize { MacRowSizeStore.shared.size }" in frame
    assert ".environment(\\.macRowSize, rowSize) .modifier(RowSizeAlternateKey())" in frame
    assert ("PlaylistPicker(request: request) .environment(\\.sheetRowSize, SheetRowSize(height: "
            "CGFloat(rowSize.rowHeight), cover: CGFloat(rowSize.cover))) .macSheet()") in frame
    assert "struct SheetRowSize: Equatable { let height: CGFloat let cover: CGFloat }" in frame
    assert "extension EnvironmentValues { @Entry var sheetRowSize: SheetRowSize? = nil }" in frame
    handed = [path.relative_to(APP).as_posix() for path in sorted(APP.rglob("*.swift"))
              if ".environment(\\.sheetRowSize" in path.read_text(encoding="utf-8")]
    assert handed == [FRAME], handed
    # the picker's Mac row: its cover and height the size handed in, the sheet's own where none was; the phone's row
    # untouched by it
    row = member(code(PICKER), "private struct PickerRow: View")
    assert "@Environment(\\.sheetRowSize) private var rowSize" in row
    mac = flat(settings_look.mac_path(row))
    assert "mark(side: rowSize?.cover ?? SheetLook.macCover)" in mac
    assert ".font(SheetLook.words) .frame(minHeight: rowSize?.height ?? SheetLook.rowHeight) .sheetRow() .help(name)" in mac
    phone = flat(phone_look.phone_path(member(row, "var body: some View")))
    assert "rowSize" not in phone and "mark(side: LibraryLook.rowCover)" in phone


# ----------------------------------------------------------------------------- the words, as they were

CALL = re.compile(r"\b(?:Text|Button|Toggle|Picker|Label|DWPopUp|ErrorNote|accessibilityLabel|accessibilityValue|"
                  r"accessibilityHint|navigationTitle|help|DisclosureGroup)\((?:words: |text: )?"
                  r"([^(){}\n]*(?:\([^(){}\n]*\)[^(){}\n,]*)?)")


def drawn_words(name: str) -> set[str]:
    """The first argument of every call that puts words on the page or into VoiceOver."""
    found = set()
    for argument in CALL.findall(code(name)):
        argument = argument.split(",")[0].strip().rstrip(")")
        if argument and not argument.startswith(("action", "selection")):
            found.add(argument)
    return found


#? As at the tip R19 began from (b51a90a5), read with drawn_words: no word went, none came - Downloads' two pop-ups
#? say the chosen choice in its own words (chosen.name, the storage limit's label), as the system's pop-up showed it
WORDS = {
    STORE: 7, ERROR: 3, PRESSINGS: 11, HERO: 7, MANUAL: 6, MB_ARTIST: 12, SOURCES: 30, PLAYLIST: 41, SETTINGS: 28,
    DOWNLOADS: 57, ROOT: 1, PICKER: 16,
}
SAID = {
    STORE: {"status.title", "status.lines[at]", "notes[at]", "words.done", "words.unanswered", "refused",
            "phase == .busy ? words.busy : words.idle"},
    ERROR: {"line.said", "detail", "ErrorWords.forWhoever"},
    MB_ARTIST: {"MBArtistPage.studioOnly", "MBArtistPage.loading", "SearchWords.tryAgain", "ArtistWords.albumsHeading"},
    SOURCES: {"SourcesWords.searchAgain", "SourcesLook.close", "request.subtitle", "SourcesWords.title",
              "Sources.searchingLine(search.release", "Sources.searchTakes", "notPicked", "Sources.nothingLosslessNote",
              "Sources.searchedLine(answer", "words"},
    PLAYLIST: {"PlaylistWords.needsAName", "PlaylistWords.sharedNote", "PlaylistWords.songsHeading", "row.title",
               "row.artist"},
    PRESSINGS: {"row.label", "row.facts", "row.note", "row.heldLabel"},
    MANUAL: {"ManualSearch.footer", "ManualSearch.search"},
    DOWNLOADS: {"DownloadWords.storageLimit", "DownloadWords.downloadOver", "chosen.name", "chosen.note",
                "downloads.storageLimit.label", "DownloadWords.nothingYetHeadline"},
    SETTINGS: {"setting.key", "Self.chosen(choices", "ServerSettings.locked"},
}


def test_every_word_is_as_it_was():
    for name, count in WORDS.items():
        words = drawn_words(name)
        assert len(words) == count, (name, len(words), sorted(words))
        for said in SAID.get(name, ()):
            assert said in words, (name, said)
