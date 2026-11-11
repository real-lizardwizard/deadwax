import SwiftUI

/// The notice capsule (D11): a line said over the mini player - "Playing next: …", "Added to Up Next: …" - for
/// `seconds`, then gone (PlayerModel.say keeps the time). VoiceOver reads it as it appears or changes.
struct Notice: View {
    /// How long a notice stands (PIN_NOTICE_MS, 5 s).
    static let seconds: Double = 5

    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .accessibilityAddTraits(.isStaticText)
            .onAppear { Self.announce(text) }
            .onChange(of: text) { _, now in Self.announce(now) }
    }

    static func announce(_ words: String) {
        AccessibilityNotification.Announcement(words).post()
    }
}
