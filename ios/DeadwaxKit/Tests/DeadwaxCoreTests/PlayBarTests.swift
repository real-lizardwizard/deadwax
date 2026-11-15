import Testing
@testable import DeadwaxCore

// The play bar on the tab bar (15 Nov): its gestures' rules and its words - the phone's own, with no web code to hold
// them to.
@Suite struct PlayBarTests {
    @Test func aDragsWayIsReadOnceItHasMovedFar() {
        #expect(PlayBar.way(dx: 6, dy: -6) == nil)
        #expect(PlayBar.way(dx: -12, dy: 4) == .across)
        #expect(PlayBar.way(dx: 3, dy: -11) == .up)
        #expect(PlayBar.way(dx: -2, dy: 14) == .down)
        // as far across as up: not across
        #expect(PlayBar.way(dx: 10, dy: -10) == .up)
    }

    @Test func aDragLeftIsTheNextSongAndRightTheOneBefore() {
        #expect(PlayBar.skip(dx: -60, predicted: -90) == .next)
        #expect(PlayBar.skip(dx: 55, predicted: 70) == .before)
    }

    @Test func underTheThresholdItGoesBack() {
        #expect(PlayBar.skip(dx: -40, predicted: -60) == nil)
        #expect(PlayBar.skip(dx: 30, predicted: 30) == nil)
    }

    @Test func pastTheThresholdButFlungBackItGoesBack() {
        #expect(PlayBar.skip(dx: -60, predicted: 20) == nil)
        #expect(PlayBar.skip(dx: 70, predicted: -150) == nil)
    }

    @Test func aFlickSkips() {
        #expect(PlayBar.skip(dx: -20, predicted: -140) == .next)
        #expect(PlayBar.skip(dx: 15, predicted: 130) == .before)
        #expect(PlayBar.skip(dx: 0, predicted: -120) == .next)
    }

    @Test func towardASongThatIsntThereTheTitleHoldsBack() {
        #expect(PlayBar.followed(dx: -30, songThere: true) == -30)
        #expect(PlayBar.followed(dx: 30, songThere: false) == 10)
        #expect(PlayBar.songThere(dx: -5, before: false, after: true))
        #expect(!PlayBar.songThere(dx: 5, before: false, after: true))
    }

    @Test func aDragUpOpensNowPlaying() {
        #expect(PlayBar.opens(dy: -45, predicted: -60))
        #expect(PlayBar.opens(dy: -15, predicted: -130))
    }

    @Test func aShortDragUpOrOneBroughtBackDoesnt() {
        #expect(!PlayBar.opens(dy: -30, predicted: -50))
        #expect(!PlayBar.opens(dy: -50, predicted: 10))
    }

    // after review: a drag starting at the line seeks only when it goes across; a tap is never a drag at all
    @Test func acrossFromTheLinesReachIsASeek() {
        #expect(PlayBar.role(.across, startY: 0, onTitle: true) == .seek)
        #expect(PlayBar.role(.across, startY: 13, onTitle: false) == .seek)
    }

    @Test func acrossBelowItIsASkipOnTheTitleAndNothingOverPlayPause() {
        #expect(PlayBar.role(.across, startY: 14, onTitle: true) == .skip)
        #expect(PlayBar.role(.across, startY: 30, onTitle: false) == .nothing)
    }

    @Test func upFromAnywhereOpensNowPlayingAndDownDoesNothing() {
        #expect(PlayBar.role(.up, startY: 2, onTitle: true) == .open)
        #expect(PlayBar.role(.up, startY: 30, onTitle: false) == .open)
        #expect(PlayBar.role(.down, startY: 2, onTitle: true) == .nothing)
    }

    @Test func aSkipOrASeekAcrossASongChangeDoesNothing() {
        #expect(PlayBar.atLetGo(.skip, began: 4, now: 4) == .skip)
        #expect(PlayBar.atLetGo(.skip, began: 4, now: 5) == .nothing)
        #expect(PlayBar.atLetGo(.seek, began: 4, now: 5) == .nothing)
        #expect(PlayBar.atLetGo(.seek, began: 4, now: nil) == .nothing)
    }

    @Test func openingNowPlayingDoesntDependOnTheSong() {
        #expect(PlayBar.atLetGo(.open, began: 4, now: 5) == .open)
        #expect(PlayBar.atLetGo(.nothing, began: 4, now: 4) == .nothing)
    }

    @Test func voiceOverMovesTheLineTenSeconds() {
        #expect(PlayBar.adjusted(increment: true, from: 30, length: 200) == 40)
        #expect(PlayBar.adjusted(increment: false, from: 30, length: 200) == 20)
    }

    @Test func voiceOverStopsAtTheSongsEnds() {
        #expect(PlayBar.adjusted(increment: true, from: 195, length: 200) == 200)
        #expect(PlayBar.adjusted(increment: false, from: 4, length: 200) == 0)
        #expect(PlayBar.adjusted(increment: true, from: 0, length: 0) == nil)
    }

    @Test func theBarsWords() {
        #expect(PlayerWords.barTime(shown: 83, length: 296) == "1:23 / 4:56")
        #expect(PlayerWords.nextSong == "Next song")
        #expect(PlayerWords.previousSong == "Previous song")
    }

    @Test func theSongBeforeIsTheQueuesWhereverTheSongIs() {
        let queue = UpNextQueue(tracks: simAlbum(3), index: 2)
        #expect(entryBefore(queue) == 1)
        #expect(entryBefore(UpNextQueue(tracks: simAlbum(3), index: 0)) == nil)
    }
}
