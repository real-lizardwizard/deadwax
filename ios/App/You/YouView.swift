import DeadwaxCore
import SwiftUI

/// The You tab (D1): who is signed in and Sign out (logins on), This phone's server, the version, and Debug for an
/// admin. STUB (the You part's): working, plain - Normalization and the rest are the parts'.
struct YouView: View {
    @Environment(ServerModel.self) private var server

    init() {}

    var body: some View {
        List {
            if server.access.loginsOn {
                Section {
                    Button(server.signOutRow.label, role: .destructive) { Task { await server.signOut() } }
                        .disabled(server.signOutRow.busy)
                    if let problem = server.signOutRow.problem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(SignOutRow.footnote(user: server.access.user))
                }
            }
            Section("This phone") {
                NavigationLink(value: AppRoute.serverAddress) {
                    LabeledContent("Server", value: server.address?.description ?? "")
                }
                if server.access.isAdmin {
                    NavigationLink("Debug", value: AppRoute.debug)
                }
            }
            Section {
                LabeledContent("Version", value: server.me?.version ?? (server.askingMe ? "…" : ""))
                LabeledContent("App", value: Self.appVersion)
                if let failure = server.meFailure {
                    ErrorNote(failure)
                }
            }
        }
        .navigationTitle("You")
        .onChange(of: server.signOutRow.problem) { _, problem in
            if let problem { Notice.announce(problem) }
        }
    }

    /// "deadwax for iPhone 0.2 (2)", from the bundle.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "deadwax for iPhone \(short) (\(build))"
    }
}
