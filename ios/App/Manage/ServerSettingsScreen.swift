import DeadwaxCore
import SwiftUI

/// Settings > Manage > Server settings (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; the web's
/// app/ServerSettings.tsx and components/SettingsView.tsx): what the page is for, then Connections (whoever runs deadwax:
/// MusicBrainz, slskd and Navidrome, each Connected or what is wrong, and Check again - You.tsx's), the organizing
/// verdict, and the web's three tabs as sections - Library, Downloads, Connections - each group a row pushing its own page
/// (ServerSettingsGroupScreen), marked "Needs attention" or "Unsaved" by the web's tab marks taken per group.
///
/// Everything is the app's (ServerSettingsModel, every decision Core's): the drafts outlive the page, as the web keeps
/// them in its module, and while any exist every Server settings page has the save bar at its foot - how many, Discard,
/// Save changes - which saves them all at once. Without Settings and the log it says so and asks nothing; opened out of
/// reach before anything was read, it says it needs deadwax; a first read that failed says so with Try again. Gone out of
/// reach, what is drawn is how it was under the amber line Edit album has, and Save is off until deadwax is back and the
/// settings read again. With Reduce Motion nothing slides; VoiceOver reads each row once, its mark with it.
struct ServerSettingsScreen: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        let sections = ServerSettings.sections(answer)
        List {
            Section {
                Text(ServerSettings.pageLine)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if parts.connections {
                ConnectionsSection()
            }
            ServerSettingsRereadFailure()
            Section {
                OrganizingVerdictView(organizing: answer.organizing)
            }
            ForEach(ServerSettings.tabs, id: \.self) { (tab: ServerSettings.Tab) in
                if let groups = sections.first(where: { $0.tab == tab })?.groups {
                    Section {
                        ForEach(groups) { (group: ServerSettingGroup) in
                            NavigationLink(value: AppRoute.serverSettingsGroup(group.id)) {
                                GroupRow(label: group.label, mark: marks[group.id])
                            }
                        }
                    } header: {
                        Text(ServerSettings.label(tab))
                            .font(Typeface.footnote)
                    } footer: {
                        Text(ServerSettings.hint(tab))
                            .font(Typeface.footnote)
                    }
                }
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
    }
}

/// A group's row on the root: its name, and its mark - "Needs attention" amber, "Unsaved" in the accent - read with it.
private struct GroupRow: View {
    let label: String
    let mark: ServerSettings.Mark?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let mark {
                Text(ServerSettings.markWords(mark))
                    .font(Typeface.footnote.weight(.semibold))
                    .foregroundStyle(mark == .attention ? Palette.amber : Palette.accent)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// `OrganizingVerdict`: whether finished downloads are filed now, and what stops it.
private struct OrganizingVerdictView: View {
    let organizing: Organizing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ServerSettings.verdict(organizing))
                .font(Typeface.subheadline.weight(.semibold))
                .foregroundStyle(organizing.enabled ? Palette.held : Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(organizing.blockers, id: \.self) { (blocker: String) in
                Text("• \(blocker)")
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Connections (You.tsx's three rows): each service, Connected or what is wrong in a word with the sentence under it -
/// read by VoiceOver as one - and Check again. On the root, and on the Connections group's own page (the one Set up
/// Navidrome opens), so a save there shows whether Navidrome answers now.
struct ConnectionsSection: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        Section {
            ForEach(Connections.Service.allCases, id: \.self) { (service: Connections.Service) in
                let check = settings.checks.check(service)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(service.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Circle()
                            .fill(Self.dot(check.state))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(check.text)
                            .foregroundStyle(Palette.quiet)
                            .multilineTextAlignment(.trailing)
                    }
                    if let detail = check.detail {
                        Text(detail)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(check.spoken(service))
            }
            Button(Connections.checkAgain) {
                settings.checkConnections()
            }
            .disabled(!settings.checks.againOpen(online: reachability.online))
        } header: {
            Text(Connections.title)
                .font(Typeface.footnote)
        }
    }

    /// `.app-dot`: green once it answered, the danger text's red when it didn't, nothing while it is asked.
    private static func dot(_ state: Connections.Check.State) -> Color {
        switch state {
        case .ok: return Palette.greenIcon
        case .failed: return Palette.danger
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
                .buttonStyle(PrimaryFace())
                .disabled(settings.flow.reading || !reachability.online)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(ServerSettings.reading)
                        .foregroundStyle(Palette.quiet)
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
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        if let failure = settings.flow.readError, !settings.flow.checkStalled {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(failure)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(ServerSettings.tryAgain) {
                        settings.retry()
                    }
                    .buttonStyle(.borderless)
                    .font(Typeface.footnote.weight(.semibold))
                    .disabled(settings.flow.reading || settings.flow.saving || !reachability.online)
                }
            }
        }
    }
}

/// The save bar (the web's `.app-settings-savebar`), at the foot of every Server settings page while there is
/// something to say or to save: the refusal, "Saved." or how many are unsaved - and with drafts, Discard and Save
/// changes. Its words are said by VoiceOver as a save ends (ServerSettingsModel), never with each change typed.
private struct SaveBar: View {
    @Environment(ServerSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let flow = settings.flow
        VStack(spacing: 0) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    words(flow)
                    Spacer(minLength: 8)
                    buttons(flow)
                }
                VStack(alignment: .leading, spacing: 10) {
                    words(flow)
                    HStack(spacing: 12) {
                        buttons(flow)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func words(_ flow: SettingsFlow) -> some View {
        Text(flow.barText)
            .font(Typeface.footnote)
            .foregroundStyle(flow.checkStalled || flow.saveError != nil && flow.checking == nil
                             ? Palette.danger : Palette.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func buttons(_ flow: SettingsFlow) -> some View {
        // a save that never answered, and the read to see how it came out failed: Try again here, on every page - the
        // way out of "looking again" (Discard ends the look too)
        if flow.checkStalled {
            Button(ServerSettings.tryAgain) {
                settings.retry()
            }
            .buttonStyle(SecondaryPill())
            .disabled(!reachability.online)
        }
        if flow.dirty > 0 {
            Button(ServerSettings.discard) {
                settings.discard()
            }
            .buttonStyle(SecondaryPill())
            .disabled(flow.saving)
            Button(flow.saving ? ServerSettings.saving : ServerSettings.save) {
                settings.save()
            }
            .buttonStyle(PrimaryFace())
            .disabled(!settings.saveOpen(online: reachability.online))
        }
    }
}

extension View {
    /// Every Server settings page's frame: told to the model as it shows and goes, its permissions watched, the save bar
    /// at its foot, and the amber line while deadwax is out of reach.
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
            .onAppear { settings.shows(page) }
            .onDisappear { settings.hides(page) }
            // a part given (or taken) while the page is up: asked for now
            .onChange(of: settings.parts) { _, _ in
                settings.accessChanged()
            }
    }
}
