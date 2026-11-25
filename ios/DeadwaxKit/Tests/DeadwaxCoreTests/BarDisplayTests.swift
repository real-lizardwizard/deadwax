import Testing
@testable import DeadwaxCore

// The player's display (slice R4, notes/ios.md "The redesign, slice R4: the player bar, the mini player and the tab
// bar"): Next names the song that then plays, or nothing; "3 of 11" counts the list's songs this time round; the
// format is what the song in hand says.
@Suite struct BarDisplayTests {
    /// An album of `count` songs, "s1"...: FLAC 16/44.1 unless said otherwise.
    private func album(_ count: Int) -> [QueueTrack] {
        (1...count).map { (n: Int) -> QueueTrack in
            QueueTrack(id: "s\(n)", title: "Song \(n)", artist: "Wilco", album: "Wilco (The Album)", albumId: "al",
                       duration: 200, contentType: "audio/flac", suffix: "flac", sampleRate: 44100, bitDepth: 16,
                       channels: 2)
        }
    }

    /// A fixed draw, so a shuffle is the same every run (the queue's own Fisher-Yates over it).
    private func drawn(_ values: [Double]) -> () -> Double {
        var at = 0
        return {
            defer { at += 1 }
            return values[at % values.count]
        }
    }

    private func playing(_ queue: UpNextQueue, at index: Int) -> UpNextQueue {
        var moved = queue
        moved.index = index
        return moved
    }

    // MARK: Next

    @Test func nextIsTheQueuesNextEntry() {
        let queue = startUpNext(album(11), start: 2)
        #expect(BarDisplay.next(queue, repeat: .off)?.id == "s4")
        #expect(BarDisplay.next(queue, repeat: .all)?.id == "s4")
    }

    @Test func atTheLastSongRepeatOffNamesNothing() {
        let queue = playing(startUpNext(album(11), start: 0), at: 10)
        #expect(BarDisplay.next(queue, repeat: .off) == nil)
    }

    @Test func atTheLastSongRepeatAllNamesTheFirst() {
        let queue = playing(startUpNext(album(11), start: 0), at: 10)
        #expect(BarDisplay.next(queue, repeat: .all)?.id == "s1")
        // topped up, as the player does once the song has played a while: the same song, from the queue itself
        let topped = toppedUp(queue, .all)
        #expect(nextIndex(topped) != nil)
        #expect(BarDisplay.next(topped, repeat: .all)?.id == "s1")
    }

    @Test func repeatOneNamesNothing() {
        let queue = startUpNext(album(11), start: 2)
        #expect(BarDisplay.next(queue, repeat: .one) == nil)
        // the copies Repeat One queues: still nothing - the song again
        let copies = toppedUp(queue, .one)
        #expect(copies.tracks[3].id == "s3")
        #expect(BarDisplay.next(copies, repeat: .one) == nil)
        // a copy left in the queue as Repeat goes off names nothing either: it is this song again
        #expect(BarDisplay.next(copies, repeat: .off) == nil)
    }

    @Test func underShuffleNextIsTheShuffledOrder() {
        let queue = startUpNext(album(11), start: nil, shuffle: true, random: drawn([0.3, 0.7, 0.1, 0.9, 0.5]))
        guard let state = queue.upNext else {
            Issue.record("no state")
            return
        }
        // each song but the last: the shuffled order's next, never the list's
        var differs = 0
        for index in 0..<10 {
            let here = playing(queue, at: index)
            let after = queue.tracks[index + 1]
            #expect(BarDisplay.next(here, repeat: .off) == after)
            let listsNext = state.source[(state.marks[index].at + 1) % 11]
            if after != listsNext { differs += 1 }
        }
        // (the draw is a real shuffle: most of its next songs aren't the list's)
        #expect(differs >= 5)
    }

    @Test func atAShuffledRoundsEndOnlyTheQueueKnowsWhatPlays() {
        let queue = playing(startUpNext(album(4), start: nil, shuffle: true, random: drawn([0.3, 0.7, 0.1])), at: 3)
        // not drawn yet: nothing named rather than a guess
        #expect(BarDisplay.next(queue, repeat: .all) == nil)
        // drawn: the round's first
        let topped = toppedUp(queue, .all, random: drawn([0.6, 0.2, 0.8, 0.4]))
        #expect(BarDisplay.next(topped, repeat: .all) == topped.tracks[4])
    }

    @Test func aSongAddedIsNext() {
        let extra = QueueTrack(id: "x", title: "Added", artist: "Someone", album: "Else")
        let queue = withNext(startUpNext(album(11), start: 2), [extra])
        #expect(BarDisplay.next(queue, repeat: .off)?.id == "x")
    }

    @Test func nothingPlayingNamesNothing() {
        #expect(BarDisplay.next(.empty, repeat: .all) == nil)
        #expect(BarDisplay.place(.empty) == nil)
        #expect(BarDisplay.readout(.empty) == nil)
    }

    // MARK: 3 of 11

    @Test func theAlbumsThirdSongIsThreeOfEleven() {
        let queue = startUpNext(album(11), start: 2)
        #expect(BarDisplay.place(queue) == BarDisplay.Place(number: 3, of: 11))
        #expect(BarDisplay.Words.place(BarDisplay.Place(number: 3, of: 11)) == "3 of 11")
        #expect(BarDisplay.place(playing(queue, at: 0)) == BarDisplay.Place(number: 1, of: 11))
        #expect(BarDisplay.place(playing(queue, at: 10)) == BarDisplay.Place(number: 11, of: 11))
    }

    @Test func underShuffleItCountsWhatPlayed() {
        let queue = startUpNext(album(11), start: nil, shuffle: true, random: drawn([0.3, 0.7, 0.1, 0.9, 0.5]))
        #expect(BarDisplay.place(queue) == BarDisplay.Place(number: 1, of: 11))
        #expect(BarDisplay.place(playing(queue, at: 2)) == BarDisplay.Place(number: 3, of: 11))
    }

    @Test func shuffleTurnedOnCountsFromWhereListeningBegan() {
        // from the third song, Shuffle then: the two never heard come in the shuffle, so this is the first of 11
        let queue = withShuffle(startUpNext(album(11), start: 2), true, random: drawn([0.4, 0.2, 0.8]))
        #expect(BarDisplay.place(queue) == BarDisplay.Place(number: 1, of: 11))
    }

    @Test func aSongTakenOutLeavesThePlaceAsItWas() {
        let queue = startUpNext(album(11), start: 2)
        guard let state = queue.upNext else {
            Issue.record("no state")
            return
        }
        let out = withoutKey(queue, state.marks[6].key)
        #expect(out.tracks.count == 10)
        #expect(BarDisplay.place(out) == BarDisplay.Place(number: 3, of: 10))
    }

    @Test func inTheListsOrderASongTakenOutBeforeThisOneMovesItUp() {
        // (after R4's review) under Shuffle a song still to come that the list has BEFORE this one is taken out, then
        // Shuffle goes off: this song's place is its place in the list less the one taken out before it
        let shuffled = startUpNext(album(11), start: nil, shuffle: true, random: drawn([0.3, 0.7, 0.1, 0.9, 0.5, 0.2]))
        guard let state = shuffled.upNext else {
            Issue.record("no state")
            return
        }
        // the first song played whose list place has a song still to come before it
        let found = state.marks.indices.lazy.compactMap { (place: Int) -> (Int, Int)? in
            guard let later = state.marks.indices.first(where: { $0 > place && state.marks[$0].at < state.marks[place].at })
            else { return nil }
            return (place, later)
        }.first
        guard let (place, later) = found else {
            Issue.record("no song still to come before one played, in this shuffle")
            return
        }
        let at = state.marks[place].at
        let out = withoutKey(playing(shuffled, at: place), state.marks[later].key)
        let off = withShuffle(out, false, random: drawn([0.5]))
        #expect(off.upNext?.shuffle == false && off.current?.id == shuffled.tracks[place].id)
        #expect(BarDisplay.place(off) == BarDisplay.Place(number: at, of: 10))
    }

    @Test func repeatAllsNextRoundCountsAfresh() {
        let first = playing(startUpNext(album(4), start: 0), at: 3)
        let topped = toppedUp(first, .all)
        #expect(BarDisplay.place(topped) == BarDisplay.Place(number: 4, of: 4))
        #expect(BarDisplay.place(playing(topped, at: 4)) == BarDisplay.Place(number: 1, of: 4))
        #expect(BarDisplay.place(playing(topped, at: 5)) == BarDisplay.Place(number: 2, of: 4))
    }

    @Test func aRepeatOneCopyIsItsSongsPlace() {
        let copies = toppedUp(startUpNext(album(11), start: 2), .one)
        #expect(BarDisplay.place(playing(copies, at: 3)) == BarDisplay.Place(number: 3, of: 11))
        // and past the copies, the next song's
        #expect(BarDisplay.place(playing(copies, at: 5)) == BarDisplay.Place(number: 4, of: 11))
    }

    @Test func aSongAddedHasNoPlace() {
        let extra = QueueTrack(id: "x", title: "Added", artist: "Someone", album: "Else", suffix: "mp3")
        let queue = playing(withNext(startUpNext(album(11), start: 2), [extra]), at: 3)
        #expect(BarDisplay.place(queue) == nil)
        // the format alone
        #expect(BarDisplay.readout(queue) == "MP3")
        // and the album's next song after it is still its own place
        #expect(BarDisplay.place(playing(queue, at: 4)) == BarDisplay.Place(number: 4, of: 11))
    }

    @Test func aTrimmedFrontKeepsThePlace() {
        // a reload keeps only so much before the song playing (Resume.before): counted from the end, the place holds
        let whole = startUpNext(album(11), start: 6)
        guard var state = whole.upNext else {
            Issue.record("no state")
            return
        }
        state.marks.removeFirst(4)
        let trimmed = UpNextQueue(tracks: Array(whole.tracks.dropFirst(4)), index: 2, upNext: state)
        #expect(trimmed.current?.id == "s7")
        #expect(BarDisplay.place(trimmed) == BarDisplay.Place(number: 7, of: 11))
    }

    @Test func aLibrarysShuffleCountsItsWholeOrder() {
        let page = album(3)
        let paged = Paged(token: "t", total: 1612, fetched: 3, scope: .yours)
        let queue = startUpNext(page, start: 0, paged: paged)
        #expect(BarDisplay.place(queue) == BarDisplay.Place(number: 1, of: 1612))
        #expect(BarDisplay.Words.place(BarDisplay.Place(number: 1, of: 1612)) == "1 of 1,612")
        // more of it fetched: the place holds
        let more = withMore(playing(queue, at: 2), token: "t", tracks: album(2).map { (t: QueueTrack) -> QueueTrack in
            var other = t
            other.id = "p\(t.id)"
            return other
        })
        #expect(BarDisplay.place(more) == BarDisplay.Place(number: 3, of: 1612))
        // nothing past what is queued is named next at its end
        #expect(BarDisplay.next(playing(more, at: 4), repeat: .all) == nil)
    }

    @Test func aPlainQueueHasNoPlace() {
        let plain = UpNextQueue(tracks: album(3), index: 1)
        #expect(BarDisplay.place(plain) == nil)
        #expect(BarDisplay.next(plain, repeat: .off)?.id == "s3")
        #expect(BarDisplay.next(playing(plain, at: 2), repeat: .all) == nil)
    }

    // MARK: the format

    @Test func theFormatIsWhatTheSongSays() {
        let flac = album(1)[0]
        #expect(BarDisplay.format(flac) == "FLAC 16/44.1")
        #expect(BarDisplay.formatSpoken(flac) == "FLAC, 16-bit, 44.1 kHz")
        var hiRes = flac
        hiRes.bitDepth = 24
        hiRes.sampleRate = 96000
        #expect(BarDisplay.format(hiRes) == "FLAC 24/96")
        var noRate = flac
        noRate.sampleRate = 0
        #expect(BarDisplay.format(noRate) == "FLAC 16-bit")
        var noDepth = flac
        noDepth.bitDepth = 0
        #expect(BarDisplay.format(noDepth) == "FLAC 44.1 kHz")
        #expect(BarDisplay.formatSpoken(noDepth) == "FLAC, 44.1 kHz")
        var neither = noDepth
        neither.sampleRate = 0
        #expect(BarDisplay.format(neither) == "FLAC")
        var odd = flac
        odd.sampleRate = 88200
        #expect(BarDisplay.format(odd) == "FLAC 16/88.2")
    }

    @Test func aLossyFilesFormatIsItsNameAlone() {
        let mp3 = QueueTrack(id: "m", title: "M", artist: "A", album: "B", contentType: "audio/mpeg", suffix: "mp3",
                             sampleRate: 44100, bitDepth: 16)
        #expect(BarDisplay.format(mp3) == "MP3")
        // an MP4 is ALAC only when its type says so
        let aac = QueueTrack(id: "a", title: "A", artist: "A", album: "B", contentType: "audio/mp4", suffix: "m4a",
                             sampleRate: 44100, bitDepth: 16)
        #expect(BarDisplay.format(aac) == "M4A")
        var alac = aac
        alac.contentType = "audio/mp4; codecs=alac"
        #expect(BarDisplay.format(alac) == "ALAC 16/44.1")
        // a type alone, no suffix
        let typed = QueueTrack(id: "t", title: "T", artist: "A", album: "B", contentType: "audio/x-flac", bitDepth: 24)
        #expect(BarDisplay.format(typed) == "FLAC 24-bit")
        // nothing names one
        let bare = QueueTrack(id: "n", title: "N", artist: "A", album: "B")
        #expect(BarDisplay.format(bare) == nil)
        #expect(BarDisplay.formatSpoken(bare) == nil)
    }

    @Test func theReadoutJoinsThePlaceAndTheFormat() {
        let queue = startUpNext(album(11), start: 2)
        #expect(BarDisplay.readout(queue) == "3 of 11 · FLAC 16/44.1")
        #expect(BarDisplay.readoutSpoken(queue) == "3 of 11, FLAC, 16-bit, 44.1 kHz")
        #expect(BarDisplay.Words.nextSpoken("Bull Black Nova") == "Next: Bull Black Nova")
    }

    // MARK: (R4's review) a list of one, an earlier round, and a queue brought back by a reload

    @Test func aListOfOneUnderShuffleAndRepeatAllNamesItself() {
        // a shuffled list's next round isn't drawn until it is topped up - but a list of one can only be itself
        let one = startUpNext(album(1), start: nil, shuffle: true, random: drawn([0.5]))
        #expect(BarDisplay.next(one, repeat: .all)?.id == "s1")
        #expect(BarDisplay.next(one, repeat: .off) == nil)
        #expect(BarDisplay.next(startUpNext(album(2), start: nil, shuffle: true, random: drawn([0.5])), repeat: .all)?.id
                != nil)
        #expect(BarDisplay.next(playing(startUpNext(album(2), start: nil, shuffle: true, random: drawn([0.5])), at: 1),
                                repeat: .all) == nil)
    }

    @Test func anEarlierRoundOfALibrarysShuffleCountsItsOwnOrder() {
        // a library of 3 shuffled under Repeat All, its next round's first page fetched while the round's last songs
        // play - from a library of 5 by then: the round playing is still 3 songs, its place among them
        let paged = Paged(token: "t", total: 3, fetched: 3, scope: .yours)
        let first = playing(startUpNext(album(3), start: 0, paged: paged), at: 1)
        let more = withMore(first, token: "t", tracks: album(2).map { (t: QueueTrack) -> QueueTrack in
            var other = t
            other.id = "n\(t.id)"
            return other
        }, next: Paged(token: "u", total: 5, fetched: 0, scope: .yours))
        #expect(more.upNext?.pagedRounds?.first?.paged.total == 3)
        #expect(BarDisplay.place(more) == BarDisplay.Place(number: 2, of: 3))
        #expect(BarDisplay.place(playing(more, at: 2)) == BarDisplay.Place(number: 3, of: 3))
        // and the next round's own: the first of the library's 5
        #expect(BarDisplay.place(playing(more, at: 3)) == BarDisplay.Place(number: 1, of: 5))
    }

    /// The queue as a reload brings it back: Resume's own save (toSave, its window) and read (fromSnapshot).
    private func reloaded(_ queue: UpNextQueue) -> UpNextQueue? {
        let saving = toSave(queue, position: 1)
        let window = queue.tracks[saving.start..<(saving.start + saving.ids.count)].map(bare)
        return fromSnapshot(saving.snapshot, tracks: Array(window), index: saving.index, setting: .auto)
    }

    private func list(_ count: Int) -> [QueueTrack] {
        (1...count).map { (n: Int) -> QueueTrack in
            QueueTrack(id: "l\(n)", title: "Song \(n)", artist: "A", album: "B", albumId: "al", duration: 200,
                       contentType: "audio/flac", suffix: "flac", sampleRate: 44100, bitDepth: 16, channels: 2)
        }
    }

    @Test func aLongListReloadedKeepsItsPlace() {
        // the review's: a 2,100-song playlist comes back as Resume's 2,000 - its end cut, its list whole
        let queue = startUpNext(list(2100), start: 0)
        #expect(BarDisplay.place(queue) == BarDisplay.Place(number: 1, of: 2100))
        let back = reloaded(queue)
        #expect(back?.tracks.count == Resume.maxEntries)
        #expect(back.flatMap(BarDisplay.place) == BarDisplay.Place(number: 1, of: 2100))
        // its end cut from its 10th song, its front trimmed (the 50 before kept) and its end cut from its 80th, its front
        // alone from its 300th
        for at in [9, 79, 299] {
            let here = playing(queue, at: at)
            let again = reloaded(here)
            #expect(again.map { $0.tracks.count < 2100 } == true, "\(at)")
            #expect(again.flatMap(BarDisplay.place) == BarDisplay.Place(number: at + 1, of: 2100), "\(at)")
        }
        // a song still to come taken out, before and after the reload: the same place, of one fewer
        guard let state = queue.upNext else {
            Issue.record("no state")
            return
        }
        let out = withoutKey(playing(queue, at: 299), state.marks[400].key)
        #expect(BarDisplay.place(out) == BarDisplay.Place(number: 300, of: 2099))
        #expect(reloaded(out).flatMap(BarDisplay.place) == BarDisplay.Place(number: 300, of: 2099))
    }

    @Test func aShuffledListReloadedWithoutAllOfItsRoundHasNoPlace() {
        // its end cut, or its front trimmed: which songs were played can't be told - nothing rather than a guess
        let random = drawn([0.3, 0.7, 0.1, 0.9, 0.5, 0.2, 0.8])
        let long = startUpNext(list(2100), start: nil, shuffle: true, random: random)
        #expect(BarDisplay.place(long) == BarDisplay.Place(number: 1, of: 2100))
        #expect(reloaded(long).map(BarDisplay.place) == .some(nil))
        let album = startUpNext(list(60), start: nil, shuffle: true, random: random)
        #expect(BarDisplay.place(playing(album, at: 55)) == BarDisplay.Place(number: 56, of: 60))
        #expect(reloaded(playing(album, at: 55)).map(BarDisplay.place) == .some(nil))
        // brought back whole: its place as it was
        #expect(reloaded(playing(album, at: 40)).flatMap(BarDisplay.place) == BarDisplay.Place(number: 41, of: 60))
        // and once its next round is the queue's own, counted again
        guard let back = reloaded(playing(album, at: 59)) else {
            Issue.record("not reloaded")
            return
        }
        let round = toppedUp(back, .all, random: random)
        #expect(BarDisplay.place(round) == nil)
        #expect(BarDisplay.place(playing(round, at: back.tracks.count)) == BarDisplay.Place(number: 1, of: 60))
    }

    @Test func aLibrarysShuffleReloadedWithASongTakenOutHasNoPlace() {
        // the review's: the reload keeps no `left` for a library's shuffle, so the song taken out can't be counted -
        // "3 of 1,611" would come back "4 of 1,612"
        let paged = Paged(token: "t", total: 1612, fetched: 10, scope: .yours)
        let queue = playing(startUpNext(list(10), start: 0, paged: paged), at: 2)
        guard let state = queue.upNext else {
            Issue.record("no state")
            return
        }
        let out = withoutKey(queue, state.marks[6].key)
        #expect(BarDisplay.place(out) == BarDisplay.Place(number: 3, of: 1611))
        #expect(reloaded(out).map(BarDisplay.place) == .some(nil))
        // nothing taken out, and the whole of it brought back: its place as it was
        #expect(reloaded(queue).flatMap(BarDisplay.place) == BarDisplay.Place(number: 3, of: 1612))
    }

    // MARK: (R4's review) walks through every edit, as the player makes them

    /// A seeded draw, the same every run.
    private final class Seeded {
        private var seed: UInt64
        init(_ seed: UInt64) { self.seed = seed }
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func pick(_ count: Int) -> Int { min(Int(next() * Double(count)), count - 1) }
    }

    /// What plays at a song's natural end, as QueueController plays it: Repeat's round topped up, then the next entry.
    private func ended(_ queue: UpNextQueue, _ mode: Repeat, _ draw: Seeded) -> UpNextQueue? {
        var next = queue
        if mode != .off && nextIndex(next) == nil { next = toppedUp(next, mode, random: draw.next) }
        guard let index = nextIndex(next) else { return nil }
        next.index = index
        return next
    }

    @Test func nextNamesWhatPlaysAndThePlaceStepsByOne() {
        let draw = Seeded(0x9E3779B97F4A7C15)
        var checks = 0
        var wrong: [String] = []
        for run in 0..<3000 {
            let count = 1 + draw.pick(14)
            var mode: Repeat = [Repeat.off, .all, .one][draw.pick(3)]
            let start: Int? = draw.pick(2) == 0 ? nil : draw.pick(count)
            var queue = toppedUp(startUpNext(album(count), start: start, shuffle: draw.pick(2) == 0, random: draw.next),
                                 mode, random: draw.next)
            for step in 0..<40 {
                guard queue.current != nil else { break }
                let edit = draw.pick(10)
                if edit < 5 {
                    let named = BarDisplay.next(queue, repeat: mode)
                    let before = BarDisplay.place(queue)
                    guard let after = ended(queue, mode, draw) else {
                        if named != nil { wrong.append("\(run).\(step): named \(named!.id), the queue ended") }
                        break
                    }
                    checks += 1
                    let copy = after.upNext.map { markAt($0.marks, after.index)?.from == .one } ?? false
                    if let named, named.id != after.current?.id {
                        wrong.append("\(run).\(step): named \(named.id), \(after.current?.id ?? "-") played")
                    }
                    // within a round one more, a new round from 1, a copy its song's own
                    if let was = before, let now = BarDisplay.place(after) {
                        let stepped = copy ? now == was : (now.number == was.number + 1 && now.of == was.of) || now.number == 1
                        if !stepped { wrong.append("\(run).\(step): \(was) then \(now)") }
                    }
                    queue = toppedUp(after, mode, random: draw.next)
                } else if edit == 5 {
                    queue = withNext(queue, [QueueTrack(id: "x\(step)", title: "X", artist: "A", album: "B")])
                } else if edit == 6 {
                    queue = withLast(queue, [QueueTrack(id: "y\(step)", title: "Y", artist: "A", album: "B")])
                } else if edit == 7 {
                    let view = upNextView(queue, mode)
                    let rows = view.added + (view.list?.rows ?? [])
                    if !rows.isEmpty { queue = withoutKey(queue, rows[draw.pick(rows.count)].key) }
                } else if edit == 8 {
                    queue = toppedUp(withShuffle(queue, !(queue.upNext?.shuffle ?? false), random: draw.next), mode,
                                     random: draw.next)
                } else {
                    mode = [Repeat.off, .all, .one][draw.pick(3)]
                    queue = toppedUp(withRepeat(queue, mode), mode, random: draw.next)
                }
                if let place = BarDisplay.place(queue), !(1...place.of).contains(place.number) {
                    wrong.append("\(run).\(step): \(place)")
                }
            }
        }
        #expect(checks > 10_000)
        #expect(wrong.isEmpty, "\(wrong.prefix(8))")
    }

    @Test func aLibrarysShuffleFedAPageAtATimeCountsEverySong() {
        let draw = Seeded(12345)
        var steps = 0
        var wrong: [String] = []
        for run in 0..<500 {
            let total = 3 + draw.pick(30)
            let size = 1 + draw.pick(5)
            var made = 0
            func page(_ count: Int) -> [QueueTrack] {
                (0..<count).map { (_: Int) -> QueueTrack in
                    made += 1
                    return QueueTrack(id: "p\(made)", title: "P", artist: "A", album: "B", suffix: "flac")
                }
            }
            let mode: Repeat = draw.pick(2) == 0 ? .all : .off
            let first = min(size, total)
            var queue = startUpNext(page(first), start: 0,
                                    paged: Paged(token: "t", total: total, fetched: first, scope: .yours))
            var token = "t"
            var expected = 1
            for _ in 0..<(total * 3) {
                guard let paged = queue.upNext?.paged else { break }
                // the feed: more while fewer than 2 follow
                if queue.tracks.count - queue.index - 1 < 2 {
                    if paged.fetched < paged.total {
                        queue = withMore(queue, token: token, tracks: page(min(size, paged.total - paged.fetched)))
                    } else if mode == .all {
                        let fresh = Paged(token: "t\(made)", total: total, fetched: 0, scope: .yours)
                        queue = withMore(queue, token: token, tracks: page(min(size, total)), next: fresh)
                        token = fresh.token
                    }
                }
                steps += 1
                let place = BarDisplay.place(queue)
                if place != BarDisplay.Place(number: expected, of: total) {
                    wrong.append("\(run): \(expected) of \(total), \(String(describing: place))")
                    break
                }
                let named = BarDisplay.next(queue, repeat: mode)
                guard let index = nextIndex(queue) else { break }
                if let named, named.id != queue.tracks[index].id { wrong.append("\(run): named \(named.id)") }
                queue.index = index
                expected = expected == total ? 1 : expected + 1
            }
        }
        #expect(steps > 10_000)
        #expect(wrong.isEmpty, "\(wrong.prefix(8))")
    }

    @Test func previousAndHistoryNeverNameAWrongSongOrPlace() {
        let draw = Seeded(777)
        var checks = 0
        var wrong: [String] = []
        for run in 0..<2000 {
            let count = 2 + draw.pick(12)
            var mode: Repeat = [Repeat.off, .all, .one][draw.pick(3)]
            var queue = toppedUp(startUpNext(album(count), start: draw.pick(count), shuffle: draw.pick(2) == 0,
                                             random: draw.next), mode, random: draw.next)
            for step in 0..<40 {
                guard queue.current != nil else { break }
                switch draw.pick(6) {
                case 0, 1, 2:
                    let named = BarDisplay.next(queue, repeat: mode)
                    guard let after = ended(queue, mode, draw) else { break }
                    checks += 1
                    if let named, named.id != after.current?.id {
                        wrong.append("\(run).\(step): named \(named.id), \(after.current?.id ?? "-") played")
                    }
                    queue = toppedUp(after, mode, random: draw.next)
                case 3:
                    if case .go(let index) = backward(queue, position: 0) { queue = wentBack(queue, index) }
                case 4:
                    let rows = historyRows(queue)
                    if !rows.isEmpty, let jump = jumpedTo(queue, rows[draw.pick(rows.count)].key, mode) {
                        queue = jump.queue
                        queue.index = jump.index
                        queue = toppedUp(queue, mode, random: draw.next)
                    }
                default:
                    let view = upNextView(queue, mode)
                    let rows = view.added + (view.list?.rows ?? [])
                    if !rows.isEmpty, let jump = jumpedTo(queue, rows[draw.pick(rows.count)].key, mode) {
                        queue = jump.queue
                        queue.index = jump.index
                        queue = toppedUp(queue, mode, random: draw.next)
                    }
                    if draw.pick(4) == 0 {
                        mode = [Repeat.off, .all, .one][draw.pick(3)]
                        queue = toppedUp(withRepeat(queue, mode), mode, random: draw.next)
                    }
                }
                if let place = BarDisplay.place(queue), !(1...place.of).contains(place.number) {
                    wrong.append("\(run).\(step): \(place)")
                }
            }
        }
        #expect(checks > 10_000)
        #expect(wrong.isEmpty, "\(wrong.prefix(8))")
    }
}
