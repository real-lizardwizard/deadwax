import DeadwaxCore
import SwiftUI

/// The presets (eq.md 3.6), pushed from an EQ page's Preset row and bound to that page's output (3.2): whatever connects
/// while it is open, a choice here goes to the output it was opened for - heard if that is the one playing, kept if
/// not, and then a line at its top says so. Apple's own pattern (Settings > Music > EQ): a pushed list, a checkmark on
/// the chosen one, the page staying as you tap, so you can listen through several; Back returns.
///
/// - **Custom** comes first while the tone is Custom - and stays for the page's life once it has been, so tapping it
///   puts back where you left the sliders after trying a few presets.
/// - **The nine built-ins**, in 3.6's order, each with its note.
/// - **Your presets**, when you have any: their names, no note; swipe for Rename and Delete (VoiceOver has both as
///   actions). Deleting the one an output uses leaves its sliders where they were, as Custom.
///
/// Rows as Normalization's (PlaybackSection): one element each, the name its label, the note its hint, `.isSelected`
/// on the chosen one.
struct EQPresetsScreen: View {
    let key: String

    @Environment(EQModel.self) private var eq
    /// Custom's gains, from the first time the tone was Custom while the page was open.
    @State private var custom: [Double]?
    @State private var ask: EQNameAsk?

    var body: some View {
        let output = eq.output(key)
        let tone = eq.setting(output).tone
        let gone = EQScreenRules.goneLine(.pushed(key, route: eq.route.key), name: output.name)
        List {
            Section {
                if let custom {
                    row(EQWords.Presets.custom, note: EQWords.Presets.customNote, chosen: Self.isCustom(tone)) {
                        eq.choose(.custom(custom), for: output)
                    }
                }
                ForEach(EQGraphic.presets, id: \.id) { preset in
                    row(preset.name, note: preset.note, chosen: tone == .preset(preset.id)) {
                        eq.choose(.preset(preset.id), for: output)
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
            if !eq.settings.presets.isEmpty {
                Section {
                    ForEach(eq.settings.presets, id: \.id) { preset in
                        row(preset.name, note: nil, chosen: tone == .yours(preset.id)) {
                            eq.choose(.yours(preset.id), for: output)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(EQWords.Presets.delete, role: .destructive) { eq.deletePreset(preset.id) }
                            Button(EQWords.Presets.rename) { askRename(preset) }
                        }
                    }
                } header: {
                    Text(EQWords.Presets.yours)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(EQWords.Presets.title)
        .eqDoneButton()
        .eqNameAlert($ask)
        .onChange(of: tone, initial: true) { _, now in
            if case .custom(let gains) = now { custom = gains }
        }
    }

    private func row(_ name: String, note: String?, chosen: Bool, choose: @escaping () -> Void) -> some View {
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

    private func askRename(_ preset: EQYourPreset) {
        let model = eq
        let id = preset.id
        ask = EQNameAsk(title: EQWords.Presets.renameTitle, placeholder: EQWords.Presets.name, text: preset.name,
                        save: EQWords.Presets.save, cancel: EQWords.Presets.cancel,
                        done: { (name: String) -> String? in
                            model.renamePreset(id, to: name).map(EQWords.Presets.problem)
                        })
    }

    private static func isCustom(_ tone: EQTone) -> Bool {
        if case .custom = tone { return true }
        return false
    }
}
