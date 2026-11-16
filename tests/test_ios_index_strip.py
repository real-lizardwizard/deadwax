"""
The iPhone app's Library index beats the list's momentum (notes/ios.md "The letter bar beats momentum"; James: "if
the library is still scrolling by momentum, I can't use the letter bar on the right side. I'd like that seek bar to
override the momentum").

The cause, measured on this Mac's Catalyst build of iOS 27.2's SwiftUI: the strip is laid over the list, outside the
list's UIScrollView, so a touch on it never stops the list as a touch on the list does; and a ScrollViewReader jump made
while that scroll view decelerates was dropped by SwiftUI in three flings of seven. The fix: at touch-down the strip
stops the list's deceleration through the list's own UIScrollView (MomentumStop, found from inside the list's
content), then jumps. Read from the Swift source: the stop comes first, at touch-down and in VoiceOver's "Jump to"
too; every screen that draws the strip hands it its own list's stop; and the strip's own rules - entryAt over the
strip as drawn at touch-down, the haptic tick - and the pull to shuffle on the same ScrollView are as they were.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
LIBRARY = APP / "Library"
STRIP = LIBRARY / "ShelfIndexStrip.swift"
STOP = LIBRARY / "MomentumStop.swift"


def code(path: Path) -> str:
    """A Swift file with its // comments blanked."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


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


def test_a_touch_on_the_strip_stops_the_list_before_it_jumps():
    strip = code(STRIP)
    assert "let momentum: MomentumStop" in strip
    # the strip's own gesture, from touch-down, in its own space - as it was
    assert "DragGesture(minimumDistance: 0, coordinateSpace: .local)" in strip
    changed = block(strip, strip.index("{", strip.index(".onChanged { touch in")))
    down = changed.index("if press == nil {")
    first = block(changed, changed.index("{", down))
    # at touch-down: the strip as drawn kept, and the list stopped
    assert "press = held" in first and "momentum.stop()" in first
    # then the jump, read from the strip as drawn at touch-down
    assert changed.index("momentum.stop()") < changed.index("jump(entries[at].group)")
    assert "ShelfIndex.entryAt(held.drawn, y: Double(touch.location.y), top: held.top," in changed
    # the tick a finger feels, at each jump
    assert "jumps += 1" in changed and ".sensoryFeedback(.selection, trigger: jumps)" in strip
    ended = strip[strip.index(".onEnded { _ in"):]
    assert "press = nil" in ended[:120] and "under = nil" in ended[:120]


def test_voiceovers_jump_to_stops_the_list_too():
    strip = code(STRIP)
    action = block(strip, strip.index(".accessibilityAction {") + len(".accessibilityAction {") - 1)
    assert action.index("momentum.stop()") < action.index("jump(entry.group)")
    assert ".accessibilityLabel(entry.accessibility)" in strip and ".accessibilityAddTraits(.isButton)" in strip
    assert ".accessibilityLabel(Self.spoken)" in strip


def test_the_stop_is_uikits_own_and_only_for_momentum():
    stop = code(STOP)
    body = block(stop, stop.index("func stop() {") + len("func stop() {") - 1)
    # only a list gliding by momentum - UIKit's isDecelerating, which is the finger up already, and nothing else to
    # leave a real fling unstopped (review: an isDragging guard too could)
    assert "guard let scrollView, scrollView.isDecelerating else { return }" in body
    assert "isDragging" not in body
    # setContentOffset(_:animated: false) ends a deceleration and tells the delegate (the contentOffset setter doesn't)
    assert "scrollView.setContentOffset(scrollView.contentOffset, animated: false)" in body
    # found from inside the list's content: the nearest scroll view up its superviews, the list's own (the Library's
    # pager is further up)
    find = block(stop, stop.index("func find() {") + len("func find() {") - 1)
    assert "var at = superview" in find and "if let scrollView = view as? UIScrollView {" in find
    assert "return" in find[find.index("as? UIScrollView"):]
    # a view of no size that takes no touch and VoiceOver doesn't see
    assert ".frame(width: 0, height: 0)" in stop and ".accessibilityHidden(true)" in stop
    assert "view.isUserInteractionEnabled = false" in stop and "view.accessibilityElementsHidden = true" in stop
    assert "weak var scrollView: UIScrollView?" in stop


def test_every_screen_with_the_strip_hands_it_its_own_lists_stop():
    uses = []
    for path in sorted(APP.rglob("*.swift")):
        if path == STRIP:
            continue
        source = code(path)
        if "ShelfIndexStrip(" not in source.replace("ShelfIndexStrip.width(", ""):
            continue
        uses.append(path.name)
        assert "@State private var momentum = MomentumStop()" in source, path.name
        for found in re.finditer(r"ShelfIndexStrip\((?!years:)", source):
            call = source[found.start():source.index("{", found.start())]
            assert "momentum: momentum" in call, f"{path.name}: {call}"
        # the stop is found inside the ScrollView's content, and the strip is the ScrollView's overlay
        scroll = source.index("ScrollView {")
        finder = source.index(".stopsMomentum(momentum)")
        overlay = source.index(".overlay(alignment: .trailing) {", scroll)
        assert scroll < finder < overlay, path.name
        content = block(source, source.index("{", scroll))
        assert ".stopsMomentum(momentum)" in content, path.name
        # the pull to shuffle stays on the same ScrollView
        assert scroll < source.index(".pullsToShuffle(", scroll) < overlay, path.name
    assert uses == ["AlbumsScreen.swift", "ArtistsScreen.swift"]
