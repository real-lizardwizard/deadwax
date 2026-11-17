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

    /// (Phase 8, slice 5) The artist page's tools (permissions.ts `ArtistManaging`): Artist images… and Which artist is
    /// this? Edit albums', Move albums to … Look after the library's.
    public struct ArtistManaging: Sendable, Equatable {
        public let images: Bool
        public let whichArtist: Bool
        public let move: Bool
        public let any: Bool

        public init(images: Bool, whichArtist: Bool, move: Bool, any: Bool) {
            self.images = images
            self.whichArtist = whichArtist
            self.move = move
            self.any = any
        }
    }

    /// permissions.ts `artistManaging(perms)`.
    public static func artistManaging(_ permissions: Set<Access.Permission>) -> ArtistManaging {
        let edit = permissions.contains(.edit), library = permissions.contains(.library)
        return ArtistManaging(images: edit, whichArtist: edit, move: library, any: edit || library)
    }

    /// (Phase 8, slice 6) permissions.ts `asksQueueSummary(perms)`: Needs a look's count is asked only with Look after
    /// the library - the server answers 403 otherwise.
    public static func asksQueueSummary(_ permissions: Set<Access.Permission>) -> Bool {
        permissions.contains(.library)
    }

    /// (slice 6) Needs a look's page for this person (App.tsx's `allowed={perms.has('library')}` and
    /// `canEdit={perms.has('edit')}`): whether it opens at all, and whether fixing an album is theirs - without Edit
    /// albums the page says NEEDS_EDIT, and the editor it opens has no Edit section.
    public struct NeedsLookPage: Sendable, Equatable {
        public let allowed: Bool
        public let canEdit: Bool

        public init(allowed: Bool, canEdit: Bool) {
            self.allowed = allowed
            self.canEdit = canEdit
        }
    }

    public static func needsLook(_ permissions: Set<Access.Permission>) -> NeedsLookPage {
        NeedsLookPage(allowed: permissions.contains(.library), canEdit: permissions.contains(.edit))
    }

    /// One of Manage's rows, in the order You draws them: the phone's own Edit an album first (the web's editors live
    /// on an album's page, not in You), then the web's five in You.tsx's order.
    public enum Tool: String, Sendable, CaseIterable, Hashable {
        case edit, queue, care, people, settings, log

        /// The app's own page (Phase 8 - one slice at a time): Edit an album since slice 1, Needs a look since slice 6,
        /// Library care since slice 7, Server settings since slice 8, the event log since slice 9, People since slice 11 -
        /// every row now, so nothing in Manage opens Safari (slice 12 takes the web app's way out away).
        public var native: Bool {
            switch self {
            case .edit, .queue, .care, .people, .settings, .log: return true
            }
        }
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

    /// Whether Account offers Change password (lib/ownPassword.ts `changeOffered`) - OwnPassword's rule (Phase 8, slice
    /// 10: the page is the app's own now), kept under this name for Manage's fixture.
    public static func changeOffered(_ me: Me?) -> Bool {
        OwnPassword.changeOffered(me)
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

    /// You's root in the web app: Account's Change password is in it, and has no address of its own. (Phase 8, slice 10:
    /// Account's row is the app's own page now - nothing opens this; slice 12 removes it with the rest.)
    public static let youFragment = "/you"

    /// A tool's page in the web app at this phone's deadwax; nil with no address.
    public static func url(_ tool: Tool, at server: ServerAddress?) -> URL? {
        url(fragment: fragment(tool), at: server)
    }

    /// An album's page in the web app (Edit album's rows still there - Tags, Artwork, Lyrics, Delete); nil with no
    /// address or no id.
    public static func albumURL(id: String, at server: ServerAddress?) -> URL? {
        id.isEmpty ? nil : url(fragment: albumFragment(id: id), at: server)
    }

    /// The web app's You (Account's Change password until Phase 8's slice 10; slice 12 removes it).
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

    /// The phone's own row for the editors (Phase 8, slice 1: the app's own - Choose the folder, then Edit album).
    public static let editAnAlbum = "Edit an album"

    /// Account's row (ownPassword.ts CHANGE_TITLE), and the line under it: where it is once open, and whose password
    /// it changes there - Safari's person's, who may not be the app's (Safari signs in apart). (Phase 8, slice 10: the
    /// row opens the app's own page - OwnPassword.title - and the line is drawn nowhere; slice 12 removes it.)
    public static let changePassword = "Change password"
    public static let changePasswordLine = "Opens the web app's You: Change password is under Account there. It changes "
        + "the password of whoever is signed in in Safari."

    /// VoiceOver's hint on every row that opens Safari.
    public static let opensInSafari = "Opens in Safari."

    public static let opens = "These open in the web app, in Safari."
    /// (Phase 8, slice 1) With Edit an album, the app's own now, above the rows that still open Safari.
    public static let othersOpen = "Edit an album is the app's own; the others open in the web app, in Safari."

    /// (slice 6) The same, of every row drawn that is the app's own (Tool.native), in Manage's order: "Edit an album and
    /// Needs a look are the app's own; the others open in the web app, in Safari."
    public static func othersOpen(_ native: [Managing.Tool]) -> String {
        let names = native.map(label)
        guard names.count > 1 else { return names.first.map { "\($0) is the app's own; \(rest)" } ?? opens }
        return "\(names.dropLast().joined(separator: ", ")) and \(names.last ?? "") are the app's own; \(rest)"
    }

    private static let rest = "the others open in the web app, in Safari."
    /// With logins on: Safari signs in apart from the app - and each page is Safari's person's, not the app's: nothing
    /// compares the two.
    public static let signIn = "Safari has its own sign-in, apart from the app's: the first time, sign in there with the "
        + "same name and password you use here. The pages open as whoever is signed in there, who may not be who's "
        + "signed in here."
    /// deadwax out of reach: the rows are off.
    public static let offline = "These open once deadwax is back."

    /// iOS refused to open the address (Managing.notice(opened:)): said over the tabs, announced.
    public static let notOpened = "Couldn't open the web app - Safari may be turned off in Screen Time."

    /// The section's footer, a sentence a line: where the rows that open Safari open (or, out of reach, when), then
    /// Safari's sign-in with logins on - nothing at all when every row drawn is the app's own (Edit an album since
    /// Phase 8's slice 1, Needs a look since slice 6, Library care since slice 7, Server settings since slice 8, the event
    /// log since slice 9, People since slice 11 - so since slice 11, never), whose pages say for themselves that they
    /// need deadwax.
    public static func footer(loginsOn: Bool, online: Bool, tools: [Managing.Tool] = Managing.Tool.allCases) -> [String] {
        let web = tools.filter { !$0.native }
        guard !web.isEmpty else { return [] }
        let native = tools.filter(\.native)
        let lead = !online ? offline : native.isEmpty ? opens : othersOpen(native)
        return [lead] + (loginsOn ? [signIn] : [])
    }

    /// The trailing sign on a row that opens elsewhere (where a pushed page's row has a chevron), and the menu item's.
    public static let outSymbol = "arrow.up.forward"
    public static let safariSymbol = "safari"
}
