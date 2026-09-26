"""
The image's HEALTHCHECK asks /deadwax/health whether this container is doing its job.

About deadwax alone: slskd logged out or MusicBrainz down is another service's problem, and
calling deadwax unhealthy for it would have an orchestrator restart a container that a restart
cannot fix. The one thing that does count is the download poller having stopped - without it
nothing is tracked or filed while the page goes on looking fine.
"""

from types import SimpleNamespace

from fastapi.testclient import TestClient

from src import __version__
from src.api.app import start


def client_with(poller):
    app = start()  # no `with`, so no lifespan: nothing connects to anything
    if poller is not None:
        app.state.poller_task = poller
    return TestClient(app)


def test_healthy_while_the_poller_runs():
    response = client_with(SimpleNamespace(done=lambda: False)).get("/deadwax/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": __version__, "poller": "running"}


def test_unhealthy_once_the_poller_has_stopped():
    response = client_with(SimpleNamespace(done=lambda: True)).get("/deadwax/health")
    assert response.status_code == 503
    assert response.json()["poller"] == "stopped"


def test_unhealthy_before_the_poller_ever_started():
    assert client_with(None).get("/deadwax/health").status_code == 503


def test_the_dockerfile_asks_the_same_address():
    from pathlib import Path
    dockerfile = (Path(__file__).resolve().parent.parent / "dockerfile").read_text()
    assert "HEALTHCHECK" in dockerfile
    assert "http://127.0.0.1:8080/deadwax/health" in dockerfile


# ----- the cache-header middleware, rewritten as plain ASGI in v0.9.8 -----
#
# It was @app.middleware("http") - Starlette's BaseHTTPMiddleware, whose wrapped receive made
# request.is_disconnected() answer False for every request, so an abandoned Soulseek search could
# never be noticed. The rewrite must set exactly the headers the old one did.

def test_the_interface_is_revalidated_and_hashed_assets_are_cached_hard():
    client = client_with(SimpleNamespace(done=lambda: False))
    assert client.get("/").headers["cache-control"] == "no-cache"
    assert client.get("/scripts/main.js").headers["cache-control"] == "no-cache"
    assert client.get("/styles/main.css").headers["cache-control"] == "no-cache"
    assert client.get("/dist/assets/app-0123abcd.js").headers["cache-control"] == \
        "public, max-age=31536000, immutable"


def test_the_api_is_left_alone():
    client = client_with(SimpleNamespace(done=lambda: False))
    assert "cache-control" not in client.get("/deadwax/health").headers


def test_no_middleware_hides_a_disconnect_from_the_routes():
    """BaseHTTPMiddleware is what broke is_disconnected() - none may come back."""
    from starlette.middleware.base import BaseHTTPMiddleware
    app = start()
    assert not any(m.cls is BaseHTTPMiddleware for m in app.user_middleware)
