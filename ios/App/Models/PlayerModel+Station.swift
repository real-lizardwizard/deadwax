import DeadwaxCore
import Foundation

// Radio and Autoplay (Last.fm, slice A3 - deadwax-plans/lastfm.md 3.5; notes/ios.md "Last.fm, slice A3"): Start Radio
// plays a song as a new queue in the tap and asks deadwax for songs of your library Last.fm calls similar; Autoplay, a
// setting of this device's (off by default), does the same at a queue's end from its last song. Core's Station holds
// every rule - when the queue wants more, which songs it takes, which rows are Autoplay's - and QueueController's
// appendStation (withStation) appends them through the edit path Add to Queue's songs take. This is the asking, the
// retry's timer, the setting kept, and the top-up's watch - which reads the queue, Repeat, the setting, Last.fm's state
// and whether deadwax can be reached, and nothing else, outside every view. Nothing of a station is saved.

/// The station the queue playing has, and Autoplay's setting (PlayerModel.stations - one, made with the player).
@MainActor
@Observable
final class StationKeeper {
    /// The queue's station, or none - dropped once the queue playing is another (its id, UpNextState.id).
    private(set) var station: Station?
    /// Autoplay, this device's own (UserDefaults, Autoplay.storageKey): off unless it was turned on here.
    private(set) var autoplay = Autoplay.read(UserDefaults.standard.string(forKey: Autoplay.storageKey))

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private weak var player: PlayerModel?
    @ObservationIgnored private weak var downloads: DownloadModel?
    @ObservationIgnored private weak var reachability: Reachability?
    @ObservationIgnored private var asking: Task<Void, Never>?
    @ObservationIgnored private var again: DispatchWorkItem?
    @ObservationIgnored private var watching = false

    init(server: ServerModel) {
        self.server = server
    }

    /// The player it tops up (PlayerModel's init).
    func attach(_ player: PlayerModel) {
        self.player = player
    }

    /// The downloads and deadwax's reach wired in (PlayerModel.connect, once): offline, a top-up takes only songs on
    /// this device, and nothing is asked. The watch starts here, with everything it reads in hand.
    func connect(downloads: DownloadModel, reachability: Reachability) {
        self.downloads = downloads
        self.reachability = reachability
        guard !watching else { return }
        watching = true
        watch()
        check()
    }

    // MARK: Start Radio and the setting

    /// Start Radio's station, once its song plays as a new queue (PlayerModel.startRadio, after the play): the old one
    /// let go, and deadwax asked at once. Nothing when the song isn't what plays (no engine could be made).
    func radioStarted(_ song: Song) {
        drop()
        guard let player, let made = Station.radio(player.queue), made.seed.id == song.id else { return }
        station = made
        ask()
    }

    /// Autoplay turned on or off, and kept. Off takes Autoplay's songs still to come out of the queue and lets its
    /// station go (`letAutoplayGo`); a radio's station, and its songs, are never touched.
    func setAutoplay(_ on: Bool) {
        guard on != autoplay else { return }
        autoplay = on
        UserDefaults.standard.set(Autoplay.stored(on), forKey: Autoplay.storageKey)
        if !on { letAutoplayGo() }
    }

    /// (A3's review) Autoplay off: its songs out of the queue - the entries to come and the list's source from where
    /// they begin (withoutStation, so the heading, Repeat All's line and its next time round are the album's again) -
    /// and its station let go. While an edit waits for a song's join, nothing yet: a held append of Autoplay's would
    /// land after the removal as plain rows, so the top-up's check makes it once the held edit has landed.
    private func letAutoplayGo() {
        guard let held = station, held.kind == .autoplay, let player, !player.holdsAnEdit else { return }
        drop()
        if let start = held.start { player.removeStation(from: start) }
    }

    /// The queue playing has a station of its own whose songs are in its list (Station.inList): a radio's, or
    /// Autoplay's once it has given some. Shuffle can't be turned on then.
    func has(_ queue: UpNextQueue) -> Bool {
        guard let station, let id = queue.upNext?.id else { return false }
        return station.queueId == id && station.inList
    }

    // MARK: the top-up

    /// The watch: whatever it reads changing, the top-up looked at again - once the change has been made.
    private func watch() {
        withObservationTracking {
            _ = player?.queue
            _ = player?.repeatMode
            _ = autoplay
            _ = server.access.lastfm
            _ = reachability?.online
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.check()
                    self?.watch()
                }
            }
        }
    }

    /// The top-up (Station.wantsMore): a station not of this queue let go; Autoplay turned off while an edit waited,
    /// its songs taken out now; then, while the queue wants more, Autoplay's station begun (seeded by the queue's last
    /// entry), its next songs taken and appended, or its answer asked for. Never while an edit waits for the join: the
    /// queue it would be made against isn't the one in hand.
    private func check() {
        guard let player else { return }
        let queue = player.queue
        if let held = station, held.queueId != queue.upNext?.id { drop() }
        guard !player.holdsAnEdit else { return }
        if !autoplay, station?.kind == .autoplay {
            letAutoplayGo()
            return
        }
        guard Station.wantsMore(queue, mode: player.repeatMode, lastfm: server.access.lastfm == .on, station: station,
                                autoplay: autoplay) else { return }
        if station == nil {
            guard autoplay, let made = Station.autoplay(queue) else { return }
            station = made
        }
        guard var working = station, !working.exhausted else { return }
        guard working.songs != nil else {
            ask()
            return
        }
        let online = reachability?.online ?? true
        let here: ((String) -> Bool)? = online ? nil : { [weak downloads] (id: String) -> Bool in
            downloads?.isHere(id) ?? false
        }
        let songs = working.take(queue, here: here)
        if working != station { station = working }
        if !songs.isEmpty { player.appendStation(songs) }
    }

    /// The station's answer asked for, when it may be (Station.mayAsk) - never while deadwax can't be reached (the
    /// reach coming back looks again). A seed with no title or artist has no answer to ask: nothing, at once.
    private func ask() {
        guard var working = station, let player, asking == nil else { return }
        guard reachability?.online ?? true else { return }
        let entry = player.current?.key
        guard working.mayAsk(playing: entry, now: Monotonic.seconds()) else {
            if working.ask == nil, working.songs == nil {
                answered(LastfmRadio(songs: []), queueId: working.queueId)
            }
            return
        }
        guard let seed = working.ask, let client = server.client else { return }
        working.began()
        station = working
        again?.cancel()
        let scope = ShuffleOf.library.scope(library: AlbumScope.albums(for: server.me))
        let queueId = working.queueId
        asking = Task { [weak self] in
            let answer = try? await client.lastfmRadio(songId: seed.songId, title: seed.title, artist: seed.artist,
                                                       scope: scope)
            guard !Task.isCancelled else { return }
            self?.answered(answer, queueId: queueId)
        }
    }

    /// The answer (nil: the ask failed), for the station of `queueId` - let go if that station has gone. A radio says
    /// what came of it: nothing similar ("No similar songs in your library.", the song plays alone), or deadwax
    /// couldn't make it at the first ask ("Couldn't start the radio just now.") - asked again by the top-up's rule, 30 s
    /// later while the same entry plays (`again`), at once on another, 3 times at most. Autoplay says nothing.
    private func answered(_ answer: LastfmRadio?, queueId: String) {
        asking = nil
        guard var working = station, working.queueId == queueId, let player else { return }
        let outcome = working.answered(answer, playing: player.current?.key, now: Monotonic.seconds())
        station = working
        if working.kind == .radio {
            if outcome == .nothing { player.say(LastfmWords.noSimilarSongs) }
            if outcome == .failed && working.asks == 1 { player.say(LastfmWords.radioFailed) }
        }
        if outcome == .failed { scheduleAgain() }
        check()
    }

    /// The ask after a failure, when it falls due (Station.againAt) - looked at as any top-up is.
    private func scheduleAgain() {
        again?.cancel()
        guard let at = station?.againAt else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        again = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, at - Monotonic.seconds()), execute: work)
    }

    /// The station let go: its ask and its retry with it.
    private func drop() {
        asking?.cancel()
        asking = nil
        again?.cancel()
        again = nil
        if station != nil { station = nil }
    }
}

extension PlayerModel {
    /// Start Radio (every one-song •••, Now Playing's, a song's right-click on the Mac): `song` played at once as a new
    /// queue, at the songs level as a playlist's tap plays one (PlaylistPlay.plan) - in the tap, nothing awaited first
    /// - and only then its station made and deadwax asked for its similar songs, which are appended as they come.
    func startRadio(_ song: Song) {
        play(playlist: [song], at: 0)
        stations.radioStarted(song)
    }

    /// Autoplay, this device's setting.
    var autoplay: Bool { stations.autoplay }

    /// The Queue's chip and the Mac's tick: Autoplay turned on or off.
    func setAutoplay(_ on: Bool) {
        stations.setAutoplay(on)
    }

    /// The queue playing has a station whose songs are in its list (StationKeeper.has).
    var hasStation: Bool { stations.has(queue) }

    /// (A3's review) Shuffle can't be turned on while the queue has a station - shuffling would mix the station's songs
    /// into the album - but one already on can still be turned off: every Shuffle (the Queue's, Now Playing's, the Mac's
    /// player bar and Controls) is dimmed only then.
    var stationHoldsShuffle: Bool { hasStation && !shuffle }

    /// The Queue's list as drawn: its own rows, and Autoplay's under their heading (Station.split).
    func stationSplit(_ list: UpNextList?) -> (list: UpNextList?, autoplay: [UpNextRow]) {
        Station.split(list, queue, stations.station)
    }
}
