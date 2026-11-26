import Foundation
import Testing
@testable import DeadwaxCore

/// Edit album redrawn (notes/ios.md "The redesign, slice R10: Edit album, the folder list and Release"): the Mac's folder
/// list and its switch, the header's chip, the strip's and the tabs' parts by permission, Revert's gate, and the Mac's
/// page at each width. tests/test_ios_edit_look.py holds where the app draws each.
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
        // Edit albums and Look after the library: Release drawn on the root, the rest pushed as the rows pushed them
        let both = EditAlbumPage.strip(editors: true, delete: true)
        #expect(both.tabs == [.release] && both.pushes == [.tags, .artwork, .lyrics, .delete])
        // Edit albums alone: no Delete
        let editors = EditAlbumPage.strip(editors: true, delete: false)
        #expect(editors.tabs == [.release] && editors.pushes == [.tags, .artwork, .lyrics])
        // Look after the library alone: Delete only, as the root had Delete album… alone
        let delete = EditAlbumPage.strip(editors: false, delete: true)
        #expect(delete.tabs.isEmpty && delete.pushes == [.delete])
        let neither = EditAlbumPage.strip(editors: false, delete: false)
        #expect(neither.tabs.isEmpty && neither.pushes.isEmpty)
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
        #expect(EditAlbumPage.Words.openPart(.tags) == "Open Tags…")
    }
}
