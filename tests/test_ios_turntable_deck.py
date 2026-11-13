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
