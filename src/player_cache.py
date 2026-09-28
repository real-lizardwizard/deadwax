"""
FLAC songs sent to Safari inside an MP4, and the disk cache that makes that affordable.

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
     name and renamed into place, so a half-written file is never served. One repackage per
     version at a time however many requests want it (single flight), and one at a time
     altogether, since the whole file is in memory while it is repackaged.
  4. Served from the cache with byte ranges, which Safari won't play without.

Anything that goes wrong answers None, and the route relays the FLAC exactly as it did before this
existed: a type that isn't FLAC, a file too big to hold in memory, a stream the muxer won't vouch
for, Navidrome dropping the download, a full disk. A song that plays and seeks badly in Safari
beats a song that doesn't play.

The cache is in the container's TEMPORARY space, not the config volume. It is rebuilt on demand
from Navidrome, so there is nothing in it worth keeping; the config volume is what people back up,
and a gigabyte of repackaged audio in their backups would be a cost for nothing; and a new image
starts it empty, so an MP4 made by an older muxer can't outlive the upgrade that changed it
(FORMAT_VERSION covers a restart without one). It has no setting: it only ever has to hold the
songs being listened to now, and CACHE_MAX_BYTES holds a few albums of them.

A retag rewrites a file in place under the same Navidrome id, so the cache is keyed on the
version, never the id alone. Worth knowing when reading that: the MP4 carries only STREAMINFO and
the audio frames, never the tags, so a retag makes the same MP4 again - a wasted repackage, never
a wrong one. It is a file whose AUDIO was replaced that the key has to catch.
"""

import asyncio
import hashlib
import json
import os
import re
import secrets
import tempfile
import time
from dataclasses import dataclass
from email.utils import formatdate
from pathlib import Path

import httpx
from fastapi import Request
from fastapi.responses import Response, StreamingResponse
from starlette.background import BackgroundTask

from src.api.navidrome_endpoint import NavidromeError, navidrome
from src.flac_mp4 import CannotRepackage, mp4_layout
from src.logger import logger

#? The container's temporary space - see the module's docstring for why not /config.
CACHE_DIR = Path(tempfile.gettempdir()) / "deadwax-player"

#? The whole cache, least recently used going first past it. A CD-quality FLAC song is 20-60 MB,
#? so this holds several albums: the song playing, the next one (the gapless switch fetches it
#? early), and anything played again soon. It is only ever written for Safari.
CACHE_MAX_BYTES = 1 << 30

#? The largest file repackaged. The whole file is held in memory while it is - one at a time, for
#? a second or two - so this bounds what that costs a NAS. It covers every CD-quality song and most
#? hi-res ones; past it (an hour-long single-file rip, 24/192 at length) Safari gets the FLAC.
WRAP_MAX_BYTES = 512 << 20

#? How long what Navidrome said about a song's file is believed without asking again, in seconds.
#? A retag within that time is served from the MP4 of the version before it for at most this long.
VERSION_SECONDS = 30

#? Part of every cache key. Bump it whenever src/flac_mp4.py's output changes, so an MP4 made by
#? the old muxer is never served under a new one's name.
FORMAT_VERSION = 1

#? What Navidrome calls a FLAC file (resources/mime_types.yaml), and what an older setup might.
FLAC_TYPES = frozenset({"audio/flac", "audio/x-flac"})
MP4_TYPE = "audio/mp4"

#? A file this old in the cache folder that isn't a finished MP4 is left over from a process that
#? stopped part-way, and is cleared the first time the cache is used.
LEFTOVER_SECONDS = 600

#? What the download writes in one go, and what a range is read from disk in.
WRITE_BATCH = 1 << 20
READ_CHUNK = 64 * 1024

#? Versions whose file can't be repackaged, remembered so Safari's next request for the same file
#? doesn't fetch it all again only to fail again. Bounded; the oldest are forgotten first.
REFUSALS_KEPT = 256


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


async def ranged_file(path: Path, request: Request, etag: str) -> Response:
    """
    A file from the cache, whole or as the byte range asked for, as audio/mp4.

    Not Starlette's FileResponse, which was read (0.50) before deciding: its 416 says
    `Content-Range: */N` without the unit RFC 9110 requires, it refuses a suffix range longer than
    the file, and it stats the file only once it is sending - by which time the cache may have
    evicted it, which would surface as a 500. Here the file is opened first, so an eviction after
    that can't touch what is being sent (an open file outlives its name), and FileNotFoundError
    reaches the caller while it can still send the FLAC instead.

    If-Range is honoured against the ETag (strongly - a weak tag never matches) and the
    Last-Modified: a range asked for against any other version gets the whole file, which is how a
    seek never splices two versions of a song together.
    """
    handle = await asyncio.to_thread(open, path, "rb")
    try:
        stat = os.fstat(handle.fileno())
    except OSError:
        handle.close()
        raise
    size = stat.st_size
    last_modified = formatdate(stat.st_mtime, usegmt=True)
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


def _repackage(part: Path, target: Path) -> int:
    """
    The FLAC at `part` written out as an MP4 at `target`, under a temporary name first, so a
    half-written MP4 is never there to be served. Runs in a worker thread. Returns its size.

    The MP4 is the muxer's head followed by a slice of the FLAC already in memory (mp4_layout()),
    so the file is held once, not twice.
    """
    data = part.read_bytes()
    head, start, end = mp4_layout(data)
    temporary = target.with_name(f"{target.stem}.{secrets.token_hex(4)}.tmp")
    try:
        with open(temporary, "wb") as out:
            out.write(head)
            out.write(memoryview(data)[start:end])
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return len(head) + end - start


class Mp4Cache:
    """The repackaged songs on disk, and what is known about the versions they were made from."""

    def __init__(self, directory: Path = CACHE_DIR, max_bytes: int = CACHE_MAX_BYTES,
                 wrap_max_bytes: int = WRAP_MAX_BYTES):
        self.directory = Path(directory)
        self.max_bytes = max_bytes
        self.wrap_max_bytes = wrap_max_bytes
        #? song id -> (believed until, on the monotonic clock; its version, or None: not one to wrap)
        self._versions: dict[str, tuple[float, Version | None]] = {}
        #? cache key -> the repackage under way for it
        self._working: dict[str, asyncio.Task] = {}
        #? cache key -> why it can't be repackaged, oldest first
        self._refused: dict[str, str] = {}
        #? file name -> when it was last served (time.time()). A file not here - one made before a
        #? restart - counts as used when it was made. Kept apart from the file's own times, because
        #? its mtime is its Last-Modified: touching it would change the validator under a seek.
        self._used: dict[str, float] = {}
        self._prepared = False
        #? what VERSION_SECONDS is measured on - a test moves it on rather than waiting
        self.clock = time.monotonic
        #? one repackage at a time, made for the event loop that uses it
        self._gate_loop: asyncio.AbstractEventLoop | None = None
        self._gate_lock: asyncio.Lock | None = None

    def _gate(self) -> asyncio.Lock:
        loop = asyncio.get_running_loop()
        if self._gate_loop is not loop:
            self._gate_loop, self._gate_lock = loop, asyncio.Lock()
        return self._gate_lock

    def path_for(self, version: Version) -> Path:
        return self.directory / f"{version.key[:40]}.mp4"

    @staticmethod
    def etag_for(version: Version) -> str:
        return f'"{version.key[:32]}"'

    async def answer(self, song_id: str, request: Request) -> Response | None:
        """
        The song as an MP4, with the request's byte range - or None, and the caller sends the FLAC
        as it is. NavidromeError is raised as it would be for the FLAC: a song Navidrome doesn't
        have, a login it refuses, a Navidrome that isn't there.
        """
        version = await self._version(song_id)
        if version is None:
            return None
        path = await self._mp4(version)
        if path is None:
            return None
        try:
            return await ranged_file(path, request, self.etag_for(version))
        except FileNotFoundError:
            #? evicted between being found and being opened - the next request makes it again
            return None

    async def _version(self, song_id: str) -> Version | None:
        """What Navidrome has for this song now, or None when it isn't a FLAC this can wrap."""
        now = self.clock()
        remembered = self._versions.get(song_id)
        if remembered and remembered[0] > now:
            return remembered[1]

        try:
            version = await self._look(song_id)
        except httpx.TransportError:
            #? Navidrome dropped the four bytes: this request gets the FLAC, and nothing is
            #? remembered, so the next one asks again rather than taking FLAC for VERSION_SECONDS
            return None
        #? the expired go whenever anything is added, so this never grows past what was asked lately
        self._versions = {key: value for key, value in self._versions.items() if value[0] > now}
        self._versions[song_id] = (now + VERSION_SECONDS, version)
        return version

    async def _look(self, song_id: str) -> Version | None:
        """Four bytes of the file: its version, or None when it isn't a FLAC this can wrap."""
        try:
            upstream = await navidrome.open("stream", {"id": song_id, "format": "raw"},
                                            {"range": "bytes=0-3"})
        except NavidromeError as e:
            #? a 416 is an EMPTY file - an answer about the four bytes asked for here, not about
            #? anything Safari asked; the FLAC path answers Safari's own range
            if e.status == 416:
                return None
            raise
        first = b""
        try:
            #? a 200 would be the whole file, sent by something that ignored the range: not read
            if upstream.status_code != 206:
                return None
            if _media_type(upstream.headers.get("content-type")) not in FLAC_TYPES:
                return None
            async for chunk in upstream.aiter_raw():
                first += chunk
                if len(first) >= 4:
                    break
        finally:
            await upstream.aclose()

        size = _total(upstream.headers.get("content-range"))
        #? the bytes as well as the type: 'fLaC', or an ID3 tag some taggers put in front of it
        if size is None or not (first.startswith(b"fLaC") or first.startswith(b"ID3")):
            return None
        stamp = json.dumps([upstream.headers.get("last-modified"), upstream.headers.get("etag")])
        version = Version(song_id=song_id, size=size, stamp=stamp)
        if size > self.wrap_max_bytes:
            self._refuse(version, f"it is {size >> 20} MiB, more than the {self.wrap_max_bytes >> 20} "
                                  f"MiB a song is held in memory to repackage", warn=False)
            return None
        return version

    def _refuse(self, version: Version, reason: str, warn: bool = True) -> None:
        """Remember that this version can't be wrapped, and say so the first time."""
        if version.key in self._refused:
            return
        self._refused[version.key] = reason
        while len(self._refused) > REFUSALS_KEPT:
            del self._refused[next(iter(self._refused))]
        say = logger.warning if warn else logger.info
        say(f"player: song {version.song_id} is sent to Safari as FLAC, not in an MP4 - {reason}. "
            f"It plays, but Safari's seeks in it can land seconds off")

    async def _mp4(self, version: Version) -> Path | None:
        """The cached MP4 for this version, made if it isn't there. None when it can't be."""
        path = self.path_for(version)
        if await asyncio.to_thread(path.is_file):
            self._used[path.name] = time.time()
            return path
        if version.key in self._refused:
            return None

        task = self._working.get(version.key)
        if task is None:
            task = asyncio.ensure_future(self._make(version))
            self._working[version.key] = task

            def finished(done: asyncio.Task, key: str = version.key) -> None:
                if self._working.get(key) is done:
                    del self._working[key]

            task.add_done_callback(finished)
        #? shielded: a phone that hangs up mustn't cancel a repackage another request is waiting on
        return await asyncio.shield(task)

    async def _make(self, version: Version) -> Path | None:
        """
        Fetch, repackage, store. Never raises: every way it can fail is logged here, and answers
        None so the FLAC is sent instead.
        """
        try:
            async with self._gate():
                path = self.path_for(version)
                if await asyncio.to_thread(path.is_file):
                    return path
                await asyncio.to_thread(self._prepare)
                part = self.directory / f"{path.stem}.{secrets.token_hex(4)}.part"
                try:
                    if not await self._download(version, part):
                        return None
                    began = time.monotonic()
                    try:
                        size = await asyncio.to_thread(_repackage, part, path)
                    except CannotRepackage as e:
                        self._refuse(version, f"its FLAC stream couldn't be repackaged with certainty ({e})")
                        return None
                    took = (time.monotonic() - began) * 1000
                    logger.info(f"player: song {version.song_id} put in an MP4 for Safari "
                                f"({size >> 10} KiB, repackaged in {took:.0f} ms)")
                    self._used[path.name] = time.time()
                    await asyncio.to_thread(self._evict, path.name)
                    return path
                finally:
                    await asyncio.to_thread(part.unlink, missing_ok=True)
        except OSError as e:
            #? the disk: full, unwritable, the folder gone - the FLAC still plays
            logger.warning(f"player: song {version.song_id} couldn't be put in an MP4 for Safari "
                           f"({e}); it is sent as FLAC")
            return None
        except Exception:
            logger.exception(f"player: putting song {version.song_id} in an MP4 for Safari failed; "
                             f"it is sent as FLAC")
            return None

    async def _download(self, version: Version, part: Path) -> bool:
        """The whole file into `part`, exactly the version looked at. False, and said, otherwise."""
        what = f"song {version.song_id}"
        try:
            upstream = await navidrome.open("stream", {"id": version.song_id, "format": "raw"})
        except NavidromeError as e:
            logger.warning(f"player: {what} couldn't be fetched to put in an MP4 ({e}); it is sent as FLAC")
            return False
        out = None
        try:
            declared = upstream.headers.get("content-length")
            #? a length is checked when there is one; the bytes are counted either way, below
            if upstream.status_code != 200 or (declared is not None and declared != str(version.size)):
                #? changed since it was looked at: the next request looks again and wraps that
                self._versions.pop(version.song_id, None)
                logger.info(f"player: {what} changed while it was being put in an MP4; this request "
                            f"is sent the FLAC")
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
                               f"and stopped; it is sent as FLAC")
                return False
            return True
        except httpx.TransportError as e:
            logger.warning(f"player: Navidrome stopped sending {what} while it was being fetched to put "
                           f"in an MP4 ({str(e) or type(e).__name__}); it is sent as FLAC")
            return False
        finally:
            if out is not None:
                await asyncio.to_thread(out.close)
            await upstream.aclose()

    def _prepare(self) -> None:
        """The folder, made on first use; and what a process that stopped part-way left in it."""
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        if self._prepared:
            return
        self._prepared = True
        stale = time.time() - LEFTOVER_SECONDS
        for entry in os.scandir(self.directory):
            try:
                if not entry.name.endswith(".mp4") and entry.is_file() and entry.stat().st_mtime < stale:
                    os.unlink(entry.path)
            except OSError:
                pass

    def _evict(self, keep: str) -> None:
        """
        Least recently served first, until the cache is under its limit again - never `keep`, the
        file just made, which is the one about to be served. A file being served when it goes is
        unaffected: it was opened before, and an open file outlives its name.
        """
        entries = []
        for entry in os.scandir(self.directory):
            if not entry.name.endswith(".mp4"):
                continue
            try:
                stat = entry.stat()
            except OSError:
                continue
            entries.append((self._used.get(entry.name, stat.st_mtime), entry.name, stat.st_size))
        total = sum(size for _, _, size in entries)
        for _, name, size in sorted(entries):
            if total <= self.max_bytes:
                break
            if name == keep:
                continue
            try:
                os.unlink(self.directory / name)
            except OSError:
                continue
            total -= size
            self._used.pop(name, None)


#? One for the process, like the Navidrome client it fetches with.
cache = Mp4Cache()
