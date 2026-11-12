import DeadwaxCore
import SwiftUI

/// What a ••• queues: one song (a row's - queued as a song) or an album's songs (the album's own - queued as an album),
/// always in hand (Core's QueuePick), and the album they are from, which the player remembers as just added (Info,
/// and the album opening at once from Up Next).
struct QueueMenuRequest {
    let pick: QueuePick<Song>
    let album: Album
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
/// music didn't start from it - when it did, the mini player says so. The menu closes either way. Playlists' "Add to
/// a playlist…" is Phase 4's.
///
/// `request` is nil while there is nothing to queue (the album's songs not in yet): the ••• is then dimmed and opens
/// nothing. The label is the •••, drawn by the caller; its VoiceOver name is the caller's too ("More for Roads").
struct QueueMenu<Label: View>: View {
    let request: QueueMenuRequest?
    @ViewBuilder let label: () -> Label

    @Environment(PlayerModel.self) private var player

    var body: some View {
        Menu {
            if let request {
                Section(request.pick.title) {
                    ForEach(QueueChoice.allCases, id: \.self) { choice in
                        Button(choice.label) {
                            player.choose(choice, request.pick, album: request.album)
                        }
                    }
                }
            }
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .disabled(request == nil)
    }
}
