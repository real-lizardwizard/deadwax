"""
Writes another website asks for are refused (v1.0.1).

deadwax has no login, and a page elsewhere could make the browser POST to it - FastAPI reads a
JSON body with no Content-Type, and the body-less routes take any form post. Browsers mark every
cross-origin POST with an Origin they can't be told to forge, so that is what is checked: a write
naming another host or port is refused, and one naming none at all (curl, scripts) goes through.
"""

from fastapi.testclient import TestClient

from src.api.app import start
from src.api.same_origin import refusal, trusted_origins

HOST = {"host": "192.168.1.20:8090"}


def ask(method="POST", **headers):
    return refusal(method, {**HOST, **{k.replace("_", "-"): v for k, v in headers.items()}}, trusted=[])


# ----- the rules -----

def test_deadwaxs_own_page_may_write():
    assert ask(origin="http://192.168.1.20:8090") is None


def test_another_website_may_not():
    assert "another website" in ask(origin="https://evil.example")


def test_another_port_on_the_same_box_is_another_website():
    """Navidrome, slskd and the NAS's admin page share the host - the port is what tells them apart."""
    assert ask(origin="http://192.168.1.20:4533") is not None
    assert ask(origin="http://192.168.1.20:5030") is not None


def test_reads_are_never_refused():
    """A GET changes nothing, and images, the log stream and audio are all GETs from wherever."""
    assert ask("GET", origin="https://evil.example") is None
    assert ask("HEAD", origin="https://evil.example") is None


def test_a_request_with_no_origin_at_all_goes_through():
    """curl, scripts and health checks send neither header, and were never the threat."""
    assert ask() is None


def test_the_referer_stands_in_when_there_is_no_origin():
    assert ask(referer="http://192.168.1.20:8090/player/") is None
    assert ask(referer="https://evil.example/page") is not None


def test_a_null_origin_is_refused():
    """What a sandboxed frame or a file:// page sends - never deadwax's own page."""
    assert "no web address" in ask(origin="null")


def test_a_host_header_without_a_port_means_the_default_one():
    """Behind a proxy on 443, Host has no port and the page's Origin is https."""
    assert refusal("POST", {"host": "music.example", "origin": "https://music.example"}, trusted=[]) is None
    assert refusal("POST", {"host": "music.example", "origin": "https://music.example:8443"}, trusted=[]) is not None


def test_a_proxy_that_rewrites_host_is_matched_by_x_forwarded_host():
    headers = {"host": "deadwax:8080", "x-forwarded-host": "music.example, proxy.internal",
               "origin": "https://music.example"}
    assert refusal("PUT", headers, trusted=[]) is None


def test_x_forwarded_port_fills_in_the_port_a_proxy_dropped():
    """nginx's $host has no port, so a proxy on 8443 passes plain "nas" (v1.0.2)."""
    headers = {"host": "nas", "x-forwarded-port": "8443", "origin": "https://nas:8443"}
    assert refusal("POST", headers, trusted=[]) is None
    assert refusal("POST", {**headers, "origin": "https://nas:9000"}, trusted=[]) is not None
    assert refusal("POST", {**headers, "x-forwarded-port": "junk"}, trusted=[]) is not None
    #? a Host that names its own port is taken at its word
    assert refusal("POST", {**headers, "host": "nas:8090"}, trusted=[]) is not None


def test_trusted_origins_names_the_rest():
    headers = {"host": "deadwax:8080", "origin": "https://music.example"}
    assert refusal("POST", headers, trusted=[]) is not None
    assert refusal("POST", headers, trusted=trusted_origins("https://music.example, junk")) is None


def test_hosts_compare_without_case_and_ipv6_hosts_work():
    assert refusal("POST", {"host": "Music.Example:8090", "origin": "http://music.example:8090"}, trusted=[]) is None
    assert refusal("POST", {"host": "[::1]:8090", "origin": "http://[::1]:8090"}, trusted=[]) is None


def test_trusted_origins_reads_the_environment(monkeypatch):
    monkeypatch.setenv("TRUSTED_ORIGINS", "https://music.example")
    assert trusted_origins() == [("music.example", 443)]


# ----- wired into the real app -----

def test_the_real_app_refuses_a_foreign_write_before_any_route_runs():
    client = TestClient(start())  # no lifespan: nothing connects to anything
    response = client.post("/deadwax/download/enqueue", json={}, headers={"Origin": "https://evil.example"})
    assert response.status_code == 403
    assert "another website" in response.json()["detail"]


def test_the_real_app_lets_its_own_page_through():
    """The same empty body gets as far as validation (422), so the guard didn't stop it."""
    client = TestClient(start())
    origin = f"{client.base_url.scheme}://{client.base_url.netloc.decode()}"
    response = client.post("/deadwax/download/enqueue", json={}, headers={"Origin": origin})
    assert response.status_code == 422


def test_the_guard_is_plain_asgi_and_outermost():
    """Plain ASGI keeps is_disconnected() working; outermost means nothing runs before it."""
    from src.api.same_origin import SameOriginWrites
    app = start()
    assert app.user_middleware[0].cls is SameOriginWrites
