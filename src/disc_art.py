"""
CD art: a picture of the disc itself, saved beside the tracks as `disc.<ext>`.

Asked for by James after songs in Amperfy showed pictures that didn't match their album - which
turned out to be Navidrome showing a song's DISC artwork, and finding a scan of the CD that came
with the download. The disc slot is a real thing players show; this fills it deliberately.

The SEVENTH writer, and like save_cover_art() narrow enough not to need a plan/execute split for
the write itself: it writes image files with names it made, and nothing else. Choosing WHICH
images is pure and lives here, so it is testable without a network; fetching them is the
route's job.

WHERE IT GOES, and why these names:
  - `disc.<ext>` for a single-disc album, `disc<N>.<ext>` per disc of a set. Navidrome's
    DiscArtPriority default is "disc*.*, cd*.*, cover.*, ..." and it matches a NUMBER after the
    prefix to the disc it belongs to, with an unnumbered file standing in for any disc (read in
    its source, core/artwork/disc.go). Kodi and Jellyfin read `disc.*` too.
  - `disc` ahead of `cd` in that order is also what makes a fetched image win over a `cd.jpg`
    scan a download brought with it, without deleting the scan.

WHERE IT COMES FROM, in order:
  1. The Cover Art Archive's "Medium" images for the EXACT release the album is tagged with -
     the disc of the pressing you actually have, which is the point of this whole project, and
     no key needed.
  2. fanart.tv's `cdart`, for the release GROUP - clean, transparent, made to be displayed, and
     numbered per disc - when a fanart.tv key is set.

What it will NOT do: guess which of several unnumbered CAA images belongs to which disc of a set
beyond the one safe case (as many images as discs, in upload order). Otherwise one image is used
for every disc, unnumbered - a right picture on the wrong disc is less wrong than inventing an
order.
"""

import re
from pathlib import Path

from src.logger import logger
from src.matching import AUDIO_EXTENSIONS, file_extension
from src.organizer import is_within

DISC_ART_STEM = "disc"

#? The Cover Art Archive's own type for "a picture of the disc".
CAA_MEDIUM = "Medium"

#? "Disc 2", "CD2", "disc two"? - the last isn't worth it. A number after a word meaning disc.
DISC_IN_COMMENT = re.compile(r"(?:disc|disk|cd|medium|side)\s*[#-]?\s*(\d+)", re.IGNORECASE)

#? Only names this module makes may be written - the writer refuses anything else.
OWN_NAME = re.compile(r"disc\d*\.(jpg|jpeg|png|gif|webp)")

EXTENSIONS = {"image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp"}


def disc_art_filename(disc: int | None, mime: str) -> str:
    """`disc.png` for the one image a whole album shares, `disc2.jpg` for disc 2's own."""
    return f"{DISC_ART_STEM}{disc or ''}.{EXTENSIONS.get(mime, 'jpg')}"


def _caa_url(image: dict, size: str) -> str | None:
    """One CAA image at COVER_ART_SIZE - the same sizes a cover is saved at."""
    thumbnails = image.get("thumbnails") or {}
    if size == "full":
        return image.get("image")
    wanted = {"250": ("250", "small"), "500": ("500", "large"), "1200": ("1200", "large")}
    for key in wanted.get(size, ("500", "large")):
        if thumbnails.get(key):
            return thumbnails[key]
    return image.get("image")


def choose_from_caa(images: list[dict], discs: list[int], size: str = "500") -> dict[int | None, str]:
    """
    Which of a release's Cover Art Archive images to save, as {disc or None: url}.

    Only "Medium" images - the disc itself. Numbered by the image's own comment where it says
    ("Disc 2", "CD2"); for a set with as many unnumbered images as discs, in the order they were
    uploaded, which is how editors add them; otherwise the first stands for every disc.
    """
    media = [image for image in images or [] if CAA_MEDIUM in (image.get("types") or [])]
    if not media:
        return {}

    if len(discs) <= 1:
        url = _caa_url(media[0], size)
        return {None: url} if url else {}

    numbered: dict[int | None, str] = {}
    for image in media:
        match = DISC_IN_COMMENT.search(image.get("comment") or "")
        if match and int(match.group(1)) in discs and int(match.group(1)) not in numbered:
            url = _caa_url(image, size)
            if url:
                numbered[int(match.group(1))] = url
    if numbered:
        return numbered

    if len(media) == len(discs):
        return {disc: url for disc, image in zip(sorted(discs), media)
                if (url := _caa_url(image, size))}

    url = _caa_url(media[0], size)
    return {None: url} if url else {}


def choose_from_fanarttv(cdarts: list[dict], discs: list[int]) -> dict[int | None, str]:
    """
    Which of fanart.tv's `cdart` images to save, as {disc or None: url} - the most liked per disc.

    fanart.tv numbers its disc art, so a set gets one per disc where it has them; a single-disc
    album gets its disc 1 (or whichever it has) as the unnumbered `disc.png`.
    """
    best: dict[int, dict] = {}
    for art in cdarts or []:
        if not art.get("url"):
            continue
        try:
            disc = int(art.get("disc") or 1)
        except ValueError:
            disc = 1
        likes = int(art.get("likes") or 0)
        if disc not in best or likes > int(best[disc].get("likes") or 0):
            best[disc] = art

    if not best:
        return {}

    if len(discs) <= 1:
        return {None: (best.get(1) or next(iter(best.values())))["url"]}

    chosen = {disc: best[disc]["url"] for disc in discs if disc in best}
    return chosen or {None: next(iter(best.values()))["url"]}


# ------------------------------------------------------------------ the album on disk


def _album_directory(album_path: str, library_root: str) -> Path | None:
    root = Path(library_root or "")
    directory = root / (album_path or "")
    if not library_root or not album_path or not is_within(directory, root) or not directory.is_dir():
        return None
    return directory


def plan_disc_art(album_path: str, library_root: str) -> dict:
    """
    What fetching CD art for this album would go on: its release, its discs, what is there already.

    Reads the folder and one track's tags. The release comes from the TAGS, as a cover's does,
    so there is nothing to choose and nothing to preview: this asks for the disc of the release
    the album already claims to be.
    """
    from src.library import find_disc_art
    import mutagen

    directory = _album_directory(album_path, library_root)
    if directory is None:
        return {"problem": "that album is not inside the library"}

    try:
        entries = sorted(p for p in directory.iterdir() if p.is_file())
    except OSError as e:
        return {"problem": f"could not read the folder: {e}"}

    release = group = None
    discs: set[int] = set()

    for entry in entries:
        if file_extension(entry.name) not in AUDIO_EXTENSIONS:
            continue
        try:
            audio = mutagen.File(str(entry), easy=True)
        except Exception:
            continue
        if audio is None:
            continue

        def first(key):
            try:
                values = audio.get(key) or []
            except (KeyError, ValueError):
                return ""
            return str(values[0]).strip() if values else ""

        release = release or first("musicbrainz_albumid") or None
        group = group or first("musicbrainz_releasegroupid") or None
        number = first("discnumber").partition("/")[0]
        if number.isdigit() and int(number) > 0:
            discs.add(int(number))

    existing = [name for name in find_disc_art(entries) if name.lower().startswith(DISC_ART_STEM)]

    return {
        "problem": None,
        "release_mbid": release,
        "release_group_mbid": group,
        #? a single-disc album with no disc tags is [] - one unnumbered image, as for one disc
        "discs": sorted(discs),
        #? deadwax's own `disc*` files; a download's `cd*` scans don't count, and a fetched
        #? `disc.*` sits ahead of them in every reader's order anyway
        "existing": existing,
    }


def save_disc_art(album_path: str, library_root: str, files: list[tuple[str, bytes]],
                  replace: bool = False) -> dict:
    """
    Write disc images into an album folder, and touch nothing else.

    Containment is re-checked here, and only names this module makes are written, for the same
    reason save_cover_art() re-checks: this is the function that writes. An image already there
    under the same name is kept unless `replace`.
    """
    directory = _album_directory(album_path, library_root)
    if directory is None:
        return {"written": [], "problems": ["that album is not inside the library"]}

    written, problems = [], []

    for name, data in files:
        if not OWN_NAME.fullmatch(name):
            problems.append(f"{name} is not a CD art name deadwax writes")
            continue

        target = directory / name
        if target.exists() and not replace:
            continue

        try:
            target.write_bytes(data)
            written.append(name)
        except OSError as e:
            logger.error(f"could not write {target}: {e}")
            problems.append(f"could not save {name}: {e}")

    if written:
        logger.info(f"saved CD art {', '.join(written)} into {directory.name}", extra={"frontend": True})

    return {"written": written, "problems": problems}
