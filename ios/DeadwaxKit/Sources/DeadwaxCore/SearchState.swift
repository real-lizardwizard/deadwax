import Foundation

/// Search's state for one person, the library's half (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 2.6-2.7;
/// the web's app/Search.tsx: its `library`, `drawn`, `kindLibrary`, `ready`, `view` and runs): what the box says,
/// what has been asked for which words, the list drawn - frozen once drawn - and a kind view's own. Pure: the app's
/// SearchModel makes the requests and the pause, and tells this what landed; every rule of when to ask and when to
/// draw is here, tested on Linux.
///
/// - The box's words, trimmed (`query`). Typing other words starts a new run: the list drawn stays until the library
///   settles for the new words, then theirs takes its place. An empty box lets everything go.
/// - All's search3 is asked once per words (`wantsLibrary`) - again only after a failure, Try again, or the keyboard's
///   Search on a failure; only the newest ask's answer counts (`libraryAnswered`'s token).
/// - The list is drawn once per run (`advance`), only in the All view: a chip, See all and Back to All draw afresh.
/// - A kind view asks its own (`wantsKind`), kept for its words and kind; More by offset (`askingMore`).
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

    /// The words All's search3 was asked for (`libraryAsked`) - nil after a failure, so it is asked again.
    private var libraryAsked: String?
    /// The run: one more for new words, Try again, Back to All - the list is drawn once per run.
    private var run = 0
    private var drawnRun = -1
    /// Only the newest ask's answer counts: All's, and a kind view's (its More's too).
    private var allToken = 0
    private var kindToken = 0

    public init() {}

    // MARK: the box and the view

    /// The box changed: its words trimmed. True when it emptied - everything let go, the view back to All (the caller
    /// calls off what it asked).
    @discardableResult
    public mutating func typed(_ text: String) -> Bool {
        let next = JSText.trim(text)
        guard !WebText.same(next, query) else { return false }
        query = next
        run += 1
        guard next.isEmpty else { return false }
        libraryText = nil
        library = nil
        libraryAsked = nil
        drawn = nil
        kind = nil
        ready = [:]
        view = .all
        allToken += 1
        kindToken += 1
        return true
    }

    /// A chip, See all, Back to All. Back to All draws the list afresh from what is in hand (your own act). True when
    /// the view changed.
    @discardableResult
    public mutating func choose(_ next: SearchView) -> Bool {
        guard next != view else { return false }
        view = next
        if next == .all { run += 1 }
        return true
    }

    /// Try again (the library's failure), or Navidrome back after the library was skipped: asked again, and the list
    /// drawn afresh once it settles.
    public mutating func tryAgain() {
        libraryAsked = nil
        run += 1
    }

    /// deadwax back, or Navidrome found again (Search.tsx's status effect, :1087-1100): the words' library, failed or
    /// skipped, is asked again - and a list this run drew with the failure in it, or without the library, starts a new
    /// run, so the new answer is drawn in its place (the web's late review: "asked again, its answer was drawn
    /// nowhere"). True when the library is to be asked again.
    @discardableResult
    public mutating func resumed() -> Bool {
        guard !query.isEmpty, let libraryText, WebText.same(libraryText, query),
              library == .failed || library == .skipped else { return false }
        libraryAsked = nil
        if drawnRun == run, let drawn, WebText.same(drawn.text, query) { run += 1 }
        return true
    }

    /// The keyboard's Search: All asked now when not yet asked for the words, or failed - a list drawn with the failure
    /// drawn afresh once the new answer lands (Search.tsx's submit, the library's part).
    public mutating func submitted() {
        guard !query.isEmpty else { return }
        if libraryText == query, library == .failed {
            libraryAsked = nil
            if view == .all, drawn?.text == query { run += 1 }
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
    public var settled: Bool {
        guard let libraryText, WebText.same(libraryText, query), let library else { return false }
        return library != .asking
    }

    private var isAnswered: Bool {
        if case .answered? = library { return true }
        return false
    }

    // MARK: the list drawn

    /// The All view's next draw (Search.tsx `advance`, the library's part): a run's list, once the library has settled
    /// for its words - made from what is in hand then, and frozen. Nil when nothing new is drawn.
    public mutating func advance(ownedArtists: [String], artistList: [Artist]?, marks: SearchMarks) -> SearchList.Drawn? {
        guard view == .all, !query.isEmpty, drawnRun != run, settled else { return nil }
        guard let next = SearchList.draw(query, results: resultsForQuery, failed: library == .failed,
                                         skipped: library == .skipped, ownedArtists: ownedArtists,
                                         artistList: artistList, marks: marks) else { return nil }
        drawn = next
        drawnRun = run
        return next
    }

    /// The albums to ask for as All's answer lands, so a song's tap plays (Search.tsx's askLibrary): the songs of Top
    /// results as they will be drawn first, then the answer's - those not in hand already.
    public func albumsWanted(_ text: String, _ results: LibraryResults, ownedArtists: [String], artistList: [Artist]?,
                             marks: SearchMarks) -> [String] {
        let top = SearchList.draw(text, results: results, failed: false, ownedArtists: ownedArtists,
                                  artistList: artistList, marks: marks)?.top ?? []
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

    /// The kind view's ask begins: its token and kind - nil when it isn't wanted.
    public mutating func askingKind() -> (token: Int, kind: SearchKind)? {
        guard wantsKind, let wanted = view.kind else { return nil }
        kindToken += 1
        kind = KindLibrary(text: query, kind: wanted)
        return (kindToken, wanted)
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
}
