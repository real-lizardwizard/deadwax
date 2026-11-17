"""
The iPhone app's Server settings (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; notes/ios.md "Server settings
on the phone") against the routes it adds - the settings read and their one save (`GET` and `PUT /settings`), MusicBrainz's
saved answers and their Clear (`GET /settings/musicbrainz_cache`, `POST .../clear`) and Connections' two pings (`GET
/search_musicbrainz/ping`, `GET /monitor_slskd/ping`; Navidrome's status the Library's gate reads already) - read from its
own source (ios/DeadwaxKit/Sources/DeadwaxCore: ServerSettings.swift, Routes.swift, EditWaits.swift; ios/App/Manage) and
held to the server's. Re-time saved lyrics asks only the lyrics fetch Get lyrics asks, with `retime`.

- what it SENDS - the batch as SettingUpdate takes it, a revert a null; Re-time's body as LyricsRequest takes it;
- what it READS - the settings as the real route answers them (every field the phone reads, each setting's choices),
  a save's answer the same, a refusal's words; the saved answers' file as the real routes say it; each ping's answer;
- how long it waits - the save by its batch, every store call SQLite's busy timeout and the settings read after; the
  MusicBrainz ping past one request's worst; the rest pinned where the server has no bound of its own;
- who may: the page by Settings and the log, Connections for whoever runs deadwax, Re-time with Edit albums too, as the
  server's routes are (tests/test_logins.py ROUTES) - and the app only carrying out what Core decides.
"""

import asyncio
import inspect
import re
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import lyrics as lyrics_module  # noqa: E402
from src.api import lrclib_endpoint  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.musicbrainz_endpoint import MusicBrainzClient  # noqa: E402
from src.api.slskd_endpoint import SlskdClient  # noqa: E402
from src.config import Config  # noqa: E402
from src.musicbrainz_cache import SavedAnswers  # noqa: E402
from src.routes import library as library_route  # noqa: E402
from src.routes import settings as settings_route  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests.test_ios_artist_manage import musicbrainz_worst  # noqa: E402
from tests.test_ios_contract import CORE, _code, coding_keys, fields, required_fields, swift_function, swift_struct  # noqa: E402
from tests.test_ios_needs_look import app_file, swift_like, timeouts  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402

SETTINGS = (CORE / "ServerSettings.swift").read_text(encoding="utf-8")
APP = CORE.parent.parent.parent / "App"


def settings_function(name: str) -> str:
    return swift_function("ServerSettings.swift", name)


@pytest.fixture
def env(monkeypatch, tmp_path):
    """The real app with logins off and a throwaway store - the one setting saved here put back after, and the saved
    answers' file a fresh one in tmp_path."""
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    monkeypatch.setattr(Config, "COVER_ART_SIZE", Config.COVER_ART_SIZE)
    monkeypatch.setattr(Config, "DB_PATH", str(tmp_path / "config" / "deadwax.db"))
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(tmp_path / "cache"))
    saved = SavedAnswers()
    monkeypatch.setattr(MusicBrainzClient.cache, "disk", saved)
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    yield TestClient(app)  # no `with`, so no lifespan: nothing connects
    asyncio.run(saved.close())


# ---------------------------------------------------------------------------- the routes, and who may

def test_the_routes_are_the_servers_by_method_path_and_permission():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    for name, method, path, permission in (
            ("serverSettings", "GET", "/deadwax/settings", "server"),
            ("saveServerSettings", "PUT", "/deadwax/settings", "server"),
            ("savedAnswers", "GET", "/deadwax/settings/musicbrainz_cache", "server"),
            ("clearSavedAnswers", "POST", "/deadwax/settings/musicbrainz_cache/clear", "server"),
            ("pingMusicBrainz", "GET", "/deadwax/search_musicbrainz/ping", "user"),
            ("pingSlskd", "GET", "/deadwax/monitor_slskd/ping", "user")):
        line = f'public static let {name} = Endpoint(method: "{method}", path: "{path}", query: [])'
        assert line in text, line
        assert ROUTES[(method, path)] == permission, (method, path)
    # Navidrome's status (the third row) and Re-time's route are ones the phone had already
    assert ROUTES[("GET", "/deadwax/navidrome/status")] == "user"
    assert ROUTES[("POST", "/deadwax/library/lyrics/fetch")] == "edit"
    # who sees which part: the page by Settings and the log; Connections for whoever runs deadwax (access.ts seesDetail);
    # Re-time with Edit albums too, the permission of the route it asks for each album; the saved answers with the page
    parts = settings_function("parts")
    assert "let page = access.can(.server)" in parts
    assert ("Parts(page: page, connections: page && access.seesDetail, retime: page && access.can(.edit), "
            "answers: page)") in parts
    # the page is the app's own now: no Safari for Server settings
    managing = _code((CORE / "Managing.swift").read_text(encoding="utf-8"))
    assert "case .edit, .queue, .care, .settings, .log: return true" in managing[managing.index("public var native: Bool {"):]
    # and the Library's Set up Navidrome is the app's own page too: no address of the web app's left for it
    assert "setUpURL" not in (CORE / "NavidromeGate.swift").read_text(encoding="utf-8")


def test_a_save_sends_what_settingupdate_takes_and_a_revert_as_null():
    # the batch: every draft as {key, value}, value null for a revert - the pydantic model's own fields, so nothing the
    # phone sends is dropped without a word (CLAUDE.md)
    update = swift_struct("SettingUpdate")
    assert set(coding_keys(update).values()) == set(settings_route.SettingUpdate.model_fields) == {"key", "value"}
    assert settings_route.SettingUpdate.model_fields["value"].default is None
    # a nil value is ENCODED (null), never left out - encodeIfPresent would drop it, and the server read it as a revert
    # only by its default; said, not assumed
    assert "try fields.encode(value, forKey: .value)" in update and "encodeIfPresent" not in update
    # the route takes a list of them: the phone's one PUT is the batch
    signature = inspect.signature(settings_route.update_settings)
    assert str(signature.parameters["updates"].annotation) in ("list[src.routes.settings.SettingUpdate]",
                                                              "list[SettingUpdate]")
    client = settings_function("saveServerSettings")
    assert "request(Routes.saveServerSettings, json: try Self.json(drafts.updates))" in client
    assert "built.timeout = ServerSettings.saveWait(drafts.count)" in client
    # Re-time: the lyrics fetch's own body, with retime on and replace off
    retime = swift_struct("RetimeBody")
    assert set(coding_keys(retime).values()) == set(library_route.LyricsRequest.model_fields)
    assert "self.replace = false" in retime and "self.retime = true" in retime


# ---------------------------------------------------------------------------- what the phone reads, from real routes

def test_the_settings_are_what_the_phone_reads(env):
    answer = env.get("/deadwax/settings")
    assert answer.status_code == 200, answer.text
    got = answer.json()
    assert set(fields("ServerSettingsAnswer")) <= set(got), set(fields("ServerSettingsAnswer")) - set(got)
    assert {"groups", "organizing"} <= set(got)
    assert set(fields("Organizing")) == set(got["organizing"]) == {"enabled", "blockers"}
    group_reads = set(fields("ServerSettingGroup")) | {"settings"}
    setting_reads = set(fields("ServerSetting")) | {"choices"}
    seen = set()
    for group in got["groups"]:
        assert group_reads <= set(group), (group["id"], group_reads - set(group))
        for setting in group["settings"]:
            seen |= set(setting)
            # what the phone can't do without is in every row (it reads them leniently, but a row without them is
            # one it could only guess at)
            assert required_fields("ServerSetting") <= set(setting), (setting["key"], setting)
    # every field the phone reads is one deadwax sends somewhere - none renamed under it
    assert setting_reads <= seen, setting_reads - seen
    # the groups the phone places by name are the server's ids (tabForGroup, the saved answers, Re-time, Connections)
    ids = [group["id"] for group in got["groups"]]
    for named in ("connections", "logins", "musicbrainz-cache", "lyrics", "organizing"):
        assert named in ids, named
    for name, value in (("savedAnswersGroup", "musicbrainz-cache"), ("lyricsGroup", "lyrics"),
                        ("connectionsGroup", "connections"), ("organizingGroup", "organizing"),
                        ("leadKey", "LYRICS_LEAD_MS"), ("savedAnswersPath", "MUSICBRAINZ_CACHE_PATH")):
        assert f'public static let {name} = "{value}"' in SETTINGS, name
    keys = {setting["key"]: setting for group in got["groups"] for setting in group["settings"]}
    assert "LYRICS_LEAD_MS" in keys and "MUSICBRAINZ_CACHE_PATH" in keys
    # the dropdowns: each with choices, an object of value to words
    for key in ("COUNTRY_IN_FOLDER", "COVER_ART_SIZE", "FETCH_LYRICS", "AUTO_RETRY_PEER"):
        choices = keys[key]["choices"]
        assert isinstance(choices, dict) and choices and all(isinstance(v, str) for v in choices.values()), key
    # a secret never comes back: the phone's field is empty, its placeholder says whether one is set
    secrets = [setting for setting in keys.values() if setting["secret"]]
    assert secrets and all(setting["value"] in (None, "", "set") for setting in secrets), secrets


def test_a_save_answers_the_settings_and_a_refusal_says_each_setting(env):
    current = {s["key"]: s for g in env.get("/deadwax/settings").json()["groups"] for s in g["settings"]}
    choice = next(value for value in current["COVER_ART_SIZE"]["choices"] if value != current["COVER_ART_SIZE"]["value"])
    saved = env.put("/deadwax/settings", json=[{"key": "COVER_ART_SIZE", "value": choice}])
    assert saved.status_code == 200, saved.text
    after = {s["key"]: s for g in saved.json()["groups"] for s in g["settings"]}
    # the save answers the settings themselves, as the GET does: SettingsFlow.saved takes it as the new answer
    assert after["COVER_ART_SIZE"]["value"] == choice and after["COVER_ART_SIZE"]["overridden"] is True
    assert set(saved.json()) == set(env.get("/deadwax/settings").json())
    # a revert is a null, and brings the environment's back
    reverted = env.put("/deadwax/settings", json=[{"key": "COVER_ART_SIZE", "value": None}])
    assert reverted.status_code == 200
    back = {s["key"]: s for g in reverted.json()["groups"] for s in g["settings"]}["COVER_ART_SIZE"]
    assert back["overridden"] is False
    # refused whole, a 400 naming each setting in deadwax's words - the bar says them as they came
    refused = env.put("/deadwax/settings", json=[{"key": "COVER_ART_SIZE", "value": "huge"},
                                                 {"key": "NOT_A_SETTING", "value": "x"}])
    assert refused.status_code == 400
    detail = refused.json()["detail"]
    assert detail.startswith("COVER_ART_SIZE: ") and "; NOT_A_SETTING: " in detail
    failure = settings_function("saveFailure")
    assert "if answer.status == 400, let detail = answer.detail, !detail.isEmpty { return detail }" in failure


def test_the_saved_answers_are_what_the_phone_reads(env):
    stats = env.get("/deadwax/settings/musicbrainz_cache")
    assert stats.status_code == 200, stats.text
    reads = set(fields("SavedAnswersStats"))
    assert reads <= set(stats.json()), reads - set(stats.json())
    cleared = env.post("/deadwax/settings/musicbrainz_cache/clear")
    assert cleared.status_code == 200, cleared.text
    assert reads <= set(cleared.json()) and cleared.json()["answers"] == 0
    # the line's words read MUSICBRAINZ_CACHE_MB by name, and the group carries both settings
    assert "Saving is off (MUSICBRAINZ_CACHE_MB is 0)" in SETTINGS
    [group] = [g for g in env.get("/deadwax/settings").json()["groups"] if g["id"] == "musicbrainz-cache"]
    assert {"MUSICBRAINZ_CACHE_PATH", "MUSICBRAINZ_CACHE_MB"} <= {s["key"] for s in group["settings"]}


def test_each_pings_answer_is_what_the_phone_reads():
    # {status, code, error}: "ok", or failed with the short name the words key on and the sentence under it
    reads = set(fields("PingAnswer"))
    assert reads == {"status", "code", "error"}
    assert required_fields("PingAnswer") == {"status"}
    for source in (inspect.getsource(MusicBrainzClient.ping), inspect.getsource(SlskdClient.ping)):
        for literal in re.findall(r"return \{([^{}]*)\}", source):
            assert set(re.findall(r'"(\w+)":', literal)) <= reads, literal
    assert '"code": "UNKNOWN_ERROR"' in inspect.getsource(MusicBrainzClient.ping)


# ---------------------------------------------------------------------------- how long the phone waits

def test_each_wait_is_past_the_servers_own_worst_case_or_pinned():
    given = timeouts()
    # the save: each setting's row written (a set or a clear, one store call each) and the overrides read back (one
    # more), each its own SQLite connection that may wait out the busy timeout - then the settings read as the GET is
    handler = inspect.getsource(settings_route.update_settings)
    assert handler.count("await store.") == 2, "set_setting or clear_setting, one per update"
    assert re.search(r"for update in updates:\n\s+if update\.value is None:\n\s+await store\.clear_setting\(update\.key\)"
                     r"\n\s+else:\n\s+await store\.set_setting\(update\.key, update\.value\)", handler)
    assert handler.count("store.stored_settings()") == 1
    assert "return _as_seen_by(await settings(), user)" in handler
    busy = re.search(r"sqlite3\.connect\(self\.path, timeout=(\d+)\)", inspect.getsource(JobStore._connect))
    assert busy and int(busy.group(1)) == 10
    assert "public static let storeBusy: Double = 10" in SETTINGS
    assert ("EditWaits.wait(settingsRead + storeBusy * Double(count + 1), floor: "
            "Routes.timeouts[Routes.saveServerSettings])") in settings_function("saveWait")
    assert "Routes.timeouts[Routes.serverSettings] ?? 30" in SETTINGS
    # no bound of the server's own on the read (each path stat'ed, slskd's folder probed, PROBE_VISITS at most) - the
    # value itself is pinned; a save never less than one setting's (30 + 2 x 10)
    read = inspect.getsource(settings_route.settings)
    assert "wait_for" not in read and "httpx" not in read
    assert given["serverSettings"] == 30
    assert given["saveServerSettings"] == 60 >= given["serverSettings"] + 2 * int(busy.group(1))
    # the saved answers: on their own thread, a stat and a clear of one SQLite file - no bound of the server's own,
    # pinned (a Clear that never answers may have cleared: said, and read again)
    stats = inspect.getsource(settings_route.musicbrainz_cache_stats)
    clear = inspect.getsource(settings_route.clear_musicbrainz_cache)
    assert "wait_for" not in stats + clear
    assert (given["savedAnswers"], given["clearSavedAnswers"]) == (30, 120)
    assert "if answers.clearUnanswered(" in swift_like(app_file("Manage", "ServerSettingsModel.swift"), "clearAnswers")
    # MusicBrainz's ping: one request with its retries, never from the saved answers - past its worst
    assert 'self.request_with_retries("release-group/' in inspect.getsource(MusicBrainzClient.ping)
    assert given["pingMusicBrainz"] == 120 > musicbrainz_worst() == 111.5
    # slskd's: slskd_api's own request, no bound of deadwax's - pinned; a row that never answers says "Couldn't check"
    ping = inspect.getsource(SlskdClient.ping)
    assert "asyncio.to_thread(client.application.state)" in ping and "wait_for" not in ping
    assert given["pingSlskd"] == 30
    # Re-time: each album's lyrics fetch with retime - only the tracks WITH a lyrics file (the scan's lyrics_count), two
    # at a time, each asked of LRCLIB by `candidates`: under each name, the exact lookup then the search - as many
    # requests at worst as Get lyrics', so the same figures (test_ios_edit_parts_contract.py holds them)
    plan = inspect.getsource(lyrics_module.plan_lyrics)
    assert 'if not existing:\n                skip = "absent"' in plan
    fetch = inspect.getsource(lyrics_module.fetch_album_lyrics)
    assert "if retime:" in fetch and "async with semaphore:" in fetch
    assert "client.candidates(lookup)" in inspect.getsource(lyrics_module._find_source)
    candidates = inspect.getsource(lrclib_endpoint.LrclibClient.candidates)
    names = candidates[candidates.index('for artist in lookup["artists"]:'):]
    assert names.count("await self._get(") == 2
    retime = swift_function("EditWaits.swift", "retime")
    assert "let asked = max(1, album.lyricsCount)" in retime
    assert "let track = lrclibNames * lrclibRequestsPerName * (lrclibRequest + lrclibBusy)" in retime
    assert "floor: Routes.timeouts[Routes.lyricsFetch]" in retime


# ---------------------------------------------------------------------------- the app

def test_the_app_only_carries_out_what_core_decides():
    model = app_file("Manage", "ServerSettingsModel.swift")
    # nothing read while the sign-in is over the app; SettingsFlow says when a page reads
    read = swift_like(model, "readIfNeeded")
    assert "server.signInOver == nil" in read
    assert "flow.readsNow(shown: visible, online: reachability.online, allowed: parts.page, again: again)" in read
    # every read's ticket taken before its Task: a second ask in the same turn sends nothing, and a Save after calls it
    # off, never a GET out during the save
    for name, began in (("read", "let ticket = flow.readBegan()"), ("readAnswers", "let ticket = answers.readBegan(key: key)")):
        asked = swift_like(model, name)
        assert asked.index(began) < asked.index("Task {"), name
    assert "Task { await read" not in model and "Task { await readAnswers" not in model
    assert "if flow.readLanded(ticket, found) { announce(flow.barText) }" in model
    # Discard reads again (a look at a save that never answered, ended)
    assert "flow.discard()\n        readIfNeeded(again: false)" in swift_like(model, "discard")
    # a ping called off settles its row (back to its last answer), never left on Checking…
    asking = swift_like(model, "ask")
    assert "checks.dropped(ticket, service)" in asking and "checks.settled(ticket, service, check)" in asking
    # Re-time's library read is held for the read alone; each album has its own hold
    start = swift_like(model, "startRetime")
    assert "defer { hold.end() }" not in start
    assert start.index("hold.end()") < start.index("await driveRetime(mine)")
    # the save: Core's batch, held through the background; refused (a 4xx) said in Core's words; never answered (or a
    # 5xx) may have landed - said, and the settings read again
    save = swift_like(model, "save")
    assert "let batch = flow.save(online: reachability.online, allowed: parts.page)" in save
    assert 'BackgroundHold(named: "Server settings: save")' in save
    assert "try await client.saveServerSettings(batch)" in save
    assert "RetagFlow.outcome(of: error) == .refused" in save
    assert "flow.refused(ServerSettings.saveFailure(error, admin: admin))" in save
    assert "flow.unanswered(ServerSettings.unansweredWords(error, admin: admin))" in save
    assert "announce(EditWords.mayHaveFinished)" in save and "readIfNeeded(again: false)" in save
    assert "APIFailure.isCancellation(error)" in save and "flow.saveDropped()" in save
    # after a save: the Library's gate asks Navidrome again for one of its settings (the web's onServerSettingsSaved),
    # Connections are checked again for one of theirs
    saved = swift_like(model, "saved")
    assert "if ServerSettings.asksNavidromeAgain(keys) {\n            Task { await library.checkNavidrome() }" in saved
    assert "ServerSettings.checksConnectionsAgain(keys, flow.answer)" in saved
    # Re-time: Core's run, one album at a time, each held; the session ending or deadwax out of reach stops it after
    # the album out
    drive = swift_like(model, "driveRetime")
    assert "if server.signInOver != nil || client == nil { retime.sessionEnded() }" in drive
    assert "switch retime.next(allowed: parts.retime, online: reachability.online) {" in drive
    assert "step = RetimeRun.step(failure: error)" in drive and "retime.finished(step)" in drive
    assert "BackgroundHold(named:" in drive
    assert "retime.suspended()" in swift_like(model, "scene")
    reach = swift_like(model, "reachChanged")
    assert "flow.outOfReach()" in reach and "retime.outOfReach()" in reach
    # the lead drafted lets go of how a run ended at the old one
    assert "if leadUnsaved { retime.leadDrafted() }" in swift_like(model, "edit")
    # another person: nothing of the last one's kept, the drafts with it
    reset = swift_like(model, "reset")
    for line in ("generation += 1", "flow = SettingsFlow()", "answers = SavedAnswers()", "retime = RetimeRun()",
                 "checks = ConnectionChecks()"):
        assert line in reset, line
    app = app_file("DeadwaxApp.swift")
    assert "serverSettings.reset()" in app and ".environment(serverSettings)" in app
    assert "reachability.whenChanged { [weak serverSettings] in serverSettings?.reachChanged() }" in app
    root = app_file("Root", "RootView.swift")
    assert "serverSettings.scene(phase)" in root and "if over == nil { serverSettings.sessionBack() }" in root
    for polling in ("Task.sleep", "Timer.publish", "Timer.scheduled", "TimelineView"):
        assert polling not in model, f"nothing polled: {polling}"


def test_the_screen_stays_on_only_through_screen_awake():
    # Library care's runs and Re-time each say whether they want it; one place sets the idle timer
    awake = app_file("Manage", "ScreenAwake.swift")
    assert "UIApplication.shared.isIdleTimerDisabled = !wanted.isEmpty" in awake
    for path in APP.rglob("*.swift"):
        if path.name != "ScreenAwake.swift":
            assert "isIdleTimerDisabled" not in path.read_text(encoding="utf-8"), path.name
    care = app_file("Manage", "CareRunModel.swift")
    assert "ScreenAwake.keep(runs.keepsScreenOn(visible: visible), for: .libraryCare)" in care
    model = app_file("Manage", "ServerSettingsModel.swift")
    assert "ScreenAwake.keep(retime.keepsScreenOn(visible: retimeShown > 0 && active), for: .retime)" in model


def test_the_pages_draw_as_the_spec_says():
    screen = app_file("Manage", "ServerSettingsScreen.swift")
    group = app_file("Manage", "ServerSettingsGroupScreen.swift")
    # Connections first on the root, then the verdict, then the tabs as sections of group rows
    listing = screen[screen.index("private func list("):]
    assert (listing.index("ConnectionsSection()") < listing.index("OrganizingVerdictView(")
            < listing.index("ForEach(ServerSettings.tabs"))
    assert "NavigationLink(value: AppRoute.serverSettingsGroup(group.id))" in listing
    assert "GroupRow(label: group.label, mark: marks[group.id])" in listing
    # a row's control: a menu Picker for choices, a SecureField for a secret, the URL keyboard for an address, no
    # autocorrection or capitals - and a locked one says so
    assert ".pickerStyle(.menu)" in group
    assert "SecureField(setting.key, text: value, prompt: Text(row.placeholder))" in group
    assert ".keyboardType(ServerSettings.isAddress(setting.key) ? .URL : .default)" in group
    assert ".textInputAutocapitalization(.never)" in group and ".autocorrectionDisabled()" in group
    assert "Text(ServerSettings.locked)" in group
    # the saved answers' Clear asks first; Re-time and the saved answers on their groups only
    assert ".confirmationDialog(SavedAnswers.clearQuestion, isPresented: $asking, titleVisibility: .visible)" in group
    assert "if group.id == ServerSettings.lyricsGroup {\n                RetimeSection()" in group
    assert "if group.id == ServerSettings.savedAnswersGroup && parts.answers {" in group
    # every page: told to the model, the save bar at its foot, the amber line out of reach - its frame on a ZStack
    # that stays as the spinner gives way (on a Group it went to each branch: hidden and shown again, read twice)
    assert screen.count(".serverSettingsPage(") == 1 and group.count(".serverSettingsPage(") == 1
    for page in (screen, group):
        body = page[page.index("    var body: some View {"):]
        assert body.index("ZStack {") < body.index("if !parts.page {") and "        Group {" not in body[:200]
    frame = screen[screen.index("private struct ServerSettingsPageFrame"):]
    assert ".safeAreaInset(edge: .bottom, spacing: 0)" in frame and "SaveBar()" in frame
    assert ".editOutOfReach(!reachability.online && settings.flow.answer != nil)" in frame
    assert ".onAppear { settings.shows(page) }" in frame and ".onDisappear { settings.hides(page) }" in frame
    # the bar: a look at a save that never answered whose read failed offers Try again; the list doesn't say it twice
    bar = screen[screen.index("private struct SaveBar"):]
    assert "if flow.checkStalled {\n            Button(ServerSettings.tryAgain) {\n                settings.retry()" in bar
    assert "!settings.flow.checkStalled" in screen[screen.index("struct ServerSettingsRereadFailure"):]
    # VoiceOver reads a setting's name once, from its control: the section's header is hidden from it
    section = group[group.index("private struct SettingSection"):]
    assert ".textSelection(.enabled)\n                .accessibilityHidden(true)" in section
    for control in ('.accessibilityLabel("\\(setting.key), \\(ServerSettings.locked)")', ".accessibilityLabel(setting.key)"):
        assert control in section, control
    # Set up Navidrome: the Connections group page in a sheet, never closed during a save
    sheet = group[group.index("struct SetUpNavidromeSheet"):]
    assert "ServerSettingsGroupScreen(id: ServerSettings.connectionsGroup)" in sheet
    assert ".interactiveDismissDisabled(settings.flow.saving)" in sheet and ".disabled(settings.flow.saving)" in sheet
    # held and drawn by LibraryView above the gate's switch - deadwax going out of reach opens the gate, and must not
    # take the sheet - and put away only once Navidrome answers (a check deadwax answered, in reach), never mid-save
    library = app_file("Library", "LibraryView.swift")
    gate = library[library.index("struct NavidromeGateView"):]
    assert "SetUpNavidromeSheet()" not in gate and ".sheet(" not in gate[:gate.index("private extension View")]
    assert "openURL" not in gate[:gate.index("private extension View")]
    assert "NavidromeGateView(closed: closed) { settingUp = true }" in library
    view = library[library.index("struct LibraryView"):library.index("struct NavidromeGateView")]
    body = view[view.index("    var body: some View {"):]
    assert body.index("ZStack { root }") < body.index(".sheet(isPresented: $settingUp) {\n                SetUpNavidromeSheet()")
    assert "return !checked.offline && checked.status.ok" in view
    assert "guard NavidromeGate.consulted(reachability.reach), let checked = library.navidrome else { return false }" in view
    assert "guard settingUp, navidromeAnswers, !serverSettings.flow.saving else { return }" in view
    assert ".onChange(of: navidromeAnswers) { _, _ in setUpDone() }" in body
    assert ".onChange(of: serverSettings.flow.saving) { _, _ in setUpDone() }" in body
    assert "settingUp = false" in body[body.index(".onChange(of: server.person)"):]
    # the routes: the root from Manage, a group by its id
    routes = app_file("Shared", "Routes.swift")
    assert "case .serverSettings: ServerSettingsScreen()" in routes
    assert "case .serverSettingsGroup(let id): ServerSettingsGroupScreen(id: id)" in routes
    assert "NavigationLink(value: AppRoute.serverSettings)" in app_file("You", "ManageSection.swift")
