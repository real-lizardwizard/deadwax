import Foundation

/// What the redrawn artist page counts and says (the redesign, slice R6 - notes/ios.md "The redesign, slice R6: an
/// artist"; Artist.dc.html, iArtist.dc.html): the discography's counts - the phone's "16 · 6 yours" by the Albums heading,
/// the Mac band's chips and its status bar - each album's format in the Mac's table, which rows offer Get, and the
/// page's own words. Everything here is read from what the page already has: its rows (ArtistJoin's), and the songs of
/// your albums in hand.
public enum ArtistPageFacts {
    public enum Words {
        /// The strip's and the toolbar's switch: Studio only, or Everything (Studio only off - every release group).
        public static let studioOnly = MBArtistPage.studioOnly
        public static let everything = "Everything"
        /// VoiceOver's name for the switch - and (R6's review) for the phone strip's tab bar, which holds the switch's
        /// two alone: the managers' two after it are buttons of their own, outside it.
        public static let studioLabel = "Which of their albums"
        /// The managers' two, as the strip and the toolbar draw them - Move albums… the menu's Move albums to {name}…
        /// in full beside it (`.help`, VoiceOver).
        public static let images = ArtistManageWords.imagesItem
        public static let moveAlbums = "Move albums\u{2026}"
        /// The Mac's section under the discography (MostPlayedSongs): the songs YOU have played most. "Your most
        /// played" since slice A2 (James, 26 Nov), so it never reads as the albums' order - "Most played" in the Albums
        /// heading's menu (LastfmWords.mostPlayed), Last.fm's plays, everyone's.
        public static let yourMostPlayed = "Your most played"
        /// The Mac's table's columns (Artist.dc.html's .cols): Album, Year, Songs, In your library, and the buttons'.
        public static let album = LibraryColumnWords.album
        public static let year = LibraryColumnWords.year
        public static let songs = LibraryColumnWords.songs
        public static let inYourLibrary = "In your library"
        public static let actions = ""
        /// A row's buttons: Play and Open an album you have, Get one you don't.
        public static let play = PlaylistWords.play
        public static let open = "Open"
        public static let get = SourcesWords.get
        /// The library cell of an album you don't have.
        public static let notInYourLibrary = "not in your library"

        /// VoiceOver's: "Get Powerage", "Play Highway to Hell", "Open Highway to Hell".
        public static func getLabel(_ title: String) -> String { "\(get) \(title)" }
        public static func playLabel(_ title: String) -> String { "\(play) \(title)" }
        public static func openLabel(_ title: String) -> String { "\(open) \(title)" }
        /// A Most played row's plays, said: "12 plays", "1 play".
        public static func plays(_ count: Int) -> String { ArtistTotals.count(count, one: "play", many: "plays") }
    }

    /// How the discography stands: its albums drawn, those that are yours (ticked, as the rows' lines say - every one
    /// held without a library of your own), those the collection holds that aren't yours, and those nobody holds.
    public struct Counts: Sendable, Equatable {
        public let albums: Int
        public let yours: Int
        public let collection: Int
        public let toGet: Int

        public init(albums: Int, yours: Int, collection: Int, toGet: Int) {
            self.albums = albums
            self.yours = yours
            self.collection = collection
            self.toGet = toGet
        }
    }

    /// The counts of the page's rows. A row of theirs the library hasn't said of yet (held nil) is counted as an album
    /// alone: never one to get, never yours.
    public static func counts(_ rows: [ArtistJoin.Row], personal: Bool) -> Counts {
        var yours = 0, collection = 0, toGet = 0
        for row in rows {
            switch row {
            case .yours(let mine):
                if ArtistPage.marked(mine, personal: personal) { yours += 1 } else { collection += 1 }
            case .theirs(let other):
                if MBArtistPage.marked(other, personal: personal) {
                    yours += 1
                } else if other.held == true {
                    collection += 1
                } else if other.held == false {
                    toGet += 1
                }
            }
        }
        return Counts(albums: rows.count, yours: yours, collection: collection, toGet: toGet)
    }

    /// The phone's Albums heading's count (iArtist's "16 · 6 yours"): the albums, and how many are yours when that is
    /// some and not all - "16 · 6 yours", "6" - nothing with no album.
    public static func heading(_ counts: Counts) -> String {
        guard counts.albums > 0 else { return "" }
        let albums = AlbumInfo.grouped(counts.albums)
        guard counts.yours > 0, counts.yours < counts.albums else { return albums }
        return "\(albums) \u{00B7} \(AlbumInfo.grouped(counts.yours)) yours"
    }

    /// VoiceOver's for it: "16 albums, 6 yours".
    public static func headingSpoken(_ counts: Counts) -> String {
        guard counts.albums > 0 else { return "" }
        let albums = ArtistTotals.albums(counts.albums)
        guard counts.yours > 0, counts.yours < counts.albums else { return albums }
        return "\(albums), \(AlbumInfo.grouped(counts.yours)) yours"
    }

    /// One of the Mac band's chips: its words, and whether it is the green one (yours).
    public struct Chip: Sendable, Equatable, Identifiable {
        public let words: String
        public let yours: Bool

        public var id: String { words }
    }

    /// The band's chips (Artist.dc.html): "6 in your library" in green, "2 in the collection" (with a library of your
    /// own, the collection's that aren't yours), "10 more to get" - each only when it counts something, and (R6's
    /// review) the last only for someone who may get albums (`mayGet`, the request permission): to anyone else there is
    /// nothing to get.
    public static func chips(_ counts: Counts, mayGet: Bool) -> [Chip] {
        var chips: [Chip] = []
        if counts.yours > 0 {
            chips.append(Chip(words: "\(AlbumInfo.grouped(counts.yours)) \(Whose.inYourLibrary)", yours: true))
        }
        if counts.collection > 0 {
            chips.append(Chip(words: "\(AlbumInfo.grouped(counts.collection)) \(Whose.inTheCollection)", yours: false))
        }
        if mayGet && counts.toGet > 0 {
            chips.append(Chip(words: "\(AlbumInfo.grouped(counts.toGet)) more to get", yours: false))
        }
        return chips
    }

    /// The Mac's status bar: "16 albums", "6 in your library", "59 songs" (the songs of your albums in hand). The
    /// drawing's "16 studio albums" is "16 albums": your own albums are listed whatever Studio only says. Its "MusicBrainz
    /// asked 4 minutes ago" is left out - the page keeps no time for its answer.
    public static func status(_ counts: Counts, songs: Int) -> [String] {
        guard counts.albums > 0 else { return [] }
        var items = [ArtistTotals.albums(counts.albums)]
        if counts.yours > 0 { items.append("\(AlbumInfo.grouped(counts.yours)) \(Whose.inYourLibrary)") }
        if songs > 0 { items.append(ArtistTotals.songs(songs)) }
        return items
    }

    /// An album's format in the Mac's table, as Album info's Format says it: "FLAC · 24-bit / 96 kHz" - nothing until its
    /// songs are in.
    public static func format(_ album: Album?) -> String {
        guard let songs = album?.song, !songs.isEmpty else { return "" }
        return AlbumInfo.quality(songs).first { (row: AlbumInfoRow) -> Bool in row.label == "Format" }?.value ?? ""
    }

    /// The library cell's line beside a held album of theirs: "2 pressings" past one, else nothing.
    public static func pressings(_ row: MBArtistPage.Row) -> String {
        row.held == true && row.editions > 1 ? "\(row.editions) pressings" : ""
    }

    /// Whether a row of theirs offers Get: only an album the library has said it doesn't hold - never one it holds,
    /// never one it hasn't said of yet - and (R6's review) only to someone who may get albums (`mayGet`, the request
    /// permission, as the album you don't have and Requests hide Get without it). Without it the row draws what it
    /// would for one held: the chevron on the phone, Open on the Mac.
    public static func offersGet(_ row: MBArtistPage.Row, mayGet: Bool) -> Bool {
        mayGet && row.held == false
    }

    /// (R6's review) Whether the phone's top holds the room of the line under the name (who they are on MusicBrainz):
    /// once it says something, or once it is being asked - who they are known there (an MBID) and deadwax in reach - so
    /// the line arriving late moves nothing under it (Play), as the listeners' line keeps its room. The page keeps it for
    /// its life once held (ArtistView), so an ask that fails leaves the room blank rather than taking it back.
    public static func holdsFacts(mbid: String?, online: Bool, facts: MBArtistFacts?) -> Bool {
        facts != nil || (online && MBID.of(mbid) != nil)
    }

    /// (R6's review) What VoiceOver says of a row of the Mac's table, its buttons its actions: "Low, 1977, in your
    /// library, FLAC · 24-bit / 96 kHz"; "Heroes, 1977, in the collection, 2 pressings"; "Powerage, 1978, not in your
    /// library" - the cells' words in order, the format (`format`, ArtistPageFacts.format's) for an album of yours.
    public static func spoken(_ row: ArtistJoin.Row, personal: Bool, format: String) -> String {
        var parts = [row.title, row.year ?? ""]
        switch row {
        case .yours(let mine):
            parts += [Whose.heldPhrase(personal: personal, yours: mine.yours), format]
        case .theirs(let other):
            if other.held == true {
                parts += [Whose.heldPhrase(personal: personal, yours: other.yours), pressings(other)]
            } else if other.held == false {
                parts.append(Words.notInYourLibrary)
            }
        }
        return parts.filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }

    /// A row's title and year in the Mac's table, whichever list it came from (ArtistJoin.Row's own).
    public static func title(_ row: ArtistJoin.Row) -> String { row.title }
    public static func year(_ row: ArtistJoin.Row) -> String { row.year ?? "" }
}
