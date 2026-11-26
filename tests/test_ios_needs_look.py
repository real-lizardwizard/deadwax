"""
The iPhone app's Needs a look (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; notes/ios.md "Needs a look on the
phone") against the two routes it adds - the count (`GET /library/queue/summary`) and an album looked at (`POST
/library/queue/reviewed`) - read from its own source (ios/DeadwaxKit/Sources/DeadwaxCore: NeedsLook.swift, Retag.swift,
Managing.swift, Routes.swift; ios/App/Manage) and held to the server's. The page's list is the scan Edit album reads
(tests/test_ios_edit_contract.py holds it); its marks are Edit album's two (the same file).

- what it SENDS - QueueMarkBody, its path alone (no `issues` key: the model's own default) - to the real reviewed route;
- what it READS - QueueSummary from the real count, before a scan and after one, and QueueReviewed from a real note, over
  a real folder of real FLACs, Navidrome not set up (nothing here calls out);
- how long it waits - the count past the most the route waits for Navidrome's first listing, as long as the album
  index's saved read; a note as long as a mark (one store row);
- who may: the count and the page by Look after the library, as the server's routes are (tests/test_logins.py ROUTES);
- and that the count is asked as the web asks it - one request out at a time, never polled, never without the
  permission - and that every write the app makes to the library asks it again.
"""

import asyncio
import inspect
import re
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import library  # noqa: E402
from src import navidrome_listing  # noqa: E402
from src.api import same_origin  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import library as library_route  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests.test_ios_contract import CORE, coding_keys, swift_function, swift_struct  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402
from tests.test_retag import seed  # noqa: E402

APP = CORE.parent.parent.parent / "App"
ALBUM = "Tame Impala/The Slow Rush (2020)"


def reads(struct: str) -> set[str]:
    """Every JSON name a Decodable struct reads: its CodingKeys (each of these models reads every key it names)."""
    keys = coding_keys(swift_struct(struct))
    assert keys is not None, f"{struct} has no CodingKeys"
    return set(keys.values())


def timeouts() -> dict[str, float]:
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    return {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}


def app_file(*parts: str) -> str:
    return APP.joinpath(*parts).read_text(encoding="utf-8")


@pytest.fixture(autouse=True)
def nothing_left_over(monkeypatch):
    """The scan's caches emptied and Navidrome not set up - all of it lives in the process, not the request."""
    library.clear_scan_cache()
    monkeypatch.setattr(library_route, "_cache_loaded_for", None)
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    yield
    library.clear_scan_cache()


@pytest.fixture
def env(monkeypatch, tmp_path):
    root = tmp_path / "music"
    root.mkdir()
    seed(root)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    app.state.store = store
    return SimpleNamespace(client=TestClient(app), store=store, app=app)


# ---------------------------------------------------------------------------- the routes, and who may

def test_the_routes_are_the_servers_by_method_path_and_permission():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    for name, method, path in (("queueSummary", "GET", "/deadwax/library/queue/summary"),
                               ("queueReviewed", "POST", "/deadwax/library/queue/reviewed")):
        line = f'public static let {name} = Endpoint(method: "{method}", path: "{path}", query: [])'
        assert line in text, line
        # both Look after the library's, as the count and the page are on the phone
        assert ROUTES[(method, path)] == "library", (method, path)
    assert "permissions.contains(.library)" in swift_function("Managing.swift", "asksQueueSummary")
    page = swift_function("Managing.swift", "needsLook")
    assert "NeedsLookPage(allowed: permissions.contains(.library), canEdit: permissions.contains(.edit))" in page
    # the scan the page lists is Edit album's, read the same way - a route anyone signed in may read, which the page
    # asks only with Look after the library (NeedsLookModel's reads are guarded by page.allowed)
    assert ROUTES[("GET", "/deadwax/library/albums")] == "user"
    page_model = app_file("Manage", "NeedsLookModel.swift")
    assert "guard samePerson, page.allowed, server?.signInOver == nil else { return }" in swift_like(page_model, "read")
    assert "guard page.allowed, online, samePerson else { return }" in swift_like(page_model, "look")
    assert 'request(Routes.libraryAlbums, query: [("tracks", "false")])' in swift_function("EditClient.swift",
                                                                                           "libraryScan")


def test_a_note_sends_its_path_alone():
    body = swift_function("NeedsLook.swift", "markReviewed")
    assert "QueueMarkBody(albumPath: path, issues: nil)" in body
    # no issues is no key at all (QueueMarkBody's encodeIfPresent): the model's own default
    assert library_route.QueueRequest(album_path=ALBUM).issues == []
    assert {"album_path", "issues"} >= set(library_route.QueueRequest.model_fields) >= {"album_path"}
    assert same_origin.refusal("POST", {"content-type": "application/json"}) is None


# ---------------------------------------------------------------------------- what the phone reads, from real routes

def test_the_count_is_what_the_phone_reads_before_a_scan_and_after(env):
    # deadwax filed it: a new import, before any scan has seen the folder
    asyncio.run(env.store.record_albums_seen([{"path": ALBUM, "artist": "Tame Impala", "album": "The Slow Rush"}],
                                             source="import"))
    first = env.client.get("/deadwax/library/queue/summary")
    assert first.status_code == 200, first.text
    count = first.json()
    assert reads("QueueSummary") <= set(count), reads("QueueSummary") - set(count)
    assert count["known"] is False and count["total"] == 1 and count["tracking_enabled"] is True
    # the page's scan, then the count over it: the album listed, new, and counted once
    scan = env.client.get("/deadwax/library/albums", params={"tracks": "false"})
    assert scan.status_code == 200, scan.text
    [album] = scan.json()["albums"]
    assert album["path"] == ALBUM and album["imported"] is True and album["reviewed"] is False
    assert scan.json()["review_tracking_enabled"] is True
    counted = env.client.get("/deadwax/library/queue/summary").json()
    assert counted["known"] is True and counted["new_imports"] == 1 and counted["total"] >= 1
    # looked at: what clears a new import - its issues, if any, stay
    noted = env.client.post("/deadwax/library/queue/reviewed", json={"album_path": ALBUM})
    assert noted.status_code == 200, noted.text
    assert reads("QueueReviewed") <= set(noted.json())
    assert noted.json() == {"reviewed": True, "album_path": ALBUM}
    after = env.client.get("/deadwax/library/queue/summary").json()
    assert after["new_imports"] == 0 and after["total"] == counted["total"] - 1 + (1 if album["needs_attention"] else 0)
    again = env.client.get("/deadwax/library/albums", params={"tracks": "false"}).json()
    assert again["albums"][0]["reviewed"] is True


def test_with_no_store_the_count_says_marks_cant_be_kept_and_a_note_is_refused(env):
    env.app.state.store = None
    count = env.client.get("/deadwax/library/queue/summary")
    assert count.status_code == 200 and count.json()["tracking_enabled"] is False
    # the phone's ignoresUnsaved reads the count's tracking_enabled (absent is true, as the web reads it)
    assert "trackingEnabled = fields.looseField(Bool.self, .trackingEnabled) ?? true" in swift_struct("QueueSummary")
    refused = env.client.post("/deadwax/library/queue/reviewed", json={"album_path": ALBUM})
    assert refused.status_code == 503 and "job store" in refused.json()["detail"]


# ---------------------------------------------------------------------------- how long the phone waits

def test_the_count_and_a_note_are_waited_for_past_the_routes_worst_case():
    given = timeouts()
    # the count reads the saved scan and the store, never the disk, and waits for Navidrome's first listing at most
    # LISTING_WAIT_SECONDS - as long as the album index's own saved read, which is far past it
    handler = inspect.getsource(library_route.queue_summary).split('"""')[2]
    assert "await asyncio.to_thread(snapshot_library, root)" in handler
    assert "await navidrome_listing.ask(LISTING_STALE_SECONDS)" in handler
    assert "scan_library(" not in handler and "_scan_with_queue(" not in handler
    assert "wait = LISTING_WAIT_SECONDS if wait is None else wait" in inspect.getsource(
        navidrome_listing.NavidromeListing.ask)
    assert given["queueSummary"] >= given["albumIndex"] > navidrome_listing.LISTING_WAIT_SECONDS
    # a note writes one store row, as a mark does
    note = inspect.getsource(library_route.reviewed)
    assert note.count("await store.") == 1 and "await store.mark_album_reviewed(body.album_path)" in note
    assert given["queueReviewed"] == given["queueIgnore"] == given["queueUnignore"]
# ---------------------------------------------------------------------------- the app

def test_the_count_is_asked_as_the_web_asks_it():
    model = app_file("Manage", "QueueCountModel.swift")
    # one request out at a time, never without Look after the library, an answer for the last person dropped
    assert ("guard count.ask(allowed: Managing.asksQueueSummary(server.access.permissions) && server.signInOver == nil)"
            " else {") in model
    assert "let summary = try await client.queueSummary()" in model
    assert model.count("guard ticket == generation else { return }") == 3
    assert "Timer" not in model and "sleep" not in model, "the count is never polled"
    # drawn as Manage's value, read once by VoiceOver - never on a tab
    manage = app_file("You", "ManageSection.swift")
    assert "NavigationLink(value: AppRoute.needsALook)" in manage
    assert "Text(queueCount.count.value)" in manage and ".accessibilityLabel(queueCount.count.spoken)" in manage
    tabs = app_file("Root", "MainTabs.swift")
    bar = tabs[tabs.index("struct AppTabBar"):]
    assert "queueCount" not in bar.split("\nstruct ", 1)[0], "the count is never on a tab"
    # the next person starts with none - and none of the last one's pages on screen
    assert "queueCount.reset()" in app_file("DeadwaxApp.swift")
    assert "showing = []" in swift_like(model, "reset")


def test_the_count_is_asked_only_while_a_page_that_uses_it_shows():
    # (slice 6's review) asked as Settings or Needs a look comes on screen, on their pulls, back from the background
    # with one up, and after something may have moved it - never at start-up on another tab, never twice for one event
    model = app_file("Manage", "QueueCountModel.swift")
    assert "private func ask()" in model, "nothing outside asks without saying why"
    assert "guard showing.insert(page).inserted else { return }" in swift_like(model, "shows"), "once per showing"
    assert "guard !showing.isEmpty else { return }" in swift_like(model, "changed")
    scene = swift_like(model, "scene")
    assert "case .background:\n            away = true" in scene
    assert "guard away else { return }" in scene and "changed()" in scene, "back from the background, not a launch"
    you = app_file("You", "YouView.swift")
    assert "queueCount.shows(.settings)" in you and "queueCount.hides(.settings)" in you
    pull = you[you.index(".pullToRefresh {"):you.index(".task {")]
    assert pull.index("queueCount.pulled()") < pull.index("await server.refreshMe()"), \
        "asked before /me, so the permission it may give asks once"
    screen = app_file("Manage", "NeedsLookScreen.swift")
    assert "count.shows(.needsLook)" in screen and "count.hides(.needsLook)" in screen
    tabs = app_file("Root", "MainTabs.swift")
    assert ".onChange(of: navigation.managingWrites) { _, _ in queueCount.changed() }" in tabs
    assert ".onChange(of: scenePhase) { _, phase in queueCount.scene(phase) }" in tabs
    assert ".onChange(of: Managing.asksQueueSummary(server.access.permissions)) { _, asks in" in tabs
    # (slice 7's review) never under the sign-in over the app - Settings and Needs a look still count as shown under
    # it, and Now Playing closing under it brings one on screen - and asked again as it goes; one asked again while a
    # request was out waits for it too
    assert "guard let client = server.client, server.signInOver == nil else {" in swift_like(model, "run")
    assert ".onChange(of: server.signInOver == nil) { _, clear in\n            if clear { queueCount.changed() }" in tabs
    assert "Managing.asksQueueSummary(server.access.permissions), initial: true" not in tabs, "never at start-up on another tab"
    # nothing anywhere else asks it
    for path in APP.rglob("*.swift"):
        if path.name == "QueueCountModel.swift":
            continue
        text = path.read_text(encoding="utf-8")
        assert "queueCount.ask()" not in text and "count?.ask()" not in text and "count.ask()" not in text, path.name
    # Needs a look's own pull: never out of reach, the count then the list - (R12's review) and never while a session
    # lasts or a read is out (Core's NeedsLookPage.pullReads, test_ios_needs_look_look's pin)
    page = app_file("Manage", "NeedsLookModel.swift")
    pulled = swift_like(page, "pulled")
    assert ("guard NeedsLookPage.pullReads(online: online, samePerson: samePerson, allowed: page.allowed,"
            in pulled and "session: session != nil, reading: scan.reading) else { return }" in pulled)
    assert pulled.index("count?.pulled()") < pulled.index("await read()")
    assert ".pullToRefresh {\n            await model.pulled()\n        }" in screen
    # (slice 7's review) nothing read or noted under the sign-in over the app: every read of the page's goes through
    # read() (reach, shows, the pull, Try again, a session's ending) and every note through review() - the editor's
    # sheet stays up over the sign-in, so its steps reach them - and once it goes, the page reads again
    assert "guard samePerson, page.allowed, server?.signInOver == nil else { return }" in swift_like(page, "read")
    assert "guard let path, samePerson, server?.signInOver == nil, let client = server?.client else { return }" \
        in swift_like(page, "review")
    assert page.count("scan.read(client:") == 1 and page.count("client.markReviewed(") == 1
    again = swift_like(page, "signedInAgain")
    assert "guard shown, online, session == nil else { return }" in again and "await read()" in again
    # (R12) in NeedsLookLife, the page's life the Mac's Needs a look wears too
    assert ".onChange(of: server.signInOver == nil) { _, clear in\n                guard clear, visible else { return }\n" \
           "                Task { await model.signedInAgain() }" in screen
    assert "struct NeedsLookLife: ViewModifier {" in screen and screen.count(".modifier(NeedsLookLife(model: model))") == 1


def test_every_write_asks_the_count_again_and_tells_the_page():
    edit = app_file("Edit", "EditAlbumModel.swift")
    told = swift_like(edit, "told")
    assert "navigation?.managed()" in told
    assert "queue?.heard(NeedsLook.FolderChange(from: from, album: deleted ? nil : album, deleted: deleted))" in told
    # an apply, Tags' apply, the cover alone, a Get (wrote), a delete (gone), a mark (mark) - each tells
    assert "told(from: before.path)" in swift_like(edit, "wrote")
    assert "told(from: before.path, deleted: true)" in swift_like(edit, "gone")
    assert "told(from: from)" in swift_like(edit, "mark")
    assert edit.count("wrote(before: before)") >= 5
    # the artist tools' Save and Move
    artist = app_file("Artist", "ArtistToolModels.swift")
    assert artist.count("navigation?.managed()") == 3
    # a note, then the count; nothing past a sign-out
    page = app_file("Manage", "NeedsLookModel.swift")
    review = swift_like(page, "review")
    assert "_ = try await client.markReviewed(path: path)" in review and "count?.changed()" in review
    assert review.index("markReviewed") < review.index("count?.changed()")
    assert page.count("samePerson") >= 6


def test_a_mark_is_judged_as_every_write_is():
    # (slice 6's review) only a 4xx is a refusal; any other end may have been written - said so, read again, and the
    # session and the count told what the read shows
    mark = swift_like(app_file("Edit", "EditAlbumModel.swift"), "mark")
    assert "guard RetagFlow.outcome(of: error) != .refused else {" in mark
    refused = mark[mark.index("guard RetagFlow.outcome(of: error) != .refused else {"):]
    refused = refused[:refused.index("}") + 1]
    assert "markFailure = EditWords.said(error, failed: failed, admin: admin)" in refused and "return" in refused
    assert "markFailure = EditWords.writeFailure(error, failed: failed, admin: admin)" in mark
    assert "AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()" in mark
    # the read and the telling come after the catch - an answered mark and an unanswered one alike
    catch = mark.index("} catch {")
    assert mark.index("await lookUp()") > catch and mark.index("told(from: from)") > mark.index("await lookUp()")


def test_the_page_says_its_own_failures_and_shows_when_deadwax_is_out_of_reach():
    page = app_file("Manage", "NeedsLookModel.swift")
    # (slice 7's review) READ_FAILED whenever there are no albums to show, and a read ended (answered or failed) the
    # ladder's `loaded`, as the web's: a failed first read is Try again, not the spinner for good
    assert "scan.failure(saying: scan.albums.isEmpty ? NeedsLook.readFailed : NeedsLook.checkFailed)" in page
    assert "NeedsLook.state(problem: scan.answer?.problem, loaded: scan.ended, failed: scan.failed != nil," in page
    screen = app_file("Manage", "NeedsLookScreen.swift")
    assert "ErrorNote(text: model.failure ?? NeedsLook.readFailed)" in screen
    assert "Text(model.failure ?? NeedsLook.checkFailed)" in screen
    assert "scan.failure" not in screen, "never the editor's words"
    assert ".editOutOfReach(!reachability.online && model.scan.loaded)" in screen
    # back in reach with the page up and no editor open on a session: read again
    reach = swift_like(page, "reach")
    assert "guard now, shown, session == nil else { return }" in reach and "await read()" in reach
    # the scan keeps the error, each place saying it its own way; the editor's words stay READ_FAILED's
    scan = app_file("Edit", "LibraryScanModel.swift")
    assert "var failure: String? { failure(saying: EditWords.readFailed) }" in scan
    assert "failed = (error, admin)" in scan


def test_the_editor_steps_through_the_queue_as_the_web_does():
    sheet = app_file("Edit", "EditAlbumSheet.swift")
    # one sheet, each album opened afresh in it with the page's scan
    assert ".task(id: request.queue?.steps ?? 0)" in sheet
    assert "scan: request.queue?.scan" in sheet
    # ‹, where it is, Skip or Next album - each through the editor's gate, typed work asked about first
    # (R12) the bar above the root's foot (EditQueueBar), the system's bottom toolbar gone with the grey
    assert "bottomBar" not in sheet and "EditAlbumRoot(model: model, path: $path, queue: queue)" in sheet
    assert ".disabled(!nav.back || !model.canStep)" in sheet and ".disabled(!nav.on || !model.canStep)" in sheet
    assert "pendingStep = delta" in sheet and "askingDiscard = true" in sheet
    assert "queue.go(by: delta, gate: model.stepGate)" in swift_like(sheet, "take")
    # Discard's step: the gate as it is at that moment, not as it was when the step was asked
    assert "if let model { request.queue?.go(by: delta, gate: model.stepGate) }" in sheet
    # a delete in queue mode leaves the sheet up
    assert "if request.queue != nil {\n                path.removeAll()\n            } else {\n                dismiss()" in sheet
    page = app_file("Manage", "NeedsLookModel.swift")
    # an album gone when stepped to ends the session, the scan listing paths code unit by code unit
    assert "carry(run.step(by: delta, gate: gate, present: NeedsLook.lists(scan.albums), live: liveChips))" in page
    assert "navigation.albumEdit?.queue === self" in page


def test_the_step_gate_waits_for_everything_done_to_the_album():
    # (slice 6's review) no step while a write or a mark - or what follows it, the read then the page told - is under
    # way, while the scan is read, while Release or Tags waits for a read, or while a delete waits to be found gone
    edit = app_file("Edit", "EditAlbumModel.swift")
    gate = edit[edit.index("var stepGate: NeedsLook.StepGate {"):]
    gate = gate[:gate.index("\n    }\n")]
    for part in ("online: online", "busy: writing || marking || following > 0", "reading: scan.reading",
                 "needsRead: retag?.flow.needsRead == true || tags?.flow.needsRead == true",
                 "deletePending: unansweredDelete != nil"):
        assert part in gate, part
    assert "var canStep: Bool { stepGate.open }" in edit
    # each write and the mark hold `following` from before they send until their follow-up has told the page
    for name in ("apply", "saveCoverOnly", "applyTags", "get", "delete", "mark"):
        body = swift_like(edit, name)
        assert "following += 1" in body and "defer {" in body and "following -= 1" in body, name
    # watched, so the bar's buttons come back on when it settles
    assert "@ObservationIgnored private var unansweredDelete" not in edit
    assert "private var unansweredDelete: (before: ScanAlbum, all: Bool)?" in edit


def test_the_page_only_carries_out_what_the_run_decides():
    # (slice 6's review) Core's NeedsLook.Run decides every move of the session - begun, stepped, ended once - and the
    # page carries out each After whole: the note sent, the editor closed, the ending read
    page = app_file("Manage", "NeedsLookModel.swift")
    for move in ("run.step(", "run.closed(", "run.facetChosen("):
        for at in [m.start() for m in re.finditer(re.escape(move), page)]:
            assert page[at - 6:at] == "carry(", f"{move} carried out"
    assert "run.begin(NeedsLook.facetAlbums(scan.albums, shown), path: row.album.path, facet: shown," in page
    assert "carry(run.closed(live: liveChips))" in swift_like(page, "editorClosed")
    assert "carry(run.facetChosen(live: liveChips))" in swift_like(page, "choose")
    carry = swift_like(page, "carry")
    assert "let note = after.note" in carry and "let noted = Task { await self.review(note) }" in carry
    assert "if after.close {\n            closeEditor()" in carry
    ending = carry[carry.index("if let ticket = after.ended {"):]
    assert ending.index("await noted.value") < ending.index("await self.read()") < ending.index("self.run.endingRead(ticket)")
    # no state of its own about the session: the Run's
    for word in ("private(set) var session", "heldChips", "private var endings", "private(set) var ending", "private(set) var steps"):
        assert word not in page, word


def test_the_session_ends_where_the_sheet_really_goes():
    # (slice 6's review) never on the sheet's content disappearing - a full-screen cover over it does that too
    sheet = app_file("Edit", "EditAlbumSheet.swift")
    assert "onDisappear" not in sheet[sheet.index("struct EditAlbumSheet"):sheet.index("struct EditPageView")]
    close = swift_like(sheet, "closeSheet")
    assert close.index("request.queue?.editorClosed()") < close.index("dismiss()")
    assert sheet.count("request.queue?.editorClosed()") == 1
    assert "closeSheet()" in swift_like(sheet, "close")
    tabs = app_file("Root", "MainTabs.swift")
    assert ".appSheet(item: $navigation.albumEdit, onDismiss: { navigation.editorDismissed() })" in tabs
    nav = app_file("Shared", "Routes.swift")
    dismissed = swift_like(nav, "editorDismissed")
    assert "guard let was = presentedEdit, albumEdit?.id != was.id else { return }" in dismissed
    assert "was.queue?.editorClosed()" in dismissed
    assert "if let was, was.id != request.id, was.queue !== request.queue { was.queue?.editorClosed() }" \
        in swift_like(nav, "editAlbum")
    # a sign-out: ended after the session has moved on, so nothing is noted for the next person
    reset = swift_like(nav, "reset")
    assert reset.index("session += 1") < reset.index("editor?.queue?.editorClosed()")


def swift_like(text: str, name: str) -> str:
    """The body of `func <name>` in an App file's text (one only) - comments left in."""
    found = list(re.finditer(r"\bfunc\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"func {name} is declared {len(found)} times"
    start = found[0].end()
    depth = 1
    for at in range(start, len(text)):
        if text[at] == "{":
            depth += 1
        elif text[at] == "}":
            depth -= 1
            if depth == 0:
                return text[start:at]
    raise AssertionError(f"func {name} never ends")
