import DeadwaxCore
import SwiftUI

/// A pop-up button (Sort ▾, an output ▾ - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1: the
/// frame and the shared pieces"): SwiftUI's Menu, its items the caller's, with a Mac button for its face - the words and
/// dw.css's caret after them (.btn's gap of 6). The menu that opens is macOS's own. Should Catalyst draw its own pop-up
/// face over ours, that is accepted (the build plan's section 2).
struct MacPopUp<Items: View>: View {
    let words: String
    var small = false
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 6) {
                Text(words)
                MacCaret(colour: MacPalette.buttonText)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(MacButtonStyle(kind: .normal, small: small))
        .fixedSize()
    }
}

/// dw.css's .caret: a triangle 8 wide and 4 tall pointing down, in the words' colour - given, as MacPalette's: the
/// inherited foreground style would be the system's label colour wherever a caller set none.
struct MacCaret: View {
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
