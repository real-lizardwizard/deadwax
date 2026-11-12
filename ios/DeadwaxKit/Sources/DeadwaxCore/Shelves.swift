import Foundation

// The Library's shelves - ui/src/lib/shelves.ts, ported: the album sorts, the headers each groups by, and Find.
// Pinned by Tests/DeadwaxCoreTests/Library*.swift, which replay what the compiled TypeScript answered
// (Fixtures/library, written by ios/scripts/export-library-vectors.cjs) and the web's own sims' checks.

/// The album orders (ALBUM_SORTS), in the picker's order, with the web's ids - what a device saves - and labels.
/// Phase 1 has five; Recently played and Most played (`recent`, `frequent`) come with Phase 4.
public enum AlbumSort: String, CaseIterable, Sendable {
    case alphabeticalByArtist
    case alphabeticalByName
    case newest
    case byYearDesc
    case byYearAsc

    /// DEFAULT_ALBUM_SORT: Artist, each artist's albums oldest first.
    public static let `default`: AlbumSort = .alphabeticalByArtist

    public var label: String {
        switch self {
        case .alphabeticalByArtist: return "Artist"
        case .alphabeticalByName: return "Title"
        case .newest: return "Recently added"
        case .byYearDesc: return "Year, newest first"
        case .byYearAsc: return "Year, oldest first"
        }
    }

    /// `albumSortFrom`: a sort as a device saved it - one of these, anything else (nothing, an old or mistyped
    /// value) the default.
    public init(saved: String?) {
        self = saved.flatMap(AlbumSort.init(rawValue:)) ?? .default
    }
}

/// Whose Recently added a list is (2.0.11): the collection's - when the collection got each album, Navidrome's
/// `created` - or yours, when each entered your library, its `starred`. And this phone's (Phase 2's Downloaded): when
/// each album's first song arrived, which `DownloadedAlbums.index` puts in the album's `created` - so it sorts and
/// groups as the collection's does.
public enum AddedBy: String, Sendable {
    case collection
    case you
    case phone
}

/// What a sort compares an album by, made once per album (`albumKeys`) - never inside a comparator.
public struct AlbumKeys: Sendable, Equatable {
    public let artist: FoldKey
    public let title: FoldKey
    public let initial: String
    public let titleInitial: String
    /// nil: no year, or 0
    public let year: Int?
    public let created: Int64?
    /// when the asker starred it - when it entered their library; nil without one
    public let starred: Int64?

    public init(_ album: IndexAlbum, zone: TimeZone = .current) {
        artist = FoldKey(Fold.key(album.artist))
        title = FoldKey(Fold.key(album.name))
        initial = artist.initial
        titleInitial = title.initial
        year = (album.year ?? 0) > 0 ? album.year : nil
        created = AlbumTime.ms(album.created, zone: zone)
        starred = AlbumTime.ms(album.starred, zone: zone)
    }

    /// When one of YOUR albums was added: its star, else `created`. The collection's lists never ask it.
    public var addedAt: Int64? { starred ?? created }
}

/// A run of a sorted list under one header: its key, its words (nil for a sort without headers - none in Phase 1),
/// and its albums as places in `Shelf.albums`.
public struct ShelfGroup: Sendable, Equatable {
    public let key: String
    public let label: String?
    public var items: [Int]
}

/// One album list as the Library draws it: the albums in Navidrome's order, each one's keys and Find text made
/// once as the list lands. Everything else - an order, its groups, what Find keeps - is places in `albums`.
public struct Shelf: Sendable {
    /// Stars this close together are one moment (SAME_MOMENT_MS): deadwax stars a batch one album after another.
    public static let sameMomentMs: Int64 = 30_000
    /// The header of a year sort's albums with no year (NO_YEAR).
    public static let noYear = "No year"

    public let albums: [IndexAlbum]
    public let keys: [AlbumKeys]
    /// `findText(name) + " " + findText(artist)` - what Find's words are looked for in
    let findTexts: [FoldKey]

    public init(_ albums: [IndexAlbum], zone: TimeZone = .current) {
        self.albums = albums
        keys = albums.map { AlbumKeys($0, zone: zone) }
        findTexts = albums.map { FoldKey(Fold.findText($0.name) + " " + Fold.findText($0.artist)) }
    }

    public var count: Int { albums.count }

    // ===== sorts =====

    static func text(_ a: FoldKey, _ b: FoldKey) -> Int { a < b ? -1 : (b < a ? 1 : 0) }

    /// Letters first, then `#`; then the key itself.
    static func byName(_ a: FoldKey, _ aInitial: String, _ b: FoldKey, _ bInitial: String) -> Int {
        let first = (aInitial == Fold.otherInitial ? 1 : 0) - (bInitial == Fold.otherInitial ? 1 : 0)
        return first != 0 ? first : text(a, b)
    }

    /// A value that may be missing: the missing last, whichever way the rest go.
    static func missingLast<N: Comparable>(_ a: N?, _ b: N?, descending: Bool) -> Int {
        switch (a, b) {
        case (nil, nil): return 0
        case (nil, _): return 1
        case (_, nil): return -1
        case let (x?, y?): return x == y ? 0 : ((descending ? y < x : x < y) ? -1 : 1)
        }
    }

    /// The order the albums are drawn in (`sortAlbums`) - a new list of places, the list itself untouched. Every
    /// comparison ends in the place the album had in the answer, so ties keep Navidrome's order and the order is
    /// total (Swift's sort isn't stable; with a total order that can't show).
    public func sorted(_ sort: AlbumSort, by: AddedBy = .collection) -> [Int] {
        if sort == .newest && by == .you { return moments(Array(albums.indices)).flatMap(\.members) }
        let keys = self.keys
        func compare(_ a: Int, _ b: Int) -> Int {
            let x = keys[a], y = keys[b]
            var c: Int
            switch sort {
            case .alphabeticalByArtist:
                c = Self.byName(x.artist, x.initial, y.artist, y.initial)
                if c == 0 { c = Self.missingLast(x.year, y.year, descending: false) }
                if c == 0 { c = Self.text(x.title, y.title) }
            case .alphabeticalByName:
                c = Self.byName(x.title, x.titleInitial, y.title, y.titleInitial)
                if c == 0 { c = Self.text(x.artist, y.artist) }
            case .newest:
                c = Self.missingLast(x.created, y.created, descending: true)
            case .byYearDesc, .byYearAsc:
                c = Self.missingLast(x.year, y.year, descending: sort == .byYearDesc)
                if c == 0 { c = Self.byName(x.artist, x.initial, y.artist, y.initial) }
                if c == 0 { c = Self.text(x.title, y.title) }
            }
            return c != 0 ? c : a - b
        }
        return albums.indices.sorted { compare($0, $1) < 0 }
    }

    struct Moment {
        /// the newest star in it - what its month header says
        let at: Int64?
        var members: [Int]
    }

    /// Your albums cut into the moments they were added (2.0.11), newest first: each run of stars no more than
    /// `sameMomentMs` apart, one after the next (the gap to the PREVIOUS album, chained - never to the moment's
    /// first), is one; the albums with no date at all one last moment. Inside each: `created` newest first
    /// (missing last), then the star, then the order handed in.
    func moments(_ places: [Int]) -> [Moment] {
        let keys = self.keys
        let listed = places.sorted { a, b in
            let c = Self.missingLast(keys[a].addedAt, keys[b].addedAt, descending: true)
            return c != 0 ? c < 0 : a < b
        }
        var cut: [Moment] = []
        var last: Int64? = nil
        for place in listed {
            let at = keys[place].addedAt
            let joins: Bool
            if let current = cut.last {
                if let at {
                    joins = last.map { $0 - at <= Self.sameMomentMs } ?? false
                } else {
                    joins = current.at == nil
                }
            } else {
                joins = false
            }
            if joins { cut[cut.count - 1].members.append(place) } else { cut.append(Moment(at: at, members: [place])) }
            last = at
        }
        for n in cut.indices {
            cut[n].members.sort { a, b in
                var c = Self.missingLast(keys[a].created, keys[b].created, descending: true)
                if c == 0 { c = Self.missingLast(keys[a].addedAt, keys[b].addedAt, descending: true) }
                return c != 0 ? c < 0 : a < b
            }
        }
        return cut
    }

    // ===== headers =====

    /// Consecutive runs of the same key, each a group.
    static func runs(_ places: [Int], key: (Int) -> String, label: (Int) -> String?) -> [ShelfGroup] {
        var groups: [ShelfGroup] = []
        for place in places {
            let at = key(place)
            if let last = groups.last, last.key == at {
                groups[groups.count - 1].items.append(place)
            } else {
                groups.append(ShelfGroup(key: at, label: label(place), items: [place]))
            }
        }
        return groups
    }

    /// Sorted albums cut into their headers' groups (`groupAlbums`): the artist's or the title's first letter
    /// (`#` last), the year ("No year" last), the month added ("Date unknown" last). The month follows `by`: yours
    /// the month of the moment it entered your library - its newest star, so one moment is never split between two
    /// months - cut from `whole`, the sorted list BEFORE Find narrowed it to `sorted` (taking albums out of a run
    /// of stars only widens its gaps); an album not in `whole` reads "Date unknown". The collection's, its
    /// `created`. An empty list has no groups.
    public func groups(_ sorted: [Int], _ sort: AlbumSort, by: AddedBy = .collection, whole: [Int]? = nil) -> [ShelfGroup] {
        if sorted.isEmpty { return [] }
        let keys = self.keys
        switch sort {
        case .alphabeticalByArtist:
            return Self.runs(sorted, key: { keys[$0].initial }, label: { keys[$0].initial })
        case .alphabeticalByName:
            return Self.runs(sorted, key: { keys[$0].titleInitial }, label: { keys[$0].titleInitial })
        case .newest where by == .you:
            var month: [Int: String] = [:]
            for moment in moments(whole ?? sorted) {
                let label = AlbumTime.month(moment.at)
                for place in moment.members { month[place] = label }
            }
            return Self.runs(sorted, key: { month[$0] ?? AlbumTime.dateUnknown }, label: { month[$0] ?? AlbumTime.dateUnknown })
        case .newest:
            return Self.runs(sorted, key: { AlbumTime.month(keys[$0].created) }, label: { AlbumTime.month(keys[$0].created) })
        case .byYearDesc, .byYearAsc:
            return Self.runs(sorted, key: { keys[$0].year.map(String.init) ?? "none" },
                             label: { keys[$0].year.map(String.init) ?? Self.noYear })
        }
    }

    // ===== Find =====

    /// The albums Find keeps (`filterAlbums`), in the order handed in: every word typed, in any order, inside the
    /// album's title and artist folded - as runs of code units, not word starts ("eat" finds "Beatles"). Nothing
    /// typed (or spaces): everything.
    public func filter(_ sorted: [Int], typed: String) -> [Int] {
        let words = Find.words(typed)
        if words.isEmpty { return sorted }
        let texts = findTexts
        return sorted.filter { place in words.allSatisfy { texts[place].contains($0) } }
    }

    /// Everything one screen draws for a sort, `by` and what is typed into Find - as app/LibrarySection.tsx makes
    /// it. Pass the `sorted` list already made for this sort and `by` to keep from sorting again as Find changes.
    public func view(_ sort: AlbumSort, by: AddedBy, typed: String, sorted: [Int]? = nil) -> ShelfView {
        let sorted = sorted ?? self.sorted(sort, by: by)
        let finding = Find.finding(typed)
        let found = finding ? filter(sorted, typed: typed) : sorted
        let groups = self.groups(found, sort, by: by, whole: sorted)
        let index = ShelfIndex.shows(sort, count: sorted.count, typed: typed) ? ShelfIndex.entries(groups, sort) : nil
        let count = finding ? Find.filteredCountText(shown: found.count, total: sorted.count, one: "album", many: "albums")
            : Find.countText(sorted.count, one: "album", many: "albums")
        return ShelfView(sorted: sorted, found: found, groups: groups, index: index, countText: count)
    }
}

/// What one Albums screen draws: the sorted list, what Find kept of it, their headers, the index (nil when none is
/// drawn) and the count's words.
public struct ShelfView: Sendable, Equatable {
    public let sorted: [Int]
    public let found: [Int]
    public let groups: [ShelfGroup]
    public let index: [ShelfIndex.Entry]?
    public let countText: String
}

/// Find's words, and the counts it says (lib/shelves.ts, lib/artistPage.ts `countText`).
public enum Find {
    /// What is typed as the words Find looks for: folded as findText, split on its spaces (as code units - a
    /// Character can hold a space with a scalar clustered onto it).
    public static func words(_ typed: String) -> [FoldKey] {
        Array(Fold.findText(typed).utf16).split(separator: 0x20, omittingEmptySubsequences: true).map { FoldKey(units: Array($0)) }
    }

    /// Whether anything is typed into Find (spaces alone are nothing).
    public static func finding(_ typed: String) -> Bool { !words(typed).isEmpty }

    /// "12 of 3012 albums" - the plural chosen by the total.
    public static func filteredCountText(shown: Int, total: Int, one: String, many: String) -> String {
        "\(shown) of \(total) \(total == 1 ? one : many)"
    }

    /// "3012 albums", "1 album"; "" while there is no list.
    public static func countText(_ count: Int?, one: String, many: String) -> String {
        guard let count else { return "" }
        return "\(count) \(count == 1 ? one : many)"
    }

    /// "No albums match “dumy”." - what was typed, trimmed.
    public static func noMatchText(_ kind: String, typed: String) -> String {
        "No \(kind) match \u{201C}\(JSText.trim(typed))\u{201D}."
    }
}
