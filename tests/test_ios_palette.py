"""The iPhone app's primary button is the web's (notes/ios-specs/phase4-library.md 2.8, slice 3b).

James: "the color of the play button on the album page doesn't show the play icon". The phone drew its Play with
SwiftUI's `.borderedProminent` under the app's tint (#C084FC, the web's accent for text on black) and a white glyph -
2.64:1. It now draws the web's primary button, as player.css's `.pl-pill.is-primary` and app.css's primary buttons do:
theme.css's --dw-primary-bg gradient, --dw-primary-border edge, --dw-primary-highlight line, a --dw-text label, 4 pt
corners (--dw-radius-control; square on the phone since 15 Nov, Corners.control), and the album's and playlist's pills
48 pt tall (--pl-pill-height). Pressed, its fill
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
    # (15 Nov, actual corners) every number but the radius: PrimaryButton.radius keeps the web's 4, and the phone's
    # face takes Corners.control, square
    for name in ("top", "bottom", "edge", "highlight", "label", "pressedTop", "pressedBottom", "pressedEdge",
                 "largeHeight"):
        assert re.search(rf"\bPrimaryButton\.{name}\b", text), f"the app's face doesn't draw PrimaryButton.{name}"
    assert "PrimaryButton.radius" not in text and "let radius = Corners.control" in text
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
    # 15 Nov, James: "let's square off everything already square a bit more. Actual corners." Every corner is 0 - truly
    # square - a system button's border with them
    assert (corner("art"), corner("card"), corner("control"), corner("track"), corner("fill")) == (0, 0, 0, 0, 0)
    assert "static let controlBorder = ButtonBorderShape.roundedRectangle(radius: control)\n" in CORNERS.read_text(
        encoding="utf-8")
    # the departure from the web, on purpose: square where the web's cover, card, control, track and fill are rounded -
    # PrimaryButton.radius keeps the web's control radius (held above), which the phone's face no longer draws
    for web in ("dw-radius-cover", "dw-radius-card", "dw-radius-control", "dw-radius-track", "dw-radius-fill"):
        assert px(token(THEME_CSS, web)) > 0
    assert swift_number("radius") == px(token(THEME_CSS, "dw-radius-control"))


def test_every_corner_in_the_app_is_a_token():
    # no radius written in a view: a RoundedRectangle is Corners' own, or a face's `radius` - Corners.control: the
    # primary's, and (review, 15 Nov) the look button's and the speed chip's, which drew TurntableFace.lookRadius. That
    # stays the web's number for the plinth's speed readout, drawn by DeadwaxTurntable, never by a view in the app.
    kept = {"RoundedRectangle(cornerRadius: radius)"}
    left = []
    for name, number, code in app_code():
        if "TurntableFace.lookRadius" in code or "squareIcon.radius" in code:
            left.append(f"{name}:{number} the turntable's radius")
        #? (the Mac redesign, R1; R1b) the Mac's rounded corners - James: "Rounded on Mac only" - are DWCorners' Mac half's
        #? alone, held to dw.css by test_ios_mac_look.py; the phone's stay Corners', every one 0 (DWCorners' phone half
        #? names them, below), and round stays round: DWCorners' round shape is the switch's
        if name in ("Shared/Corners.swift", "Look/DWCorners.swift"):
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
    assert "let radius = Corners.control" in faces
    look = (APP / "Player" / "Turntable" / "TurntableView.swift").read_text(encoding="utf-8")
    look = look[look.index("private struct LookFace"):look.index("private struct LookGlyph")]
    chip = (APP / "Player" / "NowPlayingView.swift").read_text(encoding="utf-8")
    chip = chip[chip.index("private struct SpeedChipFace"):chip.index("private struct Backdrop")]
    for face in (look, chip):
        assert "let radius = Corners.control" in face
    # the look button's highlight kept where it is square: its band down to the line's foot
    assert "Rectangle().frame(height: max(radius, line))" in look


def test_the_looks_phone_corners_are_corners():
    # (the redesign, R1b) James, 25 Nov: "keep the phone square as well" - the shared look's corners on the phone are
    # Corners' own (every one 0), never a number of the look's; on the Mac dw.css's (test_ios_mac_look.py)
    text = (APP / "Look" / "DWCorners.swift").read_text(encoding="utf-8")
    phone = text[text.index("    enum Phone {"):text.index("    /// This device's.")]
    #? (R8) and the meter's track and fill (DWMeter): Corners' own track and fill
    assert re.findall(r"static let (\w+): CGFloat = (\S+)", phone) == [
        ("button", "Corners.control"), ("box", "Corners.card"), ("chip", "Corners.control"), ("meter", "Corners.track"),
        ("meterFill", "Corners.fill")]
    assert (corner("control"), corner("card"), corner("track"), corner("fill")) == (0, 0, 0, 0)
    for name in ("button", "box", "chip", "meter", "meterFill"):
        assert f"static var {name}: CGFloat {{ Platform.mac ? Mac.{name} : Phone.{name} }}" in text
    # the one round shape is a capsule, the switch's - nothing else in the app is one
    assert re.findall(r"Capsule\(", text) == ["Capsule("] and "static var roundShape: Capsule" in text
    uses = [name for name, _, code in app_code() if "roundShape" in code and name != "Look/DWCorners.swift"]
    assert sorted(set(uses)) == ["Phone/PhoneSwitch.swift"], uses


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


def _phone_look():
    """test_ios_phone_look.py's reading of dw.css's phone rules, loaded when a test asks: it loads this file itself."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("_palette_phone_look", Path(__file__).resolve().parent
                                                  / "test_ios_phone_look.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_apps_own_bars_are_the_webs():
    # the iPhone's Palette, still theme.css's colours where the app draws them
    assert palette_rgb("border") == hex_colour(token(THEME_CSS, "dw-border"))[:3]
    assert palette_rgb("text2") == hex_colour(token(THEME_CSS, "dw-text-2"))[:3]
    assert token(THEME_CSS, "dw-well") == "rgba(0, 0, 0, 0.2)"
    palette = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    assert "static let well = Color.black.opacity(0.2)\n" in palette
    #? (R4, after its review) the old bars' fills and grey, read by nothing once DWPalette's tabBarFace and tabItemText
    #? and MacPalette's playerFace drew the bars, are gone rather than kept for this test alone
    for gone in ("tabBar", "tabInactive", "playerBar"):
        assert not re.search(rf"\bstatic let {gone}\b", palette), gone
    #? (the redesign, R4) the tab bar is dw.css's `.dw.ph .tabbar` now, not the web's .app-tabbar: on #121117 under its
    #? #2c2a36 edge, the tabs 6 under it side to side with no room at either end, each 49 tall at least, its symbol's
    #? box 24 and 3 over its words, 11 and medium, #8a8a9c - the shown one the accent. DWPalette's lines and PhoneLook's
    #? sizes say which rule each is (test_ios_phone_look.py holds every one to it); these are the bar's own draws
    look = _phone_look()
    lines = look.palette_lines()
    for name, source, value in (("tabBarFace", "dw.ph: .tabbar background", "#121117"),
                                ("tabBarEdge", "dw.ph: .tabbar border-top", "#2c2a36"),
                                ("tabItemText", "dw.ph: .tabbar > a color", "#8a8a9c")):
        assert lines[name][1] == source, name
        selector, prop = source[len("dw.ph: "):].rsplit(" ", 1)
        assert look.css(selector, prop) == value, source
    assert look.css(".tabbar", "padding-top") == "6px" and look.css(".tabbar", "padding-left") == "0"
    assert look.css(".tabbar > a", "height") == "49px" and look.css(".tabbar > a", "gap") == "3px"
    assert look.css(".tabbar svg", "width") == "24px" and look.css(".tabbar > a", "font-size") == "11px"
    assert look.css(".tabbar > a", "font-weight") == "500" and look.css(".tabbar > a.on", "color") == "#c084fc"
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    bar = tabs[tabs.index("struct AppTabBar"):tabs.index("private struct AppTabButton")]
    for drawn in ("private static let pad = CGFloat(PhoneLook.tabBarTop)\n", ".padding(.top, Self.pad)",
                  "DWRule(colour: DWPalette.tabBarEdge)",
                  "DWPalette.tabBarFace\n                .ignoresSafeArea(.container, edges: .bottom)"):
        assert drawn in bar, drawn
    assert ".padding(.horizontal" not in bar and not re.search(r"(?<![\w.])Palette\.", bar)
    # the edge drawn before the tabs, so the lit line over the shown one is drawn over it
    assert bar.index("DWRule(colour: DWPalette.tabBarEdge)") < bar.index("HStack(spacing: 0) {")
    button = tabs[tabs.index("private struct AppTabButton"):tabs.index("private struct TabBadge")]
    for drawn in ("VStack(spacing: CGFloat(PhoneLook.tabGap))",
                  "@ScaledMetric(relativeTo: .title2) private var symbolBox = CGFloat(PhoneLook.tabIcon)",
                  ".frame(height: symbolBox)", ".font(Typeface.Phone.text(.tabItem).weight(.medium))",
                  ".foregroundStyle(shown ? DWPalette.acc : DWPalette.tabItemText)", ".lookHeight(PhoneLook.tabItem)"):
        assert drawn in button, drawn
    assert not re.search(r"(?<![\w.])Palette\.", button)
    #? (the redesign, R2) the Library's switch was the strip's (PhoneStrip); (R2b) the row's switch again, DWSegmented's
    #? (test_ios_library_look.py)
    # iOS's own bar is hidden on every tab's stack and every page pushed, so it never comes back over the app's
    routes = (APP / "Shared" / "Routes.swift").read_text(encoding="utf-8")
    assert tabs.count(".toolbar(.hidden, for: .tabBar)") == 2 and ".toolbar(.hidden, for: .tabBar)" in routes
    assert ".accessibilityAddTraits(.isTabBar)" in tabs


def test_the_requests_badge_is_the_webs():
    # (Phase 6) Requests' count on the app's tab bar - since the redesign's R4 dw.css's `.dw.ph .tabbar .count`: the
    # look's count (DWCount - .count's purple, its mono words, square on the phone) laid over the bar's own colour, so
    # it is opaque, its left edge 9 right of the tab's centre and its top 1 above the tab's
    look = _phone_look()
    assert look.css(".count", "background") == "rgba(168, 85, 247, 0.16)"
    assert look.css(".count", "border") == "rgba(192, 132, 252, 0.4)" and look.css(".count", "border-radius") == "0"
    assert look.css(".tabbar .count", "position") == "absolute" and look.css(".tabbar .count", "left") == "50%"
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    badge = tabs[tabs.index("private struct TabBadge"):]
    badge = badge[:badge.index("\n}\n")]
    assert f"private static let right: CGFloat = {px(look.css('.tabbar .count', 'margin-left')):g}\n" in badge
    assert f"private static let up: CGFloat = {-px(look.css('.tabbar .count', 'top')):g}\n" in badge
    for drawn in ("DWCount(count: count)", ".background(DWPalette.tabBarFace, in: DWCorners.chipShape)",
                  "box[.leading] - Self.right", "box[.top] + Self.up", ".accessibilityHidden(true)"):
        assert drawn in badge, drawn
    assert not re.search(r"(?<![\w.])(Palette|Corners)\.", badge)
    count = (APP / "Look" / "DWChip.swift").read_text(encoding="utf-8")
    count = count[count.index("struct DWCount"):]
    for drawn in ("DWPalette.acct", "DWPalette.countFill", "DWPalette.countEdge", "DWCorners.chipShape"):
        assert drawn in count, drawn
    # over the tab, on Requests' button alone, and read in its label
    button = tabs[tabs.index("private struct AppTabButton"):tabs.index("private struct TabBadge")]
    assert ".overlay(alignment: .top) {\n                if !badge.isEmpty { TabBadge(count: badge) }" in button
    assert 'tab == .requests ? RequestWords.badgeText(requests.badgeCount) : ""' in tabs
    assert "tab == .requests ? RequestWords.badgeLabel(tab.title, requests.badgeCount) : tab.title" in tabs
    assert ".accessibilityLabel(spoken)" in tabs



def gradient(css: str) -> list[tuple[int, int, int, float]]:
    """A `linear-gradient(to bottom, #a, #b)` token's two colours, top first."""
    found = re.fullmatch(r"linear-gradient\(to bottom,\s*(#[0-9a-fA-F]{6}),\s*(#[0-9a-fA-F]{6})\)", css)
    assert found, css
    return [hex_colour(found.group(1)), hex_colour(found.group(2))]


def test_the_sources_sheet_is_drawn_in_the_webs_colours():
    # (Phase 6, slice 2) a source's card and the store line's box (.app-source, .app-store-box): --dw-card under a
    # --dw-border edge, the best match's --dw-best; the speed's bars --dw-bar-green and --dw-bar-grey; a signal under 40
    # and a red edition word STYLE.md's red badge; the facts' labels --dw-text-label-color
    assert palette_rgb("card") == hex_colour(token(THEME_CSS, "dw-card"))[:3]
    assert palette_rgb("best") == hex_colour(token(THEME_CSS, "dw-best"))[:3]
    assert palette_rgb("label") == hex_colour(token(THEME_CSS, "dw-text-label-color"))[:3]
    palette = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    for name, css in (("barGreen", "dw-bar-green"), ("barGrey", "dw-bar-grey")):
        top, bottom = gradient(token(THEME_CSS, css))
        declared = palette[palette.index(f"static let {name} = LinearGradient("):]
        declared = declared[:declared.index("startPoint:")]
        drawn = [tuple(int(part, 16) for part in found)
                 for found in re.findall(r"Color\(red: 0x([0-9A-F]{2}) / 255, green: 0x([0-9A-F]{2}) / 255, "
                                         r"blue: 0x([0-9A-F]{2}) / 255\)", declared)]
        assert drawn == [top[:3], bottom[:3]], name
    assert token(THEME_CSS, "dw-badge-red-bg") == "rgba(248, 113, 113, 0.14)"
    assert token(THEME_CSS, "dw-badge-red-border") == "rgba(252, 165, 165, 0.3)"
    assert "static let dangerFill = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255).opacity(0.14)\n" in palette
    assert "static let dangerEdge = Color(red: 252 / 255, green: 165 / 255, blue: 165 / 255).opacity(0.3)\n" in palette
    # and drawn where the web draws them
    card = (APP / "Get" / "SourceCardView.swift").read_text(encoding="utf-8")
    for drawn in ("Palette.card", "Palette.best", "Palette.border", "Palette.barGreen", "Palette.barGrey",
                  "Palette.dangerFill", "Palette.dangerEdge", "Palette.label", "Palette.well", "Palette.toggledFill",
                  "Palette.toggledEdge", "Palette.accentText", "PrimaryFace()"):
        assert drawn in card, drawn
    box = (APP / "Get" / "StoreLineView.swift").read_text(encoding="utf-8")
    assert "Palette.card" in box and "Palette.border" in box and "Palette.held" in box
    # (slice 3) Join and Add waiting on deadwax: faded to --app-job-busy, as app.css fades .app-store-join
    assert token(REPO / "interface" / "player" / "app.css", "app-job-busy") == "0.75"
    assert "static let busy: Double = 0.75\n" in palette
    assert "Palette.busy" in box and "SecondaryPill()" in box and "Palette.danger" in box

def test_the_play_bar_is_the_tab_bars_top():
    # 15 Nov, James: "merge the play bar with the bottom bar so it doesn't look like it's floating", "opaque the whole
    # way", "get rid of the skip forward button", "let's make sure the play/pause isn't right up against the edge". The
    # mini player is drawn by AppTabBar alone, on its opaque fill rather than as a card of material over the pages, with
    # Play/Pause its only button: 48 pt, 12-16 pt from the edge. VoiceOver's actions are the bar's way to skip.
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    mini = (APP / "Player" / "MiniPlayerView.swift").read_text(encoding="utf-8")
    bar = tabs[tabs.index("struct AppTabBar"):tabs.index("private struct AppTabButton")]
    assert "MiniPlayerView()" in bar
    assert sum(path.read_text(encoding="utf-8").count("MiniPlayerView()") for path in APP.rglob("*.swift")) == 1
    assert "Material" not in mini and "Corners.card" not in mini
    assert "forward.fill" not in mini and "backward.fill" not in mini
    # (R4) dw.css's .mini: 60 tall, Play/Pause's target 48 with 12 past it, on the bar's own ground
    look = _phone_look()
    assert look.css(".mini", "height") == "60px" and look.css(".mini .key.big", "width") == "48px"
    assert look.css(".mini", "padding-right") == "12px"
    assert "private static let height = CGFloat(PhoneLook.mini)\n" in mini
    assert "private static let button = CGFloat(PhoneLook.miniPlay)\n" in mini
    assert "private static let edge = CGFloat(PhoneLook.miniTrail)\n" in mini
    assert ".background { PhoneMiniGround() }" in mini
    assert "Button(PlayerWords.nextSong) { player.next() }" in mini
    assert "Button(PlayerWords.previousSong) { player.songBefore() }" in mini
    # after review: one drag takes the bar, never a touch that hasn't moved, so every tap is the cover's, the title's or
    # Play/Pause's; the line is drawn only, nothing over the page above the bar takes a touch; VoiceOver's order is set
    assert mini.count("DragGesture(") == 1 and "DragGesture(minimumDistance: PlayBar.decideAfter" in mini
    assert ".highPriorityGesture(drag)" in mini and "minimumDistance: 0" not in mini
    line = mini[mini.index("private struct SeekLine"):]
    assert ".allowsHitTesting(false)" in line and "gesture" not in line.lower()
    for priority in (3, 2, 1):
        assert f".accessibilitySortPriority({priority})" in mini


def test_the_bars_run_smooth_only_while_the_song_plays():
    # 15 Nov, James: "Can we make the progress bar smooth instead of updating every half second?" The seek line's part
    # played and Now Playing's bar (and its clocks) are drawn from a timeline of frames, 30 a second at most, that stops
    # unless the song plays - paused, loading, under a finger, for the play bar with Now Playing over it, and (review)
    # for Now Playing's bar unseen, on the turntable or under a sheet - and then they show shownPosition, as before.
    # Between the ticker's readings they carry the last one on (Core's PlayClock), the engine not asked, and (review)
    # through a wait - loading to play - they stand where they drew; the ticker and all it drives are as they were;
    # VoiceOver's value stays on shownPosition.
    model = (APP / "Models" / "PlayerModel.swift").read_text(encoding="utf-8")
    mini = (APP / "Player" / "MiniPlayerView.swift").read_text(encoding="utf-8")
    scrubber = (APP / "Player" / "ScrubberView.swift").read_text(encoding="utf-8")
    clock = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "PlayClock.swift").read_text(encoding="utf-8")
    assert "public static let frame = 1.0 / 30\n" in clock
    assert "var barsRun: Bool { isPlaying && !isLoading }" in model
    reading = model[model.index("func barPosition(at now: Double) -> Double {"):]
    reading = reading[:reading.index("\n    }\n")]
    assert "guard barsRun || barsWait, let smooth, smooth.entry == heardEntry else { return shownPosition }" in reading
    assert "private var barsWait: Bool { isPlaying && isLoading }" in model
    assert "PlayClock.shown(smooth, now: now)" in reading and "link" not in reading
    # the ticker: still twice a second, still driving the plays, Repeat's top-up, resume and the pace from `position`
    assert "Timer(timeInterval: 0.5, repeats: true)" in model
    tick = model[model.index("    private func tick() {"):]
    tick = tick[:tick.index("\n    }\n")]
    for kept in ("measurePace()", "reporter.tick(position: position, duration: duration)",
                 "controller?.tick(heard: reporter.heard, length: length)", "resuming?.position(position)",
                 "if !isPlaying { stopTicking() }"):
        assert kept in tick
    assert "smooth = PlayClock.reading(entry: at.key, seconds: at.seconds, at: now, rate: speed, shown: before)" in tick
    # stopped: a wait holds the reading where the bars drew (PlayClock.held), a pause drops it
    assert "if !barsRun {\n            smooth = barsWait ? smooth.map" in tick and "PlayClock.held(reading, now: now)" in tick
    # a speed restart's wait, past its hold, with no tick to say so: held there too, never dropped; a speed sent while
    # they wait leaves it held
    assert "if let reading = self.smooth { self.smooth = PlayClock.held(reading, now: now) }" in model
    assert "self.smooth = nil" not in model and "if barsRun, let reading = smooth {" in model
    for view, runs, timelines in ((mini, "let runs = player.barsRun && held == nil && !navigation.nowPlayingShown", 1),
                                  (scrubber, "let runs = visible && player.barsRun && held == nil", 2)):
        assert runs in view
        assert view.count("TimelineView(.animation(minimumInterval: PlayClock.frame, paused: !runs))") == timelines
        assert "let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)" in view
        assert ".accessibilityValue(PlayerWords.scrubberValue(shown: shown, length: length))" in view
        # the frames' value is drawn inside the timeline alone
        assert view.count("player.barPosition(at: Monotonic.seconds())") == 1
        assert view.index("TimelineView(") < view.index("player.barPosition(")
    # the seek line's timeline holds its fill alone; the scrubber's clocks are redrawn only when their words change
    fill = mini[mini.index("TimelineView("):]
    assert fill.index("Rectangle().fill(DWPalette.seekFill)") < fill.index("}")
    # (review) the scrubber's two hold its fill and its clocks alone - the track and the touch outside them - and it
    # runs only while it can be seen: Now Playing's flag, the turntable's look and the sheets over it
    order = [scrubber.index(part) for part in ("Rectangle().fill(Color.primary.opacity(0.2))", "TimelineView(",
                                               "Rectangle().fill(Color.primary.opacity(0.85))", ".gesture(press(",
                                               "ScrubberClocks(elapsed:")]
    assert order == sorted(order)
    second = scrubber.index("TimelineView(", order[1] + 1)
    assert order[3] < second < order[4]
    assert scrubber.count("drawn(held, length: length)") == 2
    assert "let visible: Bool" in scrubber
    now_playing = (APP / "Player" / "NowPlayingView.swift").read_text(encoding="utf-8")
    assert "ScrubberView(visible: !turntable && !sheetOver)" in now_playing
    #? (R3) the one sheet (the Queue, Info, the EQ), Add to a playlist and the cover full screen
    assert "private var sheetOver: Bool { sheetUp || playlistPick != nil || viewing != nil }" in now_playing
    assert "private struct ScrubberClocks: View, Equatable" in scrubber and ".equatable()" in scrubber
    assert "PlayerWords.elapsed(shown: time)" in scrubber and "PlayerWords.remaining(shown: time, length: length)" in scrubber
    # the lyrics keep their own clock
    assert "player.clock()" in (APP / "Player" / "LyricsView.swift").read_text(encoding="utf-8")


def test_the_librarys_top_sits_under_the_status_bar():
    # 15 Nov, James: "on the app the top bar is obstructed by the Dynamic Island". The Library's own top was an inset on
    # its pager, a scroll view free to run under the status bar; now the top, the offline banner and the pager stand
    # in a VStack, which is laid out in the safe area whatever they do, and only the top's fill reaches up behind the
    # status bar. The Library is the only page that hides iOS's navigation bar, and every other view that reaches
    # under the status bar is a fill (or keeps its content in the safe area). Since 18 Nov the row's room is read by a
    # UIKit probe in its own window, kept under a presentation and measured afresh otherwise; since 20 Nov kept too while
    # the row is above its window's edge, and read again after every ask. (The redesign, R2) The top is over the phone's
    # own black ground (dw.css's `.dw.ph` background, `.dw.ph .topbar`'s none) - the old tab bar's fill and its hairline
    # gone; (R2b) it is iLibrary's one row again (.ltop: Find's circle, the switch, the •••), R2's titled top and strip
    # gone, the offline banner straight under it.
    library = (APP / "Library" / "LibraryView.swift").read_text(encoding="utf-8")
    pager = library[library.index("private func pager(albums: AlbumList)"):library.index("private func pageView(")]
    assert ".safeAreaInset(edge: .top" not in library and ".showsOfflineBanner()" not in pager
    order = [pager.index(part) for part in ("return VStack(spacing: 0) {", "LibraryTop(", "switcher(order)",
                                             "OfflineBanner()", "ScrollView(.horizontal)",
                                             ".containerRelativeFrame([.horizontal, .vertical])",
                                             ".toolbar(.hidden, for: .navigationBar)")]
    assert order == sorted(order)
    top = (APP / "Library" / "LibraryTop.swift").read_text(encoding="utf-8")
    assert top.count("ignoresSafeArea") == 1
    assert ".background {\n            Palette.page\n                .ignoresSafeArea(.container, edges: .top)\n" in top
    design = (REPO / "ios" / "design" / "dw.css").read_text(encoding="utf-8")
    assert re.search(r"^\.dw\.ph \{ background: #000;", design, re.M)
    assert re.search(r"^\.dw\.ph \.topbar \{[^}]*background: none;", design, re.M)
    assert palette_rgb("page") == (0, 0, 0)
    assert "Palette.tabBar" not in top and "Palette.border" not in top and "LibrarySwitchControl" not in top
    # the second time (15 Nov, "the library's top still doesn't clear the dynamic island"): the row measures where its
    # own top is and comes down by what of its window's top safe area that doesn't clear (TopClearance), its padding
    # inside what it measures so coming down never moves it
    assert ".padding(.top, clearance)" in top
    # the third (18 Nov, "after pulling up the play screen and going back to library, the top bar is back inside the
    # Dynamic Island"): read by a UIKit probe of the row's own frame - a background after the padding, the fill's
    # ignore not on it - in ITS OWN window's coordinates, with that window's inset, nothing out of a window
    row = top
    body = row[row.index("var body: some View {"):row.index("private func take(")]
    order = [body.index(part) for part in (".padding(.top, clearance)", ".ignoresSafeArea(.container, edges: .top)\n",
                                           ".background {\n            TopProbe(eyes: eyes) {",
                                           ".onGeometryChange(for: [CGFloat].self)", '.onAppear { eyes.probe?.soon("appear") }')]
    assert order == sorted(order)
    probe_view = body[body.index("TopProbe(eyes: eyes)"):body.index(".onGeometryChange(for: [CGFloat].self)")]
    assert "ignoresSafeArea" not in probe_view
    probe = row[row.index("private struct TopProbe: UIViewRepresentable {"):]
    assert "guard let window else { return }" in probe
    assert "measured?(Sample(top: convert(bounds, to: nil).minY, windowTop: window.safeAreaInsets.top," in probe
    # when it reads: UIKit's three moments, a presentation the app made going, the scene in front, SwiftUI's asks
    for moment in ("override func didMoveToWindow() {\n            super.didMoveToWindow()\n            soon(\"window\")",
                   "override func layoutSubviews() {\n            super.layoutSubviews()\n            soon(\"layout\")",
                   "override func safeAreaInsetsDidChange() {\n            super.safeAreaInsetsDidChange()\n"
                   "            soon(\"safe area\")",
                   "selector: #selector(presentationGone), name: .appPresentationGone, object: nil)",
                   "selector: #selector(sceneActive), name: UIScene.didActivateNotification, object: nil)",
                   "        probe.measured = measured\n        eyes.probe = probe\n        return probe\n"):
        assert moment in probe, moment
    # SwiftUI asks too - the row appearing (the tabs back from under the cover), its geometry changing (at once, in its
    # action, and once UIKit has laid it out) - and its own numbers are Debug's alone, never the room's
    assert 'swiftUI = measured\n            eyes.probe?.now("geometry")\n            eyes.probe?.soon("geometry")' in body
    # never a guessed key window, nor SwiftUI's global space, for the room
    assert "KeyWindow" not in top and "isKeyWindow" not in top and ".windows" not in top
    clearance = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "TopClearance.swift").read_text(encoding="utf-8")
    assert "TopClearance.kept(" not in top and "func kept(" not in clearance
    take = row[row.index("private func take("):row.index("/// LibraryTop's eyes in UIKit")]
    assert ("TopClearance.room(kept: Double(clearance), top: Double(sample.top), windowTop: Double(sample.windowTop),\n"
            "                                     presented: sample.presented)") in take
    assert "global" not in take
    # no measuring under a presentation: the window's root view controller presenting (or the row's own controller);
    # and every sheet and cover says it has gone once it has
    assert "if window.rootViewController?.presentedViewController != nil { return true }" in probe
    assert "let presented = presentedOver(window)" in probe
    # (20 Nov, James: "well now the whole screen is too low", "It's after I leave the player") read as the tabs came
    # back from under Now Playing, the row was 117 points above its window's edge, came down twice the inset, then
    # settled with nothing telling the probe. So a row above the edge keeps its room (Core's `settled`, no `most`), and
    # every ask is followed by reads again - 12, a quarter second apart - whatever is presented; a read again doesn't
    # start them afresh, an ask does
    assert "if presented || !settled(top: top) { return kept.isFinite ? max(kept, 0) : 0 }" in clearance
    assert "public static func settled(top: Double) -> Bool {\n        top.isFinite && top >= -edge\n" in clearance
    assert "public static let edge = 1.0\n" in clearance and "func most(" not in clearance
    assert "return max(windowTop - max(top, 0), 0)" in clearance
    assert "private static let gap: TimeInterval = 0.25\n" in probe and "private static let tries = 12\n" in probe
    assert "presented: presented, cause: cause))\n            readAgain()\n        }" in probe
    assert "if presented { readAgain() }" not in probe
    assert "func now(_ cause: String) {\n            follow(cause)\n            read(cause)\n" in probe
    assert "func soon(_ cause: String) {\n            follow(cause)\n            schedule(cause)\n" in probe
    assert "left = Self.tries\n            asked = cause\n" in probe
    again = probe[probe.index("private func readAgain() {"):probe.index("private func presentedOver(")]
    assert "guard !againWaiting, left > 0 else { return }" in again and "left -= 1" in again
    assert 'schedule("\\(asked), again")' in again and "soon(" not in again and "follow(" not in again
    presenting = (APP / "Shared" / "Presenting.swift").read_text(encoding="utf-8")
    assert presenting.count("onDismiss: gone(onDismiss)") == 4 and "onDismiss: onDismiss)" not in presenting
    assert "onDismiss?()\n        NotificationCenter.default.post(name: .appPresentationGone, object: nil)" in presenting
    # the last reading is Debug's
    assert "if debug.libraryTop != reading { debug.libraryTop = reading }" in take
    assert "var libraryTop: TopClearance.Reading?" in (APP / "Models" / "DebugModel.swift").read_text(encoding="utf-8")
    debug_view = (APP / "You" / "DebugView.swift").read_text(encoding="utf-8")
    assert 'LabeledContent("Top") {\n                Text(model.libraryTop?.line ?? "Not measured yet")' in debug_view
    assert "KeyWindow.safeArea.bottom" in (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    sources = {path.relative_to(APP).as_posix(): path.read_text(encoding="utf-8") for path in APP.rglob("*.swift")}
    assert [name for name, text in sources.items() if ".toolbar(.hidden, for: .navigationBar)" in text] == [
        "Library/LibraryView.swift"]
    # what reaches the top edge (any ignore but the bottom's alone): the Library top's fill, RootView's background, Now
    # Playing's black and its blurred cover, and (review) MainTabs's clear reader of the screen's layout - a new one must
    # be a fill too, or keep its content in the safe area
    reaching = {}
    for name, text in sources.items():
        for line in text.splitlines():
            if ".ignoresSafeArea(" in line and "edges: .bottom" not in line:
                reaching[name] = reaching.get(name, 0) + 1
    # The cover full screen's two (notes/ios.md "The cover, full screen"): its black ground, a fill, and the zoomed
    # picture, edge to edge as Photos' is, with the status bar hidden - its ✕ keeps to the safe area.
    # Edit album's cover full screen, from Compare covers (Phase 8, slice 1): its black ground alone, a fill - the
    # picture and its Close keep to the safe area.
    # (The Mac redesign, R1) The Mac's desktop frame, laid under the window's title bar for its title strip - the Mac's
    # alone (the iPhone draws MainTabs, never the frame), and its content below the strip.
    assert reaching == {"Library/LibraryTop.swift": 1, "Root/RootView.swift": 1, "Player/NowPlayingView.swift": 2,
                        "Root/MainTabs.swift": 1, "Player/CoverViewer.swift": 2, "Edit/ReleasePage.swift": 1,
                        "Root/DesktopFrame.swift": 1}
    full = sources["Edit/ReleasePage.swift"]
    full = full[full.index("struct FullCoverView"):]
    assert "ZStack {\n            Color.black.ignoresSafeArea()\n" in full and full.count("ignoresSafeArea") == 1
    viewer = sources["Player/CoverViewer.swift"]
    assert "Palette.page\n                .opacity(ground)\n                .ignoresSafeArea()\n" in viewer
    assert "onDrag: held, onClose: close)\n                .ignoresSafeArea()\n" in viewer
    assert ".statusBarHidden(true)" in viewer
    close = viewer[viewer.index("CoverCloseButton(action: close)\n"):viewer.index(".statusBarHidden(true)")]
    assert "ignoresSafeArea" not in close
    tabs = sources["Root/MainTabs.swift"]
    assert "Color.clear\n                .ignoresSafeArea()\n                .onGeometryChange(" in tabs
    now_playing = sources["Player/NowPlayingView.swift"]
    assert "Color.black.ignoresSafeArea()" in now_playing
    backdrop = now_playing[now_playing.index("private struct Backdrop"):]
    assert ".ignoresSafeArea()" in backdrop and "CoverImage(" in backdrop
    assert ".background(Color(.systemBackground).ignoresSafeArea())" in sources["Root/RootView.swift"]


def test_the_tab_bar_comes_down_into_the_home_indicators_room():
    # 15 Nov, James: "there might be a little too much space below the bottom tab bar". The bar runs to the screen's edge
    # itself, its play bar and tabs padded off it by Core's TabBarFoot (20 on a Face ID iPhone, where they stood on the
    # home indicator's whole 34; 6 with a Home button); the pages' room is the bar over the home indicator's, so nothing
    # sits under it; the keyboard is as it was.
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    foot = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "TabBarFoot.swift").read_text(encoding="utf-8")
    assert "public static let drop = 14.0\n" in foot and "public static let least = 6.0\n" in foot
    bar = tabs[tabs.index("struct AppTabBar"):tabs.index("private struct AppTabButton")]
    body = bar[bar.index("var body: some View {"):]
    order = [body.index(part) for part in ("measured(height)", ".padding(.bottom, CGFloat(TabBarFoot.below(home: home)))",
                                           ".background {", ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)",
                                           ".ignoresSafeArea(.container, edges: .bottom)\n    }")]
    assert order == sorted(order)
    assert ".environment(\\.tabBarRoom, keyboardUp ? 0 : CGFloat(TabBarFoot.room(content: barHeight, home: home)))" in tabs
    assert "AppTabBar(home: home)" in tabs and "barHeight = height" in tabs
    # the window's bottom safe area, never a view's (which counts the keyboard): KeyWindow's. (18 Nov) The app's own
    # window: the scene's key window when it is one of the app's, the scene in front first, else the first of the app's
    # that shows - never iOS's keyboard or text effects windows over it (above a normal window's level), and never
    # `windows.first` whatever it is
    assert "KeyWindow.safeArea.bottom" in tabs
    key_window = (APP / "Shared" / "KeyWindow.swift").read_text(encoding="utf-8")
    assert "if let key = scene.keyWindow, isApps(key) { return key }" in key_window
    assert "scene.windows.first(where: { (window: UIWindow) -> Bool in isApps(window) })" in key_window
    assert "window.windowLevel == .normal && !window.isHidden && window.rootViewController != nil" in key_window
    assert "case .foregroundActive: return 0" in key_window and "?? windows.first" not in key_window
    assert "window?.safeAreaInsets ?? .zero" in key_window
    # (review) read again whenever SwiftUI lays the screen out anew, never only when the body happens to be
    assert "@State private var home: CGFloat = 0" in tabs and tabs.count("home = Self.windowHome()") == 2
    assert ".onGeometryChange(for: [CGFloat].self)" in tabs
    assert "[proxy.size.width, proxy.size.height, proxy.safeAreaInsets.bottom]" in tabs
    # the keyboard: the bar under it, the pages making no room meanwhile
    assert ".ignoresSafeArea(.keyboard, edges: .bottom)" in tabs and "keyboardUp = true" in tabs


def test_the_transport_and_the_librarys_icon_have_actual_corners():
    # 15 Nov, James: "Actual corners. The pause, skip buttons, etc. ... Even the library icon should be a bit more square."
    # SF Symbols' play, pause, forward and backward are rounded, so each place draws SharpGlyph's sharp-cornered shapes
    # instead (Core: measured from the symbols, at their weight - SharpGlyphTests), in the frame of the symbol it
    # replaced (hidden, as the template); the Library's tab its squared stack. No transport symbol is named anywhere in
    # the app now - only Core's templates; the other tabs keep their SF Symbols.
    core = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "SharpGlyph.swift").read_text(encoding="utf-8")
    for template in ('"play.fill"', '"pause.fill"', '"forward.fill"', '"backward.fill"', '"square.stack.fill"'):
        assert template in core
    glyphs = (APP / "Shared" / "SharpGlyphs.swift").read_text(encoding="utf-8")
    assert "Image(systemName: glyph.template)\n            .hidden()" in glyphs
    assert ".animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: playing)" in glyphs
    left = [f"{name}:{number}" for name, number, code in app_code()
            if re.search(r'"(play|pause|forward|backward)(\.fill|\.end\.fill|\.end)?"', code)]
    assert not left, left
    places = {"Player/MiniPlayerView.swift": "PlayPauseGlyph(playing: player.isPlaying)",
              "Player/NowPlayingView.swift": "PlayPauseGlyph(playing: player.isPlaying)",
              "Album/AlbumHero.swift": "SharpSymbol(.play)", "Requests/RequestCards.swift": "SharpSymbol(.play)",
              "Search/SearchScreen.swift": "SharpSymbol(.play)", "You/DebugView.swift": "PlayPauseGlyph("}
    for name, drawn in places.items():
        assert drawn in (APP / name).read_text(encoding="utf-8"), name
    now_playing = (APP / "Player" / "NowPlayingView.swift").read_text(encoding="utf-8")
    assert "SharpSymbol(.previous)" in now_playing and "SharpSymbol(.next)" in now_playing
    # the Large Content Viewer keeps an image of each
    mini = (APP / "Player" / "MiniPlayerView.swift").read_text(encoding="utf-8")
    assert "Image(uiImage: (player.isPlaying ? SharpGlyph.pause : SharpGlyph.play).image)" in mini
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    button = tabs[tabs.index("private struct AppTabButton"):]
    assert "SharpSymbol(sharp)" in button and ".symbolVariant(.fill)" in button and "Image(uiImage: sharp.image)" in button
    routes = (APP / "Shared" / "Routes.swift").read_text(encoding="utf-8")
    assert "case .library: return .library" in routes


# The app's fonts (25 Nov - notes/ios.md "The app's fonts: Libre Franklin and Courier Prime (2026-11-25)"): James chose
# "libre franklin", then "Adopt it", in place of Noto Sans (15 Nov, the web's) and Noto Sans Mono (24 Nov, R1's "Bundle
# Noto Sans Mono"). Libre Franklin's four faces are its variable font pinned at 400, 500, 600 and 700, Courier Prime's two
# its own files (ios/scripts/make-fonts.py, from ios/scripts/fonts), named by Info.plist's UIAppFonts, and every text
# style the app sets is ios/App/Shared/Typeface.swift's - nothing in ios/App names a system text font of its own. A
# symbol drawn alone keeps iOS's own font (Typeface.symbol), which is how an SF Symbol is sized, and data a slice hasn't
# redrawn the system's monospace (Typeface.mono).

TYPEFACE = APP / "Shared" / "Typeface.swift"
FONTS = APP / "Fonts"
SOURCES = REPO / "ios" / "scripts" / "fonts"
MAKE_FONTS = REPO / "ios" / "scripts" / "make-fonts.py"
#? the files as downloaded (google/fonts at 6ebe737e44fd64ee736bbc6feed6136a6dbfd222 - ios/scripts/fonts/README.md),
#? each to its hash: a source that changes is a decision, not an accident
SOURCE_HASHES = {
    "librefranklin/LibreFranklin[wght].ttf": "2329f394b10ed1c71107df20fddc11e2bb1b68c1ecbb385f975b36fd64a971f8",
    "librefranklin/OFL.txt": "2710268527181a27b8e938617551bae29e714e6525247be6679bf897a9942a60",
    "courierprime/CourierPrime-Regular.ttf": "72f793376f8e2841656bf21d77a5de010f2929bd6956a22ee848ad0c7eb978af",
    "courierprime/CourierPrime-Bold.ttf": "ff1f38786c849d1c41fa8e447960abdb2bd75fdfb0cfcdeb524fad65a5af3638",
    "courierprime/OFL.txt": "9a755af092b494944c99f471be6fddd19b006a448fefdc4717e4ee0aa09a97b0",
}
WORDS_FACES = {"LibreFranklin-Regular": 400, "LibreFranklin-Medium": 500, "LibreFranklin-SemiBold": 600,
               "LibreFranklin-Bold": 700}
READOUT_FACES = {"CourierPrime-Regular": 400, "CourierPrime-Bold": 700}
INFO_PLIST = REPO / "ios" / "Config" / "Info.plist"
INFO_MAC_PLIST = REPO / "ios" / "Config" / "Info-Mac.plist"
STYLES = ("largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline", "footnote", "caption",
          "caption2")
# each text style's size at iOS's standard text size (Large) - what SwiftUI's .body and the rest were
IOS_SIZES = {"largeTitle": 34, "title": 28, "title2": 22, "title3": 20, "headline": 17, "body": 17, "callout": 16,
             "subheadline": 15, "footnote": 13, "caption": 12, "caption2": 11}


def sfnt_tables(data: bytes) -> dict:
    count = int.from_bytes(data[4:6], "big")
    tables = {}
    for index in range(count):
        record = data[12 + 16 * index:28 + 16 * index]
        tables[record[:4].decode("latin-1")] = int.from_bytes(record[8:12], "big")
    return tables


def font_names(path: Path) -> dict:
    # the name table's Windows (3, 1) strings, by name id
    data = path.read_bytes()
    start = sfnt_tables(data)["name"]
    count = int.from_bytes(data[start + 2:start + 4], "big")
    strings = start + int.from_bytes(data[start + 4:start + 6], "big")
    names = {}
    for index in range(count):
        record = data[start + 6 + 12 * index:start + 18 + 12 * index]
        platform, encoding, _, name_id, length, offset = (int.from_bytes(record[i:i + 2], "big") for i in range(0, 12, 2))
        if (platform, encoding) == (3, 1):
            names[name_id] = data[strings + offset:strings + offset + length].decode("utf-16-be")
    return names


def font_characters(path: Path) -> set:
    # the code points the (3, 1) cmap - a format 4 table - maps to a glyph
    data = path.read_bytes()
    start = sfnt_tables(data)["cmap"]
    for index in range(int.from_bytes(data[start + 2:start + 4], "big")):
        record = data[start + 4 + 8 * index:start + 12 + 8 * index]
        if (int.from_bytes(record[0:2], "big"), int.from_bytes(record[2:4], "big")) != (3, 1):
            continue
        table = start + int.from_bytes(record[4:8], "big")
        assert int.from_bytes(data[table:table + 2], "big") == 4
        segments = int.from_bytes(data[table + 6:table + 8], "big") // 2

        def column(base: int) -> list:
            return [int.from_bytes(data[base + 2 * i:base + 2 * i + 2], "big") for i in range(segments)]

        ends, starts = column(table + 14), column(table + 16 + 2 * segments)
        deltas, offsets = column(table + 16 + 4 * segments), column(table + 16 + 6 * segments)
        found = set()
        for i in range(segments):
            for code in range(starts[i], ends[i] + 1):
                if code == 0xFFFF:
                    continue
                if offsets[i] == 0:
                    glyph = (code + deltas[i]) & 0xFFFF
                else:
                    at = table + 16 + 6 * segments + 2 * i + offsets[i] + 2 * (code - starts[i])
                    glyph = int.from_bytes(data[at:at + 2], "big")
                    glyph = (glyph + deltas[i]) & 0xFFFF if glyph else 0
                if glyph:
                    found.add(code)
        return found
    raise AssertionError(f"{path.name} has no (3, 1) cmap")


def os2_weight(path: Path) -> int:
    # the OS/2 table's usWeightClass: its third field, after its version and xAvgCharWidth
    data = path.read_bytes()
    start = sfnt_tables(data)["OS/2"]
    return int.from_bytes(data[start + 4:start + 6], "big")


def sha256(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_the_sources_are_the_files_as_downloaded():
    found = sorted(str(path.relative_to(SOURCES)) for path in SOURCES.rglob("*")
                   if path.is_file() and not path.name.startswith(".") and path.name != "README.md")
    assert found == sorted(SOURCE_HASHES)
    readme = (SOURCES / "README.md").read_text(encoding="utf-8")
    assert "github.com/google/fonts" in readme and "6ebe737e44fd64ee736bbc6feed6136a6dbfd222" in readme
    for name, digest in SOURCE_HASHES.items():
        assert sha256(SOURCES / name) == digest, name
        # and the README's table says the same
        assert f"| {name} | {(SOURCES / name).stat().st_size} | {digest} |" in readme, name
    # each family its own licence, its own copyright line
    libre = (SOURCES / "librefranklin" / "OFL.txt").read_text(encoding="utf-8")
    courier = (SOURCES / "courierprime" / "OFL.txt").read_text(encoding="utf-8")
    assert libre.startswith("Copyright 2020 The Libre Franklin Project Authors")
    assert courier.startswith("Copyright 2015 The Courier Prime Project Authors")
    for licence in (libre, courier):
        assert "SIL OPEN FONT LICENSE Version 1.1" in licence


def test_the_fonts_are_libre_franklin_and_courier_prime():
    import plistlib
    faces = sorted([*WORDS_FACES, *READOUT_FACES])
    fonts = sorted(f"{face}.ttf" for face in faces)
    # the folder is exactly what make-fonts.py makes: six faces and each family's licence, under the family's name -
    # every file in App/ lands at the bundle's root, so two OFL.txt would collide (check_project.py)
    files = sorted(path.name for path in FONTS.iterdir() if not path.name.startswith("."))
    assert files == sorted(fonts + ["CourierPrime-OFL.txt", "LibreFranklin-OFL.txt"])
    # Info.plist names each (the synchronized folder copies them to the bundle's root, where UIAppFonts looks) - and
    # Info-Mac.plist the same (check_project.py holds the two plists in step)
    for plist in (INFO_PLIST, INFO_MAC_PLIST):
        assert sorted(plistlib.loads(plist.read_bytes())["UIAppFonts"]) == fonts, plist.name
    # the licences and Courier Prime's two faces, byte for byte as downloaded
    assert (FONTS / "LibreFranklin-OFL.txt").read_bytes() == (SOURCES / "librefranklin" / "OFL.txt").read_bytes()
    assert (FONTS / "CourierPrime-OFL.txt").read_bytes() == (SOURCES / "courierprime" / "OFL.txt").read_bytes()
    for face in READOUT_FACES:
        assert (FONTS / f"{face}.ttf").read_bytes() == (SOURCES / "courierprime" / f"{face}.ttf").read_bytes(), face
    source = TYPEFACE.read_text(encoding="utf-8")
    # the words: of the family Typeface asks for, under the PostScript names Typeface.Face gives UIKit, each at the
    # weight make-fonts.py pins it at, with every character of the variable font it was pinned from
    assert re.search(r'static let family = "([^"]+)"', source).group(1) == "Libre Franklin"
    assert sorted(re.findall(r'case \w+ = "(LibreFranklin-\w+)"', source)) == sorted(WORDS_FACES)
    script = MAKE_FONTS.read_text(encoding="utf-8")
    words = script[script.index("\nWORDS = ("):script.index("\nREADOUTS = (")]
    pinned = {f"LibreFranklin-{style}": int(weight) for weight, style in re.findall(r'(\d{3}): "(\w+)"', words)}
    assert pinned == WORDS_FACES
    whole = font_characters(SOURCES / "librefranklin" / "LibreFranklin[wght].ttf")
    assert len(whole) > 900
    for face, weight in WORDS_FACES.items():
        table = font_names(FONTS / f"{face}.ttf")
        assert table.get(16, table[1]) == "Libre Franklin", face
        assert table[6] == face
        assert os2_weight(FONTS / f"{face}.ttf") == weight, face
        assert font_characters(FONTS / f"{face}.ttf") == whole, face
    # the readouts: of the family Typeface.Mac asks for, under Typeface.Mac.MonoFace's names - Regular and Bold, no more
    assert re.search(r'static let monoFamily = "([^"]+)"', source).group(1) == "Courier Prime"
    assert sorted(re.findall(r'case \w+ = "(CourierPrime-\w+)"', source)) == sorted(READOUT_FACES)
    for face, weight in READOUT_FACES.items():
        table = font_names(FONTS / f"{face}.ttf")
        assert table.get(16, table[1]) == "Courier Prime", face
        assert table[6] == face and os2_weight(FONTS / f"{face}.ttf") == weight, face
    # nothing of Noto is left in the app's fonts nor named by its code
    assert not [path.name for path in FONTS.iterdir() if "Noto" in path.name]
    assert not [f"{name}:{number}" for name, number, code in app_code() if "Noto" in code]


#? (25 Nov, narrowed after review) The readouts that change as you watch them. A number is in the readout face,
#? Courier Prime, where the drawings set it in mono, or where it changes continuously while you watch it and stands on
#? its own - a clock, a speed, a value being dragged or held, a size growing as a download comes: Libre Franklin has no
#? tabular figures (`.monospacedDigit()` does nothing in it), so in the words its figures would shift as it counts. A
#? step count inside a sentence ("Downloading - 4 of 12 songs", "30 of 140", a place in the queue) stays in the words,
#? as drawn - its small shift as a digit changes accepted - and so do the Mac Queue's time left (once a minute; R3b's
#? review set it in the words), Settings > Downloads' amount, line and fetching counts, and an album footer's download
#? line. Each: (file, what draws it, the departure it is from the drawings - a readout they set in the words' face or
#? don't draw - or None). notes/ios.md lists them.
TICKING = [
    # the players' clocks: the phone's scrubber, the mini player's held time, the Mac bar's
    ("Player/ScrubberView.swift", "            Text(remaining)\n        }\n        .font(Typeface.readout(.caption))",
     None),
    ("Player/MiniPlayerView.swift", "        Text(words)\n            .font(Typeface.Phone.mono(.extraSmall))", None),
    ("Player/PlayerBar.swift",
     "            Text(PlayerWords.remaining(shown: shown, length: length))\n        }\n        .font(Typeface.Mac.mono(.label))",
     None),
    # the Queue's time left on the phone, as iQueue draws it (the Mac's is in the words, as drawn)
    ("UpNext/UpNextScreen.swift",
     ".font(Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.mono(.extraSmall))", None),
    # Requests: a download's progress and its speed, the page's speed in the status bar (the drawing's words)
    ("Mac/Requests/MacRequestsPage.swift", "Text(row.progressWords ?? \"\")\n                    .font(Typeface.Mac.mono(.label))",
     None),
    ("Mac/Requests/MacRequestsPage.swift",
     "return Text(RequestFilter.speedText(row))\n            .font(Typeface.Mac.mono(.small))", None),
    ("Mac/Requests/MacRequestsPage.swift", "readouts: [RequestWords.speed(RequestFilter.speed(board))]",
     "the Mac status bar's speed"),
    ("Mac/Components/MacStatusBar.swift",
     "if items.readouts.contains(fact) {\n                    Text(fact).font(Typeface.Mac.mono(.label))",
     "the Mac status bar's speed"),
    ("Requests/RequestCards.swift", "Text(row.data ?? \" \")\n                                .font(Typeface.Phone.mono(.extraSmall))",
     None),
    # what this device holds, growing as songs come: You's Downloads row (the drawings have no figure there)
    ("You/DownloadsRow.swift", "Text(Bytes.words(downloads.bytesHere))\n                            .font(Typeface.readout(.body))",
     "You's Downloads value"),
    # Library care's facts: the scan's age
    ("Manage/LibraryCareScreen.swift",
     "Text(care.facts(now: context.date.timeIntervalSince1970 * 1000))\n                    .font(Typeface.readout(.footnote))",
     None),
    # the EQ's values under a finger: a held slider's, a stepper's (the accessibility sizes' row, not drawn), the
    # selected handle's, the hand preamp's, a filter's row - and deadwax's own preamp, which moves as a band is dragged
    # (iEQ draws it in mono)
    ("EQ/EQSliders.swift", ".font(EQSliders.phone ? Typeface.Phone.mono(.extraSmall).weight(.semibold)\n"
                           "                                          : Typeface.readout(.caption).weight(.semibold))", None),
    ("EQ/EQSliders.swift", "Text(EQWords.held(gain))\n                .font(Typeface.readout(.body))", "the EQ stepper's value"),
    ("EQ/EQCurveView.swift", "Text(text ?? \" \")\n            .font(Typeface.readout(.caption))", None),
    ("EQ/EQScreen.swift", "Text(EQWords.Preamp.value(hand))\n                            .font(Typeface.readout(.body))", None),
    ("EQ/EQScreen.swift", "Text(EQWords.Preamp.value(hand))\n                            .font(Typeface.Phone.mono(.small))",
     None),
    ("EQ/EQScreen.swift",
     "Text(EQWords.Preamp.value(setting.on ? drawing.preamp : automaticPreamp(output, setting)))\n"
     "                        .font(Typeface.readout(.body))", None),
    ("EQ/EQScreen.swift",
     "value: EQWords.Preamp.value(setting.on ? drawing.preamp : automaticPreamp(output, setting)),\n"
     "                        mono: true)", None),
    ("EQ/EQScreen.swift", "Text(EQWords.Advanced.detail(f))\n                        .font(Typeface.readout(.footnote))", None),
    ("EQ/EQScreen.swift", "Text(EQWords.Advanced.detail(f))\n                        .font(Typeface.Phone.mono(.extraSmall))",
     None),
    # Debug's measurements (not drawn): every one, below
    ("You/DebugView.swift", "Text(row.value).font(Typeface.readout(.footnote))", "Debug's measurements"),
]
#? (a readout face, or what chooses one: a status bar fact named a readout, a fact's row set in mono)
READOUT_FONT = re.compile(r"Typeface\.readout\(|Typeface\.(Mac|Phone|Look)\.mono\(|readouts: |mono: true")
#? the four departures from the drawings, for James
DEPARTURES = {"the Mac status bar's speed", "You's Downloads value", "the EQ stepper's value", "Debug's measurements"}
#? what went back to the words, as drawn, after review (25 Nov): none of it is in the readout face again
BACK_IN_WORDS = [
    ("UpNext/UpNextScreen.swift", "Typeface.Look.mono(.chip)"),
    ("Downloads/DownloadsScreen.swift", "Typeface.readout("),
    ("Downloads/DownloadsScreen.swift", "Typeface.Phone.mono("),
    ("Album/AlbumView.swift", "Typeface.Phone.mono("),
]


def test_every_number_that_ticks_is_in_the_readout_face():
    for name, drawn, _ in TICKING:
        text = (APP / name).read_text(encoding="utf-8")
        assert drawn in text, f"{name}: {drawn!r}"
        assert READOUT_FONT.search(drawn), drawn
    # the departures, said: those the drawings set in the words' face, or don't draw
    assert {departs for _, _, departs in TICKING if departs} == DEPARTURES
    # the narrowed rule: a step count in a sentence, the Mac's time left and an album's footer stay in the words
    for name, face in BACK_IN_WORDS:
        assert face not in "\n".join(code for file, _, code in app_code() if file == name), f"{name}: {face}"
    # PhoneKV's `mono` is the readout face at the small 13, as `.mono.s` is
    kv = (APP / "Phone" / "PhoneCard.swift").read_text(encoding="utf-8")
    kv = kv[kv.index("struct PhoneKV: View {"):]
    kv = kv[:kv.index("\n}\n")]
    assert "var mono = false" in kv
    assert "if mono {\n                Text(value)\n                    .font(Typeface.Phone.mono(.small))" in kv
    # Debug's measurements, every one (`.monospacedDigit()` held them still in Noto Sans)
    debug = (APP / "You" / "DebugView.swift").read_text(encoding="utf-8")
    assert debug.count(".font(Typeface.readout(.footnote))") == 18
    # and nothing in the app asks `.monospacedDigit()` of a face where it does nothing: Libre Franklin has no tabular
    # figures, Courier Prime's are all one width, and every Text takes one or the other (DeadwaxApp's root font)
    assert not [f"{name}:{number}" for name, number, code in app_code() if ".monospacedDigit()" in code]
    # the readout at a text style: Courier Prime at the style's size, scaled as the style scales, as the words are
    source = TYPEFACE.read_text(encoding="utf-8")
    readout = source[source.index("static func readout(_ style: Font.TextStyle) -> Font {"):]
    readout = readout[:readout.index("\n    }\n") + 6]
    sizes = dict(re.findall(r"case \.(\w+): size = (\d+)", readout))
    assert {style: int(size) for style, size in sizes.items()} == IOS_SIZES
    assert "return .custom(Mac.monoFamily, size: size, relativeTo: style)" in readout


def _swift():
    import importlib.util
    spec = importlib.util.spec_from_file_location("_palette_ios_swift", Path(__file__).resolve().parent / "ios_swift.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


#? a readout's face, named
READOUT_CALL = re.compile(r"Typeface\.(?:readout|Mac\.mono|Phone\.mono|Look\.mono)\(")
MEDIUM = re.compile(r"\.medium\b")
FONT_WEIGHT_MEDIUM = re.compile(r"\.fontWeight\([^()]*\.medium\b")


def readout_scopes(code: str) -> list[tuple[int, str]]:
    """Every readout's scope in one file's code: (where its face is named, the code it is in force over) - the whole view
    its `.font(...)` is set on, that view's every modifier before and after it, the font's own; a Font property's own
    expression and every view that takes it; and the modifiers of every block around it (a container's `.fontWeight`)."""
    swift = _swift()
    scopes = []
    aliases = set()
    for found in READOUT_CALL.finditer(code):
        call = swift.opener_before(code, found.start())
        if call >= 0 and code[call] == "(" and code[:call].rstrip().endswith(".font"):
            link = code[:call].rstrip().rfind(".font")
            start = swift.expression_start(code, link)
            end = swift.chain_end(code, swift.closer(code, call) + 1)
            scope = code[start:end]
        else:
            # a Font made apart (`var labelFont: Font { ... }`): its own expression, and every `.font` that takes it
            block = swift.opener_before(code, found.start(), "{")
            scope = code[block:swift.closer(code, block) + 1] if block >= 0 else code[found.start():found.end()]
            named = re.search(r"var (\w+): Font\s*$", code[:block]) if block >= 0 else None
            if named:
                aliases.add(named.group(1))
        around = [code[close + 1:swift.chain_end(code, close + 1)] for _, _, close in swift.blocks_around(code, found.start())]
        scopes.append((found.start(), scope + "\n" + "\n".join(part for part in around if FONT_WEIGHT_MEDIUM.search(part))))
    for alias in aliases:
        for found in re.finditer(rf"\.font\((?:\w+\.)?{alias}\)", code):
            call = found.start() + len(".font")
            start = swift.expression_start(code, found.start())
            end = swift.chain_end(code, swift.closer(code, call) + 1)
            scopes.append((found.start(), code[start:end]))
    return scopes


def test_no_readout_asks_for_medium():
    # Courier Prime has no Medium: asked for one, CoreText draws its Bold (measured, 25 Nov), not the Regular the
    # drawings' browser draws at 500 - so nothing in force over a readout asks for Medium: not its font's own
    # `.weight(...)` (a ternary's either side), not a `.fontWeight(...)` anywhere in its view's chain, before its
    # `.font` or after, nor one on a block around it - and MonoFace has none to name
    swift = _swift()
    asks = []
    for path in sorted(APP.rglob("*.swift")):
        name = str(path.relative_to(APP))
        if name == "Shared/Typeface.swift":
            continue
        code = swift.code_only(path.read_text(encoding="utf-8"))
        for at, scope in readout_scopes(code):
            if MEDIUM.search(scope):
                asks.append(f"{name}:{code.count(chr(10), 0, at) + 1}")
    assert not asks, asks
    # the rule, rehearsed on what review found passed the line-at-a-time check
    def caught(swift_code: str) -> bool:
        code = swift.code_only(swift_code)
        return any(MEDIUM.search(scope) for _, scope in readout_scopes(code))
    assert caught("        Text(text ?? \" \")\n            .font(Typeface.readout(.caption))\n            .fontWeight(.medium)\n")
    assert caught("        Text(x)\n            .font(Typeface.Mac.mono(.label).weight(held ? .medium : .bold))\n")
    assert caught("        Text(x)\n            .fontWeight(.medium)\n            .lineLimit(1)\n            .font(Typeface.Phone.mono(.small))\n")
    assert caught("        HStack {\n            Text(a)\n            Text(b)\n        }\n        .font(Typeface.readout(.body))\n"
                  "        .fontWeight(.medium)\n")
    assert caught("        VStack {\n            Text(a).font(Typeface.readout(.body))\n        }\n        .fontWeight(.medium)\n")
    assert caught("    var labelFont: Font { Typeface.Phone.mono(.small) }\n    var body: some View {\n"
                  "        Text(a).font(labelFont).fontWeight(.medium)\n    }\n")
    assert not caught("        Text(x)\n            .font(Typeface.Mac.text(.label).weight(.medium))\n")
    assert not caught("        Text(x)\n            .font(Typeface.readout(.body).weight(.semibold))\n"
                      "        Text(y)\n            .font(Typeface.Mac.text(.label).weight(.medium))\n")
    source = TYPEFACE.read_text(encoding="utf-8")
    mono = source[source.index("enum MonoFace: String, CaseIterable {"):]
    assert "medium" not in mono[:mono.index("}")]


def test_each_face_is_named_for_its_own_weight():
    # Typeface.Face and Mac.MonoFace, case by case: each case's PostScript name is the file of that weight - its name
    # table's, its OS/2 weight's - so UIKit's `.semibold` (a bar's title, a chosen segment) is SemiBold, not Bold
    source = TYPEFACE.read_text(encoding="utf-8")
    face = source[source.index("enum Face: String, CaseIterable {"):]
    face = face[:face.index("}")]
    mono = source[source.index("enum MonoFace: String, CaseIterable {"):]
    mono = mono[:mono.index("}")]
    weights = {"regular": 400, "medium": 500, "semibold": 600, "bold": 700}
    words = dict(re.findall(r'case (\w+) = "([\w-]+)"', face))
    readouts = dict(re.findall(r'case (\w+) = "([\w-]+)"', mono))
    assert words == {"regular": "LibreFranklin-Regular", "medium": "LibreFranklin-Medium",
                     "semibold": "LibreFranklin-SemiBold", "bold": "LibreFranklin-Bold"}
    assert readouts == {"regular": "CourierPrime-Regular", "bold": "CourierPrime-Bold"}
    for case, postscript in [*words.items(), *readouts.items()]:
        path = FONTS / f"{postscript}.ttf"
        assert font_names(path)[6] == postscript, case
        assert os2_weight(path) == weights[case], case
    # and UIKit asks by case: the bars' titles and a chosen segment SemiBold, the large title Bold, the rest Regular
    assert "uiFont(.bold, size: 34, style: .largeTitle, capped: false)" in source
    assert "uiFont(.semibold, size: 17, style: .headline)" in source
    assert "uiFont(.semibold, size: 13, style: .footnote)" in source


def test_every_text_style_is_libre_franklin_scaled_as_ios_scales_it():
    source = TYPEFACE.read_text(encoding="utf-8")
    for style in STYLES:
        found = re.search(rf"static let {style} = text\(([0-9]+), \.([a-zA-Z0-9]+)\)", source)
        assert found, f"Typeface has no {style}"
        # the size iOS gives the style at the standard text size, relative to that same style, so it grows as it did
        assert (int(found.group(1)), found.group(2)) == (IOS_SIZES[style], style)
    assert ".custom(family, size: size, relativeTo: style)" in source
    assert "static let headline = text(17, .headline).weight(.semibold)" in source
    app = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    # the app's words default to it, under every Text and control that sets none, and UIKit's bars and fields are
    # given the faces before any is made
    assert ".font(Typeface.body)" in app and "Typeface.configureUIKit()" in app
    for face in ("largeTitleTextAttributes", "titleTextAttributes", "UISearchTextField.appearance().font",
                 "UIBarButtonItem.appearance().setTitleTextAttributes", "UISegmentedControl.appearance()"):
        assert face in source, face
    # after review: UIKit's fonts stop growing at xxxLarge, the tab bar's cap - all but the large title, as iOS's grows
    assert "scaledFont(for: font, maximumPointSize: cap(size, style))" in source
    assert "UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)" in source
    assert source.count("capped: false)") == 1
    assert "uiFont(.bold, size: 34, style: .largeTitle, capped: false)" in source
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in tabs


def test_no_system_text_font_is_left_in_the_app():
    styles = "|".join(sorted(STYLES, key=len, reverse=True))
    leading = re.compile(rf"(?<![\w)\]])\.({styles})\b")
    left = []
    for name, number, code in app_code():
        if name == "Shared/Typeface.swift":
            continue
        where = f"{name}:{number}"
        # a symbol drawn alone and data keep the system's faces - but only through Typeface, by name - and a readout
        # names its text style only through Typeface.readout (Courier Prime at that style)
        plain = re.sub(r"Typeface\.(symbol|mono|readout)\([^()]*\)", "Typeface.kept", code)
        for found in re.finditer(r"\.font\(", plain):
            depth, end = 0, len(plain)
            for end in range(found.start() + len(".font"), len(plain)):
                depth += {"(": 1, ")": -1}.get(plain[end], 0)
                if depth == 0:
                    break
            argument = plain[found.start() + len(".font("):end]
            if leading.search(argument):
                left.append(f"{where} .font({argument})")
        if re.search(r"\.system\(|Font\.(system|custom)|\.custom\([^()]*size:", plain):
            left.append(f"{where} a system or custom font of its own")
        if re.search(rf"font: \.({styles})\b|Font = \.({styles})\b", plain):
            left.append(f"{where} a system text style handed on")
        if re.search(r"\.monospaced\(\)", plain):
            left.append(f"{where} .monospaced() (Typeface.mono is the data face)")
        if re.search(r"UIFont\.(systemFont|boldSystemFont|preferredFont)|UIFont\(name:", plain):
            left.append(f"{where} a UIKit font of its own")
    assert not left, left
    # the one font left is the turntable's own drawing's (its readouts, drawn in a Canvas), left alone on purpose
    turntable = (APP / "Player" / "Turntable" / "TurntableView.swift").read_text(encoding="utf-8")
    assert "UIFont.monospacedSystemFont(ofSize: CGFloat(points), weight: .regular)" in turntable


def test_every_list_sections_header_and_footer_is_libre_franklin():
    # a header's or footer's words take the face at footnote's size (iOS's own for both), never the list's own font;
    # a section titled by a string is a menu's (QueueMenu, DownloadControl: UIMenu's titles take no font)
    lines = app_code()
    loose = []
    for index, (name, number, code) in enumerate(lines):
        if re.search(r"\} (header|footer): \{", code):
            following = " ".join(line for _, _, line in lines[index:index + 40])
            if ".font(Typeface." not in following:
                loose.append(f"{name}:{number}")
        if re.search(r"Section\([^{}:]+\) \{", code) and name not in ("Player/QueueMenu.swift",
                                                                     "Downloads/DownloadControl.swift"):
            loose.append(f"{name}:{number} a section titled by a string")
    assert not loose, loose
