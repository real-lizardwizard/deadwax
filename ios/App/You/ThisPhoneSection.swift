import DeadwaxCore
import SwiftUI

/// Settings > This phone (16 Nov, a page of its own - You's This phone section before), its row on the root showing the
/// server's name or IP (ServerAddress.host). Debug is offered by what /me last said (YouLines.debug). (R9) Flat, a
/// Settings page (SettingsPage).
struct ThisPhonePage: View {
    @Environment(ServerModel.self) private var server

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        SettingsPage {
            ThisPhoneSection(debug: lines.debug)
        }
        .navigationTitle(YouWords.thisDevice(Platform.device))
    }
}

/// This phone (screens.md 8, the phone's own): the deadwax this phone finds at its address, Change address (the Server
/// address screen, pushed - another server signs out of this one, whose Keychain session stays keyed to it), and, for
/// an admin, Debug (D1: Phase 0's test screen). The app's own version is About's App row. (16 Nov) No header: the
/// page's title says This phone. (R9) One flat group: the address a fact in the readout face (selectable), the two
/// `.go` rows under it.
struct ThisPhoneSection: View {
    /// Debug is offered (YouLines.debug: an admin).
    let debug: Bool

    @Environment(ServerModel.self) private var server

    var body: some View {
        PhoneGroup {
            PhoneKV(label: YouWords.server, value: server.address?.description ?? "", mono: true)
                .textSelection(.enabled)
            NavigationLink(value: AppRoute.serverAddress) {
                SettingsGo { Text(YouWords.changeAddress) }
            }
            .buttonStyle(.plain)
            if debug {
                NavigationLink(value: AppRoute.debug) {
                    SettingsGo { Text(YouWords.debug) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
