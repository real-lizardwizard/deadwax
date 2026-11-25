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
/// button (VoiceOver: "Not on this phone"); its ••• still offers Download, which waits.
///
/// Add to Queue (notes/ios.md "Add to Queue: the swipe, and the menus' one item"): swiped right, the List's own leading
/// swipe action adds the song - wherever its ••• offers Add to Queue (AddToQueueSwipe.swift) - and the song's element
/// has it as a VoiceOver action of its own.
///
/// THE REDESIGN, SLICE R5 (iAlbum.dc.html's .row; notes/ios.md "The redesign, slice R5: an album, Playlists, a
/// playlist"): 48 tall at least, on the row's rule - the number in the mono face from 16 in, the title in the page's
/// words at the drawing's 56 (its number's 46-wide box holds its own 16 of padding, and the title's 10 follows it), the
/// time in the mono face, the ••• in the third colour 16 from the right. (R5's review) The number's width and the gap
/// after it grow with the text size, as the number's words do (plan 3.3), so "999" fits at every size - and a number
/// wider still takes its own room. One VoiceOver element (wave B's rule): the number, the title, playing or paused, its
/// artist, its state and its time; its tap plays, and the •••'s items are its actions - Add to Queue, Add to a
/// playlist…, the song's download items. The swipe and the right-click stay.
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

    @Environment(\.dynamicTypeSize) private var typeSize
    /// (R5's review) The number's width and the gap after it, scaled as the number's words are (mono .small scales with
    /// footnote): the drawing's at the default size.
    @ScaledMetric(relativeTo: .footnote) private var numberWidth: CGFloat = AlbumPageLook.numberWidth
    @ScaledMetric(relativeTo: .footnote) private var numberGap: CGFloat = AlbumPageLook.numberGap

    var body: some View {
        let artist = AlbumPageLines.artistShown(song, albumArtist: albumArtist)
        HStack(spacing: 0) {
            Button(action: play) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    number
                        .fixedSize()
                        .frame(minWidth: numberWidth, alignment: .leading)
                        .padding(.trailing, numberGap)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title ?? "")
                            .font(Typeface.body)
                            .foregroundStyle(current ? DWPalette.acc : DWPalette.text)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        if let artist {
                            Text(artist)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 8)
                    if slot {
                        stateSlot
                            .padding(.trailing, AlbumPageLook.chipGap)
                    }
                    Text(Format.trackTime(song.duration))
                        .font(Typeface.Phone.mono(.small))
                        .foregroundStyle(DWPalette.t3)
                        .padding(.trailing, AlbumPageLook.timeTrail)
                }
                .padding(.leading, AlbumPageLook.rowSide)
                .padding(.vertical, 6)
                .lookHeight(DWLook.here.rowHeight)
                .contentShape(Rectangle())
                .opacity(dimmed ? DWPalette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)

            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(Typeface.symbol(.body).weight(.semibold))
                    .foregroundStyle(DWPalette.t3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            // a button-styled menu, so the plain button style is sure to reach it (as Apple pairs .menuStyle(.button)
            // with .buttonStyle): in a List row beside the song's own button, each takes only its own tap
            .menuStyle(.button)
            .buttonStyle(.plain)
            // the glyph's own edge 16 from the right (.row's •••): 12 of its 44 target lie beyond it
            .padding(.trailing, AlbumPageLook.moreTrail - 12)
        }
        // (R5, wave B's rule) one element: its tap plays, the •••'s items its actions
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(artist))
        .accessibilityAddTraits(dimmed ? [] : .isButton)
        .accessibilityAction {
            if !dimmed { play() }
        }
        .accessibilityActions {
            ForEach(actions, id: \.self) { choice in
                Button(choice.label) { act(choice) }
            }
        }
        .addToQueueAction(menu)
        .addToPlaylistAction(menu)
        .addsToQueue(menu, in: .list)
        // (the Mac app, slice 2) the row's ••• on a right-click - its own items; nothing on the iPhone
        .macContextMenu { QueueMenuItems(request: menu) }
    }

    /// The row as VoiceOver reads it: (R5's review) its track number first, as before R5, then the title, playing or
    /// paused, its own artist, the download state ("Not on this phone" for a dimmed row), the time.
    private func spoken(_ artist: String?) -> String {
        var parts = [AlbumPageLines.number(song), song.title ?? ""]
        if current { parts.append(PlayingBars.label(paused: !playing)) }
        if let artist { parts.append(artist) }
        let state = dimmed ? DownloadWords.notOnDevice(Platform.device) : DownloadWords.songLine(download, device: Platform.device)
        if let state { parts.append(state) }
        parts.append(Format.trackTime(song.duration))
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The one slot (1.2): the song's mark, or the room for one held - every row of the album lines up. VoiceOver reads
    /// its words in the row's label.
    @ViewBuilder private var stateSlot: some View {
        ZStack {
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: Typeface.symbol(.caption))
            } else {
                DownloadMark(mark: .downloaded, font: Typeface.symbol(.caption)).hidden()
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var number: some View {
        if current {
            Image(systemName: "waveform")
                .font(Typeface.symbol(.subheadline).weight(.semibold))
                .foregroundStyle(DWPalette.acc)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: playing)
        } else {
            Text(AlbumPageLines.number(song))
                .font(Typeface.Phone.mono(.small))
                .foregroundStyle(DWPalette.t3)
        }
    }
}

/// "Disc 2 · <title>" above the first song of each disc (DiscHeadings) - (R5) 16 in, as the rows' numbers.
struct DiscHeadingRow: View {
    let heading: String

    var body: some View {
        Text(heading)
            .font(Typeface.Phone.text(.small).weight(.semibold))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .padding(.horizontal, AlbumPageLook.rowSide)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// (R5) A song row's VoiceOver action "Add to a playlist…" - the •••'s own item, offered where the ••• offers it
    /// (deadwax in reach, the album not gone from the collection), so a row that is one element loses nothing of its •••.
    func addToPlaylistAction(_ request: QueueMenuRequest?) -> some View {
        modifier(AddToPlaylistAction(request: request))
    }
}

private struct AddToPlaylistAction: ViewModifier {
    let request: QueueMenuRequest?

    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation

    /// (R5's review) Always the one modifier, the action offered or not inside it (AddToQueueAction's way): a branch
    /// between `content` and `content` with an action would give the row two identities, so the row - its Add to Queue
    /// action with it - would be made again whenever deadwax came or went.
    func body(content: Content) -> some View {
        let offered = request.map { (shown: QueueMenuRequest) -> Bool in
            reachability.online && !shown.gone && !shown.pick.tracks.isEmpty
        } ?? false
        content.accessibilityActions {
            if offered, let request {
                Button(PlaylistWords.addToAPlaylistRow) {
                    navigation.playlistPick = PlaylistPickRequest(PlaylistPick(request.pick))
                }
            }
        }
    }
}
