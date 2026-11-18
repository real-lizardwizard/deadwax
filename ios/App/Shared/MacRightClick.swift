import DeadwaxCore
import SwiftUI

// A right-click on an album's tile or row, or a playlist's row (the Mac app, slice 2 - notes/ios.md "The Mac app, slice
// 2: menus, keys, right-click and the window"): the ••• of the page it opens, drawn from the same items
// (QueueMenuItems) and the same request (QueueMenuRequest.album, .playlist) - less the page's Refresh, which is the page's
// own (⌘R there). A song's row needs none of this: its own •••'s request is in hand (Platform's `macContextMenu`).
//
// The album's songs, or the playlist's, are what the menu queues, and a tile hasn't got them: they are asked for as the
// pointer rests on it (a quarter of a second - not for every tile the pointer crosses), the answer kept with a download
// drawn first, as the page draws it. A right-click before they are in says Loading; with deadwax out of reach and none
// kept, there is no menu, as there is nothing to queue. Only on the Mac (Platform's `albumRightClick`,
// `playlistRightClick`): the iPhone's tiles and rows have no long press, and get none.

/// How long the pointer rests on a tile or row before its songs are asked for.
private let resting: Duration = .milliseconds(250)

/// An album's tile or row: the album page's •••, on a right-click.
struct AlbumRightClick: ViewModifier {
    let route: AlbumRoute

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation

    @State private var album: Album?
    @State private var over = false
    @State private var asking = false
    /// Album info, from the menu: its sheet over the tile's page, as the album page's is over it.
    @State private var info: Album?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let album, let request = request(album) {
                    QueueMenuItems(request: request)
                } else if asking {
                    Text(AlbumPageLines.loading)
                }
            }
            .onHover { (inside: Bool) -> Void in over = inside }
            .task(id: over) {
                guard over, album == nil, !asking else { return }
                try? await Task.sleep(for: resting)
                guard !Task.isCancelled else { return }
                // not called off when the pointer leaves - a menu opening over the tile takes it away
                asking = true
                Task { @MainActor in
                    await ask()
                    asking = false
                }
            }
            .sheet(item: $info) { (album: Album) in
                AlbumInfoSheet(album: album)
            }
    }

    private func request(_ album: Album) -> QueueMenuRequest? {
        QueueMenuRequest.album(album, gone: false, permissions: server.access.permissions, navigation: navigation,
                               info: { info = album })
    }

    /// The album as the page asks it: the answer kept with a download first, then deadwax's - dropped should someone
    /// else have signed in meanwhile.
    private func ask() async {
        if let kept = downloads.keptAlbum(route.id) { album = kept }
        guard reachability.online, let client = server.client else { return }
        let person = server.person
        guard let answer = try? await client.albumAnswered(id: route.id), person == server.person,
              let found = answer.album else { return }
        album = found
    }
}

/// A playlist's row: its page's •••, on a right-click.
struct PlaylistRightClick: ViewModifier {
    let route: PlaylistRoute

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation

    @State private var answer: PlaylistWithSongs?
    @State private var over = false
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let request {
                    QueueMenuItems(request: request)
                } else if asking {
                    Text(AlbumPageLines.loading)
                }
            }
            .onHover { (inside: Bool) -> Void in over = inside }
            .task(id: over) {
                guard over, answer == nil, !asking else { return }
                try? await Task.sleep(for: resting)
                guard !Task.isCancelled else { return }
                asking = true
                Task { @MainActor in
                    await ask()
                    asking = false
                }
            }
    }

    /// As the page's bar has it: nothing while that page's Edit is open.
    private var request: QueueMenuRequest? {
        guard let answer, navigation.editingPlaylist != route.id else { return nil }
        return QueueMenuRequest.playlist(answer, name: answer.playlist.name, songs: answer.songs)
    }

    /// The playlist as its page asks it: the answer this phone keeps for a download, or the one kept from its page,
    /// first; then deadwax's.
    private func ask() async {
        if let kept = downloads.keptPlaylist(route.id) ?? playlists.kept(route.id) { answer = kept }
        guard reachability.online, let client = server.client else { return }
        let person = server.person
        guard let found = try? await client.playlist(id: route.id), person == server.person else { return }
        answer = found
    }
}
