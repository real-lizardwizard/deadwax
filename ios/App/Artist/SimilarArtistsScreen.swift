import DeadwaxCore
import SwiftUI

/// The Similar Artists page (Last.fm, slice A2 - deadwax-plans/lastfm.md 3.4; notes/ios.md "Last.fm, slice A2"): See
/// All's, from an artist's page - every tile their page has (12 at most) in a grid as wide as the page lets it, each
/// column 112 at least and growing with the text (never wider than the page - one column at AX5), so a mouse on the Mac
/// reaches every one; "From Last.fm" under them.
/// Its tiles are the artist page's showing under it (ArtistsModel.page): the same answer, nothing asked again. With no
/// such page (it was let go), the page is its own, as the Top Songs page is: the artist asked, and Last.fm's answer the
/// session's (or asked). The library's artists asked if they aren't in hand. The same on the iPhone and the Mac at the
/// readable width, in the text styles - none of the phone's own pieces.
struct SimilarArtistsScreen: View {
    let route: ArtistRoute

    @Environment(ServerModel.self) private var server
    @Environment(ArtistsModel.self) private var artists
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The page's own state, used only with no artist page showing for them.
    @State private var own: ArtistPageModel
    /// The page has waited `SearchPacing.ownedWaitMs` since the library's artists were asked for (or there was nothing
    /// to ask): the tiles are drawn with what it has.
    @State private var waited = false
    /// A grid column's least width, growing with the text - never past the page (`page`, SimilarArtists.side).
    @ScaledMetric(relativeTo: .footnote) private var scaled = SimilarArtistsDrawn.side
    /// (A2's review) The grid's width, measured: at AX5 a column of the scaled side (some 379) would run off both edges.
    @State private var page: CGFloat?

    init(route: ArtistRoute) {
        self.route = route
        _own = State(initialValue: ArtistPageModel(route: route))
    }

    /// Who and which artist - the page's own, apart from the artist page's.
    private var taskKey: String { "\(server.person)|\(route.id)|similar-artists" }

    /// The artist page showing for them, else this page's own.
    private var model: ArtistPageModel { artists.page(route.id) ?? own }

    /// No artist page showing for them: the page asks for itself (and says its own troubles).
    private var alone: Bool { artists.page(route.id) == nil }

    private var mbid: String? {
        model.mbid(index: search.ownedIndex, version: search.ownedVersion) ?? artists.chosen[route.id]?.mbid
    }

    /// (Its own only) Last.fm asked once the artist's answer is in hand, for who they are.
    private var ownAsk: LastfmPage.Ask? {
        guard let answer = own.answer else { return nil }
        return LastfmPage.Ask(mbid: mbid, name: answer.name)
    }

    private var ownLastfmKey: String {
        "\(taskKey)|\(ownAsk?.key ?? "")|\(own.answer != nil)|\(server.access.lastfm)|\(reachability.online)"
    }

    /// (Its own only) Last.fm asked for who they are - a failure the session keeps asked again at once: this page has
    /// nothing else to show.
    private func askLastfm(again: Bool = false) {
        guard alone else { return }
        own.askLastfm(page: taskKey, ask: ownAsk, inHand: own.answer != nil, state: server.access.lastfm,
                      client: server.client, online: reachability.online, artists: artists, again: again,
                      retryFailed: true)
    }

    /// Try again, the artist's: asked again.
    private func reload() {
        let key = taskKey
        Task {
            await own.load(key: key, client: server.client, online: reachability.online, artists: artists, again: true)
        }
    }

    var body: some View {
        let model = self.model
        let online = reachability.online
        let listed = LastfmPage.state(me: server.access.lastfm, answer: model.lastfm) == .on
            && SimilarArtists.listed(model.lastfm)
        let tiles = listed ? SimilarArtists.tiles(model.lastfm?.similar, library: artists.similarLibrary(),
                                                  page: route.id, mbid: mbid) : []
        let drawn = SimilarArtists.drawsTiles(listKnown: artists.listKnown, waited: waited)
        let lines = typeSize.isAccessibilitySize ? 3 : 1
        let side = CGFloat(SimilarArtists.side(Double(scaled), page: page.map(Double.init)))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if drawn && !tiles.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: side), spacing: SimilarArtistsDrawn.gap,
                                                 alignment: .top)],
                              alignment: .leading, spacing: 18) {
                        ForEach(tiles) { (tile: SimilarArtists.Tile) in
                            SimilarArtistTile(tile: tile, side: side, lines: lines) {
                                navigation.open(tile.route)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 12)
                    LastfmCredit(lastfmPage: model.lastfm?.url, font: Typeface.footnote, above: 16)
                } else if model.gone {
                    ErrorNote(text: ErrorWords.artistGone)
                        .padding(.top, 8)
                } else if alone, let failure = model.failure, model.answer == nil, online {
                    // the artist didn't come: as their page says it, with its Try again
                    VStack(alignment: .leading, spacing: 10) {
                        ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)
                        Button(LibraryWords.tryAgain) { reload() }
                            .buttonStyle(DWButtonStyle())
                    }
                    .padding(.top, 8)
                } else if alone, let failure = model.lastfmFailure, model.lastfm == nil, online {
                    // Last.fm's answer didn't come: said the same way, and asked again
                    VStack(alignment: .leading, spacing: 10) {
                        ErrorNote(failure, retry: true)
                        Button(LibraryWords.tryAgain) { askLastfm(again: true) }
                            .buttonStyle(DWButtonStyle())
                    }
                    .padding(.top, 8)
                } else if !drawn || (model.lastfm == nil && online) {
                    // its own page, Last.fm's answer (or the library's artists) not in yet
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .onGeometryChange(for: CGFloat.self) { (grid: GeometryProxy) -> CGFloat in
                grid.size.width
            } action: { (width: CGFloat) -> Void in
                page = width
            }
            .padding(.horizontal, SimilarArtistsDrawn.edge)
            .padding(.bottom, 24)
        }
        .navigationTitle(LastfmWords.similarArtists)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: taskKey) {
            guard alone else { return }
            search.refreshOwned()
            await own.load(key: taskKey, client: server.client, online: reachability.online, artists: artists)
        }
        .task(id: ownLastfmKey) { askLastfm() }
        // the library's artists, to meet the tiles with - asked if they aren't in hand, the tiles waiting a moment for
        // them from the ask (as the artist page's do); with nothing to ask (in hand, or deadwax out of reach) no wait
        .task(id: "\(taskKey)|\(online)") {
            guard online, artists.list == nil else {
                waited = true
                return
            }
            let artists = self.artists
            async let asked: Void = artists.ask()
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.ownedWaitMs) * 1_000_000)
            if !Task.isCancelled { waited = true }
            await asked
        }
    }
}
