import DeadwaxCore
import SwiftUI

/// An album's page, by Navidrome's album id; what the row knew (name, artist, cover) drawn while it loads. STUB (the
/// Album part's): the album's songs as a plain list - a tap plays the album from that song, Play from the top.
struct AlbumView: View {
    let route: AlbumRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @State private var album: Album?
    @State private var failure: (any Error)?
    @State private var gone = false

    init(route: AlbumRoute) {
        self.route = route
    }

    init(id: String, name: String? = nil, artist: String? = nil, coverArt: String? = nil) {
        self.init(route: AlbumRoute(id: id, name: name, artist: artist, coverArt: coverArt))
    }

    private var songs: [Song] { album?.song ?? [] }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    CoverImage(id: album?.coverArt ?? route.coverArt, size: 240)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(album?.name ?? route.name ?? "").font(.title3.bold()).multilineTextAlignment(.center)
                    Text(album?.artist ?? route.artist ?? "").foregroundStyle(Palette.accent)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                if let album, !songs.isEmpty {
                    Button("Play") { player.play(songs: songs, album: album, at: 0) }
                }
            }
            if gone {
                ErrorNote(text: ErrorWords.albumGone)
            } else if let failure {
                ErrorNote(failure, gone: ErrorWords.albumGone)
            } else if album == nil {
                ProgressView().accessibilityLabel(AlbumPageLines.loading)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                Button {
                    if let album { player.play(songs: songs, album: album, at: index) }
                } label: {
                    HStack {
                        Text(AlbumPageLines.number(song)).foregroundStyle(Palette.quiet).monospacedDigit()
                        Text(song.title ?? "")
                            .foregroundStyle(player.current?.track.id == song.id ? Palette.accent : .primary)
                        Spacer()
                        Text(Format.trackTime(song.duration)).foregroundStyle(Palette.quiet).monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album?.name ?? route.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(server.person)|\(route.id)") { await load() }
    }

    private func load() async {
        guard let client = server.client else { return }
        do {
            failure = nil
            if let found = try await client.album(id: route.id) {
                album = found
                gone = false
                player.albumShown(found)
            } else {
                album = nil
                gone = true
                player.albumGone(id: route.id)
            }
        } catch {
            if APIFailure.isCancellation(error) { return }
            failure = error
        }
    }
}
