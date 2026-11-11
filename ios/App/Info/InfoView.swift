import DeadwaxCore
import SwiftUI

/// Info (D8): what the song playing is and how it plays - its album, format, sample rate, bit depth, the level
/// applied, Gapless. STUB (the Info part's): the song's name and its album's.
struct InfoView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        NavigationStack {
            List {
                if let entry = player.current {
                    LabeledContent("Song", value: entry.track.title)
                    LabeledContent("Album", value: entry.track.album)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
