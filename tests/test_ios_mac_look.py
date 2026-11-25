"""
The Mac redesign's look (slice R1, notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"): the
window as James approved it on the design canvas, whose stylesheet is kept beside the app at ios/design/dw.css (outside
App/, so it is never bundled). The Mac's look is dw.css's and nothing else:

  - MacPalette (App/Mac/Look) holds dw.css's tokens under their own names, each the custom property's colour, and each
    part's own colours with the rule and property they come from (`// dw: .btn background`) - held here colour by
    colour, so a colour moved off dw.css, or one with no rule named, fails.
  - MacLook (Core) holds its sizes, MacCorners its radii and Typeface.Mac its type sizes - each the rule's own number,
    or (two sizes and two type sizes) the drawings' own inline styles, said here.
  - Nothing in App/Mac, nor the sidebar it draws, writes a colour, a radius or a font of its own: MacPalette's,
    MacCorners' and Typeface.Mac's (or Typeface.symbol's, for a glyph) only.

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
PALETTE = MAC / "Look" / "MacPalette.swift"
CORNERS = MAC / "Look" / "MacCorners.swift"
LOOK = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "MacLook.swift"
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

def swift_colours(expression: str) -> list[tuple[int, int, int, float]]:
    """The colours a MacPalette line makes, in order: hex(0x...) and rgba(r, g, b, a)."""
    found = []
    for match in re.finditer(r"hex\(0x([0-9a-fA-F]{6})\)|rgba\((\d+), (\d+), (\d+), ([0-9.]+)\)", expression):
        if match.group(1):
            digits = match.group(1)
            found.append((int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), 1.0))
        else:
            found.append((int(match.group(2)), int(match.group(3)), int(match.group(4)), float(match.group(5))))
    return found


PALETTE_LINE = re.compile(r"^    static let (\w+)(?:: [\w.]+)? = (.+?)\s*// (.+)$")
#? where a part says it comes from: `dw: <selector> <property>`, and which of the property's colours when it has more
#? than one (a box-shadow's layer), counting from 1
SOURCE = re.compile(r"dw: (.+?) ([a-z-]+)(?: (\d+))?")
#? the only ways MacPalette makes a colour: dw.css's own numbers through its three makings
COLOUR_CALL = r"(?:hex\(0x[0-9a-f]{6}\)|rgba\(\d{1,3}, \d{1,3}, \d{1,3}, [0-9.]+\))"
MADE = re.compile(rf"{COLOUR_CALL}|vertical\({COLOUR_CALL}, {COLOUR_CALL}\)"
                  rf"|vertical\(\({COLOUR_CALL}, [0-9.]+\)(?:, \({COLOUR_CALL}, [0-9.]+\))+\)")


def palette() -> dict[str, tuple[str, str]]:
    """MacPalette's lines: name -> (its expression, where it says it comes from)."""
    lines = {}
    for line in PALETTE.read_text(encoding="utf-8").splitlines():
        found = PALETTE_LINE.match(line)
        if found:
            lines[found.group(1)] = (found.group(2), found.group(3).strip())
    return lines


def palette_problems(text: str) -> list[str]:
    """What in MacPalette.swift's text is not a dw.css colour said with its source: every line of the enum before its
    makings is a comment or a colour line (`static let <name> = <made> // <source>`), each made only by the makings
    from numbers (MADE) - the one Double, `off`, the web's - and after the makings, only the makings."""
    problems = []
    head, marker, makings = text.partition("    // MARK: the makings")
    if not marker:
        return ["MacPalette.swift has no `// MARK: the makings`"]
    for number, line in enumerate(head.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped in ("import SwiftUI", "enum MacPalette {"):
            continue
        found = PALETTE_LINE.match(line)
        if not found:
            problems.append(f"MacPalette.swift:{number} not a colour with its source: {stripped}")
        elif found.group(3).strip().startswith("web: "):
            if not re.fullmatch(r"static let \w+: Double = [0-9.]+", line.split("//")[0].strip()):
                problems.append(f"MacPalette.swift:{number} only a number is the web's: {stripped}")
        elif not MADE.fullmatch(found.group(2)):
            problems.append(f"MacPalette.swift:{number} a colour not made from dw.css's numbers: {found.group(2)}")
    code = bare(makings)
    if re.search(r"\bstatic (let|var)\b", code):
        problems.append("MacPalette.swift: a colour after its makings")
    if re.findall(r"\bprivate static func (\w+)\(", code) != ["hex", "rgba", "vertical", "vertical"] \
            or re.search(r"\b(?<!private )static func\b", code):
        problems.append("MacPalette.swift: its makings are hex, rgba and vertical (twice), private, and nothing more")
    return problems


def test_macpalette_is_dw_css_colours_and_nothing_else():
    assert not palette_problems(PALETTE.read_text(encoding="utf-8")), palette_problems(PALETTE.read_text(encoding="utf-8"))
    # and no other file adds to it
    for name, text in drawn_in_the_look().items():
        assert not re.search(r"\bextension MacPalette\b", bare(text)), name


def test_the_palette_reading_refuses_what_it_is_for():
    text = PALETTE.read_text(encoding="utf-8")
    at = text.index("    static let bg = ")
    for planted in ("    static let extra = Color.purple\n",                        # a system colour, no source
                    "    static let extra = Color.purple                // --extra\n",  # with a source
                    "    static let extra = hex(0xc084fc).opacity(0.5)  // --acc\n",   # a number of its own on dw.css's
                    "    static let extra: Double = 0.5\n",                          # a number, no source
                    "    static var extra = hex(0xc084fc)               // --acc\n"):  # not a constant
        assert palette_problems(text[:at] + planted + text[at:]), planted
    end = text.rindex("}")
    assert palette_problems(text[:end] + "    static let extra = hex(0xc084fc)\n" + text[end:])
    assert palette_problems(text[:end] + "    static func tinted() -> Color { .purple }\n" + text[end:])
    assert not palette_problems(text)


#? a part drawn from a box-shadow says what it is by its name, and the layer it names is that: a sheen is the white
#? highlight, a drop the dark shadow under, a shade the dark one inside, a ring a spread ring round the edge
SHADOW_PARTS = {
    "Sheen": lambda layer, colour: colour[:3] == (255, 255, 255),
    "Drop": lambda layer, colour: colour[:3] == (0, 0, 0) and not layer.startswith("inset"),
    "Shade": lambda layer, colour: colour[:3] == (0, 0, 0) and layer.startswith("inset"),
    "Ring": lambda layer, colour: bool(re.fullmatch(r"0 0 0 \d+px \S+", layer)),
}


def test_every_colour_in_the_palette_is_one_dw_css_names():
    lines = palette()
    assert len(lines) > 60, "the palette is read"
    for name, (expression, source) in lines.items():
        made = swift_colours(expression)
        if source.startswith("web: "):
            continue
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
        if expression.startswith("vertical("):
            # a gradient: every stop the rule's, in its order
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
        assert token[2:] in lines and lines[token[2:]][1] == token, f"MacPalette has no {token}"
    # --mono is the type's: the bundled face's family
    assert rule(".dw")["--mono"].startswith('"Noto Sans Mono"')
    assert re.search(r'static let monoFamily = "Noto Sans Mono"', TYPEFACE.read_text(encoding="utf-8"))


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
    found = re.findall(r"static let (\w+): CGFloat = ([0-9.]+)\s*// dw: (\S+) border-radius", text)
    assert {name for name, _, _ in found} == {"button", "box", "chip"}, found
    for name, value, selector in found:
        assert float(value) == px(rule(selector)["border-radius"]), name
    assert [(n, float(v)) for n, v, _ in found] == [("button", 4), ("box", 5), ("chip", 3)]
    # a folder tab's top is a box's: .tab's 5px 5px 0 0
    assert rule(".tab")["border-radius"] == "5px 5px 0 0"
    assert "UnevenRoundedRectangle(topLeadingRadius: box, topTrailingRadius: box, style: .circular)" in text
    # the iPhone's corners are as they were: every one 0 (test_ios_palette.py holds them)
    phone = (APP / "Shared" / "Corners.swift").read_text(encoding="utf-8")
    assert re.findall(r"static let \w+: CGFloat = (\d+)", phone) == ["0"] * 5


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
    # at fixed sizes, as a Mac's own windows draw theirs; the words Noto Sans, the data Noto Sans Mono
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
    files = {path.relative_to(APP).as_posix(): path.read_text(encoding="utf-8") for path in sorted(MAC.rglob("*.swift"))}
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


def test_nothing_in_the_macs_views_draws_a_value_of_its_own():
    files = drawn_in_the_look()
    assert len(files) > 25, "App/Mac is read"
    left = []
    for name, text in files.items():
        code = bare(text)
        if name != "Mac/Look/MacPalette.swift":
            for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                                  ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                                  ("the iPhone's palette", r"\bPalette\."),
                                  ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]")):
                if re.search(pattern, code):
                    left.append(f"{name}: {what}")
            if NAMED_COLOUR.search(code):
                left.append(f"{name}: a named colour ({NAMED_COLOUR.search(code).group(0)})")
        if name != "Mac/Look/MacCorners.swift":
            for what, pattern in (("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b|[(:]\s*\.capsule\b|"
                                                r"Corners\."),):
                found = [m.group(0) for m in re.finditer(pattern, code) if not code[:m.start()].endswith("Mac")]
                if found:
                    left.append(f"{name}: {what} ({found[0]})")
        for argument in font_arguments(code):
            if not re.match(r"Typeface\.(Mac\.(text|mono)|symbol)\(", argument):
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
    # and none of what the Mac's views write of their own: MacPalette's colours, modifiers named like a style, a
    # Color-typed property, the kinds and tones named for what they do, Color.clear
    for clean in ("let x = MacPalette.text\n.alignment(.leading)", "view.tint(MacPalette.acc)",
                  "view.background(MacPalette.well, in: MacCorners.buttonShape)", "view.background { face }",
                  "case .plain: return MacPalette.t2", "Color.clear.frame(width: 1)", "view.buttonStyle(.plain)",
                  "private var text: Color {", "MacChip(words: w, tone: .bad)", "MacButtonStyle(kind: .danger)",
                  "view.toolbar(.hidden, for: .tabBar)", "view.foregroundStyle(MacPalette.selt)"):
        assert not NAMED_COLOUR.search(bare(clean + "\n")), clean
    assert font_arguments(bare(".font(Typeface.body)\n")) == ["Typeface.body"]
    assert re.search(r"cornerRadius|RoundedRectangle\(", bare("RoundedRectangle(cornerRadius: 4)\n"))
    # MacCorners' own shapes are no radius of a view's own
    code = bare("MacCorners.buttonShape.fill(MacPalette.well)\n")
    assert not [m for m in re.finditer(r"Corners\.", code) if not code[:m.start()].endswith("Mac")]


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
    code = bare((MAC / "Components" / "MacSegmented.swift").read_text(encoding="utf-8"))
    seg, button, on, large = rule(".seg"), rule(".seg button"), rule(".seg button.on"), rule(".seg.lg button")
    assert seg["background"] == "var(--well)" and ".background(MacPalette.well, in: MacCorners.buttonShape)" in code
    assert seg["border"] == "1px solid var(--line)" and "MacPalette.line, lineWidth: 1" in code
    assert seg["border-radius"] == rule(".btn")["border-radius"] and ".clipShape(MacCorners.buttonShape)" in code
    assert button["background"] == "none" and button["border"] == "0" and ".buttonStyle(.plain)" in code
    assert "MacRaised" not in code and "MacButtonStyle" not in code
    assert button["color"] == "var(--t2)" and "on ? MacPalette.selt : MacPalette.t2" in code
    assert on["color"] == "var(--selt)"
    assert on["background"] == "var(--selbg)" and ".fill(MacPalette.selbg)" in code
    assert on["box-shadow"] == "inset 0 0 0 1px var(--selbd)" and ".strokeBorder(MacPalette.selbd, lineWidth: 1)" in code
    # its sizes and words: .seg button's and .seg.lg button's
    assert (button["padding"], large["padding"]) == ("0 8px", "0 10px") and ".padding(.horizontal, large ? 10 : 8)" in code
    assert (px(button["font-size"]), px(large["font-size"]), button["font-weight"]) == (11.5, 12.5, "600")
    assert "Typeface.Mac.text(large ? .control : .label).weight(.semibold)" in code
    assert "MacLook.largeSegmentHeight : MacLook.segmentHeight" in code
