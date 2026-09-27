"""
Move an artist's albums under the name MusicBrainz uses for them now (v0.9.14).

The EIGHTH writer to the user's filesystem, and it keeps the same plan/execute split as the
others: `plan_artist_refile` reads and decides, `execute_artist_refile` does exactly that and
nothing else, and the route recomputes the plan rather than taking one back over the wire.

Why it exists: an artist who renamed ends up in two folders. Since v0.6.18 deadwax files an
album under its artist's CURRENT name, but anything filed before that, or by another tool, sits
under the old one - `Kanye West/` beside `Ye/` - and the library tree shows two artists. The scan
notices (`artist_split`, one artist id under two folder names); this fixes it, from the artist
page, which is the part of deadwax that asks MusicBrainz who an artist is now.

What moves is deliberately narrow:

- the ALBUM ARTIST tag becomes the current name, and the artist id is written where it was
  missing - the same two fields a download filed today would carry. The TRACK artist is the
  credit, what the sleeve says, and is left alone: Donda was credited to Kanye West.
- the album folder moves, keeping its own name, into the current-name folder. Never onto a
  folder already there; that album is reported and stays.
- single-artist albums only. A collaboration's folder is its own.

Once the albums have gone, the old artist folder's pictures (artist.jpg, banner.jpg...) move too
where the new folder has none of that name, and the old folder is removed with rmdir - so it goes
only if nothing else is left in it.
"""

import shutil
from pathlib import Path

from src.artists import ARTIST_ART_STEMS
from src.logger import logger
from src.matching import AUDIO_EXTENSIONS, file_extension
from src.organizer import is_within, sanitize_filename
from src.retag import _tidy_emptied_artist, read_current_tags


def plan_artist_refile(library_root: str, albums: list[dict], current_name: str,
                       artist_mbid: str | None) -> dict:
    """
    Every album of this artist that would move under `current_name`, and every one that can't.

    `albums` are the scan's album dicts for the artist (paths relative to the library).
    """
    root = Path(library_root)
    folder = sanitize_filename(current_name or "", "")
    plan = {"current_name": current_name, "to_folder": folder, "artist_mbid": artist_mbid or None,
            "moves": [], "refused": [], "problems": []}

    if not folder:
        plan["problems"].append("MusicBrainz gave no name to file them under")
        return plan

    for album in albums:
        source = root / (album.get("path") or "")
        label = f"{album.get('album') or source.name}"
        ids = album.get("albumartist_mbids") or []

        if not album.get("path") or not is_within(source, root) or not source.is_dir():
            continue
        if source.parent.name == folder:
            continue  # already there
        if len(ids) > 1:
            plan["refused"].append({"album": label, "path": album["path"],
                                    "reason": "a collaboration - its folder is its own"})
            continue
        if artist_mbid and ids and ids[0] != artist_mbid:
            plan["refused"].append({"album": label, "path": album["path"],
                                    "reason": "tagged as a different artist"})
            continue

        target = root / folder / source.name
        if not is_within(target, root):
            plan["refused"].append({"album": label, "path": album["path"],
                                    "reason": "the new place would fall outside the library"})
            continue
        if target.exists():
            plan["refused"].append({"album": label, "path": album["path"],
                                    "reason": f"'{folder}/{source.name}' is already there"})
            continue

        audio = sorted(p for p in source.iterdir() if p.is_file() and file_extension(p.name) in AUDIO_EXTENSIONS)
        retag = []
        for path in audio:
            current = read_current_tags(path)
            changes = {}
            if current.get("albumartist", "") != current_name:
                changes["albumartist"] = {"from": current.get("albumartist", ""), "to": current_name}
            if artist_mbid and not current.get("musicbrainz_albumartistid"):
                changes["musicbrainz_albumartistid"] = {"from": "", "to": artist_mbid}
            if changes:
                retag.append({"filename": path.name, "changes": changes})

        plan["moves"].append({
            "album": label,
            "path": album["path"],
            "target_path": str(target.relative_to(root)),
            "files": len(audio),
            "retag": retag,
        })

    plan["empty"] = not plan["moves"]
    return plan


def execute_artist_refile(plan: dict, library_root: str) -> dict:
    """
    Carry out a plan: per album, write the tags, then move the folder. A tag that won't write
    keeps that album where it is - moving it would put a folder whose files still name the old
    artist under the new one.
    """
    root = Path(library_root)
    results = {"moved": [], "failed": [], "pictures_moved": [], "removed_folders": []}
    old_folders: set[Path] = set()

    for move in plan.get("moves") or []:
        source = root / move["path"]
        target = root / move["target_path"]

        #? re-checked at the write rather than trusted from the plan, as save_cover_art does
        if not (is_within(source, root) and is_within(target, root)) or target.exists():
            results["failed"].append({"album": move["album"], "reason": "the folder changed since the preview"})
            continue

        try:
            for entry in move["retag"]:
                _write_artist_tags(source / entry["filename"], entry["changes"])
        except Exception as e:
            logger.error(f"could not retag {move['path']}: {e}")
            results["failed"].append({"album": move["album"], "reason": f"a tag wouldn't write: {e}"})
            continue

        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(target))
        except OSError as e:
            logger.error(f"could not move {source} to {target}: {e}")
            results["failed"].append({"album": move["album"], "reason": f"tags were written but the folder wouldn't move: {e}"})
            continue

        results["moved"].append({"from": move["path"], "to": move["target_path"]})
        old_folders.add(source.parent)
        logger.info(f"moved {move['path']} to {move['target_path']}", extra={"frontend": True})

    new_folder = root / (plan.get("to_folder") or "")
    for old in sorted(old_folders):
        results["pictures_moved"] += _carry_artist_pictures(old, new_folder, root)
        before = old.exists()
        _tidy_emptied_artist(old, str(root))
        if before and not old.exists():
            results["removed_folders"].append(old.name)

    return results


def _write_artist_tags(path: Path, changes: dict) -> None:
    import mutagen

    audio = mutagen.File(str(path), easy=True)
    if audio is None:
        raise ValueError(f"{path.name} isn't readable audio")
    for key, change in changes.items():
        audio[key] = change["to"]
    audio.save()


def _carry_artist_pictures(old: Path, new: Path, root: Path) -> list[str]:
    """
    The artist's pictures follow them when the old folder holds nothing else of theirs - only
    names artist_art writes, only where the new folder has none of that name, and only once no
    album is left behind (an album still there means the old name is still in use).
    """
    moved: list[str] = []
    try:
        if not old.is_dir() or not is_within(old, root) or not is_within(new, root):
            return moved
        if any(p.is_dir() for p in old.iterdir()):
            return moved
        stems = set(ARTIST_ART_STEMS.values())
        for path in sorted(p for p in old.iterdir() if p.is_file()):
            if path.stem.lower() in stems and not (new / path.name).exists():
                new.mkdir(parents=True, exist_ok=True)
                shutil.move(str(path), str(new / path.name))
                moved.append(path.name)
    except OSError as e:
        logger.warning(f"couldn't move {old.name}'s pictures: {e}")
    return moved
