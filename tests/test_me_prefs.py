"""
GET and PUT /deadwax/me/preferences (2.0.0-player.15): what a user chose in the app's You > Getting
albums - "When I tap Get" (show me the sources, or pick the best source for me) and the quality
floor - kept per user on the server, through `current_user`, in store.user_prefs.

- Only the allowlisted keys, each with only its listed values: anything else is a 422 and nothing
  is written. A stored value no longer allowed reads as the default.
- An unset preference is its default, and `stored` names the ones set, while `can_save` says
  whether deadwax can keep them at all. `seeded` says whether anything was ever saved for the user:
  every save writes a `_seeded` row beside what it sets - an empty one too - which is how the app
  seeds a user once from the old page's settings without storing the defaults as if they were chosen
  (review): an absent preference is its default, so a default changed later still reaches them.
- Per user: the route reads the dependency, so step 3's logins change current_user and nothing here.
- A PUT is a write, so the same-origin guard refuses one another website asks for - through the real
  app start() builds, every middleware in the way, as the page meets it.
- The three lists of keys and values - here, the PUT's model and the app's lib/getSettings.ts - are
  one list.
"""

import re
import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src.api.app import start
from src.routes import me
from src.store import JobStore
from src.users import current_user

ROUTE = "/deadwax/me/preferences"
GET_SETTINGS_TS = Path(__file__).resolve().parent.parent / "ui" / "src" / "lib" / "getSettings.ts"


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


def client(store, user=None):
    app = start()
    app.state.store = store
    if user:
        app.dependency_overrides[current_user] = lambda: user
    return TestClient(app)  # no `with`: no lifespan, nothing connects


def rows(store):
    with sqlite3.connect(store.path) as connection:
        return sorted(connection.execute("SELECT user, key, value FROM user_prefs").fetchall())


def test_nothing_set_is_every_default_and_says_none_is_stored(store):
    assert client(store).get(ROUTE).json() == {
        "get_mode": "sources", "quality_floor": "any", "stored": [], "seeded": False, "can_save": True,
    }


def test_an_empty_save_stores_no_preference_and_says_the_user_is_seeded(store):
    """The app's seeding with nothing to carry over: no default stored as a choice, and seeded once."""
    put = client(store).put(ROUTE, json={})

    assert put.status_code == 200
    assert put.json() == {"get_mode": "sources", "quality_floor": "any", "stored": [], "seeded": True, "can_save": True}
    assert rows(store) == [("local", "_seeded", "1")]
    assert client(store).get(ROUTE).json()["seeded"] is True


def test_a_default_changed_later_reaches_a_user_seeded_with_nothing(store, monkeypatch):
    client(store).put(ROUTE, json={})
    monkeypatch.setitem(me.DEFAULTS, "quality_floor", "lossless")

    assert client(store).get(ROUTE).json()["quality_floor"] == "lossless"


def test_a_preference_set_is_kept_and_read_back(store):
    put = client(store).put(ROUTE, json={"quality_floor": "lossless"})

    assert put.status_code == 200
    assert put.json() == {"get_mode": "sources", "quality_floor": "lossless", "stored": ["quality_floor"], "seeded": True, "can_save": True}
    assert client(store).get(ROUTE).json()["quality_floor"] == "lossless"
    assert rows(store) == [("local", "_seeded", "1"), ("local", "quality_floor", "lossless")]


def test_setting_one_leaves_the_other_as_it_was(store):
    client(store).put(ROUTE, json={"get_mode": "pick", "quality_floor": "24bit"})
    client(store).put(ROUTE, json={"quality_floor": "320"})

    answer = client(store).get(ROUTE).json()
    assert (answer["get_mode"], answer["quality_floor"], answer["stored"]) == ("pick", "320", ["get_mode", "quality_floor"])


@pytest.mark.parametrize("body", [
    {"quality_floor": "flac"},
    {"get_mode": "auto"},
    {"get_mode": ""},
    {"quality_floor": 320},
    {"theme": "dark"},
    {"get_mode": "pick", "theme": "dark"},
    {"_seeded": "1"},
])
def test_a_key_or_value_not_on_the_list_is_refused_and_nothing_is_written(store, body):
    answer = client(store).put(ROUTE, json=body)

    assert answer.status_code == 422
    assert rows(store) == []


def test_a_stored_value_no_longer_allowed_reads_as_the_default(store):
    with sqlite3.connect(store.path) as connection:
        connection.execute("INSERT INTO user_prefs VALUES ('local', 'quality_floor', 'flac', 'then')")
        connection.execute("INSERT INTO user_prefs VALUES ('local', 'theme', 'dark', 'then')")

    assert client(store).get(ROUTE).json() == {"get_mode": "sources", "quality_floor": "any", "stored": [], "seeded": True, "can_save": True}


def test_each_user_has_their_own(store):
    client(store, "james").put(ROUTE, json={"get_mode": "pick"})

    assert client(store, "james").get(ROUTE).json()["get_mode"] == "pick"
    assert client(store).get(ROUTE).json()["get_mode"] == "sources"
    assert rows(store) == [("james", "_seeded", "1"), ("james", "get_mode", "pick")]


def test_the_user_comes_from_the_dependency_never_middleware():
    routes = {(r.path, tuple(sorted(r.methods))): r for r in me.router.routes}
    for key in [("/preferences", ("GET",)), ("/preferences", ("PUT",))]:
        assert current_user in [d.call for d in routes[key].dependant.dependencies]


def test_a_put_another_website_asks_for_is_refused(store):
    """The app's own PUT carries its own origin; a page elsewhere can't make the browser send one."""
    refused = client(store).put(ROUTE, json={"get_mode": "pick"}, headers={"Origin": "http://elsewhere.example:8080"})
    assert refused.status_code == 403
    assert rows(store) == []

    allowed = client(store).put(ROUTE, json={"get_mode": "pick"}, headers={"Origin": "http://testserver"})
    assert allowed.status_code == 200
    assert rows(store) == [("local", "_seeded", "1"), ("local", "get_mode", "pick")]


def test_reading_is_not_a_write_and_is_never_refused(store):
    assert client(store).get(ROUTE, headers={"Origin": "http://elsewhere.example"}).status_code == 200


def test_an_unwritable_database_says_so_and_a_put_is_refused(tmp_path):
    broken = JobStore(str(tmp_path / "state" / "deadwax.db"))  # never init()ed: unavailable

    assert client(broken).get(ROUTE).json() == {"get_mode": "sources", "quality_floor": "any", "stored": [], "seeded": False, "can_save": False}
    answer = client(broken).put(ROUTE, json={"get_mode": "pick"})
    assert answer.status_code == 503
    assert answer.json()["detail"] == "deadwax can't keep preferences: its database isn't writable"


def test_a_write_the_database_refuses_is_said_and_nothing_claims_it_was_kept(store, monkeypatch):
    async def refuses(user, values):
        return False
    monkeypatch.setattr(store, "set_user_preferences", refuses)

    answer = client(store).put(ROUTE, json={"get_mode": "pick"})

    assert answer.status_code == 503
    assert answer.json()["detail"] == "deadwax couldn't save that: its database refused the write"
    #? an empty save is a write too - the seeding's - and refused the same way
    assert client(store).put(ROUTE, json={}).status_code == 503


def test_a_database_from_before_this_gains_the_table(tmp_path):
    path = tmp_path / "old.db"
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)")

    old = JobStore(str(path))
    old.init()

    assert client(old).put(ROUTE, json={"quality_floor": "24bit"}).json()["quality_floor"] == "24bit"


def test_only_get_and_put():
    assert TestClient(start()).post(ROUTE, json={}).status_code == 405


def test_the_keys_and_values_are_one_list_here_in_the_put_and_in_the_app():
    #? the PUT's model takes exactly PREFERENCES
    fields = me.Preferences.model_fields
    assert set(fields) == set(me.PREFERENCES)
    for key, values in me.PREFERENCES.items():
        assert set(fields[key].annotation.__args__[0].__args__) == set(values)
    assert me.DEFAULTS == {"get_mode": "sources", "quality_floor": "any"}

    #? ...and so does the app's: each key's values, in order, in lib/getSettings.ts
    text = GET_SETTINGS_TS.read_text()
    for key, values in me.PREFERENCES.items():
        listed = re.search(rf"export const {key.upper()}_VALUES = \[([^\]]*)\] as const", text)
        assert listed, key
        assert tuple(re.findall(r"'([^']*)'", listed.group(1))) == values
