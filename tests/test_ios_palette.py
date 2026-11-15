"""The iPhone app's primary button is the web's (notes/ios-specs/phase4-library.md 2.8, slice 3b).

James: "the color of the play button on the album page doesn't show the play icon". The phone drew its Play with
SwiftUI's `.borderedProminent` under the app's tint (#C084FC, the web's accent for text on black) and a white glyph -
2.64:1. It now draws the web's primary button, as player.css's `.pl-pill.is-primary` and app.css's primary buttons do:
theme.css's --dw-primary-bg gradient, --dw-primary-border edge, --dw-primary-highlight line, a --dw-text label, 4 pt
corners (--dw-radius-control), and the album's and playlist's pills 48 pt tall (--pl-pill-height). Pressed, its fill
and edge are darkened by brightness(0.92) (--dw-primary-pressed) and its label left white - the web's filter darkens the
label too, under AA at its top (slice 3b's review) - and the secondary pill beside it turns its gradient over
(--dw-secondary-bg-active), as the web's .pl-pill does. PrimaryButton (ios/DeadwaxKit/Sources/DeadwaxCore/PrimaryButton.swift) holds those
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
    # every `.borderedProminent` took the primary face (2.8): one left would be the tint under a white label again -
    # however it is spelled (slice 3b's review): `.buttonStyle(.borderedProminent)`, `BorderedProminentButtonStyle()`,
    # a style chosen by a ternary, anywhere in the app's code (its comments may name it)
    app = REPO / "ios" / "App"
    tint = re.compile(r"\bborderedProminent\b|\bBorderedProminentButtonStyle\b")
    left = [f"{path.relative_to(app)}:{number}" for path in sorted(app.rglob("*.swift"))
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
            if tint.search(line.split("//", 1)[0])]
    assert not left, left
    faces = REPO / "ios" / "App" / "Shared" / "ButtonFaces.swift"
    text = faces.read_text(encoding="utf-8")
    for name in ("top", "bottom", "edge", "highlight", "label", "pressedTop", "pressedBottom", "pressedEdge",
                 "radius", "largeHeight"):
        assert re.search(rf"\bPrimaryButton\.{name}\b", text), f"the app's face doesn't draw PrimaryButton.{name}"
    # the label is never darkened with the fill: no multiply over the whole button
    assert "colorMultiply" not in text and ".brightness(" not in text


def test_the_secondary_pill_turns_its_gradient_over_when_pressed():
    # the web's pressed pill (.pl-pill:active) is its gradient reversed, neither lighter nor darker: so is the phone's
    rest = re.fullmatch(r"linear-gradient\(to bottom, (rgba\([^)]*\)), (rgba\([^)]*\))\)",
                        token(THEME_CSS, "dw-secondary-bg"))
    active = re.fullmatch(r"linear-gradient\(to bottom, (rgba\([^)]*\)), (rgba\([^)]*\))\)",
                          token(THEME_CSS, "dw-secondary-bg-active"))
    assert rest and active, (token(THEME_CSS, "dw-secondary-bg"), token(THEME_CSS, "dw-secondary-bg-active"))
    assert (active.group(1), active.group(2)) == (rest.group(2), rest.group(1))
    assert token(PLAYER_CSS, "pl-secondary-bg-active") == "var(--dw-secondary-bg-active)"
    assert ".pl-pill:active:not(:disabled) { background: var(--pl-secondary-bg-active); }" in PLAYER_CSS.read_text(
        encoding="utf-8")
    palette = (REPO / "ios" / "App" / "DeadwaxApp.swift").read_text(encoding="utf-8")
    pressed = re.search(r"static let secondaryFillPressed = LinearGradient\(colors: \[([^\]]*)\]", palette)
    assert pressed, "DeadwaxApp.swift has no secondaryFillPressed"
    stops = re.findall(r"TurntablePalette\.(\w+)", pressed.group(1))
    assert stops == ["secondaryFillBottom", "secondaryFillTop"], stops
    faces = (REPO / "ios" / "App" / "Shared" / "ButtonFaces.swift").read_text(encoding="utf-8")
    assert "pressed ? Palette.secondaryFillPressed : Palette.secondaryFill" in faces


# The squared look (14 Nov, notes/ios.md "The squared look"). James, on the phone at app 0.11: "maybe square off the
# slider and the bar at the bottom and the now playing bar as well" - "as a matter of fact, let's square everything off
# a bit more, especially the album arts" - "but the search button and options button at the top can be circles". Every
# corner in the app is one of ios/App/Shared/Corners.swift's; the phone's covers and cards are squarer than the web's on
# purpose, its controls, tracks and fills the web's own.

APP = REPO / "ios" / "App"
CORNERS = APP / "Shared" / "Corners.swift"
APP_CSS = REPO / "interface" / "player" / "app.css"


def corner(name: str) -> float:
    found = re.search(rf"static let {name}: CGFloat = ([0-9.]+)\n", CORNERS.read_text(encoding="utf-8"))
    assert found, f"Corners has no {name}"
    return float(found.group(1))


def app_code() -> list[tuple[str, int, str]]:
    # every line of the app's Swift with its comments taken off: (file, line number, code)
    lines = []
    for path in sorted(APP.rglob("*.swift")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            lines.append((str(path.relative_to(APP)), number, line.split("//", 1)[0]))
    return lines


def test_the_corners_are_the_squared_looks():
    assert (corner("art"), corner("card"), corner("control"), corner("track"), corner("fill")) == (2, 4, 4, 2, 1)
    # the controls, tracks and fills are the web's own - the primary button's corners among them (PrimaryButton.radius,
    # held to --dw-radius-control above), so a button is the same shape on both
    assert corner("control") == px(token(THEME_CSS, "dw-radius-control")) == swift_number("radius")
    assert corner("track") == px(token(THEME_CSS, "dw-radius-track"))
    assert corner("fill") == px(token(THEME_CSS, "dw-radius-fill"))
    # the departure, on purpose: covers and cards squarer on the phone than the web's 3 and 6
    assert corner("art") < px(token(THEME_CSS, "dw-radius-cover"))
    assert corner("card") < px(token(THEME_CSS, "dw-radius-card"))


def test_every_corner_in_the_app_is_a_token():
    # no radius written in a view: a RoundedRectangle is Corners' own, the primary's (PrimaryButton.radius, the same as
    # Corners.control) or the turntable's (TurntableFace.lookRadius - the plinth's look button and the speed chip)
    kept = {"RoundedRectangle(cornerRadius: radius)", "RoundedRectangle(cornerRadius: CGFloat(TurntableFace.lookRadius))"}
    left = []
    for name, number, code in app_code():
        if name == "Shared/Corners.swift":
            continue
        if re.search(r"cornerRadius:\s*[0-9]", code):
            left.append(f"{name}:{number} a radius of its own")
        for found in re.findall(r"RoundedRectangle\([^)]*\)+", code):
            if found not in kept:
                left.append(f"{name}:{number} {found}")
        # nothing is a capsule: a pill is a control's rounded rectangle now
        if re.search(r"\bCapsule\(\)|[(:]\s*\.capsule\b", code):
            left.append(f"{name}:{number} a capsule")
    assert not left, left
    faces = (APP / "Shared" / "ButtonFaces.swift").read_text(encoding="utf-8")
    assert "let radius = CGFloat(PrimaryButton.radius)" in faces


def test_every_system_bordered_button_is_squared():
    # SwiftUI's `.bordered` is a capsule on iOS 26 and later: each in the app takes a control's corners beside it
    lines = app_code()
    loose = []
    for index, (name, number, code) in enumerate(lines):
        if ".buttonStyle(.bordered)" in code:
            following = " ".join(line for _, _, line in lines[index:index + 3])
            if ".buttonBorderShape(Corners.controlBorder)" not in following:
                loose.append(f"{name}:{number}")
    assert not loose, loose


def palette_rgb(name: str) -> tuple[int, int, int]:
    palette = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    found = re.search(rf"static let {name} = Color\(red: 0x([0-9A-F]{{2}}) / 255, green: 0x([0-9A-F]{{2}}) / 255, "
                      rf"blue: 0x([0-9A-F]{{2}}) / 255\)\n", palette)
    assert found, f"Palette has no {name}"
    return int(found.group(1), 16), int(found.group(2), 16), int(found.group(3), 16)


def test_the_apps_own_bars_are_the_webs():
    # the tab bar (.app-tabbar) and the Library's top with its switch (.app-segmented): theme.css's colours
    assert palette_rgb("tabBar") == hex_colour(token(THEME_CSS, "dw-tab-bar"))[:3]
    assert palette_rgb("border") == hex_colour(token(THEME_CSS, "dw-border"))[:3]
    assert palette_rgb("tabInactive") == hex_colour(token(THEME_CSS, "dw-tab-inactive"))[:3]
    assert palette_rgb("text2") == hex_colour(token(THEME_CSS, "dw-text-2"))[:3]
    assert token(THEME_CSS, "dw-well") == "rgba(0, 0, 0, 0.2)"
    palette = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    assert "static let well = Color.black.opacity(0.2)\n" in palette
    # the tab bar's sizes: --dw-tab-item tall, --dw-tab-pad above, --app-tab-side either side, --app-tab-gap between
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    assert f"private static let height: CGFloat = {px(token(THEME_CSS, 'dw-tab-item')):g}\n" in tabs
    assert f"private static let pad: CGFloat = {px(token(THEME_CSS, 'dw-tab-pad')):g}\n" in tabs
    assert f"private static let side: CGFloat = {px(token(APP_CSS, 'app-tab-side')):g}\n" in tabs
    assert f"private static let gap: CGFloat = {px(token(APP_CSS, 'app-tab-gap')):g}\n" in tabs
    # the switch's well, the gap between its segments and their reach past it
    top = (APP / "Library" / "LibraryTop.swift").read_text(encoding="utf-8")
    assert f"private static let well: CGFloat = {px(token(THEME_CSS, 'dw-segmented')):g}\n" in top
    assert f"private static let gap: CGFloat = {px(token(APP_CSS, 'app-segment-gap')):g}\n" in top
    assert f"private static let reach: CGFloat = {px(token(APP_CSS, 'app-segment-reach')):g}\n" in top
    # iOS's own bar is hidden on every tab's stack and every page pushed, so it never comes back over the app's
    routes = (APP / "Shared" / "Routes.swift").read_text(encoding="utf-8")
    assert tabs.count(".toolbar(.hidden, for: .tabBar)") == 2 and ".toolbar(.hidden, for: .tabBar)" in routes
    assert ".accessibilityAddTraits(.isTabBar)" in tabs
