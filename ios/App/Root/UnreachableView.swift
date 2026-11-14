import DeadwaxCore
import SwiftUI

/// Can't reach deadwax (D10): /me failed at launch with no 401, so a sign-in form couldn't help. Its sentence, Try
/// again (/me asked again - also as the app comes back to the front), Change address (the Server address screen, the
/// address in its field), and - folded under "For whoever runs deadwax" - what failed in the words of whoever set the
/// phone up. Core's UnreachedLines decides both lines and who sees the second.
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
                    .font(.system(size: mark))
                    .foregroundStyle(Palette.quiet)
                    .accessibilityHidden(true)
                Text(lines.text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    Button {
                        Task { await server.check() }
                    } label: {
                        Text(UnreachedLines.tryAgain).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFace(large: true))
                    Button {
                        server.changeAddress()
                    } label: {
                        Text(UnreachedLines.changeAddress).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryPill(large: true))
                }
                if let address = server.address {
                    Text(address.description)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                }
                if let detail = lines.detail {
                    DisclosureGroup(ErrorWords.forWhoever) {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .font(.footnote)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { Notice.announce(lines.text) }
    }
}
