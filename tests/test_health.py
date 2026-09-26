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
