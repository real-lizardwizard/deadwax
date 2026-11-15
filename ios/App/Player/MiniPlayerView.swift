import DeadwaxCore
import SwiftUI

/// The mini player above the tab bar, whenever something is queued (ui/src/player/MiniPlayer.tsx): the cover, the
/// title and its second line - the player's failure words, a skipped song's notice included, else the artist
/// (PlayerWords.secondLine) - Play/Pause (busy while the song loads) and Next, each at least 44 points and growing with
/// the text size, and a hairline along its bottom edge
/// for how far into the song it is (PlayerWords.progress). The bar, not its buttons, opens Now Playing; VoiceOver
/// reads it as "Now playing: Roads, Portishead - open" (PlayerWords.miniPlayerLabel). Squared since the squared look
/// (James: "maybe square off the slider and the bar at the bottom and the now playing bar as well"): a card's corners,
/// its cover a cover's (Corners).
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
                            .clipShape(Corners.artShape)
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
                        // the glyph keeps its room under the spinner, so the button doesn't change size as it loads
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .opacity(player.isLoading ? 0 : 1)
                        if player.isLoading {
                            ProgressView()
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(PlayerWords.next)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(minHeight: Self.height)
            .background(.regularMaterial, in: Corners.cardShape)
            .overlay(alignment: .bottom) { Hairline() }
            .clipShape(Corners.cardShape)
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
