"""
Records Last.fm's real answers for deadwax's tests (2.1.36, notes/lastfm.md) - run once, on a machine with a key:

    LASTFM_API_KEY=<your key> python3 tests/fixtures/lastfm/record.py

It asks Last.fm's API every method deadwax will ask - artist.getInfo, artist.getTopTracks, artist.getSimilar,
artist.getTopAlbums (by MusicBrainz id and by name), album.getInfo and track.getSimilar - for Tame Impala, Dance Gavin
Dance and Portishead (and Dummy), a name nobody has, an id nobody has, a misspelling and one track ("Let It Happen"),
about 4 a second. Each answer goes into recorded/<name>.json beside this: the method, what it was asked with, the HTTP
status, Last.fm's Cache-Control and Expires headers, and the answer itself - errors included, since what an unknown
artist answers is one of the things to find out. Standard library only, from the repository's root or anywhere else.

THE KEY: read from the environment, sent only to https://ws.audioscrobbler.com, and taken out of everything written -
it is never among the parameters kept, and any echo of it anywhere in an answer (a message, a header, an address) is
replaced with "<LASTFM_API_KEY>". Every file is read back afterwards, and the run fails if the key is in one. A
redirect is never followed (NoRedirects): the key is in the address, so the redirect itself is recorded - its Location
with the key taken out - and the run stops there, exit status 3.

Its starting point was ~/Library/Caches/deadwax-build/topsongs/lastfm.py, the script James's top songs were compared
with (2026-11-24).
"""

#? the Mac's own python3 can be 3.9, which reads `str | None` in a signature only this way
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://ws.audioscrobbler.com/2.0/"
HERE = Path(__file__).resolve().parent
OUT = HERE / "recorded"
#? what the key becomes in every file written
MARK = "<LASTFM_API_KEY>"
#? at most 4 a second - under the 5 deadwax itself allows
PAUSE_S = 0.25
#? Location is there only on a redirect, which stops the run
HEADERS_KEPT = ("Cache-Control", "Expires", "Content-Type", "Location")

TAME = ("tame-impala", "Tame Impala", "63aa26c3-d59b-4da4-84ac-716b54f1ef4d")
DGD = ("dance-gavin-dance", "Dance Gavin Dance", "16456fed-c9f2-4adf-b6ea-97b648c474d2")
PORTISHEAD = ("portishead", "Portishead", "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11")

#? the four methods an artist page asks, with the limits deadwax asks them with
ARTIST_METHODS = (
    ("artist.getinfo", "info", {}),
    ("artist.gettoptracks", "top-tracks", {"limit": "50"}),
    ("artist.getsimilar", "similar", {"limit": "30"}),
    ("artist.gettopalbums", "top-albums", {"limit": "50"}),
)


def recordings() -> list[tuple[str, str, dict[str, str]]]:
    """Every (file name, method, parameters) to record - never the key, which ask() adds."""
    asked = []
    for slug, name, mbid in (TAME, DGD, PORTISHEAD):
        for method, short, extra in ARTIST_METHODS:
            asked.append((f"{slug}.{short}.mbid", method, {"mbid": mbid, **extra}))
            asked.append((f"{slug}.{short}.name", method, {"artist": name, "autocorrect": "1", **extra}))
    asked += [
        ("portishead.dummy.album-info", "album.getinfo", {"artist": "Portishead", "album": "Dummy", "autocorrect": "1"}),
        ("tame-impala.let-it-happen.similar", "track.getsimilar",
         {"artist": "Tame Impala", "track": "Let It Happen", "limit": "100", "autocorrect": "1"}),
        ("unknown-name.info", "artist.getinfo", {"artist": "Qzxvwy Nonexistent Ensemble 7731", "autocorrect": "1"}),
        ("unknown-name.top-tracks", "artist.gettoptracks",
         {"artist": "Qzxvwy Nonexistent Ensemble 7731", "autocorrect": "1", "limit": "50"}),
        ("unknown-mbid.top-tracks", "artist.gettoptracks",
         {"mbid": "00000000-0000-4000-8000-000000000000", "limit": "50"}),
        ("misspelt.info", "artist.getinfo", {"artist": "Tame Impla", "autocorrect": "1"}),
        ("misspelt.top-tracks", "artist.gettoptracks", {"artist": "Tame Impla", "autocorrect": "1", "limit": "50"}),
        ("misspelt.info.no-autocorrect", "artist.getinfo", {"artist": "Tame Impla"}),
    ]
    return asked


def version() -> str:
    """deadwax's version, read from src/__init__.py without importing it."""
    for line in (HERE.parents[2] / "src" / "__init__.py").read_text(encoding="utf-8").splitlines():
        if line.startswith("__version__ ="):
            return line.split("=", 1)[1].strip().strip("\"'")
    return "unknown"


def without_key(text: str, key: str) -> str:
    """`text` with the key, and its address-encoded forms, replaced by MARK."""
    for form in {key, urllib.parse.quote(key, safe=""), urllib.parse.quote_plus(key)}:
        text = text.replace(form, MARK)
    return text


class NoRedirects(urllib.request.HTTPRedirectHandler):
    """Every redirect refused, before anything is asked of where it points: the key is in the address, and following
    one would carry it there - to a plain http:// address too, which urllib allows. The 3xx comes back as an
    HTTPError, recorded like any other answer, and main() stops there."""

    def refuse(self, req, fp, code, msg, headers):
        return None

    http_error_301 = http_error_302 = http_error_303 = http_error_307 = http_error_308 = refuse


def opener(*network: urllib.request.BaseHandler) -> urllib.request.OpenerDirector:
    """The one way the recorder asks anything: urllib's opener with NoRedirects in place of its own redirect handler.
    `network` is the tests' stand-in for the network, as urllib handlers."""
    return urllib.request.build_opener(NoRedirects, *network)


def ask(method: str, params: dict[str, str], key: str, asking: urllib.request.OpenerDirector
        ) -> tuple[int, dict[str, str], bytes]:
    """Last.fm's status, kept headers and body for one method - its errors (4xx, 5xx) answered as they came."""
    query = {"method": method, **params, "api_key": key, "format": "json"}
    request = urllib.request.Request(API + "?" + urllib.parse.urlencode(query),
                                     headers={"User-Agent": f"deadwax/{version()} (fixture recorder)",
                                              "Accept": "application/json"})
    try:
        with asking.open(request, timeout=30) as response:
            status, headers, body = response.status, response.headers, response.read()
    except urllib.error.HTTPError as e:
        status, headers, body = e.code, e.headers, e.read()
    kept = {name: headers.get(name) for name in HEADERS_KEPT if headers is not None and headers.get(name) is not None}
    return status, kept, body


def record(name: str, method: str, params: dict[str, str], status: int, headers: dict[str, str], body: bytes,
           key: str) -> str:
    """The file's text, the key out of every part of it."""
    text = body.decode("utf-8", errors="replace")
    try:
        answer = json.loads(text)
    except ValueError:
        answer = text
    written = json.dumps({
        "recorded": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "method": method,
        "params": params,
        "status": status,
        "headers": headers,
        "answer": answer,
    }, indent=1, ensure_ascii=True) + "\n"
    #? ensure_ascii writes a non-ASCII key as escapes, which the plain replace wouldn't find: the escaped form too
    written = without_key(without_key(written, key), json.dumps(key, ensure_ascii=True)[1:-1])
    if key in written:
        raise SystemExit(f"{name}: the key is still in what would be written - nothing written")
    return written


def main(argv: list[str] | None = None, out: Path = OUT, network: tuple = (), pause: float = PAUSE_S,
         environ=os.environ) -> int:
    key = (environ.get("LASTFM_API_KEY") or "").strip()
    if not key:
        print("Set LASTFM_API_KEY first (a free API key from https://www.last.fm/api/account/create).", file=sys.stderr)
        return 2
    wanted = set(argv or [])
    asking = opener(*network)
    out.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    caching: dict[str, set[str]] = {}
    for n, (name, method, params) in enumerate(recordings()):
        if wanted and name not in wanted:
            continue
        if n and pause:
            time.sleep(pause)
        status, headers, body = ask(method, params, key, asking)
        path = out / f"{name}.json"
        path.write_text(record(name, method, params, status, headers, body, key), encoding="ascii")
        written.append(path)
        for header in ("Cache-Control", "Expires"):
            caching.setdefault(header, set()).add(without_key(headers.get(header) or "(none)", key))
        print(f"{status}  {method:<22} {name}")
        if 300 <= status < 400:
            redirected = (status, name, without_key(headers.get("Location") or "(no Location)", key))
            break
    else:
        redirected = None
    leaked = [path.name for path in written if key in path.read_text(encoding="ascii")]
    if leaked:
        for path in written:
            path.unlink()
        print(f"the key was in {', '.join(leaked)} - every file written was removed", file=sys.stderr)
        return 1
    if redirected:
        status, name, location = redirected
        print(f"\nLast.fm answered {name} with a redirect ({status}) to {location}\n"
              f"The recorder follows no redirect - the key is in the address - so it stopped there: {name}.json records "
              f"the redirect, and nothing was asked after it.",
              file=sys.stderr)
        return 3
    print(f"\n{len(written)} answers in {out}, the key in none of them.")
    for header, values in caching.items():
        print(f"{header}: {' | '.join(sorted(values))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
