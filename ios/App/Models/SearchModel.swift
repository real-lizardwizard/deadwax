import DeadwaxCore
import Foundation
import Observation

/// Search, your library's half (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 2.6-2.9; the web's app/Search.tsx):
/// Core's SearchState kept here, and the requests it says to make - All's search3 once typing pauses
/// (`SearchReading.librarySettleMs`) or at once on the keyboard's Search, a kind view's own beside it, More by offset,
/// the albums a song plays from, and `/library/owned` as Search shows.
///
/// Every rule of when to ask and what to draw is Core's (SearchState, SearchList); this makes the asks, keeps their
/// tasks, and tells the state what landed. Only the newest ask's answer counts (the state's tokens), and an ask let go -
/// new words, the box emptied, a new person - is cancelled.
///
/// - The list drawn is announced as it draws (`libraryWords`, or "No results for …"), a chip as it is pressed.
/// - While deadwax can't be reached nothing is asked (2.9); the screen says so for words with nothing drawn, and when
///   deadwax is back what wasn't asked is.
/// - Navidrome known not to be there (the Library's own check, LibraryModel): search3 isn't asked, the library counted
///   as skipped - the gate's words stand above the list.
/// - `/library/owned` (question 6): asked each time Search shows, with its ETag - kept in memory for the person, never
///   on disk; a failure is quiet. Your albums and the library's artists are the Library's own lists, asked as Search
///   shows when not in hand.
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

    private let server: ServerModel
    private let library: LibraryModel
    private let artists: ArtistsModel
    private let reachability: Reachability

    /// One more at every reset: nothing begun for the person before lands after.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var asking: Task<Void, Never>?
    @ObservationIgnored private var askingKind: Task<Void, Never>?
    @ObservationIgnored private var askingMore: Task<Void, Never>?
    @ObservationIgnored private var prefetching: [Task<Void, Never>] = []
    @ObservationIgnored private var ownedTag: String?
    @ObservationIgnored private var askingOwned = false

    init(server: ServerModel, library: LibraryModel, artists: ArtistsModel, reachability: Reachability) {
        self.server = server
        self.library = library
        self.artists = artists
        self.reachability = reachability
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

    // MARK: what the screen tells it

    /// Search shows (the tab picked, the app back in front on it): `/library/owned` asked again (a 304 unless the
    /// library changed), and your albums and the library's artists when not in hand.
    func shown() {
        guard reachability.online, server.client != nil else { return }
        askOwned()
        if personal, library.albums(.yours) == nil {
            Task { await library.load(.yours) }
        }
        if artists.list == nil {
            Task { await artists.ask() }
        }
        if library.navidrome == nil, !library.checkingNavidrome {
            Task { await library.checkNavidrome() }
        }
    }

    /// The box changed.
    func type(_ typed: String) {
        let clamped = Self.clamped(typed)
        text = clamped
        let before = state.query
        if state.typed(clamped) {
            letGo()
            return
        }
        guard state.query != before else { return }
        // asked once typing pauses - a keystroke meanwhile starts the pause again
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchReading.librarySettleMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.settled()
        }
    }

    /// The keyboard's Search: asked now - again after a failure - and the list drawn afresh once it lands.
    func submitted() {
        settling?.cancel()
        state.submitted()
        askLibrary()
        askKind()
    }

    /// A chip, See all, Back to All.
    func choose(_ view: SearchView) {
        guard state.choose(view) else { return }
        Notice.announce(SearchWords.view(view))
        if view == .all {
            // drawn afresh from what is in hand - your own act
            draw()
        } else if state.libraryAskedForQuery {
            // the words asked already: the kind's own at once (else with the pause)
            askKind()
        }
    }

    /// Try again under All's failure: asked again, and drawn afresh.
    func tryAgain() {
        state.tryAgain()
        askLibrary()
    }

    /// Try again under a kind view's failure.
    func tryKindAgain() {
        askKind()
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

    /// Deadwax is back, or Navidrome found: what wasn't asked for the words, asked now - a library skipped while
    /// Navidrome wasn't there, again.
    func resumed() {
        guard !state.query.isEmpty, reachability.online else { return }
        if state.library == .skipped, navidromeAway == nil { state.tryAgain() }
        if state.kindShown?.state == .skipped, navidromeAway == nil { askKind() }
        askLibrary()
        askKind()
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

    /// The pause passed: All's search3 for the words, and a kind view's own.
    private func settled() {
        askLibrary()
        askKind()
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
                self.failure = nil
                self.prefetch(self.state.albumsWanted(words, found, ownedArtists: self.owned?.artists ?? [],
                                                      artistList: self.artists.list, marks: self.marks),
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

    /// A kind view's own search3, when the view wants it for its words.
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

    /// `/library/owned`, with its ETag: kept in memory for the person; a failure keeps what is in hand, quietly.
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
            }
        }
    }

    /// The All view's next draw, when the state has one - announced as it draws.
    private func draw() {
        guard let drawn = state.advance(ownedArtists: owned?.artists ?? [], artistList: artists.list, marks: marks) else {
            return
        }
        if drawn.nothing {
            Notice.announce(SearchWords.nothing(.all, drawn.text))
        } else {
            let said = drawn.said(personal: personal)
            if !said.isEmpty { Notice.announce(said) }
        }
    }

    /// Every ask let go - the box emptied, or a new person.
    private func letGo() {
        settling?.cancel()
        asking?.cancel()
        askingKind?.cancel()
        askingMore?.cancel()
        for task in prefetching { task.cancel() }
        prefetching = []
        failure = nil
        kindFailure = nil
        moreFailure = nil
    }

    /// At most `SearchReading.maxCharacters` - counted as the server's `q` counts them, by Unicode scalar.
    static func clamped(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard scalars.count > SearchReading.maxCharacters else { return text }
        return String(String.UnicodeScalarView(scalars.prefix(SearchReading.maxCharacters)))
    }
}
