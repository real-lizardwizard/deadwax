import DeadwaxCore
import SwiftUI

/// The Library's Playlists (Phase 4, phase4-library.md 3.2; the web's app/PlaylistsPage.tsx): Yours, then Shared with
/// you, then From files folded behind one row ("From files (3)", opened in place for the screen's life) - each in
/// Navidrome's order (by name) and drawn only when it has something (PlaylistRules.groups). A row OPENS its playlist and
/// plays nothing (the gesture rule). Every word and line is Core's (PlaylistRules, PlaylistWords).
///
/// The list is PlaylistsModel's, one per person: asked afresh as the screen shows and each time it shows again (the app
/// coming back to the front included), drawn
/// meanwhile from what is in hand; a failure with a list in hand leaves the list and says so under the title; with
/// none, why, and Try again. Pull to refresh asks now. While deadwax can't be reached nothing is asked: the list in hand
/// draws, a playlist whose page isn't in hand with a song of it on this phone dimmed (it opens nothing), and with no list
/// the screen says the playlists show once deadwax is back. New playlist is slice 2's.
struct PlaylistsScreen: View {
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(\.scenePhase) private var scenePhase
    /// From files opened - the screen's own: leaving it folds it again.
    @State private var filesOpen = false

    var body: some View {
        let online = reachability.online
        List {
            if let list = playlists.list {
                if online, let failure = playlists.failure {
                    ListFailedNote(failure: failure, retry: nil)
                        .listRowSeparator(.hidden)
                }
                if list.isEmpty {
                    Text(PlaylistWords.playlistsEmpty)
                        .foregroundStyle(Palette.quiet)
                        .listRowSeparator(.hidden)
                } else {
                    groups(PlaylistRules.groups(list), online: online)
                }
            } else if !online {
                Text(PlaylistWords.offlineList)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
            } else if let failure = playlists.failure {
                ListFailedNote(failure: failure) { Task { await playlists.ask(fresh: true) } }
                    .listRowSeparator(.hidden)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(PlaylistWords.loading)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(PlaylistWords.title)
        .navigationBarTitleDisplayMode(.large)
        .task(id: "\(server.person)|\(online)") {
            // shown (and shown again): asked afresh - nothing while deadwax can't be reached
            guard online else { return }
            await playlists.ask(fresh: true)
        }
        .refreshable {
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            await playlists.ask(fresh: true)
        }
        .onChange(of: scenePhase) { _, phase in
            // the app back in front is the screen shown again (the web's): asked afresh
            guard phase == .active, reachability.online else { return }
            Task { await playlists.ask(fresh: true) }
        }
    }

    @ViewBuilder private func groups(_ groups: PlaylistGroups, online: Bool) -> some View {
        if !groups.yours.isEmpty {
            LibraryHeader(label: PlaylistWords.yours)
                .listRowSeparator(.hidden)
            rows(groups.yours, online: online)
        }
        if !groups.shared.isEmpty {
            LibraryHeader(label: PlaylistWords.shared)
                .listRowSeparator(.hidden)
            rows(groups.shared, online: online)
        }
        if !groups.files.isEmpty {
            DisclosureGroup(isExpanded: $filesOpen) {
                rows(groups.files, online: online)
            } label: {
                Text(PlaylistWords.files(groups.files.count))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private func rows(_ list: [Playlist], online: Bool) -> some View {
        ForEach(list) { playlist in
            let dimmed = !online && !playlists.playsOffline(playlist.id, here: downloads.isHere)
            PlaylistRow(playlist: playlist, dimmed: dimmed)
        }
    }
}

/// One playlist's row (PlaylistsPage.tsx `row`): the mosaic at the rows' size - or the playlist mark on a quiet square
/// for one with none - the name, its line, and the chevron; a page pushed on the tab's path. Read as one: "Late night,
/// 12 songs · 48 min". Dimmed, and opening nothing, while deadwax can't be reached and nothing of it plays here.
struct PlaylistRow: View {
    let playlist: Playlist
    var dimmed = false

    var body: some View {
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
            }
            .padding(.vertical, 4)
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
