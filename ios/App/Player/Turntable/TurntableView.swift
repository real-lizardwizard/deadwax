import DeadwaxCore
import DeadwaxTurntable
import SwiftUI
import UIKit

// The turntable's SwiftUI parts on Now Playing (notes/ios-specs/turntable.md 2.1, 2.2, 2.9, 2.11, 5.1): the plinth in
// the cover's room, the time line in the scrubber's row, the line over the plinth's foot, the speed's readout laid over
// it, and the look button.

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
                // where the readout goes: Now Playing lays it over its column there (TurntableReadoutLayer)
                .anchorPreference(key: PlinthPlaceKey.self, value: .bounds) { (bounds: Anchor<CGRect>) -> PlinthPlace? in
                    PlinthPlace(bounds: bounds, layout: layout)
                }
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

/// Where the plinth is drawn, and at which layout (5.1): the readout is laid over Now Playing's column there.
struct PlinthPlace {
    let bounds: Anchor<CGRect>
    let layout: TurntableLayout
}

struct PlinthPlaceKey: PreferenceKey {
    static var defaultValue: PlinthPlace? { nil }

    static func reduce(value: inout PlinthPlace?, nextValue: () -> PlinthPlace?) {
        value = value ?? nextValue()
    }
}

/// The speed's readout (5.1, 2.11): `1.00x` in its well at the plinth's bottom right corner, the toggled face off 1x,
/// a tap back to exactly 1x - drawn by DeadwaxTurntable's TurntableReadout, the face the plinth's renders draw, in a
/// control of its own. Laid over Now Playing's whole column rather than drawn in the plinth's layers, so it sits ABOVE
/// the line a failure or the silent record lays over the plinth's foot, as the web's z-index puts it. Its words grow
/// with the text size (a caption's 12 pt, scaled) up to 3.2% of the plinth; its target is a tap's, 44 pt, or 14% of a
/// small plinth; a long press at the accessibility sizes shows its large version. VoiceOver reads it from the deck
/// view, in the web's order after the fader - this control is hidden from it. Fades with the look's swap.
struct TurntableReadoutLayer: View {
    let place: PlinthPlace?
    let shown: Bool
    let swap: Animation?
    @Environment(DeckController.self) private var deck
    @Environment(PlayerModel.self) private var player
    /// UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12) (2.11)
    @ScaledMetric(relativeTo: .caption) private var textSize: CGFloat = 12

    var body: some View {
        GeometryReader { (space: GeometryProxy) in
            if let place {
                let plinth = space[place.bounds]
                let layout = place.layout
                let speed = player.speed
                let points = TurntableReadout.points(layout, scaled: Double(textSize))
                let face = TurntableReadout.size(speed, points: points)
                let target = CGFloat(layout.readoutTarget)
                ReadoutButton(deck: deck, speed: speed, points: points)
                    .frame(width: Swift.max(face.width, target), height: Swift.max(face.height, target))
                    .position(x: plinth.minX + CGFloat(layout.readout.x), y: plinth.minY + CGFloat(layout.readout.y))
                    .transition(.opacity)
            }
        }
        .opacity(shown ? 1 : 0)
        .animation(swap, value: shown)
        .allowsHitTesting(shown)
        .accessibilityHidden(true)
    }
}

/// The readout's control, sized by SwiftUI and drawing the face at its middle.
private struct ReadoutButton: UIViewRepresentable {
    let deck: DeckController
    let speed: Double
    let points: Double

    func makeUIView(context: Context) -> ReadoutControl {
        ReadoutControl(deck: deck, scale: context.environment.displayScale)
    }

    func updateUIView(_ control: ReadoutControl, context: Context) {
        control.show(speed, points: points)
    }
}

/// A tap back to 1x (nothing at 1x, the web's disabled button - the deck says so), and the large content viewer's
/// title: the readout's own words.
final class ReadoutControl: UIControl {
    private let face: TurntableReadout
    private weak var deck: DeckController?

    init(deck: DeckController, scale: CGFloat) {
        face = TurntableReadout(scale: scale)
        self.deck = deck
        super.init(frame: .zero)
        backgroundColor = .clear
        // the web's mono with tabular figures: the system's monospaced face (2.11)
        face.font = { (points: Double) -> CFTypeRef in
            UIFont.monospacedSystemFont(ofSize: CGFloat(points), weight: .regular)
        }
        layer.addSublayer(face.root)
        isAccessibilityElement = false
        showsLargeContentViewer = true
        addInteraction(UILargeContentViewerInteraction())
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ speed: Double, points: Double) {
        face.set(speed, points: points)
        largeContentTitle = TurntableWords.speedLabel(speed)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        face.root.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @objc private func tapped() {
        deck?.readoutTapped()
    }
}

/// The time line in the scrubber's row (2.1, 2.11): "2:31 of 7:05", led by "Needle up" or "Scrubbing" while a hand
/// moves it - the web's mono in the note's colour, one line whatever it says (smaller first, then cut at its end),
/// centred in a row the scrubber's height, so the swap moves no row.
///
/// Wide, never tall: the row's ZStack centres it on the hidden scrubber, which gives the row its height. A frame that
/// asked for the most height (`maxHeight: .infinity`) made the row as flexible as the cover's room above it, and the
/// column split its leftover height between the two - measured in a Mac probe of the same column, the room went from
/// 445 pt to 255.5 and the row from 66 to 255.5, so the plinth shrank and the titles jumped at every swap.
/// tests/test_ios_turntable_face.py holds the row to this.
struct TurntableTimeLine: View {
    @Environment(DeckController.self) private var deck

    var body: some View {
        Text(deck.timeLine)
            .font(.footnote.monospaced())
            .foregroundStyle(Palette.quiet)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
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
