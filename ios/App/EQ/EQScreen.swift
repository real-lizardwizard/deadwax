import DeadwaxCore
import SwiftUI

/// The EQ page (eq.md 3.2, 3.3): one output's EQ, top to bottom - the output and its switch, the curve and the line
/// under it, the correction (the Correction row and AutoEq's suggestion, slice 4), the tone (Preset, the ten sliders,
/// Save as Preset…), Other outputs, and Forget This Output for one that isn't connected. Titled "EQ", large when pushed
/// from You, inline in the Mac's side panel; a ••• with "Rename…".
///
/// **Drawn** (the redesign, slice R3b - notes/ios.md "The redesign, slice R3b: the Queue, Info and the EQ inside";
/// iEQ.dc.html): on the phone as iEQ - the output as a button across the page (EQOutputButton: AirPlay's own picker
/// under it, the output's name on it), the curve in a well (EQCurveView's `well`), and Correction, Tone, Preamp, Other
/// outputs and Advanced as the look's groups (PhoneGroup), the sliders' knobs round (EQSliders). In Now Playing's sheet
/// (`sheet`, its EQ tab) the top is the sheet's: `‹ Now Playing`, the strip, and at its right "EQ on" as the purple
/// switch (PhoneSwitchStyle - a real Toggle to VoiceOver) and the •••. Pushed on You's stack, the system's bar as
/// before, the switch on the output's card. On the Mac, in the side panel, the inset grouped List as it was. Every
/// control makes the same EQModel call it did, so the sound is as it was; the phone's groups aren't a List, so their
/// rows have no swipes: Not now is a button beside the suggestion, a filter is deleted in its editor (Delete Filter) or
/// by VoiceOver's action, and Other outputs' Rename and Forget are VoiceOver's actions on the row and the output's own
/// page's (its ••• Rename… and Forget This Output).
///
/// **Advanced** (3.8, slice 5; one switch per phone, after Other outputs): the curve grows to 220 pt with a handle for
/// each correction filter that is on and the selected one's numbers above it; Correction lists the filters by
/// frequency (each a row to its editor, with its switch, swiped to delete), Add Filter, Import from Files…, Paste and
/// Export…; a changed AutoEq correction goes back to AutoEq's from the Correction row's menu and the •••; and Preamp,
/// after Tone, sets it by hand. Imports from here are previewed over this page, For starting on its output.
///
/// - **Which output** (3.2, Core's EQPage): opened from You or Now Playing's EQ, the page is the output now's and
///   follows the route - only while it is on top (nothing pushed or presented over it, its tab shown, Now Playing not
///   over You), and never under a finger. When it switches, the name crossfades and VoiceOver hears "EQ for …".
///   Opened from Other outputs, it stays on its output. The alerts and the dialog capture the output they were opened
///   for.
/// - **While Off, every control still works**, and a change turns the EQ on (EQModel says "EQ on").
struct EQScreen: View {
    /// `.now` (You's row, Now Playing's EQ) or `.output(key)` (Other outputs).
    let opened: EQRoute
    /// (R3b) In Now Playing's sheet, its EQ tab's page: the sheet's top (`‹ Now Playing`, the strip) - nil on You's stack,
    /// for a page pushed on the sheet's own, and in the Mac's side panel.
    var sheet: SheetTop? = nil

    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.eqDone) private var done
    /// (The Mac redesign, R3) In the Mac's side panel, the dock's EQ tab: its title inline, as in the sheet.
    @Environment(\.inSidePanel) private var inSidePanel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The sheet's stack, in the sheet over Now Playing; nil on You's.
    @Environment(EQSheetStack.self) private var sheetStack: EQSheetStack?

    /// (R3b) iEQ's groups on the phone; the Mac's side panel's inset List as it was.
    private var cards: Bool { !Platform.mac }
    /// (R3b) The phone's page's sides, the room above the curve's well, and under the page (the drawing's foot).
    private static let side: CGFloat = 16
    private static let wellAbove: CGFloat = 12
    private static let foot: CGFloat = 34

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
        let advanced = eq.advanced
        top(content(page, output: output, setting: setting, advanced: advanced), output: output, setting: setting,
            advanced: advanced)
        .eqNameAlert($ask)
        .confirmationDialog(forgetTitle, isPresented: Binding<Bool>(get: { forgetting != nil }, set: { (up: Bool) -> Void in
            if !up { forgetting = nil }
        }), titleVisibility: .visible, presenting: forgetting) { (asked: Forgetting) in
            Button(EQWords.Outputs.forget, role: .destructive) { forget(asked) }
            Button(EQWords.Outputs.cancel, role: .cancel) {}
                .returnCancels()
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

    /// (R3b) The page's top. In Now Playing's sheet the sheet's own (`sheetTop`): "EQ on" and the ••• at its right - and
    /// no Done, `‹ Now Playing` puts the sheet down. Elsewhere titled "EQ", the ••• in the toolbar, and Done where the
    /// page is the sheet's or the side panel's (EQDoneButton), as before.
    @ViewBuilder
    private func top<Content: View>(_ content: Content, output: EQOutput, setting: EQOutputSetting,
                                    advanced: Bool) -> some View {
        if let sheet {
            content
                .sheetTop(sheet) {
                    onSwitch(output, on: setting.on)
                    more(output, setting: setting, advanced: advanced)
                }
        } else {
            content
                .navigationTitle(EQWords.Screen.title)
                .navigationBarTitleDisplayMode(done == nil && !inSidePanel ? .large : .inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        more(output, setting: setting, advanced: advanced)
                    }
                }
                .eqDoneButton()
        }
    }

    /// The •••: Rename…, and in Advanced "Back to AutoEq's" for a changed AutoEq correction. (R3b) In the sheet's top a
    /// small button of the look's, square.
    private func more(_ output: EQOutput, setting: EQOutputSetting, advanced: Bool) -> some View {
        let key = output.key
        return Menu {
            Button(EQWords.Screen.rename, systemImage: "pencil") { askRename(key) }
            if advanced && EQAdvancedRules.goesBack(setting.correction) {
                Button(EQWords.Correction.backToAutoEq, systemImage: "arrow.uturn.backward") {
                    eq.backToAutoEq(for: output)
                }
            }
        } label: {
            Image(systemName: sheet == nil ? "ellipsis.circle" : "ellipsis")
        }
        .modifier(EQMoreLook(inSheet: sheet != nil))
        .accessibilityLabel(EQWords.Screen.more)
    }

    /// (R3b) "EQ on" (iEQ's top, its words as drawn): the output's switch as the purple switch - PhoneSwitchStyle, a real
    /// Toggle to VoiceOver ("EQ for James's AirPods Pro", its value, a double tap) - in the sheet's top at the small size
    /// in the second colour, on You's page the output card's row at the row's. In the sheet's top from xxxLarge
    /// (`folds`) the switch alone, its words folded away: `‹ Now Playing` (17), "EQ on" (13), the switch (46) and the
    /// ••• (small) take about 372 of a 375-point phone at xxxLarge (about 350 at xxLarge), too little to spare; the
    /// switch alone about 312 (test_ios_nowplaying_pages_look.py works it out, taken wide). VoiceOver's name for it is
    /// the same either way.
    private func onSwitch(_ output: EQOutput, on: Bool) -> some View {
        Toggle(isOn: Binding<Bool>(get: { on }, set: { (now: Bool) -> Void in
            eq.setOn(now, for: output)
        })) {
            if sheet == nil || !Self.folds(dynamicTypeSize) {
                Text(EQWords.Screen.on)
                    .font(Typeface.Phone.text(sheet == nil ? .row : .small))
                    .foregroundStyle(sheet == nil ? DWPalette.text : DWPalette.t2)
            }
        }
        .toggleStyle(.phoneSwitch)
        .accessibilityLabel(EQWords.Screen.toggleSaid(output.name))
    }

    /// (R3b's review) From xxxLarge the sheet's top holds the switch without its words.
    static func folds(_ size: DynamicTypeSize) -> Bool {
        size > .xxLarge
    }

    /// The page: (R3b) iEQ's groups on the phone, the inset List on the Mac.
    @ViewBuilder
    private func content(_ page: EQPage, output: EQOutput, setting: EQOutputSetting, advanced: Bool) -> some View {
        let connected = output.key == eq.route.key
        if cards {
            cardsPage(page, output: output, setting: setting, connected: connected, advanced: advanced)
        } else {
            listPage(page, output: output, setting: setting, connected: connected, advanced: advanced)
        }
    }

    /// The Mac's: the inset grouped List, as it was.
    private func listPage(_ page: EQPage, output: EQOutput, setting: EQOutputSetting, connected: Bool,
                          advanced: Bool) -> some View {
        let key = output.key
        return List {
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
                    .font(Typeface.footnote)
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
            Group {
                if output.isAirPlay {
                    Text(EQWords.Screen.airPlayFooter)
                }
            }
            .font(Typeface.footnote)
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
            Group {
                if !connected {
                    Text(EQWords.Screen.notConnectedLine)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .textCase(nil)
                }
            }
            .font(Typeface.footnote)
        } footer: {
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    Text(line.text)
                        .foregroundStyle(Self.color(line.tone))
                    if line.tone == .danger, server.access.seesDetail, let problem = eq.unitProblem {
                        Text(problem)
                            .font(Typeface.mono(.footnote))
                            .foregroundStyle(Palette.quiet)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(Typeface.footnote)
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
                                .font(Typeface.footnote)
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
                .font(Typeface.footnote)
        } footer: {
            Text(EQWords.Correction.footer(output))
                .font(Typeface.footnote)
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
                        .font(Typeface.footnote)
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
                .font(Typeface.footnote)
        } footer: {
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hand == nil ? EQWords.Preamp.automaticFooter : EQWords.Preamp.handFooter)
                    if let hand, setting.on, drawing.top + hand > 1e-9 {
                        Text(EQWords.Screen.hand(hand, top: drawing.top))
                            .foregroundStyle(Palette.amber)
                    }
                }
            }
            .font(Typeface.footnote)
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
                .font(Typeface.footnote)
        } footer: {
            Text(EQWords.Tone.footer)
                .font(Typeface.footnote)
        }
    }

    /// 6. Other outputs (3.12): each to its own page; swipe for Rename and Forget (never the speaker), which asks first.
    private func othersSection(_ key: String) -> some View {
        Section {
            ForEach(EQScreenRules.others(eq.settings, shown: key, device: Platform.device), id: \.key) { other in
                EQLink(route: .output(other.key)) {
                    EQOtherOutputRow(output: other.output(Platform.device), short: EQWords.shortSetting(other, in: eq.settings))
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
                .font(Typeface.footnote)
        }
    }

    // MARK: the phone's groups (R3b, iEQ)

    /// iEQ: the output, the curve in its well and the line under it, then the groups - Correction, Tone, Preamp (in
    /// Advanced), Other outputs, Advanced - and Forget This Output, on the panel's ground. The same sections as the List,
    /// each control the same call.
    private func cardsPage(_ page: EQPage, output: EQOutput, setting: EQOutputSetting, connected: Bool,
                           advanced: Bool) -> some View {
        let key = output.key
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                outputCard(output, on: setting.on, connected: connected)
                curveWell(output, setting: setting, connected: connected, held: page.held > 0, advanced: advanced)
                correctionCard(output, setting: setting, advanced: advanced)
                toneCard(output, tone: setting.tone)
                if advanced {
                    preampCard(output, setting: setting)
                }
                if EQScreenRules.showsOthers(page) {
                    othersCard(key)
                }
                PhoneGroup {
                    Toggle(isOn: Binding<Bool>(get: { advanced }, set: { (now: Bool) -> Void in
                        eq.advanced = now
                    })) {
                        Text(EQWords.Advanced.title)
                            .font(Typeface.Phone.text(.row))
                            .foregroundStyle(DWPalette.text)
                    }
                    .toggleStyle(.phoneSwitch)
                }
                cardNote(EQWords.Advanced.footer)
                if EQScreenRules.forgets(page, met: eq.settings.output(key) != nil) {
                    Button(role: .destructive) {
                        askForget(key, isPage: true)
                    } label: {
                        EQButtonWords(words: EQWords.Outputs.forgetThis)
                    }
                    .buttonStyle(DWButtonStyle(kind: .danger, fills: true))
                    .padding(.top, CGFloat(PhoneLook.groupAbove))
                }
            }
            .padding(.horizontal, Self.side)
            .padding(.top, CGFloat(PhoneLook.topGap) / 2)
            .padding(.bottom, Self.foot)
        }
        .background(DWPalette.panel)
    }

    /// The output (iEQ's first row): its button across the page - AirPlay's picker under it - and, on You's page, "EQ on"
    /// under it (the sheet's is in its top); the AirPlay line for an AirPlay output.
    private func outputCard(_ output: EQOutput, on: Bool, connected: Bool) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(PhoneLook.goGap)) {
            EQOutputButton(output: output, connected: connected, playsTo: eq.settings.setting(for: eq.route).shownName)
            if sheet == nil {
                onSwitch(output, on: on)
            }
            if output.isAirPlay {
                cardNote(EQWords.Screen.airPlayFooter)
            }
        }
    }

    /// The curve in a well (iEQ's `.well`), "Not connected: …" above it for an output that isn't, and the line under it
    /// - with, for an admin, the engine's own words when its unit couldn't be made. In Advanced 220 pt with the
    /// correction's handles, as the List's.
    private func curveWell(_ output: EQOutput, setting: EQOutputSetting, connected: Bool, held: Bool,
                           advanced: Bool) -> some View {
        let key = output.key
        let line = eq.line(key)
        return VStack(alignment: .leading, spacing: CGFloat(PhoneLook.groupEnds) * 3) {
            if !connected {
                cardNote(EQWords.Screen.notConnectedLine, above: 0)
            }
            EQCurveView(drawing: eq.drawing(key), name: output.name, animated: !held,
                        height: advanced ? 220 : EQCurveView.height,
                        handles: advanced ? handles(output, correction: setting.correction) : nil, well: true)
                .background { DWWell() }
            cardNote(line.text, colour: Self.cardColour(line.tone), above: 0)
            if line.tone == .danger, server.access.seesDetail, let problem = eq.unitProblem {
                Text(problem)
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(DWPalette.t2)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, Self.wellAbove)
    }

    /// Correction (iEQ's group): the correction - its name, where it's from under it - to the picker, its long press
    /// Back to AutoEq's in Advanced as the List's; AutoEq's suggestion with Not now beside it; in Advanced the filters,
    /// Add Filter, Import from Files…, Paste and Export….
    @ViewBuilder
    private func correctionCard(_ output: EQOutput, setting: EQOutputSetting, advanced: Bool) -> some View {
        let suggestion = eq.suggestion(output.key)
        let shows = EQSuggestionRules.shows(output, setting, suggestion, online: reachability.online)
        let value = EQWords.Correction.value(setting.correction)
        let source = setting.correction.map(EQWords.Correction.source)
        PhoneGroup(legend: EQWords.Correction.header) {
            EQLink(route: .correction(output.key)) {
                PhoneGo {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value)
                            .font(Typeface.Phone.text(.row).weight(.semibold))
                        if let source {
                            Text(source)
                                .font(Typeface.Phone.text(.extraSmall))
                                .foregroundStyle(DWPalette.t2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PhoneChevron()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(EQWords.Correction.header)
                .accessibilityValue([value, source].compactMap { $0 }.joined(separator: ", "))
            }
            .buttonStyle(.plain)
            //? (R3b's review) the List's long press on the Correction row: Back to AutoEq's (also the •••'s)
            .contextMenu {
                if advanced && EQAdvancedRules.goesBack(setting.correction) {
                    Button(EQWords.Correction.backToAutoEq, systemImage: "arrow.uturn.backward") {
                        eq.backToAutoEq(for: output)
                    }
                }
            }
            if shows, let suggestion, let lines = suggestion.lines {
                suggestionRow(output, route: Self.route(suggestion, for: output.key), lines: lines)
            }
            if advanced {
                cardAdvancedRows(output, setting: setting)
            }
        }
        cardNote(EQWords.Correction.footer(output))
    }

    /// AutoEq's suggestion (3.7) in Correction's group: its two lines to the profile or the picker, and Not now beside it
    /// - a button, where the List's row is swiped - which puts it away for good. One element for VoiceOver: the link,
    /// Not now its action, as before. Stacked at the accessibility sizes.
    private func suggestionRow(_ output: EQOutput, route: EQRoute, lines: (title: String, detail: String)) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: CGFloat(PhoneLook.goGap)))
            : AnyLayout(HStackLayout(spacing: CGFloat(PhoneLook.goGap)))
        return layout {
            EQLink(route: route) {
                HStack(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.goGap)) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(DWPalette.acc)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lines.title)
                            .font(Typeface.Phone.text(.row))
                            .foregroundStyle(DWPalette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lines.detail)
                            .font(Typeface.Phone.text(.extraSmall))
                            .foregroundStyle(DWPalette.t2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PhoneChevron()
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityAction(named: EQWords.Correction.notNow) { eq.mark(.notNow, for: output) }
            Button {
                eq.mark(.notNow, for: output)
            } label: {
                EQButtonWords(words: EQWords.Correction.notNow)
            }
            .buttonStyle(DWButtonStyle(size: .small))
            //? VoiceOver's is the link's action: one element
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(PhoneLook.groupEnds) * 3)
        .lookHeight(PhoneLook.goRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .onAppear { eq.mark(.shown, for: output) }
    }

    /// Advanced's rows in Correction's group (3.8): the filters low to high, each to its editor with its switch - Delete
    /// on a long press, where the List's row is swiped, and VoiceOver's action; Add Filter; Import from Files… and
    /// Paste; Export….
    @ViewBuilder
    private func cardAdvancedRows(_ output: EQOutput, setting: EQOutputSetting) -> some View {
        let key = output.key
        let correction = setting.correction
        let canAdd = EQAdvancedRules.canAdd(correction)
        ForEach(EQAdvancedRules.rows(correction, rate: eq.rate(key)), id: \.filter.id) { (row: EQFilterRow) in
            EQPhoneFilterRow(row: row, open: {
                push(.filter(EQFilterPage(output: key, id: row.filter.id)))
            }, setOn: { (on: Bool) -> Void in
                eq.setFilter(row.filter.id, on: on, for: output)
            }, delete: {
                eq.deleteFilter(row.filter.id, for: output)
            })
        }
        Button {
            if let id = eq.addFilter(for: output) { push(.filter(EQFilterPage(output: key, id: id))) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(EQWords.Advanced.addFilter, systemImage: "plus")
                if !canAdd {
                    Text(EQWords.Advanced.mostFilters)
                        .font(Typeface.Phone.text(.extraSmall))
                        .foregroundStyle(DWPalette.t2)
                }
            }
        }
        .buttonStyle(EQCardRowStyle())
        .disabled(!canAdd)
        EQImportRows(page: pageID, key: key)
            .buttonStyle(EQCardRowStyle())
        EQExportMenu(setting: setting, settings: eq.settings, rate: eq.rate(key))
            .menuStyle(.button)
            .buttonStyle(EQCardRowStyle())
    }

    /// Tone (iEQ's group): Preset to the presets, the ten sliders - ten stepper rows at the accessibility sizes (3.15) -
    /// and Save as Preset… while the tone is Custom.
    @ViewBuilder
    private func toneCard(_ output: EQOutput, tone: EQTone) -> some View {
        let gains = eq.settings.gains(tone)
        let change = { (band: Int, gain: Double) -> Void in
            eq.setBand(band, to: gain, for: output)
        }
        PhoneGroup(legend: EQWords.Tone.header) {
            EQLink(route: .presets(output.key)) {
                PhoneGo {
                    Text(EQWords.Tone.preset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(EQWords.Tone.value(tone, in: eq.settings))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                    PhoneChevron()
                }
            }
            .buttonStyle(.plain)
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(gains.indices, id: \.self) { band in
                    EQStepperRow(band: band, gain: gains[band], onChange: change, onHold: hold)
                        .font(Typeface.Phone.text(.row))
                        .padding(.vertical, CGFloat(PhoneLook.groupEnds) * 3)
                        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                }
            } else {
                EQSliders(gains: gains, onChange: change, onHold: hold)
                    .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            }
            if Self.isCustom(tone) {
                Button(EQWords.Tone.saveAsPreset) { askSave(output) }
                    .buttonStyle(EQCardRowStyle())
            }
        }
        cardNote(EQWords.Tone.footer)
    }

    /// Preamp (3.8, Advanced), as the List's: Automatic as the purple switch - deadwax's preamp shown; off, yours, a
    /// stepper of 0.1 dB from -30 to +12 - and the lines under it.
    @ViewBuilder
    private func preampCard(_ output: EQOutput, setting: EQOutputSetting) -> some View {
        let drawing = eq.drawing(output.key)
        let hand = { () -> Double? in
            if case .hand(let dB) = setting.preamp { return dB }
            return nil
        }()
        PhoneGroup(legend: EQWords.Preamp.header) {
            Toggle(isOn: Binding<Bool>(get: { hand == nil }, set: { (now: Bool) -> Void in
                eq.setAutomaticPreamp(now, for: output)
            })) {
                Text(EQWords.Preamp.automatic)
                    .font(Typeface.Phone.text(.row))
                    .foregroundStyle(DWPalette.text)
            }
            .toggleStyle(.phoneSwitch)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            if let hand {
                Stepper(value: Binding<Double>(get: { hand }, set: { (now: Double) -> Void in
                    eq.setHandPreamp(now, for: output)
                }), in: -30...12, step: 0.1, onEditingChanged: { (down: Bool) -> Void in hold(down) }) {
                    HStack(spacing: CGFloat(PhoneLook.kvGap)) {
                        Text(EQWords.Preamp.row)
                            .foregroundStyle(DWPalette.kvLabel)
                        Spacer(minLength: 0)
                        Text(EQWords.Preamp.value(hand))
                            .font(Typeface.Phone.mono(.small))
                            .foregroundStyle(DWPalette.t2)
                    }
                    .font(Typeface.Phone.text(.row))
                }
                .accessibilityValue(EQWords.decibelsSaid(hand))
                .lookHeight(PhoneLook.kvRow)
                .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            } else {
                PhoneKV(label: EQWords.Preamp.row,
                        value: EQWords.Preamp.value(setting.on ? drawing.preamp : automaticPreamp(output, setting)))
            }
        }
        cardNote(hand == nil ? EQWords.Preamp.automaticFooter : EQWords.Preamp.handFooter)
        if let hand, setting.on, drawing.top + hand > 1e-9 {
            cardNote(EQWords.Screen.hand(hand, top: drawing.top), colour: DWPalette.amberText)
        }
    }

    /// Other outputs (3.12) as a group: each to its own page - Rename and Forget (never the speaker) on a long press,
    /// where the List's row is swiped, and VoiceOver's actions on the row; on the output's own page its ••• Rename… and
    /// Forget This Output.
    private func othersCard(_ key: String) -> some View {
        PhoneGroup(legend: EQWords.Outputs.others) {
            ForEach(EQScreenRules.others(eq.settings, shown: key, device: Platform.device), id: \.key) { other in
                EQLink(route: .output(other.key)) {
                    EQOtherOutputRow(output: other.output(Platform.device), short: EQWords.shortSetting(other, in: eq.settings),
                                     phone: true)
                }
                .buttonStyle(.plain)
                //? (R3b's review) the List's swipe, as a long press: the group isn't a List
                .contextMenu {
                    Button(EQWords.Outputs.rename, systemImage: "pencil") { askRename(other.key) }
                    if EQScreenRules.forgets(other.key) {
                        Button(EQWords.Outputs.forget, systemImage: "trash", role: .destructive) {
                            askForget(other.key, isPage: false)
                        }
                    }
                }
                .accessibilityActions {
                    if EQScreenRules.forgets(other.key) {
                        Button(EQWords.Outputs.forget) { askForget(other.key, isPage: false) }
                    }
                    Button(EQWords.Outputs.rename) { askRename(other.key) }
                }
            }
        }
    }

    /// A line under a group, or above and under the curve: the small words in the second colour (amber, danger's red,
    /// where the line says so), at the legend's side.
    private func cardNote(_ words: String, colour: Color = DWPalette.t2, above: CGFloat = 6) -> some View {
        Text(words)
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, above)
            .padding(.horizontal, CGFloat(PhoneLook.legendSide))
    }

    /// The line's colour on the phone: the second colour, the look's amber, danger's red.
    private static func cardColour(_ tone: EQLine.Tone) -> Color {
        switch tone {
        case .quiet: return DWPalette.t2
        case .amber: return DWPalette.amberText
        case .danger: return DWPalette.redChipText
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
                    .font(Typeface.footnote)
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
                        .font(Typeface.footnote.monospacedDigit())
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.leftOut {
                        Text(EQWords.Advanced.above)
                            .font(Typeface.footnote)
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

/// (R3b) A filter's row on the phone (Correction's group): its type at the row's 16 in white, its numbers in mono in
/// the second colour, the look's amber for one left out, 46 tall at least on the group's hairline; its switch the phone's
/// own (PhoneSwitchStyle, as every switch on the phone's pages - the knob the look's), "Filter 3 on" to VoiceOver. The
/// group isn't a List, so it has no swipe: a long press has Delete, as the List's swipe had; VoiceOver's actions Delete
/// and Turn Off (or On), as the Mac's row's. The Mac's row is EQFilterRowView, as it was.
struct EQPhoneFilterRow: View {
    let row: EQFilterRow
    let open: () -> Void
    let setOn: (Bool) -> Void
    let delete: () -> Void

    var body: some View {
        let f = row.filter
        HStack(spacing: CGFloat(PhoneLook.goGap)) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: CGFloat(PhoneLook.groupEnds)) {
                    Text(EQWords.Advanced.type(f.kind))
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.text)
                    Text(EQWords.Advanced.detail(f))
                        .font(Typeface.Phone.mono(.extraSmall))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.leftOut {
                        Text(EQWords.Advanced.above)
                            .font(Typeface.Phone.text(.extraSmall))
                            .foregroundStyle(DWPalette.amberText)
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
            Toggle(isOn: Binding<Bool>(get: { f.on }, set: setOn)) {
                EmptyView()
            }
            .toggleStyle(.phoneSwitch)
            .fixedSize()
            .accessibilityLabel(EQWords.Advanced.switchSaid(row.number))
        }
        .padding(.vertical, CGFloat(PhoneLook.groupEnds) * 3)
        .lookHeight(PhoneLook.goRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .contentShape(Rectangle())
        .contextMenu {
            Button(EQWords.Advanced.delete, systemImage: "trash", role: .destructive, action: delete)
        }
    }
}

/// (R3b) The •••'s face: in the sheet's top a small button of the look's (square, the glyph in the button's words), as
/// the Queue's top's buttons are; elsewhere the system's toolbar ellipsis, as before.
private struct EQMoreLook: ViewModifier {
    let inSheet: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if inSheet {
            content
                .menuStyle(.button)
                .buttonStyle(DWButtonStyle(size: .small))
                .menuIndicator(.hidden)
        } else {
            content
        }
    }
}

/// (R3b) A group's row that does something (Add Filter, Save as Preset…, Import from Files…, Export…): its words at the
/// row's 16 in white, 46 tall at least on the group's hairline, the card's colour under it while pressed, faded while it
/// can't be used.
private struct EQCardRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EQCardRowBody(configuration: configuration)
    }
}

private struct EQCardRowBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, CGFloat(PhoneLook.groupEnds) * 3)
            .lookHeight(PhoneLook.goRow)
            .background {
                if configuration.isPressed { DWPalette.card }
            }
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : DWPalette.off)
    }
}

/// (R3b) A button's words on the phone's EQ page (Not now, Forget This Output): one line, three at the accessibility
/// sizes, centred.
private struct EQButtonWords: View {
    let words: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
    }
}
