import DeadwaxCore
import SwiftUI

/// Now Playing's ••• (app/ActionMenu.tsx): Info, and Go to album for a song that names its album - left out, not
/// greyed, for one that doesn't. Phase 1 has neither the web's Add to a playlist… nor its pin. The button's name says
/// what the menu holds (NowPlayingWords.more). A SwiftUI Menu on the button, opened from it, as the album page's •••
/// are (QueueMenu): it was a confirmationDialog on the button until the queue menus moved, and a menu has no Cancel
/// row - a tap anywhere else closes it. The order is fixed, Info first.
struct NowPlayingMenu: View {
    /// The song playing names its album: Go to album is in the menu.
    let hasAlbum: Bool
    let onInfo: () -> Void
    let onAlbum: () -> Void

    var body: some View {
        Menu {
            Button(NowPlayingWords.info, action: onInfo)
            if hasAlbum {
                Button(NowPlayingWords.goToAlbum, action: onAlbum)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        // drawn as the plain button it was (no tint): a button-styled menu with .buttonStyle, as Apple pairs them
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(NowPlayingWords.more(hasAlbum: hasAlbum))
    }
}

/// The album a queue entry goes to, from Now Playing's byline, its ••• and Info's album card (App.tsx goToAlbum):
/// the album as its page last loaded it, when the queue was played from it - else a stub of what the entry knows
/// (its id, its album's name and its cover), which the page draws while the album loads.
@MainActor
enum PlayedAlbum {
    static func route(id: String?, track: QueueTrack, player: PlayerModel) -> AlbumRoute? {
        guard let id, !id.isEmpty else { return nil }
        if let album = player.playedAlbum(id: id) { return AlbumRoute(album) }
        return AlbumRoute(id: id, name: track.album.isEmpty ? nil : track.album, coverArt: track.coverArt)
    }

    static func route(_ track: QueueTrack, player: PlayerModel) -> AlbumRoute? {
        route(id: track.albumId, track: track, player: player)
    }
}
