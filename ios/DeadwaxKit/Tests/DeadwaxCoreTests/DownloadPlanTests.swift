import Foundation
import Testing
@testable import DeadwaxCore

// The planner and the storage limit (spec 8.5), the waits' order, and the rules offline (7.1, 7.6, 5.4).

private let gb: Int64 = 1_000_000_000

/// An album's songs asked for as an album, `each` bytes apiece, asked at `at`.
private func album(_ id: String, songs: Int, each: Int64, at: Int64) -> [DownloadPlan.Song] {
    (1...songs).map { n in
        DownloadPlan.Song(id: "\(id)-\(n)", albumID: id, disc: 1, track: n, wantedAt: at, origins: [.album(id)], expected: each)
    }
}

private func facts(here: Int64 = 0, limit: StorageLimit = .gb20, free: Int64 = 100 * gb, reach: Reach = .online,
                   path: NetworkPath = .wifiAtHome, signedIn: Bool = true, over: DownloadOver = .wifi) -> DownloadPlan.Facts {
    DownloadPlan.Facts(bytesHere: here, limit: limit.bytes, freeSpace: free, reach: reach, path: path, signedIn: signedIn, over: over)
}

@Suite struct DownloadPlanTests {
    @Test func anAlbumThatFitsGoesWholeInItsOrder() {
        let plan = DownloadPlan.plan(album("a", songs: 3, each: gb, at: 1), facts())
        #expect(plan.values.allSatisfy { $0 == DownloadPlan.Decision(wait: .queued, task: true) })
        #expect(plan.count == 3)
    }

    @Test func anAlbumThatDoesntFitWaitsAndASmallerOneAfterItGoes() {
        let big = album("big", songs: 4, each: 2 * gb, at: 1)       // 8 GB
        let small = album("small", songs: 2, each: gb / 2, at: 2)   // 1 GB
        let plan = DownloadPlan.plan(big + small, facts(here: 15 * gb))
        #expect(big.allSatisfy { plan[$0.id] == DownloadPlan.Decision(wait: .room, task: false) }, "the whole album waits: never half of it")
        #expect(small.allSatisfy { plan[$0.id] == DownloadPlan.Decision(wait: .queued, task: true) }, "one big album never holds up small ones")
    }

    @Test func whenRoomComesTheOldestGoesFirst() {
        let first = album("first", songs: 2, each: 3 * gb, at: 1)
        let second = album("second", songs: 2, each: 3 * gb, at: 2)
        let plan = DownloadPlan.plan(second + first, facts(here: 12 * gb))
        #expect(first.allSatisfy { plan[$0.id]?.task == true })
        #expect(second.allSatisfy { plan[$0.id]?.wait == .room })
    }

    @Test func theTwoGigabyteReserve() {
        let one = album("a", songs: 1, each: 3 * gb, at: 1)
        #expect(DownloadPlan.plan(one, facts(limit: StorageLimit.none, free: 5 * gb))["a-1"]?.task == true, "5 - 3 leaves 2 GB")
        #expect(DownloadPlan.plan(one, facts(limit: StorageLimit.none, free: 5 * gb - 1))["a-1"] == DownloadPlan.Decision(wait: .phoneFull, task: false))
        // what the units let go have yet to receive counts against the free space
        let two = album("b", songs: 1, each: 2 * gb, at: 2)
        let plan = DownloadPlan.plan(one + two, facts(limit: StorageLimit.none, free: 6 * gb))
        #expect(plan["a-1"]?.task == true && plan["b-1"]?.wait == .phoneFull)
    }

    @Test func noLimitIsBoundOnlyByThePhone() {
        let plan = DownloadPlan.plan(album("a", songs: 10, each: 50 * gb, at: 1), facts(here: 900 * gb, limit: StorageLimit.none, free: 600 * gb))
        #expect(plan.values.allSatisfy { $0.task })
    }

    @Test func aLimitLoweredBelowWhatsHereRemovesNothingAndNewUnitsWaitForRoom() {
        let started = [DownloadPlan.Song(id: "s-1", albumID: "s", track: 1, wantedAt: 1, origins: [.album("s")], expected: gb,
                                         received: gb / 2, out: true),
                       DownloadPlan.Song(id: "s-2", albumID: "s", track: 2, wantedAt: 1, origins: [.album("s")], expected: gb)]
        let fresh = album("new", songs: 1, each: 100, at: 2)
        let plan = DownloadPlan.plan(started + fresh, facts(here: 8 * gb, limit: .gb5))
        #expect(plan["s-1"] == DownloadPlan.Decision(wait: .queued, task: true), "a started album goes on: never half an album for room")
        #expect(plan["s-2"]?.task == true)
        #expect(plan["new-1"] == DownloadPlan.Decision(wait: .room, task: false))
    }

    @Test func aSongAskedAloneIsAUnitOfItsOwnAndOneWithItsAlbumGoesWithIt() {
        let alone = DownloadPlan.Song(id: "x", albumID: "al", wantedAt: 1, origins: [.song], expected: 4 * gb)
        let both = DownloadPlan.Song(id: "y", albumID: "al2", wantedAt: 2, origins: [.song, .album("al2")], expected: gb)
        let sibling = DownloadPlan.Song(id: "z", albumID: "al2", wantedAt: 3, origins: [.album("al2")], expected: 20 * gb)
        let plan = DownloadPlan.plan([alone, both, sibling], facts(here: 10 * gb))
        #expect(plan["x"]?.task == true)
        #expect(plan["y"]?.wait == .room && plan["z"]?.wait == .room, "y is planned with its album, whole")
    }

    @Test func theWaitsOrder() {
        let songs = album("a", songs: 1, each: 100, at: 1)
        func wait(_ f: DownloadPlan.Facts) -> DownloadWait? { DownloadPlan.plan(songs, f)["a-1"]?.wait }
        let cellular = NetworkPath(satisfied: true, cellular: true, expensive: true)
        let hotspot = NetworkPath(satisfied: true, wifi: true, expensive: true)
        let lowData = NetworkPath(satisfied: true, wifi: true, constrained: true)
        #expect(wait(facts(reach: .noNetwork, path: .none, signedIn: false)) == .connection, "connection before all")
        #expect(wait(facts(reach: .unreachable, path: cellular, signedIn: false)) == .deadwax, "deadwax before sign-in")
        #expect(wait(facts(path: cellular, signedIn: false)) == .signIn)
        #expect(wait(facts(path: cellular)) == .wifi)
        #expect(wait(facts(path: hotspot)) == .hotspot)
        #expect(wait(facts(path: lowData)) == .lowData)
        #expect(wait(facts(path: NetworkPath(satisfied: true, cellular: true, expensive: true, constrained: true))) == .wifi,
                "on mobile data with Low Data on, it is Wi-Fi that's waited for")
        #expect(wait(facts(path: cellular, over: .any)) == .queued, "neither with Wi-Fi and cellular")
        #expect(wait(facts(path: hotspot, over: .any)) == .queued)
        #expect(wait(facts(path: lowData, over: .any)) == .queued)
        #expect(wait(facts(here: 30 * gb, path: cellular)) == .wifi, "the network's wait before the limit's")
        #expect(wait(facts(here: 30 * gb)) == .room)
    }

    @Test func aNetworkWaitStillMakesItsTaskForIOSToHoldButDeadwaxAwayAndSignedOutDont() {
        let songs = album("a", songs: 2, each: 100, at: 1)
        let cellular = NetworkPath(satisfied: true, cellular: true, expensive: true)
        #expect(DownloadPlan.plan(songs, facts(path: cellular)).values.allSatisfy { $0 == DownloadPlan.Decision(wait: .wifi, task: true) })
        #expect(DownloadPlan.plan(songs, facts(reach: .noNetwork, path: .none)).values.allSatisfy { $0.task })
        #expect(DownloadPlan.plan(songs, facts(reach: .unreachable)).values.allSatisfy { !$0.task })
        #expect(DownloadPlan.plan(songs, facts(signedIn: false)).values.allSatisfy { !$0.task })
        #expect(DownloadPlan.plan(songs, facts(here: 25 * gb, path: cellular)).values.allSatisfy { $0 == DownloadPlan.Decision(wait: .wifi, task: false) },
                "a unit that doesn't fit makes no task, whatever the network")
    }

    @Test func aTaskOutStaysOutUnlessSignedOut() {
        let out = [DownloadPlan.Song(id: "o", albumID: "a", wantedAt: 1, origins: [.album("a")], expected: 100, out: true)]
        #expect(DownloadPlan.plan(out, facts(reach: .unreachable))["o"] == DownloadPlan.Decision(wait: .deadwax, task: true))
        #expect(DownloadPlan.plan(out, facts(signedIn: false))["o"] == DownloadPlan.Decision(wait: .signIn, task: false), "cancelled, resume kept")
    }

    @Test func atMostAHundredTasksOut() {
        let many = album("a", songs: 150, each: 1_000, at: 1)
        let plan = DownloadPlan.plan(many, facts())
        #expect(plan.values.filter { $0.task }.count == DownloadPlan.maxOut)
        #expect(plan["a-1"]?.task == true && plan["a-150"]?.task == false && plan["a-150"]?.wait == .queued,
                "the first in the album's order go")
    }

    @Test func aTranscodesEstimateIsWhatsPlanned() {
        let record = DownloadRecord(id: "t", albumID: "a", format: "mp3", suffix: "mp3", duration: 250, wantedAt: 1)
        let song = DownloadPlan.Song(record, origins: [.album("a")])
        #expect(song.expected == 10_000_000)
        #expect(DownloadPlan.plan([song], facts(here: StorageLimit.gb5.bytes! - 9_999_999, limit: .gb5))["t"]?.wait == .room)
    }
}

@Suite struct OfflineRuleTests {
    private let wifi = NetworkPath.wifiAtHome

    @Test func noNetworkAtOnce() {
        var rule = OfflineRule()
        #expect(rule.pathChanged(.none, now: 0) == .nothing)
        #expect(rule.reach == .noNetwork)
        #expect(rule.noAnswer(now: 1) == .nothing, "nothing is tried with no network")
        #expect(rule.pathChanged(wifi, now: 2) == .probe, "the network back: asked at once")
        #expect(rule.reach == .noNetwork, "until the probe says")
        rule.probeAnswered(now: 3)
        #expect(rule.reach == .online)
    }

    @Test func twoFailuresMakeItUnreachableAndAnyAnswerBringsItBack() {
        var rule = OfflineRule()
        _ = rule.pathChanged(wifi, now: 0)
        #expect(rule.noAnswer(now: 1) == .probe)
        #expect(rule.noAnswer(now: 1.5) == .nothing, "one probe at a time")
        #expect(rule.reach == .online)
        rule.probeFailed(now: 4)
        #expect(rule.reach == .unreachable)
        #expect(rule.nextProbe == 34)
        #expect(rule.tick(now: 20) == .nothing)
        #expect(rule.tick(now: 34) == .probe, "every 30 s")
        rule.probeFailed(now: 37)
        #expect(rule.reach == .unreachable && rule.nextProbe == 67)
        #expect(rule.pathChanged(wifi, now: 40) == .probe, "a path change probes at once")
        rule.probeAnswered(now: 41)
        #expect(rule.reach == .online && rule.nextProbe == nil)
    }

    @Test func aRequestAnsweredMidProbeIsDeadwaxReached() {
        var rule = OfflineRule()
        _ = rule.pathChanged(wifi, now: 0)
        _ = rule.noAnswer(now: 1)
        rule.answered(now: 2)
        rule.probeFailed(now: 4)
        #expect(rule.reach == .online, "one failure after an answer isn't two in a row")
    }

    @Test func askingNowProbesOnlyWhileNotOnline() {
        var rule = OfflineRule()
        _ = rule.pathChanged(wifi, now: 0)
        #expect(rule.askNow(now: 1) == .nothing)
        _ = rule.noAnswer(now: 2)
        rule.probeFailed(now: 5)
        #expect(rule.askNow(now: 6) == .probe, "the banner's Try again")
        #expect(rule.answeredSince(0) == false)
        rule.probeAnswered(now: 7)
        #expect(rule.answeredSince(6) && !rule.answeredSince(8))
    }

    @Test func aBlipWhileOnlineMovesNothing() {
        var rule = OfflineRule()
        _ = rule.pathChanged(wifi, now: 0)
        #expect(rule.pathChanged(NetworkPath(satisfied: true, cellular: true, expensive: true), now: 1) == .nothing)
        #expect(rule.reach == .online)
    }

    @Test func thePathsKind() {
        #expect(NetworkPath.wifiAtHome.kind == .wifi)
        #expect(NetworkPath(satisfied: true, cellular: true, expensive: true).kind == .mobileData)
        #expect(NetworkPath(satisfied: true, wifi: true, expensive: true).kind == .hotspot)
        #expect(NetworkPath(satisfied: true, wifi: true, constrained: true).kind == .lowData)
        #expect(NetworkPath.none.kind == .none)
    }
}

@Suite struct OfflineOtherRulesTests {
    @Test func keptPlaysAreSentOldestFirstEachForgottenOnA200() {
        #expect(PendingPlays.after(status: 200) == .sent)
        #expect(PendingPlays.after(status: 401) == .held)
        #expect(PendingPlays.after(status: 404) == .dropped)
        #expect(PendingPlays.after(status: 422) == .dropped)
        #expect(PendingPlays.after(status: 503) == .stopped)
        #expect(PendingPlays.after(status: nil) == .stopped)
        #expect(PendingPlays.keeps(.played(songID: "s", atMs: 1)))
        #expect(!PendingPlays.keeps(.nowPlaying(songID: "s")), "now playing would be stale")
    }

    @Test func theLibraryRootNeverSwapsUnderAFinger() {
        var root = LibraryRoot()
        #expect(root.look(online: false, onScreen: true) == .downloaded, "offline at launch: Downloaded")
        #expect(root.look(online: true, onScreen: true) == .downloaded, "back while it is on screen: unchanged")
        #expect(root.look(online: true, onScreen: false) == .albums, "off screen: it changes")
        #expect(root.look(online: false, onScreen: true) == .albums, "deadwax going while the root is on screen")
        #expect(root.look(online: false, onScreen: false) == .downloaded)
        var fresh = LibraryRoot()
        #expect(fresh.look(online: true, onScreen: true) == .albums)
    }

    @Test func theGateIsntConsultedWhileDeadwaxCantBeReached() {
        #expect(NavidromeGate.consulted(.online))
        #expect(!NavidromeGate.consulted(.noNetwork) && !NavidromeGate.consulted(.unreachable))
        let closed = NavidromeGate.Shown.closed(.init(title: "t", lines: [], tryAgain: true, setUp: false))
        #expect(NavidromeGate.showsDownloaded(closed, anythingHere: true))
        #expect(!NavidromeGate.showsDownloaded(closed, anythingHere: false))
        #expect(!NavidromeGate.showsDownloaded(.open, anythingHere: true))
    }

    @Test func downloadedsRecentlyAddedIsWhenEachArrivedOnThisPhone() {
        let albums = [Album(id: "a", name: "Dummy", artist: "Portishead", created: "2001-01-01T00:00:00Z"),
                      Album(id: "b", name: "Mezzanine", artist: "Massive Attack", created: "2020-01-01T00:00:00Z"),
                      Album(id: "c", name: "Not here")]
        let october = AlbumTime.ms("2026-10-03T10:00:00Z")!, november = AlbumTime.ms("2026-11-12T09:30:00.250Z")!
        let index = DownloadedAlbums.index(albums, arrived: ["a": november, "b": october])
        #expect(index.map(\.id) == ["a", "b"], "only albums with a song here")
        #expect(index[0].created == "2026-11-12T09:30:00.250Z")
        #expect(DownloadedAlbums.iso(ms: 0) == "1970-01-01T00:00:00.000Z")
        #expect(DownloadedAlbums.iso(ms: -1) == "1969-12-31T23:59:59.999Z")
        let shelf = Shelf(index, zone: TimeZone(identifier: "UTC")!)
        let sorted = shelf.sorted(.newest, by: AlbumList.downloaded.addedBy)
        #expect(sorted.map { index[$0].id } == ["a", "b"], "newest arrival first, whatever the collection's dates")
        let groups = shelf.groups(sorted, .newest, by: .phone)
        #expect(groups.count == 2, "grouped by the month each arrived")
        #expect(AlbumList.scope(.yours).addedBy == .you && AlbumList.scope(.store).addedBy == .collection)
    }
}

@Suite struct BytesAndMD5Tests {
    @Test func sizesInWords() {
        #expect(DeadwaxCore.Bytes.words(0) == "0 MB")
        #expect(DeadwaxCore.Bytes.words(1) == "1 MB", "anything above 0 and under 1 MB")
        #expect(DeadwaxCore.Bytes.words(412_000_000) == "412 MB")
        #expect(DeadwaxCore.Bytes.words(412_499_999) == "412 MB")
        #expect(DeadwaxCore.Bytes.words(999_999_999) == "1 GB", "never 1000 MB")
        #expect(DeadwaxCore.Bytes.words(1_000_000_000) == "1 GB")
        #expect(DeadwaxCore.Bytes.words(2_100_000_000) == "2.1 GB")
        #expect(DeadwaxCore.Bytes.words(20_000_000_000) == "20 GB", "a trailing .0 dropped")
        #expect(DeadwaxCore.Bytes.words(41_240_000_000) == "41.2 GB")
        #expect(DeadwaxCore.Bytes.words(99_949_999_999) == "99.9 GB")
        #expect(DeadwaxCore.Bytes.words(99_950_000_000) == "100 GB")
        #expect(DeadwaxCore.Bytes.words(128_400_000_000) == "128 GB")
    }

    @Test func md5sSevenVectors() {
        // RFC 1321, A.5
        let vectors = ["": "d41d8cd98f00b204e9800998ecf8427e",
                       "a": "0cc175b9c0f1b6a831c399e269772661",
                       "abc": "900150983cd24fb0d6963f7d28e17f72",
                       "message digest": "f96b697d7cb7938d525a2f31aaf161d0",
                       "abcdefghijklmnopqrstuvwxyz": "c3fcd3d76192e4007dfb496cca67e13b",
                       "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789": "d174ab98d277d9f5a5611c2c9f419d9f",
                       "12345678901234567890123456789012345678901234567890123456789012345678901234567890": "57edf4a22be3c955ac49da2e2107b67a"]
        for (text, digest) in vectors { #expect(MD5.hex(Array(text.utf8)) == digest, "\"\(text)\"") }
    }

    @Test func md5FedInPiecesIsTheSame() {
        let bytes = (0..<1_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        var whole = MD5()
        whole.update(bytes)
        for split in [1, 55, 56, 63, 64, 65, 128, 999] {
            var pieces = MD5()
            pieces.update(Array(bytes[..<split]))
            pieces.update(Array(bytes[split...]))
            var again = whole
            #expect(pieces.finish() == again.finish(), "split at \(split)")
        }
    }

    @Test func packingSixteenAndTwentyFourBitsSignIncluded() {
        // 16-bit: -1, 1, -32768, 32767 as little-endian two's complement, channels interleaved
        let left: [Float] = [-1.0 / 32_768, -1.0], right: [Float] = [1.0 / 32_768, 32_767.0 / 32_768]
        #expect(FLACMD5.pack([left, right], bits: 16) == [0xFF, 0xFF, 0x01, 0x00, 0x00, 0x80, 0xFF, 0x7F])
        // 24-bit: -2 and 8388607
        let scale: Float = 8_388_608
        #expect(FLACMD5.pack([[-2 / scale], [8_388_607 / scale]], bits: 24) == [0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])
        // what FLAC hashes is the integers': the packing of a 24-bit tone is its integers' bytes
        let ints: [Int32] = [0, 1, -1, 4_000_000, -4_000_000, 8_388_607, -8_388_608]
        let floats = ints.map { Float($0) / scale }
        var expected: [UInt8] = []
        for value in ints { for byte in 0..<3 { expected.append(UInt8(truncatingIfNeeded: value >> Int32(8 * byte))) } }
        #expect(FLACMD5.pack([floats], bits: 24) == expected)
    }
}
