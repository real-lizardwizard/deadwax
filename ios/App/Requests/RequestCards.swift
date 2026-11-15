import DeadwaxCore
import SwiftUI

// The Requests board's cards (Phase 6, slice 1 - phase6-get-requests.md 3.2; the web's app/JobCard.tsx): a card for a
// download on its way or needing attention, a plain row for one done. Every word comes from the row (Core's
// RequestsView); these only lay it out and hand a tap to the screen. A line that changes as answers land - the data
// line - is one line high, drawn whether or not a speed is in it; the bar's height is fixed. The covers (44, and
// Downloading's 52 - the web's) and the ✕'s and ▶'s 32-point faces are fixed, as the app's rows' covers are
// (LibraryRow.cover, Up Next's 44), their glyphs growing to the largest standard size and holding there: at the
// accessibility sizes the words take the room - a title on up to 3 lines, and a card's two buttons one over the other
// when they don't fit side by side (slice 1's review, finding 4).

/// The pressing's front through deadwax's relay (question 9), or the plain tile without one.
struct RequestCover: View {
    let release: String?
    let size: CGFloat

    var body: some View {
        // the relay takes MusicBrainz's ids as MusicBrainz gives them - lowercase
        let addresses = release.map { [ArchiveCoverID(.release, $0.lowercased())] } ?? []
        ArchiveCover(addresses: addresses, size: ArchiveCoverSize.row)
            .frame(width: size, height: size)
            .clipShape(Corners.artShape)
    }
}

/// The cards' fixed sizes.
private enum CardSizes {
    /// A card's cover, and a Done row's.
    static let cover: CGFloat = 44
    /// Downloading's.
    static let largeCover: CGFloat = 52
    /// The ✕'s and the ▶'s round face, inside a 44-point target.
    static let face: CGFloat = 32
    /// A title's lines at the accessibility sizes (one otherwise).
    static let titleLines = 3
}

/// Two buttons side by side, or one over the other when they don't fit (the accessibility sizes, a long label) - each
/// label on one line beside the other, on up to 3 over it at the accessibility sizes.
private struct ButtonPair<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons.lineLimit(1) }
            VStack(alignment: .leading, spacing: 8) {
                buttons.lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
            }
        }
    }
}

/// A line's colour by its tone: the ordinary grey, the warning amber, the failure red.
private func toneColour(_ tone: RequestTone) -> Color {
    switch tone {
    case .plain: return Palette.quiet
    case .warning: return Palette.amber
    case .danger: return Palette.danger
    }
}

/// Downloading's card (the bigger cover, the bar and "6 of 10 files · 1.8 MB/s") and Waiting's (its place in the
/// queue): the ✕, and the card's question under its words while it asks.
struct JobCardView: View {
    let row: RequestRow
    /// Downloading's: the bigger cover, the bar and the data line.
    let downloading: Bool
    /// This card is asking "cancel it?".
    let asking: Bool
    let onCancel: () -> Void
    let onKeep: () -> Void
    let onConfirm: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RequestCover(release: row.cover, size: downloading ? CardSizes.largeCover : CardSizes.cover)
                    .opacity(row.dimmed ? Palette.dimmed : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(Typeface.body.weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
                        .opacity(row.dimmed ? Palette.dimmed : 1)
                    Text(row.line)
                        .font(Typeface.footnote)
                        .foregroundStyle(toneColour(row.lineTone))
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(row.dimmed && downloading ? Palette.dimmed : 1)
                    if let askedBy = row.askedBy {
                        Text(askedBy)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if downloading {
                        DownloadBar(fraction: row.progress / 100)
                            .padding(.vertical, 4)
                            .opacity(row.dimmed ? Palette.dimmed : 1)
                        // one line, always drawn: its height kept whether or not a speed is in it
                        Text(row.data ?? " ")
                            .font(Typeface.footnote.monospacedDigit())
                            .foregroundStyle(Palette.quiet)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.cancel != nil {
                    CancelButton(row: row, action: onCancel)
                }
            }
            if asking {
                CancelQuestion(row: row, onKeep: onKeep, onConfirm: onConfirm)
            }
        }
        .padding(.vertical, 4)
    }
}

/// ✕ - a tap target 44 points square, the board's 32-point face drawn inside it. It opens the card's question (a second
/// tap closes it); while its cancel is on its way it waits. Named for what it does: "Leave …" on a download somebody
/// else waits for too.
private struct CancelButton: View {
    let row: RequestRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Typeface.symbol(.footnote).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Palette.onSecondary)
                .frame(width: CardSizes.face, height: CardSizes.face)
                .background(Palette.secondaryFill, in: Circle())
                .overlay(Circle().strokeBorder(Palette.secondaryEdge, lineWidth: 1))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(row.cancel == .cancelling)
        .opacity(row.cancel == .cancelling ? Palette.off : 1)
        .accessibilityLabel(RequestWords.cancelLabel(row))
        .accessibilityShowsLargeContentViewer {
            Label(RequestWords.cancelLabel(row), systemImage: "xmark")
        }
    }
}

/// The card's question, under its words: what a cancel costs, and the two answers - the row's own ("Leave it",
/// "Cancel for everyone" with logins on).
private struct CancelQuestion: View {
    let row: RequestRow
    let onKeep: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.cancelWords.question)
                .font(Typeface.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            ButtonPair {
                Button(action: onKeep) {
                    Text(RequestWords.keepIt)
                }
                .buttonStyle(SecondaryPill())
                Button(action: onConfirm) {
                    Text(row.cancelWords.action)
                        .foregroundStyle(Palette.danger)
                }
                .buttonStyle(SecondaryPill())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(RequestWords.cancelLabel(row))?")
    }
}

/// Needs attention's card: why it stopped, in red, and the two ways on - "Another source · N left" (the solid button only
/// on the first such card) and "Same source again". While one runs both wait, the one tapped saying what it does; a
/// refusal is the red line under the reason. Without Get albums neither is drawn, and the line saying so is.
struct AttentionCardView: View {
    let row: RequestRow
    /// Get albums (Access `.request`).
    let gets: Bool
    /// Whoever runs deadwax (Access.seesDetail): the error's own words under the reason, never "Tell whoever…".
    let runs: Bool
    let onRetry: (_ same: Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ways = row.nextPeer != nil || row.askAgain != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RequestCover(release: row.cover, size: CardSizes.cover)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(Typeface.body.weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
                    if !row.line.isEmpty {
                        Text(row.line)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let askedBy = row.askedBy {
                        Text(askedBy)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let reason = row.reason {
                        ReasonLine(text: row.reasonTell && !runs ? "\(reason) \(ErrorWords.tell)" : reason,
                                   detail: runs ? row.reasonDetail : nil)
                    }
                    if let problem = row.problem {
                        ReasonLine(text: problem, detail: runs ? row.problemDetail : nil)
                    }
                    if !gets && ways {
                        Text(RequestWords.getOff)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if gets && ways {
                ButtonPair {
                    if let next = row.nextPeer {
                        if next.primary {
                            Button { onRetry(false) } label: { Text(next.label) }
                                .buttonStyle(PrimaryFace())
                        } else {
                            Button { onRetry(false) } label: { Text(next.label) }
                                .buttonStyle(SecondaryPill())
                        }
                    }
                    if let again = row.askAgain {
                        Button { onRetry(true) } label: { Text(again.label) }
                            .buttonStyle(SecondaryPill())
                    }
                }
                .disabled(row.busy)
            }
        }
        .padding(.vertical, 4)
    }
}

/// What went wrong, in red - and, for whoever runs deadwax, the error's own words under it to open.
private struct ReasonLine: View {
    let text: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                DisclosureGroup(ErrorWords.forWhoever) {
                    Text(detail)
                        .font(Typeface.mono(.footnote))
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Typeface.footnote)
            }
        }
    }
}

/// Done: how it ended and how long ago. A download whose album is in the library opens it - the row is a button - and
/// one this download filed has the ▶, which plays it (the screen decides, in the tap, whether its songs are in hand).
/// `note`: why a tapped row couldn't open; `opening` while it looks, faded so the tap shows it was taken.
struct DoneRowView: View {
    let row: RequestRow
    let opening: Bool
    let note: String?
    let runs: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if row.release != nil {
                Button(action: onOpen) { face }
                    .buttonStyle(.plain)
                    .opacity(opening ? Palette.dimmed : 1)
            } else {
                face
            }
            if row.release != nil && row.plays {
                Button(action: onPlay) {
                    SharpSymbol(.play)
                        .font(Typeface.symbol(.footnote).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(Palette.primaryLabel)
                        .frame(width: CardSizes.face, height: CardSizes.face)
                        .background(Palette.primaryFill, in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(RequestWords.playLabel(row))
                .accessibilityShowsLargeContentViewer {
                    Label {
                        Text(RequestWords.playLabel(row))
                    } icon: {
                        Image(uiImage: SharpGlyph.play.image)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var face: some View {
        HStack(alignment: .top, spacing: 12) {
            RequestCover(release: row.cover, size: CardSizes.cover)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Typeface.body.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
                Text(row.line)
                    .font(Typeface.footnote)
                    .foregroundStyle(toneColour(row.lineTone))
                    .fixedSize(horizontal: false, vertical: true)
                if runs, let detail = row.reasonDetail, !detail.isEmpty {
                    Text(detail)
                        .font(Typeface.mono(.footnote))
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !runs && row.reasonTell {
                    Text(ErrorWords.tell)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let askedBy = row.askedBy {
                    Text(askedBy)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note {
                    Text(note)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
