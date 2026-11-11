import DeadwaxCore
import SwiftUI

/// You > Account (screens.md 3 and 8, the web's app/SignOutRow.tsx), drawn only with logins on: Sign out, the user
/// name beside it, "Signing out…" while it asks, and the footnote - who is signed in and how, break-glass's 12 hours.
///
/// Signing out is leaving: ServerModel.signOut asks POST /auth/logout, and any answer from deadwax ends the session -
/// the music stops (the player is reset with the person), the Keychain's session goes, every page pops and the sign-in
/// shows alone. Only no answer at all keeps you signed in, and the row says so (Core's SignOutRow), announced. Change
/// password is a later phase's.
struct AccountSection: View {
    let user: String

    @Environment(ServerModel.self) private var server

    var body: some View {
        let row = server.signOutRow
        Section {
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
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(YouWords.account)
        } footer: {
            Text(SignOutRow.footnote(user: user))
        }
        .onChange(of: row.problem) { _, problem in
            if let problem { Notice.announce(problem) }
        }
    }
}
