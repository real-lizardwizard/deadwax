"""The web recording the iPhone's replay is held to (notes/ios-specs/turntable.md 6.3, slice 4).

ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/recording/web-script.json is deck.ts's own recorder's file, made by
ios/scripts/export-deck-recording.cjs from the web's TypeScript; DeckReplayTests plays it through the Swift voice. When
a source it was made from changes, the file may no longer be what the web would write: this fails, naming the source,
until the exporter is run again (on Node 20.12.2, the deck fixtures' maker) and the Swift replay checked against it.
"""

import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FOLDER = REPO / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "recording"


def test_the_web_recording_is_made_from_the_sources_as_they_are():
    made = json.loads((FOLDER / "web-script.made.json").read_text())
    assert made["made_from"], "it names its sources"
    for source, digest in made["made_from"] + made["made_with"]:
        text = (REPO / source).read_text()
        assert hashlib.sha256(text.encode()).hexdigest() == digest, (
            f"{source} changed since web-script.json was made: run ios/scripts/export-deck-recording.cjs again "
            "and check DeckReplayTests"
        )


def test_the_web_recording_is_the_webs_file():
    recording = json.loads((FOLDER / "web-script.json").read_text())
    assert recording["recording"] == "deadwax turntable sound" and recording["version"] == 3
    assert recording["voice"] == "script" and "phone" not in recording
    types = {message["type"] for message in recording["messages"]}
    assert {"window", "take", "hand"} <= types, "a window, a take and the hand's samples are in it, so it replays from rest"
    assert (FOLDER / "web-script.json").stat().st_size < 600_000
