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

    @Test func theMenusWords() {
        #expect(LibraryMenuItem.shuffle(.ready).words(personal: true) == "Shuffle")
        #expect(LibraryMenuItem.shuffle(.gettingReady).words(personal: true) == "Getting ready\u{2026}")
        #expect(LibraryMenuItem.shuffle(.failed("Your library is too big to shuffle here")).words(personal: true)
                == "Your library is too big to shuffle here")
        #expect(LibraryMenuItem.shuffle(.downloads).words(personal: true) == "Shuffle downloads")
        #expect(LibraryMenuItem.albums(.yours).words(personal: true) == "Your albums")
        #expect(LibraryMenuItem.albums(.store).words(personal: false) == "Albums")
        #expect(LibraryMenuItem.albums(.store).words(personal: true) == "All albums")
        #expect(LibraryMenuItem.refresh.words(personal: true) == "Refresh")
        #expect(LibraryMenuItem.editOrder.words(personal: true) == "Edit order")
        // (R2b) Downloaded is the •••'s again, in the words the old ••• and R2's strip had
        #expect(LibraryMenuItem.downloaded.words(personal: true) == "Downloaded")
        #expect(LibraryMenuItem.downloaded.words(personal: false) == DownloadWords.downloadedTitle)
        // (R2's review) the old •••'s items went with it; their words live on where the items went
        #expect(DownloadWords.downloadedTitle == "Downloaded")
        #expect(LibraryWords.allMusic == "All music")
        #expect(ArtistWords.title(.store, personal: true) == "All artists" && ArtistWords.title(.store, personal: false) == "Artists")
        #expect(SongWords.title(personal: true) == "All songs" && SongWords.title(personal: false) == "Songs")
        #expect(LibraryWords.sortLabel == "Album order" && ArtistWords.sortLabel == "Artist order")
        #expect(LibrarySwitchWords.showAsList == "Show as list" && LibrarySwitchWords.showAsGrid == "Show as grid")
        #expect(PlaylistWords.newPlaylist == "New playlist")
        #expect(LibrarySwitchWords.cancelFind == "Cancel")
        let enabled = [LibraryMenuItem.shuffle(.ready), .shuffle(.downloads), .shuffle(.gettingReady), .shuffle(.failed("x")),
                       .albums(.yours), .downloaded, .refresh, .editOrder].map(\.enabled)
        #expect(enabled == [true, true, false, false, true, true, true, true])
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

    // MARK: the redesign's top (slice R2, James's answer 1 of 25 Nov)

    @Test func songsAreNeverBesideYourOwnAlbums() {
        let standard = LibraryPages.standard
        let kept: [LibraryPage] = [.songs, .playlists, .artists, .albums]
        for order in [standard, kept] {
            // Yours, and with no library of your own: the pages as they were
            #expect(LibraryPages.shown(order, personal: true, side: .yours) == LibraryPages.shown(order, personal: true))
            #expect(!LibraryPages.shown(order, personal: true, side: .yours).contains(.songs))
            for side in LibrarySide.allCases {
                #expect(LibraryPages.shown(order, personal: false, side: side) == order, "one side, every page")
            }
            // All: All music's pages, in the order kept - Songs among them, no Playlists
            let all = LibraryPages.shown(order, personal: true, side: .all)
            #expect(all == order.filter { (page: LibraryPage) -> Bool in page != .playlists })
            #expect(!all.contains(.playlists) && all.contains(.songs))
        }
        #expect(LibraryPages.allMusic == [.albums, .artists, .songs])
        #expect(LibraryPages.shown(kept, personal: true, side: .all) == [.songs, .artists, .albums])
    }

    @Test func yoursOrAllShowsWhereAllMusicWas() {
        for chosen in LibrarySide.allCases {
            #expect(LibraryPages.sides(personal: true, scope: .yours, online: true, chosen: chosen))
            #expect(!LibraryPages.sides(personal: false, scope: .store, online: true, chosen: chosen),
                    "no library of your own: no switch")
            #expect(!LibraryPages.sides(personal: true, scope: .store, online: true, chosen: chosen))
            #expect(!LibraryPages.sides(personal: false, scope: .store, online: false, chosen: chosen))
        }
        #expect(LibraryPages.side(.all, sides: true) == .all)
        #expect(LibraryPages.side(.all, sides: false) == .yours, "no switch: Yours")
        #expect(LibraryPages.side(.yours, sides: true) == .yours)
        #expect(LibrarySide.yours.scope == .yours && LibrarySide.all.scope == .store)
        #expect(LibrarySide.allCases.map { (side: LibrarySide) -> String in side.title } == ["Yours", "All"])
        // the •••'s All music is the switch's now: the top's ••• has none
        for scope in [AlbumScope.yours, .store] {
            for list in [LibraryRootList.albums, .downloaded] {
                let items = LibraryMenu.topSections(shuffle: .ready, albumsPage: list, scope: scope).joined()
                #expect(!items.contains(.albums(.store)) || scope == .store, "All albums is All's Albums page")
            }
        }
    }

    /// (R2's review, finding 1) deadwax dropping out never turns a chosen All back into Yours on screen: the switch is
    /// put away offline only while Yours is the side shown.
    @Test func aChosenAllStaysAllWhenDeadwaxDropsOut() {
        let away = LibraryPages.sides(personal: true, scope: .yours, online: false, chosen: .all)
        #expect(away, "offline on All: the switch stays, and All with it")
        #expect(LibraryPages.side(.all, sides: away) == .all)
        let yours = LibraryPages.sides(personal: true, scope: .yours, online: false, chosen: .yours)
        #expect(!yours, "offline on Yours: no switch, nothing to offer that can't be asked for")
        #expect(LibraryPages.side(.yours, sides: yours) == .yours)
        // and the pages shown don't move under him: All's pages, Songs among them, offline as online
        let order = LibraryPages.standard
        #expect(LibraryPages.shown(order, personal: true, side: LibraryPages.side(.all, sides: away))
                == LibraryPages.shown(order, personal: true, side: .all))
        #expect(LibraryPages.showing(.songs, in: LibraryPages.shown(order, personal: true, side: .all)) == .songs,
                "All's Songs stays Songs")
    }

    /// (R2's review, findings 1 and 4) Each side's Albums list, Artists scope and Shuffle: All's are the collection's,
    /// whatever Yours' root is - never Downloaded, which stands in for Yours' albums alone.
    @Test func eachSidesAlbumsArtistsAndShuffle() {
        for root in [AlbumList.scope(.yours), .scope(.store), .downloaded] {
            #expect(LibrarySide.yours.albums(root) == root, "Yours: the root's list, Downloaded included")
            #expect(LibrarySide.all.albums(root) == .scope(.store), "All: the collection's, never Downloaded")
        }
        #expect(LibrarySide.yours.artistsScope == nil, "Yours: the page's own scope")
        #expect(LibrarySide.all.artistsScope == .store)
        #expect(LibrarySide.yours.shuffle == .library)
        #expect(LibrarySide.all.shuffle == .allSongs)
        #expect(LibrarySide.all.shuffle.scope(library: .yours) == .store, "All's Shuffle is the collection's")
    }

    /// (R2b) The ••• is Shuffle, Downloaded, Refresh and Edit order (James's drawing of 25 Nov) - Downloaded back from
    /// R2's strip, and, while the Albums page is Downloaded itself, the way back to the albums in its place, as the old
    /// ••• had them (5123bab3's "places": `albumsPage == .downloaded ? .albums(scope) : .downloaded`).
    @Test func theTopsMoreIsShuffleDownloadedRefreshAndEditOrder() {
        #expect(LibraryMenu.topSections(shuffle: .ready, albumsPage: .albums, scope: .yours)
                == [[.shuffle(.ready)], [.downloaded], [.refresh, .editOrder]])
        #expect(LibraryMenu.topSections(shuffle: .none, albumsPage: .albums, scope: .store)
                == [[.downloaded], [.refresh, .editOrder]])
        #expect(LibraryMenu.topSections(shuffle: .nothingHere, albumsPage: .downloaded, scope: .yours)
                == [[.albums(.yours)], [.refresh, .editOrder]], "the way back to the albums while they are Downloaded")
        #expect(LibraryMenu.topSections(shuffle: .gettingReady, albumsPage: .downloaded, scope: .store)
                == [[.shuffle(.gettingReady)], [.albums(.store)], [.refresh, .editOrder]])
        // Downloaded and the way back are never both there, and one of them always is
        for shuffle in [ShuffleCan.ready, .none, .downloads] {
            for list in [LibraryRootList.albums, .downloaded] {
                let items = LibraryMenu.topSections(shuffle: shuffle, albumsPage: list, scope: .yours).joined()
                #expect(items.contains(.downloaded) == (list == .albums))
                #expect(items.contains(.albums(.yours)) == (list == .downloaded))
            }
        }
        // no order, layout or New playlist - each page's line's: (its review) LibraryMenuItem has no such items since
        // the old ••• went
        #expect(LibrarySwitchWords.grid == "Grid" && LibrarySwitchWords.list == "List")
    }

    /// (R2b) Grid and List are on Albums' line alone, as they were Albums' own in the old •••.
    @Test func gridAndListAreOnAlbumsLineAlone() {
        #expect(LibraryPage.allCases.filter { (page: LibraryPage) -> Bool in LibraryLine.layouts(on: page) } == [.albums])
    }

    /// (R2b) The row holds the switch where its equal segments fit between the circles - 375 pt wide, room for 251 -
    /// and folds it under them where they don't, into the page's width less the circles' sides.
    @Test func theRowFoldsTheSwitchOnlyWhereItCantHoldIt() {
        #expect(LibraryTopFit.room(width: 375) == 375 - 2 * (16 + 34 + 12))
        #expect(LibraryTopFit.room(width: 375) == 251)
        #expect(LibraryTopFit.foldedRoom(width: 375) == 343)
        #expect(!LibraryTopFit.folds(needs: 251, width: 375), "exactly the room: held")
        #expect(LibraryTopFit.folds(needs: 251.5, width: 375))
        #expect(!LibraryTopFit.folds(needs: 300, width: 440))
        #expect(LibraryTopFit.foldedRoom(width: 320) == 288)
        // the row as LibraryTopRow asks for it: given a width, the switch offered the room beside the circles or the
        // page's; asked its own, as wide as the switch needs beside them - never folded
        #expect(LibraryTopFit.row(needs: 240, width: 375) == LibraryTopFit.Row(width: 375, folds: false, room: 251))
        #expect(LibraryTopFit.row(needs: 251.5, width: 375) == LibraryTopFit.Row(width: 375, folds: true, room: 343))
        #expect(LibraryTopFit.row(needs: 300, width: nil) == LibraryTopFit.Row(width: 424, folds: false, room: 300))
    }

    /// (R2b, its review) The row's views where James drew them: Find's circle at the leading edge and the •••'s at the
    /// trailing one - each centred where its 34 pt face is, 16 in - and the switch between them, or across the page
    /// under them, folded.
    @Test func theRowPutsFindLeadingTheMoreTrailingAndTheSwitchBetween() {
        let target = LookSize(width: 44, height: 44)
        let well = LookSize(width: 251, height: 38)
        let need = LookSize(width: 240, height: 38)
        let row = LibraryTopFit.place(LibraryTopFit.row(needs: 240, width: 375), find: target, switcher: well,
                                      more: target, need: need)
        // Find's face 16 in from the leading edge, its target reaching 5 past it; the •••'s as far in from the trailing
        #expect(row.find == LookBox(x: 11, y: 4, width: 44, height: 44))
        #expect(row.more == LookBox(x: 320, y: 4, width: 44, height: 44))
        #expect(row.find.midX == 16 + 17 && row.more.midX == 375 - 16 - 17)
        // the switch in the room between the faces, 12 from each: 16 + 34 + 12 = 62 to 375 - 62 = 313
        #expect(row.switcher == LookBox(x: 62, y: 7, width: 251, height: 38))
        #expect(row.switcher.maxX == 375 - 62)
        // its need on it, at its own size; all of them centred in the row's 52
        #expect(row.need == LookBox(x: 67.5, y: 7, width: 240, height: 38))
        #expect(row.find.midY == 26 && row.switcher.midY == 26 && row.more.midY == 26)
        #expect(row.width == 375 && row.height == 52)
        // a switch taller than the row (the larger text sizes) makes the row as tall, everything centred in it
        let tall = LibraryTopFit.place(LibraryTopFit.row(needs: 240, width: 375), find: target,
                                       switcher: LookSize(width: 251, height: 60), more: target, need: need)
        #expect(tall.height == 60 && tall.find.midY == 30 && tall.switcher.y == 0)

        // folded (four pages at xLarge on a 375 pt phone): the circles where they were, the switch under them across the
        // page less the circles' sides, the room under it the row would give it beside them
        let wide = LookSize(width: 343, height: 42)
        let folded = LibraryTopFit.place(LibraryTopFit.row(needs: 300, width: 375), find: target, switcher: wide,
                                         more: target, need: LookSize(width: 300, height: 42))
        #expect(folded.find == row.find && folded.more == row.more)
        #expect(folded.switcher == LookBox(x: 16, y: 52, width: 343, height: 42))
        #expect(folded.need == LookBox(x: 37.5, y: 52, width: 300, height: 42))
        #expect(folded.height == 52 + 42 + 5)
        // on a wider phone the same switch fits beside the circles again, and nothing is under them
        let roomy = LibraryTopFit.place(LibraryTopFit.row(needs: 300, width: 440), find: target,
                                        switcher: LookSize(width: 316, height: 42), more: target, need: need)
        #expect(roomy.switcher.y == 5 && roomy.height == 52 && roomy.more.maxX == 440 - 11)
    }

    /// (R2b, its review) VoiceOver reads the row as it is drawn: Find, the switch, the ••• on one row - and, folded,
    /// the two circles on the row before the switch under them.
    @Test func voiceOverReadsTheRowAsItIsDrawn() {
        #expect(LibraryTopFit.reading(folds: false) == [.find, .switcher, .more])
        #expect(LibraryTopFit.reading(folds: true) == [.find, .more, .switcher])
        let parts: [LibraryTopFit.Part] = [.find, .switcher, .more]
        for folds in [false, true] {
            // higher is sooner: the priorities read in the order said
            let sorted = parts.sorted { (one: LibraryTopFit.Part, other: LibraryTopFit.Part) -> Bool in
                LibraryTopFit.priority(one, folds: folds) > LibraryTopFit.priority(other, folds: folds)
            }
            #expect(sorted == LibraryTopFit.reading(folds: folds))
        }
        #expect(LibraryTopFit.priority(.find, folds: true) == 3 && LibraryTopFit.priority(.switcher, folds: true) == 1)
    }


    @Test func playlistsMetaLineCountsAsFindDoes() {
        #expect(LibrarySwitchWords.playlistsCount(total: 9, shown: 9, finding: false) == "9 playlists")
        #expect(LibrarySwitchWords.playlistsCount(total: 1, shown: 1, finding: false) == "1 playlist")
        #expect(LibrarySwitchWords.playlistsCount(total: 9, shown: 3, finding: true) == "3 of 9 playlists")
        #expect(LibrarySwitchWords.playlistsCount(total: 0, shown: 0, finding: false) == "", "none: nothing said")
        #expect(LibrarySwitchWords.playlistsCount(total: 0, shown: 0, finding: true) == "")
    }
}
