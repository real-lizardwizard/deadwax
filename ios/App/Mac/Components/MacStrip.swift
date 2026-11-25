import DeadwaxCore
import SwiftUI

/// A strip of joined buttons (the Mac redesign, slice R4 - notes/ios.md "The redesign, slice R4: the player bar, the mini
/// player and the tab bar"): the player bar's Queue, Lyrics and Info, as dw.css draws them (`.player > .f:last-child >
/// :nth-child(1)`, `(2)`, `(3)`) - .btn's faces, each overlapping the one before by its 1 pt edge (`margin-left: -7px`
/// across the tools' gap of 6), a button's corners (DWCorners.button) at the strip's two ends alone and square where
/// they join. The one lit (`.btn.on`, `position: relative`) is drawn over its neighbours, so its edge shows whole: the
/// strip gives that button the higher zIndex (a style's own can't reach past its button to the strip's stack).
struct MacStripButtonStyle: ButtonStyle {
    /// Where in the strip: its first button (the corners at its start), its last (at its end), or between.
    enum Place: Sendable {
        case first, middle, last
    }

    let place: Place
    /// .btn.on: its panel shows.
    var on = false

    func makeBody(configuration: Configuration) -> some View {
        MacStripButton(configuration: configuration, place: place, on: on)
    }
}

private struct MacStripButton: View {
    let configuration: ButtonStyleConfiguration
    let place: MacStripButtonStyle.Place
    let on: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let shape = MacStripShape(leading: place == .first, trailing: place == .last)
        let pressed = configuration.isPressed && enabled
        configuration.label
            .font(Typeface.Look.text(.button).weight(.medium))
            .foregroundStyle(on ? DWPalette.selt : DWPalette.buttonText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, CGFloat(DWLook.here.buttonPadding))
            .frame(height: CGFloat(MacLook.buttonHeight))
            .background {
                ZStack {
                    // DWRaised's face, its gradient turned over while pressed - the rectangle's, clipped to the strip's
                    // corners, so a corner at one end only stays at that end
                    Rectangle()
                        .fill(on ? DWPalette.selbg : DWPalette.buttonFace)
                        .rotationEffect(.degrees(pressed ? 180 : 0))
                        .clipShape(shape)
                    if !pressed {
                        shape.inset(by: 1)
                            .fill((on ? DWPalette.selbg : DWPalette.buttonFace)
                                .shadow(.inner(color: DWPalette.buttonSheen, radius: 0, x: 0, y: 1)))
                    }
                    shape.strokeBorder(on ? DWPalette.selbd : DWPalette.buttonEdge, lineWidth: 1)
                }
                .shadow(color: DWPalette.buttonDrop, radius: 0.5, x: 0, y: 1)
                .accessibilityHidden(true)
            }
            .contentShape(shape)
            .opacity(enabled ? 1 : DWPalette.off)
    }
}

/// A strip button's outline: a button's corners (DWCorners.button, the Mac's 4) at the strip's ends alone.
struct MacStripShape: InsettableShape {
    let leading: Bool
    let trailing: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let corner = max(min(DWCorners.button - inset, box.height / 2), 0)
        let lead = leading ? corner : 0
        let trail = trailing ? corner : 0
        var path = Path()
        path.move(to: CGPoint(x: box.minX + lead, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - trail, y: box.minY))
        if trail > 0 {
            path.addArc(center: CGPoint(x: box.maxX - trail, y: box.minY + trail), radius: trail,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - trail))
        if trail > 0 {
            path.addArc(center: CGPoint(x: box.maxX - trail, y: box.maxY - trail), radius: trail,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: box.minX + lead, y: box.maxY))
        if lead > 0 {
            path.addArc(center: CGPoint(x: box.minX + lead, y: box.maxY - lead), radius: lead,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + lead))
        if lead > 0 {
            path.addArc(center: CGPoint(x: box.minX + lead, y: box.minY + lead), radius: lead,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> MacStripShape {
        var inner = self
        inner.inset += amount
        return inner
    }
}
