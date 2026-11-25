import DeadwaxCore
import SwiftUI

/// Folder tabs (dw.css's .tabs and .tab - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1: the frame
/// and the shared pieces"): the side panel's Queue | Lyrics | Info and Edit an album's Release | Tags | Artwork | Lyrics |
/// Delete. A strip 35 tall with the line along its foot; each tab 26 tall with a box's corners at its top, the one chosen
/// 29 tall in the ground below it (`ground`: the panel's, or the page's - .tabs.onbg) with the accent along its top, its
/// foot over the strip's line so it opens into what is under it.
///
/// Each tab is a button VoiceOver reads as selected when chosen (`.isSelected`).
struct MacFolderTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    let words: (Tab) -> String
    @Binding var chosen: Tab
    /// What VoiceOver calls the strip.
    let spoken: String
    /// The chosen tab's ground: the panel's, else the page's (.tabs.onbg .tab.on).
    var ground: Color = MacPalette.panel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(tabs, id: \.self) { (tab: Tab) in
                    folder(tab)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: CGFloat(MacLook.tabStripHeight) - 1, alignment: .bottom)
            // the chosen tab's foot lies over the line under the strip
            .zIndex(1)
            MacRule(colour: MacPalette.line)
        }
        .background(MacPalette.tabStripFace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
    }

    private func folder(_ tab: Tab) -> some View {
        let on = tab == chosen
        return Button {
            chosen = tab
        } label: {
            Text(words(tab))
                .font(Typeface.Mac.text(.control).weight(on ? .semibold : .regular))
                .foregroundStyle(on ? MacPalette.chosenTabText : MacPalette.t2)
                .lineLimit(1)
                // .tab: padding 0 13px
                .padding(.horizontal, 13)
                .frame(height: CGFloat(on ? MacLook.chosenTabHeight : MacLook.tabHeight))
                .background {
                    if on {
                        MacCorners.tabShape.fill(ground)
                    } else {
                        MacCorners.tabShape.fill(MacPalette.tabFace)
                    }
                }
                // .tab.on: box-shadow inset 0 2px 0 var(--acc) - 2 pt of the accent inside its top edge
                .overlay(alignment: .top) {
                    if on {
                        MacPalette.acc
                            .frame(height: 2)
                            .padding(.top, 1)
                            .clipShape(MacCorners.tabShape)
                    }
                }
                // its edge on three sides: no edge along its foot (border-bottom: 0)
                .overlay {
                    MacCorners.tabShape
                        .strokeBorder(on ? MacPalette.chosenTabEdge : MacPalette.line, lineWidth: 1)
                        .padding(.bottom, -1)
                        .clipped()
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // .tab.on: margin-bottom -1px
        .offset(y: on ? 1 : 0)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
