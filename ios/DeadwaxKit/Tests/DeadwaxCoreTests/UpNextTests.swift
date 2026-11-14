import Foundation
import Testing
@testable import DeadwaxCore

// Up Next's rules, each as ui/test/upnext.sim.cjs states it (the line numbers are the sim's), checked directly
// against the Swift port. The traces (UpNextTraceTests) hold the port to everything the TypeScript does; these say
// what each rule is, so a failure reads as the rule broken.

@Suite struct UpNextStartTests {
    @Test func noSongsIsTheEmptyQueue() { // :143
        let empty = startUpNext([], start: 0)
        #expect(empty == .empty)
        #expect(empty.upNext == nil && empty.index == -1 && current(empty) == nil)
    }

    @Test func oneSongShuffledIsThatSong() { // :145
        let one = startUpNext([simTrack("x")], start: 0, shuffle: true, random: Seeded(3).next)
        #expect(one.ids == ["x"] && one.index == 0)
    }

    @Test func everyMarkTheListsFirstRoundKnowingItsPlace() { // :147-149
        let list = simAlbum(7)
        let shuffled = startUpNext(list, start: 2, shuffle: true, random: Seeded(5).next)
        let marks = shuffled.upNext?.marks ?? []
        #expect(marks.enumerated().allSatisfy { $0.element.from == .source && $0.element.pass == 0 && list[$0.element.at].id == shuffled.tracks[$0.offset].id })
        #expect(marks.map(\.key).sorted() == Array(0..<7))
        #expect(shuffled.upNext?.nextKey == 7 && shuffled.upNext?.startedAt == 0)
        #expect(startUpNext(list, start: 4).upNext?.startedAt == 4)
        #expect(shuffled.current?.id == "3")
    }

    @Test func aSongTwiceIsTwoEntriesEachItsOwnPlace() { // :151
        let twice = startUpNext([simTrack("a"), simTrack("b"), simTrack("a")], start: 0, shuffle: true, random: Seeded(9).next)
        #expect(twice.upNext?.marks.map(\.at).sorted() == [0, 1, 2])
    }

    @Test func theSourceIsTheListInItsOwnOrderAndShuffleAsAsked() { // :152
        let list = simAlbum(7)
        let shuffled = startUpNext(list, start: 2, shuffle: true, random: Seeded(5).next)
        #expect(shuffled.upNext?.source.map(\.id) == list.map(\.id))
        #expect(shuffled.upNext?.shuffle == true && startUpNext(list, start: 0).upNext?.shuffle == false)
    }

    @Test func theStartIsHeldInsideTheList() { // Phase 0's PlayQueueTests, on the port; playqueue.sim.cjs:61-64
        let songs = simAlbum(3)
        #expect(startUpNext(songs, start: 9).index == 2)
        #expect(startUpNext(songs, start: -4).index == 0)
        #expect(startUpNext(songs, start: nil).index == 0)
        #expect(startUpNext([], start: 4).current == nil)
    }

    @Test func nextAndPreviousOnAPlainList() { // playqueue.sim.cjs:81-92
        let queue = startUpNext(simAlbum(5), start: 1)
        #expect(nextIndex(queue) == 2 && nextIndex(queue.at(4)) == nil)
        #expect(previousAction(queue.at(2), position: 1.5) == .go(1))
        #expect(previousAction(queue.at(2), position: 40) == .restart)
        #expect(previousAction(queue.at(2), position: 3.0) == .go(1))
        #expect(previousAction(queue.at(2), position: 3.01) == .restart)
        #expect(previousAction(queue.at(0), position: 0.5) == .restart)
        #expect(onward(queue) == 2 && backward(queue.at(2), position: 1) == .go(1))
    }

    @Test func aSongOfNavidromesAsAQueueEntry() { // playqueue.sim.cjs:308-317 (toQueueTrack)
        let full = QueueTrack(song: Song(id: "s", title: "One", samplingRate: 192_000, bitDepth: 24, channelCount: 2),
                              albumId: "al", albumName: "The Album", albumArtist: "Them", albumCoverArt: "cv")
        #expect(full.sampleRate == 192_000 && full.bitDepth == 24 && full.channels == 2)
        let bare = QueueTrack(song: Song(id: "s", title: "One"), albumId: "al", albumName: "The Album",
                              albumArtist: "Them", albumCoverArt: "cv")
        #expect(bare.sampleRate == 0 && bare.bitDepth == 0 && bare.channels == 0 && bare.duration == 0)
        #expect(bare.album == "The Album" && bare.artist == "Them" && bare.albumId == "al" && bare.coverArt == "cv")
        let own = QueueTrack(song: Song(id: "t", album: "Its Own", albumId: "x", artist: "Her", coverArt: "c2"),
                             albumId: "al", albumName: "The Album", albumArtist: "Them", albumCoverArt: "cv", level: .album)
        #expect(own.album == "Its Own" && own.albumId == "x" && own.artist == "Her" && own.coverArt == "c2")
        #expect(own.level == .album)
        #expect(QueueTrack(song: Song(id: "u"), albumId: "al", albumName: "A").artist == "")
    }

    @Test func aQueueEntrysTitleIsTheSongsOwn() { // (review) api.ts toQueueTrack's `title: song.title`
        //? never the id Song.name falls back to: a title Navidrome left out, or sent empty, is "" - the web's
        //? undefined and "" - as shuffledTrack makes it from GET /queue's songs
        #expect(entry(title: "One").title == "One")
        #expect(entry(title: nil).title == "")
        #expect(entry(title: "").title == "")
        #expect(shuffledTrack(Song(id: "t")).title == "" && shuffledTrack(Song(id: "t", title: "")).title == "")
    }

    private func entry(title: String?) -> QueueTrack {
        QueueTrack(song: Song(id: "t", title: title, album: "Its Own", albumId: "x"), albumId: "al", albumName: "The Album")
    }
}

@Suite struct UpNextEditTests {
    @Test func playNextAndPlayLastPlaces() { // :235-247
        let start = startUpNext(simAlbum(4), start: 0)
        let next = withNext(start, [simTrack("n")])
        #expect(next.after == ["n", "2", "3", "4"])
        let both = withLast(withNext(next, [simTrack("m")]), [simTrack("z")])
        #expect(both.after == ["m", "n", "z", "2", "3", "4"])
        #expect(both.froms == ["a", "a", "a", "s0", "s0", "s0"])
        let one = toppedUp(start, .one)
        #expect(withNext(one, [simTrack("n")]).after == ["1", "1", "n", "2", "3", "4"])
        #expect(withLast(one, [simTrack("z")]).after == ["1", "1", "z", "2", "3", "4"])
        #expect(withNext(start, [simTrack("a"), simTrack("b")]).after == ["a", "b", "2", "3", "4"])
        #expect(withNext(start, []) == start)
        #expect(withLast(.empty, [simTrack("a")]) == .empty)
    }

    @Test func aRowOutMovedAndClear() { // :249-266
        let start = withLast(startUpNext(simAlbum(4), start: 0), [simTrack("a"), simTrack("b")])
        #expect(withoutKey(start, start.key("a")!).after == ["b", "2", "3", "4"])
        let gone = withoutKey(start, start.key("3")!)
        #expect(gone.after == ["a", "b", "2", "4"])
        #expect(gone.upNext?.left == [LeftOut(pass: 0, at: 2)])
        let later = start.at(2)
        let marks = start.upNext!.marks
        #expect(withoutKey(start, marks[0].key) == start)
        #expect(withoutKey(later, marks[1].key) == later)
        #expect(withoutKey(start, 999) == start)
        #expect(movedKey(start, start.key("b")!, to: 0).after == ["b", "a", "2", "3", "4"])
        #expect(movedKey(start, start.key("2")!, to: 2).after == ["a", "b", "3", "4", "2"])
        #expect(movedKey(start, start.key("2")!, to: 9).after == ["a", "b", "3", "4", "2"])
        #expect(movedKey(start, start.key("3")!, to: 1) == start)
        let one = toppedUp(start, .one)
        let copy = one.upNext!.marks[1].key
        #expect(movedKey(one, copy, to: 3) == one && withoutKey(one, copy) == one)
        let cleared = withoutAdded(start)
        #expect(cleared.after == ["2", "3", "4"])
        #expect(withoutAdded(cleared) == cleared)
    }

    @Test func aMoveStaysInItsGroup() {
        let start = withLast(startUpNext(simAlbum(4), start: 0), [simTrack("a"), simTrack("b")])
        // "a" to the list's places: held at Playing Next's end
        #expect(movedKey(start, start.key("a")!, to: 4).after == ["b", "a", "2", "3", "4"])
        // the list's first to place 0 of its own group: where it is
        #expect(movedKey(start, start.key("2")!, to: -3) == start)
    }

    @Test func aRowsTap() { // :389-402 (2.1.3)
        let start = withLast(startUpNext(simAlbum(5), start: 0), [simTrack("a"), simTrack("b")])
        let toList = jumpedTo(start, start.key("4")!, .off)!
        let moved = toList.queue.at(toList.index)
        // into the list: it plays, the songs passed kept behind it in order, Playing Next after it
        #expect(moved.current?.id == "4" && moved.ids == ["1", "2", "3", "4", "a", "b", "5"] && moved.index == 3)
        #expect(moved.after == ["a", "b", "5"] && toList.queue.upNext?.left == [])
        // into Playing Next: the same queue, the place moved - the songs added above it behind it
        let toAdded = jumpedTo(start, start.key("b")!, .off)!
        let there = toAdded.queue.at(toAdded.index)
        #expect(toAdded.queue == start && there.current?.id == "b" && Array(there.ids.prefix(there.index)) == ["1", "a"])
        #expect(there.after == ["2", "3", "4", "5"])
        #expect(jumpedTo(start, start.upNext!.marks[0].key, .off) == nil)
        let copies = toppedUp(start, .one)
        #expect(jumpedTo(copies, copies.upNext!.marks[1].key, .one) == nil)
        #expect(jumpedTo(start, 77, .off) == nil)
        let one = toppedUp(startUpNext(simAlbum(3), start: 0), .one)
        let jumped = jumpedTo(one, one.key("3")!, .one)!
        #expect(jumped.queue.at(jumped.index).current?.id == "3" && jumped.queue.ids == ["1", "1", "1", "2", "3"])
    }

    @Test func aJumpWithNothingToEditIsTheSameQueue() {
        let start = startUpNext(simAlbum(4), start: 0)
        #expect(jumpedTo(start, start.key("2")!, .off) == Jump(queue: start, index: 1))
    }
}

@Suite struct UpNextShuffleTests {
    @Test func shuffleOnShufflesTheSongsNotYetHeardThisRound() { // :286-311
        let start = startUpNext(simAlbum(12), start: 4)
        let queue = withShuffle(start.at(6), true, random: Seeded(4).next)
        #expect(Array(queue.ids.prefix(7)) == ["1", "2", "3", "4", "5", "6", "7"] && queue.index == 6)
        #expect(queue.after.sorted { Int($0)! < Int($1)! } == ["1", "2", "3", "4", "8", "9", "10", "11", "12"])
        #expect(queue.after.joined(separator: ",") != "1,2,3,4,8,9,10,11,12")
        let keys = Dictionary(uniqueKeysWithValues: start.upNext!.marks.dropFirst(7).map { ($0.at, $0.key) })
        #expect(queue.upNext!.marks.dropFirst(7).filter { keys[$0.at] != nil }.allSatisfy { keys[$0.at] == $0.key })
        #expect(queue.upNext?.shuffle == true)

        let added = withNext(withLast(start.at(6), [simTrack("a")]), [simTrack("b")])
        #expect(Array(withShuffle(added, true, random: Seeded(2).next).after.prefix(2)) == ["b", "a"])
        let removed = withShuffle(withoutKey(start.at(6), start.key("9")!), true, random: Seeded(3).next)
        #expect(!removed.after.contains("9"))
        let jumped = jumpedTo(start.at(6), start.key("10")!, .off)!
        let overJumped = withShuffle(jumped.queue.at(jumped.index), true, random: Seeded(3).next)
        #expect(overJumped.current?.id == "10" && !overJumped.after.contains("8") && !overJumped.after.contains("9"))
        // (2.1.3) behind the song jumped to, heard this round as far as a shuffle goes
        #expect(Array(overJumped.ids[7..<9]) == ["8", "9"])
        #expect(overJumped.after.sorted { Int($0)! < Int($1)! } == ["1", "2", "3", "4", "11", "12"])

        let all = toppedUp(startUpNext(simAlbum(3), start: 0).at(0), .all)
        let lastSong = toppedUp(all.at(2), .all)
        let shuffledEnd = toppedUp(withShuffle(lastSong, true, random: Seeded(8).next), .all, random: Seeded(8).next)
        #expect(shuffledEnd.froms.allSatisfy { $0 == "s1" } && shuffledEnd.after.sorted() == ["1", "2", "3"])
        #expect(!withShuffle(all, true, random: Seeded(1).next).upNext!.marks.contains { $0.pass > 0 })
        #expect(withShuffle(start, false) == start && withShuffle(.empty, true) == .empty)
    }

    @Test func shuffleOffPlaysTheListsOwnOrderFromTheSongPlayingsPlace() { // :313-329
        let shuffled = startUpNext(simAlbum(8), start: nil, shuffle: true, random: Seeded(6).next)
        let now = shuffled.at(2)
        let place = now.upNext!.marks[2].at
        let expected = simAlbum(8).map(\.id).dropFirst(place + 1).map { $0 }
        let off = withShuffle(now, false)
        #expect(off.after == expected)
        #expect(off.upNext!.marks.dropFirst(3).allSatisfy { $0.key >= shuffled.upNext!.nextKey })
        if let first = expected.first {
            #expect(!withShuffle(withoutKey(now, now.key(first) ?? -1), false).after.contains(first))
        }
        #expect(withShuffle(withNext(now, [simTrack("a")]), false).after.first == "a")
        #expect(withShuffle(withNext(now, [simTrack("a")]).at(3), false).after == expected)
        #expect(off.upNext?.shuffle == false)
    }

    @Test func aLibrarysShuffleIsLeftAsItIs() { // :458
        let first = startUpNext(simAlbum(3, "p"), start: 0, paged: Paged(token: "t1", total: 450, fetched: 3, scope: .store))
        #expect(first.upNext?.shuffle == true)
        #expect(withShuffle(first, false) == first)
        #expect(toppedUp(first.at(2), .all) == first.at(2))
        #expect(Array(toppedUp(first, .one).after.prefix(2)) == ["p1", "p1"])
    }
}

@Suite struct UpNextRepeatTests {
    @Test func repeatAllQueuesTheListAgain() { // :333-357
        let start = startUpNext(simAlbum(3), start: 0)
        #expect(toppedUp(start, .all) == start)
        let late = toppedUp(start.at(1), .all)
        #expect(late.after == ["3", "1", "2", "3"] && late.froms == ["s0", "s1", "s1", "s1"])
        #expect(toppedUp(late, .all) == late)
        let single = toppedUp(startUpNext([simTrack("x")], start: 0), .all)
        #expect(single.after == ["x", "x"] && single.froms == ["s1", "s2"])
        let added = toppedUp(withNext(start.at(2), [simTrack("a")]), .all)
        #expect(added.after == ["a", "1", "2", "3"] && added.tracks.filter { $0.id == "a" }.count == 1)
        let shuffledRounds = toppedUp(startUpNext(simAlbum(6), start: 0, shuffle: true, random: Seeded(3).next).at(5), .all, random: Seeded(9).next)
        #expect(shuffledRounds.after.sorted() == ["1", "2", "3", "4", "5", "6"])
        #expect(toppedUp(start.at(2), .off) == start.at(2))
    }

    @Test func repeatOneCopiesTheSongStraightAfterIt() { // :359-367
        let start = withLast(startUpNext(simAlbum(3), start: 0), [simTrack("a")])
        let one = toppedUp(start, .one)
        #expect(one.after == ["1", "1", "a", "2", "3"] && one.froms == ["o", "o", "a", "s0", "s0"])
        #expect(one.tracks[1] == one.tracks[0] && one.upNext?.marks[1].at == 0 && one.upNext?.marks[1].pass == 0)
        let moved = toppedUp(one.ended, .one)
        #expect(moved.after == ["1", "1", "a", "2", "3"] && toppedUp(moved, .one) == moved)
    }

    @Test func aCopyKeepsItsSongsLevel() {
        var song = simTrack("1")
        song.level = .album
        let one = toppedUp(startUpNext([song, simTrack("2")], start: 0), .one)
        #expect(one.tracks[1].level == .album && one.tracks[2].level == .album)
    }

    @Test func aRepeatChangedLetsGoOfWhatItNoLongerWants() { // :369-380
        let one = toppedUp(startUpNext(simAlbum(3), start: 0), .one)
        #expect(withRepeat(one, .off).after == ["2", "3"])
        let all = toppedUp(startUpNext(simAlbum(3), start: 0).at(1), .all)
        #expect(withRepeat(all, .off).after == ["3"])
        #expect(withRepeat(toppedUp(all.at(2), .all), .off).after == [])
        #expect(toppedUp(withRepeat(toppedUp(startUpNext(simAlbum(3), start: 0).at(1), .one), .all), .all).after == ["3", "1", "2", "3"])
        #expect(toppedUp(withRepeat(all, .one), .one).after == ["2", "2", "3"])
        let plain = startUpNext(simAlbum(3), start: 0)
        #expect(withRepeat(plain, .off) == plain && withRepeat(all, .all) == all)
    }

    @Test func repeatIsReadWithCare() { // player.sim.cjs:5257
        #expect(["all", "one", nil, "ALL", "repeat", ""].map(Repeat.read) == [.all, .one, .off, .off, .off, .off])
        #expect(Repeat.storageKey == "deadwax-player-repeat")
        #expect(Repeat.allCases.map(nextRepeat) == [.all, .one, .off])
    }
}

@Suite struct UpNextMovingTests {
    @Test func nextPreviousAndAFailuresSkipPassRepeatOnesCopies() { // :384-397
        let one = toppedUp(startUpNext(simAlbum(3), start: 0).at(1), .one)
        #expect(onward(one) == 4)
        #expect(onward(toppedUp(startUpNext(simAlbum(2), start: 0).at(1), .one)) == nil)
        let plain = UpNextQueue(tracks: simAlbum(3), index: 0)
        #expect(onward(plain.at(1)) == 2 && onward(plain.at(2)) == nil)
        let onCopy = one.ended
        #expect(backward(onCopy, position: 10) == .restart)
        #expect(backward(onCopy, position: 1) == .go(0))
        #expect(backward(toppedUp(startUpNext(simAlbum(2), start: 0), .one).ended, position: 1) == .restart)
        #expect(backward(startUpNext(simAlbum(3), start: 0).at(2), position: 1) == .go(1))
        #expect(backward(startUpNext(simAlbum(3), start: 0), position: 1) == .restart)
        #expect(pastCopies(one, from: 2) == 4)
        #expect(pastCopies(toppedUp(startUpNext(simAlbum(2), start: 0).at(1), .one), from: 2) == nil)
        #expect(pastCopies(plain, from: 2) == 2 && pastCopies(plain, from: 3) == nil)
    }

    @Test func theEmptyQueueAnswersAsAPlainOne() {
        #expect(onward(.empty) == nil && backward(.empty, position: 1) == .restart && pastCopies(.empty, from: 0) == nil)
        #expect(shownPass(.empty) == -1 && nextIndex(.empty) == nil)
        #expect(toppedUp(.empty, .all) == .empty && withRepeat(.empty, .off) == .empty && withoutAdded(.empty) == .empty)
        #expect(withoutKey(.empty, 0) == .empty && movedKey(.empty, 0, to: 1) == .empty && jumpedTo(.empty, 0, .off) == nil && broughtBack(.empty, [], .off) == nil)
        #expect(withMore(.empty, token: "t1", tracks: [simTrack("1")]) == .empty)
    }
}

@Suite struct UpNextViewTests {
    @Test func whatUpNextDraws() { // :401-433
        let start = startUpNext(simAlbum(4), start: 0)
        let view = upNextView(start, .off)
        #expect(view.playing?.id == "1" && view.added.isEmpty && view.then == nil)
        #expect(view.list?.title == "From Mezzanine" && view.list?.rows.map(\.track.id) == ["2", "3", "4"] && view.list?.more == 0)

        let full = toppedUp(toppedUp(withNext(start, [simTrack("a", album: "Dummy", albumId: "dum")]), .one), .one)
        let drawn = upNextView(full, .one)
        #expect(drawn.added.map(\.track.id) == ["a"] && drawn.list?.rows.map(\.track.id) == ["2", "3", "4"] && drawn.repeatOne)

        let end = upNextView(toppedUp(start.at(3), .all), .all)
        #expect(end.list?.title == "From Mezzanine, again" && end.list?.rows.map(\.track.id) == ["1", "2", "3", "4"])
        #expect(end.then == "Then Mezzanine again from the top.")
        #expect(upNextView(toppedUp(start.at(2), .all), .all).list?.rows.map(\.track.id) == ["4"])
        #expect(upNextView(toppedUp(startUpNext(simAlbum(4), start: nil, shuffle: true, random: Seeded(1).next), .all), .all).then
                == "Then Mezzanine again, in a new order.")
        #expect(upNextView(start.at(3), .off).then == "Nothing after this song.")

        let long = startUpNext(simAlbum(130), start: 0)
        #expect(upNextView(long, .off).list?.rows.count == 100 && upNextView(long, .off).list?.more == 29)
        #expect(upNextView(long, .off, limit: 5).list?.more == 124)

        let mixed = startUpNext([simTrack("1"), simTrack("2", album: "Dummy", albumId: "dum")], start: 0)
        #expect(upNextView(mixed, .off).list?.title == "Still to play")
        #expect(upNextView(toppedUp(mixed.at(1), .all), .all).then == "Then the list again from the top.")
        #expect(upNextView(.empty, .all) == UpNextView(history: [], playing: nil, added: [], list: nil, then: nil, repeatOne: false))
    }

    @Test func aLibrarysShuffleCountsWhatIsStillToCome() { // :437-465
        let paged = Paged(token: "t1", total: 450, fetched: 3, scope: .store)
        let first = startUpNext(simAlbum(3, "p"), start: 0, paged: paged)
        let more = withMore(first, token: "t1", tracks: simAlbum(2, "q"))
        #expect(more.after == ["p2", "p3", "q1", "q2"] && more.froms == ["s0", "s0", "s0", "s0"] && more.upNext?.paged?.fetched == 5)
        #expect(withMore(first, token: "t0", tracks: simAlbum(2, "q")) == first)

        var whole = first
        whole.upNext?.paged?.fetched = 450
        let fresh = withMore(whole, token: "t1", tracks: simAlbum(2, "r"), next: Paged(token: "t2", total: 450, fetched: 0, scope: .store))
        #expect(Array(fresh.froms.suffix(2)) == ["s1", "s1"])
        #expect(fresh.upNext?.paged == Paged(token: "t2", total: 450, fetched: 2, scope: .store))
        #expect(withMore(whole, token: "t1", tracks: [], next: Paged(token: "t9", total: 0, fetched: 0, scope: .store)) == whole)
        #expect(withMore(first, token: "t1", tracks: []) == first)

        let off = withRepeat(fresh.at(2), .off)
        #expect(off.after == [] && off.upNext?.paged == Paged(token: "t1", total: 450, fetched: 450, scope: .store))
        #expect(off.upNext?.pagedRounds == [])
        #expect(withRepeat(fresh.at(2), .one).upNext?.paged?.token == "t1" && withRepeat(fresh.at(2), .all) == fresh.at(2))

        let restarted = withMore(first, token: "t1", tracks: simAlbum(2, "r"), next: Paged(token: "t3", total: 450, fetched: 0, scope: .store))
        #expect(Array(restarted.froms.suffix(2)) == ["s0", "s0"] && restarted.upNext?.paged?.token == "t3")
        #expect(restarted.upNext?.pagedRounds == nil)

        let view = upNextView(first, .off)
        #expect(view.list?.title == "All music, shuffled" && view.list?.more == 447)
        var yours = first
        yours.upNext?.paged?.scope = .yours
        #expect(upNextView(yours, .all).then == "Then your library again, in a new order.")
        #expect(upNextView(first, .all).then == "Then all music again, in a new order.")
    }

    @Test func theWords() { // :423-432
        #expect(listTitle(simAlbum(2), again: false) == "From Mezzanine")
        #expect(listTitle(simAlbum(2), again: true) == "From Mezzanine, again")
        #expect(listTitle([simTrack("1"), simTrack("2", albumId: "x")], again: true) == "Still to play, again")
        #expect(listTitle([simTrack("1", albumId: nil)], again: false) == "Still to play")
        #expect(listTitle([simTrack("1", albumId: "")], again: false) == "Still to play")
        #expect(queuedWords(.next, label: "Roads") == "Playing next: Roads")
        #expect(queuedWords(.last, label: "Dummy") == "Added to Up Next: Dummy")
        #expect(Repeat.allCases.map(repeatLabel) == ["Repeat", "Repeat all", "Repeat one"])
        #expect(shuffleLabel(nil) == "Shuffle")
        #expect(shuffleLabel(.store) == "Shuffle - shuffling all music")
        #expect(shuffleLabel(.yours) == "Shuffle - shuffling your whole library")
        #expect([upNextLabel(shuffle: false, repeat: .off), upNextLabel(shuffle: true, repeat: .off), upNextLabel(shuffle: false, repeat: .all),
                 upNextLabel(shuffle: false, repeat: .one), upNextLabel(shuffle: true, repeat: .all)]
                == ["Up Next", "Up Next - Shuffle on", "Up Next - Repeat all", "Up Next - Repeat one", "Up Next - Shuffle and Repeat all"])
    }

    @Test func theSheetsOwnWords() { // UpNext.tsx
        #expect(UpNextWords.more(1) == "And 1 more song.")
        #expect(UpNextWords.more(29) == "And 29 more songs.")
        #expect(UpNextWords.more(3_997) == "And 3,997 more songs.")
        #expect(UpNextWords.more(1_234_567) == "And 1,234,567 more songs.")
        #expect(UpNextWords.more(999) == "And 999 more songs.")
        #expect(UpNextWords.more(100_000) == "And 100,000 more songs.")
        #expect(UpNextWords.songLine(artist: "Massive Attack", album: "Mezzanine") == "Massive Attack · Mezzanine")
        #expect(UpNextWords.songLine(artist: "", album: "Mezzanine") == "Mezzanine")
        #expect(UpNextWords.songLine(artist: "", album: "") == "")
        #expect(UpNextWords.repeatingOne == "Repeat one: this song plays again until you skip it.")
        #expect(UpNextWords.shufflingLibrary == "Shuffling your whole library")
        #expect(UpNextWords.playNow("Angel") == "Angel, play now")
        #expect(UpNextWords.playAgain("Angel") == "Angel, play again" && UpNextWords.playing("Angel") == "Playing Angel")
        #expect(UpNextWords.history == "History")
        #expect([UpNextWords.moveUp("Angel"), UpNextWords.moveDown("Angel"), UpNextWords.remove("Angel")]
                == ["Move Angel up", "Move Angel down", "Remove Angel"])
        #expect([UpNextWords.shuffleSaid(true), UpNextWords.shuffleSaid(false)] == ["Shuffle on", "Shuffle off"])
        #expect(Repeat.allCases.map(UpNextWords.repeatSaid) == ["Repeat off", "Repeat all", "Repeat one"])
        #expect(UpNextWords.movedSaid("Angel", to: 0, of: 3) == "Angel: 1 of 3")
        #expect(UpNextWords.removedSaid("Angel") == "Angel removed")
        #expect(UpNextWords.clearedSaid == "Playing Next cleared")
        // SwiftUI's onMove: one row down (from 0 to before 2) is place 1; up (from 2 to before 0) is place 0
        #expect(UpNextWords.movedTo(from: 0, destination: 2) == 1 && UpNextWords.movedTo(from: 2, destination: 0) == 0)
    }
}

/// (2.1.3) History, and a tap that keeps what it passes - upnext.sim.cjs's 2.1.3 section, check by check.
@Suite struct UpNextHistoryTests {
    /// Previous early, as the player moves: backward's place, startedAt following it down (wentBack).
    private func previous(_ queue: UpNextQueue) -> UpNextQueue {
        if case .go(let index) = backward(queue, position: 1) { return wentBack(queue, index) }
        return queue
    }
    private func history(_ queue: UpNextQueue) -> [String] { historyRows(queue).map(\.track.id) }

    @Test func jamesWalk() { // :361-374
        var q = startUpNext(simAlbum(12), start: 0).at(4)
        let jump = jumpedTo(q, q.key("8")!, .off)!
        #expect(jump.queue == q && jump.index == 7 && !jump.back)
        q = jump.queue.at(jump.index)
        #expect(q.current?.id == "8" && q.ids == simAlbum(12).map(\.id) && q.upNext?.left == [])
        #expect(upNextView(q, .off).history.map(\.track.id) == ["1", "2", "3", "4", "5", "6", "7"])
        #expect(upNextView(q, .off).list?.rows.map(\.track.id) == ["9", "10", "11", "12"])
        var walk: [String] = []
        for _ in 0..<3 {
            q = previous(q)
            walk.append(q.current!.id)
        }
        #expect(walk == ["7", "6", "5"])
        q = q.at(onward(q)!)
        #expect(q.current?.id == "6" && q.ended.current?.id == "7")
    }

    @Test func aSongAddedStaysNextAfterTheTapAndPlaysWhereItPlayedAfterPrevious() { // :375-387
        let start = withNext(startUpNext(simAlbum(12), start: 0).at(4), [simTrack("a", album: "Dummy", albumId: "dum")])
        let jump = jumpedTo(start, start.key("8")!, .off)!
        var q = jump.queue.at(jump.index)
        #expect(jump.index == 7 && Array(q.ids[4..<10]) == ["5", "6", "7", "8", "a", "9"])
        #expect(upNextView(q, .off).added.map(\.track.id) == ["a"])
        q = previous(q)
        let v = upNextView(q, .off)
        #expect(q.current?.id == "7" && v.added.isEmpty && v.list?.title == "From Mezzanine")
        #expect(v.list?.rows.map(\.track.id) == ["8", "a", "9", "10", "11", "12"] && withoutAdded(q) == q)
        let aKey = q.key("a")!
        let tapA = jumpedTo(q, aKey, .off)!
        #expect(Array(movedKey(q, aKey, to: 0).after.prefix(3)) == ["a", "8", "9"])
        #expect(Array(withoutKey(q, aKey).after.prefix(2)) == ["8", "9"])
        #expect(tapA.queue == q && tapA.queue.at(tapA.index).current?.id == "a")
    }

    @Test func historyIsWhatIsBehindTheSongPlaying() { // :389-422
        let fromFive = startUpNext(simAlbum(12), start: 4)
        #expect(upNextView(fromFive, .off).history.isEmpty && backward(fromFive, position: 1) == .go(3))
        #expect(upNextView(fromFive.at(6), .off).history.map(\.track.id) == ["5", "6"])
        let back = previous(fromFive)
        #expect(back.current?.id == "4" && back.upNext?.startedAt == 3 && history(back).isEmpty && back.tracks == fromFive.tracks)
        #expect(history(back.ended) == ["4"])
        let later = fromFive.at(6)
        // wentBack at or after where listening began: the place moves, the account the same but for how far it had got
        // (2.1.18 reached, 7's key) - and again from there, the same account, the furthest kept
        let wb = wentBack(later, 5)
        var unreached = wb.upNext
        unreached?.reached = nil
        #expect(wb.index == 5 && wb.tracks == later.tracks && unreached == later.upNext && wb.upNext?.reached == later.upNext?.marks[6].key)
        #expect(wentBack(wb, 4).upNext == wb.upNext)
        let plain = UpNextQueue(tracks: simAlbum(3), index: 2)
        #expect(wentBack(plain, 1) == UpNextQueue(tracks: simAlbum(3), index: 1))
        let shuffled = startUpNext(simAlbum(6), start: 3, shuffle: true, random: Seeded(5).next)
        #expect(history(shuffled.at(3)) == Array(shuffled.ids.prefix(3)))
        let library = startUpNext(simAlbum(3), start: 0, paged: Paged(token: "t", total: 9, fetched: 3, scope: .yours))
        #expect(history(library.at(2)) == ["1", "2"])
        // Repeat One on song 2 for three plays, then off, then on to 4
        var one = toppedUp(startUpNext(simAlbum(5), start: 0).at(1), .one)
        one = toppedUp(one.ended, .one).ended
        one = toppedUp(withRepeat(one, .off), .off)
        one = one.at(onward(one)!)
        one = one.at(onward(one)!)
        let oneView = upNextView(one, .off)
        #expect(Array(one.ids.prefix(one.index + 1)) == ["1", "2", "2", "2", "3", "4"])
        #expect(oneView.history.map(\.track.id) == ["1", "2", "3"] && oneView.history[1].key == one.upNext!.marks[1].key)
        #expect(history(one.at(2)) == ["1"])
        var all = toppedUp(startUpNext(simAlbum(3), start: 0), .all)
        for _ in 0..<4 { all = toppedUp(all.ended, .all) }
        #expect(all.current?.id == "2" && upNextView(all, .all).history.map(\.track.id) == ["1", "2", "3", "1"])
        let long = startUpNext(simAlbum(80), start: 0).at(70)
        let lv = upNextView(long, .off)
        #expect(UpNext.historyBack == 50 && lv.history.count == 50)
        #expect(lv.history.first?.track.id == "21" && lv.history.last?.track.id == "70")
        #expect(historyRows(.empty).isEmpty)
        #expect(UpNext.historyBack == Resume.before) // what a reload keeps, so History after one is the same
    }

    @Test func aUnitIsOneSong() { // :423-445 (review)
        var q = toppedUp(startUpNext(simAlbum(5), start: 0).at(1), .one)
        q = toppedUp(previous(q), .one)
        #expect(q.ids == ["1", "1", "1", "2", "2", "2", "3", "4", "5"])
        q = withShuffle(q, true, random: Seeded(7).next)
        #expect(Array(q.ids.prefix(3)) == ["1", "1", "1"] && q.ids.filter { $0 == "2" }.count == 1)
        #expect(q.upNext!.marks.filter { $0.from == .one }.count == 2)
        q = toppedUp(q.at(onward(q)!), .one)
        guard case .go(let index) = backward(q, position: 0) else {
            Issue.record("Previous restarted")
            return
        }
        #expect(history(q) == ["1"] && q.tracks[index].id == "1")
        var r = toppedUp(startUpNext(simAlbum(2), start: 0).at(1), .all)
        r = toppedUp(r.ended, .all)
        r = toppedUp(withRepeat(r, .one), .one)
        r = toppedUp(previous(r), .one)
        #expect(r.current?.id == "2" && r.froms == ["o", "o", "s1", "o", "o", "s1"])
        // (2.1.18) Previous walked back from the second round's 1, so that round played: Repeat lets go only of rounds
        // after it - Repeat One asked of it keeps it; a later round nobody reached goes, its copies with it
        #expect(withRepeat(r, .one) == r)
        var unreached = r
        unreached.upNext?.reached = nil
        let fresh = withRepeat(unreached, .one)
        #expect(Array(fresh.ids.dropFirst(fresh.index)) == ["2", "2", "2"] && fresh.froms == ["o", "o"])
    }

    /// (2.1.18) James's: A, B, C, D played, D playing, songs added waiting - "Keep their place": tap B, then B, C, D, the
    /// songs added, the rest. upnext.sim.cjs's 2.1.18 section (:762-795), check by check.
    @Test func historysTapRollsBack() {
        let abc = ["A", "B", "C", "D", "E", "F"].map { simTrack($0) }
        var q = withNext(startUpNext(abc, start: 0).at(3), [simTrack("n1"), simTrack("n2")])
        let jump = jumpedTo(q, q.upNext!.marks[1].key, .off)!
        // a roll-back to B - the same songs, in the same order, the place moved back to it
        #expect(jump.back && jump.index == 1 && jump.queue.index == 1 && jump.queue.ids == ["A", "B", "C", "D", "n1", "n2", "E", "F"])
        #expect(jump.queue.tracks == q.tracks && jump.queue.upNext?.marks == q.upNext?.marks)
        q = jump.queue
        let v = upNextView(q, .off)
        // Up Next: C, D, the songs added where they were, then the rest - History above it A
        #expect(q.current?.id == "B" && v.history.map(\.track.id) == ["A"] && v.added.isEmpty)
        #expect(v.list?.rows.map(\.track.id) == ["C", "D", "n1", "n2", "E", "F"] && v.list?.title == "From Mezzanine")
        #expect(q.after == ["C", "D", "n1", "n2", "E", "F"])
        #expect(previous(q).current?.id == "A" && q.at(onward(q)!).current?.id == "C" && q.ended.ended.current?.id == "D")
        // the furthest song played named (D), so the list runs on to it and past it
        #expect(q.upNext?.reached == q.upNext?.marks[3].key)
        var walk = q
        var heard: [String] = []
        for _ in 0..<6 {
            walk = walk.ended
            heard.append(walk.current!.id)
        }
        #expect(heard == ["C", "D", "n1", "n2", "E", "F"] && history(walk) == ["A", "B", "C", "D", "n1", "n2", "E"])
        // the songs added keep their place: Clear above the card doesn't reach them (they play after D)
        #expect(withoutAdded(q) == q)
        // C playing, tap A: the furthest played still D; then a list row tapped from there - the rows it passes behind it
        let deeper = jumpedTo(q.at(2), q.upNext!.marks[0].key, .off)!
        #expect(deeper.queue.upNext?.reached == q.upNext?.marks[3].key)
        #expect(upNextView(deeper.queue, .off).list?.rows.map(\.track.id) == ["B", "C", "D", "n1", "n2", "E", "F"])
        let toE = jumpedTo(deeper.queue, deeper.queue.key("E")!, .off)!
        #expect(toE.queue.at(toE.index).ids == ["A", "B", "C", "D", "n1", "n2", "E", "F"] && !toE.back)

        // with no copies, a History tap is Previous's walk to it, one row at a time - the queue's own tracks
        let nine = startUpNext(simAlbum(9), start: 0).at(6)
        var w = nine
        while w.index > 2 { w = previous(w) }
        let three = jumpedTo(nine, nine.upNext!.marks[2].key, .off)!
        #expect(three.queue == w && three.queue.tracks == nine.tracks)
    }

    @Test func aRollBackUnderRepeat() { // :796-889 (2.1.18)
        // Repeat One: the copies stay - the run played as drawn; off and All: a row plays once, the copies after it go
        var one = toppedUp(startUpNext(simAlbum(4), start: 0).at(1), .one)
        one = toppedUp(one.ended, .one)
        one = toppedUp(one.ended, .one)
        one = toppedUp(withRepeat(one, .off), .off)
        one = one.at(onward(one)!)
        one = toppedUp(withRepeat(one, .one), .one)
        #expect(one.ids == ["1", "2", "2", "2", "3", "3", "3", "4"] && one.current?.id == "3")
        let kept = jumpedTo(one, one.upNext!.marks[1].key, .one)!
        #expect(kept.index == 1 && kept.queue.ids == ["1", "2", "2", "2", "3", "3", "3", "4"])
        let off = jumpedTo(toppedUp(withRepeat(one, .off), .off), one.upNext!.marks[1].key, .off)!
        #expect(off.index == 1 && off.queue.ids == ["1", "2", "3", "4"] && upNextView(off.queue, .off).list?.rows.map(\.track.id) == ["3", "4"])
        #expect(jumpedTo(one, one.upNext!.marks[4].key, .one) == nil && jumpedTo(one, one.upNext!.marks[5].key, .one) == nil)
        #expect(jumpedTo(one, 99, .one) == nil)
        let fromFive = startUpNext(simAlbum(12), start: 4).at(6)
        #expect(jumpedTo(fromFive, fromFive.upNext!.marks[1].key, .off) == nil)
        let long = startUpNext(simAlbum(80), start: 0).at(70)
        let oldest = jumpedTo(long, long.upNext!.marks[20].key, .off)!
        #expect(jumpedTo(long, long.upNext!.marks[19].key, .off) == nil && oldest.queue.current?.id == "21")
        #expect(oldest.queue.after.count == 59 && upNextView(oldest.queue, .off).list?.more == 0 && historyRows(oldest.queue).count == 20)

        // Repeat All: a roll-back into the earlier round - the rounds after it moved back down, drawn whole
        var rounds = toppedUp(startUpNext(simAlbum(3), start: 0).at(2), .all)
        rounds = toppedUp(rounds.ended, .all)
        rounds = toppedUp(rounds.ended, .all)
        #expect(rounds.current?.id == "2" && rounds.froms == ["s1", "s2", "s2", "s2"])
        let back = jumpedTo(rounds, rounds.upNext!.marks[0].key, .all)!
        let v = upNextView(back.queue, .all)
        #expect(back.queue.current?.id == "1" && v.list?.rows.map(\.track.id) == ["2", "3", "1", "2", "3"] && v.list?.title == "From Mezzanine")
        let repeatOff = withRepeat(back.queue, .off)
        #expect(repeatOff.after == ["2", "3", "1", "2", "3"] && upNextView(repeatOff, .off).list?.rows.map(\.track.id) == ["2", "3", "1", "2", "3"])
        #expect(Array(toppedUp(withRepeat(back.queue, .one), .one).after.prefix(7)) == ["1", "1", "2", "3", "1", "2", "3"])
        // Edit's moves: each place keeps its time round, so the rounds never go down - and every song is still drawn
        let movedUp = movedKey(back.queue, back.queue.upNext!.marks[3].key, to: 0)
        #expect(Array(movedUp.after.prefix(5)) == ["1", "2", "3", "2", "3"] && Array(movedUp.froms.prefix(5)) == ["s0", "s0", "s1", "s1", "s1"])
        #expect(upNextView(movedUp, .all).list?.rows.map(\.track.id) == ["1", "2", "3", "2", "3"])
        // the furthest played taken out, or moved up: the reach handed to the unit before it, or the last of them now
        let reachKey = back.queue.upNext!.reached!
        let removed = withoutKey(back.queue, reachKey)
        #expect(removed.upNext?.reached == back.queue.upNext!.marks[3].key)
        #expect(upNextView(removed, .all).list?.rows.map(\.track.id) == ["2", "3", "1", "3"])
        let reachUp = movedKey(back.queue, reachKey, to: 0)
        #expect(reachUp.upNext?.reached == back.queue.upNext!.marks[3].key)
        #expect(upNextView(reachUp, .all).list?.rows.map(\.track.id) == ["2", "2", "3", "1", "3"])
        // (2.1.18 review) Shuffle on after it: each round shuffled on its own, all drawn; off: the list's order
        let turnedOn = withShuffle(back.queue, true, random: Seeded(5).next)
        #expect(turnedOn.current?.id == "1" && Array(turnedOn.after.prefix(2)).sorted() == ["2", "3"])
        #expect(Array(turnedOn.after.dropFirst(2)).sorted() == ["1", "2", "3"] && turnedOn.froms == ["s0", "s0", "s1", "s1", "s1"])
        #expect(upNextView(turnedOn, .all).list?.rows.map(\.track.id) == turnedOn.after && turnedOn.upNext?.shuffle == true)
        let orders = (0..<200).map { seed -> [String] in
            let random = Seeded(Int64(seed + 1))
            _ = random.next()
            return withShuffle(back.queue, true, random: random.next).after
        }
        // over 200 orders: the first round's 2 and 3 both ways, the second's all six, never starting with the song that
        // ends the first's (toppedUp's rule)
        #expect(Set(orders.map { $0.prefix(2).joined(separator: ",") }).count == 2)
        #expect(Set(orders.map { $0.dropFirst(2).joined(separator: ",") }).count == 6 && orders.filter { $0[1] == $0[2] }.isEmpty)
        let offAgain = withShuffle(turnedOn, false)
        #expect(offAgain.after == ["2", "3", "1", "2", "3"] && offAgain.froms == ["s0", "s0", "s1", "s1", "s1"])
        #expect(withRepeat(offAgain, .off).after == ["2", "3", "1", "2", "3"] && withRepeat(turnedOn, .off).after.count == 5)

        // ...each unit whole: the second round's 1 three times over and its 2 twice (Repeat One), the first round's 2 tapped
        var c = toppedUp(startUpNext(simAlbum(3), start: 0).at(2), .all)
        c = toppedUp(withRepeat(c.ended, .one), .one)
        c = toppedUp(c.ended, .one)
        c = toppedUp(c.ended, .one)
        c = toppedUp(c.at(onward(c)!), .one)
        let tapped = jumpedTo(c, c.upNext!.marks[1].key, .one)!.queue
        let runs = { (q: UpNextQueue) -> [String] in
            var list: [String] = []
            for (i, id) in q.after.enumerated() {
                if i > 0 && q.upNext!.marks[q.index + 1 + i].from == .one { list[list.count - 1] += id } else { list.append(id) }
            }
            return list
        }
        let shuffles = Set((0..<12).map { seed in
            runs(withShuffle(tapped, true, random: Seeded(Int64(seed + 1)).next)).dropFirst().sorted().joined(separator: ",")
        })
        #expect(runs(tapped) == ["3", "11111", "222", "3"] && shuffles == ["11111,222,3"])
        #expect(runs(withShuffle(withShuffle(tapped, true, random: Seeded(1).next), false)) == ["3", "11111", "222", "3"])
    }

    @Test func pastUpNextsHundredTheRoundMovedBackDownIsHeld() { // :859-875 (2.1.18 review)
        // 200 songs under Repeat All begun at 150, played round to the second time's 10, the first time's 200 tapped in
        // History, then Shuffle on: wherever the second round's 1-10 land, the queue holds every one (shownKeys), the
        // furthest played the last of them
        var long = toppedUp(startUpNext(simAlbum(200), start: 149), .all)
        while long.index < 209 { long = toppedUp(long.ended, .all) }
        let tapped = jumpedTo(long, long.upNext!.marks[199].key, .all)!.queue
        let played = tapped.upNext!.marks[200..<210].map(\.key)
        let held = (0..<6).map { seed -> Bool in
            let on = withShuffle(tapped, true, random: Seeded(Int64(seed + 11)).next)
            let shown = shownKeys(on)
            let places = played.compactMap { key in on.upNext!.marks.firstIndex { $0.key == key } }
            return played.allSatisfy(shown.contains) && places.count == played.count
                && on.upNext?.reached == on.upNext!.marks[places.max()!].key
        }
        #expect(tapped.current?.id == "200" && tapped.after.count == 200 && held == Array(repeating: true, count: 6))
    }

    @Test func aShuffleRolledBackKeepsItsOrder() { // :876-889
        let shuffled = startUpNext(simAlbum(6), start: 0, shuffle: true, random: Seeded(3).next).at(4)
        let rolled = jumpedTo(shuffled, shuffled.upNext!.marks[1].key, .off)!
        #expect(rolled.queue.after == Array(shuffled.ids.dropFirst(2)) && rolled.queue.upNext?.shuffle == true)
        // Shuffle turned on after one: the song added kept first, the list's songs to come in a new order
        let plain = withNext(startUpNext(simAlbum(6), start: 0).at(4), [simTrack("a")])
        let turned = withShuffle(jumpedTo(plain, plain.upNext!.marks[1].key, .off)!.queue, true, random: Seeded(4).next)
        #expect(turned.current?.id == "2" && turned.after.first == "a" && turned.after.dropFirst().sorted().joined(separator: ",") == "3,4,5,6")
    }

    @Test func olderRowsBroughtBack() { // :890-930 (2.1.18)
        // an album at 71: z played in another queue (twice in a run), then this album from its start - its 1-20 older
        // rows (past History's 50); each row's song as the screen passes it, at the setting's level for a song (track)
        let q = startUpNext(simAlbum(80).map { song -> QueueTrack in
            var at = song
            at.level = .album
            return at
        }, start: 0).at(70)
        let rows = (0..<20).map { i -> Brought in
            var song = q.tracks[i]
            song.level = .track
            return Brought(track: song, starts: [1000 + Int64(i)], entry: q.upNext!.marks[i].key)
        }
        var z = simTrack("z", album: "Dummy", albumId: "dum")
        z.level = .track
        let elsewhere = Brought(track: z, starts: [900, 901], entry: nil)
        let jump = broughtBack(q, [elsewhere] + rows, .off)!
        #expect(jump.back && jump.index == 0 && jump.queue.current?.id == "z" && Array(jump.queue.ids.prefix(4)) == ["z", "1", "2", "3"])
        #expect(jump.queue.tracks.count == 81)
        // z a song added; 1-20 moved - their own entries, the list's; each carrying the starts its row stood for
        let first = Array(jump.queue.upNext!.marks.prefix(3))
        #expect(first.map(\.key) == [80, 0, 1] && first.map(\.from) == [.added, .source, .source])
        #expect(first.map(\.starts) == [[900, 901], [1000], [1001]])
        // (2.1.18 review) 1-20 each their own track, the list's (album) - not the row's copy; z the row's own
        #expect(Array(jump.queue.tracks[1...20]) == Array(q.tracks[0..<20]) && jump.queue.tracks[1].level == .album)
        #expect(jump.queue.tracks[0] == z)
        // to come, as drawn: 1-20, History's 21-70, 71 (the song that was playing), 72-80 - every song after it, in order
        let every = upNextView(jump.queue, .off, limit: Int.max)
        #expect(every.list?.rows.map(\.track.id) == simAlbum(80).map(\.id))
        #expect(every.list?.title == upNextView(q, .off).list?.title && upNextView(jump.queue, .off).list?.title == "From Mezzanine")
        // nothing before it; the same queue; the starts it holds, by song and moment
        #expect(historyRows(jump.queue).isEmpty && backward(jump.queue, position: 0) == .restart && jump.queue.upNext?.startedAt == 0)
        #expect(jump.queue.upNext?.id == q.upNext?.id && jump.queue.upNext?.source == q.upNext?.source)
        #expect(Array(heldStarts(jump.queue).prefix(4)) == [
            HeldStart(id: "z", at: 900), HeldStart(id: "z", at: 901), HeldStart(id: "1", at: 1000), HeldStart(id: "2", at: 1001),
        ])
        // one older row, 13: it, then History's 21 on; rows out of the queue's order: the first moved, the other added
        let one = broughtBack(q, [rows[12]], .off)!
        #expect(Array(one.queue.ids.prefix(3)) == ["13", "21", "22"] && one.queue.tracks.count == 61)
        let out = broughtBack(q, [rows[2], rows[0]], .off)!
        #expect(out.queue.upNext!.marks.prefix(2).map(\.from) == [.source, .added])
        #expect(broughtBack(q, [], .off) == nil && broughtBack(.empty, rows, .off) == nil)
        // a library's shuffle carries on: its pages still land at the end, and what is to come counts them
        let lib = startUpNext(simAlbum(3, "p"), start: 0, paged: Paged(token: "t1", total: 40, fetched: 3, scope: .yours)).at(2)
        let libBack = broughtBack(lib, [Brought(track: simTrack("old"), starts: [5], entry: nil)], .off)!
        let more = withMore(libBack.queue, token: "t1", tracks: simAlbum(2, "q"))
        #expect(more.ids == ["old", "p1", "p2", "p3", "q1", "q2"] && upNextView(more, .off).list?.more == 35)
        #expect(more.upNext?.paged?.fetched == 5)
    }

    @Test func theFloorDrawnKeepsTheQueueFromThere() { // :931-951 (2.1.18 review)
        // History at its 50 (10-59, 60 playing), older rows 5-9 tapped - the engine had crossed into 61 first, so the
        // controller's catch-up moved History's floor on (11). The rows were read against 10's: `floor` keeps it
        let drawn = startUpNext(simAlbum(80), start: 0).at(59)
        let floor = historyRows(drawn)[0].key
        let caught = drawn.at(60)
        let rows = [4, 5, 6, 7, 8].map { i in Brought(track: drawn.tracks[i], starts: [2000 + Int64(i)], entry: drawn.upNext!.marks[i].key) }
        let withFloor = broughtBack(caught, rows, .off, floor: floor)!
        let without = broughtBack(caught, rows, .off)!
        #expect(historyRows(drawn)[0].track.id == "10" && historyRows(caught)[0].track.id == "11")
        #expect(withFloor.queue.ids == Array(simAlbum(80).map(\.id).dropFirst(4)))
        #expect(!without.queue.ids.contains("10") && without.queue.tracks.count == 75)
        // the floor at or after History's own (no race), or a key it hasn't: as without it - History's floor
        let same = { (f: Int) in broughtBack(caught, rows, .off, floor: f)?.queue.ids == without.queue.ids }
        #expect(same(historyRows(caught)[0].key) && same(caught.upNext!.marks[70].key) && same(999))
    }

    @Test func shuffleOffAfterAJumpInAShuffle() { // :479-487
        let shuffled = startUpNext(simAlbum(6), start: 0, shuffle: true, random: Seeded(2).next)
        let order = shuffled.ids
        let jump = jumpedTo(shuffled, shuffled.upNext!.marks[3].key, .off)!
        let off = withShuffle(jump.queue.at(jump.index), false)
        #expect(jump.queue == shuffled && Array(off.ids.prefix(4)) == Array(order.prefix(4)) && off.current?.id == order[3])
        #expect(off.after == simAlbum(6).map(\.id).filter { Int($0)! > Int(order[3])! })
    }

    @Test func previousAcrossSongsAddedDrawsTheListThroughThem() { // the 2.1.3 commit: 190ebaa drew ["4"]
        let q = previous(withNext(startUpNext(simAlbum(6), start: 0).at(3), [simTrack("a"), simTrack("b")]))
        let v = upNextView(q, .off)
        #expect(q.current?.id == "3" && v.added.isEmpty && v.list?.rows.map(\.track.id) == ["4", "a", "b", "5", "6"])
        #expect(withoutAdded(q) == q)
    }
}
