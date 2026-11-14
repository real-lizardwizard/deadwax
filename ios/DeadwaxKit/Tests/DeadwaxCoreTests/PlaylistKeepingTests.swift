import Foundation
import Testing
@testable import DeadwaxCore

// Slice 3's review: the keeper's order, pure (PlaylistKeeping) - a row written before its songs are asked for, deleted
// before its origin is taken, nothing touched after a write that failed, an answer older than one taken in dropped -
// and a smart playlist never downloaded, a downloaded one found smart kept as it was.

private let minute: Int64 = 60_000
private let t0: Int64 = 1_800_000_000_000

private func song(_ id: String) -> Song {
    Song(id: id, title: "Song \(id)", album: "Album", albumId: "al-\(id)", artist: "Someone", duration: 200)
}

private func answer(_ ids: [String], id: String = "p1", changed: String = "c1", smart: Bool = false, hidden: Int = 0)
    -> PlaylistWithSongs {
    PlaylistWithSongs(playlist: Playlist(id: id, name: "Late night", songCount: ids.count, changed: changed, owner: "james",
                                         mine: true, editable: !smart, smart: smart),
                      songs: ids.map { (id: String) -> Song in song(id) }, hidden: hidden)
}

private func kept(_ ids: [String], id: String = "p1", left: [String: Int64] = [:], askedAt: Int64 = t0 - minute)
    -> KeptPlaylist {
    KeptPlaylist(id: id, answer: answer(ids, id: id), body: Data("{}".utf8), readAt: t0, left: left, askedAt: askedAt)
}

private struct Refused: Error {}

/// What a run did, in order.
private final class Record {
    var steps: [String] = []
    var applied: [PlaylistKeeping.Change] = []
    var failWrite = false
    var failTake = false

    func run(_ change: PlaylistKeeping.Change, into keeping: inout PlaylistKeeping) -> Bool {
        var applied: PlaylistKeeping.Change?
        let made = PlaylistKeeping.run(change, write: { (write: PlaylistKeeping.Write) throws -> Void in
            switch write {
            case .put(let entry): self.steps.append("put \(entry.id)")
            case .delete(let id): self.steps.append("delete \(id)")
            }
            if self.failWrite { throw Refused() }
        }, apply: { (change: PlaylistKeeping.Change) -> Void in
            self.steps.append("apply")
            applied = change
        }, take: { (songs: [String], id: String) -> Bool in
            self.steps.append("take \(songs.joined(separator: ",")) from \(id)")
            return !self.failTake
        }, ask: { (songs: [Song], id: String) -> Void in
            self.steps.append("ask \(songs.map(\.id).joined(separator: ",")) for \(id)")
        })
        if let applied { keeping.apply(applied) }
        return made
    }
}

@Suite struct PlaylistKeepingTests {
    // MARK: the order

    @Test func aDownloadWritesItsRowBeforeAskingForItsSongs() throws {
        var keeping = PlaylistKeeping()
        let record = Record()
        let change = try #require(keeping.download(answer(["s1", "s2"]), body: Data("b".utf8), at: t0, carrying: ["s2"]))
        let made1 = record.run(change, into: &keeping)
        #expect(made1)
        #expect(record.steps == ["put p1", "apply", "ask s1 for p1"], "the song already carrying it isn't asked again")
        #expect(keeping.kept.map(\.id) == ["p1"] && keeping.kept.first?.body == Data("b".utf8))
        // downloaded already: nothing
        #expect(keeping.download(answer(["s1"]), body: Data(), at: t0, carrying: []) == nil)
    }

    @Test func aWriteThatFailsTouchesNothingAfterIt() throws {
        var keeping = PlaylistKeeping()
        let record = Record()
        record.failWrite = true
        let change = try #require(keeping.download(answer(["s1"]), body: Data(), at: t0, carrying: []))
        let made2 = record.run(change, into: &keeping)
        #expect(!made2)
        #expect(record.steps == ["put p1"], "not kept in memory, nothing asked")
        #expect(keeping.kept.isEmpty)
        // a delete that fails: the row and the songs stay, nothing taken
        keeping = PlaylistKeeping(kept: [kept(["s1"])])
        let removing = try #require(keeping.remove("p1", carrying: ["s1"]))
        let refused = Record()
        refused.failWrite = true
        let made3 = refused.run(removing, into: &keeping)
        #expect(!made3)
        #expect(refused.steps == ["delete p1"])
        #expect(keeping.kept.map(\.id) == ["p1"])
    }

    @Test func aRemoveDeletesTheRowBeforeTakingItsOrigin() throws {
        var keeping = PlaylistKeeping(kept: [kept(["s1", "s2"]), kept(["s9"], id: "p2")])
        let record = Record()
        let change = try #require(keeping.remove("p1", carrying: ["s2", "s1"]))
        let made4 = record.run(change, into: &keeping)
        #expect(made4)
        #expect(record.steps == ["delete p1", "apply", "take s1,s2 from p1"])
        #expect(keeping.kept.map(\.id) == ["p2"])
        #expect(keeping.remove("p1", carrying: []) == nil, "not kept: nothing")
        // nothing carrying it: the row alone
        #expect(try #require(keeping.remove("p2", carrying: [])).effects.isEmpty)
    }

    @Test func aTakeThatFailsStopsTheAsksAfterIt() throws {
        // s3 agreed gone, s4 new: the take first, and the ask never made when the store can't be written
        var keeping = PlaylistKeeping(kept: [kept(["s1", "s3"], left: ["s3": t0 - 20 * minute])])
        let change = try #require(keeping.took(answer(["s1", "s4"]), body: Data(), at: t0, carrying: ["s1", "s3"]))
        #expect(change.effects == [.take(["s3"], from: "p1"), .ask([song("s4")], for: "p1")])
        let record = Record()
        record.failTake = true
        let made5 = record.run(change, into: &keeping)
        #expect(made5, "the row was written: the change holds")
        #expect(record.steps == ["put p1", "apply", "take s3 from p1"])
    }

    @Test func anAnswerOlderThanOneTakenInIsDropped() throws {
        var keeping = PlaylistKeeping(kept: [kept(["s1", "s2"])])
        // a read goes out
        let since = keeping.serial("p1")
        // this phone's Edit takes s2 out, its answer taken in meanwhile
        let edit = try #require(keeping.took(answer(["s1"]), body: Data(), at: t0, edited: ["s2"], carrying: ["s1", "s2"]))
        #expect(edit.takesIn == "p1")
        let made6 = Record().run(edit, into: &keeping)
        #expect(made6)
        #expect(keeping.serial("p1") == since + 1)
        // the read's answer, sent before the Edit, still lists s2: dropped, so s2 isn't asked for again
        #expect(keeping.answered(answer(["s1", "s2"]), body: Data(), at: t0, since: since, carrying: ["s1"]) == nil)
        #expect(keeping.gone("p1", at: t0, since: since, carrying: ["s1"]) == nil)
        // one sent after it is taken in
        #expect(keeping.answered(answer(["s1"]), body: Data(), at: t0 + minute, since: keeping.serial("p1"), carrying: ["s1"]) != nil)
        // a list's marks don't move the serial: a read out across a list is still taken in
        let list = keeping.listed([Playlist(id: "p9", name: "x")], at: t0 + minute, carrying: { (_: String) -> Set<String> in [] })
        for change in list.changes {
            let made9 = Record().run(change, into: &keeping)
            #expect(made9)
        }
        #expect(keeping.serial("p1") == since + 1)
    }

    @Test func aReadAnsweredGoneIsMarkedThenLetGoTenMinutesOn() throws {
        var keeping = PlaylistKeeping(kept: [kept(["s1"])])
        let first = try #require(keeping.gone("p1", at: t0, since: 0, carrying: ["s1"]))
        #expect(first.effects.isEmpty)
        let made7 = Record().run(first, into: &keeping)
        #expect(made7)
        #expect(keeping.entry("p1")?.missingSince == t0)
        let record = Record()
        let second = try #require(keeping.gone("p1", at: t0 + 10 * minute, since: 0, carrying: ["s1"]))
        let made8 = record.run(second, into: &keeping)
        #expect(made8)
        #expect(record.steps == ["delete p1", "apply", "take s1 from p1"])
        #expect(keeping.kept.isEmpty)
    }

    @Test func aListWritesTheMarksItMovedAndLetsGoWhatTwoListsAgreeOn() throws {
        var gone = kept(["s9"], id: "p2")
        gone.missingSince = t0 - 10 * minute
        var keeping = PlaylistKeeping(kept: [kept(["s1"]), gone, kept(["s5"], id: "p3")])
        let listed = Playlist(id: "p3", name: "x", changed: "c2", owner: "james", mine: true, editable: true)
        let out = keeping.listed([listed], at: t0, carrying: { (id: String) -> Set<String> in id == "p2" ? ["s9"] : [] })
        #expect(out.toRead == ["p3"], "its changed moved")
        let record = Record()
        for change in out.changes {
            let made10 = record.run(change, into: &keeping)
            #expect(made10)
        }
        // p1 marked missing (written), p2 let go (deleted, then taken), p3 unchanged (not written)
        #expect(record.steps == ["put p1", "apply", "delete p2", "apply", "take s9 from p2"])
        #expect(keeping.kept.map(\.id) == ["p1", "p3"] && keeping.entry("p1")?.missingSince == t0)
    }

    @Test func aStoreOpeningTakesTheOrphansFirstThenActsOnEachPlaylist() {
        let keeping = PlaylistKeeping(kept: [kept(["s1", "s2"])])
        let origins: [String: Set<DownloadOrigin>] = ["s1": [.playlist("p1")], "o1": [.playlist("zz"), .song],
                                                      "o2": [.playlist("aa")]]
        let changes = keeping.opened(origins: origins, carrying: { (id: String) -> Set<String> in id == "p1" ? ["s1"] : [] })
        #expect(changes == [PlaylistKeeping.Change(write: nil, effects: [.take(["o2"], from: "aa")]),
                            PlaylistKeeping.Change(write: nil, effects: [.take(["o1"], from: "zz")]),
                            PlaylistKeeping.Change(write: nil, effects: [.ask([song("s2")], for: "p1")])])
    }

    @Test func applyPutsInPlaceOrLastAndMovesOnlyAnAnswersSerial() {
        var keeping = PlaylistKeeping(kept: [kept(["s1"]), kept(["s2"], id: "p2")])
        var read = kept(["s3"])
        read.readAt = t0 + minute
        keeping.apply(PlaylistKeeping.Change(write: .put(read), effects: []))
        #expect(keeping.kept.map(\.id) == ["p1", "p2"] && keeping.entry("p1") == read && keeping.serial("p1") == 0)
        keeping.apply(PlaylistKeeping.Change(write: .put(kept([], id: "p3")), effects: [], takesIn: "p3"))
        #expect(keeping.kept.map(\.id) == ["p1", "p2", "p3"] && keeping.serial("p3") == 1)
        keeping.apply(PlaylistKeeping.Change(write: .delete("p2"), effects: []))
        #expect(keeping.kept.map(\.id) == ["p1", "p3"])
        keeping.clear()
        #expect(keeping.kept.isEmpty && keeping.serial("p3") == 0)
    }

    // MARK: smart playlists (James: "No Download for them")

    @Test func aSmartPlaylistIsNeverDownloaded() throws {
        #expect(!PlaylistDownloads.downloadable(answer([], smart: true).playlist))
        #expect(PlaylistDownloads.downloadable(answer([]).playlist))
        #expect(PlaylistKeeping().download(answer(["s1"], smart: true), body: Data(), at: t0, carrying: []) == nil)
        #expect(PlaylistDownloads.choices(nil, smart: true).isEmpty)
        #expect(PlaylistDownloads.choices(nil) == [.download])
        #expect(PlaylistDownloadWords.heroLine(nil, smart: true) == PlaylistDownloadWords.smartOnline)
        #expect(PlaylistDownloadWords.heroLine(nil) == nil)
        // the page's: smart when the answer in hand says so, or the one kept here does
        let frozen = PlaylistDownloads.read(kept(["s1"]), answer: answer(["s1"], smart: true), body: Data(),
                                            carrying: ["s1"], at: t0)
        #expect(PlaylistDownloads.isSmart(answer([], smart: true), kept: nil))
        #expect(PlaylistDownloads.isSmart(nil, kept: frozen) && PlaylistDownloads.isSmart(answer([]), kept: frozen))
        #expect(!PlaylistDownloads.isSmart(answer([]), kept: kept(["s1"])) && !PlaylistDownloads.isSmart(nil, kept: nil))
        // deadwax's summary without the field (before main's 2.1.x): not smart; with it, read as sent
        let without = try JSONDecoder().decode(Playlist.self, from: Data(#"{"id":"p1","name":"x","editable":false}"#.utf8))
        #expect(!without.smart)
        let with = try JSONDecoder().decode(Playlist.self, from: Data(#"{"id":"p1","smart":true}"#.utf8))
        #expect(with.smart)
        let again = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(with))
        #expect(again == with, "kept and read back as smart")
    }

    @Test func aDownloadedPlaylistFoundSmartIsKeptAsItWas() throws {
        // s2 marked gone, s9 new, the playlist marked missing by a list: a read whose answer says smart changes none of
        // its songs, and finds it
        var entry = kept(["s1", "s2"], left: ["s2": t0 - 20 * minute])
        entry.missingSince = t0 - minute
        let read = PlaylistDownloads.read(entry, answer: answer(["s9"], changed: "c9", smart: true), body: Data("new".utf8),
                                          carrying: ["s1", "s2"], at: t0 + minute)
        #expect(read.answer?.songs.map(\.id) == ["s1", "s2"] && read.answer?.playlist.smart == true)
        #expect(read.answer?.playlist.songCount == 2 && read.left.isEmpty && read.readAt == t0 + minute)
        #expect(read.missingSince == nil, "found")
        #expect(try JSONDecoder().decode(PlaylistWithSongs.self, from: read.body) == read.answer, "the store keeps it smart")
        #expect(PlaylistDownloads.actions(read, carrying: ["s1", "s2"]).isEmpty, "nothing asked, nothing taken")
        #expect(PlaylistDownloads.actions(read, carrying: []).isEmpty, "not even its own songs asked again")
        #expect(PlaylistDownloads.dueReads([read], now: t0 + 60 * minute).isEmpty && PlaylistDownloads.nextLook([read]) == nil)
        // Remove Download still offered, its words its own
        #expect(PlaylistDownloads.choices(.downloaded(checking: false), smart: true) == [.remove])
        #expect(PlaylistDownloadWords.heroLine(.downloaded(checking: false), smart: true) == PlaylistDownloadWords.smartKept)
        #expect(PlaylistDownloadWords.heroLine(.downloaded(checking: false)) == PlaylistDownloadWords.playsOffline)
        // and its Remove takes its origin as any playlist's
        let keeping = PlaylistKeeping(kept: [read])
        #expect(try #require(keeping.remove("p1", carrying: ["s1", "s2"])).effects == [.take(["s1", "s2"], from: "p1")])
    }

    @Test func aListSayingSmartKeepsItAsItWasButLetsItGoOnceGone() {
        let smart = Playlist(id: "p1", name: "Late night", changed: "c9", owner: "james", mine: true, smart: true)
        var marked = kept(["s1"], left: ["s2": t0 - 20 * minute])
        marked.missingSince = t0 - minute
        let first = PlaylistDownloads.listed([marked], list: [smart], at: t0)
        #expect(first.kept.first?.missingSince == nil, "listed: found")
        #expect(first.toRead.isEmpty, "never read again: its changed moves on every reading")
        #expect(first.kept.first?.answer?.playlist.smart == true && first.kept.first?.answer?.songs.map(\.id) == ["s1"])
        #expect(first.kept.first?.left.isEmpty == true)
        // listed again, changed again: still not read
        var missing = first.kept[0]
        missing.missingSince = t0
        let again = PlaylistDownloads.listed([missing], list: [smart], at: t0 + minute)
        #expect(again.toRead.isEmpty && again.kept.first?.missingSince == nil)
        // kept as it was, it is written once: a later list moves nothing of it, so nothing is put
        let quiet = PlaylistKeeping(kept: first.kept).listed([smart], at: t0 + 5 * minute,
                                                             carrying: { (id: String) -> Set<String> in [] })
        #expect(quiet.changes.isEmpty && quiet.toRead.isEmpty)
        // gone from two lists ten minutes apart: let go, as any
        let other = Playlist(id: "p9", name: "x")
        let gone = PlaylistDownloads.listed(again.kept, list: [other], at: t0 + 2 * minute)
        let letGo = PlaylistDownloads.listed(gone.kept, list: [other], at: t0 + 12 * minute)
        #expect(letGo.letGo == ["p1"])
    }
}
