import DeadwaxCore
import SwiftUI

/// The Library tab's root. STUB (the Library part's): the album index of the person's scope as a plain list, each
/// row pushing its album's page (AppRoute.album), so the shell can be played from end to end.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server

    init() {}

    var body: some View {
        let scope = library.scope
        List {
            if let answer = library.albums(scope) {
                ForEach(answer.albums) { album in
                    NavigationLink(value: AppRoute.album(AlbumRoute(album))) {
                        HStack(spacing: 12) {
                            CoverImage(id: album.coverArt, size: 44)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name ?? album.id)
                                Text(album.artist ?? "").font(.footnote).foregroundStyle(Palette.quiet)
                            }
                        }
                    }
                }
            } else if let failure = library.failures[scope] {
                ErrorNote(failure, retry: true)
                Button(LibraryWords.tryAgain) { Task { await library.load(scope) } }
            } else {
                ProgressView().accessibilityLabel(LibraryWords.loading)
            }
        }
        .navigationTitle(LibraryWords.title(scope, personal: server.access.hasLibrary))
        .task(id: "\(server.person)|\(scope.rawValue)") { await library.load(scope) }
        .refreshable { await library.load(scope) }
    }
}
