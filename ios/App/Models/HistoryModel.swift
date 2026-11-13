import DeadwaxCore
import Foundation
import Observation

/// The person's play history as Up Next draws it (app 0.8; the web's app/usePlayHistory.ts and player/historyOutbox.ts,
/// notes/ios.md "Play history on the phone"): every song they began, on this phone and on the web, newest first, each
/// start once - deadwax's pages, the newest of them kept on this phone, and this phone's own starts (Core's
/// PlayHistory.merged).
///
///  - A START is recorded the moment "now playing" goes (PlayReporter's onStart, PlayerModel making it from the entry
///    heard): kept in this run's outbox - drawn at once - and in the person's download store (`start_pending`), from
///    which DownloadModel sends it, online or not, so a start survives the app being killed before it is sent. A
///    queue of deadwax's own put back mid-song (ResumeController's `continuing`) carries on its listen: its first
///    start of that song is no new start.
///  - A PLAY COUNTED marks its start counted, here and in the store (deadwax's insert ORs it in).
///  - THE NEWEST PAGE is asked for each time Up Next opens and each time the app comes to the front with it open, and
///    joined to what is held (withNewest) - and kept in the person's store (`meta`), so the songs played lately show
///    with deadwax out of reach, until a page comes.
///  - OLDER PAGES as Up Next is scrolled up to its oldest rows (`older`), one at a time, from the cursor the last gave
///    (withOlder) - until there are none. They need deadwax.
///  - ONLY THE NEWEST ANSWER DRAWS: each ask numbered, and the person's too.
///  - A FAILURE is kept, for Up Next to say in a listener's words (ErrorWords) with Try again (`retry`, the ask that
///    failed) - and scrolling asks no more until it is tried again.
///
/// Another person (ServerModel.whenPersonChanges): everything let go (`reset`), and their own read from their store.
@MainActor
@Observable
final class HistoryModel {
    /// Every start held and made, newest first, each once.
    private(set) var plays: [Played] = []
    /// An older page is on its way.
    private(set) var loading = false
    /// The last ask's failure - said with Try again; nil when it didn't fail.
    private(set) var failure: Failure?
    /// What deadwax's pages brought, and where to ask on from.
    private var held = HistoryHeld.nothing

    /// There are older plays than those held: scrolling up asks for them.
    var more: Bool { held.before != nil }

    struct Failure {
        let error: any Error
        let ask: Ask
    }

    enum Ask {
        case newest, older
    }

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored weak var downloads: DownloadModel?
    /// This run's own starts (the newest 500) and the continuation a queue put back set.
    @ObservationIgnored private var outbox = HistoryOutbox()
    /// The newest page kept on this phone, drawn until a page comes.
    @ObservationIgnored private var kept: [Played] = []
    /// The starts the store held unsent when they were read - an earlier run's, offline.
    @ObservationIgnored private var waiting: [Played] = []
    /// The person whose kept page and starts were read (ServerModel.person); nil: not yet.
    @ObservationIgnored private var readFor: Int?
    @ObservationIgnored private var newestAsk = 0
    @ObservationIgnored private var olderAsk = 0
    @ObservationIgnored private var asking = false

    init(server: ServerModel) {
        self.server = server
    }

    // MARK: what the player tells it

    /// A song begun (PlayerModel, at its "now playing"): drawn at once, and kept to be sent - unless it is the listen a
    /// queue put back carries on.
    func record(_ played: Played) {
        read()
        guard outbox.record(played) else { return }
        downloads?.keepStart(played)
        redraw()
    }

    /// A play counted: its start marked counted (a start not here - this run's or one waiting - is deadwax's to mark,
    /// from the play itself).
    func counted(songID: String, at: Int64) {
        outbox.counted(songID: songID, at: at)
        waiting = PlayHistory.countedIn(waiting, songID: songID, at: at)
        downloads?.countStart(songID: songID, at: at)
    }

    /// A queue put back (ResumeController): one of deadwax's own, mid-song, carries its listen on; nil ends that.
    func continuing(_ queue: UpNextQueue?) {
        outbox.continuing(queue)
    }

    // MARK: what Up Next asks

    /// Up Next opened: what this phone keeps drawn at once, and the newest page asked for.
    func opened() {
        read()
        redraw()
        refresh()
    }

    /// The newest page, joined to what is held - as Up Next opens, and as the app comes to the front with it open
    /// (what the web played meanwhile).
    func refresh() {
        guard let client = server.client else { return }
        newestAsk += 1
        let ask = newestAsk
        let person = server.person
        Task {
            do {
                let page = try await client.historyPage()
                guard ask == newestAsk, person == server.person else { return }
                held = PlayHistory.withNewest(held, page)
                downloads?.keepHistoryPage(page)
                if failure?.ask == .newest { failure = nil }
                redraw()
            } catch {
                guard ask == newestAsk, person == server.person, !APIFailure.isCancellation(error) else { return }
                failure = Failure(error: error, ask: .newest)
            }
        }
    }

    /// The page before the oldest held - one at a time, while there is one, and not after a failure until Try again.
    func older() {
        guard let from = held.before, !asking, failure == nil, let client = server.client else { return }
        asking = true
        loading = true
        olderAsk += 1
        let ask = olderAsk
        let person = server.person
        Task {
            do {
                let page = try await client.historyPage(before: from)
                guard ask == olderAsk, person == server.person else { return }
                asking = false
                loading = false
                held = PlayHistory.withOlder(held, from: from, page)
                if failure?.ask == .older { failure = nil }
                redraw()
            } catch {
                guard ask == olderAsk, person == server.person, !APIFailure.isCancellation(error) else { return }
                asking = false
                loading = false
                failure = Failure(error: error, ask: .older)
            }
        }
    }

    /// Try again: the ask that failed, again.
    func retry() {
        let ask = failure?.ask
        failure = nil
        if ask == .older { older() } else { refresh() }
    }

    /// Another person: nothing of the last one's kept, and every answer still on its way dropped.
    func reset() {
        outbox.forget()
        held = .nothing
        kept = []
        waiting = []
        readFor = nil
        newestAsk += 1
        olderAsk += 1
        asking = false
        loading = false
        failure = nil
        plays = []
    }

    // MARK: drawing

    /// The person's kept page and unsent starts, read once their store is open.
    private func read() {
        guard readFor != server.person, let downloads, downloads.isOpen else { return }
        readFor = server.person
        kept = downloads.keptHistoryPage()?.plays ?? []
        waiting = downloads.keptStarts()
    }

    private func redraw() {
        let next = PlayHistory.merged(held.asked ? held.plays : kept, outbox.own + waiting)
        if next != plays { plays = next }
    }
}
