import Foundation
import Testing
@testable import DeadwaxCore

// The resume cases export-traces.cjs wrote from the web's own lib/resume.ts (Fixtures/resume/cases.json): every
// snapshot the phone writes must be the web's text to the UTF-16 unit, and every text the web writes - or anything
// else in a record - the phone must read exactly as the web does.

@Suite struct ResumeCaseTests {
    struct Loaded {
        let header: JSONValue
        let songs: ResumeSongs
        let cases: [String: [JSONValue]]
    }

    static func load() throws -> Loaded {
        let json = try Fixtures.json("resume/cases.json")
        let songs = try ResumeSongs(json["songs"])
        var cases: [String: [JSONValue]] = [:]
        for item in try #require(json["cases"]?.array) { cases[item["kind"]?.string ?? "?", default: []].append(item) }
        return Loaded(header: json, songs: songs, cases: cases)
    }

    static func setting(_ json: JSONValue?) throws -> Normalization {
        try #require(json?.string.flatMap(Normalization.init(rawValue:)), "no setting")
    }

    @Test func theConstantsAreTheWebs() throws {
        let c = try #require(try Self.load().header["constants"])
        #expect(c["RESUME_MAX"]?.int == Resume.maxEntries)
        #expect(c["RESUME_BEFORE"]?.int == Resume.before)
        #expect(c["RESUME_SNAPSHOT_MAX"]?.int == Resume.snapshotMax)
        #expect(c["RESUME_EVERY_S"]?.int == Resume.everySeconds)
        #expect(c["RESUME_FULL_WAIT_MS"]?.int.map(Int64.init) == Resume.fullWaitMs)
        #expect(c["RESUME_AT_WAIT_MS"]?.int.map(Int64.init) == Resume.atWaitMs)
        #expect(c["RESUME_RECHECK_MS"]?.int.map(Int64.init) == Resume.recheckMs)
        #expect(c["MARGIN_MS"]?.int.map(Int64.init) == Resume.marginMs)
        #expect(c["DEADWAX_CLIENT"]?.string == Resume.deadwaxClient)
        #expect(c["iPhoneLabel"]?.string == Resume.label)
        #expect(c["OWED_ORDER"]?.array?.compactMap(\.string) == Resume.owedOrder.map(\.rawValue))
        #expect(c["DEVICE_LETTERS"]?.string == String(DeviceID.alphabet))
        #expect(c["DEVICE_ID"]?.string == "^[A-Za-z0-9_-]{8,64}$", "persisted.ts's DEVICE_ID changed: DeviceID.isValid with it")
        #expect(DeviceID.lengths == 8...64)
        #expect(c["DEVICE_LENGTH"]?.int == DeviceID.length)
        #expect(c["playerDevice"]?.string == DeviceID.storageKey)
        #expect(c["playerNormalization"]?.string == Normalization.storageKey)
        #expect(Set(c["prototypeNames"]?.array?.compactMap(\.string) ?? []) == WebJSON.prototypeNames)
    }

    @Test func windowsRelevelsAndWords() throws {
        let loaded = try Self.load()
        for item in loaded.cases["window", default: []] {
            let window = windowOf(try #require(item["count"]?.int), try #require(item["index"]?.int))
            #expect(window.start == item["start"]?.int && window.end == item["end"]?.int, "\(describe(item))")
        }
        for item in loaded.cases["relevel", default: []] {
            let level = item["level"]?.string.flatMap(Level.init(rawValue:))
            #expect(relevel(level, try Self.setting(item["setting"]))?.rawValue == item["result"]?.string, "\(describe(item))")
        }
        for item in loaded.cases["pickedUp", default: []] {
            let from: PickedFrom? = item["from"]?["device"]?.string.map(PickedFrom.device)
                ?? item["from"]?["app"]?.string.map(PickedFrom.app)
            #expect(pickedUpWords(from, shared: try #require(item["shared"]?.bool as Bool?)) == item["result"]?.string, "\(describe(item))")
        }
        #expect(loaded.cases["window"]?.count == 15 && loaded.cases["relevel"]?.count == 12 && loaded.cases["pickedUp"]?.count == 22)
    }

    @Test func theSnapshotIsTheWebsToTheUnit() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["toSave", default: []]
        #expect(cases.count == 33) // (2.1.18) with v2, reached and starts; (2.1.23) gone back twice
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let queue = try #require(loaded.songs.queue(item["queue"]), "\(label): the queue doesn't rebuild")
            let saving = toSave(queue, position: try #require(item["position"]?.double))
            let wanted = try #require(item["saving"])
            #expect(saving.ids == wanted["ids"]?.array?.compactMap(\.string), "\(label): ids")
            #expect(saving.index == wanted["index"]?.int && saving.start == wanted["start"]?.int, "\(label): index/start")
            #expect(saving.position == wanted["position"]?.double, "\(label): position")
            let snapshot = wanted["snapshot"]?.string
            #expect(sameText(saving.snapshot, snapshot),
                    "\(label): snapshot differs from unit \(firstDifference(saving.snapshot, snapshot))")
        }
    }

    @Test func recipesAndTheCap() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["toSaveRecipe", default: []]
        #expect(cases.count == 6)
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let recipe = try #require(item["recipe"])
            var tracks = rAlbum(try #require(recipe["n"]?.int), recipe["prefix"]?.string ?? "")
            if let pad = recipe["pad"], pad != .null {
                let at = try #require(tracks.firstIndex { $0.id == pad["id"]?.string })
                tracks[at].title += String(repeating: try #require(pad["unit"]?.string), count: try #require(pad["count"]?.int))
                    + String(repeating: "x", count: try #require(pad["tail"]?.int))
            }
            let queue = startUpNext(tracks, start: try #require(recipe["start"]?.int), id: try #require(recipe["id"]?.string))
                .at(try #require(recipe["index"]?.int))
            let saving = toSave(queue, position: try #require(recipe["position"]?.double))
            let wanted = try #require(item["saving"])
            #expect(saving.ids.count == wanted["count"]?.int, "\(label)")
            #expect(saving.ids.first == wanted["first"]?.string && saving.ids.last == wanted["last"]?.string, "\(label)")
            #expect(saving.index == wanted["index"]?.int && saving.start == wanted["start"]?.int, "\(label)")
            #expect(saving.snapshot?.utf16.count == wanted["length"]?.int, "\(label): length")
            #expect(saving.snapshot.map(unitHash) == wanted["hash"]?.string, "\(label): hash")
            #expect(saving.snapshot.map { unitPrefix($0, 120) } == wanted["head"]?.string.map { Array($0.utf16) }, "\(label): head")
        }
    }

    /// (the web's 2.1.22) The library's shuffle a recipe makes, as export-traces.cjs's fromPagedRecipe makes it: its
    /// pages fetched one after another, played to `index`, entries taken out, songs played next, a Repeat, Repeat One's
    /// copies played.
    static func pagedQueue(_ recipe: JSONValue) throws -> UpNextQueue {
        let size = try #require(recipe["page"]?.int)
        let pages = try #require(recipe["pages"]?.int)
        let prefix = try #require(recipe["prefix"]?.string)
        let token = try #require(recipe["token"]?.string)
        let total = size * pages + (try #require(recipe["more"]?.int))
        let page = { (k: Int) in rAlbum(size, "\(prefix)\(k)-", level: .track) }
        let paged = Paged(token: token, total: total, fetched: size, scope: .yours, level: .track)
        var queue = startUpNext(page(0), start: 0, paged: paged, id: try #require(recipe["id"]?.string))
        for k in 1..<pages { queue = withMore(queue, token: token, tracks: page(k)) }
        queue = queue.at(try #require(recipe["index"]?.int))
        for place in try #require(recipe["without"]?.array) {
            queue = withoutKey(queue, queue.upNext!.marks[try #require(place.int)].key)
        }
        let next = try #require(recipe["next"]?.int)
        if next > 0 { queue = withNext(queue, rAlbum(next, "\(prefix)n", level: .track)) }
        if let mode = recipe["repeat"]?.string.flatMap(Repeat.init(rawValue:)) { queue = toppedUp(withRepeat(queue, mode), mode) }
        for _ in 0..<(try #require(recipe["copies"]?.int)) { queue = toppedUp(queue.at(queue.index + 1), .one) }
        return queue
    }

    /// (the web's 2.1.22) A library's shuffle thousands of songs in: the snapshot the web's text, under the cap, its list
    /// the songs its window names - and read back a library's shuffle still, its feed where it was.
    @Test func librariesShufflesThousandsOfSongsIn() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["toSavePaged", default: []]
        #expect(cases.count == 6)
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let recipe = try #require(item["recipe"])
            let queue = try Self.pagedQueue(recipe)
            let saving = toSave(queue, position: try #require(recipe["position"]?.double))
            let wanted = try #require(item["saving"])
            #expect(saving.ids.count == wanted["count"]?.int, "\(label)")
            #expect(saving.ids.first == wanted["first"]?.string && saving.ids.last == wanted["last"]?.string, "\(label)")
            #expect(saving.index == wanted["index"]?.int && saving.start == wanted["start"]?.int, "\(label)")
            #expect(queue.upNext?.source.count == wanted["queueSource"]?.int && queue.upNext?.left.count == wanted["left"]?.int,
                    "\(label): the queue isn't the web's")
            let snapshot = try #require(saving.snapshot, "\(label): over the cap")
            #expect(snapshot.utf16.count == wanted["length"]?.int, "\(label): length")
            #expect(unitHash(snapshot) == wanted["hash"]?.string, "\(label): hash")
            #expect(unitPrefix(snapshot, 120) == wanted["head"]?.string.map { Array($0.utf16) }, "\(label): head")
            let bare = queue.tracks[saving.start..<(saving.start + saving.ids.count)].map { track -> QueueTrack in
                var plain = track
                plain.level = nil
                return plain
            }
            let back = try #require(fromSnapshot(snapshot, tracks: bare, index: saving.index, setting: .auto), "\(label): not read back")
            let was = try #require(item["back"])
            #expect(back.tracks.count == was["tracks"]?.int && back.index == was["index"]?.int, "\(label): read back")
            #expect(back.upNext?.source.count == wanted["source"]?.int && was["source"]?.bool == true, "\(label): its list")
            let paged = try #require(back.upNext?.paged, "\(label): read back without its feed")
            #expect(paged.token == was["paged"]?["token"]?.string && paged.total == was["paged"]?["total"]?.int
                    && paged.fetched == was["paged"]?["fetched"]?.int, "\(label): its feed")
            let mode = recipe["repeat"]?.string.flatMap(Repeat.init(rawValue:)) ?? .off
            #expect(upNextView(back, mode, limit: Int.max).list?.rows.count ?? 0 == was["ahead"]?.int, "\(label): Up Next")
        }
    }

    @Test func snapshotsReadAsTheWebReadsThem() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["fromSnapshot", default: []]
        #expect(cases.count == 327) // (2.1.18) with v 1 or 2, reached and starts, read or refused; (2.1.23) the record
        var nils = 0
        var fresh = 0
        var held = 0
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let tracks = try #require(loaded.songs.tracks(item["tracks"]), "\(label): tracks")
            //? (2.1.15) the queue the player holds, when the case has one
            var holding: UpNextQueue?
            if let record = item["holding"] {
                holding = try #require(loaded.songs.queue(record), "\(label): the queue held doesn't rebuild")
                held += 1
            }
            let back = fromSnapshot(item["snapshot"]?.string, tracks: tracks, index: try #require(item["index"]?.int),
                                    setting: try Self.setting(item["setting"]), holding: holding,
                                    newId: { ResumeSongs.freshId })
            if item["result"]?["upNext"]?["id"] == .null { fresh += 1 }
            let wanted: UpNextQueue?
            if item["result"] == .null {
                wanted = nil
                nils += 1
            } else {
                let rebuilt = try #require(loaded.songs.queue(item["result"]), "\(label): the result doesn't rebuild")
                wanted = rebuilt
            }
            let difference = queueDifference(back, wanted)
            #expect(difference == nil, "\(label): \(difference ?? "")")
        }
        #expect(nils == 91 && fresh == 49 && held == 16)
    }

    /// (2.1.15) Whether a queue read back without an id is the queue held: the web's sameQueue, case by case.
    @Test func whetherItIsTheQueueHeld() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["sameQueue", default: []]
        #expect(cases.count == 12)
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let held = try #require(loaded.songs.queue(item["held"]), "\(label): held")
            let put = try #require(loaded.songs.queue(item["put"]), "\(label): put")
            #expect(sameQueue(held, put) == item["result"]?.bool, "\(label)")
        }
    }

    @Test func levelsOfASnapshotThatDoesntReadWhole() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["savedLevels", default: []]
        #expect(cases.count == 18)
        for item in cases {
            let got = savedLevels(item["snapshot"]?.string, count: try #require(item["count"]?.int)).map { $0?.rawValue }
            let wanted = try #require(item["result"]?.array).map(\.string)
            #expect(got == wanted, "\(describe(item["snapshot"])) \(item["count"]?.int ?? -1)")
        }
    }

    @Test func navidromesSongsAsQueueEntries() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["shuffledTrack", default: []]
        #expect(cases.count == 4)
        for item in cases {
            let song = try JSONDecoder().decode(Song.self, from: Data(try #require(item["song"]?.string).utf8))
            #expect(shuffledTrack(song) == queueTrack(try #require(item["result"])), "\(song.id)")
        }
    }

    @Test func whatIsPutBack() throws {
        let loaded = try Self.load()
        let cases = loaded.cases["resumed", default: []]
        #expect(cases.count == 56)
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let answer = try JSONDecoder().decode(QueueAnswer.self, from: Data(try #require(item["answer"]?.string).utf8))
            let holding = try item["holding"].map { try #require(loaded.songs.queue($0), "\(label): the queue held") }
            let back = resumed(answer, setting: try Self.setting(item["setting"]), device: try #require(item["device"]?.string),
                               holding: holding, newId: { ResumeSongs.freshId })
            guard let wanted = item["result"], wanted != .null else {
                #expect(back == nil, "\(label)")
                continue
            }
            let got = try #require(back, "\(label): nothing put back")
            let queue = try #require(loaded.songs.queue(wanted["queue"]), "\(label): the result doesn't rebuild")
            let difference = queueDifference(got.queue, queue)
            #expect(difference == nil, "\(label): \(difference ?? "")")
            #expect(got.position == wanted["position"]?.double, "\(label): position")
            #expect(got.exact == wanted["exact"]?.bool, "\(label): exact")
            let from: PickedFrom? = wanted["from"]?["device"]?.string.map(PickedFrom.device)
                ?? wanted["from"]?["app"]?.string.map(PickedFrom.app)
            #expect(got.from == from, "\(label): from")
        }
    }

    @Test func whenASaveIsDue() throws {
        let loaded = try Self.load()
        let queuesCase = try #require(loaded.cases["saveQueues"]?.first?["queues"]?.object)
        var queues: [String: UpNextQueue] = [:]
        for (name, record) in queuesCase {
            let queue = try #require(loaded.songs.queue(record), "\(name) doesn't rebuild")
            queues[name] = queue
        }
        let cases = loaded.cases["saveDue", default: []]
        #expect(cases.count == 735)
        let int64 = { (json: JSONValue?) -> Int64? in json?.int.map(Int64.init) }
        for item in cases {
            let label = item["label"]?.string ?? "?"
            let c = try #require(item["clock"])
            var baseline: SaveBaseline?
            if let saved = c["saved"], saved != .null {
                let queue = try #require(queues[saved["queue"]?.string ?? ""])
                baseline = SaveBaseline(tracks: queue.tracks, upNext: queue.upNext, index: try #require(saved["index"]?.int),
                                        position: try #require(saved["position"]?.double), start: try #require(saved["start"]?.int),
                                        count: try #require(saved["count"]?.int))
            }
            let clock = SaveClock(saved: baseline, idsRev: c["idsRev"]?.int, countFrom: int64(c["countFrom"]),
                                  changedAt: int64(c["changedAt"]), failedAt: int64(c["failedAt"]))
            let name = item["queue"]?.string ?? ""
            let queue = try #require(queues[name])
            let position = try #require(item["position"]?.double)
            let now = try #require(int64(item["now"]))
            #expect(changedSince(baseline, queue, position: position)?.rawValue == item["changed"]?.string,
                    "\(label), \(name) at \(position): changed")
            var results = ""
            for playing in [false, true] {
                for trigger in [SaveTrigger.wait, .position, .pause, .hidden] {
                    let due = saveDue(clock, queue, position: position, playing: playing, now: now, trigger: trigger)
                    results += due == .full ? "f" : due == .at ? "a" : "-"
                }
            }
            #expect(results == item["results"]?.string, "\(label), \(name) at \(position)")
        }
    }

    @Test func numbersAsJavaScriptWritesThem() throws {
        let cases = try Self.load().cases["number", default: []]
        #expect(cases.count == 551)
        for item in cases {
            let bits = try #require(item["bits"]?.string.flatMap { UInt64($0, radix: 16) })
            let x = Double(bitPattern: bits)
            let text = try #require(item["text"]?.string)
            #expect(WebJSON.number(x) == text, "\(item["bits"]?.string ?? "")")
            if x.isFinite {
                guard case .number(let back)? = WebJSON.parse(text) else {
                    Issue.record("\(text) doesn't read back")
                    continue
                }
                #expect(back == x, "\(text) reads back as \(back)")
            }
        }
    }

    @Test func stringsAsJavaScriptWritesThem() throws {
        let cases = try Self.load().cases["string", default: []]
        #expect(cases.count == 47)
        for item in cases {
            let text = try #require(item["text"]?.string)
            let json = try #require(item["json"]?.string)
            #expect(sameText(WebJSON.quoted(text), json), "\(json)")
            guard case .string(let back)? = WebJSON.parse(json) else {
                Issue.record("\(json) doesn't read back")
                continue
            }
            #expect(sameText(back, text), "\(json) reads back otherwise")
        }
    }

    @Test func textsAsJSONParseReadsThem() throws {
        let cases = try Self.load().cases["parse", default: []]
        #expect(cases.count == 72)
        for item in cases {
            let text = try #require(item["text"]?.string)
            let got = WebJSON.parse(text).map(canonical)
            let wanted = item["canonical"]?.string
            #expect(sameText(got, wanted), "\(String(text.prefix(60))): \(got.map { String($0.prefix(60)) } ?? "nil")")
        }
    }

    @Test func theDevicesID() throws {
        let loaded = try Self.load()
        for item in loaded.cases["deviceId", default: []] {
            let candidate = try #require(item["candidate"]?.string)
            #expect(DeviceID.isValid(candidate) == item["valid"]?.bool, "\(candidate.debugDescription)")
        }
        for item in loaded.cases["deviceIdMade", default: []] {
            var bytes = Bytes(try #require(item["bytes"]?.array).compactMap { $0.int.map(UInt8.init) })
            #expect(DeviceID.make(using: &bytes) == item["id"]?.string)
        }
        #expect(loaded.cases["deviceId"]?.count == 20 && loaded.cases["deviceIdMade"]?.count == 4)
    }

    /// The first UTF-16 unit two texts differ at, with a little of each from there.
    func firstDifference(_ a: String?, _ b: String?) -> String {
        guard let a, let b else { return "(one is nil: \(a == nil), \(b == nil))" }
        let x = Array(a.utf16), y = Array(b.utf16)
        let at = (0..<min(x.count, y.count)).first { x[$0] != y[$0] } ?? min(x.count, y.count)
        let piece = { (units: [UInt16]) in String(decoding: units[at..<min(units.count, at + 80)], as: UTF16.self) }
        return "\(at): \(piece(x)) | \(piece(y))"
    }
}

/// A generator that gives these bytes, one a draw (UInt8.random over its whole range takes a draw's low byte).
struct Bytes: RandomNumberGenerator {
    var bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }
    mutating func next() -> UInt64 { UInt64(bytes.isEmpty ? 0 : bytes.removeFirst()) }
}
