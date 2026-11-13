import Foundation

// The starts and plays kept on this phone, sent to deadwax (app 0.8, notes/ios.md "Play history on the phone"): the
// decisions of the App's send loop (DownloadModel), here where they are tested - what goes in which order, what is
// forgotten after which answer, what waits and for how long, and whose it is.
//
//  - WHOSE. A store is one person's on one server (KeptOwner), and every request goes out as whoever is signed in now
//    (KeptLine.owner, asked again before each one). Nothing is sent while the two differ - a sign-in in hand before
//    the App has moved its store over (its change of person is a hop on the main queue away) must never carry the
//    last person's starts or plays under the new session.
//  - THE STARTS FIRST, so a play's count finds its start at deadwax: oldest first, in batches of at most
//    PlayHistory.postMax. A batch taken (any 2xx, whatever its body says) or refused with another 4xx is forgotten -
//    each start only while it is as it was sent: one counted while its batch was on its way stays, and goes again
//    counted (deadwax ORs `counted` in; its scrobble may have marked a row that wasn't there yet). A 401 holds
//    everything for the same person's next sign-in. No answer, a 5xx, a 408 or a 429 stops the starts until
//    PlayHistory.retryAfter (30 s doubling to 10 min) or the next start - the plays still go.
//  - THEN THE PLAYS, one at a time, oldest first (PendingPlays): forgotten on a 2xx or another 4xx; a 401, a 5xx or
//    no answer stops them until the next send.
//  - NO STORE (it couldn't be opened, or none is yet): a start is held here, by whose it is (`loose`, the newest
//    PlayHistory.ownKept each), put into their store once it opens - or, while none will, sent from here as the web
//    sends its own, by the same rules. Never lost for want of a store.
//  - ONE SEND AT A TIME: a send asked for meanwhile is made once it ends.
//
// One thread (the App's main), as ResumeController: every answer handed back on it.

/// Whose a store is, and who a send goes as: the server (ServerAddress's key) and the person - /me's user with logins
/// on, "local" with them off.
public struct KeptOwner: Hashable, Sendable, CustomStringConvertible {
    public let server: String
    public let person: String

    public init(server: String, person: String) {
        self.server = server
        self.person = person
    }

    /// Whose store /me names: the person signed in, or "local" with logins off.
    public static func person(_ me: Me) -> String {
        me.loginsOn ? me.user : "local"
    }

    /// Who is signed in on `server` now (its key) - nil with no server or no /me.
    public static func of(server: String?, me: Me?) -> KeptOwner? {
        guard let server, let me else { return nil }
        return KeptOwner(server: server, person: person(me))
    }

    public var description: String { "\(person) on \(server)" }
}

/// The store open now: whose, and its database.
public struct KeptStore {
    public let owner: KeptOwner
    public let database: DownloadDatabase

    public init(owner: KeptOwner, database: DownloadDatabase) {
        self.owner = owner
        self.database = database
    }
}

/// What sends now, and as whom - asked for again before every request. Each send answers its status once (nil: no
/// answer at all), on the thread the sender runs on.
public struct KeptLine {
    public let owner: KeptOwner
    public let sendStarts: ([Played], @escaping (Int?) -> Void) -> Void
    public let sendPlay: (DownloadDatabase.KeptPlay, @escaping (Int?) -> Void) -> Void

    public init(owner: KeptOwner, sendStarts: @escaping ([Played], @escaping (Int?) -> Void) -> Void,
                sendPlay: @escaping (DownloadDatabase.KeptPlay, @escaping (Int?) -> Void) -> Void) {
        self.owner = owner
        self.sendStarts = sendStarts
        self.sendPlay = sendPlay
    }

    /// A request's status as the sender reads it: 200 when `send` returned, the answer's status when it threw one
    /// (APIFailure), nil for none at all.
    public static func status(_ send: () async throws -> Void) async -> Int? {
        do {
            try await send()
            return 200
        } catch let failure as APIFailure {
            return failure.answer?.status
        } catch {
            return nil
        }
    }
}

/// The App, as the sender reads and tells it.
public struct KeptSendWorld {
    /// The store open now - nil while none is.
    public var openStore: () -> KeptStore?
    /// What sends now - nil while nothing may (offline, not ready, a sign-in over the app, no client, no one signed in).
    public var line: () -> KeptLine?
    /// The next send, `ms` from now (one timer: a new one replaces the last).
    public var retry: (Int64) -> Void
    /// A line for the downloads log.
    public var note: (String) -> Void
    /// What waits changed: the counts again.
    public var changed: () -> Void

    public init(openStore: @escaping () -> KeptStore?, line: @escaping () -> KeptLine?, retry: @escaping (Int64) -> Void,
                note: @escaping (String) -> Void, changed: @escaping () -> Void) {
        self.openStore = openStore
        self.line = line
        self.retry = retry
        self.note = note
        self.changed = changed
    }
}

public final class KeptSender {
    /// A send is on its way.
    public private(set) var sending = false
    /// Sends of starts that stopped in a row - the next try's wait (PlayHistory.retryAfter).
    public private(set) var failures = 0
    /// Starts with no store to keep them in, by whose they are, oldest first.
    public private(set) var loose: [KeptOwner: [Played]] = [:]

    private let world: KeptSendWorld
    private var again = false

    public init(world: KeptSendWorld) {
        self.world = world
    }

    // MARK: what the App tells it

    /// A song begun, `owner`'s (nil: no one signed in - nobody's to keep): into their store when it is the one open,
    /// else held here; then sent, if it can be.
    public func keep(_ played: Played, owner: KeptOwner?) {
        guard let owner else {
            world.note("a start with no one signed in: not kept")
            return
        }
        if let store = world.openStore(), store.owner == owner, (try? store.database.keepStart(played)) != nil {
            // kept
        } else {
            var held = loose[owner] ?? []
            held.append(played)
            if held.count > PlayHistory.ownKept { held.removeFirst(held.count - PlayHistory.ownKept) }
            loose[owner] = held
        }
        world.changed()
        send()
    }

    /// A play counted: its start, wherever it waits, marked counted - it goes counted (deadwax ORs it in).
    public func counted(songID: String, at: Int64) {
        if let store = world.openStore() { try? store.database.countStart(songID: songID, at: at) }
        for (owner, held) in loose { loose[owner] = PlayHistory.countedIn(held, songID: songID, at: at) }
    }

    /// The starts held here for `owner`.
    public func looseCount(_ owner: KeptOwner?) -> Int {
        owner.flatMap { loose[$0]?.count } ?? 0
    }

    /// The store let go (another person, signed out): the failures' count starts again with the next.
    public func storeClosed() {
        failures = 0
    }

    /// Everything waiting sent, as far as it can be now. One at a time: asked for meanwhile, made once this ends.
    public func send() {
        if sending {
            again = true
            return
        }
        sending = true
        again = false
        begin()
    }

    // MARK: the run

    private func begin() {
        guard let line = world.line() else { return finish() }
        let owner = line.owner
        if let store = world.openStore() {
            // the store open isn't the person a request would go as: nothing, until the App has moved it over
            guard store.owner == owner else { return finish() }
            adopt(owner, into: store.database)
            starts(owner, store.database)
        } else {
            looseStarts(owner)
        }
    }

    /// What may send as `owner` now - nil while nothing may, or it would go as someone else.
    private func line(as owner: KeptOwner) -> KeptLine? {
        guard let line = world.line(), line.owner == owner else { return nil }
        return line
    }

    /// `database` is still the open store, and `owner`'s.
    private func open(_ database: DownloadDatabase, _ owner: KeptOwner) -> Bool {
        guard let store = world.openStore() else { return false }
        return store.database === database && store.owner == owner
    }

    /// The starts held here for `owner`, into their store now it is open (those it won't take stay held).
    private func adopt(_ owner: KeptOwner, into database: DownloadDatabase) {
        guard let held = loose[owner], !held.isEmpty else { return }
        var left: [Played] = []
        for played in held where (try? database.keepStart(played)) == nil { left.append(played) }
        loose[owner] = left.isEmpty ? nil : left
        world.note("starts kept with no store: \(held.count - left.count) put in it")
        world.changed()
    }

    private func starts(_ owner: KeptOwner, _ database: DownloadDatabase) {
        guard open(database, owner), let line = line(as: owner) else { return finish() }
        let batch = (try? database.keptStarts(limit: PlayHistory.postMax)) ?? []
        guard !batch.isEmpty else { return plays(owner, database, nil) }
        line.sendStarts(batch.map(\.played)) { [self] status in
            switch PlayHistory.after(status: status) {
            case .sent, .dropped:
                failures = 0
                //? (a store that can't forget them stops here, rather than send them again and again)
                guard let gone = try? database.forgetStarts(batch) else { return plays(owner, database, nil) }
                //? the log is the downloads' 50 lines: a start sent as it is made isn't news; a backlog, a refusal or
                //? one that counted on its way is
                if let status, !(200..<300).contains(status) {
                    world.note("starts refused (\(status)): \(gone) let go")
                } else if batch.count > 1 {
                    world.note("starts sent: \(batch.count)")
                }
                if gone < batch.count { world.note("starts counted on their way: \(batch.count - gone) to go again") }
                world.changed()
                starts(owner, database)
            case .held:
                finish()
            case .stopped:
                stopped(status)
                plays(owner, database, nil)
            }
        }
    }

    private func plays(_ owner: KeptOwner, _ database: DownloadDatabase, _ list: [DownloadDatabase.KeptPlay]?) {
        guard open(database, owner), let line = line(as: owner) else { return finish() }
        let waiting = list ?? ((try? database.keptPlays()) ?? [])
        guard let play = waiting.first else { return finish() }
        line.sendPlay(play) { [self] status in
            switch PendingPlays.after(status: status) {
            case .sent, .dropped:
                try? database.forgetPlay(play.id)
                world.changed()
                plays(owner, database, Array(waiting.dropFirst()))
            case .held, .stopped:
                finish()
            }
        }
    }

    /// No store: the starts held for `owner` sent from here, a batch at a time - until a store opens (the next send
    /// puts what is left into it).
    private func looseStarts(_ owner: KeptOwner) {
        guard world.openStore() == nil, let line = line(as: owner) else { return finish() }
        let batch = Array((loose[owner] ?? []).prefix(PlayHistory.postMax))
        guard !batch.isEmpty else { return finish() }
        line.sendStarts(batch) { [self] status in
            switch PlayHistory.after(status: status) {
            case .sent, .dropped:
                failures = 0
                // each only as it was sent: one counted meanwhile stays, to go again counted
                var held = loose[owner] ?? []
                for sent in batch {
                    if let at = held.firstIndex(where: { Self.same($0, sent) }) { held.remove(at: at) }
                }
                loose[owner] = held.isEmpty ? nil : held
                if let status, !(200..<300).contains(status) { world.note("starts refused (\(status)): \(batch.count) let go") }
                world.changed()
                looseStarts(owner)
            case .held:
                finish()
            case .stopped:
                stopped(status)
                finish()
            }
        }
    }

    private func stopped(_ status: Int?) {
        failures += 1
        let wait = PlayHistory.retryAfter(failures)
        world.note("starts not sent (\(status.map(String.init) ?? "no answer")): again in \(wait / 1000) s")
        world.retry(wait)
    }

    private func finish() {
        sending = false
        world.changed()
        if again {
            again = false
            send()
        }
    }

    /// The same start, as it was: its moment, song, queue and entry (ids by UTF-16 unit, as the web compares them) and
    /// whether it had counted.
    static func same(_ a: Played, _ b: Played) -> Bool {
        a.at == b.at && a.counted == b.counted && a.entry == b.entry && WebText.same(a.song.id, b.song.id)
            && (a.queue == nil) == (b.queue == nil) && WebText.same(a.queue ?? "", b.queue ?? "")
    }
}
