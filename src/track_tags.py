"""
Editing tags by hand, on one track or on several at once.

The metadata editor applies a release wholesale: every file takes MusicBrainz's title, number
and disc for whichever track it matched. That is the right tool for a mistagged album and the
wrong one for nearly everything else - a genre MusicBrainz doesn't carry, the one track that
ended up on the wrong disc, a composer credit for six songs out of twelve. James asked for this
by name, with a selection so that one change can go to many tracks.

It is the fourth thing in jimbrainz that writes to the user's filesystem, and it is built the
same way as the other three:

  plan_tag_edits()     - reads every file named and works out exactly what would change.
                         Writes nothing, and is what the preview shows.
  execute_tag_edits()  - carries out that plan, and nothing else.

The apply endpoint recomputes the plan rather than accepting one back, for the reason the retag
endpoint does: a plan is a list of files to write, and taking one over the wire would let a
caller name any file it liked.

The rules, each of which is a guard rather than a convenience:

  - A file is named by its bare filename, and only a name found in a listing of the album's own
    folder is accepted. Nothing a caller sends is joined onto a path until it has matched a file
    that was already there - which is the whole of the containment story for files.
  - Only the tags in EDITABLE_TAGS can be touched. The MusicBrainz ids are an album's identity,
    and they change by applying a release, where the preview can say what that means.
  - A tag you did not edit is not written. Values that differ across a selection stay different.
  - The whole batch is refused if any part of it is invalid. A half-applied edit - some tracks
    changed, some not, and no way to tell which by looking - is the worst outcome available.

Tags only: no file is renamed and no folder moves. Re-filing is the metadata editor's job, and
it previews it. Renaming an album here leaves a folder that no longer matches its tags, which
the metadata queue already knows how to point out.
"""

import re
from pathlib import Path

from src.library import named_tags
from src.logger import logger
from src.matching import AUDIO_EXTENSIONS, file_extension
from src.organizer import is_within

#? What can be edited, in mutagen's easy-interface names so one key means the same thing in
#? FLAC, MP3 and M4A - and the names the track viewer reads, so a preview compares against
#? exactly what was on screen. Kept in step with EDIT_FIELDS in ui/src/lib/tagEdit.ts; a test
#? reads that file and says so when they drift.
EDITABLE_TAGS = (
    "title", "artist", "album", "albumartist", "tracknumber", "discnumber",
    "date", "originaldate", "genre", "composer",
)

#? "4", "04" and "4/12" are all track numbers - and so is 0, which MusicBrainz uses for a
#? hidden track in the pregap
NUMBER_PATTERN = re.compile(r"\d{1,4}(/\d{1,4})?")

#? a year, a year and a month, or a whole date: what taggers write, and what the scan reads a
#? year back out of by its first four characters
DATE_PATTERN = re.compile(r"\d{4}(-\d{2}(-\d{2})?)?")

MAX_VALUE_LENGTH = 1000

#? An album is dozens of files, not thousands. Stops one request doing unbounded work.
MAX_EDITS = 2000


def validate_tag(key: str, value: str) -> str | None:
    """
    Why `value` can't go into `key`, or None if it can. An empty value means "remove the tag".

    Only what is definitionally wrong is refused - a track number that isn't a number, a date
    that isn't a date. Whether a title is RIGHT is yours to decide, and the preview shows it
    to you first.
    """
    if key not in EDITABLE_TAGS:
        return f"{key} can't be edited here"

    if not value:
        return None

    if len(value) > MAX_VALUE_LENGTH:
        return f"{key} is longer than {MAX_VALUE_LENGTH} characters"

    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        return f"{key} has a line break or a control character in it"

    if key in ("tracknumber", "discnumber") and not NUMBER_PATTERN.fullmatch(value):
        return f"{key} has to be a number, like 3 or 3/12"

    if key in ("date", "originaldate") and not DATE_PATTERN.fullmatch(value):
        return f"{key} has to be a year or a date, like 2022 or 2022-07-29"

    return None


def _read_tags(path: Path) -> dict[str, str] | None:
    """The named tags a file carries now, exactly as the track viewer reads them. None if unreadable."""
    import mutagen

    try:
        audio = mutagen.File(str(path), easy=True)
    except Exception:
        return None

    return named_tags(audio) if audio is not None else None


def _empty(album_path: str, problem: str) -> dict:
    return {
        "album_path": album_path, "source": None, "files": [], "file_count": 0,
        "changed_file_count": 0, "problems": [problem], "empty": True,
    }


def plan_tag_edits(album_path: str, edits: list[dict], library_root: str) -> dict:
    """
    What applying `edits` to the album at `album_path` would change, file by file. Writes nothing.

    `edits` is a list of {"filename": ..., "tags": {key: value}}. A value of '' or None removes
    that tag; a tag left out is not touched. Every value is compared against the file as it is
    right now, so setting a tag to what a track already says is no change at all - which is
    what lets one value go to a selection with mixed values without rewriting the files that
    already had it.

    `album_path` is relative to LIBRARY_PATH, as the scan reports it.
    """
    root = Path(library_root)
    directory = root / album_path

    if not album_path or not is_within(directory, root) or not directory.is_dir():
        return _empty(album_path, "that album is not inside the library")

    if len(edits) > MAX_EDITS:
        return _empty(album_path, f"that is more than {MAX_EDITS} files in one edit")

    try:
        present = {entry.name for entry in directory.iterdir() if entry.is_file()}
    except OSError as e:
        return _empty(album_path, f"could not read the album folder: {e}")

    #? a dict rather than a list, so one bad value sent to eighteen tracks is reported once
    problems: dict[str, None] = {}
    files = []
    seen: set[str] = set()

    for edit in edits:
        filename = str(edit.get("filename") or "")

        #? The containment guard: the name must be one found in the folder, not merely one that
        #? resolves to something. "../../etc/passwd" and "Disc 2/01.flac" are not entries of
        #? this directory, so neither gets as far as being joined onto a path.
        if filename not in present or file_extension(filename) not in AUDIO_EXTENSIONS:
            problems[f"{filename or 'a file'} is not an audio file in this album"] = None
            continue

        if filename in seen:
            problems[f"{filename} is in this edit twice"] = None
            continue
        seen.add(filename)

        wanted: dict[str, str] = {}
        for key, raw in (edit.get("tags") or {}).items():
            value = "" if raw is None else str(raw).strip()
            problem = validate_tag(str(key), value)
            if problem:
                problems[problem] = None
            else:
                wanted[str(key)] = value

        current = _read_tags(directory / filename)
        if current is None:
            problems[f"{filename} couldn't be read as audio"] = None
            continue

        files.append({
            "filename": filename,
            "changes": {
                key: {"from": current.get(key, ""), "to": value}
                for key, value in wanted.items()
                if current.get(key, "") != value
            },
        })

    changed = sum(1 for entry in files if entry["changes"])

    return {
        "album_path": album_path,
        "source": str(directory),
        "files": files,
        "file_count": len(files),
        "changed_file_count": changed,
        #? any of these refuses the whole batch - execute_tag_edits writes nothing while they stand
        "problems": list(problems),
        #? nothing to do is still a valid answer, and the editor says so rather than offering an
        #? apply button that would write nothing
        "empty": changed == 0,
    }


def execute_tag_edits(plan: dict, mode: str = "dry_run") -> dict:
    """
    Carry out a plan. `dry_run` reports what it would do and touches nothing.

    Refuses outright when the plan has problems - see the module docstring on half-applied
    batches. Each file is written with one save, so a file is either edited or untouched. A tag
    its format can't hold (easy MP4 has no `originaldate`, for one) is reported by name rather
    than skipped in silence, because an edit that quietly didn't happen reads exactly like one
    that did.
    """
    import mutagen

    results = {
        "mode": mode,
        "dry_run": mode != "apply",
        "written": 0,
        "failed": 0,
        "problems": [],
    }

    if plan.get("source") is None or plan.get("problems"):
        results["problems"] = list(plan.get("problems") or ["there is nothing here to edit"])
        return results

    directory = Path(plan["source"])

    for entry in plan["files"]:
        if not entry["changes"]:
            continue

        if results["dry_run"]:
            results["written"] += 1
            continue

        refused: list[str] = []

        try:
            audio = mutagen.File(str(directory / entry["filename"]), easy=True)
            if audio is None:
                raise ValueError("not a format jimbrainz can tag")

            for key, change in entry["changes"].items():
                if change["to"]:
                    try:
                        audio[key] = change["to"]
                    except Exception:
                        refused.append(key)
                    continue

                try:
                    del audio[key]
                except KeyError:
                    #? not there to remove - or not a key this format has, which comes to the
                    #? same thing as far as removing it goes
                    pass
                except Exception:
                    refused.append(key)

            audio.save()

        except Exception as e:
            logger.error(f"could not edit the tags of {entry['filename']}: {e}")
            results["failed"] += 1
            results["problems"].append(f"{entry['filename']} could not be written: {e}")
            continue

        if len(refused) < len(entry["changes"]):
            results["written"] += 1

        if refused:
            results["problems"].append(
                f"{entry['filename']} is a format that can't hold {', '.join(refused)}, so "
                f"{'that was' if len(refused) == 1 else 'those were'} left as they were"
            )

    return results
