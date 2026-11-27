import SwiftUI

/// The notice capsule (D11): a line said over the mini player - "Playing next: …", "Added to Queue: …" - for
/// `seconds`, then gone (PlayerModel.say keeps the time). Drawn in two places since Phase 2 - over the mini player, and
/// in Now Playing's top row (which covers the tabs) - so VoiceOver hears it from PlayerModel.say, once per notice said,
/// never from the view as it appears (it would be heard twice, and a view under a full-screen cover may not "appear").
/// Since the squared look a card's corners (Corners.card), no longer a capsule's ends.
///
/// (R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") No material: a DWPalette ground
/// with a hairline - the phone's page black inside the line's edge, square (flat, as the page it sits on), the Mac's
/// raised ground (--card) in a box's corners (`.box`). Its words the phone's 15 at the subheadline's scale - the very
/// size Now Playing measures its longest word at (NowPlayingView's NoticeWord, Typeface.subheadline) - and the Mac's 13.
/// It takes no touch: a tap where it lies goes to what is under it, so it never stands over another control's target
/// (and where it is placed - 8 above the mini player and the tab bar, MainTabs' NoticeInset; inside Now Playing's top
/// between Close and the look button - it covers no fixed control either: tests/test_ios_sheets_look.py works it out).
struct Notice: View {
    /// How long a notice stands (PIN_NOTICE_MS, 5 s).
    static let seconds: Double = 5

    let text: String

    var body: some View {
        Text(text)
            .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.strip))
            .foregroundStyle(DWPalette.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Platform.mac ? DWPalette.card : DWPalette.page, in: DWCorners.boxShape)
            .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
    }

    static func announce(_ words: String) {
        AccessibilityNotification.Announcement(words).post()
    }
}
