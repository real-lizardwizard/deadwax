import Foundation
import Testing
@testable import DeadwaxCore

/// Needs a look as the redesign draws it (slice R12 - notes/ios.md "The redesign, slice R12: Needs a look"): Marked fine
/// a button of its own beside the strip, the counts the same rule as the sidebar's, a row's chips by meaning, a row
/// picked during a session, and Apply moving on.
@Suite struct NeedsLookPageTests {
    static func album(_ path: String, issues: [String] = [], ignored: [String] = [], imported: Bool = false,
                      artist: String = "Tame Impala", name: String = "Currents", severity: Int = 0) -> ScanAlbum {
        NeedsLookTests.album(path, issues: issues, ignored: ignored, imported: imported, severity: severity,
                             artist: artist, name: name)
    }

    /// Six albums: Beach House new, ABBA with two issues, Tame Impala with one, Nobody's two with every issue marked
    /// fine - and (R12's review) Mixed/Half with one of its two marked fine and one outstanding: in the queue, never
    /// Marked fine's, and last in it (no severity).
    static let albums = [
        album("Tame Impala/Currents", issues: ["no_art"], severity: 1),
        album("Beach House/Bloom", imported: true, artist: "Beach House", name: "Bloom"),
        album("ABBA/Arrival", issues: ["no_release", "no_year"], artist: "ABBA", name: "Arrival", severity: 3),
        album("Nobody/Quiet", issues: ["no_art"], ignored: ["no_art"], artist: "Nobody", name: "Quiet"),
        album("Nobody/Loud", issues: ["no_year"], ignored: ["no_year"], artist: "Nobody", name: "Loud"),
        album("Mixed/Half", issues: ["no_art", "no_year"], ignored: ["no_art"], artist: "Mixed", name: "Half"),
    ]

    @Test func theStripAndTheBadgeCountTheSameAlbums() {
        let facets = NeedsLook.facets(Self.albums, [:])
        let all = facets.first
        // All's count is summaryTotal's - the sidebar's and Settings' count over the same scan - and Marked fine is
        // never in it
        #expect(all?.id == nil && all?.count == NeedsLook.summaryTotal(Self.albums) && all?.count == 4)
        // (R12's review) Mixed/Half, with an issue marked fine and one outstanding, needs a look - it is not marked fine
        #expect(NeedsLookPage.status(Self.albums) == ["4 need a look", "2 marked fine"])
        #expect(NeedsLookPage.status([Self.albums[5]]) == ["1 needs a look"], "an issue marked fine, one outstanding")
        #expect(NeedsLookPage.status(Array(Self.albums.prefix(3))) == ["3 need a look"], "no marked fine, none said")
        // the strip: every facet but Marked fine, which is the button's
        let strip = NeedsLookPage.strip(facets)
        #expect(strip == facets.filter { $0.id != NeedsLook.ignoredFacet } && strip.count == facets.count - 1)
        #expect(!strip.contains { NeedsLookPage.isMarkedFine($0.id) } && strip.first?.id == nil)
        let fine = NeedsLookPage.markedFine(facets)
        #expect(fine?.count == 2 && NeedsLookPage.markedFineWords(fine?.count ?? 0) == "Marked fine \u{b7} 2")
        #expect(NeedsLookPage.markedFine(NeedsLook.facets(Array(Self.albums.prefix(3)), [:])) == nil)
        // the button: Marked fine shown, then All again
        #expect(NeedsLookPage.markedFineTapped(nil) == NeedsLook.ignoredFacet)
        #expect(NeedsLookPage.markedFineTapped("no_art") == NeedsLook.ignoredFacet)
        #expect(NeedsLookPage.markedFineTapped(NeedsLook.ignoredFacet) == nil)
        // the Mac's pop-up
        #expect(NeedsLookPage.popUp(NeedsLook.Facet(id: nil, label: "All", count: 3)) == "Every issue \u{b7} 3 albums")
        #expect(NeedsLookPage.popUp(NeedsLook.Facet(id: "no_art", label: "No cover art", count: 1))
                == "No cover art \u{b7} 1 album")
        #expect(NeedsLookPage.popUpSpoken(NeedsLook.Facet(id: nil, label: "All", count: 3)) == "Show, Every issue, 3 albums")
        #expect(NeedsLookPage.popUpSpoken(nil) == "Show")
    }

    @Test func aRowsChipsSayWhatEachIs() {
        let types: [String: MetadataIssueType] = [:]
        let abba = NeedsLook.DrawnRow(key: "ABBA/Arrival", album: Self.albums[2], mark: nil)
        let kinds = NeedsLookPage.chips(abba, pressed: nil, issueTypes: types).map(\.kind)
        #expect(kinds == [.issue, .issue] && NeedsLookPage.issueCount(abba) == 2)
        let fresh = NeedsLook.DrawnRow(key: "Beach House/Bloom", album: Self.albums[1], mark: nil)
        #expect(NeedsLookPage.chips(fresh, pressed: nil, issueTypes: types).map(\.kind) == [.new])
        #expect(NeedsLookPage.issueCount(fresh) == 0)
        // a new import with an issue: New first, then the issue
        let both = NeedsLook.DrawnRow(key: "X/Y", album: Self.album("X/Y", issues: ["no_art"], imported: true), mark: nil)
        #expect(NeedsLookPage.chips(both, pressed: nil, issueTypes: types).map(\.kind) == [.new, .issue])
        // under Marked fine, an album marked fine says so
        let quiet = NeedsLook.DrawnRow(key: "Nobody/Quiet", album: Self.albums[3], mark: nil)
        let under = NeedsLookPage.chips(quiet, pressed: NeedsLook.ignoredFacet, issueTypes: types)
        #expect(under.map(\.words) == ["Marked fine"] && under.map(\.kind) == [.markedFine])
        // in a session, what became of it - and no count beside it
        for (mark, kind) in [(NeedsLook.RowMark.fixed, NeedsLookPage.ChipKind.fixed), (.ignored, .markedFine),
                             (.deleted, .deleted)] {
            let row = NeedsLook.DrawnRow(key: "ABBA/Arrival", album: Self.albums[2], mark: mark)
            let chips = NeedsLookPage.chips(row, pressed: nil, issueTypes: types)
            #expect(chips.map(\.words) == [mark.words] && chips.map(\.kind) == [kind])
            #expect(NeedsLookPage.issueCount(row) == 0)
        }
    }

    @Test func theMacsRowFoldsItsChipsAndSaysThemWhole() {
        #expect(NeedsLookPage.more(3, shown: 1) == "+2" && NeedsLookPage.more(1, shown: 1) == nil)
        #expect(NeedsLookPage.more(0, shown: 1) == nil)
        let abba = NeedsLook.DrawnRow(key: "ABBA/Arrival", album: Self.albums[2], mark: nil)
        #expect(NeedsLookPage.help(abba, chips: ["No release id", "No original year"])
                == "ABBA/Arrival\nNo release id \u{b7} No original year")
        #expect(NeedsLookPage.help(abba, chips: []) == "ABBA/Arrival")
        #expect(NeedsLookPage.macLeaves.hasSuffix("an album leaves once its issues are fixed or marked fine."))
        #expect(NeedsLookPage.back == "\u{2039}" && NeedsLookWords.skip.hasSuffix("\u{203A}"))
    }

    @Test func aRowPickedDuringASessionIsAStepToIt() throws {
        let list = NeedsLook.facetAlbums(Self.albums, nil)
        #expect(list.map(\.path) == ["Beach House/Bloom", "ABBA/Arrival", "Tame Impala/Currents", "Mixed/Half"])
        var session = try #require(NeedsLook.startSession(list, path: "ABBA/Arrival", facet: nil))
        #expect(NeedsLookPage.step(to: "Tame Impala/Currents", in: session) == 1)
        #expect(NeedsLookPage.step(to: "Beach House/Bloom", in: session) == -1)
        // (R12's review) a row further off is a step of more than one - all the way, never one at a time
        #expect(NeedsLookPage.step(to: "Mixed/Half", in: session) == 2)
        let first = try #require(NeedsLook.startSession(list, path: "Beach House/Bloom", facet: nil))
        #expect(NeedsLookPage.step(to: "Mixed/Half", in: first) == 3)
        let last = try #require(NeedsLook.startSession(list, path: "Mixed/Half", facet: nil))
        #expect(NeedsLookPage.step(to: "Beach House/Bloom", in: last) == -3)
        #expect(NeedsLookPage.step(to: "ABBA/Arrival", in: session) == 0, "the album open: no step")
        #expect(NeedsLookPage.step(to: "Nobody/Quiet", in: session) == 0, "not a row of the session")
        // a row renamed by an apply is still found by the key it was listed at
        session = NeedsLook.rowChanged(session, .init(from: "Tame Impala/Currents",
                                                      album: Self.album("Tame Impala/Currents (2015)")))
        #expect(NeedsLookPage.step(to: "Tame Impala/Currents", in: session) == 1)
        #expect(NeedsLookPage.step(to: "Tame Impala/Currents (2015)", in: session) == 0)
    }

    @Test func applyMovesOnToTheNextAlbumButTheLast() throws {
        let list = NeedsLook.facetAlbums(Self.albums, nil)
        let first = try #require(NeedsLook.startSession(list, path: "Beach House/Bloom", facet: nil))
        let last = try #require(NeedsLook.startSession(list, path: "Mixed/Half", facet: nil))
        #expect(NeedsLookPage.movesOn(NeedsLook.Nav(first), applied: true))
        #expect(!NeedsLookPage.movesOn(NeedsLook.Nav(first), applied: false), "nothing applied: Apply")
        #expect(!NeedsLookPage.movesOn(NeedsLook.Nav(last), applied: true), "the last keeps Apply")
        #expect(!NeedsLookPage.movesOn(nil, applied: true), "not in queue mode")
    }

    @Test func itsFineMarksOnlyTheAlbumItIsFor() throws {
        // a mark told of one album changes that album's row alone - every other row as it was
        let list = NeedsLook.facetAlbums(Self.albums, nil)
        let session = try #require(NeedsLook.startSession(list, path: "ABBA/Arrival", facet: nil))
        let fine = Self.album("ABBA/Arrival", issues: ["no_release", "no_year"], ignored: ["no_release", "no_year"],
                              artist: "ABBA", name: "Arrival")
        let after = NeedsLook.rowChanged(session, .init(from: "ABBA/Arrival", album: fine))
        #expect(after.rows.map(\.mark) == [nil, .ignored, nil, nil])
        #expect(after.rows[0] == session.rows[0] && after.rows[2] == session.rows[2] && after.rows[3] == session.rows[3])
        // and the album leaves the queue for Marked fine once the list is read again
        let read = Self.albums.map { $0.path == "ABBA/Arrival" ? fine : $0 }
        #expect(NeedsLook.summaryTotal(read) == 3 && NeedsLookPage.markedFine(NeedsLook.facets(read, [:]))?.count == 3)
        #expect(NeedsLookPage.status(read) == ["3 need a look", "3 marked fine"])
    }

    // MARK: (R12's review)

    /// Every count the window shows reads the scan as it is now (the decision: "The tab badge and the queue never count
    /// different things"): after It's fine on one album in a session, the status bar, the pop-up's counts and Marked
    /// fine · N say one number each - the facets the session began with, its albums still its own.
    @Test func afterItsFineTheStatusBarThePopUpAndMarkedFineAgree() throws {
        var run = NeedsLook.Run()
        let list = NeedsLook.facetAlbums(Self.albums, nil)
        let begun = run.begin(list, path: "ABBA/Arrival", facet: nil, live: NeedsLook.facets(Self.albums, [:]))
        #expect(begun)
        let fine = Self.album("ABBA/Arrival", issues: ["no_release", "no_year"], ignored: ["no_release", "no_year"],
                              artist: "ABBA", name: "Arrival", severity: 3)
        run.heard(.init(from: "ABBA/Arrival", album: fine))
        let read = Self.albums.map { $0.path == "ABBA/Arrival" ? fine : $0 }
        let live = NeedsLook.facets(read, [:])
        let session = try #require(run.session)
        let held = NeedsLook.chips(session: session, held: run.held, ending: nil, live: live)
        #expect(held.first?.count == 4 && NeedsLookPage.markedFine(held)?.count == 2, "held as the session began")
        let drawn = NeedsLookPage.counted(held, live: live, pressed: session.facet)
        let all = try #require(NeedsLook.chip(drawn, pressed: nil))
        let marked = try #require(NeedsLookPage.markedFine(drawn))
        // the status bar, the pop-up and Marked fine · N: one number each
        #expect(NeedsLookPage.status(read) == [EditAlbumPage.Words.needALook(all.count), "\(marked.count) marked fine"])
        #expect(all.count == 3 && marked.count == 3 && all.count == NeedsLook.summaryTotal(read))
        #expect(NeedsLookPage.popUp(all) == "Every issue \u{b7} 3 albums")
        #expect(NeedsLookPage.markedFineWords(marked.count) == "Marked fine \u{b7} 3")
        // every facet drawn counted live; the strip and the pop-up its facets but Marked fine
        for chip in drawn {
            #expect(chip.count == (NeedsLook.chip(live, pressed: chip.id)?.count ?? 0), "\(chip.label)")
        }
        #expect(NeedsLookPage.strip(drawn).allSatisfy { !NeedsLookPage.isMarkedFine($0.id) })
        // the session's albums stay its own: every row, ABBA's saying Marked fine
        #expect(session.rows.count == 4 && session.rows.map(\.mark) == [nil, .ignored, nil, nil])
    }

    /// Which facets are drawn: the session's - a live one it lacks joining them (Marked fine, once It's fine took an
    /// album there, last), one emptied since gone unless it is the one pressed.
    @Test func theFacetsDrawnAreTheSessionsCountedLive() {
        let three = Array(Self.albums.prefix(3))
        let held = NeedsLook.facets(three, [:])
        #expect(NeedsLookPage.markedFine(held) == nil, "nothing marked fine as the session began")
        let fine = Self.album("ABBA/Arrival", issues: ["no_release", "no_year"], ignored: ["no_release", "no_year"],
                              artist: "ABBA", name: "Arrival", severity: 3)
        let live = NeedsLook.facets(three.map { $0.path == "ABBA/Arrival" ? fine : $0 }, [:])
        let drawn = NeedsLookPage.counted(held, live: live, pressed: nil)
        #expect(drawn.map(\.id) == [nil, NeedsLook.newFacet, "no_art", NeedsLook.ignoredFacet])
        #expect(drawn.map(\.count) == [2, 1, 1, 1])
        // the session's own facet, emptied: still drawn while pressed, at its count now
        let pressed = NeedsLookPage.counted(held, live: live, pressed: "no_release")
        #expect(pressed.first?.id == nil && pressed.last?.id == NeedsLook.ignoredFacet && pressed.count == 5)
        #expect(Set(pressed.compactMap(\.id)) == [NeedsLook.newFacet, "no_release", "no_art", NeedsLook.ignoredFacet])
        #expect(NeedsLook.chip(pressed, pressed: "no_release")?.count == 0)
        // no session: the live facets as the web draws them
        #expect(NeedsLookPage.counted(live, live: live, pressed: nil) == NeedsLook.drawn(live))
    }

    /// ⌘R (and the phone's pull) is held as Try again and a sign-in again are: never while a read is out, nor while a
    /// session lasts - the editor beside the queue reads this same scan (ScanReadsTests drive both).
    @Test func aPullIsHeldWhileAReadIsOutOrASessionLasts() {
        #expect(NeedsLookPage.pullReads(online: true, samePerson: true, allowed: true, session: false, reading: false))
        #expect(!NeedsLookPage.pullReads(online: true, samePerson: true, allowed: true, session: true, reading: false))
        #expect(!NeedsLookPage.pullReads(online: true, samePerson: true, allowed: true, session: false, reading: true))
        #expect(!NeedsLookPage.pullReads(online: false, samePerson: true, allowed: true, session: false, reading: false))
        #expect(!NeedsLookPage.pullReads(online: true, samePerson: false, allowed: true, session: false, reading: false))
        #expect(!NeedsLookPage.pullReads(online: true, samePerson: true, allowed: false, session: false, reading: false))
    }

    /// It's fine as it is in the Mac's foot needs Edit albums and Look after the library, as the phone's Release tab has
    /// it - every set of permissions, and the Look-after-the-library-only person offered none.
    @Test func itsFineNeedsEditAlbumsToo() {
        let every = Access.Permission.allCases
        for mask in 0..<(1 << every.count) {
            let given = Set(every.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            let phone = Managing.albumEdit(given).editors && AlbumEdit.marksFine(given)
            #expect(NeedsLookPage.offersFine(given) == phone, "\(given)")
            #expect(NeedsLookPage.offersFine(given) == (given.contains(.edit) && given.contains(.library)), "\(given)")
        }
        #expect(!NeedsLookPage.offersFine([.library]), "Look after the library alone: Delete's tab, no It's fine")
        #expect(!NeedsLookPage.offersFine([.edit]), "Edit albums alone: no route to mark it")
        #expect(NeedsLookPage.offersFine([.edit, .library]))
    }
}
