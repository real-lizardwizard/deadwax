import DeadwaxCore
import SwiftUI

/// The mini player above the tab bar, with something queued: the cover, the title and its second line
/// (PlayerWords.secondLine - the failure words, else the artist), Play/Pause and Next; a tap opens Now Playing.
/// STUB (the Player part's): working, plain.
struct MiniPlayerView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation

    init() {}

    var body: some View {
        if let track = player.current?.track {
            let line = PlayerWords.secondLine(error: player.errorLine, artist: track.artist)
            HStack(spacing: 12) {
                Button {
                    navigation.nowPlayingShown = true
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(id: track.coverArt, size: 44)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1)
                            if let line { Text(line).font(.footnote).foregroundStyle(Palette.quiet).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PlayerWords.miniPlayerLabel(title: track.title, line: line))
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .accessibilityLabel(PlayerWords.next)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 64)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
