"""
Which of a release's tracks a Soulseek folder doesn't have (2.0.0-player.15), for the app's source
cards: an amber "Missing “Threads”" line under a folder of ten tracks out of eleven.

Worked out where the pairing is (matching.missing_tracks, inside score_candidate), because the
pairing - `track_mapping`, whole file dicts - is dropped before a candidate reaches the page. The
page is sent the first MISSING_NAMED in tracklist order, as {position, disc, title}, and how many
in all (`missing_count`), through the real find_candidates route with slskd faked. A video track
(a CD+DVD's films) is never missing from a folder of audio; a release that is all video keeps every
track. A folder with every track names none; a release with no tracklist has nothing to miss. And
the page is told how many of the release's tracks are audio (`audio_expected`), so a card's Tracks
counts against the same tracks the missing line does: "14 of 14" for a CD+DVD shared whole, never
"14 of 34" with nothing missing (review).
"""

import asyncio
from types import SimpleNamespace

from src.matching import audio_tracks, group_files_by_directory, missing_tracks, rank_candidates, score_candidate
from src.routes import download as routes
from src.routes.download import MISSING_NAMED, _serialize_candidate
from tests.test_matching import EXPECTED_BASE, EXPECTED_TRACKS, album_files, make_file, make_response

THIRD = ["Silence", "Hunter", "Nylon Smile", "The Rip", "Plastic", "We Carry On", "Deep Water",
         "Machine Gun", "Small", "Magic Doors", "Threads"]
THIRD_TRACKS = [{"position": n, "title": title, "disc": 1, "disc_position": n} for n, title in enumerate(THIRD, 1)]


def folder(name, titles, user="crate_dig"):
    files = [make_file(f"share\\{name}\\{n:02d} - {title}.flac") for n, title in enumerate(titles, 1)]
    return make_response(user, files)


def scored(response, tracks):
    candidate = group_files_by_directory([response])[0]
    return score_candidate(candidate, {**EXPECTED_BASE, "tracks": tracks})


def test_a_folder_without_one_track_names_it():
    found = scored(folder("Third", THIRD[:-1]), THIRD_TRACKS)

    assert found["missing_tracks"] == [{"position": 11, "disc": 1, "title": "Threads"}]
    assert (found["matched_tracks"], found["expected_tracks"]) == (10, 11)


def test_a_folder_with_every_track_names_none():
    assert scored(folder("Third", THIRD), THIRD_TRACKS)["missing_tracks"] == []


def test_the_missing_are_in_tracklist_order_wherever_they_fall():
    kept = [title for title in THIRD if title not in ("Hunter", "Small", "Silence")]
    found = scored(folder("Third", kept), THIRD_TRACKS)

    assert [track["title"] for track in found["missing_tracks"]] == ["Silence", "Hunter", "Small"]
    assert [track["position"] for track in found["missing_tracks"]] == [1, 2, 9]


def test_a_video_track_is_never_missing_from_a_folder_of_audio():
    """A CD+DVD deluxe: the films never arrive as audio files, so they are never "missing"."""
    tracks = [*THIRD_TRACKS, {"position": 12, "title": "Machine Gun (video)", "disc": 2, "video": True}]
    found = scored(folder("Third", THIRD), tracks)

    assert found["missing_tracks"] == []


def test_a_cd_and_dvd_shared_whole_is_counted_against_its_audio_tracks():
    """What a card's Tracks counts against: the CD's 11, not 11 + the DVD's - and the score unchanged."""
    films = [{"position": 11 + n, "title": f"Film {n}", "disc": 2, "video": True} for n in range(1, 4)]
    found = scored(folder("Third", THIRD), [*THIRD_TRACKS, *films])

    assert (found["audio_expected"], found["expected_tracks"], found["missing_tracks"]) == (11, 14, [])
    sent = _serialize_candidate(found)
    assert (sent["audio_expected"], sent["missing_count"]) == (11, 0)


def test_audio_expected_is_every_track_of_an_ordinary_album_and_none_without_a_tracklist():
    assert scored(folder("Third", THIRD[:-1]), THIRD_TRACKS)["audio_expected"] == 11
    assert scored(folder("Third", THIRD), [])["audio_expected"] == 0
    #? all video: every track, as the missing line counts them
    assert len(audio_tracks([{"position": 1, "video": True}, {"position": 2, "video": True}])) == 2


def test_a_release_that_is_all_video_keeps_every_track():
    tracks = [{"position": 1, "title": "Roseland", "video": True}, {"position": 2, "title": "Glory Box", "video": True}]
    assert missing_tracks(tracks, {}) == [{"position": 1, "disc": None, "title": "Roseland"},
                                          {"position": 2, "disc": None, "title": "Glory Box"}]


def test_a_release_with_no_tracklist_has_nothing_to_miss():
    found = scored(folder("Third", THIRD), [])
    assert found["missing_tracks"] == []


def test_the_page_is_sent_the_first_few_and_how_many_in_all():
    found = scored(folder("Third", THIRD[:3]), THIRD_TRACKS)
    sent = _serialize_candidate(found)

    assert MISSING_NAMED == 5
    assert [track["title"] for track in sent["missing_tracks"]] == ["The Rip", "Plastic", "We Carry On", "Deep Water", "Machine Gun"]
    assert sent["missing_count"] == 8
    #? the pairing itself never reaches the page
    assert "track_mapping" not in sent


def test_a_complete_folder_is_sent_none_and_a_count_of_nought():
    sent = _serialize_candidate(scored(folder("Third", THIRD), THIRD_TRACKS))
    assert (sent["missing_tracks"], sent["missing_count"]) == ([], 0)


def test_rank_candidates_keeps_what_each_folder_is_missing():
    whole = make_response("vinylhead", album_files(r"share\MHTRTC"))
    short = make_response("crate_dig", album_files(r"share\MHTRTC short")[:-1])

    ranked = {c["username"]: c for c in rank_candidates([whole, short], EXPECTED_BASE)}

    assert ranked["vinylhead"]["missing_tracks"] == []
    assert ranked["crate_dig"]["missing_tracks"] == [
        {"position": 5, "disc": None, "title": EXPECTED_TRACKS[4]["title"]},
    ]


class Slskd:
    def __init__(self, responses):
        self.responses = responses

    async def search_all(self, queries, **kwargs):
        return self.responses


def test_find_candidates_answers_with_each_folders_missing_tracks():
    """Through the real route: the cards' amber line comes from what Find answers."""
    request = SimpleNamespace(
        app=SimpleNamespace(state=SimpleNamespace(store=None, slskd_client=Slskd([folder("Third", THIRD[:-1])]),
                                                  musicbrainz_client=None)),
        is_disconnected=lambda: asyncio.sleep(0, result=False),
    )
    body = routes.FindCandidatesRequest(artist="Portishead", album="Third", release_mbid=None, tracks=THIRD_TRACKS)

    answer = asyncio.run(routes.find_candidates(request, body))

    [candidate] = answer["candidates"]
    assert (candidate["missing_tracks"], candidate["missing_count"]) == ([{"position": 11, "disc": 1, "title": "Threads"}], 1)
    assert candidate["audio_expected"] == 11
