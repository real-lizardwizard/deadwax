import Foundation
import Testing
@testable import DeadwaxCore

/// The library's shuffle's feed carried out (slice 3b's review): ShuffleFeedLoop - PlayerModel's own steps, in Core -
/// driven over the real QueueController and a fake engine (QueueControllerTests' FakeEngine), with answers landing late
/// or failing, retries, the next song scheduled (D4's held edits), joins and Next, Play Next, Repeat moved. Does every
/// song of the order play once a round, under Repeat Off and All, none twice and none lost - and does a round never
/// begin with the song that ended the last? The reviewer's property test, brought in: it passed on 50f60b6 and failed
/// with `look`'s page offset broken. Plus what stopping lets go.
@Suite struct ShuffleFeedLoopTests {
    /// The world the feed runs in: deadwax's orders, the asks out, the retry's timer, what was heard.
    private final class World {
        let engine = FakeEngine()
        let controller: QueueController
        let feed = ShuffleFeedLoop()
        let rng: Seeded
        /// the order's songs, s1...sN
        let all: [String]
        /// deadwax's orders, by token
        var orders: [String: [String]] = [:]
        var made = 0
        /// the asks made, oldest first
        var pending: [FeedAsk] = []
        /// the retry's timer is running
        var retryDue = false
        /// the order's songs heard, in order (songs added by Play Next not counted)
        var heard: [String] = []
        var lastKey = -1
        var notices = 0
        /// the songs handed over before each extension (PlayerModel shelves them)
        var added = 0
        /// Play Next, Repeat One and back, now and then
        var wobble = false
        var extras = 0
        /// the engine joined into the next song and hasn't said so yet: the controller a song behind until it does
        var lagging = false

        init(total: Int, mode: Repeat, seed: Int64) {
            rng = Seeded(seed)
            all = (1...total).map { (n: Int) -> String in "s\(n)" }
            controller = QueueController(engine: engine, repeat: mode, random: rng.next)
            controller.onChange = { [unowned self] (_: UpNextQueue) -> Void in self.changed() }
            controller.onRepeatChange = { [unowned self] (_: Repeat) -> Void in self.feed.look(self.controller) }
            feed.send = { [unowned self] (ask: FeedAsk) -> Void in self.pending.append(ask) }
            feed.say = { [unowned self] (_: String) -> Void in self.notices += 1 }
            feed.adding = { [unowned self] (songs: [Song]) -> Void in self.added += songs.count }
            feed.retry = { [unowned self] (on: Bool) -> Void in self.retryDue = on }
        }

        func song(_ id: String) -> Song { Song(id: id, title: id, album: "a", albumId: "al") }

        /// deadwax makes an order: every song once, shuffled.
        func newOrder() -> (token: String, ids: [String]) {
            made += 1
            var ids = all
            for place in stride(from: ids.count - 1, to: 0, by: -1) { ids.swapAt(place, rng.pick(place + 1)) }
            let token = "t\(made)"
            orders[token] = ids
            return (token, ids)
        }

        /// The Library's tap: the first page, as a library's shuffle.
        func start() {
            let order = newOrder()
            let first = Array(order.ids.prefix(200))
            let tracks = first.map { (id: String) -> QueueTrack in ShuffleFeed.track(song(id), level: .track) }
            controller.playTracks(tracks, start: 0, shuffle: false,
                                  paged: Paged(token: order.token, total: order.ids.count, fetched: first.count,
                                               scope: .yours, level: .track))
        }

        /// The queue changed: the song heard counted once per entry, and the feed looked (PlayerModel's queueChanged).
        func changed() {
            let queue = controller.queue
            if let marks = queue.upNext?.marks, marks.indices.contains(queue.index), marks[queue.index].key != lastKey,
               let current = queue.current {
                lastKey = marks[queue.index].key
                if marks[queue.index].from == .source { heard.append(current.id) }
            }
            feed.look(controller)
        }

        /// The oldest ask answered - or failed, at `failRate`.
        func answerOne(failRate: Double) {
            guard !pending.isEmpty else { return }
            let ask = pending.removeFirst()
            if rng.next() < failRate {
                feed.failed(ask, into: controller)
                return
            }
            switch ask.kind {
            case .page(let offset):
                guard let ids = orders[ask.token] else {
                    feed.gone(ask, into: controller)
                    return
                }
                let page = Array(ids[offset..<min(ids.count, offset + 200)])
                feed.page(ask, songs: page.map(song), into: controller)
            case .fresh:
                let order = newOrder()
                let first = ShuffleStart(token: order.token, total: order.ids.count,
                                         songs: Array(order.ids.prefix(200)).map(song))
                feed.fresh(ask, first, into: controller, random: rng.next)
            }
        }

        /// The retry's timer fires.
        func retryFires() {
            retryDue = false
            feed.retryDue(controller)
        }

        /// Everything out answered, the retries with them.
        func settle() {
            for _ in 0..<50 {
                answerOne(failRate: 0)
                if retryDue { retryFires() }
            }
        }

        /// One moment: maybe Play Next or Repeat moved, maybe an answer lands, maybe the retry fires - all of them
        /// perhaps while the engine has joined into a song it hasn't said yet - maybe the next song is scheduled (an
        /// edit then waits, D4); then the song moves on, by a join (said at once, or the next moment) or Next.
        func step(failRate: Double, holdRate: Double) {
            if wobble {
                let roll = rng.next()
                if roll < 0.03 {
                    extras += 1
                    controller.playNext([simTrack("x\(extras)")])
                } else if roll < 0.05 {
                    controller.setRepeat(.one)
                } else if roll < 0.08 && controller.repeatMode == .one {
                    controller.setRepeat(.all)
                }
            }
            if rng.next() < 0.5 { answerOne(failRate: failRate) }
            if retryDue && rng.next() < 0.3 { retryFires() }
            if lagging {
                // the engine says so: the controller catches up
                lagging = false
                controller.tick(heard: 0)
            }
            engine.nextScheduled = rng.next() < holdRate
            if rng.next() < 0.5 && engine.index < engine.entries.count - 1 {
                engine.join()
                if rng.next() < 0.7 { controller.tick(heard: 0) } else { lagging = true }
            } else {
                controller.next()
            }
        }

        var atTheEnd: Bool { controller.queue.index == controller.queue.tracks.count - 1 }
    }

    @Test(arguments: Array(Int64(1)...Int64(25)))
    func everySongOnceUnderRepeatOff(seed: Int64) {
        let world = World(total: 1037, mode: .off, seed: seed)
        world.start()
        var steps = 0
        while steps < 20000 {
            let before = world.controller.queue.index
            world.step(failRate: 0.2, holdRate: 0.3)
            steps += 1
            let stuck = world.controller.queue.index == before && world.atTheEnd
            if stuck && world.pending.isEmpty && !world.retryDue { break }
            // the queue at its end: everything out lets land
            if stuck { world.settle() }
        }
        let round = world.heard
        #expect(round.count == 1037, "heard \(round.count)")
        #expect(Set(round).count == round.count, "a song twice")
        #expect(Set(round) == Set(world.all), "a song lost")
    }

    @Test(arguments: Array(Int64(1)...Int64(60)))
    func underRepeatAllEachRoundIsWholeWhateverMoves(seed: Int64) {
        let world = World(total: 437, mode: .all, seed: seed)
        world.wobble = true
        world.start()
        var steps = 0
        while world.heard.count < 437 * 3 && steps < 30000 {
            world.step(failRate: 0.15, holdRate: 0.3)
            steps += 1
            if world.atTheEnd { world.settle() }
        }
        let heard = world.heard
        #expect(heard.count >= 437 * 3, "stalled at \(heard.count)")
        guard heard.count >= 437 * 3 else { return }
        for round in 0..<3 {
            let part = Array(heard.dropFirst(round * 437).prefix(437))
            #expect(Set(part) == Set(world.all) && part.count == 437, "round \(round): \(Set(part).count) different songs")
        }
        for round in 1..<3 {
            #expect(heard[round * 437] != heard[round * 437 - 1], "round \(round) began with the song that ended the last")
        }
    }

    @Test func anOrderDeadwaxLostStartsOverAndSaysSoOnce() {
        let world = World(total: 450, mode: .off, seed: 7)
        world.start()
        // deadwax restarted: the order it gave is gone
        world.orders = [:]
        for _ in 0..<160 { world.controller.next() }
        world.answerOne(failRate: 0)
        #expect(world.pending.count == 1, "the 404: a fresh order asked")
        world.answerOne(failRate: 0)
        #expect(world.notices == 1 && world.controller.queue.tracks.count == 400)
        #expect(world.added == 200, "the fresh order's songs handed over before they're queued")
        #expect(world.controller.queue.upNext?.paged?.token == "t2")
    }

    @Test func aRetryDueAsksAgainFromTheSamePlace() {
        let world = World(total: 450, mode: .off, seed: 3)
        world.start()
        for _ in 0..<160 { world.controller.next() }
        #expect(world.pending.count == 1, "49 ahead: the next page asked")
        world.answerOne(failRate: 1)
        #expect(world.retryDue && world.pending.isEmpty)
        // the song moving on meanwhile asks nothing: the failed ask waits for its retry (useShuffleFeed.ts's)
        world.controller.next()
        #expect(world.pending.isEmpty)
        world.retryFires()
        #expect(world.pending.count == 1 && !world.retryDue)
        guard case .page(let offset)? = world.pending.first?.kind else {
            Issue.record("the retry asked for no page")
            return
        }
        #expect(offset == 200 && world.pending.first?.token == "t1")
    }

    @Test func stoppingLetsEveryAskAndTheRetryGo() {
        let world = World(total: 450, mode: .off, seed: 3)
        world.start()
        for _ in 0..<160 { world.controller.next() }
        // a failure, its retry waiting - then the player stops (PlayerModel.stop; its reset for a new person too)
        world.answerOne(failRate: 1)
        #expect(world.retryDue)
        world.feed.stopped()
        #expect(!world.retryDue, "the retry called off")
        // the retry's timer firing after the stop anyway (PlayerModel hands it no queue): nothing asked
        world.feed.retryDue(nil)
        #expect(world.pending.isEmpty)
        // another shuffle's ask out, then a stop: its answer dropped
        world.start()
        for _ in 0..<160 { world.controller.next() }
        #expect(world.pending.count == 1)
        world.feed.stopped()
        let before = world.controller.queue.tracks.count
        world.answerOne(failRate: 0)
        #expect(world.controller.queue.tracks.count == before, "an answer after the stop: dropped")
    }

    @Test func aNewAskCallsOffTheRetry() {
        let world = World(total: 450, mode: .off, seed: 5)
        world.start()
        for _ in 0..<160 { world.controller.next() }
        world.answerOne(failRate: 1)
        #expect(world.retryDue)
        // another shuffle while the retry waits: its ask goes out, and the old retry is called off
        world.start()
        for _ in 0..<160 { world.controller.next() }
        #expect(world.pending.count == 1 && world.pending.first?.token == "t2" && !world.retryDue)
    }
}
