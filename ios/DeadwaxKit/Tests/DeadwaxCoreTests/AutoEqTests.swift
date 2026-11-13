import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/autoeq/answers.json: what deadwax's two AutoEq routes answered (ios/scripts/autoeq_answers.py, over
/// tests/test_autoeq.py's fake GitHub and its 46 lines of AutoEq's list at 7ae0f56) - never written by hand.
enum AutoEqAnswers {
    struct Case {
        let name: String
        let path: String
        /// the query as asked, in the order asked ("q", then "limit")
        let query: [(String, String)]
        let status: Int
        /// the answer as deadwax sent it
        let body: Data
    }

    struct File {
        let limit: Int
        let searches: [Case]
        let profiles: [Case]
    }

    static func load() throws -> File {
        let object = try JSONSerialization.jsonObject(with: Fixtures.data("autoeq/answers.json")) as? [String: Any]
        let top = try #require(object)
        func cases(_ key: String) throws -> [Case] {
            let list = try #require(top[key] as? [[String: Any]])
            return try list.map { (one: [String: Any]) -> Case in
                let query = (one["query"] as? [String: String]) ?? [:]
                let ordered = ["q", "limit"].compactMap { (name: String) -> (String, String)? in
                    query[name].map { (name, $0) }
                }
                return Case(name: try #require(one["name"] as? String), path: try #require(one["path"] as? String),
                            query: ordered, status: try #require(one["status"] as? Int),
                            body: try JSONSerialization.data(withJSONObject: try #require(one["answer"])))
            }
        }
        return File(limit: try #require(top["limit"] as? Int), searches: try cases("searches"),
                    profiles: try cases("profiles"))
    }

    /// A search's answer, by the query it was asked with.
    static func search(_ q: String) throws -> AutoEqResults {
        let found = try #require(try load().searches.first { $0.query.first?.1 == q && $0.status == 200 }, "no search for \(q)")
        return try JSONDecoder().decode(AutoEqResults.self, from: found.body)
    }

    static func profile(_ name: String) throws -> AutoEqProfile {
        let found = try #require(try load().profiles.first { $0.name == name }, "no profile \(name)")
        return try JSONDecoder().decode(AutoEqProfile.self, from: found.body)
    }
}

@Suite struct AutoEqTests {
    @Test func everyAnswerTheRoutesSentDecodes() throws {
        let file = try AutoEqAnswers.load()
        #expect(file.limit == AutoEqAsk.limit)
        #expect(file.searches.count >= 8 && file.profiles.count >= 5)
        for one in file.searches where one.status == 200 {
            let answer = try JSONDecoder().decode(AutoEqResults.self, from: one.body)
            #expect(answer.listFrom == "2026-11-12T09:30:00Z", "\(one.name)")
            #expect(answer.results.count <= AutoEqAsk.limit)
            #expect(answer.complete == (answer.total == answer.results.count), "\(one.name)")
        }
        for one in file.profiles where one.status == 200 {
            let profile = try JSONDecoder().decode(AutoEqProfile.self, from: one.body)
            #expect(profile.text.hasPrefix("Preamp:"), "\(one.name)")
            #expect(profile.id.count == 16)
        }
        let hd650 = try AutoEqAnswers.search("Sennheiser HD 650")
        let row = try #require(hd650.results.first)
        // the row is the best source's result, the others under it - a folder naming only the form has no rig
        #expect(row.name == "Sennheiser HD 650" && row.source == "oratory1990")
        #expect(row.rig == nil && row.form == "over-ear")
        #expect(row.others.count == 6)
        #expect(row.others.first == AutoEqMeasurement(id: "9cb3fd4601c49d6e", source: "crinacle", rig: "GRAS 43AG-7", form: "over-ear"))
        #expect(row.measurement == AutoEqMeasurement(id: row.id, source: "oratory1990", rig: nil, form: "over-ear"))
        // a name outside ASCII as AutoEq wrote it
        #expect(try AutoEqAnswers.search("aur audio").results.map(\.name) == ["A\u{FC}R Audio Aure"])
        // more found than asked for
        let apple = try AutoEqAnswers.search("apple")
        #expect(apple.results.count == 3 && apple.total == 18 && !apple.complete)
    }

    @Test func theClientAsksAsTheServerWasAskedAndReadsWhatItAnswered() async throws {
        let file = try AutoEqAnswers.load()
        for one in file.searches + file.profiles {
            let (deadwax, transport) = client(session: "s.1")
            let body = one.body
            let status = one.status
            transport.handle(one.path) { (_: HTTPRequest) -> HTTPResponse in
                HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
            }
            let isSearch = one.path == Routes.autoEqSearch.path
            do {
                if isSearch {
                    let limit = Int(one.query.last?.1 ?? "") ?? AutoEqAsk.limit
                    let answer = try await deadwax.autoEq(search: one.query.first?.1 ?? "", limit: limit)
                    #expect(answer == (try JSONDecoder().decode(AutoEqResults.self, from: body)), "\(one.name)")
                } else {
                    let id = String(one.path.split(separator: "/").last ?? "")
                    let answer = try await deadwax.autoEqProfile(id: id)
                    #expect(answer == (try JSONDecoder().decode(AutoEqProfile.self, from: body)), "\(one.name)")
                }
                #expect(status == 200, "\(one.name) read, though deadwax answered \(status)")
            } catch let failure as APIFailure {
                #expect(failure.answer?.status == status && status != 200, "\(one.name): \(failure)")
            }
            let sent = try #require(transport.last)
            // the path the server was asked at, the query in the server's order, the session's cookie
            #expect(sent.url.path == one.path, "\(one.name)")
            #expect(sent.method == "GET")
            let items = URLComponents(url: sent.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.map(\.name) == one.query.map(\.0), "\(one.name)")
            #expect(items.map { (item: URLQueryItem) -> String in item.value ?? "" } == one.query.map(\.1), "\(one.name)")
            #expect(sent.headers["Cookie"] != nil)
            // given longer than the transport's 8 s: deadwax may wait 15 s for AutoEq's list or a file (the review)
            #expect(sent.timeout == 20, "\(one.name)")
        }
    }

    @Test func aQueryWithPunctuationIsSentAsTyped() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/eq/autoeq", 200, #"{"results":[],"total":0,"list_from":"2026-11-12T09:30:00Z"}"#)
        let answer = try await deadwax.autoEq(search: "Bang & Olufsen H9+")
        #expect(answer == AutoEqResults(results: [], total: 0, listFrom: "2026-11-12T09:30:00Z"))
        let url = try #require(transport.last?.url)
        #expect(url.query == "q=Bang%20%26%20Olufsen%20H9%2B&limit=50")
    }

    @Test func theFailuresAreSaidInAListenersWords() async throws {
        let file = try AutoEqAnswers.load()
        func failure(_ one: AutoEqAnswers.Case) async throws -> any Error {
            let (deadwax, transport) = client()
            transport.answer(one.path, one.status, String(decoding: one.body, as: UTF8.self))
            do {
                if one.path == Routes.autoEqSearch.path {
                    _ = try await deadwax.autoEq(search: one.query.first?.1 ?? "")
                } else {
                    _ = try await deadwax.autoEqProfile(id: String(one.path.split(separator: "/").last ?? ""))
                }
            } catch {
                return error
            }
            Issue.record("\(one.name) didn't fail")
            return CancellationError()
        }
        // deadwax can't reach AutoEq (a 503): its words as sent; for a listener, who to tell; for an admin, nothing
        let down = try #require(file.searches.first { $0.status == 503 })
        let refused = try await failure(down)
        let said = ErrorWords.of(refused, admin: false, gone: EQWords.Profile.gone, retry: true)
        #expect(said.text == "deadwax can't reach AutoEq just now.")
        #expect(said.advice == "If it keeps happening, tell whoever runs deadwax.")
        #expect(ErrorWords.of(refused, admin: true, gone: EQWords.Profile.gone, retry: true).advice == "")
        let profileDown = try #require(file.profiles.first { $0.status == 503 })
        #expect(ErrorWords.of(try await failure(profileDown), retry: true).text == "deadwax can't reach AutoEq just now.")
        // a measurement AutoEq no longer has (a 404 in deadwax's words): the page's own gone, no advice - as the pages
        // say it, through AutoEqAsk.failure
        for gone in file.profiles where gone.status == 404 {
            let said = AutoEqAsk.failure(try await failure(gone))
            let line = ErrorWords.of(said, admin: false, gone: EQWords.Profile.gone, retry: true)
            #expect(line.kind == .notFound)
            #expect(line.text == "AutoEq doesn't have that measurement any more." && line.advice == "")
        }
        // a deadwax from before the AutoEq routes answers FastAPI's own 404 (or one with no words), to the search and
        // to a profile: never "gone" - for a listener ErrorWords' own words for what didn't work, and the version it
        // needs only for whoever runs deadwax (the review: the sentence was said to everyone)
        for (path, body) in [("/deadwax/eq/autoeq", #"{"detail":"Not Found"}"#),
                             ("/deadwax/eq/autoeq/0123456789abcdef", #"{"detail":"Not Found"}"#),
                             ("/deadwax/eq/autoeq", "")] {
            let (older, olderTransport) = client()
            olderTransport.answer(path, 404, body)
            do {
                if path == Routes.autoEqSearch.path {
                    _ = try await older.autoEq(search: "AirPods Pro")
                } else {
                    _ = try await older.autoEqProfile(id: "0123456789abcdef")
                }
                Issue.record("an older deadwax's 404 didn't fail")
            } catch {
                let said = AutoEqAsk.failure(error)
                #expect(ErrorWords.kind(of: said) == .other, "\(path)")
                let listener = ErrorWords.of(said, admin: false, gone: EQWords.Profile.gone, retry: true)
                #expect(listener.text == "Something went wrong." && listener.detail == nil, "\(path)")
                #expect(listener.advice == "If it keeps happening, tell whoever runs deadwax.")
                #expect(!listener.said.contains("2.1.7"))
                let admin = ErrorWords.of(said, admin: true, gone: EQWords.Profile.gone, retry: true)
                #expect(admin.text == "Something went wrong." && admin.advice == "")
                let detail = try #require(admin.detail)
                #expect(detail.hasPrefix(EQWords.Picker.tooOld + " (GET /eq/autoeq"), "\(detail)")
                #expect(detail.hasSuffix(" answered 404)"))
            }
        }
        // every other failure is as it was
        let refusedAgain = AutoEqAsk.failure(refused)
        #expect(refusedAgain as? APIFailure == refused as? APIFailure)
        #expect(ErrorWords.of(refusedAgain, retry: true).text == "deadwax can't reach AutoEq just now.")
        // offline: ErrorWords' own, beside the page's Try again
        let (deadwax, transport) = client()
        transport.goAway()
        do {
            _ = try await deadwax.autoEq(search: "AirPods Pro")
            Issue.record("offline didn't fail")
        } catch {
            let line = ErrorWords.of(error, admin: false, gone: EQWords.Profile.gone, retry: true)
            #expect(line.text == "Can't connect to deadwax." && line.advice == "Check your connection.")
        }
    }

    @Test func theQueryIsTrimmedAndKeptWithinWhatTheServerTakes() {
        #expect(AutoEqAsk.query("  AirPods Pro \n") == "AirPods Pro")
        #expect(AutoEqAsk.query("   ") == nil)
        #expect(AutoEqAsk.query("") == nil)
        let long = String(repeating: "a", count: 99) + "\u{FC}" + "bcd"
        #expect(AutoEqAsk.query(long)?.unicodeScalars.count == 100)
        // a letter made of two scalars is cut as the server counts - by scalar - never past 100
        let marks = String(repeating: "e\u{301}", count: 60)
        #expect((AutoEqAsk.query(marks)?.unicodeScalars.count ?? 0) <= 100)
    }

    @Test func aProfileIsReadToItsCorrection() throws {
        let airpods = try AutoEqAnswers.profile("crinacle's AirPods Pro")
        let c = try airpods.correction().get()
        #expect(c.kind == .autoeq && c.id == airpods.id && c.name == "Apple AirPods Pro")
        #expect(c.source == "crinacle" && c.rig == "711" && c.form == "in-ear")
        #expect(c.text == airpods.text)
        #expect(c.filters.count == 10 && c.filters.map(\.id) == Array(1...10) && c.nextFilterID == 11)
        #expect(c.preamp.all == -6.0)
        #expect(!c.changed && !c.converted)
        #expect(EQWords.Correction.source(c) == "AutoEq, measured by crinacle")
        let hd650 = try AutoEqAnswers.profile("oratory1990's HD 650").correction().get()
        #expect(hd650.filters.count == 10 && hd650.preamp.all == -6.1 && hd650.rig == nil)
        // a file the reader refuses is the reader's refusal, not a correction
        let broken = AutoEqProfile(id: "0123456789abcdef", name: "X", source: "Y", rig: nil, form: nil,
                                   text: "IIR: 1 2 3 4 5 6")
        #expect(throws: APORefusal.self) { try broken.correction().get() }
    }
}

@Suite struct EQSuggestionTests {
    @Test func theAirPodsProAreAChoiceNeverTheFirst() throws {
        // iOS names the first generation and the Pro 2 "AirPods Pro" alike: the name can't say which is in your ears
        let output = EQOutput(key: "bluetooth:60:F8", port: .bluetoothA2DP, portType: "BluetoothA2DPOutput",
                              uid: "60:F8", name: "James's AirPods Pro", symbol: "airpodspro")
        let setting = EQSettings.newOutput(output, seen: "")
        let query = EQSuggestionRules.query(output, setting)
        #expect(query == "AirPods Pro")
        let suggestion = EQSuggestion.of(query, answer: try AutoEqAnswers.search(query))
        guard case .several(let asked, let rows) = suggestion else {
            Issue.record("the AirPods Pro were offered \(suggestion), not a choice")
            return
        }
        #expect(asked == "AirPods Pro")
        let names = rows.map(\.name)
        // the first generation, the Pro 2 as three sources name it, and crinacle's fourteen Pro 2 measurements -
        // every word of the name whole: Rtings' "Pro2" isn't among them (the picker shows it under them)
        #expect(names.count == 16)
        #expect(names.first == "Apple AirPods Pro")
        #expect(names.filter { $0.hasPrefix("Apple AirPods Pro 2 (") }.count == 14)
        #expect(names.contains("Apple Airpods Pro 2"))
        #expect(!names.contains("Apple AirPods Pro2"))
        #expect(suggestion.rows == rows && suggestion.searched == "AirPods Pro")
        let lines = try #require(suggestion.lines)
        #expect(lines.title == "AutoEq has corrections for AirPods Pro")
        #expect(lines.detail == "16 models - pick yours")
    }

    @Test func anAirPodsProRenamedWithItsMakerIsStillAChoice() throws {
        // "Apple AirPods Pro" is one row's whole name - but "Apple AirPods Pro 2" is another model beside it
        let suggestion = EQSuggestion.of("Apple AirPods Pro", answer: try AutoEqAnswers.search("Apple AirPods Pro"))
        guard case .several(_, let rows) = suggestion else {
            Issue.record("offered \(suggestion)")
            return
        }
        #expect(rows.count == 16)
    }

    @Test func theHD650IsOfferedItsOne() throws {
        // six rows hold "Sennheiser HD 650": the name alone, and five with a word in parentheses - one headphone
        let answer = try AutoEqAnswers.search("Sennheiser HD 650")
        #expect(answer.results.count == 6)
        let suggestion = EQSuggestion.of("Sennheiser HD 650", answer: answer)
        guard case .one(let row) = suggestion else {
            Issue.record("the HD 650 was offered \(suggestion)")
            return
        }
        #expect(row.name == "Sennheiser HD 650" && row.source == "oratory1990")
        #expect(suggestion.rows == [row] && suggestion.searched == nil)
        let lines = try #require(suggestion.lines)
        #expect(lines.title == "AutoEq has a correction for Sennheiser HD 650")
        #expect(lines.detail == "Measured by oratory1990")
    }

    @Test func aSpeakerIsOfferedNothing() throws {
        let suggestion = EQSuggestion.of("JBL Flip 6", answer: try AutoEqAnswers.search("JBL Flip 6"))
        #expect(suggestion == .none && suggestion.rows.isEmpty && suggestion.lines == nil)
    }

    @Test func oneRowIsOfferedAndALetterOutsideASCIIIsTheSameWord() throws {
        // deadwax's one row for "aur audio" is the AüR Audio Aure: named by its model, it is offered
        let answer = try AutoEqAnswers.search("aur audio")
        let suggestion = EQSuggestion.of("Aur Audio Aure", answer: answer)
        #expect(suggestion.rows.map(\.name) == ["A\u{FC}R Audio Aure"])
        if case .one = suggestion {} else { Issue.record("offered \(suggestion)") }
        // ...by its maker alone, it is a choice: AüR Audio's one measured model needn't be yours (the review)
        guard case .several(_, let rows) = EQSuggestion.of("aur audio", answer: answer) else {
            Issue.record("the maker's one model was offered as the output")
            return
        }
        #expect(rows.map(\.name) == ["A\u{FC}R Audio Aure"])
    }

    static func answer(_ rows: [AutoEqResult]) -> AutoEqResults {
        AutoEqResults(results: rows, total: rows.count, listFrom: "2026-11-12T09:30:00Z")
    }

    static func row(_ name: String, _ id: String) -> AutoEqResult {
        AutoEqResult(id: id, name: name, source: "Rtings", rig: "HMS II.3", form: "in-ear", others: [])
    }

    @Test func theOnlyRowIsOfferedOnlyWhenItIsThisHeadphone() throws {
        // a list holding the Pro 2's ANC mode and no first generation: the one row under "AirPods Pro" has a word
        // after the name, so it is another model - a choice, never the Pro 2 offered as the AirPods Pro (the review:
        // "exactly one row" offered it)
        let airpods = try AutoEqAnswers.search("AirPods Pro")
        let pro2 = try #require(airpods.results.first { $0.name == "Apple AirPods Pro 2 (ANC mode)" })
        guard case .several(let asked, let rows) = EQSuggestion.of("AirPods Pro", answer: Self.answer([pro2])) else {
            Issue.record("the Pro 2 alone was offered to the AirPods Pro")
            return
        }
        #expect(asked == "AirPods Pro" && rows == [pro2])
        // it is the Pro 2's own: the name after its maker, a qualifier in parentheses aside
        #expect(EQSuggestion.of("AirPods Pro 2", answer: Self.answer([pro2])) == .one(pro2))
        // the first generation alone is the AirPods Pro's (3.7's exactly one), as the maker's name before it is
        let first = try #require(airpods.results.first { $0.name == "Apple AirPods Pro" })
        #expect(EQSuggestion.of("AirPods Pro", answer: Self.answer([first])) == .one(first))
        #expect(EQSuggestion.of("Apple AirPods Pro", answer: Self.answer([first])) == .one(first))
        // a word among the name's is another model: the Galaxy Buds 2 Pro aren't the Galaxy Buds Pro
        let buds2 = Self.row("Samsung Galaxy Buds 2 Pro", "0123456789abcdef")
        #expect(EQSuggestion.of("Galaxy Buds Pro", answer: Self.answer([buds2])) == .several(query: "Galaxy Buds Pro", rows: [buds2]))
        #expect(EQSuggestion.of("Galaxy Buds 2 Pro", answer: Self.answer([buds2])) == .one(buds2))
        // the name ends the row's at a word's start, not inside one ("earbuds pro" ends "buds pro")
        let earbuds = Self.row("Samsung Galaxy Buds Earbuds Pro", "0123456789abcdee")
        #expect(EQSuggestion.of("Buds Pro", answer: Self.answer([earbuds])) == .several(query: "Buds Pro", rows: [earbuds]))
        // two rows that are each the name alone (deadwax keeps "&" and "and" apart, the phone doesn't): a choice
        let ampersand = Self.row("Bang & Olufsen Beoplay H9", "0123456789abcded")
        let and = Self.row("Bang and Olufsen Beoplay H9", "0123456789abcdec")
        #expect(EQSuggestion.of("Bang & Olufsen Beoplay H9", answer: Self.answer([ampersand, and]))
            == .several(query: "Bang & Olufsen Beoplay H9", rows: [ampersand, and]))
    }

    @Test func aPlusIsAWordOfTheName() {
        // Apple's "Beats Studio Buds +" aren't the Beats Studio Buds, though folding drops the "+" (deadwax's search
        // does too): offered nothing from the Studio Buds alone, the Studio Buds+ when AutoEq has them - and the
        // Studio Buds never the Studio Buds+ (the review)
        let buds = Self.row("Beats Studio Buds", "0123456789abcde0")
        let plus = Self.row("Beats Studio Buds+", "0123456789abcde1")
        #expect(EQSuggestion.of("Beats Studio Buds +", answer: Self.answer([buds])) == .none)
        #expect(EQSuggestion.of("Beats Studio Buds +", answer: Self.answer([buds, plus])) == .one(plus))
        #expect(EQSuggestion.of("Beats Studio Buds", answer: Self.answer([plus])) == .several(query: "Beats Studio Buds", rows: [plus]))
        #expect(EQSuggestion.of("Beats Studio Buds", answer: Self.answer([buds, plus])).rows == [buds, plus])
        // a "+" and a "Plus" are the one word
        let t2 = Self.row("Tin HiFi T2+", "0123456789abcde2")
        #expect(EQSuggestion.of("Tin HiFi T2 Plus", answer: Self.answer([t2])) == .one(t2))
        #expect(EQSuggestion.holdsEveryWord("T2+", "Tin HiFi T2 Plus"))
        // a "+" inside a qualifier stays inside it
        #expect(EQSuggestion.folded("Apple AirPods Pro 2 (51dB + ANC)", key: true) == "apple airpods pro 2")
    }

    @Test func aPartAnswerIsNeverPickedFrom() throws {
        // more found than the limit let through: a row not seen could be another model, so it is a choice
        let apple = try AutoEqAnswers.search("apple")
        if case .several(_, let rows) = EQSuggestion.of("apple", answer: apple) {
            #expect(rows.count == 3)
        } else {
            Issue.record("a part answer was picked from")
        }
        let hd650 = try AutoEqAnswers.search("Sennheiser HD 650")
        let cut = AutoEqResults(results: Array(hd650.results.prefix(1)), total: hd650.total, listFrom: hd650.listFrom)
        if case .several(_, let rows) = EQSuggestion.of("Sennheiser HD 650", answer: cut) {
            #expect(rows.count == 1)
            #expect(EQSuggestion.several(query: "Sennheiser HD 650", rows: rows).lines?.detail == "1 model - pick yours")
        } else {
            Issue.record("one row of six was offered")
        }
    }

    @Test func wordsAreWholeAsTheSuggestionLooksAtThem() throws {
        // deadwax's search runs a query's words together ("hd650" finds the HD 650); the suggestion asks for each
        // word whole, so a name typed that way is offered nothing - the picker still finds it
        let answer = try AutoEqAnswers.search("hd650")
        #expect(answer.results.count == 6)
        #expect(EQSuggestion.of("hd650", answer: answer) == .none)
        #expect(EQSuggestion.holdsEveryWord("airpods PRO", "Apple AirPods Pro 2 (ANC mode)"))
        #expect(!EQSuggestion.holdsEveryWord("airpods pro", "Apple AirPods Pro2"))
        #expect(!EQSuggestion.holdsEveryWord("", "Apple AirPods Pro"))
        #expect(EQSuggestion.holdsEveryWord("Bang & Olufsen", "Bang and Olufsen H95"))
    }

    @Test func whichOutputsAskAndWhenTheRowShows() throws {
        let airpods = EQOutput(key: "bluetooth:60:F8", port: .bluetoothA2DP, portType: "BluetoothA2DPOutput",
                               uid: "60:F8", name: "James's AirPods Pro", symbol: "airpodspro")
        var setting = EQSettings.newOutput(airpods, seen: "")
        let one = EQSuggestion.of("Sennheiser HD 650", answer: try AutoEqAnswers.search("Sennheiser HD 650"))
        #expect(EQSuggestionRules.asks(airpods, setting))
        #expect(EQSuggestionRules.shows(airpods, setting, one, online: true))
        // offline, unanswered, or answered with nothing: no row - an offer, not an error
        #expect(!EQSuggestionRules.shows(airpods, setting, one, online: false))
        #expect(!EQSuggestionRules.shows(airpods, setting, nil, online: true))
        #expect(!EQSuggestionRules.shows(airpods, setting, EQSuggestion.none, online: true))
        // renamed: still asked by the name iOS gives it
        setting.renamed = "Gym buds"
        #expect(EQSuggestionRules.query(airpods, setting) == "AirPods Pro")
        // Not now, for good
        setting.suggestion = .notNow
        #expect(!EQSuggestionRules.asks(airpods, setting))
        setting.suggestion = .shown
        #expect(EQSuggestionRules.asks(airpods, setting))
        // gone once there's a correction
        let profile = try AutoEqAnswers.profile("crinacle's AirPods Pro")
        setting.correction = try profile.correction().get()
        #expect(!EQSuggestionRules.asks(airpods, setting))
        // the speaker, a car, AirPlay, wired: never asked (8, question 20)
        for port in [EQPort.builtInSpeaker, .carAudio, .airPlay, .headphones, .hdmi] {
            let output = EQOutput(key: "k", port: port, portType: "", uid: "", name: "Sennheiser HD 650", symbol: "")
            #expect(!EQSuggestionRules.asks(output, EQSettings.newOutput(output, seen: "")), "\(port)")
        }
        let usb = EQOutput(key: "usb:1", port: .usbAudio, portType: "USBAudio", uid: "1", name: "Sennheiser HD 650", symbol: "")
        #expect(EQSuggestionRules.asks(usb, EQSettings.newOutput(usb, seen: "")))
    }
}

/// Choosing a correction and the suggestion's marks, as the settings keep them (3.7, 4), and a profile's page.
@Suite struct EQCorrectionChoiceTests {
    static let airpods = EQOutput(key: "bluetooth:60:F8", port: .bluetoothA2DP, portType: "BluetoothA2DPOutput",
                                  uid: "60:F8", name: "James's AirPods Pro", symbol: "airpodspro")

    @Test func usingAProfileIsTheCorrectionAndTurnsTheEQOn() throws {
        let profile = try AutoEqAnswers.profile("crinacle's AirPods Pro")
        let correction = try profile.correction().get()
        var settings = EQSettings()
        // never met: given its setting first, Off - and using turns it on
        let changed1 = settings.use(correction, for: Self.airpods)
        #expect(changed1)
        let kept = try #require(settings.output(Self.airpods.key))
        #expect(kept.on && kept.correction == correction && kept.uses(profile.id))
        #expect(!kept.uses("0123456789abcdef"))
        // kept in eq.json and read back after a relaunch the same: the file's text, its filters and their ids
        let written = try settings.written()
        let reread = try #require(EQSettings.read(written))
        #expect(reread == settings && reread.output(Self.airpods.key)?.correction?.text == profile.text)
        // a correction of a kind this build doesn't know, or one garbled, is a file it can't read - set aside (4)
        let text = String(decoding: written, as: UTF8.self)
        #expect(text.contains("\"autoeq\"") && text.contains("\"nextFilterID\""))
        #expect(EQSettings.read(Data(text.replacingOccurrences(of: "\"autoeq\"", with: "\"graphic\"").utf8)) == nil)
        #expect(EQSettings.read(Data(text.replacingOccurrences(of: "\"nextFilterID\"", with: "\"next\"").utf8)) == nil)
        // already on: used again, nothing to turn on
        let changed2 = settings.use(correction, for: Self.airpods)
        #expect(!changed2)
        // None: taken away, the switch left on
        let changed3 = settings.use(nil, for: Self.airpods)
        #expect(!changed3)
        #expect(settings.output(Self.airpods.key)?.correction == nil && settings.output(Self.airpods.key)?.on == true)
        // None while Off leaves it Off
        settings.setOn(false, for: Self.airpods)
        settings.use(correction, for: Self.airpods)
        settings.setOn(false, for: Self.airpods)
        let changed4 = settings.use(nil, for: Self.airpods)
        #expect(!changed4)
        #expect(settings.output(Self.airpods.key)?.on == false)
        // a file's correction of the same name isn't AutoEq's profile
        var file = correction
        file.kind = .file
        settings.use(file, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.uses(profile.id) == false)
    }

    @Test func theSuggestionsMarksAreKeptAndNotNowIsForGood() {
        var settings = EQSettings()
        let changed5 = settings.mark(.shown, for: Self.airpods)
        #expect(changed5)
        #expect(settings.output(Self.airpods.key)?.suggestion == .shown)
        let changed6 = settings.mark(.shown, for: Self.airpods)
        #expect(!changed6)
        let changed7 = settings.mark(.notNow, for: Self.airpods)
        #expect(changed7)
        #expect(settings.output(Self.airpods.key)?.suggestion == .notNow)
        // drawn again after a Not now (it isn't, but if it were): still Not now
        let changed8 = settings.mark(.shown, for: Self.airpods)
        #expect(!changed8)
        #expect(settings.output(Self.airpods.key)?.suggestion == .notNow)
        // a mark is no sound: the output stays Off
        #expect(settings.output(Self.airpods.key)?.on == false)
    }

    @Test func aProfilesPageKnowsTheHeadphonesOtherMeasurements() throws {
        let row = try #require(try AutoEqAnswers.search("Sennheiser HD 650").results.first)
        let page = AutoEqPage(output: Self.airpods.key, row: row)
        #expect(page.name == "Sennheiser HD 650" && page.shown.source == "oratory1990")
        #expect(page.measurements.count == 7 && page.others.count == 6)
        #expect(!page.others.contains(page.shown))
        let other = try #require(page.others.first)
        let next = page.showing(other)
        #expect(next.shown == other && next.output == page.output && next.name == page.name)
        // the best source is among the next page's others, and the one shown isn't
        #expect(next.others.contains(row.measurement) && !next.others.contains(other) && next.others.count == 6)
    }

    @Test func aProfilesCurveIsTheCorrectionAloneAt48kHz() throws {
        let correction = try AutoEqAnswers.profile("crinacle's AirPods Pro").correction().get()
        var settings = EQSettings()
        // the output's own setting - Bass Boost, Off, a preamp by hand - changes nothing on the profile's page
        settings.choose(.preset("bassBoost"), for: Self.airpods)
        settings.setOn(false, for: Self.airpods)
        let drawing = EQDrawing.profile(correction, for: Self.airpods, in: settings)
        #expect(drawing.on && drawing.rate == 48_000)
        #expect(drawing.lines.map(\.kind) == [.heard])
        // deadwax's automatic preamp, within 0.5 dB of the file's own -6.0 (AutoEqProfileTests)
        #expect(abs(drawing.preamp - -6.0) <= 0.5)
        var alone = EQSettings.newOutput(Self.airpods, seen: "")
        alone.on = true
        alone.correction = correction
        #expect(drawing == EQDrawing.make(alone, in: EQSettings(), rate: 48_000))
        // the correction's f0s are among the curve's frequencies: so many points, not the grid's 241
        #expect(drawing.frequencies.count > EQChart.grid.count)
    }
}
