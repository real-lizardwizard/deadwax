import DeadwaxCore
import SwiftUI

// The Requests board's cards on the phone (Phase 6, slice 1 - phase6-get-requests.md 3.2; the web's app/JobCard.tsx),
// in the redesign's look since slice R8 (notes/ios.md "The redesign, slice R8: Requests"; iRequests.dc.html): a card
// (PhoneCard, square) for a download on its way or needing attention, a plain row for one done. Every word comes from
// the row (Core's RequestsView); these only lay it out and hand a tap to the screen. A line that changes as answers land
// - the data line, "3 of 11 files · 244 KB/s" in mono - is one line high, drawn whether or not a speed is in it; the
// meter's height is DWLook's, grown with the text. The covers (the cards' 48, a done row's 44 - the drawing's) and the
// ✕'s and ▶'s 32-point round faces are fixed, as the app's rows' covers are, their glyphs growing to the largest
// standard size and holding there: at the accessibility sizes the words take the room - a title on up to 3 lines, and a
// card's two buttons one over the other when they don't fit side by side (slice 1's review, finding 4), each then
// across the card on up to 3 lines (R8's review: ButtonWords). Round stays round - the ✕ and the ▶ - and everything else
// is square. Each card is one element for VoiceOver (R8's review): everything it shows (RequestSpoken.card), and its
// actions named as its buttons are (RequestAction) - a cancel's question, while it asks, its own group under it.

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
    /// A card's cover (iRequests' .card .cover).
    static let cover: CGFloat = 48
    /// A done row's (iRequests' .row.tall .cover).
    static let doneCover: CGFloat = 44
    /// The ✕'s and the ▶'s round face, inside a 44-point target.
    static let face: CGFloat = 32
    /// A title's lines at the accessibility sizes (one otherwise).
    static let titleLines = 3
    /// A card's words, one under the other (.col's gap 3), and the meter's room above it (its margin-top 5).
    static let lines: CGFloat = 3
    static let aboveMeter: CGFloat = 5
}

/// Two buttons side by side, each at its own words' width, or - when they don't fit (the accessibility sizes, a long
/// label) - one over the other, each across the card: `buttons(stacked)` draws them either way, a stacked button filling
/// (DWButtonStyle's `fills`) so its words can take more than one line (ButtonWords).
private struct ButtonPair<Buttons: View>: View {
    let buttons: (_ stacked: Bool) -> Buttons

    init(@ViewBuilder buttons: @escaping (_ stacked: Bool) -> Buttons) {
        self.buttons = buttons
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons(false) }
            VStack(alignment: .leading, spacing: 8) { buttons(true) }
        }
    }
}

/// A card's button's words (R8's review - slice 1's fix, kept in the new look): one line, up to 3 at the accessibility
/// sizes. The limit is the words' own, inside the button - the innermost limit is the one that holds, so DWButtonStyle's
/// one line round the label never cuts "Another source · 2 left" at AX5 - and side by side each keeps its whole width.
private struct ButtonWords: View {
    let words: String
    let stacked: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: !stacked, vertical: stacked)
            .padding(.vertical, typeSize.isAccessibilitySize ? CardSizes.lines : 0)
    }
}

/// A line's colour by its tone: the second colour, the warning amber, the failure red.
private func toneColour(_ tone: RequestTone) -> Color {
    switch tone {
    case .plain: return DWPalette.t2
    case .warning: return DWPalette.amberText
    case .danger: return DWPalette.redChipText
    }
}

/// A card's title (.b, 16): one line, up to 3 at the accessibility sizes.
private struct CardTitle: View {
    let words: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(words)
            .font(Typeface.Phone.text(.row).weight(.semibold))
            .foregroundStyle(DWPalette.text)
            .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
    }
}

/// A card's small line (.s .q): the second colour, or its tone's.
private struct CardLine: View {
    let words: String
    var colour: Color = DWPalette.t2

    var body: some View {
        Text(words)
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Downloading's card (the meter and "3 of 11 files · 244 KB/s") and Waiting's (its place in the queue): the ✕, and
/// the card's question under its words while it asks.
struct JobCardView: View {
    let row: RequestRow
    /// Downloading's: the meter and the data line.
    let downloading: Bool
    /// This card is asking "cancel it?".
    let asking: Bool
    let onCancel: () -> Void
    let onKeep: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        PhoneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: downloading ? .top : .center, spacing: 12) {
                    RequestCover(release: row.cover, size: CardSizes.cover)
                        .opacity(row.dimmed ? DWPalette.off : 1)
                    VStack(alignment: .leading, spacing: CardSizes.lines) {
                        CardTitle(words: row.title)
                            .opacity(row.dimmed ? DWPalette.off : 1)
                        CardLine(words: row.line, colour: toneColour(row.lineTone))
                            .opacity(row.dimmed && downloading ? DWPalette.off : 1)
                        if let askedBy = row.askedBy {
                            CardLine(words: askedBy)
                        }
                        if downloading {
                            DWMeter(fraction: row.progress / 100)
                                .padding(.top, CardSizes.aboveMeter - CardSizes.lines)
                                .opacity(row.dimmed ? DWPalette.off : 1)
                            // one line, always drawn: its height kept whether or not a speed is in it
                            Text(row.data ?? " ")
                                .font(Typeface.Phone.mono(.extraSmall))
                                .foregroundStyle(DWPalette.t2)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if row.cancel != nil {
                        CancelButton(row: row, action: onCancel)
                    }
                }
                // one element: what the card shows, and its ✕ as an action
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RequestSpoken.card(row, runs: false, gets: true))
                .accessibilityActions {
                    ForEach(RequestAction.offered(row, gets: true, online: true), id: \.self) { (action: RequestAction) in
                        Button(action.words(row), action: onCancel)
                    }
                }
                if asking {
                    CancelQuestion(row: row, onKeep: onKeep, onConfirm: onConfirm)
                }
            }
        }
    }
}

/// ✕ - a tap target 44 points square, its 32-point round face drawn inside it, raised as a button is (.btn's colours;
/// round stays round). It opens the card's question (a second tap closes it); while its cancel is on its way it waits.
/// Named for what it does: "Leave …" on a download somebody else waits for too.
private struct CancelButton: View {
    let row: RequestRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Typeface.symbol(.footnote).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(DWPalette.buttonText)
                .frame(width: CardSizes.face, height: CardSizes.face)
                .background {
                    DWRaised(shape: Circle(), face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen,
                             edge: DWPalette.buttonEdge, drop: DWPalette.buttonDrop)
                }
                .frame(minWidth: CGFloat(DWLook.here.target), minHeight: CGFloat(DWLook.here.target))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(row.cancel == .cancelling)
        .opacity(row.cancel == .cancelling ? DWPalette.off : 1)
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
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.head)
                .fixedSize(horizontal: false, vertical: true)
            ButtonPair { (stacked: Bool) in
                Button(action: onKeep) {
                    ButtonWords(words: RequestWords.keepIt, stacked: stacked)
                }
                .buttonStyle(DWButtonStyle(size: .small, fills: stacked))
                Button(action: onConfirm) {
                    ButtonWords(words: row.cancelWords.action, stacked: stacked)
                }
                .buttonStyle(DWButtonStyle(kind: .danger, size: .small, fills: stacked))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(RequestWords.cancelLabel(row))?")
    }
}

/// Needs attention's card: why it stopped, in red, and the two ways on - "Another source · N left" (the purple button
/// only on the first such card) and "Same source again", side by side across the card. While one runs both wait, the one
/// tapped saying what it does; a refusal is the red line under the reason. Without Get albums neither is drawn, and the
/// line saying so is.
struct AttentionCardView: View {
    let row: RequestRow
    /// Get albums (Access `.request`).
    let gets: Bool
    /// Whoever runs deadwax (Access.seesDetail): the error's own words under the reason, never "Tell whoever…".
    let runs: Bool
    let onRetry: (_ same: Bool) -> Void

    var body: some View {
        let ways = row.nextPeer != nil || row.askAgain != nil
        PhoneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    RequestCover(release: row.cover, size: CardSizes.cover)
                    VStack(alignment: .leading, spacing: CardSizes.lines) {
                        CardTitle(words: row.title)
                        if !row.line.isEmpty {
                            CardLine(words: row.line)
                        }
                        if let askedBy = row.askedBy {
                            CardLine(words: askedBy)
                        }
                        if let reason = row.reason {
                            ReasonLine(text: row.reasonTell && !runs ? "\(reason) \(ErrorWords.tell)" : reason,
                                       detail: runs ? row.reasonDetail : nil)
                        }
                        if let problem = row.problem {
                            ReasonLine(text: problem, detail: runs ? row.problemDetail : nil)
                        }
                        if !gets && ways {
                            CardLine(words: RequestWords.getOff)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if gets && ways {
                    ButtonPair { (stacked: Bool) in
                        if let next = row.nextPeer {
                            Button {
                                onRetry(false)
                            } label: {
                                ButtonWords(words: next.label, stacked: stacked)
                            }
                            .buttonStyle(DWButtonStyle(kind: next.primary ? .pri : .normal, fills: true))
                        }
                        if let again = row.askAgain {
                            Button {
                                onRetry(true)
                            } label: {
                                ButtonWords(words: again.label, stacked: stacked)
                            }
                            .buttonStyle(DWButtonStyle(fills: true))
                        }
                    }
                    .disabled(row.busy)
                }
            }
        }
        // one element: everything the card shows - for whoever runs deadwax the errors' own words after it - and its
        // two ways on as actions
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RequestSpoken.card(row, runs: runs, gets: gets))
        .accessibilityHint(runs ? [row.reasonDetail, row.problemDetail].compactMap { $0 }.joined(separator: " ") : "")
        .accessibilityActions {
            ForEach(RequestAction.offered(row, gets: gets, online: true), id: \.self) { (action: RequestAction) in
                Button(action.words(row)) { onRetry(action == .askAgain) }
            }
        }
    }
}

/// What went wrong, in red - and, for whoever runs deadwax, the error's own words under it to open.
private struct ReasonLine: View {
    let text: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardLine(words: text, colour: DWPalette.redChipText)
            if let detail, !detail.isEmpty {
                DisclosureGroup {
                    Text(detail)
                        .font(Typeface.Phone.mono(.extraSmall))
                        .foregroundStyle(DWPalette.t2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(ErrorWords.forWhoever)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
                .tint(DWPalette.t2)
            }
        }
    }
}

/// Done (.row.tall): how it ended and how long ago, on the row's hairline. A download whose album is in the library
/// opens it - the row is a button - and one this download filed has the round ▶, which plays it (the screen decides, in
/// the tap, whether its songs are in hand). `note`: why a tapped row couldn't open; `opening` while it looks, faded so
/// the tap shows it was taken. `filed`: (manual search) how a manual search's download was filed, quietly under how it
/// ended.
struct DoneRowView: View {
    let row: RequestRow
    let opening: Bool
    let note: String?
    let filed: String?
    let runs: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if row.opens != nil {
                Button(action: onOpen) { face }
                    .buttonStyle(.plain)
                    .opacity(opening ? DWPalette.off : 1)
            } else {
                face
            }
            if row.opens != nil && row.plays {
                Button(action: onPlay) {
                    SharpSymbol(.play)
                        .font(Typeface.symbol(.footnote).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(DWPalette.phonePrimaryText)
                        .frame(width: CardSizes.face, height: CardSizes.face)
                        .background(DWPalette.phonePrimaryFace, in: Circle())
                        .frame(minWidth: CGFloat(DWLook.here.target), minHeight: CGFloat(DWLook.here.target))
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
        .padding(.vertical, 6)
        .lookHeight(DWLook.here.tallRowHeight)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
        // one element: everything the row shows, its tap opening its album, Play and Open its actions
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RequestSpoken.card(row, runs: runs, gets: true, filed: filed, note: note))
        .accessibilityHint(runs ? row.reasonDetail ?? "" : "")
        .accessibilityAddTraits(row.opens != nil ? .isButton : [])
        .accessibilityAction {
            if row.opens != nil { onOpen() }
        }
        .accessibilityActions {
            ForEach(RequestAction.offered(row, gets: true, online: true), id: \.self) { (action: RequestAction) in
                Button(action.words(row)) {
                    if action == .play { onPlay() } else { onOpen() }
                }
            }
        }
    }

    private var face: some View {
        HStack(alignment: .center, spacing: 12) {
            RequestCover(release: row.cover, size: CardSizes.doneCover)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Typeface.Phone.text(.row))
                    .foregroundStyle(DWPalette.head)
                    .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1)
                CardLine(words: row.line, colour: toneColour(row.lineTone))
                if let filed {
                    CardLine(words: filed)
                }
                if runs, let detail = row.reasonDetail, !detail.isEmpty {
                    Text(detail)
                        .font(Typeface.Phone.mono(.extraSmall))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !runs && row.reasonTell {
                    CardLine(words: ErrorWords.tell)
                }
                if let askedBy = row.askedBy {
                    CardLine(words: askedBy)
                }
                if let note {
                    CardLine(words: note, colour: DWPalette.amberText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
