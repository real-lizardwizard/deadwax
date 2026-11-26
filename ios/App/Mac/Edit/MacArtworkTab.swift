import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its Artwork tab (the redesign, slice R11 - notes/ios.md "The redesign, slice R11: Tags,
/// Artwork, Lyrics and Delete"; Main.dc.html): the Cover box - the folder's cover at 150 (a click shows it full size)
/// beside where it is, Get cover when there is none and the album names a release, and Compare with this pressing… (the
/// folder's beside the pressing's, the sheet Release's Compare full size… opens) - and the CD art box: each picture
/// round and 150 across (on the empty disc, its hole a third across, while it comes), else the empty disc, and Get CD
/// art beside "deadwax never replaces CD art it saved."
/// Side by side from an editor of 620, one under the other below it. With no release, each box's pointer and Go to
/// Release, which shows the Release tab.
///
/// Every rule is the phone's (GetResults, ArtworkLooks, EditAlbumModel.get): getting a cover never applies a release and
/// chooses nothing - it saves what the Cover Art Archive has for the release the folder is tagged with. The tab has no
/// action in the foot: its Gets are its boxes', as the drawing has them.
struct MacArtworkTab: View {
    let model: EditAlbumModel
    let album: ScanAlbum
    let twoColumns: Bool
    /// Compare with this pressing…: the comparison opened over the page (MacAlbumEditor's sheet).
    let compare: () -> Void
    /// Go to Release: the Release tab shown.
    let showRelease: () -> Void

    @State private var full: FullCover?

    /// Main.dc.html: the cover and the disc at 150.
    private static let side: CGFloat = 150

    var body: some View {
        Group {
            if twoColumns {
                HStack(alignment: .top, spacing: 14) {
                    coverBox
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    discBox
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    coverBox
                    discBox
                }
            }
        }
        .font(Typeface.Mac.text(.base))
        .foregroundStyle(DWPalette.text)
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
        .appCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
                .macSheet()
        }
    }

    // MARK: Cover

    private var coverBox: some View {
        let compares = ArtworkLooks.compares(model, album)
        return MacGroupBox(legend: GetResults.cover) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 6) {
                        Text(GetResults.coverNote(album.art))
                            .foregroundStyle(DWPalette.t2)
                        if !album.art.isEmpty {
                            Text(EditAlbumPage.Words.seeFullSize(Platform.device))
                                .font(Typeface.Mac.text(.small))
                                .foregroundStyle(DWPalette.t3)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if GetResults.offersCover(album) || compares {
                    HStack(alignment: .top, spacing: 6) {
                        if GetResults.offersCover(album) {
                            GetButton(model: model, kind: .cover, trackCount: album.trackCount,
                                      saidFont: Typeface.Mac.text(.small))
                        }
                        if compares {
                            Button(EditAlbumPage.Words.compareWithPressing, action: compare)
                                .buttonStyle(DWButtonStyle())
                        }
                    }
                }
                // (R11's review) Compare full size… named only while Release shows it: never here, where the pressing
                // has no cover to compare (compares is false) - the words alone
                if !compares, let pointer = EditAlbumPage.coverPointer(album, compare: ArtworkLooks.releaseCompares(model)
                                                                       ? EditAlbumPage.Words.compareFullSize : nil) {
                    pointerLine(pointer)
                }
            }
        }
    }

    /// The folder's cover, a click full size - or a picture's empty face while it has none.
    @ViewBuilder private var cover: some View {
        if album.art.isEmpty {
            Rectangle().fill(DWPalette.card)
                .frame(width: Self.side, height: Self.side)
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            Button {
                full = FullCover(source: .folder(album.path, album.artMtime))
            } label: {
                FolderCover(path: album.path, mtime: album.artMtime, hasArt: true, pixels: 360)
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(DWCorners.chipShape)
                    .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(GetResults.seeCover)
        }
    }

    // MARK: CD art

    private var discBox: some View {
        MacGroupBox(legend: GetResults.discArt) {
            VStack(alignment: .leading, spacing: 10) {
                if album.discArt.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        DiscFace()
                            .frame(width: Self.side, height: Self.side)
                        Text(GetResults.noDiscArt)
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.side), spacing: 14, alignment: .top)],
                              alignment: .leading, spacing: 14) {
                        ForEach(album.discArt, id: \.self) { (name: String) in
                            Button {
                                full = FullCover(source: .discArt(path: album.path, file: name))
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    DiscArtPicture(path: album.path, file: name)
                                        .frame(width: Self.side, height: Self.side)
                                    Text(name)
                                        .font(Typeface.Mac.mono(.label))
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
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if GetResults.offersDiscArt(album) {
                        GetButton(model: model, kind: .disc, trackCount: album.trackCount,
                                  saidFont: Typeface.Mac.text(.small))
                    }
                    if album.releaseMbid.isEmpty == false, let pointer = GetResults.webDiscArtPointer(album) {
                        Text(pointer)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if album.releaseMbid.isEmpty, let pointer = GetResults.webDiscArtPointer(album) {
                    pointerLine(pointer)
                }
            }
        }
    }

    /// A pointer, in the third colour - and, with the album matched to no release, Go to Release under it.
    @ViewBuilder private func pointerLine(_ pointer: String) -> some View {
        Text(pointer)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t3)
            .fixedSize(horizontal: false, vertical: true)
        if album.releaseMbid.isEmpty {
            Button(EditAlbumPage.Words.openRelease, action: showRelease)
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(model.retag == nil)
        }
    }
}
