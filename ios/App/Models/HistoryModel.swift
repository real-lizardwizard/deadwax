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
///  - ONLY THE NEWEST ANSWER DRAWS: each ask numbered (Core's HistoryAsking, which holds these rules), and the
///    person's too.
///  - A FAILURE is kept, for Up Next to say in a listener's words (ErrorWords) with Try again (`retry`, the ask that
///    failed): an older page's stops scrolling from asking until then; the newest page's never stops the older pages,
///    and offline the newest page isn't asked for - what this phone keeps is drawn - nor its earlier failure said.
///    Up Next asks for it again as the network comes back.
///
/// Another person (ServerModel.whenPersonChanges): everything let go (`reset`), and their own read from their store.
@MainActor
@Observable
final class HistoryModel {
    /// Every start held and made, newest first, each once.
    private(set) var plays: [Played] = []
    /// What may be asked, and what failed.
    private(set) var asking = HistoryAsking()
    /// Each older page that landed, counted: Up Next asks again when the rows near the top are still in view.
    private(set) var landed = 0
    /// What deadwax's pages brought, and where to ask on from.
    private var held = HistoryHeld.nothing

    /// There are older plays than those held: scrolling up asks for them.
    var more: Bool { held.before != nil }
    /// An older page is on its way.
    var loading: Bool { asking.loadingOlder }
    /// The failure to say with Try again, and its error - nil for none.
    var failure: (any Error)? {
        switch asking.shown(online: reachability.online) {
        case .older?: olderError
        case .newest?: newestError
        case nil: nil
        }
    }
    /// An older page may be asked for now.
    var mayAskOlder: Bool { asking.mayAskOlder(more: more) }

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored weak var downloads: DownloadModel?
    /// This run's own starts (the newest 500) and the continuation a queue put back set.
    @ObservationIgnored private var outbox = HistoryOutbox()
    /// The newest page kept on this phone, drawn until a page comes.
    @ObservationIgnored private var kept: [Played] = []
    /// The starts the store held unsent when they were read - an earlier run's, offline.
    @ObservationIgnored private var waiting: [Played] = []
    /// The person whose kept page and starts were read (ServerModel.person); nil: not yet.
    @ObservationIgnored private var readFor: Int?
    @ObservationIgnored private var newestError: (any Error)?
    @ObservationIgnored private var olderError: (any Error)?

    init(server: ServerModel, reachability: Reachability) {
        self.server = server
        self.reachability = reachability
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

    /// The newest page, joined to what is held - as Up Next opens, as the app comes to the front with it open (what
    /// the web played meanwhile), and as the network comes back. Not asked offline.
    func refresh() {
        guard let client = server.client, let ask = asking.askNewest(online: reachability.online) else { return }
        let person = server.person
        Task {
            do {
                let page = try await client.historyPage()
                guard person == server.person, asking.newestCame(ask) else { return }
                newestError = nil
                held = PlayHistory.withNewest(held, page)
                downloads?.keepHistoryPage(page)
                redraw()
            } catch {
                guard person == server.person, !APIFailure.isCancellation(error) else { return }
                if asking.failedNewest(ask) { newestError = error }
            }
        }
    }

    /// The page before the oldest held - one at a time, while there is one, and not after an older page's failure
    /// until Try again.
    func older() {
        guard let from = held.before, let client = server.client, let ask = asking.askOlder(more: more) else { return }
        let person = server.person
        Task {
            do {
                let page = try await client.historyPage(before: from)
                guard person == server.person, asking.olderCame(ask) else { return }
                olderError = nil
                held = PlayHistory.withOlder(held, from: from, page)
                redraw()
                landed += 1
            } catch {
                guard person == server.person, !APIFailure.isCancellation(error) else { return }
                if asking.failedOlder(ask) { olderError = error }
            }
        }
    }

    /// Try again: the ask that failed, again.
    func retry() {
        switch asking.retry(online: reachability.online) {
        case .older?: older()
        case .newest?: refresh()
        case nil: refresh()
        }
    }

    /// Another person: nothing of the last one's kept, and every answer still on its way dropped.
    func reset() {
        outbox.forget()
        held = .nothing
        kept = []
        waiting = []
        readFor = nil
        asking.reset()
        newestError = nil
        olderError = nil
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
