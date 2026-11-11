import DeadwaxCore
import SwiftUI

/// Up Next (Core's `UpNextView` is what it draws, so this is the screen): the song playing, Playing Next, the list
/// and its "more", Repeat One's line. STUB (the Up Next part's): the rows, a tap jumping to one.
struct UpNextScreen: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        let view = player.upNext
        NavigationStack {
            List {
                if let playing = view.playing {
                    Section { Text(playing.title) }
                }
                if !view.added.isEmpty {
                    Section {
                        ForEach(view.added, id: \.key) { row($0) }
                    }
                }
                if let list = view.list {
                    Section(list.title) {
                        ForEach(list.rows, id: \.key) { row($0) }
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ row: UpNextRow) -> some View {
        Button {
            player.jump(to: row.key)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.track.title)
                Text(row.track.artist).font(.footnote).foregroundStyle(Palette.quiet)
            }
        }
    }
}
