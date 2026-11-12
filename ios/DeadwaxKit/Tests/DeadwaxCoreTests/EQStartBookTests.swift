import Foundation
import Testing
@testable import DeadwaxCore

/// Slice 2's review, items 1 and 2 (eq.md 1.6, 1.8): every output's bank made ahead, so a start only looks it up; and
/// one version counter that every change, every route change and every start raises, so the bank for the rate the unit
/// runs at always lands. The orders are run against EQHost's own rules here (a model of them, `Host`) and against the
/// real EQHost in DeadwaxAudioTests' EQStartTests.
@Suite struct EQStartBookTests {
    static let airpods = EQOutputs.output(EQRoutePort(port: .bluetoothA2DP, portType: "", name: "Pods", uid: "a"))
    static let car = EQOutputs.output(EQRoutePort(port: .carAudio, portType: "", name: "Golf", uid: "c"))

    static func settings(_ tone: String, on: Bool = true) -> EQSettings {
        var s = EQSettings()
        s.met(airpods, at: "")
        s.choose(.preset(tone), for: airpods)
        s.setOn(on, for: airpods)
        return s
    }

    /// EQHost.publish's two rules (eq.md 1.6 and slice 2's review), as DeadwaxAudio has them: a bank for the output now
    /// and from a version at least the last one published; and not a same-version bank for another rate when the last
    /// one is for the unit's rate.
    final class Host: @unchecked Sendable {
        var output: String?
        var lastVersion: Int?
        var newest: EQBank?
        var rate: Double?
        var taken: [EQBank] = []

        func publish(_ bank: EQBank) -> Bool {
            guard EQBank.publishable(key: bank.key, version: bank.version, keyNow: output, lastPublished: lastVersion) else {
                return false
            }
            if bank.version == lastVersion, let rate, bank.rate != rate, let newest, newest.rate == rate,
               newest.key == bank.key {
                return false
            }
            lastVersion = bank.version
            newest = bank
            taken.append(bank)
            return true
        }

        var taker: EQTaker {
            EQTaker(setOutput: { [unowned self] in self.output = $0 }, publish: { [unowned self] in self.publish($0) },
                    rate: { [unowned self] in self.rate })
        }
    }

    static func desk() -> EQStartDesk {
        EQStartDesk(muffleKey: "test", muffleBank: { (rate: Double, version: Int) -> EQBank in
            EQBank.make(rate: rate, key: "test", version: version, on: true,
                        correction: [EQFilter(id: 1, kind: .highShelf, fc: 2_000, gain: -24)], offsets: .zero,
                        bands: EQGraphic.flat, preamp: nil)
        }, clock: { 0 })
    }

    // MARK: the book (item 1)

    /// A sound's bank is the settings' own, bit for bit.
    @Test func aSoundMakesTheSettingsBank() {
        let s = Self.settings("loudness")
        let o = s.output(Self.airpods.key)!
        #expect(s.sound(o.key)!.bank(key: o.key, rate: 44_100, version: 7) == s.bank(o, rate: 44_100, version: 7))
        #expect(s.sound(Self.car.key) == nil)
    }

    /// Made ahead for the usual two rates, then for the rates the output has started at, most recent first.
    @Test func whatIsMadeAhead() {
        var book = EQStartBook()
        book.update(Self.settings("bassBoost"))
        #expect(book.wanted(Self.airpods.key).map(\.rate) == [48_000, 44_100])
        #expect(book.wanted(Self.car.key).isEmpty)
        _ = book.start(Self.airpods.key, rate: 96_000)
        #expect(book.rates(for: Self.airpods.key) == [96_000, 48_000, 44_100])
        _ = book.start(Self.airpods.key, rate: 88_200)
        _ = book.start(Self.airpods.key, rate: 96_000)
        #expect(book.rates(for: Self.airpods.key) == [96_000, 88_200, 48_000, 44_100])
        //? nothing is made for an output that is Off: its bank is the identity
        book.update(Self.settings("bassBoost", on: false))
        #expect(book.wanted(Self.airpods.key).isEmpty)
    }

    /// A start with its bank made ahead only looks it up and stamps it - the same bank a start making it would make.
    @Test func aStartFindsItsBankMade() {
        let s = Self.settings("bassBoost")
        let desk = Self.desk()
        _ = desk.take(s, muffle: false)
        #expect(desk.makeAhead([Self.airpods.key, Self.car.key]) == 2)
        #expect(desk.makeAhead([Self.airpods.key]) == 0)
        let plan = desk.plan(Self.airpods.key, rate: 44_100)
        guard case .ready(let bank) = plan else {
            Issue.record("made ahead, yet \(plan)")
            return
        }
        #expect(bank == s.bank(s.output(Self.airpods.key)!, rate: 44_100, version: 2))
        //? a rate not met before is made at the start - once: kept for the next
        guard case .make = desk.plan(Self.airpods.key, rate: 96_000) else {
            Issue.record("96 kHz was never made")
            return
        }
        let host = Host()
        desk.start(Self.airpods.key, rate: 96_000, host: host.taker)
        #expect(desk.lastStart?.ready == false)
        desk.start(Self.airpods.key, rate: 96_000, host: host.taker)
        #expect(desk.lastStart == EQStartTime(seconds: 0, ready: true, rate: 96_000))
        #expect(host.newest == s.bank(s.output(Self.airpods.key)!, rate: 96_000, version: 5))
    }

    /// A change drops the banks made from the sound it changed - never another output's - and a bank made from a sound
    /// that changed while it was being made is not kept.
    @Test func aBankNeverOutlivesItsSetting() {
        var book = EQStartBook()
        var s = Self.settings("bassBoost")
        s.choose(.preset("vocal"), for: Self.car)
        book.update(s)
        let pods = book.sounds[Self.airpods.key]!
        let car = book.sounds[Self.car.key]!
        #expect(book.keep(pods.bank(key: Self.airpods.key, rate: 48_000, version: 0), from: pods) == true)
        #expect(book.keep(car.bank(key: Self.car.key, rate: 48_000, version: 0), from: car) == true)
        s.setBand(3, to: 2, for: Self.airpods)
        book.update(s)
        #expect(book.ready[Self.airpods.key] == nil && book.ready[Self.car.key]?[48_000] != nil)
        #expect(book.keep(pods.bank(key: Self.airpods.key, rate: 48_000, version: 0), from: pods) == false)
        //? a route change (`seen` moving) is no change to the sound
        s.met(Self.car, at: "2026-11-12T10:00:00Z")
        book.update(s)
        #expect(book.ready[Self.car.key]?[48_000] != nil)
        //? an output forgotten
        s.forget(Self.car.key)
        book.update(s)
        #expect(book.ready[Self.car.key] == nil)
    }

    /// An output never met starts Off (3.12), and so does one whose EQ is off: the identity, nothing made.
    @Test func neverMetOrOffIsTheIdentity() {
        var book = EQStartBook()
        book.update(Self.settings("bassBoost", on: false))
        #expect(book.start(Self.car.key, rate: 48_000) == .ready(EQBank.identity(rate: 48_000, key: Self.car.key, version: 1)))
        #expect(book.start(Self.airpods.key, rate: 48_000)
                == .ready(EQBank.identity(rate: 48_000, key: Self.airpods.key, version: 2)))
        book.muffle = true
        #expect(book.start(Self.airpods.key, rate: 48_000) == .muffle(version: 3))
    }

    // MARK: versions (item 2)

    /// Every change and every start takes a version of its own, strictly rising.
    @Test func versionsOnlyRise() {
        let desk = Self.desk()
        let s = Self.settings("bassBoost")
        var seen: [Int] = []
        seen.append(desk.take(s, muffle: false).version)
        let first = desk.plan(Self.airpods.key, rate: 48_000)
        guard case .make(_, _, let v1) = first else {
            Issue.record("nothing was made ahead, yet \(first)")
            return
        }
        seen.append(v1)
        #expect(desk.bank(first, rate: 48_000).bank.version == v1)
        seen.append(desk.take(s, muffle: false).version)
        guard case .ready(let bank) = desk.plan(Self.airpods.key, rate: 48_000) else {
            Issue.record("the start's bank wasn't kept")
            return
        }
        seen.append(bank.version)
        #expect(seen == [1, 2, 3, 4])
    }

    /// The race slice 2's review found, in every order: a change on the main thread (take a version, read the rate,
    /// publish) and a start at a new rate on the engine's queue (the unit allocates at it, the start takes its own
    /// version, publishes). Whatever the order, what plays at the end is the new settings at the rate the unit runs at.
    @Test func theRightBankLandsInEveryOrder() {
        let before = Self.settings("bassBoost")
        let after = Self.settings("trebleBoost")
        let wanted = after.bank(after.output(Self.airpods.key)!, rate: 48_000, version: 0)
        var orders = 0
        for order in Self.interleavings(main: 3, start: 3) {
            let desk = Self.desk()
            let host = Host()
            // playing at 44.1 kHz with the old settings
            _ = desk.take(before, muffle: false)
            host.rate = 44_100
            desk.start(Self.airpods.key, rate: 44_100, host: host.taker)
            #expect(host.newest?.rate == 44_100)

            var ticket: EQTicket?
            var readRate: Double?
            var plan: EQStartPlan?
            var main = 0, start = 0
            for step in order {
                if step == .main {
                    switch main {
                    case 0: ticket = desk.take(after, muffle: false)
                    case 1: readRate = host.rate
                    default:
                        let (output, bank) = desk.bank(Self.airpods.key, rate: readRate!, ticket: ticket!)
                        host.output = output
                        _ = host.publish(bank)
                    }
                    main += 1
                } else {
                    switch start {
                    case 0: host.rate = 48_000
                    case 1: plan = desk.plan(Self.airpods.key, rate: 48_000)
                    default:
                        let (output, bank, _) = desk.bank(plan!, rate: 48_000)
                        host.output = output
                        _ = host.publish(bank)
                    }
                    start += 1
                }
            }
            var landed = host.newest
            landed?.version = 0
            #expect(landed == wanted, "\(order)")
            orders += 1
        }
        #expect(orders == 20)
    }

    /// A route change publishes a version of its own, so the new output's bank lands even when the last start's bank,
    /// at this rate, was the newest version until then.
    @Test func aRouteChangeLandsItsOutputsBank() {
        var s = Self.settings("bassBoost")
        s.choose(.preset("vocal"), for: Self.car)
        let desk = Self.desk()
        let host = Host()
        _ = desk.take(s, muffle: false)
        host.rate = 48_000
        desk.start(Self.airpods.key, rate: 48_000, host: host.taker)
        #expect(host.newest?.key == Self.airpods.key)
        // the car connects; the main thread hears it before any start
        s.met(Self.car, at: "now")
        let bank = desk.changed(s, route: Self.car.key, muffle: false, host: host.taker)
        #expect(bank != nil && host.newest == bank && host.output == Self.car.key)
        #expect(host.newest?.version == 3)
        // Muffle on and off goes through the same door
        #expect(desk.changed(s, route: Self.car.key, muffle: true, host: host.taker)?.key == "test")
        #expect(host.output == "test" && host.newest?.key == "test")
        #expect(desk.changed(s, route: Self.car.key, muffle: false, host: host.taker)?.key == Self.car.key)
        #expect(host.newest?.key == Self.car.key && host.newest?.version == 5)
        //? before the output first started there is no rate: nothing is published, the start puts it in
        let fresh = Host()
        #expect(Self.desk().changed(s, route: Self.car.key, muffle: false, host: fresh.taker) == nil)
        #expect(fresh.taken.isEmpty)
    }

    /// The mutation the rule guards against: a route change that didn't take a version of its own (the old "one
    /// version per settings change") - its bank, the same version as the last start's, at the same rate, would land
    /// only by luck of the host's rules; at another rate it is dropped. With its own version it always lands.
    @Test func withoutItsOwnVersionTheBankCanBeDropped() {
        let s = Self.settings("bassBoost")
        let host = Host()
        host.rate = 48_000
        host.output = Self.airpods.key
        let started = s.bank(s.output(Self.airpods.key)!, rate: 48_000, version: 4)
        #expect(host.publish(started))
        // a bank made from the same version at the rate read before the start: dropped
        #expect(!host.publish(s.bank(s.output(Self.airpods.key)!, rate: 44_100, version: 4)))
        // with a version of its own it goes in - and a start after it outranks it in turn
        #expect(host.publish(s.bank(s.output(Self.airpods.key)!, rate: 48_000, version: 5)))
    }

    enum Step: Equatable { case main, start }

    /// Every order of two step lists that keeps each list's own order.
    static func interleavings(main: Int, start: Int) -> [[Step]] {
        if main == 0 { return [Array(repeating: .start, count: start)] }
        if start == 0 { return [Array(repeating: .main, count: main)] }
        return interleavings(main: main - 1, start: start).map { [.main] + $0 }
            + interleavings(main: main, start: start - 1).map { [.start] + $0 }
    }
}
