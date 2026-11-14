import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/search/search-vectors.json: what the web's TypeScript (lib/searchList.ts, lib/searchQuery.ts,
/// lib/searchResults.ts, lib/songs.ts's titleKey, lib/owned.ts, lib/whose.ts) answers, written by
/// ios/scripts/export-search-vectors.cjs - never by hand - and the shapes it is read into. The library's answers, the
/// artists, the albums and the folders in it are decoded by the real models (LibraryResults, Artist, Album, Song,
/// OwnedAlbum).
enum SearchVectors {
    struct Vectors: Decodable {
        let numbers: Numbers
        let words: Words
        let fold: [FoldCase]
        let names: [NamesCase]
        let readings: [ReadingCase]
        let owned: [OwnedCase]
        let whose: [WhoseCase]
        let prefetch: Prefetch
        let cases: [Case]
    }

    struct Counts: Decodable { let artistCount, albumCount, songCount: Int }
    struct ByKind<T: Decodable>: Decodable { let artists, albums, songs: T }

    struct Numbers: Decodable {
        let searchCounts: Counts
        let chipCounts: ByKind<Counts>
        let topResults: Int
        let preview: ByKind<Int>
        let albumsPrefetched, librarySettleMs, musicBrainzSettleMs, musicBrainzMinChars, maxCharacters: Int
        let variousArtists: String
        let kinds: [String]
    }

    struct Words: Decodable {
        struct Counted: Decodable {
            struct Counts: Decodable { let artists, albums, songs: Int? }
            let counts: Counts
            let said, library, libraryPersonal: String
        }
        struct Nothing: Decodable { let text, said: String }
        struct ViewCase: Decodable { let view, said: String; let nothing: [Nothing] }
        struct ArtistLine: Decodable { let count: Int?; let personal, top: Bool; let said: String }

        let prompt, label, labelPersonal, searching, searchingPersonal, checkSpelling: String
        let moreFromLibrary, moreFromCollection, topResults, inYourLibrary, inTheCollection: String
        let counts: [Counted]
        let views: [ViewCase]
        let artistLine: [ArtistLine]
    }

    struct FoldCase: Decodable { let text, foldName, titleKey: String }

    /// `[key, name]`.
    struct Entry: Decodable {
        let key, name: String

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            key = try pair.decode(String.self)
            name = try pair.decode(String.self)
        }
    }
    struct NamesCase: Decodable { let names: [String?]; let entries: [Entry] }

    struct Plan: Decodable { let query, kind: String; let artist, title: String? }
    struct ReadingCase: Decodable { let names: [String?]; let text: String; let plan: Plan? }

    struct OwnedCase: Decodable {
        struct Release: Decodable { let id: String?; let held: [String] }
        struct Query: Decodable { let groupId: String?; let releaseIds: [String]?; let title: String?; let artists: [String?]? }
        struct Group: Decodable { let query: Query; let held, guessed: [String] }
        let albums: [OwnedAlbum]
        let artists: [String]
        let total: Int
        let releases: [Release]
        let groups: [Group]
    }

    /// `[id, count]` - an artist's count of your albums.
    struct Count: Decodable {
        let id: String
        let count: Int

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            id = try pair.decode(String.self)
            count = try pair.decode(Int.self)
        }
    }

    struct WhoseCase: Decodable {
        struct Given: Decodable {
            let personal: Bool
            let index: Bool?
            let yourAlbums: [String]?
            let yourArtists: [Count]?
            let known: Bool?
        }
        struct OfAlbum: Decodable { let album: Album; let yours, navidrome: Bool?; let place: String }
        struct OfSong: Decodable { let song: Song; let yours: Bool? }
        struct OfArtist: Decodable { let artist: Artist; let yours: Bool? }
        let marks: Given
        let albums: [OfAlbum]
        let songs: [OfSong]
        let artists: [OfArtist]
        let folders: [OwnedAlbum]
        let known: [Album]
    }

    struct Prefetch: Decodable {
        struct Albums: Decodable { let songs, preferred: [String?]; let count: Int; let ids: [String] }
        struct Index: Decodable { let songs: [String]?; let id: String; let at: Int }
        let albums: [Albums]
        let index: [Index]
    }

    /// `[key, holder, position]`.
    struct Placed: Decodable, Equatable {
        let key, holder: String
        let position: Int

        init(key: String, holder: String, position: Int) {
            self.key = key
            self.holder = holder
            self.position = position
        }

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            holder = try row.decode(String.self)
            position = try row.decode(Int.self)
        }
    }

    /// `[key, tier, source, position]`.
    struct Candidate: Decodable, Equatable {
        let key: String
        let tier: Int
        let source, position: Double

        init(key: String, tier: Int, source: Double, position: Double) {
            self.key = key
            self.tier = tier
            self.source = source
            self.position = position
        }

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            tier = try row.decode(Int.self)
            source = try row.decode(Double.self)
            position = try row.decode(Double.self)
        }
    }

    /// `[key, yours]` - yours true, false or null.
    struct Yours: Decodable {
        let key: String
        let yours: Bool?

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            key = try row.decode(String.self)
            yours = try row.decodeNil() ? nil : row.decode(Bool.self)
        }
    }

    struct Line: Decodable { let key, line, place: String }

    struct Case: Decodable {
        let text: String
        let library: LibraryResults?
        let failed: Bool
        let artistList: [Artist]?
        let folders: [OwnedAlbum]
        let personal: Bool
        let yourAlbums: [String]?
        let yourArtists: [Count]?
        let ready: [Album]
        let plan: Plan?
        let pool: ByKind<[Placed]>?
        let candidates: [Candidate]?
        let top: [Line]?
        let decided: [String]?
        let sections: ByKind<[Line]>?
        let full: ByKind<[String]>?
        let whose: [Yours]?
        let said: String?
        let prefetch: [String]?
        let named: String?
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("search/search-vectors.json"))
    }

    /// Equal as JavaScript compares strings: code unit by code unit (Swift's == is canonical equivalence).
    static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return Array(a.utf16) == Array(b.utf16)
        default: return false
        }
    }

    static func kinds<T>(_ by: ByKind<T>) -> [(SearchKind, T)] {
        [(.artists, by.artists), (.albums, by.albums), (.songs, by.songs)]
    }

    /// A state with a case's words typed, its library answered (or failed) and - when the words ask MusicBrainz - its
    /// albums answered with nothing, as slice 1's cases hold none.
    static func state(_ each: Case, ownedArtists: [String]) -> SearchState {
        var state = SearchState()
        state.ownedArtists = ownedArtists
        state.typed(each.text)
        let token = state.askingLibrary()
        if each.failed {
            state.libraryFailed(token, state.query)
        } else {
            state.libraryAnswered(token, state.query, each.library ?? LibraryResults())
        }
        if state.drawnMusicBrainz(state.query), let ask = state.askingMusicBrainz(state.query, view: .all) {
            state.albumsAnswered(ask, FullySearchAnswer(), query: ask.first, index: nil)
        }
        return state
    }

    /// A case's marks as the web's Search makes them (Search.tsx `marksNow`): the albums in hand - search3's over
    /// those asked for so a song plays.
    static func marks(_ each: Case, index: OwnedIndex) -> SearchMarks {
        var known: [String: Album] = [:]
        for album in each.ready { known[album.id] = album }
        if !each.failed {
            for album in each.library?.albums ?? [] { known[album.id] = album }
        }
        return SearchMarks(
            personal: each.personal, index: index,
            yourAlbums: each.personal ? each.yourAlbums.map { Set($0) } : nil,
            yourArtists: each.personal ? each.yourArtists.map { (pairs: [Count]) -> [String: Int] in
                Dictionary(pairs.map { ($0.id, $0.count) }, uniquingKeysWith: { (_: Int, later: Int) -> Int in later })
            } : nil,
            known: known)
    }
}

/// The phone's Search against the web's own answers (export-search-vectors.cjs).
@Suite struct SearchVectorTests {
    private typealias V = SearchVectors

    @Test func theNumbersAreTheWebs() throws {
        let numbers = try V.load().numbers
        #expect(SearchPacing.artistCount == numbers.searchCounts.artistCount)
        #expect(SearchPacing.albumCount == numbers.searchCounts.albumCount)
        #expect(SearchPacing.songCount == numbers.searchCounts.songCount)
        #expect(SearchPacing.all == SearchCounts(artists: numbers.searchCounts.artistCount,
                                                 albums: numbers.searchCounts.albumCount,
                                                 songs: numbers.searchCounts.songCount))
        for (kind, counts) in V.kinds(numbers.chipCounts) {
            #expect(SearchPacing.chip(kind) == SearchCounts(artists: counts.artistCount, albums: counts.albumCount,
                                                            songs: counts.songCount), "\(kind)")
        }
        for (kind, cap) in V.kinds(numbers.preview) {
            #expect(SearchPacing.preview(kind) == cap, "\(kind)")
        }
        #expect(SearchPacing.topResults == numbers.topResults)
        #expect(SearchPacing.albumsPrefetched == numbers.albumsPrefetched)
        #expect(SearchReading.librarySettleMs == numbers.librarySettleMs)
        #expect(SearchReading.musicBrainzSettleMs == numbers.musicBrainzSettleMs)
        #expect(SearchReading.musicBrainzMinChars == numbers.musicBrainzMinChars)
        #expect(SearchReading.maxCharacters == numbers.maxCharacters)
        #expect(SearchReading.variousArtists == numbers.variousArtists)
        #expect(SearchKind.allCases.map(\.rawValue) == numbers.kinds)
    }

    @Test func theWordsAreTheWebs() throws {
        let words = try V.load().words
        #expect(SearchWords.prompt == words.prompt)
        #expect(SearchWords.label == words.label && SearchWords.label == words.labelPersonal)
        #expect(SearchWords.searching(personal: false) == words.searching)
        #expect(SearchWords.searching(personal: true) == words.searchingPersonal)
        #expect(SearchWords.checkSpelling == words.checkSpelling)
        #expect(SearchWords.moreFromLibrary(personal: false) == words.moreFromLibrary)
        #expect(SearchWords.moreFromLibrary(personal: true) == words.moreFromCollection)
        #expect(SearchWords.topResults == words.topResults)
        #expect(Whose.inYourLibrary == words.inYourLibrary && Whose.inTheCollection == words.inTheCollection)
        for each in words.counts {
            var counts: [SearchKind: Int] = [:]
            counts[.artists] = each.counts.artists
            counts[.albums] = each.counts.albums
            counts[.songs] = each.counts.songs
            #expect(SearchWords.count(counts) == each.said, "\(counts)")
            #expect(SearchWords.library(counts, personal: false) == each.library, "\(counts)")
            #expect(SearchWords.library(counts, personal: true) == each.libraryPersonal, "\(counts)")
        }
        for each in words.views {
            let view = try #require(SearchView(rawValue: each.view))
            #expect(SearchWords.view(view) == each.said)
            for nothing in each.nothing {
                #expect(V.same(SearchWords.nothing(view, nothing.text), nothing.said), "\(view) \(nothing.text)")
            }
        }
        for each in words.artistLine {
            #expect(SearchList.artistLine(each.count, personal: each.personal, top: each.top) == each.said,
                    "\(String(describing: each.count)) \(each.personal) \(each.top)")
        }
    }

    @Test func namesAndTitlesFoldAsTheWebs() throws {
        for each in try V.load().fold {
            #expect(V.same(Fold.key(each.text), each.foldName), "foldName \(Array(each.text.unicodeScalars))")
            #expect(V.same(SongTitle.key(each.text), each.titleKey), "titleKey \(Array(each.text.unicodeScalars))")
        }
    }

    @Test func theBoxIsReadAgainstTheWebsNames() throws {
        let vectors = try V.load()
        for each in vectors.names {
            let names = SearchReading.artistNames(each.names)
            let wanted = Dictionary(each.entries.map { (entry: V.Entry) -> (FoldKey, [UInt16]) in
                (FoldKey(entry.key), Array(entry.name.utf16))
            }, uniquingKeysWith: { (first: [UInt16], _: [UInt16]) -> [UInt16] in first })
            #expect(names.mapValues { Array($0.utf16) } == wanted, "\(each.names)")
        }
        for each in vectors.readings {
            let plan = SearchReading.read(each.text, names: SearchReading.artistNames(each.names))
            let what = "\"\(each.text)\" against \(each.names)"
            guard let wanted = each.plan else {
                #expect(plan == nil, "\(what)")
                continue
            }
            let read = try #require(plan, "\(what)")
            #expect(V.same(read.query, wanted.query), "\(what): the query")
            #expect(read.kind.rawValue == wanted.kind, "\(what): the reading")
            #expect(V.same(read.artist, wanted.artist), "\(what): the artist")
            #expect(V.same(read.title, wanted.title), "\(what): the title")
        }
    }

    @Test func theFoldersAreIndexedAndLookedUpAsTheWebs() throws {
        for each in try V.load().owned {
            let index = OwnedIndex(each.albums)
            #expect(index.total == each.total)
            #expect(OwnedAnswer(albums: each.albums).artists == each.artists)
            for release in each.releases {
                #expect(OwnedIndex.forRelease(index, release.id).map(\.path) == release.held,
                        "release \(String(describing: release.id))")
            }
            for group in each.groups {
                let found = OwnedIndex.forGroup(index, groupId: group.query.groupId,
                                                releaseIds: group.query.releaseIds ?? [], title: group.query.title ?? "",
                                                artists: group.query.artists ?? [])
                #expect(found.held.map(\.path) == group.held, "\(group.query)")
                #expect(found.guessed.map(\.path) == group.guessed, "\(group.query)")
            }
        }
        // no index is nothing held
        #expect(OwnedIndex.forRelease(nil, "rel-dummy").isEmpty)
        #expect(OwnedIndex.forGroup(nil, groupId: "rg-dummy").held.isEmpty)
    }

    @Test func whoseIsTheWebs() throws {
        for each in try V.load().whose {
            let given = each.marks
            let marks = SearchMarks(
                personal: given.personal, index: given.index == true ? OwnedIndex(each.folders) : nil,
                yourAlbums: given.yourAlbums.map { Set($0) },
                yourArtists: given.yourArtists.map { (pairs: [V.Count]) -> [String: Int] in
                    Dictionary(pairs.map { ($0.id, $0.count) }, uniquingKeysWith: { (_: Int, later: Int) -> Int in later })
                },
                known: given.known == true ? Dictionary(each.known.map { ($0.id, $0) },
                                                        uniquingKeysWith: { (_: Album, later: Album) -> Album in later }) : [:])
            let what = "\(given.personal) index \(given.index == true) known \(given.known == true)"
            for album in each.albums {
                let yours = SearchWhose.album(album.album, marks)
                #expect(yours == album.yours, "\(what): album \(album.album.id)")
                #expect(SearchWhose.navidrome(starred: album.album.starred, musicBrainzId: album.album.musicBrainzId,
                                              index: marks.index) == album.navidrome, "\(what): \(album.album.id) by Navidrome")
                #expect(SearchWhose.place(personal: marks.personal, yours: yours) == album.place, "\(what): \(album.album.id)'s place")
            }
            for song in each.songs {
                #expect(SearchWhose.song(song.song, marks) == song.yours, "\(what): song \(song.song.id)")
            }
            for artist in each.artists {
                #expect(SearchWhose.artist(artist.artist, marks) == artist.yours, "\(what): artist \(artist.artist.id)")
            }
        }
    }

    @Test func theAlbumsAskedForFirstAreTheWebs() throws {
        let prefetch = try V.load().prefetch
        for each in prefetch.albums {
            let songs = each.songs.enumerated().map { (pair: (offset: Int, element: String?)) -> Song in
                Song(id: "s\(pair.offset)", albumId: pair.element)
            }
            let preferred = each.preferred.enumerated().map { (pair: (offset: Int, element: String?)) -> Song in
                Song(id: "p\(pair.offset)", albumId: pair.element)
            }
            #expect(SearchPacing.albumsToPrefetch(songs, preferred: preferred, count: each.count) == each.ids,
                    "\(each.songs) \(each.preferred) \(each.count)")
        }
        for each in prefetch.index {
            let songs = each.songs.map { (ids: [String]) -> [Song] in ids.map { Song(id: $0) } }
            #expect((SearchPacing.songIndex(songs, each.id) ?? -1) == each.at, "\(String(describing: each.songs)) \(each.id)")
        }
    }

    /// Every worked and seeded search, made as the web makes it: the reading, the pool, the candidates, Top results,
    /// the sections and every line - and the list drawn as the phone draws it holds the same.
    @Test func everySearchIsTheWebs() throws {
        let cases = try V.load().cases
        #expect(cases.count >= 200)
        for (number, each) in cases.enumerated() {
            let what = "case \(number), \"\(each.text)\""
            let index = OwnedIndex(each.folders)
            let ownedArtists = OwnedAnswer(albums: each.folders).artists
            let results = each.failed ? nil : each.library
            let marks = V.marks(each, index: index)
            let term = JSText.trim(each.text)
            let names = SearchReading.artistNames(SearchList.knownNames(ownedArtists, results))
            let plan = SearchReading.read(term, names: names)
            guard let wanted = each.plan else {
                #expect(plan == nil, "\(what): nothing to read")
                var state = V.state(each, ownedArtists: ownedArtists)
                #expect(state.advance(artistList: each.artistList, marks: marks) == nil, "\(what): nothing drawn")
                continue
            }
            let reading = try #require(plan, "\(what)")
            #expect(V.same(reading.query, wanted.query) && reading.kind.rawValue == wanted.kind
                    && V.same(reading.artist, wanted.artist) && V.same(reading.title, wanted.title), "\(what): the reading")

            let pool = SearchList.pool(reading: reading, library: results, artistList: each.artistList, marks: marks)
            for (kind, placed) in V.kinds(try #require(each.pool)) {
                #expect(pool[kind].library.map { V.Placed(key: $0.row.key, holder: $0.holder.rawValue, position: $0.position) } == placed,
                        "\(what): the pool's \(kind)")
            }
            let candidates = SearchList.candidates(pool, box: term, reading: reading)
            #expect(candidates.map { V.Candidate(key: $0.key, tier: $0.tier, source: $0.source, position: $0.position) }
                    == each.candidates, "\(what): the candidates")

            let top = SearchList.topResults(candidates, n: SearchPacing.topResults, library: results,
                                            artistList: each.artistList)
            let wantedTop = try #require(each.top)
            #expect(top.map(\.key) == wantedTop.map(\.key), "\(what): Top results")
            #expect(top.map(\.key) == each.decided, "\(what): Top results decided")
            for (row, line) in zip(top, wantedTop) {
                let made = SearchList.line(row, marks, top: true)
                #expect(V.same(made.line, line.line) && V.same(made.place, line.place),
                        "\(what): \(row.key)'s Top line \"\(made.said)\"")
            }

            var drawnSections: [SearchList.Drawn.Section] = []
            for (kind, lines) in V.kinds(try #require(each.sections)) {
                let rows = SearchList.sectionRows(pool[kind], cap: SearchPacing.cap(kind))
                #expect(rows.map(\.key) == lines.map(\.key), "\(what): the \(kind) section")
                for (row, line) in zip(rows, lines) {
                    let made = SearchList.line(row, marks)
                    #expect(V.same(made.line, line.line) && V.same(made.place, line.place),
                            "\(what): \(row.key)'s line \"\(made.said)\"")
                }
                if !rows.isEmpty { drawnSections.append(SearchList.Drawn.Section(kind: kind, rows: rows)) }
            }
            for (kind, keys) in V.kinds(try #require(each.full)) {
                #expect(SearchList.sectionRows(pool[kind]).map(\.key) == keys, "\(what): all the \(kind)")
            }
            let whose = SearchKind.allCases.flatMap { (kind: SearchKind) -> [SearchPlaced] in pool[kind].library }
            #expect(whose.map(\.row.key) == (each.whose ?? []).map(\.key), "\(what): whose, the rows")
            for (placed, yours) in zip(whose, each.whose ?? []) {
                #expect(SearchWhose.row(placed.row, marks) == yours.yours, "\(what): whose \(placed.row.key)")
            }
            let said = SearchWords.library(results?.counts ?? [:], personal: each.personal)
            #expect(said == each.said, "\(what): the words")
            let prefetch = results.map { (found: LibraryResults) -> [String] in
                SearchPacing.albumsToPrefetch(found.songs, preferred: SearchPacing.preferredSongs(top))
            } ?? []
            #expect(prefetch == each.prefetch, "\(what): the albums asked for first")
            let named = SearchList.namedArtist(reading, SearchList.knownArtists(each.artistList, results?.artists ?? []))
            #expect(named?.id == each.named, "\(what): the artist named")

            // the list as the phone draws it (SearchState, MusicBrainz answering with nothing): the same Top results
            // and sections, drawn whole
            var state = V.state(each, ownedArtists: ownedArtists)
            let drawingMade = state.advance(artistList: each.artistList, marks: marks)
            let drawing = try #require(drawingMade, "\(what): drawn")
            let drawn = drawing.drawn
            let musicBrainz = state.drawnMusicBrainz(term)
            #expect(drawn.top == top, "\(what): drawn, Top results")
            #expect(drawn.sections == drawnSections, "\(what): drawn, the sections")
            #expect(drawn.failed == each.failed && drawn.musicBrainz == musicBrainz, "\(what): drawn")
            #expect(drawing.said == [each.said ?? "", musicBrainz ? "Nothing more found." : ""].filter { !$0.isEmpty }
                .joined(separator: " "), "\(what): drawn, the words")
            #expect(drawn.nothing == (top.isEmpty && drawnSections.isEmpty && !each.failed && musicBrainz),
                    "\(what): nothing found")
            // a kind view's Artists, led by the artist the box named when its own search3 didn't list them
            if let found = results {
                let rows = SearchList.kindRows(.artists, rows: found.artists.map { SearchRow.artist($0) }, text: term,
                                               allResults: found, ownedArtists: ownedArtists,
                                               artistList: each.artistList)
                let listed = found.artists.map { "artist:\($0.id)" }
                let lead = named.map { (artist: Artist) -> [String] in listed.contains("artist:\(artist.id)") ? [] : ["artist:\(artist.id)"] } ?? []
                #expect(rows.map(\.key) == lead + listed, "\(what): the Artists view")
            }
        }
    }
}
