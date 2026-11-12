import Foundation
import Testing
@testable import DeadwaxCore

// The player and the album page while deadwax can't be reached (spec 3.7, 7.3), and Now Playing's ••• name (4.1).

@Suite struct OfflinePlayTests {
    // MARK: a song not on this phone

    @Test func aSongNotHereIsPassedOverToOneThatIs() {
        #expect(OfflinePlay.after(intendsToPlay: true, hereAfter: true, chosen: false) == .skip)
    }

    @Test func withNothingHereStillToComeThePlayerStopsOnIt() {
        #expect(OfflinePlay.after(intendsToPlay: true, hereAfter: false, chosen: false) == .stop)
    }

    @Test func theOneTappedInUpNextStopsOnItself() {
        //? the listener chose it: passing over it would play something they didn't ask for
        #expect(OfflinePlay.after(intendsToPlay: true, hereAfter: true, chosen: true) == .stop)
    }

    @Test func pausedItStops() {
        for here in [true, false] {
            #expect(OfflinePlay.after(intendsToPlay: false, hereAfter: here, chosen: false) == .stop)
        }
    }

    @Test func itIsNeverAskedForAgain() {
        //? no .retry in any case: nothing would answer
        for intends in [true, false] {
            for here in [true, false] {
                for chosen in [true, false] {
                    #expect(OfflinePlay.after(intendsToPlay: intends, hereAfter: here, chosen: chosen) != .retry)
                }
            }
        }
    }

    @Test func whatIsStillToCome() {
        let here = [true, false, false, true, false]
        #expect(OfflinePlay.hereAfter(here, index: 1, repeatAll: false), "song 4 is here")
        #expect(!OfflinePlay.hereAfter(here, index: 3, repeatAll: false), "only song 5 is after it")
        #expect(OfflinePlay.hereAfter(here, index: 3, repeatAll: true), "Repeat All comes round to song 1")
        #expect(!OfflinePlay.hereAfter([true, false], index: 1, repeatAll: false))
        #expect(OfflinePlay.hereAfter([true, false], index: 1, repeatAll: true))
        #expect(!OfflinePlay.hereAfter([false], index: 0, repeatAll: true), "the song itself isn't still to come")
        #expect(!OfflinePlay.hereAfter([], index: 0, repeatAll: true))
    }

    // MARK: the skip's notice

    @Test func oneSkipIsNamed() {
        var run = OfflinePlay.SkipRun()
        #expect(run.skipped(title: "Roads", now: 100) == "Skipped \"Roads\" - it isn't on this phone")
        #expect(run.count == 1)
    }

    @Test func aRunWithinTheNoticesTimeIsCounted() {
        var run = OfflinePlay.SkipRun()
        _ = run.skipped(title: "Roads", now: 100)
        #expect(run.skipped(title: "Undenied", now: 100.2) == "Skipped 2 songs that aren't on this phone")
        #expect(run.skipped(title: "Humming", now: 104.9) == "Skipped 3 songs that aren't on this phone")
        //? past the notice's 5 s, a new run
        #expect(run.skipped(title: "Mysterons", now: 110) == "Skipped \"Mysterons\" - it isn't on this phone")
    }

    @Test func aSongWithNoTitleIsASong() {
        var run = OfflinePlay.SkipRun()
        #expect(run.skipped(title: "", now: 0) == "Skipped \"a song\" - it isn't on this phone")
        var again = OfflinePlay.SkipRun()
        #expect(again.skipped(title: nil, now: 0) == "Skipped \"a song\" - it isn't on this phone")
    }

    // MARK: the album page

    @Test func offlineTheAlbumPlaysWhatIsHereInItsOrder() {
        let songs = ["a", "b", "c", "d"].map { Song(id: $0) }
        let here: Set<String> = ["d", "b"]
        #expect(OfflineAlbum.playable(songs, here: { here.contains($0) }).map(\.id) == ["b", "d"])
        #expect(OfflineAlbum.playable(songs, here: { _ in false }).isEmpty)
    }

    @Test func thePagesOwnLine() {
        #expect(OfflineAlbum.note(online: true, haveSongs: true, gone: true, anyHere: true) == DownloadWords.albumGoneHere)
        #expect(OfflineAlbum.note(online: false, haveSongs: true, gone: true, anyHere: true) == DownloadWords.albumGoneHere)
        #expect(OfflineAlbum.note(online: false, haveSongs: false, gone: false, anyHere: false) == DownloadWords.albumNotHere)
        //? nothing of it here, gone: Phase 1's own gone line, not this one
        #expect(OfflineAlbum.note(online: true, haveSongs: false, gone: true, anyHere: false) == nil)
        #expect(OfflineAlbum.note(online: false, haveSongs: true, gone: false, anyHere: true) == nil)
        #expect(OfflineAlbum.note(online: true, haveSongs: true, gone: false, anyHere: false) == nil)
    }

    // MARK: Now Playing's •••

    @Test func nowPlayingsMoreSaysDownload() {
        #expect(NowPlayingWords.more(hasAlbum: true, download: true) == "More: info, go to album, download")
        #expect(NowPlayingWords.more(hasAlbum: false, download: true) == "More: info, download")
        #expect(NowPlayingWords.more(hasAlbum: true) == "More: info, go to album", "Phase 1's words, with no downloads")
    }
}
