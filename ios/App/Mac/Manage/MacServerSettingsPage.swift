import DeadwaxCore
import SwiftUI

/// Server settings on the Mac (the redesign, slice R14 - ServerSettings.dc.html; notes/ios.md "The redesign, slice R14:
/// People and Server settings"): the phone's pages as one, every setting a box.
///
/// - The toolbar: the page's line, cut to fit with the whole in its help.
/// - The web's three tabs as folder tabs (Library | Downloads | Connections), each tab's mark in its words - "Library ·
///   Needs attention" - so a tab not shown says it too; opened at a group's tab when the route names a group.
/// - Under them the chosen tab: Library opens with the organizing verdict, Connections with Connections' rows and Check
///   again; then each of its groups - its name and mark, its note - and a box per setting, two columns where they fit
///   (`twoColumns`), else one: the setting's name as the box's legend in the readout face, its control (the phone's own,
///   SettingControl: a menu, a secure field, a field, Locked), its chips with Revert to the environment at their end,
///   its words. Lyrics' group ends with Re-time saved lyrics' box, MusicBrainz's saved answers with its own.
/// - Every edit is a draft in the app's model, as on the phone: one Save in the save bar at the page's foot sends them
///   all (Revert drafted as `null`, never a key left out - Core's SettingUpdate), and File > Save changes (⌘S) is that
///   Save while the page is in front - the page framed as the phone's root is (`serverSettingsPage(.root)`).
/// - Re-time's and the saved answers' groups are told to the model as their pages are on the phone (shows and hides of
///   `.group`) while their tab is shown: the saved answers read, Re-time's screen kept awake, as there.
/// - The status bar: how many settings there are, how many are set here, and deadwax's version.
///
/// The drawing's per-setting Save and Revert every override aren't drawn: one Save sends every draft (the model's one
/// way), and no revert-them-all exists today.
struct MacServerSettingsPage: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @State private var tab: ServerSettings.Tab

    init(tab: ServerSettings.Tab = .library) {
        _tab = State(initialValue: tab)
    }

    /// The page wide enough for two columns of boxes (ServerSettings.dc.html's grid: 18 apart, inside the page's 22 either
    /// side). (R14's review) Each column holds on one line, inside its box's 12 either side, the widest chips that can
    /// show together with Revert: "From the container environment" and Unsaved - a setting set here, then typed in -
    /// beside "Revert to the environment", some 437 points (Set here never shows with Unsaved, nor Revert with Needs
    /// attention but beside Set here, 347). So 2 × (437 + 24) + 18 + 44 = 984, made 990. Two at the window's opening (a
    /// page of 1060, columns of 499); one at the smallest window (660) and beside the side panel (659). What Revert
    /// brings back, after its words, is the box's to fold: under the chips, cut, the whole in its help.
    static let twoColumns: CGFloat = 990
    /// The page's sides and the columns' gap (the grid's padding 28px 22px, gap 26px 18px).
    static let pageSide: CGFloat = 22
    static let columnGap: CGFloat = 18

    var body: some View {
        let parts = settings.parts
        MacPage {
            Text(ServerSettings.pageLine)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(ServerSettings.pageLine)
            Spacer(minLength: 8)
        } content: {
            // a ZStack, as the phone's pages: the frame's shows and hides stay on one view as the spinner gives way
            ZStack {
                if !parts.page {
                    ContentUnavailableView {
                        Label(ServerSettings.title, systemImage: "lock")
                    } description: {
                        Text(EditWords.noPermission)
                    }
                } else if let answer = settings.flow.answer {
                    page(answer, parts)
                } else if !reachability.online {
                    ContentUnavailableView {
                        Label(ServerSettings.title, systemImage: "wifi.slash")
                    } description: {
                        Text(EditWords.needsDeadwax)
                    }
                } else {
                    ServerSettingsFirstRead()
                }
            }
        }
        .macStatus(MacStatusItems.Items(leading: Self.status(settings.flow.answer),
                                        trailing: Self.version(settings.flow.answer)))
        .serverSettingsPage(.root)
    }

    @ViewBuilder private func page(_ answer: ServerSettingsAnswer, _ parts: ServerSettings.Parts) -> some View {
        let sections = ServerSettings.sections(answer)
        let tabs = sections.map(\.tab)
        let marks = settings.flow.tabMarks
        // a tab the answer no longer has: its first
        let shown = tabs.contains(tab) ? tab : tabs.first ?? tab
        VStack(spacing: 0) {
            if !tabs.isEmpty {
                MacFolderTabs(tabs: tabs,
                              words: { (each: ServerSettings.Tab) -> String in ServerSettingsScreen.words(each, marks[each]) },
                              chosen: Binding(get: { shown }, set: { (chosen: ServerSettings.Tab) -> Void in tab = chosen }),
                              spoken: ServerSettings.title, ground: DWPalette.bg)
            }
            GeometryReader { (room: GeometryProxy) in
                let columns = room.size.width >= Self.twoColumns ? 2 : 1
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ServerSettingsRereadFailure(font: Typeface.Mac.text(.small))
                        if shown == .library {
                            OrganizingVerdictView(organizing: answer.organizing, font: Typeface.Mac.text(.small))
                        }
                        if shown == .connections && parts.connections {
                            connections
                        }
                        ForEach(sections.first { $0.tab == shown }?.groups ?? []) { (group: ServerSettingGroup) in
                            MacSettingsGroup(group: group, columns: columns, parts: parts,
                                             mark: settings.flow.groupMarks[group.id])
                        }
                    }
                    .padding(EdgeInsets(top: 28, leading: Self.pageSide, bottom: Self.pageSide, trailing: Self.pageSide))
                }
            }
        }
    }

    /// Connections' box: each service's row, and Check again.
    private var connections: some View {
        MacGroupBox(legend: Connections.title, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Connections.Service.allCases, id: \.self) { (service: Connections.Service) in
                    ConnectionRow(service: service, check: settings.checks.check(service),
                                  font: Typeface.Mac.text(.small))
                }
                Button(Connections.checkAgain) {
                    settings.checkConnections()
                }
                .buttonStyle(DWButtonStyle())
                .disabled(!settings.checks.againOpen(online: reachability.online))
                .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }

    // MARK: the status bar

    /// "19 settings", "1 set here".
    static func status(_ answer: ServerSettingsAnswer?) -> [String] {
        guard let answer else { return [] }
        let all = answer.groups.flatMap(\.settings)
        let here = all.filter { (setting: ServerSetting) -> Bool in setting.overridden }.count
        return [MacManageCount.words(all.count, one: "setting", many: "settings"),
                "\(here) \(ServerSettings.setHere.lowercased())"]
    }

    /// "deadwax 2.1.40", as the server says it.
    static func version(_ answer: ServerSettingsAnswer?) -> [String] {
        guard let version = answer?.version, !version.isEmpty else { return [] }
        return ["deadwax \(version)"]
    }
}

/// One group of the tab shown: its name (a heading) and its mark, its note, its settings' boxes in `columns` - and Re-time
/// saved lyrics' box under Lyrics, the saved answers' under theirs. Re-time's and the saved answers' groups are told to
/// the model as shown while drawn, as their pages are on the phone.
private struct MacSettingsGroup: View {
    let group: ServerSettingGroup
    let columns: Int
    let parts: ServerSettings.Parts
    let mark: ServerSettings.Mark?

    @Environment(ServerSettingsModel.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.label)
                    .font(Typeface.Mac.text(.h3).weight(.semibold))
                    .foregroundStyle(DWPalette.head)
                if let mark {
                    DWChip(words: ServerSettings.markWords(mark), tone: mark == .attention ? .caution : .marked)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if !group.note.isEmpty {
                Text(group.note)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // the boxes, row by row: each row's boxes side by side, as tall as the tallest
            VStack(alignment: .leading, spacing: 26) {
                ForEach(Self.rows(group.settings, columns: columns), id: \.first?.key) { (row: [ServerSetting]) in
                    HStack(alignment: .top, spacing: MacServerSettingsPage.columnGap) {
                        ForEach(row) { (setting: ServerSetting) in
                            MacSettingBox(setting: setting)
                        }
                        if row.count < columns {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.top, 16)
            if group.id == ServerSettings.lyricsGroup {
                MacGroupBox(legend: RetimeRun.button, ground: DWPalette.bg) {
                    RetimePart(font: Typeface.Mac.text(.small), heading: false)
                }
                .padding(.top, 26)
            }
            if group.id == ServerSettings.savedAnswersGroup && parts.answers {
                MacGroupBox(legend: group.label, ground: DWPalette.bg) {
                    SavedAnswersPart(font: Typeface.Mac.text(.small))
                }
                .padding(.top, 26)
            }
        }
        .onAppear {
            if Self.told(group.id) { settings.shows(.group(group.id)) }
        }
        .onDisappear {
            if Self.told(group.id) { settings.hides(.group(group.id)) }
        }
    }

    /// The groups the model counts as their own pages: the saved answers (read while shown) and Lyrics (Re-time's).
    static func told(_ id: String) -> Bool {
        id == ServerSettings.lyricsGroup || id == ServerSettings.savedAnswersGroup
    }

    /// The settings in rows of `columns`, in the server's order.
    static func rows(_ settings: [ServerSetting], columns: Int) -> [[ServerSetting]] {
        stride(from: 0, to: settings.count, by: max(1, columns)).map { (start: Int) -> [ServerSetting] in
            Array(settings[start..<min(settings.count, start + max(1, columns))])
        }
    }
}

/// A setting's box (ServerSettings.dc.html's `.group.onbg`): the box's corners in the line's edge, the setting's name its
/// legend in the readout face, set into the top edge on the page's ground; in it the control (the phone's own), the chips
/// with Revert at their end, and the setting's words. VoiceOver hears the name from the control, never the legend.
private struct MacSettingBox: View {
    let setting: ServerSetting

    @Environment(ServerSettingsModel.self) private var settings

    var body: some View {
        let row = settings.flow.row(setting)
        VStack(alignment: .leading, spacing: 8) {
            SettingControl(setting: setting, row: row)
            SettingChips(row: row) {
                SettingRevert(setting: setting, row: row)
            }
            SettingWords(row: row, font: Typeface.Mac.text(.small))
        }
        // .group: padding 14px 12px 12px
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            // .legend.mono: top -9px, left 9px inside the 1 pt edge, padding 0 6px, 16 tall - cut in its middle to fit,
            // the whole in its help
            Text(setting.key)
                .font(Typeface.Mac.mono(.label).weight(.bold))
                .foregroundStyle(DWPalette.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(DWPalette.bg)
                .offset(x: 10, y: -8)
                .padding(.trailing, 20)
                .help(setting.key)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}
