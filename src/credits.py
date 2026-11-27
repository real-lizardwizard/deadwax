"""
A song's credits - who played what on it - from MusicBrainz (credits, slice C1, 27 Nov 2026). PURE: no I/O, the way
matching.py is. The lookup is the client's (get_release_credits, kept PARSED - kept() below is what is kept), the
asking is src/routes/credits.py's, and every rule of what is shown is here. notes/credits.md has the whole story.

James: "it would be great to be able to see who is playing what instruments in each song."

WHAT IS KEPT (kept): of one release looked up with CREDITS_INC, only what is drawn - per disc and track position the
recording's id, its first release date and its credits (performers and production), and its works' writers; the
release's own credits; the release's credited artists; and the fetch time. Photography, design, liner notes and the
rest are dropped before anything is kept, and so is `target-credit`: the name shown is always the artist's name. A
change to what kept() keeps is a change of the kept shape - bump CREDITS_SHAPE with it, so no answer of the old shape
is ever read again (the client asks MusicBrainz afresh instead).

THE LEVELS, in order (answer):
  - "song": the song is found on its release and its recording has performer credits;
  - "album": it hasn't (or the song couldn't be placed), but the release itself has performer credits - or, with no
    performer anywhere, production credits of the release's own;
  - "band": no performer credit anywhere on the release, and its one credited artist is a group whose members'
    time in the band surely covers the album's date (line_up) - never worded as "on this song";
  - "song" again when the placed song has no performers but has its own writers or production;
  - "none": nothing at all;
  - and two the route answers without a lookup: "unmatched" (the album has no release id, or MusicBrainz has nothing
    at it) and "unavailable" (MusicBrainz or Navidrome couldn't be asked just now, and nothing was kept).

A WRONG PAIRING IS WORSE THAN NONE (place): a song is found on its release by its recording id when its file has
one, else by disc and track number - and then only when the release's track count on that disc equals the album's
in Navidrome. A song that can't be placed never borrows another track's credits: the answer falls to the album's.
"""

import re
from typing import NamedTuple

#? Bump with any change to what kept() keeps: a kept answer of another shape is never read (the client asks again)
CREDITS_SHAPE = 1

LEVELS = ("song", "album", "band", "none", "unmatched", "unavailable")

#? A MusicBrainz id, as every id this module reads or hands on must look
MBID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
#? A date as MusicBrainz writes one, to the year, the month or the day
DATE = re.compile(r"^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$")

MUSICBRAINZ = "https://musicbrainz.org"

#? Who performed: the relation types read as performers, and the word an ensemble's credit is said with
PERFORMING = frozenset({"instrument", "vocal", "performer", "performing orchestra", "conductor", "chorus master",
                        "concertmaster"})
ENSEMBLE = {"performing orchestra": "orchestra", "conductor": "conductor", "chorus master": "chorus master",
            "concertmaster": "concertmaster"}
#? A performer credit's place in the list: lead vocals, other vocals, instruments (in MusicBrainz's order), then an
#? orchestra, choir or conductor
LEAD, VOCALS, PLAYED, ENSEMBLES = 0, 1, 2, 3
#? Kept as words on a performer's credit - "guitar (solo)", "vocals (guest)" - and never read as an instrument
FLAGS = ("guest", "solo", "additional")
#? A member's attributes that say nothing of what they played
MEMBER_ONLY = frozenset({"original", "founder"})

#? Production's jobs, in the order shown - producer, engineers, mix, then mastering - each with its noun
PRODUCTION = (
    ("producer", "producer"),
    ("engineer", "engineer"),
    ("recording", "recording engineer"),
    ("audio", "audio engineer"),
    ("sound", "sound engineer"),
    ("programming", "programming"),
    ("editor", "editing"),
    ("mix", "mix"),
    ("remixer", "remix"),
    ("mastering", "mastering"),
)
PRODUCTION_ORDER = {kind: index for index, (kind, _) in enumerate(PRODUCTION)}
PRODUCTION_NOUN = dict(PRODUCTION)
#? A job's attributes said before its noun - "Assistant engineer", "Co-producer", "Remastering" - in this order
JOB_WORDS = (("executive", "executive "), ("co", "co-"), ("associate", "associate "), ("additional", "additional "),
             ("assistant", "assistant "), ("re", "re"))

#? A work's writers: who wrote both, the music, or the words
WRITING = {"writer": "both", "composer": "music", "lyricist": "words", "librettist": "words"}

KEPT_TYPES = PERFORMING | frozenset(PRODUCTION_ORDER)

MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December")


# ----------------------------------------------------------------- reading MusicBrainz's answer, defensively

def _list(value) -> list:
    return value if isinstance(value, list) else []


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def _text(value) -> str:
    return value.strip() if isinstance(value, str) else ""


def _id(value) -> str | None:
    text = _text(value).lower()
    return text if MBID.match(text) else None


def _date(value) -> str | None:
    text = _text(value)
    return text if DATE.match(text) else None


def _number(value) -> int | None:
    """A positive whole number, from an int or its digits - None for anything else (0 is Navidrome's "unset")."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    text = _text(value)
    return int(text) if text.isdigit() and int(text) > 0 else None


def _artist(relation: dict) -> dict | None:
    """The artist a relation is to, by their own name - never `target-credit`, the name as printed."""
    if relation.get("target-type") != "artist":
        return None
    artist = _dict(relation.get("artist"))
    name = _text(artist.get("name"))
    if not name:
        return None
    return {"id": _id(artist.get("id")), "name": name}


def _credit(relation) -> dict | None:
    """One relation as kept: a performer's or production's credit to an artist, or None."""
    relation = _dict(relation)
    kind = _text(relation.get("type"))
    artist = _artist(relation)
    if kind not in KEPT_TYPES or artist is None:
        return None
    return {"type": kind, "attributes": [a for a in _list(relation.get("attributes")) if isinstance(a, str)],
            **artist, "begin": _date(relation.get("begin")), "end": _date(relation.get("end"))}


def _credits(relations) -> list[dict]:
    return [credit for credit in map(_credit, _list(relations)) if credit is not None]


def _written(relations) -> list[dict]:
    """The writers of the works a recording is a performance of - each work's writer, composer, lyricist and
    librettist relations, in MusicBrainz's order."""
    found = []
    for relation in _list(relations):
        relation = _dict(relation)
        if relation.get("type") != "performance" or relation.get("target-type") != "work":
            continue
        for writing in _list(_dict(relation.get("work")).get("relations")):
            writing = _dict(writing)
            kind = _text(writing.get("type"))
            artist = _artist(writing)
            if kind in WRITING and artist is not None:
                found.append({"type": kind, **artist})
    return found


def kept(payload: dict, fetched_at: float) -> dict:
    """What is kept of one release looked up with the client's CREDITS_INC - see the module's docstring."""
    payload = _dict(payload)
    media = []
    for medium in _list(payload.get("media")):
        medium = _dict(medium)
        tracks = []
        for track in _list(medium.get("tracks")):
            track = _dict(track)
            recording = _dict(track.get("recording"))
            position = _number(track.get("position"))
            if position is None:
                continue
            relations = recording.get("relations")
            tracks.append({"position": position, "recording": _id(recording.get("id")),
                           "first_released": _date(recording.get("first-release-date")),
                           "credits": _credits(relations), "written": _written(relations)})
        media.append({"position": _number(medium.get("position")), "track_count": _number(medium.get("track-count")),
                      "tracks": tracks})
    artists = []
    for credit in _list(payload.get("artist-credit")):
        artist = _dict(_dict(credit).get("artist"))
        if _text(artist.get("name")):
            artists.append({"id": _id(artist.get("id")), "name": _text(artist.get("name")),
                            "type": _text(artist.get("type")) or None})
    return {"shape": CREDITS_SHAPE, "fetched_at": fetched_at, "id": _id(payload.get("id")), "artists": artists,
            "credits": _credits(payload.get("relations")), "media": media}


def is_current(value) -> bool:
    """Whether a kept answer is of the shape kept() keeps now (CREDITS_SHAPE read at each call, never captured)."""
    return isinstance(value, dict) and value.get("shape") == CREDITS_SHAPE


# ----------------------------------------------------------------- finding the song on its release

def release_of(album: dict) -> str | None:
    """The release an album in Navidrome is: its `musicBrainzId`, read from the folder's MUSICBRAINZ_ALBUMID - only
    ever an id of MusicBrainz's shape, which is all that is put in a lookup's address."""
    return _id(_dict(album).get("musicBrainzId"))


class Where(NamedTuple):
    """Where Navidrome says a song is: its recording id (the file's own, when it has one), its disc and track
    number, and how many songs the album has on that disc."""
    recording: str | None
    disc: int | None
    track: int | None
    count: int


def navidrome_place(song: dict, album: dict) -> Where:
    """
    Where a song sits, from Navidrome's getSong and getAlbum. A song's `musicBrainzId` is its RECORDING's id (the
    file's musicbrainz_trackid, Picard's recording id - deadwax itself writes none, so every song it filed sends
    ""); `discNumber` and `track` are left out when unset. The count is of the album's songs on the same disc - a
    song with no disc number counted with the others that have none.
    """
    song, album = _dict(song), _dict(album)
    disc = _number(song.get("discNumber"))
    count = sum(1 for other in _list(album.get("song"))
                if isinstance(other, dict) and _number(other.get("discNumber")) == disc)
    return Where(_id(song.get("musicBrainzId")), disc, _number(song.get("track")), count)


def place(found: dict, where: Where) -> dict | None:
    """
    The track of the kept release this song is, or None - never a guess. By the recording id when the file has one
    (an id the release doesn't carry is None, not a fall back to its position). Else by disc and track number, and
    only when the release has exactly as many tracks on that disc as the album has songs there - a missing disc
    number read as the one disc of a one-disc release - and MusicBrainz listed every track of the disc.
    """
    media = [_dict(medium) for medium in _list(_dict(found).get("media"))]
    if where.recording:
        for medium in media:
            for track in _list(medium.get("tracks")):
                if _dict(track).get("recording") == where.recording:
                    return track
        return None
    if where.track is None:
        return None
    if where.disc is None:
        medium = media[0] if len(media) == 1 else None
    else:
        medium = next((m for m in media if m.get("position") == where.disc), None)
    if medium is None:
        return None
    tracks = _list(medium.get("tracks"))
    listed = medium.get("track_count")
    if (isinstance(listed, int) and listed > len(tracks)) or len(tracks) != where.count:
        return None
    return next((track for track in tracks if _dict(track).get("position") == where.track), None)


# ----------------------------------------------------------------- what is shown

def _bare(name: str) -> str:
    """An instrument's or a voice's name with its bracketed qualifier dropped: "drums (drum set)" is "drums"."""
    return re.sub(r"\s*\([^()]*\)\s*$", "", name).strip() or name.strip()


def _with_flags(word: str, attributes: list[str]) -> str:
    flags = [flag for flag in FLAGS if flag in attributes]
    return f"{word} ({', '.join(flags)})" if flags else word


def _did(credit: dict) -> list[tuple[int, str]]:
    """What one performer credit says they did, each with its place (LEAD, VOCALS, PLAYED, ENSEMBLES)."""
    kind = credit.get("type")
    attributes = [a for a in _list(credit.get("attributes")) if isinstance(a, str)]
    named = [_bare(a) for a in attributes if a not in FLAGS]
    if kind == "vocal":
        voices = ["vocals" if name == "other vocals" else name for name in named] or ["vocals"]
        return [(LEAD if voice == "lead vocals" else VOCALS, _with_flags(voice, attributes)) for voice in voices]
    if kind == "instrument":
        return [(PLAYED, _with_flags(name, attributes)) for name in (named or ["instruments"])]
    if kind == "performer":
        return [(PLAYED, _with_flags("performer", attributes))]
    if kind in ENSEMBLE:
        return [(ENSEMBLES, _with_flags(ENSEMBLE[kind], attributes))]
    return []


def _people(rows: list[tuple[dict, list[tuple[int, str]]]]) -> list[dict]:
    """
    One row per person, from (artist, [(place, word)]) in MusicBrainz's order: their words joined in one list - lead
    vocals first, then the rest as MusicBrainz gives them, each once - and the rows ordered by each person's
    foremost credit (lead vocals, other vocals, instruments, an ensemble), MusicBrainz's order among equals.
    """
    people: dict[str, dict] = {}
    for index, (artist, words) in enumerate(rows):
        if not words:
            continue
        key = artist.get("id") or f"name:{artist.get('name')}"
        person = people.get(key)
        if person is None:
            person = people[key] = {"id": artist.get("id"), "name": artist["name"], "words": [], "first": index}
        person["words"].extend((place, len(person["words"]), word) for place, word in words)
    shown = []
    for person in people.values():
        did: list[str] = []
        for _, _, word in sorted(person["words"], key=lambda w: (w[0] != LEAD, w[1])):
            if word not in did:
                did.append(word)
        shown.append(((min(place for place, _, _ in person["words"]), person["first"]),
                      {"id": person["id"], "name": person["name"], "did": did}))
    return [row for _, row in sorted(shown, key=lambda each: each[0])]


def performers(credits: list[dict]) -> list[dict]:
    """Who performed, from kept credits: `{id, name, did}` a person - see _people."""
    return _people([(credit, _did(credit)) for credit in _list(credits)
                    if isinstance(credit, dict) and credit.get("type") in PERFORMING and credit.get("name")])


def _person(credit: dict) -> dict:
    return {"id": credit.get("id"), "name": credit["name"]}


def _add(people: list[dict], credit: dict) -> None:
    person = _person(credit)
    if not any((p["id"] or p["name"]) == (person["id"] or person["name"]) for p in people):
        people.append(person)


def _job(credit: dict) -> str:
    attributes = _list(credit.get("attributes"))
    words = "".join(word for attribute, word in JOB_WORDS if attribute in attributes)
    label = words + PRODUCTION_NOUN[credit["type"]]
    return label[:1].upper() + label[1:]


def production(song_credits: list[dict], release_credits: list[dict]) -> list[dict]:
    """
    Production as `{job, people}` rows: the song's own jobs, then the release's for every kind of job the song
    doesn't list (so a release's mastering is added, its extra engineers aren't when the song names its engineers),
    ordered producer, engineers, mix, mastering - a job with no attribute before its assistants - each person once.
    """
    own = [c for c in _list(song_credits) if isinstance(c, dict) and c.get("type") in PRODUCTION_NOUN and c.get("name")]
    kinds = {credit["type"] for credit in own}
    added = [c for c in _list(release_credits) if isinstance(c, dict) and c.get("type") in PRODUCTION_NOUN
             and c.get("name") and c["type"] not in kinds]
    rows: dict[str, dict] = {}
    for index, credit in enumerate(own + added):
        job = _job(credit)
        row = rows.get(job)
        if row is None:
            plain = not any(attribute for attribute, _ in JOB_WORDS if attribute in _list(credit.get("attributes")))
            row = rows[job] = {"order": (PRODUCTION_ORDER[credit["type"]], not plain, index), "job": job, "people": []}
        _add(row["people"], credit)
    return [{"job": row["job"], "people": row["people"]} for row in sorted(rows.values(), key=lambda r: r["order"])]


def writing(written: list[dict]) -> list[dict]:
    """
    Who wrote it, as `{job, people}` lines: "Written by" its writers - or, when a work separates them, "Music by"
    (its writers and composers) and "Words by" (its writers, lyricists and librettists). Each person once a line.
    """
    both: list[dict] = []
    music: list[dict] = []
    words: list[dict] = []
    for credit in _list(written):
        if not isinstance(credit, dict) or not credit.get("name"):
            continue
        part = WRITING.get(credit.get("type"))
        if part == "both":
            _add(both, credit)
        elif part == "music":
            _add(music, credit)
        elif part == "words":
            _add(words, credit)
    if not music and not words:
        return [{"job": "Written by", "people": both}] if both else []
    lines = []
    for job, extra in (("Music by", music), ("Words by", words)):
        people: list[dict] = []
        for credit in both + extra:
            _add(people, credit)
        if extra or both:
            lines.append({"job": job, "people": people})
    return lines


# ----------------------------------------------------------------- dates

def _bounds(date: str) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    """The earliest and latest day a date of any precision can mean."""
    year, month, day = DATE.match(date).groups()  # type: ignore[union-attr]
    if month is None:
        return (int(year), 1, 1), (int(year), 12, 31)
    if day is None:
        return (int(year), int(month), 1), (int(year), int(month), 31)
    return (int(year), int(month), int(day)), (int(year), int(month), int(day))


def _said(date: str, with_year: bool = True) -> str:
    year, month, day = DATE.match(date).groups()  # type: ignore[union-attr]
    if month is None or not 1 <= int(month) <= 12:
        return year
    words = MONTHS[int(month) - 1]
    if day is not None:
        words = f"{int(day)} {words}"
    return f"{words} {year}" if with_year else words


def recorded_words(begin: str | None, end: str | None) -> str | None:
    """When it was recorded, in words: "April to May 1980", "December 1979 to January 1980", "12 April 1980"."""
    dates = sorted(date for date in (begin, end) if date)
    if not dates:
        return None
    first, last = dates[0], dates[-1]
    if first == last:
        return _said(first)
    if first[:4] == last[:4]:
        if len(first) == 4 or len(last) == 4:
            return first[:4]
        return f"{_said(first, False)} to {_said(last, False)} {first[:4]}"
    return f"{_said(first)} to {_said(last)}"


def recorded(credits: list[dict]) -> dict | None:
    """When its performers' credits say it was recorded - `{begin, end, words}` - or None when they carry no dates."""
    shown = [c for c in _list(credits) if isinstance(c, dict) and c.get("type") in PERFORMING]
    begins = [c["begin"] for c in shown if _date(c.get("begin"))]
    ends = [c["end"] for c in shown if _date(c.get("end"))]
    if not begins and not ends:
        return None
    begin = min(begins) if begins else None
    end = max(ends) if ends else None
    return {"begin": begin, "end": end, "words": recorded_words(begin, end)}


# ----------------------------------------------------------------- the band, when nothing else is known

def album_year(album: dict, found: dict | None) -> int | None:
    """
    The album's year (`original_year`, the release group's first release): Navidrome's originalReleaseDate - read
    from the originaldate tag, which deadwax writes as original_year - else the earliest first release of the
    release's recordings, else Navidrome's year (the date tag, the pressing's).
    """
    album = _dict(album)
    year = _number(_dict(album.get("originalReleaseDate")).get("year"))
    if year:
        return year
    firsts = [t.get("first_released") for m in _list(_dict(found).get("media")) for t in _list(_dict(m).get("tracks"))
              if isinstance(t, dict) and _date(t.get("first_released"))]
    if firsts:
        return int(min(firsts)[:4])
    return _number(album.get("year"))


def album_when(year: int | None, album: dict, found: dict | None) -> str | None:
    """
    The album's date, as closely as it is known, within its year - what a member's time in the band is measured
    against: Navidrome's full originalReleaseDate of that year, else the earliest first release of the release's
    recordings in that year, else the year alone.
    """
    if not year:
        return None
    original = _dict(_dict(album).get("originalReleaseDate"))
    if _number(original.get("year")) == year and _number(original.get("month")):
        month, day = _number(original.get("month")), _number(original.get("day"))
        date = f"{year:04d}-{month:02d}" + (f"-{day:02d}" if day else "")
        if DATE.match(date):
            return date
    firsts = [t.get("first_released") for m in _list(_dict(found).get("media")) for t in _list(_dict(m).get("tracks"))
              if isinstance(t, dict) and _date(t.get("first_released")) and t["first_released"][:4] == f"{year:04d}"]
    return min(firsts) if firsts else f"{year:04d}"


def _anyone_performed(found: dict) -> bool:
    found = _dict(found)
    if performers(found.get("credits")):
        return True
    return any(performers(_dict(track).get("credits")) for medium in _list(found.get("media"))
               for track in _list(_dict(medium).get("tracks")))


def band_of(found: dict) -> str | None:
    """The group whose line-up stands in for credits - the release's one credited artist, a Group - when no
    performer credit is anywhere on the release. None otherwise."""
    artists = _list(_dict(found).get("artists"))
    if len(artists) != 1 or _dict(artists[0]).get("type") != "Group" or not _dict(artists[0]).get("id"):
        return None
    return None if _anyone_performed(found) else artists[0]["id"]


def covers(begin: str | None, end: str | None, ended: bool, when: str) -> bool:
    """
    Whether a time in the band SURELY covers `when` - not merely may: it began no later than the album's earliest
    day could be, and it hadn't ended (or ended no earlier than its latest day could be). An unknown start, or an
    end with no date, is not sure. With only the album's year known, a member who joined or left that year isn't
    counted - better a line-up short a name than one with somebody who wasn't there.
    """
    begin, end = _date(begin), _date(end)
    if begin is None or not DATE.match(when or ""):
        return False
    earliest, latest = _bounds(when)
    if _bounds(begin)[1] > earliest:
        return False
    if end is None:
        return not ended
    return _bounds(end)[0] >= latest


def line_up(artist: dict, when: str | None) -> list[dict]:
    """
    The band's members whose time in it surely covers the album's date (covers), from the artist lookup deadwax
    already makes (ARTIST_INC's artist-rels: each "member of band" relation, backward), as performers - what each
    played from the membership's attributes ("original" and "founder" dropped, a bracket dropped, guest/solo/
    additional kept as words), lead vocals first, the rest by when they joined, then MusicBrainz's order.
    """
    if not when:
        return []
    rows = []
    for relation in _list(_dict(artist).get("relations")):
        relation = _dict(relation)
        if relation.get("type") != "member of band" or relation.get("direction") != "backward":
            continue
        person = _artist(relation)
        if person is None or not covers(relation.get("begin"), relation.get("end"), bool(relation.get("ended")), when):
            continue
        attributes = [a for a in _list(relation.get("attributes")) if isinstance(a, str) and a not in MEMBER_ONLY]
        played = [_bare(a) for a in attributes if a not in FLAGS]
        words = [(LEAD if name == "lead vocals" else VOCALS if name.endswith("vocals") else PLAYED,
                  _with_flags(name, attributes)) for name in played]
        rows.append((_date(relation.get("begin")) or "9999", person, words))
    rows.sort(key=lambda row: row[0])
    #? a member with nothing known of what they played still counts: a row with no words
    shown = _people([(person, words or [(PLAYED, "")]) for _, person, words in rows])
    for row in shown:
        row["did"] = [word for word in row["did"] if word]
    return shown


# ----------------------------------------------------------------- the answer

def empty(level: str, year: int | None = None, source_url: str | None = None) -> dict:
    """An answer with nothing in it: "none", or one of the two the route gives without a lookup."""
    return {"level": level, "year": year, "performers": [], "written": [], "production": [], "recorded": None,
            "source_url": source_url}


def release_url(release: str | None) -> str | None:
    return f"{MUSICBRAINZ}/release/{release}" if _id(release) else None


def artist_url(artist: str | None) -> str | None:
    return f"{MUSICBRAINZ}/artist/{artist}" if _id(artist) else None


def answer(found: dict, track: dict | None, *, year: int | None, members: list[dict] | None = None,
           band: str | None = None) -> dict:
    """
    The route's answer - `{level, year, performers: [{id, name, did}], written: [{job, people}], production:
    [{job, people: [{id, name}]}], recorded: {begin, end, words} | None, source_url}` - from the kept release, the
    track the song was placed at (None: not placed), and, for "band", the line-up (members) of `band`'s id. The
    levels are the module docstring's, in its order.
    """
    found = _dict(found)
    release_credits = _list(found.get("credits"))
    song_credits = _list(_dict(track).get("credits")) if track else []
    written = writing(_dict(track).get("written")) if track else []
    produced = production(song_credits, release_credits)
    own_production = production(song_credits, [])
    source = release_url(found.get("id"))

    def said(level, people, dates, url=source):
        return {"level": level, "year": year, "performers": people, "written": written, "production": produced,
                "recorded": dates, "source_url": url}

    on_song = performers(song_credits)
    if on_song:
        return said("song", on_song, recorded(song_credits))
    on_album = performers(release_credits)
    if on_album:
        return said("album", on_album, recorded(release_credits))
    if members and band and band_of(found) == band:
        return said("band", members, None, artist_url(band))
    if track and (written or own_production):
        return said("song", [], None)
    if produced:
        return said("album", [], None)
    return empty("none", year, source)
