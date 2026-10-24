import SwiftUI

/// deadwax for iPhone, Phase 0 ("Hello, iPhone"): one screen that proves the toolchain, the
/// connection and the audio engine on the phone - see docs/ios.md and notes/ios.md.
@main
struct DeadwaxApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
    }
}

/// The app's few colours, in code: there is no asset catalog (James's Mac has no Simulator
/// runtime, and actool needs one). The web app's brand purple and its page black.
enum Palette {
    static let accent = Color(red: 0xC0 / 255, green: 0x84 / 255, blue: 0xFC / 255)
    static let quiet = Color.secondary
}
