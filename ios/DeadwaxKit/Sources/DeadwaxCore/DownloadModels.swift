import Foundation

// Phase 2's downloads (notes/ios-specs/phase2-downloads.md): what a song kept on this phone is, in the words the
// rules, the planner, the store and the screens share. Pure - tested on Linux with the rest of Core.

/// Why a song asked for isn't being fetched now (spec 2.1), in the order the planner gives them (8.5).
public enum DownloadWait: String, Sendable, CaseIterable, Codable {
    /// No network at all.
    case connection
    /// The network is there; deadwax doesn't answer.
    case deadwax
    /// A 401: the session ended.
    case signIn = "sign_in"
    /// Wi-Fi only, on mobile data.
    case wifi
    /// Wi-Fi only, on a Wi-Fi that is a phone's hotspot (iOS calls it expensive).
    case hotspot
    /// Wi-Fi only, with Low Data Mode on (iOS calls it constrained).
    case lowData = "low_data"
    /// The storage limit.
    case room
    /// 2 GB of the phone must stay free.
    case phoneFull = "phone_full"
    /// (Phase 3, slice 3) Only while charging is on and the phone isn't: a song only your library wants waits for it.
    case charging
    /// Its task is out and hasn't had a byte yet (the session fetches three at a time).
    case queued

    /// A wait the network causes: the song's task is still made, with the request's own flags (`DownloadOver.access`),
    /// so iOS starts it by itself the moment the network allows - the app need not be running then.
    public var isTheNetwork: Bool { self == .connection || self == .wifi || self == .hotspot || self == .lowData }

    /// A wait one of the settings causes - the control's menu names it (spec 3.1): Download over, the storage limit,
    /// and (Phase 3) Only while charging.
    public var isTheSettings: Bool {
        self == .wifi || self == .hotspot || self == .lowData || self == .room || self == .charging
    }
}

/// How a copy on this phone was checked (spec 2.1, 8.4).
public enum CopyCheck: String, Sendable, CaseIterable, Codable {
    /// A FLAC not yet decoded: it plays meanwhile.
    case unchecked
    /// Its decoded sound's MD5 is STREAMINFO's.
    case matched
    /// Its length only: not a FLAC, a FLAC whose MD5 is all zeros, or one over 24 bits.
    case bySize = "by_size"
}

/// Why a song didn't download, kept until it is asked for again (spec 2.4). The HTTP ones are said by ErrorWords, as an
/// APIFailure for the stream's path; the download's own by DownloadWords.
public enum DownloadFailure: Sendable, Equatable {
    /// deadwax answered with a status the stream doesn't succeed with (a 404: the song isn't there any more).
    case answered(status: Int, detail: String?)
    /// Nothing answered, though deadwax had answered since the task began (else it is a wait, not a failure).
    case offline(reason: String)
    /// Nothing answered in time, the same way.
    case timeout(reason: String)
    /// The copy's length wasn't the song's, three times.
    case wrongSize
    /// The copy's decoded sound didn't match the MD5 its FLAC carries, three times.
    case soundMismatch
    /// iOS couldn't open or decode the copy.
    case unreadable
    /// The file couldn't be written.
    case unsaved

    /// The store's `failure` column.
    public var code: String {
        switch self {
        case .answered(let status, _): return "http_\(status)"
        case .offline: return "offline"
        case .timeout: return "timeout"
        case .wrongSize: return "wrong_size"
        case .soundMismatch: return "sound"
        case .unreadable: return "unreadable"
        case .unsaved: return "unsaved"
        }
    }

    /// The store's `failure_raw` column: deadwax's words, or the system's - for whoever runs deadwax.
    public var raw: String? {
        switch self {
        case .answered(_, let detail): return detail
        case .offline(let reason), .timeout(let reason): return reason
        default: return nil
        }
    }

    /// A failure as the store kept it; nil for a code it doesn't know.
    public init?(code: String, raw: String?) {
        switch code {
        case "offline": self = .offline(reason: raw ?? "")
        case "timeout": self = .timeout(reason: raw ?? "")
        case "wrong_size": self = .wrongSize
        case "sound": self = .soundMismatch
        case "unreadable": self = .unreadable
        case "unsaved": self = .unsaved
        default:
            guard code.hasPrefix("http_"), let status = Int(code.dropFirst(5)) else { return nil }
            self = .answered(status: status, detail: raw)
        }
    }
}

/// A song's download, as every screen draws it (spec 2.1).
public enum SongDownload: Sendable, Equatable {
    /// Not asked for: plays from the stream.
    case none
    /// Asked for; not being fetched now.
    case waiting(DownloadWait)
    /// Its first bytes have come: bytes received over bytes expected (a transcode's over its estimate, held under 95%).
    case fetching(Double)
    /// On the phone, its length checked: it plays from the phone.
    case done(CopyCheck)
    /// Given up on after three tries.
    case failed(DownloadFailure)

    /// It plays from the phone.
    public var isHere: Bool {
        if case .done = self { return true }
        return false
    }

    /// Asked for and not given up on - waiting, fetching or here.
    public var isAsked: Bool {
        switch self {
        case .none, .failed: return false
        default: return true
        }
    }
}

/// Why a song is wanted (the store's `origin`): a song is removed once it has none left (spec 8.2).
public enum DownloadOrigin: Sendable, Hashable, Comparable {
    /// Asked for by itself - a song's ••• Download, Now Playing's, Download Up Next.
    case song
    /// Asked for with its album - the album page's control, its •••.
    case album(String)
    /// One a later phase writes, kept as it is: your library's (`library`, Phase 3) and a downloaded playlist's
    /// (`playlist(_:)`, `playlist:<id>`, Phase 4 - PlaylistDownloads.swift).
    case other(String)

    public var raw: String {
        switch self {
        case .song: return "song"
        case .album(let id): return "album:\(id)"
        case .other(let raw): return raw
        }
    }

    public init(raw: String) {
        if raw == "song" {
            self = .song
        } else if raw.hasPrefix("album:"), raw.count > 6 {
            self = .album(String(raw.dropFirst(6)))
        } else {
            self = .other(raw)
        }
    }

    public static func < (a: DownloadOrigin, b: DownloadOrigin) -> Bool { a.raw < b.raw }

    /// Phase 3's: asked for with your library (phase3-autodownload.md 2.7) - the raw "library" Phase 2 reserved, so a
    /// store written before Phase 3 reads it as the same origin. Taken only by the library's own rules (removed, given
    /// way, kept off, the switch off) and by Remove Download; never deletes a song that carries any other origin.
    public static let library = DownloadOrigin.other("library")

    /// The song is wanted by the library and by nothing else.
    public static func onlyLibrary(_ origins: Set<DownloadOrigin>) -> Bool { origins == [.library] }
}

/// The store's `song.state`.
public enum StoredState: String, Sendable, CaseIterable {
    /// Asked for, no task out.
    case wanted
    /// A task is out (`task` names it).
    case fetching
    /// On the phone.
    case done
    /// Given up on.
    case failed
}

/// STREAMINFO's facts about a FLAC copy, for Info and Debug (spec 4.4).
public struct FLACFacts: Sendable, Equatable {
    public let rate: Int
    public let bits: Int
    /// 32 hex digits; all zeros when the encoder didn't compute it.
    public let md5: String

    public init(rate: Int, bits: Int, md5: String) {
        self.rate = rate
        self.bits = bits
        self.md5 = md5
    }

    public init(_ info: FLACStreamInfo) {
        rate = info.sampleRate
        bits = info.bitsPerSample
        md5 = info.md5.map { String($0, radix: 16).zeroPadded(to: 2) }.joined()
    }
}

/// One song asked for or here - a row of the store's `song` table (spec 8.2).
public struct DownloadRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public var albumID: String
    public var disc: Int?
    public var track: Int?
    /// `raw` or `mp3` (StreamFormat.format).
    public var format: String
    /// As it arrives (StreamFormat.suffix).
    public var suffix: String
    /// Navidrome's size; nil for a transcode, which has none.
    public var sizeExpected: Int64?
    /// The song's length in seconds: a transcode's estimate (8.5).
    public var duration: Double?
    public var state: StoredState
    /// The planner's reason, while `wanted` - kept so a launch draws it before the planner has run.
    public var wait: DownloadWait?
    /// While `done`.
    public var check: CopyCheck?
    /// The file's length, once done.
    public var bytes: Int64?
    public var flac: FLACFacts?
    public var tries: Int
    /// While `failed`.
    public var failure: DownloadFailure?
    /// The task's description while one is out (`DownloadTaskName`).
    public var task: String?
    /// Resume data, while an interrupted fetch waits.
    public var resume: Data?
    /// Milliseconds since 1970.
    public var wantedAt: Int64
    public var doneAt: Int64?

    public init(id: String, albumID: String, disc: Int? = nil, track: Int? = nil, format: String = "raw",
                suffix: String, sizeExpected: Int64? = nil, duration: Double? = nil, state: StoredState = .wanted,
                wait: DownloadWait? = nil, check: CopyCheck? = nil, bytes: Int64? = nil, flac: FLACFacts? = nil,
                tries: Int = 0, failure: DownloadFailure? = nil, task: String? = nil, resume: Data? = nil,
                wantedAt: Int64, doneAt: Int64? = nil) {
        self.id = id
        self.albumID = albumID
        self.disc = disc
        self.track = track
        self.format = format
        self.suffix = suffix
        self.sizeExpected = sizeExpected
        self.duration = duration
        self.state = state
        self.wait = wait
        self.check = check
        self.bytes = bytes
        self.flac = flac
        self.tries = tries
        self.failure = failure
        self.task = task
        self.resume = resume
        self.wantedAt = wantedAt
        self.doneAt = doneAt
    }

    /// A record for `song` of `albumID`, asked for at `now` (ms): fetched as its stream is (StreamFormat).
    public init(song: Song, albumID: String, now: Int64) {
        let format = StreamFormat.format(for: song)
        self.init(id: song.id, albumID: albumID, disc: song.discNumber, track: song.track, format: format,
                  suffix: StreamFormat.suffix(for: song), sizeExpected: format == "raw" ? song.size : nil,
                  duration: song.duration, wantedAt: now)
    }

    /// The file's name on the phone: `<id>.<suffix>` (LocalFiles.name), nil for an id that can't name a file.
    public var fileName: String? { LocalFiles.name(songID: id, suffix: suffix) }

    /// A transcode (Navidrome's mp3 of what iOS can't decode): any length but 0 is its length.
    public var isTranscode: Bool { format != "raw" }

    /// The bytes the planner counts it at: Navidrome's size, or a transcode's estimate (8.5); its own once here.
    public var expectedBytes: Int64 {
        if state == .done, let bytes { return bytes }
        return DownloadRules.expectedBytes(size: sizeExpected, transcode: isTranscode, duration: duration)
    }
}

/// Which network downloads may use (spec 6.4) - kept per phone in UserDefaults, as Normalization is.
public enum DownloadOver: String, Sendable, CaseIterable {
    /// Wi-Fi alone: never mobile data, a hotspot or Low Data Mode.
    case wifi
    /// Mobile data too, whenever there's no Wi-Fi.
    case any

    public static let storageKey = "downloadOver"
    public static let `default`: DownloadOver = .wifi

    /// A setting as the phone saved it: anything but `any` is Wi-Fi only.
    public init(saved: String?) {
        self = saved.flatMap(DownloadOver.init(rawValue:)) ?? .default
    }

    /// The flags each download request is made with (`allowsCellularAccess`, `allowsExpensiveNetworkAccess`,
    /// `allowsConstrainedNetworkAccess`) - set per request, so a change of setting is a new request, not a new session.
    public var access: (cellular: Bool, expensive: Bool, constrained: Bool) {
        self == .any ? (true, true, true) : (false, false, false)
    }
}

/// What downloads may take (spec 6.3): 5, 10, 20 (the default), 50, 100 GB, or no limit. A GB is 1,000,000,000 bytes,
/// as iOS's Storage counts (and StreamCache's limit is).
public enum StorageLimit: String, Sendable, CaseIterable {
    case gb5 = "5"
    case gb10 = "10"
    case gb20 = "20"
    case gb50 = "50"
    case gb100 = "100"
    case none

    public static let storageKey = "storageLimit"
    public static let `default`: StorageLimit = .gb20

    public init(saved: String?) {
        self = saved.flatMap(StorageLimit.init(rawValue:)) ?? .default
    }

    /// The limit in bytes; nil for No limit.
    public var bytes: Int64? {
        guard let gigabytes = Int64(rawValue) else { return nil }
        return gigabytes * 1_000_000_000
    }

    /// The picker's words: "20 GB", "No limit".
    public var label: String { self == .none ? DownloadWords.noLimit : "\(rawValue) GB" }
}

/// What the phone's network is now (NWPathMonitor's path, read by the App).
public struct NetworkPath: Sendable, Equatable {
    /// `status == .satisfied`.
    public var satisfied: Bool
    public var wifi: Bool
    public var cellular: Bool
    /// `isExpensive`: mobile data, or a Wi-Fi that is a phone's hotspot.
    public var expensive: Bool
    /// `isConstrained`: Low Data Mode.
    public var constrained: Bool

    public init(satisfied: Bool, wifi: Bool = false, cellular: Bool = false, expensive: Bool = false,
                constrained: Bool = false) {
        self.satisfied = satisfied
        self.wifi = wifi
        self.cellular = cellular
        self.expensive = expensive
        self.constrained = constrained
    }

    /// On Wi-Fi at home, as a launch assumes until the monitor says.
    public static let wifiAtHome = NetworkPath(satisfied: true, wifi: true)
    public static let none = NetworkPath(satisfied: false)

    /// What the Download over footer says the phone is on (6.4).
    public var kind: Kind {
        if !satisfied { return .none }
        if constrained { return .lowData }
        if wifi { return expensive ? .hotspot : .wifi }
        if cellular { return .mobileData }
        // wired, or a VPN alone: counted as Wi-Fi unless iOS calls it expensive
        return expensive ? .mobileData : .wifi
    }

    public enum Kind: String, Sendable, CaseIterable {
        case wifi, mobileData, hotspot, lowData, none
    }
}

/// Whether deadwax can be reached (spec 7.1).
public enum Reach: String, Sendable, CaseIterable {
    case online
    /// The phone has no network: nothing is tried.
    case noNetwork
    /// The network is there, deadwax doesn't answer.
    case unreachable
}

/// Where a download task's completion belongs, written into its `taskDescription`: `<server>|<person>|<song id>|<suffix>`,
/// each part `KeptAlbumIndex.safeName`d (no "|" can appear in one) - so a completion lands in the right person's store
/// even after someone else signed in, and its `.part` can be named before the store is open (spec 8.3).
public struct DownloadTaskName: Sendable, Equatable, Hashable {
    public let server: String
    public let person: String
    public let songID: String
    public let suffix: String

    public init(server: String, person: String, songID: String, suffix: String) {
        self.server = server
        self.person = person
        self.songID = songID
        self.suffix = suffix
    }

    public var description: String {
        [server, person, songID, suffix].map(KeptAlbumIndex.safeName).joined(separator: "|")
    }

    public init?(description: String) {
        let parts = description.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { return nil }
        let decoded = parts.map(Self.unsafe)
        guard !decoded[2].isEmpty else { return nil }
        self.init(server: decoded[0], person: decoded[1], songID: decoded[2], suffix: decoded[3])
    }

    /// `safeName` undone: every `%XX` back to its byte.
    static func unsafe(_ text: String) -> String {
        var bytes: [UInt8] = []
        var utf8 = Array(text.utf8)[...]
        while let byte = utf8.first {
            utf8 = utf8.dropFirst()
            if byte == 0x25, utf8.count >= 2, let value = UInt8(String(decoding: utf8.prefix(2), as: UTF8.self), radix: 16) {
                bytes.append(value)
                utf8 = utf8.dropFirst(2)
            } else {
                bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

extension String {
    func zeroPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
