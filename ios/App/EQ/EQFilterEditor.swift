import DeadwaxCore
import SwiftUI

/// One correction filter's editor (eq.md 3.8): a Form titled "Filter 3" - its place in the list, low to high - bound
/// to the output and the filter it was opened for (3.2), its rules Core's EQEditorRules.
///
/// - **The filter's own curve** at the top, 120 pt, its handle draggable and pinchable as on the EQ page.
/// - **Type** (a menu of the eight): changing it keeps the frequency, and the gain and width where the new type has
///   them (EQEditorRules.changingKind).
/// - **Frequency**: a field, "Hz", and under it a slider on a log scale, 20 Hz to 20 kHz; a shelf read by its corner
///   says where it is centred. **Gain** (peaks and shelves): a field, "dB", a stepper of 0.1 dB. **Q** - or **Width**
///   in octaves, or **Slope** in dB an octave, as the filter is written - a field (its type's default as the
///   placeholder when it has none) and a stepper, with "Use Q instead" for the two that aren't a Q.
/// - **Ear** (only when the correction has per-ear filters), **On**, and **Delete Filter** at the foot.
/// - **The fields** use the phone's decimal mark and `.numbersAndPunctuation` (`.decimalPad` has no minus). What is
///   typed is applied when it is submitted or the field is left; out of range it stays, in danger's colour, its line
///   under it, and nothing changes until it is in range. Nothing typed, nothing applied - a filter is changed only
///   when you change it.
/// - A finger on the curve, the slider or a stepper holds the file's save until it is up, as the sliders do. The
///   filter gone (deleted here, or the correction replaced): the page goes back, once.
struct EQFilterEditor: View {
    let page: EQFilterPage

    @Environment(EQModel.self) private var eq
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// What was typed in each field, not yet applied.
    @State private var editing: [EQField: String] = [:]
    /// The fields whose text was refused when applied: their line shows until the text is in range.
    @State private var refused: Set<EQField> = []
    @FocusState private var focus: EQField?
    /// Fingers down on the page's controls.
    @State private var holding = 0
    /// Gone back already.
    @State private var left = false

    private var decimal: String { Locale.current.decimalSeparator ?? "." }

    var body: some View {
        let output = eq.output(page.output)
        let correction = eq.setting(output).correction
        let filter = correction?.filters.first { (f: EQFilter) -> Bool in f.id == page.id }
        let gone = EQScreenRules.goneLine(.pushed(page.output, route: eq.route.key), name: output.name)
        Form {
            if let filter {
                curveSection(filter, output: output, gone: gone)
                typeSection(filter, output: output)
                widthSection(filter, output: output)
                if EQAdvancedRules.showsEar(correction) {
                    Section {
                        Picker(EQWords.Editor.ear, selection: Binding<EQChannel>(get: { filter.channel },
                                                                                set: { (now: EQChannel) -> Void in
                            var g = filter
                            g.channel = now
                            edit(g, output)
                        })) {
                            Text(EQWords.Editor.both).tag(EQChannel.all)
                            Text(EQWords.Editor.left).tag(EQChannel.left)
                            Text(EQWords.Editor.right).tag(EQChannel.right)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text(EQWords.Editor.ear)
                    }
                }
                Section {
                    Toggle(EQWords.Editor.on, isOn: Binding<Bool>(get: { filter.on }, set: { (now: Bool) -> Void in
                        eq.setFilter(page.id, on: now, for: output)
                    }))
                }
                Section {
                    Button(EQWords.Editor.deleteFilter, role: .destructive) {
                        eq.deleteFilter(page.id, for: output)
                        goBack()
                    }
                }
            }
        }
        .navigationTitle(EQWords.Editor.title(EQAdvancedRules.number(of: page.id, in: correction) ?? 0))
        .navigationBarTitleDisplayMode(.inline)
        .eqDoneButton()
        .onChange(of: focus) { (was: EQField?, _: EQField?) -> Void in
            // a field left: what was typed in it applied (or refused)
            if let was { commit(was, output) }
        }
        .onChange(of: filter == nil, initial: true) { (_: Bool, isGone: Bool) -> Void in
            if isGone { goBack() }
        }
        .onDisappear {
            while holding > 0 { hold(false) }
        }
    }

    // MARK: the sections

    /// The filter's own curve, its handle on it - and, its output gone, the line saying so above it.
    private func curveSection(_ f: EQFilter, output: EQOutput, gone: String?) -> some View {
        let handles = EQHandles(handles: f.on ? [EQHandleRules.handle(f)] : [], selected: f.id, capsule: nil,
                                showsCapsule: false,
                                filter: { (id: Int) -> EQFilter? in
                                    eq.setting(output).correction?.filters.first { (g: EQFilter) -> Bool in g.id == id }
                                },
                                select: { (_: Int) -> Void in },
                                change: { (_: Int, g: EQFilter) -> Void in
                                    editedElsewhere()
                                    edit(g, output)
                                },
                                hold: { (down: Bool) -> Void in hold(down) })
        return Section {
            EQCurveView(drawing: EQDrawing.filter(f, rate: eq.rate(page.output)), name: output.name,
                        animated: holding == 0, height: 120, handles: handles)
                .listRowInsets(EdgeInsets())
        } header: {
            if let gone {
                Text(gone)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .textCase(nil)
            }
        }
    }

    /// Type, Frequency (its field, its slider, a corner shelf's line) and Gain.
    private func typeSection(_ f: EQFilter, output: EQOutput) -> some View {
        Section {
            Picker(EQWords.Editor.type, selection: Binding<EQKind>(get: { f.kind }, set: { (now: EQKind) -> Void in
                editedElsewhere()
                edit(EQEditorRules.changingKind(f, to: now), output)
            })) {
                ForEach(EQKind.allCases, id: \.self) { (kind: EQKind) in
                    Text(EQWords.Advanced.type(kind)).tag(kind)
                }
            }
            .pickerStyle(.menu)
            VStack(alignment: .leading, spacing: 6) {
                field(.frequency, label: EQWords.Editor.frequency, unit: EQWords.Editor.hz, filter: f, output: output,
                      steps: false)
                Slider(value: Binding<Double>(get: { EQEditorRules.place(f.fc) }, set: { (place: Double) -> Void in
                    editedElsewhere()
                    var g = f
                    g.fc = EQEditorRules.frequency(place: place)
                    edit(g, output)
                }), in: 0...1, onEditingChanged: { (down: Bool) -> Void in hold(down) })
                .accessibilityLabel(EQWords.Editor.frequency)
                .accessibilityValue("\(EQWords.number(f.fc)) \(EQWords.Editor.hz)")
                if let note = EQEditorRules.cornerNote(f) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if f.kind.hasGain {
                field(.gain, label: EQWords.Editor.gain, unit: EQWords.Editor.dB, filter: f, output: output, steps: true)
            }
        }
    }

    /// Q, Width or Slope - as the filter is written - and "Use Q instead" for the two that aren't a Q.
    private func widthSection(_ f: EQFilter, output: EQOutput) -> some View {
        let which = EQEditorRules.widthField(f)
        let label: String, unit: String?
        switch which {
        case .width: (label, unit) = (EQWords.Editor.width, EQWords.Editor.octaves)
        case .slope: (label, unit) = (EQWords.Editor.slope, EQWords.Editor.dBAnOctave)
        default: (label, unit) = (EQWords.Editor.q, nil)
        }
        return Section {
            field(which, label: label, unit: unit, filter: f, output: output, steps: true)
            if which != .q, let converted = EQEditorRules.usingQ(f) {
                Button(EQWords.Editor.useQ) {
                    editedElsewhere()
                    edit(converted, output)
                }
            }
        }
    }

    /// A number's row: its label, the field (the phone's decimal mark; red while what was applied is out of range),
    /// its unit and - for Gain and the width - a stepper; the field's line under it. Label and field above the
    /// stepper at the accessibility sizes.
    private func field(_ field: EQField, label: String, unit: String?, filter f: EQFilter, output: EQOutput,
                       steps: Bool) -> some View {
        let typed = editing[field]
        let problem = { () -> String? in
            guard refused.contains(field), let typed, case .problem(let words) = EQEditorRules.check(typed, field, for: f)
            else { return nil }
            return words
        }()
        let shown = typed ?? EQEditorRules.text(f, field, decimal: decimal)
        let placeholder = field == .q || field == .width ? EQWords.Editor.placeholder(f.kind) : nil
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 4) {
            layout {
                HStack(spacing: 8) {
                    Text(label)
                    Spacer(minLength: 8)
                    TextField(label, text: Binding<String>(get: { shown }, set: { (now: String) -> Void in
                        editing[field] = now
                    }), prompt: placeholder.map { Text($0) })
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(problem == nil ? Color.primary : Palette.danger)
                    .focused($focus, equals: field)
                    .submitLabel(.done)
                    .onSubmit { commit(field, output) }
                    .frame(maxWidth: 120)
                    if let unit {
                        Text(unit)
                            .foregroundStyle(Palette.quiet)
                            .accessibilityHidden(true)
                    }
                }
                if steps {
                    let down = EQEditorRules.stepped(f, field, up: false)
                    let up = EQEditorRules.stepped(f, field, up: true)
                    Stepper(label, onIncrement: up.map { (g: EQFilter) -> (() -> Void) in
                        { step(g, output) }
                    }, onDecrement: down.map { (g: EQFilter) -> (() -> Void) in
                        { step(g, output) }
                    }, onEditingChanged: { (down: Bool) -> Void in hold(down) })
                    .labelsHidden()
                    .accessibilityValue([shown, unit].compactMap { $0 }.joined(separator: " "))
                    .fixedSize()
                }
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: changing it

    /// The filter as it is now, heard - its id kept.
    private func edit(_ g: EQFilter, _ output: EQOutput) {
        eq.editFilter(page.id, for: output, to: g)
    }

    /// A stepper's step: what was typed in its field gives way to it.
    private func step(_ g: EQFilter, _ output: EQOutput) {
        editedElsewhere()
        edit(g, output)
    }

    /// What was typed in a field, applied - nothing typed, nothing changes; out of range, its line shows and nothing
    /// changes.
    private func commit(_ field: EQField, _ output: EQOutput) {
        guard let typed = editing[field],
              let f = eq.setting(output).correction?.filters.first(where: { (g: EQFilter) -> Bool in g.id == page.id })
        else { return }
        switch EQEditorRules.check(typed, field, for: f) {
        case .value(let v):
            editing[field] = nil
            refused.remove(field)
            edit(EQEditorRules.applying(v, field, to: f), output)
        case .problem:
            refused.insert(field)
        }
    }

    /// Another control moved the filter: what was typed and not applied is dropped, so leaving the field later can't
    /// put it back over the change.
    private func editedElsewhere() {
        editing = [:]
        refused = []
        focus = nil
    }

    /// A finger down on the curve, the slider or a stepper (true), or up: the file waits for the last one up.
    private func hold(_ down: Bool) {
        if down {
            holding += 1
            eq.hold()
        } else if holding > 0 {
            holding -= 1
            eq.release()
        }
    }

    /// Back to the page it came from, once - deleted here, or the filter gone from under it.
    private func goBack() {
        guard !left else { return }
        left = true
        dismiss()
    }
}
