"""
FLAC songs sent to Safari inside an MP4 - or to the gapless player as a fragmented one - and the
disk cache that makes that affordable.

Why at all: Safari plays <audio> through AVFoundation, which does not land a seek in a FLAC file
where it was asked to - seconds off in an ordinary song, whatever the seek table says, while its
clock reports the time asked for (James saw 3 s and 8 s on his iPhone). The very same frames in
an MP4 land exactly, because an MP4 carries a table of every frame. src/flac_mp4.py does the
repackaging, losslessly and without ffmpeg; this is how the player's stream route gets one. The
page asks for it (`wrap=mp4`) only from WebKit, and only for a FLAC - see ui/src/lib/streamWrap.ts.
Chromium seeks FLAC exactly and keeps getting the file as it is.

How a request is answered (`Mp4Cache.answer()`):

  1. Which version of the file Navidrome has (`_version()`): four bytes of it, as a range, whose
     Content-Range gives the size and whose Last-Modified (and ETag, when there is one) changes
     when the file does. The type and those four bytes also say whether it is FLAC at all.
     Remembered for VERSION_SECONDS, because Safari makes several requests for every song - two
     bytes, then the rest, then a range per seek - and each one asking Navidrome first would be a
     round trip for nothing.
  2. The MP4 made for that version, if the cache has it.
  3. If not, the file is fetched whole, repackaged in a worker thread, written under a temporary
     name and renamed into place, so a half-written file is never served. One make per version
     however many requests want it (single flight), and it is STOPPED - its download from
     Navidrome included - when the last request waiting for it goes: skipping through five songs
     must not leave the fifth waiting on four nobody is listening to. The repackage itself runs
     one at a time, since the whole file is in memory while it does; the downloads don't wait on
     each other.
  4. Served from the cache with byte ranges, which Safari won't play without.

ONE URL, ONE FILE. The element reads each range against what it was sent before, so a URL is
never answered as the FLAC on one request and the MP4 on the next: their bytes and lengths differ,
and a splice of the two is a decode error. So what each song was last answered as is remembered
(`_answered`). A request carrying on from bytes the phone already has - anything but a fresh start,
which is Safari's two-byte probe or the whole file - gets that same container: a song sent as FLAC
stays FLAC, and a song sent as an MP4 is made again and waited for when its MP4 has gone, or
answered 503 when it can't be had, never with FLAC bytes. A fresh start after a FLAC answer stays
FLAC for VERSION_SECONDS too, so the page's readout and the element can't be told different things.

Anything else that goes wrong sends the FLAC, exactly as before this existed: a type that isn't
FLAC, a file too big to hold in memory, a stream the muxer won't vouch for, Navidrome dropping the
download, a disk short of space, a cache folder that can't be used. A song that plays and seeks
badly in Safari beats a song that doesn't play.

THE GAPLESS PLAYER (`answer_fragmented()`, `wrap=fmp4`) plays consecutive FLAC songs as one
MediaSource stream, which takes fragmented MP4 - src/flac_mp4.py's fmp4_layout(). It is made and
kept the same way, beside the MP4s but never sharing one with them: its own key, file (`.f.mp4`),
make and refusals, so an MP4 and a fragmented MP4 of one song are two files, two ETags and two
makes, even at the same moment. What it is never sent is the FLAC - a MediaSource can't take it -
so it gets its own answers instead of `_answered`'s: the fragments with byte ranges; a 415 with the
reason when this version of the song can't be repackaged (the page plays it the ordinary way); a 503
with Retry-After and a `scope` - "song" when asking again in a moment may work, "server" when the
cache can't be used at all, which the page takes as a reason to stop streaming for a while. No
body names a folder: the reasons that do go to the log. And a range asked for with If-Range naming
the fragmented MP4 the song was last served as is answered from it, while the cache has it, without
asking Navidrome anything - so a Navidrome redeploy or a retag in the middle of a song doesn't break
the stream (`_pinned`).

WHERE: PLAYER_CACHE_PATH (asked for, so the cache can live on an SSD), or the container's
temporary space when that is empty - never the config volume, which is what people back up. Either way deadwax keeps to a folder of its own inside it, `deadwax-player`,
which it makes private (0700) and checks is still its own (a real folder, not a link, its owner,
that mode) before anything in it is listed, deleted or served. So the setting can point at a
folder other things share, and a /tmp shared with other users on a machine running from source
can't hand it a folder somebody else planted. Nothing is resolved at import: a read-only root
filesystem with no temporary space means no cache - FLAC for Safari, said once - not a deadwax
that won't start.

HOW MUCH: PLAYER_CACHE_MB of MP4s, a gigabyte by default, least recently served going first. Room
for a song is made BEFORE it is fetched, counting the songs being made as well as those made, so
the MP4s never add up to more than the cap. While a song is made there is a second copy of it on
disk too (the download, beside the MP4 being written), so the folder's peak is the cap plus that
copy. Nor does the cache take the last of the disk: a make needs room for both copies and
DISK_SPARE_BYTES besides, older songs are cleared to find it - none at all when clearing them
couldn't find enough - and a disk that is short even then is a FLAC answer, not a full disk (to the
gapless player, a 503 for that song only, unless the disk is short even for a small one). If the disk fills anyway (something else writing), older songs are
cleared for twice the song and it is tried once more. It is only ever a cache: deleting it is safe,
and costs the next play of each song the wait for its MP4 to be made again. What is never cleared
to make room for a new song is one served in the last IN_USE_SECONDS: that song is being played -
Safari seeks in it, the gapless player fetches its next pieces - and clearing it would have it made
again at once, clearing the new one in turn. The new one waits instead (the gapless player is told
to ask again; Safari gets the FLAC), and a cache trimmed back under its cap clears those songs last.

A retag rewrites a file in place under the same Navidrome id, so the cache is keyed on the
version, never the id alone. Worth knowing when reading that: the MP4 carries only STREAMINFO and
the audio frames, never the tags, so a retag makes the same MP4 again - a wasted repackage, never
a wrong one. It is a file whose AUDIO was replaced that the key has to catch.
"""

import asyncio
import errno
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import tempfile
import time
from dataclasses import dataclass
from email.utils import formatdate
from enum import Enum
from pathlib import Path
from typing import Callable

import httpx
from fastapi import Request
from fastapi.responses import JSONResponse, Response, StreamingResponse
from starlette.background import BackgroundTask

from src.api.navidrome_endpoint import NavidromeError, navidrome
from src.config import Config, player_cache_bytes
from src.flac_mp4 import CannotRepackage, fmp4_layout, mp4_layout
from src.logger import logger

#? The cache's own folder, inside PLAYER_CACHE_PATH or the temporary space. deadwax makes it, and
#? uses nothing else there.
FOLDER_NAME = "deadwax-player"

#? The largest file repackaged. The whole file is held in memory while it is - one at a time, for
#? a second or two - so this bounds what that costs a NAS. It covers every CD-quality song and most
#? hi-res ones; past it (an hour-long single-file rip, 24/192 at length) Safari gets the FLAC.
WRAP_MAX_BYTES = 512 << 20

#? How long what Navidrome said about a song's file is believed without asking again, in seconds.
#? A retag within that time is served from the MP4 of the version before it for at most this long.
#? Also how long a fresh start after a FLAC answer stays FLAC - see the module's docstring.
VERSION_SECONDS = 30

#? Part of every cache key. Bump it whenever src/flac_mp4.py's output changes, so an MP4 made by
#? the old muxer is never served under a new one's name. 2 (1.1.0-player.4): the muxer now refuses
#? files 1 wrapped wrongly - zeros or frames after the audio, a wrong split - and their MP4s,
#? which AVFoundation stops in before the end, mustn't be served from a cache kept since.
FORMAT_VERSION = 2

#? The same for the fragmented MP4s the gapless player streams, apart so that bumping one leaves
#? the other's files valid. Bump it whenever fmp4_layout()'s output changes - CHUNK_SECONDS too,
#? which sizes its fragments. tests/test_flac_mp4.py pins its output by hash to catch that.
FMP4_FORMAT_VERSION = 1

#? What Navidrome calls a FLAC file (resources/mime_types.yaml), and what an older setup might.
FLAC_TYPES = frozenset({"audio/flac", "audio/x-flac"})
MP4_TYPE = "audio/mp4"

#? A file this old in the cache folder that isn't a finished MP4 is left over from a process that
#? stopped part-way, and is cleared the first time the folder is used.
LEFTOVER_SECONDS = 600

#? What the download writes in one go, and what a range is read from disk in.
WRITE_BATCH = 1 << 20
READ_CHUNK = 64 * 1024

#? Versions whose file can't be repackaged, remembered so Safari's next request for the same file
#? doesn't fetch it all again only to fail again. Bounded; the oldest are forgotten first.
REFUSALS_KEPT = 256

#? How many songs' last answer is remembered, to keep each URL on one container. Bounded; the
#? song answered longest ago is forgotten first.
ANSWERS_KEPT = 1024

#? What a make needs on disk while it runs, as a multiple of the song: the file downloaded (.part)
#? and the MP4 written beside it (.tmp, renamed into place). The .part goes once the MP4 is there,
#? so only one of the two counts against the cap - see _make_room().
MAKE_ROOM_FACTOR = 2

#? What the cache leaves free on its disk, whatever its cap. The temporary space is usually the
#? Docker root's filesystem, where other containers' layers and logs live, and filling it to the
#? last byte would be somebody else's failure.
DISK_SPARE_BYTES = 128 << 20

#? A small song, for telling a disk short of room for ONE song (a long one, a hi-res one: the gapless
#? player plays it the ordinary way and streams the rest) from a disk the cache can't use at all
#? (the gapless player stops streaming for a while). About a minute and a half of CD FLAC.
SMALL_SONG_BYTES = 16 << 20

#? How long a phone that can't be sent its MP4 just now is asked to wait before asking again.
RETRY_AFTER_SECONDS = 2

#? How long the gapless player is asked to leave the cache alone when it can't be used at all - no
#? folder it may use, or a disk short even with everything cleared. Neither clears by itself.
SERVER_RETRY_AFTER_SECONDS = 30

#? A file served this recently, in seconds, is a song being played: never cleared to make room for
#? another, and the last to go when the cache is trimmed. A song is served range by range as it
#? plays - Safari's seeks, the gapless player's pieces of a few seconds each - so this is a
#? comfortable margin over the gap between two of them.
IN_USE_SECONDS = 120

#? How many songs' last fragmented MP4 is remembered for If-Range (see answer_fragmented()).
#? Bounded; the song served longest ago is forgotten first.
PINS_KEPT = 1024

#? What a song was last answered as.
MP4, FLAC = "mp4", "flac"

#? What the gapless player is told a 503 is about: this song - ask again in a moment - or the whole
#? cache, which it takes as a reason to stop streaming for a while.
SONG, SERVER = "song", "server"


@dataclass(frozen=True)
class Version:
    """One state of one song's file on Navidrome."""

    song_id: str
    size: int
    #? Last-Modified and ETag, as Navidrome sent them: what changes when the file does. Navidrome
    #? sends its database's UpdatedAt for the first, which moves once its scan has seen a change
    stamp: str

    @property
    def key(self) -> str:
        #? hashed, so what names a file on disk is never the id the caller sent
        material = json.dumps([FORMAT_VERSION, self.song_id, self.size, self.stamp])
        return hashlib.sha256(material.encode("utf-8")).hexdigest()

    def key_for(self, wrap: "Wrap") -> str:
        """The cache key of this version in that container: the MP4's is `key`, unchanged, so the
        MP4s already cached stay valid; the fragmented one's has material of its own."""
        if wrap.name == MP4_WRAP.name:
            return self.key
        material = json.dumps([FMP4_FORMAT_VERSION, wrap.name, self.song_id, self.size, self.stamp])
        return hashlib.sha256(material.encode("utf-8")).hexdigest()


def _total(content_range: str | None) -> int | None:
    """The file's size from a Content-Range of `bytes a-b/N`, or None."""
    if not content_range or "/" not in content_range:
        return None
    try:
        return int(content_range.rsplit("/", 1)[1])
    except ValueError:
        return None


def _media_type(value: str | None) -> str:
    return (value or "").split(";")[0].strip().lower()


#? ASCII digits only: str.isdigit() also takes '²', which int() then refuses
_DIGITS = re.compile(r"[0-9]*")


class Unsatisfiable(Exception):
    """A byte range that starts past the end of the file."""


def byte_range(header: str | None, size: int) -> tuple[int, int] | None:
    """
    The one byte range a Range header asks for, as (first, last) inclusive - or None to send the
    whole file. Raises Unsatisfiable for a range that starts at or past the end.

    RFC 9110 lets a server ignore a Range it doesn't want to answer and send the whole file with a
    200, which is what happens to several ranges at once (no player asks for them), to a unit other
    than bytes, and to anything malformed. A suffix range longer than the file is the whole file
    as a 206, as the RFC says - Starlette's FileResponse refuses that with a 416.
    """
    if not header:
        return None
    unit, _, spec = header.partition("=")
    if unit.strip().lower() != "bytes" or "," in spec:
        return None
    first, dash, last = spec.strip().partition("-")
    first, last = first.strip(), last.strip()
    if not dash or not _DIGITS.fullmatch(first) or not _DIGITS.fullmatch(last):
        return None
    if first == "":
        if last == "":
            return None
        length = int(last)
        if length == 0:
            raise Unsatisfiable()
        return max(0, size - length), size - 1
    start = int(first)
    end = size - 1 if last == "" else min(int(last), size - 1)
    if last != "" and int(last) < start:
        return None
    if start >= size:
        raise Unsatisfiable()
    return start, end


def continues(header: str | None) -> bool:
    """
    Whether a request carries on from bytes of this URL the phone already has, rather than starting
    it afresh. Safari starts every song with its first two bytes (`bytes=0-1`), and no Range at all
    is the whole file (the gapless switch's download); anything else - the rest after the probe, a
    seek - is read against what came before, so it has to come from the same file. A Range the
    route would ignore (another unit, several ranges) is answered whole, so it is a start too.
    """
    if not header:
        return False
    unit, _, spec = header.partition("=")
    if unit.strip().lower() != "bytes" or "," in spec:
        return False
    return spec.replace(" ", "") != "0-1"


def _open_cached(path: Path):
    """A cached MP4, opened for reading - never through a link, which nothing of deadwax's makes."""
    return os.fdopen(os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)), "rb")


async def ranged_file(path: Path, request: Request, etag: str) -> Response:
    """
    A file from the cache, whole or as the byte range asked for, as audio/mp4.

    Not Starlette's FileResponse, which was read (0.50) before deciding: its 416 says
    `Content-Range: */N` without the unit RFC 9110 requires, it refuses a suffix range longer than
    the file, and it stats the file only once it is sending - by which time the cache may have
    evicted it, which would surface as a 500. Here the file is opened first, so an eviction after
    that can't touch what is being sent (an open file outlives its name), and FileNotFoundError
    reaches the caller while it can still make it again.

    If-Range is honoured against the ETag (strongly - a weak tag never matches) and the
    Last-Modified: a range asked for against any other version gets the whole file, which is how a
    seek never splices two versions of a song together.
    """
    handle = await asyncio.to_thread(_open_cached, path)
    try:
        info = os.fstat(handle.fileno())
    except OSError:
        handle.close()
        raise
    size = info.st_size
    last_modified = formatdate(info.st_mtime, usegmt=True)
    headers = {
        "accept-ranges": "bytes",
        "etag": etag,
        "last-modified": last_modified,
        #? the same as a stream relayed from Navidrome: a cached copy is asked about, never trusted
        "cache-control": "no-cache",
    }

    try:
        wanted = byte_range(request.headers.get("range"), size)
    except Unsatisfiable:
        handle.close()
        return Response(status_code=416, headers={**headers, "content-range": f"bytes */{size}"})
    if_range = request.headers.get("if-range")
    if wanted is not None and if_range is not None and if_range not in (etag, last_modified):
        wanted = None

    start, end = wanted if wanted is not None else (0, size - 1)
    if wanted is not None:
        headers["content-range"] = f"bytes {start}-{end}/{size}"
    headers["content-length"] = str(end - start + 1)

    async def body():
        try:
            await asyncio.to_thread(handle.seek, start)
            left = end - start + 1
            while left > 0:
                chunk = await asyncio.to_thread(handle.read, min(READ_CHUNK, left))
                if not chunk:
                    break
                left -= len(chunk)
                yield chunk
        finally:
            handle.close()

    return StreamingResponse(
        body(), status_code=206 if wanted is not None else 200, headers=headers, media_type=MP4_TYPE,
        #? a client that leaves before the first chunk never starts the generator, so its finally
        #? never runs - this closes the file in that case too
        background=BackgroundTask(handle.close),
    )


def _mp4_pieces(data: bytes) -> list:
    """The MP4 of `data` as what is written, in order: the muxer's head, then the FLAC's frames as
    a slice of the file already in memory (mp4_layout())."""
    head, start, end = mp4_layout(data)
    return [head, memoryview(data)[start:end]]


def _fmp4_pieces(data: bytes) -> list:
    """The fragmented MP4 of `data` the same way: the head, then each fragment's moof and mdat
    header and its frames, a slice of the file (fmp4_layout())."""
    head, fragments = fmp4_layout(data)
    view = memoryview(data)
    pieces = [head]
    for header, start, end in fragments:
        pieces += (header, view[start:end])
    return pieces


@dataclass(frozen=True)
class Wrap:
    """One container a FLAC is repackaged into: its own files, keys, makes and refusals, and its
    own words for the log - what happens instead of it is different for each."""

    #? in its cache key: what keeps the two containers' keys, makes and refusals apart
    name: str
    #? the end of its files' names - both end in ".mp4", which is what the cap, the eviction and
    #? the clean-up of leftovers count as a finished file
    suffix: str
    #? for the log: "putting song X in <noun>", "song X put in <made>"
    noun: str
    made: str
    #? what the request gets when it can't be had just now, and when the cache can't be used
    instead: str
    no_cache: str
    #? how the file is laid out: _mp4_pieces or _fmp4_pieces
    pieces: Callable[[bytes], list]


MP4_WRAP = Wrap("mp4", ".mp4", "an MP4", "an MP4 for Safari", "it is sent as FLAC", "it is sent as FLAC",
                _mp4_pieces)
FMP4_WRAP = Wrap("fmp4", ".f.mp4", "a fragmented MP4", "a fragmented MP4 for the gapless player",
                 "the gapless player is asked to try again", "the gapless player is told the cache can't be used",
                 _fmp4_pieces)


def _repackage(part: Path, target: Path, pieces: Callable[[bytes], list]) -> int:
    """
    The FLAC at `part` written out at `target` in the container `pieces` lays out (a Wrap's), under
    a temporary name first, so a half-written file is never there to be served. Runs in a worker
    thread. Returns its size.

    Every piece is the muxer's own header bytes or a slice of the FLAC already in memory, so the
    file is held once, not twice - and the layout is worked out before anything is written, so a
    file the muxer refuses leaves nothing behind.
    """
    data = part.read_bytes()
    parts = pieces(data)
    temporary = target.with_name(f"{target.stem}.{secrets.token_hex(4)}.tmp")
    try:
        with open(temporary, "wb") as out:
            for piece in parts:
                out.write(piece)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return sum(len(piece) for piece in parts)


def _etag(key: str) -> str:
    return f'"{key[:32]}"'


def _refusal(reason: str) -> Response:
    """The gapless player's answer for a song this version of which can't be repackaged: 415, and
    why - which it doesn't ask for again, and plays the ordinary way."""
    return JSONResponse({"detail": reason}, status_code=415, headers={"cache-control": "no-store"})


def _unavailable(scope: str, detail: str) -> Response:
    """The gapless player's answer when a song can't be had just now: 503, whether it is this song's
    trouble or the cache's, and when to ask again. `detail` never names a folder."""
    wait = RETRY_AFTER_SECONDS if scope == SONG else SERVER_RETRY_AFTER_SECONDS
    return JSONResponse({"detail": detail, "scope": scope}, status_code=503,
                        headers={"retry-after": str(wait), "cache-control": "no-store"})


async def _to_the_end(work):
    """
    A worker thread's result, waited for to its end even when whatever awaits it is cancelled
    meanwhile - and then the cancellation carried on. A thread can't be stopped, and the gate it
    runs under has to stay held until it is done, or a second song could be held in memory beside
    it.
    """
    job = asyncio.ensure_future(work)
    try:
        return await asyncio.shield(job)
    except asyncio.CancelledError:
        while not job.done():
            try:
                await asyncio.wait({job})
            except asyncio.CancelledError:
                pass
        raise


# ---------------------------------------------------------------- the cache's own folder

def _base(configured: str | None) -> tuple[Path | None, str | None]:
    """The folder the cache's own goes inside - PLAYER_CACHE_PATH, else the temporary space - or why none."""
    configured = (configured or "").strip()
    if configured:
        return Path(configured), None
    try:
        #? raises when no candidate is writable: a read-only root filesystem with no tmpfs
        return Path(tempfile.gettempdir()), None
    except OSError:
        return None, ("this container has no writable temporary space (a read-only root filesystem?), "
                      "and PLAYER_CACHE_PATH isn't set - set it to a folder deadwax can write to")


def _judge(folder: Path) -> str | None:
    """
    Why `folder` isn't one deadwax can keep its cache in, or None when it is: a real folder, not a
    link, owned by the user deadwax runs as, and private to it (no group or other permission bits).
    Read with lstat, so a link planted in its place is seen as a link. The owner rules out a folder
    somebody else made first in a shared /tmp; the mode, one that anybody could have put files in.
    Only the PERMISSION bits count: OpenMediaVault sets setgid on every shared folder and Linux's
    mkdir passes it on to a folder made inside, so the folder deadwax makes there is 02700 - which
    gives nobody else anything. Judging the whole mode refused exactly that, on every song.
    """
    try:
        info = os.lstat(folder)
    except OSError as e:
        return f"{folder} can't be looked at ({e.strerror or e})"
    if stat.S_ISLNK(info.st_mode):
        return f"{folder} is a link, not a folder deadwax made"
    if not stat.S_ISDIR(info.st_mode):
        return f"{folder} is a file, not a folder"
    if info.st_uid != os.getuid():
        return (f"{folder} belongs to another user (uid {info.st_uid}; deadwax runs as {os.getuid()}) - "
                f"remove it, and deadwax makes its own")
    mode = stat.S_IMODE(info.st_mode)
    if mode & 0o077:
        return (f"{folder} is open to other users (mode {mode & 0o777:o}, where deadwax makes it 700) - "
                f"remove it, and deadwax makes it again")
    if not os.access(folder, os.W_OK | os.X_OK):
        return f"{folder} can't be written to"
    return None


def _own(folder: Path) -> tuple[Path | None, str | None]:
    """`folder`, made private if it isn't there, once it has been checked - or None and why not."""
    try:
        os.mkdir(folder, 0o700)
    except FileExistsError:
        made = False
    except OSError as e:
        return None, f"{folder} couldn't be made ({e.strerror or e})"
    else:
        made = True
        #? what deadwax has just made is its own to set: this drops a setgid bit inherited from the
        #? folder above (OpenMediaVault's shared folders have one), and a folder it didn't make is
        #? never touched
        try:
            os.chmod(folder, 0o700)
        except OSError:
            pass
    problem = _judge(folder)
    if problem and made and stat.S_IMODE(os.lstat(folder).st_mode) & 0o077:
        #? made 0700 and chmodded, yet open: the filesystem keeps no modes of its own, and removing
        #? the folder would only bring it back the same way
        return None, (f"{folder} can't be made private: the disk it is on doesn't keep file permissions "
                      f"(CIFS, NTFS or exFAT, say) - point PLAYER_CACHE_PATH at a Linux-formatted disk")
    return (None, problem) if problem else (folder, None)


def open_folder(configured: str | None) -> tuple[Path | None, str | None]:
    """The cache's own folder under this PLAYER_CACHE_PATH, made and checked - or None and why not."""
    base, problem = _base(configured)
    if base is None:
        return None, problem
    if (configured or "").strip() and not base.is_dir():
        return None, f"PLAYER_CACHE_PATH, {base}, isn't a folder this container can see"
    return _own(base / FOLDER_NAME)


def folder_problem(configured: str | None) -> str | None:
    """
    For the settings tab: why the cache couldn't use its folder under this PLAYER_CACHE_PATH, or
    None when it can - without making anything. A folder not there yet is made on first use.
    Whether a configured folder exists and can be written to is the Paths row's own check.
    """
    base, problem = _base(configured)
    if base is None:
        return problem
    folder = base / FOLDER_NAME
    if not os.path.lexists(folder):
        if not (configured or "").strip() and not os.access(base, os.W_OK | os.X_OK):
            return f"the temporary space, {base}, can't be written to"
        return None
    return _judge(folder)


def _is_cached(path: Path) -> bool:
    """A finished MP4 is there under this name - a file, never a link."""
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except OSError:
        return False


# ---------------------------------------------------------------- the cache

class _Make:
    """A make under way, and how many requests are waiting for it."""

    def __init__(self, task: asyncio.Task):
        self.task = task
        self.waiters = 0


class Room(Enum):
    """What `_make_room()` found. Only MADE is true, so `if not room` reads as it says."""

    MADE = "made"
    #? the disk can't take even a small song with every song cleared off it: the cache can't be used
    DISK = "disk"
    #? the disk can't take THIS song with every song cleared off it - others still fit
    SHORT = "short"
    #? room only by clearing a song being played, or the songs being made fill the cap themselves:
    #? it passes once they have played or been made
    BUSY = "busy"

    def __bool__(self) -> bool:
        return self is Room.MADE


class Mp4Cache:
    """The repackaged songs on disk, and what is known about the versions they were made from."""

    def __init__(self, directory: Path | None = None, max_bytes: int | None = None,
                 wrap_max_bytes: int = WRAP_MAX_BYTES):
        #? A folder given here is used exactly (tests); otherwise it is PLAYER_CACHE_PATH's, read at
        #? every request, and the cap PLAYER_CACHE_MB's - so the settings tab changes both live
        self._fixed = Path(directory) if directory is not None else None
        self._max_bytes = max_bytes
        self.wrap_max_bytes = wrap_max_bytes
        #? song id -> (believed until, on the monotonic clock; its version, or None: not one to wrap)
        self._versions: dict[str, tuple[float, Version | None]] = {}
        #? song id -> why its version is None there, for the gapless player's 415
        self._why_not: dict[str, str] = {}
        #? cache key (each container's own) -> the make under way for it
        self._working: dict[str, _Make] = {}
        #? cache key -> why it can't be repackaged, oldest first
        self._refused: dict[str, str] = {}
        #? song id -> (MP4 or FLAC, when, on the monotonic clock) - what it was last answered as,
        #? the song answered longest ago first. The MP4 path's alone: the gapless player is never
        #? sent FLAC, so it neither reads nor writes this
        self._answered: dict[str, tuple[str, float]] = {}
        #? song id -> the key of the fragmented MP4 it was last served as, the song served longest ago
        #? first - what an If-Range naming that file is answered from without asking Navidrome
        self._pinned: dict[str, str] = {}
        #? file name -> when it was last served (wall_clock()). A file not here - one made before a
        #? restart - counts as used when it was made. Kept apart from the file's own times, because
        #? its mtime is its Last-Modified: touching it would change the validator under a seek.
        self._used: dict[str, float] = {}
        #? bytes of the cap the makes under way have claimed - the MP4 each will add
        self._reserved = 0
        #? folders whose leftovers have been cleared; the folder last used; the problem last said
        self._prepared: set[Path] = set()
        self._using: Path | None = None
        self._said: str | None = None
        #? what VERSION_SECONDS is measured on - a test moves it on rather than waiting
        self.clock = time.monotonic
        #? what `_used` and IN_USE_SECONDS are measured on - the wall clock, since a file made before
        #? a restart counts by its mtime - and a test moves on the same way
        self.wall_clock = time.time
        #? one repackage at a time, made for the event loop that uses it
        self._gate_loop: asyncio.AbstractEventLoop | None = None
        self._gate_lock: asyncio.Lock | None = None

    @property
    def directory(self) -> Path | None:
        """The folder the cache uses under the settings as they are now - made and checked only when used."""
        if self._fixed is not None:
            return self._fixed
        base, _ = _base(Config.PLAYER_CACHE_PATH)
        return base / FOLDER_NAME if base is not None else None

    @property
    def max_bytes(self) -> int:
        return self._max_bytes if self._max_bytes is not None else player_cache_bytes()

    def _gate(self) -> asyncio.Lock:
        loop = asyncio.get_running_loop()
        if self._gate_loop is not loop:
            self._gate_loop, self._gate_lock = loop, asyncio.Lock()
        return self._gate_lock

    def path_for(self, version: Version, wrap: Wrap = MP4_WRAP) -> Path:
        return self.directory / f"{version.key_for(wrap)[:40]}{wrap.suffix}"

    @staticmethod
    def etag_for(version: Version, wrap: Wrap = MP4_WRAP) -> str:
        return _etag(version.key_for(wrap))

    async def answer(self, song_id: str, request: Request) -> Response | None:
        """
        The song as an MP4, with the request's byte range - or None, and the caller sends the FLAC
        as it is - or a 503, for a request carrying on from an MP4 that can't be had just now (see
        the module's docstring). NavidromeError is raised as it would be for the FLAC: a song
        Navidrome doesn't have, a login it refuses, a Navidrome that isn't there.

        Cancelling it (the route does when the phone hangs up) takes this request off the make it
        waits for, and a make nobody waits for any more stops.
        """
        carrying_on = continues(request.headers.get("range"))
        last = self._answered.get(song_id)
        if last is not None and last[0] == FLAC and (carrying_on or self.clock() - last[1] < VERSION_SECONDS):
            return self._as_flac(song_id)

        folder = await self._folder()
        if folder is None:
            return self._instead(song_id, carrying_on, "the player's cache has nowhere to go")
        try:
            version = await self._version(song_id)
        except httpx.TransportError:
            return self._instead(song_id, carrying_on, "Navidrome broke off saying which file it has")
        if version is None:
            return self._as_flac(song_id)
        if version.size > self.wrap_max_bytes:
            self._refuse(version, self._too_big(version), warn=False)
            return self._as_flac(song_id)

        for _ in range(2):
            path = await self._mp4(version, folder)
            if not isinstance(path, Path):
                break
            try:
                response = await ranged_file(path, request, self.etag_for(version))
            except FileNotFoundError:
                #? cleared out between being found and being opened: made again, and waited for
                continue
            except OSError as e:
                logger.warning(f"player: the MP4 of song {song_id} couldn't be opened ({e})")
                break
            self._mark(song_id, MP4)
            return response
        return self._instead(song_id, carrying_on, "its MP4 couldn't be made again just now")

    async def answer_fragmented(self, song_id: str, request: Request) -> Response:
        """
        The song as a fragmented MP4 for the gapless player, with the request's byte range - always
        an answer of its own, never the FLAC, which a MediaSource can't take (see the module's
        docstring for the answers). NavidromeError is raised as for the FLAC: a song Navidrome
        doesn't have, a login it refuses, a Navidrome that isn't there.

        Cancelling it (the route does when the phone hangs up) takes this request off the make it
        waits for, and a make nobody waits for any more stops - as for the MP4.
        """
        folder = await self._folder()
        if folder is None:
            return _unavailable(SERVER, "the player's cache can't be used on this server just now")
        pinned = await self._pinned_answer(song_id, folder, request)
        if pinned is not None:
            return pinned
        try:
            version = await self._version(song_id)
        except httpx.TransportError:
            logger.warning(f"player: Navidrome broke off saying which file song {song_id} has; "
                           f"{FMP4_WRAP.instead}")
            return _unavailable(SONG, "Navidrome broke off saying which file it has")
        if version is None:
            return _refusal(self._why_not.get(song_id) or "it isn't a FLAC file")
        if version.size > self.wrap_max_bytes:
            return _refusal(self._refuse(version, self._too_big(version), warn=False, wrap=FMP4_WRAP))

        key = version.key_for(FMP4_WRAP)
        got: Path | Room | None = None
        for _ in range(2):
            got = await self._mp4(version, folder, FMP4_WRAP)
            if not isinstance(got, Path):
                break
            try:
                response = await ranged_file(got, request, _etag(key))
            except FileNotFoundError:
                #? cleared out between being found and being opened: made again, and waited for
                continue
            except OSError as e:
                logger.warning(f"player: the fragmented MP4 of song {song_id} couldn't be opened ({e})")
                got = None
                break
            self._pin(song_id, key)
            return response
        if key in self._refused:
            return _refusal(self._refused[key])
        if got is Room.DISK:
            return _unavailable(SERVER, "the disk holding the player's cache is short of space")
        if got is Room.SHORT:
            return _unavailable(SONG, "the disk holding the player's cache is short of space for this song")
        if got is Room.BUSY:
            return _unavailable(SONG, "the player's cache has no room for it until the songs being played or "
                                      "made are done")
        return _unavailable(SONG, "its fragmented MP4 couldn't be made just now")

    async def _pinned_answer(self, song_id: str, folder: Path, request: Request) -> Response | None:
        """
        A request whose If-Range names the fragmented MP4 this song was last served as, answered
        from that file while the cache still has it - WITHOUT asking Navidrome which version it has.
        None, and the ordinary way, for anything else.

        The page streams a song as ranges of one file, each carrying that file's ETag as If-Range,
        and the ordinary way asks Navidrome again every VERSION_SECONDS. Then a Navidrome being
        redeployed would fail the rest of the song though every byte is here, and a retag - a new
        stamp, so a new key and ETag, for identical audio - would answer the next range with the
        whole file, which the page must take for the song having changed under it. Carrying on
        from the file it has been reading is right either way: it is the very bytes it has been
        sent. Once the file is gone the ordinary way asks Navidrome, and a version that changed
        meanwhile answers If-Range with the whole file, as it should.
        """
        key = self._pinned.get(song_id)
        if key is None or request.headers.get("if-range") != _etag(key):
            return None
        path = folder / f"{key[:40]}{FMP4_WRAP.suffix}"
        if not await asyncio.to_thread(_is_cached, path):
            return None
        try:
            response = await ranged_file(path, request, _etag(key))
        except OSError:
            #? cleared out since it was found: the ordinary way makes it again
            return None
        self._used[path.name] = self.wall_clock()
        self._pin(song_id, key)
        return response

    def _pin(self, song_id: str, key: str) -> None:
        self._pinned.pop(song_id, None)
        self._pinned[song_id] = key
        while len(self._pinned) > PINS_KEPT:
            del self._pinned[next(iter(self._pinned))]

    def _too_big(self, version: Version) -> str:
        return (f"it is {version.size >> 20} MiB, more than the {self.wrap_max_bytes >> 20} MiB a song is "
                f"held in memory to repackage")

    def _mark(self, song_id: str, container: str) -> None:
        self._answered.pop(song_id, None)
        self._answered[song_id] = (container, self.clock())
        while len(self._answered) > ANSWERS_KEPT:
            del self._answered[next(iter(self._answered))]

    def _as_flac(self, song_id: str) -> None:
        self._mark(song_id, FLAC)
        return None

    def _instead(self, song_id: str, carrying_on: bool, why: str) -> Response | None:
        """
        What a request gets when its MP4 can't be had: the FLAC - unless it carries on from an MP4
        this URL was answered with, where FLAC bytes under another length would be spliced into what
        the phone already has. That gets a 503, and the page's own retry starts the song afresh.
        """
        last = self._answered.get(song_id)
        if carrying_on and last is not None and last[0] == MP4:
            logger.warning(f"player: song {song_id} was being played as an MP4, and {why}; Safari is "
                           f"asked to try again rather than sent the FLAC, whose bytes aren't the MP4's")
            return Response(status_code=503, headers={"retry-after": str(RETRY_AFTER_SECONDS),
                                                      "cache-control": "no-store"})
        return self._as_flac(song_id)

    async def _folder(self) -> Path | None:
        """The folder to keep MP4s in now, made and checked, or None - said once - when there is none."""
        if self._fixed is not None:
            folder, problem = await asyncio.to_thread(_own, self._fixed)
        else:
            folder, problem = await asyncio.to_thread(open_folder, Config.PLAYER_CACHE_PATH)
        if folder is None:
            if problem != self._said:
                self._said = problem
                logger.warning(f"player: the player's cache can't be kept - {problem}. Until that is fixed "
                               f"Safari is sent FLAC, not MP4s, so its seeks can land seconds off, and the "
                               f"gapless player doesn't stream")
            return None
        self._said = None
        if folder != self._using:
            if self._using is not None:
                #? the names in it are the old folder's
                self._used.clear()
            self._using = folder
            logger.info(f"player: the MP4s made for Safari and for the gapless player are kept in {folder}, "
                        f"{self.max_bytes >> 20} MB at most")
        return folder

    async def _version(self, song_id: str) -> Version | None:
        """
        What Navidrome has for this song now, or None when it isn't a FLAC this can wrap. Four bytes
        that Navidrome breaks off raise httpx.TransportError, and nothing is remembered.
        """
        now = self.clock()
        remembered = self._versions.get(song_id)
        if remembered and remembered[0] > now:
            return remembered[1]

        looked = await self._look(song_id)
        version = looked if isinstance(looked, Version) else None
        #? the expired go whenever anything is added, so this never grows past what was asked lately
        self._versions = {key: value for key, value in self._versions.items() if value[0] > now}
        self._versions[song_id] = (now + VERSION_SECONDS, version)
        self._why_not = {key: value for key, value in self._why_not.items() if key in self._versions}
        if version is None:
            self._why_not[song_id] = looked
        else:
            self._why_not.pop(song_id, None)
        return version

    async def _look(self, song_id: str) -> Version | str:
        """
        Four bytes of the file: its version, or why it isn't a FLAC this can wrap. A file too big to
        hold is a version still - each container says so in its own words.
        """
        try:
            upstream = await navidrome.open("stream", {"id": song_id, "format": "raw"},
                                            {"range": "bytes=0-3"})
        except NavidromeError as e:
            #? a 416 is an EMPTY file - an answer about the four bytes asked for here, not about
            #? anything Safari asked; the FLAC path answers Safari's own range
            if e.status == 416:
                return "the file is empty"
            raise
        first = b""
        try:
            #? a 200 would be the whole file, sent by something that ignored the range: not read
            if upstream.status_code != 206:
                return "Navidrome didn't answer a range of the file"
            if _media_type(upstream.headers.get("content-type")) not in FLAC_TYPES:
                return "it isn't a FLAC file"
            async for chunk in upstream.aiter_raw():
                first += chunk
                if len(first) >= 4:
                    break
        finally:
            await upstream.aclose()

        size = _total(upstream.headers.get("content-range"))
        if size is None:
            return "Navidrome didn't say how big the file is"
        #? the bytes as well as the type: 'fLaC', or an ID3 tag some taggers put in front of it
        if not (first.startswith(b"fLaC") or first.startswith(b"ID3")):
            return "its first bytes aren't a FLAC file's"
        stamp = json.dumps([upstream.headers.get("last-modified"), upstream.headers.get("etag")])
        return Version(song_id=song_id, size=size, stamp=stamp)

    def _refuse(self, version: Version, reason: str, warn: bool = True, wrap: Wrap = MP4_WRAP) -> str:
        """Remember that this version can't be wrapped in that container, and say so the first
        time. Returns the reason remembered."""
        key = version.key_for(wrap)
        if key in self._refused:
            return self._refused[key]
        self._refused[key] = reason
        while len(self._refused) > REFUSALS_KEPT:
            del self._refused[next(iter(self._refused))]
        say = logger.warning if warn else logger.info
        if wrap is MP4_WRAP:
            say(f"player: song {version.song_id} is sent to Safari as FLAC, not in an MP4 - {reason}. "
                f"It plays, but Safari's seeks in it can land seconds off")
        else:
            say(f"player: song {version.song_id} isn't streamed by the gapless player - it can't be put in "
                f"{wrap.noun}: {reason}. The player plays it the ordinary way")
        return reason

    async def _mp4(self, version: Version, folder: Path, wrap: Wrap = MP4_WRAP) -> Path | Room | None:
        """
        The cached file of this version in that container, made if it isn't there. Otherwise why
        not: the Room there was no room of, or None - refused (in `_refused`) or failed.
        """
        key = version.key_for(wrap)
        path = folder / f"{key[:40]}{wrap.suffix}"
        if await asyncio.to_thread(_is_cached, path):
            self._used[path.name] = self.wall_clock()
            return path
        if key in self._refused:
            return None

        #? keyed on the container's own key: an MP4 and a fragmented MP4 of one song are two makes
        make = self._working.get(key)
        if make is None:
            make = _Make(asyncio.ensure_future(self._make(version, path, wrap)))
            self._working[key] = make

            def finished(done: asyncio.Task, key: str = key, this: _Make = make) -> None:
                if self._working.get(key) is this:
                    del self._working[key]
                if not done.cancelled():
                    done.exception()  # retrieved, so an abandoned make's error is never "never retrieved"

            make.task.add_done_callback(finished)

        make.waiters += 1
        try:
            #? shielded: one request hanging up mustn't cancel a make another is waiting on
            return await asyncio.shield(make.task)
        finally:
            make.waiters -= 1
            if make.waiters == 0 and not make.task.done():
                #? Nobody waits for it any more - Safari skipped on, the gapless download was let go,
                #? the gapless player moved on - so it stops, download and all. A request for it
                #? after this starts afresh.
                if self._working.get(key) is make:
                    del self._working[key]
                make.task.cancel()

    async def _make(self, version: Version, path: Path, wrap: Wrap) -> Path | Room | None:
        """
        Fetch, repackage, store. Never raises but for being cancelled: every way it can fail is
        logged here, and answers the Room there wasn't, or None - so the MP4's request is sent the
        FLAC instead, and the gapless player its own answer.
        """
        folder = path.parent
        what = f"song {version.song_id}"
        part = folder / f"{path.stem}.{secrets.token_hex(4)}.part"
        self._reserved += version.size
        try:
            await asyncio.to_thread(self._prepare, folder)
            if await asyncio.to_thread(_is_cached, path):
                return path
            room = await asyncio.to_thread(self._make_room, folder, version.size)
            if room is Room.DISK:
                logger.warning(f"player: {what} isn't put in {wrap.made} - the disk holding the cache ({folder}) "
                               f"is short of space even with older songs cleared out of it; {wrap.no_cache}")
                return room
            if room is Room.SHORT:
                logger.warning(f"player: {what} isn't put in {wrap.made} - the disk holding the cache ({folder}) "
                               f"is short of space for a song its size ({version.size >> 20} MiB), even with "
                               f"older songs cleared out of it; {wrap.instead}")
                return room
            if not room:
                logger.warning(f"player: {what} isn't put in {wrap.made} just now - the cache has room for it "
                               f"only by clearing a song being played, or the songs being made fill it "
                               f"(PLAYER_CACHE_MB may be small for the songs played at once); {wrap.instead}")
                return room

            fetched = False
            for attempt in (1, 2):
                try:
                    if not fetched:
                        if not await self._download(version, part, wrap):
                            return None
                        fetched = True
                    began = time.monotonic()
                    async with self._gate():
                        size = await _to_the_end(asyncio.to_thread(_repackage, part, path, wrap.pieces))
                    break
                except OSError as e:
                    if e.errno != errno.ENOSPC or attempt == 2:
                        raise
                    #? something else filled the disk since room was made: older songs go, and once more
                    freed = await asyncio.to_thread(self._clear, folder, MAKE_ROOM_FACTOR * version.size,
                                                    path.name)
                    logger.info(f"player: the disk holding the cache filled up while {what} was being put in "
                                f"{wrap.noun}; {freed >> 20} MiB of songs played longest ago were cleared, and it "
                                f"is tried once more")

            took = (time.monotonic() - began) * 1000
            logger.info(f"player: {what} put in {wrap.made} ({size >> 10} KiB, repackaged in {took:.0f} ms)")
            self._used[path.name] = self.wall_clock()
            #? room was made for the FLAC's size; the file made can be a little bigger (an MP4's boxes)
            await asyncio.to_thread(self._evict, folder, path.name, max(0, size - version.size))
            return path
        except CannotRepackage as e:
            self._refuse(version, f"its FLAC stream couldn't be repackaged with certainty ({e})", wrap=wrap)
            return None
        except asyncio.CancelledError:
            logger.info(f"player: putting {what} in {wrap.noun} was stopped - nobody was waiting for it any more")
            raise
        except OSError as e:
            #? the disk: full, unwritable, the folder gone - the FLAC still plays
            logger.warning(f"player: {what} couldn't be put in {wrap.made} ({e}); {wrap.instead}")
            return None
        except Exception:
            logger.exception(f"player: putting {what} in {wrap.made} failed; {wrap.instead}")
            return None
        finally:
            self._reserved -= version.size
            await asyncio.to_thread(part.unlink, missing_ok=True)

    async def _download(self, version: Version, part: Path, wrap: Wrap) -> bool:
        """The whole file into `part`, exactly the version looked at. False, and said, otherwise."""
        what = f"song {version.song_id}"
        try:
            upstream = await navidrome.open("stream", {"id": version.song_id, "format": "raw"})
        except NavidromeError as e:
            logger.warning(f"player: {what} couldn't be fetched to put in {wrap.noun} ({e}); {wrap.instead}")
            return False
        out = None
        try:
            declared = upstream.headers.get("content-length")
            #? a length is checked when there is one; the bytes are counted either way, below
            if upstream.status_code != 200 or (declared is not None and declared != str(version.size)):
                #? changed since it was looked at: the next request looks again and wraps that
                self._versions.pop(version.song_id, None)
                logger.info(f"player: {what} changed while it was being put in {wrap.noun}; {wrap.instead}, "
                            f"and the next request looks at it again")
                return False
            out = await asyncio.to_thread(open, part, "wb")
            received, batch = 0, []
            held = 0
            async for chunk in upstream.aiter_raw():
                received += len(chunk)
                if received > version.size:
                    self._versions.pop(version.song_id, None)
                    return False
                batch.append(chunk)
                held += len(chunk)
                if held >= WRITE_BATCH:
                    await asyncio.to_thread(out.write, b"".join(batch))
                    batch, held = [], 0
            if batch:
                await asyncio.to_thread(out.write, b"".join(batch))
            if received != version.size:
                logger.warning(f"player: Navidrome sent {received} of {version.size} bytes of {what} "
                               f"and stopped; {wrap.instead}")
                return False
            return True
        except httpx.TransportError as e:
            logger.warning(f"player: Navidrome stopped sending {what} while it was being fetched to put "
                           f"in {wrap.noun} ({str(e) or type(e).__name__}); {wrap.instead}")
            return False
        finally:
            if out is not None:
                await asyncio.to_thread(out.close)
            await upstream.aclose()

    def _prepare(self, folder: Path) -> None:
        """What a process that stopped part-way left in the folder, cleared the first time it is used."""
        if folder in self._prepared:
            return
        self._prepared.add(folder)
        stale = time.time() - LEFTOVER_SECONDS
        with os.scandir(folder) as entries:
            for entry in entries:
                try:
                    if (not entry.name.endswith(".mp4") and entry.is_file(follow_symlinks=False)
                            and entry.stat(follow_symlinks=False).st_mtime < stale):
                        os.unlink(entry.path)
                except OSError:
                    pass

    def _entries(self, folder: Path) -> list[tuple[float, str, int]]:
        """The finished MP4s in the folder, plain and fragmented, as (last served, name, size), played
        longest ago first."""
        found = []
        with os.scandir(folder) as entries:
            for entry in entries:
                if not entry.name.endswith(".mp4"):
                    continue
                try:
                    info = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISREG(info.st_mode):
                    found.append((self._used.get(entry.name, info.st_mtime), entry.name, info.st_size))
        return sorted(found)

    def _drop(self, folder: Path, name: str) -> bool:
        """One MP4 out of the cache. A file being served is unaffected: an open file outlives its name."""
        try:
            os.unlink(folder / name)
        except FileNotFoundError:
            pass
        except OSError:
            return False
        self._used.pop(name, None)
        return True

    def _make_room(self, folder: Path, size: int) -> Room:
        """
        Room for a song of `size` bytes about to be made, by clearing the songs played longest ago:
        its file within the cap beside those made and those being made, and both its copies on the
        disk with DISK_SPARE_BYTES to spare.

        Never by clearing a song served in the last IN_USE_SECONDS - one being played, whose next
        range would only make it again, clearing this one in turn: Room.BUSY when nothing else would
        do, as when the songs being made fill the cap by themselves. Room.DISK when the disk can't
        take even a small song with every song cleared, those included; Room.SHORT when it can take
        others but not this one - and then nothing is cleared, since clearing couldn't find enough.
        Past the cap it goes only as the one way this allows: a song too big for what is left of it,
        with nothing being played kept beside it, goes past by that one song at most.
        """
        entries = self._entries(folder)
        now = self.wall_clock()
        held = sum(length for _, _, length in entries)
        playing = sum(length for served, _, length in entries if now - served < IN_USE_SECONDS)
        others = self._reserved - size
        cap = self.max_bytes
        need = MAKE_ROOM_FACTOR * size + DISK_SPARE_BYTES
        try:
            free = shutil.disk_usage(folder).free
        except OSError:
            free = None
        if free is not None:
            #? short even for a small song (or this one, when it is smaller) with everything cleared
            if free + held < MAKE_ROOM_FACTOR * min(size, SMALL_SONG_BYTES) + DISK_SPARE_BYTES:
                return Room.DISK
            clearable = held - playing
            if free + clearable < need:
                #? every song not being played cleared wouldn't be enough: none is, for nothing
                return Room.BUSY if free + held >= need else Room.SHORT

        def fits() -> bool:
            return (free is None or free >= need) and held + others + size <= cap

        #? not `size`: fits() reads that, the song's own, and a loop rebinding it judged every song
        #? against the one about to be cleared instead
        for served, name, cleared in entries:
            if fits() or now - served < IN_USE_SECONDS:
                #? played longest ago first, so every song from here on is being played too
                break
            if self._drop(folder, name):
                held -= cleared
                if free is not None:
                    free += cleared
        if fits():
            return Room.MADE
        if free is not None and free < need:
            #? a song that wouldn't go (a file held open elsewhere): what the rest could have freed
            return Room.BUSY if free + playing >= need else Room.SHORT
        if playing:
            #? over the cap with them kept, and getting back under it would clear one of them
            return Room.BUSY
        return Room.MADE if held + others <= cap or others <= 0 else Room.BUSY

    def _clear(self, folder: Path, need: int, keep: str) -> int:
        """
        The songs played longest ago cleared until `need` bytes are freed, never `keep` and never a
        song being played (IN_USE_SECONDS) - a make that still can't be written fails, as a make that
        found no room does. What was freed.
        """
        freed, now = 0, self.wall_clock()
        for served, name, size in self._entries(folder):
            if freed >= need or now - served < IN_USE_SECONDS:
                break
            if name != keep and self._drop(folder, name):
                freed += size
        return freed

    def _evict(self, folder: Path, keep: str, over: int = 0) -> None:
        """
        Least recently served first, until the cache is under its limit again - never `keep`, the
        file just made, which is the one about to be served. The songs being played were served last
        of all, so they go last, and only when nothing else brings the cache back under its cap -
        which after _make_room() is only once the cap has been lowered. `over`: how much bigger the
        file just made came out than the room made for it - never a reason to clear a song being
        played, whose next piece would only make it again, clearing another in turn.
        """
        entries = self._entries(folder)
        now = self.wall_clock()
        total = sum(size for _, _, size in entries)
        for served, name, size in entries:
            if total <= self.max_bytes:
                break
            if now - served < IN_USE_SECONDS and total <= self.max_bytes + over:
                break
            if name != keep and self._drop(folder, name):
                total -= size


#? One for the process, like the Navidrome client it fetches with. Nothing about where it keeps its
#? files is decided until a song is asked for.
cache = Mp4Cache()
