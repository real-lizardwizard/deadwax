import Foundation

// Songs (Phase 4, slice 5 - notes/ios-specs/phase4-library.md 2.7, 3.1, 6.5; the web's app/LibraryViews.tsx SongsView,
// app/usePaged.ts, app/LibrarySection.tsx SongSection): every song of the collection, 100 a page (search3 with an
// empty query, which Navidrome answers with everything - SONGS_PAGE), in Navidrome's order. A row opens its album -
// a fetch-then-play would start the music outside the tap - and its ••• is the song's own menu. Where the collection
// is the Library (no library of your own) it is the switch's Songs page; with a library of your own it is All music >
// All songs (question 32: Subsonic can't list your songs alone - question 2), with the collection's own Shuffle
// (`ShuffleOf.allSongs`). Pure: the app makes the asks these name and hands back what came (SongsScreen).

/// Songs' words: the web's, verbatim, but the phone's own where named.
public enum SongWords {
    /// The switch's word for the page, and the page's title without a library of your own (LIBRARY_TITLES.songs).
    public static let songs = "Songs"
    /// The collection's songs with a library of your own (PERSONAL_TITLES.songs, SIDEBAR_BROWSE's).
    public static let allSongs = "All songs"
    /// The title: "All songs" with a library of your own, else "Songs" (libraryTitle('songs', personal)).
    public static func title(personal: Bool) -> String { personal ? allSongs : songs }
    /// Navidrome lists no songs at all (NO_SONGS).
    public static let noSongs = "No songs yet."
    /// The rest of a row as VoiceOver reads it (SongsView's visually hidden ", opens its album").
    public static let opensItsAlbum = "opens its album"
    /// (the phone's own, question 33) Find's placeholder on Songs - Find there asks Navidrome's own search.
    public static let findPlaceholder = "Find in songs"
    /// (the phone's own, question 34) While deadwax can't be reached and no songs are in hand.
    public static let offline = "Songs show here once deadwax is back."

    /// "No songs match “roads”." - what was typed, trimmed.
    public static func noMatch(_ typed: String) -> String { Find.noMatchText("songs", typed: typed) }

    /// The count over the list (SongSection's `countText(songs, 'song', 'songs')`): "1 song", "12480 songs" - "" while
    /// it isn't known.
    public static func count(_ count: Int?) -> String { Find.countText(count, one: "song", many: "songs") }

    /// A row as VoiceOver reads it: its title, its line (`PlaylistRules.songLine`, the web's `[song.artist,
    /// song.album].filter(Boolean).join(' · ')`), and that it opens its album when it does - "Roads, Portishead ·
    /// Dummy, opens its album".
    public static func spoken(_ song: Song) -> String {
        var parts = [song.title ?? ""]
        let line = PlaylistRules.songLine(song)
        if !line.isEmpty { parts.append(line) }
        if SongsList.opensAlbum(song) { parts.append(opensItsAlbum) }
        return parts.filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }
}

/// A list of songs a page at a time (app/usePaged.ts, ported): the first page asked as the list shows, the next as its
/// end comes near - one at a time, only the newest ask's answer counting - each page added to what is drawn, leaving out
/// any song already there (`appended`: the list is live, so a later page can repeat the song at an earlier one's edge),
/// while the next offset follows what the server handed out. A page shorter than `pageSize` is the last. A page that
/// won't come stops the paging until Try again (`retry`) asks it again.
///
/// Keyed on `query` - what Songs' Find asks Navidrome for ("" for every song; question 33): another query is another
/// list, emptied at once, the page on its way for the old one let go (the web's new `key`). The same query asked again -
/// a pull to refresh, the •••'s Refresh - keeps the list drawn until its first page lands in its place (`stale`), as the
/// Library's lists swap in where the old one was.
public struct SongsPaging: Sendable, Equatable {
    /// SONGS_PAGE (player/api.ts): how many songs a page asks for.
    public static let pageSize = 100

    /// One ask: `search?q=&songCount=&songOffset=` with no artists or albums (librarySongs).
    public struct Ask: Sendable, Equatable {
        public let serial: Int
        /// Navidrome's search words - "" for every song
        public let query: String
        public let offset: Int
        public var count: Int { SongsPaging.pageSize }
    }

    /// The songs drawn, in Navidrome's order.
    public private(set) var items: [Song] = []
    /// The list's key: nil before anything was asked.
    public private(set) var query: String?
    /// A page is on its way.
    public private(set) var loading = false
    /// The last page asked wouldn't come.
    public private(set) var failing = false
    /// Every page is in: the list is the whole of it.
    public private(set) var done = false
    /// The songs drawn are the list as it was before a refresh, its first page still to come.
    public private(set) var stale = false
    /// Where the next page starts - what the server has handed out, whatever was left out as already drawn.
    public private(set) var next = 0
    /// The newest ask's: an answer for any other is dropped.
    var serial = 0

    public init() {}

    /// The list for `query`, from its first page: another query empties the list at once; the same one asked again
    /// keeps it drawn until the first page replaces it.
    public mutating func start(_ query: String) -> Ask {
        if self.query != query { items = [] }
        stale = !items.isEmpty
        self.query = query
        done = false
        next = 0
        return begin(offset: 0)
    }

    /// The end of the list came near: its next page - nil while one is on its way, every page is in, the last failed
    /// (Try again asks it), the list drawn is a refresh's old one, or nothing was asked yet.
    public mutating func more() -> Ask? {
        guard query != nil, !loading, !done, !failing, !stale else { return nil }
        return begin(offset: next)
    }

    /// Try again: the page that wouldn't come, asked again (nil when none failed).
    public mutating func retry() -> Ask? {
        guard query != nil, failing else { return nil }
        return begin(offset: next)
    }

    /// `ask`'s page came: the first in place of what was drawn, a later one added after it, songs already drawn left
    /// out; the last once it is short.
    public mutating func answered(_ ask: Ask, _ page: [Song]) {
        guard ask.serial == serial else { return }
        items = ask.offset == 0 ? page : Self.appended(items, page)
        loading = false
        failing = false
        stale = false
        done = page.count < Self.pageSize
        next = ask.offset + page.count
    }

    /// `ask`'s page wouldn't come (not called off): what is drawn stays, and Try again asks it again.
    public mutating func failed(_ ask: Ask) {
        guard ask.serial == serial else { return }
        loading = false
        failing = true
    }

    /// A new person, or the list gone: everything let go, no answer asked before landing.
    public mutating func reset() {
        serial += 1
        items = []
        query = nil
        loading = false
        failing = false
        done = false
        stale = false
        next = 0
    }

    /// `ask` is the newest: its answer is the one that counts (an older one's is dropped by `answered` and `failed`).
    public func isNewest(_ ask: Ask) -> Bool { ask.serial == serial }

    /// The count over the list: "N songs" once every page is in (the web's `songs.done ? songs.items.length : null`).
    public var countText: String { SongWords.count(done ? items.count : nil) }

    /// appendPage (usePaged.ts): `page` after `shown`, leaving out any song already shown, by id - a song twice within
    /// the page itself kept twice, as the web's filter keeps it.
    public static func appended(_ shown: [Song], _ page: [Song]) -> [Song] {
        let held = Set(shown.map { (song: Song) -> String in song.id })
        return shown + page.filter { (song: Song) -> Bool in !held.contains(song.id) }
    }

    private mutating func begin(offset: Int) -> Ask {
        serial += 1
        loading = true
        failing = false
        return Ask(serial: serial, query: query ?? "", offset: offset)
    }
}

/// What Songs draws (SongsView), from the list in hand.
public enum SongsBody: Sendable, Equatable {
    /// nothing in hand, its first page on its way: a spinner
    case loading
    /// nothing in hand, and the ask failed: why, and Try again
    case failed
    /// every page in and no song: "No songs yet." - or, finding, "No songs match “…”."
    case empty(String)
    /// (question 34) deadwax can't be reached and nothing is in hand: SongWords.offline
    case offline
    /// the rows - and at their foot `SongsFoot`
    case songs

    /// `paging`: the list; `online`: deadwax can be reached; `typed`: what is in Find.
    public static func of(_ paging: SongsPaging, online: Bool, typed: String) -> SongsBody {
        if !paging.items.isEmpty { return .songs }
        if paging.done && !paging.loading {
            return .empty(Find.finding(typed) ? SongWords.noMatch(typed) : SongWords.noSongs)
        }
        if !online { return .offline }
        if paging.failing { return .failed }
        return .loading
    }
}

/// What is drawn under the rows (SongsView's foot): a spinner while a page comes, why and Try again when one wouldn't
/// - or, over a refresh's old list, that it couldn't be updated (COULDNT_REFRESH, at the top instead) - else nothing.
public enum SongsFoot: Sendable, Equatable {
    case nothing
    case loading
    case failed
    /// the list drawn is the one before a refresh, which failed: "Couldn't update this list - showing it as it was."
    case couldntRefresh

    public static func of(_ paging: SongsPaging, online: Bool) -> SongsFoot {
        guard !paging.items.isEmpty else { return .nothing }
        if paging.failing { return paging.stale ? .couldntRefresh : .failed }
        if paging.loading && !paging.stale && online { return .loading }
        return .nothing
    }
}

/// A row's rules.
public enum SongsList {
    /// What Songs' Find asks Navidrome for: what is typed, trimmed - "" (every song) while nothing is.
    public static func query(_ typed: String) -> String {
        Find.finding(typed) ? JSText.trim(typed) : ""
    }

    /// A row opens its album - only with an album id to open (SongsView's `if (!song.albumId) return`).
    public static func opensAlbum(_ song: Song) -> Bool {
        guard let id = song.albumId else { return false }
        return !id.isEmpty
    }

    /// Dimmed, opening nothing (3.1's rule, as an artist's row is): deadwax out of reach and the song not on this phone.
    public static func dimmed(_ song: Song, online: Bool, here: (String) -> Bool) -> Bool {
        !online && !here(song.id)
    }

    /// The row is asked to bring the next page when it is this near the end of what is drawn (usePaged's 800 px
    /// rootMargin - some 12 rows - and a flick's worth more), so the next page is there by the time a flick gets to it.
    public static let nearTheEnd = 25

    /// The row at `index` of `count` drawn is near enough the end to ask for more.
    public static func asksMore(at index: Int, of count: Int) -> Bool { index >= count - nearTheEnd }
}

/// All songs' Shuffle button (ShuffleSongs.tsx's, at the head of the collection's songs with a library of your own):
/// what it says, whether it plays, and why not - from what the Shuffle can do (ShuffleCan); nil for no button.
public struct ShuffleButtonFace: Sendable, Equatable {
    public let words: String
    public let enabled: Bool
    /// Under it when its first page wouldn't come - the web's title and live line (SHUFFLE_UNREADY, or a 413's words).
    public let why: String?

    public static func of(_ can: ShuffleCan) -> ShuffleButtonFace? {
        switch can {
        case .ready: return ShuffleButtonFace(words: ShuffleWords.shuffle, enabled: true, why: nil)
        case .downloads: return ShuffleButtonFace(words: LibrarySwitchWords.shuffleDownloads, enabled: true, why: nil)
        case .gettingReady: return ShuffleButtonFace(words: ShuffleWords.gettingReady, enabled: false, why: nil)
        // the web's button stays "Getting ready…", aria-disabled, its title and live line saying why
        case .failed(let why): return ShuffleButtonFace(words: ShuffleWords.gettingReady, enabled: false, why: why)
        // nothing to shuffle (`total` 0), or nothing on this phone offline: no dead button
        case .nothingHere, .none: return nil
        }
    }
}
