import DeadwaxCore
import Testing

/// The planner's free space kept a while (notes/ios.md "A slow start, and the watchdog").
struct KeptFreeSpaceTests {
    let kept = KeptFreeSpace(bytes: 10_000, at: 100, used: 500)

    @Test func aReadingAnswersForHalfAMinute() {
        #expect(KeptFreeSpace.keptFor == 30)
        #expect(kept.estimate(now: 100, used: 500) == 10_000)
        #expect(kept.estimate(now: 129.9, used: 500) == 10_000)
        #expect(kept.estimate(now: 130, used: 500) == nil)
        #expect(kept.estimate(now: 1_000, used: 500) == nil)
    }

    @Test func whatLandedSinceIsTakenOffAndWhatWentIsGivenBack() {
        #expect(kept.estimate(now: 110, used: 2_500) == 8_000)
        #expect(kept.estimate(now: 110, used: 0) == 10_500)
        // never less than nothing
        #expect(kept.estimate(now: 110, used: 50_000) == 0)
    }

    @Test func aReadingFromAnotherClockIsReadAgain() {
        #expect(kept.estimate(now: 99.9, used: 500) == nil)
        #expect(kept.estimate(now: .nan, used: 500) == nil)
        #expect(KeptFreeSpace(bytes: 10, at: .infinity, used: 0).estimate(now: .infinity, used: 0) == nil)
        #expect(kept.estimate(now: 110, used: Int64.min) == nil)
        #expect(KeptFreeSpace(bytes: Int64.min, at: 100, used: 0).estimate(now: 110, used: 1) == nil)
    }
}
