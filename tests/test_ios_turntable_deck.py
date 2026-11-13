"""The iPhone turntable never waits on the song's engine from the main thread (notes/ios-specs/turntable.md 2.6).

PlaybackEngine's position() and debug() are a queue.sync on its queue, which is busiest exactly when the deck hands
the song back (the resume opening the file, decoding and starting the output). The deck asks them only from the
`deck.position` queue (DeckPositionFeed in DeckController.swift). The let-go counts the engine's starts from its phase
instead (HandoverStarts in DeckRules.swift). The review of slice 3 found a debug() on the main thread at the let-go;
this test keeps it out.
"""

from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TURNTABLE = REPO / "ios" / "App" / "Player" / "Turntable"


def test_only_the_position_queue_asks_the_songs_engine():
    feed_seen = False
    for path in sorted(TURNTABLE.glob("*.swift")):
        text = path.read_text()
        if "final class DeckPositionFeed" in text:
            start = text.index("final class DeckPositionFeed")
            end = text.index("\n}\n", start)
            feed = text[start:end]
            assert "engine.position()" in feed and "engine.debug()" in feed, "the feed reads the engine"
            text = text[:start] + text[end:]
            feed_seen = True
        for ask in (".position()", ".debug()"):
            assert ask not in text, f"{path.name} asks the song's engine {ask} outside the deck.position queue"
        for line in text.splitlines():
            if "engineForDeck" in line:
                assert "feed.run(engine" in line, f"{path.name}: the song's engine is only handed to the feed: {line}"
    assert feed_seen, "DeckPositionFeed not found"


def test_every_deck_engine_the_app_makes_activates_the_session_first():
    """Slice 2's review, question 6: the session is active before the deck starts. DeckEngine's `activate` does it at
    the top of every start (DeckReviewTests holds the order); here, every deck engine the app makes is given it."""
    made = 0
    for path in sorted((REPO / "ios" / "App").rglob("*.swift")):
        lines = path.read_text().splitlines()
        for number, line in enumerate(lines):
            code = line.split("//")[0]
            if "DeckEngine(" not in code and "DeckTrial(" not in code:
                continue
            made += 1
            after = "\n".join(lines[number:number + 8])
            assert "activate = { try AudioSessionController.activateShared() }" in after, (
                f"{path.name}:{number + 1} makes a deck engine without the session's activation")
    assert made >= 2, "the deck's engine and Debug's trial"


def test_the_fader_takes_touches_across_its_whole_target_and_is_let_go_whenever_the_turntable_goes():
    """The fader's review (slice 4). The target overhangs the plinth's right edge (TurntableLayout.touchWidth, held by
    SpeedControlTests' theWholeFaderTargetIsInsideTheViewThatTakesTouches), and a touch outside a view's bounds never
    reaches its subviews: the deck's UIView and its SwiftUI frame are touchWidth wide, the plinth laid out at its own
    width with the rest overhanging its right. The fader's touch view is under the arm's, as the web draws the handle
    over the fader. And a held fader is let go however the turntable goes - Now Playing closed, or the look switched
    (destroy), whose touch view goes with it and whose cancel may never come."""
    view = (TURNTABLE / "TurntableDeckView.swift").read_text()
    swiftui = (TURNTABLE / "TurntableView.swift").read_text()
    deck = (TURNTABLE / "DeckController.swift").read_text()

    assert "super.init(frame: CGRect(x: 0, y: 0, width: layout.touchWidth, height: layout.height))" in view
    plinth = swiftui[swiftui.index("DeckPlinth(deck: deck, layout: layout)\n"):]
    plinth = plinth[:plinth.index(".padding(")]
    wide = plinth.index(".frame(width: CGFloat(layout.touchWidth), height: CGFloat(layout.height))")
    laid = plinth.index(".frame(width: CGFloat(layout.width), height: CGFloat(layout.height), alignment: .leading)")
    assert wide < laid, "the view is touchWidth wide inside a plinth-wide frame, overhanging its right"

    assert "insertSubview(fader, belowSubview: arm)" in view and "addSubview(fader)" not in view

    for name in ("    func closed() {", "    private func destroy() {"):
        body = deck[deck.index(name):]
        body = body[:body.index("\n    }\n")]
        assert "faderLetGo()" in body, f"{name.strip()} lets a held fader go"
        if "destroy" in name:
            assert body.index("faderLetGo()") < body.index("guard let rules"), "before anything can return"
