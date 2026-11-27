"""
A song's credits - who played what on it - from MusicBrainz (credits, slice C1, 27 Nov 2026). PURE: no I/O, the way
matching.py is. The lookup is the client's (get_release_credits, kept PARSED - kept() below is what is kept), the
asking is src/routes/credits.py's, and every rule of what is shown is here. notes/credits.md has the whole story.

James: "it would be great to be able to see who is playing what instruments in each song."

WHAT IS KEPT (kept): of one release looked up with CREDITS_INC, only what is drawn - per disc and track position the
recording's id, its credits (performers and production, each instrument's credited form with it) and its works'
writers; the release's own credits; its credited artists; its release group's first release date (the album's date)
and whether it is a compilation; and the fetch time. Photography, design, liner notes and the rest are dropped before
anything is kept, and so is `target-credit`: the name shown is always the artist's name. A change to what kept()
keeps is a change of the kept shape - bump CREDITS_SHAPE with it, so no answer of the old shape is ever read again
(the client asks MusicBrainz afresh instead).

THE LEVELS, in order (answer):
  - "song": the song is found on its release and its recording has performer credits;
  - "album": it hasn't (or the song couldn't be placed), but the release itself has performer credits - or, with no
    performer anywhere, production credits of the release's own;
  - "band": no performer credit anywhere on the release, which is no compilation, and its one credited artist is a
    group: its members nothing rules out on the album's date (line_up) - never worded as "on this song";
  - "song" again when the placed song has no performers but has its own writers or production;
  - "none": nothing at all;
  - and two the route answers without a lookup: "unmatched" (the album has no release id, or MusicBrainz has nothing
    at it) and "unavailable" (MusicBrainz or Navidrome couldn't be asked just now, and nothing was kept).
Every answer also says whether other songs on the release have performer credits (`others_credited`).

A WRONG PAIRING IS WORSE THAN NONE (place): a song is found on its release by its recording id when its file has
one, else by disc and track number - and then only when the track numbers of the album's songs on that disc in
Navidrome are exactly the release's positions there. A song that can't be placed never borrows another track's
credits: the answer falls to the album's.
"""

import re
from typing import NamedTuple

#? Bump with any change to what kept() keeps: a kept answer of another shape is never read (the client asks again).
#? 2 (27 Nov, after review): the release group's first release date and whether it's a compilation, and each
#? instrument's credited form, kept; the recordings' first release dates no longer
CREDITS_SHAPE = 2

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
    #? isdecimal, never isdigit: "²" is a digit int() can't read
    return int(text) if text.isdecimal() and int(text) > 0 else None


def _artist(relation: dict) -> dict | None:
    """The artist a relation is to, by their own name - never `target-credit`, the name as printed."""
    if relation.get("target-type") != "artist":
        return None
    artist = _dict(relation.get("artist"))
    name = _text(artist.get("name"))
    if not name:
        return None
    return {"id": _id(artist.get("id")), "name": name}


def _attributes(relation: dict) -> list[str]:
    return [a for a in _list(relation.get("attributes")) if isinstance(a, str)]


def _credited(relation: dict, attributes: list[str]) -> dict[str, str]:
    """How the release credits each attribute, where MusicBrainz says: its `attribute-credits`, a map from an
    attribute's name to the credited text ("guitar": "lead guitar"), present only when some attribute is creditable
    (musicbrainz-server's JSON Relationship serializer)."""
    said = _dict(relation.get("attribute-credits"))
    return {a: _text(said[a]) for a in attributes if _text(said.get(a))}


def _credit(relation) -> dict | None:
    """One relation as kept: a performer's or production's credit to an artist, or None."""
    relation = _dict(relation)
    kind = _text(relation.get("type"))
    artist = _artist(relation)
    if kind not in KEPT_TYPES or artist is None:
        return None
    attributes = _attributes(relation)
    return {"type": kind, "attributes": attributes, "credited": _credited(relation, attributes), **artist,
            "begin": _date(relation.get("begin")), "end": _date(relation.get("end"))}


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
                           "credits": _credits(relations), "written": _written(relations)})
        #? `track-count` and `tracks` are the same tracks: both leave out a pregap (MusicBrainz's own `pregap` key)
        #? and data tracks (`data-tracks`) - musicbrainz-server's Data/Medium.pm counts cdtoc_track_count as the
        #? tracks at a position above 0 that aren't data, and its JSON Medium serializer lists cdtoc_tracks, the same
        #? set. So neither is kept: a disc's count is compared with its `tracks` alone (place)
        media.append({"position": _number(medium.get("position")), "track_count": _number(medium.get("track-count")),
                      "tracks": tracks})
    artists = []
    for credit in _list(payload.get("artist-credit")):
        artist = _dict(_dict(credit).get("artist"))
        if _text(artist.get("name")):
            artists.append({"id": _id(artist.get("id")), "name": _text(artist.get("name")),
                            "type": _text(artist.get("type")) or None})
    group = _dict(payload.get("release-group"))
    return {"shape": CREDITS_SHAPE, "fetched_at": fetched_at, "id": _id(payload.get("id")),
            #? the album's date - original_year's, its release group's first release - never a recording's (a single
            #? out before the album, a compilation's oldest song)
            "first_released": _date(group.get("first-release-date")),
            "compilation": "Compilation" in _list(group.get("secondary-types")),
            "artists": artists, "credits": _credits(payload.get("relations")), "media": media}


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
    number, and the track numbers of the album's songs on that disc, in order (0 for a song with none)."""
    recording: str | None
    disc: int | None
    track: int | None
    numbers: tuple[int, ...]


def navidrome_place(song: dict, album: dict) -> Where:
    """
    Where a song sits, from Navidrome's getSong and getAlbum. A song's `musicBrainzId` is its RECORDING's id (the
    file's musicbrainz_trackid, Picard's recording id - deadwax itself writes none, so every song it filed sends
    ""); `discNumber` and `track` are left out when unset. The numbers are of the album's songs on the same disc - a
    song with no disc number counted with the others that have none.
    """
    song, album = _dict(song), _dict(album)
    disc = _number(song.get("discNumber"))
    numbers = tuple(sorted(_number(other.get("track")) or 0 for other in _list(album.get("song"))
                           if isinstance(other, dict) and _number(other.get("discNumber")) == disc))
    return Where(_id(song.get("musicBrainzId")), disc, _number(song.get("track")), numbers)


def place(found: dict, where: Where) -> dict | None:
    """
    The track of the kept release this song is, or None - never a guess. By the recording id when the file has one
    (an id the release doesn't carry is None, not a fall back to its position). Else by disc and track number, and
    only when the track numbers of the album's songs on that disc are exactly the release's positions there - so a
    folder with a song more or less, two songs of one number or a gap is never paired - a missing disc number read as
    the one disc of a one-disc release, and MusicBrainz having listed every track of the disc.
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
    tracks = [track for track in _list(medium.get("tracks")) if isinstance(track, dict)]
    positions = [track.get("position") for track in tracks]
    if not all(isinstance(position, int) for position in positions):
        return None
    listed = medium.get("track_count")
    if (isinstance(listed, int) and listed > len(tracks)) or tuple(sorted(positions)) != tuple(sorted(where.numbers)):
        return None
    return next((track for track in tracks if track.get("position") == where.track), None)


# ----------------------------------------------------------------- what is shown

def _bare(name: str) -> str:
    """An instrument's or a voice's name with its bracketed qualifier dropped: "drums (drum set)" is "drums"."""
    return re.sub(r"\s*\([^()]*\)\s*$", "", name).strip() or name.strip()


def _with_flags(word: str, attributes: list[str]) -> str:
    flags = [flag for flag in FLAGS if flag in attributes]
    return f"{word} ({', '.join(flags)})" if flags else word


def _named(attributes: list[str], credited: dict) -> list[tuple[str, str]]:
    """
    Each attribute that names an instrument or a voice, as (its name, bracket dropped; the word shown for it): the
    credited form where MusicBrainz gives one - Back in Black's "lead guitar" and "rhythm guitar", for two credits
    of "guitar" - else the name itself, any bracketed qualifier dropped ("drums (drum set)" is "drums").
    """
    named = []
    for attribute in attributes:
        if attribute in FLAGS:
            continue
        credit = credited.get(attribute)
        named.append((_bare(attribute), _text(credit) or _bare(attribute)))
    return named


def _did(credit: dict) -> list[tuple[int, str]]:
    """What one performer credit says they did, each with its place (LEAD, VOCALS, PLAYED, ENSEMBLES) - placed by
    the attribute's own name, said in its credited form (_named)."""
    kind = credit.get("type")
    attributes = [a for a in _list(credit.get("attributes")) if isinstance(a, str)]
    named = _named(attributes, _dict(credit.get("credited")))
    if kind == "vocal":
        voices = [(name, "vocals" if word == "other vocals" else word) for name, word in named] or [("", "vocals")]
        return [(LEAD if name == "lead vocals" else VOCALS, _with_flags(word, attributes)) for name, word in voices]
    if kind == "instrument":
        return [(PLAYED, _with_flags(word, attributes)) for _, word in (named or [("", "instruments")])]
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
        key = _key(artist)
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
                      {"id": person["id"], "name": person["name"], "did": did, "joined": None, "left": None}))
    return [row for _, row in sorted(shown, key=lambda each: each[0])]


def _key(artist: dict) -> str:
    """One person, however many credits: their id, or their name when MusicBrainz gave no id."""
    return artist.get("id") or f"name:{artist.get('name')}"


def performers(credits: list[dict]) -> list[dict]:
    """Who performed, from kept credits: `{id, name, did, joined, left}` a person (joined and left null: only a
    band's line-up says them) - see _people."""
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

def _parts(date: str) -> tuple[int, ...]:
    """A date's year, month and day, as far as it gives them."""
    return tuple(int(part) for part in DATE.match(date).groups() if part is not None)  # type: ignore[union-attr]


def order(date: str, when: str) -> int:
    """
    Whether `date` is before (-1) or after (1) `when`, compared at the precision both dates have - 0 when they can't
    be ordered: the same year, when either gives only a year; the same month, when either gives no day; or the same
    day. "1980-04" against "1980" is 0, against "1980-07-25" is -1.
    """
    mine, theirs = _parts(date), _parts(when)
    both = min(len(mine), len(theirs))
    return (mine[:both] > theirs[:both]) - (mine[:both] < theirs[:both])


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


# ----------------------------------------------------------------- the album's date

def _navidrome_date(album: dict) -> str | None:
    """Navidrome's originalReleaseDate (the originaldate tag, which deadwax writes as original_year) as a date of
    MusicBrainz's form, as precisely as it is given - None when it has no year."""
    original = _dict(_dict(album).get("originalReleaseDate"))
    year, month, day = (_number(original.get(part)) for part in ("year", "month", "day"))
    if not year:
        return None
    date = f"{year:04d}" + (f"-{month:02d}" + (f"-{day:02d}" if day else "") if month else "")
    return date if DATE.match(date) else f"{year:04d}"


def album_date(album: dict, found: dict | None) -> str | None:
    """
    The album's date (original_year's: the release group's first release), as precisely as it is known - what a
    member's time in the band is measured against. The release group's first release date, from the kept lookup;
    Navidrome's originalReleaseDate where it is more precise and agrees (1980-07-25 over 1980); Navidrome's alone
    when the lookup has none. Never a recording's first release (a single out before the album, a compilation's
    oldest song) and never the pressing's date.
    """
    group = _date(_dict(found).get("first_released"))
    navidrome = _navidrome_date(album)
    if group is None:
        return navidrome
    if navidrome and len(navidrome) > len(group) and navidrome.startswith(group):
        return navidrome
    return group


def album_year(album: dict, found: dict | None) -> int | None:
    """The album's year (album_date's), else Navidrome's year - the date tag, the pressing's - for the answer's
    `year` alone: a line-up is only ever measured against album_date."""
    date = album_date(album, found)
    return int(date[:4]) if date else _number(_dict(album).get("year"))


# ----------------------------------------------------------------- the band, when nothing else is known

def others_credited(found: dict, track: dict | None) -> bool:
    """Whether other songs on the release have performer credits - every song but the placed one (`track`, one of
    `found`'s own), or every song when it isn't placed."""
    found = _dict(found)
    return any(performers(_dict(other).get("credits")) for medium in _list(found.get("media"))
               for other in _list(_dict(medium).get("tracks")) if other is not track)


def band_of(found: dict) -> str | None:
    """The group whose line-up stands in for credits - the release's one credited artist, a Group - when no
    performer credit is anywhere on the release and it is no compilation (whose songs come from other times than
    its date). None otherwise."""
    found = _dict(found)
    artists = _list(found.get("artists"))
    if len(artists) != 1 or _dict(artists[0]).get("type") != "Group" or not _dict(artists[0]).get("id"):
        return None
    if found.get("compilation") or performers(found.get("credits")) or others_credited(found, None):
        return None
    return artists[0]["id"]


def membership(begin: str | None, end: str | None, when: str) -> dict | None:
    """
    A time in the band against the album's date (App Design's ruling, 27 Nov: anyone nothing rules out). None when
    it is ruled out: it began after the album's date, or ended before it, compared at the precision both dates have
    (order). Else `{joined, left}`: the year of a start or an end that falls in the album's own year and can't be
    ordered against its date - the app's "joined 1980", "left 1980" - each null otherwise. An unknown start or end
    rules nothing out, an end MusicBrainz knows happened but has no date for among them.
    """
    begin, end = _date(begin), _date(end)
    joined = left = None
    if begin is not None:
        began = order(begin, when)
        if began > 0:
            return None
        if began == 0:
            joined = int(begin[:4])
    if end is not None:
        ended = order(end, when)
        if ended < 0:
            return None
        if ended == 0:
            left = int(end[:4])
    return {"joined": joined, "left": left}


def _joined(held: list[dict], part: str, pick) -> int | None:
    """One person's `joined` (or `left`) over their memberships that count: a year only when every one of them gives
    one - a membership plainly covering the album's date says nothing is in doubt."""
    years = [one[part] for one in held]
    return pick(years) if years and all(year is not None for year in years) else None


def line_up(artist: dict, when: str | None) -> tuple[list[dict], bool]:
    """
    The band's members nothing rules out on the album's date (membership), from the artist lookup deadwax already
    makes (ARTIST_INC's artist-rels: each "member of band" relation, backward), as performers - what each played
    from the membership's attributes ("original" and "founder" dropped, the credited form or the bracket dropped,
    guest/solo/additional kept as words), lead vocals first, the rest by when they joined, then MusicBrainz's order -
    and whether the line-up was measured against dates at all: False when no member has any date, or the album's
    date isn't known, and then every member is shown (the app heads it "The band's members", not "The band in ...").
    """
    memberships = []
    for relation in _list(_dict(artist).get("relations")):
        relation = _dict(relation)
        if relation.get("type") != "member of band" or relation.get("direction") != "backward":
            continue
        person = _artist(relation)
        if person is not None:
            memberships.append((relation, person))
    dated = bool(when) and any(_date(r.get("begin")) or _date(r.get("end")) for r, _ in memberships)
    rows = []
    held: dict[str, list[dict]] = {}
    for relation, person in memberships:
        counted = membership(relation.get("begin"), relation.get("end"), when) if dated else {"joined": None,
                                                                                              "left": None}
        if counted is None:
            continue
        held.setdefault(_key(person), []).append(counted)
        attributes = [a for a in _attributes(relation) if a not in MEMBER_ONLY]
        words = [(LEAD if name == "lead vocals" else VOCALS if name.endswith("vocals") else PLAYED,
                  _with_flags(word, attributes)) for name, word in _named(attributes, _credited(relation, attributes))]
        rows.append((_date(relation.get("begin")) or "9999", person, words))
    rows.sort(key=lambda row: row[0])
    #? a member with nothing known of what they played still counts: a row with no words
    shown = _people([(person, words or [(PLAYED, "")]) for _, person, words in rows])
    for row in shown:
        row["did"] = [word for word in row["did"] if word]
        times = held.get(_key(row), [])
        row["joined"], row["left"] = _joined(times, "joined", min), _joined(times, "left", max)
    return shown, dated


# ----------------------------------------------------------------- the answer

def empty(level: str, year: int | None = None, source_url: str | None = None, others: bool = False) -> dict:
    """An answer with nothing in it: "none", or one of the two the route gives without a lookup."""
    return {"level": level, "year": year, "dated": None, "others_credited": others, "performers": [], "written": [],
            "production": [], "recorded": None, "source_url": source_url}


def release_url(release: str | None) -> str | None:
    return f"{MUSICBRAINZ}/release/{release}" if _id(release) else None


def artist_url(artist: str | None) -> str | None:
    return f"{MUSICBRAINZ}/artist/{artist}" if _id(artist) else None


def answer(found: dict, track: dict | None, *, year: int | None, band: str | None = None,
           members: list[dict] | None = None, dated: bool | None = None) -> dict:
    """
    The route's answer - `{level, year, dated, others_credited, performers: [{id, name, did, joined, left}], written:
    [{job, people}], production: [{job, people: [{id, name}]}], recorded: {begin, end, words} | None, source_url}` -
    from the kept release, the track the song was placed at (one of `found`'s own; None: not placed), and, for
    "band", `band`'s id with its line-up (members) and whether that was measured against dates (line_up). `dated` is
    that, for "band", and null for every other level. The levels are the module docstring's, in its order.
    """
    found = _dict(found)
    release_credits = _list(found.get("credits"))
    song_credits = _list(_dict(track).get("credits")) if track else []
    written = writing(_dict(track).get("written")) if track else []
    produced = production(song_credits, release_credits)
    own_production = production(song_credits, [])
    source = release_url(found.get("id"))
    others = others_credited(found, track)

    def said(level, people, dates, url=source, line_dated=None):
        return {"level": level, "year": year, "dated": line_dated, "others_credited": others, "performers": people,
                "written": written, "production": produced, "recorded": dates, "source_url": url}

    on_song = performers(song_credits)
    if on_song:
        return said("song", on_song, recorded(song_credits))
    on_album = performers(release_credits)
    if on_album:
        return said("album", on_album, recorded(release_credits))
    if members and band and band_of(found) == band:
        return said("band", members, None, artist_url(band), bool(dated))
    if track and (written or own_production):
        return said("song", [], None)
    if produced:
        return said("album", [], None)
    return empty("none", year, source, others)
