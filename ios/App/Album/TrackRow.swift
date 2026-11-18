import DeadwaxCore
import SwiftUI

/// One song of an album page (screens.md 4's track list): its number - or, for the song the player has, its playing
/// bars, still while paused (PlayingBars) - its title, its own artist only when it isn't the album's
/// (AlbumPageLines.artistShown), its time (Format.trackTime). A tap plays the album from it; its ••• ("More for
/// {title}") opens the queue menu from itself, with the one song.
///
/// Phase 2 (phase2-downloads.md 3.3): a state slot between the title and the time, drawn on every row of an album where
/// any song has a download state and on none where none does - so the times stay in one column, and an album never
/// downloaded is Phase 1's page exactly. The mark at caption size, on the title's first line; the ring alone (no stop
/// square: the row's tap plays). VoiceOver hears the state after the title ("Roads, Downloaded, 4:12"), and the song's
/// download items as the row's actions. While deadwax can't be reached, a song not on this phone is dimmed and isn't a
/// button (VoiceOver: "dimmed"); its ••• still offers Download, which waits.
///
/// Add to Queue (notes/ios.md "Add to Queue: the swipe, and the menus' one item"): swiped right, the List's own leading
/// swipe action adds the song - wherever its ••• offers Add to Queue (AddToQueueSwipe.swift) - and the song's element
/// has it as a VoiceOver action of its own.
struct TrackRow: View {
    let song: Song
    let albumArtist: String?
    /// The song the player has (PlayingBars.marks).
    let current: Bool
    /// The player means to play (the bars move); false while paused.
    let playing: Bool
    let play: () -> Void
    /// What the row's ••• queues: the one song, as a song.
    let menu: QueueMenuRequest
    /// The song's download, and whether the album draws the slot at all.
    var download: SongDownload = .none
    var slot = false
    /// Not on this phone while deadwax can't be reached.
    var dimmed = false
    /// The row's VoiceOver actions: the song's download items, carried out by the page.
    var actions: [DownloadChoice] = []
    var act: (DownloadChoice) -> Void = { _ in }

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
                                .font(Typeface.footnote)
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 8)
                    if slot { stateSlot }
                    Text(Format.trackTime(song.duration))
                        .font(Typeface.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.quiet)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .opacity(dimmed ? Palette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityActions {
                ForEach(actions, id: \.self) { choice in
                    Button(choice.label) { act(choice) }
                }
            }
            // on the song's own element, where VoiceOver rests: the swipe's action, said for certain (the List's own
            // swipe action is the row's, and the row is two elements - this and the •••)
            .addToQueueAction(menu)

            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(Typeface.symbol(.body).weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            // a button-styled menu, so the plain button style is sure to reach it (as Apple pairs .menuStyle(.button)
            // with .buttonStyle): in a List row beside the song's own button, each takes only its own tap
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
        }
        .addsToQueue(menu, in: .list)
        // (the Mac app, slice 2) the row's ••• on a right-click - its own items; nothing on the iPhone
        .macContextMenu { QueueMenuItems(request: menu) }
    }

    /// The one slot (1.2): the song's mark, or the room for one held - every row of the album lines up. Its words are
    /// VoiceOver's, read between the title and the time; "Not on this phone" for a dimmed row.
    @ViewBuilder private var stateSlot: some View {
        let words = dimmed ? DownloadWords.notOnDevice(Platform.device) : DownloadWords.songLine(download, device: Platform.device)
        ZStack {
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: Typeface.symbol(.caption))
            } else {
                DownloadMark(mark: .downloaded, font: Typeface.symbol(.caption)).hidden()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words ?? "")
        .accessibilityHidden(words == nil)
    }

    @ViewBuilder private var number: some View {
        if current {
            Image(systemName: "waveform")
                .font(Typeface.symbol(.subheadline).weight(.semibold))
                .foregroundStyle(Palette.accent)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: playing)
                .accessibilityLabel(PlayingBars.label(paused: !playing))
        } else {
            Text(AlbumPageLines.number(song))
                .font(Typeface.subheadline.monospacedDigit())
                .foregroundStyle(Palette.quiet)
        }
    }
}

/// "Disc 2 · <title>" above the first song of each disc (DiscHeadings).
struct DiscHeadingRow: View {
    let heading: String

    var body: some View {
        Text(heading)
            .font(Typeface.footnote.weight(.semibold))
            .foregroundStyle(Palette.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .accessibilityAddTraits(.isHeader)
    }
}
