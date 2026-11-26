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

And slice 3b's Library Shuffle (phase4-library.md 2.7, 2.8): ShuffleStart and ShufflePage to what /shuffle and
/shuffle/{token} return, their songs' fields among SHUFFLE_FIELDS, PagedScope the scopes /shuffle takes, the 404 the
feed starts over on and the 413's words; and the numbers and words the phone holds by hand from the web (question 24) -
SHUFFLE_FRESH_MS, FEED_BELOW, FEED_RETRY_MS and the Shuffle's three sentences, read from ShuffleSongs.tsx and
useShuffleFeed.ts - with SHUFFLE_FRESH_MS the route's SHUFFLE_LIST_TTL_S.

And slice 4's artists (phase4-library.md 2.6): ArtistList, Artist and ArtistWithAlbums to what /artists (getArtists'
index flattened under "artists") and /artists/{id} (getArtist's artist as Navidrome sent it, `{}` for none) return -
every field the phone reads one Navidrome sends, the id the one it can't do without - over the routes' own tests'
answers (tests/test_navidrome_artists.py).

And Phase 6's Requests (notes/ios-specs/phase6-get-requests.md): DownloadJob and JobsAnswer to what /download/jobs
builds (its merged row, the transfer summary, the runners-up, who asked and the library grant) and to a real answer of
the route; CancelAnswer, RetryAnswer, RetrySameAnswer and ClearAnswer to what the four writes and the poller's retries
return, the statuses the phone reads, and the writes' time to answer held above what deadwax may take.

And Phase 6's Get (slice 2): what a Get sends - GetRelease, GetTrack, FindCandidatesBody, EnqueueBody, its runners-up,
the folder's files and quality - every field one the routes declare (pydantic drops an undeclared one without a word);
StoreStateAnswer, HeldPressing, DownloadInFlight, OtherPressing, Candidate, FindCandidatesAnswer and EnqueueAnswer
within what /store_state, /find_candidates and /enqueue build; GetSettings and its three enums the preferences route's
own; a search's time to answer above what deadwax may take; and Get albums the routes' own permission.

And slice 3's Join, Add and You's three: JoinAnswer within what the join route returns, its refusals 409s in words and
Get albums its permission, and its time to answer above the release lock it waits on; Add from the store line sending
the Get's release, FindCandidatesRequest's fields; GetChoice to the extra="forbid" Preferences it is PUT to (only
what was chosen, each value one the route takes) and GetSettingsAnswer's `can_save` to what both preference routes answer.

And app 0.13's Album info (notes/ios.md "Album info"): AlbumFiles and AlbumFile to what /library/tracks sends
(read_album_details); the answers the Swift tests decode (Fixtures/albuminfo/files.json, written by
ios/scripts/album_files_answers.py over a FLAC set, an MP3 and an M4A tagged as Picard tags them, and a FLAC set and an
M4A tagged by deadwax's own filing) to what the helper makes now and to the real route's answer over the same folders;
AlbumTag's names - the server's among DETAIL_TAGS, each container's as Picard writes it - finding every tag the sheet
reads in those answers, deadwax's whole-release media among them; and libraryTracks' timeout above the transport's own
and the sheet's hold, the route having no bound of its own.
"""

import asyncio
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

from src import auth, autoeq, levels, loudness, lyrics, poller, users  # noqa: E402
from src import store as store_module  # noqa: E402
from src import store_index  # noqa: E402
from src.artists import artist_match  # noqa: E402
from src import play_history as history_rules  # noqa: E402
from src import playlists as playlist_rules  # noqa: E402
from src import play_queue as queue_rules  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import CLIENT_NAME  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import eq as eq_route  # noqa: E402
from src.routes import library as library_route  # noqa: E402
from src.api import musicbrainz_endpoint  # noqa: E402
from src.api import slskd_endpoint  # noqa: E402
from src.routes import coverart as coverart_route  # noqa: E402
from src.routes import download as download_route  # noqa: E402
from src.routes import me as me_route  # noqa: E402
from src.routes import my_library, navidrome, search_musicbrainz, store_album  # noqa: E402
from src.routes import play_history as history_route  # noqa: E402
from src.routes.auth import SignIn  # noqa: E402
from src.routes.download import FindCandidatesRequest  # noqa: E402
from src.store import JobStore  # noqa: E402

CORE = Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
ENDPOINT = re.compile(r'Endpoint\(method: "(\w+)", path: "([^"]+)", query: \[([^\]]*)\]\)')
ROUTE_COUNT = 112
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


def fields(struct: str, body: str | None = None) -> dict[str, bool]:
    """A struct's stored properties by JSON name -> whether optional: its own `let`s (not a nested type's), named as
    its CodingKeys say; a property CodingKeys leaves out is never read, so isn't here. `body` for a struct whose name
    another type in DeadwaxCore shares (struct_in)."""
    body = swift_struct(struct) if body is None else body
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

    def pacing(name: str) -> int:
        # (Phase 5) Search's counts: All's search3 and a kind view's own (SearchPacing, the web's SEARCH_COUNTS)
        return swift_constant("SearchList.swift", "SearchPacing", name)

    sent = [
        ((search, "songCount"), [swift_constant("TestSongs.swift", "TestSounds", "pageSize"), hi_res,
                                 pacing("songCount"), pacing("chipSongCount")]),
        ((search, "songOffset"), [0, (pages - 1) * hi_res, pacing("chipSongCount")]),
        ((search, "artistCount"), [0, pacing("artistCount"), pacing("chipArtistCount")]),
        ((search, "albumCount"), [0, pacing("albumCount"), pacing("chipAlbumCount")]),
        # a kind view's More asks from the rows it has (SearchState.askingMore), the other kinds' offsets 0
        ((search, "artistOffset"), [0, pacing("chipArtistCount")]),
        ((search, "albumOffset"), [0, pacing("chipAlbumCount")]),
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
    assert {"version", "permissions", "permissions_unverified", "lastfm"} <= {name for name, optional in fields("Me").items() if optional}
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
    # `yours` only with logins on and a folder held - read from the route (since 2.1.40 its two halves: by a release,
    # and by a job - a manual search's download, which the app's Done row asks by - whose answer has the same keys)
    by_job = inspect.getsource(store_album._by_job)
    source = inspect.getsource(store_album.store_album) + inspect.getsource(store_album._by_release) + by_job
    assert 'answer["yours"]' in source and 'answer["yours"]' in by_job
    job_answer = re.search(r"answer = (\{.*?\})\n", by_job, re.S)
    assert job_answer and set(re.findall(r'"(\w+)":', job_answer.group(1))) == set(body), "a job's answer is the same shape"
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


def assert_decodes(struct: str, answer: dict, read: dict[str, bool] | None = None):
    """What decoding `answer` as `struct` needs: every field the Swift reads is a key the answer has (one renamed would
    read as absent, or fail), and every one it can't do without is there and not null (a null where the Swift has a
    plain type fails the whole answer). `read`: the struct's `fields`, for a caller decoding many answers (each read
    parses every DeadwaxCore file)."""
    read = fields(struct) if read is None else read
    reads = set(read)
    assert reads <= set(answer), f"{struct} reads {sorted(reads - set(answer))}, never sent"
    sent = {name for name, value in answer.items() if value is not None}
    needs = {name for name, optional in read.items() if not optional}
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


def test_the_playlist_answers_are_what_the_app_decodes():
    # summary() is each row of the list and a playlist's own: the phone reads exactly its keys - the cover optional
    # (null for an empty playlist), every other one always sent; Navidrome leaving everything out still decodes.
    # (2.1.21) `smart` among them - read by the phone ahead of main sending it (iOS slice 3's review, James: "No
    # Download for them"), exempt until then; main sends it now, so it is a field like every other
    row = playlist_rules.summary(NAVIDROME_PLAYLIST, "james")
    reads = set(fields("Playlist"))
    assert reads == set(row), sorted(reads ^ set(row))
    assert "smart" in row and row["smart"] is False
    assert optional_fields("Playlist") == {"coverArt"}
    assert_decodes("Playlist", row)
    assert row["mine"] and row["editable"] and row["public"]
    bare = playlist_rules.summary({"id": "pl2"}, "james")
    assert_decodes("Playlist", bare)
    assert bare["coverArt"] is None and not bare["mine"]
    # with_songs() is one playlist: its summary, its songs and how many aren't listed
    whole = playlist_rules.with_songs(NAVIDROME_PLAYLIST, "james", 1)
    assert set(fields("PlaylistWithSongs")) == set(whole) == {"playlist", "songs", "hidden"}
    assert_decodes("PlaylistWithSongs", whole)
    assert_decodes("Playlist", whole["playlist"])
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


# ---------------------------------------------------------------------------- slice 3b's Library Shuffle

WEB_APP = Path(__file__).resolve().parent.parent / "ui" / "src" / "app"


def web_constant(file: str, name: str):
    """`export const <name> = <number or string>` in a ui/src/app file: an int (underscores allowed) or the string."""
    text = (WEB_APP / file).read_text(encoding="utf-8")
    found = re.search(r"^export const " + name + r"\s*=\s*(.+?)\s*$", text, re.M)
    assert found, f"no {name} in {file}"
    value = found.group(1)
    if re.fullmatch(r"[\d_]+", value):
        return int(value.replace("_", ""))
    quoted = re.fullmatch(r"'([^']*)'|\"([^\"]*)\"", value)
    assert quoted, f"{file} {name} is {value}"
    return quoted.group(1) if quoted.group(1) is not None else quoted.group(2)


def swift_words(file: str, holder: str, name: str) -> str:
    """`public static let <name> = "<words>"` inside `<holder>` of a DeadwaxCore file, its \\u{...} escapes read."""
    text = (CORE / file).read_text(encoding="utf-8")
    start = re.search(r"public (?:enum|struct) " + holder + r"\b", text)
    assert start, f"no {holder} in {file}"
    body = text[start.end():text.index("\n}\n", start.end())]
    found = re.search(r'public static let ' + name + r' = "((?:[^"\\]|\\.)*)"\n', body)
    assert found, f"no {holder}.{name} in {file}"
    return re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), found.group(1)).replace('\\"', '"')


def swift_struct_constant(file: str, holder: str, name: str) -> int:
    """`public static let <name> = <int>` inside `public struct <holder>` (swift_constant reads enums)."""
    text = (CORE / file).read_text(encoding="utf-8")
    start = re.search(r"public struct " + holder + r"\b", text)
    assert start, f"no {holder} in {file}"
    body = text[start.end():text.index("\n}\n", start.end())]
    found = re.search(r"public static let " + name + r" = ([\d_]+)\b", body)
    assert found, f"no {holder}.{name} in {file}"
    return int(found.group(1).replace("_", ""))


def test_the_shuffle_answers_are_what_the_app_decodes(monkeypatch):
    # /shuffle answers its token, total and first page; /shuffle/{token} its total and the page - the phone reads
    # exactly those keys, and can't do without the token (a first page with none couldn't be paged)
    (start_answer,) = returned_literals(navidrome.shuffle)
    (page_answer,) = returned_literals(navidrome.shuffle_more)
    assert set(fields("ShuffleStart")) == literal_keys(start_answer) == {"token", "total", "songs"}
    assert set(fields("ShufflePage")) == literal_keys(page_answer) == {"total", "songs"}
    assert not literal_nulls(start_answer) and not literal_nulls(page_answer)
    shuffle_code = _code((CORE / "Shuffle.swift").read_text(encoding="utf-8"))
    assert "token = try fields.decode(String.self, forKey: .token)" in shuffle_code
    # the songs are trimmed to SHUFFLE_FIELDS, and the phone makes its entries with shuffledTrack, which reads only
    # those (test_the_queue_answer_is_what_get_queue_sends holds it): the feed's own track() goes through it
    assert '"songs": _shuffle_page(held, 0)' in start_answer and '"songs": _shuffle_page(held, offset)' in page_answer
    assert "shuffledTrack(song)" in swift_function("Shuffle.swift", "track")
    # PagedScope is the scope /shuffle takes - and /album_index's, the same two
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    routes = app_routes()
    shuffle = routes[("GET", "/deadwax/navidrome/shuffle")]
    scope = next(field for field in shuffle.dependant.query_params if field.alias == "scope")
    assert swift_raw_values("UpNextTypes.swift", "PagedScope") == set(typing.get_args(scope.field_info.annotation)) \
        == {"yours", "store"}
    claim = next(field for field in shuffle.dependant.query_params if field.alias == "claim")
    assert claim.field_info.annotation is bool and '("claim", "true")' in swift_function("DeadwaxClient.swift", "shuffleStart")
    # the offset the feed asks from is how many songs it has, never past the order's total - within the route's bounds
    assert bounds(routes[("GET", "/deadwax/navidrome/shuffle/{token}")], "offset") == (0, navidrome.SHUFFLE_MAX)
    # an order deadwax no longer holds is the 404 the feed starts over on; a library too big, the 413 whose words the
    # phone says as they come
    assert 'raise HTTPException(status_code=404, detail="gone")' in inspect.getsource(navidrome.shuffle_more)
    assert "raise HTTPException(status_code=413, detail=SHUFFLE_TOO_BIG)" in inspect.getsource(navidrome._shuffle_songs)
    assert "if status == 413, let detail, !detail.isEmpty { return detail }" in shuffle_code


def test_the_shuffles_numbers_and_words_are_the_webs():
    # each read here from the web's own source - and since slice 5 (question 24) the feed's behaviour is held too, by
    # ios/scripts/export-shuffle-vectors.cjs, which drives useShuffleFeed.ts itself (ShuffleVectorTests)
    assert swift_struct_constant("Shuffle.swift", "ShuffleAhead", "freshSeconds") * 1000 \
        == web_constant("ShuffleSongs.tsx", "SHUFFLE_FRESH_MS")
    assert swift_struct_constant("Shuffle.swift", "ShuffleAhead", "freshSeconds") == navidrome.SHUFFLE_LIST_TTL_S
    assert swift_constant("Shuffle.swift", "ShuffleFeed", "below") == web_constant("useShuffleFeed.ts", "FEED_BELOW")
    assert swift_constant("Shuffle.swift", "ShuffleFeed", "retrySeconds") * 1000 \
        == web_constant("useShuffleFeed.ts", "FEED_RETRY_MS")
    assert swift_words("Shuffle.swift", "ShuffleWords", "gettingReady") \
        == web_constant("ShuffleSongs.tsx", "SHUFFLE_GETTING_READY") == "Getting ready\u2026"
    assert swift_words("Shuffle.swift", "ShuffleWords", "unready") == web_constant("ShuffleSongs.tsx", "SHUFFLE_UNREADY")
    assert swift_words("Shuffle.swift", "ShuffleWords", "startedOver") \
        == web_constant("useShuffleFeed.ts", "SHUFFLE_STARTED_OVER")
    assert navidrome.SHUFFLE_TOO_BIG == "Your library is too big to shuffle here"


# ---------------------------------------------------------------------------- slice 4's artists

def test_the_artist_answers_are_what_the_app_decodes():
    # /artists flattens getArtists' index into one list under "artists"; /artists/{id} hands getArtist's artist back as
    # Navidrome sent it, {} for none (the phone's nil) - each read leniently, only the id needed
    from tests import test_navidrome_artists as answers

    assert fields("ArtistList") == {"artists": False}
    (listed,) = returned_literals(navidrome.artists)
    assert literal_keys(listed) == {"artists"}
    assert 'return body.get("artist") or {}' in inspect.getsource(navidrome.artist)
    assert "if Self.isEmptyObject(" in swift_function("DeadwaxClient.swift", "artist")
    assert fields("Artist") == {"id": False, "name": True, "albumCount": True, "coverArt": True, "musicBrainzId": True}
    assert set(fields("ArtistWithAlbums")) == set(fields("Artist")) | {"album"}
    # `album` is a list in Swift, read leniently - absent or unreadable is none, so only the id is needed of an answer
    assert required_fields("ArtistWithAlbums") == {"id", "album"}
    artists_code = _code((CORE / "Artists.swift").read_text(encoding="utf-8"))
    assert "album = fields.looseList(Album.self, .album) ?? []" in artists_code
    assert "artists = fields.looseList(Artist.self, .artists) ?? []" in artists_code
    # Navidrome's own answers, as the routes' tests have them: every field the phone reads is one getArtists and
    # getArtist send, and the id is always there
    for initial in answers.INDEX["index"]:
        for one in initial["artist"]:
            assert set(one) <= set(fields("Artist")), one
            assert {"id"} <= set(one)
    assert_decodes("Artist", answers.PORTISHEAD)
    assert set(fields("ArtistWithAlbums")) == set(answers.ARTIST)
    for album in answers.ARTIST["album"]:
        assert set(album) <= set(fields("Album")), album
        assert required_fields("Album") <= set(album)


# ---------------------------------------------------------------------------- Phase 5, slice 1: Search

def test_the_owned_answer_is_what_the_app_decodes():
    # /library/owned answers {albums, problem}, each album OWNED_FIELDS and, with logins on, `yours` - every field the
    # phone reads is one it sends (one renamed would read as absent: no album artist to read the box against, every
    # folder the collection's), and only the path is needed of a row
    source = inspect.getsource(library_route.owned)
    assert re.search(r'json_with_etag\(request, \{\s*"albums": albums,\s*', source)
    assert '"problem": result.get("problem")' in source
    assert 'album["yours"] = album.get("path") in yours' in source
    assert set(fields("OwnedAnswer")) == {"albums", "problem"}
    assert required_fields("OwnedAnswer") == {"albums"}
    assert set(fields("OwnedAlbum")) <= set(library_route.OWNED_FIELDS) | {"yours"}
    assert required_fields("OwnedAlbum") == {"path"}
    # the answer carries an ETag, which the phone sends back (DeadwaxClient.owned): a 304 while the library is as it was
    assert "ifNoneMatch" in swift_function("DeadwaxClient.swift", "owned")


def test_search_answers_what_the_app_decodes():
    # search3's three lists, under the names LibraryResults reads (each leniently: a list absent is none)
    (answer,) = returned_literals(navidrome.search)
    assert literal_keys(answer) == {"artists", "albums", "songs"}
    assert set(fields("LibraryResults")) == literal_keys(answer)


def test_the_box_is_never_longer_than_the_route_takes(monkeypatch):
    # the phone clamps the box to SearchReading.maxCharacters Unicode scalars (SearchModel.clamped) - a str's length
    # in Python, which `q`'s max_length counts: a bound lowered under it would make a long search a 422
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    search = app_routes()[("GET", "/deadwax/navidrome/search")]
    query = next(f for f in search.dependant.query_params if f.alias == "q")
    lengths = {type(rule).__name__: rule for rule in query.field_info.metadata}
    assert swift_constant("SearchReading.swift", "SearchReading", "maxCharacters") == lengths["MaxLen"].max_length == 200


# ---------------------------------------------------------------------------- Phase 5, slice 2: albums you don't have

def test_musicbrainzs_albums_are_asked_and_read_as_the_server_answers(monkeypatch):
    # /fully_search asked as the web's Search asks it - quick (a search's patience, a 400 said as words, MusicBrainz
    # shedding said as busy), no pressings walked - and its answer's two keys under the names FullySearchAnswer reads
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    body = swift_function("DeadwaxClient.swift", "fullySearch")
    assert '("releases", "false")' in body and '("quick", "true")' in body and '("limit", String(limit))' in body
    route = app_routes()[("GET", "/deadwax/search_musicbrainz/fully_search")]
    low, high = bounds(route, "limit")
    assert low <= swift_constant("SearchAlbums.swift", "SearchAlbums", "limit") <= high
    source = inspect.getsource(musicbrainz_endpoint.MusicBrainzClient.fully_search)
    assert 'return {"release-groups": release_groups["release-groups"], "best-match-releases": [], **counted}' in source
    assert 'counted = {"count": count}' in source
    assert set(fields("FullySearchAnswer")) == {"release-groups", "count"}
    assert required_fields("ReleaseGroup") == {"id"}
    # (Phase 8, slice 1) and MusicBrainz's own `score`, which Edit album's group ranking breaks ties by
    # (release.ts scoreReleaseGroupMatch) - passed through untouched in the release groups MusicBrainz sent
    assert set(fields("ReleaseGroup")) == {"id", "title", "first-release-date", "primary-type", "secondary-types",
                                           "artist-credit", "score"}
    assert fields("ReleaseGroup")["score"], "optional: a browse's groups carry none"


def test_an_albums_pressings_are_read_as_the_route_answers_them():
    # /release_group's {id, releases, problem} - `problem` the page's trouble, never a short list passed off as the
    # album's pressings
    (answer,) = returned_literals(search_musicbrainz.release_group)
    assert literal_keys(answer) == {"id", "releases", "problem"} == set(fields("ReleaseGroupAnswer"))
    assert "release_group_mbid" in swift_function("DeadwaxClient.swift", "releaseGroup")
    # the ids the app tells apart from a cold address are the ones the routes take (MBID.isOne spells the pattern out)
    text = (CORE / "MusicBrainz.swift").read_text(encoding="utf-8")
    assert search_musicbrainz.MBID_PATTERN == "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    assert "/" + search_musicbrainz.MBID_PATTERN + "/" in text


def test_the_cover_relay_is_asked_for_a_kind_and_a_size_it_takes(monkeypatch):
    # the app's two sizes and two kinds within the relay's Literals - another would be a 422, drawn as the empty cover
    # for every MusicBrainz album
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    route = app_routes()[("GET", "/deadwax/coverart/{kind}/{mbid}")]
    taken = {field.alias: set(typing.get_args(field.field_info.annotation)) for field in
             route.dependant.query_params + route.dependant.path_params if field.alias in ("kind", "size")}
    # (Phase 8, slice 1) and Edit album's Compare covers' 500
    sizes = {str(swift_constant("Routes.swift", "ArchiveCoverSize", name)) for name in ("row", "hero", "compare")}
    assert sizes <= taken["size"]
    assert swift_raw_values("MusicBrainz.swift", "Kind") == taken["kind"] == {"release", "release-group"}
    # anything but a front (none, the Archive away, a server before 2.1.24 that answers the route's own 404) is nil
    body = swift_function("DeadwaxClient.swift", "archiveCover")
    assert "case 200:" in body and "default: return nil" in body
    assert coverart_route.COVER_CACHE == "private, max-age=604800"


def test_the_app_waits_for_musicbrainz_as_long_as_deadwax_does():
    # a quick search gives up after SEARCH_PATIENCE's attempts and the rate limiter's turns; an album's pressings are
    # several pages of MusicBrainz's browse - the phone's transport's own 8 s would give up before deadwax answers
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    patience = musicbrainz_endpoint.SEARCH_PATIENCE
    window = musicbrainz_endpoint.RateLimit.time_window
    assert timeouts["fullySearch"] > patience.attempts * patience.busy_pause + window
    assert timeouts["releaseGroup"] > timeouts["fullySearch"]


def test_a_held_album_is_found_by_its_release():
    # the id bridge asked by a release you hold (DeadwaxClient.navidromeAlbum(releaseMbid:)), its navidrome_id read -
    # since Phase 6's slice 1 through storeAlbum(releaseMbid:), the whole answer, which a Done row's note reads too
    text = _code((CORE / "DeadwaxClient.swift").read_text(encoding="utf-8"))
    assert 'func storeAlbum(releaseMbid: String) async throws -> StoreAlbum {' in text
    assert 'call(Routes.storeAlbum, query: [("release_mbid", releaseMbid)])' in text
    assert "let answer = try await storeAlbum(releaseMbid: releaseMbid)" in text
    assert "release_mbid" in inspect.signature(store_album.store_album).parameters
    assert "navidrome_id" in fields("StoreAlbum")


# ---------------------------------------------------------------------------- Phase 5, slice 3: artists and songs

SONGS = Path(__file__).resolve().parent / "fixtures" / "songs"


def _hyphenated_keys(literal: str) -> set[str]:
    """literal_keys for MusicBrainz's own names ("release-groups"), which carry hyphens."""
    return set(re.findall(r'"([\w-]+)":', _top_level(literal)))


def test_musicbrainzs_artists_and_songs_are_asked_within_the_routes_bounds(monkeypatch):
    # /artists and /songs asked with the app's own page - the server's default, which the web's searchList.ts keeps
    # too - under the routes' ceilings; the name the box can hold within /artists', and the longest song query the app
    # builds from it within /songs': a title and an artist out of the box's 200 characters, each quote and backslash
    # escaped (doubled), the artist named twice, and the fielded query's own 45 characters
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    routes = app_routes()
    artists = routes[("GET", "/deadwax/search_musicbrainz/artists")]
    songs = routes[("GET", "/deadwax/search_musicbrainz/songs")]
    artist_limit = swift_constant("MBArtist.swift", "MBArtistSearch", "limit")
    song_limit = swift_constant("SongSearch.swift", "SongSearch", "limit")
    low, high = bounds(artists, "limit")
    assert low <= artist_limit <= high and artist_limit == search_musicbrainz.ARTIST_SEARCH_LIMIT
    low, high = bounds(songs, "limit")
    assert low <= song_limit <= high and song_limit == search_musicbrainz.SONG_SEARCH_LIMIT
    box = swift_constant("SearchReading.swift", "SearchReading", "maxCharacters")
    assert search_musicbrainz.ARTIST_SEARCH_NAME_MAX >= box
    shell = len('recording:"" AND (artist:"" OR artistname:"")')
    assert shell == 45
    assert search_musicbrainz.SONG_SEARCH_QUERY_MAX >= 4 * box + shell
    assert '"recording:\\(SearchReading.quoteTerm(title)) AND (artist:\\(artist) OR artistname:\\(artist))"' in \
        swift_function("SongSearch.swift", "fieldedQuery")
    # the words go as they are: the server asks MusicBrainz for the name and its aliases itself
    assert '("name", name), ("limit", String(limit))' in swift_function("DeadwaxClient.swift", "searchArtists")
    assert '("query", query), ("limit", String(limit))' in swift_function("DeadwaxClient.swift", "searchSongs")


def test_musicbrainzs_artists_and_songs_are_read_as_the_server_answers_them():
    # /artists' {matches, count}, each match artist_match's - the score left unread (the list is MusicBrainz's order)
    search = inspect.getsource(search_musicbrainz.artists)
    assert '"matches": [artist_match(artist, name)' in search and '"count": count' in search
    assert set(fields("ArtistSearchAnswer")) == {"matches", "count"}
    assert set(fields("MBArtistMatch")) == set(artist_match({}, "")) - {"score"}
    # /songs' {recordings, count}: MusicBrainz's recordings as it gave them, each with every release it is on
    source = inspect.getsource(musicbrainz_endpoint.MusicBrainzClient.search_recordings)
    assert 'return {"recordings": found["recordings"], **counted}' in source
    assert set(fields("SongSearchAnswer")) == {"recordings", "count"}
    # ...so what the app reads of a recording is what MusicBrainz's real answers carry (tests/fixtures/songs, recorded)
    seen = {"recording": set(), "release": set(), "medium": set(), "track": set()}
    for path in sorted(SONGS.glob("*.json")):
        for recording in json.loads(path.read_text(encoding="utf-8")).get("recordings", []):
            seen["recording"] |= set(recording)
            for release in recording.get("releases", []):
                seen["release"] |= set(release)
                for medium in release.get("media", []):
                    seen["medium"] |= set(medium)
                    for track in medium.get("track", []):
                        seen["track"] |= set(track)
    assert all(seen.values()), "no recorded song search under tests/fixtures/songs"
    assert set(fields("MBRecording")) <= seen["recording"]
    assert set(fields("MBRecordingRelease")) <= seen["release"]
    assert set(fields("MBRecordingMedium")) <= seen["medium"]
    assert set(fields("MBRecordingTrack")) <= seen["track"]
    # read leniently: a recording, a release, a medium or a track missing any of it is still one
    for struct in ("MBRecording", "MBRecordingRelease", "MBRecordingMedium", "MBRecordingTrack", "MBArtistMatch"):
        assert "fields.loose" in swift_struct(struct), struct


def test_a_musicbrainz_artists_page_is_asked_and_read_as_the_routes_answer():
    # who they are: /artist's fields, the line under the name reading only some of them
    assert set(fields("MBArtistFacts")) <= set(search_musicbrainz.ARTIST_FACT_FIELDS)
    assert {"type", "area", "began", "ended_on", "ended"} <= set(fields("MBArtistFacts"))
    assert '("mbid", mbid)' in swift_function("DeadwaxClient.swift", "artistFacts")
    # their albums: /discography as the web's artist page asks it - albums, the studio ones alone with Studio only -
    # under the names the route answers with, `problem` the trouble (never a short list passed off as their albums)
    body = swift_function("DeadwaxClient.swift", "discography")
    assert '("artist_mbid", mbid), ("types", "album")' in body and '("studio_only", "true")' in body
    assert "album" in search_musicbrainz.DISCOGRAPHY_TYPES
    taken = inspect.signature(search_musicbrainz.discography).parameters
    assert {"artist_mbid", "types", "studio_only"} <= set(taken)
    answers = returned_literals(musicbrainz_endpoint.MusicBrainzClient.get_artist_release_groups)
    assert answers and all({"release-groups", "truncated", "problem"} <= _hyphenated_keys(one) for one in answers)
    assert set(fields("DiscographyAnswer")) == {"release-groups", "truncated", "problem"}


def test_the_app_waits_for_an_artists_page_as_long_as_deadwax_does():
    # /artists and /songs are quick searches, as /fully_search is; /artist is one lookup with deadwax's ten attempts,
    # each turned away for 3 s while MusicBrainz is busy, with the rate limiter's turns; /discography a browse of up to
    # five pages, as an album's pressings are
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    patience = musicbrainz_endpoint.SEARCH_PATIENCE
    window = musicbrainz_endpoint.RateLimit.time_window
    for name in ("searchArtists", "searchSongs"):
        assert timeouts[name] > patience.attempts * patience.busy_pause + window, name
    for route in (search_musicbrainz.artists, search_musicbrainz.songs):
        assert "quick=True" in inspect.getsource(route)
    client = musicbrainz_endpoint.MusicBrainzClient
    assert "await asyncio.sleep(3.0)" in inspect.getsource(client._ask)
    assert "patience" not in inspect.getsource(client.get_artist)
    assert timeouts["artistFacts"] > client.RETRIES * 3.0 + window
    assert client.DISCOGRAPHY_MAX // client.DISCOGRAPHY_PAGE == 5
    assert timeouts["discography"] >= timeouts["releaseGroup"] > timeouts["fullySearch"]


# ---------------------------------------------------------------------------- Phase 5, slice 4: what's saved, More


def test_whats_saved_is_asked_and_read_as_the_route_answers_it(monkeypatch):
    # /saved by the words typed - the box's 200 characters within its bound, never nothing - answering each kind in
    # the shape of the route the app already reads it from, and `available` (false: nothing searched, never an error)
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    route = app_routes()[("GET", "/deadwax/search_musicbrainz/saved")]
    words = next(f for f in route.dependant.query_params if f.alias == "words")
    lengths = {type(rule).__name__: rule for rule in words.field_info.metadata}
    box = swift_constant("SearchReading.swift", "SearchReading", "maxCharacters")
    assert lengths["MinLen"].min_length == 1
    assert lengths["MaxLen"].max_length >= box
    assert '("words", words)' in swift_function("DeadwaxClient.swift", "savedSearch")
    assert set(fields("SavedSearchAnswer")) == {"artists", "albums", "songs", "credited", "available"}
    answers = returned_literals(search_musicbrainz.saved)
    assert answers and all("available" in literal_keys(one) for one in answers)
    source = inspect.getsource(search_musicbrainz.saved)
    for kind in ("artists", "albums", "songs", "credited"):
        assert f'"{kind}":' in source, kind
    # read leniently: a kind missing or of the wrong shape is none, a missing `available` nothing searched
    assert "looseField" in swift_struct("SavedSearchAnswer")
    # ...and bounded to the app's own page of each, which the app's kinds draw as MusicBrainz's would be
    from src import saved_index
    assert saved_index.SAVED_ARTISTS == swift_constant("MBArtist.swift", "MBArtistSearch", "limit")
    assert saved_index.SAVED_ALBUMS == swift_constant("SearchAlbums.swift", "SearchAlbums", "limit")
    assert saved_index.SAVED_SONGS == swift_constant("SongSearch.swift", "SongSearch", "limit")
    # the artist reading draws at most a page of an artist's saved albums, from the credited list (50)
    assert swift_constant("SearchSaved.swift", "SearchSaved", "artistAlbums") <= saved_index.SAVED_CREDITED


def test_more_from_musicbrainz_asks_within_the_routes_offsets(monkeypatch):
    # More asks the next page by offset - never past SearchMore.offsetMax (morePages says narrow it instead), which
    # every search route takes; sent only past the first page, so the first is asked as it always was
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    routes = app_routes()
    furthest = swift_constant("SearchSaved.swift", "SearchMore", "offsetMax")
    assert furthest == search_musicbrainz.FULLY_SEARCH_OFFSET_MAX
    for path in ("fully_search", "artists", "songs"):
        low, high = bounds(routes[("GET", f"/deadwax/search_musicbrainz/{path}")], "offset")
        assert low <= 0 and furthest <= high, path
    for name in ("fullySearch", "searchArtists", "searchSongs"):
        body = swift_function("DeadwaxClient.swift", name)
        assert 'if offset > 0 { fields.append(("offset", String(offset))) }' in body, name


def test_the_apps_kept_answers_last_deadwaxs_own_hour():
    # (slice 4's review) the phone answers a search again from what it kept for as long as deadwax answers it from
    # memory - ResponseCache's hour - so a search repeated days later is asked again, never answered from the morning's
    from src.api.musicbrainz_endpoint import ResponseCache
    hour = inspect.signature(ResponseCache.__init__).parameters["ttl_seconds"].default
    text = (CORE / "SearchSaved.swift").read_text(encoding="utf-8")
    body = re.search(r"public struct SearchAnswersKept\b[^{]*\{(.*?)\n\}", text, re.S)
    assert body, "no SearchAnswersKept in SearchSaved.swift"
    found = re.search(r"public static let lifetime: Double = ([\d_]+)\b", body.group(1))
    assert found, "no SearchAnswersKept.lifetime"
    assert float(found.group(1).replace("_", "")) == hour


# ---------------------------------------------------------------------------- Phase 6, slice 1: Requests

PER_PERSON = {"mine", "shared", "requested_by", "library"}


def _jobs_row_keys() -> tuple[set[str], set[str]]:
    """What /download/jobs can send of a row, from its source: the merged literal's own keys (always sent), with the
    transfer summary, the runners-up, who asked and the library grant laid on - and the always-sent ones alone."""
    source = inspect.getsource(download_route.jobs)
    opening = re.search(r"merged\.append\(\{", source)
    assert opening, "no merged.append({...}) in the jobs route"
    always = literal_keys(_block(source, opening.end() - 1))
    summary = set().union(*(literal_keys(one) for one in returned_literals(store_module.summarize_transfers)))
    #? a finished job's summary is the route's own literal, the open one's summarize_transfers'
    assert '"files_total": len(job["files"]), "matched": False}' in source
    assert '**({"alternatives_left": len(untried_alternatives(job))}' in source
    assert '**({"library": job.get("library_grant")} if logins else {})' in source
    assert "**_per_person(job, user, admin)" in source
    person = set().union(*(literal_keys(one) for one in returned_literals(download_route._per_person)))
    assert '**({"requested_by": others} if admin else {})' in inspect.getsource(download_route._per_person)
    #? (2.1.38, manual search slice A1) a manual search's download is marked - only when it is one
    assert '**({"manual": True} if job.get("manual") else {})' in source
    #? (2.1.40, slice A2) and, once filed, what it was filed as - only on a manual row the store still has
    assert '**({"filed_as": filed[job["album_id"]]} if job.get("manual") and job.get("album_id") in filed' in source
    return always | summary | person | {"alternatives_left", "library", "requested_by", "manual", "filed_as"}, always


def test_a_download_is_read_as_the_jobs_route_sends_it():
    # every field the phone reads of a row is one the route sends, and the two it can't do without - the id and the
    # status - are in the literal every row is built from, never null; the rest are read leniently (looseField)
    sent, always = _jobs_row_keys()
    reads = set(fields("DownloadJob"))
    assert reads <= sent, f"DownloadJob reads {sorted(reads - sent)}, never sent"
    assert required_fields("DownloadJob") == {"id", "status"} <= always
    assert PER_PERSON <= reads
    body = swift_struct("DownloadJob")
    assert body.count("c.looseField(") + body.count("c.looseList(") == len(reads) - 2
    # the answer: both returns carry both keys
    answers = returned_literals(download_route.jobs)
    assert len(answers) == 2 and all(literal_keys(one) == {"jobs", "tracking_enabled"} for one in answers)
    assert required_fields("JobsAnswer") == {"jobs", "tracking_enabled"}


def test_the_jobs_route_answers_what_the_app_decodes(monkeypatch, tmp_path):
    # through the real route with logins off (one user, every download theirs): a download on its way, one filed and
    # one failed with a runner-up left - every field the phone reads is in one of them, but who asked and the library
    # grant, which are sent only with logins on (the source test above holds those)
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    #? (slice A2) the library the manual one was filed into, so its store row is live
    root = str(tmp_path / "library")
    monkeypatch.setattr(Config, "LIBRARY_PATH", root)
    files = [{"filename": f"share\\Dummy\\0{n}.flac", "size": 10} for n in (1, 2)]
    release = {"artist": "Portishead", "album": "Dummy", "year": "1994", "release_mbid": "rel-dummy",
               "release_group_mbid": "rg-dummy", "disambiguation": "2014 vinyl", "tracks": []}

    class Slskd:
        async def get_downloads(self, usernames=()):
            return [{"username": "bob", "directories": [{"directory": "d", "files": [
                {"id": "t1", "filename": files[0]["filename"], "state": "Queued, Remotely", "percentComplete": 0,
                 "averageSpeed": 0, "bytesTransferred": 0}]}]}]

        async def queue_position(self, username, transfer_id):
            return 4

    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()

    async def jobs():
        await store.create_job("bob", "share\\Dummy", files, release, [])
        #? (manual search, slice A1) the filed one a manual search's, as /enqueue stores it: marked on its release
        filed = await store.create_job("dave", "share\\Dummy", files, {**release, "manual": True}, [])
        #? (slice A2, 2.1.40) filed by its own tags into a folder the store knows, which /jobs names as `filed_as`
        album_id = await store.index_upsert(root, {
            "path": "Portishead/Dummy (1994) [unmatched]", "release_mbid": None, "release_group_mbid": None,
            "artist": "Portishead", "album": "Dummy", "year": "1994", "edition": "", "track_count": 2,
            "formats": ["flac"]})
        await store.set_job_album(filed, album_id)
        await store.update_status(filed, "organized")
        failed = await store.create_job("erin", "share\\Dummy", files, release,
                                        [{"username": "carol", "directory": "x", "files": files}])
        await store.update_status(failed, "failed", "the peer went offline")

    asyncio.run(jobs())
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd()
    answer = TestClient(app).get("/deadwax/download/jobs")
    assert answer.status_code == 200
    body = answer.json()
    assert set(body) == {"jobs", "tracking_enabled"} and body["tracking_enabled"] is True
    rows = body["jobs"]
    assert sorted(row["status"] for row in rows) == ["failed", "organized", "queued"]
    for row in rows:
        assert all(row.get(name) is not None for name in required_fields("DownloadJob")), row
    seen = set().union(*(set(row) for row in rows))
    missing = set(fields("DownloadJob")) - PER_PERSON - seen
    assert not missing, f"DownloadJob reads {sorted(missing)}, which no row sent"
    queued = next(row for row in rows if row["status"] == "queued")
    assert (queued["queue_position"], queued["matched"], queued["files_total"]) == (4, True, 2)
    assert next(row for row in rows if row["status"] == "failed")["alternatives_left"] == 1
    # the manual one marked, and only it: every other row as it always was, without the key
    assert [row["status"] for row in rows if "manual" in row] == ["organized"]
    assert next(row for row in rows if row["status"] == "organized")["manual"] is True
    # and what it was filed as, on it alone
    assert [row["filed_as"] for row in rows if "filed_as" in row] == [{"artist": "Portishead", "album": "Dummy"}]


def test_the_four_writes_answer_what_the_app_decodes():
    # a cancel: `left` - only your request withdrawn - or the download itself, both through literals the route returns
    cancels = returned_literals(download_route.cancel_job) + returned_literals(download_route._cancel_download)
    sent = set().union(*(literal_keys(one) for one in cancels))
    assert set(fields("CancelAnswer")) <= sent and not required_fields("CancelAnswer")
    assert all("left" in literal_keys(one) for one in cancels)
    # Another source and Same source again answer the poller's own, 200 either way: `moved` / `retried` in every one
    assert "return await retry_next_peer(" in inspect.getsource(download_route.retry_job)
    assert "return await retry_same_peer(" in inspect.getsource(download_route.retry_job_same_peer)
    for struct, function, needed in (("RetryAnswer", poller.retry_next_peer, "moved"),
                                     ("RetrySameAnswer", poller.retry_same_peer, "retried")):
        literals = returned_literals(function)
        assert literals, struct
        keys = set().union(*(literal_keys(one) for one in literals))
        assert set(fields(struct)) <= keys, f"{struct} reads {sorted(set(fields(struct)) - keys)}"
        assert required_fields(struct) == {needed}
        assert all(needed in literal_keys(one) and needed not in literal_nulls(one) for one in literals), struct
    # Clear done: how many went
    clears = returned_literals(download_route.clear_jobs)
    assert clears and all(set(fields("ClearAnswer")) <= literal_keys(one) for one in clears)
    # the statuses the phone reads: 409 for a download no longer failed or cancelled, 404 for one not the asker's
    for function in (download_route.retry_job, download_route.retry_job_same_peer):
        assert "status_code=409" in inspect.getsource(function)
    assert 'status_code=404, detail="No such download job"' in inspect.getsource(download_route._job_for)
    # and every write is a POST with no body: the routes read none (a body would be ignored without a word)
    routes = app_routes()
    for path in ("/deadwax/download/jobs/{job_id}/cancel", "/deadwax/download/jobs/{job_id}/retry",
                 "/deadwax/download/jobs/{job_id}/retry_same", "/deadwax/download/jobs/clear"):
        assert routes[("POST", path)].body_field is None, path
    for name in ("cancelJob", "retryJob", "retryJobSame", "clearJobs"):
        assert "sending:" not in swift_function("DeadwaxClient.swift", name), name


def test_the_app_waits_for_the_downloads_as_long_as_deadwax_does():
    # /download/jobs asks slskd once for every open download and each queued one's place; Another source asks up to
    # RETRY_ASKS runners-up in turn, each an ask of slskd - so it is given that many looks' time
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    for name in ("jobs", "cancelJob", "retryJob", "retryJobSame", "clearJobs"):
        assert timeouts[name] > 8, name
    assert timeouts["retryJob"] >= poller.RETRY_ASKS * timeouts["jobs"]
    assert timeouts["retryJob"] > timeouts["retryJobSame"]


# ---------------------------------------------------------------------------- Phase 6, slice 2: Get

def struct_in(file: str, declaration: str) -> str:
    """The body of the struct a declaration opens in one DeadwaxCore file - `public struct Candidate: Decodable`, where
    another type nested elsewhere shares its name."""
    code = _code((CORE / file).read_text(encoding="utf-8"))
    found = [match for match in re.finditer(re.escape(declaration) + r"[^{]*\{", code)]
    assert len(found) == 1, f"{declaration} is declared {len(found)} times in {file}"
    return _block(code, found[0].end() - 1)


def test_a_get_sends_only_what_the_routes_declare():
    # the release a Get is for, as /store_state and /find_candidates take it (FindCandidatesRequest, flat with the
    # Format and an edited query) and as /enqueue files it (EnqueueRelease) - and every track as Track
    release = sent_fields("GetRelease")
    assert release <= set(FindCandidatesRequest.model_fields), sorted(release - set(FindCandidatesRequest.model_fields))
    assert release <= set(download_route.EnqueueRelease.model_fields)
    assert {"artist", "album"} <= release
    assert sent_fields("GetTrack") <= set(download_route.Track.model_fields)
    body = sent_fields("FindCandidatesBody")
    assert body == {"format_preference", "query_override"} and body <= set(FindCandidatesRequest.model_fields)
    assert "try release.encode(to: encoder)" in swift_struct("FindCandidatesBody")
    # a card's Get: the folder, the release, the runners-up as shown and what the copy is (synthesized: every let)
    enqueue = set(fields("EnqueueBody"))
    assert enqueue == {"username", "files", "directory", "release", "alternatives", "quality"}
    assert enqueue <= set(download_route.EnqueueRequest.model_fields)
    alternative = set(fields("Alternative"))
    assert alternative <= set(download_route.Alternative.model_fields) and {"username", "files"} <= alternative
    assert sent_fields("JobQuality") <= set(download_route.Quality.model_fields)
    assert sent_fields("CandidateFile") == set(download_route.EnqueueFile.model_fields)
    # what each route can't do without is sent
    for model, sent in ((FindCandidatesRequest, release | body), (download_route.EnqueueRequest, enqueue),
                        (download_route.Alternative, alternative)):
        needed = {name for name, field in model.model_fields.items() if field.is_required()}
        assert needed <= sent, f"{model.__name__} needs {sorted(needed - sent)}"
    # the Format is one the route scores by
    assert swift_raw_values("GetSettings.swift", "FormatPreference") == set(me_route.PREFERENCES["format_preference"])


def test_the_stores_word_is_read_as_the_routes_send_it():
    # /store_state's answer, and find_candidates' with the search's on it: the four keys always sent
    nothing = returned_literals(download_route._nothing_here)
    assert len(nothing) == 1 and literal_keys(nothing[0]) == set(fields("StoreStateAnswer"))
    assert set(fields("StoreStateAnswer")) == {"held", "downloading", "downloading_part", "other_pressings"}
    # a pressing held: held_copy's literal, with the asker's word and the part's filing laid on by the route
    held = set().union(*(literal_keys(one) for one in returned_literals(store_index.held_copy)))
    source = inspect.getsource(download_route._store_state)
    assert 'held["yours"] = yours' in source and 'held["filed_to"]' in source and 'held["fills_gaps"]' in source
    assert set(fields("HeldPressing")) <= held | {"yours"}, sorted(set(fields("HeldPressing")) - held)
    # a download in flight: describe_job's, how far it has got laid on (done_files)
    described = inspect.getsource(store_index.describe_job)
    sent = set(re.findall(r'"(\w+)":', described)) | set(re.findall(r'"(\w+)"\s*[,)]', described.split("for key in", 1)[1]))
    assert 'described["done_files"]' in inspect.getsource(download_route._describe_in_flight)
    assert set(fields("DownloadInFlight")) <= sent | {"done_files"}, sorted(set(fields("DownloadInFlight")) - sent)
    # another pressing held: other_pressings' rows, whose each is laid on by the route
    others = inspect.getsource(store_index.other_pressings)
    rows = set(re.findall(r'"(\w+)":', others[others.index("found.append({"):]))
    assert 'pressing["yours"]' in source
    assert set(fields("OtherPressing")) <= rows | {"yours"}, sorted(set(fields("OtherPressing")) - rows)
    # every one read leniently: an answer missing a field is never a failure
    for struct in ("HeldPressing", "DownloadInFlight", "OtherPressing", "StoreStateAnswer"):
        body = swift_struct(struct)
        assert body.count("looseField(") + body.count("looseList(") == len(fields(struct)), struct


def test_a_search_is_read_as_find_candidates_sends_it():
    # each folder: _serialize_candidate's keys, with what deadwax measured of the peer laid on
    candidate = set(fields("Candidate", struct_in("Sources.swift", "public struct Candidate: Decodable")))
    serialized = set().union(*(literal_keys(one) for one in returned_literals(download_route._serialize_candidate)))
    measured = inspect.getsource(download_route._attach_measured_speeds)
    assert 'candidate["measured_speed"]' in measured and 'candidate["measured_samples"]' in measured
    assert candidate <= serialized | {"measured_speed", "measured_samples"}, sorted(candidate - serialized)
    # the answer: both returns (nothing searched for a pressing held or downloading whole, and a search) carry the
    # search's four keys and the store's, laid on with **store_state
    answers = returned_literals(download_route.find_candidates)
    assert len(answers) == 2
    for answer in answers:
        assert set(fields("FindCandidatesAnswer")) - {"manual"} <= literal_keys(answer)
        assert "**store_state" in answer
    #? (2.1.38, manual search slice A1) a manual question echoed - only on a search, only when it was one; the app
    #? reads its absence as a server that would file the download as a matched pressing (ManualSearch.needsNewer)
    assert [answer for answer in answers if '**({"manual": True} if body.manual else {})' in answer] == [answers[1]]
    assert "manual = fields.looseField(Bool.self, .manual) ?? false" in swift_struct("FindCandidatesAnswer")
    assert "store = try StoreStateAnswer(from: decoder)" in swift_struct("FindCandidatesAnswer")
    # an enqueue: its job, or (logins on) the download somebody else asked for, joined
    enqueued = returned_literals(download_route.enqueue)
    assert len(enqueued) == 2 and all("job_id" in literal_keys(one) for one in enqueued)
    keys = set().union(*(literal_keys(one) for one in enqueued))
    assert set(fields("EnqueueAnswer")) <= keys
    # its refusals: deadwax's 409 (already downloading, or already yours) and slskd's 502, each with its words
    source = inspect.getsource(download_route.enqueue)
    assert "status_code=409, detail=problem" in source and "status_code=502" in source


def test_you_getting_albums_is_read_as_the_preferences_route_sends_it():
    answer = me_route._answer(None, True)
    reads = set(fields("GetSettings"))
    assert reads == {"get_mode", "quality_floor", "format_preference"} <= set(answer)
    assert swift_raw_values("GetSettings.swift", "GetMode") == set(me_route.PREFERENCES["get_mode"])
    assert swift_raw_values("GetSettings.swift", "QualityFloor") == set(me_route.PREFERENCES["quality_floor"])
    # the phone's defaults are the route's
    defaults = swift_struct("GetSettings")
    assert "static let defaults = GetSettings(mode: .sources, floor: .any, format: .preferLossless)" in defaults
    assert me_route.DEFAULTS == {"get_mode": "sources", "quality_floor": "any", "format_preference": "prefer_lossless"}


def test_the_app_waits_for_a_search_as_long_as_deadwax_does():
    # deadwax's longest search (find_candidates, slskd_endpoint's _run_searches), from the server's own numbers (slice 2's
    # review, finding 3):
    # - two rounds of slskd's search: the names the release carries, then a former name MusicBrainz gave within
    #   FORMER_NAMES_BUDGET_SECONDS (a lookup beside the first round, counted whole);
    # - every start waits its turn at SEARCH_GATE, up to SEARCH_TURN_SECONDS (a start stuck ahead of it holds the line
    #   that long) - the first round's two names (the credit and the current one), the second's one former name;
    # - each round's answers waited on for max_wait: SLSKD_SEARCH_TIMEOUT at its range's top, plus the route's allowance;
    # - and beyond max_wait, which counts only its sleeps: slskd's state asked each half second, the answers fetched and
    #   the searches deleted (ROUND_MARGIN a round), and the store's look before and the ranking after (MARGIN).
    # An artist renamed more than once starts a search behind the gate for every name: deadwax bounds none of it as a
    # whole, so this is the worst case of an artist renamed once.
    ROUND_MARGIN, MARGIN = 15, 10
    from src.config import SEARCH_TIMEOUT_RANGE
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    source = inspect.getsource(download_route.find_candidates)
    allowances = [int(found) for found in re.findall(r"max_wait=timeout \+ (\d+)", source)]
    assert len(allowances) == 2, "a search is two rounds"
    assert "for name in search_names(body.artist, body.album_artist)" in source
    searches = inspect.getsource(slskd_endpoint.SlskdClient._run_searches)
    assert "for query in queries:" in searches and "async with SEARCH_GATE.turn(query):" in searches
    assert slskd_endpoint.SEARCH_GATE.bound == slskd_endpoint.SEARCH_TURN_SECONDS
    starts = (2, 1)
    worst = sum(count * slskd_endpoint.SEARCH_TURN_SECONDS + SEARCH_TIMEOUT_RANGE[1] + allowance + ROUND_MARGIN
                for count, allowance in zip(starts, allowances)) + download_route.FORMER_NAMES_BUDGET_SECONDS + MARGIN
    assert timeouts["findCandidates"] >= worst, f"{timeouts['findCandidates']} s, but deadwax may take {worst} s"
    # and Routes.swift's account of it says the same number
    assert f"{worst:g} s at worst" in " ".join(text.replace("///", " ").split())
    # an enqueue: no bound on the server at all - the release's lock, then slskd's enqueue, which sets none of its own -
    # so the phone gives it the search's, and an answer that never comes isn't a refusal (RequestOverlays.unanswered)
    enqueue = inspect.getsource(download_route.enqueue)
    assert "async with release_lock(" in enqueue and "wait_for" not in enqueue
    assert "timeout" not in inspect.getsource(slskd_endpoint.SlskdClient.enqueue)
    assert timeouts["enqueue"] == timeouts["findCandidates"]
    # the store's look may ask slskd how far a download has got
    assert timeouts["storeState"] > 8
    assert "preferences" not in timeouts


def test_get_albums_is_the_routes_own_permission():
    # a search and an enqueue need `request`, as the app's Get the album does (Access.can(.request)); the store's word
    # needs nothing more, so someone without Get albums still sees what's here
    routes = app_routes()
    for path in ("/deadwax/download/find_candidates", "/deadwax/download/enqueue"):
        route = routes[("POST", path)]
        assert any(getattr(dependency.dependency, "__qualname__", "").startswith("require")
                   for dependency in route.dependencies), path
    assert "dependencies=GET_ALBUMS" in inspect.getsource(download_route.find_candidates)
    assert "dependencies=GET_ALBUMS" in inspect.getsource(download_route.enqueue)
    assert "dependencies=" not in inspect.getsource(download_route.store_state).split("\n", 1)[0]
    assert 'GET_ALBUMS = [Depends(require("request"))]' in inspect.getsource(download_route)
    view = (CORE.parent.parent.parent / "App" / "Search" / "GroupView.swift").read_text(encoding="utf-8")
    assert "server.access.can(.request)" in view and "RequestWords.getOff" in view
    # every body is POSTed, as the routes take them
    for name, route in (("storeState", "store_state"), ("findCandidates", "find_candidates"), ("enqueue", "enqueue")):
        assert f'public static let {name} = Endpoint(method: "POST", path: "/deadwax/download/{route}", query: [])' in \
            (CORE / "Routes.swift").read_text(encoding="utf-8")
        assert "sending:" in swift_function("DeadwaxClient.swift", name), name


# ---------------------------------------------------------------------------- Phase 6, slice 3: Join, Add, You's three

def test_a_join_is_read_as_the_join_route_answers_it():
    # one literal, the job and whether this asked joined it (false: already waiting for it) - read leniently
    (joined,) = returned_literals(download_route.join_job)
    assert set(fields("JoinAnswer")) == literal_keys(joined) == {"status", "job_id", "joined"}
    assert swift_struct("JoinAnswer").count("looseField(") == len(fields("JoinAnswer"))
    # its refusals are 409s in words, the phone's .refused (said as deadwax said them): cleared since, landed or
    # stopped since, or only part of the pressing (cleared is said at three moments) - and a database that won't write, a
    # 503 in words
    source = inspect.getsource(download_route.join_job)
    assert source.count("raise HTTPException(status_code=409") == 5
    assert "status_code=503, detail=" in source
    assert download_route.CLEARED_SINCE == "that download has been cleared from the list since - get it again"
    # a POST with no body, Get albums its permission - as the line draws Join only for someone with it
    route = app_routes()[("POST", "/deadwax/download/jobs/{job_id}/join")]
    assert route.body_field is None
    assert any(getattr(dependency.dependency, "__qualname__", "").startswith("require")
               for dependency in route.dependencies)
    assert "dependencies=GET_ALBUMS" in inspect.getsource(download_route.join_job).split("\n", 1)[0]
    assert "sending:" not in swift_function("DeadwaxClient.swift", "joinJob")
    app = CORE.parent.parent.parent / "App"
    view = (app / "Search" / "GroupView.swift").read_text(encoding="utf-8")
    assert "let allowed = server.access.can(.request)" in view and "onJoin: allowed ?" in view
    assert "joins: allowed" in view
    sheet = (app / "Get" / "SourcesSheet.swift").read_text(encoding="utf-8")
    assert sheet.count("server.access.can(.request)") == 2
    # it waits for the same release's lock an enqueue or Another source holds while it asks slskd: the phone gives
    # it Another source's time, and a second Join is harmless (`joined` false)
    assert "async with release_lock(job_lock_key(job)):" in source
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    assert timeouts["joinJob"] >= timeouts["retryJob"] > 8


def test_add_from_the_store_line_sends_the_gets_release():
    # the web's line sends download.release - the Get's whole body - to /me/library/add, which takes a
    # FindCandidatesRequest: every field the phone's GetRelease sends one it declares, and what it needs sent
    import src.routes.my_library as library_route
    assert inspect.signature(library_route.add_to_my_library).parameters["body"].annotation is FindCandidatesRequest
    release = sent_fields("GetRelease")
    assert release <= set(FindCandidatesRequest.model_fields)
    needed = {name for name, field in FindCandidatesRequest.model_fields.items() if field.is_required()}
    assert needed <= release, sorted(needed - release)
    # the line's Add: the GetRelease itself is the body, as the album page's Add sends its AddRelease
    client = _code((CORE / "DeadwaxClient.swift").read_text(encoding="utf-8"))
    opened = client.index("func addToLibrary(_ release: GetRelease) async throws -> AddedToLibrary {")
    assert "try await call(Routes.libraryAdd, sending: release)" in _block(client, client.index("{", opened))


def test_you_getting_albums_is_saved_as_the_preferences_route_takes_it():
    # PUT, its body the extra="forbid" Preferences: only the keys chosen, each one of the route's values
    routes = app_routes()
    assert ("PUT", "/deadwax/me/preferences") in routes
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    assert 'public static let savePreferences = Endpoint(method: "PUT", path: "/deadwax/me/preferences", query: [])' \
        in text
    assert me_route.Preferences.model_config.get("extra") == "forbid"
    sent = sent_fields("GetChoice")
    assert sent == set(me_route.Preferences.model_fields) == {"get_mode", "quality_floor", "format_preference"}
    assert not any(field.is_required() for field in me_route.Preferences.model_fields.values())
    for key, enum in (("get_mode", "GetMode"), ("quality_floor", "QualityFloor"),
                      ("format_preference", "FormatPreference")):
        values = set(typing.get_args(typing.get_args(me_route.Preferences.model_fields[key].annotation)[0]))
        assert swift_raw_values("GetSettings.swift", enum) == values == set(me_route.PREFERENCES[key]), key
    # what isn't chosen is never sent - a null would be one of the keys, and the route takes none as "leave it"
    encode = swift_struct("GetChoice")
    assert encode.count("encodeIfPresent(") == 3 and "encodeNil" not in encode
    assert "sending: choice" in swift_function("DeadwaxClient.swift", "saveSettings")
    # both routes answer _answer: the three, and can_save - which the phone reads, true unless deadwax says false
    answer = me_route._answer(None, False)
    assert set(fields("GetSettingsAnswer")) == {"can_save"} <= set(answer) and answer["can_save"] is False
    assert "return _answer(stored, can_save)" in inspect.getsource(me_route.preferences)
    assert "return _answer(stored, can_save)" in inspect.getsource(me_route.save_preferences)
    assert "looseField(Bool.self, .canSave) != false" in swift_struct("GetSettingsAnswer")
    assert "settings = try GetSettings(from: decoder)" in swift_struct("GetSettingsAnswer")
    # and a database that can't keep them is a 503 in words, said under the three ("Not saved. …")
    source = inspect.getsource(me_route.save_preferences)
    assert source.count("raise HTTPException(status_code=503, detail=") == 2


def test_an_add_is_given_time_for_its_stars_and_said_as_maybe_when_none_came():
    # (slice 3's review, finding 3) the add route writes your library, THEN stars it in Navidrome as you before it
    # answers - so an answer that never came may well have landed, which the phone says as maybe, never as refused
    import src.stars as stars
    source = inspect.getsource(my_library.add_to_my_library)
    assert source.index("await store.grant_albums(") < source.index("await _star_now(")
    # every star call goes through the login client, whose every phase gives up after 10 s; the first that finds
    # Navidrome away (a transport error, a timeout among them) ends the starring - the entry waits for the worker
    assert isinstance(stars.star_client, auth.LoginClient)
    phases = re.findall(r"timeout=httpx\.Timeout\(([\d.]+)\)", inspect.getsource(auth.LoginClient.get_client))
    assert len(phases) == 1
    phase = float(phases[0])
    assert "raise NavidromeDown(" in inspect.getsource(stars._fail)
    assert "unreachable=isinstance(e, httpx.TransportError)" in inspect.getsource(stars.AsUser.call)
    star_now = inspect.getsource(my_library._star_now)
    assert "except (stars.CredentialDead, stars.NavidromeDown)" in star_now and "return False" in star_now
    # so the phone waits past one call that never answers (pool, connect, write, read), as long as for a join
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    assert timeouts["libraryAdd"] > 4 * phase
    assert timeouts["libraryAdd"] == timeouts["joinJob"]
    # and the store line's Join and Add say an answer that never came as maybe, looking for it in the store
    app = CORE.parent.parent.parent / "App"
    line = _code((app / "Get" / "StoreLineView.swift").read_text(encoding="utf-8"))
    assert "if RequestOverlays.unanswered(error) {" in line and "words.unanswered" in line
    sheet = _code((app / "Get" / "SourcesSheet.swift").read_text(encoding="utf-8"))
    assert "StoreLine.joinLanded(jobId, in: answer)" in sheet and "StoreLine.addLanded(in: answer)" in sheet
    assert "try? await client.storeState(release)" in sheet
    view = _code((app / "Search" / "GroupView.swift").read_text(encoding="utf-8"))
    assert view.count("if RequestOverlays.unanswered(error) {") == 2
    requests = _code((app / "Models" / "RequestsModel.swift").read_text(encoding="utf-8"))
    join = _block(requests, requests.index("{", requests.index("func join(_ jobId: Int)")))
    assert "defer { if epoch == self.epoch { kick() } }" in join


def test_the_sources_sheet_runs_the_very_search_again_offline_and_lets_it_go_as_it_goes():
    app = CORE.parent.parent.parent / "App"
    sheet = _code((app / "Get" / "SourcesSheet.swift").read_text(encoding="utf-8"))
    search = _code((app / "Models" / "SourcesSearch.swift").read_text(encoding="utf-8"))
    # (finding 1) deadwax back: the very run again - a search again by hand stays one (its query as sent, the field
    # as typed: never `start`, which empties it), and only a fresh Get picks
    opened = sheet.index(".onChange(of: online)")
    back = _block(sheet, sheet.index("{", opened))
    assert "model.rerunOnReturn(client: server.client, settings: settings)" in back and "begin(" not in back
    rerun = _block(search, search.index("{", search.index("func rerunOnReturn(")))
    assert "SourcesRun.onReturn(lastRun, error: search.error)" in rerun
    assert "case .requery: run(search.release, kind: kind," in rerun and rerun.count("start(") == 1
    run = _block(search, search.index("{", search.index("private func run(")))
    assert "let picking = kind.picks ? lastPicking : nil" in run and "lastRun = kind" in run
    assert "queryOverride: kind.override" in run
    # (finding 2) out of reach: Join and Add off, and a pick landing then isn't asked for, but said
    assert "live: online" in sheet
    assert "guard online else { return .offline }" in sheet
    assert "== .offline { notPicked = Sources.notPickedOffline }" in search
    # (finding 4) let go as the sheet starts going - a swipe let go, Cancel, the page's binding - and nothing from it
    # after: no answer lands, no pick, no download
    # (R7) the Mac's dock holds the page while its Get is open, the tab switched away from and back: there the Get's end
    # lets it go (closeDock, AppNavigation.endSources), never the page's going
    assert ".background(SheetGoing { model.close() })" in sheet and ".onDisappear { if !docked { model.close() } }" in sheet
    assert "model.close()\n                        dismiss()" in sheet
    view = _code((app / "Search" / "GroupView.swift").read_text(encoding="utf-8"))
    assert "if next == nil { getting?.search.close() }" in view
    for function in ("func start(", "private func run(", "private func pick(", "func download()"):
        body = _block(search, search.index("{", search.index(function)))
        assert "!closed" in body, function


def test_search_again_sits_in_the_bar_as_well_as_under_the_cards():
    # (James, 2026-11-15: "search again should be somewhere near the top as well", then "maybe on the right of 'choose
    # a source'") - at the right of the title while folders found are shown, so a long list needn't be scrolled to its
    # end to try other words; still under folders found
    app = CORE.parent.parent.parent / "App"
    sheet = _code((app / "Get" / "SourcesSheet.swift").read_text(encoding="utf-8"))
    toolbar = _block(sheet, sheet.index("{", sheet.index(".toolbar {")))
    assert "if foundFolders {" in toolbar and "ToolbarItem(placement: .topBarTrailing) {" in toolbar
    assert toolbar.index("placement: .cancellationAction") < toolbar.index("againInBar")
    # offered only while folders found are shown: not searching, no error, no store box, something found
    found_folders = _block(sheet, sheet.index("{", sheet.index("private var foundFolders: Bool")))
    for part in ("!search.pending", "search.error == nil", "storeBox(answer) == nil", "!answer.candidates.isEmpty"):
        assert part in found_folders, part
    # the bar's opens the words to change above the chips, outside the list, so no scroll takes them away
    body = _block(sheet, sheet.index("{", sheet.index("var body: some View {")))
    top = body.index("if again == .top && foundFolders {")
    assert top < body.index("queryForm(focus: true)") < body.index("chips") < body.index("ScrollView {")
    # the list's under the cards and under "none match", as before
    found = _block(sheet, sheet.index("{", sheet.index("private func found(")))
    assert found.count("searchAgain") == 2
    assert found.index("Sources.noneMatchLine(") < found.index("searchAgain") < found.index("ForEach(shown)")
    assert found.index("Sources.searchedLine(answer") < found.rindex("searchAgain")
    # one form at a time - a second tap closes it, the other's moves it - closed as a search starts
    assert "@State private var again: AgainPlace?" in sheet
    assert "again = again == place ? nil : place" in sheet
    for function in ("private func begin(", "private func requery("):
        assert "again = nil" in _block(sheet, sheet.index("{", sheet.index(function))), function
    below = _block(sheet, sheet.index("{", sheet.index("@ViewBuilder private var searchAgain: some View {")))
    assert "toggleAgain(.bottom)" in below and "if again == .bottom {" in below
    assert "again == .bottom ? SourcesWords.expanded : SourcesWords.collapsed" in below
    # the bar's: in words up to the default text size, a magnifying glass above it (the words would cut the title
    # short), named Search again either way and saying whether it is open
    bar = _block(sheet, sheet.index("{", sheet.index("private var againInBar: some View {")))
    assert "toggleAgain(.top)" in bar
    assert "if typeSize > .large {" in bar and 'Image(systemName: "magnifyingglass")' in bar
    assert "Text(SourcesWords.searchAgain)" in bar and ".accessibilityLabel(SourcesWords.searchAgain)" in bar
    assert "again == .top ? SourcesWords.expanded : SourcesWords.collapsed" in bar


# ---------------------------------------------------------------------------- Album info (app 0.13)

ALBUM_FILES_HELPER = Path(__file__).resolve().parent.parent / "ios" / "scripts" / "album_files_answers.py"
ALBUM_FILES_ANSWERS = (Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests"
                       / "Fixtures" / "albuminfo" / "files.json")


def _album_files_helper():
    spec = importlib.util.spec_from_file_location("ios_album_files_answers", ALBUM_FILES_HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _album_files_cases() -> dict:
    return {case["name"]: case["answer"] for case in json.loads(ALBUM_FILES_ANSWERS.read_text(encoding="utf-8"))["cases"]}


def test_the_album_files_answers_are_the_ones_the_helper_makes():
    # Fixtures/albuminfo/files.json is what ios/scripts/album_files_answers.py writes now, byte for byte - what the route
    # sends changed (or the file by hand) fails until it is written again
    helper = _album_files_helper()
    assert ALBUM_FILES_ANSWERS.read_text(encoding="utf-8") == helper.text()
    assert ALBUM_FILES_ANSWERS.read_bytes().isascii()


def test_the_album_files_answers_are_the_routes_own(monkeypatch, tmp_path):
    # the same folders asked of the real route, as the phone asks it (a folder relative to the library, the id
    # bridge's `path`): what the Swift tests decode is what /library/tracks sends
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    helper = _album_files_helper()
    made = helper.make(tmp_path)
    cases = _album_files_cases()
    assert [name for name, _ in made] == list(cases)
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    client = TestClient(app)
    for name, folder in made:
        answer = client.get("/deadwax/library/tracks", params={"album": folder})
        assert answer.status_code == 200, answer.text
        assert helper.tidy(answer.json()) == cases[name], name
    # a folder that isn't there is a 404, which the phone says as moved (AlbumInfoWords.filesGone)
    assert client.get("/deadwax/library/tracks", params={"album": "Nobody/Nothing"}).status_code == 404


def test_album_info_reads_what_the_tracks_route_sends():
    assert '{"album": album, "files": await asyncio.to_thread(read_album_details, directory)}' in \
        inspect.getsource(library_route.tracks)
    assert fields("AlbumFiles") == {"files": False}
    # (Phase 8, slice 2) and Edit album's Tags reads the rest of what the route sends: the file, its audio, its pictures
    assert fields("AlbumFile") == {"disc": True, "tags": True, "raw": True, "filename": False, "format": False, "size": False,
                                   "length": False, "bitrate": True, "sample_rate": True, "bits_per_sample": True,
                                   "channels": True, "codec": False, "position": True, "pictures": False}
    assert fields("EmbeddedPicture") == {"index": False, "type": True, "label": False, "mime": False, "size": False,
                                         "description": False}
    for name, answer in _album_files_cases().items():
        assert answer["files"], name
        for file in answer["files"]:
            assert set(fields("AlbumFile")) <= set(file), name
    # read leniently, as every answer is: a file or a field of an unexpected type is left out, never the whole sheet
    for struct in ("AlbumFiles", "AlbumFile", "AlbumExtras", "Day", "Named"):
        assert ".loose" in swift_struct(struct), struct
    # asked by the folder the id bridge names - a present row's `path`, relative to the library as the route takes it
    body = swift_function("DeadwaxClient.swift", "albumFiles")
    assert 'call(Routes.libraryTracks, as: AlbumFiles.self, query: [("album", folder)])' in body
    assert "path" in required_fields("StoreRow")


def album_tag_names(kind: str) -> dict[str, list[str]]:
    """AlbumTag's `named` or `raw` names, case by case, read from AlbumInfo.swift."""
    code = _code((CORE / "AlbumInfo.swift").read_text(encoding="utf-8"))
    enum = _block(code, re.search(r"\benum\s+AlbumTag\b[^{]*\{", code).end() - 1)
    var = _block(enum, re.search(r"\bvar\s+" + kind + r"\s*:\s*\[String\]\s*\{", enum).end() - 1)
    names = {}
    for cases, listed in re.findall(r"\bcase\s+((?:\.\w+\s*,?\s*)+):\s*(?:return\s*)?\[([^\]]*)\]", var, re.S):
        for case in re.findall(r"\.(\w+)", cases):
            names[case] = re.findall(r'"([^"]*)"', listed)
    return names


def test_the_tags_album_info_reads_are_the_servers_names_and_picards():
    from src.library import DETAIL_TAGS

    named = album_tag_names("named")
    raw = album_tag_names("raw")
    cases = swift_raw_values("AlbumInfo.swift", "AlbumTag")
    assert set(named) == set(raw) == cases
    # every name read from `tags` is one the route sends there (DETAIL_TAGS): another would never be found
    for tag, names in named.items():
        assert set(names) <= set(DETAIL_TAGS), tag
    # the status and type aren't sent by name, so are read raw, as each container keeps them
    assert {"releasestatus", "releasetype"}.isdisjoint(DETAIL_TAGS)
    assert named["status"] == named["type"] == []
    # the phone compares a raw name lower-cased
    assert all(name == name.lower() for names in raw.values() for name in names)

    def values(file: dict, tag: str) -> list[str]:
        # AlbumFile.values: the named tag first, else the first raw pair under any of the tag's names
        for key in named[tag]:
            found = [one.strip() for one in (file["tags"].get(key) or "").split(";") if one.strip()]
            if found:
                return found
        for pair in file["raw"]:
            if len(pair) >= 2 and pair[0].lower() in raw[tag]:
                found = [one.strip() for one in pair[1].split(";") if one.strip()]
                if found:
                    return found
        return []

    helper = _album_files_helper()
    group = helper.GROUP
    expected = {
        "flac": {"media": ["CD"], "label": ["Harvest"], "catalogueNumber": ["SHVL 804"], "barcode": ["5099902894225"],
                 "country": ["GB"], "status": ["official"], "type": ["album", "live"], "date": ["2011-09-26"],
                 "originalDate": ["1973-03-01"], "genre": ["Rock"], "releaseGroup": [group]},
        "mp3": {"media": ['12" Vinyl'], "label": ["Go! Beat"], "catalogueNumber": ["828 522-1"],
                "barcode": ["042282852216"], "country": ["GB"], "status": ["Official"], "type": ["album"],
                "releaseGroup": [group]},
        "m4a": {"media": ["Digital Media"], "label": ["Warp"], "catalogueNumber": ["WAP105CD"],
                "barcode": ["801061010524"], "country": ["XW"], "status": ["Promotion"], "type": ["single"]},
        # what deadwax's own filing writes (organizer.write_tags): the media is the WHOLE release, " + "-joined, on every
        # disc's files (AlbumInfo.media takes it once); no barcode, status or label; into an M4A only the country
        "deadwax-flac": {"media": ["CD + CD"], "catalogueNumber": ["XDUSTCD1X"], "country": ["GB"], "date": ["2015"],
                         "originalDate": ["1995"], "releaseGroup": [helper.FILED_GROUP], "barcode": [], "status": [],
                         "label": []},
        "deadwax-m4a": {"country": ["US"], "media": [], "catalogueNumber": [], "barcode": [], "status": []},
    }
    answers = _album_files_cases()
    for name, tags in expected.items():
        first = answers[name]["files"][0]
        for tag, value in tags.items():
            assert values(first, tag) == value, (name, tag)
    # the M4A's are every one raw: Easy MP4 has no names for Picard's freeform atoms
    assert set(answers["m4a"]["files"][0]["tags"]) == {"title", "album"}
    # deadwax's set carries the one whole-release value on both discs' files - never a disc's own medium
    filed = answers["deadwax-flac"]["files"]
    assert {file["disc"] for file in filed} == {1, 2}
    assert {values(file, "media")[0] for file in filed} == {"CD + CD"}
    # the join AlbumInfo splits on is the one both writers of a job's media_format join with
    assert 'static let releaseJoin = " + "\n' in (CORE / "AlbumInfo.swift").read_text(encoding="utf-8")
    assert 'formats.joined(separator: " + ")' in (CORE / "GetRelease.swift").read_text(encoding="utf-8")
    assert ".join(' + ')" in (Path(__file__).resolve().parent.parent / "ui" / "src" / "lib"
                              / "releasePayload.ts").read_text(encoding="utf-8")


def test_the_app_waits_for_an_albums_files_as_long_as_the_route_takes():
    # /library/tracks reads every file of the folder off the disk with no bound of its own (a box set on a disk that
    # has to spin up): the phone gives it longer than the transport's own 8 s, and longer than Album info holds the
    # sheet, so a slow read lands late rather than failing as "That took too long."
    source = inspect.getsource(library_route.tracks)
    assert "asyncio.to_thread(read_album_details" in source
    assert "wait_for" not in source and "timeout" not in source
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    timeouts = {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}
    transport = (Path(__file__).resolve().parent.parent / "ios" / "App" / "URLSessionTransport.swift").read_text(
        encoding="utf-8")
    standard = float(re.search(r"static let standardTimeout: Double = ([\d.]+)\n", transport).group(1))
    album_info = (CORE / "AlbumInfo.swift").read_text(encoding="utf-8")
    settle = float(re.search(r"public static let settleSeconds = ([\d.]+)\n", album_info).group(1))
    assert timeouts["libraryTracks"] > standard
    assert timeouts["libraryTracks"] > settle
    # and only two folders are read at once (a box set's ten folders never all spin a disk together)
    assert re.search(r"public static let foldersAtOnce = 2\n", album_info)


# ---------------------------------------------------------------------------- Last.fm, slice A1: Top Songs

def test_mes_word_for_lastfm_is_one_the_app_knows(monkeypatch):
    # /me's `lastfm` (server 2.1.36): the three words LastfmState reads, and nothing else - anything else is `absent`
    # on the phone, which draws nothing of Last.fm's
    from src.api import lastfm_endpoint

    said = set(re.findall(r'return "(\w+)"', inspect.getsource(lastfm_endpoint.LastfmClient.state)))
    said |= set(re.findall(r'else "(\w+)"', inspect.getsource(lastfm_endpoint.LastfmClient.state)))
    assert said == {"off", "refused", "on"}
    state = _code((CORE / "Lastfm.swift").read_text(encoding="utf-8"))
    for word in said:
        assert f'case "{word}": self = .{word}' in state
    assert fields("Me")["lastfm"] is True


def test_lastfms_answer_is_what_the_app_decodes(monkeypatch):
    # (server 2.1.41, built on main beside slice A1: this FAILS on the ios branch until main is merged into it)
    # GET /deadwax/lastfm/artist, asked with only what it takes, and every answer it builds - no key, refused,
    # whole, a part late - holding what LastfmArtist and LastfmTrack read: only a track's title is needed. Since
    # 2.1.43 the answer also carries `similar` and `top_albums`, which the app reads since slice A2 (LastfmSimilarArtist:
    # only a name needed; LastfmAlbum: a title, plays and what they count)
    from src import lastfm as lastfm_rules
    from src.routes import lastfm as lastfm_route

    route = app_routes()[("GET", "/deadwax/lastfm/artist")]
    params = {field.alias: field for field in route.dependant.query_params}
    assert set(params) == {"mbid", "name"}
    assert declared_query("lastfmArtist") == ["mbid", "name"]
    # the name: 1-200 letters - the app's nameMax - and an id the route's pattern takes (MBID.of: lowercase)
    assert lastfm_route.NAME_MAX == int(re.search(r"public static let nameMax = (\d+)\n",
                                                  (CORE / "LastfmPage.swift").read_text(encoding="utf-8")).group(1))
    assert "mbid: str | None = Query(None, pattern=MBID_PATTERN)" in inspect.getsource(lastfm_route.lastfm_artist)
    assert lastfm_route.MBID_PATTERN == search_musicbrainz.MBID_PATTERN
    assert "name = (name or \"\").strip() or None" in inspect.getsource(lastfm_route.lastfm_artist)
    body = swift_function("DeadwaxClient.swift", "lastfmArtist")
    assert 'if let mbid = ask.mbid { query.append(("mbid", mbid)) }' in body
    assert 'if let name = ask.name { query.append(("name", name)) }' in body
    # what the app reads - each struct read once: the exported answers below hold some 450 entries (A2's similar
    # artists and albums), and a read parses every DeadwaxCore file
    read = {struct: fields(struct) for struct in ("LastfmArtist", "LastfmTrack", "LastfmSimilarArtist", "LastfmAlbum")}
    assert read["LastfmArtist"] == {"enabled": False, "unavailable": False, "why": True, "url": True,
                                      "listeners": True, "top_songs": True, "similar": True, "top_albums": True}
    assert read["LastfmTrack"] == {"title": False, "playcount": True, "listeners": True, "url": True}
    assert read["LastfmSimilarArtist"] == {"name": False, "mbid": True, "match": True, "url": True}
    assert read["LastfmAlbum"] == {"title": False, "mbid": True, "plays": False, "counted": False}
    # what an album's count counts: the route's kinds, each the app's (LastfmAlbum.Counted)
    album = swift_struct("LastfmAlbum")
    assert re.search(r"public enum Counted: String, Sendable, Equatable, Hashable \{\s*case plays, listeners\s*\}", album)
    assert {counted for counted, _ in lastfm_rules.COUNTED} == {"plays", "listeners"}
    # the answers the route builds
    tracks = {"artist_url": "https://www.last.fm/music/Tame+Impala",
              "top_songs": [{"title": "Let It Happen", "playcount": 12, "listeners": 3,
                             "url": "https://www.last.fm/music/Tame+Impala/_/Let+It+Happen"}]}
    info = {"url": "https://www.last.fm/music/Tame+Impala", "listeners": 2345678}
    refusal = lastfm_rules.Refused(10, "Invalid API key", 0.0)
    similar = {"artist": "Tame Impala", "similar": [
        {"name": "Pond", "mbid": "1b4d2f0c-5f2b-4d6e-9a59-1a5bd4f1d6e2", "match": 1.0,
         "url": "https://www.last.fm/music/Pond"},
        {"name": "GUM", "mbid": None, "match": None, "url": None}]}
    albums = {"top_albums": [{"title": "Currents", "mbid": None, "plays": 4123456, "counted": "plays"}]}
    known = lastfm_rules.NotKnown
    answers = [lastfm_rules.no_key_answer(),
               lastfm_rules.artist_answer(lastfm_rules.Answer(info), lastfm_rules.Answer(tracks),
                                          lastfm_rules.Answer(similar), lastfm_rules.Answer(albums), None,
                                          name="Tame Impala"),
               lastfm_rules.artist_answer(lastfm_rules.Answer(info), None, None, None, None),
               lastfm_rules.artist_answer(None, None, None, None, refusal),
               lastfm_rules.artist_answer(known(), known(), known(), known(), None)]
    for answer in answers:
        assert set(answer) == set(read["LastfmArtist"]), answer
        assert_decodes("LastfmArtist", answer, read["LastfmArtist"])
        for song in answer["top_songs"] or []:
            assert set(song) == set(read["LastfmTrack"]), song
            assert_decodes("LastfmTrack", song, read["LastfmTrack"])
        for artist in answer["similar"] or []:
            assert set(artist) == set(read["LastfmSimilarArtist"]), artist
            assert_decodes("LastfmSimilarArtist", artist, read["LastfmSimilarArtist"])
        for album in answer["top_albums"] or []:
            assert set(album) == set(read["LastfmAlbum"]), album
            assert_decodes("LastfmAlbum", album, read["LastfmAlbum"])
    whole = answers[1]
    assert whole["enabled"] and not whole["unavailable"] and whole["listeners"] == 2345678
    assert whole["top_songs"][0]["title"] == "Let It Happen"
    assert [artist["name"] for artist in whole["similar"]] == ["Pond", "GUM"]
    assert whole["top_albums"] == [{"title": "Currents", "mbid": None, "plays": 4123456, "counted": "plays"}]
    # refused with nothing kept: not enabled, and unavailable - the app's `refused` (LastfmPage.state); no key: off
    assert not answers[3]["enabled"] and answers[3]["unavailable"]
    assert not answers[0]["enabled"] and not answers[0]["unavailable"]
    # a part the deadline passed: unavailable, so the app keeps the answer a moment only
    assert answers[2]["unavailable"] and answers[2]["top_songs"] is None
    # the list's length is the app's: TopSongs.most, TopSongs.shown on the page
    top = (CORE / "TopSongs.swift").read_text(encoding="utf-8")
    assert f"public static let most = {lastfm_rules.TOP_SONGS}\n" in top
    # the route answers within its own deadline, inside the transport's 8 s: no timeout of its own
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    assert "lastfmArtist" not in literal.group(1)
    transport = (Path(__file__).resolve().parent.parent / "ios" / "App" / "URLSessionTransport.swift").read_text(
        encoding="utf-8")
    standard = float(re.search(r"static let standardTimeout: Double = ([\d.]+)\n", transport).group(1))
    assert lastfm_route.ARTIST_DEADLINE_S < standard
    # the route's own answers as exported for the app's tests (tests/fixtures/lastfm/answers.py; tests/test_lastfm_routes.py
    # holds the copy to the route): each read whole, each asked as the app asks - an id the route's pattern takes, a
    # name it takes, never an empty part
    exported = json.loads((CORE.parent.parent / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "lastfm" / "answers"
                           / "artist.json").read_text(encoding="utf-8"))
    assert exported["fixtures"] == "recorded" and len(exported["cases"]) >= 9
    for case in exported["cases"]:
        answer = case["answer"]
        assert case["path"] == "/deadwax/lastfm/artist" and case["status"] == 200, case["name"]
        assert set(answer) == set(read["LastfmArtist"]), case["name"]
        assert_decodes("LastfmArtist", answer, read["LastfmArtist"])
        for song in answer["top_songs"] or []:
            assert set(song) == set(read["LastfmTrack"]), song
            assert_decodes("LastfmTrack", song, read["LastfmTrack"])
            assert song["url"] is None or lastfm_rules.lastfm_url(song["url"]) == song["url"]
        for artist in answer["similar"] or []:
            assert set(artist) == set(read["LastfmSimilarArtist"]), artist
            assert_decodes("LastfmSimilarArtist", artist, read["LastfmSimilarArtist"])
        for album in answer["top_albums"] or []:
            assert set(album) == set(read["LastfmAlbum"]), album
            assert_decodes("LastfmAlbum", album, read["LastfmAlbum"])
            assert album["counted"] in {"plays", "listeners"}
        assert set(case["query"]) <= {"mbid", "name"} and case["query"]
        if "mbid" in case["query"]:
            assert re.fullmatch(search_musicbrainz.MBID_PATTERN, case["query"]["mbid"])
        if "name" in case["query"]:
            assert 1 <= len(case["query"]["name"]) <= lastfm_route.NAME_MAX
            assert case["query"]["name"] == case["query"]["name"].strip()
    # the links: the route passes on only an https address on last.fm, as LastfmLink takes it
    assert lastfm_rules.URL_MAX == int(re.search(r"public static let most = (\d+)\n",
                                                 (CORE / "Lastfm.swift").read_text(encoding="utf-8")).group(1))
    taken = {"https://www.last.fm/x", "https://www.last.fm:443/music/X", "https://www.last.fm/music/Sigur+R%C3%B3s"}
    for link in [*taken, "http://www.last.fm/x", "https://notlast.fm/x", "https://a@last.fm/x",
                 "https://evil.example\\.last.fm/x", "https://evil.com%2elast.fm/", "https://%6Cast.fm/x"]:
        assert (lastfm_rules.lastfm_url(link) is None) == (link not in taken), link
    # and LastfmLink reads the host as written, as urlparse does (a percent in it refused)
    assert "URLComponents(string: text)?.percentEncodedHost, !written.contains(\"%\")" in _code(
        (CORE / "Lastfm.swift").read_text(encoding="utf-8"))


def test_the_radios_answer_is_what_the_app_decodes():
    # (Last.fm, slice A3) GET /deadwax/lastfm/radio (server 2.1.44): asked with the song's id, title and artist and the
    # asker's scope - all four, each within the route's limits - and every answer it builds holding what LastfmRadio
    # reads: the songs Song decodes, null when none could be had, [] for a definite nothing
    from src import lastfm as lastfm_rules
    from src.routes import lastfm as lastfm_route
    from src.routes import navidrome as navidrome_route

    route = app_routes()[("GET", "/deadwax/lastfm/radio")]
    params = {field.alias: field for field in route.dependant.query_params}
    assert set(params) == {"song_id", "title", "artist", "scope"} and all(f.required for f in params.values())
    assert declared_query("lastfmRadio") == ["song_id", "title", "artist", "scope"]
    # the app's limits are the route's: an id of ID_MAX, a title and an artist of WORDS_MAX, trimmed as it trims them
    station = (CORE / "Station.swift").read_text(encoding="utf-8")
    assert f"public static let idMost = {navidrome_route.ID_MAX}\n" in station
    assert f"public static let wordsMost = {lastfm_route.WORDS_MAX}\n" in station
    assert "let title = PyText.strip(title)" in station and "let artist = PyText.strip(artist)" in station
    assert "title, artist = whole(title).strip(), whole(artist).strip()" in inspect.getsource(lastfm_route.lastfm_radio)
    # the scope: the route's two words, PagedScope's
    assert 'scope: Literal["yours", "store"] = Query(...)' in inspect.getsource(lastfm_route.lastfm_radio)
    assert re.search(r"public enum PagedScope: String, Sendable \{\s*case yours, store\s*\}",
                     (CORE / "UpNextTypes.swift").read_text(encoding="utf-8"))
    body = re.sub(r"\s+", " ", swift_function("DeadwaxClient.swift", "lastfmRadio"))
    assert ('query: [("song_id", ask.songId), ("title", ask.title), ("artist", ask.artist), '
            '("scope", scope.rawValue)])') in body
    assert "guard let ask = Station.Ask(songId: songId, title: title, artist: artist) else {" in body
    # what the app reads
    read = fields("LastfmRadio")
    assert read == {"enabled": False, "unavailable": False, "why": True, "songs": True}
    song_fields = fields("Song")
    song = {"id": "so-np", "title": "New Person, Same Old Mistakes", "artist": "Tame Impala", "album": "Currents",
            "albumId": "al-Currents", "duration": 240}
    refusal = lastfm_rules.Refused(10, "Invalid API key", 0.0)
    answer = lastfm_rules.Answer
    answers = [lastfm_rules.no_key_radio(),
               lastfm_rules.radio_answer(answer({}), answer({}), [song], None),
               lastfm_rules.radio_answer(answer({}), lastfm_rules.NotKnown(), [], None),
               lastfm_rules.radio_answer(answer({}), None, [], None),
               lastfm_rules.radio_answer(None, None, None, refusal),
               lastfm_rules.radio_answer(answer({}), answer({}), None, None, "too big")]
    for one in answers:
        assert set(one) == set(read), one
        assert_decodes("LastfmRadio", one, read)
    # songs, a definite nothing, none could be had: songs nil is the app's failure, asked again by the top-up's rule
    assert [one["songs"] for one in answers] == [None, [song], [], None, None, None]
    assert not answers[0]["enabled"] and not answers[0]["unavailable"]
    assert not answers[4]["enabled"] and answers[4]["unavailable"]
    # the route answers within its 4 s for Last.fm, a cold scope's list read a page at a time besides: 30 s, past the
    # transport's 8
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    assert "lastfmRadio: 30," in literal.group(1) and lastfm_route.RADIO_DEADLINE_S < 30
    # the route's own answers as exported for the app's tests (tests/fixtures/lastfm/answers.py; tests/test_lastfm_radio.py
    # holds the copy to the route): each read whole, its songs each a Song, each asked as the app asks
    exported = json.loads((CORE.parent.parent / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "lastfm" / "answers"
                           / "radio.json").read_text(encoding="utf-8"))
    assert exported["fixtures"] == "recorded" and len(exported["cases"]) == 10
    for case in exported["cases"]:
        assert set(case["answer"]) == set(read), case["name"]
        assert_decodes("LastfmRadio", case["answer"], read)
        for each in case["answer"]["songs"] or []:
            assert set(each) <= set(song_fields), sorted(set(each) - set(song_fields))
            assert required_fields("Song") <= {name for name, value in each.items() if value is not None}
        query = case["query"]
        assert set(query) == {"song_id", "title", "artist", "scope"}, case["name"]
        assert 1 <= len(query["song_id"]) <= navidrome_route.ID_MAX and query["scope"] in {"yours", "store"}
        for words in (query["title"], query["artist"]):
            assert 1 <= len(words) <= lastfm_route.WORDS_MAX and words == words.strip()


def declared_query(name: str) -> list[str]:
    """The query an Endpoint of Routes.swift is declared with, by its name."""
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    found = re.search(r"public static let " + name + r' = Endpoint\(method: "\w+", path: "[^"]+", query: \[([^\]]*)\]\)',
                      text)
    assert found, name
    return re.findall(r'"(\w+)"', found.group(1))
