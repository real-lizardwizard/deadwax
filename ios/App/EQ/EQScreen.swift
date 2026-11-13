import DeadwaxCore
import SwiftUI

/// The EQ page (eq.md 3.2, 3.3): one output's EQ, top to bottom - the output and its switch, the curve and the line
/// under it, the correction (the Correction row and AutoEq's suggestion, slice 4), the tone (Preset, the ten sliders,
/// Save as Preset…), Other outputs, and Forget This Output for one that isn't connected. An inset grouped List titled
/// "EQ", large when pushed from You, inline in the sheet; a toolbar ••• with "Rename…", and "Done" in the sheet.
///
/// **Advanced** (3.8, slice 5; one switch per phone, after Other outputs): the curve grows to 220 pt with a handle for
/// each correction filter that is on and the selected one's numbers above it; Correction lists the filters by
/// frequency (each a row to its editor, with its switch, swiped to delete), Add Filter, Import from Files…, Paste and
/// Export…; a changed AutoEq correction goes back to AutoEq's from the Correction row's menu and the •••; and Preamp,
/// after Tone, sets it by hand. Imports from here are previewed over this page, For starting on its output.
///
/// - **Which output** (3.2, Core's EQPage): opened from You or Now Playing's •••, the page is the output now's and
///   follows the route - only while it is on top (nothing pushed or presented over it, its tab shown, Now Playing not
///   over You), and never under a finger. When it switches, the name crossfades and VoiceOver hears "EQ for …".
///   Opened from Other outputs, it stays on its output. The alerts and the dialog capture the output they were opened
///   for.
/// - **While Off, every control still works**, and a change turns the EQ on (EQModel says "EQ on").
struct EQScreen: View {
    /// `.now` (You's row, Now Playing's •••) or `.output(key)` (Other outputs).
    let opened: EQRoute

    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.eqDone) private var done
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The sheet's stack, in the sheet over Now Playing; nil on You's.
    @Environment(EQSheetStack.self) private var sheetStack: EQSheetStack?

    @State private var page: EQPage?
    /// This page, for its own import's preview (3.9).
    @State private var pageID = UUID()
    /// The handle selected (Advanced): its numbers in the capsule.
    @State private var selectedFilter: Int?
    @State private var appeared = false
    @State private var ask: EQNameAsk?
    @State private var forgetting: Forgetting?
    /// The dialog's title, kept while it animates away.
    @State private var forgetTitle = ""

    /// An output to forget, asked first (3.2, 3.12): this page's own (popped once it's gone), or one of Other outputs.
    private struct Forgetting {
        let key: String
        let isPage: Bool
    }

    /// The page as it is - or, before it first appears, as it will be.
    private var current: EQPage {
        if let page { return page }
        if case .output(let key) = opened { return .of(key, route: eq.route.key) }
        return .now(route: eq.route.key)
    }

    /// On top: shown, with nothing pushed or presented over it - no import's preview (3.9) - and, on You's stack, Now
    /// Playing or a shared file's EQ sheet not over it.
    private var onTop: Bool {
        appeared && ask == nil && forgetting == nil && !navigation.eqPreviewUp
            && !(done == nil && (navigation.nowPlayingShown || navigation.eqImportSheet))
    }

    var body: some View {
        let page = current
        let key = page.output
        let output = eq.output(key)
        let setting = eq.setting(output)
        let connected = key == eq.route.key
        let advanced = eq.advanced
        List {
            outputSection(output, on: setting.on, connected: connected)
            curveSection(output, setting: setting, connected: connected, held: page.held > 0, advanced: advanced)
            correctionSection(output, setting: setting, advanced: advanced)
            toneSection(output, tone: setting.tone)
            if advanced {
                preampSection(output, setting: setting)
            }
            if EQScreenRules.showsOthers(page) {
                othersSection(key)
            }
            Section {
                Toggle(EQWords.Advanced.title, isOn: Binding<Bool>(get: { advanced }, set: { (now: Bool) -> Void in
                    eq.advanced = now
                }))
            } footer: {
                Text(EQWords.Advanced.footer)
            }
            if EQScreenRules.forgets(page, met: eq.settings.output(key) != nil) {
                Section {
                    Button(EQWords.Outputs.forgetThis, role: .destructive) {
                        askForget(key, isPage: true)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(EQWords.Screen.title)
        .navigationBarTitleDisplayMode(done == nil ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(EQWords.Screen.rename, systemImage: "pencil") { askRename(key) }
                    if advanced && EQAdvancedRules.goesBack(setting.correction) {
                        Button(EQWords.Correction.backToAutoEq, systemImage: "arrow.uturn.backward") {
                            eq.backToAutoEq(for: output)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(EQWords.Screen.more)
            }
        }
        .eqDoneButton()
        .eqNameAlert($ask)
        .confirmationDialog(forgetTitle, isPresented: Binding<Bool>(get: { forgetting != nil }, set: { (up: Bool) -> Void in
            if !up { forgetting = nil }
        }), titleVisibility: .visible, presenting: forgetting) { (asked: Forgetting) in
            Button(EQWords.Outputs.forget, role: .destructive) { forget(asked) }
            Button(EQWords.Outputs.cancel, role: .cancel) {}
        }
        .eqImportPreview(page: pageID)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .onChange(of: onTop, initial: true) { _, top in
            if top { show() } else { self.page?.covered() }
        }
        .onChange(of: eq.route.key) { _, route in
            if self.page?.heard(route: route) == true { switched() }
        }
        .onChange(of: key) { (_: String, _: String) -> Void in selectedFilter = nil }
        // AutoEq's suggestion for the output shown (3.7): asked once a launch, and again when deadwax comes back in reach
        .task(id: SuggestionAsk(key: key, online: reachability.online, correction: setting.correction == nil)) {
            eq.askSuggestion(for: output, client: server.client, online: reachability.online)
        }
    }

    /// What the suggestion is asked again on: the output shown, deadwax in reach, the output without a correction.
    private struct SuggestionAsk: Equatable {
        let key: String
        let online: Bool
        let correction: Bool
    }

    // MARK: the sections

    /// 1. The output, and its switch - the AirPlay footer when it is AirPlay.
    private func outputSection(_ output: EQOutput, on: Bool, connected: Bool) -> some View {
        Section {
            EQOutputHeader(output: output, connected: connected)
            Toggle(EQWords.Screen.toggle, isOn: Binding<Bool>(get: { on }, set: { (now: Bool) -> Void in
                eq.setOn(now, for: output)
            }))
            .accessibilityLabel(EQWords.Screen.toggleSaid(output.name))
        } footer: {
            if output.isAirPlay {
                Text(EQWords.Screen.airPlayFooter)
            }
        }
    }

    /// 2. The curve, edge to edge, and the line under it (3.3) - for an admin, the engine's own words under the line
    /// when its unit couldn't be made. Not connected, "Not connected: this is what it plays when it is." above it. In
    /// Advanced, 220 pt with the correction's handles and the selected one's capsule (3.8).
    private func curveSection(_ output: EQOutput, setting: EQOutputSetting, connected: Bool, held: Bool,
                              advanced: Bool) -> some View {
        let key = output.key
        let line = eq.line(key)
        return Section {
            EQCurveView(drawing: eq.drawing(key), name: output.name, animated: !held,
                        height: advanced ? 220 : EQCurveView.height,
                        handles: advanced ? handles(output, correction: setting.correction) : nil)
                .listRowInsets(EdgeInsets())
        } header: {
            if !connected {
                Text(EQWords.Screen.notConnectedLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .textCase(nil)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(line.text)
                    .foregroundStyle(Self.color(line.tone))
                if line.tone == .danger, server.access.seesDetail, let problem = eq.unitProblem {
                    Text(problem)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Advanced's handles (3.8): the correction's filters that are on; the selected one white, its numbers above the
    /// plot. A handle's drag is heard as it goes, and holds the page on its output until it is let go.
    private func handles(_ output: EQOutput, correction: EQCorrection?) -> EQHandles {
        let selected = correction?.filters.first { (f: EQFilter) -> Bool in f.id == selectedFilter && f.on }
        let model = eq
        return EQHandles(handles: EQHandleRules.handles(correction), selected: selected?.id,
                         capsule: selected.map { (f: EQFilter) -> String in EQWords.Advanced.capsule(f) },
                         showsCapsule: true,
                         filter: { (id: Int) -> EQFilter? in
                             model.setting(output).correction?.filters.first { (f: EQFilter) -> Bool in f.id == id }
                         },
                         select: { (id: Int) -> Void in selectedFilter = id },
                         change: { (id: Int, f: EQFilter) -> Void in model.editFilter(id, for: output, to: f) },
                         hold: { (down: Bool) -> Void in hold(down) })
    }

    /// 3. Correction (3.2, 3.7): the Correction row - its value None or the correction's name, where it's from under
    /// the label - pushing the picker; and, when it applies, AutoEq's suggestion: one headphone's profile, or the
    /// picker searched for the output's name. Swipe (or VoiceOver's action) for Not now, which puts it away for good.
    /// In Advanced (3.8) the Correction row's menu has "Back to AutoEq's" for a changed AutoEq correction, and the
    /// section grows its filters, Add Filter, Import from Files…, Paste and Export….
    private func correctionSection(_ output: EQOutput, setting: EQOutputSetting, advanced: Bool) -> some View {
        let suggestion = eq.suggestion(output.key)
        let shows = EQSuggestionRules.shows(output, setting, suggestion, online: reachability.online)
        return Section {
            EQLink(route: .correction(output.key)) {
                LabeledContent {
                    Text(EQWords.Correction.value(setting.correction))
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(EQWords.Correction.header)
                        if let correction = setting.correction {
                            Text(EQWords.Correction.source(correction))
                                .font(.footnote)
                                .foregroundStyle(Palette.quiet)
                        }
                    }
                }
            }
            .contextMenu {
                if advanced && EQAdvancedRules.goesBack(setting.correction) {
                    Button(EQWords.Correction.backToAutoEq, systemImage: "arrow.uturn.backward") {
                        eq.backToAutoEq(for: output)
                    }
                }
            }
            if shows, let suggestion, let lines = suggestion.lines {
                EQLink(route: Self.route(suggestion, for: output.key)) {
                    EQSuggestionRow(title: lines.title, detail: lines.detail)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(EQWords.Correction.notNow) { eq.mark(.notNow, for: output) }
                }
                .accessibilityAction(named: EQWords.Correction.notNow) { eq.mark(.notNow, for: output) }
                .onAppear { eq.mark(.shown, for: output) }
            }
            if advanced {
                advancedRows(output, setting: setting)
            }
        } header: {
            Text(EQWords.Correction.header)
        } footer: {
            Text(EQWords.Correction.footer(output))
        }
    }

    /// Advanced's rows in Correction (3.8): the filters low to high - each to its editor, its switch at the right, a
    /// filter left out at this rate saying so - swiped to delete; Add Filter (pushed into its editor; disabled at 64
    /// to an ear, saying so); Import from Files… and Paste (3.9); Export… (3.11).
    @ViewBuilder
    private func advancedRows(_ output: EQOutput, setting: EQOutputSetting) -> some View {
        let key = output.key
        let correction = setting.correction
        let canAdd = EQAdvancedRules.canAdd(correction)
        ForEach(EQAdvancedRules.rows(correction, rate: eq.rate(key)), id: \.filter.id) { (row: EQFilterRow) in
            EQFilterRowView(row: row, open: {
                push(.filter(EQFilterPage(output: key, id: row.filter.id)))
            }, setOn: { (on: Bool) -> Void in
                eq.setFilter(row.filter.id, on: on, for: output)
            }, delete: {
                eq.deleteFilter(row.filter.id, for: output)
            })
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(EQWords.Advanced.delete, role: .destructive) { eq.deleteFilter(row.filter.id, for: output) }
            }
        }
        Button {
            if let id = eq.addFilter(for: output) { push(.filter(EQFilterPage(output: key, id: id))) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(EQWords.Advanced.addFilter, systemImage: "plus")
                if !canAdd {
                    Text(EQWords.Advanced.mostFilters)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .disabled(!canAdd)
        EQImportRows(page: pageID, key: key)
        EQExportMenu(setting: setting, settings: eq.settings, rate: eq.rate(key))
    }

    /// A page pushed from this one - on the sheet's own stack, or You's.
    private func push(_ route: EQRoute) {
        if let sheetStack {
            sheetStack.path.append(route)
        } else {
            navigation.open(.eq(route))
        }
    }

    /// 5. Preamp (3.8, Advanced): Automatic, on by default - deadwax's preamp, shown; off, yours, a stepper of 0.1 dB
    /// from -30 to +12, and when it takes away less than the curve's top, the line that says loud songs may clip.
    private func preampSection(_ output: EQOutput, setting: EQOutputSetting) -> some View {
        let key = output.key
        let drawing = eq.drawing(key)
        let hand = { () -> Double? in
            if case .hand(let dB) = setting.preamp { return dB }
            return nil
        }()
        return Section {
            Toggle(EQWords.Preamp.automatic, isOn: Binding<Bool>(get: { hand == nil }, set: { (now: Bool) -> Void in
                eq.setAutomaticPreamp(now, for: output)
            }))
            if let hand {
                Stepper(value: Binding<Double>(get: { hand }, set: { (now: Double) -> Void in
                    eq.setHandPreamp(now, for: output)
                }), in: -30...12, step: 0.1, onEditingChanged: { (down: Bool) -> Void in hold(down) }) {
                    LabeledContent(EQWords.Preamp.row) {
                        Text(EQWords.Preamp.value(hand))
                            .monospacedDigit()
                    }
                }
                .accessibilityValue(EQWords.decibelsSaid(hand))
            } else {
                LabeledContent(EQWords.Preamp.row) {
                    Text(EQWords.Preamp.value(setting.on ? drawing.preamp : automaticPreamp(output, setting)))
                        .monospacedDigit()
                }
            }
        } header: {
            Text(EQWords.Preamp.header)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(hand == nil ? EQWords.Preamp.automaticFooter : EQWords.Preamp.handFooter)
                if let hand, setting.on, drawing.top + hand > 1e-9 {
                    Text(EQWords.Screen.hand(hand, top: drawing.top))
                        .foregroundStyle(Palette.amber)
                }
            }
        }
    }

    /// The automatic preamp an output would play at, on - shown while it is Off, as every control still works there.
    private func automaticPreamp(_ output: EQOutput, _ setting: EQOutputSetting) -> Double {
        var on = setting
        on.on = true
        return eq.settings.bank(on, rate: eq.rate(output.key), version: 0).preamp
    }

    /// Where the suggestion goes: one headphone's profile, or the picker, searched (3.7).
    private static func route(_ suggestion: EQSuggestion, for key: String) -> EQRoute {
        if case .one(let row) = suggestion { return .profile(AutoEqPage(output: key, row: row)) }
        return .correction(key)
    }

    /// 4. Tone: the Preset row, the ten sliders - ten stepper rows at the accessibility sizes (3.15) - and Save as
    /// Preset… while the tone is Custom.
    private func toneSection(_ output: EQOutput, tone: EQTone) -> some View {
        let gains = eq.settings.gains(tone)
        let change = { (band: Int, gain: Double) -> Void in
            eq.setBand(band, to: gain, for: output)
        }
        return Section {
            EQLink(route: .presets(output.key)) {
                LabeledContent(EQWords.Tone.preset, value: EQWords.Tone.value(tone, in: eq.settings))
            }
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(gains.indices, id: \.self) { band in
                    EQStepperRow(band: band, gain: gains[band], onChange: change, onHold: hold)
                }
            } else {
                EQSliders(gains: gains, onChange: change, onHold: hold)
                    .listRowInsets(EdgeInsets())
            }
            if Self.isCustom(tone) {
                Button(EQWords.Tone.saveAsPreset) { askSave(output) }
                    .foregroundStyle(Palette.accent)
            }
        } header: {
            Text(EQWords.Tone.header)
        } footer: {
            Text(EQWords.Tone.footer)
        }
    }

    /// 6. Other outputs (3.12): each to its own page; swipe for Rename and Forget (never the speaker), which asks first.
    private func othersSection(_ key: String) -> some View {
        Section {
            ForEach(EQScreenRules.others(eq.settings, shown: key), id: \.key) { other in
                EQLink(route: .output(other.key)) {
                    EQOtherOutputRow(output: other.output, short: EQWords.shortSetting(other, in: eq.settings))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if EQScreenRules.forgets(other.key) {
                        Button(EQWords.Outputs.forget, role: .destructive) { askForget(other.key, isPage: false) }
                    }
                    Button(EQWords.Outputs.rename) { askRename(other.key) }
                }
            }
        } header: {
            Text(EQWords.Outputs.others)
        }
    }

    // MARK: following the route (3.2)

    /// On top again (first shown, Back, an alert gone): the page made the first time; after, the route as it is now
    /// heard, and the page switched to it if it moved while covered.
    private func show() {
        guard page != nil else {
            page = current
            return
        }
        page?.heard(route: eq.route.key)
        if page?.shown() == true { switched() }
    }

    /// A finger down on a slider or a stepper (true), or up: the page never switches under it, and the file is
    /// written once they're all up.
    private func hold(_ down: Bool) {
        if down {
            page?.hold()
            eq.hold()
        } else {
            eq.release()
            if page?.release() == true { switched() }
        }
    }

    /// The page switched to the route: VoiceOver hears "EQ for James's AirPods Pro" (the header crossfades itself).
    private func switched() {
        guard let key = page?.output else { return }
        EQModel.say(EQWords.Said.route(eq.output(key).name))
    }

    // MARK: asking

    private func askRename(_ key: String) {
        let model = eq
        let kept = model.settings.output(key)
        ask = EQNameAsk(title: EQWords.Outputs.renameTitle, placeholder: kept?.name ?? model.output(key).name,
                        text: kept?.renamed ?? "", save: EQWords.Outputs.save, cancel: EQWords.Outputs.cancel,
                        done: { (name: String) -> String? in
                            model.rename(key, to: name)
                            return nil
                        })
    }

    private func askSave(_ output: EQOutput) {
        let model = eq
        ask = EQNameAsk(title: EQWords.Presets.saveTitle, placeholder: EQWords.Presets.name, save: EQWords.Presets.save,
                        cancel: EQWords.Presets.cancel, done: { (name: String) -> String? in
                            model.savePreset(name, from: output).map(EQWords.Presets.problem)
                        })
    }

    private func askForget(_ key: String, isPage: Bool) {
        forgetTitle = EQWords.Outputs.forgetQuestion(eq.output(key).name)
        forgetting = Forgetting(key: key, isPage: isPage)
    }

    private func forget(_ asked: Forgetting) {
        eq.forget(asked.key)
        if asked.isPage { dismiss() }
    }

    // MARK: words and colours

    private static func isCustom(_ tone: EQTone) -> Bool {
        if case .custom = tone { return true }
        return false
    }

    private static func color(_ tone: EQLine.Tone) -> Color {
        switch tone {
        case .quiet: return Palette.quiet
        case .amber: return Palette.amber
        case .danger: return Palette.danger
        }
    }
}

/// AutoEq's suggestion's row (3.7): `wand.and.stars` in accent, its two lines - one element, the chevron the link's.
struct EQSuggestionRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One correction filter's row (3.8): its type, and under it "105 Hz · +2.6 dB · Q 0.70" (its ear after it when it is
/// one ear's) in `.footnote.monospacedDigit()` `quiet` - a filter left out at this rate saying so in amber - tapped
/// for its editor; its switch at the right. For VoiceOver the row is one element, "Filter 3: peak at 8903 hertz, plus
/// 6 decibels, Q 1.66", its value On or Off, its actions Delete and Turn Off (or On); the switch is its own, "Filter 3
/// on".
struct EQFilterRowView: View {
    let row: EQFilterRow
    let open: () -> Void
    let setOn: (Bool) -> Void
    let delete: () -> Void

    var body: some View {
        let f = row.filter
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(EQWords.Advanced.type(f.kind))
                        .foregroundStyle(.primary)
                    Text(EQWords.Advanced.detail(f))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.leftOut {
                        Text(EQWords.Advanced.above)
                            .font(.footnote)
                            .foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EQWords.Advanced.said(f, number: row.number)
                                + (row.leftOut ? ". " + EQWords.Advanced.above : ""))
            .accessibilityValue(f.on ? EQWords.Advanced.on : EQWords.Advanced.off)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: EQWords.Advanced.delete, delete)
            .accessibilityAction(named: f.on ? EQWords.Advanced.turnOff : EQWords.Advanced.turnOn) { setOn(!f.on) }
            Toggle(EQWords.Advanced.switchSaid(row.number), isOn: Binding<Bool>(get: { f.on }, set: setOn))
                .labelsHidden()
        }
    }
}
