"""
The Queue, Info and the EQ inside Now Playing's sheet, redrawn (the redesign, slice R3b - notes/ios.md "The redesign,
slice R3b: the Queue, Info and the EQ inside"; the build plan's 3.4). Core holds the words and the rules - QueueTimeLeft,
QueuePageWords, AboutCard.played and .facts, EQEditorRules.leaving (QueueTimeLeftTests, InfoPlayedTests,
EQPhonePageTests); test_ios_panels_look.py holds the sheet itself. This holds the drawing's promises:

  - Each page draws the sheet's top (`sheetTop`): `‹ Now Playing`, the strip, the page's own at its right - the EQ's
    only at its stack's root, so a page pushed there keeps its own bar.
  - The Queue: History, Clear and Edit at the top - History and Clear in a ••• from xLarge, worked out for a 375-point
    phone - the song playing as the selected row first (the review: no heading over it, nor over Playing Next's), "Next
    from …", rows 48, and Shuffle, Repeat and the time left at the foot; the time left a small view of its own (the
    player's position is busy). The Mac's dock gets the time left, in the status bar's type at its left.
  - Info: This song and The album as the look's groups of kv rows (AboutCard.facts, Played and Size among them), the
    day said against a `now` that moves at midnight; Go to album and Go to artist. The Mac's dock's song card says the
    same facts.
  - The EQ: "EQ on" a real Toggle drawn as the purple switch (never a picture of one), its words folded away at
    xxxLarge, worked out for a 375-point phone; the knobs round; the page follows the route only while it is on top, as
    before; the phone's groups make every EQModel call the List makes, and no other - so the sound is as it was - its
    swipes and long press long presses on the same rows; the filters' switches the phone's own; the output's button
    says the page's output to VoiceOver; a filter's editor applies what was typed as it goes.
  - Tokens alone: no raw colour, corner or face in any of the pages redrawn.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"
SHEET = APP / "Player" / "NowPlayingSheet.swift"
QUEUE = APP / "UpNext" / "UpNextScreen.swift"
INFO = APP / "Info" / "InfoView.swift"
EQ_SCREEN = APP / "EQ" / "EQScreen.swift"
EQ_ROUTE = APP / "EQ" / "EQRoute.swift"
SLIDERS = APP / "EQ" / "EQSliders.swift"
CURVE = APP / "EQ" / "EQCurveView.swift"
OUTPUTS = APP / "EQ" / "EQOutputViews.swift"
EDITOR = APP / "EQ" / "EQFilterEditor.swift"
SWITCH = APP / "Phone" / "PhoneSwitch.swift"
TIME_LEFT = CORE / "QueueTimeLeft.swift"
EQ_PHONE = CORE / "EQPhonePage.swift"
REDRAWN = (SHEET, QUEUE, INFO, EQ_SCREEN, SLIDERS, CURVE, OUTPUTS)


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_pages_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
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
    found = list(re.finditer(r"\b" + re.escape(declaration) + r"(?!\w)[^{]*\{", text))
    assert len(found) == 1, f"{declaration} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def page_body(text: str) -> str:
    """The file's own view's body: its first `var body`, the page's (the private views after it have theirs)."""
    found = re.search(r"\bvar body: some View \{", text)
    assert found, "no body"
    return block(text, found.end() - 1)


def between(path: Path, start: str, end: str) -> str:
    """The code (comments blanked) from the comment `start` to the comment `end` - found in the source as written, as
    the blanking keeps every offset."""
    source = path.read_text(encoding="utf-8")
    text = code(path)
    assert len(text) == len(source)
    return text[source.index(start):source.index(end)]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


# ----------------------------------------------------------------------------- the sheet's top, each page's

def test_each_page_draws_the_sheets_top():
    sheet = code(SHEET)
    for page in ("UpNextScreen(sheet: top)", "InfoView(sheet: top, picked: $infoTab)", "EQSheet(sheet: top)"):
        assert sheet.count(page) == 1, page
    bar = member(sheet, "struct SheetTopBar<Trailing: View>: ViewModifier")
    order = [bar.index(part) for part in ("PhoneStrip(options: NowPlayingTabs.strip, words: NowPlayingTabs.Words.tab, shown: top.tab,",
                                          "\n            content\n", "PhoneBack(words: NowPlayingTabs.Words.back) { top.close() }")]
    assert order == sorted(order), "the strip, the page under it, `‹ Now Playing` in its bar"
    #? the sheet's About or Debug is the sheet's own: kept while the strip shows another tab (R3's review, 9)
    assert "@State private var infoTab: InfoTab = .about" in sheet
    assert ".presentationBackground(DWPalette.panel)" in sheet
    #? each page draws it - the Queue and Info as the page's top, the EQ's only at its stack's root
    assert "sheetTop(sheet, trailing: phone)" in code(QUEUE)
    assert ".sheetTop(sheet) {}" in code(INFO)
    screen = code(EQ_SCREEN)
    assert ".sheetTop(sheet) {\n                    onSwitch(output, on: setting.on)\n                    more(output, setting: setting, advanced: advanced)" in screen
    route = code(EQ_ROUTE)
    assert "EQScreen(opened: .now, sheet: sheet)" in member(route, "struct EQSheet: View")
    destination = member(route, "struct EQDestination: View")
    assert "sheet:" not in destination, "a page pushed on the sheet's stack has its own bar and Back"
    #? in the sheet the EQ's root has no Done - `‹ Now Playing` puts the sheet down; elsewhere Done as before
    top = member(screen, "private func top<Content: View>")
    assert top.index("if let sheet {") < top.index("} else {") < top.index(".eqDoneButton()")
    assert top.count(".eqDoneButton()") == 1 and screen.count(".eqDoneButton()") == 1


# ----------------------------------------------------------------------------- the Queue

#? Apple's text styles at the sizes the top is drawn at (headline for `‹ Now Playing`, footnote for a small button's
#? words - Typeface.Phone's .back and Typeface.Look's .smallButton scale relative to them)
HEADLINE = {"large": 17, "xLarge": 19, "xxLarge": 21, "xxxLarge": 23}
FOOTNOTE = {"large": 13, "xLarge": 15, "xxLarge": 17, "xxxLarge": 19}
#? a proportional face's mean advance as a share of its size: Noto Sans's is about 0.5 em - taken wide
ADVANCE = 0.55
PHONE = 375
BAR_SIDE = 16


def words_width(words: str, points: float) -> float:
    return len(words) * ADVANCE * points


def test_the_queues_top_fits_a_375_point_phone_and_folds_from_xlarge():
    """iQueue's top: `‹ Now Playing` at the left; History, Clear and Edit small buttons at the right (13.5 words, 11 in
    either side, 8 apart). Worked out for 375 points: the three fit at Large; from xLarge History and Clear fold into a
    ••• beside Edit, which fits at xxxLarge, where the top stops growing."""
    queue = code(QUEUE)
    assert "static func folds(_ size: DynamicTypeSize) -> Bool {\n        size > .large\n    }" in queue
    top = member(queue, "private func phoneTop")
    assert top.index("if Self.folds(dynamicTypeSize) {") < top.index("Button(UpNextWords.history) { toHistory(proxy) }")
    assert "Image(systemName: \"ellipsis\")" in top and ".accessibilityLabel(QueuePageWords.more)" in top
    assert top.count("Button(UpNextWords.history) { toHistory(proxy) }") == 2, "in the ••• and as a button"
    assert top.count("Button(UpNextWords.clear, action: clear)") == 2
    assert "Button(editing ? UpNextWords.done : UpNextWords.edit) {" in top
    sheet = code(SHEET)
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in member(sheet, "struct SheetTopItems<Leading: View, Trailing: View>: ToolbarContent")
    pad, gap = 11, 8

    def button(words: str, size: str) -> float:
        return words_width(words, 13.5 * FOOTNOTE[size] / 13) + 2 * pad

    def width(size: str, folded: bool) -> float:
        back = words_width("‹ Now Playing", 17 * HEADLINE[size] / 17)
        if folded:
            right = FOOTNOTE[size] * 1.2 + 2 * pad + gap + button("Done", size)
        else:
            right = button("History", size) + gap + button("Clear", size) + gap + button("Edit", size)
        return BAR_SIDE + back + gap + right + BAR_SIDE

    assert width("large", folded=False) <= PHONE, width("large", folded=False)
    #? and at xLarge the three wouldn't: the fold is where it has to be, no later
    assert width("xLarge", folded=False) > PHONE, width("xLarge", folded=False)
    for size in ("xLarge", "xxLarge", "xxxLarge"):
        assert width(size, folded=True) <= PHONE, (size, width(size, folded=True))


def test_the_queues_rows_and_foot_on_the_phone():
    queue = code(QUEUE)
    body = page_body(queue)
    #? (R3b's review) no heading stacked under the sheet's top: the song playing's selected row is the page's first - the
    #? row the sheet is scrolled to - Playing Next's songs follow it, and "Next from …" heads the list
    assert "playingRow(playing)\n                                        .id(Self.card)" in body
    assert "heading(QueuePageWords.nowPlaying)" not in queue and "heading(UpNextWords.playingNext)" not in queue
    assert "nowPlaying" not in bare(TIME_LEFT)
    assert len(re.findall(r"(?<![\w.])heading\(", body)) == 1, "the list's alone"
    assert "heading(QueuePageWords.heading(list.title))" in body
    assert "QueuePageWords.showsLines(list.rows, title: list.title)" in body
    playing = member(queue, "private func playingRow")
    for part in (".foregroundStyle(DWPalette.selt)", ".lookHeight(DWLook.here.tallRowHeight)", ".background(DWPalette.selbg)",
                 ".overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))", ".accessibilityElement(children: .combine)"):
        assert part in playing, part
    label = member(queue, "private func rowLabel")
    assert ".lookHeight(DWLook.here.rowHeight)" in label
    assert "QueueRowHeight(phone: phone)" in member(queue, "private func editRow")
    #? the Mac's rows keep their own height: on the Mac lookHeight is the row's exact height, so never one of 0 there
    for path in (QUEUE, EQ_SCREEN):
        assert not re.search(r"lookHeight\([^()]*\?[^()]*: 0\)", flat(code(path))), path.name
    #? the foot: Shuffle, Repeat and the time left - on one line where they fit, else the time on its own under them
    foot = member(queue, "private func phoneFoot")
    assert foot.index("ViewThatFits(in: .horizontal) {") < foot.index("modeButtons") < foot.index("QueueTimeLeftLine(view: view)")
    assert foot.count("QueueTimeLeftLine(view: view)") == 2 and ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in foot
    modes = member(queue, "private var modeButtons: some View")
    assert "Button(action: toggleShuffle)" in modes and "Button(action: cycleRepeat)" in modes
    assert ".accessibilityAddTraits(player.shuffle ? .isSelected : [])" in modes
    #? (R3b's review) the Mac's at the dock's left, as the status bar's words are
    assert "HStack(spacing: 0) {\n            QueueTimeLeftLine(view: view)\n            Spacer(minLength: 0)\n        }" in member(
        queue, "private func macFoot")
    #? the Mac's side panel keeps its List: its Edit, its Done with Escape, its section headers with Clear
    mac = member(queue, "private func macToolbar")
    assert "placement: .cancellationAction" in mac and "placement: .confirmationAction" in mac
    assert "Button(UpNextWords.clear, action: clear)\n                                                    .buttonStyle(.borderless)" in body


def test_the_time_left_is_a_small_view_of_its_own_reading_the_rows_drawn():
    """The player's position moves twice a second: only the time left's own view reads it, so the list never redraws
    for it; and the words are Core's, from the rows the page draws (UpNextView), never the queue's own order."""
    queue = code(QUEUE)
    line = member(queue, "private struct QueueTimeLeftLine: View")
    assert "QueueTimeLeft.words(view, position: player.shownPosition, speed: player.speed)" in line
    outside = queue.replace(line, "")
    assert "shownPosition" not in outside and "player.speed" not in outside
    #? (R3b's review) on the Mac the status bar's 11.5 in its own type - not mono - leading; the phone's mono, trailing
    assert ".font(Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.mono(.extraSmall))" in line
    assert ".multilineTextAlignment(Platform.mac ? .leading : .trailing)" in line
    words = bare(TIME_LEFT)
    rule = member(words, "public static func words(_ view: UpNextView, position: Double, speed: Double = 1) -> String?")
    assert "let after = view.added + (view.list?.rows ?? [])" in rule
    assert "history" not in rule, "History never counts: it has played"
    assert "var seconds = max(length, 0) - heard" in rule, "what is left of the song playing, never the whole song"
    #? (R3b's review) never "0 min left" nor "over 0 min left": the time part is `left`'s, nil where it would be
    assert "left(seconds / rate, least: least)" in rule and "span(" not in rule
    left = member(words, "static func left(_ seconds: Double, least: Bool) -> String?")
    assert "guard seconds.isFinite, seconds > 0 else { return nil }" in left
    assert "(seconds / 60).rounded(.down)" in left and "minutes == 0 ? nil :" in left


# ----------------------------------------------------------------------------- Info

def test_info_on_the_phone_is_this_song_and_the_album_as_groups():
    info = code(INFO)
    about = member(info, "private func phoneAbout")
    assert about.index("PhoneGroup(legend: AboutFactWords.thisSong) {") < about.index("PhoneGroup(legend: AboutFactWords.theAlbum) {")
    assert "ForEach(format + facts.song + rest, id: \\.label)" in about
    assert "InfoEQRow()" in about, "the EQ's row a view of its own: the EQ's changes redraw it alone"
    assert "eq." not in about
    assert "NavigationLink(value: AlbumInfoPush(album: album)) {" in about
    goes = member(info, "private func goes")
    assert "navigation.openAlbum(route)" in goes and "goToArtist(artistID, name: track.artist)" in goes
    assert "InfoButtonWords(words: AboutFactWords.goToAlbum)" in goes and "InfoButtonWords(words: AboutFactWords.goToArtist)" in goes
    assert "typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Self.goesGap))" in goes
    artist = member(info, "private func goToArtist")
    assert "navigation.nowPlayingShown = false" in artist
    assert "navigation.open(.artist(ArtistRoute(id: id, preview: Artist(id: id, name: name))))" in artist
    #? a fact's row is one element, its value under its label at the accessibility sizes
    kv = member(info, "private struct InfoKV: View")
    assert ".accessibilityElement(children: .combine)" in kv and "typeSize.isAccessibilitySize" in kv
    assert ".font(row.mono ? Typeface.Phone.mono(.small) : Typeface.Phone.text(.small))" in kv
    #? an admin's About or Debug, the sheet's own choice
    page = member(info, "private func phonePage")
    assert "DWSegmented(options: tabs, words:" in page and "chosen: picked," in page


def test_played_is_said_against_a_day_that_moves_at_midnight():
    info = code(INFO)
    assert "@State private var now = ArtistTotals.now()" in info
    body = page_body(info)
    assert ".onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in\n            now = ArtistTotals.now()" in body
    assert ".onAppear { now = ArtistTotals.now() }" in body
    facts = member(info, "private func aboutFacts")
    assert "folders: folders, size: song?.size, bitRate: song?.bitRate, now: now)" in facts
    #? (R3b's review) Size: the file's size and bit rate from the song as the player has it (Navidrome's)
    assert "let song = player.song(for: entry)" in facts
    assert "Date()" not in info
    #? the Mac's dock says the same facts - Played among them - under the song's name
    about = member(info, "private func about")
    assert "ForEach(facts.song, id: \\.label) { (row: InfoRow) in\n                LabeledContent(row.label, value: row.value)" in about
    assert "about.song.lines" not in about
    core = bare(CORE / "About.swift")
    played = member(core, "public static func played")
    assert "guard let plays = WebText.whole(counted?.playCount), plays > 0 else { return nil }" in played
    assert "ArtistTotals.lastPlayedWords(when, now: now, zone: zone)" in played


# ----------------------------------------------------------------------------- the EQ

def test_eq_on_is_a_real_toggle_drawn_as_the_purple_switch():
    screen = code(EQ_SCREEN)
    switch = member(screen, "private func onSwitch")
    assert switch.strip().startswith("Toggle(isOn: Binding<Bool>(get: { on }, set: { (now: Bool) -> Void in\n            eq.setOn(now, for: output)")
    assert ".toggleStyle(.phoneSwitch)" in switch and "Image(" not in switch
    assert ".accessibilityLabel(EQWords.Screen.toggleSaid(output.name))" in switch
    #? in the sheet's top, and on the output's card off it (You's page)
    assert "if sheet == nil {\n                onSwitch(output, on: on)" in member(screen, "private func outputCard")
    #? the style is a real Toggle to VoiceOver - its label, its value, a double tap
    style = code(SWITCH)
    assert "accessibilityRepresentation {\n            Toggle(isOn: configuration.$isOn) {" in style
    words = member(code(EQ_PHONE), "extension EQWords.Screen")
    assert 'public static let on = "EQ on"' in words


def test_the_eqs_top_fits_a_375_point_phone_and_folds_at_xxxlarge():
    """(R3b's review) iEQ's top: `‹ Now Playing` at the left; "EQ on" at the small size (13), the switch (46) and the •••
    (a small button: its glyph about 1.2 em of 13.5, 11 either side) at the right, 8 apart - the switch's words and its
    face 8 either side of the Spacer between them, both counted. Worked out for 375 points: whole through xxLarge, with
    a margin to spare; at xxxLarge, where the top stops growing, it wouldn't be, so the words fold away and the switch
    stands alone - VoiceOver's name for it the same."""
    screen = code(EQ_SCREEN)
    assert "static func folds(_ size: DynamicTypeSize) -> Bool {\n        size > .xxLarge\n    }" in screen
    switch = member(screen, "private func onSwitch")
    assert switch.index("if sheet == nil || !Self.folds(dynamicTypeSize) {") < switch.index("Text(EQWords.Screen.on)")
    assert ".accessibilityLabel(EQWords.Screen.toggleSaid(output.name))" in switch
    top = member(screen, "private func top<Content: View>")
    assert top.index("onSwitch(output, on: setting.on)") < top.index("more(output, setting: setting, advanced: advanced)")
    items = member(code(SHEET), "struct SheetTopItems<Leading: View, Trailing: View>: ToolbarContent")
    assert "HStack(spacing: CGFloat(PhoneLook.topGap)) {" in items and ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in items
    assert "Spacer(minLength: 0)\n                PhoneSwitchFace(on: configuration.isOn)" in code(SWITCH)
    gap, pad, face, spare = 8, 11, 46, 16

    def width(size: str, folded: bool) -> float:
        back = words_width("‹ Now Playing", 17 * HEADLINE[size] / 17)
        words = 0 if folded else words_width("EQ on", 13 * FOOTNOTE[size] / 13) + gap
        more = 13.5 * FOOTNOTE[size] / 13 * 1.2 + 2 * pad
        return BAR_SIDE + back + gap + words + gap + face + gap + more + BAR_SIDE

    for size in ("large", "xLarge", "xxLarge"):
        assert width(size, folded=False) <= PHONE - spare, (size, width(size, folded=False))
    #? and at xxxLarge it wouldn't, with a margin: the fold is where it has to be, no earlier
    assert width("xxxLarge", folded=False) > PHONE - spare, width("xxxLarge", folded=False)
    assert width("xxxLarge", folded=True) <= PHONE - 3 * spare, width("xxxLarge", folded=True)


def test_the_knobs_stay_round():
    sliders = code(SLIDERS)
    knob = member(sliders, "private var knob: some View")
    assert knob.count("Circle()") == 2, "round on both: round stays round"
    for square in ("Rectangle()", "boxShape", "buttonShape", "RoundedRectangle", "Capsule"):
        assert square not in knob, square
    assert ".fill(DWPalette.switchKnob)" in knob and "DWPalette.switchKnobDrop" in knob
    assert "knob\n                .frame(width: EQSliders.knob, height: EQSliders.knob)" in sliders
    #? the rest square on the phone: the track a well, the chip the card's colour
    track = member(sliders, "private var trackFace: some View")
    assert "DWCorners.boxShape" in track and "DWPalette.well" in track


def test_the_eq_follows_the_route_only_while_it_is_on_top():
    screen = code(EQ_SCREEN)
    on_top = member(screen, "private var onTop: Bool")
    assert flat(on_top).strip() == ("appeared && ask == nil && forgetting == nil && !navigation.eqPreviewUp "
                                    "&& !(done == nil && (navigation.nowPlayingShown || navigation.eqImportSheet))")
    body = page_body(screen)
    assert ".onAppear { appeared = true }\n        .onDisappear { appeared = false }" in body
    assert ".onChange(of: onTop, initial: true) { _, top in\n            if top { show() } else { self.page?.covered() }" in body
    assert ".onChange(of: eq.route.key) { _, route in\n            if self.page?.heard(route: route) == true { switched() }" in body
    assert "if top { show() }" in body and body.count("show()") == 1


def calls(text: str) -> set[str]:
    return set(re.findall(r"\beq\.(\w+)\s*[(=]", text))


def test_the_phones_groups_make_the_lists_calls_and_no_others():
    """Every control on the phone's groups does what the List's did - the same EQModel call - and nothing else, so the
    sound is as it was: the redraw is of the controls alone. The groups have no swipes (no List): (R3b's review) the
    List's swipes and its long press are long presses on the same rows (test_the_lists_swipes_are_long_presses_here);
    Not now is a button beside the suggestion, Rename and Forget VoiceOver's actions on Other outputs' rows too."""
    screen = code(EQ_SCREEN)
    sections = between(EQ_SCREEN, "// MARK: the sections", "// MARK: the phone's groups")
    groups = between(EQ_SCREEN, "// MARK: the phone's groups", "// MARK: following the route")
    sections += member(screen, "private func listPage")
    groups += member(screen, "private func cardsPage")
    #? the output's switch is "EQ on" (the top's, or the output card's), and the List's long press on Correction -
    #? Back to AutoEq's - is the •••'s on the phone, as it was the •••'s on both
    more = member(screen, "private func more")
    assert "eq.backToAutoEq(for: output)" in more
    groups += member(screen, "private func onSwitch") + more
    assert calls(groups) == calls(sections), (calls(groups) ^ calls(sections))
    assert "eq.advanced = now" in groups and "eq.advanced = now" in sections
    for gesture in (".swipeActions", "onLongPressGesture"):
        assert gesture not in groups, gesture
    assert "Button {\n                eq.mark(.notNow, for: output)" in groups
    assert ".accessibilityAction(named: EQWords.Correction.notNow) { eq.mark(.notNow, for: output) }" in groups
    assert "Button(EQWords.Outputs.rename) { askRename(other.key) }" in groups
    assert "Button(EQWords.Outputs.forget) { askForget(other.key, isPage: false) }" in groups
    #? the phone's page is iEQ's: the output's button over AirPlay's picker, the curve in a well
    assert "EQOutputButton(output: output, connected: connected, playsTo: eq.settings.setting(for: eq.route).shownName)" in groups
    assert "well: true)\n                .background { DWWell() }" in groups
    button = member(code(OUTPUTS), "struct EQOutputButton: View")
    assert button.index(".allowsHitTesting(false)") < button.index("AirPlayButton(glyph: false, playsTo: playsTo, said: said)")


def menu_of(text: str) -> str:
    """The one `.contextMenu { … }` in `text`: what its long press holds."""
    assert text.count(".contextMenu {") == 1, text.count(".contextMenu {")
    return block(text, text.index(".contextMenu {") + len(".contextMenu "))


def test_the_lists_swipes_are_long_presses_here():
    """(R3b's review) The phone's groups aren't a List, so what its rows' swipes and long press did is each a long press
    (a context menu) on the same row - a filter's Delete, Other outputs' Rename and Forget (never the speaker),
    Correction's Back to AutoEq's in Advanced - reached by touch without opening the filter's editor or the output's
    page: none of them pushes a page. VoiceOver's actions on those rows are kept, and Not now is a button."""
    screen = code(EQ_SCREEN)
    row = member(screen, "struct EQPhoneFilterRow: View")
    delete = menu_of(row)
    assert 'Button(EQWords.Advanced.delete, systemImage: "trash", role: .destructive, action: delete)' in delete
    assert ".accessibilityAction(named: EQWords.Advanced.delete, delete)" in row
    rows = member(screen, "private func cardAdvancedRows")
    assert "EQPhoneFilterRow(row: row, open: {" in rows and "delete: {\n                eq.deleteFilter(row.filter.id, for: output)" in rows
    others = member(screen, "private func othersCard")
    outputs = menu_of(others)
    assert 'Button(EQWords.Outputs.rename, systemImage: "pencil") { askRename(other.key) }' in outputs
    assert outputs.index("if EQScreenRules.forgets(other.key) {") < outputs.index("askForget(other.key, isPage: false)")
    assert others.index(".contextMenu {") < others.index(".accessibilityActions {")
    correction = member(screen, "private func correctionCard")
    back = menu_of(correction)
    assert back.index("if advanced && EQAdvancedRules.goesBack(setting.correction) {") < back.index("eq.backToAutoEq(for: output)")
    #? the same three on the Mac's List, as R3 left them
    sections = between(EQ_SCREEN, "// MARK: the sections", "// MARK: the phone's groups")
    assert ".swipeActions" in sections and "eq.backToAutoEq(for: output)" in sections
    #? by touch alone: no long press opens a page or the editor
    for menu in (delete, outputs, back):
        for opens in ("push(", "open(", "open:", "EQLink(", "NavigationLink("):
            assert opens not in menu, opens
    #? (R3b's review) a filter's switch is the phone's own, as every switch on its pages: never the accent's tint
    toggle = row[row.index("Toggle(isOn:"):]
    assert ".toggleStyle(.phoneSwitch)" in toggle[:toggle.index(".accessibilityLabel(EQWords.Advanced.switchSaid(row.number))")]
    for tint in (".tint(", "DWPalette.acc", "Palette.acc"):
        assert tint not in row, tint


def test_the_outputs_button_says_the_pages_output():
    """(R3b's review) The output's button is AirPlay's under the face: its double tap opens AirPlay, as before, and it says
    the page's output and whether it's connected - the old header's words - with AirPlay's double tap as its hint."""
    button = member(code(OUTPUTS), "struct EQOutputButton: View")
    said = member(button, "private var said: AirPlaySaid")
    assert flat(said).strip() == ("AirPlaySaid(label: output.name, value: connected ? EQWords.Screen.connected : "
                                  "EQWords.Screen.notConnected, hint: EQWords.Screen.outputHint(playsTo: playsTo))")
    airplay = code(APP / "Player" / "AirPlayButton.swift")
    dress = flat(airplay)
    for part in ("picker.accessibilityLabel = said?.label ?? NowPlayingWords.airPlay",
                 "picker.accessibilityValue = said?.value ?? playsTo", "picker.accessibilityHint = said?.hint"):
        assert part in dress, part
    assert "var said: AirPlaySaid?" in airplay
    #? everywhere else AirPlay's button says what it said: "AirPlay", where the music plays
    told = [path.name for path in sorted(APP.rglob("*.swift")) if re.search(r"AirPlayButton\([^)]*\bsaid:", code(path))]
    assert told == ["EQOutputViews.swift"], told


def test_a_filters_editor_applies_what_was_typed_as_it_goes():
    """R3's review: Back, the strip or the sheet put down left a typed value unapplied. Leaving now applies it, as
    leaving the field does - before the holds are let go, so the file is written once, with it."""
    editor = code(EDITOR)
    gone = editor[editor.index(".onDisappear {"):]
    gone = block(gone, gone.index("{"))
    assert gone.index("leave()") < gone.index("while holding > 0 { hold(false) }")
    leave = member(editor, "private func leave")
    assert "let left = EQEditorRules.leaving(editing, filter: f) else { return }" in leave
    assert "edit(left, output)" in leave
    rule = member(bare(EQ_PHONE), "public static func leaving(_ typed: [EQField: String], filter f: EQFilter) -> EQFilter?")
    assert "case .value(let value) = check(text, field, for: g)" in rule and "g = applying(value, field, to: g)" in rule


# ----------------------------------------------------------------------------- tokens

def test_the_pages_redrawn_draw_with_tokens_alone():
    for path in REDRAWN:
        text = bare(path)
        for raw in ("Color(red:", "Color(white:", "Color(hex", "UIColor(", ".cornerRadius(", "RoundedRectangle(",
                    ".font(.system(", "Font.system(", "Font.custom(", ".custom("):
            assert raw not in text, f"{path.name}: {raw}"
    #? the phone's new parts in the look's colours: DWPalette, never the old Palette
    for path, parts in ((QUEUE, ("private func playingRow", "private func heading", "private func phoneFoot",
                                 "private struct QueueTimeLeftLine: View")),
                        (INFO, ("private func songRow", "private struct InfoKV: View", "private struct InfoDebugRow: View")),
                        (EQ_SCREEN, ("private func cardsPage", "private func correctionCard", "private func toneCard",
                                     "private func preampCard", "private func suggestionRow", "private func cardNote",
                                     "struct EQPhoneFilterRow: View")),
                        (OUTPUTS, ("struct EQOutputButton: View",))):
        text = bare(path)
        for part in parts:
            assert not re.search(r"(?<![\w.])Palette\.", member(text, part)), f"{path.name}: {part}"
