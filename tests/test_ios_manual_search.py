"""
The iPhone and Mac app's Search Soulseek (manual search, slice A1 - notes/ios.md "Manual search, slice A1"): the
first row of Requests opens a sheet of two fields, Artist and Album; Search pushes Choose a source - the very page an
album's Get opens - over a manual question; a card's Get enqueues it, filed by its own tags (server 2.1.37, 2.1.38).

Two halves, as the app's other source tests have them. The app's Swift read as text: the Sources sheet split into a
page (SourcesPage) the album's Get keeps in a stack of its own, exactly as before, and the manual search pushes; the
row, the sheet and Return in its fields. And the app's question and Get through the real routes, with the very keys
GetRelease's CodingKeys send (DeadwaxKit's ManualSearchTests holds the encoding itself): a `manual` the server didn't
declare would be dropped without a word, and the question scored as a trackless Get.
"""

import asyncio
import re

import pytest
from fastapi.testclient import TestClient

from src.api.app import start
from src.config import Config
from src.store import JobStore
from tests.test_ios_contract import sent_fields
from tests.test_ios_mac import _body, app_sources, reader
from tests.test_manual_search import SHARES

FIND = "/deadwax/download/find_candidates"
ENQUEUE = "/deadwax/download/enqueue"
JOBS = "/deadwax/download/jobs"

#? GetRelease.manual(artist:album:) as encoded: the words, every pressing's field null or empty, no pressing's four
#? (disambiguation, media_format, country, catalog_number - sent only for a pressing) and `manual` - ManualSearchTests'
#? aManualQuestionIsTheWordsTrimmedWithTheFlagAndNothingElse holds the same keys
RELEASE = {"artist": "Radiohead", "album_artist": "Radiohead", "artist_mbids": [], "album": "OK Computer", "year": None,
           "original_year": None, "release_mbid": None, "edition_tags": [], "tracks": [], "release_group_mbid": None,
           "manual": True}
PRESSING_ONLY = {"disambiguation", "media_format", "country", "catalog_number"}
#? FindCandidatesBody: the release flat, with the Format and an edited query (none)
QUESTION = {**RELEASE, "format_preference": "prefer_lossless", "query_override": ""}


def test_the_bodies_here_are_the_apps():
    assert set(RELEASE) == sent_fields("GetRelease") - PRESSING_ONLY
    assert set(QUESTION) - set(RELEASE) == sent_fields("FindCandidatesBody")


# ---------------------------------------------------------------------------- the app's Swift

def _app():
    """The app's sources with their comments blanked (the literals kept: some of what's held is words)."""
    return {name: reader.views(text)[0] for name, text in app_sources().items()}


def test_the_sources_sheet_is_the_page_in_a_stack_of_its_own():
    """The album page's Get is as it was: SourcesSheet is SourcesPage in a NavigationStack with its Cancel; the manual
    search pushes the same page, without a stack or a Cancel of its own."""
    app = _app()
    sheet = app["Get/SourcesSheet.swift"]
    wrapper = _body(sheet, "struct SourcesSheet: View {")
    assert re.search(r"NavigationStack \{\s*SourcesPage\(request: request, pushed: false, onQueued: onQueued\)\s*\}",
                     wrapper), wrapper
    page = _body(sheet, "struct SourcesPage: View {")
    assert "NavigationStack" not in page, "the page is pushed by the manual search: no stack of its own"
    assert "let pushed: Bool" in page
    # the Cancel only on a sheet of its own - a pushed page has Back
    cancel = page.index("placement: .cancellationAction")
    assert re.search(r"if !pushed \{\s*ToolbarItem\($", page[:cancel]), page[cancel - 200:cancel]
    # who builds which: the album's Get the sheet, the manual search the page pushed - nobody else either
    builds = {name: (code.count("SourcesSheet("), code.count("SourcesPage(")) for name, code in app.items()
              if "SourcesSheet(" in code or "SourcesPage(" in code}
    #? (the redesign, R8) the Mac's Requests searches from its toolbar: Choose a source as a sheet of its own, as the album's
    #? Get opens it
    assert builds == {"Get/SourcesSheet.swift": (0, 1), "Search/GroupView.swift": (1, 0),
                      "Get/ManualSearchSheet.swift": (0, 1), "Mac/Requests/MacRequestsPage.swift": (1, 0)}, builds
    assert "SourcesSheet(request: request) {" in app["Search/GroupView.swift"]
    assert "SourcesPage(request: results, pushed: true) {" in app["Get/ManualSearchSheet.swift"]


def test_a_manual_search_gets_nothing_from_a_server_that_would_file_it_as_a_pressing():
    page = _body(_app()["Get/SourcesSheet.swift"], "struct SourcesPage: View {")
    get = _body(page, "private func get(_ candidate: Candidate, release: GetRelease, shown: [Candidate]) -> Bool {")
    assert "guard online, !ManualSearch.needsNewer(release, model.search?.answer), model.download() else { return false }" in get
    assert "let gets = online && !ManualSearch.needsNewer(release, answer)" in page
    # and says why, where the page says why nothing was picked
    assert "model.notPicked ?? tooOld(search)" in page
    assert "ManualSearch.tooOldLine(search.release, search.answer, runs: server.access.seesDetail)" in page
    # no Complete albums only for a manual search
    assert "GetSettings.chips(floor, filters, manual: request.release.manual)" in page


def test_requests_opens_search_soulseek_from_its_first_row():
    requests = _app()["Requests/RequestsScreen.swift"]
    # the first thing drawn - above every heading, above an empty state too - and only with Get albums
    content = _body(requests, "@ViewBuilder private func content(_ board: RequestsView) -> some View {")
    assert re.match(r"[^{]*\{\s*if server\.access\.can\(\.request\) \{\s*Section \{\s*manualSearch\s*\.id\(Self\.searchRow\)"
                    r"\s*\}\s*\}\s*if !reachability\.online \{", content), content[:400]
    row = _body(requests, "private var manualSearch: some View {")
    assert 'Label(ManualSearch.row, systemImage: "plus.magnifyingglass")' in row
    assert ".disabled(!reachability.online)" in row and "searching = true" in row
    # its sheet, marked as a sheet for the Mac's menus
    assert re.search(r"\.appSheet\(isPresented: \$searching\) \{\s*ManualSearchSheet \{ searching = false \}\s*\.macSheet\(\)\s*\}",
                     requests)
    # the scroll-to-top goes to it while it's drawn
    top = _body(requests, "private func topRow(_ board: RequestsView) -> String {")
    assert top.split("\n", 1)[1].lstrip().startswith("if server.access.can(.request) { return Self.searchRow }")
    # a Done manual download says it was filed by its own tags
    assert "filed: ManualSearch.doneLine(row, edits: server.access.can(.edit))" in requests


def test_return_in_search_soulseek_moves_on_or_searches_and_nothing_else():
    sheet = _app()["Get/ManualSearchSheet.swift"]
    assert re.findall(r"\.onSubmit\b[^\n]*", sheet) == [".onSubmit { focused = .album }", ".onSubmit { search() }"]
    artist = sheet[sheet.index("TextField(ManualSearch.artistField"):sheet.index("TextField(ManualSearch.albumField")]
    assert ".onSubmit { focused = .album }" in artist and ".submitLabel(.next)" in artist
    album = sheet[sheet.index("TextField(ManualSearch.albumField"):]
    assert album.index(".onSubmit { search() }") < album.index("Text(ManualSearch.footer)") and ".submitLabel(.search)" in album
    # Search is the words as typed, a new search each time - the Get is a card's, never the form's
    search = _body(sheet, "private func search() {")
    assert search.split("\n", 1)[1].lstrip().startswith("guard searchable, !showing else { return }")
    assert "GetRelease.manual(artist: artist, album: album)" in search and "search: SourcesSearch()" in search
    assert "download" not in search and "onQueued" not in search
    # the search on the results goes with them: Back (the page's own onDisappear, once the pop is done), Cancel, a
    # swipe, the sheet gone - and never as a back-swipe starts (slice A1's review: one let go and cancelled would leave
    # the results up with their search shut)
    assert "onChange(of: showing)" not in sheet
    assert sheet.count("results?.search.close()") == 4, "the sheet going, Cancel, the sheet gone and a new Search"
    assert ".onDisappear { model.close() }" in _body(_app()["Get/SourcesSheet.swift"], "struct SourcesPage: View {")
    assert ".background(SheetGoing { results?.search.close() })" in sheet
    assert ".onDisappear { results?.search.close() }" in sheet


# ---------------------------------------------------------------------------- the routes, as the app asks them

class Slskd:
    """slskd answering every search with the same folders, taking every enqueue, with nothing yet downloading."""

    def __init__(self, responses=()):
        self.responses = list(responses)

    async def search_all(self, queries, **kwargs):
        return list(self.responses)

    async def enqueue(self, username, files):
        return True, None

    async def get_downloads(self, usernames=()):
        return []


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


def _client(store):
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd(SHARES)
    return TestClient(app)  # no `with`: no lifespan, so nothing connects


def test_the_apps_manual_question_is_answered_as_a_manual_search(store):
    answer = _client(store).post(FIND, json=QUESTION)
    assert answer.status_code == 200
    body = answer.json()
    # the echo the app gets by (ManualSearch.needsNewer): without it, every Get is off
    assert body["manual"] is True
    ranked = body["candidates"]
    assert ranked and all(list(card["signals"])[0] == "name_match" for card in ranked)
    first = ranked[0]
    assert first["signals"]["name_match"] == 1.0
    # nothing to judge the files against: no tracks, no lengths, so Tracks reads "N files" (Sources.tracksText)
    assert all(first["signals"][name] is None for name in ("title_match", "track_count", "duration_match"))
    assert (first["expected_tracks"], first["missing_count"], first["audio_expected"]) == (0, 0, 0)
    # nothing asked of the store: no release to be held or downloading
    assert (body["held"], body["downloading"], body["downloading_part"], body["other_pressings"]) == (None, None, None, [])


def test_a_blank_field_is_refused_in_the_apps_words(store):
    for blank in ({"artist": "  "}, {"album": ""}):
        answer = _client(store).post(FIND, json={**QUESTION, **blank})
        assert answer.status_code == 400 and answer.json()["detail"] == "Type an artist and an album."


def test_the_apps_manual_get_is_marked_in_requests(store, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    client = _client(store)
    card = client.post(FIND, json=QUESTION).json()["candidates"][0]
    files = [{"filename": f["filename"], "size": f["size"]} for f in card["files"]]
    # EnqueueBody: the folder, the release (the flag inside it, where EnqueueRelease declares it), no runners-up
    asked = client.post(ENQUEUE, json={"username": card["username"], "directory": card["directory"], "files": files,
                                       "release": RELEASE, "alternatives": [], "quality": None})
    assert asked.status_code == 200, asked.text
    job = asyncio.run(store.get_job(asked.json()["job_id"]))
    assert job["release"]["manual"] is True
    rows = client.get(JOBS).json()["jobs"]
    assert len(rows) == 1
    # the row the app marks "· manual search" (Requests.jobRow), under the typed words
    assert rows[0]["manual"] is True
    assert (rows[0]["artist"], rows[0]["album"]) == ("Radiohead", "OK Computer")
