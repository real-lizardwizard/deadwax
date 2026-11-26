import Foundation
import Testing
@testable import DeadwaxCore

/// Edit album redrawn (notes/ios.md "The redesign, slice R10: Edit album, the folder list and Release"): the Mac's folder
/// list and its switch, the header's chip, the strip's and the tabs' parts by permission, Revert's gate, and the Mac's
/// page at each width - and (R11) the tags' ticks, the feet's words and what a delete takes, said in rows. tests/test_ios_edit_look.py holds where the app draws each.
@Suite struct EditAlbumPageTests {
    // (R10's review) as deadwax sends them: an album with an issue outstanding needs attention (the queue's own word,
    // `needs_attention`); one whose every issue was marked fine doesn't
    private let albums = [
        ScanAlbum(path: "Sigur Rós/( ) (2002)", artist: "Sigur Rós", album: "( )", year: "2002"),
        ScanAlbum(path: "AC_DC/Back in Black (1980) [2003 remaster]", artist: "AC/DC", album: "Back in Black",
                  year: "2003", releaseMbid: "a4f2c0de", issues: ["missing_cover", "no_year"], needsAttention: true),
        ScanAlbum(path: "Abba/Arrival (1976)", artist: "ABBA", album: "Arrival", year: "1976",
                  issues: ["missing_cover"], ignoredIssues: ["missing_cover"]),
    ]

    /// (R10's review) Two clean new imports - filed by deadwax, nobody has looked at them yet: the queue lists them
    /// with no issue at all, and the sidebar's badge counts them.
    private let fresh = [
        ScanAlbum(path: "dEUS/The Ideal Crash (1999)", artist: "dEUS", album: "The Ideal Crash", year: "1999",
                  imported: true),
        ScanAlbum(path: "Ólafur Arnalds/Re:member (2018)", artist: "Ólafur Arnalds", album: "re:member", year: "2018",
                  imported: true),
        // filed, and looked at: no longer new
        ScanAlbum(path: "Zola Jesus/Okovi (2017)", artist: "Zola Jesus", album: "Okovi", year: "2017", imported: true,
                  reviewed: true),
    ]

    @Test func theListIsEveryFolderInTheLibrarysOrderOrThoseTheQueueLists() {
        // the Library's order (its Artist sort): "Abba" before "AC/DC" (folded, the slash a space), never Choose the
        // folder's raw path order ("AC_DC" before "Abba") - every one, the list being lazy
        #expect(EditAlbumPage.folders(albums, typed: "", shown: .all).map(\.album) == ["Arrival", "Back in Black", "( )"])
        // "dEUS" among the D's and "Ólafur" among the O's, not after Z as raw UTF-16 puts them
        let all = albums + fresh
        #expect(EditAlbumPage.folders(all, typed: "", shown: .all).map(\.artist)
                == ["ABBA", "AC/DC", "dEUS", "Ólafur Arnalds", "Sigur Rós", "Zola Jesus"])
        #expect(AlbumEdit.folderChoices(all, typed: "", limit: all.count).shown.map(\.artist).suffix(2)
                == ["dEUS", "Ólafur Arnalds"])
        // one artist: by year (none last), then the album, then the path
        let one = [
            ScanAlbum(path: "Low/c", artist: "Low", album: "Things We Lost in the Fire", year: ""),
            ScanAlbum(path: "Low/b", artist: "Low", album: "Secret Name", year: "1999"),
            ScanAlbum(path: "Low/a2", artist: "Low", album: "I Could Live in Hope", year: "1994"),
            ScanAlbum(path: "Low/a1", artist: "Low", album: "I Could Live in Hope", year: "1994"),
            ScanAlbum(path: "#/x", artist: "!!!", album: "Myth Takes", year: "2007"),
        ]
        #expect(EditAlbumPage.libraryOrder(one).map(\.path) == ["Low/a1", "Low/a2", "Low/b", "Low/c", "#/x"])
        // every word somewhere in the path, the artist or the album, accents and case aside
        #expect(EditAlbumPage.folders(albums, typed: "sigur ros 2002", shown: .all).map(\.album) == ["( )"])
        #expect(EditAlbumPage.folders(albums, typed: "ac/dc", shown: .all).map(\.album) == ["Back in Black"])
        // Needs a look: what the queue lists - an issue outstanding (one marked fine no longer is), or a new import
        // nobody has looked at, issues or none
        #expect(EditAlbumPage.folders(albums, typed: "", shown: .needsALook).map(\.album) == ["Back in Black"])
        #expect(EditAlbumPage.folders(albums, typed: "abba", shown: .needsALook).isEmpty)
        #expect(EditAlbumPage.folders(all, typed: "", shown: .needsALook).map(\.album)
                == ["Back in Black", "The Ideal Crash", "re:member"])
        #expect(EditAlbumPage.issues(albums[1]) == 2 && EditAlbumPage.issues(albums[2]) == 0)
        // the status bar's count is the queue's and the sidebar badge's, through the queue's own function
        #expect(EditAlbumPage.needingALook(albums) == 1)
        #expect(EditAlbumPage.needingALook(all) == 3)
        for scan in [albums, fresh, all, []] {
            #expect(EditAlbumPage.needingALook(scan) == NeedsLook.summaryTotal(scan))
            #expect(EditAlbumPage.folders(scan, typed: "", shown: .needsALook).count == NeedsLook.summaryTotal(scan))
            #expect(Set(EditAlbumPage.folders(scan, typed: "", shown: .needsALook).map(\.path))
                    == Set(MetadataQueue.queueAlbums(scan, nil).map(\.path)))
        }
        // a row's mark: its issues; New for a clean new import; nothing for a folder the queue doesn't list
        #expect(EditAlbumPage.mark(albums[1]) == .issues(2))
        #expect(EditAlbumPage.mark(fresh[0]) == .new && EditAlbumPage.mark(fresh[1]) == .new)
        #expect(EditAlbumPage.mark(albums[0]) == nil && EditAlbumPage.mark(albums[2]) == nil)
        #expect(EditAlbumPage.mark(fresh[2]) == nil)
        // issues the server doesn't call needing attention aren't the queue's either
        #expect(EditAlbumPage.mark(ScanAlbum(path: "A/B", issues: ["no_year"])) == nil)
        // more folders than Choose the folder shows (its 50): all of them
        let many = (0..<120).map { (n: Int) -> ScanAlbum in ScanAlbum(path: String(format: "A/%03d", n)) }
        #expect(EditAlbumPage.folders(many, typed: "", shown: .all).count == 120)
        #expect(EditAlbumPage.Shown.allCases.map(\.label) == ["All", "Needs a look"])
    }

    @Test func theChipIsTheReleaseTheFolderIsTaggedWith() {
        #expect(EditAlbumPage.matched(albums[1]))
        #expect(!EditAlbumPage.matched(albums[0]))
        #expect(!EditAlbumPage.matched(ScanAlbum(path: "A/B", releaseMbid: "  ")))
    }

    @Test func theStripAndTheTabsAreThePermissions() {
        // (R11) Edit albums and Look after the library: every part a tab of the root's, none pushed
        let both = EditAlbumPage.strip(editors: true, delete: true)
        #expect(both.tabs == [.release, .tags, .artwork, .lyrics, .delete])
        // Edit albums alone: no Delete
        let editors = EditAlbumPage.strip(editors: true, delete: false)
        #expect(editors.tabs == [.release, .tags, .artwork, .lyrics])
        // Look after the library alone: Delete only, as the root had Delete album… alone - shown, the one tab offered
        let delete = EditAlbumPage.strip(editors: false, delete: true)
        #expect(delete.tabs == [.delete] && EditAlbumPage.shown(.release, in: delete.tabs) == .delete)
        let neither = EditAlbumPage.strip(editors: false, delete: false)
        #expect(neither.tabs.isEmpty)
        // the phone's strip and the Mac's tabs are one list
        for (editors, delete) in [(true, true), (true, false), (false, true), (false, false)] {
            #expect(EditAlbumPage.strip(editors: editors, delete: delete).tabs
                    == EditAlbumPage.tabs(editors: editors, delete: delete))
        }
        // the Mac's tabs: every part offered, in the web's order
        #expect(EditAlbumPage.tabs(editors: true, delete: true) == [.release, .tags, .artwork, .lyrics, .delete])
        #expect(EditAlbumPage.tabs(editors: false, delete: true) == [.delete])
        // the tab shown: the chosen while offered, else the first offered
        #expect(EditAlbumPage.shown(.lyrics, in: [.release, .tags, .artwork, .lyrics]) == .lyrics)
        #expect(EditAlbumPage.shown(.lyrics, in: [.delete]) == .delete)
        #expect(EditAlbumPage.shown(.tags, in: []) == .release)
    }

    @Test func revertGoesOnlyWithTypedWorkAndNothingUnderWay() {
        #expect(EditAlbumPage.canRevert(unsaved: true, online: true, writing: false, marking: false, needsRead: false))
        #expect(!EditAlbumPage.canRevert(unsaved: false, online: true, writing: false, marking: false, needsRead: false))
        #expect(!EditAlbumPage.canRevert(unsaved: true, online: false, writing: false, marking: false, needsRead: false))
        #expect(!EditAlbumPage.canRevert(unsaved: true, online: true, writing: true, marking: false, needsRead: false))
        #expect(!EditAlbumPage.canRevert(unsaved: true, online: true, writing: false, marking: true, needsRead: false))
        #expect(!EditAlbumPage.canRevert(unsaved: true, online: true, writing: false, marking: false, needsRead: true))
    }

    @Test func theMacsPageFitsEachWidth() {
        let sidebar = MacLook.sidebarWidth, panel = MacLook.panelWidth
        // the window's opening 1280 less the sidebar's 220: the drawing's 398 list, Artist shown, Release in two columns
        let opening = EditAlbumPage.Layout(page: MacFrame.openingWidth - sidebar)
        #expect(opening.list == MacLook.folderListWidth && opening.list == 398 && opening.artistColumn)
        #expect(opening.editor == 661 && opening.twoColumns && opening.headerBeside)
        // (R10's review) 1280 with the side panel open: 1280 - 220 - 400 and the panel's rule, about 659 - the
        // smallest page there is, smaller than the smallest window's: the narrow list, everything stacked
        let withPanel = EditAlbumPage.Layout(page: MacFrame.openingWidth - sidebar - panel - 1)
        #expect(withPanel.list == 280 && !withPanel.artistColumn && withPanel.editor == 378)
        #expect(!withPanel.twoColumns && !withPanel.headerBeside)
        // the smallest window (880, the page 660): the editor keeps 379, everything stacked
        let smallest = EditAlbumPage.Layout(page: MacFrame.smallestWidth - sidebar)
        #expect(smallest.list == 280 && smallest.editor == 379 && !smallest.twoColumns && !smallest.headerBeside)
        // each boundary, a point either side - so `>=` as `>`, or a constant moved by a point, fails
        // the list: 398 with Artist from a page of 1000
        for (page, wide) in [(999.0, false), (1000.0, true), (1001.0, true)] {
            let layout = EditAlbumPage.Layout(page: page)
            #expect(layout.artistColumn == wide && layout.list == (wide ? 398 : 280), "page \(page)")
        }
        // two columns from an editor of 620 (the narrow list: the page 280 + 1 + 620 = 901)
        for (page, editor, two) in [(900.0, 619.0, false), (901.0, 620.0, true), (902.0, 621.0, true)] {
            let layout = EditAlbumPage.Layout(page: page)
            #expect(layout.editor == editor && layout.twoColumns == two, "page \(page)")
        }
        // ...and with the wide list (the page 398 + 1 + 620 = 1019)
        for (page, two) in [(1018.0, false), (1019.0, true), (1020.0, true)] {
            #expect(EditAlbumPage.Layout(page: page).twoColumns == two, "page \(page)")
        }
        // the header's chip beside its words from an editor of 560 (the page 280 + 1 + 560 = 841)
        for (page, editor, beside) in [(840.0, 559.0, false), (841.0, 560.0, true), (842.0, 561.0, true)] {
            let layout = EditAlbumPage.Layout(page: page)
            #expect(layout.editor == editor && layout.headerBeside == beside && !layout.twoColumns, "page \(page)")
        }
        // never a negative editor
        #expect(EditAlbumPage.Layout(page: 100).editor == 0)
    }

    @Test func theWords() {
        #expect(EditAlbumPage.Words.folders(1) == "1 folder" && EditAlbumPage.Words.folders(1406) == "1,406 folders")
        #expect(EditAlbumPage.Words.needALook(1) == "1 needs a look" && EditAlbumPage.Words.needALook(3) == "3 need a look")
        #expect(EditAlbumPage.Words.issues(1) == "1 issue to look at" && EditAlbumPage.Words.issues(2) == "2 issues to look at")
        #expect(EditAlbumPage.Words.folderRow(albums[1]) == "Back in Black, AC/DC, 2003, 2 issues to look at")
        #expect(EditAlbumPage.Words.folderRow(fresh[0]) == "The Ideal Crash, dEUS, 1999, Newly added")
        #expect(EditAlbumPage.Words.folderRow(albums[2]) == "Arrival, ABBA, 1976")
        #expect(EditAlbumPage.Words.folderRow(ScanAlbum(path: "A/B")) == "A/B")
        #expect(EditAlbumPage.Words.mark(.issues(1)) == "1 issue to look at" && EditAlbumPage.Words.mark(nil).isEmpty)
        // (R11) the Mac's foot under each tab - Delete's its summary's, drawn by the foot
        #expect(EditAlbumPage.Words.foot(.release) == "Apply writes the tags and files the folder. There is no undo.")
        #expect(EditAlbumPage.Words.foot(.tags) == "A field left as it is isn\u{2019}t written.")
        #expect(EditAlbumPage.Words.foot(.artwork) == "Pictures are saved into the album folder.")
        #expect(EditAlbumPage.Words.foot(.lyrics) == "Lyrics come from LRCLIB, one .lrc beside each track.")
        #expect(EditAlbumPage.Words.foot(.delete).isEmpty)
    }

    // MARK: Tags (R11)

    private let files = ["01 Hells Bells.flac", "02 Shoot to Thrill.flac", "03 What Do You Do for Money Honey.flac",
                         "04 Givin the Dog a Bone.flac"]

    @Test func onlyTheTickedRowsAreEdited() {
        // none ticked: every track, in running order
        #expect(EditAlbumPage.tagTargets(files, ticked: []) == files)
        #expect(EditAlbumPage.ticked(files, []) == 0)
        // three ticked, out of order: those three, in running order - and counted three, not four
        let three: Set<String> = [files[3], files[0], files[2]]
        #expect(EditAlbumPage.tagTargets(files, ticked: three) == [files[0], files[2], files[3]])
        #expect(EditAlbumPage.ticked(files, three) == 3)
        #expect(!EditAlbumPage.allTicked(files, three))
        // one ticked: one
        #expect(EditAlbumPage.tagTargets(files, ticked: [files[1]]) == [files[1]])
        #expect(EditAlbumPage.ticked(files, [files[1]]) == 1)
        // a tick left on a file gone since (a release renames them) is no track: never counted, never edited
        let gone: Set<String> = [files[1], "02 Shoot To Thrill (old name).flac"]
        #expect(EditAlbumPage.ticked(files, gone) == 1)
        #expect(EditAlbumPage.tagTargets(files, ticked: gone) == [files[1]])
        #expect(EditAlbumPage.tagTargets(files, ticked: ["gone.flac"]) == files, "only gone ticks: every track")
        #expect(EditAlbumPage.ticked(files, ["gone.flac"]) == 0)
        // every track ticked: Deselect all
        #expect(EditAlbumPage.allTicked(files, Set(files)))
        #expect(EditAlbumPage.allTicked(files, Set(files + ["gone.flac"])))
        #expect(!EditAlbumPage.allTicked([], []))
    }

    /// (R11's review) Select all ticks every track; once every track is ticked it is Deselect all, and ticks none.
    @Test func selectAllAndDeselectAll() {
        #expect(EditAlbumPage.selectAll(files, []) == Set(files))
        #expect(EditAlbumPage.selectAll(files, [files[1]]) == Set(files))
        #expect(EditAlbumPage.selectAll(files, Set(files)) == [], "every track ticked: Deselect all ticks none")
        #expect(EditAlbumPage.selectAll(files, Set(files + ["gone.flac"])) == [])
        #expect(EditAlbumPage.selectAll([], []) == [])
        // twice is back where it began
        #expect(EditAlbumPage.selectAll(files, EditAlbumPage.selectAll(files, [])) == [])
    }

    /// (R11's review) A tick over typed work for another set of tracks asks "Discard changes?" first; the same tracks,
    /// or nothing typed, never.
    @Test func aTickOverTypedWorkAsksFirst() {
        let two = [files[0], files[2]]
        #expect(EditAlbumPage.asksFirst(files, ticked: [files[0]], editing: two, typed: true))
        #expect(!EditAlbumPage.asksFirst(files, ticked: [files[0]], editing: two, typed: false))
        #expect(!EditAlbumPage.asksFirst(files, ticked: Set(two), editing: two, typed: true), "the same tracks")
        // none ticked is every track: editing every track already, nothing to ask
        #expect(!EditAlbumPage.asksFirst(files, ticked: [], editing: files, typed: true))
        #expect(EditAlbumPage.asksFirst(files, ticked: [], editing: two, typed: true))
        // Edit this track…: only that one
        #expect(EditAlbumPage.asksFirst(files, ticked: [files[3]], editing: files, typed: true))
        #expect(!EditAlbumPage.asksFirst(files, ticked: [files[3]], editing: [files[3]], typed: true))
    }

    /// (R11's review) After a read: nothing typed, the editor takes the ticks; typed over, a release's renames tick the
    /// tracks still edited (Apply then says what it writes to); none of them left, stranded - never put away unasked.
    @Test func theEditorFollowsAReadWithoutLosingTypedWork() {
        // as it was: the same tracks
        #expect(EditAlbumPage.afterRead(files, ticked: [], editing: files, typed: true) == .keep)
        #expect(EditAlbumPage.afterRead(files, ticked: [files[1]], editing: [files[1]], typed: false) == .keep)
        #expect(EditAlbumPage.afterRead([], ticked: [], editing: [], typed: true) == .keep, "nothing read yet")
        // the first read, nothing typed: every track
        #expect(EditAlbumPage.afterRead(files, ticked: [], editing: [], typed: false) == .edit(files))
        // a rename under no typed work: the editor takes the ticks as they are
        let renamed = [files[0], files[1], files[2], "04 Givin' the Dog a Bone.flac"]
        #expect(EditAlbumPage.afterRead(renamed, ticked: [], editing: Array(files.prefix(3)), typed: false)
                == .edit(renamed))
        // every track edited, one renamed, typed over: the three still there ticked - "Apply to 3 tracks", and Apply
        // writes to those three, never "all 4" over three
        let three = Array(files.prefix(3))
        guard case .tick(let ticks) = EditAlbumPage.afterRead(renamed, ticked: [], editing: three, typed: true) else {
            Issue.record("a partial rename under typed work ticks the tracks still edited")
            return
        }
        #expect(ticks == Set(three))
        #expect(EditAlbumPage.tagTargets(renamed, ticked: ticks) == three, "the targets are the tracks edited")
        #expect(EditAlbumPage.ticked(renamed, ticks) == 3)
        #expect(EditAlbumPage.afterRead(renamed, ticked: ticks, editing: three, typed: true) == .keep, "and it settles")
        // every track edited renamed, typed over: stranded
        let moved = ["1 Hells Bells.flac", "2 Shoot to Thrill.flac", "3 Money Honey.flac", "4 Dog a Bone.flac"]
        #expect(EditAlbumPage.afterRead(moved, ticked: [], editing: [], typed: true) == .stranded)
        // stranded, the typed work put back: the editor takes the ticks again
        #expect(EditAlbumPage.afterRead(moved, ticked: [], editing: [], typed: false) == .edit(moved))
    }

    @Test func tagsWords() {
        // the counts the buttons say are the ticked rows'
        #expect(TagEditWords.editTracks(EditAlbumPage.ticked(files, [files[0], files[2], files[3]])) == "Edit 3 tracks\u{2026}")
        #expect(TagEditWords.editTracks(EditAlbumPage.ticked(files, [])) == "Edit all tracks\u{2026}")
        #expect(EditAlbumPage.Words.editLegend(3) == "Edit 3 tracks" && EditAlbumPage.Words.editLegend(1) == "Edit 1 track")
        #expect(EditAlbumPage.Words.editLegend(0) == "Edit all tracks")
        #expect(EditAlbumPage.Words.applyTo(ticked: 3, of: 10) == "Apply to 3 tracks")
        #expect(EditAlbumPage.Words.applyTo(ticked: 1, of: 10) == "Apply to 1 track")
        #expect(EditAlbumPage.Words.applyTo(ticked: 0, of: 10) == "Apply to all 10 tracks")
        #expect(EditAlbumPage.Words.applyTo(ticked: 0, of: 1) == "Apply to all 1 track")
        #expect(EditAlbumPage.Words.applyTo(ticked: 0, of: 1406) == "Apply to all 1,406 tracks")
        // the app's verb, never the drawings' Tick
        for device in Device.allCases {
            #expect(EditAlbumPage.Words.tagsNote(device).hasPrefix("Select tracks to edit only those."))
            #expect(!EditAlbumPage.Words.tagsNote(device).contains("Tick"))
        }
        #expect(EditAlbumPage.Words.tagsNote(.iPhone).hasSuffix("Tap \u{203a} to see everything in a track's file."))
        #expect(EditAlbumPage.Words.selectAll == "Select all" && EditAlbumPage.Words.deselectAll == "Deselect all")
        #expect(EditAlbumPage.Words.seeEveryTag == "See a file's every tag\u{2026}")
        // (R11's review) a ticked row says so once, a checkbox's word: "selected" is VoiceOver's own, for the row the
        // list has selected
        #expect(EditAlbumPage.Words.tagRow("Track 3, Shoot to Thrill", length: "5:17", ticked: true)
                == "Track 3, Shoot to Thrill, 5:17, checked")
        #expect(EditAlbumPage.Words.tagRow("Track 3, Shoot to Thrill", length: "5:17", ticked: false)
                == "Track 3, Shoot to Thrill, 5:17")
        for ticked in [true, false] {
            #expect(!EditAlbumPage.Words.tagRow("Track 3, Shoot to Thrill", length: "5:17", ticked: ticked)
                .lowercased().contains("select"))
        }
        #expect(EditAlbumPage.Words.compareWithPressing == "Compare with this pressing\u{2026}")
    }

    // MARK: Artwork, Lyrics, Delete (R11)

    @Test func artworkAndLyricsWords() {
        #expect(EditAlbumPage.Words.seeFullSize(.iPhone) == "Tap the cover to see it full size.")
        #expect(EditAlbumPage.Words.seeFullSize(.mac) == "Click the cover to see it full size.")
        #expect(EditAlbumPage.Words.nothingReplaced == "Nothing saved is replaced.")
        // the pointers say the Release tab, on both devices now: it is a tab of each
        let unmatched = ScanAlbum(path: "A/B", art: "file")
        #expect(GetResults.webCoverPointer(unmatched)?.contains("in the Release tab") == true)
        #expect(GetResults.webDiscArtPointer(unmatched)?.contains("in the Release tab") == true)
        // (R11's review) the button Release shows named only while it shows it: the phone's Compare, the Mac's Compare
        // full size… - with none shown, the words alone
        let tagged = ScanAlbum(path: "A", releaseMbid: "x", art: "file")
        #expect(EditAlbumPage.coverPointer(tagged, compare: EditAlbumPage.Words.compare)
                == "To replace it, compare it with the release's in the Release tab (Compare).")
        #expect(EditAlbumPage.coverPointer(tagged, compare: EditAlbumPage.Words.compareFullSize)
                == GetResults.webCoverPointer(tagged))
        #expect(GetResults.webCoverPointer(tagged)
                == "To replace it, compare it with the release's in the Release tab (Compare full size\u{2026}).")
        #expect(EditAlbumPage.coverPointer(tagged, compare: nil)
                == "To replace it, compare it with the release's in the Release tab.")
        for compare in [EditAlbumPage.Words.compare, nil] {
            #expect(EditAlbumPage.coverPointer(unmatched, compare: compare) == GetResults.webCoverPointer(unmatched))
            #expect(EditAlbumPage.coverPointer(ScanAlbum(path: "A", releaseMbid: "x"), compare: compare) == nil)
        }
        #expect(EditAlbumPage.coverPointer(tagged, compare: nil)?.contains("Compare") == false)
    }

    @Test func whatADeleteTakesIsSaidInRows() {
        let summary = DeletionSummary(audioFiles: 12, totalBytes: 314_572_800, otherFiles: ["rip.log", "album.cue"],
                                      otherFileCount: 2, holders: ["ana"], yours: true)
        #expect(EditAlbumPage.deleteTracks(summary) == "12 \u{b7} 300 MB")
        #expect(EditAlbumPage.deleteTracks(DeletionSummary(audioFiles: 3)) == "3", "no size for nothing")
        // (R11's review) what else goes, in deadwax's words on both devices: the lead counts every file, the names
        // are the twelve the summary lists - the drawing's "10 .lrc" never said how many
        #expect(DeleteWords.others(summary)?.lead == "and 2 other files:")
        #expect(DeleteWords.others(summary)?.names == "rip.log, album.cue")
        let twelve = (1...12).map { (n: Int) -> String in "\(n).lrc" }
        let many = DeletionSummary(audioFiles: 10, otherFiles: twelve, otherFileCount: 40)
        #expect(many.otherFileCount > many.otherFiles.count)
        #expect(DeleteWords.others(many)?.lead == "and 40 other files:")
        #expect(DeleteWords.others(many)?.names == twelve.joined(separator: ", ") + ", \u{2026}")
        #expect(DeleteWords.others(DeletionSummary(audioFiles: 2)) == nil)
        #expect(DeleteWords.counts(summary) == "12 tracks \u{b7} 300 MB")
        // the Mac's foot, short - the whole sentence is the tab's row
        #expect(EditAlbumPage.deleteFoot(summary) == "In a library: Yours and ana's")
        #expect(EditAlbumPage.deleteFoot(DeletionSummary(audioFiles: 1, holders: [], yours: false))
                == "In a library: Nobody's")
        #expect(EditAlbumPage.deleteFoot(DeletionSummary(audioFiles: 1)) == "", "logins off: nothing")
        #expect(EditAlbumPage.deleteFoot(nil) == "")
        #expect(DeleteWords.holders(summary)?.hasPrefix("In your library and ana's: deleting it takes it out") == true)
        // who holds it, short - unread is said as unread, never as nobody's; logins off, nothing
        #expect(EditAlbumPage.held(summary) == "Yours and ana's")
        #expect(EditAlbumPage.held(DeletionSummary(audioFiles: 1, holders: [], yours: true)) == "Yours only")
        #expect(EditAlbumPage.held(DeletionSummary(audioFiles: 1, holders: [], yours: false)) == "Nobody's")
        #expect(EditAlbumPage.held(DeletionSummary(audioFiles: 1, holders: ["ana", "bo"], yours: false)) == "ana's and bo's")
        #expect(EditAlbumPage.held(DeletionSummary(audioFiles: 1, holders: ["ana", "bo"], yours: true))
                == "Yours, ana's and bo's")
        #expect(EditAlbumPage.held(DeletionSummary(audioFiles: 1, holdersUnknown: true)) == "Couldn't tell")
        #expect(EditAlbumPage.held(DeletionSummary(audioFiles: 1)) == nil)
        #expect(EditAlbumPage.held(nil) == nil)
    }

    /// (R11's review) A delete from a folder opening closes the album's pages by the album the folder holds: by the
    /// release the page knew, by its name for an untagged folder, by the id bridge's album for the folder's release -
    /// gone when the folder was all of it, asked again when folders are left; a page of another album untouched.
    @Test func aFolderDeleteClosesTheAlbumsPagesByWhatTheFolderHolds() {
        let tagged = ScanAlbum(path: "AC_DC/Back in Black (1980)", artist: "AC/DC", album: "Back in Black",
                               releaseMbid: "a4f2c0de", trackCount: 10)
        let untagged = ScanAlbum(path: "Abba/Arrival (1976)", artist: "ABBA", album: "Arrival", trackCount: 10)
        let other = ScanAlbum(path: "Sigur Rós/( ) (2002)", artist: "Sigur Rós", album: "( )", trackCount: 8)
        let scan = [tagged, untagged, other]
        let sigur = AlbumEdit.Subject(id: "nd-sigur", name: "( )", artist: "Sigur Rós")
        // untagged: the page opened by its name and artist goes - the folder was all of it; another album's stays
        let arrival = AlbumEdit.Subject(id: "nd-arrival", name: "Arrival", artist: "ABBA")
        #expect(EditAlbumPage.folderPages(untagged.path, tracks: 10, bridge: nil, scan: scan, pages: [arrival, sigur])
                == EditAlbumPage.FolderPages(leave: ["nd-arrival"]))
        // tagged, the page opened knowing its release: found by it
        let known = AlbumEdit.Subject(id: "nd-bib", name: "Back in Black", artist: "AC/DC", musicBrainzId: "a4f2c0de")
        #expect(EditAlbumPage.folderPages(tagged.path, tracks: 10, bridge: nil, scan: scan, pages: [known])
                == EditAlbumPage.FolderPages(leave: ["nd-bib"]))
        // tagged, the page opened without it (a tagged folder is never found by name): the id bridge names it
        let unknown = AlbumEdit.Subject(id: "nd-bib", name: "Back in Black", artist: "AC/DC")
        #expect(EditAlbumPage.folderPages(tagged.path, tracks: 10, bridge: nil, scan: scan, pages: [unknown])
                == EditAlbumPage.FolderPages())
        let bridge = StoreAlbum(releaseMbid: "a4f2c0de", navidromeId: "nd-bib",
                                present: [StoreRow(id: 1, path: tagged.path)])
        #expect(EditAlbumPage.folderPages(tagged.path, tracks: 10, bridge: bridge, scan: scan, pages: [unknown, sigur])
                == EditAlbumPage.FolderPages(leave: ["nd-bib"]))
        // one folder of two (a set kept a folder per disc): asked again, not gone - each page once
        let disc2 = ScanAlbum(path: "AC_DC/Back in Black (1980)/Disc 2", artist: "AC/DC", album: "Back in Black",
                              releaseMbid: "a4f2c0de", trackCount: 4)
        let two = StoreAlbum(releaseMbid: "a4f2c0de", navidromeId: "nd-bib",
                             present: [StoreRow(id: 1, path: tagged.path), StoreRow(id: 2, path: disc2.path)])
        #expect(EditAlbumPage.folderPages(tagged.path, tracks: 10, bridge: two, scan: scan + [disc2],
                                          pages: [unknown, unknown, known])
                == EditAlbumPage.FolderPages(ask: ["nd-bib"]))
        #expect(EditAlbumPage.folderPages(tagged.path, tracks: 10, bridge: nil, scan: scan + [disc2], pages: [known])
                == EditAlbumPage.FolderPages(ask: ["nd-bib"]))
        // the bridge's album for another page's id names nothing of this one
        #expect(EditAlbumPage.folderPages(tagged.path, tracks: 10, bridge: bridge, scan: scan, pages: [arrival])
                == EditAlbumPage.FolderPages())
        // nothing open: nothing to close
        #expect(EditAlbumPage.folderPages(untagged.path, tracks: 10, bridge: nil, scan: scan, pages: [])
                == EditAlbumPage.FolderPages())
        // what the bridge is asked by: the folder's release, trimmed - none for an untagged folder
        #expect(EditAlbumPage.bridgeRelease(tagged) == "a4f2c0de")
        #expect(EditAlbumPage.bridgeRelease(ScanAlbum(path: "A", releaseMbid: "  b1 ")) == "b1")
        #expect(EditAlbumPage.bridgeRelease(untagged) == nil)
        #expect(EditAlbumPage.bridgeRelease(ScanAlbum(path: "A", releaseMbid: "  ")) == nil)
    }
}
