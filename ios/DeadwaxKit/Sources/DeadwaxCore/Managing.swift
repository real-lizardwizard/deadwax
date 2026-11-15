import Foundation

/// You > Manage (Phase 7, notes/ios-specs/phase7-managing.md): deadwax's managing tools - the editors, Needs a look,
/// Library care, People, Server settings and the event log - each opened in the web app, in Safari, never rebuilt on
/// the phone. Which show is the web's rule (lib/permissions.ts `managing` and `albumEdit`, by the permissions /me
/// gives - Access); where each opens is the web app's own address for it (lib/appRoutes.ts `formatRoute`: the app at
/// `/player/`, its page after the `#`, opened cold as itself). Held to the TypeScript by
/// Tests/DeadwaxCoreTests/Fixtures/managing/managing-vectors.json (ios/scripts/export-managing-vectors.cjs, which runs
/// it as it is; ui/test/iosmanaging.sim.cjs checks it is current).
///
/// Every page it opens refuses for itself without its permission, and every route behind it is the server's to
/// refuse: the rows only say what to offer.
public enum Managing {
    /// The web's Managing (permissions.ts): You's rows and the sidebar's group, each by its permission.
    public struct Parts: Sendable, Equatable {
        /// Needs a look - Look after the library.
        public let queue: Bool
        /// Library care - Look after the library (Rescan, Held by nobody) or Edit albums (its bulk runs).
        public let care: Bool
        /// People - a Navidrome admin's, and only with logins on (with them off there is nobody to manage).
        public let people: Bool
        /// Server settings - Settings and the log.
        public let settings: Bool
        /// The event log - Settings and the log.
        public let log: Bool

        public init(queue: Bool, care: Bool, people: Bool, settings: Bool, log: Bool) {
            self.queue = queue
            self.care = care
            self.people = people
            self.settings = settings
            self.log = log
        }

        /// Any of them: the section shows.
        public var any: Bool { queue || care || people || settings || log }
    }

    /// permissions.ts `managing(perms, loginsOn)`.
    public static func parts(_ permissions: Set<Access.Permission>, loginsOn: Bool = true) -> Parts {
        Parts(queue: permissions.contains(.library),
              care: permissions.contains(.library) || permissions.contains(.edit),
              people: permissions.contains(.people) && loginsOn,
              settings: permissions.contains(.server),
              log: permissions.contains(.server))
    }

    /// The album page's Edit (permissions.ts `AlbumEdit`): with Edit albums or Look after the library - the editors
    /// inside it Edit albums', Delete Look after the library's.
    public struct AlbumEdit: Sendable, Equatable {
        public let shown: Bool
        public let editors: Bool
        public let delete: Bool

        public init(shown: Bool, editors: Bool, delete: Bool) {
            self.shown = shown
            self.editors = editors
            self.delete = delete
        }
    }

    /// permissions.ts `albumEdit(perms)`.
    public static func albumEdit(_ permissions: Set<Access.Permission>) -> AlbumEdit {
        let edit = permissions.contains(.edit), library = permissions.contains(.library)
        return AlbumEdit(shown: edit || library, editors: edit, delete: library)
    }

    /// One of Manage's rows, in the order You draws them: the phone's own Edit an album first (the web's editors live
    /// on an album's page, not in You), then the web's five in You.tsx's order.
    public enum Tool: String, Sendable, CaseIterable, Hashable {
        case edit, queue, care, people, settings, log
    }

    /// The rows for this person (You.tsx: `managing(access.permissions, access.on)`; the first by `albumEdit`).
    public static func tools(_ access: Access) -> [Tool] {
        let parts = parts(access.permissions, loginsOn: access.on)
        return Tool.allCases.filter { tool in
            switch tool {
            case .edit: return albumEdit(access.permissions).shown
            case .queue: return parts.queue
            case .care: return parts.care
            case .people: return parts.people
            case .settings: return parts.settings
            case .log: return parts.log
            }
        }
    }

    /// Whether Account offers Change password (lib/ownPassword.ts `changeOffered`): logins on and a Navidrome sign-in -
    /// never with logins off (no password of yours in deadwax), never break-glass (no Navidrome account behind it).
    /// The name compared as JavaScript compares it, unit for unit.
    public static func changeOffered(_ me: Me?) -> Bool {
        guard let me, me.auth == "on", !me.user.isEmpty else { return false }
        return !me.user.utf16.elementsEqual(Access.breakGlassUser.utf16)
    }

    // MARK: the addresses

    /// Where the web app is: `/` answers a 307 to it, so the phone goes there itself.
    public static let appPath = "/player/"

    /// The page's address after the `#` (formatRoute's, without its `#`): each Managing page on the You tab, as You
    /// opens it - one page each, whatever id an address gives it, so the id is the web's own - and for the editors,
    /// which no address opens (the Edit panel opens only from a tap on an album's page), the Library's root.
    public static func fragment(_ tool: Tool) -> String {
        switch tool {
        case .edit: return "/library"
        case .queue: return "/you/queue/all"
        case .care: return "/you/care/library"
        case .people: return "/you/people/all"
        case .settings: return "/you/settings/server"
        case .log: return "/you/log/all"
        }
    }

    /// An album's page in the web app, by Navidrome's album id (formatRoute: the id `encodeURIComponent`'d).
    public static func albumFragment(id: String) -> String {
        "/library/album/" + TurntableGeometry.encodeURIComponent(id)
    }

    /// You's root in the web app: Account's Change password is in it, and has no address of its own.
    public static let youFragment = "/you"

    /// A tool's page in the web app at this phone's deadwax; nil with no address.
    public static func url(_ tool: Tool, at server: ServerAddress?) -> URL? {
        url(fragment: fragment(tool), at: server)
    }

    /// An album's page in the web app (an album's ••• - Edit in the web app); nil with no address or no id.
    public static func albumURL(id: String, at server: ServerAddress?) -> URL? {
        id.isEmpty ? nil : url(fragment: albumFragment(id: id), at: server)
    }

    /// The web app's You (Account's Change password).
    public static func youURL(at server: ServerAddress?) -> URL? {
        url(fragment: youFragment, at: server)
    }

    static func url(fragment: String, at server: ServerAddress?) -> URL? {
        guard let server else { return nil }
        return URL(string: server.base.absoluteString + appPath + "#" + fragment)
    }

    /// What a tap says once iOS has answered the open (SwiftUI's openURL completion): nothing when the browser took the
    /// address; when iOS refused it - Safari turned off in Screen Time, no other browser to open it - a notice in a
    /// listener's words, so a tap that opened nothing never says nothing. The address is no help to anyone here (iOS
    /// refused the kind of link, not this one), so it isn't said, even to whoever runs deadwax.
    public static func notice(opened: Bool) -> String? {
        opened ? nil : ManagingWords.notOpened
    }
}

/// Manage's words: the web's where the web says them (You.tsx's title and rows, ownPassword.ts's CHANGE_TITLE - held by
/// the fixture), the phone's own for what only the phone does - open them in Safari.
public enum ManagingWords {
    /// The section's title (You.tsx `app-managing-title`).
    public static let title = "Manage"

    /// A row's label: the web's rows' own (You.tsx), and the phone's for the editors.
    public static func label(_ tool: Managing.Tool) -> String {
        switch tool {
        case .edit: return editAnAlbum
        case .queue: return "Needs a look"
        case .care: return "Library care"
        case .people: return "People"
        case .settings: return "Server settings"
        case .log: return "Event log"
        }
    }

    /// The phone's own row for the editors, and the line under it: where they are once it opens.
    public static let editAnAlbum = "Edit an album"
    public static let editLine = "Opens the web app's Library: open an album there, then Edit. An album's ••• here has "
        + "Edit in the web app too."
    /// The line under a row, if it has one: only the rows that can't open their tool's own page.
    public static func line(_ tool: Managing.Tool) -> String? {
        tool == .edit ? editLine : nil
    }

    /// An album's ••• (its page's bar): that album's page in the web app, its Edit one tap away.
    public static let editInWebApp = "Edit in the web app"

    /// Account's row (ownPassword.ts CHANGE_TITLE), and the line under it: where it is once open, and whose password
    /// it changes there - Safari's person's, who may not be the app's (Safari signs in apart).
    public static let changePassword = "Change password"
    public static let changePasswordLine = "Opens the web app's You: Change password is under Account there. It changes "
        + "the password of whoever is signed in in Safari."

    /// VoiceOver's hint on every row that opens Safari.
    public static let opensInSafari = "Opens in Safari."

    public static let opens = "These open in the web app, in Safari."
    /// With logins on: Safari signs in apart from the app - and each page is Safari's person's, not the app's: nothing
    /// compares the two.
    public static let signIn = "Safari has its own sign-in, apart from the app's: the first time, sign in there with the "
        + "same name and password you use here. The pages open as whoever is signed in there, who may not be who's "
        + "signed in here."
    /// deadwax out of reach: the rows are off.
    public static let offline = "These open once deadwax is back."

    /// iOS refused to open the address (Managing.notice(opened:)): said over the tabs, announced.
    public static let notOpened = "Couldn't open the web app - Safari may be turned off in Screen Time."

    /// The section's footer, a sentence a line: where they open (or, out of reach, when), then Safari's sign-in with
    /// logins on.
    public static func footer(loginsOn: Bool, online: Bool) -> [String] {
        [online ? opens : offline] + (loginsOn ? [signIn] : [])
    }

    /// The trailing sign on a row that opens elsewhere (where a pushed page's row has a chevron), and the menu item's.
    public static let outSymbol = "arrow.up.forward"
    public static let safariSymbol = "safari"
}
