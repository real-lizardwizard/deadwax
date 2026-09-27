"""
Tests for the candidate scoring engine.

These matter more than usual: slskd lives on the user's home server, so this logic can't be
exercised end to end from a dev machine. Fixtures below are shaped exactly like slskd's
`search_responses()` output (see slskd_api.apis._types.SearchResponseItem / SearchFile).

Run with:  .venv/bin/python -m pytest tests/ -q
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.matching import (  # noqa: E402
    detect_edition_tags,
    group_files_by_directory,
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
    offering; EDITION_KEYWORDS in interface/scripts/main.js tags the RELEASE you picked, and
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
