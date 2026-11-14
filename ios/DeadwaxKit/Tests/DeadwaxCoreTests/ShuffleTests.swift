import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's Shuffle (phase4-library.md 2.7, 2.8): its first page asked ahead (ShuffleSongs.tsx's rules), the feed
/// that brings in the rest (useShuffleFeed.ts's - driven as ui/test/shuffle.sim.cjs drives the hook), the two answers,
/// the two calls, and the offline shuffle of what's on the phone. Held by hand until slice 5's exporter (question 24).
@Suite struct ShuffleTests {
    private static func song(_ n: Int) -> Song {
        Song(id: "s\(n)", title: "Song \(n)", album: "Album \(n % 7)", albumId: "al\(n % 7)", artist: "Artist", duration: 200,
             suffix: "flac", contentType: "audio/flac", coverArt: "al-\(n % 7)")
    }

    /// shuffle.sim's order: s1...s450.
    private static let order: [Song] = (1...450).map(song)

    /// A library's shuffle as the Library's tap plays it: the first `count` songs of the order, from the first.
    private static func shuffle(_ count: Int = 200, total: Int = 450, token: String = "t1", level: Level? = nil) -> UpNextQueue {
        let tracks = order.prefix(count).map { ShuffleFeed.track($0, level: level) }
        return startUpNext(Array(tracks), start: 0,
                           paged: Paged(token: token, total: total, fetched: count, scope: .store, level: level))
    }

    /// The ids, in order - outside a key path, for CI's older Swift.
    private static func ids(_ tracks: [QueueTrack]) -> [String] { tracks.map { (track: QueueTrack) -> String in track.id } }
    private static func ids(_ songs: [Song]) -> [String] { songs.map { (song: Song) -> String in song.id } }

    /// The step's tracks added as PlayerModel adds them (QueueController.extendQueue's withMore).
    private static func carried(_ queue: UpNextQueue, _ step: FeedStep) -> UpNextQueue {
        guard case .extend(let token, let tracks, let next, _) = step else { return queue }
        return withMore(queue, token: token, tracks: tracks, next: next)
    }

    // MARK: the numbers and words, named with their sources

    @Test func theNumbersAndWordsAreTheWebs() {
        #expect(ShuffleFeed.below == 50 && ShuffleFeed.retrySeconds == 30)
        #expect(ShuffleAhead.freshSeconds == 600)
        #expect(ShuffleWords.shuffle == "Shuffle")
        #expect(ShuffleWords.gettingReady == "Getting ready\u{2026}")
        #expect(ShuffleWords.unready == "Couldn't get your songs ready to shuffle")
        #expect(ShuffleWords.startedOver == "Your shuffle started over - deadwax no longer had its order")
        #expect(ShuffleWords.unready(status: 413, detail: "Your library is too big to shuffle here")
                == "Your library is too big to shuffle here")
        #expect(ShuffleWords.unready(status: 413, detail: nil) == ShuffleWords.unready)
        #expect(ShuffleWords.unready(status: 502, detail: "Navidrome didn't answer") == ShuffleWords.unready)
        #expect(ShuffleWords.unready(status: nil, detail: nil) == ShuffleWords.unready)
    }

    // MARK: the pure part

    @Test func aSongIsQueuedWithItsAlbumAsTheAnswerNamesIt() {
        let track = ShuffleFeed.track(Self.song(3), level: .track)
        #expect(track.id == "s3" && track.title == "Song 3" && track.album == "Album 3" && track.albumId == "al3")
        #expect(track.coverArt == "al-3" && track.duration == 200 && track.level == .track)
        let bare = ShuffleFeed.track(Song(id: "x"), level: nil)
        #expect(bare.albumId == "" && bare.album == "" && bare.title == "" && bare.level == nil,
                "shuffledTrack: an album id of \"\", never the song's")
    }

    @Test func startingElsewhere() { // shuffle.sim.cjs's own three, and the edges
        let three = (1...3).map { ShuffleFeed.track(Self.song($0), level: nil) }
        #expect(Self.ids(ShuffleFeed.startingElsewhere(three, ending: "s1", random: { () -> Double in 0 })) == ["s2", "s1", "s3"])
        #expect(Self.ids(ShuffleFeed.startingElsewhere(three, ending: "s9")) == ["s1", "s2", "s3"])
        #expect(Self.ids(ShuffleFeed.startingElsewhere([three[0]], ending: "s1")) == ["s1"])
        #expect(Self.ids(ShuffleFeed.startingElsewhere(three, ending: "s1", random: { () -> Double in 0.99 })) == ["s3", "s2", "s1"])
        #expect(Self.ids(ShuffleFeed.startingElsewhere(three, ending: "s1", random: { () -> Double in 1 })) == ["s3", "s2", "s1"],
                "a random of 1 stays in range")
        #expect(Self.ids(ShuffleFeed.startingElsewhere(three, ending: nil)) == ["s1", "s2", "s3"])
        let same = [three[0], three[0]]
        #expect(Self.ids(ShuffleFeed.startingElsewhere(same, ending: "s1")) == ["s1", "s1"], "nothing else to start with")
        let later = [three[0], three[0], three[2]]
        #expect(Self.ids(ShuffleFeed.startingElsewhere(later, ending: "s1", random: { () -> Double in 0 })) == ["s3", "s1", "s1"],
                "a later copy of the song ending is no start")
    }

    @Test func songsAheadCountsTheListsSongsAfterTheOnePlaying() {
        let queue = Self.shuffle()
        #expect(ShuffleFeed.songsAhead(queue) == 199)
        #expect(ShuffleFeed.songsAhead(queue.at(149)) == 50 && ShuffleFeed.songsAhead(queue.at(150)) == 49)
        #expect(ShuffleFeed.songsAhead(queue.at(199)) == 0)
        let added = withNext(queue.at(150), [simTrack("n1"), simTrack("n2")])
        #expect(ShuffleFeed.songsAhead(added) == 49, "songs played next are no songs of the list")
        #expect(ShuffleFeed.songsAhead(.empty) == 0)
        #expect(ShuffleFeed.songsAhead(UpNextQueue(tracks: simAlbum(3), index: 0)) == 0, "a queue with no account")
    }

    // MARK: the feed (shuffle.sim.cjs's scenarios) - every mutating call made before its #expect

    @Test func theFeedAsksForTheNextPageUnder50Ahead() {
        var feed = ShuffleFeedRun()
        let plain = feed.look(startUpNext(simAlbum(3), start: 0), repeat: .off)
        #expect(plain == nil, "no library's shuffle: nothing")
        var queue = Self.shuffle()
        var none = feed.look(queue, repeat: .off)
        #expect(none == nil, "199 after the song playing: nothing asked")
        none = feed.look(queue.at(149), repeat: .off)
        #expect(none == nil, "...50 after it: still nothing")
        queue = queue.at(150)
        let ask = feed.look(queue, repeat: .off)
        #expect(ask?.kind == .page(offset: 200) && ask?.token == "t1" && ask?.scope == .store && ask?.ending == "s200",
                "49 after it: the next page, from where the order has got to")
        let twice = feed.look(queue, repeat: .off)
        let repeatAll = feed.look(queue, repeat: .all)
        let repeatOff = feed.look(queue, repeat: .off)
        #expect(twice == nil && repeatAll == nil && repeatOff == nil,
                "one ask at a time, however often it is looked at or Repeat changed meanwhile")
        guard let ask else { return }
        // a page that won't come: asked again later, from the same place - not at the queue's next change
        let failed = feed.failed(ask)
        #expect(failed == .retry)
        let soon = feed.look(queue.at(151), repeat: .off)
        #expect(soon == nil, "the next song: not asked again before FEED_RETRY_MS")
        feed.retried()
        let again = feed.look(queue, repeat: .off)
        #expect(again?.kind == .page(offset: 200) && again?.serial != ask.serial)
        let late = feed.page(ask, songs: [])
        #expect(late == .nothing, "the failed ask's answer, landing late: dropped")
        guard let again else { return }
        let step = feed.page(again, songs: Array(Self.order[200..<400]))
        guard case .extend(let token, let tracks, let next, let notice) = step else {
            Issue.record("a page: \(step)")
            return
        }
        #expect(token == "t1" && tracks.count == 200 && tracks.first?.id == "s201" && next == nil && notice == nil)
        queue = Self.carried(queue, step)
        #expect(queue.upNext?.paged?.fetched == 400 && ShuffleFeed.songsAhead(queue) == 249)
        none = feed.look(queue, repeat: .off)
        #expect(none == nil, "249 ahead")
        queue = queue.at(352)
        let last = feed.look(queue, repeat: .off)
        #expect(last?.kind == .page(offset: 400))
        guard let last else { return }
        let lastStep = feed.page(last, songs: Array(Self.order[400...]))
        queue = Self.carried(queue, lastStep)
        #expect(queue.upNext?.paged?.fetched == 450, "the last page: the order whole")
        queue = queue.at(420)
        none = feed.look(queue, repeat: .off)
        #expect(none == nil, "the whole order in, Repeat off: nothing more")
        none = feed.look(queue, repeat: .one)
        #expect(none == nil, "...nor under Repeat One")
        let round = feed.look(queue, repeat: .all)
        #expect(round?.kind == .fresh(startedOver: false) && round?.ending == "s450",
                "...with Repeat All: a fresh order, as the next round")
        guard let round else { return }
        // the fresh order begins with the song that ends this one: moved later
        let fresh = ShuffleStart(token: "t2", total: 450, songs: [Self.order[449]] + Array(Self.order.prefix(199)))
        let freshStep = feed.fresh(round, fresh, repeat: .all, random: { () -> Double in 0 })
        guard case .extend(let roundToken, let roundTracks, let roundNext, let roundNotice) = freshStep else {
            Issue.record("a fresh round: \(freshStep)")
            return
        }
        #expect(roundToken == "t1" && roundTracks.count == 200 && roundNotice == nil)
        #expect(roundTracks.first?.id == "s1" && roundTracks[1].id == "s450", "swapped with the next place")
        #expect(roundNext == Paged(token: "t2", total: 450, fetched: 0, scope: .store))
        queue = Self.carried(queue, freshStep)
        #expect(queue.upNext?.paged?.token == "t2" && queue.upNext?.marks[450].pass == 1, "as the next time round")
        none = feed.look(queue, repeat: .all)
        #expect(none == nil, "the new round's 229 ahead")
    }

    @Test func aRetryDueAfterAnotherAskLetsNothingGo() {
        var feed = ShuffleFeedRun()
        guard let ask = feed.look(Self.shuffle().at(150), repeat: .off) else {
            Issue.record("no ask")
            return
        }
        let failed = feed.failed(ask)
        #expect(failed == .retry)
        let other = feed.look(Self.shuffle(token: "t2").at(150), repeat: .off)
        #expect(other?.token == "t2", "another shuffle: asked at once")
        feed.retried()
        let twice = feed.look(Self.shuffle(token: "t2").at(150), repeat: .off)
        #expect(twice == nil, "the first's retry, due now, lets the second's ask stand")
    }

    @Test func aShortLastPageNearTheEndAsksTheNextRoundAtOnce() {
        var feed = ShuffleFeedRun()
        var queue = Self.shuffle(200, total: 230).at(190)
        guard let ask = feed.look(queue, repeat: .all) else {
            Issue.record("no ask")
            return
        }
        #expect(ask.kind == .page(offset: 200))
        let step = feed.page(ask, songs: Array(Self.order[200..<230]))
        queue = Self.carried(queue, step)
        #expect(queue.upNext?.paged?.fetched == 230 && ShuffleFeed.songsAhead(queue) == 39)
        let round = feed.look(queue, repeat: .all)
        #expect(round?.kind == .fresh(startedOver: false) && round?.ending == "s230",
                "the order whole with 39 ahead: the next round asked at once")
    }

    @Test func aPageIsQueuedAtTheShufflesLevel() {
        var feed = ShuffleFeedRun()
        let queue = Self.shuffle(level: .track).at(150)
        guard let ask = feed.look(queue, repeat: .off) else {
            Issue.record("no ask")
            return
        }
        let step = feed.page(ask, songs: Array(Self.order[200..<400]))
        guard case .extend(_, let tracks, _, _) = step else {
            Issue.record("a page: \(step)")
            return
        }
        #expect(tracks.count == 200 && tracks.allSatisfy { (track: QueueTrack) -> Bool in track.level == .track })
    }

    @Test func anOrderDeadwaxNoLongerHoldsStartsOverSaidOnce() {
        var feed = ShuffleFeedRun()
        var queue = Self.shuffle(level: .track).at(150)
        guard let ask = feed.look(queue, repeat: .off) else {
            Issue.record("no ask")
            return
        }
        #expect(ask.level == .track)
        let gone = feed.gone(ask)
        guard case .ask(let fresh) = gone else {
            Issue.record("a 404: \(gone)")
            return
        }
        #expect(fresh.kind == .fresh(startedOver: true) && fresh.token == "t1" && fresh.serial == ask.serial)
        let answer = ShuffleStart(token: "t3", total: 450, songs: Array(Self.order.prefix(200)))
        let step = feed.fresh(fresh, answer, repeat: .off)
        guard case .extend(let token, let tracks, let next, let notice) = step else {
            Issue.record("started over: \(step)")
            return
        }
        #expect(token == "t1" && tracks.count == 200 && tracks.allSatisfy { (track: QueueTrack) -> Bool in track.level == .track })
        #expect(next == Paged(token: "t3", total: 450, fetched: 0, scope: .store, level: .track))
        #expect(notice == ShuffleWords.startedOver, "said once, with Repeat off too: it is the rest of this round")
        queue = Self.carried(queue, step)
        #expect(queue.upNext?.paged?.token == "t3" && queue.upNext?.paged?.fetched == 200)
        #expect(queue.upNext?.marks[200].pass == 0, "the rest of this round, not a new one")
    }

    @Test func anEmptyFreshOrderIsAppendedAsNothingAndNotSaid() {
        var feed = ShuffleFeedRun()
        let queue = Self.shuffle().at(150)
        guard let ask = feed.look(queue, repeat: .off) else {
            Issue.record("no ask")
            return
        }
        let gone = feed.gone(ask)
        guard case .ask(let fresh) = gone else {
            Issue.record("a 404: \(gone)")
            return
        }
        let step = feed.fresh(fresh, ShuffleStart(token: "t9", total: 0, songs: []), repeat: .off)
        #expect(step == .extend(token: "t1", tracks: [], next: Paged(token: "t9", total: 0, fetched: 0, scope: .store),
                                notice: nil))
        let after = Self.carried(queue, step)
        #expect(after == queue, "withMore hands the queue back as it was")
        let more = feed.look(after, repeat: .off)
        #expect(more == nil, "and the feed asks for it no more - no loop")
    }

    @Test func anotherShuffleOrNoneLetsAnAskGo() {
        var feed = ShuffleFeedRun()
        let first = Self.shuffle().at(150)
        guard let ask = feed.look(first, repeat: .off) else {
            Issue.record("no ask")
            return
        }
        let other = Self.shuffle(token: "t5").at(150)
        let theirs = feed.look(other, repeat: .off)
        #expect(theirs?.token == "t5" && theirs?.kind == .page(offset: 200), "the other shuffle asks for its own")
        let page = feed.page(ask, songs: Array(Self.order[200..<400]))
        let gone = feed.gone(ask)
        let failed = feed.failed(ask)
        #expect(page == .nothing && gone == .nothing && failed == .nothing, "the first's answers: dropped")
        // none: the other's ask let go too
        let plain = feed.look(startUpNext(simAlbum(3), start: 0), repeat: .off)
        #expect(plain == nil)
        if let theirs {
            let theirPage = feed.page(theirs, songs: Array(Self.order[200..<400]))
            #expect(theirPage == .nothing)
        }
        // a new person
        var reset = ShuffleFeedRun()
        guard let pending = reset.look(first, repeat: .off) else { return }
        reset.reset()
        let landed = reset.page(pending, songs: [])
        #expect(landed == .nothing)
        let afresh = reset.look(first, repeat: .off)
        #expect(afresh?.kind == .page(offset: 200), "and asks afresh after")
    }

    @Test func repeatTurnedOffWhileARoundIsOnItsWay() {
        var feed = ShuffleFeedRun()
        let whole = Self.shuffle(450).at(420)
        guard let round = feed.look(whole, repeat: .all) else {
            Issue.record("no round asked")
            return
        }
        let off = feed.look(whole, repeat: .off)
        #expect(off == nil, "Repeat off: the ask let go")
        let answer = ShuffleStart(token: "t2", total: 450, songs: Array(Self.order.prefix(200)))
        let landed = feed.fresh(round, answer, repeat: .off)
        #expect(landed == .nothing, "its answer, landing anyway: dropped")
        // landing before the look has caught up: dropped unless Repeat is All now
        var racing = ShuffleFeedRun()
        guard let raced = racing.look(whole, repeat: .all) else { return }
        let early = racing.fresh(raced, answer, repeat: .one)
        #expect(early == .nothing)
        let again = racing.look(whole, repeat: .all)
        #expect(again?.kind == .fresh(startedOver: false), "Repeat All again: asked afresh")
    }

    // MARK: the first page, asked ahead (ShuffleSongs.tsx)

    @Test func theFirstPageIsAskedAsTheLibraryShows() {
        var ahead = ShuffleAhead()
        #expect(!ahead.ready && !ahead.empty && ahead.failure == nil)
        let ask = ahead.shown(.yours, now: 1000)
        #expect(ask?.scope == .yours && ask?.playing == nil)
        var none = ahead.shown(.yours, now: 1300)
        #expect(none == nil, "shown again meanwhile: nothing asked twice")
        guard let ask else { return }
        let answer = ShuffleStart(token: "t1", total: 450, songs: Array(Self.order.prefix(200)))
        ahead.answered(ask, answer)
        #expect(ahead.ready && ahead.first == answer)
        none = ahead.shown(.yours, now: 1600)
        #expect(none == nil, "600 s on: still the one")
        let stale = ahead.shown(.yours, now: 1600.5)
        #expect(stale != nil && !ahead.ready, "past SHUFFLE_FRESH_MS: let go, and asked afresh")
        ahead.answered(ask, answer)
        #expect(!ahead.ready, "the older ask's answer: dropped")
    }

    @Test func theTapPlaysThePageAndAsksForTheNextNamingIt() {
        var ahead = ShuffleAhead()
        let early = ahead.take(level: .track, now: 0)
        #expect(early == nil, "nothing in hand: the tap does nothing")
        guard let ask = ahead.shown(.store, now: 0) else { return }
        ahead.answered(ask, ShuffleStart(token: "t1", total: 450, songs: Array(Self.order.prefix(200))))
        guard let taken = ahead.take(level: .track, now: 10) else {
            Issue.record("ready, and nothing taken")
            return
        }
        #expect(taken.tracks.count == 200 && taken.tracks.first?.id == "s1" && taken.tracks.allSatisfy { (track: QueueTrack) -> Bool in track.level == .track })
        #expect(taken.songs == Array(Self.order.prefix(200)))
        #expect(taken.paged == Paged(token: "t1", total: 450, fetched: 200, scope: .store, level: .track))
        #expect(taken.next.playing == "t1" && taken.next.scope == .store, "the next ask names the order played")
        let second = ahead.take(level: .track, now: 11)
        #expect(!ahead.ready && second == nil, "a second tap before the next page: nothing")
        // the next ask fails: the one after names it still
        ahead.failed(taken.next, words: ShuffleWords.unready)
        #expect(ahead.failure == ShuffleWords.unready)
        let retry = ahead.shown(.store, now: 20)
        #expect(retry?.playing == "t1", "named until one gets through")
        guard let retry else { return }
        ahead.answered(retry, ShuffleStart(token: "t2", total: 450, songs: Array(Self.order.prefix(200))))
        #expect(ahead.failure == nil && ahead.ready)
        let off = ahead.take(level: nil, now: 30)
        #expect(off?.next.playing == "t2" && off?.paged.level == nil && off?.tracks.first?.level == nil, "under Off: no level")
        guard let off else { return }
        ahead.answered(off.next, ShuffleStart(token: "t3", total: 450, songs: Array(Self.order.prefix(200))))
        let third = ahead.take(level: nil, now: 40)
        #expect(third?.next.playing == "t3", "t2's ask answered: t2 no longer named, the one just played is")
        guard let third else { return }
        ahead.answered(third.next, ShuffleStart(token: "t4", total: 450, songs: Array(Self.order.prefix(200))))
        let later = ahead.shown(.store, now: 40 + 601)
        #expect(later != nil && later?.playing == nil, "its ask got through: t3 is named no more")
    }

    @Test func aFailureIsAskedAgainTheNextTimeItShows() {
        var ahead = ShuffleAhead()
        guard let ask = ahead.shown(.yours, now: 0) else { return }
        ahead.failed(ask, words: "Your library is too big to shuffle here")
        #expect(ahead.failure == "Your library is too big to shuffle here" && !ahead.ready)
        let again = ahead.shown(.yours, now: 1)
        #expect(again != nil, "at once, the next time it shows")
        ahead.failed(ask, words: "late")
        #expect(ahead.failure == "Your library is too big to shuffle here", "an older ask's failure: dropped")
    }

    @Test func anotherScopeOrPersonStartsAfresh() {
        var ahead = ShuffleAhead()
        guard let yours = ahead.shown(.yours, now: 0) else { return }
        ahead.answered(yours, ShuffleStart(token: "t1", total: 450, songs: Array(Self.order.prefix(200))))
        let store = ahead.shown(.store, now: 5)
        #expect(store?.scope == .store && !ahead.ready && ahead.scope == .store, "another scope: its own first page")
        ahead.answered(yours, ShuffleStart(token: "t1", total: 450, songs: []))
        #expect(ahead.first == nil, "the other scope's answer: dropped")
        ahead.reset()
        guard let store else { return }
        ahead.answered(store, ShuffleStart(token: "t4", total: 9, songs: Array(Self.order.prefix(9))))
        #expect(ahead.first == nil && ahead.scope == nil, "a new person: nothing asked before lands")
        let afresh = ahead.shown(.yours, now: 6)
        #expect(afresh != nil)
    }

    @Test func aLibraryWithNoSongsOffersNoShuffle() {
        var ahead = ShuffleAhead()
        guard let ask = ahead.shown(.yours, now: 0) else { return }
        ahead.answered(ask, ShuffleStart(token: "t1", total: 0, songs: []))
        let taken = ahead.take(level: nil, now: 1)
        #expect(ahead.empty && !ahead.ready && taken == nil)
        var odd = ShuffleAhead()
        guard let oddAsk = odd.shown(.yours, now: 0) else { return }
        odd.answered(oddAsk, ShuffleStart(token: "t1", total: 30, songs: []))
        #expect(!odd.empty && !odd.ready, "a total with no songs in the page: not ready, nor empty")
    }

    // MARK: the answers and the calls

    @Test func theAnswersAreReadLeniently() throws {
        let start = try JSONDecoder().decode(ShuffleStart.self, from: Data("""
            {"token": "t1", "total": 450, "songs": [{"id": "s1", "title": "Roads", "albumId": "al1"}, 7, {"title": "no id"}]}
            """.utf8))
        #expect(start.token == "t1" && start.total == 450 && Self.ids(start.songs) == ["s1"], "an unreadable song left out")
        let bare = try JSONDecoder().decode(ShuffleStart.self, from: Data(#"{"token": "t2"}"#.utf8))
        #expect(bare.total == 0 && bare.songs.isEmpty)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ShuffleStart.self, from: Data(#"{"total": 3}"#.utf8)) }
        let page = try JSONDecoder().decode(ShufflePage.self, from: Data(#"{"total": "x", "songs": [{"id": "s9"}]}"#.utf8))
        #expect(page.total == 0 && Self.ids(page.songs) == ["s9"])
        #expect(try JSONDecoder().decode(ShufflePage.self, from: Data("{}".utf8)) == ShufflePage(total: 0, songs: []))
    }

    @Test func theCallsAskWhatTheRoutesTake() async throws {
        let (client, transport) = client(session: "abc")
        transport.answer("/deadwax/navidrome/shuffle", 200, #"{"token": "t1", "total": 1, "songs": [{"id": "s1"}]}"#)
        transport.answer("/deadwax/navidrome/shuffle/t-1_x", 200, #"{"total": 1, "songs": [{"id": "s2"}]}"#)
        let first = try await client.shuffleStart(scope: .yours)
        #expect(first.token == "t1")
        let plain = try #require(transport.last)
        #expect(plain.method == "GET" && plain.url.path == "/deadwax/navidrome/shuffle" && plain.url.query == "scope=yours")
        _ = try await client.shuffleStart(scope: .store, playing: "t0", claim: true)
        let named = try #require(transport.last)
        #expect(named.url.query == "scope=store&playing=t0&claim=true")
        _ = try await client.shuffleStart(scope: .store, playing: "")
        #expect(transport.last?.url.query == "scope=store", "no order played: none named")
        let page = try await client.shufflePage(token: "t-1_x", offset: 200)
        #expect(Self.ids(page.songs) == ["s2"])
        let paged = try #require(transport.last)
        #expect(paged.url.path == "/deadwax/navidrome/shuffle/t-1_x" && paged.url.query == "offset=200")
        do {
            _ = try await client.shufflePage(token: "gone", offset: 0)
            Issue.record("a 404 answered")
        } catch let failure as APIFailure {
            #expect(failure.status == 404, "thrown, for the feed to start over")
        }
        #expect(Routes.all.contains(Routes.shuffle) && Routes.all.contains(Routes.shufflePage))
    }

    // MARK: offline

    @Test func offlineItShufflesEverySongOnThePhone() {
        let here: [String: Song] = ["s2": Self.song(2), "s1": Self.song(1), "s3": Self.song(3)]
        let songs = ShuffleHere.songs(["s3", "s1", "s9", "s1", "s2"]) { (id: String) -> Song? in here[id] }
        #expect(Self.ids(songs) == ["s1", "s2", "s3"], "each once, a song the phone can't say left out")
        #expect(ShuffleHere.songs([]) { (_: String) -> Song? in nil }.isEmpty)
    }
}
