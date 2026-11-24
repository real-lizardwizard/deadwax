import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac's frame and sidebar, the parts that are the Mac's own (notes/ios.md "The Mac app, slice 3: the desktop
/// frame"): the frame at every size, one panel of three at a time, the window's sizes; the rows from the person's page
/// order and permissions; where the app is on its stacks (the web's sidebarCurrent) and what a row does (its
/// sidebarMove). The web's own rules are MacFrameVectorTests'.
@Suite struct MacFrameTests {
    @Test func theMacIsAlwaysTheDesktop() {
        #expect(MacFrame.drawsDesktop(.mac) && !MacFrame.drawsDesktop(.iPhone))
        #expect(!MacFrame.opensNowPlaying(.mac) && MacFrame.opensNowPlaying(.iPhone))
        // never a sheet, however narrow: a drawer up to COLUMN_MIN, a column from it
        for width in [0.0, 400, 880, 1023, 1024, 1279] {
            #expect(MacFrame.panelStyle(width: width) == .drawer, "\(width)")
            #expect(!MacFrame.panelIsModal(MacFrame.panelStyle(width: width)))
        }
        for width in [1280.0, 1440, 3000] {
            #expect(MacFrame.panelStyle(width: width) == .column, "\(width)")
        }
    }

    @Test func onePanelAtATime() {
        for shown in MacFrame.Panel.allCases {
            for asked in MacFrame.Panel.allCases where asked != .none {
                let now = MacFrame.toggled(shown, asked)
                #expect(now == (shown == asked ? .none : asked), "\(asked) over \(shown)")
            }
        }
        // the queue gone: Up Next and Info go with it, Lyrics stays to say Nothing playing
        #expect(MacFrame.afterQueueEnds(.upNext) == .none && MacFrame.afterQueueEnds(.info) == .none)
        #expect(MacFrame.afterQueueEnds(.lyrics) == .lyrics && MacFrame.afterQueueEnds(.none) == .none)
    }

    @Test func theWindowHoldsTheSidebarAPageAndTheBar() {
        // the bar's two sides, its gaps and ends, and the controls between them fit the smallest window
        let bar = 2 * MacFrame.barSideNarrow + 2 * MacFrame.barGap + 2 * MacFrame.barPad + MacFrame.barMiddleMin
        #expect(bar <= MacFrame.smallestWidth)
        // beside the sidebar, a page wider than a phone's (430, the biggest iPhone's)
        #expect(MacFrame.smallestWidth - MacFrame.sidebarWidth >= 430)
        #expect(MacFrame.smallestHeight - MacFrame.barHeight >= 480)
        // it opens wide enough for a panel beside the page, and never smaller than its smallest
        #expect(MacFrame.panelStyle(width: MacFrame.openingWidth) == .column)
        #expect(MacFrame.openingWidth >= MacFrame.smallestWidth && MacFrame.openingHeight >= MacFrame.smallestHeight)
        // a drawer always leaves some of the page in view, the sidebar shown, at the smallest
        #expect(MacFrame.smallestWidth - MacFrame.sidebarWidth - MacFrame.panelWidth > 0)
        // the grid's cover fits twice beside a panel's column at the column's width
        #expect(MacFrame.columnMin - MacFrame.sidebarWidth - MacFrame.panelWidth >= 2 * MacFrame.tileMin)
    }

    @Test func escapeHasOneOwnerTypingThenThePanelThenThePage() {
        // (slice 3's review) a text field with the cursor keeps it, whatever else is up
        for panel in MacFrame.Panel.allCases {
            #expect(MacFrame.escape(typing: true, panel: panel) == .field, "\(panel)")
        }
        // then the panel showing (its Done) - before a playlist's Edit on the page under it
        for panel in MacFrame.Panel.allCases where panel != .none {
            #expect(MacFrame.escape(typing: false, panel: panel) == .panel, "\(panel)")
        }
        // and only with neither, the page's Edit Cancel
        #expect(MacFrame.escape(typing: false, panel: .none) == .page)
    }

    @Test func aReadablePageKeepsItsScrollViewAcrossThePage() {
        // the margins either side of the readable column - none on a page narrower than it
        #expect(MacFrame.readableMargin(width: 0) == 0)
        #expect(MacFrame.readableMargin(width: MacFrame.readableWidth - 1) == 0)
        #expect(MacFrame.readableMargin(width: MacFrame.readableWidth) == 0)
        #expect(MacFrame.readableMargin(width: 1260) == 250)
        // the smallest window's page, the sidebar shown: the whole page
        #expect(MacFrame.readableMargin(width: MacFrame.smallestWidth - MacFrame.sidebarWidth) == 0)
        // what's left of the page between the margins is the readable width
        let page = 1687.0
        #expect(page - 2 * MacFrame.readableMargin(width: page) == MacFrame.readableWidth)
    }

    @Test func aSheetWithPagesFitsTheWindowAtEverySize() {
        // (slice 7) Edit album over the window as it opens: the readable width, the window's height less the room
        #expect(MacFrame.sheetSize(width: MacFrame.openingWidth, height: MacFrame.openingHeight)
                == MacFrame.Size(width: MacFrame.readableWidth, height: MacFrame.openingHeight - 2 * MacFrame.sheetRoom))
        #expect(MacFrame.sheetSize(width: 1280, height: 820) == MacFrame.Size(width: 760, height: 740))
        // the smallest window: still the readable width - 880 less the room is wider - inside it
        #expect(MacFrame.sheetSize(width: MacFrame.smallestWidth, height: MacFrame.smallestHeight)
                == MacFrame.Size(width: 760, height: 520))
        // every window from the smallest up, its page under a title bar of any height: inside it with room either side,
        // never wider than its pages read well, and as tall as the window leaves
        for width in stride(from: MacFrame.smallestWidth, through: 3000, by: 53) {
            for height in stride(from: MacFrame.smallestHeight - 60, through: 2000, by: 71) {
                let sheet = MacFrame.sheetSize(width: width, height: height)
                #expect(sheet.width + 2 * MacFrame.sheetRoom <= width, "\(width) x \(height)")
                #expect(sheet.height + 2 * MacFrame.sheetRoom == height, "\(width) x \(height)")
                #expect(sheet.width == MacFrame.readableWidth, "\(width): wider than the readable width")
                #expect(sheet.height > 400, "\(height): room for a page of rows")
            }
        }
        // narrower than the readable width and its room (no window is, but the rule holds), and nothing at all
        #expect(MacFrame.sheetSize(width: 700, height: 400) == MacFrame.Size(width: 620, height: 320))
        #expect(MacFrame.sheetSize(width: 0, height: 0) == MacFrame.Size(width: 0, height: 0))
        #expect(MacFrame.sheetRoom == 40)
    }
}

@Suite struct MacSidebarTests {
    private typealias Row = MacSidebar.Row

    // MARK: the rows

    @Test func theLibrarysRowsAreThePersonsOwnPages() {
        // logins off: the Library's pages in the person's order, Playlists in its own group, then Downloaded
        let order: [LibraryPage] = [.artists, .playlists, .songs, .albums]
        #expect(MacSidebar.rows(.yours, order: order, personal: false)
                == [.view(.artists), .view(.songs), .view(.albums), .downloaded])
        // the switch's side means nothing without a library of your own
        #expect(MacSidebar.rows(.all, order: order, personal: false) == MacSidebar.rows(.yours, order: order, personal: false))
        // a library of your own: yours, Songs the collection's (LibraryPages.shown); All's three
        #expect(MacSidebar.rows(.yours, order: order, personal: true) == [.view(.artists), .view(.albums), .downloaded])
        #expect(MacSidebar.rows(.all, order: order, personal: true) == [.allAlbums, .allArtists, .allSongs, .downloaded])
        // Edit order's own order, as saved
        let saved = LibraryPages.read("songs,albums")
        #expect(MacSidebar.rows(.yours, order: saved, personal: false) == [.view(.songs), .view(.albums), .view(.artists),
                                                                             .downloaded])
    }

    @Test func manageIsSettingsManageByPermission() {
        // Settings > Manage's rows, in its order: a Navidrome admin's six (check 424), with Needs a look's count
        let admin = Access(me: Me(user: "james", admin: true, auth: "on", permissions: nil))
        #expect(MacSidebar.manageRows(admin) == [.manage(.edit), .manage(.queue), .manage(.care), .manage(.people),
                                                 .manage(.settings), .manage(.log)])
        // logins off: no People (nobody to manage); a listener: none, and no Manage group
        let off = Access(me: Me(user: "local", admin: true, auth: "off", permissions: nil))
        #expect(MacSidebar.manageRows(off) == Managing.tools(off).map(Row.manage))
        #expect(!MacSidebar.manageRows(off).contains(.manage(.people)))
        let listener = Access(me: Me(user: "ethan", admin: false, auth: "on", permissions: ["request"]))
        #expect(MacSidebar.manageRows(listener).isEmpty)
    }

    @Test func everyRowHasItsWordsAndAGlyphButAPlaylist() {
        let rows: [Row] = [.requests, .view(.albums), .view(.artists), .view(.songs), .allAlbums, .allArtists, .allSongs,
                           .downloaded, .playlists, .settings] + Managing.Tool.allCases.map(Row.manage)
        for row in rows {
            #expect(!MacSidebar.label(row).isEmpty, "\(row)")
            #expect(MacSidebar.symbol(row) != nil, "\(row)")
        }
        #expect(MacSidebar.symbol(.playlist("p1")) == nil, "a playlist's name sits under All playlists' words")
        #expect(MacSidebar.label(.view(.albums)) == "Albums" && MacSidebar.label(.allAlbums) == "Albums")
        #expect(MacSidebar.label(.downloaded) == DownloadWords.downloadedTitle)
        #expect(MacSidebar.label(.manage(.edit)) == ManagingWords.editAnAlbum)
        #expect(MacSidebar.label(.settings) == YouWords.title && MacSidebar.label(.requests) == RequestWords.tab)
        // the tab bar's own glyphs for the tabs the sidebar stands for
        #expect(MacSidebar.symbol(.requests) == "square.and.arrow.down" && MacSidebar.symbol(.settings) == "gearshape")
        // a folding heading's state, as VoiceOver says the web's aria-expanded
        #expect(MacSidebar.Words.collapsed == "Collapsed" && MacSidebar.Words.expanded == "Expanded")
    }

    // MARK: where the app is

    @Test func theRowForWhereTheAppIs() {
        typealias W = MacSidebar.Where
        // the Library at its root: the page its switch shows; Playlists' page is All playlists
        #expect(MacSidebar.current(W(tab: .library, page: .artists), listed: []) == .view(.artists))
        #expect(MacSidebar.current(W(tab: .library, page: .playlists), listed: []) == .playlists)
        // an album over it: still the view under it
        #expect(MacSidebar.current(W(tab: .library, page: .albums, library: [.other]), listed: []) == .view(.albums))
        // a section at the foot names its own row, whatever is over it
        #expect(MacSidebar.current(W(tab: .library, page: .albums, library: [.allArtists, .other]), listed: []) == .allArtists)
        #expect(MacSidebar.current(W(tab: .library, library: [.downloaded]), listed: []) == .downloaded)
        // a playlist's page on top: its row while it is listed, All playlists while it isn't
        #expect(MacSidebar.current(W(tab: .library, library: [.playlist("p1")]), listed: ["p1"]) == .playlist("p1"))
        #expect(MacSidebar.current(W(tab: .library, library: [.playlist("p9")]), listed: ["p1"]) == .playlists)
        // ...before a section under it
        #expect(MacSidebar.current(W(tab: .library, library: [.allAlbums, .playlist("p1")]), listed: ["p1"]) == .playlist("p1"))
        // a Manage page on top - or one under it - is its row; under an album it is the tab's again
        #expect(MacSidebar.current(W(tab: .settings, settings: [.manage(.log)]), listed: []) == .manage(.log))
        #expect(MacSidebar.current(W(tab: .settings, settings: [.manage(.people), .under(.people)]), listed: [])
                == .manage(.people))
        #expect(MacSidebar.current(W(tab: .settings, settings: [.manage(.queue), .other]), listed: []) == .settings)
        // Search has none - its place is the field; Requests and Settings are theirs
        #expect(MacSidebar.current(W(tab: .search, library: [.allAlbums]), listed: []) == nil)
        #expect(MacSidebar.current(W(tab: .requests), listed: []) == .requests)
        #expect(MacSidebar.current(W(tab: .settings), listed: []) == .settings)
        // the Library's section isn't the row while another tab shows
        #expect(MacSidebar.current(W(tab: .requests, library: [.allAlbums]), listed: []) == .requests)
    }

    @Test func overTheLibrarysView() {
        typealias W = MacSidebar.Where
        #expect(!MacSidebar.overLibraryView(W(tab: .library)))
        #expect(!MacSidebar.overLibraryView(W(tab: .library, library: [.allAlbums])))
        #expect(MacSidebar.overLibraryView(W(tab: .library, library: [.other])))
        #expect(MacSidebar.overLibraryView(W(tab: .library, library: [.allAlbums, .other])))
        #expect(!MacSidebar.overLibraryView(W(tab: .requests, library: [.other])), "off the Library nothing is")
    }

    // MARK: what a row does

    @Test func whatEachRowDoes() {
        typealias W = MacSidebar.Where
        let root = W(tab: .library, page: .albums)
        // Requests and Settings: their tabs' buttons
        #expect(MacSidebar.move(.requests, root) == .tab(.requests))
        #expect(MacSidebar.move(.settings, root) == .tab(.settings))
        // the Library's page showing: the tab's button (back to its root, then its top); another page at the root
        #expect(MacSidebar.move(.view(.albums), root) == .tab(.library))
        #expect(MacSidebar.move(.view(.albums), W(tab: .requests, page: .albums, library: [.other])) == .tab(.library),
                "the Library as it was left")
        #expect(MacSidebar.move(.view(.artists), root) == .view(.artists))
        #expect(MacSidebar.move(.playlists, root) == .view(.playlists))
        #expect(MacSidebar.move(.playlists, W(tab: .library, page: .playlists)) == .tab(.library))
        // over a section, the page under it is no longer showing: every Library page is that page at the root
        let section = W(tab: .library, page: .albums, library: [.allAlbums])
        #expect(MacSidebar.move(.view(.albums), section) == .view(.albums))
        #expect(MacSidebar.move(.playlists, W(tab: .library, page: .playlists, library: [.allAlbums])) == .view(.playlists))
        // a section: the Library with it at the foot - the tab's button when it is there already
        #expect(MacSidebar.move(.allAlbums, section) == .tab(.library))
        #expect(MacSidebar.move(.allArtists, section) == .section(.allArtists))
        #expect(MacSidebar.move(.allSongs, root) == .section(.allSongs))
        #expect(MacSidebar.move(.downloaded, root) == .section(.downloaded))
        // a playlist: on the Library, siblings never piled up
        #expect(MacSidebar.move(.playlist("p1"), root) == .playlist("p1", .open))
        #expect(MacSidebar.move(.playlist("p1"), W(tab: .library, library: [.playlist("p1")])) == .playlist("p1", .stay))
        #expect(MacSidebar.move(.playlist("p2"), W(tab: .library, library: [.playlist("p1")])) == .playlist("p2", .become))
        #expect(MacSidebar.move(.playlist("p1"), W(tab: .library, library: [.playlist("p1"), .playlist("p2")]))
                == .playlist("p1", .back))
        // a Manage page: on Settings, in the place of another Manage page on top, else pushed
        #expect(MacSidebar.move(.manage(.queue), root) == .manage(.queue, .open))
        #expect(MacSidebar.move(.manage(.queue), W(tab: .settings, settings: [.manage(.queue)])) == .manage(.queue, .stay))
        #expect(MacSidebar.move(.manage(.log), W(tab: .settings, settings: [.manage(.queue)])) == .manage(.log, .become))
        #expect(MacSidebar.move(.manage(.log), W(tab: .settings, settings: [.manage(.people), .under(.people)]))
                == .manage(.log, .open))
        #expect(MacSidebar.managingMove([], .care) == .open)
    }

    @Test func aRowNeverTakesAwayAPageHoldingWork() {
        // (slice 3's review) a move that takes the top away or replaces it, with the top holding work: pushed over it
        for how in [MacSidebar.StackMove.back, .become] {
            #expect(MacSidebar.keepingWork(how, count: 2, kept: 2) == .open, "\(how)")
            #expect(MacSidebar.keepingWork(how, count: 2, kept: 3) == .open, "\(how)")
            #expect(MacSidebar.keepingWork(how, count: 2, kept: 1) == how, "\(how): the top holds none")
            #expect(MacSidebar.keepingWork(how, count: 2, kept: 0) == how, "\(how)")
        }
        for how in [MacSidebar.StackMove.stay, .open] {
            #expect(MacSidebar.keepingWork(how, count: 2, kept: 2) == how, "\(how)")
        }
        #expect(MacSidebar.keepingWork(.become, count: 0, kept: 0) == .become)
    }

    @Test func aRowsMoveAsTheAppMakesIt() {
        // the stacks as AppNavigation keeps them, and the tab's own rule for what they keep
        func kept(_ stack: [String], editing: String?) -> Int {
            PlaylistEdit.pagesKept(stack.map { $0.hasPrefix("playlist:") ? String($0.dropFirst(9)) : nil }, editing: editing)
        }
        func page(_ name: String) -> MacSidebar.Page {
            name.hasPrefix("playlist:") ? .playlist(String(name.dropFirst(9))) : .other
        }
        func click(_ id: String, on stack: [String], editing: String?) -> [String] {
            var stack = stack
            let how = MacSidebar.playlistsMove(stack.map(page), .playlist(id))
            MacSidebar.put("playlist:\(id)", how, on: &stack, kept: kept(stack, editing: editing))
            return stack
        }
        // playlist A in Edit, B clicked: A stays under B, its Edit with it - never replaced
        #expect(click("B", on: ["playlist:A"], editing: "A") == ["playlist:A", "playlist:B"])
        #expect(click("B", on: ["playlist:A"], editing: nil) == ["playlist:B"], "no Edit: siblings, never piled")
        // B under A, A in Edit, B clicked: A isn't popped - B opens over it
        #expect(click("B", on: ["playlist:B", "playlist:A"], editing: "A") == ["playlist:B", "playlist:A", "playlist:B"])
        #expect(click("B", on: ["playlist:B", "playlist:A"], editing: nil) == ["playlist:B"])
        // an Edit lower down holds only the pages up to it: a playlist over an album over it is replaced as before
        #expect(click("C", on: ["playlist:A", "album", "playlist:B"], editing: "A") == ["playlist:A", "album", "playlist:C"])
        // the one on top clicked again: nothing
        #expect(click("A", on: ["playlist:A"], editing: "A") == ["playlist:A"])

        // People with a write out on top of Settings, Event log clicked: pushed over People, never in its place
        func manage(_ tool: Managing.Tool, on stack: [Managing.Tool], writing: Bool) -> [Managing.Tool] {
            var stack = stack
            let how = MacSidebar.managingMove(stack.map(MacSidebar.Page.manage), tool)
            MacSidebar.put(tool, how, on: &stack, kept: People.pagesKept(stack.map { $0 == .people }, writing: writing))
            return stack
        }
        #expect(manage(.log, on: [.people], writing: true) == [.people, .log])
        #expect(manage(.log, on: [.people], writing: false) == [.log])
        #expect(manage(.people, on: [.log], writing: false) == [.people])
        #expect(manage(.people, on: [.people], writing: true) == [.people])
    }

    @Test func theSwitchAndTheFoldsKeptAsTheWebKeepsThem() {
        #expect(MacSidebar.side(saved: nil) == .yours && MacSidebar.side(saved: "all") == .all)
        #expect(MacSidebar.folds(saved: nil) == MacSidebar.Folds())
        #expect(MacSidebar.saved(MacSidebar.Folds(playlists: true, manage: true)) == "playlists,manage")
        var folds = MacSidebar.Folds()
        folds = folds.toggled(.manage)
        #expect(folds.manage && !folds.playlists && folds[.manage])
        folds = folds.toggled(.manage).toggled(.playlists)
        #expect(folds == MacSidebar.Folds(playlists: true, manage: false))
        // the flip from the Mac's own rows: Songs with logins off goes to All's Albums as the web's Recently added does
        #expect(MacSidebar.sideFlip(.view(.songs), to: .all, over: false) == .allAlbums)
        #expect(MacSidebar.sideFlip(.downloaded, to: .all, over: false) == nil, "Downloaded is on neither side")
        #expect(MacSidebar.side(of: .downloaded) == nil && MacSidebar.fold(of: .downloaded) == nil)
        #expect(MacSidebar.fold(of: .manage(.edit)) == .manage && MacSidebar.fold(of: .playlist("p")) == .playlists)
    }

    @Test func thePlaylistsListedAtMostTwenty() {
        let yours = (0..<25).map { Playlist(id: "y\($0)", name: "Mix \($0)", mine: true, editable: true) }
        let shared = Playlist(id: "s", name: "Shared", mine: false, editable: false)
        let file = Playlist(id: "f", name: "File", mine: true, editable: false)
        #expect(MacSidebar.playlists(nil).isEmpty && MacSidebar.playlists([]).isEmpty)
        #expect(MacSidebar.playlists([shared, file, yours[0]]).map(\.id) == ["y0", "s"])
        #expect(MacSidebar.playlists(yours + [shared]).count == MacSidebar.playlistsMax)
    }
}
