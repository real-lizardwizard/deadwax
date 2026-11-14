import Foundation

/// The rules every download screen draws by (spec 2): a song's state from its record and its task, the album's from
/// its songs', what each menu offers, and how a record moves on each thing that happens to it. Pure.
public enum DownloadRules {
    /// Tries before a song is given up on (8.3).
    public static let maxTries = 3
    /// A transcode's estimate: its duration at 320 kbps, an upper bound (8.5).
    public static let transcodeBytesPerSecond: Double = 40_000
    /// A transcode's fraction is held under this until it lands (1.3).
    public static let transcodeHold = 0.95

    /// What the planner counts a song at: Navidrome's `size`; a transcode's estimate from its duration (0 without one).
    public static func expectedBytes(size: Int64?, transcode: Bool, duration: Double?) -> Int64 {
        if !transcode, let size, size > 0 { return size }
        guard let duration, duration > 0 else { return transcode ? 0 : (size ?? 0) }
        return Int64((duration * transcodeBytesPerSecond).rounded(.up))
    }

    // MARK: a song's state

    /// The song's state for the screens: nothing asked; the planner's wait (`planned`, else the one the store kept); a
    /// task out with no byte yet (`queued` - unless the network holds it, when the planner's wait is said); fetching,
    /// by the bytes `received` over what's expected; here, with its check; or given up on.
    public static func state(_ record: DownloadRecord?, received: Int64? = nil, planned: DownloadWait? = nil) -> SongDownload {
        guard let record else { return .none }
        switch record.state {
        case .done:
            return .done(record.check ?? .unchecked)
        case .failed:
            return .failed(record.failure ?? .unsaved)
        case .wanted:
            return .waiting(planned ?? record.wait ?? .queued)
        case .fetching:
            if let received, received > 0 { return .fetching(fraction(received: received, of: record)) }
            if let planned, planned != .queued, planned.isTheNetwork { return .waiting(planned) }
            return .waiting(.queued)
        }
    }

    /// Bytes received over bytes expected, 0...1 - a transcode's over its estimate, held under 95% until it lands.
    public static func fraction(received: Int64, of record: DownloadRecord) -> Double {
        let expected = record.expectedBytes
        guard expected > 0 else { return 0 }
        let part = min(max(Double(received) / Double(expected), 0), 1)
        return record.isTranscode ? min(part, transcodeHold) : part
    }

    // MARK: what happens to one

    /// Everything that moves a song's record (8.3, 8.4).
    public enum Event: Sendable, Equatable {
        /// Its task was made: `fetching`, under this description.
        case taskMade(String)
        /// Its task was cancelled - by the app (a setting changed, a sign-out) or by iOS (a force quit): back to
        /// `wanted`, with its resume data when it can resume. Never a try.
        case cancelled(resume: Data?)
        /// deadwax answered 401: the session ended. A `signIn` wait, never a try; resume data dropped (it carries the
        /// old cookie).
        case signedOut
        /// Nothing answered. A try only when deadwax had answered since the task began (`counts`); else a wait, made
        /// again when deadwax answers. Resume data kept either way.
        case noAnswer(DownloadFailure, resume: Data?, counts: Bool)
        /// deadwax answered with another status (a 404, a 500): a try.
        case refused(status: Int, detail: String?)
        /// The file arrived at another length than the song's: deleted, a try.
        case wrongLength
        /// The file couldn't be written - a full phone is a `phoneFull` wait; anything else a try.
        case unsaved(outOfSpace: Bool)
        /// Its length checked: on the phone, `check` (unchecked for a FLAC with a fingerprint, else by size).
        case arrived(bytes: Int64, check: CopyCheck, flac: FLACFacts?, at: Int64)
        /// Its sound checked: matched (or by size, when the decode found nothing to compare).
        case checked(CopyCheck)
        /// Its decoded sound didn't match STREAMINFO's MD5: deleted, a try.
        case soundMismatch
        /// iOS couldn't open or decode it: deleted, a try.
        case unreadable
        /// "Try again": asked for afresh, its tries from 0.
        case retry
        /// A launch: a song given up on gets one more try (until Phase 3's sync takes it over).
        case launched
        /// Its file is gone from the phone (deleted by something else): asked for again.
        case fileMissing
    }

    /// `record` after `event`.
    public static func apply(_ event: Event, to record: DownloadRecord) -> DownloadRecord {
        var r = record
        switch event {
        case .taskMade(let description):
            r.state = .fetching
            r.task = description
            r.wait = nil
        case .cancelled(let resume):
            r.state = .wanted
            r.task = nil
            r.resume = resume ?? r.resume
        case .signedOut:
            r.state = .wanted
            r.task = nil
            r.resume = nil
            r.wait = .signIn
        case .noAnswer(let failure, let resume, let counts):
            r.task = nil
            r.resume = resume ?? r.resume
            if counts {
                r = tried(r, failure)
            } else {
                r.state = .wanted
            }
        case .refused(let status, let detail):
            r.task = nil
            r.resume = nil
            r = tried(r, .answered(status: status, detail: detail))
        case .wrongLength:
            r.task = nil
            r.resume = nil
            r = tried(r, .wrongSize)
        case .unsaved(let outOfSpace):
            r.task = nil
            r.resume = nil
            if outOfSpace {
                r.state = .wanted
                r.wait = .phoneFull
            } else {
                r = tried(r, .unsaved)
            }
        case .arrived(let bytes, let check, let flac, let at):
            r.state = .done
            r.task = nil
            r.resume = nil
            r.wait = nil
            r.bytes = bytes
            r.check = check
            r.flac = flac
            r.failure = nil
            r.doneAt = at
        case .checked(let check):
            if r.state == .done { r.check = check }
        case .soundMismatch:
            r = gone(r)
            r = tried(r, .soundMismatch)
        case .unreadable:
            r = gone(r)
            r = tried(r, .unreadable)
        case .retry:
            r.state = r.state == .done ? .done : .wanted
            r.tries = 0
            r.failure = nil
            r.wait = nil
        case .launched:
            if r.state == .failed {
                r.state = .wanted
                r.wait = nil
            }
        case .fileMissing:
            if r.state == .done { r = gone(r) }
        }
        return r
    }

    /// A try spent: given up on at the third, else asked for again.
    static func tried(_ record: DownloadRecord, _ failure: DownloadFailure) -> DownloadRecord {
        var r = record
        r.tries += 1
        r.task = nil
        if r.tries >= maxTries {
            r.state = .failed
            r.failure = failure
            r.wait = nil
        } else {
            r.state = .wanted
            r.failure = nil
        }
        return r
    }

    /// The copy deleted: no longer here.
    static func gone(_ record: DownloadRecord) -> DownloadRecord {
        var r = record
        r.state = .wanted
        r.bytes = nil
        r.check = nil
        r.doneAt = nil
        r.task = nil
        r.resume = nil
        return r
    }

    /// Whether a finished task's status is the song: 200, or 206 for a resumed one. Anything else is a failure,
    /// whatever its body - a background download "succeeds" with an error page (8.3).
    public static func isTheSong(status: Int) -> Bool { status == 200 || status == 206 }

    /// Whether a finished file's `length` is the song's: Navidrome's size for the file as it is, any length but 0 for a
    /// transcode (8.4, LocalFiles.lengthMatches).
    public static func lengthMatches(_ length: Int64, record: DownloadRecord) -> Bool {
        guard !record.isTranscode, let size = record.sizeExpected, size > 0 else { return length > 0 }
        return length == size
    }

    /// How a copy whose length matched is checked from here (8.4): a FLAC whose STREAMINFO carries an MD5, at 24 bits
    /// or fewer, is decoded (`unchecked` until then); anything else is checked by size - not a FLAC, an all-zero MD5,
    /// or FLAC 1.4's 32-bit, which Float32 can't hold exactly.
    public static func checkAfterLength(_ info: FLACStreamInfo?) -> CopyCheck {
        guard let info, info.md5Known, info.bitsPerSample <= 24, info.bitsPerSample >= 4 else { return .bySize }
        return .unchecked
    }

    /// How a song's or an album's copies were checked, in You > Downloads' words (6.6) and Info's (4.4).
    public enum Verdict: String, Sendable, Equatable {
        /// Every copy matched - or checked by size where that is all its file allows (not a FLAC).
        case checked
        /// A FLAC carries no sound fingerprint (or is over 24 bits): its length alone.
        case bySize
        /// One is still to be decoded.
        case checking
    }

    /// The verdict of one copy: `isFLAC` - its STREAMINFO was read (FLACFacts).
    public static func verdict(_ check: CopyCheck, isFLAC: Bool) -> Verdict {
        switch check {
        case .unchecked: return .checking
        case .matched: return .checked
        case .bySize: return isFLAC ? .bySize : .checked
        }
    }

    /// The verdict of several: checking while any is, else by size when any FLAC was, else checked.
    public static func verdict(_ copies: [(check: CopyCheck, isFLAC: Bool)]) -> Verdict {
        let each = copies.map { verdict($0.check, isFLAC: $0.isFLAC) }
        if each.contains(.checking) { return .checking }
        if each.contains(.bySize) { return .bySize }
        return .checked
    }

    // MARK: removing

    /// What Remove Download leaves (8.2): `removed` taken from each song's origins; the songs left with none are deleted.
    public static func afterRemoving(_ removed: Set<DownloadOrigin>, from origins: [String: Set<DownloadOrigin>])
        -> (kept: [String: Set<DownloadOrigin>], deleted: [String]) {
        var kept: [String: Set<DownloadOrigin>] = [:]
        var deleted: [String] = []
        for (song, its) in origins {
            let left = its.subtracting(removed)
            if left.isEmpty { deleted.append(song) } else { kept[song] = left }
        }
        return (kept, deleted.sorted())
    }

    /// (Phase 3, after the review) The files of the store's music folder no song row names - audio a crash left between
    /// a row's delete and its file's (removeOrigins deletes the row first): swept as the store settles. Only names the
    /// store itself gives a song (`<id>.<suffix>`, LocalFiles' rule) - never a part (the settle's own rule has those),
    /// nor anything else. `named`: every row's file name, from a read of the database that succeeded - with none, the
    /// caller sweeps nothing.
    public static func unnamedFiles(_ fileNames: [String], named: Set<String>) -> [String] {
        fileNames.filter { StreamCache.isSongName($0) && !named.contains($0) }.sorted()
    }

    // MARK: offline

    /// Whether a song plays while deadwax can't be reached: only from the phone.
    public static func playsOffline(_ state: SongDownload) -> Bool { state.isHere }
}

/// One song of an album, as the album's state is made from it (spec 2.2).
public struct AlbumSongFacts: Sendable, Equatable {
    public let state: SongDownload
    /// Its bytes expected: Navidrome's size (or a transcode's estimate) - its own length once here.
    public let expected: Int64
    /// Bytes on the phone or received so far: its length once here, the task's count while fetching.
    public let received: Int64

    public init(state: SongDownload, expected: Int64 = 0, received: Int64 = 0) {
        self.state = state
        self.expected = expected
        self.received = received
    }
}

/// An album's download, from its songs' as deadwax lists them (spec 2.2) - the control, the hero's line, a tile's mark.
public enum AlbumDownload: Sendable, Equatable {
    case none
    /// Some here, the rest not asked for: "3 of 12 songs downloaded".
    case partial(here: Int, of: Int)
    /// Something fetching: the songs here of those asked for or here, and the bytes' fraction.
    case downloading(here: Int, of: Int, fraction: Double)
    /// Something waiting: the first such song's reason.
    case waiting(DownloadWait, here: Int, of: Int)
    /// Something given up on: how many, and the first one's reason.
    case failed(count: Int, first: DownloadFailure)
    /// Every song here - `checking` while any is unchecked.
    case downloaded(checking: Bool)

    /// The album's state, in this order: any fetching -> downloading; any waiting -> waiting; any failed -> failed; every
    /// song here -> downloaded; some here -> partial; else none.
    public static func of(_ songs: [AlbumSongFacts]) -> AlbumDownload {
        let here = songs.filter(\.state.isHere).count
        if songs.contains(where: { if case .fetching = $0.state { return true } else { return false } }) {
            let counted = songs.filter(\.state.isAsked)
            let total = counted.reduce(Int64(0)) { $0 + max($1.expected, 0) }
            let got = counted.reduce(Int64(0)) { $0 + min(max($1.received, 0), max($1.expected, 0)) }
            let fraction = total > 0 ? min(max(Double(got) / Double(total), 0), 1) : 0
            return .downloading(here: here, of: counted.count, fraction: fraction)
        }
        for song in songs {
            if case .waiting(let reason) = song.state {
                return .waiting(reason, here: here, of: songs.filter(\.state.isAsked).count)
            }
        }
        let failures = songs.compactMap { song -> DownloadFailure? in
            if case .failed(let failure) = song.state { return failure }
            return nil
        }
        if let first = failures.first { return .failed(count: failures.count, first: first) }
        if !songs.isEmpty && here == songs.count {
            let checking = songs.contains { $0.state == .done(.unchecked) }
            return .downloaded(checking: checking)
        }
        if here > 0 { return .partial(here: here, of: songs.count) }
        return .none
    }

    /// Any song of it is on the phone.
    public var hasSongsHere: Bool {
        switch self {
        case .partial, .downloaded: return true
        case .downloading(let here, _, _), .waiting(_, let here, _): return here > 0
        case .none, .failed: return false
        }
    }
}

/// What a menu offers for a song or several (spec 2.5).
public enum DownloadChoice: String, Sendable, CaseIterable {
    case download
    case downloadAgain
    case remove

    /// The menu's words (title case, as Play Next and Play Last).
    public var label: String {
        switch self {
        case .download: return DownloadWords.download
        case .downloadAgain: return DownloadWords.downloadAgain
        case .remove: return DownloadWords.removeDownload
        }
    }

    /// Its SF Symbol (iOS 13.0 each).
    public var symbol: String {
        switch self {
        case .download: return DownloadWords.downloadSymbol
        case .downloadAgain: return "arrow.clockwise"
        case .remove: return "trash"
        }
    }

    /// Remove Download is destructive (red).
    public var isDestructive: Bool { self == .remove }

    /// One song's items: none -> Download; waiting, fetching or here -> Remove Download; failed -> Download Again and
    /// Remove Download.
    public static func forSong(_ state: SongDownload) -> [DownloadChoice] {
        switch state {
        case .none: return [.download]
        case .waiting, .fetching, .done: return [.remove]
        case .failed: return [.downloadAgain, .remove]
        }
    }

    /// (Phase 3) One song's items when your library keeps it (it carries the library's origin): no Remove Download of the
    /// song alone - the library would ask for it again at once. Its album's Remove Download keeps the album off.
    public static func forSong(_ state: SongDownload, keptByLibrary: Bool) -> [DownloadChoice] {
        forSong(state, staying: keptByLibrary)
    }

    /// (Phase 3) Several songs asked for each alone (Up Next, a selection - not an album): Remove Download only when a
    /// song that isn't your library's is asked for or here; `keptByLibrary` beside `states`.
    public static func forSongs(_ states: [SongDownload], gone: Bool = false, keptByLibrary: [Bool]) -> [DownloadChoice] {
        forSongs(states, gone: gone, staying: keptByLibrary)
    }

    /// (Phase 4, slice 3) One song's items when it would stay after its Remove Download - your library or a downloaded
    /// playlist keeps it (DownloadRemoval.stays): no Remove Download, which would leave it where it is.
    public static func forSong(_ state: SongDownload, staying: Bool) -> [DownloadChoice] {
        let choices = forSong(state)
        return staying ? choices.filter { $0 != .remove } : choices
    }

    /// (Phase 4, slice 3) Several songs': Remove Download only when one asked for or here would go with it - `staying`
    /// beside `states`, each song's DownloadRemoval.stays for that Remove (a song's, alone; an album's, for an album).
    public static func forSongs(_ states: [SongDownload], gone: Bool = false, staying: [Bool]) -> [DownloadChoice] {
        let choices = forSongs(states, gone: gone)
        let removable = zip(states, staying).contains { (pair: (SongDownload, Bool)) -> Bool in pair.0 != .none && !pair.1 }
        return removable ? choices : choices.filter { $0 != .remove }
    }

    /// Several songs' (an album, Up Next): Download when any is none or failed - and the album is still in the
    /// collection (`gone` false: there is nothing to fetch otherwise); Remove Download when any is anything but none.
    public static func forSongs(_ states: [SongDownload], gone: Bool = false) -> [DownloadChoice] {
        var choices: [DownloadChoice] = []
        let wantsOne = states.contains { state in
            if case .none = state { return true }
            if case .failed = state { return true }
            return false
        }
        if wantsOne && !gone { choices.append(.download) }
        if states.contains(where: { $0 != .none }) { choices.append(.remove) }
        return choices
    }

    /// Now Playing's Download Up Next (4.1): the songs from the one playing to the queue's end that are none or failed -
    /// offered only for two or more (one is "Download"), and never during a library's shuffle (`paged`).
    public static func upNext(_ states: [SongDownload], paged: Bool) -> Int? {
        guard !paged else { return nil }
        let count = states.filter { state in
            if case .none = state { return true }
            if case .failed = state { return true }
            return false
        }.count
        return count >= 2 ? count : nil
    }

    /// Which of `states` "Download" asks for: those none or failed, and only those.
    public static func asked(by states: [SongDownload]) -> [Int] {
        states.indices.filter { index in
            if case .none = states[index] { return true }
            if case .failed = states[index] { return true }
            return false
        }
    }
}
