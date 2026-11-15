import DeadwaxCore
import SwiftUI

/// You > Account (screens.md 3 and 8, the web's app/SignOutRow.tsx), drawn only with logins on: (Phase 7) Change
/// password first, as the web's Account has it - for a Navidrome sign-in, never break-glass (Core's
/// Managing.changeOffered, the web's changeOffered) - opening the web app's You in Safari, where it is under Account
/// (it has no address of its own), the line under the row saying so; off while deadwax can't be reached. Then Sign out,
/// the user name beside it, "Signing out…" while it asks, and the footnote - who is signed in and how, break-glass's
/// 12 hours.
///
/// Signing out is leaving: ServerModel.signOut asks POST /auth/logout, and any answer from deadwax ends the session -
/// the music stops (the player is reset with the person), the Keychain's session goes, every page pops and the sign-in
/// shows alone. Only no answer at all keeps you signed in, and the row says so (Core's SignOutRow), announced.
struct AccountSection: View {
    let user: String

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let row = server.signOutRow
        Section {
            if Managing.changeOffered(server.me), let url = Managing.youURL(at: server.address) {
                WebAppRow(label: ManagingWords.changePassword, line: ManagingWords.changePasswordLine, url: url,
                          live: reachability.online)
            }
            Button(role: .destructive) {
                Task { await server.signOut() }
            } label: {
                HStack {
                    Text(row.label)
                        .foregroundStyle(Palette.danger)
                    Spacer(minLength: 12)
                    Text(user)
                        .foregroundStyle(Palette.quiet)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contentShape(Rectangle())
            }
            .disabled(row.busy)
            if let problem = row.problem {
                Text(problem)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(YouWords.account)
                .font(Typeface.footnote)
        } footer: {
            Group {
                // with anything on the phone, where someone signing out wonders: the downloads stay (6.1)
                Text(SignOutRow.footnote(user: user) + (downloads.anythingHere ? DownloadWords.staysAfterSignOut : ""))
            }
            .font(Typeface.footnote)
        }
        .onChange(of: row.problem) { _, problem in
            if let problem { Notice.announce(problem) }
        }
    }
}
