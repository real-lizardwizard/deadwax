import DeadwaxCore
import SwiftUI

/// Search, your library's half (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 3.1-3.5; the web's app/Search.tsx
/// and SearchRows.tsx): one list, Apple Music's way - Top results, then Artists, Albums and Songs, yours first in each -
/// from Navidrome's search3. The box is the navigation bar's (always drawn, question 2), the chips under it while it has
/// words; every rule and word is Core's (SearchState, SearchList, SearchWords) and SearchModel makes the asks.
///
/// - All: the list as drawn for the words - frozen once drawn, its lines (whose a row is) changing in place - each
///   section's first rows with See all; a kind view: that kind in full, More from your library when it is full.
/// - A song plays from its tap when its album's songs are in hand (▶), else its album's page opens (question 10); its
///   ••• is the album page's song menu, or the song's own before its album is in hand (question 11). An artist and an
///   album open their pages, pushed on this tab's stack.
/// - While deadwax can't be reached (question 5) nothing is asked: a list drawn for the words stays, songs not on this
///   phone dimmed; for new words, "Search works once deadwax is back."
/// - Navidrome known not to be there: the Library's gate words above the list, nothing asked of it.
struct SearchScreen: View {
    @Environment(SearchModel.self) private var search
    @Environment(ArtistsModel.self) private var artists
    @Environment(LibraryModel.self) private var library
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let state = search.state
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                    if !state.query.isEmpty {
                        chips
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: navigation.searchScrollToTop) { _, _ in
                // the Search tab tapped at its root: to the top of the list
                withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
            }
            .onChange(of: state.view) { _, _ in jump(proxy) }
            .onChange(of: state.drawn?.text) { _, _ in jump(proxy) }
        }
        .navigationTitle(SearchWords.title)
        .searchable(text: Binding(get: { search.text }, set: { (typed: String) -> Void in search.type(typed) }),
                    placement: .navigationBarDrawer(displayMode: .always), prompt: Text(SearchWords.prompt))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) { search.submitted() }
        .onAppear { search.shown() }
        .onChange(of: navigation.tab) { _, tab in
            if tab == .search { search.shown() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, navigation.tab == .search { search.shown() }
        }
        .onChange(of: reachability.online) { _, online in
            guard online else { return }
            search.shown()
            search.resumed()
        }
        .onChange(of: library.generations[.yours]) { _, _ in
            // your albums let go (an Add, a Remove, a star seen elsewhere): asked again, so whose a row is follows
            search.shown()
        }
        .onChange(of: search.navidromeAway == nil) { _, there in
            // Navidrome found again: what was skipped while it wasn't, asked
            if there { search.resumed() }
        }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
    }

    // MARK: the chips

    private var chips: some View {
        Picker(SearchWords.chipsLabel, selection: Binding(get: { search.state.view },
                                                          set: { (view: SearchView) -> Void in search.choose(view) })) {
            ForEach(SearchView.allCases) { (view: SearchView) in
                Text(SearchWords.chip(view)).tag(view)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(SearchWords.chipsLabel)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: what is drawn

    @ViewBuilder private var content: some View {
        let state = search.state
        let personal = search.personal
        if state.query.isEmpty {
            ShelfNote(SearchWords.hint(personal: personal))
        } else {
            if let closed = search.navidromeAway {
                SearchGateNote(closed: closed)
            }
            if let wanted = state.view.kind {
                kindView(wanted)
            } else {
                allView
            }
        }
    }

    /// The All view: the list drawn - kept while new words are asked - or the asking line before one is.
    @ViewBuilder private var allView: some View {
        let state = search.state
        let online = reachability.online
        if let drawn = state.drawn, online || drawn.text.utf16.elementsEqual(state.query.utf16) {
            DrawnList(drawn: drawn)
        } else if !online {
            ShelfNote(SearchWords.offline)
        } else if search.navidromeAway == nil {
            AskingLine(personal: search.personal)
        }
    }

    /// A kind view: the chip's own search3, its rows in its order.
    @ViewBuilder private func kindView(_ kind: SearchKind) -> some View {
        let state = search.state
        if let own = state.kindShown {
            switch own.state {
            case .asking:
                AskingLine(personal: search.personal)
            case .failed:
                FailureNote(failure: search.kindFailure) { search.tryKindAgain() }
            case .skipped:
                EmptyView()
            case .answered:
                // each key once (search3 can name a song twice)
                let rows: [SearchRow] = SearchList.drawable(SearchList.kindRows(
                    kind, rows: own.rows, text: state.query, allResults: state.results,
                    ownedArtists: search.owned?.artists ?? [], artistList: artists.list))
                if rows.isEmpty {
                    ShelfNote(SearchWords.nothing(SearchView(kind), state.query))
                } else {
                    SectionHead(kind: kind, seeAll: false)
                    let marks = search.marks
                    ForEach(rows) { (row: SearchRow) in
                        SearchRowView(row: row, marks: marks, top: false)
                    }
                    if own.full || own.more != .idle {
                        MoreButton(own: own, personal: search.personal)
                    }
                }
            }
        } else if !reachability.online {
            ShelfNote(SearchWords.offline)
        } else if search.navidromeAway == nil {
            AskingLine(personal: search.personal)
        }
    }
}

/// The list as drawn for some words: its failure or "nothing found", Top results, and each section's first rows with
/// See all - each row's line read from the marks as they are now.
private struct DrawnList: View {
    let drawn: SearchList.Drawn

    @Environment(SearchModel.self) private var search

    var body: some View {
        let marks = search.marks
        if drawn.failed {
            FailureNote(failure: search.failure) { search.tryAgain() }
        }
        if drawn.nothing {
            VStack(alignment: .leading, spacing: 6) {
                Text(SearchWords.nothing(.all, drawn.text))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SearchWords.checkSpelling)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        }
        if !drawn.top.isEmpty {
            Text(SearchWords.topResults)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(SearchList.drawable(drawn.top)) { (row: SearchRow) in
                SearchRowView(row: row, marks: marks, top: true)
            }
        }
        ForEach(drawn.sections) { (section: SearchList.Drawn.Section) in
            SectionHead(kind: section.kind, seeAll: true)
            ForEach(SearchList.drawable(section.rows)) { (row: SearchRow) in
                SearchRowView(row: row, marks: marks, top: false)
            }
        }
    }
}

/// A section's heading, with See all (All's).
private struct SectionHead: View {
    let kind: SearchKind
    let seeAll: Bool

    @Environment(SearchModel.self) private var search

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(SearchWords.section(kind))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if seeAll {
                Button(SearchWords.seeAll) { search.choose(SearchView(kind)) }
                    .accessibilityLabel(SearchWords.seeAllLabel(kind))
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 2)
    }
}

/// The line while the library is asked.
private struct AskingLine: View {
    let personal: Bool

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(SearchWords.searching(personal: personal))
                .foregroundStyle(Palette.quiet)
        }
        .accessibilityElement(children: .combine)
        .padding(.top, 12)
    }
}

/// A failure's words, and Try again (nothing asked while deadwax can't be reached - whether it is back, instead).
private struct FailureNote: View {
    let failure: (any Error)?
    let retry: () -> Void

    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure {
                ErrorNote(failure, retry: true)
            } else {
                // never drawn without its failure in hand (SearchModel keeps it with the list); said plainly if it is
                ErrorNote(text: reachability.online ? ErrorWords.other : SearchWords.offline)
            }
            Button(SearchWords.tryAgain) {
                if reachability.online { retry() } else { reachability.tryNow() }
            }
            .disabled(reachability.probing)
        }
        .padding(.vertical, 8)
    }
}

/// Navidrome known not to be there: the Library's gate words, above the list (the web's NeedsNavidrome), with its Try
/// again.
private struct SearchGateNote: View {
    let closed: NavidromeGate.Closed

    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(closed.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(closed.lines, id: \.self) { (line: String) in
                Text(line)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if closed.tryAgain {
                Button(NavidromeGate.tryAgain) {
                    Task { await library.checkNavidrome() }
                }
                .disabled(library.checkingNavidrome)
            }
        }
        .padding(.vertical, 8)
    }
}

/// A kind view's More from your library: Loading… while it asks, Try again after a failure.
private struct MoreButton: View {
    let own: KindLibrary
    let personal: Bool

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if own.more == .failed, let failure = search.moreFailure {
                ErrorNote(failure, retry: true)
            }
            Button {
                if reachability.online { search.more() } else { reachability.tryNow() }
            } label: {
                switch own.more {
                case .asking: Text(SearchWords.loading)
                case .failed: Text(SearchWords.tryAgain)
                case .idle: Text(SearchWords.moreFromLibrary(personal: personal))
                }
            }
            .buttonStyle(SecondaryPill())
            .disabled(own.more == .asking)
        }
        .padding(.top, 14)
    }
}

// MARK: the rows

/// One row - an artist, an album or a song - as the Library's rows: its cover (round for an artist), its title, and its
/// line, the facts truncating and the place never (searchList.ts `rowLine`). Read as one: "Roads, Song · Portishead ·
/// Dummy · in your library, plays it from its album".
struct SearchRowView: View {
    let row: SearchRow
    let marks: SearchMarks
    let top: Bool

    @Environment(SearchModel.self) private var search
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize

    // Each part its own small function, every value's type spelled out: the one body this was type-checked in 366 ms
    // (7291225's review), and CI's older Swift is slower still.
    var body: some View {
        let line: SearchList.Line = SearchList.line(row, marks, top: top)
        VStack(spacing: 0) {
            content(line)
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }

    @ViewBuilder private func content(_ line: SearchList.Line) -> some View {
        switch row {
        case .artist(let artist):
            link(AppRoute.artist(ArtistRoute(artist)), line, round: true, cover: artist.coverArt,
                 dimmed: dims(artist: artist.id))
        case .album(let album):
            link(AppRoute.album(AlbumRoute(album)), line, round: false, cover: album.coverArt,
                 dimmed: dims(album: album.id))
        case .song(let song):
            songRow(song, line)
        }
    }

    /// An artist's or an album's row: its page pushed on Search's stack.
    private func link(_ route: AppRoute, _ line: SearchList.Line, round: Bool, cover: String?,
                      dimmed: Bool) -> some View {
        let opacity: Double = dimmed ? Palette.off : 1
        let value: String = dimmed ? DownloadWords.notOnPhone : ""
        return NavigationLink(value: route) {
            face(line, round: round, cover: cover, plays: false)
                .opacity(opacity)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(value)
    }

    // MARK: offline

    /// Offline, an album with nothing on this phone (the Library's Albums).
    private func dims(album id: String) -> Bool {
        if reachability.online { return false }
        let download: AlbumDownload = downloads.album(id: id)
        return !download.hasSongsHere
    }

    /// Offline, an artist with no album on this phone (ArtistsScreen's `artistsHere`).
    private func dims(artist id: String) -> Bool {
        if reachability.online { return false }
        let here: Bool = downloads.downloadedAlbums.contains { (album: IndexAlbum) -> Bool in
            album.artistId == id && downloads.album(id: album.id).hasSongsHere
        }
        return !here
    }

    /// Offline, a song not on this phone.
    private func dims(song id: String) -> Bool {
        if reachability.online { return false }
        return !downloads.isHere(id)
    }

    // MARK: a song's

    /// The album a song plays from: asked for so its tap plays - or, while deadwax can't be reached, its copy on this
    /// phone.
    private func album(of song: Song) -> Album? {
        guard let id = song.albumId, !id.isEmpty else { return nil }
        if let ready = search.state.ready[id] { return ready }
        return reachability.online ? nil : downloads.keptAlbum(id)
    }

    /// What a song's tap plays: its album's songs (those on this phone, offline), with it among them.
    private func playable(_ song: Song) -> (album: Album, songs: [Song], at: Int)? {
        guard let album = album(of: song), let songs = album.song else { return nil }
        let shown: [Song] = reachability.online ? songs : OfflineAlbum.playable(songs, here: downloads.isHere)
        guard let at = shown.firstIndex(where: { (each: Song) -> Bool in each.id == song.id }) else { return nil }
        return (album, shown, at)
    }

    /// What VoiceOver adds of a song's tap - only where the tap does it (a dimmed row does nothing).
    private static func tapSaid(plays: Bool, opens: Bool, dimmed: Bool) -> String {
        if dimmed { return "" }
        if plays { return SearchWords.playsSaid }
        return opens ? SearchWords.opensSaid : ""
    }

    @ViewBuilder private func songRow(_ song: Song, _ line: SearchList.Line) -> some View {
        let plays: Bool = playable(song) != nil
        let dimmed: Bool = dims(song: song.id)
        let opens: Bool = !(song.albumId ?? "").isEmpty
        let opacity: Double = dimmed ? Palette.off : 1
        let said: String = spoken(line) + Self.tapSaid(plays: plays, opens: opens, dimmed: dimmed)
        let value: String = dimmed ? DownloadWords.notOnPhone : ""
        HStack(spacing: 4) {
            Button {
                tapped(song)
            } label: {
                face(line, round: false, cover: song.coverArt, plays: plays && !dimmed)
                    .opacity(opacity)
            }
            .buttonStyle(.plain)
            .disabled(dimmed || (!plays && !opens))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(said)
            .accessibilityValue(value)
            songMenu(song)
        }
    }

    private func songMenu(_ song: Song) -> some View {
        QueueMenu(request: menu(song)) {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.quiet)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
    }

    /// The song's ••• - as its album's when that album is in hand, else the song alone (Songs' row).
    private func menu(_ song: Song) -> QueueMenuRequest {
        if let album = album(of: song) {
            return QueueMenuRequest(pick: QueuePick.song(song, of: album), album: album)
        }
        return QueueMenuRequest(pick: PlaylistPlay.pick(song: song), album: nil)
    }

    /// A song's tap: its album played from it, in the tap with nothing awaited - or, with its album not in hand, the
    /// album's page (question 10).
    private func tapped(_ song: Song) {
        if let plays = playable(song) {
            player.play(songs: plays.songs, album: plays.album, at: plays.at)
        } else if let id = song.albumId, !id.isEmpty {
            navigation.open(.album(AlbumRoute(id: id, name: song.album, artist: song.artist, coverArt: song.coverArt)))
        }
    }

    // MARK: the face

    private func spoken(_ line: SearchList.Line) -> String {
        [row.title, line.said].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }

    private func face(_ line: SearchList.Line, round: Bool, cover: String?, plays: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        let titleLines: Int = large ? 3 : 1
        return HStack(spacing: 12) {
            picture(round: round, cover: cover)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .foregroundStyle(.primary)
                    .lineLimit(titleLines)
                lineText(line, large: large)
            }
            Spacer(minLength: 8)
            trailing(plays: plays)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func picture(round: Bool, cover: String?) -> some View {
        if round {
            ArtistPicture(id: cover, side: LibraryRow.cover, pixels: CoverSize.row)
        } else {
            LibraryCover(id: cover, pixels: CoverSize.row)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// The line under the title: the facts take the ellipsis, the place is never cut - at accessibility sizes, both
    /// as one, wrapping.
    @ViewBuilder private func lineText(_ line: SearchList.Line, large: Bool) -> some View {
        if line.said.isEmpty {
            EmptyView()
        } else if large {
            Text(line.said)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .lineLimit(2)
        } else {
            let place: String = line.line.isEmpty ? line.place : " \u{00B7} " + line.place
            HStack(spacing: 0) {
                if !line.line.isEmpty {
                    Text(line.line)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !line.place.isEmpty {
                    Text(place)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.quiet)
        }
    }

    /// ▶ for a song that plays from its tap, › for an artist.
    @ViewBuilder private func trailing(plays: Bool) -> some View {
        if plays {
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(Palette.quiet)
                .accessibilityHidden(true)
        } else if case .artist = row {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
