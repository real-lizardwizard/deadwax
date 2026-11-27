import DeadwaxCore
import SwiftUI

/// Can't reach deadwax (D10): /me failed at launch with no 401, so a sign-in form couldn't help. Its sentence, Try
/// again (/me asked again - also as the app comes back to the front), Change address (the Server address screen, the
/// address in its field), and - folded under "For whoever runs deadwax" - what failed in the words of whoever set the
/// phone up. Core's UnreachedLines decides both lines and who sees the second.
///
/// (R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") On both devices: the sentence a
/// heading in the look's words (SheetLook), Try again the look's large purple button and Change address its large
/// flat one (the phone's accent words, the Mac's `.btn`) - PrimaryFace and SecondaryPill gone - each across the column,
/// its words up to three lines at the accessibility sizes; the address in Courier Prime, the detail in the small greys,
/// all on the page's ground (the phone's black, the Mac's window ground).
struct UnreachableView: View {
    let failure: APIFailure

    @Environment(ServerModel.self) private var server
    @ScaledMetric(relativeTo: .largeTitle) private var mark: CGFloat = 44

    init(failure: APIFailure) {
        self.failure = failure
    }

    var body: some View {
        // nothing has answered /me on this launch: nobody is known yet (UnreachedLines folds the detail for anyone)
        let lines = UnreachedLines(failure, access: server.me == nil ? nil : server.access)
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(Typeface.symbol(size: mark))
                    .foregroundStyle(DWPalette.t2)
                    .accessibilityHidden(true)
                Text(lines.text)
                    .font(SheetLook.title)
                    .foregroundStyle(DWPalette.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    Button {
                        Task { await server.check() }
                    } label: {
                        SheetButtonWords(UnreachedLines.tryAgain)
                    }
                    .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
                    Button {
                        server.changeAddress()
                    } label: {
                        SheetButtonWords(UnreachedLines.changeAddress)
                    }
                    .buttonStyle(DWButtonStyle(size: .large, fills: true))
                }
                if let address = server.address {
                    Text(address.description)
                        .font(SheetLook.mono)
                        .foregroundStyle(DWPalette.t2)
                        .textSelection(.enabled)
                }
                if let detail = lines.detail {
                    DisclosureGroup(ErrorWords.forWhoever) {
                        Text(detail)
                            .font(SheetLook.small)
                            .foregroundStyle(DWPalette.t2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .font(SheetLook.small)
                    .foregroundStyle(DWPalette.t2)
                    .tint(DWPalette.acc)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SheetLook.ground)
        .onAppear { Notice.announce(lines.text) }
    }
}
