"""
`GET /deadwax/me` and the `current_user` dependency behind it (2.0.0-player.9) - the seam logins
(step 3 of the multi-user plan) will fill in. Through the real app, start(), so every middleware is
in the way, as the page meets it.
"""

from fastapi.testclient import TestClient

from src import __version__
from src.api.app import start
from src.routes import me
from src.users import LOCAL_USER, current_user


def test_logins_off_means_the_one_implicit_admin():
    response = TestClient(start()).get("/deadwax/me")  # no `with`: no lifespan, nothing connects

    assert response.status_code == 200
    assert response.json() == {"user": "local", "admin": True, "auth": "off", "version": __version__}


def test_the_user_comes_from_the_dependency_not_from_the_route():
    """Step 3 changes current_user() and nothing else: the route has to be reading it."""
    app = start()
    app.dependency_overrides[current_user] = lambda: "james"

    body = TestClient(app).get("/deadwax/me").json()

    assert body["user"] == "james"
    #? only the implicit user is the admin while logins are off - step 3 decides who else is
    assert body["admin"] is False


def test_current_user_is_a_dependency_of_the_route_never_middleware():
    """A dependency is named in the route's signature - so which routes are per user can be read
    off the routes - and costs nothing on the requests that don't ask."""
    [route] = [r for r in me.router.routes if r.path == ""]

    assert current_user in [d.call for d in route.dependant.dependencies]


def test_the_implicit_user_is_local():
    assert current_user() == LOCAL_USER == "local"


def test_only_a_get():
    client = TestClient(start())
    assert client.post("/deadwax/me").status_code == 405
