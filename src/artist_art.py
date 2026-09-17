"""
Artist images, written into the library. The FIFTH writer to the user's filesystem.

Same plan/execute split as the organizer, the retag and the hand tag editor, for the same
reason: `plan_artist_art()` reads the folder and says what WOULD happen, `execute_artist_art()`
does that and nothing else, and the route recomputes the plan rather than accepting one back
over the wire. It takes bytes already fetched, as save_cover_art does, so this module needs no
network to be tested.

Where the files go is decided in artists.py (ARTIST_ART_STEMS) and is not arbitrary: Navidrome
reads `artist.*` out of an artist's folder with no configuration at all. The other five are for
jimbrainz's own artist page and for anything else pointed at the same library.
"""

from pathlib import Path

from src.api.coverart_endpoint import extension_for
from src.artists import ARTIST_ART_KINDS, ARTIST_ART_STEMS
from src.library import IMAGE_EXTENSIONS
from src.logger import logger
from src.matching import AUDIO_EXTENSIONS, file_extension
from src.organizer import is_within


def _empty(artist_path: str, problem: str) -> dict:
    return {
        "artist_path": artist_path,
        "source": "",
        "files": [],
        "problems": [problem],
        "empty": True,
    }


def artist_folder(album_paths: list[str]) -> dict:
    """
    Which folder is the artist's own, given where their albums are.

    An artist has no folder of its own in the scan - the library is read album by album - so it
    is derived from the albums, and only when they agree. `{artist}/{album}` is the convention
    the organizer files into, so the shared parent IS the artist folder; a library laid out
    some other way, or an artist whose albums sit in two different places, has no single answer
    and is told so rather than guessed at. Writing an artist's picture into the wrong folder is
    not dangerous, but it is silently useless, which is worse to debug.

    An album directly in the library root would make the ROOT the artist folder, which would put
    one artist's picture at the top of the whole library. Refused.
    """
    parents = sorted({str(Path(p).parent) for p in album_paths if p})

    if not parents:
        return {"path": None, "problem": "no albums by this artist in the library", "candidates": []}

    if "." in parents:
        return {
            "path": None,
            "candidates": parents,
            "problem": "an album by this artist sits at the top of the library, "
                       "so there is no folder that belongs to the artist alone",
        }

    if len(parents) > 1:
        return {
            "path": None,
            "candidates": parents,
            "problem": f"this artist's albums are in {len(parents)} different folders, "
                       "so there is no one folder to put their pictures in",
        }

    return {"path": parents[0], "problem": None, "candidates": parents}


def plan_artist_art(
    artist_path: str,
    kinds: list[str],
    library_root: str,
    replace: bool = False,
) -> dict:
    """
    What writing these images into `artist_path` would do. Touches nothing.

    `artist_path` is relative to LIBRARY_PATH, like every other path over this API.
    """
    if not library_root:
        return _empty(artist_path, "LIBRARY_PATH is not set")

    root = Path(library_root)
    directory = root / artist_path

    if not artist_path or not is_within(directory, root) or not directory.is_dir():
        return _empty(artist_path, "that folder is not inside the library")

    try:
        if directory.resolve() == root.resolve():
            return _empty(artist_path, "the library root is not an artist's folder")
    except OSError as e:
        return _empty(artist_path, f"could not read that folder: {e}")

    try:
        entries = sorted(p for p in directory.iterdir() if p.is_file())
    except OSError as e:
        return _empty(artist_path, f"could not read that folder: {e}")

    #? A folder with tracks DIRECTLY in it is an album, not an artist - that is exactly how the
    #? scanner reads it. Writing here would put an artist picture among an album's files, where
    #? Navidrome's own cover-art priority would then be free to read `artist.*` as that album's
    #? artist and `folder.*` as its cover. Refusing is the difference between "nothing happened"
    #? and "something happened somewhere you weren't looking".
    if any(file_extension(p.name) in AUDIO_EXTENSIONS for p in entries):
        return _empty(artist_path, "that folder holds tracks, so it is an album rather than an artist")

    wanted = [k for k in ARTIST_ART_KINDS if k in set(kinds or ())]
    if not wanted:
        return _empty(artist_path, "no images asked for")

    files = []
    for kind in wanted:
        stem = ARTIST_ART_STEMS[kind]
        existing = next(
            (p.name for p in entries
             if p.stem.lower() == stem and file_extension(p.name) in IMAGE_EXTENSIONS),
            None,
        )
        files.append({
            "kind": kind,
            "stem": stem,
            "existing": existing,
            #? an existing picture is KEPT unless replacing was asked for, the same rule the
            #? one-click cover fetch follows: adding what is missing needs no decision, and
            #? overwriting a picture somebody chose is not recoverable
            "action": "write" if not existing else ("replace" if replace else "keep"),
        })

    return {
        "artist_path": artist_path,
        "source": str(directory),
        "files": files,
        "problems": [],
        "empty": not any(f["action"] != "keep" for f in files),
    }


def execute_artist_art(plan: dict, images: dict, mode: str = "dry_run") -> dict:
    """
    Write the images the plan says to write, and nothing else.

    `images` is {kind: (bytes, mime)}, fetched by the caller - this module stays free of the
    network for the same reason execute_retag does.
    """
    dry_run = mode != "apply"
    written: list[str] = []
    skipped: list[str] = []
    problems: list[str] = list(plan.get("problems") or [])

    if problems:
        #? a plan that could not be made is not a plan to half-apply
        return {"mode": mode, "dry_run": dry_run, "written": [], "skipped": [], "problems": problems}

    source = plan.get("source") or ""
    directory = Path(source)

    #? containment re-checked at the write rather than trusted from the plan, for the reason the
    #? retag endpoint recomputes its own: a path that arrived over the wire is not evidence
    from src.config import Config
    root = Path(Config.LIBRARY_PATH or "")
    if not source or not str(Config.LIBRARY_PATH or "") or not is_within(directory, root) \
            or not directory.is_dir():
        return {
            "mode": mode, "dry_run": dry_run, "written": [], "skipped": [],
            "problems": ["that folder is not inside the library"],
        }

    for entry in plan.get("files") or []:
        kind = entry["kind"]

        if entry["action"] == "keep":
            skipped.append(f"{kind}: {entry['existing']} is already there")
            continue

        image = images.get(kind)
        if not image or not image[0]:
            skipped.append(f"{kind}: nothing to write")
            continue

        data, mime = image
        name = f"{entry['stem']}.{extension_for(mime)}"

        if dry_run:
            written.append(name)
            continue

        try:
            (directory / name).write_bytes(data)
        except OSError as e:
            logger.error(f"could not write {name} into {directory}: {e}")
            problems.append(f"could not save {name}: {e}")
            continue

        #? Replacing artist.png with a JPEG would otherwise leave BOTH on disk, and every reader
        #? here matches on the stem with any extension - Navidrome's `artist.*` would then pick
        #? whichever it happened to see first, which is not necessarily the one just written.
        old = entry.get("existing")
        if old and old != name:
            try:
                (directory / old).unlink()
            except OSError as e:
                problems.append(f"wrote {name} but could not remove the old {old}: {e}")

        written.append(name)

    if written and not dry_run:
        logger.info(
            f"saved {len(written)} artist image(s) into {directory.name}: {', '.join(written)}",
            extra={"frontend": True},
        )

    return {"mode": mode, "dry_run": dry_run, "written": written, "skipped": skipped, "problems": problems}
