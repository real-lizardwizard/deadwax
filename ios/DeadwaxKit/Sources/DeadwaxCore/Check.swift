import Foundation

/// What the Check button found, in the words it shows: whether deadwax answered, and who this
/// phone is to it.
public struct CheckReport: Sendable, Equatable {
    public enum Who: Sendable, Equatable {
        /// logins off: everyone is the shared account
        case shared(Me)
        /// logins on and signed in
        case signedIn(Me)
        /// logins on, and this phone has no session (or it ended)
        case needsSignIn
        /// /me failed for another reason
        case unknown(String)
    }

    public let health: Result<Health, DeadwaxError>
    public let who: Who?

    public init(health: Result<Health, DeadwaxError>, who: Who?) {
        self.health = health
        self.who = who
    }

    /// The report from the two answers. `/me` isn't asked when health failed.
    public static func from(health: Result<Health, DeadwaxError>, me: Result<Me, DeadwaxError>?) -> CheckReport {
        guard case .success = health, let me else { return CheckReport(health: health, who: nil) }
        switch me {
        case .success(let me):
            return CheckReport(health: health, who: me.loginsOn ? .signedIn(me) : .shared(me))
        case .failure(.signedOut):
            return CheckReport(health: health, who: .needsSignIn)
        case .failure(let error):
            return CheckReport(health: health, who: .unknown(error.words))
        }
    }

    public var ok: Bool {
        switch who {
        case .shared, .signedIn: return true
        default: return false
        }
    }

    public var needsSignIn: Bool { who == .needsSignIn }

    /// The lines shown under Check, first to last.
    public var lines: [String] {
        var lines: [String] = []
        switch health {
        case .failure(let error):
            return [error.words]
        case .success(let health):
            let version = health.version.map { " \($0)" } ?? ""
            if health.status == "ok" {
                lines.append("deadwax\(version) answered: OK.")
            } else {
                lines.append("deadwax\(version) answered, but says it isn't working: its download poller has \(health.poller ?? "stopped"). Restarting the container is the usual fix.")
            }
        }
        switch who {
        case .shared(let me)?:
            lines.append("Logins are off: everyone uses the shared account (\(me.user)).")
        case .signedIn(let me)?:
            lines.append("Logins are on: signed in as \(me.user)\(me.admin ? ", an admin" : "").")
        case .needsSignIn?:
            lines.append("Logins are on, and this phone isn't signed in. Sign in below with your Navidrome name and password.")
        case .unknown(let words)?:
            lines.append(words)
        case nil:
            break
        }
        return lines
    }
}
