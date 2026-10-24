"""
Errors and connections in a listener's words (2.0.4, UX batch 1) - the server's half.

The app says every error in a listener's words (ui/src/lib/errorWords.ts, pinned by ui/test/errors.sim.cjs); what
the server owes it is sentences where it sends words at all:

- the sign-in and a session's refusals hold no setting, address or exception: where whoever runs deadwax needs one
  (DEADWAX_SECRET_KEY, DB_PATH, Navidrome's own words), deadwax answers in two halves - src/auth.py's Explained, as
  {"detail", "why"} - `detail` for anyone, `why` for them - and the status is what it always was;
- You -> Connections' slskd row: a sentence under each code (PING_WORDS), never the log's own line;
- a playlist saved in part says so in a sentence, Navidrome's words as its why.
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from requests.exceptions import ConnectionError as RequestsConnectionError, HTTPError, InvalidURL  # noqa: E402

from src import auth, playlists  # noqa: E402
from src.api.slskd_endpoint import PING_WORDS, PING_WORDS_NOT_ADMIN, SlskdClient  # noqa: E402
from src.config import Config  # noqa: E402
from tests import test_logins  # noqa: E402
from tests.test_logins import ME, PASSWORDS, sign_in, signed_in  # noqa: E402

#? the logins tests' fixture - an app with logins on, its store and a fake Navidrome
on = test_logins.on

#? what a listener must never be shown: a setting's name, an address, an exception's name, an errno
SETTING = re.compile(r"\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b")
PLUMBING = re.compile(r"https?://|\b[A-Za-z]*(Error|Exception)\b|Errno|Traceback|HTTPConnectionPool")


def listener_fit(words: str) -> bool:
    return not SETTING.search(words) and not PLUMBING.search(words)


# ---------------------------------------------------------------- the sign-in's and a session's words

#? every sentence a request with logins on can be answered with that reaches someone who isn't an admin - the
#? break-glass admin's own (BREAK_GLASS_ENDED) names its setting on purpose: only they ever read it
LISTENER_WORDS = ["SIGN_IN", "SIGNED_OUT", "EXPIRED", "LOGIN_GONE", "KEY_CHANGED", "NO_DATABASE", "CANT_SIGN_IN",
                  "NAVIDROME_UNSET", "NAVIDROME_REFUSED", "LDAP_ACCOUNT", "WRONG_LOGIN", "PASSWORD_RESET",
                  "ACCOUNT_REMOVED", "PASSWORD_CHANGED", "RESERVED_SESSION"]


@pytest.mark.parametrize("name", LISTENER_WORDS)
def test_no_sign_in_or_session_word_holds_a_setting_or_an_exception(name):
    words = getattr(auth, name)
    assert listener_fit(words), f"{name}: {words!r}"
    assert "WireGuard" not in words


def test_whoever_runs_deadwax_keeps_the_setting_as_the_why():
    assert "DB_PATH" in auth.NO_DATABASE_WHY
    assert auth.no_database().why == auth.NO_DATABASE_WHY and auth.no_database().status_code == 503
    assert auth.cant_sign_in("Logins are on, but x").why == "Logins are on, but x"


def test_no_secret_key_says_nobody_can_sign_in_and_names_the_key_only_as_the_why(on, monkeypatch):
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", None)
    for response in (on.client.get(ME), sign_in(on.client, "ethan", PASSWORDS["ethan"])):
        assert response.status_code == 503
        body = response.json()
        assert body["detail"] == auth.CANT_SIGN_IN
        assert "DEADWAX_SECRET_KEY" in body["why"] and "DEADWAX_SECRET_KEY" not in body["detail"]


def test_organizing_off_says_so_only_in_the_why(on, monkeypatch):
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    body = on.client.get(ME).json()
    assert body["detail"] == auth.CANT_SIGN_IN and "ORGANIZE_MODE" in body["why"]


def test_a_database_that_cant_be_read_is_said_in_two_halves(on):
    ethan = signed_in(on, "ethan")
    on.store.available = False
    response = ethan.get(ME)
    assert response.status_code == 503
    assert response.json() == {"detail": auth.NO_DATABASE, "why": auth.NO_DATABASE_WHY}
    login = sign_in(TestClient(on.app), "ethan", PASSWORDS["ethan"])
    assert login.status_code == 503 and login.json()["why"] == auth.NO_DATABASE_WHY


def test_navidrome_not_set_up_at_sign_in_names_its_setting_only_as_the_why(on, monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"])
    assert response.status_code == 503
    assert response.json()["detail"] == auth.NAVIDROME_UNSET
    assert "NAVIDROME_URL" in response.json()["why"]


def test_navidrome_answering_oddly_at_sign_in_keeps_its_words_for_the_why(on):
    on.fake.code = 0   # an error code Navidrome has, but deadwax has no words for
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"])
    assert response.status_code == 502
    assert response.json()["detail"] == auth.NAVIDROME_REFUSED and "Navidrome said" in response.json()["why"]


def test_an_ldap_account_is_told_what_to_ask_for(on):
    on.fake.code = 41
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"])
    assert response.status_code == 502
    assert response.json()["detail"] == auth.LDAP_ACCOUNT and "token" in response.json()["why"]


def test_navidrome_down_at_sign_in_is_still_said_plainly_with_no_why(on):
    on.fake.down = True
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"])
    assert response.status_code == 503
    assert "isn't answering" in response.json()["detail"] and "why" not in response.json()


def test_a_wrong_password_is_still_a_plain_401(on):
    response = sign_in(on.client, "ethan", "nope-nope-nope")
    assert response.status_code == 401 and response.json() == {"detail": auth.WRONG_LOGIN}


# ---------------------------------------------------------------- You -> Connections, slskd's row

class _App:
    def __init__(self, outcome):
        self.outcome = outcome

    def state(self):
        if isinstance(self.outcome, BaseException):
            raise self.outcome
        return self.outcome


class _Response:
    def __init__(self, status):
        self.status_code = status


def ping(outcome, admin: bool = True) -> dict:
    client = SlskdClient()
    client.client = type("Api", (), {"application": _App(outcome)})()
    return asyncio.run(client.ping(admin=admin))


@pytest.mark.parametrize("outcome, code", [
    (RequestsConnectionError("HTTPConnectionPool(host='slskd', port=5030): Max retries exceeded"), "CONNECTION_ERROR"),
    (HTTPError("401", response=_Response(401)), 401),
    (HTTPError("502", response=_Response(502)), 502),
    (HTTPError("418", response=_Response(418)), "UNKNOWN_HTTP_ERROR"),
    ({}, "NO_STATE"),
    (RuntimeError("boom"), "UNKNOWN_ERROR"),
    (InvalidURL("Invalid URL 'x': No scheme supplied"), "UNKNOWN_ERROR"),
])
def test_each_ping_failure_has_a_sentence_and_keeps_its_code(outcome, code):
    answer = ping(outcome)
    assert answer["status"] == "failed" and answer["code"] == code
    words = answer["error"]
    #? (review) each code's own sentence, whole - a test that let anything starting "slskd" through pinned none of them
    expected = PING_WORDS["UNKNOWN_HTTP_ERROR"].format(status=418) if code == "UNKNOWN_HTTP_ERROR" else PING_WORDS[code]
    assert words == expected
    #? a sentence - never the log's own line, nor the exception
    assert words.endswith(".") and (words[0].isupper() or words.startswith(("slskd", "deadwax")))
    assert not re.search(r"couldnt|didnt|functionality enabled|no auth checked|HTTPConnectionPool|boom", words), words


def test_the_ping_sentences_name_where_to_fix_it():
    assert "SLSKD_URL" in PING_WORDS["CONNECTION_ERROR"] and "Server settings" in PING_WORDS["CONNECTION_ERROR"]
    assert "SLSKD_APIKEY" in PING_WORDS[401]
    assert PING_WORDS["UNKNOWN_HTTP_ERROR"].format(status=418).count("418") == 1


@pytest.mark.parametrize("outcome, code", [
    (RequestsConnectionError("HTTPConnectionPool(host='slskd', port=5030)"), "CONNECTION_ERROR"),
    (HTTPError("401", response=_Response(401)), 401),
])
def test_someone_who_isnt_an_admin_is_never_sent_to_change_slskds_address_or_key(outcome, code):
    """(review) SLSKD_URL and SLSKD_APIKEY are an admin's alone (routes/settings.py ADMINS_ONLY) - locked on the page
    of someone with Settings and the log, who reads these rows too: they are told only an admin can change them."""
    from src.routes.settings import ADMINS_ONLY
    theirs, admins = ping(outcome, admin=False)["error"], ping(outcome)["error"]
    assert theirs == PING_WORDS_NOT_ADMIN[code] and "only an admin" in theirs and "check SLSKD" not in theirs
    assert admins == PING_WORDS[code] and "only an admin" not in admins
    assert {"SLSKD_URL", "SLSKD_APIKEY"} <= set(ADMINS_ONLY)


def test_an_slskd_not_set_up_tells_someone_who_isnt_an_admin_that_an_admin_sets_it(monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_URL", "http://slskd:5030")
    monkeypatch.setattr(Config, "SLSKD_APIKEY", None)
    answer = asyncio.run(SlskdClient().ping(admin=False))
    assert answer["code"] == "NOT_SET_UP" and answer["error"].endswith("only an admin can set it, in Server settings (Connections).")


def test_the_ping_route_says_its_sentences_for_the_reader(on, monkeypatch):
    """The route asks the words by who is reading: an admin (james) the setting to change, anyone else (ethan) that
    an admin changes it."""
    asked = []

    class Slskd:
        async def ping(self, admin=True):
            asked.append(admin)
            return {"status": "failed", "code": 401, "error": "x"}
    monkeypatch.setattr(on.app.state, "slskd_client", Slskd(), raising=False)
    for name in ("james", "ethan"):
        assert signed_in(on, name).get("/deadwax/monitor_slskd/ping").status_code == 200
    assert asked == [True, False]


def test_an_slskd_not_set_up_says_which_setting(monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_URL", "slskd:5030")   # no scheme
    client = SlskdClient()
    answer = asyncio.run(client.ping())
    assert answer["code"] == "NOT_SET_UP" and answer["error"].startswith("SLSKD_URL is unusable")
    monkeypatch.setattr(Config, "SLSKD_URL", "http://slskd:5030")
    monkeypatch.setattr(Config, "SLSKD_APIKEY", None)
    answer = asyncio.run(SlskdClient().ping())
    assert answer["code"] == "NOT_SET_UP" and "SLSKD_APIKEY" in answer["error"]


def test_slskd_logged_out_keeps_slskds_own_words():
    answer = ping({"server": {"state": "Disconnected", "isConnected": False, "isLoggedIn": False}})
    assert answer["code"] == "NOT_CONNECTED" and "not connected to the Soulseek server" in answer["error"]


# ---------------------------------------------------------------- a playlist saved in part

def test_a_playlist_saved_in_part_says_so_in_a_sentence():
    for words in (playlists.PART_SAVED, playlists.SAVED_UNREAD):
        assert "{" not in words and words.endswith(".")


def test_the_app_answers_an_explained_refusal_as_its_two_halves():
    """The handler is registered (the answers above come through it: their status the HTTPException's, the body
    {"detail", "why"}); an Explained is an HTTPException, so anything catching those still catches it."""
    from fastapi import HTTPException
    from src.api.app import start
    assert auth.Explained in start().exception_handlers
    assert isinstance(auth.Explained(503, "a", "b"), HTTPException)
