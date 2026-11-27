import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/search/search-songs-vectors.json: what the web's TypeScript (lib/songs.ts, lib/searchList.ts's artists and
/// songs, lib/searchQuery.ts's song queries, lib/artistPage.ts's artistRows and factsLine, lib/pressings.ts's trackRows)
/// answers for slice 3, written by ios/scripts/export-search-songs-vectors.cjs - never by hand. The recordings, the
/// pressings, the folders, the groups and the library's answers in it are decoded by the real models (MBRecording,
/// PageRelease, OwnedAlbum, ReleaseGroup, LibraryResults, MBArtistMatch, MBArtistFacts).
///
/// Every comparison is made of values built outside `#expect`, in typed `let`s: CI's older Swift gives up type-checking
/// a closure or a `??` written inside the macro (b451241).
enum SearchSongsVectors {
    typealias Plan = SearchVectors.Plan
    typealias Placed = SearchVectors.Placed
    typealias Candidate = SearchVectors.Candidate
    typealias Count = SearchVectors.Count
    typealias ByKind = SearchVectors.ByKind
    typealias Line = SearchAlbumsVectors.Line
    typealias Lines = SearchAlbumsVectors.Lines

    struct Vectors: Decodable {
        let numbers: Numbers
        let words: Words
        let queries: Queries
        let titles: Titles
        let songs: [SongsCase]
        let holding: [HoldingCase]
        let pressings: PressingsCase
        let cases: [Case]
        let artist: ArtistCase
        let collation: Collation
    }

    struct Collation: Decodable {
        /// `[a, b, the sign of a.localeCompare(b)]`.
        struct Pair: Decodable {
            let a, b: String
            let sign: Int

            init(from decoder: any Decoder) throws {
                var row = try decoder.unkeyedContainer()
                a = try row.decode(String.self)
                b = try row.decode(String.self)
                sign = try row.decode(Int.self)
            }
        }
        let all, sorted: [String]
        let pairs: [Pair]
    }

    struct Numbers: Decodable { let songSearchLimit, artistSearchLimit, songIdsKept, artistsKept: Int }

    /// `[primary type | null, [secondary types]]`.
    struct Types: Decodable {
        let primary: String?
        let secondary: [String]

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            primary = try pair.decodeNil() ? nil : pair.decode(String.self)
            secondary = try pair.decode([String].self)
        }
    }

    struct Words: Decodable {
        struct Said: Decodable { let text, said: String }
        struct Fold: Decodable { let albums: [Types]; let said: String }
        let needATitle, songWords: String
        let noRelease: [Said]
        let fold: [Fold]
        let studioOnly, loading, away, truncated, noneStudio, none: String
    }

    struct Queries: Decodable {
        struct Reading: Decodable { let names: [String]; let text: String; let plan: Plan?; let song, title: String? }
        struct Fielded: Decodable { let title, artist, said: String }
        let readings: [Reading]
        let fielded: [Fielded]
    }

    struct Titles: Decodable {
        struct Title: Decodable { let title, key: String }
        struct Band: Decodable { let primary: String?; let secondary: [String]?; let band: String }
        let titles: [Title]
        let bands: [Band]
    }

    struct Album: Decodable {
        let id, title: String
        let primaryType: String?
        let secondaryTypes: [String]
        let kind, band, status, date, credit: String
        let releases, recordings: [String]
        let length: Double?
    }

    struct Named: Decodable { let id, name: String }

    struct Song: Decodable {
        let key, title, credit: String
        let artists: [Named]
        let recordings: [String]
        let albums: [Album]
    }

    struct SongsCase: Decodable {
        struct Bands: Decodable { let listed, folded: [String]; let label: String }
        let name, query: String
        let recordings: [MBRecording]
        let keys: [String]
        let songs: [Song]
        let bands: [Bands]
    }

    struct Evidence: Decodable {
        let heard: [DeadwaxCore.Song]?
        let pressings: [String: [PageRelease]]
        var evidence: SongEvidence { SongEvidence(heard: heard, pressings: pressings) }
    }

    struct HoldingCase: Decodable {
        struct OfAlbum: Decodable {
            let id: String
            let song, heard, other, albums, bare, releases: [String]
            let words, line: [String]
        }
        struct OfSong: Decodable {
            let key, named: String
            let held: [String]
            /// `[personal: [[section line, place], [Top line, place]]]`.
            let line: [[[String]]]
            let albums: [OfAlbum]
        }
        struct Read: Decodable { let list, evidence: Int; let songs: [OfSong] }
        let name: String
        let lists: [[OwnedAlbum]?]
        let evidence: [Evidence]
        let read: [Read]
    }

    struct PressingsCase: Decodable {
        struct IDs: Decodable { let text: String; let ids: [String] }
        struct IDList: Decodable { let list, ids: [String] }
        /// `[key, title, the song]`.
        struct Track: Decodable {
            let key, title: String
            let song: Bool

            init(from decoder: any Decoder) throws {
                var row = try decoder.unkeyedContainer()
                key = try row.decode(String.self)
                title = try row.decode(String.self)
                song = try row.decode(Bool.self)
            }
        }
        struct Ask: Decodable {
            let what: String
            let ids: [String]
            let matches: [[String]]?
            let pressing, chosen: String?
            let tracks: [Track]
        }
        let group: String
        let releases: [PageRelease]
        let ids: [IDs]
        let idLists: [IDList]
        let asks: [Ask]
    }

    struct Case: Decodable {
        struct Pool: Decodable { let library, brought, musicbrainz: [Placed] }
        struct Decided: Decodable { let kinds: [String]; let prefix: [String]; let place: Bool }
        struct Family: Decodable { let key: String; let family: [Line] }
        struct Songs: Decodable { let name: String; let take: Int }
        /// `[id, line, the releases the bridge is asked, the albums heard, any other pressing]`.
        struct DisclosedAlbum: Decodable {
            let id, line: String
            let releases, albums: [String]
            let other: Bool

            init(from decoder: any Decoder) throws {
                var row = try decoder.unkeyedContainer()
                id = try row.decode(String.self)
                line = try row.decode(String.self)
                releases = try row.decode([String].self)
                albums = try row.decode([String].self)
                other = try row.decode(Bool.self)
            }
        }
        struct Disclosure: Decodable {
            let key: String
            let listed, folded: [String]
            let fold: String?
            let named: String
            let albums: [DisclosedAlbum]
        }
        let text: String
        let library: LibraryResults?
        let failed: Bool
        let artistList: [Artist]?
        /// The folder lists and the evidence by their place in that recording search's `holding`.
        let songsOf: String?
        let list, ev: Int
        let matches: [MBArtistMatch]?
        let groups: [ReleaseGroup]?
        let songs: Songs?
        let personal: Bool
        let yourAlbums: [String]?
        let yourArtists: [Count]?
        let plan: Plan?
        let song: String?
        let pool: ByKind<Pool>?
        let candidates: [Candidate]?
        let decided: [Decided]?
        let top: [Line]?
        let topFixed: [String]?
        let sections, full: ByKind<[String]>?
        let lines: [Lines]?
        let families: [Family]?
        let disclosures: [Disclosure]?
    }

    struct ArtistCase: Decodable {
        struct Row: Decodable {
            let key, title: String
            let year, group: String?
            let held, yours: Bool?
            let editions: Int
            let releases: [String]
            let kind: String?
            let line, linePersonal: String
        }
        struct Page: Decodable { let list: Int; let groups: [String]; let rows: [Row] }
        struct Facts: Decodable { let facts: MBArtistFacts?; let line: String }
        let groups: [ReleaseGroup]
        let lists: [[OwnedAlbum]?]
        let pages: [Page]
        let facts: [Facts]
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("search/search-songs-vectors.json"))
    }

    static func kinds(_ raws: [String]) throws -> [SearchKind] { try SearchAlbumsVectors.kinds(raws) }
    static func index(_ folders: [OwnedAlbum]?) -> OwnedIndex? { folders.map { OwnedIndex($0) } }
    static func same(_ a: String?, _ b: String?) -> Bool { SearchVectors.same(a, b) }

    /// Text compared by UTF-16 code units, as the web's `===` compares it.
    static func units(_ list: [String]) -> [[UInt16]] { list.map { (each: String) -> [UInt16] in Array(each.utf16) } }

    static func optional(_ value: String?) -> String { value.map { (text: String) -> String in "=\(text)" } ?? "nil" }

    static func flag(_ value: Bool?) -> String {
        guard let value else { return "nil" }
        return value ? "true" : "false"
    }

    static func length(_ value: Double?) -> String { value.map { (ms: Double) -> String in String(ms) } ?? "nil" }

    /// A song's album as words, made and wanted alike.
    static func cells(_ album: SongAlbum) -> [String] {
        [album.id, album.title, optional(album.primaryType), album.secondaryTypes.joined(separator: "|"), album.kind,
         album.band.rawValue, album.status, album.date, album.credit, album.releases.joined(separator: ","),
         album.recordings.joined(separator: ","), length(album.length)]
    }

    static func cells(_ album: Album) -> [String] {
        [album.id, album.title, optional(album.primaryType), album.secondaryTypes.joined(separator: "|"), album.kind,
         album.band, album.status, album.date, album.credit, album.releases.joined(separator: ","),
         album.recordings.joined(separator: ","), length(album.length)]
    }

    static func cells(_ song: FoundSong) -> [String] {
        let artists: [String] = song.artists.map { (artist: SongArtist) -> String in "\(artist.id)=\(artist.name)" }
        return [song.key, song.title, song.credit, artists.joined(separator: ","), song.recordings.joined(separator: ",")]
    }

    static func cells(_ song: Song) -> [String] {
        let artists: [String] = song.artists.map { (artist: Named) -> String in "\(artist.id)=\(artist.name)" }
        return [song.key, song.title, song.credit, artists.joined(separator: ","), song.recordings.joined(separator: ",")]
    }

    static func paths(_ folders: [OwnedAlbum]) -> [String] { folders.map(\.path) }

    static func placed(_ list: [SearchPlaced]) -> [Placed] {
        list.map { (each: SearchPlaced) -> Placed in Placed(key: each.row.key, holder: each.holder.rawValue, position: each.position) }
    }

    static func lineCells(_ line: SearchList.Line) -> [[UInt16]] { units([line.line, line.place]) }
}

/// The phone's slice 3 against the web's own answers (export-search-songs-vectors.cjs).
@Suite struct SearchSongsVectorTests {
    private typealias V = SearchSongsVectors

    @Test func theNumbersAreTheWebs() throws {
        let numbers = try V.load().numbers
        #expect(SongSearch.limit == numbers.songSearchLimit)
        #expect(MBArtistSearch.limit == numbers.artistSearchLimit)
        #expect(SongSearch.idsKept == numbers.songIdsKept)
        #expect(MBArtistPage.kept == numbers.artistsKept)
    }

    @Test func theWordsAreTheWebs() throws {
        let words = try V.load().words
        #expect(V.same(SongSearch.needATitle, words.needATitle))
        #expect(V.same(SongSearch.songWords, words.songWords))
        for each in words.noRelease {
            let made = SongSearch.noRelease(each.text)
            #expect(V.same(made, each.said), "\(each.text)")
        }
        #expect(words.fold.count > 20)
        for (number, each) in words.fold.enumerated() {
            let albums: [SongAlbum] = each.albums.map { (types: V.Types) -> SongAlbum in
                SongAlbum(id: "x", title: "x", primaryType: types.primary, secondaryTypes: types.secondary, kind: "", band: .other)
            }
            let made = SongSearch.foldLabel(albums)
            #expect(made == each.said, "fold \(number)")
        }
        #expect(MBArtistPage.studioOnly == words.studioOnly)
        #expect(V.same(MBArtistPage.loading, words.loading))
        #expect(MBArtistPage.away == words.away)
        #expect(MBArtistPage.truncated == words.truncated)
        #expect(MBArtistPage.none(studio: true) == words.noneStudio)
        #expect(MBArtistPage.none(studio: false) == words.none)
    }

    @Test func theSongQueriesAreTheWebs() throws {
        let queries = try V.load().queries
        #expect(queries.readings.count > 60)
        for each in queries.readings {
            let what = "\"\(each.text)\" with \(each.names)"
            let plan = SearchReading.read(JSText.trim(each.text), names: SearchReading.artistNames(each.names))
            let madeKind: String? = plan?.kind.rawValue
            #expect(madeKind == each.plan?.kind, "\(what): the reading")
            let song: String? = SongSearch.query(each.text, plan)
            #expect(V.same(song, each.song), "\(what): the song search")
            let title: String? = SongSearch.titleQuery(each.text)
            #expect(V.same(title, each.title), "\(what): its fallback")
        }
        for each in queries.fielded {
            let made = SongSearch.fieldedQuery(title: each.title, artist: each.artist)
            #expect(V.same(made, each.said), "\(each.title) by \(each.artist)")
        }
    }

    @Test func titlesAndBandsAreTheWebs() throws {
        let titles = try V.load().titles
        #expect(titles.titles.count > 40)
        for each in titles.titles {
            let made = SongTitle.key(each.title)
            #expect(V.same(made, each.key), "\"\(each.title)\"")
        }
        for each in titles.bands {
            let made = SongSearch.band(each.primary, each.secondary).rawValue
            #expect(made == each.band, "\(V.optional(each.primary)) \(each.secondary ?? [])")
        }
    }

    /// Every recording search grouped into songs: each recording's key, every song and every album it is on, in full.
    @Test func everySongSearchIsGroupedAsTheWebs() throws {
        for each in try V.load().songs {
            let keys: [String] = each.recordings.map { (recording: MBRecording) -> String in SongSearch.key(recording) }
            #expect(V.units(keys) == V.units(each.keys), "\(each.name): the keys")
            let songs = SongSearch.group(each.recordings)
            let madeSongs: [[String]] = songs.map { (song: FoundSong) -> [String] in V.cells(song) }
            let wantedSongs: [[String]] = each.songs.map { (song: V.Song) -> [String] in V.cells(song) }
            #expect(madeSongs == wantedSongs, "\(each.name): the songs")
            for (song, wanted) in zip(songs, each.songs) {
                let made: [[String]] = song.albums.map { (album: SongAlbum) -> [String] in V.cells(album) }
                let want: [[String]] = wanted.albums.map { (album: V.Album) -> [String] in V.cells(album) }
                #expect(made == want, "\(each.name), \(song.title): its albums")
            }
            for (song, bands) in zip(songs, each.bands) {
                let split = SongSearch.bands(song)
                let listed: [String] = split.listed.map(\.id)
                let folded: [String] = split.folded.map(\.id)
                #expect(listed == bands.listed && folded == bands.folded, "\(each.name), \(song.title): its bands")
                let label = SongSearch.foldLabel(split.folded)
                #expect(label == bands.label, "\(each.name), \(song.title): its fold")
            }
        }
    }

    /// Every album a song is on, read against folder lists and evidence: what is held of it and how, the releases the id
    /// bridge is asked about, its words and its line; each song's named album and its row's line.
    @Test func whatIsHeldOfASongsAlbumsIsTheWebs() throws {
        let vectors = try V.load()
        for each in vectors.holding {
            let search = try #require(vectors.songs.first { $0.name == each.name }, "\(each.name)")
            let songs = SongSearch.group(search.recordings)
            #expect(each.read.count == each.lists.count * each.evidence.count, "\(each.name)")
            for read in each.read {
                let index = V.index(each.lists[read.list])
                let evidence = each.evidence[read.evidence].evidence
                let what = "\(each.name), folders \(read.list), evidence \(read.evidence)"
                #expect(read.songs.count == min(3, songs.count), "\(what)")
                for (song, wanted) in zip(songs, read.songs) {
                    #expect(V.same(song.key, wanted.key), "\(what)")
                    let named = SongSearch.namedAlbum(song, index, evidence)
                    #expect(named.album.id == wanted.named && V.paths(named.held) == wanted.held, "\(what), \(song.title): named")
                    for (personal, lines) in zip([false, true], wanted.line) {
                        let marks = SearchMarks(personal: personal, index: index, evidence: evidence)
                        let section = V.lineCells(SearchList.line(.mbSong(song), marks))
                        let top = V.lineCells(SearchList.line(.mbSong(song), marks, top: true))
                        #expect(section == V.units(lines[0]), "\(what), \(song.title): its line, personal \(personal)")
                        #expect(top == V.units(lines[1]), "\(what), \(song.title): its Top line, personal \(personal)")
                    }
                    #expect(wanted.albums.count == min(8, song.albums.count), "\(what), \(song.title)")
                    for (album, want) in zip(song.albums, wanted.albums) {
                        let on = "\(what), \(song.title) on \(album.title)"
                        #expect(album.id == want.id, "\(on)")
                        let holding = SongSearch.holding(index, album, song, evidence)
                        let split: [[String]] = [V.paths(holding.song), V.paths(holding.heard), V.paths(holding.other), holding.albums]
                        let wantedSplit: [[String]] = [want.song, want.heard, want.other, want.albums]
                        #expect(split == wantedSplit, "\(on): its holding")
                        let bare = V.paths(SongSearch.held(index, album, nil, evidence))
                        #expect(bare == want.bare, "\(on): held, with no song")
                        let releases = SongSearch.heldReleases(index, album, song, evidence)
                        #expect(releases == want.releases, "\(on): the releases the bridge is asked")
                        let words: [String] = [SongSearch.albumWords(holding, personal: false), SongSearch.albumWords(holding, personal: true)]
                        #expect(V.units(words) == V.units(want.words), "\(on): its words")
                        let lines: [String] = [SongSearch.albumLine(album, song, index, personal: false, evidence),
                                               SongSearch.albumLine(album, song, index, personal: true, evidence)]
                        #expect(V.units(lines) == V.units(want.line), "\(on): its line")
                    }
                }
            }
        }
    }

    /// The Slow Rush opened from a song: the ids an address carries, which tracks are the song, the pressing shown, and
    /// the tracklist with the song marked.
    @Test func theAlbumOpenedFromASongIsTheWebs() throws {
        let pressings = try V.load().pressings
        for each in pressings.ids {
            let made = SongSearch.ids(each.text)
            #expect(made == each.ids, "\"\(each.text)\"")
        }
        for each in pressings.idLists {
            let made = SongSearch.ids(each.list)
            #expect(made == each.ids, "\(each.list)")
        }
        let releases = pressings.releases
        let usual = Pressings.view(releases)
        for ask in pressings.asks {
            let matches = SongSearch.matcher(releases, ask.ids)
            let found: [[String]]? = matches.map { (isSong: (MBTrack) -> Bool) -> [[String]] in
                releases.map { (release: PageRelease) -> [String] in
                    var keys: [String] = []
                    for (disc, medium) in release.media.enumerated() {
                        for (at, track) in medium.tracks.enumerated() where isSong(track) { keys.append("\(disc):\(at)") }
                    }
                    return keys
                }
            }
            #expect(found == ask.matches, "\(ask.what): the song's tracks")
            let picked = SongSearch.pressing(releases, ask.ids)
            #expect(picked == ask.pressing, "\(ask.what): the pressing")
            let view = Pressings.view(releases, asked: picked)
            #expect(view.chosenId == ask.chosen, "\(ask.what): chosen")
            let release: PageRelease? = releases.first { (each: PageRelease) -> Bool in each.id == view.chosenId }
            let diff: TracklistDiff? = view.chosenId.flatMap { (id: String) -> TracklistDiff? in usual.diffs[id] ?? nil }
            let rows = Pressings.trackRows(release, diff, isSong: matches)
            let made: [String] = rows.map { (row: PressingTrack) -> String in "\(row.key) \(row.title) \(row.song)" }
            let wanted: [String] = ask.tracks.map { (row: V.PressingsCase.Track) -> String in "\(row.key) \(row.title) \(row.song)" }
            #expect(V.units(made) == V.units(wanted), "\(ask.what): the tracklist")
        }
        let page = GroupPage(id: pressings.group, answer: ReleaseGroupAnswer(id: pressings.group, releases: releases), preview: nil, index: nil,
                             picked: nil, personal: false, editors: false, song: pressings.asks[0].ids)
        let marked: [String] = page.tracks.filter(\.song).map(\.title)
        let wantedMarked: [String] = pressings.asks[0].tracks.filter(\.song).map(\.title)
        #expect(marked == wantedMarked, "the page opened from Patience marks it")
    }

    /// Every worked and seeded search with MusicBrainz's artists and songs in hand, made as the web makes it.
    @Test func everySearchWithArtistsAndSongsIsTheWebs() throws {
        let vectors = try V.load()
        #expect(vectors.cases.count >= 60)
        for (number, each) in vectors.cases.enumerated() {
            try check(each, number, vectors)
        }
    }

    private func check(_ each: V.Case, _ number: Int, _ vectors: V.Vectors) throws {
        let what = "case \(number), \"\(each.text)\""
        let holding: V.HoldingCase? = each.songsOf.flatMap { (name: String) -> V.HoldingCase? in
            vectors.holding.first { $0.name == name }
        }
        let folders: [OwnedAlbum]? = holding.flatMap { (case_: V.HoldingCase) -> [OwnedAlbum]? in
            case_.lists[min(each.list, case_.lists.count - 1)]
        }
        let given: SongEvidence = holding.map { (case_: V.HoldingCase) -> SongEvidence in case_.evidence[each.ev].evidence } ?? .none
        let index = V.index(folders)
        let ownedArtists = OwnedAnswer(albums: folders ?? []).artists
        let results = each.failed ? nil : each.library
        var known: [String: Album] = [:]
        for album in results?.albums ?? [] { known[album.id] = album }
        let evidence = SongEvidence(heard: results?.songs, pressings: given.pressings)
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
        let asked: String? = SongSearch.query(term, reading)
        #expect(V.same(asked, each.song), "\(what): the song search")
        let recordings: [MBRecording]? = try each.songs.map { (songs: V.Case.Songs) -> [MBRecording] in
            let found = try #require(vectors.songs.first { $0.name == songs.name }, "\(what): \(songs.name)")
            return Array(found.recordings.prefix(songs.take))
        }
        let songs: [FoundSong]? = recordings.map { SongSearch.group($0) }
        let groups = each.groups ?? []
        let albums: SearchAlbumsInHand? = each.groups.map { (list: [ReleaseGroup]) -> SearchAlbumsInHand in
            SearchAlbumsInHand(groups: list, shown: SearchAlbums.notInLibrary(list, index))
        }
        let bare = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks)
        let pool = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks,
                                   albums: albums, artists: each.matches, songs: songs)
        for (kind, blocks) in SearchVectors.kinds(try #require(each.pool)) {
            let library = V.placed(pool[kind].library)
            let brought = V.placed(pool[kind].brought)
            let musicbrainz = V.placed(pool[kind].musicbrainz)
            #expect(library == blocks.library, "\(what): the pool's \(kind), the library's")
            #expect(brought == blocks.brought, "\(what): the pool's \(kind), brought in")
            #expect(musicbrainz == blocks.musicbrainz, "\(what): the pool's \(kind), MusicBrainz's")
        }
        let candidates = SearchList.candidates(pool, box: term, reading: reading)
        let madeCandidates: [V.Candidate] = candidates.map { (each: SearchList.Candidate) -> V.Candidate in
            V.Candidate(key: each.key, tier: each.tier, source: each.source, position: each.position)
        }
        #expect(madeCandidates == each.candidates, "\(what): the candidates")

        let n = SearchPacing.topResults
        let bareCandidates = SearchList.candidates(bare, box: term, reading: reading)
        for decided in try #require(each.decided) {
            let phantoms = try V.kinds(decided.kinds).compactMap { SearchList.phantom($0, reading) }
            let made = SearchList.decidedTop(bareCandidates, phantoms: phantoms, n: n, library: results,
                                             artistList: each.artistList, index: index, groups: groups, evidence: evidence)
            let prefix: [String] = made.prefix.map(\.key)
            #expect(prefix == decided.prefix && made.place == decided.place, "\(what): decided with \(decided.kinds) out")
        }
        let top = SearchList.topResults(candidates, n: n, library: results, artistList: each.artistList, index: index,
                                        groups: groups, evidence: evidence)
        let wantedTop = try #require(each.top)
        let topKeys: [String] = top.map(\.key)
        let wantedTopKeys: [String] = wantedTop.map(\.key)
        #expect(V.units(topKeys) == V.units(wantedTopKeys), "\(what): Top results")
        for (row, line) in zip(top, wantedTop) {
            let made = V.lineCells(SearchList.line(row, marks, top: true))
            #expect(made == V.units([line.line, line.place]), "\(what): \(row.key)'s Top line")
        }
        let allPhantoms = SearchKind.allCases.compactMap { SearchList.phantom($0, reading) }
        let prefix = SearchList.decidedTop(bareCandidates, phantoms: allPhantoms, n: n, library: results,
                                           artistList: each.artistList, index: index, groups: groups, evidence: evidence).prefix
        let fixed = SearchList.topResults(candidates, n: n, library: results, artistList: each.artistList, index: index,
                                          groups: groups, evidence: evidence, fixed: prefix)
        let fixedKeys: [String] = fixed.map(\.key)
        #expect(V.units(fixedKeys) == V.units(each.topFixed ?? []), "\(what): Top results completed")

        for (kind, keys) in SearchVectors.kinds(try #require(each.sections)) {
            let made: [String] = SearchList.sectionRows(pool[kind], cap: SearchPacing.cap(kind)).map(\.key)
            #expect(V.units(made) == V.units(keys), "\(what): the \(kind) section")
        }
        for (kind, keys) in SearchVectors.kinds(try #require(each.full)) {
            let made: [String] = SearchList.sectionRows(pool[kind]).map(\.key)
            #expect(V.units(made) == V.units(keys), "\(what): all the \(kind)")
        }

        let rows: [SearchRow] = SearchKind.allCases.flatMap { (kind: SearchKind) -> [SearchRow] in
            (pool[kind].library + pool[kind].brought + pool[kind].musicbrainz).map(\.row)
        }
        let lines = try #require(each.lines)
        let rowKeys: [String] = rows.map(\.key)
        let lineKeys: [String] = lines.map(\.key)
        #expect(V.units(rowKeys) == V.units(lineKeys), "\(what): every row")
        for (row, line) in zip(rows, lines) {
            let section = V.lineCells(SearchList.line(row, marks))
            let topLine = V.lineCells(SearchList.line(row, marks, top: true))
            #expect(section == V.units([line.line, line.place]), "\(what): \(row.key)'s line")
            #expect(topLine == V.units([line.topLine, line.topPlace]), "\(what): \(row.key)'s Top line")
        }

        let relatives = rows.filter { (row: SearchRow) -> Bool in
            if case .mbSong = row { return true }
            if case .group = row { return true }
            return false
        }
        let families = try #require(each.families)
        let familyKeys: [String] = families.map(\.key)
        #expect(V.units(relatives.map(\.key)) == V.units(familyKeys), "\(what): the rows with relatives")
        for (row, family) in zip(relatives, families) {
            let made = SearchList.family(of: row, library: results, artistList: each.artistList, index: index,
                                         groups: groups, evidence: evidence)
            let madeKeys: [String] = made.map(\.key)
            let wantedKeys: [String] = family.family.map(\.key)
            #expect(V.units(madeKeys) == V.units(wantedKeys), "\(what): \(row.key)'s relatives")
            for (relative, line) in zip(made, family.family) {
                let said = V.lineCells(SearchList.line(relative, marks, top: true))
                #expect(said == V.units([line.line, line.place]), "\(what): relative \(relative.key)")
            }
        }

        let disclosed: [FoundSong] = rows.compactMap { (row: SearchRow) -> FoundSong? in
            if case .mbSong(let song) = row { return song }
            return nil
        }
        let disclosures = try #require(each.disclosures)
        #expect(disclosed.count == disclosures.count, "\(what): the songs disclosed")
        for (song, disclosure) in zip(disclosed, disclosures) {
            let of = "\(what), \(song.title)"
            let bands = SongSearch.bands(song)
            let listed: [String] = bands.listed.map(\.id)
            let folded: [String] = bands.folded.map(\.id)
            #expect(listed == disclosure.listed && folded == disclosure.folded, "\(of): its bands")
            let fold: String? = bands.folded.isEmpty ? nil : SongSearch.foldLabel(bands.folded)
            #expect(fold == disclosure.fold, "\(of): its fold")
            let named = SongSearch.namedAlbum(song, index, evidence).album.id
            #expect(named == disclosure.named, "\(of): its named album")
            #expect(song.albums.count == disclosure.albums.count, "\(of): its albums")
            for (album, want) in zip(song.albums, disclosure.albums) {
                let line = SongSearch.albumLine(album, song, index, personal: each.personal, evidence)
                #expect(album.id == want.id && V.same(line, want.line), "\(of) on \(album.title): its line")
                let holding = SongSearch.holding(index, album, song, evidence)
                let releases = SongSearch.heldReleases(index, album, song, evidence)
                #expect(releases == want.releases && holding.albums == want.albums, "\(of) on \(album.title): its tap")
                #expect(!holding.other.isEmpty == want.other, "\(of) on \(album.title): another pressing")
            }
        }
    }

    // MARK: localeCompare

    /// ICU's collation as WebCollation approximates it: every title the recorded answers carry, and made ones, sorted as
    /// JavaScript's (stable) sort orders them with localeCompare; and the sign of seeded pairs.
    @Test func titlesAreOrderedAsLocaleCompareOrdersThem() throws {
        let collation = try V.load().collation
        #expect(collation.all.count > 300)
        let sorted: [String] = collation.all.enumerated().sorted { (a: (offset: Int, element: String), b: (offset: Int, element: String)) -> Bool in
            let sign = WebCollation.compare(a.element, b.element)
            return sign != 0 ? sign < 0 : a.offset < b.offset
        }.map(\.element)
        #expect(V.units(sorted) == V.units(collation.sorted), "the order")
        for (made, wanted) in zip(sorted, collation.sorted) where !V.same(made, wanted) {
            Issue.record("first out of place: \(made) where the web has \(wanted)")
            break
        }
        for pair in collation.pairs {
            let sign = WebCollation.compare(pair.a, pair.b)
            #expect(sign == pair.sign, "\(pair.a) against \(pair.b)")
        }
    }

    // MARK: a MusicBrainz artist's page

    @Test func aMusicBrainzArtistsPageIsTheWebs() throws {
        let artist = try V.load().artist
        var byId: [String: ReleaseGroup] = [:]
        for group in artist.groups where byId[group.id] == nil { byId[group.id] = group }
        #expect(artist.pages.count >= 16)
        for page in artist.pages {
            let what = "folders \(page.list), groups \(page.groups.count)"
            let groups: [ReleaseGroup] = try page.groups.map { (id: String) -> ReleaseGroup in try #require(byId[id], "\(what): \(id)") }
            let rows = MBArtistPage.rows(groups, index: V.index(artist.lists[page.list]))
            let keys: [String] = rows.map(\.key)
            let wantedKeys: [String] = page.rows.map(\.key)
            #expect(V.units(keys) == V.units(wantedKeys), "\(what): the rows")
            for (row, want) in zip(rows, page.rows) {
                let made: [String] = [row.title, V.optional(row.year), V.optional(row.group.id), V.flag(row.held),
                                      V.flag(row.yours), String(row.editions), row.releases.joined(separator: ","),
                                      V.optional(row.kind)]
                let wanted: [String] = [want.title, V.optional(want.year), V.optional(want.group), V.flag(want.held),
                                        V.flag(want.yours), String(want.editions), want.releases.joined(separator: ","),
                                        V.optional(want.kind)]
                #expect(V.units(made) == V.units(wanted), "\(what): \(row.key)")
                let lines: [String] = [MBArtistPage.line(row, personal: false), MBArtistPage.line(row, personal: true)]
                #expect(V.units(lines) == V.units([want.line, want.linePersonal]), "\(what): \(row.key)'s line")
            }
        }
        for each in artist.facts {
            let made = MBArtistPage.factsLine(each.facts)
            #expect(V.same(made, each.line), "\(String(describing: each.facts))")
        }
    }
}
