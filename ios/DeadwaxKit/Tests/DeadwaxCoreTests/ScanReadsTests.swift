import Foundation
import Testing
@testable import DeadwaxCore

/// The library scan's reads, shared (R12's review - notes/ios.md "The redesign, slice R12: Needs a look", "After
/// review"): Needs a look's page and its editor read one scan, and ⌘R beside the editor - mid-read, or just after a row
/// was picked - must never leave the editor waiting on a read that came to nothing. Each test drives the reads as the app
/// makes them: the session (NeedsLook.Run), the page's ⌘R (NeedsLookPage.pullReads), the editor's look-up
/// (ScanReads.answer, as LibraryScanModel.readShared calls it) and the page's read (LibraryScanModel.read), over a
/// network whose every answer the test gives.
@MainActor
@Suite struct ScanReadsTests {
    /// The network under the reads: each ticket's request held until the test answers it.
    @MainActor final class Wire {
        private(set) var asked: [Int: CheckedContinuation<ScanRead, Never>] = [:]

        func ask(_ ticket: Int) async -> ScanRead {
            await withCheckedContinuation { (wait: CheckedContinuation<ScanRead, Never>) -> Void in
                asked[ticket] = wait
            }
        }

        func answer(_ ticket: Int, _ end: ScanRead) {
            asked.removeValue(forKey: ticket)?.resume(returning: end)
        }
    }

    /// What a read came to, once it has.
    @MainActor final class Ended {
        var value: ScanRead?
    }

    /// A read as LibraryScanModel's makes one: its request, and only the newest's answer landing.
    static func fetch(_ reads: ScanReads, _ wire: Wire, _ ticket: Int) async -> ScanRead {
        let raw = await wire.ask(ticket)
        guard reads.isNewest(ticket) else { return .dropped }
        return reads.ended(ticket, raw)
    }

    /// The editor's look-up: its read carried to an answer.
    static func lookUp(_ reads: ScanReads, _ wire: Wire, cancelled: Bool = false) -> Ended {
        let ended = Ended()
        Task {
            ended.value = await reads.answer(cancelled: { cancelled }) { (ticket: Int) -> ScanRead in
                await fetch(reads, wire, ticket)
            }
        }
        return ended
    }

    /// The page's own read (NeedsLookModel.read - ⌘R's, unguarded as it was at R12's review).
    static func pageRead(_ reads: ScanReads, _ wire: Wire) -> Ended {
        let ended = Ended()
        Task { ended.value = await fetch(reads, wire, reads.begin()) }
        return ended
    }

    /// The main actor let run until `done()` - bounded, so a test that would hang fails instead.
    static func until(_ done: () -> Bool) async {
        var turns = 0
        while !done() && turns < 10_000 {
            await Task.yield()
            turns += 1
        }
    }

    /// A few turns of the main actor: what is to happen now has happened.
    static func turns() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// A session open on ABBA, as a row picked begins one (NeedsLookModel.open).
    static func session() -> NeedsLook.Run {
        var run = NeedsLook.Run()
        let albums = NeedsLookPageTests.albums
        _ = run.begin(NeedsLook.facetAlbums(albums, nil), path: "ABBA/Arrival", facet: nil,
                      live: NeedsLook.facets(albums, [:]))
        return run
    }

    static func pulls(session: Bool, reading: Bool) -> Bool {
        NeedsLookPage.pullReads(online: true, samePerson: true, allowed: true, session: session, reading: reading)
    }

    // MARK: ⌘R mid-read

    @Test func aRefreshMidReadNeverStrandsTheEditor() async {
        let run = Self.session()
        #expect(run.session != nil)
        // the editor's read out - its first, or the follow-up read after an Apply
        let reads = ScanReads(), wire = Wire()
        let editor = Self.lookUp(reads, wire)
        await Self.until { wire.asked[1] != nil }
        #expect(reads.out && reads.newest == 1)
        // ⌘R: held while a session lasts - and while a read is out, the page's own included (its first read, or the
        // one after a session ends, with no session)
        #expect(!Self.pulls(session: run.session != nil, reading: reads.out))
        #expect(!Self.pulls(session: false, reading: reads.out), "a read out: no second read over it")
        // a read of the page's that takes over all the same: the editor's own answer is dropped, and it waits for the
        // page's - its answer is the editor's, never nothing
        let page = Self.pageRead(reads, wire)
        await Self.until { wire.asked[2] != nil }
        wire.answer(1, .landed)
        await Self.turns()
        #expect(editor.value == nil, "the editor waits on the read that took over")
        wire.answer(2, .landed)
        await Self.until { editor.value != nil }
        #expect(page.value == .landed && editor.value == .landed && !reads.out && reads.newest == 2)
        // one that took over and failed: the editor says it failed (its Look again), never waits on
        let again = Self.lookUp(reads, wire)
        await Self.until { wire.asked[3] != nil }
        let failing = Self.pageRead(reads, wire)
        await Self.until { wire.asked[4] != nil }
        wire.answer(3, .landed)
        wire.answer(4, .failed)
        await Self.until { again.value != nil }
        #expect(failing.value == .failed && again.value == .failed && reads.newest == 4)
    }

    /// The read that took over has already landed when the editor's answer comes back: its end is the editor's, with no
    /// read more.
    @Test func aReadThatTookOverAndLandedFirstIsTheEditorsAnswer() async {
        let reads = ScanReads(), wire = Wire()
        let editor = Self.lookUp(reads, wire)
        await Self.until { wire.asked[1] != nil }
        let page = Self.pageRead(reads, wire)
        await Self.until { wire.asked[2] != nil }
        wire.answer(2, .landed)
        await Self.until { page.value != nil }
        wire.answer(1, .landed)
        await Self.until { editor.value != nil }
        #expect(editor.value == .landed && reads.newest == 2 && wire.asked.isEmpty)
    }

    // MARK: ⌘R just after picking a row

    @Test func aRefreshJustAfterPickingARowNeverStrandsTheEditor() async {
        // the row picked: the session begun, the editor's first read not yet out
        let run = Self.session()
        let reads = ScanReads(), wire = Wire()
        #expect(run.session != nil && !reads.out)
        #expect(!Self.pulls(session: run.session != nil, reading: reads.out), "a session lasts: ⌘R asks nothing")
        // the editor's first read begins; a read that took over came to nothing (cancelled with its page): the editor
        // asks again, and that one's answer is the editor's
        let editor = Self.lookUp(reads, wire)
        await Self.until { wire.asked[1] != nil }
        #expect(!Self.pulls(session: run.session != nil, reading: reads.out))
        let page = Self.pageRead(reads, wire)
        await Self.until { wire.asked[2] != nil }
        wire.answer(1, .landed)
        wire.answer(2, .dropped)
        await Self.until { wire.asked[3] != nil }
        #expect(page.value == .dropped && editor.value == nil, "asked again, not left with nothing")
        wire.answer(3, .landed)
        await Self.until { editor.value != nil }
        #expect(editor.value == .landed && reads.newest == 3 && !reads.out)
        // asked again once, at most: a second read that came to nothing ends it dropped, never a loop
        let twice = Self.lookUp(reads, wire)
        await Self.until { wire.asked[4] != nil }
        wire.answer(4, .dropped)
        await Self.until { wire.asked[5] != nil }
        wire.answer(5, .dropped)
        await Self.until { twice.value != nil }
        #expect(twice.value == .dropped && reads.newest == 5 && ScanReads.tries == 2)
    }

    /// A look-up called off with its own page (the Mac's page left while it read) stays dropped, waiting on nothing:
    /// the page asks again as it comes back (EditAlbumModel.reopen).
    @Test func aLookUpCalledOffWithItsPageWaitsOnNothing() async {
        let reads = ScanReads(), wire = Wire()
        let editor = Self.lookUp(reads, wire, cancelled: true)
        await Self.until { wire.asked[1] != nil }
        let page = Self.pageRead(reads, wire)
        await Self.until { wire.asked[2] != nil }
        wire.answer(1, .landed)
        await Self.until { editor.value != nil }
        #expect(editor.value == .dropped && reads.out, "dropped at once, the page's read still out")
        wire.answer(2, .landed)
        await Self.until { page.value != nil }
        #expect(page.value == .landed && !reads.out)
    }
}
