import DeadwaxCore
import SwiftUI

/// The Server address screen (screens.md 2): deadwax's address, and Check - GET /deadwax/health, then (ServerModel)
/// the launch goes on from /me. From This phone > Change address it's pushed, and pops once the address checks out
/// (another server starts the app again). (The redesign, slice R9) At launch the first gate is the sign-in's one screen
/// now (SignInView: Where deadwax is, then Who you are - this screen's Check, in its order), so this is This phone's
/// alone; drawn flat (SettingsPage), its field still a box (FieldLook).
///
/// Phase 0's field and words, kept verbatim: this is the one screen that speaks to whoever set the phone up, so
/// what Check found is said in Phase 0's words (CheckReport.lines: the address, the reason, Wi-Fi or WireGuard,
/// Local Network), not a listener's. The address is saved only once deadwax answered (ServerModel.checkAddress).
struct ServerAddressView: View {
    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What is typed, handed to ServerModel at Check - so leaving a pushed screen unchecked changes nothing.
    @State private var typed = ""
    /// Check pressed on this screen: only then is what it found shown (a pushed screen never shows an earlier one's).
    @State private var checked = false
    @FocusState private var focused: Bool

    init() {}

    /// Pushed from You, with the app running under it (not the launch's gate).
    private var pushed: Bool { server.launch == .ready }

    var body: some View {
        SettingsPage {
            PhoneGroup(legend: "deadwax's address") {
                VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                    // (R9's review) Check on the address's first text baseline, as the sign-in's; under the field at
                    // the accessibility sizes
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                            addressField
                            checkButton
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: SettingsLook.fieldGap) {
                            addressField
                            checkButton
                        }
                    }
                    if checked, let report = server.addressReport {
                        ForEach(report.lines(Platform.device), id: \.self) { line in
                            Text(line)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, SettingsLook.fieldGap)
            }
            Text(AddressWords.footer(Platform.device))
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SettingsLook.noteAbove)
        }
        .navigationTitle("deadwax")
        .onAppear {
            // pushed: the address in use; the launch's: what ServerModel holds (Change address put the old one there)
            typed = pushed ? (server.address?.description ?? server.addressText) : server.addressText
            if typed.isEmpty { focused = true }
        }
        .onChange(of: server.addressReport) { _, report in
            if checked, let line = report?.lines(Platform.device).first { Notice.announce(line) }
        }
    }

    private var addressField: some View {
        TextField("http://192.168.1.20:8090", text: $typed)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focused)
            .onSubmit { check() }
            .font(Typeface.Phone.mono(.row))
            .modifier(FieldLook(focused: focused))
            .accessibilityLabel("deadwax's address")
    }

    private var checkButton: some View {
        Button(server.checkingAddress ? "Checking\u{2026}" : "Check") { check() }
            .buttonStyle(DWButtonStyle())
            .disabled(server.checkingAddress)
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
