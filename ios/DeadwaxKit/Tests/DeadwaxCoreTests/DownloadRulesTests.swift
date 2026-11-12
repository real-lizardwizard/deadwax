import Foundation
import Testing
@testable import DeadwaxCore

// Phase 2's rules (notes/ios-specs/phase2-downloads.md 2, 8.3, 8.4): a song's state, every transition, the album's state
// and what each menu offers. The cases are the spec's: nothing here has a web counterpart.

private func record(_ id: String = "s1", album: String = "al-1", size: Int64? = 1_000, state: StoredState = .wanted,
                    format: String = "raw", duration: Double? = 200) -> DownloadRecord {
    DownloadRecord(id: id, albumID: album, disc: 1, track: 1, format: format, suffix: format == "raw" ? "flac" : "mp3",
                   sizeExpected: format == "raw" ? size : nil, duration: duration, state: state, wantedAt: 1)
}

@Suite struct DownloadStateTests {
    @Test func aSongsStateFromItsRecordAndItsTask() {
        #expect(DownloadRules.state(nil) == .none)
        var r = record()
        #expect(DownloadRules.state(r) == .waiting(.queued), "asked for, not yet planned")
        #expect(DownloadRules.state(r, planned: .room) == .waiting(.room))
        r.wait = .wifi
        #expect(DownloadRules.state(r) == .waiting(.wifi), "the store's kept wait draws before the planner runs")
        r = DownloadRules.apply(.taskMade("t"), to: r)
        #expect(r.state == .fetching && r.task == "t" && r.wait == nil)
        #expect(DownloadRules.state(r) == .waiting(.queued), "a task out with no byte yet is queued")
        #expect(DownloadRules.state(r, received: 0, planned: .wifi) == .waiting(.wifi), "the network holding it is said")
        #expect(DownloadRules.state(r, received: 0, planned: .room) == .waiting(.queued), "a task out isn't waiting for room")
        #expect(DownloadRules.state(r, received: 400) == .fetching(0.4))
        #expect(DownloadRules.state(r, received: 400, planned: .wifi) == .fetching(0.4), "its first byte: fetching")
        r = DownloadRules.apply(.arrived(bytes: 1_000, check: .unchecked, flac: nil, at: 5), to: r)
        #expect(DownloadRules.state(r) == .done(.unchecked))
        #expect(DownloadRules.state(r).isHere && DownloadRules.playsOffline(DownloadRules.state(r)))
        r = DownloadRules.apply(.checked(.matched), to: r)
        #expect(DownloadRules.state(r) == .done(.matched))
    }

    @Test func aTranscodesFractionIsOverItsEstimateAndHeldUnder95() {
        let r = record(format: "mp3", duration: 100)
        #expect(r.expectedBytes == 4_000_000, "100 s at 320 kbps")
        #expect(DownloadRules.fraction(received: 2_000_000, of: r) == 0.5)
        #expect(DownloadRules.fraction(received: 9_000_000, of: r) == DownloadRules.transcodeHold, "past its estimate: held")
        #expect(DownloadRules.expectedBytes(size: 5_000, transcode: true, duration: nil) == 0, "a transcode has no size of its own")
        #expect(DownloadRules.expectedBytes(size: 5_000, transcode: false, duration: 10) == 5_000)
    }

    @Test func threeTriesThenFailedWithTheLastReason() {
        var r = DownloadRules.apply(.taskMade("t"), to: record())
        r = DownloadRules.apply(.refused(status: 500, detail: "boom"), to: r)
        #expect(r.state == .wanted && r.tries == 1 && r.failure == nil && r.task == nil)
        r = DownloadRules.apply(.wrongLength, to: r)
        #expect(r.state == .wanted && r.tries == 2)
        r = DownloadRules.apply(.refused(status: 404, detail: nil), to: r)
        #expect(r.state == .failed && r.tries == 3 && r.failure == .answered(status: 404, detail: nil))
        #expect(DownloadRules.state(r) == .failed(.answered(status: 404, detail: nil)))
    }

    @Test func aFailureWhileDeadwaxWasAwayIsNoTry() {
        var r = DownloadRules.apply(.taskMade("t"), to: record())
        r = DownloadRules.apply(.noAnswer(.offline(reason: "lost"), resume: Data([1, 2]), counts: false), to: r)
        #expect(r.state == .wanted && r.tries == 0 && r.resume == Data([1, 2]), "a wait, its resume data kept")
        r = DownloadRules.apply(.taskMade("t2"), to: r)
        r = DownloadRules.apply(.noAnswer(.timeout(reason: "slow"), resume: nil, counts: true), to: r)
        #expect(r.tries == 1 && r.resume == Data([1, 2]), "deadwax had answered: a try, the resume data still kept")
    }

    @Test func a401IsASignInWaitAndDropsItsResumeData() {
        var r = record()
        r.resume = Data([9])
        r.tries = 2
        r = DownloadRules.apply(.signedOut, to: DownloadRules.apply(.taskMade("t"), to: r))
        #expect(r.state == .wanted && r.wait == .signIn && r.resume == nil && r.tries == 2)
    }

    @Test func aForceQuitsCancelKeepsItsResumeDataAndIsNoTry() {
        var r = DownloadRules.apply(.taskMade("t"), to: record())
        r = DownloadRules.apply(.cancelled(resume: Data([7])), to: r)
        #expect(r.state == .wanted && r.resume == Data([7]) && r.tries == 0 && r.task == nil)
        r = DownloadRules.apply(.cancelled(resume: nil), to: r)
        #expect(r.resume == Data([7]), "a cancel without resume data keeps what was kept")
    }

    @Test func aSoundThatDidntMatchIsDeletedAndATry() {
        var r = DownloadRules.apply(.arrived(bytes: 1_000, check: .unchecked, flac: nil, at: 5), to: record())
        r = DownloadRules.apply(.soundMismatch, to: r)
        #expect(r.state == .wanted && r.bytes == nil && r.check == nil && r.doneAt == nil && r.tries == 1)
        r.tries = 2
        r = DownloadRules.apply(.unreadable, to: DownloadRules.apply(.arrived(bytes: 1_000, check: .unchecked, flac: nil, at: 6), to: r))
        #expect(r.state == .failed && r.failure == .unreadable)
    }

    @Test func aFullPhoneIsAWaitAndAnotherWriteFailureATry() {
        let out = DownloadRules.apply(.taskMade("t"), to: record())
        let full = DownloadRules.apply(.unsaved(outOfSpace: true), to: out)
        #expect(full.state == .wanted && full.wait == .phoneFull && full.tries == 0)
        let other = DownloadRules.apply(.unsaved(outOfSpace: false), to: out)
        #expect(other.tries == 1)
    }

    @Test func tryAgainStartsTheTriesAfreshAndALaunchGivesOneMore() {
        var r = record()
        r.state = .failed
        r.tries = 3
        r.failure = .wrongSize
        let launched = DownloadRules.apply(.launched, to: r)
        #expect(launched.state == .wanted && launched.tries == 3)
        #expect(DownloadRules.apply(.wrongLength, to: launched).state == .failed, "one more try, and failed again")
        let retried = DownloadRules.apply(.retry, to: r)
        #expect(retried.state == .wanted && retried.tries == 0 && retried.failure == nil)
    }

    @Test func aMissingFileIsAskedForAgain() {
        let r = DownloadRules.apply(.arrived(bytes: 1_000, check: .matched, flac: nil, at: 5), to: record())
        #expect(DownloadRules.apply(.fileMissing, to: r).state == .wanted)
    }

    @Test func whatTheTaskBringsIsTheSongOnlyAt200Or206AndItsLength() {
        #expect(DownloadRules.isTheSong(status: 200) && DownloadRules.isTheSong(status: 206))
        #expect(!DownloadRules.isTheSong(status: 401) && !DownloadRules.isTheSong(status: 404) && !DownloadRules.isTheSong(status: 304))
        #expect(DownloadRules.lengthMatches(1_000, record: record()))
        #expect(!DownloadRules.lengthMatches(999, record: record()))
        #expect(DownloadRules.lengthMatches(5, record: record(format: "mp3")), "a transcode: any length but 0")
        #expect(!DownloadRules.lengthMatches(0, record: record(format: "mp3")))
    }

    @Test func whatIsCheckedAfterTheLength() {
        func info(bits: Int, md5: [UInt8]) -> FLACStreamInfo {
            FLACStreamInfo(minBlockSize: 4096, maxBlockSize: 4096, sampleRate: 44_100, channels: 2, bitsPerSample: bits,
                           totalSamples: 10, md5: md5)
        }
        #expect(DownloadRules.checkAfterLength(info(bits: 16, md5: Array(repeating: 1, count: 16))) == .unchecked)
        #expect(DownloadRules.checkAfterLength(info(bits: 24, md5: Array(repeating: 1, count: 16))) == .unchecked)
        #expect(DownloadRules.checkAfterLength(info(bits: 32, md5: Array(repeating: 1, count: 16))) == .bySize, "over 24 bits")
        #expect(DownloadRules.checkAfterLength(info(bits: 16, md5: Array(repeating: 0, count: 16))) == .bySize, "no fingerprint")
        #expect(DownloadRules.checkAfterLength(nil) == .bySize, "not a FLAC")
    }

    @Test func theVerdictsWords() {
        #expect(DownloadRules.verdict(.matched, isFLAC: true) == .checked)
        #expect(DownloadRules.verdict(.bySize, isFLAC: false) == .checked, "size is all an MP3 allows")
        #expect(DownloadRules.verdict(.bySize, isFLAC: true) == .bySize)
        #expect(DownloadRules.verdict(.unchecked, isFLAC: true) == .checking)
        #expect(DownloadRules.verdict([(.matched, true), (.bySize, false)]) == .checked)
        #expect(DownloadRules.verdict([(.matched, true), (.bySize, true)]) == .bySize)
        #expect(DownloadRules.verdict([(.bySize, true), (.unchecked, true)]) == .checking)
    }

    @Test func removingTakesTheOriginsAskedThroughAndDeletesTheSongsLeftWithNone() {
        let origins: [String: Set<DownloadOrigin>] = ["a": [.song], "b": [.song, .album("x")], "c": [.album("x"), .other("library")]]
        let after = DownloadRules.afterRemoving([.song, .album("x")], from: origins)
        #expect(after.deleted == ["a", "b"])
        #expect(after.kept == ["c": [.other("library")]], "Phase 3's library origin keeps it")
    }

    @Test func originsAndFailuresRoundTripThroughTheirColumns() {
        for origin in [DownloadOrigin.song, .album("al-1"), .other("library"), .other("playlist:p")] {
            #expect(DownloadOrigin(raw: origin.raw) == origin)
        }
        #expect(DownloadOrigin(raw: "album:") == .other("album:"))
        let failures: [DownloadFailure] = [.answered(status: 404, detail: "gone"), .answered(status: 500, detail: nil),
                                           .offline(reason: "lost"), .timeout(reason: "slow"), .wrongSize, .soundMismatch,
                                           .unreadable, .unsaved]
        for failure in failures { #expect(DownloadFailure(code: failure.code, raw: failure.raw) == failure) }
        #expect(DownloadFailure(code: "nonsense", raw: nil) == nil)
    }

    @Test func aTasksNameCarriesWhereItLands() {
        let name = DownloadTaskName(server: "http://10.0.0.2:8090", person: "james|x", songID: "s-1", suffix: "flac")
        #expect(!name.description.contains("http://"))
        #expect(name.description.split(separator: "|").count == 4, "no part holds the separator")
        #expect(DownloadTaskName(description: name.description) == name)
        #expect(DownloadTaskName(description: "a|b|c") == nil)
        #expect(DownloadTaskName(description: "a|b||flac") == nil)
    }

    @Test func aRecordForASongIsFetchedAsItsStreamIs() {
        let song = Song(id: "s", title: "Roads", albumId: "al", track: 3, discNumber: 1, duration: 300, suffix: "opus", size: 9_000)
        let r = DownloadRecord(song: song, albumID: "al", now: 42)
        #expect(r.format == "mp3" && r.suffix == "mp3" && r.sizeExpected == nil && r.isTranscode, "Opus: Navidrome's mp3")
        #expect(r.fileName == "s.mp3" && r.wantedAt == 42 && r.track == 3)
        let flac = DownloadRecord(song: Song(id: "f", suffix: "flac", size: 9_000), albumID: "al", now: 1)
        #expect(flac.format == "raw" && flac.sizeExpected == 9_000 && flac.fileName == "f.flac")
    }

    @Test func theSettingsAsThePhoneKeepsThem() {
        #expect(DownloadOver(saved: nil) == .wifi && DownloadOver(saved: "any") == .any && DownloadOver(saved: "x") == .wifi)
        #expect(DownloadOver.wifi.access == (false, false, false) && DownloadOver.any.access == (true, true, true))
        #expect(StorageLimit(saved: nil) == .gb20 && StorageLimit(saved: "none") == .none && StorageLimit(saved: "7") == .gb20)
        #expect(StorageLimit.allCases.map(\.label) == ["5 GB", "10 GB", "20 GB", "50 GB", "100 GB", "No limit"])
        #expect(StorageLimit.gb20.bytes == 20_000_000_000 && StorageLimit.none.bytes == nil)
        #expect(DownloadOver.storageKey == "downloadOver" && StorageLimit.storageKey == "storageLimit")
    }
}

@Suite struct AlbumDownloadTests {
    private func facts(_ states: [SongDownload], expected: Int64 = 100, received: [Int64]? = nil) -> [AlbumSongFacts] {
        states.enumerated().map { index, state in
            let got: Int64 = received?[index] ?? (state.isHere ? expected : 0)
            return AlbumSongFacts(state: state, expected: expected, received: got)
        }
    }

    @Test func eachRowOfTheOrder() {
        #expect(AlbumDownload.of(facts([.none, .none])) == .none)
        #expect(AlbumDownload.of([]) == .none)
        #expect(AlbumDownload.of(facts([.done(.matched), .none, .none])) == .partial(here: 1, of: 3))
        #expect(AlbumDownload.of(facts([.done(.matched), .done(.bySize)])) == .downloaded(checking: false))
        #expect(AlbumDownload.of(facts([.done(.matched), .done(.unchecked)])) == .downloaded(checking: true))
        #expect(AlbumDownload.of(facts([.done(.matched), .failed(.wrongSize), .failed(.unsaved)]))
                == .failed(count: 2, first: .wrongSize))
        #expect(AlbumDownload.of(facts([.done(.matched), .waiting(.wifi), .waiting(.room)])) == .waiting(.wifi, here: 1, of: 3))
    }

    @Test func fetchingOverWaitingOverFailed() {
        let states: [SongDownload] = [.failed(.unsaved), .waiting(.queued), .fetching(0.5), .done(.matched), .none]
        guard case .downloading(let here, let of, let fraction) = AlbumDownload.of(facts(states, received: [0, 0, 50, 100, 0])) else {
            Issue.record("fetching first")
            return
        }
        #expect(here == 1 && of == 3, "the songs here, of those asked for or here (a failed one isn't counted)")
        #expect(abs(fraction - 150.0 / 300.0) < 1e-9, "bytes here and received over every song here or asked for")
        #expect(AlbumDownload.of(facts([.failed(.unsaved), .waiting(.deadwax)])) == .waiting(.deadwax, here: 0, of: 1))
    }

    @Test func whetherAnyIsHere() {
        #expect(AlbumDownload.partial(here: 1, of: 3).hasSongsHere)
        #expect(AlbumDownload.downloading(here: 0, of: 3, fraction: 0.1).hasSongsHere == false)
        #expect(AlbumDownload.waiting(.room, here: 2, of: 3).hasSongsHere)
        #expect(!AlbumDownload.failed(count: 1, first: .unsaved).hasSongsHere)
    }
}

@Suite struct DownloadChoiceTests {
    @Test func oneSongsItems() {
        #expect(DownloadChoice.forSong(.none) == [.download])
        #expect(DownloadChoice.forSong(.waiting(.wifi)) == [.remove])
        #expect(DownloadChoice.forSong(.fetching(0.2)) == [.remove])
        #expect(DownloadChoice.forSong(.done(.matched)) == [.remove])
        #expect(DownloadChoice.forSong(.failed(.unsaved)) == [.downloadAgain, .remove])
    }

    @Test func severalSongsItems() {
        #expect(DownloadChoice.forSongs([.none, .none]) == [.download])
        #expect(DownloadChoice.forSongs([.done(.matched), .none]) == [.download, .remove])
        #expect(DownloadChoice.forSongs([.done(.matched), .fetching(0.1)]) == [.remove])
        #expect(DownloadChoice.forSongs([.done(.matched), .failed(.unsaved)]) == [.download, .remove])
        #expect(DownloadChoice.forSongs([.done(.matched), .none], gone: true) == [.remove], "nothing to fetch when gone")
        #expect(DownloadChoice.forSongs([]) == [])
        #expect(DownloadChoice.asked(by: [.done(.matched), .none, .failed(.unsaved), .waiting(.room)]) == [1, 2])
    }

    @Test func downloadUpNextIsForTwoOrMoreAndNeverAShuffledLibrary() {
        #expect(DownloadChoice.upNext([.none, .done(.matched)], paged: false) == nil, "one is Download")
        #expect(DownloadChoice.upNext([.none, .failed(.unsaved), .fetching(0.1)], paged: false) == 2)
        #expect(DownloadChoice.upNext([.none, .none, .none], paged: true) == nil)
    }

    @Test func theItemsLookAndRole() {
        #expect(DownloadChoice.download.label == "Download" && DownloadChoice.download.symbol == "arrow.down.circle")
        #expect(DownloadChoice.downloadAgain.label == "Download Again" && DownloadChoice.downloadAgain.symbol == "arrow.clockwise")
        #expect(DownloadChoice.remove.label == "Remove Download" && DownloadChoice.remove.symbol == "trash")
        #expect(DownloadChoice.remove.isDestructive && !DownloadChoice.download.isDestructive)
    }
}
