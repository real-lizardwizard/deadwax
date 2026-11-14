import Foundation

// Download a playlist (Phase 4, slice 3; notes/ios-specs/phase4-library.md 2.5, 6.3): the playlist's own origin, what
// each Remove Download takes, the playlist kept on this phone with its last answer (the store's `playlist` table,
// version 6), and how it is kept in step with the playlist on deadwax - pure, tested on Linux with the rest of Core.
//
// A downloaded playlist is a HAND download (Choice 19): its songs carry `playlist:<id>`, never given way and never
// evicted - your library never takes that origin (LibraryDownloads.gives is its own alone), so it never removes a
// playlist's song. The origin is taken only by the playlist's Remove Download, by Remove All, and by the playlist itself
// as it is kept in step: a song it lost - once two reads at least 10 minutes apart agree it has (Phase 3's caution), or
// at once after this phone's own Edit took it out (question 3) - and all of it once the playlist is gone (missing from
// two lists 10 minutes apart, or deleted here). A song that keeps another origin - its own download, its album's, your
// library's, another playlist's - stays: Phase 2's removeOrigins deletes only a song left with none.

// MARK: the origin

extension DownloadOrigin {
    /// What a playlist's origin is written as: `playlist:<id>`, the raw Phase 2 reserved - a store that kept one reads
    /// it back as the same origin.
    static let playlistPrefix = "playlist:"

    /// A downloaded playlist's origin (`playlist:<id>`).
    public static func playlist(_ id: String) -> DownloadOrigin { .other(playlistPrefix + id) }

    /// The playlist's id, for a playlist's origin - nil for any other.
    public var playlistID: String? {
        guard case .other(let raw) = self, raw.hasPrefix(Self.playlistPrefix),
              raw.count > Self.playlistPrefix.count else { return nil }
        return String(raw.dropFirst(Self.playlistPrefix.count))
    }

    /// The downloaded playlists that want a song, by id.
    public static func playlists(_ origins: Set<DownloadOrigin>) -> [String] {
        origins.compactMap(\.playlistID).sorted()
    }

    /// Wanted only by what this phone keeps in step itself - your library, downloaded playlists - and not as a song's
    /// or an album's own download: Downloading's album rows leave such a song to the library's row and its playlists'.
    public static func keptInStep(_ origins: Set<DownloadOrigin>) -> Bool {
        !origins.isEmpty && origins.allSatisfy { (origin: DownloadOrigin) -> Bool in
            origin == .library || origin.playlistID != nil
        }
    }

    /// Wanted by downloaded playlists and nothing else: Downloaded's album rows leave such a song to its playlists'.
    public static func onlyPlaylists(_ origins: Set<DownloadOrigin>) -> Bool {
        !origins.isEmpty && origins.allSatisfy { (origin: DownloadOrigin) -> Bool in origin.playlistID != nil }
    }
}

// MARK: what each Remove Download takes

/// What each Remove Download takes from a song's origins (Phase 2 8.2, Phase 3 2.7, Phase 4 2.5) - and whether the song
/// then stays, another origin keeping it. A song is deleted only when it is left with none (DownloadRules.afterRemoving).
public enum DownloadRemoval {
    /// A song's own Remove Download: its own origin and its album's.
    public static func song(albumID: String) -> Set<DownloadOrigin> { [.song, .album(albumID)] }

    /// An album's: those, and your library's (which then keeps the album off this phone). Never a playlist's.
    public static func album(_ albumID: String) -> Set<DownloadOrigin> { [.song, .album(albumID), .library] }

    /// A downloaded playlist's: its own origin alone - its songs downloaded any other way stay.
    public static func playlist(_ id: String) -> Set<DownloadOrigin> { [.playlist(id)] }

    /// Whether a song with `origins` stays on this phone once `removed` is taken - another origin keeps it. A song with
    /// none kept reads as asked for alone (`song`), as the store's rules read it.
    public static func stays(_ origins: Set<DownloadOrigin>?, removing removed: Set<DownloadOrigin>) -> Bool {
        let its = origins.flatMap { (kept: Set<DownloadOrigin>) -> Set<DownloadOrigin>? in kept.isEmpty ? nil : kept }
            ?? [.song]
        return !its.subtracting(removed).isEmpty
    }
}

// MARK: a downloaded playlist, kept

/// One downloaded playlist as this phone keeps it - a row of the store's `playlist` table (version 6): its last answer
/// as deadwax sent it (so it opens and plays offline), when it was read, the marks keeping it in step, and when it was
/// downloaded.
public struct KeptPlaylist: Sendable, Equatable, Identifiable {
    public let id: String
    /// The last answer taken in - nil when the kept body couldn't be read: it is read again, and nothing is asked or
    /// taken by it meanwhile.
    public var answer: PlaylistWithSongs?
    /// That answer's body, as deadwax sent it (or, for a playlist downloaded from the answer in hand, as it was encoded
    /// until its first read).
    public var body: Data
    /// When it was last read (ms).
    public var readAt: Int64
    /// When the first list without it was asked for, or the first read answered it gone (ms) - nil while listed.
    public var missingSince: Int64?
    /// Songs carrying its origin that a read no longer had, each with when the first read without it was (ms): one is
    /// taken only once a read 10 minutes or more after that agrees (`leftAgreed`). A song this phone's Edit took out is
    /// marked as agreed already.
    public var left: [String: Int64]
    /// When it was downloaded (ms).
    public var askedAt: Int64

    public init(id: String, answer: PlaylistWithSongs?, body: Data, readAt: Int64, missingSince: Int64? = nil,
                left: [String: Int64] = [:], askedAt: Int64) {
        self.id = id
        self.answer = answer
        self.body = body
        self.readAt = readAt
        self.missingSince = missingSince
        self.left = left
        self.askedAt = askedAt
    }

    /// Its name, as last answered ("" for an unreadable one).
    public var name: String { answer?.playlist.name ?? "" }

    /// Its songs, each once, in the playlist's order - a song listed twice is downloaded once.
    public var songIDs: [String] {
        var seen = Set<String>()
        return (answer?.songs ?? []).map(\.id).filter { (id: String) -> Bool in seen.insert(id).inserted }
    }

    /// The songs two reads at least 10 minutes apart agree have left it (or this phone's Edit took out).
    public var leftAgreed: Set<String> {
        Set(left.filter { (mark: (key: String, value: Int64)) -> Bool in
            readAt - mark.value >= PlaylistDownloads.confirmAfterMs
        }.keys)
    }

    /// When a song found to have left is due its second read - the earliest not yet agreed, 10 minutes on; nil for none.
    public var secondReadAt: Int64? {
        let waiting = left.values.filter { (mark: Int64) -> Bool in readAt - mark < PlaylistDownloads.confirmAfterMs }
        return waiting.min().map { (mark: Int64) -> Int64 in mark + PlaylistDownloads.confirmAfterMs }
    }
}

// MARK: the rules

public enum PlaylistDownloads {
    /// Two observations agree only this far apart - a song gone from the playlist, the playlist gone from the list: Phase
    /// 3's ten minutes (LibraryFollow.confirmAfterMs).
    public static let confirmAfterMs = LibraryFollow.confirmAfterMs

    /// A playlist downloaded from the answer in hand at `at` (ms): kept as it is, its songs asked for at once. It is read
    /// again straight after - the body then kept is deadwax's own.
    public static func started(_ answer: PlaylistWithSongs, body: Data, at: Int64) -> KeptPlaylist {
        KeptPlaylist(id: answer.playlist.id, answer: answer, body: body, readAt: at, askedAt: at)
    }

    // MARK: the list

    /// What a list made of the downloaded playlists.
    public struct ListOutcome: Sendable, Equatable {
        /// The playlists kept, with their marks.
        public var kept: [KeptPlaylist]
        /// To be read now: their `changed` moved, they couldn't be read last time, or the list was empty.
        public var toRead: [String]
        /// Gone: missing from two lists at least 10 minutes apart - their origin is let go.
        public var letGo: [String]

        public init(kept: [KeptPlaylist] = [], toRead: [String] = [], letGo: [String] = []) {
            self.kept = kept
            self.toRead = toRead
            self.letGo = letGo
        }
    }

    /// The downloaded playlists after deadwax's list (asked for at `at`, ms - the moment a missing mark is dated by): one
    /// listed is no longer missing, and is read again when its `changed` moved - Navidrome moves it on every add and
    /// removal (notes/playlists.md) - or its kept answer couldn't be read; one not listed is marked missing, and let go
    /// once a list 10 minutes or more after the first without it agrees. An EMPTY list is never believed on its own (a
    /// Navidrome mid-rescan, a list that failed quietly): it marks nothing, and every downloaded playlist is read instead
    /// - a read answered 404 being a list without it (`missing`). One downloaded after the list was asked for is left as
    /// it is: the list can't speak for it. One the list says is smart (slice 3's review) is kept as it was, never read
    /// again (`frozen`) - though gone from two lists, it is let go as any is.
    public static func listed(_ kept: [KeptPlaylist], list: [Playlist], at: Int64) -> ListOutcome {
        var byID: [String: Playlist] = [:]
        for playlist in list where byID[playlist.id] == nil { byID[playlist.id] = playlist }
        var out = ListOutcome()
        for entry in kept {
            var entry = entry
            if entry.askedAt > at {
                out.kept.append(entry)
            } else if let listed = byID[entry.id], listed.smart {
                // never read: its `changed` moves each time Navidrome works it out again
                let smartAlready = entry.answer?.playlist.smart == true
                out.kept.append(smartAlready ? noLongerMissing(entry) : frozen(entry, as: listed, at: at))
            } else if let listed = byID[entry.id] {
                entry.missingSince = nil
                // (an answer that couldn't be read has no `changed`: it is read too)
                if listed.changed != entry.answer?.playlist.changed { out.toRead.append(entry.id) }
                out.kept.append(entry)
            } else if list.isEmpty {
                out.toRead.append(entry.id)
                out.kept.append(entry)
            } else {
                let marked = missing(entry, at: at)
                if marked.gone {
                    out.letGo.append(entry.id)
                } else {
                    out.kept.append(marked.entry)
                }
            }
        }
        return out
    }

    /// The playlist not listed, or answered gone (a read's 404), at `at` (ms): marked missing the first time; gone once
    /// that mark is 10 minutes old or more.
    public static func missing(_ entry: KeptPlaylist, at: Int64) -> (entry: KeptPlaylist, gone: Bool) {
        guard let since = entry.missingSince else {
            var marked = entry
            marked.missingSince = at
            return (marked, false)
        }
        return (entry, at - since >= confirmAfterMs)
    }

    static func noLongerMissing(_ entry: KeptPlaylist) -> KeptPlaylist {
        var out = entry
        out.missingSince = nil
        return out
    }

    // MARK: a read

    /// The playlist after a read answered at `at` (ms, when it was asked). `carrying`: the songs the store has under its
    /// origin. Found, it is no longer missing. A song carrying the origin that the answer hasn't is marked as left, dated
    /// by the first read without it - taken only once a read 10 minutes or more after that agrees - and one back in the
    /// playlist is no longer marked. `edited`: the songs this phone's own Edit took out (PlaylistEditBody.removed) - the
    /// answer is its Done's - each taken at once (marked as agreed already); nothing else is (slice 3's review: a Done
    /// that changed only the name is no reason to take a song Navidrome is hiding).
    ///
    /// **Songs Navidrome is hiding** (slice 3's review): the answer's `hidden` counts songs still in the playlist that it
    /// isn't listing just now (a file being moved, a rescan). While `hidden` is at least the songs carried that the
    /// answer lacks (the Edit's own aside), any of them may be one, so none of them is marked - they stay, and are
    /// marked only once a read lacks more songs than Navidrome is hiding.
    ///
    /// An EMPTY answer is never taken in on its own: while a song it would take hasn't been agreed, or Navidrome is
    /// hiding the songs it lacks, the answer kept stays (the page draws it, nothing is taken) - unless the Edit here
    /// emptied it.
    ///
    /// **A smart playlist** (slice 3's review, James: "No Download for them"): one found to be smart is kept as it was -
    /// its songs as last taken in, its marks dropped, read no more, nothing asked or taken by it again (`actions`).
    public static func read(_ entry: KeptPlaylist, answer: PlaylistWithSongs, body: Data, carrying: Set<String>,
                            at: Int64, edited: Set<String> = []) -> KeptPlaylist {
        if answer.playlist.smart { return frozen(entry, as: answer.playlist, at: at) }
        var out = entry
        out.missingSince = nil
        out.readAt = at
        let ids = Set(answer.songs.map(\.id))
        let lacking = carrying.subtracting(ids)
        let unexplained = lacking.subtracting(edited)
        let hiding = !unexplained.isEmpty && answer.hidden >= unexplained.count
        var left: [String: Int64] = [:]
        for id in lacking {
            if edited.contains(id) {
                left[id] = at - confirmAfterMs
            } else if !hiding {
                left[id] = min(entry.left[id] ?? at, at)
            }
        }
        out.left = left
        // (after an Edit here every mark it made is agreed already, so an answer it emptied is taken in)
        let emptied = answer.songs.isEmpty && !(entry.answer?.songs.isEmpty ?? true)
        if emptied && (hiding || left.values.contains(where: { (mark: Int64) -> Bool in at - mark < confirmAfterMs })) {
            return out
        }
        out.answer = answer
        out.body = body
        return out
    }

    /// A downloaded playlist found to be a smart one (`summary`, a list's or a read's), at `at` (ms): kept as it was -
    /// the songs last taken in, under that summary marked smart - no longer missing, its marks dropped. Its body is the
    /// kept answer encoded again, so the store keeps it as smart.
    static func frozen(_ entry: KeptPlaylist, as summary: Playlist, at: Int64) -> KeptPlaylist {
        var out = entry
        out.missingSince = nil
        out.readAt = at
        out.left = [:]
        let songs = entry.answer?.songs ?? []
        let kept = PlaylistWithSongs(playlist: summary.asSmart(songs: songs.count), songs: songs,
                                     hidden: entry.answer?.hidden ?? 0)
        out.answer = kept
        out.body = (try? JSONEncoder().encode(kept)) ?? entry.body
        return out
    }

    /// Whether a playlist may be downloaded: anything but a smart playlist (slice 3's review).
    public static func downloadable(_ playlist: Playlist) -> Bool { !playlist.smart }

    /// Whether a playlist's page treats it as smart: deadwax's answer in hand says so, or the answer kept here does (a
    /// downloaded one found smart is kept smart - `frozen`).
    public static func isSmart(_ answer: PlaylistWithSongs?, kept: KeptPlaylist?) -> Bool {
        answer?.playlist.smart == true || kept?.answer?.playlist.smart == true
    }

    /// What the playlist does to the store now.
    public struct Actions: Sendable, Equatable {
        /// Its songs not yet carrying its origin, each once, in its order: asked for under it.
        public var ask: [Song]
        /// Songs its origin is taken from (Phase 2's removeOrigins: deleted only when left with none) - those two reads
        /// agree have left it, or this phone's Edit took out.
        public var take: [String]

        public init(ask: [Song] = [], take: [String] = []) {
            self.ask = ask
            self.take = take
        }

        public var isEmpty: Bool { ask.isEmpty && take.isEmpty }
    }

    /// What `entry` asks of the store, `carrying` being the songs under its origin: its songs that don't carry it, and the
    /// agreed-left songs that do. Nothing at all while its kept answer can't be read, nor for a smart playlist (kept as
    /// it was). A song carrying the origin that the answer hasn't and no read has marked is kept: only a read takes
    /// anything.
    public static func actions(_ entry: KeptPlaylist, carrying: Set<String>) -> Actions {
        guard let answer = entry.answer, !answer.playlist.smart else { return Actions() }
        var seen = Set<String>()
        var ask: [Song] = []
        for song in answer.songs where seen.insert(song.id).inserted && !carrying.contains(song.id) { ask.append(song) }
        let agreed = entry.leftAgreed
        let take = carrying.filter { (id: String) -> Bool in !seen.contains(id) && agreed.contains(id) }.sorted()
        return Actions(ask: ask, take: take)
    }

    /// The songs each playlist's origin is on with no downloaded playlist of that id kept - its row deleted (a Remove
    /// Download or a playlist let go) before its origin could be taken, the app gone between the two: theirs to take
    /// as the store opens. By playlist id, each list sorted.
    public static func orphans(_ origins: [String: Set<DownloadOrigin>], kept: Set<String>) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (song, its) in origins {
            for id in DownloadOrigin.playlists(its) where !kept.contains(id) { out[id, default: []].append(song) }
        }
        return out.mapValues { (songs: [String]) -> [String] in songs.sorted() }
    }

    // MARK: when

    /// The playlists to read now beside the list's: one whose kept answer couldn't be read, and one whose song found to
    /// have left is due its second read (at `now`, ms). In the kept order.
    public static func dueReads(_ kept: [KeptPlaylist], now: Int64) -> [String] {
        kept.filter { (entry: KeptPlaylist) -> Bool in
            if entry.answer == nil { return true }
            guard let due = entry.secondReadAt else { return false }
            return now >= due
        }.map(\.id)
    }

    /// When the downloaded playlists next need a look without anything happening: the earliest second read due, or the
    /// earliest missing mark's confirmation (10 minutes on) - nil for none.
    public static func nextLook(_ kept: [KeptPlaylist]) -> Int64? {
        var times: [Int64] = []
        for entry in kept {
            if let due = entry.secondReadAt { times.append(due) }
            if let since = entry.missingSince { times.append(since + confirmAfterMs) }
        }
        return times.min()
    }

    /// Whether the downloaded playlists are looked at for `reason` - at the library follower's cadence
    /// (LibraryFollow.due: at once for a store opened, a change here, by hand; the front and deadwax back after a minute;
    /// the timer every 15 minutes) - or, the timer's minute, because a second read or a missing mark is due.
    public static func due(_ reason: LibraryCheck, lastBegan: Int64?, now: Int64, kept: [KeptPlaylist]) -> Bool {
        if LibraryFollow.due(reason, lastBegan: lastBegan, now: now) { return true }
        guard reason == .timer, let next = nextLook(kept) else { return false }
        return now >= next
    }

    // MARK: what the screens say

    /// The downloaded playlists as a list draws them - Downloaded playlists, and the Playlists screen with no connection
    /// and no list in hand: each as its last answer summed it up, by name (folded, as the Library sorts); one whose
    /// answer can't be read is left out (it is read again at the next look).
    public static func shelf(_ kept: [KeptPlaylist]) -> [Playlist] {
        kept.compactMap { (entry: KeptPlaylist) -> Playlist? in entry.answer?.playlist }.sorted { (a: Playlist, b: Playlist) -> Bool in
            let x = FoldKey(Fold.key(a.name)), y = FoldKey(Fold.key(b.name))
            return x != y ? x < y : a.id < b.id
        }
    }

    /// The downloaded playlist that keeps a song, for its menu's title ("Downloaded with Late night"): of those whose
    /// origin it carries, the first by name (folded, as the Library sorts) - nil for none.
    public static func keeping(_ origins: Set<DownloadOrigin>?, kept: [KeptPlaylist]) -> KeptPlaylist? {
        let ids = Set(DownloadOrigin.playlists(origins ?? []))
        guard !ids.isEmpty else { return nil }
        return kept.filter { (entry: KeptPlaylist) -> Bool in ids.contains(entry.id) }.min { (a: KeptPlaylist, b: KeptPlaylist) -> Bool in
            let x = FoldKey(Fold.key(a.name)), y = FoldKey(Fold.key(b.name))
            return x != y ? x < y : a.id < b.id
        }
    }

    /// A downloaded playlist's state, from its songs' (each once) - the control, the hero's line: nil when it isn't
    /// downloaded (the control's arrow). A song not yet asked for under it counts as waiting (it is asked at the keeper's
    /// next turn); an empty playlist is downloaded.
    public static func state(downloaded: Bool, songs: [AlbumSongFacts]) -> AlbumDownload? {
        guard downloaded else { return nil }
        guard !songs.isEmpty else { return .downloaded(checking: false) }
        let asked = songs.map { (song: AlbumSongFacts) -> AlbumSongFacts in
            song.state == .none ? AlbumSongFacts(state: .waiting(.queued), expected: song.expected, received: song.received)
                : song
        }
        return AlbumDownload.of(asked)
    }

    /// The playlist's download items (the control's menu, its •••): Download while it isn't downloaded - never for a
    /// smart playlist (slice 3's review); Download Again (its songs that didn't download) and Remove Download once some
    /// didn't; else Remove Download - a downloaded one found to be smart keeps both, its songs as they were.
    public static func choices(_ state: AlbumDownload?, smart: Bool = false) -> [DownloadChoice] {
        guard let state else { return smart ? [] : [.download] }
        if case .failed = state { return [.downloadAgain, .remove] }
        return [.remove]
    }

    /// Each downloaded playlist's songs as its kept answer lists them, by playlist id - made once a draw, for
    /// drawnWithPlaylists.
    public static func listing(_ kept: [KeptPlaylist]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for entry in kept { out[entry.id] = Set(entry.songIDs) }
        return out
    }

    /// (slice 3's review) Whether a song is drawn under its downloaded playlists' rows in You > Downloads: one of the
    /// playlists whose origin it carries lists it in its kept answer (`listing`). A song one no longer lists (marked,
    /// still coming, or one Navidrome is hiding) is drawn under its album's row instead, so it is always somewhere.
    public static func drawnWithPlaylists(_ song: String, origins: Set<DownloadOrigin>,
                                          listing: [String: Set<String>]) -> Bool {
        origins.contains { (origin: DownloadOrigin) -> Bool in
            guard let id = origin.playlistID else { return false }
            return listing[id]?.contains(song) == true
        }
    }

    /// Downloading's album rows: a song asked for any other way (by hand, with an album) - and one only this phone keeps
    /// in step (keptInStep) that neither your library's row (it carries `.library`) nor a downloaded playlist's draws.
    public static func inDownloadingAlbumRow(_ song: String, origins: Set<DownloadOrigin>,
                                             listing: [String: Set<String>]) -> Bool {
        guard DownloadOrigin.keptInStep(origins) else { return true }
        return !origins.contains(.library) && !drawnWithPlaylists(song, origins: origins, listing: listing)
    }

    /// Downloaded's album rows: a song kept any way but downloaded playlists' alone (onlyPlaylists) - and one only they
    /// keep that none of their rows draws.
    public static func inDownloadedAlbumRow(_ song: String, origins: Set<DownloadOrigin>,
                                            listing: [String: Set<String>]) -> Bool {
        !DownloadOrigin.onlyPlaylists(origins) || !drawnWithPlaylists(song, origins: origins, listing: listing)
    }

    /// Downloading's row for a downloaded playlist: its songs still to come (each once - waiting, fetching, or not yet
    /// asked), of all its songs; nil when none is (`states` beside `entry.songIDs`). A song that didn't download is
    /// Didn't download's, not to come.
    public static func progress(_ entry: KeptPlaylist, states: [SongDownload]) -> Progress? {
        let of = entry.songIDs.count
        let toGo = states.prefix(of).filter { (state: SongDownload) -> Bool in
            switch state {
            case .none, .waiting, .fetching: return true
            case .done, .failed: return false
            }
        }.count
        guard toGo > 0 else { return nil }
        return Progress(toGo: toGo, of: of)
    }

    /// "3 of 12 songs to go".
    public struct Progress: Sendable, Equatable {
        public let toGo: Int
        public let of: Int

        public init(toGo: Int, of: Int) {
            self.toGo = toGo
            self.of = of
        }

        /// The songs here of those it has, 0...1.
        public var fraction: Double { of > 0 ? Double(of - toGo) / Double(of) : 0 }
    }
}

// MARK: the words

/// Slice 3's words (phase4-library.md 6.3): Download and Remove Download are Phase 2's (DownloadWords).
public enum PlaylistDownloadWords {
    /// A song's menu title while a downloaded playlist keeps it.
    public static func downloadedWith(_ name: String) -> String { "Downloaded with \(name)" }
    /// The hero's line once every song of it is here.
    public static let playsOffline = "This playlist is downloaded - it plays with no connection."
    /// (slice 3's review, James: "No Download for them") A smart playlist's page, where Download would be.
    public static let smartOnline = "Smart playlists are worked out again each time, so this one plays only while deadwax can be reached."
    /// A smart playlist downloaded before deadwax said it was one, once every song of it is here: kept as it was.
    public static let smartKept = "Smart playlists are worked out again each time, so this download stays as it was when you made it."

    /// A downloaded playlist's hero line: the album's line (DownloadWords.albumLine) while its songs come or some didn't,
    /// and `playsOffline` once they are all here (`smartKept` for a smart one); not downloaded, a smart playlist's
    /// `smartOnline`, else none.
    public static func heroLine(_ state: AlbumDownload?, smart: Bool = false) -> String? {
        guard let state else { return smart ? smartOnline : nil }
        if case .downloaded = state { return smart ? smartKept : playsOffline }
        return DownloadWords.albumLine(state)
    }
    /// The Library's On this phone place, and its screen's title.
    public static let place = "Downloaded playlists"
    /// That screen with none.
    public static let noneYet = "No downloaded playlists yet."
    public static let noneYetHow = "Open a playlist and tap the download button beside its ••• - it then plays with no connection, and keeps in step as it changes."
    /// The Playlists screen offline with no list in hand, over the downloaded ones.
    public static let offlineDownloaded = "Your downloaded playlists - the rest show once deadwax is back."

    /// Downloading's row: what its songs wait for (a wait a setting or the room causes), else "3 of 12 songs to go".
    public static func downloadingRow(_ progress: PlaylistDownloads.Progress, wait: DownloadWait?) -> String {
        if let wait, wait != .queued { return DownloadWords.wait(wait) }
        let of = "\(UpNextWords.grouped(progress.of)) \(progress.of == 1 ? "song" : "songs")"
        return "\(UpNextWords.grouped(progress.toGo)) of \(of) to go"
    }

    /// Spoken: "Late night, 3 of 12 songs to go, 40 percent".
    public static func downloadingSpoken(_ name: String, _ progress: PlaylistDownloads.Progress, wait: DownloadWait?)
        -> String {
        "\(name), \(downloadingRow(progress, wait: wait)), \(DownloadWords.percent(progress.fraction))"
    }

    /// A place row's count, spoken: "1 playlist", "3 playlists".
    public static func count(_ n: Int) -> String { "\(UpNextWords.grouped(n)) \(n == 1 ? "playlist" : "playlists")" }

    /// Remove All's dialog, with playlists downloaded: they go too (nil for none).
    public static func removeAllToo(playlists n: Int) -> String? {
        guard n > 0 else { return nil }
        if n == 1 { return "Your downloaded playlist goes from this phone too - it stays in your playlists." }
        return "Your \(UpNextWords.grouped(n)) downloaded playlists go from this phone too - they stay in your playlists."
    }

    /// Every line, for the vocabulary's test.
    public static var everyLine: [String] {
        let progress = PlaylistDownloads.Progress(toGo: 3, of: 12)
        return [downloadedWith("Late night"), playsOffline, smartOnline, smartKept, place, noneYet, noneYetHow, offlineDownloaded,
                downloadingRow(progress, wait: nil), downloadingRow(progress, wait: .wifi),
                downloadingSpoken("Late night", progress, wait: nil), count(1), count(3),
                removeAllToo(playlists: 1) ?? "", removeAllToo(playlists: 3) ?? ""]
    }
}
