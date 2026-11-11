import DeadwaxCore
import SwiftUI

/// The Server address screen (screens.md 2): deadwax's address, and Check - GET /deadwax/health, then (ServerModel)
/// the launch goes on from /me. At launch it's the first gate, in its own NavigationStack; from You's This phone >
/// Change address it's pushed, and pops once the address checks out (another server starts the app again).
///
/// Phase 0's field and words, kept verbatim: this is the one screen that speaks to whoever set the phone up, so
/// what Check found is said in Phase 0's words (CheckReport.lines: the address, the reason, Wi-Fi or WireGuard,
/// Local Network), not a listener's. The address is saved only once deadwax answered (ServerModel.checkAddress).
struct ServerAddressView: View {
    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss

    /// What is typed, handed to ServerModel at Check - so leaving a pushed screen unchecked changes nothing.
    @State private var typed = ""
    /// Check pressed on this screen: only then is what it found shown (a pushed screen never shows an earlier one's).
    @State private var checked = false
    @FocusState private var focused: Bool

    init() {}

    /// Pushed from You, with the app running under it (not the launch's gate).
    private var pushed: Bool { server.launch == .ready }

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.20:8090", text: $typed)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { check() }
                    .accessibilityLabel("deadwax's address")
                Button(server.checkingAddress ? "Checking\u{2026}" : "Check") { check() }
                    .disabled(server.checkingAddress)
                if checked, let report = server.addressReport {
                    ForEach(report.lines, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("deadwax's address")
            } footer: {
                Text("The address you open deadwax at, by IP or by name. The first time, iOS asks to let deadwax find devices on your local network: say yes.")
            }
        }
        .navigationTitle("deadwax")
        .onAppear {
            // pushed: the address in use; the launch's: what ServerModel holds (Change address put the old one there)
            typed = pushed ? (server.address?.description ?? server.addressText) : server.addressText
            if typed.isEmpty { focused = true }
        }
        .onChange(of: server.addressReport) { _, report in
            if checked, let line = report?.lines.first { Notice.announce(line) }
        }
    }

    private func check() {
        guard !server.checkingAddress else { return }
        checked = true
        focused = false
        server.addressText = typed
        let wasPushed = pushed
        Task {
            let good = await server.checkAddress()
            typed = server.addressText
            if good, wasPushed { dismiss() }
        }
    }
}
