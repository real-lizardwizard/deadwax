import Foundation

/// What is new in your library - the Library's New marks (ui/src/lib/myLibrary.ts `newMarks`, `isNew`): the
/// Navidrome album ids, and the release ids lowercased, of `GET /me/library`'s `new`. Compared as JavaScript compares
/// strings (code units), as the web's Sets do.
public struct NewMarks: Sendable, Equatable {
    let ids: Set<[UInt16]>
    let releases: Set<[UInt16]>

    /// `newMarks(answer)` - none for no answer.
    public init(_ answer: MyLibrary?) {
        var ids = Set<[UInt16]>()
        var releases = Set<[UInt16]>()
        for entry in answer?.new ?? [] {
            if let id = entry.navidromeID, !id.isEmpty { ids.insert(Array(id.utf16)) }
            if let release = entry.releaseMBID, !release.isEmpty { releases.insert(Array(JSText.lowercase(release).utf16)) }
        }
        self.ids = ids
        self.releases = releases
    }

    public var isEmpty: Bool { ids.isEmpty && releases.isEmpty }

    /// `isNew`: an album is new in your library by its Navidrome id, or by the release it is (its MusicBrainz id
    /// trimmed and lowercased, whatever its case).
    public func isNew(id: String, musicBrainzId: String?) -> Bool {
        if ids.contains(Array(id.utf16)) { return true }
        let release = NewMarks.release(musicBrainzId)
        return !release.isEmpty && releases.contains(release)
    }

    public func isNew(_ album: IndexAlbum) -> Bool { isNew(id: album.id, musicBrainzId: album.musicBrainzId) }

    /// An album's release as the marks compare it: trimmed, lowercased, as code units.
    static func release(_ musicBrainzId: String?) -> [UInt16] {
        Array(JSText.lowercase(JSText.trim(musicBrainzId ?? "")).utf16)
    }
}

/// Your library as the app keeps it between answers (ui/src/app/useMyLibrary.ts), as a value: the last answer, and
/// what opening an album does - "cleared when you open it". An album new in your library, opened, is taken off the
/// marks at once and deadwax is told (by its release, else by the store's ids of the entries it clears); one opened
/// before deadwax first said is remembered (the last `openedKept`) and looked at as the first answer lands.
public struct MyLibraryState: Sendable, Equatable {
    /// OPENED_KEPT
    public static let openedKept = 20

    /// An album page as it opened: its Navidrome id and its release, when known.
    public struct Opened: Sendable, Equatable {
        public let id: String
        public let musicBrainzId: String?

        public init(id: String, musicBrainzId: String? = nil) {
            self.id = id
            self.musicBrainzId = musicBrainzId
        }
    }

    /// The newest answer - nil until deadwax has first said (and always, with logins off).
    public private(set) var answer: MyLibrary?
    public private(set) var openedBefore: [Opened] = []

    public init() {}

    /// The marks the Library draws.
    public var marks: NewMarks { NewMarks(answer) }

    /// An answer landed - the newest (the caller lets only the newest through, as latestOnly does): kept, and the
    /// albums opened before any answer looked at, as `opened` looks (`personal`: whether there is a library of your
    /// own now). What to tell deadwax, in order (`POST /me/library/seen`).
    public mutating func landed(_ answer: MyLibrary, personal: Bool = true) -> [SeenBody] {
        self.answer = answer
        let before = openedBefore
        openedBefore = []
        var told: [SeenBody] = []
        for album in before {
            if let body = opened(album, personal: personal) { told.append(body) }
        }
        return told
    }

    /// `seenAlbum`: an album page opened. What to tell deadwax - nil for an album that isn't new, with no library
    /// of your own (`personal` false: logins off, the break-glass admin), or before deadwax has first said (it is
    /// remembered and looked at then).
    public mutating func opened(_ album: Opened, personal: Bool) -> SeenBody? {
        guard personal else { return nil }
        guard var answer = self.answer else {
            let id = Array(album.id.utf16)
            if !openedBefore.contains(where: { Array($0.id.utf16) == id }) {
                openedBefore = Array((openedBefore + [album]).suffix(Self.openedKept))
            }
            return nil
        }
        guard NewMarks(answer).isNew(id: album.id, musicBrainzId: album.musicBrainzId) else { return nil }
        let release = NewMarks.release(album.musicBrainzId)
        let id = Array(album.id.utf16)
        func clears(_ entry: LibraryEntry) -> Bool {
            if let navidrome = entry.navidromeID, Array(navidrome.utf16) == id { return true }
            return !release.isEmpty && Array(JSText.lowercase(entry.releaseMBID ?? "").utf16) == release
        }
        let new = answer.new ?? []
        let cleared = new.filter(clears)
        answer.new = new.filter { !clears($0) }
        self.answer = answer
        if !release.isEmpty { return .release(String(decoding: release, as: UTF16.self)) }
        return .albums(cleared.map(\.albumID))
    }

    /// Everything forgotten - sign-out, sign-in, another server.
    public mutating func clear() {
        answer = nil
        openedBefore = []
    }
}

/// Your albums asked again when your library's starred count moves (player/Library.tsx): the starring worker done,
/// a star read back from Amperfy. Fed every `GET /me/library` answer; true when the `yours` list must be forgotten.
public struct StarredCountWatch: Sendable, Equatable {
    public private(set) var seen: Int?

    public init() {}

    public mutating func saw(_ answer: MyLibrary?) -> Bool {
        guard let answer, answer.on, answer.kept == true, let starred = answer.starred else { return false }
        defer { seen = starred }
        return seen != nil && seen != starred
    }
}
