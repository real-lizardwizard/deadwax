"""
Which album folders Navidrome lists (2.0.0-player.46) - src/navidrome_listing.py, what raises "Not in
Navidrome" in the review queue.

Two halves, as the module is:

  THE MATCH is pure (build_listing, judge): plain dicts in the shapes getAlbumList2 and library.py
  produce. A folder is listed by its release id, else - untagged, or an id Navidrome's album doesn't
  carry - by its folded title and one of its artists; a folder with no album tag is never judged; a
  negative needs a settled listing and a folder unchanged since Navidrome's last scan (by its mtime, its
  ctime, or deadwax writing it) - or a quarter of an hour since the change with no scan - or the last
  verdict stands.

  THE CACHE (NavidromeListing) asks a fake client - an object with the client's one async `call()` -
  so nothing here needs a Navidrome or a network: getScanStatus first, the album pages until a short
  one, getScanStatus again; measured from when Navidrome's last scan BEGAN (lastScan less
  elapsedTime); one call when Navidrome hasn't scanned since; a read held only for Navidrome's first
  answer or a Rescan's, never past the bound; failures kept as words, never raised (an unreachable
  getScanStatus ending the refresh), and a refresh begun before a forget landing nowhere, answer or
  failure; verdicts merged, pruned only by a real scan, followed through a move; another Navidrome
  forgetting everything. And the scan's half: the write time stamped on the album and saved with the
  scan cache, a folder moved in carrying when it arrived.

The route-level half (the chip in /albums, the count, the ETag) is tests/test_not_in_navidrome.py.
"""

import asyncio
import os
import sys
import time
from dataclasses import replace
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import library  # noqa: E402
from src import navidrome_listing as nl  # noqa: E402
from src.api.navidrome_endpoint import NavidromeError  # noqa: E402
from src.config import Config  # noqa: E402
from src.navidrome_listing import NavidromeListing, build_listing, judge  # noqa: E402

DUMMY_CD = "11111111-1111-4111-8111-111111111111"
DUMMY_DELUXE = "22222222-2222-4222-8222-222222222222"
THIRD = "33333333-3333-4333-8333-333333333333"

#? Navidrome last finished a scan an hour ago, two seconds after it began: folders older than that are
#? what it read
SCANNED = time.time() - 3600
OLD = SCANNED - 86400
LAST_SCAN = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(SCANNED)) + ".123456789Z"
#? Navidrome's elapsedTime is a Go duration: nanoseconds
TOOK = 2_000_000_000


def run(awaitable):
    return asyncio.run(awaitable)


def asked(cache, due_after=0, **more):
    """cache.ask(), and the refresh it began LANDED - a read no longer waits for one (but the first
    answer), and asyncio.run would cancel it on the way out. Returns check() once it has."""
    async def go():
        await cache.ask(due_after, **more)
        task = cache._task
        if task is not None and not task.done():
            await asyncio.wait({task})
        return cache.check()
    return run(go())


def folder(path, album="Dummy", artist="Portishead", release="", modified=OLD, tracks=None, **more):
    """A folder as the scan reports it: its tracks carrying the tags the match reads."""
    if tracks is None:
        tracks = [{"album": album, "albumartist": artist, "artist": artist}]
    return {"path": path, "album": album, "artist": artist, "release_mbid": release,
            "modified_at": modified, "tracks": tracks, **more}


def nav(name, artist="Portishead", release=None, **more):
    """An album as getAlbumList2 lists it."""
    entry = {"id": f"al-{name}-{artist}-{release}", "name": name, "artist": artist, **more}
    if release:
        entry["musicBrainzId"] = release
    return entry


def listing(*albums, seen_until=SCANNED, settled=True, asked_at=SCANNED + 60):
    """Navidrome's albums as a Listing - asked for, by default, a minute after its last scan ended."""
    return build_listing(list(albums), seen_until, settled, asked_at)


# ----- the match -----

def test_a_folder_is_listed_by_its_release_id_whatever_its_name():
    held = listing(nav("Dummy (Remastered)", release=DUMMY_CD.upper()))
    assert judge(folder("Portishead/Dummy (1994)", release=DUMMY_CD), held) is True
    assert judge(folder("Portishead/Third (2008)", album="Third", release=THIRD), held) is False


def test_an_album_with_another_release_id_is_another_pressing_not_this_folder():
    """The deluxe beside the standard: Navidrome has the CD (by its id), the deluxe folder isn't it."""
    held = listing(nav("Dummy", release=DUMMY_CD))
    assert judge(folder("Portishead/Dummy (1994) [Deluxe]", release=DUMMY_DELUXE), held) is False


def test_a_tagged_folder_matches_an_album_navidrome_knows_by_no_id_by_its_name():
    """A Navidrome that didn't read the id (or an older one that never sends it) still lists it."""
    held = listing(nav("Dummy"))
    assert judge(folder("Portishead/Dummy (1994)", release=DUMMY_CD), held) is True


def test_an_untagged_folder_is_matched_by_its_folded_title_and_artist():
    held = listing(nav("Dummy", release=DUMMY_CD), nav("Roseland NYC Live", artist="Portishead"))
    assert judge(folder("Old Rips/dummy", album="DUMMY", artist="portishead"), held) is True, "any pressing of the name"
    assert judge(folder("Old Rips/roseland", album="Roseland NYC Live", artist="Portishead"), held) is True
    assert judge(folder("Old Rips/third", album="Third"), held) is False, "no album of that name"
    assert judge(folder("Old Rips/dummy", album="Dummy", artist="Massive Attack"), held) is False, "another artist's"


def test_folding_takes_away_case_accents_and_typography():
    """One spelling of a name against another (artists._fold) - never fuzzy."""
    held = listing(nav("\u00c1g\u00e6tis byrjun", artist="Sigur R\u00f3s"),
                   nav("Dummy \u2013 Live", artist="Portishead"))
    assert judge(folder("x/y", album="\u00c1G\u00c6TIS BYRJUN", artist="sigur ros"), held) is True
    assert judge(folder("x/y", album="Dummy - Live"), held) is True, "an en dash is a hyphen"
    assert judge(folder("x/y", album="Agaetis Byrjun", artist="Sigur Ros"), held) is False, "ae is not the ash"


def test_every_artist_the_folder_or_the_album_is_credited_to_is_tried():
    held = listing(nav("Blue Lines", artist="Massive Attack", displayArtist="Massive Attack feat. Shara Nelson",
                       artists=[{"id": "a1", "name": "Massive Attack"}, {"id": "a2", "name": "Shara Nelson"}]))
    tracks = [{"album": "Blue Lines", "albumartist": "", "artist": "Shara Nelson"}]
    assert judge(folder("x/y", album="Blue Lines", artist="Unknown", tracks=tracks), held) is True
    #? the display artist alone, no OpenSubsonic `artists`
    shown = listing(nav("Blue Lines", artist="Massive Attack", displayArtist="Shara Nelson"))
    assert judge(folder("x/y", album="Blue Lines", artist="Unknown", tracks=tracks), shown) is True


def test_a_folder_naming_no_artist_is_matched_as_navidromes_unknown_artist():
    """No ARTIST or ALBUMARTIST on any file: the scan names the parent folder, Navidrome "[Unknown Artist]"."""
    held = listing(nav("Mezzanine", artist="[Unknown Artist]", displayArtist="[Unknown Artist]",
                       artists=[{"id": "u", "name": "[Unknown Artist]"}]))
    nameless = folder("Massive Attack/Mezzanine", album="Mezzanine", artist="Massive Attack",
                      tracks=[{"album": "Mezzanine", "albumartist": "", "artist": ""}])
    assert judge(nameless, held) is True
    named = folder("Massive Attack/Mezzanine", album="Mezzanine", artist="Massive Attack")
    assert judge(named, held) is False, "a folder that names its artist is listed under that name, not the placeholder"


def test_a_compilation_is_matched_by_its_title_alone():
    """Navidrome credits Various Artists when there's no album artist; the folder names a track's artist."""
    tracks = [{"album": "Bristol Sound", "albumartist": "", "artist": "Tricky"}]
    rip = folder("Various/Bristol Sound", album="Bristol Sound", artist="Tricky", tracks=tracks)
    assert judge(rip, listing(nav("Bristol Sound", artist="Various Artists"))) is True
    assert judge(rip, listing(nav("Bristol Sound", artist="Someone", isCompilation=True))) is True
    assert judge(rip, listing(nav("Bristol Sound", artist="Someone"))) is False
    tagged = [{"album": "Bristol Sound", "albumartist": "Various Artists", "artist": "Tricky"}]
    assert judge(folder("Various/Bristol Sound", album="Bristol Sound", tracks=tagged),
                 listing(nav("Bristol Sound", artist="Someone", isCompilation=True))) is True, "its album artist IS Various Artists"


def test_a_folder_with_an_album_artist_of_its_own_is_never_somebody_elses_compilation():
    """Navidrome credits the tagged album artist whenever there is one: Queen's Greatest Hits is listed
    under Queen, so a Various Artists "Greatest Hits" says nothing about it."""
    queen = folder("Queen/Greatest Hits", album="Greatest Hits", artist="Queen")
    assert judge(queen, listing(nav("Greatest Hits", artist="Various Artists"))) is False
    assert judge(queen, listing(nav("Greatest Hits", artist="Someone", isCompilation=True))) is False
    assert judge(queen, listing(nav("Greatest Hits", artist="Queen"))) is True
    assert judge({**queen, "release_mbid": THIRD}, listing(nav("Greatest Hits", artist="Various Artists"))) is False, \
        "nor through an id-less compilation"


def test_a_tagged_folder_matches_only_an_id_less_compilation_by_its_title():
    """The deluxe beside the standard, for a Various Artists album too: one with another release's id
    is another pressing."""
    tracks = [{"album": "Bristol Sound", "albumartist": "", "artist": "Tricky"}]
    deluxe = folder("Various/Bristol Sound [Deluxe]", album="Bristol Sound", artist="Tricky", release=DUMMY_DELUXE, tracks=tracks)
    assert judge(deluxe, listing(nav("Bristol Sound", artist="Various Artists", release=DUMMY_CD))) is False
    assert judge(deluxe, listing(nav("Bristol Sound", artist="Various Artists"))) is True


def test_a_folder_named_after_its_folder_is_never_judged():
    """No album tag on any file: Navidrome files it under [Unknown Album], with nothing to match."""
    untitled = folder("Old Rips/Third rip", album="Third rip", tracks=[{"album": "", "artist": "Portishead"}])
    assert judge(untitled, listing(nav("Dummy"))) is None
    assert judge(untitled, listing(nav("Dummy")), last=False) is False, "a verdict it had stands"
    assert judge({**untitled, "release_mbid": DUMMY_CD}, listing(nav("x", release=DUMMY_CD))) is True, "its id still lists it"


def test_a_folder_changed_since_navidromes_last_scan_keeps_the_verdict_it_had():
    """Filed, retagged or given a cover since Navidrome last scanned: it may not have looked yet."""
    held = listing(nav("Dummy", release=DUMMY_CD))
    new = folder("Portishead/Third (2008)", album="Third", release=THIRD, modified=SCANNED + 5)
    assert judge(new, held) is None, "never judged: not raised"
    assert judge(new, held, last=False) is False, "flagged before: still flagged"
    assert judge(new, held, last=True) is True, "listed before (a retag to another id): still listed"
    written = folder("Portishead/Third (2008)", album="Third", release=THIRD)
    assert judge({**written, "written_at": SCANNED + 5}, held) is None, "deadwax wrote it: the folder's mtime didn't move"
    assert judge({**written, "written_at": SCANNED - 5}, held) is False, "written before the scan: Navidrome saw it"
    assert judge(written, held) is False


def test_a_folder_moved_in_with_its_old_mtime_counts_as_changed_when_it_arrived():
    """mv, cp -a, rsync -a and an unzip keep a folder's mtime; its ctime (`changed_at`) is when it came."""
    held = listing(nav("Dummy", release=DUMMY_CD))
    moved_in = folder("Portishead/Third (2008)", album="Third", release=THIRD, modified=OLD, changed_at=SCANNED + 5)
    assert judge(moved_in, held) is None, "Navidrome hasn't scanned since it arrived"
    assert judge({**moved_in, "changed_at": SCANNED - 5}, held) is False, "there before the scan: it saw it"


def test_with_no_scan_since_a_change_is_waited_out_for_a_quarter_of_an_hour_and_no_longer():
    """A folder outside Navidrome's music folder never wakes its watcher, so no scan comes: once the
    change is LISTING_GRACE_SECONDS older than the listing's asking, it is judged anyway - whichever
    way it changed, and whatever it was before."""
    changed = SCANNED + 5
    soon = listing(nav("Dummy", release=DUMMY_CD), asked_at=changed + nl.LISTING_GRACE_SECONDS - 1)
    later = listing(nav("Dummy", release=DUMMY_CD), asked_at=changed + nl.LISTING_GRACE_SECONDS + 1)
    for how in ({"modified_at": changed}, {"changed_at": changed}, {"written_at": changed}):
        third = {**folder("Portishead/Third (2008)", album="Third", release=THIRD), **how}
        assert judge(third, soon) is None, f"{how}: inside the grace"
        assert judge(third, later) is False, f"{how}: past it, with no scan since"
        assert judge(third, later, last=True) is False, f"{how}: past it, whatever it was"
    assert judge(folder("Portishead/Dummy (1994)", release=DUMMY_CD, modified=changed), later) is True


def test_a_listing_navidrome_says_still_holds_is_asked_afresh_for_the_grace(navidrome_set):
    """No scan since: the listing is kept, but as of THIS asking - or a folder filed after it was first
    taken would never be past its grace."""
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    first = cache.listing
    assert first.asked_at == pytest.approx(time.time(), abs=2)
    third = folder("Portishead/Third (2008)", album="Third", release=THIRD, modified=first.asked_at + 5)
    assert cache.unlisted([third]) == set(), "filed after the asking: inside its grace"

    #? as if that asking was sixteen minutes ago, and Third filed just after it
    cache.listing = replace(first, asked_at=first.asked_at - nl.LISTING_GRACE_SECONDS - 60)
    third = {**third, "modified_at": cache.listing.asked_at + 5}
    assert cache.unlisted([third]) == set(), "by the listing as it was asked: inside its grace"
    fake.calls.clear()
    asked(cache)
    assert fake.endpoints() == ["getScanStatus"], "no scan since: kept"
    assert (cache.listing.ids, cache.listing.seen_until) == (first.ids, first.seen_until)
    assert cache.listing.asked_at == pytest.approx(time.time(), abs=2), "...as of now"
    assert cache.unlisted([third]) == {"Portishead/Third (2008)"}, "filed a quarter of an hour ago, no scan since"


def test_a_listing_taken_while_navidrome_scanned_never_says_an_album_isnt_there():
    held = listing(nav("Dummy", release=DUMMY_CD), settled=False)
    assert judge(folder("Portishead/Dummy (1994)", release=DUMMY_CD), held) is True
    assert judge(folder("Portishead/Third (2008)", album="Third", release=THIRD), held) is None
    assert judge(folder("Portishead/Third (2008)", album="Third", release=THIRD), held, last=False) is False


def test_build_listing_reads_what_navidrome_sends_and_skips_what_it_cannot_read():
    held = build_listing([nav("Dummy", release=" " + DUMMY_CD.upper() + " "), "junk", nav("", release=THIRD),
                          {"id": "x", "name": None, "artist": 7}], SCANNED)
    assert held.ids == {DUMMY_CD, THIRD}
    assert held.count == 3
    assert ("dummy", "portishead") in held.names and held.idless_names == frozenset()


# ----- the cache -----

class FakeNavidrome:
    """The client's one call, answering getScanStatus and getAlbumList2 from `state`; every call kept."""

    def __init__(self, albums=(), statuses=None):
        self.albums = list(albums)
        #? scanStatus bodies in turn - the last one again once they run out
        self.statuses = list(statuses or [{"scanning": False, "lastScan": LAST_SCAN, "elapsedTime": TOOK}])
        self.calls: list[tuple[str, dict]] = []
        self.down = False
        self.hold: asyncio.Event | None = None
        #? endpoint -> an exception it raises instead of answering
        self.raises: dict[str, Exception] = {}

    async def call(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        if self.hold is not None:
            await self.hold.wait()
        if endpoint in self.raises:
            raise self.raises[endpoint]
        if self.down:
            raise NavidromeError("Navidrome couldn't be reached at http://navidrome:4533: refused", unreachable=True)
        if endpoint == "getScanStatus":
            status = self.statuses.pop(0) if len(self.statuses) > 1 else self.statuses[0]
            return {"scanStatus": status}
        if endpoint == "getAlbumList2":
            offset, size = params["offset"], params["size"]
            return {"albumList2": {"album": self.albums[offset:offset + size]}}
        raise AssertionError(f"not this one: {endpoint}")

    def endpoints(self):
        return [endpoint for endpoint, _ in self.calls]


@pytest.fixture
def navidrome_set(monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")


@pytest.fixture(autouse=True)
def clean_writes():
    library.clear_scan_cache()
    yield
    library.clear_scan_cache()


def test_unset_asks_nothing_and_says_so(monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "")
    fake = FakeNavidrome([nav("Dummy")])
    cache = NavidromeListing(fake)
    assert run(cache.ask(0)) == {"state": "unset", "problem": None}
    assert fake.calls == []
    assert cache.unlisted([folder("a/b", album="Third")]) == set(), "nothing raised"


def test_a_listing_in_hand_raises_nothing_once_navidrome_is_unset(navidrome_set, monkeypatch):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    third = folder("Portishead/Third (2008)", album="Third", release=THIRD)
    assert cache.unlisted([third]) == {"Portishead/Third (2008)"}
    monkeypatch.setattr(Config, "NAVIDROME_URL", "")
    assert cache.unlisted([third]) == set()


def test_the_scan_status_is_asked_first_then_every_page_then_the_status_again(navidrome_set, monkeypatch):
    monkeypatch.setattr(nl, "LISTING_PAGE", 2)
    fake = FakeNavidrome([nav(f"Album {n}", release=None) for n in range(5)])
    cache = NavidromeListing(fake)
    assert run(cache.ask(0)) == {"state": "listed", "problem": None}
    assert fake.endpoints() == ["getScanStatus", "getAlbumList2", "getAlbumList2", "getAlbumList2", "getScanStatus"]
    assert [params.get("offset") for endpoint, params in fake.calls if endpoint == "getAlbumList2"] == [0, 2, 4]
    assert all(params["type"] == "alphabeticalByName" and params["size"] == 2
               for endpoint, params in fake.calls if endpoint == "getAlbumList2")
    assert cache.listing.count == 5
    assert cache.listing.seen_until == pytest.approx(SCANNED - TOOK / 1e9, abs=1), \
        "measured from when Navidrome's last scan began: lastScan less elapsedTime"


def test_the_numbers_the_docs_give(navidrome_set):
    """500 albums a page (Subsonic's cap), asked again past ten seconds by a read and five minutes by
    the count, the first answer waited for three seconds at most, a change waited out for fifteen
    minutes with no scan - as docs/library.md and troubleshooting.md say."""
    assert (nl.LISTING_PAGE, nl.LISTING_FRESH_SECONDS, nl.LISTING_STALE_SECONDS, nl.LISTING_WAIT_SECONDS,
            nl.LISTING_GRACE_SECONDS) == (500, 10.0, 300.0, 3.0, 900.0)
    fake = FakeNavidrome([nav("Dummy")])
    run(NavidromeListing(fake).ask(0))
    assert [params["size"] for endpoint, params in fake.calls if endpoint == "getAlbumList2"] == [500]


def test_a_server_that_repeats_a_page_or_never_stops_is_not_asked_forever(navidrome_set, monkeypatch):
    monkeypatch.setattr(nl, "LISTING_PAGE", 2)
    monkeypatch.setattr(nl, "LISTING_PAGES_MAX", 4)

    class Repeats(FakeNavidrome):
        async def call(self, endpoint, params=None):
            if endpoint == "getAlbumList2":
                self.calls.append((endpoint, dict(params)))
                return {"albumList2": {"album": self.albums[:2]}}
            return await super().call(endpoint, params)

    fake = Repeats([nav("A"), nav("B"), nav("C")])
    run(NavidromeListing(fake).ask(0))
    assert fake.endpoints().count("getAlbumList2") == 2, "the repeated page ends it"

    class Endless(FakeNavidrome):
        async def call(self, endpoint, params=None):
            if endpoint == "getAlbumList2":
                self.calls.append((endpoint, dict(params)))
                offset = params["offset"]
                return {"albumList2": {"album": [nav(f"A{offset}"), nav(f"B{offset}")]}}
            return await super().call(endpoint, params)

    fake = Endless()
    run(NavidromeListing(fake).ask(0))
    assert fake.endpoints().count("getAlbumList2") == 4, "LISTING_PAGES_MAX"


def test_no_scan_since_costs_one_call_and_keeps_the_listing(navidrome_set):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    first = cache.listing
    fake.calls.clear()
    fake.albums = []
    asked(cache)
    assert fake.endpoints() == ["getScanStatus"], "Navidrome's albums can't have changed"
    assert replace(cache.listing, asked_at=0) == replace(first, asked_at=0), "the same listing, asked afresh"

    fake.calls.clear()
    fake.statuses = [{"scanning": False, "lastScan": "2099-01-01T00:00:00Z"}]
    asked(cache)
    assert fake.endpoints() == ["getScanStatus", "getAlbumList2", "getScanStatus"], "a scan since: listed again"
    assert cache.listing.count == 0


@pytest.mark.parametrize("statuses", [
    [{"scanning": True, "lastScan": LAST_SCAN}, {"scanning": False, "lastScan": LAST_SCAN}],
    [{"scanning": False, "lastScan": LAST_SCAN}, {"scanning": True, "lastScan": LAST_SCAN}],
    [{"scanning": False, "lastScan": LAST_SCAN}, {"scanning": False, "lastScan": "2099-01-01T00:00:00Z"}],
])
def test_a_scan_across_the_asking_leaves_the_listing_unsettled(navidrome_set, statuses):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)], statuses)
    cache = NavidromeListing(fake)
    assert run(cache.ask(0))["state"] == "scanning"
    assert cache.listing.settled is False
    assert cache.unlisted([folder("Portishead/Third (2008)", album="Third", release=THIRD)]) == set()
    fake.calls.clear()
    asked(cache)
    assert "getAlbumList2" in fake.endpoints(), "an unsettled listing is never reused"


def test_an_unsettled_listing_is_listed_again_even_when_navidrome_says_what_it_said_before(navidrome_set):
    """A scan seen running that then failed leaves lastScan where it was: the status matches, the albums may not."""
    statuses = [{"scanning": False, "lastScan": LAST_SCAN}, {"scanning": True, "lastScan": LAST_SCAN},
                {"scanning": False, "lastScan": LAST_SCAN}]
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)], statuses)
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    assert cache.listing.settled is False
    fake.calls.clear()
    asked(cache)
    assert fake.endpoints() == ["getScanStatus", "getAlbumList2", "getScanStatus"]
    assert cache.listing.settled is True


def test_a_server_that_wont_say_when_it_scanned_is_measured_from_now(navidrome_set):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)], [{"scanning": False}])
    cache = NavidromeListing(fake)
    assert run(cache.ask(0))["state"] == "listed"
    assert cache.listing.settled is True
    assert cache.listing.seen_until == pytest.approx(time.time() - nl.LISTING_SETTLE_SECONDS, abs=5)


def test_navidrome_down_raises_nothing_and_says_why(navidrome_set):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    assert cache.unlisted([folder("Portishead/Third (2008)", album="Third", release=THIRD)]) == {"Portishead/Third (2008)"}
    fake.down = True
    fake.calls.clear()
    check = asked(cache)
    assert check == {"state": "failed", "problem": "Navidrome couldn't be reached at http://navidrome:4533: refused"}
    assert fake.endpoints() == ["getScanStatus"], "nothing reached: the album pages aren't asked to time out too"
    assert cache.listing is None
    assert cache.unlisted([folder("Portishead/Third (2008)", album="Third", release=THIRD)]) == set(), \
        "Navidrome down raises nothing - not even what it raised before"


def test_a_slow_navidrome_is_waited_for_a_bounded_while_and_answers_the_next_read(navidrome_set):
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        fake.hold = asyncio.Event()
        cache = NavidromeListing(fake)
        started = time.monotonic()
        check = await cache.ask(0, wait=0.05)
        waited = time.monotonic() - started
        assert check == {"state": "checking", "problem": None}, "until Navidrome has answered, nothing"
        assert waited < 1
        again = await cache.ask(0, wait=0)
        for _ in range(5):
            await asyncio.sleep(0)
        assert len(fake.calls) == 1, "the refresh still out is joined, not asked twice"
        assert again["state"] == "checking"
        fake.hold.set()
        await asyncio.sleep(0.01)
        assert cache.check()["state"] == "listed", "it carried on after the wait, for the next read"
    run(scenario())


def test_due_after_decides_whether_navidrome_is_asked(navidrome_set):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    assert run(cache.ask(None)) == {"state": "checking", "problem": None}
    assert fake.calls == [], "a snapshot never asks"
    run(cache.ask(nl.LISTING_FRESH_SECONDS))
    assert fake.calls, "never answered: asked"
    fake.calls.clear()
    asked(cache, nl.LISTING_FRESH_SECONDS)
    assert fake.calls == [], "answered a moment ago: not asked again"
    cache._answered -= nl.LISTING_FRESH_SECONDS
    asked(cache, nl.LISTING_FRESH_SECONDS)
    assert fake.calls, "older than that: asked"
    fake.calls.clear()
    asked(cache, 0)
    assert fake.calls, "0 always asks (a Rescan)"


def test_forgetting_drops_every_answer_and_a_refresh_begun_before_lands_nowhere(navidrome_set):
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        cache = NavidromeListing(fake)
        await cache.ask(0)
        assert cache.listing is not None
        fake.hold = asyncio.Event()
        await cache.ask(0, wait=0)
        cache.forget()
        assert (cache.listing, cache.problem, cache.check()["state"]) == (None, None, "checking")
        fake.hold.set()
        await asyncio.sleep(0.01)
        assert cache.listing is None, "the old Navidrome's answer, asked before the forget"
    run(scenario())


@pytest.mark.parametrize("failure", [
    NavidromeError("Navidrome didn't answer within 10s", unreachable=True),
    ValueError("odd body"),
], ids=["navidrome-error", "anything-else"])
def test_a_refresh_begun_before_a_forget_that_then_FAILS_lands_nowhere_either(navidrome_set, failure):
    """Navidrome's URL corrected in Settings while the wrong one's refresh waits out its timeout: that
    failure, landing after the forget (and after the new server's answer), mustn't put the old server's
    words over the new one's listing, nor take its chips away."""
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        cache = NavidromeListing(fake)
        wrong = fake.hold = asyncio.Event()
        await cache.ask(0, wait=0)  #? the wrong server's refresh, waiting out its timeout
        old = cache._task
        for _ in range(3):
            await asyncio.sleep(0)
        assert fake.endpoints() == ["getScanStatus"], "its call is out"
        cache.forget()
        fake.hold = None
        await cache.ask(0, wait=0)  #? the right one's, answered at once
        await asyncio.wait({cache._task})
        listed = cache.listing
        assert cache.check() == {"state": "listed", "problem": None}

        fake.raises["getScanStatus"] = failure
        wrong.set()  #? ...and now the wrong one's call fails
        await asyncio.wait({old})
        assert (cache.listing, cache.problem, cache.check()) == (listed, None, {"state": "listed", "problem": None})
        third = folder("Portishead/Third (2008)", album="Third", release=THIRD)
        assert cache.unlisted([third]) == {"Portishead/Third (2008)"}, "its chips stay"
    run(scenario())


def test_another_navidrome_or_account_forgets_what_the_last_one_listed(navidrome_set, monkeypatch):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    monkeypatch.setattr(Config, "NAVIDROME_USER", "someone-else")
    assert run(cache.ask(None))["state"] == "checking"
    assert cache.listing is None


def test_unlisted_judges_each_folder_and_keeps_its_verdict_for_when_it_cannot(navidrome_set):
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    third = folder("Portishead/Third (2008)", album="Third", release=THIRD)
    dummy = folder("Portishead/Dummy (1994)", release=DUMMY_CD)
    assert cache.unlisted([third, dummy]) == {"Portishead/Third (2008)"}

    #? deadwax writes Third (an apply): its folder mtime doesn't move, but Navidrome hasn't looked since -
    #? the scan's next read of it says when (`written_at`)
    written = {**third, "written_at": time.time()}
    assert cache.unlisted([written, dummy]) == {"Portishead/Third (2008)"}, "still flagged - its last verdict"

    #? a folder never judged and written since: not raised
    cache._verdicts.clear()
    assert cache.unlisted([written, dummy]) == set()
    assert cache._verdicts == {"Portishead/Dummy (1994)": True}, "only verdicts made are kept"


def test_forget_cached_album_says_when_deadwax_wrote_the_folder(tmp_path):
    before = time.time()
    library.forget_cached_album(str(tmp_path / "A/B"))
    assert library.written_at(str(tmp_path / "A/B")) >= before
    assert library.written_at(str(tmp_path / "A/C")) is None
    library.clear_scan_cache()
    assert library.written_at(str(tmp_path / "A/B")) is None


def scanned(root):
    return {album["path"]: album for album in library.scan_library(str(root))["albums"]}


def test_the_scan_stamps_the_write_on_the_album_and_the_saved_cache_brings_it_back(tmp_path):
    """Whether a folder is flagged must not hang on whether deadwax restarted since it wrote it."""
    from tests.test_queue_summary import clean_album

    clean_album(tmp_path, "Portishead/Third (2008)", THIRD)
    assert "written_at" not in scanned(tmp_path)["Portishead/Third (2008)"], "nothing written: nothing said"
    library.drain_cache_changes()
    library.forget_cached_album(str(tmp_path / "Portishead/Third (2008)"))
    wrote = library.written_at(str(tmp_path / "Portishead/Third (2008)"))

    assert scanned(tmp_path)["Portishead/Third (2008)"]["written_at"] == wrote, "the next read stamps it"
    saved, _ = library.drain_cache_changes()
    assert [album.get("written_at") for _, _, album in saved] == [wrote], "...saved with the scan cache"

    library.clear_scan_cache()  #? a restart: memory gone, the saved rows loaded back
    library.seed_cache(saved)
    assert library.written_at(str(tmp_path / "Portishead/Third (2008)")) == wrote
    forced = {album["path"]: album for album in library.scan_library(str(tmp_path), force=True)["albums"]}
    assert forced["Portishead/Third (2008)"]["written_at"] == wrote, "a Rescan reads it afresh and keeps it"
    wire = library.compact_for_wire(list(forced.values()))
    assert not {"written_at", "changed_at"} & set(wire[0]), "the server's own: not sent"


def test_a_folder_moved_in_by_hand_carries_when_it_arrived(tmp_path):
    """Its mtime is the download's from an hour ago; its ctime, which nothing can set back, is now."""
    from tests.test_queue_summary import clean_album

    directory = clean_album(tmp_path / "downloads", "Portishead/Third (2008)", THIRD)
    hour_ago = time.time() - 3600
    os.utime(directory, (hour_ago, hour_ago))
    (tmp_path / "music" / "Portishead").mkdir(parents=True)
    arrived = time.time()
    os.rename(directory, tmp_path / "music" / "Portishead" / "Third (2008)")

    album = scanned(tmp_path / "music")["Portishead/Third (2008)"]
    assert album["modified_at"] == pytest.approx(hour_ago, abs=1)
    assert album["changed_at"] >= arrived - 1


# ----- measured from the scan's start (lastScan is written as a scan ENDS) -----

def test_a_folder_written_while_navidrome_scanned_is_not_judged_by_that_scan(navidrome_set):
    """Navidrome's scan ran from `began` to `ended`; Third was filed in between, after the scan had passed
    its folder. lastScan says `ended` - the folder counts as changed since the scan BEGAN, so it is never
    flagged until a scan that began after it."""
    ended = time.time() - 60
    began = ended - 30
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ended)) + f".{int(ended % 1 * 1e6):06d}000Z"
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)],
                         [{"scanning": False, "lastScan": stamp, "elapsedTime": int((ended - began) * 1e9)}])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    assert cache.listing.seen_until == pytest.approx(began, abs=0.01)
    mid_scan = folder("Portishead/Third (2008)", album="Third", release=THIRD, modified=began + 10)
    before_it = folder("Portishead/Third (2008)", album="Third", release=THIRD, modified=began - 10)
    assert cache.unlisted([mid_scan]) == set(), "written after the scan began: not judged by it"
    assert judge(before_it, cache.listing) is False, "there before the scan began: the scan saw it"


@pytest.mark.parametrize("elapsed", [None, 0, -5_000_000_000, True, "2s"])
def test_with_no_usable_elapsed_time_a_margin_stands_in(navidrome_set, elapsed):
    """An older server, a scan that started and never finished (its start after lastScan), or nonsense."""
    status = {"scanning": False, "lastScan": LAST_SCAN}
    if elapsed is not None:
        status["elapsedTime"] = elapsed
    cache = NavidromeListing(FakeNavidrome([nav("Dummy")], [status]))
    run(cache.ask(0))
    assert cache.listing.seen_until == pytest.approx(SCANNED - nl.LISTING_SETTLE_SECONDS, abs=1)


# ----- a read is judged by the answer in hand -----

def test_once_navidrome_has_answered_a_read_is_never_held_for_a_refresh(navidrome_set):
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        cache = NavidromeListing(fake)
        await cache.ask(0)
        first = cache.listing
        fake.hold = asyncio.Event()
        started = time.monotonic()
        check = await cache.ask(0, wait=5)
        assert time.monotonic() - started < 0.5, "the answer in hand, at once"
        assert check == {"state": "listed", "problem": None} and cache.listing is first
        await asyncio.sleep(0)
        assert fake.endpoints()[-1] == "getScanStatus", "...with the refresh asked behind it"
        fake.hold.set()
        await asyncio.wait({cache._task})
    run(scenario())


def test_after_a_failure_too_a_read_is_not_held(navidrome_set):
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        fake.down = True
        cache = NavidromeListing(fake)
        assert (await cache.ask(0))["state"] == "failed"
        fake.hold = asyncio.Event()
        started = time.monotonic()
        assert (await cache.ask(0, wait=5))["state"] == "failed"
        assert time.monotonic() - started < 0.5
        fake.hold.set()
        await asyncio.wait({cache._task})
    run(scenario())


def test_the_first_answer_is_waited_for_once_however_many_reads_come(navidrome_set):
    """A Navidrome that hasn't answered yet: the reads that come while it is out share one wait, counted
    from when it was asked - never each paying it again."""
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        fake.hold = asyncio.Event()
        cache = NavidromeListing(fake)
        started = time.monotonic()
        assert (await cache.ask(0, wait=0.2))["state"] == "checking"
        assert time.monotonic() - started == pytest.approx(0.2, abs=0.15)
        again = time.monotonic()
        assert (await cache.ask(0, wait=0.2))["state"] == "checking"
        assert time.monotonic() - again < 0.1, "the wait was spent: not paid twice"
        assert fake.endpoints() == ["getScanStatus"], "one refresh"
        fake.hold.set()
        await asyncio.wait({cache._task})
    run(scenario())


def test_a_rescan_waits_for_navidrome_even_with_an_answer_in_hand(navidrome_set):
    async def scenario():
        fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
        cache = NavidromeListing(fake)
        await cache.ask(0)
        fake.down = True
        assert (await cache.ask(0, rescan=True))["state"] == "failed", "the Rescan's own answer"
        fake.down = False
        fake.hold = asyncio.Event()
        started = time.monotonic()
        assert (await cache.ask(0, wait=0.2, rescan=True))["state"] == "failed"
        assert time.monotonic() - started == pytest.approx(0.2, abs=0.15), "bounded"
        fake.hold.set()
        await asyncio.wait({cache._task})
        assert cache.check()["state"] == "listed"
    run(scenario())


# ----- failures, whatever their kind -----

def test_a_call_that_never_answers_is_a_failure_within_its_bound(navidrome_set, monkeypatch):
    monkeypatch.setattr(nl, "LISTING_CALL_TIMEOUT_SECONDS", 0.05)
    fake = FakeNavidrome([nav("Dummy")])
    fake.hold = asyncio.Event()  #? never set
    cache = NavidromeListing(fake)
    assert asked(cache) == {"state": "failed", "problem": "Navidrome didn't answer within 0.05s"}
    assert fake.endpoints() == ["getScanStatus"], "unreached: the pages aren't waited out too"
    assert cache.age() is not None


def test_an_unexpected_error_is_a_failure_said_in_words_never_raised(navidrome_set):
    fake = FakeNavidrome([nav("Dummy")])
    fake.raises["getAlbumList2"] = ValueError("odd body")
    cache = NavidromeListing(fake)
    assert asked(cache) == {"state": "failed", "problem": "ValueError: odd body"}
    assert cache.age() is not None, "answered: not asked again on every read"


def test_a_scan_status_that_answers_wrongly_still_lets_the_albums_be_listed(navidrome_set):
    """Only NOT REACHING Navidrome ends the refresh at getScanStatus: an answer it can't use goes on."""
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    fake.raises["getScanStatus"] = NavidromeError("Navidrome said no: 0 - not supported")
    cache = NavidromeListing(fake)
    assert asked(cache)["state"] == "listed", "as a server that won't say when it scanned"
    assert fake.endpoints() == ["getScanStatus", "getAlbumList2", "getScanStatus"]
    assert cache.listing.seen_until == pytest.approx(time.time() - nl.LISTING_SETTLE_SECONDS, abs=5), "measured from now, with room"


# ----- the verdicts: merged, pruned by a real scan, carried through a move -----

def flagged_then_written():
    fake = FakeNavidrome([nav("Dummy", release=DUMMY_CD)])
    cache = NavidromeListing(fake)
    run(cache.ask(0))
    third = folder("Portishead/Third (2008)", album="Third", release=THIRD)
    dummy = folder("Portishead/Dummy (1994)", release=DUMMY_CD)
    assert cache.unlisted([third, dummy], prune=True) == {"Portishead/Third (2008)"}
    #? deadwax writes it: the scan's next read says when
    return cache, {**third, "written_at": time.time()}, dummy


def test_a_snapshot_without_a_folder_keeps_its_verdict(navidrome_set):
    """The count's route reads the saved scan, which lacks a folder a writer has just forgotten."""
    cache, third, dummy = flagged_then_written()
    assert cache.unlisted([dummy]) == set()
    assert cache.unlisted([third, dummy], prune=True) == {"Portishead/Third (2008)"}, "still flagged"


def test_only_a_real_scan_that_found_albums_lets_a_verdict_go(navidrome_set):
    cache, third, dummy = flagged_then_written()
    assert cache.unlisted([], prune=True) == set()
    assert "Portishead/Third (2008)" in cache._verdicts, "an empty scan is an unmounted volume more often than not"
    cache.unlisted([dummy], prune=True)
    assert cache._verdicts == {"Portishead/Dummy (1994)": True}, "gone from a real scan: gone"
    assert cache.unlisted([third, dummy]) == set(), "back at that path, changed since: not judged"


def test_a_folder_deadwax_moves_keeps_its_verdict_at_its_new_path(navidrome_set):
    cache, third, dummy = flagged_then_written()
    moved = {**third, "path": "Portishead/Third (2008) [Deluxe]"}
    cache.follow(third["path"], moved["path"])
    assert cache.unlisted([moved, dummy], prune=True) == {moved["path"]}
    assert third["path"] not in cache._verdicts

    #? merged into a folder with a verdict of its own: that one stands
    cache.follow(moved["path"], dummy["path"])
    assert cache._verdicts == {"Portishead/Dummy (1994)": True}
