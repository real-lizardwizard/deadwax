import DeadwaxCore
import SwiftUI

/// The Server address screen (screens.md 1, step 1): deadwax's address, and Check. At launch it's the first gate;
/// from You's This phone > Server it's pushed, and pops once the address is in use. STUB (the Root part's): Phase 0's
/// field and words, working.
struct ServerAddressView: View {
    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        @Bindable var server = server
        Form {
            Section {
                TextField("http://192.168.1.20:8090", text: $server.addressText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { check() }
                    .accessibilityLabel("deadwax's address")
                Button(server.checkingAddress ? "Checking…" : "Check") { check() }
                    .disabled(server.checkingAddress)
                ForEach(server.addressReport?.lines ?? [], id: \.self) { line in
                    Text(line).font(.footnote)
                }
            } header: {
                Text("deadwax's address")
            } footer: {
                Text("The address you open deadwax at, by IP or by name. The first time, iOS asks to let deadwax find devices on your local network: say yes.")
            }
        }
        .navigationTitle("deadwax")
    }

    private func check() {
        Task {
            let pushed = server.launch == .ready
            if await server.checkAddress(), pushed { dismiss() }
        }
    }
}
