import Foundation
import Testing
@testable import DeadwaxCore

/// The album lists' store (ui/src/app/albumIndex.ts) as a value: the TypeScript module's own traces replayed step by
/// step, whose.sim's checks, and the phone's additions (a 304, a list restored, everything cleared at sign-out).
@Suite struct LibraryStoreTests {
    /// The answer a trace's ask N brings: one album named for it, truncated when N % 3 == 0.
    static func answer(_ n: Int) -> AlbumIndexAnswer {
        AlbumIndexAnswer(albums: [IndexAlbum(id: "ask-\(n)")], truncated: n % 3 == 0)
    }

    static func ask(_ look: AlbumIndexState.Look) -> AlbumIndexState.Ask? {
        if case let .ask(ask) = look { return ask }
        return nil
    }

    static func keptID(_ state: AlbumIndexState, _ scope: AlbumScope) -> String? { state.kept(scope)?.answer.albums.first?.id }

    // MARK: - the module's traces

    @Test func everyTraceAsTheModuleRanIt() throws {
        let fixture = try LibraryFixtures.load("store", as: StoreFixture.self)
        #expect(fixture.traces.count == 12)
        var misses = LibraryFixtures.Misses()
        for (name, steps) in fixture.traces.sorted(by: { $0.key < $1.key }) {
            var state = AlbumIndexState()
            var out: [(ask: AlbumIndexState.Ask, n: Int)] = []
            var asks = 0
            var clock: Int64 = 1_000_000
            for (n, step) in steps.enumerated() {
                let scope = step.scope.flatMap(AlbumScope.init(rawValue:))
                switch step.op {
                case "list":
                    if let ask = Self.ask(state.list(try #require(scope))) {
                        out.append((ask, asks))
                        asks += 1
                    }
                case "forget": state.forget(try #require(scope))
                case "refreshIfOld": state.refreshIfOld(try #require(scope), now: clock)
                case "tick": clock += try #require(step.ms)
                case "land", "fail":
                    if out.isEmpty {
                        if step.none != true { misses.add("\(name) step \(n): nothing out to \(step.op)") }
                    } else {
                        if step.none == true { misses.add("\(name) step \(n): the module had nothing out") }
                        let one = step.newest == true ? out.removeLast() : out.removeFirst()
                        if step.op == "land" {
                            state.landed(one.ask, answer: Self.answer(one.n), etag: nil, now: clock)
                        } else {
                            state.failed(one.ask)
                        }
                    }
                default:
                    Issue.record("\(name): no op \(step.op)")
                }
                let scopes: [AlbumScope] = [.yours, .store]
                let generations = scopes.map { state.generation($0) }
                let kept = scopes.map { Self.keptID(state, $0) }
                let at = scopes.map { state.kept($0)?.at }
                let truncated = scopes.map { state.kept($0)?.answer.truncated }
                if asks != step.asks || generations != step.generation || kept != step.kept || at != step.at || truncated != step.truncated {
                    misses.add("\(name) step \(n) \(step.op): asks \(asks) \(generations) \(kept) \(at) \(truncated); TS \(step.asks) \(step.generation) \(step.kept) \(step.at) \(step.truncated)")
                }
            }
        }
        #expect(misses.isEmpty, "\(misses)")
    }

    // MARK: - whose.sim "your albums, the module itself"

    @Test func oneAskSharedOneListPerGeneration() throws {
        var state = AlbumIndexState()
        let first = try #require(Self.ask(state.list(.yours)))
        #expect(state.list(.yours) == .wait(first))                     //? two readers, one request
        #expect(state.asking(.yours) == first)
        let r1 = state.landed(first, answer: Self.answer(0), etag: "\"e1\"", now: 1_000)
        #expect(r1)
        guard case let .have(kept) = state.list(.yours) else { Issue.record("no list in hand"); return }
        #expect(kept.answer.albums.map(\.id) == ["ask-0"] && kept.etag == "\"e1\"" && kept.at == 1_000)
        #expect(state.asking(.yours) == nil)
        //? an Add or a Remove: the next look asks again, the list in hand drawn meanwhile
        state.forget(.yours)
        #expect(state.generation(.yours) == 1)
        let second = try #require(Self.ask(state.list(.yours)))
        #expect(second.generation == 1 && second.ifNoneMatch == "\"e1\"")   //? the ETag exactly as it came
        #expect(Self.keptID(state, .yours) == "ask-0")
        #expect(state.generation(.store) == 0 && state.kept(.store) == nil)  //? the scopes apart
    }

    @Test func freshForAMinuteAndNeverWhileAnAskIsOut() throws {
        var state = AlbumIndexState()
        let r2 = state.refreshIfOld(.store, now: 0)
        #expect(!r2)                       //? nothing kept: nothing to refresh
        let ask = try #require(Self.ask(state.list(.store)))
        let r3 = state.refreshIfOld(.store, now: 10_000_000)
        #expect(!r3)
        state.landed(ask, answer: Self.answer(1), etag: nil, now: 1_000)
        let r4 = state.refreshIfOld(.store, now: 1_000 + AlbumIndexState.freshMs)
        #expect(!r4)
        #expect(state.generation(.store) == 0)
        let r5 = state.refreshIfOld(.store, now: 1_000 + AlbumIndexState.freshMs + 1)
        #expect(r5)
        #expect(state.generation(.store) == 1)
        let again = try #require(Self.ask(state.list(.store)))
        let r6 = state.refreshIfOld(.store, now: 9_000_000)
        #expect(!r6)              //? one is out for this generation
        state.failed(again)
        let r7 = state.refreshIfOld(.store, now: 9_000_000)
        #expect(r7)
    }

    @Test func aFailedAskIsLetGoAndNothingKept() throws {
        var state = AlbumIndexState()
        let ask = try #require(Self.ask(state.list(.store)))
        state.failed(ask)
        #expect(state.kept(.store) == nil && state.asking(.store) == nil)
        let next = try #require(Self.ask(state.list(.store)))
        #expect(next.id != ask.id && next.generation == 0)
    }

    @Test func anOlderAskLandingLateKeepsNothingOnceAListIsKept() throws {
        var state = AlbumIndexState()
        let old = try #require(Self.ask(state.list(.yours)))
        state.forget(.yours)
        let new = try #require(Self.ask(state.list(.yours)))
        let r8 = state.landed(new, answer: Self.answer(1), etag: nil, now: 5)
        #expect(r8)
        let r9 = state.landed(old, answer: Self.answer(0), etag: nil, now: 6)
        #expect(!r9)
        #expect(Self.keptID(state, .yours) == "ask-1")
        //? nothing kept yet: the older one is drawn until the newer lands
        var fresh = AlbumIndexState()
        let a = try #require(Self.ask(fresh.list(.store)))
        fresh.forget(.store)
        let b = try #require(Self.ask(fresh.list(.store)))
        let r10 = fresh.landed(a, answer: Self.answer(0), etag: nil, now: 1)
        #expect(r10)
        #expect(fresh.list(.store) == .wait(b))
        let r11 = fresh.landed(b, answer: Self.answer(1), etag: nil, now: 2)
        #expect(r11)
        #expect(Self.keptID(fresh, .store) == "ask-1")
    }

    // MARK: - the phone's additions

    @Test func aThreeOhFourKeepsTheListAndRenewsItsTime() throws {
        var state = AlbumIndexState()
        let first = try #require(Self.ask(state.list(.yours)))
        #expect(first.ifNoneMatch == nil)                                 //? no ETag held: none sent
        state.landed(first, answer: Self.answer(0), etag: "W/\"abc\"", now: 1_000)
        let r12 = state.refreshIfOld(.yours, now: 100_000)
        #expect(r12)
        let second = try #require(Self.ask(state.list(.yours)))
        #expect(second.ifNoneMatch == "W/\"abc\"")
        let r13 = state.unchanged(second, now: 100_500)
        #expect(r13)
        guard case let .have(kept) = state.list(.yours) else { Issue.record("the 304 didn't keep the list"); return }
        #expect(kept.at == 100_500 && kept.etag == "W/\"abc\"" && kept.answer.albums.map(\.id) == ["ask-0"])
        let r14 = state.refreshIfOld(.yours, now: 100_500 + AlbumIndexState.freshMs)
        #expect(!r14)
    }

    @Test func aThreeOhFourThatCantStandIsLetGo() throws {
        var state = AlbumIndexState()
        let none = try #require(Self.ask(state.list(.store)))
        let r15 = state.unchanged(none, now: 1)
        #expect(!r15)                           //? nothing held to compare: asked again
        #expect(state.asking(.store) == nil)
        let first = try #require(Self.ask(state.list(.store)))
        state.landed(first, answer: Self.answer(0), etag: "\"a\"", now: 2)
        state.forget(.store)
        let stale = try #require(Self.ask(state.list(.store)))
        state.forget(.store)
        let newer = try #require(Self.ask(state.list(.store)))
        state.landed(newer, answer: Self.answer(1), etag: "\"b\"", now: 3)
        let r16 = state.unchanged(stale, now: 4)
        #expect(!r16)                          //? a newer list landed since it was asked
        #expect(Self.keptID(state, .store) == "ask-1" && state.kept(.store)?.at == 3)
    }

    /// A 304 to an ask sent with no ETag can't be about the list kept - here an older generation's, landed while
    /// this one was out (nothing kept then): it is let go and asked again, never taken as this generation's list.
    @Test func aThreeOhFourToAnAskWithNoETagNeverStands() throws {
        var state = AlbumIndexState()
        let older = try #require(Self.ask(state.list(.store)))
        state.forget(.store)
        let current = try #require(Self.ask(state.list(.store)))
        #expect(older.ifNoneMatch == nil && current.ifNoneMatch == nil)
        let keptOlder = state.landed(older, answer: Self.answer(0), etag: "\"x\"", now: 10)
        #expect(keptOlder)                                                //? nothing kept yet: drawn meanwhile
        let stands = state.unchanged(current, now: 20)
        #expect(!stands)
        #expect(state.asking(.store) == nil && state.kept(.store)?.at == 10)
        let again = try #require(Self.ask(state.list(.store)))
        #expect(again.generation == 1 && again.ifNoneMatch == "\"x\"")
    }

    @Test func aListRestoredFromAnEarlierLaunch() throws {
        var state = AlbumIndexState()
        state.restore(.yours, answer: Self.answer(9), etag: "\"disk\"", at: 50)
        #expect(Self.keptID(state, .yours) == "ask-9")
        let ask = try #require(Self.ask(state.list(.yours)))              //? drawn, but this session still asks
        #expect(ask.ifNoneMatch == "\"disk\"")
        let r17 = state.unchanged(ask, now: 60)
        #expect(r17)
        state.restore(.yours, answer: Self.answer(10), etag: "\"other\"", at: 70)
        #expect(Self.keptID(state, .yours) == "ask-9")                    //? only when nothing is kept
    }

    @Test func signingOutForgetsEverythingAndNothingAskedBeforeLandsAfter() throws {
        var state = AlbumIndexState()
        let mine = try #require(Self.ask(state.list(.yours)))
        state.landed(mine, answer: Self.answer(0), etag: "\"e\"", now: 1)
        state.forget(.yours)
        let late = try #require(Self.ask(state.list(.yours)))
        let lateFailure = try #require(Self.ask(state.list(.store)))
        state.clear()
        #expect(state.kept(.yours) == nil && state.generation(.yours) == 0 && state.asking(.yours) == nil)
        let r18 = state.landed(late, answer: Self.answer(1), etag: nil, now: 2)
        #expect(!r18)
        #expect(state.kept(.yours) == nil)
        let theirs = try #require(Self.ask(state.list(.yours)))
        #expect(theirs.ifNoneMatch == nil)
        state.failed(lateFailure)                                         //? the earlier session's failure lets nothing go
        let r19 = state.unchanged(late, now: 3)
        #expect(!r19)
        #expect(state.list(.yours) == .wait(theirs))
    }

    // MARK: - which list the Albums screen shows

    @Test func yoursOnlyWithLoginsOnAndALibraryOfYourOwn() {
        #expect(AlbumScope.albums(for: Me(user: "ethan", admin: false, auth: "on")) == .yours)
        #expect(AlbumScope.albums(for: Me(user: "james", admin: true, auth: "on")) == .yours)
        #expect(AlbumScope.albums(for: Me(user: "deadwax", admin: true, auth: "on")) == .store)
        #expect(AlbumScope.albums(for: Me(user: "local", admin: true, auth: "off")) == .store)
        #expect(AlbumScope.albums(for: nil) == .store)
        #expect(AlbumScope.yours.addedBy == .you && AlbumScope.store.addedBy == .collection)
        #expect(AlbumScope.allCases.map(\.rawValue) == ["yours", "store"])
    }
}
