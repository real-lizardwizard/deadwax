"""
How one source of a download differs from another, in a listener's words - damaged downloads (asked for, 27 Nov).

James: "I want to know if the next peer is as good of a match as the first." / "Actually I want it to tell me the
differences in the next peer." So whenever a job has a next source - the one a damaged download moves to by itself
(poller._refuse_damaged), and the one "try the next peer" would move any failed job to (/jobs' `next_source`) - it
is described against the source it replaces: its own facts first, then only what differs, each said "new, was old"
(the design's table, deadwax-plans/damaged-downloads.md). Better is said the same way as worse.

What is compared, in this order, each a difference only when it differs:

- quality: "MP3 320, was FLAC 16/44.1" - the format, and the bit depth and rate (lossless) or the bitrate (lossy),
  as the app's cards say it without the "k". No quality known on either side is no difference.
- songs: the release's audio tracks the folder holds - "10 of 11 songs, was all 11 (missing: Krakow)". The same
  songs missing from both is no difference.
- extra files, paired with no track: "13 files for 11 songs, was 11".
- edition words in the folder's path (matching.detect_edition_tags): "folder says Deluxe, the first said nothing".
- the match score, compared at the whole percent shown, and the parts of it that moved by more than SIGNAL_MOVED
  points: "match 81%, was 96% (lengths 70, was 100)".
- size beyond SIZE_SHARE; when it can start ("4th in their queue, the first had a free slot"); and the speed
  deadwax measured from each (peer_speed), only when both were measured, beyond SPEED_FACTOR.

THE SCORE IS DEADWAX'S OWN (review): both sources scored here by matching.score_candidate, from the job's stored
release and each source's files - never a score a client sent, which the iPhone and Mac apps don't send at all.
Availability ("peer") is left out (matching.blend without it): it isn't the folder's match to the release, and
when it can start is said on its own. A score that can't be made - no files, no release - is "not known", and an
unknown score is a difference of kind (below): it never allows "as good" or "better".

THE VERDICT comes from the differences listed and nothing else - one source of truth, so it is never "weaker" with
nothing named. Each difference is of a kind: worse, different, better, or neither (size, start, speed). First that
applies wins (App Design's ruling, 27 Nov - James's "Stricter" defined "as good"):

1. "a weaker match": something is worse - lossy for lossless, a lower bit depth or rate, songs missing, a lower score;
2. "a different match": nothing worse, but not the same thing - other edition words, extra files, or quality or a
   score not known on one side;
3. "a better match": nothing worse or different in kind, and the quality or the score higher;
4. "as good a match": the same by the strict rule - same quality, every song the first had, same edition words, a
   score at least as high.

The differences of the kind that decided come first, then the rest in the table's order.

Pure: dicts in, dicts and words out.
"""

from src.matching import (LOSSLESS_EXTENSIONS, audio_tracks, blend, detect_edition_tags, file_extension, is_audio,
                          match_tracks_to_files, missing_tracks, score_candidate, split_remote_path)

AS_GOOD = "as_good"
BETTER = "better"
DIFFERENT = "different"
WEAKER = "weaker"
MATCH_WORDS = {AS_GOOD: "as good a match", BETTER: "a better match", DIFFERENT: "a different match",
               WEAKER: "a weaker match"}
#? each difference's kind, and the verdict it makes when it is the first that applies
WORSE = "worse"
VERDICT_OF = ((WORSE, WEAKER), (DIFFERENT, DIFFERENT), (BETTER, BETTER))
SAME = "same quality, songs and edition"

#? the parts of the score, short, as the design's table says one ("lengths 70, was 100") - availability ("peer") is
#? not part of the score compared (THE SCORE above)
SIGNAL_WORDS = {
    "name_match": "folder name",
    "title_match": "titles",
    "track_count": "count",
    "duration_match": "lengths",
    "edition": "edition",
    "format": "format",
}
#? JUDGEMENT, not measured (notes/downloads.md has the numbers): a part of the score is named when it moved by more
#? than this many points of 100 - a few points either way is two rips of one album, not a different match
SIGNAL_MOVED = 5
#? JUDGEMENT: sizes are said to differ beyond this share of the smaller - two rips of one album are never the same
#? size to the byte, and a few MB either way says nothing
SIZE_SHARE = 0.10
#? JUDGEMENT: measured speeds are said to differ when one is beyond this many times the other - every measurement
#? differs a little
SPEED_FACTOR = 1.5
#? missing songs named in full before "and N more"
MISSING_NAMED = 3


# --- one source's facts --------------------------------------------------------------------------------------

def source_facts(source: dict, release: dict | None, speed: float | None = None) -> dict:
    """
    What one source is: `source` as a job or a runner-up keeps it - {username, directory, files, quality,
    has_free_slot, queue_length}, any of them missing - `release` the job's stored release (its tracklist, edition
    words and year: what the score is made against), `speed` the rate deadwax measured from the peer (bytes a
    second) or None. JSON throughout: it rides in /jobs and in the notice.
    """
    release = release if isinstance(release, dict) else {}
    files = [f for f in source.get("files") or [] if isinstance(f, dict)]
    tracks = [t for t in release.get("tracks") or [] if isinstance(t, dict)]
    mapping = match_tracks_to_files(tracks, files) if tracks else {}
    audio = audio_tracks(tracks) if tracks else []
    missing = missing_tracks(tracks, mapping) if tracks else []
    score, signals = match_score(source, release)
    quality = source.get("quality") or {}
    return {
        "username": source.get("username") or "",
        "directory": source.get("directory") or "",
        "quality": quality_words(quality, files),
        "grade": _grade(quality, files),
        "songs": max(0, len(audio) - len(missing)) if tracks else None,
        "of": len(audio) if tracks else None,
        "missing": [t.get("title") or f"track {t.get('position')}" for t in missing],
        #? which tracks, to compare - two songs can share a title
        "missing_keys": [f"{t.get('disc') or 1}-{t.get('position')}" for t in missing],
        "files": len(files),
        #? files no track was paired with - with no tracklist, none can be said to be extra
        "extra": max(0, len(files) - len(mapping)) if tracks else 0,
        "edition": sorted(detect_edition_tags(source.get("directory") or "")),
        "size": sum(int(f.get("size") or 0) for f in files),
        "score": score,
        "signals": signals,
        "free_slot": source.get("has_free_slot"),
        "queue": source.get("queue_length"),
        "speed": float(speed) if speed else None,
    }


def match_score(source: dict, release: dict | None) -> tuple[float | None, dict]:
    """
    (review) The source's match to the job's release, as deadwax scores it - matching.score_candidate on its audio
    files and folder against the stored release, availability left out (matching.blend without "peer") - and the
    parts it was made of. (None, {}) when it can't be made: no audio files, or no release to make it against. Never
    a score the client sent.
    """
    release = release if isinstance(release, dict) else {}
    files = [f for f in source.get("files") or []
             if isinstance(f, dict) and is_audio(split_remote_path(f.get("filename", ""))[1])]
    if not files or not release:
        return None, {}
    try:
        scored = score_candidate({"files": files, "directory": source.get("directory") or "", "response": {}},
                                 release)
    except Exception:
        return None, {}
    signals = {name: part for name, part in scored["signals"].items() if name != "peer"}
    return round(blend(signals, bool(release.get("manual"))), 4), {k: v for k, v in signals.items() if v is not None}


def _formats(quality: dict, files: list[dict] | None) -> list[str]:
    """The formats a source is in: its candidate's, or from its files' names when the candidate's weren't kept."""
    formats = [str(f).lower() for f in quality.get("formats") or [] if f]
    if not formats:
        formats = [file_extension(split_remote_path(f.get("filename", ""))[1])
                   for f in files or [] if is_audio(split_remote_path(f.get("filename", ""))[1])]
    return sorted(set(formats))


def quality_words(quality: dict, files: list[dict] | None = None) -> str:
    """
    A source's quality as the app's cards say it, less the "k": "FLAC 16/44.1", "FLAC 16-24/44.1-96", "FLAC 24-bit",
    "FLAC 96 kHz", "MP3 320", "MP3 VBR 245", the format alone when nothing more was reported - the formats from the
    files' names when the candidate's quality wasn't kept - and "" with no format at all. Only what was reported.
    """
    formats = _formats(quality, files)
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


def _grade(quality: dict, files: list[dict]) -> dict | None:
    """What the quality words are made of, to tell worse from better: lossless or not, and the lowest bit depth,
    rate and bitrate reported (None each unknown) - None with no format at all."""
    formats = _formats(quality, files)
    if not formats:
        return None
    return {"lossless": all(f in LOSSLESS_EXTENSIONS for f in formats), "depth": _lowest(quality.get("bit_depths")),
            "rate": _lowest(quality.get("sample_rates")), "bitrate": _lowest(quality.get("bitrates"))}


def _numbers(values) -> list[float]:
    return [v for v in values or [] if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0]


def _lowest(values) -> float | None:
    numbers = _numbers(values)
    return min(numbers) if numbers else None


def _span(values, show) -> str:
    numbers = _numbers(values)
    if not numbers:
        return ""
    low, high = min(numbers), max(numbers)
    return show(low) if low == high else f"{show(low)}-{show(high)}"


def _number(value: float) -> str:
    """44.1 as 44.1, 48.0 as 48 - as the app's trimRate."""
    rounded = round(float(value), 1)
    return str(int(rounded)) if rounded == int(rounded) else str(rounded)


def start_words(free_slot, queue_length) -> str | None:
    """When the new source can start, as the design's table says it: "a free slot", "4th in their queue" - the
    place you'd join at, behind everyone they have waiting - or None unknown."""
    if free_slot is None and queue_length is None:
        return None
    if free_slot:
        return "a free slot"
    return f"{_ordinal(int(queue_length or 0) + 1)} in their queue"


def _start_was(free_slot, queue_length) -> str:
    """The first source's start, after the new one's: "the first had a free slot", "the first was 2nd in theirs"."""
    if free_slot:
        return "the first had a free slot"
    return f"the first was {_ordinal(int(queue_length or 0) + 1)} in theirs"


def _ordinal(number: int) -> str:
    """As the app's ordinal: 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st."""
    suffix = "th" if number % 100 in (11, 12, 13) else {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
    return f"{number}{suffix}"


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
    """Math.round's rounding, which Python's round() (to even) is not - with a hair for a float a shade under its
    half (0.955 * 100 is 95.49999...): what's compared is the whole percent a person reads, 95.5 as 96."""
    return int(value + 0.5 + 1e-9)


def _percent(score: float) -> int:
    return _half_up(score * 100)


# --- two sources compared ------------------------------------------------------------------------------------

def compare(new: dict, old: dict) -> dict:
    """
    How `new` differs from `old`, both source_facts(): {verdict, match, differences: [{what, now, was, words,
    kind}], detail, notes}. The verdict is decided by the differences' kinds alone (the module's docstring), and
    `detail` is the words after "as good a match: " and the rest - "same quality, songs and edition" first when the
    verdict is as good, then every difference, the deciding kind's first, joined by " · ".
    """
    differences = []
    notes = []

    def differ(what: str, now: str, was: str, kind: str | None, words: str | None = None) -> None:
        differences.append({"what": what, "now": now, "was": was, "kind": kind, "words": words or f"{now}, was {was}"})

    if new["quality"] != old["quality"]:
        differ("quality", new["quality"] or "quality not known", old["quality"] or "not known",
               _quality_kind(new["grade"], old["grade"]))
    elif not new["quality"]:
        notes.append("no quality to compare")

    if new["of"] is None or old["of"] is None:
        #? no tracklist (a manual search's download): the files are all there is to count
        if new["files"] != old["files"]:
            differ("files", f"{new['files']} files", str(old["files"]), DIFFERENT)
        notes.append("no tracklist to count songs against")
    else:
        lacking = set(new["missing_keys"]) - set(old["missing_keys"])
        if lacking or set(old["missing_keys"]) - set(new["missing_keys"]):
            #? a song the first had and this hasn't is worse, whatever else it brings back
            differ("songs", _songs_held(new), _songs_was(old), WORSE if lacking else BETTER, _songs_words(new, old))
        if new["extra"] != old["extra"]:
            differ("files", f"{new['files']} files for {new['of']} songs", str(old["files"]), DIFFERENT)

    if new["edition"] != old["edition"]:
        differ("edition", f"folder says {_edition_words(new['edition'])}", _edition_words(old["edition"]), DIFFERENT,
               f"folder says {_edition_words(new['edition'])}, the first said {_edition_words(old['edition'])}")

    if new["score"] is None or old["score"] is None:
        #? (review) an unknown score never allows "as good" or "better": a difference of kind, said
        notes.append("no match score to compare")
        now = "match not known" if new["score"] is None else f"match {_percent(new['score'])}%"
        was = "not known" if old["score"] is None else f"{_percent(old['score'])}%"
        differ("score", now, was, DIFFERENT, "match not known for either" if new["score"] is None and old["score"] is None
               else None)
    elif _percent(new["score"]) != _percent(old["score"]):
        moved = _moved_parts(new["signals"], old["signals"])
        now, was = f"match {_percent(new['score'])}%", f"{_percent(old['score'])}%"
        differ("score", now, was, WORSE if _percent(new["score"]) < _percent(old["score"]) else BETTER,
               f"{now}, was {was}" + (f" ({moved})" if moved else ""))

    if new["size"] and old["size"] and abs(new["size"] - old["size"]) > SIZE_SHARE * min(new["size"], old["size"]):
        differ("size", size_words(new["size"]), size_words(old["size"]), None)

    starts, started = start_words(new["free_slot"], new["queue"]), start_words(old["free_slot"], old["queue"])
    if starts and started and starts != started:
        differ("start", starts, started, None, f"{starts}, {_start_was(old['free_slot'], old['queue'])}")

    if new["speed"] and old["speed"] and max(new["speed"], old["speed"]) > SPEED_FACTOR * min(new["speed"], old["speed"]):
        differ("speed", speed_words(new["speed"]), speed_words(old["speed"]).removeprefix("about "), None)

    kinds = {d["kind"] for d in differences}
    deciding, verdict = next(((kind, verdict) for kind, verdict in VERDICT_OF if kind in kinds), (None, AS_GOOD))
    #? the reason for the word first, then the rest in the table's order (sorted is stable)
    ordered = sorted(differences, key=lambda d: d["kind"] != deciding)
    parts = ([SAME] if verdict == AS_GOOD else []) + [d["words"] for d in ordered]
    return {
        "verdict": verdict,
        "match": MATCH_WORDS[verdict],
        "differences": ordered,
        "detail": " · ".join(parts),
        "notes": notes,
    }


def _quality_kind(new: dict | None, old: dict | None) -> str:
    """Worse, better or different, for quality words that differ: lossy for lossless is worse, a lower bit depth,
    rate or bitrate worse, a higher one (and none lower) better; anything else - another lossless format at the
    same depth and rate, VBR for CBR, a quality not known on one side - different."""
    if new is None or old is None:
        return DIFFERENT
    if new["lossless"] != old["lossless"]:
        return BETTER if new["lossless"] else WORSE
    keys = ("depth", "rate") if new["lossless"] else ("bitrate",)
    pairs = [(new[key], old[key]) for key in keys if new[key] is not None and old[key] is not None]
    if any(now < was for now, was in pairs):
        return WORSE
    if any(now > was for now, was in pairs):
        return BETTER
    return DIFFERENT


def _songs_held(facts: dict) -> str:
    """ "all 11 songs", "10 of 11 songs"."""
    noun = "song" if facts["of"] == 1 else "songs"
    if not facts["missing"]:
        return f"all {facts['of']} {noun}"
    return f"{facts['songs']} of {facts['of']} {noun}"


def _songs_was(facts: dict) -> str:
    """The first source's, after "was": "all 11", "10"."""
    return f"all {facts['of']}" if not facts["missing"] else str(facts["songs"])


def _songs_words(new: dict, old: dict) -> str:
    """ "10 of 11 songs, was all 11 (missing: Krakow)", "7 of 11 songs, was 10 (missing: A, B, C and 1 more)",
    "all 11 songs, was 10" - the missing named are the new source's."""
    words = f"{_songs_held(new)}, was {_songs_was(old)}"
    if not new["missing"]:
        return words
    named = new["missing"][:MISSING_NAMED]
    more = len(new["missing"]) - len(named)
    return f"{words} (missing: {', '.join(named)}{f' and {more} more' if more else ''})"


def _edition_words(labels: list[str]) -> str:
    """ "Deluxe", "Super Deluxe and Remaster", "nothing" - matching's labels in a sentence's case."""
    if not labels:
        return "nothing"
    return " and ".join(" ".join(word.capitalize() for word in label.split()) for label in labels)


def _moved_parts(new: dict, old: dict) -> str:
    """The parts of the score that moved by more than SIGNAL_MOVED points: "lengths 70, was 100"."""
    moved = []
    for name, word in SIGNAL_WORDS.items():
        now, was = new.get(name), old.get(name)
        if now is None or was is None:
            continue
        if abs(_percent(now) - _percent(was)) > SIGNAL_MOVED:
            moved.append(f"{word} {_percent(now)}, was {_percent(was)}")
    return "; ".join(moved)


# --- what /jobs and the notice carry --------------------------------------------------------------------------

def lead(facts: dict) -> str:
    """The new source's own facts first, as the design's table has it: "Next: sofaking · FLAC 16/44.1 · 95%"."""
    parts = [facts["username"]]
    if facts["quality"]:
        parts.append(facts["quality"])
    if facts["score"] is not None:
        parts.append(f"{_percent(facts['score'])}%")
    return "Next: " + " · ".join(parts)


def next_source(new: dict, old: dict) -> dict:
    """
    /jobs' `next_source` (and a damaged download's notice): the next source's facts and how they differ from the
    source it would replace - {username, directory, replaces, lead, verdict, match, differences, summary, detail,
    notes, facts, was}. `summary` stands alone: "Same quality, songs and edition as glassbeads." when nothing
    differs, else "A weaker match: ...", "A different match: ...", "A better match: ..." or "As good a match: ...".
    """
    compared = compare(new, old)
    if not compared["differences"] and compared["verdict"] == AS_GOOD:
        summary = f"Same quality, songs and edition as {old['username']}."
    else:
        summary = f"{compared['match'][0].upper()}{compared['match'][1:]}: {compared['detail']}."
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
