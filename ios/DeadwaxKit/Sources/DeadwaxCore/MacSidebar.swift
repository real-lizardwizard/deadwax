import Foundation

// The Mac's sidebar (the Mac app's plan 1.2; notes/ios.md "The Mac app, slice 3: the desktop frame"): the web desktop's
// (app/Sidebar.tsx, lib/appFrame.ts) as its 2.1.35 lays it out - the search field; Requests, with what is arriving;
// one LIBRARY group, a Yours | All switch in its heading with a library of your own; PLAYLISTS and MANAGE, each folding
// away; Settings at the foot - every row with its glyph. Built from what the app has: the Library's rows are its own
// switch's pages in the person's order (LibraryPages, Edit order reorders them), All's the Library •••'s All music
// (LibraryMenu.allMusic), Manage's Settings > Manage's (Managing.tools, by permission), the playlists the web's
// sidebarPlaylists.
//
// Held to the web by Fixtures/frame/frame-vectors.json (ios/scripts/export-frame-vectors.cjs): the switch's words and
// rows, which side a row is on, the side shown and what a turn opens (sideOfItem, sideShown, sideFlip), what folds and
// what a folded heading says (foldOf, foldCurrent, manageHeadLabel), whether a page is pushed above a Library view
// (overLibraryView), the playlists listed (sidebarPlaylists), how a playlist's page is opened (playlistsMove), and the
// two choices kept on the device (state/persisted.ts) - mapped row for row where the app has the web's row. The Mac's
// own, tested in MacSidebarTests: where the app is (`current`, the web's sidebarCurrent on the app's stacks) and what a
// row does (`move`, its sidebarMove).
//
// Departures, each because the app has no such page: no Home (the app has none) and no Recently added (the app's
// Library has no such page; its Albums sort by Recently added); Downloaded closes the Library group, on either side
// (the phone's own: what is on this Mac); Edit an album opens Manage (the phone's own row, Choose the folder); Songs
// stays with logins off whatever Navidrome lists (the app's Library always has its Songs page).

public enum MacSidebar {
    /// Whose library the Library group lists (the web's LibrarySide, in LIBRARY_SIDES' order).
    public enum Side: String, Sendable, CaseIterable {
        case yours, all

        /// The switch's two words (SIDE_LABELS).
        public var label: String {
            switch self {
            case .yours: return "Yours"
            case .all: return "All"
            }
        }
    }

    /// The groups that fold away (SidebarFold): Playlists and Manage. The Library and Requests never fold.
    public enum Fold: String, Sendable, CaseIterable {
        case playlists, manage
    }

    /// Which are folded - neither by default (OPEN_FOLDS).
    public struct Folds: Sendable, Equatable {
        public var playlists: Bool
        public var manage: Bool

        public init(playlists: Bool = false, manage: Bool = false) {
            self.playlists = playlists
            self.manage = manage
        }

        public subscript(fold: Fold) -> Bool {
            get { fold == .playlists ? playlists : manage }
            set { if fold == .playlists { playlists = newValue } else { manage = newValue } }
        }

        /// `fold` turned over.
        public func toggled(_ fold: Fold) -> Folds {
            var next = self
            next[fold] = !self[fold]
            return next
        }
    }

    /// A row of the sidebar.
    public enum Row: Hashable, Sendable {
        case requests
        /// One of the Library's own pages at its root - yours with a library of your own, the library's with logins off.
        case view(LibraryPage)
        /// All's three, with a library of your own: the collection's albums, artists and songs.
        case allAlbums, allArtists, allSongs
        /// What is on this Mac.
        case downloaded
        /// The Playlists group's first row: the Library's Playlists page.
        case playlists
        /// One playlist, by its id.
        case playlist(String)
        /// One of Manage's.
        case manage(Managing.Tool)
        /// Settings, at the foot: the Settings tab.
        case settings
    }

    /// A page on one of the app's stacks, as the sidebar reads it.
    public enum Page: Hashable, Sendable {
        /// A Library row's own page, pushed at the foot of the Library's stack (as the Library •••'s All music pushes them).
        case allAlbums, allArtists, allSongs, downloaded
        case playlist(String)
        /// A Manage row's page.
        case manage(Managing.Tool)
        /// A page below one of Manage's: In nobody's library under Library care, a group of Server settings, a person.
        case under(Managing.Tool)
        /// Any other - an album, an artist, an EQ page.
        case other

        /// The row a section at the foot of the Library's stack is.
        public var section: Row? {
            switch self {
            case .allAlbums: return .allAlbums
            case .allArtists: return .allArtists
            case .allSongs: return .allSongs
            case .downloaded: return .downloaded
            default: return nil
            }
        }
    }

    /// The app's four tabs, as the sidebar names them (the Settings tab is You's).
    public enum Tab: Sendable, Equatable {
        case library, search, requests, settings
    }

    /// Where the app is: the tab showing, the Library's root page, and the stacks the sidebar reads.
    public struct Where: Sendable, Equatable {
        public var tab: Tab
        /// The Library's own page at its root - the one its switch shows.
        public var page: LibraryPage
        /// The Library's stack, bottom first.
        public var library: [Page]
        /// The Settings tab's stack.
        public var settings: [Page]
        /// The stack of the tab showing.
        public var shown: [Page]

        public init(tab: Tab, page: LibraryPage = .albums, library: [Page] = [], settings: [Page] = [],
                    shown: [Page]? = nil) {
            self.tab = tab
            self.page = page
            self.library = library
            self.settings = settings
            switch tab {
            case .library: self.shown = shown ?? library
            case .settings: self.shown = shown ?? settings
            case .search, .requests: self.shown = shown ?? []
            }
        }
    }

    // MARK: the rows

    /// The Library group's rows for a side: with logins off (or break-glass), the Library's own pages in the person's
    /// order, Playlists aside (its own group); with a library of your own, Yours' - your pages, Songs aside (the
    /// collection's: LibraryPages.shown) - or All's three. Downloaded last, on either.
    public static func rows(_ side: Side, order: [LibraryPage], personal: Bool) -> [Row] {
        let library: [Row]
        if personal && side == .all {
            library = [.allAlbums, .allArtists, .allSongs]
        } else {
            library = LibraryPages.shown(order, personal: personal).filter { $0 != .playlists }.map(Row.view)
        }
        return library + [.downloaded]
    }

    /// Manage's rows: Settings > Manage's, by permission, in its order.
    public static func manageRows(_ access: Access) -> [Row] {
        Managing.tools(access).map(Row.manage)
    }

    /// The Playlists group's playlists (sidebarPlaylists): yours, then shared with you, in Navidrome's order (by name) -
    /// never those made from files - at most `max`. None while the list isn't known.
    public static func playlists(_ list: [Playlist]?, max: Int = playlistsMax) -> [Playlist] {
        guard let list else { return [] }
        let groups = PlaylistRules.groups(list)
        return Array((groups.yours + groups.shared).prefix(max))
    }

    /// SIDEBAR_PLAYLISTS_MAX.
    public static let playlistsMax = 20

    // MARK: where the app is

    /// Whether a page is pushed above the Library's view on the tab showing (overLibraryView): anything over its root,
    /// or over a section at its stack's foot. Off the Library nothing is.
    public static func overLibraryView(_ at: Where) -> Bool {
        guard at.tab == .library else { return false }
        return at.library.count > (at.library.first?.section != nil ? 1 : 0)
    }

    /// The row for where the app is (the web's sidebarCurrent): a playlist's page on top is its row - All playlists
    /// when it isn't listed (`listed`, the ids the group lists); a section at the Library's foot its own row, whatever is
    /// over it; a Manage page (or one under it) on top its row, whatever tab; then the tab's - on the Library, the page
    /// its switch shows. Search has none: its place is the field.
    public static func current(_ at: Where, listed: [String]) -> Row? {
        let top = at.shown.last
        if case .playlist(let id)? = top { return listed.contains(id) ? .playlist(id) : .playlists }
        if at.tab == .library, let row = at.library.first?.section { return row }
        switch top {
        case .manage(let tool)?, .under(let tool)?: return .manage(tool)
        default: break
        }
        switch at.tab {
        case .search: return nil
        case .library: return at.page == .playlists ? .playlists : .view(at.page)
        case .requests: return .requests
        case .settings: return .settings
        }
    }

    /// Which side a row is on (sideOfItem): All for the collection's three, Yours for the Library's own pages, none for
    /// the rest - Downloaded is on neither.
    public static func side(of row: Row?) -> Side? {
        switch row {
        case .allAlbums?, .allArtists?, .allSongs?: return .all
        case .view(let page)?: return page == .playlists ? nil : .yours
        default: return nil
        }
    }

    /// The side the switch shows (sideShown): where you are while a Library view shows, else - off the Library, or on a
    /// page pushed above a view - the side last shown.
    public static func sideShown(_ current: Row?, remembered: Side, over: Bool) -> Side {
        if over { return remembered }
        return side(of: current) ?? remembered
    }

    /// What turning the switch to `to` opens (sideFlip): with a view of the other side showing, the same kind of view
    /// on this one - Albums for Albums, Artists for Artists, All's Songs back to your Albums (ACROSS); anywhere else, a
    /// page pushed above a view included, nothing (only the rows change).
    public static func sideFlip(_ current: Row?, to: Side, over: Bool) -> Row? {
        if over { return nil }
        guard let from = side(of: current), from != to, let current else { return nil }
        switch current {
        case .view(.albums), .view(.songs): return .allAlbums
        case .view(.artists): return .allArtists
        case .allAlbums, .allSongs: return .view(.albums)
        case .allArtists: return .view(.artists)
        default: return nil
        }
    }

    /// The group a row is listed in, of the two that fold (foldOf).
    public static func fold(of row: Row?) -> Fold? {
        switch row {
        case .playlists?, .playlist?: return .playlists
        case .manage?: return .manage
        default: return nil
        }
    }

    /// Whether a group's heading is drawn current (foldCurrent): folded, with one of its own pages showing.
    public static func foldCurrent(_ fold: Fold, _ folds: Folds, _ current: Row?) -> Bool {
        folds[fold] && self.fold(of: current) == fold
    }

    /// What a reader hears for Manage's heading (manageHeadLabel): folded with albums that need a look, its count.
    public static func manageHeadLabel(folded: Bool, needsLook: Int?) -> String {
        guard folded, let needsLook, needsLook > 0 else { return Words.manage }
        return "\(Words.manage), \(needsLook) album\(needsLook == 1 ? " needs" : "s need") a look"
    }

    // MARK: what a row does

    /// How a page is put on a stack: nothing (it is on top already), back to it (just under the top), over the top in
    /// its place (a sibling on top - never a pile), or pushed.
    public enum StackMove: String, Sendable, CaseIterable {
        case stay, back, become, open
    }

    /// What a row does.
    public enum Move: Sendable, Equatable {
        /// The tab's own button (AppNavigation.select): the tab as it was left, or back to its root - and its top - when
        /// it is the one showing.
        case tab(Tab)
        /// The Library at its root, showing this page of its switch.
        case view(LibraryPage)
        /// The Library with this section at its stack's foot.
        case section(Page)
        /// A playlist's page on the Library.
        case playlist(String, StackMove)
        /// A Manage page on the Settings tab.
        case manage(Managing.Tool, StackMove)
    }

    /// What a row does from where the app is (the web's sidebarMove): Requests and Settings are their tabs' buttons; the
    /// Library's page showing is the Library's (a second click: back to its root, then its top); another Library page is
    /// that page at the Library's root; a section is the Library with it at the foot - the tab's button when it is there
    /// already; a playlist or a Manage page is put on its stack as the web's openPlaylistsPage and openManagingPage do.
    public static func move(_ row: Row, _ at: Where) -> Move {
        let base = at.library.first
        switch row {
        case .requests:
            return .tab(.requests)
        case .settings:
            return .tab(.settings)
        case .view(let page):
            return base?.section == nil && page == at.page ? .tab(.library) : .view(page)
        case .playlists:
            return base?.section == nil && at.page == .playlists ? .tab(.library) : .view(.playlists)
        case .allAlbums, .allArtists, .allSongs, .downloaded:
            let section = sectionPage(row)
            return base == section ? .tab(.library) : .section(section)
        case .playlist(let id):
            return .playlist(id, playlistsMove(at.library, .playlist(id)))
        case .manage(let tool):
            return .manage(tool, managingMove(at.settings, tool))
        }
    }

    /// How a playlist's page is opened on the Library's stack (playlistsMove): nothing when it is on top; back to it when
    /// it is just under a playlist's page on top; in the place of another playlist's on top; else pushed.
    public static func playlistsMove(_ stack: [Page], _ page: Page) -> StackMove {
        let top = stack.last
        if top == page { return .stay }
        let playlistOnTop: Bool
        if case .playlist? = top { playlistOnTop = true } else { playlistOnTop = false }
        if playlistOnTop && stack.count >= 2 && stack[stack.count - 2] == page { return .back }
        return playlistOnTop ? .become : .open
    }

    /// How a Manage page is opened on the Settings tab's stack (the web's openManagingPage): nothing when it is on top;
    /// in the place of another Manage page on top (the rows are siblings, so going from one to another never piles
    /// them up, and back from any says Settings); else pushed.
    public static func managingMove(_ stack: [Page], _ tool: Managing.Tool) -> StackMove {
        guard case .manage(let top)? = stack.last else { return .open }
        return top == tool ? .stay : .become
    }

    /// (Slice 3's review) A row's move on a stack whose first `kept` pages hold work - a playlist's Edit open, a password
    /// or a People write out, as the tab's own button keeps them (PlaylistEdit.pagesKept, OwnPassword.pagesKept,
    /// People.pagesKept): a move that would take its top away (back) or put the row's page in its place (become) when the
    /// top is one of those pages pushes the row's page over it instead, so the work stays, a Back away. The rest as asked.
    public static func keepingWork(_ how: StackMove, count: Int, kept: Int) -> StackMove {
        switch how {
        case .back, .become:
            return count > 0 && kept >= count ? .open : how
        case .stay, .open:
            return how
        }
    }

    /// `page` put on `stack` as a row's move puts it (AppNavigation.macMove), its first `kept` pages never taken away or
    /// replaced (`keepingWork`).
    public static func put<Element>(_ page: Element, _ how: StackMove, on stack: inout [Element], kept: Int) {
        switch keepingWork(how, count: stack.count, kept: kept) {
        case .stay:
            break
        case .back:
            if !stack.isEmpty { stack.removeLast() }
        case .become:
            if stack.isEmpty { stack.append(page) } else { stack[stack.count - 1] = page }
        case .open:
            stack.append(page)
        }
    }

    private static func sectionPage(_ row: Row) -> Page {
        switch row {
        case .allAlbums: return .allAlbums
        case .allArtists: return .allArtists
        case .allSongs: return .allSongs
        default: return .downloaded
        }
    }

    // MARK: kept on the device - the web's keys and values (state/persisted.ts)

    /// The switch's side last shown: "all", or anything else (nothing kept) Yours.
    public static let sideKey = "deadwax-sidebar-side"
    /// The groups folded: their names, comma-separated.
    public static let foldedKey = "deadwax-sidebar-folded"

    public static func side(saved: String?) -> Side {
        saved == Side.all.rawValue ? .all : .yours
    }

    public static func folds(saved: String?) -> Folds {
        let named = (saved ?? "").split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Folds(playlists: named.contains(Fold.playlists.rawValue), manage: named.contains(Fold.manage.rawValue))
    }

    public static func saved(_ folds: Folds) -> String {
        Fold.allCases.filter { folds[$0] }.map(\.rawValue).joined(separator: ",")
    }

    // MARK: words and glyphs

    /// The sidebar's words - the web's where it says them (app/Sidebar.tsx, lib/appFrame.ts), the app's own elsewhere.
    public enum Words {
        /// (The Mac redesign, R1) The wordmark at the sidebar's top, as the design canvas draws it: the app's name,
        /// lowercase as the project always writes it.
        public static let brand = "deadwax"
        /// The groups' headings.
        public static let library = "Library"
        public static let playlists = "Playlists"
        public static let manage = ManagingWords.title
        /// SIDEBAR_PLAYLISTS: the Playlists group's first row.
        public static let allPlaylists = "All playlists"
        /// The field's placeholder (the web's "Search"); what a reader hears is Search's own name for its field.
        public static let searchPlaceholder = SearchWords.title
        public static let searchLabel = SearchWords.label
        /// The field's clear button.
        public static let clearSearch = "Clear search"
        /// The sidebar, as a reader finds it (the web's nav "Sections").
        public static let sections = "Sections"
        /// A folding heading's state to a reader - what the web's aria-expanded has VoiceOver say.
        public static let collapsed = "Collapsed"
        public static let expanded = "Expanded"
    }

    /// A row's words: the Library's pages by their switch's names (Albums, Artists, Songs - the switch says whose), All's
    /// plainly (SIDEBAR_ALL_ROWS), the rest by their pages' names. A playlist's is its name, from the list.
    public static func label(_ row: Row) -> String {
        switch row {
        case .requests: return RequestWords.tab
        case .view(let page): return page.title
        case .allAlbums: return LibraryPage.albums.title
        case .allArtists: return LibraryPage.artists.title
        case .allSongs: return LibraryPage.songs.title
        case .downloaded: return DownloadWords.downloadedTitle
        case .playlists: return Words.allPlaylists
        case .playlist: return ""
        case .manage(let tool): return ManagingWords.label(tool)
        case .settings: return YouWords.title
        }
    }

    /// A row's glyph (an SF Symbol), as the web's sidebar draws one on every row - the tab bar's own for Requests and
    /// Settings, the Library •••'s for its pages; a playlist has none (its name is set under All playlists').
    public static func symbol(_ row: Row) -> String? {
        switch row {
        case .requests: return "square.and.arrow.down"
        case .view(.albums), .allAlbums: return "square.stack"
        case .view(.artists), .allArtists: return "music.mic"
        case .view(.songs), .allSongs: return "music.note"
        case .view(.playlists), .playlists: return "music.note.list"
        case .downloaded: return DownloadWords.downloadSymbol
        case .playlist: return nil
        case .manage(.edit): return "pencil"
        case .manage(.queue): return "flag"
        case .manage(.care): return "cross.case"
        case .manage(.people): return "person.2"
        case .manage(.settings): return "server.rack"
        case .manage(.log): return "doc.plaintext"
        case .settings: return "gearshape"
        }
    }
}
