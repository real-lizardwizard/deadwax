"""
Now Playing's top and bottom rows after R3's review (notes/ios.md "The redesign, slice R3: the side panel's tabs; the Now
Playing sheet", its review). test_ios_panels_look.py holds the row's five and what each opens; this holds what the
review found:

  - The speed chip's frame overlaps no button's target, at any text size it is drawn, on a 375 or a 390 point phone:
    it has a band of its own between the transport and the row (SpeedChipBand). Worked out here from the code's own
    numbers - Now Playing's padding, the transport's buttons, TurntableFace's chip, PhoneLook's item, the row's order -
    as the look tests read sizes. In the row it lapped about 28 points of Info's column and 15 of AirPlay's target.
  - The notice clears the chevron, the look button and the •••: it is the top row's middle, as wide as they leave it.
  - The row's VoiceOver, each part on its own: the Queue's and the EQ's names say more than their words, Lyrics dimmed
    is a button that does nothing, the output is AirPlay's picker alone (where it plays its value), and PhoneTabItem
    says `spoken` ahead of its words.
  - The output's target is its whole column (the picker under it), as the other four's are.
  - Only the row's EQ and its output read the EQ: a slider moved never redraws Now Playing.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"
NOW_PLAYING = APP / "Player" / "NowPlayingView.swift"
AIRPLAY = APP / "Player" / "AirPlayButton.swift"
TAB_ITEM = APP / "Phone" / "PhoneTabItem.swift"
TABS = CORE / "NowPlayingTabs.swift"
TURNTABLE = CORE / "TurntableScreen.swift"
LOOK = CORE / "DWLook.swift"
SPEED = CORE / "PlaySpeed.swift"
WORDS = CORE / "TurntableWords.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_nowplaying_row_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def bare(path: Path) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(path.read_text(encoding="utf-8"))[1]


def code(path: Path) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(path.read_text(encoding="utf-8"))[0]


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
    """The body of the one member declared as `declaration` (`func content`, `struct OutputItem: View`, ...)."""
    found = list(re.finditer(r"\b" + re.escape(declaration) + r"\b[^{]*\{", text))
    assert len(found) == 1, f"{declaration} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def number(text: str, pattern: str) -> float:
    found = re.findall(pattern, text)
    assert len(found) == 1, f"{pattern}: {found}"
    return float(found[0])


# ----------------------------------------------------------------------------- the speed chip's place

#? Dynamic Type's footnote, the chip's words' style, at each size the chip is drawn (Apple's table; the accessibility
#? sizes draw no chip - the ••• says the speed). The chip's words stop growing at xxLarge (its .dynamicTypeSize cap).
FOOTNOTE = {"xSmall": 12, "small": 12, "medium": 12, "large": 13, "xLarge": 15, "xxLarge": 17, "xxxLarge": 19}
SIZES = list(FOOTNOTE)
#? a monospaced glyph's advance, as a share of its size: SF Mono's is about 0.6 - taken a little wide
MONO_ADVANCE = 0.62
#? SwiftUI's HStack spacing between two plain views, where none is given
HSTACK_SPACING = 8
PHONES = (375, 390)


def overlaps(a: tuple, b: tuple) -> bool:
    """Two (x0, y0, x1, y1) rects share area - edges that touch don't."""
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def chip_words_width(size: float) -> float:
    """The widest label the chip says (TurntableWords.speedLabel: two places and an x), at `size` points."""
    words = bare(WORDS)
    label = r'public static func speedLabel\(_ speed: Double\) -> String \{\s*"\\\(jsFixed\(PlaySpeed\.roundSpeed\(speed\), 2\)\)x"'
    assert re.search(label, code(WORDS))
    speed = code(SPEED)
    low, high = number(speed, r"public static let min = ([0-9.]+)"), number(speed, r"public static let max = ([0-9.]+)")
    widest = max(len(f"{value:.2f}x") for value in (low, high, 1.25, 1.75))
    assert widest == 5 and "speedLabel" in words
    return widest * MONO_ADVANCE * size


def frames(width: float, size: str) -> tuple[tuple, list[tuple]]:
    """Now Playing's foot on a phone `width` points wide, at text size `size`: the chip's frame, and every button's target
    near it - the transport's five and the row's five - in the content column's own points (its top the transport's)."""
    now = bare(NOW_PLAYING)
    tabs = bare(TABS)
    face = bare(TURNTABLE)
    look = bare(LOOK)
    content = member(now, "func content")
    inset = number(content, r"\.padding\(\.horizontal, (\d+)\)\n\s*\.padding\(\.bottom, \d+\)\s*$")
    column = width - 2 * inset

    # the transport: Shuffle, Previous, Play/Pause, Next, Repeat, with Spacer(minLength: 0) between - its top padding
    # above it, nothing under it
    transport = member(now, "var transport: some View")
    mode = member(now, "struct ModeButton: View")
    mode_size = number(mode, r"\.frame\(minWidth: (\d+), minHeight: \d+\)")
    parts = [found.group(0) for found in
             re.finditer(r"ModeButton\(|\.frame\(minWidth: \d+, minHeight: \d+\)|Spacer\(minLength: 0\)", transport)]
    kinds = ["gap" if part.startswith("Spacer") else "button" for part in parts]
    assert kinds == ["button", "gap"] * 4 + ["button"], parts
    buttons = [mode_size if part == "ModeButton(" else number(part, r"minWidth: (\d+)") for part in parts
               if not part.startswith("Spacer")]
    assert buttons[1:4] == [56, 72, 56], buttons
    tall = max(buttons)
    free = (column - sum(buttons)) / kinds.count("gap")
    assert free > 0, "the transport fits"
    targets = []
    x = 0.0
    for side in buttons:
        top = (tall - side) / 2
        targets.append((x, top, x + side, top + side))
        x += side + free

    # the band: as tall as its frame says, under the transport and over the row
    band = member(now, "struct SpeedChipBand: View")
    band_size = re.findall(r"\.frame\(height: CGFloat\(TurntableFace\.(\w+)\)\)", band)
    assert len(band_size) == 1, band_size
    band_top, band_bottom = tall, tall + turntable_face(face, band_size[0])

    # the chip: its words across, its face's padding either side, as tall as its face's outer frame - its target
    chip_face = member(now, "struct SpeedChipFace: ButtonStyle")
    pad = turntable_face(face, re.search(r"\.padding\(\.horizontal, CGFloat\(TurntableFace\.(\w+)\)\)", chip_face).group(1))
    outer = re.findall(r"\.frame\(height: CGFloat\(TurntableFace\.(\w+)\)\)", chip_face)[-1]
    last = f".frame(height: CGFloat(TurntableFace.{outer}))\n            .contentShape(Rectangle())"
    assert member(chip_face, "func makeBody").rstrip().endswith(last), "the target is the face's last frame"
    hit = turntable_face(face, outer)
    chip = member(now, "struct SpeedChip: View")
    assert ".dynamicTypeSize(...DynamicTypeSize.xxLarge)" in chip and "Typeface.mono(.footnote)" in chip
    words = FOOTNOTE[min(size, "xxLarge", key=SIZES.index)]
    across = chip_words_width(words) + 2 * pad
    at = chip_at(tabs)
    centre_x, centre_y = column * at, (band_top + band_bottom) / 2
    chip_frame = (centre_x - across / 2, centre_y - hit / 2, centre_x + across / 2, centre_y + hit / 2)

    # the row: five equal columns, each its whole column a target (the output's too: the picker under it)
    row = re.search(r"public static let row: \[Button\] = \[([^\]]*)\]", tabs).group(1).split(", ")
    item = number(look, r"public static let tabItem: Double = ([0-9.]+)")
    share = column / len(row)
    for index in range(len(row)):
        targets.append((index * share, band_bottom, (index + 1) * share, band_bottom + item))
    return chip_frame, targets


def turntable_face(face: str, name: str) -> float:
    """One of TurntableFace's sizes, by name."""
    return number(face, r"public static let " + re.escape(name) + r" = ([0-9.]+)")


def chip_at(tabs: str) -> float:
    """NowPlayingTabs.chipAt, as the Swift works it out: the line after the chip's left-hand neighbour's column."""
    body = member(tabs, "public static var chipAt: Double")
    assert "guard let left = row.firstIndex(of: chipBetween.0) else { return 0.5 }" in body
    assert "return Double(left + 1) / Double(row.count)" in body
    row = re.search(r"public static let row: \[Button\] = \[([^\]]*)\]", tabs).group(1).split(", ")
    left = re.search(r"public static let chipBetween: \(Button, Button\) = \((\.\w+), (\.\w+)\)", tabs).group(1)
    return (row.index(left) + 1) / len(row)


def test_the_speed_chip_overlaps_no_buttons_target():
    """R3's review, 1: at 1.25x a tap on the left of Info reset the speed and opened nothing. The chip's frame now
    overlaps no target of the transport's or the row's - every size it is drawn at, 375 and 390 points wide."""
    for width in PHONES:
        for size in SIZES:
            chip, targets = frames(width, size)
            hit = [target for target in targets if overlaps(chip, target)]
            assert not hit, f"{width} pt, {size}: the chip {chip} laps {hit}"
            #? and it is still over the gap between the output and Info, inside the column
            row = targets[5:]
            output, info = row[2], row[3]
            centre = (chip[0] + chip[2]) / 2
            assert (output[0] + output[2]) / 2 < centre < (info[0] + info[2]) / 2, (width, size)
            assert chip[0] >= 0 and chip[2] <= row[-1][2], (width, size)
    #? the old place, worked out the same way - level with the row's icons - did lap them: what the band is for
    chip, targets = frames(390, "large")
    row_top, row_bottom = targets[5][1], targets[5][3]
    middle, tall = (row_top + row_bottom) / 2, chip[3] - chip[1]
    old = (chip[0], middle - tall / 2, chip[2], middle + tall / 2)
    assert [index for index, target in enumerate(targets[5:]) if overlaps(old, target)] == [2, 3], "AirPlay's and Info's"


def test_the_chip_has_a_band_of_its_own_between_the_transport_and_the_row():
    now = bare(NOW_PLAYING)
    content = member(now, "func content")
    #? stacked: the transport (its top padding alone), the band, the row - so growing text moves them together
    order = [content.index(part) for part in ("transport\n                .padding(.top, 12)\n",
                                              "SpeedChipBand(shown: chipShown)\n", "bottomRow\n")]
    assert order == sorted(order)
    assert ".padding(.vertical, 12)" not in content, "nothing under the transport but the band"
    between = content[order[0]:order[2]]
    assert ".offset(" not in between and ".overlay" not in between
    #? the chip is drawn in the band alone, centred in it on the line between the output's column and Info's
    assert now.count("SpeedChip(") == 1 and "SpeedChip(" in member(now, "struct SpeedChipBand: View")
    band = member(now, "struct SpeedChipBand: View")
    assert ".position(x: band.size.width * CGFloat(NowPlayingTabs.chipAt), y: band.size.height / 2)" in band
    assert "GeometryReader { (band: GeometryProxy) in\n            if shown {" in band and ".offset(" not in band
    #? drawn whether the chip shows or not: the band's frame is outside the `if shown`
    assert member(band, "var body: some View").rstrip().endswith(".frame(height: CGFloat(TurntableFace.hit))")
    #? the row hangs nothing over itself any more (the readout's layer is the column's, the plinth's)
    row = member(now, "var bottomRow: some View")
    assert "overlay" not in row and "anchorPreference" not in now and "FooterGap" not in now
    assert now.count("overlayPreferenceValue(") == 1 and "overlayPreferenceValue(PlinthPlaceKey.self)" in now


# ----------------------------------------------------------------------------- the notice

def test_the_notice_clears_the_chevron_the_look_button_and_the_menu():
    """R3's review, 2: centred over the whole row with 48 points either side, a notice wider than about 150 points
    covered the look button and left it dead for its 5 seconds. It is the row's middle now - as wide as the chevron,
    the look button and the ••• leave it - and takes no touch."""
    now = bare(NOW_PLAYING)
    top = member(now, "func topRow")
    stack = top[top.index("HStack {"):]
    row = block(stack, stack.index("{"))
    parts = ("Button(action: close)", "Spacer(minLength: 0)\n                .overlay {", "Notice(text: notice)",
             "LookButton(showingTurntable:", "menu(track)")
    order = [row.index(part) for part in parts]
    assert order == sorted(order), order
    #? the notice is the middle's overlay, never the row's: nothing after the row's brace draws it
    after = stack[stack.index(row) + len(row):]
    assert re.sub(r"\s+", " ", after).strip() == "} .animation(.default, value: player.notice)", after
    notice = row[row.index("Notice(text: notice)"):row.index("LookButton(")]
    assert ".fixedSize(horizontal: false, vertical: true)" in notice, "as tall as its lines, as wide as the middle"
    assert ".allowsHitTesting(false)" in notice, "it takes no touch"
    assert ".padding(.horizontal, 48)" not in now
    #? worked out: what the middle has on the narrower phone, with the look button there - room for words
    content = member(now, "func content")
    inset = number(content, r"\.padding\(\.horizontal, (\d+)\)\n\s*\.padding\(\.bottom, \d+\)\s*$")
    buttons = 3 * 44
    middle = 375 - 2 * inset - buttons - 3 * HSTACK_SPACING
    padding = 2 * number(bare(APP / "Shared" / "Notice.swift"), r"\.padding\(\.horizontal, (\d+)\)")
    assert middle - padding >= 120, middle


# ----------------------------------------------------------------------------- VoiceOver, part by part

def test_the_queue_says_what_is_on():
    now = bare(NOW_PLAYING)
    item = member(now, "func sheetItem")
    assert "case .upNext: upNextLabel(shuffle: player.shuffle, repeat: player.repeatMode)" in item
    assert "PhoneTabItem(words: words, shown: false, spoken: spoken, action: { tapped(button) })" in item


def test_the_eq_says_the_outputs_setting():
    now = bare(NOW_PLAYING)
    item = member(now, "struct EQRowItem: View")
    assert "spoken: NowPlayingTabs.Words.eq(setting: eq.now.short), action: action)" in item
    assert "EQRowItem { tapped(.eq) }" in member(now, "var bottomRow: some View")


def test_lyrics_dimmed_does_nothing_and_says_why():
    now = bare(NOW_PLAYING)
    item = member(now, "var lyricsItem: some View")
    assert "let dimmed = Lyrics.dimmed(have, on: on)" in item
    assert ".disabled(dimmed)\n        .opacity(dimmed ? Palette.off : 1)" in item
    assert "spoken: LyricsWords.label(have, device: Platform.device)," in item
    assert "PhoneTabItem(words: NowPlayingTabs.Words.button(.lyrics) ?? LyricsWords.lyrics, shown: on," in item


def test_the_output_is_airplays_picker_alone_saying_where_it_plays():
    now = bare(NOW_PLAYING)
    item = member(now, "struct OutputItem: View")
    #? the glyph and the name drawn over the picker are hidden, and take no touch; the picker is under the whole column
    drawn = item[item.index("VStack(spacing: CGFloat(PhoneLook.tabGap)) {"):item.index(".background {")]
    for part in (".frame(maxWidth: .infinity)", ".lookHeight(PhoneLook.tabItem)", ".allowsHitTesting(false)",
                 ".accessibilityHidden(true)"):
        assert part in drawn, part
    assert drawn.index(".lookHeight(PhoneLook.tabItem)") < drawn.index(".allowsHitTesting(false)")
    background = block(item, item.index("{", item.index(".background {")))
    assert background.strip() == "AirPlayButton(glyph: false, playsTo: name)"
    assert "let name = eq.settings.setting(for: eq.route).shownName" in item and "Text(name)" in drawn
    assert "Image(systemName: NowPlayingTabs.symbol(.output) ?? \"\")" in code(NOW_PLAYING)
    #? the picker: AirPlay by name, where it plays as its value, its glyph hidden there
    picker = bare(AIRPLAY)
    dress = member(picker, "private func dress")
    for line in ("picker.accessibilityLabel = NowPlayingWords.airPlay", "picker.accessibilityValue = playsTo",
                 "picker.tintColor = glyph ? UIColor.label : UIColor.clear",
                 "picker.activeTintColor = glyph ? UIColor(Palette.accent) : UIColor.clear"):
        assert line in dress, line
    assert "dress(picker)" in member(picker, "func makeUIView") and "dress(picker)" in member(picker, "func updateUIView")
    assert "var glyph = true" in picker and "var playsTo: String?" in picker
    #? the Mac's two keep AirPlay's glyph, with no value
    for name in ("Player/PlayerBar.swift", "Player/MacOutput.swift"):
        path = APP / name
        if path.exists():
            assert "AirPlayButton(glyph:" not in bare(path), name


def test_a_tab_item_says_spoken_before_its_words():
    item = bare(TAB_ITEM)
    assert ".accessibilityLabel(spoken ?? words)" in item
    assert "var spoken: String?" in item


# ----------------------------------------------------------------------------- the EQ's readers

def test_only_the_rows_eq_and_output_read_the_eq():
    """R3's review, 4: Now Playing read the EQ itself, so every slider moved redrew it. Its own code reads none of it
    now; the row's EQ and output, views of their own, are the only readers in the file."""
    now = bare(NOW_PLAYING)
    view = member(now, "struct NowPlayingView: View")
    assert not re.search(r"\beq\.", view), re.search(r"\beq\.", view)
    assert "EQModel" not in view
    readers = [match.start() for match in re.finditer(r"@Environment\(EQModel\.self\) private var eq\b", now)]
    assert len(readers) == 2
    for name in ("struct EQRowItem: View", "struct OutputItem: View"):
        assert "@Environment(EQModel.self) private var eq" in member(now, name), name
    #? and no other view in the file reads it
    others = now
    for name in ("struct EQRowItem: View", "struct OutputItem: View"):
        others = others.replace(member(now, name), "")
    assert not re.search(r"\beq\.", others)
