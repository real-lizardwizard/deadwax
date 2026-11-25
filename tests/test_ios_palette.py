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
        #? (the Mac redesign, R1) the Mac's rounded corners - James: "Rounded on Mac only" - are MacCorners' alone, held to
        #? dw.css by test_ios_mac_look.py; the phone's stay Corners', every one 0
        if name in ("Shared/Corners.swift", "Mac/Look/MacCorners.swift"):
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


def test_the_requests_badge_is_the_webs():
    # (Phase 6) Requests' count on the app's tab bar, as app.css's .app-tab-badge: STYLE.md's purple badge laid over the
    # bar's own colour, the accent's words, a control's corners, the web's sizes and its place over the icon's corner
    assert token(THEME_CSS, "dw-badge-purple-bg") == "rgba(168, 85, 247, 0.16)"
    assert token(THEME_CSS, "dw-badge-purple-border") == "rgba(192, 132, 252, 0.4)"
    palette = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    assert "static let badgeFill = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255).opacity(0.16)\n" in palette
    assert "static let badgeEdge = Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255).opacity(0.4)\n" in palette
    assert palette_rgb("accentText") == hex_colour(token(THEME_CSS, "dw-accent-text"))[:3]
    tabs = (APP / "Root" / "MainTabs.swift").read_text(encoding="utf-8")
    badge = tabs[tabs.index("private struct TabBadge"):]
    badge = badge[:badge.index("\n}\n")]
    assert f"private var size: CGFloat = {px(token(APP_CSS, 'app-tab-badge')):g}\n" in badge
    assert f"private static let pad: CGFloat = {px(token(APP_CSS, 'app-tab-badge-pad')):g}\n" in badge
    assert f"private static let up: CGFloat = {-px(token(APP_CSS, 'app-tab-badge-top')):g}\n" in badge
    icon, left = px(token(APP_CSS, "app-tab-icon")), px(token(APP_CSS, "app-tab-badge-left"))
    assert f"private static let right: CGFloat = {left - icon / 2:g}\n" in badge
    for drawn in ("Palette.accentText", "Palette.badgeFill", "Palette.tabBar", "Palette.badgeEdge",
                  "Corners.controlShape"):
        assert drawn in badge, drawn
    # drawn on Requests' button alone, and read in its label
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
    assert "private static let height: CGFloat = 60\n" in mini
    assert "private static let button: CGFloat = 48\n" in mini
    edge = re.search(r"private static let edge: CGFloat = (\d+)\n", mini)
    assert edge and 12 <= int(edge.group(1)) <= 16
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
    assert fill.index("Rectangle().fill(Palette.accent)") < fill.index("}")
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
    assert ("private var sheetOver: Bool { showsUpNext || showsInfo || showsEQ || playlistPick != nil || viewing != nil }"
            in now_playing)
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
    # the row is above its window's edge, and read again after every ask.
    library = (APP / "Library" / "LibraryView.swift").read_text(encoding="utf-8")
    pager = library[library.index("private func pager(albums: AlbumList)"):library.index("private func pageView(")]
    assert ".safeAreaInset(edge: .top" not in library and ".showsOfflineBanner()" not in pager
    order = [pager.index(part) for part in ("return VStack(spacing: 0) {", "LibraryTop(", "OfflineBanner()",
                                             "ScrollView(.horizontal)", ".containerRelativeFrame([.horizontal, .vertical])",
                                             ".toolbar(.hidden, for: .navigationBar)")]
    assert order == sorted(order)
    top = (APP / "Library" / "LibraryTop.swift").read_text(encoding="utf-8")
    assert top.count("ignoresSafeArea") == 1
    assert ".background {\n            Palette.tabBar\n                .ignoresSafeArea(.container, edges: .top)\n" in top
    # the second time (15 Nov, "the library's top still doesn't clear the dynamic island"): the row measures where its
    # own top is and comes down by what of its window's top safe area that doesn't clear (TopClearance), its padding
    # inside what it measures so coming down never moves it
    assert ".padding(.top, clearance)" in top
    # the third (18 Nov, "after pulling up the play screen and going back to library, the top bar is back inside the
    # Dynamic Island"): read by a UIKit probe of the row's own frame - a background after the padding, the fill's
    # ignore not on it - in ITS OWN window's coordinates, with that window's inset, nothing out of a window
    row = top[:top.index("struct LibrarySwitchControl")]
    body = row[row.index("var body: some View {"):row.index("private func take(")]
    order = [body.index(part) for part in (".padding(.top, clearance)", ".ignoresSafeArea(.container, edges: .top)\n",
                                           ".background {\n            TopProbe(eyes: eyes) {", ".onGeometryChange(",
                                           '.onAppear { eyes.probe?.soon("appear") }')]
    assert order == sorted(order)
    probe_view = body[body.index("TopProbe(eyes: eyes)"):body.index(".overlay(alignment: .bottom)")]
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


# Noto Sans (15 Nov): James chose "Noto Sans (the web's)". The phone's four faces are the web's own seven files made into
# one font per weight (ios/scripts/make-fonts.py), named by Info.plist's UIAppFonts, and every text style the app sets is
# ios/App/Shared/Typeface.swift's - nothing in ios/App names a system text font of its own. A symbol drawn alone keeps
# iOS's own font (Typeface.symbol), which is how an SF Symbol is sized, and data the system's monospace (Typeface.mono).

TYPEFACE = APP / "Shared" / "Typeface.swift"
FONTS = APP / "Fonts"
WEB_FONTS = REPO / "interface" / "styles" / "font" / "noto-sans"
#? (the Mac redesign, R1) James, 24 Nov: "Bundle Noto Sans Mono" - the Mac's data face, made from the web's own
WEB_MONO = REPO / "interface" / "styles" / "font" / "noto-sans-mono"
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


def web_characters(folder: str) -> set:
    """Every character the web's files of a family claim (tests/fixtures/font_cmaps.json, read from the woff2s)."""
    import json
    web = json.loads((REPO / "tests" / "fixtures" / "font_cmaps.json").read_text(encoding="utf-8"))
    wanted = set()
    for key, entry in web.items():
        if key.startswith(folder + "/"):
            for part in entry["cmap"].split(","):
                low, _, high = part.strip()[2:].partition("-")
                wanted |= set(range(int(low, 16), int(high or low, 16) + 1))
    return wanted


def test_the_fonts_are_the_webs_own_noto_sans():
    import plistlib
    files = sorted(path.name for path in FONTS.glob("*.ttf"))
    words = ["NotoSans-Bold.ttf", "NotoSans-Medium.ttf", "NotoSans-Regular.ttf", "NotoSans-SemiBold.ttf"]
    #? (the Mac redesign, R1) and Noto Sans Mono's three, the drawings' 400, 500 and 600
    mono = ["NotoSansMono-Medium.ttf", "NotoSansMono-Regular.ttf", "NotoSansMono-SemiBold.ttf"]
    assert files == sorted(words + mono)
    # Info.plist names each (the synchronized folder copies them to the bundle's root, where UIAppFonts looks) - and
    # Info-Mac.plist the same (check_project.py holds the two plists in step)
    for plist in (INFO_PLIST, INFO_MAC_PLIST):
        assert sorted(plistlib.loads(plist.read_bytes())["UIAppFonts"]) == files, plist.name
    # the licence goes with them: the web's own - the same file beside both families
    assert (FONTS / "OFL.txt").read_bytes() == (WEB_FONTS / "OFL.txt").read_bytes() == (WEB_MONO / "OFL.txt").read_bytes()
    # each face is of the family Typeface asks for, under the PostScript name Typeface gives UIKit
    source = TYPEFACE.read_text(encoding="utf-8")
    assert re.search(r'static let family = "([^"]+)"', source).group(1) == "Noto Sans"
    faces = sorted(re.findall(r'case \w+ = "(NotoSans-\w+)"', source))
    assert len(faces) == 4
    named = []
    for name in words:
        table = font_names(FONTS / name)
        assert table.get(16, table[1]) == "Noto Sans", name
        named.append(table[6])
    assert sorted(named) == faces
    # (R1) the mono faces: of the family Typeface.Mac asks for, under Typeface.Mac.MonoFace's names
    assert re.search(r'static let monoFamily = "([^"]+)"', source).group(1) == "Noto Sans Mono"
    mono_faces = sorted(re.findall(r'case \w+ = "(NotoSansMono-\w+)"', source))
    assert len(mono_faces) == 3
    named = []
    for name in mono:
        table = font_names(FONTS / name)
        assert table.get(16, table[1]) == "Noto Sans Mono", name
        named.append(table[6])
    assert sorted(named) == mono_faces
    # every character of the web's seven files, in every face: one font per weight, the web's whole range
    wanted = web_characters("noto-sans")
    assert len(wanted) > 1600
    for name in words:
        assert font_characters(FONTS / name) == wanted, name
    wanted = web_characters("noto-sans-mono")
    assert len(wanted) > 1600
    for name in mono:
        assert font_characters(FONTS / name) == wanted, name


def test_every_text_style_is_noto_sans_scaled_as_ios_scales_it():
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
        # a symbol drawn alone and data keep the system's faces - but only through Typeface, by name
        plain = re.sub(r"Typeface\.(symbol|mono)\([^()]*\)", "Typeface.kept", code)
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


def test_every_list_sections_header_and_footer_is_noto_sans():
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
