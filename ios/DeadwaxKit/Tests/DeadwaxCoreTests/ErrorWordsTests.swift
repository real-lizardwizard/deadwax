import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/errors/error-words.json: what the web app's lib/errorWords.ts and lib/signIn.ts answer, case by case,
/// written by ios/scripts/export-error-words.cjs (ui/test/ioserrorwords.sim.cjs keeps it current). Never edited by
/// hand; when the web's words change, run the script and make ErrorWords.swift say the same.
struct ErrorFixture: Decodable {
    struct JobError: Decodable { let reason: String; let text: String; let tell: Bool }
    struct Media: Decodable { let code: Int?; let words: String }
    struct Options: Decodable { let admin: Bool?; let retry: Bool?; let service: String?; let gone: String?; let failed: String? }
    struct Skipped: Decodable { let decode_code: Int; let decode: String; let other: String }
    struct AnswerSpec: Decodable {
        let status: Int; let path: String; let method: String?; let detail: String?; let why: String?; let kind: String?
        let busy: Bool?
    }
    struct Spec: Decodable { let answer: AnswerSpec?; let offline: String?; let timeout: String?; let other: String? }
    struct Way: Decodable { let text: String; let advice: String; let detail: String?; let notice: String }
    struct Case: Decodable {
        let error: Spec; let kind: String; let service: String; let raw: String; let sign_in_problem: String
        let sign_in_why: String?; let unanswered: String; let ways: [Way]
    }
    struct Plumbing: Decodable { let text: String?; let plumbing: Bool }
    struct Sentence: Decodable { let text: String; let sentence: String }
    struct Keeping: Decodable { let names: [String]; let text: String; let sentence: String }
    struct Said: Decodable { let text: String; let advice: String; let said: String }
    struct Safe: Decodable { let text: String?; let fallback: String; let result: String; let detail: String? }
    struct Job: Decodable { let error: String?; let text: String; let tell: Bool; let detail: String? }
    struct Ping: Decodable { let service: String; let code: String?; let error: String?; let text: String; let line: String? }
    struct Reason: Decodable { let detail: String?; let shown: String? }
    struct After: Decodable { let before: String?; let now: String; let result: String }

    let constants: [String: String]
    let down: [String: String]
    let job_errors: [JobError]
    let ping_status: [String: String]
    let musicbrainz_lines: [String: String]
    let page: [String: String]
    let media: [Media]
    let options: [Options]
    let skipped: Skipped
    let errors: [Case]
    let plumbing: [Plumbing]
    let as_sentence: [Sentence]
    let as_sentence_keeping: [Keeping]
    let said: [Said]
    let safe_words: [Safe]
    let job_error_words: [Job]
    let ping_words: [Ping]
    let reason_shown: [Reason]
    let after_sign_in: [After]

    static func load() throws -> ErrorFixture {
        let url = try #require(Bundle.module.url(forResource: "error-words", withExtension: "json", subdirectory: "Fixtures/errors")
                               ?? Bundle.module.resourceURL?.appendingPathComponent("Fixtures/errors/error-words.json"))
        return try JSONDecoder().decode(ErrorFixture.self, from: Data(contentsOf: url))
    }
}

/// What differs, one line each - so a failure names its cases, never dumps two whole lists.
final class WordDiffs {
    private(set) var lines: [String] = []

    func check<T: Equatable>(_ label: @autoclosure () -> String, _ swift: T, _ web: T) {
        if swift != web { lines.append("\(label()): Swift \(swift), the web \(web)") }
    }

    var summary: String { "\(lines.count) differ: " + lines.prefix(6).joined(separator: " | ") }
}

@Suite struct ErrorWordsTests {
    let server = try! ServerAddress.parse("192.168.3.20:8090").get()

    func failure(_ spec: ErrorFixture.Spec) -> APIFailure {
        if let answer = spec.answer {
            return .answered(.init(status: answer.status, method: answer.method ?? "GET", path: answer.path,
                                   detail: answer.detail, why: answer.why, kind: answer.kind, busy: answer.busy == true))
        }
        if let words = spec.offline { return .offline(.init(server: server, method: "GET", path: "/me", reason: words)) }
        if let words = spec.timeout { return .timeout(.init(server: server, method: "GET", path: "/me", reason: words)) }
        return .other(spec.other ?? "")
    }

    @Test func theFixtureIsThere() throws {
        let fixture = try ErrorFixture.load()
        #expect(fixture.errors.count > 70 && fixture.options.count == 10 && fixture.plumbing.count > 100)
    }

    @Test func everySentenceIsTheWebs() throws {
        let fixture = try ErrorFixture.load()
        let words = fixture.constants
        let ours: [String: String] = [
            "TELL": ErrorWords.tell, "OFFLINE": ErrorWords.offline, "OFFLINE_ADVICE": ErrorWords.offlineAdvice,
            "OFFLINE_RETRY": ErrorWords.offlineRetry, "TIMEOUT": ErrorWords.timeout, "SIGNED_OUT": ErrorWords.signedOut,
            "NOT_ALLOWED": ErrorWords.notAllowed, "GONE": ErrorWords.gone, "OTHER": ErrorWords.other,
            "PING_UNANSWERED": ErrorWords.pingUnanswered, "PLAIN_SIGN_IN": ErrorWords.plainSignIn,
            "UNREACHED": ErrorWords.unreached, "SERVER_FAILED": ErrorWords.serverFailed,
            "FOR_WHOEVER": ErrorWords.forWhoever, "BREAK_GLASS_USER": Access.breakGlassUser,
        ]
        let differ = WordDiffs()
        differ.check("the constants' names", ours.keys.sorted(), words.keys.sorted())
        for (name, sentence) in ours { differ.check(name, sentence, words[name] ?? "") }
        for service in ErrorWords.Service.allCases {
            differ.check("down \(service)", ErrorWords.down[service], fixture.down[service.rawValue])
        }
        differ.check("down's services", fixture.down.count, ErrorWords.Service.allCases.count)
        differ.check("the job reasons", ErrorWords.jobErrors.count, fixture.job_errors.count)
        for (ours, web) in zip(ErrorWords.jobErrors, fixture.job_errors) {
            differ.check("job \(web.reason)", [ours.reason, ours.text, "\(ours.tell)"], [web.reason, web.text, "\(web.tell)"])
        }
        differ.check("ping status", ErrorWords.pingStatus, fixture.ping_status)
        differ.check("MusicBrainz's lines", ErrorWords.musicBrainzLines, fixture.musicbrainz_lines)
        differ.check("ALBUM_GONE", ErrorWords.albumGone, fixture.page["ALBUM_GONE"] ?? "")
        differ.check("ARTIST_GONE", ErrorWords.artistGone, fixture.page["ARTIST_GONE"] ?? "")
        differ.check("COULDNT_REFRESH", ErrorWords.couldntRefresh, fixture.page["COULDNT_REFRESH"] ?? "")
        for media in fixture.media { differ.check("media \(String(describing: media.code))", ErrorWords.media(media.code), media.words) }
        differ.check("media 1, and none", [ErrorWords.media(1), ErrorWords.media(nil)], [fixture.media.last?.words, fixture.media.last?.words].compactMap { $0 })
        differ.check("the decode code", ErrorWords.MediaError.decode.rawValue, fixture.skipped.decode_code)
        let title = "Mysterons \"live\""
        differ.check("skipped, decode", ErrorWords.skipped(title: title, code: fixture.skipped.decode_code),
                     fixture.skipped.decode.replacingOccurrences(of: "${title}", with: title))
        for code in [nil, 1, 2, 4] {
            differ.check("skipped, \(String(describing: code))", ErrorWords.skipped(title: title, code: code),
                         fixture.skipped.other.replacingOccurrences(of: "${title}", with: title))
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
    }

    @Test func everyErrorIsClassedAndSaidAsTheWebSaysIt() throws {
        let fixture = try ErrorFixture.load()
        let differ = WordDiffs()
        for (index, one) in fixture.errors.enumerated() {
            let error = failure(one.error)
            let label = "error \(index)"
            differ.check("\(label) kind", ErrorWords.kind(of: error).rawValue, one.kind)
            differ.check("\(label) service", ErrorWords.service(of: error).rawValue, one.service)
            differ.check("\(label) raw", ErrorWords.rawWords(error), one.raw)
            differ.check("\(label) sign-in", ErrorWords.signInProblem(error), one.sign_in_problem)
            differ.check("\(label) sign-in why", ErrorWords.signInWhy(error), one.sign_in_why)
            differ.check("\(label) unanswered", ErrorWords.unansweredLine(error), one.unanswered)
            differ.check("\(label) ways", one.ways.count, fixture.options.count)
            for (way, options) in zip(one.ways, fixture.options) {
                let service = options.service.flatMap(ErrorWords.Service.init(rawValue:))
                let words = ErrorWords.of(error, admin: options.admin == true, service: service, gone: options.gone,
                                          failed: options.failed, retry: options.retry == true)
                let wayLabel = "\(label) \(options.admin == true ? "admin" : "listener") \(options.retry == true ? "retry " : "")\(options.service ?? "")\(options.gone.map { " gone(\($0))" } ?? "")\(options.failed.map { " failed(\($0))" } ?? "")"
                differ.check("\(wayLabel) kind", words.kind.rawValue, one.kind)
                differ.check("\(wayLabel) text", words.text, way.text)
                differ.check("\(wayLabel) advice", words.advice, way.advice)
                differ.check("\(wayLabel) detail", words.detail, way.detail)
                let notice = ErrorWords.notice("Not saved.", error, admin: options.admin == true, service: service,
                                               gone: options.gone, failed: options.failed, retry: options.retry == true)
                differ.check("\(wayLabel) notice", notice, way.notice)
                differ.check("\(wayLabel) said", notice.hasPrefix("Not saved. \(words.said)"), true)
            }
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
    }

    @Test func plumbingIsTheWebsRegularExpressions() throws {
        let fixture = try ErrorFixture.load()
        let differ = WordDiffs()
        for one in fixture.plumbing {
            differ.check("plumbing \(String(reflecting: one.text))", ErrorWords.plumbing(one.text), one.plumbing)
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
        // the fixture holds both answers, and the edges where ICU's own rules differ from JavaScript's
        #expect(fixture.plumbing.contains { $0.plumbing } && fixture.plumbing.contains { !$0.plumbing })
    }

    @Test func sentencesAreMadeAsTheWebMakesThem() throws {
        let fixture = try ErrorFixture.load()
        let differ = WordDiffs()
        for one in fixture.as_sentence {
            differ.check("asSentence \(String(reflecting: one.text))", ErrorWords.asSentence(one.text), one.sentence)
        }
        for one in fixture.as_sentence_keeping {
            differ.check("asSentence \(String(reflecting: one.text)) keeping \(one.names)",
                         ErrorWords.asSentence(one.text, keeping: one.names), one.sentence)
        }
        for one in fixture.said {
            differ.check("said \(one.text) / \(one.advice)", ErrorWords.said(text: one.text, advice: one.advice), one.said)
        }
        for one in fixture.safe_words {
            let safe = ErrorWords.safeWords(one.text, fallback: one.fallback)
            differ.check("safeWords \(String(reflecting: one.text))", [safe.text, safe.detail ?? "<nil>"], [one.result, one.detail ?? "<nil>"])
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
    }

    @Test func aDownloadsReasonsAreTheWebs() throws {
        let fixture = try ErrorFixture.load()
        let differ = WordDiffs()
        for one in fixture.job_error_words {
            let words = ErrorWords.jobErrorWords(one.error)
            differ.check("job \(String(reflecting: one.error))", words, ErrorWords.JobWords(text: one.text, tell: one.tell, detail: one.detail))
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
    }

    @Test func connectionsRowsAreTheWebs() throws {
        let fixture = try ErrorFixture.load()
        let differ = WordDiffs()
        for one in fixture.ping_words {
            let service = try #require(ErrorWords.Ping(rawValue: one.service))
            let words = ErrorWords.pingWords(service, code: one.code, error: one.error)
            differ.check("ping \(one.service) \(String(describing: one.code)) \(String(describing: one.error))",
                         [words.text, words.line ?? "<nil>"], [one.text, one.line ?? "<nil>"])
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
    }

    @Test func theSignInScreensRulesAreTheWebs() throws {
        let fixture = try ErrorFixture.load()
        let differ = WordDiffs()
        for one in fixture.reason_shown {
            differ.check("reasonShown \(String(reflecting: one.detail))", ErrorWords.reasonShown(one.detail), one.shown)
        }
        for one in fixture.after_sign_in {
            differ.check("afterSignIn \(String(reflecting: one.before)) -> \(one.now)",
                         Access.afterSignIn(before: one.before, now: one.now).rawValue, one.result)
        }
        #expect(differ.lines.isEmpty, "\(differ.summary)")
    }

    // MARK: the app's own uses, beside the replay

    @Test func aListenerNeverReadsTheRawWords() {
        let unreached = APIFailure.answered(.init(status: 502, method: "GET", path: "/navidrome/albums/al-1",
                                                  detail: "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed"))
        let listener = ErrorWords.of(unreached)
        #expect(listener.kind == .unreachable && listener.detail == nil)
        #expect(listener.said == "Can't reach the music server right now. Try again in a minute - if it keeps happening, tell whoever runs deadwax.")
        let admin = ErrorWords.of(unreached, admin: true)
        #expect(admin.said == "Can't reach the music server right now. Try again in a minute.")
        #expect(admin.detail == "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed")
    }

    @Test func anErrorThatIsntAnAPIFailureIsStillSaid() {
        #expect(ErrorWords.kind(of: URLError(.notConnectedToInternet)) == .offline)
        #expect(ErrorWords.kind(of: URLError(.timedOut)) == .timeout)
        #expect(ErrorWords.kind(of: CancellationError()) == .other)
        #expect(ErrorWords.of(CancellationError()).said == "Something went wrong. Try again - if it keeps happening, tell whoever runs deadwax.")
        #expect(ErrorWords.signInProblem(URLError(.notConnectedToInternet)) == ErrorWords.unreached)
    }
}
