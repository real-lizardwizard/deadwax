"""
src/index_keep.py (2.1.49): the Library's album list kept for a moment - for how long, for whom, what drops it,
and when nothing is kept at all. The route that keeps by it is tests/test_navidrome_album_index.py's.
"""

from src import index_keep, library
from src.index_keep import INDEX_KEEP_S, INDEX_SETTLE_S

JAMES = ("james", ("user", "james"), "http://navidrome:4533", "store")
JAMES_YOURS = ("james", ("user", "james"), "http://navidrome:4533", "yours")
ETHAN = ("ethan", ("user", "ethan"), "http://navidrome:4533", "store")


def keep(key, at, etag='"a"', body=b"packed"):
    index_keep.keep(key, etag, body, index_keep.epoch(), now=at)


def test_the_numbers_the_notes_give():
    assert (INDEX_KEEP_S, INDEX_SETTLE_S) == (30, 180)


def test_a_list_is_kept_for_its_time_and_no_longer():
    keep(JAMES, 100.0)

    assert index_keep.kept(JAMES, now=100.0) == ('"a"', b"packed")
    assert index_keep.kept(JAMES, now=100.0 + INDEX_KEEP_S - 0.01) == ('"a"', b"packed")
    assert index_keep.kept(JAMES, now=100.0 + INDEX_KEEP_S) is None
    assert index_keep._kept == {}, "and it is let go of"


def test_each_key_is_its_own():
    keep(JAMES, 100.0, '"store"')
    keep(JAMES_YOURS, 100.0, '"yours"')

    assert index_keep.kept(JAMES, now=101.0)[0] == '"store"'
    assert index_keep.kept(JAMES_YOURS, now=101.0)[0] == '"yours"'
    assert index_keep.kept(ETHAN, now=101.0) is None


def test_forgetting_one_person_leaves_everyone_elses():
    keep(JAMES, 100.0)
    keep(JAMES_YOURS, 100.0)
    keep(ETHAN, 100.0)

    index_keep.forget("james")

    assert index_keep.kept(JAMES, now=101.0) is None and index_keep.kept(JAMES_YOURS, now=101.0) is None
    assert index_keep.kept(ETHAN, now=101.0) is not None
    index_keep.forget()
    assert index_keep.kept(ETHAN, now=101.0) is None


def test_a_list_whose_reading_a_forget_cut_across_is_not_kept():
    """Read before the star landed, encoded after it: it may be the list from before."""
    began = index_keep.epoch()
    index_keep.forget("ethan")

    index_keep.keep(JAMES, '"a"', b"packed", began, now=100.0)

    assert index_keep.kept(JAMES, now=100.0) is None
    keep(JAMES, 100.0)
    assert index_keep.kept(JAMES, now=100.0) is not None


def test_an_unsettled_library_keeps_nothing_and_answers_from_nothing():
    keep(JAMES, 100.0)

    index_keep.unsettle(now=101.0)

    assert index_keep.kept(JAMES, now=101.0) is None
    keep(JAMES, 102.0)
    assert index_keep.kept(JAMES, now=102.0) is None, "nothing kept while Navidrome may be scanning"
    keep(JAMES, 101.0 + INDEX_SETTLE_S)
    assert index_keep.kept(JAMES, now=101.0 + INDEX_SETTLE_S) is not None


def test_a_later_change_keeps_it_unsettled_longer_and_an_earlier_one_never_shortens_it():
    index_keep.unsettle(now=100.0)
    index_keep.unsettle(now=200.0)
    index_keep.unsettle(now=150.0)

    keep(JAMES, 200.0 + INDEX_SETTLE_S - 1)
    assert index_keep.kept(JAMES, now=200.0 + INDEX_SETTLE_S - 1) is None
    keep(JAMES, 200.0 + INDEX_SETTLE_S)
    assert index_keep.kept(JAMES, now=200.0 + INDEX_SETTLE_S) is not None


def test_old_lists_are_let_go_of_as_new_ones_are_kept():
    keep(JAMES, 100.0)
    keep(ETHAN, 100.0 + INDEX_KEEP_S)

    assert list(index_keep._kept) == [ETHAN]


def test_every_writer_to_the_library_unsettles_it(tmp_path):
    """forget_cached_album is what every writer calls once its files are written; the poller says so as it files."""
    for changed in (library.note_library_changed, lambda: library.forget_cached_album(str(tmp_path / "Artist" / "Album"))):
        index_keep.reset()
        keep(JAMES, 100.0)
        began = index_keep.epoch()

        changed()

        assert index_keep.epoch() != began and index_keep._kept == {}
        assert index_keep._unsettled_until > 0
