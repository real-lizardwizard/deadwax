import Foundation

/// Edit album redrawn (the Mac and iPhone redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the
/// folder list and Release"): on the Mac one page, the library's folders at its left and the album's editor at its right
/// (Main.dc.html); on the phone the sheet's root as iEdit draws it - the header, the strip of five, Release's cards and
/// the foot. What both read that isn't a word of RetagWords' or EditWords': the folder list's rows and switch, the
/// header's chip, when Revert may go, which parts the strip and the tabs offer, and how the Mac's page lays itself out
/// at the window's width. Nothing here asks deadwax anything: every row and fact is the library's scan's, as it was.
public enum EditAlbumPage {
    // MARK: the folder list (the Mac's left)

    /// The folder list's switch (Main.dc.html's `.seg.lg`): every folder, or only those with an issue still to look at.
    public enum Shown: String, Sendable, CaseIterable, Hashable {
        case all, needsALook

        public var label: String {
            switch self {
            case .all: return Words.all
            case .needsALook: return EditWords.needsALook
            }
        }
    }

    /// The folder list's rows: the scan's folders matching what was typed - every word somewhere in the folder's path,
    /// artist or album, as Choose the folder finds them (AlbumEdit.folderChoices) but every one of them, the list being
    /// lazy - in the Library's order (`libraryOrder`); and, Needs a look, only those the queue lists (`waiting`).
    public static func folders(_ albums: [ScanAlbum], typed: String, shown: Shown) -> [ScanAlbum] {
        let matching = libraryOrder(AlbumEdit.folderChoices(albums, typed: typed, limit: albums.count).shown)
        switch shown {
        case .all: return matching
        case .needsALook: return matching.filter(waiting)
        }
    }

    /// (R10's review) The folders in the Library's order - its Artist sort (Shelf.sorted's `.alphabeticalByArtist`),
    /// the comparisons its own: by artist folded as the Library folds names (accents, case, punctuation and a leading
    /// "The" aside: "AC/DC" among the A's after "Abba", "dEUS" among the D's, "Ólafur Arnalds" among the O's), letters
    /// before `#`; then the year, none last; then the album; then the path, so two folders of one album keep one order.
    /// Choose the folder's path order (raw UTF-16: "AC_DC" before "Abba", "dEUS" and "Ólafur" after Z) is the phone's.
    public static func libraryOrder(_ albums: [ScanAlbum]) -> [ScanAlbum] {
        struct Keyed {
            let artist: FoldKey
            let initial: String
            let year: Int?
            let title: FoldKey
            let path: FoldKey
            let at: Int
        }
        let keyed = albums.enumerated().map { (at: Int, album: ScanAlbum) -> Keyed in
            let artist = FoldKey(Fold.key(album.artist))
            let year = Int(album.year.prefix(4)).flatMap { (year: Int) -> Int? in year > 0 ? year : nil }
            return Keyed(artist: artist, initial: artist.initial, year: year, title: FoldKey(Fold.key(album.album)),
                         path: FoldKey(album.path), at: at)
        }
        let order = keyed.sorted { (x: Keyed, y: Keyed) -> Bool in
            var c = Shelf.byName(x.artist, x.initial, y.artist, y.initial)
            if c == 0 { c = Shelf.missingLast(x.year, y.year, descending: false) }
            if c == 0 { c = Shelf.text(x.title, y.title) }
            if c == 0 { c = Shelf.text(x.path, y.path) }
            return c != 0 ? c < 0 : x.at < y.at
        }
        return order.map { (key: Keyed) -> ScanAlbum in albums[key.at] }
    }

    /// (R10's review) The folder waits in Needs a look: the queue's own rule, asked of the queue's own function
    /// (MetadataQueue.queueAlbums - an issue outstanding as deadwax judges it, or a new import nobody has looked at yet),
    /// so the switch, the status bar, the queue and the sidebar's badge (NeedsLook.summaryTotal) never count different
    /// things.
    public static func waiting(_ album: ScanAlbum) -> Bool {
        !MetadataQueue.queueAlbums([album], nil).isEmpty
    }

    /// How many issues a folder still has to look at (MetadataQueue.outstanding: one marked fine no longer counts).
    public static func issues(_ album: ScanAlbum) -> Int {
        MetadataQueue.outstanding(album).count
    }

    /// (R10's review) A row's mark: nothing for a folder the queue doesn't list; else its issues still to look at, amber
    /// - or, a new import with none, "New" (NeedsLook.newWord, the queue's own chip).
    public enum Mark: Sendable, Equatable {
        case issues(Int)
        case new
    }

    public static func mark(_ album: ScanAlbum) -> Mark? {
        guard waiting(album) else { return nil }
        let count = issues(album)
        if count > 0 { return .issues(count) }
        return MetadataQueue.isNewImport(album) ? .new : nil
    }

    /// How many of the scan's folders wait in Needs a look: the status bar's "3 need a look" - the queue's own count,
    /// the sidebar's badge's (NeedsLook.summaryTotal), never a count of this page's.
    public static func needingALook(_ albums: [ScanAlbum]) -> Int {
        NeedsLook.summaryTotal(albums)
    }

    // MARK: the header

    /// The folder is tagged with a MusicBrainz release: the header's green chip - else the plain one, "Not matched".
    public static func matched(_ album: ScanAlbum) -> Bool {
        !JSText.trim(album.releaseMbid).isEmpty
    }

    // MARK: the strip (the phone) and the tabs (the Mac)

    /// What the phone's strip offers, by the person's permissions (Managing.albumEdit, AlbumEdit.parts - Release, Tags,
    /// Artwork and Lyrics with Edit albums, Delete with Look after the library): `tabs` the parts drawn on the root
    /// under it - Release alone in R10 - and `pushes` the parts that are still pages of their own, pushed as the root's
    /// rows pushed them (Tags, Artwork, Lyrics, Delete), until R11 makes each a tab of the root. Without Edit albums no
    /// tab at all: Delete alone, as the root had Delete album… alone.
    public struct Strip: Sendable, Equatable {
        public let tabs: [AlbumEdit.Part]
        public let pushes: [AlbumEdit.Part]
    }

    /// The phone's strip for these permissions.
    public static func strip(editors: Bool, delete: Bool) -> Strip {
        let parts = AlbumEdit.parts(editors: editors, remove: delete)
        let tabs = parts.filter { (part: AlbumEdit.Part) -> Bool in part == .release }
        return Strip(tabs: tabs, pushes: parts.filter { (part: AlbumEdit.Part) -> Bool in !tabs.contains(part) })
    }

    /// The Mac's folder tabs for these permissions: every part the person may use, in the web's order (`EDIT_TABS`).
    public static func tabs(editors: Bool, delete: Bool) -> [AlbumEdit.Part] {
        AlbumEdit.parts(editors: editors, remove: delete)
    }

    /// The tab shown once the tabs change (another person, other permissions): the one chosen while it is still offered,
    /// else the first offered - Release, or Delete alone.
    public static func shown(_ chosen: AlbumEdit.Part, in tabs: [AlbumEdit.Part]) -> AlbumEdit.Part {
        tabs.contains(chosen) ? chosen : (tabs.first ?? .release)
    }

    // MARK: Revert

    /// Revert (the foot's, beside Apply): Release's typed work - the fields, the cover's switch, a pressing picked - put
    /// back as the folder has it, the pressing it is tagged with chosen again, as the editor opens. Only with typed work
    /// to put back, deadwax in reach, no write or mark under way, and the folder not waiting to be read again after one:
    /// a Release made afresh then would offer Apply on what the folder held before the write.
    public static func canRevert(unsaved: Bool, online: Bool, writing: Bool, marking: Bool, needsRead: Bool) -> Bool {
        unsaved && online && !writing && !marking && !needsRead
    }

    // MARK: the Mac's page at the window's width

    /// How the Mac's page lays itself out at its own width (the window less the sidebar, and the side panel when open):
    /// the folder list 398 wide (MacLook.folderListWidth) from 1000 (Main.dc.html: 1060 at the window's opening 1280),
    /// 280 under it - with no Artist column, which the row's VoiceOver label and its help still say - so the editor
    /// keeps 379 at the smallest window (880, the page 660) and about 378 at 1280 with the side panel open (the page
    /// 1280 - 220 - 400 - 1, about 659); Release in two columns from an editor of 620 (each about 300), one under 620;
    /// the header's chip and Open album beside its words from an editor of 560, under them below that.
    public struct Layout: Sendable, Equatable {
        public let list: Double
        public let artistColumn: Bool
        public let editor: Double
        public let twoColumns: Bool
        public let headerBeside: Bool

        public init(page: Double) {
            let wide = page >= Self.wideList
            list = wide ? MacLook.folderListWidth : Self.narrowList
            artistColumn = wide
            editor = max(0, page - list - 1)
            twoColumns = editor >= Self.twoColumnsFrom
            headerBeside = editor >= Self.headerBesideFrom
        }

        public static let narrowList: Double = 280
        public static let wideList: Double = 1000
        public static let twoColumnsFrom: Double = 620
        public static let headerBesideFrom: Double = 560
    }

    /// The folder list's columns' fixed widths (Main.dc.html's `.cols`): Artist 112, Year 50, the count 42 - Album takes
    /// what they leave.
    public static let artistWidth: Double = 112
    public static let yearWidth: Double = 50
    public static let countWidth: Double = 42

    // MARK: the words

    public enum Words {
        /// The phone's chip in the top bar (iEdit's `.chip.green`).
        public static let matched = "Matched"
        /// The Mac's, in the header (Main.dc.html) - EditWords.releaseValue's words for a folder matched.
        public static let matchedMusicBrainz = "Matched to MusicBrainz"
        /// Either's plain chip, for a folder tagged with no release.
        public static let notMatched = "Not matched"
        public static let revert = "Revert"
        /// The Mac's header: the album's page, when the editor was opened from it.
        public static let openAlbum = "Open album"
        /// The phone's Fields: the second label on the Year row.
        public static let original = "Original"
        /// The Mac's Pressing box (Main.dc.html's legend), its field as VoiceOver calls it, and its button: search
        /// MusicBrainz with what the field says.
        public static let pressing = "Pressing"
        public static let musicBrainzSearch = "MusicBrainz search"
        public static let findReleases = "Find releases"
        /// The phone's Release card: Choose a release.
        public static let change = "Change…"
        /// The phone's Cover card: Compare covers.
        public static let compare = "Compare"
        /// The Mac's Cover box: Compare covers, as a sheet.
        public static let compareFullSize = "Compare full size…"
        /// The Mac's Cover box: the two covers' captions.
        public static let inTheFolder = "In the folder"
        public static let thisPressing = "This pressing"
        /// The Mac's What Apply does: every file's changes, under the summary - and put away again.
        public static let showChanges = "Show every change"
        public static let hideChanges = "Hide the changes"
        /// The Mac's foot under Release (Main.dc.html's `foots.release`).
        public static let releaseFoot = "Apply writes the tags and files the folder. There is no undo."
        /// The Mac's foot under the parts still today's pages (R11 draws each): what opens them.
        public static let partFoot = "Opens as it does today, over this page."
        /// The Mac's foot under a part still today's page: its button.
        public static func openPart(_ part: AlbumEdit.Part) -> String { "Open \(part.label)…" }
        /// What VoiceOver calls the strip and the tabs.
        public static let parts = "Edit album's parts"
        /// The folder list's switch: everything.
        public static let all = "All"
        /// What VoiceOver calls the folder list's switch.
        public static let show = "Show"
        /// What VoiceOver calls the folder list.
        public static let folderList = "Folders"
        /// The folder list with nothing to show: nothing matches what was typed, or no folder needs a look.
        public static let noneMatch = "No folders match."
        public static let noneNeedALook = "No folder needs a look."
        /// The Mac's editor with no folder chosen yet.
        public static let pickAFolder = "Choose a folder at the left to edit it."
        /// The status bar: how many folders the list shows, and how many of the scan's need a look.
        public static func folders(_ count: Int) -> String { "\(AlbumInfo.grouped(count)) folder\(count == 1 ? "" : "s")" }
        public static func needALook(_ count: Int) -> String { "\(AlbumInfo.grouped(count)) need\(count == 1 ? "s" : "") a look" }
        /// A row's count, as VoiceOver hears it.
        public static func issues(_ count: Int) -> String { "\(count) issue\(count == 1 ? "" : "s") to look at" }
        /// (R10's review) A row's New mark, as VoiceOver hears it - the queue's facet's words.
        public static let newlyAdded = "Newly added"
        /// A row's mark in words: its issues, or Newly added.
        public static func mark(_ mark: EditAlbumPage.Mark?) -> String {
            switch mark {
            case .issues(let count): return issues(count)
            case .new: return newlyAdded
            case nil: return ""
            }
        }
        /// A folder's row, read as one: its album, its artist, its year, its mark.
        public static func folderRow(_ album: ScanAlbum) -> String {
            [album.album.isEmpty ? album.path : album.album, album.artist, album.year, mark(EditAlbumPage.mark(album))]
                .filter { !$0.isEmpty }.joined(separator: ", ")
        }
        /// (R10's review) The Mac's Find over the folder list: short enough for the field's 114 points beside the
        /// switch - what it finds by (EditWords.folderPrompt) its name to VoiceOver and its help.
        public static let findFolders = "Find folders"
    }
}
