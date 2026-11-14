"""The iPhone app's primary button is the web's (notes/ios-specs/phase4-library.md 2.8, slice 3b).

James: "the color of the play button on the album page doesn't show the play icon". The phone drew its Play with
SwiftUI's `.borderedProminent` under the app's tint (#C084FC, the web's accent for text on black) and a white glyph -
2.64:1. It now draws the web's primary button, as player.css's `.pl-pill.is-primary` and app.css's primary buttons do:
theme.css's --dw-primary-bg gradient, --dw-primary-border edge, --dw-primary-highlight line, a --dw-text label, 4 pt
corners (--dw-radius-control), brightness(0.92) while pressed (--dw-primary-pressed), and the album's and playlist's
pills 48 pt tall (--pl-pill-height). PrimaryButton (ios/DeadwaxKit/Sources/DeadwaxCore/PrimaryButton.swift) holds those
numbers for the app's PrimaryFace; this reads both sides, so a change on either fails here. (The deck's tokens.json
holds the turntable's colours; the primary's are held here instead, so the deck's fixtures need no regenerating.)
The contrast its label was measured with is PrimaryButtonTests' (Swift), from these same numbers.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SWIFT = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "PrimaryButton.swift"
THEME_CSS = REPO / "interface" / "styles" / "theme.css"
PLAYER_CSS = REPO / "interface" / "player" / "player.css"


def token(css: Path, name: str) -> str:
    found = re.search(rf"--{name}:\s*([^;]+);", css.read_text(encoding="utf-8"))
    assert found, f"{css.name} has no --{name}"
    return found.group(1).strip()


def primary() -> str:
    text = SWIFT.read_text(encoding="utf-8")
    start = text.index("public enum PrimaryButton")
    return text[start:text.index("\n}\n", start) + 1]


def swift_colour(name: str) -> tuple[int, int, int, float]:
    found = re.search(rf"public static let {name} = DeckRGBA\(([^)]*)\)\n", primary())
    assert found, f"PrimaryButton has no {name}"
    parts = [part.strip() for part in found.group(1).split(",")]
    channels = [int(part, 16) if part.startswith("0x") else int(part) for part in parts[:3]]
    alpha = float(parts[3]) if len(parts) > 3 else 1.0
    return channels[0], channels[1], channels[2], alpha


def swift_number(name: str) -> float:
    found = re.search(rf"public static let {name} = ([0-9.]+)\n", primary())
    assert found, f"PrimaryButton has no {name}"
    return float(found.group(1))


def hex_colour(value: str) -> tuple[int, int, int, float]:
    digits = value.strip().lstrip("#")
    if len(digits) == 3:
        digits = "".join(c * 2 for c in digits)
    assert len(digits) == 6, value
    return int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), 1.0


def px(value: str) -> float:
    assert value.endswith("px"), value
    return float(value[:-2])


def test_the_gradient_is_the_webs():
    gradient = token(THEME_CSS, "dw-primary-bg")
    found = re.fullmatch(r"linear-gradient\(to bottom, (#[0-9a-fA-F]{6}) 0%, (#[0-9a-fA-F]{6}) 100%\)", gradient)
    assert found, gradient
    assert swift_colour("top") == hex_colour(found.group(1))
    assert swift_colour("bottom") == hex_colour(found.group(2))


def test_the_edge_highlight_and_label_are_the_webs():
    assert swift_colour("edge") == hex_colour(token(THEME_CSS, "dw-primary-border"))
    highlight = re.fullmatch(r"inset 0 1px 0 rgba\((\d+), (\d+), (\d+), ([0-9.]+)\)", token(THEME_CSS, "dw-primary-highlight"))
    assert highlight, token(THEME_CSS, "dw-primary-highlight")
    r, g, b, a = highlight.groups()
    assert swift_colour("highlight") == (int(r), int(g), int(b), float(a))
    assert swift_colour("label") == hex_colour(token(THEME_CSS, "dw-text"))


def test_pressed_corners_and_height_are_the_webs():
    pressed = re.fullmatch(r"brightness\(([0-9.]+)\)", token(THEME_CSS, "dw-primary-pressed"))
    assert pressed, token(THEME_CSS, "dw-primary-pressed")
    assert swift_number("pressed") == float(pressed.group(1))
    assert swift_number("radius") == px(token(THEME_CSS, "dw-radius-control"))
    assert swift_number("largeHeight") == px(token(PLAYER_CSS, "pl-pill-height"))


def test_the_players_primary_pill_is_drawn_from_these_tokens():
    # .pl-pill.is-primary is what the web's album page draws its Play with: its fill, edge and highlight are the --dw-
    # primary tokens (through player.css's --pl- aliases), so the phone's Play is the web's
    assert token(PLAYER_CSS, "pl-primary-bg") == "var(--dw-primary-bg)"
    assert token(PLAYER_CSS, "pl-primary-edge") == "var(--dw-primary-border)"
    assert token(PLAYER_CSS, "pl-primary-highlight") == "var(--dw-primary-highlight)"
    assert token(PLAYER_CSS, "pl-primary-pressed") == "var(--dw-primary-pressed)"
    css = PLAYER_CSS.read_text(encoding="utf-8")
    rule = re.search(r"\n\.pl-pill\.is-primary \{([^}]*)\}", css)
    assert rule, "player.css has no .pl-pill.is-primary"
    assert "background: var(--pl-primary-bg);" in rule.group(1)
    assert "border-color: var(--pl-primary-edge);" in rule.group(1)
    assert "box-shadow: var(--pl-primary-highlight);" in rule.group(1)
    assert ".pl-pill.is-primary:active:not(:disabled) { filter: var(--pl-primary-pressed); }" in css
    pill = re.search(r"\n\.pl-pill \{([^}]*)\}", css)
    assert pill and "height: var(--pl-pill-height);" in pill.group(1)
    assert "border-radius: var(--pl-radius-control);" in pill.group(1)
    assert token(PLAYER_CSS, "pl-radius-control") == "var(--dw-radius-control)"


def test_no_button_in_the_app_is_drawn_with_the_tint():
    # every `.borderedProminent` took the primary face (2.8): one left would be the tint under a white label again
    app = REPO / "ios" / "App"
    left = [str(path.relative_to(app)) for path in sorted(app.rglob("*.swift"))
            if ".buttonStyle(.borderedProminent)" in path.read_text(encoding="utf-8")]
    assert not left, left
    faces = REPO / "ios" / "App" / "Shared" / "ButtonFaces.swift"
    text = faces.read_text(encoding="utf-8")
    for name in ("top", "bottom", "edge", "highlight", "label", "pressed", "radius", "largeHeight"):
        assert f"PrimaryButton.{name}" in text, f"the app's face doesn't draw PrimaryButton.{name}"
