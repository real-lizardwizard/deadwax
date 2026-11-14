import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's switch (Phase 4, slice 3b - phase4-library.md 2.8): the pages' order as this phone keeps it, Edit
/// order's moves, the page it opens on, what the Shuffle can do, the •••'s sections and words, and Find on Playlists.
@Suite struct LibrarySwitchTests {
    /// The ids, in order - outside a key path, for CI's older Swift.
    private static func ids(_ list: [Playlist]) -> [String] { list.map { (playlist: Playlist) -> String in playlist.id } }

    // MARK: the order

    @Test func theOrderIsReadWithCare() {
        let standard: [LibraryPage] = [.albums, .playlists]
        #expect(LibraryPages.standard == standard)
        #expect(LibraryPages.read(nil) == standard, "nothing kept: the standard order")
        #expect(LibraryPages.read("") == standard)
        #expect(LibraryPages.read("albums,playlists") == standard)
        #expect(LibraryPages.read("playlists,albums") == [.playlists, .albums])
        #expect(LibraryPages.read("playlists") == [.playlists, .albums], "a page it doesn't name joins at the end")
        #expect(LibraryPages.read("albums") == standard)
        #expect(LibraryPages.read("songs,playlists") == [.playlists, .albums], "a name it doesn't know left out")
        #expect(LibraryPages.read("playlists,playlists,albums") == [.playlists, .albums], "a page twice, once")
        #expect(LibraryPages.read(" playlists , albums ") == [.playlists, .albums], "spaces round a name")
        #expect(LibraryPages.read(",,playlists,,") == [.playlists, .albums])
        #expect(LibraryPages.read("Playlists,ALBUMS") == standard, "names as written, never folded")
        #expect(LibraryPages.read("garbage\u{0}") == standard)
    }

    @Test func theOrderIsWrittenAsItIsRead() {
        #expect(LibraryPages.saved([.playlists, .albums]) == "playlists,albums")
        #expect(LibraryPages.saved(LibraryPages.standard) == "albums,playlists")
        for order in [[LibraryPage.albums, .playlists], [.playlists, .albums]] {
            #expect(LibraryPages.read(LibraryPages.saved(order)) == order)
        }
        #expect(LibraryPages.storageKey == "deadwax-library-pages")
    }

    @Test func editOrdersMovesAreTheLists() {
        let order: [LibraryPage] = [.albums, .playlists]
        // a List's onMove: the second dragged above the first, the first below the second
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 1), to: 0) == [.playlists, .albums])
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 0), to: 2) == [.playlists, .albums])
        // dropped where it was: nothing moves
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 0), to: 0) == order)
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 0), to: 1) == order)
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 1), to: 2) == order)
        // nothing, or out of range: the order as it was
        #expect(LibraryPages.moved(order, from: IndexSet(), to: 0) == order)
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 5), to: 0) == order)
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 1), to: 9) == order)
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 1), to: -3) == [.playlists, .albums])
    }

    @Test func theLibraryOpensOnTheFirstPage() {
        #expect(LibraryPages.first([.playlists, .albums]) == .playlists)
        #expect(LibraryPages.first(LibraryPages.read(nil)) == .albums)
        #expect(LibraryPages.first([]) == .albums)
        #expect(LibraryPage.albums.title == "Albums" && LibraryPage.playlists.title == "Playlists")
    }

    // MARK: what the Shuffle can do

    @Test func whatTheShuffleCanDo() {
        #expect(ShuffleCan.of(online: true, ready: true, empty: false, failed: nil, songsHere: 0) == .ready)
        #expect(ShuffleCan.of(online: true, ready: false, empty: false, failed: nil, songsHere: 9) == .gettingReady)
        #expect(ShuffleCan.of(online: true, ready: false, empty: false, failed: "why", songsHere: 9) == .failed("why"))
        #expect(ShuffleCan.of(online: true, ready: false, empty: true, failed: nil, songsHere: 9) == .none,
                "a library with no songs: no Shuffle")
        #expect(ShuffleCan.of(online: true, ready: true, empty: false, failed: "old", songsHere: 0) == .ready,
                "a page in hand plays, whatever failed before")
        #expect(ShuffleCan.of(online: false, ready: true, empty: false, failed: nil, songsHere: 3) == .downloads)
        #expect(ShuffleCan.of(online: false, ready: true, empty: false, failed: nil, songsHere: 0) == .nothingHere)
        #expect(ShuffleCan.of(online: false, ready: false, empty: true, failed: "x", songsHere: 1) == .downloads)
        let starts = [ShuffleCan.ready, .downloads, .gettingReady, .failed("x"), .nothingHere, .none].map(\.starts)
        #expect(starts == [true, true, false, false, false, false])
    }

    // MARK: the •••

    @Test func theLibrarysMenu() {
        let yours = LibraryMenu.sections(shuffle: .ready, albumsPage: .albums, scope: .yours, personal: true, online: true)
        #expect(yours == [[.shuffle(.ready)], [.downloaded, .allMusic], [.refresh, .editOrder]])
        let store = LibraryMenu.sections(shuffle: .gettingReady, albumsPage: .albums, scope: .store, personal: false,
                                         online: true)
        #expect(store == [[.shuffle(.gettingReady)], [.downloaded], [.refresh, .editOrder]], "no All music without a library")
        let offline = LibraryMenu.sections(shuffle: .downloads, albumsPage: .downloaded, scope: .yours, personal: true,
                                           online: false)
        #expect(offline == [[.shuffle(.downloads)], [.albums(.yours)], [.refresh, .editOrder]],
                "offline: the way back in Downloaded's place, no All music")
        let back = LibraryMenu.sections(shuffle: .ready, albumsPage: .downloaded, scope: .yours, personal: true, online: true)
        #expect(back == [[.shuffle(.ready)], [.albums(.yours), .allMusic], [.refresh, .editOrder]],
                "back online with the page still Downloaded")
        for nothing in [ShuffleCan.nothingHere, .none] {
            let sections = LibraryMenu.sections(shuffle: nothing, albumsPage: .albums, scope: .yours, personal: true,
                                                online: true)
            #expect(sections.first == [.downloaded, .allMusic], "nothing to shuffle: no Shuffle item")
        }
    }

    @Test func theMenusWords() {
        #expect(LibraryMenuItem.shuffle(.ready).words(personal: true) == "Shuffle")
        #expect(LibraryMenuItem.shuffle(.gettingReady).words(personal: true) == "Getting ready\u{2026}")
        #expect(LibraryMenuItem.shuffle(.failed("Your library is too big to shuffle here")).words(personal: true)
                == "Your library is too big to shuffle here")
        #expect(LibraryMenuItem.shuffle(.downloads).words(personal: true) == "Shuffle downloads")
        #expect(LibraryMenuItem.downloaded.words(personal: true) == "Downloaded")
        #expect(LibraryMenuItem.albums(.yours).words(personal: true) == "Your albums")
        #expect(LibraryMenuItem.albums(.store).words(personal: false) == "Albums")
        #expect(LibraryMenuItem.allMusic.words(personal: true) == "All music")
        #expect(LibraryMenuItem.refresh.words(personal: true) == "Refresh")
        #expect(LibraryMenuItem.editOrder.words(personal: true) == "Edit order")
        let enabled = [LibraryMenuItem.shuffle(.ready), .shuffle(.downloads), .shuffle(.gettingReady), .shuffle(.failed("x")),
                       .downloaded, .refresh].map(\.enabled)
        #expect(enabled == [true, true, false, false, true, true])
        #expect(LibrarySwitchWords.more == "More for the Library")
        #expect(LibrarySwitchWords.orderFooter == "Drag the pages into the order you want. The Library opens on the first.")
    }

    // MARK: Find on Playlists

    @Test func findKeepsThePlaylistsWhoseNameHoldsEveryWord() {
        let list = [Playlist(id: "1", name: "Late night"), Playlist(id: "2", name: "Café mornings"),
                    Playlist(id: "3", name: "NIGHT drive"), Playlist(id: "4", name: "Beatles")]
        #expect(Self.ids(PlaylistRules.found(list, typed: "")) == ["1", "2", "3", "4"])
        #expect(Self.ids(PlaylistRules.found(list, typed: "   ")) == ["1", "2", "3", "4"], "spaces are nothing")
        #expect(Self.ids(PlaylistRules.found(list, typed: "night")) == ["1", "3"], "case folded, in the list's order")
        #expect(Self.ids(PlaylistRules.found(list, typed: "night late")) == ["1"], "every word, any order")
        #expect(Self.ids(PlaylistRules.found(list, typed: "cafe")) == ["2"], "accents folded")
        #expect(Self.ids(PlaylistRules.found(list, typed: "eat")) == ["4"], "anywhere in a word")
        #expect(PlaylistRules.found(list, typed: "dumy").isEmpty)
        #expect(LibrarySwitchWords.noPlaylistMatch(" dumy ") == "No playlists match \u{201C}dumy\u{201D}.")
    }
}
