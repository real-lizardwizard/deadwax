"""
The player as you (2.0.0-player.52, step 6 of the multi-user plan) - src/api/navidrome_endpoint.py's
client_for and UserClient, src/auth.py's PlayerLogin and player_refused, routes/navidrome.py's access check
before the stream cache, routes/my_library.py's Remove and Add's star at once, and "in your library" meaning
yours: /library/owned's, the id bridge's and the store line's `yours` - through the whole app start() builds
(no lifespan), a real SQLite store, real tagged files, the real stream cache, and a fake Navidrome that checks
Subsonic token auth for james, ethan and the shared account `demo`, keeps each user's stars AND plays apart,
and can keep a song from one user (a Navidrome with per-user libraries).

What these hold (every rule decided with James on 2026-09-27 - one Navidrome library, your library is your
starred albums, two-way with Amperfy):

  - EVERY CALL IS MADE AS YOU: a walk of every player route (the walk must name each one routes/navidrome.py
    has) - each Navidrome call made while answering it is the signed-in user's, but the stream cache's own
    make (the shared account, for every phone). With logins off - and for the break-glass admin - every call
    is the shared account's, and nothing is checked first.
  - The shared account's list is the code's: only SHARED_ACCOUNT_USES name the shared client; the player's
    routes, the bridge, the pins and your library ask through client_for alone.
  - THE CACHED STREAM IS STILL CHECKED PER USER: before a cached MP4, fragmented MP4 or turntable window, one
    getSong as them, kept ACCESS_SECONDS (a yes only) - a song Navidrome won't give them is a 404 even with
    its MP4 made for somebody else; the bytes are the same whoever asks.
  - A login that dies mid-session: the player's call refused (40) ends the session - from memory and the
    database, the kept login dead too - the 401 says why, it is said once, and nothing after it asks
    Navidrome again. The status route says it as a 401, never "not set up".
  - Plays and scrobbles are each user's own; Library (getAlbumList2 starred) is each user's own.
  - Remove from my library: unstarred as you, confirmed, your entries removed by you (not a tombstone, not
    new, not listed as removed by the admin), the store and everyone else's libraries untouched, the
    read-back leaving it removed; refused in words with logins off and for break-glass. Add stars at once.
  - "In your library" means yours with logins on: /library/owned's `yours`, the bridge's `yours` (and each
    other pressing's), the store line's other pressings - left out with logins off, for break-glass, and
    when the ledger can't be read.
"""

import ast
import asyncio
import hashlib
import logging
import re
import sqlite3
import time
import uuid
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from src import auth, player_cache
from src.api import navidrome_endpoint
from src.api.navidrome_endpoint import SHARED_ACCOUNT_USES, navidrome
from src.config import Config
from src.player_cache import Mp4Cache
from src.routes import navidrome as navidrome_routes
from src.routes import store_album as bridge
from src.routes.my_library import REMOVE_UNWRITTEN, REMOVED
from tests.test_library import write_flac
from tests.test_navidrome import FLAC, navidrome_file, streamed
from tests import test_personal_libraries
from tests.test_personal_libraries import (
    DUMMY, LIBRARY, NAVIDROME, STORE_STATE, THIRD, Navidrome, entries, failed, grant, held, ok, release_body,
    run, signed_in, wire, work,
)

#? step 5's fixture - its app, store and Navidrome - which `player` builds on
on = test_personal_libraries.on

ROOT = Path(__file__).resolve().parent.parent
PLAYER = "/deadwax/navidrome"
OWNED = "/deadwax/library/owned"
BRIDGE = "/deadwax/store/album"
SONG = "so-1"


class Player(Navidrome):
    """
    Step 5's Navidrome, with what the player asks besides: ping, getAlbumList2 (starred: the asker's own),
    getArtists, getArtist, getSong, getCoverArt, stream (a real FLAC, by range, as Go's ServeContent) and
    scrobble - each user's plays counted apart, as Navidrome counts them. `hidden` keeps songs from a user, as
    a Navidrome giving users their own libraries would: getSong and stream answer them 70.

    And (2.0.0-player.58) Navidrome's playlists, faithful to its source as read at 0.64.2: getPlaylists (an admin's
    every playlist; anyone else's own and the public ones, by name), getPlaylist (the same, error 70 otherwise),
    createPlaylist (by name - new, owned by the asker as their name is stored - or by `playlistId`: the REPLACE,
    every row deleted and the songs written from position 1; with no songId the songs untouched), updatePlaylist
    (removals by position first, renumbered; then additions after the last row; then the name - '' read as absent -
    the description and `public`), deletePlaylist - each write only by the owner or an admin (50 otherwise), and the
    songs of a smart or a file-synced playlist never (50). Rows are numbered 1..n INCLUDING rows whose song is
    `missing` (listed by nobody, still counted by the stored counter) and orphans (an id with no song - counted by
    nothing); the counter getPlaylists answers is refreshed only by writes. Repeated values are kept and a form
    body is read, merged with the query, as Navidrome's formPost does; every playlist call is kept with who made
    it and whether it came as a form (`playlist_calls`).
    """

    PLAYLIST_CALLS = frozenset({"getPlaylists", "getPlaylist", "createPlaylist", "updatePlaylist", "deletePlaylist"})
    #? (2.0.0-player.64) Navidrome's play queue, one per user, as server/subsonic/bookmarks.go and
    #? persistence/playqueue_repository.go keep it at 0.64.2 - see play_queue_call
    QUEUE_CALLS = frozenset({"getPlayQueue", "getPlayQueueByIndex", "savePlayQueue", "savePlayQueueByIndex"})
    PLAYER_CALLS = frozenset({"ping", "getAlbumList2", "getArtists", "getArtist", "getSong", "getCoverArt",
                              "stream", "scrobble"}) | PLAYLIST_CALLS | QUEUE_CALLS

    def __init__(self):
        super().__init__()
        self.add("nd-dummy", "rel-dummy")
        self.add("nd-third", "rel-third", name="Third")
        self.songs = {SONG: {"id": SONG, "title": "Wandering Star", "albumId": "nd-dummy", "album": "Dummy",
                             "artist": "Portishead", "contentType": "audio/flac", "suffix": "flac", "duration": 290}}
        self.hidden: dict[str, set[str]] = {}
        self.plays: dict[tuple[str, str], int] = {}
        self.playing: dict[str, str] = {}
        self.file, self.serve = navidrome_file(FLAC)
        #? the playlists: id -> its row (owner as stored, public, comment, smart, sync, rows of song ids, the counter)
        self.playlists: dict[str, dict] = {}
        #? (2.0.0-player.61) james is Navidrome's admin, as the shared fake says - so he is deadwax's, and Navidrome
        #? would hand him every playlist (deadwax shows him only his own and shared ones)
        self.admins: set[str] = {"james"}
        self.missing: set[str] = set()
        #? a user's name as Navidrome stores it - what `owner` says
        self.stored_names: dict[str, str] = {}
        self.playlist_calls: list[dict] = []
        #? (2.0.0-player.64) each user's play queue - ids (as stored, comma-joined in Navidrome), current index,
        #? position (ms), changedBy (the `c` of the call that saved) and changed - and every play queue call kept
        self.queues: dict[str, dict] = {}
        self.queue_calls: list[dict] = []
        self.ticks = 0
        #? one playlist owned by each account the walk asks as - ethan, and the shared `demo` (logins off,
        #? break-glass) - and a private one of james's nobody else may see
        for owner in ("ethan", "demo", "james"):
            self.playlist(f"pl-{owner}", f"{owner.title()}'s", owner, [SONG])

    def playlist(self, playlist_id: str, name: str, owner: str, rows: list[str], public: bool = False,
                 smart: bool = False, sync: bool = False, comment: str = "") -> dict:
        """A playlist put in as Navidrome would hold it, its counter refreshed."""
        held = {"id": playlist_id, "name": name, "owner": owner, "public": public, "comment": comment,
                "smart": smart, "sync": sync, "rows": list(rows), "created": self.tick(), "changed": self.tick()}
        self.refresh(held)
        self.playlists[playlist_id] = held
        return held

    def tick(self) -> str:
        self.ticks += 1
        return f"2026-10-20T10:{self.ticks // 60:02d}:{self.ticks % 60:02d}.000Z"

    def refresh(self, held: dict) -> None:
        #? Navidrome's refreshCounters: the rows whose media file it has - missing ones included, orphans not
        held["counter"] = sum(1 for song in held["rows"] if song in self.songs)
        held["seconds"] = sum(self.songs[song].get("duration", 0) for song in held["rows"] if song in self.songs)

    def listed(self, held: dict) -> list[dict]:
        return [self.songs[song] for song in held["rows"] if song in self.songs and song not in self.missing]

    def sees(self, user: str, held: dict) -> bool:
        return user in self.admins or held["owner"].lower() == user or held["public"]

    def shown(self, user: str, held: dict, entries: bool) -> dict:
        songs = self.listed(held)
        body = {"id": held["id"], "name": held["name"], "owner": held["owner"],
                "songCount": len(songs) if entries else held["counter"],
                "duration": sum(song.get("duration", 0) for song in songs) if entries else held["seconds"],
                "created": held["created"], "changed": held["changed"],
                "readonly": held["owner"].lower() != user or held["smart"] or held["sync"]}
        if held["comment"]:
            body["comment"] = held["comment"]
        if held["public"]:
            body["public"] = True
        if held["rows"]:
            body["coverArt"] = f"pl-{held['id']}_5f3a"
        if entries:
            body["entry"] = songs
        return body

    def playlist_call(self, endpoint: str, user: str, values: dict[str, list[str]]) -> httpx.Response:
        one = lambda key: (values.get(key) or [None])[0]
        held = self.playlists.get(one("playlistId") or one("id") or "")
        if endpoint == "getPlaylists":
            found = [self.shown(user, each, False) for each in sorted(self.playlists.values(), key=lambda each: each["name"].lower())
                     if self.sees(user, each)]
            return httpx.Response(200, json=ok(playlists={"playlist": found}) if found else ok())
        if endpoint == "createPlaylist" and not one("playlistId"):
            if not one("name"):
                return httpx.Response(200, json=failed(10, "required parameter name is missing"))
            made = self.playlist(f"pl-new-{len(self.playlists) + 1}", one("name"), self.stored_names.get(user, user), values.get("songId") or [])
            return httpx.Response(200, json=ok(playlist=self.shown(user, made, True)))
        if held is None or not self.sees(user, held):
            return httpx.Response(200, json=failed(70, "playlist not found"))
        if endpoint == "getPlaylist":
            return httpx.Response(200, json=ok(playlist=self.shown(user, held, True)))
        if user not in self.admins and held["owner"].lower() != user:
            return httpx.Response(200, json=failed(50, "user not authorized"))
        fixed = held["smart"] or held["sync"]
        if endpoint == "deletePlaylist":
            del self.playlists[held["id"]]
            return httpx.Response(200, json=ok())
        if endpoint == "createPlaylist":
            if fixed:
                return httpx.Response(200, json=failed(50, "playlist is not editable"))
            #? "only update tracks if they were specified"
            if values.get("songId"):
                held["rows"] = list(values["songId"])
                self.refresh(held)
            held["changed"] = self.tick()
            return httpx.Response(200, json=ok(playlist=self.shown(user, held, True)))
        removals = [int(index) for index in values.get("songIndexToRemove") or []]
        additions = values.get("songIdToAdd") or []
        if (removals or additions) and fixed:
            return httpx.Response(200, json=failed(50, "playlist is not editable"))
        if removals:
            gone = set(removals)
            held["rows"] = [song for place, song in enumerate(held["rows"]) if place not in gone]
        held["rows"].extend(additions)
        if removals or additions:
            self.refresh(held)
        if one("name"):
            held["name"] = one("name")
        if "comment" in values:
            held["comment"] = one("comment") or ""
        if "public" in values:
            held["public"] = one("public") in ("true", "on", "1")
        held["changed"] = self.tick()
        return httpx.Response(200, json=ok())

    def play_queue_call(self, endpoint: str, user: str, values: dict[str, list[str]]) -> httpx.Response:
        """
        Navidrome's play queue as 0.64.2 keeps it (server/subsonic/bookmarks.go, persistence/playqueue_repository.go):
        ONE per user. savePlayQueueByIndex takes `id` repeated and - with any ids - a `currentIndex` inside them, else
        error 10; savePlayQueue finds `current` by the FIRST id equal to it (0 when none is); either with no ids clears
        the queue; `position` an int64, 0 when it isn't one; `changedBy` the request's `c`, `changed` the server's
        time. getPlayQueueByIndex drops songs it no longer has, in order, and answers the STORED index unchanged; an
        empty queue answers only the username, the zero time and an empty changedBy.
        """
        one = lambda key: (values.get(key) or [None])[0]
        if endpoint in ("savePlayQueue", "savePlayQueueByIndex"):
            ids = list(values.get("id") or [])
            try:
                position = int(one("position") or 0)
            except ValueError:
                position = 0
            current = 0
            if endpoint == "savePlayQueueByIndex" and ids:
                try:
                    current = int(one("currentIndex"))
                except (TypeError, ValueError):
                    current = -1
                if current < 0 or current >= len(ids):
                    return httpx.Response(200, json=failed(10, "missing parameter index, err: required 'currentIndex' parameter is missing"))
            elif endpoint == "savePlayQueue":
                current = next((i for i, song in enumerate(ids) if song == one("current")), 0)
            self.queues.pop(user, None)
            if ids:
                self.queues[user] = {"ids": ids, "current": current, "position": position,
                                     "changedBy": one("c") or "", "changed": self.tick()}
            return httpx.Response(200, json=ok())
        held = self.queues.get(user)
        entries = [self.songs[song] for song in (held or {}).get("ids", []) if song in self.songs]
        key = "playQueueByIndex" if endpoint == "getPlayQueueByIndex" else "playQueue"
        if not entries:
            return httpx.Response(200, json=ok(**{key: {"username": user, "changed": "0001-01-01T00:00:00Z", "changedBy": ""}}))
        body = {"entry": entries, "username": user, "changed": held["changed"], "changedBy": held["changedBy"]}
        if held["position"]:
            body["position"] = held["position"]
        if endpoint == "getPlayQueueByIndex":
            body["currentIndex"] = held["current"]
        elif 0 <= held["current"] < len(entries):
            body["current"] = entries[held["current"]]["id"]
        return httpx.Response(200, json=ok(**{key: body}))

    def handle(self, request: httpx.Request) -> httpx.Response:
        endpoint = request.url.path.removeprefix("/rest/")
        if endpoint not in self.PLAYER_CALLS:
            return super().handle(request)
        query = urlparse(str(request.url)).query
        #? every value kept, repeated keys in order - and a form body merged in, as Navidrome's formPost reads one
        values = parse_qs(query, keep_blank_values=True)
        form = request.method == "POST" and request.headers.get("content-type", "").startswith("application/x-www-form-urlencoded")
        if form:
            for key, more in parse_qs(request.content.decode(), keep_blank_values=True).items():
                values.setdefault(key, []).extend(more)
        q = {key: listed[0] for key, listed in values.items()}
        user = q.get("u", "").lower()
        self.calls.append((user, endpoint, q))
        if endpoint in self.PLAYLIST_CALLS:
            self.playlist_calls.append({"user": user, "endpoint": endpoint, "form": form, "query": query, "values": values})
        if endpoint in self.QUEUE_CALLS:
            self.queue_calls.append({"user": user, "endpoint": endpoint, "form": form, "query": query, "values": values})
        if self.down:
            raise httpx.ConnectError("connection refused")
        token = hashlib.md5((self.passwords.get(user, "") + q.get("s", "")).encode()).hexdigest()
        if user not in self.passwords or q.get("t") != token:
            return httpx.Response(200, json=failed(40, "Wrong username or password"))
        if (user, endpoint) in self.errors:
            return self.errors[(user, endpoint)]
        if endpoint in self.PLAYLIST_CALLS:
            return self.playlist_call(endpoint, user, values)
        if endpoint in self.QUEUE_CALLS:
            return self.play_queue_call(endpoint, user, values)
        if q.get("id") in self.hidden.get(user, set()):
            return httpx.Response(200, json=failed(70, "Song not found"))
        stars = self.starred(user)
        mine = lambda album: {**album, **({"starred": "2026-10-15T09:00:00.000Z"} if album["id"] in stars else {})}
        if endpoint == "ping":
            return httpx.Response(200, json=ok())
        if endpoint == "getAlbumList2":
            listed = [mine(album) for album in self.albums.values()
                      if q.get("type") != "starred" or album["id"] in stars]
            return httpx.Response(200, json=ok(albumList2={"album": listed}))
        if endpoint == "getArtists":
            return httpx.Response(200, json=ok(artists={"index": [{"name": "P", "artist": [
                {"id": "ar-1", "name": "Portishead", "albumCount": len(self.albums)}]}]}))
        if endpoint == "getArtist":
            return httpx.Response(200, json=ok(artist={"id": q.get("id"), "name": "Portishead",
                                                       "album": [mine(album) for album in self.albums.values()]}))
        if endpoint == "getSong":
            song = self.songs.get(q.get("id", ""))
            if song is None:
                return httpx.Response(200, json=failed(70, "Song not found"))
            return httpx.Response(200, json=ok(song={**song, "playCount": self.plays.get((user, song["id"]), 0)}))
        if endpoint == "scrobble":
            if q.get("submission") == "true":
                self.plays[(user, q["id"])] = self.plays.get((user, q["id"]), 0) + 1
            else:
                self.playing[user] = q["id"]
            return httpx.Response(200, json=ok())
        if endpoint == "getCoverArt":
            return streamed(200, b"\x89PNG\r\n\x1a\n" + b"\0" * 32, {"content-type": "image/png"})
        return self.serve(request)

    def by(self, endpoint: str | None = None) -> list[tuple[str, str]]:
        """(user, endpoint) of every call since forget(), or of one endpoint's."""
        return [(user, called) for user, called, _ in self.calls if endpoint is None or called == endpoint]

    def forget(self) -> None:
        self.calls.clear()


@pytest.fixture
def player(on, monkeypatch, tmp_path):
    """Step 5's `on`, its Navidrome the player's too - the shared client wired to it - and a stream cache of
    the test's own."""
    fake = Player()
    wire(fake)
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=f"{NAVIDROME}/rest")
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "deadwax-player"))
    navidrome_routes.forget_access()
    navidrome_endpoint.forget_confirmed()
    on.fake = fake
    yield on
    navidrome_routes.forget_access()
    navidrome_endpoint.forget_confirmed()
    run(navidrome.close_client())


class Slow:
    """The fake Navidrome a real network's round trip away - each answer `delay` seconds after it is asked -
    counting how many calls are out at once."""

    def __init__(self, fake, delay: float = 0.05):
        self.fake, self.delay = fake, delay
        self.flying = self.most = 0

    async def __call__(self, request: httpx.Request) -> httpx.Response:
        self.flying += 1
        self.most = max(self.most, self.flying)
        try:
            await asyncio.sleep(self.delay)
            return self.fake.handle(request)
        finally:
            self.flying -= 1


def slow(env, delay: float = 0.05) -> Slow:
    """The shared client's connections (a UserClient's too) through Slow."""
    answering = Slow(env.fake, delay)
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(answering), base_url=f"{NAVIDROME}/rest")
    return answering


def ethans_client(env) -> tuple[navidrome_endpoint.UserClient, str]:
    """ethan signed in, his session read once (/status), and a UserClient asking as its login - with its key."""
    ethan = signed_in(env, "ethan")
    ethan.get(f"{PLAYER}/status")
    key, held_session = next((key, held) for key, held in auth._held.items() if held.user == "ethan")
    login = auth.PlayerLogin(key, "ethan", held_session.credential, env.store)
    return navidrome_endpoint.UserClient(navidrome, login, *auth.unseal_credential(held_session.credential)), key


#? Every player route, and how the walk asks it - a route routes/navidrome.py gains without a line here fails
#? test_the_walk_covers_every_player_route
WALK = {
    "/status": [("get", "/status")],
    "/albums": [("get", "/albums?order=starred"), ("get", "/albums?order=newest")],
    #? (2.0.0-player.59) the Library's whole album list, both ways - yours and the store's
    "/album_index": [("get", "/album_index?scope=yours"), ("get", "/album_index?scope=store")],
    "/albums/{album_id}": [("get", "/albums/nd-dummy")],
    "/search": [("get", "/search?q=dummy")],
    "/artists": [("get", "/artists")],
    "/artists/{artist_id}": [("get", "/artists/ar-1")],
    "/songs/{song_id}": [("get", f"/songs/{SONG}")],
    "/cover/{cover_id}": [("get", "/cover/al-1")],
    "/stream/{song_id}": [("get", f"/stream/{SONG}?format=raw"), ("get", f"/stream/{SONG}?format=raw&wrap=mp4"),
                          ("get", f"/stream/{SONG}?format=raw&wrap=fmp4")],
    "/scrub/{song_id}": [("get", f"/scrub/{SONG}?at=0&seconds=1")],
    "/scrobble/{song_id}": [("post", f"/scrobble/{SONG}?submission=true")],
    #? (2.0.0-player.57) the Library's Shuffle: an order made as you, then its page - `{token}` the order just made
    "/shuffle": [("get", "/shuffle?scope=yours"), ("get", "/shuffle?scope=store")],
    "/shuffle/{token}": [("get", "/shuffle/{token}?offset=0")],
    #? (2.0.0-player.58) the playlists - `{mine}` the asker's own playlist (the fake holds one for each), the edit's
    #? body read fresh just before it posts (FRESH: its `base` the songs as they are), the delete last
    "/playlists": [("get", "/playlists"), ("post", "/playlists", {"name": "Walked", "song_ids": [SONG]})],
    "/playlists/{playlist_id}": [("get", "/playlists/{mine}")],
    "/playlists/{playlist_id}/add": [("post", "/playlists/{mine}/add", {"song_ids": [SONG], "duplicates": "add"})],
    "/playlists/{playlist_id}/edit": [("post", "/playlists/{mine}/edit", "FRESH")],
    "/playlists/{playlist_id}/delete": [("post", "/playlists/{mine}/delete")],
    #? (2.0.0-player.62) Normalization: Info's level of a song, and an album page's "measure this album" (a 202)
    "/level/{song_id}": [("get", f"/level/{SONG}?level=track")],
    "/level/album/{album_id}": [("post", "/level/album/nd-dummy")],
    #? (2.0.0-player.64) resume what was playing: read, a full save, then a position save against its ids (the first
    #? full save of a fresh database is rev 1)
    "/queue": [("get", "/queue"), ("post", "/queue", {"ids": [SONG, SONG], "index": 1, "position": 12.5,
                                                         "device": "walk-device-1", "label": "Mac", "snapshot": None})],
    "/queue/at": [("post", "/queue/at", {"ids_rev": 1, "index": 0, "position": 3.0, "device": "walk-device-1",
                                         "label": "Mac"})],
}

#? whose playlist the walk's `{mine}` is, by who asks
MINE = {"ethan": "pl-ethan", "demo": "pl-demo"}

#? the routes that answer from deadwax's own memory and ask Navidrome nothing: a shuffle's next page
ASKS_NAVIDROME_NOTHING = {"/shuffle/{token}?offset=0"}

#? what the stream cache asks Navidrome as the shared account while answering: its version check, its download
#? and the turntable's ranges - every one a `stream` of the file as it is
CACHE_CALL = ("demo", "stream")

#? (2.0.0-player.62) what the player's Normalization asks as the shared account once the asker's access is confirmed:
#? an album's listing and its songs (src/levels.py - measured once for every phone), beside the cache's own reads
LEVEL_CALLS = {CACHE_CALL, ("demo", "getAlbum"), ("demo", "getSong")}
LEVEL_WAYS = {f"/level/{SONG}?level=track", "POST /level/album/nd-dummy"}


def way_key(method: str, path: str) -> str:
    """What the walk keeps a way's calls under: its path - and its method too for a way that isn't a GET, since
    (2.0.0-player.58) `/playlists` is two ways, GET and POST, which a key by path alone would make one."""
    return path if method == "get" else f"{method.upper()} {path}"


def walk(env, client: TestClient, asker: str = "ethan") -> dict[str, list[tuple[str, str]]]:
    """Every player route asked once each way WALK says: the calls each answer made, by route and way. `asker`
    names whose playlist the playlist ways write to - the account the client asks Navidrome as."""
    made = {}
    token = None
    navidrome_routes.forget_shuffles()
    for route, ways in WALK.items():
        for method, path, *body in ways:
            asked = path.replace("{token}", token or "").replace("{mine}", MINE[asker])
            sent = body[0] if body else None
            if sent == "FRESH":
                now = [song["id"] for song in client.get(f"{PLAYER}/playlists/{MINE[asker]}").json()["songs"]]
                sent = {"base": now, "song_ids": now[::-1], "name": "Walked again"}
            env.fake.forget()
            #? each way asks as if afresh - the access a way before it confirmed isn't carried over
            navidrome_routes.forget_access()
            response = getattr(client, method)(f"{PLAYER}{asked}", **({"json": sent} if sent is not None else {}))
            assert response.status_code in (200, 202, 206), (path, response.status_code, response.text[:200])
            if route == "/shuffle":
                token = response.json()["token"]
            made[way_key(method, path)] = env.fake.by()
    return made


def test_the_walk_covers_every_player_route():
    assert set(WALK) == {route.path for route in navidrome_routes.router.routes}


def test_every_player_route_asks_navidrome_as_the_signed_in_user(player):
    made = walk(player, signed_in(player, "ethan"))

    for path, calls in made.items():
        assert calls or path in ASKS_NAVIDROME_NOTHING, f"{path} asked Navidrome nothing"
        theirs = [call for call in calls if call != CACHE_CALL and not (path in LEVEL_WAYS and call in LEVEL_CALLS)]
        assert (theirs or path in ASKS_NAVIDROME_NOTHING) and all(user == "ethan" for user, _ in theirs), (path, calls)
    #? Normalization's reads as the shared account only after ethan's access is confirmed: his getSong, his getAlbum
    assert made[f"/level/{SONG}?level=track"][0] == ("ethan", "getSong"), made[f"/level/{SONG}?level=track"]
    assert made["POST /level/album/nd-dummy"][0] == ("ethan", "getAlbum"), made["POST /level/album/nd-dummy"]
    #? the stream cache's make alone asks as the shared account - and only after ethan's access is confirmed
    for path in (f"/stream/{SONG}?format=raw&wrap=mp4", f"/stream/{SONG}?format=raw&wrap=fmp4", f"/scrub/{SONG}?at=0&seconds=1"):
        assert made[path][0] == ("ethan", "getSong"), (path, made[path])
    assert made[f"/stream/{SONG}?format=raw&wrap=mp4"][1:] and set(made[f"/stream/{SONG}?format=raw&wrap=mp4"][1:]) == {CACHE_CALL}
    #? the FLAC as it is is relayed as ethan, with no check before it - Navidrome's own answer is the check
    assert made[f"/stream/{SONG}?format=raw"] == [("ethan", "stream")]
    #? his play counted for him alone - never the shared account, never james
    assert player.fake.plays == {("ethan", SONG): 1}
    #? (2.0.0-player.64) his queue is his: Navidrome's as ethan, by index, as forms; deadwax's record under his name
    assert [made["/queue"], made["POST /queue"], made["POST /queue/at"]] == [
        [("ethan", "getPlayQueueByIndex")], [("ethan", "savePlayQueueByIndex")], [("ethan", "savePlayQueueByIndex")]]
    assert all(call["form"] for call in player.fake.queue_calls if call["endpoint"].startswith("save"))
    assert set(player.fake.queues) == {"ethan"} and player.fake.queues["ethan"]["ids"] == [SONG, SONG]
    assert player.store.play_queue("ethan")["rev"] == 2 and player.store.play_queue("demo") is None


def test_with_logins_off_every_call_is_the_shared_accounts_and_nothing_is_checked(player, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    made = walk(player, TestClient(player.app), "demo")

    assert {user for calls in made.values() for user, _ in calls} == {"demo"}
    assert all(endpoint != "getSong" for path, calls in made.items() if "/songs/" not in path for _, endpoint in calls)
    assert player.fake.plays == {("demo", SONG): 1}
    #? (2.0.0-player.64) one queue for everyone: the shared account's in Navidrome, local's in deadwax
    assert set(player.fake.queues) == {"demo"} and player.store.play_queue("local")["rev"] == 2


def test_the_break_glass_admin_plays_as_the_shared_account(player):
    made = walk(player, signed_in(player, auth.BREAK_GLASS_USER), "demo")

    assert {user for calls in made.values() for user, _ in calls} == {"demo"}
    assert ("demo", "getSong") not in made[f"/stream/{SONG}?format=raw&wrap=mp4"]
    #? (2.0.0-player.64) it keeps no queue: the shared account's (which may be a person's) asked nothing, nothing written
    assert [made["/queue"], made["POST /queue"], made["POST /queue/at"]] == [[], [], []]
    assert player.fake.queues == {} and player.store.play_queue(auth.BREAK_GLASS_USER) is None


def names_the_shared_client(source: str) -> bool:
    """Whether Python source reaches the shared `navidrome` itself - imported by name however the import is
    wrapped, or as an attribute of the module however the module was imported (review: a line-by-line match
    missed a wrapped import and `navidrome_endpoint.navidrome`)."""
    tree = ast.parse(source)
    modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and (node.module or "").split(".")[-1] == "navidrome_endpoint":
            if any(alias.name in ("navidrome", "*") for alias in node.names):
                return True
        if isinstance(node, ast.ImportFrom):
            modules.update(alias.asname or alias.name for alias in node.names if alias.name == "navidrome_endpoint")
        if isinstance(node, ast.Import):
            modules.update(alias.asname for alias in node.names
                           if alias.asname and alias.name.split(".")[-1] == "navidrome_endpoint")
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and node.attr == "navidrome":
            owner = node.value
            if isinstance(owner, ast.Name) and owner.id in modules:
                return True
            if isinstance(owner, ast.Attribute) and owner.attr == "navidrome_endpoint":
                return True
    return False


def test_the_shared_client_is_found_however_it_is_reached():
    named = [
        "from src.api.navidrome_endpoint import NavidromeError, navidrome",
        "from src.api.navidrome_endpoint import (\n    NavidromeError,\n    navidrome,\n)",
        "def f():\n    from src.api.navidrome_endpoint import navidrome as n\n    return n",
        "from src.api import navidrome_endpoint\nnavidrome_endpoint.navidrome.call('ping')",
        "from src.api import navidrome_endpoint as ne\nne.navidrome.call('ping')",
        "import src.api.navidrome_endpoint as ne\nne.navidrome",
        "import src.api.navidrome_endpoint\nsrc.api.navidrome_endpoint.navidrome",
        "from .navidrome_endpoint import navidrome",
    ]
    clean = [
        "from src.api.navidrome_endpoint import NavidromeError, client_for",
        "from src.api import navidrome_endpoint\nnavidrome_endpoint.client_for(None)",
        "navidrome = 1\nnavidrome.call",
    ]
    assert [names_the_shared_client(source) for source in named] == [True] * len(named)
    assert [names_the_shared_client(source) for source in clean] == [False] * len(clean)


def test_only_the_shared_account_list_names_the_shared_client():
    """The shared `navidrome` itself is reached only by SHARED_ACCOUNT_USES - and the player's routes, the
    bridge, the pins and your library ask through client_for alone."""
    named = set()
    for path in sorted((ROOT / "src").rglob("*.py")):
        if path.name == "navidrome_endpoint.py":
            continue
        if names_the_shared_client(path.read_text()):
            named.add(str(path.relative_to(ROOT)))
    assert named == set(SHARED_ACCOUNT_USES)
    for path in ("src/routes/navidrome.py", "src/routes/store_album.py", "src/routes/pins.py", "src/routes/my_library.py"):
        text = (ROOT / path).read_text()
        assert not re.search(r"\bnavidrome\.(call|open)\(", text), path
        assert "client_for" in text, path
    #? the library routes' one call as the shared account is the apply's getScanStatus
    calls = re.findall(r"\bnavidrome\.call\(\"(\w+)\"", (ROOT / "src/routes/library.py").read_text())
    assert calls == ["getScanStatus"]


# ----------------------------------------------------------------- the cached stream, checked per user

def test_a_cached_song_is_checked_as_the_user_once_then_kept_five_minutes(player):
    ethan = signed_in(player, "ethan")
    wrapped = f"{PLAYER}/stream/{SONG}?format=raw&wrap=mp4"

    for _ in range(3):
        assert ethan.get(wrapped, headers={"Range": "bytes=0-1"}).status_code == 206
    assert player.fake.by("getSong") == [("ethan", "getSong")]

    #? five minutes on: asked again
    assert navidrome_routes.ACCESS_SECONDS == 300
    for key in navidrome_routes._access:
        navidrome_routes._access[key] = time.monotonic() - navidrome_routes.ACCESS_SECONDS - 1
    assert ethan.get(wrapped, headers={"Range": "bytes=0-1"}).status_code == 206
    assert player.fake.by("getSong") == [("ethan", "getSong")] * 2
    #? and james is asked about for himself
    assert signed_in(player, "james").get(wrapped, headers={"Range": "bytes=0-1"}).status_code == 206
    assert player.fake.by("getSong")[-1] == ("james", "getSong")


def test_a_song_navidrome_wont_give_them_never_comes_out_of_the_cache(player):
    james, ethan = signed_in(player, "james"), signed_in(player, "ethan")
    player.fake.hidden["ethan"] = {SONG}
    whole = james.get(f"{PLAYER}/stream/{SONG}?format=raw&wrap=mp4")
    assert whole.status_code == 200 and whole.headers["content-type"] == "audio/mp4"
    assert james.get(f"{PLAYER}/stream/{SONG}?format=raw&wrap=fmp4").status_code == 200

    for path in (f"/stream/{SONG}?format=raw&wrap=mp4", f"/stream/{SONG}?format=raw&wrap=fmp4",
                 f"/scrub/{SONG}?at=0&seconds=1", f"/stream/{SONG}?format=raw"):
        player.fake.forget()
        answer = ethan.get(f"{PLAYER}{path}")
        assert answer.status_code == 404, (path, answer.status_code)
        assert player.fake.by() and all(user == "ethan" for user, _ in player.fake.by()), path
    #? a refusal is never kept: shown to him again, he is asked afresh and plays
    player.fake.hidden.clear()
    assert ethan.get(f"{PLAYER}/stream/{SONG}?format=raw&wrap=mp4").content == whole.content


def test_the_same_song_is_the_same_bytes_whoever_asks(player, monkeypatch, tmp_path):
    ethan, james = signed_in(player, "ethan"), signed_in(player, "james")
    paths = (f"/stream/{SONG}?format=raw&wrap=mp4", f"/stream/{SONG}?format=raw&wrap=fmp4",
             f"/scrub/{SONG}?at=0.5&seconds=1", f"/stream/{SONG}?format=raw")
    as_ethan = {path: ethan.get(f"{PLAYER}{path}").content for path in paths}
    as_james = {path: james.get(f"{PLAYER}{path}").content for path in paths}
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "another-cache"))
    as_nobody = {path: TestClient(player.app).get(f"{PLAYER}{path}").content for path in paths}

    assert as_ethan == as_james == as_nobody
    assert as_ethan[f"/stream/{SONG}?format=raw"] == FLAC


def test_what_is_kept_of_who_may_have_what_is_bounded(player, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "ACCESS_KEPT", 2)
    player.fake.songs.update({f"so-{n}": {**player.fake.songs[SONG], "id": f"so-{n}"} for n in (2, 3)})
    ethan = signed_in(player, "ethan")
    for song in (SONG, "so-2", "so-3"):
        assert ethan.get(f"{PLAYER}/scrub/{song}?at=0&seconds=1").status_code == 200
    assert list(navidrome_routes._access) == [("ethan", "so-2"), ("ethan", "so-3")]


def test_the_least_recently_asked_song_goes_first(player, monkeypatch):
    """A song asked for again (every seek) moves to the back: the one nobody has asked about since goes
    first, not the one confirmed first."""
    monkeypatch.setattr(navidrome_routes, "ACCESS_KEPT", 2)
    player.fake.songs.update({f"so-{n}": {**player.fake.songs[SONG], "id": f"so-{n}"} for n in (2, 3)})
    ethan = signed_in(player, "ethan")
    for song in (SONG, "so-2", SONG, "so-3"):
        assert ethan.get(f"{PLAYER}/scrub/{song}?at=0&seconds=1").status_code == 200
    assert list(navidrome_routes._access) == [("ethan", SONG), ("ethan", "so-3")]
    assert player.fake.by("getSong") == [("ethan", "getSong")] * 3


# ----------------------------------------------------------------- a login that dies mid-session

def test_a_login_navidrome_refuses_mid_session_ends_it_says_why_and_asks_no_more(player, caplog):
    ethan = signed_in(player, "ethan")
    assert ethan.get(f"{PLAYER}/albums?order=starred").status_code == 200
    player.fake.passwords["ethan"] = "a-new-password"
    caplog.set_level(logging.INFO)

    answer = ethan.get(f"{PLAYER}/albums?order=starred")

    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE
    with sqlite3.connect(player.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM sessions WHERE user = 'ethan'").fetchone()[0] == 0
    assert player.store.credential_row("ethan")["dead_at"]
    asked = len(player.fake.calls)
    for path in ("/albums?order=starred", f"/stream/{SONG}?format=raw&wrap=mp4", f"/stream/{SONG}?format=raw", "/status"):
        again = ethan.get(f"{PLAYER}{path}")
        assert again.status_code == 401 and again.json()["detail"] == auth.LOGIN_GONE, path
    assert ethan.get("/deadwax/me").json()["detail"] == auth.LOGIN_GONE
    assert len(player.fake.calls) == asked, "nothing after the refusal asks Navidrome again"
    assert len([r for r in caplog.records if "signed ethan out" in r.getMessage()]) == 1
    #? a sign-in with the new password brings it all back
    player.fake.passwords["ethan"] = "a-new-password"
    fresh = TestClient(player.app)
    assert fresh.post("/deadwax/auth/login", json={"username": "ethan", "password": "a-new-password"}).status_code == 200
    assert fresh.get(f"{PLAYER}/albums?order=starred").status_code == 200


def test_calls_already_on_their_way_when_the_login_dies_end_it_once(player):
    ethan = signed_in(player, "ethan")
    ethan.get(f"{PLAYER}/status")
    login = next(iter(auth._held.items()))
    stand_in = auth.PlayerLogin(login[0], "ethan", login[1].credential, player.store)
    assert auth.player_refused(stand_in) is True
    assert auth.player_refused(stand_in) is False


def test_a_refused_login_is_a_401_from_the_status_the_bridge_the_turntable_and_the_pins_too(player):
    """Each place that turns a Navidrome failure into "Navidrome didn't say" lets a refused login through."""
    asks = [("get", f"{PLAYER}/status", None), ("get", f"{BRIDGE}?navidrome_id=nd-dummy", None),
            ("get", f"{BRIDGE}?release_mbid={CD}", None),
            ("get", "/deadwax/library/disc_art/navidrome?album=nd-dummy", None),
            ("post", "/deadwax/me/pins/toggle", {"kind": "album", "pinned": True, "navidrome_id": "nd-dummy"})]
    for method, path, body in asks:
        ethan = signed_in(player, "ethan")
        player.fake.passwords["ethan"] = "changed"
        answer = getattr(ethan, method)(path, **({"json": body} if body else {}))
        assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE, (path, answer.text)
        player.fake.passwords["ethan"] = "ethan-navidrome-pw"


def test_a_refused_login_is_a_401_from_home_s_pins_and_forgets_no_id(player):
    """GET /me/pins resolving an album pin (its getAlbum), and the bridge by release checking the Navidrome id
    it keeps: a refused login is the 401, never the pin's stale id nor "Navidrome hasn't got it" - and the id
    kept for everyone isn't forgotten over one person's password."""
    player.fake.add("nd-cd", CD)
    ethan = signed_in(player, "ethan")
    toggled = ethan.post("/deadwax/me/pins/toggle", json={"kind": "album", "pinned": True, "release_mbid": CD})
    assert toggled.status_code == 200, toggled.text
    assert ethan.get(BRIDGE, params={"release_mbid": CD}).json()["navidrome_id"] == "nd-cd"
    assert bridge.known_navidrome_id(CD) == "nd-cd"
    player.fake.passwords["ethan"] = "changed"

    answer = ethan.get("/deadwax/me/pins")
    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE, answer.text

    again = signed_in(player, "james")
    player.fake.passwords["james"] = "changed"
    assert again.get(BRIDGE, params={"release_mbid": CD}).status_code == 401
    assert bridge.known_navidrome_id(CD) == "nd-cd"


def test_the_users_login_goes_on_last_and_an_ended_session_asks_nothing(player):
    ethan = signed_in(player, "ethan")
    ethan.get(f"{PLAYER}/status")
    key, held_session = next(iter(auth._held.items()))
    login = auth.PlayerLogin(key, "ethan", held_session.credential, player.store)
    client = navidrome_endpoint.UserClient(navidrome, login, *auth.unseal_credential(held_session.credential))
    params = client._params({"u": "james", "t": "forged", "s": "forged", "id": "x", "f": "xml"})
    assert (params["u"], params["f"], params["id"]) == ("ethan", "json", "x") and params["t"] != "forged"
    auth._note_ended(key, auth.SIGNED_OUT)
    player.fake.forget()
    with pytest.raises(navidrome_endpoint.SignedOut):
        run(client.call("ping"))
    assert player.fake.by() == []


def test_a_refusal_of_a_login_since_resealed_fails_the_call_and_never_signs_out(player):
    """(2.0.2) A player call made with the login read before its person changed their own password from deadwax, and
    refused after it (error 40): the session has been re-sealed with the new password (auth.own_password_changed), so
    the call fails as itself - never a SignedOut, whose 401 would bring the sign-in screen up - and the session stands;
    and while the change is under way (auth.changing_password) the same."""
    client, key = ethans_client(player)
    player.fake.passwords["ethan"] = "changed-from-deadwax"
    with auth.changing_password(key, "ethan"):
        with pytest.raises(navidrome_endpoint.NavidromeError) as during:
            run(client.call("ping"))
    assert not isinstance(during.value, navidrome_endpoint.SignedOut) and during.value.code == 40
    assert auth.session_ended(key) is None
    resealed = auth.seal_credential("ethan", auth.subsonic_token("changed-from-deadwax", "salt"), "salt")
    with auth._lock:
        auth._held[key].credential = resealed
    with pytest.raises(navidrome_endpoint.NavidromeError) as after:
        run(client.call("ping"))
    assert not isinstance(after.value, navidrome_endpoint.SignedOut)
    assert auth.session_ended(key) is None and player.store.session(key) is not None
    #? an old login with nothing newer behind it is still the sign-out it always was
    with auth._lock:
        auth._held[key].credential = client.login.sealed
    with pytest.raises(navidrome_endpoint.SignedOut):
        run(client.call("ping"))
    assert auth.session_ended(key) == auth.LOGIN_GONE


def _twenty_pins(env, user: str = "ethan") -> None:
    pins = [{"kind": "album", "ref": f"release:{uuid.uuid4()}", "label": f"Album {n}", "sub": "X",
             "navidrome_id": f"nd-{n}", "cover": None} for n in range(20)]
    assert run(env.store.write_pins(user, pins))


def test_a_burst_with_the_old_login_while_the_change_runs_is_one_refused_login(player):
    """(2.0.2 review) ethan changes his password from this session, Navidrome has taken it, and Home's pins are resolved
    with the OLD login before the re-seal: the session stands - but the refusal never confirms the dead login, so one
    call asks and the other nineteen fail without asking (twenty failed logins would trip Navidrome's 5-in-20-s block
    on the name, and the change's proof with the new password would be refused)."""
    ethan = signed_in(player, "ethan")
    _twenty_pins(player)
    slow(player)
    player.fake.passwords["ethan"] = "changed-from-deadwax"
    player.fake.forget()
    with auth.changing_password(auth.id_hash(ethan.cookies[auth.COOKIE]), "ethan"):
        answer = ethan.get("/deadwax/me/pins")
    assert answer.status_code != 401
    assert len([call for call in player.fake.by() if call[0] == "ethan"]) == 1
    assert ethan.get("/deadwax/me").json()["user"] == "ethan"


def test_concurrent_calls_with_a_superseded_login_ask_navidrome_once(player):
    client, key = ethans_client(player)
    navidrome_endpoint.forget_confirmed()                  # the last answer a while ago: the first call goes alone
    player.fake.passwords["ethan"] = "changed-from-deadwax"
    player.fake.forget()

    async def eight():
        with auth.changing_password(key, "ethan"):
            return await asyncio.gather(*(client.call("ping") for _ in range(8)), return_exceptions=True)

    results = run(eight())
    assert len(player.fake.by()) == 1
    assert all(isinstance(r, navidrome_endpoint.NavidromeError) and not isinstance(r, navidrome_endpoint.SignedOut)
               and r.code == 40 for r in results)
    assert auth.session_ended(key) is None
    #? a refused login is never confirmed by its refusal
    assert key not in navidrome_endpoint._confirmed


def test_another_device_while_a_change_runs_ends_at_its_first_refusal_told_why(player):
    """(2.0.2 review) The guard is the changing SESSION's, never the person's: ethan's desktop, on Home while his phone
    changes the password, is refused once and signed out - its burst is one failed login, as in 2.0.0 - and (review 2)
    told it is the change's doing, as the devices own_password_changed ends are. The change never took here, so once
    it is over the reason noted is LOGIN_GONE again: that login died of something else."""
    phone, desktop = signed_in(player, "ethan"), signed_in(player, "ethan")
    _twenty_pins(player)
    slow(player)
    player.fake.passwords["ethan"] = "changed-from-deadwax"
    player.fake.forget()
    desktop_key = auth.id_hash(desktop.cookies[auth.COOKIE])
    with auth.changing_password(auth.id_hash(phone.cookies[auth.COOKIE]), "ethan"):
        answer = desktop.get("/deadwax/me/pins")
        assert desktop.get("/deadwax/me").json()["detail"] == auth.PASSWORD_CHANGED
    assert answer.status_code == 401 and answer.json()["detail"] == auth.PASSWORD_CHANGED
    assert len([call for call in player.fake.by() if call[0] == "ethan"]) == 1
    assert auth.superseded(player.store, "ethan", desktop_key, "x") is False
    assert auth.session_ended(desktop_key) == auth.LOGIN_GONE


def test_a_login_that_wont_open_asks_navidrome_nothing_and_ends_the_session(player, monkeypatch):
    """Met while the session is still held in memory: the player's first call ends it, so /me says so too
    (review: /me answering 200 while every player call was a 401 had the sign-in screen come and go)."""
    ethan = signed_in(player, "ethan")
    assert ethan.get("/deadwax/me").status_code == 200
    monkeypatch.setattr(auth, "unseal_credential", lambda sealed: None)
    player.fake.forget()
    answer = ethan.get(f"{PLAYER}/albums?order=starred")
    assert answer.status_code == 401 and answer.json()["detail"] == auth.KEY_CHANGED
    assert player.fake.by() == []
    assert ethan.get("/deadwax/me").json()["detail"] == auth.KEY_CHANGED
    with sqlite3.connect(player.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM sessions WHERE user = 'ethan'").fetchone()[0] == 0


@pytest.mark.parametrize("first", ["/deadwax/me", f"{PLAYER}/status", f"{PLAYER}/stream/{SONG}?format=raw"])
def test_a_new_secret_key_ends_each_session_at_its_first_request_after_the_restart(player, monkeypatch, first):
    """DEADWAX_SECRET_KEY changed and deadwax restarted: the first request a session makes - /me or the player's
    - ends it, KEY_CHANGED, as the re-check would minutes later; /me and the player agree from then on, and
    Navidrome is asked nothing with a login that won't open."""
    ethan = signed_in(player, "ethan")
    james = signed_in(player, "james")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "another-key-entirely-0123456789abcdef")
    auth.forget_sessions()   # what the restart forgets
    player.fake.forget()

    answer = ethan.get(first)

    assert answer.status_code == 401 and answer.json()["detail"] == auth.KEY_CHANGED, answer.text
    for path in ("/deadwax/me", f"{PLAYER}/status", f"{PLAYER}/albums?order=starred"):
        again = ethan.get(path)
        assert again.status_code == 401 and again.json()["detail"] == auth.KEY_CHANGED, path
    assert [call for call in player.fake.by() if call[0] == "ethan"] == []
    with sqlite3.connect(player.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM sessions WHERE user = 'ethan'").fetchone()[0] == 0
    assert player.store.credential_row("ethan")["dead_why"] == auth.KEY_CHANGED
    #? one request ends one session: james's waits for his own
    with sqlite3.connect(player.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM sessions WHERE user = 'james'").fetchone()[0] == 1
    assert james.get("/deadwax/me").json()["detail"] == auth.KEY_CHANGED


@pytest.mark.parametrize("first", ["/cover/al-1", f"/stream/{SONG}?format=raw"])
def test_a_cover_or_a_song_refused_first_ends_the_session_too(player, first):
    """A binary call (UserClient.open) refused is the same 401 as a JSON one: after a password change the
    first request is as likely a cover in the grid or the next song as anything."""
    ethan = signed_in(player, "ethan")
    player.fake.passwords["ethan"] = "changed"

    answer = ethan.get(f"{PLAYER}{first}")

    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE, answer.text
    with sqlite3.connect(player.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM sessions WHERE user = 'ethan'").fetchone()[0] == 0
    assert player.store.credential_row("ethan")["dead_at"]
    asked = len(player.fake.calls)
    assert ethan.get(f"{PLAYER}/cover/al-2").status_code == 401
    assert len(player.fake.calls) == asked


def test_an_ended_session_opens_nothing(player):
    client, key = ethans_client(player)
    auth._note_ended(key, auth.SIGNED_OUT)
    player.fake.forget()
    with pytest.raises(navidrome_endpoint.SignedOut):
        run(client.open("getCoverArt", {"id": "al-1"}))
    assert player.fake.by() == []


# ----------------------------------------------------------------- calls on their way when a login dies

def test_a_burst_after_a_password_change_is_one_refused_login(player):
    """Home's pins, resolved together (one getAlbum each), the first request after ethan changed his password:
    one call goes first, it is refused, and the other nineteen are a 401 without asking - Navidrome blocks a
    user for 20 s after 5 failed logins, the new password included."""
    ethan = signed_in(player, "ethan")
    pins = [{"kind": "album", "ref": f"release:{uuid.uuid4()}", "label": f"Album {n}", "sub": "X",
             "navidrome_id": f"nd-{n}", "cover": None} for n in range(20)]
    assert run(player.store.write_pins("ethan", pins))
    slow(player)
    player.fake.passwords["ethan"] = "changed"
    player.fake.forget()

    answer = ethan.get("/deadwax/me/pins")

    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE
    assert len([call for call in player.fake.by() if call[0] == "ethan"]) == 1


def test_calls_as_a_login_navidrome_has_just_taken_go_together(player):
    client, key = ethans_client(player)
    answering = slow(player)
    navidrome_endpoint._confirmed[key] = time.monotonic()

    async def ten():
        return await asyncio.gather(*(client.call("ping") for _ in range(10)))

    run(ten())
    assert answering.most == 10


def test_after_a_pause_one_call_goes_first_and_the_rest_together(player):
    client, key = ethans_client(player)
    answering = slow(player)
    navidrome_endpoint.forget_confirmed()

    async def ten():
        return await asyncio.gather(*(client.call("ping") for _ in range(10)))

    run(ten())
    assert answering.most == 9
    #? ...and refused, it is the only one that asked - five seconds on (the gate kept: a lock is made afresh for
    #? another event loop, here the next run's, as the tests' loops come and go)
    navidrome_endpoint._confirmed[key] = time.monotonic() - navidrome_endpoint.CONFIRMED_SECONDS - 1
    player.fake.passwords["ethan"] = "changed"
    player.fake.forget()

    async def refused():
        return await asyncio.gather(*(client.call("ping") for _ in range(10)), return_exceptions=True)

    said = run(refused())
    assert all(isinstance(answer, navidrome_endpoint.SignedOut) for answer in said)
    assert len(player.fake.by()) == 1


def test_navidrome_not_there_holds_up_nothing_waiting_on_the_first_call(player):
    """Down is no failed login: the calls waiting on the first don't then go one by one to find that out."""
    client, key = ethans_client(player)
    answering = slow(player)
    navidrome_endpoint.forget_confirmed()
    player.fake.down = True

    async def five():
        return await asyncio.gather(*(client.call("ping") for _ in range(5)), return_exceptions=True)

    said = run(five())
    assert all(isinstance(answer, navidrome_endpoint.NavidromeError) and answer.unreachable for answer in said)
    assert answering.most == 4
    assert auth.session_ended(key) is None


def test_a_request_with_no_login_to_ask_as_is_refused_never_the_shared_account(player):
    request = type("Request", (), {"state": type("State", (), {})()})()
    client = navidrome_endpoint.client_for(request)
    assert client is not navidrome
    with pytest.raises(navidrome_endpoint.SignedOut):
        run(client.call("ping"))


# ----------------------------------------------------------------- each user's own

def test_library_is_each_users_starred_albums(player):
    player.fake.starred("ethan").add("nd-third")
    player.fake.starred("james").update({"nd-dummy", "nd-third"})

    def library(user):
        return [album["id"] for album in signed_in(player, user).get(f"{PLAYER}/albums?order=starred").json()["albums"]]

    assert library("ethan") == ["nd-third"]
    assert sorted(library("james")) == ["nd-dummy", "nd-third"]
    #? the store - Browse - is everyone's
    assert len(signed_in(player, "ethan").get(f"{PLAYER}/albums?order=newest").json()["albums"]) == 2


def test_plays_and_now_playing_are_each_users_own(player):
    ethan, james = signed_in(player, "ethan"), signed_in(player, "james")
    ethan.post(f"{PLAYER}/scrobble/{SONG}")
    ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=true")
    james.post(f"{PLAYER}/scrobble/{SONG}?submission=true")
    ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=true")

    assert player.fake.plays == {("ethan", SONG): 2, ("james", SONG): 1}
    assert player.fake.playing == {"ethan": SONG}
    assert ethan.get(f"{PLAYER}/songs/{SONG}").json()["playCount"] == 2
    assert james.get(f"{PLAYER}/songs/{SONG}").json()["playCount"] == 1


# ----------------------------------------------------------------- Remove from my library, and Add at once

def test_remove_unstars_it_as_you_and_takes_it_out_of_your_library_alone(player):
    album = held(player)
    ethan, _ = signed_in(player, "ethan"), signed_in(player, "james")
    grant(player, ["ethan"], album)
    work(player)
    assert player.fake.starred("ethan") == {"nd-dummy"} and "nd-dummy" in player.fake.starred("james")
    player.fake.forget()

    answer = ethan.post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})

    assert answer.status_code == 200 and answer.json() == {"removed": True, "entries": 1, "words": REMOVED}
    assert set(player.fake.by()) == {("ethan", "getAlbum"), ("ethan", "unstar")}
    assert player.fake.starred("ethan") == set() and "nd-dummy" in player.fake.starred("james")
    entry = entries(player, "ethan")[album]
    #? removed BY HIM - not a tombstone, nothing new, never "removed by the admin"
    assert (entry["state"], entry["removed_why"]) == ("removed", "unstarred")
    assert entries(player, "james")[album]["state"] == "starred"
    assert ethan.get(LIBRARY).json()["removed"] == []
    #? nothing in the store went
    assert (player.tmp / "library" / DUMMY).is_dir()
    #? not yours any more, wherever deadwax says whose it is
    assert {a["path"]: a.get("yours") for a in ethan.get(OWNED).json()["albums"]} == {DUMMY: False}
    assert ethan.get(BRIDGE, params={"navidrome_id": "nd-dummy"}).json()["yours"] is False
    #? the read-back leaves it removed - and Add brings it back, starred at once
    work(player)
    assert entries(player, "ethan")[album]["state"] == "removed"
    assert ethan.post(f"{LIBRARY}/add", json=release_body()).json()["starred"] is True
    assert entries(player, "ethan")[album]["state"] == "starred" and player.fake.starred("ethan") == {"nd-dummy"}
    assert {a["path"]: a.get("yours") for a in ethan.get(OWNED).json()["albums"]} == {DUMMY: True}
    assert ethan.get(BRIDGE, params={"navidrome_id": "nd-dummy"}).json()["yours"] is True


def test_remove_takes_out_an_album_still_waiting_to_be_starred_too(player):
    album = held(player)
    grant(player, ["ethan"], album)
    ethan = signed_in(player, "ethan")
    assert entries(player, "ethan")[album]["state"] == "waiting"

    assert ethan.post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"}).json()["entries"] == 1
    assert entries(player, "ethan")[album]["state"] == "removed"
    work(player)
    assert player.fake.starred("ethan") == set(), "the worker never stars it after the Remove"


def test_remove_of_an_album_starred_elsewhere_with_no_release_unstars_it(player):
    player.fake.add("nd-untagged", "", name="Untagged")
    player.fake.starred("ethan").add("nd-untagged")
    answer = signed_in(player, "ethan").post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-untagged"})
    assert answer.json()["entries"] == 0 and player.fake.starred("ethan") == set()


def test_remove_says_so_when_navidrome_keeps_the_star_and_leaves_the_library_as_it_was(player):
    album = held(player)
    signed_in(player, "ethan")
    grant(player, ["ethan"], album)
    work(player)
    assert entries(player, "ethan")[album]["state"] == "starred"
    original = player.fake.handle

    def keeps(request):
        if request.url.path.endswith("/unstar"):
            return httpx.Response(200, json=ok())
        return original(request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(keeps), base_url=f"{NAVIDROME}/rest")
    answer = signed_in(player, "ethan").post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})
    assert answer.status_code == 502 and "kept the star" in answer.json()["detail"]
    #? unstarred first, the ledger after: a Remove Navidrome refused takes nothing out of it
    assert entries(player, "ethan")[album]["state"] == "starred"


def test_remove_takes_out_what_was_starred_as_that_album_even_once_its_release_is_gone(player):
    """An album whose tags lost their release id since deadwax starred it: the entry starred as that Navidrome
    album goes too."""
    album = held(player)
    signed_in(player, "ethan")
    grant(player, ["ethan"], album)
    work(player)
    player.fake.albums["nd-dummy"]["musicBrainzId"] = ""
    answer = signed_in(player, "ethan").post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})
    assert answer.json()["entries"] == 1 and entries(player, "ethan")[album]["state"] == "removed"


@pytest.mark.parametrize("state", ["waiting", "starred"])
def test_remove_says_so_when_deadwax_cant_write_it_and_the_album_isnt_starred_again(player, state):
    """A ledger write that fails (a full /config) is a 503 in words - never "Removed" over an entry still
    waiting, which the worker would star again. Remove again, once writes work, removes it."""
    album = held(player)
    ethan = signed_in(player, "ethan")
    grant(player, ["ethan"], album)
    if state == "starred":
        work(player)
    assert entries(player, "ethan")[album]["state"] == state
    with sqlite3.connect(player.path) as connection:
        connection.execute("CREATE TRIGGER full BEFORE UPDATE ON library_membership "
                           "BEGIN SELECT RAISE(ABORT, 'database or disk is full'); END")

    answer = ethan.post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})

    assert answer.status_code == 503 and answer.json()["detail"] == REMOVE_UNWRITTEN
    assert entries(player, "ethan")[album]["state"] == state
    with sqlite3.connect(player.path) as connection:
        connection.execute("DROP TRIGGER full")
    again = ethan.post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})
    assert again.status_code == 200 and again.json()["entries"] == 1
    work(player)
    assert entries(player, "ethan")[album]["state"] == "removed" and player.fake.starred("ethan") == set()


def test_remove_says_so_when_deadwax_cant_read_what_was_starred_as_it(player, monkeypatch):
    album = held(player)
    ethan = signed_in(player, "ethan")
    grant(player, ["ethan"], album)
    monkeypatch.setattr(player.store, "ledger_by_navidrome", _unread)
    answer = ethan.post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})
    assert answer.status_code == 503 and answer.json()["detail"] == REMOVE_UNWRITTEN


def test_remove_is_refused_in_words_with_logins_off_and_for_break_glass(player, monkeypatch):
    glass = signed_in(player, auth.BREAK_GLASS_USER)
    answer = glass.post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"})
    assert answer.status_code == 409 and "no Navidrome account" in answer.json()["detail"]
    assert signed_in(player, "ethan").post(f"{LIBRARY}/remove", json={"navidrome_id": "x" * 300}).status_code == 422
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    assert TestClient(player.app).post(f"{LIBRARY}/remove", json={"navidrome_id": "nd-dummy"}).status_code == 409
    assert player.fake.by("unstar") == []


def test_add_stars_it_at_once_as_you(player):
    album = held(player)
    ethan = signed_in(player, "ethan")
    player.fake.forget()

    answer = ethan.post(f"{LIBRARY}/add", json=release_body()).json()

    assert answer["added"] is True and answer["starred"] is True
    assert entries(player, "ethan")[album]["state"] == "starred"
    assert player.fake.starred("ethan") == {"nd-dummy"}
    assert {user for user, _ in player.fake.by()} == {"ethan"}
    assert [album["id"] for album in ethan.get(f"{PLAYER}/albums?order=starred").json()["albums"]] == ["nd-dummy"]


# ----------------------------------------------------------------- "in your library" means yours

def test_owned_says_which_albums_are_yours_with_logins_on_only(player, monkeypatch):
    dummy, _ = held(player), held(player, THIRD, "rel-third")
    #? james is seeded with the whole store at his first sign-in
    james = signed_in(player, "james")
    grant(player, ["ethan"], dummy)

    def yours(client):
        return {album["path"]: album.get("yours", "unsaid") for album in client.get(OWNED).json()["albums"]}

    assert yours(signed_in(player, "ethan")) == {DUMMY: True, THIRD: False}
    assert yours(james) == {DUMMY: True, THIRD: True}
    assert yours(signed_in(player, auth.BREAK_GLASS_USER)) == {DUMMY: "unsaid", THIRD: "unsaid"}
    monkeypatch.setattr(player.store, "ledger_held_paths", _unread)
    assert yours(signed_in(player, "ethan")) == {DUMMY: "unsaid", THIRD: "unsaid"}
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    assert yours(TestClient(player.app)) == {DUMMY: "unsaid", THIRD: "unsaid"}


async def _unread(*args):
    return None


#? the bridge takes release ids as MusicBrainz writes them
CD = "11111111-1111-4111-8111-111111111111"
REMASTER = "22222222-2222-4222-8222-222222222222"
GROUP = "33333333-3333-4333-8333-333333333333"


def test_the_bridge_and_the_store_line_say_whose_each_pressing_is(player, monkeypatch):
    for folder, release in ((DUMMY, CD), ("Portishead/Dummy (2014 Remaster)", REMASTER)):
        for n in (1, 2):
            write_flac(player.tmp / "library" / folder / f"0{n}.flac", album="Dummy", albumartist="Portishead",
                       artist="Portishead", title=f"Track {n}", tracknumber=str(n), date="1994",
                       musicbrainz_albumid=release, musicbrainz_releasegroupid=GROUP)
    from src.store_index import index_folder
    dummy = run(index_folder(player.store, player.root, player.tmp / "library" / DUMMY))
    run(index_folder(player.store, player.root, player.tmp / "library" / "Portishead/Dummy (2014 Remaster)"))
    ethan = signed_in(player, "ethan")

    answer = ethan.get(BRIDGE, params={"release_mbid": CD}).json()
    assert answer["yours"] is False and [p["yours"] for p in answer["other_pressings"]] == [False]
    #? the store line too: asked from the CD, the remaster is the store's
    state = ethan.post(STORE_STATE, json={**release_body(CD), "release_group_mbid": GROUP}).json()
    assert [p["yours"] for p in state["other_pressings"]] == [False]
    grant(player, ["ethan"], dummy)
    answer = ethan.get(BRIDGE, params={"release_mbid": CD}).json()
    assert answer["yours"] is True
    remaster = ethan.get(BRIDGE, params={"release_mbid": REMASTER}).json()
    assert remaster["yours"] is False and [p["yours"] for p in remaster["other_pressings"]] == [True]
    state = ethan.post(STORE_STATE, json={**release_body(REMASTER), "release_group_mbid": GROUP}).json()
    assert [p["yours"] for p in state["other_pressings"]] == [True]
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    off = TestClient(player.app)
    assert "yours" not in off.get(BRIDGE, params={"release_mbid": CD}).json()
    state = off.post(STORE_STATE, json={**release_body(REMASTER), "release_group_mbid": GROUP}).json()
    assert ["yours" in p for p in state["other_pressings"]] == [False]


def test_a_release_held_in_two_folders_is_yours_when_you_hold_either(player):
    """A set kept one folder per disc - two present folders of one release - one of them in ethan's library."""
    folders = ("Portishead/Dummy (1994)/Disc 1", "Portishead/Dummy (1994)/Disc 2")
    for folder in folders:
        write_flac(player.tmp / "library" / folder / "01.flac", album="Dummy", albumartist="Portishead",
                   artist="Portishead", title="Track", tracknumber="1", date="1994", musicbrainz_albumid=CD)
    from src.store_index import index_folder
    first = run(index_folder(player.store, player.root, player.tmp / "library" / folders[0]))
    run(index_folder(player.store, player.root, player.tmp / "library" / folders[1]))
    ethan = signed_in(player, "ethan")
    assert ethan.get(BRIDGE, params={"release_mbid": CD}).json()["yours"] is False
    grant(player, ["ethan"], first)
    answer = ethan.get(BRIDGE, params={"release_mbid": CD}).json()
    assert len(answer["present"]) == 2 and answer["yours"] is True


def test_a_newer_sign_in_on_another_device_keeps_the_old_session_asking_as_its_own_login(player):
    """Each session asks as the login it was signed in with: a phone signed in yesterday and a laptop today
    are each their own, and the laptop's sign-in doesn't put the phone's calls on another token."""
    phone = signed_in(player, "ethan")
    laptop = signed_in(player, "ethan")
    player.fake.forget()
    phone.get(f"{PLAYER}/status")
    laptop.get(f"{PLAYER}/status")
    tokens = [(q["t"], q["s"]) for _, called, q in player.fake.calls if called == "ping"]
    assert len(tokens) == 2 and tokens[0] != tokens[1]


def test_nothing_runs_on_the_event_loop_while_ending_a_refused_session(player, monkeypatch):
    """The refusal's database writes go to the thread pool, as every write of the sign-in does."""
    ran_in = []
    real = auth.player_refused

    def watched(login):
        try:
            asyncio.get_running_loop()
            ran_in.append("loop")
        except RuntimeError:
            ran_in.append("thread")
        return real(login)

    monkeypatch.setattr(auth, "player_refused", watched)
    ethan = signed_in(player, "ethan")
    player.fake.passwords["ethan"] = "changed"
    assert ethan.get(f"{PLAYER}/albums").status_code == 401
    assert ran_in == ["thread"]
