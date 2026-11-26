import Foundation

// The redesign, slice R9 (notes/ios.md "The redesign, slice R9: Downloaded, Settings and Sign in"): Settings' pages as
// cards on the phone and as boxes on the Mac, Sign in as one screen (one dialog on the Mac), and the Mac's own
// Downloaded. What they draw that is a rule or a word of its own is here, pure and tested on Linux; everything else is
// the pages' existing words (YouWords, SignInWords, RequestWords, DownloadWords, GettingWords).

/// The account card at the top of Settings (iSettings' first card; James, 25 Nov, "Today's pages as cards" - the plan's
/// 3.8, answer 5): the round avatar's letter, the name, the address deadwax is at in the readout face, the role as a
/// chip, and Sign out - each from what /me last said (YouLines, Access) and the address in use.
public struct AccountCard: Sendable, Equatable {
    /// The avatar's letter: YouLines' - the signed-in user's first, a capital, else "d".
    public let letter: String
    /// The name: the user signed in, else "deadwax" (logins off).
    public let name: String
    /// Under the name: "No sign-in needed" with logins off, "…" while /me hasn't answered - YouLines' identity.
    public let identity: String?
    /// The address deadwax is at, as it is kept (`ServerAddress.description`) - nil before one is.
    public let address: String?
    /// The role's chip: "Admin" for an admin signed in - a Navidrome admin or break-glass. None for anyone else, and
    /// none with logins off, where everyone is the admin and "No sign-in needed" says so.
    public let role: String?
    /// Sign out is on the card: logins on (YouLines.account) - with them off there is nothing to sign out of.
    public let signsOut: Bool

    public init(lines: YouLines, access: Access, address: ServerAddress?) {
        letter = lines.avatar
        name = lines.name
        identity = lines.identity
        self.address = address?.description
        role = lines.account && access.isAdmin ? SettingsWords.admin : nil
        signsOut = lines.account
    }

    /// What VoiceOver reads for the card, one element: the name, the line under it, the role, the address.
    public var spoken: String {
        [name, identity, role, address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// R9's own words: the account card's role, the sign-in's two cards, and the Mac's Settings page.
public enum SettingsWords {
    /// The account card's chip for an admin (People's own tag for one, People.tags).
    public static let admin = "Admin"

    // MARK: Sign in (iSignIn, SignIn) - one screen, two cards

    /// The first card: the address, and Check.
    public static let whereTitle = "Where deadwax is"
    /// The second: the user name and the password.
    public static let whoTitle = "Who you are"
    /// The address field's name for VoiceOver, and the Server address screen's heading (Phase 0's words).
    public static let address = "deadwax's address"
    /// The address field's placeholder: an example of a private address (the Server address screen's).
    public static let addressExample = "http://192.168.1.20:8090"
    /// Check, and while it asks (the Server address screen's, Phase 0's).
    public static let check = "Check"
    public static let checking = "Checking\u{2026}"
    /// The chip once deadwax has answered at the address shown - before a sign-in, it answered and asked for one.
    public static let answered = "deadwax answered"
    /// Under Sign in: what is kept, and where (SessionStore: the Keychain on the phone, a file on the Mac) - and that the
    /// password never is (SignInForm forgets it after any answer).
    public static func kept(_ device: Device) -> String {
        switch device {
        case .iPhone: return "Your sign-in is kept in this phone's Keychain - never your password."
        case .mac: return "Your sign-in is kept in a file on this Mac - never your password."
        }
    }

    // MARK: the Mac's Settings (Settings.dc.html)

    /// The toolbar's line: with Server settings to open, where how deadwax runs is.
    public static func macLede(serverSettings: Bool) -> String {
        serverSettings ? "Your own choices. How deadwax itself runs is in Server settings." : "Your own choices."
    }
    /// The status bar's: every choice is kept the moment it is made.
    public static let macSaved = "Saved as you change them"
    /// The boxes' legends that aren't a page's title already (Playback, Getting albums, Account, About are).
    public static let downloadsBox = "Downloads"
    public static let freeSpace = "Free space"
    public static let showDownloaded = "Show Downloaded"
    /// The Downloads box's way to its lists - Downloading, Didn't download, Downloaded - the phone's Settings > Downloads.
    public static let downloadsList = "Downloading and downloaded\u{2026}"
    public static let signedInAs = "Signed in as"
    /// The Account box's row for where the sign-in is kept (SettingsWords.kept beside it).
    public static let keptLabel = "Kept"
    public static let changePassword = "Change password\u{2026}"
    public static let changeAddress = "Change address\u{2026}"
    /// Playback's EQ: the side panel's EQ opened (the drawing's "Open the EQ").
    public static let openEQ = "Open the EQ"
    /// The Downloads box's fact (the drawing's "38 albums · 412 songs · 11.4 GB"): what is on this device, by Settings >
    /// Downloads' own counts (DownloadShelf) - nothing yet said as the phone's Storage says it.
    public static func downloadsFact(albums: Int, songs: Int, bytes: Int64) -> String {
        guard songs > 0 else { return DownloadWords.nothingYetHeadline }
        return "\(albums) \(albums == 1 ? "album" : "albums") \u{00B7} \(DownloadWords.songs(songs)) \u{00B7} "
            + Bytes.words(bytes)
    }
}

/// Sign in's one screen (iSignIn; the build plan's section 8: "Sign in is one screen, as drawn, over today's two
/// screens' calls"): today's calls in today's order - Check (ServerModel.checkAddress: /health, then /me) and only then
/// Sign in (ServerModel.signIn), never Sign in before Check has answered for the address shown.
public enum SignInGate {
    /// The address typed is the one in use: it parses to it. Anything else - another address, or one that doesn't
    /// parse - hasn't been checked.
    public static func isChecked(typed: String, inUse: ServerAddress?) -> Bool {
        guard let inUse, case .success(let parsed) = ServerAddress.parse(typed) else { return false }
        return parsed == inUse
    }

    /// Whether Sign in can be pressed: deadwax answered at the address in use and asked for a sign-in (`asksSignIn`:
    /// the launch's 401, or a session ended under the app), the address shown is that one, no Check is out, and no sign-in
    /// is on its way.
    public static func signInOn(asksSignIn: Bool, typed: String, inUse: ServerAddress?, checking: Bool,
                                busy: Bool) -> Bool {
        asksSignIn && !checking && !busy && isChecked(typed: typed, inUse: inUse)
    }

    /// The chip under the address: deadwax answered there (it asked for a sign-in, or let you in), while the address
    /// shown is the one it answered at and no Check is out.
    public static func answered(asksSignIn: Bool, typed: String, inUse: ServerAddress?, checking: Bool) -> Bool {
        asksSignIn && !checking && isChecked(typed: typed, inUse: inUse)
    }

    /// (R9's review) Return in the password does what the button that is on would: Sign in once deadwax has answered at
    /// the address shown and asked for a sign-in, Check until then - never nothing while Sign in is off.
    public static func returnSignsIn(asksSignIn: Bool, typed: String, inUse: ServerAddress?) -> Bool {
        asksSignIn && isChecked(typed: typed, inUse: inUse)
    }
}

/// The Mac's Downloaded (Downloaded.dc.html): Albums | Playlists, Remove all…, the columns and the status bar - every
/// number DownloadModel's.
public enum MacDownloaded {
    public enum Tab: String, Sendable, CaseIterable {
        case albums, playlists
    }

    public enum Column: String, Sendable, CaseIterable {
        case name, artist, songs, size, here
    }

    public static func tabWords(_ tab: Tab) -> String {
        switch tab {
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        }
    }

    /// The columns each tab draws: a playlist has no artist.
    public static func columns(_ tab: Tab) -> [Column] {
        tab == .albums ? Column.allCases : [.name, .songs, .size, .here]
    }

    /// The drawing's widths (`.cols`): the name takes what the others leave.
    public static func width(_ column: Column) -> MacTable.Width {
        switch column {
        case .name: return .flexible
        case .artist: return .fixed(132)
        case .songs: return .fixed(62)
        case .size: return .fixed(82)
        case .here: return .fixed(158)
        }
    }

    public static func title(_ column: Column, tab: Tab, device: Device) -> String {
        switch column {
        case .name: return tab == .albums ? "Album" : "Playlist"
        case .artist: return "Artist"
        case .songs: return "Songs"
        case .size: return "Size"
        case .here: return DownloadWords.onThisDevice(device)
        }
    }

    /// Remove all…'s button - its dialog is Settings > Downloads' own (DownloadWords.removeAllTitle and its message).
    public static let removeAll = "Remove all\u{2026}"

    /// (R9's review) Find, as the Mac's Albums page finds (Shelf's rule): every word typed, folded, somewhere in the
    /// row's name and artist - a playlist's, its name (PlaylistRules.found's). Nothing typed finds every row.
    public static func finds(_ typed: String, name: String?, artist: String? = nil) -> Bool {
        let words = Find.words(typed)
        if words.isEmpty { return true }
        let text = FoldKey(Fold.findText(name) + " " + Fold.findText(artist))
        return words.allSatisfy { (word: FoldKey) -> Bool in text.contains(word) }
    }

    /// The Songs cell: how many are here, of how many the album has when it isn't all of them ("7 of 13").
    public static func songs(here: Int, of total: Int) -> String {
        here >= total ? "\(here)" : "\(here) of \(total)"
    }

    /// An album's On this Mac cell once its songs are here (the drawing's "today", "yesterday", "21 Nov"): when the last of
    /// them came (DownloadRecord.doneAt), in ArtistTotals' day words, the day turning with the calendar's. Nothing when
    /// no song says when.
    public static func when(_ doneAt: [Int64?], now: Int64, zone: TimeZone = .current) -> String {
        guard let last = doneAt.compactMap({ (at: Int64?) -> Int64? in at }).max(), last > 0 else { return "" }
        return ArtistTotals.lastPlayedWords(last, now: now, zone: zone)
    }

    /// The status bar (`.status`): "38 albums on this Mac", "412 songs", "11.4 GB", "1 downloading" - each only when it
    /// isn't nothing - and at its right the free space, "182 GB free".
    public static func status(albums: Int, songs: Int, bytes: Int64, downloading: Int, free: Int64?,
                              device: Device) -> (leading: [String], trailing: [String]) {
        var leading: [String] = []
        if albums > 0 { leading.append("\(albums) \(albums == 1 ? "album" : "albums") on this \(device.noun)") }
        if songs > 0 { leading.append(DownloadWords.songs(songs)) }
        if bytes > 0 { leading.append(Bytes.words(bytes)) }
        if downloading > 0 { leading.append("\(downloading) downloading") }
        let trailing = free.map { ["\(Bytes.words($0)) free"] } ?? []
        return (leading, trailing)
    }

    /// The same for the Playlists tab: "3 playlists on this Mac" and the songs and size of them here.
    public static func playlistsStatus(playlists: Int, songs: Int, bytes: Int64, free: Int64?,
                                       device: Device) -> (leading: [String], trailing: [String]) {
        var leading: [String] = []
        if playlists > 0 {
            leading.append("\(playlists) \(playlists == 1 ? "playlist" : "playlists") on this \(device.noun)")
        }
        if songs > 0 { leading.append(DownloadWords.songs(songs)) }
        if bytes > 0 { leading.append(Bytes.words(bytes)) }
        let trailing = free.map { ["\(Bytes.words($0)) free"] } ?? []
        return (leading, trailing)
    }
}

extension RequestWords {
    /// Settings > Getting albums' note under Confirm before cancelling, as each device's Requests asks: the phone's ✕ on
    /// a card (`confirmCancelNote`, word for word), the Mac's Cancel - and Leave, its other name when someone else asked
    /// too - on a row of its table (R8's MacRequestsPage: `RequestColumns.cancel`, ConfirmCancel read at the click).
    public static func cancelAsksNote(_ device: Device) -> String {
        switch device {
        case .iPhone: return confirmCancelNote
        case .mac: return "Cancel on a download in Requests asks first, and so does Leave. Kept on this Mac."
        }
    }
}
