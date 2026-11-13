import DeadwaxCore
import SwiftUI

/// One AutoEq profile's page (eq.md 3.7), pushed from the picker, the suggestion or another measurement's page, and
/// bound to the output it was opened for (3.2): "Use for James's AirPods Pro" does what it says, whatever connects
/// while you read - and a line at its top says when that output isn't connected.
///
/// - **The curve of the correction alone** (Core's `EQDrawing.profile`: at 48 kHz, its own automatic preamp, no tone),
///   then who measured it and on what, and "10 filters, preamp -6.0 dB" - the file's own preamp.
/// - **Use for …**: a full-width prominent button. Using copies the profile's text and filters into the output's
///   setting as its correction (crossfaded), turns the EQ on if it was Off ("EQ on"), and goes back to the EQ page.
///   Once used: "Used for …", disabled, with a checkmark.
/// - **Other measurements** of the same headphone, each its own page; the footer's credit and "AutoEq on GitHub".
/// - Loading, a failure in a listener's words with Try again - a 404's own sentence and no button (3.17) - and a file
///   the reader refuses: "deadwax couldn't read this correction.", the reader's words under it for an admin.
struct EQProfileScreen: View {
    let page: AutoEqPage

    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.eqBackToPage) private var backToPage

    @State private var loaded: Loaded?
    @State private var failed: (any Error)?
    /// Try again's count: the profile asked for afresh.
    @State private var attempt = 0

    /// The profile as deadwax sent it, and as the reader read it.
    private struct Loaded {
        let profile: AutoEqProfile
        let reading: Result<EQCorrection, APORefusal>
    }

    var body: some View {
        let output = eq.output(page.output)
        let setting = eq.setting(output)
        let gone = EQScreenRules.goneLine(.pushed(page.output, route: eq.route.key), name: output.name)
        List {
            Section {
                content(output)
            } header: {
                if let gone {
                    Text(gone)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .textCase(nil)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(EQWords.Profile.measured(source: page.shown.source, rig: page.shown.rig, form: page.shown.form))
                    if let loaded, case .success(let correction) = loaded.reading {
                        Text(EQWords.Profile.summary(filters: correction.filters.count, preamp: correction.preamp.all))
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
            }
            if let loaded, case .success(let correction) = loaded.reading {
                Section {
                    useButton(correction, output: output, used: setting.uses(loaded.profile.id))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !page.others.isEmpty {
                Section {
                    ForEach(page.others, id: \.id) { other in
                        EQLink(route: .profile(page.showing(other))) {
                            Text(EQWords.Profile.other(source: other.source, form: other.form))
                        }
                    }
                } header: {
                    Text(EQWords.Profile.others)
                }
            }
            Section {
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(EQWords.Profile.footer)
                    if let address = URL(string: EQWords.Profile.gitHubAddress) {
                        Link(EQWords.Profile.gitHub, destination: address)
                            .font(.footnote)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(page.name)
        .navigationBarTitleDisplayMode(.inline)
        .eqDoneButton()
        .task(id: attempt) {
            await load()
        }
    }

    /// The first section's row: the curve, the reader's refusal, a failure, or loading.
    @ViewBuilder
    private func content(_ output: EQOutput) -> some View {
        if let loaded {
            switch loaded.reading {
            case .success(let correction):
                EQCurveView(drawing: EQDrawing.profile(correction, for: output, in: eq.settings), name: page.name,
                            animated: false)
                    .listRowInsets(EdgeInsets())
            case .failure(let refusal):
                VStack(alignment: .leading, spacing: 6) {
                    Text(EQWords.Profile.notRead)
                        .foregroundStyle(Palette.danger)
                    if server.access.seesDetail {
                        Text(refusal.text)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Palette.quiet)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
        } else if let failed {
            VStack(alignment: .leading, spacing: 10) {
                ErrorNote(failed, gone: EQWords.Profile.gone, retry: true)
                // a measurement AutoEq no longer has won't come back by asking again
                if ErrorWords.kind(of: failed) != .notFound {
                    Button(EQWords.Picker.tryAgain) { attempt += 1 }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        } else {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(height: EQCurveView.height)
        }
    }

    /// "Use for James's AirPods Pro" - or, once used, "Used for …", disabled, with a checkmark.
    private func useButton(_ correction: EQCorrection, output: EQOutput, used: Bool) -> some View {
        Button {
            use(correction, for: output)
        } label: {
            Group {
                if used {
                    Label(EQWords.Profile.used(output.name), systemImage: "checkmark")
                } else {
                    Text(EQWords.Profile.use(output.name))
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(used)
    }

    // MARK: acting

    /// The profile made this output's correction - the EQ on with it - and back to the EQ page, on whichever stack.
    private func use(_ correction: EQCorrection, for output: EQOutput) {
        eq.use(correction, for: output)
        if let backToPage {
            backToPage()
        } else {
            navigation.backToEQPage()
        }
    }

    /// The profile asked for, and read as an import would read it (Core's `AutoEqProfile.correction()`).
    private func load() async {
        guard loaded == nil, let client = server.client else { return }
        failed = nil
        do {
            let profile = try await client.autoEqProfile(id: page.shown.id)
            guard !Task.isCancelled else { return }
            loaded = Loaded(profile: profile, reading: profile.correction())
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            failed = error
        }
    }
}
