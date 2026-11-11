import Foundation

/// What went wrong, in a listener's words - the web app's ui/src/lib/errorWords.ts ported line for line, with
/// lib/signIn.ts's sign-in sentences and the player's media-error words beside it. Every sentence, the class order,
/// the advice and the plumbing test are the web's; Tests/DeadwaxCoreTests/Fixtures/errors/error-words.json holds
/// what the TypeScript itself answers (ios/scripts/export-error-words.cjs), and ErrorWordsTests replays it here.
///
/// THE CLASSES (`kind(of:)`), from what the error is - never from its words, but for `plumbing`:
///
///  - offline: the request never reached deadwax (`APIFailure.offline`) - the phone off the network, the VPN down,
///    deadwax restarting.
///  - timeout: a 408 or 504, or no answer in time (`APIFailure.timeout`).
///  - unreachable: a 502 or 503 with no words fit for anyone - deadwax answered, and what it needed behind it
///    didn't (Navidrome, slskd). Said by whose answer it was (`service`, else `service(of:)`: the route).
///  - not-found: a 404 - said by the caller (`gone`), else deadwax's words, never FastAPI's bare "Not Found".
///  - not-allowed: a 401 (the sign-in comes up over it anyway) or a 403 - a 403's words are deadwax's own.
///  - refused: deadwax said no in words written for whoever reads them - a 4xx, or a 502/503, whose detail passes
///    `plumbing`; any answer deadwax split in two (`detail` for anyone, `why` for whoever runs it); or any refusal
///    it named a `kind` of. Its words as written - a user's name in them is never re-cased.
///  - other: anything else - a 500, an answer the app couldn't read.
///
/// `plumbing` is the one test of words: a sentence naming a setting (DB_PATH), an address, an exception, an errno,
/// a file path or slskd is never a listener's line. Its patterns are the web's regular expressions written out for
/// ICU so they match exactly what JavaScript's do: `\b` as lookarounds on ASCII word characters, `/i` as both cases
/// of each letter, `\s` as JavaScript's own set, `$` as the end of the input.
///
/// A raw error's words go only to someone who runs deadwax (`admin`: `Access.seesDetail`), and a player failure's
/// only to Debug's "Last failure".
public enum ErrorWords {
    /// What kind of failure it was (errorWords.ts ErrorKind).
    public enum Kind: String, Sendable, CaseIterable {
        case offline, timeout, unreachable
        case notFound = "not-found"
        case notAllowed = "not-allowed"
        case refused, other
    }

    /// Whose answer an error is: the music server's (the Navidrome routes), the downloads' (slskd's), or deadwax's.
    public enum Service: String, Sendable, CaseIterable {
        case music, downloads, deadwax
    }

    /// What went wrong, for one reader.
    public struct Line: Sendable, Equatable {
        public let kind: Kind
        /// What happened, for everyone.
        public let text: String
        /// What to do about it - "" when the text says it, or there's nothing to do.
        public let advice: String
        /// The error's own words, for someone who runs deadwax - nil for a listener, and when they'd add nothing.
        public let detail: String?

        public init(kind: Kind, text: String, advice: String, detail: String?) {
            self.kind = kind
            self.text = text
            self.advice = advice
            self.detail = detail
        }

        /// The sentence and its advice as one line.
        public var said: String { ErrorWords.said(text: text, advice: advice) }
    }

    // MARK: the sentences

    /// What a listener can always do about a problem only whoever runs deadwax can fix.
    public static let tell = "Tell whoever runs deadwax."
    /// Said to a listener after a problem that should pass: the try again, and the tell if it doesn't.
    static let keeps = "if it keeps happening, tell whoever runs deadwax."
    static let keepsTold = "If it keeps happening, tell whoever runs deadwax."

    public static let offline = "Can't connect to deadwax."
    public static let offlineAdvice = "Check your connection, then try again."
    /// ...beside a Try again the page draws itself.
    public static let offlineRetry = "Check your connection."
    public static let timeout = "That took too long."
    public static let signedOut = "Your sign-in has ended - sign in again."
    public static let notAllowed = "You don't have permission for that."
    public static let gone = "It isn't there any more."
    public static let other = "Something went wrong."

    /// An unreachable's sentence, by whose answer it was.
    public static let down: [Service: String] = [
        .music: "Can't reach the music server right now.",
        .downloads: "Downloads aren't working right now.",
        .deadwax: "deadwax can't do that right now.",
    ]

    // MARK: the classes

    /// Whose answer an error was, from the route that gave it: the Navidrome routes' the music server's, the
    /// downloads' and slskd's the downloads', anything else - and anything nothing answered - deadwax's own.
    public static func service(of error: any Error) -> Service {
        let path = (error as? APIFailure)?.answer?.path ?? ""
        if path.hasPrefix("/navidrome") { return .music }
        if path.hasPrefix("/download") || path.hasPrefix("/monitor_slskd") { return .downloads }
        return .deadwax
    }

    /// Which class an error is (see the head of this file).
    public static func kind(of error: any Error) -> Kind {
        switch error as? APIFailure {
        case .answered(let answer)?:
            // a refusal deadwax named a kind of is its own words for whoever asked, whatever its status
            if present(answer.kind) && answer.status != 401 && fit(answer.detail) { return .refused }
            if answer.status == 401 || answer.status == 403 { return .notAllowed }
            if answer.status == 404 { return .notFound }
            if answer.status == 408 || answer.status == 504 { return .timeout }
            // deadwax split it in two itself: its detail is written for anyone
            if present(answer.why) && present(answer.detail) { return .refused }
            // deadwax's routes say why in their own words - kept where they hold no plumbing
            if (answer.status == 502 || answer.status == 503) && fit(answer.detail) { return .refused }

            if answer.status == 502 || answer.status == 503 { return .unreachable }
            if answer.status >= 400 && answer.status < 500 && fit(answer.detail) { return .refused }
            return .other
        case .offline?:
            return .offline
        case .timeout?:
            return .timeout
        case .other?:
            return .other
        case nil:
            guard let code = (error as? URLError)?.code else { return .other }
            if code == .timedOut { return .timeout }
            return APIFailure.isOffline(code) ? .offline : .other
        }
    }

    /// The error's own words, as whoever runs deadwax is shown them: the server's why, else its detail, else
    /// "METHOD /path failed"; the system's words when nothing answered.
    public static func rawWords(_ error: any Error) -> String {
        switch error as? APIFailure {
        case .answered(let answer)?:
            return words(answer.why) ?? words(answer.detail) ?? answer.fallback
        case .offline(let none)?, .timeout(let none)?:
            return none.reason
        case .other(let words)?:
            return words
        case nil:
            return (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    /// What went wrong, for the reader `admin` says.
    ///
    /// - Parameters:
    ///   - admin: the reader runs deadwax (`Access.seesDetail`): the detail too, and never "tell whoever runs deadwax".
    ///   - service: whose answer it was - an unreachable's sentence (`down`); else the route's.
    ///   - gone: a 404's sentence - "This album isn't here any more...".
    ///   - failed: what didn't work, said in place of an unreachable's or an other's sentence.
    ///   - retry: the page draws its own Try again beside the line - the advice leaves trying again to it.
    public static func of(_ error: any Error, admin: Bool = false, service: Service? = nil, gone: String? = nil,
                          failed: String? = nil, retry: Bool = false) -> Line {
        let service = service ?? self.service(of: error)
        let kind = self.kind(of: error)
        let answer = (error as? APIFailure)?.answer
        let text: String
        let advice: String
        switch kind {
        case .offline:
            text = offline
            advice = retry ? offlineRetry : offlineAdvice
        case .timeout:
            text = timeout
            advice = retry ? "" : "Try again."
        case .unreachable:
            text = failed ?? down[service] ?? other
            advice = retry ? (admin ? "" : keepsTold) : admin ? "Try again in a minute." : "Try again in a minute - \(keeps)"
        case .notFound:
            // the caller's own sentence; else deadwax's, else ours
            text = gone ?? (fit(answer?.detail) ? answer?.detail ?? Self.gone : Self.gone)
            advice = ""
        case .notAllowed:
            text = answer?.status == 401 ? signedOut : fit(answer?.detail) ? answer?.detail ?? notAllowed : notAllowed
            advice = ""
        case .refused:
            // the server's words as it wrote them
            text = answer?.detail ?? ""
            // deadwax's own split 503: only whoever runs it can fix it - and its own words for a 5xx, which may pass
            if let answer, !admin, answer.status >= 500 {
                advice = present(answer.why) ? (answer.status == 503 ? tell : "") : keepsTold
            } else {
                advice = ""
            }
        case .other:
            text = failed ?? other
            advice = retry ? (admin ? "" : keepsTold) : admin ? "Try again." : "Try again - \(keeps)"
        }
        let raw = trim(rawWords(error))
        let detail = admin && !raw.isEmpty && !same(raw, text) ? raw : nil
        return Line(kind: kind, text: text, advice: advice, detail: detail)
    }

    /// The sentence and its advice, as one line - a full stop between them where the server's words left none.
    public static func said(text: String, advice: String) -> String {
        if advice.isEmpty { return text }
        if text.isEmpty { return advice }
        return "\(endsASentence(text) ? text : "\(text).") \(advice)"
    }

    /// One line, for a store that keeps words rather than errors (a notice): `lead`, what went wrong and what to do -
    /// and, for whoever runs deadwax, the error's own words in brackets after it (errorWords.ts noticeWords).
    public static func notice(_ lead: String, _ error: any Error, admin: Bool = false, service: Service? = nil,
                              gone: String? = nil, failed: String? = nil, retry: Bool = false) -> String {
        let words = of(error, admin: admin, service: service, gone: gone, failed: failed, retry: retry)
        let line = [lead, words.said].filter { !$0.isEmpty }.joined(separator: " ")
        if let detail = words.detail, !detail.isEmpty { return "\(line) (\(detail))" }
        return line
    }

    /// Server words a listener may see as they are - or `fallback` in their place when they hold plumbing.
    public static func safeWords(_ text: String?, fallback: String) -> (text: String, detail: String?) {
        let raw = trim(text ?? "")
        if raw.isEmpty { return (fallback, nil) }
        if plumbing(raw) { return (fallback, raw) }
        return (raw, nil)
    }

    // MARK: the words themselves

    /// Whether `text` holds something a listener should never be shown as their line: a setting's name, an address,
    /// an exception, an errno, a path, slskd, a status.
    public static func plumbing(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return plumbingPatterns.contains { $0.test(text) }
    }

    /// errorWords.ts PLUMBING, each written out for ICU (see the head of this file).
    static let plumbingPatterns: [JSRegex] = [
        // /https?:\/\//i
        JSRegex(#"[Hh][Tt][Tt][Pp][Ss]?://"#),
        // /\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b/
        JSRegex(#"(?<![A-Za-z0-9_])[A-Z][A-Z0-9]*_[A-Z0-9_]+(?![A-Za-z0-9_])"#),
        // /\b[A-Za-z]*(Error|Exception)\b/
        JSRegex(#"(?<![A-Za-z0-9_])[A-Za-z]*(?:Error|Exception)(?![A-Za-z0-9_])"#),
        // /Errno|Traceback|HTTPConnectionPool|Max retries|\bhost=|\bport=/
        JSRegex(#"Errno|Traceback|HTTPConnectionPool|Max retries|(?<![A-Za-z0-9_])host=|(?<![A-Za-z0-9_])port="#),
        // /\b(GET|POST|PUT|DELETE|PATCH) \//
        JSRegex(#"(?<![A-Za-z0-9_])(?:GET|POST|PUT|DELETE|PATCH) /"#),
        // /(^|[\s('"])\/[\w.-]+\/[\w./-]*/
        JSRegex(#"(?:^|[\#(jsSpace)('"])/[A-Za-z0-9_.\-]+/[A-Za-z0-9_./\-]*"#),
        // /\bslskd\b|\bSubsonic\b/i
        JSRegex(#"(?<![A-Za-z0-9_])[Ss][Ll][Ss][Kk][Dd](?![A-Za-z0-9_])|(?<![A-Za-z0-9_])[Ss][Uu][Bb][Ss][Oo][Nn][Ii][Cc](?![A-Za-z0-9_])"#),
        // /\banswered [1-5]\d\d\b|\bHTTP [1-5]\d\d\b/
        JSRegex(#"(?<![A-Za-z0-9_])answered [1-5][0-9][0-9](?![A-Za-z0-9_])|(?<![A-Za-z0-9_])HTTP [1-5][0-9][0-9](?![A-Za-z0-9_])"#),
        // another program's own words, relayed: /\b(Navidrome|MusicBrainz) said\b/
        JSRegex(#"(?<![A-Za-z0-9_])(?:Navidrome|MusicBrainz) said(?![A-Za-z0-9_])"#),
    ]

    /// JavaScript's `\s` (WhiteSpace and LineTerminator), as the inside of an ICU set: NEL is not in it, the BOM is.
    static let jsSpace = #"\x{09}\x{0A}\x{0B}\x{0C}\x{0D}\x{20}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}"#

    /// The first letter up, and a full stop where the server left none - its words as a sentence. Never "Deadwax"
    /// or "Slskd": both are lower-case names, at a sentence's start too.
    public static func asSentence(_ text: String) -> String {
        let trimmed = trim(text)
        if trimmed.isEmpty { return trimmed }
        let upper = startsWithName(trimmed) ? trimmed : upperFirst(trimmed)
        return endsASentence(upper) ? upper : "\(upper)."
    }

    /// asSentence, for words that can begin with a file's name: a sentence that starts with one of `names` keeps
    /// its case and only gains its full stop (src/track_tags.py writes "intro.flac couldn't be read as audio").
    public static func asSentence(_ text: String, keeping names: [String]) -> String {
        let trimmed = trim(text)
        if !names.contains(where: { !$0.isEmpty && trimmed.utf16.starts(with: $0.utf16) }) { return asSentence(text) }
        return endsASentence(trimmed) ? trimmed : "\(trimmed)."
    }

    // MARK: a download's own reasons

    /// One reason the server writes into a job's `error`, in a listener's words; `tell`: only whoever runs deadwax
    /// can put it right.
    public struct JobReason: Sendable, Equatable {
        public let reason: String
        public let text: String
        public let tell: Bool
    }

    /// Why a download stopped, or why it didn't file - every string src/poller.py, src/store.py and
    /// src/routes/download.py write there (errorWords.ts JOB_ERRORS, in its order).
    public static let jobErrors: [JobReason] = [
        JobReason(reason: "the peer refused to send it", text: "The person sharing it refused to send it.", tell: false),
        JobReason(reason: "the peer stopped responding", text: "The person sharing it stopped responding.", tell: false),
        JobReason(reason: "the transfer errored", text: "The download broke off.", tell: false),
        JobReason(reason: "the transfer was cancelled", text: "The download was cancelled before it finished.", tell: false),
        JobReason(reason: "the transfer failed", text: "The download didn't finish.", tell: false),
        JobReason(reason: "no transfers reported by slskd", text: "deadwax lost track of this download - the person sharing it may have gone offline, or downloads stopped working for a while.", tell: false),
        JobReason(reason: "cancelled from deadwax", text: "Cancelled.", tell: false),
        JobReason(reason: "dry run - not organized", text: "Downloaded, but not added to your library: deadwax is set to rehearse adding albums, without moving any files.", tell: true),
        JobReason(reason: "nothing could be organized, check SLSKD_DOWNLOAD_PATH", text: "It downloaded, but deadwax couldn't find its files to add them to your library.", tell: true),
        JobReason(reason: "deadwax stopped while filing this - check the library and slskd's folder", text: "deadwax stopped while it was adding this to your library.", tell: true),
    ]

    /// A download's `error`, in a listener's words.
    public struct JobWords: Sendable, Equatable {
        /// The reason, for everyone.
        public let text: String
        /// Only whoever runs deadwax can put it right: a listener is told so (`tell`).
        public let tell: Bool
        /// The job's own words, for someone who runs deadwax - nil when the text is them.
        public let detail: String?

        public init(text: String, tell: Bool, detail: String?) {
            self.text = text
            self.tell = tell
            self.detail = detail
        }
    }

    /// A download's `error`, in a listener's words. Unknown words pass through when they are fit to (`safeWords`).
    public static func jobErrorWords(_ error: String?) -> JobWords {
        let raw = trim(error ?? "")
        if raw.isEmpty { return JobWords(text: "", tell: false, detail: nil) }
        let arrived = arrivedPattern.groups(raw)
        let reason = arrived?[0] ?? raw
        let known = jobErrors.first { same($0.reason, reason) }
        var tell = known?.tell == true
        var text: String
        if let known {
            text = known.text
        } else if reason.utf16.starts(with: "organize failed:".utf16) {
            // the filing's own messages, which carry a number or an exception (poller.py)
            text = "It downloaded, but couldn't be added to your library."
            tell = true
        } else if noTrackFiledPattern.test(reason) {
            text = "It downloaded, but none of its songs could be added to your library."
            tell = true
        } else if failedToOrganizePattern.test(reason) {
            let count = number(String(reason.prefix { $0 != " " }))
            text = "\(count) \(count == "1" ? "file" : "files") couldn't be added to your library."
            tell = true
        } else if alreadyExistedPattern.test(reason) {
            text = "Its files were already in the collection, so nothing was added."
        } else if alreadyInStorePattern.test(reason) {
            text = "Every song was already in the collection, so nothing was added."
        } else {
            let safe = safeWords(reason, fallback: "It stopped, and deadwax couldn't say why.")
            text = safe.text
            tell = safe.detail != nil
        }
        if let arrived {
            let done = number(arrived[1])
            let total = number(arrived[2])
            text = "\(text) \(done) of \(total) \(total == "1" ? "file" : "files") arrived."
        }
        return JobWords(text: text, tell: tell, detail: same(raw, text) ? nil : raw)
    }

    /// "3 of 10 file(s) arrived" after a failure's reason (poller.py): /^(.*) \((\d+) of (\d+) file\(s\) arrived\)$/.
    static let arrivedPattern = JSRegex(#"^([^\x{0A}\x{0D}\x{2028}\x{2029}]*) \(([0-9]+) of ([0-9]+) file\(s\) arrived\)\z"#)
    static let noTrackFiledPattern = JSRegex(#"^[0-9]+ file\(s\) failed to organize, no track was filed\z"#)
    static let failedToOrganizePattern = JSRegex(#"^[0-9]+ file\(s\) failed to organize\z"#)
    static let alreadyExistedPattern = JSRegex(#"^all [0-9]+ file\(s\) already existed, nothing was filed\z"#)
    static let alreadyInStorePattern = JSRegex(#"^already in the store: all [0-9]+ track\(s\) were already there, nothing was filed\z"#)

    // MARK: You -> Connections

    /// The short word on a Connections row for each code a ping answers with.
    public static let pingStatus: [String: String] = [
        "CONNECTION_ERROR": "Can't reach it",
        "NOT_SET_UP": "Not set up",
        "401": "Key refused",
        "502": "Not running",
        "NOT_LOGGED_IN": "Not on Soulseek",
        "NOT_CONNECTED": "Not on Soulseek",
        "CONNECTING": "Connecting\u{2026}",
        "NO_STATE": "Unclear",
        "UNKNOWN_HTTP_ERROR": "Unexpected answer",
        "UNKNOWN_ERROR": "Unexpected problem",
        "MAX_RETRIES_EXCEEDED": "No answer",
        "VALUE_ERROR": "Not set up",
        "503": "Busy",
        "429": "Busy",
        "403": "Refused",
        "400": "Refused",
        "404": "Not found",
    ]

    /// MusicBrainz's ping row's sentence, by code.
    public static let musicBrainzLines: [String: String] = [
        "CONNECTION_ERROR": "deadwax can't reach MusicBrainz - check the container can reach the internet.",
        "MAX_RETRIES_EXCEEDED": "MusicBrainz didn't answer after a few tries - it often goes away for a few minutes.",
        "503": "MusicBrainz is busy - it often is for a few minutes at a time.",
        "429": "MusicBrainz is asking deadwax to slow down - it will answer again shortly.",
        "403": "MusicBrainz turned deadwax away - usually the contact in MUSICBRAINZ_EMAIL (Server settings, Connections).",
        "400": "MusicBrainz refused the question deadwax asked - the log has the details.",
        "404": "MusicBrainz has nothing at the address deadwax asked - the log has the details.",
        "VALUE_ERROR": "No contact is set for MusicBrainz - set MUSICBRAINZ_EMAIL in Server settings (Connections).",
        "UNKNOWN_HTTP_ERROR": "MusicBrainz answered with an error deadwax doesn't know - the log has the details.",
        "UNKNOWN_ERROR": "Asking MusicBrainz failed in a way deadwax doesn't know - the log has the details.",
    ]

    /// Which connection a ping row is.
    public enum Ping: String, Sendable { case musicbrainz, slskd }

    /// A failed ping's row: its word, and the sentence under it (`code` as the ping sent it - a number as its digits).
    public static func pingWords(_ service: Ping, code: String?, error: String?) -> (text: String, line: String?) {
        let key = code ?? ""
        let text = pingStatus[key] ?? "Not connected"
        let said = error?.isEmpty == false ? error : nil
        let line = service == .musicbrainz ? musicBrainzLines[key] ?? said : said
        return (text, line)
    }

    /// A ping that got no answer from deadwax at all.
    public static let pingUnanswered = "Couldn't check"

    /// The sentence under a "Couldn't check" row - only ever drawn for whoever runs deadwax.
    public static func unansweredLine(_ error: any Error) -> String {
        notice("", error, admin: true)
    }

    // MARK: signing in (lib/signIn.ts)

    /// What deadwax says to a request with no session at all - the sign-in screen's own lede says it already.
    public static let plainSignIn = "Sign in to use deadwax."
    /// deadwax not reached at all.
    public static let unreached = "Can't reach deadwax. Check you're on the right network (or your VPN is on) and try again."
    /// An answer with no words of deadwax's own - a 500, something in front of it.
    public static let serverFailed = "Something went wrong on the server - try again in a moment."
    /// The heading over what whoever runs deadwax needs (`signInWhy`), folded under the sentence.
    public static let forWhoever = "For whoever runs deadwax"

    /// What the sign-in screen says about a sign-in that failed: deadwax's own words where it sent some fit to show
    /// (a wrong password, too many tries, Navidrome not answering); otherwise what kind of failure it was, plainly.
    public static func signInProblem(_ error: any Error) -> String {
        guard let answer = (error as? APIFailure)?.answer else { return unreached }
        if let detail = words(answer.detail), !plumbing(detail) {
            // deadwax's split 503 (logins it can't run, its database) is a problem only whoever runs it can fix
            return present(answer.why) && answer.status == 503 ? "\(asSentence(detail)) \(tell)" : detail
        }
        if answer.status == 401 { return "That user name and password didn't work." }
        if answer.status == 429 { return "Too many tries - wait a minute and try again." }
        return serverFailed
    }

    /// What whoever runs deadwax needs beside the sign-in's sentence - the server's `why`, or a detail too technical
    /// for the sentence - shown folded under `forWhoever`. Nil when there is nothing more.
    public static func signInWhy(_ error: any Error) -> String? {
        guard let answer = (error as? APIFailure)?.answer else { return nil }
        if let why = words(answer.why) { return why }
        if let detail = words(answer.detail), plumbing(detail) { return detail }
        return nil
    }

    /// Why the sign-in screen is showing, said above the form - nothing for the plain "sign in".
    public static func reasonShown(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let text = trim(detail)
        return text.isEmpty || same(text, plainSignIn) ? nil : text
    }

    // MARK: the player's

    /// HTMLMediaElement's error codes, as the player's failures are named by them.
    public enum MediaError: Int, Sendable {
        case aborted = 1, network = 2, decode = 3, unsupported = 4
    }

    /// A song that wouldn't play, in a listener's words, by its error's code (usePlayer.ts describeMediaError).
    public static func media(_ code: Int?) -> String {
        switch code.flatMap(MediaError.init(rawValue:)) {
        case .network?: return "The connection dropped while this song was loading"
        case .decode?: return "This device couldn't play this song's audio"
        // also what a failed request looks like from the element
        case .unsupported?: return "Couldn't play this song - it didn't come as audio this device can play"
        default: return "Couldn't play this song"
        }
    }

    /// Why the song before this one was passed over, named - shown under the NEXT song (usePlayer.ts skipNotice).
    public static func skipped(title: String, code: Int?) -> String {
        code == MediaError.decode.rawValue
            ? "Skipped \"\(title)\" - this device couldn't play its audio"
            : "Skipped \"\(title)\" - it wouldn't play"
    }

    // MARK: pages' own

    /// An album page whose album Navidrome no longer has (a 404) - AlbumPage.tsx ALBUM_GONE.
    public static let albumGone = "This album isn't here any more - it may have been moved or deleted."
    /// An artist the music server no longer has - ArtistPage.tsx ARTIST_GONE.
    public static let artistGone = "This artist isn't here any more - their albums may have been moved or deleted."
    /// Over a list that couldn't be asked again - the list below stays as it was (LibrarySection.tsx COULDNT_REFRESH).
    public static let couldntRefresh = "Couldn't update this list - showing it as it was."

    // MARK: JavaScript's string rules

    /// Words a server answer may be shown by as they are: there, not FastAPI's bare "Not Found", and no plumbing.
    static func fit(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return !same(trim(text), "Not Found") && !plumbing(text)
    }

    /// JavaScript's truthiness of a string: there and not empty.
    static func present(_ text: String?) -> Bool { words(text) != nil }

    static func words(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// JavaScript's `===` on strings: the same UTF-16 code units (Swift's `==` would also equate canonically
    /// equivalent spellings).
    static func same(_ one: String, _ other: String) -> Bool { one.utf16.elementsEqual(other.utf16) }

    /// JavaScript's String.prototype.trim: its WhiteSpace and LineTerminator characters off both ends.
    static func trim(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isJSSpace($0) }) else { return "" }
        let last = scalars.lastIndex(where: { !isJSSpace($0) }) ?? first
        return String(scalars[first...last])
    }

    static func isJSSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// /[.!?…]$/
    static func endsASentence(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        return [".", "!", "?", "\u{2026}"].contains(last)
    }

    /// /^(deadwax|slskd)\b/
    static func startsWithName(_ text: String) -> Bool {
        let units = Array(text.utf16)
        for name in ["deadwax", "slskd"] {
            let spelled = Array(name.utf16)
            guard units.starts(with: spelled) else { continue }
            if units.count == spelled.count || !isWordUnit(units[spelled.count]) { return true }
        }
        return false
    }

    static func isWordUnit(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: return true
        default: return false
        }
    }

    /// `text.charAt(0).toUpperCase() + text.slice(1)`: the first UTF-16 unit upper-cased - so a first character
    /// outside the Basic Multilingual Plane (a surrogate) is left as it is.
    static func upperFirst(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, first.value <= 0xFFFF else { return text }
        return String(first).uppercased() + String(text.unicodeScalars.dropFirst())
    }

    /// `Number(digits)` as a string: the digits without their leading zeros.
    static func number(_ digits: String) -> String {
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

/// A regular expression that matches as a JavaScript one does - its pattern written for ICU with explicit classes
/// (see ErrorWords' head) - compiled once; NSRegularExpression is immutable, so sharing it is safe. Ranges are in
/// UTF-16 units, as NSRegularExpression counts them (and JavaScript does).
struct JSRegex: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String) {
        // the patterns are constants; one that doesn't compile is a programming error the tests catch at once
        regex = try! NSRegularExpression(pattern: pattern, options: [])
    }

    /// RegExp.prototype.test.
    func test(_ text: String) -> Bool {
        regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
    }

    /// The capture groups of a match, or nil for none (a group that took no part is "").
    func groups(_ text: String) -> [String]? {
        let whole = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: whole) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
