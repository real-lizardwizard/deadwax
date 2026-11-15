import DeadwaxCore
import SwiftUI

/// One place an album can come from, in the Sources sheet (Phase 6, slice 2 - phase6-get-requests.md 2.10, 3.5; the
/// web's app/SourceCard.tsx as a phone draws it, its words and rules Core's Sources):
///
/// - The top line: the match score, "92%" - green from 75 (the band a pick needs), amber under it - the folder, "from
///   <peer>" (and, for a set shared one folder per disc, "in 2 parts, one per disc"), and Get. The best match's Get is
///   the sheet's one primary button, wherever the sort puts its card, its card edged in --dw-best; the rest are tinted.
///   Each Get is named for its folder and its peer (one peer often shares a FLAC folder and an MP3 one of an album).
/// - The speed leads, in its well with its bar (against 3 MB/s, capped), saying where its number comes from - measured
///   (green), their usual speed, or none reported yet.
/// - Then Tracks (amber when tracks are missing), Quality, Size and Starts (green "now", amber while it waits), side by
///   side - two by two, or one over another, where the text is too large for that - and what it is missing, in amber.
/// - WHY IT SCORED WHAT IT DID, behind a tap on the score (a phone's, as the web's sheet has it): the edition words in
///   the folder's name in their colours, and each signal's chip with what it measures beside it. Last on the card, so
///   opening it moves nothing above; the chevron turns.
struct SourceCardView: View {
    let candidate: Candidate
    let best: Bool
    let onGet: () -> Void

    @State private var open = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let percent = Sources.percent(candidate)
        VStack(alignment: .leading, spacing: 10) {
            top(percent)
            speed
            facts
            if let missing = Sources.missingLine(candidate) {
                Text(missing)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if open {
                reasons(percent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: Corners.cardShape)
        .overlay(Corners.cardShape.strokeBorder(best ? Palette.best : Palette.border))
    }

    // MARK: the top line

    private func top(_ percent: Double) -> some View {
        HStack(spacing: 12) {
            score(percent)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.directoryName)
                    .font(Typeface.subheadline.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(SourcesWords.from(candidate))
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            get
        }
    }

    /// The score, a button that opens why it is what it is - 44 points to a finger.
    private func score(_ percent: Double) -> some View {
        let good = Sources.band(percent) == .good
        return Button {
            open.toggle()
        } label: {
            HStack(spacing: 2) {
                Text(SourcesWords.percent(percent))
                    .font(Typeface.mono(.subheadline).weight(.bold))
                Image(systemName: "chevron.down")
                    .font(Typeface.symbol(.caption2).weight(.semibold))
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .foregroundStyle(good ? Palette.held : Palette.amber)
            .padding(.horizontal, 6)
            .frame(minWidth: 38, minHeight: 32)
            .background(Corners.controlShape.fill(good ? Palette.heldFill : Palette.amberFill))
            .overlay(Corners.controlShape.strokeBorder(good ? Palette.heldEdge : Palette.amberEdge))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: open)
        .accessibilityLabel(SourcesWords.match(percent))
        .accessibilityValue(open ? SourcesWords.expanded : SourcesWords.collapsed)
    }

    /// Get: the best match's the primary, the rest tinted - in the tap, the download asked for.
    @ViewBuilder private var get: some View {
        if best {
            Button(SourcesWords.get, action: onGet)
                .buttonStyle(PrimaryFace())
                .accessibilityLabel(SourcesWords.getLabel(candidate))
        } else {
            Button(SourcesWords.get, action: onGet)
                .buttonStyle(TintedFace())
                .accessibilityLabel(SourcesWords.getLabel(candidate))
        }
    }

    // MARK: the speed

    private var speed: some View {
        let fact = Sources.speedFact(candidate)
        return VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    speedValue(fact)
                    Spacer(minLength: 0)
                    speedNote(fact)
                }
                VStack(alignment: .leading, spacing: 2) {
                    speedValue(fact)
                    speedNote(fact)
                }
            }
            SpeedBar(percent: fact.percent, kind: fact.kind)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Palette.well, in: Corners.controlShape)
        .accessibilityElement(children: .combine)
    }

    private func speedValue(_ fact: Sources.SpeedFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(SourcesWords.speed)
                .font(Typeface.caption)
                .foregroundStyle(Palette.label)
            Text(fact.text)
                .font(Typeface.mono(.body).weight(.bold))
                .foregroundStyle(fact.kind == .measured ? Palette.held
                                 : fact.kind == .unknown ? Palette.textTertiary : Palette.onSecondary)
        }
    }

    private func speedNote(_ fact: Sources.SpeedFact) -> some View {
        Text(fact.note)
            .font(Typeface.caption)
            .foregroundStyle(Palette.text2)
    }

    // MARK: the facts

    @ViewBuilder private var facts: some View {
        let missing = Sources.missingLine(candidate) != nil
        let starts = Sources.startsFact(candidate)
        let size = Sources.size(candidate.totalSize)
        let tracks = Fact(label: SourcesWords.tracks, value: Sources.tracksText(candidate), mono: false,
                          colour: missing ? Palette.amber : Color.primary)
        let quality = Fact(label: SourcesWords.quality, value: Sources.qualityText(candidate), mono: true, colour: .primary)
        let sized = Fact(label: SourcesWords.size, value: size.isEmpty ? SourcesWords.noSize : size, mono: true,
                         colour: .primary)
        let start = Fact(label: SourcesWords.starts, value: starts.text, mono: false,
                         colour: starts.waits ? Palette.amber : Palette.held)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                tracks
                Spacer(minLength: 0)
                quality
                Spacer(minLength: 0)
                sized
                Spacer(minLength: 0)
                start
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    tracks
                    quality
                }
                GridRow {
                    sized
                    start
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                tracks
                quality
                sized
                start
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: why

    private func reasons(_ percent: Double) -> some View {
        let tags = Sources.editionTags(candidate)
        let chips = Sources.signalChips(candidate)
        return VStack(alignment: .leading, spacing: 6) {
            Text(SourcesWords.reasons(percent))
                .font(Typeface.caption.weight(.semibold))
                .foregroundStyle(Palette.text2)
                .accessibilityAddTraits(.isHeader)
            if !tags.isEmpty {
                Wrap(spacing: 6) {
                    ForEach(tags.indices, id: \.self) { (at: Int) in
                        EditionTag(tag: tags[at].tag, tone: tags[at].tone)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(SourcesWords.inItsName + tags.map(\.tag).joined(separator: ", "))
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(chips) { (chip: Sources.SignalChip) in
                    GridRow {
                        SignalBadge(chip: chip)
                        Text(chip.meaning)
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One of a card's facts: its label over its value, read as one.
private struct Fact: View {
    let label: String
    let value: String
    let mono: Bool
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typeface.caption)
                .foregroundStyle(Palette.label)
            Text(value)
                .font(mono ? Typeface.mono(.footnote) : Typeface.footnote)
                .foregroundStyle(colour)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The speed's bar: its sunken track, filled to the speed against 3 MB/s - green for one measured, grey for the peer's
/// usual, none for none reported.
private struct SpeedBar: View {
    let percent: Double
    let kind: Sources.SpeedFact.Kind

    private static let height: CGFloat = 8

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .leading) {
                Corners.trackShape
                    .fill(Palette.barTrack)
                Group {
                    switch kind {
                    case .measured: Corners.fillShape.fill(Palette.barGreen)
                    case .advertised: Corners.fillShape.fill(Palette.barGrey)
                    case .unknown: Color.clear
                    }
                }
                .frame(width: max(0, (space.size.width - 2) * min(max(percent, 0), 100) / 100))
                .padding(1)
            }
            .overlay(Corners.trackShape.strokeBorder(Palette.barEdge, lineWidth: 1))
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

/// A signal's chip: its word and its number, in its band's colour - green from 75, amber from 40, red under.
private struct SignalBadge: View {
    let chip: Sources.SignalChip

    var body: some View {
        let colours = self.colours
        HStack(spacing: 4) {
            Text(chip.label)
            Text(SourcesWords.percent(chip.value))
                .font(Typeface.mono(.caption))
        }
        .font(Typeface.caption)
        .foregroundStyle(colours.text)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(minHeight: 22)
        .background(Corners.controlShape.fill(colours.fill))
        .overlay(Corners.controlShape.strokeBorder(colours.edge))
    }

    private var colours: (text: Color, fill: Color, edge: Color) {
        switch chip.band {
        case .good: return (Palette.held, Palette.heldFill, Palette.heldEdge)
        case .mid: return (Palette.amber, Palette.amberFill, Palette.amberEdge)
        case .bad: return (Palette.danger, Palette.dangerFill, Palette.dangerEdge)
        }
    }
}

/// An edition word found in the folder's name, in its colour as the main page drew it.
private struct EditionTag: View {
    let tag: String
    let tone: Sources.EditionTone

    var body: some View {
        let colours = self.colours
        Text(tag)
            .font(Typeface.caption.weight(.semibold))
            .foregroundStyle(colours.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Corners.controlShape.fill(colours.fill))
            .overlay(Corners.controlShape.strokeBorder(colours.edge))
    }

    private var colours: (text: Color, fill: AnyShapeStyle, edge: Color) {
        switch tone {
        case .amber: return (Palette.amber, AnyShapeStyle(Palette.amberFill), Palette.amberEdge)
        case .red: return (Palette.danger, AnyShapeStyle(Palette.dangerFill), Palette.dangerEdge)
        case .purple: return (Palette.accentText, AnyShapeStyle(Palette.badgeFill), Palette.badgeEdge)
        case .green: return (Palette.held, AnyShapeStyle(Palette.heldFill), Palette.heldEdge)
        case .plain: return (Palette.onSecondary, AnyShapeStyle(Palette.secondaryFill), Palette.secondaryEdge)
        }
    }
}

/// A source's Get other than the best match's (.app-source-get.is-tinted): --dw-toggled-bg under --dw-accent-text, its
/// edge --dw-toggled-border - the primary's size, so the two line up card to card.
struct TintedFace: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TintedFaceBody(configuration: configuration)
    }
}

private struct TintedFaceBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Typeface.body.weight(.semibold))
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(Corners.controlShape.fill(configuration.isPressed ? Palette.pressed : Palette.toggledFill))
            .overlay(Corners.controlShape.strokeBorder(Palette.toggledEdge))
            .opacity(isEnabled ? 1 : Palette.off)
            .contentShape(Corners.controlShape)
    }
}

/// Words laid in rows, wrapping at the width offered - a card's edition words.
private struct Wrap: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
