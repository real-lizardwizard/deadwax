import Foundation

/// An album's and a playlist's facts on the Mac's pages (the redesign, slice R5 - Album.dc.html, Playlists.dc.html,
/// Playlist.dc.html; notes/ios.md "The redesign, slice R5: an album, Playlists, a playlist"): the album's Properties
/// box, its status bar, a song's Plays, and the line saying when and how often it was played - "Played yesterday · 12
/// times" - which Album info says too (its Played row), so the album's page and Albums' Info never disagree (check
/// 555). The day's words are R2's, ArtistTotals.lastPlayedWords - today, yesterday, 3 days ago, last week, the date -
/// read against a `now` the page re-reads at a day's change: no second set of them here.
///
/// Every fact is what the app already has - getAlbum's album and songs, the id bridge's folder for whoever may see it,
/// the playlists list - and one Navidrome didn't give is left out, never drawn as nothing-at-all: a nil play count is
/// a blank cell (never 0), a size only when every song of every disc says its own.
public enum MacAlbumFacts {
    /// A fact in the Properties box (.group's rows): its label and its value.
    public struct Fact: Sendable, Equatable, Identifiable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }

        public var id: String { label }
    }

    /// The pages' words.
    public enum Words {
        public static let properties = "Properties"
        public static let released = "Released"
        public static let added = "Added"
        public static let format = "Format"
        public static let size = "Size"
        /// Album info's row (check 555): "Played" - "yesterday · 12 times".
        public static let played = "Played"
        /// The columns (Album.dc.html, Playlist.dc.html, Playlists.dc.html).
        public static let number = "#"
        public static let title = "Title"
        public static let plays = LibraryColumnWords.plays
        public static let length = "Length"
        public static let album = LibraryColumnWords.album
        public static let playlist = "Playlist"
        public static let songs = LibraryColumnWords.songs
        public static let whose = "Whose"
        public static let changed = "Changed"
        /// The ••• column's header says nothing (the drawing's 44 wide, empty).
        public static let more = ""
        /// "On this Mac".
        public static func onDevice(_ device: Device) -> String { DownloadWords.onThisDevice(device) }
        /// A playlist that is yours (Whose), as the Playlists list's group names it.
        public static let yours = PlaylistWords.yours
        /// A playlist from a file in the music folders (Whose).
        public static let fromAFile = "From a file"
        /// One whose owner Navidrome didn't name.
        public static let somebody = "Somebody"
    }

    static let dot = DiscHeadings.dot

    // MARK: the songs' lines

    /// A song's row in the album's list, by its place and its id (a song twice on an album is two rows).
    public static func lineID(_ index: Int, _ song: Song) -> String {
        "\(index)|\(song.id)"
    }

    /// The album's songs as the Mac's list draws them (R5's review): a disc's heading row (MacTable's `.group`) above
    /// the first song of each disc wherever the phone's page draws one - more than one disc, or a disc with a title -
    /// carrying its title ("Disc 2 · Live"); each song a row by `lineID`, its # its own track number. `headings` is
    /// DiscHeadings.headings' (the page model's), one per song. This departs from the drawing's "2-3" numbering, so a
    /// disc's title survives and "1-10" never overflows the 46-point # column.
    public static func songLines(_ songs: [Song], headings: [String?]) -> [MacTable.Line<String>] {
        var lines: [MacTable.Line<String>] = []
        for (index, song) in songs.enumerated() {
            if headings.indices.contains(index), let heading = headings[index] { lines.append(.group(heading)) }
            lines.append(.row(lineID(index, song)))
        }
        return lines
    }

    // MARK: a song's Plays

    /// A song's Plays cell: "12", "1,411" - nothing for a song Navidrome gives no count for. Navidrome sends playCount
    /// only once a song has been played, so a nil is never drawn as 0; a count of none is blank, as Artists' Plays.
    public static func plays(_ count: Int?) -> String {
        guard let count else { return "" }
        return ArtistTotals.plays(count)
    }

    // MARK: played

    /// When the album was last played and how often, after "Played": "yesterday · 12 times", "today · once", "12 Nov" -
    /// nil when it never was (no time, or Navidrome's zero time). Days are the calendar's in `zone`, read against `now`
    /// (ArtistTotals.now(), re-read at a day's change).
    public static func playedWords(_ played: String?, count: Int?, now: Int64, zone: TimeZone = .current) -> String? {
        guard let ms = AlbumTime.ms(played, zone: zone), ms > 0 else { return nil }
        let when = ArtistTotals.lastPlayedWords(ms, now: now, zone: zone)
        guard let count, count > 0 else { return when }
        return "\(when)\(dot)\(times(count))"
    }

    /// The album page's line (Album.dc.html's hero): "Played yesterday · 12 times" - nil when it never was.
    public static func played(_ album: Album, now: Int64, zone: TimeZone = .current) -> String? {
        playedWords(album.played, count: album.playCount, now: now, zone: zone).map { (words: String) -> String in
            "\(Words.played) \(words)"
        }
    }

    /// Album info's row (check 555): the same words as the page's line, under "Played" - nil when it never was.
    public static func playedRow(_ album: Album, now: Int64, zone: TimeZone = .current) -> AlbumInfoRow? {
        playedWords(album.played, count: album.playCount, now: now, zone: zone).map { (words: String) -> AlbumInfoRow in
            AlbumInfoRow(label: Words.played, value: words)
        }
    }

    /// "once", "12 times", "1,411 times".
    static func times(_ count: Int) -> String {
        count == 1 ? "once" : "\(AlbumInfo.grouped(count)) times"
    }

    // MARK: the album's size

    /// The album's size: every song's, every disc's - nil unless every song says its own (a part never drawn as the
    /// whole), as Album info's Size.
    public static func size(_ songs: [Song]) -> Int64? {
        guard !songs.isEmpty, songs.allSatisfy({ (song: Song) -> Bool in (song.size ?? 0) > 0 }) else { return nil }
        return songs.reduce(Int64(0)) { (sum: Int64, song: Song) -> Int64 in sum + (song.size ?? 0) }
    }

    // MARK: Properties

    /// The Properties box (Album.dc.html's .group): Released (the album's year), Added (when Navidrome got it, the
    /// day in `zone`), Format (Album info's Quality line), Size (every disc), and Album info's own folder row - "Folder",
    /// or "Folders" for an album in more than one (AlbumInfo.server's, by its rule: the id bridge's, for whoever may see
    /// it - `folder` nil otherwise). When it was played is the hero's line (`played`), not a row here. The drawing's
    /// Pressing is left out: the app has no pressing's name to give (Album info's The release has its edition, asked of
    /// deadwax there).
    public static func properties(_ album: Album, songs: [Song], folder: AlbumInfoRow?,
                                  zone: TimeZone = .current) -> [Fact] {
        var facts: [Fact] = []
        if let year = album.year, year > 0 { facts.append(Fact(label: Words.released, value: String(year))) }
        if let added = added(album.created, zone: zone) { facts.append(Fact(label: Words.added, value: added)) }
        if let format = AlbumInfo.quality(songs).first(where: { (row: AlbumInfoRow) -> Bool in row.label == "Format" }) {
            facts.append(Fact(label: Words.format, value: format.value))
        }
        if let size = size(songs) { facts.append(Fact(label: Words.size, value: Bytes.words(size))) }
        if let folder, !folder.value.isEmpty { facts.append(Fact(label: folder.label, value: folder.value)) }
        return facts
    }

    /// When Navidrome got the album, as a day in `zone`, in Album info's words: "12 November 2025" - nil for none.
    static func added(_ created: String?, zone: TimeZone) -> String? {
        guard let ms = AlbumTime.ms(created, zone: zone), ms > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(ms) / 1000))
        return AlbumInfo.dateWords(year: parts.year, month: parts.month, day: parts.day)
    }

    // MARK: the status bar

    /// The album page's status bar (Album.dc.html's .status): "10 songs", "42 min" and the size when every song says
    /// its own. The drawing's format and "Navidrome up to date" are left out (the build plan's section 4).
    public static func status(_ songs: [Song]) -> [String] {
        guard !songs.isEmpty else { return [] }
        var items = [ArtistTotals.songs(songs.count)]
        let length = Format.formatDuration(AlbumPageLines.total(songs))
        if !length.isEmpty { items.append(length) }
        if let size = size(songs) { items.append(Bytes.words(size)) }
        return items
    }

    // MARK: playlists

    /// Whose a playlist is (Playlists.dc.html's Whose): "Yours", its owner's name, "From a file".
    public static func whose(_ playlist: Playlist) -> String {
        switch PlaylistRules.group(of: playlist) {
        case .yours: return Words.yours
        case .files: return Words.fromAFile
        case .shared:
            let owner = WebText.trim(playlist.owner)
            return owner.isEmpty ? Words.somebody : owner
        }
    }

    /// When a playlist last changed (Changed): today, yesterday, 3 days ago, last week, "21 Nov" - Last played's words,
    /// read against `now`; nothing for a time Navidrome didn't give.
    public static func changed(_ playlist: Playlist, now: Int64, zone: TimeZone = .current) -> String {
        guard let ms = AlbumTime.ms(playlist.changed, zone: zone), ms > 0 else { return "" }
        return ArtistTotals.lastPlayedWords(ms, now: now, zone: zone)
    }

    /// A playlist page's line under its name (Playlist.dc.html's hero): "Yours · changed today", "Sam's · Shared with
    /// you · changed 21 Nov" - whose (PlaylistRules.ownerLine), then when it last changed.
    public static func playlistLine(_ playlist: Playlist, now: Int64, zone: TimeZone = .current) -> String {
        let when = changed(playlist, now: now, zone: zone)
        let owner = PlaylistRules.ownerLine(playlist)
        return when.isEmpty ? owner : "\(owner)\(dot)changed \(when)"
    }

    /// The Playlists list's status bar (Playlists.dc.html's .status): "9 playlists", "7 yours", "2 shared with you" -
    /// of the playlists listed (those Find finds, or those on this device while deadwax can't be reached), as R2's lists
    /// count theirs; nothing while none is listed (the page's own words say why), never "0 playlists".
    public static func playlistsStatus(_ playlists: [Playlist]) -> [String] {
        guard !playlists.isEmpty else { return [] }
        let yours = playlists.filter { (playlist: Playlist) -> Bool in PlaylistRules.group(of: playlist) == .yours }.count
        let shared = playlists.filter { (playlist: Playlist) -> Bool in PlaylistRules.group(of: playlist) == .shared }.count
        var items = [ArtistTotals.count(playlists.count, one: "playlist", many: "playlists")]
        if yours > 0 { items.append("\(yours) yours") }
        if shared > 0 { items.append("\(shared) shared with you") }
        return items
    }

    /// A playlist's Length cell: "1 h 04 min" as drawn is the album's own coarse length here - "1h 4m", "48 min"
    /// (PlaylistRules.lengthText), so the list and the playlist's page say one length.
    public static func length(_ seconds: Double) -> String {
        PlaylistRules.lengthText(seconds)
    }

    // MARK: the Playlists list's columns (R5's review)

    /// A column of the Playlists list (Playlists.dc.html's .cols).
    public enum PlaylistColumn: String, Sendable, CaseIterable {
        case playlist, songs, length, whose, changed, onDevice
    }

    /// Each column's width. The drawing's 80, 110, 130, 140 and 150 (610 together) left Playlist nothing beside the side
    /// panel (a 1280 window's page is 589 there), so each is narrowed to what its header and its longest usual words
    /// need - Playlist taking what they leave.
    public static func playlistWidth(_ column: PlaylistColumn) -> MacTable.Width {
        switch column {
        case .playlist: return .flexible
        case .songs: return .fixed(64)
        case .length: return .fixed(84)
        case .whose: return .fixed(110)
        case .changed: return .fixed(110)
        case .onDevice: return .fixed(110)
        }
    }

    /// The least Playlist is left: a cover and a name of some length.
    public static let playlistLeast: Double = 160

    /// The columns dropped first when the list is narrow: Whose (each row's right-click and its page say it) and
    /// Changed.
    public static let playlistDropped: Set<PlaylistColumn> = [.whose, .changed]

    /// The columns a list `width` wide draws: all six while Playlist keeps its least beside them, else all but Whose
    /// and Changed - so the fixed ones never reach past the page, as R2's lists keep theirs within it.
    public static func playlistColumns(width: Double) -> [PlaylistColumn] {
        let all = PlaylistColumn.allCases
        if width - fixedWidth(all) >= playlistLeast { return all }
        return all.filter { (column: PlaylistColumn) -> Bool in !playlistDropped.contains(column) }
    }

    /// The fixed columns' widths together.
    public static func fixedWidth(_ columns: [PlaylistColumn]) -> Double {
        columns.reduce(0.0) { (sum: Double, column: PlaylistColumn) -> Double in
            if case .fixed(let points) = playlistWidth(column) { return sum + points }
            return sum
        }
    }

    /// A column's header.
    public static func playlistTitle(_ column: PlaylistColumn, device: Device) -> String {
        switch column {
        case .playlist: return Words.playlist
        case .songs: return Words.songs
        case .length: return Words.length
        case .whose: return Words.whose
        case .changed: return Words.changed
        case .onDevice: return Words.onDevice(device)
        }
    }
}
