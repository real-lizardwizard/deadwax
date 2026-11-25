"""
Last.fm, the pure half (2.1.36 - notes/lastfm.md; the design is deadwax-plans/lastfm.md). No I/O:
src/api/lastfm_endpoint.py asks Last.fm, src/lastfm_kept.py keeps its answers, and this says what an answer IS and
what a Last.fm name or title is keyed by.

WHAT AN ANSWER IS - classify(). Last.fm's API answers an error as JSON, `{"error": <code>, "message": ...}`, with
an HTTP status that varies, so the code is read first and the status after it. Five outcomes:

  - Answer      the JSON, an object with no error in it;
  - NotKnown    error 6, "invalid parameters" - what an artist, album or track Last.fm doesn't know is believed to
                answer (not seen yet: tests/fixtures/lastfm/record.py records it). Kept as "none", for 3 days;
  - Refused     error 10 (an invalid key) or 26 (a suspended one): the key itself is wrong. The client holds it an
                hour, asking nothing; never kept;
  - Limited     error 29, or an HTTP 429: too many requests. The client asks nothing for a minute; never kept;
  - Unreachable anything else - errors 8, 11 and 16 (Last.fm's own "try again"), any other code, a 5xx, a redirect,
                an answer that isn't a JSON object - and, from the client, a timeout, an answer too big, no turn
                in time. Never kept.

Every Last.fm word kept (a refusal's message) is cleaned - control characters out, one line, at most MESSAGE_MAX
letters - and the key taken out of it, should Last.fm ever quote it back.

THE KEYS a Last.fm name or title meets the library by (the design's 2.4), held to
tests/fixtures/lastfm/match-vectors.json - which the TypeScript's own answers fill
(tests/fixtures/lastfm/export-vectors.cjs) and the iPhone app's Core will be held to too:

  - match_key(title): a feature dropped (an aside "(feat. X)", "[ft. X]", "(with X)"; a tail " feat. X"), then a
    dash take ("- 2015 Remaster", "- Live"), then ui/src/lib/songs.ts titleKey. Remixes, edits and versions stay
    songs of their own;
  - name_key(name): ui/src/lib/owned.ts foldName - a leading "the " and bracketed asides dropped;
  - first_credit(artist): the name before " feat. ", " ft. ", " featuring " or " • " - never split at "&" or ",",
    since "Simon & Garfunkel" is one name.

title_key() and name_key() are ports of the TypeScript, line for line: JavaScript's \\s (its own set of spaces, here
JS_SPACE) and \\b (ASCII word letters - with the i and u flags also the long s and the Kelvin sign, which fold into
them) are spelled out rather than left to Python's, which differ.

AN ARTIST PAGE'S PARTS (2.1.41, S2 - GET /deadwax/lastfm/artist, src/routes/lastfm.py): each method's answer parsed to
the shape deadwax keeps (src/lastfm_kept.py) - never Last.fm's own answer:

  - artist_info(): artist.getInfo as {url, listeners, bio: {summary, content}} - the bio kept with it, so the
    descriptions (S3, 2.1.42) read this same row: one ask serves the artist page and the description;
  - top_tracks(): artist.getTopTracks as {artist_url, top_songs} - top_songs() already folded, so a change to the
    fold (TOP_SONGS, match_key) is a change of the kept shape: bump LASTFM_SHAPE with it;
  - artist_answer(): the route's answer from the two, `why` in words for whoever runs deadwax (auth.Explained's
    rule: the app shows it only to them).

AN ALBUM'S WORDS (2.1.42, S3 - the descriptions, src/routes/describe.py): album_info(), album.getInfo as {url, wiki:
{summary, content}}, cut as a bio is. descriptions.from_lastfm() reads it, and getInfo's bio, as a description.

Every number Last.fm gives is read loosely (count(): its JSON gives most as strings), and every address passed on is
an https one on last.fm (lastfm_url(), descriptions.py's rule too).
"""

import json
import math
import re
import time
import unicodedata
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse

#? Bumped whenever a kept answer's parsed shape changes - the SCAN_FORMAT rule: every kept row's key begins with it
#? (src/lastfm_kept.py), so an answer parsed the old way is never read as the new one
LASTFM_SHAPE = 1

#? Last.fm's error codes (https://www.last.fm/api/errorcodes, read 2026-11-24)
NOT_KNOWN_ERRORS = frozenset({6})
REFUSED_ERRORS = frozenset({10, 26})
LIMITED_ERRORS = frozenset({29})

#? a refusal's message from Last.fm, as kept and said: one line, this long at most
MESSAGE_MAX = 200

#? what an API key looks like: Last.fm's are 32 hex digits (as are its shared secrets, which is why the words say
#? to check). Only ever a flag on the settings row - a value that doesn't match is stored all the same
KEY_SHAPE = re.compile(r"[0-9a-fA-F]{32}")


@dataclass(frozen=True)
class Answer:
    """Last.fm answered: its JSON - or, from a route's ask (2.1.41 on), the answer parsed to deadwax's shape."""
    body: Any


@dataclass(frozen=True)
class NotKnown:
    """Error 6: Last.fm doesn't know the artist, album or track asked for."""
    message: str = ""


@dataclass(frozen=True)
class Refused:
    """Error 10 or 26: Last.fm refused the key. `at` is when (time.time())."""
    error: int
    message: str
    at: float


@dataclass(frozen=True)
class Limited:
    """Error 29 or an HTTP 429: Last.fm asked deadwax to slow down."""
    why: str


@dataclass(frozen=True)
class Unreachable:
    """No usable answer. `why` is deadwax's own words, never an exception's (which can carry the address, and the
    key in it)."""
    why: str


Outcome = Answer | NotKnown | Refused | Limited | Unreachable

#? what each outcome is called in the log
FAILURES = (Refused, Limited, Unreachable)


def without(text: str, secret: str | None) -> str:
    """`text` with `secret` taken out of it, wherever it is and in any case - a key is hex, which Last.fm could quote
    back in capitals."""
    return re.sub(re.escape(secret), "(the key)", text, flags=re.IGNORECASE) if secret else text


def cleaned(text: Any, secret: str | None = None) -> str:
    """Last.fm's words as deadwax keeps them: a string, the key out, control characters out, one line, MESSAGE_MAX
    letters at most."""
    words = without(text if isinstance(text, str) else "", secret)
    words = "".join(" " if not c.isprintable() else c for c in words)
    words = " ".join(words.split())
    return words if len(words) <= MESSAGE_MAX else words[:MESSAGE_MAX - 1].rstrip() + chr(0x2026)


def error_code(value: Any) -> int | None:
    """An `error` field as a number - Last.fm gives an int; a string of digits is read too."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return None


def classify(status: int, body: bytes, now: float, secret: str | None = None) -> Outcome:
    """What an answer from Last.fm is - its HTTP status and body, read whole (and under the client's size limit)."""
    if 300 <= status < 400:
        return Unreachable(f"a redirect ({status}), not followed")
    if status == 429:
        return Limited("HTTP 429")
    try:
        answer = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return Unreachable(f"HTTP {status}" if status != 200 else "an answer that isn't JSON")
    if isinstance(answer, dict) and "error" in answer:
        code = error_code(answer.get("error"))
        message = cleaned(answer.get("message"), secret)
        if code in NOT_KNOWN_ERRORS:
            return NotKnown(message)
        if code in REFUSED_ERRORS:
            return Refused(code, message, now)
        if code in LIMITED_ERRORS:
            return Limited(f"error {code}")
        return Unreachable(f"error {code}" if code is not None else "an error with no code")
    if status != 200:
        return Unreachable(f"HTTP {status}")
    if not isinstance(answer, dict):
        return Unreachable("an answer that isn't a JSON object")
    return Answer(answer)


# ===== the words =================================================================================================

def at_clock(at: float) -> str:
    """When, as the server's clock says it: HH:MM."""
    return time.strftime("%H:%M", time.localtime(at))


def refused_detail(refusal: Refused) -> str:
    """The settings row's detail while a refusal is held."""
    return (f"Last.fm refused this key at {at_clock(refusal.at)} (error {refusal.error}: {refusal.message}) - check "
            f"it's the API key, not the shared secret")


def refused_event(refusal: Refused) -> str:
    """The event log's line, once, as Last.fm first refuses the key."""
    return (f"Last.fm refused LASTFM_API_KEY (error {refusal.error}: {refusal.message}): top songs, similar artists "
            f"and radio are off until it's fixed in Server settings.")


KEY_LOOKS_WRONG = ("doesn't look like a Last.fm API key (32 letters and digits) - check you copied the API key, not "
                   "the shared secret")

KEY_NOT_ONE_WORD = "a Last.fm API key is one word - letters and digits, no spaces"


def one_word(value: str) -> bool:
    """Whether a key typed into Server settings could be one at all: no space or control character inside it (the
    ends are trimmed, as a paste brings a newline)."""
    return not any(c.isspace() or not c.isprintable() for c in value.strip())


# ===== the keys (the design's 2.4) =================================================================================

#? JavaScript's \s: WhiteSpace and LineTerminator (ECMA-262), which Python's \s is not quite
JS_SPACE = "".join(map(chr, (0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, *range(0x2000, 0x200B), 0x2028,
                             0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF)))
_S = f"[{JS_SPACE}]"
#? JavaScript's \w under the i and u flags: ASCII word letters, and the two that case-fold into them
_W = "A-Za-z0-9_" + chr(0x17F) + chr(0x212A)
#? JavaScript's \b, from that \w
_B = f"(?:(?<=[{_W}])(?![{_W}])|(?<![{_W}])(?=[{_W}]))"

#? songs.ts SAME_SONG_ASIDE: an aside naming the same song in another take or mastering - "(live)", "(Remastered
#? 2015)", "(mono)"
SAME_SONG_ASIDE = re.compile(
    rf"{_S}*[(\[]{_S}*(?:live{_B}[^)\]]*|[^)\]]*{_B}remaster(?:ed)?{_B}[^)\]]*|mono|stereo){_S}*[)\]]",
    re.IGNORECASE)
#? owned.ts foldName's bracketed aside, any words in it
ANY_ASIDE = re.compile(rf"{_S}*[(\[][^)\]]*[)\]]")
#? the quotes titleKey and foldName read as an apostrophe
QUOTES = re.compile("[" + "".join(map(chr, (0x2019, 0x2018, 0x60, 0xB4))) + "]")

#? step 1: an aside whose words begin with a feature - "(feat. X)", "[ft X]", "(featuring X)", "(with X)"
FEATURE_ASIDE = re.compile(r"\s*[(\[]\s*(?:feat\.|feat\s|ft\.|ft\s|featuring\s|with\s)[^)\]]*[)\]]", re.IGNORECASE)
#? step 2: an unbracketed feature to the end - " feat. ", " ft. ", " featuring " (never " with ": "Dancing with
#? Myself" is a title)
FEATURE_TAIL = re.compile(r"\s+(?:feat\.|ft\.|featuring)\s", re.IGNORECASE)
#? step 3: a dash, " - " or " – ", and the words after it
DASH = re.compile(r"\s+[-" + chr(0x2013) + r"]\s+")
TAKE_WORD = re.compile(r"\b(?:live|remaster|remastered|mono|stereo)\b", re.IGNORECASE)
#? first_credit's cuts
CREDIT_CUT = re.compile(r"\s+(?:feat\.|ft\.|featuring|" + chr(0x2022) + r")\s+", re.IGNORECASE)


def _depth(text: str) -> int:
    """How many brackets are open at the end of `text`."""
    depth = 0
    for c in text:
        if c in "([":
            depth += 1
        elif c in ")]" and depth:
            depth -= 1
    return depth


def _letters_and(text: str, kept: str) -> str:
    """JavaScript's `.replace(/[^\\p{L}\\p{N}<kept>]+/gu, ' ').trim()`: every run of anything else one space, none at
    the ends."""
    out: list[str] = []
    gap = False
    for c in text:
        if unicodedata.category(c)[0] in "LN" or c in kept:
            if gap and out:
                out.append(" ")
            gap = False
            out.append(c)
        else:
            gap = True
    return "".join(out)


def _folded(text: str) -> str:
    """NFKD, the marks out, lowercased - as both TypeScript folds begin (after titleKey's asides)."""
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.category(c).startswith("M")).lower()


def title_key(title: str | None) -> str:
    """songs.ts titleKey: accents, case and punctuation folded, an aside naming another take or a remaster dropped -
    but no other words in brackets, so "Roads (Max Cooper remix)" stays a song of its own."""
    text = _folded(SAME_SONG_ASIDE.sub(" ", title or ""))
    text = QUOTES.sub("'", text).replace("&", " and ")
    return _letters_and(text, "()[]'")


def name_key(name: str | None) -> str:
    """owned.ts foldName: bracketed asides, accents, a leading "The", & and "and" fold away."""
    text = ANY_ASIDE.sub(" ", _folded(name or ""))
    text = QUOTES.sub("'", text).replace("&", " and ")
    text = _letters_and(text, "")
    return text[4:] if text.startswith("the ") else text


def strip_title(title: str | None) -> str:
    """Steps 1-3 of match_key: the features and the dash takes dropped, the title otherwise as it was."""
    text = FEATURE_ASIDE.sub("", title or "")
    for tail in FEATURE_TAIL.finditer(text):
        if not _depth(text[:tail.start()]):
            text = text[:tail.start()]
            break
    while True:
        dashes = [dash for dash in DASH.finditer(text) if not _depth(text[:dash.start()])]
        if not dashes or not TAKE_WORD.search(text[dashes[-1].end():]):
            break
        text = text[:dashes[-1].start()]
    return text.strip()


def match_key(title: str | None) -> str:
    """The song key a Last.fm track meets a library song by."""
    return title_key(strip_title(title))


def first_credit(artist: str | None) -> str:
    """The first name of a credit: before " feat. ", " ft. ", " featuring " or " • ", never split at & or a comma."""
    text = (artist or "").strip()
    cut = CREDIT_CUT.search(text)
    return text[:cut.start()].strip() if cut else text


# ===== an artist page's parts (2.1.41, S2 - GET /deadwax/lastfm/artist) ==========================================

#? an artist page's top songs, after the fold. Kept folded (top_tracks()), so changing it changes the kept shape:
#? bump LASTFM_SHAPE with it
TOP_SONGS = 10
#? How much of Last.fm's bio is kept, as it wrote it (HTML), for the descriptions (S3): its content (the text S3 reads
#? first) at most BIO_MAX letters, and its summary at most SUMMARY_LETTERS (descriptions.MAX_LETTERS, the most S3
#? shows). Kept rows are written as ASCII JSON (src/lastfm_kept.py), where a letter outside ASCII takes 6 bytes and
#? one outside the BMP 12, so each is cut by what it takes WRITTEN too: SUMMARY_BYTES holds SUMMARY_LETTERS of any
#? script in the BMP, and CONTENT_BYTES is what's left. A getInfo row then fits the keeping's 32 KB (ROW_MAX_BYTES)
#? whatever the script: 13 KB of content, 9 KB of summary, 2 KB of address (URL_MAX), at most 6.5 KB of key (a name
#? of the route's 200 letters folds to at most 6,600 bytes - U+FDFA is 18 letters in NFKD) and under 100 bytes of the
#? rest - 30.5 KB at most. Changing one changes what is kept: bump LASTFM_SHAPE. tests/test_lastfm.py
#? test_a_getinfo_row_always_fits_the_keeping holds it. An album's wiki (album_info, 2.1.42) is cut the same way, and
#? its key is its release group's id (src/lastfm_kept.py release_group_key, under 100 bytes), so its row fits too
BIO_MAX = 4000
SUMMARY_LETTERS = 1500
CONTENT_BYTES = 13 * 1024
SUMMARY_BYTES = 9 * 1024
#? an address longer than this isn't one Last.fm made (its longest recorded: 117)
URL_MAX = 2048
#? a count longer than this isn't a count (and int() refuses past 4300 digits)
COUNT_DIGITS = 18

NO_KEY_WHY = ("No Last.fm API key is set - add LASTFM_API_KEY in Server settings > Connections (a free key from "
              "last.fm/api/account/create).")


def refused_why(refusal: Refused) -> str:
    """The artist route's `why` while Last.fm refuses the key."""
    return (f"Last.fm refused deadwax's API key (error {refusal.error}: {refusal.message}) - check LASTFM_API_KEY in "
            f"Server settings > Connections: it's the API key, not the shared secret.")


#? what an address passed on may hold: printable ASCII - Last.fm's are percent-encoded, every one of the 1,702 in the
#? recordings - but never a space, nor a backslash (which a browser reads as "/": https://evil.example\.last.fm/
#? is evil.example's) nor an @ (whatever is before it is a user name, not the host)
URL_LETTERS = re.compile(r"[!-~]+")


def lastfm_url(link: Any) -> str | None:
    """A Last.fm address as deadwax passes one on: https, on last.fm or a host under it, plain ASCII with no `\\`,
    `@` or space in it, at most URL_MAX letters - else None."""
    if not isinstance(link, str):
        return None
    link = link.strip()
    if (not link.startswith("https://") or len(link) > URL_MAX or not URL_LETTERS.fullmatch(link)
            or "\\" in link or "@" in link):
        return None
    try:
        host = (urlparse(link).hostname or "").lower()
    except ValueError:
        return None
    return link if host == "last.fm" or host.endswith(".last.fm") else None


def count(value: Any) -> int | None:
    """A count Last.fm gave - a string of digits, as its JSON gives most numbers, or a number - else None (absent,
    negative, a fraction, words)."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value >= 0 else None
    if isinstance(value, float):
        return int(value) if math.isfinite(value) and value >= 0 and value.is_integer() else None
    if isinstance(value, str):
        text = value.strip()
        if text.isascii() and text.isdigit() and len(text) <= COUNT_DIGITS:
            return int(text)
    return None


def _name(value: Any) -> str:
    """A name or title as Last.fm wrote it, its ends trimmed - "" for none."""
    if isinstance(value, str):
        return value.strip()
    return str(value) if isinstance(value, int) and not isinstance(value, bool) else ""


def written_size(text: str) -> int:
    """How many bytes `text` takes in a kept row: as ASCII JSON, its quotes aside."""
    return len(json.dumps(text, ensure_ascii=True)) - 2


def _bio_text(value: Any, letters: int, most_bytes: int) -> str | None:
    """A bio's text, its ends trimmed, cut to `letters` and then to what fits in `most_bytes` written."""
    text = (value.strip() if isinstance(value, str) else "")[:letters]
    if written_size(text) > most_bytes:
        used = end = 0
        for letter in text:
            used += written_size(letter)
            if used > most_bytes:
                break
            end += 1
        text = text[:end]
    return text or None


def _object(value: Any) -> dict:
    return value if isinstance(value, dict) else {}


def artist_info(body: Any) -> dict | None:
    """artist.getInfo's answer as deadwax keeps it: {url, listeners, bio: {summary, content}} - None for an answer
    with no artist in it (Unreachable: never kept)."""
    artist = _object(body).get("artist")
    if not isinstance(artist, dict):
        return None
    bio = _object(artist.get("bio"))
    return {
        "url": lastfm_url(artist.get("url")),
        "listeners": count(_object(artist.get("stats")).get("listeners")),
        "bio": {"summary": _bio_text(bio.get("summary"), SUMMARY_LETTERS, SUMMARY_BYTES),
                "content": _bio_text(bio.get("content"), BIO_MAX, CONTENT_BYTES)},
    }


def album_info(body: Any) -> dict | None:
    """album.getInfo's answer as deadwax keeps it (2.1.42, S3 - the descriptions): {url, wiki: {summary, content}}, the
    wiki as Last.fm wrote it (HTML), each field cut as an artist's bio is - None for an answer with no album in it
    (Unreachable: never kept). Nothing else of it is kept: S3 reads only the words and the page they credit."""
    album = _object(body).get("album")
    if not isinstance(album, dict):
        return None
    wiki = _object(album.get("wiki"))
    return {
        "url": lastfm_url(album.get("url")),
        "wiki": {"summary": _bio_text(wiki.get("summary"), SUMMARY_LETTERS, SUMMARY_BYTES),
                 "content": _bio_text(wiki.get("content"), BIO_MAX, CONTENT_BYTES)},
    }


def tracks_of(body: Any) -> list[dict] | None:
    """artist.getTopTracks' tracks, in Last.fm's order - one track alone given as an object too, as Last.fm's JSON
    (made from its XML) can - or None for an answer with no `toptracks` in it."""
    top = _object(body).get("toptracks")
    if not isinstance(top, dict):
        return None
    tracks = top.get("track")
    if isinstance(tracks, dict):
        tracks = [tracks]
    return [track for track in tracks if isinstance(track, dict)] if isinstance(tracks, list) else []


def top_songs(tracks: list[dict]) -> list[dict]:
    """
    An artist's top songs from Last.fm's tracks, in Last.fm's order: a track with no name, or one whose match_key is
    empty, dropped; one whose match_key an earlier track had dropped - the higher rank wins, so "Let It Happen - 2015
    Remaster", "Lost in Yesterday (feat. X)" and a case variant are the song above them, while a remix or an edit is
    a song of its own; the first TOP_SONGS. Titles as Last.fm wrote them.
    """
    songs: list[dict] = []
    seen: set[str] = set()
    for track in tracks:
        title = _name(track.get("name"))
        key = match_key(title) if title else ""
        if not key or key in seen:
            continue
        seen.add(key)
        songs.append({"title": title, "playcount": count(track.get("playcount")),
                      "listeners": count(track.get("listeners")), "url": lastfm_url(track.get("url"))})
        if len(songs) >= TOP_SONGS:
            break
    return songs


def top_tracks(body: Any) -> dict | None:
    """artist.getTopTracks' answer as deadwax keeps it: {artist_url, top_songs} - the artist's address from the
    first track that has one - or None for an answer with no top tracks in it (Unreachable: never kept)."""
    tracks = tracks_of(body)
    if tracks is None:
        return None
    artist_url = next((url for url in (lastfm_url(_object(track.get("artist")).get("url")) for track in tracks) if url),
                      None)
    return {"artist_url": artist_url, "top_songs": top_songs(tracks)}


def _kept_songs(value: Any) -> list[dict]:
    """A kept row's top songs, read as carefully as anything read back."""
    if not isinstance(value, list):
        return []
    return [{"title": song["title"], "playcount": count(song.get("playcount")), "listeners": count(song.get("listeners")),
             "url": lastfm_url(song.get("url"))}
            for song in value if isinstance(song, dict) and isinstance(song.get("title"), str) and song["title"]]


def no_key_answer() -> dict:
    """The artist route's answer with no LASTFM_API_KEY: nothing asked, nothing there."""
    return {"enabled": False, "unavailable": False, "why": NO_KEY_WHY, "url": None, "listeners": None,
            "top_songs": None}


def artist_answer(info: Outcome | None, tracks: Outcome | None, refusal: Refused | None) -> dict:
    """
    GET /deadwax/lastfm/artist's answer from its two parts - each what its ask came to (a kept answer, or Last.fm's),
    None for one the deadline passed - and the refusal the client holds, if any:

      - `url`: getInfo's, else the top tracks' artist's - https on last.fm only;
      - `listeners`: an integer, or None;
      - `top_songs`: the folded list - [] when Last.fm lists nothing, None when it couldn't be had (or doesn't know
        the artist: a definite none, not a failure);
      - `unavailable`: a part couldn't be had just now - failed, or late - so the app keeps this a moment only;
      - `enabled`: false while Last.fm refuses the key and nothing is kept, with `why` saying so.
    """
    parts = (info, tracks)
    found = [part.body if isinstance(part, Answer) and isinstance(part.body, dict) else None for part in parts]
    had = any(isinstance(part, (Answer, NotKnown)) for part in parts)
    got_info, got_tracks = (body or {} for body in found)
    return {
        "enabled": had or refusal is None,
        "unavailable": not all(isinstance(part, (Answer, NotKnown)) for part in parts),
        "why": refused_why(refusal) if refusal is not None else None,
        "url": lastfm_url(got_info.get("url")) or lastfm_url(got_tracks.get("artist_url")),
        "listeners": count(got_info.get("listeners")),
        "top_songs": _kept_songs(got_tracks.get("top_songs")) if found[1] is not None else None,
    }
