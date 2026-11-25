import DeadwaxCore
import SwiftUI

/// The one-tap strip (dw.css's .chips - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look,
/// and the phone's pieces"): a page's parts in a row of buttons under its top, the one shown in the selection's fill and
/// edge - the Library's Albums | Artists | Songs (R2), Now Playing's sheet's Queue | Info | EQ (R3). Drawn nowhere until
/// those slices.
///
/// - Each button's face is 32 tall at least, growing with the text; a finger's target round it is 44 (DWTarget), and
///   the row is padded by the target's reach above and below - and the strip drawn as tall as its faces again - so the
///   scroll view, which takes no touch outside itself, holds the whole target.
/// - It starts at the leading edge (.chips) and never wraps: where its buttons don't fit the width, the strip scrolls
///   sideways, and the shown button is brought into view whenever it changes - by a tap or by the page's own swipe -
///   moving as the Library's swipe does (`.snappy`, none with Reduce Motion).
/// - VoiceOver hears a tab bar: each button a tab, the one shown selected.
/// - Capped at xxxLarge, as the tab bar is.
struct PhoneStrip<Part: Hashable>: View {
    let options: [Part]
    let words: (Part) -> String
    @Binding var shown: Part
    /// What VoiceOver calls the strip.
    let spoken: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollViewReader { (proxy: ScrollViewProxy) in
                ScrollView(.horizontal, showsIndicators: false) {
                    row
                }
                .onAppear {
                    proxy.scrollTo(shown, anchor: .center)
                }
                .onChange(of: shown) { (_: Part, now: Part) in
                    withAnimation(reduceMotion ? nil : .snappy) {
                        proxy.scrollTo(now, anchor: .center)
                    }
                }
            }
        }
        // .chips starts at its leading edge, where it fits as where it scrolls
        .frame(maxWidth: .infinity, alignment: .leading)
        // drawn as tall as its faces: the targets' reach (the row's padding) laid over what is above and below it
        .padding(.vertical, -reach)
        // .chips: padding 0 16px 10px
        .padding(.bottom, CGFloat(PhoneLook.stripFoot))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel(spoken)
    }

    private var row: some View {
        HStack(spacing: CGFloat(PhoneLook.stripGap)) {
            ForEach(options, id: \.self) { (option: Part) in
                button(option)
                    .id(option)
            }
        }
        .padding(.horizontal, CGFloat(PhoneLook.stripSide))
        // room for each button's whole target inside the scroll view
        .padding(.vertical, reach)
    }

    /// How far a button's target reaches above and below its 32 pt face: 6 on the phone.
    private var reach: CGFloat {
        CGFloat(DWLook.here.reach(PhoneLook.strip))
    }

    private func button(_ option: Part) -> some View {
        let on = option == shown
        return Button {
            shown = option
        } label: {
            Text(words(option))
                // .chips > button: 500; .chips > .on 600
                .font(Typeface.Phone.text(.strip).weight(on ? .semibold : .medium))
                .foregroundStyle(on ? DWPalette.selt : DWPalette.stripText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, CGFloat(PhoneLook.stripPadding))
                .lookHeight(PhoneLook.strip)
                .background {
                    // .chips > button's face, sheen and edge, no drop; .chips > .on the selection's fill and edge
                    if on {
                        DWRaised(shape: DWCorners.buttonShape, face: DWPalette.selbg, sheen: DWPalette.stripSheen,
                                 edge: DWPalette.selbd, drop: nil)
                    } else {
                        DWRaised(shape: DWCorners.buttonShape, face: DWPalette.stripFace, sheen: DWPalette.stripSheen,
                                 edge: DWPalette.stripEdge, drop: nil)
                    }
                }
                .contentShape(DWTarget(face: DWCorners.buttonShape))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
