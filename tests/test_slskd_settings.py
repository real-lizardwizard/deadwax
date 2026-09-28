"""
slskd's address and key, saved through the real app (v1.0.5) - the rule 1.0.3 made for Navidrome.

Every request to SLSKD_URL carries SLSKD_APIKEY, and that key is full control of slskd: searches,
downloads, its shares, its settings. deadwax has no login, so anyone who can reach it can save a
setting - and re-pointing the address alone would send the saved key to whatever was typed on the
next ping or search. What these protect:

  - the address can't be pointed somewhere new without the key being typed with it;
  - an address that would carry more than slskd's address - a login, a query - is refused, from
    the settings tab and, by the client, from compose or .env;
  - a login typed into an address never comes back out, in a refusal or in the payload;
  - saving the address and the key together works, and drops the cached client.

Built with start() and no lifespan, as test_navidrome_settings.py is, so the middleware is the
real app's and nothing connects to anything. The store is a throwaway database per test.
"""

import asyncio
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api import slskd_endpoint  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.slskd_endpoint import SlskdClient  # noqa: E402
from src.config import Config  # noqa: E402
from src.store import JobStore  # noqa: E402

ENV_URL = "http://slskd:5030"
ENV_KEY = "env-apikey-3e9a"
NEW_KEY = "typed-apikey-72bd"
MOVED = "type the slskd API key again with the new address"


@pytest.fixture
def env(monkeypatch):
    """slskd as the environment supplied it, nothing overridden yet."""
    monkeypatch.setattr(Config, "SLSKD_URL", ENV_URL)
    monkeypatch.setattr(Config, "SLSKD_APIKEY", ENV_KEY)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "env-password-8c1f")
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})


@pytest.fixture
def store(tmp_path):
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    return store


@pytest.fixture
def slskd():
    """The app's slskd client, already built, as it is after the first ping."""
    client = SlskdClient()
    client.client = object()  # stands in for slskd_api's client: nothing may call it
    return client


@pytest.fixture
def app(env, store, slskd):
    app = start()
    app.state.store = store
    app.state.slskd_client = slskd  # the lifespan's job, which doesn't run here
    return TestClient(app)  # no `with`, so no lifespan: nothing connects


def save(app: TestClient, **values):
    return app.put("/deadwax/settings", json=[{"key": key, "value": value} for key, value in values.items()])


def find(payload: dict, key: str) -> dict:
    for group in payload["groups"]:
        for setting in group["settings"]:
            if setting["key"] == key:
                return setting
    raise AssertionError(f"{key} is not in the settings payload")


# ----- saving the address -----

def test_a_new_address_with_the_key_is_saved_and_the_client_rebuilt(app, store, slskd):
    response = save(app, SLSKD_URL="http://slskd-box:5030", SLSKD_APIKEY=NEW_KEY)

    assert response.status_code == 200
    assert store.stored_settings() == {"SLSKD_URL": "http://slskd-box:5030", "SLSKD_APIKEY": NEW_KEY}
    assert (Config.SLSKD_URL, Config.SLSKD_APIKEY) == ("http://slskd-box:5030", NEW_KEY)
    assert slskd.client is None, "the old address's client is gone"
    row = find(response.json(), "SLSKD_URL")
    assert (row["value"], row["overridden"], row["status"]) == ("http://slskd-box:5030", True, "ok")
    assert NEW_KEY not in response.text and ENV_KEY not in response.text


def test_a_new_address_without_the_key_is_refused(app, store, slskd):
    """What anyone who can reach deadwax could otherwise do: collect slskd's API key."""
    built = slskd.client
    response = save(app, SLSKD_URL="http://collector.example:9999")

    assert response.status_code == 400
    assert response.json()["detail"] == (
        f"SLSKD_URL: {MOVED} - deadwax won't send the saved one to an address it wasn't entered for"
    )
    assert store.stored_settings() == {}
    assert Config.SLSKD_URL == ENV_URL
    assert slskd.client is built, "the client for the real address is untouched"


def test_reverting_or_blanking_the_key_is_not_typing_it(app, store):
    for key in (None, "", "   "):
        response = save(app, SLSKD_URL="http://slskd-box:5030", SLSKD_APIKEY=key)
        assert response.status_code == 400 and MOVED in response.json()["detail"], repr(key)
    assert store.stored_settings() == {}


def test_saving_the_address_it_already_is_is_not_a_change(app, store):
    assert save(app, SLSKD_URL=ENV_URL).status_code == 200


def test_clearing_the_address_is_refused_as_unset_not_as_moved(app, store):
    """slskd is required, so an empty address was never allowed - and nothing is sent to one."""
    response = save(app, SLSKD_URL="")
    assert response.status_code == 400
    assert response.json()["detail"] == "SLSKD_URL: not set"


def test_reverting_the_address_goes_back_to_the_environments(app, store):
    """The environment's address is the admin's own, and reverting is how the tab gets back to it."""
    assert save(app, SLSKD_URL="http://slskd-box:5030", SLSKD_APIKEY=NEW_KEY).status_code == 200

    response = save(app, SLSKD_URL=None)

    assert response.status_code == 200
    assert Config.SLSKD_URL == ENV_URL
    assert store.stored_settings() == {"SLSKD_APIKEY": NEW_KEY}


def test_with_no_key_set_there_is_nothing_to_keep_from_a_new_address(app, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_APIKEY", None)
    assert save(app, SLSKD_URL="http://slskd-box:5030").status_code == 200


def test_a_new_key_alone_needs_no_address(app, store):
    assert save(app, SLSKD_APIKEY=NEW_KEY).status_code == 200


def test_each_address_needs_its_own_secret(app, store):
    """Typing Navidrome's password doesn't carry slskd's new address, and the batch is all or nothing."""
    response = save(app, SLSKD_URL="http://slskd-box:5030",
                    NAVIDROME_URL="http://music-box:4533", NAVIDROME_PASSWORD="typed-password-51d0")

    assert response.status_code == 400
    detail = response.json()["detail"]
    assert detail.startswith(f"SLSKD_URL: {MOVED}") and "NAVIDROME" not in detail
    assert store.stored_settings() == {}


def test_both_addresses_moved_without_either_secret_names_both(app, store):
    response = save(app, SLSKD_URL="http://slskd-box:5030", NAVIDROME_URL="http://music-box:4533")
    detail = response.json()["detail"]
    assert response.status_code == 400
    assert MOVED in detail and "type the Navidrome password again" in detail


def test_a_page_elsewhere_cannot_save_it_at_all(app, store):
    response = app.put("/deadwax/settings", headers={"Origin": "http://192.168.1.20:5030"},
                       json=[{"key": "SLSKD_URL", "value": "http://x:1"},
                             {"key": "SLSKD_APIKEY", "value": NEW_KEY}])
    assert response.status_code == 403
    assert store.stored_settings() == {}


@pytest.mark.parametrize("url, reason", [
    ("slskd:5030", "scheme"),
    ("ftp://slskd:5030", "scheme"),
    ("http://", "no host"),
    ("http://:5030", "no host"),
    ("http://me:secret@slskd:5030", "user name or password"),
    ("http://me@slskd:5030", "user name or password"),
    ("http://slskd:5030/?x=", "? or #"),
    ("http://evil.example/any/path?", "? or #"),
    ("http://slskd:5030#", "? or #"),
    ("http://slskd:port", "port"),
    ("http://sl skd:5030", "space"),
])
def test_an_address_that_carries_more_than_slskds_is_refused(app, store, url, reason):
    response = save(app, SLSKD_URL=url, SLSKD_APIKEY=NEW_KEY)

    assert response.status_code == 400
    assert response.json()["detail"].startswith("SLSKD_URL: ")
    assert reason in response.json()["detail"]
    assert MOVED not in response.json()["detail"], "an unusable address is told that, not this"
    assert store.stored_settings() == {}


def test_refusing_an_address_never_quotes_a_login_typed_into_it(app, store):
    """With no scheme, the refusal used to suggest "use http://<the value>" - password and all."""
    for url in ("me:secret-pw@slskd:5030", "http://me:secret-pw@slskd:5030"):
        response = save(app, SLSKD_URL=url, SLSKD_APIKEY=NEW_KEY)
        assert response.status_code == 400
        assert "secret-pw" not in response.text


def test_a_url_base_is_allowed(app, store):
    """slskd's own URL base, or a reverse proxy's subpath."""
    response = save(app, SLSKD_URL="https://nas.example/slskd", SLSKD_APIKEY=NEW_KEY)
    assert response.status_code == 200


# ----- an address from compose or .env -----

def test_the_client_refuses_an_unusable_address_from_the_environment(monkeypatch):
    """It never met the settings tab's check, so the client makes it, and sends slskd nothing."""
    monkeypatch.setattr(Config, "SLSKD_URL", "http://me:hunter2@slskd:5030")
    monkeypatch.setattr(Config, "SLSKD_APIKEY", ENV_KEY)
    monkeypatch.setattr(slskd_endpoint.slskd_api, "SlskdClient",
                        lambda **kwargs: pytest.fail("a client was built for the address"))

    with pytest.raises(ValueError) as refused:
        asyncio.run(SlskdClient().get_client())

    assert "user name or password" in str(refused.value)
    assert "hunter2" not in str(refused.value)


def test_a_login_in_an_address_from_the_environment_is_masked_on_its_row(app, monkeypatch):
    """Saving refuses one; one that came from compose is flagged, and shown without the password."""
    monkeypatch.setattr(Config, "SLSKD_URL", "http://me:hunter2@slskd:5030")
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://me:hunter3@navidrome:4533/music")

    response = app.get("/deadwax/settings")

    assert "hunter" not in response.text
    slskd, navidrome = find(response.json(), "SLSKD_URL"), find(response.json(), "NAVIDROME_URL")
    assert slskd["value"] == "http://•••@slskd:5030"
    assert slskd["status"] == "error" and "user name or password" in slskd["detail"]
    assert navidrome["value"] == "http://•••@navidrome:4533/music"


def test_the_environments_address_is_masked_in_what_reverting_would_restore(app, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_URL", "http://me:hunter2@slskd:5030")
    assert save(app, SLSKD_URL="http://slskd-box:5030", SLSKD_APIKEY=NEW_KEY).status_code == 200

    response = app.get("/deadwax/settings")

    assert "hunter" not in response.text
    assert find(response.json(), "SLSKD_URL")["env_value"] == "http://•••@slskd:5030"


def test_the_start_up_check_never_logs_a_login_in_the_address(env, monkeypatch, caplog):
    #? check() corrects these two in place when they're unrecognised; keep that from leaking out
    monkeypatch.setattr(Config, "ORGANIZE_MODE", Config.ORGANIZE_MODE)
    monkeypatch.setattr(Config, "COVER_ART_SIZE", Config.COVER_ART_SIZE)

    for url in ("http://me:hunter2@slskd:5030", "me:hunter2@slskd:5030"):
        monkeypatch.setattr(Config, "SLSKD_URL", url)
        Config.check()

    assert "SLSKD_URL is unusable (has a user name or password in it" in caplog.text
    assert "SLSKD_URL is unusable (missing the scheme" in caplog.text
    assert "hunter2" not in caplog.text and ENV_KEY not in caplog.text
