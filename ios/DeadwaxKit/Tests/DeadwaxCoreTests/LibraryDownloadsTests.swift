import Foundation
import Testing
@testable import DeadwaxCore

// Your library downloaded (phase3-autodownload.md 2.6-2.7, slice 2): what the library asks of the store and what it
// gives back. The strict rules, each a test of its own: nothing wanted by anything but the library is ever deleted by
// it; an empty or suspicious list deletes nothing; a removal waits for two checks ten minutes apart; every delete is
// Phase 2's removeOrigins.

private let t0: Int64 = 1_800_000_000_000
private let minute: Int64 = 60_000
private let gb: Int64 = 1_000_000_000
private let mb: Int64 = 1_000_000

private func read(_ album: String, _ count: Int = 2, bytes: Int64 = 100 * mb) -> [FollowedSong] {
    (1...count).map { FollowedSong(id: "\(album)-\($0)", disc: 1, track: $0, size: bytes, suffix: "flac") }
}

private func entry(_ id: String) -> IndexAlbum {
    IndexAlbum(id: id, name: "Album \(id)", songCount: 2, duration: 600)
}

/// An album of the library, its songs read.
private func followed(_ id: String, _ position: Int = 0, songs: [FollowedSong]? = nil, missingSince: Int64? = nil,
                      removedHere: Int64? = nil, keptOff: Int64? = nil, unread: Bool = false,
                      left: [String: Int64] = [:]) -> FollowedAlbum {
    FollowedAlbum(album: entry(id), position: position, songs: unread ? nil : (songs ?? read(id)),
                  readAt: unread ? nil : t0, missingSince: missingSince, removedHere: removedHere, keptOff: keptOff,
                  left: left)
}

private func library(_ ids: [String]) -> [FollowedAlbum] {
    ids.enumerated().map { followed($1, $0) }
}

/// Both songs of `album` in the store with `origins`.
private func here(_ album: String, _ origins: Set<DownloadOrigin> = [.library], state: StoredState = .done,
                  count: Int = 2, bytes: Int64 = 100 * mb) -> [StoreSong] {
    (1...count).map { StoreSong(id: "\(album)-\($0)", albumID: album, origins: origins, state: state, bytes: bytes) }
}

private func listed(_ ids: [String]) -> LibraryFollow.Answer {
    .listed(AlbumIndexAnswer(albums: ids.map(entry)))
}

/// Every album fits.
private func roomy(_ ordered: [FollowedAlbum]) -> LibraryFill.Plan {
    LibraryFill.plan(LibraryFill.albums(ordered), .init(limit: nil, freeSpace: 10_000 * gb))
}

/// One check and its turn, as LibraryFollower and DownloadModel run them: the sync, then the fill and the actions.
private func check(_ kept: [FollowedAlbum], _ answer: LibraryFollow.Answer, held: LibraryFollow.Held? = nil,
                   at: Int64, songs: [StoreSong], believing: Bool = false, limit: Int64? = nil,
                   free: Int64 = 10_000 * gb) -> (out: LibraryFollow.Outcome, turn: LibraryDownloads.Turn) {
    let out = LibraryFollow.sync(kept, answer: answer, held: held, at: at, believing: believing)
    let ordered = LibraryFollow.ordered(out.albums, scope: .yours, now: at)
    let bytes = songs.reduce(Int64(0)) { $0 + ($1.state == .done ? $1.bytes : 0) }
    let turn = LibraryDownloads.turn(ordered, removed: Set(out.removed), songs: songs, bytesHere: bytes, handToCome: 0,
                                     limit: limit, freeSpace: free)
    return (out, turn)
}

/// The songs a turn deletes - Phase 2's rule over its takes.
private func deleted(_ turn: LibraryDownloads.Turn, _ songs: [StoreSong]) -> [String] {
    LibraryDownloads.deleted(turn.actions, songs: songs)
}

@Suite struct LibraryDownloadsTests {
    // MARK: rule 1 - the library takes only its own origin

    @Test func theLibraryOnlyEverTakesItsOwnOrigin() {
        #expect(LibraryDownloads.gives == [.library])
        #expect(DownloadOrigin.library == .other("library") && DownloadOrigin.library.raw == "library")
        #expect(DownloadOrigin(raw: "library") == .library, "a store written before Phase 3 reads it as the same origin")
    }

    @Test func noSongWantedByHandInAPlaylistOrAnyOtherWayIsEverDeleted() {
        // every reason the library has to give back, each album holding songs wanted another way beside its own
        let others: [Set<DownloadOrigin>] = [[.song], [.album("x")], [.other("playlist:p1")], [.other("anything:later")]]
        var songs: [StoreSong] = []
        for (n, origin) in others.enumerated() {
            for album in ["removed", "gave", "kept", "notOn"] {
                songs.append(StoreSong(id: "\(album)-hand\(n)", albumID: album, origins: origin.union([.library]),
                                       bytes: 50 * mb))
                songs.append(StoreSong(id: "\(album)-only\(n)", albumID: album, origins: origin, bytes: 50 * mb))
            }
        }
        songs += here("removed") + here("gave") + here("kept") + here("notOn")
        // every song of notOn found to have left it, by two reads ten minutes apart
        var gone: [String: Int64] = [:]
        for song in songs where song.albumID == "notOn" && song.isLibrary { gone[song.id] = t0 - 10 * minute }
        let ordered = [followed("gave", 0, songs: read("gave", 2, bytes: 30 * gb)), followed("kept", 1, keptOff: t0),
                       followed("notOn", 2, songs: [FollowedSong(id: "notOn-stays")], left: gone)]
        let fill = LibraryFill.plan(LibraryFill.albums(ordered), .init(limit: StorageLimit.gb20.bytes, freeSpace: 500 * gb))
        let actions = LibraryDownloads.actions(ordered, fill: fill, removed: ["removed"], songs: songs)
        #expect(actions.why == ["removed": .removed, "gave": .gaveWay, "kept": .keptOff, "notOn": .notOnAlbum])
        let deletedNow = Set(LibraryDownloads.deleted(actions, songs: songs))
        #expect(deletedNow == Set(["removed-1", "removed-2", "gave-1", "gave-2", "kept-1", "kept-2", "notOn-1", "notOn-2"]))
        // nothing deleted carried another origin; nothing without the library's was even touched
        let byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        for id in deletedNow { #expect(byID[id]?.origins == [.library], "\(id) carried another origin") }
        for id in actions.take { #expect(byID[id]?.isLibrary == true, "\(id) wasn't the library's to take") }
    }

    @Test func theSwitchOffTakesOnlyTheLibrarysOriginAndDeletesOnlyItsOwnSongs() {
        let songs = here("a") + here("b", [.library, .album("b")]) + here("c", [.song]) + here("d", [.other("playlist:x"), .library])
        let actions = LibraryDownloads.switchedOff(songs)
        #expect(Set(actions.take) == Set(["a-1", "a-2", "b-1", "b-2", "d-1", "d-2"]))
        #expect(LibraryDownloads.deleted(actions, songs: songs) == ["a-1", "a-2"])
        #expect(Set(actions.why.values) == [.switchedOff])
    }

    @Test func everyDeleteIsPhaseTwosRuleOverTheTakes() {
        let songs = here("a") + [StoreSong(id: "a-3", albumID: "a", origins: [.library, .song])]
        let actions = LibraryDownloads.Actions(take: ["a-1", "a-2", "a-3"])
        let origins = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0.origins) })
        #expect(LibraryDownloads.deleted(actions, songs: songs)
            == DownloadRules.afterRemoving(LibraryDownloads.gives, from: origins).deleted)
    }

    @Test func inTheStoreTheLibrarysTakesDeleteOnlyItsOwnSongsAndNoKeptPlay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-libdl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try DownloadDatabase(path: folder.appendingPathComponent("downloads.sqlite").path)
        let wanted: [(String, [DownloadOrigin])] = [("lib", [.library]), ("hand", [.library, .song]),
                                                    ("album", [.library, .album("al")]),
                                                    ("list", [.library, .other("playlist:p")]), ("mine", [.song])]
        for (n, (id, origins)) in wanted.enumerated() {
            var record = DownloadRecord(id: id, albumID: "al", suffix: "flac", sizeExpected: 10, wantedAt: Int64(n))
            record = DownloadRules.apply(.arrived(bytes: 10, check: .matched, flac: nil, at: 5), to: record)
            try db.put(record)
            for origin in origins { try db.addOrigin(origin, song: id, at: Int64(n)) }
            _ = try db.keepPlay(songID: id, timeMs: 1_000 + Int64(n))
            _ = try db.keepStart(Played(at: 2_000 + Int64(n), queue: nil, entry: nil, song: simTrack(id)))
        }
        try db.keepQueue(kind: "queue", body: Data([7]), at: 3)
        let songs = LibraryDownloads.songs(try db.songs(), origins: try db.origins(), library: [])
        let actions = LibraryDownloads.switchedOff(songs)
        let predicted = LibraryDownloads.deleted(actions, songs: songs)
        let gone = try db.removeOrigins(LibraryDownloads.gives, songs: actions.take)
        #expect(gone == ["lib"] && predicted == gone)
        #expect(Set(try db.songs().map(\.id)) == ["hand", "album", "list", "mine"])
        #expect(try db.origins()["hand"] == [.song] && db.origins()["list"] == [.other("playlist:p")])
        #expect(try db.keptPlays().count == 5, "a kept play is never the library's to remove")
        #expect(try db.keptStartCount() == 5)
        #expect(try db.keptQueue()?.body == Data([7]))
    }

    // MARK: rule 2 - an empty or suspicious list deletes nothing

    @Test func anEmptyListDeletesNothingAndConfirmsNothingLater() {
        let kept = library(["a", "b", "c"])
        let songs = here("a") + here("b") + here("c")
        let first = check(kept, listed([]), at: t0, songs: songs)
        #expect(first.out.held == .empty(kept: 3) && first.out.missing.isEmpty)
        #expect(first.turn.actions.take.isEmpty && deleted(first.turn, songs).isEmpty)
        // and an hour on, again and as a 304 of it: still nothing
        let again = check(first.out.albums, listed([]), held: first.out.held, at: t0 + 60 * minute, songs: songs)
        #expect(again.turn.actions.take.isEmpty && again.out.removed.isEmpty)
        let unchanged = check(first.out.albums, .unchanged, held: first.out.held, at: t0 + 61 * minute, songs: songs)
        #expect(unchanged.turn.actions.take.isEmpty && unchanged.out.removed.isEmpty)
    }

    @Test func aLargeDropDeletesNothing() {
        let ids = (0..<30).map { "a\($0)" }
        let kept = library(ids)
        let songs = ids.flatMap { here($0) }
        let first = check(kept, listed(Array(ids.prefix(5))), at: t0, songs: songs)
        #expect(first.out.held == .drop(gone: 25, of: 30))
        #expect(first.turn.actions.take.isEmpty)
        let later = check(first.out.albums, .unchanged, held: first.out.held, at: t0 + 20 * minute, songs: songs)
        #expect(later.turn.actions.take.isEmpty && later.out.removed.isEmpty)
    }

    @Test func aTruncatedListDeletesNothing() {
        let kept = library(["a", "b"])
        let songs = here("a") + here("b")
        let answer = LibraryFollow.Answer.listed(AlbumIndexAnswer(albums: [entry("a")], truncated: true))
        let first = check(kept, answer, at: t0, songs: songs)
        let later = check(first.out.albums, answer, held: first.out.held, at: t0 + 20 * minute, songs: songs)
        #expect(first.turn.actions.take.isEmpty && later.turn.actions.take.isEmpty)
        // even believing: a truncated list is never believed
        let believed = check(first.out.albums, answer, held: first.out.held, at: t0 + 40 * minute, songs: songs,
                             believing: true)
        #expect(believed.turn.actions.take.isEmpty && !believed.out.believed)
    }

    @Test func anAlbumTheTableNoLongerHasForAnyOtherReasonKeepsItsSongs() {
        // nothing in the library, nothing removed: the store's library songs stay (a table read empty is no list)
        let songs = here("a") + here("b")
        let actions = LibraryDownloads.actions([], fill: roomy([]), removed: [], songs: songs)
        #expect(actions.take.isEmpty)
        let some = LibraryDownloads.actions(library(["a"]), fill: roomy(library(["a"])), removed: [], songs: songs)
        #expect(some.take.isEmpty, "b isn't in the library, but no check removed it")
    }

    // MARK: rule 3 - two checks at least 10 minutes apart

    @Test func aRemovalWaitsForTwoChecksTenMinutesApart() {
        let kept = library(["a", "b"])
        let songs = here("a") + here("b")
        let first = check(kept, listed(["a"]), at: t0, songs: songs)
        #expect(first.out.missing == ["b"])
        #expect(first.turn.actions.take.isEmpty, "missing isn't removed")
        #expect(first.turn.fill.fits.contains("b"), "a missing album stays in the fill until removed")
        let early = check(first.out.albums, listed(["a"]), at: t0 + 10 * minute - 1, songs: songs)
        #expect(early.out.removed.isEmpty && early.turn.actions.take.isEmpty)
        let early304 = check(first.out.albums, .unchanged, at: t0 + 10 * minute - 1, songs: songs)
        #expect(early304.turn.actions.take.isEmpty)
        let agreed = check(first.out.albums, listed(["a"]), at: t0 + 10 * minute, songs: songs)
        #expect(agreed.out.removed == ["b"])
        #expect(Set(agreed.turn.actions.take) == ["b-1", "b-2"] && agreed.turn.actions.why == ["b": .removed])
        let agreed304 = check(first.out.albums, .unchanged, at: t0 + 10 * minute, songs: songs)
        #expect(Set(agreed304.turn.actions.take) == ["b-1", "b-2"])
    }

    @Test func aMissingAlbumIsAskedForNothingMore() {
        var ordered = library(["a", "b"])
        ordered[1].missingSince = t0
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: [])
        #expect(actions.ask.map(\.album) == ["a"])
    }

    @Test func backBeforeTheSecondCheckKeepsEverything() {
        let kept = library(["a", "b"])
        let songs = here("a") + here("b")
        let first = check(kept, listed(["a"]), at: t0, songs: songs)
        let back = check(first.out.albums, listed(["a", "b"]), at: t0 + 11 * minute, songs: songs)
        #expect(back.out.back == ["b"] && back.turn.actions.take.isEmpty)
    }

    @Test func removedHereGoesWhenTheNextListConfirmsItAndNotBefore() {
        let kept = [followed("a", 0), followed("b", 1, removedHere: t0)]
        let songs = here("a") + here("b") + [StoreSong(id: "b-hand", albumID: "b", origins: [.song], bytes: mb)]
        // a list asked before the Remove answered still has it: kept
        let stale = check(kept, listed(["a", "b"]), at: t0 - 1, songs: songs)
        #expect(stale.turn.actions.take.isEmpty)
        let confirmed = check(kept, listed(["a"]), at: t0 + 1, songs: songs)
        #expect(confirmed.out.removed == ["b"])
        #expect(deleted(confirmed.turn, songs) == ["b-1", "b-2"], "the song downloaded by hand stays")
    }

    @Test func rememberingRemoveOnTheQuestionStillWaitsTenMinutes() {
        let kept = library(["a", "b", "c"])
        let songs = here("a") + here("b") + here("c")
        let held = check(kept, listed([]), at: t0, songs: songs)
        #expect(LibraryFollow.asks(held.out.held, keptThem: false))
        // Remove answered: the next list is believed - missing, nothing removed yet
        let believed = check(held.out.albums, listed([]), held: held.out.held, at: t0 + minute, songs: songs,
                             believing: true)
        #expect(believed.out.believed && believed.out.held == nil)
        #expect(Set(believed.out.missing) == ["a", "b", "c"])
        #expect(believed.turn.actions.take.isEmpty)
        #expect(LibraryFollow.keepsBelieving(believed.out, listed: true))
        let early = check(believed.out.albums, listed([]), at: t0 + 11 * minute - 1, songs: songs, believing: true)
        #expect(early.turn.actions.take.isEmpty)
        let agreed = check(believed.out.albums, .unchanged, held: believed.out.held, at: t0 + 11 * minute,
                           songs: songs, believing: true)
        #expect(Set(agreed.out.removed) == ["a", "b", "c"])
        #expect(deleted(agreed.turn, songs).count == 6)
        #expect(!LibraryFollow.keepsBelieving(agreed.out, listed: false), "spent: nothing is missing any more")
    }

    @Test func believingEndsWithAListThatWasntHeld() {
        let kept = library(["a", "b"])
        let fine = LibraryFollow.sync(kept, answer: listed(["a", "b"]), held: nil, at: t0, believing: true)
        #expect(!fine.believed && !LibraryFollow.keepsBelieving(fine, listed: true))
        let missingOne = LibraryFollow.sync(kept, answer: listed(["a"]), held: nil, at: t0, believing: true)
        #expect(!LibraryFollow.keepsBelieving(missingOne, listed: true), "an ordinary list is no question's answer")
    }

    @Test func theQuestionIsAskedForAnEmptyListOrADropUntilKeepThem() {
        #expect(LibraryFollow.asks(.empty(kept: 3), keptThem: false))
        #expect(LibraryFollow.asks(.drop(gone: 20, of: 30), keptThem: false))
        #expect(!LibraryFollow.asks(.drop(gone: 20, of: 30), keptThem: true))
        #expect(!LibraryFollow.asks(.truncated, keptThem: false))
        #expect(!LibraryFollow.asks(nil, keptThem: false))
    }

    // MARK: giving way, keeping off, songs gone from an album

    @Test func aLoweredLimitGivesWayFromTheBottomWholeAndNeverAHandDownload() {
        let ordered = [followed("top", 0, songs: read("top", 2, bytes: 4 * gb)),
                       followed("mid", 1, songs: read("mid", 2, bytes: 4 * gb)),
                       followed("bottom", 2, songs: read("bottom", 2, bytes: 4 * gb))]
        let songs = here("top", bytes: 4 * gb) + here("mid", bytes: 4 * gb) + here("bottom", bytes: 4 * gb)
            + [StoreSong(id: "hand", albumID: "elsewhere", origins: [.album("elsewhere")], bytes: 1 * gb)]
        let turn = LibraryDownloads.turn(ordered, removed: [], songs: songs, bytesHere: 25 * gb, handToCome: 0,
                                         limit: StorageLimit.gb20.bytes, freeSpace: 100 * gb)
        #expect(turn.fill.fits == ["top", "mid"] && turn.fill.waits == ["bottom": .room])
        #expect(Set(turn.actions.take) == ["bottom-1", "bottom-2"] && turn.actions.why == ["bottom": .gaveWay])
        // 10 GB, 1 of it by hand: only the top fits
        let lower = LibraryDownloads.turn(ordered, removed: [], songs: songs, bytesHere: 25 * gb, handToCome: 0,
                                          limit: StorageLimit.gb10.bytes, freeSpace: 100 * gb)
        #expect(Set(lower.actions.take) == ["mid-1", "mid-2", "bottom-1", "bottom-2"])
        #expect(!lower.actions.take.contains("hand"))
    }

    @Test func aHandDownloadOnAFullPhoneMakesTheBottomGiveWay() {
        let ordered = [followed("top", 0, songs: read("top", 2, bytes: 2 * gb)),
                       followed("bottom", 1, songs: read("bottom", 2, bytes: 2 * gb))]
        let songs = here("top", bytes: 2 * gb) + here("bottom", bytes: 2 * gb)
        // 3 GB free and a 5 GB hand download to come: 4 GB under the reserve once it arrives
        let seen = LibraryDownloads.turn(ordered, removed: [], songs: songs, bytesHere: 8 * gb, handToCome: 5 * gb,
                                         limit: nil, freeSpace: 3 * gb)
        #expect(seen.fill.deficit == 4 * gb && seen.actions.take.isEmpty, "not until it holds on plans minutes apart")
        let turn = LibraryDownloads.turn(ordered, removed: [], songs: songs, bytesHere: 8 * gb, handToCome: 5 * gb,
                                         limit: nil, freeSpace: 3 * gb, deficitConfirmed: true)
        #expect(turn.fill.fits == ["top"] && turn.fill.waits == ["bottom": .phoneFull])
        #expect(turn.actions.why == ["bottom": .gaveWay])
    }

    @Test func nothingGivesWayWhileThePhoneKeepsItsReserve() {
        let ordered = library(["a", "b"])
        let songs = here("a") + here("b")
        let turn = LibraryDownloads.turn(ordered, removed: [], songs: songs, bytesHere: 400 * mb, handToCome: 0,
                                         limit: nil, freeSpace: 2 * gb + 1)
        #expect(turn.actions.take.isEmpty)
    }

    @Test func anAlbumWaitingForRoomWithNothingHereGivesBackItsAsks() {
        let ordered = [followed("big", 0, songs: read("big", 2, bytes: 30 * gb))]
        let songs = here("big", state: .wanted, bytes: 0)
        let actions = LibraryDownloads.actions(ordered, fill: LibraryFill.plan(LibraryFill.albums(ordered),
                                                                               .init(limit: StorageLimit.gb20.bytes, freeSpace: 500 * gb)),
                                               removed: [], songs: songs)
        #expect(actions.why == ["big": .waits] && actions.take.count == 2)
    }

    @Test func keptOffGivesBackAndIsNeverAskedAgain() {
        let ordered = [followed("off", 0, keptOff: t0), followed("on", 1)]
        let songs = here("off")
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: songs)
        #expect(actions.why == ["off": .keptOff] && Set(actions.take) == ["off-1", "off-2"])
        #expect(actions.ask.map(\.album) == ["on"])
    }

    @Test func aSongNoLongerOnItsAlbumGoesAndTheRestStay() {
        let songs = here("a")
        // two reads ten minutes apart agree a-2 left
        let ordered = [followed("a", 0, songs: [read("a")[0]], left: ["a-2": t0 - 10 * minute])]
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: songs)
        #expect(actions.take == ["a-2"] && actions.why == ["a": .notOnAlbum])
        // one read, or two nine minutes apart, or none marking it: nothing goes
        for left in [["a-2": t0], ["a-2": t0 - 10 * minute + 1], [:]] as [[String: Int64]] {
            let early = [followed("a", 0, songs: [read("a")[0]], left: left)]
            #expect(LibraryDownloads.actions(early, fill: roomy(early), removed: [], songs: songs).take.isEmpty)
        }
    }

    @Test func anAlbumWhoseSongsAreReadAgainKeepsEverything() {
        let ordered = [followed("a", 0, unread: true)]
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: here("a"))
        #expect(actions.isEmpty)
    }

    // MARK: asking

    @Test func albumsThatFitAreAskedInOrderForTheSongsNotYetTheLibrarys() {
        let ordered = library(["a", "b", "c"])
        let songs = here("a") + [StoreSong(id: "b-1", albumID: "b", origins: [.song])]
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: songs)
        #expect(actions.ask.map(\.album) == ["b", "c"])
        #expect(actions.ask[0].songs.map(\.id) == ["b-1", "b-2"], "a song downloaded by hand gains the origin beside its own")
        #expect(actions.take.isEmpty)
    }

    @Test func atMostTenAlbumsAreOnTheirWayAtOnce() {
        let ids = (0..<25).map { String(format: "a%02d", $0) }
        let ordered = library(ids)
        let first = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: [])
        #expect(first.ask.map(\.album) == Array(ids.prefix(10)))
        // three on their way, two of the first ten here: seven more
        let songs = here("a00") + here("a01") + here("a02", state: .fetching) + here("a03", state: .wanted)
            + here("a04", state: .wanted)
        let next = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: songs)
        #expect(next.ask.map(\.album) == Array(ids[5..<12]))
        // songs already here with another origin need no fetch, and take no place
        let hand = ids.prefix(10).flatMap { here($0, [.song]) }
        let gained = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: hand)
        #expect(gained.ask.count == 20)
    }

    @Test func nothingIsAskedBelowAnAlbumStillToBeRead() {
        let ordered = [followed("a", 0), followed("b", 1, unread: true), followed("c", 2)]
        let reading = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: [], readsPending: true)
        #expect(reading.ask.map(\.album) == ["a"])
        let done = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: [], readsPending: false)
        #expect(done.ask.map(\.album) == ["a", "c"])
    }

    @Test func anAlbumRemovedHereIsAskedForNothing() {
        let ordered = [followed("a", 0, removedHere: t0), followed("b", 1)]
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: [])
        #expect(actions.ask.map(\.album) == ["b"])
    }

    @Test func aSongThatFailedByHandIsAskedAgainAndTakesAPlace() {
        let ordered = library(["a"])
        let songs = [StoreSong(id: "a-1", albumID: "a", origins: [.song], state: .failed)]
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: [], songs: songs)
        #expect(actions.ask.first?.songs.map(\.id) == ["a-1", "a-2"])
    }

    @Test func aRemovedAlbumThatCameBackIsntAskedTheSameTurn() {
        let ordered = library(["a"])
        let actions = LibraryDownloads.actions(ordered, fill: roomy(ordered), removed: ["a"], songs: here("a"))
        #expect(actions.why == ["a": .removed] && actions.ask.isEmpty)
    }

    // MARK: the fill's inputs and the store's songs

    @Test func theFillCountsSongsWantedByHandAsHandDownloads() {
        let songs = here("a") + here("b", [.library, .song]) + here("c", state: .wanted)
        let kept = ["a": Int64(0), "b": 0, "c": 0]
        let inputs = LibraryDownloads.inputs(library(["a", "b", "c"]), songs: songs, covers: kept)
        #expect(inputs.hand == ["b-1", "b-2"])
        #expect(inputs.albums.map(\.here) == [200 * mb, 0, 0] && inputs.givable == 200 * mb)
        #expect(inputs.albums.map(\.bytes) == [200 * mb, 0, 200 * mb], "b's songs are the hand download's")
        #expect(inputs.albums.map(\.held) == [true, true, true] && inputs.albums.map(\.toCome) == [0, 0, 200 * mb])
    }

    @Test func storeSongsAreReadOnTheAlbumOfTheLibraryThatHasThem() {
        var record = DownloadRecord(id: "x-1", albumID: "", suffix: "flac", sizeExpected: 5, wantedAt: 1)
        record = DownloadRules.apply(.arrived(bytes: 5, check: .matched, flac: nil, at: 2), to: record)
        let lone = DownloadRecord(id: "y", albumID: "yal", suffix: "flac", wantedAt: 1)
        let songs = LibraryDownloads.songs([record, lone], origins: ["x-1": [.library]],
                                           library: [followed("x", 0, songs: [FollowedSong(id: "x-1")])])
        #expect(songs[0].albumID == "x" && songs[0].bytes == 5 && songs[0].onlyLibrary)
        #expect(songs[1].albumID == "yal" && songs[1].origins == [.song], "no origin kept reads as asked for alone")
        #expect(songs[1].bytes == 0, "bytes only once here")
    }

    @Test func theLibrarysDownloadedListsALibraryAlbumOnlyOnceSomethingOfItCame() {
        var songs = here("waits", state: .wanted) + here("arrived") + here("failed", state: .failed)
        songs += here("hand", [.album("hand")], state: .wanted)
        songs += [StoreSong(id: "going-1", albumID: "going", origins: [.library], state: .fetching),
                  StoreSong(id: "going-2", albumID: "going", origins: [.library], state: .wanted)]
        #expect(LibraryDownloads.listed(songs) == ["going", "arrived", "failed", "hand"])
    }

    // MARK: the screens

    @Test func progressCountsTheAlbumsThatFitAndArentAllHere() {
        let ordered = library(["a", "b", "c"])
        let fill = roomy(ordered)
        let songs = here("a") + here("b", count: 1)
        let progress = LibraryDownloads.progress(ordered, fill: fill, songs: songs)
        #expect(progress == LibraryDownloads.Progress(toGo: 2, of: 3, bytes: 300 * mb))
        #expect(abs((progress?.fraction ?? 0) - 1.0 / 3) < 1e-9)
        #expect(LibraryDownloads.progress(ordered, fill: fill, songs: here("a") + here("b") + here("c")) == nil)
        // an album whose songs not here all failed isn't on its way
        let failed = here("a") + here("b") + here("c", state: .failed)
        #expect(LibraryDownloads.progress(ordered, fill: fill, songs: failed) == nil)
    }

    @Test func anAlbumPageSaysHowTheLibraryHasIt() {
        let ordered = [followed("here", 0), followed("big", 1, songs: read("big", 2, bytes: 30 * gb)),
                       followed("off", 2, keptOff: t0)]
        let fill = LibraryFill.plan(LibraryFill.albums(ordered), .init(limit: StorageLimit.gb20.bytes, freeSpace: 500 * gb))
        let songs = here("here")
        func mark(_ id: String, following: Bool = true) -> LibraryDownloads.AlbumMark {
            LibraryDownloads.mark(id, following: following, library: ordered.first { $0.id == id }, fill: fill, songs: songs)
        }
        #expect(mark("here") == .withLibrary)
        #expect(mark("big") == .waitsForRoom)
        #expect(mark("off") == .keptOff)
        #expect(mark("elsewhere") == .none)
        #expect(mark("here", following: false) == .none)
    }

    @Test func aSongYourLibraryKeepsOffersNoRemoveOfItsOwn() {
        let here = SongDownload.done(.matched)
        #expect(DownloadChoice.forSong(here, keptByLibrary: true) == [])
        #expect(DownloadChoice.forSong(.failed(.wrongSize), keptByLibrary: true) == [.downloadAgain])
        #expect(DownloadChoice.forSong(here, keptByLibrary: false) == [.remove])
        #expect(DownloadChoice.forSongs([here, here], keptByLibrary: [true, true]) == [])
        #expect(DownloadChoice.forSongs([here, here], keptByLibrary: [true, false]) == [.remove])
        #expect(DownloadChoice.forSongs([.none, here], keptByLibrary: [false, true]) == [.download])
    }
}
