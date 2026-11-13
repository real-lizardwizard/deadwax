import CAudioRing
import Foundation
import Testing
@testable import DeadwaxCore

/// Turntable slice 2's Core (notes/ios-specs/turntable.md 4.3-4.5, 3.2): the window's plan on the grid and its
/// pre-roll, `/scrub`'s ask, header and statuses, the record's clock, the message slot, and CAudioRing's queue - the
/// parts of the deck engine that run on Linux too.
@Suite struct DeckWindowPlanTests {
    /// The grid start, its pre-roll and the frames dropped are whole at every rate a FLAC has and every output: 0.2 s
    /// is 2205 frames at 11.025 kHz, 60 of 44.1-to-48's 147-frame cycles.
    @Test func thePreRollIsWholeFramesAtEveryRate() throws {
        for fileRate in [11_025.0, 22_050, 32_000, 44_100, 48_000, 88_200, 96_000, 176_400, 192_000] {
            for output in [44_100.0, 48_000, 96_000] {
                for from in [0.0, 2, 40, 42, 600] {
                    let plan = try #require(DeckScrub.plan(from: from, seconds: 40, fileRate: fileRate, fileFrames: nil,
                                                           outputRate: output))
                    #expect(Double(plan.startFrame) == from * fileRate)
                    #expect(plan.start == from)
                    let preRoll = from == 0 ? 0.0 : 0.2
                    #expect(Double(plan.preRollFrames) == (preRoll * fileRate).rounded())
                    // the pre-roll's output frames, exactly - no rounding hidden in them
                    #expect(Double(plan.dropFrames) * fileRate == Double(plan.preRollFrames) * output,
                            "\(fileRate) -> \(output) from \(from)")
                    #expect(plan.converts == (fileRate != output))
                }
            }
        }
        // 44.1 to 48: 60 cycles of 147 input frames
        let cd = try #require(DeckScrub.plan(from: 42, seconds: 40, fileRate: 44_100, fileFrames: nil, outputRate: 48_000))
        #expect(cd.preRollFrames == 8_820 && cd.preRollFrames % 147 == 0 && cd.dropFrames == 9_600)
        #expect(cd.decodeFrom == 42 * 44_100 - 8_820)
    }

    /// 40 s at 48 kHz, the same bytes at a faster output (20 s at 96, 10 s at 192), the song's end permitting; nothing
    /// from past the end.
    @Test func theWindowsLengthIsCappedAndEndsWithTheSong() throws {
        let at48 = try #require(DeckScrub.plan(from: 2, seconds: 40, fileRate: 44_100, fileFrames: nil, outputRate: 48_000))
        #expect(at48.frames == 1_920_000 && at48.end == 42)
        let at96 = try #require(DeckScrub.plan(from: 2, seconds: 40, fileRate: 44_100, fileFrames: nil, outputRate: 96_000))
        #expect(at96.frames == 1_920_000 && at96.end == 22)
        let at192 = try #require(DeckScrub.plan(from: 2, seconds: 40, fileRate: 192_000, fileFrames: nil, outputRate: 192_000))
        #expect(at192.end == 12)
        let at441 = try #require(DeckScrub.plan(from: 2, seconds: 40, fileRate: 44_100, fileFrames: nil, outputRate: 44_100))
        #expect(at441.frames == 1_764_000)
        // a song of 30.5 s: from 20, 10.5 s of it
        let short = try #require(DeckScrub.plan(from: 20, seconds: 40, fileRate: 44_100, fileFrames: 1_345_050,
                                                outputRate: 48_000))
        #expect(short.frames == 504_000 && short.end == 30.5)
        // a length that isn't whole at the output: rounded down, never a frame the file can't fill
        let odd = try #require(DeckScrub.plan(from: 0, seconds: 40, fileRate: 44_100, fileFrames: 44_101, outputRate: 48_000))
        #expect(odd.frames == 48_001)
        #expect(DeckScrub.plan(from: 32, seconds: 40, fileRate: 44_100, fileFrames: 1_345_050, outputRate: 48_000) == nil)
        #expect(DeckScrub.plan(from: 2, seconds: 0, fileRate: 44_100, fileFrames: nil, outputRate: 48_000) == nil)
    }

    /// `/scrub`'s ask (4.5): the grid start less the pre-roll; the window, the pre-roll and a second; at most 60 - and
    /// never above the route's bound at any output.
    @Test func scrubIsAskedFromThePreRollWithItsSlack() {
        let ask = DeckScrub.ask(from: 42, seconds: 40, outputRate: 48_000)
        #expect(abs(ask.at - 41.8) < 1e-12 && abs(ask.seconds - 41.2) < 1e-12)
        let first = DeckScrub.ask(from: 0, seconds: 40, outputRate: 48_000)
        #expect(first.at == 0 && first.seconds == 41)
        let fast = DeckScrub.ask(from: 42, seconds: 40, outputRate: 96_000)
        #expect(abs(fast.seconds - 21.2) < 1e-12)
        for output in [8_000.0, 22_050, 44_100, 48_000] {
            #expect(DeckScrub.ask(from: 100, seconds: 100, outputRate: output).seconds <= Double(DeckScrub.maxSeconds))
        }
        #expect(DeckScrub.query(at: 41.8, seconds: 41.2).map { "\($0.0)=\($0.1)" } == ["at=41.8", "seconds=41.2"])
    }

    /// `X-Deadwax-Window`: three whole numbers or nothing; the window's end from first + samples; the answer's frames
    /// skipped to reach the pre-roll.
    @Test func theWindowHeaderIsReadAndPlacesTheAnswer() throws {
        #expect(DeckScrub.Header.parse("1838592/1862656/44100") == .init(first: 1_838_592, samples: 1_862_656, rate: 44_100))
        for bad in [nil, "", "1/2", "1/2/3/4", "a/2/3", "-1/2/3", "1/2/0", "1.5/2/3", "1//3"] as [String?] {
            #expect(DeckScrub.Header.parse(bad) == nil, "\(bad ?? "nil")")
        }
        // asked from 41.8 s at 44.1 kHz; deadwax's frame began at 1,838,592 (before 1,843,380) and holds 42.24 s
        let header = DeckScrub.Header(first: 1_838_592, samples: 1_862_656, rate: 44_100)
        let placed = try DeckScrub.plan(from: 42, seconds: 40, header: header, outputRate: 48_000).get()
        #expect(placed.skip == 42 * 44_100 - 8_820 - 1_838_592)
        #expect(placed.plan.frames == 1_920_000)
        // a hi-res answer cut short at 8 MB: its end from what came, not from what was asked
        let hiRes = DeckScrub.Header(first: 8_000_000, samples: 2_150_400, rate: 192_000)
        let cut = try DeckScrub.plan(from: 42, seconds: 40, header: hiRes, outputRate: 48_000).get()
        #expect(abs(cut.plan.end - Double(hiRes.end) / 192_000) < 1e-9 && cut.plan.frames == 521_600)
        #expect(cut.skip == 42 * 192_000 - 38_400 - 8_000_000)
        // an answer that began after where it was asked can't hold the pre-roll
        let late = DeckScrub.Header(first: 1_843_381, samples: 100_000, rate: 44_100)
        #expect(throws: DeckWindowError.self) { try DeckScrub.plan(from: 42, seconds: 40, header: late, outputRate: 48_000).get() }
        let past = DeckScrub.Header(first: 0, samples: 44_100, rate: 44_100)
        #expect(throws: DeckWindowError.pastTheEnd) { try DeckScrub.plan(from: 2, seconds: 40, header: past, outputRate: 48_000).get() }
    }

    @Test func scrubsStatusesAreTheDecksWords() {
        #expect(DeckScrub.failure(status: 204, detail: nil, words: "x") == nil)
        #expect(DeckScrub.failure(status: 415, detail: "it is MP3", words: "x") == .notFlac("it is MP3"))
        #expect(DeckScrub.failure(status: 416, detail: nil, words: "x") == .pastTheEnd)
        #expect(DeckScrub.failure(status: 503, detail: nil, words: "Navidrome broke off") == .failed("Navidrome broke off"))
        #expect(DeckScrub.fileName(songID: "a1B2-c_d", first: 42) == "a1B2-c_d-42.flac")
        #expect(DeckScrub.fileName(songID: "../x y", first: 0) == "___x_y-0.flac")
        #expect(DeckScrub.fileName(songID: "", first: 7) == "song-7.flac")
    }

    /// The client asks `at` and `seconds` only, reads the header, and takes each status as the deck does.
    @Test func theClientsScrubCall() async throws {
        let (deadwax, transport) = client()
        let flac = Data([0x66, 0x4C, 0x61, 0x43, 1, 2, 3])
        transport.handle("/deadwax/navidrome/scrub/song1") { (_: HTTPRequest) -> HTTPResponse in
            HTTPResponse(status: 200, headers: ["X-Deadwax-Window": "100/200/44100"], body: flac)
        }
        let got = try #require(try await deadwax.scrub(songID: "song1", at: 41.8, seconds: 41.2))
        let answer = try got.get()
        #expect(answer.flac == flac && answer.header == .init(first: 100, samples: 200, rate: 44_100))
        let sent = try #require(transport.last)
        #expect(sent.method == "GET" && sent.url.path == "/deadwax/navidrome/scrub/song1")
        #expect(sent.url.query == "at=41.8&seconds=41.2")
        #expect(sent.headers["Accept"] == "audio/flac")

        transport.answer("/deadwax/navidrome/scrub/mp3", 415, #"{"detail":"it isn't a FLAC file (it is MP3)"}"#)
        #expect(try await deadwax.scrub(songID: "mp3", at: 0, seconds: 1)?.failure == .notFlac("it isn't a FLAC file (it is MP3)"))
        transport.answer("/deadwax/navidrome/scrub/bare", 415, "")
        #expect(try await deadwax.scrub(songID: "bare", at: 0, seconds: 1)?.failure == .notFlac(nil))
        transport.answer("/deadwax/navidrome/scrub/end", 416, #"{"detail":"past the end"}"#)
        #expect(try await deadwax.scrub(songID: "end", at: 9_999, seconds: 1)?.failure == .pastTheEnd)
        transport.answer("/deadwax/navidrome/scrub/gone", 204, "")
        #expect(try await deadwax.scrub(songID: "gone", at: 0, seconds: 1) == nil)
        transport.answer("/deadwax/navidrome/scrub/broke", 503, #"{"detail":"Navidrome broke off"}"#)
        if case .failed(let words)? = try await deadwax.scrub(songID: "broke", at: 0, seconds: 1)?.failure {
            #expect(words.contains("Navidrome broke off"))
        } else {
            Issue.record("a 503 is failed, with deadwax's words")
        }
        transport.answer("/deadwax/navidrome/scrub/noheader", 200, "fLaC")
        if case .failed? = try await deadwax.scrub(songID: "noheader", at: 0, seconds: 1)?.failure {} else {
            Issue.record("an answer with no X-Deadwax-Window is failed")
        }
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@Suite struct DeckLeadTests {
    /// The largest end-of-block lead over 1.5 s; free while quiet; slewed at 0.5 ms a second under a sound; never
    /// stepping under one.
    @Test func theClockFollowsTheLargestLead() {
        var lead = DeckLead(floor: 0.0426)
        defer { lead.deallocate() }
        #expect(lead.value == 0.0426)
        let rate = 48_000.0, frames = 1_024
        let block = Double(frames) / rate
        var host = 1_000.0
        // quiet, every block entered 5 ms after it is presented: lead = block - 5 ms
        for _ in 0..<100 {
            lead.block(hostOut: host, frames: frames, rate: rate, entry: host + 0.005, sounding: false)
            host += block
        }
        #expect(abs(lead.value - (block - 0.005)) < 1e-12 && lead.target == lead.value)
        // one late-entered block's lead is smaller; one early, larger - it is the largest for 1.5 s, then forgotten
        lead.block(hostOut: host, frames: frames, rate: rate, entry: host - 0.004, sounding: false)
        host += block
        #expect(abs(lead.value - (block + 0.004)) < 1e-12)
        var blocks = 0
        while lead.value > block - 0.004 {
            lead.block(hostOut: host, frames: frames, rate: rate, entry: host + 0.005, sounding: false)
            host += block
            blocks += 1
        }
        #expect(blocks == Int((DeckLead.windowS / block).rounded(.up)), "forgotten once it is 1.5 s old")
        // under a sound: a larger lead is reached at 0.5 ms a second, never stepped to
        let before = lead.value
        var largestStep = 0.0
        for _ in 0..<470 {
            let was = lead.value
            lead.block(hostOut: host, frames: frames, rate: rate, entry: host - 0.010, sounding: true)
            largestStep = max(largestStep, abs(lead.value - was))
            host += block
        }
        #expect(largestStep <= DeckLead.slew * block * (1 + 1e-9))
        #expect(abs((lead.value - before) - DeckLead.slew * 470 * block) < 1e-9)
        #expect(abs(lead.largestSounding - (block + 0.010)) < 1e-12)
        // quiet again: straight to it
        lead.block(hostOut: host, frames: frames, rate: rate, entry: host - 0.010, sounding: false)
        #expect(abs(lead.value - (block + 0.010)) < 1e-12)
    }

    /// A full deque (the smallest blocks, leads always falling) loses its oldest, never grows.
    @Test func theDequeIsBoundedAndARouteChangeStartsAgain() {
        var lead = DeckLead(floor: 0.01)
        defer { lead.deallocate() }
        var host = 0.0
        for i in 0..<5_000 {
            lead.block(hostOut: host, frames: 16, rate: 48_000, entry: host + Double(i) * 1e-9, sounding: false)
            host += 16 / 48_000.0
        }
        #expect(lead.count <= DeckLead.capacity)
        lead.restart(floor: 0.05)
        #expect(lead.value == 0.05 && lead.count == 0 && lead.blocks == 5_000)
    }
}

@Suite struct DeckSlotTests {
    /// Every message through a slot and back, the same message.
    @Test func everyMessageRoundTrips() {
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        defer { samples.deallocate() }
        let window = VoiceWindow(first: samples, second: samples + 2, length: 2, start: 42, rate: 48_000)
        let messages: [VoiceMessage] = [
            .window(window), .window(nil), .take(at: 1.5, rate: -2, time: 1_000.25, until: 1_000.37),
            .drive(at: 3, rate: 1, accel: nil, time: 4, until: .infinity), .drive(at: 3, rate: 1, accel: -0.5, time: 4, until: 9),
            .hand(at: 7.125, time: 8.5), .fade(seconds: 0.03), .stop,
        ]
        for message in messages {
            let slot = DeckSlot(message, id: 7)
            #expect(String(describing: slot.message) == String(describing: message))
            var isWindow = false
            if case .window = message { isWindow = true }
            #expect(slot.replacesWindow == isWindow)
        }
        let windowSlot = DeckSlot(.window(window), id: 3)
        if case .window(let back?) = windowSlot.message {
            #expect(back.first == window.first && back.second == window.second && back.length == 2 && back.start == 42)
        } else {
            Issue.record("the window came back")
        }
        #expect(windowSlot.id == 3)
        #expect(_isPOD(DeckSlot.self) && _isPOD(VoiceState.self) && _isPOD(DeckHeardSlot.self))
    }

    /// The voice's sounding, as its clock reads it.
    @Test func soundingIsTheVoicesOwnGain() {
        var state = DeckRender.newState()
        defer { state.deallocate() }
        #expect(!withUnsafePointer(to: &state) { DeckRender.sounding($0) })
        withUnsafeMutablePointer(to: &state) { DeckRender.command($0, .take(at: 0, rate: 1, time: 0, until: 1), now: 0, rate: 48_000) }
        #expect(withUnsafePointer(to: &state) { DeckRender.sounding($0) })
    }
}

@Suite struct DeckQueueTests {
    /// CAudioRing's queue: every slot in order, a full one refused, a power of two only.
    @Test func theQueueKeepsEveryOneInOrder() throws {
        #expect(audio_fifo_make(0) == nil && audio_fifo_make(3) == nil && audio_fifo_make(1) == nil)
        let fifo = try #require(audio_fifo_make(8))
        defer { audio_fifo_free(fifo) }
        #expect(audio_fifo_capacity(fifo) == 8)
        var storage = [Int](repeating: -1, count: 8)
        var slot: UInt32 = 0
        var next = 0, expected = 0
        // wrap the counts many times
        for round in 0..<1_000 {
            let put = round % 9
            var refused = 0
            for _ in 0..<put {
                if audio_fifo_reserve(fifo, &slot) {
                    storage[Int(slot)] = next
                    next += 1
                    audio_fifo_commit(fifo)
                } else {
                    refused += 1
                }
            }
            #expect(audio_fifo_count(fifo) <= 8)
            if audio_fifo_count(fifo) == 8 { #expect(!audio_fifo_reserve(fifo, &slot)) }
            let take = (round * 7) % 9
            for _ in 0..<take {
                guard audio_fifo_peek(fifo, &slot) else { break }
                #expect(storage[Int(slot)] == expected)
                expected += 1
                audio_fifo_release(fifo)
            }
            _ = refused
        }
        while audio_fifo_peek(fifo, &slot) {
            #expect(storage[Int(slot)] == expected)
            expected += 1
            audio_fifo_release(fifo)
        }
        #expect(expected == next && audio_fifo_count(fifo) == 0)
    }

    /// Two threads, a million slots: the consumer sees each the producer committed, in order, whole.
    @Test func theQueueHoldsAcrossThreads() async throws {
        let fifo = try #require(audio_fifo_make(256))
        defer { audio_fifo_free(fifo) }
        let storage = UnsafeMutablePointer<(UInt64, UInt64)>.allocate(capacity: 256)
        defer { storage.deallocate() }
        let total: UInt64 = 1_000_000
        let box = (fifo: UInt(bitPattern: fifo), storage: UInt(bitPattern: storage))
        let producer = Thread {
            let fifo = OpaquePointer(bitPattern: box.fifo)!
            let storage = UnsafeMutablePointer<(UInt64, UInt64)>(bitPattern: box.storage)!
            var slot: UInt32 = 0
            var n: UInt64 = 0
            while n < total {
                if audio_fifo_reserve(fifo, &slot) {
                    storage[Int(slot)] = (n, n &* 2_654_435_761)
                    audio_fifo_commit(fifo)
                    n += 1
                }
            }
        }
        producer.start()
        var slot: UInt32 = 0
        var seen: UInt64 = 0, wrong = 0
        while seen < total {
            if audio_fifo_peek(fifo, &slot) {
                let (n, check) = storage[Int(slot)]
                if n != seen || check != n &* 2_654_435_761 { wrong += 1 }
                seen += 1
                audio_fifo_release(fifo)
            }
        }
        #expect(wrong == 0 && seen == total)
    }
}

@Suite struct DeckEngineWordsTests {
    @Test func thePhonesOwnRows() {
        #expect(TurntableDebugRows.clockRow(lead: nil, largest: nil, underHand: false).value
                == "The record's engine hasn't rendered yet")
        #expect(TurntableDebugRows.clockRow(lead: 0.0239, largest: 0.0246, underHand: true).value
                == "The record's clock runs 23.9 ms behind the render's time stamps; the largest lead under the last hand 24.6 ms")
        #expect(TurntableDebugRows.clockRow(lead: 0.0239, largest: 0.0241, underHand: false).value
                == "The record's clock runs 23.9 ms behind the render's time stamps; the largest lead over the last 1.5 s 24.1 ms")
        #expect(TurntableDebugRows.messagesDroppedRow(0) == nil)
        #expect(TurntableDebugRows.messagesDroppedRow(1)?.value == "1 of the record's messages was dropped")
        #expect(TurntableDebugRows.messagesDroppedRow(3)?.value == "3 of the record's messages were dropped")
        #expect(TurntableDebugRows.windowMadeRow(took: 0.214, seconds: 40, rate: 44_100).value == "0.21 s for 40 s of a 44.1 kHz song")
        #expect(TurntableDebugRows.trialButton(running: false) == "Start" && TurntableDebugRows.trialButton(running: true) == "Stop")
        #expect(TurntableDebugRows.trialRow(rate: 48_000, blocks: 0, starts: 0, lastStart: nil, failure: nil).value == "Not started")
        #expect(TurntableDebugRows.trialRow(rate: 48_000, blocks: 4_410, starts: 1, lastStart: 0.0123, failure: nil).value
                == "48 kHz, 4410 blocks rendered; started once, the last start 12.3 ms")
        #expect(TurntableDebugRows.trialRow(rate: 44_100, blocks: 9, starts: 3, lastStart: nil, failure: nil).value
                == "44.1 kHz, 9 blocks rendered; started 3 times")
        #expect(TurntableDebugRows.trialRow(rate: 0, blocks: 0, starts: 0, lastStart: nil, failure: "no output").value
                == "Couldn't start: no output")
    }
}
