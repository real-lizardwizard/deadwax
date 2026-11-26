import DeadwaxCore
import SwiftUI

/// A group of Server settings, its own page (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; the web's
/// ServerGroup and SettingRow, components/SettingsView.tsx): the group's note, then a card per setting - its name, the
/// control (a menu where it takes certain values, a secure field for a secret - "•••••••• (set)" its placeholder, never
/// its value - a field otherwise, with no autocorrection or capitals and the URL keyboard for an address, "Locked" where
/// it can't be changed here), Revert to the environment (and what that brings back) where it was set here, and under it
/// where the value came from, Unsaved or Needs attention, what it does, why it's locked, what another row's edit asks of
/// it, and what is wrong. Lyrics carries Re-time saved lyrics; MusicBrainz's saved answers carries the file's size and
/// Clear, asked first. The Connections group's page draws Connections' rows too - it is the page Set up Navidrome opens
/// over the Library (SetUpNavidromeSheet), so a save there shows whether Navidrome answers now.
///
/// Typing makes a draft in the app's model (ServerSettingsModel) - kept going back and forth between groups, saved with
/// the others by one Save at any page's foot. The fields stay editable while a save is out, as the web's.
///
/// (The redesign, slice R14 - notes/ios.md "The redesign, slice R14: People and Server settings") Flat, as
/// iServerSettings draws a setting: no Form - the page's black with each setting a card on its hairline (`.group.pad`):
/// its name in the readout face, its field a box (the look's well: anywhere you type is a box), its chips - where the
/// value came from (purple when set here), Unsaved, Needs attention - with Revert, then its words. The Mac draws this
/// page only in Set up Navidrome's sheet (its Server settings is MacServerSettingsPage), at its own sizes: every piece
/// here is the look's (DWLook's field, DWButtonStyle, DWChip), none of the phone's rows.
struct ServerSettingsGroupScreen: View {
    let id: String

    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parts = settings.parts
        // a ZStack, not a Group: the page's frame (its shows and hides) stays on one view as the spinner gives way to
        // the cards (as ServerSettingsScreen's)
        ZStack {
            if !parts.page {
                ContentUnavailableView {
                    Label(title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if settings.flow.answer != nil {
                if let group = settings.flow.group(id) {
                    cards(group, parts)
                } else {
                    ContentUnavailableView {
                        Label(title, systemImage: "questionmark.folder")
                    } description: {
                        Text(ServerSettings.groupGone)
                    }
                }
            } else if !reachability.online {
                ContentUnavailableView {
                    Label(title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                ServerSettingsFirstRead()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .serverSettingsPage(.group(id))
    }

    /// The group's name as deadwax gives it - before the settings are read, Connections' (Set up Navidrome's page) or
    /// the page's.
    private var title: String {
        if let group = settings.flow.group(id), !group.label.isEmpty { return group.label }
        return id == ServerSettings.connectionsGroup ? Connections.title : ServerSettings.title
    }

    private func cards(_ group: ServerSettingGroup, _ parts: ServerSettings.Parts) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !group.note.isEmpty {
                    ManageNote(words: group.note)
                }
                if group.id == ServerSettings.connectionsGroup && parts.connections {
                    ConnectionsSection()
                }
                ServerSettingsRereadFailure()
                ForEach(group.settings) { (setting: ServerSetting) in
                    SettingCard(setting: setting)
                }
                if group.id == ServerSettings.lyricsGroup {
                    RetimePart()
                        .padding(.top, ManageLook.cardAbove)
                }
                if group.id == ServerSettings.savedAnswersGroup && parts.answers {
                    SavedAnswersPart()
                        .padding(.top, ManageLook.cardAbove)
                }
            }
            .padding(.horizontal, ManageLook.side)
            .padding(.bottom, ManageLook.cardAbove)
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
    }
}

// MARK: - a setting (iServerSettings' `.group.pad`)

/// One setting (SettingRow), a card on the page's black (iServerSettings' `.group.pad`, 26 above, its parts 8 apart): its
/// name in the readout face over the control, the chips with Revert at their end, then its words - and the hairline under
/// it. VoiceOver reads the name once, from the control (each control carries it); the chips and the words are read
/// after it, as one.
struct SettingCard: View {
    let setting: ServerSetting

    @Environment(ServerSettingsModel.self) private var settings

    var body: some View {
        let row = settings.flow.row(setting)
        VStack(alignment: .leading, spacing: ManageLook.cardGap) {
            // .legend.mono: the name is said once, by the control it labels - VoiceOver skips it here
            Text(setting.key)
                .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                .foregroundStyle(DWPalette.t2)
                .textSelection(.enabled)
                .accessibilityHidden(true)
            SettingControl(setting: setting, row: row)
            SettingChips(row: row) {
                SettingRevert(setting: setting, row: row)
            }
            SettingWords(row: row)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ManageLook.cardAbove)
        .padding(.bottom, ManageLook.cardFoot)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }
}

/// A setting's control (SettingRow's), the same on both devices' pages: "Locked" where it can't be changed here; a menu
/// of the values it takes; a field - a secure one for a secret, its placeholder "•••••••• (set)" never its value - in
/// the readout face (`.in.mono`), with no capitals or autocorrection and the URL keyboard for an address. Every field is
/// a box: the look's well (SettingWell). Typing drafts it in the app's model; Return only puts the keyboard away.
struct SettingControl: View {
    let setting: ServerSetting
    let row: ServerSettings.Row

    @Environment(ServerSettingsModel.self) private var settings
    @FocusState private var focused: Bool

    var body: some View {
        let value = Binding(
            get: { settings.flow.row(setting).value },
            set: { (typed: String) -> Void in settings.edit(setting.key, typed) }
        )
        // the purple edge (`selbd`) while it is set here and nothing is drafted - the drawing's overridden field
        let setHere = row.source == ServerSettings.setHere
        switch row.control {
        case .locked:
            Text(ServerSettings.locked)
                .font(Typeface.Look.text(.field))
                .foregroundStyle(DWPalette.t2)
                .accessibilityLabel("\(setting.key), \(ServerSettings.locked)")
        case .choices:
            let choices = ServerSettings.pickerChoices(setting, value: row.value)
            if Platform.mac {
                Picker(selection: value) {
                    ForEach(choices) { (choice: ServerSettings.Choice) in
                        Text(choice.label).tag(choice.value)
                    }
                } label: {
                    Text(setting.key)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(DWPalette.acc)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(setting.key)
            } else {
                // (R14's review) the phone's: a menu whose label is the whole row, 44 tall - out of a Form's row a menu
                // Picker takes a tap on its own words alone. The choices are the Picker's, inline in the menu, the one
                // chosen ticked; the row says it in the accent with the look's caret.
                Menu {
                    Picker(selection: value) {
                        ForEach(choices) { (choice: ServerSettings.Choice) in
                            Text(choice.label).tag(choice.value)
                        }
                    } label: {
                        Text(setting.key)
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 6) {
                        Text(Self.chosen(choices, value: row.value))
                            .font(Typeface.Look.text(.field))
                            .foregroundStyle(DWPalette.acc)
                            .multilineTextAlignment(.leading)
                        DWCaret(colour: DWPalette.acc)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: CGFloat(DWLook.here.target), alignment: .leading)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(setting.key)
                .accessibilityValue(Self.chosen(choices, value: row.value))
            }
        case .field(let secret):
            if secret {
                SecureField(setting.key, text: value, prompt: Text(row.placeholder))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .accessibilityLabel(setting.key)
                    .modifier(SettingWell(focus: $focused, setHere: setHere))
            } else {
                TextField(setting.key, text: value, prompt: Text(row.placeholder))
                    .keyboardType(ServerSettings.isAddress(setting.key) ? .URL : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .accessibilityLabel(setting.key)
                    .modifier(SettingWell(focus: $focused, setHere: setHere))
            }
        }
    }

    /// The choice the row holds, in its words (pickerChoices always holds the value, "Not set" for none).
    static func chosen(_ choices: [ServerSettings.Choice], value: String) -> String {
        choices.first { (choice: ServerSettings.Choice) -> Bool in choice.value == value }?.label ?? value
    }
}

/// A setting's field in its box (dw.css's `.in.mono` on its `.well`), on both devices: the plain field in the readout
/// face at the field's size (16 on the phone, so iOS never zooms to it; the Mac's 13), the system's focus ring off,
/// padded 8 either side, the field's height (36 at least on the phone, the Mac's 24) - on the look's well, its edge the
/// accent's while it has the cursor and, while the setting is set here, `selbd` (the drawing's overridden edge). A tap
/// on the well, or a finger's 44 round it, puts the cursor in it.
struct SettingWell: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let setHere: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Typeface.Look.mono(.field))
            .foregroundStyle(DWPalette.fieldText)
            .focusEffectDisabled()
            // .in: padding 0 8px
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background {
                DWWell(focused: focus.wrappedValue)
                    .contentShape(DWTarget(face: DWCorners.buttonShape))
                    .onTapGesture {
                        focus.wrappedValue = true
                    }
            }
            .overlay {
                if setHere && !focus.wrappedValue {
                    DWCorners.buttonShape
                        .strokeBorder(DWPalette.selbd, lineWidth: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// A setting's chips (`.chip`, `.chip.purple`, `.chip.amber`): where the value came from - "Set here" in the accent's
/// purple, "From the container environment" plain - then Unsaved (purple) and Needs attention (amber), with what the
/// page puts at their end (Revert). On one line while it fits; else - the largest sizes, a long revert - the end under
/// the chips; and where even the chips don't fit one line ("From the container environment", Unsaved and Needs attention
/// in a column of the Mac's or at the phone's largest sizes), each chip on a line of its own. VoiceOver reads the chips
/// as one element.
struct SettingChips<End: View>: View {
    let row: ServerSettings.Row
    @ViewBuilder let end: End

    var body: some View {
        // (R14's review) the end under the chips is the last way, so it is laid out in the width it's given - a long
        // Revert wraps there (ManageWrapButton) - and the chips choose their own line or lines over it
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: ManageLook.chipGap) {
                chips(stacked: false)
                Spacer(minLength: 0)
                end
            }
            VStack(alignment: .leading, spacing: ManageLook.chipGap) {
                ViewThatFits(in: .horizontal) {
                    chips(stacked: false)
                    chips(stacked: true)
                }
                end
            }
        }
    }

    @ViewBuilder private func chips(stacked: Bool) -> some View {
        let shown = Self.chips(row)
        if !shown.isEmpty {
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ManageLook.chipGap))
                : AnyLayout(HStackLayout(spacing: ManageLook.chipGap))
            layout {
                ForEach(shown, id: \.words) { (chip: SettingChip) in
                    DWChip(words: chip.words, tone: chip.tone)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.map(\.words).joined(separator: ", "))
        }
    }

    /// The chips a row has, in order: its source, Unsaved, Needs attention.
    static func chips(_ row: ServerSettings.Row) -> [SettingChip] {
        var chips: [SettingChip] = []
        if let source = row.source {
            chips.append(SettingChip(words: source, tone: source == ServerSettings.setHere ? .marked : .plain))
        }
        if row.unsaved { chips.append(SettingChip(words: ServerSettings.unsavedBadge, tone: .marked)) }
        if row.attention { chips.append(SettingChip(words: ServerSettings.needsAttention, tone: .caution)) }
        return chips
    }
}

/// One of a setting's chips: its words, and what they mean.
struct SettingChip {
    let words: String
    let tone: DWChip.Tone
}

/// Revert to the environment (and what that brings back), where the setting was set here and no revert is drafted: it
/// drafts the revert - sent as `null` with the others by Save (Core's SettingUpdate), never a key left out. (R14's
/// review) A ManageWrapButton: one line as drawn while it fits; else across the card, its words wrapping on the phone
/// ("Revert to the environment (http://navidrome:4533)" is some 337 points at the default size), cut on one line in the
/// Mac's box - the whole in its help.
struct SettingRevert: View {
    let setting: ServerSetting
    let row: ServerSettings.Row

    @Environment(ServerSettingsModel.self) private var settings

    var body: some View {
        if let revert = row.revert {
            ManageWrapButton(size: .small, words: revert, action: {
                settings.revert(setting.key)
            }) { (across: Bool) in
                ManageButtonWords(words: revert, across: across)
            }
        }
    }
}

/// (R14's review) A button whose words never run off its row. DWButtonStyle holds a button that doesn't fill to its
/// words' width on one line - a line limit on its words can't wrap it - so: as drawn while that fits the width; else
/// across the width (`fills`), its words wrapping on the phone, cut on one line on the Mac, where a button is 26 tall -
/// the whole in its help. `label(across)` draws the words for either.
struct ManageWrapButton<Label: View>: View {
    var kind: DWButtonStyle.Kind = .normal
    var size: DWButtonStyle.Size = .standard
    /// The whole words, for the help.
    let words: String
    let action: () -> Void
    @ViewBuilder let label: (_ across: Bool) -> Label

    var body: some View {
        ViewThatFits(in: .horizontal) {
            button(across: false)
            button(across: true)
        }
        .help(words)
    }

    private func button(across: Bool) -> some View {
        Button(action: action) {
            label(across)
        }
        .buttonStyle(DWButtonStyle(kind: kind, size: size, fills: across))
    }
}

/// (R14's review) A ManageWrapButton's words: one line as drawn; across the width, on the phone as many lines as they
/// take, centred - the innermost line limit is the one that holds, so the style's one line round the label never cuts
/// them - and on the Mac one line, cut at its end.
struct ManageButtonWords: View {
    let words: String
    let across: Bool

    var body: some View {
        Text(words)
            .lineLimit(across && !Platform.mac ? nil : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: across && !Platform.mac)
    }
}

/// A setting's words under it (SettingRow's footer): what it does, why it's locked, that a revert is drafted, what
/// another row's edit asks of it (amber) and what is wrong (red) - in the small size (`font`: the page's), wrapping.
struct SettingWords: View {
    let row: ServerSettings.Row
    var font: Font = ManageLook.small

    var body: some View {
        VStack(alignment: .leading, spacing: ManageLook.wordsGap) {
            if !row.effect.isEmpty {
                Text(row.effect)
                    .foregroundStyle(DWPalette.t2)
            }
            if let locked = row.locked {
                Text(locked)
                    .foregroundStyle(DWPalette.t2)
            }
            if row.reverting {
                Text(ServerSettings.willRevert)
                    .foregroundStyle(DWPalette.acct)
            }
            if let note = row.note {
                Text(note)
                    .foregroundStyle(DWPalette.amberText)
            }
            if let detail = row.detail {
                Text(detail)
                    .foregroundStyle(DWPalette.redChipText)
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Re-time and the saved answers

/// Re-time saved lyrics (RetimeLyrics.tsx), beside the lead: Start, refused while the lead has a draft; while it runs,
/// "Re-timing 4 of 60 albums · Stop after this album" - pressing it stops it after the album out - and that the screen
/// stays on; under it, the web's note: the prompt, "Save the new lead first.", or how the last run ended (and, the phone's
/// own, why it stopped short). It needs Edit albums too, the permission of the route it asks for each album. (R14) Flat:
/// its heading, its button (the look's), its words - on both devices' pages, in the page's small size (`font`).
struct RetimePart: View {
    var font: Font = ManageLook.small
    /// Whether it draws its own heading - the Mac's box has its legend.
    var heading = true

    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let run = settings.retime
        let unsaved = settings.leadUnsaved
        VStack(alignment: .leading, spacing: ManageLook.cardGap) {
            if heading {
                ManageHeading(words: RetimeRun.button)
            }
            if run.running {
                // (R14's review) "Re-timing 4 of 60 albums · Stop after this album" is some 354 points at the default
                // size: across the card, wrapping, where it doesn't fit
                ManageWrapButton(words: run.runningLabel, action: {
                    settings.stopRetime()
                }) { (across: Bool) in
                    HStack(spacing: 8) {
                        ProgressView()
                            .accessibilityHidden(true)
                        ManageButtonWords(words: run.runningLabel, across: across)
                    }
                }
                .disabled(run.stopping)
                Text(RetimeRun.screenOnNote)
                    .foregroundStyle(DWPalette.t2)
                // (the Mac app, slice 7) what ⌘Q does to it; none on the iPhone
                if let quit = RetimeRun.quitNote(Platform.device) {
                    Text(quit)
                        .foregroundStyle(DWPalette.t2)
                }
            } else {
                ManageWrapButton(words: RetimeRun.button, action: {
                    settings.startRetime()
                }) { (across: Bool) in
                    ManageButtonWords(words: RetimeRun.button, across: across)
                }
                .disabled(!settings.retimeOpen(online: reachability.online))
            }
            Text(run.note(unsaved: unsaved))
                .foregroundStyle(run.phase == .ended && run.error != nil ? DWPalette.redChipText : DWPalette.t2)
            if !settings.parts.retime {
                Text(ServerSettings.retimeNeedsEdit)
                    .foregroundStyle(DWPalette.t2)
            }
            Text(unsaved ? RetimeRun.saveFirstHint : RetimeRun.hint)
                .foregroundStyle(DWPalette.t3)
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// MusicBrainz's saved answers (MusicBrainzAnswers.tsx), under their two settings: what the file holds, and Clear -
/// asked first, the phone's own (the web clears at once) - refused while the path is a draft, with nothing to clear, while
/// it goes and out of reach. (R14) Flat, Clear the look's red button: it can't be undone.
struct SavedAnswersPart: View {
    var font: Font = ManageLook.small

    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @State private var asking = false

    var body: some View {
        let answers = settings.answers
        let unsaved = settings.pathUnsaved
        VStack(alignment: .leading, spacing: ManageLook.cardGap) {
            Text(answers.line(unsaved: unsaved))
                .foregroundStyle(answers.error != nil && !unsaved ? DWPalette.redChipText : DWPalette.t2)
            // (R14's review) "Clear MusicBrainz's saved answers" is some 373 points at xxxLarge: across the card,
            // wrapping, where it doesn't fit
            ManageWrapButton(kind: .danger, words: answers.label, action: {
                asking = true
            }) { (across: Bool) in
                HStack(spacing: 8) {
                    ManageButtonWords(words: answers.label, across: across)
                    if answers.clearing {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
            }
            .disabled(answers.refused(unsaved: unsaved, online: reachability.online))
            .confirmationDialog(SavedAnswers.clearQuestion, isPresented: $asking, titleVisibility: .visible) {
                Button(SavedAnswers.clearConfirm, role: .destructive) {
                    settings.clearAnswers()
                }
                Button(SavedAnswers.cancel, role: .cancel) {}
                    .returnCancels()
            } message: {
                Text(SavedAnswers.clearHint)
            }
            Text(answers.hint(unsaved: unsaved))
                .foregroundStyle(DWPalette.t3)
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Server settings' and People's own (R14)

/// (R14) A part's heading on the flat pages, both devices' (`.group > .legend`): 13 semibold in the second colour, a
/// header for VoiceOver - PhoneGroup's legend, without PhoneGroup's frame, so the Mac's sheet draws it at its own size.
struct ManageHeading: View {
    let words: String

    var body: some View {
        Text(words)
            .font(ManageLook.small.weight(.semibold))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// (R14) A note on the flat pages: the small size, the second colour unless said, wrapping - room above it.
struct ManageNote: View {
    let words: String
    var colour: Color = DWPalette.t2

    var body: some View {
        Text(words)
            .font(ManageLook.small)
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ManageLook.noteAbove)
    }
}

/// (R14) Server settings' and People's measures on the flat pages, from iServerSettings and iPerson: the page's sides
/// (`padding: 0 16px`), a setting card's room above (`.group` margin-top 26) and under it, its parts' gap (`.group.pad`
/// gap 8), the chips' (`.f` gap 6), the words' under it, and a note's room above (R9's 6) - and iPerson's head: its
/// mark (60), the gap beside it (12) and its room under the bar (8) - and the small size (`.s`: 13 at the standard size
/// on the phone, scaled; on the Mac its fixed 12 - through the look's small button, which is the Mac's .s, since App/Manage
/// names no Mac type), in words and in the readout face. The group page and the sheets are drawn on the Mac too (Set up
/// Navidrome, macSheet), so neither is the phone's size there.
enum ManageLook {
    static let side: CGFloat = 16
    static let cardAbove: CGFloat = 26
    static let cardFoot: CGFloat = 14
    static let cardGap: CGFloat = 8
    static let chipGap: CGFloat = 6
    static let wordsGap: CGFloat = 4
    static let noteAbove: CGFloat = 6
    static let headMark: CGFloat = 60
    static let headGap: CGFloat = 12
    static let headAbove: CGFloat = 8
    static var small: Font { Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small) }
    /// People's sheets' ground (PeopleSheetPage) and Set up Navidrome's: the phone's page black, the Mac's window ground.
    static var sheetGround: Color { Platform.mac ? DWPalette.bg : DWPalette.page }
}

/// Set up Navidrome (the Library's gate, phase8-managing.md 7): Server settings' Connections group page in a sheet over
/// the Library - with Connections' rows, and the save bar once something is typed. Saved, the Library asks Navidrome
/// again (ServerSettingsModel.saved), and LibraryView puts the sheet away once Navidrome answers - never because deadwax
/// went out of reach, nor during a save. Close at the leading edge; while a save is out, neither Close nor a swipe closes
/// it. The drafts are the app's, so closing it loses nothing typed: they wait on Server settings' pages. (R14's review)
/// On the page's black on the phone, as People's sheets are - no sheet's grey under the flat group page - and the Mac's
/// own ground in its window (ManageLook.sheetGround).
struct SetUpNavidromeSheet: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ServerSettingsGroupScreen(id: ServerSettings.connectionsGroup)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(EditWords.close) {
                            dismiss()
                        }
                        .disabled(settings.flow.saving)
                        .escapeCloses()
                    }
                }
        }
        .interactiveDismissDisabled(settings.flow.saving)
        .presentationBackground(ManageLook.sheetGround)
    }
}
