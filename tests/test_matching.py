"""
Tests for the candidate scoring engine.

These matter more than usual: slskd lives on the user's home server, so this logic can't be
exercised end to end from a dev machine. Fixtures below are shaped exactly like slskd's
`search_responses()` output (see slskd_api.apis._types.SearchResponseItem / SearchFile).

Run with:  .venv/bin/python -m pytest tests/ -q
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.matching import (  # noqa: E402
    detect_edition_tags,
    disc_folder,
    group_files_by_directory,
    join_disc_folders,
    match_tracks_to_files,
    normalize,
    rank_candidates,
    score_candidate,
    split_remote_path,
    title_similarity,
)


def make_file(path, size=30_000_000, length=None, extension=None, bitrate=None):
    entry = {"filename": path, "size": size, "code": 1, "isLocked": False}
    entry["extension"] = extension if extension is not None else path.rpartition(".")[2]
    if length is not None:
        entry["length"] = length
    if bitrate is not None:
        entry["bitRate"] = bitrate
    return entry


def make_response(username, files, free_slot=True, queue=0, speed=2_000_000):
    return {
        "username": username,
        "files": files,
        "fileCount": len(files),
        "hasFreeUploadSlot": free_slot,
        "lockedFileCount": 0,
        "lockedFiles": [],
        "queueLength": queue,
        "token": 1,
        "uploadSpeed": speed,
    }


#? a small real-shaped release: Boards of Canada - Music Has the Right to Children
EXPECTED_TRACKS = [
    {"position": 1, "title": "Wildlife Analysis", "length_ms": 87_000},
    {"position": 2, "title": "An Eagle in Your Mind", "length_ms": 383_000},
    {"position": 3, "title": "The Color of the Fire", "length_ms": 103_000},
    {"position": 4, "title": "Telephasic Workshop", "length_ms": 386_000},
    {"position": 5, "title": "Triangles & Rhombuses", "length_ms": 111_000},
]

EXPECTED_BASE = {
    "artist": "Boards of Canada",
    "album": "Music Has the Right to Children",
    "year": "1998",
    "tracks": EXPECTED_TRACKS,
    "edition_tags": [],
}


def album_files(directory, extension="flac", offset_sec=0):
    return [
        make_file(
            f"{directory}\\0{t['position']} - {t['title']}.{extension}",
            length=(t["length_ms"] // 1000) + offset_sec,
        )
        for t in EXPECTED_TRACKS
    ]


# ---------------------------------------------------------------- helpers

def test_split_remote_path_handles_backslashes():
    directory, filename = split_remote_path(r"@@user\Music\Artist\Album\01 track.flac")
    assert directory == "@@user/Music/Artist/Album"
    assert filename == "01 track.flac"


def test_split_remote_path_handles_bare_filename():
    assert split_remote_path("track.flac") == ("", "track.flac")


def test_normalize_strips_punctuation_and_case():
    assert normalize("The Color of the Fire!") == "the color of the fire"
    assert normalize("Triangles & Rhombuses") == "triangles rhombuses"


def test_title_similarity_matches_despite_track_number_and_suffix():
    assert title_similarity("The Color of the Fire", "03 - The Color of the Fire (2013 Remaster).flac") == 1.0


def test_title_similarity_rejects_unrelated_track():
    assert title_similarity("Wildlife Analysis", "05 - Completely Different Song.flac") < 0.6


def test_detect_edition_tags_finds_remaster_and_deluxe():
    assert "REMASTER" in detect_edition_tags("Album (2011 Remastered)")
    assert "DELUXE" in detect_edition_tags("Album [Deluxe Edition]")


def test_detect_edition_tags_prefers_super_deluxe_over_deluxe():
    tags = detect_edition_tags("Album (Super Deluxe Edition)")
    assert "SUPER DELUXE" in tags
    assert "DELUXE" not in tags


# ---------------------------------------------------------------- grouping

def test_group_files_by_directory_splits_one_peer_across_albums():
    responses = [
        make_response("alice", [
            make_file(r"share\Music\BoC\Geogaddi\01 Ready Lets Go.flac"),
            make_file(r"share\Music\BoC\MHTRTC\01 Wildlife Analysis.flac"),
        ])
    ]
    candidates = group_files_by_directory(responses)
    assert len(candidates) == 2
    assert {c["directory_name"] for c in candidates} == {"Geogaddi", "MHTRTC"}


def test_group_files_by_directory_drops_non_audio():
    responses = [
        make_response("alice", [
            make_file(r"share\Album\01 track.flac"),
            make_file(r"share\Album\cover.jpg"),
            make_file(r"share\Album\notes.txt"),
        ])
    ]
    candidates = group_files_by_directory(responses)
    assert len(candidates) == 1
    assert len(candidates[0]["files"]) == 1


# ---------------------------------------------------------------- track mapping

def test_match_tracks_to_files_maps_every_track():
    files = album_files(r"share\MHTRTC")
    mapping = match_tracks_to_files(EXPECTED_TRACKS, files)
    assert len(mapping) == len(EXPECTED_TRACKS)
    assert mapping[3]["track"]["title"] == "The Color of the Fire"


def test_match_tracks_to_files_never_reuses_a_file():
    # two tracks, but the folder only holds one of them
    files = [make_file(r"share\Album\01 - Wildlife Analysis.flac")]
    mapping = match_tracks_to_files(EXPECTED_TRACKS, files)
    assert len(mapping) == 1
    assert list(mapping.keys()) == [1]


# ---------------------------------------------------------------- scoring

def test_exact_match_scores_highly():
    responses = [make_response("alice", album_files(r"share\Music Has the Right to Children"))]
    ranked = rank_candidates(responses, EXPECTED_BASE)
    assert ranked[0]["score"] > 0.9
    assert ranked[0]["matched_tracks"] == 5


def test_wrong_track_count_ranks_below_exact_match():
    good = make_response("alice", album_files(r"share\MHTRTC"))
    # a bootleg-ish folder with the right name but way too many files
    padded = album_files(r"share\MHTRTC Bootleg") + [
        make_file(rf"share\MHTRTC Bootleg\bonus {i}.flac", length=200) for i in range(12)
    ]
    bad = make_response("bob", padded)

    ranked = rank_candidates([good, bad], EXPECTED_BASE)
    assert ranked[0]["username"] == "alice"
    assert ranked[0]["score"] > ranked[1]["score"]


def test_remaster_request_prefers_remaster_folder():
    """The original complaint: asking for a remaster should surface the remaster."""
    expected = {**EXPECTED_BASE, "edition_tags": ["REMASTER"], "year": "2013"}

    original = make_response("alice", album_files(r"share\Music Has the Right to Children"))
    remaster = make_response("bob", album_files(r"share\Music Has the Right to Children (2013 Remaster)"))

    ranked = rank_candidates([original, remaster], expected)
    assert ranked[0]["username"] == "bob"
    assert "REMASTER" in ranked[0]["detected_edition_tags"]


def test_plain_edition_request_deprioritises_deluxe_folder():
    """Inverse case - a plain release shouldn't quietly pull down a deluxe edition."""
    plain = make_response("alice", album_files(r"share\Music Has the Right to Children"))
    deluxe = make_response("bob", album_files(r"share\Music Has the Right to Children (Deluxe Edition)"))

    ranked = rank_candidates([plain, deluxe], EXPECTED_BASE)
    assert ranked[0]["username"] == "alice"


def test_edition_mismatch_is_not_a_hard_filter():
    """
    Folder names often omit edition text entirely. A remaster request must still return
    non-matching folders rather than an empty list, otherwise real results disappear.
    """
    expected = {**EXPECTED_BASE, "edition_tags": ["REMASTER"]}
    plain_only = [make_response("alice", album_files(r"share\Music Has the Right to Children"))]

    ranked = rank_candidates(plain_only, expected)
    assert len(ranked) == 1
    assert ranked[0]["score"] > 0


def test_prefer_lossless_ranks_flac_over_mp3():
    flac = make_response("alice", album_files(r"share\MHTRTC FLAC", extension="flac"))
    mp3 = make_response("bob", album_files(r"share\MHTRTC MP3", extension="mp3"))

    ranked = rank_candidates([flac, mp3], EXPECTED_BASE, format_preference="prefer_lossless")
    assert ranked[0]["username"] == "alice"


def test_lossless_only_excludes_lossy_candidates():
    flac = make_response("alice", album_files(r"share\MHTRTC FLAC", extension="flac"))
    mp3 = make_response("bob", album_files(r"share\MHTRTC MP3", extension="mp3"))

    ranked = rank_candidates([flac, mp3], EXPECTED_BASE, format_preference="lossless_only")
    assert len(ranked) == 1
    assert ranked[0]["username"] == "alice"


def test_any_format_keeps_both():
    flac = make_response("alice", album_files(r"share\MHTRTC FLAC", extension="flac"))
    mp3 = make_response("bob", album_files(r"share\MHTRTC MP3", extension="mp3"))

    ranked = rank_candidates([flac, mp3], EXPECTED_BASE, format_preference="any")
    assert len(ranked) == 2


def test_duration_mismatch_lowers_score():
    """Same track names, wildly wrong lengths - probably live versions or the wrong recording."""
    right = make_response("alice", album_files(r"share\MHTRTC A"))
    wrong = make_response("bob", album_files(r"share\MHTRTC B", offset_sec=120))

    ranked = rank_candidates([right, wrong], EXPECTED_BASE)
    assert ranked[0]["username"] == "alice"
    assert ranked[0]["signals"]["duration_match"] == 1.0
    assert ranked[1]["signals"]["duration_match"] == 0.0


def test_missing_duration_data_is_ignored_not_penalised():
    """slskd omits `length` for some files; that's absence of evidence, not evidence of a bad match."""
    no_lengths = [make_file(rf"share\MHTRTC\0{t['position']} - {t['title']}.flac") for t in EXPECTED_TRACKS]
    responses = [make_response("alice", no_lengths)]

    ranked = rank_candidates(responses, EXPECTED_BASE)
    assert ranked[0]["signals"]["duration_match"] is None
    assert ranked[0]["score"] > 0.9


def test_release_group_search_without_tracklist_still_ranks():
    """Group-level search has no tracklist; tracklist signals drop out instead of zeroing the score."""
    expected = {"artist": "Boards of Canada", "album": "Music Has the Right to Children",
                "year": "1998", "tracks": [], "edition_tags": []}
    responses = [make_response("alice", album_files(r"share\Music Has the Right to Children"))]

    ranked = rank_candidates(responses, expected)
    assert ranked[0]["signals"]["title_match"] is None
    assert ranked[0]["signals"]["track_count"] is None
    assert ranked[0]["score"] > 0


def test_peer_health_breaks_ties():
    fast = make_response("alice", album_files(r"share\MHTRTC"), free_slot=True, queue=0, speed=5_000_000)
    slow = make_response("bob", album_files(r"share\MHTRTC"), free_slot=False, queue=500, speed=1_000)

    ranked = rank_candidates([fast, slow], EXPECTED_BASE)
    assert ranked[0]["username"] == "alice"


def test_score_candidate_exposes_signal_breakdown():
    """The UI shows *why* a candidate ranked where it did, so the shape is part of the contract."""
    responses = [make_response("alice", album_files(r"share\MHTRTC"))]
    candidate = group_files_by_directory(responses)[0]
    scored = score_candidate(candidate, EXPECTED_BASE)

    assert set(scored["signals"]) == {
        "title_match", "track_count", "duration_match", "edition", "format", "peer"
    }
    assert scored["formats"] == ["flac"]
    assert scored["track_mapping"][1]["track"]["title"] == "Wildlife Analysis"


def test_candidate_carries_peer_stats_for_the_ui():
    """Speed/queue/size drive both the display and the candidate filters, so they're contractual."""
    files = album_files(r"share\MHTRTC")
    responses = [make_response("alice", files, free_slot=True, queue=3, speed=1_500_000)]

    ranked = rank_candidates(responses, EXPECTED_BASE)
    candidate = ranked[0]

    assert candidate["upload_speed"] == 1_500_000
    assert candidate["queue_length"] == 3
    assert candidate["has_free_slot"] is True
    assert candidate["total_size"] == sum(f["size"] for f in files)


def test_bitrates_collected_from_lossy_files():
    files = [
        make_file(r"share\Album\01 - Wildlife Analysis.mp3", length=87, bitrate=320),
        make_file(r"share\Album\02 - An Eagle in Your Mind.mp3", length=383, bitrate=320),
    ]
    ranked = rank_candidates([make_response("alice", files)], EXPECTED_BASE, format_preference="any")
    assert ranked[0]["bitrates"] == [320]


def test_bit_depth_and_sample_rate_are_what_the_client_reported():
    """Filtered and sorted on in the candidates panel (v0.9.11); empty means unknown, not low."""
    hires = [dict(make_file(r"share\Album\01 - Wildlife Analysis.flac", length=87),
                  bitDepth=24, sampleRate=96000),
             dict(make_file(r"share\Album\02 - An Eagle in Your Mind.flac", length=383),
                  bitDepth=16, sampleRate=44100)]
    silent = [make_file(r"other\Album\01 - Wildlife Analysis.mp3", length=87, bitrate=256)]
    vbr = [dict(make_file(r"third\Album\01 - Wildlife Analysis.mp3", length=87, bitrate=245),
                isVariableBitRate=True)]

    ranked = {c["username"]: c for c in rank_candidates(
        [make_response("alice", hires), make_response("bob", silent), make_response("cat", vbr)],
        EXPECTED_BASE, format_preference="any")}

    assert (ranked["alice"]["bit_depths"], ranked["alice"]["sample_rates"]) == ([16, 24], [44100, 96000])
    assert (ranked["bob"]["bit_depths"], ranked["bob"]["sample_rates"]) == ([], [])
    assert [ranked[u]["variable_bitrate"] for u in ("alice", "bob", "cat")] == [False, False, True]


def test_the_quality_fields_reach_the_panel():
    from src.routes.download import _serialize_candidate
    files = [dict(make_file(r"share\Album\01 - Wildlife Analysis.flac", length=87), bitDepth=24, sampleRate=48000)]
    candidate = rank_candidates([make_response("alice", files)], EXPECTED_BASE, format_preference="any")[0]
    sent = _serialize_candidate(candidate)
    assert (sent["bit_depths"], sent["sample_rates"], sent["variable_bitrate"]) == ([24], [48000], False)


def test_empty_responses_produce_no_candidates():
    assert rank_candidates([], EXPECTED_BASE) == []


# ===== alternate performances in folder names ================================


def test_instrumental_is_detected_in_a_soulseek_folder_name():
    """
    The other half of the instrumental fix. This vocabulary tags the FOLDER a peer is
    offering; EDITION_KEYWORDS in ui/src/lib/release.ts tags the RELEASE you picked, and
    the two are scored against each other. A marker present in only one of them is worse than
    one present in neither - the release would carry a tag no folder could ever match.
    """
    from src.matching import detect_edition_tags

    assert detect_edition_tags("Dance Gavin Dance - Afterburner (2020) [Instrumental]") == {
        "INSTRUMENTAL"
    }
    assert detect_edition_tags("Afterburner (2020) [FLAC]") == set()


def test_acoustic_and_a_cappella_are_detected_including_the_common_misspelling():
    from src.matching import detect_edition_tags

    assert detect_edition_tags("Some Album (Acoustic)") == {"ACOUSTIC"}
    assert detect_edition_tags("Some Album (A Cappella)") == {"A CAPPELLA"}
    #? "acapella" and "a capella" are both far more common in the wild than the correct
    #? spelling, and a folder name is typed by a stranger
    assert detect_edition_tags("Some Album (Acappella)") == {"A CAPPELLA"}
    assert detect_edition_tags("Some Album (A Capella)") == {"A CAPPELLA"}


def test_the_new_markers_do_not_disturb_the_existing_ones():
    from src.matching import detect_edition_tags

    assert detect_edition_tags("Album (Super Deluxe Edition)") == {"SUPER DELUXE"}
    assert detect_edition_tags("Album (2011 Remaster)") == {"REMASTER"}
    #? a release can genuinely be both
    assert detect_edition_tags("Album (Deluxe) [Instrumental]") == {"DELUXE", "INSTRUMENTAL"}


def test_the_fast_matcher_pairs_exactly_as_title_similarity_would():
    """
    match_tracks_to_files skips work title_similarity() would do - a name normalised once, a
    perfect match ending the search, pairs difflib's upper bounds rule out (v0.9.28) - and must
    still choose exactly what calling it on every pair chooses. Held here against that plain
    version, on names built to be awkward: numbered, bare "Track NN", near-misses, one title
    inside another, duplicates, and files with no name at all.
    """
    from src.matching import TITLE_MATCH_THRESHOLD, match_tracks_to_files, split_remote_path

    def plainly(tracks, files):
        remaining, mapping = list(files), {}
        for track in tracks:
            best, best_score = None, 0.0
            for f in remaining:
                score = title_similarity(track.get("title", ""), split_remote_path(f["filename"])[1])
                if score > best_score:
                    best, best_score = f, score
            if best is not None and best_score >= TITLE_MATCH_THRESHOLD:
                mapping[track["position"]] = {"file": best, "score": round(best_score, 3), "track": track}
                remaining.remove(best)
        return mapping

    titles = ["Roads", "Road", "Sour Times", "Sour Times (Nobody Loves Me)", "It's a Fire",
              "Its A Fire", "Numb", "Glory Box", "", "Wandering Star", "Wandering Stars"]
    names = ["01 - Roads.flac", "Road.mp3", "Track 03.mp3", "04 sour times.flac", "Sour Times (live).flac",
             "its a fire.flac", "Numb (edit).mp3", "glory-box.flac", ".flac", "10 - Wandering Star.flac",
             "Wandering Star.flac", "11 - Elysium.flac", "Numb.flac"]
    import random
    rng = random.Random(28)
    for _ in range(200):
        tracks = [{"position": n, "title": t} for n, t in enumerate(rng.sample(titles, rng.randint(1, len(titles))), 1)]
        files = [{"filename": f"@@peer\\share\\Album\\{name}"} for name in rng.sample(names, rng.randint(0, len(names)))]
        assert match_tracks_to_files(tracks, files) == plainly(tracks, files), (tracks, files)


# ------------------------------------------------------------ a set shared one folder per disc
#
# Reported on the Experience edition of Wish You Were Here: a peer had every track, in "CD 1" and
# "CD 2" folders as it should be, and the panel showed two poor half-albums instead of one good
# candidate - each folder scored alone against the whole two-disc release.

#? The Experience edition, as MusicBrainz lists it: two discs, and disc 2 repeats disc 1's titles
#? with something added, so every one of them CONTAINS a disc 1 title.
EXPERIENCE_TRACKS = [
    {"position": 1, "disc": 1, "title": "Shine On You Crazy Diamond (Parts I-V)", "length_ms": 813_000},
    {"position": 2, "disc": 1, "title": "Welcome to the Machine", "length_ms": 452_000},
    {"position": 3, "disc": 1, "title": "Have a Cigar", "length_ms": 308_000},
    {"position": 4, "disc": 1, "title": "Wish You Were Here", "length_ms": 335_000},
    {"position": 5, "disc": 1, "title": "Shine On You Crazy Diamond (Parts VI-IX)", "length_ms": 750_000},
    {"position": 6, "disc": 2, "title": "Shine On You Crazy Diamond (live at Wembley 1974)", "length_ms": 1_223_000},
    {"position": 7, "disc": 2, "title": "Raving and Drooling (live at Wembley 1974)", "length_ms": 755_000},
    {"position": 8, "disc": 2, "title": "You've Got to Be Crazy (live at Wembley 1974)", "length_ms": 1_093_000},
    {"position": 9, "disc": 2, "title": "Wine Glasses (from 'Household Objects' project)", "length_ms": 137_000},
    {"position": 10, "disc": 2, "title": "Have a Cigar (alternative version)", "length_ms": 432_000},
    {"position": 11, "disc": 2, "title": "Wish You Were Here (with Stéphane Grappelli)", "length_ms": 374_000},
]
EXPERIENCE = {"artist": "Pink Floyd", "album": "Wish You Were Here", "year": "2011",
              "tracks": EXPERIENCE_TRACKS, "edition_tags": []}
SET_FOLDER = "@@share\\Music\\Pink Floyd - Wish You Were Here (Experience Edition)"


def disc_files(folder, tracks):
    numbered = {}
    files = []
    for t in tracks:
        numbered[t["disc"]] = numbered.get(t["disc"], 0) + 1
        files.append(make_file(f"{folder}\\{numbered[t['disc']]:02d} - {t['title']}.flac",
                               length=t["length_ms"] // 1000))
    return files


def experience_set(folder=SET_FOLDER, cd1="CD 1", cd2="CD 2"):
    return (disc_files(f"{folder}\\{cd1}", EXPERIENCE_TRACKS[:5])
            + disc_files(f"{folder}\\{cd2}", EXPERIENCE_TRACKS[5:]))


def test_disc_folders_are_recognised_by_the_names_sharers_give_them():
    for name, number in [("CD 1", 1), ("cd2", 2), ("CD01", 1), ("cd.2", 2), ("Disc 2", 2), ("Disk 3", 3),
                         ("Disc One", 1), ("[CD2]", 2), ("(Disc 1)", 1), ("Disc 1 - Wish You Were Here", 1)]:
        assert disc_folder(name) == ("", number), name
    assert disc_folder("Wish You Were Here CD2") == ("Wish You Were Here", 2)
    assert disc_folder("Wish You Were Here (Disc 2)") == ("Wish You Were Here", 2)
    #? a disc marker needs a separator in front of it, and a number of its own
    for name in ["ABCD1", "ACDC 2", "Discography", "Disco Inferno 2", "CD", "CD 2011 Remaster",
                 "1994 - Dummy", "Metallica - S&M2 (2020)"]:
        assert disc_folder(name) is None, name


def test_a_set_shared_one_folder_per_disc_is_one_candidate():
    ranked = rank_candidates([make_response("glassbeads", experience_set())], EXPERIENCE)

    assert len(ranked) == 1, "the two disc folders are one album, not two poor halves of it"
    best = ranked[0]
    assert best["directory_name"] == "Pink Floyd - Wish You Were Here (Experience Edition)"
    assert best["disc_folders"] == ["CD 1", "CD 2"]
    assert best["matched_tracks"] == 11 and best["audio_file_count"] == 11
    assert best["signals"]["track_count"] == 1.0 and best["signals"]["duration_match"] == 1.0
    assert best["score"] > 0.9


def test_each_track_pairs_with_a_file_from_its_own_disc():
    """
    Disc 2's "Wish You Were Here (with Stéphane Grappelli)" CONTAINS disc 1's "Wish You Were
    Here", so a matcher that takes the first containing name gives disc 1's track the disc 2
    file whenever disc 2 is listed first - and the organizer names and tags the file from that.
    """
    files = list(reversed(experience_set()))
    mapping = match_tracks_to_files(EXPERIENCE_TRACKS, files)

    for position, entry in mapping.items():
        disc = EXPERIENCE_TRACKS[position - 1]["disc"]
        assert f"\\CD {disc}\\" in entry["file"]["filename"], (position, entry["file"]["filename"])
    assert len(mapping) == 11


def test_a_single_disc_release_keeps_the_disc_folders_apart():
    """A peer's "CD 1" of the two-disc set can be exactly the one-disc album that was picked."""
    standard = {**EXPERIENCE, "year": "1975",
                "tracks": [{**t, "disc": 1} for t in EXPERIENCE_TRACKS[:5]]}
    ranked = rank_candidates([make_response("glassbeads", experience_set())], standard)

    assert len(ranked) == 2
    assert ranked[0]["directory_name"] == "Pink Floyd - Wish You Were Here (Experience Edition) / CD 1", \
        "a disc folder is named with its album, since CD 1 alone says nothing"
    assert ranked[0]["matched_tracks"] == 5 and ranked[0]["audio_file_count"] == 5
    assert ranked[0]["disc_folders"] == []


def test_a_release_with_no_tracklist_is_offered_the_whole_set():
    ranked = rank_candidates([make_response("glassbeads", experience_set())], {**EXPERIENCE, "tracks": []})
    assert [c["disc_folders"] for c in ranked] == [["CD 1", "CD 2"]]


def test_discs_named_beside_each_other_join_on_the_name_they_share():
    folder = "@@share\\Music\\Pink Floyd"
    files = (disc_files(f"{folder}\\Wish You Were Here (Experience Edition) CD1", EXPERIENCE_TRACKS[:5])
             + disc_files(f"{folder}\\Wish You Were Here (Experience Edition) CD2", EXPERIENCE_TRACKS[5:]))
    ranked = rank_candidates([make_response("glassbeads", files)], EXPERIENCE)

    assert len(ranked) == 1
    assert ranked[0]["directory_name"] == "Wish You Were Here (Experience Edition)"
    assert ranked[0]["matched_tracks"] == 11


def test_disc_folders_are_joined_only_when_it_is_certain():
    groups = group_files_by_directory([
        #? two of the same disc: which is the album?
        make_response("a", experience_set(cd1="CD 1", cd2="CD1")),
        #? an album folder with tracks of its own beside its disc folders
        make_response("b", experience_set() + [make_file(f"{SET_FOLDER}\\Bonus.flac")]),
    ])
    joined = join_disc_folders(groups)
    assert all(not c.get("disc_folders") for c in joined)
    assert len(joined) == len(groups)


def test_two_peers_disc_folders_are_never_joined_together():
    responses = [make_response("a", experience_set()[:5]), make_response("b", experience_set()[5:])]
    assert all(not c.get("disc_folders") for c in rank_candidates(responses, EXPERIENCE))


# ---------------------------------------------------------------- a manual search (2.1.37)
#
# The iPhone and Mac app's Search Soulseek: an artist and an album as typed, no release behind them - no
# tracklist, no year. Ranked by `name_match`, how closely the folder's name is the typed album and its path
# the typed artist, 0.80 of the score, with the usual edition, format and availability blend as the rest.
# The folders are invented, as everything in this file is.

from src.matching import FORMAT_WORDS, MANUAL_NAME_WEIGHT, name_match  # noqa: E402

MANUAL = {"artist": "Radiohead", "album": "OK Computer", "year": None, "tracks": [], "edition_tags": [],
          "manual": True}


def folder_files(directory, count=3, extension="flac"):
    return [make_file(f"{directory}\\{n:02d} Track {n}.{extension}") for n in range(1, count + 1)]


def fit(path, artist="Radiohead", album="OK Computer", files=None):
    """name_match of a Soulseek path, as group_files_by_directory hands it on ("/" between folders)."""
    directory = path.replace("\\", "/")
    return name_match(directory, folder_files(path) if files is None else files, artist, album)


def manual_ranked(*responses, expected=None, **kwargs):
    return rank_candidates(list(responses), expected or MANUAL, **kwargs)


def test_an_exact_folder_ranks_above_one_with_extra_words():
    exact = make_response("alice", folder_files(r"@@a\Music\Radiohead\OK Computer"))
    extra = make_response("bob", folder_files(r"@@b\Music\Radiohead\OK Computer OKNOTOK 1997 2017"))
    ranked = manual_ranked(extra, exact)
    assert [c["username"] for c in ranked] == ["alice", "bob"]
    assert ranked[0]["signals"]["name_match"] == 1.0
    #? two of three words: the album fit is 0.67, the artist is in the path
    assert ranked[1]["signals"]["name_match"] == round(0.65 * 2 / 3 + 0.35, 3)


def test_format_words_years_and_disc_markers_cost_nothing():
    for path in (r"@@a\Radiohead - 1997 - OK Computer [FLAC 24-96]", r"@@a\Radiohead\OK Computer (1997)",
                 r"@@a\Radiohead\OK Computer CD1", r"@@a\Radiohead\OK Computer WEB", r"@@a\Radiohead\OK Computer 24bit 96khz",
                 r"@@a\Radiohead\OK Computer [320kbps MP3]", r"@@a\Radiohead\OK Computer (Disc One)"):
        assert fit(path) == 1.0, path


def test_a_disc_folder_is_read_with_its_album():
    assert fit(r"@@a\Radiohead\OK Computer\CD 1") == 1.0
    assert fit(r"@@a\Radiohead\OK Computer\Disc 2") == 1.0


def test_a_folder_named_only_by_its_format_reads_the_folder_above():
    assert fit(r"@@a\Radiohead\OK Computer\FLAC") == 1.0
    assert fit(r"@@a\Radiohead\OK Computer\FLAC 24bit") == 1.0
    #? once: a format folder above a format folder is not read through to the album
    assert fit(r"@@a\Radiohead\OK Computer\FLAC\MP3") < 1.0


def test_a_self_titled_album_keeps_its_word():
    assert fit(r"@@a\Music\Weezer - Weezer (1994)", artist="Weezer", album="Weezer") == 1.0
    assert fit(r"@@a\Music\Weezer\Weezer", artist="Weezer", album="Weezer") == 1.0


@pytest.mark.parametrize("artist, album, right, wrong", [
    #? (review) the artist's word is the album's too, so an "Artist - Other Album" folder kept it and
    #? outranked the album itself
    ("Weezer", "Weezer", r"@@b\Weezer\Weezer (Blue Album) [FLAC]", r"@@a\Music\Weezer - Pinkerton"),
    ("Weezer", "Weezer", r"@@b\Weezer\Weezer - 1994 - Weezer (Blue Album)", r"@@a\Weezer\Weezer - 1996 - Pinkerton"),
    ("Weezer", "Weezer", r"@@b\Music\Weezer - Weezer", r"@@a\Music\Weezer - Pinkerton (Deluxe Edition)"),
    ("Peter Gabriel", "Peter Gabriel", r"@@b\Music\Peter Gabriel 3 (Melt)", r"@@a\Music\Peter Gabriel - So (1986)"),
    ("Peter Gabriel", "Peter Gabriel", r"@@b\Music\Peter Gabriel - Peter Gabriel 3 (Melt)",
     r"@@a\Peter Gabriel\Peter Gabriel - So (1986)"),
])
def test_a_self_titled_search_ranks_the_album_above_the_artists_others(artist, album, right, wrong):
    expected = {**MANUAL, "artist": artist, "album": album}
    ranked = manual_ranked(make_response("wrong", folder_files(wrong)), make_response("right", folder_files(right)),
                           expected=expected)
    assert [c["username"] for c in ranked] == ["right", "wrong"]
    assert ranked[0]["score"] > ranked[1]["score"], "outranked, not tied"


def test_the_artist_before_a_dash_is_taken_out_once():
    #? the prefix stops counting, the album's own word still does - and a name that is only the artist and
    #? noise after it is still the album
    assert fit(r"@@a\Music\Weezer - Weezer (1994)", artist="Weezer", album="Weezer") == 1.0
    assert fit(r"@@a\Music\Weezer - 1994 [FLAC]", artist="Weezer", album="Weezer") == 1.0
    assert fit(r"@@a\Music\Weezer - Pinkerton", artist="Weezer", album="Weezer") == 0.35
    assert fit(r"@@a\Music\The Beatles - The Beatles (White Album)", artist="The Beatles",
               album="The Beatles") == pytest.approx(0.65 / 3 + 0.35)
    #? a hyphen inside a name is not a dash between artist and album
    assert fit(r"@@a\Music\Jay-Z\Jay-Z [2003]", artist="Jay-Z", album="Jay-Z") == 1.0


def test_an_artist_found_only_in_the_file_names_counts():
    named = [make_file(rf"@@a\Music\OK Computer\{n:02d} Radiohead - Track {n}.flac") for n in range(1, 5)]
    assert fit(r"@@a\Music\OK Computer", files=named) == 1.0
    #? in fewer than half the names, it doesn't
    unnamed = named[:1] + folder_files(r"@@a\Music\OK Computer", count=3)
    assert fit(r"@@a\Music\OK Computer", files=unnamed) == 0.65
    assert fit(r"@@a\Music\OK Computer", files=[]) == 0.65


def test_the_beatles_fits_beatles_abbey_road():
    assert fit(r"@@a\Music\Beatles - Abbey Road", artist="The Beatles", album="Abbey Road") == 1.0
    #? "&" and "and" are one word as far as fit goes
    assert fit(r"@@a\Music\Simon and Garfunkel - Bookends", artist="Simon & Garfunkel", album="Bookends") == 1.0


def test_edition_words_are_the_edition_signals_alone():
    for path in (r"@@a\Radiohead\OK Computer (Deluxe Edition)", r"@@a\Radiohead\OK Computer [Super Deluxe]",
                 r"@@a\Radiohead\OK Computer - Remastered", r"@@a\Radiohead\OK Computer (Instrumental)"):
        assert fit(path) == 1.0, path
    #? typed with its edition, the album's words are the rest - and the edition signal asks for it
    assert fit(r"@@a\Radiohead\OK Computer", album="OK Computer (Deluxe Edition)") == 1.0


def test_an_album_named_only_by_noise_or_an_edition_word_still_fits():
    assert fit(r"@@a\Music\Taylor Swift\1989 (2014)", artist="Taylor Swift", album="1989") == 1.0
    assert fit(r"@@a\Music\Taylor Swift\1989 (2014)", artist="Taylor Swift", album="1988") < 0.5
    assert fit(r"@@a\Music\The The - Soul Mining", artist="The The", album="Soul Mining") == 1.0
    assert fit(r"@@a\Music\Harmonia - Deluxe (1975)", artist="Harmonia", album="Deluxe") == 1.0


def test_a_different_album_by_the_artist_fits_only_by_its_artist():
    assert fit(r"@@a\Radiohead\The Bends") == 0.35
    assert fit(r"@@a\Other\Kid A") == 0.0


def test_the_worked_examples():
    """The plan's table, with prefer_lossless: fit first, then edition, format and availability."""
    def score(path, **response):
        return manual_ranked(make_response("p", folder_files(path, extension=response.pop("extension", "flac")),
                                           **response))[0]["score"]

    slow = {"free_slot": False, "queue": 40, "speed": 1_000}
    assert round(score(r"@@a\Radiohead\OK Computer", extension="mp3", **slow), 2) == 0.92
    assert round(score(r"@@a\Radiohead\OK Computer OKNOTOK"), 2) == 0.83
    assert score(r"@@a\Radiohead\OK Computer") == 1.0
    assert round(score(r"@@a\Radiohead\OK Computer (Instrumental)"), 2) == 0.95


def test_a_perfect_fit_mp3_from_a_slow_peer_ranks_above_a_poorer_fit_flac_from_a_fast_one():
    mp3 = make_response("slow", folder_files(r"@@a\Radiohead\OK Computer", extension="mp3"),
                        free_slot=False, queue=40, speed=1_000)
    flac = make_response("fast", folder_files(r"@@b\Radiohead\OK Computer OKNOTOK"), speed=5_000_000)
    assert [c["username"] for c in manual_ranked(flac, mp3)] == ["slow", "fast"]


def test_between_two_perfect_fits_flac_comes_first_then_the_free_slot():
    flac = make_response("flac", folder_files(r"@@a\Radiohead\OK Computer"))
    mp3 = make_response("mp3", folder_files(r"@@b\Radiohead\OK Computer", extension="mp3"))
    assert [c["username"] for c in manual_ranked(mp3, flac)] == ["flac", "mp3"]
    free = make_response("free", folder_files(r"@@c\Radiohead\OK Computer"))
    queued = make_response("queued", folder_files(r"@@d\Radiohead\OK Computer"), free_slot=False, queue=40)
    assert [c["username"] for c in manual_ranked(queued, free)] == ["free", "queued"]


def test_the_score_and_the_fit_stay_between_0_and_1_whatever_the_folder():
    for directory, files in (("", []), ("@@a/Radiohead/OK Computer", []), ("!!! ??? ...", []),
                             ("@@a/---/[]", [{"filename": "@@a/---/[]/().flac"}])):
        value = name_match(directory, files, "Radiohead", "OK Computer")
        assert 0.0 <= value <= 1.0
    for artist, album in (("", ""), ("!!!", "???"), ("Radiohead", ""), ("", "OK Computer")):
        assert 0.0 <= name_match("@@a/Radiohead/OK Computer", [], artist, album) <= 1.0
    many = [make_response(f"peer{n}", folder_files(rf"@@{n}\Folder {n} {'OK Computer' if n % 3 else 'Other'}"),
                          free_slot=bool(n % 2), queue=n, speed=n * 1000) for n in range(300)]
    many.append(make_response("empty", []))
    ranked = manual_ranked(*many, limit=500)
    assert len(ranked) == 300
    for candidate in ranked:
        assert 0.0 <= candidate["score"] <= 1.0 and 0.0 <= candidate["signals"]["name_match"] <= 1.0
    assert len(manual_ranked(*many)) == 50, "the limit is still 50"


def test_a_manual_question_with_nothing_to_go_on_scores_its_rest_and_nothing_else():
    candidate = group_files_by_directory([make_response("a", folder_files(r"@@a\x"))])[0]
    scored = score_candidate(candidate, {**MANUAL, "artist": "", "album": ""})
    assert scored["signals"]["name_match"] == 0.0
    assert scored["score"] == round((1 - MANUAL_NAME_WEIGHT) * 1.0, 4)


def test_lossless_only_still_drops_lossy_folders_from_a_manual_search():
    mp3 = make_response("mp3", folder_files(r"@@a\Radiohead\OK Computer", extension="mp3"))
    flac = make_response("flac", folder_files(r"@@b\Radiohead\OK Computer OKNOTOK"))
    ranked = manual_ranked(mp3, flac, format_preference="lossless_only")
    assert [c["username"] for c in ranked] == ["flac"]


def test_the_folder_name_is_the_first_reason_a_manual_card_gives():
    ranked = manual_ranked(make_response("a", folder_files(r"@@a\Radiohead\OK Computer")))
    assert list(ranked[0]["signals"]) == ["name_match", "title_match", "track_count", "duration_match",
                                          "edition", "format", "peer"]
    assert ranked[0]["signals"]["title_match"] is None and ranked[0]["matched_tracks"] == 0


def test_format_words_are_the_plans():
    assert FORMAT_WORDS >= {"flac", "mp3", "web", "cd", "vinyl", "lossless", "hires", "mqa", "v0", "v2", "lp"}


#? scores and signals computed from matching.py as it was at 2.1.35, before the manual search existed
GOLDEN_RESPONSES = (
    ("alice", r"share\Boards of Canada\Music Has the Right to Children (1998) [FLAC]", "flac", {}),
    ("bob", r"share\MHTRTC", "mp3", {"free_slot": False, "queue": 40, "speed": 50_000}),
    ("carol", r"share\BoC - MHTRTC (Deluxe Edition)", "flac", {"queue": 3, "speed": 500_000}),
)
GOLDEN_FULL = [("alice", 1.0, (1.0, 1.0, 1.0, 1.0, 1.0, 1.0)), ("carol", 0.89, (1.0, 1.0, 1.0, 0.4, 1.0, 0.75)),
               ("bob", 0.854, (1.0, 1.0, 1.0, 1.0, 0.45, 0.0))]
GOLDEN_TRACKLESS = [("alice", 1.0, (None, None, None, 1.0, 1.0, 1.0)),
                    ("carol", 0.6857, (None, None, None, 0.4, 1.0, 0.75)),
                    ("bob", 0.5829, (None, None, None, 1.0, 0.45, 0.0))]


def test_a_question_without_manual_scores_exactly_as_before():
    responses = [make_response(user, album_files(path, extension=extension), **peer)
                 for user, path, extension, peer in GOLDEN_RESPONSES]
    order = ("title_match", "track_count", "duration_match", "edition", "format", "peer")
    for expected, golden in ((EXPECTED_BASE, GOLDEN_FULL), ({**EXPECTED_BASE, "tracks": []}, GOLDEN_TRACKLESS)):
        for question in (expected, {**expected, "manual": False}):
            ranked = rank_candidates(responses, question)
            assert [(c["username"], c["score"], tuple(c["signals"][k] for k in order)) for c in ranked] == golden
            assert all(list(c["signals"]) == list(order) for c in ranked), "no name_match key"
