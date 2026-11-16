import Foundation
import Testing
@testable import DeadwaxCore

/// Album info's rules (AlbumInfo.swift): its words from the album's songs, getAlbum's other fields, the id bridge and
/// the files' tags - the last over the route's own answers for a FLAC set, an MP3 and an M4A tagged as Picard tags them
/// (Fixtures/albuminfo/files.json, written by ios/scripts/album_files_answers.py and held to the route by
/// tests/test_ios_contract.py).
@Suite struct AlbumInfoTests {
    static let group = "4b4f4f2f-7a5e-3d58-9d1a-5c3b5c3c2b10"
    static let release = "9c7c3a3e-1b2d-4c5e-8f9a-0b1c2d3e4f50"

    struct Case: Decodable {
        let name: String
        let answer: AlbumFiles
    }

    struct Answers: Decodable {
        let cases: [Case]
    }

    static func files(_ name: String) throws -> [AlbumFile] {
        let answers = try JSONDecoder().decode(Answers.self, from: Fixtures.data("albuminfo/files.json"))
        return try #require(answers.cases.first { $0.name == name }).answer.files
    }

    /// The country names a phone would give, for the codes the tests use.
    static func named(_ code: String) -> String? {
        ["GB": "United Kingdom", "US": "United States"][code]
    }

    static func song(_ id: String, suffix: String = "flac", bits: Int? = 16, rate: Int? = 44100, bitRate: Int? = 900,
                     channels: Int? = 2, disc: Int? = nil, duration: Double? = 240, size: Int64? = 27_000_000,
                     contentType: String? = nil) -> Song {
        Song(id: id, title: id, discNumber: disc, duration: duration, suffix: suffix, contentType: contentType, size: size,
             bitRate: bitRate, samplingRate: rate, bitDepth: bits, channelCount: channels)
    }

    static func songs(_ count: Int, _ make: (Int) -> Song) -> [Song] { (1...count).map(make) }

    // MARK: the files' tags, as the route sends them

    @Test func theRoutesAnswerIsRead() throws {
        let answers = try JSONDecoder().decode(Answers.self, from: Fixtures.data("albuminfo/files.json"))
        #expect(answers.cases.map(\.name) == ["flac", "mp3", "m4a", "deadwax-flac", "deadwax-m4a"])
        let flac = try Self.files("flac")
        #expect(flac.count == 3)
        #expect(flac.map(\.disc) == [1, 1, 2])
        #expect(flac[0].tags?["media"] == "CD")
        #expect(try Self.files("mp3").first?.disc == nil)
    }

    @Test func aFlacSetSaysWhatItsVorbisCommentsSay() throws {
        let files = try Self.files("flac")
        #expect(AlbumInfo.media(files) == "CD + DVD-Video")
        #expect(AlbumInfo.values(files, .label) == ["Harvest"])
        #expect(AlbumInfo.values(files, .catalogueNumber) == ["SHVL 804"])
        #expect(AlbumInfo.values(files, .barcode) == ["5099902894225"])
        #expect(AlbumInfo.values(files, .country) == ["GB"])
        // not among the server's named tags: read raw, by Vorbis's name
        #expect(AlbumInfo.values(files, .status) == ["official"])
        #expect(AlbumInfo.values(files, .type) == ["album", "live"])
        #expect(AlbumInfo.values(files, .date) == ["2011-09-26"])
        #expect(AlbumInfo.values(files, .originalDate) == ["1973-03-01"])
        #expect(AlbumInfo.values(files, .genre) == ["Rock"])
        #expect(AlbumInfo.values(files, .releaseGroup) == [Self.group])
    }

    @Test func anMP3SaysWhatItsID3FramesSay() throws {
        let files = try Self.files("mp3")
        #expect(AlbumInfo.media(files) == "12\" Vinyl")
        // ID3's TPUB is the server's `organization`
        #expect(AlbumInfo.values(files, .label) == ["Go! Beat"])
        #expect(AlbumInfo.values(files, .catalogueNumber) == ["828 522-1"])
        #expect(AlbumInfo.values(files, .country) == ["GB"])
        // the status and type by their TXXX frames' names
        #expect(AlbumInfo.values(files, .status) == ["Official"])
        #expect(AlbumInfo.values(files, .type) == ["album"])
        #expect(AlbumInfo.values(files, .releaseGroup) == [Self.group])
    }

    @Test func anM4ASaysWhatItsFreeformAtomsSay() throws {
        let files = try Self.files("m4a")
        // Easy MP4 has no names for any of them: every one read raw
        #expect(files.first?.tags?["media"] == nil)
        #expect(AlbumInfo.media(files) == "Digital Media")
        #expect(AlbumInfo.values(files, .label) == ["Warp"])
        #expect(AlbumInfo.values(files, .catalogueNumber) == ["WAP105CD"])
        #expect(AlbumInfo.values(files, .barcode) == ["801061010524"])
        #expect(AlbumInfo.values(files, .country) == ["XW"])
        #expect(AlbumInfo.values(files, .status) == ["Promotion"])
        #expect(AlbumInfo.values(files, .type) == ["single"])
    }

    @Test func anAlbumDeadwaxFiledSaysWhatItsFilingWrote() throws {
        // a 2-CD set: the whole release's formats in every file ("CD + CD"), said once, folded
        let set = try Self.files("deadwax-flac")
        #expect(set.map { $0.tags?["media"] } == ["CD + CD", "CD + CD", "CD + CD"])
        #expect(AlbumInfo.media(set) == "2\u{00D7}CD")
        #expect(AlbumInfo.values(set, .catalogueNumber) == ["XDUSTCD1X"])
        #expect(AlbumInfo.values(set, .country) == ["GB"])
        #expect(AlbumInfo.values(set, .status) == [] && AlbumInfo.values(set, .barcode) == [])
        let rows = AlbumInfo.release(album: Album(id: "al"), extras: nil, store: nil, files: set, countryName: Self.named)
        #expect(rows.map(\.label) == ["Media", "Catalogue number", "Country", "Released", "First released"])
        #expect(rows.map(\.value) == ["2\u{00D7}CD", "XDUSTCD1X", "United Kingdom", "2015", "1995"])
        // an M4A: Easy MP4 took the country (its own name for it), not the media or the catalogue number
        let single = try Self.files("deadwax-m4a")
        #expect(single.first?.tags?["releasecountry"] == "US")
        #expect(AlbumInfo.media(single) == nil)
        #expect(AlbumInfo.values(single, .catalogueNumber) == [])
        #expect(AlbumInfo.release(album: Album(id: "al"), extras: nil, store: nil, files: single, countryName: Self.named)
            .first { $0.label == "Country" }?.value == "United States")
    }

    @Test func theReleaseSectionInWords() throws {
        let album = Album(id: "al", name: "The Dark Side of the Moon")
        let flac = AlbumInfo.release(album: album, extras: nil, store: nil, files: try Self.files("flac"), countryName: Self.named)
        #expect(flac.map(\.label) == ["Media", "Label", "Catalogue number", "Barcode", "Country", "Released", "First released",
                                      "Type", "Status", "Genre"])
        #expect(flac.map(\.value) == ["CD + DVD-Video", "Harvest", "SHVL 804", "5099902894225", "United Kingdom",
                                      "26 September 2011", "1 March 1973", "Album · Live", "Official", "Rock"])
        #expect(flac.first { $0.label == "Barcode" }?.style == .copyable)
        #expect(flac.first { $0.label == "Barcode" }?.copy == "5099902894225")

        let m4a = AlbumInfo.release(album: album, extras: nil, store: nil, files: try Self.files("m4a"), countryName: Self.named)
        #expect(m4a.first { $0.label == "Country" }?.value == "Worldwide")
        #expect(m4a.first { $0.label == "Status" }?.value == "Promotion")
        #expect(m4a.first { $0.label == "Type" }?.value == "Single")
    }

    @Test func mediaIsSaidPerDiscAsMusicBrainzWritesIt() {
        func file(_ disc: Int?, _ medium: String?) -> AlbumFile {
            AlbumFile(disc: disc, tags: medium.map { ["media": $0] } ?? [:])
        }
        #expect(AlbumInfo.media([file(1, "CD"), file(1, "CD")]) == "CD")
        #expect(AlbumInfo.media([file(1, "CD"), file(2, "cd"), file(3, "DVD-Video")]) == "2\u{00D7}CD + DVD-Video")
        // a run is folded, as MusicBrainz writes a release's format - not every disc of a kind counted together
        #expect(AlbumInfo.media([file(1, "CD"), file(2, "DVD-Video"), file(3, "CD")]) == "CD + DVD-Video + CD")
        // a disc's medium is the one most of its files name; a file with no disc is disc 1
        #expect(AlbumInfo.media([file(nil, "Vinyl"), file(1, "Vinyl"), file(1, "CD")]) == "Vinyl")
        #expect(AlbumInfo.media([file(1, nil), file(2, nil)]) == nil)
        #expect(AlbumInfo.media([]) == nil)
        // a disc whose files say nothing is left out, the others still said
        #expect(AlbumInfo.media([file(1, nil), file(2, "Blu-ray")]) == "Blu-ray")
    }

    @Test func deadwaxsWholeReleaseMediaIsSaidOnce() {
        func file(_ disc: Int?, _ medium: String) -> AlbumFile { AlbumFile(disc: disc, tags: ["media": medium]) }
        // deadwax's filing writes every medium's format, joined, into every file: never counted per disc
        #expect(AlbumInfo.media([file(1, "CD + CD"), file(2, "CD + CD")]) == "2\u{00D7}CD")
        #expect(AlbumInfo.media([file(1, "CD + DVD-Video"), file(2, "CD + DVD-Video")]) == "CD + DVD-Video")
        #expect(AlbumInfo.media([file(1, "CD + CD + DVD-Video"), file(1, "CD + CD + DVD-Video"), file(3, "CD + CD + DVD-Video")])
            == "2\u{00D7}CD + DVD-Video")
        #expect(AlbumInfo.media([file(nil, "12\" Vinyl + 12\" Vinyl + 12\" Vinyl")]) == "3\u{00D7}12\" Vinyl")
        // a few files retagged by hand: the commonest whole value still wins
        #expect(AlbumInfo.media([file(1, "CD + CD"), file(1, "CD + CD"), file(2, "CD")]) == "2\u{00D7}CD")
        // the same medium in another case is still one run
        #expect(AlbumInfo.media([file(1, "CD + cd"), file(2, "CD + cd")]) == "2\u{00D7}CD")
    }

    @Test func theNamedTagWinsAndRawIsReadByAnyCase() {
        let both = AlbumFile(tags: ["label": "Harvest"], raw: [["TPUB", "EMI"]])
        #expect(both.values(.label) == ["Harvest"])
        let raw = AlbumFile(tags: [:], raw: [["TXXX:MUSICBRAINZ ALBUM STATUS", "bootleg"], ["short"]])
        #expect(raw.values(.status) == ["bootleg"])
        // several values, as the server joins them
        #expect(AlbumFile(tags: ["catalognumber": "A-1; B-2 ;"]).values(.catalogueNumber) == ["A-1", "B-2"])
        #expect(AlbumFile().values(.media) == [])
        // the same value in two cases is said once, as first met
        #expect(AlbumInfo.values([AlbumFile(tags: ["media": "CD"]), AlbumFile(tags: ["media": "cd"])], .media) == ["CD"])
    }

    // MARK: Quality

    @Test func oneKindOfFileIsOneLine() {
        let songs = Self.songs(10) { Self.song("s\($0)", bits: 24, rate: 96000) }
        let rows = AlbumInfo.quality(songs)
        #expect(rows.first?.label == "Format")
        #expect(rows.first?.value == "FLAC · 24-bit / 96 kHz · all 10 songs")
        #expect(rows.first?.lines == [])
        #expect(rows.first { $0.label == "Channels" }?.value == "Stereo")
        // one song: no count
        #expect(AlbumInfo.quality([Self.song("only")]).first?.value == "FLAC · 16-bit / 44.1 kHz")
    }

    @Test func aMixIsSaidKindByKindTheCommonestFirst() {
        let songs = [Self.song("a", suffix: "mp3", bits: 0, bitRate: 320)]
            + Self.songs(8) { Self.song("f\($0)") }
            + [Self.song("b", suffix: "mp3", bits: nil, bitRate: 320)]
        let format = AlbumInfo.quality(songs).first
        #expect(format?.value == "FLAC · 16-bit / 44.1 kHz · 8 of 10 songs")
        #expect(format?.lines == ["MP3 · 320 kbps · 2 of 10 songs"])

        let rates = Self.songs(4) { Self.song("lo\($0)", bits: 24, rate: 48000) } + Self.songs(6) { Self.song("hi\($0)", bits: 24, rate: 96000) }
        let mixed = AlbumInfo.quality(rates).first
        #expect(mixed?.value == "FLAC · 24-bit / 96 kHz · 6 of 10 songs")
        #expect(mixed?.lines == ["FLAC · 24-bit / 48 kHz · 4 of 10 songs"])
    }

    @Test func aLossyFileNeverShowsADepth() {
        // a tag reader may give an MP3 a bit depth: it isn't one
        let songs = [Self.song("a", suffix: "mp3", bits: 16, bitRate: 245), Self.song("b", suffix: "mp3", bits: 16, bitRate: 251)]
        #expect(AlbumInfo.quality(songs).first?.value == "MP3 · 248 kbps on average · all 2 songs")
        // no suffix: its type names it
        let typed = [Self.song("t", suffix: "", contentType: "audio/x-flac")]
        #expect(AlbumInfo.quality(typed).first?.value == "FLAC · 16-bit / 44.1 kHz")
        // nothing said of the file: no Format line at all
        #expect(AlbumInfo.quality([Self.song("n", suffix: "", bits: nil, rate: nil, bitRate: nil, channels: nil, size: nil)]).isEmpty)
        // a depth only for a lossless format: one nobody lists says its bitrate
        #expect(AlbumInfo.quality([Self.song("d", suffix: "dsf", bits: 1, rate: 2_822_400, bitRate: 5645)]).first?.value
            == "DSF · 5,645 kbps")
    }

    @Test func anM4AIsAACOrALACByWhatItCarries() {
        // an iTunes AAC album: Navidrome says "m4a", "audio/mp4" and 16 bits - never "M4A · 16-bit / 44.1 kHz"
        let aac = Self.songs(10) { Self.song("a\($0)", suffix: "m4a", bits: 16, bitRate: 256, contentType: "audio/mp4") }
        let rows = AlbumInfo.quality(aac)
        #expect(rows.first?.value == "AAC · 256 kbps · all 10 songs")
        #expect(!rows.contains { $0.label == "Bitrate" })
        // ALAC: its bitrate says so, decided for the album - its one quiet song still ALAC
        let alac = Self.songs(9) { Self.song("l\($0)", suffix: "m4a", bits: 24, rate: 96000, bitRate: 2600) }
            + [Self.song("quiet", suffix: "m4a", bits: 24, rate: 96000, bitRate: 380)]
        let format = AlbumInfo.quality(alac).first
        #expect(format?.value == "ALAC · 24-bit / 96 kHz · all 10 songs")
        #expect(AlbumInfo.quality(alac).contains { $0.label == "Bitrate" })
        // a type naming its codec decides, whatever the bitrate
        #expect(AlbumInfo.quality([Self.song("t", suffix: "m4a", bits: 16, bitRate: 350, contentType: "audio/x-alac")])
            .first?.value == "ALAC · 16-bit / 44.1 kHz")
        #expect(AlbumInfo.quality([Self.song("u", suffix: "m4a", bits: 16, bitRate: 900, contentType: "audio/aac")])
            .first?.value == "AAC · 900 kbps")
        // at the line: over 400 kbps on average is ALAC
        #expect(AlbumInfo.mp4Lossless([Self.song("x", suffix: "m4a", bitRate: 400)]) == false)
        #expect(AlbumInfo.mp4Lossless([Self.song("y", suffix: "m4a", bitRate: 401)]) == true)
        #expect(AlbumInfo.mp4Lossless([Self.song("z", suffix: "flac", bitRate: 900)]) == false)
    }

    @Test func theBitrateIsSaidOnce() {
        // a lossy album's Format line says it: no Bitrate line too
        let mp3 = Self.songs(3) { Self.song("m\($0)", suffix: "mp3", bits: nil, bitRate: 320) }
        #expect(AlbumInfo.quality(mp3).map(\.label) == ["Format", "Channels"])
        #expect(AlbumInfo.quality(mp3).first?.value == "MP3 · 320 kbps · all 3 songs")
        // a lossless one's doesn't: the Bitrate line does
        let flac = Self.songs(2) { Self.song("f\($0)", bitRate: 1000) }
        #expect(AlbumInfo.quality(flac).map(\.label) == ["Format", "Bitrate", "Channels"])
        // lossless and lossy together: each lossy line says its own, nothing averaged across them
        let both = Self.songs(8) { Self.song("f\($0)", bitRate: 1000) } + Self.songs(2) { Self.song("m\($0)", suffix: "mp3", bits: nil, bitRate: 320) }
        #expect(AlbumInfo.quality(both).map(\.label) == ["Format", "Channels"])
    }

    @Test func theBitrate() {
        let same = Self.songs(3) { Self.song("m\($0)", suffix: "mp3", bits: nil, bitRate: 320) }
        #expect(AlbumInfo.bitrateWords(same) == "320 kbps")
        // Navidrome's bitrates weighed by length - never the sizes, which a cover in every file would swell
        let weighed = [Self.song("a", bitRate: 1000, duration: 100, size: 90_000_000),
                       Self.song("b", bitRate: 2000, duration: 300, size: 90_000_000)]
        #expect(AlbumInfo.bitrateWords(weighed) == "1,750 kbps on average")
        // no lengths: the plain mean
        let untimed = [Self.song("a", bitRate: 1000, duration: nil), Self.song("b", bitRate: 1501, duration: nil)]
        #expect(AlbumInfo.bitrateWords(untimed) == "1,251 kbps on average")
        #expect(AlbumInfo.bitrateWords([Self.song("x", bitRate: nil, size: nil)]) == nil)
        #expect(AlbumInfo.bitrateWords([]) == nil)
        #expect(AlbumInfo.grouped(1411) == "1,411" && AlbumInfo.grouped(999) == "999" && AlbumInfo.grouped(1_234_567) == "1,234,567")
    }

    @Test func theChannels() {
        #expect(AlbumInfo.channelWords(1) == "Mono" && AlbumInfo.channelWords(6) == "5.1 surround" && AlbumInfo.channelWords(4) == "4 channels")
        let songs = Self.songs(8) { Self.song("s\($0)") } + Self.songs(2) { Self.song("q\($0)", channels: 6) }
        let row = AlbumInfo.quality(songs).first { $0.label == "Channels" }
        #expect(row?.value == "Stereo · 8 of 10 songs")
        #expect(row?.lines == ["5.1 surround · 2 of 10 songs"])
    }

    // MARK: The album

    @Test func theAlbumsSongsDiscsLengthAndSize() {
        let songs = Self.songs(3) { Self.song("a\($0)", disc: 1, duration: 600, size: 100_000_000) }
            + Self.songs(2) { Self.song("b\($0)", disc: 2, duration: 300, size: 50_000_000) }
        let album = Album(id: "al", song: songs, discTitles: [DiscTitle(disc: 2, title: "Live at Wembley")])
        let rows = AlbumInfo.theAlbum(album)
        #expect(rows.map(\.label) == ["Songs", "Discs", "Length", "Size"])
        #expect(rows.map(\.value) == ["5", "2", "40 min", "400 MB"])
        #expect(rows[1].lines == ["Disc 1 · 3 songs", "Disc 2 · Live at Wembley · 2 songs"])

        // one disc with a title of its own
        let titled = Album(id: "t", song: [Self.song("x", disc: 1)], discTitles: [DiscTitle(disc: 1, title: "Bonus")])
        #expect(AlbumInfo.theAlbum(titled).first { $0.label == "Disc title" }?.value == "Bonus")
        // a song without a size: no Size, rather than a size too small
        let unsized = Album(id: "u", song: [Self.song("a"), Self.song("b", size: nil)])
        #expect(!AlbumInfo.theAlbum(unsized).contains { $0.label == "Size" })
        // nothing known: nothing said
        #expect(AlbumInfo.theAlbum(Album(id: "e")).isEmpty)
    }

    // MARK: On this phone

    @Test func whatThisPhoneHolds() {
        #expect(AlbumInfo.onPhone(.none, here: 0, of: 10, bytes: 0).value == "Not downloaded")
        let all = AlbumInfo.onPhone(.downloaded(checking: false), here: 10, of: 10, bytes: 412_000_000)
        #expect(all.label == "Downloaded" && all.value == "All 10 songs · 412 MB" && all.lines == [])
        #expect(AlbumInfo.onPhone(.partial(here: 3, of: 12), here: 3, of: 12, bytes: 92_000_000).value == "3 of 12 songs · 92 MB")
        let going = AlbumInfo.onPhone(.downloading(here: 4, of: 12, fraction: 0.4), here: 4, of: 12, bytes: 120_000_000)
        #expect(going.value == "4 of 12 songs · 120 MB")
        #expect(going.lines == ["Downloading - 4 of 12 songs"])
        #expect(AlbumInfo.onPhone(.downloading(here: 0, of: 12, fraction: 0.1), here: 0, of: 12, bytes: 0).value == "Downloading - 0 of 12 songs")
    }

    // MARK: The release, from every source

    @Test func getAlbumsFieldsComeFirst() throws {
        let album = Album(id: "al", year: 2011, genre: "Rock", recordLabels: [Album.RecordLabel(name: "EMI")])
        let extras = AlbumExtras(releaseTypes: ["album", "ep"], releaseDate: .init(year: 2011, month: 9, day: 26),
                                 originalReleaseDate: .init(year: 1973), version: "Immersion Box",
                                 genres: [.init(name: "Progressive Rock"), .init(name: "Rock"), .init(name: "rock")],
                                 isCompilation: true, recordLabels: [.init(name: "Harvest"), .init(name: "Capitol")])
        let store = StoreAlbum(present: [
            StoreRow(id: 1, path: "Pink Floyd/DSOTM [Box]", edition: "Immersion", firstSeen: "2026-10-14T23:30:00+00:00", imported: true),
            StoreRow(id: 2, path: "Pink Floyd/DSOTM [Box] (Disc 2)", firstSeen: "2026-10-20T08:00:00+00:00", imported: false),
        ])
        let rows = AlbumInfo.release(album: album, extras: extras, store: store, files: try Self.files("flac"),
                                     countryName: Self.named, timeZone: TimeZone(identifier: "UTC")!)
        let said = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0.value) })
        #expect(said["Labels"] == "Harvest / Capitol")
        #expect(said["Released"] == "26 September 2011")
        #expect(said["First released"] == "1973")
        #expect(said["Type"] == "Album · EP · Compilation")
        // deadwax's edition over the files' version
        #expect(said["Edition"] == "Immersion")
        #expect(said["Genres"] == "Progressive Rock, Rock")
        // the earliest folder's day, and that deadwax filed that one
        #expect(said["Added"] == "14 October 2026, downloaded by deadwax")
        // in the reader's own time zone, the day it was there
        let london = AlbumInfo.release(album: album, extras: extras, store: store, files: nil,
                                       timeZone: TimeZone(identifier: "Europe/London")!)
        #expect(london.first { $0.label == "Added" }?.value == "15 October 2026, downloaded by deadwax")
    }

    @Test func withNothingButTheAlbumTheAlbumStillSaysWhatItCan() {
        let album = Album(id: "al", year: 1994, genre: "Trip Hop", recordLabels: [Album.RecordLabel(name: "Go! Beat")])
        let rows = AlbumInfo.release(album: album, extras: nil, store: nil, files: nil)
        #expect(rows.map(\.label) == ["Label", "Released", "Genre"])
        #expect(rows.map(\.value) == ["Go! Beat", "1994", "Trip Hop"])
        // the same year twice is said once
        let store = StoreAlbum(present: [StoreRow(id: 1, path: "p", originalYear: "1994")])
        #expect(!AlbumInfo.release(album: album, extras: nil, store: store, files: nil).contains { $0.label == "First released" })
        #expect(AlbumInfo.release(album: Album(id: "e"), extras: nil, store: nil, files: nil).isEmpty)
    }

    @Test func datesInWords() {
        #expect(AlbumInfo.dateWords("1973") == "1973")
        #expect(AlbumInfo.dateWords("1973-03") == "March 1973")
        #expect(AlbumInfo.dateWords("1973-03-01") == "1 March 1973")
        #expect(AlbumInfo.dateWords("1973-03-01T00:00:00Z") == "1 March 1973")
        #expect(AlbumInfo.dateWords("73") == nil && AlbumInfo.dateWords("") == nil && AlbumInfo.dateWords("soon") == nil)
        #expect(AlbumInfo.dateWords(year: 1973, month: 13, day: 1) == "1973")
        #expect(AlbumInfo.dateWords(year: 1973, month: 12, day: 0) == "December 1973")
        #expect(AlbumInfo.dateWords(year: 0, month: 1, day: 1) == nil)
    }

    @Test func countriesInWords() {
        #expect(AlbumInfo.country("XW", name: Self.named) == "Worldwide")
        #expect(AlbumInfo.country("xe", name: Self.named) == "Europe")
        #expect(AlbumInfo.country("gb", name: Self.named) == "United Kingdom")
        // MusicBrainz's countries that have gone, by its names, ahead of any Locale's
        let gone = ["XC": "Czechoslovakia", "XG": "East Germany", "SU": "Soviet Union", "YU": "Yugoslavia",
                    "CS": "Serbia and Montenegro"]
        for (code, words) in gone {
            #expect(AlbumInfo.country(code, name: { _ in "a Locale's name" }) == words, "\(code)")
        }
        // the unknown country is said by no line
        #expect(AlbumInfo.country("XU", name: Self.named) == nil)
        #expect(AlbumInfo.country(" ", name: Self.named) == nil)
        let unknown = AlbumInfo.release(album: Album(id: "u"), extras: nil, store: nil,
                                        files: [AlbumFile(tags: ["releasecountry": "XU"])], countryName: Self.named)
        #expect(!unknown.contains { $0.label == "Country" })
        // a code nobody names, or not a code at all, as it is
        #expect(AlbumInfo.country("ZZ", name: Self.named) == "ZZ")
        #expect(AlbumInfo.country("Mars", name: Self.named) == "Mars")
    }

    @Test func releaseTypesInWords() {
        #expect(AlbumInfo.typeWords(["dj-mix"], compilation: false) == "DJ mix")
        #expect(AlbumInfo.typeWords(["mixtape/street"], compilation: false) == "Mixtape/Street")
        // ID3v2.3's one frame of several, joined by "/" - the one type with a slash in its name kept whole
        #expect(AlbumInfo.typeWords(["album/live"], compilation: false) == "Album · Live")
        #expect(AlbumInfo.typeWords(["Album/Mixtape/Street"], compilation: false) == "Album · Mixtape/Street")
        #expect(AlbumInfo.typeWords(["album; compilation", "ep, spokenword"], compilation: true)
            == "Album · Compilation · EP · Spoken word")
        #expect(AlbumInfo.typeWords([" / "], compilation: false) == nil)
    }

    @Test func addedSaysDeadwaxOnlyOfTheFolderItFiledFirst() {
        let utc = TimeZone(identifier: "UTC")!
        // the earliest folder was there before deadwax; a later one it filed doesn't make the album its download
        let later = [StoreRow(id: 1, path: "a", firstSeen: "2026-10-14T10:00:00+00:00", imported: false),
                     StoreRow(id: 2, path: "b", firstSeen: "2026-10-20T10:00:00+00:00", imported: true)]
        #expect(AlbumInfo.addedWords(later, timeZone: utc) == "14 October 2026")
        let first = [StoreRow(id: 1, path: "a", firstSeen: "2026-10-20T10:00:00+00:00", imported: false),
                     StoreRow(id: 2, path: "b", firstSeen: "2026-10-14T10:00:00.250+00:00", imported: true)]
        #expect(AlbumInfo.addedWords(first, timeZone: utc) == "14 October 2026, downloaded by deadwax")
        #expect(AlbumInfo.addedWords([StoreRow(id: 1, path: "a", firstSeen: "soon")], timeZone: utc) == nil)
    }

    @Test func everyContainersNameForTheDatesAndTheGroup() {
        #expect(AlbumFile(raw: [["----:com.apple.iTunes:ORIGINALDATE", "1995-03-27"]]).values(.originalDate) == ["1995-03-27"])
        #expect(AlbumFile(raw: [["WM/OriginalReleaseTime", "1995"]]).values(.originalDate) == ["1995"])
        #expect(AlbumFile(raw: [["MusicBrainz/Release Group Id", Self.group]]).values(.releaseGroup) == [Self.group])
        #expect(AlbumFile(raw: [["----:com.apple.iTunes:MusicBrainz Release Country", "GB"]]).values(.country) == ["GB"])
    }

    // MARK: MusicBrainz and the server

    @Test func theIdsToCopyAndTheirPages() throws {
        let album = Album(id: "al", musicBrainzId: Self.release.uppercased())
        let rows = AlbumInfo.musicBrainz(album: album, store: nil, files: try Self.files("flac"))
        #expect(rows.map(\.label) == ["Release", "Release group", "This pressing on MusicBrainz", "Every pressing on MusicBrainz"])
        #expect(rows[0].style == .copyable && rows[0].copy == Self.release.uppercased())
        // the release group from the files, with no bridge
        #expect(rows[1].value == Self.group)
        #expect(rows[2].style == .link && rows[2].link?.absoluteString == "https://musicbrainz.org/release/\(Self.release)")
        #expect(rows[3].link?.absoluteString == "https://musicbrainz.org/release-group/\(Self.group)")
        // the bridge's release over the album's own
        let other = "11111111-2222-3333-4444-555555555555"
        let bridged = AlbumInfo.musicBrainz(album: album, store: StoreAlbum(releaseMbid: other), files: nil)
        #expect(bridged.first?.value == other)
        // something that isn't a MusicBrainz id is shown, and links nowhere
        let odd = AlbumInfo.musicBrainz(album: Album(id: "x", musicBrainzId: "not-an-id"), store: nil, files: nil)
        #expect(odd.map(\.label) == ["Release"])
        #expect(AlbumInfo.musicBrainz(album: Album(id: "x", musicBrainzId: ""), store: nil, files: nil).isEmpty)
    }

    @Test func theFolderIsForWhoeverMaySeeIt() {
        let one = StoreAlbum(present: [StoreRow(id: 1, path: "Portishead/Dummy")])
        #expect(AlbumInfo.server(store: one, folders: false).isEmpty)
        let row = AlbumInfo.server(store: one, folders: true).first
        #expect(row?.label == "Folder" && row?.value == "Portishead/Dummy" && row?.copy == "Portishead/Dummy")
        let set = StoreAlbum(present: [StoreRow(id: 1, path: "A/Box (Disc 1)"), StoreRow(id: 2, path: "A/Box (Disc 2)")])
        #expect(AlbumInfo.server(store: set, folders: true).first?.label == "Folders")
        #expect(AlbumInfo.server(store: set, folders: true).first?.value == "A/Box (Disc 1)\nA/Box (Disc 2)")
        #expect(AlbumInfo.server(store: nil, folders: true).isEmpty)
    }

    @Test func whichFoldersAreRead() {
        let rows = (1...10).map { StoreRow(id: $0, path: "A/Box \($0)") } + [StoreRow(id: 99, path: "A/Box 1"), StoreRow(id: 98, path: "")]
        #expect(AlbumInfo.foldersToRead(StoreAlbum(present: rows)) == (1...8).map { "A/Box \($0)" })
        #expect(AlbumInfo.foldersToRead(nil) == [])
    }

    @Test func aSectionWithNothingToSayIsLeftOut() throws {
        let album = Album(id: "al", song: [Self.song("a")])
        let local = AlbumInfo.local(album: album, onPhone: nil)
        #expect(local.map(\.title) == ["Quality", "The album"])
        let withPhone = AlbumInfo.local(album: album, onPhone: AlbumInfo.onPhone(.none, here: 0, of: 1, bytes: 0))
        #expect(withPhone.map(\.title) == ["Quality", "The album", "On this phone"])
        #expect(AlbumInfo.fromServer(album: Album(id: "e"), extras: nil, store: nil, files: nil, folders: true).isEmpty)
        let full = AlbumInfo.fromServer(album: Album(id: "al", musicBrainzId: Self.release), extras: nil,
                                        store: StoreAlbum(present: [StoreRow(id: 1, path: "p")]), files: try Self.files("mp3"),
                                        folders: true)
        #expect(full.map(\.title) == ["The release", "MusicBrainz", "On the server"])
    }

    // MARK: reading getAlbum's other fields

    @Test func getAlbumsOtherFieldsAreReadLeniently() throws {
        let text = #"""
        {"id": "al", "name": "Dummy", "releaseTypes": ["album", 3, "live"], "releaseDate": {"year": 1994, "month": 8},
         "originalReleaseDate": {"year": "1994"}, "version": "Deluxe", "genres": [{"name": "Trip Hop"}, {"name": 5}],
         "isCompilation": false, "recordLabels": [{"name": "Go! Beat"}], "song": []}
        """#
        let extras = try JSONDecoder().decode(AlbumExtras.self, from: Data(text.utf8))
        #expect(extras.releaseTypes == ["album", "live"])
        #expect(extras.releaseDate == .init(year: 1994, month: 8, day: nil))
        #expect(extras.originalReleaseDate == .init(year: nil, month: nil, day: nil))
        #expect(extras.version == "Deluxe")
        #expect(extras.genres?.map(\.name) == ["Trip Hop", nil])
        #expect(extras.isCompilation == false)
        #expect(extras.recordLabels?.first?.name == "Go! Beat")
        // an older Navidrome's answer, with none of them
        let bare = try JSONDecoder().decode(AlbumExtras.self, from: Data(#"{"id": "al"}"#.utf8))
        #expect(bare == AlbumExtras())
        // the files' answer: an odd file is left out, an odd field nil
        let files = try JSONDecoder().decode(AlbumFiles.self, from: Data(#"{"album": "a", "files": [{"disc": "x", "tags": {"media": "CD"}}, 7]}"#.utf8))
        #expect(files.files == [AlbumFile(disc: nil, tags: ["media": "CD"], raw: nil)])
    }

    @Test func theFilesAreAskedForByTheirFolder() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/tracks", 200, #"{"album": "Portishead/Dummy", "files": [{"disc": 1, "tags": {"media": "CD"}, "raw": []}]}"#)
        let files = try await deadwax.albumFiles(folder: "Portishead/Dummy & Co+")
        #expect(files.first?.values(.media) == ["CD"])
        #expect(transport.last?.url.query == "album=Portishead/Dummy%20%26%20Co%2B")
        #expect(transport.last?.timeout == 30)
    }
}
