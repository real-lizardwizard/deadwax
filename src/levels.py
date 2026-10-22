"""
The level a song is played at - the player's Normalization (2.0.0-player.62): which songs are measured,
when, where the measurements are kept, and the gain a levelled copy is made at.

src/loudness.py measures and works the gain out; src/resample.py applies it, in the copy the player cache
already makes of a FLAC song (src/player_cache.py). This is the part between: one `Levels` per cache.

  - A levelled request (`level=album` or `level=track` on the stream, the scrub) asks copy_plan()
    (src/album_context.py), which asks levelled() here for the gain - the song's own (`track`), or its
    album's (`album`: every FLAC song of Navidrome's album - every disc - that deadwax can read, their
    histograms pooled, one gain for all of them, so the album's joins stay sample-exact).
  - What isn't measured yet is measured first, ON DEMAND: each song downloaded from Navidrome into the
    cache's folder (`<key>.<token>.measure`, deleted after; the cache's leftover sweep clears old ones),
    measured MEASURES_AT_ONCE at a time in worker threads, single flight per song and per album, ONE
    album at a time, shielded - a phone hanging up never stops a measurement: unlike a make, it is worth
    finishing, kept for good.
  - A request waits LEVEL_WAIT_SECONDS for it at the most (LEVEL_WAIT_HIRES_SECONDS for a copy that is
    resampled too, or above 48 kHz: its make takes longer), so the wait AND the make fit under the
    stream's own 60 s head wait - and past it is answered as without `level` this once (said once); the
    measurement carries on. While that album is still being measured its other songs are answered as they
    are AT ONCE (`_overdue`), not after a wait of their own each; and a gain kept from before is answered
    within STALE_WAIT_SECONDS while it is worked out again.
  - What was answered as the song as it is is remembered (`_plain`, for the song's length and a little):
    Info's route says so, and the turntable's windows of it are cut from the song as it is - what is heard.
  - An album whose songs are all measured is never held behind another album being measured: the
    one-album gate is taken only to measure. An album one of whose songs couldn't be looked at just now
    gets no gain until it can be (looked at again once at once) - a gain pooled from part of it would be
    another gain a moment later, and the album would step at a join.
  - An album page opening (Part A) starts its album's measurement early (warm(), POST /level/album/{id}),
    dropped when another album is being measured - a play measures on demand anyway.
  - A download filed by the organizer (Part B) has its FLAC songs measured from their local files, on a
    low-priority thread of their own (measure_filed()), keyed by the STREAMINFO read from each file - the
    same key Navidrome's copy of it will have, since tagging never touches STREAMINFO.
  - Kept in deadwax's database (store.py's `loudness`), by audio key (loudness.audio_key()), and in
    memory (LEVELS_KEPT). The gain resolved for a (version, level, cap) is kept VERSION_SECONDS like the
    cache's other memories, and beyond that as what a lookup that fails falls back on - so a Navidrome
    hiccup never changes a song's level, and so never its file, under a URL being played.

What can be levelled: FLAC, 1 or 2 channels, 16 or 24 bits (libsndfile 1.2.2 can't open 20 or 32), any
rate. Anything else is answered exactly as without `level`, and describe() - Info's route - says why.
"""

import asyncio
import concurrent.futures
import os
import secrets
import shutil
import threading
import time
from dataclasses import dataclass, replace
from functools import cache

import httpx

from src import loudness, resample
from src.album_context import _ASKING, CONTEXT_SECONDS, CannotPlan, _is_flac, _keep, _NoAlbum, _why
from src.api.navidrome_endpoint import NavidromeError, navidrome
from src.flac_mp4 import CannotRepackage, NotFlac, StreamInfo, _parse_streaminfo, _skip_id3v2
from src.logger import logger

#? How long a levelled request waits for its song or album to be measured, in seconds, before it is
#? answered as the song as it is, this once. Under the page's 60 s wait for a stream's first song
#? (RESAMPLE_HEAD_WAIT_MS), so the stream gets an answer before it gives up.
LEVEL_WAIT_SECONDS = 50
#? ...and for a copy that is resampled as well, or levelled above 48 kHz: its make (a hi-res resample can
#? run most of a minute on a NAS) needs the rest of the page's 60 s, so the gain gets less of it
LEVEL_WAIT_HIRES_SECONDS = 20
#? ...and when a gain was worked out before (kept beyond VERSION_SECONDS): it is worked out again, but
#? answered with the one kept when that takes longer than this - an album measured already never waits
STALE_WAIT_SECONDS = 5
#? How long past a song's own length deadwax remembers that it answered it as it is (`_plain`)
PLAIN_MARGIN_SECONDS = 60

#? Songs measured at once: numpy's FFT and libsndfile let go of the GIL, so several cores help - one
#? left for everything else, four at the most (measured: 12 CD songs in 10.6 s on 1, 4.0 s on 4).
MEASURES_AT_ONCE = max(1, min(4, (os.cpu_count() or 2) - 1))

#? Songs of an album looked at at once for their versions and STREAMINFO (as album_context's).
LOOKS_AT_ONCE = 8
#? What Navidrome answers a song's look with that may pass in a moment (a song of an album looked at again
#? before it is levelled without it, _album_songs) - any other error is about the file, and stays.
BRIEF_REFUSALS = (429, 503)

#? How many songs' measurements are held in memory (each a few hundred bytes), and how many resolved
#? gains - bounded, the oldest going first.
LEVELS_KEPT = 8192
GAINS_KEPT = 1024
#? ...and how many songs that can't be measured, and why
UNMEASURABLE_KEPT = 1024

#? What the cache's folder keeps of a song being measured. Not ending in .mp4: the cache's leftover
#? sweep clears one a process left behind.
MEASURE_SUFFIX = ".measure"

#? How much of a filed FLAC is read for its STREAMINFO (Part B).
HEAD_READ = 64 * 1024

#? The libraries a level needs: numpy and soundfile. (soxr only to measure a hi-res song's loudness at
#? 48 kHz - without it, at the song's own rate.)
LIBRARIES = ("numpy", "soundfile")

#? The one cap the page asks for ("Up to 48 kHz"): an album with a song deadwax resamples under it keeps the
#? resample's room in its one gain (_album_reserve())
RESAMPLE_CAP = 48000

#? The words Info's route gives for a song it won't level.
NOT_FLAC = "it isn't a FLAC file"
UNREADABLE = "its file can't be read as FLAC by deadwax (20- or 32-bit)"
NO_CACHE = "the player's cache can't be used on this server"
NO_LIBRARIES = "deadwax is running without numpy and soundfile"


@cache
def _missing() -> str | None:
    gone = []
    for name in LIBRARIES:
        try:
            __import__(name)
        except Exception:
            gone.append(name)
    return ", ".join(gone) or None


def missing_libraries() -> str | None:
    """Which of the libraries a level needs can't be imported, in words - or None when both can."""
    return _missing()


@dataclass(frozen=True)
class Song:
    """One song as levelling knows it: its file's version, STREAMINFO and audio key."""

    song_id: str
    version: object
    info: StreamInfo
    key: str


@dataclass(frozen=True)
class Resolved:
    """A level worked out: its gain, and the songs it was worked out from."""

    gain: loudness.Gain
    songs: int


def _reason(info: StreamInfo) -> str | None:
    """Why a FLAC of this STREAMINFO can't be levelled, or None when it can."""
    if info.bits_per_sample not in loudness.MEASURED_DEPTHS:
        return UNREADABLE
    if info.channels not in loudness.MEASURED_CHANNELS:
        return f"it has {info.channels} channels - only mono and stereo are levelled"
    if not info.total_samples:
        return "its STREAMINFO doesn't say how long it is"
    return None


def _row(key: str, measurement: loudness.Measurement) -> dict:
    return {"audio_key": key, "algorithm": loudness.ALGORITHM_VERSION, "peak": measurement.peak,
            "histogram": loudness.pack(measurement.histogram), "blocks": measurement.blocks,
            "seconds": measurement.seconds}


def _measurement(row: dict) -> loudness.Measurement | None:
    """A kept row as a measurement - None for one of another algorithm, or one that doesn't read."""
    try:
        if int(row["algorithm"]) != loudness.ALGORITHM_VERSION:
            return None
        return loudness.Measurement(peak=float(row["peak"]), histogram=loudness.unpack(bytes(row["histogram"])),
                                    blocks=int(row["blocks"]), seconds=float(row["seconds"]))
    except (KeyError, TypeError, ValueError):
        return None


class Levels:
    """What deadwax knows of its songs' loudness, and the gains it levels them at. One per player cache."""

    def __init__(self, cache):
        #? the player cache: its versions, its folder, its clock and its albums
        self.cache = cache
        #? the database the measurements are kept in - set at start-up (src/api/app.py); without one they
        #? are kept in memory only
        self.store = None
        #? audio key -> its measurement, the oldest first (LEVELS_KEPT)
        self._read: dict[str, loudness.Measurement] = {}
        #? audio key -> why it can't be measured: the same on every try
        self._unmeasurable: dict[str, str] = {}
        #? (version key, level, cap) -> (believed until, the level resolved) - kept beyond, as what a
        #? lookup that fails falls back on
        self._gains: dict[tuple, tuple[float, Resolved]] = {}
        #? the single flights: a resolution per (version key, level, cap), a measurement per audio key,
        #? an album's per album id
        self._resolving: dict[tuple, asyncio.Task] = {}
        self._songs: dict[str, asyncio.Task] = {}
        self._albums: dict[str, asyncio.Task] = {}
        #? an album being measured: (songs measured, songs in all)
        self._progress: dict[str, tuple[int, int]] = {}
        #? the background measurements nobody awaits, kept so they aren't collected half way
        self._background: set[asyncio.Task] = set()
        #? one album at a time, and MEASURES_AT_ONCE songs - made for the event loop that uses them
        self._gate_loop = None
        self._album_gate: asyncio.Lock | None = None
        self._measures: asyncio.Semaphore | None = None
        self._said: dict[tuple, float] = {}
        self._said_libraries = False
        #? (version key, level, cap) -> until: answered as the song as it is, its level not to be had in
        #? time - Info says so, and its windows are cut as without the level (what is heard)
        self._plain: dict[tuple, float] = {}
        #? albums a request has waited the whole wait for while their measurement is still running: their
        #? other songs are answered as they are at once until it ends, not after a wait each
        self._overdue: set[str] = set()
        #? a resolution waiting on its album's measurement -> that album's id
        self._awaiting: dict[tuple, str] = {}

    # ------------------------------------------------------------ the gates

    def _gates(self) -> tuple[asyncio.Lock, asyncio.Semaphore]:
        loop = asyncio.get_running_loop()
        if self._gate_loop is not loop:
            self._gate_loop, self._album_gate, self._measures = loop, asyncio.Lock(), asyncio.Semaphore(MEASURES_AT_ONCE)
        return self._album_gate, self._measures

    @staticmethod
    def _live(task: asyncio.Task | None) -> bool:
        """A task this loop can wait on, still running."""
        return task is not None and not task.done() and task.get_loop() is asyncio.get_running_loop()

    def levelling(self) -> bool:
        """Whether songs can be levelled here: numpy and soundfile are there. Said once when not."""
        missing = missing_libraries()
        if missing and not self._said_libraries:
            self._said_libraries = True
            logger.warning(f"player: songs can't be levelled on this server - {missing} couldn't be loaded - so "
                           f"they are sent as they are, whatever the player's Normalization says")
        return missing is None

    # ------------------------------------------------------------ songs

    async def song_of(self, version) -> Song | str:
        """This version of a song as levelling knows it, or why it can't be levelled. Raises CannotPlan
        when its STREAMINFO couldn't be read just now."""
        try:
            head = await asyncio.wait_for(self.cache.albums.stream_info(version), CONTEXT_SECONDS)
        except _ASKING as e:
            raise CannotPlan(_why(e)) from e
        if head is None:
            return UNREADABLE
        info = head[0]
        why = _reason(info)
        if why is not None:
            return why
        key = loudness.audio_key(info.raw, version.key)
        return Song(song_id=version.song_id, version=version, info=info, key=key)

    async def _song(self, song_id: str) -> Song | str:
        """A song by its id, as song_of() - what the cache has of it first. Raises what asking raises."""
        version = await self.cache._version(song_id)
        if version is None:
            return self.cache._why_not.get(song_id) or NOT_FLAC
        return await self.song_of(version)

    async def _album_songs(self, album_id: str) -> tuple[list[Song], bool]:
        """
        The FLAC songs of an album that can be levelled, in its order: Navidrome's album (getAlbum: every
        disc), as the shared account - like every other read the cache makes. A song that isn't FLAC, or
        one deadwax can't read, is left out (it plays as it is). And whether that is the WHOLE album: False
        when a song couldn't be looked at just now (its STREAMINFO not read in time, Navidrome broken off,
        or answering it with a 429 or 503) - it may be levellable a moment later, and a gain pooled without
        it would be another gain then. A song Navidrome answers with any other error (its file gone or
        unreadable on Navidrome's side: a 404, a 500) is left out like one deadwax can't read - it can't be
        played either, and that doesn't pass in a moment, so it mustn't keep the whole album unlevelled.
        Navidrome not answering at all raises, as asking does.
        """
        listing = await self.cache.albums._listing(album_id)
        ids = [str(entry.get("id")) for entry in listing if _is_flac(entry) and entry.get("id")]
        at_once = asyncio.Semaphore(LOOKS_AT_ONCE)

        async def look(song_id: str):
            async with at_once:
                try:
                    return await self._song(song_id)
                except NavidromeError as e:
                    if e.unreachable:
                        raise
                    #? (after review) only a refusal that says "a moment" is brief; any other is the file's
                    return None if e.status in BRIEF_REFUSALS else str(e)
                except (CannotPlan, httpx.TransportError):
                    return None

        looked = await asyncio.gather(*(look(song_id) for song_id in ids))
        return [song for song in looked if isinstance(song, Song)], all(song is not None for song in looked)

    # ------------------------------------------------------------ measurements

    async def known(self, keys: list[str]) -> dict[str, loudness.Measurement]:
        """The measurements of these songs deadwax has - in memory, else in its database."""
        found = {key: self._read[key] for key in keys if key in self._read}
        missing = [key for key in keys if key not in found]
        if missing and self.store is not None:
            rows = await self.store.loudness_get(missing)
            for key, row in rows.items():
                measurement = _measurement(row)
                if measurement is not None:
                    found[key] = measurement
                    _keep(self._read, key, measurement, LEVELS_KEPT)
        return found

    async def _remember(self, key: str, measurement: loudness.Measurement) -> None:
        _keep(self._read, key, measurement, LEVELS_KEPT)
        if self.store is not None:
            await self.store.loudness_put(_row(key, measurement))

    async def measure(self, song: Song) -> loudness.Measurement | None:
        """This song measured - once however many ask (single flight per audio key), and finished even
        when every asker has gone. None when it can't be, which is said."""
        if song.key in self._unmeasurable:
            return None
        task = self._songs.get(song.key)
        if not self._live(task):
            task = asyncio.ensure_future(self._measure_now(song))
            self._songs[song.key] = task

            def forget(done: asyncio.Task, key: str = song.key) -> None:
                if self._songs.get(key) is done:
                    del self._songs[key]
                if not done.cancelled():
                    done.exception()

            task.add_done_callback(forget)
        return await asyncio.shield(task)

    async def _measure_now(self, song: Song) -> loudness.Measurement | None:
        """Download the song into the cache's folder, measure it in a worker thread, keep the answer."""
        _, measures = self._gates()
        async with measures:
            known = await self.known([song.key])
            if song.key in known:
                return known[song.key]
            folder = await self.cache._folder()
            if folder is None:
                return None
            await asyncio.to_thread(self.cache._prepare, folder)
            path = folder / f"{song.version.key[:40]}.{secrets.token_hex(4)}{MEASURE_SUFFIX}"
            try:
                if not await self._room(folder, song.version.size):
                    logger.warning(f"player: song {song.song_id} isn't measured just now - the disk holding the "
                                   f"player's cache is short of space for it; it plays as it is")
                    return None
                if not await self._download(song, path):
                    return None
                began = time.monotonic()
                try:
                    measurement = await asyncio.to_thread(loudness.measure_file, path)
                except loudness.CannotMeasure as e:
                    _keep(self._unmeasurable, song.key, str(e), UNMEASURABLE_KEPT)
                    logger.warning(f"player: song {song.song_id} can't be measured ({e}); it plays as it is")
                    return None
                await self._remember(song.key, measurement)
                logger.info(f"player: song {song.song_id} measured - {_lufs(measurement.loudness)}, peak "
                            f"{_dbfs(measurement.peak)} ({measurement.seconds:.0f} s of it in "
                            f"{time.monotonic() - began:.1f} s)")
                return measurement
            except OSError as e:
                logger.warning(f"player: song {song.song_id} couldn't be measured just now ({e}); it plays as it is")
                return None
            finally:
                await asyncio.to_thread(path.unlink, missing_ok=True)

    async def _room(self, folder, size: int) -> bool:
        """Room on the cache's disk for a song being measured, beside DISK_SPARE_BYTES - songs played
        longest ago cleared for it if need be, never one being played."""
        from src.player_cache import DISK_SPARE_BYTES

        def find() -> bool:
            try:
                free = shutil.disk_usage(folder).free
            except OSError:
                return True
            need = size + DISK_SPARE_BYTES
            if free >= need:
                return True
            self.cache._clear(folder, need - free, "")
            try:
                return shutil.disk_usage(folder).free >= need
            except OSError:
                return True
        return await asyncio.to_thread(find)

    async def _download(self, song: Song, path) -> bool:
        """The whole of the song's file into `path`, exactly the version looked at. False, and said,
        otherwise."""
        version = song.version
        what = f"song {song.song_id}"
        try:
            upstream = await navidrome.open("stream", {"id": song.song_id, "format": "raw"})
        except NavidromeError as e:
            logger.warning(f"player: {what} couldn't be fetched to measure it ({e}); it plays as it is")
            return False
        out = None
        try:
            declared = upstream.headers.get("content-length")
            if upstream.status_code != 200 or (declared is not None and declared != str(version.size)):
                self.cache._versions.pop(song.song_id, None)
                logger.info(f"player: {what} changed while it was being fetched to measure it; it plays as it is")
                return False
            out = await asyncio.to_thread(open, path, "wb")
            received, batch, held = 0, [], 0
            async for chunk in upstream.aiter_raw():
                received += len(chunk)
                if received > version.size:
                    self.cache._versions.pop(song.song_id, None)
                    return False
                batch.append(chunk)
                held += len(chunk)
                if held >= 1 << 20:
                    await asyncio.to_thread(out.write, b"".join(batch))
                    batch, held = [], 0
            if batch:
                await asyncio.to_thread(out.write, b"".join(batch))
            if received != version.size:
                logger.warning(f"player: Navidrome sent {received} of {version.size} bytes of {what} while it was "
                               f"being fetched to measure it; it plays as it is")
                return False
            return True
        except httpx.TransportError as e:
            logger.warning(f"player: Navidrome stopped sending {what} while it was being fetched to measure it "
                           f"({str(e) or type(e).__name__}); it plays as it is")
            return False
        finally:
            if out is not None:
                await asyncio.to_thread(out.close)
            await upstream.aclose()

    # ------------------------------------------------------------ albums

    def _album_task(self, album_id: str) -> asyncio.Task:
        """The album's measurement, started if it isn't under way - one album at a time."""
        task = self._albums.get(album_id)
        if self._live(task):
            return task
        task = asyncio.ensure_future(self._measure_album(album_id))
        self._albums[album_id] = task

        def forget(done: asyncio.Task) -> None:
            if self._albums.get(album_id) is done:
                del self._albums[album_id]
            self._progress.pop(album_id, None)
            self._overdue.discard(album_id)
            if not done.cancelled():
                done.exception()

        task.add_done_callback(forget)
        return task

    async def _unmeasured(self, songs: list[Song]) -> list[Song]:
        """The songs of these not measured yet - and not known to be unmeasurable."""
        known = await self.known([song.key for song in songs])
        return [song for song in songs if song.key not in known and song.key not in self._unmeasurable]

    async def _measure_album(self, album_id: str) -> tuple[list[Song], bool]:
        """Every song of the album not measured yet, measured - MEASURES_AT_ONCE at a time, under the
        one-album gate, which is taken only when there is something to measure: an album measured already
        never waits behind another. The album's songs that can be levelled, and whether that is all of
        them (_album_songs)."""
        gate, _ = self._gates()
        began = time.monotonic()
        songs, whole = await self._album_songs(album_id)
        if not await self._unmeasured(songs):
            return songs, whole
        self._progress[album_id] = (len(songs) - len(await self._unmeasured(songs)), len(songs))
        async with gate:
            missing = await self._unmeasured(songs)
            done = len(songs) - len(missing)
            self._progress[album_id] = (done, len(songs))

            async def one(song: Song) -> None:
                nonlocal done
                await self.measure(song)
                done += 1
                self._progress[album_id] = (done, len(songs))

            if missing:
                await asyncio.gather(*(one(song) for song in missing))
                logger.info(f"player: album {album_id} measured for Normalization - {len(missing)} of its "
                            f"{len(songs)} FLAC songs in {time.monotonic() - began:.1f} s")
            return songs, whole

    def warm(self, album_id: str) -> str:
        """
        An album page opened: its album measured in the background, not waited for (Part A) - unless
        it is being measured already ("measuring"), or another album's measurement is under way - its
        songs being listed as well as measured - and then it is dropped ("busy"): a play measures on
        demand anyway. (After review: judged by the gate alone, two pages opened while the first album
        was still being listed both queued a whole album, and a play behind them waited past its wait.)
        """
        if self._live(self._albums.get(album_id)):
            return "measuring"
        gate, _ = self._gates()
        if gate.locked() or any(self._live(task) for task in self._albums.values()):
            return "busy"
        task = self._album_task(album_id)
        self._background.add(task)
        task.add_done_callback(self._background.discard)
        return "measuring"

    # ------------------------------------------------------------ the gain

    async def levelled(self, version, base: resample.ResamplePlan | None, max_rate: int | None,
                       level: str, window: bool = False) -> resample.ResamplePlan | None:
        """
        The plan of the copy deadwax makes of this version at `level` - `base` (the resample's plan, or
        None) with the level's gain set, or a plan at the song's own rate when there is no resample - or
        `base` unchanged when the song can't be levelled, or its level can't be had in time (said, and
        remembered in `_plain`). A turntable's `window` of a song lately answered as it is is cut as without
        the level: the window sounds as the song heard does. Raises CannotPlan when its own STREAMINFO
        couldn't be read just now.
        """
        song = await self.song_of(version)
        if not isinstance(song, Song):
            return base
        too_big = self._too_big(song, self._copy(song, base, max_rate, level, 0.0))
        if too_big is not None:
            #? (after review) a copy too big to make goes as Off would send the song - Safari's plain MP4,
            #? not the bare FLAC a refused copy is - and its window the same; nothing measured for it
            self._say(("too big", song.version.key), f"player: song {song.song_id} plays as it is - {too_big}")
            return base
        memo = (song.version.key, level, max_rate)
        now = self.cache.clock()
        if window and self._plain.get(memo, 0) > now:
            return base
        resolved = await self.resolve(song, base, max_rate, level)
        if resolved is None:
            if not window:
                seconds = song.info.total_samples / song.info.sample_rate if song.info.sample_rate else 0
                self._plain = {key: until for key, until in self._plain.items() if until > now}
                _keep(self._plain, memo, now + seconds + PLAIN_MARGIN_SECONDS, GAINS_KEPT)
            return base
        if not window:
            self._plain.pop(memo, None)
        return self._copy(song, base, max_rate, level, resolved.gain.gain_db)

    @staticmethod
    def _copy(song: Song, base: resample.ResamplePlan | None, max_rate: int | None, level: str,
              gain: float) -> resample.ResamplePlan:
        """The plan of the levelled copy: `base` with the level's gain set, or a plan at the song's own rate."""
        if base is not None:
            return replace(base, level=level, gain_db=gain)
        info = song.info
        return resample.ResamplePlan(max_rate=max_rate, source_rate=info.sample_rate, out_rate=info.sample_rate,
                                     channels=info.channels, bits=info.bits_per_sample,
                                     total_samples=info.total_samples, level=level, gain_db=gain)

    def _too_big(self, song: Song, plan: resample.ResamplePlan) -> str | None:
        """Why this levelled copy is too big to make - more than the cache holds in memory to repackage
        (WRAP_MAX_BYTES; a CD song's 24-bit copy is about 1.5 times its file) - or None. Its size is the
        same whatever the gain."""
        if self.cache._held_size(song.version, plan) <= self.cache.wrap_max_bytes:
            return None
        return self.cache._too_big(song.version, plan)

    async def resolve(self, song: Song, base: resample.ResamplePlan | None, max_rate: int | None,
                      level: str) -> Resolved | None:
        """The level of this song, worked out once for everyone asking (single flight), waited for
        LEVEL_WAIT_SECONDS at the most (LEVEL_WAIT_HIRES_SECONDS for a hi-res copy, STALE_WAIT_SECONDS
        with one kept from before): past that, the one kept from before - or None, this once."""
        memo = (song.version.key, level, max_rate)
        kept = self._gains.get(memo)
        if kept is not None and kept[0] > self.cache.clock():
            return kept[1]
        task = self._resolving.get(memo)
        if not self._live(task):
            task = asyncio.ensure_future(self._resolve_now(song, base, max_rate, level, memo))
            self._resolving[memo] = task

            def forget(done: asyncio.Task) -> None:
                if self._resolving.get(memo) is done:
                    del self._resolving[memo]
                if not done.cancelled():
                    done.exception()

            task.add_done_callback(forget)
        if kept is not None:
            wait = STALE_WAIT_SECONDS
        elif base is not None or song.info.sample_rate > 48000:
            wait = LEVEL_WAIT_HIRES_SECONDS
        else:
            wait = LEVEL_WAIT_SECONDS
        try:
            return await asyncio.wait_for(asyncio.shield(task), wait)
        except asyncio.TimeoutError:
            if kept is not None:
                return kept[1]
            album_id = self._awaiting.get(memo)
            if album_id is not None and self._live(self._albums.get(album_id)):
                self._overdue.add(album_id)
            self._say(("waiting", memo), f"player: song {song.song_id} plays as it is this time - its "
                      f"{'album' if level == 'album' else 'loudness'} is still being measured")
            return None

    async def _resolve_now(self, song: Song, base, max_rate: int | None, level: str, memo) -> Resolved | None:
        now = self.cache.clock()
        kept = self._gains.get(memo)
        try:
            resolved = await (self._album_gain(song, memo) if level == "album" else self._track_gain(song, base))
        except (*_ASKING, _NoAlbum) as e:
            if kept is not None:
                return kept[1]
            self._say(("no album", memo), f"player: song {song.song_id} plays as it is - its album couldn't be "
                      f"looked at to level it ({_why(e)})", warn=True)
            return None
        if resolved is None:
            return kept[1] if kept is not None else None
        _keep(self._gains, memo, (now + self.cache.albums._seconds, resolved), GAINS_KEPT)
        return resolved

    async def _track_gain(self, song: Song, base) -> Resolved | None:
        """The song's own level: its loudness, held under its own peak - and the resample's headroom
        when its copy is resampled."""
        measurement = (await self.known([song.key])).get(song.key) or await self.measure(song)
        if measurement is None:
            return None
        reserve = resample.HEADROOM_DB if base is not None else 0.0
        return Resolved(gain=loudness.gain_for(measurement.loudness, measurement.peak, reserve), songs=1)

    async def _album_gain(self, song: Song, memo: tuple = ()) -> Resolved | None:
        """
        The album's level: the loudness of all its FLAC songs deadwax can read, pooled - whichever of
        them are in the queue - held under the loudest sample of any of them, with the resample's
        headroom when ANY of them is one deadwax resamples under Up to 48 kHz, whatever cap the asking
        song carries (_album_reserve()), so the album keeps one gain. None
        when any of them can't be had measured just now, or looked at (one measured only partly would be
        another gain a moment later, and the album would step at a join) - and at once while the album is
        overdue (a request has waited the whole wait for it already).
        """
        album_id = await self.cache.albums._album_of(song.song_id)
        task = self._album_task(album_id)
        if album_id in self._overdue and self._live(task):
            return None
        self._awaiting[memo] = album_id
        try:
            #? shielded: the album's measurement is everyone's, and worth finishing
            songs, whole = await asyncio.shield(task)
        finally:
            if self._awaiting.get(memo) == album_id:
                del self._awaiting[memo]
        if not whole:
            #? a song of it couldn't be looked at just now: once more, at once - then none, this time
            songs, whole = await self._album_songs(album_id)
            if not whole:
                self._say(("part", album_id), f"player: song {song.song_id} plays as it is this time - a song of its "
                          f"album couldn't be looked at just now, and the album is levelled only whole")
                return None
        if not any(other.key == song.key for other in songs):
            #? Navidrome's album doesn't list it (a scan under way): its own level, alone
            songs = [*songs, song]
        known = await self.known([other.key for other in songs])
        missing = [other for other in songs if other.key not in known and other.key not in self._unmeasurable]
        for other in missing:
            measurement = await self.measure(other)
            if measurement is not None:
                known[other.key] = measurement
        if song.key not in known or any(other.key not in known and other.key not in self._unmeasurable for other in songs):
            return None
        pooled = [known[other.key] for other in songs if other.key in known]
        peak = max(measurement.peak for measurement in pooled)
        gain = loudness.gain_for(loudness.loudness_of(pooled), peak, _album_reserve(songs))
        return Resolved(gain=gain, songs=len(pooled))

    # ------------------------------------------------------------ Info's answer

    async def describe(self, song_id: str, level: str, max_rate: int | None) -> dict:
        """
        What deadwax would level this song at - from what it has measured already, never measuring and
        never making anything: Info's Normalization row (GET /deadwax/navidrome/level/{song_id}).
        Raises NavidromeError and httpx's errors as the song's own reads would.
        """
        answer = {"level": level, "state": "unmeasured", "gain_db": None, "wanted_db": None, "loudness_lufs": None,
                  "peak_db": None, "held": False, "songs": 1, "measured_songs": 0, "why": None}

        def not_levelled(why: str) -> dict:
            return {**answer, "state": "not_levelled", "why": why}

        if missing_libraries() is not None:
            return not_levelled(NO_LIBRARIES)
        if await self.cache._folder() is None:
            return not_levelled(NO_CACHE)
        try:
            song = await self._song(song_id)
        except CannotPlan:
            return answer
        if not isinstance(song, Song):
            return not_levelled(song)
        memo = (song.version.key, level, max_rate)
        if song.key in self._unmeasurable:
            return not_levelled(self._unmeasurable[song.key])
        info = song.info
        out = resample.output_rate(info.sample_rate, max_rate, info.bits_per_sample)
        resampled = out is not None
        #? the copy's size, as levelled() judges it (the resample's plan needs the song's length)
        copy = resample.ResamplePlan(max_rate=max_rate, source_rate=info.sample_rate,
                                     out_rate=out if out is not None and info.total_samples else info.sample_rate,
                                     channels=info.channels, bits=info.bits_per_sample,
                                     total_samples=info.total_samples, level=level, gain_db=0.0)
        too_big = self._too_big(song, copy)
        if too_big is not None:
            return not_levelled(too_big)
        if self._plain.get(memo, 0) > self.cache.clock():
            #? answered as it is this time: what is heard, whatever has been measured since
            return {**answer, "state": "plain"}
        kept = self._gains.get(memo)
        if kept is not None:
            return _measured(answer, kept[1])
        if level == "track":
            measurement = (await self.known([song.key])).get(song.key)
            if measurement is not None:
                reserve = resample.HEADROOM_DB if resampled else 0.0
                return _measured(answer, Resolved(loudness.gain_for(measurement.loudness, measurement.peak, reserve), 1))
            return {**answer, "state": "measuring" if self._live(self._songs.get(song.key)) else "unmeasured"}
        try:
            album_id = await self.cache.albums._album_of(song.song_id)
            songs, whole = await self._album_songs(album_id)
        except (*_ASKING, _NoAlbum):
            return answer
        if not any(other.key == song.key for other in songs):
            songs = [*songs, song]
        known = await self.known([other.key for other in songs])
        counted = [other for other in songs if other.key not in self._unmeasurable]
        measured = sum(1 for other in counted if other.key in known)
        if whole and counted and measured == len(counted):
            pooled = [known[other.key] for other in counted]
            gain = loudness.gain_for(loudness.loudness_of(pooled), max(m.peak for m in pooled), _album_reserve(songs))
            return _measured(answer, Resolved(gain, len(pooled)))
        state = "measuring" if self._live(self._albums.get(album_id)) else "unmeasured"
        progress = self._progress.get(album_id)
        if state == "measuring" and progress is not None:
            measured = max(measured, progress[0])
        return {**answer, "state": state, "songs": len(counted), "measured_songs": measured}

    def _say(self, what: tuple, line: str, warn: bool = False) -> None:
        """A line said once a VERSION_SECONDS, however many requests run into it."""
        now = self.cache.clock()
        if self._said.get(what, 0) > now:
            return
        self._said = {key: until for key, until in self._said.items() if until > now}
        self._said[what] = now + self.cache.albums._seconds
        (logger.warning if warn else logger.info)(line)


def _album_reserve(songs: list[Song]) -> float:
    """
    The resample's room an album's one gain keeps: HEADROOM_DB when any of its songs is one deadwax resamples
    under "Up to 48 kHz" (resample.output_rate() under RESAMPLE_CAP), and it can resample here at all - whatever
    cap the song asking carries. The page sends the cap only with a song it resamples (lib/streamWrap
    resamples()), so an album's CD songs come without it under either setting: keyed on the asking song's own
    cap, they would be levelled up to 3 dB from its hi-res songs, and the album would step at their joins. So
    the reserve is the album's, the same under either setting - under "Original", where nothing is resampled, it
    costs a peak-held album with a hi-res song up to 3 dB of loudness, and nothing else.
    """
    if resample.missing_libraries() is not None:
        return 0.0
    if any(resample.output_rate(song.info.sample_rate, RESAMPLE_CAP, song.info.bits_per_sample) is not None
           for song in songs):
        return resample.HEADROOM_DB
    return 0.0


def _finite(value: float) -> float | None:
    return round(value, 2) if value == value and abs(value) != float("inf") else None


def _measured(answer: dict, resolved: Resolved) -> dict:
    gain = resolved.gain
    return {**answer, "state": "measured", "gain_db": gain.gain_db, "wanted_db": _finite(gain.wanted_db),
            "loudness_lufs": _finite(gain.loudness), "peak_db": _finite(gain.peak_db), "held": gain.held,
            "songs": resolved.songs, "measured_songs": resolved.songs}


def _lufs(value: float) -> str:
    return f"{value:.1f} LUFS" if value != float("-inf") else "silent"


def _dbfs(peak: float) -> str:
    import math
    return f"{20 * math.log10(peak):+.2f} dBFS" if peak > 0 else "silent"


# ---------------------------------------------------------------- Part B: a download filed

def streaminfo_of(path) -> bytes | None:
    """The 34 bytes of a FLAC file's STREAMINFO, read from its first HEAD_READ bytes - None for a file
    that isn't a FLAC this reads."""
    try:
        with open(path, "rb") as handle:
            data = handle.read(HEAD_READ)
        pos = _skip_id3v2(data)
        if not data.startswith(b"fLaC", pos) or data[pos + 4] & 0x7F != 0 or int.from_bytes(data[pos + 5:pos + 8], "big") != 34:
            return None
        info = _parse_streaminfo(data[pos + 8:pos + 42])
        return info.raw if len(info.raw) == 34 else None
    except (OSError, IndexError, NotFlac, CannotRepackage):
        return None


def _quietly(work):
    """`work` run on a thread of its own, at a low priority (nice 10, Linux; ignored where it can't be
    set) - so a measurement at filing never holds up a song being played. Its own thread, so the nice
    goes with it: a pooled thread would keep it for whatever it ran next."""
    def run():
        try:
            os.setpriority(os.PRIO_PROCESS, threading.get_native_id(), 10)
        except (AttributeError, OSError):
            pass
        return work()

    pool = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="deadwax-measure")
    try:
        return asyncio.wrap_future(pool.submit(run))
    finally:
        pool.shutdown(wait=False)


async def measure_filed(store, paths) -> int:
    """
    (Part B) The FLAC songs a download just filed, measured from their local files and kept, so the
    album's first levelled play waits only for its make. Each keyed by its own STREAMINFO - the same
    key Navidrome's copy of it has. Reads only, and writes only deadwax's database: not a writer to the
    library. A song already measured, one whose MD5 is all zeros (keyed by Navidrome's version, which
    this can't know), and one that can't be read are passed over. Never raises. How many were measured.
    """
    if store is None or not getattr(store, "available", False) or missing_libraries() is not None:
        return 0
    measured = 0
    for path in paths:
        try:
            raw = await asyncio.to_thread(streaminfo_of, path)
            key = loudness.audio_key(raw, None) if raw is not None else None
            if key is None:
                continue
            kept = await store.loudness_get([key])
            if key in kept and _measurement(kept[key]) is not None:
                continue
            measurement = await _quietly(lambda path=path: loudness.measure_file(path))
            if await store.loudness_put(_row(key, measurement)):
                measured += 1
        except loudness.CannotMeasure as e:
            logger.info(f"filed song {path} isn't measured for Normalization ({e})")
        except Exception as e:
            logger.warning(f"measuring filed song {path} for Normalization failed ({type(e).__name__}: {e})")
    if measured:
        logger.info(f"measured {measured} filed song(s) for the player's Normalization")
    return measured
