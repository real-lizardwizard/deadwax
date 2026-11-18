import DeadwaxCore
import SwiftUI

// A right-click on an album's tile or row, or a playlist's row (the Mac app, slice 2 - notes/ios.md "The Mac app, slice
// 2: menus, keys, right-click and the window"): the ••• of the page it opens, drawn from the same items
// (QueueMenuItems) and the same request (QueueMenuRequest.album, .playlist) - less the page's Refresh, which is the page's
// own (⌘R there). A song's row needs none of this: its own •••'s request is in hand (Platform's `macContextMenu`).
//
// The album's songs, or the playlist's, are what the menu queues, and a tile hasn't got them: they are asked for each
// time the pointer rests on it (a quarter of a second - not for every tile the pointer crosses), as the page asks them -
// the answer kept with a download drawn meanwhile, then deadwax's. An album deadwax says is gone while songs of it are
// on this Mac is the page's "gone but here" one, its menu the page's then (`gone`: Add to Queue and Album info, no Add
// to a playlist…, Edit album or Download). Whatever was answered is let go the moment it may be out of date - Edit album
// wrote to the album (AppNavigation's albumWrites), or an apply gave it a new id, which is asked for from then on
// (AppNavigation.albumId); a write here changed the playlist (PlaylistsModel.lastChange) - so the menu never queues songs
// that are no longer there. With no answer yet the menu says Loading - a right-click before the rest is over, or
// while the ask is out - whenever one can come; with deadwax out of reach and none kept, and once deadwax has said
// there is nothing, there is no menu. Only on the Mac (Platform's `albumRightClick`, `playlistRightClick`): the
// iPhone's tiles and rows have no long press, and get none.

/// How long the pointer rests on a tile or row before its songs are asked for.
private let resting: Duration = .milliseconds(250)

/// What a tile or row's ask is keyed on: the pointer over it, and what it asks for - an answer for one of these is
/// never drawn for another.
private struct Asking: Hashable {
    let over: Bool
    let stamp: Stamp
}

/// What the answer in hand was asked for: who asked, the album's id now and how many writes it had had - or the
/// playlist's, and how many changes here it had had.
private struct Stamp: Hashable {
    let person: Int
    let id: String
    let writes: Int
}

/// An album's tile or row: the album page's •••, on a right-click.
struct AlbumRightClick: ViewModifier {
    let route: AlbumRoute

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation

    /// The answer in hand, and whether deadwax said the album is gone with songs of it here (the page's goneButHere).
    @State private var album: Album?
    @State private var gone = false
    /// deadwax said there is no such album, and none of it is here: no menu.
    @State private var nothing = false
    /// What `album` was asked for: an answer for anything else is let go.
    @State private var answered: Stamp?
    @State private var over = false
    @State private var asking = false
    /// Album info, from the menu: its sheet over the tile's page, as the album page's is over it.
    @State private var info: Album?

    /// The album's id now - an apply may have given it a new one - and its writes.
    private var stamp: Stamp {
        let id = navigation.albumId(route.id)
        return Stamp(person: server.person, id: id, writes: navigation.albumWrites[id] ?? 0)
    }

    func body(content: Content) -> some View {
        let stamp = self.stamp
        // the answer for what is asked for now; else the one kept with a download, as the page draws it meanwhile
        let shown = answered == stamp ? album : downloads.keptAlbum(stamp.id)
        let gone = answered == stamp && self.gone
        let nothing = answered == stamp && self.nothing
        content
            .contextMenu {
                if let shown, let request = request(shown, gone: gone) {
                    QueueMenuItems(request: request)
                } else if shown == nil, !nothing, reachability.online, server.client != nil {
                    Text(AlbumPageLines.loading)
                }
            }
            .onHover { (inside: Bool) -> Void in over = inside }
            .task(id: Asking(over: over, stamp: stamp)) {
                guard over, !asking else { return }
                try? await Task.sleep(for: resting)
                guard !Task.isCancelled else { return }
                // not called off when the pointer leaves - a menu opening over the tile takes it away
                asking = true
                Task { @MainActor in
                    await ask(stamp)
                    asking = false
                }
            }
            .sheet(item: $info) { (album: Album) in
                AlbumInfoSheet(album: album)
                    .macSheet()
            }
    }

    private func request(_ album: Album, gone: Bool) -> QueueMenuRequest? {
        QueueMenuRequest.album(album, gone: gone, permissions: server.access.permissions, navigation: navigation,
                               info: { info = album })
    }

    /// The album as its page asks it (AlbumModel.askAlbum): deadwax's answer; gone, the kept answer stays with songs of
    /// it here; any other failure keeps what is in hand. Let go should someone else have signed in meanwhile, or the
    /// album have been written to or moved.
    private func ask(_ asked: Stamp) async {
        guard reachability.online, let client = server.client else { return }
        let person = server.person
        let had = answered == asked ? album : downloads.keptAlbum(asked.id)
        do {
            let (found, _) = try await client.albumAnswered(id: asked.id)
            guard person == server.person, stamp == asked else { return }
            if let found {
                settle(asked, album: found, gone: false)
            } else {
                answeredGone(asked, had: had)
            }
        } catch {
            guard person == server.person, stamp == asked, !APIFailure.isCancellation(error) else { return }
            if AlbumGone.isGone(empty: false, failure: error) { answeredGone(asked, had: had) }
        }
    }

    /// deadwax says the album is gone: the answer in hand stays, as gone, while it is kept with a download and songs of
    /// it are here (AlbumModel.keepsKept); otherwise nothing.
    private func answeredGone(_ asked: Stamp, had: Album?) {
        if let had, downloads.keptAlbum(had.id) != nil, downloads.here(had.song ?? []).count > 0 {
            settle(asked, album: had, gone: true)
        } else {
            settle(asked, album: nil, gone: false)
        }
    }

    private func settle(_ asked: Stamp, album: Album?, gone: Bool) {
        self.album = album
        self.gone = gone
        nothing = album == nil
        answered = asked
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

    /// deadwax's answer, or nil with `nothing` (a 404: gone) - for `answered`'s stamp alone.
    @State private var answer: PlaylistWithSongs?
    @State private var nothing = false
    @State private var answered: Stamp?
    @State private var over = false
    @State private var asking = false
    /// One more at each write here that changed this playlist (PlaylistsModel.lastChange - its page asks again at each).
    @State private var changes = 0

    private var stamp: Stamp {
        Stamp(person: server.person, id: route.id, writes: changes)
    }

    func body(content: Content) -> some View {
        let stamp = self.stamp
        // the answer for now; else the one kept with a download or from its page (a write here keeps that one new)
        let shown = answered == stamp ? answer : downloads.keptPlaylist(route.id) ?? playlists.kept(route.id)
        let nothing = answered == stamp && self.nothing
        content
            .contextMenu {
                if let request = request(shown) {
                    QueueMenuItems(request: request)
                } else if shown == nil, !nothing, reachability.online, server.client != nil {
                    Text(AlbumPageLines.loading)
                }
            }
            .onHover { (inside: Bool) -> Void in over = inside }
            .task(id: Asking(over: over, stamp: stamp)) {
                guard over, !asking else { return }
                try? await Task.sleep(for: resting)
                guard !Task.isCancelled else { return }
                asking = true
                Task { @MainActor in
                    await ask(stamp)
                    asking = false
                }
            }
            .onChange(of: playlists.lastChange) { (_: PlaylistsModel.Change?, change: PlaylistsModel.Change?) -> Void in
                if change?.id == route.id { changes += 1 }
            }
    }

    /// As the page's bar has it: nothing while that page's Edit is open.
    private func request(_ shown: PlaylistWithSongs?) -> QueueMenuRequest? {
        guard let shown, navigation.editingPlaylist != route.id else { return nil }
        return QueueMenuRequest.playlist(shown, name: shown.playlist.name, songs: shown.songs)
    }

    /// The playlist as its page asks it: deadwax's answer; a 404 is gone, and has no menu, as the page's ••• hasn't; any
    /// other failure keeps what is in hand.
    private func ask(_ asked: Stamp) async {
        guard reachability.online, let client = server.client else { return }
        let person = server.person
        do {
            let found = try await client.playlist(id: route.id)
            guard person == server.person, stamp == asked else { return }
            answer = found
            nothing = false
            answered = asked
        } catch {
            guard person == server.person, stamp == asked, !APIFailure.isCancellation(error),
                  AlbumGone.isGone(empty: false, failure: error) else { return }
            answer = nil
            nothing = true
            answered = asked
        }
    }
}
