import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/search/search-albums-vectors.json: what the web's TypeScript (lib/searchList.ts's albums, Top results and
/// moments, lib/searchQuery.ts's typing rules, lib/searchResults.ts, lib/idBridge.ts, lib/artistPage.ts's
/// libraryArtistFor, lib/pressings.ts and lib/tracklistDiff.ts) answers for slice 2, written by
/// ios/scripts/export-search-albums-vectors.cjs - never by hand. MusicBrainz's groups, the pressings, the folders and the
/// library's answers in it are decoded by the real models (ReleaseGroup, PageRelease, OwnedAlbum, LibraryResults).
enum SearchAlbumsVectors {
    typealias Plan = SearchVectors.Plan
    typealias Placed = SearchVectors.Placed
    typealias Candidate = SearchVectors.Candidate
    typealias Count = SearchVectors.Count
    typealias ByKind = SearchVectors.ByKind

    struct Vectors: Decodable {
        let numbers: Numbers
        let words: Words
        let typing: Typing
        let groups: [GroupCase]
        let holding: [HoldingCase]
        let studio: [StudioCase]
        let moments: Moments
        let cases: [Case]
        let pressings: [PressingsCase]
        let page: Page
    }

    struct Numbers: Decodable {
        let musicBrainzLimit, ownedWaitMs, resultsWaitMs, libraryLateMs, pressingFilterMin, pressingsKept: Int
        let previewMusicBrainz: ByKind<Int>
    }

    struct Counts: Decodable {
        let artists, albums, songs: Int?
        var byKind: [SearchKind: Int] {
            var out: [SearchKind: Int] = [:]
            if let artists { out[.artists] = artists }
            if let albums { out[.albums] = albums }
            if let songs { out[.songs] = songs }
            return out
        }
    }

    struct Failure: Decodable {
        let message: String
        let refused, busy, unavailable: Bool
        var failure: MBFailure { MBFailure(message: message, unavailable: unavailable, busy: busy, refused: refused) }
    }

    struct Words: Decodable {
        struct MusicBrainz: Decodable { let counts: Counts; let answered: Bool; let said: String }
        struct Failed: Decodable { let failure: Failure; let short: Bool; let said: String }
        struct Fold: Decodable { let kind: String; let count: Int; let button, said: String }
        struct Empty: Decodable { let kind, text, said: String }
        struct Late: Decodable { let counts: Counts; let personal: Bool; let text: String; let button: String?; let line: String }
        struct Skipped: Decodable { let personal: Bool; let said: String }
        let hint, hintPersonal, searching, searchingPersonal, searchingLibrary, searchingLibraryPersonal: String
        let allHeld, allHeldPersonal, typeMore, studioNote, libraryAbove, libraryAbovePersonal: String
        let musicBrainz: [MusicBrainz]
        let failure: [Failed]
        let fold: [Fold]
        let empty: [Empty]
        let libraryLate: [Late]
        let librarySkipped: [Skipped]
    }

    struct Typing: Decodable {
        struct Filter: Decodable {
            struct Given: Decodable { let primary: [String]?; let studioOnly: Bool? }
            let given: Given
            let filter: String
        }
        struct Settling: Decodable { let text: String; let settles: Bool }
        struct OnTyping: Decodable { let text: String; let asked: String?; let then: String }
        struct AllAlbums: Decodable {
            struct Query: Decodable { let query: String; let studio: Bool }
            let names: [String]
            let text: String
            let plan: Plan
            let all: Query
        }
        let typeFilter: [Filter]
        let settling: [Settling]
        let onTyping: [OnTyping]
        let allAlbums: [AllAlbums]
    }

    struct Sole: Decodable { let mbid, name: String }

    struct GroupCase: Decodable {
        let group: ReleaseGroup
        let year: String?
        let kind, word, credit, current: String
        let sole: Sole?
    }

    struct HoldingCase: Decodable {
        struct OfGroup: Decodable {
            let id: String
            let held: Bool
            let place, placePersonal, maybe, maybePersonal: String
            let releases: [String]
        }
        struct Artists: Decodable {
            struct Found: Decodable { let mbid, name: String?; let artist: String? }
            let list: [Artist]
            let found: [Found]
        }
        let folders: [OwnedAlbum]?
        let groups: [OfGroup]
        let notInLibrary, heldUnlisted, heldUnlistedListed, inOrder: [String]
        let artists: [Artists]
    }

    struct StudioCase: Decodable {
        let ids, ordered: [String]
        let groups: [ReleaseGroup]
    }

    struct Moments: Decodable {
        struct Ready: Decodable { let librarySettled, musicBrainz, asked: Bool; let out: [String]; let capPassed, ready: Bool }
        struct Late: Decodable { let wanted, inHand, late: [String] }
        struct Landing: Decodable { let kind: String; let drawn: [String]; let footTappable: Bool; let landing: String }
        struct Behind: Decodable { let was: Bool; let outcome: String; let behind: Bool }
        let ready: [Ready]
        let late: [Late]
        let landing: [Landing]
        let behind: [Behind]
    }

    /// `[key, line, place]`.
    struct Line: Decodable {
        let key, line, place: String

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            line = try row.decode(String.self)
            place = try row.decode(String.self)
        }
    }

    /// `[key, section line, section place, Top line, Top place]`.
    struct Lines: Decodable {
        let key, line, place, topLine, topPlace: String

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            line = try row.decode(String.self)
            place = try row.decode(String.self)
            topLine = try row.decode(String.self)
            topPlace = try row.decode(String.self)
        }
    }

    struct Case: Decodable {
        struct Pool: Decodable { let library, brought, musicbrainz: [Placed] }
        struct Decided: Decodable { let kinds: [String]; let prefix: [String]; let place: Bool }
        struct Late: Decodable { let drawn: [String]; let counts: [Int]; let rows, uncapped: [String] }
        struct Family: Decodable { let id: String; let family: [Line] }
        struct Phantoms: Decodable { let artists, albums, songs: Int? }
        let text: String
        let library: LibraryResults?
        let failed: Bool
        let artistList: [Artist]?
        /// The folder lists by their place in `holding` (0: none answered).
        let folders, landed: Int
        /// The groups by id, from `groups`.
        let groups: [String]?
        let personal: Bool
        let yourAlbums: [String]?
        let yourArtists: [Count]?
        let plan: Plan?
        let shown: [String]?
        let pool: ByKind<Pool>?
        let candidates: [Candidate]?
        let phantoms: Phantoms?
        let decided: [Decided]?
        let top: [Line]?
        let topFixed: [String]?
        let sections, full: ByKind<[String]>?
        let late: Late?
        let lines: [Lines]?
        let families: [Family]?
    }

    struct PressingsCase: Decodable {
        struct Each: Decodable { let id, format, year, label, facts: String }
        struct Base: Decodable { let index, count, total: Int; let key, sharedBy: String }
        struct Chosen: Decodable { let asked: String?; let id: String? }
        struct Added: Decodable { let position: Int; let title: String; let length: Int?; let after: String? }
        struct Removed: Decodable { let position: Int; let title: String; let length: Int? }
        struct Renamed: Decodable { let position: Int; let from, to: String }
        struct Timed: Decodable { let position: Int; let title: String; let from, to, delta: Int }
        struct Diff: Decodable {
            let added: [Added]
            let removed: [Removed]
            let renamed: [Renamed]
            let versions, lengths: [Timed]
            let same: Int
        }
        struct Row: Decodable { let id, label, facts, note, kind: String; let isDefault, held, inStore: Bool }
        struct Summary: Decodable { let text: String; let differs: Bool }
        struct View: Decodable {
            let asked: String?
            let held: [String]
            let yours: [String]?
            let defaultId, chosenId: String?
            let shown, more: [Row]
            let summary: Summary
        }
        /// `[key, heading, number, title, length, [kind, chip, note] | null]`.
        struct Track: Decodable {
            let key: String
            let heading: String?
            let number, title, length: String
            let mark: [String]?

            init(from decoder: any Decoder) throws {
                var row = try decoder.unkeyedContainer()
                key = try row.decode(String.self)
                heading = try row.decodeNil() ? nil : row.decode(String.self)
                number = try row.decode(String.self)
                title = try row.decode(String.self)
                length = try row.decode(String.self)
                mark = try row.decodeNil() ? nil : row.decode([String].self)
            }
        }
        struct Missing: Decodable { let title, length: String }
        struct Header: Decodable { let title, artist, year, kind: String }
        struct PageCase: Decodable {
            let id: String
            let tracks: [Track]
            let missing: [Missing]
            let summary: Summary
            let header, headerPreview: Header
        }
        struct Filter: Decodable { let typed: String; let ids: [String]; let said: String }
        let name: String
        let preview: ReleaseGroup
        let releases: [PageRelease]
        let each: [Each]
        let base: Base?
        let representative: String?
        let chosen: [Chosen]
        let diffs: [String: Diff?]
        let views: [View]
        let pages: [PageCase]
        let filter: [Filter]
    }

    struct Page: Decodable {
        struct Header: Decodable { let year, kind: String }
        struct Meta: Decodable { let header: Header; let held: Bool?; let place: String?; let said: String }
        struct Disc: Decodable { let position: Int; let title: String?; let said: String }
        struct Holding: Decodable {
            struct Given: Decodable { let held, guessed: Int }
            let given: Given?
            let holding: String?
        }
        struct Covers: Decodable { let release: String?; let group: String; let addresses: [String] }
        let meta: [Meta]
        let discHeading: [Disc]
        let holding: [Holding]
        let covers: [Covers]
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("search/search-albums-vectors.json"))
    }

    static func kind(_ raw: String) throws -> SearchKind { try #require(SearchKind(rawValue: raw), "\(raw)") }
    static func kinds(_ raws: [String]) throws -> [SearchKind] { try raws.map(kind) }

    static func index(_ folders: [OwnedAlbum]?) -> OwnedIndex? { folders.map { OwnedIndex($0) } }

    static func same(_ a: String?, _ b: String?) -> Bool { SearchVectors.same(a, b) }
}

/// The phone's slice 2 against the web's own answers (export-search-albums-vectors.cjs).
@Suite struct SearchAlbumsVectorTests {
    private typealias V = SearchAlbumsVectors

    @Test func theNumbersAreTheWebs() throws {
        let numbers = try V.load().numbers
        #expect(SearchAlbums.limit == numbers.musicBrainzLimit)
        #expect(SearchPacing.ownedWaitMs == numbers.ownedWaitMs)
        #expect(SearchPacing.resultsWaitMs == numbers.resultsWaitMs)
        #expect(SearchPacing.libraryLateMs == numbers.libraryLateMs)
        #expect(Pressings.filterMin == numbers.pressingFilterMin)
        #expect(Pressings.kept == numbers.pressingsKept)
        for (kind, cap) in SearchVectors.kinds(numbers.previewMusicBrainz) {
            #expect(SearchPacing.previewMusicBrainz(kind) == cap, "\(kind)")
            #expect(SearchPacing.cap(kind) == (SearchPacing.preview(kind), cap), "\(kind)")
        }
    }

    @Test func theWordsAreTheWebs() throws {
        let words = try V.load().words
        #expect(SearchWords.hint(personal: false) == words.hint && SearchWords.hint(personal: true) == words.hintPersonal)
        #expect(SearchWords.searching(personal: false, musicBrainz: true) == words.searching)
        #expect(SearchWords.searching(personal: true, musicBrainz: true) == words.searchingPersonal)
        #expect(SearchWords.searching(personal: false) == words.searchingLibrary)
        #expect(SearchWords.searching(personal: true) == words.searchingLibraryPersonal)
        #expect(SearchWords.allHeld(personal: false) == words.allHeld)
        #expect(SearchWords.allHeld(personal: true) == words.allHeldPersonal)
        #expect(SearchWords.typeMore == words.typeMore && SearchWords.studioNote == words.studioNote)
        #expect(SearchWords.libraryAbove(personal: false) == words.libraryAbove)
        #expect(SearchWords.libraryAbove(personal: true) == words.libraryAbovePersonal)
        for each in words.musicBrainz {
            #expect(SearchWords.musicBrainz(each.counts.byKind, answered: each.answered) == each.said, "\(each.counts)")
        }
        for each in words.failure {
            #expect(SearchWords.failure(each.failure.failure, short: each.short) == each.said, "\(each.failure.message)")
        }
        for each in words.fold {
            let made = SearchWords.fold(try V.kind(each.kind), each.count)
            #expect(made.button == each.button && made.said == each.said, "\(each.kind) \(each.count)")
        }
        for each in words.empty {
            #expect(V.same(SearchWords.empty(try V.kind(each.kind), each.text), each.said), "\(each.kind) \(each.text)")
        }
        for each in words.libraryLate {
            let made = SearchWords.libraryLate(each.counts.byKind, personal: each.personal, text: each.text)
            #expect(made.button == each.button && V.same(made.line, each.line), "\(each.counts) \(each.personal)")
        }
        for each in words.librarySkipped {
            #expect(SearchWords.librarySkipped(personal: each.personal) == each.said)
        }
    }

    @Test func typingAndTheQueriesAreTheWebs() throws {
        let typing = try V.load().typing
        for each in typing.typeFilter {
            #expect(SearchReading.typeFilter(primary: each.given.primary ?? [], studioOnly: each.given.studioOnly ?? false)
                    == each.filter, "\(each.given)")
        }
        for each in typing.settling {
            #expect(SearchReading.asksMusicBrainzBySettling(each.text) == each.settles, "\"\(each.text)\"")
        }
        for each in typing.onTyping {
            #expect(SearchReading.musicBrainzOnTyping(each.text, asked: each.asked).rawValue == each.then,
                    "\"\(each.text)\" after \(each.asked ?? "nil")")
        }
        #expect(typing.allAlbums.count > 20)
        for each in typing.allAlbums {
            let plan = try #require(SearchReading.read(each.text, names: SearchReading.artistNames(each.names)), "\(each.text)")
            #expect(V.same(plan.query, each.plan.query) && plan.kind.rawValue == each.plan.kind, "\(each.text): the reading")
            let all = SearchAlbums.allAlbumsQuery(plan)
            #expect(V.same(all.query, each.all.query) && all.studio == each.all.studio, "\(each.text) \(each.names): All's albums")
        }
    }

    @Test func aGroupsYearKindAndCreditAreTheWebs() throws {
        let groups = try V.load().groups
        #expect(groups.count >= 20)
        for each in groups {
            let what = each.group.title ?? each.group.id
            #expect(SearchAlbums.year(each.group) == each.year, "\(what): year")
            #expect(SearchAlbums.kind(each.group) == each.kind, "\(what): kind")
            #expect(SearchAlbums.word(each.group) == each.word, "\(what): word")
            #expect(V.same(Credits.name(each.group.artistCredit), each.credit), "\(what): credit")
            #expect(V.same(Credits.current(each.group.artistCredit), each.current), "\(what): current")
            let sole = Credits.sole(each.group.artistCredit)
            #expect(sole?.mbid == each.sole?.mbid && V.same(sole?.name, each.sole?.name), "\(what): sole")
        }
    }

    @Test func whatIsHeldIsTheWebs() throws {
        let vectors = try V.load()
        let groups = vectors.groups.map(\.group)
        for (number, each) in vectors.holding.enumerated() {
            let index = V.index(each.folders)
            for (group, wanted) in zip(groups, each.groups) {
                let what = "folders \(number), \(group.title ?? "")"
                #expect(group.id == wanted.id)
                #expect(SearchAlbums.held(index, group.id) == wanted.held, "\(what): held")
                #expect(SearchAlbums.place(index, group.id, personal: false) == wanted.place, "\(what): place")
                #expect(SearchAlbums.place(index, group.id, personal: true) == wanted.placePersonal, "\(what): place, personal")
                #expect(SearchAlbums.maybe(group, SearchMarks(personal: false, index: index)) == wanted.maybe, "\(what): maybe")
                #expect(SearchAlbums.maybe(group, SearchMarks(personal: true, index: index)) == wanted.maybePersonal,
                        "\(what): maybe, personal")
                #expect(SearchAlbums.heldReleases(index, group.id) == wanted.releases, "\(what): the releases held")
            }
            #expect(SearchAlbums.notInLibrary(groups, index).map(\.id) == each.notInLibrary, "folders \(number): not held")
            #expect(SearchAlbums.heldUnlisted(groups, index, []).map(\.id) == each.heldUnlisted, "folders \(number)")
            let listed = [Album(id: "", musicBrainzId: "76df3287-6cda-33eb-8e9a-044b5e15ffdd"),
                          Album(id: "", musicBrainzId: " 930345B1-A970-3495-A1DD-55147BEA7741 "), Album(id: "")]
            #expect(SearchAlbums.heldUnlisted(groups, index, listed).map(\.id) == each.heldUnlistedListed,
                    "folders \(number): listed by search3")
            #expect(SearchAlbums.heldInOrder(each.folders ?? []).map(\.path) == each.inOrder, "folders \(number): in order")
            for artists in each.artists {
                for found in artists.found {
                    #expect(SearchAlbums.libraryArtist(artists.list, mbid: found.mbid, index: index, name: found.name)?.id
                            == found.artist, "folders \(number), \(artists.list.map(\.id)): \(found.mbid ?? "nil") \(found.name ?? "nil")")
                }
            }
        }
    }

    @Test func theStudioClausesOrderIsTheWebs() throws {
        for each in try V.load().studio {
            #expect(each.groups.map(\.id) == each.ids)
            #expect(SearchAlbums.studioOrder(each.groups).map(\.id) == each.ordered, "\(each.ids)")
        }
    }

    @Test func theMomentsAreTheWebs() throws {
        let moments = try V.load().moments
        for each in moments.ready {
            #expect(SearchList.sectionsReady(librarySettled: each.librarySettled, musicBrainz: each.musicBrainz,
                                             asked: each.asked, out: try V.kinds(each.out), capPassed: each.capPassed)
                    == each.ready, "\(each)")
        }
        for each in moments.late {
            let inHand = Set(try V.kinds(each.inHand))
            #expect(SearchList.lateKinds(try V.kinds(each.wanted)) { inHand.contains($0) } == (try V.kinds(each.late)), "\(each)")
        }
        for each in moments.landing {
            #expect(SearchList.drawInOrFold(try V.kind(each.kind), try V.kinds(each.drawn), footTappable: each.footTappable)
                .rawValue == each.landing, "\(each)")
        }
        for each in moments.behind {
            let outcome = try #require(SearchList.Outcome(rawValue: each.outcome))
            #expect(SearchList.nextBehind(each.was, outcome) == each.behind, "\(each)")
        }
    }

    /// Every worked and seeded search with MusicBrainz's albums in hand, made as the web makes it: the block shown, the
    /// pool, the candidates, the phantoms, Top results decided and completed, the sections, a late answer's landing,
    /// every line and every album's relatives.
    @Test func everySearchWithAlbumsIsTheWebs() throws {
        let vectors = try V.load()
        let byId = Dictionary(vectors.groups.map { ($0.group.id, $0.group) }, uniquingKeysWith: { (first: ReleaseGroup, _: ReleaseGroup) in first })
        #expect(vectors.cases.count >= 90)
        for (number, each) in vectors.cases.enumerated() {
            let what = "case \(number), \"\(each.text)\""
            let folders = vectors.holding[each.folders].folders
            let index = V.index(folders)
            let landed = V.index(vectors.holding[each.landed].folders)
            let ownedArtists = OwnedAnswer(albums: folders ?? []).artists
            let results = each.failed ? nil : each.library
            var known: [String: Album] = [:]
            for album in results?.albums ?? [] { known[album.id] = album }
            let marks = SearchMarks(
                personal: each.personal, index: index,
                yourAlbums: each.personal ? each.yourAlbums.map { Set($0) } : nil,
                yourArtists: each.personal ? each.yourArtists.map { (pairs: [V.Count]) -> [String: Int] in
                    Dictionary(pairs.map { ($0.id, $0.count) }, uniquingKeysWith: { (_: Int, later: Int) -> Int in later })
                } : nil,
                known: known)
            let term = JSText.trim(each.text)
            let plan = SearchReading.read(term, names: SearchReading.artistNames(SearchList.knownNames(ownedArtists, results)))
            guard let wanted = each.plan else {
                #expect(plan == nil, "\(what): nothing to read")
                continue
            }
            let reading = try #require(plan, "\(what)")
            #expect(V.same(reading.query, wanted.query) && reading.kind.rawValue == wanted.kind, "\(what): the reading")
            let groups = try (each.groups ?? []).map { try #require(byId[$0], "\(what): group \($0)") }
            let shown = each.groups == nil ? nil : SearchAlbums.notInLibrary(groups, landed)
            #expect(shown?.map(\.id) == each.shown, "\(what): MusicBrainz's block, as it landed")
            let found = shown.map { SearchAlbumsInHand(groups: groups, shown: $0) }
            let bare = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks)
            let pool = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks,
                                       albums: found)
            func placed(_ list: [SearchPlaced]) -> [V.Placed] {
                list.map { V.Placed(key: $0.row.key, holder: $0.holder.rawValue, position: $0.position) }
            }
            for (kind, blocks) in SearchVectors.kinds(try #require(each.pool)) {
                #expect(placed(pool[kind].library) == blocks.library, "\(what): the pool's \(kind), the library's")
                #expect(placed(pool[kind].brought) == blocks.brought, "\(what): the pool's \(kind), brought in")
                #expect(placed(pool[kind].musicbrainz) == blocks.musicbrainz, "\(what): the pool's \(kind), MusicBrainz's")
            }
            let candidates = SearchList.candidates(pool, box: term, reading: reading)
            #expect(candidates.map { V.Candidate(key: $0.key, tier: $0.tier, source: $0.source, position: $0.position) }
                    == each.candidates, "\(what): the candidates")
            let phantoms = try #require(each.phantoms)
            #expect(SearchList.phantom(.artists, reading)?.tier == phantoms.artists
                    && SearchList.phantom(.albums, reading)?.tier == phantoms.albums
                    && SearchList.phantom(.songs, reading)?.tier == phantoms.songs, "\(what): the phantoms")

            let n = SearchPacing.topResults
            let bareCandidates = SearchList.candidates(bare, box: term, reading: reading)
            for decided in try #require(each.decided) {
                let made = SearchList.decidedTop(bareCandidates, phantoms: try V.kinds(decided.kinds).compactMap { SearchList.phantom($0, reading) },
                                                 n: n, library: results, artistList: each.artistList, index: index)
                #expect(made.prefix.map(\.key) == decided.prefix && made.place == decided.place,
                        "\(what): decided with \(decided.kinds) out")
            }
            let top = SearchList.topResults(candidates, n: n, library: results, artistList: each.artistList, index: index)
            let wantedTop = try #require(each.top)
            #expect(top.map(\.key) == wantedTop.map(\.key), "\(what): Top results")
            for (row, line) in zip(top, wantedTop) {
                let made = SearchList.line(row, marks, top: true)
                #expect(V.same(made.line, line.line) && V.same(made.place, line.place), "\(what): \(row.key)'s Top line")
            }
            let prefix = SearchList.decidedTop(bareCandidates, phantoms: [SearchList.phantom(.albums, reading)].compactMap { $0 },
                                               n: n, library: results, artistList: each.artistList, index: index).prefix
            #expect(SearchList.topResults(candidates, n: n, library: results, artistList: each.artistList, index: index,
                                          fixed: prefix).map(\.key) == each.topFixed, "\(what): Top results completed")

            for (kind, keys) in SearchVectors.kinds(try #require(each.sections)) {
                #expect(SearchList.sectionRows(pool[kind], cap: SearchPacing.cap(kind)).map(\.key) == keys,
                        "\(what): the \(kind) section")
            }
            for (kind, keys) in SearchVectors.kinds(try #require(each.full)) {
                #expect(SearchList.sectionRows(pool[kind]).map(\.key) == keys, "\(what): all the \(kind)")
            }
            let late = try #require(each.late)
            let cap = SearchPacing.cap(.albums)
            let drawn = SearchList.sectionRows(bare.albums, cap: cap)
            #expect(drawn.map(\.key) == late.drawn, "\(what): the albums drawn before theirs landed")
            let counts = SearchList.drawnCounts(pool.albums, drawn)
            #expect([counts.0, counts.1] == late.counts, "\(what): the drawn counts")
            #expect(SearchList.lateRows(pool.albums, cap: (max(0, cap.0 - counts.0), max(0, cap.1 - counts.1)),
                                        drawn: Set(drawn.map(\.key))).map(\.key) == late.rows, "\(what): the late albums")
            #expect(SearchList.lateRows(pool.albums).map(\.key) == late.uncapped, "\(what): the late albums, all")

            let rows = SearchKind.allCases.flatMap { (kind: SearchKind) -> [SearchPlaced] in
                pool[kind].library + pool[kind].brought + pool[kind].musicbrainz
            }
            let lines = try #require(each.lines)
            #expect(rows.map(\.row.key) == lines.map(\.key), "\(what): every row")
            for (row, line) in zip(rows.map(\.row), lines) {
                let section = SearchList.line(row, marks)
                let topLine = SearchList.line(row, marks, top: true)
                #expect(V.same(section.line, line.line) && V.same(section.place, line.place), "\(what): \(row.key)'s line")
                #expect(V.same(topLine.line, line.topLine) && V.same(topLine.place, line.topPlace), "\(what): \(row.key)'s Top line")
            }
            for family in try #require(each.families) {
                let group = try #require(byId[family.id])
                let made = SearchList.family(of: .group(group), library: results, artistList: each.artistList, index: index)
                #expect(made.map(\.key) == family.family.map(\.key), "\(what): \(group.title ?? "")'s relatives")
                for (row, line) in zip(made, family.family) {
                    let said = SearchList.line(row, marks, top: true)
                    #expect(V.same(said.line, line.line) && V.same(said.place, line.place), "\(what): relative \(row.key)")
                }
            }
        }
    }

    // MARK: the album you don't have

    @Test func eachPressingIsSaidAsTheWebs() throws {
        for group in try V.load().pressings {
            #expect(group.releases.map(\.id) == group.each.map(\.id), "\(group.name): decoded")
            for (release, each) in zip(group.releases, group.each) {
                let what = "\(group.name), \(release.id)"
                #expect(V.same(Pressings.format(release), each.format), "\(what): format")
                #expect(Pressings.year(release) == each.year, "\(what): year")
                #expect(V.same(Pressings.label(release), each.label), "\(what): label")
                #expect(V.same(Pressings.facts(release), each.facts), "\(what): facts")
            }
        }
    }

    @Test func theUsualTracklistAndTheDefaultAreTheWebs() throws {
        for group in try V.load().pressings {
            let base = Tracklist.chooseBase(group.releases)
            #expect(base?.index == group.base?.index && base?.count == group.base?.count && base?.total == group.base?.total,
                    "\(group.name): the base")
            #expect(V.same(base.map { Tracklist.key($0.tracks) }, group.base?.key), "\(group.name): the base's tracklist")
            #expect(base.map { Pressings.sharedBy($0) } == group.base?.sharedBy, "\(group.name): shared by")
            #expect(Tracklist.representative(group.releases)?.id == group.representative, "\(group.name): the default")
            for chosen in group.chosen {
                #expect(Pressings.chosenId(group.releases, asked: chosen.asked, defaultId: Pressings.defaultId(group.releases))
                        == chosen.id, "\(group.name): asked \(chosen.asked ?? "nil")")
            }
            let view = Pressings.view(group.releases)
            #expect(Set(view.diffs.keys) == Set(group.diffs.keys), "\(group.name): every pressing compared")
            for (id, wanted) in group.diffs {
                let made = view.diffs[id] ?? nil
                let what = "\(group.name), \(id)"
                guard let wanted else {
                    #expect(made == nil, "\(what): no diff")
                    continue
                }
                let diff = try #require(made, "\(what)")
                // each row made [String] by a typed function and compared outside #expect: CI's Xcode 26.6 gives up
                // type-checking these closures written inline in the macro
                let madeAdded: [[String]] = diff.added.map { (a: TracklistDiff.Added) -> [String] in
                    diffCells(a.position, a.title, a.length) + [a.after ?? "-"]
                }
                let wantedAdded: [[String]] = wanted.added.map { (a: V.PressingsCase.Added) -> [String] in
                    diffCells(a.position, a.title, a.length) + [a.after ?? "-"]
                }
                #expect(madeAdded == wantedAdded, "\(what): added")
                let madeRemoved: [[String]] = diff.removed.map { (r: TracklistDiff.Removed) -> [String] in
                    diffCells(r.position, r.title, r.length)
                }
                let wantedRemoved: [[String]] = wanted.removed.map { (r: V.PressingsCase.Removed) -> [String] in
                    diffCells(r.position, r.title, r.length)
                }
                #expect(madeRemoved == wantedRemoved, "\(what): removed")
                let madeRenamed: [[String]] = diff.renamed.map { (r: TracklistDiff.Renamed) -> [String] in
                    [String(r.position), r.from, r.to]
                }
                let wantedRenamed: [[String]] = wanted.renamed.map { (r: V.PressingsCase.Renamed) -> [String] in
                    [String(r.position), r.from, r.to]
                }
                #expect(madeRenamed == wantedRenamed, "\(what): renamed")
                #expect(diff.versions.map { [$0.position, $0.from, $0.to, $0.delta] } == wanted.versions.map { [$0.position, $0.from, $0.to, $0.delta] },
                        "\(what): other versions")
                #expect(diff.versions.map(\.title) == wanted.versions.map(\.title), "\(what): other versions' titles")
                #expect(diff.lengths.map { [$0.position, $0.from, $0.to, $0.delta] } == wanted.lengths.map { [$0.position, $0.from, $0.to, $0.delta] },
                        "\(what): lengths")
                #expect(diff.same == wanted.same, "\(what): the same")
            }
        }
    }

    @Test func thePickerIsTheWebs() throws {
        for group in try V.load().pressings {
            for (number, wanted) in group.views.enumerated() {
                let what = "\(group.name), view \(number)"
                let view = Pressings.view(group.releases, asked: wanted.asked, held: Set(wanted.held),
                                          yours: wanted.yours.map { Set($0) })
                #expect(view.defaultId == wanted.defaultId && view.chosenId == wanted.chosenId, "\(what): chosen")
                func rows(_ made: [PressingChoice], _ rows: [V.PressingsCase.Row], _ part: String) {
                    #expect(made.map(\.id) == rows.map(\.id), "\(what): \(part)")
                    for (row, want) in zip(made, rows) {
                        #expect(V.same(row.label, want.label) && V.same(row.facts, want.facts) && V.same(row.note, want.note),
                                "\(what): \(row.id)'s words")
                        #expect(row.kind.rawValue == want.kind && row.isDefault == want.isDefault && row.held == want.held
                                && row.inStore == want.inStore, "\(what): \(row.id)'s marks")
                    }
                }
                rows(view.shown, wanted.shown, "shown")
                rows(view.more, wanted.more, "more")
                let summary = Pressings.summary(view, releaseCount: group.releases.count)
                #expect(summary.text == wanted.summary.text && summary.differs == wanted.summary.differs, "\(what): the summary")
            }
            let all = Pressings.view(group.releases, held: Set(group.views[5].held))
            for each in group.filter {
                let found = Pressings.filter(all.shown + all.more, each.typed)
                #expect(found.map(\.id) == each.ids, "\(group.name): filtered by \"\(each.typed)\"")
                #expect(V.same(Pressings.filterWords(found.count, each.typed), each.said), "\(group.name): \"\(each.typed)\" said")
            }
        }
    }

    @Test func eachPressingsPageIsTheWebs() throws {
        for group in try V.load().pressings {
            let view = Pressings.view(group.releases)
            for (release, page) in zip(group.releases, group.pages) {
                let what = "\(group.name), \(release.id)"
                #expect(release.id == page.id)
                let diff = view.diffs[release.id] ?? nil
                let tracks = Pressings.trackRows(release, diff)
                #expect(tracks.map(\.key) == page.tracks.map(\.key), "\(what): the tracklist")
                for (track, want) in zip(tracks, page.tracks) {
                    #expect(track.heading == want.heading && track.number == want.number && V.same(track.title, want.title)
                            && track.length == want.length, "\(what): track \(track.key)")
                    #expect(track.mark.map { [$0.kind.rawValue, $0.chip, $0.note] } == want.mark, "\(what): track \(track.key)'s mark")
                }
                let missing = Pressings.leftOut(diff)
                #expect(missing.map(\.title) == page.missing.map(\.title) && missing.map(\.length) == page.missing.map(\.length),
                        "\(what): left out")
                let summary = Pressings.summary(Pressings.view(group.releases, asked: release.id), releaseCount: group.releases.count)
                #expect(summary.text == page.summary.text && summary.differs == page.summary.differs, "\(what): the summary")
                for (preview, header) in [(nil, page.header), (group.preview, page.headerPreview)] as [(ReleaseGroup?, V.PressingsCase.Header)] {
                    let made = Pressings.header(group.releases, chosen: release, preview: preview)
                    #expect(V.same(made.title, header.title) && V.same(made.artist, header.artist) && made.year == header.year
                            && made.kind == header.kind, "\(what): the header \(preview == nil ? "" : "from Search")")
                }
            }
        }
    }

    @Test func thePagesWordsAreTheWebs() throws {
        let page = try V.load().page
        for each in page.meta {
            let made = each.place.map { Pressings.metaLine(year: each.header.year, kind: each.header.kind, held: each.held, place: $0) }
                ?? Pressings.metaLine(year: each.header.year, kind: each.header.kind, held: each.held)
            #expect(made == each.said, "\(each.header) \(String(describing: each.held)) \(each.place ?? "")")
        }
        for each in page.discHeading {
            #expect(Pressings.discHeading(each.position, each.title) == each.said, "\(each.position) \(each.title ?? "nil")")
        }
        for each in page.holding {
            let album = OwnedAlbum(path: "x")
            let given = each.given.map { (given: V.Page.Holding.Given) -> (held: [OwnedAlbum], guessed: [OwnedAlbum]) in
                (Array(repeating: album, count: given.held), Array(repeating: album, count: given.guessed))
            }
            #expect(Pressings.holding(given)?.rawValue == each.holding, "\(String(describing: each.given))")
        }
        for each in page.covers {
            let made = ArchiveCoverID.addresses(release: each.release, group: each.group).map { (cover: ArchiveCoverID) -> String in
                "https://coverartarchive.org/\(cover.kind.rawValue)/\(cover.mbid)/front-250"
            }
            #expect(made == each.addresses, "\(each.release ?? "nil") \(each.group)")
        }
    }
}

/// A tracklist diff's row as words - its position, title and length ("-" for none) - for comparing the made and the
/// wanted (the pressings case above).
private func diffCells(_ position: Int, _ title: String, _ length: Int?) -> [String] {
    let shown: String = length.map { (seconds: Int) -> String in String(seconds) } ?? "-"
    return [String(position), title, shown]
}
