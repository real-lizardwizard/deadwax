import Foundation

/// The Library's switch (Phase 4, slice 3b - notes/ios-specs/phase4-library.md 2.8 and 3.1, James's of 2026-11-14): the
/// Library opens on its pages, side by side - Albums | Playlists | Artists since slice 4, Songs joining in slice 5 - in
/// an order kept per phone, swiped between, with nothing above the albums. These are its rules and words; the app draws
/// them (LibraryView).
public enum LibraryPage: String, CaseIterable, Sendable, Hashable, Identifiable {
    case albums
    case playlists
    /// (slice 4) Your artists - or Artists, without a library of your own.
    case artists

    public var id: String { rawValue }

    /// The switch's word for the page.
    public var title: String {
        switch self {
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .artists: return ArtistWords.artists
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

/// One item of the Library's ••• (2.8).
public enum LibraryMenuItem: Sendable, Equatable {
    /// the Shuffle, as it can be just now (never `.nothingHere` or `.none`: then there is no item)
    case shuffle(ShuffleCan)
    /// (slice 4, question 26) the page's order - Albums' or Artists': a submenu of its orders
    case order(LibraryPage)
    /// (slice 4, question 26) Albums' tiles or rows: `grid` while it is tiles
    case layout(grid: Bool)
    /// Downloaded, pushed
    case downloaded
    /// the way back to the albums while the Albums page is Downloaded: the scope's albums, pushed - and All music's
    /// All albums (the store's)
    case albums(AlbumScope)
    /// All music: a submenu of the collection's lists (`LibraryMenu.allMusic`) since slice 4
    case allMusic
    /// (slice 4) All music's All artists: the store's artists, pushed
    case artists(AlbumScope)
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
        case .order(let page): return page == .artists ? ArtistWords.sortLabel : LibraryWords.sortLabel
        case .layout(let grid): return grid ? LibrarySwitchWords.showAsList : LibrarySwitchWords.showAsGrid
        case .downloaded: return DownloadWords.downloadedTitle
        case .albums(let scope): return LibraryWords.title(scope, personal: personal)
        case .allMusic: return LibraryWords.allMusic
        case .artists(let scope): return ArtistWords.title(scope, personal: personal)
        case .refresh: return LibrarySwitchWords.refresh
        case .editOrder: return LibrarySwitchWords.editOrder
        }
    }

    /// It can be chosen (Getting ready… and why it failed are drawn dimmed).
    public var enabled: Bool {
        if case .shuffle(let can) = self { return can.starts }
        return true
    }
}

/// The Library's ••• (2.8): what it holds, in its sections. Since slice 4 (question 26: three pages and their buttons
/// crowd the bar) the page's own order and Albums' Grid or list are its second section - Playlists keeps its + in the
/// bar - and All music is a submenu of the collection's albums and artists.
public enum LibraryMenu {
    /// All music's submenu: the collection's albums and artists, each pushed.
    public static let allMusic: [LibraryMenuItem] = [.albums(.store), .artists(.store)]

    /// `shuffle`: what the Shuffle can do; `page`: the page shown, `grid`: Albums drawn as tiles; `albumsPage`: the list
    /// the Albums page is (Downloaded while deadwax couldn't be reached as it was last drawn); `scope`, `personal`,
    /// `online`: the person's and the connection's.
    public static func sections(shuffle: ShuffleCan, page: LibraryPage, grid: Bool, albumsPage: LibraryRootList,
                                scope: AlbumScope, personal: Bool, online: Bool) -> [[LibraryMenuItem]] {
        var sections: [[LibraryMenuItem]] = []
        switch shuffle {
        case .nothingHere, .none: break
        default: sections.append([.shuffle(shuffle)])
        }
        switch page {
        case .albums: sections.append([.order(.albums), .layout(grid: grid)])
        case .artists: sections.append([.order(.artists)])
        case .playlists: break
        }
        var places: [LibraryMenuItem] = [albumsPage == .downloaded ? .albums(scope) : .downloaded]
        if online && personal && scope == .yours { places.append(.allMusic) }
        sections.append(places)
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
    /// Find's placeholder on Playlists.
    public static let findPlaylists = "Find in playlists"
    /// "No playlists match “late”."
    public static func noPlaylistMatch(_ typed: String) -> String { Find.noMatchText("playlists", typed: typed) }
}
