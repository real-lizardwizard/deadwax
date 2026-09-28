"""
The player's three settings, saved through the real app (v1.0.3).

Every request to NAVIDROME_URL carries a token made from NAVIDROME_PASSWORD, and Navidrome takes
the same token and salt again for as long as the password stands - so the address is as much a
secret's destination as the password is a secret. What these protect:

  - the password never comes back out, in the payload or in the log;
  - the address can't be pointed somewhere new without the password being typed with it, since
    anyone who can reach deadwax can save a setting (the audit re-pointed it with curl and
    collected a replayable token);
  - an address that would carry more than Navidrome's address - a login, a query - is refused;
  - saving the address drops the cached client, so the next request goes to the new one.

Built with start() and no lifespan, as test_same_origin.py does, so the middleware is the real
app's and nothing connects to anything. The store is a throwaway database per test.
"""

import asyncio
import json
import logging
import sys
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.store import JobStore  # noqa: E402

ENV_PASSWORD = "env-password-8c1f"
NEW_PASSWORD = "typed-password-51d0"
MOVED = "type the Navidrome password again with the new address"


@pytest.fixture
def env(monkeypatch):
    """Navidrome as the environment supplied it, nothing overridden yet."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", ENV_PASSWORD)
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})


@pytest.fixture
def store(tmp_path):
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    return store


@pytest.fixture
def app(env, store):
    app = start()
    app.state.store = store
    return TestClient(app)  # no `with`, so no lifespan: nothing connects


@pytest.fixture
def cached_client():
    """A Navidrome client already built, as it would be after the player's first request."""
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200)),
                               base_url="http://navidrome:4533/rest")
    navidrome.client = client
    yield client
    asyncio.run(navidrome.close_client())


def save(app: TestClient, **values) -> httpx.Response:
    return app.put("/deadwax/settings", json=[{"key": key, "value": value} for key, value in values.items()])


def find(payload: dict, key: str) -> tuple[str, dict]:
    for group in payload["groups"]:
        for setting in group["settings"]:
            if setting["key"] == key:
                return group["id"], setting
    raise AssertionError(f"{key} is not in the settings payload")


# ----- saving the address -----

def test_a_new_address_with_the_password_is_saved_and_the_client_rebuilt(app, store, cached_client):
    response = save(app, NAVIDROME_URL="http://music-box:4533", NAVIDROME_PASSWORD=NEW_PASSWORD)

    assert response.status_code == 200
    assert store.stored_settings() == {"NAVIDROME_URL": "http://music-box:4533",
                                       "NAVIDROME_PASSWORD": NEW_PASSWORD}
    assert Config.NAVIDROME_URL == "http://music-box:4533"
    assert navidrome.client is None and cached_client.is_closed, "the old address's client is gone"
    _, row = find(response.json(), "NAVIDROME_URL")
    assert (row["value"], row["overridden"], row["status"]) == ("http://music-box:4533", True, "ok")


def test_a_new_address_without_the_password_is_refused(app, store, cached_client):
    """What anyone who can reach deadwax could otherwise do: collect the saved password's token."""
    response = save(app, NAVIDROME_URL="http://collector.example:9999")

    assert response.status_code == 400
    assert MOVED in response.json()["detail"]
    assert "won't send the saved one" in response.json()["detail"]
    assert store.stored_settings() == {}
    assert Config.NAVIDROME_URL == "http://navidrome:4533"
    assert navidrome.client is cached_client and not cached_client.is_closed


def test_reverting_the_password_is_not_typing_it(app, store):
    response = save(app, NAVIDROME_URL="http://music-box:4533", NAVIDROME_PASSWORD=None)
    assert response.status_code == 400 and MOVED in response.json()["detail"]
    response = save(app, NAVIDROME_URL="http://music-box:4533", NAVIDROME_PASSWORD="   ")
    assert response.status_code == 400 and MOVED in response.json()["detail"]


def test_saving_the_address_it_already_is_is_not_a_change(app, store):
    assert save(app, NAVIDROME_URL="http://navidrome:4533").status_code == 200


def test_clearing_the_address_sends_nothing_anywhere(app, store):
    response = save(app, NAVIDROME_URL="")
    assert response.status_code == 200
    assert not Config.navidrome_configured()


def test_reverting_the_address_goes_back_to_the_environments(app, store):
    """The environment's address is the admin's own, and reverting is how the tab gets back to it."""
    assert save(app, NAVIDROME_URL="http://music-box:4533", NAVIDROME_PASSWORD=NEW_PASSWORD).status_code == 200

    response = save(app, NAVIDROME_URL=None)

    assert response.status_code == 200
    assert Config.NAVIDROME_URL == "http://navidrome:4533"
    assert "NAVIDROME_URL" not in store.stored_settings()


def test_with_no_password_set_there_is_nothing_to_keep_from_a_new_address(app, store, monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", None)
    assert save(app, NAVIDROME_URL="http://music-box:4533").status_code == 200


def test_a_page_elsewhere_cannot_save_it_at_all(app, store):
    response = app.put("/deadwax/settings", headers={"Origin": "http://192.168.1.20:4533"},
                       json=[{"key": "NAVIDROME_URL", "value": "http://x:1"},
                             {"key": "NAVIDROME_PASSWORD", "value": NEW_PASSWORD}])
    assert response.status_code == 403
    assert store.stored_settings() == {}


@pytest.mark.parametrize("url, reason", [
    ("navidrome:4533", "scheme"),
    ("ftp://navidrome:4533", "scheme"),
    ("http://", "no host"),
    ("http://:4533", "no host"),
    ("http://me:secret@navidrome:4533", "user name or password"),
    ("http://me@navidrome:4533", "user name or password"),
    ("http://navidrome:4533/?x=", "? or #"),
    ("http://evil.example/any/path?", "? or #"),
    ("http://navidrome:4533#", "? or #"),
    ("http://navidrome:port", "port"),
    ("http://navi drome:4533", "space"),
])
def test_an_address_that_carries_more_than_navidromes_is_refused(app, store, url, reason):
    response = save(app, NAVIDROME_URL=url, NAVIDROME_PASSWORD=NEW_PASSWORD)

    assert response.status_code == 400
    assert response.json()["detail"].startswith("NAVIDROME_URL: ")
    assert reason in response.json()["detail"]
    assert store.stored_settings() == {}


def test_refusing_an_address_never_quotes_a_login_typed_into_it(app, store):
    """With no scheme, the refusal used to suggest "use http://<the value>" - password and all."""
    for url in ("me:secret-pw@navidrome:4533", "http://me:secret-pw@navidrome:4533"):
        response = save(app, NAVIDROME_URL=url, NAVIDROME_PASSWORD=NEW_PASSWORD)
        assert response.status_code == 400
        assert "secret-pw" not in response.text


def test_a_base_path_is_allowed(app, store):
    """Navidrome behind a proxy, or with ND_BASEPATH, lives under a path."""
    response = save(app, NAVIDROME_URL="https://nas.example/navidrome", NAVIDROME_PASSWORD=NEW_PASSWORD)
    assert response.status_code == 200


# ----- the password never comes back out -----

def test_an_overridden_password_never_appears_in_the_payload(app, store):
    saved = save(app, NAVIDROME_PASSWORD=NEW_PASSWORD)
    fetched = app.get("/deadwax/settings")

    for response in (saved, fetched):
        assert response.status_code == 200
        assert NEW_PASSWORD not in response.text and ENV_PASSWORD not in response.text
        _, row = find(response.json(), "NAVIDROME_PASSWORD")
        assert (row["value"], row["secret"], row["overridden"], row["env_value"]) == ("set", True, True, None)


def test_the_three_are_on_the_connections_tab(app):
    payload = app.get("/deadwax/settings").json()
    assert {find(payload, key)[0] for key in Config.NAVIDROME_SETTINGS} == {"connections"}


def test_the_user_row_says_no_admin_is_needed(app):
    _, row = find(app.get("/deadwax/settings").json(), "NAVIDROME_USER")
    assert "admin" in row["effect"] and "stars" not in row["effect"]


def test_an_unusable_address_from_the_environment_is_flagged_on_its_row(app, monkeypatch):
    """Saving refuses it; one that came from compose is shown, not silently used."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://me:pw@navidrome:4533")
    _, row = find(app.get("/deadwax/settings").json(), "NAVIDROME_URL")
    assert row["status"] == "error" and "user name or password" in row["detail"]


# ----- what start-up says -----

def test_the_start_up_report_never_logs_the_password(env, monkeypatch, caplog):
    cases = [
        {},                                                        # all three set
        {"NAVIDROME_PASSWORD": None},                              # one missing
        {"NAVIDROME_PASSWORD": ENV_PASSWORD,
         "NAVIDROME_URL": "http://me:hunter@navidrome:4533"},      # unusable address
        {"NAVIDROME_URL": "me:hunter@navidrome:4533"},             # ...and with no scheme
    ]
    for case in cases:
        for key, value in case.items():
            monkeypatch.setattr(Config, key, value)
        with caplog.at_level(logging.INFO):
            Config.report_navidrome()

    assert [r.levelno for r in caplog.records[-4:]] == [logging.INFO, logging.ERROR, logging.ERROR, logging.ERROR]
    assert "user name or password" in caplog.records[-2].getMessage()
    assert "scheme" in caplog.records[-1].getMessage()
    assert ENV_PASSWORD not in caplog.text
    assert "hunter" not in caplog.text, "an address with a login in it is described, not quoted"


def test_the_start_up_report_of_an_unusable_address_says_what_it_stops(env, monkeypatch, caplog):
    """It is true to the letter now: the client refuses the address, and the apply won't ask it."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533/?x=")

    with caplog.at_level(logging.INFO):
        Config.report_navidrome()

    message = caplog.records[-1].getMessage()
    assert "can't reach Navidrome" in message and "fixed RETAG_RENAME_WAIT" in message
    assert not Config.navidrome_usable() and Config.navidrome_configured()


def test_the_rename_wait_row_names_the_fixed_wait_for_an_unusable_address(app, monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://me:pw@navidrome:4533")
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "20")
    _, row = find(app.get("/deadwax/settings").json(), "RETAG_RENAME_WAIT")
    assert "waits 20s" in row["effect"] and "asks Navidrome" not in row["effect"]


def test_the_start_up_report_names_what_is_missing(env, monkeypatch, caplog):
    monkeypatch.setattr(Config, "NAVIDROME_USER", None)
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", None)

    with caplog.at_level(logging.INFO):
        Config.report_navidrome()

    record = caplog.records[-1]
    assert record.levelno == logging.ERROR
    assert "NAVIDROME_USER and NAVIDROME_PASSWORD are not set" in record.getMessage()
    assert "only NAVIDROME_URL is there" in record.getMessage()


def test_the_start_up_report_says_where_the_address_came_from(env, monkeypatch, caplog):
    monkeypatch.setattr(Config, "OVERRIDDEN", {"NAVIDROME_URL"})

    with caplog.at_level(logging.INFO):
        Config.report_navidrome()

    assert "http://navidrome:4533 (from the settings tab)" in caplog.records[-1].getMessage()


def test_nothing_set_is_quietly_optional(env, monkeypatch, caplog):
    for key in Config.NAVIDROME_SETTINGS:
        monkeypatch.setattr(Config, key, None)

    with caplog.at_level(logging.INFO):
        Config.report_navidrome()

    assert caplog.records[-1].levelno == logging.INFO
    assert "player at /player/ is off" in caplog.records[-1].getMessage()


def test_check_leaves_navidrome_to_the_report(env, monkeypatch, caplog):
    """check() runs before the settings tab's overrides exist, so it says nothing about Navidrome."""
    #? check() corrects these two in place when they're unrecognised; keep that from leaking out
    monkeypatch.setattr(Config, "ORGANIZE_MODE", Config.ORGANIZE_MODE)
    monkeypatch.setattr(Config, "COVER_ART_SIZE", Config.COVER_ART_SIZE)

    with caplog.at_level(logging.INFO):
        Config.check()

    assert caplog.records, "check() did report something"
    assert "navidrome" not in json.dumps([r.getMessage() for r in caplog.records]).lower()
