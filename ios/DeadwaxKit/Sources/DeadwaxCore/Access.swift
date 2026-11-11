import Foundation

/// What the app draws by: this person's permissions as /deadwax/me last said them, whether logins are on, whether
/// an admin gave them something this session doesn't honour, and who they are - the web's app/access.ts Access and
/// lib/permissions.ts, with useMyLibrary.ts's hasLibrary beside them. Made from every /me answer (`init(me:)`); the
/// server decides every request either way, so this only says what to show.
public struct Access: Sendable, Equatable {
    /// A permission an admin gives an ordinary person (src/users.py PERMISSIONS, in its order) - an admin has them all.
    public enum Permission: String, Sendable, CaseIterable, Hashable {
        case request, edit, library, downloads, server, people
    }

    /// The break-glass admin's fixed name (src/auth.py BREAK_GLASS_USER): no Navidrome account signs in as it, so it
    /// has no library and no play queue of its own.
    public static let breakGlassUser = "deadwax"

    /// Who /me said this is (`local`, the shared account, with logins off).
    public let user: String
    public let permissions: Set<Permission>
    /// Logins are on.
    public let on: Bool
    /// /me's `permissions_unverified`: some of what an admin gave is off until they sign in again.
    public let unverified: Bool
    /// /me's `admin` - a Navidrome admin, break-glass, or everyone with logins off.
    public let admin: Bool

    public init(user: String, permissions: Set<Permission>, on: Bool, unverified: Bool, admin: Bool) {
        self.user = user
        self.permissions = permissions
        self.on = on
        self.unverified = unverified
        self.admin = admin
    }

    /// What a /me answer says (access.ts accessOf): with logins off everyone has everything and is the admin.
    public init(me: Me) {
        let off = me.auth == "off"
        self.init(user: me.user, permissions: off ? Self.all : Self.permissions(of: me), on: me.auth == "on",
                  unverified: me.permissionsUnverified == true, admin: off || me.admin)
    }

    public static let all = Set(Permission.allCases)

    /// The set /me's answer names - only names it knows, so a stray word grants nothing. An answer with no list at
    /// all is from a server before 2.0.0-player.61: its `admin` then says it all - every permission or none
    /// (lib/permissions.ts permissionsOf).
    public static func permissions(of me: Me) -> Set<Permission> {
        guard let named = me.permissions else { return me.admin ? all : [] }
        return Set(Permission.allCases.filter { named.contains($0.rawValue) })
    }

    public var isAdmin: Bool { admin }
    public var loginsOn: Bool { on }

    public func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// Whether this person runs deadwax, as far as what went wrong goes (access.ts seesDetail): an admin, or someone
    /// given Settings and the log. They are shown an error's own words under its sentence (`ErrorWords`'s `admin`)
    /// and the can't-reach screen's detail; everyone else the sentence, told to tell whoever runs deadwax.
    public var seesDetail: Bool { admin || permissions.contains(.server) }

    /// The break-glass admin, signed in with deadwax's own password rather than a Navidrome account.
    public var isBreakGlass: Bool { on && user == Self.breakGlassUser }

    /// Whether there is a library of this person's to ask about - logins on, signed in through Navidrome
    /// (useMyLibrary.ts hasLibrary). Only then is the id bridge asked, and Add and Remove shown.
    public var hasLibrary: Bool { on && user != Self.breakGlassUser }

    /// What a sign-in made over the running app does (lib/signIn.ts afterSignIn): carries on for the same person,
    /// and starts again for someone else - what was in hand (the queue, the pins) was the other person's.
    public enum AfterSignIn: String, Sendable { case carryOn = "carry-on", startAgain = "start-again" }

    public static func afterSignIn(before: String?, now: String) -> AfterSignIn {
        guard let before else { return .carryOn }
        return before.utf16.elementsEqual(now.utf16) ? .carryOn : .startAgain
    }
}
