import Foundation

// Playlists (Phase 4, notes/ios-specs/phase4-library.md 2.1-2.2) - the web app's ui/src/lib/playlists.ts, ported: which
// playlists show where, what their rows and pages say, and the words. Held to what the TypeScript answers by
// Tests/DeadwaxCoreTests/Fixtures/playlists/playlist-vectors.json, written by ios/scripts/export-playlist-vectors.cjs.
//
// The playlists are Navidrome's own, read as the person signed in (src/playlists.py says whose is whose): YOURS are
// yours and editable; SHARED WITH YOU are somebody else's public ones, read-only; FROM FILES are yours and read-only -
// a smart playlist, or one Navidrome made from an .m3u in the music folders (drawn folded, last).

// MARK: the answers (src/playlists.py summary, with_songs)

/// deadwax's summary of one playlist (`summary`, src/playlists.py:84): every field always sent, '' or 0 for what
/// Navidrome left out. Read leniently all the same: a field of an unexpected type is its empty value.
public struct Playlist: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// The description - Subsonic's `comment`; "" for none.
    public let comment: String
    /// In the list, Navidrome's stored count (songs not in the library just now included); on one playlist, the
    /// songs listed.
    public let songCount: Int
    /// Seconds.
    public let duration: Double
    public let created: String
    /// Moved by Navidrome on every add and removal - the picker's order (PlaylistRules.picker), and how a downloaded
    /// playlist is kept in step (slice 3).
    public let changed: String
    /// The owner's Navidrome user name, as Navidrome has it.
    public let owner: String
    /// Shared with everyone on the Navidrome.
    public let isPublic: Bool
    /// `pl-<id>_<hash>`, Navidrome's 2x2 mosaic - nil for an empty playlist.
    public let coverArt: String?
    /// The asker's own.
    public let mine: Bool
    /// The asker's own, and not a smart playlist or one kept in step with a file.
    public let editable: Bool
    /// (slice 3's review) One of Navidrome's smart playlists (made from rules, an `.nsp`): worked out again as it is
    /// read, so it is never downloaded (James: "No Download for them") - it plays only while deadwax can be reached.
    /// Sent by deadwax's summary() from main's 2.1.x on, read from Navidrome's playlist; false when deadwax doesn't
    /// send it, so no playlist reads as smart before then.
    public let smart: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, comment, songCount, duration, created, changed, owner
        case isPublic = "public"
        case coverArt, mine, editable, smart
    }

    public init(id: String, name: String = "", comment: String = "", songCount: Int = 0, duration: Double = 0,
                created: String = "", changed: String = "", owner: String = "", isPublic: Bool = false,
                coverArt: String? = nil, mine: Bool = false, editable: Bool = false, smart: Bool = false) {
        self.id = id
        self.name = name
        self.comment = comment
        self.songCount = songCount
        self.duration = duration
        self.created = created
        self.changed = changed
        self.owner = owner
        self.isPublic = isPublic
        self.coverArt = coverArt
        self.mine = mine
        self.editable = editable
        self.smart = smart
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        name = fields.looseField(String.self, .name) ?? ""
        comment = fields.looseField(String.self, .comment) ?? ""
        songCount = fields.looseField(Int.self, .songCount) ?? 0
        duration = fields.looseField(Double.self, .duration) ?? 0
        created = fields.looseField(String.self, .created) ?? ""
        changed = fields.looseField(String.self, .changed) ?? ""
        owner = fields.looseField(String.self, .owner) ?? ""
        isPublic = fields.looseField(Bool.self, .isPublic) ?? false
        let cover = fields.looseField(String.self, .coverArt)
        coverArt = cover?.isEmpty == false ? cover : nil
        mine = fields.looseField(Bool.self, .mine) ?? false
        editable = fields.looseField(Bool.self, .editable) ?? false
        smart = fields.looseField(Bool.self, .smart) ?? false
    }

    /// The same playlist known to be a smart one - a downloaded playlist found to be one is kept as it was (slice 3's
    /// review), its songs `songs` long.
    func asSmart(songs: Int) -> Playlist {
        Playlist(id: id, name: name, comment: comment, songCount: songs, duration: duration, created: created,
                 changed: changed, owner: owner, isPublic: isPublic, coverArt: coverArt, mine: mine, editable: editable,
                 smart: true)
    }
}

/// `GET /deadwax/navidrome/playlists`: the asker's playlists and everyone's shared ones, in Navidrome's order (by
/// name). A playlist that can't be read is left out rather than losing the list.
public struct PlaylistList: Decodable, Sendable, Equatable {
    public let playlists: [Playlist]

    enum CodingKeys: String, CodingKey {
        case playlists
    }

    public init(playlists: [Playlist]) {
        self.playlists = playlists
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        playlists = fields.looseList(Playlist.self, .playlists) ?? []
    }
}

/// `GET /deadwax/navidrome/playlists/{id}` (and what a new playlist and Edit's Done answer): one playlist with its songs -
/// Navidrome's own, as they are, a song twice listed twice - and how many of them it isn't listing just now. Encodable
/// too (slice 3): a playlist downloaded from the answer in hand is kept as it is encoded until its first read.
public struct PlaylistWithSongs: Codable, Sendable, Equatable {
    public let playlist: Playlist
    public let songs: [Song]
    /// The songs Navidrome counts but isn't listing just now (deleted, or being moved) - an editable playlist's only.
    public let hidden: Int

    enum CodingKeys: String, CodingKey {
        case playlist, songs, hidden
    }

    public init(playlist: Playlist, songs: [Song] = [], hidden: Int = 0) {
        self.playlist = playlist
        self.songs = songs
        self.hidden = hidden
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        playlist = try fields.decode(Playlist.self, forKey: .playlist)
        songs = fields.looseList(Song.self, .songs) ?? []
        hidden = max(0, fields.looseField(Int.self, .hidden) ?? 0)
    }
}

// MARK: whose, and where each shows

/// Who it is: yours (and editable), shared with you, or yours from a file.
public enum PlaylistGroup: String, Sendable, CaseIterable {
    case yours, shared, files
}

/// The Playlists screen's three groups, each in Navidrome's own order (by name).
public struct PlaylistGroups: Sendable, Equatable {
    public var yours: [Playlist] = []
    public var shared: [Playlist] = []
    public var files: [Playlist] = []

    public init(yours: [Playlist] = [], shared: [Playlist] = [], files: [Playlist] = []) {
        self.yours = yours
        self.shared = shared
        self.files = files
    }

    public subscript(_ group: PlaylistGroup) -> [Playlist] {
        switch group {
        case .yours: yours
        case .shared: shared
        case .files: files
        }
    }
}

public enum PlaylistRules {
    /// The longest name and description deadwax writes, and the most songs it edits - src/playlists.py's.
    public static let nameMax = 200
    public static let commentMax = 1000
    public static let songsMax = 2000
    /// How old the list may be before an ask that isn't `fresh` asks again (PLAYLISTS_FRESH_MS), in seconds.
    public static let freshSeconds: Double = 30
    /// How many playlist pages' answers are kept to draw a page at once as it comes back (PLAYLISTS_KEPT).
    public static let kept = 8

    /// groupOf: somebody else's is shared; yours, editable or from a file.
    public static func group(of playlist: Playlist) -> PlaylistGroup {
        if !playlist.mine { return .shared }
        return playlist.editable ? .yours : .files
    }

    /// groupPlaylists: the list cut into its groups, each in the list's order.
    /// (slice 3b, phase4-library.md 2.8) Find on the Library's Playlists page: the playlists whose name holds every word
    /// typed, in any order and anywhere in it - folded as the albums' Find folds (Find.words, Fold.findText) - in the
    /// order handed in. Nothing typed (or spaces): every one.
    public static func found(_ list: [Playlist], typed: String) -> [Playlist] {
        let words = Find.words(typed)
        if words.isEmpty { return list }
        return list.filter { (playlist: Playlist) -> Bool in
            let name = FoldKey(Fold.findText(playlist.name))
            return words.allSatisfy { name.contains($0) }
        }
    }

    public static func groups(_ list: [Playlist]) -> PlaylistGroups {
        var groups = PlaylistGroups()
        for playlist in list {
            switch group(of: playlist) {
            case .yours: groups.yours.append(playlist)
            case .shared: groups.shared.append(playlist)
            case .files: groups.files.append(playlist)
            }
        }
        return groups
    }

    // MARK: lines

    private static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    /// "12 songs"
    public static func songCount(_ n: Int) -> String { count(n, "song", "songs") }

    /// Coarse, as an album's: "48 min", "1h 5m"; "" for nothing (0, NaN). Whole minutes by Math.round.
    public static func lengthText(_ seconds: Double) -> String {
        guard JSNumber.truthy(seconds) else { return "" }
        let minutes = JSMath.round(seconds / 60)
        if minutes < 60 { return "\(JSNumber.string(minutes)) min" }
        return "\(JSNumber.string((minutes / 60).rounded(.down)))h \(JSNumber.string(minutes.truncatingRemainder(dividingBy: 60)))m"
    }

    /// A playlist page's count and length, as an album's foot says them: "12 songs, 48 min".
    public static func songsLine(_ n: Int, seconds: Double) -> String {
        let length = lengthText(seconds)
        return length.isEmpty ? songCount(n) : "\(songCount(n)), \(length)"
    }

    /// What a row on the Playlists screen says under its name.
    public static func rowLine(_ playlist: Playlist) -> String {
        let length = lengthText(playlist.duration)
        let songs = [songCount(playlist.songCount)] + (length.isEmpty ? [] : [length])
        switch group(of: playlist) {
        case .files:
            return "From a file · \(songCount(playlist.songCount))"
        case .shared:
            return ([owner(playlist) ?? "Somebody"] + songs).joined(separator: " · ")
        case .yours:
            return (songs + (playlist.isPublic ? ["Shared"] : [])).joined(separator: " · ")
        }
    }

    /// Whose it is, under a playlist page's title.
    public static func ownerLine(_ playlist: Playlist) -> String {
        switch group(of: playlist) {
        case .files: return "From a file in the music folders"
        case .shared: return "\(owner(playlist) ?? "Somebody")'s · Shared with you"
        case .yours: return playlist.isPublic ? "Yours · Shared with everyone" : "Yours"
        }
    }

    /// Why a playlist page has no Edit - nil when it has one.
    public static func readOnlyWords(_ playlist: Playlist, songs: Int) -> String? {
        switch group(of: playlist) {
        case .shared:
            return "Only \(owner(playlist) ?? "its owner") can change this playlist."
        case .files:
            return "Navidrome made this playlist from a file in the music folders - a smart playlist, or an .m3u - so it can't be changed here."
        case .yours:
            if songs > songsMax {
                return "deadwax edits playlists of up to 2,000 songs - edit this one in Amperfy or Navidrome."
            }
            return nil
        }
    }

    /// Whether a playlist page offers Edit - once its own ask has answered (PlaylistPageModel.fresh).
    public static func canEdit(_ playlist: Playlist, songs: Int) -> Bool {
        readOnlyWords(playlist, songs: songs) == nil
    }

    /// "2 songs in this playlist aren't in the library just now - deleted, or being moved." - "" for none.
    public static func hiddenWords(_ hidden: Int) -> String {
        guard hidden > 0 else { return "" }
        return "\(count(hidden, "song", "songs")) in this playlist \(hidden == 1 ? "isn't" : "aren't") in the library just now - deleted, or being moved."
    }

    /// A playlist page's length: its songs' own, summed (PlaylistPage.tsx `total`) - not the summary's.
    public static func total(_ songs: [Song]) -> Double {
        songs.reduce(0) { (sum: Double, song: Song) -> Double in sum + (song.duration ?? 0) }
    }

    /// A song row's second line on a playlist's page: its artist and its album, those it has (PlaylistPage.tsx's
    /// `[song.artist, song.album].filter(Boolean).join(' · ')`).
    public static func songLine(_ song: Song) -> String {
        [song.artist, song.album].compactMap { (part: String?) -> String? in
            guard let part, !part.isEmpty else { return nil }
            return part
        }.joined(separator: " · ")
    }

    /// The owner as `playlist.owner || ...` reads it: nil for none.
    private static func owner(_ playlist: Playlist) -> String? {
        playlist.owner.isEmpty ? nil : playlist.owner
    }
}

/// The words of the Playlists screen and a playlist's page: the web's lib/playlists.ts constants (held to the
/// fixture), the TSX's own (copied, their source named), and the phone's own for what the web hasn't (offline - the
/// spec's 1.2). Slice 2's - the picker's, New playlist's, Edit's and Delete's - are in PlaylistChanges.swift.
public enum PlaylistWords {
    // lib/playlists.ts
    public static let playlistsEmpty = "No playlists yet."
    public static let playlistsEmptyHow = "Make one here, or start one from a song's or an album's ••• menu, or from Now Playing: Add to a playlist."
    public static let playlistEmpty = "Nothing in this playlist yet. Add songs from a song's or an album's ••• menu - Add to a playlist - or from Now Playing's ••• while a song plays."
    public static let playlistGone = "This playlist isn't on Navidrome any more - deleted in another app, maybe."

    /// "Couldn't list your playlists. <why>" - `why` a listener's words (ErrorWords' sentence and advice).
    public static func listFailed(_ why: String) -> String { "Couldn't list your playlists. \(why)" }

    // PlaylistsPage.tsx
    public static let title = "Playlists"
    public static let yours = "Yours"
    public static let shared = "Shared with you"
    /// The folded group's row: "From files (3)".
    public static func files(_ n: Int) -> String { "From files (\(n))" }

    // PlaylistPage.tsx
    /// "Couldn't open this playlist. <why>" - nothing in hand and the first ask failed.
    public static func openFailed(_ why: String) -> String { "Couldn't open this playlist. \(why)" }
    /// "Couldn't update this playlist - showing it as it was. <why>" - a refresh that failed.
    public static func refreshFailed(_ why: String) -> String { "Couldn't update this playlist - showing it as it was. \(why)" }
    public static let tryAgain = "Try again"
    public static let play = "Play"
    public static let shuffle = "Shuffle"
    /// The bar's ••• button's name.
    public static let moreForPlaylist = "More for this playlist"
    /// The spinner's name while the playlist loads.
    public static let loading = "Loading"

    // the phone's own (the spec's 1.2): deadwax out of reach
    /// The Playlists screen with no list in hand while deadwax can't be reached.
    public static let offlineList = "Your playlists show here once deadwax is back."
    /// A playlist's page with nothing in hand while deadwax can't be reached.
    public static let offlinePage = "This playlist opens once deadwax is back."
}
