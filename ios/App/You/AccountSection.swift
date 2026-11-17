import DeadwaxCore
import SwiftUI

/// Settings > Account (16 Nov, a page of its own - You's Account section before), its row on the root only with logins
/// on (YouLines.account). The section, while /me still says logins are on - should a pull find them off with the page
/// open, it is left empty rather than offering a Sign out there is nothing to sign out of. A pull asks /me again, as
/// the root's does: Change password is offered by what /me last said.
struct AccountPage: View {
    @Environment(ServerModel.self) private var server

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        List {
            if lines.account, let me = server.me {
                AccountSection(user: me.user)
            }
        }
        .navigationTitle(YouWords.account)
        .pullToRefresh {
            await server.refreshMe()
        }
    }
}

/// Account (screens.md 3 and 8, the web's app/SignOutRow.tsx), drawn only with logins on: Change password first, as the
/// web's Account has it - for a Navidrome sign-in, never break-glass (Core's OwnPassword.changeOffered, the web's
/// changeOffered) - (Phase 8, slice 10) its own page here (ChangePasswordScreen). Then Sign out, the user name beside
/// it, "Signing out…" while it asks, and the footnote - who is signed in and how, break-glass's 12 hours. (16 Nov) No
/// header: the page's title says Account.
///
/// Signing out is leaving: ServerModel.signOut asks POST /auth/logout, and any answer from deadwax ends the session -
/// the music stops (the player is reset with the person), the Keychain's session goes, every page pops and the sign-in
/// shows alone. Only no answer at all keeps you signed in, and the row says so (Core's SignOutRow), announced.
struct AccountSection: View {
    let user: String

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        let row = server.signOutRow
        Section {
            if OwnPassword.changeOffered(server.me) {
                NavigationLink(value: AppRoute.changePassword) {
                    Text(OwnPassword.title)
                }
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
