import Foundation
import Testing
@testable import DeadwaxCore

// Resume's parts the fixtures don't hold: the spec's own examples, the wire bodies as deadwax reads them, the
// device's id kept, and where the phone knowingly differs from the web (each said in notes/ios.md).

@Suite struct ResumeUnitTests {
    @Test func theSpecsWindows() {
        #expect(windowOf(5000, 0) == (0, 2000))
        #expect(windowOf(5000, 100) == (50, 2050))
        #expect(windowOf(10, 3) == (0, 10))
        #expect(windowOf(0, 0) == (0, 0))
    }

    @Test func aPlainQueueSavesNoSnapshot() {
        let saving = toSave(UpNextQueue(tracks: rAlbum(2), index: 1), position: 4)
        #expect(saving == Saving(ids: ["1", "2"], index: 1, position: 4, snapshot: nil, start: 0))
        let empty = toSave(.empty, position: 0)
        #expect(empty.ids.isEmpty && empty.snapshot == nil)
    }

    @Test func theSnapshotsShapeForASmallQueue() throws {
        let queue = withNext(startUpNext(rAlbum(3, level: .album), start: 1, id: "q-1"), [rTrack("x", level: .track)])
        let snapshot = try #require(toSave(queue, position: 61.5).snapshot)
        #expect(snapshot == #"{"v":1,"id":"q-1","levels":"aata","marks":[[0,"s",0,0],[1,"s",1,0],[3,"a",-1,-1],[2,"s",2,0]],"source":["1","2","3"],"sourceLevels":"aaa","extra":{},"shuffle":false,"nextKey":4,"startedAt":1,"left":[]}"#)
        let back = fromSnapshot(snapshot, tracks: queue.tracks.map { var t = $0; t.level = nil; return t }, index: 1, setting: .auto)
        #expect(back == queue)
        //? By song: every entry at its song's level; Off: none
        #expect(fromSnapshot(snapshot, tracks: queue.tracks, index: 1, setting: .song)?.tracks.allSatisfy { $0.level == .track } == true)
        #expect(fromSnapshot(snapshot, tracks: queue.tracks, index: 1, setting: .off)?.tracks.allSatisfy { $0.level == nil } == true)
    }

    /// (app 0.8, the web's 2.1.15) The queue's `id` is written second and read back - the same queue on every device;
    /// a snapshot saved without one (the phone before 0.8, the web before 2.1.15) reads as the same queue under a new
    /// id - or the queue held's, when it is that queue - and is saved again with it.
    @Test func theQueuesIdIsSavedAndReadBack() throws {
        let queue = withNext(startUpNext(rAlbum(3, level: .album), start: 1, id: "mhyx7k2c-a1b2c3d4"),
                             [rTrack("x", level: .track)])
        let ours = try #require(toSave(queue, position: 61.5).snapshot)
        #expect(ours.hasPrefix(#"{"v":1,"id":"mhyx7k2c-a1b2c3d4","levels":"#))
        let before = ours.replacingOccurrences(of: #""id":"mhyx7k2c-a1b2c3d4","#, with: "")
        #expect(before != ours)
        let tracks = queue.tracks.map { var t = $0; t.level = nil; return t }
        for setting in [Normalization.auto, .song, .album, .off] {
            var back = try #require(fromSnapshot(before, tracks: tracks, index: 1, setting: setting, newId: { "new-1" }))
            #expect(back.upNext?.id == "new-1")
            back.upNext?.id = queue.upNext!.id
            #expect(back == fromSnapshot(ours, tracks: tracks, index: 1, setting: setting))
        }
        #expect(fromSnapshot(ours, tracks: tracks, index: 1, setting: .auto) == queue)
        //? while the phone holds that queue, the id-less snapshot keeps its id; holding another, a new one
        #expect(fromSnapshot(before, tracks: tracks, index: 1, setting: .auto, holding: queue) == queue)
        let other = startUpNext(rAlbum(3, "o"), start: 0, id: "other")
        #expect(fromSnapshot(before, tracks: tracks, index: 1, setting: .auto, holding: other, newId: { "new-2" })?.upNext?.id == "new-2")
        //? read back, it saves with the id it has now
        let resaved = try #require(fromSnapshot(before, tracks: tracks, index: 1, setting: .auto, newId: { "new-3" }))
        #expect(toSave(resaved, position: 61.5).snapshot?.hasPrefix(#"{"v":1,"id":"new-3","levels":"#) == true)
    }

    /// (2.1.15) A queue's id as the web's queueId() makes one, and what one is.
    @Test func aQueuesId() {
        #expect(UpNext.queueId(nowMs: 1_762_000_000_000, bytes: [0, 1, 35, 36, 37, 255, 71, 10]) == "mhg9b18g-01z013za")
        #expect(UpNext.queueId(nowMs: -5, bytes: []) == "0-")
        let made = UpNext.newQueueId()
        #expect(UpNext.isQueueId(made) && made.count == 17)
        #expect(UpNext.newQueueId() != made)
        for good in ["a", String(repeating: "Z", count: 64), "AZaz09_-", "mhyx7k2c-a1b2c3d4"] { #expect(UpNext.isQueueId(good), "\(good)") }
        for bad in ["", String(repeating: "a", count: 65), "q 1", "q.1", "q\u{1F600}", "caf\u{E9}", "q\n"] { #expect(!UpNext.isQueueId(bad), "\(bad)") }
        //? a new queue gets one, every edit carries it
        let queue = startUpNext(rAlbum(4), start: 1)
        let id = queue.upNext?.id ?? ""
        #expect(UpNext.isQueueId(id))
        let edited = withShuffle(toppedUp(withRepeat(withNext(queue, [rTrack("n")]), .all), .all), true)
        #expect(edited.upNext?.id == id)
        #expect(startUpNext(rAlbum(4), start: 1, id: "given").upNext?.id == "given")
    }

    @Test func positionsAsSent() {
        #expect(Resume.sent(-3) == 0)
        #expect(Resume.sent(12.5) == 12.5)
        #expect(Resume.sent(100_000) == 86_400)
        #expect(Resume.sent(.nan) == 0 && Resume.sent(.infinity) == 0)
    }

    @Test func failuresFromTheClient() {
        #expect(ResumeFailure(status: 409) == .status(409))
        #expect(ResumeFailure(status: nil) == .unanswered)
    }

    @Test func theBodiesAsDeadwaxReadsThem() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let full = QueueSaveBody(ids: ["1", "2"], index: 1, position: 3.5, device: "dev-1234", label: "iPhone", snapshot: nil)
        let text = String(decoding: try encoder.encode(full), as: UTF8.self)
        #expect(text == #"{"device":"dev-1234","ids":["1","2"],"index":1,"label":"iPhone","position":3.5}"#,
                "no snapshot: the key left out, as the web's JSON.stringify leaves an undefined one")
        let withSnapshot = QueueSaveBody(ids: ["1"], index: 0, position: 0, device: "dev-1234", label: "iPhone", snapshot: #"{"v":1}"#)
        #expect(String(decoding: try encoder.encode(withSnapshot), as: UTF8.self).contains(#""snapshot":"{\"v\":1}""#))
        let at = QueueAtBody(ids_rev: 4, index: 2, position: 61, device: "dev-1234", label: "iPhone")
        #expect(String(decoding: try encoder.encode(at), as: UTF8.self)
                    == #"{"device":"dev-1234","ids_rev":4,"index":2,"label":"iPhone","position":61}"#)
        let saved = try JSONDecoder().decode(SavedQueue.self, from: Data(#"{"rev":null,"ids_rev":null}"#.utf8))
        #expect(saved.rev == nil && saved.ids_rev == nil)
        let answer = try JSONDecoder().decode(QueueAnswer.self, from: Data(
            #"{"tracks":[{"id":"a","title":"A"}],"index":null,"position":0,"changed_by":"","shared":true,"kept":null}"#.utf8))
        #expect(answer.index == nil && answer.kept == nil && answer.shared && answer.tracks.map(\.id) == ["a"])
    }

    @Test func theDevicesIDKept() {
        var bytes = Bytes(Array(repeating: 0, count: 16))
        #expect(DeviceID.read("kept_device-0001", using: &bytes) == ("kept_device-0001", false))
        var more = Bytes(Array(repeating: 1, count: 16))
        let remade = DeviceID.read("not an id!", using: &more)
        #expect(remade.id == "BBBBBBBBBBBBBBBB" && remade.isNew)
        var none = Bytes(Array(repeating: 63, count: 16))
        #expect(DeviceID.read(nil, using: &none) == ("----------------", true))
        let made = DeviceID.read(nil)
        #expect(made.isNew && made.id.count == DeviceID.length && DeviceID.isValid(made.id))
    }

    @Test func theNormalizationSettingKept() {
        #expect(Normalization.default == .auto)
        #expect(Normalization.read(nil) == .auto && Normalization.read("album") == .album && Normalization.read("loud") == .auto)
        #expect(Normalization.allCases.map(\.rawValue) == ["auto", "song", "album", "off"])
    }

    /// Where the phone's reader knowingly stops before JavaScript's: nesting past 1,000 (the web reads any depth its
    /// stack allows). No snapshot nests past 5.
    @Test func nestingPastAThousandIsRefused() {
        #expect(WebJSON.parse(String(repeating: "[", count: 1000) + String(repeating: "]", count: 1000)) != nil)
        #expect(WebJSON.parse(String(repeating: "[", count: 1001) + String(repeating: "]", count: 1001)) == nil)
    }

    @Test func theNoticesWords() {
        #expect(pickedUpWords(.device("Mac"), shared: false) == "Picked up from your Mac")
        #expect(pickedUpWords(.device("iPhone"), shared: true) == "Picked up from an iPhone")
        #expect(pickedUpWords(.app("Symfonium"), shared: true) == "Picked up from Symfonium")
        #expect(pickedUpWords(nil, shared: false) == nil)
    }
}
