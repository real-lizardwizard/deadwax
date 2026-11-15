import Foundation

// What a Get sends (Phase 6, slice 2 - notes/ios-specs/phase6-get-requests.md 2.8): the web's ONE download payload
// builder, ui/src/lib/releasePayload.ts, with release.ts's edition words and video rule and pressings.ts's getGroup -
// ported to the character and held to them by Fixtures/get/get-vectors.json (GetVectorTests), over the real groups
// MusicBrainz answered (tests/fixtures/pressings/) and what the main page's two Find buttons sent before the web moved
// them onto the one builder (tests/fixtures/payloads/find-buttons.json).
//
// The artist has two roles, and they are not interchangeable: `artist` is AS CREDITED on the album - what a stranger
// typed into their Soulseek folder, so what is searched for and scored against - and `albumArtist` who the album is BY
// in their CURRENT names, from the pressing's own credit: the folder it is filed under. Ye's Donda is searched as
// "Kanye West" and filed under Ye.

/// One track of a Get (`Track` in ui/src/api/types.ts, src/routes/download.py's Track): the running number across every
/// disc (what the matcher keys on and files are named after), its title and length, MusicBrainz's own disc and place on
/// it (what a multi-disc release is tagged with), its own credit, its disc's title and whether it is video.
public struct GetTrack: Encodable, Sendable, Equatable {
    public let position: Int
    public let title: String
    /// Milliseconds, as MusicBrainz gave them.
    public let lengthMs: Double?
    public let disc: Int
    public let discPosition: Int
    public let artist: String?
    public let artistMbids: [String]
    public let discTitle: String?
    public let video: Bool

    enum CodingKeys: String, CodingKey {
        case position, title, disc, artist, video
        case lengthMs = "length_ms"
        case discPosition = "disc_position"
        case artistMbids = "artist_mbids"
        case discTitle = "disc_title"
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(position, forKey: .position)
        try fields.encode(title, forKey: .title)
        try GetRelease.encodeNumber(lengthMs, &fields, .lengthMs)
        try fields.encode(disc, forKey: .disc)
        try fields.encode(discPosition, forKey: .discPosition)
        try fields.encode(artist, forKey: .artist)
        try fields.encode(artistMbids, forKey: .artistMbids)
        try fields.encode(discTitle, forKey: .discTitle)
        try fields.encode(video, forKey: .video)
    }
}

/// The release a download is FOR (`DownloadRelease`): what Get searches Soulseek for (`/find_candidates`), what the store
/// is asked about (`/store_state`) and what the job files the download as (`/enqueue`'s `release`) - every field one
/// the server declares, by its name there (pydantic drops an undeclared one without a word).
public struct GetRelease: Encodable, Sendable, Equatable {
    public let artist: String
    public let albumArtist: String
    public let artistMbids: [String]
    public let album: String
    /// This pressing's year.
    public let year: String?
    /// The album's own year (the group's first release) - what the folder is named after.
    public let originalYear: String?
    /// nil for the album as a whole: no tracklist, and nothing checked as held or downloading.
    public let releaseMbid: String?
    public let editionTags: [String]
    public let tracks: [GetTrack]
    public let releaseGroupMbid: String?
    /// What names an edition's folder (src/editions.py) - nil, and not sent, for the album as a whole.
    public let disambiguation: String?
    public let mediaFormat: String?
    public let country: String?
    public let catalogNumber: String?
    /// Whether the four above are sent at all - a pressing's are (null when it has none), the album as a whole's aren't.
    let pressing: Bool

    enum CodingKeys: String, CodingKey {
        case artist, album, year, tracks, disambiguation, country
        case albumArtist = "album_artist"
        case artistMbids = "artist_mbids"
        case originalYear = "original_year"
        case releaseMbid = "release_mbid"
        case editionTags = "edition_tags"
        case releaseGroupMbid = "release_group_mbid"
        case mediaFormat = "media_format"
        case catalogNumber = "catalog_number"
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(artist, forKey: .artist)
        try fields.encode(albumArtist, forKey: .albumArtist)
        try fields.encode(artistMbids, forKey: .artistMbids)
        try fields.encode(album, forKey: .album)
        try fields.encode(year, forKey: .year)
        try fields.encode(originalYear, forKey: .originalYear)
        try fields.encode(releaseMbid, forKey: .releaseMbid)
        try fields.encode(editionTags, forKey: .editionTags)
        try fields.encode(tracks, forKey: .tracks)
        try fields.encode(releaseGroupMbid, forKey: .releaseGroupMbid)
        guard pressing else { return }
        try fields.encode(disambiguation, forKey: .disambiguation)
        try fields.encode(mediaFormat, forKey: .mediaFormat)
        try fields.encode(country, forKey: .country)
        try fields.encode(catalogNumber, forKey: .catalogNumber)
    }

    /// A number as JavaScript's JSON writes it: a whole one without a fraction (the server's `int` fields take it so),
    /// null for none.
    static func encodeNumber<Key: CodingKey>(_ value: Double?, _ fields: inout KeyedEncodingContainer<Key>, _ key: Key) throws {
        guard let value else { return try fields.encodeNil(forKey: key) }
        if value.isFinite, value == value.rounded(.towardZero), abs(value) < 9_007_199_254_740_992 {
            try fields.encode(Int64(value), forKey: key)
        } else {
            try fields.encode(value, forKey: key)
        }
    }

    /// "Portishead - Dummy", "Kanye West - Donda [DELUXE]" (`downloadLabel`).
    public var label: String {
        let tags = editionTags.isEmpty ? "" : " [\(editionTags.joined(separator: ", "))]"
        return "\(artist) - \(album)\(tags)"
    }

    // MARK: building one (releasePayload.ts)

    /// What a pressing's payload takes from its album (`GroupContext`).
    public struct Context: Sendable, Equatable {
        /// The album's credit as credited: "N/A" when it names nobody.
        public let artist: String
        /// The same credit in each artist's current name, else the credit.
        public let albumArtist: String
        public let artistMbids: [String]
        /// The album's title: "N/A" when MusicBrainz gave none.
        public let album: String
        /// The first four characters of the group's first-release-date, or nil.
        public let year: String?
        public let releaseGroupId: String?
    }

    /// An album's context, from its release group (`groupContext`).
    public static func context(_ group: ReleaseGroup) -> Context {
        let artist = credited(group.artistCredit)
        let date = group.firstReleaseDate ?? ""
        return Context(artist: artist, albumArtist: Credits.first(Credits.current(group.artistCredit), artist),
                       artistMbids: creditIds(group.artistCredit), album: Credits.first(group.title, "N/A"),
                       year: date.isEmpty ? nil : WebText.prefix(date, 4),
                       releaseGroupId: group.id.isEmpty ? nil : group.id)
    }

    /// A download of `release` - a pressing of `group` - or, with none, of the album as a whole (`buildDownloadRelease`).
    public static func build(group: ReleaseGroup, release: PageRelease?) -> GetRelease {
        let context = self.context(group)
        guard let release else { return fallback(context) }
        return payload(release, context)
    }

    /// One real pressing of the album, as a download (`releasePayload`).
    public static func payload(_ release: PageRelease, _ context: Context) -> GetRelease {
        let first = release.eventDates.first ?? nil
        let rawDate = Credits.first(first, release.date)
        let numbers = release.labelInfo.compactMap { (info: PageRelease.LabelInfo) -> String? in
            guard let number = info.catalogNumber, !number.isEmpty else { return nil }
            return number
        }
        let formats = release.media.compactMap { (medium: MBMedium) -> String? in
            guard let format = medium.format, !format.isEmpty else { return nil }
            return format
        }
        let country = Credits.first(release.eventCountries.first ?? nil, release.country)
        return GetRelease(
            artist: context.artist,
            albumArtist: Credits.first(Credits.current(release.artistCredit), context.albumArtist),
            artistMbids: creditIds(release.artistCredit),
            album: Credits.first(release.title, context.album),
            year: rawDate.isEmpty ? realYear(context.year) : WebText.prefix(rawDate, 4),
            originalYear: realYear(context.year),
            releaseMbid: release.id,
            editionTags: EditionTags.detect(title: release.title, disambiguation: release.disambiguation,
                                            packaging: release.packaging),
            tracks: tracks(release),
            releaseGroupMbid: present(context.releaseGroupId),
            disambiguation: present(release.disambiguation),
            mediaFormat: present(formats.joined(separator: " + ")),
            country: present(country),
            catalogNumber: present(numbers.joined(separator: ", ")),
            pressing: true)
    }

    /// The album as a whole, no pressing (`groupFallback`): no tracklist to match against, no release id - nothing
    /// checked as held or downloading - filed under the album's current artist.
    public static func fallback(_ context: Context) -> GetRelease {
        GetRelease(artist: context.artist, albumArtist: context.albumArtist, artistMbids: context.artistMbids,
                   album: context.album, year: realYear(context.year), originalYear: realYear(context.year),
                   releaseMbid: nil, editionTags: [], tracks: [], releaseGroupMbid: present(context.releaseGroupId),
                   disambiguation: nil, mediaFormat: nil, country: nil, catalogNumber: nil, pressing: false)
    }

    /// Every track of every disc, with both numberings (`tracksOf`): `position` running across the whole release,
    /// `disc` and `discPosition` MusicBrainz's own. Each keeps its OWN credit (the track's, else its recording's), the
    /// disc's title and whether it is video.
    static func tracks(_ release: PageRelease) -> [GetTrack] {
        var out: [GetTrack] = []
        var position = 0
        for (discIndex, medium) in release.media.enumerated() {
            let discTitle = present(JSText.trim(medium.title ?? ""))
            for (trackIndex, track) in medium.tracks.enumerated() {
                position += 1
                let credit = track.artistCredit ?? track.recording?.artistCredit
                out.append(GetTrack(
                    position: position,
                    title: Credits.first(track.recording?.title, track.title),
                    lengthMs: track.recording?.length ?? track.length,
                    disc: medium.position ?? discIndex + 1,
                    discPosition: track.position ?? trackIndex + 1,
                    artist: credit.map { credited($0) },
                    artistMbids: creditIds(credit),
                    discTitle: discTitle,
                    video: isVideo(format: medium.format, recording: track.recording)))
            }
        }
        return out
    }

    /// A credit as credited, or "N/A" for one that names nobody.
    static func credited(_ credit: [MBArtistCredit]?) -> String {
        Credits.first(Credits.name(credit), "N/A")
    }

    /// Every artist id in a credit, in the order credited (`creditIds`).
    public static func creditIds(_ credit: [MBArtistCredit]?) -> [String] {
        var ids: [String] = []
        for entry in credit ?? [] {
            guard let id = entry.artist?.id, !id.isEmpty, !ids.contains(where: { WebText.same($0, id) }) else { continue }
            ids.append(id)
        }
        return ids
    }

    /// Formats that are video whatever is on them (`VIDEO_FORMATS`). A plain "DVD" may be DVD-Audio, so it counts only
    /// by its recording's own flag.
    public static let videoFormats: Set<String> = [
        "DVD-Video", "Blu-ray", "Blu-ray-R", "HD-DVD", "VHS", "VCD", "SVCD", "Betamax", "LaserDisc", "CED", "UMD",
        "DualDisc (DVD-Video side)",
    ]

    /// A track that never arrives as an audio file: on a video medium, or of a video recording (`isVideoTrack`).
    public static func isVideo(format: String?, recording: MBTrack.Recording?) -> Bool {
        recording?.video == true || videoFormats.contains(format ?? "")
    }

    /// A year or nothing (`realYear`): four ASCII digits, never "N/A".
    static func realYear(_ year: String?) -> String? {
        guard let year, WebText.fourDigits(year) else { return nil }
        return year
    }

    /// JavaScript's `x || null`.
    static func present(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: the group a Get builds from (pressings.ts getGroup)

    /// The release group a Get on the album you don't have builds its download from (`getGroup`): the group Search
    /// handed over, else the one the pressings carry - and where MusicBrainz gave no credit for it, the chosen
    /// pressing's; with no group at all, its title and the earliest date any pressing came out.
    public static func group(id: String, preview: ReleaseGroup?, releases: [PageRelease], chosen: PageRelease?) -> ReleaseGroup {
        let group = preview ?? releases.first(where: { $0.releaseGroup != nil })?.releaseGroup
        let dates = releases.map(\.knownDate).filter { !$0.isEmpty }
            .sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
        let credit = (group?.artistCredit ?? []).isEmpty ? chosen?.artistCredit : group?.artistCredit
        return ReleaseGroup(
            id: Credits.first(group?.id, id),
            title: Credits.first(group?.title, Credits.first(chosen?.title, releases.first?.title)),
            firstReleaseDate: group.map { $0.firstReleaseDate ?? "" } ?? dates.first ?? "",
            artistCredit: credit)
    }
}

/// Edition markers found in a release's own text (release.ts `detectEditionTags`) - the same words as src/matching.py's
/// EDITION_PATTERNS, which tag the folders found: the two are compared, so changing one without the other weakens the
/// edition signal without a word.
public enum EditionTags {
    /// Each pattern and its tag, in order (`EDITION_KEYWORDS`).
    static let keywords: [(matches: @Sendable ([UInt16]) -> Bool, tag: String)] = [
        ({ has($0, "super deluxe") }, "SUPER DELUXE"),
        ({ has($0, "deluxe") }, "DELUXE"),
        ({ has($0, "box set") || has($0, "boxset") }, "BOX SET"),
        ({ has($0, "anniversary") }, "ANNIVERSARY"),
        ({ has($0, "expanded") }, "EXPANDED"),
        ({ has($0, "limited edition") }, "LIMITED"),
        ({ has($0, "special edition") }, "SPECIAL EDITION"),
        ({ has($0, "instrumental") }, "INSTRUMENTAL"),
        ({ has($0, "acoustic") }, "ACOUSTIC"),
        ({ aCappella($0) }, "A CAPPELLA"),
    ]

    public static func detect(title: String?, disambiguation: String?, packaging: String?) -> [String] {
        let haystack = Array(JSText.lowercase("\(disambiguation ?? "") \(title ?? "")").utf16)
        var tags: [String] = []
        if has(haystack, "remaster") { tags.append("REMASTER") }
        for (matches, tag) in keywords where matches(haystack) {
            tags.append(tag)
            // "super deluxe" also trips the plain "deluxe" pattern on the same text
            if tag == "SUPER DELUXE" { break }
        }
        if packaging == "Box" && !tags.contains("BOX SET") { tags.append("BOX SET") }
        return tags
    }

    static func has(_ haystack: [UInt16], _ words: String) -> Bool {
        FoldKey.contains(haystack, Array(words.utf16))
    }

    /// `/a\s*capp?ella/`: an "a", any of JavaScript's white space, then "capella" or "cappella".
    static func aCappella(_ text: [UInt16]) -> Bool {
        let a: UInt16 = 0x61
        for start in text.indices where text[start] == a {
            var at = start + 1
            while at < text.count, let scalar = Unicode.Scalar(text[at]), WebText.isSpace(scalar) { at += 1 }
            for rest in ["capella", "cappella"] {
                let units = Array(rest.utf16)
                if at + units.count <= text.count, text[at..<(at + units.count)].elementsEqual(units) { return true }
            }
        }
        return false
    }
}
