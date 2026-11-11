import Foundation

/// The disc headings on the album page, from Navidrome's own answer - the web app's ui/src/lib/discTitles.ts,
/// ported line for line and held to what it answers (Tests/DeadwaxCoreTests/Fixtures/screens/discs.json, written by
/// ios/scripts/export-screen-vectors.cjs; ui/test/discs.sim.cjs's cases among them, by name).
///
/// deadwax writes each disc's MusicBrainz medium title into the files as `discsubtitle`, Navidrome reads it, and its
/// getAlbum answer carries them as OpenSubsonic `discTitles` (`DiscTitle`), only for discs that have one:
///
///  - a heading reads "Disc 4 · <title>" when that disc has a title, "Disc 4" when it has none;
///  - headings show when the album has more than one disc, OR when any of its discs has a title - a one-disc album
///    with no title is drawn with no heading at all;
///  - a song with no disc number (or 0) is on disc 1, as every player treats it;
///  - a title for a disc the album has no songs on is ignored, and so is a blank one; the first title of a disc wins.
///
/// `DiscTitle.disc` is read by the model as a whole number or a string of digits; the web reads it with JS's
/// `Number()`, which also takes " 2 ", "2.0" and `true` - Navidrome sends a number, so the two agree on every answer
/// it gives (About reads the field the web's way for Info, About.swift AboutDiscTitle).
public enum DiscHeadings {
    /// Between a disc's number and its title, and between the parts of the album page's meta line.
    public static let dot = " · "

    /// A song's disc, as a heading counts it: `discNumber || 1`.
    public static func discOf(_ song: Song) -> Int {
        guard let disc = song.discNumber, disc != 0 else { return 1 }
        return disc
    }

    /// Each disc's title, in the order kept - blank titles and discs that aren't whole numbers above 0 left out, the
    /// first title of a disc kept (discTitleMap).
    public static func titleList(_ titles: [DiscTitle]?) -> [(disc: Int, title: String)] {
        var list: [(disc: Int, title: String)] = []
        for entry in titles ?? [] {
            let title = WebText.trim(entry.title ?? "")
            guard let disc = entry.disc, disc > 0, !title.isEmpty, !list.contains(where: { $0.disc == disc }) else { continue }
            list.append((disc, title))
        }
        return list
    }

    /// The same, by disc.
    public static func titleMap(_ titles: [DiscTitle]?) -> [Int: String] {
        Dictionary(titleList(titles).map { ($0.disc, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    /// What a disc's heading says (discHeading).
    public static func heading(_ disc: Int, _ titles: [Int: String]) -> String {
        if let title = titles[disc], !title.isEmpty { return "Disc \(disc)\(dot)\(title)" }
        return "Disc \(disc)"
    }

    /// For each song, the heading to draw ABOVE it, or nil: the first song of each disc gets one, whenever the album
    /// shows headings at all (discHeadings).
    public static func headings(_ songs: [Song], _ titles: [DiscTitle]?) -> [String?] {
        let byDisc = titleMap(titles)
        let discs = Set(songs.map(discOf))
        let show = discs.count > 1 || discs.contains { byDisc[$0] != nil }
        return songs.indices.map { index in
            let disc = discOf(songs[index])
            let first = index == 0 || discOf(songs[index - 1]) != disc
            return show && first ? heading(disc, byDisc) : nil
        }
    }

    /// The headings of an album as Navidrome answered it.
    public static func headings(_ album: Album) -> [String?] {
        headings(album.song ?? [], album.discTitles)
    }
}
