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

Phase 1's models are held the same way, each to the code that builds its answer or reads its body: resume's
(GET /queue's answer and deadwax's record, the two saves' bodies, what a save answers, the device and label the
phone saves under), the loudness route's (2.1.1) with its album and song parts, Info's level answer, Navidrome's
status, a play's query (sent through the real route) and the New mark's `seen` body. The Library's own models are in
tests/test_ios_library_contract.py, which reads every DeadwaxCore file the same way.

And app 0.4's lyrics (notes/app-lyrics.md 4.8): SongLyrics and LyricLine to what the lyrics route sends (src/lyrics.py
song_lyrics(), sent whole by the route), and the answers the Swift tests decode (Fixtures/lyrics/answers.json, written
by ios/scripts/lyrics_answers.py) to song_lyrics() itself, case by case.

And the EQ's AutoEq (server 2.1.7, eq.md 5.4): AutoEqResults, AutoEqResult, AutoEqMeasurement and AutoEqProfile to
src/autoeq.py's row_answer and profile_answer and the search route's own answer; the answers the Swift tests decode
(Fixtures/autoeq/answers.json, written by ios/scripts/autoeq_answers.py over tests/test_autoeq.py's fake GitHub) to
what the helper makes now; and the search's limit and longest query within what the route takes.

And app 0.8's play history (server 2.1.14, notes/play-history.md): Played and HistorySong to the route's HistoryStart and
HistorySong - every name the phone writes one the server declares, and the other way - HistoryPage, HistoryCursor and
HistoryTaken to what src/play_history.py page() and the POST answer; a start as the phone writes it (every field, nulls
written out - PlayHistoryTests' own JSON) taken by the real route and paged back; and the page the phone asks for and the
batch it sends within the route's bounds.

And app 0.10's playlists (Phase 4, notes/ios-specs/phase4-library.md): Playlist, PlaylistList and PlaylistWithSongs to
what src/playlists.py's summary() and with_songs() build and the two read routes send - every field the phone reads one
they send, and every one it can't do without there and not null, Navidrome's fields left out included. And slice 2's
four writes: NewPlaylistBody, PlaylistAddBody and PlaylistEditBody to the extra="forbid" models they are posted to (every
key the phone sends one the server declares, every one it requires sent), the duplicates the phone names the route's
own, PlaylistAddAnswer and PlaylistDeleted to what the add and the delete return, create and edit answering a playlist
with its songs, and the statuses the phone reads (409 changed, 404 gone, 403 not yours) where the routes raise them.
"""

import importlib.util
import inspect
import json
import re
import sys
import time
import typing
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth, autoeq, levels, loudness, lyrics, users  # noqa: E402
from src import play_history as history_rules  # noqa: E402
from src import playlists as playlist_rules  # noqa: E402
from src import play_queue as queue_rules  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import CLIENT_NAME  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import eq as eq_route  # noqa: E402
from src.routes import my_library, navidrome, store_album  # noqa: E402
from src.routes import play_history as history_route  # noqa: E402
from src.routes.auth import SignIn  # noqa: E402
from src.routes.download import FindCandidatesRequest  # noqa: E402
from src.store import JobStore  # noqa: E402

CORE = Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
ENDPOINT = re.compile(r'Endpoint\(method: "(\w+)", path: "([^"]+)", query: \[([^\]]*)\]\)')
ROUTE_COUNT = 36
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
    # every Endpoint the Swift makes is a line in the one form read here - one in another form would be missed,
    # silently - and each route is named once
    code = _code((CORE / "Routes.swift").read_text(encoding="utf-8"))
    assert code.count("Endpoint(") == len(found) == ROUTE_COUNT
    assert len({(m, p) for m, p, _ in found}) == ROUTE_COUNT
    # Routes.all lists every one of them, each once - by name, so a route left out of it (and so out of the
    # Swift's own checks) fails here, not only a count that happens to agree
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    declared = re.findall(r"public static let (\w+) = Endpoint\(", text)
    listed = re.findall(r"\w+", re.search(r"public static let all: \[Endpoint\] = \[(.*?)\]", text, re.S).group(1))
    assert len(declared) == ROUTE_COUNT
    assert sorted(listed) == sorted(declared), set(listed) ^ set(declared)


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
    scrub = routes[("GET", "/deadwax/navidrome/scrub/{song_id}")]
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
        # the turntable's /scrub (turntable.md 4.5): the longest it asks, and the shortest (a window of nothing, its
        # pre-roll and its second)
        ((scrub, "seconds"), [swift_constant("DeckScrub.swift", "DeckScrub", "maxSeconds"), 1]),
        ((scrub, "at"), [0]),
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


# ---------------------------------------------------------------------------- Phase 1's models

def returned_literals(function) -> list[str]:
    """The text of each dict literal a route function returns (`return {...}`, or `return _no_store({...})`), braces
    matched - so a multi-line literal is read whole."""
    source = inspect.getsource(function)
    return [_block(source, match.end() - 1) for match in re.finditer(r"\breturn (?:_no_store\()?\{", source)]


def literal_keys(literal: str) -> set[str]:
    return set(re.findall(r'"(\w+)":', _top_level(literal)))


def literal_nulls(literal: str) -> set[str]:
    """The keys a literal sends as null."""
    return set(re.findall(r'"(\w+)":\s*None\b', _top_level(literal)))


def swift_raw_values(file: str, enum: str) -> set[str]:
    """The raw values of a String enum's cases in a DeadwaxCore file: `case a, b` and `case c = "c_d"`."""
    code = _code((CORE / file).read_text(encoding="utf-8"))
    found = list(re.finditer(r"\benum\s+" + enum + r"\b[^{]*\{", code))
    assert len(found) == 1, f"enum {enum} is declared {len(found)} times in {file}"
    values = set()
    for line in re.findall(r"\bcase\s+([^\n]+)", _top_level(_block(code, found[0].end() - 1))):
        for item in line.split(","):
            named = re.match(r'\s*(\w+)\s*(?:=\s*"([^"]+)")?\s*$', item)
            assert named, f"{enum}: can't read {item!r}"
            values.add(named.group(2) or named.group(1))
    return values


def swift_function(file: str, name: str) -> str:
    """The body of `func <name>` in a DeadwaxCore file (one only), comments blanked."""
    code = _code((CORE / file).read_text(encoding="utf-8"))
    found = list(re.finditer(r"\bfunc\s+" + name + r"\b[^{]*\{", code))
    assert len(found) == 1, f"func {name} is declared {len(found)} times in {file}"
    return _block(code, found[0].end() - 1)


def optional_fields(struct: str) -> set[str]:
    return {name for name, optional in fields(struct).items() if optional}


def assert_decodes(struct: str, answer: dict, ahead: frozenset[str] = frozenset()):
    """What decoding `answer` as `struct` needs: every field the Swift reads is a key the answer has (one renamed would
    read as absent, or fail), and every one it can't do without is there and not null (a null where the Swift has a
    plain type fails the whole answer). `ahead`: fields the phone reads before the server sends them, each decoded
    from its absence (PLAYLIST_AHEAD) - exempt only while the answer leaves them out."""
    ahead = frozenset(ahead) - set(answer)
    reads = set(fields(struct)) - ahead
    assert reads <= set(answer), f"{struct} reads {sorted(reads - set(answer))}, never sent"
    sent = {name for name, value in answer.items() if value is not None}
    needs = required_fields(struct) - ahead
    assert needs <= sent, f"{struct} needs {sorted(needs - sent)}: {answer}"


def _play_queue_record(tmp_path, snapshot):
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    store.put_play_queue("ethan", ["so-1", "so-2", "so-1"], 1, 12.5, snapshot, "AbCdEfGhIjKlMnOp", "iPhone")
    return store.play_queue("ethan")


def test_the_queue_answer_is_what_get_queue_sends(tmp_path):
    # resume's GET /queue: play_queue.answer() builds every answer the route gives but the break-glass admin's
    body = {"entry": [{"id": "so-1", "title": "One"}, {"id": "so-2"}], "currentIndex": 1, "position": 12500,
            "changedBy": CLIENT_NAME}
    for record in (_play_queue_record(tmp_path, None), None):
        answer = queue_rules.answer(body, record, False, navidrome.SHUFFLE_FIELDS, CLIENT_NAME)
        assert set(fields("QueueAnswer")) == set(answer), answer
        assert_decodes("QueueAnswer", answer)
    # Navidrome's queue empty - no index, no record - and logins off
    empty = queue_rules.answer({}, None, True, navidrome.SHUFFLE_FIELDS, CLIENT_NAME)
    assert_decodes("QueueAnswer", empty)
    assert {"index", "kept"} <= optional_fields("QueueAnswer")
    # the break-glass admin's, written out in the route
    (glass,) = returned_literals(navidrome.queue)
    assert literal_keys(glass) == set(fields("QueueAnswer"))
    assert not required_fields("QueueAnswer") & literal_nulls(glass)
    # its songs are trimmed to the shuffle's fields: a Song needs only its id, which is always among them
    assert required_fields("Song") <= set(navidrome.SHUFFLE_FIELDS)
    # (review) and every field the phone makes a resumed entry from is among them too: shuffledTrack's `song.<name>`
    # reads, by Song's JSON names. A trimmed-out field decodes as absent without a word - no suffix or content type
    # and every song put back reads as no FLAC, so plays unlevelled; no duration and every length is 0
    keys = coding_keys(swift_struct("Song"))
    read = {keys[name] for name in re.findall(r"\bsong\.(\w+)", swift_function("Resume.swift", "shuffledTrack"))}
    assert {"id", "title", "duration", "contentType", "suffix", "samplingRate"} <= read, read  # the reader's guard
    assert read <= set(navidrome.SHUFFLE_FIELDS), f"GET /queue trims away {sorted(read - set(navidrome.SHUFFLE_FIELDS))}"


def test_deadwaxs_record_is_what_the_app_reads_back(tmp_path):
    record = queue_rules.kept_view(_play_queue_record(tmp_path, None))
    assert set(fields("KeptQueue")) == set(record), record
    assert_decodes("KeptQueue", record)
    # and every column the record can hold NULL is optional in the Swift (the snapshot today) - read from the schema,
    # so a column made nullable on the server without the phone's model following fails here
    schema = re.search(r"CREATE TABLE IF NOT EXISTS play_queue \((.*?)\n\);", Path(inspect.getfile(JobStore)).read_text(
        encoding="utf-8"), re.S).group(1)
    columns = {}
    for line in re.sub(r"--[^\n]*", "", schema).splitlines():
        column = re.match(r"\s*(\w+)\s+(\w+)(.*?),?\s*$", line)
        if column:
            columns[{"idx": "index"}.get(column.group(1), column.group(1))] = "NOT NULL" in column.group(3)
    nullable = {name for name in record if not columns[name]}
    assert nullable == {"snapshot"}
    assert nullable <= optional_fields("KeptQueue")


def test_the_queue_saves_send_what_the_server_declares():
    # both bodies are extra="forbid": a key the server doesn't declare is a 422 for every save, and so is one it
    # requires left out
    for struct, model in (("QueueSaveBody", navidrome.QueueSave), ("QueueAtBody", navidrome.QueueAt)):
        assert model.model_config.get("extra") == "forbid"
        sent = fields(struct)
        assert set(sent) == set(model.model_fields), f"{struct}: {sorted(set(sent) ^ set(model.model_fields))}"
        needed = {name for name, field in model.model_fields.items() if field.is_required()}
        assert needed <= required_fields(struct), f"{struct} may leave out {sorted(needed - required_fields(struct))}"
        # a Swift nil is left out of the JSON (the synthesized encoder's encodeIfPresent): only a field with a
        # default may be
        assert optional_fields(struct) <= set(model.model_fields) - needed
    assert optional_fields("QueueSaveBody") == {"snapshot"}


def test_the_phone_saves_under_a_device_and_label_the_server_takes():
    # a device or label outside the patterns is a 422 on every save
    alphabet = re.search(r'public static let alphabet = Array\("([^"]+)"\)', (CORE / "DeviceID.swift").read_text(
        encoding="utf-8")).group(1)
    length = swift_constant("DeviceID.swift", "DeviceID", "length")
    assert queue_rules.DEVICE.match(alphabet[:length]) and queue_rules.DEVICE.match(alphabet[-length:])
    assert all(queue_rules.DEVICE.match(char * length) for char in alphabet)
    assert re.search(r"public static let lengths = 8\.\.\.64\n", (CORE / "DeviceID.swift").read_text(encoding="utf-8"))
    assert queue_rules.DEVICE_PATTERN.endswith("{8,64}$")
    label = re.search(r'public static let label = "([^"]+)"', (CORE / "Resume.swift").read_text(encoding="utf-8"))
    assert label and queue_rules.LABEL.match(label.group(1))
    # the window, the snapshot's cap and the furthest position are the server's - and what Navidrome records a
    # deadwax save as, which says whose the record is
    assert swift_constant("Resume.swift", "Resume", "maxEntries") == queue_rules.RESUME_MAX
    assert swift_constant("Resume.swift", "Resume", "before") == queue_rules.RESUME_BEFORE
    assert swift_constant("Resume.swift", "Resume", "snapshotMax") == queue_rules.SNAPSHOT_MAX
    assert swift_constant("Resume.swift", "Resume", "positionMax") == queue_rules.POSITION_MAX
    assert f'public static let deadwaxClient = "{CLIENT_NAME}"' in (CORE / "Resume.swift").read_text(encoding="utf-8")


def test_a_save_answers_what_the_app_reads():
    for route in (navidrome.save_queue, navidrome.save_queue_at):
        literals = returned_literals(route)
        assert len(literals) == 2, literals          # the break-glass admin's nulls, and the record's revs
        for literal in literals:
            assert literal_keys(literal) == set(fields("SavedQueue")), literal
        # the break-glass admin's are null: neither may be required
        assert {"rev", "ids_rev"} <= set().union(*map(literal_nulls, literals))
    assert required_fields("SavedQueue") == set()


def test_the_loudness_answer_is_what_the_app_decodes():
    # src/levels.py builds every answer of the loudness route (2.1.1) with these three, so each has every key
    measured = levels._loudness_answer(
        "measured", None, True, levels._album_level(-20.5, 0.75, 2),
        [levels._song_entry("so-1", "measured", -20.0, 0.5), levels._song_entry("so-2", "measured", None, 0.0)])
    later = levels._loudness_answer("unmeasured", levels.LOOK_LATER, False, levels._album_level(None, None, 0), [])
    for answer in (measured, later):
        assert set(fields("AlbumLoudness")) == set(answer), answer
        assert_decodes("AlbumLoudness", answer)
        assert set(fields("AlbumLevel")) == set(answer["album"])
        assert_decodes("AlbumLevel", answer["album"])
    for song in (levels._song_entry("so-3", "unmeasured"), levels._song_entry("so-4", "not_levelled", why=levels.NOT_FLAC),
                 *measured["songs"]):
        assert set(fields("SongLoudness")) == set(song), song
        assert_decodes("SongLoudness", song)
    # the measurement's version is always sent, a whole number - the phone requires it
    assert "algorithm" in required_fields("AlbumLoudness")
    assert measured["algorithm"] == loudness.ALGORITHM_VERSION and isinstance(loudness.ALGORITHM_VERSION, int)
    # and the states it says are the ones the app names (one it doesn't know reads as unmeasured, by design - so a
    # state renamed on either side would read as unmeasured, without a word)
    said = set(re.findall(r'_(?:loudness_answer|song_entry)\((?:[^,()]+, )?"(\w+)"', inspect.getsource(levels)))
    assert said == {"measured", "measuring", "unmeasured", "not_levelled"}, said
    assert swift_raw_values("LoudnessModels.swift", "LoudnessState") == said


def test_infos_level_answer_is_the_servers_shape():
    # the phone makes its own (levelAnswer) so the web's words say what is heard - in the shape GET /level/{song_id}
    # answers (levels.describe), so the words are written against one shape
    source = inspect.getsource(levels.Levels.describe)
    literal = _block(source, re.search(r"answer = \{", source).end() - 1)
    assert set(fields("LevelAnswer")) == literal_keys(literal)
    assert required_fields("LevelAnswer") == literal_keys(literal) - literal_nulls(literal)
    level = next(field for field in app_routes()[("GET", "/deadwax/navidrome/level/{song_id}")].dependant.query_params
                 if field.alias == "level")
    assert swift_raw_values("Levels.swift", "Level") == set(typing.get_args(level.field_info.annotation))
    # and every state a level answer is given (describe() and the measured answer it hands on) is one the phone's
    # LevelAnswer.State names
    states = set(re.findall(r'"state": "(\w+)"', inspect.getsource(levels)))
    assert states == {"measured", "measuring", "unmeasured", "plain", "not_levelled"}, states
    assert swift_raw_values("LoudnessModels.swift", "State") == states


def test_navidrome_status_is_what_the_app_decodes():
    literals = returned_literals(navidrome.status)
    assert len(literals) == 3, literals                 # not set up, its ping failed, ok
    for literal in literals:
        assert literal_keys(literal) == set(fields("NavidromeStatus")), literal
        assert not required_fields("NavidromeStatus") & literal_nulls(literal), literal
    assert required_fields("NavidromeStatus") == {"configured", "ok"}


def test_a_play_is_sent_as_the_server_reads_it(monkeypatch):
    # the query a PlayReport is sent with, read from the Swift, through the real route: the names it declares and
    # the values as FastAPI parses them ("true"/"false", a time in whole milliseconds)
    plays = (CORE / "Plays.swift").read_text(encoding="utf-8")
    sent = re.findall(r'case \.(nowPlaying|played)[^:]*: return \[(.*?)\]\n', plays)
    assert [name for name, _ in sent] == ["nowPlaying", "played"]
    pairs = {name: re.findall(r'\("(\w+)", ("?)([^")]+)"?\)', items) for name, items in sent}
    assert pairs["nowPlaying"] == [("submission", '"', "false")]
    assert pairs["played"] == [("submission", '"', "true"), ("time", "", "String(atMs")]
    query = next(q for m, p, q in endpoints() if p == "/deadwax/navidrome/scrobble/{song_id}")
    assert {name for items in pairs.values() for name, _, _ in items} == set(query)

    monkeypatch.setattr(Config, "AUTH_MODE", None)
    asked = []

    class Navidrome:
        async def call(self, name, params=None, **_):
            asked.append((name, params))
            return {}

    monkeypatch.setattr(navidrome, "client_for", lambda request: Navidrome())
    client = TestClient(start())
    assert client.post("/deadwax/navidrome/scrobble/so-1?submission=false").status_code == 200
    assert client.post("/deadwax/navidrome/scrobble/so-1?submission=true&time=1767312000123").status_code == 200
    assert asked == [("scrobble", {"id": "so-1", "submission": "false", "time": None}),
                     ("scrobble", {"id": "so-1", "submission": "true", "time": 1767312000123})]


def test_seen_is_taken_as_the_app_sends_it(monkeypatch):
    # SeenBody's two shapes, as the synthesized encoder writes them (a nil left out): the server takes each
    keys = coding_keys(swift_struct("SeenBody"))
    assert set(keys.values()) == set(my_library.Seen.model_fields)
    assert optional_fields("SeenBody") == set(my_library.Seen.model_fields)
    assert all(not field.is_required() for field in my_library.Seen.model_fields.values())
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    client = TestClient(start())
    for body in ({keys["releaseMBID"]: "b84ee12a-09ef-421b-82de-0441a926375b"}, {keys["albumIDs"]: [1, 2]}):
        answer = client.post("/deadwax/me/library/seen", json=body)
        assert answer.status_code == 200 and answer.json() == {"cleared": 0}, answer.text


# ---------------------------------------------------------------------------- app 0.4: lyrics

LYRICS_HELPER = Path(__file__).resolve().parent.parent / "ios" / "scripts" / "lyrics_answers.py"
LYRICS_ANSWERS = (Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests"
                  / "Fixtures" / "lyrics" / "answers.json")


def _lyrics_helper():
    spec = importlib.util.spec_from_file_location("ios_lyrics_answers", LYRICS_HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_lyrics_answer_is_what_the_app_decodes():
    # the route sends song_lyrics() whole (json_with_etag of it): what the phone decodes is its two keys, and each
    # line's two - `time` null for plain lyrics, so optional; `text` always there
    source = inspect.getsource(navidrome.lyrics_of_song)
    assert "json_with_etag(request, lyrics.song_lyrics(body))" in source
    assert fields("SongLyrics") == {"synced": False, "lines": False}
    assert fields("LyricLine") == {"time": True, "text": False}
    cases = json.loads(LYRICS_ANSWERS.read_text(encoding="utf-8"))["cases"]
    kinds = set()
    for case in cases:
        answer = lyrics.song_lyrics(case["navidrome"])
        # the answer the Swift tests decode is the server's own, today
        assert answer == case["answer"], case["name"]
        assert_decodes("SongLyrics", answer)
        for line in answer["lines"]:
            assert_decodes("LyricLine", line)
            assert set(line) == set(fields("LyricLine")), line
        kinds.add("none" if not answer["lines"] else "synced" if answer["synced"] else "plain")
    # every case the route answers: synced, plain, none
    assert kinds == {"synced", "plain", "none"}


def test_the_lyrics_answers_are_the_ones_the_helper_makes():
    # Fixtures/lyrics/answers.json is what ios/scripts/lyrics_answers.py writes now, byte for byte - a case changed
    # there (or the file by hand) fails until it is written again; and its snapshot is the route tests' own
    from tests import test_navidrome_lyrics

    helper = _lyrics_helper()
    assert LYRICS_ANSWERS.read_text(encoding="utf-8") == helper.text()
    assert helper.SNAPSHOT == test_navidrome_lyrics.SNAPSHOT
    assert LYRICS_ANSWERS.read_bytes().isascii()


# ---------------------------------------------------------------------------- the EQ's AutoEq (2.1.7)

AUTOEQ_HELPER = Path(__file__).resolve().parent.parent / "ios" / "scripts" / "autoeq_answers.py"
AUTOEQ_ANSWERS = (Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests"
                  / "Fixtures" / "autoeq" / "answers.json")


def _autoeq_helper():
    spec = importlib.util.spec_from_file_location("ios_autoeq_answers", AUTOEQ_HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_autoeq_models_are_what_the_routes_answer():
    # each model reads exactly the keys its answer has - the search's row and the measurements under it (row_answer),
    # the profile (profile_answer), the search's own literal - rig and form optional (a folder may name neither),
    # everything else needed
    results, _ = autoeq.parse_index((Path(__file__).resolve().parent / "fixtures" / "autoeq" / "INDEX.md")
                                    .read_text(encoding="utf-8"))
    rows = autoeq.rows_of(results)
    several = next(row for row in rows if len(row.results) > 1 and any(r.rig is None for r in row.results[1:]))
    row = autoeq.row_answer(several)
    assert fields("AutoEqResult") == {"id": False, "name": False, "source": False, "rig": True, "form": True,
                                      "others": False}
    assert set(row) == set(fields("AutoEqResult"))
    assert_decodes("AutoEqResult", row)
    assert fields("AutoEqMeasurement") == {"id": False, "source": False, "rig": True, "form": True}
    for other in row["others"]:
        assert set(other) == set(fields("AutoEqMeasurement"))
        assert_decodes("AutoEqMeasurement", other)
    assert any(other["rig"] is None for other in row["others"])
    assert fields("AutoEqResults") == {"results": False, "total": False, "list_from": False}
    assert returned_keys(eq_route.search_autoeq) == set(fields("AutoEqResults"))
    profile = autoeq.profile_answer(results[0], "Preamp: -6.0 dB")
    assert fields("AutoEqProfile") == {"id": False, "name": False, "source": False, "rig": True, "form": True,
                                       "text": False}
    assert set(profile) == set(fields("AutoEqProfile"))
    assert_decodes("AutoEqProfile", profile)


def test_the_autoeq_answers_the_app_decodes_are_the_routes():
    # every answer in the fixture the Swift tests decode is one the route sent: the 200s read whole, the failures
    # deadwax's two sentences in `detail` (ErrorWords says a 503's as deadwax wrote it, a 404's as the page's gone)
    answers = json.loads(AUTOEQ_ANSWERS.read_text(encoding="utf-8"))
    seen = set()
    for case in answers["searches"]:
        answer = case["answer"]
        if case["status"] == 200:
            assert_decodes("AutoEqResults", answer)
            assert len(answer["results"]) == min(answer["total"], int(case["query"]["limit"]))
            for row in answer["results"]:
                assert_decodes("AutoEqResult", row)
                for other in row["others"]:
                    assert_decodes("AutoEqMeasurement", other)
            seen.add("found" if answer["results"] else "none")
            if answer["total"] > len(answer["results"]):
                seen.add("more than the limit")
        else:
            assert (case["status"], answer) == (503, {"detail": eq_route.UNREACHABLE})
            seen.add("503")
    for case in answers["profiles"]:
        answer = case["answer"]
        if case["status"] == 200:
            assert_decodes("AutoEqProfile", answer)
            assert answer["text"].startswith("Preamp:")
            seen.add("profile")
        else:
            assert answer == {"detail": {404: eq_route.GONE, 503: eq_route.UNREACHABLE}[case["status"]]}
            seen.add(f"profile {case['status']}")
    assert seen == {"found", "none", "more than the limit", "503", "profile", "profile 404", "profile 503"}


def test_the_autoeq_answers_are_the_ones_the_helper_makes(monkeypatch):
    # Fixtures/autoeq/answers.json is what ios/scripts/autoeq_answers.py writes now, byte for byte, over the route
    # tests' own fake GitHub - a route's answer changed (or the file by hand) fails until it is written again
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    helper = _autoeq_helper()
    assert AUTOEQ_ANSWERS.read_text(encoding="utf-8") == helper.text()
    assert AUTOEQ_ANSWERS.read_bytes().isascii()


def test_what_the_app_asks_autoeq_is_within_the_routes_bounds(monkeypatch):
    # the limit the phone asks with (AutoEqAsk.limit, the fixture's too) and the longest query it sends
    # (AutoEqAsk.longest) - a bound lowered under either makes every search a 422
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    route = app_routes()[("GET", "/deadwax/eq/autoeq")]
    limit = swift_constant("AutoEq.swift", "AutoEqAsk", "limit")
    longest = swift_constant("AutoEq.swift", "AutoEqAsk", "longest")
    low, high = bounds(route, "limit")
    assert low <= limit <= high and (low, high) == (1, 50)
    assert _autoeq_helper().LIMIT == limit
    query = next(f for f in route.dependant.query_params if f.alias == "q")
    lengths = {type(rule).__name__: rule for rule in query.field_info.metadata}
    assert lengths["MinLen"].min_length == 1
    assert longest == lengths["MaxLen"].max_length == 100


def test_the_app_waits_for_autoeq_as_long_as_deadwax_does():
    # a search may wait for deadwax's first fetch of AutoEq's list, and a profile for its file: the phone asking with
    # the transport's own 8 s would give up first - "That took too long." where deadwax would have answered
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    assert literal, "no Routes.timeouts"
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    assert timeouts["autoEqSearch"] > autoeq.FIRST_FETCH_SECONDS
    assert timeouts["autoEqProfile"] > autoeq.PROFILE_DEADLINE_SECONDS


# ---------------------------------------------------------------------------- app 0.8: play history

#? a start exactly as the phone writes it - PlayHistoryTests.writtenAsTheWebWritesAStart's JSON (every field, nil as
#? null), with a queue and entry
PHONE_START = ('{"at":1800000000000,"counted":false,"entry":3,"queue":"mhg9b18g-01z013za","song":{"album":"Mezzanine",'
               '"albumId":"mez","artist":"Massive Attack","bitDepth":16,"channels":2,"contentType":"audio\\/flac",'
               '"coverArt":null,"duration":200,"id":"1","sampleRate":44100,"suffix":"flac","title":"song 1"}}')


def test_a_start_is_written_in_the_names_the_server_declares():
    # Played and HistorySong write and read by their CodingKeys (their own encoders, every key): each name one the
    # route's model declares - pydantic would drop one it doesn't without a word - and every one it declares written
    played = coding_keys(swift_struct("Played"))
    song = coding_keys(swift_struct("HistorySong"))
    assert set(played.values()) == set(history_route.HistoryStart.model_fields)
    assert set(song.values()) == set(history_route.HistorySong.model_fields)
    assert set(song.values()) == set(history_rules.SONG_COLUMNS)
    # what the server needs is what the phone always has: the time, and the song with its id
    needed = {name for name, field in history_route.HistoryStart.model_fields.items() if field.is_required()}
    assert needed == {"at", "song"} and required_fields("Played") >= needed
    assert {name for name, field in history_route.HistorySong.model_fields.items() if field.is_required()} == {"id"}
    assert history_route.HistoryStart.model_config.get("extra") == "ignore"
    # the batch's one key
    assert fields("HistoryPost") == {"starts": False}
    assert set(history_route.HistoryPost.model_fields) == {"starts"}


def test_a_page_and_a_sends_answer_are_what_the_app_decodes():
    row = {"started_at": 1_800_000_000_000, "counted": 1, "queue": "q-1", "entry": 0,
           **{column: None for column in history_rules.SONG_COLUMNS.values()}, "song_id": "so-1"}
    for answer in (history_rules.page([row, dict(row)], 1, False), history_rules.page([row], 1, True),
                   history_rules.page([], 100, False)):
        assert set(fields("HistoryPage")) == set(answer), answer
        assert_decodes("HistoryPage", answer)
        if answer["next"] is not None:
            assert set(fields("HistoryCursor")) == set(answer["next"])
            assert_decodes("HistoryCursor", answer["next"])
        for play in answer["plays"]:
            assert set(coding_keys(swift_struct("Played")).values()) == set(play)
            assert set(coding_keys(swift_struct("HistorySong")).values()) == set(play["song"])
    assert optional_fields("HistoryPage") == {"next"}
    assert returned_keys(history_route.record) == set(fields("HistoryTaken")) == {"taken", "skipped"}
    assert required_fields("HistoryTaken") == {"taken", "skipped"}


def test_what_the_phone_sends_is_taken_and_paged_back(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    app = start()
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    app.state.store = store
    client = TestClient(app)
    # its time a minute ago (deadwax skips a start from the future): the text otherwise exactly the phone's
    phone = PHONE_START.replace("1800000000000", str(int(time.time() * 1000) - 60_000))
    sent = json.loads(phone)
    later = {**sent, "at": sent["at"] + 1000, "queue": None, "entry": None}
    answer = client.post("/deadwax/me/history", content='{"starts":[' + phone + "," + json.dumps(later) + "]}",
                         headers={"Content-Type": "application/json"})
    assert answer.status_code == 200 and answer.json() == {"taken": 2, "skipped": 0}, answer.text
    page = client.get("/deadwax/me/history", params={"limit": 1}).json()
    assert page["plays"] == [later] and page["next"] == {"at": later["at"], "id": "1"} and page["shared"]
    older = client.get("/deadwax/me/history", params={"limit": 1, "before_at": page["next"]["at"],
                                                       "before_id": page["next"]["id"]}).json()
    assert older == {"plays": [sent], "next": None, "shared": True}


def test_the_phones_page_and_batch_are_within_the_routes_bounds(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    routes = app_routes()
    read = routes[("GET", "/deadwax/me/history")]
    page = swift_constant("PlayHistory.swift", "PlayHistory", "page")
    low, high = bounds(read, "limit")
    assert low <= page <= high and page == history_rules.HISTORY_PAGE
    assert bounds(read, "before_at") == (0, history_rules.HISTORY_AT_MAX)
    batch = swift_constant("PlayHistory.swift", "PlayHistory", "postMax")
    size = {type(rule).__name__: rule for rule in history_route.HistoryPost.model_fields["starts"].metadata}
    assert size["MinLen"].min_length == 1 and batch == size["MaxLen"].max_length == history_rules.HISTORY_POST_MAX


# ---------------------------------------------------------------------------- app 0.10's playlists (Phase 4)

NAVIDROME_PLAYLIST = {
    "id": "pl1", "name": "Late night", "comment": "For after", "songCount": 3, "duration": 611, "public": True,
    "owner": "James", "readonly": False, "created": "2026-10-01T10:00:00Z", "changed": "2026-11-01T10:00:00Z",
    "coverArt": "pl-pl1_abc", "entry": [{"id": "s1", "title": "Roads", "albumId": "al-d", "duration": 305},
                                        {"id": "s2", "title": "Teardrop", "albumId": "al-m", "duration": 306}],
}


# (iOS slice 3's review, James: "No Download for them") `smart` - one of Navidrome's smart playlists - read by the phone
# ahead of main's summary() sending it (its own 2.1.x); until then decoded from its absence as false. Exempt only while
# summary() leaves it out: once main sends it, it is a field like every other, the same equality holding it.
PLAYLIST_AHEAD = frozenset({"smart"})


def test_the_playlist_answers_are_what_the_app_decodes():
    # summary() is each row of the list and a playlist's own: the phone reads exactly its keys - the cover optional
    # (null for an empty playlist), every other one always sent; Navidrome leaving everything out still decodes
    row = playlist_rules.summary(NAVIDROME_PLAYLIST, "james")
    ahead = PLAYLIST_AHEAD - set(row)
    reads = set(fields("Playlist")) - ahead
    assert reads == set(row), sorted(reads ^ set(row))
    assert optional_fields("Playlist") == {"coverArt"}
    assert_decodes("Playlist", row, PLAYLIST_AHEAD)
    assert row["mine"] and row["editable"] and row["public"]
    # what is read ahead is read from its absence, never required
    playlist_code = _code((CORE / "Playlists.swift").read_text(encoding="utf-8"))
    for name in ahead:
        assert f"{name} = fields.looseField(Bool.self, .{name}) ?? false" in playlist_code, name
    bare = playlist_rules.summary({"id": "pl2"}, "james")
    assert_decodes("Playlist", bare, PLAYLIST_AHEAD)
    assert bare["coverArt"] is None and not bare["mine"]
    # with_songs() is one playlist: its summary, its songs and how many aren't listed
    whole = playlist_rules.with_songs(NAVIDROME_PLAYLIST, "james", 1)
    assert set(fields("PlaylistWithSongs")) == set(whole) == {"playlist", "songs", "hidden"}
    assert_decodes("PlaylistWithSongs", whole)
    assert_decodes("Playlist", whole["playlist"], PLAYLIST_AHEAD)
    assert whole["playlist"]["songCount"] == 2 and whole["hidden"] == 1
    # the songs as Navidrome sent them, which carry what Song needs (its id: everything else may be left out)
    assert all(required_fields("Song") <= set(song) for song in whole["songs"]) and required_fields("Song") == {"id"}
    # and the two routes send them so: the list under "playlists", one through _answer (with_songs)
    assert fields("PlaylistList") == {"playlists": False}
    assert '{"playlists": [playlist_rules.summary(' in inspect.getsource(navidrome.playlists)
    assert "return _answer(found, counter, asker)" in inspect.getsource(navidrome.playlist)
    assert "playlist_rules.with_songs(" in inspect.getsource(navidrome._answer)


def test_the_playlist_writes_send_what_the_server_declares():
    # each body is extra="forbid": a key the server doesn't declare is a 422 for every write, and so is one it requires
    # left out - and a Swift nil is left out of the JSON, so only a field with a default may be optional
    for struct, model in (("NewPlaylistBody", navidrome.NewPlaylist), ("PlaylistAddBody", navidrome.PlaylistAdd),
                          ("PlaylistEditBody", navidrome.PlaylistEdit)):
        assert model.model_config.get("extra") == "forbid", struct
        assert sent_fields(struct) == set(fields(struct)) == set(model.model_fields), \
            f"{struct}: {sorted(set(fields(struct)) ^ set(model.model_fields))}"
        needed = {name for name, field in model.model_fields.items() if field.is_required()}
        assert needed <= required_fields(struct), f"{struct} may leave out {sorted(needed - required_fields(struct))}"
        assert optional_fields(struct) <= set(model.model_fields) - needed
    assert optional_fields("PlaylistEditBody") == {"tried", "name", "comment", "public"}
    assert required_fields("PlaylistEditBody") == {"base", "song_ids"}
    # the duplicates the phone can name are the route's own
    enum = re.search(r"public enum PlaylistDuplicates\b[^{]*\{\s*case ([^\n]+)", (CORE / "PlaylistChanges.swift").read_text(
        encoding="utf-8"))
    assert enum, "no PlaylistDuplicates in PlaylistChanges.swift"
    named = {case.strip() for case in enum.group(1).split(",")}
    assert named == set(typing.get_args(navidrome.PlaylistAdd.model_fields["duplicates"].annotation)) == {"ask", "add", "skip"}
    # the bounds the phone keeps a typed name and description within are the server's
    assert swift_constant("Playlists.swift", "PlaylistRules", "nameMax") == playlist_rules.PLAYLIST_NAME_MAX
    assert swift_constant("Playlists.swift", "PlaylistRules", "commentMax") == playlist_rules.PLAYLIST_COMMENT_MAX
    assert swift_constant("Playlists.swift", "PlaylistRules", "songsMax") == playlist_rules.PLAYLIST_SONGS_MAX


def test_the_playlist_writes_answer_what_the_app_decodes():
    # the add: three answers, each with done and already - asked when nothing was written, added when it was
    literals = returned_literals(navidrome.add_to_playlist)
    assert len(literals) == 3
    assert set().union(*(literal_keys(one) for one in literals)) == set(fields("PlaylistAddAnswer"))
    assert required_fields("PlaylistAddAnswer") == {"done", "already"}
    assert all(required_fields("PlaylistAddAnswer") <= literal_keys(one) for one in literals)
    assert not any(literal_nulls(one) for one in literals)
    # the delete: {"deleted": True}
    (deleted,) = returned_literals(navidrome.delete_playlist)
    assert literal_keys(deleted) == set(fields("PlaylistDeleted")) == {"deleted"}
    # a new playlist and Edit's Done answer the playlist with its songs, as the read does
    assert "return playlist_rules.with_songs(found, asked_as(client), 0)" in inspect.getsource(navidrome.create_playlist)
    assert "return _answer(found, counter, asker)" in inspect.getsource(navidrome.edit_playlist)
    # the statuses the phone reads: 409 changed in another app (nothing written - the page draws it as it is now), 404
    # gone, 403 not the asker's - ErrorWords says the server's own words for each
    edit = inspect.getsource(navidrome.edit_playlist)
    assert "status_code=409, detail=playlist_rules.CHANGED" in edit
    writable = inspect.getsource(navidrome._writable)
    assert "status_code=404, detail=playlist_rules.GONE" in writable
    assert "status_code=403, detail=playlist_rules.NOT_YOURS" in writable
