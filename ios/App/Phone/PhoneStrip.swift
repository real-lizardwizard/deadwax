import DeadwaxCore
import SwiftUI

/// The one-tap strip (dw.css's .chips - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look,
/// and the phone's pieces"): a page's parts in a row under its top - Now Playing's sheet's Queue | Info | EQ (R3), and
/// the strips later slices draw (Edit album's, Search's, Server settings', the Event log's, an artist's). (R1c -
/// notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)") Words, with no face: at 15 in the second
/// colour, 22 apart, over a hairline under the whole strip; the one shown white and semibold over the accent's 2 pt
/// line, as wide as its words (`.dw.ph .chips`, `.chips > .on`).
///
/// - Each button is 40 tall at least, growing with the text; a finger's target round it is 44 (DWTarget), and the row
///   is padded by the target's reach above and below - and the strip drawn as tall as its words again - so the scroll
///   view, which takes no touch outside itself, holds the whole target. The hairline is the row's foot, under the
///   words, the shown one's line over it.
/// - (R1c's review) Sideways, a button's target is its words and half the gap either side - the buttons touch, 22
///   between their words as .chips' gap, and the row's sides are the strip's 16 less that half - and 44 wide at least
///   (DWLook's target: Queue's EQ is 21 wide in words, 43 with its room). The shown one's line stays as wide as its
///   words, under them, not under the room.
/// - It starts at the leading edge (.chips) and never wraps: where its buttons don't fit the width, the strip scrolls
///   sideways, and the shown button is brought into view whenever it changes - by a tap or by the page's own swipe -
///   moving as the Library's swipe does (`.snappy`, none with Reduce Motion).
/// - VoiceOver hears a tab bar: each button a tab, the one shown selected. (R6 - notes/ios.md "The redesign, slice R6:
///   an artist") A button that opens something of its own (an artist's Artist images… and Move albums…, `pushes`)
///   follows the tabs in the same row, drawn as they are and never lit: a button to VoiceOver, outside the tab bar.
/// - Capped at xxxLarge, as the tab bar is.
struct PhoneStrip<Part: Hashable>: View {
    let options: [Part]
    let words: (Part) -> String
    @Binding var shown: Part
    /// What VoiceOver calls the strip.
    let spoken: String
    /// (R6) The buttons after the tabs that open something of their own: a tap sets `shown` to one - the page's
    /// binding opens it and keeps the tab shown - and it is drawn as the others, never lit.
    var pushes: [Part] = []
    /// (R6's review) What VoiceOver and the pointer's help say of a part, where its words are short of it (an artist's
    /// Move albums…, "Move albums to Ye…"). nil: its words, as every strip before.
    var said: ((Part) -> String)? = nil

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
        // drawn as tall as its words: the targets' reach (the row's padding) laid over what is above and below it
        .padding(.vertical, -reach)
        // .dw.ph .chips: box-shadow inset 0 -1px 0 #1c1b22 - the hairline at the words' foot, under the shown one's line
        .background(alignment: .bottom) { DWRule(colour: DWPalette.stripRule) }
        // .dw.ph .chips: margin-bottom 10px, under the hairline
        .padding(.bottom, CGFloat(PhoneLook.stripFoot))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var row: some View {
        // the gap is the buttons' own room (`room`), so the buttons touch and a finger's target reaches the next one's
        HStack(spacing: 0) {
            // the tabs, a tab bar to VoiceOver - (R6) and the pushes after them, buttons
            if !options.isEmpty {
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { (option: Part) in
                        button(option)
                            .id(option)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isTabBar)
                .accessibilityLabel(spoken)
            }
            ForEach(pushes, id: \.self) { (push: Part) in
                button(push)
                    .id(push)
            }
        }
        // .chips padding 0 16px, less the first button's room before its words and the last's after
        .padding(.horizontal, CGFloat(PhoneLook.stripSide) - room)
        // room for each button's whole target inside the scroll view
        .padding(.vertical, reach)
    }

    /// A button's room either side of its words: half the gap between two buttons' words, 11.
    private var room: CGFloat {
        CGFloat(PhoneLook.stripGap) / 2
    }

    /// How far a button's target reaches above and below its 40 pt height: 2 on the phone.
    private var reach: CGFloat {
        CGFloat(DWLook.here.reach(PhoneLook.strip))
    }

    private func button(_ option: Part) -> some View {
        // (R6) a push is never lit
        let on = option == shown && !pushes.contains(option)
        return Button {
            shown = option
        } label: {
            Text(words(option))
                // .chips > button: 500 in the second colour; .chips > .on 600, white
                .font(Typeface.Phone.text(.strip).weight(on ? .semibold : .medium))
                .foregroundStyle(on ? DWPalette.text : DWPalette.t2)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, CGFloat(PhoneLook.stripPadding))
                .lookHeight(PhoneLook.strip)
                .overlay(alignment: .bottom) {
                    // .chips > .on: box-shadow inset 0 -2px 0 var(--acc) - as wide as its words, at their foot
                    if on {
                        Rectangle()
                            .fill(DWPalette.acc)
                            .frame(height: CGFloat(DWFlat.chosenLine))
                            .accessibilityHidden(true)
                    }
                }
                // (R1c's review) a finger's target sideways: the words' room either side, 44 wide at least
                .padding(.horizontal, room)
                .frame(minWidth: CGFloat(DWLook.here.target))
                .contentShape(DWTarget(face: DWCorners.buttonShape))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .modifier(StripPartSaid(words: said?(option)))
    }
}

/// (R6's review) A strip part's words in full, where the page gives them: its help and VoiceOver's label.
private struct StripPartSaid: ViewModifier {
    let words: String?

    @ViewBuilder func body(content: Content) -> some View {
        if let words {
            content
                .help(words)
                .accessibilityLabel(words)
        } else {
            content
        }
    }
}
