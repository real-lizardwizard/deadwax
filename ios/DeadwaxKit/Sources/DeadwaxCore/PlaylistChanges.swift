import Foundation

// Changing playlists (Phase 4, slice 2, notes/ios-specs/phase4-library.md 2.4) - the web app's ui/src/lib/playlists.ts,
// its adding and editing halves, ported: which playlists the picker offers and in what order, what an add and a made
// playlist say, the question when some songs are in the playlist already, Edit's rows and the one body its Done sends,
// and the words. Held to the TypeScript by Tests/DeadwaxCoreTests/Fixtures/playlists/playlist-vectors.json
// (ios/scripts/export-playlist-vectors.cjs).
//
// Every write is deadwax's (src/routes/navidrome.py's create, add, edit and delete), asked as the person signed in: the
// owner check is the server's, and the phone only reads a playlist's `editable`. Navidrome has no undo, and neither
// has deadwax: nothing here is optimistic - the app draws what an answer says.

// MARK: what the writes send (src/routes/navidrome.py NewPlaylist, PlaylistAdd, PlaylistEdit - each extra="forbid")

/// What an add does with songs the playlist has already: `ask` writes nothing and says how many (the question),
/// `add` adds every one, `skip` only the others.
public enum PlaylistDuplicates: String, Codable, Sendable, CaseIterable {
    case ask, add, skip
}

/// `POST /deadwax/navidrome/playlists`: a new playlist of the asker's, with the songs given (none from the Playlists
/// screen's New playlist, the songs in hand from the picker's). The name is sent trimmed; the server trims again and
/// refuses a blank one.
public struct NewPlaylistBody: Encodable, Sendable, Equatable {
    public let name: String
    public let songIds: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case songIds = "song_ids"
    }

    public init(name: String, songIds: [String]) {
        self.name = name
        self.songIds = songIds
    }
}

/// `POST /deadwax/navidrome/playlists/{id}/add`: the songs (at least one), added at the end.
public struct PlaylistAddBody: Encodable, Sendable, Equatable {
    public let songIds: [String]
    public let duplicates: PlaylistDuplicates

    enum CodingKeys: String, CodingKey {
        case songIds = "song_ids"
        case duplicates
    }

    public init(songIds: [String], duplicates: PlaylistDuplicates) {
        self.songIds = songIds
        self.duplicates = duplicates
    }
}

/// `POST /deadwax/navidrome/playlists/{id}/edit` - Edit's Done (the web's PlaylistEditBody): the songs as drawn when
/// Edit began (`base`), the songs now, and only the name, description and sharing that changed - nil is left out of
/// the JSON, unchanged. `tried`: the songs a Done that FAILED sent (Navidrome may have taken them before failing), so
/// the next Done finding them there isn't taken for a change made in another app - sent only after one.
public struct PlaylistEditBody: Encodable, Sendable, Equatable {
    public let base: [String]
    public let songIds: [String]
    public let tried: [String]?
    public let name: String?
    public let comment: String?
    public let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case base
        case songIds = "song_ids"
        case tried, name, comment
        case isPublic = "public"
    }

    public init(base: [String], songIds: [String], tried: [String]? = nil, name: String? = nil,
                comment: String? = nil, isPublic: Bool? = nil) {
        self.base = base
        self.songIds = songIds
        self.tried = tried
        self.name = name
        self.comment = comment
        self.isPublic = isPublic
    }

    /// The same body sent after a Done that failed: `tried` the songs that one sent (nil: none failed).
    public func trying(_ tried: [String]?) -> PlaylistEditBody {
        PlaylistEditBody(base: base, songIds: songIds, tried: tried, name: name, comment: comment, isPublic: isPublic)
    }

    /// (slice 3's review) The songs this Edit took out: in `base` and nowhere in the songs now - a song listed twice and
    /// taken out once is still in it. A downloaded playlist lets these go at once, and only these (a song Navidrome is
    /// hiding is missing from Done's answer too, and isn't the Edit's).
    public var removed: Set<String> { Set(base).subtracting(songIds) }
}

// MARK: what they answer

/// What an add came to (the web's AddAnswer): written (`done`, with how many were `added`) - or, asked to ask, some
/// there `already` and NOTHING written (`asked`: how many songs were asked about).
public struct PlaylistAddAnswer: Decodable, Sendable, Equatable {
    public let done: Bool
    public let already: Int
    public let added: Int?
    public let asked: Int?

    enum CodingKeys: String, CodingKey {
        case done, already, added, asked
    }

    public init(done: Bool, already: Int = 0, added: Int? = nil, asked: Int? = nil) {
        self.done = done
        self.already = already
        self.added = added
        self.asked = asked
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        done = try fields.decode(Bool.self, forKey: .done)
        already = max(0, fields.looseField(Int.self, .already) ?? 0)
        added = fields.looseField(Int.self, .added)
        asked = fields.looseField(Int.self, .asked)
    }
}

/// `POST .../{id}/delete`'s answer: `{"deleted": true}`.
public struct PlaylistDeleted: Decodable, Sendable, Equatable {
    public let deleted: Bool
}

// MARK: what the picker adds

/// What the picker was opened with (the web's PlaylistPick): one song, or an album's or a playlist's songs - in hand,
/// with what they are called. A song's ••• and Now Playing's give one song; an album's or a playlist's ••• its songs.
public struct PlaylistPick: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let id: String
        public let title: String
        /// nil or "" for none - pickLine leaves it out either way.
        public let artist: String?

        public init(id: String, title: String, artist: String? = nil) {
            self.id = id
            self.title = title
            self.artist = artist
        }
    }

    /// The album's or playlist's name, or the song's title.
    public let label: String
    public let songs: [Entry]

    public init(label: String, songs: [Entry]) {
        self.label = label
        self.songs = songs
    }

    /// A queue menu's songs (QueuePick's label and songs, as App.tsx's queueToPlaylist maps them).
    public init(_ pick: QueuePick<Song>) {
        self.init(label: pick.label, songs: pick.tracks.map { (song: Song) -> Entry in
            Entry(id: song.id, title: song.title ?? "", artist: song.artist)
        })
    }

    /// The song playing (App.tsx's playingPick): Now Playing's •••.
    public init(playing track: QueueTrack) {
        self.init(label: track.title, songs: [Entry(id: track.id, title: track.title, artist: track.artist)])
    }

    /// The songs' ids, in order - what the add and the new playlist send.
    public var ids: [String] { songs.map(\.id) }
}

/// The question when some of the songs are in the playlist already (the web's duplicateQuestion): its words, and its
/// two buttons - what each sends. `no.mode` nil: back to the list, nothing sent.
public struct PlaylistQuestion: Sendable, Equatable {
    public struct Choice: Sendable, Equatable {
        public let label: String
        public let mode: PlaylistDuplicates?

        public init(label: String, mode: PlaylistDuplicates?) {
            self.label = label
            self.mode = mode
        }
    }

    public let text: String
    /// Always `add`.
    public let yes: Choice
    /// `skip`, or nil (Cancel).
    public let no: Choice

    public init(text: String, yes: Choice, no: Choice) {
        self.text = text
        self.yes = yes
        self.no = no
    }
}

/// What an add's answer comes to (PlaylistPicker.tsx's `add`): nothing written - some there already - and the question
/// asked (`already` of `asked`), or written and what the notice says.
public enum PlaylistAddOutcome: Sendable, Equatable {
    case asks(already: Int, asked: Int)
    case added(String)
}

extension PlaylistRules {
    /// An add answered: the question (`asked` the answer's, else the songs sent), or the notice's words.
    public static func outcome(of answer: PlaylistAddAnswer, mode: PlaylistDuplicates, pick: PlaylistPick,
                               name: String) -> PlaylistAddOutcome {
        guard answer.done else { return .asks(already: answer.already, asked: answer.asked ?? pick.songs.count) }
        return .added(addedWords(added: answer.added ?? 0, already: answer.already, mode: mode, pick: pick, name: name))
    }

    /// pickerPlaylists: the ones you can add to - yours and editable - the one changed last first (Navidrome moves
    /// `changed` on every add and removal, so the one you last added to is on top), ties by name.
    ///
    /// `changed` is compared as JavaScript compares strings, by UTF-16 code unit. A tie's name is the web's
    /// `localeCompare` - ICU's collation, which nothing here has on Linux - taken as Fold's (case and accents
    /// folded, compared by code unit), then the names as written, then the list's own order (the web's sort is
    /// stable): the same for every pair of names that differ by more than case or accents alone.
    public static func picker(_ list: [Playlist]) -> [Playlist] {
        let yours = list.enumerated().filter { (_: Int, playlist: Playlist) -> Bool in playlist.mine && playlist.editable }
        return yours.sorted { (a: (offset: Int, element: Playlist), b: (offset: Int, element: Playlist)) -> Bool in
            let (one, other) = (a.element, b.element)
            if one.changed != other.changed { return FoldKey(other.changed) < FoldKey(one.changed) }
            let folded = (FoldKey(Fold.findText(one.name)), FoldKey(Fold.findText(other.name)))
            if folded.0 != folded.1 { return folded.0 < folded.1 }
            if one.name != other.name { return FoldKey(one.name) < FoldKey(other.name) }
            return a.offset < b.offset
        }.map { (pair: (offset: Int, element: Playlist)) -> Playlist in pair.element }
    }

    /// Edit's note of the songs not listed just now: what Done does to them if the songs change - "" for none.
    public static func hiddenEditWords(_ hidden: Int) -> String {
        guard hidden > 0 else { return "" }
        return "\(songCount(hidden)) that \(hidden == 1 ? "isn't" : "aren't") in the library just now will be dropped if you change the songs."
    }

    /// Delete's question.
    public static func deleteQuestion(_ name: String) -> String {
        "Delete \"\(name)\"? It goes from Navidrome for good - from Amperfy and every other app too, and for everyone it's shared with. The songs stay in the library."
    }

    /// The picker's line of what it is adding: "Roads · Portishead", or "Dummy · 11 songs".
    public static func pickLine(_ pick: PlaylistPick) -> String {
        if pick.songs.count == 1, let first = pick.songs.first {
            guard let artist = first.artist, !artist.isEmpty else { return first.title }
            return "\(first.title) · \(artist)"
        }
        return "\(pick.label) · \(songCount(pick.songs.count))"
    }

    /// What the songs are called in a sentence: the one song's title, or "11 songs".
    static func what(_ pick: PlaylistPick, _ n: Int) -> String {
        pick.songs.count == 1 && n == 1 ? pick.songs[0].title : songCount(n)
    }

    /// What became of an add that was written, in the app's notice.
    public static func addedWords(added: Int, already: Int, mode: PlaylistDuplicates, pick: PlaylistPick,
                                  name: String) -> String {
        if added <= 0 {
            if pick.songs.count == 1 { return "Nothing added - \(pick.songs[0].title) is in \(name) already" }
            return "Nothing added - they're all in \(name) already"
        }
        if mode == .skip && already > 0 {
            return "Added \(what(pick, added)) to \(name) - \(already) \(already == 1 ? "was" : "were") in it already"
        }
        return "Added \(what(pick, added)) to \(name)"
    }

    /// What a playlist made from the picker says: "Made Late night with Roads".
    public static func madeWords(_ name: String, pick: PlaylistPick) -> String {
        "Made \(name) with \(what(pick, pick.songs.count))"
    }

    /// The question when `already` of the `asked` songs are in the playlist already.
    public static func duplicateQuestion(already: Int, asked: Int, pick: PlaylistPick, name: String) -> PlaylistQuestion {
        if asked == 1 {
            return PlaylistQuestion(text: "\(pick.songs.first?.title ?? "That song") is in \(name) already.",
                                    yes: .init(label: "Add it again", mode: .add), no: .init(label: "Cancel", mode: nil))
        }
        if already >= asked {
            return PlaylistQuestion(text: "These \(asked) songs are all in \(name) already.",
                                    yes: .init(label: "Add them again", mode: .add), no: .init(label: "Cancel", mode: nil))
        }
        return PlaylistQuestion(
            text: "\(already) of these \(asked) songs \(already == 1 ? "is" : "are") in \(name) already.",
            yes: .init(label: "Add them all", mode: .add),
            no: .init(label: already == 1 ? "Skip that one" : "Skip those \(already)", mode: .skip))
    }
}

// MARK: Edit

/// A row of Edit's list: keyed by the place its song had when Edit began ("3:so-1"), so a song in twice is two rows.
public struct PlaylistEditRow: Sendable, Equatable, Hashable {
    public let key: String
    /// The song's id - the same on both rows of a song in twice.
    public let id: String
    public let title: String
    public let artist: String

    public init(key: String, id: String, title: String, artist: String) {
        self.key = key
        self.id = id
        self.title = title
        self.artist = artist
    }
}

/// What Edit holds (the web's EditState): the rows, and the name, description and sharing as typed.
public struct PlaylistEditState: Sendable, Equatable {
    public var rows: [PlaylistEditRow]
    public var name: String
    public var comment: String
    public var isPublic: Bool

    public init(rows: [PlaylistEditRow], name: String, comment: String, isPublic: Bool) {
        self.rows = rows
        self.name = name
        self.comment = comment
        self.isPublic = isPublic
    }
}

/// Edit's rules (lib/playlists.ts startEdit ... isRearrangement): what it begins with, a row moved or taken out, and
/// the one body Done sends.
public enum PlaylistEdit {
    /// startEdit: the songs as drawn, and the playlist's name, description and sharing.
    public static func start(songs: [Song], playlist: Playlist) -> PlaylistEditState {
        let rows = songs.enumerated().map { (index: Int, song: Song) -> PlaylistEditRow in
            PlaylistEditRow(key: "\(index):\(song.id)", id: song.id, title: song.title ?? "", artist: song.artist ?? "")
        }
        return PlaylistEditState(rows: rows, name: playlist.name, comment: playlist.comment, isPublic: playlist.isPublic)
    }

    /// moveRow: the row at `from` moved to `to` (clamped to the rows); the same rows when it doesn't move.
    public static func move(_ rows: [PlaylistEditRow], from: Int, to: Int) -> [PlaylistEditRow] {
        let target = max(0, min(rows.count - 1, to))
        guard from >= 0, from < rows.count, target != from else { return rows }
        var next = rows
        let row = next.remove(at: from)
        next.insert(row, at: target)
        return next
    }

    /// removeRow: every row but the one at `index`.
    public static func remove(_ rows: [PlaylistEditRow], at index: Int) -> [PlaylistEditRow] {
        rows.enumerated().filter { (at: Int, _: PlaylistEditRow) -> Bool in at != index }
            .map { (pair: (offset: Int, element: PlaylistEditRow)) -> PlaylistEditRow in pair.element }
    }

    /// editChanged: whether Edit has changed anything since it began.
    public static func changed(start: PlaylistEditState, now: PlaylistEditState) -> Bool {
        body(start: start, now: now) != nil
    }

    /// editBody: what Done sends - `base` (the songs as drawn when Edit began), the songs now, and only the metadata
    /// that changed, trimmed as JavaScript trims ("" for a description cleared). Nil when nothing changed: a row moved
    /// back where it was is no change, and neither is a name given back its own spaces.
    public static func body(start: PlaylistEditState, now: PlaylistEditState) -> PlaylistEditBody? {
        let base = start.rows.map(\.id)
        let songIds = now.rows.map(\.id)
        let songsChanged = now.rows.count != start.rows.count
            || now.rows.enumerated().contains { (at: Int, row: PlaylistEditRow) -> Bool in
                !start.rows.indices.contains(at) || row.key != start.rows[at].key
            }
        let name = WebText.trim(now.name)
        let comment = WebText.trim(now.comment)
        let newName: String? = name != WebText.trim(start.name) ? name : nil
        let newComment: String? = comment != WebText.trim(start.comment) ? comment : nil
        let newPublic: Bool? = now.isPublic != start.isPublic ? now.isPublic : nil
        guard songsChanged || newName != nil || newComment != nil || newPublic != nil else { return nil }
        return PlaylistEditBody(base: base, songIds: songIds, name: newName, comment: newComment, isPublic: newPublic)
    }

    /// What a refused Done means (PlaylistPage.tsx `done`): a 409 - the playlist changed in another app since Edit began,
    /// or grew past what deadwax edits - nothing saved, drawn as it is now; a 404, gone; anything else, Edit stays open
    /// with why, and the next Done sends `tried` (the songs this one sent).
    public enum Refusal: Sendable, Equatable {
        case changedElsewhere, gone, refused
    }

    public static func refusal(of error: any Error) -> Refusal {
        switch (error as? APIFailure)?.answer?.status {
        case 409?: return .changedElsewhere
        case 404?: return .gone
        default: return .refused
        }
    }

    /// isRearrangement: whether `next` only removes and reorders `base`'s songs - src/playlists.py's rule, mirrored.
    public static func isRearrangement(base: [String], next: [String]) -> Bool {
        var have: [String: Int] = [:]
        for id in base { have[id, default: 0] += 1 }
        for id in next {
            let left = have[id] ?? 0
            if left <= 0 { return false }
            have[id] = left - 1
        }
        return true
    }

    /// The name is blank as typed (Done waits for one - NEEDS_A_NAME).
    public static func needsName(_ state: PlaylistEditState) -> Bool {
        trimmed(state.name).isEmpty
    }

    /// Typed text as the web sends it - JavaScript's trim (New playlist's name; Done's name and description).
    public static func trimmed(_ text: String) -> String {
        WebText.trim(text)
    }

    /// A field's text after a keystroke or a paste, `was` the text before it, kept within `max` UTF-16 code units as an
    /// HTML field's maxLength keeps it (PLAYLIST_NAME_MAX, PLAYLIST_COMMENT_MAX - the server's own bound, in code
    /// points, never met): text within the bound, or no longer than it was, taken as it is - a name already over it is
    /// never cut, and can be cut down by hand; text that grows past it keeps what was there and takes only as much of
    /// what was put in as fits, at a character's edge - nothing, when nothing does.
    public static func typed(_ text: String, was old: String, max: Int) -> String {
        let units = text.utf16.count
        guard units > max, units > old.utf16.count else { return text }
        // what was put in: between what the two share at the start and at the end
        let before = Array(old)
        let after = Array(text)
        var head = 0
        while head < before.count, head < after.count, before[head] == after[head] { head += 1 }
        var tail = 0
        while tail < before.count - head, tail < after.count - head,
              before[before.count - 1 - tail] == after[after.count - 1 - tail] { tail += 1 }
        let lead = String(before[..<head])
        let rest = String(before[(before.count - tail)...])
        let room = max - lead.utf16.count - rest.utf16.count
        guard room > 0 else { return old }
        let put = clamped(String(after[head..<(after.count - tail)]), to: room)
        guard !put.isEmpty else { return old }
        return lead + put + rest
    }

    /// Text cut to `max` UTF-16 code units, at a character's edge (`typed`'s cut of what was put in).
    public static func clamped(_ text: String, to max: Int) -> String {
        guard text.utf16.count > max else { return text }
        var kept = ""
        var units = 0
        for character in text {
            let size = character.utf16.count
            if units + size > max { break }
            kept.append(character)
            units += size
        }
        return kept
    }
}

extension PlaylistWords {
    // lib/playlists.ts
    public static let playlistChanged = "This playlist changed in another app while you were editing it - here it is now. Your changes weren't saved."
    public static let sharedNote = "Everyone with an account on this Navidrome can find it and play it - in deadwax, Navidrome and their other apps. Only you can change it."
    public static let needsAName = "A playlist needs a name."
    public static let discardQuestion = "Discard your changes?"

    // PlaylistPicker.tsx
    /// The picker's title.
    public static let addToAPlaylist = "Add to a playlist"
    public static let newPlaylistRow = "New playlist…"
    public static let noPlaylistsYet = "No playlists yet - make one:"
    public static let adding = "Adding…"
    /// The picker's add answered with the sheet closed, some there already and nothing written.
    public static func someAlready(_ name: String) -> String { "Nothing added - some are in \(name) already" }
    /// The picker's add refused with the sheet closed: "Couldn't add to Late night." - the why after it.
    public static func couldntAdd(_ name: String) -> String { "Couldn't add to \(name)." }

    // QueueMenu.tsx
    /// The ••• menus' row.
    public static let addToAPlaylistRow = "Add to a playlist…"
    /// Its symbol - Apple Music's for its own Add to a Playlist (SF Symbols, iOS 14.0).
    public static let addSymbol = "text.badge.plus"

    // NewPlaylistForm.tsx
    public static let nameField = "Name"
    public static let create = "Create"
    public static let creating = "Creating…"
    public static let cancel = "Cancel"

    // PlaylistsPage.tsx
    public static let newPlaylist = "New playlist"
    /// A playlist made from the Playlists screen, said when the screen was left before it answered.
    public static func made(_ name: String) -> String { "Made \(name)" }

    // PlaylistPage.tsx
    public static let edit = "Edit"
    public static let done = "Done"
    public static let saving = "Saving…"
    public static let descriptionField = "Description"
    public static let sharedWithEveryone = "Shared with everyone"
    public static let discard = "Discard"
    public static let keepEditing = "Keep editing"
    public static let deletePlaylist = "Delete playlist"
    public static let keepIt = "Keep it"
    public static let deleting = "Deleting…"

    // App.tsx playlistDeleted
    public static func deleted(_ name: String) -> String { "Deleted \(name)" }

    // the phone's own: the sheet the Playlists screen's New playlist opens, and Edit's list of songs
    /// The sheet's title (the web's form opens in place, with no title of its own).
    public static let newPlaylistTitle = "New playlist"
    /// The heading over Edit's rows.
    public static let songsHeading = "Songs"
}
