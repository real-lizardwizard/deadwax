import SwiftUI

/// The notice capsule (D11): a line said over the mini player - "Playing next: …", "Added to Queue: …" - for
/// `seconds`, then gone (PlayerModel.say keeps the time). Drawn in two places since Phase 2 - over the mini player, and
/// in Now Playing's top row (which covers the tabs) - so VoiceOver hears it from PlayerModel.say, once per notice said,
/// never from the view as it appears (it would be heard twice, and a view under a full-screen cover may not "appear").
/// Since the squared look a card's corners (Corners.card), no longer a capsule's ends.
struct Notice: View {
    /// How long a notice stands (PIN_NOTICE_MS, 5 s).
    static let seconds: Double = 5

    let text: String

    var body: some View {
        Text(text)
            .font(Typeface.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Corners.cardShape)
            .accessibilityAddTraits(.isStaticText)
    }

    static func announce(_ words: String) {
        AccessibilityNotification.Announcement(words).post()
    }
}
