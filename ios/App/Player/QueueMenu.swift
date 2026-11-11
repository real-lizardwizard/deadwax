import DeadwaxCore
import SwiftUI

/// What a ••• opened the queue menu with: one song (a row's - queued as a song) or an album's songs (the album's own -
/// queued as an album), always in hand (Core's QueuePick), and the album they are from, which the player remembers as
/// just added (Info, and the album opening at once from Up Next).
struct QueueMenuRequest: Identifiable {
    let id = UUID()
    let pick: QueuePick<Song>
    let album: Album
}

/// The queue menu (screens.md 5; the web's app/QueueMenu.tsx): Play Next, Play Last and Cancel, over the page that
/// opened it, titled with what it was opened with (QueuePick.title - the song's or the album's name, or "Up Next").
///
/// A choice is carried out in its tap, nothing awaited first (the gesture rule - Play Next with nothing playing starts
/// the music): `PlayerModel.choose`, which queues the songs at the level QueuePick.choose says (an album's ••• as an
/// album, a song's as a song), remembers the album, and says the notice (D11, "Playing next: Roads") only when the
/// music didn't start from it - when it did, the mini player says so. The menu closes either way. Playlists' "Add to a
/// playlist…" is Phase 4's.
struct QueueMenu: ViewModifier {
    @Binding var request: QueueMenuRequest?

    @Environment(PlayerModel.self) private var player

    func body(content: Content) -> some View {
        content.confirmationDialog(
            request?.pick.title ?? "",
            isPresented: Binding(get: { request != nil }, set: { shown in if !shown { request = nil } }),
            titleVisibility: .visible,
            presenting: request
        ) { asked in
            ForEach(QueueChoice.allCases, id: \.self) { choice in
                Button(choice.label) {
                    player.choose(choice, asked.pick, album: asked.album)
                }
            }
            Button(QueuePickWords.cancel, role: .cancel) {}
        }
    }
}

extension View {
    /// The queue menu, shown while `request` holds what a ••• opened it with (set it in the •••'s tap; the menu sets
    /// it back to nil as it closes).
    func queueMenu(_ request: Binding<QueueMenuRequest?>) -> some View {
        modifier(QueueMenu(request: request))
    }
}
