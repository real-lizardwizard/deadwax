import DeadwaxCore
import SwiftUI

/// Settings > Manage (Phase 7 - notes/ios-specs/phase7-managing.md; the web's You.tsx Manage section; since 16 Nov a
/// group of the Settings root): deadwax's managing tools this person may use. Top to bottom, each only with its
/// permission (Core's Managing.tools, the web's `managing` and `albumEdit` by what /me last said): Edit an album (the
/// phone's own row), Needs a look, Library care, People (logins on), Server settings and Event log - the web's five, in
/// its order and words. Drawn only with a row to draw, between Downloads and Account (the web's Manage comes before its
/// Account).
///
/// Phase 8 brings them into the app one at a time (phase8-managing.md 11). Since slice 1 Edit an album is the app's: it
/// pushes Choose the folder (ChooseFolderScreen), whose folder opens Edit album over the tabs - and that page says for
/// itself that it needs deadwax, so the row is never dimmed. Since slice 6 Needs a look is too: it pushes the review
/// queue (NeedsLookScreen), its count at the row's right (QueueCountModel - asked by YouView and MainTabs, never here).
/// Since slice 7 Library care is too: it pushes LibraryCareScreen (Rescan, Get covers, CD art and lyrics, In nobody's
/// library). Since slice 8 Server settings is too: it pushes ServerSettingsScreen (Connections, the organizing verdict,
/// each group of the server's settings a page of its own, one save). Since slice 9 the event log is too: it pushes
/// EventLogScreen (the lines, live, Copy and Clear). People still opens the web app in Safari (WebAppRow) until its
/// slice lands.
///
/// The footer says those open in Safari (the app's own said apart, ManagingWords.othersOpen) and - with logins on -
/// that Safari signs in apart from the app, the first time, with the same name and password, and that each page opens
/// as Safari's person, who may not be the app's: nothing compares the two. While deadwax can't be reached the Safari
/// rows are dimmed and off, the footer saying they open once it's back: Safari would only fail at the same address.
/// Nothing is asked of deadwax here - the page each opens asks it itself, and refuses for itself without its
/// permission.
struct ManageSection: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(QueueCountModel.self) private var queueCount

    var body: some View {
        let tools = Managing.tools(server.access)
        if !tools.isEmpty {
            let online = reachability.online
            Section {
                ForEach(tools, id: \.self) { (tool: Managing.Tool) in
                    if tool == .edit {
                        // (Phase 8, slice 1) the app's own: Choose the folder
                        NavigationLink(value: AppRoute.chooseFolder) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .queue {
                        // (Phase 8, slice 6) the app's own: the review queue - its count at the right, as a value
                        // (You.tsx's badge; never on a tab), nothing while nobody knows it or it is none
                        NavigationLink(value: AppRoute.needsALook) {
                            LabeledContent(ManagingWords.label(tool)) {
                                Text(queueCount.count.value)
                                    .monospacedDigit()
                            }
                            // read once: "Needs a look, 3 albums" (needsLookLabel)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(queueCount.count.spoken)
                        }
                    } else if tool == .care {
                        // (Phase 8, slice 7) the app's own: Rescan, the runs and In nobody's library
                        NavigationLink(value: AppRoute.libraryCare) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .settings {
                        // (Phase 8, slice 8) the app's own: Connections, the verdict and the server's settings
                        NavigationLink(value: AppRoute.serverSettings) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .log {
                        // (Phase 8, slice 9) the app's own: the event log, live
                        NavigationLink(value: AppRoute.eventLog) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if let url = Managing.url(tool, at: server.address) {
                        WebAppRow(label: ManagingWords.label(tool), url: url, live: online)
                    }
                }
            } header: {
                Text(ManagingWords.title)
                    .font(Typeface.footnote)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ManagingWords.footer(loginsOn: server.access.on, online: online, tools: tools), id: \.self) {
                        (line: String) in
                        Text(line)
                    }
                }
                .font(Typeface.footnote)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension OpenURLAction {
    /// Opens a web-app address - Manage's rows, Change password, Edit album's rows still in the web app, Set up
    /// Navidrome - in the default browser (never a web view in the app), and when iOS refuses it (Safari turned off in
    /// Screen Time, no other browser to take it) says so over the tabs, announced: Core's Managing.notice(opened:). A
    /// tap that opens nothing never says nothing.
    @MainActor
    func webApp(_ url: URL, player: PlayerModel) {
        self(url) { (accepted: Bool) in
            guard let words = Managing.notice(opened: accepted) else { return }
            Task { @MainActor in player.say(words) }
        }
    }
}

/// A row that opens the web app in Safari (Manage's rows, Account's Change password): its words - and, for a row that
/// can't open its tool's own page, a line under them saying where it is once open - with `arrow.up.forward` at the
/// trailing edge, where a pushed page's row has its chevron. The tap hands the address to the default browser
/// (`OpenURLAction.webApp`, which says so if iOS refuses it). Off (dimmed, `.disabled`) while deadwax can't be reached.
/// VoiceOver reads it as one button, its words and line, with the hint "Opens in Safari."; the words wrap at every
/// text size, the sign growing with them.
struct WebAppRow: View {
    let label: String
    var line: String?
    let url: URL
    let live: Bool

    @Environment(\.openURL) private var openURL
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Button {
            guard live else { return }
            openURL.webApp(url, player: player)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .foregroundStyle(.primary)
                    if let line {
                        Text(line)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: ManagingWords.outSymbol)
                    .font(Typeface.symbol(.body))
                    .foregroundStyle(Palette.quiet)
                    .accessibilityHidden(true)
            }
            .opacity(live ? 1 : Palette.off)
            .contentShape(Rectangle())
        }
        .disabled(!live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.map { "\(label), \($0)" } ?? label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(ManagingWords.opensInSafari)
    }
}
