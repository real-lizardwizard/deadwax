import Foundation

/// A track's page in Edit album's Tags (Phase 8, slice 2 - notes/ios-specs/phase8-managing.md 3.4): what the web's
/// track inspector says of one track (ui/src/lib/trackInspector.ts over lib/trackFields.ts' registry) - every field
/// under its group (Tags, Audio, MusicBrainz, File) in the registry's order, its raw tags' title, its pictures' facts
/// and the words for none - held to the web's own answers by Fixtures/edit/edit-parts-vectors.json.
///
/// The web reads each field from the scan's copy of the track and the file read just now, the file winning where both
/// say. The phone has no scan copy of a track (it asks the scan without its tracks, server 2.1.28), so its row is the
/// file alone: the track the registry is handed is made of the file's own format, size and name, and nothing else -
/// which is what the web shows once the file has been read.
public enum TrackInspector {
    public enum Group: String, CaseIterable, Sendable {
        case tags = "Tags"
        case audio = "Audio"
        case musicBrainz = "MusicBrainz"
        case file = "File"
    }

    /// One field as the page draws it: '' for one the file lacks; `inferred` when the value is a default rather than
    /// a tag (the disc of a file with no disc tag - drawn dimmed, saying why).
    public struct Field: Sendable, Equatable, Identifiable {
        public let id: String
        public let label: String
        public let value: String
        public let mono: Bool
        public let inferred: String?
    }

    public struct Section: Sendable, Equatable, Identifiable {
        public let group: Group
        public let fields: [Field]
        public var id: String { group.rawValue }
    }

    /// `inspectorGroups(track, details, false)` with the file as both.
    public static func groups(_ file: AlbumFile) -> [Section] {
        let fields = registry.map { field -> (Group, Field) in
            let value = field.value(file)
            let inferred = value.isEmpty ? nil : field.inferred?(file)
            return (field.group, Field(id: field.id, label: field.label, value: value, mono: field.mono, inferred: inferred))
        }
        return Group.allCases.map { group in Section(group: group, fields: fields.filter { $0.0 == group }.map(\.1)) }
    }

    struct Entry: Sendable {
        let id: String
        let label: String
        let group: Group
        let mono: Bool
        let value: @Sendable (AlbumFile) -> String
        let inferred: (@Sendable (AlbumFile) -> String?)?

        init(_ id: String, _ label: String, _ group: Group, mono: Bool = false, inferred: (@Sendable (AlbumFile) -> String?)? = nil,
             value: @escaping @Sendable (AlbumFile) -> String) {
            self.id = id
            self.label = label
            self.group = group
            self.mono = mono
            self.value = value
            self.inferred = inferred
        }
    }

    static func tag(_ key: String) -> @Sendable (AlbumFile) -> String { { $0.tags?[key] ?? "" } }

    /// lib/trackFields.ts `TRACK_FIELDS`, each as it reads a row whose file has been read.
    static let registry: [Entry] = [
        Entry("number", "#", .tags, mono: true) { file in
            guard let n = file.position else { return "" }
            let text = String(n)
            return String(repeating: "0", count: max(0, 2 - text.utf16.count)) + text
        },
        Entry("disc", "Disc", .tags, mono: true,
              inferred: { $0.disc == nil ? "No disc number on the file - it reads as disc 1" : nil }) { file in
            String(file.disc ?? 1)
        },
        Entry("artist", "Artist", .tags, value: tag("artist")),
        Entry("albumartist", "Album artist", .tags, value: tag("albumartist")),
        Entry("album", "Album", .tags, value: tag("album")),
        Entry("date", "Date", .tags, mono: true, value: tag("date")),
        Entry("originaldate", "Original date", .tags, mono: true, value: tag("originaldate")),
        Entry("genre", "Genre", .tags, value: tag("genre")),
        Entry("composer", "Composer", .tags, value: tag("composer")),
        Entry("conductor", "Conductor", .tags, value: tag("conductor")),
        Entry("lyricist", "Lyricist", .tags, value: tag("lyricist")),
        Entry("discsubtitle", "Disc title", .tags, value: tag("discsubtitle")),
        //? Vorbis files use either name and ID3 only knows `organization` - whichever is there
        Entry("label", "Label", .tags) { $0.tags?["label"] ?? $0.tags?["organization"] ?? "" },
        Entry("catalognumber", "Catalog #", .tags, mono: true, value: tag("catalognumber")),
        Entry("barcode", "Barcode", .tags, mono: true, value: tag("barcode")),
        Entry("isrc", "ISRC", .tags, mono: true, value: tag("isrc")),
        Entry("releasecountry", "Country", .tags, value: tag("releasecountry")),
        Entry("media", "Media", .tags, value: tag("media")),
        Entry("bpm", "BPM", .tags, mono: true, value: tag("bpm")),
        Entry("language", "Language", .tags, value: tag("language")),
        Entry("copyright", "Copyright", .tags, value: tag("copyright")),
        Entry("comment", "Comment", .tags, value: tag("comment")),

        Entry("length", "Length", .audio, mono: true) { trackTime($0.length) },
        Entry("format", "Format", .audio) { $0.format.uppercased() },
        Entry("codec", "Codec", .audio) { $0.codec },
        Entry("bitrate", "Bitrate", .audio, mono: true) { file in
            guard let rate = file.bitrate, rate != 0 else { return "" }
            return "\(WebText.number(WebText.round(rate / 1000))) kbps"
        },
        Entry("sample_rate", "Sample rate", .audio, mono: true) { file in
            guard let rate = file.sampleRate, rate != 0 else { return "" }
            return "\(jsFixed(rate / 1000, rate.truncatingRemainder(dividingBy: 1000) != 0 ? 1 : 0)) kHz"
        },
        Entry("bits", "Bit depth", .audio, mono: true) { file in
            guard let bits = file.bitsPerSample, bits != 0 else { return "" }
            return "\(WebText.number(bits))-bit"
        },
        Entry("channels", "Channels", .audio) { channels($0.channels) },

        Entry("musicbrainz_trackid", "Recording ID", .musicBrainz, mono: true, value: tag("musicbrainz_trackid")),
        Entry("musicbrainz_releasetrackid", "Track ID", .musicBrainz, mono: true, value: tag("musicbrainz_releasetrackid")),
        Entry("musicbrainz_albumid", "Release ID", .musicBrainz, mono: true, value: tag("musicbrainz_albumid")),
        Entry("musicbrainz_releasegroupid", "Release group ID", .musicBrainz, mono: true,
              value: tag("musicbrainz_releasegroupid")),
        Entry("musicbrainz_artistid", "Artist ID", .musicBrainz, mono: true, value: tag("musicbrainz_artistid")),

        //? which songs carry their OWN picture - what a player shows instead of the album's cover
        Entry("pictures", "Picture", .file) { file in
            guard let first = file.pictures.first else { return "" }
            return file.pictures.count > 1 ? "\(first.label) +\(file.pictures.count - 1)" : first.label
        },
        Entry("size", "Size", .file, mono: true) { Sources.size($0.size) },
        Entry("filename", "File name", .file, mono: true) { $0.filename },
    ]

    /// lib/format.ts `trackTime`: "4:07", '' for none.
    public static func trackTime(_ seconds: Double) -> String {
        if seconds == 0 || seconds.isNaN { return "" }
        let whole = Int(WebText.round(seconds))
        let rest = String(whole % 60)
        return "\(whole / 60):\(String(repeating: "0", count: max(0, 2 - rest.count)))\(rest)"
    }

    /// trackFields.ts `channels`.
    static func channels(_ count: Double?) -> String {
        guard let count, count != 0 else { return "" }
        if count == 1 { return "Mono" }
        if count == 2 { return "Stereo" }
        if count == 6 { return "5.1" }
        return "\(WebText.number(count)) ch"
    }

    // MARK: the page's words

    /// Over the fields - the file's own title, else its name, as the list named it.
    public static func title(_ file: AlbumFile) -> String { file.tags?["title"] ?? file.filename }

    /// `untitled`: the file has no title tag, so the title shown is its name.
    public static func untitled(_ file: AlbumFile) -> Bool { (file.tags?["title"] ?? "").isEmpty }

    public static let noTitle = "No title tag - this is the file's name."

    /// Where the track sits (`trackPlace`, the disc's own title left to the Tags group's Disc title): "Track 3, disc 2
    /// of 2 · 4:07 · FLAC" - "Unnumbered" for a file with no track number.
    public static func place(_ file: AlbumFile, discs: Int) -> String {
        let at = [file.position.map { "Track \($0)" } ?? "Unnumbered",
                  discs > 1 && (file.disc ?? 0) != 0 ? "disc \(file.disc ?? 0) of \(discs)" : ""]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return [at, trackTime(file.length), file.format.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public static let editThis = "Edit this track…"
    public static let pictures = "Pictures in this file"

    /// `NO_PICTURES`.
    public static let noPictures = "None - a player shows the album's cover for this song, or its CD art if the song has a disc number."

    /// `rawTagsTitle(details)`: "All tags in this file (24)".
    public static func rawTitle(_ file: AlbumFile) -> String { "All tags in this file (\(file.raw?.count ?? 0))" }

    /// `pictureBytes`: embedded art is usually tens of KB, which the size's words would call 0 MB.
    public static func pictureBytes(_ bytes: Double) -> String {
        bytes < 1024 * 1024 ? "\(WebText.number(max(1, WebText.round(bytes / 1024)))) KB" : Sources.size(bytes)
    }

    /// `pictureFacts(picture, pixels)`: "500 × 500 · 61 KB · JPEG" - its pixel size once it has loaded.
    public static func pictureFacts(_ picture: EmbeddedPicture, pixels: String?) -> String {
        [pixels ?? "", pictureBytes(picture.size), picture.mime.replacingOccurrences(of: "image/", with: "", options: [],
                                                                                     range: firstImage(picture.mime)).uppercased()]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// JavaScript's `replace('image/', '')` takes the first only.
    static func firstImage(_ mime: String) -> Range<String.Index>? { mime.range(of: "image/") }

    /// A picture's pixels as the web writes them: "500 × 500".
    public static func pixels(width: Int, height: Int) -> String { "\(width) × \(height)" }

    /// What VoiceOver says of a picture's row: its label, then that a tap shows it.
    public static func pictureLabel(_ picture: EmbeddedPicture) -> String { "\(picture.label) - see it full size" }
}
