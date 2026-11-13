"""
The server's answers the iPhone app reads AutoEq from (EQ slice 4, notes/ios-specs/eq.md 5.4): what
`GET /deadwax/eq/autoeq` and `GET /deadwax/eq/autoeq/{id}` (src/routes/eq.py) send - asked of the whole app, start(),
over tests/test_autoeq.py's own fake GitHub and its fixtures (46 lines of AutoEq's INDEX.md at 7ae0f56, and two
ParametricEQ.txt files), with a real SQLite store in a folder of its own and the routes' clock held at one moment, so
`list_from` is the same every time. Written to

  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/autoeq/answers.json

which DeadwaxCoreTests' AutoEqTests decodes as AutoEqResults and AutoEqProfile, asks through DeadwaxClient's two
calls (the path and query each case was asked with, answered with what the server sent) and runs EQSuggestion over -
the AirPods Pro's several, the HD 650's one, a speaker's none. tests/test_ios_contract.py holds the file to what this
makes now, so a change to the routes' answers fails there until it is written again
(`.venv/bin/python ios/scripts/autoeq_answers.py`) and the phone's tests run on it.

Names outside ASCII are written as JSON escapes, so the file holds none raw.
"""

import asyncio
import json
import sys
import tempfile
import types
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

import httpx

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.api.autoeq_endpoint import autoeq_client  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import eq as eq_route  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests import test_autoeq as T  # noqa: E402

FIXTURE = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "autoeq" / "answers.json"

#? the moment the list is fetched at, as the routes' clock reads it: `list_from` is said from it
NOW = datetime(2026, 11, 12, 9, 30, tzinfo=timezone.utc).timestamp()

#? what the phone asks for: Core's AutoEqAsk.limit, which the contract test holds to this
LIMIT = 50

SEARCHES = [
    ("the HD 650 by its name: one headphone, and five of its own with a word in parentheses",
     {"q": "Sennheiser HD 650", "limit": LIMIT}),
    ("the AirPods Pro as iOS names them, an owner's name taken off: the first generation and the Pro 2's",
     {"q": "AirPods Pro", "limit": LIMIT}),
    ("an AirPods Pro renamed with its maker: still the first generation and the Pro 2's",
     {"q": "Apple AirPods Pro", "limit": LIMIT}),
    ("a speaker: AutoEq measures headphones", {"q": "JBL Flip 6", "limit": LIMIT}),
    ("the model alone, its words run together", {"q": "hd650", "limit": LIMIT}),
    ("a letter outside ASCII, typed plain", {"q": "aur audio", "limit": LIMIT}),
    ("more found than asked for", {"q": "apple", "limit": 3}),
]

#? the AirPods Pro's and the HD 650's files are GitHub's; Super Review's AirPods Pro is in the list with no file there
PROFILES = [
    ("crinacle's AirPods Pro", T.AIRPODS_PRO),
    ("oratory1990's HD 650", T.HD650),
    ("in the list, but GitHub has no file for it: gone", "Super Review/in-ear/Apple AirPods Pro"),
    ("not in the list: gone", None),
]


@contextmanager
def _app(hub: T.GitHub):
    """The whole app over the fake GitHub, its store new, logins off (the routes are a user's: the implicit admin
    asks), the routes' clock at NOW - and the AutoEq client as it was afterwards (tests/test_autoeq.py's env fixture
    sets its own for each test)."""
    was = autoeq_client._client
    autoeq_client._client = httpx.AsyncClient(transport=httpx.MockTransport(hub.handle), follow_redirects=False)
    try:
        with tempfile.TemporaryDirectory() as folder:
            store = JobStore(str(Path(folder) / "deadwax.db"))
            store.init()
            with mock.patch.object(Config, "AUTH_MODE", None), \
                    mock.patch.object(eq_route, "time", types.SimpleNamespace(time=lambda: NOW)):
                with T.serving(store) as (_app, client):
                    yield client
    finally:
        asyncio.run(autoeq_client.close_client())
        autoeq_client._client = was


def _case(name: str, client, path: str, query: dict | None = None) -> dict:
    response = client.get(path, params=query or {})
    return {"name": name, "path": path, "query": {k: str(v) for k, v in (query or {}).items()},
            "status": response.status_code, "answer": response.json()}


def answers() -> dict:
    hub = T.GitHub()
    with _app(hub) as client:
        searches = [_case(name, client, "/deadwax/eq/autoeq", query) for name, query in SEARCHES]
        profiles = [_case(name, client, f"/deadwax/eq/autoeq/{T.rid(path) if path else '0123456789abcdef'}")
                    for name, path in PROFILES]
        #? GitHub gone, once the list is kept: a profile not fetched yet can't be
        hub.down = True
        profiles.append(_case("GitHub not answering: a profile not fetched before", client,
                              f"/deadwax/eq/autoeq/{T.rid(T.BK_AIRPODS)}"))
    #? GitHub gone with no list kept: a search can't be answered
    down = T.GitHub()
    down.down = True
    with _app(down) as client:
        searches.append(_case("GitHub not answering, no list kept", client, "/deadwax/eq/autoeq",
                              {"q": "AirPods Pro", "limit": LIMIT}))
    return {
        "made_from": "src/routes/eq.py over tests/test_autoeq.py's GitHub (ios/scripts/autoeq_answers.py)",
        "limit": LIMIT,
        "searches": searches,
        "profiles": profiles,
    }


def text() -> str:
    return json.dumps(answers(), indent=1, ensure_ascii=True) + "\n"


if __name__ == "__main__":
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(text(), encoding="utf-8")
    print(f"wrote {FIXTURE.relative_to(ROOT)}")
