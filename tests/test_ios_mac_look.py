"""
The Mac redesign's look (slice R1, notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"; since
R1b, "The redesign, slice R1b: the shared look, and the phone's pieces"): the window as James approved it on the design
canvas, whose stylesheet is kept beside the app at ios/design/dw.css (outside App/, so it is never bundled). The Mac's
look is dw.css's and nothing else:

  - DWPalette (App/Look, since R1b both devices') holds dw.css's tokens under their own names, each the custom
    property's colour, and the shared parts' colours with the rule and property they come from (`// dw: .btn
    background`); MacPalette (App/Mac/Look) the Mac's own parts' alone, the same way - each held here colour by colour,
    so a colour moved off dw.css, or one with no rule named, fails. (DWPalette's phone lines, `// dw.ph: ...`, are
    test_ios_phone_look.py's, held to the phone's rules.)
  - MacLook (Core) holds the Mac's sizes and DWLook's Mac half names them, DWCorners' Mac half its radii, and
    Typeface.Mac its type sizes (Typeface.Look's Mac half naming them) - each the rule's own number, or (two sizes and
    two type sizes) the drawings' own inline styles, said here.
  - Nothing in App/Mac, App/Look, nor the sidebar the Mac draws, writes a colour, a radius or a font of its own:
    DWPalette's and MacPalette's, DWCorners' and Typeface.Mac's or Typeface.Look's (or Typeface.symbol's, for a glyph)
    only.

dw.css is the canvas's copy as it is now, the phone's own rules (`.dw.ph`, 25 Nov: square corners, the bare-glyph
transport) included - and read for the Mac without them: a `.dw.ph` selector is never the Mac's.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
DW = IOS / "design" / "dw.css"
APP = IOS / "App"
MAC = APP / "Mac"
LOOK_DIR = APP / "Look"
PALETTE = LOOK_DIR / "DWPalette.swift"
MAC_PALETTE = MAC / "Look" / "MacPalette.swift"
CORNERS = LOOK_DIR / "DWCorners.swift"
LOOK = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "MacLook.swift"
DWLOOK = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "DWLook.swift"
PRIMARY = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "PrimaryButton.swift"
TYPEFACE = APP / "Shared" / "Typeface.swift"
APP_CSS = REPO / "interface" / "player" / "app.css"
#? the sidebar is a frame file outside App/Mac, redrawn in R1 in the Mac's look
DRAWN_IN_THE_LOOK = ["Root/MacSidebarView.swift"]


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


# ----------------------------------------------------------------------------- reading dw.css

#? the phone's own rules on the canvas (James, 25 Nov: "Both together" - the phone square, its transport bare glyphs):
#? never the Mac's
PHONE_ONLY = ".dw.ph"


def rules() -> list[tuple[list[str], dict[str, str]]]:
    """Each rule of dw.css: its selectors and its declarations - the phone's own selectors (`.dw.ph ...`) left out, and a
    rule with none but those left out whole."""
    text = re.sub(r"/\*.*?\*/", "", DW.read_text(encoding="utf-8"), flags=re.S)
    found = []
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", text):
        selectors = [part.strip() for part in match.group(1).split(",")
                     if not part.strip().startswith(PHONE_ONLY)]
        if not selectors:
            continue
        declarations = {}
        for declaration in match.group(2).split(";"):
            if ":" in declaration:
                name, _, value = declaration.partition(":")
                declarations[name.strip()] = value.strip()
        found.append((selectors, declarations))
    return found


def rule(selector: str) -> dict[str, str]:
    """Every declaration of `.dw <selector>` (or `.dw` itself), wherever dw.css says it - later ones winning."""
    wanted = ".dw" if selector == ".dw" else f".dw {selector}"
    merged: dict[str, str] = {}
    for selectors, declarations in rules():
        if wanted in selectors:
            merged.update(declarations)
    assert merged, f"dw.css has no {wanted}"
    return merged


def colours(value: str) -> list[tuple[int, int, int, float]]:
    """The colours in a CSS value, in order: #rgb, #rrggbb and rgba()."""
    found = []
    for match in re.finditer(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b|rgba\((\d+),\s*(\d+),\s*(\d+),\s*([0-9.]+)\)", value):
        if match.group(1):
            digits = match.group(1)
            if len(digits) == 3:
                digits = "".join(c * 2 for c in digits)
            found.append((int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), 1.0))
        else:
            found.append((int(match.group(2)), int(match.group(3)), int(match.group(4)), float(match.group(5))))
    return found


def layers(value: str) -> list[str]:
    """A box-shadow's layers: its value split at the commas outside parentheses."""
    found, depth, start = [], 0, 0
    for at, char in enumerate(value):
        depth += {"(": 1, ")": -1}.get(char, 0)
        if char == "," and depth == 0:
            found.append(value[start:at].strip())
            start = at + 1
    found.append(value[start:].strip())
    return found


def px(value: str) -> float:
    found = re.match(r"([0-9.]+)px\b", value)
    assert found, value
    return float(found.group(1))


# ----------------------------------------------------------------------------- reading the Swift

def primary_colours() -> dict[str, tuple[int, int, int, float]]:
    """Core PrimaryButton's colours (the phone's purple): name -> (r, g, b, a)."""
    found = {}
    for name, args in re.findall(r"public static let (\w+) = DeckRGBA\(([^)]*)\)", PRIMARY.read_text(encoding="utf-8")):
        parts = [part.strip() for part in args.split(",")]
        found[name] = (int(parts[0], 0), int(parts[1], 0), int(parts[2], 0), float(parts[3]) if len(parts) > 3 else 1.0)
    return found


def swift_colours(expression: str) -> list[tuple[int, int, int, float]]:
    """The colours a palette line makes, in order: hex(0x...), rgba(r, g, b, a) and deck(PrimaryButton.x)."""
    found = []
    for match in re.finditer(r"hex\(0x([0-9a-fA-F]{6})\)|rgba\((\d+), (\d+), (\d+), ([0-9.]+)\)"
                             r"|deck\(PrimaryButton\.(\w+)\)", expression):
        if match.group(1):
            digits = match.group(1)
            found.append((int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), 1.0))
        elif match.group(6):
            found.append(primary_colours()[match.group(6)])
        else:
            found.append((int(match.group(2)), int(match.group(3)), int(match.group(4)), float(match.group(5))))
    return found


PALETTE_LINE = re.compile(r"^    static let (\w+)(?:: [\w.]+)? = (.+?)\s*// (.+)$")
#? where a part says it comes from: `dw: <selector> <property>`, and which of the property's colours when it has more
#? than one (a box-shadow's layer), counting from 1
SOURCE = re.compile(r"dw: (.+?) ([a-z-]+)(?: (\d+))?")
#? the ways a palette makes a colour: dw.css's own numbers through its makings - and DWPalette's purple, the app's own
#? (Core PrimaryButton's, the phone's: `.dw.ph .btn.pri` is that colour)
COLOUR_CALL = r"(?:hex\(0x[0-9a-f]{6}\)|rgba\(\d{1,3}, \d{1,3}, \d{1,3}, [0-9.]+\))"
MADE = re.compile(rf"{COLOUR_CALL}|vertical\({COLOUR_CALL}, {COLOUR_CALL}\)"
                  rf"|vertical\(\({COLOUR_CALL}, [0-9.]+\)(?:, \({COLOUR_CALL}, [0-9.]+\))+\)")
DECK_CALL = r"deck\(PrimaryButton\.(?:top|bottom|edge|highlight|label)\)"
LOOK_CALL = rf"(?:{COLOUR_CALL}|{DECK_CALL})"
LOOK_MADE = re.compile(rf"{LOOK_CALL}|vertical\({LOOK_CALL}, {LOOK_CALL}\)|horizontal\({COLOUR_CALL}, {COLOUR_CALL}\)")
#? the phone's primary pressed: PrimaryButton's own darkened press (PrimaryFace's), the web's `--dw-primary-pressed` -
#? dw.css draws no pressed state - DWPalette's alone, and only under that source
PRESSED_CALL = r"deck\(PrimaryButton\.(?:pressedTop|pressedBottom|pressedEdge)\)"
PRESSED_MADE = re.compile(rf"{PRESSED_CALL}|vertical\({PRESSED_CALL}, {PRESSED_CALL}\)")
PRESSED_SOURCE = "web: --dw-primary-pressed"


class Palette:
    """One palette file: its enum, the lines it may open with, how it may make a colour, and its makings."""

    def __init__(self, path: Path, enum: str, heads: tuple[str, ...], made: re.Pattern, makings: list[str],
                 pressed: bool = False):
        self.path, self.enum, self.heads, self.made, self.makings = path, enum, heads, made, makings
        #? whether it may hold the phone's pressed primary (PRESSED_MADE, the web's)
        self.pressed = pressed


#? the two palettes: DWPalette, both devices' (the tokens, the shared parts, the phone's own), and MacPalette, the Mac's
#? own parts alone - each made only by its own makings
PALETTES = {
    "Look/DWPalette.swift": Palette(PALETTE, "DWPalette", ("import DeadwaxCore", "import SwiftUI", "enum DWPalette {"),
                                    LOOK_MADE, ["hex", "rgba", "deck", "vertical", "horizontal"], pressed=True),
    "Mac/Look/MacPalette.swift": Palette(MAC_PALETTE, "MacPalette", ("import SwiftUI", "enum MacPalette {"), MADE,
                                         ["hex", "rgba", "vertical", "vertical"]),
}


def palette(path: Path = PALETTE) -> dict[str, tuple[str, str]]:
    """A palette's lines: name -> (its expression, where it says it comes from)."""
    lines = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        found = PALETTE_LINE.match(line)
        if found:
            lines[found.group(1)] = (found.group(2), found.group(3).strip())
    return lines


def palette_problems(text: str, spec: Palette) -> list[str]:
    """What in a palette file's text is not a dw.css colour said with its source: every line of the enum before its
    makings is a comment or a colour line (`static let <name> = <made> // <source>`), each made only by the makings
    from numbers (the palette's own `made`) - the web's: the one Double, `off`, and DWPalette's pressed primary
    (PrimaryButton's own press) - and after the makings, only the makings."""
    problems, name = [], spec.path.name
    head, marker, makings = text.partition("    // MARK: the makings")
    if not marker:
        return [f"{name} has no `// MARK: the makings`"]
    for number, line in enumerate(head.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped in spec.heads:
            continue
        found = PALETTE_LINE.match(line)
        if not found:
            problems.append(f"{name}:{number} not a colour with its source: {stripped}")
        elif found.group(3).strip().startswith("web: "):
            number_line = re.fullmatch(r"static let \w+: Double = [0-9.]+", line.split("//")[0].strip())
            pressed = spec.pressed and found.group(3).strip() == PRESSED_SOURCE and PRESSED_MADE.fullmatch(found.group(2))
            if not (number_line or pressed):
                problems.append(f"{name}:{number} only a number and the pressed primary are the web's: {stripped}")
        elif not spec.made.fullmatch(found.group(2)):
            problems.append(f"{name}:{number} a colour not made from dw.css's numbers: {found.group(2)}")
    code = bare(makings)
    if re.search(r"\bstatic (let|var)\b", code):
        problems.append(f"{name}: a colour after its makings")
    if re.findall(r"\bprivate static func (\w+)\(", code) != spec.makings \
            or re.search(r"\b(?<!private )static func\b", code):
        problems.append(f"{name}: its makings are {', '.join(spec.makings)}, private, and nothing more")
    return problems


def test_the_palettes_are_dw_css_colours_and_nothing_else():
    for name, spec in PALETTES.items():
        text = spec.path.read_text(encoding="utf-8")
        assert not palette_problems(text, spec), palette_problems(text, spec)
        # and no other file adds to it
        for other, code in drawn_in_the_look().items():
            assert not re.search(rf"\bextension {spec.enum}\b", bare(code)), (name, other)


def test_the_palette_reading_refuses_what_it_is_for():
    for name, spec in PALETTES.items():
        text = spec.path.read_text(encoding="utf-8")
        at = text.index("    // MARK: ", text.index(f"enum {spec.enum} {{"))
        for planted in ("    static let extra = Color.purple\n",                        # a system colour, no source
                        "    static let extra = Color.purple                // --extra\n",  # with a source
                        "    static let extra = hex(0xc084fc).opacity(0.5)  // --acc\n",   # a number of its own
                        "    static let extra: Double = 0.5\n",                          # a number, no source
                        "    static var extra = hex(0xc084fc)               // --acc\n",  # not a constant
                        "    static let extra = deck(PrimaryButton.edge).opacity(0.5)  // dw.ph: .sw border\n",
                        "    static let extra = deck(TurntablePalette.ttPlinth)  // dw.ph: .sw border\n",
                        "    static let extra = horizontal(deck(PrimaryButton.top), hex(0xc084fc))  // dw.ph: .x y\n",
                        # the pressed primary: only PrimaryButton's own press, only as the web's
                        "    static let extra = deck(PrimaryButton.pressedEdge)  // dw.ph: .btn.pri border-color\n",
                        "    static let extra = deck(PrimaryButton.pressedEdge)  // web: --other\n",
                        "    static let extra = hex(0x7235da)  // web: --dw-primary-pressed\n",
                        "    static let extra = deck(PrimaryButton.edge)  // web: --dw-primary-pressed\n"):
            assert palette_problems(text[:at] + planted + text[at:], spec), (name, planted)
        end = text.rindex("}")
        assert palette_problems(text[:end] + "    static let extra = hex(0xc084fc)\n" + text[end:], spec), name
        assert palette_problems(text[:end] + "    static func tinted() -> Color { .purple }\n" + text[end:], spec), name
        assert not palette_problems(text, spec), name
    # the Mac's own palette makes no purple of the app's and no sideways gradient: those are DWPalette's alone
    mac = PALETTES["Mac/Look/MacPalette.swift"]
    text = mac.path.read_text(encoding="utf-8")
    at = text.index("    // MARK: folder tabs")
    for planted in ("    static let extra = deck(PrimaryButton.edge)  // dw: .x border\n",
                    "    static let extra = deck(PrimaryButton.pressedEdge)  // web: --dw-primary-pressed\n",
                    "    static let extra = horizontal(hex(0x9333ea), hex(0xc084fc))  // dw: .x background\n"):
        assert palette_problems(text[:at] + planted + text[at:], mac), planted


#? a part drawn from a box-shadow says what it is by its name, and the layer it names is that: a sheen is the white
#? highlight, a drop the dark shadow under, a shade the dark one inside, a ring a spread ring round the edge
SHADOW_PARTS = {
    "Sheen": lambda layer, colour: colour[:3] == (255, 255, 255),
    "Drop": lambda layer, colour: colour[:3] == (0, 0, 0) and not layer.startswith("inset"),
    "Shade": lambda layer, colour: colour[:3] == (0, 0, 0) and layer.startswith("inset"),
    "Ring": lambda layer, colour: bool(re.fullmatch(r"0 0 0 \d+px \S+", layer)),
}


def test_every_colour_in_the_palette_is_one_dw_css_names():
    every = {}
    for name, spec in PALETTES.items():
        lines = palette(spec.path)
        assert not set(lines) & set(every), f"{name}: a name in both palettes: {set(lines) & set(every)}"
        every.update(lines)
    assert len(palette(PALETTE)) > 70 and len(palette(MAC_PALETTE)) > 25, "the palettes are read"
    for name, (expression, source) in every.items():
        if source.startswith(("web: ", "dw.ph: ")):
            # the web's opacity (below); the phone's own, test_ios_phone_look.py's
            continue
        made = swift_colours(expression)
        assert made, f"{name}: no colour read from {expression}"
        if source.startswith("--"):
            # a token: the custom property's own value, under its own name
            assert source == f"--{name}", f"{name} is dw.css's {source}: name it so"
            assert made == colours(rule(".dw")[source]), f"{name}: {made} is not dw.css's {source}"
            continue
        found = SOURCE.fullmatch(source)
        assert found, f"{name}: say `dw: <selector> <property>` - {source}"
        selector, prop, position = found.groups()
        declarations = rule(selector)
        assert prop in declarations, f"{name}: dw.css's {selector} has no {prop}"
        value = declarations[prop]
        css = colours(value)
        if expression.startswith(("vertical(", "horizontal(")):
            # a gradient: every stop the rule's, in its order, and its way
            direction = "to bottom" if expression.startswith("vertical(") else "to right"
            assert value.startswith(f"linear-gradient({direction},"), f"{name}: {selector}'s {prop} is {value}"
            assert position is None, f"{name}: a gradient is the whole of {selector}'s {prop}"
            assert made == css, f"{name}: {made} is not {selector}'s {prop} {css}"
            stops = re.findall(r"#[0-9a-fA-F]{6} ([0-9.]+)%", value)
            places = re.findall(r"\), ([0-9.]+)\)", expression)
            if stops:
                assert [float(s) / 100 for s in stops] == [float(p) for p in places[1:-1]], name
            continue
        assert len(made) == 1, f"{name}: one colour, {made}"
        if len(css) == 1:
            assert position is None, f"{name}: {selector}'s {prop} has one colour - name no layer"
            at = 1
        else:
            assert position, f"{name}: {selector}'s {prop} has {len(css)} colours - say which: `dw: {selector} {prop} N`"
            at = int(position)
            assert 1 <= at <= len(css), f"{name}: {selector}'s {prop} has no colour {at}"
        assert made == [css[at - 1]], f"{name}: {made} is not colour {at} of {selector}'s {prop} {css}"
        if prop == "box-shadow":
            shadow = layers(value)
            assert [len(colours(layer)) for layer in shadow] == [1] * len(shadow), f"{selector}: a colour a layer"
            kinds = [kind for kind in SHADOW_PARTS if name.endswith(kind)]
            assert kinds, f"{name}: a box-shadow's part is a Sheen, a Drop, a Shade or a Ring, by its name"
            assert SHADOW_PARTS[kinds[0]](shadow[at - 1], made[0]), \
                f"{name}: {selector}'s box-shadow layer {at} ({shadow[at - 1]}) is no {kinds[0].lower()}"


def test_every_dw_css_token_is_in_the_palette():
    tokens = {name for name in rule(".dw") if name.startswith("--")}
    assert len(tokens) == 19, tokens
    lines = palette()
    for token in sorted(tokens - {"--mono"}):
        assert token[2:] in lines and lines[token[2:]][1] == token, f"DWPalette has no {token}"
    # one set, both devices': the Mac's own palette holds none of them
    assert not [name for name, (_, source) in palette(MAC_PALETTE).items() if source.startswith("--")]
    # --mono is the type's: the bundled readout face's family - and .dw's font names the words' (25 Nov: Libre Franklin
    # and Courier Prime, in place of Noto Sans and Noto Sans Mono)
    assert rule(".dw")["--mono"].startswith('"Courier Prime"')
    assert re.search(r'static let monoFamily = "Courier Prime"', TYPEFACE.read_text(encoding="utf-8"))
    assert '"Libre Franklin"' in rule(".dw")["font"]
    assert re.search(r'static let family = "Libre Franklin"', TYPEFACE.read_text(encoding="utf-8"))


def test_the_faded_opacity_is_the_web_apps():
    lines = palette()
    expression, source = lines["off"]
    assert source == "web: --app-pin-off"
    css = re.search(r"--app-pin-off:\s*([0-9.]+);", APP_CSS.read_text(encoding="utf-8")).group(1)
    assert float(expression) == float(css)


# ----------------------------------------------------------------------------- sizes, corners, type

#? MacLook's sizes, each a dw.css rule's own number
LOOK_FROM_CSS = {
    "sidebarWidth": (".side", "width"), "barHeight": (".player", "height"), "titleHeight": (".titlebar", "height"),
    "toolbarHeight": (".bar", "height"), "statusHeight": (".status", "height"), "headerHeight": (".cols", "height"),
    "rowHeight": (".row", "height"), "groupRowHeight": (".row.grp", "height"), "navRowHeight": (".nav", "height"),
    "findHeight": (".find", "height"), "buttonHeight": (".btn", "height"), "smallButtonHeight": (".btn.sm", "height"),
    "fieldHeight": (".in", "height"), "labelWidth": (".field > label", "width"),
    "segmentHeight": (".seg button", "height"), "largeSegmentHeight": (".seg.lg button", "height"),
    "chipHeight": (".chip", "height"), "countHeight": (".count", "height"), "grooveHeight": (".groove", "height"),
    "tabStripHeight": (".tabs", "height"), "tabHeight": (".tab", "height"), "chosenTabHeight": (".tab.on", "height"),
    "keySize": (".key", "width"), "bigKeySize": (".key.big", "width"), "toggleSize": (".tog", "width"),
}
#? and two of the drawings' own inline styles, not dw.css's rules: the side panel (Albums.dc.html's 400px) and Edit an
#? album's folder list (Main.dc.html's 398px)
LOOK_FROM_DRAWINGS = {"panelWidth": 400, "folderListWidth": 398}


def test_mac_look_is_dw_css_size_by_size():
    found = dict(re.findall(r"public static let (\w+): Double = ([0-9.]+)\n", LOOK.read_text(encoding="utf-8")))
    assert set(found) == set(LOOK_FROM_CSS) | set(LOOK_FROM_DRAWINGS), set(found) ^ (set(LOOK_FROM_CSS) | set(LOOK_FROM_DRAWINGS))
    for name, (selector, prop) in LOOK_FROM_CSS.items():
        assert float(found[name]) == px(rule(selector)[prop]), f"MacLook.{name} is not {selector}'s {prop}"
    for name, size in LOOK_FROM_DRAWINGS.items():
        assert float(found[name]) == size, name
    # the plan's sizes (the build plan's section 2): sidebar 220, panel 400, bar 66, title 28, toolbar 40, header 24,
    # row 30, group row 26, status 24, tab strip 35, folder list 398, button 26 (small 22), field 24, label 84, keys 34/46
    assert [float(found[n]) for n in ("sidebarWidth", "panelWidth", "barHeight", "titleHeight", "toolbarHeight",
                                      "headerHeight", "rowHeight", "groupRowHeight", "statusHeight", "tabStripHeight",
                                      "folderListWidth", "buttonHeight", "smallButtonHeight", "fieldHeight",
                                      "labelWidth", "keySize", "bigKeySize")] == \
        [220, 400, 66, 28, 40, 24, 30, 26, 24, 35, 398, 26, 22, 24, 84, 34, 46]


def test_mac_corners_are_dw_css_radii():
    text = CORNERS.read_text(encoding="utf-8")
    mac = text[text.index("    enum Mac {"):text.index("    enum Phone {")]
    found = re.findall(r"static let (\w+): CGFloat = ([0-9.]+)\s*// dw: (.+?) border-radius", mac)
    #? (R8) and the meter's: .meter's 2, its fill's (.meter > i) 1
    assert len(re.findall(r"static let", mac)) == 5, "the Mac's half: dw.css's five"
    assert {name for name, _, _ in found} == {"button", "box", "chip", "meter", "meterFill"}, found
    for name, value, selector in found:
        assert float(value) == px(rule(selector)["border-radius"]), name
    assert [(n, float(v)) for n, v, _ in found] == [("button", 4), ("box", 5), ("chip", 3), ("meter", 2),
                                                    ("meterFill", 1)]
    # a folder tab's top is a box's: .tab's 5px 5px 0 0
    assert rule(".tab")["border-radius"] == "5px 5px 0 0"
    assert "UnevenRoundedRectangle(topLeadingRadius: box, topTrailingRadius: box, style: .circular)" in text
    # the iPhone's corners are as they were: every one 0 (test_ios_palette.py holds them), DWCorners' phone half theirs
    phone = (APP / "Shared" / "Corners.swift").read_text(encoding="utf-8")
    assert re.findall(r"static let \w+: CGFloat = (\d+)", phone) == ["0"] * 5
    # on the Mac, the Mac's: the device's one flag
    assert "static var button: CGFloat { Platform.mac ? Mac.button : Phone.button }" in text


def lookfields(start: str) -> list[tuple[str, str, str]]:
    """A DWLook made in DWLook.swift: each field's (name, value, its comment)."""
    text = DWLOOK.read_text(encoding="utf-8")
    made = text[text.index(start):]
    made = made[:made.index(")\n") + 1]
    return re.findall(r"^\s*(\w+): ([\w.]+)\)?,?\s*(?://\s*(.*))?$", made, re.M)


def side(value: str, which: str) -> str:
    """One side of a CSS padding shorthand."""
    words = value.split()
    words = {1: words * 4, 2: words * 2, 3: words + [words[1]], 4: words}[len(words)]
    return words[["top", "right", "bottom", "left"].index(which)]


def test_dwlooks_mac_sizes_are_r1s():
    # the shared parts' sizes on the Mac (Core DWLook.onMac): MacLook's own, or the rule's number - R1's, unchanged
    maclook = dict(re.findall(r"public static let (\w+): Double = ([0-9.]+)\n", LOOK.read_text(encoding="utf-8")))
    fields = lookfields("static let onMac = DWLook(")
    assert [name for name, _, _ in fields][-2:] == ["target", "grows"] and len(fields) == 22, fields
    for name, value, source in fields[:-2]:
        found = re.fullmatch(r"dw: (.+) ([a-z-]+)", source)
        assert found, f"DWLook.onMac.{name}: say `dw: <selector> <property>` - {source}"
        selector, prop = found.groups()
        number = float(maclook[value[len("MacLook."):]]) if value.startswith("MacLook.") else float(value)
        if prop.startswith("padding-"):
            css = px(side(rule(selector)["padding"], prop[len("padding-"):]))
        else:
            css = px(rule(selector)[prop])
        assert number == css, f"DWLook.onMac.{name} {number} is not {selector}'s {prop} {css}"
    # every height the Mac's look drew in R1 is MacLook's own name, never a copy of its number
    named = {name: value for name, value, _ in fields}
    for name in ("buttonHeight", "smallButtonHeight", "fieldHeight", "chipHeight", "countHeight", "segmentHeight",
                 "largeSegmentHeight", "toggleSize", "rowHeight", "groupRowHeight", "labelWidth"):
        assert named[name] == f"MacLook.{name}", name
    assert named["target"] == "0" and named["grows"] == "false"


def test_the_looks_mac_type_is_r1s():
    # Typeface.Look's Mac half: Typeface.Mac's sizes, each the rule's - as R1's components drew them
    text = TYPEFACE.read_text(encoding="utf-8")
    mac = text[text.index("    enum Mac {"):]
    sizes = dict(re.findall(r"case (\w+) = ([0-9.]+)\n", mac[mac.index("enum Size"):mac.index("static func text")]))
    look = text[text.index("    enum Look {"):text.index("    enum Phone {")]
    lines = re.findall(r"case \.(\w+): return \.(\w+)\s*// dw: (.+) (font-size|font)\n", look[look.index("var mac:"):])
    assert len(lines) == 9, lines
    for role, size, selector, prop in lines:
        css = rule(selector)[prop]
        assert float(sizes[size]) == px(css.split()[1] if prop == "font" else css), f"Typeface.Look.{role}"
    # R1's components' own: a button .control (small .small), a field .base, a label .control, a chip and a segment
    # .label (large .control), a count .count
    assert {role: size for role, size, _, _ in lines} == {
        "button": "control", "smallButton": "small", "largeButton": "control", "field": "base", "fieldLabel": "control",
        "chip": "label", "count": "count", "segment": "label", "largeSegment": "control"}


#? Typeface.Mac's sizes: each a dw.css rule's own font size - or, for two, the drawings' own (inline styles)
TYPE_FROM_CSS = {"h1": (".h1", "font-size"), "brand": (".brand", "font-size"), "lcd": (".lcd .b", "font-size"),
                 "control": (".btn", "font-size"), "small": (".s", "font-size"), "label": (".xs", "font-size")}
TYPE_FROM_DRAWINGS = {"h2": 20, "h3": 18}


def test_the_macs_type_is_dw_css_size_by_size():
    text = TYPEFACE.read_text(encoding="utf-8")
    mac = text[text.index("    enum Mac {"):]
    sizes = dict(re.findall(r"case (\w+) = ([0-9.]+)\n", mac[mac.index("enum Size"):mac.index("static func text")]))
    assert set(sizes) == set(TYPE_FROM_CSS) | set(TYPE_FROM_DRAWINGS) | {"base", "count"}
    for name, (selector, prop) in TYPE_FROM_CSS.items():
        assert float(sizes[name]) == px(rule(selector)[prop]), name
    for name, size in TYPE_FROM_DRAWINGS.items():
        assert float(sizes[name]) == size, name
    # the window's words: .dw's font shorthand; a count's: .count's, in the mono face
    assert float(sizes["base"]) == px(rule(".dw")["font"].split()[1])
    count = rule(".count")["font"].split()
    assert float(sizes["count"]) == px(count[1]) and count[2] == "var(--mono)"
    # the plan's: 13, 12.5, 12, 11.5, 14, 18, 19, 20 and 28 - and the count's 11
    assert sorted(float(v) for v in sizes.values()) == [11, 11.5, 12, 12.5, 13, 14, 18, 19, 20, 28]
    # at fixed sizes, as a Mac's own windows draw theirs; the words Libre Franklin, the data Courier Prime
    assert ".custom(family, fixedSize: CGFloat(size.rawValue))" in mac
    assert ".custom(monoFamily, fixedSize: CGFloat(size.rawValue))" in mac
    # the iPhone's sizes as they were: its styles' sizes, relative to the style
    assert ".custom(family, size: size, relativeTo: style)" in text


# ----------------------------------------------------------------------------- nothing of its own in App/Mac

#? the iPhone's text styles and its data face: never the Mac's
PHONE_TYPE = re.compile(r"\bTypeface\.(largeTitle|title|title2|title3|headline|body|callout|subheadline|footnote|caption|"
                        r"caption2|mono)\b")
#? a colour of SwiftUI's or the system's, in every form it is written: Color's own (`Color.red`; Color.clear aside, which
#? draws nothing), a colour or a style by its bare name wherever a ShapeStyle or a Color goes (`return .red`,
#? `.foregroundStyle(.secondary)`, `.tint(.purple)`, `.fill(.foreground)`) - a modifier of the same name, `.tint(` or
#? `.background {`, is not one - the system's (`.systemRed`, Color(uiColor:) - Color( is refused below), and materials
COLOUR_WORDS = "white|black|gray|grey|red|green|blue|orange|yellow|pink|purple|teal|cyan|mint|indigo|brown"
STYLE_WORDS = ("primary|secondary|tertiary|quaternary|quinary|accentColor|tint|foreground|background|separator|selection|"
               "link|placeholder|multicolor|bar")
NAMED_COLOUR = re.compile(rf"\bColor\.(?!clear\b)\w+|(?<![\w.])\.(?:{COLOUR_WORDS}|{STYLE_WORDS})\b(?!\s*[({{])"
                          r"|(?<![\w.])\.(?:ultraThin|thin|regular|thick|ultraThick)Material\b|\bMaterial\b"
                          r"|(?<![\w.])\.system[A-Z]\w*|\b(?:Hierarchical|Separator|Selection|Tint)ShapeStyle\b"
                          r"|\b(?:Foreground|Background)Style\b")


def drawn_in_the_look() -> dict[str, str]:
    files = {path.relative_to(APP).as_posix(): path.read_text(encoding="utf-8")
             for folder in (MAC, LOOK_DIR) for path in sorted(folder.rglob("*.swift"))}
    for name in DRAWN_IN_THE_LOOK:
        files[name] = (APP / name).read_text(encoding="utf-8")
    return files


def font_arguments(code: str) -> list[str]:
    found = []
    for match in re.finditer(r"\.font\(", code):
        depth = 0
        for end in range(match.start() + len(".font"), len(code)):
            depth += {"(": 1, ")": -1}.get(code[end], 0)
            if depth == 0:
                break
        found.append(code[match.start() + len(".font("):end])
    return found


#? the type a file may draw: App/Look's, by role on either device (or a glyph's); App/Mac's and the sidebar's, the Mac's
#? own sizes too
LOOK_FONT = re.compile(r"Typeface\.(Look\.(text|mono)|symbol)\(")
MAC_FONT = re.compile(r"Typeface\.(Mac\.(text|mono)|Look\.(text|mono)|symbol)\(")


def test_nothing_in_the_macs_views_draws_a_value_of_its_own():
    files = drawn_in_the_look()
    assert len(files) > 30 and len([name for name in files if name.startswith("Look/")]) == 10, "App/Mac and App/Look"
    left = []
    for name, text in files.items():
        code = bare(text)
        if name not in PALETTES:
            for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                                  ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                                  ("the iPhone's palette", r"\bPalette\."),
                                  ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]")):
                if re.search(pattern, code):
                    left.append(f"{name}: {what}")
            if NAMED_COLOUR.search(code):
                left.append(f"{name}: a named colour ({NAMED_COLOUR.search(code).group(0)})")
        if name != "Look/DWCorners.swift":
            for what, pattern in (("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b|[(:]\s*\.capsule\b|"
                                                r"Corners\."),):
                found = [m.group(0) for m in re.finditer(pattern, code) if not code[:m.start()].endswith("DW")]
                if found:
                    left.append(f"{name}: {what} ({found[0]})")
        for argument in font_arguments(code):
            if not (LOOK_FONT if name.startswith("Look/") else MAC_FONT).match(argument):
                left.append(f"{name}: .font({argument})")
        if re.search(r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\bUIFont\b|\.monospaced\(\)", code) \
                or PHONE_TYPE.search(code):
            left.append(f"{name}: a font of its own")
    assert not left, left


def test_the_matcher_catches_what_it_is_for():
    # the reading above refuses each kind of value of its own, planted
    for planted in ('Color(red: 1, green: 0, blue: 0)', "Color.red", ".foregroundStyle(.white)", "Palette.accent",
                    ".opacity(0.5)", "hex(0xffffff)", "Color(uiColor: .systemRed)"):
        code = bare(f"let x = {planted}\n")
        hits = [re.search(p, code) for p in (r"\bColor\s*\(|\bUIColor\b|\bCGColor\b", r"0x[0-9a-fA-F]{6}\b",
                                             r"\bPalette\.", r"\.opacity\(\s*0?\.[0-9]")]
        assert any(hits) or NAMED_COLOUR.search(code), planted
    # a named or a semantic colour, in each form it's written
    for planted in ("switch kind {\ncase .plain: return .red\n}", "Text(x)\n    .foregroundStyle(.secondary)",
                    "view.tint(.purple)", "Color.accentColor", "shape.fill(.foreground)", "Text(x).foregroundStyle(.tint)",
                    "view.background(.ultraThinMaterial)", "shape.fill(.background)", "Text(x).foregroundStyle(.primary)",
                    "Image(systemName: s).symbolRenderingMode(.multicolor)", "view.background(.bar)",
                    "Text(x).foregroundColor(.white.opacity(0.5))", "LinearGradient(colors: [.purple, .black], "
                    "startPoint: .top, endPoint: .bottom)", "view.foregroundStyle(.background.secondary)",
                    "let s: HierarchicalShapeStyle = .secondary", "view.background(Material.thin)"):
        assert NAMED_COLOUR.search(bare(planted + "\n")), planted
    # and none of what the look's views write of their own: the palettes' colours, modifiers named like a style, a
    # Color-typed property, the kinds and tones named for what they do, Color.clear
    for clean in ("let x = DWPalette.text\n.alignment(.leading)", "view.tint(DWPalette.acc)",
                  "view.background(DWPalette.well, in: DWCorners.buttonShape)", "view.background { face }",
                  "case .plain: return DWPalette.t2", "Color.clear.frame(width: 1)", "view.buttonStyle(.plain)",
                  "private var text: Color {", "DWChip(words: w, tone: .bad)", "DWButtonStyle(kind: .danger)",
                  "view.toolbar(.hidden, for: .tabBar)", "view.foregroundStyle(DWPalette.selt)",
                  "view.foregroundStyle(MacPalette.keyText)", "drop: Color.clear"):
        assert not NAMED_COLOUR.search(bare(clean + "\n")), clean
    assert font_arguments(bare(".font(Typeface.body)\n")) == ["Typeface.body"]
    assert re.search(r"cornerRadius|RoundedRectangle\(", bare("RoundedRectangle(cornerRadius: 4)\n"))
    # DWCorners' own shapes are no radius of a view's own; the iPhone's Corners named in the look are
    code = bare("DWCorners.buttonShape.fill(DWPalette.well)\n")
    assert not [m for m in re.finditer(r"Corners\.", code) if not code[:m.start()].endswith("DW")]
    code = bare("Corners.controlShape.fill(DWPalette.well)\n")
    assert [m for m in re.finditer(r"Corners\.", code) if not code[:m.start()].endswith("DW")]
    # App/Look draws by role, never the Mac's own sizes: those would be the Mac's on the phone
    assert not LOOK_FONT.match("Typeface.Mac.text(.base)") and MAC_FONT.match("Typeface.Mac.text(.base)")
    assert LOOK_FONT.match("Typeface.Look.text(.chip).weight(.semibold)") and LOOK_FONT.match("Typeface.symbol(.body)")


# ----------------------------------------------------------------------------- the canvas's copy, and the segmented control

def test_dw_css_is_the_canvas_copy_read_without_the_phones_rules():
    raw = DW.read_text(encoding="utf-8")
    # the copy of 25 Nov: the phone square, its transport bare glyphs
    assert re.search(r"\.dw\.ph \.btn, \.dw\.ph \.seg, \.dw\.ph \.chip,[^{]*\{ border-radius: 0; \}", raw)
    assert ".dw.ph .np .key, .dw.ph .mini .key, .dw.ph .key.bare { border: 0; background: none; box-shadow: none;" in raw
    # never read for the Mac: no selector of the phone's is in a rule read, and the Mac's values are its own
    assert not [s for selectors, _ in rules() for s in selectors if s.startswith(PHONE_ONLY)]
    assert re.search(r"\.dw\.ph \.chip \{ height: 22px;", raw) and rule(".chip")["height"] == "19px"
    assert rule(".btn")["border-radius"] == "4px" and rule(".key")["border"].startswith("1px solid")


def test_the_segmented_control_is_dw_css_seg():
    # .seg: a well with the line's edge and a button's corners, its segments plain words, the chosen one the
    # selection's fill inside its edge - no raised face (that's .btn's), so none drawn
    code = bare((LOOK_DIR / "DWSegmented.swift").read_text(encoding="utf-8"))
    seg, button, on, large = rule(".seg"), rule(".seg button"), rule(".seg button.on"), rule(".seg.lg button")
    assert seg["background"] == "var(--well)" and ".background(DWPalette.well, in: DWCorners.buttonShape)" in code
    assert seg["border"] == "1px solid var(--line)" and "DWPalette.line, lineWidth: 1" in code
    assert seg["border-radius"] == rule(".btn")["border-radius"] and ".clipShape(DWCorners.buttonShape)" in code
    assert button["background"] == "none" and button["border"] == "0" and ".buttonStyle(.plain)" in code
    assert "DWRaised" not in code and "DWButtonStyle" not in code
    assert button["color"] == "var(--t2)" and "on ? DWPalette.selt : DWPalette.t2" in code
    assert on["color"] == "var(--selt)"
    assert on["background"] == "var(--selbg)" and ".fill(DWPalette.selbg)" in code
    assert on["box-shadow"] == "inset 0 0 0 1px var(--selbd)" and ".strokeBorder(DWPalette.selbd, lineWidth: 1)" in code
    # its sizes and words: .seg button's and .seg.lg button's, DWLook's on the Mac - R1's 8 and 10, 20 and 24
    assert (button["padding"], large["padding"]) == ("0 8px", "0 10px")
    assert ".padding(.horizontal, CGFloat(large ? look.largeSegmentPadding : look.segmentPadding))" in code
    mac = {name: value for name, value, _ in lookfields("static let onMac = DWLook(")}
    assert (mac["segmentPadding"], mac["largeSegmentPadding"]) == ("8", "10")
    assert (mac["segmentHeight"], mac["largeSegmentHeight"]) == ("MacLook.segmentHeight", "MacLook.largeSegmentHeight")
    assert (px(button["font-size"]), px(large["font-size"]), button["font-weight"]) == (11.5, 12.5, "600")
    assert "Typeface.Look.text(large ? .largeSegment : .segment).weight(.semibold)" in code
    assert ".lookHeight(large ? look.largeSegmentHeight : look.segmentHeight)" in code
    # on the Mac, the keyboard's: focused, ← and → - as R1's
    mac_half = code[code.index("if Platform.mac {"):code.index("} else {")]
    for part in (".fixedSize()", ".focusable()", ".focused($focused)", ".focusEffectDisabled()", ".arrowKeys {"):
        assert part in mac_half, part
