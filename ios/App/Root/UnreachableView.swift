import DeadwaxCore
import SwiftUI

/// Can't reach deadwax (D10): /me failed at launch with no 401. Its sentence (ErrorWords.unreached), Try again, Change
/// address, and - for whoever runs deadwax (Access.seesDetail, from the last /me answered) - what failed in its own
/// words under "For whoever runs deadwax". STUB (the Root part's): working, plain.
struct UnreachableView: View {
    let failure: APIFailure

    @Environment(ServerModel.self) private var server

    init(failure: APIFailure) {
        self.failure = failure
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(ErrorWords.unreached)
                .font(.title3)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await server.check() } }
                .buttonStyle(.borderedProminent)
            Button("Change address") { server.changeAddress() }
            if server.access.seesDetail {
                DisclosureGroup(ErrorWords.forWhoever) {
                    Text(failure.words)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
    }
}
