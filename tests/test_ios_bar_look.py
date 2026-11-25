"""
The player bar, the mini player and the tab bar in the redesign's look (slice R4 - notes/ios.md "The redesign, slice R4:
the player bar, the mini player and the tab bar"; dw.css's .player, .mini and .tabbar, and James's corrections in the
redesign's notes: the bar 66 tall, its display the bar's whole height with the cover flush and three lines, the five
keys one row of drawn glyphs, Queue, Lyrics and Info one joined strip, then the EQ and the output).

The app's Swift read as text, as the other look tests read it, and held to dw.css as the cascade resolves it:

- The Mac's bar: its sizes dw.css's, its keys in the drawing's order, each key's action PlayerModel's own call made in
  the click (no Task, nothing awaited), the display's three lines and Core's Next and readout (BarDisplay), the strip
  joined as dw.css joins it, Space from the Controls menu and never while typing, and the whole of it fitting the
  smallest window (880) and the one a window opens at (1280), added up from the sizes and the words' lengths.
- The phone's mini player: dw.css's .mini, Play bare in its 48 target, no skip button, the one drag as it was and
  VoiceOver's Next and Previous on the title.
- The phone's tab bar: the lit line square, on the bar's top edge, over the shown tab alone; its badge, glyphs, Large
  Content Viewer and its cap at xxxLarge kept.
- Tokens only, in every one of them: no colour, radius or font of its own.
"""

import hashlib
import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_bar_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
mac_look = _load("test_ios_mac_look")
fonts = _load("ios_fonts")

BAR = "Player/PlayerBar.swift"
MINI = "Player/MiniPlayerView.swift"
TABS = "Root/MainTabs.swift"
STRIP = "Mac/Components/MacStrip.swift"
OUTPUT = "Mac/Components/MacOutput.swift"


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def kept(text: str) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def body(code: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = code.index(start)
    opened = code.index("{", at)
    return code[at:reader.closing(code, opened) + 1]


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


def mac(selector: str, prop: str) -> float:
    """A Mac size of dw.css's, as its cascade resolves it."""
    return phone_look.px(phone_look.css(selector, prop, phone_look.MAC_ROOT).replace("!important", "").strip())


def phone(selector: str, prop: str) -> float:
    return phone_look.px(phone_look.css(selector, prop))


def look_size(enum: str, name: str, file: str) -> float:
    """A Core size: `public static let <name>: Double = <n>` in `enum` of `file`."""
    text = core(file)
    text = text[text.index(f"enum {enum}"):]
    return float(re.search(rf"public static let {name}: Double = (-?[0-9.]+)\b", text).group(1))


def estimate(words: str, size: float, mono: bool = False, weight: str = "semibold") -> float:
    """A width for `words` at `size`, measured from the bundled faces (tests/ios_fonts.py, 25 Nov - it was 0.55 of the
    size a letter in Noto Sans until then): Libre Franklin at `weight` - SemiBold unless said, the heaviest the bar's
    words take, so from above - or the readout face, Courier Prime, for `mono`."""
    return fonts.readout(words, size) if mono else fonts.words(words, size, weight)


def tabs_bar() -> str:
    """MainTabs' tab bar alone: AppTabBar, AppTabButton and TabBadge."""
    code = source(TABS)
    return code[code.index("struct AppTabBar"):code.index("struct TabStack")]


# ----------------------------------------------------------------------------- the Mac's bar

def test_the_bars_sizes_are_dw_css_player():
    code = source(BAR)
    found = re.findall(r"private static let (\w+): CGFloat = ([0-9.]+)\s+// dw: (.+?) ([\w-]+)\n", code)
    assert len(found) == 11, found
    for name, value, selector, prop in found:
        prop = {"padding": "padding-left"}.get(prop, prop)
        assert float(value) == mac(selector, prop), f"PlayerBar.{name} is not {selector}'s {prop}"
    # the bar 66 tall (MacLook's, .player's), its 1 pt edge along the top: the bar's height under it is the display's,
    # and the display's cover is that height, flush (.lcd > .cover's 65)
    assert look_size("MacLook", "barHeight", "MacLook.swift") == mac(".player", "height") == 66
    assert "private static let cover = CGFloat(MacLook.barHeight) - 1\n" in code
    assert mac(".lcd > .cover", "width") == 66 - 1
    plain = bare(code)
    drawn = flat(body(plain, "var body: some View {"))
    for part in (".padding(.horizontal, Self.pad) .frame(height: CGFloat(MacLook.barHeight) - 1)",
                 ".background(alignment: .top) { DWRule(colour: MacPalette.playerSheen) } .padding(.top, 1) "
                 ".background(MacPalette.playerFace) .overlay(alignment: .top) { DWRule(colour: MacPalette.playerEdge) }"):
        assert part in drawn, part
    palette = (APP / "Mac" / "Look" / "MacPalette.swift").read_text(encoding="utf-8")
    for name, prop in (("playerFace", "background"), ("playerEdge", "border-top"), ("playerSheen", "box-shadow")):
        assert re.search(rf"static let {name} = .+// dw: \.player {prop}\n", palette), name


def test_the_keys_are_one_row_in_the_drawings_order():
    keys = bare(source(BAR))
    keys = keys[keys.index("private var keys: some View {"):keys.index("private func display(")]
    order = [keys.index(part) for part in (
        "player.toggleShuffle()", "DWToggleStyle(on: player.shuffle)",
        "player.previous()", "SharpSymbol(.previous)", "MacKeyStyle()",
        "player.toggle()", "PlayPauseGlyph(playing: player.isPlaying)", "MacKeyStyle(big: true)",
        "player.next()", "SharpSymbol(.next)",
        "player.setRepeat(nextRepeat(mode))", "DWToggleStyle(on: mode != .off)")]
    assert order == sorted(order)
    assert "HStack(spacing: Self.keysGap) {" in keys and keys.count("Button {") == 5
    # the keys' sizes are MacLook's, dw.css's .key, .key.big and .tog
    for name, (selector, prop) in (("keySize", (".key", "width")), ("bigKeySize", (".key.big", "width")),
                                   ("toggleSize", (".tog", "width"))):
        assert look_size("MacLook", name, "MacLook.swift") == mac(selector, prop), name
    # the transport's glyphs drawn sharp (SharpSymbol, PlayPauseGlyph), round keys the Mac's own
    assert "forward.fill" not in keys and "backward.fill" not in keys and "play.fill" not in keys


def test_every_key_acts_in_the_click():
    code = bare(source(BAR))
    for call in (r"if !paged \{ player\.toggleShuffle\(\) \}", r"player\.previous\(\)", r"player\.toggle\(\)",
                 r"player\.next\(\)", r"player\.setRepeat\(nextRepeat\(mode\)\)"):
        assert re.search(r"Button \{\s*" + call + r"\s*\} label:", code), call
    for tab in ("upNext", "lyrics", "info"):
        assert re.search(rf"Button\(MacDock\.Words\.tab\(\.{tab}\)\) \{{\s*navigation\.togglePanel\(\.{tab}\)\s*\}}",
                         code), tab
    assert re.search(r"BarEQButton\(on: shown == \.eq\) \{\s*navigation\.togglePanel\(\.eq\)\s*\}", code)
    assert "Button(MacDock.Words.tab(.eq), action: action)" in code
    # nothing in the bar waits before it acts, or acts later
    assert "Task" not in code and "await" not in code and "DispatchQueue" not in code
    # the scrubber seeks where it is let go, or by VoiceOver's step: the player's own seek
    assert code.count("player.seek(to:") == 2


def test_the_display_fills_the_bar_with_its_three_lines():
    code = bare(source(BAR))
    drawn = flat(body(code, "var body: some View {"))
    assert re.search(r"HStack\(spacing: Self\.gap\) \{ keys MacDisplay \{ if let entry = player\.current \{ "
                     r"display\(entry\.track\) \} else \{ Text\(LyricsWords\.nothingPlaying\)", drawn)
    assert drawn.index("MacDisplay {") < drawn.index("tools .fixedSize()")
    display = body(code, "private func display(_ track: QueueTrack) -> some View {")
    # the cover first, flush - nothing padded before it - the bar's height under its edge, its rule at its right
    assert re.search(r"return HStack\(spacing: Self\.lcdGap\) \{\s*CoverImage\(id: track\.coverArt, size: Self\.cover\)"
                     r"\s*\.frame\(width: Self\.cover, height: Self\.cover\)", display)
    assert ".overlay(alignment: .trailing) { DWRule(colour: DWPalette.line, vertical: true) }" in display
    # then three lines: the title and Next, the byline and the readout, the clocks and the scrubber
    order = [display.index(part) for part in ("VStack(alignment: .leading, spacing: Self.lineGap) {",
                                              "titleLine(track, next: next)", "titleLine(track, next: nil)",
                                              "byline(track)", "Text(readout)", "BarScrubber()",
                                              ".padding(.trailing, Self.lcdEnd)")]
    assert order == sorted(order)
    assert display.count("ViewThatFits(in: .horizontal) {") == 2
    # the title in .lcd .b's 14, semibold (Typeface.Mac's lcd), the readout in the mono face
    assert "case lcd = 14" in (APP / "Shared" / "Typeface.swift").read_text(encoding="utf-8")
    assert mac(".lcd .b", "font-size") == 14
    assert ".font(Typeface.Mac.text(.lcd).weight(.semibold))" in code and ".font(Typeface.Mac.mono(.label))" in display
    # the display is MacDisplay: the well's black, its shade inside, its two rules - the bar's whole height
    keys = (APP / "Mac" / "Components" / "MacKeys.swift").read_text(encoding="utf-8")
    assert ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)" in body(bare(keys), "struct MacDisplay")
    assert phone_look.css(".lcd", "align-self", phone_look.MAC_ROOT) == "stretch"


def test_next_and_the_readout_are_cores():
    code = bare(source(BAR))
    assert "let next = BarDisplay.next(player.queue, repeat: player.repeatMode)" in code
    assert "let readout = BarDisplay.readout(player.queue)" in code
    assert ".accessibilityValue(next.map { BarDisplay.Words.nextSpoken($0.title) } ?? \"\")" in code
    assert ".accessibilityLabel(BarDisplay.readoutSpoken(player.queue) ?? readout)" in code
    assert "Text(BarDisplay.Words.next)" in code and "Text(next.title)" in code
    # Core's, from the queue the player holds - no new route, nothing asked of the server
    display = core("BarDisplay.swift")
    assert "DeadwaxClient" not in display and "Routes" not in display and "async" not in display
    assert "nextIndex(queue)" in display
    tests = (IOS / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "BarDisplayTests.swift").read_text(encoding="utf-8")
    for case in ("atTheLastSongRepeatOffNamesNothing", "atTheLastSongRepeatAllNamesTheFirst", "repeatOneNamesNothing",
                 "underShuffleNextIsTheShuffledOrder", "theAlbumsThirdSongIsThreeOfEleven",
                 "theFormatIsWhatTheSongSays", "aLossyFilesFormatIsItsNameAlone"):
        assert f"@Test func {case}()" in tests, case


def test_the_strip_is_three_joined_buttons_then_the_groove_eq_and_output():
    code = bare(source(BAR))
    tools = code[code.index("private var tools: some View {"):code.index("private func more(")]
    order = [tools.index(part) for part in (
        "HStack(spacing: -1) {", "MacStripButtonStyle(place: .first, on: shown == .upNext)",
        "MacStripButtonStyle(place: .middle, on: lyricsOn)", "MacStripButtonStyle(place: .last, on: shown == .info)",
        "MacGroove()", "BarEQButton(on: shown == .eq)", "MacOutput(named: width == 0 || width >= Self.namedFrom)",
        "more(entry.track)")]
    assert order == sorted(order)
    # joined as dw.css joins them: each overlapping the one before by its 1 pt edge, across the tools' gap
    assert mac(".tools", "gap") + phone_look.px(mac_look.rule(".tools > :nth-child(2)")["margin-left"]) == -1
    assert mac_look.rule(".tools > :nth-child(1)")["border-radius"] == "4px 0 0 4px"
    assert mac_look.rule(".tools > :nth-child(2)")["border-radius"] == "0"
    assert mac_look.rule(".tools > :nth-child(3)")["border-radius"] == "0 4px 4px 0"
    strip = bare(source(STRIP))
    assert "let shape = MacStripShape(leading: place == .first, trailing: place == .last)" in strip
    assert "let corner = max(min(DWCorners.button - inset, box.height / 2), 0)" in strip
    assert ".frame(height: CGFloat(MacLook.buttonHeight))" in strip
    assert look_size("MacLook", "buttonHeight", "MacLook.swift") == mac(".tools .btn", "height")
    assert ".padding(.horizontal, CGFloat(DWLook.here.buttonPadding))" in strip
    # the lit one over its neighbours, its edge whole - the bar gives it the higher place in the strip's stack
    for lit in ("shown == .upNext", "lyricsOn", "shown == .info"):
        assert f".zIndex({lit} ? 1 : 0)" in tools, lit
    # lit while its tab shows, and said so
    assert tools.count(".accessibilityAddTraits(") == 3
    # (R4's review) the output's cap applied to it: the room the fit test below counts on, never the name's own width
    assert re.search(r"MacOutput\(named: width == 0 \|\| width >= Self\.namedFrom\)\s*\.frame\(maxWidth: Self\.outputMost\)",
                     tools)
    # (R3) the •••'s EQ still opens the dock's EQ tab
    assert "onEQ: { navigation.showPanel(.eq) }" in code
    # the output names the route; its name's tooltip whatever is drawn
    output = bare(source(OUTPUT))
    assert "AirPlayButton()" in output and "if named {" in output and ".help(name)" in output


def test_space_plays_and_pauses_except_in_a_field():
    menu = core("MacMenu.swift")
    assert "case .playPause: return Shortcut(.space)" in menu
    assert "command == .playPause || command == .next || command == .previous" in menu
    assert "let shortcut = state.typing && yieldsToTyping(command) ? nil : key(command)" in menu
    commands = (APP / "Shared" / "MacCommands.swift").read_text(encoding="utf-8")
    assert "case .playPause:\n            player.toggle()" in commands
    # the bar takes no key of its own, so Space is never had twice
    assert "keyboardShortcut" not in bare(source(BAR))


def test_the_bar_fits_the_smallest_window_and_the_one_it_opens_at():
    # the bar runs the window's width, under the sidebar, the page and the side panel alike
    smallest = look_size("MacFrame", "smallestWidth", "MacFrame.swift")
    opening = look_size("MacFrame", "openingWidth", "MacFrame.swift")
    assert (smallest, opening) == (880, 1280)
    # (after R4's review) the web's bar sizes are gone from MacFrame: this test's arithmetic is what holds the bar to
    # the smallest window now, not a sum of the web's sides (frame-vectors.json keeps them, the web's record)
    frame = bare(core("MacFrame.swift"))
    assert not re.search(r"\bbar(Height|Cover|SideNarrow|SideWide|Pad|Gap|MiddleMin|Side)\b", frame)
    code = source(BAR)
    statics = {name: float(value) for name, value in re.findall(r"private static let (\w+): CGFloat = ([0-9.]+)", code)}
    size = lambda name: look_size("MacLook", name, "MacLook.swift")  # noqa: E731
    keys = 2 * size("toggleSize") + 2 * size("keySize") + size("bigKeySize") + 4 * statics["keysGap"]
    control = 12.5
    # the Mac's .btn padding, DWLook.mac's
    pad = float(re.search(r"buttonPadding: (\d+),\s+// dw: \.btn padding-left", core("DWLook.swift")).group(1))
    assert pad == mac(".tools .btn", "padding-left")
    words = [re.search(r'public static let title = "(\w+)"', core("UpNextView.swift")).group(1),
             re.search(r'public static let lyrics = "(\w+)"', core("Lyrics.swift")).group(1),
             re.search(r'public static let title = "(\w+)"', core("Info.swift")).group(1)]
    assert words == ["Queue", "Lyrics", "Info"]
    strip = sum(estimate(w, control) + 2 * pad for w in words) - 2
    groove = 2 + 2 * mac(".groove", "margin-left")
    eq = estimate(re.search(r'public static let nowPlaying = "(\w+)"', core("EQWords.swift")).group(1), control) + 2 * pad

    def tools(named: bool) -> float:
        output = statics["outputMost"] if named else size("smallButtonHeight")
        return strip + groove + eq + output + statics["more"] + 4 * statics["toolsGap"]

    def column(width: float) -> float:
        named = width >= statics["namedFrom"]
        lcd = width - 2 * statics["pad"] - 2 * statics["gap"] - keys - tools(named)
        return lcd - (size("barHeight") - 1) - statics["lcdGap"] - statics["lcdEnd"]

    # the third line holds an hour-long song's clocks in the mono face (8 apart) with a meter between them
    clocks = estimate("1:02:03", 11.5, mono=True) + estimate("-1:02:03", 11.5, mono=True) + 2 * 8 + 40
    for width in (smallest, statics["namedFrom"] - 1, statics["namedFrom"], opening):
        assert column(width) >= clocks, (width, column(width), clocks)
    # the name gives way only below namedFrom: the smallest window's column would not hold the clocks with it
    assert smallest - 2 * statics["pad"] - 2 * statics["gap"] - keys - tools(True) - 95 < clocks
    # as a window opens, the first line holds a title's least, Next and its song's widest beside it, and the second
    # a byline's least and the longest readout a library's shuffle gives
    first = 120 + statics["rowGap"] + estimate("Next", 11.5) + statics["rowGap"] + statics["nextMost"]
    second = statics["bylineLeast"] + statics["rowGap"] + estimate("1,612 of 1,612 · FLAC 24/192", 11.5, mono=True)
    assert first <= column(opening) and second <= column(opening), (first, second, column(opening))


# ----------------------------------------------------------------------------- the phone's mini player

def test_the_mini_player_is_dw_css_mini():
    code = bare(source(MINI))
    assert phone(".mini", "height") == look_size("PhoneLook", "mini", "DWLook.swift") == 60
    assert phone(".mini .key.big", "width") == look_size("PhoneLook", "miniPlay", "DWLook.swift") == 48
    assert phone(".mini", "padding-right") == look_size("PhoneLook", "miniTrail", "DWLook.swift") == 12
    assert phone(".mini", "gap") == look_size("PhoneLook", "miniGap", "DWLook.swift") == 10
    # on its own ground (#1c1b22 under its top edge), the cover flush left, the bar's height under that edge
    assert ".background { PhoneMiniGround() }" in code
    assert phone(".mini .cover", "width") == 60 - 1 and "let cover = row - 1" in code
    assert ".frame(maxHeight: .infinity, alignment: .bottom)" in code
    title = body(code, "private struct BarTitle")
    assert re.search(r"HStack\(spacing: Self\.gap\) \{\s*CoverImage\(id: track\.coverArt, size: cover\)", title)
    # the seek line, 2 tall along the top edge: the track in the line's colour, the part played in the purple gradient
    line = body(code, "private struct SeekLine")
    assert phone(".mini > .prog", "height") == 2 and "private static let rest: CGFloat = 2" in line
    assert phone_look.css(".mini > .prog > i", "background") == "linear-gradient(to right, #9333ea, #c084fc)"
    assert "Rectangle().fill(DWPalette.seekTrack)" in line and "Rectangle().fill(DWPalette.seekFill)" in line


def test_play_is_bare_and_there_is_no_skip_button():
    code = bare(source(MINI))
    # the bar's buttons: Play/Pause, and VoiceOver's two actions on the title - nothing else
    buttons = re.findall(r"\bButton\b\s*(?:\{|\([^)]*\))", code)
    assert buttons == ["Button {", "Button(PlayerWords.nextSong)", "Button(PlayerWords.previousSong)"], buttons
    assert "Button { player.toggle() } label: {" in code
    actions = body(code, ".accessibilityActions {")
    assert "Button(PlayerWords.nextSong) { player.next() }" in actions
    assert "Button(PlayerWords.previousSong) { player.songBefore() }" in actions
    # bare: a sharp glyph in the bar's white, no face, edge or round key
    play = code[code.index("Button { player.toggle() } label: {"):code.index(".accessibilitySortPriority(2)")]
    assert "PlayPauseGlyph(playing: player.isPlaying)" in play and ".buttonStyle(.plain)" in play
    assert ".foregroundStyle(DWPalette.text)" in play
    for absent in ("MacKeyStyle", "DWButtonStyle", "Circle()", "Capsule", "SharpSymbol(.next)", "forward"):
        assert absent not in code, absent
    assert ".frame(minWidth: Self.button, maxHeight: .infinity)" in play and ".padding(.trailing, Self.edge)" in play


def test_the_titles_tap_ends_where_the_drag_reads_the_title():
    # (R4's review) the words stop .mini's gap (10) short of Play/Pause, and that gap is the title's to tap - padded
    # inside its tap area - so a tap and a drag agree on where the title ends: the bar's width less Play/Pause's target
    # and the room past it
    code = bare(source(MINI))
    title = body(code, "private struct BarTitle")
    assert "private static let end = CGFloat(PhoneLook.miniGap)" in title
    assert look_size("PhoneLook", "miniGap", "DWLook.swift") == phone(".mini", "gap")
    padded = title.index(".padding(.trailing, Self.end)")
    assert padded < title.index(".contentShape(Rectangle())") < title.index(".onTapGesture {")
    # nothing else between the title and Play/Pause: the row's spacing 0, Play's target and the room past it
    assert re.search(r"HStack\(spacing: 0\) \{\s*BarTitle\(", code)
    play = code[code.index("Button { player.toggle() } label: {"):code.index(".accessibilitySortPriority(2)")]
    assert ".frame(minWidth: Self.button, maxHeight: .infinity)" in play and ".padding(.trailing, Self.edge)" in play
    assert "let onTitle = value.startLocation.x < width - (Self.button + Self.edge)" in code


#? the drag as it stood before R4 (b6f8dcfa), byte for byte: the drag and the skip it lets go into
DRAG_DIGEST = "12c31414b6ca643f8a1e3c34290a71de208c897e73b74edd4ae073a1ee41633d"


def test_the_mini_players_drag_is_as_it_was():
    text = source(MINI)
    at = text.index("    private var drag: some Gesture {")
    drag = text[at:text.index("\n    private func springBack() {", at)]
    assert hashlib.sha256(drag.encode("utf-8")).hexdigest() == DRAG_DIGEST, "the mini player's drag changed"
    assert "let onTitle = value.startLocation.x < width - (Self.button + Self.edge)" in drag
    assert "PlayBar.role(way, startY: value.startLocation.y, onTitle: onTitle)" in drag
    # its reach and its threshold Core's, as they were
    bar = core("PlayBar.swift")
    assert "public static let seekReach: Double = 14\n" in bar and "public static let decideAfter: Double = 10\n" in bar
    code = bare(text)
    assert code.count("DragGesture(") == 1 and ".highPriorityGesture(drag)" in code
    # a tap anywhere on the cover or the words opens Now Playing
    assert ".onTapGesture { navigation.nowPlayingShown = true }" in body(code, "private struct BarTitle")


# ----------------------------------------------------------------------------- the phone's tab bar

def test_the_lit_line_is_square_and_over_the_shown_tab_alone():
    lit = ".tabbar > a.on::before"
    assert phone_look.css(lit, "border-radius") == "0"
    assert phone(lit, "width") == look_size("PhoneLook", "litLineWidth", "DWLook.swift") == 24
    assert phone(lit, "height") == look_size("PhoneLook", "litLineHeight", "DWLook.swift") == 2
    assert -phone(lit, "top") == look_size("PhoneLook", "litLineLift", "DWLook.swift") == 7
    # 7 over the tab is the bar's top edge: its 1 pt edge and the 6 above the tabs
    assert phone(".tabbar", "border-top-width") + phone(".tabbar", "padding-top") == 7
    assert look_size("PhoneLook", "tabBarTop", "DWLook.swift") == phone(".tabbar", "padding-top")
    item = body(bare((APP / "Phone" / "PhoneTabItem.swift").read_text(encoding="utf-8")), "struct PhoneLitLine")
    assert "Rectangle()" in item and not re.search(r"cornerRadius|RoundedRectangle|Capsule|clipShape", item)
    bar = bare(tabs_bar())
    assert bar.count("PhoneLitLine()") == 1
    assert re.search(r"\.overlay\(alignment: \.top\) \{\s*if shown \{\s*PhoneLitLine\(\)\s*"
                     r"\.offset\(y: -CGFloat\(PhoneLook\.litLineLift\)\)\s*\}\s*\}", bar)
    # the edge drawn first, so the lit line lies over it; the tabs 6 under it
    tab_bar = body(bar, "struct AppTabBar")
    assert tab_bar.index("DWRule(colour: DWPalette.tabBarEdge)") < tab_bar.index("HStack(spacing: 0) {")
    assert ".padding(.top, Self.pad)" in tab_bar and "private static let pad = CGFloat(PhoneLook.tabBarTop)" in tab_bar


def test_the_tab_bar_keeps_its_glyphs_its_badge_and_its_cap():
    bar = bare(tabs_bar())
    for kept_ in (".dynamicTypeSize(...DynamicTypeSize.xxxLarge)", ".accessibilityAddTraits(.isTabBar)",
                  ".accessibilityShowsLargeContentViewer {", "SharpSymbol(sharp)", "Image(uiImage: sharp.image)",
                  ".symbolVariant(.fill)", ".padding(.bottom, CGFloat(TabBarFoot.below(home: home)))",
                  "if !badge.isEmpty { TabBadge(count: badge) }", "DWCount(count: count)",
                  ".foregroundStyle(shown ? DWPalette.acc : DWPalette.tabItemText)", ".lookHeight(PhoneLook.tabItem)",
                  "@ScaledMetric(relativeTo: .title2) private var symbolBox = CGFloat(PhoneLook.tabIcon)",
                  "if player.hasQueue {\n                MiniPlayerView()\n            }"):
        assert kept_ in bar, kept_
    assert phone(".tabbar > a", "height") == look_size("PhoneLook", "tabItem", "DWLook.swift") == 49
    assert phone(".tabbar svg", "width") == look_size("PhoneLook", "tabIcon", "DWLook.swift") == 24


# ----------------------------------------------------------------------------- tokens only

PHONE_FONT = re.compile(r"Typeface\.(?:Phone\.(?:text|mono)|symbol)\(")


def test_the_bars_draw_no_value_of_their_own():
    left = []
    for name, text in ((BAR, source(BAR)), (STRIP, source(STRIP)), (OUTPUT, source(OUTPUT)), (MINI, source(MINI)),
                       (TABS, tabs_bar())):
        code = bare(text)
        for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                              ("the iPhone's old palette", r"(?<![\w.])Palette\."),
                              ("the iPhone's old corners", r"(?<![\w.])Corners\."),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b"),
                              ("a font of its own", r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\.monospaced")):
            if re.search(pattern, code):
                left.append(f"{name}: {what}")
        if mac_look.NAMED_COLOUR.search(code):
            left.append(f"{name}: a named colour ({mac_look.NAMED_COLOUR.search(code).group(0)})")
        fonts = mac_look.font_arguments(code)
        if name in (BAR, STRIP, OUTPUT):
            left += [f"{name}: .font({f})" for f in fonts if not mac_look.MAC_FONT.match(f)]
        else:
            # the phone's: Typeface.Phone's sizes - and the mini player's title, iOS's subheadline (15, growing with
            # the text size), which Typeface.Phone has no size for
            left += [f"{name}: .font({f})" for f in fonts
                     if not PHONE_FONT.match(f) and f != "Typeface.subheadline.weight(.semibold)"]
    assert not left, left


def test_the_word_is_queue():
    for name in (BAR, MINI):
        assert "Up Next" not in kept(source(name)), name
    assert "Up Next" not in kept(tabs_bar())
