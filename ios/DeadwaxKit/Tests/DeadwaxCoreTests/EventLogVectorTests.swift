import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/log/log-vectors.json: the web's lib/eventLog.ts, api/logs.ts, lib/errorWords.ts and lib/permissions.ts run
/// as they are, and app/EventLog.tsx's, lib/appRoutes.ts's, app/App.tsx's and app/access.ts's own rules and words read
/// out of their source - replayed here through EventLog, case for case (notes/ios-specs/phase8-managing.md 8). Every
/// line and history is read as the phone reads deadwax's: from its body, with LogLine and RecentLog.
@Suite struct EventLogVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("log/log-vectors.json"))

    static func line(_ web: Web) -> LogLine {
        try! JSONDecoder().decode(LogLine.self, from: Data(web.string!.utf8))
    }

    static func history(_ web: Web) -> RecentLog {
        try! JSONDecoder().decode(RecentLog.self, from: Data(web.string!.utf8))
    }

    static let server = try! ServerAddress.parse("192.168.3.20:8090").get()
    static let deadwax = DeadwaxClient(server: server, transport: FakeTransport())

    /// The stream's address as the phone asks it, from where the page stands: its path and query, as the web's is
    /// written (`/deadwax/...?after=..&boot=..`).
    static func address(_ from: (after: Int?, boot: String?)) -> String {
        let url = deadwax.url(Routes.logStream, query: EventLog.streamQuery(after: from.after, boot: from.boot))
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?\($0)" } ?? "")
    }

    // MARK: the fixture, the words

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-log-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/eventLog.ts", "ui/src/api/logs.ts", "ui/src/lib/errorWords.ts",
                                 "ui/src/lib/permissions.ts", "ui/src/app/EventLog.tsx a line's key",
                                 "ui/src/app/EventLog.tsx the empty words", "ui/src/app/EventLog.tsx the history's failure",
                                 "ui/src/app/EventLog.tsx the stream's address", "ui/src/app/EventLog.tsx the page's line",
                                 "ui/src/app/EventLog.tsx a stream the browser gave up on",
                                 "ui/src/app/EventLog.tsx asked again by hand, the history first",
                                 "ui/src/app/App.tsx who opens the page", "ui/src/app/access.ts who runs deadwax",
                                 "ui/src/lib/appRoutes.ts not allowed, in words"])
        #expect(fixture["runs"].list.count == 37)
        #expect(fixture["times"].list.count == 198)
        #expect(fixture["historyErrors"].list.count == 24)
        #expect(fixture["permissions"].list.count == 65)
    }

    @Test func thePageSaysWhatTheWebSays() {
        let words = fixture["words"]
        let diffs = ScreenDiffs()
        diffs.text("title", EventLog.title, words["title"])
        diffs.text("manage's row", ManagingWords.label(.log), words["title"])
        diffs.text("the page's line", EventLog.pageLine, words["pageLine"])
        diffs.text("the list's label", EventLog.listLabel, words["listLabel"])
        diffs.text("Clear", EventLog.clear, words["clear"])
        diffs.text("the history's failure", EventLog.historyFailed, words["historyFailed"])
        diffs.text("never", EventLog.emptyNever, words["emptyNever"])
        diffs.text("cleared", EventLog.emptyCleared, words["emptyCleared"])
        diffs.text("connecting", EventLog.words(.connecting), words["connecting"])
        diffs.text("live", EventLog.words(.live), words["live"])
        diffs.text("lost", EventLog.words(.lost), words["lost"])
        diffs.text("not allowed", EditWords.noPermission, words["noPermission"])
        diffs.number("LOG_KEPT", Double(EventLog.kept), words["kept"])
        diffs.number("STREAM_RETRY_MS", EventStream.retry * 1000, words["retryMs"])
        diffs.done()
    }

    // MARK: a line drawn

    @Test func aLinesLevelIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["levels"].list {
            let type = row["type"].string!
            diffs.text("level of \(Screens.spelled(type))", EventLog.level(type).rawValue, row["level"])
        }
        diffs.done()
    }

    @Test func aLinesTimeIsTheWebsOnEveryClock() throws {
        let diffs = ScreenDiffs()
        for row in fixture["times"].list {
            let zone = try #require(TimeZone(identifier: row["zone"].string!))
            let time = row["time"].num!
            diffs.text("\(time) in \(zone.identifier)", EventLog.time(time, in: zone), row["said"])
        }
        // no time, or one of another type: nothing - read from the line as deadwax would send it
        for row in fixture["untimed"].list {
            var fields: [String: Any] = ["event_type": "INFO", "event_content": ""]
            switch row["time"] {
            case .null: break
            case .string(let text): fields["time"] = text
            case .bool(let flag): fields["time"] = flag
            case .array: fields["time"] = [1]
            case .object: fields["time"] = ["at": 1]
            case .number(let number): fields["time"] = number
            }
            let line = try JSONDecoder().decode(LogLine.self, from: JSONSerialization.data(withJSONObject: fields))
            diffs.text("time \(row["time"])", EventLog.time(line.time), row["said"])
        }
        diffs.done()
    }

    // MARK: the runs

    /// Each run's ops - a line from the stream, a history, Clear - applied to the phone's state as the web applied
    /// them to its own, the state compared after every op: the run and the number held, the gap, cleared, how many
    /// lines and the newest, the empty words and where the stream would be asked from; and at the end every line, in
    /// order, and the web's keys against the phone's identities.
    @Test func everyRunJoinsAsTheWebs() {
        let diffs = ScreenDiffs()
        var unkeyed = 0
        for run in fixture["runs"].list {
            let name = run["name"].string!
            var state = EventLog.State()
            for (index, step) in run["steps"].list.enumerated() {
                let label = "\(name) step \(index)"
                if !step["line"].isNull {
                    state = state.joining(Self.line(step["line"]))
                } else if !step["history"].isNull {
                    state = state.joining(history: Self.history(step["history"]))
                } else {
                    state = state.emptied()
                }
                let after = step["after"]
                diffs.text("\(label) boot", state.boot, after["boot"])
                diffs.number("\(label) last", Double(state.last), after["last"])
                diffs.number("\(label) gap", state.gap.map(Double.init), after["gap"])
                diffs.flag("\(label) cleared", state.cleared, after["cleared"])
                diffs.number("\(label) count", Double(state.lines.count), after["count"])
                diffs.check("\(label) top", state.lines.prefix(2).map(\.line), after["top"].list.map(Self.line))
                diffs.text("\(label) empty", EventLog.empty(state), after["empty"])
                diffs.text("\(label) address", Self.address(state.streamFrom), after["url"])
            }
            diffs.check("\(name) lines", state.lines.map(\.line), run["lines"].list.map(Self.line))
            let keys = run["keys"].list.map { $0.string! }
            diffs.check("\(name) keys counted", keys.count, state.lines.count)
            for (line, key) in zip(state.lines, keys) {
                if let seq = line.id.seq {
                    diffs.check("\(name) key", "\(line.id.boot):\(seq)", key)
                } else if key.hasPrefix("n") {
                    // a line deadwax numbered none: the web keys it by place, the phone by when it was taken
                    diffs.check("\(name) unnumbered", line.seq, nil)
                } else {
                    // a number that isn't one (`"seq": "2"`): the web keys it by what came, the phone reads none
                    unkeyed += 1
                }
            }
            // the phone's identities are its own: never two the same, however the web's keys fall
            diffs.check("\(name) every identity once", Set(state.lines.map(\.id)).count, state.lines.count)
        }
        #expect(unkeyed == 1, "the one line of the wrong type's number, and only it")
        diffs.done()
    }

    // MARK: the history's failure, the stream's address

    @Test func theHistorysFailureIsSaidAsTheWebSaysIt() {
        let diffs = ScreenDiffs()
        for row in fixture["historyErrors"].list {
            let error = screenFailure(row["error"], path: "/interface_logs/recent", method: "GET")
            let admin = row["admin"].bool!
            diffs.text("\(row["error"]) admin \(admin)", EventLog.historyFailure(error, admin: admin), row["said"])
        }
        diffs.done()
    }

    @Test func theStreamIsAskedFromWhereTheWebAsksIt() {
        let diffs = ScreenDiffs()
        for row in fixture["addresses"].list {
            let last = row["last"].int!
            let boot = row["boot"].string
            let from = EventLog.streamFrom(last: last, boot: boot)
            let label = "\(last) \(Screens.spelled(boot))"
            let query = EventLog.streamQuery(after: from.after, boot: from.boot)
            diffs.check("\(label) query", query.map { "\($0.0)=\($0.1)" },
                        row["query"].list.map { "\($0[0].string!)=\($0[1].string!)" })
            let url = Self.deadwax.url(Routes.logStream, query: query)
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            diffs.text("\(label) path", parts.path, row["path"])
            // the same pairs as the server reads them back, however each was escaped
            diffs.check("\(label) as sent", (parts.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" },
                        row["query"].list.map { "\($0[0].string!)=\($0[1].string!)" })
        }
        diffs.done()
    }

    // MARK: who may

    @Test func whoOpensThePageIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["permissions"].list {
            let named = Set(row["permissions"].list.compactMap { Access.Permission(rawValue: $0.string!) })
            let admin = row["admin"].bool!
            let access = Access(user: "ethan", permissions: named, on: true, unverified: false, admin: admin)
            let label = "\(row["permissions"]) admin \(admin)"
            diffs.flag("\(label) allowed", EventLog.allowed(access), row["allowed"])
            diffs.flag("\(label) seesDetail", access.seesDetail, row["seesDetail"])
            // Manage's row is drawn for whoever the page opens for
            diffs.check("\(label) the row", Managing.tools(access).contains(.log), EventLog.allowed(access))
        }
        // logins off: the one admin, everything
        diffs.check("logins off", EventLog.allowed(Access(me: Me(user: "local", admin: true, auth: "off"))), true)
        diffs.done()
    }
}
