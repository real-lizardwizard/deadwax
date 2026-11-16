import Foundation
import Testing
@testable import DeadwaxCore

/// How long the phone waits for Get lyrics, Get CD art and Tags' Apply (review, 16 Nov - EditWaits): by the album in
/// hand, past the server's worst case for it with a minute's margin, rounded up to the minute, and never under the
/// route's own `Routes.timeouts`. tests/test_ios_edit_parts_contract.py holds each figure against the server's source.
@Suite struct EditWaitsTests {
    @Test func getLyricsIsWaitedForByTheTracksItAsks() {
        // a track: two names, two requests each, 55 s a request (40 s of silence, 15 s of busy pauses)
        let request = EditWaits.lrclibRequest + EditWaits.lrclibBusy
        #expect(EditWaits.lrclibNames * EditWaits.lrclibRequestsPerName * request == 220)
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B", trackCount: 12)) == 1380, "six rounds of two, and the margin")
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B", trackCount: 13)) == 1620, "an odd track is a round of its own")
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B", trackCount: 12, lyricsCount: 10)) == 600,
                "two left to ask: 280 s, under the route's own 600")
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B", trackCount: 5)) == 720, "three rounds: 720 s exactly")
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B")) == 600, "nothing counted: one track at least, and the floor")
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B", trackCount: 3, lyricsCount: 9)) == 600)
        #expect(EditWaits.lyrics(ScanAlbum(path: "A/B", trackCount: 30)) == 3360)
    }

    @Test func getCDArtIsWaitedForByTheDiscs() {
        // each Archive address three requests of 55 s; the listing, fanart.tv's, then a picture a disc
        #expect(EditWaits.discArt(ScanAlbum(path: "A/B", discCount: 1)) == 420, "415 s, to the minute")
        #expect(EditWaits.discArt(ScanAlbum(path: "A/B")) == 420, "no disc counted: one")
        #expect(EditWaits.discArt(ScanAlbum(path: "A/B", discCount: 2)) == 600)
        #expect(EditWaits.discArt(ScanAlbum(path: "A/B", discCount: 4)) == 960, "910 s, to the minute")
        #expect(EditWaits.discArt(ScanAlbum(path: "A/B", discCount: 10)) == 1920)
        #expect(EditWaits.discArt(ScanAlbum(path: "A/B", discCount: 1)) > Routes.timeouts[Routes.discArtFetch] ?? 0,
                "one disc through the Archive's redirects is past the route's own 360 already")
    }

    @Test func tagsApplyIsWaitedForByTheFilesSize() {
        #expect(EditWaits.tagsApply(bytes: 0) == 120, "the route's own")
        #expect(EditWaits.tagsApply(bytes: 60_000_000) == 180)
        #expect(EditWaits.tagsApply(bytes: 1_200_000_000) == 180, "1.2 GB written whole: a minute")
        #expect(EditWaits.tagsApply(bytes: 3_000_000_000) == 300, "a hi-res album: 120 s and 150 s, to the minute")
        #expect(EditWaits.tagsApply(bytes: -1) == 120)
        #expect(EditWaits.tagsApply(bytes: .nan) == 120)
        #expect(EditWaits.tagsApply(bytes: .infinity) == 120, "a size that can't be read waits the route's own")
    }

    @Test func aWaitIsRoundedUpToTheMinuteAndNeverUnderTheRoutes() {
        #expect(EditWaits.wait(61, floor: nil) == 120)
        #expect(EditWaits.wait(120, floor: nil) == 120)
        #expect(EditWaits.wait(0, floor: 30) == 30)
        #expect(EditWaits.wait(500, floor: 600) == 600)
    }
}
