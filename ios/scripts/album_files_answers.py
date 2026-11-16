"""
The server's answers the iPhone app's Album info reads the files' tags from (notes/ios.md "Album info"): what
`GET /deadwax/library/tracks?album=<folder>` sends - `{"album": <folder>, "files": read_album_details(<folder>)}`,
src/routes/library.py tracks() - over real files tagged as Picard tags them, one folder per container:

  - a FLAC set of two discs (Vorbis comments: MEDIA per disc, LABEL, CATALOGNUMBER, BARCODE, RELEASECOUNTRY,
    RELEASESTATUS, RELEASETYPE twice, DATE, ORIGINALDATE, GENRE, MUSICBRAINZ_RELEASEGROUPID);
  - an MP3 (ID3: TMED, TPUB, TXXX:CATALOGNUMBER, TXXX:BARCODE, TXXX:MusicBrainz Album Release Country,
    TXXX:MusicBrainz Album Status, TXXX:MusicBrainz Album Type, TXXX:MusicBrainz Release Group Id);
  - an M4A (iTunes freeform atoms ----:com.apple.iTunes:MEDIA and the rest, which Easy MP4 has no names for);

and two as deadwax's own filing tags them - src/organizer.py write_tags, the very writer, over a release as a Get
sends it (GetRelease.swift payload, releasePayload.ts):

  - a FLAC set of two CDs, whose MEDIA is the whole release's formats in every file ("CD + CD", `media_format`);
  - an M4A, which Easy MP4 takes only some of (the country, as "MusicBrainz Release Country"; no media or catalogue
    number).

Written to

  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/albuminfo/files.json

which DeadwaxCoreTests' AlbumInfoTests decodes as AlbumFiles and reads every tag of, and tests/test_ios_contract.py
holds to what this makes now and to the route's own answer over the same folders: so a change to what the route
sends fails there until the file is written again (`.venv/bin/python ios/scripts/album_files_answers.py`) and the
phone's tests run on it. A FLAC's raw tags come in a set's order (mutagen's VCommentDict.keys()), so each file's
`raw` is sorted here, and the file is the same each time it is made.

Every tag here is invented, and ASCII.
"""

import base64
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.library import read_album_details  # noqa: E402
from src.organizer import write_tags  # noqa: E402

FIXTURE = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "albuminfo" / "files.json"

#? a FLAC's STREAMINFO and nothing else: tests/test_library.py write_flac's 42 bytes
FLAC_STREAMINFO = (
    b"fLaC" + b"\x80\x00\x00\x22"
    + b"\x10\x00\x10\x00\x00\x00\x00\x00\x00\x00\x0a\xc4\x42\xf0\x00\x00\x00\x00" + b"\x00" * 16
)

#? MPEG-1 Layer III at 128 kbps and 44.1 kHz, stereo, no padding: twenty 417-byte frames of silence
MP3_FRAMES = (bytes([0xFF, 0xFB, 0x90, 0x64]) + bytes(413)) * 20

#? tests/test_disc_titles.py TINY_M4A: 778 bytes of AAC silence, made once with ffmpeg
TINY_M4A = base64.b64decode(
    "AAAAHGZ0eXBNNEEgAAACAE00QSBpc29taXNvMgAAAtZtb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAB9AAAABkAAB"
    "AAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAACAAACJXRyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAABkAAAAAAAAAAAAAAAAQEA"
    "AAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAACRlZHRzAAAAHGVsc3QAAAAA"
    "AAAAAQAAAZAAAAQAAAEAAAAAAZ1tZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAB9AAAAFkFXEAAAAAAAtaGRscgAA"
    "AAAAAAAAc291bgAAAAAAAAAAAAAAAFNvdW5kSGFuZGxlcgAAAAFIbWluZgAAABBzbWhkAAAAAAAAAAAAAAAkZGlu"
    "ZgAAABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAAEMc3RibAAAAGpzdHNkAAAAAAAAAAEAAABabXA0YQAAAAAA"
    "AAABAAAAAAAAAAAAAQAQAAAAAB9AAAAAAAA2ZXNkcwAAAAADgICAJQABAASAgIAXQBUAAAAAAB9AAAABZwWAgIAF"
    "FYhW5QAGgICAAQIAAAAgc3R0cwAAAAAAAAACAAAAAQAABAAAAAABAAABkAAAABxzdHNjAAAAAAAAAAEAAAABAAAA"
    "AgAAAAEAAAAUc3RzegAAAAAAAAAEAAAAAgAAABRzdGNvAAAAAAAAAAEAAAMCAAAAGnNncGQBAAAAcm9sbAAAAAIA"
    "AAAB//8AAAAcc2JncAAAAAByb2xsAAAAAQAAAAIAAAABAAAAPXVkdGEAAAA1bWV0YQAAAAAAAAAhaGRscgAAAAAA"
    "AAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAIaWxzdAAAAAhmcmVlAAAAEG1kYXQBGCAHARggBw=="
)

GROUP = "4b4f4f2f-7a5e-3d58-9d1a-5c3b5c3c2b10"
#? deadwax's filed set's release group
FILED_GROUP = "5c505030-8b6f-4e69-ae2b-6d4c6d4d3c21"

#? a 2-CD set as a Get sends it: every medium's format joined by " + " (GetRelease.payload's mediaFormat)
FILED_SET = {
    "album": "Exit Planet Dust", "artist": "The Chemical Brothers", "year": "2015", "original_year": "1995",
    "release_mbid": "6d5d6161-9c70-4f7a-bf3c-7e5e7e5e4d32", "release_group_mbid": FILED_GROUP,
    "country": "GB", "media_format": "CD + CD", "catalog_number": "XDUSTCD1X",
    "tracks": [
        {"position": 1, "disc": 1, "disc_position": 1, "title": "Leave Home"},
        {"position": 2, "disc": 1, "disc_position": 2, "title": "In Dust We Trust"},
        {"position": 3, "disc": 2, "disc_position": 1, "title": "Chemical Beats (live)"},
    ],
}

#? a single as a Get sends it, filed as an M4A
FILED_SINGLE = {
    "album": "Midnight City", "artist": "M83", "year": "2011", "original_year": "2011",
    "release_mbid": "7e6e7272-ad81-4a8b-c04d-8f6f8f6f5e43", "release_group_mbid": FILED_GROUP,
    "country": "US", "media_format": "Digital Media", "catalog_number": "MUTE 9534",
    "tracks": [{"position": 1, "title": "Midnight City"}],
}

#? one disc of the set: its number, its medium, and its tracks' titles
FLAC_DISCS = [(1, "CD", ["Speak to Me", "Breathe"]), (2, "DVD-Video", ["Speak to Me (live)"])]


def _flac(path: Path, **tags) -> None:
    from mutagen.flac import FLAC

    path.write_bytes(FLAC_STREAMINFO)
    audio = FLAC(str(path))
    for key, value in tags.items():
        audio[key] = value if isinstance(value, list) else str(value)
    audio.save()


def _mp3(path: Path) -> None:
    from mutagen.id3 import ID3, TALB, TIT2, TMED, TPUB, TRCK, TXXX

    path.write_bytes(MP3_FRAMES)
    tags = ID3()
    tags.add(TIT2(encoding=3, text=["Roads"]))
    tags.add(TALB(encoding=3, text=["Dummy"]))
    tags.add(TRCK(encoding=3, text=["1"]))
    tags.add(TMED(encoding=3, text=['12" Vinyl']))
    tags.add(TPUB(encoding=3, text=["Go! Beat"]))
    tags.add(TXXX(encoding=3, desc="CATALOGNUMBER", text=["828 522-1"]))
    tags.add(TXXX(encoding=3, desc="BARCODE", text=["042282852216"]))
    tags.add(TXXX(encoding=3, desc="MusicBrainz Album Release Country", text=["GB"]))
    tags.add(TXXX(encoding=3, desc="MusicBrainz Album Status", text=["Official"]))
    tags.add(TXXX(encoding=3, desc="MusicBrainz Album Type", text=["album"]))
    tags.add(TXXX(encoding=3, desc="MusicBrainz Release Group Id", text=[GROUP]))
    tags.save(str(path))


def _m4a(path: Path) -> None:
    from mutagen.mp4 import MP4, MP4FreeForm

    path.write_bytes(TINY_M4A)
    audio = MP4(str(path))
    audio["\xa9nam"] = ["Windowlicker"]
    audio["\xa9alb"] = ["Windowlicker"]
    for name, value in [("MEDIA", "Digital Media"), ("LABEL", "Warp"), ("CATALOGNUMBER", "WAP105CD"),
                        ("BARCODE", "801061010524"), ("MusicBrainz Album Release Country", "XW"),
                        ("MusicBrainz Album Status", "Promotion"), ("MusicBrainz Album Type", "single")]:
        audio["----:com.apple.iTunes:" + name] = [MP4FreeForm(value.encode("utf-8"))]
    audio.save()


def make(root: Path) -> list[tuple[str, str]]:
    """The three folders under `root`, as (name, folder relative to `root`)."""
    flac = root / "Pink Floyd" / "The Dark Side of the Moon [Box]"
    flac.mkdir(parents=True)
    for disc, medium, titles in FLAC_DISCS:
        for number, title in enumerate(titles, start=1):
            _flac(flac / f"{disc}-{number:02d} {title}.flac", title=title, album="The Dark Side of the Moon",
                  tracknumber=str(number), discnumber=str(disc), media=medium, label="Harvest",
                  catalognumber="SHVL 804", barcode="5099902894225", releasecountry="GB", releasestatus="official",
                  releasetype=["album", "live"], date="2011-09-26", originaldate="1973-03-01", genre="Rock",
                  musicbrainz_releasegroupid=GROUP)
    mp3 = root / "Portishead" / "Dummy"
    mp3.mkdir(parents=True)
    _mp3(mp3 / "01 Roads.mp3")
    m4a = root / "Aphex Twin" / "Windowlicker"
    m4a.mkdir(parents=True)
    _m4a(m4a / "01 Windowlicker.m4a")
    filed = root / "The Chemical Brothers" / "Exit Planet Dust"
    filed.mkdir(parents=True)
    for track in FILED_SET["tracks"]:
        path = filed / f"{track['position']:02d} {track['title']}.flac"
        path.write_bytes(FLAC_STREAMINFO)
        write_tags(path, FILED_SET, track)
    single = root / "M83" / "Midnight City"
    single.mkdir(parents=True)
    path = single / "01 Midnight City.m4a"
    path.write_bytes(TINY_M4A)
    write_tags(path, FILED_SINGLE, FILED_SINGLE["tracks"][0])
    return [("flac", str(flac.relative_to(root))), ("mp3", str(mp3.relative_to(root))), ("m4a", str(m4a.relative_to(root))),
            ("deadwax-flac", str(filed.relative_to(root))), ("deadwax-m4a", str(single.relative_to(root)))]


def tidy(answer: dict) -> dict:
    """The route's answer with each file's raw tags sorted (a FLAC's come in a set's order)."""
    files = [{**file, "raw": sorted(file.get("raw") or [])} for file in answer["files"]]
    return {**answer, "files": files}


def answers() -> dict:
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        cases = [{"name": name, "answer": tidy({"album": album, "files": read_album_details(root / album)})}
                 for name, album in make(root)]
    return {"made_from": "src/routes/library.py tracks(): read_album_details (ios/scripts/album_files_answers.py)",
            "cases": cases}


def text() -> str:
    return json.dumps(answers(), indent=1, ensure_ascii=True) + "\n"


if __name__ == "__main__":
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(text(), encoding="utf-8")
