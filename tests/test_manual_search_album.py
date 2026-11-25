"""
The Done row's album (2.1.40, manual search's S3): how the native app gets from a manual search's finished
download to the album it was filed as - a manual download is filed by its own tags, usually with NO release
id, so the id bridge can't find it by release.

  - The poller records `jobs.album_id` for every MANUAL filing (store.set_job_album), before the grant and
    whatever it gives: with logins off a flagged filing, or a break-glass request, grants nothing and so
    writes nothing. Any other job's album_id is still written by its grant alone.
  - /jobs gives a manual row `filed_as` - the artist and album of the store row its album_id leads to, merges
    followed, in ONE index_follow for every such row - only for a live row; a failed read says nothing.
  - The id bridge takes `job_id`: the asker's job, or anyone's with Everyone's downloads (404 otherwise); no
    album or no live row is `present: []`; a row matched since is answered exactly as its release is; else
    the row, and Navidrome's ONE album of that name by that artist with no release id of its own.

Through the whole app start() builds (no lifespan), a real SQLite store, real folders, and step 5's fake
Navidrome (tests/test_personal_libraries.py) checking token auth - james the admin, ethan and sam users -
wired as the player's client too, so the bridge's search3 is seen asked as whoever asked. Navidrome's answer
for an album with no release id is shaped from its source (musicBrainzId empty or left out), not recorded.
"""

from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from src import poller
from src.api.navidrome_endpoint import navidrome
from src.config import Config
from src.poller import poll_downloads_once
from src.users import LOCAL_USER
from tests import test_personal_libraries
from tests.test_library import write_flac
from tests.test_personal_libraries import (FILED_RELEASE, FILES, FOLDER, NAVIDROME, Slskd, failed, grant, held, ok,
                                           run, signed_in)

on = test_personal_libraries.on

BRIDGE = "/deadwax/store/album"
JOBS = "/deadwax/download/jobs"
OK_COMPUTER = "Radiohead/OK Computer (1997)"
MATCHED = "0b6b4ba0-d36f-47bd-b4ea-6a5b91842d29"   # a release id applied to it since
#? what was TYPED to find it - lowercase, unlike the tags it was filed by
TYPED = {"artist": "radiohead", "album_artist": "radiohead", "album": "ok computer", "year": None,
         "release_mbid": None, "tracks": [], "manual": True}
EMPTY = {"release_mbid": None, "release_group_mbid": None, "navidrome_id": None, "present": [], "other_pressings": []}


@pytest.fixture
def bridge(on):
    """
    Step 5's `on`, its Navidrome the player's too - so the bridge's lookups reach it, as the asker. Its search3
    as Navidrome's is read to search (from its source, not a real server): every word of the query in an
    album's full text - its name and its artist - or the query its release id; at most `albumCount` albums, in
    the order the library holds them.
    """
    def handle(request: httpx.Request) -> httpx.Response:
        answer = on.fake.handle(request)
        if request.url.path.rsplit("/", 1)[-1] != "search3" or answer.json()["subsonic-response"]["status"] != "ok":
            return answer
        q = {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query).items()}
        asked = q.get("query", "")
        words = asked.lower().split()
        found = [album for album in on.fake.albums.values()
                 if (on.fake.mbid_search and asked and album.get("musicBrainzId") == asked)
                 or (words and all(word in f"{album['name']} {album.get('artist', '')}".lower() for word in words))]
        return httpx.Response(200, json=ok(searchResult3={"album": found[:int(q.get("albumCount", 20))]}))

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url=f"{NAVIDROME}/rest")
    yield on
    run(navidrome.close_client())


def row(on, path=OK_COMPUTER, artist="Radiohead", album="OK Computer", release=None, year="1997", tracks=12) -> int:
    """An album folder on disk and its store row - a manual search's, by default (no release id)."""
    (on.tmp / "library" / path).mkdir(parents=True, exist_ok=True)
    return run(on.store.index_upsert(on.root, {
        "path": path, "release_mbid": release, "release_group_mbid": None, "artist": artist, "album": album,
        "year": year, "edition": "", "track_count": tracks, "formats": ["flac"],
    }))


def manual_job(on, user="ethan", album_id=None, release=None) -> int:
    """A manual search's finished download asked for by `user`, filed as `album_id` (None: not yet)."""
    job_id = run(on.store.create_job("bob", "share/album", FILES, release or TYPED, user=user))
    run(on.store.update_status(job_id, "organized"))
    if album_id is not None:
        run(on.store.set_job_album(job_id, album_id))
    return job_id


def in_navidrome(on, album_id, name="OK Computer", artist="Radiohead", release="", year=None, songs=None) -> None:
    """An album Navidrome lists; `release` '' is one it holds no release id for (its answer's musicBrainzId empty).
    `year` and `songs` are its answer's `year` and `songCount`, left out when None."""
    on.fake.albums[album_id] = {"id": album_id, "name": name, "artist": artist, "musicBrainzId": release,
                                **({"year": year} if year is not None else {}),
                                **({"songCount": songs} if songs is not None else {})}


def searched(on) -> list[tuple[str, str]]:
    return [(user, q.get("query")) for user, q in on.fake.asked("search3")]


# ----------------------------------------------------------------- whose job

def test_the_askers_own_job_is_answered_with_its_album(bridge):
    album = row(bridge)
    in_navidrome(bridge, "nd-ok")
    job_id = manual_job(bridge, "ethan", album)
    ethan = signed_in(bridge, "ethan")

    answer = ethan.get(BRIDGE, params={"job_id": job_id})

    assert answer.status_code == 200, answer.text
    body = answer.json()
    assert (body["release_mbid"], body["release_group_mbid"], body["navidrome_id"], body["other_pressings"]) == (
        None, None, "nd-ok", [])
    [present] = body["present"]
    assert (present["id"], present["path"], present["artist"], present["album"], present["release_mbid"]) == (
        album, OK_COMPUTER, "Radiohead", "OK Computer", None)
    assert body["yours"] is False
    #? asked as ethan, on the title the store row has - never the typed words
    assert searched(bridge) == [("ethan", "OK Computer")]
    grant(bridge, ["ethan"], album)
    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["yours"] is True


def test_somebody_elses_job_is_a_404_with_logins_on(bridge):
    job_id = manual_job(bridge, "ethan", row(bridge))
    in_navidrome(bridge, "nd-ok")
    sam = signed_in(bridge, "sam")

    for asked in (job_id, job_id + 100):
        answer = sam.get(BRIDGE, params={"job_id": asked})
        assert answer.status_code == 404, asked
        assert answer.json()["detail"] == "No such download job"
    assert searched(bridge) == [], "nothing was asked of Navidrome for it"


def test_an_admin_sees_anyones_job(bridge):
    album = row(bridge)
    in_navidrome(bridge, "nd-ok")
    job_id = manual_job(bridge, "ethan", album)
    james = signed_in(bridge, "james")

    answer = james.get(BRIDGE, params={"job_id": job_id})

    assert answer.status_code == 200, answer.text
    assert [p["id"] for p in answer.json()["present"]] == [album]
    assert answer.json()["navidrome_id"] == "nd-ok"


# ----------------------------------------------------------------- what the job leads to

def test_a_job_with_no_album_is_answered_empty_never_guessed_by_its_words(bridge):
    #? an album of exactly the typed words is in the store and in Navidrome - and still nothing is said
    row(bridge, artist="radiohead", album="ok computer")
    in_navidrome(bridge, "nd-ok", name="ok computer", artist="radiohead")
    job_id = manual_job(bridge, "ethan")
    ethan = signed_in(bridge, "ethan")

    answer = ethan.get(BRIDGE, params={"job_id": job_id})

    assert answer.status_code == 200 and answer.json() == EMPTY
    assert searched(bridge) == []


@pytest.mark.parametrize("gone", ["missing", "deleted", "on disk"])
def test_a_row_no_longer_live_is_answered_empty(bridge, gone):
    album = row(bridge)
    in_navidrome(bridge, "nd-ok")
    job_id = manual_job(bridge, "ethan", album)
    if gone == "on disk":
        #? the folder went since the index saw it: marked missing as the release path marks one
        (bridge.tmp / "library" / OK_COMPUTER).rmdir()
    else:
        run(bridge.store.index_gone(bridge.root, OK_COMPUTER, gone))
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json() == EMPTY
    assert run(bridge.store.index_follow([album]))[album]["state"] == ("missing" if gone == "on disk" else gone)


def test_a_row_matched_since_is_answered_exactly_as_its_release_is(bridge):
    album = row(bridge, release=MATCHED)
    in_navidrome(bridge, "nd-matched", release=MATCHED)
    #? an id-less album of the same name and artist, which the by-name lookup would have opened
    in_navidrome(bridge, "nd-idless")
    job_id = manual_job(bridge, "ethan", album)
    ethan = signed_in(bridge, "ethan")

    by_job = ethan.get(BRIDGE, params={"job_id": job_id}).json()
    by_release = ethan.get(BRIDGE, params={"release_mbid": MATCHED}).json()

    assert by_job == by_release
    assert (by_job["release_mbid"], by_job["navidrome_id"]) == (MATCHED, "nd-matched")
    assert [p["id"] for p in by_job["present"]] == [album]


def test_a_disc_folder_merged_since_is_followed_to_the_one_it_joined(bridge):
    kept = row(bridge, path="Radiohead/OK Computer (1997)/Disc 1")
    merged = row(bridge, path="Radiohead/OK Computer (1997)/Disc 2")
    run(bridge.store.index_merge(bridge.root, "Radiohead/OK Computer (1997)/Disc 2", "Radiohead/OK Computer (1997)/Disc 1"))
    in_navidrome(bridge, "nd-ok")
    job_id = manual_job(bridge, "ethan", merged)
    ethan = signed_in(bridge, "ethan")

    assert [p["id"] for p in ethan.get(BRIDGE, params={"job_id": job_id}).json()["present"]] == [kept]


# ----------------------------------------------------------------- Navidrome's album, by name

@pytest.mark.parametrize("albums, expected", [
    #? one id-less album of that name by that artist - its spelling folded as navidrome_listing folds it
    ([("nd-ok", "OK Computer", "Radiohead", "")], "nd-ok"),
    ([("nd-ok", "ok  computer", "RADIOHEAD", "")], "nd-ok"),
    #? beside a matched pressing of the same name, which is never this folder
    ([("nd-ok", "OK Computer", "Radiohead", ""), ("nd-cd", "OK Computer", "Radiohead", MATCHED)], "nd-ok"),
    #? two id-less albums of that name by that artist: which is which can't be told
    ([("nd-ok", "OK Computer", "Radiohead", ""), ("nd-ok-2", "OK Computer", "Radiohead", "")], None),
    #? only an album of that name WITH a release id
    ([("nd-cd", "OK Computer", "Radiohead", MATCHED)], None),
    #? only another artist's album of that name
    ([("nd-other", "OK Computer", "Easy Star All-Stars", "")], None),
    #? only another album the words find
    ([("nd-oknotok", "OK Computer OKNOTOK 1997 2017", "Radiohead", "")], None),
])
def test_navidromes_album_is_the_one_id_less_album_of_that_name_by_that_artist(bridge, albums, expected):
    job_id = manual_job(bridge, "ethan", row(bridge))
    for album_id, name, artist, release in albums:
        in_navidrome(bridge, album_id, name=name, artist=artist, release=release)
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] == expected


def test_an_album_whose_answer_leaves_its_release_id_out_is_id_less(bridge):
    job_id = manual_job(bridge, "ethan", row(bridge))
    bridge.fake.mbid_search = False   # the fake compares musicBrainzId only when it searches ids
    bridge.fake.albums["nd-ok"] = {"id": "nd-ok", "name": "OK Computer", "artist": "Radiohead"}
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] == "nd-ok"


def test_an_artist_navidrome_credits_among_others_counts(bridge):
    job_id = manual_job(bridge, "ethan", row(bridge, artist="Massive Attack", album="Protection"))
    bridge.fake.albums["nd-p"] = {"id": "nd-p", "name": "Protection", "artist": "Massive Attack & Tracey Thorn",
                                  "musicBrainzId": "", "artists": [{"name": "Massive Attack"}, {"name": "Tracey Thorn"}]}
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] == "nd-p"


def test_another_folders_id_less_copy_is_not_taken_for_one_navidrome_hasnt_listed(bridge):
    """The review's case: an older id-less copy of the album in its own folder, which Navidrome lists; the manual
    download filed beside it, not scanned yet. Title and artist alone opened the OTHER folder's album."""
    row(bridge, path="Radiohead/OK Computer (2009)", year="2009", tracks=10)
    in_navidrome(bridge, "nd-old", year=2009, songs=10)
    new = row(bridge, path="Radiohead/OK Computer (1997)", year="1997", tracks=12)
    job_id = manual_job(bridge, "ethan", new)
    ethan = signed_in(bridge, "ethan")

    body = ethan.get(BRIDGE, params={"job_id": job_id}).json()
    assert [p["id"] for p in body["present"]] == [new] and body["navidrome_id"] is None

    #? scanned: its own album, the older copy's still refused
    in_navidrome(bridge, "nd-new", year=1997, songs=12)
    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] == "nd-new"


@pytest.mark.parametrize("year, songs, why", [
    (1998, 12, "another year"),
    (1997, 11, "another count of songs"),
    (1997, 6, "Navidrome still scanning it"),
    (1997, 24, "two id-less copies Navidrome made one album of"),
])
def test_an_album_whose_year_or_song_count_isnt_the_folders_is_not_it(bridge, year, songs, why):
    job_id = manual_job(bridge, "ethan", row(bridge, year="1997", tracks=12))
    in_navidrome(bridge, "nd-ok", year=year, songs=songs)
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] is None, why


@pytest.mark.parametrize("row_year, row_tracks, year, songs", [
    ("1997", 12, 1997, 12),        # both sides say both, and agree
    ("1997", 12, "1997", 12),      # a year answered as a string
    ("1997", 12, None, 12),        # Navidrome says no year
    ("1997", 12, 0, 12),           # ...or 0, which is none
    ("1997", 12, 1997, None),      # Navidrome says no song count
    ("", 12, 2001, 12),            # the folder's files have no date
    ("1997", 0, 1997, 30),         # the row has no track count
])
def test_a_year_or_song_count_only_one_side_says_doesnt_count_against_it(bridge, row_year, row_tracks, year, songs):
    job_id = manual_job(bridge, "ethan", row(bridge, year=row_year, tracks=row_tracks))
    in_navidrome(bridge, "nd-ok", year=year, songs=songs)
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] == "nd-ok"


def test_a_common_title_past_the_first_answers_is_found_by_artist_and_title(bridge):
    for n in range(25):
        in_navidrome(bridge, f"nd-gh-{n}", name="Greatest Hits", artist=f"Someone {n}")
    in_navidrome(bridge, "nd-gh", name="Greatest Hits", artist="Radiohead")
    job_id = manual_job(bridge, "ethan", row(bridge, path="Radiohead/Greatest Hits (1997)", album="Greatest Hits"))
    ethan = signed_in(bridge, "ethan")

    assert ethan.get(BRIDGE, params={"job_id": job_id}).json()["navidrome_id"] == "nd-gh"
    assert searched(bridge) == [("ethan", "Greatest Hits"), ("ethan", "Radiohead Greatest Hits")]


def test_navidrome_down_is_no_id_and_the_store_still_answered(bridge):
    album = row(bridge)
    job_id = manual_job(bridge, "ethan", album)
    ethan = signed_in(bridge, "ethan")
    bridge.fake.errors[("ethan", "search3")] = httpx.Response(200, json=failed(0, "something broke"))

    body = ethan.get(BRIDGE, params={"job_id": job_id}).json()

    assert body["navidrome_id"] is None and [p["id"] for p in body["present"]] == [album]


def test_a_refused_login_is_a_401_never_no_album(bridge):
    job_id = manual_job(bridge, "ethan", row(bridge))
    ethan = signed_in(bridge, "ethan")
    bridge.fake.errors[("ethan", "search3")] = httpx.Response(200, json=failed(40, "Wrong username or password"))

    assert ethan.get(BRIDGE, params={"job_id": job_id}).status_code == 401


# ----------------------------------------------------------------- exactly one key

@pytest.mark.parametrize("params", [
    {"job_id": 1, "release_mbid": MATCHED},
    {"job_id": 1, "navidrome_id": "nd-ok"},
    {"job_id": 1, "release_mbid": MATCHED, "navidrome_id": "nd-ok"},
    {},
    {"job_id": 0},
    {"job_id": -3},
    {"job_id": "one"},
])
def test_exactly_one_key_or_a_422_with_nothing_asked(bridge, params):
    manual_job(bridge, "ethan", row(bridge))
    ethan = signed_in(bridge, "ethan")
    before = len(bridge.fake.calls)

    assert ethan.get(BRIDGE, params=params).status_code == 422
    assert bridge.fake.calls[before:] == []


# ----------------------------------------------------------------- /jobs' filed_as

def jobs_off(on, monkeypatch) -> dict[int, dict]:
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    answer = TestClient(on.app).get(JOBS)
    assert answer.status_code == 200, answer.text
    return {job["id"]: job for job in answer.json()["jobs"]}


def test_a_manual_row_says_what_it_was_filed_as_from_its_store_row(on, monkeypatch):
    album = row(on)
    manual = manual_job(on, LOCAL_USER, album)
    unfiled = manual_job(on, LOCAL_USER)
    #? any other download with an album id (its grant's) says nothing of the kind
    other = manual_job(on, LOCAL_USER, album, release={"artist": "Radiohead", "album": "OK Computer"})

    rows = jobs_off(on, monkeypatch)

    #? the tags' spelling, not the typed words
    assert rows[manual]["filed_as"] == {"artist": "Radiohead", "album": "OK Computer"}
    assert rows[manual]["manual"] is True
    assert "filed_as" not in rows[unfiled] and "filed_as" not in rows[other]


def test_filed_as_follows_a_merge_and_says_nothing_of_a_row_not_live(on, monkeypatch):
    kept = row(on, path="Radiohead/OK Computer (1997)/Disc 1", album="OK Computer")
    merged = row(on, path="Radiohead/OK Computer (1997)/Disc 2", album="OK Computer (Disc 2)")
    run(on.store.index_merge(on.root, "Radiohead/OK Computer (1997)/Disc 2", "Radiohead/OK Computer (1997)/Disc 1"))
    missing = row(on, path="Radiohead/Kid A (2000)", album="Kid A")
    run(on.store.index_gone(on.root, "Radiohead/Kid A (2000)", "missing"))
    deleted = row(on, path="Radiohead/Amnesiac (2001)", album="Amnesiac")
    run(on.store.index_gone(on.root, "Radiohead/Amnesiac (2001)", "deleted"))
    jobs = {name: manual_job(on, LOCAL_USER, album)
            for name, album in (("merged", merged), ("missing", missing), ("deleted", deleted), ("none", 9999))}

    rows = jobs_off(on, monkeypatch)

    assert kept != merged
    assert rows[jobs["merged"]]["filed_as"] == {"artist": "Radiohead", "album": "OK Computer"}
    for name in ("missing", "deleted", "none"):
        assert "filed_as" not in rows[jobs[name]], name


def test_one_read_for_every_manual_row_and_none_without_them(on, monkeypatch):
    asked: list[list[int]] = []
    real = on.store.index_follow

    async def counted(ids):
        asked.append(list(ids))
        return await real(ids)

    monkeypatch.setattr(on.store, "index_follow", counted)
    other = manual_job(on, LOCAL_USER, row(on), release={"artist": "Radiohead", "album": "OK Computer"})
    jobs_off(on, monkeypatch)
    assert asked == [], "no manual row with an album: nothing read"

    first = manual_job(on, LOCAL_USER, row(on, path="Radiohead/Kid A (2000)", album="Kid A"))
    second = manual_job(on, LOCAL_USER, row(on, path="Radiohead/Amnesiac (2001)", album="Amnesiac"))
    rows = jobs_off(on, monkeypatch)
    assert len(asked) == 1 and sorted(asked[0]) == sorted(
        run(on.store.get_job(job_id))["album_id"] for job_id in (first, second))
    assert rows[first]["filed_as"]["album"] == "Kid A" and rows[second]["filed_as"]["album"] == "Amnesiac"
    assert "filed_as" not in rows[other]


def test_no_library_path_says_nothing_was_filed_anywhere(on, monkeypatch):
    #? as the id bridge answers nothing without one: no root, no row is this library's
    job_id = manual_job(on, LOCAL_USER, row(on))
    asked: list[list[int]] = []
    real = on.store.index_follow

    async def counted(ids):
        asked.append(list(ids))
        return await real(ids)

    monkeypatch.setattr(on.store, "index_follow", counted)
    monkeypatch.setattr(Config, "LIBRARY_PATH", None)

    rows = jobs_off(on, monkeypatch)
    assert "filed_as" not in rows[job_id] and rows[job_id]["manual"] is True
    assert asked == []


@pytest.mark.parametrize("fault", ["raises", "unread"])
def test_a_store_that_cant_say_leaves_filed_as_out_never_a_500(on, monkeypatch, fault):
    async def broken(ids):
        if fault == "raises":
            raise RuntimeError("disk I/O error")
        return None

    job_id = manual_job(on, LOCAL_USER, row(on))
    monkeypatch.setattr(on.store, "index_follow", broken)

    rows = jobs_off(on, monkeypatch)
    assert "filed_as" not in rows[job_id] and rows[job_id]["manual"] is True


# ----------------------------------------------------------------- the poller writes it

def slskd_folder(on) -> None:
    """A manual search's two files where slskd put them: their titles and numbers, no album or artist."""
    for n in (1, 2):
        write_flac(on.tmp / "downloads" / "album" / f"0{n}.flac", title=f"Track {n}", tracknumber=str(n))


def file_all(on, peer="bob") -> None:
    run(poll_downloads_once(Slskd(peer), on.store, {}))


def test_the_poller_records_a_manual_filings_album_before_the_grant_and_no_other_jobs(on, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    seen: dict[int, int | None] = {}

    async def no_grant(store, job, results, album_id, same_release, path=None):
        #? what the job says as the grant is made: its album already, for a manual one
        seen[job["id"]] = (await store.get_job(job["id"]))["album_id"]
        return None

    monkeypatch.setattr(poller, "grant_job", no_grant)
    slskd_folder(on)
    manual = run(on.store.create_job("bob", "share/album", FILES, TYPED, user=LOCAL_USER))
    file_all(on)
    filed = run(on.store.get_job(manual))
    assert filed["status"] == "organized" and filed["album_id"] is not None
    assert seen[manual] == filed["album_id"]
    there = run(on.store.index_follow([filed["album_id"]]))[filed["album_id"]]
    assert (there["state"], there["album"], there["artist"]) == ("present", "ok computer", "radiohead")

    slskd_folder(on)
    other = run(on.store.create_job("carol", "share/album", FILES, FILED_RELEASE, user=LOCAL_USER))
    file_all(on, "carol")
    filed = run(on.store.get_job(other))
    assert filed["status"] == "organized"
    assert seen[other] is None and filed["album_id"] is None, "only a grant writes any other job's album"


def test_a_manual_download_already_there_records_the_folder_its_grant_writes_nothing_for(on, monkeypatch):
    #? logins off: a manual download whose every track is already in the id-less folder it is filed as is
    #? flagged - and a flag with logins off writes nothing on the job. The bridge needs the album all the same.
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    slskd_folder(on)
    first = run(on.store.create_job("bob", "share/album", FILES, TYPED, user=LOCAL_USER))
    file_all(on)
    album = run(on.store.get_job(first))["album_id"]
    assert album is not None
    slskd_folder(on)
    second = run(on.store.create_job("carol", "share/album", FILES, TYPED, user=LOCAL_USER))

    file_all(on, "carol")

    again = run(on.store.get_job(second))
    assert again["error"].startswith("already in the store"), again["error"]
    assert (again["album_id"], again["library_grant"]) == (album, None)


def test_any_other_download_already_in_an_untagged_folder_still_records_nothing_with_logins_off(on, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    for n in (1, 2):
        write_flac(on.tmp / "downloads" / "album" / f"0{n}.flac", title=f"Track {n}", tracknumber=str(n))
    held(on, FOLDER, tagged=False)
    job_id = run(on.store.create_job("bob", "share/album", FILES, FILED_RELEASE, user=LOCAL_USER))

    file_all(on)

    stored = run(on.store.get_job(job_id))
    assert stored["error"].startswith("already in the store")
    assert (stored["album_id"], stored["library_grant"]) == (None, None)

