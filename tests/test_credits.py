"""
Artist credits: who a track is by, and saying so in MusicBrainz's terms.

Until now every track was tagged with the RELEASE's artist, so applying a release to a
compilation rewrote eighteen different artists into one, and nothing deadwax filed recorded
an artist id at all - which is why the artist page has to fall back to searching by name.

The test that matters most here is the last one: a file deadwax has just tagged must report
NO changes when the preview looks at it again. Multi-valued tags are where that goes wrong -
one side a string, the other a one-item list - and the symptom is an album that can never say
"nothing to change" however many times you apply it.
"""

from pathlib import Path

from src.artists import credit_ids, credit_name
from src.organizer import tag_values, write_tags
from src.retag import read_current_tags
from tests.test_retag import write_flac

SPLIT = [
    {"name": "Dance Gavin Dance", "joinphrase": " / ", "artist": {"id": "id-dgd", "name": "Dance Gavin Dance"}},
    {"name": "Tilian", "joinphrase": "", "artist": {"id": "id-tilian", "name": "Tilian"}},
]
FEATURING = [
    {"name": "Jay-Z", "joinphrase": " feat. ", "artist": {"id": "id-jay", "name": "JAY-Z"}},
    {"name": "Linkin Park", "artist": {"id": "id-lp", "name": "Linkin Park"}},
]


def test_a_credit_reads_the_way_musicbrainz_writes_it():
    assert credit_name(SPLIT) == "Dance Gavin Dance / Tilian"
    assert credit_name(FEATURING) == "Jay-Z feat. Linkin Park"


def test_one_artist_is_just_their_name():
    assert credit_name([{"name": "Portishead", "artist": {"id": "x"}}]) == "Portishead"
    assert credit_name([]) == "" and credit_name(None) == ""


def test_the_credited_name_wins_over_the_artists_own():
    #? MusicBrainz credits "Jay-Z" on a record whose artist page is "JAY-Z", and the tag should
    #? say what the sleeve says
    assert credit_name(FEATURING).startswith("Jay-Z ")


def test_every_id_in_the_credit_is_kept_in_order():
    assert credit_ids(SPLIT) == ["id-dgd", "id-tilian"]
    assert credit_ids([]) == [] and credit_ids(None) == []


def test_the_same_artist_credited_twice_is_one_id():
    doubled = [{"name": "A", "artist": {"id": "id-a"}}, {"name": "A again", "artist": {"id": "id-a"}}]
    assert credit_ids(doubled) == ["id-a"]


# ---------------------------------------------------------------- what gets written

RELEASE = {
    "album": "A Split", "artist": "Dance Gavin Dance / Tilian",
    "artist_mbids": ["id-dgd", "id-tilian"], "release_mbid": "rel-1", "year": "2022",
}


def test_the_album_artist_id_is_written():
    """The thing nothing deadwax filed had until now."""
    values = tag_values(RELEASE, None)
    assert values["musicbrainz_albumartistid"] == ["id-dgd", "id-tilian"]
    assert values["albumartist"] == "Dance Gavin Dance / Tilian"


def test_one_artist_writes_one_value_not_a_list_of_one():
    values = tag_values({**RELEASE, "artist": "Portishead", "artist_mbids": ["id-p"]}, None)
    assert values["musicbrainz_albumartistid"] == "id-p"


def test_a_track_keeps_its_own_artist():
    track = {"position": 2, "title": "Theirs", "artist": "Tilian", "artist_mbids": ["id-tilian"]}
    values = tag_values(RELEASE, track)

    assert values["artist"] == "Tilian", "the track's own credit"
    assert values["musicbrainz_artistid"] == "id-tilian"
    #? and the album still says who the album is by
    assert values["albumartist"] == "Dance Gavin Dance / Tilian"


def test_a_track_with_no_credit_of_its_own_takes_the_releases():
    values = tag_values(RELEASE, {"position": 1, "title": "Ours"})
    assert values["artist"] == "Dance Gavin Dance / Tilian"
    assert values["musicbrainz_artistid"] == ["id-dgd", "id-tilian"]


def test_nothing_is_written_when_musicbrainz_supplied_no_ids():
    #? clearing a tag the user has because MusicBrainz didn't supply one would be destructive
    values = tag_values({k: v for k, v in RELEASE.items() if k != "artist_mbids"}, None)
    assert "musicbrainz_albumartistid" not in values


# ---------------------------------------------------------------- the round trip

def test_a_file_deadwax_just_tagged_reports_no_changes(tmp_path):
    """
    The phantom diff, which is what multi-valued tags get wrong.

    Write two artist ids, read them back, and the preview must see them as equal - not as a
    string against a list. Otherwise the album shows a change on every preview forever and
    "nothing to change" becomes a thing it can never say.
    """
    path = tmp_path / "01 - Theirs.flac"
    write_flac(path, title="Theirs", album="A Split", artist="whoever", tracknumber="1")

    track = {"position": 1, "title": "Theirs", "artist": "Tilian", "artist_mbids": ["id-tilian"]}
    write_tags(path, RELEASE, track)

    current = read_current_tags(path)
    assert current["musicbrainz_albumartistid"] == ["id-dgd", "id-tilian"]
    assert current["musicbrainz_artistid"] == "id-tilian"
    assert current["artist"] == "Tilian"

    #? the diff the preview computes, against the file that was just written from it
    desired = tag_values(RELEASE, track, current)
    differing = {k: v for k, v in desired.items() if current.get(k, "") != v}
    assert differing == {}, f"a file it just wrote already disagrees with itself: {differing}"


def test_applying_a_release_to_a_compilation_keeps_every_artist(tmp_path):
    """What the old rule destroyed: eighteen artists rewritten into one."""
    various = {"album": "A Compilation", "artist": "Various Artists",
               "artist_mbids": ["id-va"], "release_mbid": "rel-2"}
    tracks = [
        {"position": 1, "title": "One", "artist": "Portishead", "artist_mbids": ["id-p"]},
        {"position": 2, "title": "Two", "artist": "Björk", "artist_mbids": ["id-b"]},
    ]

    written = []
    for index, track in enumerate(tracks, start=1):
        path = tmp_path / f"0{index}.flac"
        write_flac(path, title="placeholder", album="A Compilation")
        write_tags(path, various, track)
        written.append(read_current_tags(path))

    assert [w["artist"] for w in written] == ["Portishead", "Björk"]
    assert [w["musicbrainz_artistid"] for w in written] == ["id-p", "id-b"]
    #? and every one of them still knows which album it belongs to
    assert {w["albumartist"] for w in written} == {"Various Artists"}
