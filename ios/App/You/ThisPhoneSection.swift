import DeadwaxCore
import SwiftUI

/// You > This phone (screens.md 8, the phone's own): the deadwax this phone finds at its address, Change address
/// (the Server address screen, pushed - another server signs out of this one, whose Keychain session stays keyed to
/// it), and, for an admin, Debug (D1: Phase 0's test screen). The app's own version is About's App row.
struct ThisPhoneSection: View {
    /// Debug is offered (YouLines.debug: an admin).
    let debug: Bool

    @Environment(ServerModel.self) private var server

    var body: some View {
        Section {
            LabeledContent(YouWords.server) {
                Text(server.address?.description ?? "")
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            NavigationLink(value: AppRoute.serverAddress) {
                Text(YouWords.changeAddress)
            }
            if debug {
                NavigationLink(value: AppRoute.debug) {
                    Text(YouWords.debug)
                }
            }
        } header: {
            Text(YouWords.thisPhone)
        }
    }
}
