import Foundation

/// Settings > Manage (Phase 7, notes/ios-specs/phase7-managing.md; Phase 8, phase8-managing.md): deadwax's managing
/// tools - the editors, Needs a look, Library care, People, Server settings and the event log. Phase 7 opened each
/// in the web app, in Safari; Phase 8 rebuilt them on the phone one slice at a time, and since slice 12 nothing here
/// addresses the web app at all (James: "nothing in the app should take you to the web app" -
/// tests/test_ios_no_web_app.py keeps it so). Which show is the web's rule (lib/permissions.ts `managing` and
/// `albumEdit`, by the permissions /me gives - Access). Held to the TypeScript by
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

    /// One of Manage's rows, in the order Settings draws them: the phone's own Edit an album first (the web's editors
    /// live on an album's page, not in You), then the web's five in You.tsx's order - each the app's own page (Edit an
    /// album since Phase 8's slice 1, Needs a look since slice 6, Library care since 7, Server settings since 8, the
    /// event log since 9, People since 11).
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

    /// Whether Account offers Change password (lib/ownPassword.ts `changeOffered`) - OwnPassword's rule (Phase 8, slice
    /// 10: the page is the app's own now), kept under this name for Manage's fixture.
    public static func changeOffered(_ me: Me?) -> Bool {
        OwnPassword.changeOffered(me)
    }
}

/// Manage's words: the web's where the web says them (You.tsx's title and rows, ownPassword.ts's CHANGE_TITLE - held by
/// the fixture), the phone's own for its own row, Edit an album.
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

    /// Account's row (ownPassword.ts CHANGE_TITLE): since Phase 8's slice 10 it opens the app's own page
    /// (OwnPassword.title), and is held to the web's here for Manage's fixture.
    public static let changePassword = "Change password"
}
