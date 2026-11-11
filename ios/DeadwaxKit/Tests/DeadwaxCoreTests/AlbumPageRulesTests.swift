import Foundation
import Testing
@testable import DeadwaxCore

/// PlayingBars: the album page's playing mark - AlbumPage.tsx's `player.track?.id === song.id` and icons.tsx's
/// `aria-label={paused ? 'paused' : 'playing'}`, held by hand (no TypeScript is run: two literals and one `===`).
@Suite struct PlayingBarsTests {
    private func track(_ id: String) -> QueueTrack {
        QueueTrack(id: id, title: "Roads", artist: "Portishead", album: "Dummy", albumId: "al-1")
    }

    @Test func theWordsAreTheWebsAriaLabel() {
        #expect(PlayingBars.label(paused: false) == "playing")
        #expect(PlayingBars.label(paused: true) == "paused")
    }

    @Test func theRowOfTheSongHeardIsMarked() {
        let song = Song(id: "tr-3", title: "Roads", albumId: "al-1")
        #expect(PlayingBars.marks(song, heard: track("tr-3")))
        #expect(!PlayingBars.marks(song, heard: track("tr-4")))
        #expect(!PlayingBars.marks(song, heard: nil))
    }

    @Test func itIsTheSongsIdAloneThatCounts() {
        // the same song queued from another album's page, a playlist or Debug: its row here is marked all the same
        let song = Song(id: "tr-3", title: "Roads (live)", albumId: "al-1")
        var heard = track("tr-3")
        heard.albumId = "al-9"
        heard.title = "Something else"
        #expect(PlayingBars.marks(song, heard: heard))
        // ids compare as JS's ===: exactly, case and all
        #expect(!PlayingBars.marks(Song(id: "TR-3"), heard: track("tr-3")))
        #expect(!PlayingBars.marks(Song(id: "tr-3 "), heard: track("tr-3")))
    }
}

/// AlbumGone: the phone's own rule for an album page whose album isn't there - `{}`, or a 404 ErrorWords reads as
/// not-found; nothing else.
@Suite struct AlbumGoneTests {
    private let server = ServerAddress(base: URL(string: "http://deadwax.test:8080")!)

    private func answered(_ status: Int, detail: String? = nil, kind: String? = nil) -> APIFailure {
        .answered(.init(status: status, method: "GET", path: "/navidrome/albums/al-1", detail: detail, kind: kind))
    }

    @Test func anEmptyAnswerIsGone() {
        #expect(AlbumGone.isGone(empty: true, failure: nil))
        #expect(!AlbumGone.isGone(empty: false, failure: nil))
    }

    @Test func aNotFoundIsGoneAndSaidAsTheGoneLine() {
        let failure = answered(404, detail: "Navidrome has nothing by that id")
        #expect(AlbumGone.isGone(empty: false, failure: failure))
        #expect(ErrorWords.of(failure, gone: ErrorWords.albumGone).said == ErrorWords.albumGone)
        #expect(AlbumGone.isGone(empty: false, failure: answered(404)))
    }

    @Test func everyOtherFailureIsNotGone() {
        let none = APIFailure.NoAnswer(server: server, method: "GET", path: "/navidrome/albums/al-1", reason: "offline")
        for failure in [answered(502, detail: "Navidrome said no"), answered(503), answered(500), answered(401),
                        answered(403), answered(408), APIFailure.offline(none), APIFailure.timeout(none),
                        APIFailure.other("deadwax's answer couldn't be read")] {
            #expect(!AlbumGone.isGone(empty: false, failure: failure), "\(failure)")
        }
        #expect(!AlbumGone.isGone(empty: false, failure: CancellationError()))
    }

    @Test func aNamedRefusalWithA404IsTheServersOwnWordsNotGone() {
        // ErrorWords reads a 404 that deadwax named a kind of, with words fit to show, as a refusal: said as sent
        let failure = answered(404, detail: "That album is somewhere else now.", kind: "moved")
        #expect(ErrorWords.kind(of: failure) == .refused)
        #expect(!AlbumGone.isGone(empty: false, failure: failure))
    }
}
