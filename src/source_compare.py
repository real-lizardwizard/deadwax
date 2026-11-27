"""
How one source of a download differs from another, in a listener's words - damaged downloads (asked for, 27 Nov).

James: "I want to know if the next peer is as good of a match as the first." / "Actually I want it to tell me the
differences in the next peer." So whenever a job has a next source - the one a damaged download moves to by itself
(poller._refuse_damaged), and the one "try the next peer" would move any failed job to (/jobs' `next_source`) - it
is described against the source it replaces: its own facts first, then only what differs, each said "new, was old".
Better is said the same way as worse: "FLAC 16/44.1, was MP3 320" and "MP3 320, was FLAC 16/44.1".

What is compared, in this order:

- quality: the format, and the bit depth and rate (lossless) or the bitrate (lossy) - as the app's cards say it, but
  without the "k": "FLAC 16/44.1", "FLAC 24-bit", "MP3 320", "MP3 VBR 245";
- songs: the release's audio tracks the folder holds, and which are missing (matching.missing_tracks);
- extra files: files paired with no track ("13 files for 11 songs, was 11");
- edition words in the folder's path (matching.detect_edition_tags): "folder says Deluxe, was nothing";
- the match score, and the parts of it that moved by more than SIGNAL_MOVED points;
- size, when it differs by SIZE_SHARE or more; when it can start ("now", "after 4 others", "soon"); and the speed
  deadwax measured from each (peer_speed), only when both were measured and one is SPEED_FACTOR times the other.

AS GOOD A MATCH (James chose "Stricter"): the same quality words, every track held, the same edition words, and a
match score at least as high. Anything else is A WEAKER MATCH. A score that can't be compared (a job from before
scores were kept) is left out of the test and said so in `notes`; size, start and speed are never part of it.

Pure: dicts in, dicts and words out.
"""

from src.matching import (LOSSLESS_EXTENSIONS, audio_tracks, detect_edition_tags, file_extension, is_audio,
                          match_tracks_to_files, missing_tracks, split_remote_path)

AS_GOOD = "as_good"
WEAKER = "weaker"
MATCH_WORDS = {AS_GOOD: "as good a match", WEAKER: "a weaker match"}
SAME = "same quality, songs and edition"

#? the parts of the score, as the app's Match details chips name them (ui/src/lib/candidates.ts SIGNAL_LABELS)
SIGNAL_WORDS = {
    "name_match": "folder name",
    "title_match": "track names",
    "track_count": "track count",
    "duration_match": "track lengths",
    "edition": "edition",
    "format": "format",
    "peer": "availability",
}
#? a part of the score is named when it moved by more than this many points (of 100)
SIGNAL_MOVED = 5
#? sizes are said to differ when one is this share larger than the other - two rips of one album are never the
#? same size to the byte, and a few MB either way says nothing
SIZE_SHARE = 0.10
#? measured speeds, when one is this many times the other - every measurement differs a little
SPEED_FACTOR = 1.5
#? missing songs named in full before "and N more"
MISSING_NAMED = 3


# --- one source's facts --------------------------------------------------------------------------------------

def source_facts(source: dict, tracks: list[dict] | None, speed: float | None = None) -> dict:
    """
    What one source is: `source` as a job or a runner-up keeps it - {username, directory, files, quality, score,
    signals, has_free_slot, queue_length}, any of them missing - `tracks` the release's tracklist, `speed` the
    rate deadwax measured from the peer (bytes a second) or None.
    """
    files = [f for f in source.get("files") or [] if isinstance(f, dict)]
    tracks = [t for t in tracks or [] if isinstance(t, dict)]
    mapping = match_tracks_to_files(tracks, files) if tracks else {}
    audio = audio_tracks(tracks) if tracks else []
    missing = missing_tracks(tracks, mapping) if tracks else []
    score = source.get("score")
    free = source.get("has_free_slot")
    queue = source.get("queue_length")
    return {
        "username": source.get("username") or "",
        "directory": source.get("directory") or "",
        "quality": quality_words(source.get("quality") or {}, files),
        "songs": max(0, len(audio) - len(missing)) if tracks else None,
        "of": len(audio) if tracks else None,
        "missing": [t.get("title") or f"track {t.get('position')}" for t in missing],
        "files": len(files),
        #? files no track was paired with - with no tracklist, none can be said to be extra
        "extra": max(0, len(files) - len(mapping)) if tracks else 0,
        "edition": sorted(detect_edition_tags(source.get("directory") or "")),
        "size": sum(int(f.get("size") or 0) for f in files),
        "score": float(score) if isinstance(score, (int, float)) and not isinstance(score, bool) else None,
        "signals": {k: v for k, v in (source.get("signals") or {}).items() if isinstance(v, (int, float))},
        "start": start_words(free, queue),
        "speed": float(speed) if speed else None,
    }


def quality_words(quality: dict, files: list[dict] | None = None) -> str:
    """
    A source's quality as the app's cards say it, less the "k": "FLAC 16/44.1", "FLAC 16-24/44.1-96", "FLAC 24-bit",
    "FLAC 96 kHz", "MP3 320", "MP3 VBR 245", the format alone when nothing more was reported - the formats from the
    files' names when the candidate's quality wasn't kept - and "" with no format at all. Only what was reported.
    """
    formats = [str(f).lower() for f in quality.get("formats") or [] if f]
    if not formats:
        formats = sorted({file_extension(split_remote_path(f.get("filename", ""))[1])
                          for f in files or [] if is_audio(split_remote_path(f.get("filename", ""))[1])})
    formats = sorted(set(formats))
    if not formats:
        return ""
    named = ", ".join(f.upper() for f in formats)
    if all(f in LOSSLESS_EXTENSIONS for f in formats):
        depth = _span(quality.get("bit_depths"), _number)
        rate = _span(quality.get("sample_rates"), lambda hz: _number(hz / 1000))
        if depth and rate:
            return f"{named} {depth}/{rate}"
        if depth:
            return f"{named} {depth}-bit"
        if rate:
            return f"{named} {rate} kHz"
        return named
    bitrate = _span(quality.get("bitrates"), _number)
    if not bitrate:
        return named
    return f"{named} {'VBR ' if quality.get('variable_bitrate') else ''}{bitrate}"


def _span(values, show) -> str:
    numbers = [v for v in values or [] if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0]
    if not numbers:
        return ""
    low, high = min(numbers), max(numbers)
    return show(low) if low == high else f"{show(low)}-{show(high)}"


def _number(value: float) -> str:
    """44.1 as 44.1, 48.0 as 48 - as the app's trimRate."""
    rounded = round(float(value), 1)
    return str(int(rounded)) if rounded == int(rounded) else str(rounded)


def start_words(free_slot, queue_length) -> str | None:
    """When it can start, as the app's Starts says it: "now" (a free slot), "after 3 others", "soon" - None unknown."""
    if free_slot is None and queue_length is None:
        return None
    if free_slot:
        return "now"
    ahead = int(queue_length or 0)
    if ahead > 0:
        return f"after {ahead} {'other' if ahead == 1 else 'others'}"
    return "soon"


def size_words(size: int) -> str:
    """As the app's formatSize: "412 MB", "1.2 GB"."""
    mb = size / (1024 * 1024)
    if mb < 1024:
        return f"{_half_up(mb)} MB"
    return f"{mb / 1024:.1f} GB"


def speed_words(speed: float) -> str:
    """As the app's formatSpeed, with "about": "about 300 KB/s", "about 1.2 MB/s"."""
    kb = speed / 1024
    if kb < 1024:
        return f"about {_half_up(kb)} KB/s"
    return f"about {kb / 1024:.1f} MB/s"


def _half_up(value: float) -> int:
    """Math.round's rounding, which Python's round() (to even) is not."""
    return int(value + 0.5)


def _percent(score: float) -> int:
    return _half_up(score * 100)


# --- two sources compared ------------------------------------------------------------------------------------

def compare(new: dict, old: dict) -> dict:
    """
    How `new` differs from `old`, both source_facts(): {verdict, match, differences: [{what, now, was, words}],
    detail, notes}. `detail` is the words after "as good a match: " or "a weaker match: " - "same quality, songs and
    edition" first when those are, then every difference, joined by " · ".
    """
    differences = []
    notes = []

    def differ(what: str, now: str, was: str, words: str | None = None) -> None:
        differences.append({"what": what, "now": now, "was": was, "words": words or f"{now}, was {was}"})

    same_quality = bool(new["quality"]) and new["quality"] == old["quality"]
    if new["quality"] != old["quality"]:
        differ("quality", new["quality"] or "quality not known", old["quality"] or "not known")
    elif not new["quality"]:
        notes.append("no quality to compare")

    if new["of"] is None:
        #? no tracklist (a manual search's download): the files are all there is to count
        every_track = new["files"] >= old["files"]
        if new["files"] != old["files"]:
            differ("files", f"{new['files']} files", str(old["files"]))
        notes.append("no tracklist to count songs against")
    else:
        every_track = not new["missing"]
        if (new["songs"], new["missing"]) != (old["songs"], old["missing"]):
            differ("songs", _songs_words(new), _songs_held(old))
        if new["extra"] != old["extra"]:
            differ("files", f"{new['files']} files for {new['of']} songs", str(old["files"]))

    same_edition = new["edition"] == old["edition"]
    if not same_edition:
        differ("edition", f"folder says {_edition_words(new['edition'])}", _edition_words(old["edition"]))

    score_ok = True
    if new["score"] is None or old["score"] is None:
        notes.append("no match score to compare")
    else:
        score_ok = new["score"] >= old["score"]
        if _percent(new["score"]) != _percent(old["score"]):
            moved = _moved_parts(new["signals"], old["signals"])
            now = f"match {_percent(new['score'])}%"
            was = f"{_percent(old['score'])}%"
            differ("score", now, was, f"{now}, was {was}" + (f" ({moved})" if moved else ""))

    if new["size"] and old["size"] and abs(new["size"] - old["size"]) >= SIZE_SHARE * min(new["size"], old["size"]):
        differ("size", size_words(new["size"]), size_words(old["size"]))

    if new["start"] and old["start"] and new["start"] != old["start"]:
        differ("start", f"starts {new['start']}", old["start"])

    if new["speed"] and old["speed"] and max(new["speed"], old["speed"]) >= SPEED_FACTOR * min(new["speed"], old["speed"]):
        differ("speed", speed_words(new["speed"]), speed_words(old["speed"]).removeprefix("about "))

    as_good = same_quality and every_track and same_edition and score_ok
    verdict = AS_GOOD if as_good else WEAKER
    parts = ([SAME] if as_good else []) + [d["words"] for d in differences]
    return {
        "verdict": verdict,
        "match": MATCH_WORDS[verdict],
        "differences": differences,
        "detail": " · ".join(parts) or SAME,
        "notes": notes,
    }


def _songs_held(facts: dict) -> str:
    if not facts["missing"]:
        return f"all {facts['of']}"
    return f"{facts['songs']} of {facts['of']}"


def _songs_words(facts: dict) -> str:
    """ "all 11 songs", "10 of 11 songs (missing: Krakow)", "7 of 11 songs (missing: A, B, C and 1 more)"."""
    noun = "song" if facts["of"] == 1 else "songs"
    if not facts["missing"]:
        return f"all {facts['of']} {noun}"
    named = facts["missing"][:MISSING_NAMED]
    more = len(facts["missing"]) - len(named)
    listed = ", ".join(named) + (f" and {more} more" if more else "")
    return f"{facts['songs']} of {facts['of']} {noun} (missing: {listed})"


def _edition_words(labels: list[str]) -> str:
    """ "Deluxe", "Super Deluxe and Remaster", "nothing" - matching's labels in a sentence's case."""
    if not labels:
        return "nothing"
    return " and ".join(" ".join(word.capitalize() for word in label.split()) for label in labels)


def _moved_parts(new: dict, old: dict) -> str:
    """The parts of the score that moved by more than SIGNAL_MOVED points: "track lengths 70%, was 100%"."""
    moved = []
    for name, word in SIGNAL_WORDS.items():
        now, was = new.get(name), old.get(name)
        if now is None or was is None:
            continue
        if abs(_percent(now) - _percent(was)) > SIGNAL_MOVED:
            moved.append(f"{word} {_percent(now)}%, was {_percent(was)}%")
    return "; ".join(moved)


# --- what /jobs and the notice carry --------------------------------------------------------------------------

def lead(facts: dict) -> str:
    """The new source's own facts first: "sofaking · FLAC 16/44.1 · 11 of 11 songs · match 95%"."""
    parts = [facts["username"]]
    if facts["quality"]:
        parts.append(facts["quality"])
    if facts["of"] is not None:
        parts.append(f"{facts['songs']} of {facts['of']} {'song' if facts['of'] == 1 else 'songs'}")
    if facts["score"] is not None:
        parts.append(f"match {_percent(facts['score'])}%")
    return " · ".join(parts)


def next_source(new: dict, old: dict) -> dict:
    """
    /jobs' `next_source` (and a damaged download's notice): the next source's facts and how they differ from the
    source it would replace - {username, directory, replaces, lead, verdict, match, differences, summary, detail,
    notes, facts, was}. `summary` stands alone: "Same quality, songs and edition as glassbeads" when nothing
    differs, else "As good a match: ..." or "A weaker match: ...".
    """
    compared = compare(new, old)
    if not compared["differences"] and compared["verdict"] == AS_GOOD:
        summary = f"Same quality, songs and edition as {old['username']}"
    else:
        summary = f"{compared['match'][0].upper()}{compared['match'][1:]}: {compared['detail']}"
    return {
        "username": new["username"],
        "directory": new["directory"],
        "replaces": old["username"],
        "lead": lead(new),
        **compared,
        "summary": summary,
        "facts": new,
        "was": old,
    }


def moved_words(compared: dict) -> str:
    """What a move to the next source adds to a message: "Now coming from sofaking, as good a match: same quality,
    songs and edition." - `compared` a next_source()."""
    return f"Now coming from {compared['username']}, {compared['match']}: {compared['detail']}."
