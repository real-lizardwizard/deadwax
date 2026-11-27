"""
The iPhone and Mac app's radio, slice A3 (notes/ios.md "Last.fm, slice A3"; deadwax-plans/lastfm.md 3.5-3.8): Start
Radio in every one-song ••• and Now Playing's, the song played in the tap and deadwax asked after; Autoplay, this
device's setting, off by default - the Queue's chip after Repeat on both, the Mac's tick after Repeat's submenu; the
rows Autoplay gave under their own heading; Shuffle dimmed while the queue has a station; the top-up watched outside
every view, reading only what it needs; Autoplay never starting the music.

Read from the Swift source, as the other ios tests read theirs. Core's rules (Station, withStation, MacMenu's tick,
LastfmRadio, LastfmWords) are the Swift tests under DeadwaxKit (StationTests, WithStationTests, MacMenuTests,
LastfmDecodeTests, DeviceWordsTests).
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"

STATION = "Models/PlayerModel+Station.swift"
PLAYER = "Models/PlayerModel.swift"
QUEUE_MENU = "Player/QueueMenu.swift"
NOW_MENU = "Player/NowPlayingMenu.swift"
QUEUE = "UpNext/UpNextScreen.swift"
COMMANDS = "Shared/MacCommands.swift"
#? every App file the slice draws or speaks in
SPOKEN = (STATION, QUEUE_MENU, NOW_MENU, QUEUE, COMMANDS, "Player/NowPlayingView.swift", "Player/PlayerBar.swift")


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_lastfm_a3_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def uncommented(text: str) -> str:
    """Swift with its comments blanked and its literals kept (the words a file says)."""
    return re.sub(r"(?m)//.*$", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


def code(name: str) -> str:
    """A file as code, its comments gone and its literals kept, its spacing made one."""
    return flat(uncommented(source(name)))


def body(text: str, opening: str) -> str:
    """What `opening`'s braces hold, with `opening`: `opening` ends at, or just before, its `{`."""
    start = text.index(opening)
    brace = text.index("{", start + len(opening) - 1)
    depth = 0
    for end in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[end], 0)
        if depth == 0:
            return text[start:end + 1]
    raise AssertionError(f"{opening}: never closed")


def inner(text: str, opening: str) -> str:
    """Only what the braces hold, trimmed."""
    whole = body(text, opening)
    return whole[whole.index("{", len(opening) - 1) + 1:-1].strip()


# ----------------------------------------------------------------------------- Start Radio


def test_start_radio_plays_in_the_tap_and_asks_after():
    station = code(STATION)
    start = inner(station, "func startRadio(_ song: Song) {")
    # the existing play call first - a new queue, the song playing at once - and only then the station and its ask
    assert start == "play(playlist: [song], at: 0) stations.radioStarted(song)"
    assert "await" not in start and "Task" not in start
    # the play call is the playlist's tap's own: the songs level (PlaylistPlay.plan), nothing awaited in it either
    player = code(PLAYER)
    play = body(player, "func play(playlist songs: [Song], at index: Int?, shuffle: Bool = false)")
    assert "PlaylistPlay.plan(" in play and "await" not in play and "Task" not in play
    # the station made of the queue the play started, its seed the song tapped; deadwax asked at once
    started = inner(station, "func radioStarted(_ song: Song) {")
    assert started == ("drop() guard let player, let made = Station.radio(player.queue), made.seed.id == song.id else "
                       "{ return } station = made ask()")
    # every Start Radio is this call alone, in the tap
    for name, seed in ((QUEUE_MENU, "seed"), (NOW_MENU, "song")):
        button = inner(code(name), "Button(LastfmWords.startRadio, systemImage: LastfmWords.startRadioSymbol) {")
        assert button == f"player.startRadio({seed})", name
    calls = [path.relative_to(APP).as_posix() for path in sorted(APP.rglob("*.swift"))
             if ".startRadio(" in uncommented(path.read_text(encoding="utf-8"))]
    assert calls == [NOW_MENU, QUEUE_MENU], calls


def test_start_radio_is_in_every_one_song_menu_while_lastfm_is_on_and_deadwax_reached():
    menu = code(QUEUE_MENU)
    # one song's •••: never an album's own (queued as an album) nor a playlist's whole
    assert ("var radioSong: Song? { pick.queuedAs == nil && !wholeList && pick.tracks.count == 1 ? pick.tracks.first : "
            "nil }") in menu
    assert "var request = QueueMenuRequest(pick: pick, album: nil, playlist: answer) request.wholeList = true" in menu
    items = body(menu, "struct QueueMenuItems: View {")
    assert ("if let seed = request.radioSong, reachability.online, !request.gone, server.access.lastfm == .on { "
            "Button(LastfmWords.startRadio, systemImage: LastfmWords.startRadioSymbol)") in items
    # after Add to a playlist…, in the song's own section
    assert items.index("PlaylistWords.addToAPlaylistRow") < items.index("LastfmWords.startRadio")
    # a song's right-click on the Mac draws these very items, and nothing of its own
    for name in ("Album/TrackRow.swift", "Library/SongsScreen.swift", "Artist/TopSongsSection.swift",
                 "Playlists/PlaylistView.swift", "Mac/Album/MacAlbumPage.swift", "Mac/Album/MacPlaylistPage.swift"):
        text = code(name)
        assert ".macContextMenu { QueueMenuItems(request: menu) }" in text, name
        assert "startRadio" not in text, name
    assert ".macContextMenu { QueueMenuItems(request: menu(song)) }" in code("Search/SearchScreen.swift")
    # Now Playing's •••, for the song playing, after Go to album - its name says so
    now = code(NOW_MENU)
    assert "let radio = song != nil && reachability.online && server.access.lastfm == .on" in now
    menu_body = body(now, "Menu {")
    assert (menu_body.index("NowPlayingWords.goToAlbum") < menu_body.index("if radio, let song {")
            < menu_body.index("DownloadMenuSection("))
    assert "playlist: onPlaylist != nil, radio: radio))" in now
    info = flat(core("Info.swift"))
    assert '+ "\\(radio ? ", start radio" : "")\\(download ? ", download" : "")"' in info


# ----------------------------------------------------------------------------- Autoplay, the device's setting


def test_autoplay_is_the_devices_own_and_off_by_default():
    station = code(STATION)
    assert "private(set) var autoplay = Autoplay.read(UserDefaults.standard.string(forKey: Autoplay.storageKey))" in station
    assert "UserDefaults.standard.set(Autoplay.stored(on), forKey: Autoplay.storageKey)" in station
    words = flat(core("Station.swift"))
    assert 'public static let storageKey = "deadwax-player-autoplay"' in words
    assert 'public static func read(_ stored: String?) -> Bool { stored == "on" }' in words
    # kept nowhere else: never with the queue, never on deadwax
    for path in sorted(APP.rglob("*.swift")):
        name = path.relative_to(APP).as_posix()
        if name != STATION:
            assert "Autoplay.storageKey" not in path.read_text(encoding="utf-8"), name


def test_autoplay_off_takes_its_rows_out_and_never_touches_a_radio():
    station = code(STATION)
    off = inner(station, "func setAutoplay(_ on: Bool) {")
    assert off == ("guard on != autoplay else { return } autoplay = on UserDefaults.standard.set(Autoplay.stored(on), "
                   "forKey: Autoplay.storageKey) if !on { letAutoplayGo() }")
    # (A3's review) its songs out of the queue AND the list's source (withoutStation), from where they begin - a radio's
    # never; nothing while an edit waits for a join (a held append would land after it as plain rows)
    go = inner(station, "private func letAutoplayGo() {")
    assert go == ("guard let held = station, held.kind == .autoplay, let player, !player.holdsAnEdit else { return } "
                  "drop() if let start = held.start { player.removeStation(from: start) }")
    # the check makes it once the held edit has landed (the queue changes, so the watch looks again), before anything
    check = inner(station, "private func check() {")
    assert ("guard !player.holdsAnEdit else { return } if !autoplay, station?.kind == .autoplay { letAutoplayGo() "
            "return } guard Station.wantsMore(") in check
    assert inner(code(PLAYER), "func removeStation(from start: Int) {") == (
        "guard let controller else { return } act { controller.removeStation(from: start) }")
    controller = flat(core("QueueController.swift"))
    assert "public func removeStation(from start: Int) { edit { withoutStation($0, from: start) } }" in controller
    # a row at a time (withoutKey) no longer: that left the songs in the source
    assert "player.remove(key:" not in station and "autoplayKeys" not in station
    assert "autoplayKeys" not in core("Station.swift")


def test_the_chip_is_after_repeat_on_both_and_only_while_lastfm_is_on():
    queue = code(QUEUE)
    # the phone's foot: the flat button Shuffle's and Repeat's are, lit and selected while on, with its hint
    buttons = body(queue, "@ViewBuilder private var modeButtons: some View {")
    assert buttons.index("Text(UpNextWords.shuffle)") < buttons.index("Text(repeatLabel(mode))") < buttons.index(
        "if server.access.lastfm == .on {")
    assert ("if server.access.lastfm == .on { Button(action: toggleAutoplay) { Text(LastfmWords.autoplay) } "
            ".buttonStyle(DWButtonStyle(kind: player.autoplay ? .on : .normal)) "
            ".accessibilityAddTraits(player.autoplay ? .isSelected : []) "
            ".accessibilityHint(LastfmWords.autoplayHint) } }") in buttons
    # the Mac's: (R16) the dock header's `.btn.sm` after Repeat's, lit and selected while on, with its hint - the header
    # folds History and Clear into a ••• where the three don't leave them room (tests/test_ios_dock_look.py)
    modes = body(queue, "private var macModes: some View {")
    assert modes.index("Button(UpNextWords.shuffle, action: toggleShuffle)") < modes.index(
        "Button(repeatLabel(mode), action: cycleRepeat)") < modes.index("if server.access.lastfm == .on {")
    assert ("if server.access.lastfm == .on { Button(LastfmWords.autoplay, action: toggleAutoplay) "
            ".buttonStyle(DWButtonStyle(kind: player.autoplay ? .on : .normal, size: .small)) "
            ".accessibilityAddTraits(player.autoplay ? .isSelected : []) "
            ".accessibilityHint(LastfmWords.autoplayHint)") in modes
    assert "private struct Chip: View {" not in queue
    # the chip's own call, said as Shuffle's and Repeat's are
    assert inner(queue, "private func toggleAutoplay() {") == (
        "let on = !player.autoplay player.setAutoplay(on) Notice.announce(LastfmWords.autoplaySaid(on))")
    words = flat(core("LastfmWords.swift"))
    assert 'public static let autoplaySymbol = "infinity"' in words
    assert 'public static let startRadioSymbol = "dot.radiowaves.left.and.right"' in words


def test_the_macs_tick_is_after_repeats_submenu():
    commands = code(COMMANDS)
    controls = body(commands, "@ViewBuilder private func controls(_ section: [MacMenu.Item]) -> some View {")
    assert "section.filter { $0.command.repeatMode == nil && $0.command != .autoplay }" in controls
    assert controls.index("Menu(MacMenu.Words.repeatMenu)") < controls.index(
        "ForEach(section.filter { $0.command == .autoplay }, id: \\.command) { (each: MacMenu.Item) in tick(each) }")
    assert "case .autoplay: player.setAutoplay(!player.autoplay)" in commands
    assert ("lastfm: server.access.lastfm == .on, autoplay: player.autoplay, station: player.hasStation, "
            "rowSize: MacRowSizeStore.shared.size)") in commands
    menu = flat(core("MacMenu.swift"))
    assert "[.shuffle] + Command.repeats + (state.lastfm ? [.autoplay] : [])" in menu


def test_the_word_is_queue():
    # nothing the slice shows or speaks says "Up Next": the chip, the heading, the items, the notices, the hint
    a3 = flat(core("LastfmWords.swift"))
    a3 = a3[a3.index("startRadio"):]
    for said in re.findall(r'"([^"]*)"', a3):
        assert "Up Next" not in said, said
    assert re.search(r'public static let autoplay = "Autoplay"', a3)
    for name in SPOKEN:
        for said in re.findall(r'"((?:[^"\\]|\\.)*)"', uncommented(source(name))):
            assert "Up Next" not in said, (name, said)
    for name in ("Station.swift", "MacMenu.swift", "LastfmWords.swift"):
        for said in re.findall(r'"((?:[^"\\]|\\.)*)"', uncommented(core(name))):
            assert "Up Next" not in said, (name, said)


# ----------------------------------------------------------------------------- the Queue's rows


def test_autoplays_rows_are_drawn_under_their_own_heading():
    queue = code(QUEUE)
    assert "if let whole = view.list { let split = player.stationSplit(whole) let own = split.list?.rows.count ?? 0" in queue
    # the phone's: the list's title over its own rows, "Autoplay" over the rest - one group, drawn in two parts
    assert queue.count("heading(LastfmWords.autoplay)") == 1
    assert ("heading(QueuePageWords.heading(list.title)) rows(whole.rows, lines: QueuePageWords.showsLines(list.rows, "
            "title: list.title), part: 0..<own)") in queue
    assert "heading(LastfmWords.autoplay) rows(whole.rows, lines: true, part: own..<whole.rows.count)" in queue
    # the Mac's: (R16) a `.navh` of the dock's over them, as the list's title is
    assert queue.count("macHeading(LastfmWords.autoplay) rows(whole.rows, lines: true, part: own..<whole.rows.count)") == 1
    assert queue.count("rows(whole.rows, lines: true, part: own..<whole.rows.count)") == 2
    # a drag in a part moves in the whole group's places
    assert "let drawn = part.map { $0.clamped(to: rows.indices) } ?? rows.indices" in queue
    assert ".onMove(perform: mover(rows, from: drawn.lowerBound))" in queue
    mover = body(queue, "private func mover(_ rows: [UpNextRow], from offset: Int = 0)")
    assert ("let from = first + offset move(rows[from], in: rows, to: UpNextWords.movedTo(from: from, destination: "
            "destination + offset))") in mover
    station = code(STATION)
    assert inner(station, "func stationSplit(_ list: UpNextList?) -> (list: UpNextList?, autoplay: [UpNextRow]) {") == (
        "Station.split(list, queue, stations.station)")


def test_shuffle_is_dimmed_while_the_queue_has_a_station():
    # (A3's review) only while Shuffle is off - one already on can be turned off - and only once the station's songs
    # are in the list: a radio's always, Autoplay's once it has given some (Station.inList)
    station = code(STATION)
    assert "var hasStation: Bool { stations.has(queue) }" in station
    assert "var stationHoldsShuffle: Bool { hasStation && !shuffle }" in station
    assert inner(station, "func has(_ queue: UpNextQueue) -> Bool {") == (
        "guard let station, let id = queue.upNext?.id else { return false } return station.queueId == id && "
        "station.inList")
    assert "public var inList: Bool { kind == .radio || !added.isEmpty }" in flat(core("Station.swift"))
    # every Shuffle: the Queue's foot and chip (and its call), Now Playing's, the Mac's player bar and Controls
    queue = code(QUEUE)
    assert (".disabled(player.paged != nil || player.stationHoldsShuffle)"
            in body(queue, "@ViewBuilder private var modeButtons"))
    #? (R16) the dock header's Shuffle
    assert ("Button(UpNextWords.shuffle, action: toggleShuffle) .buttonStyle(DWButtonStyle(kind: player.shuffle ? .on : "
            ".normal, size: .small)) .disabled(player.paged != nil || player.stationHoldsShuffle)"
            in body(queue, "private var macModes: some View {"))
    assert ("guard player.paged == nil, !player.stationHoldsShuffle else { return }"
            in body(queue, "private func toggleShuffle()"))
    for name in ("Player/NowPlayingView.swift", "Player/PlayerBar.swift"):
        text = code(name)
        assert "let paged = player.paged != nil || player.stationHoldsShuffle" in text, name
        assert "hasStation" not in text, name
    assert ("case .shuffle: return state.queued && state.paged == nil && (!state.station || state.shuffle)"
            in flat(core("MacMenu.swift")))
    # nothing else reads a station to dim Shuffle
    for path in sorted(APP.rglob("*.swift")):
        name = path.relative_to(APP).as_posix()
        if name not in (STATION, COMMANDS):
            assert "hasStation" not in uncommented(path.read_text(encoding="utf-8")), name


def test_the_phones_foot_holds_the_three_on_one_line():
    # Shuffle, the longest Repeat and Autoplay, flat buttons of 14 pt (the footnote's at large, 13), 6 either side and
    # 44 at least, 8 apart, inside the foot's 16 either side - at xxxLarge, where the foot stops growing, on a
    # 375-point phone: the time left goes under them (ViewThatFits), never the buttons off the line
    look = flat(core("DWLook.swift"))
    phone = look[look.index("static let onPhone = DWLook("):]
    padding = float(re.search(r"buttonPadding: (\d+)", phone).group(1))
    target = float(re.search(r"target: (\d+)", phone).group(1))
    assert (padding, target) == (6, 44)
    assert "case .button: return (14, .footnote)" in flat(source("Shared/Typeface.swift"))
    queue = code(QUEUE)
    assert "private static let side: CGFloat = 16" in queue and "private static let footGap: CGFloat = 8" in queue
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in body(queue, "private func phoneFoot(")
    words = {"Shuffle": "Shuffle", "Repeat one": "Repeat one", "Autoplay": "Autoplay"}
    assert 'public static let shuffle = "Shuffle"' in flat(core("Info.swift"))
    assert 'case .one: return "Repeat one"' in flat(core("UpNextView.swift"))
    for size, footnote in (("large", 13), ("xxxLarge", 19)):
        points = 14 * footnote / 13
        # lit is semibold, the widest: each as wide as its words and room, or a target
        widths = [max(fonts.words(word, points, "semibold") + 2 * padding, target) for word in words.values()]
        assert 2 * 16 + sum(widths) + 2 * 8 <= 375, (size, widths)


# ----------------------------------------------------------------------------- the top-up


def test_the_top_up_is_watched_outside_every_view_reading_only_what_it_needs():
    station = code(STATION)
    watch = body(station, "private func watch() {")
    assert inner(watch, "withObservationTracking {") == (
        "_ = player?.queue _ = player?.repeatMode _ = autoplay _ = server.access.lastfm _ = reachability?.online")
    assert "DispatchQueue.main.async { MainActor.assumeIsolated { self?.check() self?.watch() } }" in watch
    # one keeper, the player's, made with it and wired in once
    player = code(PLAYER)
    assert "let stations: StationKeeper" in player
    assert "stations = StationKeeper(server: server)" in player and "stations.attach(self)" in player
    assert "stations.connect(downloads: downloads, reachability: reachability)" in player
    for path in sorted(APP.rglob("*.swift")):
        name = path.relative_to(APP).as_posix()
        text = uncommented(path.read_text(encoding="utf-8"))
        if name not in (STATION, PLAYER):
            assert "StationKeeper" not in text and "stations." not in text, name
    # a new queue drops the station; never made against a queue a held edit will change
    check = inner(station, "private func check() {")
    assert check.startswith("guard let player else { return } let queue = player.queue if let held = station, "
                            "held.queueId != queue.upNext?.id { drop() } guard !player.holdsAnEdit else { return } "
                            "if !autoplay, station?.kind == .autoplay { letAutoplayGo() return } "
                            "guard Station.wantsMore(queue, mode: player.repeatMode, lastfm: server.access.lastfm == .on, "
                            "station: station, autoplay: autoplay) else { return }")
    # Autoplay's station begun only with Autoplay on; offline only songs on this device
    assert "if station == nil { guard autoplay, let made = Station.autoplay(queue) else { return } station = made }" in check
    assert "let here: ((String) -> Bool)? = online ? nil :" in check and "downloads?.isHere(id) ?? false" in check
    # never asked offline; the retry after a failure is the rule's
    ask = inner(station, "private func ask() {")
    assert "guard reachability?.online ?? true else { return }" in ask
    assert "working.mayAsk(playing: entry, now: Monotonic.seconds())" in ask


def test_the_keepers_every_definition_is_as_written():
    # (A3's review) each of these was mutated and passed the whole suite: a late answer applied (both guards), `has`
    # false, a take's pointer not kept, the radio asked of the store, an ask not counted, the setter a no-op, the retry
    # at once. Each is pinned as it is, so a change to one is a change of its own
    station = code(STATION)
    assert inner(station, "private func check() {") == (
        "guard let player else { return } let queue = player.queue if let held = station, held.queueId != "
        "queue.upNext?.id { drop() } guard !player.holdsAnEdit else { return } if !autoplay, station?.kind == .autoplay "
        "{ letAutoplayGo() return } guard Station.wantsMore(queue, mode: player.repeatMode, lastfm: "
        "server.access.lastfm == .on, station: station, autoplay: autoplay) else { return } if station == nil { guard "
        "autoplay, let made = Station.autoplay(queue) else { return } station = made } guard var working = station, "
        "!working.exhausted else { return } guard working.songs != nil else { ask() return } let online = "
        "reachability?.online ?? true let here: ((String) -> Bool)? = online ? nil : { [weak downloads] (id: String) "
        "-> Bool in downloads?.isHere(id) ?? false } let songs = working.take(queue, here: here) if working != station "
        "{ station = working } if !songs.isEmpty { player.appendStation(songs) }")
    assert inner(station, "private func ask() {") == (
        "guard var working = station, let player, asking == nil else { return } guard reachability?.online ?? true "
        "else { return } let entry = player.current?.key guard working.mayAsk(playing: entry, now: "
        "Monotonic.seconds()) else { if working.ask == nil, working.songs == nil { answered(LastfmRadio(songs: []), "
        "queueId: working.queueId) } return } guard let seed = working.ask, let client = server.client else { return } "
        "working.began() station = working again?.cancel() let scope = ShuffleOf.library.scope(library: "
        "AlbumScope.albums(for: server.me)) let queueId = working.queueId asking = Task { [weak self] in let answer = "
        "try? await client.lastfmRadio(songId: seed.songId, title: seed.title, artist: seed.artist, scope: scope) "
        "guard !Task.isCancelled else { return } self?.answered(answer, queueId: queueId) }")
    assert inner(station, "private func answered(_ answer: LastfmRadio?, queueId: String) {") == (
        "asking = nil guard var working = station, working.queueId == queueId, let player else { return } let outcome "
        "= working.answered(answer, playing: player.current?.key, now: Monotonic.seconds()) station = working if "
        "working.kind == .radio { if outcome == .nothing { player.say(LastfmWords.noSimilarSongs) } if outcome == "
        ".failed && working.asks == 1 { player.say(LastfmWords.radioFailed) } } if outcome == .failed { "
        "scheduleAgain() } check()")
    assert inner(station, "private func scheduleAgain() {") == (
        "again?.cancel() guard let at = station?.againAt else { return } let work = DispatchWorkItem { [weak self] in "
        "MainActor.assumeIsolated { self?.check() } } again = work DispatchQueue.main.asyncAfter(deadline: .now() + "
        "max(0, at - Monotonic.seconds()), execute: work)")
    assert inner(station, "private func drop() {") == (
        "asking?.cancel() asking = nil again?.cancel() again = nil if station != nil { station = nil }")
    assert inner(station, "func radioStarted(_ song: Song) {") == (
        "drop() guard let player, let made = Station.radio(player.queue), made.seed.id == song.id else { return } "
        "station = made ask()")
    assert inner(station, "func connect(downloads: DownloadModel, reachability: Reachability) {") == (
        "self.downloads = downloads self.reachability = reachability guard !watching else { return } watching = true "
        "watch() check()")
    # the player's half: each the keeper's own call, nothing more
    player = inner(station, "extension PlayerModel {")
    assert player == (
        "func startRadio(_ song: Song) { play(playlist: [song], at: 0) stations.radioStarted(song) } var autoplay: Bool "
        "{ stations.autoplay } func setAutoplay(_ on: Bool) { stations.setAutoplay(on) } var hasStation: Bool { "
        "stations.has(queue) } var stationHoldsShuffle: Bool { hasStation && !shuffle } func stationSplit(_ list: "
        "UpNextList?) -> (list: UpNextList?, autoplay: [UpNextRow]) { Station.split(list, queue, stations.station) }")


def test_autoplay_never_starts_the_music():
    station = code(STATION)
    keeper = body(station, "final class StationKeeper {")
    # the keeper appends and removes: it never plays, resumes or skips
    for call in (r"\bplay\(", r"\bresume\(", r"\btogglePlay", r"\bplayPause", r"\.next\(\)", r"\bskip\w*\("):
        assert not re.search(call, keeper), call
    append = inner(code(PLAYER), "func appendStation(_ songs: [Song]) {")
    assert append == ("guard let controller, !songs.isEmpty else { return } let plan = PlaylistPlay.plan(songs, setting: "
                      "normalization) { [played] (id: String) -> Album? in played.get(id) } let keeping = "
                      "QueueAlbums.named(entries.map(\\.track) + plan.tracks) for each in plan.albums { "
                      "played.also(each, keeping: keeping) } shelve(songs) controller.appendStation(plan.tracks)")
    # QueueController's append is an edit: held for a join, never a play
    controller = flat(core("QueueController.swift"))
    assert ("public func appendStation(_ tracks: [QueueTrack]) { let mode = repeatMode edit { withStation($0, tracks, "
            "mode) } }") in controller


def test_the_notices_are_the_players():
    station = code(STATION)
    answered = inner(station, "private func answered(_ answer: LastfmRadio?, queueId: String) {")
    assert ("if working.kind == .radio { if outcome == .nothing { player.say(LastfmWords.noSimilarSongs) } "
            "if outcome == .failed && working.asks == 1 { player.say(LastfmWords.radioFailed) } }") in answered
    assert "if outcome == .failed { scheduleAgain() } check()" in answered


#? (R16) The Mac's chips are gone: Shuffle, Repeat and Autoplay are the dock header's `.btn.sm`s, and how they fit the
#? panel's 400 is tests/test_ios_dock_look.py's (test_the_queues_header_fits_the_dock).


def foot_draws(text: str) -> list[str]:
    """What the phone's foot's buttons draw with a fill, a face or an edge - none: they are flat."""
    buttons = body(phone_look.bare(text), "@ViewBuilder private var modeButtons: some View {")
    shapes = re.findall(r"\.bordered\w*|\bDivider\(\)|\bDWRaised\b|\bDWWell\b|\bPhoneCard\b|cornerRadius|"
                        r"RoundedRectangle\(|\bCapsule\b|\.capsule\b|\.shadow\(", buttons)
    return phone_look.drawn(phone_look.phone_path(buttons)) + shapes


def test_the_phones_new_button_is_flat():
    # the Queue's foot is one of the redesign's flat pages (R3b): Shuffle, Repeat and Autoplay, DWButtonStyle's flat
    # buttons, with no face of their own - the foot's ground and hairline are phoneFoot's, as before
    assert QUEUE in phone_look.SLICES
    assert foot_draws(source(QUEUE)) == []
    #? and (R16) the Mac dock header's three, the same kinds at the small size
    assert code(QUEUE).count(".buttonStyle(DWButtonStyle(kind:") == 6
    # (the mutation's guard) a face given to the phone's Autoplay is found
    planted = source(QUEUE).replace(".accessibilityHint(LastfmWords.autoplayHint)\n        }",
                                    ".accessibilityHint(LastfmWords.autoplayHint)\n            .background(DWPalette.card)\n"
                                    "        }", 1)
    assert planted != source(QUEUE)
    assert foot_draws(planted) == ["background: DWPalette.card"]
