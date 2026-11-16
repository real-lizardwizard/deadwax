import Foundation

/// Edit album's Release (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 3.3): which MusicBrainz release an album
/// on disk is, its fields corrected by hand, and the release written back - the web's components/MetadataEditor.tsx,
/// its rules in ui/src/lib/release.ts (the editor's half: the two queries, both scores, `buildRetagRelease` and its own
/// `flattenTracks`, `describeRelease`, `releaseTrackCount`, `currentName`) and its words in ui/src/lib/retagPlan.ts and
/// the component's own lines. Held to the TypeScript by Tests/DeadwaxCoreTests/Fixtures/edit/edit-vectors.json
/// (ios/scripts/export-edit-vectors.cjs runs it as it is; ui/test/iosedit.sim.cjs checks the file is current).
///
/// THE SEARCH. Fielded - `releasegroup:"…" AND (artist:"…" OR artistname:"…")` - unless something is typed, falling
/// back to the loose words when the fielded finds nothing; MusicBrainz's albums ranked against the FIELDS
/// (`score(_:fields:)` - year, exact title, studio album, unlikely types, its own score a tiebreak); the first
/// `groupsSearched` groups' pressings listed without their tracklists, ranked against the album on disk
/// (`score(_:album:)` - the id decisive, then track count, year, title). A pressing picked has its tracklist fetched on
/// its own, and only the newest pick's lands (RetagFlow).
///
/// THE PAYLOAD IS NOT A GET'S. `buildRetagRelease` looks like releasePayload.ts's (GetRelease.payload) and differs:
/// a track's credit is `entry['artist-credit'] ?? recording's` and `creditName(credit) || null` - null for an empty
/// credit, where a Get says "N/A"; the country `?? release.country`, a Get's `||`; no `album_artist`; `year` the first
/// four characters of whatever date there is, with no four-digit check. So this is its own port, with its own vectors.
public enum Retag {
    // MARK: the numbers

    /// `GROUPS_SEARCHED`: how many release groups get their pressings fetched - each at least one request against a
    /// service that allows about one a second.
    public static let groupsSearched = 3
    /// The search's `limit` (`fullySearch(query, 25, false)`).
    public static let searchLimit = 25
    /// `PREVIEW_DEBOUNCE_MS`: the preview waits this long after the last change - long enough to finish a word.
    public static let previewDebounceMs = 400

    // MARK: the queries

    /// `fieldedAlbumQuery(album, artist)`: the album by its title, the artist as credited or as called now -
    /// bracketed, so the AND binds to the whole OR; `\` and `"` escaped.
    public static func fieldedQuery(album: String, artist: String) -> String {
        "releasegroup:\(quoted(album)) AND (artist:\(quoted(artist)) OR artistname:\(quoted(artist)))"
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `plainAlbumQuery(album, artist)`: what the box shows while it is blank - the album and its artist.
    public static func plainQuery(album: String, artist: String) -> String {
        [JSText.trim(album), JSText.trim(artist)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// What a search asks first: what was typed, trimmed, else the fielded query from the fields.
    public static func firstQuery(typed: String, fields: RetagFields) -> String {
        let trimmed = JSText.trim(typed)
        return trimmed.isEmpty ? fieldedQuery(album: fields.album, artist: fields.artist) : trimmed
    }

    /// The fallback when the fielded query found nothing and nothing was typed: `${artist} ${album}`, trimmed - nil
    /// when something was typed (no fallback then).
    public static func looseQuery(typed: String, fields: RetagFields) -> String? {
        guard JSText.trim(typed).isEmpty else { return nil }
        return JSText.trim("\(fields.artist) \(fields.album)")
    }

    /// The editor searches as it opens - unless there is nothing to search on (no artist and no album), so an untagged
    /// album never sends `releasegroup:"" AND artist:""`.
    public static func searchesAtOnce(_ album: ScanAlbum) -> Bool {
        !JSText.trim(album.artist).isEmpty || !JSText.trim(album.album).isEmpty
    }

    // MARK: the scores

    /// `releaseTrackCount`: every disc's `track-count`, summed.
    public static func trackCount(_ release: PageRelease) -> Int {
        release.media.reduce(0) { $0 + ($1.trackCount ?? 0) }
    }

    /// `release['release-events']?.[0]?.date || release.date || ''` - the first event's date first.
    static func eventFirstDate(_ release: PageRelease) -> String {
        Credits.first(release.eventDates.first ?? nil, release.date)
    }

    /// `scoreReleaseMatch(release, album)`: how well a pressing matches the album on disk - the id decisive (1000),
    /// then the track count (100), the year (50), the title (25).
    public static func score(_ release: PageRelease, album: ScanAlbum) -> Int {
        if !album.releaseMbid.isEmpty && WebText.same(release.id, album.releaseMbid) { return 1000 }
        var score = 0
        let tracks = trackCount(release)
        if tracks != 0 && tracks == album.trackCount { score += 100 }
        let year = WebText.prefix(eventFirstDate(release), 4)
        if !year.isEmpty && WebText.same(year, album.year) { score += 50 }
        if WebText.same(JSText.lowercase(release.title ?? ""), JSText.lowercase(album.album)) { score += 25 }
        return score
    }

    /// `isCurrentRelease`: the pressing the album's tags already name.
    public static func isCurrent(_ release: PageRelease, _ albumRelease: String) -> Bool {
        !albumRelease.isEmpty && WebText.same(release.id, albumRelease)
    }

    /// `UNLIKELY_SECONDARY_TYPES`: usually not the copy in someone's library - a penalty, never a filter.
    public static let unlikelyTypes: Set<String> = [
        "Live", "Compilation", "Interview", "Remix", "DJ-mix", "Demo", "Mixtape/Street", "Audiobook",
    ]

    /// `scoreReleaseGroupMatch(group, {album, year, original_year})`, against the FIELDS: the year (100), the exact
    /// title (40), a studio album (30), an unlikely type (-30), MusicBrainz's own score a tenth.
    public static func score(_ group: ReleaseGroup, fields: RetagFields) -> Double {
        var score = 0.0
        let wanted = JSText.trim(fields.originalYear.isEmpty ? fields.year : fields.originalYear)
        let groupYear = WebText.prefix(group.firstReleaseDate ?? "", 4)
        if !wanted.isEmpty && !groupYear.isEmpty && WebText.same(wanted, groupYear) { score += 100 }
        if WebText.same(JSText.lowercase(JSText.trim(group.title ?? "")), JSText.lowercase(JSText.trim(fields.album))) {
            score += 40
        }
        let secondary = group.secondaryTypes ?? []
        if group.primaryType == "Album" && secondary.isEmpty { score += 30 }
        if secondary.contains(where: { unlikelyTypes.contains($0) }) { score -= 30 }
        let reported = group.score ?? 0
        if reported.isFinite { score += reported / 10 }
        return score
    }

    /// The groups in the order the editor looks inside them: best against the fields first, ties as MusicBrainz gave
    /// them (JavaScript's sort is stable).
    public static func rankGroups(_ groups: [ReleaseGroup], fields: RetagFields) -> [ReleaseGroup] {
        groups.enumerated()
            .map { (score: score($0.element, fields: fields), at: $0.offset, group: $0.element) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.at < $1.at }
            .map(\.group)
    }

    /// The pressings found, best match for the album on disk first - its own pressing, for a tagged album - ties in
    /// the order they were found.
    public static func rankReleases(_ found: [RetagCandidate], album: ScanAlbum) -> [RetagCandidate] {
        found.enumerated()
            .map { (score: score($0.element.release, album: album), at: $0.offset, candidate: $0.element) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.at < $1.at }
            .map(\.candidate)
    }

    // MARK: describing a pressing

    /// `describeRelease`: its disambiguation, formats, first event's country and first catalogue number, ` · `-joined.
    public static func describe(_ release: PageRelease) -> String {
        let formats = release.media.compactMap(\.format).filter { !$0.isEmpty }.joined(separator: " + ")
        let country = release.eventCountries.first ?? nil
        let catalog = release.labelInfo.compactMap(\.catalogNumber).first { !$0.isEmpty }
        return [release.disambiguation, formats, country, catalog].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// A row's detail line: the pressing's own year and its description (`[date?.substring(0, 4), describeRelease]`).
    public static func detail(_ release: PageRelease) -> String {
        [WebText.prefix(release.date ?? "", 4), describe(release)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A row's track count: "2 discs · 24 tracks", "1 track", "? tracks" when MusicBrainz didn't count them.
    public static func trackWords(_ release: PageRelease) -> String {
        let tracks = trackCount(release)
        let discs = release.media.count > 1 ? "\(release.media.count) discs · " : ""
        return discs + (tracks != 0 ? "\(tracks) \(tracks == 1 ? "track" : "tracks")" : "? tracks")
    }

    /// The pressing whose cover Compare covers shows and the cover alone saves (MetadataEditor's `incomingId`): the one
    /// chosen, else the one the folder is tagged with - nil for neither.
    public static func coverRelease(selected: String?, album: ScanAlbum) -> String? {
        selected ?? (album.releaseMbid.isEmpty ? nil : album.releaseMbid)
    }

    /// A row's track count differs from the folder's (the web's `mismatch`).
    public static func countDiffers(_ release: PageRelease, album: ScanAlbum) -> Bool {
        let tracks = trackCount(release)
        return tracks != 0 && tracks != album.trackCount
    }

    // MARK: the payload

    /// What `buildRetagRelease` is handed beside the release: who the album is by and its title (the editor's - the
    /// fields override both), and the group it was found in - carried by hand, since a release fetched on its own has
    /// no idea which search produced it.
    public struct Context: Sendable, Equatable {
        public let artist: String
        public let album: String
        public let releaseGroupMbid: String?
        /// The group's first-release-date - the album's own year, not this pressing's.
        public let firstReleaseDate: String?

        public init(artist: String, album: String, releaseGroupMbid: String? = nil, firstReleaseDate: String? = nil) {
            self.artist = artist
            self.album = album
            self.releaseGroupMbid = releaseGroupMbid
            self.firstReleaseDate = firstReleaseDate
        }
    }

    /// `buildRetagRelease(release, context)`: a MusicBrainz release as the retag routes take it.
    public static func release(_ release: PageRelease, context: Context) -> RetagRelease {
        let rawDate = eventFirstDate(release)
        let numbers = release.labelInfo.compactMap(\.catalogNumber).filter { !$0.isEmpty }
        let formats = release.media.compactMap(\.format).filter { !$0.isEmpty }
        let first = context.firstReleaseDate ?? ""
        return RetagRelease(
            artist: context.artist,
            artistMbids: GetRelease.creditIds(release.artistCredit),
            album: Credits.first(release.title, context.album),
            year: rawDate.isEmpty ? nil : WebText.prefix(rawDate, 4),
            originalYear: first.isEmpty ? nil : WebText.prefix(first, 4),
            releaseMbid: release.id,
            releaseGroupMbid: context.releaseGroupMbid,
            disambiguation: GetRelease.present(release.disambiguation),
            mediaFormat: GetRelease.present(formats.joined(separator: " + ")),
            country: (release.eventCountries.first ?? nil) ?? release.country,
            catalogNumber: GetRelease.present(numbers.joined(separator: ", ")),
            editionTags: EditionTags.detect(title: release.title, disambiguation: release.disambiguation,
                                            packaging: release.packaging),
            tracks: tracks(release),
            pressing: true)
    }

    /// The editor's `flattenTracks`: every track in running order, with its disc, its number on the disc, its own
    /// credit (`?? recording's`, null when it names nobody), the disc's own title and whether it is a video.
    static func tracks(_ release: PageRelease) -> [GetTrack] {
        var out: [GetTrack] = []
        var position = 0
        for (discIndex, medium) in release.media.enumerated() {
            let discTitle = GetRelease.present(JSText.trim(medium.title ?? ""))
            for (trackIndex, track) in medium.tracks.enumerated() {
                position += 1
                let credit = track.artistCredit ?? track.recording?.artistCredit
                out.append(GetTrack(
                    position: position,
                    title: Credits.first(track.recording?.title, track.title),
                    lengthMs: track.recording?.length ?? track.length,
                    disc: medium.position ?? discIndex + 1,
                    discPosition: track.position ?? trackIndex + 1,
                    artist: GetRelease.present(Credits.name(credit)),
                    artistMbids: GetRelease.creditIds(credit),
                    discTitle: discTitle,
                    video: GetRelease.isVideo(format: medium.format, recording: track.recording)))
            }
        }
        return out
    }

    /// What Apply writes (MetadataEditor's `payload`): the chosen pressing with the typed fields laid over it - or,
    /// with none chosen, the album's own values and no tracklist (so hand-editing works without MusicBrainz, and no
    /// file gets a title or number it didn't ask for), the release id the album already carries kept.
    public static func payload(selected: RetagCandidate?, album: ScanAlbum, fields: RetagFields) -> RetagRelease {
        var base: RetagRelease
        if let selected {
            base = release(selected.release, context: Context(artist: album.artist, album: album.album,
                                                               releaseGroupMbid: selected.groupMbid,
                                                               firstReleaseDate: selected.firstReleaseDate))
        } else {
            base = RetagRelease(artist: album.artist, album: album.album, year: GetRelease.present(album.year),
                                originalYear: GetRelease.present(album.originalYear),
                                releaseMbid: GetRelease.present(album.releaseMbid), tracks: [], pressing: false)
        }
        base.artist = fields.artist
        base.album = fields.album
        base.year = GetRelease.present(fields.year)
        base.originalYear = GetRelease.present(fields.originalYear)
        base.editionLabel = GetRelease.present(JSText.trim(fields.editionLabel))
        base.labelled = true
        return base
    }

    /// The fields a pressing picked fills in (MetadataEditor's `loadRelease` with `seedFields`): who the album is BY in
    /// their current name (`currentName(credit) || album.artist` - what it is filed under), its title, this pressing's
    /// year and the album's, and the edition left blank for the server to work out.
    public static func seeded(_ picked: RetagCandidate, album: ScanAlbum) -> RetagFields {
        let built = release(picked.release, context: Context(
            artist: Credits.first(Credits.current(picked.release.artistCredit), album.artist), album: album.album,
            releaseGroupMbid: picked.groupMbid, firstReleaseDate: picked.firstReleaseDate))
        return RetagFields(artist: built.artist, album: built.album, year: built.year ?? "",
                           originalYear: built.originalYear ?? "", editionLabel: "")
    }
}

/// A pressing the search found, with the group it was found in (MetadataEditor's `_groupMbid`, `_firstReleaseDate`).
public struct RetagCandidate: Sendable, Equatable, Hashable, Identifiable {
    public let release: PageRelease
    public let groupMbid: String?
    public let firstReleaseDate: String?

    public var id: String { release.id }

    public init(release: PageRelease, groupMbid: String?, firstReleaseDate: String?) {
        self.release = release
        self.groupMbid = groupMbid
        self.firstReleaseDate = firstReleaseDate
    }

    /// The same pressing with its tracklist (`/search_musicbrainz/release`'s answer), the group carried across.
    public func with(_ full: PageRelease) -> RetagCandidate {
        RetagCandidate(release: full, groupMbid: groupMbid, firstReleaseDate: firstReleaseDate)
    }

    /// A group's pressings as the search lists them (`/releases?tracks=false`).
    public static func found(_ releases: [PageRelease], in group: ReleaseGroup) -> [RetagCandidate] {
        releases.map { RetagCandidate(release: $0, groupMbid: group.id, firstReleaseDate: group.firstReleaseDate) }
    }
}

/// What can be typed (MetadataEditor's `Fields`): the artist and album, this pressing's year, the album's first year
/// (which names the folder) and the edition.
public struct RetagFields: Sendable, Equatable, Hashable {
    public var artist: String
    public var album: String
    public var year: String
    public var originalYear: String
    public var editionLabel: String

    public init(artist: String, album: String, year: String, originalYear: String, editionLabel: String) {
        self.artist = artist
        self.album = album
        self.year = year
        self.originalYear = originalYear
        self.editionLabel = editionLabel
    }

    /// Seeded from what is on disk, so the editor opens showing the album as it is - the edition blank for a
    /// "Standard" one.
    public init(_ album: ScanAlbum) {
        self.init(artist: album.artist, album: album.album, year: album.year, originalYear: album.originalYear,
                  editionLabel: album.edition == "Standard" ? "" : album.edition)
    }
}

/// A release as `/library/retag/preview` and `/apply` take it (src/routes/library.py RetagRelease): exactly the keys the
/// web sends - the chosen pressing's fourteen, or the album's own seven with none chosen; `edition_label` only once the
/// fields are laid over (`labelled`). pydantic drops anything else without a word.
public struct RetagRelease: Encodable, Sendable, Equatable {
    public var artist: String
    public var artistMbids: [String]
    public var album: String
    public var year: String?
    public var originalYear: String?
    public var releaseMbid: String?
    public var releaseGroupMbid: String?
    public var disambiguation: String?
    public var mediaFormat: String?
    public var country: String?
    public var catalogNumber: String?
    public var editionLabel: String?
    public var editionTags: [String]
    public var tracks: [GetTrack]
    /// Built from a pressing (`buildRetagRelease`): its own keys are sent.
    let pressing: Bool
    /// The fields laid over it: `edition_label` is sent.
    var labelled = false

    enum CodingKeys: String, CodingKey {
        case artist, album, year, tracks, disambiguation, country
        case artistMbids = "artist_mbids"
        case originalYear = "original_year"
        case releaseMbid = "release_mbid"
        case releaseGroupMbid = "release_group_mbid"
        case mediaFormat = "media_format"
        case catalogNumber = "catalog_number"
        case editionLabel = "edition_label"
        case editionTags = "edition_tags"
    }

    init(artist: String, artistMbids: [String] = [], album: String, year: String?, originalYear: String?,
         releaseMbid: String?, releaseGroupMbid: String? = nil, disambiguation: String? = nil,
         mediaFormat: String? = nil, country: String? = nil, catalogNumber: String? = nil, editionLabel: String? = nil,
         editionTags: [String] = [], tracks: [GetTrack], pressing: Bool) {
        self.artist = artist
        self.artistMbids = artistMbids
        self.album = album
        self.year = year
        self.originalYear = originalYear
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.disambiguation = disambiguation
        self.mediaFormat = mediaFormat
        self.country = country
        self.catalogNumber = catalogNumber
        self.editionLabel = editionLabel
        self.editionTags = editionTags
        self.tracks = tracks
        self.pressing = pressing
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(artist, forKey: .artist)
        try fields.encode(album, forKey: .album)
        try fields.encode(year, forKey: .year)
        try fields.encode(originalYear, forKey: .originalYear)
        try fields.encode(releaseMbid, forKey: .releaseMbid)
        try fields.encode(tracks, forKey: .tracks)
        if labelled { try fields.encode(editionLabel, forKey: .editionLabel) }
        guard pressing else { return }
        try fields.encode(artistMbids, forKey: .artistMbids)
        try fields.encode(releaseGroupMbid, forKey: .releaseGroupMbid)
        try fields.encode(disambiguation, forKey: .disambiguation)
        try fields.encode(mediaFormat, forKey: .mediaFormat)
        try fields.encode(country, forKey: .country)
        try fields.encode(catalogNumber, forKey: .catalogNumber)
        try fields.encode(editionTags, forKey: .editionTags)
    }
}

/// `POST /library/retag/preview` and `/apply`'s body (RetagRequest): the folder, the release, whether to fetch the cover.
public struct RetagRequestBody: Encodable, Sendable, Equatable {
    public let albumPath: String
    public let release: RetagRelease
    public let fetchArt: Bool

    public init(albumPath: String, release: RetagRelease, fetchArt: Bool) {
        self.albumPath = albumPath
        self.release = release
        self.fetchArt = fetchArt
    }

    enum CodingKeys: String, CodingKey {
        case release
        case albumPath = "album_path"
        case fetchArt = "fetch_art"
    }
}

/// `POST /library/art/fetch`'s body (CoverArtRequest): the cover only, replacing what is there, of the pressing shown.
public struct CoverFetchBody: Encodable, Sendable, Equatable {
    public let albumPath: String
    public let replace: Bool
    public let releaseMbid: String?

    public init(albumPath: String, replace: Bool, releaseMbid: String?) {
        self.albumPath = albumPath
        self.replace = replace
        self.releaseMbid = releaseMbid
    }

    enum CodingKeys: String, CodingKey {
        case replace
        case albumPath = "album_path"
        case releaseMbid = "release_mbid"
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(albumPath, forKey: .albumPath)
        try fields.encode(replace, forKey: .replace)
        try fields.encode(releaseMbid, forKey: .releaseMbid)
    }
}

/// `POST /library/art/fetch`'s answer: the file written and the one it replaced.
public struct CoverFetched: Decodable, Sendable, Equatable {
    public let written: String?
    public let replaced: String?

    enum CodingKeys: String, CodingKey { case written, replaced }

    public init(written: String?, replaced: String?) {
        self.written = written
        self.replaced = replaced
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        written = fields.looseField(String.self, .written)
        replaced = fields.looseField(String.self, .replaced)
    }
}

/// `POST /library/queue/ignore` and `/unignore`'s body (QueueRequest): the folder, and exactly the issues shown -
/// none for an unignore.
public struct QueueMarkBody: Encodable, Sendable, Equatable {
    public let albumPath: String
    public let issues: [String]?

    public init(albumPath: String, issues: [String]?) {
        self.albumPath = albumPath
        self.issues = issues
    }

    enum CodingKeys: String, CodingKey {
        case issues
        case albumPath = "album_path"
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(albumPath, forKey: .albumPath)
        if let issues { try fields.encode(issues, forKey: .issues) }
    }
}

/// `/queue/ignore` and `/unignore`'s answer: whether the album is marked fine now.
public struct QueueMarked: Decodable, Sendable, Equatable {
    public let ignored: Bool

    enum CodingKeys: String, CodingKey { case ignored }

    public init(ignored: Bool) {
        self.ignored = ignored
    }

    public init(from decoder: any Decoder) throws {
        ignored = try decoder.container(keyedBy: CodingKeys.self).looseField(Bool.self, .ignored) ?? false
    }
}

// MARK: the preview's answer

/// One tag a file would change (`changes[tag]`): what it holds now ("" for nothing) and what it would hold.
public struct TagChange: Sendable, Equatable, Hashable, Decodable {
    public let tag: String
    public let from: String
    public let to: String

    public init(tag: String, from: String, to: String) {
        self.tag = tag
        self.from = from
        self.to = to
    }

    enum CodingKeys: String, CodingKey { case from, to }

    struct Value: Decodable {
        let from: String
        let to: String

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            from = fields.looseField(String.self, .from) ?? ""
            to = fields.looseField(String.self, .to) ?? ""
        }
    }

    public init(from decoder: any Decoder) throws {
        let value = try Value(from: decoder)
        self.init(tag: "", from: value.from, to: value.to)
    }
}

/// One file of the preview (RetagFileChange): its name, the track it matched, and the tags it would change - in the
/// server's order (`RetagPlan.read` keeps it).
public struct RetagFileChange: Sendable, Equatable, Decodable {
    public let filename: String
    public let matched: Bool
    public let trackTitle: String
    public internal(set) var changes: [TagChange]

    enum CodingKeys: String, CodingKey {
        case filename, matched, changes
        case trackTitle = "track_title"
    }

    public init(filename: String, matched: Bool = true, trackTitle: String = "", changes: [TagChange]) {
        self.filename = filename
        self.matched = matched
        self.trackTitle = trackTitle
        self.changes = changes
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        filename = try fields.decode(String.self, forKey: .filename)
        matched = fields.looseField(Bool.self, .matched) ?? false
        trackTitle = fields.looseField(String.self, .trackTitle) ?? ""
        //? keyed by tag name; sorted here, put back in the server's order by RetagPlan.read
        let changed = fields.looseField([String: TagChange.Value].self, .changes) ?? [:]
        changes = changed.keys.sorted { FoldKey($0) < FoldKey($1) }
            .map { TagChange(tag: $0, from: changed[$0]!.from, to: changed[$0]!.to) }
    }
}

/// What a retag would do about the cover (RetagArtPlan): '' nothing, 'download', 'replace'; the cover there now; the
/// size it would be saved at ('250', '500', '1200', 'full' - laid on by the preview route).
public struct RetagArtPlan: Sendable, Equatable, Decodable {
    public let action: String
    public let reason: String
    public let existing: String?
    public let size: String?

    enum CodingKeys: String, CodingKey { case action, reason, existing, size }

    public init(action: String = "", reason: String = "", existing: String? = nil, size: String? = nil) {
        self.action = action
        self.reason = reason
        self.existing = existing
        self.size = size
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        action = fields.looseField(String.self, .action) ?? ""
        reason = fields.looseField(String.self, .reason) ?? ""
        existing = fields.looseField(String.self, .existing)
        size = fields.looseField(String.self, .size)
    }
}

/// The discs of one release stored one folder per disc (`merge_detail`).
public struct RetagMerge: Sendable, Equatable, Decodable {
    public let into: String
    public let discsHere: [Int]
    public let discsThere: [Int]
    public let keptBack: [String]

    enum CodingKeys: String, CodingKey {
        case into
        case discsHere = "discs_here"
        case discsThere = "discs_there"
        case keptBack = "kept_back"
    }

    public init(into: String, discsHere: [Int], discsThere: [Int], keptBack: [String]) {
        self.into = into
        self.discsHere = discsHere
        self.discsThere = discsThere
        self.keptBack = keptBack
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        into = fields.looseField(String.self, .into) ?? ""
        discsHere = fields.looseList(Int.self, .discsHere) ?? []
        discsThere = fields.looseList(Int.self, .discsThere) ?? []
        keptBack = fields.looseList(String.self, .keptBack) ?? []
    }
}

/// What applying a release would do (`POST /library/retag/preview`, RetagPlan) - a faithful report, never an
/// instruction: Apply sends the same request and the server works it out again.
public struct RetagPlan: Sendable, Equatable, Decodable {
    public let albumPath: String
    public let targetPath: String?
    public let moves: Bool
    public let merge: Bool
    public let mergeDetail: RetagMerge?
    public let editionLabel: String
    public internal(set) var files: [RetagFileChange]
    public let changedFileCount: Int
    public let fileCount: Int
    public let art: RetagArtPlan
    /// Warnings worth reading before applying - a track count that differs, files the tracklist didn't reach. Never
    /// a refusal: Apply goes ahead through them, as the web's does.
    public let problems: [String]
    /// Nothing to change: the album already carries this release, as chosen.
    public let empty: Bool
    /// Seconds the apply may pause before renaming (0 for none) - with `renameBy` "navidrome" the most it can take.
    public let renameWait: Double
    /// "navidrome", "timer" or nil.
    public let renameBy: String?

    enum CodingKeys: String, CodingKey {
        case moves, merge, files, art, problems, empty
        case albumPath = "album_path"
        case targetPath = "target_path"
        case mergeDetail = "merge_detail"
        case editionLabel = "edition_label"
        case changedFileCount = "changed_file_count"
        case fileCount = "file_count"
        case renameWait = "rename_wait"
        case renameBy = "rename_by"
    }

    public init(albumPath: String = "", targetPath: String? = nil, moves: Bool = false, merge: Bool = false,
                mergeDetail: RetagMerge? = nil, editionLabel: String = "", files: [RetagFileChange] = [],
                changedFileCount: Int = 0, fileCount: Int = 0, art: RetagArtPlan = RetagArtPlan(),
                problems: [String] = [], empty: Bool = false, renameWait: Double = 0, renameBy: String? = nil) {
        self.albumPath = albumPath
        self.targetPath = targetPath
        self.moves = moves
        self.merge = merge
        self.mergeDetail = mergeDetail
        self.editionLabel = editionLabel
        self.files = files
        self.changedFileCount = changedFileCount
        self.fileCount = fileCount
        self.art = art
        self.problems = problems
        self.empty = empty
        self.renameWait = renameWait
        self.renameBy = renameBy
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        albumPath = fields.looseField(String.self, .albumPath) ?? ""
        targetPath = fields.looseField(String.self, .targetPath)
        moves = fields.looseField(Bool.self, .moves) ?? false
        merge = fields.looseField(Bool.self, .merge) ?? false
        mergeDetail = fields.looseField(RetagMerge.self, .mergeDetail)
        editionLabel = fields.looseField(String.self, .editionLabel) ?? ""
        files = fields.looseList(RetagFileChange.self, .files) ?? []
        changedFileCount = fields.looseField(Int.self, .changedFileCount) ?? 0
        fileCount = fields.looseField(Int.self, .fileCount) ?? 0
        art = fields.looseField(RetagArtPlan.self, .art) ?? RetagArtPlan()
        problems = fields.looseList(String.self, .problems) ?? []
        empty = fields.looseField(Bool.self, .empty) ?? false
        renameWait = fields.looseField(Double.self, .renameWait) ?? 0
        renameBy = fields.looseField(String.self, .renameBy)
    }

    /// The files with something to change, as the Changes page lists them.
    public var changedFiles: [RetagFileChange] { files.filter { !$0.changes.isEmpty } }

    /// A preview's body read, each file's changes in the order the server wrote them (the web draws
    /// `Object.entries(file.changes)`, which keeps it; JSONDecoder doesn't).
    public static func read(_ body: Data) throws -> RetagPlan {
        var plan = try JSONDecoder().decode(RetagPlan.self, from: body)
        plan.order(OrderedJSON.parse(body)?["files"])
        return plan
    }

    /// Each file's changes put in the order `files` (the body's own, read in order) names them.
    mutating func order(_ ordered: OrderedJSON?) {
        guard case .array(let rows)? = ordered else { return }
        //? read leniently, a file left out of `files` leaves the rest out of step: matched by filename instead
        var keys: [String: [String]] = [:]
        for row in rows {
            guard case .string(let name)? = row["filename"], case .object(let changes)? = row["changes"] else { continue }
            keys[name] = changes.map(\.0)
        }
        for index in files.indices {
            guard let order = keys[files[index].filename] else { continue }
            let changes = files[index].changes
            files[index].changes = order.compactMap { tag in changes.first { WebText.same($0.tag, tag) } }
                + changes.filter { change in !order.contains { WebText.same($0, change.tag) } }
        }
    }
}

/// What an apply did (RetagResults).
public struct RetagResults: Sendable, Equatable, Decodable {
    public let tagged: Int
    public let failed: Int
    public let movedTo: String?
    public let merged: Bool
    public let artWritten: String?
    public let problems: [String]

    enum CodingKeys: String, CodingKey {
        case tagged, failed, merged, problems
        case movedTo = "moved_to"
        case artWritten = "art_written"
    }

    public init(tagged: Int = 0, failed: Int = 0, movedTo: String? = nil, merged: Bool = false, artWritten: String? = nil,
                problems: [String] = []) {
        self.tagged = tagged
        self.failed = failed
        self.movedTo = movedTo
        self.merged = merged
        self.artWritten = artWritten
        self.problems = problems
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        tagged = fields.looseField(Int.self, .tagged) ?? 0
        failed = fields.looseField(Int.self, .failed) ?? 0
        movedTo = fields.looseField(String.self, .movedTo)
        merged = fields.looseField(Bool.self, .merged) ?? false
        artWritten = fields.looseField(String.self, .artWritten)
        problems = fields.looseList(String.self, .problems) ?? []
    }
}

/// `POST /library/retag/apply`'s answer: the plan it worked out again, and what it did.
public struct RetagResponse: Sendable, Equatable, Decodable {
    public let plan: RetagPlan
    public let results: RetagResults

    enum CodingKeys: String, CodingKey { case plan, results }

    public init(plan: RetagPlan, results: RetagResults) {
        self.plan = plan
        self.results = results
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        plan = fields.looseField(RetagPlan.self, .plan) ?? RetagPlan()
        results = try fields.decode(RetagResults.self, forKey: .results)
    }

    /// Where the album lives after it: the plan's target when the folder moved, else where it was.
    public func pathAfter(_ before: String, preview: RetagPlan?) -> String {
        guard results.movedTo != nil, let target = preview?.targetPath ?? plan.targetPath, !target.isEmpty else { return before }
        return target
    }
}

/// JSON read with every object's keys in the order they were written - only for what order matters to (a preview's
/// changes). ECMA-404 read leniently: what can't be read is nil.
indirect enum OrderedJSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([OrderedJSON])
    case object([(String, OrderedJSON)])

    static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.array(let x), .array(let y)): return x == y
        case (.object(let x), .object(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let fields) = self else { return nil }
        return fields.last { $0.0 == key }?.1
    }

    static func parse(_ data: Data) -> OrderedJSON? {
        var reader = Reader(bytes: Array(data))
        guard let value = reader.value(depth: 0) else { return nil }
        reader.space()
        return reader.at == reader.bytes.count ? value : nil
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0

        mutating func space() {
            while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        }

        mutating func value(depth: Int) -> OrderedJSON? {
            guard depth < 512 else { return nil }
            space()
            guard at < bytes.count else { return nil }
            switch bytes[at] {
            case UInt8(ascii: "{"):
                at += 1
                var fields: [(String, OrderedJSON)] = []
                space()
                if at < bytes.count, bytes[at] == UInt8(ascii: "}") { at += 1; return .object(fields) }
                while true {
                    space()
                    guard let key = string() else { return nil }
                    space()
                    guard at < bytes.count, bytes[at] == UInt8(ascii: ":") else { return nil }
                    at += 1
                    guard let item = value(depth: depth + 1) else { return nil }
                    fields.append((key, item))
                    space()
                    guard at < bytes.count else { return nil }
                    if bytes[at] == UInt8(ascii: ",") { at += 1; continue }
                    if bytes[at] == UInt8(ascii: "}") { at += 1; return .object(fields) }
                    return nil
                }
            case UInt8(ascii: "["):
                at += 1
                var items: [OrderedJSON] = []
                space()
                if at < bytes.count, bytes[at] == UInt8(ascii: "]") { at += 1; return .array(items) }
                while true {
                    guard let item = value(depth: depth + 1) else { return nil }
                    items.append(item)
                    space()
                    guard at < bytes.count else { return nil }
                    if bytes[at] == UInt8(ascii: ",") { at += 1; continue }
                    if bytes[at] == UInt8(ascii: "]") { at += 1; return .array(items) }
                    return nil
                }
            case UInt8(ascii: "\""):
                return string().map { .string($0) }
            case UInt8(ascii: "t"): return word("true", .bool(true))
            case UInt8(ascii: "f"): return word("false", .bool(false))
            case UInt8(ascii: "n"): return word("null", .null)
            default:
                return number()
            }
        }

        mutating func word(_ text: String, _ value: OrderedJSON) -> OrderedJSON? {
            let units = Array(text.utf8)
            guard at + units.count <= bytes.count, Array(bytes[at..<(at + units.count)]) == units else { return nil }
            at += units.count
            return value
        }

        mutating func number() -> OrderedJSON? {
            let start = at
            while at < bytes.count, "+-0123456789.eE".utf8.contains(bytes[at]) { at += 1 }
            guard at > start, let text = String(bytes: bytes[start..<at], encoding: .ascii), let value = Double(text)
            else { return nil }
            return .number(value)
        }

        mutating func string() -> String? {
            guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { return nil }
            at += 1
            var units: [UInt16] = []
            var run: [UInt8] = []
            func flush() {
                units.append(contentsOf: String(decoding: run, as: UTF8.self).utf16)
                run.removeAll()
            }
            while at < bytes.count {
                let byte = bytes[at]
                if byte == UInt8(ascii: "\"") {
                    at += 1
                    flush()
                    return String(decoding: units, as: UTF16.self)
                }
                if byte == UInt8(ascii: "\\") {
                    flush()
                    guard at + 1 < bytes.count else { return nil }
                    let escape = bytes[at + 1]
                    at += 2
                    switch escape {
                    case UInt8(ascii: "\""): units.append(0x22)
                    case UInt8(ascii: "\\"): units.append(0x5C)
                    case UInt8(ascii: "/"): units.append(0x2F)
                    case UInt8(ascii: "b"): units.append(0x08)
                    case UInt8(ascii: "f"): units.append(0x0C)
                    case UInt8(ascii: "n"): units.append(0x0A)
                    case UInt8(ascii: "r"): units.append(0x0D)
                    case UInt8(ascii: "t"): units.append(0x09)
                    case UInt8(ascii: "u"):
                        guard at + 4 <= bytes.count, let text = String(bytes: bytes[at..<(at + 4)], encoding: .ascii),
                              let unit = UInt16(text, radix: 16) else { return nil }
                        units.append(unit)
                        at += 4
                    default: return nil
                    }
                    continue
                }
                run.append(byte)
                at += 1
            }
            return nil
        }
    }
}
