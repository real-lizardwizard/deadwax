import Foundation
import Testing
@testable import DeadwaxCore

/// Slice 2's safety rules, after its review (PlaylistFlows.swift): one write from Add to a playlist at a time across
/// every opening of the picker; what an opening draws and says as its add answers; a playlist page's Edit - when it may
/// begin, what Done sends, what each refusal leaves, Delete; and a field's bound as maxLength keeps it. (Every mutating
/// call is made before its #expect, never inside one.)
struct PlaylistFlowTests {
    /// A scalar as a string - written so, never as an escape in this file (the file tools write escapes raw).
    static func scalar(_ value: UInt32) -> String { String(Character(Unicode.Scalar(value)!)) }

    static func answered(_ status: Int, _ detail: String = "Words.") -> APIFailure {
        .answered(.init(status: status, method: "POST", path: "/navidrome/playlists/pl1/edit", detail: detail))
    }

    static let pick = PlaylistPick(label: "Dummy", songs: [.init(id: "a", title: "Roads"), .init(id: "b", title: "Sour Times")])
    static let lateNight = Playlist(id: "pl1", name: "Late night", mine: true, editable: true)

    // MARK: one write at a time

    @Test func onlyOneOfThePickersWritesIsOutAtATime() throws {
        var writes = PlaylistWrites()
        #expect(!writes.busy)
        let firstBegun = writes.begin(.add(playlist: "pl1", mode: .ask), person: 1)
        let first = try #require(firstBegun)
        #expect(writes.busy)
        #expect(writes.adding("pl1") == .ask)
        #expect(writes.adding("pl2") == nil)
        // another add, to this playlist or another, and New playlist…: not sent
        let again = writes.begin(.add(playlist: "pl1", mode: .ask), person: 1)
        let other = writes.begin(.add(playlist: "pl2", mode: .add), person: 1)
        let create = writes.begin(.create, person: 1)
        #expect(again == nil && other == nil && create == nil)
        #expect(writes.adding("pl1") == .ask)
        // Done and Delete wait on their own: sent, and their answer never opens the picker's gate
        let doneBegun = writes.begin(nil, person: 1)
        let done = try #require(doneBegun)
        let doneCounts = writes.end(done, person: 1)
        #expect(doneCounts)
        #expect(writes.busy)
        // the add answered: the gate open
        let firstCounts = writes.end(first, person: 1)
        #expect(firstCounts)
        #expect(!writes.busy)
        #expect(writes.adding("pl1") == nil)
        let madeBegun = writes.begin(.create, person: 1)
        let made = try #require(madeBegun)
        #expect(writes.busy && writes.adding("pl1") == nil)
        let madeCounts = writes.end(made, person: 1)
        #expect(madeCounts)
        // an answer ended twice opens nothing it didn't hold
        let nextBegun = writes.begin(.add(playlist: "pl2", mode: .skip), person: 1)
        let next = try #require(nextBegun)
        _ = writes.end(made, person: 1)
        #expect(writes.busy && writes.adding("pl2") == .skip)
        _ = writes.end(next, person: 1)
        #expect(!writes.busy)
    }

    @Test func thePickerOpenedAgainSeesTheAddOut() throws {
        // the review's case: Late night tapped, the sheet closed, opened again (or Now Playing's), tapped again
        var writes = PlaylistWrites()
        var first = PlaylistPickerFlow(pick: Self.pick)
        let ticketBegun = writes.begin(.add(playlist: "pl1", mode: .ask), person: 1)
        let ticket = try #require(ticketBegun)
        first.sending()
        first.shown = false
        let opened = PlaylistPickerFlow(pick: Self.pick)
        #expect(opened.question == nil && opened.failure == nil)
        // the opening has nothing of its own out - the gate is the model's, shared: its rows wait, the row says Adding…
        #expect(writes.busy)
        #expect(writes.adding("pl1") == .ask)
        let second = writes.begin(.add(playlist: "pl1", mode: .ask), person: 1)
        #expect(second == nil)
        // the first answers: said in the notice (its sheet gone); the gate open for the second
        let said = first.answered(PlaylistAddAnswer(done: true, already: 0, added: 2), mode: .ask, to: Self.lateNight)
        #expect(said == PlaylistPickerFlow.Said(notice: "Added 2 songs to Late night"))
        let counts = writes.end(ticket, person: 1)
        #expect(counts)
        #expect(!writes.busy)
    }

    @Test func anAnswerForSomeoneElseCountsForNothing() throws {
        var writes = PlaylistWrites()
        // another person signed in meanwhile
        let gatedBegun = writes.begin(.create, person: 1)
        let gated = try #require(gatedBegun)
        let gatedCounts = writes.end(gated, person: 2)
        #expect(!gatedCounts)
        #expect(!writes.busy)
        let plainBegun = writes.begin(nil, person: 1)
        let plain = try #require(plainBegun)
        let plainCounts = writes.end(plain, person: 2)
        #expect(!plainCounts)
        let mineBegun = writes.begin(nil, person: 2)
        let mine = try #require(mineBegun)
        let mineCounts = writes.end(mine, person: 2)
        #expect(mineCounts)
        // a reset (the same person signed in again): the gate open at once, the old answer nothing
        let oldBegun = writes.begin(.add(playlist: "pl1", mode: .ask), person: 3)
        let old = try #require(oldBegun)
        writes.reset()
        #expect(!writes.busy)
        let newBegun = writes.begin(.add(playlist: "pl2", mode: .ask), person: 3)
        let new = try #require(newBegun)
        let oldCounts = writes.end(old, person: 3)
        #expect(!oldCounts)
        // the old answer leaves the new write's gate shut
        #expect(writes.busy && writes.adding("pl2") == .ask)
        let newCounts = writes.end(new, person: 3)
        #expect(newCounts)
        #expect(!writes.busy)
    }

    // MARK: an opening of the picker

    @Test func anAddAnsweredIsDrawnWhileShownAndSaidOnceClosed() {
        var flow = PlaylistPickerFlow(pick: Self.pick)
        let some = PlaylistAddAnswer(done: false, already: 1, asked: 2)
        // some there already: the question, nothing said
        let asked = flow.answered(some, mode: .ask, to: Self.lateNight)
        #expect(asked == PlaylistPickerFlow.Said())
        #expect(flow.question == PlaylistPickerFlow.Asked(playlist: Self.lateNight, already: 1, asked: 2))
        #expect(!flow.finished)
        flow.back()
        #expect(flow.question == nil)
        // added: said, and the sheet closes
        let added = flow.answered(PlaylistAddAnswer(done: true, already: 1, added: 1), mode: .skip, to: Self.lateNight)
        #expect(added == PlaylistPickerFlow.Said(notice: "Added 1 song to Late night - 1 was in it already"))
        #expect(flow.finished && flow.question == nil)

        // the sheet closed meanwhile: said, never drawn
        var closed = PlaylistPickerFlow(pick: Self.pick)
        closed.shown = false
        let someSaid = closed.answered(some, mode: .ask, to: Self.lateNight)
        #expect(someSaid == PlaylistPickerFlow.Said(notice: "Nothing added - some are in Late night already"))
        #expect(closed.question == nil)
        let addedSaid = closed.answered(PlaylistAddAnswer(done: true, already: 0, added: 2), mode: .ask, to: Self.lateNight)
        #expect(addedSaid == PlaylistPickerFlow.Said(notice: "Added 2 songs to Late night"))
        #expect(!closed.finished)
    }

    @Test func anAddRefusedSaysWhyToWhoeverReads() {
        let error = Self.answered(500, "Navidrome said no")
        // the words differ for whoever runs deadwax: the flow passes `admin` through
        #expect(ErrorWords.of(error, admin: true).said != ErrorWords.of(error, admin: false).said)
        for admin in [false, true] {
            var flow = PlaylistPickerFlow(pick: Self.pick)
            _ = flow.answered(PlaylistAddAnswer(done: false, already: 1, asked: 2), mode: .ask, to: Self.lateNight)
            let said = flow.failed(error, to: Self.lateNight, admin: admin)
            #expect(said == PlaylistPickerFlow.Said(announce: ErrorWords.of(error, admin: admin).said))
            #expect(flow.failure != nil && flow.question == nil && !flow.finished)
            flow.sending()
            #expect(flow.failure == nil)

            var closed = PlaylistPickerFlow(pick: Self.pick)
            closed.shown = false
            let closedSaid = closed.failed(error, to: Self.lateNight, admin: admin)
            #expect(closedSaid == PlaylistPickerFlow.Said(notice: ErrorWords.notice("Couldn't add to Late night.", error,
                                                                                     admin: admin)))
            #expect(closed.failure == nil)
        }
        // a 404: the playlist let go, shown or not
        var flow = PlaylistPickerFlow(pick: Self.pick)
        let shownGone = flow.failed(Self.answered(404), to: Self.lateNight, admin: false)
        #expect(shownGone.gone == "pl1")
        flow.shown = false
        let closedGone = flow.failed(Self.answered(404), to: Self.lateNight, admin: false)
        #expect(closedGone.gone == "pl1")
        let refused = flow.failed(Self.answered(403), to: Self.lateNight, admin: false)
        #expect(refused.gone == nil)
    }

    @Test func aPlaylistMadeInThePickerIsSaid() {
        var flow = PlaylistPickerFlow(pick: Self.pick)
        flow.making = true
        let said = flow.made(Self.lateNight)
        #expect(said == PlaylistPickerFlow.Said(notice: "Made Late night with 2 songs"))
        #expect(flow.finished)
        var closed = PlaylistPickerFlow(pick: Self.pick)
        closed.shown = false
        let closedSaid = closed.made(Self.lateNight)
        #expect(closedSaid == PlaylistPickerFlow.Said(notice: "Made Late night with 2 songs"))
        #expect(!closed.finished)
    }

    // MARK: a playlist page's Edit

    static let songs = [Song(id: "e1", title: "Roads"), Song(id: "e2", title: "Teardrop"), Song(id: "e3", title: "Angel")]

    /// A flow with this page's own answer in, Edit open.
    static func editing() -> PlaylistEditFlow {
        var flow = PlaylistEditFlow()
        flow.answered()
        flow.begin(songs: songs, playlist: lateNight, editable: true, online: true)
        return flow
    }

    /// Done's body, or nil when Done sent nothing.
    static func sent(_ step: PlaylistEditFlow.DoneStep) -> PlaylistEditBody? {
        guard case .send(let body) = step else { return nil }
        return body
    }

    @Test func editWaitsForThisPagesOwnAnswer() {
        var flow = PlaylistEditFlow()
        // a kept answer drawn, none of this page's own yet
        #expect(!flow.canBegin(editable: true, online: true))
        let early = flow.begin(songs: Self.songs, playlist: Self.lateNight, editable: true, online: true)
        #expect(!early && !flow.editing)
        let taken = flow.answered()
        #expect(taken)
        #expect(flow.canBegin(editable: true, online: true))
        #expect(!flow.canBegin(editable: false, online: true))
        #expect(!flow.canBegin(editable: true, online: false))
        // an add from the picker made it old: waits for the next answer
        flow.madeOld()
        #expect(!flow.canBegin(editable: true, online: true))
        flow.answered()
        let began = flow.begin(songs: Self.songs, playlist: Self.lateNight, editable: true, online: true)
        #expect(began && flow.editing && !flow.canBegin(editable: true, online: true))
        #expect(flow.now?.rows.map(\.id) == ["e1", "e2", "e3"] && flow.start == flow.now)
        // an answer landing while Edit is open is dropped
        flow.madeOld()
        let dropped = flow.answered()
        #expect(!dropped)
        #expect(!flow.fresh && flow.editing)
        // gone: never again
        var gone = PlaylistEditFlow()
        gone.answered()
        gone.notFound()
        #expect(gone.gone && !gone.canBegin(editable: true, online: true))
        gone.reset()
        #expect(!gone.gone && !gone.fresh && !gone.editing)
        // the page's ask, sent just before Edit began, answered 404: Edit closed on a playlist that has gone
        var goneWhileOpen = Self.editing()
        goneWhileOpen.remove(at: 0)
        goneWhileOpen.notFound()
        #expect(goneWhileOpen.gone && !goneWhileOpen.editing && goneWhileOpen.now == nil)
        #expect(!goneWhileOpen.canBegin(editable: true, online: true))
        // an add's change landing while Edit is open, then Done saved: Done's answer is this page's own, so Edit may
        // begin from it (an add written after the edit makes the next Done's base old: the server's 409)
        var savedAfter = Self.editing()
        savedAfter.remove(at: 0)
        savedAfter.madeOld()
        #expect(!savedAfter.fresh)
        _ = savedAfter.done()
        savedAfter.saved()
        #expect(savedAfter.fresh && savedAfter.canBegin(editable: true, online: true))
    }

    @Test func aRefusedDoneLeavesEditOpenAndSendsWhatItTriedNext() throws {
        var flow = Self.editing()
        flow.remove(at: 1)
        let firstStep = flow.done()
        let first = try #require(Self.sent(firstStep))
        #expect(first.base == ["e1", "e2", "e3"] && first.songIds == ["e1", "e3"] && first.tried == nil)
        #expect(flow.saving && flow.busy)
        // a 502 (part saved): Edit open, why, and the songs it sent kept
        let partSaved = flow.refused(Self.answered(502))
        #expect(partSaved == .refused)
        #expect(flow.editing && !flow.saving && flow.failure != nil)
        #expect(flow.refusals == 1)
        #expect(flow.tried == ["e1", "e3"])
        #expect(flow.fresh)
        // the next Done sends them as `tried` - and a second refusal keeps ITS songs
        flow.move(from: 1, to: 0)
        let secondStep = flow.done()
        let second = try #require(Self.sent(secondStep))
        #expect(second.base == ["e1", "e2", "e3"] && second.songIds == ["e3", "e1"] && second.tried == ["e1", "e3"])
        #expect(flow.failure == nil)
        let notYours = flow.refused(Self.answered(403))
        #expect(notYours == .refused)
        #expect(flow.tried == ["e3", "e1"] && flow.refusals == 2)
        // saved at last: closed, drawn fresh, nothing tried
        let thirdStep = flow.done()
        let third = try #require(Self.sent(thirdStep))
        #expect(third.tried == ["e3", "e1"])
        flow.saved()
        #expect(!flow.editing && !flow.saving && flow.fresh && flow.tried == nil && flow.failure == nil)
    }

    @Test func aDoneRefusedAs409Or404ClosesEdit() {
        var changed = Self.editing()
        changed.remove(at: 0)
        _ = changed.done()
        let elsewhere = changed.refused(Self.answered(409))
        #expect(elsewhere == .changedElsewhere)
        #expect(!changed.editing && !changed.saving && !changed.fresh)
        #expect(changed.note == PlaylistWords.playlistChanged)
        #expect(changed.tried == nil && changed.failure == nil && changed.refusals == 0)
        #expect(!changed.canBegin(editable: true, online: true))
        changed.clearNote()
        #expect(changed.note == nil)

        // after a refused one, a 409 forgets what it tried
        var after = Self.editing()
        after.remove(at: 0)
        _ = after.done()
        after.refused(Self.answered(502))
        _ = after.done()
        after.refused(Self.answered(409))
        #expect(after.tried == nil)

        var gone = Self.editing()
        gone.remove(at: 0)
        _ = gone.done()
        let missing = gone.refused(Self.answered(404))
        #expect(missing == .gone)
        #expect(gone.gone && !gone.editing && !gone.saving && gone.tried == nil)
    }

    @Test func leavingAfterARefusalAsksAgain() {
        var flow = Self.editing()
        // nothing refused: leaving asks nothing
        let plain = flow.leave()
        #expect(!plain && !flow.editing && flow.fresh)

        flow = Self.editing()
        flow.remove(at: 2)
        _ = flow.done()
        flow.refused(Self.answered(502))
        let asks = flow.leave()
        #expect(asks)
        #expect(!flow.editing && !flow.fresh && flow.tried == nil && flow.failure == nil)

        // a refused Done, then the change undone by hand: Done is Cancel - and asks again
        flow = Self.editing()
        flow.remove(at: 2)
        _ = flow.done()
        flow.refused(Self.answered(502))
        flow.now = flow.start
        let undone = flow.done()
        #expect(undone == .unchanged(askAgain: true))
        #expect(!flow.editing && !flow.fresh)
    }

    @Test func doneSendsNothingItShouldnt() {
        var flow = Self.editing()
        let nothing = flow.done()
        #expect(nothing == .unchanged(askAgain: false))
        #expect(!flow.editing && flow.fresh)
        // not open
        let closed = flow.done()
        #expect(closed == .notSent)
        // a blank name
        flow = Self.editing()
        flow.now?.name = "  "
        #expect(flow.needsName && flow.changed)
        let blank = flow.done()
        #expect(blank == .notSent)
        #expect(!flow.saving && flow.editing)
        // Done out: nothing else goes - a second Done, moves, removals, leaving, Delete
        flow.now?.name = "Early"
        let out = flow.done()
        #expect(Self.sent(out) != nil)
        let twice = flow.done()
        #expect(twice == .notSent)
        let rows = flow.now?.rows
        flow.move(from: 0, to: 2)
        flow.remove(at: 0)
        #expect(flow.now?.rows == rows)
        let left = flow.leave()
        #expect(!left && flow.editing)
        let deleting = flow.beginDelete()
        #expect(!deleting)
        // its answer came for someone else
        flow.notSent()
        #expect(!flow.saving && flow.editing)
    }

    @Test func aDeleteAnswered404IsGoneAsADeleteIs() {
        var flow = PlaylistEditFlow()
        flow.answered()
        let closed = flow.beginDelete()
        #expect(!closed)
        flow = Self.editing()
        let begun = flow.beginDelete()
        #expect(begun && flow.deleting && flow.busy)
        let twice = flow.beginDelete()
        #expect(!twice)
        flow.deleted()
        #expect(flow.gone && !flow.editing && !flow.deleting)

        // gone in another app already: gone all the same, Edit closed
        flow = Self.editing()
        _ = flow.beginDelete()
        let gone = flow.deleteRefused(Self.answered(404))
        #expect(gone)
        #expect(flow.gone && !flow.editing && !flow.deleting && flow.deleteFailure == nil)

        // anything else: why, Edit open
        flow = Self.editing()
        _ = flow.beginDelete()
        let refused = flow.deleteRefused(Self.answered(403))
        #expect(!refused)
        #expect(!flow.gone && flow.editing && !flow.deleting && flow.deleteFailure != nil)
        let again = flow.beginDelete()
        #expect(again && flow.deleteFailure == nil)
        flow.deleteNotSent()
        #expect(!flow.deleting && flow.editing)
    }

    // MARK: around the page

    @Test func aPlaylistMadeOnTheScreenClosesOnlyItsOwnSheet() {
        #expect(PlaylistEdit.made(sentFrom: 1, up: 1, shown: true) == .closeThenOpen)
        #expect(PlaylistEdit.made(sentFrom: 1, up: 1, shown: false) == .closeThenOpen)
        #expect(PlaylistEdit.made(sentFrom: 1, up: nil, shown: true) == .open)
        #expect(PlaylistEdit.made(sentFrom: 1, up: nil, shown: false) == .say)
        // swiped away, and another opened since: its name kept
        #expect(PlaylistEdit.made(sentFrom: 1, up: 2, shown: true) == .say)
    }

    @Test func aTabTappedAgainStopsAtAPlaylistBeingEdited() {
        #expect(PlaylistEdit.pagesKept([], editing: nil) == 0)
        #expect(PlaylistEdit.pagesKept([nil, "pl1", nil], editing: nil) == 0)
        #expect(PlaylistEdit.pagesKept([nil, "pl1", nil], editing: "pl1") == 2)
        #expect(PlaylistEdit.pagesKept(["pl1"], editing: "pl1") == 1)
        #expect(PlaylistEdit.pagesKept([nil, "pl2"], editing: "pl1") == 0)
        // the same playlist twice: the topmost is the one open
        #expect(PlaylistEdit.pagesKept(["pl1", nil, "pl1", nil], editing: "pl1") == 3)
    }

    @Test func aFieldKeepsItsBoundAsMaxLengthDoes() {
        // within the bound, as typed
        #expect(PlaylistEdit.typed("abc", was: "ab", max: 3) == "abc")
        #expect(PlaylistEdit.typed("", was: "abc", max: 3) == "")
        // a keystroke past it: refused
        #expect(PlaylistEdit.typed("abcd", was: "abc", max: 3) == "abc")
        // a paste: what fits of it, what was after the cursor kept
        #expect(PlaylistEdit.typed("abxyz", was: "ab", max: 4) == "abxy")
        #expect(PlaylistEdit.typed("aXYZb", was: "ab", max: 4) == "aXYb")
        #expect(PlaylistEdit.typed("XYZab", was: "ab", max: 4) == "XYab")
        // a selection replaced: the rest kept, what fits put in
        #expect(PlaylistEdit.typed("aXYZWd", was: "abcd", max: 5) == "aXYZd")
        // nothing fits: as it was
        #expect(PlaylistEdit.typed("abcX", was: "abc", max: 3) == "abc")
        // never a character split: a note of two UTF-16 units
        let note = Self.scalar(0x1F3B5)
        #expect(PlaylistEdit.typed("ab" + note, was: "ab", max: 3) == "ab")
        #expect(PlaylistEdit.typed("ab" + note, was: "ab", max: 4) == "ab" + note)
        #expect(PlaylistEdit.typed("a" + note + note, was: "a", max: 4) == "a" + note)
        // a name already over the bound (made in another app): never cut, cut down by hand, never grown
        let long = String(repeating: "x", count: 250)
        #expect(PlaylistEdit.typed(long, was: "", max: 200).utf16.count == 200)
        #expect(PlaylistEdit.typed(long + "y", was: long, max: 200) == long)
        #expect(PlaylistEdit.typed(String(long.dropLast()), was: long, max: 200).count == 249)
        #expect(PlaylistEdit.typed("y" + String(long.dropFirst()), was: long, max: 200) == "y" + String(long.dropFirst()))
        #expect(PlaylistEdit.typed("yz" + String(long.dropFirst()), was: long, max: 200) == long)
        // the server's bound
        #expect(PlaylistEdit.typed(String(repeating: "n", count: 201), was: String(repeating: "n", count: 200),
                                   max: PlaylistRules.nameMax).count == 200)
    }
}
