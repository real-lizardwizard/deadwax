import DeadwaxCore
import SwiftUI

/// Settings > Manage (Phase 7 - notes/ios-specs/phase7-managing.md; the web's You.tsx Manage section; since 16 Nov a
/// group of the Settings root, its rules unchanged - each row still opens the web app): deadwax's managing
/// tools this person may use, each opened in the web app, in Safari - never rebuilt on the phone. Top to bottom, each
/// only with its permission (Core's Managing.tools, the web's `managing` and `albumEdit` by what /me last said):
/// Edit an album (the phone's own: the web's editors open from an album's page, so the row opens the web app's Library,
/// and says so under it), Needs a look, Library care, People (logins on), Server settings and Event log - the web's
/// five, in its order and words. Drawn only with a row to draw, between Downloads and Account (the web's Manage comes
/// before its Account).
///
/// The footer says they open in Safari and - with logins on - that Safari signs in apart from the app, the first
/// time, with the same name and password, and that each page opens as Safari's person, who may not be the app's:
/// nothing compares the two. While deadwax can't be reached the rows are dimmed and off, the footer
/// saying they open once it's back: Safari would only fail at the same address. Nothing is asked of deadwax here -
/// the page each opens asks it itself, and refuses for itself without its permission.
struct ManageSection: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let tools = Managing.tools(server.access)
        if !tools.isEmpty {
            let online = reachability.online
            Section {
                ForEach(tools, id: \.self) { (tool: Managing.Tool) in
                    if let url = Managing.url(tool, at: server.address) {
                        WebAppRow(label: ManagingWords.label(tool), line: ManagingWords.line(tool), url: url, live: online)
                    }
                }
            } header: {
                Text(ManagingWords.title)
                    .font(Typeface.footnote)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ManagingWords.footer(loginsOn: server.access.on, online: online), id: \.self) { (line: String) in
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
    /// Opens a web-app address - Manage's rows, Change password, an album's Edit in the web app, Set up Navidrome - in
    /// the default browser (never a web view in the app), and when iOS refuses it (Safari turned off in Screen Time, no
    /// other browser to take it) says so over the tabs, announced: Core's Managing.notice(opened:). A tap that opens
    /// nothing never says nothing.
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
