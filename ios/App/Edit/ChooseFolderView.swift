import DeadwaxCore
import SwiftUI

/// Choose the folder (notes/ios-specs/phase8-managing.md 3.1; the web's EditPanel picker): the library scan's folders
/// matching what was typed - every word somewhere in the folder's path, artist or album, accents and case aside - by
/// path, the first AlbumEdit.folderChoicesShown, with what folderChoicesWords says over them. Each row the folder's
/// cover, album, artist and path; a tap is `pick`. Inside Edit album (its album's folder not found) and in Settings >
/// Manage > Edit an album (ChooseFolderScreen), each with its own scan.
///
/// (R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") Flat: no List - the folders down
/// the page on their hairlines, 16 in from its sides, under the count in the small greys, on the page's black; what
/// was typed in iOS's own search field in the bar, as before (its own box - the place you type keeps one).
struct ChooseFolderView: View {
    let scan: LibraryScanModel
    let online: Bool
    let pick: (String) -> Void

    @State private var typed = ""

    var body: some View {
        let choices = AlbumEdit.folderChoices(scan.albums, typed: typed)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !scan.loaded {
                    if scan.reading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(EditWords.readingLibrary).foregroundStyle(DWPalette.t2)
                        }
                        .padding(.top, SheetLook.gap)
                        .accessibilityElement(children: .combine)
                    } else if let failure = scan.failure {
                        ErrorNote(text: failure)
                            .padding(.top, SheetLook.gap)
                    }
                } else {
                    if let problem = scan.answer?.problem, !problem.isEmpty {
                        Text(problem)
                            .font(SheetLook.small)
                            .foregroundStyle(DWPalette.amberText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, SheetLook.gap)
                    }
                    Text(AlbumEdit.folderChoicesWords(shown: choices.shown.count, matching: choices.matching, typed: typed))
                        .font(SheetLook.small)
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, SheetLook.gap)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(choices.shown) { (album: ScanAlbum) in
                        Button {
                            pick(album.path)
                        } label: {
                            FolderRow(album: album)
                        }
                        .buttonStyle(.plain)
                        .disabled(!online)
                        .opacity(online ? 1 : DWPalette.off)
                    }
                    if let failure = scan.failure {
                        ErrorNote(text: failure)
                            .padding(.top, SheetLook.gap)
                    }
                }
            }
            .font(SheetLook.words)
            .padding(.horizontal, SheetLook.side)
            .padding(.bottom, 24)
        }
        .background(SheetLook.ground)
        .navigationTitle(EditWords.chooseFolder)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $typed, placement: .navigationBarDrawer(displayMode: .always), prompt: EditWords.folderPrompt)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
}

/// A folder of the library: its cover, album, artist and path - read by VoiceOver as one (EditWords.folderRow). (R18) A
/// row of the page's on its hairline: the album in the rows' words, the artist in the small greys, the path in Courier
/// Prime in the third colour (`.mono .xs .q3`), the cover a picture's square.
struct FolderRow: View {
    let album: ScanAlbum

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 120)
                .frame(width: 44, height: 44)
                .clipShape(DWCorners.chipShape)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.album.isEmpty ? album.path : album.album)
                    .font(SheetLook.words.weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                if !album.artist.isEmpty {
                    Text(album.artist)
                        .font(SheetLook.small)
                        .foregroundStyle(DWPalette.t2)
                }
                Text(album.path)
                    .font(SheetLook.mono)
                    .foregroundStyle(DWPalette.t3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { DWRule(colour: SheetLook.rule) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EditWords.folderRow(album))
        .accessibilityAddTraits(.isButton)
    }
}

/// Settings > Manage > Edit an album (phase8-managing.md 1): Choose the folder, pushed on the Settings tab - the one way
/// to a folder Navidrome doesn't list - its scan read as it opens, and again on a pull; a folder tapped opens Edit album
/// over the tabs for it. Opened while deadwax can't be reached it says it needs deadwax and asks nothing, reading the
/// scan once deadwax is back; gone out of reach, the list stays and taps are off. (R18) That word in the look's own words
/// (FolderNeedsDeadwax), not the system's ContentUnavailableView.
struct ChooseFolderScreen: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @State private var scan = LibraryScanModel()

    var body: some View {
        Group {
            if !reachability.online && !scan.loaded {
                FolderNeedsDeadwax()
                    .navigationTitle(EditWords.chooseFolder)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ChooseFolderView(scan: scan, online: reachability.online) { (path: String) in
                    navigation.editAlbum(AlbumEditRequest(target: .folder(path)))
                }
                .pullToRefresh {
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

/// (R18) Choose the folder opened while deadwax can't be reached: its glyph, its name as a heading and what it needs, in
/// the look's words and greys, centred on the page's ground - read by VoiceOver as one.
private struct FolderNeedsDeadwax: View {
    var body: some View {
        VStack(spacing: SheetLook.gap) {
            Image(systemName: "wifi.slash")
                .font(Typeface.symbol(.title))
                .foregroundStyle(DWPalette.t2)
                .accessibilityHidden(true)
            Text(EditWords.chooseFolder)
                .font(SheetLook.title)
                .foregroundStyle(DWPalette.text)
                .accessibilityAddTraits(.isHeader)
            Text(EditWords.needsDeadwax)
                .font(SheetLook.small)
                .foregroundStyle(DWPalette.t2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SheetLook.side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SheetLook.ground)
        .accessibilityElement(children: .combine)
    }
}
