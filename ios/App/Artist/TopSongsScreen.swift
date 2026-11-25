import DeadwaxCore
import SwiftUI

/// The Top Songs page (Last.fm, slice A1 - deadwax-plans/lastfm.md 3.2; notes/ios.md "Last.fm, slice A1"): See All's,
/// from an artist's page - every one of their top songs (Last.fm's ten at most) as their page draws them (TopSongRow),
/// with "From Last.fm" under them. Its rows are the very rows of the artist page showing under it (ArtistsModel.page):
/// nothing is asked again, a song's album asked for is that page's opener. With no such page (it was let go), the page
/// is its own: the artist and their albums' songs asked as their page asks them, Last.fm's answer the session's (or
/// asked). The same on the iPhone and the Mac at the readable width.
struct TopSongsScreen: View {
    let route: ArtistRoute

    @Environment(ServerModel.self) private var server
    @Environment(ArtistsModel.self) private var artists
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    /// The page's own state, used only with no artist page showing for them.
    @State private var own: ArtistPageModel

    init(route: ArtistRoute) {
        self.route = route
        _own = State(initialValue: ArtistPageModel(route: route))
    }

    /// Who and which artist - the page's own, apart from the artist page's.
    private var taskKey: String { "\(server.person)|\(route.id)|top-songs" }

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

    /// Try again, the artist's: asked again, with the albums whose songs didn't come (as their page's Try again).
    private func reload() {
        let key = taskKey
        Task {
            await own.load(key: key, client: server.client, online: reachability.online, artists: artists, again: true)
            if own.asks.someMissing { own.again(client: server.client) }
        }
    }

    var body: some View {
        let model = self.model
        let online = reachability.online
        let mine = ArtistPage.rows(model.albums(online: online, downloads: downloads))
        let shown = LastfmPage.shown(state: LastfmPage.state(me: server.access.lastfm, answer: model.lastfm),
                                     online: online, answer: model.lastfm, seesDetail: false)
        let rows = shown.topSongs ? model.topRows(mine, online: online, downloads: downloads) : []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    if model.gone {
                        ErrorNote(text: ErrorWords.artistGone)
                            .padding(.top, 8)
                    } else if alone, let failure = model.failure, model.answer == nil, online {
                        // the artist didn't come: as their page says it, with its Try again
                        VStack(alignment: .leading, spacing: 10) {
                            ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)
                            Button(LibraryWords.tryAgain) { reload() }
                        }
                        .padding(.top, 8)
                    } else if alone, let failure = model.lastfmFailure, model.lastfm == nil, online {
                        // Last.fm's answer didn't come: said the same way, and asked again
                        VStack(alignment: .leading, spacing: 10) {
                            ErrorNote(failure, retry: true)
                            Button(LibraryWords.tryAgain) { askLastfm(again: true) }
                        }
                        .padding(.top, 8)
                    } else if shown.heroLine && model.lastfm == nil {
                        // its own page, Last.fm's answer not in yet
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                } else {
                    ForEach(rows) { (row: TopSongs.Row) in
                        TopSongRow(row: row, all: rows, name: model.name, mbid: mbid, opener: model.opener)
                    }
                    LastfmCredit(lastfmPage: model.lastfm?.url)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(LastfmWords.topSongs)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: taskKey) {
            guard alone else { return }
            search.refreshOwned()
            await own.load(key: taskKey, client: server.client, online: reachability.online, artists: artists)
        }
        .task(id: ownLastfmKey) { askLastfm() }
        // a row asking for its album lets go once the page stops showing: it opens only where it was tapped
        .onChange(of: navigation.tab) { _, _ in model.opener.standDown() }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            if shown { model.opener.standDown() }
        }
        .onDisappear { model.opener.standDown() }
    }
}
