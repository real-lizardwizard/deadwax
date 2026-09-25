"""
Lyrics, from LRCLIB, written as a `.lrc` file beside each track.

The SIXTH writer to the user's filesystem, after the organizer, the retag, the hand tag editor,
the artist pictures and the single cover - and built the same way: `plan_lyrics()` reads the
folder and decides, `execute_lyrics()` writes what it was handed and nothing else, and the
network sits between the two in `fetch_album_lyrics()`, which takes its client as an argument so
none of this needs a network to be tested.

Why a FILE beside the track and not a tag inside it, which was James's choice from the two:

  - the audio is not touched. Embedding means rewriting every track's tags to add one field,
    which is a lot of writes to make for something this additive, and it would put the album's
    identity tags through a save for no reason of their own.
  - it is what readers look for first. Navidrome's `LyricsPriority` defaults to
    ".ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded" - a `.lrc` with the audio file's own name is
    found with no configuration at all, the way `artist.*` is. Jellyfin and Kodi read it too.
  - synced lyrics survive. Timestamps in an embedded tag are supported unevenly; in a `.lrc`
    they are the format.

What is written is LRCLIB's own text, untouched: its synced lyrics when it has them, which are
already valid LRC, and its plain lyrics when it doesn't, which a `.lrc` reader shows as unsynced
lines. No header is added - an `[ar:]` line some player doesn't understand would be drawn as a
lyric.

An existing `.lrc` is never replaced unless asked. It may be hand-corrected, or from a source
better than this one, and the same instinct keeps a cover the user chose.

THE LEAD (LYRICS_LEAD_MS, v0.7.1). LRCLIB's timings are set by people tapping along, so a line
tends to be stamped a moment after it is sung. On a song whose lines come less than a second
apart that is enough for a player to show the line just sung - James saw it in Amperfy on Five
Finger Death Punch's "American Capitalist", where every LRCLIB copy agrees to 0.16s, so the data
was consistent and simply late. The lead moves every timestamp EARLIER by a fixed amount as the
file is written. It is written into the timestamps themselves, not as an `[offset:]` tag:
Amperfy reads that tag and never applies it, and a player that did apply it on top of shifted
timestamps would move them twice.

Changing the lead re-times files already saved (`retime`), and that has to be safe to run over
a whole library, repeatedly: see timing_delta(), which is how a file deadwax wrote is told apart
from one somebody corrected, with nothing recorded anywhere.
"""

import asyncio
import re
from contextlib import aclosing
from pathlib import Path

from src.logger import logger
from src.matching import AUDIO_EXTENSIONS, file_extension
from src.organizer import is_within

LYRICS_EXTENSION = ".lrc"

#? How far apart two durations can be and still be the same recording. LRCLIB's own /api/get
#? uses two seconds, so a search result is held to the same rule rather than a looser one - a
#? live version or a radio edit of the same song is exactly what a looser rule would let in.
DURATION_TOLERANCE = 2.0

#? How close a DIFFERENT-length recording of the same song has to be for its words to be used
#? - as plain lyrics, never with its timings. A vinyl pressing runs a few seconds longer than
#? the CD (Dummy's 2014 vinyl "Sour Times" is 245s where LRCLIB's copies are 247-254s): the
#? words are the same and the timings would drift further out with every line. Ten per cent
#? keeps a live version or an extended mix, which can have different words, out.
WORDS_ONLY_TOLERANCE = 0.10

#? How many tracks of one album are looked up at once. LRCLIB asks nothing of its callers but
#? to be reasonable, and answers 503 when leaned on - measured, during a bulk run of 118 tracks
#? at three at a time. Two, and the client backs off and retries a 503.
CONCURRENCY = 2

#? `[mm:ss]`, `[mm:ss.xx]` or `[mm:ss.xxx]` - a line can carry several, for a repeated chorus
TIMESTAMP = re.compile(r"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]")
#? `[ar:Portishead]` and friends: LRC's header tags, which are not lyrics
ID_TAG = re.compile(r"^\[[a-zA-Z#]+:.*\]$")


class LyricsUnavailable(Exception):
    """LRCLIB could not be asked - down, unreachable, or it answered with an error.

    Kept apart from "it has no lyrics for this", which is a fact about the track. The first is
    worth trying again; the second is not, and counting them together would say neither.
    """


def lyrics_filename(audio_name: str) -> str:
    """`01 - Roads.flac` -> `01 - Roads.lrc`. The name every reader looks for."""
    return Path(audio_name).stem + LYRICS_EXTENSION


def has_lyrics_file(audio_name: str, names: set[str]) -> bool:
    """Whether a folder listing (lowercased names) holds this track's `.lrc`."""
    return lyrics_filename(audio_name).lower() in names


# ------------------------------------------------------------------ what to ask LRCLIB


def lookup_from_tags(tags: dict, length: float) -> dict | None:
    """
    What to ask LRCLIB about one file, or None if its tags can't identify it.

    A title and an artist are the least it can be asked by. The track's own artist comes first
    and the album artist second: LRCLIB files a guest spot under whoever sang, and a compilation
    under the track's artist, not "Various Artists".
    """
    title = (tags.get("title") or "").strip()
    artists = []
    for key in ("artist", "albumartist"):
        name = (tags.get(key) or "").strip()
        if name and name not in artists:
            artists.append(name)

    if not title or not artists:
        return None

    return {
        "title": title,
        "artists": artists,
        "album": (tags.get("album") or "").strip(),
        #? 0 when the file doesn't say, and then nothing is held to a duration at all
        "duration": round(float(length or 0), 1),
    }


def read_lookup(path: Path) -> dict | None:
    """lookup_from_tags() for a file on disk."""
    import mutagen

    try:
        audio = mutagen.File(str(path), easy=True)
    except Exception as e:
        logger.debug(f"could not read {path.name} for a lyrics lookup: {e}")
        return None

    if audio is None:
        return None

    def first(key: str) -> str:
        try:
            values = audio.get(key) or []
        except (KeyError, ValueError):
            return ""
        return str(values[0]) if values else ""

    tags = {key: first(key) for key in ("title", "artist", "albumartist", "album")}
    length = getattr(getattr(audio, "info", None), "length", 0) or 0
    return lookup_from_tags(tags, length)


def _fold(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).strip()


def choose_result(results: list[dict], lookup: dict) -> dict | None:
    """
    The search result that is this track, or None.

    Only used when the exact lookup missed - usually because the album title differs (a deluxe
    edition's longer name, or a single the song first came out on). So the album is a
    PREFERENCE here, never a requirement, and the duration is what decides: a result more than
    DURATION_TOLERANCE away is a different recording, however well its name matches.

    Among the survivors: the album matching, then having synced lyrics, then having any.
    """
    duration = lookup.get("duration") or 0
    album = _fold(lookup.get("album", ""))
    title = _fold(lookup.get("title", ""))

    same_song = [result for result in results or [] if isinstance(result, dict)
                 and _fold(result.get("trackName") or result.get("name") or "") == title]

    def off_by(result: dict) -> float:
        return abs(float(result.get("duration") or 0) - duration)

    usable = [result for result in same_song if not duration or off_by(result) <= DURATION_TOLERANCE]

    if not usable:
        #? No recording of this length - but one only a little longer or shorter has the same
        #? words. Its words are taken and its timings are not: `words_only` makes render_lyrics
        #? write plain text, since timings from another recording drift further out every line.
        near = [result for result in same_song
                if duration and off_by(result) <= duration * WORDS_ONLY_TOLERANCE
                and (result.get("plainLyrics") or result.get("syncedLyrics"))]
        if not near:
            return None
        return {**min(near, key=off_by), "words_only": True}

    def rank(result: dict) -> tuple:
        return (
            _fold(result.get("albumName") or "") == album,
            bool(result.get("syncedLyrics")),
            bool(result.get("plainLyrics")) or bool(result.get("instrumental")),
        )

    return max(usable, key=rank)


def render_lyrics(result: dict | None, lead_ms: int = 0) -> tuple[str | None, str]:
    """
    What to write for one LRCLIB answer, and what kind it is.

    Kinds: `synced`, `plain`, `instrumental` (LRCLIB says there are no words, so nothing is
    written - an invented "♪ instrumental ♪" line would be a lyric nobody sang), and `missing`.

    `lead_ms` moves synced lyrics earlier - see the module note. Plain lyrics have no times to
    move.
    """
    if not result:
        return None, "missing"

    synced = (result.get("syncedLyrics") or "").strip()
    if synced and not result.get("words_only"):
        return shift_lrc(_normalise(synced), lead_ms), "synced"

    plain = (result.get("plainLyrics") or "").strip()
    if plain:
        return _normalise(plain), "plain"

    if synced:
        #? words-only, with no plain copy on LRCLIB: the synced text with its timings taken out
        words = "\n".join(line["text"] for line in parse_lrc(synced))
        if words.strip():
            return _normalise(words), "plain"

    if result.get("instrumental"):
        return None, "instrumental"

    return None, "missing"


def _normalise(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n").strip() + "\n"


def shift_lrc(text: str, lead_ms: int) -> str:
    """
    Every timestamp in `text` moved `lead_ms` EARLIER (later, if negative), and nothing else.

    A line cannot start before the song does, so a time the lead would take below zero is held
    at zero. Each stamp keeps its own precision - LRCLIB writes hundredths, some files write
    thousandths - so a file shifted by zero is byte-for-byte the file it was.
    """
    if not lead_ms:
        return text

    def moved(match: re.Match) -> str:
        minutes, seconds = match.group(1), match.group(2).replace(":", ".")
        total = int(minutes) * 60_000 + round(float(seconds) * 1000)
        total = max(0, total - lead_ms)

        if len(seconds.partition(".")[2]) >= 3:
            whole, fraction = divmod(total, 1000)
            return f"[{whole // 60:02d}:{whole % 60:02d}.{fraction:03d}]"

        #? hundredths, LRCLIB's own precision - rounded as a whole, so 59.996s becomes 1:00.00
        whole, fraction = divmod(round(total / 10), 100)
        return f"[{whole // 60:02d}:{whole % 60:02d}.{fraction:02d}]"

    return TIMESTAMP.sub(moved, text)


def _timed(lines: list[dict]) -> list[dict]:
    """Every line but the blank untimed ones - the gaps between verses."""
    return [line for line in lines if line["time"] is not None or line["text"]]


#? How far a re-computed time may sit from the file's and still count as the same stamp: the
#? rounding of a lead into hundredths, with room to spare. Far below any real editing.
RETIME_SLACK_MS = 15


def timing_delta(existing: str, source: str) -> int | None:
    """
    How many milliseconds EARLIER than `source` the lines in `existing` are, or None.

    None means `existing` is not `source` moved by a constant: different words, a different
    number of lines, or timings changed line by line - which is what a hand correction or
    another source looks like. That is the whole test for "deadwax wrote this and nobody has
    touched it since", and it needs nothing recorded: a file written at any earlier lead,
    including 0.7.0's, which had none, passes it with that lead as the answer.

    Lines the lead pushed against zero are allowed for: they sit at 0, not at their time minus
    the lead.
    """
    #? blank lines with no time are the gaps between verses, which LRCLIB writes into synced
    #? lyrics too - counting them as "unsynced" made every song with verses look hand-edited,
    #? which is how Portishead's "Wandering Star" was first left alone
    mine, theirs = _timed(parse_lrc(existing)), _timed(parse_lrc(source))

    if (not mine or len(mine) != len(theirs)
            or any(line["time"] is None for line in mine + theirs)
            or [line["text"] for line in mine] != [line["text"] for line in theirs]):
        return None

    gaps = sorted(round((b["time"] - a["time"]) * 1000)
                  for a, b in zip(mine, theirs) if a["time"] > 0)
    delta = gaps[len(gaps) // 2] if gaps else 0

    for a, b in zip(mine, theirs):
        expected = max(0, round(b["time"] * 1000) - delta)
        if abs(expected - round(a["time"] * 1000)) > RETIME_SLACK_MS:
            return None

    return delta


# ------------------------------------------------------------------ reading what is on disk


def parse_lrc(text: str) -> list[dict]:
    """
    Lines of lyrics, each `{time, text}` - time in seconds, or None for an unsynced line.

    A line carrying several timestamps (a chorus written once) becomes one line per timestamp,
    and synced lines come back in time order. Header tags (`[ar:...]`, `[offset:...]`) are not
    lyrics and are dropped. Plain text is simply every line with no time.
    """
    lines: list[dict] = []

    for raw in (text or "").replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        line = raw.strip()
        stamps = TIMESTAMP.findall(line)

        if not stamps:
            if ID_TAG.match(line):
                continue
            lines.append({"time": None, "text": line})
            continue

        words = TIMESTAMP.sub("", line).strip()
        for minutes, seconds in stamps:
            lines.append({"time": round(int(minutes) * 60 + float(seconds.replace(":", ".")), 3),
                          "text": words})

    #? trim blank lines at either end, which LRC files commonly carry
    while lines and not lines[0]["text"] and lines[0]["time"] is None:
        lines.pop(0)
    while lines and not lines[-1]["text"] and lines[-1]["time"] is None:
        lines.pop()

    if lines and all(line["time"] is not None for line in lines):
        lines.sort(key=lambda line: line["time"])

    return lines


def embedded_lyrics(path: Path) -> str | None:
    """
    Lyrics a file carries in its own tags, from whatever wrote them there. Read, never written.

    Every container spells it differently: Vorbis comments say LYRICS (or UNSYNCEDLYRICS, which
    some taggers use), ID3 keeps them in USLT frames, MP4 in the ©lyr atom.
    """
    import mutagen

    try:
        audio = mutagen.File(str(path))
    except Exception:
        return None

    tags = getattr(audio, "tags", None)
    if not tags:
        return None

    try:
        for key in ("LYRICS", "UNSYNCEDLYRICS", "lyrics", "unsyncedlyrics", "\xa9lyr"):
            if key in tags:
                value = tags[key]
                text = value[0] if isinstance(value, list) else value
                if str(text).strip():
                    return str(text)

        for key in list(tags.keys()):
            if str(key).startswith("USLT"):
                text = getattr(tags[key], "text", "")
                if str(text).strip():
                    return str(text)
    except Exception:
        return None

    return None


def read_track_lyrics(album_path: str, library_root: str, filename: str) -> dict | None:
    """
    One track's lyrics as the track viewer shows them. None if the album or file isn't there.

    The `.lrc` beside the file wins, as it does in Navidrome: it is what deadwax writes, and
    what a player reading the folder will show. Tags inside the file are the fallback.

    `filename` is matched against a LISTING of the folder, never joined onto a path first - the
    same rule the hand tag editor uses, so `../` goes nowhere.
    """
    directory = _album_directory(album_path, library_root)
    if directory is None:
        return None

    entries = _listing(directory)
    audio = next((e for e in entries if e.name == filename
                  and file_extension(e.name) in AUDIO_EXTENSIONS), None)
    if audio is None:
        return None

    sidecar = next((e for e in entries if e.name.lower() == lyrics_filename(filename).lower()), None)

    text, source = None, None
    if sidecar is not None:
        try:
            text, source = sidecar.read_text(encoding="utf-8", errors="replace"), "file"
        except OSError as e:
            logger.warning(f"could not read {sidecar}: {e}")

    if text is None:
        embedded = embedded_lyrics(audio)
        if embedded:
            text, source = embedded, "embedded"

    lines = parse_lrc(text) if text else []

    return {
        "filename": filename,
        "source": source,
        "lyrics_file": sidecar.name if sidecar is not None else None,
        "synced": bool(lines) and any(line["time"] is not None for line in lines),
        "lines": lines,
    }


# ------------------------------------------------------------------ plan and execute


def _album_directory(album_path: str, library_root: str) -> Path | None:
    root = Path(library_root or "")
    directory = root / (album_path or "")
    if not library_root or not album_path or not is_within(directory, root) or not directory.is_dir():
        return None
    return directory


def _listing(directory: Path) -> list[Path]:
    try:
        return sorted(p for p in directory.iterdir() if p.is_file())
    except OSError as e:
        logger.warning(f"could not list {directory}: {e}")
        return []


def plan_lyrics(
    album_path: str, library_root: str, replace: bool = False, retime: bool = False,
) -> dict:
    """
    What fetching lyrics for this album would look up, and which tracks it would leave alone.

    Reads the folder and the tags; writes nothing and asks nothing of the network.

    `retime` turns it round: only tracks that HAVE a `.lrc` are looked at, and only synced ones
    - a plain file has no times to move, so it is settled here without asking LRCLIB anything.
    """
    directory = _album_directory(album_path, library_root)
    if directory is None:
        return {"album_path": album_path, "tracks": [], "problem": "that album is not inside the library"}

    entries = _listing(directory)
    names = {entry.name.lower() for entry in entries}

    tracks = []
    for entry in entries:
        if file_extension(entry.name) not in AUDIO_EXTENSIONS:
            continue

        existing = has_lyrics_file(entry.name, names)
        lookup = read_lookup(entry)
        current = None

        if retime:
            current = _read_lyrics_file(directory, entries, entry.name) if existing else None
            if not existing:
                skip = "absent"
            elif not current or not TIMESTAMP.search(current):
                skip = "plain"
            elif lookup is None:
                skip = "untagged"
            else:
                skip = None
        elif existing and not replace:
            skip = "kept"
        elif lookup is None:
            skip = "untagged"
        else:
            skip = None

        tracks.append({
            "filename": entry.name,
            "lyrics_file": lyrics_filename(entry.name),
            "existing": existing,
            "current": current,
            "lookup": lookup,
            "skip": skip,
        })

    return {"album_path": album_path, "tracks": tracks, "problem": None}


def _read_lyrics_file(directory: Path, entries: list[Path], audio_name: str) -> str | None:
    wanted = lyrics_filename(audio_name).lower()
    sidecar = next((e for e in entries if e.name.lower() == wanted), None)
    if sidecar is None:
        return None
    try:
        return sidecar.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        logger.warning(f"could not read {sidecar}: {e}")
        return None


def execute_lyrics(
    album_path: str, library_root: str, texts: dict[str, str], replace: bool = False,
) -> dict:
    """
    Write `texts` - audio filename -> lyrics - as `.lrc` files, and nothing else.

    Containment is re-checked here and every filename must be an audio file in the folder's own
    listing, rather than trusting the plan: this is the function that writes, so it is the one
    that has to be sure. An existing `.lrc` is left alone unless `replace`.
    """
    directory = _album_directory(album_path, library_root)
    if directory is None:
        return {"written": [], "problems": ["that album is not inside the library"]}

    entries = _listing(directory)
    audio = {e.name for e in entries if file_extension(e.name) in AUDIO_EXTENSIONS}
    names = {e.name.lower() for e in entries}

    written, problems = [], []

    for filename, text in texts.items():
        if filename not in audio:
            problems.append(f"{filename} is not a track in this album")
            continue

        target = directory / lyrics_filename(filename)

        if has_lyrics_file(filename, names) and not replace:
            continue

        try:
            target.write_text(text, encoding="utf-8")
            written.append(target.name)
        except OSError as e:
            logger.error(f"could not write {target}: {e}")
            problems.append(f"could not write {target.name}: {e}")

    return {"written": written, "problems": problems}


async def fetch_album_lyrics(
    album_path: str, library_root: str, client, replace: bool = False,
    lead_ms: int = 0, retime: bool = False,
) -> dict:
    """
    Look up and write lyrics for every track of one album that needs them.

    `client` is anything with `async find(lookup) -> dict | None` that raises LyricsUnavailable
    when it could not ask - the LRCLIB client in production, a stand-in in the tests.

    Every track's outcome is reported, and the kinds are kept apart because they mean different
    things: `written`/`replaced` happened; `kept` is a `.lrc` already there; `instrumental` and
    `missing` are facts about the track that asking again won't change; `failed` is worth asking
    again; `untagged` needs the tags fixing first.

    `retime` re-times the `.lrc` files already there to `lead_ms` instead, and only those that
    are LRCLIB's lyrics untouched (timing_delta): `retimed` were rewritten, `unchanged` were
    already at this lead, `custom` are left alone because they are not LRCLIB's timings any
    more - corrected by hand, from somewhere else, or LRCLIB's copy has since changed - and
    `plain` have no times to move.
    """
    plan = await asyncio.to_thread(plan_lyrics, album_path, library_root, replace, retime)

    if plan["problem"]:
        return {"album_path": album_path, "tracks": [], "problem": plan["problem"], **_counts([])}

    semaphore = asyncio.Semaphore(CONCURRENCY)

    async def look_up(track: dict) -> tuple[dict, str | None]:
        if track["skip"]:
            return {"filename": track["filename"], "outcome": track["skip"]}, None

        if retime:
            #? the entry this file was written FROM - whichever one it is a constant shift of
            async with semaphore:
                try:
                    source, delta = await _find_source(client, track["lookup"], track["current"])
                except LyricsUnavailable as e:
                    return {"filename": track["filename"], "outcome": "failed", "detail": str(e)}, None

            if source is None:
                return {"filename": track["filename"], "outcome": "custom"}, None
            if abs(delta - lead_ms) <= RETIME_SLACK_MS:
                return {"filename": track["filename"], "outcome": "unchanged"}, None
            text, _ = render_lyrics(source, lead_ms)
            return {"filename": track["filename"], "outcome": "retimed", "synced": True}, text

        async with semaphore:
            try:
                result = await client.find(track["lookup"])
            except LyricsUnavailable as e:
                return {"filename": track["filename"], "outcome": "failed", "detail": str(e)}, None

        text, kind = render_lyrics(result, lead_ms)
        if text is None:
            return {"filename": track["filename"], "outcome": kind}, None

        outcome = "replaced" if track["existing"] else "written"
        return {"filename": track["filename"], "outcome": outcome, "synced": kind == "synced"}, text

    answers = await asyncio.gather(*(look_up(track) for track in plan["tracks"]))

    texts = {entry["filename"]: text for entry, text in answers if text is not None}
    #? a re-time rewrites files that are there by definition, so it always replaces
    results = await asyncio.to_thread(execute_lyrics, album_path, library_root, texts, replace or retime)

    written = set(results["written"])
    outcomes = []
    for entry, text in answers:
        #? a write that didn't happen is not a lyric on disk, whatever the lookup found
        if text is not None and lyrics_filename(entry["filename"]) not in written:
            entry = {**entry, "outcome": "failed", "detail": "could not be written"}
        outcomes.append(entry)

    summary = {"album_path": album_path, "tracks": outcomes, "problem": None,
               "problems": results["problems"], **_counts(outcomes)}

    if retime:
        if summary["retimed"] or summary["failed"]:
            logger.info(
                f"lyrics for {Path(album_path).name}: {summary['retimed']} re-timed to a "
                f"{lead_ms}ms lead"
                + (f", {summary['custom']} left alone" if summary["custom"] else "")
                + (f", {summary['failed']} failed" if summary["failed"] else ""),
                extra={"frontend": True},
            )
        return summary

    found = summary["written"] + summary["replaced"]
    if found or summary["failed"]:
        logger.info(
            f"lyrics for {Path(album_path).name}: {found} saved"
            + (f" ({summary['synced']} synced)" if summary["synced"] else "")
            + (f", {summary['missing']} not on LRCLIB" if summary["missing"] else "")
            + (f", {summary['failed']} failed" if summary["failed"] else ""),
            extra={"frontend": True},
        )

    return summary


async def _find_source(client, lookup: dict, existing: str) -> tuple[dict | None, int | None]:
    """
    The LRCLIB entry `existing` was written from, and the lead it was written at - or (None, None).

    Asks batch by batch and stops at the first match, so the usual case costs one request. A
    client without batches (the tests' stand-in) is asked the ordinary way.
    """
    if hasattr(client, "candidates"):
        #? closed on the way out, so stopping early never leaves a request half asked
        async with aclosing(client.candidates(lookup)) as batches:
            async for batch in batches:
                source, delta = _source_of(existing, batch)
                if source is not None:
                    return source, delta
        return None, None

    found = await client.find(lookup)
    return _source_of(existing, [found] if found else [])


def _source_of(existing: str, entries: list[dict]) -> tuple[dict | None, int | None]:
    """The first entry whose synced lyrics `existing` is a constant shift of, and that shift."""
    for entry in entries:
        synced = (entry or {}).get("syncedLyrics") or ""
        if not synced:
            continue
        delta = timing_delta(existing, _normalise(synced))
        if delta is not None:
            return {**entry, "words_only": False}, delta
    return None, None


def _counts(outcomes: list[dict]) -> dict:
    counts = {kind: 0 for kind in
              ("written", "replaced", "kept", "instrumental", "missing", "failed", "untagged",
               "retimed", "unchanged", "custom", "plain", "absent")}
    for entry in outcomes:
        counts[entry["outcome"]] = counts.get(entry["outcome"], 0) + 1
    counts["synced"] = sum(1 for entry in outcomes if entry.get("synced"))
    return counts
