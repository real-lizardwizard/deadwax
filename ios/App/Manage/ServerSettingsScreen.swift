import DeadwaxCore
import SwiftUI

/// Settings > Manage > Server settings (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; the web's
/// app/ServerSettings.tsx and components/SettingsView.tsx): what the page is for, then Connections (whoever runs deadwax:
/// MusicBrainz, slskd and Navidrome, each Connected or what is wrong, and Check again - You.tsx's), the organizing
/// verdict, and the web's three tabs - Library, Downloads, Connections - each group a row pushing its own page
/// (ServerSettingsGroupScreen), marked "Needs attention" or "Unsaved" by the web's tab marks taken per group.
///
/// Everything is the app's (ServerSettingsModel, every decision Core's): the drafts outlive the page, as the web keeps
/// them in its module, and while any exist every Server settings page has the save bar at its foot - how many, Discard,
/// Save changes - which saves them all at once. Without Settings and the log it says so and asks nothing; opened out of
/// reach before anything was read, it says it needs deadwax; a first read that failed says so with Try again. Gone out of
/// reach, what is drawn is how it was under the amber line Edit album has, and Save is off until deadwax is back and the
/// settings read again. With Reduce Motion nothing slides; VoiceOver reads each row once, its mark with it.
///
/// (The redesign, slice R14 - notes/ios.md "The redesign, slice R14: People and Server settings") Flat, as
/// iServerSettings draws it: no List - the page's black, the three tabs a strip (PhoneStrip, each tab's mark in its words)
/// and the chosen tab's groups rows on their hairlines under it, each pushing its page of cards. The phone's alone: the
/// Mac's Server settings is MacServerSettingsPage, every tab's boxes on one page.
struct ServerSettingsScreen: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tab the strip shows - Library's first, as the web's.
    @State private var tab: ServerSettings.Tab = .library

    var body: some View {
        let parts = settings.parts
        // a ZStack, not a Group: the page's frame (its shows and hides) is on one view that stays as the spinner gives way
        // to the list - on a Group it would go to each branch, and the swap would hide and show the page, and read again
        ZStack {
            if !parts.page {
                ContentUnavailableView {
                    Label(ServerSettings.title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if let answer = settings.flow.answer {
                list(answer, parts)
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
        .navigationTitle(ServerSettings.title)
        .navigationBarTitleDisplayMode(.inline)
        .serverSettingsPage(.root)
    }

    @ViewBuilder private func list(_ answer: ServerSettingsAnswer, _ parts: ServerSettings.Parts) -> some View {
        let marks = settings.flow.groupMarks
        let tabMarks = settings.flow.tabMarks
        let sections = ServerSettings.sections(answer)
        let tabs = sections.map(\.tab)
        // a tab the answer no longer has: its first
        let shown = tabs.contains(tab) ? tab : tabs.first ?? tab
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ManageNote(words: ServerSettings.pageLine)
                    if parts.connections {
                        ConnectionsSection()
                    }
                    ServerSettingsRereadFailure()
                    OrganizingVerdictView(organizing: answer.organizing)
                        .padding(.top, ManageLook.cardAbove)
                }
                .padding(.horizontal, ManageLook.side)
                if !tabs.isEmpty {
                    PhoneStrip(options: tabs,
                               words: { (each: ServerSettings.Tab) -> String in Self.words(each, tabMarks[each]) },
                               shown: Binding(get: { shown },
                                              set: { (chosen: ServerSettings.Tab) -> Void in tab = chosen }),
                               spoken: ServerSettings.title)
                        .padding(.top, ManageLook.cardAbove)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections.first { $0.tab == shown }?.groups ?? []) { (group: ServerSettingGroup) in
                        NavigationLink(value: AppRoute.serverSettingsGroup(group.id)) {
                            GroupRow(label: group.label, mark: marks[group.id])
                        }
                        .buttonStyle(.plain)
                    }
                    ManageNote(words: ServerSettings.hint(shown))
                }
                .padding(.horizontal, ManageLook.side)
            }
            .padding(.bottom, ManageLook.cardAbove)
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
    }

    /// A tab's words in the strip: its name, and its mark - "Library · Needs attention" - so a tab not shown says it too.
    static func words(_ tab: ServerSettings.Tab, _ mark: ServerSettings.Mark?) -> String {
        guard let mark else { return ServerSettings.label(tab) }
        return "\(ServerSettings.label(tab)) \u{00B7} \(ServerSettings.markWords(mark))"
    }
}

/// A group's row on the root (iSettings' `.go`): its name, its mark - "Needs attention" amber, "Unsaved" purple, a chip -
/// and the chevron, on its hairline; one element for VoiceOver, its mark read with it.
private struct GroupRow: View {
    let label: String
    let mark: ServerSettings.Mark?

    var body: some View {
        PhoneGo {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let mark {
                DWChip(words: ServerSettings.markWords(mark), tone: mark == .attention ? .caution : .marked)
            }
            PhoneChevron()
        }
    }
}

/// `OrganizingVerdict`: whether finished downloads are filed now, and what stops it - (R14) flat, green or amber words
/// with the blockers under them, on both devices' pages.
struct OrganizingVerdictView: View {
    let organizing: Organizing
    var font: Font = ManageLook.small

    var body: some View {
        VStack(alignment: .leading, spacing: ManageLook.wordsGap) {
            Text(ServerSettings.verdict(organizing))
                .font(font.weight(.semibold))
                .foregroundStyle(organizing.enabled ? DWPalette.greenText : DWPalette.amberText)
            ForEach(organizing.blockers, id: \.self) { (blocker: String) in
                Text("\u{2022} \(blocker)")
                    .font(font)
                    .foregroundStyle(DWPalette.t2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Connections (You.tsx's three rows): each service, Connected or what is wrong in a word with the sentence under it -
/// read by VoiceOver as one - and Check again. On the phone's root, and on the Connections group's own page (the one Set
/// up Navidrome opens, on the Mac too), so a save there shows whether Navidrome answers now. (R14) Flat: a heading, each
/// row on its hairline with its dot, Check again the look's button - nothing of the phone's rows, so the Mac's sheet
/// draws it at its own size; the Mac's Server settings draws its own box of them (MacServerSettingsPage).
struct ConnectionsSection: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ManageHeading(words: Connections.title)
                .padding(.bottom, ManageLook.wordsGap)
            ForEach(Connections.Service.allCases, id: \.self) { (service: Connections.Service) in
                ConnectionRow(service: service, check: settings.checks.check(service))
                    .padding(.vertical, ManageLook.cardGap)
                    .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            }
            Button(Connections.checkAgain) {
                settings.checkConnections()
            }
            .buttonStyle(DWButtonStyle())
            .disabled(!settings.checks.againOpen(online: reachability.online))
            .padding(.top, ManageLook.wordsGap)
        }
        .padding(.top, ManageLook.cardAbove)
    }
}

/// One service's row: its name, the dot and the word, the sentence under them - read as one, the check's own words.
struct ConnectionRow: View {
    let service: Connections.Service
    let check: Connections.Check
    var font: Font = ManageLook.small

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(service.label)
                    .foregroundStyle(DWPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .fill(Self.dot(check.state))
                    .frame(width: CGFloat(DWFlat.dot), height: CGFloat(DWFlat.dot))
                    .accessibilityHidden(true)
                Text(check.text)
                    .foregroundStyle(DWPalette.t2)
                    .multilineTextAlignment(.trailing)
            }
            if let detail = check.detail {
                Text(detail)
                    .font(font)
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .font(Typeface.Look.text(.field))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(check.spoken(service))
    }

    /// `.app-dot`: green once it answered, the danger text's red when it didn't, nothing while it is asked.
    static func dot(_ state: Connections.Check.State) -> Color {
        switch state {
        case .ok: return DWPalette.greenText
        case .failed: return DWPalette.redChipText
        case .pending: return Color.clear
        }
    }
}

/// The settings not read yet: "Reading the settings", or - a first read that failed - why, with Try again, never a
/// spinner for good.
struct ServerSettingsFirstRead: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(spacing: 14) {
            if let failure = settings.flow.readError {
                ErrorNote(text: failure)
                Button(ServerSettings.tryAgain) {
                    settings.retry()
                }
                .buttonStyle(DWButtonStyle(kind: .pri))
                .disabled(settings.flow.reading || !reachability.online)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(ServerSettings.reading)
                        .foregroundStyle(DWPalette.t2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A read again that failed over the settings shown: "Couldn't read the settings again just now.", with Try again -
/// unless it was the look at a save that never answered, which the save bar says, with its own Try again.
struct ServerSettingsRereadFailure: View {
    var font: Font = ManageLook.small

    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        if let failure = settings.flow.readError, !settings.flow.checkStalled {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(failure)
                    .font(font)
                    .foregroundStyle(DWPalette.redChipText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(ServerSettings.tryAgain) {
                    settings.retry()
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(settings.flow.reading || settings.flow.saving || !reachability.online)
            }
            .padding(.top, ManageLook.cardAbove)
        }
    }
}

/// The save bar (the web's `.app-settings-savebar`), at the foot of every Server settings page while there is
/// something to say or to save: the refusal, "Saved." or how many are unsaved - and with drafts, Discard and Save
/// changes. Its words are said by VoiceOver as a save ends (ServerSettingsModel), never with each change typed. (R14)
/// The look's: on the phone the page's black over a hairline (`.foot2`) with Discard flat and Save changes the purple
/// one; on the Mac the panel's ground over the line's edge (People.dc.html's foot) with the Mac's buttons. (R14's
/// review) Beside the words while all of it fits one line; else the words over the buttons, side by side while they fit
/// the width (418 points at AX3 don't fit a phone's 343), else one over the other, each across the bar, its words
/// wrapping on the phone.
private struct SaveBar: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let flow = settings.flow
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                words(flow)
                Spacer(minLength: 8)
                buttons(flow, across: false)
            }
            // the last way: laid out in the bar's width, the buttons choosing their row or their stack in it
            VStack(alignment: .leading, spacing: 10) {
                words(flow)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        buttons(flow, across: false)
                    }
                    VStack(spacing: 8) {
                        buttons(flow, across: true)
                    }
                }
            }
        }
        .padding(.horizontal, ManageLook.side)
        .padding(.vertical, 10)
        .background {
            (Platform.mac ? DWPalette.panel : DWPalette.footFace)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) { DWRule(colour: Platform.mac ? DWPalette.line : DWPalette.footEdge) }
    }

    private func words(_ flow: SettingsFlow) -> some View {
        Text(flow.barText)
            .font(ManageLook.small)
            .foregroundStyle(flow.checkStalled || flow.saveError != nil && flow.checking == nil
                             ? DWPalette.redChipText : DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The bar's buttons; `across`, one over the other, each the bar's width, its words wrapping on the phone.
    @ViewBuilder private func buttons(_ flow: SettingsFlow, across: Bool) -> some View {
        // a save that never answered, and the read to see how it came out failed: Try again here, on every page - the
        // way out of "looking again" (Discard ends the look too)
        if flow.checkStalled {
            Button {
                settings.retry()
            } label: {
                ManageButtonWords(words: ServerSettings.tryAgain, across: across)
            }
            .buttonStyle(DWButtonStyle(fills: across))
            .disabled(!reachability.online)
        }
        if flow.dirty > 0 {
            Button {
                settings.discard()
            } label: {
                ManageButtonWords(words: ServerSettings.discard, across: across)
            }
            .buttonStyle(DWButtonStyle(fills: across))
            .disabled(flow.saving)
            Button {
                settings.save()
            } label: {
                ManageButtonWords(words: flow.saving ? ServerSettings.saving : ServerSettings.save, across: across)
            }
            .buttonStyle(DWButtonStyle(kind: .pri, fills: across))
            .disabled(!settings.saveOpen(online: reachability.online))
        }
    }
}

extension View {
    /// Every Server settings page's frame: told to the model as it shows and goes, its permissions watched, the save bar
    /// at its foot, and the amber line while deadwax is out of reach - and (the Mac app, slice 7) on the Mac known to the
    /// menus, so File > Save changes (⌘S) is the bar's Save changes while the page is the one in front. (R14) The Mac's
    /// Server settings (MacServerSettingsPage) is framed by it too, as its root.
    func serverSettingsPage(_ page: ServerSettingsModel.Page) -> some View {
        modifier(ServerSettingsPageFrame(page: page))
    }
}

private struct ServerSettingsPageFrame: ViewModifier {
    let page: ServerSettingsModel.Page

    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if settings.parts.page && settings.flow.barShown {
                    SaveBar()
                }
            }
            .editOutOfReach(!reachability.online && settings.flow.answer != nil)
            .macSettingsPage()
            .onAppear { settings.shows(page) }
            .onDisappear { settings.hides(page) }
            // a part given (or taken) while the page is up: asked for now
            .onChange(of: settings.parts) { _, _ in
                settings.accessChanged()
            }
    }
}
