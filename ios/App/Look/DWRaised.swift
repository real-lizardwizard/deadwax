import DeadwaxCore
import SwiftUI

/// A raised face, as dw.css draws a button, a strip's button or a player's key (the redesign, slices R1 and R1b -
/// notes/ios.md "The redesign, slice R1b: the shared look, and the phone's pieces"; R1's MacRaised, moved here for both):
/// its gradient, a sheen along its top inside its edge (the rule's `inset 0 1px 0`), its 1 pt edge and, where the rule
/// draws one, its drop under it (`0 1px 1px` - a strip's button has none) - and pressed, the gradient turned over and
/// the sheen gone, so it sits in rather than lights up (the web's secondary pill turns its gradient over when pressed;
/// dw.css draws no pressed state of its own). Every colour is the caller's, from DWPalette or MacPalette.
struct DWRaised<Face: InsettableShape>: View {
    let shape: Face
    let face: LinearGradient
    let sheen: Color
    let edge: Color
    /// The drop under it; none where the rule's box-shadow has only the sheen.
    let drop: Color?
    var pressed = false

    var body: some View {
        ZStack {
            if pressed {
                shape.fill(face)
                    .rotationEffect(.degrees(180))
            } else {
                shape.fill(face)
                shape.inset(by: 1)
                    .fill(face.shadow(.inner(color: sheen, radius: 0, x: 0, y: 1)))
            }
            shape.strokeBorder(edge, lineWidth: 1)
        }
        .shadow(color: drop ?? Color.clear, radius: drop == nil ? 0 : 0.5, x: 0, y: drop == nil ? 0 : 1)
        .accessibilityHidden(true)
    }
}

/// A 1 pt line along an edge of a strip (a border-top, a border-bottom, a row's hairline) or its sheen just inside it.
struct DWRule: View {
    let colour: Color
    var vertical = false

    var body: some View {
        colour
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

// MARK: sizes on this device

extension DWLook {
    /// The sizes this device draws (Core's DWLook: the Mac's MacLook's, the phone's dw.css's `.dw.ph` rules).
    static var here: DWLook { .of(Platform.device) }
}

extension View {
    /// A height of the look's: exact on the Mac, as R1 drew it and a Mac's own controls are; on the phone a minimum, so
    /// it grows with the text size as everything there does (DWLook's `grows`).
    @ViewBuilder func lookHeight(_ height: Double) -> some View {
        if DWLook.here.grows {
            frame(minHeight: CGFloat(height))
        } else {
            frame(height: CGFloat(height))
        }
    }

    /// A square of the look's (a toggle, a tab's icon): exact on the Mac, at least that on the phone.
    @ViewBuilder func lookSquare(_ side: Double) -> some View {
        if DWLook.here.grows {
            frame(minWidth: CGFloat(side), minHeight: CGFloat(side))
        } else {
            frame(width: CGFloat(side), height: CGFloat(side))
        }
    }
}

// MARK: Core's layouts, placed

extension LookSize {
    /// What SwiftUI measured, for Core's layout rules (MetaLine, LibraryTopFit - R2b).
    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }
}

extension LayoutSubview {
    /// Placed where Core put it - `box`'s top leading corner in the layout's `bounds` - and given the box's size.
    func lookPlace(_ box: LookBox, in bounds: CGRect) {
        place(at: CGPoint(x: bounds.minX + CGFloat(box.x), y: bounds.minY + CGFloat(box.y)), anchor: .topLeading,
              proposal: ProposedViewSize(width: CGFloat(box.width), height: CGFloat(box.height)))
    }
}

/// Where a finger or the pointer takes a control: its face - and on the phone, where the face is shorter than a finger's
/// target (DWLook's 44, the build plan's "a finger's targets at least 44"), that face reaching above and below it to the
/// target (DWLook's `reach`). Never sideways: a target grown sideways would reach into the control beside it (the
/// Library's Grid and List, side by side), as LibrarySwitchControl's SegmentReach never does. The Mac's target is
/// 0: its pointer is exact, so a control there takes its face's own shape, as R1's did.
struct DWTarget<Face: Shape>: Shape {
    let face: Face

    func path(in rect: CGRect) -> Path {
        let reach = CGFloat(DWLook.here.reach(Double(rect.height)))
        guard reach > 0 else { return face.path(in: rect) }
        return Path(rect.insetBy(dx: 0, dy: -reach))
    }
}
