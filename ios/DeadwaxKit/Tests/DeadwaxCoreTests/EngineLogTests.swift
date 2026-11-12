import Foundation
import Testing
@testable import DeadwaxCore

/// EngineLog: Debug's engine log - the last lines kept, the newest last, and nothing that could sign someone in.
@Suite struct EngineLogTests {
    @Test func linesAreKeptOldestFirstUpToTheCapacity() {
        let log = EngineLog(capacity: 3)
        #expect(log.snapshot() == .empty)
        #expect(log.snapshot().text == "")
        log.append("one")
        log.append("two")
        #expect(log.snapshot().lines == ["one", "two"])
        #expect(log.snapshot().first == 0)
        log.append("three")
        log.append("four")
        log.append("five")
        let shown = log.snapshot()
        #expect(shown.lines == ["three", "four", "five"])
        #expect(shown.total == 5)
        #expect(log.total == 5)
        #expect(shown.first == 2)
        #expect(shown.text == "three\nfour\nfive\n")
    }

    @Test func theRingGoesRoundManyTimes() {
        let log = EngineLog(capacity: 7)
        for line in 0..<1000 { log.append("line \(line)") }
        let shown = log.snapshot()
        #expect(shown.lines == (993..<1000).map { "line \($0)" })
        #expect(shown.first == 993)
        #expect(EngineLog(capacity: 0).capacity == 1)
        #expect(EngineLog().capacity == EngineLog.defaultCapacity)
    }

    @Test func theEnginesOwnWordsComeThroughUntouched() {
        // what PlaybackEngine's note() writes today, a line of each shape
        let lines = [
            "12.345 lane 44100 Hz x 2: its node at 48000 Hz",
            "12.345 the next song failed (deadwax answered 404 for this song.): said when the song heard ends",
            "12.345 failed: The song stopped arriving: The network connection was lost.",
            "12.345 lane 48000 Hz: this run's first render after 23.4 ms",
            "4096 rendered 512 of 4096 frames as silence: the output is stopped",
            "12.345 an edit: entry 4294967299 let go of; on after entry 4294967298",
            "12.345 failed: iOS couldn't open 3f9a0c.flac to play: The operation couldn't be completed.",
            "12.345 a configuration change: the output running, playing",
        ]
        let log = EngineLog()
        for line in lines { #expect(log.append(line) == line) }
        #expect(log.snapshot().lines == lines)
    }

    @Test func subsonicsAuthAndTheSessionAreScrubbed() {
        let cases: [(String, String)] = [
            ("GET /rest/stream?id=1&u=james&t=0a1b2c&s=c19b2d&v=1.16.1&c=deadwax",
             "GET /rest/stream?id=1&u=[scrubbed]&t=[scrubbed]&s=[scrubbed]&v=1.16.1&c=deadwax"),
            ("http://nd:4533/rest/ping.view?u=admin&p=enc:73656372657420&f=json",
             "http://nd:4533/rest/ping.view?u=[scrubbed]&p=[scrubbed]&f=json"),
            ("?apiKey=abc123&id=9", "?apiKey=[scrubbed]&id=9"),
            ("token=eyJhbGciOi.payload.sig; Path=/", "token=[scrubbed]; Path=/"),
            ("Cookie: deadwax_session=s3cr3t; other=1", "Cookie: [scrubbed]"),
            ("set-cookie: deadwax_session=abc; HttpOnly", "set-cookie: [scrubbed]"),
            ("Authorization: Bearer abc.def.ghi", "Authorization: [scrubbed]"),
            ("x-nd-authorization: Bearer abc.def.ghi", "x-nd-authorization: [scrubbed]"),
            ("asked with bearer abc.def.ghi, refused", "asked with bearer [scrubbed], refused"),
            ("http://james:hunter2@192.168.1.20:8090/deadwax/health", "http://[scrubbed]@192.168.1.20:8090/deadwax/health"),
            ("salt = 5f2a and password=hunter2", "salt = [scrubbed] and password=[scrubbed]"),
            ("deadwax_session=abc", "deadwax_session=[scrubbed]"),
            ("SESSION=abc&PASSWORD=def", "SESSION=[scrubbed]&PASSWORD=[scrubbed]"),
            ("COOKIE: abc", "COOKIE: [scrubbed]"),
            ("sent BeArEr abc", "sent BeArEr [scrubbed]"),
        ]
        for (line, expected) in cases {
            #expect(EngineLog.scrub(line) == expected, "\(line)")
        }
    }

    @Test func aKeyGivenWithAColonOrInJSONIsScrubbedToo() {
        let cases: [(String, String)] = [
            ("token: abc123", "token: [scrubbed]"),
            ("t: abc", "t: [scrubbed]"),
            ("PASSWORD : hunter2, then", "PASSWORD : [scrubbed], then"),
            ("x-deadwax-session: s.abc", "x-deadwax-session: [scrubbed]"),
            (#"{"password":"hunter2","username":"james"}"#, #"{"password":"[scrubbed]","username":"james"}"#),
            (#"{"apiKey" : "k 1 2", "id": "al-3"}"#, #"{"apiKey" : "[scrubbed]", "id": "al-3"}"#),
            ("'token': 'a b c' kept", "'token': '[scrubbed]' kept"),
            (#"{"api_key":"abc"}"#, #"{"api_key":"[scrubbed]"}"#),
            (#"{"t":"0a1b","s":"c19b"}"#, #"{"t":"[scrubbed]","s":"[scrubbed]"}"#),
        ]
        for (line, expected) in cases {
            #expect(EngineLog.scrub(line) == expected, "\(line)")
        }
        // a Bearer token given as a key's value: neither word is left
        #expect(!EngineLog.scrub("token: Bearer abc.def").contains("abc"))
    }

    @Test func aKeyIsOnlyScrubbedStandingOnItsOwn() {
        // "s" and "t" are Subsonic's salt and token, but the end of a longer name is not them
        let kept = ["status=401", "frames=4096", "format=raw", "rest=2", "id=al-3f", "v=1.16.1",
                    "write to a@b.c and back", "song@1x", "past: 3", "bypass: on", "Hz x 2: its node", "sets: 2",
                    "subsession: 4", #"{"tokens":"x"}"#]
        for line in kept {
            #expect(EngineLog.scrub(line) == line, "\(line)")
        }
    }

    @Test func theFirstLookFindsEveryShapeTheScrubTakesOut() {
        for line in ["a=b", "x@y", "Cookie", "xAUTHORIZATIONx", "bearer", "set-COOKIE", "token: x", "T:x", "p :x",
                     #""password":"x""#, "'Salt' : x", "x-deadwax-session: s", "api_key:x", "DEADWAX_SESSION:x"] {
            #expect(EngineLog.mayHoldSecret(line), "\(line)")
        }
        // every engine line has a ":" - one counts only after a secret's key standing on its own
        for line in ["", "12.345 lane 44100 Hz x 2: its node at 48000 Hz", "cooki", "authorizatio", "beare", "b", "c",
                     "12.345 failed: The song stopped arriving: The network connection was lost.", "past: 3",
                     "bypass: on", "x_t: 1", "2t: 1", "tokens: 2", ":x", "  : x"] {
            #expect(!EngineLog.mayHoldSecret(line), "\(line)")
        }
    }

    @Test func whatIsKeptIsTheScrubbedLine() {
        let log = EngineLog(capacity: 2)
        let kept = log.append("1.000 asked /stream?t=abc&s=def")
        #expect(kept == "1.000 asked /stream?t=[scrubbed]&s=[scrubbed]")
        #expect(log.snapshot().lines == [kept])
        #expect(!log.snapshot().text.contains("abc"))
    }

    @Test func manyWritersAndAReaderAtOnce() async {
        let log = EngineLog(capacity: 50)
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<4 {
                group.addTask {
                    for line in 0..<500 { log.append("w\(writer) \(line)") }
                }
            }
            group.addTask {
                for _ in 0..<200 {
                    let shown = log.snapshot()
                    #expect(shown.lines.count <= 50)
                    #expect(shown.first >= 0)
                }
            }
        }
        #expect(log.total == 2000)
        #expect(log.snapshot().lines.count == 50)
    }
}
