import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/search/search-saved-vectors.json: what the web's TypeScript (lib/searchList.ts's savedFor, kindArea, the
/// pool with what's saved, lateRows, drawnCounts, Top results' saved marks and the saved words; lib/searchResults.ts's
/// appendPage, morePages and morePageWords; lib/songs.ts's appendSongs and moreSongsWords; app/searchAnswers.ts's kept
/// answers) answers for slice 4, written by ios/scripts/export-search-saved-vectors.cjs - never by hand. The groups,
/// folders, recordings, artists and the library's answers in it are decoded by the real models.
///
/// Every comparison is made of values built outside `#expect`, in typed `let`s: CI's older Swift gives up type-checking
/// a closure or a `??` written inside the macro (b451241).
enum SearchSavedVectors {
    typealias Plan = SearchVectors.Plan
    typealias Count = SearchVectors.Count
    typealias ByKind = SearchVectors.ByKind
    typealias Counts = SearchVectors.Words.Counted.Counts

    struct Vectors: Decodable {
        let numbers: Numbers
        let words: Words
        let groups: [ReleaseGroup]
        let lists: [[OwnedAlbum]?]
        let recordings: [String: [MBRecording]]
        let studio: [Studio]
        let saved: [SavedCase]
        let areas: [AreaRun]
        let pages: [PagesCase]
        let append: [AppendCase]
        let songPages: SongPages
        let kept: [KeptRun]
        let cases: [Case]
    }

    struct Numbers: Decodable {
        struct Sources: Decodable { let yours, store, saved, musicbrainz: Double }
        let savedWaitMs, savedArtistAlbums, answersKept, offsetMax: Int
        let sources: Sources
    }

    struct Failure: Decodable {
        let refused, busy, unavailable: Bool
        let message: String
        var failure: MBFailure { MBFailure(message: message, unavailable: unavailable, busy: busy, refused: refused) }
    }

    struct Words: Decodable {
        struct Saved: Decodable { let counts: Counts; let said: String }
        struct MusicBrainz: Decodable { let counts: Counts; let answered, saved: Bool; let said: String }
        struct SavedAway: Decodable { let failure: Failure; let short: Bool; let said, plain: String }
        struct NothingMore: Decodable { let kind, text, said: String }
        struct MorePage: Decodable { let added, held: Int; let personal: Bool; let note: String?; let said: String }
        struct MoreSongs: Decodable { let added, grown: Int; let note: String?; let said: String }
        struct Buttons: Decodable { let albums, artists, songs, loading, tryAgain: String }
        let saved: [Saved]
        let musicBrainz: [MusicBrainz]
        let savedAway: [SavedAway]
        let nothingMore: [NothingMore]
        let morePage: [MorePage]
        let moreSongs: [MoreSongs]
        let buttons: Buttons
        let far: String
    }

    struct Studio: Decodable { let group: String; let studio: Bool }

    struct Songs: Decodable { let name: String; let take: Int }

    /// What's saved as a case gives it: artists in full, groups by id, songs as the first `take` of a recorded search.
    struct Found: Decodable {
        let matches: [MBArtistMatch]
        let groups: [String]
        let credited: [String]?
        let songs: Songs?
    }

    struct Answer: Decodable, Equatable {
        let matches, groups, shown, songs: [String]
    }

    struct SavedCase: Decodable {
        let text: String
        let names: [String]
        let found: Found?
        let view: String
        let list: Int
        let plan: Plan?
        let given: Bool
        let kinds: [String]?
        let studio: Bool?
        let answer: Answer?
    }

    /// `[key, is it the saved row]`.
    struct Flagged: Decodable, Equatable {
        let key: String
        let saved: Bool

        init(key: String, saved: Bool) {
            self.key = key
            self.saved = saved
        }

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            saved = try row.decode(Bool.self)
        }
    }

    struct Area: Decodable {
        let lead, rest: [String]
        let from: [String: String]
        let problem: Bool
    }

    struct AreaStep: Decodable {
        let saved, musicbrainz, above: [String]
        let problem: Bool
        let lead, rest: [Flagged]
        let area: Area
    }

    struct AreaRun: Decodable { let steps: [AreaStep] }

    struct PagesCase: Decodable {
        let next: Int
        let count: Int?
        let last, limit: Int
        let pages: String
    }

    struct AppendCase: Decodable {
        struct Out: Decodable {
            let groups, shown: [String]
            let added, held: Int
            let note: String?
            let said: String
        }
        let groups, shown, page: [String]
        let list: Int
        let out: Out
    }

    /// `[recorded search, the recording's place in it]`.
    struct Take: Decodable {
        let name: String
        let at: Int

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            name = try pair.decode(String.self)
            at = try pair.decode(Int.self)
        }
    }

    /// `[song key, its albums' ids joined]`.
    struct SongOut: Decodable, Equatable {
        let key, albums: String

        init(key: String, albums: String) {
            self.key = key
            self.albums = albums
        }

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            key = try pair.decode(String.self)
            albums = try pair.decode(String.self)
        }
    }

    struct SongPages: Decodable {
        struct Step: Decodable {
            let page: [Take]
            let recordings: Int
            let songs: [SongOut]
            let added, grown: Int
            let note: String?
            let said: String
        }
        struct Run: Decodable { let first: [Take]; let firstSongs: [String]; let steps: [Step] }
        struct Default: Decodable { let name: String; let split: Int; let songs: [String]; let added, grown: Int }
        let runs: [Run]
        let defaults: [Default]
    }

    struct KeptRun: Decodable {
        struct Step: Decodable {
            let keep: String?
            let value: Int?
            let present: [String]?
            let look: String?
            let found: Int?
        }
        let steps: [Step]
    }

    /// `[key, holder, position, the place marked saved, the row saved]`.
    struct Placed: Decodable, Equatable {
        let key, holder: String
        let position: Int
        let saved, rowSaved: Bool

        init(key: String, holder: String, position: Int, saved: Bool, rowSaved: Bool) {
            self.key = key
            self.holder = holder
            self.position = position
            self.saved = saved
            self.rowSaved = rowSaved
        }

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            holder = try row.decode(String.self)
            position = try row.decode(Int.self)
            saved = try row.decode(Bool.self)
            rowSaved = try row.decode(Bool.self)
        }
    }

    /// `[key, tier, source, position, the row saved]`.
    struct Candidate: Decodable, Equatable {
        let key: String
        let tier: Int
        let source, position: Double
        let saved: Bool

        init(key: String, tier: Int, source: Double, position: Double, saved: Bool) {
            self.key = key
            self.tier = tier
            self.source = source
            self.position = position
            self.saved = saved
        }

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            tier = try row.decode(Int.self)
            source = try row.decode(Double.self)
            position = try row.decode(Double.self)
            saved = try row.decode(Bool.self)
        }
    }

    struct Case: Decodable {
        struct Pool: Decodable { let library, brought, saved, musicbrainz: [Placed] }
        struct Moment: Decodable { let brought, saved: [Placed] }
        struct Decided: Decodable { let kinds: [String]; let prefix: [Flagged]; let place: Bool }
        struct Late: Decodable { let drawn: [String]; let counts: [Int]; let capped, all: [String] }
        struct Family: Decodable { let key: String; let saved: Bool; let family: [Flagged] }
        let text: String
        let library: LibraryResults?
        let failed: Bool
        let artistList: [Artist]?
        let list: Int
        let matches: [MBArtistMatch]?
        let groups: [String]?
        let songs: Songs?
        let saved: Found?
        let personal: Bool
        let yourAlbums: [String]?
        let yourArtists: [Count]?
        let plan: Plan?
        let kinds: [String]?
        let studio: Bool?
        let answer: Answer?
        let pool: ByKind<Pool>?
        let moment: ByKind<Moment>?
        let candidates: [Candidate]?
        let decided: [Decided]?
        let top, topFixed: [Flagged]?
        let sections, full: ByKind<[String]>?
        let late: ByKind<Late>?
        let families: [Family]?
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("search/search-saved-vectors.json"))
    }

    static func kinds(_ raws: [String]) throws -> [SearchKind] { try SearchAlbumsVectors.kinds(raws) }
    static func same(_ a: String?, _ b: String?) -> Bool { SearchVectors.same(a, b) }
    static func units(_ list: [String]) -> [[UInt16]] { list.map { (each: String) -> [UInt16] in Array(each.utf16) } }

    static func counts(_ given: Counts) -> [SearchKind: Int] {
        var counts: [SearchKind: Int] = [:]
        counts[.artists] = given.artists
        counts[.albums] = given.albums
        counts[.songs] = given.songs
        return counts
    }

    static func groups(_ ids: [String], _ vectors: Vectors) throws -> [ReleaseGroup] {
        try ids.map { (id: String) -> ReleaseGroup in
            try #require(vectors.groups.first { $0.id == id }, "group \(id)")
        }
    }

    static func index(_ list: Int, _ vectors: Vectors) -> OwnedIndex? {
        vectors.lists[list].map { OwnedIndex($0) }
    }

    static func songs(_ given: Songs?, _ vectors: Vectors) throws -> [FoundSong] {
        guard let given else { return [] }
        let recordings = try #require(vectors.recordings[given.name], "recordings \(given.name)")
        return SongSearch.group(Array(recordings.prefix(given.take)))
    }

    static func found(_ given: Found, _ vectors: Vectors) throws -> SavedFound {
        let credited: [ReleaseGroup]? = try given.credited.map { (ids: [String]) -> [ReleaseGroup] in try groups(ids, vectors) }
        return SavedFound(matches: given.matches, groups: try groups(given.groups, vectors), credited: credited,
                          songs: try songs(given.songs, vectors))
    }

    static func answer(_ made: SavedAnswer?) -> Answer? {
        guard let made else { return nil }
        let matches: [String] = made.matches.map(\.mbid)
        let groups: [String] = made.groups.map(\.id)
        let shown: [String] = made.shown.map(\.id)
        let songs: [String] = made.songs.map(\.key)
        return Answer(matches: matches, groups: groups, shown: shown, songs: songs)
    }

    static func placed(_ list: [SearchPlaced], rowSaved: Bool) -> [Placed] {
        list.map { (each: SearchPlaced) -> Placed in
            Placed(key: each.row.key, holder: each.holder.rawValue, position: each.position, saved: each.saved, rowSaved: rowSaved)
        }
    }

    static func flagged(_ rows: [SearchRow], saved: Set<String>) -> [Flagged] {
        rows.map { (row: SearchRow) -> Flagged in Flagged(key: row.key, saved: saved.contains(row.key)) }
    }

    static func flagged(_ picks: [SearchList.Candidate]) -> [Flagged] {
        picks.compactMap { (pick: SearchList.Candidate) -> Flagged? in
            pick.row.map { (row: SearchRow) -> Flagged in Flagged(key: row.key, saved: pick.saved) }
        }
    }

    static func flagUnits(_ list: [Flagged]) -> [[UInt16]] {
        list.map { (each: Flagged) -> [UInt16] in Array(each.key.utf16) + [each.saved ? 1 : 0] }
    }

    static func group(_ key: String) -> SearchRow { .group(ReleaseGroup(id: String(key.dropFirst("group:".count)))) }
}

/// The phone's slice 4 against the web's own answers (export-search-saved-vectors.cjs).
@Suite struct SearchSavedVectorTests {
    private typealias V = SearchSavedVectors

    @Test func theNumbersAreTheWebs() throws {
        let numbers = try V.load().numbers
        #expect(SearchSaved.waitMs == numbers.savedWaitMs)
        #expect(SearchSaved.artistAlbums == numbers.savedArtistAlbums)
        #expect(SearchAnswersKept.count == numbers.answersKept)
        #expect(SearchMore.offsetMax == numbers.offsetMax)
        #expect(SearchList.Source.yours == numbers.sources.yours)
        #expect(SearchList.Source.store == numbers.sources.store)
        #expect(SearchList.Source.saved == numbers.sources.saved)
        #expect(SearchList.Source.musicbrainz == numbers.sources.musicbrainz)
    }

    @Test func theWordsAreTheWebs() throws {
        let words = try V.load().words
        for each in words.saved {
            let made = SearchWords.saved(V.counts(each.counts))
            #expect(made == each.said, "\(each.said)")
        }
        #expect(words.musicBrainz.count >= 40)
        for each in words.musicBrainz {
            let made = SearchWords.musicBrainz(V.counts(each.counts), answered: each.answered, saved: each.saved)
            #expect(made == each.said, "\(each.said)")
        }
        for each in words.savedAway {
            let failure = each.failure.failure
            let made = SearchWords.savedAway(failure, short: each.short)
            let plain = SearchWords.failure(failure, short: each.short)
            #expect(made == each.said, "\(each.failure.message), short \(each.short)")
            #expect(plain == each.plain, "\(each.failure.message), short \(each.short): failureWords")
        }
        for each in words.nothingMore {
            let kind = try #require(SearchKind(rawValue: each.kind))
            let made = SearchWords.nothingMore(kind, each.text)
            #expect(V.same(made, each.said), "\(each.kind) \(each.text)")
        }
        for each in words.morePage {
            let made = SearchMore.pageWords(added: each.added, held: each.held, personal: each.personal)
            #expect(made.note == each.note && made.said == each.said, "\(each.added) added, \(each.held) held")
        }
        for each in words.moreSongs {
            let made = SearchMore.songsWords(added: each.added, grown: each.grown)
            #expect(made.note == each.note && made.said == each.said, "\(each.added) added, \(each.grown) grown")
        }
        #expect(SearchMore.button(.albums) == words.buttons.albums)
        #expect(SearchMore.button(.artists) == words.buttons.artists)
        #expect(SearchMore.button(.songs) == words.buttons.songs)
        #expect(V.same(SearchWords.loading, words.buttons.loading))
        #expect(SearchWords.tryAgain == words.buttons.tryAgain)
        #expect(SearchMore.far == words.far)
    }

    @Test func aStudioAlbumIsTheWebs() throws {
        let vectors = try V.load()
        #expect(vectors.studio.count == vectors.groups.count)
        for each in vectors.studio {
            let group = try #require(vectors.groups.first { $0.id == each.group })
            let made = SearchSaved.studioGroup(group)
            let name: String = group.title ?? group.id
            #expect(made == each.studio, "\(name)")
        }
    }

    @Test func whatsSavedForAViewIsTheWebs() throws {
        let vectors = try V.load()
        #expect(vectors.saved.count >= 120)
        for (number, each) in vectors.saved.enumerated() {
            let what = "saved \(number), \"\(each.text)\" in \(each.view)"
            let term = JSText.trim(each.text)
            let names: [String?] = each.names.map { (name: String) -> String? in name }
            let plan = SearchReading.read(term, names: SearchReading.artistNames(names))
            guard let wanted = each.plan else {
                #expect(plan == nil, "\(what): nothing to read")
                continue
            }
            let reading = try #require(plan, "\(what)")
            #expect(V.same(reading.query, wanted.query) && reading.kind.rawValue == wanted.kind, "\(what): the reading")
            let view = try #require(SearchView(rawValue: each.view))
            let kinds = try V.kinds(try #require(each.kinds))
            //? an optional Bool unwrapped, said so - `#require` of one alone is ambiguous (truth or presence)
            let studio = try #require(each.studio as Bool?)
            if !each.given {
                let madeKinds = SearchState.wantedKinds(term, reading, view: view)
                let madeStudio = view == .all && SearchAlbums.allAlbumsQuery(reading).studio
                #expect(madeKinds == kinds && madeStudio == studio, "\(what): the kinds asked")
            }
            let found: SavedFound? = try each.found.map { (given: V.Found) -> SavedFound in try V.found(given, vectors) }
            let made = SearchSaved.savedFor(reading, found, kinds: kinds, studio: studio, index: V.index(each.list, vectors))
            let answer = V.answer(made)
            #expect(answer == each.answer, "\(what)")
        }
    }

    @Test func aKindViewsRowsStayWhereTheyWereDrawn() throws {
        let vectors = try V.load()
        #expect(vectors.areas.count >= 60)
        for (run, each) in vectors.areas.enumerated() {
            var before: KindArea? = nil
            for (number, step) in each.steps.enumerated() {
                let what = "area \(run), step \(number)"
                let saved: [SearchRow] = step.saved.map(V.group)
                let musicbrainz: [SearchRow] = step.musicbrainz.map(V.group)
                let made = KindArea.arrange(before, saved: saved, musicbrainz: musicbrainz, above: Set(step.above),
                                            problem: step.problem)
                let from: [String: String] = made.area.from.mapValues { (source: KindArea.From) -> String in source.rawValue }
                let leadKeys: [String] = made.lead.map(\.key)
                let restKeys: [String] = made.rest.map(\.key)
                let wantedLead: [String] = step.lead.map(\.key)
                let wantedRest: [String] = step.rest.map(\.key)
                #expect(leadKeys == wantedLead && restKeys == wantedRest, "\(what): the rows")
                #expect(made.area.lead == step.area.lead && made.area.rest == step.area.rest, "\(what): the area's keys")
                #expect(from == step.area.from, "\(what): what each was drawn as")
                #expect(made.area.problem == step.area.problem, "\(what): the failure drawn")
                //? the web's row is the saved copy exactly when the area says it was drawn as what's saved
                let flags: [V.Flagged] = step.lead + step.rest
                for flag in flags {
                    let drawnAs = step.area.from[flag.key]
                    #expect((drawnAs == "saved") == flag.saved, "\(what): \(flag.key)'s copy")
                }
                before = made.area
            }
        }
    }

    @Test func whetherThereIsAnotherPageIsTheWebs() throws {
        let vectors = try V.load()
        #expect(vectors.pages.count > 1000)
        for each in vectors.pages {
            let made = SearchMore.pages(next: each.next, count: each.count, last: each.last, limit: each.limit)
            #expect(made.rawValue == each.pages, "next \(each.next), count \(String(describing: each.count)), last \(each.last), limit \(each.limit)")
        }
    }

    @Test func aPageOfAlbumsIsAppendedAsTheWebs() throws {
        let vectors = try V.load()
        #expect(vectors.append.count >= 80)
        for (number, each) in vectors.append.enumerated() {
            let what = "append \(number)"
            let made = SearchMore.appendPage(try V.groups(each.groups, vectors), try V.groups(each.shown, vectors),
                                             try V.groups(each.page, vectors), V.index(each.list, vectors))
            let groups: [String] = made.groups.map(\.id)
            let shown: [String] = made.shown.map(\.id)
            #expect(groups == each.out.groups && shown == each.out.shown, "\(what): the groups")
            #expect(made.added == each.out.added && made.held == each.out.held, "\(what): added and held")
            let words = SearchMore.pageWords(added: made.added, held: made.held, personal: each.list % 2 == 1)
            #expect(words.note == each.out.note && words.said == each.out.said, "\(what): its words")
        }
    }

    @Test func pagesOfSongsAreMergedAsTheWebs() throws {
        let vectors = try V.load()
        let pages = vectors.songPages
        #expect(pages.runs.count >= 40)
        func recordings(_ takes: [V.Take]) throws -> [MBRecording] {
            try takes.map { (take: V.Take) -> MBRecording in
                let list = try #require(vectors.recordings[take.name])
                return list[take.at]
            }
        }
        for (run, each) in pages.runs.enumerated() {
            var all = try recordings(each.first)
            var songs = SongSearch.group(all)
            let firstKeys: [String] = songs.map(\.key)
            #expect(V.units(firstKeys) == V.units(each.firstSongs), "run \(run): the first page")
            for (number, step) in each.steps.enumerated() {
                let what = "run \(run), page \(number + 2)"
                let made = SearchMore.appendSongs(all, try recordings(step.page), drawn: songs)
                let out: [V.SongOut] = made.songs.map { (song: FoundSong) -> V.SongOut in
                    V.SongOut(key: song.key, albums: song.albums.map(\.id).joined(separator: ","))
                }
                let outKeys: [String] = out.map(\.key)
                let wantedKeys: [String] = step.songs.map(\.key)
                let outAlbums: [String] = out.map(\.albums)
                let wantedAlbums: [String] = step.songs.map(\.albums)
                #expect(made.recordings.count == step.recordings, "\(what): the recordings")
                #expect(V.units(outKeys) == V.units(wantedKeys), "\(what): the songs, in order")
                #expect(outAlbums == wantedAlbums, "\(what): each song's albums")
                #expect(made.added == step.added && made.grown == step.grown, "\(what): added and grown")
                let words = SearchMore.songsWords(added: made.added, grown: made.grown)
                #expect(words.note == step.note && words.said == step.said, "\(what): its words")
                all = made.recordings
                songs = made.songs
            }
        }
        for each in pages.defaults {
            let list = try #require(vectors.recordings[each.name])
            let made = SearchMore.appendSongs(Array(list.prefix(each.split)), Array(list.dropFirst(each.split)))
            let keys: [String] = made.songs.map(\.key)
            #expect(V.units(keys) == V.units(each.songs), "\(each.name): drawn by default")
            #expect(made.added == each.added && made.grown == each.grown, "\(each.name): added and grown")
        }
    }

    @Test func theKeptAnswersAreKeptAsTheWebKeepsThem() throws {
        let vectors = try V.load()
        #expect(vectors.kept.count >= 6)
        for (run, each) in vectors.kept.enumerated() {
            var kept = SearchAnswersKept()
            var everyKey: [String] = []
            for step in each.steps {
                for key in [step.keep, step.look].compactMap({ (key: String?) -> String? in key }) where !everyKey.contains(key) {
                    everyKey.append(key)
                }
            }
            for (number, step) in each.steps.enumerated() {
                let what = "kept \(run), step \(number)"
                //? a second a step: every run well inside the phone's hour, which the web's page has no end to
                let now = Double(number)
                if let key = step.keep {
                    let value = try #require(step.value)
                    kept.keep(key, .albums(FullySearchAnswer(count: value)), at: now)
                    let wanted = Set(try #require(step.present))
                    let present = Set(kept.keys)
                    #expect(present == wanted, "\(what): kept")
                    #expect(kept.keys.count <= SearchAnswersKept.count, "\(what): at most the count")
                } else {
                    let key = try #require(step.look)
                    var value: Int? = nil
                    if case .albums(let answer)? = kept.kept(key, at: now) { value = answer.count }
                    #expect(value == step.found, "\(what): \(key)")
                }
            }
        }
    }

    @Test func everySearchWithWhatsSavedIsTheWebs() throws {
        let vectors = try V.load()
        #expect(vectors.cases.count >= 80)
        for (number, each) in vectors.cases.enumerated() {
            try check(each, number, vectors)
        }
    }

    private func check(_ each: V.Case, _ number: Int, _ vectors: V.Vectors) throws {
        let what = "case \(number), \"\(each.text)\""
        let folders = vectors.lists[each.list]
        let index = V.index(each.list, vectors)
        let ownedArtists = OwnedAnswer(albums: folders ?? []).artists
        let results = each.failed ? nil : each.library
        var known: [String: Album] = [:]
        for album in results?.albums ?? [] { known[album.id] = album }
        let evidence = SongEvidence(heard: results?.songs)
        let yourArtists: [String: Int]? = each.personal ? each.yourArtists.map { (pairs: [V.Count]) -> [String: Int] in
            Dictionary(pairs.map { ($0.id, $0.count) }, uniquingKeysWith: { (_: Int, later: Int) -> Int in later })
        } : nil
        let yourAlbums: Set<String>? = each.personal ? each.yourAlbums.map { Set($0) } : nil
        let marks = SearchMarks(personal: each.personal, index: index, yourAlbums: yourAlbums, yourArtists: yourArtists,
                                known: known, evidence: evidence)
        let term = JSText.trim(each.text)
        let plan = SearchReading.read(term, names: SearchReading.artistNames(SearchList.knownNames(ownedArtists, results)))
        guard let wanted = each.plan else {
            #expect(plan == nil, "\(what): nothing to read")
            return
        }
        let reading = try #require(plan, "\(what)")
        #expect(V.same(reading.query, wanted.query) && reading.kind.rawValue == wanted.kind, "\(what): the reading")

        //? what's saved, as All draws it
        let kinds = SearchState.wantedKinds(term, reading, view: .all)
        let studio = SearchAlbums.allAlbumsQuery(reading).studio
        let wantedKinds = try V.kinds(try #require(each.kinds))
        #expect(kinds == wantedKinds && studio == each.studio, "\(what): the kinds asked")
        let found: SavedFound? = try each.saved.map { (given: V.Found) -> SavedFound in try V.found(given, vectors) }
        let saved = SearchSaved.savedFor(reading, found, kinds: kinds, studio: studio, index: index)
        let answer = V.answer(saved)
        #expect(answer == each.answer, "\(what): what's saved")

        let songs: [FoundSong]? = try each.songs.map { (given: V.Songs) -> [FoundSong] in try V.songs(given, vectors) }
        let mbGroups: [ReleaseGroup]? = try each.groups.map { (ids: [String]) -> [ReleaseGroup] in try V.groups(ids, vectors) }
        let albums: SearchAlbumsInHand? = mbGroups.map { (list: [ReleaseGroup]) -> SearchAlbumsInHand in
            SearchAlbumsInHand(groups: list, shown: SearchAlbums.notInLibrary(list, index))
        }
        let moment = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks,
                                     saved: saved)
        let pool = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks,
                                   albums: albums, artists: each.matches, songs: songs, saved: saved)
        for (kind, blocks) in SearchVectors.kinds(try #require(each.pool)) {
            let library = V.placed(pool[kind].library, rowSaved: false)
            let brought = V.placed(pool[kind].brought, rowSaved: false)
            let savedBlock = V.placed(pool[kind].saved, rowSaved: true)
            let musicbrainz = V.placed(pool[kind].musicbrainz, rowSaved: false)
            #expect(library == blocks.library, "\(what): the pool's \(kind), the library's")
            #expect(brought == blocks.brought, "\(what): the pool's \(kind), brought in")
            #expect(savedBlock == blocks.saved, "\(what): the pool's \(kind), what's saved")
            #expect(musicbrainz == blocks.musicbrainz, "\(what): the pool's \(kind), MusicBrainz's")
        }
        for (kind, blocks) in SearchVectors.kinds(try #require(each.moment)) {
            let brought = V.placed(moment[kind].brought, rowSaved: false)
            let savedBlock = V.placed(moment[kind].saved, rowSaved: true)
            #expect(brought == blocks.brought && savedBlock == blocks.saved, "\(what): \(kind) at the library's moment")
        }

        let candidates = SearchList.candidates(pool, box: term, reading: reading)
        let madeCandidates: [V.Candidate] = candidates.map { (each: SearchList.Candidate) -> V.Candidate in
            V.Candidate(key: each.key, tier: each.tier, source: each.source, position: each.position, saved: each.saved)
        }
        #expect(madeCandidates == each.candidates, "\(what): the candidates")

        //? Top results' family: what's saved's groups, then MusicBrainz's - a relative made of a saved group marked
        let keptGroups = saved?.groups ?? []
        let savedIds = Set(keptGroups.map(\.id))
        let groupsAtMoment = keptGroups
        let groups = keptGroups + (mbGroups ?? [])
        let n = SearchPacing.topResults
        let momentCandidates = SearchList.candidates(moment, box: term, reading: reading)
        for decided in try #require(each.decided) {
            let phantoms = try V.kinds(decided.kinds).compactMap { SearchList.phantom($0, reading) }
            let made = SearchList.decidedTop(momentCandidates, phantoms: phantoms, n: n, library: results,
                                             artistList: each.artistList, index: index, groups: groupsAtMoment,
                                             saved: savedIds, evidence: evidence)
            let prefix = V.flagged(made.prefix, saved: made.saved)
            #expect(V.flagUnits(prefix) == V.flagUnits(decided.prefix) && made.place == decided.place,
                    "\(what): decided with \(decided.kinds) out")
        }
        let top = SearchList.topPicks(candidates, n: n, library: results, artistList: each.artistList, index: index,
                                      groups: groups, saved: savedIds, evidence: evidence)
        #expect(V.flagUnits(V.flagged(top)) == V.flagUnits(try #require(each.top)), "\(what): Top results")
        let phantoms = kinds.compactMap { SearchList.phantom($0, reading) }
        let decided = SearchList.decidedTop(momentCandidates, phantoms: phantoms, n: n, library: results,
                                            artistList: each.artistList, index: index, groups: groupsAtMoment,
                                            saved: savedIds, evidence: evidence)
        let fixed = SearchList.topPicks(candidates, n: n, library: results, artistList: each.artistList, index: index,
                                        groups: groups, saved: savedIds, evidence: evidence, fixed: decided.prefix,
                                        fixedSaved: decided.saved)
        #expect(V.flagUnits(V.flagged(fixed)) == V.flagUnits(try #require(each.topFixed)), "\(what): Top results completed")

        for (kind, keys) in SearchVectors.kinds(try #require(each.sections)) {
            let made: [String] = SearchList.sectionRows(pool[kind], cap: SearchPacing.cap(kind)).map(\.key)
            #expect(V.units(made) == V.units(keys), "\(what): the \(kind) section")
        }
        for (kind, keys) in SearchVectors.kinds(try #require(each.full)) {
            let made: [String] = SearchList.sectionRows(pool[kind]).map(\.key)
            #expect(V.units(made) == V.units(keys), "\(what): all the \(kind)")
        }
        //? what's saved drawn at the library's moment; MusicBrainz's answer adds only what isn't there
        for (kind, late) in SearchVectors.kinds(try #require(each.late)) {
            let drawn = SearchList.sectionRows(moment[kind], cap: SearchPacing.cap(kind))
            let drawnKeys: [String] = drawn.map(\.key)
            #expect(V.units(drawnKeys) == V.units(late.drawn), "\(what): the \(kind) drawn at the moment")
            let counts = SearchList.drawnCounts(pool[kind], drawn)
            #expect([counts.0, counts.1] == late.counts, "\(what): the \(kind) drawn, counted")
            let keys = Set(drawnKeys)
            let capped: [String] = SearchList.lateRows(pool[kind], cap: SearchPacing.cap(kind), drawn: keys).map(\.key)
            let all: [String] = SearchList.lateRows(pool[kind], drawn: keys).map(\.key)
            #expect(V.units(capped) == V.units(late.capped), "\(what): the \(kind) MusicBrainz adds")
            #expect(V.units(all) == V.units(late.all), "\(what): every \(kind) MusicBrainz adds")
        }

        let blocks: [(SearchPlaced, Bool)] = SearchKind.allCases.flatMap { (kind: SearchKind) -> [(SearchPlaced, Bool)] in
            let rows = pool[kind]
            return (rows.library + rows.brought).map { ($0, false) } + rows.saved.map { ($0, true) }
                + rows.musicbrainz.map { ($0, false) }
        }
        let relatives = blocks.filter { (placed: SearchPlaced, _: Bool) -> Bool in
            if case .mbSong = placed.row { return true }
            if case .group = placed.row { return true }
            return false
        }
        let families = try #require(each.families)
        let relativeKeys: [String] = relatives.map { (placed: SearchPlaced, _: Bool) -> String in placed.row.key }
        let familyKeys: [String] = families.map(\.key)
        #expect(V.units(relativeKeys) == V.units(familyKeys), "\(what): the rows with relatives")
        for ((placed, rowSaved), family) in zip(relatives, families) {
            #expect(rowSaved == family.saved, "\(what): \(placed.row.key) saved")
            let made = SearchList.familyMarked(of: placed.row, rowSaved: rowSaved, library: results,
                                               artistList: each.artistList, index: index, groups: groups,
                                               saved: savedIds, evidence: evidence)
            let marked: [V.Flagged] = made.map { (relative: (row: SearchRow, saved: Bool)) -> V.Flagged in
                V.Flagged(key: relative.row.key, saved: relative.saved)
            }
            #expect(V.flagUnits(marked) == V.flagUnits(family.family), "\(what): \(placed.row.key)'s relatives")
        }
    }
}
