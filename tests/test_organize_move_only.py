"""
Filing only ever moves (2.1.13) - and an old ORGANIZE_MODE is ignored, safely and visibly.

James (2026-11-13): "can we remove the 'organize mode' functionality? I would like it to only move the files,
I don't think we need anything else." So ORGANIZE_MODE (off, dry_run, copy, move) is no setting any more: a
finished download is moved into the library whenever SLSKD_DOWNLOAD_PATH and LIBRARY_PATH are both set. What an
install upgraded from before still carries must cost nothing:

  - an ORGANIZE_MODE in the container's environment is not read, and start-up says so, once, in plain words;
  - a value Server settings saved for it is passed over by apply_overrides without a warning, cleared from the
    database at start-up, and said in the same one line;
  - the settings page still draws with such a row in the database, a revert of it is let through (and clears
    it), and a value for it is refused in words that say why - never a 500;
  - deadwax starts as before whatever the old value was: dry_run, copy, off, move, or junk.

And since filing always moves, a slskd folder deadwax can't write to (a `:ro` /downloads, which copy used to be fine
with, or slskd's own user owning its folders) is refused before anything is written: shutil.move would copy each
file into the library and then fail to remove the original, leaving an untagged copy behind on every download. The
bottom of this file holds that guard; tests/test_filing_guards.py the rest the review of moving-always asked for -
the library never searched or cleared, Server settings asking what filing asks, refused downloads filed by
themselves once fixed, and the clean-up keeping any folder with something unknown left in it.

That a download is MOVED is held in test_organizer.py and test_poller.py; the logins rule (the two folders) in
test_downloads_per_person.py. See "Filing only moves (2.1.13)" in notes/decisions.md.
"""

import asyncio
import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api.app import start  # noqa: E402
from src.config import RETIRED_SETTINGS, Config, clear_retired_settings, describe_organize_mode_ignored  # noqa: E402
from src.routes.settings import RETIRED  # noqa: E402
from src.store import JobStore  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OLD_VALUES = ["dry_run", "copy", "off", "move", "sideways", ""]


@pytest.fixture
def store(tmp_path):
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    return store


@pytest.fixture
def clean_config(monkeypatch):
    """Config as the environment left it, nothing overridden, and logins off."""
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.delenv("ORGANIZE_MODE", raising=False)


def _said(caplog) -> list[logging.LogRecord]:
    return [record for record in caplog.records if "ORGANIZE_MODE" in record.getMessage()]


# ----------------------------------------------------------------- no setting any more

def test_organize_mode_is_no_setting_and_no_attribute():
    assert RETIRED_SETTINGS == ("ORGANIZE_MODE",)
    assert "ORGANIZE_MODE" not in Config.EDITABLE and "ORGANIZE_MODE" not in Config.NOT_EDITABLE
    assert not hasattr(Config, "ORGANIZE_MODE")


@pytest.mark.parametrize("old", OLD_VALUES)
def test_an_old_environment_value_changes_nothing(monkeypatch, tmp_path, old):
    """Whatever the environment says, organizing is the two folders: on with both, off without either."""
    monkeypatch.setenv("ORGANIZE_MODE", old)
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    assert Config.organizing_enabled() is True
    monkeypatch.setattr(Config, "LIBRARY_PATH", None)
    assert Config.organizing_enabled() is False


# ----------------------------------------------------------------- a saved override

def test_apply_overrides_passes_over_a_saved_mode_without_a_word(clean_config, monkeypatch, caplog):
    """A row saved before 2.1.13 is not laid over Config, not counted as overridden, and not warned about as 'not
    editable' - start-up's one line says it; every save after re-applies the store and must stay quiet."""
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "500")
    caplog.set_level(logging.INFO)
    Config.apply_overrides({"ORGANIZE_MODE": "dry_run", "COVER_ART_SIZE": "1200"})
    try:
        assert Config.OVERRIDDEN == {"COVER_ART_SIZE"} and Config.COVER_ART_SIZE == "1200"
        assert not hasattr(Config, "ORGANIZE_MODE")
        assert not _said(caplog) and "not editable" not in caplog.text
    finally:
        Config.apply_overrides({})


def test_start_up_clears_a_saved_mode_and_keeps_every_other_row(store):
    asyncio.run(store.set_setting("ORGANIZE_MODE", "dry_run"))
    asyncio.run(store.set_setting("COVER_ART_SIZE", "1200"))
    stored = store.stored_settings()

    assert asyncio.run(clear_retired_settings(store, stored)) == ["ORGANIZE_MODE"]
    assert store.stored_settings() == {"COVER_ART_SIZE": "1200"}
    #? nothing left to clear the next time
    assert asyncio.run(clear_retired_settings(store, store.stored_settings())) == []


def test_clearing_on_a_store_that_cant_write_costs_nothing(tmp_path):
    """An unavailable database clears nothing and raises nothing: apply_overrides passes the row over anyway."""
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.available = False
    assert asyncio.run(clear_retired_settings(store, {"ORGANIZE_MODE": "copy"})) == []


# ----------------------------------------------------------------- what start-up says

def test_start_up_says_nothing_when_it_is_set_nowhere(clean_config, caplog):
    caplog.set_level(logging.INFO)
    Config.report_retired({})
    Config.report_retired(None)
    assert not _said(caplog)
    assert describe_organize_mode_ignored(None, None) is None


@pytest.mark.parametrize("old", OLD_VALUES)
def test_start_up_says_once_that_an_environment_value_is_ignored(clean_config, monkeypatch, caplog, old):
    monkeypatch.setenv("ORGANIZE_MODE", old)
    caplog.set_level(logging.INFO)
    Config.report_retired({})

    said = _said(caplog)
    assert len(said) == 1 and said[0].levelno == logging.WARNING
    assert getattr(said[0], "frontend", False) is True, "the event log in the app shows it too"
    words = said[0].getMessage()
    assert f"({old or 'empty'})" in words
    assert "no longer reads it" in words and "moved into the library" in words
    assert "SLSKD_DOWNLOAD_PATH and LIBRARY_PATH" in words
    assert "Delete the ORGANIZE_MODE line" in words and "Nothing needs doing" not in words


def test_start_up_says_a_saved_value_was_cleared(clean_config, caplog):
    caplog.set_level(logging.INFO)
    Config.report_retired({"ORGANIZE_MODE": "copy", "COVER_ART_SIZE": "1200"})

    said = _said(caplog)
    assert len(said) == 1
    words = said[0].getMessage()
    assert "in Server settings (copy), where it has now been cleared" in words
    assert "Nothing needs doing." in words and "Delete the ORGANIZE_MODE line" not in words


def test_start_up_says_both_places_in_one_line(clean_config, monkeypatch, caplog):
    monkeypatch.setenv("ORGANIZE_MODE", "move")
    caplog.set_level(logging.INFO)
    Config.report_retired({"ORGANIZE_MODE": "dry_run"})

    said = _said(caplog)
    assert len(said) == 1
    words = said[0].getMessage()
    assert "(move)" in words and "in Server settings (dry_run)" in words and "Delete the ORGANIZE_MODE line" in words


def test_start_up_clears_and_reports_after_the_overrides_are_applied():
    """The lifespan's order: the stored rows read once, laid over Config, the retired ones cleared from that same
    read, and the one line said with what was saved - so a cleared row is still named."""
    source = (REPO / "src/api/app.py").read_text(encoding="utf-8")
    read = source.index("stored = app.state.store.stored_settings()")
    applied = source.index("Config.apply_overrides(stored)", read)
    cleared = source.index("await clear_retired_settings(app.state.store, stored)", applied)
    reported = source.index("Config.report_retired(stored)", cleared)
    assert read < applied < cleared < reported


@pytest.mark.parametrize("old", ["dry_run", "copy", "off", "move", "junk"])
def test_deadwax_starts_as_before_whatever_the_old_value(tmp_path, old):
    """Config read fresh with the old value in the environment - as a container upgraded with its compose file
    unchanged starts - checks and reports without a word of error, and has no ORGANIZE_MODE of its own."""
    script = (
        "import logging, sys\n"
        "logging.basicConfig(level=logging.INFO, stream=sys.stdout, format='%(levelname)s %(message)s')\n"
        "from src.config import Config\n"
        "Config.check()\n"
        "Config.report_slskd()\n"
        "Config.report_retired({})\n"
        "print('HAS_ATTRIBUTE', hasattr(Config, 'ORGANIZE_MODE'))\n"
        "print('ORGANIZING', Config.organizing_enabled())\n"
    )
    env = {key: value for key, value in os.environ.items() if not key.startswith(("SLSKD_", "LIBRARY_", "NAVIDROME_"))}
    env.update({
        "ORGANIZE_MODE": old,
        "SLSKD_DOWNLOAD_PATH": str(tmp_path / "downloads"),
        "LIBRARY_PATH": str(tmp_path / "music"),
        "DB_PATH": str(tmp_path / "deadwax.db"),
        "AUTH_MODE": "off",
    })
    run = subprocess.run([sys.executable, "-c", script], cwd=REPO, env=env, capture_output=True, text=True, timeout=60)
    assert run.returncode == 0, run.stderr
    out = run.stdout
    assert "HAS_ATTRIBUTE False" in out and "ORGANIZING True" in out
    assert "finished downloads are moved into LIBRARY_PATH" in out
    assert out.count("no longer reads it") == 1 and f"in the container environment ({old})" in out
    assert "Traceback" not in run.stderr
    #? the old mode's own complaint (an unrecognised value, fallen back to dry_run) is gone with it: the one line
    #? naming ORGANIZE_MODE is the warning that it's ignored
    named = [line for line in out.splitlines() if "ORGANIZE_MODE" in line]
    assert len(named) == 1 and named[0].startswith("WARNING "), named


# ----------------------------------------------------------------- the settings page

@pytest.fixture
def app(clean_config, store, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_URL", None)
    monkeypatch.setattr(Config, "SLSKD_APIKEY", None)
    app = start()
    app.state.store = store
    yield TestClient(app)  # no `with`, so no lifespan: nothing connects
    Config.apply_overrides({})


def test_the_settings_page_draws_with_an_old_row_in_the_database(app, store):
    """A row start-up didn't get to clear (a database it couldn't write, say) breaks nothing: no row shows it, and
    the answer has no organize_modes."""
    asyncio.run(store.set_setting("ORGANIZE_MODE", "dry_run"))
    Config.apply_overrides(store.stored_settings())

    answer = app.get("/deadwax/settings")
    assert answer.status_code == 200
    body = answer.json()
    keys = [setting["key"] for group in body["groups"] for setting in group["settings"]]
    assert "ORGANIZE_MODE" not in keys and "organize_modes" not in body
    assert "ORGANIZE_MODE" not in answer.text


def test_a_save_beside_an_old_row_works_and_says_nothing_of_it(app, store, monkeypatch, caplog):
    asyncio.run(store.set_setting("ORGANIZE_MODE", "copy"))
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "500")
    caplog.set_level(logging.INFO)

    answer = app.put("/deadwax/settings", json=[{"key": "COVER_ART_SIZE", "value": "1200"}])
    assert answer.status_code == 200, answer.text
    assert Config.COVER_ART_SIZE == "1200" and Config.OVERRIDDEN == {"COVER_ART_SIZE"}
    assert "not editable" not in caplog.text


def test_reverting_an_old_row_is_let_through_and_clears_it(app, store):
    """A page drawn before the upgrade may still send it - 'Revert to the environment' is null."""
    asyncio.run(store.set_setting("ORGANIZE_MODE", "dry_run"))

    answer = app.put("/deadwax/settings", json=[{"key": "ORGANIZE_MODE", "value": None}])
    assert answer.status_code == 200, answer.text
    assert "ORGANIZE_MODE" not in store.stored_settings()
    assert not hasattr(Config, "ORGANIZE_MODE")


@pytest.mark.parametrize("value", ["move", "copy", "dry_run", "off"])
def test_saving_a_value_for_it_is_refused_in_words_that_say_why(app, store, value):
    answer = app.put("/deadwax/settings", json=[{"key": "ORGANIZE_MODE", "value": value}])
    assert answer.status_code == 400
    assert answer.json()["detail"] == f"ORGANIZE_MODE: {RETIRED}"
    assert "moved into the library" in RETIRED and "SLSKD_DOWNLOAD_PATH and LIBRARY_PATH" in RETIRED
    #? the whole batch is refused, as for any refusal: nothing written
    assert store.stored_settings() == {}


# ----------------------------------------------------------------- a slskd folder deadwax can't write to

from src import organizer  # noqa: E402
from src.organizer import (can_move_out_of, execute_plan, mounted_read_only, organize_job,  # noqa: E402
                           plan_organization, why_cannot_move_out_of)
from src.poller import READ_ONLY_DOWNLOADS, job_outcome, poll_downloads_once  # noqa: E402
from tests.test_poller import FakeSlskd, _all_done, make_store, seed_job  # noqa: E402

#? permissions are what a test can take away; root ignores them (a read-only MOUNT it can't, and os.access says so -
#? but no test can make one), so these need an ordinary user, as CI's runner is
needs_a_user = pytest.mark.skipif(hasattr(os, "geteuid") and os.geteuid() == 0, reason="root ignores folder permissions")

RELEASE = {"artist": "Boards of Canada", "album": "Music Has the Right to Children", "year": "1998",
           "release_mbid": "mb-1", "tracks": [{"position": 1, "title": "Wildlife Analysis"},
                                              {"position": 2, "title": "An Eagle in Your Mind"}]}
ALBUM = ("Boards of Canada", "Music Has the Right to Children (1998)")


@pytest.fixture
def slskd_folder(tmp_path):
    """slskd's folder holding one finished download - two tracks and a cover. A test makes it read-only
    (READ_ONLY); it is given its permissions back after, so pytest can clear it."""
    folder = tmp_path / "downloads" / "BoC"
    folder.mkdir(parents=True)
    (folder / "01 Wildlife Analysis.flac").write_bytes(b"one")
    (folder / "02 An Eagle in Your Mind.flac").write_bytes(b"two")
    (folder / "cover.jpg").write_bytes(b"art")
    yield folder
    if folder.exists():
        folder.chmod(0o755)


#? r-x for everyone: readable and searchable, as a `:ro` mount is - nothing can be taken out of it
READ_ONLY = 0o555


def _job(files=("01 Wildlife Analysis.flac", "02 An Eagle in Your Mind.flac")):
    return {"id": 7, "artist": RELEASE["artist"], "album": RELEASE["album"], "username": "bob", "directory": "share/BoC",
            "release": RELEASE, "files": [{"filename": f"share\\BoC\\{name}", "size": 3} for name in files]}


def _everything_under(root: Path) -> list[str]:
    return sorted(str(p.relative_to(root)) for p in root.rglob("*")) if root.exists() else []


@needs_a_user
def test_the_plan_names_a_folder_that_can_t_be_moved_out_of(tmp_path, slskd_folder):
    plan = plan_organization(_job(), str(tmp_path / "downloads"), str(tmp_path / "music"))
    assert plan["read_only_dirs"] == []

    slskd_folder.chmod(READ_ONLY)
    assert can_move_out_of(slskd_folder) is False
    plan = plan_organization(_job(), str(tmp_path / "downloads"), str(tmp_path / "music"))
    assert plan["read_only_dirs"] == [str(slskd_folder)]
    #? the plan is still the whole plan - what would happen - so a preview stays honest
    assert len(plan["operations"]) == 3


@needs_a_user
def test_executing_a_plan_from_a_read_only_folder_writes_nothing(tmp_path, slskd_folder):
    slskd_folder.chmod(READ_ONLY)
    plan = plan_organization(_job(), str(tmp_path / "downloads"), str(tmp_path / "music"))

    results = execute_plan(plan, RELEASE)
    assert results["read_only"] == [str(slskd_folder)]
    assert (results["organized"], results["failed"], results["skipped"]) == (0, 0, 0)
    #? nothing copied in half-way, nothing tagged, not even the folder the album would have gone in
    assert _everything_under(tmp_path / "music") == []
    assert sorted(p.name for p in slskd_folder.iterdir()) == \
        ["01 Wildlife Analysis.flac", "02 An Eagle in Your Mind.flac", "cover.jpg"]


@needs_a_user
def test_filing_refuses_before_it_marks_moves_or_cleans_anything(tmp_path, slskd_folder, caplog):
    slskd_folder.chmod(READ_ONLY)
    marked = []
    caplog.set_level(logging.INFO)

    results = asyncio.run(organize_job(_job(), str(tmp_path / "downloads"), str(tmp_path / "music"),
                                       on_plan=marked.append))
    assert results["read_only"] == [str(slskd_folder)] and results["organized"] == 0
    assert marked == [], "the album folder is never marked as being filed"
    assert "removed_dirs" not in results, "no clean-up after a refusal"
    assert _everything_under(tmp_path / "music") == []
    assert len(list(slskd_folder.iterdir())) == 3
    said = [r.getMessage() for r in caplog.records if "can't move files out of slskd's download folder" in r.getMessage()]
    #? the folder, its own cause (here deadwax owns it, and it isn't writable) and that it files by itself once fixed
    assert len(said) == 1 and str(slskd_folder) in said[0]
    assert "deadwax's own but not writable (dr-xr-xr-x)" in said[0] and "filed by itself" in said[0]


def test_a_writable_folder_moves_as_before(tmp_path, slskd_folder):
    results = asyncio.run(organize_job(_job(), str(tmp_path / "downloads"), str(tmp_path / "music")))
    assert "read_only" not in results
    assert (results["organized"], results["tracks_organized"], results["failed"]) == (3, 2, 0)
    assert _everything_under(tmp_path / "music" / ALBUM[0] / ALBUM[1]) == \
        ["01 - Wildlife Analysis.flac", "02 - An Eagle in Your Mind.flac", "cover.jpg"]
    assert not slskd_folder.exists(), "moved, and the emptied folder cleared away"


@needs_a_user
def test_a_read_only_folder_whose_files_all_stay_is_not_refused(tmp_path, slskd_folder):
    """Only a folder something would actually be moved OUT of is asked: every target already there means nothing
    moves, and the row says it was already there, as it always did."""
    for name in ("01 - Wildlife Analysis.flac", "02 - An Eagle in Your Mind.flac", "cover.jpg"):
        target = tmp_path / "music" / ALBUM[0] / ALBUM[1] / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"already")
    slskd_folder.chmod(READ_ONLY)

    plan = plan_organization(_job(), str(tmp_path / "downloads"), str(tmp_path / "music"))
    assert plan["read_only_dirs"] == []
    results = execute_plan(plan, RELEASE)
    assert "read_only" not in results and results["skipped"] == 2


@needs_a_user
def test_the_row_says_what_to_change_and_nothing_is_filed(tmp_path, monkeypatch):
    """Through the poller: the download finishes, filing is refused, the job ends `complete` with the named words,
    nothing reaches the library, and the files are all still in slskd's folder."""
    downloads = tmp_path / "downloads" / "album"
    downloads.mkdir(parents=True)
    (downloads / "01.flac").write_bytes(b"one")
    (downloads / "02.flac").write_bytes(b"two")
    downloads.chmod(READ_ONLY)
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    try:
        store = make_store(tmp_path)
        job_id = seed_job(store)
        asyncio.run(poll_downloads_once(FakeSlskd(_all_done()), store, {}))

        job = next(j for j in asyncio.run(store.list_jobs()) if j["id"] == job_id)
        assert (job["status"], job["error"]) == ("complete", READ_ONLY_DOWNLOADS)
        assert _everything_under(tmp_path / "music") == []
        assert sorted(p.name for p in downloads.iterdir()) == ["01.flac", "02.flac"]
    finally:
        downloads.chmod(0o755)


def test_the_words_name_the_fix_and_another_source_isn_t_offered():
    """For whoever runs deadwax: nothing moved, both causes' fixes - no `:ro`, or slskd and deadwax as one user - and
    that it files by itself once fixed (review: the likeliest cause has no `:ro` at all). Not job_outcome's
    `not_filed`, which offers the next source - that would land in the same place and be refused the same way."""
    assert "can't move files out of slskd's download folder" in READ_ONLY_DOWNLOADS
    assert "nothing was moved" in READ_ONLY_DOWNLOADS and "drop :ro" in READ_ONLY_DOWNLOADS
    assert "same PUID/PGID" in READ_ONLY_DOWNLOADS and "filed by itself once fixed" in READ_ONLY_DOWNLOADS
    assert "again" not in READ_ONLY_DOWNLOADS, "never sent to get it again - a second copy would land beside the first"
    assert job_outcome("complete", READ_ONLY_DOWNLOADS, not_filed=True) is None


def test_each_cause_is_named_with_its_own_fix(tmp_path, monkeypatch):
    """(review) The event log names the folder's own cause: a read-only mount (remove :ro), a folder another user owns
    - slskd's, the likeliest - (the same PUID/PGID), or deadwax's own folder without write permission."""
    folder = tmp_path / "BoC"
    folder.mkdir()
    folder.chmod(READ_ONLY)
    try:
        assert why_cannot_move_out_of(folder) == f"{folder} is deadwax's own but not writable (dr-xr-xr-x) - give its owner write access"
        monkeypatch.setattr(organizer.os, "geteuid", lambda: os.stat(folder).st_uid + 1)
        monkeypatch.setattr(organizer.os, "getegid", lambda: 4242)
        said = why_cannot_move_out_of(folder)
        assert said.startswith(f"{folder} is owned by uid {os.stat(folder).st_uid}, gid {os.stat(folder).st_gid} (dr-xr-xr-x)")
        assert f"deadwax runs as uid {os.stat(folder).st_uid + 1}, gid 4242" in said
        assert said.endswith("run slskd and deadwax as the same PUID/PGID, or give deadwax write access to slskd's downloads")
        monkeypatch.setattr(organizer, "mounted_read_only", lambda path: True)
        assert why_cannot_move_out_of(folder) == f"{folder} is on a read-only mount - remove :ro from the /downloads volume"
    finally:
        folder.chmod(0o755)


def test_a_read_only_mount_is_read_from_statvfs(tmp_path, monkeypatch):
    assert mounted_read_only(tmp_path) is False

    class Answer:
        f_flag = os.ST_RDONLY

    monkeypatch.setattr(organizer.os, "statvfs", lambda path: Answer())
    assert mounted_read_only(tmp_path) is True
    #? a path statvfs can't answer for is not called read-only - the permission check still stands
    monkeypatch.setattr(organizer.os, "statvfs", lambda path: (_ for _ in ()).throw(OSError("gone")))
    assert mounted_read_only(tmp_path) is False


def test_the_check_asks_the_kernel_for_write_and_search(monkeypatch, tmp_path):
    """os.access, so a read-only mount (EROFS) answers no as well as a permission does - and both write and search
    are asked: taking a file out of a folder needs the two."""
    asked = []
    monkeypatch.setattr(organizer.os, "access", lambda path, mode: asked.append((path, mode)) or False)
    assert can_move_out_of(tmp_path) is False
    assert asked == [(tmp_path, os.W_OK | os.X_OK)]
