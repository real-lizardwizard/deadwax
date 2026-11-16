import DeadwaxCore
import SwiftUI
import UIKit

/// Edit album's Artwork (notes/ios-specs/phase8-managing.md 3.5; the web's EditPanel ArtworkTab): the folder's cover - a
/// tap opens it full screen - with where it is, Get cover when there is none and the album names a release, and the
/// web's pointer to replacing one, here a row pushing Compare covers (or, with no release, the Release page); then CD
/// art - its pictures in a grid, each opening full screen - with Get CD art while the folder has none of deadwax's own,
/// and that deadwax never replaces CD art it saved. Every word is Core's (GetResults); the Gets are EditAlbumModel's.
struct ArtworkPage: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    @State private var full: FullCover?

    var body: some View {
        List {
            GetWait(model: model)
            Section {
                HStack(alignment: .top, spacing: 14) {
                    if album.art.isEmpty {
                        Rectangle().fill(Palette.coverEmpty)
                            .frame(width: 96, height: 96)
                            .clipShape(Corners.artShape)
                            .accessibilityHidden(true)
                    } else {
                        Button {
                            full = FullCover(source: .folder(album.path, album.artMtime))
                        } label: {
                            FolderCover(path: album.path, mtime: album.artMtime, hasArt: true, pixels: 360)
                                .frame(width: 96, height: 96)
                                .clipShape(Corners.artShape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(GetResults.seeCover)
                    }
                    Text(GetResults.coverNote(album.art))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                if GetResults.offersCover(album) {
                    GetButton(model: model, kind: .cover, trackCount: album.trackCount)
                }
                if let pointer = GetResults.coverPointer(album) {
                    // the web's pointer to the Release tab's comparison: here a row pushing it
                    NavigationLink(value: album.releaseMbid.isEmpty ? EditPage.release : EditPage.compareCovers) {
                        Text(pointer)
                            .font(Typeface.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .disabled(model.retag == nil)
                }
            } header: {
                Text(GetResults.cover)
                    .font(Typeface.footnote)
            }
            Section {
                if album.discArt.isEmpty {
                    Text(GetResults.noDiscArt)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GetResults.discArtBeside)
                            .fixedSize(horizontal: false, vertical: true)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(album.discArt, id: \.self) { (name: String) in
                                Button {
                                    full = FullCover(source: .discArt(path: album.path, file: name))
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        DiscArtPicture(path: album.path, file: name)
                                        Text(name)
                                            .font(Typeface.footnote)
                                            .foregroundStyle(Palette.quiet)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(GetResults.seeDiscArt(name))
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if GetResults.offersDiscArt(album) {
                    GetButton(model: model, kind: .disc, trackCount: album.trackCount)
                }
                if let pointer = GetResults.discArtPointer(album) {
                    if album.releaseMbid.isEmpty {
                        NavigationLink(value: EditPage.release) {
                            Text(pointer)
                                .font(Typeface.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .disabled(model.retag == nil)
                    } else {
                        Text(pointer)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text(GetResults.discArt)
                    .font(Typeface.footnote)
            }
        }
        .navigationTitle(GetResults.artwork)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
        }
    }
}

/// Edit album's Lyrics (the web's LyricsTab): how many tracks have lyrics beside them, Get lyrics while any hasn't -
/// and, once run, what it came to - "Every track has lyrics." once they all have, and the web's pointer to re-timing
/// in Server settings, said: Server settings is still the web app's.
struct LyricsPage: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    var body: some View {
        List {
            GetWait(model: model)
            Section {
                Text(GetResults.lyricsLine(album.lyricsCount, album.trackCount))
                    .fixedSize(horizontal: false, vertical: true)
                if GetResults.offersLyrics(album, ran: model.run(.lyrics) != nil) {
                    GetButton(model: model, kind: .lyrics, trackCount: album.trackCount)
                }
                if let note = GetResults.allLyricsNote(album) {
                    Text(note)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
            } header: {
                Text(GetResults.lyrics)
                    .font(Typeface.footnote)
            } footer: {
                Text(GetResults.retimePointer)
                    .font(Typeface.footnote)
            }
        }
        .navigationTitle(GetResults.lyrics)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The lines over Artwork and Lyrics while the folder is to be read again: a Get (or any write) whose answer never
/// came, said as maybe finished while it is read; a read that failed, said with Look again - the Gets off until one
/// lands (EditAlbumModel.canGet).
struct GetWait: View {
    let model: EditAlbumModel

    var body: some View {
        if model.unansweredGet != nil {
            Section {
                MayHaveFinished(reading: model.scan.reading)
            }
        }
        if model.retag?.flow.readFailed == true {
            Section {
                ReadAgainFailed(model: model)
            }
        }
    }
}

/// One of the album's Gets (LibraryParts.tsx's GetArtButton, GetDiscArtButton, GetLyricsButton): its words by its last
/// run for this folder - a spinner while it works, Look again after a 404, Try again after a failure - and the line it
/// left under it (the route's words, or what Get lyrics came to). On only as EditAlbumModel.canGet says.
struct GetButton: View {
    let model: EditAlbumModel
    let kind: GetResults.Kind
    let trackCount: Int

    var body: some View {
        let run = model.run(kind)
        Button {
            Task { await model.get(kind) }
        } label: {
            HStack(spacing: 10) {
                if run?.state == .working { ProgressView() }
                Text(GetResults.label(kind, run, trackCount: trackCount))
            }
        }
        .disabled(!model.canGet)
        if let said = run?.said, run?.state != .working {
            Text(said)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A CD art picture beside the tracks (`/library/disc_art?album=&file=`), square on the empty cover while it comes and
/// when it couldn't - hidden from VoiceOver: its button says what it is.
struct DiscArtPicture: View {
    let path: String
    let file: String

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Corners.artShape)
        .accessibilityHidden(true)
        .task(id: "\(path)|\(file)") {
            image = nil
            guard let client = server.client,
                  let data = try? await client.libraryDiscArt(path: path, file: file),
                  let raw = UIImage(data: data) else { return }
            let side: CGFloat = 360
            let scale = min(side / max(raw.size.width, raw.size.height, 1), 1)
            let thumb = await raw.byPreparingThumbnail(ofSize: CGSize(width: raw.size.width * scale,
                                                                     height: raw.size.height * scale)) ?? raw
            guard !Task.isCancelled else { return }
            image = thumb
        }
    }
}
