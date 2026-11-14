import Foundation

/// Search's state for one person (Phase 5, slices 1 and 2 - notes/ios-specs/phase5-search.md 2.6-2.7; the web's
/// app/Search.tsx: its `library`, `musicbrainz`, `drawn`, `kindLibrary`, `ready`, `view`, runs, `lateFor` and Behind):
/// what the box says, what has been asked for which words, the list drawn - frozen once drawn - and a kind view's own.
/// Pure: the app's SearchModel makes the requests and keeps the clocks, and tells this what landed and when a clock ran
/// out; every rule of when to ask and when to draw is here, tested on Linux.
///
/// - The box's words, trimmed (`query`). Typing other words starts a new run: the list drawn stays until the library
///   settles for the new words (or is `libraryLateMs` late), then theirs takes its place. An empty box lets everything
///   go.
/// - All's search3 is asked once per words (`wantsLibrary`) - again only after a failure, Try again, or the keyboard's
///   Search on a failure; only the newest ask's answer counts (`libraryAnswered`'s token).
/// - MusicBrainz's albums are asked once typing pauses longer (`musicBrainzSettleMs`, three characters at least), or on
///   the keyboard's Search (`askingMusicBrainz`); the words it was asked for are `asked`, read as `askedPlan` was.
/// - The list is drawn in its moments (`advance`), only in the All view: Top results' decided picks first, the sections
///   in the asking line's place once MusicBrainz answers or `resultsWaitMs` passes, a late kind landing in its slot.
///   A chip, See all and Back to All draw afresh.
/// - A kind view asks its own (`wantsKind`), kept for its words and kind; More by offset (`askingMore`); the Albums view
///   MusicBrainz's albums below its own (`kindView`).
/// - The albums asked for so a song plays (`ready`), kept for the box's life: cleared with the box.
public struct SearchState: Sendable {
    /// Where All's search3 stands for the words it was last asked for (`libraryText`).
    public enum Library: Sendable, Equatable {
        case asking
        case answered(LibraryResults)
        case failed
        /// Navidrome known not to be there: not asked, counted as finding nothing.
        case skipped
    }

    /// MusicBrainz's albums for some words (Search.tsx `Musicbrainz`): `key` the words and the query a view asks.
    public enum Albums: Sendable, Equatable {
        case idle
        case searching(text: String, key: String)
        case done(AlbumsFound)
        case failed(text: String, key: String, failure: MBFailure)

        public var key: String? {
            switch self {
            case .idle: return nil
            case .searching(_, let key), .failed(_, let key, _): return key
            case .done(let found): return found.key
            }
        }
    }

    /// MusicBrainz's albums answer: its groups in the order drawn (the studio clause's in studioOrder), the block shown
    /// (the groups less those held, worked out once as it landed), what MusicBrainz was asked (`query` - the words
    /// typed, when a fielded read found nothing), the studio clause on.
    public struct AlbumsFound: Sendable, Equatable {
        public let text: String
        public let key: String
        public let plan: SearchPlan
        public let groups: [ReleaseGroup]
        public let shown: [ReleaseGroup]
        public let query: String
        public let studio: Bool
        public let count: Int?
    }

    /// An ask of MusicBrainz's albums, as the model makes it: the first query, and the words to ask again when a
    /// fielded read finds nothing (`fallback`).
    public struct AlbumsAsk: Sendable, Equatable {
        public let token: Int
        public let text: String
        public let key: String
        public let plan: SearchPlan
        public let first: String
        public let studio: Bool
        /// The words typed, single-spaced - asked when `first` finds nothing and the reading wasn't free words.
        public let fallback: String?
    }

    /// A run of a text's moments (Search.tsx `Run`): new words, Try again, Back to All - the list is drawn once per run.
    /// `phantoms`: decided picks first (a redraw draws whole); `asked` MusicBrainz asked for the run, `capPassed`
    /// `resultsWaitMs` since; `behind` Behind applies to it; `outcome` what its asks came to.
    public struct Run: Sendable, Equatable {
        public let id: Int
        public let text: String
        public let phantoms: Bool
        public fileprivate(set) var asked: Bool
        public fileprivate(set) var capPassed: Bool
        public let behind: Bool
        public fileprivate(set) var outcome: SearchList.Outcome?
    }

    /// A draw: the list, and what is announced of it ("" for nothing).
    public struct Drawing: Sendable, Equatable {
        public let drawn: SearchList.Drawn
        public let said: String
    }

    /// The library's place at the top of a list drawn without it (`libraryLate`), as it stands.
    public enum LateSlot: Sendable, Equatable {
        /// "Searching your library…"
        case asking
        /// Its failure, and Try again.
        case failed
        /// Navidrome turned out not to be there: it wasn't searched.
        case skipped
        /// Answered with this many: "Show N from your library".
        case show(Int)
        /// Answered with nothing: "Nothing in your library for …".
        case nothing
    }

    /// The box's words, trimmed.
    public private(set) var query = ""
    public private(set) var view: SearchView = .all
    /// The words All's search3 was last asked or answered for, and where it stands.
    public private(set) var libraryText: String?
    public private(set) var library: Library?
    /// The All view as drawn - frozen.
    public private(set) var drawn: SearchList.Drawn?
    /// A kind view's own search3.
    public private(set) var kind: KindLibrary?
    /// The albums in hand so a song's tap plays, by id.
    public private(set) var ready: [String: Album] = [:]
    /// MusicBrainz's albums.
    public private(set) var albums: Albums = .idle
    /// The words MusicBrainz was asked for - nil when nothing is, or dropped.
    public private(set) var asked: String?
    /// The run being drawn.
    public private(set) var run = Run(id: 0, text: "", phantoms: true, asked: false, capPassed: false, behind: false,
                                      outcome: nil)
    /// Behind (`nextBehind`), kept for the person's life.
    public private(set) var behind = false
    /// The words the library was `libraryLateMs` late for.
    public private(set) var lateFor: String?
    /// A kind view's library late (its words and kind, `"\(text)\n\(kind)"`), and Show them pressed for it.
    public private(set) var kindLateFor: String?
    public private(set) var kindShownFor: String?
    /// `/library/owned`'s album artists - names the box is read against.
    public var ownedArtists: [String] = []

    /// How the box was read when MusicBrainz was asked for `asked` - kept, so the answers asked stay in hand.
    private var askedPlan: (text: String, plan: SearchPlan)?
    /// The words All's search3 was asked for (`libraryAsked`) - nil after a failure, so it is asked again.
    private var libraryAsked: String?
    /// Only the newest ask's answer counts: All's, a kind view's (its More's too), MusicBrainz's albums'.
    private var allToken = 0
    private var kindToken = 0
    private var albumsToken = 0

    public init() {}

    // MARK: the box and the view

    /// The box changed: its words trimmed (Search.tsx's typing effect). What MusicBrainz's half does
    /// (`musicBrainzOnTyping`) - `.clear` when it emptied: everything let go, the view back to All (the caller calls off
    /// what it asked); nil when the words didn't change.
    @discardableResult
    public mutating func typed(_ text: String) -> SearchReading.OnTyping? {
        let next = JSText.trim(text)
        guard !WebText.same(next, query) else { return nil }
        query = next
        let effect = SearchReading.musicBrainzOnTyping(next, asked: asked)
        //? a text the library was once late for is late again only by its own clock, never by an old one
        lateFor = nil
        if effect == .clear {
            libraryText = nil
            library = nil
            libraryAsked = nil
            drawn = nil
            kind = nil
            kindLateFor = nil
            kindShownFor = nil
            ready = [:]
            view = .all
            allToken += 1
            kindToken += 1
            dropMusicBrainz()
            startRun("", phantoms: true)
            return .clear
        }
        if effect == .drop { dropMusicBrainz() }
        startRun(next, phantoms: true)
        //? back to exactly the words MusicBrainz was asked for: nothing asked again, but the run's cap counts from here
        if effect == .keep { armCap(next) }
        return effect
    }

    /// A chip, See all, Back to All (Search.tsx `choose`). Back to All is a run of its own, drawn whole at once. True
    /// when the view changed - the caller then asks a kind's own (`libraryAskedForQuery`) and MusicBrainz for the kinds
    /// the view needs (`askedForQuery`).
    @discardableResult
    public mutating func choose(_ next: SearchView) -> Bool {
        guard next != view else { return false }
        view = next
        guard !query.isEmpty else { return true }
        if let wanted = next.kind, let mine = kind, WebText.same(mine.text, query), mine.kind == wanted,
           mine.state == .answered {
            //? back to a view whose library has answered: drawn from what is in hand, not behind its late place
            kindShownFor = Self.lateKey(query, wanted)
        }
        if next == .all { startRun(query, phantoms: false) }
        return true
    }

    /// The library's own Try again (its failure at the top, or in its place): asked again, and drawn afresh following
    /// the moments - the cap counting from here for words MusicBrainz was asked for (`tryLibraryAgain`). The caller asks
    /// and arms the library's late clock.
    public mutating func tryAgain() {
        libraryAsked = nil
        startRun(query, phantoms: true, applyBehind: false)
        if asked.map({ WebText.same($0, query) }) == true { armCap(query) }
    }

    /// MusicBrainz's Try again in All (a kind's slot, the all-failed foot): drawn afresh, the failed asked again - the
    /// caller asks (`askingMusicBrainz(view: .all)`).
    public mutating func tryMusicBrainzAgain() {
        startRun(query, phantoms: true, applyBehind: false)
    }

    /// deadwax back, or Navidrome found again (Search.tsx's status effect): the words' library, failed or skipped, is
    /// asked again - and a list this run drew with the failure in it, or without the library, starts a new run drawn
    /// whole, so the new answer is drawn in its place. True when the library is to be asked again (and its late clock
    /// armed).
    @discardableResult
    public mutating func resumed() -> Bool {
        guard !query.isEmpty, let libraryText, WebText.same(libraryText, query),
              library == .failed || library == .skipped else { return false }
        libraryAsked = nil
        if let drawn, drawn.run == run.id, WebText.same(drawn.text, query), !drawn.libraryLate {
            startRun(query, phantoms: false)
        }
        return true
    }

    /// The keyboard's Search (Search.tsx `submitNow`): words MusicBrainz hadn't been asked for - or read anew since -
    /// their list already drawn: drawn afresh; a list drawn with a failure in it: the failed asked again and the list
    /// drawn afresh. The caller then asks the library (`wantsLibrary`), arms its late clock when this answers true,
    /// asks a kind's own, and asks MusicBrainz with the box read afresh (`askingMusicBrainz(reread: true)`).
    @discardableResult
    public mutating func submitted() -> Bool {
        guard !query.isEmpty else { return false }
        let kept = askedPlanFor(query)
        let reading = readBox(query)
        let reread = kept != nil && reading != nil && (kept?.kind != reading?.kind || kept?.query != reading?.query)
        let drawnNow = drawn.map { WebText.same($0.text, query) && $0.run == run.id } ?? false
        let wasAsked = asked.map { WebText.same($0, query) } ?? false
        let fresh = drawnNow && ((!wasAsked && drawn?.musicBrainz != true) || reread)
        let plan = kept ?? reading
        let libraryFailed = libraryText.map { WebText.same($0, query) } == true && library == .failed
        let kindFailed = plan.map { (plan: SearchPlan) -> Bool in
            Self.wantedKinds(plan, view: .all).contains { (kind: SearchKind) -> Bool in
                guard case .failed(_, let key, _) = albums else { return false }
                return key == Self.keyFor(kind, query, plan, view: .all)
            }
        } ?? false
        let retry = !fresh && drawnNow && view == .all && (libraryFailed || kindFailed)
        if fresh { startRun(query, phantoms: true) } else if retry { startRun(query, phantoms: true, applyBehind: false) }
        if libraryFailed { libraryAsked = nil }
        return retry && libraryFailed
    }

    // MARK: the run

    private mutating func startRun(_ text: String, phantoms: Bool, applyBehind: Bool = true) {
        run = Run(id: run.id + 1, text: text, phantoms: phantoms, asked: false, capPassed: false,
                  behind: applyBehind && behind, outcome: nil)
    }

    /// The cap counts from now for the run of these words, MusicBrainz asked for them (`armCap`): the model times
    /// `resultsWaitMs` for a run marked asked whose cap hasn't passed (`capPassed(run:)`).
    private mutating func armCap(_ term: String) {
        guard WebText.same(run.text, term), !run.asked else { return }
        run.asked = true
    }

    /// `resultsWaitMs` passed for run `id`. True when it is still the run.
    @discardableResult
    public mutating func capPassed(run id: Int) -> Bool {
        guard run.id == id, !run.capPassed else { return false }
        run.capPassed = true
        return true
    }

    /// How a run's MusicBrainz asks came to an end - for Behind (`noteOutcome`; a superseded run counts for nothing).
    private mutating func noteOutcome(_ id: Int, _ outcome: SearchList.Outcome) {
        guard run.id == id, run.outcome == nil else { return }
        behind = SearchList.nextBehind(behind, outcome)
        run.outcome = outcome
    }

    /// Behind, after a draw (Search.tsx's layout effect): a run whose every kind asked answered in time ends it; one
    /// whose cap passed with a kind out, or whose kind failed as MusicBrainz away, turns it on.
    public mutating func noteBehind() {
        guard run.asked, run.outcome == nil, view == .all, WebText.same(run.text, query),
              let plan = planFor(run.text) else { return }
        let wanted = Self.wantedKinds(plan, view: .all)
        let out = SearchList.lateKinds(wanted) { inHand($0, run.text, plan, view: .all) }
        let failures = wanted.compactMap { (kind: SearchKind) -> MBFailure? in failure(kind, run.text, plan, view: .all) }
        if failures.contains(where: { !$0.refused }) {
            noteOutcome(run.id, .failed)
        } else if run.capPassed && !out.isEmpty {
            noteOutcome(run.id, .late)
        } else if out.isEmpty && !wanted.isEmpty && !run.capPassed {
            let refusedAll = failures.count == wanted.count && failures.allSatisfy(\.refused)
            noteOutcome(run.id, refusedAll ? .refused : .inTime)
        }
    }

    // MARK: All's search3

    /// Whether All's search3 is to be asked for the words now (the pause passed, the keyboard's Search, Try again).
    public var wantsLibrary: Bool {
        !query.isEmpty && libraryAsked.map { !WebText.same($0, query) } ?? true
    }

    /// All's ask begins for the words: its token. What was answered for the same words stays until the new answer.
    public mutating func askingLibrary() -> Int {
        libraryAsked = query
        allToken += 1
        if !(libraryText.map { WebText.same($0, query) } ?? false) || !isAnswered {
            libraryText = query
            library = .asking
        }
        return allToken
    }

    /// Navidrome known not to be there: the library not asked for the words, counted as finding nothing.
    public mutating func librarySkipped() {
        libraryAsked = query
        allToken += 1
        libraryText = query
        library = .skipped
    }

    /// Whether `token` is All's newest ask.
    public func isNewestLibrary(_ token: Int) -> Bool { token == allToken }

    /// All's answer for `text` landed: kept when it is the newest ask's.
    @discardableResult
    public mutating func libraryAnswered(_ token: Int, _ text: String, _ results: LibraryResults) -> Bool {
        guard token == allToken else { return false }
        libraryText = text
        library = .answered(results)
        return true
    }

    /// All's ask for `text` failed: kept when it is the newest ask's - and asked again by the next Search, Try again.
    @discardableResult
    public mutating func libraryFailed(_ token: Int, _ text: String) -> Bool {
        guard token == allToken else { return false }
        libraryAsked = nil
        libraryText = text
        library = .failed
        return true
    }

    /// search3's last answer, whatever its words (Search.tsx `results`) - what the marks read the albums in hand from.
    public var results: LibraryResults? {
        if case .answered(let results)? = library { return results }
        return nil
    }

    /// The answer for the words in the box - nil while it is another's, asked, failed or skipped.
    public var resultsForQuery: LibraryResults? {
        guard let libraryText, WebText.same(libraryText, query) else { return nil }
        return results
    }

    /// The library has settled for the words: answered, failed, or not asked (Navidrome not there).
    public var settled: Bool { librarySettled(query) }

    /// The words' library is yet to settle and no place is kept for it - not asked yet (typed while deadwax was away),
    /// or asked and its late clock let go as it ran (the phone went offline): the model arms the late clock again as it
    /// resumes, so the list is drawn with the library or a place for it, never without either.
    public var libraryUnplaced: Bool {
        !query.isEmpty && !librarySettled(query) && lateFor.map { WebText.same($0, query) } != true
    }

    private func librarySettled(_ term: String) -> Bool {
        guard let libraryText, WebText.same(libraryText, term), let library else { return false }
        return library != .asking
    }

    private var isAnswered: Bool {
        if case .answered? = library { return true }
        return false
    }

    /// The library's late clock is armed for the words (`armLibraryLate`): a place it was late for, for them, let go.
    /// The model times `libraryLateMs`, then calls `libraryLatePassed`.
    public mutating func armingLibraryLate() -> String {
        if lateFor.map({ WebText.same($0, query) }) == true { lateFor = nil }
        return query
    }

    /// `libraryLateMs` passed for `term`: the list may be drawn without the library, a place kept for it - only if it
    /// hasn't settled. True when it is late now.
    @discardableResult
    public mutating func libraryLatePassed(_ term: String) -> Bool {
        guard WebText.same(term, query), !librarySettled(term) else { return false }
        lateFor = term
        return true
    }

    /// "Show N from your library": the list drawn afresh, whole, the library in it (`showLibrary`).
    public mutating func showLibrary() {
        lateFor = nil
        startRun(query, phantoms: false)
    }

    /// The library's place at the top of the list drawn without it, as it stands - nil when there is none.
    public var libraryLateSlot: LateSlot? {
        guard let drawn, drawn.libraryLate else { return nil }
        guard let libraryText, WebText.same(libraryText, drawn.text), let library else { return .asking }
        switch library {
        case .asking: return .asking
        case .failed: return .failed
        case .skipped: return .skipped
        case .answered(let results):
            let total = results.artists.count + results.albums.count + results.songs.count
            return total > 0 ? .show(total) : .nothing
        }
    }

    // MARK: MusicBrainz's albums

    /// The kinds a view asks MusicBrainz for, by the reading (`wantedKinds`): slice 2 asks albums alone - All's and the
    /// Albums view's; artists and songs are slice 3's.
    public static func wantedKinds(_ plan: SearchPlan, view: SearchView) -> [SearchKind] {
        view == .all || view == .albums ? [.albums] : []
    }

    /// What a kind is asked for these words, read this way, in this view (`keyFor`) - nil for not asked.
    public static func keyFor(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view: SearchView) -> String? {
        guard kind == .albums, view == .all || view == .albums else { return nil }
        return "\(term)\nalbums:\(view == .albums ? plan.query : SearchAlbums.allAlbumsQuery(plan).query)"
    }

    /// Whether MusicBrainz is drawn for these words (`drawnMusicBrainz`): asked for them, or long enough to be.
    public func drawnMusicBrainz(_ term: String) -> Bool {
        (asked.map { WebText.same($0, term) } ?? false) || SearchReading.asksMusicBrainzBySettling(term)
    }

    /// Whether MusicBrainz was asked for the words in the box - a chip then asks the kinds its view needs at once.
    public var askedForQuery: Bool { asked.map { WebText.same($0, query) } ?? false }

    /// The box read now, against `/library/owned`'s album artists and search3's last artists (`readBox`).
    public func readBox(_ term: String) -> SearchPlan? {
        SearchReading.read(term, names: SearchReading.artistNames(SearchList.knownNames(ownedArtists, results)))
    }

    /// The box as MusicBrainz should be asked (`planFor`): as read when it was asked for these words, else now.
    public func planFor(_ term: String) -> SearchPlan? {
        askedPlanFor(term) ?? readBox(term)
    }

    private func askedPlanFor(_ term: String) -> SearchPlan? {
        guard let asked, WebText.same(asked, term), let askedPlan, WebText.same(askedPlan.text, term) else { return nil }
        return askedPlan.plan
    }

    /// MusicBrainz asked for `term` in `view` (`askMusicBrainz`): the words asked and their reading kept (`reread`: the
    /// keyboard's Search reads the box afresh); the albums asked unless in hand or on their way for the same key - the
    /// ask returned; the cap armed in All.
    public mutating func askingMusicBrainz(_ term: String, view inView: SearchView, reread: Bool = false) -> AlbumsAsk? {
        guard !term.isEmpty, let plan = reread ? readBox(term) : planFor(term) else { return nil }
        asked = term
        askedPlan = (term, plan)
        var ask: AlbumsAsk?
        if Self.wantedKinds(plan, view: inView).contains(.albums),
           let key = Self.keyFor(.albums, term, plan, view: inView), !askedFor(key) {
            let (first, studio) = inView == .albums ? (plan.query, false) : SearchAlbums.allAlbumsQuery(plan)
            albumsToken += 1
            albums = .searching(text: term, key: key)
            ask = AlbumsAsk(token: albumsToken, text: term, key: key, plan: plan, first: first, studio: studio,
                            fallback: plan.kind == .free ? nil : SearchReading.words(term).joined(separator: " "))
        }
        if inView == .all { armCap(term) }
        return ask
    }

    /// Whether `key`'s answer is in hand, or on its way (`askedFor`) - then it isn't asked again.
    private func askedFor(_ key: String) -> Bool {
        switch albums {
        case .idle, .failed: return false
        case .searching(_, let was): return was == key
        case .done(let found): return found.key == key
        }
    }

    /// Whether `token` is the albums' newest ask.
    public func isNewestAlbums(_ token: Int) -> Bool { token == albumsToken }

    /// The albums answered (`query`: what was asked - `ask.first`, or its fallback): the studio clause's in studio order,
    /// and the block shown worked out now from `index` (all of them before it has answered). True when kept.
    @discardableResult
    public mutating func albumsAnswered(_ ask: AlbumsAsk, _ found: FullySearchAnswer, query: String,
                                        index: OwnedIndex?) -> Bool {
        guard ask.token == albumsToken else { return false }
        let studio = ask.studio && query == ask.first
        let groups = studio ? SearchAlbums.studioOrder(found.releaseGroups) : found.releaseGroups
        albums = .done(AlbumsFound(text: ask.text, key: ask.key, plan: ask.plan, groups: groups,
                                   shown: SearchAlbums.notInLibrary(groups, index), query: query, studio: studio,
                                   count: found.count))
        return true
    }

    @discardableResult
    public mutating func albumsFailed(_ ask: AlbumsAsk, _ failure: MBFailure) -> Bool {
        guard ask.token == albumsToken else { return false }
        albums = .failed(text: ask.text, key: ask.key, failure: failure)
        return true
    }

    /// Too few characters now, or the box emptied: MusicBrainz's answers for the longer words let go
    /// (`dropMusicBrainz`) - nothing would ever replace them.
    private mutating func dropMusicBrainz() {
        asked = nil
        askedPlan = nil
        albumsToken += 1
        albums = .idle
    }

    /// Whether a kind's answer for these words, in this view, has landed (`inHandFor`): answered or failed.
    func inHand(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view inView: SearchView) -> Bool {
        guard let key = Self.keyFor(kind, term, plan, view: inView) else { return false }
        switch albums {
        case .idle, .searching: return false
        case .done(let found): return found.key == key
        case .failed(_, let was, _): return was == key
        }
    }

    /// A kind's answer in hand, answered.
    func found(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view inView: SearchView) -> AlbumsFound? {
        guard inHand(kind, term, plan, view: inView), case .done(let found) = albums else { return nil }
        return found
    }

    /// A kind's answer in hand, failed.
    func failure(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view inView: SearchView) -> MBFailure? {
        guard inHand(kind, term, plan, view: inView), case .failed(_, _, let failure) = albums else { return nil }
        return failure
    }

    // MARK: the list drawn

    /// The All view's next draw, if any (Search.tsx `advance`): a new run's moment 1 once the library has settled -
    /// Top results' decided prefix and an asking line, or everything at once when nothing is out, the run is a redraw,
    /// or Behind holds; moment 2 when the sections are ready - Top results completed, the sections in the asking line's
    /// place, a slot for each kind still out; and afterwards a late kind landing in its slot. Nil when nothing new is
    /// drawn.
    public mutating func advance(artistList: [Artist]?, marks: SearchMarks) -> Drawing? {
        guard view == .all, !query.isEmpty, WebText.same(run.text, query) else { return nil }
        let term = run.text
        guard let plan = planFor(term) else { return nil }
        let settled = librarySettled(term) || lateFor.map { WebText.same($0, term) } == true
        let musicBrainz = drawnMusicBrainz(term)
        let wanted = musicBrainz ? Self.wantedKinds(plan, view: .all) : []
        let out = SearchList.lateKinds(wanted) { inHand($0, term, plan, view: .all) }
        let n = SearchPacing.topResults

        guard let was = drawn, was.run == run.id else {
            guard settled else { return nil }
            let libraryLate = !librarySettled(term)
            let withLibrary = !libraryLate && isAnswered
            let results = withLibrary ? self.results : nil
            let pool = poolFor(term, plan, results: results, artistList: artistList, marks: marks)
            let counts = results?.counts ?? [:]
            let found = counts.values.reduce(0, +) > 0
            let whole = out.isEmpty || !run.phantoms || (run.behind && found)
            let isFor = libraryText.map { WebText.same($0, term) } == true
            let failedNow = isFor && library == .failed
            let skippedNow = isFor && library == .skipped
            let runId = run.id
            let candidates = SearchList.candidates(pool, box: term, reading: plan)
            let libraryWords = SearchWords.library(counts, personal: marks.personal)
            func base(top: [SearchRow], topPlace: Bool, sections: [SearchList.Drawn.Section]?, studio: Bool,
                      allFailed: MBFailure?) -> SearchList.Drawn {
                SearchList.Drawn(text: term, run: runId, top: top, topPlace: topPlace, sections: sections,
                                 libraryLate: libraryLate, failed: failedNow, skipped: skippedNow,
                                 musicBrainz: musicBrainz, studio: studio, allFailed: allFailed, counts: counts)
            }
            if whole {
                let top = SearchList.topResults(candidates, n: n, library: results, artistList: artistList,
                                                index: marks.index)
                let (sections, allFailed) = sectionsOf(term, plan, pool, out: out)
                let next = base(top: top, topPlace: false, sections: sections, studio: studioOn(term, plan, out: out),
                                allFailed: allFailed)
                let settledAll = out.isEmpty && !wanted.isEmpty
                return draw(next, said: [libraryWords, settledAll ? mbWords(term, plan, pool, wanted: wanted) : ""])
            }
            let phantoms = out.compactMap { SearchList.phantom($0, plan) }
            let decided = SearchList.decidedTop(candidates, phantoms: phantoms, n: n, library: results,
                                                artistList: artistList, index: marks.index)
            //? a phantom first: no prefix - and then no Top results at all, no heading and no place, until moment 2
            return draw(base(top: decided.prefix, topPlace: decided.place && !decided.prefix.isEmpty, sections: nil,
                             studio: false, allFailed: nil), said: [libraryWords])
        }

        let withLibrary = !was.libraryLate && librarySettled(term) && isAnswered
        let results = withLibrary ? self.results : nil

        guard let drawnSections = was.sections else {
            guard SearchList.sectionsReady(librarySettled: settled, musicBrainz: musicBrainz,
                                           asked: run.asked || out.isEmpty, out: out, capPassed: run.capPassed) else {
                return nil
            }
            let pool = poolFor(term, plan, results: results, artistList: artistList, marks: marks)
            let top = was.topPlace || was.top.isEmpty
                ? SearchList.topResults(SearchList.candidates(pool, box: term, reading: plan), n: n, library: results,
                                        artistList: artistList, index: marks.index, fixed: was.top)
                : was.top
            let (sections, allFailed) = sectionsOf(term, plan, pool, out: out)
            let settledAll = out.isEmpty && !wanted.isEmpty
            return draw(was.with(top: top, topPlace: false, sections: sections, studio: studioOn(term, plan, out: out),
                                 allFailed: allFailed),
                        said: [settledAll ? mbWords(term, plan, pool, wanted: wanted) : ""])
        }

        //? moment 2 drawn: a late kind landing in its slot
        var changed = false
        var folded = ""
        var sections = drawnSections
        let pool = poolFor(term, plan, results: results, artistList: artistList, marks: marks)
        for section in drawnSections {
            guard section.slot == .asking, inHand(section.kind, term, plan, view: .all) else { continue }
            changed = true
            let kind = section.kind
            let order = sections.map(\.kind)
            func replaced(_ slot: SearchList.Drawn.Slot?, rows: [SearchRow]? = nil) {
                sections = sections.map { (each: SearchList.Drawn.Section) -> SearchList.Drawn.Section in
                    each.kind == kind ? SearchList.Drawn.Section(kind: kind, rows: rows ?? each.rows, slot: slot) : each
                }
            }
            if failure(kind, term, plan, view: .all) != nil {
                replaced(.failed)
                continue
            }
            let cap = SearchPacing.cap(kind)
            let (libraryDrawn, musicBrainzDrawn) = SearchList.drawnCounts(pool[kind], section.rows)
            let landing = SearchList.lateRows(pool[kind], cap: (max(0, cap.0 - libraryDrawn), max(0, cap.1 - musicBrainzDrawn)),
                                              drawn: Set(section.rows.map(\.key)))
            let landed = SearchList.drawInOrFold(kind, order)
            if !landing.isEmpty {
                if landed == .into {
                    replaced(nil, rows: section.rows + landing)
                } else {
                    replaced(.show(landing))
                    folded = SearchWords.fold(kind, landing.count).said
                }
            } else if landed == .into {
                if section.rows.isEmpty {
                    sections.removeAll { $0.kind == kind }
                } else {
                    replaced(nil)
                }
            } else {
                replaced(.said(emptyKindWords(kind, term, plan, personal: marks.personal)))
            }
        }
        guard changed else { return nil }
        let settledAll = out.isEmpty && !wanted.isEmpty
        //? the studio line was decided with the sections: never added below them as albums land
        return draw(was.with(sections: sections),
                    said: [folded, settledAll ? mbWords(term, plan, pool, wanted: wanted) : ""])
    }

    private mutating func draw(_ next: SearchList.Drawn, said: [String]) -> Drawing {
        drawn = next
        return Drawing(drawn: next, said: said.filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// "Show 3 more albums": a folded kind's rows opened in place (`showFolded`). The first row brought, for focus.
    @discardableResult
    public mutating func showFolded(_ kind: SearchKind) -> SearchRow? {
        guard let was = drawn, let sections = was.sections,
              let section = sections.first(where: { $0.kind == kind }), case .show(let rows)? = section.slot else {
            return nil
        }
        drawn = was.with(sections: sections.map { (each: SearchList.Drawn.Section) -> SearchList.Drawn.Section in
            each.kind == kind ? SearchList.Drawn.Section(kind: kind, rows: each.rows + rows, slot: nil) : each
        })
        return rows.first
    }

    /// Everything in hand for these words in the All view, each thing once (`poolFor`).
    private func poolFor(_ term: String, _ plan: SearchPlan, results: LibraryResults?, artistList: [Artist]?,
                         marks: SearchMarks) -> SearchPool {
        let albums = found(.albums, term, plan, view: .all)
            .map { SearchAlbumsInHand(groups: $0.groups, shown: $0.shown) }
        return SearchList.pool(reading: plan, library: results, artistList: artistList, marks: marks, albums: albums)
    }

    /// The sections for a draw (`sectionsOf`): each kind with rows, a slot for a kind still out, or its failure while
    /// another kind answered. Every kind asked failed (none late, none refused): the foot's block.
    private func sectionsOf(_ term: String, _ plan: SearchPlan, _ pool: SearchPool,
                            out: [SearchKind]) -> ([SearchList.Drawn.Section], MBFailure?) {
        let wanted = drawnMusicBrainz(term) ? Self.wantedKinds(plan, view: .all) : []
        let failed = wanted.filter { !out.contains($0) && failure($0, term, plan, view: .all) != nil }
        let failures = failed.compactMap { failure($0, term, plan, view: .all) }
        let allFailed = !wanted.isEmpty && failed.count == wanted.count && !failures.contains(where: \.refused)
            ? failures.first : nil
        var sections: [SearchList.Drawn.Section] = []
        for kind in SearchKind.allCases {
            let rows = SearchList.sectionRows(pool[kind], cap: SearchPacing.cap(kind))
            let late = out.contains(kind)
            let failing = failed.contains(kind) && allFailed == nil
            if rows.isEmpty && !late && !failing { continue }
            sections.append(SearchList.Drawn.Section(kind: kind, rows: rows, slot: late ? .asking : failing ? .failed : nil))
        }
        return (sections, allFailed)
    }

    /// Whether the Albums section's studio line is drawn (`studioOn`) - decided as the sections are drawn: its answer
    /// asked with the studio clause, or - albums still out - its request asking it.
    private func studioOn(_ term: String, _ plan: SearchPlan, out: [SearchKind]) -> Bool {
        if out.contains(.albums) { return SearchAlbums.allAlbumsQuery(plan).studio }
        return found(.albums, term, plan, view: .all)?.studio ?? false
    }

    /// Why a late kind's slot holds no rows (`emptyKindWords`): everything held, or nothing found.
    private func emptyKindWords(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, personal: Bool) -> String {
        if kind == .albums, let found = found(.albums, term, plan, view: .all), !found.groups.isEmpty {
            return SearchWords.allHeld(personal: personal)
        }
        return SearchWords.empty(kind, term)
    }

    /// What is announced of MusicBrainz once every kind asked has settled (`mbWords`): what it brought to the list as
    /// drawn - or a refusal's words, every kind refused.
    private func mbWords(_ term: String, _ plan: SearchPlan, _ pool: SearchPool, wanted: [SearchKind]) -> String {
        let answered = wanted.contains { found($0, term, plan, view: .all) != nil }
        let failures = wanted.compactMap { failure($0, term, plan, view: .all) }
        if !answered, let first = failures.first, failures.allSatisfy(\.refused) { return SearchWords.failure(first) }
        var counts: [SearchKind: Int] = [:]
        for kind in SearchKind.allCases {
            counts[kind] = min(pool[kind].musicbrainz.count, SearchPacing.previewMusicBrainz(kind))
        }
        return SearchWords.musicBrainz(counts, answered: answered)
    }

    /// The albums to ask for as All's answer lands, so a song's tap plays (Search.tsx's askLibrary): the songs of Top
    /// results' decided picks first, then the answer's - those not in hand already.
    public func albumsWanted(_ text: String, _ results: LibraryResults, artistList: [Artist]?,
                             marks: SearchMarks) -> [String] {
        let top = SearchList.decidedPrefix(text, results: results, ownedArtists: ownedArtists, artistList: artistList,
                                           marks: marks, musicBrainz: drawnMusicBrainz(text))
        return SearchPacing.albumsToPrefetch(results.songs, preferred: SearchPacing.preferredSongs(top))
            .filter { ready[$0] == nil }
    }

    /// An album asked for so a song plays landed - kept while the ask it was asked beside is the newest (All's, or the
    /// Songs view's).
    public mutating func albumReady(_ album: Album, library token: Int? = nil, kind kindAsk: Int? = nil) {
        if let token, token != allToken { return }
        if let kindAsk, kindAsk != kindToken { return }
        ready[album.id] = album
    }

    /// The albums in hand by id, as the marks read them (Search.tsx `albumOf`): a kind view's, then search3's, then
    /// those asked for so a song plays.
    public var knownAlbums: [String: Album] {
        var known = ready
        for album in results?.albums ?? [] { known[album.id] = album }
        if let kind, kind.kind == .albums {
            for row in kind.rows {
                if case .album(let album) = row { known[album.id] = album }
            }
        }
        return known
    }

    // MARK: a kind view's own

    static func lateKey(_ text: String, _ kind: SearchKind) -> String { "\(text)\n\(kind.rawValue)" }

    /// The kind view's own search3, when the view is a kind and it isn't asked or answered for these words.
    public var wantsKind: Bool {
        guard let wanted = view.kind, !query.isEmpty else { return false }
        return !(kind?.holds(query, wanted) ?? false)
    }

    /// Whether All has been asked or answered for the words - a chip asks its kind's own at once then, else with the
    /// pause (Search.tsx's choose).
    public var libraryAskedForQuery: Bool {
        (libraryAsked.map { WebText.same($0, query) } ?? false) || (libraryText.map { WebText.same($0, query) } ?? false)
    }

    /// The kind view's ask begins: its token and kind, and whether its late clock is to be armed (`libraryLateMs`, then
    /// `kindLatePassed`) - once per view and words, for a view that asks MusicBrainz (question 16). Nil when it isn't
    /// wanted.
    public mutating func askingKind() -> (token: Int, kind: SearchKind, armLate: Bool)? {
        guard wantsKind, let wanted = view.kind else { return nil }
        let same = kind.map { WebText.same($0.text, query) && $0.kind == wanted } ?? false
        let key = Self.lateKey(query, wanted)
        if !same {
            kindLateFor = nil
            kindShownFor = nil
        }
        kindToken += 1
        kind = KindLibrary(text: query, kind: wanted)
        let asks = planFor(query).map { !Self.wantedKinds($0, view: SearchView(wanted)).isEmpty } ?? false
        return (kindToken, wanted, asks && kindLateFor != key)
    }

    /// `libraryLateMs` passed for a kind view's own: MusicBrainz's rows draw under a place kept at its top, if it is
    /// still asking. True when it is late now.
    @discardableResult
    public mutating func kindLatePassed(_ text: String, _ wanted: SearchKind) -> Bool {
        guard let kind, WebText.same(kind.text, text), kind.kind == wanted, kind.state == .asking else { return false }
        kindLateFor = Self.lateKey(text, wanted)
        return true
    }

    /// "Show N from your library" in a kind view.
    public mutating func showKindLibrary() {
        guard let wanted = view.kind else { return }
        kindShownFor = Self.lateKey(query, wanted)
    }

    /// Navidrome known not to be there: the kind view's library not asked.
    public mutating func kindSkipped() {
        guard let wanted = view.kind, !query.isEmpty else { return }
        kindToken += 1
        kind = KindLibrary(text: query, kind: wanted, state: .skipped)
    }

    @discardableResult
    public mutating func kindAnswered(_ token: Int, _ results: LibraryResults) -> Bool {
        guard token == kindToken, var now = kind else { return false }
        now.answered(results)
        kind = now
        return true
    }

    @discardableResult
    public mutating func kindFailed(_ token: Int) -> Bool {
        guard token == kindToken, var now = kind else { return false }
        now.failed()
        kind = now
        return true
    }

    /// The kind view's own, when it is the view's and the words' - what the view draws.
    public var kindShown: KindLibrary? {
        guard let kind, let wanted = view.kind, kind.kind == wanted, WebText.same(kind.text, query) else { return nil }
        return kind
    }

    /// More from your library: its token, words, kind and offsets - nil when it can't be asked.
    public mutating func askingMore() -> (token: Int, text: String, kind: SearchKind, offsets: SearchCounts)? {
        guard var now = kindShown, let offsets = now.moreOffsets else { return nil }
        kindToken += 1
        now.moreAsked()
        kind = now
        return (kindToken, now.text, now.kind, offsets)
    }

    /// More's page landed: appended - how many it held (for the words), nil when it isn't the newest ask's.
    public mutating func moreAnswered(_ token: Int, _ results: LibraryResults) -> Int? {
        guard token == kindToken, var now = kind else { return nil }
        let count = now.moreAnswered(results)
        kind = now
        return count
    }

    public mutating func moreFailed(_ token: Int) {
        guard token == kindToken, var now = kind else { return }
        now.moreFailed()
        kind = now
    }

    // MARK: a kind view as drawn

    /// What a kind view holds as it stands (Search.tsx `kindModel`): its library's rows (its chip's own search3), then -
    /// the Albums view - MusicBrainz's. Nil for All, or an empty box.
    public func kindView(artistList: [Artist]?, marks: SearchMarks) -> KindView? {
        guard let wanted = view.kind, !query.isEmpty else { return nil }
        let plan = planFor(query)
        let lib = kindShown
        let lateKey = Self.lateKey(query, wanted)
        let late = kindLateFor == lateKey && kindShownFor != lateKey
        let libSettled = lib.map { $0.state != .asking } ?? false
        let showLib = libSettled && !late
        var answeredRows: [SearchRow] = []
        if let lib, libSettled {
            answeredRows = SearchList.kindRows(wanted, rows: lib.rows, text: query, allResults: results,
                                               ownedArtists: ownedArtists, artistList: artistList)
        }
        let libraryRows = showLib ? answeredRows : []
        let keyNow = plan.flatMap { Self.keyFor(wanted, query, $0, view: SearchView(wanted)) }
        let musicBrainz = drawnMusicBrainz(query)
        let mine: Albums? = keyNow != nil && albums.key == keyNow ? albums : nil
        let mbAllowed = libSettled || kindLateFor == lateKey
        var mbRows: [SearchRow] = []
        var groups: [ReleaseGroup] = []
        if mbAllowed, case .done(let found)? = mine {
            groups = found.groups
            let libraryAlbums = (lib?.rows ?? []).compactMap { (row: SearchRow) -> Album? in
                if case .album(let album) = row { return album }
                return nil
            }
            let held = Set(SearchAlbums.heldUnlisted(found.groups, marks.index, libraryAlbums).map(\.id))
            let shown = Set(found.shown.map(\.id))
            mbRows = found.groups.filter { shown.contains($0.id) || held.contains($0.id) }.map { SearchRow.group($0) }
        }
        let noMusicBrainz = keyNow == nil
        let searching = !late && !libSettled
        let nothing = libSettled && lib?.state != .failed && answeredRows.isEmpty
            && (noMusicBrainz || (isDone(mine) && mbRows.isEmpty && groups.isEmpty))
        var foot: KindView.Foot?
        if !noMusicBrainz {
            if !musicBrainz && mine == nil {
                foot = .typeMore
            } else if mbAllowed {
                switch mine {
                case .none, .idle?, .searching?:
                    foot = musicBrainz || mine != nil ? .searching : nil
                case .failed(_, _, let failure)?:
                    foot = .failed(failure)
                case .done?:
                    if !mbRows.isEmpty {
                        foot = .rows(mbRows)
                    } else if !nothing {
                        foot = .said(groups.isEmpty ? SearchWords.empty(wanted, query)
                            : SearchWords.allHeld(personal: marks.personal))
                    }
                }
            }
        }
        var lateSlot: LateSlot?
        if late {
            switch lib?.state {
            case .none, .asking?: lateSlot = .asking
            case .failed?: lateSlot = .failed
            case .skipped?: lateSlot = .skipped
            case .answered?: lateSlot = (lib?.rows ?? []).isEmpty ? .nothing : .show(lib?.rows.count ?? 0)
            }
        }
        return KindView(kind: wanted, lateSlot: lateSlot, searching: searching,
                        searchingMusicBrainz: musicBrainz && !noMusicBrainz, libraryFailed: lib?.state == .failed && !late,
                        libraryRows: libraryRows, own: showLib ? lib : nil, foot: foot, nothing: nothing)
    }

    private func isDone(_ answer: Albums?) -> Bool {
        if case .done? = answer { return true }
        return false
    }
}

/// A kind view as drawn (Search.tsx's kindView): the place kept for its late library, the asking line before its
/// library lands, its library's failure, its rows and More, then MusicBrainz's part below - and "No albums for …" when
/// nothing at all was found.
public struct KindView: Sendable, Equatable {
    /// MusicBrainz's part, below the library's (the Albums view).
    public enum Foot: Sendable, Equatable {
        /// MusicBrainz not asked yet: `SearchWords.typeMore`.
        case typeMore
        /// "Searching…"
        case searching
        /// Its words, and Try again unless refused.
        case failed(MBFailure)
        case rows([SearchRow])
        /// Why there are none: everything held, or nothing else found.
        case said(String)
    }

    public let kind: SearchKind
    public let lateSlot: SearchState.LateSlot?
    /// The asking line where its rows will go.
    public let searching: Bool
    /// ...saying "Searching…" (MusicBrainz in it) rather than the library's words.
    public let searchingMusicBrainz: Bool
    /// Its library failed: the failure's words and Try again.
    public let libraryFailed: Bool
    public let libraryRows: [SearchRow]
    /// Its own search3, drawn - More from your library when full.
    public let own: KindLibrary?
    public let foot: Foot?
    /// Nothing at all found: "No albums for …".
    public let nothing: Bool
}
