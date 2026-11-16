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
struct ArtistView: View {
    let route: ArtistRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(ArtistsModel.self) private var artists
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    @State private var model: ArtistPageModel
    /// The hero's name has scrolled away: the bar shows it.
    @State private var nameInBar = false
    /// The page has waited `SearchPacing.ownedWaitMs` for `/library/owned`: MusicBrainz's rows are drawn with what it has.
    @State private var ownedWaited = false
    /// (Phase 8, slice 5) The artist tools: the library's names for them and deadwax's word on each, and the sheet open.
    @State private var tools = ArtistToolsModel()
    @State private var toolSheet: ArtistToolSheet?
    /// One more each time the library's word on their names is wanted again (a save, a move, a pull).
    @State private var summaryAsks = 0

    /// The picture's side, in points (CoverImage asks the nearest step for the screen's scale: 1024 on an iPhone).
    private static let pictureSide: CGFloat = 200
    private static let edge: CGFloat = 16

    init(route: ArtistRoute) {
        self.route = route
        _model = State(initialValue: ArtistPageModel(route: route))
    }

    /// Who and which artist: a new person asks everything again.
    private var taskKey: String { "\(server.person)|\(route.id)" }

    /// Who they are on MusicBrainz, as the artist's answer and the library's folders now say (ArtistJoin.mbid).
    private var said: String? { model.mbid(index: search.ownedIndex, version: search.ownedVersion) }
    /// ...or, with nothing saying, who was chosen with Which artist is this? for this visit (the web's `said ?? chosen`).
    private var mbid: String? { said ?? artists.chosen[route.id]?.mbid }
    /// Who they are was chosen here, and nothing else says (the web's `byChoice`).
    private var byChoice: Bool { said == nil && artists.chosen[route.id] != nil }

    /// MusicBrainz's albums of theirs to draw: online, once `/library/owned` has answered or been waited for, the answer
    /// for the question asked now - or, while Studio only is asked again, the last one, kept on screen.
    private func theirGroups(online: Bool) -> [ReleaseGroup]? {
        guard ArtistJoin.drawsTheirs(online: online, indexKnown: search.ownedIndex != nil, waited: ownedWaited),
              let discography = model.discography else { return nil }
        return (discography.shown ?? discography.albums)?.groups
    }

    var body: some View {
        let online = reachability.online
        let personal = server.access.hasLibrary
        let albums = self.albums(online: online)
        let mine = ArtistPage.rows(albums)
        let rows = model.rows(albums: albums, groups: theirGroups(online: online), index: search.ownedIndex,
                              version: search.ownedVersion)
        let managing = self.managing()
        let offered = self.offered(managing, online: online)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero(managing)
                    .onAppear { nameInBar = false }
                    .onDisappear { nameInBar = true }
                if model.answer == nil && !online && mine.isEmpty {
                    // nothing of theirs in hand, and deadwax out of reach: a state, not a failure - nothing was asked
                    ShelfNote(DownloadWords.onlyDownloadedPlay)
                } else if model.gone {
                    ErrorNote(text: ErrorWords.artistGone)
                        .padding(.top, 8)
                } else if let failure = model.failure, model.answer == nil, online {
                    VStack(alignment: .leading, spacing: 10) {
                        ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)
                        Button(LibraryWords.tryAgain) { reload() }
                    }
                    .padding(.top, 8)
                } else {
                    plays(rows: mine, online: online, personal: personal)
                    albumsList(rows, albums: albums, online: online, personal: personal)
                }
            }
            .padding(.horizontal, Self.edge)
            .padding(.bottom, 24)
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
            if offered.any {
                ToolbarItem(placement: .topBarTrailing) {
                    toolsMenu(managing, offered)
                }
            }
        }
        // (Phase 8, slice 5) the library's word on each of their names, for the artist tools - for their names as they
        // are now, asked again after a write or a pull
        .task(id: "\(taskKey)|\(ArtistToolsModel.key(managing.names))|\(online)|\(summaryAsks)") {
            guard managing.may.any else { return }
            await tools.summarize(managing.names, client: server.client, online: online, again: summaryAsks > 0)
        }
        .sheet(item: $toolSheet) { (open: ArtistToolSheet) in
            toolSheetView(open, managing)
        }
        .task(id: taskKey) {
            // which of MusicBrainz's albums are yours is the library's folders' word: asked again as the page shows
            search.refreshOwned()
            await model.load(key: taskKey, client: server.client, online: reachability.online, artists: artists)
        }
        .task(id: "\(taskKey)|\(mbid ?? "")") {
            // their albums on MusicBrainz, once who they are there is known - or let go when it no longer is
            model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online)
            // (Phase 8, slice 5) and their name now, for the artist tools - only for someone who manages
            if Managing.artistManaging(server.access.permissions).any {
                await model.theirFacts(client: server.client, online: reachability.online)
            }
        }
        .task {
            // MusicBrainz's rows wait a moment for /library/owned, once a page's life
            guard !ownedWaited else { return }
            try? await Task.sleep(nanoseconds: UInt64(SearchPacing.ownedWaitMs) * 1_000_000)
            if !Task.isCancelled { ownedWaited = true }
        }
        .task { await downloads.followProgress() }
        .refreshable {
            // deadwax out of reach: a pull asks whether it is back (the banner says why nothing changes)
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            await model.load(key: taskKey, client: server.client, online: true, artists: artists, again: true)
            if model.asks.someMissing { model.again(client: server.client) }
            model.theirAlbums(mbid: mbid, client: server.client, online: true, retry: true)
            summaryAsks += 1
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
    }

    /// The artist asked again (Try again, deadwax back) - and the albums whose songs didn't come, and their albums on
    /// MusicBrainz after a failure.
    private func reload() {
        let key = taskKey
        Task {
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists)
            if model.asks.someMissing { model.again(client: server.client) }
            model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online, retry: true)
            if Managing.artistManaging(server.access.permissions).any {
                await model.theirFacts(client: server.client, online: reachability.online)
            }
        }
    }

    /// Their albums: the answer's - or, while deadwax can't be reached, the answer in hand, else the albums on this phone
    /// naming them (ArtistOffline.albums).
    private func albums(online: Bool) -> [Album] {
        if online || model.answer != nil { return model.answer?.album ?? [] }
        let downloaded = downloads.downloadedAlbums.compactMap { (album: IndexAlbum) -> Album? in
            downloads.keptAlbum(album.id)
        }
        return ArtistOffline.albums(answer: nil, artistId: route.id, downloaded: downloaded)
    }

    // MARK: the hero

    /// Their picture and name - (Phase 8, slice 5) the square from their folder once Artist images wrote to it while the
    /// app runs, or where Navidrome has none (the web's `square`: Navidrome keeps its own copy of the picture it had);
    /// and, who they are chosen here, that it was.
    private func hero(_ managing: ArtistManaged) -> some View {
        VStack(spacing: 0) {
            Group {
                if let square = managing.square(navidrome: model.coverArt, written: { (path: String) -> Int in
                    server.client.map { ArtistFolderVersions.shared.version($0, path: path) } ?? 0
                }) {
                    ArtistFolderPicture(path: square, kind: "thumb", square: true, round: true)
                        .frame(width: Self.pictureSide, height: Self.pictureSide)
                        .clipShape(Circle())
                } else {
                    ArtistPicture(id: model.coverArt, side: Self.pictureSide, pixels: CoverSize.hero)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .padding(.top, 8)
            Text(model.name)
                .font(Typeface.title.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            if byChoice {
                Text(ArtistManageWords.chosen)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
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

    /// The bar's •••: the artist tools offered, each opening its sheet.
    private func toolsMenu(_ managing: ArtistManaged, _ offered: ArtistManage.Offered) -> some View {
        Menu {
            if offered.images {
                Button {
                    toolSheet = ArtistToolSheet(kind: .images)
                } label: {
                    Label(ArtistManageWords.imagesItem, systemImage: "photo.on.rectangle")
                }
                // their folder known first: the sheet asks by it
                .disabled(!managing.known)
            }
            if offered.who {
                Button {
                    toolSheet = ArtistToolSheet(kind: .who)
                } label: {
                    Label(ArtistManageWords.whoItem, systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            if offered.move, let current = managing.current {
                Button {
                    toolSheet = ArtistToolSheet(kind: .move)
                } label: {
                    Label(ArtistManageWords.moveItem(current), systemImage: "folder")
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
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists, again: true)
            try? await Task.sleep(for: .milliseconds(AlbumEdit.settleMs))
            guard navigation.session == session else { return }
            search.refreshOwned()
            summaryAsks += 1
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists, again: true)
        }
    }

    // MARK: Play and Shuffle

    /// Play and Shuffle, the line under them (held at its height whatever it says), and Try again when some albums'
    /// songs didn't come.
    @ViewBuilder
    private func plays(rows: [ArtistPage.Row], online: Bool, personal: Bool) -> some View {
        let order = ArtistPage.playOrder(rows)
        let offlineAlbums = online ? [] : offlinePlayable(order)
        let playable = online ? model.asks.playable : !offlineAlbums.isEmpty
        let line = online ? model.asks.line(library: model.library, personal: personal)
            : DownloadWords.onlyDownloadedPlay
        VStack(spacing: 8) {
            PlayButtons(enabled: playable,
                        play: { play(shuffle: false, online: online, offlineAlbums: offlineAlbums) },
                        shuffle: { play(shuffle: true, online: online, offlineAlbums: offlineAlbums) })
            Text(line.isEmpty ? " " : line)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(line.isEmpty)
            if online, model.asks.someMissing {
                Button(LibraryWords.tryAgain) { model.again(client: server.client) }
                    .font(Typeface.footnote)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 8)
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

    // MARK: their albums

    /// Albums: the heading (Studio only at its end once MusicBrainz is asked), your albums and theirs among them, and
    /// under them what MusicBrainz is doing. With neither, nothing: the line under Play and Shuffle says so ("None of
    /// their albums are here to play.").
    @ViewBuilder
    private func albumsList(_ rows: [ArtistJoin.Row], albums: [Album], online: Bool, personal: Bool) -> some View {
        // offline the page is your albums alone: nothing of MusicBrainz's is drawn, said or asked
        let theirs = online ? model.discography : nil
        if !rows.isEmpty || theirs != nil {
            albumsHead(theirs)
            ForEach(rows) { (row: ArtistJoin.Row) in
                switch row {
                case .yours(let mine):
                    ArtistAlbumRow(row: mine, line: ArtistPage.line(mine, personal: personal),
                                   marked: ArtistPage.marked(mine, personal: personal),
                                   dimmed: !online && !downloads.album(id: mine.albumId).hasSongsHere) {
                        open(mine, albums: albums)
                    }
                case .theirs(let other):
                    MBArtistAlbumRow(row: other, line: MBArtistPage.line(other, personal: personal),
                                     marked: MBArtistPage.marked(other, personal: personal),
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

    /// "Albums", and Studio only at its end - laid out whether or not MusicBrainz is asked, so the heading is one height
    /// before who they are is known and after.
    private func albumsHead(_ theirs: MBArtistModel?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ArtistWords.albumsHeading)
                .font(Typeface.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Toggle(MBArtistPage.studioOnly, isOn: Binding(get: { theirs?.studioOnly ?? true }, set: { (_: Bool) -> Void in
                theirs?.toggleStudio(client: server.client, online: reachability.online)
            }))
            .toggleStyle(.button)
            .font(Typeface.footnote)
            .opacity(theirs == nil ? 0 : 1)
            .disabled(theirs == nil)
            .accessibilityHidden(theirs == nil)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    /// Under the rows, MusicBrainz's word, once (ArtistJoin.foot): asking, and the moment its rows wait for the library
    /// (`holding`); its trouble in a listener's words, with Try again; the cut at 500; or - with no row at all - why there
    /// are none.
    @ViewBuilder
    private func theirFoot(_ theirs: MBArtistModel, holding: Bool, rows: Int) -> some View {
        let shown = theirs.shown
        switch ArtistJoin.foot(asking: theirs.asking, answered: shown != nil, failed: theirs.trouble != nil,
                               truncated: shown?.truncated == true, holding: holding, rows: rows) {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(MBArtistPage.loading)
                    .foregroundStyle(Palette.quiet)
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
                Button(SearchWords.tryAgain) {
                    model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online, retry: true)
                }
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

    /// A row's tap: its album's page, what the artist's answer knew of it drawn at once - the artist line their link.
    private func open(_ row: ArtistPage.Row, albums: [Album]) {
        var album = albums.first { (album: Album) -> Bool in album.id == row.albumId }.map { (album: Album) -> AlbumRoute in
            AlbumRoute(album)
        } ?? AlbumRoute(id: row.albumId, name: row.title, coverArt: row.coverArt)
        if album.artist == nil { album.artist = model.name }
        if album.artistId == nil { album.artistId = route.id }
        navigation.open(.album(album))
    }
}

/// One album of the artist's (ArtistPage.tsx's row): its cover at the rows' size, its title, and "1994 · in your
/// library" with the green tick before it for an album marked (ArtistPage.marked). Read as one. Dimmed, and opening
/// nothing, while deadwax can't be reached and nothing of it is on this phone.
private struct ArtistAlbumRow: View {
    let row: ArtistPage.Row
    let line: String
    let marked: Bool
    let dimmed: Bool
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    LibraryCover(id: row.coverArt, pixels: CoverSize.row)
                        .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                        .clipShape(Corners.artShape)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .foregroundStyle(.primary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if marked {
                                Image(systemName: "checkmark")
                                    .font(Typeface.symbol(.caption2).weight(.bold))
                                    .foregroundStyle(Palette.held)
                                    .accessibilityHidden(true)
                            }
                            Text(line)
                                .font(Typeface.subheadline)
                                .foregroundStyle(Palette.quiet)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(Typeface.symbol(.footnote).weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .opacity(dimmed ? Palette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", "))
            .accessibilityValue(dimmed ? DownloadWords.notOnPhone : "")
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }
}
