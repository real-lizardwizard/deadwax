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
    /// Artwork and Lyrics with Edit albums, Delete with Look after the library). (R11 - notes/ios.md "The redesign, slice
    /// R11: Tags, Artwork, Lyrics and Delete") Every part a tab of the root's own, drawn under the strip as the Mac's
    /// tabs are - none pushed any more. Without Edit albums, Delete alone; with neither, no strip.
    public struct Strip: Sendable, Equatable {
        public let tabs: [AlbumEdit.Part]
    }

    /// The phone's strip for these permissions.
    public static func strip(editors: Bool, delete: Bool) -> Strip {
        let parts = AlbumEdit.parts(editors: editors, remove: delete)
        return Strip(tabs: parts)
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

    // MARK: Tags (R11)

    /// The tracks Edit N tracks edits, in running order (`files`, the folder's as read): those ticked - every track with
    /// none ticked (the web's "Edit all tracks…"). A tick left on a file gone since (a release applied renames them) is
    /// no track of the folder's.
    public static func tagTargets(_ files: [String], ticked: Set<String>) -> [String] {
        let chosen = files.filter { (name: String) -> Bool in ticked.contains(name) }
        return chosen.isEmpty ? files : chosen
    }

    /// How many of the folder's tracks are ticked: the N of Edit N tracks… and Apply to N tracks - 0 with none ticked
    /// (every track, then). Only a ticked row counts, and only one the folder still holds.
    public static func ticked(_ files: [String], _ ticked: Set<String>) -> Int {
        files.reduce(0) { (count: Int, name: String) -> Int in count + (ticked.contains(name) ? 1 : 0) }
    }

    /// Every track ticked: the phone's foot offers Deselect all in place of Select all.
    public static func allTicked(_ files: [String], _ ticked: Set<String>) -> Bool {
        !files.isEmpty && Self.ticked(files, ticked) == files.count
    }

    /// (R11's review) The phone's Select all, and Deselect all once every track is ticked: the ticks it leaves - every
    /// track, or none.
    public static func selectAll(_ files: [String], _ ticked: Set<String>) -> Set<String> {
        allTicked(files, ticked) ? [] : Set(files)
    }

    /// (R11's review) A tick on the Mac (or Edit this track…) over typed work for another set of tracks: "Discard
    /// changes?" first. The same tracks, or nothing typed over, and the editor takes the ticks now.
    public static func asksFirst(_ files: [String], ticked next: Set<String>, editing: [String], typed: Bool) -> Bool {
        typed && tagTargets(files, ticked: next) != editing
    }

    /// (R11's review) What the Mac's editor does once the folder's files are read again - a release applied renames
    /// them, and TagsModel.readFiles keeps of the ticks and of the tracks edited only the names the folder still holds -
    /// so the ticks, the tracks Apply writes to and the typed work stay in step.
    public enum AfterRead: Sendable, Equatable {
        /// As it is: the editor edits the tracks ticked (every track with none).
        case keep
        /// Nothing typed over: the editor takes the tracks ticked.
        case edit([String])
        /// Typed over, some of the tracks edited still there: the ticks become them, so the legend and Apply to N
        /// tracks say the tracks Apply writes to - the typed work kept.
        case tick(Set<String>)
        /// Typed over, none of the tracks edited still there: said, with Discard the one way on - never put away unasked.
        case stranded
    }

    /// See AfterRead. `files` the folder's tracks as read, `ticked` and `editing` as TagsModel holds them after it.
    public static func afterRead(_ files: [String], ticked: Set<String>, editing: [String], typed: Bool) -> AfterRead {
        guard !files.isEmpty else { return .keep }
        let targets = tagTargets(files, ticked: ticked)
        if targets == editing { return .keep }
        if !typed { return .edit(targets) }
        let held = editing.filter { (name: String) -> Bool in files.contains(name) }
        return held.isEmpty ? .stranded : .tick(Set(held))
    }

    // MARK: Delete (R11)

    /// The folder's tracks and their size, as the phone's Tracks row says them (iEditDelete): "10 · 290 MB". What else
    /// is in the folder is deadwax's own words under it (DeleteWords.others): "and 40 other files:" in the caution's
    /// colour over their names - the summary names twelve at most and counts them all (R11's review).
    public static func deleteTracks(_ summary: DeletionSummary) -> String {
        let size = Sources.size(summary.totalBytes)
        return AlbumInfo.grouped(summary.audioFiles) + (size.isEmpty ? "" : " · \(size)")
    }

    /// Who holds the album, short (the phone's In a library row): "Yours only", "Nobody's", "Yours, Ann's and Bo's",
    /// "Ann's" - "Couldn't tell" when deadwax couldn't read it, never "Nobody's"; nil with logins off. The whole sentence
    /// (DeleteWords.holders) says what deleting does to them.
    public static func held(_ summary: DeletionSummary?) -> String? {
        guard let summary else { return nil }
        if summary.holdersUnknown { return Words.couldntTell }
        guard let holders = summary.holders else { return nil }
        let yours = summary.yours == true
        if holders.isEmpty { return yours ? Words.yoursOnly : Words.nobodys }
        let names = (yours ? [Words.yours] : []) + holders.map { (name: String) -> String in "\(name)'s" }
        return DeleteWords.listed(names)
    }

    /// (R11's review) The Mac's foot under Delete: who holds it, short - "In a library: Ann's" - its whole sentence
    /// (DeleteWords.holders) the tab's own row; nothing until the summary says, and nothing with logins off.
    public static func deleteFoot(_ summary: DeletionSummary?) -> String {
        held(summary).map { (held: String) -> String in "\(Words.inALibrary): \(held)" } ?? ""
    }

    /// (R11's review) The album pages a delete closes when Edit album was opened by its folder - Choose the folder, the
    /// Mac's folder list, Needs a look - by the album the folder holds, as an album opening closes its own: each album
    /// page open (`pages`, what each was opened with) is the folder's album when the folders its own Edit album would
    /// find (AlbumEdit.folders - by the release the page knew, else by its name) hold the folder; or when it is the
    /// album the id bridge names for the folder's release (`bridge`, asked as Delete's summary is read), its folders the
    /// bridge's. One the folder was all of (AlbumEdit.deletesAll) goes back (`leave`); one with folders left is asked
    /// again (`ask`). Each page once; one found by nothing is left as it is.
    public struct FolderPages: Sendable, Equatable {
        public let leave: [String]
        public let ask: [String]

        public init(leave: [String] = [], ask: [String] = []) {
            self.leave = leave
            self.ask = ask
        }
    }

    /// See FolderPages. `path` the folder deleted, `tracks` its tracks, `scan` the library's folders before it went.
    public static func folderPages(_ path: String, tracks: Int, bridge: StoreAlbum?, scan: [ScanAlbum],
                                   pages: [AlbumEdit.Subject]) -> FolderPages {
        var leave: [String] = []
        var ask: [String] = []
        var seen = Set<String>()
        for page in pages where !page.id.isEmpty && seen.insert(page.id).inserted {
            let named = bridge.flatMap { (answer: StoreAlbum) -> AlbumEdit.Bridge? in
                answer.navidromeId == page.id ? AlbumEdit.Bridge(answer) : nil
            }
            let folders = AlbumEdit.folders(named, scan, page)
            guard folders.paths.contains(path) else { continue }
            if AlbumEdit.deletesAll(folders, tracks: tracks, page) {
                leave.append(page.id)
            } else {
                ask.append(page.id)
            }
        }
        return FolderPages(leave: leave, ask: ask)
    }

    /// (R11's review) The release a folder opening asks the id bridge by (`bridge` above): the folder's, trimmed - nil
    /// for a folder tagged with none, whose album is found by its name alone.
    public static func bridgeRelease(_ album: ScanAlbum) -> String? {
        let release = album.releaseMbid.trimmingCharacters(in: .whitespacesAndNewlines)
        return release.isEmpty ? nil : release
    }

    // MARK: Artwork (R11)

    /// The Artwork pointer to replacing a cover, on either device: the web's words (GetResults.webCoverPointer) -
    /// Release a tab on the phone too now - naming the button Release shows to compare the covers (`compare`: the
    /// phone's Compare, the Mac's Compare full size…) only while Release shows it (R11's review): with none - no
    /// pressing with a cover found yet - the words alone.
    public static func coverPointer(_ album: ScanAlbum, compare: String?) -> String? {
        GetResults.webCoverPointer(album).map { (words: String) -> String in
            let named = " (\(Words.compareFullSize))"
            return words.replacingOccurrences(of: named, with: compare.map { (button: String) -> String in
                " (\(button))"
            } ?? "")
        }
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
        /// (R11) The Mac's foot under each tab (Main.dc.html's `foots`): what the tab's action does - Delete's, who holds
        /// the album, its summary's (DeleteWords.holders), drawn by the foot itself.
        public static func foot(_ part: AlbumEdit.Part) -> String {
            switch part {
            case .release: return releaseFoot
            case .tags: return tagsFoot
            case .artwork: return artworkFoot
            case .lyrics: return lyricsFoot
            case .delete: return ""
            }
        }
        public static let tagsFoot = "A field left as it is isn’t written."
        public static let artworkFoot = "Pictures are saved into the album folder."
        public static let lyricsFoot = "Lyrics come from LRCLIB, one .lrc beside each track."

        // MARK: Tags (R11)

        /// The phone's foot: Select all - Deselect all once every track is ticked. VoiceOver hears TagEditWords' whole
        /// words ("Select every track").
        public static let selectAll = "Select all"
        public static let deselectAll = "Deselect all"
        /// The line under the tracks (iEditTags, Main.dc.html) in the app's verb, Select (TagEditWords.select): the
        /// drawings' "Tick" is never the app's word.
        public static func tagsNote(_ device: Device) -> String {
            device == .mac ? "Select tracks to edit only those."
                : "Select tracks to edit only those. Tap › to see everything in a track's file."
        }
        /// The Mac's Tags: the editor's legend - "Edit 3 tracks", "Edit all tracks" with none ticked.
        public static func editLegend(_ ticked: Int) -> String {
            ticked > 0 ? "Edit \(ticked) track\(ticked == 1 ? "" : "s")" : "Edit all tracks"
        }
        /// The Mac's foot under Tags: Apply, saying what it writes to - "Apply to 3 tracks", "Apply to all 10 tracks".
        public static func applyTo(ticked: Int, of total: Int) -> String {
            ticked > 0 ? "Apply to \(ticked) track\(ticked == 1 ? "" : "s")"
                : "Apply to all \(AlbumInfo.grouped(total)) track\(total == 1 ? "" : "s")"
        }
        /// The Mac's Tags: the selected row's file, every tag of it, in a sheet - the phone's ›.
        public static let seeEveryTag = "See a file's every tag…"
        /// What VoiceOver says a track's › does on the phone - and the Mac's row, on a double-click.
        public static let everyTagHint = "Shows everything in the track's file"
        /// The Mac's Tags row as VoiceOver hears it: the row's words (TagEditWords.trackRow), its length, and whether its
        /// checkbox is ticked - "Track 3, Shoot to Thrill, 5:17, checked", a checkbox's own word for it. Never
        /// "selected": VoiceOver says that of the row the list has selected, the one See a file's every tag… opens
        /// (R11's review - a ticked row was "selected" twice). Its actions: Select or Deselect, and See a file's every
        /// tag….
        public static func tagRow(_ row: String, length: String, ticked: Bool) -> String {
            "\(row), \(length)" + (ticked ? ", checked" : "")
        }
        /// (R11's review) The Mac's editor once a release applied has renamed every track the typed work was for
        /// (EditAlbumPage.AfterRead.stranded): said, with Discard - the typed work is never put away unasked.
        public static let editedGone = "The tracks these changes were for have been renamed since, so they can't be "
            + "written. Discard them to edit the tracks as they are now."
        public static let deselect = "Deselect"
        /// The Mac's Tags table's columns.
        public static let number = "#"
        public static let title = "Title"
        public static let length = "Length"

        // MARK: Artwork (R11)

        /// Under the cover: a tap (a click) shows it full size.
        public static func seeFullSize(_ device: Device) -> String {
            "\(device == .mac ? "Click" : "Tap") the cover to see it full size."
        }
        /// CD art beside the tracks: what it is for (iEditArtwork).
        public static let discArtNote = "What players show for a song with a disc number."
        /// The Mac's Cover box (Main.dc.html): the folder's cover beside the pressing's, in a sheet - the phone's
        /// Compare covers….
        public static let compareWithPressing = "Compare with this pressing…"
        /// The pointers' button where the album is matched to no release yet: Release, shown.
        public static let openRelease = "Go to Release"

        // MARK: Lyrics (R11)

        /// Beside Get lyrics: it never replaces what is saved (LyricsFetchBody asks for nothing to be replaced).
        public static let nothingReplaced = "Nothing saved is replaced."

        // MARK: Delete (R11)

        /// The phone's rows of what goes (iEditDelete).
        public static let tracks = "Tracks"
        public static let inALibrary = "In a library"
        /// Who holds the album, short (EditAlbumPage.held).
        public static let yoursOnly = "Yours only"
        public static let nobodys = "Nobody's"
        public static let yours = "Yours"
        public static let couldntTell = "Couldn't tell"
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
