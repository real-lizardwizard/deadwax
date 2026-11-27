import DeadwaxCore
import SwiftUI

/// An artist's page (Phase 4, slice 4 - phase4-library.md 2.6; the web's ArtistPage.tsx without its MusicBrainz parts,
/// question 4: no description, facts, pins or managing - and, until 15 Nov, no discography). Top to bottom: their picture
/// (round, as their row's) and their name; Play and Shuffle, with the line under them (ArtistPage.playsLine) and Try again
/// when some albums' songs didn't come; Albums - their albums in the collection, newest first (ArtistPage.rows), each its
/// cover, title and "1994 · in your library" with the tick for yours (or every one without a library of your own), and
/// their albums you don't have among them (below). A row opens its album; nothing here plays but Play and Shuffle.
///
/// Play plays every album of theirs in the page's order, each at its album level, from the first song; Shuffle every song
/// of them once, at the songs level (ArtistPlay.plan) - through PlayerModel.play(artist:) in the tap, with the songs in
/// hand: the page asks for every album's songs as it opens, 4 at a time (ArtistPageModel, Core's ArtistAlbumAsks), and
/// Play and Shuffle are live once every album has answered or failed.
///
/// While deadwax can't be reached (3.1's rule): nothing is asked; their albums are the answer in hand, or the albums on
/// this phone naming them; an album with nothing here is dimmed and opens nothing; Play and Shuffle take only the songs
/// on this phone (ArtistOffline.playable), and the line says only downloaded albums play.
///
/// THEIR ALBUMS YOU DON'T HAVE (15 Nov - James: "also on the artists page I'd like to also see albums I don't have yet";
/// the web's ArtistPage.tsx rows, Core's ArtistJoin): once who they are on MusicBrainz is known (Navidrome's id for them,
/// else what the library's folders of their albums say), their discography is asked - Studio only, as a MusicBrainz
/// artist's page asks it, with its toggle at the heading's end - and each of its albums none of yours claims comes in
/// among yours, in the web's order, as that page draws it: its cover through deadwax's relay, its title and "2008 · not in
/// your library", opening the album you don't have (or yours through the id bridge, for one only the library's folders
/// hold). Your albums never wait for it and never move among themselves; its rows wait only for `/library/owned`, a
/// moment at most. Under them: "Loading their albums…", its trouble said once with Try again, the cut at 500. With no id
/// to be had, or offline, the page is your albums alone and says nothing of it.
///
/// THE ARTIST TOOLS (Phase 8, slice 5 - phase8-managing.md 4; the web's ArtistPage.tsx managing): the bar's ••• holds,
/// by the person's permissions (Managing.artistManaging) and the web's own conditions, Artist images… (Edit albums;
/// once the library files their albums under a name), Which artist is this? (Edit albums; while nothing says who they
/// are on MusicBrainz, or it was chosen here) and Move albums to {name}… (Look after the library; a name the library
/// files them under isn't their name now) - each a sheet, each needing deadwax, so the ••• is there only while it is in
/// reach. They act on the LIBRARY'S names for the artist (ArtistManage.libraryNames over `/library/owned`), whose
/// folders deadwax is asked about (ArtistToolsModel) - only for someone the ••• has something for. Who they are is
/// chosen for the visit (ArtistsModel.choose), the page saying so under their name; a save draws the square from their
/// folder; a move asks the page again, now and once Navidrome has scanned.
///
/// LAST.FM (slice A1 - deadwax-plans/lastfm.md 3.1-3.3; notes/ios.md "Last.fm, slice A1"; James, 24 Nov: "can we add in
/// a list of the 10 most popular songs for the artist page?"): with deadwax's Last.fm on, "2.3M listeners" under their
/// name - its line kept from the first frame, so Play never moves as it fills - and Top Songs (TopSongsSection) between
/// Play and the albums: its first five, See All for the ten, "From Last.fm" under them. Asked once their own answer is in
/// hand (ArtistPageModel.askLastfm), everything below Play waits for it `LastfmPage.waitMs` at most, with no spinner; an
/// answer later than that puts Top Songs after the albums for the page's life (LastfmPage.placeOf); the session's answer
/// draws at once, in place. With Last.fm off or refused nothing of it is drawn - and for whoever runs deadwax the page's
/// foot says so, with Server settings to open its Connections.
///
/// LAST.FM (slice A2 - lastfm.md 3.3, 3.4; notes/ios.md "Last.fm, slice A2"): with Last.fm on, the Albums heading's
/// order menu - "Newest first" or "Most played", chosen per device (ArtistsModel.albumOrder), Most played offered only
/// with albums by plays in the answer - its rows in Most played order each line led by "4.1M plays · ", judged once for
/// the visit as the albums are first drawn (Core's LastfmVisit: an answer later than that leaves them newest first, a
/// pull takes the next); and Similar Artists under the albums (SimilarArtistsSection): Last.fm's similar artists met with
/// the library's (asked if they aren't in hand), round tiles in a row, See All past four. The Mac's page draws both from
/// the desk.
///
/// ABOUT (Last.fm, slice A4 - lastfm.md 3.9; notes/ios.md "Last.fm, slice A4"): at the page's foot, after Similar
/// Artists, "About" - deadwax's description of them (Last.fm's words first, else Wikipedia's, else Navidrome's), with
/// Wikidata's subtitle, four lines and More (AboutSection; on the Mac the desk's `about`). Asked by their MusicBrainz id
/// and Navidrome's once their answer is in hand and who they are is settled (`aboutQuestion`); absent with no words.
///
/// THE REDESIGN (slice R6 - notes/ios.md "The redesign, slice R6: an artist"; iArtist.dc.html, Artist.dc.html): on the
/// phone flat, as iArtist draws it - the top as R1c drew it (the round picture beside the name) with who they are on
/// MusicBrainz under the name ("Group · Sydney · since 1973", MBArtistPage.factsLine) and the listeners; Play and
/// Shuffle, the album page's pair (AlbumPlayPair); Top Songs where A1 puts it; the strip (PhoneStrip): Studio only and
/// Everything once their discography is asked, then the managers' Artist images… and Move albums… - each by its
/// permission, as the ••• offered them (ArtistManage.offered); the Albums heading with its count ("16 · 6 yours",
/// ArtistPageFacts.heading), and the rows on their hairlines, Get on an album nobody holds. The bar's ••• keeps Which
/// artist is this?. On the Mac (`desk`, from MacArtist.page(for:)), MacArtistPage draws the artist in the ScrollView's
/// place, handed this page's model, its rows and its actions (ArtistDesk): every ask, wait and letting go stays this
/// page's - the Mac draws, nothing more. On the iPhone there is no desk (`init(route:)`).
struct ArtistView<Desk: View>: View {
    let route: ArtistRoute
    /// (R6) The Mac's artist page, drawn in the ScrollView's place - none on the iPhone.
    private let desk: ((ArtistDesk) -> Desk)?

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(ArtistsModel.self) private var artists
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: ArtistPageModel
    /// The hero's name has scrolled away: the bar shows it.
    @State private var nameInBar = false
    /// The page has waited `SearchPacing.ownedWaitMs` for `/library/owned`: MusicBrainz's rows are drawn with what it has.
    @State private var ownedWaited = false
    /// (A2's review) Similar Artists' tiles have waited `SearchPacing.ownedWaitMs` since the library's artists were asked
    /// for (or there was nothing to ask): drawn with what is in hand. Its own wait, begun with the ask - R6's
    /// `ownedWaited` begins as the page opens, long before Similar Artists is listed.
    @State private var similarWaited = false
    /// (Phase 8, slice 5) The artist tools: the library's names for them and deadwax's word on each, and the sheet open.
    @State private var tools = ArtistToolsModel()
    @State private var toolSheet: ArtistToolSheet?
    /// One more each time the library's word on their names is wanted again (a save, a move, a pull).
    @State private var summaryAsks = 0
    /// (R6's review) The page whose top holds the room of the line under the name (ArtistPageFacts.holdsFacts) - held
    /// for the page's life once it is, so the line landing late, or not at all, moves nothing under it.
    @State private var factsRoomFor: String?

    /// (R6) The Mac's: the artist drawn by `desk` (MacArtistPage).
    init(route: ArtistRoute, desk: @escaping (ArtistDesk) -> Desk) {
        self.route = route
        self.desk = desk
        _model = State(initialValue: ArtistPageModel(route: route))
    }

    /// Who and which artist: a new person asks everything again.
    private var taskKey: String { "\(server.person)|\(route.id)" }

    /// (Speed A, fix 2) The stamp the albums' songs the page asks are kept under for the album pages now (who is signed
    /// in and every write deadwax was told of - KeptAlbumAnswers.stamp). Not `kept`: the body has a `kept` of its own
    /// (the Last.fm answer), which its tasks and pull would read in its place.
    private var keptStamp: KeptAnswers<Album>.Stamp { KeptAlbumAnswers.stamp(server: server, navigation: navigation) }

    /// Who they are on MusicBrainz, as the artist's answer and the library's folders now say (ArtistJoin.mbid).
    private var said: String? { model.mbid(index: search.ownedIndex, version: search.ownedVersion) }
    /// ...or, with nothing saying, who was chosen with Which artist is this? for this visit (the web's `said ?? chosen`).
    private var mbid: String? { said ?? artists.chosen[route.id]?.mbid }
    /// Who they are was chosen here, and nothing else says (the web's `byChoice`).
    private var byChoice: Bool { said == nil && artists.chosen[route.id] != nil }

    /// (Last.fm) Who Last.fm is asked about - their MusicBrainz id, when known, and their name - once their answer is in
    /// hand.
    private var lastfmAsk: LastfmPage.Ask? {
        guard let answer = model.answer else { return nil }
        return LastfmPage.Ask(mbid: mbid, name: answer.name)
    }

    /// (Last.fm) Last.fm asked (or the page told it won't be) for the page, who they are, whether deadwax says Last.fm is
    /// on, and whether it can be reached - so only the newest ask's answer draws.
    private var lastfmKey: String {
        "\(taskKey)|\(lastfmAsk?.key ?? "")|\(model.answer != nil)|\(server.access.lastfm)|\(reachability.online)"
    }

    /// (Last.fm) Last.fm's answer asked for now - or, with `again`, asked again (a pull).
    private func askLastfm(again: Bool = false) {
        model.askLastfm(page: taskKey, ask: lastfmAsk, inHand: model.answer != nil, state: server.access.lastfm,
                        client: server.client, online: reachability.online, artists: artists, again: again)
    }

    /// (Last.fm, slice A4) About's question for the page now (AboutBlock.artist): once their answer is in hand, and who
    /// they are on MusicBrainz is settled - the library's folders answered or waited for, and with an id, MusicBrainz's
    /// facts in (the lookup deadwax's Wikipedia side makes too) - by that id and Navidrome's.
    private var aboutQuestion: AboutBlock.Question {
        AboutBlock.artist(answered: model.answer != nil, gone: model.gone, navidromeId: route.id, mbid: mbid,
                          indexKnown: search.ownedIndex != nil, waited: ownedWaited,
                          factsSettled: model.factsSettled(for: mbid))
    }

    /// (A4) About asked for the page and the question, and whether deadwax can be reached - so only the newest draws.
    private var aboutKey: String { "\(taskKey)|\(aboutQuestion.token)|\(reachability.online)" }

    /// MusicBrainz's albums of theirs to draw: online, once `/library/owned` has answered or been waited for, the answer
    /// for the question asked now - or, while Studio only is asked again, the last one, kept on screen.
    private func theirGroups(online: Bool) -> [ReleaseGroup]? {
        guard ArtistJoin.drawsTheirs(online: online, indexKnown: search.ownedIndex != nil, waited: ownedWaited),
              let discography = model.discography else { return nil }
        return (discography.shown ?? discography.albums)?.groups
    }

    /// (R6) Whether the page is the Mac's desk (MacArtistPage) - its toolbar then the desk's, the phone's ••• not drawn.
    private var onDesk: Bool { desk != nil && Platform.mac }

    var body: some View {
        let online = reachability.online
        let personal = server.access.hasLibrary
        let albums = self.albums(online: online)
        let mine = ArtistPage.rows(albums)
        let rows = model.rows(albums: albums, groups: theirGroups(online: online), index: search.ownedIndex,
                              version: search.ownedVersion)
        let managing = self.managing()
        let offered = self.offered(managing, online: online)
        // (Last.fm) what of it the page draws, and whether what lies below Play waits for it
        let lastfm = LastfmPage.shown(state: LastfmPage.state(me: server.access.lastfm, answer: model.lastfm),
                                      online: online, answer: model.lastfm, seesDetail: server.access.seesDetail,
                                      reserved: model.lineKept(page: taskKey))
        let kept = artists.keptLastfm(route.id)
        let arrival = model.arrival(page: taskKey, state: server.access.lastfm, online: online, kept: kept)
        let factsAsked = ArtistPageFacts.holdsFacts(mbid: mbid, online: online, facts: model.facts)
        // (Last.fm, slice A2) the albums in the order the menu has drawn, its menu, and Similar Artists
        let order = albumOrder(lastfm, kept: kept)
        let shown = model.albumsShown(rows, chosen: lastfmOn ? artists.albumOrder : .newest, page: taskKey, kept: kept,
                                      albums: albums)
        let choice = AlbumOrderChoice(shown: shown.order, offered: order.offered, room: order.room,
                                      choose: { (chosen: AlbumOrder) -> Void in chooseOrder(chosen) })
        let similar = similarShown()
        Group {
            if let desk, Platform.mac {
                desk(artistDesk(rows: rows, shown: shown, choice: choice, similar: similar, albums: albums, mine: mine,
                                managing: managing, offered: offered, lastfm: lastfm, arrival: arrival, online: online,
                                personal: personal))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        phoneHero(managing, lastfm: lastfm, factsRoom: factsAsked || factsRoomFor == taskKey)
                            .onAppear { nameInBar = false }
                            .onDisappear { nameInBar = true }
                        if model.answer == nil && !online && mine.isEmpty {
                            // nothing of theirs in hand, and deadwax out of reach: a state, not a failure - nothing
                            // was asked
                            ShelfNote(DownloadWords.onlyDownloadedPlay)
                        } else if model.gone {
                            ErrorNote(text: ErrorWords.artistGone)
                                .padding(.top, 8)
                        } else if let failure = model.failure, model.answer == nil, online {
                            VStack(alignment: .leading, spacing: 10) {
                                ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)
                                Button(LibraryWords.tryAgain) { reload() }
                                    .buttonStyle(DWButtonStyle())
                            }
                            .padding(.top, 8)
                        } else {
                            plays(rows: mine, online: online, personal: personal)
                            if !arrival.holding {
                                let top = lastfm.topSongs ? topRows(mine, online: online) : []
                                if !top.isEmpty && arrival.place == .inPlace { topSongs(top) }
                                strip(managing, offered, online: online)
                                albumsList(shown, choice: choice, albums: albums, online: online, personal: personal)
                                // an answer that came once the albums were drawn: after them, for the page's life
                                if !top.isEmpty && arrival.place != .inPlace { topSongs(top) }
                                // (A2) Similar Artists, under the albums (and a late Top Songs)
                                if similar.shows { similarArtists(similar) }
                            }
                            // (A4) About, at the page's foot - once what lies above it is drawn
                            if !arrival.holding, let about = model.about.drawn(for: taskKey) { AboutSection(drawn: about) }
                            if let foot = lastfm.foot { lastfmFoot(foot) }
                        }
                    }
                    .padding(.horizontal, ArtistDrawn.edge)
                    .padding(.bottom, 24)
                }
            }
        }
        // (R6's review) the facts line's room, once asked, kept for the page's life
        .onChange(of: factsAsked, initial: true) { (_: Bool, asked: Bool) -> Void in
            if asked && factsRoomFor != taskKey { factsRoomFor = taskKey }
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.name)
                    .font(Typeface.headline)
                    .lineLimit(1)
                    .opacity(nameInBar ? 1 : 0)
                    .accessibilityHidden(!nameInBar)
            }
            // (R6) the phone's •••: Which artist is this? - Artist images… and Move albums… are the strip's; on the Mac
            // all three are MacArtistPage's toolbar's
            if offered.who && !onDesk {
                ToolbarItem(placement: .topBarTrailing) {
                    toolsMenu(offered)
                }
            }
        }
        // (Phase 8, slice 5) the library's word on each of their names, for the artist tools - for their names as they
        // are now, asked again after a write or a pull
        .task(id: "\(taskKey)|\(ArtistToolsModel.key(managing.names))|\(online)|\(summaryAsks)") {
            guard managing.may.any else { return }
            await tools.summarize(managing.names, client: server.client, online: online, again: summaryAsks > 0)
        }
        .appSheet(item: $toolSheet) { (open: ArtistToolSheet) in
            toolSheetView(open, managing)
                .macSheet()
        }
        .task(id: taskKey) {
            // which of MusicBrainz's albums are yours is the library's folders' word: (Speed A, fix 5) asked as the page
            // opens only when it isn't in hand or a write was told of since a page last asked - as the album page asks;
            // a pull asks again
            if reachability.online, artists.asksOwned(inHand: search.ownedIndex != nil, writes: keptStamp.writes) {
                search.refreshOwned()
            }
            await model.load(key: taskKey, client: server.client, online: reachability.online, artists: artists,
                             kept: keptStamp)
        }
        .task(id: "\(taskKey)|\(mbid ?? "")") {
            // their albums on MusicBrainz, once who they are there is known - or let go when it no longer is
            model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online)
            // (Phase 8, slice 5) and who they are there - their name now, for the artist tools - and (R6) for everyone,
            // the line under their name
            await model.theirFacts(client: server.client, online: reachability.online)
        }
        .task {
            // MusicBrainz's rows wait a moment for /library/owned, once a page's life
            guard !ownedWaited else { return }
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.ownedWaitMs) * 1_000_000)
            if !Task.isCancelled { ownedWaited = true }
        }
        .task { await downloads.followProgress() }
        // (Last.fm) asked once their answer is in hand, for who they are now; the page shown is the one its Top Songs
        // page reads
        .task(id: lastfmKey) { askLastfm() }
        // (Last.fm, slice A4) About, asked for the page and who they are now - the session's answer drawn at once
        .task(id: aboutKey) {
            model.about.ask(page: taskKey, person: server.person, question: aboutQuestion, client: server.client,
                            online: reachability.online)
        }
        // (Last.fm, slice A2) the library's artists, to meet Similar Artists with - asked if they aren't in hand, the
        // tiles' own wait begun with the ask (A2's review); with nothing to ask (in hand, or deadwax out of reach) none
        .task(id: "\(taskKey)|\(similarListed)|\(reachability.online)") {
            guard similarListed else { return }
            guard reachability.online, artists.list == nil else {
                similarWaited = true
                return
            }
            let artists = self.artists
            async let asked: Void = artists.ask()
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.ownedWaitMs) * 1_000_000)
            if !Task.isCancelled { similarWaited = true }
            await asked
        }
        .onAppear { artists.showing(model) }
        .pullToRefresh {
            // deadwax out of reach: a pull asks whether it is back (the banner says why nothing changes)
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            // (Speed A, fix 5) the library's word on which albums are yours asked again too
            search.refreshOwned()
            await model.load(key: taskKey, client: server.client, online: true, artists: artists, again: true,
                             kept: keptStamp)
            if model.asks.someMissing { model.again(client: server.client) }
            model.theirAlbums(mbid: mbid, client: server.client, online: true, retry: true)
            summaryAsks += 1
            askLastfm(again: true)
        }
        .onChange(of: reachability.online) { _, online in
            // back: what the page couldn't ask is asked of deadwax now - the songs that didn't come with it
            guard online else { return }
            reload()
        }
        // a row of theirs asking the id bridge lets go once the page stops showing: it opens only where it was tapped
        .onChange(of: navigation.tab) { _, _ in model.discography?.standDown() }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            if shown { model.discography?.standDown() }
        }
        .onDisappear { model.discography?.standDown() }
        // (Last.fm) and a top song's row asking for its album, the same way
        .onChange(of: navigation.tab) { _, _ in model.opener.standDown() }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            if shown { model.opener.standDown() }
        }
        .onDisappear { model.opener.standDown() }
    }

    /// The artist asked again (Try again, deadwax back) - and the albums whose songs didn't come, and their albums on
    /// MusicBrainz after a failure.
    private func reload() {
        let key = taskKey
        Task {
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists,
                             kept: keptStamp)
            if model.asks.someMissing { model.again(client: server.client) }
            model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online, retry: true)
            await model.theirFacts(client: server.client, online: reachability.online)
        }
    }

    /// Their albums: the answer's - or, while deadwax can't be reached, the answer in hand, else the albums on this phone
    /// naming them (ArtistOffline.albums).
    private func albums(online: Bool) -> [Album] {
        model.albums(online: online, downloads: downloads)
    }

    // MARK: the hero

    /// (R1c - notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)"; iArtist) The phone's top, with no
    /// band behind it: the round picture, 84, beside the name (28, bold) and its lines under it - (R6) who they are on
    /// MusicBrainz ("Group · Sydney · since 1973"), their listeners, and who they are chosen here - 14 between; at the
    /// accessibility sizes the picture over the name, so the name keeps its room. No shadow under the picture: it sits
    /// on the page. The picture: (Phase 8, slice 5) the square from their folder once Artist images wrote to it while
    /// the app runs, or where Navidrome has none (ArtistHeroPicture). The Mac's top is MacArtistPage's band. (R6's
    /// review) The facts line's room is held once they are asked (`factsRoom`), blank until they come - so a two-line
    /// name, or the accessibility sizes, never see Play pushed down as the line lands.
    private func phoneHero(_ managing: ArtistManaged, lastfm: LastfmPage.Shown, factsRoom: Bool) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ArtistDrawn.phoneHeroGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ArtistDrawn.phoneHeroGap))
        let facts = MBArtistPage.factsLine(model.facts)
        return layout {
            ArtistHeroPicture(managing: managing, coverArt: model.coverArt, side: ArtistDrawn.phonePictureSide,
                              pixels: CoverSize.tile)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(Typeface.title.bold())
                    .tracking(ArtistDrawn.phoneNameTracking)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                // (R6) who they are, once MusicBrainz says - iArtist's line under the name; (R6's review) its room held
                // from the moment they are asked, blank until (and unless) they come
                if factsRoom || !facts.isEmpty {
                    Text(facts.isEmpty ? " " : facts)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(facts.isEmpty)
                }
                // (Last.fm) "2.3M listeners": its line there from the first frame whenever it can be drawn, blank until
                // (and unless) the answer says - so nothing under it moves
                if lastfm.heroLine {
                    Text(lastfm.listeners ?? " ")
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .accessibilityHidden(lastfm.listeners == nil)
                }
                if byChoice {
                    Text(ArtistManageWords.chosen)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, ArtistDrawn.phoneHeroAbove)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Last.fm (slice A1)

    /// Top Songs' rows, met with the page's albums' songs (ArtistPageModel.topRows).
    private func topRows(_ mine: [ArtistPage.Row], online: Bool) -> [TopSongs.Row] {
        model.topRows(mine, online: online, downloads: downloads)
    }

    /// Top Songs: the heading with See All, the first five, and the credit.
    private func topSongs(_ rows: [TopSongs.Row]) -> some View {
        TopSongsSection(rows: rows, route: route, name: model.name, mbid: mbid, credit: model.lastfm?.url,
                        opener: model.opener)
    }

    // MARK: Last.fm (slice A2)

    /// (A2) Last.fm is on for the page (LastfmPage.state - /me's word, or the answer's that it isn't enabled): the
    /// albums' order and Similar Artists only then.
    private var lastfmOn: Bool { LastfmPage.state(me: server.access.lastfm, answer: model.lastfm) == .on }

    /// (A2) Whether the menu offers Most played - read as the order drawn is (ArtistPageModel.albumsOffered, A2's
    /// review: the visit's albums, or the answer in hand's) - and, with it not, whether its room is held: the hero's
    /// line drawn, so an answer may yet bring it.
    private func albumOrder(_ lastfm: LastfmPage.Shown, kept: LastfmPage.Kept.Entry?) -> (offered: Bool, room: Bool) {
        let offered = lastfmOn && model.albumsOffered(page: taskKey, kept: kept)
        return (offered, !offered && lastfm.heroLine)
    }

    /// (A2) A choice in the menu, in the tap: kept per device (ArtistsModel.albumOrder) - Most played ordering the rows
    /// by the answer in hand at once (ArtistPageModel.choseMostPlayed).
    private func chooseOrder(_ order: AlbumOrder) {
        artists.albumOrder = order
        if order == .played { model.choseMostPlayed() }
    }

    /// (A2) Similar Artists is Last.fm's to list: on, with similar artists in its answer.
    private var similarListed: Bool { lastfmOn && SimilarArtists.listed(model.lastfm) }

    /// (A2) Similar Artists as drawn: Core's tiles, met with the library's artists (asked if they aren't in hand) - drawn
    /// once those have answered or failed, or the page has waited for them since they were asked (`similarWaited`).
    private func similarShown() -> SimilarShown {
        guard similarListed else { return .none }
        return SimilarShown(listed: true,
                            drawn: SimilarArtists.drawsTiles(listKnown: artists.listKnown, waited: similarWaited),
                            tiles: SimilarArtists.tiles(model.lastfm?.similar, library: artists.similarLibrary(),
                                                        page: route.id, mbid: mbid))
    }

    /// (A2) The phone's Similar Artists: the heading with See All, the row of tiles, the credit.
    private func similarArtists(_ shown: SimilarShown) -> some View {
        SimilarArtistsSection(shown: shown, route: route, credit: model.lastfm?.url)
    }

    /// The foot line, for whoever runs deadwax while Last.fm is off or refused - and Server settings, to its Connections,
    /// where LASTFM_API_KEY is.
    private func lastfmFoot(_ words: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(words)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
            Button(LastfmWords.serverSettings) {
                navigation.open(.serverSettingsGroup(ServerSettings.connectionsGroup))
            }
            .buttonStyle(DWButtonStyle(size: .small))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
    }

    // MARK: the artist tools (Phase 8, slice 5)

    /// What the artist tools need, as the page is now: the person's permissions, the library's names for them, the folder
    /// Artist images writes to and why none can be, the names Move albums moves and their name now.
    private func managing() -> ArtistManaged {
        let may = Managing.artistManaging(server.access.permissions)
        guard may.any else { return ArtistManaged(may: may) }
        let current = model.facts?.name
        let who = ArtistManage.Who(mbid: mbid, name: model.answer?.name ?? current ?? route.preview?.name,
                                   releases: (model.answer?.album ?? []).compactMap(\.musicBrainzId))
        let names = tools.names(search.ownedIndex, version: search.ownedVersion, who: who)
        let said = tools.said(for: names)
        let folder = ArtistManage.imagesFolder(names, current: current, summaries: said)
        return ArtistManaged(may: may, names: names, known: tools.known(names), folder: folder,
                             folderSummary: tools.summary(folder.name, names: names),
                             moveNames: ArtistManage.namesToMove(names, current: current), current: current,
                             sizes: Dictionary(said.compactMap { (one: (name: String, said: ArtistManage.Said))
                                 -> (String, Double)? in
                                 if case .answered(let summary) = one.said { return (one.name, summary.totalSize) }
                                 return nil
                             }, uniquingKeysWith: { (first: Double, _: Double) -> Double in first }))
    }

    /// Which of the ••• items the page offers now (ArtistManage.offered: each by its permission, nothing while deadwax
    /// is out of reach or the artist is gone).
    private func offered(_ managing: ArtistManaged, online: Bool) -> ArtistManage.Offered {
        ArtistManage.offered(may: managing.may, online: online, gone: model.gone, names: managing.names,
                             answered: model.answer != nil, indexKnown: search.ownedIndex != nil, mbid: mbid,
                             byChoice: byChoice, current: managing.current, moveNames: managing.moveNames)
    }

    /// The bar's •••: (R6) Which artist is this?, opening its sheet - Artist images… and Move albums… are the strip's.
    private func toolsMenu(_ offered: ArtistManage.Offered) -> some View {
        Menu {
            if offered.who {
                Button {
                    toolSheet = ArtistToolSheet(kind: .who)
                } label: {
                    Label(ArtistManageWords.whoItem, systemImage: "person.crop.circle.badge.questionmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(ArtistManageWords.more)
    }

    /// The sheet the ••• opened, with the page as it is now - Move albums told when its names change under it.
    @ViewBuilder private func toolSheetView(_ open: ArtistToolSheet, _ managing: ArtistManaged) -> some View {
        switch open.kind {
        case .images:
            ArtistImagesSheet(request: ArtistImagesRequest(folder: managing.folder.name, reason: managing.folder.reason,
                                                           mbid: mbid, name: model.name)) {
                summaryAsks += 1
            }
        case .who:
            ArtistWhoSheet(name: model.name) { (match: MBArtistMatch) in
                artists.choose(route.id, match)
            }
        case .move:
            ArtistMoveSheet(ask: ArtistRefileFlow.Ask(names: managing.moveNames, mbid: mbid, current: managing.current),
                            name: model.name, sizes: managing.sizes) {
                moved()
            }
        }
    }

    /// Albums moved: the page asked again - what the session kept of it is of folders that have moved - now and once
    /// Navidrome has had time to scan (AlbumEdit.settleMs), never past a sign-out.
    private func moved() {
        artists.forget(route.id)
        search.refreshOwned()
        summaryAsks += 1
        let key = taskKey
        let session = navigation.session
        Task {
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists, again: true,
                             kept: keptStamp)
            try? await Task.sleep(for: .milliseconds(AlbumEdit.settleMs))
            guard navigation.session == session else { return }
            search.refreshOwned()
            summaryAsks += 1
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists, again: true,
                             kept: keptStamp)
        }
    }

    // MARK: Play and Shuffle

    /// Play and Shuffle - (R6) the album page's pair (AlbumPlayPair: Play the purple, Shuffle its words in the accent),
    /// side by side, one over the other at the largest text sizes - the line under them (held at its height whatever it
    /// says), and Try again when some albums' songs didn't come.
    @ViewBuilder
    private func plays(rows: [ArtistPage.Row], online: Bool, personal: Bool) -> some View {
        let order = ArtistPage.playOrder(rows)
        let offlineAlbums = online ? [] : offlinePlayable(order)
        let playable = online ? model.asks.playable : !offlineAlbums.isEmpty
        let line = playsLine(online: online, personal: personal)
        VStack(spacing: 0) {
            AlbumPlayPair(enabled: playable,
                          play: { play(shuffle: false, online: online, offlineAlbums: offlineAlbums) },
                          shuffle: { play(shuffle: true, online: online, offlineAlbums: offlineAlbums) })
            Text(line.isEmpty ? " " : line)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(line.isEmpty)
            if online, model.asks.someMissing {
                Button(LibraryWords.tryAgain) { model.again(client: server.client) }
                    .buttonStyle(DWButtonStyle(size: .small))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    /// The line under Play and Shuffle: what of their albums plays - offline, only what's downloaded.
    private func playsLine(online: Bool, personal: Bool) -> String {
        online ? model.asks.line(library: model.library, personal: personal) : DownloadWords.onlyDownloadedPlay
    }

    /// What plays offline: each album of theirs in the page's order, its kept answer's songs on this phone only.
    private func offlinePlayable(_ order: [String]) -> [Album] {
        let ready = model.asks.ready
        return ArtistOffline.playable(order, album: { (id: String) -> Album? in ready[id] ?? downloads.keptAlbum(id) },
                                      here: { (id: String) -> Bool in downloads.isHere(id) })
    }

    /// Play or Shuffle, in the tap: the albums in hand (or, offline, the songs on this phone) - nothing awaited first.
    private func play(shuffle: Bool, online: Bool, offlineAlbums: [Album]) {
        let albums = online ? model.asks.answers : offlineAlbums
        player.play(artist: albums, shuffle: shuffle)
    }

    /// (R6, the Mac's table) One album of yours played from its first song, in the tap: its songs in hand - offline,
    /// those on this Mac - at the album level, as its page's Play.
    private func playAlbum(_ id: String, online: Bool) {
        guard let playable = playableAlbum(id, online: online) else { return }
        player.play(songs: playable.songs, album: playable.album, at: 0)
    }

    /// The album's answer and its songs that play now: in hand online, on this device offline - nil with none.
    private func playableAlbum(_ id: String, online: Bool) -> (album: Album, songs: [Song])? {
        guard let album = model.asks.ready[id] ?? (online ? nil : downloads.keptAlbum(id)) else { return nil }
        let songs = (album.song ?? []).filter { (song: Song) -> Bool in online || downloads.isHere(song.id) }
        return songs.isEmpty ? nil : (album, songs)
    }

    // MARK: the strip (R6)

    /// (R6, iArtist's .chips) The strip over the albums (under Play, or under Top Songs where they are drawn): Studio
    /// only and Everything once their discography is asked (online, who they are known) - VoiceOver's tab bar, "Which
    /// of their albums" - then the managers' two - Artist images… once their folder is known, Move albums… (said in full
    /// to VoiceOver, "Move albums to Ye…") - each only as the ••• offered it (ArtistManage.offered: by its permission,
    /// deadwax in reach). Nothing at all with neither. A tab's tap asks the discography again
    /// (MBArtistModel.toggleStudio); a manager's opens its sheet.
    @ViewBuilder
    private func strip(_ managing: ArtistManaged, _ offered: ArtistManage.Offered, online: Bool) -> some View {
        let theirs = online ? model.discography : nil
        let tabs: [ArtistStripPart] = theirs == nil ? [] : [.studio, .everything]
        let pushes = ArtistStripPart.pushes(offered, known: managing.known)
        if !tabs.isEmpty || !pushes.isEmpty {
            PhoneStrip(options: tabs, words: { (part: ArtistStripPart) -> String in part.words },
                       shown: Binding(get: { theirs?.studioOnly == false ? .everything : .studio },
                                      set: { (part: ArtistStripPart) -> Void in chose(part, theirs: theirs) }),
                       spoken: ArtistPageFacts.Words.studioLabel, pushes: pushes,
                       said: { (part: ArtistStripPart) -> String in part.said(current: managing.current) })
                // the strip's own sides and hairline run to the screen's edges
                .padding(.horizontal, -ArtistDrawn.edge)
        }
    }

    /// A tap on the strip: the switch to the other of Studio only and Everything, or a manager's sheet - in the tap.
    private func chose(_ part: ArtistStripPart, theirs: MBArtistModel?) {
        switch part {
        case .studio, .everything:
            guard let theirs, theirs.studioOnly != (part == .studio) else { return }
            theirs.toggleStudio(client: server.client, online: reachability.online)
        case .images:
            toolSheet = ArtistToolSheet(kind: .images)
        case .move:
            toolSheet = ArtistToolSheet(kind: .move)
        }
    }

    // MARK: their albums

    /// Albums: the heading (R6: its count at its end, "16 · 6 yours"), your albums and theirs among them, and under them
    /// what MusicBrainz is doing. With neither, nothing: the line under Play and Shuffle says so ("None of their albums
    /// are here to play."). (R6) Each row iArtist's tall row on its hairline: yours with the chevron, theirs the library
    /// holds with the chevron too, theirs nobody holds with Get (ArtistPageFacts.offersGet) - which opens the album you
    /// don't have, as the row's tap does.
    @ViewBuilder
    private func albumsList(_ shown: AlbumPlays.Shown, choice: AlbumOrderChoice, albums: [Album], online: Bool,
                            personal: Bool) -> some View {
        // (A2) the rows in the order drawn - Most played's each line led by its plays, two lines at the accessibility
        // sizes, so the number they are sorted by is never the part cut (A2's review)
        let rows = shown.rows
        let accessibility = typeSize.isAccessibilitySize
        // offline the page is your albums alone: nothing of MusicBrainz's is drawn, said or asked
        let theirs = online ? model.discography : nil
        if !rows.isEmpty || theirs != nil {
            albumsHead(ArtistPageFacts.counts(rows, personal: personal), choice: choice)
            ForEach(rows) { (row: ArtistJoin.Row) in
                switch row {
                case .yours(let mine):
                    ArtistAlbumRow(row: mine, line: shown.line(row, ArtistPage.line(mine, personal: personal)),
                                   lines: shown.lines(row, accessibility: accessibility),
                                   dimmed: !online && !downloads.album(id: mine.albumId).hasSongsHere) {
                        open(mine, albums: albums)
                    }
                case .theirs(let other):
                    ArtistTheirRow(row: other, line: shown.line(row, MBArtistPage.line(other, personal: personal)),
                                   lines: shown.lines(row, accessibility: accessibility),
                                   get: ArtistPageFacts.offersGet(other, mayGet: server.access.can(.request)),
                                   busy: theirs?.opening == other.key) {
                        theirs?.open(other, client: server.client, online: reachability.online, navigation: navigation)
                    }
                }
            }
            if let theirs {
                theirFoot(theirs, holding: !ArtistJoin.drawsTheirs(online: online, indexKnown: search.ownedIndex != nil,
                                                                   waited: ownedWaited), rows: rows.count)
            }
        }
    }

    /// (R6, iArtist's .row.grp) "Albums", and their count at its end in the readout face - "16 · 6 yours" - laid out
    /// whatever it says, so the heading is one height before who they are is known and after; (A2) and at its end the
    /// order menu (AlbumOrderMenu), its room held while Last.fm's answer may yet offer Most played.
    private func albumsHead(_ counts: ArtistPageFacts.Counts, choice: AlbumOrderChoice) -> some View {
        ArtistSectionHead(words: ArtistWords.albumsHeading, count: ArtistPageFacts.heading(counts),
                          spoken: ArtistPageFacts.headingSpoken(counts)) {
            AlbumOrderMenu(choice: choice)
        }
        .padding(.top, 4)
    }

    /// Under the rows, MusicBrainz's word, once (ArtistTheirFoot) - its Try again asking their albums again.
    private func theirFoot(_ theirs: MBArtistModel, holding: Bool, rows: Int) -> some View {
        ArtistTheirFoot(theirs: theirs, holding: holding, rows: rows) {
            model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online, retry: true)
        }
    }

    /// A row's tap: its album's page, what the artist's answer knew of it drawn at once - the artist line their link.
    private func open(_ row: ArtistPage.Row, albums: [Album]) {
        var album = albums.first { (album: Album) -> Bool in album.id == row.albumId }.map { (album: Album) -> AlbumRoute in
            AlbumRoute(album)
        } ?? AlbumRoute(id: row.albumId, name: row.title, coverArt: row.coverArt)
        if album.artist == nil { album.artist = model.name }
        if album.artistId == nil { album.artistId = route.id }
        navigation.open(.album(album))
    }

    // MARK: the Mac (R6)

    /// What the Mac's page is handed (ArtistDesk): this page's model, its rows, what it draws of Last.fm, the managers'
    /// tools, and its own calls - so MacArtistPage asks and plays nothing this page doesn't.
    private func artistDesk(rows: [ArtistJoin.Row], shown: AlbumPlays.Shown, choice: AlbumOrderChoice,
                            similar: SimilarShown, albums: [Album], mine: [ArtistPage.Row], managing: ArtistManaged,
                            offered: ArtistManage.Offered, lastfm: LastfmPage.Shown, arrival: LastfmPage.Arrival,
                            online: Bool, personal: Bool) -> ArtistDesk {
        let order = ArtistPage.playOrder(mine)
        let offlineAlbums = online ? [] : offlinePlayable(order)
        let theirs = online ? model.discography : nil
        return ArtistDesk(
            model: model, route: route, mbid: mbid, byChoice: byChoice, online: online, personal: personal,
            mayGet: server.access.can(.request), rows: shown.rows, plays: shown.plays, albumOrder: choice,
            theirs: theirs, holding: !ArtistJoin.drawsTheirs(online: online, indexKnown: search.ownedIndex != nil,
                                                              waited: ownedWaited),
            lastfm: lastfm, arrival: arrival,
            top: lastfm.topSongs && !arrival.holding ? topRows(mine, online: online) : [], similar: similar,
            about: model.about.drawn(for: taskKey),
            mostPlayed: mostPlayed(mine, online: online),
            songs: albums.reduce(0) { (count: Int, album: Album) -> Int in count + max(album.songCount ?? 0, 0) },
            playable: online ? model.asks.playable : !offlineAlbums.isEmpty,
            line: playsLine(online: online, personal: personal), managing: managing, offered: offered,
            play: { play(shuffle: false, online: online, offlineAlbums: offlineAlbums) },
            shuffle: { play(shuffle: true, online: online, offlineAlbums: offlineAlbums) },
            playAlbum: { (id: String) -> Void in playAlbum(id, online: online) },
            playTop: { (rows: [TopSongs.Row], row: TopSongs.Row) -> Void in playTop(rows, from: row) },
            openTop: { (row: TopSongs.Row) -> Void in openTop(row) },
            playMost: { (rows: [MostPlayedSongs.Row], row: MostPlayedSongs.Row) -> Void in playMost(rows, from: row) },
            playsAlbum: { (id: String) -> Bool in playableAlbum(id, online: online) != nil },
            open: { (row: ArtistPage.Row) -> Void in open(row, albums: albums) },
            openTheirs: { (row: MBArtistPage.Row) -> Void in
                theirs?.open(row, client: server.client, online: reachability.online, navigation: navigation)
            },
            studio: { (studio: Bool) -> Void in chose(studio ? .studio : .everything, theirs: theirs) },
            tool: { (kind: ArtistToolSheet.Kind) -> Void in toolSheet = ArtistToolSheet(kind: kind) },
            tryAgain: { model.again(client: server.client) },
            theirsAgain: { model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online, retry: true) },
            reload: { reload() },
            openSimilar: { (tile: SimilarArtists.Tile) -> Void in navigation.open(tile.route) },
            seeAllSimilar: { navigation.open(.similarArtists(route)) })
    }

    /// (R6, the Mac's Top Songs) A top song you have, in the tap: every top song you have that plays now, in Last.fm's
    /// order, from this one (TopSongs.play) - as TopSongRow's tap; nothing awaited first.
    private func playTop(_ rows: [TopSongs.Row], from row: TopSongs.Row) {
        let online = reachability.online
        guard let plan = TopSongs.play(rows, from: row.rank, playable: { (song: Song) -> Bool in
            online || downloads.isHere(song.id)
        }) else { return }
        player.play(playlist: plan.songs, at: plan.at)
    }

    /// (R6, the Mac's Top Songs) A top song you don't have: the album you don't have, asked of MusicBrainz as
    /// TopSongRow's tap asks it (TopSongOpener) - nothing offline, nothing while it is already asked.
    private func openTop(_ row: TopSongs.Row) {
        guard reachability.online, model.opener.opening != TopSongOpener.key(row.top) else { return }
        model.opener.open(row.top, mbid: mbid, name: model.name, client: server.client, online: reachability.online,
                          admin: server.access.seesDetail, navigation: navigation)
    }

    /// (R6, the Mac's Most played) A song of Most played, in the tap: the listed songs that play now, from this one
    /// (MostPlayedSongs.play) - nothing awaited first.
    private func playMost(_ rows: [MostPlayedSongs.Row], from row: MostPlayedSongs.Row) {
        let online = reachability.online
        guard let plan = MostPlayedSongs.play(rows, from: row.rank, playable: { (song: Song) -> Bool in
            online || downloads.isHere(song.id)
        }) else { return }
        player.play(playlist: plan.songs, at: plan.at)
    }

    /// (R6, the Mac's Most played) The songs of their albums in hand you have played most (MostPlayedSongs) - once every
    /// album's songs have come or failed, as Top Songs waits; offline, of what is in hand or on this Mac.
    private func mostPlayed(_ mine: [ArtistPage.Row], online: Bool) -> [MostPlayedSongs.Row] {
        guard !(online && model.answer == nil),
              let library = TopSongs.library(order: ArtistPage.playOrder(mine), asks: model.asks, online: online,
                                             kept: { (id: String) -> Album? in downloads.keptAlbum(id) })
        else { return [] }
        return MostPlayedSongs.rows(library.albums)
    }
}

/// (R1c) The phone's top, iArtist's: the round picture beside the name, between the two, the name's letters drawn closer,
/// and the room above it; and (R6) the page's side margin. Here, not on ArtistView: a generic type holds no stored static.
private enum ArtistDrawn {
    static let phonePictureSide: CGFloat = 84    // drawn: iArtist .cover width
    static let phoneHeroGap: CGFloat = 14        // drawn: iArtist's top .f gap
    static let phoneNameTracking: CGFloat = -0.4 // drawn: iArtist's name letter-spacing
    static let phoneHeroAbove: CGFloat = 8       // drawn: iArtist's top .f padding-top
    static let edge: CGFloat = 16
}

extension ArtistView where Desk == EmptyView {
    /// The iPhone's page (and every one but the Mac's own): no desk.
    init(route: ArtistRoute) {
        self.route = route
        desk = nil
        _model = State(initialValue: ArtistPageModel(route: route))
    }
}

/// (R6) What the Mac's artist page (MacArtistPage) is handed by ArtistView: the page's own model, its rows and what it
/// draws, and its calls - so every ask, wait, letting go and play stays ArtistView's, and the Mac draws.
struct ArtistDesk {
    let model: ArtistPageModel
    let route: ArtistRoute
    /// Who they are on MusicBrainz, and whether that was chosen on this visit.
    let mbid: String?
    let byChoice: Bool
    let online: Bool
    let personal: Bool
    /// (R6's review) The person may get albums (the request permission): Get, and "10 more to get", only then.
    let mayGet: Bool
    /// The discography: your albums and theirs among them (ArtistJoin.rows) - (A2) in the order drawn (AlbumPlays.Shown).
    let rows: [ArtistJoin.Row]
    /// (A2) In Most played order, each row's plays in words ("4.1M plays"), by its key; and the Albums heading's menu.
    let plays: [String: String]
    let albumOrder: AlbumOrderChoice
    /// Their albums on MusicBrainz (online, who they are known) - its Studio only, its asking and its trouble - and
    /// whether its rows wait a moment for the library.
    let theirs: MBArtistModel?
    let holding: Bool
    /// What of Last.fm's is drawn, whether it is still waited for and where Top Songs goes - and its rows.
    let lastfm: LastfmPage.Shown
    let arrival: LastfmPage.Arrival
    let top: [TopSongs.Row]
    /// (A2) Similar Artists: whether it is listed, its tiles and whether they are drawn.
    let similar: SimilarShown
    /// (A4) About's words for the page - nil for none.
    let about: AboutBlock.Drawn?
    /// The songs you have played most (MostPlayedSongs).
    let mostPlayed: [MostPlayedSongs.Row]
    /// The songs of your albums of theirs, as Navidrome counts them - the status bar's.
    let songs: Int
    /// Play and Shuffle have something to play; the line the phone draws under them.
    let playable: Bool
    let line: String
    /// The artist tools: what the person may do, and what the page offers now (ArtistManage.offered).
    let managing: ArtistManaged
    let offered: ArtistManage.Offered
    /// ArtistView's own calls, each in the tap: Play, Shuffle, an album of yours played or opened, theirs opened (the
    /// album you don't have, or yours through the id bridge), Studio only or Everything, a tool's sheet, the albums
    /// that didn't come asked again, MusicBrainz asked again, the artist asked again.
    let play: () -> Void
    let shuffle: () -> Void
    let playAlbum: (String) -> Void
    /// A top song you have played from (with Top Songs' rows), one you don't opened, a most-played one played from.
    let playTop: ([TopSongs.Row], TopSongs.Row) -> Void
    let openTop: (TopSongs.Row) -> Void
    let playMost: ([MostPlayedSongs.Row], MostPlayedSongs.Row) -> Void
    let playsAlbum: (String) -> Bool
    let open: (ArtistPage.Row) -> Void
    let openTheirs: (MBArtistPage.Row) -> Void
    let studio: (Bool) -> Void
    let tool: (ArtistToolSheet.Kind) -> Void
    let tryAgain: () -> Void
    let theirsAgain: () -> Void
    let reload: () -> Void
    /// (A2) A similar artist's tile opened (their page, or their MusicBrainz page), and See All's grid.
    let openSimilar: (SimilarArtists.Tile) -> Void
    let seeAllSimilar: () -> Void
}

/// (R6) The strip's parts (iArtist's .chips): the two tabs - Studio only, Everything - and the managers' two, pushes.
enum ArtistStripPart: Hashable {
    case studio, everything, images, move

    var words: String {
        switch self {
        case .studio: return ArtistPageFacts.Words.studioOnly
        case .everything: return ArtistPageFacts.Words.everything
        case .images: return ArtistPageFacts.Words.images
        case .move: return ArtistPageFacts.Words.moveAlbums
        }
    }

    /// (R6's review) What VoiceOver and the pointer's help say of a part: its words - Move albums… in full, "Move albums
    /// to Ye…", as the ••• named it, while their name now is known.
    func said(current: String?) -> String {
        guard self == .move, let current else { return words }
        return ArtistManageWords.moveItem(current)
    }

    /// The managers' two the page offers now: each only as ArtistManage.offered says (its permission, deadwax in reach)
    /// - Artist images… once their folder is known, as the ••• had it, since the sheet asks by it.
    static func pushes(_ offered: ArtistManage.Offered, known: Bool) -> [ArtistStripPart] {
        var pushes: [ArtistStripPart] = []
        if offered.images && known { pushes.append(.images) }
        if offered.move { pushes.append(.move) }
        return pushes
    }
}

/// (R6) An artist's round picture: the square from their folder once Artist images wrote to it while the app runs, or
/// where Navidrome has none (ArtistManaged.square) - else Navidrome's (ArtistPicture). The phone's top and the Mac's
/// band.
struct ArtistHeroPicture: View {
    let managing: ArtistManaged
    let coverArt: String?
    let side: CGFloat
    let pixels: Int

    @Environment(ServerModel.self) private var server

    var body: some View {
        if let square = managing.square(navidrome: coverArt, written: { (path: String) -> Int in
            server.client.map { ArtistFolderVersions.shared.version($0, path: path) } ?? 0
        }) {
            ArtistFolderPicture(path: square, kind: "thumb", square: true, round: true)
                .frame(width: side, height: side)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            ArtistPicture(id: coverArt, side: side, pixels: pixels)
        }
    }
}

/// One album of the artist's you have (ArtistPage.tsx's row; since R6 iArtist's tall row, LibraryListRow): its cover,
/// its title and "1994 · in your library", and the chevron. Read as one: "Dummy, 1994, in your library". Dimmed, and
/// opening nothing, while deadwax can't be reached and nothing of it is on this phone.
private struct ArtistAlbumRow: View {
    let row: ArtistPage.Row
    let line: String
    /// (A2's review) The lines its title and line may take - two for one led by its plays at the accessibility sizes
    /// (AlbumPlays.Shown.lines), so they wrap rather than being cut.
    let lines: Int
    let dimmed: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            LibraryListRow(title: row.title, line: line, lines: lines) {
                LibraryCover(id: row.coverArt, pixels: CoverSize.row)
                    .clipShape(DWCorners.chipShape)
            } trailing: {
                LibraryChevron()
            }
            .contentShape(Rectangle())
            .opacity(dimmed ? DWPalette.off : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", "))
        .accessibilityValue(dimmed ? DownloadWords.notOnDevice(Platform.device) : "")
        .accessibilityAddTraits(dimmed ? [] : .isButton)
        .accessibilityAction {
            if !dimmed { open() }
        }
        // (the Mac app, slice 2) the album page's ••• on a right-click; nothing on the iPhone
        .albumRightClick(AlbumRoute(id: row.albumId, name: row.title, coverArt: row.coverArt))
    }
}

/// (R6) One album of theirs none of yours claims (MBArtistPage's row, iArtist's tall row): its cover through deadwax's
/// relay, its title and "1976 · not in your library" - and Get at its end for one nobody holds (`get`), else the
/// chevron. Its tap, and Get's, open the album you don't have (or yours through the id bridge), the spinner in place of
/// the chevron or Get while that is asked. One element to VoiceOver: its tap opens it, Get its action.
private struct ArtistTheirRow: View {
    let row: MBArtistPage.Row
    let line: String
    /// (A2's review) As ArtistAlbumRow's: two for one led by its plays at the accessibility sizes.
    let lines: Int
    let get: Bool
    let busy: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                LibraryListRow(title: row.title, line: line, lines: lines) {
                    ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: row.group.id),
                                 size: ArchiveCoverSize.row)
                        .clipShape(DWCorners.chipShape)
                } trailing: {
                    if busy {
                        ProgressView()
                    } else if !get {
                        LibraryChevron()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            if get && !busy {
                Button(ArtistPageFacts.Words.get, action: open)
                    .buttonStyle(DWButtonStyle(kind: .on, size: .small))
                    // the row's height, on its hairline as the rest of the row is
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", "))
        .accessibilityValue(busy ? SearchWords.loading : "")
        .accessibilityAddTraits(busy ? [] : .isButton)
        .accessibilityAction {
            if !busy { open() }
        }
        .accessibilityActions {
            if get && !busy {
                Button(ArtistPageFacts.Words.get, action: open)
            }
        }
    }
}

/// Under the discography's rows, MusicBrainz's word, once (ArtistJoin.foot): asking, and the moment its rows wait for
/// the library (`holding`); its trouble in a listener's words, with Try again (`again`); the cut at 500; or - with no
/// row at all - why there are none. The phone's page's and (R6) the Mac's (MacArtistPage), its words in the face the
/// page gives (`font`: the phone's small words, the Mac's base).
struct ArtistTheirFoot: View {
    let theirs: MBArtistModel
    let holding: Bool
    let rows: Int
    var font = Typeface.Phone.text(.small)
    let again: () -> Void

    @Environment(Reachability.self) private var reachability

    var body: some View {
        let shown = theirs.shown
        switch ArtistJoin.foot(asking: theirs.asking, answered: shown != nil, failed: theirs.trouble != nil,
                               truncated: shown?.truncated == true, holding: holding, rows: rows) {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(MBArtistPage.loading)
                    .font(font)
                    .foregroundStyle(DWPalette.t2)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 12)
        case .trouble:
            VStack(alignment: .leading, spacing: 10) {
                switch theirs.trouble {
                case .unavailable?:
                    ErrorNote(text: MBArtistPage.away)
                case .failed(let error)?:
                    ErrorNote(error, retry: true)
                case nil:
                    EmptyView()
                }
                Button(SearchWords.tryAgain, action: again)
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(reachability.probing)
            }
            .padding(.top, 12)
        case .truncated:
            ShelfNote(MBArtistPage.truncated)
        case .noAlbums:
            ShelfNote(MBArtistPage.none(studio: theirs.studioOnly))
        case .nothing:
            EmptyView()
        }
    }
}
