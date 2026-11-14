import DeadwaxCore
import Foundation
import Observation

/// Search (Phase 5, slices 1 and 2 - notes/ios-specs/phase5-search.md 2.6-2.9 and 6.2; the web's app/Search.tsx):
/// Core's SearchState kept here, and the requests it says to make - All's search3 once typing pauses
/// (`SearchReading.librarySettleMs`) or at once on the keyboard's Search, a kind view's own beside it, More by offset,
/// the albums a song plays from, `/library/owned` as Search shows; and MusicBrainz's albums once typing pauses longer
/// (`SearchReading.musicBrainzSettleMs`, three characters at least) or on the keyboard's Search, with the plain words
/// asked again when a fielded read finds nothing, and a moment's wait for `/library/owned` before they draw.
///
/// Every rule of when to ask and what to draw is Core's (SearchState, SearchList); this makes the asks, keeps their
/// tasks and the moments' clocks - the library's late (`libraryLateMs`), a kind view's late, the run's cap
/// (`resultsWaitMs`) - and tells the state what landed and when a clock ran out. Only the newest ask's answer counts
/// (the state's tokens), and an ask let go - new words, the box emptied, a new person - is cancelled.
///
/// - What the list drew is announced as it draws (Core's `said`, or "No results for …"), a chip as it is pressed.
/// - While deadwax can't be reached nothing is asked (2.9); the screen says so for words with nothing drawn, and when
///   deadwax is back what wasn't asked is. Nothing of MusicBrainz is drawn offline.
/// - Navidrome known not to be there (the Library's own check, LibraryModel): search3 isn't asked, the library counted
///   as skipped - the gate's words stand above the list; MusicBrainz is still asked.
/// - `/library/owned` (question 6): asked each time Search shows and beside each MusicBrainz ask, with its ETag - kept
///   in memory for the person, never on disk; a failure is quiet.
/// - A MusicBrainz album the library holds opens yours (the id bridge, `/store/album` by its releases you hold), else
///   the album you don't have (`AppRoute.group`).
///
/// `reset()` - a new person - lets everything go, and nothing asked before it lands after it.
@MainActor
@Observable
final class SearchModel {
    /// What the box holds, as typed (clamped to `SearchReading.maxCharacters`).
    private(set) var text = ""
    /// Core's state: the words, the view, what was asked and answered, the list drawn, a kind view's own.
    private(set) var state = SearchState()
    /// Why All's search3 last failed - read while the state says it failed.
    private(set) var failure: (any Error)?
    /// Why a kind view's own failed, or its More.
    private(set) var kindFailure: (any Error)?
    private(set) var moreFailure: (any Error)?
    /// `/library/owned`'s answer for the person, and its index - nil until it has answered.
    private(set) var owned: OwnedAnswer?
    private(set) var ownedIndex: OwnedIndex?
    /// The MusicBrainz album whose row is asking the id bridge (its busy look) - nil when none is.
    private(set) var opening: String?

    private let server: ServerModel
    private let library: LibraryModel
    private let artists: ArtistsModel
    private let reachability: Reachability
    private let navigation: AppNavigation

    /// One more at every reset: nothing begun for the person before lands after.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var settlingMusicBrainz: Task<Void, Never>?
    @ObservationIgnored private var asking: Task<Void, Never>?
    @ObservationIgnored private var askingKind: Task<Void, Never>?
    @ObservationIgnored private var askingMore: Task<Void, Never>?
    @ObservationIgnored private var askingAlbums: Task<Void, Never>?
    @ObservationIgnored private var askingHeld: Task<Void, Never>?
    @ObservationIgnored private var prefetching: [Task<Void, Never>] = []
    @ObservationIgnored private var ownedTag: String?
    @ObservationIgnored private var askingOwned = false
    /// The clocks: the library's late, a kind view's late (for its key), the run's cap (for its run).
    @ObservationIgnored private var lateClock: Task<Void, Never>?
    @ObservationIgnored private var kindLateClock: (key: String, task: Task<Void, Never>)?
    @ObservationIgnored private var capClock: (run: Int, task: Task<Void, Never>)?

    init(server: ServerModel, library: LibraryModel, artists: ArtistsModel, reachability: Reachability,
         navigation: AppNavigation) {
        self.server = server
        self.library = library
        self.artists = artists
        self.reachability = reachability
        self.navigation = navigation
    }

    /// With logins on and a library of your own: the library's rows are the collection's, each saying whose it is.
    var personal: Bool { server.access.hasLibrary }

    /// What says whose a row is, now: your albums (the Library's own list), the folders, the albums in hand.
    var marks: SearchMarks {
        let personal = self.personal
        let yours = personal ? library.albums(.yours).map { SearchMarks.yours($0.albums) } : nil
        return SearchMarks(personal: personal, index: ownedIndex, yourAlbums: yours?.ids, yourArtists: yours?.artists,
                           known: state.knownAlbums)
    }

    /// Navidrome known not to be there (the Library's gate, closed): nothing asked of search3.
    var navidromeAway: NavidromeGate.Closed? {
        guard NavidromeGate.consulted(reachability.reach), library.navidrome?.offline != true else { return nil }
        if case .closed(let closed) = NavidromeGate.shownOnPhone(library.navidrome, access: server.access) { return closed }
        return nil
    }

    /// A kind view as it stands (Core's `kindView`) - nil in All.
    var kindView: KindView? { state.kindView(artistList: artists.list, marks: marks) }

    // MARK: what the screen tells it

    /// Search shows (the tab picked, the app back in front on it, your library changed): `/library/owned` asked again
    /// (a 304 unless the library changed), your albums looked at - LibraryModel asks only when its generation moved,
    /// as an Add or a Remove moves it (the web's yoursGeneration), so whose a row is never reads a list let go - and the
    /// library's artists when not in hand.
    func shown() {
        guard reachability.online, server.client != nil else { return }
        askOwned()
        if personal {
            Task { await library.load(.yours) }
        }
        if artists.list == nil {
            Task { await artists.ask() }
        }
        if library.navidrome == nil, !library.checkingNavidrome {
            Task { await library.checkNavidrome() }
        }
    }

    /// The album you don't have shows (its page's task): `/library/owned` asked again, so what it says of the library
    /// is now's (ReleaseGroupPage.tsx's refreshOwned as it shows).
    func refreshOwned() {
        guard reachability.online, server.client != nil else { return }
        askOwned()
    }

    /// The box changed (Search.tsx's typing effect).
    func type(_ typed: String) {
        let clamped = Self.clamped(typed)
        text = clamped
        guard let effect = state.typed(clamped) else { return }
        // the clocks of the words before let go: a text the library was once late for is late again only by its own
        lateClock?.cancel()
        settling?.cancel()
        settlingMusicBrainz?.cancel()
        askingHeld?.cancel()
        opening = nil
        if effect == .clear {
            letGo()
            return
        }
        if effect == .drop { askingAlbums?.cancel() }
        // words whose answer is in hand already (back to them inside the pause): drawn now - the web's advance runs on
        // every render; nothing is drawn unless the library has settled for the box's words
        draw()
        // the library asked once typing pauses - a keystroke meanwhile starts the pause again
        settling = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchReading.librarySettleMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.settled()
        }
        // MusicBrainz once it pauses longer, three characters at least - unless asked for these words already
        if effect == .settle {
            let words = state.query
            settlingMusicBrainz = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(SearchReading.musicBrainzSettleMs) * 1_000_000)
                guard !Task.isCancelled, let self, self.state.query == words, !self.state.askedForQuery else { return }
                self.askMusicBrainz(view: self.state.view)
                self.draw()
            }
        }
    }

    /// The keyboard's Search (Search.tsx `submitNow`): the library asked now - again after a failure - a kind view's
    /// own, and MusicBrainz with the box read afresh; a list already drawn for words MusicBrainz hadn't been asked for,
    /// or with a failure in it, drawn afresh. The pause's own ask, if it is still to come, finds them asked.
    func submitted() {
        guard !state.query.isEmpty else { return }
        if state.submitted() { armLibraryLate() }
        askLibrary()
        askKind()
        askMusicBrainz(view: state.view, reread: true)
        draw()
    }

    /// A chip, See all, Back to All (Search.tsx `choose`): Back to All drawn whole from what is in hand; MusicBrainz
    /// asked for the kinds the view needs that nobody has asked, when it was asked for these words.
    func choose(_ view: SearchView) {
        guard state.choose(view) else { return }
        Notice.announce(SearchWords.view(view))
        guard !state.query.isEmpty else { return }
        if view != .all, state.libraryAskedForQuery {
            // the words asked already: the kind's own at once (else with the pause)
            askKind()
        }
        if state.askedForQuery { askMusicBrainz(view: view) }
        draw()
    }

    /// Try again under the library's failure (at the top, or in its late place): asked again, and drawn afresh
    /// following the moments.
    func tryAgain() {
        state.tryAgain()
        askLibrary()
        armLibraryLate()
        draw()
    }

    /// Try again under MusicBrainz's failure in All (a kind's slot, the all-failed foot): drawn afresh, the failed
    /// asked again.
    func tryMusicBrainzAgain() {
        state.tryMusicBrainzAgain()
        askMusicBrainz(view: .all)
        draw()
    }

    /// Try again under a kind view's failure - its library's.
    func tryKindAgain() {
        askKind()
    }

    /// Try again under a kind view's MusicBrainz failure.
    func tryKindMusicBrainzAgain() {
        askMusicBrainz(view: state.view)
    }

    /// "Show 3 from your library": the list drawn afresh, whole, the library in it.
    func showLibrary() {
        state.showLibrary()
        draw()
    }

    /// A kind view's "Show N from your library".
    func showKindLibrary() {
        state.showKindLibrary()
    }

    /// "Show 2 more albums": a folded kind's rows opened in place.
    func showFolded(_ kind: SearchKind) {
        state.showFolded(kind)
    }

    /// More from your library: that kind's next page.
    func more() {
        guard reachability.online, let client = server.client, let ask = state.askingMore() else { return }
        moreFailure = nil
        let epoch = self.epoch
        let personal = self.personal
        askingMore = Task { [weak self] in
            do {
                let found = try await client.searchLibrary(ask.text, counts: SearchPacing.chip(ask.kind), offsets: ask.offsets)
                guard let self, epoch == self.epoch else { return }
                if let count = self.state.moreAnswered(ask.token, found) {
                    Notice.announce(SearchWords.moreSaid(count, ask.kind, personal: personal))
                }
            } catch {
                guard let self, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                self.state.moreFailed(ask.token)
                self.moreFailure = error
            }
        }
    }

    /// deadwax is back, or Navidrome found: what wasn't asked for the words, asked now - the library's failure or skip
    /// asked again and its answer drawn in its place (SearchState.resumed), a kind view's failed or skipped own again,
    /// MusicBrainz for words its pause would have asked while deadwax was away (a failure of it keeps its Try again).
    func resumed() {
        guard !state.query.isEmpty, reachability.online else { return }
        if navidromeAway == nil { state.resumed() }
        // the library asked for the words now - again after a failure or a skip, or for the first time, typed while
        // deadwax was away (no late clock ran then) - or still out with its clock let go offline: the late clock armed,
        // as the pause's own ask has it
        let asks = navidromeAway == nil && (state.wantsLibrary || state.libraryUnplaced)
        askLibrary()
        if asks { armLibraryLate() }
        askKind()
        // MusicBrainz for words long enough to have been asked by the pause, had deadwax been there
        if !state.askedForQuery, SearchReading.asksMusicBrainzBySettling(state.query) {
            askMusicBrainz(view: state.view)
        }
        draw()
    }

    /// A MusicBrainz album's row (Search.tsx `openAnyGroup`): one the library holds opens yours - Navidrome's album for
    /// a release of it you hold, asked of the id bridge in turn (the row busy meanwhile) - else, or Navidrome not having
    /// it, or not answering, the album you don't have, which says it is held. The answer opens only on the list it was
    /// tapped on: the Search tab still shown, its pages as they were, Now Playing not over it - anything else (another
    /// row opened, another tab, Now Playing) drops it (the web's standDown, which lets its heldRequests go).
    func open(_ group: ReleaseGroup) {
        askingHeld?.cancel()
        let releases = SearchAlbums.heldReleases(ownedIndex, group.id)
        guard !releases.isEmpty, reachability.online, let client = server.client else {
            opening = nil
            navigation.open(.group(GroupRoute(group)))
            return
        }
        opening = group.id
        let epoch = self.epoch
        let tab = navigation.tab
        let pages = navigation.search
        askingHeld = Task { [weak self] in
            let found = try? await client.navidromeAlbum(releases: releases)
            guard !Task.isCancelled, let self, epoch == self.epoch, self.opening == group.id else { return }
            self.opening = nil
            let navigation = self.navigation
            guard navigation.tab == tab, navigation.search == pages, !navigation.nowPlayingShown else { return }
            if let id = found {
                // drawn with its credited artist, so the album page's artist line holds its place as it loads
                let artist = Credits.name(group.artistCredit)
                self.navigation.open(.album(AlbumRoute(id: id, name: group.title, artist: artist.isEmpty ? nil : artist)))
            } else {
                self.navigation.open(.group(GroupRoute(group)))
            }
        }
    }

    /// The list a held album's row was tapped on stopped showing (another tab, a page pushed or popped, Now Playing):
    /// the id bridge's ask let go, so its answer opens nothing on whatever shows now.
    func standDown() {
        askingHeld?.cancel()
        askingHeld = nil
        opening = nil
    }

    /// A new person: everything let go.
    func reset() {
        epoch += 1
        letGo()
        text = ""
        state = SearchState()
        owned = nil
        ownedIndex = nil
        ownedTag = nil
        askingOwned = false
    }

    // MARK: the asks

    /// The pause passed: All's search3 for the words, a kind view's own, the library's late clock - and the list drawn,
    /// should the words' answer be in hand already.
    private func settled() {
        askLibrary()
        askKind()
        armLibraryLate()
        draw()
    }

    /// All's search3, when the state wants it for the words.
    private func askLibrary() {
        guard state.wantsLibrary, reachability.online, let client = server.client else { return }
        if navidromeAway != nil {
            state.librarySkipped()
            draw()
            return
        }
        asking?.cancel()
        let token = state.askingLibrary()
        let words = state.query
        let epoch = self.epoch
        asking = Task { [weak self] in
            do {
                let found = try await client.searchLibrary(words, counts: SearchPacing.all)
                guard let self, epoch == self.epoch else { return }
                guard self.state.libraryAnswered(token, words, found) else { return }
                self.prefetch(self.state.albumsWanted(words, found, artistList: self.artists.list, marks: self.marks),
                              library: token)
                self.draw()
            } catch {
                guard let self, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                guard self.state.libraryFailed(token, words) else { return }
                self.failure = error
                self.draw()
            }
        }
    }

    /// The library settles by `libraryLateMs` from now, or the list is drawn as if it found nothing, a place kept at
    /// its top for it. Only while deadwax can be reached - armed and run out: offline nothing is asked, so a list drawn
    /// without the library would be blank (its MusicBrainz part left out) where "Search works once deadwax is back."
    /// stands, and once back its answer would sit behind Show them. `resumed()` arms it as it asks.
    private func armLibraryLate() {
        guard !state.query.isEmpty, reachability.online else { return }
        lateClock?.cancel()
        let term = state.armingLibraryLate()
        lateClock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.libraryLateMs) * 1_000_000)
            guard !Task.isCancelled, let self, self.reachability.online else { return }
            if self.state.libraryLatePassed(term) { self.draw() }
        }
    }

    /// A kind view's own search3, when the view wants it for its words - and its late clock, once per view and words
    /// for a view that asks MusicBrainz.
    private func askKind() {
        guard state.wantsKind, reachability.online, let client = server.client else { return }
        if navidromeAway != nil {
            state.kindSkipped()
            return
        }
        guard let ask = state.askingKind() else { return }
        askingKind?.cancel()
        askingMore?.cancel()
        kindFailure = nil
        moreFailure = nil
        let words = state.query
        let epoch = self.epoch
        if ask.armLate { armKindLate(words, ask.kind) }
        askingKind = Task { [weak self] in
            do {
                let found = try await client.searchLibrary(words, counts: SearchPacing.chip(ask.kind))
                guard let self, epoch == self.epoch, self.state.kindAnswered(ask.token, found) else { return }
                if ask.kind == .songs {
                    // a Songs view's answer asks its own five albums, so its songs play
                    let ready = self.state.ready
                    self.prefetch(SearchPacing.albumsToPrefetch(found.songs).filter { ready[$0] == nil }, kind: ask.token)
                }
            } catch {
                guard let self, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                if self.state.kindFailed(ask.token) { self.kindFailure = error }
            }
        }
    }

    /// A kind view's library settles by `libraryLateMs`, or MusicBrainz's rows draw under a place kept at its top - one
    /// clock per view and words (an ask again keeps the one running).
    private func armKindLate(_ words: String, _ kind: SearchKind) {
        let key = "\(words)\n\(kind.rawValue)"
        if let running = kindLateClock, running.key == key { return }
        kindLateClock?.task.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.libraryLateMs) * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.kindLateClock?.key == key { self.kindLateClock = nil }
            self.state.kindLatePassed(words, kind)
        }
        kindLateClock = (key, task)
    }

    /// MusicBrainz asked for what the view needs (Search.tsx `askMusicBrainz`, slice 2's albums): `/library/owned`
    /// beside it, the albums asked unless in hand or on their way - the plain words again when a fielded read finds
    /// nothing - then a moment's wait for `/library/owned` (`ownedWaitMs`), so what you hold is left out before they
    /// draw. The run's cap counts from the ask, in All.
    private func askMusicBrainz(view: SearchView, reread: Bool = false) {
        guard reachability.online, let client = server.client else { return }
        let words = state.query
        askOwned()
        let ask = state.askingMusicBrainz(words, view: view, reread: reread)
        syncCap()
        guard let ask else { return }
        askingAlbums?.cancel()
        let epoch = self.epoch
        let admin = server.access.seesDetail
        askingAlbums = Task { [weak self] in
            do {
                var query = ask.first
                var found = try await client.fullySearch(query)
                if found.releaseGroups.isEmpty, let fallback = ask.fallback, !fallback.isEmpty {
                    guard let self, epoch == self.epoch, self.state.isNewestAlbums(ask.token) else { return }
                    query = fallback
                    found = try await client.fullySearch(query)
                }
                await self?.waitForOwned()
                guard !Task.isCancelled, let self, epoch == self.epoch else { return }
                guard self.state.albumsAnswered(ask, found, query: query, index: self.ownedIndex) else { return }
                self.draw()
            } catch {
                guard let self, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                guard self.state.albumsFailed(ask, MBFailure.of(error, admin: admin)) else { return }
                self.draw()
            }
        }
    }

    /// `/library/owned`'s ask in flight, waited on for `ownedWaitMs` at most.
    private func waitForOwned() async {
        let step: UInt64 = 50_000_000
        var waited: UInt64 = 0
        let limit = UInt64(SearchPacing.ownedWaitMs) * 1_000_000
        while askingOwned, waited < limit, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: step)
            waited += step
        }
    }

    /// The run's cap: `resultsWaitMs` timed for a run MusicBrainz was asked for, its cap not passed - then drawn.
    private func syncCap() {
        let run = state.run
        guard run.asked, !run.capPassed, capClock?.run != run.id else { return }
        capClock?.task.cancel()
        let id = run.id
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.resultsWaitMs) * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.state.capPassed(run: id) { self.draw() }
        }
        capClock = (id, task)
    }

    /// The albums of songs found, so a song's tap plays - kept for the box's life (the ask they were asked beside the
    /// newest).
    private func prefetch(_ ids: [String], library token: Int? = nil, kind kindToken: Int? = nil) {
        guard let client = server.client else { return }
        let epoch = self.epoch
        for id in ids {
            prefetching.append(Task { [weak self] in
                guard let album = try? await client.album(id: id) else { return }
                guard let self, epoch == self.epoch else { return }
                self.state.albumReady(album, library: token, kind: kindToken)
            })
        }
    }

    /// `/library/owned`, with its ETag: kept in memory for the person; a failure keeps what is in hand, quietly. Its
    /// album artists are names the box is read against (the state's `ownedArtists`).
    private func askOwned() {
        guard !askingOwned, let client = server.client else { return }
        askingOwned = true
        let epoch = self.epoch
        let tag = ownedTag
        Task { [weak self] in
            let fetched = try? await client.owned(ifNoneMatch: tag)
            guard let self, epoch == self.epoch else { return }
            self.askingOwned = false
            guard case .fresh(let answer, let etag)? = fetched else { return }
            self.ownedTag = etag
            if answer != self.owned {
                self.owned = answer
                self.ownedIndex = OwnedIndex(answer.albums)
                self.state.ownedArtists = answer.artists
            }
        }
    }

    /// The All view's next draw, when the state has one - announced as it draws; then Behind noted and the cap timed,
    /// as the web's layout effect does after every draw.
    private func draw() {
        if let drawing = state.advance(artistList: artists.list, marks: marks) {
            let drawn = drawing.drawn
            // the failure's words kept while a list drawn with it stands - let go only as one without it takes its place
            if !drawn.failed && state.libraryLateSlot != .failed { failure = nil }
            if drawn.nothing {
                Notice.announce(SearchWords.nothing(.all, drawn.text))
            } else if !drawing.said.isEmpty {
                Notice.announce(drawing.said)
            }
        }
        state.noteBehind()
        syncCap()
    }

    /// Every ask let go - the box emptied, or a new person.
    private func letGo() {
        settling?.cancel()
        settlingMusicBrainz?.cancel()
        asking?.cancel()
        askingKind?.cancel()
        askingMore?.cancel()
        askingAlbums?.cancel()
        askingHeld?.cancel()
        lateClock?.cancel()
        kindLateClock?.task.cancel()
        kindLateClock = nil
        capClock?.task.cancel()
        capClock = nil
        for task in prefetching { task.cancel() }
        prefetching = []
        failure = nil
        kindFailure = nil
        moreFailure = nil
        opening = nil
    }

    /// At most `SearchReading.maxCharacters` - counted as the server's `q` counts them, by Unicode scalar.
    static func clamped(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard scalars.count > SearchReading.maxCharacters else { return text }
        return String(String.UnicodeScalarView(scalars.prefix(SearchReading.maxCharacters)))
    }
}
