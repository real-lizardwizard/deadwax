import Foundation
import Testing
@testable import DeadwaxCore

/// The App as KeptSender sees it: a store (a real DownloadDatabase in a folder of its own) and whose it is, who is
/// signed in, whether anything may go - and every request held until the test answers it, as deadwax would, later.
final class FakeKeptWorld {
    enum Sent: Equatable {
        case starts([Played])
        case play(String, Int64)
    }

    struct Request {
        let owner: KeptOwner
        let sent: Sent
        let done: (Int?) -> Void
    }

    let folder: URL
    var store: KeptStore?
    var signedIn: KeptOwner?
    var online = true
    private(set) var asked: [Request] = []
    private(set) var log: [(KeptOwner, Sent)] = []
    private(set) var retries: [Int64] = []
    private(set) var notes: [String] = []
    private(set) var changes = 0

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-kept-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// `owner`'s store opened (a database of its own) - and, unless said, them signed in.
    @discardableResult
    func open(_ owner: KeptOwner, signIn: Bool = true) throws -> DownloadDatabase {
        let path = folder.appendingPathComponent("\(owner.person)-\(UUID().uuidString).sqlite").path
        let database = try DownloadDatabase(path: path)
        store = KeptStore(owner: owner, database: database)
        if signIn { signedIn = owner }
        return database
    }

    var world: KeptSendWorld {
        KeptSendWorld(
            openStore: { [unowned self] in store },
            line: { [unowned self] in
                guard online, let owner = signedIn else { return nil }
                return KeptLine(owner: owner, sendStarts: { [unowned self] starts, done in
                    asked.append(Request(owner: owner, sent: .starts(starts), done: done))
                    log.append((owner, .starts(starts)))
                }, sendPlay: { [unowned self] play, done in
                    asked.append(Request(owner: owner, sent: .play(play.songID, play.timeMs), done: done))
                    log.append((owner, .play(play.songID, play.timeMs)))
                })
            },
            retry: { [unowned self] ms in retries.append(ms) },
            note: { [unowned self] line in notes.append(line) },
            changed: { [unowned self] in changes += 1 })
    }

    /// The request out, answered `status` (nil: no answer at all).
    func answer(_ status: Int?) {
        let request = asked.removeFirst()
        request.done(status)
    }

    /// What the request out sends (nil: none).
    var out: Sent? { asked.first?.sent }
}

@Suite struct KeptSenderTests {
    private let t: Int64 = 1_800_000_000_000
    private let ann = KeptOwner(server: "http://deadwax.test:8090", person: "ann")
    private let bob = KeptOwner(server: "http://deadwax.test:8090", person: "bob")

    private func start(_ id: String, _ at: Int64, counted: Bool = false) -> Played {
        Played(at: at, counted: counted, queue: "q", entry: 0, song: rTrack(id))
    }

    private func ids(_ sent: FakeKeptWorld.Sent?) -> [String] {
        guard case .starts(let starts)? = sent else { return [] }
        return starts.map(\.song.id)
    }

    // MARK: the order, and the batches

    @Test func theStartsGoFirstOldestFirstInBatchesOf500ThenThePlaysOneAtATime() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        for n in (0..<1_201).reversed() { try db.keepStart(start("s\(n)", t + Int64(n))) }
        try db.keepPlay(songID: "p2", timeMs: t + 2)
        try db.keepPlay(songID: "p1", timeMs: t + 1)
        let sender = KeptSender(world: fake.world)
        sender.send()
        #expect(sender.sending)
        var batches: [[String]] = []
        while case .starts? = fake.out {
            batches.append(ids(fake.out))
            fake.answer(200)
        }
        #expect(batches.map(\.count) == [500, 500, 201])
        #expect(batches.flatMap { $0 } == (0..<1_201).map { "s\($0)" })
        #expect(fake.out == .play("p1", t + 1))
        fake.answer(200)
        #expect(fake.out == .play("p2", t + 2))
        fake.answer(204)
        #expect(fake.out == nil && !sender.sending)
        #expect(try db.keptStartCount() == 0 && db.keptPlays().isEmpty)
        #expect(fake.retries.isEmpty && fake.notes.contains("starts sent: 500") && fake.notes.contains("starts sent: 201"))
    }

    @Test func anyTwoHundredIsTakenAndAnotherRefusalLetsTheBatchGo() throws {
        for status in [200, 201, 204, 400, 403, 404, 413, 422] {
            let fake = try FakeKeptWorld()
            let db = try fake.open(ann)
            try db.keepStart(start("a", t))
            try db.keepPlay(songID: "p", timeMs: t)
            let sender = KeptSender(world: fake.world)
            sender.send()
            fake.answer(status)
            #expect(try db.keptStartCount() == 0, "\(status)")
            // the plays go after
            #expect(fake.out == .play("p", t), "\(status)")
            #expect(fake.retries.isEmpty)
            #expect(fake.notes.contains { $0.hasPrefix("starts refused") } == !(200..<300).contains(status))
        }
    }

    @Test func a401HoldsEverythingForTheNextSignIn() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        try db.keepPlay(songID: "p", timeMs: t)
        let sender = KeptSender(world: fake.world)
        sender.send()
        fake.answer(401)
        #expect(fake.out == nil && !sender.sending && fake.retries.isEmpty)
        #expect(try db.keptStartCount() == 1 && db.keptPlays().count == 1)
        // signed in again: they go
        sender.send()
        #expect(ids(fake.out) == ["a"])
    }

    @Test func noAnswerOrABusyDeadwaxWaitsLongerEachTimeAndThePlaysStillGo() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        try db.keepPlay(songID: "p", timeMs: t)
        let sender = KeptSender(world: fake.world)
        for status in [nil, 500, 503, 408, 429] as [Int?] {
            sender.send()
            #expect(ids(fake.out) == ["a"])
            fake.answer(status)
            // the plays still go - this one answered with no answer, which stops them till the next send
            #expect(fake.out == .play("p", t))
            fake.answer(nil)
            #expect(!sender.sending)
        }
        #expect(fake.retries == [30_000, 60_000, 120_000, 240_000, 480_000])
        #expect(sender.failures == 5)
        #expect(try db.keptStartCount() == 1)
        // taken: from 30 s again after the next failure
        sender.send()
        fake.answer(200)
        fake.answer(200)
        try db.keepStart(start("b", t + 1))
        sender.send()
        fake.answer(503)
        #expect(fake.retries.last == 30_000)
        #expect(PlayHistory.retryAfter(9) == 600_000)
    }

    // MARK: counted on its way

    @Test func aStartCountedWhileItsBatchIsOnItsWayGoesAgainCounted() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        try db.keepStart(start("b", t + 1000))
        let sender = KeptSender(world: fake.world)
        sender.send()
        guard case .starts(let first)? = fake.out else { Issue.record("no batch"); return }
        #expect(first.map(\.counted) == [false, false])
        // the play counted, its scrobble perhaps at deadwax before this batch: the row isn't there yet to mark
        sender.counted(songID: "a", at: t)
        fake.answer(200)
        guard case .starts(let again)? = fake.out else { Issue.record("not sent again"); return }
        #expect(again.map(\.song.id) == ["a"] && again[0].counted)
        fake.answer(200)
        #expect(try db.keptStartCount() == 0 && fake.out == nil)
        #expect(fake.notes.contains("starts counted on their way: 1 to go again"))
    }

    @Test func forgettingKeepsOnlyARowCountedSinceItWasRead() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        try db.keepStart(start("b", t + 1, counted: true))
        try db.keepStart(start("c", t + 2))
        let read = try db.keptStarts()
        try db.countStart(songID: "a", at: t)
        try db.countStart(songID: "b", at: t + 1)
        #expect(try db.forgetStarts(read) == 2)
        #expect(try db.keptStarts().map(\.played) == [start("a", t, counted: true)])
        #expect(try db.forgetStarts([]) == 0)
    }

    // MARK: one at a time

    @Test func aSendAskedForMeanwhileIsMadeOnceThisEnds() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepPlay(songID: "p", timeMs: t)
        let sender = KeptSender(world: fake.world)
        sender.send()
        #expect(fake.out == .play("p", t))
        // a start while the play is out: kept, and its send waits for this one
        sender.keep(start("a", t + 5), owner: ann)
        #expect(fake.asked.count == 1)
        #expect(try db.keptStartCount() == 1)
        fake.answer(200)
        #expect(ids(fake.out) == ["a"] && sender.sending)
        fake.answer(200)
        #expect(fake.out == nil && !sender.sending)
        #expect(try db.keptStartCount() == 0)
        // a start while starts are out goes in the same run, after them
        try db.keepStart(start("b", t + 6))
        sender.send()
        sender.keep(start("c", t + 7), owner: ann)
        #expect(ids(fake.out) == ["b"])
        fake.answer(200)
        #expect(ids(fake.out) == ["c"])
        fake.answer(200)
        #expect(fake.out == nil && !sender.sending)
    }

    @Test func offlineOrNotReadyNothingGoes() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        fake.online = false
        let sender = KeptSender(world: fake.world)
        sender.send()
        #expect(fake.asked.isEmpty && !sender.sending)
        fake.online = true
        sender.send()
        #expect(ids(fake.out) == ["a"])
    }

    // MARK: whose

    @Test func nothingGoesAsSomeoneElseThanTheStoresPerson() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        try db.keepPlay(songID: "p", timeMs: t)
        // bob signed in, ann's store still open (the App moves it over a hop later): nothing at all
        fake.signedIn = bob
        let sender = KeptSender(world: fake.world)
        sender.send()
        #expect(fake.log.isEmpty && !sender.sending)
        // the same person on another server is someone else too
        fake.signedIn = KeptOwner(server: "http://other.test:8090", person: "ann")
        sender.send()
        #expect(fake.log.isEmpty)
        fake.signedIn = ann
        sender.send()
        #expect(fake.log.map(\.0) == [ann])
    }

    @Test func aChangeOfPersonMidSendStopsItThere() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        for n in 0..<501 { try db.keepStart(start("s\(n)", t + Int64(n))) }
        try db.keepPlay(songID: "p", timeMs: t)
        let sender = KeptSender(world: fake.world)
        sender.send()
        #expect(fake.asked.first?.owner == ann)
        // bob signs in while ann's first batch is out
        fake.signedIn = bob
        fake.answer(200)
        // ann's batch, sent as ann, forgotten; nothing more - neither her last start nor her play under bob's session
        #expect(fake.asked.isEmpty && !sender.sending)
        #expect(fake.log.allSatisfy { $0.0 == ann } && fake.log.count == 1)
        #expect(try db.keptStartCount() == 1 && db.keptPlays().count == 1)
        // and during the plays
        fake.signedIn = ann
        sender.send()
        fake.answer(200)
        #expect(fake.out == .play("p", t))
        fake.signedIn = bob
        try db.keepPlay(songID: "q", timeMs: t + 1)
        fake.answer(200)
        #expect(fake.asked.isEmpty && fake.log.allSatisfy { $0.0 == ann })
        #expect(try db.keptPlays().map(\.songID) == ["q"])
        // the store moved over to bob's: his, as him
        let bobs = try fake.open(bob)
        try bobs.keepStart(start("b", t))
        sender.send()
        #expect(fake.asked.first?.owner == bob && ids(fake.out) == ["b"])
    }

    @Test func aStoreClosedMidSendStopsItThere() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        try db.keepStart(start("a", t))
        try db.keepPlay(songID: "p", timeMs: t)
        let sender = KeptSender(world: fake.world)
        sender.send()
        fake.store = nil
        fake.answer(200)
        #expect(fake.asked.isEmpty && !sender.sending)
        #expect(try db.keptStartCount() == 0 && db.keptPlays().count == 1)
    }

    // MARK: no store

    @Test func withNoStoreAStartIsHeldAndSentFromHere() throws {
        let fake = try FakeKeptWorld()
        fake.signedIn = ann
        let sender = KeptSender(world: fake.world)
        sender.keep(start("a", t), owner: ann)
        #expect(sender.looseCount(ann) == 1 && ids(fake.out) == ["a"])
        // counted on its way: kept, and sent again counted
        sender.keep(start("b", t + 1), owner: ann)
        sender.counted(songID: "a", at: t)
        fake.answer(200)
        #expect(sender.looseCount(ann) == 2)
        guard case .starts(let again)? = fake.out else { Issue.record("not sent again"); return }
        #expect(again.map(\.song.id) == ["a", "b"] && again.map(\.counted) == [true, false])
        // no answer: held, and tried again later - but the send b's start asked for meanwhile is made now
        fake.answer(nil)
        #expect(sender.looseCount(ann) == 2 && fake.retries == [30_000])
        #expect(ids(fake.out) == ["a", "b"])
        fake.answer(200)
        #expect(sender.looseCount(ann) == 0 && fake.out == nil && !sender.sending)
    }

    @Test func heldStartsGoIntoTheirOwnersStoreOnceItOpens() throws {
        let fake = try FakeKeptWorld()
        fake.signedIn = ann
        fake.online = false
        let sender = KeptSender(world: fake.world)
        sender.keep(start("a", t), owner: ann)
        sender.keep(start("b", t + 1), owner: bob)
        #expect(sender.looseCount(ann) == 1 && sender.looseCount(bob) == 1 && fake.asked.isEmpty)
        let db = try fake.open(ann)
        fake.online = true
        sender.send()
        #expect(sender.looseCount(ann) == 0 && sender.looseCount(bob) == 1)
        #expect(ids(fake.out) == ["a"])
        #expect(try db.keptStartCount() == 1)
        fake.answer(200)
        #expect(try db.keptStartCount() == 0)
        // bob's never go as ann, nor into her store
        #expect(fake.log.count == 1)
    }

    @Test func withNoStoreTheNewest500AreHeldAndNoOnesNone() throws {
        let fake = try FakeKeptWorld()
        fake.online = false
        let sender = KeptSender(world: fake.world)
        for n in 0..<502 { sender.keep(start("s\(n)", t + Int64(n)), owner: ann) }
        #expect(sender.loose[ann]?.count == PlayHistory.ownKept && sender.loose[ann]?.first?.song.id == "s2")
        sender.keep(start("x", t), owner: nil)
        #expect(sender.loose.count == 1 && fake.notes.last == "a start with no one signed in: not kept")
    }

    @Test func aStartIntoAnotherPersonsOpenStoreIsHeldInstead() throws {
        let fake = try FakeKeptWorld()
        let db = try fake.open(ann)
        fake.online = false
        let sender = KeptSender(world: fake.world)
        sender.keep(start("b", t), owner: bob)
        #expect(try db.keptStartCount() == 0 && sender.looseCount(bob) == 1)
    }

    // MARK: the status a request answers

    @Test func aStatusIsTheAnswersOrNoneAtAll() async {
        #expect(await KeptLine.status {} == 200)
        #expect(await KeptLine.status { throw APIFailure.other("no") } == nil)
        #expect(await KeptLine.status { throw CancellationError() } == nil)
        let (deadwax, transport) = client()
        transport.answer("/deadwax/me/history", 503, #"{"detail":"deadwax couldn't keep what you played just now"}"#)
        #expect(await KeptLine.status { _ = try await deadwax.recordStarts([start("a", t)]) } == 503)
    }

    @Test func aTakenBatchIsTakenWhateverItsAnswerSays() async throws {
        let (deadwax, transport) = client()
        for (status, body) in [(200, #"{"taken":1,"skipped":0}"#), (200, "not json"), (200, "{}"), (201, ""), (204, "")] {
            transport.answer("/deadwax/me/history", status, body)
            let taken = try await deadwax.recordStarts([start("a", t)])
            #expect(taken == (body.contains("taken") ? HistoryTaken(taken: 1, skipped: 0) : nil), "\(status) \(body)")
        }
        #expect(transport.last?.method == "POST" && transport.last?.headers["Content-Type"] == "application/json")
    }

    @Test func whoseAStoreIs() {
        let on = Me(user: "ann", admin: false, auth: "on")
        let off = Me(user: "deadwax", admin: true, auth: "off")
        #expect(KeptOwner.of(server: "s", me: on) == KeptOwner(server: "s", person: "ann"))
        #expect(KeptOwner.of(server: "s", me: off) == KeptOwner(server: "s", person: "local"))
        #expect(KeptOwner.of(server: nil, me: on) == nil && KeptOwner.of(server: "s", me: nil) == nil)
    }
}
