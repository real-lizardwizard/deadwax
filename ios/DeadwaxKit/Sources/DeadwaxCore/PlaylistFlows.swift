import Foundation

// The safety rules of changing playlists (Phase 4, slice 2, after its review; notes/ios-specs/phase4-library.md 2.4) as
// state machines the App drives and the tests can: one write from Add to a playlist at a time, across every opening of
// the picker; what an opening of the picker draws and says as its add answers; and a playlist page's Edit - when it may
// begin, what Done sends, and what each refusal leaves. The App holds one of each and does what they say; nothing here
// asks deadwax.

// MARK: one write at a time

/// The writes to Navidrome's playlists, as PlaylistsModel holds them: at most one from Add to a playlist out at a time
/// (question 13, the web's one PlaylistPicker's `writing`) - an add, or New playlist… - shared by every opening of the
/// picker and both its openers (the tabs' sheet, Now Playing's), so a tap while one is out, in the same sheet or one
/// opened since, is never sent. The server's add reads the playlist and then writes to it: a second add sent before the
/// first has written would find the songs not there, and both would append them - twice, the question never asked.
///
/// And every write's ticket (Edit's Done and Delete, and the Playlists screen's New, which wait on their own, take one
/// too): its answer counts only for the person it was asked as - `end` says false once another has signed in, or
/// `reset` ran, and the App drops it (PlaylistsModel.Superseded).
public struct PlaylistWrites: Sendable, Equatable {
    public enum Write: Sendable, Equatable {
        /// Songs added to the playlist of this id, `mode` the duplicates the add sends.
        case add(playlist: String, mode: PlaylistDuplicates)
        /// New playlist…, with the songs.
        case create
    }

    /// One write, from `begin` to `end`.
    public struct Ticket: Sendable, Equatable {
        let serial: Int
        let gated: Bool
        let generation: Int
        let person: Int
    }

    /// The picker's write out - nil: none, a row may be tapped.
    public private(set) var out: Write?
    private var outSerial = 0
    private var serial = 0
    private var generation = 0

    public init() {}

    /// A write of the picker's is out: its rows and New playlist… wait.
    public var busy: Bool { out != nil }

    /// The mode of the add out to `playlist` - its row (or the question's button) says "Adding…" - else nil.
    public func adding(_ playlist: String) -> PlaylistDuplicates? {
        guard case .add(let id, let mode)? = out, id == playlist else { return nil }
        return mode
    }

    /// A write about to be sent, as `person`: its ticket. `write` is the picker's - nil while another of the picker's
    /// is out (nothing to send); nil `write` (Done, Delete, the screen's New) always has one.
    public mutating func begin(_ write: Write?, person: Int) -> Ticket? {
        if write != nil, out != nil { return nil }
        serial += 1
        if let write {
            out = write
            outSerial = serial
        }
        return Ticket(serial: serial, gated: write != nil, generation: generation, person: person)
    }

    /// A write answered, or failed: the picker's gate open again if it was this one (never one begun since a reset).
    /// True when its answer counts - asked as the person signed in now, and no reset since.
    public mutating func end(_ ticket: Ticket, person: Int) -> Bool {
        if ticket.gated, ticket.serial == outSerial {
            out = nil
            outSerial = 0
        }
        return ticket.generation == generation && ticket.person == person
    }

    /// The person changed: the gate open at once, and every write still out counting for nothing when it answers.
    public mutating func reset() {
        generation += 1
        out = nil
        outSerial = 0
    }
}

// MARK: an opening of the picker

/// One opening of Add to a playlist (PlaylistPicker.tsx), past the gate: New playlist…'s name open, the duplicate
/// question, why the last add was refused, and whether the sheet is done. What an answer does depends on whether the
/// sheet is still up (`shown`): drawn there, else said in the app's notice - an add is never called off by the sheet
/// closing (a write), so its answer always says how it went.
public struct PlaylistPickerFlow: Sendable {
    /// Some songs are in the playlist already, nothing written: the question, in the list's place.
    public struct Asked: Sendable, Equatable {
        public let playlist: Playlist
        public let already: Int
        public let asked: Int

        public init(playlist: Playlist, already: Int, asked: Int) {
            self.playlist = playlist
            self.already = already
            self.asked = asked
        }
    }

    /// What the App does besides drawing: the notice's words, VoiceOver's, and a playlist answered gone (its kept
    /// answer let go, the list asked again).
    public struct Said: Sendable, Equatable {
        public var notice: String?
        public var announce: String?
        public var gone: String?

        public init(notice: String? = nil, announce: String? = nil, gone: String? = nil) {
            self.notice = notice
            self.announce = announce
            self.gone = gone
        }
    }

    public let pick: PlaylistPick
    /// New playlist…'s name, open in its row's place.
    public var making = false
    public private(set) var question: Asked?
    /// Why the last add was refused, under the head.
    public private(set) var failure: (any Error)?
    /// The sheet closes.
    public private(set) var finished = false
    /// The sheet is up.
    public var shown = true

    public init(pick: PlaylistPick) {
        self.pick = pick
    }

    /// The question's Cancel: back to the list, nothing sent.
    public mutating func back() {
        question = nil
    }

    /// An add sent: the last refusal's words put away.
    public mutating func sending() {
        failure = nil
    }

    /// An add answered (PlaylistRules.outcome): the question drawn, or the notice and the sheet closed.
    public mutating func answered(_ answer: PlaylistAddAnswer, mode: PlaylistDuplicates, to playlist: Playlist) -> Said {
        switch PlaylistRules.outcome(of: answer, mode: mode, pick: pick, name: playlist.name) {
        case .asks(let already, let asked):
            guard shown else { return Said(notice: PlaylistWords.someAlready(playlist.name)) }
            question = Asked(playlist: playlist, already: already, asked: asked)
            return Said()
        case .added(let words):
            if shown {
                question = nil
                finished = true
            }
            return Said(notice: words)
        }
    }

    /// An add refused, or lost: why under the head (and said to VoiceOver), or in the notice once the sheet has closed;
    /// a 404 lets the playlist go.
    public mutating func failed(_ error: any Error, to playlist: Playlist, admin: Bool) -> Said {
        let gone = ErrorWords.kind(of: error) == .notFound ? playlist.id : nil
        guard shown else {
            return Said(notice: ErrorWords.notice(PlaylistWords.couldntAdd(playlist.name), error, admin: admin), gone: gone)
        }
        question = nil
        failure = error
        return Said(announce: ErrorWords.of(error, admin: admin).said, gone: gone)
    }

    /// New playlist… made with the songs: said, and the sheet closed.
    public mutating func made(_ playlist: Playlist) -> Said {
        if shown { finished = true }
        return Said(notice: PlaylistRules.madeWords(playlist.name, pick: pick))
    }
}

// MARK: a playlist's page, Edit

/// A playlist page's Edit (PlaylistPage.tsx): offered only once this page's own ask has answered (`fresh`) - never from
/// a kept answer, nor one a write elsewhere made old - and while deadwax is in reach. While Edit is open an answer
/// landing is dropped: Done's `base` is the songs as drawn when it began, which deadwax checks (a 409 for a change made in
/// another app since). Done sends the one body the changes make, with `tried` - the songs the last REFUSED Done sent,
/// which Navidrome may have taken before refusing (notes/playlists.md, "A Done refused can't be retried as it stood").
/// Each answer's transition:
/// - saved: drawn as deadwax answered it, Edit closed, `tried` let go;
/// - 409, changed elsewhere: nothing saved - Edit closed, PLAYLIST_CHANGED said, the playlist asked again before Edit
///   is offered (`fresh` false);
/// - 404: gone, Edit closed;
/// - anything else: Edit stays open with why (`failure`, `refusals` one more), the next Done sending `tried`; leaving
///   Edit then asks the playlist again.
/// Delete: deleted, or a 404 - gone either way, Edit closed; anything else, why, Edit open.
public struct PlaylistEditFlow: Sendable {
    /// The answer drawn is this page's own ask's, or its own Done's: Edit may begin from it.
    public private(set) var fresh = false
    /// deadwax says it is gone (a 404 - the page's ask, Done's or Delete's), or it was deleted here.
    public private(set) var gone = false
    /// Edit, open: what it began with - nil while closed.
    public private(set) var start: PlaylistEditState?
    /// Edit's changes as they are now - nil while closed.
    public var now: PlaylistEditState?
    /// Done is out.
    public private(set) var saving = false
    /// Delete is out.
    public private(set) var deleting = false
    /// Done was refused (not a 409 or a 404): why, while Edit stays open.
    public private(set) var failure: (any Error)?
    /// Delete was refused: why, under its row.
    public private(set) var deleteFailure: (any Error)?
    /// The playlist changed in another app while it was being edited: said over the songs as they are now.
    public private(set) var note: String?
    /// The songs the last refused Done sent - the next Done's `tried`.
    public private(set) var tried: [String]?
    /// One more for each Done refused with Edit left open: the page goes to the reason.
    public private(set) var refusals = 0
    private var sending: [String]?

    public init() {}

    public var editing: Bool { now != nil }
    /// A write of the page's is out.
    public var busy: Bool { saving || deleting }
    /// Edit holds changes Done would send.
    public var changed: Bool {
        guard let start, let now else { return false }
        return PlaylistEdit.changed(start: start, now: now)
    }
    /// The name is blank: Done waits.
    public var needsName: Bool { now.map(PlaylistEdit.needsName) ?? false }

    /// Edit may begin: the playlist editable here (PlaylistRules.canEdit), this page's own answer drawn, deadwax in
    /// reach, and Edit not open already.
    public func canBegin(editable: Bool, online: Bool) -> Bool {
        editable && fresh && online && !editing && !gone
    }

    // MARK: the page's ask

    /// Another playlist, or another person: everything let go.
    public mutating func reset() {
        self = PlaylistEditFlow()
    }

    /// This page's own ask answered: Edit may begin from it - false, and nothing changed, while Edit is open (the
    /// answer is dropped).
    @discardableResult
    public mutating func answered() -> Bool {
        guard !editing else { return false }
        fresh = true
        gone = false
        return true
    }

    /// The page's ask answered 404.
    public mutating func notFound() {
        gone = true
        close()
    }

    /// A write elsewhere changed the playlist and gave no answer (an add from the picker): what is drawn is old until
    /// the page's ask answers again.
    public mutating func madeOld() {
        fresh = false
    }

    // MARK: Edit

    /// Edit begun from the songs as drawn - false when it may not begin.
    @discardableResult
    public mutating func begin(songs: [Song], playlist: Playlist, editable: Bool, online: Bool) -> Bool {
        guard canBegin(editable: editable, online: online) else { return false }
        let began = PlaylistEdit.start(songs: songs, playlist: playlist)
        start = began
        now = began
        failure = nil
        deleteFailure = nil
        note = nil
        return true
    }

    /// Edit closed, nothing sent - true when the playlist must be asked again (a Done was refused: what is drawn may be
    /// old, so Edit waits for the answer).
    @discardableResult
    public mutating func leave() -> Bool {
        guard !busy else { return false }
        close()
        guard tried != nil else { return false }
        tried = nil
        fresh = false
        return true
    }

    /// The row at `from` moved to `to` (nothing while a write is out).
    public mutating func move(from: Int, to: Int) {
        guard var rows = now?.rows, !busy else { return }
        rows = PlaylistEdit.move(rows, from: from, to: to)
        now?.rows = rows
    }

    /// The row at `index` taken out (nothing while a write is out).
    public mutating func remove(at index: Int) {
        guard var rows = now?.rows, !busy else { return }
        rows = PlaylistEdit.remove(rows, at: index)
        now?.rows = rows
    }

    /// What Done does now.
    public enum DoneStep: Sendable, Equatable {
        /// Nothing had changed: Edit closed - and the playlist to be asked again when `askAgain`.
        case unchanged(askAgain: Bool)
        /// Edit isn't open, a write is out, or the name is blank: nothing sent.
        case notSent
        /// This body to send - Done is out.
        case send(PlaylistEditBody)
    }

    public mutating func done() -> DoneStep {
        guard let start, let now, !busy else { return .notSent }
        guard let body = PlaylistEdit.body(start: start, now: now) else { return .unchanged(askAgain: leave()) }
        guard !PlaylistEdit.needsName(now) else { return .notSent }
        saving = true
        failure = nil
        sending = body.songIds
        return .send(body.trying(tried))
    }

    /// Done answered, saved: drawn as deadwax has it.
    public mutating func saved() {
        saving = false
        sending = nil
        tried = nil
        gone = false
        fresh = true
        close()
    }

    /// Done's answer came for someone else (the person changed): nothing of it kept.
    public mutating func notSent() {
        saving = false
        sending = nil
    }

    /// Done refused: what it leaves (PlaylistEdit.refusal), returned for the page to show.
    @discardableResult
    public mutating func refused(_ error: any Error) -> PlaylistEdit.Refusal {
        saving = false
        let sent = sending
        sending = nil
        let refusal = PlaylistEdit.refusal(of: error)
        switch refusal {
        case .changedElsewhere:
            tried = nil
            close()
            fresh = false
            note = PlaylistWords.playlistChanged
        case .gone:
            tried = nil
            close()
            gone = true
        case .refused:
            tried = sent
            failure = error
            refusals += 1
        }
        return refusal
    }

    // MARK: Delete

    /// Delete about to be sent - false when it may not be (Edit not open, a write out).
    public mutating func beginDelete() -> Bool {
        guard editing, !busy else { return false }
        deleting = true
        deleteFailure = nil
        return true
    }

    /// Deleted: gone, Edit closed.
    public mutating func deleted() {
        deleting = false
        tried = nil
        gone = true
        close()
    }

    /// Delete's answer came for someone else: nothing of it kept.
    public mutating func deleteNotSent() {
        deleting = false
    }

    /// Delete refused: a 404 is gone all the same (true) - Edit closed; anything else, why, Edit open (false).
    @discardableResult
    public mutating func deleteRefused(_ error: any Error) -> Bool {
        deleting = false
        if PlaylistEdit.refusal(of: error) == .gone {
            deleted()
            return true
        }
        deleteFailure = error
        return false
    }

    /// The note said over the songs put away.
    public mutating func clearNote() {
        note = nil
    }

    private mutating func close() {
        start = nil
        now = nil
        failure = nil
        deleteFailure = nil
    }
}

// MARK: around the page

extension PlaylistEdit {
    /// What follows New playlist's Create on the Playlists screen, answered: the sheet that sent it still up - closed,
    /// the new playlist opened once it has gone; no sheet up and the screen on top - opened now; otherwise (the screen
    /// left, or another sheet opened since, holding a name of its own) - said in the notice, and nothing closed.
    public enum Made: Sendable, Equatable {
        case closeThenOpen, open, say
    }

    public static func made<Sheet: Equatable>(sentFrom sheet: Sheet, up: Sheet?, shown: Bool) -> Made {
        if up == sheet { return .closeThenOpen }
        if up == nil && shown { return .open }
        return .say
    }

    /// The pages a tab keeps when it is tapped again (back to its root): none - or, with a playlist's Edit open in it,
    /// every page up to that playlist's, so its changes are never thrown away without Cancel's question.
    /// `playlists` is the tab's pages, each a playlist's id or nil.
    public static func pagesKept(_ playlists: [String?], editing: String?) -> Int {
        guard let editing, let at = playlists.lastIndex(where: { (id: String?) -> Bool in id == editing }) else {
            return 0
        }
        return at + 1
    }
}
