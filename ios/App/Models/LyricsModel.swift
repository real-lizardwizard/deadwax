import DeadwaxCore
import Foundation
import Observation
import UIKit

/// The song playing's lyrics (app 0.4, notes/app-lyrics.md 2.6, 2.7, 4.2, 4.7) - for Now Playing's Lyrics button and
/// its face. The web app's app/useLyrics.ts, on the phone; every rule Core's (Lyrics, LyricsKept, LyricsWords).
///
/// - ASKED AT EVERY SONG CHANGE, Now Playing open or not, while the app is active and deadwax can be reached - one small
///   ask a song, with the answer in hand's ETag (a 304, usually), so the button is right the moment Now Playing opens.
///   Never in the background: a locked phone asks nothing; the song playing is asked for when the app comes back, or
///   deadwax does, if its answer isn't in hand - and again on opening the lyrics after a failure.
/// - THE NEXT SONG'S too, once, while the lyrics show and the song playing has `Lyrics.nextLyricsSeconds` left
///   (`ahead()`, from the lyrics' view as the position moves).
/// - KEPT: the last `Lyrics.kept` answers in memory, and a downloaded song's with the download (DownloadModel - so they
///   show offline, and an answer got online replaces the kept one when it differs). What is kept draws at once, while the
///   ask is on its way; a failed ask keeps nothing, and the answer in hand is drawn over it.
/// - ONLY THE NEWEST ANSWER DRAWS: a song changing mid-ask never draws the last one's words - an ask counts only while it
///   is the latest (`generation`), and `shown` is never another song's.
/// - `showing` - Lyrics on - lasts the app's life (Open question 1): kept here, not in Now Playing's own state, which
///   goes as its cover closes.
@MainActor
@Observable
final class LyricsModel {
    /// Lyrics on: the face shows them in the cover's place, every opening of Now Playing and every song, until turned
    /// off or the app quits. Not a setting. Turned on, the song's lyrics are asked for again if none are in hand.
    var showing = false {
        didSet {
            if showing, !oldValue { refresh() }
        }
    }

    /// The song whose lyrics are held - the song playing's, once the model has heard of it.
    private(set) var song: String?
    /// Its answer in hand - kept, or just come; nil while there is none.
    private(set) var lyrics: SongLyrics?
    /// An ask for it is on its way.
    private(set) var asking = false
    /// The last ask's failure (nil when it didn't fail) - drawn only while no answer is in hand.
    private(set) var failure: (any Error)?

    /// An answer and its ETag, as kept in memory.
    private struct Kept: Sendable {
        let lyrics: SongLyrics
        let etag: String?
    }

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private let downloads: DownloadModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private var memory = LyricsKept<Kept>()
    /// The answer in hand's ETag, sent with the next ask of the song.
    @ObservationIgnored private var etag: String?
    /// Counts the asks for the song playing: only the latest's answer draws.
    @ObservationIgnored private var generation = 0
    /// The app is in front (active): asks are made only then.
    @ObservationIgnored private var active = UIApplication.shared.applicationState == .active
    /// The next song asked for ahead - once a song.
    @ObservationIgnored private var askedAhead: String?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(server: ServerModel, player: PlayerModel, downloads: DownloadModel, reachability: Reachability) {
        self.server = server
        self.player = player
        self.downloads = downloads
        self.reachability = reachability
        reachability.whenChanged { [weak self] in self?.refresh() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.active = true
                self?.refresh()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.active = false }
        })
        watchSong()
        refresh()
    }

    // MARK: what Now Playing reads

    /// The song playing's answer in hand - never another song's: until the model has heard of a new song, what is kept
    /// of it in memory, else nothing.
    var shown: SongLyrics? {
        guard let id = player.current?.track.id else { return nil }
        return id == song ? lyrics : memory.peek(id)?.lyrics
    }

    /// What is known of the song playing's lyrics (2.7) - offline with none kept, "not on this phone".
    var have: LyricsHave { Lyrics.have(shown, online: reachability.online) }

    /// What the lyrics' place shows (4.2) - for a song the model hasn't heard of yet, its ask as good as on its way.
    var face: Lyrics.Face {
        guard let id = player.current?.track.id, id == song else {
            return Lyrics.face(shown, asking: true, failure: nil)
        }
        return Lyrics.face(lyrics, asking: asking, failure: failure)
    }

    // MARK: actions

    /// Now Playing opened with lyrics on: asked again if no answer is in hand and none is on its way (a failure's).
    func opened() {
        if showing { refresh() }
    }

    /// The failure's Try again.
    func retry() {
        guard let id = player.current?.track.id, id == song, active, reachability.online else { return }
        ask(id)
    }

    /// The next song's lyrics, once, while the lyrics show - called as the position moves, from the lyrics' view (2.6).
    func ahead() {
        guard showing, active, reachability.online, let client = server.client,
              Lyrics.asksAhead(position: player.shownPosition, duration: player.duration) else { return }
        let queue = player.queue
        guard queue.tracks.indices.contains(queue.index + 1) else { return }
        let next = queue.tracks[queue.index + 1].id
        guard next != askedAhead, next != song, memory.peek(next) == nil, downloads.keptLyrics(next) == nil else { return }
        askedAhead = next
        Task {
            // nothing to say of a failure: the join asks for them again
            guard case .fresh(let answer, let etag)? = try? await client.lyrics(songID: next, ifNoneMatch: nil) else { return }
            memory.keep(next, Kept(lyrics: answer.lyrics, etag: etag))
            downloads.lyricsAnswered(next, body: answer.body, etag: etag)
        }
    }

    /// The person changed (ServerModel.whenPersonChanges): nothing of the last one's kept - their answers are of songs
    /// the next may not be given. Lyrics on stays on: it is the phone's, not the person's.
    func reset() {
        letGo()
        memory.removeAll()
        askedAhead = nil
    }

    /// Nothing held: nothing playing, or the person changed - an ask on its way no longer counts.
    private func letGo() {
        generation += 1
        song = nil
        lyrics = nil
        etag = nil
        asking = false
        failure = nil
    }

    // MARK: asking

    /// The song playing, watched: each change of it drawn and asked for.
    private func watchSong() {
        withObservationTracking {
            _ = player.current?.track.id
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.player.current?.track.id != self.song { self.refresh() }
                    self.watchSong()
                }
            }
        }
    }

    /// The song playing's lyrics: a new song's drawn at once from what is kept - in memory, else with its download - and
    /// asked for; this one's asked for again only with no answer in hand and none on its way. Asked only while the app
    /// is active and deadwax can be reached.
    private func refresh() {
        guard let id = player.current?.track.id else {
            if song != nil { letGo() }
            return
        }
        let changed = id != song
        if changed {
            generation += 1
            song = id
            asking = false
            failure = nil
            let inHand = kept(id)
            lyrics = inHand?.lyrics
            etag = inHand?.etag
        }
        guard active, reachability.online else { return }
        if changed || (lyrics == nil && !asking) { ask(id) }
    }

    /// The song's answer kept: in memory (made the most recently used), else with its download.
    private func kept(_ id: String) -> Kept? {
        if let mine = memory.take(id) { return mine }
        guard let stored = downloads.keptLyrics(id) else { return nil }
        return Kept(lyrics: stored.lyrics, etag: stored.etag)
    }

    private func ask(_ id: String) {
        guard let client = server.client else { return }
        generation += 1
        let mine = generation
        let inHand = lyrics.map { Kept(lyrics: $0, etag: etag) }
        asking = true
        Task {
            do {
                let fetched = try await client.lyrics(songID: id, ifNoneMatch: inHand?.etag)
                switch fetched {
                case .fresh(let answer, let etag):
                    let fresh = Kept(lyrics: answer.lyrics, etag: etag)
                    memory.keep(id, fresh)
                    // a downloaded song's answer kept fresh by playing (4.7)
                    downloads.lyricsAnswered(id, body: answer.body, etag: etag)
                    guard mine == generation else { return }
                    lyrics = fresh.lyrics
                    self.etag = fresh.etag
                case .unchanged:
                    // still the answer in hand (a 304 is asked only with one)
                    if let inHand { memory.keep(id, inHand) }
                    guard mine == generation else { return }
                }
                asking = false
                failure = nil
            } catch {
                guard mine == generation else { return }
                asking = false
                // a failed ask keeps nothing; the answer in hand, if any, is still drawn over it
                if !APIFailure.isCancellation(error) { failure = Lyrics.failure(error) }
            }
        }
    }
}
