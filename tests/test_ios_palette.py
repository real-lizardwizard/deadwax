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
    # unless the song plays - paused, loading, under a finger, and for the play bar with Now Playing over it - and then
    # they show shownPosition, as before. Between the ticker's readings they carry the last one on (Core's PlayClock),
    # the engine not asked; the ticker and all it drives are as they were; VoiceOver's value stays on shownPosition.
    model = (APP / "Models" / "PlayerModel.swift").read_text(encoding="utf-8")
    mini = (APP / "Player" / "MiniPlayerView.swift").read_text(encoding="utf-8")
    scrubber = (APP / "Player" / "ScrubberView.swift").read_text(encoding="utf-8")
    clock = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "PlayClock.swift").read_text(encoding="utf-8")
    assert "public static let frame = 1.0 / 30\n" in clock
    assert "var barsRun: Bool { isPlaying && !isLoading }" in model
    reading = model[model.index("func barPosition(at now: Double) -> Double {"):]
    reading = reading[:reading.index("\n    }\n")]
    assert "guard barsRun, let smooth, smooth.entry == heardEntry else { return shownPosition }" in reading
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
    assert "if !barsRun { smooth = nil }" in tick
    for view, runs in ((mini, "let runs = player.barsRun && held == nil && !navigation.nowPlayingShown"),
                       (scrubber, "let runs = player.barsRun && held == nil")):
        assert runs in view
        assert view.count("TimelineView(.animation(minimumInterval: PlayClock.frame, paused: !runs))") == 1
        assert "let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)" in view
        assert ".accessibilityValue(PlayerWords.scrubberValue(shown: shown, length: length))" in view
        # the frames' value is drawn inside the timeline alone
        assert view.count("player.barPosition(at: Monotonic.seconds())") == 1
        assert view.index("TimelineView(") < view.index("player.barPosition(")
    # the seek line's timeline holds its fill alone; the scrubber's clocks are redrawn only when their words change
    fill = mini[mini.index("TimelineView("):]
    assert fill.index("Rectangle().fill(Palette.accent)") < fill.index("}")
    assert "private struct ScrubberClocks: View, Equatable" in scrubber and ".equatable()" in scrubber
    assert "PlayerWords.elapsed(shown: drawn)" in scrubber and "PlayerWords.remaining(shown: drawn, length: length)" in scrubber
    # the lyrics keep their own clock
    assert "player.clock()" in (APP / "Player" / "LyricsView.swift").read_text(encoding="utf-8")


# Noto Sans (15 Nov): James chose "Noto Sans (the web's)". The phone's four faces are the web's own seven files made into
# one font per weight (ios/scripts/make-fonts.py), named by Info.plist's UIAppFonts, and every text style the app sets is
# ios/App/Shared/Typeface.swift's - nothing in ios/App names a system text font of its own. A symbol drawn alone keeps
# iOS's own font (Typeface.symbol), which is how an SF Symbol is sized, and data the system's monospace (Typeface.mono).

TYPEFACE = APP / "Shared" / "Typeface.swift"
FONTS = APP / "Fonts"
WEB_FONTS = REPO / "interface" / "styles" / "font" / "noto-sans"
INFO_PLIST = REPO / "ios" / "Config" / "Info.plist"
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


def test_the_fonts_are_the_webs_own_noto_sans():
    import json
    import plistlib
    files = sorted(path.name for path in FONTS.glob("*.ttf"))
    assert files == ["NotoSans-Bold.ttf", "NotoSans-Medium.ttf", "NotoSans-Regular.ttf", "NotoSans-SemiBold.ttf"]
    # Info.plist names each (the synchronized folder copies them to the bundle's root, where UIAppFonts looks)
    assert sorted(plistlib.loads(INFO_PLIST.read_bytes())["UIAppFonts"]) == files
    # the licence goes with them: the web's own
    assert (FONTS / "OFL.txt").read_bytes() == (WEB_FONTS / "OFL.txt").read_bytes()
    # each face is of the family Typeface asks for, under the PostScript name Typeface gives UIKit
    source = TYPEFACE.read_text(encoding="utf-8")
    assert re.search(r'static let family = "([^"]+)"', source).group(1) == "Noto Sans"
    faces = sorted(re.findall(r'case \w+ = "(NotoSans-\w+)"', source))
    assert len(faces) == 4
    named = []
    for name in files:
        table = font_names(FONTS / name)
        assert table.get(16, table[1]) == "Noto Sans", name
        named.append(table[6])
    assert sorted(named) == faces
    # every character of the web's seven files, in every face: one font per weight, the web's whole range
    web = json.loads((REPO / "tests" / "fixtures" / "font_cmaps.json").read_text(encoding="utf-8"))
    wanted = set()
    for key, entry in web.items():
        if key.startswith("noto-sans/"):
            for part in entry["cmap"].split(","):
                low, _, high = part.strip()[2:].partition("-")
                wanted |= set(range(int(low, 16), int(high or low, 16) + 1))
    assert len(wanted) > 1600
    for name in files:
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
