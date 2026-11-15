import Foundation

/// Search's state for one person (Phase 5, slices 1-4 - notes/ios-specs/phase5-search.md 2.6-2.7, 6.4; the web's
/// app/Search.tsx: its `library`, `musicbrainz`, `artists`, `songs`, `drawn`, `kindLibrary`, `ready`, `view`, runs,
/// `lateFor` and Behind):
/// what the box says, what has been asked for which words, the list drawn - frozen once drawn - and a kind view's own.
/// Pure: the app's SearchModel makes the requests and keeps the clocks, and tells this what landed and when a clock ran
/// out; every rule of when to ask and when to draw is here, tested on Linux.
///
/// - The box's words, trimmed (`query`). Typing other words starts a new run: the list drawn stays until the library
///   settles for the new words (or is `libraryLateMs` late), then theirs takes its place. An empty box lets everything
///   go.
/// - All's search3 is asked once per words (`wantsLibrary`) - again only after a failure, Try again, or the keyboard's
///   Search on a failure; only the newest ask's answer counts (`libraryAnswered`'s token).
/// - MusicBrainz is asked once typing pauses longer (`musicBrainzSettleMs`, three characters at least), or on the
///   keyboard's Search (`askingMusicBrainz`) - albums, then artists, then songs, each the view needs and the reading
///   asks; the words it was asked for are `asked`, read as `askedPlan` was.
/// - The list is drawn in its moments (`advance`), only in the All view: Top results' decided picks first, the sections
///   in the asking line's place once MusicBrainz answers or `resultsWaitMs` passes, a late kind landing in its slot.
///   A chip, See all and Back to All draw afresh.
/// - A kind view asks its own (`wantsKind`), kept for its words and kind; More by offset (`askingMore`); MusicBrainz's
///   rows of its kind below its own (`kindView`), and More from MusicBrainz by offset (`askingMoreMusicBrainz`).
/// - (Slice 4) What's saved is asked once per words beside the library (`askingSaved`), and the library's moment waits
///   for it `SearchSaved.waitMs` at most (`savedGaveUp`); it leads MusicBrainz's rows, MusicBrainz's answer adding only
///   what isn't there. Answers kept from before (`SearchAnswersKept`, the model's) are taken with no request as the
///   library lands (`takeKept`).
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

    /// A MusicBrainz kind's answer for some words (Search.tsx `Musicbrainz`, `Artists`, `Songs`): `key` the words and the
    /// query a view asks.
    public enum Answer<Found: SearchFound>: Sendable, Equatable {
        case idle
        case searching(text: String, key: String)
        case done(Found)
        case failed(text: String, key: String, failure: MBFailure)

        public var key: String? {
            switch self {
            case .idle: return nil
            case .searching(_, let key), .failed(_, let key, _): return key
            case .done(let found): return found.key
            }
        }

        /// Answered or failed for `key` (`inHandFor`).
        func landed(_ key: String) -> Bool {
            switch self {
            case .idle, .searching: return false
            case .done(let found): return found.key == key
            case .failed(_, let was, _): return was == key
            }
        }

        /// In hand, or on its way, for `key` (`askedFor`) - then it isn't asked again. A failure is asked again.
        func asked(_ key: String) -> Bool {
            switch self {
            case .idle, .failed: return false
            case .searching(_, let was): return was == key
            case .done(let found): return found.key == key
            }
        }

        /// Its failure, when it failed - what a slot's words say.
        public var failure: MBFailure? {
            if case .failed(_, _, let failure) = self { return failure }
            return nil
        }

        public var found: Found? {
            if case .done(let found) = self { return found }
            return nil
        }
    }

    public typealias Albums = Answer<AlbumsFound>

    /// More from MusicBrainz for a kind's answer (Search.tsx `more`): not asked, asking, failed - or a page added:
    /// `added` the rows it brought, `other` the albums it found held (albums) or the albums the songs drawn gained
    /// (songs).
    public enum MorePage: Sendable, Equatable {
        case idle
        case asking
        case failed(MBFailure)
        case added(Int, other: Int)
    }

    /// MusicBrainz's albums answer: its groups in the order drawn (the studio clause's in studioOrder), the block shown
    /// (the groups less those held, worked out once as it landed), what MusicBrainz was asked (`query` - the words
    /// typed, when a fielded read found nothing), the studio clause on.
    public struct AlbumsFound: SearchFound {
        public let text: String
        public let key: String
        public let plan: SearchPlan
        public internal(set) var groups: [ReleaseGroup]
        public internal(set) var shown: [ReleaseGroup]
        public let query: String
        public let studio: Bool
        public internal(set) var count: Int?
        /// (Slice 4) Where More's next page starts (every answer so far, held ones too), the last page's size, More.
        public internal(set) var nextOffset: Int
        public internal(set) var last: Int
        public internal(set) var more: MorePage = .idle
    }

    /// MusicBrainz's artists answer (Search.tsx `Artists`): the name asked (the words typed, single-spaced) and the
    /// artists going by it, in MusicBrainz's order.
    public struct ArtistsFound: SearchFound {
        public let text: String
        public let key: String
        public let name: String
        public internal(set) var matches: [MBArtistMatch]
        public internal(set) var count: Int?
        public internal(set) var nextOffset: Int
        public internal(set) var last: Int
        public internal(set) var more: MorePage = .idle
    }

    /// MusicBrainz's songs answer (Search.tsx `Songs`): what was asked (`query` - the words as one title, when a title by
    /// an artist found no song by them), the recordings, and the songs they make (songs.ts `groupSongs`).
    public struct SongsFound: SearchFound {
        public let text: String
        public let key: String
        public let query: String
        public internal(set) var recordings: [MBRecording]
        public internal(set) var songs: [FoundSong]
        public internal(set) var count: Int?
        public internal(set) var nextOffset: Int
        public internal(set) var last: Int
        public internal(set) var more: MorePage = .idle
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

    /// An ask of MusicBrainz's artists (`askArtists`): the words typed, single-spaced, as a name.
    public struct ArtistsAsk: Sendable, Equatable {
        public let token: Int
        public let text: String
        public let key: String
        public let plan: SearchPlan
        public let name: String
    }

    /// An ask of MusicBrainz's songs (`askSongs`): the query for the box as read, and - a title beside an artist - the
    /// words typed as one title, asked when it finds no song by them (`fallback`, songTitleQuery).
    public struct SongsAsk: Sendable, Equatable {
        public let token: Int
        public let text: String
        public let key: String
        public let plan: SearchPlan
        public let first: String
        public let fallback: String?
    }

    /// What one ask of MusicBrainz sends, in its order (`SEND_ORDER`): albums, then artists (the smallest), then songs
    /// (the largest) - each nil when the view doesn't need it, the reading doesn't ask it, or it is in hand or on its way.
    public struct MusicBrainzAsks: Sendable, Equatable {
        public var albums: AlbumsAsk?
        public var artists: ArtistsAsk?
        public var songs: SongsAsk?

        public init(albums: AlbumsAsk? = nil, artists: ArtistsAsk? = nil, songs: SongsAsk? = nil) {
            self.albums = albums
            self.artists = artists
            self.songs = songs
        }

        public var isEmpty: Bool { albums == nil && artists == nil && songs == nil }
    }

    /// More from MusicBrainz asked (Search.tsx `askMore`, `askMoreArtists`, `askMoreSongs`): the kind, the answer it adds
    /// to (`key`), what is asked again - the albums' query, the artists' name, the songs' query - and from where.
    public struct MoreAsk: Sendable, Equatable {
        public let token: Int
        public let kind: SearchKind
        public let key: String
        public let words: String
        public let offset: Int
    }

    /// What's saved for some words (Search.tsx `Saved`): asked as the words settle, beside the library; `none` when there
    /// was nothing to search, it failed, or it missed `SearchSaved.waitMs` - given up for the words: MusicBrainz's answer
    /// alone.
    public enum Saved: Sendable, Equatable {
        case idle
        case asking(String)
        case done(String, SavedFound)
        case none(String)

        /// The words it is for - nil while idle.
        public var text: String? {
            switch self {
            case .idle: return nil
            case .asking(let text), .done(let text, _), .none(let text): return text
            }
        }
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
    /// MusicBrainz's albums, artists and songs.
    public private(set) var albums: Albums = .idle
    public private(set) var artists: Answer<ArtistsFound> = .idle
    public private(set) var songs: Answer<SongsFound> = .idle
    /// The words MusicBrainz was asked for - nil when nothing is, or dropped.
    public private(set) var asked: String?
    /// (Slice 4) What's saved, for the words it was last asked for.
    public private(set) var saved: Saved = .idle
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
    /// Only the newest ask's answer counts: All's, a kind view's (its More's too), each of MusicBrainz's kinds'.
    private var allToken = 0
    private var kindToken = 0
    private var albumsToken = 0
    private var artistsToken = 0
    private var songsToken = 0
    private var savedToken = 0

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
            savedToken += 1
            saved = .idle
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
            Self.wantedKinds(query, plan, view: .all).contains { (kind: SearchKind) -> Bool in
                failure(kind, query, plan, view: .all) != nil
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
        let wanted = Self.wantedKinds(run.text, plan, view: .all)
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

    // MARK: MusicBrainz

    /// The kinds a view asks MusicBrainz for, by the reading (`wantedKinds`): All every kind it asks, a kind view its own
    /// - in kind order.
    public static func wantedKinds(_ term: String, _ plan: SearchPlan, view: SearchView) -> [SearchKind] {
        SearchKind.allCases.filter { (kind: SearchKind) -> Bool in
            (view == .all || view.kind == kind) && keyFor(kind, term, plan, view: view) != nil
        }
    }

    /// What a kind is asked for these words, read this way, in this view (`keyFor`) - nil for not asked: artists not
    /// under the album-by-artist reading (the artist named is the library's), songs not for an artist's name alone.
    public static func keyFor(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view: SearchView) -> String? {
        switch kind {
        case .artists:
            return plan.kind == .albumByArtist ? nil : "\(term)\nartists:\(words1(term))"
        case .albums:
            return "\(term)\nalbums:\(view == .albums ? plan.query : SearchAlbums.allAlbumsQuery(plan).query)"
        case .songs:
            return SongSearch.query(term, plan).map { "\(term)\nsongs:\($0)" }
        }
    }

    /// The words typed, single-spaced (Search.tsx `words1`).
    static func words1(_ term: String) -> String {
        SearchReading.words(term).joined(separator: " ")
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
    /// keyboard's Search reads the box afresh); each kind the view needs asked unless in hand or on its way for the same
    /// key - the asks returned, in SEND_ORDER; the cap armed in All.
    public mutating func askingMusicBrainz(_ term: String, view inView: SearchView, reread: Bool = false) -> MusicBrainzAsks {
        guard !term.isEmpty, let plan = reread ? readBox(term) : planFor(term) else { return MusicBrainzAsks() }
        asked = term
        askedPlan = (term, plan)
        var asks = MusicBrainzAsks()
        let wanted = Self.wantedKinds(term, plan, view: inView)
        if wanted.contains(.albums), let key = Self.keyFor(.albums, term, plan, view: inView), !albums.asked(key) {
            albumsToken += 1
            albums = .searching(text: term, key: key)
            asks.albums = albumsAsk(term, plan, view: inView, key: key, token: albumsToken)
        }
        if wanted.contains(.artists), let key = Self.keyFor(.artists, term, plan, view: .all), !artists.asked(key) {
            artistsToken += 1
            artists = .searching(text: term, key: key)
            asks.artists = ArtistsAsk(token: artistsToken, text: term, key: key, plan: plan, name: Self.words1(term))
        }
        if wanted.contains(.songs), let key = Self.keyFor(.songs, term, plan, view: .all), !songs.asked(key),
           let ask = songsAsk(term, plan, key: key, token: songsToken + 1) {
            songsToken += 1
            songs = .searching(text: term, key: key)
            asks.songs = ask
        }
        if inView == .all { armCap(term) }
        return asks
    }

    /// A kind's failure as it stands - a late kind's slot says it (`answerOf(kind)`'s), nil when it hasn't failed.
    public func failure(of kind: SearchKind) -> MBFailure? {
        switch kind {
        case .albums: return albums.failure
        case .artists: return artists.failure
        case .songs: return songs.failure
        }
    }

    /// Whether `token` is each kind's newest ask.
    public func isNewestAlbums(_ token: Int) -> Bool { token == albumsToken }
    public func isNewestArtists(_ token: Int) -> Bool { token == artistsToken }
    public func isNewestSongs(_ token: Int) -> Bool { token == songsToken }

    /// The albums answered (`query`: what was asked - `ask.first`, or its fallback): the studio clause's in studio order,
    /// and the block shown worked out now from `index` (all of them before it has answered). True when kept.
    @discardableResult
    public mutating func albumsAnswered(_ ask: AlbumsAsk, _ found: FullySearchAnswer, query: String,
                                        index: OwnedIndex?) -> Bool {
        guard ask.token == albumsToken else { return false }
        albums = .done(Self.albumsFound(ask, found, query: query, index: index))
        return true
    }

    @discardableResult
    public mutating func albumsFailed(_ ask: AlbumsAsk, _ failure: MBFailure) -> Bool {
        guard ask.token == albumsToken else { return false }
        albums = .failed(text: ask.text, key: ask.key, failure: failure)
        return true
    }

    /// The artists answered. True when kept.
    @discardableResult
    public mutating func artistsAnswered(_ ask: ArtistsAsk, _ found: ArtistSearchAnswer) -> Bool {
        guard ask.token == artistsToken else { return false }
        artists = .done(Self.artistsFound(ask, found))
        return true
    }

    @discardableResult
    public mutating func artistsFailed(_ ask: ArtistsAsk, _ failure: MBFailure) -> Bool {
        guard ask.token == artistsToken else { return false }
        artists = .failed(text: ask.text, key: ask.key, failure: failure)
        return true
    }

    /// The songs answered (`query`: what was asked - `ask.first`, or its fallback): their recordings made songs. True
    /// when kept - the caller closes every song's disclosure then, and every fold.
    @discardableResult
    public mutating func songsAnswered(_ ask: SongsAsk, _ found: SongSearchAnswer, query: String) -> Bool {
        guard ask.token == songsToken else { return false }
        songs = .done(Self.songsFound(ask, found, query: query))
        return true
    }

    @discardableResult
    public mutating func songsFailed(_ ask: SongsAsk, _ failure: MBFailure) -> Bool {
        guard ask.token == songsToken else { return false }
        songs = .failed(text: ask.text, key: ask.key, failure: failure)
        return true
    }

    /// Too few characters now, or the box emptied: MusicBrainz's answers for the longer words let go
    /// (`dropMusicBrainz`) - nothing would ever replace them.
    private mutating func dropMusicBrainz() {
        asked = nil
        askedPlan = nil
        albumsToken += 1
        artistsToken += 1
        songsToken += 1
        albums = .idle
        artists = .idle
        songs = .idle
    }

    /// An answer as it is kept (`albumsDone`): the studio clause's in studio order, the block shown worked out now from
    /// `index` (all of them before it has answered), More's next page after every group it brought.
    static func albumsFound(_ ask: AlbumsAsk, _ found: FullySearchAnswer, query: String, index: OwnedIndex?) -> AlbumsFound {
        let studio = ask.studio && query == ask.first
        let groups = studio ? SearchAlbums.studioOrder(found.releaseGroups) : found.releaseGroups
        return AlbumsFound(text: ask.text, key: ask.key, plan: ask.plan, groups: groups,
                           shown: SearchAlbums.notInLibrary(groups, index), query: query, studio: studio,
                           count: found.count, nextOffset: found.releaseGroups.count, last: found.releaseGroups.count)
    }

    static func artistsFound(_ ask: ArtistsAsk, _ found: ArtistSearchAnswer) -> ArtistsFound {
        ArtistsFound(text: ask.text, key: ask.key, name: ask.name, matches: found.matches, count: found.count,
                     nextOffset: found.matches.count, last: found.matches.count)
    }

    static func songsFound(_ ask: SongsAsk, _ found: SongSearchAnswer, query: String) -> SongsFound {
        SongsFound(text: ask.text, key: ask.key, query: query, recordings: found.recordings,
                   songs: SongSearch.group(found.recordings), count: found.count, nextOffset: found.recordings.count,
                   last: found.recordings.count)
    }

    // MARK: what's saved (slice 4)

    /// What's saved is asked for `term` (Search.tsx `askSaved`): ONCE for the words, whatever it answered - given up or
    /// failed, it stays so until the words change (else, asked again by a chip, Enter or Try again, a saved answer
    /// landing late went above MusicBrainz's rows already drawn). Its token - nil when it isn't asked. The caller arms
    /// `SearchSaved.waitMs`, then `savedGaveUp`.
    public mutating func askingSaved(_ term: String) -> Int? {
        guard !term.isEmpty else { return nil }
        if let text = saved.text, WebText.same(text, term) { return nil }
        savedToken += 1
        saved = .asking(term)
        return savedToken
    }

    /// What's saved answered: kept for its words when it is the newest ask's - `none` when nothing could be searched.
    /// What is held is left out as it is DRAWN (`savedOf`), never here as it lands (an album you have drawn twice, else,
    /// when `/library/owned` hadn't answered yet).
    @discardableResult
    public mutating func savedAnswered(_ token: Int, _ answer: SavedSearchAnswer) -> Bool {
        guard token == savedToken, case .asking(let term) = saved else { return false }
        saved = answer.available ? .done(term, SavedFound(answer)) : .none(term)
        return true
    }

    /// What's saved failed: given up for the words (MusicBrainz's answer alone) when it is the newest ask's.
    @discardableResult
    public mutating func savedFailed(_ token: Int) -> Bool {
        guard token == savedToken, case .asking(let term) = saved else { return false }
        saved = .none(term)
        return true
    }

    /// `SearchSaved.waitMs` passed for `term`: still asking, it is given up for the words (its answer let go). True when
    /// it was.
    @discardableResult
    public mutating func savedGaveUp(_ term: String) -> Bool {
        guard case .asking(let text) = saved, WebText.same(text, term) else { return false }
        savedToken += 1
        saved = .none(term)
        return true
    }

    /// The library's moment waits for what's saved while it is being asked for these words (`savedSettled`) - never
    /// longer than `SearchSaved.waitMs`, which gives it up.
    public func savedSettled(_ term: String) -> Bool {
        if case .asking(let text) = saved, WebText.same(text, term) { return false }
        return true
    }

    /// What's saved for these words, as a view reading them this way draws it (`savedOf`): only when MusicBrainz is
    /// drawn for them, the kinds the view asks.
    public func savedOf(_ term: String, _ plan: SearchPlan, view inView: SearchView, index: OwnedIndex?) -> SavedAnswer? {
        guard case .done(let text, let found) = saved, WebText.same(text, term), drawnMusicBrainz(term) else { return nil }
        let studio = inView == .all && SearchAlbums.allAlbumsQuery(plan).studio
        return SearchSaved.savedFor(plan, found, kinds: Self.wantedKinds(term, plan, view: inView), studio: studio,
                                    index: index)
    }

    // MARK: the kept answers (slice 4)

    /// Every kind a view would ask MusicBrainz that a kept answer holds (Search.tsx `takeKept`), taken now with no
    /// request - as the library answers, fails or is skipped, and as a chip is pressed - so the list is drawn whole at
    /// the library's moment; what is held worked out from `index`. Only for words MusicBrainz is to be asked for, and a
    /// kind not in hand or on its way for its key (a failure is taken over). `took` when any was (the caller asks
    /// `/library/owned` again, to mark rows in place); `songs` when songs were (it closes every song's disclosure).
    public mutating func takeKept(_ term: String, view inView: SearchView, kept: SearchAnswersKept,
                                  index: OwnedIndex?) -> (took: Bool, songs: Bool) {
        guard !term.isEmpty,
              asked.map({ WebText.same($0, term) }) == true || SearchReading.asksMusicBrainzBySettling(term),
              let plan = planFor(term) else { return (false, false) }
        var took = false
        var tookSongs = false
        for kind in Self.wantedKinds(term, plan, view: inView) {
            guard let key = Self.keyFor(kind, term, plan, view: inView) else { continue }
            switch kind {
            case .albums:
                guard !albums.asked(key) else { continue }
                let ask = albumsAsk(term, plan, view: inView, key: key, token: albumsToken + 1)
                guard let hit = kept.albums(ask) else { continue }
                albumsToken += 1
                albums = .done(Self.albumsFound(ask, hit.found, query: hit.query, index: index))
                took = true
            case .artists:
                guard !artists.asked(key) else { continue }
                let ask = ArtistsAsk(token: artistsToken + 1, text: term, key: key, plan: plan, name: Self.words1(term))
                guard let found = kept.artists(ask) else { continue }
                artistsToken += 1
                artists = .done(Self.artistsFound(ask, found))
                took = true
            case .songs:
                guard !songs.asked(key), let ask = songsAsk(term, plan, key: key, token: songsToken + 1),
                      let hit = kept.songs(ask) else { continue }
                songsToken += 1
                songs = .done(Self.songsFound(ask, hit.found, query: hit.query))
                took = true
                tookSongs = true
            }
        }
        return (took, tookSongs)
    }

    /// The albums' ask for these words in this view (`askAlbums`'s): the Albums view the words as read, All the studio
    /// clause's query for an artist's name alone; the words typed again when a fielded read finds nothing.
    private func albumsAsk(_ term: String, _ plan: SearchPlan, view inView: SearchView, key: String, token: Int) -> AlbumsAsk {
        let (first, studio) = inView == .albums ? (plan.query, false) : SearchAlbums.allAlbumsQuery(plan)
        return AlbumsAsk(token: token, text: term, key: key, plan: plan, first: first, studio: studio,
                         fallback: plan.kind == .free ? nil : Self.words1(term))
    }

    /// The songs' ask (`askSongs`'s) - nil for an artist's name alone, which asks no song.
    private func songsAsk(_ term: String, _ plan: SearchPlan, key: String, token: Int) -> SongsAsk? {
        guard let first = SongSearch.query(term, plan) else { return nil }
        return SongsAsk(token: token, text: term, key: key, plan: plan, first: first,
                        fallback: plan.kind == .albumByArtist ? SongSearch.titleQuery(term) : nil)
    }

    // MARK: More from MusicBrainz (slice 4)

    /// A kind view's More from MusicBrainz (Search.tsx `askMore`, `askMoreArtists`, `askMoreSongs`): the next page of
    /// the same search, by offset, through the kind's own token - nil unless its answer for the view's key is in hand,
    /// isn't asking already, and has another page.
    public mutating func askingMoreMusicBrainz() -> MoreAsk? {
        guard let wanted = view.kind, !query.isEmpty, let plan = planFor(query),
              let key = Self.keyFor(wanted, query, plan, view: view) else { return nil }
        switch wanted {
        case .albums:
            guard var found = albums.found, found.key == key, found.more != .asking,
                  SearchMore.pages(next: found.nextOffset, count: found.count, last: found.last,
                                   limit: SearchAlbums.limit) == .more else { return nil }
            albumsToken += 1
            found.more = .asking
            albums = .done(found)
            return MoreAsk(token: albumsToken, kind: .albums, key: key, words: found.query, offset: found.nextOffset)
        case .artists:
            guard var found = artists.found, found.key == key, found.more != .asking,
                  SearchMore.pages(next: found.nextOffset, count: found.count, last: found.last,
                                   limit: MBArtistSearch.limit) == .more else { return nil }
            artistsToken += 1
            found.more = .asking
            artists = .done(found)
            return MoreAsk(token: artistsToken, kind: .artists, key: key, words: found.name, offset: found.nextOffset)
        case .songs:
            guard var found = songs.found, found.key == key, found.more != .asking,
                  SearchMore.pages(next: found.nextOffset, count: found.count, last: found.last,
                                   limit: SongSearch.limit) == .more else { return nil }
            songsToken += 1
            found.more = .asking
            songs = .done(found)
            return MoreAsk(token: songsToken, kind: .songs, key: key, words: found.query, offset: found.nextOffset)
        }
    }

    /// More's page of albums landed: appended below the rows drawn - the held left out as the first page leaves them
    /// (`appendPage`) - and what it brought, in words, to be announced. Nil when it isn't the newest ask's, or the
    /// answer it was asked of has gone.
    public mutating func moreAnswered(_ ask: MoreAsk, albums page: FullySearchAnswer, index: OwnedIndex?,
                                      personal: Bool) -> String? {
        guard ask.kind == .albums, ask.token == albumsToken, var found = albums.found, found.key == ask.key else { return nil }
        let appended = SearchMore.appendPage(found.groups, found.shown, page.releaseGroups, index)
        found.groups = appended.groups
        found.shown = appended.shown
        found.nextOffset += page.releaseGroups.count
        found.last = page.releaseGroups.count
        found.count = page.count ?? found.count
        found.more = .added(appended.added, other: appended.held)
        albums = .done(found)
        return SearchMore.pageWords(added: appended.added, held: appended.held, personal: personal).said
    }

    /// ...a page of artists: the ones not got already appended.
    public mutating func moreAnswered(_ ask: MoreAsk, artists page: ArtistSearchAnswer) -> String? {
        guard ask.kind == .artists, ask.token == artistsToken, var found = artists.found, found.key == ask.key else {
            return nil
        }
        let known = Set(found.matches.map(\.mbid))
        let fresh = page.matches.filter { !known.contains($0.mbid) }
        found.matches += fresh
        found.nextOffset += page.matches.count
        found.last = page.matches.count
        found.count = page.count ?? found.count
        found.more = .added(fresh.count, other: 0)
        artists = .done(found)
        return SearchMore.artistsSaid(page.matches.count)
    }

    /// ...a page of songs: merged in (`appendSongs`) - a later take of a song shown adding its albums to it in place, a
    /// new song after the rest.
    public mutating func moreAnswered(_ ask: MoreAsk, songs page: SongSearchAnswer) -> String? {
        guard ask.kind == .songs, ask.token == songsToken, var found = songs.found, found.key == ask.key else { return nil }
        let merged = SearchMore.appendSongs(found.recordings, page.recordings, drawn: found.songs)
        found.recordings = merged.recordings
        found.songs = merged.songs
        found.nextOffset += page.recordings.count
        found.last = page.recordings.count
        found.count = page.count ?? found.count
        found.more = .added(merged.added, other: merged.grown)
        songs = .done(found)
        return SearchMore.songsWords(added: merged.added, grown: merged.grown).said
    }

    /// More's ask failed: its words under the rows, and Try again in the button.
    public mutating func moreFailed(_ ask: MoreAsk, _ failure: MBFailure) {
        switch ask.kind {
        case .albums:
            guard ask.token == albumsToken, var found = albums.found, found.key == ask.key else { return }
            found.more = .failed(failure)
            albums = .done(found)
        case .artists:
            guard ask.token == artistsToken, var found = artists.found, found.key == ask.key else { return }
            found.more = .failed(failure)
            artists = .done(found)
        case .songs:
            guard ask.token == songsToken, var found = songs.found, found.key == ask.key else { return }
            found.more = .failed(failure)
            songs = .done(found)
        }
    }

    /// Whether a kind's answer for these words, in this view, has landed (`inHandFor`): answered or failed.
    func inHand(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view inView: SearchView) -> Bool {
        guard let key = Self.keyFor(kind, term, plan, view: inView) else { return false }
        switch kind {
        case .albums: return albums.landed(key)
        case .artists: return artists.landed(key)
        case .songs: return songs.landed(key)
        }
    }

    /// A kind's answer in hand, answered - whatever it found.
    func answered(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view inView: SearchView) -> Bool {
        inHand(kind, term, plan, view: inView) && failure(kind, term, plan, view: inView) == nil
    }

    /// Each kind's answer in hand, answered.
    func foundAlbums(_ term: String, _ plan: SearchPlan, view inView: SearchView) -> AlbumsFound? {
        inHand(.albums, term, plan, view: inView) ? albums.found : nil
    }

    func foundArtists(_ term: String, _ plan: SearchPlan, view inView: SearchView) -> ArtistsFound? {
        inHand(.artists, term, plan, view: inView) ? artists.found : nil
    }

    func foundSongs(_ term: String, _ plan: SearchPlan, view inView: SearchView) -> SongsFound? {
        inHand(.songs, term, plan, view: inView) ? songs.found : nil
    }

    /// A kind's answer in hand, failed.
    func failure(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, view inView: SearchView) -> MBFailure? {
        guard inHand(kind, term, plan, view: inView) else { return nil }
        switch kind {
        case .albums: return albums.failure
        case .artists: return artists.failure
        case .songs: return songs.failure
        }
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
        //? (slice 4) ...and what's saved, while it is asked for (at most SearchSaved.waitMs)
        let settled = (librarySettled(term) || lateFor.map { WebText.same($0, term) } == true) && savedSettled(term)
        let musicBrainz = drawnMusicBrainz(term)
        let wanted = musicBrainz ? Self.wantedKinds(term, plan, view: .all) : []
        let out = SearchList.lateKinds(wanted) { inHand($0, term, plan, view: .all) }
        let n = SearchPacing.topResults
        //? Top results' family (`familyFor`): a song's named album is a saved group's, or MusicBrainz's albums answer's
        //? own group, when either holds it - marked as saved when it is what's saved's
        let kept = savedOf(term, plan, view: .all, index: marks.index)?.groups ?? []
        let groups = kept + (albums.found.map { (found: AlbumsFound) -> [ReleaseGroup] in
            WebText.same(found.text, term) ? found.groups : []
        } ?? [])
        let savedGroups = Set(kept.map(\.id))

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
            func base(top: [SearchRow], topSaved: Set<String>, topPlace: Bool, sections: [SearchList.Drawn.Section]?,
                      studio: Bool, allFailed: MBFailure?) -> SearchList.Drawn {
                SearchList.Drawn(text: term, run: runId, top: top, topSaved: topSaved, topPlace: topPlace,
                                 sections: sections, libraryLate: libraryLate, failed: failedNow, skipped: skippedNow,
                                 musicBrainz: musicBrainz, studio: studio, allFailed: allFailed, counts: counts)
            }
            if whole {
                let picks = SearchList.topPicks(candidates, n: n, library: results, artistList: artistList,
                                                index: marks.index, groups: groups, saved: savedGroups,
                                                evidence: marks.evidence)
                let (sections, allFailed) = sectionsOf(term, plan, pool, out: out)
                let next = base(top: picks.compactMap(\.row), topSaved: SearchList.savedPicks(picks), topPlace: false,
                                sections: sections, studio: studioOn(term, plan, out: out), allFailed: allFailed)
                let settledAll = out.isEmpty && !wanted.isEmpty
                return draw(next, said: [libraryWords, Self.savedSaid(sections),
                                         settledAll ? mbWords(term, plan, pool, wanted: wanted, sections: sections) : ""])
            }
            let phantoms = out.compactMap { SearchList.phantom($0, plan) }
            let decided = SearchList.decidedTop(candidates, phantoms: phantoms, n: n, library: results,
                                                artistList: artistList, index: marks.index, groups: groups,
                                                saved: savedGroups, evidence: marks.evidence)
            //? a phantom first: no prefix - and then no Top results at all, no heading and no place, until moment 2
            return draw(base(top: decided.prefix, topSaved: decided.saved, topPlace: decided.place && !decided.prefix.isEmpty,
                             sections: nil, studio: false, allFailed: nil), said: [libraryWords])
        }

        let withLibrary = !was.libraryLate && librarySettled(term) && isAnswered
        let results = withLibrary ? self.results : nil

        guard let drawnSections = was.sections else {
            guard SearchList.sectionsReady(librarySettled: settled, musicBrainz: musicBrainz,
                                           asked: run.asked || out.isEmpty, out: out, capPassed: run.capPassed) else {
                return nil
            }
            let pool = poolFor(term, plan, results: results, artistList: artistList, marks: marks)
            var top = was.top
            var topSaved = was.topSaved
            if was.topPlace || was.top.isEmpty {
                let picks = SearchList.topPicks(SearchList.candidates(pool, box: term, reading: plan), n: n,
                                                library: results, artistList: artistList, index: marks.index,
                                                groups: groups, saved: savedGroups, evidence: marks.evidence,
                                                fixed: was.top, fixedSaved: was.topSaved)
                top = picks.compactMap(\.row)
                topSaved = SearchList.savedPicks(picks)
            }
            let (sections, allFailed) = sectionsOf(term, plan, pool, out: out)
            let settledAll = out.isEmpty && !wanted.isEmpty
            return draw(was.with(top: top, topSaved: topSaved, topPlace: false, sections: sections,
                                 studio: studioOn(term, plan, out: out), allFailed: allFailed),
                        said: [Self.savedSaid(sections),
                               settledAll ? mbWords(term, plan, pool, wanted: wanted, sections: sections) : ""])
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
            func replaced(_ slot: SearchList.Drawn.Slot?, rows: [SearchRow]? = nil, landed: Set<String> = []) {
                sections = sections.map { (each: SearchList.Drawn.Section) -> SearchList.Drawn.Section in
                    each.kind == kind ? each.with(rows: rows, slot: slot, landed: landed) : each
                }
            }
            if failure(kind, term, plan, view: .all) != nil {
                replaced(.failed)
                continue
            }
            let cap = SearchPacing.cap(kind)
            //? (slice 4) what's saved may be drawn above the slot already: MusicBrainz's answer adds only what isn't,
            //? each part's cap less what it has drawn
            let (libraryDrawn, musicBrainzDrawn) = SearchList.drawnCounts(pool[kind], section.rows)
            let landing = SearchList.lateRows(pool[kind], cap: (max(0, cap.0 - libraryDrawn), max(0, cap.1 - musicBrainzDrawn)),
                                              drawn: Set(section.rows.map(\.key)))
            let landedSaved = pool[kind].savedKeys.intersection(landing.map(\.key))
            let landed = SearchList.drawInOrFold(kind, order)
            if !landing.isEmpty {
                if landed == .into {
                    replaced(nil, rows: section.rows + landing, landed: landedSaved)
                } else {
                    replaced(.show(landing), landed: landedSaved)
                    folded = SearchWords.fold(kind, landing.count).said
                }
            } else if landed == .into {
                if section.rows.isEmpty {
                    sections.removeAll { $0.kind == kind }
                } else {
                    replaced(nil)
                }
            } else {
                //? nothing new, under rows MusicBrainz's answer already holds (what's saved): never "No albums on
                //? MusicBrainz"
                replaced(.said(section.savedRows.isEmpty ? emptyKindWords(kind, term, plan, personal: marks.personal)
                                                         : SearchWords.nothingMore(kind, term)))
            }
        }
        guard changed else { return nil }
        let settledAll = out.isEmpty && !wanted.isEmpty
        //? the studio line was decided with the sections: never added below them as albums land
        return draw(was.with(sections: sections),
                    said: [folded, settledAll ? mbWords(term, plan, pool, wanted: wanted, sections: sections) : ""])
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
            each.kind == kind ? each.with(rows: each.rows + rows, slot: nil) : each
        })
        return rows.first
    }

    /// Everything in hand for these words in the All view, each thing once (`poolFor`).
    private func poolFor(_ term: String, _ plan: SearchPlan, results: LibraryResults?, artistList: [Artist]?,
                         marks: SearchMarks) -> SearchPool {
        let albums = foundAlbums(term, plan, view: .all)
            .map { SearchAlbumsInHand(groups: $0.groups, shown: $0.shown) }
        return SearchList.pool(reading: plan, library: results, artistList: artistList, marks: marks, albums: albums,
                               artists: foundArtists(term, plan, view: .all)?.matches,
                               songs: foundSongs(term, plan, view: .all)?.songs,
                               saved: savedOf(term, plan, view: .all, index: marks.index))
    }

    /// The sections for a draw (`sectionsOf`): each kind with rows, a slot for a kind still out, or its failure while
    /// another kind answered - each with which of its rows are what's saved. Every kind asked failed (none late, none
    /// refused): the foot's block.
    private func sectionsOf(_ term: String, _ plan: SearchPlan, _ pool: SearchPool,
                            out: [SearchKind]) -> ([SearchList.Drawn.Section], MBFailure?) {
        let wanted = drawnMusicBrainz(term) ? Self.wantedKinds(term, plan, view: .all) : []
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
            sections.append(SearchList.Drawn.Section(kind: kind, rows: rows, slot: late ? .asking : failing ? .failed : nil,
                                                     saved: pool[kind].savedKeys.intersection(rows.map(\.key))))
        }
        return (sections, allFailed)
    }

    /// Whether the Albums section's studio line is drawn (`studioOn`) - decided as the sections are drawn: its answer
    /// asked with the studio clause, or - albums still out - its request asking it.
    private func studioOn(_ term: String, _ plan: SearchPlan, out: [SearchKind]) -> Bool {
        if out.contains(.albums) { return SearchAlbums.allAlbumsQuery(plan).studio }
        return foundAlbums(term, plan, view: .all)?.studio ?? false
    }

    /// Why a late kind's slot holds no rows (`emptyKindWords`): everything held (the albums), songs on no album, or
    /// nothing found.
    private func emptyKindWords(_ kind: SearchKind, _ term: String, _ plan: SearchPlan, personal: Bool) -> String {
        if kind == .albums, let found = foundAlbums(term, plan, view: .all), !found.groups.isEmpty {
            return SearchWords.allHeld(personal: personal)
        }
        if kind == .songs, let found = foundSongs(term, plan, view: .all), !found.recordings.isEmpty, found.songs.isEmpty {
            return SongSearch.noRelease(term)
        }
        return SearchWords.empty(kind, term)
    }

    /// What is announced of MusicBrainz once every kind asked has settled (`mbWords`): what it brought to the list as
    /// drawn - more than what's saved above it, when that is drawn (`sections`) - or a refusal's words, every kind
    /// refused.
    private func mbWords(_ term: String, _ plan: SearchPlan, _ pool: SearchPool, wanted: [SearchKind],
                         sections: [SearchList.Drawn.Section]) -> String {
        let answered = wanted.contains { self.answered($0, term, plan, view: .all) }
        let failures = wanted.compactMap { failure($0, term, plan, view: .all) }
        if !answered, let first = failures.first, failures.allSatisfy(\.refused) { return SearchWords.failure(first) }
        var counts: [SearchKind: Int] = [:]
        for kind in SearchKind.allCases {
            let cap = SearchPacing.previewMusicBrainz(kind)
            let left = max(0, cap - min(pool[kind].saved.count, cap))
            counts[kind] = min(pool[kind].musicbrainz.count, left)
        }
        return SearchWords.musicBrainz(counts, answered: answered, saved: sections.contains(where: \.holdsSaved))
    }

    /// What is announced of what's saved, as the sections holding it are drawn (`savedSaid`): "Found earlier: 1 song."
    static func savedSaid(_ sections: [SearchList.Drawn.Section]) -> String {
        var counts: [SearchKind: Int] = [:]
        for section in sections { counts[section.kind] = section.savedRows.count }
        return SearchWords.saved(counts)
    }

    /// The albums to ask for as All's answer lands, so a song's tap plays (Search.tsx's askLibrary): the songs of Top
    /// results' decided picks first, then the answer's - those not in hand already.
    public func albumsWanted(_ text: String, _ results: LibraryResults, artistList: [Artist]?,
                             marks: SearchMarks) -> [String] {
        //? read as MusicBrainz is asked (`planFor`), what's saved in the pool (slice 4): a saved song may lead Top results
        let plan = planFor(text)
        let top = SearchList.decidedPrefix(text, results: results, ownedArtists: ownedArtists, artistList: artistList,
                                           marks: marks, musicBrainz: drawnMusicBrainz(text), reading: plan,
                                           saved: plan.flatMap { savedOf(text, $0, view: .all, index: marks.index) })
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
        let asks = planFor(query).map { !Self.wantedKinds(query, $0, view: SearchView(wanted)).isEmpty } ?? false
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

    /// The key a kind view's area is kept by (Search.tsx `areaKey`): its kind and the box's words - nil in All.
    public var kindAreaKey: String? {
        guard let wanted = view.kind, !query.isEmpty else { return nil }
        return "\(wanted.rawValue)\n\(query)"
    }

    /// What a kind view holds as it stands (Search.tsx `kindModel`): its library's rows (its chip's own search3), then
    /// (slice 4) what's saved and MusicBrainz's of its kind, the library's left out - each row once drawn kept in its
    /// place, and as what it was drawn as, as later answers land (`before`: the area drawn for these words last, which
    /// the caller keeps from the view's `area`, `kindArea`). Nil for All, or an empty box.
    public func kindView(artistList: [Artist]?, marks: SearchMarks, before: KindArea? = nil) -> KindView? {
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
        //? the view's own kind's answer, for the key it asks now
        let mine: KindAnswer?
        if let keyNow {
            switch wanted {
            case .albums: mine = albums.key == keyNow ? KindAnswer(albums) : nil
            case .artists: mine = artists.key == keyNow ? KindAnswer(artists) : nil
            case .songs: mine = songs.key == keyNow ? KindAnswer(songs) : nil
            }
        } else {
            mine = nil
        }
        let mbAllowed = libSettled || kindLateFor == lateKey
        let libraryOf = lib?.rows ?? []
        let libraryAlbums = libraryOf.compactMap { (row: SearchRow) -> Album? in
            if case .album(let album) = row { return album }
            return nil
        }
        let librarySongs = libraryOf.compactMap { (row: SearchRow) -> Song? in
            if case .song(let song) = row { return song }
            return nil
        }
        //? the library's artists of the view, and the one the box named - who MusicBrainz's are told apart from
        let listed = (libraryOf + answeredRows).compactMap { (row: SearchRow) -> Artist? in
            if case .artist(let artist) = row { return artist }
            return nil
        }
        //? MusicBrainz's rows of this kind, in its order, the library's left out
        var mbRows: [SearchRow] = []
        var groups: [ReleaseGroup] = []
        var recordings = 0
        if mbAllowed, mine == .done {
            switch wanted {
            case .albums:
                if let found = albums.found {
                    groups = found.groups
                    mbRows = Self.albumRows(found.groups, shown: found.shown, index: marks.index, library: libraryAlbums)
                }
            case .artists:
                if let found = artists.found {
                    mbRows = Self.artistRows(found.matches, artistList: artistList, index: marks.index, listed: listed).rows
                }
            case .songs:
                if let found = songs.found {
                    recordings = found.recordings.count
                    mbRows = Self.songRows(found.songs, library: librarySongs, marks: marks)
                }
            }
        }
        //? (slice 4) what's saved leads MusicBrainz's rows - deduped against the library's as MusicBrainz's are, and
        //? MusicBrainz's answer against it by key: drawn as soon as the view's library is, MusicBrainz's added below.
        //? `savedMarked`: the rows that are what's saved's own (a library artist brought in through it is the library's)
        var savedRows: [SearchRow] = []
        var savedMarked = Set<String>()
        if mbAllowed, let plan, let kept = savedOf(query, plan, view: view, index: marks.index) {
            switch wanted {
            case .albums:
                savedRows = Self.albumRows(kept.groups, shown: kept.shown, index: marks.index, library: libraryAlbums)
                savedMarked = Set(savedRows.map(\.key))
            case .artists:
                let made = Self.artistRows(kept.matches, artistList: artistList, index: marks.index, listed: listed)
                savedRows = made.rows
                savedMarked = made.musicBrainz
            case .songs:
                savedRows = Self.songRows(kept.songs, library: librarySongs, marks: marks)
                savedMarked = Set(savedRows.map(\.key))
            }
        }
        var failed: MBFailure?
        if case .failed(let failure)? = mine { failed = failure }
        let landed = mine == .done || failed != nil
        //? MusicBrainz's rows held while what's saved is still being asked for these words (SearchSaved.waitMs at most,
        //? then given up): the two drawn together, saved first - its failure as its rows - never once any of them is
        //? drawn below (taken away again, they would move everything below)
        let mbHeld = !savedSettled(query) && landed && (before?.rest.isEmpty ?? true) && !(before?.problem ?? false)
        //? ...and what is drawn kept where it is as answers land after it: a late saved answer goes below - below
        //? MusicBrainz's failure too, once that is drawn (else its Try again moved down under the finger)
        let problem = mbAllowed && !mbHeld && failed != nil
        let arranged = KindArea.arrange(before, saved: savedRows, musicbrainz: mbHeld ? [] : mbRows,
                                        above: Set(answeredRows.map(\.key)), problem: problem)
        let lead = arranged.lead
        let rest = arranged.rest
        func fromSaved(_ row: SearchRow) -> Bool {
            arranged.area.from[row.key] == .saved && savedMarked.contains(row.key)
        }
        let savedCount = (lead + rest).filter(fromSaved).count
        //? an artist read before a title asks MusicBrainz nothing of artists: the artist named is the library's
        let noMusicBrainz = wanted == .artists && plan?.kind == .albumByArtist
        let searching = !late && !libSettled
        let nothing = libSettled && lib?.state != .failed && answeredRows.isEmpty && lead.isEmpty && !mbHeld
            && (noMusicBrainz || (mine == .done && rest.isEmpty && !(wanted == .albums && !groups.isEmpty)))
        var foot: KindView.Foot?
        var more: KindView.More?
        if !noMusicBrainz {
            if !musicBrainz && mine == nil {
                foot = .typeMore
            } else if wanted == .songs && plan?.kind == .artist {
                //? an artist's name alone asks no song: a title is needed with it
                foot = .needATitle
            } else if mbAllowed {
                if mbHeld {
                    foot = .searching
                } else {
                    switch mine {
                    case .none, .searching?:
                        foot = musicBrainz || mine != nil ? .searching : nil
                    case .failed(let failure)?:
                        foot = .failed(failure)
                    case .done?:
                        if !rest.isEmpty {
                            foot = .rows(rest)
                        } else if !nothing && lead.isEmpty {
                            if wanted == .albums && !groups.isEmpty {
                                foot = .said(SearchWords.allHeld(personal: marks.personal))
                            } else if wanted == .songs && recordings > 0 {
                                foot = .said(SongSearch.noRelease(query))
                            } else {
                                foot = .said(SearchWords.empty(wanted, query))
                            }
                        }
                        more = moreOf(wanted, personal: marks.personal)
                    }
                }
            }
        }
        var below: [SearchRow] = []
        switch foot {
        case .searching?, .failed?: below = rest
        default: break
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
        //? the view's region (Search.tsx's layout effect): its library's rows as they draw, then MusicBrainz's or its
        //? failure - what's saved said with MusicBrainz's words, drawn above them
        var libraryWords: String?
        if showLib {
            let words = SearchWords.library([wanted: libraryRows.count], personal: marks.personal)
            //? a view that asks MusicBrainz nothing (Artists under album-by-artist) and found nothing says so
            libraryWords = words.isEmpty && noMusicBrainz && nothing ? SearchWords.nothing(SearchView(wanted), query) : words
        }
        var musicBrainzWords: String?
        if mbAllowed && !mbHeld && !noMusicBrainz && landed {
            var parts: [String] = []
            if savedCount > 0 { parts.append(SearchWords.saved([wanted: savedCount])) }
            if let failed {
                parts.append(savedCount > 0 ? SearchWords.savedAway(failed, short: true) : SearchWords.failure(failed, short: true))
            } else {
                let fresh = rest.filter { (row: SearchRow) -> Bool in !fromSaved(row) }.count
                parts.append(SearchWords.musicBrainz([wanted: fresh], answered: true, saved: savedCount > 0))
            }
            musicBrainzWords = parts.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return KindView(kind: wanted, lateSlot: lateSlot, searching: searching,
                        searchingMusicBrainz: musicBrainz && keyNow != nil && !noMusicBrainz,
                        libraryFailed: lib?.state == .failed && !late,
                        libraryRows: libraryRows, own: showLib ? lib : nil, foot: foot, nothing: nothing,
                        savedRows: lead, below: below, more: more, savedCount: savedCount,
                        said: KindView.Said(key: "\(lateKey)\n\(keyNow ?? "")", library: libraryWords,
                                            musicBrainz: musicBrainzWords),
                        area: mbAllowed ? arranged.area : nil)
    }

    /// A kind view's MusicBrainz albums, in MusicBrainz's order: those shown, and those held that its own search didn't
    /// list (`heldUnlisted`) - marked in place.
    static func albumRows(_ groups: [ReleaseGroup], shown: [ReleaseGroup], index: OwnedIndex?,
                          library: [Album]) -> [SearchRow] {
        let held = Set(SearchAlbums.heldUnlisted(groups, index, library).map(\.id))
        let shownIds = Set(shown.map(\.id))
        return groups.filter { shownIds.contains($0.id) || held.contains($0.id) }.map { SearchRow.group($0) }
    }

    /// ...its artists, in MusicBrainz's order: a library artist answering to the name brought in at their place,
    /// MusicBrainz's others - `musicBrainz` the keys of MusicBrainz's own.
    static func artistRows(_ matches: [MBArtistMatch], artistList: [Artist]?, index: OwnedIndex?,
                           listed: [Artist]) -> (rows: [SearchRow], musicBrainz: Set<String>) {
        let split = SearchList.newArtists(matches, known: SearchList.knownArtists(artistList, listed), index: index,
                                          listed: listed)
        var brought: [Int: Artist] = [:]
        for each in split.brought { brought[each.position] = each.artist }
        var kept: [Int: MBArtistMatch] = [:]
        for each in split.musicbrainz { kept[each.position] = each.match }
        var rows: [SearchRow] = []
        var theirs = Set<String>()
        for at in matches.indices {
            if let artist = brought[at] {
                rows.append(.artist(artist))
            } else if let match = kept[at] {
                let row = SearchRow.mbArtist(match)
                rows.append(row)
                theirs.insert(row.key)
            }
        }
        return (rows, theirs)
    }

    /// ...its songs, in the order found: those nobody has, and those on an album held that the library didn't list.
    static func songRows(_ found: [FoundSong], library: [Song], marks: SearchMarks) -> [SearchRow] {
        let split = SearchList.newSongs(found, library: library, index: marks.index, evidence: marks.evidence)
        let kept = Set(split.musicbrainz.map { FoldKey($0.song.key) } + split.brought.map { FoldKey($0.song.key) })
        return found.filter { kept.contains(FoldKey($0.key)) }.map { SearchRow.mbSong($0) }
    }

    /// More from MusicBrainz as a kind view draws it under its answer (Search.tsx's kindView): what its last page
    /// brought, its failure, and the button while there is another page - or the far note. Nil when there is nothing
    /// to draw.
    private func moreOf(_ wanted: SearchKind, personal: Bool) -> KindView.More? {
        let next: Int
        let count: Int?
        let last: Int
        let limit: Int
        let page: MorePage
        var note: String?
        switch wanted {
        case .albums:
            guard let found = albums.found else { return nil }
            (next, count, last, limit, page) = (found.nextOffset, found.count, found.last, SearchAlbums.limit, found.more)
            if case .added(let added, let held) = page {
                note = SearchMore.pageWords(added: added, held: held, personal: personal).note
            }
        case .artists:
            guard let found = artists.found else { return nil }
            (next, count, last, limit, page) = (found.nextOffset, found.count, found.last, MBArtistSearch.limit, found.more)
        case .songs:
            guard let found = songs.found else { return nil }
            (next, count, last, limit, page) = (found.nextOffset, found.count, found.last, SongSearch.limit, found.more)
            if case .added(let added, let grown) = page {
                note = SearchMore.songsWords(added: added, grown: grown).note
            }
        }
        let pages = SearchMore.pages(next: next, count: count, last: last, limit: limit)
        var failure: MBFailure?
        if case .failed(let failed) = page { failure = failed }
        guard note != nil || failure != nil || pages != .end else { return nil }
        let asking = page == .asking
        let label = asking ? SearchWords.loading : failure != nil ? SearchWords.tryAgain : SearchMore.button(wanted)
        return KindView.More(note: note, failure: failure, pages: pages, asking: asking, label: label)
    }

    /// A kind's answer as a kind view reads it, whatever it found.
    enum KindAnswer: Equatable {
        case searching, done
        case failed(MBFailure)

        init?<Found>(_ answer: Answer<Found>) {
            switch answer {
            case .idle: return nil
            case .searching: self = .searching
            case .done: self = .done
            case .failed(_, _, let failure): self = .failed(failure)
            }
        }
    }
}

/// A MusicBrainz kind's answer as SearchState keeps it: the words it answers, and the key they were asked by.
public protocol SearchFound: Sendable, Equatable {
    var text: String { get }
    var key: String { get }
}

/// A kind view as drawn (Search.tsx's kindView): the place kept for its late library, the asking line before its
/// library lands, its library's failure, its rows and More, then MusicBrainz's part below - what's saved leading it
/// (slice 4), More from MusicBrainz at its foot - and "No albums for …" when nothing at all was found.
public struct KindView: Sendable, Equatable {
    /// MusicBrainz's part, below the library's (and below what's saved).
    public enum Foot: Sendable, Equatable {
        /// MusicBrainz not asked yet: `SearchWords.typeMore`.
        case typeMore
        /// The Songs view under the artist reading: no song is asked by an artist's name alone (`SONGS_NEED_A_TITLE`).
        case needATitle
        /// "Searching…" - `below` drawn under it.
        case searching
        /// Its words (earlier results', under what's saved), and Try again unless refused - `below` drawn under it.
        case failed(MBFailure)
        case rows([SearchRow])
        /// Why there are none: everything held, or nothing else found.
        case said(String)
    }

    /// More from MusicBrainz, under its answer's rows (slice 4): what its last page brought (`note`), its last ask's
    /// failure, and the button while there is another page (`pages` `.more`, its `label` "More albums", "Loading…" or
    /// "Try again") - or, past the furthest page MusicBrainz serves (`.far`), `SearchMore.far`.
    public struct More: Sendable, Equatable {
        public let note: String?
        public let failure: MBFailure?
        public let pages: SearchMore.Pages
        public let asking: Bool
        public let label: String
    }

    /// What the view's region says (Search.tsx's layout effect), each once for its `key` (its words, kind and the
    /// query it asks): its library's words once they are drawn, and MusicBrainz's - what's saved's with them - once it
    /// has answered or failed. Nil while not yet; "" for nothing to say.
    public struct Said: Sendable, Equatable {
        public let key: String
        public let library: String?
        public let musicBrainz: String?
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
    /// (Slice 4) What's saved, leading MusicBrainz's part; the rows that landed after the asking line or the failure
    /// was drawn, under it (`below` - with `.rows`, they are its rows).
    public let savedRows: [SearchRow]
    public let below: [SearchRow]
    public let more: More?
    /// How many rows drawn are what's saved's.
    public let savedCount: Int
    public let said: Said
    /// What is drawn below its library's rows, to keep for these words (`kindArea`) - nil while MusicBrainz's part
    /// isn't drawn.
    public let area: KindArea?
}
