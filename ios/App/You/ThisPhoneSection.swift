import DeadwaxCore
import SwiftUI

/// Settings > This phone (16 Nov, a page of its own - You's This phone section before), its row on the root showing the
/// server's name or IP (ServerAddress.host). Debug is offered by what /me last said (YouLines.debug).
struct ThisPhonePage: View {
    @Environment(ServerModel.self) private var server

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        List {
            ThisPhoneSection(debug: lines.debug)
        }
        .navigationTitle(YouWords.thisPhone)
    }
}

/// This phone (screens.md 8, the phone's own): the deadwax this phone finds at its address, Change address (the Server
/// address screen, pushed - another server signs out of this one, whose Keychain session stays keyed to it), and, for
/// an admin, Debug (D1: Phase 0's test screen). The app's own version is About's App row. (16 Nov) No header: the
/// page's title says This phone.
struct ThisPhoneSection: View {
    /// Debug is offered (YouLines.debug: an admin).
    let debug: Bool

    @Environment(ServerModel.self) private var server

    var body: some View {
        Section {
            LabeledContent(YouWords.server) {
                Text(server.address?.description ?? "")
                    .font(Typeface.mono(.body))
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
        }
    }
}
