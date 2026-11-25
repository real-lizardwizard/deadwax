import DeadwaxCore
import SwiftUI

/// A pop-up button (Sort ▾, an output ▾ - the redesign, slices R1 and R1b, notes/ios.md "The redesign, slice R1b: the
/// shared look, and the phone's pieces"; R1's MacPopUp, moved here for both): SwiftUI's Menu, its items the caller's,
/// with the look's button for its face - the words and dw.css's caret after them (.btn's gap of 6). The menu that opens
/// is the system's own, on either device. Should Catalyst draw its own pop-up face over ours, that is accepted (the build
/// plan's section 2). (R1c - notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)") On the phone a flat
/// button's - the words and the caret in the accent, no face; drawn on no phone screen yet.
struct DWPopUp<Items: View>: View {
    let words: String
    var size: DWButtonStyle.Size = .standard
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 6) {
                Text(words)
                DWCaret(colour: Platform.mac ? DWPalette.buttonText : DWPalette.acc)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(DWButtonStyle(kind: .normal, size: size))
        .fixedSize()
    }
}

/// dw.css's .caret: a triangle 8 wide and 4 tall pointing down, in the words' colour - given, as DWPalette's: the
/// inherited foreground style would be the system's label colour wherever a caller set none.
struct DWCaret: View {
    let colour: Color

    var body: some View {
        CaretShape()
            .fill(colour)
            .frame(width: 8, height: 4)
            .accessibilityHidden(true)
    }

    private struct CaretShape: Shape {
        func path(in rect: CGRect) -> Path {
            Path { (path: inout Path) -> Void in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
