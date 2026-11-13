import DeadwaxCore
import SwiftUI

// The turntable's SwiftUI parts on Now Playing (notes/ios-specs/turntable.md 2.1, 2.2, 2.9, 2.11): the plinth in the
// cover's room, the time line in the scrubber's row, the line over the plinth's foot, and the look button.

/// The plinth in the cover's room (2.2): as big as fits it both ways, at most 440 pt, 24 pt clear above (the arm's
/// counterweight reaches past the plinth's top edge) and 12 pt round it, centred in what is left - the web's `.app-tt`.
/// Sized by the room, never by the text size.
struct TurntableView: View {
    @Environment(DeckController.self) private var deck

    var body: some View {
        GeometryReader { (space: GeometryProxy) in
            let layout = TurntableFit.layout(roomWidth: Double(space.size.width), roomHeight: Double(space.size.height))
            DeckPlinth(deck: deck, layout: layout)
                .frame(width: CGFloat(layout.width), height: CGFloat(layout.height))
                .padding(EdgeInsets(top: CGFloat(TurntableFace.clear), leading: CGFloat(TurntableFace.pad),
                                    bottom: CGFloat(TurntableFace.pad), trailing: CGFloat(TurntableFace.pad)))
                .frame(width: space.size.width, height: space.size.height)
        }
    }
}

/// The UIKit view, laid out at the layout the room gives.
private struct DeckPlinth: UIViewRepresentable {
    let deck: DeckController
    let layout: TurntableLayout

    func makeUIView(context: Context) -> TurntableDeckUIView {
        TurntableDeckUIView(deck: deck, layout: layout, scale: context.environment.displayScale)
    }

    func updateUIView(_ view: TurntableDeckUIView, context: Context) {
        view.relay(layout)
    }

    static func dismantleUIView(_ view: TurntableDeckUIView, coordinator: ()) {
        view.detach()
    }
}

/// The time line in the scrubber's row (2.1, 2.11): "2:31 of 7:05", led by "Needle up" or "Scrubbing" while a hand
/// moves it - the web's mono in the note's colour, one line whatever it says (smaller first, then cut at its end),
/// centred in a row the scrubber's height, so the swap moves no row.
struct TurntableTimeLine: View {
    @Environment(DeckController.self) private var deck

    var body: some View {
        Text(deck.timeLine)
            .font(.footnote.monospaced())
            .foregroundStyle(Palette.quiet)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// A failure's line, or the silent record's, laid over the plinth's foot on the turntable (2.1, 2.8): two lines at
/// most, centred like the titles under it, taking no touch - so the plinth's size never changes as one comes or goes.
/// Its size stops at the first accessibility size: two lines over a plinth at the largest would cover half the record.
struct TurntableFootLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .center)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .allowsHitTesting(false)
    }
}

/// The look button (2.1): the boards' secondary button drawn at 36 pt inside a 44 pt target - a rounded square with a
/// hairline edge, the web's top-to-bottom fill (reversed while pressed) and a 1 pt highlight inside its top edge -
/// holding the web's own glyph: the record while the cover shows, the square while the turntable does.
struct LookButton: View {
    let showingTurntable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LookGlyph(record: !showingTurntable)
                .stroke(Palette.onSecondary, lineWidth: CGFloat(TurntableFace.iconStroke))
                .frame(width: CGFloat(TurntableFace.lookIcon), height: CGFloat(TurntableFace.lookIcon))
        }
        .buttonStyle(LookFace())
        .accessibilityLabel(TurntableWords.lookButton(showingTurntable: showingTurntable))
        .accessibilityShowsLargeContentViewer { Text(TurntableWords.lookButton(showingTurntable: showingTurntable)) }
    }
}

/// STYLE.md's secondary button at the boards' 36 pt.
private struct LookFace: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(TurntableFace.lookRadius))
        return configuration.label
            .frame(width: CGFloat(TurntableFace.lookFace), height: CGFloat(TurntableFace.lookFace))
            .background(shape.fill(configuration.isPressed ? Palette.secondaryFillPressed : Palette.secondaryFill))
            .overlay(alignment: .top) {
                // --dw-highlight: inset 0 1px 0 - a line inside the top edge, following its corners
                shape.inset(by: CGFloat(TurntableFace.hairline + TurntableFace.highlight / 2))
                    .stroke(Palette.highlight, lineWidth: CGFloat(TurntableFace.highlight))
                    .mask(alignment: .top) {
                        Rectangle().frame(height: CGFloat(TurntableFace.lookRadius))
                    }
            }
            .overlay(shape.strokeBorder(Palette.secondaryEdge, lineWidth: CGFloat(TurntableFace.hairline)))
            // the 44 pt target round the 36 pt face (--pl-hit)
            .frame(width: CGFloat(TurntableFace.hit), height: CGFloat(TurntableFace.hit))
            .contentShape(Rectangle())
    }
}

/// The web's RecordIcon (two circles, r 8.5 and 2.5) and SquareIcon (15 by 15, radius 2), on their 24 grid, drawn at
/// the frame's size.
private struct LookGlyph: Shape {
    let record: Bool

    func path(in rect: CGRect) -> Path {
        let k = Swift.min(rect.width, rect.height) / 24
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        if record {
            for r in [TurntableFace.recordIconRings.outer, TurntableFace.recordIconRings.inner] {
                let radius = CGFloat(r) * k
                path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
            }
        } else {
            let side = CGFloat(TurntableFace.squareIcon.side) * k
            let corner = CGFloat(TurntableFace.squareIcon.radius) * k
            path.addRoundedRect(in: CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side),
                                cornerSize: CGSize(width: corner, height: corner))
        }
        return path
    }
}
