import DeadwaxCore
import SwiftUI

/// An album's page (screens.md 4; the web's ui/src/player/AlbumPage.tsx), by Navidrome's album id - what opened it
/// (the Library's row, Now Playing's Go to the album) drawn at once while the album loads. Top to bottom: the hero
/// (cover, title, artist, meta line, the badge, Play and Shuffle), the mine block (logins on with a library of your
/// own), the songs with their disc headings (each swiped right adds it to the queue), the footer; the bar's ••• is the
/// whole album's Add to Queue - and (Phase 8, slice 1) Edit album, for someone the web gives the album's Edit - and
/// Album info (notes/ios.md "Album info"), the album's sheet of everything known of it, for everyone. After Edit album
/// writes to the album's folder the page asks again (AppNavigation.albumWrites); an apply that gave the album a new id
/// in Navidrome moves the page to it (AppNavigation.albumMoved).
///
/// What it asks as it opens, at once (AlbumModel): the album; the id bridge only with a library of your own (D12);
/// and, as the songs come, the album's levels warmed (PlayerModel.albumShown) - wanted again each time the page is
/// shown, let go when it goes (PlayerModel.albumLeft). While it is on top your library is told it was opened
/// (LibraryModel.opened - its New mark goes), again as /me/library answers. Every rule is Core's; this draws.
///
/// Play queues the songs from the first, Shuffle every song once in a random order, a row's tap from that song - all
/// as the album (Normalization's album level), through PlayerModel.play in the tap, nothing awaited first.
///
/// Downloads (phase2-downloads.md 3): the control in the bar beside the •••, the hero's line, the rows' marks, the
/// menus' download items and the footer's "on this phone" line - every one drawn from DownloadModel by the album's
/// songs, never from what the page last did, with progress followed while the page shows. An album with songs here
/// opens at once from what the phone kept. While deadwax can't be reached, the songs not here are dimmed, Play and
/// Shuffle take only what is here, and an album with nothing here says so in place of its songs.
///
/// PULL TO SHUFFLE (2026-11-15, James: "also let's add pull to shuffle to the album and playlists pages"; notes/ios.md
/// "Pull to shuffle on an album's and a playlist's page"): the Library's pull (ShufflePull, `pullsToShuffle`,
/// PullShuffleGraphic) on the page's List, its graphic above the hero; let go armed, it is the hero's Shuffle - the
/// same songs, as the album, from the same call, in the lift. Offline (or the album gone from the collection) only the
/// songs on this phone, or "Nothing on this phone to shuffle"; with no songs to draw (loading, failed, gone, not on
/// this phone) nothing is drawn and nothing plays (ShuffleCan.page). The pull never refreshes now, as the Library's
/// doesn't: the bar's •••'s Refresh asks again (offline, whether deadwax is back), and a failure with no album to draw
/// has Try again.
///
/// THE REDESIGN, SLICE R5 (iAlbum.dc.html, Album.dc.html; notes/ios.md "The redesign, slice R5: an album, Playlists, a
/// playlist"):
/// - On the phone, the bar holds iOS's back (‹ Library, or whatever opened the page), Edit - for whoever may edit the
///   album (Managing.albumEdit), while deadwax can be reached and the album is in the collection - and the •••, iOS's own
///   menu (James's answer 4): Add to Queue, Add to a playlist…, Download - headed with the download control's words for
///   its state, the control having left the bar - then Album info and Refresh. Edit album is the top row's Edit, so the
///   bar's ••• leaves it out (`barMenu`); no Play Next or Play Last. The hero and the rows are iAlbum's (AlbumHero,
///   TrackRow), on the page's ground; the pull and the rows' swipe stay.
/// - On the Mac (`desk`, from MacAlbum.page(for:)), MacAlbumPage draws the album in the List's place, handed this page's
///   own model and actions (AlbumDesk): every load, wait, levels warmed and let go, New mark seen and announcement stays
///   this page's - the Mac draws, nothing more. On the iPhone there is no desk (`init(route:)`).
///
/// ABOUT (Last.fm, slice A4 - lastfm.md 3.9; notes/ios.md "Last.fm, slice A4"): at the page's foot, under the songs'
/// line, "About" - deadwax's description of the album (Last.fm's words first, else Wikipedia's, else Navidrome's), with
/// Wikidata's subtitle, four lines and More (AboutSection; on the Mac, the desk's `about`). Asked by its release group -
/// the id bridge's (the web's own source) once it has answered, else what the library's folders of its pressing say
/// (`/library/owned`, asked if it isn't in hand - and again as deadwax comes back - and waited for until it answers or
/// fails) - and Navidrome's id, once the album is in hand (`aboutQuestion`); absent with no words. (A4's review) One
/// answer drawn, never Navidrome's words and then another's in their place.
struct AlbumView<Desk: View>: View {
    let route: AlbumRoute
    /// (R5) The Mac's album page, drawn in the List's place - none on the iPhone.
    private let desk: ((AlbumDesk) -> Desk)?

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    @State private var model: AlbumModel
    /// On screen - the page on top of its tab.
    @State private var shown = false
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false
    /// A download was asked for from this page and hasn't ended: its end is announced while the page is on top.
    @State private var askedHere = false
    /// The album Album info is open for (its sheet).
    @State private var albumInfo: Album?
    /// The page's pull to shuffle.
    @State private var pull = ShufflePull()
    /// (A4's review) `/library/owned`'s count of ends (SearchModel.ownedAnswers) as this page asked it - nil until it
    /// has: About's release group, without the bridge's, is the library's folders' word, waited for until it is in.
    @State private var ownedSince: Int?
    @AccessibilityFocusState private var noteFocused: Bool

    /// (R5) The Mac's: the album drawn by `desk` (MacAlbumPage).
    init(route: AlbumRoute, desk: @escaping (AlbumDesk) -> Desk) {
        self.route = route
        self.desk = desk
        _model = State(initialValue: AlbumModel(route: route))
    }

    /// What your library says of this album on its page, if anything: it waits for room, or you removed its download.
    private var libraryLine: String? {
        switch downloads.libraryMark(album: route.id) {
        case .waitsForRoom: return AutoDownloadWords.waitsForRoom(downloads.libraryScope, limit: downloads.storageLimit, device: Platform.device)
        case .keptOff: return AutoDownloadWords.keptOff(downloads.libraryScope, device: Platform.device)
        case .none, .withLibrary: return nil
        }
    }

    /// Who and which album: a new person, or a library of their own come or gone, asks everything again.
    private var taskKey: String { "\(server.person)|\(server.access.hasLibrary)|\(route.id)" }

    /// (Last.fm, slice A4) About's question for the page now (AboutBlock.album): once the album is in hand - and the
    /// bridge's word, when it is asked (A4's review) - by its release group: the bridge's, else what the library's
    /// folders of its pressing say, once they have answered or failed since the page asked; and Navidrome's id. Nothing
    /// for an album deadwax no longer has.
    private var aboutQuestion: AboutBlock.Question {
        AboutBlock.album(answered: model.album != nil && model.bridgeSettled, gone: model.gone || model.goneButHere,
                         navidromeId: route.id, release: model.album?.musicBrainzId,
                         storeGroup: model.store?.releaseGroupMbid, index: search.ownedIndex,
                         ownedSettled: ownedSettled)
    }

    /// (A4's review) `/library/owned` has answered, or failed, since this page asked it.
    private var ownedSettled: Bool {
        ownedSince.map { (since: Int) -> Bool in search.ownedAnswers > since } ?? false
    }

    /// (A4's review) When `/library/owned` is asked for About: as the page opens for someone, and again as deadwax comes
    /// back (or the app's client does).
    private var ownedKey: String { "\(taskKey)|\(reachability.online)|\(server.client != nil)" }

    /// (A4) About asked for the page and the question, and whether deadwax can be reached - so only the newest draws.
    private var aboutKey: String { "\(taskKey)|\(aboutQuestion.token)|\(reachability.online)" }

    var body: some View {
        let download = downloads.album(model.songs)
        let offline = !reachability.online
        let note = OfflineAlbum.note(online: reachability.online, haveSongs: model.album != nil, gone: model.goneButHere,
                                     anyHere: download.hasSongsHere, device: Platform.device)
        let playable = self.playable
        let can = pullCan(playable)
        Group {
            if let desk, Platform.mac {
                desk(AlbumDesk(model: model, download: download, playable: playable, offline: offline || model.goneButHere,
                               note: note, libraryLine: libraryLine, goesToo: downloads.goesWithLibrary(album: route.id),
                               noteFocused: $noteFocused, menu: albumMenu, edit: editAction, play: { play(at: 0) },
                               shuffle: { play(at: nil, shuffle: true) }, playFrom: { (song: Song) -> Void in play(song: song) },
                               row: { (song: Song, album: Album) -> QueueMenuRequest in rowMenu(song, of: album) },
                               change: { (action: AlbumMine.Action) -> Void in
                                   Task { await model.change(action, client: server.client, library: library, downloads: downloads) }
                               },
                               refresh: { refresh() }, asked: { askedHere = true },
                               about: model.about.drawn(for: taskKey)))
            } else {
                page(download: download, offline: offline, note: note, can: can, playable: playable)
            }
        }
        // (the Mac app, slice 2) ⌘R: the •••'s Refresh, while the page shows; nothing on the iPhone
        .refreshCommand { refresh() }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { bar }
        .task(id: taskKey) {
            model.online = reachability.online
            await model.load(key: taskKey, client: server.client, personal: server.access.hasLibrary, player: player,
                             downloads: downloads, kept: kept)
        }
        .task { await downloads.followProgress() }
        // (Last.fm, slice A4) About, asked for the page and the album's ids now - the session's answer drawn at once
        .task(id: aboutKey) {
            model.about.ask(page: taskKey, person: server.person, question: aboutQuestion, client: server.client,
                            online: reachability.online)
        }
        .task(id: ownedKey) {
            // (A4's review) About's release group, without the bridge's, is the library's folders' word: asked if it
            // isn't in hand, and About holds until it has answered or failed - never a fixed wait
            guard reachability.online, server.client != nil, search.ownedIndex == nil else { return }
            ownedSince = search.ownedAnswers
            search.refreshOwned()
        }
        .onChange(of: reachability.online) { _, online in
            model.online = online
            // back: what the page drew from the phone, or couldn't draw, is asked of deadwax now
            guard online else { return }
            Task {
                await model.load(key: taskKey, client: server.client, personal: server.access.hasLibrary, player: player,
                                 downloads: downloads, kept: kept)
            }
        }
        .appSheet(item: $albumInfo) { album in
            AlbumInfoSheet(album: album)
                .macSheet()
        }
        .onChange(of: download) { _, now in ended(now) }
        // (Phase 8, slice 1) Edit album wrote to this album's folder: asked again, as the web's page is after an edit
        .onChange(of: navigation.albumWrites[route.id]) { _, _ in refresh() }
        .onChange(of: model.answered) { _, _ in told() }
        .onAppear {
            shown = true
            seen()
            // shown again (a page over it gone, its tab back): its levels wanted again - its first showing waits for
            // the album to answer (AlbumModel.load)
            if let album = model.album { player.albumShown(album) }
        }
        .onDisappear {
            shown = false
            player.albumLeft(id: route.id)
        }
        .onChange(of: library.marks) { _, _ in
            // your library answered while the page is on top: one opened before deadwax said what is new is cleared too
            if shown { seen() }
        }
    }

    /// The phone's page (and the iPhone's only): the List of the hero, the notes, the songs and the footer.
    private func page(download: AlbumDownload, offline: Bool, note: String?, can: ShuffleCan,
                      playable: [Song]) -> some View {
        List {
            AlbumHero(model: model, download: download, playable: !playable.isEmpty,
                      play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) })
                .overlay(alignment: .top) {
                    // the pull's graphic, in the room the pull opens above the hero, as the Library's above its first
                    // row: its foot at the hero's top
                    PullShuffleGraphic(state: pull, can: can, of: .page)
                        .fixedSize(horizontal: false, vertical: true)
                        .alignmentGuide(.top) { (drawn: ViewDimensions) -> CGFloat in drawn[.bottom] }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .onAppear { setTitleInBar(false) }
                .onDisappear { setTitleInBar(true) }

            // the album gone from the collection, with songs of it here: said quietly under the hero - it still plays
            if model.goneButHere, let note {
                QuietNote(text: note)
                    .listRowSeparator(.hidden)
            }

            if model.placeholderShown {
                MinePlaceholder()
                    .listRowSeparator(.hidden)
            } else if model.mineBlockShown {
                MineBlock(mine: model.mine, busy: model.busy, refused: model.refused,
                          act: { action in
                              Task { await model.change(action, client: server.client, library: library, downloads: downloads) }
                          },
                          noteFocused: $noteFocused,
                          goesToo: downloads.goesWithLibrary(album: route.id))
                    .listRowSeparator(.hidden)
            }

            // your library and this album (phase3-autodownload.md 3.4): waiting for room, or kept off - said quietly
            if let line = libraryLine {
                QuietNote(text: line)
                    .listRowSeparator(.hidden)
            }

            if model.empty {
                ErrorNote(text: ErrorWords.albumGone)
                    .listRowSeparator(.hidden)
            } else if let failure = model.failure {
                // no album to draw, and not gone: Try again (the pull shuffles now; with an album drawn, the •••'s
                // Refresh)
                let retry = model.album == nil && !model.gone
                ErrorNote(failure, gone: ErrorWords.albumGone, retry: retry)
                    .listRowSeparator(.hidden)
                if retry {
                    // a row of its own, so the note's disclosure (whoever runs deadwax's) keeps its own tap
                    Button(LibraryWords.tryAgain, action: refresh)
                        .listRowSeparator(.hidden)
                }
            } else if model.album == nil, let note {
                // not on this phone, and deadwax out of reach: a state, not a failure - nothing was asked
                QuietNote(text: note)
                    .listRowSeparator(.hidden)
            } else if model.album == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(AlbumPageLines.loading)
                    .listRowSeparator(.hidden)
            }

            if let album = model.album {
                songs(album, download: download, offline: offline || model.goneButHere)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.footer)
                    let here = downloads.here(model.songs)
                    if let line = DownloadWords.footer(here: here.count, of: model.songs.count, bytes: here.bytes, device: Platform.device) {
                        Text(line)
                    }
                }
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t3)
                .listRowSeparator(.hidden, edges: .bottom)
                .listRowBackground(Color.clear)
                // (A4) About, under the songs' line, at the page's foot
                if let about = model.about.drawn(for: taskKey) {
                    AboutSection(drawn: about)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        // the pull shuffles the album (never refreshes), while the page is the one on top
        .pullsToShuffle(PullShuffling(state: pull, can: can, on: shown, start: pulled))
        // (R5) the page's ground - (R1c's review) on the phone `.dw.ph`'s black, iAlbum's, so the mini player and the tab
        // bar sit on it with no seam; the Mac's --bg, as R5 drew it
        .scrollContentBackground(.hidden)
        .background(Platform.mac ? DWPalette.bg : DWPalette.page)
    }

    /// The page on top is seen (App.tsx's seenAlbum for the page on top): its New mark goes, and deadwax is told.
    private func seen() {
        library.opened(id: route.id, musicBrainzId: route.musicBrainzId ?? model.album?.musicBrainzId)
    }

    /// The songs, a disc heading above the first of each disc when the album shows them. `offline`: a song not on this
    /// phone is dimmed (deadwax out of reach, or the album gone from the collection).
    @ViewBuilder private func songs(_ album: Album, download: AlbumDownload, offline: Bool) -> some View {
        let songs = model.songs
        let headings = model.headings
        let heard = player.current?.track
        // the slot on every row where any song has a state, on none where none does
        let slot = songs.contains { downloads.state($0.id) != .none }
        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
            if headings.indices.contains(index), let heading = headings[index] {
                DiscHeadingRow(heading: heading)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            let state = downloads.state(song.id)
            TrackRow(song: song, albumArtist: album.artist, current: PlayingBars.marks(song, heard: heard),
                     playing: player.isPlaying,
                     play: { play(song: song) },
                     menu: rowMenu(song, of: album),
                     download: state, slot: slot, dimmed: offline && !state.isHere,
                     actions: !downloads.isOpen ? []
                         : model.goneButHere ? downloads.choices(songs: [song], gone: true)
                         : downloads.choices(song: song.id)) { choice in
                act(choice, on: song)
            }
            // (R5) iAlbum's .row: edge to edge, on the row's rule
            .listRowInsets(EdgeInsets())
            .listRowSeparatorTint(DWPalette.rowRule)
            .listRowBackground(Color.clear)
        }
    }

    /// A song's own •••: the one song, as a song - its row's on the phone, its row's right-click and ••• on the Mac.
    private func rowMenu(_ song: Song, of album: Album) -> QueueMenuRequest {
        QueueMenuRequest(pick: .song(song, of: album), album: album, gone: model.goneButHere)
    }

    // MARK: the bar (R5)

    /// The phone's bar (iAlbum's top row): the title once the hero's has scrolled away, Edit for whoever may, and the
    /// ••• - iOS's back before them. On the Mac, whose toolbar is MacAlbumPage's, (R5's review) the title alone, as a
    /// playlist's page has it: its place held, unseen, the hero saying the name - so the two pages' bars agree.
    @ToolbarContentBuilder private var bar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.name)
                .font(Typeface.headline)
                .lineLimit(1)
                .opacity(titleInBar ? 1 : 0)
                .accessibilityHidden(!titleInBar)
        }
        if desk == nil || !Platform.mac {
            if Managing.albumEdit(server.access.permissions).shown {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(PlaylistWords.edit) { editAction?() }
                        .disabled(editAction == nil)
                        .accessibilityLabel(EditWords.menuItem)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                QueueMenu(request: barMenu) {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(AlbumPageLines.moreForAlbum)
            }
        }
    }

    /// (R5) Edit album, for whoever may (Managing.albumEdit, the •••'s Edit album until R5): the top row's Edit on the
    /// phone, the toolbar's on the Mac - while deadwax can be reached and the album is in the collection, as the item
    /// was offered; nil (Edit dimmed) until the album's songs are in.
    private var editAction: (@MainActor () -> Void)? {
        guard reachability.online, !model.goneButHere else { return nil }
        return albumMenu?.editAlbum
    }

    /// (R5) The phone's bar •••: the album's own (`albumMenu`) - Add to Queue, Add to a playlist…, Download headed with
    /// the control's words, Album info, Refresh - its Edit album the top row's Edit instead.
    private var barMenu: QueueMenuRequest? {
        guard var request = albumMenu else { return nil }
        request.editAlbum = nil
        return request
    }

    /// The bar's •••: the whole album, as an album - nil (the ••• dimmed) until its songs are in. (Phase 8, slice 1)
    /// With the album's Edit (Edit albums or Look after the library - Managing.albumEdit), Edit album over the tabs. And
    /// Album info, for everyone. (The Mac app, slice 2) The album's own ••• (QueueMenuRequest.album, a tile's right-click
    /// too), and the page's Refresh after it.
    private var albumMenu: QueueMenuRequest? {
        guard let album = model.album,
              var request = QueueMenuRequest.album(album, gone: model.goneButHere, permissions: server.access.permissions,
                                                   navigation: navigation, info: { albumInfo = album }) else { return nil }
        request.refresh = { refresh() }
        // (R5) Download from the ••• (the control's place on the phone): its end announced, as the control's was
        request.downloadAsked = { askedHere = true }
        return request
    }

    /// What the pull can do (ShuffleCan.page): the album's songs, as the hero's Shuffle takes them (`playable`) - while
    /// deadwax can't be reached, or with the album gone from the collection, only those on this phone; nothing while there
    /// are no songs to draw.
    private func pullCan(_ playable: [Song]) -> ShuffleCan {
        ShuffleCan.page(songs: model.songs.count, phoneOnly: !reachability.online || model.goneButHere,
                        onPhone: playable.count)
    }

    /// The pull let go armed: the hero's Shuffle, in the lift - nothing awaited first. Should the songs on this phone have
    /// gone since it armed (a removal), said, as the Library's pull says it.
    private func pulled() {
        if playable.isEmpty, !reachability.online || model.goneButHere {
            player.say(PullShuffleWords.nothingHere(Platform.device))
            return
        }
        play(at: nil, shuffle: true)
    }

    /// The •••'s Refresh and a failure's Try again (the pull was this until it shuffled): the album and whose it is asked
    /// again now - or, while deadwax can't be reached, whether it is back (the banner says why nothing changes).
    private func refresh() {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        Task { await model.refresh(client: server.client, player: player, downloads: downloads, kept: kept) }
    }

    /// (Speed A, fix 2) The stamp the session's kept album answers are read and kept under now: who is signed in and
    /// every write deadwax was told of (KeptAlbumAnswers.stamp) - an Edit's write to this album moves it, so the
    /// refresh that follows keeps its answer under the new one and nothing from before is drawn again.
    private var kept: KeptAnswers<Album>.Stamp { KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library) }

    /// What Play and Shuffle take: the album's songs - offline, or with the album gone from the collection, its songs on
    /// this phone, in its order.
    private var playable: [Song] {
        guard !reachability.online || model.goneButHere else { return model.songs }
        return OfflineAlbum.playable(model.songs, here: downloads.isHere)
    }

    /// Play, Shuffle and a row's tap: the album's songs, as the album, from `index` (nil with Shuffle: any song
    /// first). In the tap - nothing awaited before the player is called.
    private func play(at index: Int?, shuffle: Bool = false) {
        let songs = playable
        guard let album = model.album, !songs.isEmpty else { return }
        player.play(songs: songs, album: album, at: index, shuffle: shuffle)
    }

    /// A row's tap: the album from that song (among those that play, offline).
    private func play(song: Song) {
        guard let index = playable.firstIndex(where: { $0.id == song.id }) else { return }
        play(at: index)
    }

    /// A row's VoiceOver action - the song's ••• download items.
    private func act(_ choice: DownloadChoice, on song: Song) {
        switch choice {
        case .download: downloads.download(song)
        case .downloadAgain: downloads.tryAgain(song.id)
        case .remove:
            downloads.remove(song.id)
            player.say(DownloadWords.removed(song.title ?? "", device: Platform.device))
        }
    }

    /// A download asked for from this page has ended while the page is on top: VoiceOver hears it ("Downloaded Dummy",
    /// "Dummy: 2 songs didn't download"); nothing more is drawn - the control and the line say it.
    private func ended(_ now: AlbumDownload) {
        guard askedHere else { return }
        switch now {
        case .downloaded:
            askedHere = false
            if shown { Notice.announce(DownloadWords.ended(model.name, failed: 0)) }
        case .failed(let count, _):
            askedHere = false
            if shown { Notice.announce(DownloadWords.ended(model.name, failed: count)) }
        case .none:
            askedHere = false
        default:
            break
        }
    }

    /// An Add or Remove answered: taken - VoiceOver goes to the line that says so (the web's role=status, its focus
    /// handed to the line); refused - the refusal is read out where the button keeps the focus (role=alert).
    private func told() {
        if let refused = model.refused {
            Notice.announce(ErrorWords.of(refused, admin: server.access.seesDetail).said)
        } else if model.mine.note != nil {
            // after the line is drawn: the focus can only go to a view that is there
            Task { @MainActor in
                await Task.yield()
                noteFocused = true
            }
        }
    }

    private func setTitleInBar(_ shown: Bool) {
        guard titleInBar != shown else { return }
        withAnimation(.easeInOut(duration: 0.2)) { titleInBar = shown }
    }
}

extension AlbumView where Desk == EmptyView {
    /// The iPhone's page (and every one but the Mac's own): no desk.
    init(route: AlbumRoute) {
        self.route = route
        desk = nil
        _model = State(initialValue: AlbumModel(route: route))
    }

    init(id: String, name: String? = nil, artist: String? = nil, coverArt: String? = nil) {
        self.init(route: AlbumRoute(id: id, name: name, artist: artist, coverArt: coverArt))
    }
}

/// (R5) What the Mac's album page (MacAlbumPage) is handed by AlbumView: the page's own model and its actions - so every
/// load, wait, levels warmed and let go, New mark seen and announcement stays AlbumView's, and the Mac draws.
struct AlbumDesk {
    let model: AlbumModel
    let download: AlbumDownload
    /// What Play and Shuffle take: the songs - offline (or the album gone from the collection), those on this Mac.
    let playable: [Song]
    /// Songs not on this Mac are dimmed: deadwax out of reach, or the album gone from the collection.
    let offline: Bool
    /// The phone's page's quiet lines, said on the Mac's too: the album not on this Mac with deadwax out of reach (or
    /// gone from the collection with songs here - OfflineAlbum.note), and what your library says of it.
    let note: String?
    let libraryLine: String?
    /// Remove from my library takes the album's download from this Mac too (MineBlock's `goesToo`).
    let goesToo: Bool
    /// Whose line takes VoiceOver's focus when an Add or Remove is taken (AlbumView's `told`).
    let noteFocused: AccessibilityFocusState<Bool>.Binding
    /// The album's own ••• (QueueMenuRequest.album, with Album info, Edit album and Refresh) - nil until its songs are in.
    let menu: QueueMenuRequest?
    /// Edit album for whoever may - nil offline, for an album gone, and until the songs are in.
    let edit: (@MainActor () -> Void)?
    /// Play from the first song; Shuffle; a row's double-click or Return - AlbumView's own calls, in the tap.
    let play: () -> Void
    let shuffle: () -> Void
    let playFrom: (Song) -> Void
    /// A song's own •••, its right-click.
    let row: (Song, Album) -> QueueMenuRequest
    /// Add to my library or Remove from my library (the mine block's), AlbumModel.change.
    let change: (AlbumMine.Action) -> Void
    /// A failure's Try again: the album asked again (the •••'s Refresh).
    let refresh: () -> Void
    /// A download asked for from the page: its end is announced while the page is on top.
    let asked: () -> Void
    /// (A4) About's words for the page - nil for none.
    let about: AboutBlock.Drawn?
}

/// A page's own quiet line (3.7): a state in words, not a failure - "This album isn't on this phone - it plays once
/// deadwax is back."
private struct QuietNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typeface.callout)
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
