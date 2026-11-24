import Foundation

// Manual search, slice A1 (notes/ios.md "Manual search, slice A1"; the design is ~/Desktop/Code/deadwax-plans/manual-search.md,
// the server's half notes/downloads.md "Manual search (2.1.37, 2.1.38)"). James, 24 Nov: "let's add a manual search in
// the requests tab" - Soulseek by artist and album, including albums MusicBrainz doesn't have. Requests' first row, Search
// Soulseek…, opens a form of two fields; Search pushes the Choose a source page an album's Get opens, its folders ranked
// first by how closely their names fit the words (the server's `name_match`), and Get there is any Get - its download
// filed by its own tags. The iPhone and Mac app only: the web never asks one. Its rules and words are here, the phone's
// and the Mac's alike - none names the device (DeviceWordsTests holds both).

public enum ManualSearch {
    // MARK: the row and the form

    /// The sheet's title, and the Requests row's name for VoiceOver ("Search Soulseek, button").
    public static let title = "Search Soulseek"
    /// Requests' first row, above the headings: it opens a form.
    public static let row = "Search Soulseek\u{2026}"
    public static let artistField = "Artist"
    public static let albumField = "Album"
    /// Under the two fields.
    public static let footer =
        "For an album MusicBrainz doesn't have, or one you'd rather find by name. The folders people share are ranked by how well their names fit, and the one you get is filed by its own tags."
    public static let search = "Search"
    /// Over the fields while deadwax can't be reached (Search off): the Sources sheet's own words.
    public static let offline = StoreLine.offline

    /// Search is on when both fields have words after trimming - the server refuses a manual question with either blank
    /// (400 "Type an artist and an album."), so the app never asks one.
    public static func canSearch(artist: String, album: String) -> Bool {
        !JSText.trim(artist).isEmpty && !JSText.trim(album).isEmpty
    }

    // MARK: the results

    /// Choose a source's subtitle for a manual search, where an album's Get has its title and pressing.
    public static let subtitle = "Your own search \u{00B7} filed by its own tags"

    /// The server dropped the manual flag without a word (before deadwax 2.1.38, which echoes it): it would file the
    /// download by the typed words, written over every file's own album and artists - so every Get is off.
    public static func needsNewer(_ release: GetRelease, _ answer: FindCandidatesAnswer?) -> Bool {
        guard release.manual, let answer else { return false }
        return !answer.manual
    }

    /// Above the cards when `needsNewer`: for anyone, and for whoever runs deadwax (Access.seesDetail), the version.
    public static func tooOld(runs: Bool) -> String {
        runs ? "This needs deadwax 2.1.38 or later on the server." : "This needs a newer deadwax - ask whoever runs it."
    }

    /// Why Gets are off over the cards - and with the outcome, to VoiceOver - or nil.
    public static func tooOldLine(_ release: GetRelease, _ answer: FindCandidatesAnswer?, runs: Bool) -> String? {
        needsNewer(release, answer) ? tooOld(runs: runs) : nil
    }

    // MARK: Requests

    /// Where a row's edition goes, for a manual search's download: "OK Computer · manual search".
    public static let mark = "manual search"

    /// Under a manual search's Done row once it is filed: Edit album > Release can match it to a pressing (with Edit),
    /// else that it isn't matched.
    public static func doneFiled(edits: Bool) -> String {
        edits
            ? "Filed by its own tags. Edit album > Release can match it to a pressing."
            : "Filed by its own tags, not matched to a pressing."
    }

    /// A Done row's quiet line: `doneFiled` under a manual search's download this filed (RequestRow.ownTags), else nil.
    public static func doneLine(_ row: RequestRow, edits: Bool) -> String? {
        row.ownTags ? doneFiled(edits: edits) : nil
    }
}
