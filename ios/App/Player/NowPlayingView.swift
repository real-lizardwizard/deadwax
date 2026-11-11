import DeadwaxCore
import SwiftUI

/// Now Playing, over the tabs: the cover, the title, the byline (Go to the album), the scrubber, the transport, and
/// Up Next and Info as sheets. STUB (the Player part's): working, plain - no scrubbing yet, the clocks only.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var showsUpNext = false
    @State private var showsInfo = false

    init() {}

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title2) }
                    .accessibilityLabel("Close")
                Spacer()
            }
            if let track = player.current?.track {
                CoverImage(id: track.coverArt, size: 320)
                    .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(spacing: 4) {
                    Text(track.title).font(.title3.bold()).multilineTextAlignment(.center)
                    let byline = PlayerWords.byline(artist: track.artist, album: track.album)
                    if let album = AlbumRoute(track: track) {
                        Button(byline) { navigation.openAlbum(album) }
                            .accessibilityLabel(PlayerWords.goToAlbum(byline))
                    } else {
                        Text(byline).foregroundStyle(Palette.quiet)
                    }
                    if let error = player.errorLine { Text(error).font(.footnote).foregroundStyle(Palette.quiet) }
                }
                HStack {
                    Text(PlayerWords.elapsed(shown: player.shownPosition))
                    Spacer()
                    Text(PlayerWords.remaining(shown: player.shownPosition, length: player.duration))
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Palette.quiet)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PlayerWords.scrubberName)
                .accessibilityValue(PlayerWords.scrubberValue(shown: player.shownPosition, length: player.duration))
                HStack(spacing: 40) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                        .accessibilityLabel("Previous")
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                    }
                    .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.title) }
                        .accessibilityLabel(PlayerWords.next)
                }
                HStack(spacing: 40) {
                    Button { showsInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("Info")
                    Button { showsUpNext = true } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("Up Next")
                }
                .font(.title3)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .sheet(isPresented: $showsUpNext) { UpNextScreen() }
        .sheet(isPresented: $showsInfo) { InfoView() }
    }
}
