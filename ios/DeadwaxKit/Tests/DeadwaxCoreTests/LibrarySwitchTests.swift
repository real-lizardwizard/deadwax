import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's switch (Phase 4, slice 3b - phase4-library.md 2.8): the pages' order as this phone keeps it, Edit
/// order's moves, the page it opens on, what the Shuffle can do, the •••'s sections and words, and Find on Playlists -
/// and (slice 5, question 32) Songs: the fourth page, shown only without a library of your own.
@Suite struct LibrarySwitchTests {
    /// The ids, in order - outside a key path, for CI's older Swift.
    private static func ids(_ list: [Playlist]) -> [String] { list.map { (playlist: Playlist) -> String in playlist.id } }

    // MARK: the order

    @Test func theOrderIsReadWithCare() {
        let standard: [LibraryPage] = [.albums, .playlists, .artists, .songs]
        #expect(LibraryPages.standard == standard)
        #expect(LibraryPages.read(nil) == standard, "nothing kept: the standard order")
        #expect(LibraryPages.read("") == standard)
        #expect(LibraryPages.read("albums,playlists,artists,songs") == standard)
        #expect(LibraryPages.read("songs,artists,playlists,albums") == [.songs, .artists, .playlists, .albums])
        // (slice 4, question 23) an order saved before Artists was a page: Artists joins at its end - and Songs after it
        #expect(LibraryPages.read("albums,playlists") == standard)
        #expect(LibraryPages.read("playlists,albums") == [.playlists, .albums, .artists, .songs])
        #expect(LibraryPages.read("playlists") == [.playlists, .albums, .artists, .songs], "a page it doesn't name joins at the end")
        #expect(LibraryPages.read("albums") == standard)
        #expect(LibraryPages.read("artists") == [.artists, .albums, .playlists, .songs])
        #expect(LibraryPages.read("radio,playlists") == [.playlists, .albums, .artists, .songs], "a name it doesn't know left out")
        #expect(LibraryPages.read("playlists,playlists,albums") == [.playlists, .albums, .artists, .songs], "a page twice, once")
        #expect(LibraryPages.read(" playlists , albums ") == [.playlists, .albums, .artists, .songs], "spaces round a name")
        #expect(LibraryPages.read(",,playlists,,") == [.playlists, .albums, .artists, .songs])
        #expect(LibraryPages.read("Playlists,ALBUMS,Artists,SONGS") == standard, "names as written, never folded")
        #expect(LibraryPages.read("garbage\u{0}") == standard)
        #expect(LibraryPages.read("songs") == [.songs, .albums, .playlists, .artists])
    }

    /// (slice 5) An order this phone kept with three pages - slice 4's - is read back as it was, Songs joining at its end:
    /// nobody's order moves under them, and Songs is where a fourth page added since goes.
    @Test func aThreePageOrderKeptReadsBackWithSongsAtItsEnd() {
        let kept: [[LibraryPage]] = [[.albums, .playlists, .artists], [.playlists, .albums, .artists],
                                     [.artists, .albums, .playlists], [.playlists, .artists, .albums],
                                     [.artists, .playlists, .albums], [.albums, .artists, .playlists]]
        for three in kept {
            let saved = three.map { (page: LibraryPage) -> String in page.rawValue }.joined(separator: ",")
            #expect(LibraryPages.read(saved) == three + [.songs], "\(saved)")
            #expect(LibraryPages.shown(LibraryPages.read(saved), personal: true) == three, "\(saved): yours shows it as it was")
            #expect(LibraryPages.first(LibraryPages.shown(LibraryPages.read(saved), personal: false)) == three[0],
                    "\(saved): it opens where it did")
        }
    }

    @Test func theOrderIsWrittenAsItIsRead() {
        #expect(LibraryPages.saved([.playlists, .albums]) == "playlists,albums")
        #expect(LibraryPages.saved(LibraryPages.standard) == "albums,playlists,artists,songs")
        let orders: [[LibraryPage]] = [[.albums, .playlists, .artists, .songs], [.playlists, .albums, .artists, .songs],
                                       [.artists, .albums, .playlists, .songs], [.playlists, .artists, .albums, .songs],
                                       [.songs, .albums, .playlists, .artists], [.albums, .songs, .artists, .playlists]]
        for order in orders {
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
        #expect(LibraryPage.artists.title == "Artists" && LibraryPages.first([.artists, .albums, .playlists]) == .artists)
        #expect(LibraryPage.songs.title == "Songs" && LibraryPages.first([.songs, .albums, .playlists, .artists]) == .songs)
    }

    // MARK: (slice 5, question 32) Songs, shown without a library of your own

    @Test func songsIsAPageOnlyWithoutALibraryOfYourOwn() {
        let order: [LibraryPage] = [.albums, .songs, .playlists, .artists]
        #expect(LibraryPages.shown(order, personal: false) == order, "the collection is the Library: every page")
        #expect(LibraryPages.shown(order, personal: true) == [.albums, .playlists, .artists], "yours: All music > All songs")
        #expect(LibraryPages.shown([.songs, .artists, .albums, .playlists], personal: true) == [.artists, .albums, .playlists])
        #expect(LibraryPages.first(LibraryPages.shown([.songs, .artists, .albums, .playlists], personal: true)) == .artists,
                "Songs first in the order kept: yours opens on the next")
        #expect(LibraryPages.shown([], personal: true).isEmpty)
    }

    @Test func thePageShownIsOneTheSwitchShows() {
        let yours: [LibraryPage] = [.albums, .playlists, .artists]
        let all: [LibraryPage] = [.songs, .albums, .playlists, .artists]
        #expect(LibraryPages.showing(.playlists, in: yours) == .playlists)
        #expect(LibraryPages.showing(.songs, in: yours) == .albums, "Songs gone with a library of your own: the first")
        #expect(LibraryPages.showing(.songs, in: all) == .songs)
        #expect(LibraryPages.showing(nil, in: all) == .songs, "none yet: the first")
        #expect(LibraryPages.showing(nil, in: []) == .albums)
    }

    @Test func editOrderMovesOnlyThePagesShownAndSongsKeepsItsPlace() {
        let order: [LibraryPage] = [.albums, .songs, .playlists, .artists]
        // yours lists Albums, Playlists, Artists: Artists dragged to the top - Songs stays second of the order kept
        #expect(LibraryPages.moved(order, personal: true, from: IndexSet(integer: 2), to: 0)
                == [.artists, .songs, .albums, .playlists])
        #expect(LibraryPages.moved(order, personal: true, from: IndexSet(integer: 0), to: 3)
                == [.playlists, .songs, .artists, .albums])
        #expect(LibraryPages.moved(order, personal: true, from: IndexSet(integer: 1), to: 1) == order, "dropped where it was")
        #expect(LibraryPages.moved(order, personal: true, from: IndexSet(), to: 0) == order)
        // Songs last, or first, of the order kept: still there after any move of yours
        let last: [LibraryPage] = [.albums, .playlists, .artists, .songs]
        #expect(LibraryPages.moved(last, personal: true, from: IndexSet(integer: 0), to: 3) == [.playlists, .artists, .albums, .songs])
        let first: [LibraryPage] = [.songs, .albums, .playlists, .artists]
        #expect(LibraryPages.moved(first, personal: true, from: IndexSet(integer: 2), to: 0) == [.songs, .artists, .albums, .playlists])
        // without one: every page moves, Songs among them
        #expect(LibraryPages.moved(order, personal: false, from: IndexSet(integer: 1), to: 0) == [.songs, .albums, .playlists, .artists])
        #expect(LibraryPages.moved(order, personal: false, from: IndexSet(integer: 3), to: 1)
                == LibraryPages.moved(order, from: IndexSet(integer: 3), to: 1))
        // every move of yours, of every order: the pages shown are the List's move, Songs where it was
        let orders: [[LibraryPage]] = [[.albums, .songs, .playlists, .artists], [.songs, .albums, .playlists, .artists],
                                       [.albums, .playlists, .artists, .songs], [.albums, .playlists, .songs, .artists]]
        for each in orders {
            let shown = LibraryPages.shown(each, personal: true)
            for from in 0..<shown.count {
                for to in 0...shown.count {
                    let moved = LibraryPages.moved(each, personal: true, from: IndexSet(integer: from), to: to)
                    #expect(LibraryPages.shown(moved, personal: true) == LibraryPages.moved(shown, from: IndexSet(integer: from), to: to))
                    #expect(moved.firstIndex(of: .songs) == each.firstIndex(of: .songs), "\(each) \(from) -> \(to)")
                    #expect(Set(moved) == Set(LibraryPage.allCases) && moved.count == 4)
                }
            }
        }
    }

    @Test func threePagesMoveAsTheListDoes() {
        let order: [LibraryPage] = [.albums, .playlists, .artists]
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 2), to: 0) == [.artists, .albums, .playlists])
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 0), to: 3) == [.playlists, .artists, .albums])
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 0), to: 2) == [.playlists, .albums, .artists])
        #expect(LibraryPages.moved(order, from: IndexSet(integer: 2), to: 1) == [.albums, .artists, .playlists])
        #expect(LibraryPages.moved(order, from: IndexSet([0, 2]), to: 1) == [.albums, .artists, .playlists])
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
        let yours = LibraryMenu.sections(shuffle: .ready, page: .albums, grid: true, albumsPage: .albums, scope: .yours,
                                         personal: true, online: true)
        #expect(yours == [[.shuffle(.ready)], [.order(.albums), .layout(grid: true)], [.downloaded, .allMusic],
                          [.refresh, .editOrder]])
        let store = LibraryMenu.sections(shuffle: .gettingReady, page: .albums, grid: false, albumsPage: .albums,
                                         scope: .store, personal: false, online: true)
        #expect(store == [[.shuffle(.gettingReady)], [.order(.albums), .layout(grid: false)], [.downloaded],
                          [.refresh, .editOrder]], "no All music without a library")
        let offline = LibraryMenu.sections(shuffle: .downloads, page: .albums, grid: true, albumsPage: .downloaded,
                                           scope: .yours, personal: true, online: false)
        #expect(offline == [[.shuffle(.downloads)], [.order(.albums), .layout(grid: true)], [.albums(.yours)],
                            [.refresh, .editOrder]], "offline: the way back in Downloaded's place, no All music")
        let back = LibraryMenu.sections(shuffle: .ready, page: .albums, grid: true, albumsPage: .downloaded, scope: .yours,
                                        personal: true, online: true)
        #expect(back[2] == [.albums(.yours), .allMusic], "back online with the page still Downloaded")
        for nothing in [ShuffleCan.nothingHere, .none] {
            let sections = LibraryMenu.sections(shuffle: nothing, page: .albums, grid: true, albumsPage: .albums,
                                                scope: .yours, personal: true, online: true)
            #expect(sections.first == [.order(.albums), .layout(grid: true)], "nothing to shuffle: no Shuffle item")
        }
        // (slice 4, question 26) each page's own: Artists' order alone - and (the squared look) Playlists' New playlist,
        // the bar's + until then, chosen only while deadwax can be reached
        let artists = LibraryMenu.sections(shuffle: .ready, page: .artists, grid: true, albumsPage: .albums,
                                           scope: .yours, personal: true, online: true)
        #expect(artists == [[.shuffle(.ready)], [.order(.artists)], [.downloaded, .allMusic], [.refresh, .editOrder]])
        let playlists = LibraryMenu.sections(shuffle: .ready, page: .playlists, grid: true, albumsPage: .albums,
                                             scope: .yours, personal: true, online: true)
        #expect(playlists == [[.shuffle(.ready)], [.newPlaylist(online: true)], [.downloaded, .allMusic],
                              [.refresh, .editOrder]])
        let away = LibraryMenu.sections(shuffle: .downloads, page: .playlists, grid: true, albumsPage: .downloaded,
                                        scope: .yours, personal: true, online: false)
        #expect(away[1] == [.newPlaylist(online: false)], "offline: New playlist there, dimmed")
        // (slice 5) Songs has neither an order nor a layout: Navidrome's order is its one order
        let songs = LibraryMenu.sections(shuffle: .ready, page: .songs, grid: true, albumsPage: .albums,
                                         scope: .store, personal: false, online: true)
        #expect(songs == [[.shuffle(.ready)], [.downloaded], [.refresh, .editOrder]])
        #expect(LibraryMenu.allMusic == [.albums(.store), .artists(.store), .allSongs])
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
        #expect(LibraryMenuItem.albums(.store).words(personal: true) == "All albums")
        #expect(LibraryMenuItem.artists(.store).words(personal: true) == "All artists")
        #expect(LibraryMenuItem.artists(.store).words(personal: false) == "Artists")
        #expect(LibraryMenuItem.allSongs.words(personal: true) == "All songs")
        #expect(LibraryMenuItem.allSongs.words(personal: false) == "Songs")
        #expect(LibraryMenuItem.order(.albums).words(personal: true) == "Album order")
        #expect(LibraryMenuItem.order(.artists).words(personal: true) == "Artist order")
        #expect(LibraryMenuItem.layout(grid: true).words(personal: true) == "Show as list")
        #expect(LibraryMenuItem.layout(grid: false).words(personal: true) == "Show as grid")
        #expect(LibraryMenuItem.refresh.words(personal: true) == "Refresh")
        #expect(LibraryMenuItem.editOrder.words(personal: true) == "Edit order")
        #expect(LibraryMenuItem.newPlaylist(online: true).words(personal: true) == "New playlist")
        #expect(LibraryMenuItem.newPlaylist(online: false).words(personal: false) == PlaylistWords.newPlaylist)
        #expect(LibraryMenuItem.newPlaylist(online: true).enabled)
        #expect(!LibraryMenuItem.newPlaylist(online: false).enabled, "not while deadwax can't be reached")
        #expect(LibrarySwitchWords.cancelFind == "Cancel")
        let enabled = [LibraryMenuItem.shuffle(.ready), .shuffle(.downloads), .shuffle(.gettingReady), .shuffle(.failed("x")),
                       .downloaded, .refresh, .order(.artists), .layout(grid: true), .artists(.store), .allSongs].map(\.enabled)
        #expect(enabled == [true, true, false, false, true, true, true, true, true, true])
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
