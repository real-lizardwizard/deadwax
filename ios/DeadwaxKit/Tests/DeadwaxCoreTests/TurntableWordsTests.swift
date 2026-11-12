import Foundation
import Testing
@testable import DeadwaxCore

/// The turntable's words (TurntableWords.swift) against what the web's own functions and files say
/// (Fixtures/deck/words.json): the spec's 2.9, word for word, and debugRows.ts's turntable rows over 41 reports.
@Suite struct TurntableWordsTests {
    let fixture: JSONValue

    init() throws {
        fixture = try DeckFixtures.json("words.json")
    }

    func n(_ value: JSONValue?) -> Double { DeckFixtures.number(value) }

    @Test func nowPlayingsWords() {
        #expect(TurntableWords.lookButton(showingTurntable: false) == fixture["lookButton"]?["cover"]?.string)
        #expect(TurntableWords.lookButton(showingTurntable: true) == fixture["lookButton"]?["turntable"]?.string)
        #expect(TurntableWords.record(playing: true) == fixture["record"]?["playing"]?.string)
        #expect(TurntableWords.record(playing: false) == fixture["record"]?["paused"]?.string)
        #expect(TurntableWords.arm == fixture["arm"]?.string)
        for row in fixture["armValues"]?.array ?? [] {
            let r = row.array ?? []
            #expect(TurntableWords.armValue(n(r[0]), n(r[1])) == r[2].string)
        }
        let lines = fixture["timeLines"]?.array ?? []
        #expect(lines.count == 7)
        for row in lines {
            let r = row.array ?? []
            let how = r[2].string.flatMap(TurntableDrag.Kind.init(rawValue:))
            #expect(TurntableWords.timeLine(n(r[0]), n(r[1]), how) == r[3].string, "timeLine(\(n(r[0])), \(n(r[1])), \(String(describing: how)))")
        }
    }

    @Test func theSilentLine() {
        let silent = fixture["silent"]
        #expect(TurntableWords.notFlac == silent?["words"]?["notFlac"]?.string)
        #expect(TurntableWords.noAudioWeb == silent?["words"]?["noAudio"]?.string)
        //? the phone's is the web's with the one word changed
        #expect(TurntableWords.noAudio == TurntableWords.noAudioWeb.replacingOccurrences(of: "This browser", with: "This phone"))
        for row in silent?["notes"]?.array ?? [] {
            let r = row.array ?? []
            let flac = r[0].bool == true, noAudio = r[1].bool == true
            let web = r[2].string
            let phone = TurntableWords.silentNote(flac: flac, noAudio: noAudio)
            #expect(phone == (web == TurntableWords.noAudioWeb ? TurntableWords.noAudio : web), "silentNote(\(flac), \(noAudio))")
        }
        #expect(TurntableWords.silentNote(flac: true, noAudio: true, airPlay: true) == TurntableWords.airPlay)
        #expect(TurntableWords.silentNote(flac: false, noAudio: false, airPlay: true) == TurntableWords.airPlay)
    }

    @Test func theFadersWords() {
        #expect(TurntableWords.fader == fixture["fader"]?.string)
        #expect(TurntableWords.readout(1) == fixture["readoutNormal"]?.string)
        for row in fixture["speeds"]?.array ?? [] {
            let r = row.array ?? []
            let speed = n(r[0])
            #expect(TurntableWords.speedLabel(speed) == r[1].string, "speedLabel(\(speed))")
            #expect(TurntableWords.speedWords(speed) == r[2].string, "speedWords(\(speed))")
            #expect(TurntableWords.readout(speed) == r[3].string, "readout(\(speed))")
            #expect(TurntableWords.chip(speed) == r[4].string, "chip(\(speed))")
        }
    }

    @Test func youPlaybacksWords() {
        #expect(TurntableWords.opensAs == fixture["looks"]?["title"]?.string)
        #expect(TurntableWords.lookCover == fixture["looks"]?["cover"]?.string)
        #expect(TurntableWords.lookTurntable == fixture["looks"]?["turntable"]?.string)
        #expect(TurntableWords.windDown == fixture["windDown"]?.string)
        //? the web's notes, less their last sentence about its desktop frame (the spec's 2.9)
        #expect("\(TurntableWords.lookNote) \(TurntableWords.lookNoteWebEnd)" == fixture["notes"]?["look"]?.string)
        #expect("\(TurntableWords.windDownNote) \(TurntableWords.windDownNoteWebEnd)" == fixture["notes"]?["windDown"]?.string)
    }

    func report(_ json: JSONValue?) -> DeckReport? {
        guard let json, !json.isNull else { return nil }
        let window = json["window"].flatMap { $0.isNull ? nil : $0 }.map {
            DeckReport.Window(start: n($0["start"]), end: n($0["end"]), kind: $0["kind"]?.string ?? "", decodedAt: n($0["decodedAt"]), bytes: n($0["bytes"]))
        }
        var health: DeckReport.DeckHealth?
        if let h = json["health"], !h.isNull {
            var made = DeckReport.DeckHealth()
            made.blocks = n(h["blocks"]); made.lateBlocks = n(h["lateBlocks"]); made.worstBlockMs = n(h["worstBlockMs"])
            made.frames = n(h["frames"]); made.slowFrames = n(h["slowFrames"]); made.worstFrameMs = n(h["worstFrameMs"])
            made.backMs = DeckFixtures.double(h["backMs"]); made.motorMs = DeckFixtures.double(h["motorMs"])
            made.notBack = n(h["notBack"]); made.interruptions = n(h["interruptions"])
            made.peaksHeld = DeckFixtures.double(h["peaksHeld"]); made.samplesHeld = n(h["samplesHeld"]); made.deepestHoldDb = n(h["deepestHoldDb"])
            health = made
        }
        var latency: DeckReport.Latency?
        if let l = json["latency"], !l.isNull {
            latency = DeckReport.Latency(base: DeckFixtures.double(l["base"]), output: DeckFixtures.double(l["output"]), speaker: DeckFixtures.double(l["speaker"]),
                                         block: DeckFixtures.double(l["block"]), design: DeckFixtures.double(l["design"]))
        }
        return DeckReport(context: json["context"]?.string ?? "", problem: json["problem"]?.string, voice: json["voice"]?.string, voiceWhy: json["voiceWhy"]?.string,
                          window: window, loading: json["loading"]?.bool == true, refused: json["refused"]?.string, failed: json["failed"]?.string,
                          fetched: n(json["fetched"]), lastFetchAt: n(json["lastFetchAt"]), clockStep: DeckFixtures.double(json["clockStep"]),
                          health: health, latency: latency)
    }

    @Test func debugsTurntableRows() {
        let cases = fixture["reports"]?.array ?? []
        #expect(cases.count == 41)
        for (i, case_) in cases.enumerated() {
            let made = report(case_["report"])
            let rows = TurntableDebugRows.turntableRows(made)
            let want = case_["rows"]?.array ?? []
            #expect(rows.count == want.count, "report \(i): \(rows.map(\.label)) against \(want.map { $0.array?[0].string ?? "" })")
            for (row, theirs) in zip(rows, want) {
                let t = theirs.array ?? []
                #expect(row.label == t[0].string && row.value == t[1].string && row.note == t[2].string, "report \(i): \(row) against \(t)")
            }
            #expect(TurntableDebugRows.latencyNote(made) == case_["latency"]?.string, "report \(i): latencyNote")
        }
    }

    @Test func debugsSpeedRow() {
        for (i, case_) in (fixture["speedRows"]?.array ?? []).enumerated() {
            var reading: SpeedReading?
            if let r = case_["reading"], !r.isNull {
                reading = SpeedReading(speed: n(r["speed"]), rate: n(r["rate"]), pitch: r["pitch"]?.string ?? "", refused: r["refused"]?.string,
                                       measured: DeckFixtures.double(r["measured"]))
            }
            let row = TurntableDebugRows.speedRow(reading)
            let t = case_["row"]?.array ?? []
            #expect(row.label == t[0].string && row.value == t[1].string && row.note == t[2].string, "speed row \(i): \(row)")
        }
    }
}
