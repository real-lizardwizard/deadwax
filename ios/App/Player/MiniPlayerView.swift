import DeadwaxCore
import SwiftUI

/// The mini player above the tab bar, whenever something is queued (ui/src/player/MiniPlayer.tsx): the cover, the
/// title and its second line - the player's failure words, a skipped song's notice included, else the artist
/// (PlayerWords.secondLine) - Play/Pause (busy while the song loads) and Next, and a hairline along its bottom edge
/// for how far into the song it is (PlayerWords.progress). The bar, not its buttons, opens Now Playing; VoiceOver
/// reads it as "Now playing: Roads, Portishead - open" (PlayerWords.miniPlayerLabel).
struct MiniPlayerView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation

    /// The bar's height (--pl-mini-height) and its cover's.
    private static let height: CGFloat = 64
    private static let cover: CGFloat = 48

    init() {}

    var body: some View {
        if let track = player.current?.track {
            let line = PlayerWords.secondLine(error: player.errorLine, artist: track.artist)
            HStack(spacing: 4) {
                Button {
                    navigation.nowPlayingShown = true
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(id: track.coverArt, size: Self.cover)
                            .frame(width: Self.cover, height: Self.cover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if let line, !line.isEmpty {
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.quiet)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PlayerWords.miniPlayerLabel(title: track.title, line: line))

                Button { player.toggle() } label: {
                    ZStack {
                        if player.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(PlayerWords.next)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(minHeight: Self.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottom) { Hairline() }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// The hairline along the mini player's bottom edge: the part of the song played (MiniPlayer.tsx Progress) - a view of
/// its own, so only it is drawn again as the position moves.
private struct Hairline: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let done = PlayerWords.progress(position: player.shownPosition, duration: player.duration)
        GeometryReader { line in
            Rectangle()
                .fill(Palette.accent)
                .frame(width: line.size.width * (done.isFinite ? min(max(done, 0), 1) : 0))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
