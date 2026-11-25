import DeadwaxCore
import SwiftUI
import UIKit

/// The fixed bottom action (dw.css's .foot2 - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared
/// look, and the phone's pieces"): a page's one or two actions at its foot - Edit album's Save, a person's Save
/// permissions - 68 tall at least, 10 apart and 16 in, its ground run on down into the home indicator's room. Capped at
/// xxxLarge, as the tab bar is. Drawn nowhere until its slices (R9, R10). (R1c - notes/ios.md "The redesign, slice R1c:
/// the phone is flat (2026-11-25)") No fill of its own, a hairline (#1c1b22) over it: its ground is the page's own black,
/// so it reads as the page while what scrolls under it doesn't show through (`.dw.ph .foot2`'s `background: none` draws
/// the drawing's page through it, which has nothing under its foot).
struct PhoneFoot<Actions: View>: View {
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.footGap)) {
            actions
        }
        .padding(.horizontal, CGFloat(PhoneLook.footSide))
        .frame(maxWidth: .infinity)
        .lookHeight(PhoneLook.foot)
        .background {
            DWPalette.footFace
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) { DWRule(colour: DWPalette.footEdge) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

extension View {
    /// A page's fixed bottom action (PhoneFoot) laid over its foot, above the home indicator - and under the keyboard,
    /// never riding up on it (Edit album's typed work stays where the keyboard leaves it) - with the page's content
    /// given its room above it, none while the keyboard is up over it.
    func phoneFoot<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> some View {
        modifier(PhoneFootPlacing(foot: PhoneFoot(actions: actions)))
    }
}

/// The foot laid over the page, and the page given its room.
private struct PhoneFootPlacing<Actions: View>: ViewModifier {
    let foot: PhoneFoot<Actions>

    @State private var height: CGFloat = 0
    @State private var keyboardUp = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: keyboardUp ? 0 : height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                // the foot's own layer, the page's height: it - not the foot inside it - takes the keyboard's room too,
                // so where the page gives the keyboard its room the layer still reaches the foot of the screen and the
                // foot stays there under the keyboard, as the tab bar does, never riding up on it (untried on a phone:
                // notes/ios.md's R1b section)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    foot
                        .onGeometryChange(for: CGFloat.self) { (drawn: GeometryProxy) -> CGFloat in
                            drawn.size.height
                        } action: { (now: CGFloat) -> Void in
                            height = now
                        }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
                (_: Notification) -> Void in
                keyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
                (_: Notification) -> Void in
                keyboardUp = false
            }
    }
}
