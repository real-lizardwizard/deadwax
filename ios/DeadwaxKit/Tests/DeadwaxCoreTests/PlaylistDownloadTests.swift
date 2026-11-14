import Foundation
import Testing
@testable import DeadwaxCore

// Phase 4, slice 3 (phase4-library.md 2.5, 6.3): a downloaded playlist's origin, what each Remove Download takes, the
// planner's playlist unit, and how a downloaded playlist is kept in step with the playlist - the list, a read, what it
// asks and takes, when it is looked at - and its words.

private let minute: Int64 = 60_000
private let t0: Int64 = 1_800_000_000_000
private let gb: Int64 = 1_000_000_000

private func song(_ id: String, album: String? = nil) -> Song {
    Song(id: id, title: "Song \(id)", album: "Album", albumId: album ?? "al-\(id)", artist: "Someone", duration: 200)
}

private func answer(_ ids: [String], id: String = "p1", name: String = "Late night", changed: String = "c1")
    -> PlaylistWithSongs {
    PlaylistWithSongs(playlist: Playlist(id: id, name: name, songCount: ids.count, changed: changed, owner: "james",
                                         mine: true, editable: true),
                      songs: ids.map { (id: String) -> Song in song(id) })
}

private func kept(_ ids: [String], id: String = "p1", name: String = "Late night", changed: String = "c1",
                  readAt: Int64 = t0, missingSince: Int64? = nil, left: [String: Int64] = [:]) -> KeptPlaylist {
    KeptPlaylist(id: id, answer: answer(ids, id: id, name: name, changed: changed), body: Data("{}".utf8), readAt: readAt,
                 missingSince: missingSince, left: left, askedAt: t0 - minute)
}

private func listed(_ id: String, changed: String = "c1") -> Playlist {
    Playlist(id: id, name: "Late night", changed: changed, owner: "james", mine: true, editable: true)
}

@Suite struct PlaylistDownloadTests {
    // MARK: the origin

    @Test func aPlaylistsOriginIsWrittenAsPhaseTwosReservedRawAndReadBackAsItself() {
        #expect(DownloadOrigin.playlist("p1").raw == "playlist:p1")
        #expect(DownloadOrigin(raw: "playlist:p1") == .playlist("p1"), "a store's row reads back as the same origin")
        #expect(DownloadOrigin.playlist("p1") == .other("playlist:p1"))
        #expect(DownloadOrigin.playlist("p1").playlistID == "p1")
        #expect(DownloadOrigin.other("playlist:").playlistID == nil && DownloadOrigin.album("p1").playlistID == nil)
        #expect(DownloadOrigin.library.playlistID == nil && DownloadOrigin.song.playlistID == nil)
        #expect(DownloadOrigin.playlists([.playlist("b"), .song, .playlist("a"), .library]) == ["a", "b"])
        #expect(!DownloadOrigin.onlyLibrary([.library, .playlist("p")]), "a playlist's song isn't the library's alone")
    }

    @Test func whatThePhoneKeepsInStepItselfIsTheLibrarysAndThePlaylists() {
        #expect(DownloadOrigin.keptInStep([.library]))
        #expect(DownloadOrigin.keptInStep([.playlist("p")]))
        #expect(DownloadOrigin.keptInStep([.library, .playlist("p"), .playlist("q")]))
        #expect(!DownloadOrigin.keptInStep([.song, .playlist("p")]))
        #expect(!DownloadOrigin.keptInStep([.album("a"), .library]))
        #expect(!DownloadOrigin.keptInStep([]))
        #expect(DownloadOrigin.onlyPlaylists([.playlist("p"), .playlist("q")]))
        #expect(!DownloadOrigin.onlyPlaylists([.playlist("p"), .library]))
        #expect(!DownloadOrigin.onlyPlaylists([]))
    }

    // MARK: removing

    @Test func theLibraryNeverTakesAPlaylistsOriginSoNeverRemovesItsSongs() {
        #expect(!LibraryDownloads.gives.contains { (origin: DownloadOrigin) -> Bool in origin.playlistID != nil })
        let origins: [String: Set<DownloadOrigin>] = ["both": [.library, .playlist("p")], "library": [.library],
                                                      "playlist": [.playlist("p")]]
        let after = DownloadRules.afterRemoving(LibraryDownloads.gives, from: origins)
        #expect(after.deleted == ["library"])
        #expect(after.kept == ["both": [.playlist("p")], "playlist": [.playlist("p")]])
        // the switch off takes the library's from every song carrying it: the playlist's songs stay
        let songs = [StoreSong(id: "both", albumID: "a", origins: [.library, .playlist("p")]),
                     StoreSong(id: "playlist", albumID: "a", origins: [.playlist("p")])]
        let off = LibraryDownloads.switchedOff(songs)
        #expect(!off.take.contains("playlist"))
        #expect(DownloadRules.afterRemoving(LibraryDownloads.gives, from: ["both": [.library, .playlist("p")]]).deleted.isEmpty)
        // and a playlist's song is a hand download to the library's rules
        #expect(songs.allSatisfy { (song: StoreSong) -> Bool in song.byHand })
    }

    @Test func eachRemoveDownloadTakesItsOwnAndASongKeptAnotherWayStays() {
        #expect(DownloadRemoval.song(albumID: "a") == [.song, .album("a")])
        #expect(DownloadRemoval.album("a") == [.song, .album("a"), .library])
        #expect(DownloadRemoval.playlist("p") == [.playlist("p")])
        // a song's own
        #expect(!DownloadRemoval.stays([.song], removing: DownloadRemoval.song(albumID: "a")))
        #expect(!DownloadRemoval.stays(nil, removing: DownloadRemoval.song(albumID: "a")), "none kept reads as asked alone")
        #expect(!DownloadRemoval.stays([], removing: DownloadRemoval.song(albumID: "a")))
        #expect(DownloadRemoval.stays([.song, .playlist("p")], removing: DownloadRemoval.song(albumID: "a")))
        #expect(DownloadRemoval.stays([.song, .library], removing: DownloadRemoval.song(albumID: "a")))
        // an album's: never a playlist's song
        #expect(!DownloadRemoval.stays([.album("a"), .library], removing: DownloadRemoval.album("a")))
        #expect(DownloadRemoval.stays([.album("a"), .playlist("p")], removing: DownloadRemoval.album("a")))
        #expect(DownloadRemoval.stays([.library, .playlist("p")], removing: DownloadRemoval.album("a")))
        // a playlist's: its own origin alone
        #expect(!DownloadRemoval.stays([.playlist("p")], removing: DownloadRemoval.playlist("p")))
        #expect(DownloadRemoval.stays([.playlist("p"), .playlist("q")], removing: DownloadRemoval.playlist("p")))
        #expect(DownloadRemoval.stays([.playlist("p"), .song], removing: DownloadRemoval.playlist("p")))
        #expect(DownloadRemoval.stays([.playlist("p"), .album("a")], removing: DownloadRemoval.playlist("p")))
        #expect(DownloadRemoval.stays([.playlist("p"), .library], removing: DownloadRemoval.playlist("p")))
        // a song with no origin kept reads as asked alone: a playlist's Remove leaves it where it is
        #expect(DownloadRemoval.stays(nil, removing: DownloadRemoval.playlist("p")))
        #expect(DownloadRemoval.stays([], removing: DownloadRemoval.playlist("p")))
        let after = DownloadRules.afterRemoving(DownloadRemoval.playlist("p"),
                                                from: ["a": [.playlist("p")], "b": [.playlist("p"), .playlist("q")],
                                                       "c": [.playlist("p"), .song], "d": [.playlist("q")]])
        #expect(after.deleted == ["a"])
        #expect(after.kept == ["b": [.playlist("q")], "c": [.song], "d": [.playlist("q")]])
    }

    @Test func aSongThatWouldStayIsOfferedNoRemoveDownloadOfItsOwn() {
        #expect(DownloadChoice.forSong(.done(.matched), staying: true).isEmpty)
        #expect(DownloadChoice.forSong(.done(.matched), staying: false) == [.remove])
        #expect(DownloadChoice.forSong(.failed(.wrongSize), staying: true) == [.downloadAgain])
        #expect(DownloadChoice.forSong(.none, staying: true) == [.download])
        // the library's own forms are the same rule
        #expect(DownloadChoice.forSong(.done(.matched), keptByLibrary: true) == DownloadChoice.forSong(.done(.matched), staying: true))
        // several: Remove Download only when one asked for or here would go
        #expect(DownloadChoice.forSongs([.done(.matched), .done(.matched)], staying: [true, true]).isEmpty)
        #expect(DownloadChoice.forSongs([.done(.matched), .none], staying: [true, false]) == [.download])
        #expect(DownloadChoice.forSongs([.done(.matched), .done(.matched)], staying: [true, false]) == [.remove])
    }

    // MARK: the planner

    @Test func aDownloadedPlaylistsSongsArePlannedInItsUnit() {
        func unit(_ origins: Set<DownloadOrigin>) -> String {
            DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: origins, expected: 1).unit
        }
        #expect(unit([.playlist("p")]) == "playlist:p")
        #expect(unit([.song, .playlist("p")]) == "playlist:p", "a song asked for alone and in a downloaded playlist goes with it")
        #expect(unit([.library, .playlist("p")]) == "playlist:p", "a hand download first, never the library's")
        #expect(unit([.playlist("q"), .playlist("p")]) == "playlist:p")
        #expect(unit([.album("a"), .playlist("p")]) == "album:a", "an album asked for keeps its own unit")
        #expect(unit([.library]) == "library:al")
        #expect(unit([.song]) == "song:s")
        // (slice 3's review) a playlist's song already started goes on as itself
        for started in [DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.playlist("p")], expected: 2, out: true),
                        DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.playlist("p")], expected: 2, received: 1),
                        DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.playlist("p")], expected: 2,
                                           resumable: true)] {
            #expect(started.unit == "song:s")
        }
        #expect(DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.album("a"), .playlist("p")], expected: 2,
                                   out: true).unit == "album:a", "an album's unit as it was")
    }

    /// Slice 3's review (HIGH): a song of the playlist already fetching - asked for by hand, or the library's - never
    /// lets the rest of the playlist past the limit or the 2 GB the phone keeps.
    @Test func aStartedSongNeverLetsItsPlaylistPastTheLimitOrTheReserve() {
        let rest = (1...3).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "p-\(n)", albumID: "al-\(n)", wantedAt: 2, origins: [.playlist("p")], expected: 3 * gb)
        }
        let origins: [Set<DownloadOrigin>] = [[.song, .playlist("p")], [.library, .playlist("p")]]
        for its in origins {
            let fetching = DownloadPlan.Asked(id: "f", albumID: "al-f", wantedAt: 1, origins: its, expected: 2 * gb,
                                              received: gb, out: true)
            // 12 GB here, f's 1 to come and the rest's 9: over 20 - f goes on, the rest waits for room, whole
            let facts = DownloadPlan.Facts(bytesHere: 12 * gb, limit: StorageLimit.gb20.bytes, freeSpace: 100 * gb)
            let room = DownloadPlan.plan([fetching] + rest, facts)
            #expect(room["f"] == DownloadPlan.Decision(wait: .queued, task: true))
            #expect(rest.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in room[asked.id] == DownloadPlan.Decision(wait: .room, task: false) })
            // the hand downloads' still to come are f's alone: the library gives way for nothing more
            #expect(DownloadPlan.handToCome([fetching] + rest, facts) == gb)
            // the reserve: 11 GB free, less f's 1 and the rest's 9, leaves 1
            let full = DownloadPlan.plan([fetching] + rest, DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 11 * gb))
            #expect(full["f"]?.task == true)
            #expect(rest.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in full[asked.id] == DownloadPlan.Decision(wait: .phoneFull, task: false) })
        }
        // a song added to a playlist already downloading is checked with the rest of what hasn't started
        let going = DownloadPlan.Asked(id: "p-0", albumID: "al-0", wantedAt: 1, origins: [.playlist("p")], expected: 3 * gb,
                                       received: gb, out: true)
        let added = DownloadPlan.Asked(id: "new", albumID: "al-n", wantedAt: 9, origins: [.playlist("p")], expected: 9 * gb)
        let plan = DownloadPlan.plan([going, added], DownloadPlan.Facts(bytesHere: 10 * gb, limit: StorageLimit.gb20.bytes,
                                                                        freeSpace: 100 * gb))
        #expect(plan["p-0"]?.task == true && plan["new"] == DownloadPlan.Decision(wait: .room, task: false))
    }

    /// Slice 3's review (HIGH): a song two downloaded playlists share, mid-fetch, goes on as itself - the playlist that
    /// sorts first no longer takes it, so the older playlist doesn't stop half-way while the newer goes past the limit.
    @Test func aSongTwoPlaylistsShareGoesOnAloneAndEachPlaylistIsJudgedOnItsOwn() {
        let shared = DownloadPlan.Asked(id: "both", albumID: "al", wantedAt: 1, origins: [.playlist("p0"), .playlist("p1")],
                                        expected: 2 * gb, received: gb, out: true)
        let older = (1...2).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "p1-\(n)", albumID: "a\(n)", wantedAt: 1, origins: [.playlist("p1")], expected: gb)
        }
        let newer = (1...2).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "p0-\(n)", albumID: "b\(n)", wantedAt: 5, origins: [.playlist("p0")], expected: 4 * gb)
        }
        #expect(shared.unit == "song:both")
        // 12 here: the shared song's 1 and p1's 2 fit under 20; p0's 8 more don't
        let plan = DownloadPlan.plan([shared] + older + newer, DownloadPlan.Facts(bytesHere: 12 * gb,
                                                                                limit: StorageLimit.gb20.bytes,
                                                                                freeSpace: 100 * gb))
        #expect(plan["both"]?.task == true)
        #expect(older.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in plan[asked.id]?.task == true }, "not half-way")
        #expect(newer.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in plan[asked.id] == DownloadPlan.Decision(wait: .room, task: false) })
    }

    @Test func aDownloadedPlaylistIsPlannedWholeUnderTheLimitAndTheReserve() {
        let songs = (1...3).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "p-\(n)", albumID: "al-\(n)", wantedAt: 1, origins: [.playlist("p")], expected: 3 * gb)
        }
        let small = DownloadPlan.Asked(id: "loose", albumID: "x", wantedAt: 2, origins: [.song], expected: gb / 2)
        // 12 GB here, 9 GB to come: over the 20 GB limit - the whole playlist waits, never part of it; a small song goes
        let room = DownloadPlan.plan(songs + [small], DownloadPlan.Facts(bytesHere: 12 * gb, limit: StorageLimit.gb20.bytes,
                                                                         freeSpace: 100 * gb))
        #expect(songs.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in room[asked.id] == DownloadPlan.Decision(wait: .room, task: false) })
        #expect(room["loose"] == DownloadPlan.Decision(wait: .queued, task: true))
        // within the limit, every song of it goes at once
        let fits = DownloadPlan.plan(songs, DownloadPlan.Facts(bytesHere: 11 * gb, limit: StorageLimit.gb20.bytes,
                                                               freeSpace: 100 * gb))
        #expect(songs.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in fits[asked.id]?.task == true })
        // the 2 GB the phone keeps: 10 GB free less 9 leaves 1 - it waits whole for space
        let full = DownloadPlan.plan(songs, DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 10 * gb))
        #expect(songs.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in full[asked.id] == DownloadPlan.Decision(wait: .phoneFull, task: false) })
        let roomy = DownloadPlan.plan(songs, DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 11 * gb))
        #expect(songs.allSatisfy { (asked: DownloadPlan.Asked) -> Bool in roomy[asked.id]?.task == true }, "11 - 9 leaves 2 GB")
    }

    // MARK: the list

    @Test func aPlaylistWhoseChangedMovedIsReadAgain() {
        let out = PlaylistDownloads.listed([kept(["s1"], changed: "c1"), kept(["s2"], id: "p2", changed: "c1")],
                                           list: [listed("p1", changed: "c2"), listed("p2", changed: "c1")], at: t0)
        #expect(out.toRead == ["p1"])
        #expect(out.letGo.isEmpty && out.kept.map(\.id) == ["p1", "p2"])
        // one whose answer couldn't be read is read whatever its changed
        var unreadable = kept(["s1"])
        unreadable.answer = nil
        #expect(PlaylistDownloads.listed([unreadable], list: [listed("p1")], at: t0).toRead == ["p1"])
    }

    @Test func aPlaylistMissingFromTwoListsTenMinutesApartIsLetGo() {
        let other = [listed("other")]
        let first = PlaylistDownloads.listed([kept(["s1"])], list: other, at: t0)
        #expect(first.letGo.isEmpty && first.kept.first?.missingSince == t0, "one list never lets it go")
        let soon = PlaylistDownloads.listed(first.kept, list: other, at: t0 + 10 * minute - 1)
        #expect(soon.letGo.isEmpty && soon.kept.first?.missingSince == t0, "the first list without it dates the mark")
        let agreed = PlaylistDownloads.listed(soon.kept, list: other, at: t0 + 10 * minute)
        #expect(agreed.letGo == ["p1"] && agreed.kept.isEmpty)
        // listed again before then: no longer missing
        let back = PlaylistDownloads.listed(first.kept, list: [listed("p1")], at: t0 + 5 * minute)
        #expect(back.kept.first?.missingSince == nil && back.letGo.isEmpty)
        // one downloaded after the list was asked for: the list can't speak for it
        var late = kept(["s1"], missingSince: t0 - 20 * minute)
        late.askedAt = t0 + 1
        let early = PlaylistDownloads.listed([late], list: other, at: t0)
        #expect(early.kept == [late] && early.letGo.isEmpty && early.toRead.isEmpty)
    }

    @Test func anEmptyListMarksNothingAndEveryPlaylistIsReadInstead() {
        let out = PlaylistDownloads.listed([kept(["s1"]), kept(["s2"], id: "p2", missingSince: t0 - 20 * minute)],
                                           list: [], at: t0)
        #expect(out.letGo.isEmpty, "an empty list is never believed on its own")
        #expect(out.toRead == ["p1", "p2"])
        #expect(out.kept.map(\.missingSince) == [nil, t0 - 20 * minute], "no mark set, none confirmed")
    }

    @Test func aReadAnsweredNotFoundIsAListWithoutIt() {
        let first = PlaylistDownloads.missing(kept(["s1"]), at: t0)
        #expect(!first.gone && first.entry.missingSince == t0)
        #expect(!PlaylistDownloads.missing(first.entry, at: t0 + 9 * minute).gone)
        #expect(PlaylistDownloads.missing(first.entry, at: t0 + 10 * minute).gone)
        // a read that finds it again ends the mark
        let found = PlaylistDownloads.read(first.entry, answer: answer(["s1"]), body: Data(), carrying: ["s1"],
                                           at: t0 + minute)
        #expect(found.missingSince == nil)
    }

    // MARK: a read, and what it asks and takes

    @Test func aSongThePlaylistGainedIsAskedForOnceInItsOrder() {
        let read = PlaylistDownloads.read(kept(["s1"]), answer: answer(["s3", "s1", "s2", "s3"]), body: Data("b".utf8),
                                          carrying: ["s1"], at: t0 + minute)
        #expect(read.answer == answer(["s3", "s1", "s2", "s3"]) && read.body == Data("b".utf8) && read.readAt == t0 + minute)
        let actions = PlaylistDownloads.actions(read, carrying: ["s1"])
        #expect(actions.ask.map(\.id) == ["s3", "s2"], "a song listed twice is asked for once")
        #expect(actions.take.isEmpty)
        // a playlist just downloaded asks for all of it
        let started = PlaylistDownloads.started(answer(["a", "b"]), body: Data(), at: t0)
        #expect(PlaylistDownloads.actions(started, carrying: []).ask.map(\.id) == ["a", "b"])
        #expect(started.askedAt == t0 && started.left.isEmpty && started.missingSince == nil)
    }

    @Test func aSongItLostGoesOnlyOnceTwoReadsTenMinutesApartAgree() {
        let carrying: Set<String> = ["s1", "s2"]
        let first = PlaylistDownloads.read(kept(["s1", "s2"]), answer: answer(["s1"]), body: Data(), carrying: carrying,
                                           at: t0)
        #expect(first.left == ["s2": t0])
        #expect(first.answer == answer(["s1"]), "the page draws the playlist as it is")
        #expect(PlaylistDownloads.actions(first, carrying: carrying).take.isEmpty, "one read never takes anything")
        let soon = PlaylistDownloads.read(first, answer: answer(["s1"]), body: Data(), carrying: carrying,
                                          at: t0 + 10 * minute - 1)
        #expect(soon.left == ["s2": t0] && PlaylistDownloads.actions(soon, carrying: carrying).take.isEmpty)
        #expect(soon.secondReadAt == t0 + 10 * minute)
        let agreed = PlaylistDownloads.read(soon, answer: answer(["s1"]), body: Data(), carrying: carrying,
                                            at: t0 + 10 * minute)
        #expect(PlaylistDownloads.actions(agreed, carrying: carrying).take == ["s2"])
        #expect(agreed.secondReadAt == nil)
        // back in the playlist before the second read: no longer marked, nothing taken
        let back = PlaylistDownloads.read(first, answer: answer(["s1", "s2"]), body: Data(), carrying: carrying,
                                          at: t0 + 11 * minute)
        #expect(back.left.isEmpty && PlaylistDownloads.actions(back, carrying: carrying).isEmpty)
        // once taken, the song no longer carries the origin: nothing more to do
        #expect(PlaylistDownloads.actions(agreed, carrying: ["s1"]).isEmpty)
        // two songs found gone at two reads: the second read is due by the first of them
        let twice = PlaylistDownloads.read(first, answer: answer([]), body: Data(), carrying: ["s1", "s2"],
                                           at: t0 + 4 * minute)
        #expect(twice.left == ["s1": t0 + 4 * minute, "s2": t0])
        #expect(twice.secondReadAt == t0 + 10 * minute)
    }

    @Test func aSongTheKeptAnswerStillListsIsNeverTaken() {
        // a row whose marks say a song it lists has gone (a store written by an older build, a mark left behind): kept
        let odd = kept(["s1", "s2"], readAt: t0, left: ["s2": t0 - 20 * minute, "s3": t0 - 20 * minute])
        #expect(odd.leftAgreed == ["s2", "s3"])
        #expect(PlaylistDownloads.actions(odd, carrying: ["s1", "s2", "s3"]).take == ["s3"])
    }

    @Test func anEditHereTakesWhatItTookOutAtOnce() {
        let carrying: Set<String> = ["s1", "s2", "s3"]
        let edited = PlaylistDownloads.read(kept(["s1", "s2", "s3"]), answer: answer(["s1"]), body: Data(),
                                            carrying: carrying, at: t0, edited: ["s2", "s3"])
        #expect(PlaylistDownloads.actions(edited, carrying: carrying).take == ["s2", "s3"])
        #expect(edited.secondReadAt == nil, "nothing waits for a second read")
        // a read elsewhere marks first
        let elsewhere = PlaylistDownloads.read(kept(["s1", "s2", "s3"]), answer: answer(["s1"]), body: Data(),
                                               carrying: carrying, at: t0)
        #expect(PlaylistDownloads.actions(elsewhere, carrying: carrying).take.isEmpty)
    }

    /// Slice 3's review (MEDIUM): an Edit takes at once only the songs it took out - never one Navidrome is hiding, which
    /// Done's answer doesn't list either - and a read never marks songs Navidrome's `hidden` may account for.
    @Test func anEditTakesOnlyWhatItTookOutAndASongNavidromeIsHidingStays() {
        func hiding(_ ids: [String], _ hidden: Int) -> PlaylistWithSongs {
            let listed = answer(ids)
            return PlaylistWithSongs(playlist: listed.playlist, songs: listed.songs, hidden: hidden)
        }
        // a Done that changed only the name, s2's file being moved: its answer lacks s2, and nothing is taken
        let renamed = PlaylistDownloads.read(kept(["s1", "s2"]), answer: hiding(["s1"], 1), body: Data(),
                                             carrying: ["s1", "s2"], at: t0, edited: [])
        #expect(renamed.left.isEmpty && PlaylistDownloads.actions(renamed, carrying: ["s1", "s2"]).isEmpty)
        // an Edit that took s3 out with s2 hidden: s3 at once, s2 kept and unmarked
        let edited = PlaylistDownloads.read(kept(["s1", "s2", "s3"]), answer: hiding(["s1"], 1), body: Data(),
                                            carrying: ["s1", "s2", "s3"], at: t0, edited: ["s3"])
        #expect(PlaylistDownloads.actions(edited, carrying: ["s1", "s2", "s3"]).take == ["s3"])
        #expect(edited.left["s2"] == nil)
        // ordinary reads: two answers ten minutes apart listing nothing with both hidden take nothing - the kept answer
        // stays, drawn, and a mark made before the hiding is dropped
        let carrying: Set<String> = ["s1", "s2"]
        let first = PlaylistDownloads.read(kept(["s1", "s2"], left: ["s2": t0 - 20 * minute]), answer: hiding([], 2),
                                           body: Data("e".utf8), carrying: carrying, at: t0)
        let second = PlaylistDownloads.read(first, answer: hiding([], 2), body: Data("e".utf8), carrying: carrying,
                                            at: t0 + 10 * minute)
        #expect(first.left.isEmpty && second.left.isEmpty)
        #expect(PlaylistDownloads.actions(second, carrying: carrying).isEmpty)
        #expect(second.answer == answer(["s1", "s2"]), "the answer kept stays while Navidrome hides them")
        // hidden at least the songs lacking: none marked; fewer: all marked, as Navidrome can't say which
        let some = PlaylistDownloads.read(kept(["s1", "s2", "s3"]), answer: hiding(["s1"], 2), body: Data(),
                                          carrying: ["s1", "s2", "s3"], at: t0)
        #expect(some.left.isEmpty)
        let more = PlaylistDownloads.read(kept(["s1", "s2", "s3"]), answer: hiding(["s1"], 1), body: Data(),
                                          carrying: ["s1", "s2", "s3"], at: t0)
        #expect(more.left == ["s2": t0, "s3": t0])
        // a song the Edit took out isn't one Navidrome's count accounts for: s3 taken, s2 (hidden 1) kept
        let both = PlaylistDownloads.read(kept(["s1", "s2", "s3"]), answer: hiding(["s1"], 1), body: Data(),
                                          carrying: ["s1", "s2", "s3"], at: t0, edited: ["s3"])
        #expect(both.left.keys.sorted() == ["s3"])
        // an Edit's own removals: in the songs it began with and nowhere now - one listed twice and taken out once stays
        let body = PlaylistEditBody(base: ["s1", "s2", "s2", "s3"], songIds: ["s2", "s1"])
        #expect(body.removed == ["s3"])
    }

    /// Slice 3's review (test gaps): a mark dated after the read (the phone's clock moved back) is dated by the read, so
    /// a song isn't kept marked for ever; and a playlist downloaded at the very moment the list was asked is the list's.
    @Test func aMarkFromTheFutureIsTheReadsAndAListAtTheMomentOfADownloadSpeaksForIt() {
        let ahead = kept(["s1", "s2"], left: ["s2": t0 + 30 * minute])
        let read = PlaylistDownloads.read(ahead, answer: answer(["s1"]), body: Data(), carrying: ["s1", "s2"], at: t0)
        #expect(read.left == ["s2": t0])
        var now = kept(["s1"])
        now.askedAt = t0
        let other = Playlist(id: "p9", name: "x")
        #expect(PlaylistDownloads.listed([now], list: [other], at: t0).kept.first?.missingSince == t0)
        now.askedAt = t0 + 1
        #expect(PlaylistDownloads.listed([now], list: [other], at: t0).kept.first?.missingSince == nil)
    }

    /// Slice 3's review (LOW): a song carrying a playlist's origin is drawn with the playlist only while its kept answer
    /// lists it - one marked gone, or hidden, still coming, is drawn under its album.
    @Test func aSongIsDrawnWithItsPlaylistOnlyWhileItsAnswerListsIt() {
        let listing = PlaylistDownloads.listing([kept(["s1"]), kept(["s5"], id: "p2")])
        #expect(listing == ["p1": ["s1"], "p2": ["s5"]])
        #expect(PlaylistDownloads.drawnWithPlaylists("s1", origins: [.playlist("p1")], listing: listing))
        #expect(!PlaylistDownloads.drawnWithPlaylists("s2", origins: [.playlist("p1")], listing: listing))
        #expect(PlaylistDownloads.drawnWithPlaylists("s5", origins: [.playlist("p1"), .playlist("p2")], listing: listing))
        #expect(!PlaylistDownloads.drawnWithPlaylists("s5", origins: [.playlist("p1")], listing: listing), "another's list")
        #expect(!PlaylistDownloads.drawnWithPlaylists("s1", origins: [.song], listing: listing))
        #expect(!PlaylistDownloads.drawnWithPlaylists("s1", origins: [.playlist("p3")], listing: listing), "not kept")

        // Downloading's album rows: a song asked another way, or kept in step with no other row drawing it
        #expect(PlaylistDownloads.inDownloadingAlbumRow("s1", origins: [.song, .playlist("p1")], listing: listing))
        #expect(!PlaylistDownloads.inDownloadingAlbumRow("s1", origins: [.playlist("p1")], listing: listing))
        #expect(!PlaylistDownloads.inDownloadingAlbumRow("s2", origins: [.library, .playlist("p1")], listing: listing),
                "your library's row draws it")
        #expect(PlaylistDownloads.inDownloadingAlbumRow("s2", origins: [.playlist("p1")], listing: listing),
                "its playlist no longer lists it: its album's row")
        // Downloaded's: a song kept any way but playlists alone, or one no playlist's row draws
        #expect(PlaylistDownloads.inDownloadedAlbumRow("s1", origins: [.library, .playlist("p1")], listing: listing))
        #expect(!PlaylistDownloads.inDownloadedAlbumRow("s1", origins: [.playlist("p1")], listing: listing))
        #expect(PlaylistDownloads.inDownloadedAlbumRow("s2", origins: [.playlist("p1")], listing: listing))
        #expect(PlaylistDownloads.inDownloadedAlbumRow("s9", origins: [.song], listing: listing))
    }

    @Test func anEmptyAnswerIsNeverTakenInOnItsOwn() {
        let carrying: Set<String> = ["s1", "s2"]
        let first = PlaylistDownloads.read(kept(["s1", "s2"]), answer: answer([]), body: Data("empty".utf8),
                                           carrying: carrying, at: t0)
        #expect(first.answer == answer(["s1", "s2"]) && first.body == Data("{}".utf8), "the kept answer stays, drawn offline")
        #expect(first.left == ["s1": t0, "s2": t0] && first.readAt == t0)
        #expect(PlaylistDownloads.actions(first, carrying: carrying).isEmpty)
        // a second empty read ten minutes on agrees: taken in, and the songs go
        let agreed = PlaylistDownloads.read(first, answer: answer([]), body: Data("empty".utf8), carrying: carrying,
                                            at: t0 + 10 * minute)
        #expect(agreed.answer == answer([]) && agreed.body == Data("empty".utf8))
        #expect(PlaylistDownloads.actions(agreed, carrying: carrying).take == ["s1", "s2"])
        // emptied by this phone's own Edit: at once
        let here = PlaylistDownloads.read(kept(["s1", "s2"]), answer: answer([]), body: Data(), carrying: carrying,
                                          at: t0, edited: ["s1", "s2"])
        #expect(here.answer == answer([]) && PlaylistDownloads.actions(here, carrying: carrying).take == ["s1", "s2"])
        // a playlist empty already stays empty
        let none = PlaylistDownloads.read(kept([]), answer: answer([]), body: Data("e".utf8), carrying: [], at: t0)
        #expect(none.answer == answer([]) && none.body == Data("e".utf8))
        // a kept answer empty already, or one that couldn't be read, is replaced by the empty one at once - the hold keeps
        // listed songs drawn, and it has none - while a song still carried waits for a second read to go
        var unreadable = kept(["s1"])
        unreadable.answer = nil
        for before in [kept([]), unreadable] {
            let empty = PlaylistDownloads.read(before, answer: answer([]), body: Data("e".utf8), carrying: ["s1"], at: t0)
            #expect(empty.answer == answer([]) && empty.body == Data("e".utf8) && empty.left == ["s1": t0])
            #expect(PlaylistDownloads.actions(empty, carrying: ["s1"]).isEmpty)
        }
    }

    @Test func onlyAReadTakesAnythingAndAnUnreadableAnswerNothing() {
        // a song carrying the origin the answer hasn't, with no read's mark: kept
        #expect(PlaylistDownloads.actions(kept(["s1"]), carrying: ["s1", "s9"]).take.isEmpty)
        var unreadable = kept(["s1"], left: ["s9": t0 - 20 * minute])
        unreadable.answer = nil
        #expect(PlaylistDownloads.actions(unreadable, carrying: ["s9"]).isEmpty)
        #expect(PlaylistDownloads.dueReads([unreadable], now: t0) == ["p1"])
    }

    @Test func theOriginsOfAPlaylistNoLongerKeptAreOrphans() {
        let origins: [String: Set<DownloadOrigin>] = ["a": [.playlist("gone"), .playlist("p1")], "b": [.playlist("gone")],
                                                      "c": [.song], "d": [.playlist("p1")]]
        #expect(PlaylistDownloads.orphans(origins, kept: ["p1"]) == ["gone": ["a", "b"]])
        #expect(PlaylistDownloads.orphans(origins, kept: ["p1", "gone"]).isEmpty)
    }

    // MARK: when

    @Test func secondReadsAndMissingMarksAreLookedAtWhenDue() {
        let marked = kept(["s1"], readAt: t0, left: ["s2": t0])
        let missing = kept(["s3"], id: "p2", missingSince: t0 + minute)
        #expect(PlaylistDownloads.dueReads([marked, missing], now: t0 + 10 * minute - 1).isEmpty)
        #expect(PlaylistDownloads.dueReads([marked, missing], now: t0 + 10 * minute) == ["p1"])
        #expect(PlaylistDownloads.nextLook([marked, missing]) == t0 + 10 * minute)
        #expect(PlaylistDownloads.nextLook([missing]) == t0 + 11 * minute)
        #expect(PlaylistDownloads.nextLook([kept(["s1"])]) == nil)
        // the follower's cadence, and the timer's minute when something is due
        #expect(PlaylistDownloads.due(.opened, lastBegan: t0, now: t0, kept: []))
        #expect(!PlaylistDownloads.due(.front, lastBegan: t0, now: t0 + minute - 1, kept: []))
        #expect(PlaylistDownloads.due(.front, lastBegan: t0, now: t0 + minute, kept: []))
        #expect(!PlaylistDownloads.due(.timer, lastBegan: t0, now: t0 + 9 * minute, kept: [marked]))
        #expect(PlaylistDownloads.due(.timer, lastBegan: t0, now: t0 + 10 * minute, kept: [marked]))
        #expect(PlaylistDownloads.due(.timer, lastBegan: t0, now: t0 + 15 * minute, kept: []))
        #expect(!PlaylistDownloads.due(.back, lastBegan: t0, now: t0 + 30_000, kept: [marked]), "the timer's alone")
    }

    // MARK: what the screens say

    @Test func aSongsMenuNamesTheFirstPlaylistKeepingItByName() {
        let all = [kept(["s1"], id: "p1", name: "Zebra"), kept(["s1"], id: "p2", name: "apple"),
                   kept(["s1"], id: "p3", name: "Mango")]
        #expect(PlaylistDownloads.keeping([.playlist("p1"), .playlist("p2"), .song], kept: all)?.id == "p2")
        #expect(PlaylistDownloads.keeping([.playlist("p1")], kept: all)?.name == "Zebra")
        #expect(PlaylistDownloads.keeping([.song, .library], kept: all) == nil)
        #expect(PlaylistDownloads.keeping(nil, kept: all) == nil)
        #expect(PlaylistDownloads.keeping([.playlist("gone")], kept: all) == nil)
        // the list's order: by name, folded; one whose answer can't be read left out
        var unread = kept(["s1"], id: "p4", name: "Aardvark")
        unread.answer = nil
        #expect(PlaylistDownloads.shelf(all + [unread]).map(\.id) == ["p2", "p3", "p1"])
        #expect(PlaylistDownloadWords.downloadedWith("Late night") == "Downloaded with Late night")
    }

    @Test func theControlsStateAndItsItems() {
        #expect(PlaylistDownloads.state(downloaded: false, songs: [AlbumSongFacts(state: .done(.matched))]) == nil)
        #expect(PlaylistDownloads.choices(nil) == [.download], "not downloaded: the arrow, whatever is here")
        #expect(PlaylistDownloads.state(downloaded: true, songs: []) == .downloaded(checking: false))
        #expect(PlaylistDownloads.state(downloaded: true, songs: [AlbumSongFacts(state: .done(.matched))])
                == .downloaded(checking: false))
        // a song not asked for yet is on its way, never "partial"
        #expect(PlaylistDownloads.state(downloaded: true, songs: [AlbumSongFacts(state: .done(.matched)), AlbumSongFacts(state: .none)])
                == .waiting(.queued, here: 1, of: 2))
        let failed = PlaylistDownloads.state(downloaded: true, songs: [AlbumSongFacts(state: .failed(.wrongSize)),
                                                                       AlbumSongFacts(state: .done(.matched))])
        #expect(failed == .failed(count: 1, first: .wrongSize))
        #expect(PlaylistDownloads.choices(failed) == [.downloadAgain, .remove])
        #expect(PlaylistDownloads.choices(.downloaded(checking: false)) == [.remove])
        #expect(PlaylistDownloads.choices(.waiting(.wifi, here: 0, of: 3)) == [.remove])
        // the hero's line: the album's while its songs come, its own once all are here
        #expect(PlaylistDownloadWords.heroLine(.downloaded(checking: false)) == PlaylistDownloadWords.playsOffline)
        #expect(PlaylistDownloadWords.heroLine(.downloaded(checking: true)) == PlaylistDownloadWords.playsOffline)
        let failedLine = failed.flatMap { (state: AlbumDownload) -> String? in PlaylistDownloadWords.heroLine(state) }
        #expect(failedLine == "1 song didn't download" && failedLine == DownloadWords.didntDownload(1))
        #expect(PlaylistDownloadWords.heroLine(.waiting(.wifi, here: 0, of: 3)) == DownloadWords.wait(.wifi))
    }

    @Test func downloadingsRowCountsTheSongsToCome() {
        let entry = kept(["a", "b", "b", "c", "d"])
        #expect(entry.songIDs == ["a", "b", "c", "d"])
        let states: [SongDownload] = [.done(.matched), .fetching(0.5), .failed(.unsaved), .none]
        let progress = PlaylistDownloads.progress(entry, states: states)
        #expect(progress == PlaylistDownloads.Progress(toGo: 2, of: 4))
        #expect(progress?.fraction == 0.5)
        #expect(PlaylistDownloads.progress(entry, states: [.done(.matched), .done(.matched), .failed(.unsaved), .done(.bySize)]) == nil)
        let row = PlaylistDownloads.Progress(toGo: 3, of: 12)
        #expect(PlaylistDownloadWords.downloadingRow(row, wait: nil) == "3 of 12 songs to go")
        #expect(PlaylistDownloadWords.downloadingRow(row, wait: .queued) == "3 of 12 songs to go")
        #expect(PlaylistDownloadWords.downloadingRow(row, wait: .room) == DownloadWords.wait(.room))
        #expect(PlaylistDownloadWords.downloadingSpoken("Late night", row, wait: nil) == "Late night, 3 of 12 songs to go, 75 percent")
        #expect(PlaylistDownloadWords.downloadingRow(PlaylistDownloads.Progress(toGo: 1_200, of: 2_000), wait: nil)
                == "1,200 of 2,000 songs to go")
        #expect(PlaylistDownloadWords.downloadingRow(PlaylistDownloads.Progress(toGo: 1, of: 1), wait: nil)
                == "1 of 1 song to go")
    }

    @Test func theWordsAreTheSpecsAndNoneSaysAWordAListenerNeverReads() {
        #expect(PlaylistDownloadWords.playsOffline == "This playlist is downloaded - it plays with no connection.")
        #expect(PlaylistDownloadWords.place == "Downloaded playlists")
        #expect(PlaylistDownloadWords.count(1) == "1 playlist" && PlaylistDownloadWords.count(3) == "3 playlists")
        #expect(PlaylistDownloadWords.removeAllToo(playlists: 0) == nil)
        #expect(PlaylistDownloadWords.removeAllToo(playlists: 1)?.hasPrefix("Your downloaded playlist goes") == true)
        #expect(PlaylistDownloadWords.removeAllToo(playlists: 3)?.hasPrefix("Your 3 downloaded playlists go") == true)
        let banned = ["Navidrome", "the store", "cache", "sync", "MD5", "offline mode", "everything", "checksum", "Browse"]
        let lines = PlaylistDownloadWords.everyLine
        #expect(lines.count > 10)
        for line in lines {
            #expect(!line.isEmpty)
            for word in banned { #expect(!line.localizedCaseInsensitiveContains(word), "\"\(line)\" says \(word)") }
        }
    }

    // MARK: the answer kept as sent

    @Test func aPlaylistIsReadWithItsBodyAsSent() async throws {
        let (client, transport) = client(session: "s")
        let body = #"{"playlist": \#(PlaylistPlayTests.summary), "songs": [{"id": "s1", "title": "Roads", "albumId": "al-d"}], "hidden": 0, "extra": 1}"#
        transport.answer("/deadwax/navidrome/playlists/pl1", 200, body)
        let read = try await client.playlistAnswered(id: "pl1")
        #expect(read.playlist.playlist.id == "pl1" && read.playlist.songs.map(\.id) == ["s1"])
        #expect(read.body == Data(body.utf8), "kept as deadwax sent it, not a re-encoding")
        // and the answer in hand encodes back to what reads the same
        let encoded = try JSONEncoder().encode(read.playlist)
        #expect(try JSONDecoder().decode(PlaylistWithSongs.self, from: encoded) == read.playlist)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""public":false"#))
    }
}
