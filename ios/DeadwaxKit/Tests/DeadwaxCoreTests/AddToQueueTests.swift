import Foundation
import Testing
@testable import DeadwaxCore

/// Add to Queue (16 Nov; notes/ios.md "Add to Queue: the swipe, and the menus' one item"): its words, what it does, the
/// one rule that offers it on a ••• and on a row's swipe alike, its purple, and the hand-drawn swipe's numbers. The
/// order it adds in is AddToQueueOrderTests' (QueueControllerTests.swift); the phone's departure from the web's two
/// items is ScreenQueueTests'.
@Suite struct AddToQueueTests {
    private static let songs = [Song(id: "a", title: "Mysterons", albumId: "al-1"),
                                Song(id: "b", title: "Sour Times", albumId: "al-1"),
                                Song(id: "c", title: "Strangers", albumId: "al-1")]
    private static let album = Album(id: "al-1", name: "Dummy", song: songs)

    @Test func itsWordsAndWhatItDoes() {
        #expect(AddToQueue.words == "Add to Queue", "title case, as the menus' other words")
        #expect(AddToQueue.choice == .last, "the web's Play Last: after the songs already added")
        #expect(AddToQueue.symbol == DownloadWords.playLastSymbol)
        #expect(AddToQueue.symbol == "text.line.last.and.arrowtriangle.forward")
        #expect(Normalization.addedWith == AddToQueue.words)
    }

    @Test func itIsPlayLastsCallLevelAndNotice() {
        let one = QueuePick.song(Self.songs[1], of: Self.album)
        let queued = one.choose(AddToQueue.choice, setting: .auto)
        #expect(queued?.choice == .last && queued?.level == .track && queued?.tracks.map(\.id) == ["b"])
        #expect(queued?.remember == ["al-1"])
        let whole = QueuePick.album(Self.album)
        #expect(whole?.choose(AddToQueue.choice, setting: .auto)?.level == .album, "an album's ••• as the album")
        //? the menu's notice for it, unchanged: the web's Play Last's line
        #expect(one.notice(AddToQueue.choice, started: false) == "Added to Queue: Sour Times")
        #expect(one.notice(AddToQueue.choice, started: true) == nil, "the music started: the mini player says so")
    }

    @Test func onlineEveryPickIsOfferedWhole() {
        let whole = QueuePick.album(Self.album)!
        let none: (String) -> Bool = { _ in false }
        let offered = AddToQueue.pick(whole, online: true, gone: false, here: none)
        #expect(offered?.tracks.map(\.id) == ["a", "b", "c"], "nothing on the phone needed while deadwax answers")
        #expect(offered?.label == "Dummy" && offered?.albumIds == ["al-1"] && offered?.queuedAs == .album)
        let one = QueuePick.song(Self.songs[0], of: Self.album)
        #expect(AddToQueue.pick(one, online: true, gone: false, here: none)?.tracks.map(\.id) == ["a"])
    }

    @Test func offlineOrGoneOnlyWhatIsOnThisPhone() {
        let whole = QueuePick.album(Self.album)!
        let here: (String) -> Bool = { $0 != "b" }
        for (online, gone) in [(false, false), (false, true), (true, true)] {
            let offered = AddToQueue.pick(whole, online: online, gone: gone, here: here)
            #expect(offered?.tracks.map(\.id) == ["a", "c"], "online \(online), gone \(gone): the songs here, in order")
            #expect(offered?.label == "Dummy" && offered?.queuedAs == .album && offered?.albumIds == ["al-1"])
        }
        // a row's one song, not here: no swipe, and no item on its •••
        let notHere = QueuePick.song(Self.songs[1], of: Self.album)
        #expect(AddToQueue.pick(notHere, online: false, gone: false, here: here) == nil)
        #expect(AddToQueue.pick(notHere, online: true, gone: true, here: here) == nil)
        #expect(AddToQueue.pick(notHere, online: true, gone: false, here: here) != nil)
        // nothing of an album here
        #expect(AddToQueue.pick(whole, online: false, gone: false) { _ in false } == nil)
    }

    @Test func noSongsIsNeverOffered() {
        let empty = QueuePick<Song>(label: "Nothing", tracks: [], albumIds: [])
        #expect(AddToQueue.pick(empty, online: true, gone: false) { _ in true } == nil)
        #expect(AddToQueue.pick(empty, online: false, gone: false) { _ in true } == nil)
    }

    @Test func thePurpleReadsUnderItsWhiteSymbol() {
        #expect(AddToQueue.fill == PrimaryButton.bottom && AddToQueue.fill == DeckRGBA(0x8A, 0x2E, 0xE0))
        #expect(AddToQueue.glyph == DeckRGBA(255, 255, 255))
        let ratio = Contrast.ratio(AddToQueue.glyph, AddToQueue.fill)
        #expect(ratio >= 4.5, "AA, even for a symbol: \(ratio)")
        //? the app's tint, #C084FC, under white: what James couldn't see on Play - not the swipe's
        #expect(Contrast.ratio(AddToQueue.glyph, DeckRGBA(0xC0, 0x84, 0xFC)) < 3)
    }
}

/// The hand-drawn swipe (Songs, Search): when a pan is the row's, where the row stands, and what letting go does.
@Suite struct QueueSwipeTests {
    @Test func aPanIsTheRowsOnlySideways() {
        #expect(QueueSwipe.begins(dx: 12, dy: 3, startX: 200, open: false), "rightwards: the swipe")
        #expect(!QueueSwipe.begins(dx: 3, dy: 12, startX: 200, open: false), "down: the list's scroll")
        #expect(!QueueSwipe.begins(dx: -3, dy: -12, startX: 200, open: true), "up, open or not: the scroll")
        #expect(!QueueSwipe.begins(dx: 10, dy: 10, startX: 200, open: false), "a diagonal is the scroll's")
        #expect(!QueueSwipe.begins(dx: -12, dy: 2, startX: 200, open: false), "leftwards on a shut row: nothing to shut")
        #expect(QueueSwipe.begins(dx: -12, dy: 2, startX: 200, open: true), "leftwards on an open row shuts it")
    }

    @Test func theScreensEdgeIsTheBackSwipes() {
        #expect(QueueSwipe.backEdge == 24)
        #expect(!QueueSwipe.begins(dx: 30, dy: 0, startX: 0, open: false))
        #expect(!QueueSwipe.begins(dx: 30, dy: 0, startX: 23.9, open: false))
        #expect(QueueSwipe.begins(dx: 30, dy: 0, startX: 24, open: false))
        #expect(!QueueSwipe.begins(dx: 30, dy: 0, startX: 10, open: true), "open or not")
    }

    @Test func theRowFollowsTheFingerRightwardsOnly() {
        #expect(QueueSwipe.moved(40, from: 0, width: 360) == 40)
        #expect(QueueSwipe.moved(-40, from: 0, width: 360) == 0, "never left of shut")
        #expect(QueueSwipe.moved(-30, from: QueueSwipe.button, width: 360) == 44, "from open, back towards shut")
        #expect(QueueSwipe.moved(-200, from: QueueSwipe.button, width: 360) == 0)
        #expect(QueueSwipe.moved(500, from: 0, width: 360) == 360, "never past the row")
        #expect(QueueSwipe.moved(10, from: 0, width: 0) == 0, "a row not measured yet stays shut")
    }

    @Test func theFullSwipeIsHalfTheRowNeverBeforeTheButtonIsWellOut() {
        #expect(QueueSwipe.button == 74)
        #expect(QueueSwipe.fullAt(width: 360) == 180)
        #expect(QueueSwipe.fullAt(width: 393) == 196.5)
        #expect(QueueSwipe.fullAt(width: 200) == 148, "a narrow row: twice the button")
        #expect(!QueueSwipe.full(179.9, width: 360) && QueueSwipe.full(180, width: 360))
    }

    @Test func lettingGo() {
        let width = 360.0
        #expect(QueueSwipe.release(at: 180, velocity: 0, width: width) == .add, "past the full swipe: added")
        #expect(QueueSwipe.release(at: 250, velocity: -900, width: width) == .add, "past it, whatever the fling")
        #expect(QueueSwipe.release(at: 37, velocity: 0, width: width) == .open, "the button half out: it stands open")
        #expect(QueueSwipe.release(at: 120, velocity: 0, width: width) == .open)
        #expect(QueueSwipe.release(at: 36.9, velocity: 0, width: width) == .shut, "less: it shuts")
        #expect(QueueSwipe.release(at: 20, velocity: 600, width: width) == .open, "flung right: it opens")
        #expect(QueueSwipe.release(at: 120, velocity: -600, width: width) == .shut, "flung left: it shuts")
        #expect(QueueSwipe.release(at: 0, velocity: 900, width: width) == .shut, "nothing out")
        #expect(QueueSwipe.release(at: 179, velocity: 2000, width: width) == .open, "a fling never adds: only the full swipe")
        // the fling's bounds, exactly: 500 pt/s is a fling either way, a hair under it isn't
        #expect(QueueSwipe.fling == 500)
        #expect(QueueSwipe.release(at: 20, velocity: 500, width: width) == .open, "flung right at exactly 500: it opens")
        #expect(QueueSwipe.release(at: 20, velocity: 499.9, width: width) == .shut, "just under: the button's half decides")
        #expect(QueueSwipe.release(at: 120, velocity: -500, width: width) == .shut, "flung left at exactly 500: it shuts")
        #expect(QueueSwipe.release(at: 120, velocity: -499.9, width: width) == .open, "just under: the button's half decides")
    }
}
