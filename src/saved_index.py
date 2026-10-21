"""
Search what's saved (2.0.0-player.56) - an index of everything MusicBrainz's saved answers mention, so the app's
Search finds what you have come across before under ANY words, at once, even with MusicBrainz away.

James (2026-10-15), of the answers 2.0.0-player.54 keeps on disk: "and the cache includes songs and albums as well,
correct? so i can search it all?" They held every answer, but keyed on the exact request - so new WORDS asked
MusicBrainz again: search "portishead", open Dummy, then type "glory box", and MusicBrainz was asked though Glory
Box is in Dummy's saved tracklist. Asked, he chose a searchable index of everything saved (not a mirror of
MusicBrainz): Search draws what it finds first, and MusicBrainz's own answer fills in after.

WHAT IS IN IT - read from each answer as the disk layer stores it (src/musicbrainz_cache.SavedAnswers._put), into
tables of the saved answers' own file, beside the answers:
  - ARTISTS: id, name, sort name, aliases, disambiguation, type, country, years - from artist searches, artist
    pages, and every credit any answer carries (a credit gives the name, sort name and disambiguation);
  - ALBUMS (release groups): id, title, primary and secondary types, first release date, the credit as the app
    renders it (artists.credit_name) and the artist ids - from album searches, discographies, album pages (each
    pressing carries its group) and song searches (each release a recording is on carries its group);
  - SONGS (recordings): id, title, length, credit - with the PRESSINGS (releases) each is on and its track there,
    which is what a song's album rows need: from song searches, and above all from album pages' tracklists, so a
    song seen only on a saved album page is found by its title. Pressings are not rows Search lists.
One row per thing however many answers mention it; the newest answer's fields win (a field it doesn't carry keeps
what an older one said). MENTIONS say which answer mentions what: a thing stays while a stored answer mentions it,
and goes with the last one (the size bound's trim, Clear, a refresh replacing an answer).

SEARCHED with SQLite's FTS5, `unicode61 remove_diacritics 2` (Björk = bjork, Sigur Rós = sigur ros): every word
typed must match - in a name or a title, or in a credit - the last one as a prefix ("portis" finds Portishead, as
you type), ranked by bm25 with names and titles weighing over credits (and an artist's own name over the other
names they go by). Answered in MusicBrainz's own shapes (`search`), so the app draws a saved row with the very
component it draws MusicBrainz's with.

Pure but for the connection it is handed: no file, no thread, no network - SavedAnswers runs it on its worker.
"""

import json
import re
import sqlite3
import unicodedata
import uuid

from src.artists import _fold, artist_match, credit_name


#? The index's shape. A file whose index is of another shape (or none - a file 2.0.0-player.54 made) has its index
#? made afresh and the answers it holds read into it once, in the background (SavedAnswers' backfill) - the answers
#? themselves are never touched for it.
INDEX_FORMAT = "1"

#? What a mention is of - and, as a full-text row's kind (its rowid's low two bits), what a word was found in
ARTIST, ALBUM, SONG, RELEASE = 1, 2, 3, 4

#? How many of each kind one search answers: the app's own pages (src/routes/search_musicbrainz.py ARTIST_SEARCH_LIMIT,
#? ui/src/app/Search.tsx MUSICBRAINZ_LIMIT, ui/src/lib/songs.ts SONG_SEARCH_LIMIT) - so a saved answer is never longer
#? than the MusicBrainz answer it is drawn above
SAVED_ARTISTS = 10
SAVED_ALBUMS = 12
SAVED_SONGS = 25
#? ...and how many pressings one song brings at most (Bohemian Rhapsody is on 353)
SAVED_PRESSINGS_PER_SONG = 100
#? (after review) How many albums CREDITED to exactly the words typed one search answers beside them (`credited`): the
#? artist reading's albums ("portishead" read as the artist you have), chosen from all of theirs that are saved -
#? never from the bm25 candidates, which titles naming them fill first ("metallica" left only the album Metallica of a
#? whole saved discography) - in the studio order the app reads an artist's albums in (studioOrder), so the app's own
#? filters (their studio albums, MUSICBRAINZ_LIMIT of them) find theirs among these. And how many of their albums
#? are looked through for them
SAVED_CREDITED = 50
CREDITED_CANDIDATES = 2000
#? How many of each kind bm25 puts forward before the exact ones are lifted to the top (`_lifted`): enough that a
#? name typed exactly is among them - "bjork" finds 40 Icelanders with Björk in their names, and Björk herself,
#? with her many spellings in the other names, was seventh by bm25 alone
CANDIDATES = 100

#? bm25's weights: an artist's own name over the other names they go by; a title over its credit
ARTIST_WEIGHTS = (10.0, 4.0)
TITLE_WEIGHTS = (10.0, 2.0)

def stored_id(key: str):
    """A MusicBrainz id as the index keeps it: a UUID's 16 bytes (not its 36 characters - kept in a row and its index
    for every thing), anything else as it is."""
    try:
        parsed = uuid.UUID(key)
    except (ValueError, AttributeError, TypeError):
        return key
    return parsed.bytes if str(parsed) == key else key


def given_id(value) -> str:
    """...and as MusicBrainz writes it."""
    return str(uuid.UUID(bytes=bytes(value))) if isinstance(value, (bytes, memoryview)) and len(value) == 16 else str(value)


#? Each thing's row is numbered in the order it was first seen (`n`, AUTOINCREMENT: never a number again once gone, so
#? nothing that names one can come to name another), and a full-text row's rowid is n * 4 + its kind - in order, so
#? the full-text index's lists of rows stay small (numbered by a hash of the id they took two and a half times the
#? room, measured).
#? ONE full-text table for the three kinds (a row's rowid is its thing's n * 4 + its kind), CONTENTLESS - the
#? words live in the things' own rows, so they aren't kept twice - and deletable by rowid (contentless_delete, SQLite
#? 3.43), with no prefix index (a prefix is a range of the terms, quick at this size). Measured on recorded answers
#? (notes/backend-gotchas.md): a third of the size of three tables keeping their own copy with prefix indexes.
WORDS = ("CREATE VIRTUAL TABLE IF NOT EXISTS saved_words USING fts5(name, other, content = '', contentless_delete = 1, "
         "tokenize = 'unicode61 remove_diacritics 2')")

INDEX_SCHEMA = (
    """CREATE TABLE IF NOT EXISTS saved_artists (
    n              INTEGER PRIMARY KEY AUTOINCREMENT,
    id             BLOB NOT NULL UNIQUE,   -- stored_id(its MusicBrainz id)
    name           TEXT,
    sort_name      TEXT,
    aliases        TEXT,     -- JSON: the other names they go by
    disambiguation TEXT,
    type           TEXT,
    country        TEXT,
    begin          TEXT,
    end            TEXT,
    seen           REAL NOT NULL   -- fetched_at of the newest answer that said anything of them
)""",
    """CREATE TABLE IF NOT EXISTS saved_albums (
    n                  INTEGER PRIMARY KEY AUTOINCREMENT,
    id                 BLOB NOT NULL UNIQUE,
    title              TEXT,
    primary_type       TEXT,
    secondary_types    TEXT,  -- JSON, NULL for none
    first_release_date TEXT,
    credit             TEXT,  -- as the app renders it (artists.credit_name): the words searched
    artist_credit      TEXT,  -- JSON, compact (_pack_credit): MusicBrainz's credit, what a row reads of it
    seen               REAL NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS saved_songs (
    n              INTEGER PRIMARY KEY AUTOINCREMENT,
    id             BLOB NOT NULL UNIQUE,   -- stored_id(its MusicBrainz id)
    title          TEXT,
    length         INTEGER,
    disambiguation TEXT,
    credit         TEXT,
    artist_credit  TEXT,
    pressings      TEXT,  -- JSON: {the release's n: [its track's number, length, title when not the song's]}
    seen           REAL NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS saved_releases (
    n             INTEGER PRIMARY KEY AUTOINCREMENT,
    id            BLOB NOT NULL UNIQUE,
    album         BLOB NOT NULL,   -- its release group's id
    title         TEXT,            -- NULL when the album's
    status        TEXT,
    date          TEXT,
    country       TEXT,
    artist_credit TEXT,            -- NULL when the album's
    seen          REAL NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS saved_mentions (
    answer INTEGER NOT NULL,   -- the answers table's rowid
    kind   INTEGER NOT NULL,
    thing  INTEGER NOT NULL,   -- the thing's n
    PRIMARY KEY (answer, kind, thing)
) WITHOUT ROWID""",
    "CREATE INDEX IF NOT EXISTS saved_mentions_thing ON saved_mentions (kind, thing)",
    WORDS,
)

#? (after review) Every change to the answers - by ANY deadwax, an older one that knows nothing of the index included -
#? marks it stale (meta `index_stale`); this one clears the mark in the same transaction as each change it keeps the
#? index in step with (SavedAnswers._in_step). A file 2.0.0-player.55 used since this one indexed it - rolled back,
#? then forward - finds the mark, and the index is made afresh and read in again: never things found that are gone,
#? nor new answers never indexed. (A count of the answers can't tell: .55's Clear and one answer saved after it
#? leave the count and the highest rowid as they were.)
STALE = "index_stale"
TRIGGERS = tuple(
    f"CREATE TRIGGER IF NOT EXISTS saved_answers_{name} AFTER {event} ON answers "
    f"BEGIN INSERT OR REPLACE INTO meta (name, value) VALUES ('{STALE}', '1'); END"
    for name, event in (("inserted", "INSERT"), ("deleted", "DELETE"), ("changed", "UPDATE OF key, body")))
TRIGGER_NAMES = ("saved_answers_inserted", "saved_answers_deleted", "saved_answers_changed")

INDEX_TABLES = ("saved_words", "saved_mentions", "saved_releases", "saved_songs", "saved_albums", "saved_artists")
#? sqlite_sequence (AUTOINCREMENT's) is SQLite's own: its rows for these go with them
#? the shape's own: dropped with it (a file of 2.0.0-player.56's builds before this one's)
_OLD_TABLES = ("saved_artists_fts", "saved_albums_fts", "saved_songs_fts", "saved_tracks")


def make_index(connection: sqlite3.Connection, drop: bool = False) -> None:
    """The index's tables (inside the caller's transaction). `drop`: emptied first - a file of another index shape."""
    if drop:
        for trigger in TRIGGER_NAMES:
            connection.execute(f"DROP TRIGGER IF EXISTS {trigger}")
        for table in INDEX_TABLES + _OLD_TABLES:
            connection.execute(f"DROP TABLE IF EXISTS {table}")
    for statement in INDEX_SCHEMA + TRIGGERS:
        connection.execute(statement)


def clear_index(connection: sqlite3.Connection) -> None:
    """Everything in the index gone (Clear) - inside the caller's transaction."""
    for table in INDEX_TABLES:
        connection.execute(f"DELETE FROM {table}")

# ============================================================ reading an answer: pure


def _text(value) -> str | None:
    return value.strip() or None if isinstance(value, str) else None


def _lower(value) -> str | None:
    text = _text(value)
    return text.lower() if text else None


def _int(value) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _list(value) -> list:
    return value if isinstance(value, list) else []


def _credit(credit) -> list[dict] | None:
    """MusicBrainz's artist credit, trimmed to what a row reads: each name, joinphrase and artist's id and name."""
    entries = []
    for entry in _list(credit):
        if not isinstance(entry, dict):
            continue
        artist = entry.get("artist") if isinstance(entry.get("artist"), dict) else {}
        trimmed = {"name": entry.get("name") or artist.get("name") or "", "joinphrase": entry.get("joinphrase") or ""}
        if _lower(artist.get("id")):
            trimmed["artist"] = {"id": _lower(artist.get("id")), "name": artist.get("name") or trimmed["name"]}
        entries.append(trimmed)
    return entries or None


class Found:
    """What one answer mentions: each thing by id, with the fields this answer carries (None: not carried)."""

    def __init__(self):
        self.artists: dict[str, dict] = {}
        self.albums: dict[str, dict] = {}
        self.songs: dict[str, dict] = {}
        self.releases: dict[str, dict] = {}
        self.tracks: dict[tuple[str, str], dict] = {}

    def is_empty(self) -> bool:
        return not (self.artists or self.albums or self.songs or self.releases)

    def _merge(self, things: dict, key: str, fields: dict) -> None:
        was = things.get(key)
        if was is None:
            things[key] = fields
            return
        #? one answer naming a thing twice (an artist in a credit and as a search hit): what either said
        for name, value in fields.items():
            if was.get(name) is None and value is not None:
                was[name] = value

    def artist(self, artist, full: bool = False) -> None:
        """An artist - an artist search's or page's (`full`: what it doesn't say of aliases is "none"), or a credit's."""
        if not isinstance(artist, dict) or not _lower(artist.get("id")):
            return
        life = artist.get("life-span") if isinstance(artist.get("life-span"), dict) else {}
        aliases = [alias.get("name") for alias in _list(artist.get("aliases")) if isinstance(alias, dict) and _text(alias.get("name"))]
        self._merge(self.artists, _lower(artist["id"]), {
            "name": _text(artist.get("name")),
            "sort_name": _text(artist.get("sort-name")),
            "aliases": aliases if (aliases or (full and "aliases" in artist)) else None,
            "disambiguation": artist.get("disambiguation") if isinstance(artist.get("disambiguation"), str) else None,
            "type": _text(artist.get("type")),
            "country": _text(artist.get("country")),
            "begin": _text(life.get("begin")),
            "end": _text(life.get("end")),
        })

    def credit(self, credit) -> None:
        for entry in _list(credit):
            if isinstance(entry, dict):
                self.artist(entry.get("artist"))

    def album(self, group, credit_from=None) -> str | None:
        """A release group. `credit_from`: the credit to say it by when the group itself carries none (a recording
        search's release - kept only where nothing better is known: see _upsert_album)."""
        if not isinstance(group, dict) or not _lower(group.get("id")):
            return None
        key = _lower(group["id"])
        credit = _credit(group.get("artist-credit"))
        weak = None
        if credit is None and credit_from is not None:
            weak = _credit(credit_from)
        secondary = group.get("secondary-types")
        self._merge(self.albums, key, {
            "title": _text(group.get("title")),
            "primary_type": _text(group.get("primary-type")),
            "secondary_types": [str(each) for each in secondary] if isinstance(secondary, list) else None,
            "first_release_date": group.get("first-release-date") if isinstance(group.get("first-release-date"), str) else None,
            "artist_credit": credit,
            "weak_credit": weak,
        })
        self.credit(group.get("artist-credit"))
        return key

    def release(self, release, album: str) -> str | None:
        if not isinstance(release, dict) or not _lower(release.get("id")):
            return None
        key = _lower(release["id"])
        self._merge(self.releases, key, {
            "album": album,
            "title": _text(release.get("title")),
            "status": _text(release.get("status")),
            "date": release.get("date") if isinstance(release.get("date"), str) else None,
            "country": _text(release.get("country")),
            "artist_credit": _credit(release.get("artist-credit")),
        })
        self.credit(release.get("artist-credit"))
        return key

    def song(self, recording, credit_from=None) -> str | None:
        if not isinstance(recording, dict) or not _lower(recording.get("id")):
            return None
        key = _lower(recording["id"])
        credit = recording.get("artist-credit") if _list(recording.get("artist-credit")) else credit_from
        self._merge(self.songs, key, {
            "title": _text(recording.get("title")),
            "length": _int(recording.get("length")),
            "disambiguation": recording.get("disambiguation") if isinstance(recording.get("disambiguation"), str) else None,
            "artist_credit": _credit(credit),
        })
        self.credit(credit)
        return key

    def track(self, recording: str, release: str, track, medium) -> None:
        track = track if isinstance(track, dict) else {}
        medium = medium if isinstance(medium, dict) else {}
        self.tracks.setdefault((recording, release), {
            "track": _lower(track.get("id")),
            "number": _text(track.get("number")),
            "title": _text(track.get("title")),
            "length": _int(track.get("length")),
            "medium": _int(medium.get("position")),
            "format": _text(medium.get("format")),
            "track_count": _int(medium.get("track-count")),
        })


def _param(params, name: str) -> str | None:
    for key, value in params:
        if key == name:
            return value
    return None


def read_answer(endpoint: str, params, payload) -> Found:
    """
    What one saved answer mentions - `params` as the disk key holds them (a list of [name, value], or a dict). Every
    answer the app asks for is read:
      - `release-group/` - an album search (`query`) or a discography page (`artist`): its groups and their credits;
      - `recording/` - a song search: its recordings, each release they are on (and its group), and the track;
      - `release/` with `release-group` - an album's pressings (with their tracklists when asked with recordings):
        the group (from each pressing's own, when asked with release-groups), the pressings, and every track's
        recording - the songs on the album;
      - `artist/` - an artist search (`query`), or one artist (a page, or their aliases);
    and nothing else (one release looked up alone carries no group to put its songs on; the connection check is
    never saved). A payload of a shape it doesn't know reads as nothing - never an error.
    """
    found = Found()
    if not isinstance(payload, dict):
        return found
    params = list(params.items()) if isinstance(params, dict) else [tuple(each) for each in _list(params) if isinstance(each, (list, tuple)) and len(each) == 2]
    endpoint = endpoint or ""

    if endpoint == "release-group/":
        for group in _list(payload.get("release-groups")):
            found.album(group)

    elif endpoint == "recording/":
        for recording in _list(payload.get("recordings")):
            song = found.song(recording)
            if song is None:
                continue
            for release in _list(recording.get("releases")):
                if not isinstance(release, dict):
                    continue
                album = found.album(release.get("release-group"), credit_from=release.get("artist-credit"))
                pressing = found.release(release, album) if album else None
                if pressing is None:
                    continue
                for medium in _list(release.get("media")):
                    for track in _list(medium.get("track") if isinstance(medium, dict) else None):
                        found.track(song, pressing, track, medium)
                        break
                if (song, pressing) not in found.tracks:
                    found.track(song, pressing, None, None)

    elif endpoint == "release/":
        group_id = _lower(_param(params, "release-group"))
        for release in _list(payload.get("releases")):
            if not isinstance(release, dict):
                continue
            album = found.album(release.get("release-group")) if isinstance(release.get("release-group"), dict) else None
            album = album or group_id
            if not album:
                continue
            pressing = found.release(release, album)
            if pressing is None:
                continue
            for medium in _list(release.get("media")):
                if not isinstance(medium, dict):
                    continue
                for track in _list(medium.get("tracks")):
                    if not isinstance(track, dict):
                        continue
                    song = found.song(track.get("recording"), credit_from=track.get("artist-credit") or release.get("artist-credit"))
                    if song is not None:
                        found.track(song, pressing, track, medium)

    elif endpoint == "artist/":
        for artist in _list(payload.get("artists")):
            found.artist(artist, full=True)

    elif endpoint.startswith("artist/") and endpoint.count("/") == 1:
        found.artist(payload, full=True)

    return found



# ============================================================ keeping the index: on the saved answers' worker


def _json(value) -> str | None:
    return None if value is None else json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _loads(text, default=None):
    try:
        return json.loads(text) if text else default
    except ValueError:
        return default


def _pack_credit(credit: list[dict] | None) -> str | None:
    """A credit as the index keeps it: [name, joinphrase, artist id, artist name] each, the last left off when it is
    the credited name and the id when there is none - an artist's id is most of what a credit costs."""
    if not credit:
        return None
    packed = []
    for entry in credit:
        artist = entry.get("artist") or {}
        row = [entry.get("name") or "", entry.get("joinphrase") or ""]
        if artist.get("id"):
            row.append(artist["id"])
            if (artist.get("name") or "") != row[0]:
                row.append(artist.get("name") or "")
        packed.append(row)
    return _json(packed)


def _unpack_credit(text) -> list[dict]:
    """...and as MusicBrainz says it: [{name, joinphrase, artist: {id, name}}]."""
    credit = []
    for row in _loads(text, []) or []:
        if not isinstance(row, list) or len(row) < 2:
            continue
        entry = {"name": row[0], "joinphrase": row[1]}
        if len(row) >= 3:
            entry["artist"] = {"id": row[2], "name": row[3] if len(row) >= 4 else row[0]}
        credit.append(entry)
    return credit


def _upsert(connection: sqlite3.Connection, table: str, key: str, fields: dict, seen: float, weak: tuple = (),
            union: tuple = ()) -> int:
    """One thing's row, its number answered: the newest answer's fields win, a field it doesn't carry (None) keeps the
    older one's - a `weak` field only ever fills one nothing better has filled, and a `union` field (a song's
    pressings, already merged with what is stored) is written as given, however old the answer (the review's catch:
    an album page read in by the backfill after a newer song search lost the pressings it added)."""
    names = list(fields)
    sets = []
    for name in names:
        if name in weak:
            sets.append(f"{name} = COALESCE({table}.{name}, excluded.{name})")
        elif name in union:
            sets.append(f"{name} = COALESCE(excluded.{name}, {table}.{name})")
        else:
            sets.append(f"{name} = CASE WHEN excluded.seen >= {table}.seen THEN COALESCE(excluded.{name}, {table}.{name}) "
                        f"ELSE COALESCE({table}.{name}, excluded.{name}) END")
    stored = stored_id(key)
    connection.execute(
        f"INSERT INTO {table} (id, {', '.join(names)}, seen) VALUES (?, {', '.join('?' for _ in names)}, ?) "
        f"ON CONFLICT(id) DO UPDATE SET {', '.join(sets)}, seen = MAX({table}.seen, excluded.seen)",
        (stored, *fields.values(), seen),
    )
    return connection.execute(f"SELECT n FROM {table} WHERE id = ?", (stored,)).fetchone()[0]


def _words_of(connection: sqlite3.Connection, kind: int, key: str) -> tuple | None:
    """What a thing is searched by: an artist's name and the other names they go by; an album's or a song's title and
    its credit - None when it isn't there."""
    if kind == ARTIST:
        row = connection.execute("SELECT name, sort_name, aliases FROM saved_artists WHERE id = ?", (stored_id(key),)).fetchone()
        if row is None:
            return None
        name, sort_name, aliases = row
        seen, other = {(name or "").casefold()}, []
        for each in [sort_name or "", *(_loads(aliases, []) or [])]:
            if each and each.casefold() not in seen:
                seen.add(each.casefold())
                other.append(each)
        return name or "", " | ".join(other)
    table = "saved_albums" if kind == ALBUM else "saved_songs"
    row = connection.execute(f"SELECT title, credit FROM {table} WHERE id = ?", (stored_id(key),)).fetchone()
    return None if row is None else (row[0] or "", row[1] or "")


def _sync_words(connection: sqlite3.Connection, kind: int, n: int, before: tuple | None, after: tuple | None) -> None:
    """A thing's words in the full-text table - written only when they changed."""
    if before == after:
        return
    if before is not None:
        connection.execute("DELETE FROM saved_words WHERE rowid = ?", (n * 4 + kind,))
    if after is not None:
        connection.execute("INSERT INTO saved_words (rowid, name, other) VALUES (?, ?, ?)", (n * 4 + kind, *after))


def index_answer(connection: sqlite3.Connection, answer: int, found: Found, seen: float) -> None:
    """One answer's things into the index, and its mentions of them - inside the caller's transaction."""
    mentions = []

    def searched(kind: int, table: str, key: str, fields: dict, weak: tuple = (), union: tuple = ()) -> None:
        before = _words_of(connection, kind, key)
        n = _upsert(connection, table, key, fields, seen, weak, union)
        _sync_words(connection, kind, n, before, _words_of(connection, kind, key))
        mentions.append((answer, kind, n))

    for key, fields in found.artists.items():
        searched(ARTIST, "saved_artists", key, {**fields, "aliases": _json(fields["aliases"])})
    album_credit = {}
    album_title = {}
    for key, fields in found.albums.items():
        strong, weak = fields["artist_credit"], fields.get("weak_credit")
        credit = strong if strong is not None else weak
        album_credit[key] = credit
        album_title[key] = fields["title"]
        searched(ALBUM, "saved_albums", key, {
            "title": fields["title"], "primary_type": fields["primary_type"],
            "secondary_types": _json(fields["secondary_types"]) if fields["secondary_types"] else None,
            "first_release_date": fields["first_release_date"],
            "credit": credit_name(credit) if credit else None, "artist_credit": _pack_credit(credit),
        #? a credit read off a recording's release (no group credit) only fills one nothing better has
        }, weak=("credit", "artist_credit") if strong is None else ())
    #? the pressings first: a song's say which it is on by their n
    release_n: dict[str, int] = {}
    for key, fields in found.releases.items():
        album = fields["album"]
        credit = fields["artist_credit"]
        same_credit = credit is not None and credit == album_credit.get(album)
        n = _upsert(connection, "saved_releases", key, {
            "album": stored_id(album), "title": None if fields["title"] == album_title.get(album) else fields["title"],
            "status": fields["status"], "date": fields["date"], "country": fields["country"],
            "artist_credit": None if same_credit else _pack_credit(credit),
        }, seen)
        mentions.append((answer, RELEASE, n))
        release_n[key] = n
    #? each song's pressings, from this answer: merged into what other answers said - the newer one's entry winning
    #? for a pressing both name - and never lost, whichever answer is read in first
    pressings: dict[str, dict] = {}
    for (recording, release), fields in found.tracks.items():
        title = fields["title"] if fields["title"] != (found.songs.get(recording) or {}).get("title") else None
        entry = [fields["number"], fields["length"]] + ([title] if title else [])
        if release in release_n:
            pressings.setdefault(recording, {})[str(release_n[release])] = entry
    for key, fields in found.songs.items():
        credit = fields["artist_credit"]
        row = connection.execute("SELECT pressings, seen FROM saved_songs WHERE id = ?", (stored_id(key),)).fetchone()
        stored, this = (_loads(row[0], {}) or {}) if row else {}, pressings.get(key, {})
        merged = {**stored, **this} if row is None or seen >= row[1] else {**this, **stored}
        searched(SONG, "saved_songs", key, {
            "title": fields["title"], "length": fields["length"], "disambiguation": fields["disambiguation"],
            "credit": credit_name(credit) if credit else None, "artist_credit": _pack_credit(credit),
            "pressings": _json(merged) if merged else None,
        }, union=("pressings",))
    connection.executemany("INSERT OR IGNORE INTO saved_mentions (answer, kind, thing) VALUES (?, ?, ?)", mentions)


_TABLES = {ARTIST: "saved_artists", ALBUM: "saved_albums", SONG: "saved_songs", RELEASE: "saved_releases"}


def unindex(connection: sqlite3.Connection, answers: list[int]) -> int:
    """
    Answers gone (dropped by the trim, replaced by a refresh, cleared): their mentions gone, and every thing no
    answer mentions any more gone with them, its words too. Inside the caller's transaction. How many things went. (A
    song's pressings name releases; one gone simply finds nothing to join to - and isn't counted: `search` orders
    songs by the pressings that join, never by the numbers its pressings still hold.)
    """
    if not answers:
        return 0
    things: set[tuple[int, int]] = set()
    for answer in answers:
        things.update(connection.execute("SELECT kind, thing FROM saved_mentions WHERE answer = ?", (answer,)).fetchall())
        connection.execute("DELETE FROM saved_mentions WHERE answer = ?", (answer,))
    gone = 0
    for kind, n in things:
        if connection.execute("SELECT 1 FROM saved_mentions WHERE kind = ? AND thing = ? LIMIT 1", (kind, n)).fetchone():
            continue
        table = _TABLES.get(kind)
        if table is None:
            continue
        if kind != RELEASE:
            connection.execute("DELETE FROM saved_words WHERE rowid = ?", (n * 4 + kind,))
        connection.execute(f"DELETE FROM {table} WHERE n = ?", (n,))
        gone += 1
    return gone


def counts(connection: sqlite3.Connection) -> dict:
    """How many of each thing the index holds."""
    return {name: connection.execute(f"SELECT COUNT(*) FROM saved_{name}").fetchone()[0]
            for name in ("artists", "albums", "songs", "releases", "mentions")}


# ============================================================ searching it


def match_expression(words: str) -> str | None:
    """
    The words typed as an FTS5 query: every word must match, the last one as a prefix - each quoted (so nothing
    typed is read as FTS5's own syntax: AND, OR, NEAR, a column name, a star), its quotes doubled. A word with
    nothing in it to match (all punctuation) is left out; None when no word is left.
    """
    terms = []
    for word in (words or "").split():
        if not any(ch.isalnum() for ch in word):
            continue
        terms.append('"' + word.replace('"', '""') + '"')
    if not terms:
        return None
    terms[-1] += "*"
    return " ".join(terms)


def _lifted(rows: list, names, words: str) -> list:
    """
    bm25's order (`rows`, best first), with what is named EXACTLY as typed lifted to the top, then what starts with
    it - each in bm25's order still. `names(row)` is what a row is called: an artist's name and the other names they
    go by, an album's or a song's title. Folded as the app folds a name (case, accents, which dash).
    """
    typed = _fold(words)

    def lift(row) -> int:
        folded = [_fold(name) for name in names(row) if name]
        if typed in folded:
            return 0
        return _lift_of(folded[0] if folded else "", words)

    return sorted(rows, key=lift)


def _lift_of(name, words: str) -> int:
    """_lifted's level for one name: 0 named exactly as typed, 1 starting with it, 2 the rest."""
    typed, folded = _fold(words), _fold(name or "")
    return 0 if folded == typed else 1 if folded.startswith(typed) else 2


def _matching(connection: sqlite3.Connection, kind: int, query: str, weights: tuple) -> list[int]:
    """The things of a kind whose words match, best first by bm25 - their rowids, CANDIDATES at most."""
    return [rowid // 4 for (rowid,) in connection.execute(
        "SELECT rowid FROM saved_words WHERE saved_words MATCH ? AND rowid % 4 = ? ORDER BY bm25(saved_words, ?, ?) LIMIT ?",
        (query, kind, *weights, CANDIDATES))]


def name_key(name) -> str:
    """A name as the app COMPARES one (ui/src/lib/owned.ts foldName - its twin): accents, case, bracketed asides, a
    leading "The", & and "and" folded away. tests/test_saved_search.py holds the two to one answer."""
    text = "".join(ch for ch in unicodedata.normalize("NFKD", str(name or "")) if not unicodedata.combining(ch)).lower()
    text = re.sub(r"\s*[(\[][^)\]]*[)\]]", " ", text)
    text = re.sub("[\u2019\u2018`\u00b4]", "'", text)
    text = text.replace("&", " and ")
    text = re.sub(r"[\W_]+", " ", text).strip()
    return text[4:] if text.startswith("the ") else text


def _studio_rank(group: dict, at: int) -> tuple:
    """ui/src/lib/searchList.ts studioOrder's order: Album before EP before the rest, plain before any secondary type,
    earliest first (no date last), then as found."""
    primary = (group.get("primary-type") or "").lower()
    return (0 if primary == "album" else 1 if primary == "ep" else 2, 1 if group.get("secondary-types") else 0,
            (group.get("first-release-date") or "") + "~", at)


def _credited(connection: sqlite3.Connection, words: str) -> list[dict]:
    """The albums saved that are credited to exactly the words typed (name_key), in studio order, SAVED_CREDITED at
    most - found by their credit's words, whatever their titles."""
    wanted = name_key(words)
    terms = [term for term in wanted.split() if term not in ("and", "the")]
    if not wanted or not terms:
        return []
    query = "other : (" + " ".join('"' + term.replace('"', '""') + '"' for term in terms) + ")"
    rowids = [rowid // 4 for (rowid,) in connection.execute(
        "SELECT rowid FROM saved_words WHERE saved_words MATCH ? AND rowid % 4 = ? LIMIT ?", (query, ALBUM, CREDITED_CANDIDATES))]
    groups = []
    for at, row in enumerate(_rows(connection, "saved_albums", "id, title, primary_type, secondary_types, first_release_date, artist_credit, credit", rowids)):
        if name_key(row[6]) != wanted:
            continue
        groups.append((_group(row[:6]), at))
    groups.sort(key=lambda each: _studio_rank(*each))
    return [group for group, _ in groups[:SAVED_CREDITED]]


def _group(row) -> dict:
    """An album row as a release group as /fully_search answers one."""
    key, title, primary, secondary, date, credit = row
    group = {"id": given_id(key), "title": title or "", "secondary-types": _loads(secondary, []) or []}
    if primary:
        group["primary-type"] = primary
    group["first-release-date"] = date or ""
    group["artist-credit"] = _unpack_credit(credit)
    return group


def _rows(connection: sqlite3.Connection, table: str, columns: str, rowids: list[int]) -> list:
    """The things those rowids are, in that order."""
    if not rowids:
        return []
    found = {row[0]: row[1:] for row in connection.execute(
        f"SELECT rowid, {columns} FROM {table} WHERE rowid IN ({', '.join('?' for _ in rowids)})", rowids)}
    return [found[rowid] for rowid in rowids if rowid in found]


def search(connection: sqlite3.Connection, words: str, artists: int = SAVED_ARTISTS, albums: int = SAVED_ALBUMS,
           songs: int = SAVED_SONGS) -> dict:
    """
    The artists, albums and songs the index holds matching `words`, best first - in the shapes the app's own
    MusicBrainz routes answer: `artists` as /artists ({matches: [artist_match], count}), `albums` as /fully_search
    ({release-groups, count}), `songs` as /songs ({recordings, count}, each recording with the pressings it is on) -
    and `credited`, as `albums`: the albums credited to exactly these words (`_credited` - the artist reading's).
    """
    query = match_expression(words)
    empty = {"artists": {"matches": [], "count": 0}, "albums": {"release-groups": [], "count": 0},
             "songs": {"recordings": [], "count": 0}, "credited": {"release-groups": [], "count": 0}}
    if query is None:
        return empty

    found_artists = []
    rows = _rows(connection, "saved_artists", "id, name, sort_name, aliases, disambiguation, type, country, begin, end",
                 _matching(connection, ARTIST, query, ARTIST_WEIGHTS))
    for row in _lifted(rows, lambda row: [row[1], row[2], *(_loads(row[3], []) or [])], words)[:artists]:
        key, name, sort_name, aliases, disambiguation, kind, country, begin, end = row
        artist = {"id": given_id(key), "name": name or "", "sort-name": sort_name or "", "disambiguation": disambiguation or "",
                  "type": kind or "", "country": country or "",
                  "aliases": [{"name": alias} for alias in _loads(aliases, []) or []],
                  "life-span": {"begin": begin, "end": end}}
        #? the /artists route's own shape: matched_as the name of theirs the words are a spelling of, as there
        found_artists.append(artist_match(artist, words))

    found_albums = []
    rows = _rows(connection, "saved_albums", "id, title, primary_type, secondary_types, first_release_date, artist_credit",
                 _matching(connection, ALBUM, query, TITLE_WEIGHTS))
    for row in _lifted(rows, lambda row: [row[1]], words)[:albums]:
        found_albums.append(_group(row))
    credited = _credited(connection, words)

    recordings = []
    rows = _rows(connection, "saved_songs", "id, title, length, disambiguation, artist_credit, pressings",
                 _matching(connection, SONG, query, TITLE_WEIGHTS))
    for key, title, length, disambiguation, credit, pressed in rows:
        on = _loads(pressed, {}) or {}
        releases = []
        ids = list(on)
        for start in range(0, len(ids), 500):
            chunk = ids[start:start + 500]
            for release_row in connection.execute(
                "SELECT r.n, r.id, COALESCE(r.title, a.title), r.status, r.date, r.country, COALESCE(r.artist_credit, a.artist_credit), "
                "a.id, a.title, a.primary_type, a.secondary_types "
                f"FROM saved_releases r JOIN saved_albums a ON a.id = r.album WHERE r.n IN ({', '.join('?' for _ in chunk)})",
                [int(each) for each in chunk],
            ):
                (release_n, release_id, release_title, status, date, country, release_credit, group_id, group_title, primary, secondary) = release_row
                release_id, group_id = given_id(release_id), given_id(group_id)
                group = {"id": group_id, "title": group_title or "", "secondary-types": _loads(secondary, []) or []}
                if primary:
                    group["primary-type"] = primary
                printed, track_length, *rest = on.get(str(release_n)) or [None, None]
                track = {"number": printed or "", "title": rest[0] if rest else title or "", "length": track_length}
                releases.append({"id": release_id, "title": release_title or "", "status": status, "date": date or "", "country": country,
                                 "artist-credit": _unpack_credit(release_credit), "release-group": group, "media": [{"track": [track]}]})
        if not releases:
            continue
        releases.sort(key=lambda release: (not release["date"], release["date"], release["id"]))
        recordings.append({"id": given_id(key), "title": title or "", "length": length, "disambiguation": disambiguation or "",
                           "artist-credit": _unpack_credit(credit), "releases": releases})
    #? songs of one title (a song search's covers and live takes, saved too) told apart by how many pressings each is
    #? on - those still saved, never a number its pressings kept of one trimmed away (the review's catch): the one most
    #? released first - "glory box" means Portishead's, on seventeen, before a cover on one. Stable: bm25's order within
    recordings.sort(key=lambda recording: (_lift_of(recording["title"], words), -len(recording["releases"])))
    recordings = recordings[:songs]
    for recording in recordings:
        recording["releases"] = recording["releases"][:SAVED_PRESSINGS_PER_SONG]

    return {
        "artists": {"matches": found_artists, "count": len(found_artists)},
        "albums": {"release-groups": found_albums, "count": len(found_albums)},
        "songs": {"recordings": recordings, "count": len(recordings)},
        "credited": {"release-groups": credited, "count": len(credited)},
    }
