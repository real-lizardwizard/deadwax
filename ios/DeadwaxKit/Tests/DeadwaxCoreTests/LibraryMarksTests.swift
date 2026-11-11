import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's New marks (lib/myLibrary.ts newMarks, isNew) and "cleared when you open it" (app/useMyLibrary.ts
/// seenAlbum): the fixtures replayed, and ui/test/mylibrary.sim.cjs's own checks.
@Suite struct LibraryMarksTests {
    static let ethan = Me(user: "ethan", admin: false, auth: "on", version: "x")

    static func entry(_ id: Int, _ album: String, navidrome: String? = nil) -> LibraryEntry {
        LibraryEntry(albumID: id, artist: "Portishead", album: album, releaseMBID: "rel-\(id)",
                     releaseGroupMBID: "grp-\(id)", navidromeID: navidrome, addedAt: "2026-10-15T09:00:00+00:00", how: "grabbed")
    }

    /// mylibrary.sim's LIBRARY: two new, Dummy starred (its Navidrome id known), Third not yet.
    static let library = MyLibrary(on: true, library: true, kept: true, count: 12, starred: 10, waiting: 2, incomplete: 1, login: "ok",
                                   new: [entry(1, "Dummy", navidrome: "nd-dummy"), entry(3, "Third")])

    // MARK: - the fixtures

    @Test func everyMarkAsTheTypeScriptHasIt() throws {
        let fixture = try LibraryFixtures.load("marks", as: MarksFixture.self)
        #expect(fixture.answers.count == 6 && fixture.albums.count == 16)
        var misses = LibraryFixtures.Misses()
        for (row, answer) in fixture.answers.enumerated() {
            let marks = NewMarks(answer)
            for (column, album) in fixture.albums.enumerated() {
                let got = marks.isNew(id: album.id, musicBrainzId: album.musicBrainzId)
                if got != fixture.isNew[row][column] { misses.add("answer \(row), album \(column) \(album.id) \(album.musicBrainzId ?? "-"): \(got)") }
                if got != marks.isNew(IndexAlbum(id: album.id, musicBrainzId: album.musicBrainzId)) { misses.add("isNew(IndexAlbum) \(row) \(column)") }
            }
        }
        #expect(misses.isEmpty, "\(misses)")
    }

    /// Each trace of the module: who is signed in, an ask (made only with a library of your own) and its answer, an
    /// album opened - then what deadwax was told and what is still new.
    @Test func everySeenTraceAsTheModuleRanIt() throws {
        let fixture = try LibraryFixtures.load("seen", as: SeenFixture.self)
        #expect(fixture.openedKept == MyLibraryState.openedKept)
        #expect(fixture.traces.count == 9)
        var misses = LibraryFixtures.Misses()
        for (name, steps) in fixture.traces.sorted(by: { $0.key < $1.key }) {
            var state = MyLibraryState()
            var me: Me? = nil
            var asked = false
            for (n, step) in steps.enumerated() {
                var told: [SeenBody] = []
                switch step.op {
                case "me": me = step.me
                case "ask": if PersonalLibrary.has(me) { asked = true }
                case "answer":
                    //? the newest ask answered, the rest dropped - as latestOnly lets only the newest draw
                    if asked { told = state.landed(try #require(step.answer), personal: PersonalLibrary.has(me)) }
                    asked = false
                case "open":
                    let album = try #require(step.album)
                    if let body = state.opened(.init(id: album.id, musicBrainzId: album.musicBrainzId), personal: PersonalLibrary.has(me)) {
                        told = [body]
                    }
                default: Issue.record("\(name): no op \(step.op)")
                }
                let news = state.answer.map { ($0.new ?? []).map(\.albumID) }
                if told != step.told || news != step.news {
                    misses.add("\(name) step \(n) \(step.op): told \(told), new \(news.map { "\($0)" } ?? "nil"); TS \(step.told), \(step.news.map { "\($0)" } ?? "nil")")
                }
            }
        }
        #expect(misses.isEmpty, "\(misses)")
    }

    // MARK: - mylibrary.sim

    @Test func theMarksByNavidromeIdOrByReleaseWhateverItsCase() {
        let marks = NewMarks(Self.library)
        #expect(marks.isNew(id: "nd-dummy", musicBrainzId: nil))
        #expect(marks.isNew(id: "nd-x", musicBrainzId: "REL-3"))
        #expect(!marks.isNew(id: "nd-x", musicBrainzId: "rel-4"))
        #expect(!NewMarks(nil).isNew(id: "nd-dummy", musicBrainzId: nil))
        #expect(NewMarks(nil).isEmpty && !marks.isEmpty)
        #expect(NewMarks(MyLibrary(on: false)).isEmpty)
    }

    @Test func clearedWhenYouOpenIt() {
        var state = MyLibraryState()
        #expect(state.landed(Self.library).isEmpty)
        #expect(state.opened(.init(id: "nd-elsewhere", musicBrainzId: "rel-77"), personal: true) == nil)
        #expect(state.opened(.init(id: "nd-dummy", musicBrainzId: "REL-1"), personal: true) == .release("rel-1"))
        #expect(state.answer?.new?.map(\.albumID) == [3])
        #expect(!state.marks.isNew(id: "nd-dummy", musicBrainzId: nil))
        //? no release to tell by: matched only by release or by the id it was starred on
        #expect(state.opened(.init(id: "nd-third-has-no-release-here", musicBrainzId: ""), personal: true) == nil)
        //? logins off: nothing at all
        #expect(state.opened(.init(id: "x", musicBrainzId: "rel-3"), personal: false) == nil)
        #expect(state.answer?.new?.map(\.albumID) == [3])
        //? an album reached by its address: only its Navidrome id - told by the store's ids
        _ = state.landed(Self.library)
        #expect(state.opened(.init(id: "nd-dummy"), personal: true) == .albums([1]))
        #expect(state.answer?.new?.map(\.albumID) == [3])
    }

    @Test func openedBeforeDeadwaxFirstSaid() {
        var state = MyLibraryState()
        #expect(state.opened(.init(id: "nd-dummy", musicBrainzId: "rel-1"), personal: true) == nil)
        #expect(state.answer == nil)
        #expect(state.landed(Self.library) == [.release("rel-1")])
        #expect(state.answer?.new?.map(\.albumID) == [3])
        //? looked at once: the next answer tells nothing more
        #expect(state.landed(Self.library).isEmpty)
        //? the last twenty kept, each once (nd-0 and nd-1 had been let go when they came round again)
        var many = MyLibraryState()
        for n in 0..<25 { _ = many.opened(.init(id: "nd-\(n % 23)"), personal: true) }
        #expect(many.openedBefore.map(\.id) == (5..<23).map { "nd-\($0)" } + ["nd-0", "nd-1"])
        var again = MyLibraryState()
        for id in ["a", "b", "a"] { _ = again.opened(.init(id: id), personal: true) }
        #expect(again.openedBefore.map(\.id) == ["a", "b"])
        #expect(again.opened(.init(id: "c"), personal: false) == nil && again.openedBefore.count == 2)
        many.clear()
        #expect(many.openedBefore.isEmpty && many.answer == nil)
    }

    @Test func aStarredCountThatMovesForgetsYourAlbums() {
        var watch = StarredCountWatch()
        let r1 = watch.saw(nil)
        #expect(!r1)
        let r2 = watch.saw(MyLibrary(on: true, library: true, kept: true, starred: 10))
        #expect(!r2)     //? the first count: nothing to compare
        let r3 = watch.saw(MyLibrary(on: true, library: true, kept: true, starred: 10))
        #expect(!r3)
        let r4 = watch.saw(MyLibrary(on: true, library: true, kept: true, starred: 11))
        #expect(r4)
        let r5 = watch.saw(MyLibrary(on: true, library: true, kept: false, starred: 3))
        #expect(!r5)    //? deadwax can't read its database: no count
        let r6 = watch.saw(MyLibrary(on: false))
        #expect(!r6)
        #expect(watch.seen == 11)
        let r7 = watch.saw(MyLibrary(on: true, library: true, kept: true, starred: 9))
        #expect(r7)
    }

    // MARK: - the wire

    @Test func whatIsSentAndWhatComesBack() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(SeenBody.release("rel-1")), as: UTF8.self) == #"{"release_mbid":"rel-1"}"#)
        #expect(String(decoding: try encoder.encode(SeenBody.albums([1, 3])), as: UTF8.self) == #"{"album_ids":[1,3]}"#)
        let answer = try JSONDecoder().decode(MyLibrary.self, from: Data("""
        {"on":true,"library":true,"kept":true,"count":12,"starred":10,"waiting":2,"incomplete":1,"login":"ok","login_problem":null,
         "new":[{"album_id":1,"artist":"Portishead","album":"Dummy","release_mbid":"rel-1","release_group_mbid":"grp-1",
                 "navidrome_id":"nd-dummy","added_at":"2026-10-15T09:00:00+00:00","how":"grabbed"},
                {"album_id":3,"artist":"Portishead","album":"Third","release_mbid":null,"release_group_mbid":null,
                 "navidrome_id":null,"added_at":null,"how":"seeded"}]}
        """.utf8))
        #expect(answer.new?.map(\.albumID) == [1, 3] && answer.new?[0].navidromeID == "nd-dummy" && answer.new?[1].releaseMBID == nil)
        #expect(answer.starred == 10 && answer.login == "ok")
        let off = try JSONDecoder().decode(MyLibrary.self, from: Data(#"{"on":false}"#.utf8))
        #expect(!off.on && off.new == nil && off.kept == nil)
    }
}
