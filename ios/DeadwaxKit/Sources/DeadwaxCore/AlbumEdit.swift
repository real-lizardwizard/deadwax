import Foundation

/// Edit album on the phone (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 3.1, 3.2, 3.7): the web's
/// ui/src/lib/albumEdit.ts, which joins the editors to an album page - which folder the album is, what the editor says
/// while it has no album to edit, choosing the folder from the scan, and following the album after a write - and
/// lib/typedMatch.ts, how typing narrows a list of folders. Held to the TypeScript by
/// Tests/DeadwaxCoreTests/Fixtures/edit/edit-vectors.json (ios/scripts/export-edit-vectors.cjs runs it as it is;
/// ui/test/iosedit.sim.cjs checks the file is current).
///
/// WHICH FOLDER. An album page knows the album by Navidrome's id; every editor works on a folder, by its path under
/// LIBRARY_PATH. The id bridge (`GET /deadwax/store/album`) answers that for an album Navidrome knows by its release -
/// the store's live folders of it (`present`); else the scan's folders of the release Navidrome reads from the files;
/// else, for an album Navidrome knows by no release, the scan's untagged folders of its name and artist (folded as the
/// search's held marks fold them), narrowed by its track count when that still leaves several - and several by name
/// alone are the person's to choose (`needsChoice`). Opened by its folder (Settings > Manage > Edit an album's Choose the
/// folder), the folder alone (`folderOnly`).
///
/// AFTER A WRITE: the page asked again at once and once more after Navidrome has had time to scan (`settleMs`); an apply
/// that changed the album's release gives it a new id in Navidrome, looked for by the new release (`followLooksMs`,
/// `followRelease`, `followsTo`) until Navidrome has it - the album page under the sheet then becomes the new id's, and
/// any page of the old id reopened later too (`noteMove`, `movedTo`).
public enum AlbumEdit {
    // MARK: the editor's parts

    /// The editors, in the web's order (`EDIT_TABS`): on the phone each a row of the editor's root, pushing its page.
    public enum Part: String, Sendable, CaseIterable, Hashable {
        case release, tags, artwork, lyrics, delete

        /// Its label (`EDIT_TABS`).
        public var label: String {
            switch self {
            case .release: return "Release"
            case .tags: return "Tags"
            case .artwork: return "Artwork"
            case .lyrics: return "Lyrics"
            case .delete: return "Delete"
            }
        }
    }

    /// `editTabs(editors, remove)`: the editors' with Edit albums, Delete with Look after the library - in this order.
    public static func parts(editors: Bool, remove: Bool) -> [Part] {
        Part.allCases.filter { $0 == .delete ? remove : editors }
    }

    /// `marksFine(perms)`: whether the editor offers "It's fine as it is" and "Ask about it again" - with Look after the
    /// library, the permission their routes need (POST /library/queue/ignore and /unignore). On the web they sit on the
    /// Release tab, Edit albums', so they need both (2.1.31's docs): the phone draws its Needs a look section only with
    /// Edit albums, and these two in it only with this as well.
    public static func marksFine(_ permissions: Set<Access.Permission>) -> Bool {
        permissions.contains(.library)
    }

    // MARK: which folder

    /// Navidrome's album, as the album page had it when Edit album was pressed (`EditAlbum`) - what finds its folder
    /// when the store can't.
    public struct Subject: Sendable, Equatable, Hashable {
        public let id: String
        public let name: String
        public let artist: String?
        public let songCount: Int?
        public let musicBrainzId: String?

        /// `editAlbum`: the artist only when there is one, the release id only when there is one once trimmed - and
        /// kept trimmed.
        public init(id: String, name: String, artist: String? = nil, songCount: Int? = nil, musicBrainzId: String? = nil) {
            self.id = id
            self.name = name
            self.artist = (artist ?? "").isEmpty ? nil : artist
            self.songCount = songCount
            let release = JSText.trim(musicBrainzId ?? "")
            self.musicBrainzId = release.isEmpty ? nil : release
        }

        /// The album page's album.
        public init(_ album: Album) {
            self.init(id: album.id, name: album.name ?? "", artist: album.artist, songCount: album.songCount,
                      musicBrainzId: album.musicBrainzId)
        }
    }

    /// What the editor reads of the id bridge's answer (`BridgeFolders`): the release, and the store's live folders.
    public struct Bridge: Sendable, Equatable {
        public let releaseMbid: String?
        public let present: [String]

        public init(releaseMbid: String?, present: [String]) {
            self.releaseMbid = releaseMbid
            self.present = present
        }

        public init(_ answer: StoreAlbum) {
            self.init(releaseMbid: answer.releaseMbid, present: answer.present.map(\.path))
        }
    }

    /// Where the folders came from (`FoldersFrom`): the store's rows of the release, the scan by the release, the scan
    /// by name (no release anywhere), the folder itself (opened by its folder), or nowhere.
    public enum From: String, Sendable, Equatable {
        case store, release, name, folder, none
    }

    /// The folders an album is (`EditFolders`).
    public struct Folders: Sendable, Equatable {
        public let paths: [String]
        public let from: From

        public init(paths: [String], from: From) {
            self.paths = paths
            self.from = from
        }

        public static let nowhere = Folders(paths: [], from: .none)
    }

    /// `editFolders(answer, albums, album)`: the bridge's answer (nil when it didn't answer), the library's scan, and
    /// Navidrome's album. See the type's note.
    public static func folders(_ answer: Bridge?, _ albums: [ScanAlbum], _ album: Subject) -> Folders {
        let present = WebText.unique((answer?.present ?? []).filter { !$0.isEmpty })
        if !present.isEmpty { return Folders(paths: present, from: .store) }

        let release = JSText.lowercase(JSText.trim(answer?.releaseMbid ?? album.musicBrainzId ?? ""))
        if !release.isEmpty {
            let tagged = albums.filter { WebText.same(JSText.lowercase(JSText.trim($0.releaseMbid)), release) }
            return tagged.isEmpty ? .nowhere : Folders(paths: tagged.map(\.path), from: .release)
        }

        let name = Fold.key(album.name)
        let artist = Fold.key(album.artist)
        if name.isEmpty { return .nowhere }
        var named = albums.filter { scanned in
            JSText.trim(scanned.releaseMbid).isEmpty && WebText.same(Fold.key(scanned.album), name)
                && (artist.isEmpty || WebText.same(Fold.key(scanned.artist), artist))
        }
        if named.count > 1, let songs = album.songCount {
            let same = named.filter { $0.trackCount == songs }
            if !same.isEmpty { named = same }
        }
        return named.isEmpty ? .nowhere : Folders(paths: named.map(\.path), from: .name)
    }

    /// `folderOnly(path)`: an album opened by its folder - that one, nothing to find or choose.
    public static func folderOnly(_ path: String) -> Folders {
        path.isEmpty ? .nowhere : Folders(paths: [path], from: .folder)
    }

    /// `needsChoice`: several found by name alone - the person says which. Several of one release (a set kept one
    /// folder per disc) start on the first, the others a choice away.
    public static func needsChoice(_ folders: Folders) -> Bool {
        folders.from == .name && folders.paths.count > 1
    }

    // MARK: choose the folder

    /// `FOLDER_CHOICES_SHOWN`: how many of the scan's folders Choose the folder lists at once.
    public static let folderChoicesShown = 50

    /// `folderChoices(albums, typed, limit)`: the scan's folders matching what was typed (every word somewhere in the
    /// folder's path, artist or album - accents and case aside), by path as JavaScript compares strings, the first
    /// `limit`, and how many match in all.
    public static func folderChoices(_ albums: [ScanAlbum], typed: String,
                                     limit: Int = folderChoicesShown) -> (shown: [ScanAlbum], matching: Int) {
        let matching = albums.enumerated()
            .filter { TypedMatch.matches("\($0.element.path) \($0.element.artist) \($0.element.album)", typed: typed) }
            .map { (key: FoldKey($0.element.path), at: $0.offset, album: $0.element) }
            .sorted { $0.key != $1.key ? $0.key < $1.key : $0.at < $1.at }
            .map(\.album)
        return (Array(matching.prefix(max(0, limit))), matching.count)
    }

    /// `folderChoicesWords(shown, matching, typed)`: what Choose the folder says over its list.
    public static func folderChoicesWords(shown: Int, matching: Int, typed: String) -> String {
        let narrowed = !JSText.trim(typed).isEmpty
        if matching == 0 {
            return narrowed ? "No folder in the library's scan matches that." : "The library's scan lists no folders."
        }
        if shown < matching {
            return "The first \(shown) of \(matching) folders\(narrowed ? " that match" : "") - type more of the folder's "
                + "name to narrow them."
        }
        return "\(matching) folder\(matching == 1 ? "" : "s")\(narrowed ? (matching == 1 ? " matches" : " match") : "") - "
            + "pick the one this album is."
    }

    // MARK: what the editor says without an album

    /// `EditStatus`: the words, and the editor's ways on - a spinner, Look again, Choose the folder.
    public struct Status: Sendable, Equatable {
        public let text: String
        public let busy: Bool
        public let retry: Bool
        public let choose: Bool

        public init(text: String, busy: Bool = false, retry: Bool = false, choose: Bool = false) {
            self.text = text
            self.busy = busy
            self.retry = retry
            self.choose = choose
        }
    }

    /// `EditStatusFacts`: what the editor knows.
    public struct StatusFacts: Sendable, Equatable {
        /// The folder just deleted, if one was.
        public var deleted: String?
        /// Why the library can't be read at all (LIBRARY_PATH unset) - not an error.
        public var problem: String?
        /// The library's last read failed - said in words already (ErrorWords).
        public var error: String?
        /// How many albums the library lists.
        public var albums: Int
        /// The library has answered at least once.
        public var loaded: Bool
        /// What is in hand is the saved scan, the real one not in yet.
        public var stale: Bool
        /// The id bridge has answered (or failed to).
        public var asked: Bool
        public var folders: Folders?
        /// An album is held, its editors drawn.
        public var holding: Bool
        /// The scan in hand lists the (one) folder - the editor is about to take it.
        public var listed: Bool
        /// The release Navidrome (or the bridge) knows the album by, if any.
        public var release: String?

        public init(deleted: String? = nil, problem: String? = nil, error: String? = nil, albums: Int = 0,
                    loaded: Bool = false, stale: Bool = false, asked: Bool = false, folders: Folders? = nil,
                    holding: Bool = false, listed: Bool = false, release: String? = nil) {
            self.deleted = deleted
            self.problem = problem
            self.error = error
            self.albums = albums
            self.loaded = loaded
            self.stale = stale
            self.asked = asked
            self.folders = folders
            self.holding = holding
            self.listed = listed
            self.release = release
        }
    }

    /// `editStatus(facts)`: what the editor says, from what it knows - nil while it has an album to edit, or the
    /// folders to choose from. An album held is being edited, so nothing a later read finds puts "can't find it" over
    /// its editors; a read that failed is said, with Look again, also when the saved scan came in and the real one
    /// didn't.
    public static func status(_ facts: StatusFacts) -> Status? {
        if let deleted = facts.deleted, !deleted.isEmpty { return Status(text: "Deleted \(deleted).") }
        if let problem = facts.problem, !problem.isEmpty { return Status(text: problem) }
        if facts.holding { return nil }
        if let error = facts.error, !error.isEmpty, facts.stale || facts.albums == 0 {
            return Status(text: error, retry: true)
        }
        if !facts.asked || !facts.loaded || facts.stale { return Status(text: finding, busy: true) }
        guard let folders = facts.folders, !folders.paths.isEmpty else {
            let release = facts.release ?? ""
            return Status(text: release.isEmpty ? notFoundByName : notFoundByRelease, retry: true, choose: true)
        }
        if needsChoice(folders) { return nil }
        if facts.listed { return Status(text: finding, busy: true) }
        return Status(text: "The library's scan doesn't list \(folders.paths[0]) yet.", retry: true)
    }

    public static let finding = "Finding the album's folder…"
    public static let notFoundByRelease = "deadwax can't find this album's folder: no folder in the library is matched "
        + "to the release Navidrome has for it. Choose the folder yourself, or look again."
    public static let notFoundByName = "deadwax can't find this album's folder: it isn't matched to a release, and no "
        + "unmatched folder in the library has its name. Choose the folder yourself, or look again."

    // MARK: after a write

    /// `EDIT_SETTLE_MS`: when the album page is asked again the second time - Navidrome's watcher waits about five
    /// seconds after files change, then scans the folder.
    public static let settleMs = 10_000

    /// `FOLLOW_LOOKS_MS`: when the album's new id is looked for after an apply changed its release - at once, then less
    /// often while Navidrome scans; about 45 s in all, then given up.
    public static let followLooksMs = [0, 3_000, 6_000, 12_000, 24_000]

    /// `followRelease(before, after)`: the release to look for the album by after an apply - its release now, when it
    /// isn't the one it had; else nil (Navidrome keeps the id of an album whose release stayed).
    public static func followRelease(before: String?, after: String?) -> String? {
        let now = JSText.lowercase(JSText.trim(after ?? ""))
        return !now.isEmpty && !WebText.same(now, JSText.lowercase(JSText.trim(before ?? ""))) ? now : nil
    }

    /// `followsTo(pageId, found)`: the id the page moves to - Navidrome's album for the release, when it has one and it
    /// isn't the page's own; else nil, and the look goes on.
    public static func followsTo(pageId: String, found: String?) -> String? {
        guard let found, !found.isEmpty, !WebText.same(found, pageId) else { return nil }
        return found
    }

    /// `noteMove(moves, from, to)`: the album of id `from` is now `to` - and `to` is live again, should an earlier move
    /// have left it.
    public static func noteMove(_ moves: inout [String: String], from: String, to: String) {
        moves[to] = nil
        if from != to { moves[from] = to }
    }

    /// `movedTo(moves, id)`: where a page of id `id` goes - the end of its moves (A to B, then B to C, is C), or nil when
    /// it never moved; a loop is followed once round and stopped.
    public static func movedTo(_ moves: [String: String], _ id: String) -> String? {
        var seen: Set<String> = [id]
        var at = id
        while let next = moves[at], !seen.contains(next) {
            seen.insert(next)
            at = next
        }
        return at == id ? nil : at
    }
}

/// Typing to narrow a list of folders (ui/src/lib/typedMatch.ts): every word typed somewhere in what is searched,
/// accents and case aside - so "sigur ros 2002" finds "Sigur Rós/( ) (2002)". Nothing typed matches everything.
public enum TypedMatch {
    /// `searchFold`: NFKD, every mark out, JavaScript's toLowerCase - nothing else folded.
    public static func fold(_ text: String?) -> String {
        let scalars = (text ?? "").decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !Fold.isMark($0) }
        return String(String.UnicodeScalarView(JSText.lowercased(Array(scalars))))
    }

    /// `matchesTyped(haystack, typed)`: the words split on JavaScript's `\s+`, each found as a run of UTF-16 units.
    public static func matches(_ haystack: String, typed: String) -> Bool {
        let words = words(fold(typed))
        if words.isEmpty { return true }
        let hay = FoldKey(fold(haystack))
        return words.allSatisfy { hay.contains(FoldKey($0)) }
    }

    /// `split(/\s+/).filter(Boolean)`.
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var word = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if WebText.isSpace(scalar) {
                if !word.isEmpty { out.append(String(word)) }
                word = String.UnicodeScalarView()
            } else {
                word.append(scalar)
            }
        }
        if !word.isEmpty { out.append(String(word)) }
        return out
    }
}
