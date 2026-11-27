"""
The side panel's tabs and the Now Playing sheet (the redesign, slice R3 - notes/ios.md "The redesign, slice R3: the side
panel's tabs; the Now Playing sheet"; the build plan's 3.4 and 3.8). Core's MacDock and NowPlayingTabs hold the rules
(MacDockTests, NowPlayingTabsTests); test_ios_mac.py's panels test holds the dock's drawing. This holds the phone's half
and what the slice promised to leave alone:

  - One sheet over Now Playing (NowPlayingSheet): the Queue, Info and the EQ its tabs, one drawn at a time, under
    `‹ Now Playing` and the strip - no Lyrics tab (James, 25 Nov: "The cover's place").
  - The bottom row of five in the footer's place, each opening what it names; Lyrics turns the lyrics in the cover's
    place on and off and never opens the sheet; the speed chip over the gap between the output and Info (in a band of
    its own since the review - test_ios_nowplaying_row.py works its frames out); the ••• up beside the look button.
  - A shared EQ file opens the sheet on EQ - never lost under the Queue or Info - keeping eq.md 3.9's wait; on the Mac
    (the review) the dock's EQ tab, its preview over it - one EQ, never a second.
  - (The review) A dock tab with nothing to be about says so, never a blank page.
  - The drag down still closes Now Playing.
  - EQScreen's List - the Mac's side panel's - as R3 left it (R3b redrew the phone's: test_ios_nowplaying_pages_look.py).
  - "Queue on both" (James, 25 Nov, 3.8 answer 3): no word the app shows on the phone or the Mac says "Up Next".
"""

import hashlib
import importlib.util
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"
WORDS = IOS / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "words"
NOW_PLAYING = APP / "Player" / "NowPlayingView.swift"
SHEET = APP / "Player" / "NowPlayingSheet.swift"
PANELS = APP / "Player" / "MacPanels.swift"
EQ_SCREEN = APP / "EQ" / "EQScreen.swift"
TABS = CORE / "NowPlayingTabs.swift"
DOCK = CORE / "MacDock.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_panels_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def code(path: Path) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(path.read_text(encoding="utf-8"))[0]


def bare(path: Path) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(path.read_text(encoding="utf-8"))[1]


def block(text: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:index]
    raise AssertionError("unbalanced braces")


def member(text: str, declaration: str) -> str:
    """The body of the one member declared as `declaration` (`func shared`, `var grip`, ...)."""
    found = list(re.finditer(r"\b" + re.escape(declaration) + r"\b[^{]*\{", text))
    assert len(found) == 1, f"{declaration} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def body_of(text: str) -> str:
    """The first `var body` - Now Playing's, the root its presentations hang from (its private views' come after it)."""
    return block(text, text.index("{", text.index("var body: some View {")))


# ----------------------------------------------------------------------------- one sheet

def test_now_playing_has_one_sheet_for_the_queue_info_and_the_eq():
    now = bare(NOW_PLAYING)
    body = body_of(now)
    presents = re.findall(r"\.appSheet\((isPresented|item): \$(\w+)\)", body)
    #? one sheet and Add to a playlist: never a second sheet of its own over the first
    assert presents == [("isPresented", "sheetUp"), ("item", "playlistPick")], presents
    assert ".appSheet(isPresented: $sheetUp) { NowPlayingSheet(tab: $sheetTab).macSheet() }" in body
    assert now.count("NowPlayingSheet(") == 1
    #? the three sheets' pages are the sheet's own now, drawn nowhere in Now Playing
    for page in ("UpNextScreen(", "InfoView(", "EQSheet(", "EQScreen("):
        assert page not in now, f"{page} is the sheet's"
    for flag in ("showsUpNext", "showsInfo", "showsEQ"):
        assert flag not in now, f"{flag}: one sheet, one flag"
    #? open() opens it on a tab, or moves the sheet up to it in place - the one way it opens
    opener = member(now, "func open")
    assert [line.strip() for line in opener.strip().splitlines()] == ["sheetTab = tab", "sheetUp = true"]
    assert now.count("sheetUp = true") == 1 and "sheetUp = false" not in now.replace("var sheetUp = false", "")


def test_the_sheet_draws_one_tab_under_its_back_link_and_strip():
    sheet = code(SHEET)
    body = body_of(sheet)
    #? (R3b) each page draws the top itself (`sheetTop`, its own buttons at its right): `‹ Now Playing` - the sheet's
    #? own put-down, read outside every page's stack - in the page's bar, the strip its first row
    assert "let top = SheetTop(tab: $tab, close: dismiss)" in body
    bar = member(sheet, "struct SheetTopBar<Trailing: View>: ViewModifier")
    order = [bar.index(part) for part in ("PhoneStrip(options: NowPlayingTabs.strip, words: NowPlayingTabs.Words.tab, shown: top.tab,",
                                          "\n            content\n",
                                          "PhoneBack(words: NowPlayingTabs.Words.back) { top.close() }")]
    assert order == sorted(order)
    #? one tab's page at a time, each once: the tab is the page drawn
    assert body.count("switch tab {") == 1
    for page in ("case .upNext:\n                UpNextScreen(sheet: top)",
                 "case .info:\n                InfoView(sheet: top, picked: $infoTab)",
                 "case .eq:\n                EQSheet(sheet: top)"):
        assert page in body, page
    for page in ("UpNextScreen(", "InfoView(", "EQSheet("):
        assert sheet.count(page) == 1, page
    #? no Lyrics in the sheet: they take the cover's place (James, 25 Nov, answer 2)
    for lyrics in ("Lyrics", ".lyrics"):
        assert lyrics not in sheet, lyrics
    tabs = bare(TABS)
    cases = re.findall(r"case (\w+)", member(tabs, "enum Tab: String, Sendable, CaseIterable"))
    assert cases == ["upNext", "info", "eq"], cases
    assert "public static let strip: [Tab] = [.upNext, .info, .eq]" in tabs


# ----------------------------------------------------------------------------- the bottom row

def test_the_bottom_row_is_five_in_the_footers_place():
    now = bare(NOW_PLAYING)
    content = member(now, "func content")
    #? under the transport, where the footer was - the chip's band between them (R3's review)
    assert content.index("transport\n") < content.index("SpeedChipBand(shown: chipShown)") < content.index("bottomRow")
    assert "func footer" not in now and "lyricsButton" not in now
    row = member(now, "var bottomRow: some View")
    assert "ForEach(NowPlayingTabs.row, id: \\.self) { (button: NowPlayingTabs.Button) in" in row
    for case in ("case .lyrics:\n                    lyricsItem", "case .output:\n                    OutputItem()",
                 "case .eq:\n                    EQRowItem { tapped(.eq) }",
                 "case .upNext, .info:\n                    sheetItem(button)"):
        assert case in row, case
    #? each as the tab bar's item with no bar: its words under its icon, never lit
    assert "PhoneTabItem(words: words, shown: false, spoken: spoken, action: { tapped(button) })" in now
    assert "lit:" not in now
    #? the output is AirPlay's own button under its whole column, named under its glyph for the route
    output = member(now, "struct OutputItem: View")
    assert "AirPlayButton(glyph: false, playsTo: name)" in output
    assert "eq.settings.setting(for: eq.route).shownName" in output
    assert "outputItem" not in now and "reach" not in output, "no target of its own round the icon: the column is it"
    #? the speed chip over the gap between the output and Info, in a band of its own (test_ios_nowplaying_row.py)
    assert "SpeedChip(speed: player.speed)" in member(now, "struct SpeedChipBand: View")
    tabs = bare(TABS)
    assert "public static let row: [Button] = [.upNext, .lyrics, .output, .info, .eq]" in tabs
    assert "public static let chipBetween: (Button, Button) = (.output, .info)" in tabs


def test_each_button_opens_what_it_names_and_lyrics_never_the_sheet():
    now = bare(NOW_PLAYING)
    tapped = member(now, "func tapped")
    assert "switch NowPlayingTabs.opens(button) {" in tapped
    assert "case .tab(let tab):\n            open(tab)" in tapped
    assert "case .lyrics:\n            lyricsTapped()" in tapped
    assert "case .output:\n            break" in tapped
    #? Lyrics: on and off in the cover's place, never the sheet
    lyrics = member(now, "func lyricsTapped")
    for sheet in ("open(", "sheetUp", "sheetTab"):
        assert sheet not in lyrics, sheet
    assert "lyrics.showing = tapped.lyricsOn" in lyrics
    assert "action: { tapped(.lyrics) }" in member(now, "var lyricsItem: some View")
    tabs = bare(TABS)
    opens = member(tabs, "public static func opens(_ button: Button) -> Opens")
    assert "case .lyrics: return .lyrics" in opens
    assert opens.count(".tab(") == 3 and "case .upNext: return .tab(.upNext)" in opens
    #? the ••• up beside the look button, the EQ out of it for the row
    top = member(now, "func topRow")
    assert top.index("NamedLookButton(showingTurntable:") < top.index("menu(track)")
    # (R4b) the compact top: the ••• and the look button at its right, Close at its left
    assert top.index("closeButton") < top.index("} trailing: {") < top.index("NamedLookButton(")
    assert "menu(track)" not in member(now, "var bottomRow: some View")
    menu = member(now, "func menu")
    assert "onInfo: { open(.info) }, onEQ: nil," in menu


# ----------------------------------------------------------------------------- a shared EQ file

def test_a_shared_eq_file_opens_the_sheet_on_eq():
    now = bare(NOW_PLAYING)
    shared = member(now, "func shared")
    assert "guard navigation.eqImport != nil, navigation.eqImportPage == nil, !navigation.eqPreviewUp else { return }" in shared
    assert "switch NowPlayingTabs.shared(sheet: sheetUp ? sheetTab : nil, coverUp: viewing != nil) {" in shared
    assert "case .show(let tab):\n            open(tab)" in shared
    assert "case .waitThenShow:\n            eqWaits = true\n            CoverViewing.put(nil, into: $viewing)" in shared
    #? the sheet up on the Queue or Info is never left there: no early return on it
    assert "if sheetUp" not in shared and "return }" not in shared.split("guard", 1)[1].split("\n", 1)[1]
    after = member(now, "func eqAfterSheet")
    assert "if navigation.eqImport != nil && navigation.eqImportPage == nil { open(.eq) }" in after
    tabs = bare(TABS)
    rule = member(tabs, "public static func shared(sheet: Tab?, coverUp: Bool) -> Shared")
    assert [line.strip() for line in rule.strip().splitlines()] == [
        "if sheet == nil && coverUp { return .waitThenShow(.eq) }", "return .show(.eq)"]
    #? the EQ's own wait (3.9) is EQSheet's, unchanged: the sheet's EQ tab is it
    assert "EQSheet(sheet: top)" in code(SHEET)


# ----------------------------------------------------------------------------- a shared EQ file on the Mac

ROUTES = APP / "Shared" / "Routes.swift"
FRAME = APP / "Root" / "DesktopFrame.swift"
TABS_ROOT = APP / "Root" / "MainTabs.swift"
EQ_ROUTE = APP / "EQ" / "EQRoute.swift"


def test_a_shared_eq_file_on_the_mac_shows_in_the_docks_eq():
    """R3's review, 5: a shared file, or File > Import EQ File…, opened the frame's EQ sheet over the dock's EQ tab - a
    second EQ page over the first, undoing slice 3's one EQ. On the Mac it shows the dock's EQ tab now, the preview over
    it as the sheet had it; the phone's path is as it was."""
    routes = bare(ROUTES)
    share = member(routes, "func share")
    lines = [line.strip() for line in share.strip().splitlines()]
    assert lines == ["eqImport = item", "guard !eqPreviewUp else { return }", "eqImportPage = nil",
                     "switch SharedEQFile.shows(device: Platform.device, nowPlayingShown: nowPlayingShown) {",
                     "case .dock: showPanel(.eq)", "case .sheet: eqImportSheet = true", "case .nowPlaying: break", "}"], lines
    assert routes.count("eqImportSheet = true") == 1
    dock = bare(DOCK)
    rule = member(dock, "public static func shows(device: Device, nowPlayingShown: Bool) -> SharedEQFile")
    assert [line.strip() for line in rule.strip().splitlines()] == [
        "if MacFrame.drawsDesktop(device) { return .dock }", "return nowPlayingShown ? .nowPlaying : .sheet"]
    #? the frame presents no EQ sheet: the dock's EQ is the Mac's one
    frame = bare(FRAME)
    assert "eqImportSheet" not in frame and "EQSheet(" not in frame
    #? the dock's EQ: the preview over it, once it has been up a moment - EQSheet's wait and binding, as the sheet had
    panels = bare(PANELS)
    dock_eq = member(panels, "struct DockEQ: View")
    assert ("ready && navigation.eqImport != nil && navigation.eqImportPage == nil" in dock_eq
            and "if !up { navigation.importAnswered() }" in dock_eq)
    assert "EQImportSheetContent()\n                .macSheet()" in dock_eq
    assert "try? await Task.sleep(for: .milliseconds(400))\n            ready = true" in dock_eq
    assert dock_eq.index("NavigationStack(path: $stack.path) {") < dock_eq.index(".appSheet(isPresented:")
    #? the phone's path, untouched: MainTabs' EQ sheet, EQSheet's own preview and wait
    tabs_root = bare(TABS_ROOT)
    assert ".appSheet(isPresented: $navigation.eqImportSheet) {\n            EQSheet()" in tabs_root
    sheet = member(bare(EQ_ROUTE), "struct EQSheet: View")
    for line in ("ready && navigation.eqImport != nil && navigation.eqImportPage == nil",
                 ".eqFileDrop { (item: EQImportItem) -> Void in navigation.share(item) }",
                 "try? await Task.sleep(for: .milliseconds(400))", ".environment(\\.eqDone, dismiss)"):
        assert line in sheet, line


def test_a_dock_tab_with_nothing_to_be_about_says_so():
    """R3's review, 6: Info with nothing selected and nothing playing drew a blank InfoView with no heading, and a
    folder tab clicked to the Queue with nothing queued an empty list. Each says "Nothing playing" now (MacDock.empty),
    under its name - (R16) in the dock's own type, quiet and centred, no title and no Done (Escape is the panel's)."""
    panels = bare(PANELS)
    panel = member(panels, "struct MacPanel: View")
    body = member(panel, "var body: some View")
    empty = "if let words = MacDock.empty(tab, playing: player.current != nil, selected: selection?.subject != nil) {"
    assert empty in body
    assert body.index(empty) < body.index("DockEmpty(words: words)") < body.index("page")
    assert "switch tab {" not in body and "switch tab {" in member(panel, "var page: some View")
    shown = member(panels, "struct DockEmpty: View")
    for part in ("Text(words)", ".font(DockType.words)", ".foregroundStyle(DWPalette.t3)", ".multilineTextAlignment(.center)"):
        assert part in shown, part
    for gone in (".navigationTitle(", "DockDone(", "NavigationStack", "Palette.quiet"):
        assert gone not in shown, gone
    #? Info's own subject is the same rule's: never InfoView without a song playing
    info = member(panels, "struct DockInfo: View")
    assert "MacDock.infoSubject(selected: selected.map(Self.kind), playing: player.current != nil)" in info
    rule = member(bare(DOCK), "public static func empty")
    assert "case .upNext: return playing ? nil : Words.nothingPlaying" in rule
    assert "infoSubject(selected: selected ? .album : nil, playing: playing) == .nothing" in rule


# ----------------------------------------------------------------------------- the drag down

def test_the_drag_down_still_closes_now_playing():
    now = bare(NOW_PLAYING)
    grip = member(now, "var grip: some Gesture")
    assert "DragGesture(minimumDistance: PlayerWords.dragStartDistance, coordinateSpace: .global)" in grip
    assert ".onChanged { value in dragY = max(0, value.translation.height) }" in grip
    assert "if max(0, value.translation.height) > PlayerWords.dismissDistance {\n                    close()" in grip
    assert member(now, "func close").strip() == "navigation.nowPlayingShown = false"
    content = member(now, "func content")
    assert "topRow(track)\n                .contentShape(Rectangle())\n                .gesture(grip)" in content
    assert ".highPriorityGesture(grip)" in content
    assert ".offset(y: dragY)" in body_of(now)


# ----------------------------------------------------------------------------- EQScreen's List, the Mac's

#? (R3b) EQScreen's List - the Mac's side panel's page, `listPage` and its sections, and (R3b's review) its filter row,
#? EQFilterRowView - with its comments blanked, as R3 left it: R3b redrew the phone's EQ as groups of its own beside it
#? (test_ios_nowplaying_pages_look.py; the phone's filter row is EQPhoneFilterRow), and left the Mac's List alone.
#? (the app's fonts, 25 Nov) only these changed since: the hand preamp's value, deadwax's own preamp's (iEQ's mono) and
#? a filter row's numbers in the readout face (`.monospacedDigit()` did nothing in Libre Franklin) - test_ios_palette.py's
#? TICKING - and both preamp rows on their label's baseline (`.labeledContentStyle(.readout)`: centred, a readout's
#? shorter line set it higher - test_ios_readout_rows.py).
EQ_SCREEN_LIST = "d3d92f6a41ac5e514ff0156197ea5fe1db8f58a2087585669c46c4a9535a966b"


def mac_filter_row(text: str) -> str:
    """EQFilterRowView, the Mac's List's filter row, comments blanked: its declaration to its closing brace."""
    code_text = reader.views(text)[0]
    start = text.index("struct EQFilterRowView: View {")
    return code_text[start:text.index("\n}\n", start) + 2]


def the_list(text: str) -> str:
    code_text = reader.views(text)[0]
    page = code_text[text.index("    private func listPage("):text.index("    /// What the suggestion is asked again on:")]
    sections = code_text[text.index("    // MARK: the sections"):text.index("    // MARK: the phone's groups")]
    lines = [line.rstrip() for line in (page + sections + mac_filter_row(text)).splitlines()]
    return "\n".join(line for line in lines if line.strip())


def test_eq_screens_list_is_as_r3_left_it():
    text = EQ_SCREEN.read_text(encoding="utf-8")
    assert hashlib.sha256(the_list(text).encode()).hexdigest() == EQ_SCREEN_LIST
    #? (R3b's review) the Mac's filter row takes the List's font and accent: no nil font or tint, which resets them, no
    #? tint at all, the type's line in the List's own font (only the detail lines set theirs, as R3 had them), and no
    #? phone path - the phone's row is a struct of its own
    row = mac_filter_row(text)
    for reset in (".font(nil", ".tint(", "phone", "Phone", "PhoneLook", "toggleStyle", "Platform."):
        assert reset not in row, reset
    assert re.findall(r"\.font\(([^()]*(?:\([^()]*\))?[^()]*)\)", row) == ["Typeface.readout(.footnote)",
                                                                           "Typeface.footnote"]
    #? the Mac's List draws the Mac's row; the phone's groups the phone's, never the Mac's
    groups = code(EQ_SCREEN)[text.index("    // MARK: the phone's groups"):]
    assert "EQFilterRowView(row:" in the_list(text) and "EQPhoneFilterRow(" not in the_list(text)
    assert "EQPhoneFilterRow(row:" in groups and "EQFilterRowView(" not in groups
    reads = [line.strip() for line in reader.views(text)[0].splitlines() if "inSidePanel" in line]
    assert reads == ["@Environment(\\.inSidePanel) private var inSidePanel",
                     ".navigationBarTitleDisplayMode(done == nil && !inSidePanel ? .large : .inline)"], reads


# ----------------------------------------------------------------------------- the dock's own words and tokens

def test_the_dock_and_the_sheet_draw_with_tokens_alone():
    for path in (PANELS, SHEET):
        text = bare(path)
        for raw in ("Color(red:", "Color(white:", "Color(hex", "UIColor(", ".cornerRadius(", ".font(.system(", "Font.system("):
            assert raw not in text, f"{path.name}: {raw}"
        assert not re.search(r"\bradius: \d", text) and "Color." not in text, f"{path.name}: a raw colour or radius"
    panels = bare(PANELS)
    assert ".font(DockType.heading)" in panels and ".foregroundStyle(DWPalette.t2)" in panels
    assert ".background(DWPalette.panel)" in panels
    dock = bare(DOCK)
    assert "public static let tabs: [Tab]" not in dock, "Sources is in the strip only while a Get page is open"


# ----------------------------------------------------------------------------- Queue on both

def test_no_word_the_app_shows_says_up_next():
    """James, 25 Nov (3.8, answer 3: "Queue on both"): every word the app shows that said "Up Next" says Queue on the
    phone and the Mac - its titles, notices, menus and VoiceOver's labels and hints. The types and files keep the name;
    the web's vectors keep its word (the Core tests read them through QueueWord)."""
    #? the code with its comments blanked: an identifier (UpNextWords, upNext) never holds a space, so two words are a
    #? literal's
    left = []
    for root in (APP, CORE):
        for path in sorted(root.rglob("*.swift")):
            for line in code(path).splitlines():
                if re.search(r"\bup[ \t]+next\b", line, re.IGNORECASE):
                    left.append(f"{path.relative_to(IOS)}: {line.strip()}")
    assert not left, left
    #? MacFrame's panel keeps the web's raw value - a key, never shown
    assert 'case upNext = "upnext"' in code(CORE / "MacFrame.swift")
    for device in ("iphone", "mac"):
        words = json.loads((WORDS / f"{device}.json").read_text(encoding="utf-8"))
        said = [f"{key}: {value}" for key, value in words.items()
                if isinstance(value, str) and re.search(r"up next", value, re.IGNORECASE)]
        assert not said, said
        assert words["DownloadWords.everyLine[3]"] == "Download the Queue"
        assert words["DownloadWords.everyLine[58]"] == "Downloading 23 songs from the Queue"
    assert 'public static let title = "Queue"' in code(CORE / "UpNextView.swift")
