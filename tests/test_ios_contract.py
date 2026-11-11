"""
The iPhone app's contract with the server (notes/ios.md): every route the app calls, read from its own
source (ios/DeadwaxKit/Sources/DeadwaxCore/Routes.swift's `Endpoint(...)` lines), must be a route the
server has, with the method the app uses, every path parameter named as the server names it, and every
query parameter one the server declares - FastAPI ignores an undeclared one without a word, so a
renamed parameter would leave the app asking for the wrong thing and getting an answer anyway.

And what the app decodes must be there: the fields its models need (the non-optional stored properties of
its structs, by their JSON names - CodingKeys read - in any DeadwaxCore file) in the server's real answers or
the routes' own source, every field it reads at all one the server sends, what it sends one the server's
model declares, the sign-in form's fields, the session cookie's name (and the sign-in's own answer, with a
session the server takes back), search's `albums` and `songs`, the permissions' names and the break-glass
admin's - and every number the app sends (page sizes, offsets, the covers' sizes, a scrobble's time) within
the bounds the server declares. A server change that would break the app fails here, in the Python suite,
where the server is changed - the app is built only on a Mac.

Phase 1's loudness route (GET /deadwax/navidrome/loudness/album/{album_id}) lands on the server as 2.1.1:
its case below fails until then, by design - the app was written against it first.
"""

import inspect
import re
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth, users  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import my_library, navidrome, store_album  # noqa: E402
from src.routes.auth import SignIn  # noqa: E402
from src.routes.download import FindCandidatesRequest  # noqa: E402
from src.store import JobStore  # noqa: E402

CORE = Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
ENDPOINT = re.compile(r'Endpoint\(method: "(\w+)", path: "([^"]+)", query: \[([^\]]*)\]\)')
ROUTE_COUNT = 23
RAW_OPENING = re.compile(r'#+"')
HASHES = re.compile(r"#*")


def endpoints() -> list[tuple[str, str, list[str]]]:
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    found = []
    for method, path, query in ENDPOINT.findall(text):
        found.append((method, path, re.findall(r'"([^"]+)"', query)))
    return found


# ---------------------------------------------------------------------------- reading the Swift

def _code(text: str) -> str:
    """Swift source with its comments blanked and the braces inside its string literals too - so a brace in a doc
    comment ("deadwax answers `{}`") or a string can't end a struct early. Strings keep their words otherwise
    (CodingKeys' JSON names are strings)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        elif text[i] == '"' or (text[i] == "#" and RAW_OPENING.match(text, i)):
            hashes = HASHES.match(text, i).group(0)
            start = i + len(hashes)
            quote = '"""' if text.startswith('"""', start) else '"'
            close = quote + hashes
            j = start + len(quote)
            while j < n and not text.startswith(close, j):
                j += 2 if (text[j] == "\\" and not hashes) else 1
            end = min(n, j + len(close))
            out.append(text[i:end].replace("{", " ").replace("}", " "))
            i = end
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def _block(code: str, opening: int) -> str:
    """The text inside the braces that open at `opening`."""
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return code[opening + 1:index]
    raise AssertionError("unbalanced braces")


def _top_level(body: str) -> str:
    """A block's own text, without what its nested blocks hold."""
    out, depth = [], 0
    for char in body:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 0:
            out.append(char)
    return "".join(out)


def swift_struct(name: str) -> str:
    """The body of `struct <name>` in whichever DeadwaxCore file declares it (one only)."""
    found = []
    for file in sorted(CORE.glob("*.swift")):
        code = _code(file.read_text(encoding="utf-8"))
        for match in re.finditer(r"\bstruct\s+" + name + r"\b[^{]*\{", code):
            found.append(_block(code, match.end() - 1))
    assert len(found) == 1, f"struct {name} is declared {len(found)} times in DeadwaxCore"
    return found[0]


def _depth_at(body: str, index: int) -> int:
    return body.count("{", 0, index) - body.count("}", 0, index)


def coding_keys(body: str) -> dict[str, str] | None:
    """A struct's CodingKeys, Swift name -> JSON name; None when it has none of its own (a nested type's are its own)."""
    match = next((one for one in re.finditer(r"\benum\s+CodingKeys\b[^{]*\{", body) if _depth_at(body, one.start()) == 0), None)
    if not match:
        return None
    keys = {}
    for case in re.findall(r"\bcase\s+([^\n]+)", _block(body, match.end() - 1)):
        for item in case.split(","):
            item = item.strip()
            if not item:
                continue
            named = re.match(r'(\w+)\s*=\s*"([^"]+)"', item)
            if named:
                keys[named.group(1)] = named.group(2)
            else:
                keys[re.match(r"\w+", item).group(0)] = re.match(r"\w+", item).group(0)
    return keys


def fields(struct: str) -> dict[str, bool]:
    """A struct's stored properties by JSON name -> whether optional: its own `let`s (not a nested type's), named as
    its CodingKeys say; a property CodingKeys leaves out is never read, so isn't here."""
    body = swift_struct(struct)
    keys = coding_keys(body)
    found = {}
    for static, name, kind in re.findall(r"(\bstatic\s+)?\blet\s+(\w+)\s*:\s*([^=\n]+)", _top_level(body)):
        if static or (keys is not None and name not in keys):
            continue
        found[keys[name] if keys is not None else name] = kind.strip().endswith("?")
    return found


def required_fields(struct: str) -> set[str]:
    """The non-optional stored properties of a DeadwaxCore struct, by JSON name - what decoding needs."""
    return {name for name, optional in fields(struct).items() if not optional}


def sent_fields(struct: str) -> set[str]:
    """What an Encodable struct with CodingKeys sends: every key."""
    keys = coding_keys(swift_struct(struct))
    assert keys is not None, f"{struct} has no CodingKeys"
    return set(keys.values())


def app_routes() -> dict[tuple[str, str], APIRoute]:
    routes = {}
    for route in start().routes:
        if isinstance(route, APIRoute):
            for method in route.methods:
                routes[(method, route.path)] = route
    return routes


def returned_keys(function) -> set[str]:
    """The keys of the dict literals a route function returns, read from its source."""
    keys = set()
    for literal in re.findall(r"return (?:_no_store\()?\{(.*?)\}\)?\s*$", inspect.getsource(function), re.S | re.M):
        keys |= set(re.findall(r'"(\w+)":', literal))
    return keys


# ---------------------------------------------------------------------------- the routes

def test_the_app_names_its_routes_in_the_form_this_test_reads():
    found = endpoints()
    # Routes.all in the Swift lists every one; a line in another form would be missed here, silently
    assert len(found) == ROUTE_COUNT
    assert len({(m, p) for m, p, _ in found}) == ROUTE_COUNT
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    listed = re.search(r"public static let all: \[Endpoint\] = \[(.*?)\]", text, re.S).group(1)
    assert len(re.findall(r"\w+", listed)) == ROUTE_COUNT


@pytest.mark.parametrize("method,path,query", endpoints(), ids=[f"{m} {p}" for m, p, _ in endpoints()])
def test_every_route_the_app_calls_is_the_servers_with_its_parameters(monkeypatch, method, path, query):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    route = app_routes().get((method, path))
    assert route is not None, f"the app calls {method} {path}, which the server doesn't have"
    declared = {field.alias for field in route.dependant.query_params}
    assert set(query) <= declared, f"{path}: the app sends {sorted(set(query) - declared)}, which the server ignores"
    # and the other way: DeadwaxClient.url() sends only the names an Endpoint declares, so one that loses a parameter
    # the server requires would make every call to it a 422 with nothing else noticing (search's q, album_index's
    # scope, a song's level's level)
    required = {field.alias for field in route.dependant.query_params if field.required}
    assert required <= set(query), f"{path}: the server needs {sorted(required - set(query))}, which the app never sends"
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
    scrobble = routes[("POST", "/deadwax/navidrome/scrobble/{song_id}")]
    hi_res = swift_constant("TestSongs.swift", "HiRes", "pageSize")
    pages = swift_constant("TestSongs.swift", "HiRes", "maxPages")
    sent = [
        ((search, "songCount"), [swift_constant("TestSongs.swift", "TestSounds", "pageSize"), hi_res]),
        ((search, "songOffset"), [0, (pages - 1) * hi_res]),
        ((search, "artistCount"), [0]),
        ((search, "albumCount"), [0]),
        ((cover, "size"), [swift_constant("Routes.swift", "CoverSize", name) for name in ("row", "tile", "hero", "lockScreen")]),
        # milliseconds since 1970: one in 2026, and one in 2027
        ((scrobble, "time"), [0, 1_767_312_000_000, 1_800_000_000_000]),
    ]
    assert bounds(search, "songCount")[1] == navidrome.SEARCH_MAX_SONGS     # the bounds are read at all
    assert bounds(cover, "size") == (16, 2000)
    for (route, alias), values in sent:
        low, high = bounds(route, alias)
        for value in values:
            assert low <= value <= high, f"{route.path}: the app sends {alias}={value}, the server takes {low}..{high}"


def test_the_album_index_is_asked_for_a_scope_the_server_takes(monkeypatch):
    # the app asks `yours` (logins on) or `store`: a scope the server doesn't know is a 422 for the whole Library
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    answer = TestClient(start()).get("/deadwax/navidrome/album_index", params={"scope": "everything"})
    assert answer.status_code == 422
    assert set(navidrome.SCOPE_LIST) == {"yours", "store"}


# ---------------------------------------------------------------------------- the answers

def test_the_answers_hold_what_the_app_decodes(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    client = TestClient(app)
    health = client.get("/deadwax/health").json()
    assert required_fields("Health") <= set(health), health
    me = client.get("/deadwax/me").json()
    assert required_fields("Me") <= set(me), me
    # and every field the app reads at all: a renamed one would read as absent, without a word
    assert set(fields("Me")) <= set(me), me
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
        assert set(fields("Me")) <= set(answer.json()), answer.json()
        assert answer.json()["auth"] == "on"
        # the session's value, by SessionCookie's rule: after the cookie's name and `=`, up to `;`
        header = answer.headers["set-cookie"]
        value = re.search(r"(?:^|[,;]\s*)" + re.escape(auth.COOKIE) + r"=([^;,]*)", header)
        assert value and value.group(1), header
        # and that value, sent back as the app sends it, is the session
        me = TestClient(app).get("/deadwax/me", headers={"Cookie": f"{auth.COOKIE}={value.group(1)}"})
        assert me.status_code == 200 and me.json()["user"] == answer.json()["user"], me.text
        assert set(fields("Me")) <= set(me.json()), me.json()
    finally:
        auth.forget_sessions()


def test_what_the_app_reads_is_what_it_names():
    assert required_fields("Health") == {"status"}
    assert required_fields("Me") == {"user", "admin", "auth"}
    # what /me says since 2.0.0-player.61 is read when there, and an older server's answer still reads
    assert {"version", "permissions", "permissions_unverified"} <= {name for name, optional in fields("Me").items() if optional}
    assert required_fields("SearchResult") == {"albums", "songs"}
    # Navidrome's answers pass through deadwax as they are: the app needs only the id, and reads the rest leniently
    assert required_fields("Album") == {"id"}
    assert required_fields("Song") == {"id"}
    assert required_fields("StoreRow") == {"id", "path"}


def test_the_id_bridge_answers_what_the_app_decodes(monkeypatch):
    # asked by Navidrome's id, with nothing set up: the answer's shape is still the whole of it
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    answer = TestClient(app).get("/deadwax/store/album", params={"navidrome_id": "al-1"})
    assert answer.status_code == 200, answer.text
    body = answer.json()
    assert required_fields("StoreAlbum") <= set(body), body
    # `yours` only with logins on and a folder held - read from the route
    source = inspect.getsource(store_album.store_album)
    assert 'answer["yours"]' in source
    assert set(fields("StoreAlbum")) <= set(body) | {"yours"}
    # a row: _row's keys, the present rows' facts, another pressing's Navidrome id and whether it is yours
    row = set(store_album._row({}))
    facts = set(re.findall(r'"(\w+)":', re.search(r"facts\[path\] = \{(.*?)\}", inspect.getsource(store_album._facts), re.S).group(1)))
    assert '"navidrome_id": ids[' in source and 'pressing["yours"]' in source
    assert required_fields("StoreRow") <= row
    assert set(fields("StoreRow")) <= row | facts | {"navidrome_id", "yours"}


def test_adding_and_removing_send_and_read_what_the_server_says():
    # Add sends FindCandidatesRequest's fields, every one it requires among them (an undeclared one is dropped
    # without a word - the trap download.py's comments describe)
    model = FindCandidatesRequest.model_fields
    sent = sent_fields("AddRelease")
    assert sent <= set(model), f"the app sends {sorted(sent - set(model))}, which /me/library/add drops"
    assert {name for name, field in model.items() if field.is_required()} <= sent
    added = returned_keys(my_library.add_to_my_library)
    assert set(fields("AddedToLibrary")) <= added, added
    removed = returned_keys(my_library.remove_from_my_library)
    assert set(fields("RemovedFromLibrary")) <= removed, removed
    assert sent_fields("LibraryRemoveBody") == set(my_library.Remove.model_fields)


def test_warming_an_albums_levels_answers_a_state():
    # the app reads `state` from the 202 (DeadwaxClient.warmLevels)
    assert returned_keys(navidrome.level_album) == {"state"}


def test_the_permissions_and_the_break_glass_name_are_the_servers():
    text = _code((CORE / "Access.swift").read_text(encoding="utf-8"))
    match = re.search(r"\benum\s+Permission\b[^{]*\{", text)
    cases = re.findall(r"\w+", " ".join(re.findall(r"\bcase\s+([^\n]+)", _block(text, match.end() - 1))))
    assert tuple(cases) == tuple(users.PERMISSIONS), "the app's permissions aren't the server's, in its order"
    assert f'public static let breakGlassUser = "{auth.BREAK_GLASS_USER}"' in text


def test_the_sign_in_and_its_cookie():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    sent = set(re.search(r"struct SignInBody[^{]*\{(.*?)\n\}", text, re.S).group(1).split("public let ")[1:])
    sent = {line.split(":")[0] for line in sent}
    assert sent == set(SignIn.model_fields), "the app's sign-in form isn't the server's"
    cookie = (CORE / "SessionCookie.swift").read_text(encoding="utf-8")
    assert f'public static let name = "{auth.COOKIE}"' in cookie


def test_search_answers_albums_and_songs():
    source = inspect.getsource(navidrome.search)
    assert '"albums":' in source and '"songs":' in source


def test_the_swift_reader_reads_what_it_should():
    # a guard on the guard: nested types' properties aren't the outer struct's, and CodingKeys rename
    assert "role" not in fields("Song") and "contributors" in fields("Song")
    assert "release_group_mbid" in fields("StoreAlbum") and "releaseGroupMbid" not in fields("StoreAlbum")
    assert "tracks" in sent_fields("AddRelease") and "tracks" not in fields("AddRelease")
    assert fields("Health") == {"status": False, "version": True, "poller": True}
