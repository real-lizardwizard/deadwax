import DeadwaxCore
import SwiftUI
import UIKit

/// Edit album's Artwork (notes/ios-specs/phase8-managing.md 3.5; the web's EditPanel ArtworkTab): the folder's cover - a
/// tap opens it full screen - with where it is, Get cover when there is none and the album names a release, and the
/// web's pointer to replacing one; then CD art - its pictures, each opening full screen - with Get CD art while the
/// folder has none of deadwax's own, and that deadwax never replaces CD art it saved. Every word is Core's (GetResults,
/// EditAlbumPage.Words); the Gets are EditAlbumModel's.
///
/// (R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork, Lyrics and Delete") The root's Artwork tab, drawn under
/// its strip as iEditArtwork.dc.html draws it, flat: the Cover group - the cover at 112 beside what it is, Get cover and
/// Compare covers… (pushing Compare covers, as Release's Compare does) - and the CD art group, each picture round and
/// 112 across (on the empty disc, its hole a third across, while it comes and when it couldn't), Get CD art beside
/// "deadwax never replaces CD art it saved." Gets inline, as the drawing has them: the tab has no foot. With no release,
/// the pointer and Go to Release, which shows the Release tab (`showRelease`) - a tab now on both devices, so the web's
/// words ("in the Release tab") are both devices', naming Release's Compare only while Release shows it
/// (EditAlbumPage.coverPointer, R11's review).
struct ArtworkPage: View {
    let model: EditAlbumModel
    let album: ScanAlbum
    /// Go to Release: the root's Release tab shown.
    let showRelease: () -> Void

    @State private var full: FullCover?

    /// iEditArtwork: the cover and the disc at 112.
    private static let side: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GetWait(model: model)
            PhoneGroup(legend: GetResults.cover) {
                PhoneCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            cover
                            VStack(alignment: .leading, spacing: 6) {
                                Text(GetResults.coverNote(album.art))
                                    .font(Typeface.Phone.text(.small))
                                    .foregroundStyle(DWPalette.t2)
                                if !album.art.isEmpty {
                                    Text(EditAlbumPage.Words.seeFullSize(Platform.device))
                                        .font(Typeface.Phone.text(.extraSmall))
                                        .foregroundStyle(DWPalette.t3)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        coverButtons
                    }
                }
            }
            PhoneGroup(legend: GetResults.discArt) {
                PhoneCard {
                    VStack(alignment: .leading, spacing: 12) {
                        discArt
                        discButtons
                    }
                }
            }
        }
        .appCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
                .macSheet()
        }
    }

    /// The folder's cover, a tap full screen - or its empty face, a picture's, while it has none.
    @ViewBuilder private var cover: some View {
        if album.art.isEmpty {
            Rectangle().fill(DWPalette.card)
                .frame(width: Self.side, height: Self.side)
                .accessibilityHidden(true)
        } else {
            Button {
                full = FullCover(source: .folder(album.path, album.artMtime))
            } label: {
                FolderCover(path: album.path, mtime: album.artMtime, hasArt: true, pixels: 360)
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(Corners.artShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(GetResults.seeCover)
        }
    }

    /// Get cover (only as LibraryParts offers it) and Compare covers… (the folder's beside the pressing's, as Release's
    /// Compare pushes it) - else the web's pointer, and with no release Go to Release.
    @ViewBuilder private var coverButtons: some View {
        let compares = ArtworkLooks.compares(model, album)
        if GetResults.offersCover(album) || compares {
            HStack(alignment: .top, spacing: 8) {
                if GetResults.offersCover(album) {
                    GetButton(model: model, kind: .cover, trackCount: album.trackCount,
                              saidFont: Typeface.Phone.text(.extraSmall))
                }
                if compares {
                    NavigationLink(value: EditPage.compareCovers) {
                        Text(EditWords.compareCovers)
                    }
                    .buttonStyle(DWButtonStyle())
                }
            }
        }
        // (R11's review) Release's Compare named only while Release shows it - never here, where the pressing has no
        // cover to compare (compares is false): the words alone
        if !compares, let pointer = EditAlbumPage.coverPointer(album, compare: ArtworkLooks.releaseCompares(model)
                                                               ? EditAlbumPage.Words.compare : nil) {
            pointerLine(pointer)
        }
    }

    /// CD art: the scan's pictures, each round and full screen by its name - else the empty disc and the line saying so.
    @ViewBuilder private var discArt: some View {
        if album.discArt.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                DiscFace()
                    .frame(width: Self.side, height: Self.side)
                Text(GetResults.noDiscArt)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // (R11's review) each disc 112 across, as iEditArtwork draws it - an adaptive cell alone grows it to the
            // row's width over two
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.side, maximum: Self.side), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                ForEach(album.discArt, id: \.self) { (name: String) in
                    Button {
                        full = FullCover(source: .discArt(path: album.path, file: name))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            DiscArtPicture(path: album.path, file: name)
                                .frame(width: Self.side, height: Self.side)
                            Text(name)
                                .font(Typeface.Phone.mono(.extraSmall))
                                .foregroundStyle(DWPalette.t2)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(GetResults.seeDiscArt(name))
                    .accessibilityAddTraits(.isButton)
                }
            }
            Text(EditAlbumPage.Words.discArtNote)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Get CD art as the web offers it, beside its pointer - "deadwax never replaces CD art it saved.", or with no
    /// release the match to make first and Go to Release.
    @ViewBuilder private var discButtons: some View {
        let pointer = GetResults.webDiscArtPointer(album)
        if GetResults.offersDiscArt(album) {
            GetButton(model: model, kind: .disc, trackCount: album.trackCount, saidFont: Typeface.Phone.text(.extraSmall))
        }
        if let pointer {
            pointerLine(pointer)
        }
    }

    /// A pointer, in the third colour - and, with the album matched to no release, Go to Release beside it.
    @ViewBuilder private func pointerLine(_ pointer: String) -> some View {
        Text(pointer)
            .font(Typeface.Phone.text(.extraSmall))
            .foregroundStyle(DWPalette.t3)
            .fixedSize(horizontal: false, vertical: true)
        if album.releaseMbid.isEmpty {
            Button(EditAlbumPage.Words.openRelease, action: showRelease)
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(model.retag == nil)
        }
    }
}

/// What both devices' Artwork read alike.
enum ArtworkLooks {
    /// Compare covers… is offered: a cover in the folder, the album matched to a release, and the pressing chosen has
    /// a cover to compare it with - Release's Compare's own condition (RetagModel.coverRelease).
    @MainActor static func compares(_ model: EditAlbumModel, _ album: ScanAlbum) -> Bool {
        !album.art.isEmpty && !album.releaseMbid.isEmpty && releaseCompares(model)
    }

    /// (R11's review) Release shows its Compare (the phone's Compare, the Mac's Compare full size…): the pressing chosen
    /// has a cover - so the cover pointer may name it (EditAlbumPage.coverPointer).
    @MainActor static func releaseCompares(_ model: EditAlbumModel) -> Bool {
        model.retag?.coverRelease != nil
    }
}

/// Edit album's Lyrics (the web's LyricsTab): how many tracks have lyrics beside them, Get lyrics while any hasn't -
/// and, once run, what it came to - "Every track has lyrics." once they all have, and the web's pointer to re-timing
/// in Server settings, said.
///
/// (R11) The root's Lyrics tab, as iEditLyrics.dc.html draws it, flat: the Lyrics group - its line, Get lyrics beside
/// "Nothing saved is replaced." - and the pointer under it. The count is the album's as the root holds it
/// (EditAlbumModel.album): Get lyrics reads the folder again once it has written (EditAlbumModel.get's lookUp), and the
/// line says the new count. No Each track group: which track has lyrics is no fact the app can have (it needs a route).
struct LyricsPage: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GetWait(model: model)
            PhoneGroup(legend: GetResults.lyrics) {
                PhoneCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(GetResults.lyricsLine(album.lyricsCount, album.trackCount))
                            .fixedSize(horizontal: false, vertical: true)
                        if GetResults.offersLyrics(album, ran: model.run(.lyrics) != nil) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                GetButton(model: model, kind: .lyrics, trackCount: album.trackCount,
                                          saidFont: Typeface.Phone.text(.extraSmall))
                                Text(EditAlbumPage.Words.nothingReplaced)
                                    .font(Typeface.Phone.text(.extraSmall))
                                    .foregroundStyle(DWPalette.t3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let note = GetResults.allLyricsNote(album) {
                            Text(note)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                        }
                    }
                }
            }
            Text(GetResults.retimePointer)
                .font(Typeface.Phone.text(.extraSmall))
                .foregroundStyle(DWPalette.t3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .font(Typeface.Phone.text(.row))
        .foregroundStyle(DWPalette.text)
    }
}

/// The lines over Artwork and Lyrics while the folder is to be read again: a Get (or any write) whose answer never
/// came, said as maybe finished while it is read; a read that failed, said with Look again - the Gets off until one
/// lands (EditAlbumModel.canGet). (R11) Flat: a card each, on both devices' tabs.
struct GetWait: View {
    let model: EditAlbumModel

    var body: some View {
        if model.unansweredGet != nil {
            GetWaitLine {
                MayHaveFinished(reading: model.scan.reading)
            }
        }
        if model.retag?.flow.readFailed == true {
            GetWaitLine {
                ReadAgainFailed(model: model)
            }
            .buttonStyle(DWButtonStyle(size: .small))
        }
    }
}

/// One of GetWait's lines, over a hairline.
private struct GetWaitLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }
}

/// One of the album's Gets (LibraryParts.tsx's GetArtButton, GetDiscArtButton, GetLyricsButton): its words by its last
/// run for this folder - a spinner while it works, Look again after a 404, Try again after a failure - and the line it
/// left under it (the route's words, or what Get lyrics came to). On only as EditAlbumModel.canGet says. (R11) The
/// look's button on both devices - flat on the phone, faced on the Mac - its line in the caller's face (`saidFont`:
/// each device's own small type).
struct GetButton: View {
    let model: EditAlbumModel
    let kind: GetResults.Kind
    let trackCount: Int
    let saidFont: Font

    var body: some View {
        let run = model.run(kind)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await model.get(kind) }
            } label: {
                HStack(spacing: 8) {
                    if run?.state == .working { ProgressView().controlSize(.small) }
                    Text(GetResults.label(kind, run, trackCount: trackCount))
                }
            }
            .buttonStyle(DWButtonStyle())
            .disabled(!model.canGet)
            if let said = run?.said, run?.state != .working {
                Text(said)
                    .font(saidFont)
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A CD art picture beside the tracks (`/library/disc_art?album=&file=`), round as a disc is - on the empty disc while
/// it comes and when it couldn't - hidden from VoiceOver: its button says what it is.
struct DiscArtPicture: View {
    let path: String
    let file: String

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            DiscFace()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
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

/// The empty disc (iEditArtwork, Main.dc.html): round, on the card's face in the line's edge, its hole a third across
/// on the panel's - a picture's face, drawn where no CD art is, or until one comes.
struct DiscFace: View {
    var body: some View {
        GeometryReader { (room: GeometryProxy) in
            let side = min(room.size.width, room.size.height)
            ZStack {
                Circle().fill(DWPalette.card)
                    .overlay(Circle().strokeBorder(DWPalette.line, lineWidth: 1))
                Circle().fill(DWPalette.panel)
                    .overlay(Circle().strokeBorder(DWPalette.line, lineWidth: 1))
                    .frame(width: side * 0.3, height: side * 0.3)
            }
            .frame(width: room.size.width, height: room.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
