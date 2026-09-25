"""
What deadwax says when slskd refuses a search, and what it says about slskd's connection.

This is the second entry on the "what the tests cannot tell you" list coming true, after
"Completed, Rejected". Searching a live slskd failed with

    Error searching slskd: 409 Client Error: Conflict for url: http://.../api/v0/searches

which names a status whose meaning is the opposite of what it says: slskd maps
InvalidOperationException to Conflict, and the only thing throwing one on that path is
Soulseek.NET refusing to search while the server connection is down. slskd had put exactly that
sentence in the response BODY, which requests' HTTPError drops.

None of this can be caught by talking to slskd, which is the point of testing it from fixtures:
the payloads here are slskd's own documented shapes, so a refusal can be rehearsed without one.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402
from requests.exceptions import HTTPError  # noqa: E402

from src.api.slskd_endpoint import (SEARCH_REFUSALS, SlskdSearchRefused,  # noqa: E402
                                    describe_search_refusal, describe_server_state, slskd_said)


class FakeResponse:
    """A requests response, as far as reading an error out of one goes."""

    def __init__(self, status_code=409, body=None, text=""):
        self.status_code = status_code
        self._body = body
        self.text = text

    def json(self):
        if self._body is None:
            raise ValueError("no json here")
        return self._body


def refusal(status=409, body=None, text=""):
    """The HTTPError requests raises for a refused search, carrying slskd's own body."""
    return HTTPError(
        f"{status} Client Error: Conflict for url: http://gluetun-slskd:5030/api/v0/searches",
        response=FakeResponse(status, body, text),
    )


#? what slskd 0.2x actually returns: a bare string, serialized as JSON because the controller
#? declares [Produces("application/json")]
NOT_CONNECTED_BODY = (
    "The server connection must be connected and logged in to perform a search "
    "(currently: Disconnected)"
)


# ── reading what slskd said ──────────────────────────────────────────────────────────────

def test_the_reason_is_read_out_of_the_body_not_the_status_line():
    #? the whole bug: requests renders the exception as its status line and keeps the body to
    #? itself, so this is the sentence that was being thrown away
    assert slskd_said(refusal(body=NOT_CONNECTED_BODY)) == NOT_CONNECTED_BODY


def test_a_problem_details_object_is_read_too():
    said = slskd_said(refusal(body={"title": "Conflict", "detail": NOT_CONNECTED_BODY}))
    assert said == NOT_CONNECTED_BODY


def test_plain_text_is_read_when_it_is_not_json():
    assert slskd_said(refusal(text="  not   logged in  ")) == "not logged in"


def test_a_body_that_is_somebody_elses_html_is_not_quoted():
    #? a proxy or a login portal in front of slskd - a screenful of markup in the log helps
    #? nobody, and our own headline is better than it
    assert slskd_said(refusal(text="<html><body>502 Bad Gateway</body></html>")) == ""


def test_an_error_with_no_response_at_all_says_nothing():
    assert slskd_said(HTTPError("connection reset")) == ""


# ── explaining the status ────────────────────────────────────────────────────────────────

def test_409_is_explained_as_a_connection_and_not_as_a_conflict():
    said = describe_search_refusal(409, NOT_CONNECTED_BODY)
    assert "not connected to the Soulseek network" in said
    #? and slskd's own words survive rather than being replaced by our summary of them
    assert NOT_CONNECTED_BODY in said
    assert "Conflict" not in said


def test_429_is_the_one_search_at_a_time_limiter():
    assert "one at a time" in describe_search_refusal(429)


def test_an_unknown_status_still_names_itself():
    assert "HTTP 418" in describe_search_refusal(418)


def test_a_live_connection_reading_wins_over_the_canned_headline():
    #? more specific and more current than a status code, so it replaces it outright
    assert describe_search_refusal(409, NOT_CONNECTED_BODY, "slskd is waiting for its VPN") == \
        "slskd is waiting for its VPN"


def test_every_sentence_names_slskd_as_its_subject():
    #? the string is shown on its own in the log AND after "search failed: " in the panel, so
    #? one that opened with "could not search" would stutter in the second
    for status in list(SEARCH_REFUSALS) + [418, None]:
        assert describe_search_refusal(status, NOT_CONNECTED_BODY).startswith(
            ("slskd", "this slskd")
        ), status


# ── what slskd says about its own connection ─────────────────────────────────────────────

def server(**flags):
    state = {"address": "vps.slsknet.org", "state": "Disconnected", "isConnected": False,
             "isConnecting": False, "isLoggedIn": False, "isLoggingIn": False,
             "isTransitioning": False}
    state.update(flags)
    return {"version": {}, "server": state}


def test_connected_and_logged_in_is_the_only_state_a_search_can_run_in():
    described = describe_server_state(
        server(state="Connected, LoggedIn", isConnected=True, isLoggedIn=True)
    )
    assert described["ok"] is True


def test_the_api_answering_while_soulseek_is_down_is_reported_as_down():
    #? the bug this fixes: slskd answers its own API perfectly while logged out, so the pill
    #? read "ok" right up until the first search failed, and then the search took the blame
    described = describe_server_state(server())
    assert described["ok"] is False
    assert described["code"] == "NOT_CONNECTED"
    assert "Disconnected" in described["detail"]


def test_reaching_the_server_without_logging_in_points_at_the_credentials():
    described = describe_server_state(
        server(state="Connected", isConnected=True, isLoggedIn=False)
    )
    assert described["code"] == "NOT_LOGGED_IN"
    assert "username and password" in described["detail"]


def test_connecting_is_its_own_state_because_it_passes():
    described = describe_server_state(
        server(state="Connecting", isConnecting=True, isTransitioning=True)
    )
    assert described["ok"] is False
    assert described["code"] == "CONNECTING"


def test_waiting_for_a_vpn_is_named_because_that_is_the_whole_answer():
    #? slskd here runs inside a VPN container, where this is the difference between "not
    #? connected" and knowing which container to look at
    described = describe_server_state({
        **server(),
        "connectionWatchdog": {"isEnabled": True, "isAttemptingConnection": False,
                               "isAwaitingVpn": True},
    })
    assert "waiting for its VPN" in described["detail"]


def test_a_reconnection_in_progress_is_named_as_well():
    described = describe_server_state({
        **server(),
        "connectionWatchdog": {"isEnabled": True, "isAttemptingConnection": True,
                               "isAwaitingVpn": False},
    })
    assert "trying to reconnect" in described["detail"]


def test_an_slskd_too_old_to_report_its_connection_is_left_alone():
    #? absence of the field is not evidence of a disconnection, and a red pill on a working
    #? install is the worse of the two mistakes
    assert describe_server_state({"version": {}})["ok"] is True
    assert describe_server_state({"version": {}, "server": {}})["ok"] is True
    assert describe_server_state(None)["ok"] is True


# ── the search itself ────────────────────────────────────────────────────────────────────

class FakeSearches:
    def __init__(self, error=None):
        self.error = error

    def search_text(self, **kwargs):
        if self.error:
            raise self.error
        return {"id": "search-1", "isComplete": True}

    def state(self, search_id):
        return {"id": search_id, "isComplete": True}

    def search_responses(self, search_id):
        return [{"username": "bob", "files": []}]

    def delete(self, search_id):
        return True


class FakeApplication:
    def __init__(self, state=None):
        self.state_payload = state
        self.reads = 0

    def state(self):
        self.reads += 1
        if self.state_payload is None:
            raise RuntimeError("slskd went away")
        return self.state_payload


class FakeSlskdApi:
    def __init__(self, error=None, state=None):
        self.searches = FakeSearches(error)
        self.application = FakeApplication(state)


def run_search(api):
    from src.api.slskd_endpoint import SlskdClient
    client = SlskdClient()
    #? already built, so get_client() hands it straight back without touching Config
    client.client = api
    return asyncio.run(client.search("portishead dummy", poll_interval=0, max_wait=0))


def test_a_search_that_works_still_works():
    assert run_search(FakeSlskdApi()) == [{"username": "bob", "files": []}]


def test_a_refused_search_raises_the_reason_not_the_status_line():
    api = FakeSlskdApi(
        error=refusal(body=NOT_CONNECTED_BODY),
        state=server(),
    )

    with pytest.raises(SlskdSearchRefused) as caught:
        run_search(api)

    #? the live connection reading is what the user ends up seeing
    assert "not connected to the Soulseek server" in str(caught.value)
    assert caught.value.status == 409
    assert api.application.reads == 1


def test_the_diagnosis_never_replaces_the_error_it_explains():
    #? asking slskd how it is doing is a bonus; slskd being unreachable for THAT must not turn
    #? a refused search into an unrelated traceback
    api = FakeSlskdApi(error=refusal(body=NOT_CONNECTED_BODY), state=None)

    with pytest.raises(SlskdSearchRefused) as caught:
        run_search(api)

    assert NOT_CONNECTED_BODY in str(caught.value)


def test_only_a_connection_refusal_costs_a_second_request():
    #? one extra call, on the failure path, for the one status a connection explains
    api = FakeSlskdApi(error=refusal(status=429, text="Only one concurrent operation is permitted"))

    with pytest.raises(SlskdSearchRefused):
        run_search(api)

    assert api.application.reads == 0


def test_a_payload_that_is_not_an_object_is_not_a_disconnection():
    #? a proxy or an error page in slskd's place is the ping's own HTTP handling to notice, not
    #? something to render as "your Soulseek connection is down"
    for payload in ([], "Disconnected", 0):
        assert describe_server_state(payload)["ok"] is True, payload
    assert describe_server_state({"server": "Disconnected"})["ok"] is True
