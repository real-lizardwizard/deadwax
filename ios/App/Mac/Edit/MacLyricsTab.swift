import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its Lyrics tab (the redesign, slice R11 - notes/ios.md "The redesign, slice R11: Tags,
/// Artwork, Lyrics and Delete"; Main.dc.html): the Lyrics box - "8 of 12 tracks have lyrics saved beside them, as a
/// .lrc." and Get lyrics at its end while any track has none (and, once it has run, saying what it came to), "Nothing
/// saved is replaced." under it, "Every track has lyrics." once they all have - and the pointer to re-timing in Server
/// settings. The count is the album's as the editor holds it (EditAlbumModel.album): Get lyrics reads the folder again
/// once it has written (EditAlbumModel.get's lookUp), and the line says the new count.
///
/// No Each track list (the drawing's table of each track's lyrics): which track has lyrics is no fact the app can have -
/// the scan counts them, and a list of them would need a route. The foot says where lyrics come from.
struct MacLyricsTab: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacGroupBox(legend: GetResults.lyrics) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(GetResults.lyricsLine(album.lyricsCount, album.trackCount))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if GetResults.offersLyrics(album, ran: model.run(.lyrics) != nil) {
                            GetButton(model: model, kind: .lyrics, trackCount: album.trackCount,
                                      saidFont: Typeface.Mac.text(.small))
                        }
                    }
                    if GetResults.offersLyrics(album, ran: model.run(.lyrics) != nil) {
                        Text(EditAlbumPage.Words.nothingReplaced)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = GetResults.allLyricsNote(album) {
                        Text(note)
                            .foregroundStyle(DWPalette.t2)
                    }
                }
            }
            Text(GetResults.retimePointer)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typeface.Mac.text(.base))
        .foregroundStyle(DWPalette.text)
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
    }
}
