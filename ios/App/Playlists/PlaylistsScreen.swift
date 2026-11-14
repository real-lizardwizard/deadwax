import DeadwaxCore
import SwiftUI

/// The Library's Playlists page (Phase 4, phase4-library.md 3.2; the web's app/PlaylistsPage.tsx) - a page of the
/// Library's switch since slice 3b (2.8, 3.1): Yours, then Shared with you, then From files folded behind one row
/// ("From files (3)", opened in place for the app's run) - each in Navidrome's order (by name) and drawn only when it has
/// something (PlaylistRules.groups). A row OPENS its playlist and plays nothing (the gesture rule). Every word and line
/// is Core's (PlaylistRules, PlaylistWords, LibrarySwitchWords).
///
/// The list is PlaylistsModel's, one per person: asked afresh each time the page is the one shown (the app coming back
/// to the front on it included), drawn meanwhile from what is in hand; a failure with a list in hand leaves the list and
/// says so at the top; with none, why, and Try again. Find is the switch's: the playlists whose name holds every word
/// typed (PlaylistRules.found), From files opened while it finds - or "No playlists match “…”.". A pull shuffles (3.5),
/// never refreshes; the •••'s Refresh asks now. While deadwax can't be reached nothing is asked: the list in hand draws,
/// a playlist whose page isn't in hand with a song of it on this phone dimmed (it opens nothing), and with no list the
/// page says the playlists show once deadwax is back.
///
/// NEW PLAYLIST (slice 2, the web's PlaylistsPage.tsx): the bar's + (the switch's, on this page), and the empty page's
/// button, open a sheet with the name (NewPlaylistFields); Create makes an empty playlist as the person signed in and,
/// the page still showing, opens its page - else the notice says it was made ("Made Late night"). Each opening of the
/// sheet is its own: a slow Create answering after its sheet was swiped away and another opened closes nothing, and
/// only says so (PlaylistEdit.made). Not offered while deadwax can't be reached.
struct PlaylistsPage: View {
    /// One opening of New playlist's sheet.
    struct NewSheet: Identifiable, Equatable {
        let id = UUID()
    }

    /// Find's words - the switch's field, this page's own text in it.
    let typed: Binding<String>
    /// The page the switch shows.
    let current: Bool
    /// The page's pull to shuffle.
    let pulling: PullShuffling
    /// New playlist's sheet, while it is up - the bar's + opens it.
    @Binding var newSheet: NewSheet?

    @Environment(PlaylistsModel.self) private var playlists
    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(PlayerModel.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    /// From files opened - kept while the app runs.
    @State private var filesOpen = false
    /// The playlist just made, opened once its sheet has gone.
    @State private var made: PlaylistRoute?
    /// On screen (not covered by a page pushed over it).
    @State private var shown = false

    private static let edge: CGFloat = 16

    /// The page is on top of its tab and the one the switch shows: a playlist made opens; otherwise the notice says so.
    private var showing: Bool { shown && current }

    var body: some View {
        let online = reachability.online
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                        .overlay(alignment: .bottom) {
                            PullShuffleGraphic(state: pulling.state, can: pulling.can)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    content(online: online)
                }
                .padding(.horizontal, Self.edge)
                .padding(.bottom, 24)
            }
            .pullsToShuffle(pulling)
            .onChange(of: typed.wrappedValue) { _, _ in jump(proxy) }
            .onChange(of: navigation.libraryScrollToTop) { _, _ in
                // the Library tab tapped at its root: the page shown goes to its top
                guard showing else { return }
                withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
            }
        }
        .sheet(item: $newSheet, onDismiss: openMade) { (sheet: NewSheet) in
            NavigationStack {
                List {
                    NewPlaylistFields { name in
                        try await make(name, from: sheet)
                    } cancel: {
                        if newSheet == sheet { newSheet = nil }
                    }
                }
                .navigationTitle(PlaylistWords.newPlaylistTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { shown = true }
        .onDisappear { shown = false }
        .task(id: "\(server.person)|\(online)|\(current)") {
            // the page shown (and shown again): asked afresh - nothing while deadwax can't be reached
            guard online, current else { return }
            await playlists.ask(fresh: true)
        }
        .onChange(of: scenePhase) { _, phase in
            // the app back in front is the page shown again (the web's): asked afresh
            guard phase == .active, current, reachability.online else { return }
            Task { await playlists.ask(fresh: true) }
        }
    }

    @ViewBuilder private func content(online: Bool) -> some View {
        if let list = playlists.list {
            if online, let failure = playlists.failure {
                ListFailedNote(failure: failure, retry: nil)
                    .padding(.top, 8)
            }
            if list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(PlaylistWords.playlistsEmpty)
                    Text(PlaylistWords.playlistsEmptyHow)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if online {
                        Button(PlaylistWords.newPlaylist) { newSheet = NewSheet() }
                            .buttonStyle(SecondaryPill())
                            .padding(.top, 4)
                    }
                }
                .foregroundStyle(Palette.quiet)
                .padding(.top, 8)
            } else {
                let found = PlaylistRules.found(list, typed: typed.wrappedValue)
                if found.isEmpty {
                    Text(LibrarySwitchWords.noPlaylistMatch(typed.wrappedValue))
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                } else {
                    groups(PlaylistRules.groups(found), online: online, finding: Find.finding(typed.wrappedValue))
                }
            }
        } else if !online {
            // (slice 3) no list in hand: the downloaded playlists still open, and play
            let downloaded = PlaylistDownloads.shelf(downloads.playlists.kept)
            Text(downloaded.isEmpty ? PlaylistWords.offlineList : PlaylistDownloadWords.offlineDownloaded)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
            ForEach(PlaylistRules.found(downloaded, typed: typed.wrappedValue)) { (playlist: Playlist) in
                PlaylistRow(playlist: playlist, dimmed: !downloads.playlistPlaysOffline(playlist.id), inList: false)
            }
        } else if let failure = playlists.failure {
            ListFailedNote(failure: failure) { Task { await playlists.ask(fresh: true) } }
                .padding(.top, 8)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                .accessibilityLabel(PlaylistWords.loading)
        }
    }

    /// New playlist's Create, from `sheet`: an empty playlist, made as the person signed in - opened once that sheet has
    /// gone (or at once, it closed meanwhile with none opened since and the page still showing), else said, closing
    /// nothing. Refused: thrown, for the sheet to say.
    private func make(_ name: String, from sheet: NewSheet) async throws {
        let new: PlaylistWithSongs
        do {
            new = try await playlists.create(name: name, songIDs: [], picker: false)
        } catch is PlaylistsModel.Superseded {
            return
        }
        let route = PlaylistRoute(new.playlist)
        switch PlaylistEdit.made(sentFrom: sheet, up: newSheet, shown: showing) {
        case .closeThenOpen:
            made = route
            newSheet = nil
        case .open:
            navigation.open(.playlist(route))
        case .say:
            player.say(PlaylistWords.made(new.playlist.name))
        }
    }

    /// The sheet gone: the playlist it made, opened.
    private func openMade() {
        guard let route = made else { return }
        made = nil
        if showing {
            navigation.open(.playlist(route))
        } else {
            player.say(PlaylistWords.made(route.preview?.name ?? ""))
        }
    }

    @ViewBuilder private func groups(_ groups: PlaylistGroups, online: Bool, finding: Bool) -> some View {
        if !groups.yours.isEmpty {
            LibraryHeader(label: PlaylistWords.yours)
            rows(groups.yours, online: online)
        }
        if !groups.shared.isEmpty {
            LibraryHeader(label: PlaylistWords.shared)
            rows(groups.shared, online: online)
        }
        if !groups.files.isEmpty {
            // opened while Find finds: a match folded away would read as none
            DisclosureGroup(isExpanded: finding ? .constant(true) : $filesOpen) {
                rows(groups.files, online: online)
            } label: {
                Text(PlaylistWords.files(groups.files.count))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder private func rows(_ list: [Playlist], online: Bool) -> some View {
        ForEach(list) { playlist in
            let dimmed = !online && !playlists.playsOffline(playlist.id, here: downloads.isHere)
                && !downloads.playlistPlaysOffline(playlist.id)
            PlaylistRow(playlist: playlist, dimmed: dimmed, inList: false)
        }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
    }
}

/// Downloaded playlists (Phase 4, slice 3; phase4-library.md 2.5, question 15): every playlist downloaded to this phone,
/// by name, each a row opening its page - drawn from what this phone keeps, so it lists them with no connection too
/// (one with nothing of it here yet dimmed then). Reached from the Library's Downloaded (the •••'s, since slice 3b): no
/// place of its own above the albums. With none, what is empty and how to fill it. A pull
/// looks at deadwax for their changes now - or, with no connection, whether deadwax is back.
struct DownloadedPlaylistsScreen: View {
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let online = reachability.online
        let shelf = PlaylistDownloads.shelf(downloads.playlists.kept)
        List {
            if shelf.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(PlaylistDownloadWords.noneYet)
                    Text(PlaylistDownloadWords.noneYetHow)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.quiet)
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(shelf) { (playlist: Playlist) in
                    PlaylistRow(playlist: playlist, dimmed: !online && !downloads.playlistPlaysOffline(playlist.id))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(PlaylistDownloadWords.place)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            downloads.playlists.look(.byHand)
        }
        .task { await downloads.followProgress() }
    }
}

/// One playlist's row (PlaylistsPage.tsx `row`): the mosaic at the rows' size - or the playlist mark on a quiet square
/// for one with none - the name, its line, and the chevron; a page pushed on the tab's path. Read as one: "Late night,
/// 12 songs · 48 min". Dimmed, and opening nothing, while deadwax can't be reached and nothing of it plays here. In a
/// List (Downloaded playlists) the List draws its chevron and separator; on the Library's Playlists page, a scroll view
/// since slice 3b, the row draws its own, at the same height.
struct PlaylistRow: View {
    let playlist: Playlist
    var dimmed = false
    /// In a List, which draws the chevron, the separator and the row's padding.
    var inList = true

    var body: some View {
        if inList {
            link
        } else {
            VStack(spacing: 0) {
                link
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                Divider().padding(.leading, LibraryRow.textInset)
            }
        }
    }

    private var link: some View {
        NavigationLink(value: AppRoute.playlist(PlaylistRoute(playlist))) {
            HStack(spacing: 12) {
                PlaylistCover(id: playlist.coverArt, side: LibraryRow.cover, pixels: CoverSize.row, corner: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .foregroundStyle(.primary)
                    Text(PlaylistRules.rowLine(playlist))
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
                .lineLimit(2)
                if !inList {
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(dimmed ? Palette.off : 1)
        }
        .disabled(dimmed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(PlaylistRules.rowLine(playlist))")
        .accessibilityValue(dimmed ? DownloadWords.notOnPhone : "")
    }
}

/// A playlist's cover: Navidrome's 2x2 mosaic at exactly `pixels` (LibraryCover), or - for a playlist with none (an
/// empty one) - the playlist mark on the empty cover's square.
struct PlaylistCover: View {
    let id: String?
    let side: CGFloat
    let pixels: Int
    let corner: CGFloat

    var body: some View {
        Group {
            if let id {
                LibraryCover(id: id, pixels: pixels)
            } else {
                ZStack {
                    Palette.coverEmpty
                    Image(systemName: "music.note.list")
                        .font(.system(size: side * 0.4, weight: .regular))
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// "Couldn't list your playlists. <why>" - the why in a listener's words (ErrorWords, as the web's sayError), the error's
/// own words under it for whoever runs deadwax - and Try again when there is no list to show.
private struct ListFailedNote: View {
    let failure: any Error
    let retry: (() -> Void)?

    @Environment(ServerModel.self) private var server

    var body: some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: retry != nil)
        VStack(alignment: .leading, spacing: 8) {
            ErrorNote(text: PlaylistWords.listFailed(line.said), detail: line.detail)
            if let retry {
                Button(PlaylistWords.tryAgain, action: retry)
            }
        }
        .padding(.vertical, 4)
    }
}
