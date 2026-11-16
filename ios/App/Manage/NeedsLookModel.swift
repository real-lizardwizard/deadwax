import DeadwaxCore
import Observation
import SwiftUI

/// Needs a look's state (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; the web's app/NeedsALook.tsx): the
/// library's scan (`GET /library/albums?tracks=false`, its ETag kept - LibraryScanModel), the facet chosen, and the
/// session - the list as shown when a row was opened, fixed, stepped through in Edit album's queue mode. Every rule it
/// follows is Core's NeedsLook, generated from the web's own (care-vectors.json); the session's every move is Core's
/// Run (slice 6's review) - begun, stepped through the editor's gate, ended once - and this only carries out what it
/// decides (`carry`): asks, keeps and hands on.
///
/// Read the first time the page shows, again underneath as it shows again (back in front) with no session and no ending
/// held, and again as deadwax comes back into reach with no session open; a pull reads again, never out of reach. A row
/// opens Edit album over the tabs on its folder, in queue mode, with this page's scan - one read, one ETag. Stepping
/// away from an album (‹, Skip, Next album, the editor going) notes it looked at (`POST /library/queue/reviewed` -
/// what clears a new import), and the count is asked again once that is written. An album gone when stepped to ends the
/// session and closes the sheet. When the session ends, its rows and facets stay on screen until the page's own read
/// after it has landed (Ending), and the list is worked out again from it.
///
/// Nothing is done past a sign-out (`samePerson`, AppNavigation's session when the page opened): the next person's
/// page is none of this one's business.
@MainActor
@Observable
final class NeedsLookModel {
    /// The library's scan - the page's own, and the editor's in queue mode.
    let scan = LibraryScanModel()
    /// The facet chosen (nil: All) - the web's address.
    private(set) var facet: String?
    /// The session, the facets held while it lasts, and its ending (Core's Run): every move of them decided there.
    private(set) var run = NeedsLook.Run()
    /// deadwax can be reached (Reachability), as the screen last said.
    private(set) var online = true
    /// The page is the one showing, the app in front.
    @ObservationIgnored private var shown = false
    @ObservationIgnored private weak var server: ServerModel?
    @ObservationIgnored private weak var navigation: AppNavigation?
    @ObservationIgnored private weak var count: QueueCountModel?
    /// AppNavigation's session when the page opened.
    @ObservationIgnored private var person: Int?

    /// The app's server, navigation and the count - once, as the page first shows.
    func attach(server: ServerModel, navigation: AppNavigation, count: QueueCountModel) {
        guard self.server == nil else { return }
        self.server = server
        self.navigation = navigation
        self.count = count
        person = navigation.session
    }

    /// Still the person the page opened for.
    private var samePerson: Bool {
        guard let navigation, let person else { return false }
        return navigation.session == person
    }

    // MARK: what the page draws

    /// Who the page is for (App.tsx's `allowed` and `canEdit`).
    var page: Managing.NeedsLookPage {
        Managing.needsLook(server?.access.permissions ?? [])
    }

    /// deadwax's own words, for whoever runs it (access.ts seesDetail).
    private var admin: Bool { server?.access.seesDetail ?? false }

    /// The session, while Edit album is open from a row.
    var session: NeedsLook.Session? { run.session }
    /// A session just ended: its rows held until the page's read after it lands.
    var ending: NeedsLook.Ending? { run.ending }
    /// One more each time the session steps to another album: the sheet opens it afresh.
    var steps: Int { run.steps }

    var issueTypes: [String: MetadataIssueType] { scan.answer?.issueTypes ?? [:] }

    /// The facets over the scan as it is.
    var liveChips: [NeedsLook.Facet] { NeedsLook.facets(scan.albums, issueTypes) }

    /// The facet the list is narrowed by (a facet emptied shows All).
    var showing: String? { NeedsLook.showing(session: session, live: liveChips, facet: facet) }

    /// The facets drawn in the Show menu: as the session began, the ending's, else the live ones - All always, the rest
    /// with an album.
    var chips: [NeedsLook.Facet] {
        NeedsLook.drawn(NeedsLook.chips(session: session, held: run.held, ending: ending, live: liveChips))
    }

    /// The facet drawn chosen.
    var pressed: String? { NeedsLook.pressed(session: session, ending: ending, showing: showing) }

    /// The facet drawn chosen, as a chip - All's for none.
    var pressedChip: NeedsLook.Facet? {
        NeedsLook.chip(NeedsLook.chips(session: session, held: run.held, ending: ending, live: liveChips),
                       pressed: pressed)
    }

    /// The rows drawn: the session's, the ending's held, else the facet's albums.
    var rows: [NeedsLook.DrawnRow] {
        NeedsLook.rows(session: session, ending: ending, albums: NeedsLook.facetAlbums(scan.albums, showing))
    }

    /// The page's state before its list.
    var state: NeedsLook.State {
        NeedsLook.state(problem: scan.answer?.problem, loaded: scan.ended, failed: scan.failed != nil,
                        albums: scan.albums.count)
    }

    /// The status line over the list. The phone reads the real scan only - never a saved one first - so nothing in
    /// hand is ever stale.
    var status: NeedsLook.Status? {
        NeedsLook.status(failed: scan.failed != nil, loaded: scan.loaded, stale: false, reading: scan.reading,
                         navidrome: NeedsLook.navidromeNote(scan.answer?.navidromeCheck, detail: admin))
    }

    /// The last read's failure in the page's own words (slice 6's review) - never the editor's, though they share the
    /// scan: READ_FAILED with no albums to show (the ladder's, with Try again - nothing read yet, or a library read
    /// empty), CHECK_FAILED over the list on screen (the status line's) - or deadwax's own words, as the web's
    /// errorNote and sayError say them.
    var failure: String? {
        scan.failure(saying: scan.albums.isEmpty ? NeedsLook.readFailed : NeedsLook.checkFailed)
    }

    /// An "It's fine as it is" will come back: deadwax has no job store, as the scan or the count says.
    var ignoresUnsaved: Bool {
        NeedsLook.ignoresUnsaved(loaded: scan.loaded, reviewTracking: scan.answer?.reviewTracking ?? true,
                                 summaryTracking: count?.count.tracking)
    }

    /// Where the editor is in the session.
    var nav: NeedsLook.Nav? { session.map(NeedsLook.Nav.init) }

    /// The folder the editor opens: the session's current album's, followed through a rename.
    var folder: String? { session.flatMap(NeedsLook.folder) }

    /// A row's words after its lines.
    func chipWords(_ row: NeedsLook.DrawnRow) -> [String] {
        NeedsLook.chipWords(row, pressed: pressed, issueTypes: issueTypes)
    }

    // MARK: reading

    /// The page shows - opened, back from another tab, the app back in front: read the first time, and again
    /// underneath after that with nothing under way.
    func shows(online: Bool) async {
        let wasShown = shown
        shown = true
        self.online = online
        await look(wasShown: wasShown)
    }

    /// The page gone from view (another tab, popped, the app in the background).
    func hidden() {
        shown = false
    }

    /// deadwax came into reach, or went out of it. Back, with the page showing, the library is read again (review, 16
    /// Nov) - unless Edit album is open on a session: its own read as deadwax comes back (EditAlbumModel.reach) is this
    /// same scan's.
    func reach(_ now: Bool) async {
        guard now != online else { return }
        online = now
        guard now, shown, session == nil else { return }
        await read()
    }

    /// The first read, else the read again underneath (NeedsALook.tsx's `wasShown` effect).
    private func look(wasShown: Bool) async {
        guard page.allowed, online, samePerson else { return }
        if !scan.loaded {
            await read()
            return
        }
        guard NeedsLook.readsAgain(allowed: true, shown: true, wasShown: wasShown, loaded: scan.loaded,
                                   session: session != nil, ending: ending != nil) else { return }
        await read()
    }

    /// The library read again (the page's failure words are its own - `failure`).
    func read() async {
        guard samePerson, page.allowed else { return }
        await scan.read(client: server?.client, admin: admin)
        settle()
    }

    /// A pull: the count asked and the library read again - never out of reach (the line at the top says so).
    func pulled() async {
        guard online, samePerson, page.allowed else { return }
        count?.pulled()
        await read()
    }

    /// Try again (the first read's, or the status line's): never while a read is out.
    func retry() {
        guard !scan.reading else { return }
        Task { await read() }
    }

    /// After any read of the scan - the page's or the editor's - ends: an ending whose read has answered let go, and a
    /// facet that has emptied given up for All.
    func settle() {
        run.settle(reading: scan.reading)
        let real = NeedsLook.real(loaded: scan.loaded, stale: false, failed: scan.failed != nil)
        if NeedsLook.facetGivenUp(allowed: page.allowed, shown: shown, real: real, session: session != nil,
                                  ending: ending != nil, facet: facet, showing: showing) {
            facet = nil
        }
    }

    // MARK: the facet, a row, the session

    /// A facet chosen from Show: a session ends with it (the sheet closes).
    func choose(facet id: String?) {
        carry(run.facetChosen(live: liveChips))
        facet = id
    }

    /// A row tapped: the session begun on it, Edit album opened on its folder in queue mode. Nothing while rows are
    /// held or a session lasts (the Run's), out of reach, or for another person.
    func open(_ row: NeedsLook.DrawnRow) {
        guard samePerson, online else { return }
        let shown = showing
        guard run.begin(NeedsLook.facetAlbums(scan.albums, shown), path: row.album.path, facet: shown,
                        live: liveChips) else { return }
        navigation?.editAlbum(AlbumEditRequest(target: .folder(row.album.path), queue: self))
    }

    /// What the editor says became of an album of the session: its row brought up to date, in place.
    func heard(_ change: NeedsLook.FolderChange) {
        guard samePerson else { return }
        run.heard(change)
    }

    /// ‹ (-1), Skip or Next album (+1) in the editor - or Discard's step - through the editor's gate as it is now: the
    /// album left noted as looked at, and the next opened - or, gone from the scan, the session over and the sheet
    /// closed.
    func go(by delta: Int, gate: NeedsLook.StepGate) {
        guard samePerson else { return }
        carry(run.step(by: delta, gate: gate, present: NeedsLook.lists(scan.albums), live: liveChips))
    }

    /// The editor's sheet went - Close, a swipe, Discard, a step to an album gone, a sign-out (MainTabs' onDismiss,
    /// AppNavigation): the session over, the album on screen noted - the Run ends it once, whoever says so after.
    func editorClosed() {
        carry(run.closed(live: liveChips))
    }

    /// What the Run decided, carried out: the album left noted (then the count asked), the editor closed when it said
    /// so, the next album announced - and, the session over, the library read once the note is written (or the scan
    /// could still count the album just left), its ending let go after that read.
    private func carry(_ after: NeedsLook.After) {
        guard after != .nothing else { return }
        let note = after.note
        let noted = Task { await self.review(note) }
        if after.close {
            closeEditor()
        }
        if let ticket = after.ended {
            Task {
                await noted.value
                await self.read()
                self.run.endingRead(ticket)
                self.settle()
            }
        }
        if after.stepped, let now = session, let row = now.current {
            AccessibilityNotification.Announcement(
                NeedsLookWords.stepped(NeedsLook.Nav(now), album: NeedsLook.title(row.album))).post()
        }
    }

    /// The album noted as looked at, then the count asked again. Settles either way: a failure is said nowhere, as the
    /// web's isn't - the album stays new, and comes back.
    private func review(_ path: String?) async {
        guard let path, samePerson, let client = server?.client else { return }
        do {
            _ = try await client.markReviewed(path: path)
            guard samePerson else { return }
            count?.changed()
        } catch {
            return
        }
    }

    /// The editor closed, when it is this page's.
    private func closeEditor() {
        guard let navigation, navigation.albumEdit?.queue === self else { return }
        navigation.albumEdit = nil
    }
}
