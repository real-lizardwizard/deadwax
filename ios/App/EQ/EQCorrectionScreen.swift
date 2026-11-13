import DeadwaxCore
import SwiftUI

/// The correction picker (eq.md 3.7), pushed from an EQ page's Correction row (or its suggestion, when that is a
/// choice) and bound to that page's output (3.2): what's chosen here goes to the output it was opened for, and a line
/// at its top says so when that output isn't connected.
///
/// - **First**: None (checked when there's no correction) and the correction there is (checked). None takes it away at
///   once, crossfaded, and goes back; the correction's own row goes back keeping it.
/// - **Suggested for James's AirPods Pro**: the suggestion's one row, or its several - the field then opening with the
///   cleaned name, already searched (EQModel kept the answer).
/// - **AutoEq**: deadwax's search of AutoEq's list, asked 0.3 s after typing stops (`.task(id:)` - a newer ask cancels
///   the last, and a cancelled one never draws: only the newest answer does). A row the Suggested section shows isn't
///   shown again. Each row is the headphone's name, its best source and form, and how many more measurements there
///   are; a tap pushes its profile's page.
/// - Empty, searching, no match, and a failure in a listener's words with Try again (3.17).
struct EQCorrectionScreen: View {
    let key: String

    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(\.dismiss) private var dismiss

    /// What's in the field.
    @State private var text = ""
    /// The newest answer, and the query it answered.
    @State private var found: Found?
    /// The newest ask's failure, and its query.
    @State private var failed: Failed?
    @State private var searching = false
    /// Try again's count: a new ask for the same words.
    @State private var attempt = 0
    @State private var started = false

    private struct Found {
        let query: String
        let answer: AutoEqResults
    }

    private struct Failed {
        let query: String
        let error: any Error
    }

    /// One ask: the words and Try again's count.
    private struct Ask: Equatable {
        let text: String
        let attempt: Int
    }

    var body: some View {
        let output = eq.output(key)
        let setting = eq.setting(output)
        let gone = EQScreenRules.goneLine(.pushed(key, route: eq.route.key), name: output.name)
        let suggestion = eq.suggestion(key)
        // as the EQ page's row: gone with a correction, after Not now, and offline
        let suggested = EQSuggestionRules.shows(output, setting, suggestion, online: reachability.online)
            ? (suggestion?.rows ?? []) : []
        let shownAbove = Set(suggested.map(\.id))
        List {
            Section {
                choiceRow(EQWords.Picker.none, note: nil, chosen: setting.correction == nil) { () -> Void in
                    eq.use(nil, for: output)
                    dismiss()
                }
                if let correction = setting.correction {
                    choiceRow(EQWords.Correction.value(correction), note: EQWords.Correction.source(correction),
                              chosen: true) {
                        dismiss()
                    }
                }
            } header: {
                if let gone {
                    Text(gone)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .textCase(nil)
                }
            }
            if !suggested.isEmpty {
                Section {
                    ForEach(suggested) { row in
                        resultRow(row)
                    }
                } header: {
                    Text(EQWords.Picker.suggested(output.name))
                }
            }
            results(excluding: shownAbove)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(EQWords.Picker.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: EQWords.Picker.prompt)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .eqDoneButton()
        .onAppear(perform: start)
        .task(id: Ask(text: text, attempt: attempt)) {
            await search()
        }
    }

    // MARK: the results

    /// The AutoEq section in its state: nothing asked (the empty words), searching, a failure, no match, or the rows.
    @ViewBuilder
    private func results(excluding shownAbove: Set<String>) -> some View {
        if AutoEqAsk.query(text) == nil {
            Section {
            } footer: {
                Text(EQWords.Picker.empty)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            }
        } else if searching {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(EQWords.Picker.searching)
                        .foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text(EQWords.Picker.header)
            }
        } else if let failed {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    // a 404 to the search is a deadwax from before its AutoEq routes
                    ErrorNote(failed.error, gone: EQWords.Picker.tooOld, retry: true)
                    if ErrorWords.kind(of: failed.error) != .notFound {
                        Button(EQWords.Picker.tryAgain) { attempt += 1 }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(EQWords.Picker.header)
            }
        } else if let found {
            let rows = found.answer.results.filter { !shownAbove.contains($0.id) }
            if found.answer.results.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(EQWords.Picker.noMatch(found.query))
                        Text(EQWords.Picker.tryTheModel)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text(EQWords.Picker.header)
                }
            } else if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        resultRow(row)
                    }
                } header: {
                    Text(EQWords.Picker.header)
                }
            }
        }
    }

    /// A result: its name, and "crinacle · in-ear · 3 more measurements" - one element, the line its hint; a tap
    /// pushes its profile.
    private func resultRow(_ row: AutoEqResult) -> some View {
        let line = EQWords.Picker.row(source: row.source, form: row.form, more: row.others.count)
        return EQLink(route: .profile(AutoEqPage(output: key, row: row))) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityHint(line)
        }
    }

    /// None, or the correction there is - as the presets' rows: one element, `.isSelected` on the chosen one.
    private func choiceRow(_ name: String, note: String?, chosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .foregroundStyle(.primary)
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .opacity(chosen ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityHint(note ?? "")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: asking

    /// The first time the page shows: a suggestion that was a choice opens it searched - the cleaned name in the field,
    /// deadwax's answer to it already there, nothing asked again.
    private func start() {
        guard !started else { return }
        started = true
        let output = eq.output(key)
        guard EQSuggestionRules.shows(output, eq.setting(output), eq.suggestion(key), online: reachability.online) else {
            return
        }
        if let searched = eq.searched(key) {
            found = Found(query: searched.query, answer: searched.answer)
            text = searched.query
        }
    }

    /// The field's words asked of deadwax, 0.3 s after the last key - unless they are the answer there already (the
    /// suggestion's, or one come back to). A newer ask cancels this one, and a cancelled ask draws nothing.
    private func search() async {
        guard let query = AutoEqAsk.query(text) else {
            searching = false
            failed = nil
            return
        }
        if failed == nil, found?.query == query {
            searching = false
            return
        }
        try? await Task.sleep(for: AutoEqAsk.typingPause)
        guard !Task.isCancelled, let client = server.client else { return }
        searching = true
        failed = nil
        do {
            let answer = try await client.autoEq(search: query)
            guard !Task.isCancelled else { return }
            found = Found(query: query, answer: answer)
            searching = false
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            failed = Failed(query: query, error: error)
            searching = false
        }
    }
}
