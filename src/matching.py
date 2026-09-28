"""
Scoring slskd search results against the MusicBrainz release the user actually picked.

This is the whole point of cutting Lidarr out. Lidarr only ever learned "go find album N",
so a search for a 2011 remaster looked identical to a search for the 1979 original. Here we
still have the release the user clicked: its tracklist, durations, year and edition tags. So
candidate folders get ranked against that instead of guessed at.

Deliberately pure - no network, no disk, no config. Everything in here is a plain function
over plain dicts so it can be tested without a live slskd (tests/test_matching.py).
"""

import re
from difflib import SequenceMatcher


AUDIO_EXTENSIONS = {
    "flac", "mp3", "m4a", "ogg", "opus", "wav", "aac", "wma", "alac", "aiff", "aif", "ape", "wv"
}

LOSSLESS_EXTENSIONS = {"flac", "wav", "alac", "aiff", "aif", "ape", "wv"}

#? mirrors EDITION_KEYWORDS in interface/scripts/main.js. the frontend tags the release,
#? this tags the candidate folder name, and then we compare the two.
EDITION_PATTERNS = [
    (re.compile(r"super\s*deluxe"), "SUPER DELUXE"),
    (re.compile(r"deluxe"), "DELUXE"),
    (re.compile(r"box\s*set|boxset"), "BOX SET"),
    (re.compile(r"anniversary"), "ANNIVERSARY"),
    (re.compile(r"expanded"), "EXPANDED"),
    (re.compile(r"limited\s*edition"), "LIMITED"),
    (re.compile(r"special\s*edition"), "SPECIAL EDITION"),
    (re.compile(r"remaster"), "REMASTER"),

    #? ALTERNATE PERFORMANCES, which are a different kind of edition from the ones above and
    #? matter more, not less.
    #?
    #? A deluxe edition is MORE OF THE SAME ALBUM: collide it with the standard press and you
    #? lose some bonus tracks. An instrumental is a DIFFERENT RECORDING of it - same track
    #? titles, same numbers, same count - so colliding it means every single file matches an
    #? existing one, all of them are skipped, and you end up with neither album while the job
    #? reports that there was nothing to do.
    #?
    #? Dance Gavin Dance is the case that surfaced it: MusicBrainz holds the instrumental as a
    #? RELEASE inside the ordinary album's group, with "(instrumental)" in the title and an
    #? EMPTY disambiguation - so every source resolve_edition_label() consults came back blank
    #? and it resolved to the standard album's own folder. Verified against the live API.
    (re.compile(r"instrumental"), "INSTRUMENTAL"),
    (re.compile(r"acoustic"), "ACOUSTIC"),
    #? "a cappella", "acappella" and the common misspelling "a capella"
    (re.compile(r"a\s*capp?ella"), "A CAPPELLA"),
]

#? how much each signal contributes to the final score. title/count identify the album,
#? edition picks the right *version* of it, which is the thing that was broken before.
WEIGHTS = {
    "title_match": 0.30,
    "track_count": 0.20,
    "duration_match": 0.15,
    "edition": 0.15,
    "format": 0.12,
    "peer": 0.08,
}

TITLE_MATCH_THRESHOLD = 0.60
DURATION_TOLERANCE_SEC = 8

#? One disc of a set, as sharers name it: "CD 1", "CD1", "cd.2", "Disc 02", "Disk 3", "Disc One".
_DISC_WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
               "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}
_DISC_MARKER = r"(?:cd|disc|disk)\s*[-_.#]?\s*(\d{1,2}|" + "|".join(_DISC_WORDS) + r")(?![0-9a-z])"
#? the whole name, or its start: "CD 1", "[CD2]", "Disc 1 - Wish You Were Here"
_DISC_AT_START = re.compile(r"^[\[(]?\s*" + _DISC_MARKER, re.IGNORECASE)
#? or its end, after the album: "Wish You Were Here CD2", "Wish You Were Here (Disc 2)". The marker
#? has to follow a separator or a bracket, so "ABCD1" is not disc 1 of "AB".
_DISC_AT_END = re.compile(r"^(.*?[^\s\-_.,\[(])(?:[\s\-_.,]+[\[(]?|[\[(])\s*" + _DISC_MARKER
                          + r"\s*[\])]?\s*$", re.IGNORECASE)


def normalize(text: str) -> str:
    """Lowercase, drop punctuation, collapse whitespace. For comparing messy filenames."""
    if not text:
        return ""

    text = text.lower()
    text = re.sub(r"[\[\](){}_\-.,'\"!?/\\:;&+]", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def split_remote_path(path: str) -> tuple[str, str]:
    """
    Soulseek paths are Windows-ish (`@@abc\\Music\\Artist\\Album\\01 track.flac`) but not
    reliably so. Split on whichever separator the peer happened to use.
    """
    if not path:
        return "", ""

    normalized = path.replace("\\", "/")
    if "/" not in normalized:
        return "", path

    directory, _, filename = normalized.rpartition("/")
    return directory, filename


def file_extension(filename: str) -> str:
    _, _, ext = filename.rpartition(".")
    return ext.lower() if ext and ext != filename else ""


def filename_stem(filename: str) -> str:
    stem, _, ext = filename.rpartition(".")
    return stem if stem and ext != filename else filename


def is_audio(filename: str) -> bool:
    return file_extension(filename) in AUDIO_EXTENSIONS


def disc_folder(name: str) -> tuple[str, int] | None:
    """
    Is this folder one disc of a set? Its album part and disc number, or None.

    The album part is "" when the name leads with the disc ("CD 1", "Disc 2 - Live at Wembley"),
    since those sit inside the album's own folder and it is the parent that names the set; it is
    the rest of the name when the disc comes last ("Wish You Were Here CD2"), where the discs sit
    side by side in the artist's folder and only the shared name says they belong together.
    """
    name = name.strip()
    match = _DISC_AT_START.match(name)
    if match:
        return "", _disc_number(match.group(1))
    match = _DISC_AT_END.match(name)
    if match:
        return match.group(1), _disc_number(match.group(2))
    return None


def _disc_number(text: str) -> int:
    return _DISC_WORDS.get(text.lower()) or int(text)


def file_disc(remote_filename: str) -> int | None:
    """The disc a file's own folder says it is on, or None when the folder says nothing."""
    directory, _ = split_remote_path(remote_filename)
    found = disc_folder(directory.rpartition("/")[2]) if directory else None
    return found[1] if found else None


def folder_label(directory: str) -> str:
    """
    What to call a candidate's folder on screen: its own name - or, for a folder that is only a
    disc ("CD 1"), the album folder above it too, since "CD 1" on its own says nothing about
    which album the peer is offering.
    """
    parent, _, name = directory.rpartition("/")
    found = disc_folder(name)
    if found and not found[0] and parent:
        return f"{parent.rpartition('/')[2]} / {name}"
    return name or directory


def detect_edition_tags(text: str) -> set[str]:
    """Pull edition markers out of a folder name, same vocabulary the UI tags releases with."""
    haystack = normalize(text)
    tags = set()

    for pattern, label in EDITION_PATTERNS:
        if pattern.search(haystack):
            tags.add(label)

    #? "super deluxe" also trips the plain "deluxe" pattern, keep only the specific one
    if "SUPER DELUXE" in tags:
        tags.discard("DELUXE")

    return tags


def title_similarity(track_title: str, filename: str) -> float:
    """
    How well does this file look like this track? Filenames usually carry track numbers and
    junk ("03 - The Color of the Fire (2013 remaster).flac"), so a containment check comes
    first and fuzzy ratio is the fallback.
    """
    title = normalize(track_title)
    stem = normalize(filename_stem(filename))

    if not title or not stem:
        return 0.0

    if title in stem:
        return 1.0

    return SequenceMatcher(None, title, stem).ratio()


def match_tracks_to_files(expected_tracks: list[dict], files: list[dict]) -> dict[int, dict]:
    """
    Greedily pair each expected track with its best unclaimed file.

    Returned mapping is reused later by the organizer: it's what lets us write correct track
    numbers and titles even when the peer named everything "Track 04.mp3".

    Scores exactly as title_similarity() does, pair for pair, and picks exactly what calling it on
    every pair would (v0.9.28, which a test holds it to). It is just not done that way: this runs
    for every folder a search returns, inside the request, and 300 folders of 12 tracks meant
    25,000 fresh SequenceMatchers. So each file's name is normalised and indexed once, a perfect
    1.0 ends the search for that track (the first one found was always the one kept), and a pair
    difflib's cheap upper bounds say can't beat the best so far is never fully compared.
    """
    remaining = []
    for candidate_file in files:
        _, filename = split_remote_path(candidate_file.get("filename", ""))
        stem = normalize(filename_stem(filename))
        if stem:  #? a file with no name to compare can never score above 0
            #? the stem is the matcher's second sequence, as in title_similarity - difflib indexes
            #? that one, so it is done once per file here rather than once per pair
            remaining.append((candidate_file, stem, SequenceMatcher(None, "", stem),
                              file_disc(candidate_file.get("filename", ""))))

    #? A set shared one folder per disc says which disc each file is on, and a track pairs only
    #? with files of its own disc. Discs repeat titles - The Experience edition's second disc is
    #? "Shine On You Crazy Diamond (live at Wembley 1974)" and "Wish You Were Here (with Stéphane
    #? Grappelli)" - and both CONTAIN the first disc's titles, so otherwise disc 1's tracks could
    #? claim disc 2's files, whichever came first in the list. A disc no folder is named for (a
    #? peer's lone "CD 1" holding everything) leaves its tracks free to pair with anything.
    folder_discs = {entry[3] for entry in remaining if entry[3] is not None}

    mapping: dict[int, dict] = {}

    for track in expected_tracks:
        title = normalize(track.get("title", ""))
        best = None
        best_score = 0.0
        disc = track.get("disc") if track.get("disc") in folder_discs else None

        for entry in remaining if title else ():
            if disc is not None and entry[3] != disc:
                continue
            _, stem, matcher, _ = entry
            if title in stem:
                score = 1.0
            else:
                matcher.set_seq1(title)
                if matcher.real_quick_ratio() <= best_score or matcher.quick_ratio() <= best_score:
                    continue
                score = matcher.ratio()

            if score > best_score:
                best_score = score
                best = entry
                if score == 1.0:
                    break

        if best is not None and best_score >= TITLE_MATCH_THRESHOLD:
            mapping[track.get("position")] = {
                "file": best[0],
                "score": round(best_score, 3),
                "track": track,
            }
            remaining.remove(best)

    return mapping


def score_track_count(expected_count: int, actual_count: int) -> float | None:
    """None means "no opinion" - the signal gets dropped from the weighted average."""
    if not expected_count:
        return None

    if actual_count == expected_count:
        return 1.0

    difference = abs(actual_count - expected_count)

    #? a folder missing/gaining one track is plausible (hidden track, bonus). Way off is not.
    return max(0.0, 1.0 - (difference / expected_count))


def score_durations(mapping: dict[int, dict]) -> float | None:
    """
    Compare MusicBrainz track lengths against the peer's file lengths. Different masterings
    drift by a second or two, but a wholly different recording won't line up at all.
    """
    comparable = 0
    close = 0

    for entry in mapping.values():
        expected_ms = entry["track"].get("length_ms")
        actual_sec = entry["file"].get("length")

        if not expected_ms or not actual_sec:
            continue

        comparable += 1
        if abs((expected_ms / 1000) - actual_sec) <= DURATION_TOLERANCE_SEC:
            close += 1

    if not comparable:
        return None

    return close / comparable


def score_format(files: list[dict], format_preference: str) -> float:
    extensions = {file_extension(split_remote_path(f.get("filename", ""))[1]) for f in files}
    has_lossless = bool(extensions & LOSSLESS_EXTENSIONS)

    if format_preference == "lossless_only":
        return 1.0 if has_lossless else 0.0

    if format_preference == "prefer_lossless":
        return 1.0 if has_lossless else 0.45

    return 1.0


def score_edition(directory: str, expected_tags: list[str] | None, expected_year: str | None) -> float:
    """
    The signal that motivated this whole rewrite.

    Caveat worth remembering: Soulseek folder names are typed by strangers and frequently
    omit edition text entirely, so this can only ever be a weighted nudge - never a hard
    filter, or legitimate results vanish. The year is a useful proxy since reissues usually
    carry their reissue year in the folder name.
    """
    folder_tags = detect_edition_tags(directory)
    expected = set(expected_tags or [])

    if expected:
        overlap = len(expected & folder_tags) / len(expected)
        score = overlap
    else:
        #? user picked a plain edition, so a "DELUXE" folder is probably the wrong thing
        score = 1.0 if not folder_tags else 0.4

    if expected_year and expected_year in directory:
        score = min(1.0, score + 0.25)

    return score


def score_peer(response: dict) -> float:
    """Availability tiebreaker - a perfect match from someone with a 400-deep queue isn't."""
    score = 0.0

    if response.get("hasFreeUploadSlot"):
        score += 0.5

    queue_length = response.get("queueLength", 0) or 0
    if queue_length == 0:
        score += 0.3
    elif queue_length < 10:
        score += 0.15

    upload_speed = response.get("uploadSpeed", 0) or 0
    if upload_speed > 1_000_000:
        score += 0.2
    elif upload_speed > 100_000:
        score += 0.1

    return min(1.0, score)


def group_files_by_directory(responses: list[dict]) -> list[dict]:
    """
    A peer's `files` list is flat and can span several of their folders, so an album isn't a
    response - it's a (user, directory) pair. Split them out and drop non-audio clutter.

    The same file can arrive more than once: an artist who has renamed is searched under each
    name, and a share whose path happens to hold both - "Kanye West/Ye - Donda" - answers both
    searches. Kept once, or the album would count its tracks twice, score on a track count it
    doesn't have, and be enqueued with every file requested twice.
    """
    candidates: dict[tuple[str, str], dict] = {}
    seen: set[tuple[str, str]] = set()

    for response in responses:
        username = response.get("username", "")

        for file_entry in response.get("files", []) or []:
            filename_full = file_entry.get("filename", "")
            directory, filename = split_remote_path(filename_full)

            if not is_audio(filename):
                continue

            if (username, filename_full) in seen:
                continue
            seen.add((username, filename_full))

            key = (username, directory)
            if key not in candidates:
                candidates[key] = {
                    "username": username,
                    "directory": directory,
                    "directory_name": folder_label(directory),
                    "files": [],
                    "response": response,
                }

            candidates[key]["files"].append(file_entry)

    return list(candidates.values())


def join_disc_folders(candidates: list[dict]) -> list[dict]:
    """
    One candidate for a set a peer shares one folder per disc.

    `Album/CD 1` and `Album/CD 2` are two folders, so they were two candidates, and each was
    scored against the whole release: a 5-track "CD 1" and a 9-track "CD 2", both missing most of
    a 14-track album, both ranked as poor - while the peer had every track. Reported on the
    Experience edition of Wish You Were Here.

    Folders join when they are the same peer's, are named as discs ("CD 1", "Disc 2"; or
    "Album CD1", "Album CD2" side by side), sit in the same folder, and are different discs.
    The joined candidate takes the album folder's name (or the name the discs share) and lists
    its disc folders. Anything less certain is left as it was: two folders both called "CD 1",
    or an album folder holding tracks of its own beside its disc folders.
    """
    sets: dict[tuple[str, str, str], list[tuple[int, str, dict]]] = {}
    for candidate in candidates:
        parent, _, name = candidate["directory"].rpartition("/")
        found = disc_folder(name) if parent else None
        if found:
            album, number = found
            sets.setdefault((candidate["username"], parent, normalize(album)), []).append((number, album, candidate))

    own_folders = {(c["username"], c["directory"]) for c in candidates}
    joined_ids: set[int] = set()
    joined: dict[int, dict] = {}

    for (username, parent, _), members in sets.items():
        numbers = [number for number, _, _ in members]
        if len(members) < 2 or len(set(numbers)) != len(numbers):
            continue

        members.sort(key=lambda member: member[0])
        album = members[0][1]
        #? a set named inside its album folder IS that folder; one named beside its siblings has
        #? no folder of its own, so it is named for what the discs share
        directory = f"{parent}/{album}" if album else parent
        #? that folder is a candidate itself - it holds tracks of its own - so which files are
        #? the album is no longer certain
        if (username, directory) in own_folders:
            continue

        first = members[0][2]
        for _, _, member in members:
            joined_ids.add(id(member))
        joined[id(first)] = {
            "username": username,
            "directory": directory,
            "directory_name": directory.rpartition("/")[2],
            "files": [f for _, _, member in members for f in member["files"]],
            "response": first["response"],
            "disc_folders": [member["directory"].rpartition("/")[2] for _, _, member in members],
        }

    #? in place of the first of its discs, so the list keeps the order it came in
    return [joined[id(c)] if id(c) in joined else c
            for c in candidates if id(c) in joined or id(c) not in joined_ids]


def is_single_disc(expected: dict) -> bool:
    """True only when the release's tracklist is known and every track of it is on one disc."""
    tracks = expected.get("tracks") or []
    return bool(tracks) and len({t.get("disc") or 1 for t in tracks}) == 1


def score_candidate(candidate: dict, expected: dict, format_preference: str = "prefer_lossless") -> dict:
    """Score one (user, directory) candidate against the picked release. Returns it enriched."""
    files = candidate["files"]
    expected_tracks = expected.get("tracks") or []

    mapping = match_tracks_to_files(expected_tracks, files) if expected_tracks else {}

    signals: dict[str, float | None] = {}

    signals["title_match"] = (len(mapping) / len(expected_tracks)) if expected_tracks else None
    signals["track_count"] = score_track_count(len(expected_tracks), len(files))
    signals["duration_match"] = score_durations(mapping) if mapping else None
    signals["edition"] = score_edition(
        candidate["directory"], expected.get("edition_tags"), expected.get("year")
    )
    signals["format"] = score_format(files, format_preference)
    signals["peer"] = score_peer(candidate["response"])

    #? when a release has no tracklist (release-group level search) the tracklist-dependent
    #? signals are None. Renormalize over whatever we do have rather than scoring those
    #? candidates as though they'd failed.
    active = {k: v for k, v in signals.items() if v is not None}
    total_weight = sum(WEIGHTS[k] for k in active)
    score = sum(WEIGHTS[k] * v for k, v in active.items()) / total_weight if total_weight else 0.0

    response = candidate["response"]

    return {
        **candidate,
        "score": round(score, 4),
        "signals": {k: (round(v, 3) if v is not None else None) for k, v in signals.items()},
        "matched_tracks": len(mapping),
        "expected_tracks": len(expected_tracks),
        "audio_file_count": len(files),
        "track_mapping": mapping,
        "detected_edition_tags": sorted(detect_edition_tags(candidate["directory"])),
        #? the peer's own folder per disc, for a set joined from them (join_disc_folders)
        "disc_folders": candidate.get("disc_folders", []),
        "formats": sorted({file_extension(split_remote_path(f.get("filename", ""))[1]) for f in files}),
        #? Peer stats, surfaced so the UI can show and filter on them.
        #?
        #? UNITS: BYTES/sec, not bits. slskd's own web UI renders it as
        #? `formatBytes(response.uploadSpeed)/s`, and the thresholds in score_peer() are only
        #? sensible read that way (1 MB/s fast, 100 KB/s decent; as bits those would be 125 and
        #? 12.5 KB/s). A comment here previously said bits, which would invite someone to
        #? "correct" the display by a factor of eight.
        #?
        #? MEANING: the peer's average upload speed over their whole history, to everyone, as
        #? reported by Soulseek - NOT the rate this transfer will run at. It is divided among
        #? however many people they are serving at once and averaged over conditions that have
        #? since changed, so it reads high far more often than not. An earlier comment here
        #? called it "our download speed", which is what the interface then went and claimed
        #? too. score_peer() weights it accordingly: 0.2 at most, inside a signal worth 0.08.
        "upload_speed": response.get("uploadSpeed", 0) or 0,
        "queue_length": response.get("queueLength", 0) or 0,
        "has_free_slot": bool(response.get("hasFreeUploadSlot")),
        "total_size": sum(f.get("size", 0) or 0 for f in files),
        "bitrates": sorted({f["bitRate"] for f in files if f.get("bitRate")}),
        #? What the sharer's client reported about each file, where it reported anything - slskd
        #? passes Soulseek's file attributes through as bitDepth/sampleRate/isVariableBitRate.
        #? Lossy files have no bit depth, and plenty of clients report nothing at all, so an
        #? empty list means "unknown", never "low". The candidates panel filters and sorts on
        #? these (v0.9.11, asked for: "filter and search by bitrate and depth").
        "bit_depths": sorted({f["bitDepth"] for f in files if f.get("bitDepth")}),
        "sample_rates": sorted({f["sampleRate"] for f in files if f.get("sampleRate")}),
        "variable_bitrate": any(bool(f.get("isVariableBitRate")) for f in files),
    }


def rank_candidates(
    responses: list[dict],
    expected: dict,
    format_preference: str = "prefer_lossless",
    limit: int = 50,
) -> list[dict]:
    """Full pipeline: raw slskd responses in, ranked scored candidates out."""
    candidates = group_files_by_directory(responses)

    #? A release known to be ONE disc keeps disc folders apart: a peer's "CD 1" of a two-disc
    #? deluxe may be exactly the standard album that was picked, and joined to its "CD 2" it
    #? would score as a worse match than it is. Anything else - two discs, or no tracklist to
    #? say - is offered the set as the peer laid it out.
    if not is_single_disc(expected):
        candidates = join_disc_folders(candidates)

    scored = [score_candidate(c, expected, format_preference) for c in candidates]

    if format_preference == "lossless_only":
        scored = [c for c in scored if c["signals"]["format"] > 0]

    scored.sort(key=lambda c: c["score"], reverse=True)
    return scored[:limit]
