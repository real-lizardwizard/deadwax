import Foundation

/// The Library's switch (Phase 4, slice 3b - notes/ios-specs/phase4-library.md 2.8 and 3.1, James's of 2026-11-14): the
/// Library opens on its pages, side by side - Albums | Playlists | Artists | Songs (Artists since slice 4, Songs since
/// slice 5) - in an order kept per phone, swiped between, with nothing above the albums. These are its rules and words;
/// the app draws them (LibraryView).
public enum LibraryPage: String, CaseIterable, Sendable, Hashable, Identifiable {
    case albums
    case playlists
    /// (slice 4) Your artists - or Artists, without a library of your own.
    case artists
    /// (slice 5) Every song, the collection's: a page of the switch only where the collection is the Library (no
    /// library of your own) - with one, it is All music > All songs (question 32, `LibraryPages.shown`).
    case songs

    public var id: String { rawValue }

    /// The switch's word for the page.
    public var title: String {
        switch self {
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .artists: return ArtistWords.artists
        case .songs: return SongWords.songs
        }
    }
}

/// The pages' order, kept per phone.
public enum LibraryPages {
    /// Where the order is kept (UserDefaults): the pages' names joined with commas, "playlists,albums".
    public static let storageKey = "deadwax-library-pages"
    /// The order before any is chosen - James's: Albums, Playlists, Artists, Songs.
    public static let standard: [LibraryPage] = LibraryPage.allCases

    /// The order as this phone kept it, read with care: a name it doesn't know, or a page named twice, left out; every
    /// page the value doesn't name (one added since, a damaged value, nothing kept) added after the rest in the
    /// standard order - so it holds every page once, and is never empty.
    public static func read(_ saved: String?) -> [LibraryPage] {
        var order: [LibraryPage] = []
        for name in (saved ?? "").split(separator: ",", omittingEmptySubsequences: true) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard let page = LibraryPage(rawValue: trimmed), !order.contains(page) else { continue }
            order.append(page)
        }
        for page in standard where !order.contains(page) { order.append(page) }
        return order
    }

    /// The order as it is kept.
    public static func saved(_ order: [LibraryPage]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// Edit order's drag: the pages at `offsets` moved to before the page at `destination` (a List's own move, its
    /// offsets and destination counted in the order as it was), the rest keeping their order.
    public static func moved(_ order: [LibraryPage], from offsets: IndexSet, to destination: Int) -> [LibraryPage] {
        let picked = offsets.filter { $0 >= 0 && $0 < order.count }
        guard !picked.isEmpty else { return order }
        let moving = picked.map { order[$0] }
        var rest: [LibraryPage] = []
        for (place, page) in order.enumerated() where !picked.contains(place) { rest.append(page) }
        let before = picked.filter { $0 < destination }.count
        let at = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: at)
        return rest
    }

    /// The page the Library opens on: the order's first.
    public static func first(_ order: [LibraryPage]) -> LibraryPage {
        order.first ?? standard[0]
    }

    /// (slice 5, question 32) The pages the switch shows, in the order kept: every page - but Songs, with a library of
    /// your own (`personal`). Subsonic can't list your songs alone (question 2), so Songs is the collection's: where
    /// the Library is the collection (logins off, the break-glass admin) it is the switch's fourth page; with a library
    /// of your own it is All music > All songs, as the web's phone has it (Playlists, Your albums, Your artists - then
    /// All music's All albums, All artists and All songs), never "Songs" beside your own albums and artists. Songs
    /// keeps its place in the order kept, for a phone that shows it again.
    public static func shown(_ order: [LibraryPage], personal: Bool) -> [LibraryPage] {
        guard personal else { return order }
        return order.filter { (page: LibraryPage) -> Bool in page != .songs }
    }

    /// Edit order's drag over the pages shown (`shown(order, personal:)`, which the sheet lists): those moved as the
    /// List moves them, and every page not shown keeping its place in the order kept - so Songs, left out with a
    /// library of your own, stays where it was among the rest.
    public static func moved(_ order: [LibraryPage], personal: Bool, from offsets: IndexSet,
                             to destination: Int) -> [LibraryPage] {
        let shown = self.shown(order, personal: personal)
        var rearranged = moved(shown, from: offsets, to: destination).makeIterator()
        return order.map { (page: LibraryPage) -> LibraryPage in
            guard shown.contains(page) else { return page }
            return rearranged.next() ?? page
        }
    }

    /// The page shown: `page`, while it is one of the pages shown - else (none yet, or one the switch no longer shows)
    /// the first of them.
    public static func showing(_ page: LibraryPage?, in shown: [LibraryPage]) -> LibraryPage {
        if let page, shown.contains(page) { return page }
        return first(shown)
    }
}

/// (the redesign, slice R2 - James's answer 1 of 25 Nov, "Today's behaviour, new look") The Library's top's Yours | All,
/// with a library of your own: Yours, the pages as they were (`LibraryPages.shown(order, personal: true)`); All, All
/// music's - the collection's albums, artists and songs, in the pages' place rather than pushed from the •••'s All music,
/// which the top's switch replaces.
public enum LibrarySide: String, CaseIterable, Sendable, Hashable {
    case yours
    case all

    /// The switch's word for the side.
    public var title: String {
        switch self {
        case .yours: return LibrarySwitchWords.yours
        case .all: return LibrarySwitchWords.all
        }
    }

    /// The albums' and the artists' scope on this side.
    public var scope: AlbumScope {
        switch self {
        case .yours: return .yours
        case .all: return .store
        }
    }

    /// (R2's review) The Albums page's list on this side, given the root's (`root`: the scope's albums, or Downloaded
    /// while deadwax was out of reach as the Library was last drawn - LibraryRoot): Yours' is the root's; All's is always
    /// the collection's, drawn from what is in hand while deadwax is away - never Downloaded, which is Yours' stand-in.
    public func albums(_ root: AlbumList) -> AlbumList {
        self == .all ? .scope(.store) : root
    }

    /// (R2's review) The Artists page's scope: the page's own (the person's, nil) on Yours, the collection's on All.
    public var artistsScope: AlbumScope? {
        self == .all ? .store : nil
    }

    /// (R2's review) Whose Shuffle the pulls and the •••'s are: the Library's on Yours, the collection's (All songs') on
    /// All.
    public var shuffle: ShuffleOf {
        self == .all ? .allSongs : .library
    }
}

extension LibraryPages {
    /// (R2) All music's pages, as its submenu listed them: albums, artists, songs.
    public static let allMusic: [LibraryPage] = [.albums, .artists, .songs]

    /// (R2) The pages the strip shows on a side, in the order kept. Without a library of your own, or on Yours, the
    /// pages `shown(order, personal:)` gives - so Songs is never beside your own albums (question 32); on All, All
    /// music's pages (Songs among them, where All songs was) and no Playlists, which are nobody's collection.
    public static func shown(_ order: [LibraryPage], personal: Bool, side: LibrarySide) -> [LibraryPage] {
        guard personal, side == .all else { return shown(order, personal: personal) }
        return order.filter { (page: LibraryPage) -> Bool in allMusic.contains(page) }
    }

    /// (R2) Whether the top shows Yours | All: with a library of your own and the Library on your albums - just where
    /// the •••'s All music was offered - while deadwax can be reached, or (its review) while All is the side `chosen`.
    /// It is put away offline only while Yours is the side shown: a chosen All never turns back into Yours on screen
    /// when deadwax drops out (All's pages draw what is in hand, as All music's pushed pages stayed put), and it never
    /// comes up offline to offer a side that can't be asked for.
    public static func sides(personal: Bool, scope: AlbumScope, online: Bool, chosen: LibrarySide) -> Bool {
        personal && scope == .yours && (online || chosen == .all)
    }

    /// (R2) The side drawn: the one chosen while the switch shows, else Yours.
    public static func side(_ chosen: LibrarySide, sides: Bool) -> LibrarySide {
        sides ? chosen : .yours
    }
}

/// (R2) One button of the Library's strip under its top: a page of the pager, or Downloaded - last, pushed as the •••'s
/// Downloaded was, never a page.
public enum LibraryStripItem: Hashable, Sendable {
    case page(LibraryPage)
    case downloaded

    /// The strip's word for it.
    public var title: String {
        switch self {
        case .page(let page): return page.title
        case .downloaded: return DownloadWords.downloadedTitle
        }
    }

    /// (R2's review) It opens a page of its own over the Library rather than showing one of the pager's: a button to
    /// VoiceOver, never a tab of the pages' tab bar.
    public var pushes: Bool {
        self == .downloaded
    }
}

/// (R2) The strip: the pages shown, in the order kept, then Downloaded - but while the Albums page is Downloaded
/// itself (deadwax out of reach), where the •••'s way back to the albums stands in its place.
public enum LibraryStrip {
    public static func items(_ pages: [LibraryPage], albumsPage: LibraryRootList = .albums) -> [LibraryStripItem] {
        let shown = pages.map { (page: LibraryPage) -> LibraryStripItem in .page(page) }
        return albumsPage == .downloaded ? shown : shown + [.downloaded]
    }
}

/// What the Library's Shuffle can do just now (2.8) - what its ••• item and the pull's graphic say.
public enum ShuffleCan: Sendable, Equatable {
    /// deadwax's order's first page is in hand: a tap plays it
    case ready
    /// deadwax can't be reached: every song on this phone, shuffled
    case downloads
    /// its first page is on its way
    case gettingReady
    /// it wouldn't come: why, in a listener's words
    case failed(String)
    /// deadwax can't be reached and nothing is on this phone
    case nothingHere
    /// the library has no songs at all: no Shuffle anywhere
    case none

    /// From the Library's state: `online` (deadwax can be reached), the first page `ready`, the scope `empty` (a total
    /// of 0), why it `failed` (nil while it hasn't), how many songs are on this phone.
    public static func of(online: Bool, ready: Bool, empty: Bool, failed: String?, songsHere: Int) -> ShuffleCan {
        guard online else { return songsHere > 0 ? .downloads : .nothingHere }
        if empty { return .none }
        if ready { return .ready }
        if let failed { return .failed(failed) }
        return .gettingReady
    }

    /// A release would shuffle: the pull arms only then.
    public var starts: Bool { self == .ready || self == .downloads }
}

/// One item of the Library's ••• (2.8). (R2's review) Only what the top's ••• holds (LibraryMenu.topSections): the
/// old menu's order, layout, New playlist, Downloaded and All music (its All artists and All songs) went with it, to the
/// meta line, the strip and Yours | All.
public enum LibraryMenuItem: Sendable, Equatable {
    /// the Shuffle, as it can be just now (never `.nothingHere` or `.none`: then there is no item)
    case shuffle(ShuffleCan)
    /// the way back to the albums while the Albums page is Downloaded: the scope's albums, pushed
    case albums(AlbumScope)
    case refresh
    case editOrder

    /// The item's words - `personal`: a library of your own (the lists' titles).
    public func words(personal: Bool) -> String {
        switch self {
        case .shuffle(let can):
            switch can {
            case .downloads: return LibrarySwitchWords.shuffleDownloads
            case .gettingReady: return ShuffleWords.gettingReady
            case .failed(let why): return why
            default: return ShuffleWords.shuffle
            }
        case .albums(let scope): return LibraryWords.title(scope, personal: personal)
        case .refresh: return LibrarySwitchWords.refresh
        case .editOrder: return LibrarySwitchWords.editOrder
        }
    }

    /// It can be chosen (Getting ready… and why it failed are drawn dimmed).
    public var enabled: Bool {
        switch self {
        case .shuffle(let can): return can.starts
        default: return true
        }
    }
}

/// The Library's ••• (2.8): what it holds, in its sections.
public enum LibraryMenu {
    /// (R2) The ••• under the Library's new top: the Shuffle; the way back to the albums while the Albums page is
    /// Downloaded (`scope`'s); Refresh and Edit order. What it held besides has moved: each page's order, Albums' Grid
    /// and List and Playlists' New playlist to the page's meta line, Downloaded to the strip, All music to the top's
    /// Yours | All.
    public static func topSections(shuffle: ShuffleCan, albumsPage: LibraryRootList,
                                   scope: AlbumScope) -> [[LibraryMenuItem]] {
        var sections: [[LibraryMenuItem]] = []
        switch shuffle {
        case .nothingHere, .none: break
        default: sections.append([.shuffle(shuffle)])
        }
        if albumsPage == .downloaded { sections.append([.albums(scope)]) }
        sections.append([.refresh, .editOrder])
        return sections
    }
}

/// The switch's words - the phone's own (phase4-library.md 6.3b), but those named from elsewhere.
public enum LibrarySwitchWords {
    /// The •••'s button, to VoiceOver - as a playlist's bar's ••• is "More for this playlist".
    public static let more = "More for the Library"
    public static let shuffleDownloads = "Shuffle downloads"
    public static let refresh = "Refresh"
    public static let editOrder = "Edit order"
    /// (slice 4) Albums' layout, in the ••• since question 26 - what the bar's button said (LibraryLayout).
    public static let showAsList = "Show as list"
    public static let showAsGrid = "Show as grid"
    /// Edit order's sheet: its title, its footer and its one button.
    public static let orderTitle = "Edit order"
    public static let orderFooter = "Drag the pages into the order you want. The Library opens on the first."
    public static let done = "Done"
    /// The switch's label to VoiceOver.
    public static let switchLabel = "Library pages"
    /// (the squared look) Find's own Cancel, beside its field: hides Find and clears its words.
    public static let cancelFind = "Cancel"
    /// Find's placeholder on Playlists.
    public static let findPlaylists = "Find in playlists"
    /// (R2) The top's Yours | All: its two words, and its name to VoiceOver.
    public static let yours = "Yours"
    public static let all = "All"
    public static let sidesLabel = "Your library or all music"
    /// (R2) Albums' Grid and List on the meta line, to VoiceOver - and the Mac's toolbar's words.
    public static let grid = "Grid"
    public static let list = "List"
    /// (R2) Playlists' meta line: "9 playlists", "3 of 9 playlists" while Find finds (Find's own counts, as Albums' and
    /// Artists' say theirs); nothing while there are none.
    public static func playlistsCount(total: Int, shown: Int, finding: Bool) -> String {
        guard total > 0 else { return "" }
        return finding ? Find.filteredCountText(shown: shown, total: total, one: "playlist", many: "playlists")
            : Find.countText(total, one: "playlist", many: "playlists")
    }
    /// "No playlists match “late”."
    public static func noPlaylistMatch(_ typed: String) -> String { Find.noMatchText("playlists", typed: typed) }
}
