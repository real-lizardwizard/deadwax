import DeadwaxCore
import SwiftUI

/// What a ••• queues: one song (a row's - queued as a song) or an album's songs (the album's own - queued as an album),
/// always in hand (Core's QueuePick), and the album they are from, which the player remembers as just added (Info,
/// and the album opening at once from Up Next). A playlist's songs (Phase 4) name no album: each is queued with its own
/// (PlaylistPlay), and the playlist's ••• for all of them offers no download items until a playlist downloads as one
/// (slice 3 - phase4-library.md question 7).
struct QueueMenuRequest {
    let pick: QueuePick<Song>
    /// The album the songs are from - nil for a playlist's, each song with its own.
    let album: Album?
    /// The album is gone from the collection (its songs on this phone still play): no Download.
    var gone = false
    /// The download items under Play Next and Play Last.
    var offersDownload = true
}

/// The queue menu (screens.md 5; the web's app/QueueMenu.tsx): Play Next and Play Last, opened FROM the ••• tapped -
/// a SwiftUI Menu on the button, as Apple's own ••• are. It was a confirmationDialog on the album page until James's
/// check of 0.2 (2): since iOS 26 a confirmation dialog is a popover from the view it is attached to, here the page,
/// so it came up away from the ••• (notes/ios.md, "The ••• menus open from the •••"). Titled with what it queues
/// (QueuePick.title - the song's or the album's name, or "Up Next"), as the dialog was. There is no Cancel row: a menu
/// closes with a tap anywhere else (QueuePickWords.cancel stays, the web's word, held to its fixture). The order is
/// fixed (`menuOrder(.fixed)`), so Play Next is first whichever way the menu opens.
///
/// A choice is carried out in its tap, nothing awaited first (the gesture rule - Play Next with nothing playing starts
/// the music): `PlayerModel.choose`, which queues the songs at the level QueuePick.choose says (an album's ••• as an
/// album, a song's as a song), remembers the album, and says the notice (D11, "Playing next: Roads") only when the
/// music didn't start from it - when it did, the mini player says so. The menu closes either way.
///
/// Phase 4, slice 2: "Add to a playlist…", third, as the web's - the same songs into one of your playlists: the menu
/// closes and the picker opens over the tabs (AppNavigation.playlistPick, PlaylistPicker) with them in hand. It plays
/// nothing. Left out while deadwax can't be reached (a playlist is Navidrome's, written through deadwax) and for an
/// album gone from the collection.
///
/// `request` is nil while there is nothing to queue (the album's songs not in yet): the ••• is then dimmed and opens
/// nothing. The label is the •••, drawn by the caller; its VoiceOver name is the caller's too ("More for Roads").
///
/// Phase 2 (phase2-downloads.md 3.4): a second section under them, the song's or the album's download items
/// (DownloadMenuSection), and every item carries its symbol, as Apple's menus do. While deadwax can't be reached, Play
/// Next and Play Last queue only what is on this phone - and are left out for a song that isn't - while Download stays
/// (it waits for deadwax).
struct QueueMenu<Label: View>: View {
    let request: QueueMenuRequest?
    @ViewBuilder let label: () -> Label

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Menu {
            if let request {
                if let pick = playable(request) {
                    Section(request.pick.title) {
                        ForEach(QueueChoice.allCases, id: \.self) { choice in
                            Button(choice.label, systemImage: Self.symbol(choice)) {
                                player.choose(choice, pick, album: request.album)
                            }
                        }
                        if reachability.online, !request.gone, !request.pick.tracks.isEmpty {
                            Button(PlaylistWords.addToAPlaylistRow, systemImage: PlaylistWords.addSymbol) {
                                navigation.playlistPick = PlaylistPickRequest(PlaylistPick(request.pick))
                            }
                        }
                    }
                }
                if request.offersDownload {
                    DownloadMenuSection(songs: request.pick.tracks,
                                        album: request.pick.queuedAs == .album ? request.album : nil,
                                        gone: request.gone, name: request.pick.title)
                }
            }
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .disabled(request == nil)
    }

    /// What Play Next and Play Last queue: the pick - offline, its songs on this phone (nil: none).
    private func playable(_ request: QueueMenuRequest) -> QueuePick<Song>? {
        guard !reachability.online || request.gone else { return request.pick }
        let here = OfflineAlbum.playable(request.pick.tracks, here: downloads.isHere)
        guard !here.isEmpty else { return nil }
        return QueuePick(label: request.pick.label, tracks: here, albumIds: request.pick.albumIds,
                         queuedAs: request.pick.queuedAs)
    }

    /// Play Next's and Play Last's symbols (iOS 16.0).
    static func symbol(_ choice: QueueChoice) -> String {
        choice == .next ? DownloadWords.playNextSymbol : DownloadWords.playLastSymbol
    }
}
