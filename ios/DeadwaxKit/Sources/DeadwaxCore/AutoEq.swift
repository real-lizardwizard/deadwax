import Foundation

/// AutoEq through deadwax (notes/ios-specs/eq.md 2.2, 3.7; server 2.1.7): the two answers the app reads - a search's
/// rows and one result's profile - and what it asks with. The phone never talks to GitHub: deadwax searches its own
/// copy of AutoEq's list and fetches a profile's ParametricEQ.txt for it. tests/test_ios_contract.py holds these to
/// src/autoeq.py's `row_answer`, `profile_answer` and the search route's answer, and Fixtures/autoeq/answers.json
/// (ios/scripts/autoeq_answers.py) is the server's own answers, decoded by AutoEqTests.

/// One measurement of a headphone: its AutoEq result's id (16 hex digits), who measured it, and on what.
public struct AutoEqMeasurement: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let source: String
    /// the rig, "711" or "GRAS 43AG-7" - none when the folder names only the form
    public let rig: String?
    /// "in-ear", "over-ear", "earbud" - none when the folder names none
    public let form: String?

    public init(id: String, source: String, rig: String?, form: String?) {
        self.id = id
        self.source = source
        self.rig = rig
        self.form = form
    }
}

/// A search's row: one headphone (results with the same name folded, deadwax's rows_of), its best source's result and
/// the other measurements under it.
public struct AutoEqResult: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let source: String
    public let rig: String?
    public let form: String?
    public let others: [AutoEqMeasurement]

    public init(id: String, name: String, source: String, rig: String?, form: String?, others: [AutoEqMeasurement]) {
        self.id = id
        self.name = name
        self.source = source
        self.rig = rig
        self.form = form
        self.others = others
    }

    /// The best source's measurement - the row's own.
    public var measurement: AutoEqMeasurement { AutoEqMeasurement(id: id, source: source, rig: rig, form: form) }

    /// Every measurement of the headphone, the best source's first: what a profile's page and its "Other
    /// measurements" are made from.
    public var measurements: [AutoEqMeasurement] { [measurement] + others }
}

/// One profile's page, as pushed (eq.md 3.7): the output it is for (bound - 3.2), the headphone, which of its
/// measurements is shown, and all of them, so "Other measurements" is the rest without asking again.
public struct AutoEqPage: Hashable, Sendable {
    public let output: String
    public let name: String
    public let shown: AutoEqMeasurement
    public let measurements: [AutoEqMeasurement]

    public init(output: String, name: String, shown: AutoEqMeasurement, measurements: [AutoEqMeasurement]) {
        self.output = output
        self.name = name
        self.shown = shown
        self.measurements = measurements
    }

    /// A search's row, opened at its best source's measurement.
    public init(output: String, row: AutoEqResult) {
        self.init(output: output, name: row.name, shown: row.measurement, measurements: row.measurements)
    }

    /// The other measurements of the headphone, each pushing its own page.
    public var others: [AutoEqMeasurement] { measurements.filter { $0.id != shown.id } }

    /// Another of them, as its own page.
    public func showing(_ other: AutoEqMeasurement) -> AutoEqPage {
        AutoEqPage(output: output, name: name, shown: other, measurements: measurements)
    }
}

/// `GET /deadwax/eq/autoeq`'s answer: the rows found, best first, at most the limit asked; how many were found in
/// all; and when deadwax fetched the list it searched (UTC, to the second).
public struct AutoEqResults: Codable, Equatable, Sendable {
    public let results: [AutoEqResult]
    public let total: Int
    public let listFrom: String

    enum CodingKeys: String, CodingKey {
        case results, total
        case listFrom = "list_from"
    }

    public init(results: [AutoEqResult], total: Int, listFrom: String) {
        self.results = results
        self.total = total
        self.listFrom = listFrom
    }

    /// Every row found is here: no more were found than the limit let through.
    public var complete: Bool { total <= results.count }
}

/// `GET /deadwax/eq/autoeq/{id}`'s answer: one result and its ParametricEQ.txt as AutoEq wrote it, at the commit
/// deadwax's list is from.
public struct AutoEqProfile: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let source: String
    public let rig: String?
    public let form: String?
    public let text: String

    public init(id: String, name: String, source: String, rig: String?, form: String?, text: String) {
        self.id = id
        self.name = name
        self.source = source
        self.rig = rig
        self.form = form
        self.text = text
    }

    /// The profile read (APOReader, as it reads a file - eq.md 3.9) and made the output's correction: its filters
    /// numbered from 1, the text kept so "Back to AutoEq's" has it. The reader's refusal when AutoEq has changed its
    /// format.
    public func correction() -> Result<EQCorrection, APORefusal> {
        APOReader.read(Data(text.utf8)).map { (reading: APOReading) -> EQCorrection in
            EQCorrection.autoeq(id: id, name: name, source: source, rig: rig, form: form, text: text, reading: reading)
        }
    }
}

/// What the app asks AutoEq's search with: the limit (the server takes 1 to 50, the contract test holds it there) and
/// the query, trimmed and no longer than the server takes (1 to 100 characters - Python's, so scalars here).
public enum AutoEqAsk {
    public static let limit = 50
    public static let longest = 100

    /// The query as sent - nil for one with nothing in it, which isn't asked.
    public static func query(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: trimmed.unicodeScalars.prefix(longest))
        let capped = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }

    /// The picker's search waits this long after the last key (3.7).
    public static let typingPause: Duration = .milliseconds(300)

    /// A failed ask, as the picker and a profile's page say it (3.17). A 404 in deadwax's words is AutoEq's: a
    /// measurement it no longer has (the profile's `gone`). FastAPI's bare "Not Found" (or no words at all) is a deadwax
    /// with no AutoEq routes - one older than 2.1.7 - and is said as Lyrics.failure says an older deadwax: to a listener
    /// in ErrorWords' own words for something that didn't work, and to whoever runs deadwax, in the detail only they
    /// see (`Access.seesDetail`), the version it needs. Every other failure is as it was.
    public static func failure(_ error: any Error) -> any Error {
        guard let failure = error as? APIFailure, case .answered(let answer) = failure, answer.status == 404 else {
            return error
        }
        let words = (answer.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.isEmpty || words.caseInsensitiveCompare("Not Found") == .orderedSame else { return error }
        return APIFailure.other("\(EQWords.Picker.tooOld) (\(answer.method) \(answer.path) answered 404)")
    }
}

extension DeadwaxClient {
    /// AutoEq's rows whose names hold every word of `query` (`Routes.autoEqSearch`): `query` as `AutoEqAsk.query`
    /// makes it. A 503 is deadwax not reaching AutoEq, in its own words (ErrorWords' refused).
    public func autoEq(search query: String, limit: Int = AutoEqAsk.limit) async throws -> AutoEqResults {
        try await call(Routes.autoEqSearch, as: AutoEqResults.self, query: [("q", query), ("limit", String(limit))])
    }

    /// One result's profile (`Routes.autoEqProfile`). A 404 is a measurement AutoEq no longer has.
    public func autoEqProfile(id: String) async throws -> AutoEqProfile {
        try await call(Routes.autoEqProfile, as: AutoEqProfile.self, path: ["id": id])
    }
}
