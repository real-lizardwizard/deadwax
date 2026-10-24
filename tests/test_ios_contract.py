"""
The iPhone app's contract with the server (notes/ios.md): every route the app calls, read from its own
source (ios/DeadwaxKit/Sources/DeadwaxCore/Routes.swift's `Endpoint(...)` lines), must be a route the
server has, with the method the app uses, every path parameter named as the server names it, and every
query parameter one the server declares - FastAPI ignores an undeclared one without a word, so a
renamed parameter would leave the app asking for the wrong thing and getting an answer anyway.

And what the app decodes must be there: the fields its models need (the non-optional `let`s of
Health and Me in Models.swift) in the server's real answers, the sign-in form's fields, the session
cookie's name (and the sign-in's own answer, with a session the server takes back), search's `albums`
and `songs` - and every number the app sends (page sizes, offsets, the cover's size) within the bounds
the server declares. A server change that would break the app fails here,
in the Python suite, where the server is changed - the app is built only on a Mac.
"""

import re
import sys
from pathlib import Path
from types import SimpleNamespace

from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import navidrome  # noqa: E402
from src.routes.auth import SignIn  # noqa: E402
from src.store import JobStore  # noqa: E402

CORE = Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
ENDPOINT = re.compile(r'Endpoint\(method: "(\w+)", path: "([^"]+)", query: \[([^\]]*)\]\)')


def endpoints() -> list[tuple[str, str, list[str]]]:
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    found = []
    for method, path, query in ENDPOINT.findall(text):
        found.append((method, path, re.findall(r'"([^"]+)"', query)))
    return found


def required_fields(struct: str) -> set[str]:
    """The non-optional stored properties of a struct in Models.swift - what decoding needs."""
    text = (CORE / "Models.swift").read_text(encoding="utf-8")
    body = re.search(r"public struct " + struct + r"\b[^{]*\{(.*?)\n\}", text, re.S)
    assert body, f"no struct {struct} in Models.swift"
    return {name for name, kind in re.findall(r"public let (\w+): ([\w\[\]]+\??)", body.group(1))
            if not kind.endswith("?")}


def app_routes() -> dict[tuple[str, str], APIRoute]:
    routes = {}
    for route in start().routes:
        if isinstance(route, APIRoute):
            for method in route.methods:
                routes[(method, route.path)] = route
    return routes


def test_the_app_names_its_routes_in_the_form_this_test_reads():
    found = endpoints()
    # Routes.all in the Swift lists seven; a line in another form would be missed here, silently
    assert len(found) == 7
    assert len({(m, p) for m, p, _ in found}) == 7


def test_every_route_the_app_calls_is_the_servers_with_its_parameters(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    routes = app_routes()
    for method, path, query in endpoints():
        route = routes.get((method, path))
        assert route is not None, f"the app calls {method} {path}, which the server doesn't have"
        declared = {field.alias for field in route.dependant.query_params}
        assert set(query) <= declared, f"{path}: the app sends {sorted(set(query) - declared)}, which the server ignores"
        named = set(re.findall(r"\{(\w+)\}", path))
        assert named == {field.alias for field in route.dependant.path_params}


def swift_constant(file: str, enum: str, name: str) -> int:
    """`public static let <name> = <int>` inside `public enum <enum>` of a DeadwaxCore file."""
    text = (CORE / file).read_text(encoding="utf-8")
    body = re.search(r"public enum " + enum + r"\b[^{]*\{(.*?)\n\}", text, re.S)
    assert body, f"no enum {enum} in {file}"
    found = re.search(r"public static let " + name + r" = ([\d_]+)\b", body.group(1))
    assert found, f"no {enum}.{name} in {file}"
    return int(found.group(1).replace("_", ""))


def bounds(route: APIRoute, alias: str) -> tuple[float, float]:
    """A query parameter's declared ge/le (-inf/inf when it has none)."""
    field = next(f for f in route.dependant.query_params if f.alias == alias)
    low, high = float("-inf"), float("inf")
    for rule in field.field_info.metadata:
        low = getattr(rule, "ge", low) if getattr(rule, "ge", None) is not None else low
        high = getattr(rule, "le", high) if getattr(rule, "le", None) is not None else high
    return low, high


def test_what_the_app_sends_is_within_the_servers_bounds(monkeypatch):
    # a server bound lowered below what the app asks for makes every such request a 422
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    routes = app_routes()
    search = routes[("GET", "/deadwax/navidrome/search")]
    cover = routes[("GET", "/deadwax/navidrome/cover/{cover_id}")]
    hi_res = swift_constant("TestSongs.swift", "HiRes", "pageSize")
    pages = swift_constant("TestSongs.swift", "HiRes", "maxPages")
    sent = [
        ((search, "songCount"), [swift_constant("TestSongs.swift", "TestSounds", "pageSize"), hi_res]),
        ((search, "songOffset"), [0, (pages - 1) * hi_res]),
        ((search, "artistCount"), [0]),
        ((search, "albumCount"), [0]),
        ((cover, "size"), [swift_constant("Routes.swift", "CoverSize", "lockScreen")]),
    ]
    assert bounds(search, "songCount")[1] == navidrome.SEARCH_MAX_SONGS     # the bounds are read at all
    for (route, alias), values in sent:
        low, high = bounds(route, alias)
        for value in values:
            assert low <= value <= high, f"{route.path}: the app sends {alias}={value}, the server takes {low}..{high}"


def test_the_answers_hold_what_the_app_decodes(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    client = TestClient(app)
    health = client.get("/deadwax/health").json()
    assert required_fields("Health") <= set(health), health
    me = client.get("/deadwax/me").json()
    assert required_fields("Me") <= set(me), me
    assert me["auth"] in ("on", "off")


def test_the_sign_in_answers_what_the_app_decodes(monkeypatch, tmp_path):
    # the sign-in's answer is built apart from /me's (src/routes/auth.py), and the app decodes it as Me;
    # the break-glass name signs in without Navidrome
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "0123456789abcdef0123456789abcdef-test-key")
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", "break-the-glass-please")
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "slskd"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    monkeypatch.setattr(auth, "throttle", auth.Throttle())
    auth.forget_sessions()
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    try:
        answer = TestClient(app).post("/deadwax/auth/login",
                                      json={"username": auth.BREAK_GLASS_USER, "password": "break-the-glass-please"})
        assert answer.status_code == 200, answer.text
        assert required_fields("Me") <= set(answer.json()), answer.json()
        assert answer.json()["auth"] == "on"
        # the session's value, by SessionCookie's rule: after the cookie's name and `=`, up to `;`
        header = answer.headers["set-cookie"]
        value = re.search(r"(?:^|[,;]\s*)" + re.escape(auth.COOKIE) + r"=([^;,]*)", header)
        assert value and value.group(1), header
        # and that value, sent back as the app sends it, is the session
        me = TestClient(app).get("/deadwax/me", headers={"Cookie": f"{auth.COOKIE}={value.group(1)}"})
        assert me.status_code == 200 and me.json()["user"] == answer.json()["user"], me.text
    finally:
        auth.forget_sessions()


def test_what_the_app_reads_is_what_it_names():
    assert required_fields("Health") == {"status"}
    assert required_fields("Me") == {"user", "admin", "auth"}
    assert required_fields("SearchResult") == {"albums", "songs"}


def test_the_sign_in_and_its_cookie():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    sent = set(re.search(r"struct SignInBody[^{]*\{(.*?)\n\}", text, re.S).group(1).split("public let ")[1:])
    sent = {line.split(":")[0] for line in sent}
    assert sent == set(SignIn.model_fields), "the app's sign-in form isn't the server's"
    cookie = (CORE / "SessionCookie.swift").read_text(encoding="utf-8")
    assert f'public static let name = "{auth.COOKIE}"' in cookie


def test_search_answers_albums_and_songs():
    import inspect
    source = inspect.getsource(navidrome.search)
    assert '"albums":' in source and '"songs":' in source
