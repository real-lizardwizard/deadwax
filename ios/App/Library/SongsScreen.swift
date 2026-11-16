import DeadwaxCore
import SwiftUI

/// Songs (Phase 4, slice 5 - phase4-library.md 2.7, 3.1, 6.5; the web's LibraryViews.tsx SongsView and LibrarySection.tsx
/// SongSection): every song of the collection, 100 a page, in Navidrome's order. A row is the song's cover, its title,
/// its artist and album, and opens its album - a fetch-then-play would start the music outside the tap; its ••• is the
/// song's own menu (Add to Queue, Add to a playlist…), and a swipe right adds it to the queue too (SongRow). Every rule
/// and word is Core's (SongsPaging, SongsBody,
/// SongsFoot, SongsList, SongWords); SongsModel holds the list.
///
/// Two ways it is drawn (question 32). As the Library's Songs page (`page`), under the switch, where the collection is
/// the Library (no library of your own): the switch's Find, bar and •••, and a pull that shuffles the Library (3.5),
/// never refreshes. Pushed on the tab's path with a library of your own (All music's All songs, AppRoute.allSongs): its
/// own title and Find, pull to refresh - and the collection's own Shuffle at its head (ShuffleSongs.tsx's, `.allSongs`),
/// asked ahead as it shows.
///
/// Find (question 33) asks Navidrome's own search for what is typed - the list is paged, so filtering the songs in hand
/// would say "no match" of songs not yet asked - once typing pauses. Choosing what to find goes back to the top; tapping
/// the Library tab again scrolls the page shown to its top.
///
/// While deadwax can't be reached (question 34) nothing is asked: the songs in hand draw, a song not on this phone dimmed
/// (it opens nothing); with none in hand, SongWords.offline.
struct SongsScreen: View {
    /// The Library's Songs page: what the switch hands it.
    struct Page {
        /// Find's words - the switch's field, this page's own text in it.
        let typed: Binding<String>
        /// The page the switch shows.
        let current: Bool
        let pulling: PullShuffling
    }

    let page: Page?

    /// All music's All songs, pushed.
    init() {
        page = nil
    }

    /// The Library's Songs page.
    init(page: Page) {
        self.page = page
    }

    @Environment(SongsModel.self) private var songs
    @Environment(ShuffleModel.self) private var shuffles
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    /// What is typed into a pushed screen's Find - the screen's own: leaving it clears it.
    @State private var ownTyped = ""
    /// On screen (not covered by a page pushed over it).
    @State private var shown = false

    /// How long typing pauses before Find asks (question 33): one ask for a word, not one a letter.
    private static let pause: UInt64 = 350_000_000

    /// What the screen's ask is keyed on: a new person, deadwax back, the page shown again, what Find asks for.
    private struct AskKey: Equatable {
        let person: Int
        let online: Bool
        let current: Bool
        let query: String
    }

    private var typed: String { page?.typed.wrappedValue ?? ownTyped }
    private var current: Bool { page?.current ?? true }

    var body: some View {
        let personal = server.access.hasLibrary
        let query = SongsList.query(typed)
        Group {
            if let page {
                list(page: page)
            } else {
                list(page: nil)
                    .navigationTitle(SongWords.title(personal: personal))
                    .searchable(text: $ownTyped, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: Text(SongWords.findPlaceholder))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .refreshable { await pulled() }
            }
        }
        .task(id: AskKey(person: server.person, online: reachability.online, current: current, query: query)) {
            // shown, or Find changed: the list for it - nothing while deadwax can't be reached
            guard reachability.online, current else { return }
            if songs.paging.query != nil, songs.paging.query != query, !query.isEmpty {
                // typing: asked once it pauses (a keystroke meanwhile cancels this task)
                try? await Task.sleep(nanoseconds: Self.pause)
                guard !Task.isCancelled else { return }
            }
            songs.show(typed)
        }
        .onChange(of: scenePhase) { _, phase in
            // the app back in front on All songs: its Shuffle asked ahead again when it should be
            guard phase == .active, shown, page == nil, reachability.online else { return }
            shuffles.shown(.allSongs, library.scope)
        }
        .onChange(of: reachability.online) { _, online in
            guard online else { return }
            // deadwax back: the paging picks up where the reader got to - the last rows appeared while it was out of
            // reach, asking nothing, and won't appear again until scrolled away and back
            if current, page != nil || shown { songs.resumed() }
            guard shown, page == nil else { return }
            shuffles.shown(.allSongs, library.scope)
        }
        .onAppear {
            shown = true
            if page == nil, reachability.online { shuffles.shown(.allSongs, library.scope) }
        }
        .onDisappear { shown = false }
    }

    /// A pushed list's pull: its first page asked again now, the spinner lasting until it lands (as Artists' does) - or,
    /// while deadwax can't be reached, whether it is back.
    private func pulled() async {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        let asked = songs.refresh(typed)
        shuffles.shown(.allSongs, library.scope)
        await asked?.value
    }

    private func list(page: Page?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                        .overlay(alignment: .bottom) {
                            // the pull's graphic, in the room the pull opens above the first row (3.5)
                            if let page {
                                PullShuffleGraphic(state: page.pulling.state, can: page.pulling.can)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    if page == nil {
                        shuffleButton
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .pullsToShuffle(page?.pulling)
            .onChange(of: typed) { _, _ in jump(proxy) }
            .onChange(of: songs.landed) { _, _ in jump(proxy) }
            .onChange(of: navigation.libraryScrollToTop) { _, _ in
                // the Library tab tapped at its root: the page shown goes to its top
                guard shown, page?.current == true else { return }
                jump(proxy, animated: true)
            }
        }
    }

    // MARK: All songs' Shuffle (with a library of your own)

    /// What All songs' Shuffle can do now: play the collection's first page in hand, shuffle the downloads while deadwax
    /// can't be reached, or why not.
    private var allSongsCan: ShuffleCan {
        let online = reachability.online
        return ShuffleCan.of(online: online, ready: shuffles.ready(.allSongs), empty: shuffles.empty(.allSongs),
                             failed: shuffles.failure(.allSongs), songsHere: online ? 0 : downloads.songsHere.count)
    }

    /// ShuffleSongs.tsx's button at the head of the list: Shuffle, or Getting ready… dimmed with why under it once its
    /// first page wouldn't come - none when there is nothing to shuffle.
    @ViewBuilder private var shuffleButton: some View {
        if let face = ShuffleButtonFace.of(allSongsCan) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: shuffleAll) {
                    Label(face.words, systemImage: "shuffle")
                }
                .buttonStyle(SecondaryPill())
                .disabled(!face.enabled)
                if let why = face.why {
                    Text(why)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    /// All songs' Shuffle, started here in the tap, nothing awaited first: the collection's first page in hand played
    /// as a library's shuffle at the songs level - or, while deadwax can't be reached, every song on this phone shuffled.
    private func shuffleAll() {
        switch allSongsCan {
        case .ready:
            guard let taken = shuffles.take(.allSongs, level: PlaylistPlay.songsLevel(player.normalization)) else { return }
            player.play(shuffled: taken)
        case .downloads:
            let here = downloads.songsHere
            guard !here.isEmpty else {
                player.say(PullShuffleWords.nothingHere)
                return
            }
            player.play(playlist: here, at: nil, shuffle: true)
        case .gettingReady, .failed, .nothingHere, .none:
            break
        }
    }

    // MARK: the list

    @ViewBuilder private var content: some View {
        let paging = songs.paging
        let online = reachability.online
        switch SongsBody.of(paging, online: online) {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                .accessibilityLabel(LibraryWords.loading)
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                failureNote
                Button(LibraryWords.tryAgain) {
                    if reachability.online { songs.retry() } else { reachability.tryNow() }
                }
                .disabled(reachability.probing)
            }
            .padding(.top, 8)
        case .offline:
            ShelfNote(SongWords.offline)
        case .empty(let words):
            ShelfNote(words)
        case .songs:
            let foot = SongsFoot.of(paging, online: online)
            if foot == .couldntRefresh, let failure = songs.failure {
                RefreshProblemNote(failure: failure) {
                    // as the page's other Try agains: nothing asked while deadwax can't be reached (question 34)
                    if reachability.online { songs.retry() } else { reachability.tryNow() }
                }
                    .padding(.vertical, 8)
            } else if !paging.countText.isEmpty {
                Text(paging.countText)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            rows(paging.items, online: online)
            footer(foot)
        }
    }

    /// Why the ask failed, in a listener's words.
    @ViewBuilder private var failureNote: some View {
        if let failure = songs.failure {
            ErrorNote(failure, retry: true)
        } else {
            ErrorNote(text: SongWords.offline)
        }
    }

    /// The rows - a song twice in one page is two rows, as the web keeps it, so each row is known by its place. Each row
    /// appearing is how far the reader got, and a row near the end of what is drawn asks for the next page as it
    /// appears (never while deadwax can't be reached - `resumed` then, once it is back).
    @ViewBuilder private func rows(_ items: [Song], online: Bool) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { (row: (offset: Int, element: Song)) in
            SongRow(song: row.element, dimmed: SongsList.dimmed(row.element, online: online, here: { (id: String) -> Bool in
                downloads.state(id).isHere
            }))
            .onAppear {
                songs.appeared(row.offset, online: reachability.online)
            }
        }
    }

    @ViewBuilder private func footer(_ foot: SongsFoot) -> some View {
        switch foot {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .accessibilityLabel(LibraryWords.loading)
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                failureNote
                Button(LibraryWords.tryAgain) {
                    if reachability.online { songs.retry() } else { reachability.tryNow() }
                }
                .disabled(reachability.probing)
            }
            .padding(.vertical, 12)
        case .couldntRefresh, .nothing:
            EmptyView()
        }
    }

    private func jump(_ proxy: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
        }
    }
}

/// One song's row (SongsView's): its cover at the rows' size, its title, its artist and album, opening its album on the
/// tab's path - and its ••• beside it, the song's own menu. Read as one: "Roads, Portishead · Dummy, opens its album".
/// Dimmed, and opening nothing, while deadwax can't be reached and the song isn't on this phone; a song with no album
/// opens nothing. Swiped right it adds the song to the queue, wherever its ••• offers Add to Queue - the swipe drawn by
/// hand, the list being a stack (AddToQueueSwipe.swift), with Add to Queue as the row's VoiceOver action.
struct SongRow: View {
    let song: Song
    var dimmed = false

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The row's ••• - and its swipe's: the one song, as a song, with its own album.
    private var menu: QueueMenuRequest {
        QueueMenuRequest(pick: PlaylistPlay.pick(song: song), album: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                opener
                    .addToQueueAction(menu)
                QueueMenu(request: menu) {
                    Image(systemName: "ellipsis")
                        .font(Typeface.symbol(.body).weight(.semibold))
                        .foregroundStyle(Palette.quiet)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
            }
            Divider().padding(.leading, LibraryRow.textInset)
        }
        // the list's own padding (`list(page:)`): the purple runs out to the screen's edge
        .addsToQueue(menu, in: .stack(inset: 16))
    }

    /// The row's link to its album - or, with none to open, the row alone.
    @ViewBuilder private var opener: some View {
        if let id = song.albumId, SongsList.opensAlbum(song) {
            NavigationLink(value: AppRoute.album(AlbumRoute(id: id, name: song.album, artist: song.artist,
                                                            coverArt: song.coverArt))) {
                face
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(SongWords.spoken(song))
            .accessibilityValue(dimmed ? DownloadWords.notOnPhone : "")
        } else {
            face
                .accessibilityElement(children: .combine)
                .accessibilityLabel(SongWords.spoken(song))
        }
    }

    private var face: some View {
        let line = PlaylistRules.songLine(song)
        return HStack(spacing: 12) {
            LibraryCover(id: song.coverArt, pixels: CoverSize.row)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(Corners.artShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title ?? "")
                    .foregroundStyle(.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if !line.isEmpty {
                    Text(line)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(dimmed ? Palette.off : 1)
    }
}
