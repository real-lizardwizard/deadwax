import Foundation

/// The Navidrome gate (app/NeedsNavidrome.tsx, its check lib/navidromeCheck.ts): what the Library shows in place of
/// its albums when deadwax has no Navidrome to play from, or can't reach it - since the library IS what Navidrome
/// lists. Asked through `GET /deadwax/navidrome/status` (NavidromeStatus).
///
/// A listener (not `Access.seesDetail`) reads that their music isn't available, in their words, and what they can do -
/// try again, or tell whoever runs deadwax - never Navidrome's address, its error or a setting's name. Whoever runs
/// deadwax reads Navidrome's own words (the status's `problem`) and why the library needs it; an admin also gets Set up
/// Navidrome. The phone has no Server settings until Phase 7, so that button opens deadwax's own app (`/player/`) in
/// Safari, and its line keeps the web's words (D8).
///
/// Held to the web by Tests/DeadwaxCoreTests/Fixtures/gate/navidrome.json (ios/scripts/export-gate-vectors.cjs, which
/// runs NeedsNavidrome.tsx as it is; ui/test/iosgate.sim.cjs checks it is current).
public enum NavidromeGate {
    /// What a check of Navidrome found: the status deadwax answered, or - the check failing - set up but not
    /// answering, with `offline` when it was deadwax itself that didn't answer (navidromeCheck.ts).
    public struct Checked: Sendable, Equatable {
        public let status: NavidromeStatus
        public let offline: Bool

        public init(status: NavidromeStatus, offline: Bool = false) {
            self.status = status
            self.offline = offline
        }

        /// deadwax answered the status route.
        public static func answered(_ status: NavidromeStatus) -> Checked { Checked(status: status) }

        /// The check failed (navidromeChecks' rejection): Navidrome taken as set up but not answering, its problem the
        /// failure's own words (`problem`, for whoever runs deadwax), and `offline` when nothing answered at all - fetch's
        /// TypeError on the web, `APIFailure.offline` here (ErrorWords.kind) - not a timeout, not an answer that is an
        /// error.
        public static func failed(_ error: any Error, problem: String) -> Checked {
            Checked(status: NavidromeStatus(configured: true, ok: false, server: nil, problem: problem),
                    offline: ErrorWords.kind(of: error) == .offline)
        }
    }

    /// What the gate draws.
    public enum Shown: Sendable, Equatable {
        /// What it guards: the Library.
        case open
        /// Its spinner ("Connecting"): nothing found yet.
        case connecting
        /// Why not, and what to do about it.
        case closed(Closed)
    }

    /// The gate closed: its heading, its lines in order, and its buttons.
    public struct Closed: Sendable, Equatable {
        public let title: String
        /// Each line as the web draws it, an empty one (a status with no problem) left out.
        public let lines: [String]
        /// Try again (asks Navidrome again) - when it is set up.
        public let tryAgain: Bool
        /// Set up Navidrome - an admin's, when it isn't set up.
        public let setUp: Bool
    }

    // MARK: the words (NeedsNavidrome.tsx)

    public static let connecting = "Connecting"
    public static let musicUnavailable = "Your music isn't available right now"
    public static let musicNotYet = "Your music isn't available yet"
    /// Above the gate's own Try again: the advice leaves trying again to it.
    public static let musicUnreached = "\(ErrorWords.down[.music] ?? "") If it keeps happening, tell whoever runs deadwax."
    /// ...when it was deadwax itself that didn't answer: the music server may be fine.
    public static let deadwaxUnreached = "\(ErrorWords.offline) \(ErrorWords.offlineRetry)"
    public static let musicUnset = "deadwax hasn't been connected to a music server yet. \(ErrorWords.tell)"
    /// Someone with Settings and the log who isn't an admin: Navidrome's rows are an admin's alone.
    public static let adminSetsUp = "An admin can set it up in Server settings (Connections)."
    public static let navidromeRequired = "deadwax needs Navidrome for your library: the app shows and plays the albums "
        + "Navidrome lists, through deadwax - so the phone never needs Navidrome's password."
    public static let navidromeUnreached = "Your library comes from Navidrome, so it shows here once deadwax can reach it."
    /// An admin's, after navidromeRequired (D8: the words kept, the button opening /player/ in Safari).
    public static let setItUp = "Set it up in Server settings (Connections), then come back."
    public static let cantReach = "Can't reach Navidrome"
    public static let connect = "Connect Navidrome"
    public static let tryAgain = "Try again"
    public static let setUp = "Set up Navidrome"
    /// Where Set up Navidrome goes: deadwax's own app, whose Server settings set Navidrome up (Phase 7 brings the
    /// phone's links into it).
    public static let setUpPath = "/player/"

    /// Set up Navidrome's address: deadwax's own app, at the server this phone uses.
    public static func setUpURL(_ server: ServerAddress) -> URL? {
        URL(string: server.base.absoluteString + setUpPath)
    }

    // MARK: the rule

    /// What the gate draws for what the last check found (nil: none has yet), for `access` (NeedsNavidrome).
    public static func shown(_ checked: Checked?, access: Access) -> Shown {
        guard let checked else { return .connecting }
        let status = checked.status
        if status.ok { return .open }
        if !access.seesDetail {
            let line = checked.offline ? deadwaxUnreached : status.configured ? musicUnreached : musicUnset
            return .closed(Closed(title: status.configured ? musicUnavailable : musicNotYet, lines: [line],
                                  tryAgain: status.configured, setUp: false))
        }
        let problem = status.problem ?? ""
        if status.configured {
            return .closed(Closed(title: cantReach, lines: [problem, navidromeUnreached].filter { !$0.isEmpty },
                                  tryAgain: true, setUp: false))
        }
        let how = "\(navidromeRequired) \(access.isAdmin ? setItUp : adminSetsUp)"
        return .closed(Closed(title: connect, lines: [problem, how].filter { !$0.isEmpty }, tryAgain: false,
                              setUp: access.isAdmin))
    }

    /// The phone's gate (its own rule, not the web's): before the first check has found anything, the Library is drawn
    /// rather than the spinner - its list kept on disk draws at once (D2), or its own loading shows - and only a check
    /// that finds Navidrome isn't there closes it. Once something is found it is `shown`'s.
    public static func shownOnPhone(_ checked: Checked?, access: Access) -> Shown {
        guard let checked else { return .open }
        return shown(checked, access: access)
    }
}
