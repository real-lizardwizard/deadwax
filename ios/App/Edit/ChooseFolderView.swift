import DeadwaxCore
import SwiftUI

/// Choose the folder (notes/ios-specs/phase8-managing.md 3.1; the web's EditPanel picker): the library scan's folders
/// matching what was typed - every word somewhere in the folder's path, artist or album, accents and case aside - by
/// path, the first AlbumEdit.folderChoicesShown, with what folderChoicesWords says over them. Each row the folder's
/// cover, album, artist and path; a tap is `pick`. Inside Edit album (its album's folder not found) and in Settings >
/// Manage > Edit an album (ChooseFolderScreen), each with its own scan.
struct ChooseFolderView: View {
    let scan: LibraryScanModel
    let online: Bool
    let pick: (String) -> Void

    @State private var typed = ""

    var body: some View {
        let choices = AlbumEdit.folderChoices(scan.albums, typed: typed)
        List {
            if !scan.loaded {
                if scan.reading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(EditWords.readingLibrary).foregroundStyle(Palette.quiet)
                    }
                    .accessibilityElement(children: .combine)
                } else if let failure = scan.failure {
                    ErrorNote(text: failure)
                }
            } else {
                if let problem = scan.answer?.problem, !problem.isEmpty {
                    Text(problem).foregroundStyle(Palette.amber)
                }
                Section {
                    ForEach(choices.shown) { (album: ScanAlbum) in
                        Button {
                            pick(album.path)
                        } label: {
                            FolderRow(album: album)
                        }
                        .buttonStyle(.plain)
                        .disabled(!online)
                    }
                } header: {
                    Text(AlbumEdit.folderChoicesWords(shown: choices.shown.count, matching: choices.matching, typed: typed))
                        .font(Typeface.footnote)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure = scan.failure {
                    ErrorNote(text: failure)
                }
            }
        }
        .navigationTitle(EditWords.chooseFolder)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $typed, placement: .navigationBarDrawer(displayMode: .always), prompt: EditWords.folderPrompt)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
}

/// A folder of the library: its cover, album, artist and path - read by VoiceOver as one (EditWords.folderRow).
struct FolderRow: View {
    let album: ScanAlbum

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 120)
                .frame(width: 44, height: 44)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.album.isEmpty ? album.path : album.album)
                    .font(Typeface.body.weight(.semibold))
                if !album.artist.isEmpty {
                    Text(album.artist).font(Typeface.subheadline).foregroundStyle(Palette.quiet)
                }
                Text(album.path)
                    .font(Typeface.mono(.caption))
                    .foregroundStyle(Palette.quiet)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EditWords.folderRow(album))
        .accessibilityAddTraits(.isButton)
    }
}

/// Settings > Manage > Edit an album (phase8-managing.md 1): Choose the folder, pushed on the Settings tab - the one way
/// to a folder Navidrome doesn't list - its scan read as it opens, and again on a pull; a folder tapped opens Edit album
/// over the tabs for it. Opened while deadwax can't be reached it says it needs deadwax and asks nothing, reading the
/// scan once deadwax is back; gone out of reach, the list stays and taps are off.
struct ChooseFolderScreen: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @State private var scan = LibraryScanModel()

    var body: some View {
        Group {
            if !reachability.online && !scan.loaded {
                ContentUnavailableView {
                    Label(EditWords.chooseFolder, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                ChooseFolderView(scan: scan, online: reachability.online) { (path: String) in
                    navigation.editAlbum(AlbumEditRequest(target: .folder(path)))
                }
                .refreshable {
                    await scan.read(client: server.client, admin: server.access.seesDetail)
                }
            }
        }
        .task(id: reachability.online) {
            guard reachability.online else { return }
            await scan.read(client: server.client, admin: server.access.seesDetail)
        }
    }
}
