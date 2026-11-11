import DeadwaxCore
import Foundation
import Observation

/// How the Albums screens lay their albums out: tiles (the web's only view) or rows - the phone's own choice
/// (library.md Open question 3), one per device, tiles by default.
enum LibraryLayout: String, CaseIterable, Sendable {
    case grid
    case list

    /// Where the choice is kept (the phone's own key: the web has no list view).
    static let storageKey = "deadwax-library-view"

    /// The layout as a device saved it: one of these, anything else the grid.
    init(saved: String?) {
        self = saved.flatMap(LibraryLayout.init(rawValue:)) ?? .grid
    }

    /// The toolbar button's words, which say what it switches TO - the phone's own (the web has no switch).
    var switchLabel: String { self == .grid ? "Show as list" : "Show as grid" }
    var switchSymbol: String { self == .grid ? "list.bullet" : "square.grid.2x2" }
}

/// One scope's list as the screens draw it: the answer's albums with their keys and Find texts made once (Core's
/// Shelf, built off the main actor as the answer lands), whether the route stopped at its cap, and which answer it
/// is (`serial` goes up by one with every answer kept).
struct KeptShelf {
    let serial: Int
    let shelf: Shelf
    let truncated: Bool
}

/// One header's run of albums, as a screen draws it: its place among the groups (what the index jumps to), its
/// words, and its albums in order.
struct DrawnGroup: Identifiable {
    let id: Int
    let label: String?
    let albums: [IndexAlbum]
}

/// Everything one Albums screen draws for a sort and what is typed into Find (Core's ShelfView, its places turned
/// into albums) - made once per list, sort and Find, never in a view's body.
struct DrawnShelf {
    let serial: Int
    let sort: AlbumSort
    let typed: String
    /// every album of the list, in Navidrome's order (what AlbumListBody reads)
    let albums: [IndexAlbum]
    let view: ShelfView
    let groups: [DrawnGroup]
    let truncated: Bool
}

/// The Library tab's lists, kept across its pages and launches (library.md 4, D2):
///
/// - The album index of each scope as Core's AlbumIndexState keeps it - one ask per generation shared by every
///   screen, the newest answer only, a 304 against the ETag sent keeps the list, 60 s fresh. Asked in an unstructured
///   task, so a screen left before its answer doesn't cancel the one request every screen shares.
/// - The last answer and its ETag on disk per (server, person, scope) (AlbumIndexFiles), restored before the first
///   ask - drawn at once, and asked with its ETag, so an unchanged list is a 304.
/// - Each answer's Shelf (its keys made once, off the main actor) and what a screen draws of it (`drawn`), made once
///   per list, sort and Find.
/// - The sort and the layout, per device.
/// - Your library (GET /me/library, logins on with a library of your own): the New marks (Core's MyLibraryState),
///   "cleared when you open it" (POST /me/library/seen), and your albums asked again when its starred count moves
///   (Core's StarredCountWatch).
///
/// Every rule is Core's; this keeps the state, makes the requests and the files. `reset()` - a new person - drops
/// everything in memory, and nothing asked before it lands after it.
@MainActor
@Observable
final class LibraryModel {
    /// Where the album sort is kept: the web's own name for it (persisted.ts `deadwax-player-order`), as Repeat and
    /// Normalization keep theirs; read with AlbumSort(saved:).
    static let sortKey = "deadwax-player-order"

    /// The album index of each scope, as Core's state keeps it (what's kept, what's being asked).
    private(set) var index = AlbumIndexState()
    /// The last failure asking a scope, per scope; nil once an ask for it begins again, or it answers.
    private(set) var failures: [AlbumScope: APIFailure] = [:]

    /// Each scope's list as drawn - nil until one has landed (or been restored) and its keys are made.
    private(set) var shelves: [AlbumScope: KeptShelf] = [:]
    /// The generation each scope is on (AlbumIndexState.generation) - what a screen keys its ask on, so a list
    /// forgotten (an Add or a Remove, the starred count moving, older than a minute as it shows) is asked again.
    private(set) var generations: [AlbumScope: Int] = [:]
    /// The album order, one for both scopes (ALBUM_SORTS; the web's ids, saved per device).
    var sort: AlbumSort = AlbumSort(saved: UserDefaults.standard.string(forKey: LibraryModel.sortKey)) {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey) }
    }
    /// Tiles or rows, per device.
    var layout: LibraryLayout = LibraryLayout(saved: UserDefaults.standard.string(forKey: LibraryLayout.storageKey)) {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: LibraryLayout.storageKey) }
    }
    /// Your library as deadwax last said it, and the albums opened before it first did (logins on, a library of
    /// your own; nil answer otherwise).
    private(set) var mine = MyLibraryState()
    /// Each scope's last answer: when, how long it took, and how many albums - for Debug (check 1 counts them
    /// against the web's Library, and times James's library, recorded nowhere yet).
    private(set) var lastFetch: [AlbumScope: IndexFetch] = [:]
    /// What the last check of Navidrome found (GET /navidrome/status) - nil before one has, when the Library draws
    /// meanwhile (NavidromeGate.shownOnPhone). What the gate closes on.
    private(set) var navidrome: NavidromeGate.Checked?
    /// A check of Navidrome is out (the gate's Try again shows it busy).
    private(set) var checkingNavidrome = false

    /// One album index answer, as Debug may show it.
    struct IndexFetch: Equatable {
        /// 200 (a new list) or 304 (the one kept still stands)
        let status: Int
        /// the albums in it (the kept list's, for a 304)
        let albums: Int
        let seconds: Double
        let at: Date
    }

    private let server: ServerModel
    private let files: AlbumIndexFiles

    /// Each request on its way, by its Ask's id - every look at the same generation waits for the same one. True
    /// when it came back as a 304 that can't be used (a newer list landed since): the next look asks again.
    @ObservationIgnored private var asking: [Int: Task<Bool, Never>] = [:]
    /// The list kept on disk read back, once per person and scope, before the first ask.
    @ObservationIgnored private var restoring: [AlbumScope: Task<Void, Never>] = [:]
    /// One more at every reset: nothing begun for the person before lands after.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var serials: [AlbumScope: Int] = [:]
    @ObservationIgnored private var sortedCache: [AlbumScope: (serial: Int, sort: AlbumSort, places: [Int])] = [:]
    @ObservationIgnored private var drawnCache: [AlbumScope: DrawnShelf] = [:]
    /// Only the newest /me/library answer counts (latestOnly).
    @ObservationIgnored private var mineAsks = 0
    /// Only the newest Navidrome check counts (navidromeCheck.ts's latestOnly).
    @ObservationIgnored private var navidromeAsks = 0
    @ObservationIgnored private var starredCount = StarredCountWatch()
    /// The last write of each kept list, so writes of one list land in the order its answers did.
    @ObservationIgnored private var writes: [AlbumIndexFiles.Key: Task<Void, Never>] = [:]

    init(server: ServerModel, files: AlbumIndexFiles = AlbumIndexFiles()) {
        self.server = server
        self.files = files
    }

    /// The scope the Albums list shows for the person signed in (AlbumScope.albums(for: me)): yours with a library
    /// of your own, else the store's.
    var scope: AlbumScope { AlbumScope.albums(for: server.me) }

    /// What's kept of `scope`, newest answer first; nil before one has come.
    func albums(_ scope: AlbumScope) -> AlbumIndexAnswer? { index.kept(scope)?.answer }

    /// What is new in your library (the tiles' New marks) - none with logins off or before deadwax has said.
    var marks: NewMarks { mine.marks }

    // MARK: the album index

    /// A screen's look at `scope`'s list (`albumIndex(scope)`): the list kept on disk restored first (once), then
    /// one request per generation, shared - this one made, or the one on its way waited for. Returns once the list
    /// is in hand or the ask failed (`failures`).
    func load(_ scope: AlbumScope) async {
        let epoch = self.epoch
        await restore(scope)
        guard epoch == self.epoch, !Task.isCancelled else { return }
        await look(scope, epoch: epoch, tries: 2)
    }

    /// Pull to refresh: asked again now, whatever its age (with the ETag held - an unchanged list is a 304), and
    /// your library with it.
    func refresh(_ scope: AlbumScope) async {
        index.forget(scope)
        syncGeneration(scope)
        if server.access.hasLibrary { Task { await askMine() } }
        await load(scope)
    }

    /// `refreshIfOld`: forgotten - so the screen showing it asks again - when the list in hand is over a minute old
    /// and nothing is on its way. As an Albums screen shows.
    func refreshIfOld(_ scope: AlbumScope) {
        if index.refreshIfOld(scope, now: Self.nowMs()) { syncGeneration(scope) }
    }

    /// The Library tab came into view (the tab picked, the app back in front on it, a new person): Navidrome checked
    /// until it is found answering, its lists asked again if over a minute old - the store's always, yours with a
    /// library of your own - and your library asked for its New marks (App.tsx's libraryShown).
    func libraryShown() {
        if navidrome?.status.ok != true, !checkingNavidrome { Task { await checkNavidrome() } }
        refreshIfOld(.store)
        guard server.access.hasLibrary else { return }
        refreshIfOld(.yours)
        Task { await askMine() }
    }

    private func look(_ scope: AlbumScope, epoch: Int, tries: Int) async {
        guard tries > 0, epoch == self.epoch, let client = server.client else { return }
        let look = index.list(scope)
        switch look {
        case .have:
            return
        case .wait(let ask):
            _ = await asking[ask.id]?.value
        case .ask(let ask):
            setFailure(scope, nil)
            let disk = diskKey(scope)
            let task = Task { await self.fetch(ask, client: client, disk: disk, epoch: epoch) }
            asking[ask.id] = task
            if await task.value { await self.look(scope, epoch: epoch, tries: tries - 1) }
        }
    }

    /// One request for a scope's list, and what came of it - true when a 304 couldn't be used and the list must be
    /// asked again.
    private func fetch(_ ask: AlbumIndexState.Ask, client: DeadwaxClient, disk: AlbumIndexFiles.Key?,
                       epoch: Int) async -> Bool {
        let scope = ask.scope
        let clock = ContinuousClock()
        let started = clock.now
        defer { asking[ask.id] = nil }
        do {
            let fetched = try await client.fetch(Routes.albumIndex, as: AlbumIndexAnswer.self,
                                                 query: [("scope", scope.rawValue)], ifNoneMatch: ask.ifNoneMatch)
            guard epoch == self.epoch else { return false }
            let seconds = Self.seconds(clock.now - started)
            switch fetched {
            case .fresh(let answer, let etag):
                let now = Self.nowMs()
                lastFetch[scope] = IndexFetch(status: 200, albums: answer.albums.count, seconds: seconds, at: Date())
                if index.landed(ask, answer: answer, etag: etag, now: now) {
                    if let disk { keep(disk, AlbumIndexFiles.Saved(answer: answer, etag: etag, at: now)) }
                    await build(scope, answer: answer).value
                }
            case .unchanged:
                let still = index.unchanged(ask, now: Self.nowMs())
                lastFetch[scope] = IndexFetch(status: 304, albums: index.kept(scope)?.answer.albums.count ?? 0,
                                              seconds: seconds, at: Date())
                if !still { return true }
            }
            setFailure(scope, nil)
            return false
        } catch {
            guard epoch == self.epoch else { return false }
            index.failed(ask)
            if APIFailure.isCancellation(error) { return false }
            // only the newest ask's problem is said (latestOnly): a newer one on its way speaks for itself
            if index.asking(scope) == nil {
                setFailure(scope, error as? APIFailure ?? .other(String(describing: error)))
            }
            return false
        }
    }

    /// A list that landed, written to disk after the one before it of the same key.
    private func keep(_ key: AlbumIndexFiles.Key, _ saved: AlbumIndexFiles.Saved) {
        let before = writes[key]
        let files = self.files
        writes[key] = Task.detached(priority: .utility) {
            await before?.value
            await files.write(key, saved)
        }
    }

    /// The list kept on disk for this person and scope, read back once - before the first ask, so that ask carries
    /// its ETag - and drawn at once (its keys made off the main actor; the ask doesn't wait for them).
    private func restore(_ scope: AlbumScope) async {
        if let restoring = restoring[scope] {
            await restoring.value
            return
        }
        guard let key = diskKey(scope) else { return }
        let epoch = self.epoch
        let task = Task {
            guard let saved = await self.files.read(key), epoch == self.epoch, self.index.kept(scope) == nil else { return }
            self.index.restore(scope, answer: saved.answer, etag: saved.etag, at: saved.at)
            _ = self.build(scope, answer: saved.answer)
        }
        restoring[scope] = task
        await task.value
    }

    /// The Shelf of a list just kept - its keys and Find texts made once, off the main actor - drawn in place of
    /// the one before when it is ready, unless a newer list was kept meanwhile.
    private func build(_ scope: AlbumScope, answer: AlbumIndexAnswer) -> Task<Void, Never> {
        let serial = (serials[scope] ?? 0) + 1
        serials[scope] = serial
        let epoch = self.epoch
        return Task {
            let shelf = await Task.detached(priority: .userInitiated) { Shelf(answer.albums) }.value
            guard epoch == self.epoch, self.serials[scope] == serial else { return }
            self.shelves[scope] = KeptShelf(serial: serial, shelf: shelf, truncated: answer.truncated)
        }
    }

    /// Where this person's list of `scope` is kept on disk - nil before /me has said who they are.
    private func diskKey(_ scope: AlbumScope) -> AlbumIndexFiles.Key? {
        guard let address = server.address, let me = server.me else { return nil }
        return AlbumIndexFiles.Key(server: address.key, user: me.user, scope: scope)
    }

    private func syncGeneration(_ scope: AlbumScope) {
        let now = index.generation(scope)
        if generations[scope] != now { generations[scope] = now }
    }

    private func setFailure(_ scope: AlbumScope, _ failure: APIFailure?) {
        if failures[scope] != failure { failures[scope] = failure }
    }

    // MARK: what a screen draws

    /// What an Albums screen of `scope` draws for the sort chosen and `typed` into Find (Core's Shelf.view): the
    /// sorted list made once per list and sort, Find's and the headers' once per what is typed. Nil before a list.
    func drawn(_ scope: AlbumScope, typed: String) -> DrawnShelf? {
        guard let kept = shelves[scope] else { return nil }
        let sort = self.sort
        if let cached = drawnCache[scope], cached.serial == kept.serial, cached.sort == sort, cached.typed == typed {
            return cached
        }
        let places: [Int]
        if let cached = sortedCache[scope], cached.serial == kept.serial, cached.sort == sort {
            places = cached.places
        } else {
            places = kept.shelf.sorted(sort, by: scope.addedBy)
            sortedCache[scope] = (kept.serial, sort, places)
        }
        let view = kept.shelf.view(sort, by: scope.addedBy, typed: typed, sorted: places)
        let albums = kept.shelf.albums
        let groups = view.groups.enumerated().map { at, group in
            DrawnGroup(id: at, label: group.label, albums: group.items.map { albums[$0] })
        }
        let drawn = DrawnShelf(serial: kept.serial, sort: sort, typed: typed, albums: albums, view: view, groups: groups,
                               truncated: kept.truncated)
        drawnCache[scope] = drawn
        return drawn
    }

    // MARK: Navidrome

    /// Asks whether deadwax has a Navidrome that answers (navidromeChecks' check): at the Library's first showing for
    /// a person, as it shows again while it wasn't found answering, from the gate's Try again, after a sign-in again.
    /// Quiet: what was found stands until the answer lands, and only the newest answer counts.
    func checkNavidrome() async {
        guard let client = server.client else { return }
        navidromeAsks += 1
        let asked = navidromeAsks
        let epoch = self.epoch
        checkingNavidrome = true
        let found: NavidromeGate.Checked
        do {
            found = .answered(try await client.call(Routes.navidromeStatus, as: NavidromeStatus.self))
        } catch {
            guard asked == navidromeAsks, epoch == self.epoch else { return }
            if APIFailure.isCancellation(error) {
                checkingNavidrome = false
                return
            }
            let failure = error as? APIFailure ?? .other(String(describing: error))
            found = .failed(failure, problem: failure.words)
        }
        guard asked == navidromeAsks, epoch == self.epoch else { return }
        checkingNavidrome = false
        navidrome = found
    }

    // MARK: your library (logins on, a library of your own)

    /// GET /me/library - the New marks, and your albums asked again when its starred count moved. Only the newest
    /// answer counts; a failed ask keeps the last answer. Nothing with logins off or for the break-glass admin.
    func askMine() async {
        guard server.access.hasLibrary, let client = server.client else { return }
        mineAsks += 1
        let asked = mineAsks
        let epoch = self.epoch
        guard let answer = try? await client.call(Routes.myLibrary, as: MyLibrary.self),
              asked == mineAsks, epoch == self.epoch else { return }
        for body in mine.landed(answer, personal: server.access.hasLibrary) { tellSeen(body) }
        if starredCount.saw(answer) {
            index.forget(.yours)
            syncGeneration(.yours)
        }
    }

    /// An album page opened (`seenAlbum`): an album new in your library is taken off the marks at once and deadwax
    /// is told; one opened before deadwax first said is looked at as its answer lands. The Library's tiles call it
    /// as they open their album; the album page should too (Go to album, an album reached another way).
    func opened(id: String, musicBrainzId: String?) {
        let opened = MyLibraryState.Opened(id: id, musicBrainzId: musicBrainzId)
        guard let body = mine.opened(opened, personal: server.access.hasLibrary) else { return }
        tellSeen(body)
    }

    func opened(_ album: IndexAlbum) { opened(id: album.id, musicBrainzId: album.musicBrainzId) }

    /// Signed in again over the app (a session that ended mid-use): every list whose last ask failed - signed out,
    /// most likely - is asked again at its screen's next look, and your library with them.
    func signedInAgain() {
        for scope in Array(failures.keys) {
            index.forget(scope)
            syncGeneration(scope)
        }
        failures = [:]
        if navidrome?.status.ok != true { Task { await checkNavidrome() } }
        if server.access.hasLibrary { Task { await askMine() } }
    }

    /// An Add to or Remove from your library answered: your albums asked again at the next look, and your library
    /// with them (useYourAlbums.ts forgetYourAlbums, useMyLibrary's onAdded/onRemoved). Never for a filing.
    func libraryChanged() {
        index.forget(.yours)
        syncGeneration(.yours)
        Task { await askMine() }
    }

    /// POST /me/library/seen; a failure is let go (the mark is gone here; deadwax keeps it until the next open).
    private func tellSeen(_ body: SeenBody) {
        guard let client = server.client, let json = try? JSONEncoder().encode(body) else { return }
        Task { _ = try? await client.answer(client.request(Routes.librarySeen, json: json)) }
    }

    // MARK: a new person

    /// The person changed: nothing of theirs kept in memory, and nothing asked before lands after. (Their lists on
    /// disk stay, keyed by who they are - drawn again only for them.)
    func reset() {
        epoch += 1
        for task in asking.values { task.cancel() }
        asking = [:]
        restoring = [:]
        index.clear()
        failures = [:]
        shelves = [:]
        generations = [:]
        serials = [:]
        sortedCache = [:]
        drawnCache = [:]
        lastFetch = [:]
        mine.clear()
        starredCount = StarredCountWatch()
        mineAsks += 1
        navidrome = nil
        checkingNavidrome = false
        navidromeAsks += 1
    }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
