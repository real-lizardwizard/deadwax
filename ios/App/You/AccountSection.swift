import DeadwaxCore
import SwiftUI

/// Settings > Account (16 Nov, a page of its own - You's Account section before), its row on the root only with logins
/// on (YouLines.account). The section, while /me still says logins are on - should a pull find them off with the page
/// open, it is left empty rather than offering a Sign out there is nothing to sign out of. A pull asks /me again, as
/// the root's does: Change password is offered by what /me last said. (R9) Flat, a Settings page (SettingsPage).
struct AccountPage: View {
    @Environment(ServerModel.self) private var server

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        SettingsPage {
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
/// header: the page's title says Account. (R9) One flat group - Change password a `.go` row, Sign out a row in the red
/// on its hairline - the footnote a note under it.
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
        PhoneGroup {
            if OwnPassword.changeOffered(server.me) {
                NavigationLink(value: AppRoute.changePassword) {
                    SettingsGo { Text(OwnPassword.title) }
                }
                .buttonStyle(.plain)
            }
            Button(role: .destructive) {
                Task { await server.signOut() }
            } label: {
                HStack(spacing: CGFloat(PhoneLook.goGap)) {
                    Text(row.label)
                        .foregroundStyle(DWPalette.redChipText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(user)
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .settingsRow()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.busy)
        }
        if let problem = row.problem {
            SettingsNote(words: problem, colour: DWPalette.redChipText)
        }
        // with anything on the phone, where someone signing out wonders: the downloads stay (6.1)
        SettingsNote(words: SignOutRow.footnote(user: user)
                     + (downloads.anythingHere ? DownloadWords.staysAfterSignOut(Platform.device) : ""))
            .onChange(of: row.problem) { _, problem in
                if let problem { Notice.announce(problem) }
            }
    }
}
