import DeadwaxCore
import SwiftUI

/// One song of an album page (screens.md 4's track list): its number - or, for the song the player has, its playing
/// bars, still while paused (PlayingBars) - its title, its own artist only when it isn't the album's
/// (AlbumPageLines.artistShown), its time (Format.trackTime). A tap plays the album from it; its ••• ("More for
/// {title}") opens the queue menu with the one song.
struct TrackRow: View {
    let song: Song
    let albumArtist: String?
    /// The song the player has (PlayingBars.marks).
    let current: Bool
    /// The player means to play (the bars move); false while paused.
    let playing: Bool
    let play: () -> Void
    let more: () -> Void

    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 4) {
            Button(action: play) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    number
                        .frame(width: numberWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title ?? "")
                            .foregroundStyle(current ? Palette.accent : Color.primary)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        if let artist = AlbumPageLines.artistShown(song, albumArtist: albumArtist) {
                            Text(artist)
                                .font(.footnote)
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 8)
                    Text(Format.trackTime(song.duration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.quiet)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: more) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
        }
    }

    @ViewBuilder private var number: some View {
        if current {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: playing)
                .accessibilityLabel(PlayingBars.label(paused: !playing))
        } else {
            Text(AlbumPageLines.number(song))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.quiet)
        }
    }
}

/// "Disc 2 · <title>" above the first song of each disc (DiscHeadings).
struct DiscHeadingRow: View {
    let heading: String

    var body: some View {
        Text(heading)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .accessibilityAddTraits(.isHeader)
    }
}
