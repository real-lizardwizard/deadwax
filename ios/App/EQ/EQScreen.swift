import DeadwaxCore
import SwiftUI

/// The EQ page (eq.md 3.2, 3.3): one output's EQ, top to bottom - the output and its switch, the curve and the line
/// under it, the correction (the Correction row and AutoEq's suggestion, slice 4), the tone (Preset, the ten sliders,
/// Save as Preset…), Other outputs, and Forget This Output for one that isn't connected. An inset grouped List titled
/// "EQ", large when pushed from You, inline in the sheet; a toolbar ••• with "Rename…", and "Done" in the sheet.
///
/// Slice 5 adds its sections where 3.2 puts them - Preamp after Tone, Advanced after Other outputs, and the
/// correction's own rows in Correction - so nothing here stands in for them.
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

    @State private var page: EQPage?
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

    /// On top: shown, with nothing pushed or presented over it - and, on You's stack, Now Playing not over it.
    private var onTop: Bool {
        appeared && ask == nil && forgetting == nil && !(done == nil && navigation.nowPlayingShown)
    }

    var body: some View {
        let page = current
        let key = page.output
        let output = eq.output(key)
        let setting = eq.setting(output)
        let connected = key == eq.route.key
        List {
            outputSection(output, on: setting.on, connected: connected)
            curveSection(key, name: output.name, connected: connected, held: page.held > 0)
            correctionSection(output, setting: setting)
            toneSection(output, tone: setting.tone)
            if EQScreenRules.showsOthers(page) {
                othersSection(key)
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
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .onChange(of: onTop, initial: true) { _, top in
            if top { show() } else { self.page?.covered() }
        }
        .onChange(of: eq.route.key) { _, route in
            if self.page?.heard(route: route) == true { switched() }
        }
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
    /// when its unit couldn't be made. Not connected, "Not connected: this is what it plays when it is." above it.
    private func curveSection(_ key: String, name: String, connected: Bool, held: Bool) -> some View {
        let line = eq.line(key)
        return Section {
            EQCurveView(drawing: eq.drawing(key), name: name, animated: !held)
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

    /// 3. Correction (3.2, 3.7): the Correction row - its value None or the correction's name, where it's from under
    /// the label - pushing the picker; and, when it applies, AutoEq's suggestion: one headphone's profile, or the
    /// picker searched for the output's name. Swipe (or VoiceOver's action) for Not now, which puts it away for good.
    private func correctionSection(_ output: EQOutput, setting: EQOutputSetting) -> some View {
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
        } header: {
            Text(EQWords.Correction.header)
        } footer: {
            Text(EQWords.Correction.footer(output))
        }
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
