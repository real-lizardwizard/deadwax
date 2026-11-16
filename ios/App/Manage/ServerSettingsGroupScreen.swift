import DeadwaxCore
import SwiftUI

/// A group of Server settings, its own page (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; the web's
/// ServerGroup and SettingRow, components/SettingsView.tsx): the group's note, then a section per setting - its name, the
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
struct ServerSettingsGroupScreen: View {
    let id: String

    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parts = settings.parts
        Group {
            if !parts.page {
                ContentUnavailableView {
                    Label(title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if settings.flow.answer != nil {
                if let group = settings.flow.group(id) {
                    form(group, parts)
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

    @ViewBuilder private func form(_ group: ServerSettingGroup, _ parts: ServerSettings.Parts) -> some View {
        Form {
            if !group.note.isEmpty {
                Section {
                    Text(group.note)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if group.id == ServerSettings.connectionsGroup && parts.connections {
                ConnectionsSection()
            }
            ServerSettingsRereadFailure()
            ForEach(group.settings) { (setting: ServerSetting) in
                SettingSection(setting: setting)
            }
            if group.id == ServerSettings.lyricsGroup {
                RetimeSection()
            }
            if group.id == ServerSettings.savedAnswersGroup && parts.answers {
                SavedAnswersSection()
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
    }
}

/// One setting (SettingRow): its name over the control and Revert, its words under them.
private struct SettingSection: View {
    let setting: ServerSetting

    @Environment(ServerSettingsModel.self) private var settings

    var body: some View {
        let row = settings.flow.row(setting)
        Section {
            control(row)
            if let revert = row.revert {
                Button(revert) {
                    settings.revert(setting.key)
                }
            }
        } header: {
            Text(setting.key)
                .font(Typeface.mono(.footnote))
                .textCase(nil)
                .textSelection(.enabled)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let marks = Self.marks(row) {
                    marks
                }
                if !row.effect.isEmpty {
                    Text(row.effect)
                }
                if let locked = row.locked {
                    Text(locked)
                }
                if row.reverting {
                    Text(ServerSettings.willRevert)
                }
                if let note = row.note {
                    Text(note)
                        .foregroundStyle(Palette.amber)
                }
                if let detail = row.detail {
                    Text(detail)
                        .foregroundStyle(Palette.danger)
                }
            }
            .font(Typeface.footnote)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where the value came from, and the row's badges: "Set here · Unsaved", "From .env · Needs attention" - a badge
    /// in its colour and bold, as the web's.
    private static func marks(_ row: ServerSettings.Row) -> Text? {
        var parts: [AttributedString] = []
        if let source = row.source { parts.append(AttributedString(source)) }
        if row.unsaved { parts.append(badge(ServerSettings.unsavedBadge, Palette.accent)) }
        if row.attention { parts.append(badge(ServerSettings.needsAttention, Palette.amber)) }
        guard var said = parts.first else { return nil }
        for part in parts.dropFirst() {
            said += AttributedString(" · ") + part
        }
        return Text(said)
    }

    private static func badge(_ words: String, _ colour: Color) -> AttributedString {
        var badge = AttributedString(words)
        badge.foregroundColor = colour
        badge.inlinePresentationIntent = .stronglyEmphasized
        return badge
    }

    @ViewBuilder private func control(_ row: ServerSettings.Row) -> some View {
        let value = Binding(
            get: { settings.flow.row(setting).value },
            set: { (typed: String) -> Void in settings.edit(setting.key, typed) }
        )
        switch row.control {
        case .locked:
            Text(ServerSettings.locked)
                .foregroundStyle(Palette.quiet)
                .accessibilityLabel("\(setting.key), \(ServerSettings.locked)")
        case .choices:
            Picker(selection: value) {
                ForEach(ServerSettings.pickerChoices(setting, value: row.value)) { (choice: ServerSettings.Choice) in
                    Text(choice.label).tag(choice.value)
                }
            } label: {
                Text(setting.key)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(setting.key)
        case .field(let secret):
            Group {
                if secret {
                    SecureField(setting.key, text: value, prompt: Text(row.placeholder))
                } else {
                    TextField(setting.key, text: value, prompt: Text(row.placeholder))
                        .keyboardType(ServerSettings.isAddress(setting.key) ? .URL : .default)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .accessibilityLabel(setting.key)
        }
    }
}

/// Re-time saved lyrics (RetimeLyrics.tsx), beside the lead: Start, refused while the lead has a draft; while it runs,
/// "Re-timing 4 of 60 albums · Stop after this album" - pressing it stops it after the album out - and that the screen
/// stays on; under it, the web's note: the prompt, "Save the new lead first.", or how the last run ended (and, the phone's
/// own, why it stopped short). It needs Edit albums too, the permission of the route it asks for each album.
private struct RetimeSection: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let run = settings.retime
        let unsaved = settings.leadUnsaved
        Section {
            if run.running {
                Button {
                    settings.stopRetime()
                } label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .accessibilityHidden(true)
                        Text(run.runningLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(run.stopping)
                Text(RetimeRun.screenOnNote)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(RetimeRun.button) {
                    settings.startRetime()
                }
                .disabled(!settings.retimeOpen(online: reachability.online))
            }
            Text(run.note(unsaved: unsaved))
                .font(Typeface.footnote)
                .foregroundStyle(run.phase == .ended && run.error != nil ? Palette.danger : Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if !settings.parts.retime {
                Text(ServerSettings.retimeNeedsEdit)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(RetimeRun.button)
                .font(Typeface.footnote)
        } footer: {
            Text(unsaved ? RetimeRun.saveFirstHint : RetimeRun.hint)
                .font(Typeface.footnote)
        }
    }
}

/// MusicBrainz's saved answers (MusicBrainzAnswers.tsx), under their two settings: what the file holds, and Clear -
/// asked first, the phone's own (the web clears at once) - refused while the path is a draft, with nothing to clear, while
/// it goes and out of reach.
private struct SavedAnswersSection: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @State private var asking = false

    var body: some View {
        let answers = settings.answers
        let unsaved = settings.pathUnsaved
        Section {
            Text(answers.line(unsaved: unsaved))
                .font(Typeface.footnote)
                .foregroundStyle(answers.error != nil && !unsaved ? Palette.danger : Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) {
                asking = true
            } label: {
                HStack(spacing: 8) {
                    Text(answers.label)
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
            } message: {
                Text(SavedAnswers.clearHint)
            }
        } footer: {
            Text(answers.hint(unsaved: unsaved))
                .font(Typeface.footnote)
        }
    }
}

/// Set up Navidrome (the Library's gate, phase8-managing.md 7): Server settings' Connections group page in a sheet over
/// the Library - with Connections' rows, and the save bar once something is typed. Saved, the Library asks Navidrome
/// again (ServerSettingsModel.saved), and the gate opening takes the sheet with it. Close at the leading edge; while a save
/// is out, neither Close nor a swipe closes it. The drafts are the app's, so closing it loses nothing typed: they wait on
/// Server settings' pages.
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
                    }
                }
        }
        .interactiveDismissDisabled(settings.flow.saving)
    }
}
