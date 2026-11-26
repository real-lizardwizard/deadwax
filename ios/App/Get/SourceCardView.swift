import DeadwaxCore
import SwiftUI

/// One place an album can come from, in Choose a source (Phase 6, slice 2 - phase6-get-requests.md 2.10, 3.5; the
/// web's app/SourceCard.tsx as a phone draws it, its words and rules Core's Sources) - since the redesign's slice R7
/// (notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)") as iSources.dc.html draws it on the
/// phone and Get.dc.html in the Mac's dock:
///
/// - The top line: the match score, "92%" - a green chip from 75 (the band a pick needs), amber under it - the folder,
///   "from <peer>" (and, for a set shared one folder per disc, "in 2 parts, one per disc"), and Get. The best match's Get
///   is the one primary button, wherever the sort puts its card; the rest are the look's own button (on the phone its
///   words in the accent). Each Get is named for its folder and its peer (one peer often shares a FLAC folder and an MP3
///   one of an album).
/// - Its facts in three columns, each its label over its readout: Speed (green when measured - where the number comes
///   from under it), Tracks (amber when tracks are missing), Quality, Size and Starts (green "now", amber while it
///   waits) - two columns where the text is too large for three, one over another past that - and what it is missing,
///   in amber.
/// - While deadwax can't be reached (`gets` false), the card is dimmed - found before - and its Get is off (slice 2's
///   review, finding 1).
/// - WHY IT SCORED WHAT IT DID, behind a tap on the score: the edition words in the folder's name in their colours, and
///   each signal's chip with what it measures beside it. Last on the card, so opening it moves nothing above; the
///   chevron turns.
/// - On the phone the card is flat (PhoneCard: no face, a hairline under it); on the Mac a box on the panel, the best
///   match's edged in the accent.
struct SourceCardView: View {
    let candidate: Candidate
    let best: Bool
    /// Its Get can be asked: deadwax is in reach.
    let gets: Bool
    let onGet: () -> Void

    @State private var open = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if Platform.mac {
            card
                .padding(SourceCardLook.macPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DWPalette.card, in: DWCorners.boxShape)
                .overlay(DWCorners.boxShape.strokeBorder(best ? DWPalette.acc : DWPalette.line, lineWidth: 1))
                .opacity(gets ? 1 : DWPalette.off)
        } else {
            PhoneCard {
                card
            }
            .opacity(gets ? 1 : DWPalette.off)
        }
    }

    private var card: some View {
        let percent = Sources.percent(candidate)
        return VStack(alignment: .leading, spacing: SourceCardLook.gap) {
            top(percent)
            facts
            if let missing = Sources.missingLine(candidate) {
                Text(missing)
                    .font(SourceCardLook.small)
                    .foregroundStyle(DWPalette.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if open {
                reasons(percent)
            }
        }
    }

    // MARK: the top line

    private func top(_ percent: Double) -> some View {
        HStack(spacing: SourceCardLook.topGap) {
            score(percent)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.directoryName)
                    .font(SourceCardLook.name)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(SourcesWords.from(candidate))
                    .font(SourceCardLook.extraSmall)
                    .foregroundStyle(DWPalette.t3)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(SourcesWords.get, action: onGet)
                .buttonStyle(DWButtonStyle(kind: best ? .pri : .normal, size: .small))
                .fixedSize()
                .disabled(!gets)
                .accessibilityLabel(SourcesWords.getLabel(candidate))
        }
    }

    /// The score, a chip that opens why it is what it is - 44 points to a finger on the phone.
    private func score(_ percent: Double) -> some View {
        let good = Sources.band(percent) == .good
        return Button {
            open.toggle()
        } label: {
            HStack(spacing: 2) {
                DWChip(words: SourcesWords.percent(percent), tone: good ? .good : .caution)
                Image(systemName: "chevron.down")
                    .font(Typeface.symbol(.caption2).weight(.semibold))
                    .foregroundStyle(DWPalette.t3)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .frame(minHeight: CGFloat(DWLook.here.target))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SourcesWords.match(percent))
        .accessibilityValue(open ? SourcesWords.expanded : SourcesWords.collapsed)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: the facts

    @ViewBuilder private var facts: some View {
        let missing = Sources.missingLine(candidate) != nil
        let starts = Sources.startsFact(candidate)
        let size = Sources.size(candidate.totalSize)
        let speed = Sources.speedFact(candidate)
        let all: [Fact] = [
            Fact(label: SourcesWords.speed, value: speed.text, note: speed.note, bold: true,
                 colour: speed.kind == .measured ? DWPalette.greenText : speed.kind == .unknown ? DWPalette.t3 : DWPalette.text),
            Fact(label: SourcesWords.tracks, value: Sources.tracksText(candidate),
                 colour: missing ? DWPalette.amberText : DWPalette.text),
            Fact(label: SourcesWords.quality, value: Sources.qualityText(candidate), colour: DWPalette.text),
            Fact(label: SourcesWords.size, value: size.isEmpty ? SourcesWords.noSize : size, colour: DWPalette.text),
            Fact(label: SourcesWords.starts, value: starts.text,
                 colour: starts.waits ? DWPalette.amberText : DWPalette.greenText),
        ]
        ViewThatFits(in: .horizontal) {
            grid(all, columns: 3)
            grid(all, columns: 2)
            VStack(alignment: .leading, spacing: SourceCardLook.factRows) {
                ForEach(all.indices, id: \.self) { (at: Int) in all[at] }
            }
        }
    }

    /// The facts in `columns` columns (iSources' grid: three of them, 8 between rows and 6 between columns).
    private func grid(_ all: [Fact], columns: Int) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: SourceCardLook.factColumns, verticalSpacing: SourceCardLook.factRows) {
            ForEach(Array(stride(from: 0, to: all.count, by: columns)), id: \.self) { (start: Int) in
                GridRow {
                    ForEach(start..<min(start + columns, all.count), id: \.self) { (at: Int) in
                        all[at]
                            .frame(minWidth: SourceCardLook.factLeast, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: why

    private func reasons(_ percent: Double) -> some View {
        let tags = Sources.editionTags(candidate)
        let chips = Sources.signalChips(candidate)
        return VStack(alignment: .leading, spacing: 6) {
            Text(SourcesWords.reasons(percent))
                .font(SourceCardLook.small.weight(.semibold))
                .foregroundStyle(DWPalette.t2)
                .accessibilityAddTraits(.isHeader)
            if !tags.isEmpty {
                Wrap(spacing: 6) {
                    ForEach(tags.indices, id: \.self) { (at: Int) in
                        DWChip(words: tags[at].tag, tone: Self.tone(tags[at].tone))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(SourcesWords.inItsName + tags.map(\.tag).joined(separator: ", "))
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(chips) { (chip: Sources.SignalChip) in
                    GridRow {
                        DWChip(words: "\(chip.label) \(SourcesWords.percent(chip.value))", tone: Self.tone(chip.band))
                            .fixedSize()
                        Text(chip.meaning)
                            .font(SourceCardLook.extraSmall)
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A signal's band as a chip's tone: green from 75, amber from 40, red under.
    private static func tone(_ band: Sources.Band) -> DWChip.Tone {
        switch band {
        case .good: return .good
        case .mid: return .caution
        case .bad: return .bad
        }
    }

    /// An edition word's colour as the main page drew it, as a chip's tone.
    private static func tone(_ tone: Sources.EditionTone) -> DWChip.Tone {
        switch tone {
        case .amber: return .caution
        case .red: return .bad
        case .purple: return .marked
        case .green: return .good
        case .plain: return .plain
        }
    }
}

/// (R7) The card's numbers and type (iSources.dc.html, Get.dc.html - each line's `drawn:` comment says where).
enum SourceCardLook {
    static let gap: CGFloat = 9             // drawn: iSources .card gap
    static let topGap: CGFloat = 8          // drawn: iSources top line gap
    static let factRows: CGFloat = 8        // drawn: iSources facts grid row gap
    static let factColumns: CGFloat = 6     // drawn: iSources facts grid column gap
    static let factLeast: CGFloat = 72      // a fact's least width, so three columns never squeeze one to nothing
    static let macPadding: CGFloat = 10     // drawn: Get .item padding

    /// The folder's name (iSources: .b at 15), the small words (.s), the extra-small labels (.xs) - a fact's readout is
    /// set where it is drawn (Fact). On the Mac Get.dc.html's 13, 12 and 11.5 - Typeface.Mac's .base, .small and .label,
    /// reached through the look's roles of those very sizes (.field, .smallButton, .chip): a page both devices draw
    /// names no Mac piece (test_ios_mac_reach).
    static var name: Font { Platform.mac ? Typeface.Look.text(.field).weight(.semibold) : Typeface.subheadline.weight(.bold) }
    static var small: Font { Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small) }
    static var extraSmall: Font { Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.text(.extraSmall) }
}

/// One of a card's facts: its label over its readout, read as one - the value on one line, as the folder's name is, and
/// on up to three at the accessibility sizes (slice 2's review, finding 4: "FLAC, MP3 VBR 128-320k" in the one-over-
/// another fallback); the speed's note ("their usual speed") under it. ViewThatFits measures a text's one-line width
/// whatever its limit, so the side-by-side layouts are chosen as before.
private struct Fact: View {
    let label: String
    let value: String
    var note = ""
    var bold = false
    let colour: Color

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(SourceCardLook.extraSmall)
                .foregroundStyle(DWPalette.t3)
            // the readout (iSources .s mono; the Mac's small mono), a line of its own under its label
            Text(value)
                .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                .fontWeight(bold ? .bold : nil)
                .foregroundStyle(colour)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            if !note.isEmpty {
                Text(note)
                    .font(SourceCardLook.extraSmall)
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
