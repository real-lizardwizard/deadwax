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

/// (the redesign, slice R2b - notes/ios.md "The redesign, slice R2b: the Library's top, one row again") The quiet line
/// under the Library's one row: each page's count and, where it has one, its order (Albums, Artists) or New playlist…
/// (Playlists); at its trailing end Grid and List, then Yours | All where it shows (LibraryPages.sides). James, 25 Nov:
/// "lets put the grid/list next to yours/all".
public enum LibraryLine {
    /// Grid and List sit on the line of Albums alone, as they were Albums' own in the old •••: the other pages have no
    /// layout of their own.
    public static func layouts(on page: LibraryPage) -> Bool {
        page == .albums
    }
}

/// (R2b) Whether the Library's one row holds its switch beside its two circles (iLibrary's .ltop: Find's circle 16 in
/// from the leading edge, the switch filling the room between, 12 from each circle, the ••• 16 in from the trailing
/// edge). The switch's segments are equal, so it needs its widest page's words in every one of them; where that is
/// more than the room (four pages - logins off, the break-glass sign-in - at the larger text sizes on a narrow phone),
/// it folds onto a row of its own under the circles, across the page, rather than cut a word short.
public enum LibraryTopFit {
    /// The room the row leaves its switch on a phone `width` points wide: its two sides, its circles and the gaps
    /// between them taken.
    public static func room(width: Double) -> Double {
        width - 2 * (PhoneLook.rowSide + PhoneLook.circle + PhoneLook.rowGap)
    }

    /// Folded, the switch's room: the page's width, as far in from each edge as the circles are.
    public static func foldedRoom(width: Double) -> Double {
        width - 2 * PhoneLook.rowSide
    }

    /// The switch folds under the circles where what it `needs` across - the widest page's words in each of its equal
    /// segments, and its well's two edges - is more than the row leaves it.
    public static func folds(needs: Double, width: Double) -> Bool {
        needs > room(width: width)
    }

    /// The row `width` wide - or, asked its own width (nil), as wide as its switch's `needs` beside the circles: whether
    /// the switch folds, and the room it is offered across.
    public struct Row: Sendable, Equatable {
        public let width: Double
        public let folds: Bool
        public let room: Double
    }

    public static func row(needs: Double, width: Double?) -> Row {
        let wide = width ?? needs + 2 * (PhoneLook.rowSide + PhoneLook.circle + PhoneLook.rowGap)
        let folds = folds(needs: needs, width: wide)
        return Row(width: wide, folds: folds, room: folds ? foldedRoom(width: wide) : room(width: wide))
    }

    /// Where the row's views go, at their sizes (the switch's in the room it was offered), and the row's size.
    public struct Placed: Sendable, Equatable {
        public let find: LookBox
        public let switcher: LookBox
        public let more: LookBox
        /// The switch's need, hidden: on the switch, at its own size.
        public let need: LookBox
        public let width: Double
        public let height: Double
    }

    /// Find's circle centred where its face is drawn, 16 in from the leading edge, and the •••'s as far in from the
    /// trailing one (each target reaching 5 pt past its face, into the room round it), both in a band 52 tall at least;
    /// the switch centred in the room between them, 12 from each face - or, folded, across the page under the band, as
    /// far in from each edge as the circles are, with the room under it the row would give it beside them.
    public static func place(_ row: Row, find: LookSize, switcher: LookSize, more: LookSize, need: LookSize) -> Placed {
        let circles = max(find.height, more.height)
        let band = row.folds ? max(PhoneLook.row, circles) : max(PhoneLook.row, circles, switcher.height)
        let middle = band / 2
        let x = row.folds ? row.width / 2 : PhoneLook.rowSide + PhoneLook.circle + PhoneLook.rowGap + row.room / 2
        let y = row.folds ? band + switcher.height / 2 : middle
        let under = max(0, (PhoneLook.row - switcher.height) / 2)
        return Placed(find: LookBox(centredOn: PhoneLook.rowSide + PhoneLook.circle / 2, middle, find),
                      switcher: LookBox(centredOn: x, y, switcher),
                      more: LookBox(centredOn: row.width - PhoneLook.rowSide - PhoneLook.circle / 2, middle, more),
                      need: LookBox(centredOn: x, y, need),
                      width: row.width, height: row.folds ? band + switcher.height + under : band)
    }

    /// The row's three controls, as VoiceOver reads them.
    public enum Part: Sendable, Equatable {
        case find, switcher, more
    }

    /// First to last, as they are drawn: Find, the switch, the ••• on one row - folded, the two circles on the row, then
    /// the switch under them (the review of R2b, 25 Nov).
    public static func reading(folds: Bool) -> [Part] {
        folds ? [.find, .more, .switcher] : [.find, .switcher, .more]
    }

    /// A control's accessibilitySortPriority in the row: the higher, the sooner it is read.
    public static func priority(_ part: Part, folds: Bool) -> Double {
        let order = reading(folds: folds)
        return Double(order.count - (order.firstIndex(of: part) ?? order.count))
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
/// old menu's order, layout, New playlist and All music (its All artists and All songs) went with it, to the meta line
/// and Yours | All - and (R2b) Downloaded came back to it from R2's strip.
public enum LibraryMenuItem: Sendable, Equatable {
    /// the Shuffle, as it can be just now (never `.nothingHere` or `.none`: then there is no item)
    case shuffle(ShuffleCan)
    /// (R2b) Downloaded, pushed - the old •••'s, and R2's strip's last button between
    case downloaded
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
        case .downloaded: return DownloadWords.downloadedTitle
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
    /// (R2) The ••• under the Library's new top - since R2b (James's drawing of 25 Nov) Shuffle, Downloaded, Refresh and
    /// Edit order: the Shuffle; Downloaded - or, while the Albums page is Downloaded itself (deadwax out of reach), the
    /// way back to the albums (`scope`'s) in its place, as the old ••• had them; Refresh and Edit order. What it held
    /// besides has moved: each page's order, Albums' Grid and List and Playlists' New playlist to the page's quiet line,
    /// All music to Yours | All.
    public static func topSections(shuffle: ShuffleCan, albumsPage: LibraryRootList,
                                   scope: AlbumScope) -> [[LibraryMenuItem]] {
        var sections: [[LibraryMenuItem]] = []
        switch shuffle {
        case .nothingHere, .none: break
        default: sections.append([.shuffle(shuffle)])
        }
        sections.append([albumsPage == .downloaded ? .albums(scope) : .downloaded])
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
    /// The switch's label to VoiceOver - (R2b) the row's switch of the pages again, as James's of 14 Nov was.
    public static let switchLabel = "Library pages"
    /// (the squared look) Find's own Cancel, beside its field: hides Find and clears its words.
    public static let cancelFind = "Cancel"
    /// Find's placeholder on Playlists.
    public static let findPlaylists = "Find in playlists"
    /// (R2) Yours | All - (R2b) two words at the end of each page's line: its two words, and its name to VoiceOver.
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
