import Foundation

/// The artist tools (Phase 8, slice 5 - notes/ios-specs/phase8-managing.md 4): Artist images…, Which artist is this? and
/// Move albums to {name}… from an artist page's •••, the web's ArtistPanel (app/ArtistPanel.tsx: its modes images, who
/// and refile) and its rules, lib/artistManage.ts (`libraryNames`, `namesToMove`, `imagesFolder`, `bestUrls`,
/// `toggleChoice`, `byKind`, `slotLine`, `imageNotes`, `savedLine`, `matchLine`, `refileView`, `canMove`, `moveLine`,
/// `moveButton`, `refileAfter`, `refileOutcome`, `listed`). Held to the TypeScript by ArtistManageVectorTests over
/// Fixtures/artists/artist-manage-vectors.json (ios/scripts/export-artist-manage-vectors.cjs runs it as it is;
/// ui/test/iosartistmanage.sim.cjs checks the fixture is current).
///
/// Every route takes the LIBRARY'S name for the artist - the album artist the scan read - not Navidrome's: the library
/// may file one artist's albums under several names (Ye's page holds Donda, filed as "Kanye West", and BULLY, filed as
/// "Ye"). Names are compared as JavaScript compares strings, unit for unit (WebText.same).
public enum ArtistManage {
    /// Who the page is about, as far as finding their folders goes (artistManage.ts `ArtistWho`).
    public struct Who: Sendable, Equatable {
        /// Their MusicBrainz id, when the page knows it.
        public let mbid: String?
        /// The name to match an untagged folder by: Navidrome's for them, else MusicBrainz's.
        public let name: String?
        /// The releases of the albums Navidrome lists under them.
        public let releases: [String]

        public init(mbid: String?, name: String?, releases: [String]) {
            self.mbid = mbid
            self.name = name
            self.releases = releases
        }
    }

    /// `libraryNames(index, who)`: every name the library files this artist's albums under, in a steady order. A
    /// folder by several artists (a collaboration) is never one of theirs; a folder by one artist is theirs when that is
    /// the page's artist - or, with no id known to the page, when it goes by their name; a folder carrying no artist id
    /// when Navidrome lists its album under them, or it goes by their name.
    public static func libraryNames(_ index: OwnedIndex?, who: Who) -> [String] {
        let mbid = MBID.of(who.mbid)
        let name = Fold.key(who.name)
        let releases = Set(who.releases.compactMap { MBID.of($0) })
        var names: [String] = []
        var seen = Set<[UInt16]>()
        for album in ArtistJoin.everyOwned(index) {
            let artist = album.artist ?? ""
            if WebText.trim(artist).isEmpty { continue }
            let ids = (album.albumartistMbids ?? []).compactMap { MBID.of($0) }
            if ids.count > 1 { continue }
            let byName = !name.isEmpty && WebText.same(Fold.key(artist), name)
            let release = MBID.of(album.releaseMbid)
            let byRelease = release.map { releases.contains($0) } ?? false
            let theirs = mbid.map { (mbid: String) -> Bool in
                ids.count == 1 ? WebText.same(ids[0], mbid) : byName || byRelease
            } ?? (byName || byRelease)
            if theirs, seen.insert(Array(artist.utf16)).inserted { names.append(artist) }
        }
        return names.sorted { (a: String, b: String) -> Bool in
            let folded = WebCollation.compare(Fold.key(a), Fold.key(b))
            return (folded != 0 ? folded : WebCollation.compare(a, b)) < 0
        }
    }

    /// `namesToMove(names, current)`: the names that aren't MusicBrainz's name for them now - what Move albums to
    /// {name} moves. None while their name now isn't known.
    public static func namesToMove(_ names: [String], current: String?) -> [String] {
        let now = WebText.trim(current ?? "")
        guard !now.isEmpty else { return [] }
        return names.filter { !WebText.same($0, now) }
    }

    /// Where their pictures go (`ImagesFolder`): the name whose folder takes them, or why none does.
    public struct ImagesFolder: Sendable, Equatable {
        /// The library name the images routes are asked about - nil: none can be.
        public let name: String?
        /// Why Artist images… can't be used (nil: it can, or the folder isn't known yet).
        public let reason: String?

        public init(name: String?, reason: String?) {
            self.name = name
            self.reason = reason
        }
    }

    /// What `/library/artist` said of one name: its summary, or that it couldn't be read (the web's map's `null`).
    public enum Said: Sendable, Equatable {
        case answered(ArtistSummary)
        case unread
    }

    /// `imagesFolder(names, current, summaries)`: the current name's folder when the library files them under it, else
    /// the only name's. Under several names and none of them current, none - they're moved first; a name whose albums
    /// share no folder says why (the summary's own words). `summaries` holds a name's word once asked - a name not in
    /// it isn't known yet.
    public static func imagesFolder(_ names: [String], current: String?, summaries: [(name: String, said: Said)])
        -> ImagesFolder {
        guard !names.isEmpty else { return ImagesFolder(name: nil, reason: nil) }
        let now = WebText.trim(current ?? "")
        let name: String?
        if !now.isEmpty, names.contains(where: { WebText.same($0, now) }) {
            name = now
        } else {
            name = names.count == 1 ? names[0] : nil
        }
        guard let name else {
            return ImagesFolder(name: nil, reason: now.isEmpty
                ? "Their albums are filed under \(names.count) names, so there's no one folder for their pictures"
                : "Their albums are filed under \(names.count) names - move them under \(now) first, so their pictures "
                    + "have one folder")
        }
        // a Map's get: the first entry of that name, unit for unit
        switch summaries.first(where: { WebText.same($0.name, name) })?.said {
        case .unread?:
            return ImagesFolder(name: name, reason: "deadwax couldn't read their folder just now")
        case .answered(let summary)? where (summary.path ?? "").isEmpty:
            return ImagesFolder(name: name, reason: capital(summary.folderProblem ?? "they have no folder of their own"))
        default:
            return ImagesFolder(name: name, reason: nil)
        }
    }

    /// `charAt(0).toUpperCase() + slice(1)`: the first UTF-16 unit's character uppercased (a lone surrogate has none).
    static func capital(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, first.value <= 0xFFFF else { return text }
        return String(first.properties.uppercaseMapping) + String(text.unicodeScalars.dropFirst())
    }

    // MARK: Artist images…

    /// `bestUrls(preview)`: what "everything, best source first" would write - the picker's starting point.
    public static func bestUrls(_ best: [String: ArtistImageCandidate]) -> [String: String] {
        best.mapValues(\.url)
    }

    /// `toggleChoice(chosen, kind, url)`: a picture chosen for a slot - or, chosen already, taken back: that slot isn't
    /// written.
    public static func toggleChoice(_ chosen: [String: String], kind: String, url: String) -> [String: String] {
        var next = chosen
        if let now = chosen[kind], WebText.same(now, url) {
            next[kind] = nil
        } else {
            next[kind] = url
        }
        return next
    }

    /// `byKind(candidates)`: the pictures found, by the slot their source says they are, in the order found.
    public static func byKind(_ candidates: [ArtistImageCandidate]) -> [String: [ArtistImageCandidate]] {
        Dictionary(grouping: candidates, by: \.kind)
    }

    /// `slotLine(existing, found)`: a slot's line beside its name - the file already on disk, or that nothing was found.
    public static func slotLine(existing: String?, found: Int) -> String {
        if let existing, !existing.isEmpty { return "\(existing) on disk" }
        return found > 0 ? "" : "none found for this"
    }

    /// `imageNotes(preview)`: what the picker says about the sources it couldn't ask - the keys deadwax's settings hold.
    public static func imageNotes(hasKey: Bool, fanarttv: Bool?) -> [String] {
        if !hasKey {
            return ["Banners, logos and backgrounds come from fanart.tv and TheAudioDB, and both need a key - in "
                + "deadwax's settings, under Connections. Without either there is only what Wikimedia Commons has, which "
                + "is usually a single photograph - though you can put that in any slot below."]
        }
        if fanarttv != true {
            return ["fanart.tv isn't set up. Its artwork is voted on by the people using it, so it is usually the better "
                + "of the two - a key of your own goes in deadwax's settings, under Connections."]
        }
        return []
    }

    /// `savedLine(results)`: the files written, else the first problem, else that nothing needed writing.
    public static func savedLine(written: [String], problems: [String]) -> String {
        if !written.isEmpty { return "Saved \(written.joined(separator: ", "))." }
        return problems.first ?? "Nothing needed writing."
    }

    /// `matchLine(match)`: a MusicBrainz artist found by a search, in a line - the name they matched as, who they are.
    public static func matchLine(_ match: MBArtistMatch) -> String { match.line }

    /// A search's words as the web sends them (`query.trim()`) - empty: nothing to search for.
    public static func searchWords(_ query: String) -> String { WebText.trim(query) }

    /// Whether two of a candidate's addresses are one, as the web compares them (`===`).
    public static func sameAddress(_ a: String, _ b: String) -> Bool { WebText.same(a, b) }

    // MARK: ArtistPanel.tsx's own (held by pattern - notes/ios.md, "The artist tools on the phone")

    /// The pictures a slot can take beyond its own kind's: every other picture found, so one source's square can be
    /// this slot's background (ImagesBody's `others`).
    public static func others(_ candidates: [ArtistImageCandidate], kind: String) -> [ArtistImageCandidate] {
        candidates.filter { !WebText.same($0.kind, kind) }
    }

    /// Move albums' second line under its title (ArtistPanel's `subtitle`): the names whose albums move and where -
    /// never the page's own name, which on the page of their name now would read "Ye → Ye".
    public static func refileSubtitle(moveNames: [String], current: String?, name: String) -> String {
        guard let current, !current.isEmpty, !moveNames.isEmpty else { return name }
        return "\(listed(moveNames)) → \(current)"
    }

    /// The names Move applies, in turn (RefileBody's `apply`): each whose plan has an album the preview shows moving -
    /// a name whose every album stays isn't asked.
    public static func namesApplied(_ plans: [NamedPlan], view: RefileView) -> [NamedPlan] {
        let moving = Set(view.moves.map { Array($0.path.utf16) })
        return plans.filter { $0.plan.moves.contains { moving.contains(Array($0.path.utf16)) } }
    }

    /// "Showing Nirvana (90s US grunge band)" (ImagesBody): whose pictures are drawn.
    public static func showing(_ who: String, disambiguation: String) -> String {
        "Showing \(who)\(disambiguation.isEmpty ? "" : " (\(disambiguation))")"
    }

    // MARK: Move albums to …

    /// One name's plan, as `/library/artist/refile/preview` answers it for that name (`NamedPlan`).
    public struct NamedPlan: Sendable, Equatable {
        public let name: String
        public let plan: ArtistRefilePlan

        public init(name: String, plan: ArtistRefilePlan) {
            self.name = name
            self.plan = plan
        }
    }

    /// Every name's plan as one (`RefileView`): each move and refusal, the problems once each.
    public struct RefileView: Sendable, Equatable {
        public let currentName: String
        public let toFolder: String
        public let moves: [RefileMove]
        public let refused: [RefileRefused]
        public let problems: [String]
        /// Nothing to move under any name.
        public let empty: Bool
    }

    /// `refileView(plans)`: every name's plan as one. Each name's plan is the route's for that name alone, which can't
    /// see the others': two names each holding a folder of one name would both plan the move to the same folder - so
    /// the later is shown staying, as its apply will find it.
    public static func refileView(_ plans: [NamedPlan]) -> RefileView? {
        guard let first = plans.first?.plan else { return nil }
        var taken = Set<[UInt16]>()
        var moves: [RefileMove] = []
        var refused: [RefileRefused] = []
        for named in plans {
            for move in named.plan.moves {
                if !taken.insert(Array(move.targetPath.utf16)).inserted {
                    refused.append(RefileRefused(album: move.album, path: move.path,
                                                 reason: "another album moves to '\(move.targetPath)'"))
                    continue
                }
                moves.append(move)
            }
            refused.append(contentsOf: named.plan.refused)
        }
        return RefileView(currentName: first.currentName, toFolder: first.toFolder, moves: moves, refused: refused,
                          problems: WebText.unique(plans.flatMap(\.plan.problems)), empty: moves.isEmpty)
    }

    /// `canMove(view)`: a plan with something to move and no problem.
    public static func canMove(_ view: RefileView?) -> Bool {
        guard let view else { return false }
        return !view.empty && view.problems.isEmpty && !view.moves.isEmpty
    }

    /// `moveLine(move)`: a move's second line - "2 tracks, 2 retagged".
    public static func moveLine(_ move: RefileMove) -> String {
        "\(move.files) track\(move.files == 1 ? "" : "s")" + (move.retag.isEmpty ? "" : ", \(move.retag.count) retagged")
    }

    /// `moveButton(moves)`: "Move 2 albums".
    public static func moveButton(_ moves: Int) -> String { "Move \(moves) album\(moves == 1 ? "" : "s")" }

    /// One name's apply, as the route answered it: the plan it recomputed, and what it did (`AppliedName`).
    public struct AppliedName: Sendable, Equatable {
        public let name: String
        public let plan: ArtistRefilePlan
        public let results: ArtistRefileResults

        public init(name: String, plan: ArtistRefilePlan, results: ArtistRefileResults) {
            self.name = name
            self.plan = plan
            self.results = results
        }
    }

    /// `refileAfter(previewed, applied, view)`: what the applies said beyond what moved and failed. `stayed`: each album
    /// the preview showed moving that the apply's own plan kept where it is. `emptied`: the names every album of which
    /// moved, nothing refused or failed - the names the library no longer files them under.
    public static func refileAfter(previewed: [NamedPlan], applied: [AppliedName], view: RefileView)
        -> (stayed: [String], emptied: [String]) {
        let moving = Set(view.moves.map { Array($0.path.utf16) })
        let stayed = applied.flatMap { (one: AppliedName) -> [String] in
            one.plan.refused.filter { moving.contains(Array($0.path.utf16)) }.map { "\($0.album): stays - \($0.reason)" }
        }
        let emptied = previewed.filter { (named: NamedPlan) -> Bool in
            guard let done = applied.first(where: { WebText.same($0.name, named.name) }),
                  named.plan.refused.isEmpty, !named.plan.moves.isEmpty else { return false }
            if named.plan.moves.contains(where: { !moving.contains(Array($0.path.utf16)) }) { return false }
            return done.plan.refused.isEmpty && done.results.failed.isEmpty
                && done.results.moved.count == named.plan.moves.count
        }.map(\.name)
        return (stayed, emptied)
    }

    /// `refileOutcome(results, toFolder)`: what became of a move, every name's results joined.
    public static func refileOutcome(_ results: [ArtistRefileResults], toFolder: String)
        -> (moved: Int, text: String, failures: [String]) {
        let moved = results.reduce(0) { $0 + $1.moved.count }
        let failures = results.flatMap { $0.failed.map { "\($0.album): \($0.reason)" } }
        let pictures = results.flatMap(\.picturesMoved)
        let removed = results.flatMap(\.removedFolders)
        let parts = [
            moved > 0 ? "Moved \(moved) album\(moved == 1 ? "" : "s") into \(toFolder)/." : "Nothing was moved.",
            pictures.isEmpty ? "" : "Their pictures came too: \(pictures.joined(separator: ", ")).",
            removed.isEmpty ? "" : "\(listed(removed.map { "\($0)/" })) \(removed.count == 1 ? "was" : "were") left empty "
                + "and removed.",
        ]
        return (moved, parts.filter { !$0.isEmpty }.joined(separator: " "), failures)
    }

    /// `listed(items)`: "a", "a and b", "a, b and c".
    public static func listed(_ items: [String]) -> String {
        guard items.count >= 2 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

// MARK: - the answers (each field read loosely, as the rest of Core decodes)

/// `GET /library/artist`'s answer (routes/library.py `_artist_summary` and `art`): one name as the library knows it -
/// touches no network. A name the scan has no album under is a 404.
public struct ArtistSummary: Decodable, Sendable, Equatable {
    public let artist: String
    /// The folder their albums share - nil when there is none (`folderProblem` says why).
    public let path: String?
    public let folderProblem: String?
    public let albumCount: Int
    public let trackCount: Int
    public let totalSize: Double
    public let firstYear: String
    public let lastYear: String
    /// The pictures in their folder, by kind: kind -> its file's name.
    public let art: [String: String]

    public init(artist: String, path: String? = nil, folderProblem: String? = nil, albumCount: Int = 0,
                trackCount: Int = 0, totalSize: Double = 0, firstYear: String = "", lastYear: String = "",
                art: [String: String] = [:]) {
        self.artist = artist
        self.path = path
        self.folderProblem = folderProblem
        self.albumCount = albumCount
        self.trackCount = trackCount
        self.totalSize = totalSize
        self.firstYear = firstYear
        self.lastYear = lastYear
        self.art = art
    }

    enum CodingKeys: String, CodingKey {
        case artist, path, art
        case folderProblem = "folder_problem"
        case albumCount = "album_count"
        case trackCount = "track_count"
        case totalSize = "total_size"
        case firstYear = "first_year"
        case lastYear = "last_year"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        artist = fields.looseField(String.self, .artist) ?? ""
        path = fields.looseField(String.self, .path)
        folderProblem = fields.looseField(String.self, .folderProblem)
        albumCount = fields.looseField(Int.self, .albumCount) ?? 0
        trackCount = fields.looseField(Int.self, .trackCount) ?? 0
        totalSize = fields.looseField(Double.self, .totalSize) ?? 0
        firstYear = fields.looseField(String.self, .firstYear) ?? ""
        lastYear = fields.looseField(String.self, .lastYear) ?? ""
        art = fields.looseMap(String.self, .art) ?? [:]
    }
}

/// One picture a source offers (artists.py `_candidate`): the slot it is for, the address apply writes from, the
/// address it is shown by (Commons' a 600 px thumbnail - passed on by deadwax's relay), and where it is from.
public struct ArtistImageCandidate: Decodable, Sendable, Equatable, Hashable {
    public let kind: String
    public let url: String
    public let preview: String
    public let source: String
    public let label: String

    public init(kind: String, url: String, preview: String? = nil, source: String = "", label: String = "") {
        self.kind = kind
        self.url = url
        self.preview = preview ?? url
        self.source = source
        self.label = label
    }

    enum CodingKeys: String, CodingKey { case kind, url, preview, source, label }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        kind = fields.looseField(String.self, .kind) ?? ""
        url = fields.looseField(String.self, .url) ?? ""
        preview = fields.looseField(String.self, .preview) ?? url
        source = fields.looseField(String.self, .source) ?? ""
        label = fields.looseField(String.self, .label) ?? ""
    }
}

/// A slot, as the preview lists them (`kinds`): its kind and its label ("Square image", "Banner"…).
public struct ArtistImageKind: Decodable, Sendable, Equatable, Hashable {
    public let kind: String
    public let label: String

    public init(kind: String, label: String) {
        self.kind = kind
        self.label = label
    }

    enum CodingKeys: String, CodingKey { case kind, label }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        kind = fields.looseField(String.self, .kind) ?? ""
        label = fields.looseField(String.self, .label) ?? ""
    }
}

/// `POST /library/artist/images/preview`'s answer: the name's summary, who they are (the id, how it was known, the
/// matches when it couldn't be), every picture the sources offer and the best of each kind, the slots, which sources
/// have keys, and what's wrong. Nothing written; no picture's bytes fetched.
public struct ArtistImagesPreview: Decodable, Sendable, Equatable {
    public let artist: String
    public let path: String?
    public let folderProblem: String?
    /// The pictures in their folder now, by kind.
    public let art: [String: String]
    /// Who they are on MusicBrainz - nil when it couldn't be settled (`matches` the choice).
    public let mbid: String?
    public let mbidSource: String?
    public let matches: [MBArtistMatch]
    public let facts: MBArtistFacts?
    public let candidates: [ArtistImageCandidate]
    public let best: [String: ArtistImageCandidate]
    public let kinds: [ArtistImageKind]
    public let fanarttv: Bool?
    public let theaudiodb: Bool?
    public let hasKey: Bool
    public let problems: [String]

    public init(artist: String, path: String? = nil, folderProblem: String? = nil, art: [String: String] = [:],
                mbid: String? = nil, mbidSource: String? = nil, matches: [MBArtistMatch] = [],
                facts: MBArtistFacts? = nil, candidates: [ArtistImageCandidate] = [],
                best: [String: ArtistImageCandidate] = [:], kinds: [ArtistImageKind] = [], fanarttv: Bool? = nil,
                theaudiodb: Bool? = nil, hasKey: Bool = false, problems: [String] = []) {
        self.artist = artist
        self.path = path
        self.folderProblem = folderProblem
        self.art = art
        self.mbid = mbid
        self.mbidSource = mbidSource
        self.matches = matches
        self.facts = facts
        self.candidates = candidates
        self.best = best
        self.kinds = kinds
        self.fanarttv = fanarttv
        self.theaudiodb = theaudiodb
        self.hasKey = hasKey
        self.problems = problems
    }

    enum CodingKeys: String, CodingKey {
        case artist, path, art, mbid, matches, facts, candidates, best, kinds, sources, problems
        case folderProblem = "folder_problem"
        case mbidSource = "mbid_source"
        case hasKey = "has_key"
    }

    enum SourceKeys: String, CodingKey { case fanarttv, theaudiodb }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        artist = fields.looseField(String.self, .artist) ?? ""
        path = fields.looseField(String.self, .path)
        folderProblem = fields.looseField(String.self, .folderProblem)
        art = fields.looseMap(String.self, .art) ?? [:]
        mbid = fields.looseField(String.self, .mbid)
        mbidSource = fields.looseField(String.self, .mbidSource)
        matches = (fields.looseList(MBArtistMatch.self, .matches) ?? []).filter { !$0.mbid.isEmpty }
        facts = fields.looseField(MBArtistFacts.self, .facts)
        candidates = (fields.looseList(ArtistImageCandidate.self, .candidates) ?? []).filter { !$0.url.isEmpty }
        best = (fields.looseMap(ArtistImageCandidate.self, .best) ?? [:]).filter { !$0.value.url.isEmpty }
        kinds = (fields.looseList(ArtistImageKind.self, .kinds) ?? []).filter { !$0.kind.isEmpty }
        let sources = try? fields.nestedContainer(keyedBy: SourceKeys.self, forKey: .sources)
        fanarttv = sources?.looseField(Bool.self, .fanarttv)
        theaudiodb = sources?.looseField(Bool.self, .theaudiodb)
        hasKey = fields.looseField(Bool.self, .hasKey) ?? false
        problems = fields.looseList(String.self, .problems) ?? []
    }

    /// `imageNotes(preview)`.
    public var notes: [String] { ArtistManage.imageNotes(hasKey: hasKey, fanarttv: fanarttv) }
}

/// What a save did (execute_artist_art's results): the files written and skipped, and what went wrong.
public struct ArtistImagesResults: Decodable, Sendable, Equatable {
    public let written: [String]
    public let skipped: [String]
    public let problems: [String]

    public init(written: [String] = [], skipped: [String] = [], problems: [String] = []) {
        self.written = written
        self.skipped = skipped
        self.problems = problems
    }

    enum CodingKeys: String, CodingKey { case written, skipped, problems }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        written = fields.looseList(String.self, .written) ?? []
        skipped = fields.looseList(String.self, .skipped) ?? []
        problems = fields.looseList(String.self, .problems) ?? []
    }

    /// `savedLine(results)`.
    public var line: String { ArtistManage.savedLine(written: written, problems: problems) }
}

/// `POST /library/artist/images/apply`'s answer: what was written, and the folder's pictures now.
public struct ArtistImagesApplied: Decodable, Sendable, Equatable {
    public let artist: String
    public let path: String
    public let results: ArtistImagesResults
    public let art: [String: String]

    public init(artist: String, path: String, results: ArtistImagesResults, art: [String: String]) {
        self.artist = artist
        self.path = path
        self.results = results
        self.art = art
    }

    enum CodingKeys: String, CodingKey { case artist, path, results, art }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        artist = fields.looseField(String.self, .artist) ?? ""
        path = fields.looseField(String.self, .path) ?? ""
        results = fields.looseField(ArtistImagesResults.self, .results) ?? ArtistImagesResults()
        art = fields.looseMap(String.self, .art) ?? [:]
    }
}

/// `POST /library/artist/search`'s answer: MusicBrainz's artists going by the words (up to eight).
public struct ArtistMatchesAnswer: Decodable, Sendable, Equatable {
    public let query: String
    public let matches: [MBArtistMatch]

    public init(query: String, matches: [MBArtistMatch]) {
        self.query = query
        self.matches = matches
    }

    enum CodingKeys: String, CodingKey { case query, matches }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        query = fields.looseField(String.self, .query) ?? ""
        matches = (fields.looseList(MBArtistMatch.self, .matches) ?? []).filter { !$0.mbid.isEmpty }
    }
}

/// One album a move takes (artist_refile.py's plan `moves`): from where, to where, its tracks and the files retagged.
public struct RefileMove: Decodable, Sendable, Equatable {
    public let album: String
    public let path: String
    public let targetPath: String
    public let files: Int
    /// The files whose album artist tag changes, by name.
    public let retag: [String]

    public init(album: String, path: String, targetPath: String, files: Int, retag: [String] = []) {
        self.album = album
        self.path = path
        self.targetPath = targetPath
        self.files = files
        self.retag = retag
    }

    enum CodingKeys: String, CodingKey {
        case album, path, files, retag
        case targetPath = "target_path"
    }

    enum RetagKeys: String, CodingKey { case filename }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        album = fields.looseField(String.self, .album) ?? ""
        path = fields.looseField(String.self, .path) ?? ""
        targetPath = fields.looseField(String.self, .targetPath) ?? ""
        files = fields.looseField(Int.self, .files) ?? 0
        retag = (fields.looseList(RefileRetag.self, .retag) ?? []).map(\.filename)
    }
}

/// One file of a move's retag: its name (its `changes` aren't drawn).
struct RefileRetag: Decodable {
    let filename: String

    enum CodingKeys: String, CodingKey { case filename }

    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        filename = fields.looseField(String.self, .filename) ?? ""
    }
}

/// An album that stays where it is, and why (the plan's `refused`).
public struct RefileRefused: Decodable, Sendable, Equatable {
    public let album: String
    public let path: String
    public let reason: String

    public init(album: String, path: String, reason: String) {
        self.album = album
        self.path = path
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey { case album, path, reason }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        album = fields.looseField(String.self, .album) ?? ""
        path = fields.looseField(String.self, .path) ?? ""
        reason = fields.looseField(String.self, .reason) ?? ""
    }
}

/// `POST /library/artist/refile/preview`'s answer (artist_refile.py `plan_artist_refile`, and the route's problems):
/// the name MusicBrainz uses now, the folder they go into, each album that moves and each that stays.
public struct ArtistRefilePlan: Decodable, Sendable, Equatable {
    public let currentName: String
    public let toFolder: String
    public let artistMbid: String?
    public let moves: [RefileMove]
    public let refused: [RefileRefused]
    public let problems: [String]
    public let empty: Bool

    public init(currentName: String, toFolder: String, artistMbid: String? = nil, moves: [RefileMove] = [],
                refused: [RefileRefused] = [], problems: [String] = [], empty: Bool? = nil) {
        self.currentName = currentName
        self.toFolder = toFolder
        self.artistMbid = artistMbid
        self.moves = moves
        self.refused = refused
        self.problems = problems
        self.empty = empty ?? moves.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case moves, refused, problems, empty
        case currentName = "current_name"
        case toFolder = "to_folder"
        case artistMbid = "artist_mbid"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        currentName = fields.looseField(String.self, .currentName) ?? ""
        toFolder = fields.looseField(String.self, .toFolder) ?? ""
        artistMbid = fields.looseField(String.self, .artistMbid)
        moves = fields.looseList(RefileMove.self, .moves) ?? []
        refused = fields.looseList(RefileRefused.self, .refused) ?? []
        problems = fields.looseList(String.self, .problems) ?? []
        empty = fields.looseField(Bool.self, .empty) ?? moves.isEmpty
    }
}

/// What a move did (execute_artist_refile): each album moved, each that failed and why, the pictures that came, the
/// folders left empty and removed.
public struct ArtistRefileResults: Decodable, Sendable, Equatable {
    public struct Moved: Decodable, Sendable, Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }

        enum CodingKeys: String, CodingKey { case from, to }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            from = fields.looseField(String.self, .from) ?? ""
            to = fields.looseField(String.self, .to) ?? ""
        }
    }

    public struct Failed: Decodable, Sendable, Equatable {
        public let album: String
        public let reason: String

        public init(album: String, reason: String) {
            self.album = album
            self.reason = reason
        }

        enum CodingKeys: String, CodingKey { case album, reason }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            album = fields.looseField(String.self, .album) ?? ""
            reason = fields.looseField(String.self, .reason) ?? ""
        }
    }

    public let moved: [Moved]
    public let failed: [Failed]
    public let picturesMoved: [String]
    public let removedFolders: [String]

    public init(moved: [Moved] = [], failed: [Failed] = [], picturesMoved: [String] = [], removedFolders: [String] = []) {
        self.moved = moved
        self.failed = failed
        self.picturesMoved = picturesMoved
        self.removedFolders = removedFolders
    }

    enum CodingKeys: String, CodingKey {
        case moved, failed
        case picturesMoved = "pictures_moved"
        case removedFolders = "removed_folders"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        moved = fields.looseList(Moved.self, .moved) ?? []
        failed = fields.looseList(Failed.self, .failed) ?? []
        picturesMoved = fields.looseList(String.self, .picturesMoved) ?? []
        removedFolders = fields.looseList(String.self, .removedFolders) ?? []
    }
}

/// `POST /library/artist/refile/apply`'s answer: the plan it worked out again, and what it did.
public struct ArtistRefileApplied: Decodable, Sendable, Equatable {
    public let plan: ArtistRefilePlan
    public let results: ArtistRefileResults

    public init(plan: ArtistRefilePlan, results: ArtistRefileResults) {
        self.plan = plan
        self.results = results
    }

    enum CodingKeys: String, CodingKey { case plan, results }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        plan = fields.looseField(ArtistRefilePlan.self, .plan) ?? ArtistRefilePlan(currentName: "", toFolder: "")
        results = fields.looseField(ArtistRefileResults.self, .results) ?? ArtistRefileResults()
    }
}

// MARK: - what the phone sends (each the server's model's declared fields alone)

/// `ArtistImagesRequest`: the library's name, who they are (the preview's answer, so apply doesn't search again), the
/// picture chosen for each slot (each one the sources offered - apply checks) and Replace.
public struct ArtistImagesBody: Encodable, Sendable, Equatable {
    public let artist: String
    public let artistMbid: String?
    public let choices: [String: String]
    public let replace: Bool

    public init(artist: String, artistMbid: String?, choices: [String: String] = [:], replace: Bool = false) {
        self.artist = artist
        self.artistMbid = artistMbid
        self.choices = choices
        self.replace = replace
    }

    enum CodingKeys: String, CodingKey {
        case artist, choices, replace
        case artistMbid = "artist_mbid"
    }
}

/// `ArtistSearchRequest`: the words to look for in MusicBrainz.
public struct ArtistSearchBody: Encodable, Sendable, Equatable {
    public let query: String

    public init(query: String) { self.query = query }

    enum CodingKeys: String, CodingKey { case query }
}

/// `ArtistRefileRequest`: the library's name whose albums move, and who they are (the page's id, as the web sends).
public struct ArtistRefileBody: Encodable, Sendable, Equatable {
    public let artist: String
    public let artistMbid: String?

    public init(artist: String, artistMbid: String?) {
        self.artist = artist
        self.artistMbid = artistMbid
    }

    enum CodingKeys: String, CodingKey {
        case artist
        case artistMbid = "artist_mbid"
    }
}
