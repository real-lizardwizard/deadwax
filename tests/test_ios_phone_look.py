"""
The redesign's shared look and the phone's own pieces (slice R1b, notes/ios.md "The redesign, slice R1b: the shared look,
and the phone's pieces"; the build plan's 2, 3.1 and 3.2). James, 25 Nov: "Both together" - each shared piece built for
the Mac and the iPhone at once, each in its own device's sizes, corners and type - and "keep the phone square as well".

The phone's look is dw.css's `.dw.ph` rules, read as a browser reads them: the canvas restyled the phone twice, so a
property can be set by an earlier `.dw.ph` rule and again by a later one, and only the cascade says which holds. So this
resolves it - each rule's selectors matched against the element a comment names, specificity first, then the later rule
- and holds every phone number and colour to the rule its comment names:

  - Core's DWLook (`.of(.iPhone)`) and PhoneLook, Typeface.Look's phone half and Typeface.Phone, DWPalette's `dw.ph:`
    lines and DWCorners' phone half - each the cascade's value, a few the drawings' own inline styles, said here.
  - The phone's purple is the app's own, PrimaryButton's (held to theme.css by test_ios_palette.py), made from it.
  - Square: every corner the phone draws is Corners' 0; round stays round (the switch).
  - Tokens only: nothing in App/Look or App/Phone writes a colour, a radius, a font or a fixed height of its own; on the
    phone a height is a minimum, grown with the text, and a finger's target is 44 at least.
  - Drawn nowhere yet: App/Phone's pieces are named only in App/Phone, and App/Look's only where the Mac's look was.
  - (R1c, notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)") Flat: on the phone no shared piece
    draws a fill or an edge but the purple and the red button, a track, a text input's well - and the pieces the slice
    leaves as they were (the toggle, the switch, the count) and the marks (hairlines, the chosen line, a chip's dot);
    and every place you type on the phone is still a box.

The Mac's half of the same pieces is held by test_ios_mac_look.py, and who may name what by test_ios_mac_reach.py.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
DW = IOS / "design" / "dw.css"
APP = IOS / "App"
LOOK_DIR = APP / "Look"
PHONE_DIR = APP / "Phone"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"
DWLOOK = CORE / "DWLook.swift"
MACLOOK = CORE / "MacLook.swift"
PRIMARY = CORE / "PrimaryButton.swift"
TYPEFACE = APP / "Shared" / "Typeface.swift"
PALETTE = LOOK_DIR / "DWPalette.swift"
CORNERS = LOOK_DIR / "DWCorners.swift"
SHARED_CORNERS = APP / "Shared" / "Corners.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_phone_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
mac_look = _load("test_ios_mac_look")
ios_palette = _load("test_ios_palette")
fonts = _load("ios_fonts")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


# ----------------------------------------------------------------------------- the cascade

class Compound:
    """One compound selector (`a.on::before`), or the element a comment names made from one."""

    def __init__(self, text: str):
        found = re.fullmatch(r"([a-zA-Z][\w-]*|\*)?((?:\.[\w-]+|\[[^\]]*\]|::?[\w-]+(?:\([^)]*\))?)*)", text)
        assert found, f"not a compound selector: {text}"
        self.tag = None if found.group(1) in (None, "*") else found.group(1)
        parts = re.findall(r"\.[\w-]+|\[[^\]]*\]|::?[\w-]+(?:\([^)]*\))?", found.group(2))
        # :not(x) (R1c's flat block: div.well:not(.sfield), .key:not(.bare)) - one compound inside, never a list
        nots = [p for p in parts if p.startswith(":not(")]
        assert not [n for n in nots if "," in n or " " in n.strip()], f"{text}: only :not(<one compound>) is read"
        self.nots = tuple(Compound(n[len(":not("):-1]) for n in nots)
        self.classes = frozenset(p[1:] for p in parts if p.startswith("."))
        self.attrs = frozenset(p for p in parts if p.startswith("["))
        self.pseudo = frozenset(p[1:] for p in parts if p.startswith(":") and not p.startswith("::")
                                and not p.startswith(":not("))
        elements = [p[2:] for p in parts if p.startswith("::")]
        self.element = elements[0] if elements else None

    def takes(self, element: "Compound") -> bool:
        """Whether this compound, as a rule's, matches `element`."""
        return ((self.tag is None or self.tag == element.tag) and self.classes <= element.classes
                and self.attrs <= element.attrs and self.pseudo <= element.pseudo and self.element == element.element
                and not any(inner.names(element) for inner in self.nots))

    def names(self, element: "Compound") -> bool:
        """Whether this compound, as a :not()'s inside, names `element` - its pseudo-element aside."""
        return ((self.tag is None or self.tag == element.tag) and self.classes <= element.classes
                and self.attrs <= element.attrs and self.pseudo <= element.pseudo)


def parse_selector(text: str) -> list[tuple[str | None, Compound]]:
    """A selector as its compounds from left to right, each with the combinator joining it to the one before."""
    chain, pending = [], " "
    for token in re.sub(r"\s*([>+~])\s*", r" \1 ", text.strip()).split():
        if token in (">", "+", "~"):
            pending = token
            continue
        chain.append((pending if chain else None, Compound(token)))
        pending = " "
    return chain


def specificity(chain: list[tuple[str | None, Compound]]) -> tuple[int, int, int]:
    # a :not() counts as what it holds
    compounds = [c for _, c in chain] + [inner for _, c in chain for inner in c.nots]
    classes = sum(len(c.classes) + len(c.attrs) + len(c.pseudo) for c in compounds)
    tags = sum((c.tag is not None) + (c.element is not None) for c in compounds)
    return (0, classes, tags)


def matches(chain: list[tuple[str | None, Compound]], path: list[Compound], at: int | None = None) -> bool:
    """Whether a rule's selector matches the last element of `path` (the root first) - read right to left."""
    at = len(path) - 1 if at is None else at
    combinator, last = chain[-1]
    if not last.takes(path[at]):
        return False
    if len(chain) == 1:
        return True
    if combinator == ">":
        return at > 0 and matches(chain[:-1], path, at - 1)
    if combinator == " ":
        return any(matches(chain[:-1], path, i) for i in range(at - 1, -1, -1))
    return False  # a sibling combinator: the path an element is named by has no siblings


def split_value(value: str) -> list[str]:
    """A value's words, split at the spaces outside parentheses and quotes."""
    words, depth, quote, start = [], 0, None, 0
    for at, char in enumerate(value + " "):
        if quote:
            quote = None if char == quote else quote
        elif char in "\"'":
            quote = char
        elif char in "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == " " and depth == 0:
            if value[start:at].strip():
                words.append(value[start:at].strip())
            start = at + 1
    return words


SIDES = ("top", "right", "bottom", "left")


def four(words: list[str]) -> list[str]:
    """CSS's one to four values as top, right, bottom and left."""
    return {1: lambda w: w * 4, 2: lambda w: [w[0], w[1], w[0], w[1]], 3: lambda w: [w[0], w[1], w[2], w[1]],
            4: lambda w: w}[len(words)](words)


def border_parts(value: str) -> tuple[str, str, str]:
    """A border shorthand's width, style and colour."""
    if value in ("0", "none"):
        return "0", "none", "currentcolor"
    width, style, colour = "medium", "none", "currentcolor"
    for word in split_value(value):
        if re.fullmatch(r"-?[0-9.]+(px)?", word):
            width = word
        elif word in ("solid", "dashed", "dotted", "none", "double"):
            style = word
        else:
            colour = word
    return width, style, colour


def expand(name: str, value: str) -> list[tuple[str, str]]:
    """A declaration as the longhands it sets."""
    if name in ("padding", "margin"):
        return [(f"{name}-{side}", part) for side, part in zip(SIDES, four(split_value(value)))]
    if name == "border":
        width, style, colour = border_parts(value)
        return [(f"border-{side}-{what}", part) for side in SIDES
                for what, part in (("width", width), ("style", style), ("color", colour))]
    if name in (f"border-{side}" for side in SIDES):
        width, style, colour = border_parts(value)
        return [(f"{name}-width", width), (f"{name}-style", style), (f"{name}-color", colour)]
    if name in ("border-color", "border-width", "border-style"):
        what = name.split("-")[1]
        return [(f"border-{side}-{what}", part) for side, part in zip(SIDES, four(split_value(value)))]
    if name == "font":
        if value == "inherit":
            return []
        words = split_value(value)
        sized = [i for i, w in enumerate(words) if re.fullmatch(r"[0-9.]+px(/[0-9.]+(px)?)?", w)]
        assert sized, f"font: {value}"
        size, _, height = words[sized[0]].partition("/")
        weight = next((w for w in words[:sized[0]] if re.fullmatch(r"\d00|bold|normal", w)), "normal")
        parts = [("font-size", size), ("font-weight", weight), ("font-family", " ".join(words[sized[0] + 1:]))]
        return parts + ([("line-height", height)] if height else [])
    return [(name, value)]


def css_rules(text: str) -> list[tuple[int, list[str], list[tuple[str, str]]]]:
    """Each rule of a stylesheet, in order: its selectors and its declarations."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    found = []
    for order, match in enumerate(re.finditer(r"([^{}]+)\{([^{}]*)\}", text)):
        declarations = []
        for declaration in match.group(2).split(";"):
            if ":" in declaration:
                name, _, value = declaration.partition(":")
                declarations.append((name.strip(), value.strip()))
        found.append((order, [s.strip() for s in match.group(1).split(",")], declarations))
    return found


RULES = css_rules(DW.read_text(encoding="utf-8"))
#? (R1c's review) the rules as R1b drew the phone: dw.css before its flat block - what a line marked `(R1b)` is read
#? against (the Mac's own card face, the scrub tag's), so no change to the flat phone can move it
FLAT_BLOCK = "/* The phone, flat"
R1B_RULES = css_rules(DW.read_text(encoding="utf-8").partition(FLAT_BLOCK)[0])
PHONE_ROOT = Compound(".dw.ph")
MAC_ROOT = Compound(".dw")


def path_for(selector: str, root: Compound) -> list[Compound]:
    """The element a comment's selector names, under the canvas's root - each compound the child of the one before
    (`.dw` itself is the root)."""
    if selector == ".dw":
        return [root]
    return [root] + [compound for _, compound in parse_selector(selector)]


def resolved(selector: str, root: Compound = PHONE_ROOT, rules=None) -> dict[str, str]:
    """Every longhand the cascade gives the element `selector` names under `root`: the rules whose selectors match it,
    the most specific winning, then the later; !important above both; `var(--x)` read from the root's own."""
    rules = RULES if rules is None else rules
    path = path_for(selector, root)
    declared = []
    for order, selectors, declarations in rules:
        best = None
        for text in selectors:
            chain = parse_selector(text)
            if matches(chain, path):
                best = max(best or (0, 0, 0), specificity(chain))
        if best is None:
            continue
        for index, (name, value) in enumerate(declarations):
            important = "!important" in value
            for longhand, part in expand(name, value.replace("!important", "").strip()):
                declared.append(((important, best, order, index), longhand, part))
    found: dict[str, str] = {}
    for _, longhand, part in sorted(declared, key=lambda entry: entry[0]):
        found[longhand] = part
    if path != [root]:
        tokens = resolved(".dw", root, rules)
        found = {name: re.sub(r"var\((--[\w-]+)\)", lambda m: tokens[m.group(1)], value) for name, value in found.items()}
    return found


#? a comment's property as the longhand that holds what the line is: a border's (or a side's) colour, a font's size
LONGHAND = {"border": "border-top-color", "border-color": "border-top-color", "border-top": "border-top-color",
            "border-bottom": "border-bottom-color", "font": "font-size"}


def css(selector: str, prop: str, root: Compound = PHONE_ROOT, rules=None) -> str:
    found = resolved(selector, root, rules)
    longhand = LONGHAND.get(prop, prop)
    assert longhand in found, f"dw.css gives {selector} no {prop} ({sorted(found)})"
    return found[longhand]


def px(value: str) -> float:
    found = re.fullmatch(r"(-?[0-9.]+)(px)?", value.strip())
    assert found and (found.group(2) or float(found.group(1)) == 0), value
    return float(found.group(1))


# ----------------------------------------------------------------------------- the cascade's own tests

def test_the_cascade_takes_the_later_phone_rule():
    # the canvas restyled the phone twice: .field's min-height is 42, then 40, then 44 - each rule as specific as the
    # others, the last holding; a row 44 then 48; a label 92 wide then 88
    text = DW.read_text(encoding="utf-8")
    assert [m.start() for m in re.finditer(r"\.dw\.ph \.field \{ min-height: (\d+)px", text)]
    assert re.findall(r"\.dw\.ph \.field \{ min-height: (\d+)px", text) == ["42", "40", "44"]
    assert px(css(".field", "min-height")) == 44
    assert re.findall(r"\.dw\.ph \.row \{ height: (\d+)px", text) == ["44", "48"] and px(css(".row", "height")) == 48
    assert px(css(".field > label", "width")) == 88 and px(css(".field > label", "font-size")) == 16
    # the Mac's root never takes a phone rule
    assert px(css(".field", "min-height", MAC_ROOT)) == 28 and px(css(".chip", "height", MAC_ROOT)) == 19


def test_the_cascade_is_specificity_then_order():
    rules = css_rules(".dw.ph .x { height: 1px; } .dw .x { height: 2px; } .dw .x.y { height: 3px; }"
                      ".dw .x { width: 4px; } .dw .x { width: 5px; } .dw .x { color: #fff !important; } "
                      ".dw.ph .x { color: #000; } .dw .p > .x { top: 6px; } .dw .x::after { top: 7px; }")
    # the more specific wins though it came first; the later of two as specific; !important above both
    assert resolved(".x", PHONE_ROOT, rules)["height"] == "1px" and resolved(".x", MAC_ROOT, rules)["height"] == "2px"
    assert resolved(".x.y", PHONE_ROOT, rules)["height"] == "3px"
    assert resolved(".x", PHONE_ROOT, rules)["width"] == "5px" and resolved(".x", PHONE_ROOT, rules)["color"] == "#fff"
    # a child's rule only under its parent, a pseudo-element's only on it
    assert "top" not in resolved(".x", PHONE_ROOT, rules) and resolved(".p > .x", PHONE_ROOT, rules)["top"] == "6px"
    assert resolved(".x::after", PHONE_ROOT, rules)["top"] == "7px"
    # shorthands into their longhands, a later longhand over an earlier shorthand - on the Mac's root, where R1c's
    # flat block (`.dw.ph .chips > .on { border: 0 }`) doesn't reach; on the phone's, that later shorthand over both
    found = resolved(".chips > button.on", MAC_ROOT)
    assert found["border-top-color"] == "rgba(192, 132, 252, 0.5)" and found["border-top-width"] == "1px"
    assert resolved(".chips > button.on")["border-top-width"] == "0"
    assert resolved(".chips", MAC_ROOT)["padding-left"] == "16px" and resolved(".chips", MAC_ROOT)["padding-bottom"] == "10px"
    assert resolved(".chips")["padding-bottom"] == "0" and resolved(".chips")["margin-bottom"] == "10px"
    # a font shorthand as its size, weight and family, `var()` read from the root's own: .count's 600 11px var(--mono)
    count = resolved(".count")
    assert (count["font-size"], count["font-weight"]) == ("11px", "600"), count
    assert count["font-family"].startswith('"Courier Prime"'), count["font-family"]
    synthetic = css_rules('.dw { --m: "Mono", monospace; } .dw .f { font: 600 11px var(--m); } .dw .f.g { font-size: 12px; }')
    assert resolved(".f", MAC_ROOT, synthetic) == {"font-size": "11px", "font-weight": "600",
                                                  "font-family": '"Mono", monospace'}
    assert resolved(".f.g", MAC_ROOT, synthetic)["font-size"] == "12px"
    # :last-child's rules only on a last child; a descendant's rule never on another's (.keys svg is not .tabbar's)
    assert resolved(".field")["border-bottom-color"] == "#23212b"
    assert resolved(".field:last-child")["border-bottom-width"] == "0"
    assert px(resolved(".tabbar svg")["width"]) == 24 and "width" not in resolved(".keys")


def test_the_cascade_reads_the_mac_as_r1s_reader_does():
    # every size R1 holds the Mac to, read again through the cascade on the Mac's root: the same number
    for name, (selector, prop) in mac_look.LOOK_FROM_CSS.items():
        assert px(css(selector, prop, MAC_ROOT)) == mac_look.px(mac_look.rule(selector)[prop]), name


# ----------------------------------------------------------------------------- the phone's sizes

def between(text: str, start: str, end: str | None = None) -> str:
    """The text from `start` to `end` (or to the end)."""
    at = text.index(start)
    return text[at:text.index(end, at)] if end else text[at:]


def dwlook_fields() -> list[str]:
    text = DWLOOK.read_text(encoding="utf-8")
    struct = between(text, "public struct DWLook", "public enum PhoneLook")
    return re.findall(r"^    public let (\w+): (?:Double|Bool)$", struct, re.M)


def test_dwlooks_phone_sizes_are_the_phones_rules():
    text = DWLOOK.read_text(encoding="utf-8")
    phone = between(text, "static let onPhone = DWLook(", "grows: true)") + "grows: true)"
    lines = re.findall(r"^\s*(\w+): (-?[0-9.]+),\s*// dw\.ph: (.+) ([a-z-]+)$", phone, re.M)
    fields = dwlook_fields()
    assert set(fields) - {name for name, _, _, _ in lines} == {"target", "grows"}, fields
    assert [name for name, _, _, _ in lines] == [f for f in fields if f not in ("target", "grows")], "in its order"
    for name, value, selector, prop in lines:
        found = css(selector, prop)
        want = 0 if found == "auto" and name in AUTO_HEIGHTS else px(found)
        assert float(value) == want, f"DWLook.onPhone.{name} is not .dw.ph {selector}'s {prop}"
    assert {name for name, _, selector, prop in lines if css(selector, prop) == "auto"} == AUTO_HEIGHTS
    # a finger's target and the growing aren't dw.css's: iOS's 44, the build plan's "each height a minimum"
    assert re.search(r"^\s*target: 44,\n\s*grows: true\)", phone, re.M)


#? (R1c) a height dw.css leaves to the words (`height: auto` - the flat chip's, `.dw.ph .chip`): 0 in DWLook, lookHeight's
#? minimum of nothing, so the chip is its words' own height
AUTO_HEIGHTS = {"chipHeight"}


#? PhoneLook's sizes the drawings' own inline styles give, not dw.css's rules: (R2b) iLibrary's, iArtists' and
#? iPlaylists' quiet line, `height: 32px; padding-right: 16px` (R2's titled top's three went with it)
PHONE_FROM_DRAWINGS = {"meta": 32, "metaTrail": 16}
#? the two that stand above what holds them: dw.css's top is negative (`top: -7px`), PhoneLook's lift positive
NEGATED = {"litLineLift", "legendLift"}


def test_phonelook_is_the_phones_rules_size_by_size():
    text = DWLOOK.read_text(encoding="utf-8")
    look = between(text, "public enum PhoneLook")
    declared = re.findall(r"public static let (\w+)", look)
    lines = re.findall(r"public static let (\w+): Double = (-?[0-9.]+)\s*// (dw\.ph|drawn): (.+) ([a-z-]+)\n", look)
    assert [name for name, *_ in lines] == declared and len(declared) > 45, set(declared) - {n for n, *_ in lines}
    for name, value, source, selector, prop in lines:
        if source == "drawn":
            assert name in PHONE_FROM_DRAWINGS and float(value) == PHONE_FROM_DRAWINGS[name], name
            continue
        want = px(css(selector, prop))
        assert float(value) == (-want if name in NEGATED else want), f"PhoneLook.{name} is not .dw.ph {selector}'s {prop}"
    assert {name for name, _, source, _, _ in lines if source == "drawn"} == set(PHONE_FROM_DRAWINGS)
    # the plan's sizes (the build plan's section 2): card rows 44/42/46, mini player 60, tab bar 83 (items 49), foot 68,
    # top 44, large title 34 - and the lit line 24 x 2; (R2b) the Library's row 52; (R1c) the strip's words 40 tall and
    # 22 apart, and Find's and the •••'s box 36 x 34 (bare glyphs now: `.dw.ph .circ`)
    numbers = {name: float(value) for name, value, *_ in lines}
    assert [numbers[n] for n in ("strip", "stripGap", "kvRow", "goRow", "mini", "tabBar", "tabItem", "foot", "top", "row",
                                 "circle", "circleHeight", "litLineWidth", "litLineHeight")] == [
        40, 22, 42, 46, 60, 83, 49, 68, 44, 52, 36, 34, 24, 2]
    assert px(css(".circ", "width")) == numbers["circle"] and px(css(".circ", "height")) == numbers["circleHeight"]
    assert css(".circ", "border-radius") == "50%" and px(css(".circ svg", "width")) == 21
    assert px(css(".big", "font-size")) == 34


def test_dwflat_is_the_flat_phones_rules():
    # (R1c) the flat phone's sizes App/Look's shared pieces draw on the phone alone, each its `.dw.ph` rule's
    text = DWLOOK.read_text(encoding="utf-8")
    flat_sizes = between(text, "public enum DWFlat", "public enum PhonePieceWords")
    declared = re.findall(r"public static let (\w+)", flat_sizes)
    lines = re.findall(r"public static let (\w+): Double = (-?[0-9.]+)\s*// dw\.ph: (.+?) ([a-z-]+)( \(R1b\))?\n",
                       flat_sizes)
    # (R1c's review) and one of R1c's own, said so - no dw.css rule's: the switch's room either side of its words
    own = re.findall(r"public static let (\w+): Double = (-?[0-9.]+)\s*// own: (.+)\n", flat_sizes)
    assert own == [("segmentRoom", "6", "the switch's room, R1c's")], own
    assert sorted([name for name, *_ in lines] + ["segmentRoom"]) == sorted(declared) and len(declared) == 9, declared
    # (R1c's review) and one as R1b drew the phone, read from the rules before the flat block: the New mark's face
    assert [name for name, *_, r1b in lines if r1b] == ["facedChipHeight"]
    assert px(css(".chip", "height", rules=R1B_RULES)) == 22 and css(".chip", "height") == "auto"
    # the drawing's large segment has no room of its own, so the 6 is the slice's - as much as a flat button's
    assert px(css(".seg.lg button", "padding-left")) == 0 and px(css(".btn", "padding-left")) == 6
    assert "R1c's own room, no rule of dw.css's" in flat_sizes and "fold under the glyphs at the standard size" in flat_sizes
    for name, value, selector, prop, r1b in lines:
        found = css(selector, prop, rules=R1B_RULES if r1b else None)
        if prop == "box-shadow":
            # a line drawn as an inset shadow at the foot - `inset 0 -2px 0 <colour>` - is its thickness
            line = re.fullmatch(r"inset 0 -(\d+)px 0 \S+", found)
            assert line, f"DWFlat.{name}: {selector}'s box-shadow is {found}"
            want = float(line.group(1))
        else:
            want = px(found)
        assert float(value) == want, f"DWFlat.{name} is not .dw.ph {selector}'s {prop}"
    # the faced two's room is the purple's and the red's alike; the chosen line is the switch's and the strip's
    assert px(css(".btn.red", "padding-left")) == px(css(".btn.pri", "padding-left")) == 16
    for selector in (".seg button.on", ".seg.lg button.on", ".chips > button.on"):
        assert css(selector, "box-shadow") == "inset 0 -2px 0 #c084fc", selector
    # the dot: a 6 pt round mark in the words' own colour, before the four tones' chips and never a plain one's
    for tone in ("green", "amber", "red", "purple"):
        dot = resolved(f".chip.{tone}::before")
        assert (dot["width"], dot["height"], dot["border-radius"], dot["background"]) == ("6px", "6px", "50%",
                                                                                         "currentColor"), tone
    assert "content" not in resolved(".chip::before")
    # the Mac draws none of them
    mac = [path.relative_to(APP).as_posix() for path in sorted((APP / "Mac").rglob("*.swift"))
           if "DWFlat" in bare(path.read_text(encoding="utf-8"))]
    assert not mac, mac


#? iOS's text styles at the standard size (test_ios_palette's), in SwiftUI's order: a size scales with the nearest,
#? the smaller on a tie, then the earlier
STYLE_ORDER = list(ios_palette.STYLES)


def nearest(points: float) -> str:
    sizes = ios_palette.IOS_SIZES
    return min(STYLE_ORDER, key=lambda style: (abs(sizes[style] - points), sizes[style], STYLE_ORDER.index(style)))


def test_the_nearest_style_rule():
    assert [nearest(p) for p in (34, 28, 17, 16, 14, 13.5, 13, 12.5, 12, 11)] == [
        "largeTitle", "title", "headline", "callout", "footnote", "footnote", "footnote", "caption", "caption", "caption2"]


def typeface() -> str:
    return TYPEFACE.read_text(encoding="utf-8")


def test_the_looks_phone_type_is_the_phones_rules_scaled():
    text = typeface()
    look = text[text.index("    enum Look {"):text.index("    enum Phone {")]
    roles = re.findall(r"case (\w+)(?:, (\w+))?(?:, (\w+))?\n", look[look.index("enum Role"):look.index("var mac:")])
    names = [name for group in roles for name in group if name]
    phone = look[look.index("var phone:"):look.index("static func text")]
    lines = re.findall(r"case \.(\w+): return \(([0-9.]+), \.(\w+)\)\s*// dw\.ph: (.+?) (font-size|font)( \(R1b\))?\n",
                       phone)
    assert [name for name, *_ in lines] == names and len(names) == 10, (names, lines)
    # (R1c's review) the New mark's faced chip, as R1b drew a chip - the rules before the flat block, 12.5 (a flat
    # chip's is 13)
    assert [name for name, *_, r1b in lines if r1b] == ["facedChip"]
    for name, points, style, selector, prop, r1b in lines:
        size = px(css(selector, prop, rules=R1B_RULES if r1b else None))
        assert float(points) == size, f"Typeface.Look {name} is not .dw.ph {selector}'s size"
        assert style == nearest(float(points)), f"{name}: {points} scales with .{nearest(float(points))}, not .{style}"
    # the Mac's fixed, as R1's; the phone's scaled, Libre Franklin and Courier Prime
    assert "Platform.mac ? Mac.text(role.mac) : .custom(family, size: role.phone.points, relativeTo: role.phone.style)" in look
    assert ".custom(Mac.monoFamily, size: role.phone.points, relativeTo: role.phone.style)" in look


#? Typeface.Phone's sizes the drawings' own inline styles give: none since R2b (iLibrary's titled top's 28 went with it)
TYPE_FROM_DRAWINGS: dict[str, float] = {}


def test_the_phones_own_type_is_its_rules_scaled():
    text = typeface()
    phone = text[text.index("    enum Phone {"):]
    sizes = re.findall(r"case (\w+)(?:, (\w+))?\n", phone[phone.index("enum Size"):phone.index("var scaled:")])
    names = [name for group in sizes for name in group if name]
    scaled = phone[phone.index("var scaled:"):phone.index("static func text")]
    lines = re.findall(r"case \.(\w+): return \(([0-9.]+), \.(\w+)\)\s*// (dw\.ph|drawn): (.+) (font-size)\n", scaled)
    assert [name for name, *_ in lines] == names and len(names) == 10, (names, lines)
    for name, points, style, source, selector, _ in lines:
        if source == "drawn":
            assert float(points) == TYPE_FROM_DRAWINGS[name], name
        else:
            assert float(points) == px(css(selector, "font-size")), f"Typeface.Phone {name} is not .dw.ph {selector}'s"
        assert style == nearest(float(points)), f"{name}: {points} scales with .{nearest(float(points))}, not .{style}"
    assert ".custom(family, size: size.scaled.points, relativeTo: size.scaled.style)" in phone
    assert ".custom(Mac.monoFamily, size: size.scaled.points, relativeTo: size.scaled.style)" in phone
    # the page's own words on the phone are 17 (.dw.ph's last), the topName's
    assert px(css(".dw", "font-size")) == 17


# ----------------------------------------------------------------------------- the phone's colours

def primary() -> dict[str, tuple[int, int, int, float]]:
    """Core PrimaryButton's colours: name -> (r, g, b, a)."""
    found = {}
    for name, args in re.findall(r"public static let (\w+) = DeckRGBA\(([^)]*)\)", PRIMARY.read_text(encoding="utf-8")):
        parts = [part.strip() for part in args.split(",")]
        found[name] = (int(parts[0], 0), int(parts[1], 0), int(parts[2], 0), float(parts[3]) if len(parts) > 3 else 1.0)
    return found


def made_colours(expression: str) -> list[tuple[int, int, int, float]]:
    """The colours a DWPalette line makes, in order: hex, rgba and deck(PrimaryButton.x)."""
    found, purple = [], primary()
    for match in re.finditer(r"hex\(0x([0-9a-fA-F]{6})\)|rgba\((\d+), (\d+), (\d+), ([0-9.]+)\)"
                             r"|deck\(PrimaryButton\.(\w+)\)", expression):
        if match.group(1):
            digits = match.group(1)
            found.append((int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), 1.0))
        elif match.group(6):
            found.append(purple[match.group(6)])
        else:
            found.append((int(match.group(2)), int(match.group(3)), int(match.group(4)), float(match.group(5))))
    return found


PHONE_SOURCE = re.compile(r"dw\.ph: (.+?) ([a-z-]+)(?: (\d+))?( \(R1b\))?")


def palette_lines() -> dict[str, tuple[str, str]]:
    lines = {}
    for line in PALETTE.read_text(encoding="utf-8").splitlines():
        found = mac_look.PALETTE_LINE.match(line)
        if found:
            lines[found.group(1)] = (found.group(2), found.group(3).strip())
    return lines


def test_the_phones_colours_are_the_phones_rules():
    lines = {name: line for name, line in palette_lines().items() if line[1].startswith("dw.ph: ")}
    assert len(lines) > 30, "the phone's colours are read"
    for name, (expression, source) in lines.items():
        found = PHONE_SOURCE.fullmatch(source)
        assert found, f"{name}: say `dw.ph: <selector> <property>` - {source}"
        selector, prop, position, r1b = found.groups()
        value = css(selector, prop, rules=R1B_RULES if r1b else None)
        wanted = mac_look.colours(value)
        made = made_colours(expression)
        if expression.startswith(("vertical(", "horizontal(")):
            direction = "to bottom" if expression.startswith("vertical(") else "to right"
            assert value.startswith(f"linear-gradient({direction},"), f"{name}: {selector}'s {prop} is {value}"
            assert position is None and made == wanted, f"{name}: {made} is not {selector}'s {prop} {wanted}"
            continue
        assert len(made) == 1, f"{name}: one colour, {made}"
        if len(wanted) == 1:
            assert position is None, f"{name}: {selector}'s {prop} has one colour - name no layer"
            at = 1
        else:
            assert position, f"{name}: {selector}'s {prop} has {len(wanted)} colours - say which"
            at = int(position)
        assert made == [wanted[at - 1]], f"{name}: {made} is not colour {at} of .dw.ph {selector}'s {prop} {wanted}"
        if prop == "box-shadow":
            layer = mac_look.layers(value)[at - 1]
            kinds = [kind for kind in SHADOW_PARTS if name.endswith(kind)]
            assert kinds and SHADOW_PARTS[kinds[0]](layer, made[0]), f"{name}: {layer} is no {kinds}"


#? a box-shadow's parts, R1's - and (R1c) a Rule: the flat strip's and switch's hairline at their foot, drawn by dw.css
#? as a 1 pt inset shadow (`inset 0 -1px 0 #1c1b22`)
SHADOW_PARTS = {**mac_look.SHADOW_PARTS, "Rule": lambda layer, colour: bool(re.fullmatch(r"inset 0 -1px 0 \S+", layer))}


def test_every_shared_part_the_phone_draws_otherwise_has_its_twin():
    # a `dw:` part (the Mac's, from App/Mac) whose `.dw.ph` value differs is drawn on the phone by its `dw.ph:` twin
    lines = palette_lines()
    shared = {name: line for name, line in lines.items() if line[1].startswith("dw: ")}
    twins = {line[1][len("dw.ph: "):] for line in lines.values() if line[1].startswith("dw.ph: ")}
    differ = []
    for name, (expression, source) in shared.items():
        selector, prop, position = mac_look.SOURCE.fullmatch(source).groups()
        mac, phone = css(selector, prop, MAC_ROOT), css(selector, prop)
        if position:
            # a box-shadow's layer: that layer alone - none on the phone where its shadow has fewer
            at = int(position) - 1
            phone_layers = mac_look.layers(phone)
            mac, phone = mac_look.layers(mac)[at], phone_layers[at] if at < len(phone_layers) else "none"
        if mac != phone:
            differ.append(name)
            if name in FLAT:
                # (R1c) a part the flat phone has none of: no fill, no edge, no shadow - a flat button's words the accent
                if name == "buttonText":
                    assert phone == resolved(".dw")["--acc"], f"{name}: {phone}"
                elif prop.startswith("border"):
                    assert resolved(selector)["border-top-width"] == "0", f"{name}: .dw.ph {selector} keeps an edge"
                else:
                    assert phone == "none", f"{name}: .dw.ph {selector}'s {prop} is {phone}"
                continue
            assert source[len("dw: "):] in twins, f"{name}: .dw.ph {selector}'s {prop} is {phone}, not {mac} - no twin"
    assert sorted(set(differ) - FLAT) == ["primaryEdge", "primaryFace", "primarySheen"], differ
    assert FLAT <= set(differ), FLAT - set(differ)
    # and no phone rule redefines a token: one set for both
    assert not [n for _, selectors, declarations in RULES if any(s.startswith(".dw.ph") for s in selectors)
                for n, _ in declarations if n.startswith("--")]


#? (R1c) the Mac's parts the flat phone draws nowhere - a secondary button's face, edge, sheen, drop and words, and the
#? tinted chips' fills and edges - its pieces drawing no face there (test_the_phone_is_flat)
FLAT = {"buttonEdge", "buttonFace", "buttonSheen", "buttonDrop", "buttonText", "amberEdge", "amberFill", "greenEdge",
        "greenFill", "redChipEdge", "redChipFill"}


#? the phone's purple: the app's own (PrimaryButton, held to theme.css by test_ios_palette.py), made from it - never
#? numbers of its own that happen to match
PURPLE = {
    "phonePrimaryEdge": "deck(PrimaryButton.edge)",
    "phonePrimaryFace": "vertical(deck(PrimaryButton.top), deck(PrimaryButton.bottom))",
    "phonePrimarySheen": "deck(PrimaryButton.highlight)",
    "phonePrimaryText": "deck(PrimaryButton.label)",
    "phonePrimaryPressedFace": "vertical(deck(PrimaryButton.pressedTop), deck(PrimaryButton.pressedBottom))",
    "phonePrimaryPressedEdge": "deck(PrimaryButton.pressedEdge)",
    "switchEdge": "deck(PrimaryButton.edge)",
    "switchFace": "vertical(deck(PrimaryButton.top), deck(PrimaryButton.bottom))",
}


def test_the_phones_purple_is_primarybuttons():
    lines = palette_lines()
    for name, expression in PURPLE.items():
        assert lines[name][0] == expression, f"{name}: {lines[name][0]} - the phone's purple is PrimaryButton's"
    # pressed, PrimaryButton's own press (PrimaryFace's, the web's brightness(0.92) - test_ios_palette.py's): the web's
    assert {name for name, (_, source) in lines.items() if source == mac_look.PRESSED_SOURCE} == {
        "phonePrimaryPressedFace", "phonePrimaryPressedEdge"}
    core = PRIMARY.read_text(encoding="utf-8")
    for end, of in (("Top", "top"), ("Bottom", "bottom"), ("Edge", "edge")):
        assert f"public static let pressed{end} = Contrast.brightness({of}, pressed)" in core, end
    assert [name for name, (expression, _) in lines.items() if "PrimaryButton" in expression] == list(PURPLE)
    purple = primary()
    # .dw.ph .btn.pri and .sw are PrimaryButton's own colours
    assert mac_look.colours(css(".btn.pri", "border-color")) == [purple["edge"]] == mac_look.colours(css(".sw", "border"))
    gradient = [purple["top"], purple["bottom"]]
    assert mac_look.colours(css(".btn.pri", "background")) == gradient == mac_look.colours(css(".sw", "background"))
    assert mac_look.colours(mac_look.layers(css(".btn.pri", "box-shadow"))[0]) == [purple["highlight"]]
    assert mac_look.colours(css(".btn.pri", "color")) == [purple["label"]]
    # and the phone's button draws it: the Mac's own purple on the Mac, the app's on the phone
    style = bare((LOOK_DIR / "DWButtonStyle.swift").read_text(encoding="utf-8"))
    face = style.index("case .pri:\n            if Platform.mac {")
    pri = style[face:style.index("case .danger:\n", face)]
    mac, phone = pri.split("} else {")
    assert "DWPalette.primaryFace" in mac and "DWPalette.phonePrimaryFace" not in mac
    # the Mac's pressed in as R1's (the gradient turned over); the phone's PrimaryFace's: the fill and the edge
    # darkened, the highlight kept, nothing turned over
    assert "pressed: pressed)" in mac and "pressed: pressed" not in phone
    phone = re.sub(r"\s+", " ", phone)
    for part in ("face: pressed ? DWPalette.phonePrimaryPressedFace : DWPalette.phonePrimaryFace",
                 "sheen: DWPalette.phonePrimarySheen",
                 "edge: pressed ? DWPalette.phonePrimaryPressedEdge : DWPalette.phonePrimaryEdge",
                 "drop: DWPalette.phonePrimaryDrop)"):
        assert part in phone, part
    assert "case .pri: return Platform.mac ? DWPalette.primaryText : DWPalette.phonePrimaryText" in style


#? what later slices draw, in DWPalette already - App/Look gains only new files after R1b (the build plan's 3.5): the
#? checkbox's fill (R11's DWCheckbox), the meter's well shade and fills (R8's DWMeter), and the tab bar's, the rows' and
#? the mini player's (R2-R4) - each a `dw:` or `dw.ph:` line, held to dw.css by the colour tests
AHEAD = {"checkFill": "dw: input[type=checkbox] accent-color", "meterShade": "dw: .meter box-shadow",
         "meterFill": "dw: .meter > i background", "meterMarked": "dw: .meter.pur > i background",
         "meterGood": "dw: .meter.grn > i background", "tabBarFace": "dw.ph: .tabbar background",
         "rowRule": "dw.ph: .row border-bottom-color", "miniFace": "dw.ph: .mini background"}


def test_the_palette_holds_what_later_slices_draw():
    lines = palette_lines()
    for name, source in AHEAD.items():
        assert name in lines and lines[name][1] == source, f"DWPalette has no {name} ({source})"
    # the meter's well and edge are the tokens; the checkbox is both devices' now, MacPalette's no more
    meter = mac_look.rule(".meter")
    assert (meter["background"], meter["border"]) == ("var(--well)", "1px solid var(--line)"), meter
    assert "checkFill" not in mac_look.palette(mac_look.MAC_PALETTE)
    checkbox = bare((APP / "Mac" / "Components" / "MacCheckbox.swift").read_text(encoding="utf-8"))
    assert "DWPalette.checkFill" in checkbox and "MacPalette.checkFill" not in checkbox


def test_the_palettes_makings_and_lines():
    text = PALETTE.read_text(encoding="utf-8")
    problems = mac_look.palette_problems(text, mac_look.PALETTES["Look/DWPalette.swift"])
    assert not problems, problems


# ----------------------------------------------------------------------------- square

def test_the_phones_corners_are_corners_square():
    text = CORNERS.read_text(encoding="utf-8")
    phone = between(text, "    enum Phone {", "    /// This device's.")
    #? (R8) and the meter's track and its fill (.meter, .meter > i), Corners' track and fill
    found = re.findall(r"static let (\w+): CGFloat = Corners\.(\w+)\s*// dw\.ph: (.+?) border-radius", phone)
    assert {name for name, _, _ in found} == {"button", "box", "chip", "meter", "meterFill"}, phone
    assert len(re.findall(r"static let", phone)) == 5, "every one Corners'"
    assert [(name, corner) for name, corner, _ in found if name.startswith("meter")] == [("meter", "track"),
                                                                                          ("meterFill", "fill")]
    shared = dict(re.findall(r"static let (\w+): CGFloat = (\d+)", SHARED_CORNERS.read_text(encoding="utf-8")))
    for name, corner, selector in found:
        assert px(css(selector, "border-radius")) == 0 == float(shared[corner]), name
    # each device's: the Mac's own, the phone's Corners' - by the device's one flag
    for name in ("button", "box", "chip", "meter", "meterFill"):
        assert f"static var {name}: CGFloat {{ Platform.mac ? Mac.{name} : Phone.{name} }}" in text
    # every corner of what the phone's pieces draw is 0 (dw.css's last block); round stays round: the switch
    for selector in (".btn", ".btn.sm", ".btn.lg", ".btn.pri", ".seg", ".chip", ".count", ".in", ".well", ".card",
                     ".group", ".tog", ".tog.sm", ".chips > button", ".tabbar > a.on::before"):
        assert px(css(selector, "border-radius")) == 0, selector
    assert css(".sw", "border-radius") == f"{px(css('.sw', 'height')) / 2:g}px"
    assert "static var roundShape: Capsule { Capsule(style: .circular) }" in text
    switch = bare((PHONE_DIR / "PhoneSwitch.swift").read_text(encoding="utf-8"))
    assert "DWCorners.roundShape" in switch and "Circle()" in switch


# ----------------------------------------------------------------------------- tokens only

def look_and_phone() -> dict[str, str]:
    files = {}
    for folder in (LOOK_DIR, PHONE_DIR):
        for path in sorted(folder.rglob("*.swift")):
            files[path.relative_to(APP).as_posix()] = path.read_text(encoding="utf-8")
    return files


def test_app_look_and_app_phone_hold_their_files():
    files = look_and_phone()
    assert sorted(name for name in files if name.startswith("Look/")) == [
        f"Look/DW{n}.swift" for n in sorted(("Palette", "Corners", "Raised", "ButtonStyle", "Field", "Chip", "Segmented",
                                             "PopUp", "ToggleStyle", "Meter", "WellField"))]
    assert sorted(name for name in files if name.startswith("Phone/")) == [
        f"Phone/Phone{n}.swift" for n in sorted(("Strip", "Top", "TabItem", "Mini", "Card", "Switch", "Foot", "Meta"))]


FONT_OF_THE_LOOK = re.compile(r"Typeface\.(?:(?:Look|Phone)\.(?:text|mono)|symbol)\(")


def test_nothing_in_app_look_or_app_phone_draws_a_value_of_its_own():
    left = []
    for name, text in look_and_phone().items():
        code = bare(text)
        if name != "Look/DWPalette.swift":
            for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                                  ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                                  ("the iPhone's palette", r"\bPalette\."),
                                  ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                                  ("the Mac's palette", r"\bMacPalette\b")):
                if re.search(pattern, code):
                    left.append(f"{name}: {what}")
            if mac_look.NAMED_COLOUR.search(code):
                left.append(f"{name}: a named colour ({mac_look.NAMED_COLOUR.search(code).group(0)})")
        if name != "Look/DWCorners.swift":
            found = [m.group(0) for m in re.finditer(r"cornerRadius|RoundedRectangle\(|\bCapsule\b|[(:]\s*\.capsule\b|"
                                                     r"Corners\.", code) if not code[:m.start()].endswith("DW")]
            if found:
                left.append(f"{name}: a radius ({found[0]})")
        for argument in mac_look.font_arguments(code):
            if not FONT_OF_THE_LOOK.match(argument):
                left.append(f"{name}: .font({argument})")
        if re.search(r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\bUIFont\b|\.monospaced\(\)", code) \
                or mac_look.PHONE_TYPE.search(code):
            left.append(f"{name}: a font of its own")
    assert not left, left


#? the fixed sizes App/Look and App/Phone may draw: marks that are drawn at their size whatever the text's (a rule's
#? 1 pt, the caret, the toggle's dot, the lit line, the seek line, the switch and its knob), and the foot's room - each
#? file's exactly these, every other height a minimum (`lookHeight`)
FIXED = {
    "Look/DWRaised.swift": ["width: vertical ? 1 : nil, height: vertical ? nil : 1"],
    # the Mac's label column, R1's exactly (the phone's is a minimum)
    "Look/DWField.swift": ["width: CGFloat(DWLook.here.labelWidth), alignment: .trailing"],
    "Look/DWPopUp.swift": ["width: 8, height: 4"],
    "Look/DWToggleStyle.swift": ["width: 4, height: 4"],
    "Phone/PhoneTabItem.swift": ["width: CGFloat(PhoneLook.litLineWidth), height: CGFloat(PhoneLook.litLineHeight)"],
    "Phone/PhoneMini.swift": ["height: CGFloat(PhoneLook.seekLine)"],
    "Phone/PhoneSwitch.swift": ["width: CGFloat(PhoneLook.knob), height: CGFloat(PhoneLook.knob)",
                                "width: CGFloat(PhoneLook.switchWidth), height: CGFloat(PhoneLook.switchHeight)"],
    "Phone/PhoneFoot.swift": ["height: keyboardUp ? 0 : height"],
    #? (R2b) the Library's circles, R1b's switch's kind, in a finger's 44 pt target round them - (R1c) bare glyphs now,
    #? centred in the 36 x 34 box the circle was
    "Phone/PhoneTop.swift": ["width: face, height: tall", "width: target, height: target"],
    #? (R1c) the chosen one's 2 pt accent line - a mark, drawn at its size whatever the text's - and a chip's dot, grown
    #? with the text by its own @ScaledMetric
    "Phone/PhoneStrip.swift": ["height: CGFloat(DWFlat.chosenLine)"],
    "Look/DWSegmented.swift": ["height: CGFloat(DWFlat.chosenLine)"],
    "Look/DWChip.swift": ["width: dot, height: dot"],
    #? (R8) a meter: its fill's width the share of its track, and its height DWLook's - on the phone grown with the text
    #? by its own @ScaledMetric, so a minimum would only let it stretch
    "Look/DWMeter.swift": ["width: track.size.width * share", "height: height"],
}


def fixed_frames(code: str) -> list[str]:
    """Every `.frame(...)` that fixes a height or a width: its arguments."""
    found = []
    for match in re.finditer(r"(?<![\w])\.?frame\(", code):
        depth, end = 0, len(code)
        for end in range(match.end() - 1, len(code)):
            depth += {"(": 1, ")": -1}.get(code[end], 0)
            if depth == 0:
                break
        arguments = re.sub(r"\s+", " ", code[match.end():end])
        if re.search(r"(?<![A-Za-z])(height|width):", arguments):
            found.append(arguments)
    return found


def lookhelpers_removed(code: str) -> str:
    """The code with the look's own two helpers taken out - the one place a height is fixed on the Mac alone."""
    for start in ("@ViewBuilder func lookHeight(", "@ViewBuilder func lookSquare("):
        if start in code:
            at = code.index(start)
            opened = code.index("{", at)
            end = reader.closing(code, opened)
            code = code[:at] + code[end + 1:]
    return code


def test_every_height_on_the_phone_is_a_minimum():
    left = []
    for name, text in look_and_phone().items():
        frames = fixed_frames(lookhelpers_removed(bare(text)))
        if frames != FIXED.get(name, []):
            left.append(f"{name}: {frames}")
    assert not left, left
    # the look's height: exact on the Mac (as R1 drew it), a minimum on the phone - DWLook's own `grows` says which
    code = bare(PALETTE.with_name("DWRaised.swift").read_text(encoding="utf-8"))
    height = code[code.index("@ViewBuilder func lookHeight("):code.index("@ViewBuilder func lookSquare(")]
    assert re.search(r"if DWLook\.here\.grows \{\s*frame\(minHeight: CGFloat\(height\)\)\s*\} else \{\s*"
                     r"frame\(height: CGFloat\(height\)\)\s*\}", height)
    square = code[code.index("@ViewBuilder func lookSquare("):code.index("struct DWTarget")]
    assert re.search(r"if DWLook\.here\.grows \{\s*frame\(minWidth: CGFloat\(side\), minHeight: CGFloat\(side\)\)\s*"
                     r"\} else \{\s*frame\(width: CGFloat\(side\), height: CGFloat\(side\)\)\s*\}", square)
    assert "static var here: DWLook { .of(Platform.device) }" in code
    # and the matcher finds a fixed height planted where a minimum belongs
    assert fixed_frames(bare(".lookHeight(PhoneLook.goRow)\n.frame(height: CGFloat(PhoneLook.goRow))\n")) == [
        "height: CGFloat(PhoneLook.goRow)"]
    assert not fixed_frames(bare(".frame(minHeight: 44)\n.frame(maxWidth: .infinity)\n"))


def test_a_fingers_target_is_44_at_least():
    code = bare(PALETTE.with_name("DWRaised.swift").read_text(encoding="utf-8"))
    target = code[code.index("struct DWTarget"):]
    # the face reaching above and below it to DWLook's target where it is shorter (Core's `reach`, DWLookTests'
    # numbers); the face's own shape where it isn't, and on the Mac. Never sideways: Grid and List, 28 wide and 6 apart,
    # would reach into each other - so the target's x and width are the face's, as SegmentReach's are
    body = re.sub(r"\s+", " ", target[target.index("func path(in rect: CGRect) -> Path {"):])
    assert body.startswith("func path(in rect: CGRect) -> Path { let reach = CGFloat(DWLook.here.reach(Double(rect.height))) "
                           "guard reach > 0 else { return face.path(in: rect) } return Path(rect.insetBy(dx: 0, dy: -reach)) }"), body
    assert not re.search(r"\bwidth\b|\.midX\b|\bdx: -", target), "a target grown sideways"
    look = DWLOOK.read_text(encoding="utf-8")
    assert re.search(r"public func reach\(_ height: Double\) -> Double \{\s*max\(0, \(target - height\) / 2\)\s*\}", look)
    # every piece a finger takes: through DWTarget, or a row 44 at least as drawn (Core's DWLookTests hold the numbers)
    files = {name: bare(text) for name, text in look_and_phone().items()}
    for name, wanted in (("Look/DWButtonStyle.swift", ".contentShape(DWTarget(face: DWCorners.buttonShape))"),
                         ("Look/DWField.swift", ".contentShape(DWTarget(face: DWCorners.buttonShape))"),
                         ("Look/DWWellField.swift", ".contentShape(DWTarget(face: DWCorners.buttonShape))"),
                         ("Look/DWSegmented.swift", ".contentShape(DWTarget(face: Rectangle()))"),
                         ("Look/DWToggleStyle.swift", ".contentShape(DWTarget(face: DWCorners.boxShape))"),
                         ("Phone/PhoneStrip.swift", ".contentShape(DWTarget(face: DWCorners.buttonShape))"),
                         ("Phone/PhoneTop.swift", ".contentShape(DWTarget(face: Rectangle()))"),
                         ("Phone/PhoneMeta.swift", ".contentShape(DWTarget(face: Rectangle()))"),
                         ("Phone/PhoneTabItem.swift", ".lookHeight(PhoneLook.tabItem)"),
                         ("Phone/PhoneSwitch.swift", ".lookHeight(DWLook.here.target)")):
        assert wanted in files[name], f"{name}: {wanted}"
    # (R1c) a flat button's target is a faced one's: both bodies' shape the same DWTarget
    assert files["Look/DWButtonStyle.swift"].count(".contentShape(DWTarget(face: DWCorners.buttonShape))") == 2
    # (R1c's review) and 44 wide at least, as a faced one's face is: a flat button's words alone can be narrower than a
    # finger - Up Next's Edit, 37.5 with its room (Libre Franklin's "Edit" at .btn.sm's 13.5, and 6 either side) - so
    # its frame is a target wide: drawn that wide, never reached past sideways
    style = files["Look/DWButtonStyle.swift"]
    flat_body = re.sub(r"\s+", " ", style[style.index("private struct DWFlatButtonBody"):style.index("private struct DWButtonBody")])
    assert re.search(r"let look = DWLook\.here .*\.frame\(minWidth: CGFloat\(look\.target\), maxWidth: fills \? \.infinity : nil\) "
                     r"\.lookHeight\([^()]*\) \.contentShape\(DWTarget\(face: DWCorners\.buttonShape\)\)", flat_body), flat_body
    assert fonts.words("Edit", 13.5, "medium") + 2 * 6 < 44
    # the strip's buttons touch: each one's target is its words and half the gap either side (the gap theirs, the
    # HStack's spacing none, the row's sides the strip's 16 less that half), 44 wide at least - Queue | Info | EQ's EQ,
    # at 15, is 43 with its room - and the shown one's line is drawn before that room, as wide as the words
    strip = re.sub(r"\s+", " ", files["Phone/PhoneStrip.swift"])
    assert "HStack(spacing: 0) {" in strip and "HStack(spacing: CGFloat" not in strip
    assert "private var room: CGFloat { CGFloat(PhoneLook.stripGap) / 2 }" in strip
    assert ".padding(.horizontal, CGFloat(PhoneLook.stripSide) - room)" in strip
    line = strip.index(".overlay(alignment: .bottom) {")
    room = strip.index(".padding(.horizontal, room) .frame(minWidth: CGFloat(DWLook.here.target)) "
                       ".contentShape(DWTarget(face: DWCorners.buttonShape))")
    assert line < room and "DWFlat.chosenLine" in strip[line:room] and strip.count(".padding(.horizontal, room)") == 1
    assert px(css(".chips", "gap")) / 2 < px(css(".chips", "padding-left"))
    assert fonts.words("EQ", 15, "medium") + px(css(".chips", "gap")) < 44
    # a field's target is its well's, under the field, and a tap there puts the cursor in it
    field = files["Look/DWField.swift"]
    well = re.sub(r"\s+", " ", field[field.index(".background {", field.index("struct DWField")):field.index("struct DWFieldRow")])
    assert ("DWWell(focused: focused) .contentShape(DWTarget(face: DWCorners.buttonShape)) .onTapGesture { focused = true }"
            in well), well
    # and no other button is drawn in them - (R1c) DWSegmented's two its devices' segments, the Mac's and the phone's
    buttons = {name: len(re.findall(r"\bButton\s*(\{|\(action:)", code)) for name, code in files.items()}
    assert {name: count for name, count in buttons.items() if count} == {
        "Look/DWSegmented.swift": 2, "Phone/PhoneStrip.swift": 1, "Phone/PhoneTop.swift": 1,
        "Phone/PhoneTabItem.swift": 1, "Phone/PhoneSwitch.swift": 1}, buttons


# ----------------------------------------------------------------------------- VoiceOver, text size, the keyboard

def test_the_phones_pieces_read_and_grow_as_the_plan_says():
    files = {name: bare(text) for name, text in look_and_phone().items()}
    strip = files["Phone/PhoneStrip.swift"]
    # the strip: a tab bar of tabs, the shown one selected; scrolled sideways when it won't fit, never wrapped
    assert ".accessibilityAddTraits(.isTabBar)" in strip and ".accessibilityAddTraits(on ? .isSelected : [])" in strip
    flat = re.sub(r"\s+", " ", strip)
    assert ("ViewThatFits(in: .horizontal) { row ScrollViewReader { (proxy: ScrollViewProxy) in "
            "ScrollView(.horizontal, showsIndicators: false) { row }") in flat and ".lineLimit(1)" in strip
    # where it scrolls, the shown button is brought into view - as it opens, and whenever it changes (a tap, the page's
    # swipe) - moving as the Library's swipe does (its chip's tap, LibraryView's .snappy, none with Reduce Motion)
    assert ".onAppear { proxy.scrollTo(shown, anchor: .center) }" in flat
    assert (".onChange(of: shown) { (_: Part, now: Part) in withAnimation(reduceMotion ? nil : .snappy) { "
            "proxy.scrollTo(now, anchor: .center) } }") in flat
    assert "button(option) .id(option)" in flat and "@Environment(\\.accessibilityReduceMotion) private var reduceMotion" in strip
    library = bare((APP / "Library" / "LibraryView.swift").read_text(encoding="utf-8"))
    assert "withAnimation(reduceMotion ? nil : .snappy) { show(chosen) }" in library
    # it starts at the leading edge (.chips), where it fits as where it scrolls
    assert ".frame(maxWidth: .infinity, alignment: .leading)" in flat
    chips = resolved(".chips")
    assert chips["display"] == "flex" and chips.get("justify-content", "normal") in ("normal", "flex-start", "start")
    # the scroll view takes no touch outside itself: the row is padded by the target's reach, so the scroll view holds
    # every button's whole 44, and the strip is drawn as tall as its words again - (R1c) its hairline at their foot, the
    # strip's 10 under it
    assert ".padding(.horizontal, CGFloat(PhoneLook.stripSide) - room) .padding(.vertical, reach)" in flat
    assert (".padding(.vertical, -reach) .background(alignment: .bottom) { DWRule(colour: DWPalette.stripRule) } "
            ".padding(.bottom, CGFloat(PhoneLook.stripFoot))") in flat
    assert "CGFloat(DWLook.here.reach(PhoneLook.strip))" in flat
    # a legend, a title and a large title are headers; a fact's row and a row that goes somewhere are one element
    card = files["Phone/PhoneCard.swift"]
    assert card.count(".accessibilityAddTraits(.isHeader)") == 1
    assert files["Phone/PhoneTop.swift"].count(".accessibilityAddTraits(.isHeader)") == 2
    assert ".accessibilityElement(children: .combine)" in card[card.index("struct PhoneKV"):card.index("struct PhoneGo")]
    assert ".accessibilityElement(children: combined ? .combine : .contain)" in card
    # the switch is iOS's switch to VoiceOver
    switch = files["Phone/PhoneSwitch.swift"]
    assert re.search(r"\.accessibilityRepresentation \{\s*Toggle\(isOn: configuration\.\$isOn\) \{\s*configuration\.label"
                     r"\s*\}\s*\.toggleStyle\(\.switch\)\s*\}", switch)
    assert "extension ToggleStyle where Self == PhoneSwitchStyle" in switch
    # a tab item: selected while shown, the Large Content Viewer's as the tab bar's
    item = files["Phone/PhoneTabItem.swift"]
    assert ".accessibilityAddTraits(shown ? .isSelected : [])" in item and ".accessibilityShowsLargeContentViewer {" in item
    # the bars cap at xxxLarge, as the tab bar does; the large title grows on, as iOS's does
    for name in ("Phone/PhoneStrip.swift", "Phone/PhoneTabItem.swift", "Phone/PhoneFoot.swift", "Phone/PhoneMeta.swift"):
        assert files[name].count(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)") == 1, name
    top = files["Phone/PhoneTop.swift"]
    assert top[:top.index("struct PhoneBack")].count(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)") == 1
    assert "dynamicTypeSize" not in top[top.index("struct PhoneBigTitle"):]
    # the foot: above the home indicator, under the keyboard - never riding up on it - its room none meanwhile
    foot = files["Phone/PhoneFoot.swift"]
    assert ".ignoresSafeArea(.keyboard, edges: .bottom)" in foot and ".ignoresSafeArea(.container, edges: .bottom)" in foot
    # the keyboard's room taken by the layer the foot is in (the page's height), not by the foot itself: a 68 pt foot
    # ignoring it moves nothing where the layer it is aligned in has risen with the keyboard
    at = foot.index("VStack(spacing: 0) {")
    end = reader.closing(foot, foot.index("{", at))
    layer = foot[at:end + 1]
    assert "Spacer(minLength: 0)" in layer and re.search(r"\bfoot\b", layer) and ".ignoresSafeArea(" not in layer
    assert re.match(r"\s*\.ignoresSafeArea\(\.keyboard, edges: \.bottom\)", foot[end + 1:])
    assert foot.count(".ignoresSafeArea(.keyboard") == 1
    assert re.search(r"\.overlay \{\s*VStack\(spacing: 0\) \{", foot)
    assert ".frame(height: keyboardUp ? 0 : height)" in foot
    assert "keyboardWillShowNotification" in foot and "keyboardWillHideNotification" in foot
    # the back link is read as iOS's own back button is: the page, then "Back"
    assert ".accessibilityLabel(PhonePieceWords.back(to: words))" in top
    assert re.search(r'public static func back\(to page: String\) -> String \{\s*"\\\(page\), Back"\s*\}',
                     DWLOOK.read_text(encoding="utf-8"))
    # the switch fades while it can't be used, as every control the app can't use does
    assert "@Environment(\\.isEnabled) private var enabled" in switch
    assert ".buttonStyle(.plain)\n        .opacity(enabled ? 1 : DWPalette.off)" in switch
    assert "PhoneSwitchRow(configuration: configuration)" in switch
    # the segmented control takes the keyboard's focus on the Mac alone
    seg = files["Look/DWSegmented.swift"]
    phone = seg[seg.index("} else {"):seg.index("private var segments")]
    assert ".focusable()" not in phone and ".arrowKeys" not in phone
    # (R1c; R2b's review) a phone segment's words in iOS's Large Content Viewer under a held finger, as the tab bar's
    segment = re.sub(r"\s+", " ", phone[phone.index("private func phoneSegment("):])
    assert ".accessibilityShowsLargeContentViewer { Text(words(option)) }" in segment
    # the Mac's toggle keeps its dot; the phone's .tog.sm draws none
    assert "if on, Platform.mac {" in files["Look/DWToggleStyle.swift"]
    assert resolved(".tog.sm.on::after")["display"] == "none"


# ----------------------------------------------------------------------------- each device's half

#? every place App/Look's shared pieces part by device, line by line - a half swapped (`!Platform.mac`), added or
#? dropped is a change here. App/Phone parts by none: it is the phone's alone.
BRANCHES = {
    #? (R1c) on the phone the flat body for every kind but the purple and the red, and the faced two's room of 16
    "Look/DWButtonStyle.swift": [
        "if Platform.mac || kind == .pri || kind == .danger {",
        "if !Platform.mac {",
        "case .normal, .on: return size == .large && !Platform.mac ? .semibold : .medium",
        "case .pri: return Platform.mac ? DWPalette.primaryText : DWPalette.phonePrimaryText",
        "if Platform.mac {"],
    #? (R1c) the Mac's chip faced, the phone's words after a dot - (R1c's review) but for a chip that keeps its face (the
    #? New mark), drawn as R1b drew a chip on the phone: its type and its height the phone's own there
    "Look/DWChip.swift": ["if Platform.mac || keepsFace {",
                          ".font(Typeface.Look.text(Platform.mac ? .chip : .facedChip).weight(.semibold))",
                          ".lookHeight(Platform.mac ? DWLook.here.chipHeight : DWFlat.facedChipHeight)"],
    "Look/DWCorners.swift": [f"static var {n}: CGFloat {{ Platform.mac ? Mac.{n} : Phone.{n} }}"
                             for n in ("button", "box", "chip", "meter", "meterFill")],
    "Look/DWField.swift": ["if Platform.mac {"],
    #? (R1c) the caret after a pop-up's words: the Mac's button words' colour, the phone's flat button's accent
    "Look/DWPopUp.swift": ["DWCaret(colour: Platform.mac ? DWPalette.buttonText : DWPalette.acc)"],
    "Look/DWRaised.swift": ["static var here: DWLook { .of(Platform.device) }"],
    "Look/DWSegmented.swift": ["if Platform.mac {", ".frame(maxWidth: large && !Platform.mac ? .infinity : nil)"],
    "Look/DWToggleStyle.swift": ["if on, Platform.mac {"],
    #? (R1c's review) a page's own field on the look's well on the phone; on the Mac the field as its page drew it
    "Look/DWWellField.swift": ["if Platform.mac {"],
}


def halves(code: str, condition: str) -> tuple[str, str]:
    """An `if <condition> { A } else { B }`'s two halves, flattened: (A, B) - B "" where there is no else."""
    at = code.index(condition)
    opened = code.index("{", at)
    end = reader.closing(code, opened)
    first = code[opened + 1:end]
    rest = code[end + 1:]
    second = ""
    if re.match(r"\s*else \{", rest):
        start = end + 1 + rest.index("{")
        second = code[start + 1:reader.closing(code, start)]
    return re.sub(r"\s+", " ", first), re.sub(r"\s+", " ", second)


def test_each_shared_piece_parts_by_device_only_where_said():
    found = {}
    for name, text in look_and_phone().items():
        lines = [line.strip() for line in bare(text).splitlines() if re.search(r"\bPlatform\.", line)]
        if lines:
            found[name] = lines
    assert found == BRANCHES, found


def test_each_device_half_of_the_shared_pieces_draws_its_own():
    files = {name: bare(text) for name, text in look_and_phone().items()}
    # a field's row: on the Mac R1's (the label trailing in a column 84 wide, the second colour, one line, no rule); on
    # the phone a card's row (the label leading, 88 at least, white, on the group's hairline)
    field = files["Look/DWField.swift"]
    mac, phone = halves(field[field.index("struct DWFieldRow"):], "if Platform.mac {")
    for part in (".frame(width: CGFloat(DWLook.here.labelWidth), alignment: .trailing)", ".foregroundStyle(DWPalette.t2)",
                 ".lineLimit(1)", ".frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))"):
        assert part in mac, part
    for part in (".frame(minWidth: CGFloat(DWLook.here.labelWidth), alignment: .leading)",
                 ".foregroundStyle(DWPalette.rowText)", ".frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))",
                 ".overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }"):
        assert part in phone, part
    assert "DWRule" not in mac and ".trailing" not in phone and "DWPalette.t2" not in phone
    assert mac.index("Text(label)") < mac.index("content") and phone.index("Text(label)") < phone.index("content")
    # a button: its words never wrap and it takes its own width (R1's fixedSize), unless the caller asks it to fill
    # (.btn.lg.grow, the phone's) - which no Mac piece does; the purple's two halves are test_the_phones_purple's
    button = re.sub(r"\s+", " ", files["Look/DWButtonStyle.swift"])
    assert "var fills = false" in button
    assert ".fixedSize(horizontal: !fills, vertical: false)" in button and ".frame(maxWidth: fills ? .infinity : nil)" in button
    # (R1c) in both bodies, the faced one's and the flat one's
    assert button.count("fixedSize") == 2 and button.count(".fixedSize(horizontal: !fills, vertical: false)") == 2
    # (R1c) a button's body by device and kind: the Mac's every kind and the phone's purple and red faced, as R1b drew
    # them; the phone's others flat - the accent's words, medium (semibold when on or large), faded while held
    dispatch = button[button.index("@ViewBuilder func makeBody("):button.index("struct DWFlatButtonBody")]
    assert ("if Platform.mac || kind == .pri || kind == .danger { DWButtonBody(configuration: configuration, kind: kind, "
            "size: size, fills: fills) } else { DWFlatButtonBody(configuration: configuration, on: kind == .on, "
            "size: size, fills: fills) }") in dispatch
    flat_button = button[button.index("struct DWFlatButtonBody"):button.index("struct DWButtonBody")]
    for part in (".font(Typeface.Look.text(role).weight(on || size == .large ? .semibold : .medium))",
                 ".foregroundStyle(DWPalette.acc)", ".lookHeight(size == .small ? look.smallButtonHeight "
                 ": size == .large ? look.largeButtonHeight : look.buttonHeight)",
                 ".opacity(enabled && !configuration.isPressed ? 1 : DWPalette.off)"):
        assert part in flat_button, part
    # its room either side, a flat button's, DWLook's; the faced two's DWFlat's on the phone, R1's on the Mac
    padding = button[button.index("private var padding: Double {"):button.index("private var weight")]
    assert re.match(r"private var padding: Double \{ if !Platform\.mac \{ switch size \{ case \.standard: return "
                    r"DWFlat\.facedPadding case \.small: return DWFlat\.smallFacedPadding case \.large: return "
                    r"DWFlat\.largeFacedPadding \} \} let look = DWLook\.here", padding), padding
    # a chip: on the Mac R1's face; on the phone its words after a dot, which only a tone that means something draws
    chip = files["Look/DWChip.swift"]
    mac, phone = halves(chip, "if Platform.mac || keepsFace {")
    assert (mac, phone) == (" faced ", " flat "), (mac, phone)
    faced = re.sub(r"\s+", " ", chip[chip.index("private var faced"):chip.index("private var text")])
    assert ".background(fill, in: DWCorners.chipShape) .overlay(DWCorners.chipShape.strokeBorder(edge, lineWidth: 1))" in faced
    # (R1c's review) a chip that keeps its face is the New mark alone, on the phone as R1b drew it: 12.5 semibold, 22
    # tall at least, 7 either side, its tone's fill and edge - the purple's (`.chip.purple`), on the window's ground
    assert ("Text(words) .font(Typeface.Look.text(Platform.mac ? .chip : .facedChip).weight(.semibold)) "
            ".foregroundStyle(text) .lineLimit(1) .fixedSize() .padding(.horizontal, 7) "
            ".lookHeight(Platform.mac ? DWLook.here.chipHeight : DWFlat.facedChipHeight)") in faced, faced
    assert "var keepsFace = false" in chip
    keeping = {path.relative_to(APP).as_posix(): len(re.findall(r"keepsFace: true", bare(path.read_text(encoding="utf-8"))))
               for path in sorted(APP.rglob("*.swift"))}
    assert {name: count for name, count in keeping.items() if count} == {"Library/LibraryTiles.swift": 1}
    tiles = re.sub(r"\s+", " ", bare((APP / "Library" / "LibraryTiles.swift").read_text(encoding="utf-8")))
    assert ("struct LibraryNewMark: View { var body: some View { DWChip(words: LibraryWords.newMark, tone: .marked, "
            "keepsFace: true) .background(DWPalette.bg, in: DWCorners.chipShape)") in tiles
    assert (resolved(".chip", rules=R1B_RULES)["padding-left"], resolved(".chip", rules=R1B_RULES)["font-size"]) == (
        "7px", "12.5px")
    flat_chip = re.sub(r"\s+", " ", chip[chip.index("private var flat"):chip.index("private var faced")])
    assert ("HStack(spacing: CGFloat(DWFlat.dotGap)) { if tone != .plain { Circle() .fill(text) "
            ".frame(width: dot, height: dot) .accessibilityHidden(true) }") in flat_chip, flat_chip
    assert ".background" not in flat_chip and "strokeBorder" not in flat_chip
    assert "@ScaledMetric(relativeTo: .footnote) private var dot = CGFloat(DWFlat.dot)" in chip
    # the segmented control: on the Mac R1's - its own width, the keyboard's focus, ← and →; on the phone its own width
    # (`large` across the page) and no focus
    seg = files["Look/DWSegmented.swift"]
    mac, phone = halves(seg, "if Platform.mac {")
    for part in ("segments .fixedSize() .focusable() .focused($focused) .focusEffectDisabled() .arrowKeys",
                 ".accessibilityElement(children: .contain) .accessibilityLabel(spoken)"):
        assert part in mac, part
    assert phone == (" phoneSegments .fixedSize(horizontal: !large, vertical: true) "
                     ".accessibilityElement(children: .contain) .accessibilityLabel(spoken) "), phone
    # the toggle's dot is the Mac's (.tog.on::after); the phone's .tog.sm draws none
    mac, phone = halves(files["Look/DWToggleStyle.swift"], "if on, Platform.mac {")
    assert "Circle() .fill(DWPalette.acc) .frame(width: 4, height: 4) .offset(y: 7)" in mac and phone == ""
    assert px(css(".tog.on::after", "bottom", MAC_ROOT)) == -7 and px(css(".tog.on::after", "width", MAC_ROOT)) == 4
    # and nothing in App/Phone parts by device at all
    assert not [name for name, code in files.items() if name.startswith("Phone/") and "Platform." in code]


# ----------------------------------------------------------------------------- flat (R1c)

def phone_path(code: str) -> str:
    """The code as the phone runs it: each `if Platform.mac { A } else { B }` (or `if <x>, Platform.mac {`) as B, and
    as nothing where there is no else - and (R1c's review) `if Platform.mac || <x> {` as `if <x> {`, both halves kept."""
    while True:
        either = re.search(r"\bif Platform\.mac \|\| ([^{]+)\{", code)
        if either:
            code = code[:either.start()] + f"if {either.group(1)}{{" + code[either.end():]
            continue
        found = re.search(r"\bif (?:\w+, )?Platform\.mac \{", code)
        if not found:
            return code
        opened = code.index("{", found.start())
        end = reader.closing(code, opened)
        rest = code[end + 1:]
        if re.match(r"\s*else \{", rest):
            start = end + 1 + rest.index("{")
            close = reader.closing(code, start)
            code = code[:found.start()] + code[start + 1:close] + code[close + 1:]
        else:
            code = code[:found.start()] + code[end + 1:]


def cut(code: str, start: str, opener: str = "{") -> str:
    """The code without the declaration (or the call) that starts at the pattern `start`: up to its brace's (or its
    parenthesis') close."""
    found = re.search(start, code)
    assert found, start
    opened = code.index(opener, found.start())
    return code[:found.start()] + code[reader.closing(code, opened) + 1:]


#? what the phone never runs of App/Look's shared pieces, though it is not inside an `if Platform.mac`: the Mac's
#? segments (named from their Mac half alone - held below), and the faced button body's .normal and .on faces (the
#? phone sends only the purple and the red to that body - DWButtonStyle's dispatch, held by
#? test_each_device_half_of_the_shared_pieces_draws_its_own). (R1c's review) The chip's face is no longer here: the
#? phone draws it for the New mark (`keepsFace`)
MAC_ONLY = {
    "Look/DWSegmented.swift": [(r"private var segments: some View \{", "{"),
                               (r"private func segment\(_ option: Value\) -> some View \{", "{")],
    "Look/DWButtonStyle.swift": [(r"case \.normal:\s*DWRaised\(", "("), (r"case \.on:\s*DWRaised\(", "(")],
}

#? a fill, a face or an edge, or a hairline - each drawing call, with the colours it names
DRAWS = re.compile(r"(\.fill|\.background|\.strokeBorder|\.stroke|\bDWRaised|\bDWWell|\bDWRule)\(")


def drawn(code: str) -> list[str]:
    """Each fill, face, edge and rule the code draws: the call, then the colours it is given."""
    found = []
    for match in DRAWS.finditer(code):
        opened = match.end() - 1
        arguments = re.sub(r"\s+", " ", code[opened + 1:reader.closing(code, opened)]).strip()
        colours = re.findall(r"\bDWPalette\.\w+", arguments)
        call = match.group(1).lstrip(".")
        if call == "background" and not colours and not re.match(r"\w+(,|$)", arguments):
            continue  # a background's alignment, its content drawn by the calls inside it
        found.append(f"{call}: {', '.join(colours) or arguments}")
    return found


#? everything App/Look's and App/Phone's pieces draw on the phone that has a fill or an edge, in each file's order.
#? James, 25 Nov: "get rid of all the grey boxes" - so only these, each for the reason beside it:
#?   the primary and the destructive button (the purple, the red); a sunken track (the meter's, the seek line's); a
#?   text input's well (DWField's, DWWell, DWWellField's); what the slice leaves as it was (the toggle, the switch, the
#?   count badge and the New mark's face - the brief's "unchanged"); the marks (a hairline, the chosen line in the
#?   accent, a chip's dot, the lit line, the pop-up's caret); and DWRaised itself, which draws only what a caller gives it
FLAT_DRAWS = {
    "Look/DWButtonStyle.swift": [
        # the purple, PrimaryButton's own, and the red
        "DWRaised: DWPalette.phonePrimaryPressedFace, DWPalette.phonePrimaryFace, DWPalette.phonePrimarySheen, "
        "DWPalette.phonePrimaryPressedEdge, DWPalette.phonePrimaryEdge, DWPalette.phonePrimaryDrop",
        "DWRaised: DWPalette.redFace, DWPalette.buttonSheen, DWPalette.redEdge, DWPalette.buttonDrop"],
    # the dot (in its words' colour); (R1c's review) a chip that keeps its face, the New mark's on a cover, as R1b's -
    # the only caller is LibraryNewMark (held by test_each_device_half_of_the_shared_pieces_draws_its_own); the count
    # badge, unchanged
    "Look/DWChip.swift": ["fill: text", "background: fill, in: DWCorners.chipShape", "strokeBorder: edge, lineWidth: 1",
                          "background: DWPalette.countFill", "strokeBorder: DWPalette.countEdge"],
    # a text input's well - and a field's row's hairline
    "Look/DWField.swift": ["fill: DWPalette.well, DWPalette.wellShade", "strokeBorder: DWPalette.acc, DWPalette.line",
                           "DWWell: focused: focused", "DWRule: DWPalette.groupRule"],
    # the meter: a sunken track and its fill, unchanged
    "Look/DWMeter.swift": ["fill: DWPalette.well, DWPalette.meterShade", "strokeBorder: DWPalette.line", "fill: fill"],
    "Look/DWPopUp.swift": ["fill: colour"],
    "Look/DWRaised.swift": ["fill: face", "fill: face", "fill: face.shadow(.inner(color: sheen, radius: 0, x: 0, y: 1))",
                            "strokeBorder: edge, lineWidth: 1"],
    # the hairline under the switch, the chosen one's line in the accent
    "Look/DWSegmented.swift": ["DWRule: DWPalette.segRule", "fill: DWPalette.acc"],
    # the toggle, unchanged (drawn on no phone screen since R2b)
    "Look/DWToggleStyle.swift": ["fill: DWPalette.selbg", "strokeBorder: DWPalette.selbd"],
    # (R1c's review) a page's own field on the look's well: a text input's box
    "Look/DWWellField.swift": ["DWWell: focused: focus.wrappedValue == field"],
    # a card's hairline under it, a group's rows' under each
    "Phone/PhoneCard.swift": ["DWRule: DWPalette.cardRule", "DWRule: DWPalette.groupRule", "DWRule: DWPalette.groupRule"],
    "Phone/PhoneFoot.swift": ["DWRule: DWPalette.footEdge"],
    # the hairline over the mini player, and its seek line's played part (the scrubber, unchanged)
    "Phone/PhoneMini.swift": ["DWRule: DWPalette.miniEdge", "fill: DWPalette.seekFill"],
    "Phone/PhoneStrip.swift": ["DWRule: DWPalette.stripRule", "fill: DWPalette.acc"],
    # the switch, unchanged: on in the app's purple, off sunken, its knob
    "Phone/PhoneSwitch.swift": ["fill: DWPalette.switchFace, DWPalette.switchShade", "strokeBorder: DWPalette.switchEdge",
                                "fill: DWPalette.switchOffFace, DWPalette.switchShade",
                                "strokeBorder: DWPalette.switchOffEdge", "fill: DWPalette.switchKnob, DWPalette.switchOffKnob"],
    # the lit line over the tab shown
    "Phone/PhoneTabItem.swift": ["fill: DWPalette.acc"],
}


def test_the_phone_is_flat():
    found = {}
    for name, text in look_and_phone().items():
        code = phone_path(bare(text))
        for start, opener in MAC_ONLY.get(name, []):
            code = cut(code, start, opener)
        draws = drawn(code)
        if draws:
            found[name] = draws
    assert found == FLAT_DRAWS, {name: draws for name, draws in found.items() if draws != FLAT_DRAWS.get(name)}
    # what MAC_ONLY takes out is the Mac's alone: the Mac's segments named from their Mac half - and (R1c's review) the
    # faced chip reached on the phone only by a chip that keeps its face
    files = {name: bare(text) for name, text in look_and_phone().items()}
    chip, seg = files["Look/DWChip.swift"], files["Look/DWSegmented.swift"]
    assert len(re.findall(r"\bfaced\b", chip)) == 2 and halves(chip, "if Platform.mac || keepsFace {")[0] == " faced "
    assert len(re.findall(r"\bsegments\b", seg)) == 2 and halves(seg, "if Platform.mac {")[0].startswith(" segments ")
    assert len(re.findall(r"\bsegment\(", seg)) == 2 and "segment(option)" in seg[seg.index("private var segments"):
                                                                                     seg.index("private func segment(")]
    # and the matcher finds a face planted on the phone's path, and none on the Mac's
    planted = bare("if Platform.mac { x.background(DWPalette.buttonFace) } else { x.background(DWPalette.cardRule) }")
    assert drawn(phone_path(planted)) == ["background: DWPalette.cardRule"]
    # and both halves of an `if Platform.mac || <x>`, which the phone runs either way <x> says
    planted = bare("if Platform.mac || keep { x.background(DWPalette.buttonFace) } else { x.background(DWPalette.line) }")
    assert drawn(phone_path(planted)) == ["background: DWPalette.buttonFace", "background: DWPalette.line"]
    # the grounds the phone's bars stand on are the page's own black (`.dw.ph .mini`, `.tabbar`), never a grey bar's
    lines = palette_lines()
    black = mac_look.colours(css(".mini", "background"))
    assert black == [(0, 0, 0, 1.0)] == mac_look.colours(css(".tabbar", "background"))
    for ground in ("page", "miniFace", "tabBarFace", "footFace"):
        assert made_colours(lines[ground][0]) == black, ground
    assert re.search(r"var body: some View \{\s*DWPalette\.miniFace", files["Phone/PhoneMini.swift"])
    # (R1c's review) and the very colour of every page they sit on: `.dw.ph`'s own ground, which the album's and the
    # playlist's pages draw on the phone too now (R5 drew them on --bg, #0b0a10 - a seam against the bars); every other
    # phone page is iOS's own black under the app's dark scheme
    assert lines["page"][1] == "dw.ph: .dw background" and css(".dw", "background") == "#000"
    for page in ("Album/AlbumView.swift", "Playlists/PlaylistView.swift"):
        code = bare((APP / page).read_text(encoding="utf-8"))
        assert code.count(".background(Platform.mac ? DWPalette.bg : DWPalette.page)") == 1, page
        assert ".background(DWPalette.bg)" not in code, page
    # the two colours read from the rules as R1b drew the phone, each where the flat phone no longer draws it: the Mac's
    # own card face (RefreshProblemNote's Mac half) and the scrub's time tag over the mini player
    r1b = {name: source for name, (_, source) in lines.items() if source.endswith(" (R1b)")}
    assert r1b == {"macCardFace": "dw.ph: .card background (R1b)",
                   "scrubTagFace": "dw.ph: .mini background (R1b)"}, r1b
    assert css(".card", "background", rules=R1B_RULES) == css(".mini", "background", rules=R1B_RULES) == "#1c1b22"
    assert css(".card", "background") == "none" and css(".mini", "background") == "#000"
    uses = {name: [path.relative_to(APP).as_posix() for path in sorted(APP.rglob("*.swift"))
                   if re.search(rf"\bDWPalette\.{name}\b", bare(path.read_text(encoding="utf-8")))]
            for name in r1b}
    assert uses == {"macCardFace": ["Library/AlbumsScreen.swift"], "scrubTagFace": ["Player/MiniPlayerView.swift"]}, uses
    albums = re.sub(r"\s+", " ", bare((APP / "Library" / "AlbumsScreen.swift").read_text(encoding="utf-8")))
    note = albums[albums.index("struct RefreshProblemNote"):]
    assert halves(note, "if Platform.mac {")[0].strip().endswith(".background(DWPalette.macCardFace, in: DWCorners.boxShape)")
    # (R1c's review) the two other Library one-offs, flat on the phone: Downloaded's first ask a PhoneCard with Not Now a
    # flat button (its toggled fill and SecondaryPill the Mac's halves alone), and an empty library's See All music a
    # flat button (`.bordered`, the system's grey, the Mac's alone) - each Mac half pinned in test_ios_mac_halves.py
    first = albums[albums.index("struct FirstAskCard"):albums.index("private var ask: some View")]
    mac, phone = halves(first, "if Platform.mac {")
    assert phone == " PhoneCard { ask } .accessibilityElement(children: .contain) .padding(.bottom, 12) ", phone
    assert "Palette.toggledFill" in mac and "toggledFill" not in phone
    buttons = albums[albums.index("private var buttons: some View"):]
    mac, phone = halves(buttons, "if Platform.mac {")
    assert phone == " Button(AutoDownloadWords.notNow) { asked = true } .buttonStyle(DWButtonStyle()) ", phone
    assert ".buttonStyle(SecondaryPill())" in mac
    empty = albums[albums.index("struct EmptyLibraryNote"):]
    mac, phone = halves(empty, "if Platform.mac {")
    assert phone == " StoreAlbumsLink { Text(LibraryWords.seeAllMusic) } .buttonStyle(DWButtonStyle()) ", phone
    assert ".buttonStyle(.bordered)" in mac
    mini = re.sub(r"\s+", " ", bare((APP / "Player" / "MiniPlayerView.swift").read_text(encoding="utf-8")))
    assert (".padding(.vertical, 3) .background(DWPalette.scrubTagFace, in: DWCorners.chipShape) "
            ".overlay(DWCorners.chipShape.strokeBorder(DWPalette.line,") in mini


#? (R1c; James, 25 Nov: "actually any place you can input text should be a box") every place you type on the phone, by
#? file in the order it draws them, and the box each is in - read from the field itself (R1c's review: a file-wide
#? look passed a field with its box taken away, another box in the file answering for it):
#?   the look's sunken well - DWWell drawn under the field by its own chain (DWField's), by a modifier it names
#?   (DWWellField's: a playlist's Edit, the manual search) or by the stack it shares with its glyph (the Library's Find);
#?   the app's own box - a fill and an edge in the field's own chain or a modifier it names (sign-in's FieldLook, Sources'
#?   query);
#?   iOS's own box - no plain style taking it away, and every way the field is reached held in a Form, a List that
#?   isn't plain, an alert or a .searchable (Platform's searchField on the phone): walked out from the field through its
#?   blocks, and on through each use of the view or the helper it is declared in (TYPING_HOPS at most).
#? R1c left iOS's own as they were: Settings', People's, the editors' and the EQ's are wave D's slices.
WELL, OWN, SYSTEM = "the look's well", "the app's own box", "iOS's own box"
TEXT_INPUTS = {
    "Artist/ArtistImagesSheet.swift": [SYSTEM], "Artist/ArtistMoveSheet.swift": [SYSTEM],
    "EQ/EQCorrectionScreen.swift": [SYSTEM], "EQ/EQFilterEditor.swift": [SYSTEM], "EQ/EQNameAlert.swift": [SYSTEM],
    "Edit/ChooseFolderView.swift": [SYSTEM], "Edit/ReleasePage.swift": [SYSTEM, SYSTEM], "Edit/TagsPages.swift": [SYSTEM],
    # (R1c's review) Artist and Album on the look's wells, in a flat sheet
    "Get/ManualSearchSheet.swift": [WELL, WELL], "Get/SourcesSheet.swift": [OWN],
    "Library/AlbumsScreen.swift": [SYSTEM], "Library/ArtistsScreen.swift": [SYSTEM], "Library/LibraryView.swift": [WELL],
    "Library/SongsScreen.swift": [SYSTEM], "Look/DWField.swift": [WELL],
    "Manage/LibraryCareScreen.swift": [SYSTEM], "Manage/PeopleScreen.swift": [SYSTEM],
    "Manage/PeopleSheets.swift": [SYSTEM] * 7, "Manage/ServerSettingsGroupScreen.swift": [SYSTEM, SYSTEM],
    "Playlists/PlaylistPicker.swift": [SYSTEM],
    # (R1c's review) Edit's name and description: a plain List's rows draw no box, so the look's wells
    "Playlists/PlaylistView.swift": [WELL, WELL],
    "Root/ServerAddressView.swift": [SYSTEM], "Root/SignInView.swift": [OWN, OWN],
    "Search/PressingPickerSheet.swift": [SYSTEM],
    # Search's field: Platform's searchField - on the phone .searchable's, held below
    "Search/SearchScreen.swift": [SYSTEM],
    "You/ChangePasswordScreen.swift": [SYSTEM] * 3,
}
TYPING = re.compile(r"\b(?:TextField|SecureField|TextEditor)\(|\.searchable\(|\.searchField\(")
TYPING_HOPS = 3
#? a block whose head is a presentation's root: what is in it is held by nothing further out
PRESENTED = re.compile(r"(\.sheet\(|\.fullScreenCover\(|\.popover\(|\bNavigationStack\s*)[^{}]*$")
#? iOS's own boxes, as the walk names them
SYSTEM_HOLDERS = {"Form", "List", "alert", "searchable"}


def typing_files() -> dict[str, str]:
    """Every phone file's code alone (the Mac's own pages aside: R1's fields, held by test_ios_mac_look.py)."""
    files = {}
    for path in sorted(APP.rglob("*.swift")):
        name = path.relative_to(APP).as_posix()
        if not (name.startswith("Mac/") or name == "Root/MacSidebarView.swift"):
            files[name] = bare(path.read_text(encoding="utf-8"))
    return files


def chain(code: str, at: int) -> str:
    """The modifiers chained on from `at` (just past a call or a block): each `.name`, its arguments and a closure on its
    own line."""
    start = at
    while True:
        found = re.match(r"\s*\.(\w+)", code[at:])
        if not found:
            return code[start:at]
        at += found.end()
        while True:
            follow = re.match(r"\s*(<[^<>]*>)?\s*([({])", code[at:])
            if not follow or (follow.group(2) == "{" and code[at:at + follow.end()].count("\n") > 1):
                break
            at = reader.closing(code, at + follow.end() - 1) + 1


def past_call(code: str, at: int) -> int:
    """Past the call that starts at `at` (`TextField(`...`)`), and a closure trailing it."""
    end = reader.closing(code, code.index("(", at)) + 1
    follow = re.match(r"\s*\{", code[end:])
    return reader.closing(code, end + follow.end() - 1) + 1 if follow else end


def blocks_around(code: str, at: int) -> list[tuple[int, str]]:
    """Each `{` holding `at`, innermost first: where it is, and its head (back to the brace before it)."""
    found, depth = [], 0
    for i in range(at - 1, -1, -1):
        if code[i] == "}":
            depth += 1
        elif code[i] == "{":
            if depth:
                depth -= 1
            else:
                found.append((i, code[max(code.rfind("{", 0, i), code.rfind("}", 0, i)) + 1:i]))
    return found


def modifiers_named(files: dict[str, str], text: str) -> str:
    """The bodies of the ViewModifiers `text` names (`.modifier(FieldLook())`, `.modifier(DWWellField(`...)."""
    bodies = []
    for modifier in re.findall(r"\.modifier\((\w+)\(", text):
        found = [re.search(rf"\bstruct {modifier}\b[^{{]*: ViewModifier \{{", other) for other in files.values()]
        found = [(other, match) for other, match in zip(files.values(), found) if match]
        assert len(found) == 1, f"the modifier {modifier}"
        other, match = found[0]
        bodies.append(other[match.start():reader.closing(other, match.end() - 1) + 1])
    return " ".join(bodies)


def dressed(files: dict[str, str], name: str, at: int) -> str:
    """What the field at `at` is drawn in: its own chain and the bodies of the modifiers that chain names."""
    own = chain(files[name], past_call(files[name], at))
    return own + " " + modifiers_named(files, own)


def held_by(files: dict[str, str], name: str, at: int, hops: int = 0) -> list[str]:
    """What holds the place you type at `at`: one word for each way it is reached - "Form", "List", "List .plain",
    "alert", "searchable", or "nothing (why)" - walking out through its blocks, then to each use of the view or helper
    it is declared in."""
    code = files[name]
    if re.match(r"\.(searchable|searchField)\(", code[at:]):
        return ["searchable"]
    for brace, head in blocks_around(code, at):
        if re.search(r"\bForm\s*(\([^()]*\))?\s*$", head):
            return ["Form"]
        if re.search(r"\bList\s*(\([^()]*\))?\s*$", head):
            return ["List .plain" if ".listStyle(.plain)" in chain(code, reader.closing(code, brace) + 1) else "List"]
        if re.search(r"\.alert\([^{}]*\)\s*$", head):
            return ["alert"]
        if PRESENTED.search(head):
            return [f"nothing ({name}: a presentation's root)"]
        # what the block declares: the last func, struct or computed var in its head (a `var x = ...` before it, as
        # `@Bindable var model = model` in a helper's body, is a value, not the block's)
        declarations = [found for found in re.finditer(r"\b(func|var|struct)\s+(\w+)", head)
                        if not (found.group(1) == "var" and re.match(r"\s*(?::[^=\n]*)?=", head[found.end():]))]
        if not declarations:
            continue
        kind, what = declarations[-1].groups()
        if kind == "var" and what == "body":
            continue
        if hops >= TYPING_HOPS:
            return [f"nothing ({name}: {what}, too far)"]
        if kind == "struct":
            uses = [(other, use.start()) for other, text in files.items() for use in re.finditer(rf"\b{what}\(", text)]
        else:
            pattern = rf"\b{what}\(" if kind == "func" else rf"\b{what}\b(?!\s*:)"
            uses = [(name, use.start()) for use in re.finditer(pattern, code)
                    if not brace - len(head) <= use.start() < brace]
        return [way for other, use in uses for way in held_by(files, other, use, hops + 1)] or [
            f"nothing ({name}: {what} unused on the phone)"]
    return [f"nothing ({name})"]


def boxes(files: dict[str, str], name: str) -> list[tuple[int, str, list[str]]]:
    """Each place you type in `name`: its line, what it is drawn in, and what holds it."""
    code = files[name]
    found = []
    for match in TYPING.finditer(code):
        dress = "" if match.group(0).startswith(".") else dressed(files, name, match.start())
        around = blocks_around(code, match.start())
        if around and re.search(r"\bHStack\s*(\([^()]*\))?\s*$", around[0][1]):
            # the stack it shares with a glyph (the Library's Find: the magnifying glass and the field on one well)
            dress += " " + chain(code, reader.closing(code, around[0][0]) + 1)
        found.append((code.count("\n", 0, match.start()) + 1, dress, held_by(files, name, match.start())))
    return found


def box_of(dress: str, holders: list[str]) -> str | None:
    """Which box a place you type is in, from what it is drawn in and what holds it - None for none."""
    flat = re.sub(r"\s+", " ", dress)
    if "DWWell(" in flat and ".textFieldStyle(.plain)" in flat:
        return WELL
    if re.search(r"\.background\((?!alignment)[^)]", flat) and ".strokeBorder(" in flat:
        return OWN
    if ".textFieldStyle(" not in flat and holders and set(holders) <= SYSTEM_HOLDERS:
        return SYSTEM
    return None


def test_every_place_you_type_on_the_phone_is_still_a_box():
    files = typing_files()
    found = {}
    for name in files:
        for line, dress, holders in boxes(files, name):
            found.setdefault(name, []).append((line, box_of(dress, holders), holders))
    assert {name: [box for _, box, _ in places] for name, places in found.items()} == TEXT_INPUTS, {
        name: places for name, places in found.items()
        if [box for _, box, _ in places] != TEXT_INPUTS.get(name)}
    # the look's well, under the field: DWField's and the Library's Find - a plain field on DWWell's sunken box - and
    # (R1c's review) DWWellField's, on the phone alone: the Mac draws the field as its page did
    field = re.sub(r"\s+", " ", files["Look/DWField.swift"])
    assert ".textFieldStyle(.plain)" in field and "DWWell(focused: focused)" in field
    library = re.sub(r"\s+", " ", files["Library/LibraryView.swift"])
    assert ".textFieldStyle(.plain)" in library and "DWWell(focused: findFocused)" in library
    well_field = re.sub(r"\s+", " ", files["Look/DWWellField.swift"])
    mac, phone = halves(well_field, "if Platform.mac {")
    assert mac == " content ", mac
    # its focus is the page's - the field's own `.focused`, both devices' (the Mac's Tab and a sheet's first cursor need
    # it there): DWWellField reads it for the edge and sets it from a tap, and never binds it again
    assert ".focused(" not in well_field
    assert re.match(r" content \.textFieldStyle\(\.plain\) \.font\(Typeface\.Look\.text\(\.field\)\) "
                    r"\.foregroundStyle\(DWPalette\.fieldText\) \.focusEffectDisabled\(\) "
                    r"\.padding\(\.horizontal, 8\) \.padding\(\.vertical, lines \? 8 : 0\) "
                    r"\.lookHeight\(DWLook\.here\.fieldHeight\) \.background \{ DWWell\(focused: focus\.wrappedValue == field\) "
                    r"\.contentShape\(DWTarget\(face: DWCorners\.buttonShape\)\) \.onTapGesture \{ focus\.wrappedValue = field \} \} $",
                    phone), phone
    # a playlist's Edit: its two fields each on a well of its own, the description's growing a line at a time
    playlist = re.sub(r"\s+", " ", files["Playlists/PlaylistView.swift"])
    assert ".modifier(DWWellField(focus: $typing, field: .name))" in playlist
    assert ".modifier(DWWellField(focus: $typing, field: .description, lines: true))" in playlist
    # each its own focus, which the well reads: the name's, then the description's, once each
    assert re.findall(r"\.focused\(\$typing, equals: \.(\w+)\)", playlist) == ["name", "description"]
    for kind, call in (("name", "TextField(PlaylistWords.nameField"),
                       ("description", "TextField(PlaylistWords.descriptionField")):
        own = playlist[playlist.index(call):playlist.index(f"field: .{kind}")]
        assert f".focused($typing, equals: .{kind})" in own, kind
    # the manual search: flat - no Form (so no grey cells), on the page's black under its bar and as the sheet's ground
    # - its two fields the look's wells, each prompt in the third colour, the footer in the second, the purple Search
    manual = re.sub(r"\s+", " ", files["Get/ManualSearchSheet.swift"])
    assert not re.search(r"\b(Form|Section|List)\b|listRowBackground", manual)
    assert "NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 0) {" in manual
    assert ".background(DWPalette.page.ignoresSafeArea())" in manual and ".presentationBackground(DWPalette.page)" in manual
    for kind in ("artist", "album"):
        assert f".modifier(DWWellField(focus: $focused, field: .{kind}))" in manual, kind
        # its focus the sheet's own, as A1 made it, right before its Tab (test_ios_mac's): the well reads it
        assert manual.count(f".focused($focused, equals: .{kind})") == 1, kind
        assert f".focused($focused, equals: .{kind}) .tabs($focused, in: Self.order)" in manual, kind
    assert manual.count("prompt: Text(ManualSearch.") == 2 and manual.count(".foregroundStyle(DWPalette.t3)") == 2
    assert "Text(ManualSearch.footer) .font(Typeface.footnote) .foregroundStyle(DWPalette.t2)" in manual
    assert "Button(ManualSearch.search, action: search) .buttonStyle(PrimaryFace())" in manual
    # Search's field on the phone is iOS's own search field in the navigation bar (Platform's phone half), as before
    platform = re.sub(r"\s+", " ", bare((APP / "Shared" / "Platform.swift").read_text(encoding="utf-8")))
    assert ("func searchField(text: Binding<String>, prompt: String) -> some View { searchable(text: text, "
            "placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt)) }") in platform
    # the well itself is a box: the well's fill, its inner shadow and an edge (the accent's while focused) - dw.css's
    # .in on the phone, unchanged by the flat block
    well = re.sub(r"\s+", " ", files_well())
    assert ".fill(DWPalette.well.shadow(.inner(color: DWPalette.wellShade" in well, well
    assert ".strokeBorder(focused ? DWPalette.acc : DWPalette.line, lineWidth: 1)" in well, well
    entry = resolved(".in")
    assert (entry["background"], entry["border-top-width"], entry["border-top-color"]) == ("#09080d", "1px", "#2c2a36")
    assert entry["box-shadow"] == "inset 0 1px 2px rgba(0, 0, 0, 0.7)"
    assert resolved("div.well.sfield")["background"] == "#09080d" and px(css("div.well.sfield", "height")) == 40
    # and Requests' Search Soulseek… is flat: a row in the accent on its hairline, no face
    requests = re.sub(r"\s+", " ", bare((APP / "Requests" / "RequestsScreen.swift").read_text(encoding="utf-8")))
    row = requests[requests.index("private var manualSearch: some View {"):requests.index("private func notice(")]
    assert ".foregroundStyle(DWPalette.acc)" in row and ".buttonStyle(.plain)" in row
    assert "DWRule(colour: DWPalette.rowRule)" in row and not re.search(r"DWRaised|\.background\(|\.fill\(", row)


def test_the_walk_finds_each_box_from_the_field_itself():
    # the walk reads each field's own box, not its file's: another box in the file never answers for it
    files = {
        "A.swift": bare("struct A: View {\n var body: some View {\n VStack {\n Text(x)\n .background(Color.red)\n"
                        " .overlay(Rectangle().strokeBorder(Color.blue))\n TextField(a, text: $a)\n } } }\n"),
        "B.swift": bare("struct B: View {\n var body: some View {\n NavigationStack {\n Form {\n Section {\n"
                        " field\n } } } }\n private var field: some View {\n TextField(b, text: $b)\n } }\n"),
        "C.swift": bare("struct C: View {\n var body: some View {\n List {\n TextField(c, text: $c)\n"
                        " .modifier(Boxed())\n }\n .listStyle(.plain)\n } }\n"
                        "private struct Boxed: ViewModifier {\n func body(content: Content) -> some View {\n content\n"
                        " .background(Color.gray, in: Rectangle())\n .overlay(Rectangle().strokeBorder(Color.white))\n"
                        " } }\n"),
        "D.swift": bare("struct D: View {\n var body: some View {\n List {\n TextField(d, text: $d)\n }\n"
                        " .listStyle(.plain)\n .sheet(isPresented: $e) {\n TextField(e, text: $e)\n } } }\n"),
    }
    found = {name: [box_of(dress, holders) for _, dress, holders in boxes(files, name)] for name in files}
    assert found == {"A.swift": [None], "B.swift": [SYSTEM], "C.swift": [OWN], "D.swift": [None, None]}, found
    assert boxes(files, "B.swift")[0][2] == ["Form"] and boxes(files, "D.swift")[0][2] == ["List .plain"]


def files_well() -> str:
    """DWWell's body: the look's sunken box."""
    code = bare((LOOK_DIR / "DWField.swift").read_text(encoding="utf-8"))
    at = code.index("struct DWWell")
    return code[at:reader.closing(code, code.index("{", at)) + 1]


# ----------------------------------------------------------------------------- drawn nowhere yet

def declared(folder: Path) -> set[str]:
    names = set()
    for path in sorted(folder.rglob("*.swift")):
        code = bare(path.read_text(encoding="utf-8"))
        names |= set(re.findall(r"^(?:@MainActor\s+)?(?:final\s+)?(?:struct|enum|class|protocol|typealias)\s+(\w+)",
                                code, re.M))
        for extension in re.finditer(r"^extension \w+\b[^{]*\{", code, re.M):
            opened = code.index("{", extension.start())
            inside = code[opened:reader.closing(code, opened) + 1]
            names |= set(re.findall(r"\b(?:func|var) (\w+)\b", inside))
    return names


#? R1b draws none of App/Phone's pieces and puts App/Look's only where the Mac's look already was: each slice that draws
#? one on a phone screen adds that file here - R2 the Library's top, its pages and their rows; R3: Now Playing's sheet
#? (PhoneTop, PhoneBack, PhoneStrip) and its bottom row (PhoneTabItem, PhoneLook's sizes, DWPalette's accent for the
#? output's name); R8: Requests on the phone, its cards (PhoneCard, DWMeter, DWRaised, DWButtonStyle) and its screen;
#? R3b: the sheet's three pages - the Queue (its rows, top and foot), Info (PhoneGroup, its kv rows, PhoneGo) and the EQ
#? (its groups, the switch, the output's button, the curve's well, the sliders' faces), and the sheet's ground (DWPalette)
#? R4: the mini player (PhoneMiniGround, PhoneLook's sizes, DWPalette's seek line) and the tab bar (PhoneLitLine, DWCount)
#? R5: an album's page and a playlist's on the phone (iAlbum, iPlaylist - their heroes, rows and ground), and the Add to
#? a playlist sheet's shared buttons (PlaylistPicker's NewPlaylistFields, the Look's alone); (R1c's review) Requests'
#? manual search sheet (its two wells, DWWellField, and the page's black)
R2_LIBRARY = {"Library/LibraryTop.swift", "Library/LibraryView.swift", "Library/LibraryTiles.swift",
              "Library/AlbumsScreen.swift", "Library/ArtistsScreen.swift", "Library/SongsScreen.swift",
              "Playlists/PlaylistsScreen.swift", "Library/LibraryLine.swift"}
R3B_PAGES = {"UpNext/UpNextScreen.swift", "Info/InfoView.swift", "EQ/EQScreen.swift", "EQ/EQSliders.swift",
             "EQ/EQCurveView.swift", "EQ/EQOutputViews.swift", "Player/NowPlayingSheet.swift"}
R4_BARS = {"Player/MiniPlayerView.swift", "Root/MainTabs.swift"}
R5_PAGES = {"Album/AlbumHero.swift", "Album/TrackRow.swift", "Album/AlbumView.swift", "Playlists/PlaylistView.swift"}
#? R4b: Now Playing's scrubber, sunken as the meter is (DWCorners' meter shapes, DWPalette's well and fill)
R4B_FACE = {"Player/ScrubberView.swift"}
SLICES = R2_LIBRARY | R3B_PAGES | R4_BARS | R5_PAGES | R4B_FACE
PHONE_PIECES_DRAWN_IN: set[str] = {"Player/NowPlayingSheet.swift", "Player/NowPlayingView.swift",
                                   "Requests/RequestCards.swift", "Requests/RequestsScreen.swift"} | SLICES
LOOK_PIECES_DRAWN_IN = {"Root/MacSidebarView.swift", "Root/DesktopFrame.swift", "Player/PlayerBar.swift",
                        "Player/MacPanels.swift", "Player/NowPlayingView.swift", "Requests/RequestCards.swift",
                        "Requests/RequestsScreen.swift"} | SLICES | {"Playlists/PlaylistPicker.swift",
                                                                     "Get/ManualSearchSheet.swift"}


def test_the_phones_pieces_are_drawn_nowhere_yet():
    phone = declared(PHONE_DIR)
    assert {"PhoneStrip", "PhoneTop", "PhoneBack", "PhoneBigTitle", "PhoneTabItem", "PhoneLitLine", "PhoneMiniGround",
            "PhoneSeekLine", "PhoneCard", "PhoneGroup", "PhoneKV", "PhoneGo", "PhoneChevron", "PhoneSwitchStyle",
            "phoneSwitch", "PhoneFoot", "phoneFoot", "PhoneMeta", "PhoneMetaLink", "PhoneCircleStyle"} <= phone, phone
    look = declared(LOOK_DIR) - {"here"}
    assert {"DWPalette", "DWCorners", "DWRaised", "DWRule", "DWButtonStyle", "DWWell", "DWField", "DWFieldRow", "DWChip",
            "DWCount", "DWSegmented", "DWPopUp", "DWCaret", "DWToggleStyle", "DWTarget", "lookHeight",
            "lookSquare", "DWMeter", "DWWellField"} <= look, look
    phone_use = re.compile(r"\bTypeface\.Phone\b|\bPhoneLook\b|\bPhonePieceWords\b|\b(" + "|".join(sorted(phone, key=len, reverse=True)) + r")\b")
    look_use = re.compile(r"\bTypeface\.Look\b|\bDWLook\b|\bDWLook\.here\b|\b(" + "|".join(sorted(look, key=len, reverse=True))
                          + r")\b")
    phone_left, look_left = [], []
    for path in sorted(APP.rglob("*.swift")):
        name = path.relative_to(APP).as_posix()
        code = bare(path.read_text(encoding="utf-8"))
        if not name.startswith("Phone/") and name not in PHONE_PIECES_DRAWN_IN and phone_use.search(code):
            if name != "Shared/Typeface.swift":
                phone_left.append(f"{name}: {phone_use.search(code).group(0)}")
        if not name.startswith(("Look/", "Phone/", "Mac/")) and name not in LOOK_PIECES_DRAWN_IN and look_use.search(code):
            if name != "Shared/Typeface.swift":
                look_left.append(f"{name}: {look_use.search(code).group(0)}")
    assert not phone_left, phone_left
    assert not look_left, look_left
