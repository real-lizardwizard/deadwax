import Foundation

// What deadwax already has of a pressing (Phase 6, slice 2 - notes/ios-specs/phase6-get-requests.md 2.9): the store
// line under Get the album, and the box and notes in the Sources sheet. The answers of POST /deadwax/download/store_state
// (and find_candidates' same four fields), and the web's words for them - lib/candidates.ts storeStatus, storeNotes and
// their parts, lib/perPerson.ts storeStatusFor, withoutJoin and the quality floor's word - ported to the character and
// held to them by Fixtures/get/get-vectors.json (GetVectorTests).

/// A pressing the library holds, whole or in part (`HeldPressing`, src/store_index.py held_copy).
public struct HeldPressing: Decodable, Sendable, Equatable {
    public let path: String
    /// Every folder, for a set stored one folder per disc - nil from an older server.
    public let paths: [String]?
    public let artist: String
    public let album: String
    public let edition: String
    public let trackCount: Int
    /// 0 when no tracklist was sent to count against.
    public let expectedTracks: Int
    public let formats: [String]?
    public let complete: Bool
    /// (a part held) whether a download fills in the folder it files into, and which folder that is.
    public let fillsGaps: Bool?
    public let filedTo: String?
    /// (logins on) whether it is in the asker's library - nil when deadwax didn't say.
    public let yours: Bool?

    public init(path: String, paths: [String]? = nil, artist: String = "", album: String = "", edition: String = "",
                trackCount: Int, expectedTracks: Int, formats: [String]? = nil, complete: Bool, fillsGaps: Bool? = nil,
                filedTo: String? = nil, yours: Bool? = nil) {
        self.path = path
        self.paths = paths
        self.artist = artist
        self.album = album
        self.edition = edition
        self.trackCount = trackCount
        self.expectedTracks = expectedTracks
        self.formats = formats
        self.complete = complete
        self.fillsGaps = fillsGaps
        self.filedTo = filedTo
        self.yours = yours
    }

    enum CodingKeys: String, CodingKey {
        case path, paths, artist, album, edition, formats, complete, yours
        case trackCount = "track_count"
        case expectedTracks = "expected_tracks"
        case fillsGaps = "fills_gaps"
        case filedTo = "filed_to"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        path = fields.looseField(String.self, .path) ?? ""
        paths = fields.looseList(String.self, .paths)
        artist = fields.looseField(String.self, .artist) ?? ""
        album = fields.looseField(String.self, .album) ?? ""
        edition = fields.looseField(String.self, .edition) ?? ""
        trackCount = fields.looseField(Int.self, .trackCount) ?? 0
        expectedTracks = fields.looseField(Int.self, .expectedTracks) ?? 0
        formats = fields.looseList(String.self, .formats)
        complete = fields.looseField(Bool.self, .complete) ?? false
        fillsGaps = fields.looseField(Bool.self, .fillsGaps)
        filedTo = fields.looseField(String.self, .filedTo)
        yours = fields.looseField(Bool.self, .yours)
    }

    /// Its folders: every one of a set stored one folder per disc, else its one.
    var folders: [String] { (paths ?? []).isEmpty ? [path] : paths ?? [] }
}

/// A download of the pressing in flight (`DownloadInFlight`, routes/download.py `_describe_in_flight`): the job, how far
/// it has got, and - logins on - whose it is and what its copy is.
public struct DownloadInFlight: Decodable, Sendable, Equatable {
    public let jobId: Int
    public let status: String
    public let username: String
    public let files: Int
    /// How many have arrived - nil when slskd wouldn't say (the server leaves it out).
    public let doneFiles: Int?
    public let yours: Bool?
    public let shared: Bool?
    /// (an admin's) who else asked.
    public let requestedBy: [String]?
    public let formats: [String]?
    public let bitrates: [Double]?
    public let bitDepths: [Double]?
    public let sampleRates: [Double]?
    public let variableBitrate: Bool?

    public init(jobId: Int, status: String, username: String, files: Int, doneFiles: Int? = nil, yours: Bool? = nil,
                shared: Bool? = nil, requestedBy: [String]? = nil, formats: [String]? = nil, bitrates: [Double]? = nil,
                bitDepths: [Double]? = nil, sampleRates: [Double]? = nil, variableBitrate: Bool? = nil) {
        self.jobId = jobId
        self.status = status
        self.username = username
        self.files = files
        self.doneFiles = doneFiles
        self.yours = yours
        self.shared = shared
        self.requestedBy = requestedBy
        self.formats = formats
        self.bitrates = bitrates
        self.bitDepths = bitDepths
        self.sampleRates = sampleRates
        self.variableBitrate = variableBitrate
    }

    enum CodingKeys: String, CodingKey {
        case status, username, files, yours, shared, formats, bitrates
        case jobId = "job_id"
        case doneFiles = "done_files"
        case requestedBy = "requested_by"
        case bitDepths = "bit_depths"
        case sampleRates = "sample_rates"
        case variableBitrate = "variable_bitrate"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        jobId = fields.looseField(Int.self, .jobId) ?? 0
        status = fields.looseField(String.self, .status) ?? ""
        username = fields.looseField(String.self, .username) ?? ""
        files = fields.looseField(Int.self, .files) ?? 0
        doneFiles = fields.looseField(Int.self, .doneFiles)
        yours = fields.looseField(Bool.self, .yours)
        shared = fields.looseField(Bool.self, .shared)
        requestedBy = fields.looseList(String.self, .requestedBy)
        formats = fields.looseList(String.self, .formats)
        bitrates = fields.looseList(Double.self, .bitrates)
        bitDepths = fields.looseList(Double.self, .bitDepths)
        sampleRates = fields.looseList(Double.self, .sampleRates)
        variableBitrate = fields.looseField(Bool.self, .variableBitrate)
    }
}

/// Another pressing of the album the library holds (`OtherPressing`).
public struct OtherPressing: Decodable, Sendable, Equatable {
    public let path: String
    public let releaseMbid: String?
    public let edition: String
    public let year: String
    public let trackCount: Int
    public let formats: [String]
    public let yours: Bool?

    public init(path: String, releaseMbid: String? = nil, edition: String = "", year: String = "", trackCount: Int = 0,
                formats: [String] = [], yours: Bool? = nil) {
        self.path = path
        self.releaseMbid = releaseMbid
        self.edition = edition
        self.year = year
        self.trackCount = trackCount
        self.formats = formats
        self.yours = yours
    }

    enum CodingKeys: String, CodingKey {
        case path, edition, year, formats, yours
        case releaseMbid = "release_mbid"
        case trackCount = "track_count"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        path = fields.looseField(String.self, .path) ?? ""
        releaseMbid = fields.looseField(String.self, .releaseMbid)
        edition = fields.looseField(String.self, .edition) ?? ""
        year = fields.looseField(String.self, .year) ?? ""
        trackCount = fields.looseField(Int.self, .trackCount) ?? 0
        formats = fields.looseList(String.self, .formats) ?? []
        yours = fields.looseField(Bool.self, .yours)
    }
}

/// `POST /deadwax/download/store_state` - and the same four fields of a find_candidates answer.
public struct StoreStateAnswer: Decodable, Sendable, Equatable {
    public let held: HeldPressing?
    public let downloading: DownloadInFlight?
    public let downloadingPart: DownloadInFlight?
    public let otherPressings: [OtherPressing]

    public init(held: HeldPressing? = nil, downloading: DownloadInFlight? = nil, downloadingPart: DownloadInFlight? = nil,
                otherPressings: [OtherPressing] = []) {
        self.held = held
        self.downloading = downloading
        self.downloadingPart = downloadingPart
        self.otherPressings = otherPressings
    }

    enum CodingKeys: String, CodingKey {
        case held, downloading
        case downloadingPart = "downloading_part"
        case otherPressings = "other_pressings"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        held = fields.looseField(HeldPressing.self, .held)
        downloading = fields.looseField(DownloadInFlight.self, .downloading)
        downloadingPart = fields.looseField(DownloadInFlight.self, .downloadingPart)
        otherPressings = fields.looseList(OtherPressing.self, .otherPressings) ?? []
    }
}

/// A status that stands in for the results (`StoreStatus`): a heading, and lines under it.
public struct StoreStatus: Sendable, Equatable {
    public enum Kind: String, Sendable { case held, downloading }

    public let kind: Kind
    public let title: String
    public let lines: [String]
    /// A download somebody else asked for, which Join joins (slice 3).
    public let joinJobId: Int?
    /// A pressing the store holds that isn't in your library: Add to my library is offered (slice 3).
    public let add: Bool

    public init(kind: Kind, title: String, lines: [String], joinJobId: Int? = nil, add: Bool = false) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.joinJobId = joinJobId
        self.add = add
    }
}

/// Where a download is cancelled - the app's Requests (the main page's Downloads, until it retired).
public enum CancelPlace: String, Sendable { case downloads = "Downloads", requests = "Requests" }

/// The store's words (candidates.ts, perPerson.ts, myLibrary.ts).
public enum StoreLine {
    /// The store line's title for a pressing held whole (and, logins on, in your library).
    public static let heldTitle = "Already in your library"
    /// The title of the store line for a pressing held whole that isn't yours (myLibrary.ts `IN_THE_STORE`).
    public static let inTheStore = "In the collection, not in your library"
    /// ...and what it says under it (`ADD_NOTE`).
    public static let addNote = "It's already here - add it to your library to keep it with your music."
    /// The phone's own (spec section 1): the store line's place while deadwax is out of reach.
    public static let offline = "Getting albums works once deadwax is back."

    /// "FLAC", "FLAC, MP3" (`formatNames`).
    public static func formatNames(_ formats: [String]?) -> String {
        (formats ?? []).filter { !$0.isEmpty }.map { $0.uppercased() }.joined(separator: ", ")
    }

    /// "10 of 10 tracks", or "9 tracks" when no tracklist was sent to count against (`heldTrackText`).
    public static func heldTrackText(_ held: HeldPressing) -> String {
        func plural(_ n: Int) -> String { n == 1 ? "track" : "tracks" }
        return held.expectedTracks != 0
            ? "\(held.trackCount) of \(held.expectedTracks) \(plural(held.expectedTracks))"
            : "\(held.trackCount) \(plural(held.trackCount))"
    }

    /// Past downloading, on its way into the library (`beingFiled`).
    public static func beingFiled(_ download: DownloadInFlight) -> Bool {
        download.status == "organizing" || download.status == "complete"
    }

    /// How far a download in flight has got, in a few words (`downloadProgressText`).
    public static func progressText(_ download: DownloadInFlight) -> String {
        if beingFiled(download) { return "being added to your library now" }
        switch download.status {
        case "queued": return "queued"
        case "downloading":
            guard let done = download.doneFiles else { return "downloading" }
            return "\(done) of \(download.files) files"
        //? only ever in flight while it moves to its next peer by itself
        case "failed": return "didn't work - trying another source"
        default: return download.status
        }
    }

    /// The status in place of the results, or nil for an ordinary result (`storeStatus`).
    public static func status(_ answer: StoreStateAnswer?, cancelIn: CancelPlace = .downloads) -> StoreStatus? {
        if let downloading = answer?.downloading {
            let line = "From \(downloading.username) · \(progressText(downloading))"
            //? being filed: the files are all in, so there's no other peer to cancel it for
            return beingFiled(downloading)
                ? StoreStatus(kind: .downloading, title: "Already downloaded", lines: [line])
                : StoreStatus(kind: .downloading, title: "Already downloading",
                              lines: [line, "To get it from another source, cancel it in \(cancelIn.rawValue) first."])
        }
        guard let held = answer?.held, held.complete else { return nil }
        let facts = [heldTrackText(held), formatNames(held.formats)].filter { !$0.isEmpty }.joined(separator: " · ")
        return StoreStatus(kind: .held, title: heldTitle, lines: held.folders + [facts])
    }

    /// What a download would do with a part held, said only as far as it is true (`whatADownloadDoes`).
    static func whatADownloadDoes(_ held: HeldPressing) -> String {
        let folders = held.folders
        let those = folders.count > 1 ? "those folders" : "that folder"
        if held.fillsGaps == true, let filedTo = held.filedTo, !filedTo.isEmpty {
            return folders.count > 1
                ? "Getting it adds only the tracks \(filedTo) doesn't have yet."
                : "Getting it adds only the tracks that folder doesn't have yet."
        }
        if let filedTo = held.filedTo, !filedTo.isEmpty {
            return "Getting it would add a separate copy, in \(filedTo), rather than fill in \(those)."
        }
        return "Getting it may add a separate copy rather than fill in \(those)."
    }

    /// The notes above the results: a download of part of this pressing running, part of it held, and each other
    /// pressing held (`storeNotes`).
    public static func notes(_ answer: StoreStateAnswer?) -> [String] {
        var notes: [String] = []
        if let part = answer?.downloadingPart {
            let files = "\(part.files) \(part.files == 1 ? "file" : "files")"
            notes.append("A download of part of this pressing is already running: \(files) from \(part.username) · "
                         + "\(progressText(part)).")
        }
        if let held = answer?.held, !held.complete {
            let who = held.yours == false ? "The collection has" : "You have"
            notes.append("\(who) \(held.trackCount) of \(held.expectedTracks) tracks of this pressing, in "
                         + "\(PerPerson.listed(held.folders)). \(whatADownloadDoes(held))")
        }
        for pressing in answer?.otherPressings ?? [] {
            let parts = [Credits.first(pressing.edition, pressing.year), formatNames(pressing.formats), pressing.path]
                .filter { !$0.isEmpty }
            let who = pressing.yours == false ? "The collection also has" : "You also have"
            notes.append("\(who) another pressing: \(parts.joined(separator: " · "))")
        }
        return notes
    }

    // MARK: downloads per person (perPerson.ts)

    /// A download in flight as a candidate, for the quality floor's own rules (`asCandidate`).
    static func asCandidate(_ download: DownloadInFlight) -> Candidate {
        Candidate(username: download.username, score: 1, matchedTracks: download.files, expectedTracks: 0,
                  audioFileCount: download.files, formats: download.formats ?? [], hasFreeSlot: true,
                  bitrates: download.bitrates ?? [], bitDepths: download.bitDepths ?? [],
                  sampleRates: download.sampleRates ?? [], variableBitrate: download.variableBitrate ?? false)
    }

    /// "FLAC 24/96", "MP3 320k" - the copy, as a source card's Quality says it; "" when nothing is known (`copyText`).
    public static func copyText(_ download: DownloadInFlight) -> String {
        let quality = Sources.qualityText(asCandidate(download))
        return quality == "Unknown" ? "" : quality
    }

    public enum FloorVerdict: String, Sendable { case below, unknown }

    /// How the copy in flight stands against your quality floor (`floorVerdict`): nil when it meets it (or the floor is
    /// Any), `.below`, or `.unknown` when its folder doesn't say what the floor asks about.
    public static func floorVerdict(_ download: DownloadInFlight, _ floor: QualityFloor) -> FloorVerdict? {
        if floor == .any { return nil }
        if Sources.passes(asCandidate(download), GetSettings.candidateFilters(GetSettings.floorFilters(floor))) {
            return nil
        }
        let unsaid = (download.formats ?? []).isEmpty
            || (floor == .bit24 && (download.bitDepths ?? []).isEmpty)
            || (floor == .kbps320 && (download.bitrates ?? []).isEmpty)
        return unsaid ? .unknown : .below
    }

    /// The line saying a joinable copy falls short of your floor - or nil (`floorNote`).
    public static func floorNote(_ download: DownloadInFlight, _ floor: QualityFloor?) -> String? {
        guard let floor, let verdict = floorVerdict(download, floor) else { return nil }
        let own = "getting a copy of your own isn't offered yet"
        return verdict == .below
            ? "It's below your quality floor (\(floor.label)), and \(own)."
            : "Its quality isn't known, so it may be below your quality floor (\(floor.label)), and \(own)."
    }

    /// The last line of a download somebody else asked for: what Join does (`joinNote`).
    public static func joinNote(_ place: CancelPlace) -> String {
        "Join it to have it in your \(place.rawValue) too - one download, everyone who asked waiting for it."
    }

    /// The store line's last line for a download of yours somebody else waits for too (`sharedNote`).
    public static func sharedNote(_ place: CancelPlace) -> String {
        "Someone else asked for it too, so cancelling it in \(place.rawValue) only takes it off your list - another source isn't offered for a download you share."
    }

    /// The store's status for a pressing, with downloads per person's and personal libraries' cases (`storeStatusFor`).
    public static func statusFor(_ answer: StoreStateAnswer?, cancelIn: CancelPlace = .downloads,
                                 floor: QualityFloor? = nil) -> StoreStatus? {
        let download = answer?.downloading
        if let download, download.yours == false {
            let first = ["From \(download.username)", copyText(download), progressText(download)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            let note = floorNote(download, floor)
            return StoreStatus(
                kind: .downloading,
                title: beingFiled(download) ? "Already downloaded for someone else" : "Already downloading for someone else",
                lines: [first] + (note.map { [$0] } ?? []) + [joinNote(cancelIn)],
                joinJobId: download.jobId)
        }
        let status = status(answer, cancelIn: cancelIn)
        //? held whole by the store, but not in your library: Add to my library, not a download
        if download == nil, let status, let held = answer?.held, held.complete, held.yours == false {
            return StoreStatus(kind: status.kind, title: inTheStore, lines: status.lines + [addNote], add: true)
        }
        guard let download, let status, !beingFiled(download) else { return status }
        //? storeStatus's lines here: the peer and how far, then where to cancel it for another peer
        if download.status == "failed" { return StoreStatus(kind: status.kind, title: status.title, lines: Array(status.lines.prefix(1))) }
        if PerPerson.leavesOnCancel(shared: download.shared, requestedBy: download.requestedBy) {
            return StoreStatus(kind: status.kind, title: status.title, lines: Array(status.lines.prefix(1)) + [sharedNote(cancelIn)])
        }
        return status
    }

    /// A store line drawn with no Join under it (`withoutJoin`): the line saying what Join does goes too, and so does the
    /// job Join would join, so it never says "Join it" above no button.
    public static func withoutJoin(_ status: StoreStatus) -> StoreStatus {
        guard status.joinJobId != nil else { return status }
        let notes = [joinNote(.downloads), joinNote(.requests)]
        return StoreStatus(kind: status.kind, title: status.title, lines: status.lines.filter { !notes.contains($0) },
                           add: status.add)
    }

    /// THE PHONE'S OWN, until slice 3 brings Add to my library: a store line drawn with no Add under it loses the line
    /// telling you to add it (`addNote`) and its `add`, so it never says "add it" above no button. The title stays the
    /// web's - "In the collection, not in your library" is still true. The web has no such case (every page of its
    /// gives Add), so this is held by hand (GetTests), not by the vectors.
    public static func withoutAdd(_ status: StoreStatus) -> StoreStatus {
        guard status.add else { return status }
        return StoreStatus(kind: status.kind, title: status.title, lines: status.lines.filter { $0 != addNote },
                           joinJobId: status.joinJobId)
    }

    /// What the phone draws in slice 2: neither Join nor Add.
    public static func drawn(_ answer: StoreStateAnswer?, floor: QualityFloor?) -> StoreStatus? {
        statusFor(answer, cancelIn: .requests, floor: floor).map { withoutAdd(withoutJoin($0)) }
    }
}
