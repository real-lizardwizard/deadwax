import Foundation
import Testing
@testable import DeadwaxCore

/// Similar Artists (SimilarArtists, Last.fm slice A2 - lastfm.md 3.4): Last.fm's similar artists met with the library -
/// by MusicBrainz id, else one artist alone with the folded name - each tile yours (their page) or theirs (their
/// MusicBrainz page, needing an id), each once, never the page's own, twelve at most, in Last.fm's order.
@Suite struct SimilarArtistsTests {
    static let pond = "69ac44f7-c80d-47b4-9bc8-fcc758d209e6"
    static let gum = "bca076a4-0ff5-43ae-b4c1-27ece7a0ca1c"
    static let temples = "3514578c-402a-4825-bd97-a525f31004e6"
    static let tame = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"

    static func similar(_ name: String, _ mbid: String? = nil) -> LastfmSimilarArtist {
        LastfmSimilarArtist(name: name, mbid: mbid, match: 0.5, url: "https://www.last.fm/music/\(name)")
    }

    static func kinds(_ tiles: [SimilarArtists.Tile]) -> [String] {
        tiles.map { (tile: SimilarArtists.Tile) -> String in
            switch tile.opens {
            case .artist(let artist): return "yours:\(artist.id):\(tile.name)"
            case .musicBrainz(let mbid, let name): return "theirs:\(mbid.prefix(4)):\(name)"
            }
        }
    }

    @Test func yoursByIdElseByTheOneArtistWithTheName() {
        let library = SimilarArtists.Library([
            Artist(id: "ar-pond", name: "POND", coverArt: "ar-pond", musicBrainzId: Self.pond.uppercased()),
            Artist(id: "ar-temples", name: "Temples"),
            Artist(id: "ar-mgmt", name: "MGMT"),
        ])
        let tiles = SimilarArtists.tiles([Self.similar("Pond", Self.pond), Self.similar("temples", Self.temples),
                                          Self.similar("GUM", Self.gum), Self.similar("M.G.M.T.")],
                                         library: library, page: "ar-tame", mbid: Self.tame)
        // Pond by their id (drawn with the library's own name), Temples by their folded name, GUM not in the library -
        // and "M.G.M.T." folds to "m g m t", no one's
        #expect(Self.kinds(tiles) == ["yours:ar-pond:POND", "yours:ar-temples:Temples", "theirs:bca0:GUM"])
        #expect(tiles[0].coverArt == "ar-pond" && tiles[2].coverArt == nil)
        #expect(tiles.map(\.line) == ["", "", "Not in your library"])
        #expect(tiles.map(\.spoken) == ["POND", "Temples", "GUM, Not in your library"])
        #expect(tiles.map(\.id) == ["artist:ar-pond", "artist:ar-temples", "mb:\(Self.gum)"])
    }

    @Test func twoWhoShareTheFoldedNameAreNoMatch() {
        // "Low" and "LOW" in the library: neither is guessed at - theirs, by Last.fm's id
        let library = SimilarArtists.Library([Artist(id: "ar-1", name: "Low"), Artist(id: "ar-2", name: "LOW")])
        let low = "e53a5a1d-b1e5-4b2e-8bda-14ab7bd79f2d"
        let tiles = SimilarArtists.tiles([Self.similar("Low", low)], library: library, page: "ar-x", mbid: nil)
        #expect(Self.kinds(tiles) == ["theirs:e53a:Low"])
        // with no id either: nowhere to open, so no tile
        #expect(SimilarArtists.tiles([Self.similar("Low")], library: library, page: "ar-x", mbid: nil).isEmpty)
        // one alone with the name: yours
        let one = SimilarArtists.Library([Artist(id: "ar-1", name: "Low")])
        #expect(Self.kinds(SimilarArtists.tiles([Self.similar("low")], library: one, page: "ar-x", mbid: nil))
            == ["yours:ar-1:Low"])
    }

    static let nirvanaUS = "5b11f4ce-a62d-471e-81fc-a69a8278c7da"
    static let nirvanaUK = "9282c8b4-ca0b-4c6b-b7e3-4f7762dfc4d6"

    /// (A2's review, correcting lastfm.md 3.4) Two different ids are two artists: the 1960s UK Nirvana Last.fm names by
    /// its own id is never your Seattle Nirvana, whose folder carries theirs - a tile of theirs, opening MusicBrainz.
    @Test func idsThatDifferAreTwoArtistsWhateverTheName() {
        let library = SimilarArtists.Library([Artist(id: "ar-nirvana", name: "Nirvana", musicBrainzId: Self.nirvanaUS)])
        let tiles = SimilarArtists.tiles([Self.similar("Nirvana", Self.nirvanaUK)], library: library, page: "ar-x",
                                         mbid: nil)
        #expect(Self.kinds(tiles) == ["theirs:9282:Nirvana"])
        #expect(tiles.map(\.opens) == [.musicBrainz(mbid: Self.nirvanaUK, name: "Nirvana")])
        // Last.fm naming yours by your id: yours
        let same = SimilarArtists.tiles([Self.similar("NIRVANA", Self.nirvanaUS.uppercased())], library: library,
                                        page: "ar-x", mbid: nil)
        #expect(Self.kinds(same) == ["yours:ar-nirvana:Nirvana"])
    }

    /// The name alone meets them only where one side has no id.
    @Test func byNameOnlyWhereOneSideHasNoId() {
        // yours without an id, Last.fm's with one: yours, by the one name
        let untagged = SimilarArtists.Library([Artist(id: "ar-low", name: "Low")])
        #expect(Self.kinds(SimilarArtists.tiles([Self.similar("Low", Self.nirvanaUK)], library: untagged, page: "ar-x",
                                                mbid: nil)) == ["yours:ar-low:Low"])
        // yours with an id, Last.fm's without: yours, by the one name
        let tagged = SimilarArtists.Library([Artist(id: "ar-low", name: "Low", musicBrainzId: Self.nirvanaUS)])
        #expect(Self.kinds(SimilarArtists.tiles([Self.similar("low")], library: tagged, page: "ar-x", mbid: nil))
            == ["yours:ar-low:Low"])
        // neither with one: yours, by the one name
        #expect(Self.kinds(SimilarArtists.tiles([Self.similar("LOW")], library: untagged, page: "ar-x", mbid: nil))
            == ["yours:ar-low:Low"])
    }

    /// Two library artists with one id (Navidrome splitting one artist under two spellings): the first in the list's
    /// order, as ArtistJoin's claims keep the first - never the last, never neither.
    @Test func twoLibraryArtistsWithOneIdGiveTheFirst() {
        let library = SimilarArtists.Library([Artist(id: "ar-1", name: "Beyoncé", musicBrainzId: Self.pond),
                                              Artist(id: "ar-2", name: "Beyonce", musicBrainzId: Self.pond.uppercased())])
        let tiles = SimilarArtists.tiles([Self.similar("Beyoncé", Self.pond)], library: library, page: "ar-x", mbid: nil)
        #expect(Self.kinds(tiles) == ["yours:ar-1:Beyoncé"])
        // the list the other way round: the other first
        let other = SimilarArtists.Library([Artist(id: "ar-2", name: "Beyonce", musicBrainzId: Self.pond),
                                            Artist(id: "ar-1", name: "Beyoncé", musicBrainzId: Self.pond)])
        #expect(Self.kinds(SimilarArtists.tiles([Self.similar("Beyoncé", Self.pond)], library: other, page: "ar-x",
                                                mbid: nil)) == ["yours:ar-2:Beyonce"])
    }

    /// (A2's review) A phone's tile grows with the text, but never past the page: at AX5 (112 at 13 points' footnote,
    /// grown to 44: some 379) it is the page's 343, See All's grid one column.
    @Test func aTileNeverOutgrowsThePage() {
        let ax5 = SimilarArtists.gridMin * 44 / 13
        #expect(ax5 > 343)
        #expect(SimilarArtists.side(ax5, page: 343) == 343)
        #expect(SimilarArtists.side(SimilarArtists.gridMin, page: 343) == SimilarArtists.gridMin)
        // the page not yet measured: the side grown with the text
        #expect(SimilarArtists.side(ax5, page: nil) == ax5 && SimilarArtists.side(ax5, page: 0) == ax5)
    }

    @Test func theirsWithoutAnIdIsLeftOut() {
        let tiles = SimilarArtists.tiles([Self.similar("Melody's Echo Chamber"), Self.similar("GUM", Self.gum)],
                                         library: SimilarArtists.Library([]), page: "ar-x", mbid: nil)
        #expect(Self.kinds(tiles) == ["theirs:bca0:GUM"])
    }

    @Test func yoursOpenTheirPageNeverMusicBrainzs() {
        // a library artist Last.fm names by id opens their page in the library, not the MusicBrainz artist's
        let pond = Artist(id: "ar-pond", name: "Pond", musicBrainzId: Self.pond)
        let tiles = SimilarArtists.tiles([Self.similar("Pond", Self.pond)], library: SimilarArtists.Library([pond]),
                                         page: "ar-x", mbid: nil)
        #expect(tiles.map(\.opens) == [.artist(pond)] && tiles[0].yours)
        // theirs open MusicBrainz's, with Last.fm's name to draw at once
        let gum = SimilarArtists.tiles([Self.similar("GUM", Self.gum)], library: nil, page: "ar-x", mbid: nil)
        #expect(gum.map(\.opens) == [.musicBrainz(mbid: Self.gum, name: "GUM")] && !gum[0].yours)
    }

    @Test func eachOnceNeverThePagesOwnTwelveAtMost() {
        let library = SimilarArtists.Library([Artist(id: "ar-tame", name: "Tame Impala", musicBrainzId: Self.tame),
                                              Artist(id: "ar-pond", name: "Pond", musicBrainzId: Self.pond)])
        // Pond twice (by id, then by name), the page's artist by id and by name - each once, the page's never
        let tiles = SimilarArtists.tiles([Self.similar("Pond", Self.pond), Self.similar("pond"),
                                          Self.similar("Tame Impala", Self.tame), Self.similar("tame impala"),
                                          Self.similar("GUM", Self.gum), Self.similar("Gum", Self.gum)],
                                         library: library, page: "ar-tame", mbid: Self.tame)
        #expect(Self.kinds(tiles) == ["yours:ar-pond:Pond", "theirs:bca0:GUM"])
        // their own id, while the library doesn't hold them: still not a tile
        let theirsOwn = SimilarArtists.tiles([Self.similar("Tame Impala", Self.tame)], library: nil, page: "ar-tame",
                                             mbid: Self.tame.uppercased())
        #expect(theirsOwn.isEmpty)
        // at most twelve, in Last.fm's order
        let many = (0..<20).map { (at: Int) -> LastfmSimilarArtist in
            Self.similar("Band \(at)", String(format: "%08d-0000-4000-8000-000000000000", at))
        }
        let twelve = SimilarArtists.tiles(many, library: nil, page: "ar-x", mbid: nil)
        #expect(twelve.count == SimilarArtists.shown && SimilarArtists.shown == 12)
        #expect(twelve.map(\.name) == (0..<12).map { "Band \($0)" })
    }

    @Test func noLibraryInHandMakesEveryTileTheirs() {
        let tiles = SimilarArtists.tiles([Self.similar("Pond", Self.pond), Self.similar("Temples")], library: nil,
                                         page: "ar-x", mbid: nil)
        #expect(Self.kinds(tiles) == ["theirs:69ac:Pond"])
        #expect(SimilarArtists.tiles(nil, library: nil, page: "ar-x", mbid: nil).isEmpty)
    }

    @Test func whenTheyAreDrawnAndSeeAll() {
        #expect(!SimilarArtists.drawsTiles(listKnown: false, waited: false))
        #expect(SimilarArtists.drawsTiles(listKnown: true, waited: false))
        #expect(SimilarArtists.drawsTiles(listKnown: false, waited: true))
        let tile = SimilarArtists.Tile(opens: .musicBrainz(mbid: Self.gum, name: "GUM"), name: "GUM")
        #expect(!SimilarArtists.seesAll(Array(repeating: tile, count: 4)))
        #expect(SimilarArtists.seesAll(Array(repeating: tile, count: 5)))
        #expect(SimilarArtists.listed(LastfmArtist(similar: [Self.similar("GUM", Self.gum)])))
        #expect(!SimilarArtists.listed(LastfmArtist(similar: [])) && !SimilarArtists.listed(nil))
        #expect(!SimilarArtists.listed(LastfmArtist(enabled: false, similar: [Self.similar("GUM", Self.gum)])))
        #expect(SimilarArtists.gridMin == 112 && SimilarArtists.seeAllPast == 4)
        #expect(LastfmWords.similarArtists == "Similar Artists")
    }

    /// The recorded answers (Fixtures/lastfm/answers/artist.json): Tame Impala's thirty, met with a library holding
    /// two of them.
    @Test func theRecordedSimilarArtistsMeetALibrary() throws {
        let (cases, _, _) = try LastfmDecodeTests.exported()
        let tame = try LastfmDecodeTests.named(cases, "Tame Impala, by MusicBrainz id").answer
        let similar = try #require(tame.similar)
        #expect(similar.count == 30)
        #expect(similar.prefix(3).map(\.name) == ["Pond", "Melody's Echo Chamber", "GUM"])
        let library = SimilarArtists.Library([Artist(id: "ar-pond", name: "Pond"),
                                              Artist(id: "ar-mgmt", name: "MGMT",
                                                     musicBrainzId: "c485632c-b784-4ee9-8ea1-c5fb365681fc")])
        let tiles = SimilarArtists.tiles(similar, library: library, page: "ar-tame", mbid: Self.tame)
        // twelve: Pond yours by name, Melody's Echo Chamber (no id) left out, MGMT yours by id
        #expect(tiles.count == 12)
        #expect(Array(Self.kinds(tiles).prefix(5)) == ["yours:ar-pond:Pond", "theirs:bca0:GUM", "theirs:3514:Temples",
                                                       "theirs:ab72:The Holydrug Couple",
                                                       "theirs:3244:Moses Gunn Collective"])
        #expect(Self.kinds(tiles).contains("yours:ar-mgmt:MGMT"))
        #expect(Set(tiles.map(\.id)).count == tiles.count)
    }
}
