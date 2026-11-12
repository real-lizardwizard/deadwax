import Foundation
import Testing
@testable import DeadwaxCore

/// The JavaScript number rules the turntable's ports lean on (the spec's 4.2), against Node's own answers
/// (Fixtures/deck/jsmath.json): Math.round, Math.fround, Math.min and Math.max, and ToInt32 with the voice's masks.
@Suite struct JSMathTests {
    let fixture: JSONValue

    init() throws {
        fixture = try DeckFixtures.json("jsmath.json")
    }

    @Test func roundIsMathRound() {
        let cases = fixture["round"]?.array ?? []
        #expect(cases.count > 40)
        for row in cases {
            let x = DeckFixtures.number(row.array?[0]), want = DeckFixtures.number(row.array?[1])
            #expect(DeckFixtures.same(JSMath.round(x), want), "Math.round(\(x)) is \(want), not \(JSMath.round(x))")
        }
    }

    @Test func froundIsAFloat32Store() {
        for row in fixture["fround"]?.array ?? [] {
            let x = DeckFixtures.number(row.array?[0]), want = DeckFixtures.number(row.array?[1])
            #expect(DeckFixtures.same(JSMath.fround(x), want), "Math.fround(\(x)) is \(want)")
            #expect(DeckFixtures.same(Double(Float(x)), want))
        }
    }

    @Test func minAndMaxAreJavaScripts() {
        let pairs = fixture["minmax"]?.array ?? []
        #expect(pairs.count == 72)
        for row in pairs {
            let a = DeckFixtures.number(row.array?[0]), b = DeckFixtures.number(row.array?[1])
            #expect(DeckFixtures.same(JSMath.min(a, b), DeckFixtures.number(row.array?[2])), "Math.min(\(a), \(b))")
            #expect(DeckFixtures.same(JSMath.max(a, b), DeckFixtures.number(row.array?[3])), "Math.max(\(a), \(b))")
        }
    }

    @Test func toInt32AndTheVoicesMasks() {
        for row in fixture["int32"]?.array ?? [] {
            let x = DeckFixtures.number(row.array?[0])
            let int32 = JSMath.toInt32(x)
            #expect(Double(int32) == row.array?[1].double, "\(x) | 0")
            #expect(Double(int32 & 1023) == row.array?[2].double, "\(x) & 1023")
            #expect(Double(int32 & 8191) == row.array?[3].double, "\(x) & 8191")
        }
    }
}
