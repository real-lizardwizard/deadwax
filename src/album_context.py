"""
Which album a song resampled for the player is in, and what its album says about resampling it:
the phase of the album's sample grid in it, and which songs beside it lend their samples as context
(1.1.0-player.6). src/resample.py does the resampling, and says why both matter.

What is asked of Navidrome, and how. Nothing here is a player route - the player's list of routes
stays fixed (test_there_is_no_general_proxy) - these are internal questions through the client, the
way the rename wait asks getScanStatus:
  - `getSong` for the song's album, then `getAlbum` for its songs in Navidrome's order (disc, then
    track). Each song carries its suffix and type, and for every client Navidrome doesn't list as
    legacy its `samplingRate` - so songs of another rate aren't looked at further.
  - The rest by small byte ranges of the files themselves, never a whole file: which version each
    song is (the cache's own look, four bytes - so its memory and its 30-second rule are shared),
    each candidate's STREAMINFO from the first 64 KiB, and, when the song is made, the last hundred
    kilobytes or so of the song before and the first of the song after.

A SONG ON THE GRID is one of the album's songs at the same rate and channel count, 16 or 24 bits:
one that is resampled the same way. The phase of a song is album_phase() of the samples of the
songs on the grid before it; its neighbours are the songs right before and after it, when those are
on the grid. Every song works that out from the same listing, so consecutive songs agree.

Everything that goes wrong only costs exactness, never the song: a neighbour that can't be read is
that side without context, logged ("the join with the song before may not be exact") - and the song
made without it is kept under the plan it really had, not this one, so the next play tries again
(player_cache's _make); a song of the album Navidrome answers for but won't serve is off the grid,
like a file that isn't a FLAC; an album Navidrome won't say anything about is the song resampled on
its own. And the plan is KEPT (sticky)
per song version: it is part of the resampled file's cache key, so a Navidrome hiccup that turned a
song being played into a plan without context would start a second make of it - and on the MP4 path,
which has no If-Range, could splice two files under one URL. So a plan that can't be made again
this time is the one last made.
"""

import asyncio
import json

import httpx

from src import resample
from src.api.navidrome_endpoint import NavidromeError, navidrome
from src.flac_mp4 import CannotRepackage, NotFlac, StreamInfo, Unsupported, _parse_streaminfo, _skip_id3v2
from src.logger import logger

#? How long one question to Navidrome may take here, in seconds - the whole of the album's part of
#? a plan, the song's own STREAMINFO, or one side's context. The client waits a minute for a read,
#? for streams; a Navidrome that hangs mustn't hold a song's first bytes that long.
CONTEXT_SECONDS = 10

#? What is read of a file for its STREAMINFO, from its start. A picture in the metadata bigger than
#? this costs one more read, at its end, for where the audio starts.
HEAD_READ = 64 * 1024

#? Reads of one file's metadata before where its audio starts is given up on (a crafted file of
#? many big blocks), a HEAD_READ each - 4 MiB at the most, once per version. Its STREAMINFO is in the
#? first read, and each block bigger than a read after it costs one more: a rip with its booklet
#? embedded carries a picture a page, twenty or thirty of them, and at 8 reads such a song never lent
#? its start to the song before it.
METADATA_READS_MAX = 64

#? A context read bigger than this is not made: a stream whose STREAMINFO claims frames megabytes
#? long. A real 24/192 song's end is a few hundred kilobytes at the most.
CONTEXT_READ_MAX = 8 << 20

#? Songs of an album looked at, at once, when a plan is first made - track 12 has eleven before it.
LOOKS_AT_ONCE = 8

#? How many songs' STREAMINFO is remembered, by version (never stale: a version names one state of
#? a file), and how many albums, songs' albums and plans. Bounded; the oldest go first.
INFOS_KEPT = 4096
ALBUMS_KEPT = 512
PLANS_KEPT = 1024

#? What Navidrome calls a FLAC file (as in player_cache).
FLAC_TYPES = frozenset({"audio/flac", "audio/x-flac"})

_UNKNOWN = object()


class CannotPlan(Exception):
    """The song's own file couldn't be looked at just now: its request goes as it would when
    Navidrome breaks off saying which file it has."""


class Unreadable(Exception):
    """A byte range of a file couldn't be read as asked: changed since it was looked at, or not
    answered as a range."""


def _validator(version) -> str | None:
    """What an If-Range names this version by: its ETag when it is a strong one, else its
    Last-Modified."""
    try:
        modified, etag = json.loads(version.stamp)
    except (TypeError, ValueError):
        return None
    if etag and not etag.startswith("W/"):
        return etag
    return modified or None


def _why(error: BaseException) -> str:
    if isinstance(error, asyncio.TimeoutError):
        return f"Navidrome didn't answer within {CONTEXT_SECONDS} s"
    return str(error) or type(error).__name__


def _is_flac(song: dict) -> bool:
    suffix = str(song.get("suffix") or "").lower()
    kind = str(song.get("contentType") or "").split(";")[0].strip().lower()
    return suffix == "flac" or kind in FLAC_TYPES


def _whole(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _keep(memo: dict, key, value, bound: int) -> None:
    """`value` remembered under `key` as the newest, the oldest forgotten past `bound`."""
    memo.pop(key, None)
    memo[key] = value
    while len(memo) > bound:
        del memo[next(iter(memo))]


#? What can go wrong asking Navidrome something here, short of being cancelled.
_ASKING = (NavidromeError, httpx.HTTPError, asyncio.TimeoutError, Unreadable)


class _NoAlbum(Exception):
    """The album, or a song of it, couldn't be had this time."""


class AlbumContexts:
    """What is known about the albums of songs resampled for the player. One per Mp4Cache."""

    def __init__(self, version_of, clock, seconds: float):
        #? the cache's own _version(): a song's Version, or None when it isn't a FLAC it can wrap
        self._version_of = version_of
        #? the cache's clock, read at every use - a test moves it on - and how long what Navidrome
        #? said is believed on it (VERSION_SECONDS)
        self._clock = clock
        self._seconds = seconds
        #? version key -> (StreamInfo, where its audio starts, or None) - or None: not a FLAC
        self._infos: dict[str, tuple[StreamInfo, int | None] | None] = {}
        #? song id -> (believed until, its album's id); album id -> (believed until, its songs)
        self._albums: dict[str, tuple[float, str]] = {}
        self._listings: dict[str, tuple[float, list[dict]]] = {}
        #? (version key, max rate) -> (believed until, the plan made last) - kept beyond that, as
        #? what a plan that can't be made again falls back on
        self._plans: dict[tuple[str, int], tuple[float, resample.ResamplePlan]] = {}
        #? (version key, max rate) -> the plan being made for it, which every request for it waits on.
        #? Safari's first two bytes and the readout's ask come together on every fresh song, and two
        #? plans made side by side - one of them without its album, after a hiccup only it met - are
        #? two files under one URL, and a splice
        self._making: dict[tuple[str, int], asyncio.Task] = {}
        #? what was said lately, and until when, so a line isn't said on every request
        self._said: dict[tuple, float] = {}

    # ------------------------------------------------------------ the plan

    async def plan(self, version, max_rate: int) -> resample.ResamplePlan | None:
        """
        How this version of the song is resampled under `max_rate` - or None, and it is sent
        exactly as it is: not a FLAC this can read, not above the cap, not a rate or depth that is
        resampled. Raises CannotPlan when its own STREAMINFO couldn't be read just now. Whatever
        about its album can't be had is never raised: the plan goes without it.
        """
        try:
            head = await asyncio.wait_for(self.stream_info(version), CONTEXT_SECONDS)
        except _ASKING as e:
            raise CannotPlan(_why(e)) from e
        if head is None:
            return None
        info, _ = head
        out = resample.output_rate(info.sample_rate, max_rate, info.bits_per_sample)
        if out is None:
            return None
        if not info.total_samples:
            self._say(("no length", version.key), f"player: song {version.song_id} isn't resampled to "
                      f"{resample.khz(out)} - its STREAMINFO doesn't say how many samples it has, which the "
                      f"album's sample grid needs; it is sent as it is")
            return None

        memo = (version.key, max_rate)
        kept = self._plans.get(memo)
        if kept is not None and kept[0] > self._clock():
            return kept[1]
        making = self._making.get(memo)
        #? one of another event loop's (a test's TestClient runs each request on a loop of its own)
        #? can't be waited on here, finished or not
        if making is None or making.done() or making.get_loop() is not asyncio.get_running_loop():
            making = asyncio.ensure_future(self._replan(version, info, out, max_rate, memo))
            self._making[memo] = making

            def forget(done: asyncio.Task) -> None:
                if self._making.get(memo) is done:
                    del self._making[memo]
                if not done.cancelled():
                    done.exception()  # retrieved, so one nobody waited for is never "never retrieved"

            making.add_done_callback(forget)
        #? shielded: a request that hangs up doesn't stop the plan another one waits for
        return await asyncio.shield(making)

    async def _replan(self, version, info: StreamInfo, out: int, max_rate: int, memo) -> resample.ResamplePlan:
        """The plan made again from the song's album - or the one kept, or one made alone, when that
        can't be had. Run once for all the requests waiting on it (plan())."""
        now = self._clock()
        kept = self._plans.get(memo)
        try:
            made = await asyncio.wait_for(self._in_album(version, info, out, max_rate), CONTEXT_SECONDS)
        except (*_ASKING, _NoAlbum) as e:
            if kept is not None:
                #? the plan last made: what the song is already cached, and being played, as
                self._say(("kept", memo), f"player: song {version.song_id}'s album couldn't be looked at again "
                          f"({_why(e)}); it is resampled as it was last time")
                made = kept[1]
            else:
                self._say(("alone", memo), f"player: song {version.song_id} is resampled without its album around "
                          f"it ({_why(e)}) - its joins with the songs beside it may not be exact",
                          warn=True)
                made = resample.ResamplePlan(max_rate=max_rate, source_rate=info.sample_rate, out_rate=out,
                                             channels=info.channels, bits=info.bits_per_sample,
                                             total_samples=info.total_samples)
        _keep(self._plans, memo, (now + self._seconds, made), PLANS_KEPT)
        return made

    async def _in_album(self, version, info: StreamInfo, out: int, max_rate: int) -> resample.ResamplePlan:
        """The plan from the song's album: the phase from the songs on the grid before it, and the
        songs right beside it when they are on it. Raises _NoAlbum, or what asking raises."""
        album = await self._album_of(version.song_id)
        songs = await self._listing(album)
        ids = [str(song.get("id")) for song in songs]
        if version.song_id not in ids:
            raise _NoAlbum("it isn't in its album's listing")
        index = ids.index(version.song_id)

        def may_be_on_grid(i: int) -> bool:
            song = songs[i]
            said = _whole(song.get("samplingRate"))
            return _is_flac(song) and (not said or said == info.sample_rate)

        #? every song before it counts towards the phase; of those after it only the next one matters
        wanted = [i for i in range(min(index + 2, len(songs))) if i != index and may_be_on_grid(i)]
        at_once = asyncio.Semaphore(LOOKS_AT_ONCE)

        async def look(i: int):
            async with at_once:
                try:
                    found = await self._version_of(ids[i])
                    if found is None:
                        return None
                    head = await self.stream_info(found)
                except NavidromeError as e:
                    if e.unreachable:
                        raise
                    #? An ANSWER about that song's file - gone from disk until the next scan,
                    #? unreadable, not found - puts it off the grid, as a file that isn't a FLAC is:
                    #? it can't be played either, so only the joins either side of it go without
                    #? context. Taken for the album not being known, one such song took the grid and
                    #? the context away from every song after it. Navidrome not answering at all is
                    #? still that: the kept plan, or the song alone.
                    self._say(("off grid", ids[i]), f"player: song {ids[i]} isn't counted in its album's "
                              f"sample grid ({_why(e)}) - the joins either side of it may not be exact",
                              warn=True)
                    return None
                return (found, head) if head is not None else None

        looked = await asyncio.gather(*(look(i) for i in wanted))
        on_grid = {}
        for i, got in zip(wanted, looked):
            if got is None:
                continue
            found, (other, _) = got
            if (other.sample_rate, other.channels) == (info.sample_rate, info.channels) and \
                    resample.output_rate(other.sample_rate, max_rate, other.bits_per_sample) == out:
                on_grid[i] = got

        ratio = info.sample_rate // out
        earlier = sum(head[0].total_samples for i, (_, head) in on_grid.items() if i < index)

        def neighbour(i: int) -> resample.Neighbour | None:
            got = on_grid.get(i)
            if got is None:
                return None
            found, (other, offset) = got
            #? a song that doesn't say how long it is counted as 0 towards the phase, so neither of
            #? its joins can be exact: no context across them
            if not other.total_samples:
                return None
            return resample.Neighbour(song_id=found.song_id, version_key=found.key, size=found.size,
                                      validator=_validator(found), info=other, audio_offset=offset)

        return resample.ResamplePlan(max_rate=max_rate, source_rate=info.sample_rate, out_rate=out,
                                     channels=info.channels, bits=info.bits_per_sample,
                                     total_samples=info.total_samples,
                                     phase=resample.album_phase(earlier, ratio),
                                     before=neighbour(index - 1), after=neighbour(index + 1))

    async def _album_of(self, song_id: str) -> str:
        now = self._clock()
        known = self._albums.get(song_id)
        if known is not None and known[0] > now:
            return known[1]
        body = await navidrome.call("getSong", {"id": song_id})
        song = body.get("song")
        album = song.get("albumId") if isinstance(song, dict) else None
        if not album:
            raise _NoAlbum("Navidrome didn't say which album it is in")
        self._albums = {key: value for key, value in self._albums.items() if value[0] > now}
        _keep(self._albums, song_id, (now + self._seconds, str(album)), ALBUMS_KEPT)
        return str(album)

    async def _listing(self, album_id: str) -> list[dict]:
        now = self._clock()
        known = self._listings.get(album_id)
        if known is not None and known[0] > now:
            return known[1]
        body = await navidrome.call("getAlbum", {"id": album_id})
        album = body.get("album")
        songs = album.get("song") if isinstance(album, dict) else None
        if not isinstance(songs, list) or not all(isinstance(song, dict) for song in songs):
            raise _NoAlbum("Navidrome didn't list the album's songs")
        self._listings = {key: value for key, value in self._listings.items() if value[0] > now}
        _keep(self._listings, album_id, (now + self._seconds, songs), ALBUMS_KEPT)
        return songs

    # ------------------------------------------------------------ STREAMINFO

    async def stream_info(self, version) -> tuple[StreamInfo, int | None] | None:
        """
        This version's STREAMINFO, and where its first frame starts (None when that couldn't be
        found out - only the song after the one resampled needs it). None when it isn't a FLAC this
        can read. Remembered by version; a read that failed is not.
        """
        known = self._infos.get(version.key, _UNKNOWN)
        if known is not _UNKNOWN:
            return known
        try:
            head = await self._read_head(version)
        except CannotRepackage:
            head = None
        _keep(self._infos, version.key, head, INFOS_KEPT)
        return head

    async def _read_head(self, version) -> tuple[StreamInfo, int | None]:
        """The metadata at the start of a FLAC file, read a window at a time: any ID3v2 tags in
        front of it, the marker, STREAMINFO, and each block's header until the last."""
        window = _Window(self, version)
        pos = 0
        #? ID3v2 tags in front, as flac_mp4 allows them
        for _ in range(8):
            header = await window.get(pos, 10)
            if not header.startswith(b"ID3"):
                break
            pos += _skip_id3v2(header)
        start = await window.get(pos, 42)
        if not start.startswith(b"fLaC"):
            raise NotFlac("no 'fLaC' marker at the start of the file")
        if start[4] & 0x7F != 0 or int.from_bytes(start[5:8], "big") != 34:
            raise Unsupported("the first metadata block isn't STREAMINFO")
        info = _parse_streaminfo(start[8:42])
        at, last = pos + 42, start[4] & 0x80
        while not last:
            if window.reads >= METADATA_READS_MAX and not window.holds(at, 4):
                return info, None
            header = await window.get(at, 4)
            last = header[0] & 0x80
            at += 4 + int.from_bytes(header[1:4], "big")
        return info, at

    # ------------------------------------------------------------ the context

    async def context(self, plan: resample.ResamplePlan, song_id: str):
        """
        The samples of the plan's neighbours, as the song is made: the last CONTEXT_SAMPLES of the
        song before and the first of the song after, float64 - each None when there is none or it
        couldn't be had, which is said. A song made without a side its plan names isn't what that
        plan says it is, and the cache keeps it under the plan without that side (player_cache's
        _make): so a read that failed once is tried again at a play once the cache's VERSION_SECONDS
        have passed - not asked for at every fresh start before then, and not kept for good.
        """
        async def side(neighbour, read, where: str):
            if neighbour is None:
                return None
            try:
                return await asyncio.wait_for(read(neighbour), CONTEXT_SECONDS)
            except (*_ASKING, resample.CannotResample) as e:
                logger.warning(f"player: song {song_id} is resampled without the song {where} it ({_why(e)}) - "
                               f"the join with the song {where} may not be exact")
                return None

        before, after = await asyncio.gather(side(plan.before, self._tail, "before"),
                                             side(plan.after, self._head, "after"))
        return before, after

    async def _tail(self, neighbour: resample.Neighbour):
        info = neighbour.info
        want = resample.tail_bytes(info)
        if want > CONTEXT_READ_MAX:
            raise Unreadable(f"its frames are too big to read the end of ({want} bytes)")
        floor = neighbour.audio_offset or 0
        start = max(floor, neighbour.size - want)
        data = await self._range(neighbour.song_id, neighbour.size, neighbour.validator, start, neighbour.size - 1)
        tags = resample.trailer_length(data)
        if tags and len(data) - tags < want and start > floor:
            #? a tag appended to the file, bigger than what was read: again, from before it
            start = max(floor, neighbour.size - want - tags)
            if want + tags > CONTEXT_READ_MAX:
                raise Unreadable(f"the tags after its audio are too big to read past ({tags} bytes)")
            data = await self._range(neighbour.song_id, neighbour.size, neighbour.validator, start,
                                     neighbour.size - 1)
        return await asyncio.to_thread(resample.tail_samples, info, data)

    async def _head(self, neighbour: resample.Neighbour):
        info = neighbour.info
        if neighbour.audio_offset is None:
            raise Unreadable("where its audio starts couldn't be found")
        want = resample.head_bytes(info)
        if want > CONTEXT_READ_MAX:
            raise Unreadable(f"its frames are too big to read the start of ({want} bytes)")
        end = min(neighbour.size, neighbour.audio_offset + want)
        data = await self._range(neighbour.song_id, neighbour.size, neighbour.validator,
                                 neighbour.audio_offset, end - 1)
        return await asyncio.to_thread(resample.head_samples, info, data, resample.CONTEXT_SAMPLES,
                                       end >= neighbour.size)

    # ------------------------------------------------------------ reading

    async def _range(self, song_id: str, size: int, validator: str | None, start: int, end: int) -> bytes:
        """
        Bytes `start` to `end` of a song's file, as they were when its version was looked at - a
        file changed since comes back whole for the If-Range, and is never read. Raises Unreadable,
        NavidromeError, or httpx's errors.
        """
        end = min(end, size - 1)
        headers = {"range": f"bytes={start}-{end}"}
        if validator:
            headers["if-range"] = validator
        upstream = await navidrome.open("stream", {"id": song_id, "format": "raw"}, headers)
        try:
            #? a 200 is the whole file: changed since it was looked at, or a range ignored - not read
            if upstream.status_code != 206:
                raise Unreadable("its file changed since it was looked at")
            answered = upstream.headers.get("content-range") or ""
            if not answered.startswith(f"bytes {start}-") or not answered.endswith(f"/{size}"):
                raise Unreadable("Navidrome didn't answer the range asked for")
            wanted, data = end - start + 1, bytearray()
            async for chunk in upstream.aiter_raw():
                data += chunk
                if len(data) >= wanted:
                    break
            if len(data) < wanted:
                raise Unreadable(f"Navidrome sent {len(data)} of the {wanted} bytes asked for")
            return bytes(data[:wanted])
        finally:
            await upstream.aclose()

    def _say(self, what: tuple, line: str, warn: bool = False) -> None:
        """A line said once a VERSION_SECONDS, however many requests run into it."""
        now = self._clock()
        if self._said.get(what, 0) > now:
            return
        self._said = {key: until for key, until in self._said.items() if until > now}
        self._said[what] = now + self._seconds
        (logger.warning if warn else logger.info)(line)


class _Window:
    """One file's bytes from its start, read a window at a time as the metadata is walked."""

    def __init__(self, contexts: AlbumContexts, version):
        self.contexts, self.version = contexts, version
        self.start, self.data, self.reads = 0, b"", 0

    def holds(self, pos: int, n: int) -> bool:
        return self.start <= pos and pos + n <= self.start + len(self.data)

    async def get(self, pos: int, n: int) -> bytes:
        if not self.holds(pos, n):
            if pos + n > self.version.size:
                raise Unsupported("the metadata runs past the end of the file")
            self.reads += 1
            self.data = await self.contexts._range(self.version.song_id, self.version.size,
                                                   _validator(self.version), pos, pos + max(n, HEAD_READ) - 1)
            self.start = pos
        return self.data[pos - self.start:pos - self.start + n]
