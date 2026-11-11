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

    @Test func aRowsTap() { // :268-282
        let start = withLast(startUpNext(simAlbum(5), start: 0), [simTrack("a"), simTrack("b")])
        let toList = jumpedTo(start, start.key("4")!)!
        let moved = toList.at(onward(toList)!)
        #expect(moved.current?.id == "4" && moved.after == ["a", "b", "5"])
        #expect(toList.upNext?.left == [LeftOut(pass: 0, at: 1), LeftOut(pass: 0, at: 2)])
        let toAdded = jumpedTo(start, start.key("b")!)!
        let there = toAdded.at(onward(toAdded)!)
        #expect(there.current?.id == "b" && there.after == ["2", "3", "4", "5"])
        #expect(jumpedTo(start, start.upNext!.marks[0].key) == nil)
        let copies = toppedUp(start, .one)
        #expect(jumpedTo(copies, copies.upNext!.marks[1].key) == nil)
        #expect(jumpedTo(start, 77) == nil)
        let one = toppedUp(startUpNext(simAlbum(3), start: 0), .one)
        let jumped = jumpedTo(one, one.key("3")!)!
        #expect(jumped.at(onward(jumped)!).current?.id == "3")
    }

    @Test func aJumpToAGroupsFirstRowIsANewButEqualQueue() {
        let start = startUpNext(simAlbum(4), start: 0)
        #expect(jumpedTo(start, start.key("2")!) == start)
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
        let jumped = jumpedTo(start.at(6), start.key("10")!)!
        let overJumped = withShuffle(jumped.at(onward(jumped)!), true, random: Seeded(3).next)
        #expect(overJumped.current?.id == "10" && !overJumped.after.contains("8") && !overJumped.after.contains("9"))

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
        #expect(withoutKey(.empty, 0) == .empty && movedKey(.empty, 0, to: 1) == .empty && jumpedTo(.empty, 0) == nil)
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
        #expect(upNextView(.empty, .all) == UpNextView(playing: nil, added: [], list: nil, then: nil, repeatOne: false))
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
