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
"""

import json
import re
import time
import unicodedata
from dataclasses import dataclass
from typing import Any

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
    """Last.fm answered: its JSON (from 2.1.37 on, each method's answer parsed to deadwax's shape)."""
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
    """`text` with `secret` taken out of it, wherever it is."""
    return text.replace(secret, "(the key)") if secret else text


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
