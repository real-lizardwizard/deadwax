import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 1.5-1.7 and 5.1: the render run over the fixtures' own coefficients (so Swift's and Python's libm can't
/// differ underneath) equals the script's Direct Form I bit for bit, Float32 output included - which also proves
/// nothing was fused into one rounding - at blocks of 1, 7, 512 and 4096 frames; the identity leaves a buffer's bytes
/// untouched; a crossfade is the raised cosine between the two banks, warm-started by id; a bank mid-crossfade waits
/// and the newest wins; a bank for another rate is ignored; the counters count.
@Suite struct EQRenderTests {
    // ------------------------------------------------------------ helpers

    /// One block of `signal` from `start`, in place, through the render's own entry.
    @discardableResult
    static func block(_ state: UnsafeMutablePointer<EQRenderState>, _ signal: inout [[Float]], from start: Int,
                      frames: Int, offering bank: [Double]? = nil) -> Bool {
        let count = signal.count
        let pointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: count)
        for c in 0..<count {
            pointers[c] = UnsafeMutablePointer<Float>.allocate(capacity: max(frames, 1))
            for n in 0..<frames { pointers[c][n] = signal[c][start + n] }
        }
        let ok: Bool
        if let bank {
            ok = bank.withUnsafeBufferPointer { EQRender.process(state, buffers: pointers, frames: frames, offered: $0.baseAddress) }
        } else {
            ok = EQRender.process(state, buffers: pointers, frames: frames, offered: nil)
        }
        for c in 0..<count {
            for n in 0..<frames { signal[c][start + n] = pointers[c][n] }
            pointers[c].deallocate()
        }
        pointers.deallocate()
        return ok
    }

    /// The whole signal in blocks of `size`, the bank offered at the first.
    static func render(_ bank: EQBank, _ input: [[Float]], blocks size: Int, maximumFrames: Int = 4096) -> ([[Float]], EQRenderCounters) {
        let state = EQRender.make(rate: bank.rate, channels: input.count, maximumFrames: maximumFrames)
        defer { EQRender.free(state) }
        var signal = input
        var start = 0
        while start < input[0].count {
            let n = min(size, input[0].count - start)
            block(state, &signal, from: start, frames: n, offering: start == 0 ? bank.packed : nil)
            start += n
        }
        return (signal, state.pointee.counters)
    }

    static func noise(_ channels: Int, _ frames: Int, seed: UInt64) -> [[Float]] {
        var x = seed
        return (0..<channels).map { (_: Int) -> [Float] in
            (0..<frames).map { (_: Int) -> Float in
                x = x &* 6364136223846793005 &+ 1442695040888963407
                return Float(Double(x >> 11) / Double(1 << 53) * 1.6 - 0.8)
            }
        }
    }

    static func bits(_ signal: [[Float]]) -> [[UInt32]] { signal.map { $0.map(\.bitPattern) } }

    static func section(_ id: EQSectionID, _ kind: EQKind = .peak, fc: Double, gain: Double, q: Double, rate: Double = 48000) -> EQSection {
        let d = EQFilter(kind: kind, fc: fc, gain: gain, width: .q(q)).design(rate: rate)
        return EQSection(id: id, kind: kind, f0: d.f0!, coefficients: d.coefficients!)
    }

    static func bank(_ sections: [EQSection], level: Double, rate: Double = 48000) -> EQBank {
        EQBank(rate: rate, key: "test", version: 1, left: sections, right: sections, shared: sections, preamp: 0,
               levels: [level, level, level])
    }

    /// Direct Form I written out again: a section's state is x1, x2, y1, y2.
    struct Reference {
        var sections: [EQSection]
        var level: Double
        var states: [[Double]]

        init(_ sections: [EQSection], level: Double, states: [[Double]]? = nil) {
            self.sections = sections
            self.level = level
            self.states = states ?? sections.map { _ in [0, 0, 0, 0] }
        }

        mutating func run(_ x: Double) -> Double {
            var v = x
            for i in sections.indices {
                let c = sections[i].coefficients
                var s = states[i]
                let y = c.b0 * v + c.b1 * s[0] + c.b2 * s[1] - c.a1 * s[2] - c.a2 * s[3]
                s = [v, s[0], y, s[2]]
                states[i] = s
                v = y
            }
            return v * level
        }
    }

    // ------------------------------------------------------------ the script's Direct Form I, bit for bit

    @Test func theRenderIsTheScriptsDirectFormIBitForBit() throws {
        let file = try EQFixtures.render()
        let rate = EQFixtures.d(file.rate)
        let lists = file.lists.map { $0.map(\.section) }
        let bank = EQBank(rate: rate, key: "fixture", version: 1, left: lists[0], right: lists[1], shared: lists[2],
                          preamp: 0, levels: file.levels.map(EQFixtures.d))
        #expect(!bank.isIdentity && file.scenarios.map(\.channels) == [2, 8, 1])
        for scenario in file.scenarios {
            let input = scenario.input_f4.map(EQFixtures.floats)
            let expected = scenario.output_f4.map(EQFixtures.floats)
            #expect(input.count == scenario.channels && input[0].count == scenario.frames)
            for size in [1, 7, 512, 4096] {
                let (output, counters) = Self.render(bank, input, blocks: size)
                #expect(Self.bits(output) == Self.bits(expected), "\(scenario.name), blocks of \(size)")
                #expect(counters.overs == scenario.overs && counters.largest == EQFixtures.d(scenario.largest),
                        "\(scenario.name), blocks of \(size): \(counters)")
                #expect(counters.crossfades == 0 && counters.refused == 0)
            }
            print("\(scenario.name): \(scenario.channels) channels x \(scenario.frames) frames, bit for bit at blocks of 1, 7, 512 and 4096; \(scenario.overs) over full scale, the largest \(scenario.largest)")
        }
    }

    /// filters.json's impulses - the script's own Direct Form I in Python floats - through the render's section loop.
    @Test func eachImpulseIsTheScriptsBitForBit() throws {
        var checked = 0, samples = 0
        for c in try EQFixtures.filters().cases {
            guard let impulse = c.impulse_f8.map(EQFixtures.doubles), let co = c.coefficientsValue else { continue }
            let q = [co.b0, co.b1, co.b2, co.a1, co.a2]
            var state = [0.0, 0, 0, 0]
            var x = [Double](repeating: 0, count: impulse.count)
            x[0] = 1
            q.withUnsafeBufferPointer { qp in
                state.withUnsafeMutableBufferPointer { sp in
                    x.withUnsafeMutableBufferPointer { xp in EQRender.df1(qp.baseAddress!, sp.baseAddress!, xp.baseAddress!, impulse.count) }
                }
            }
            #expect(x.map(\.bitPattern) == impulse.map(\.bitPattern), "\(c.name)")
            checked += 1
            samples += impulse.count
        }
        #expect(checked == 148)
        print("EQRenderTests: \(checked) impulses, \(samples) samples, bit for bit")
    }

    // ------------------------------------------------------------ the identity (1.7)

    @Test func theIdentityLeavesABuffersBytesUntouched() {
        //? NaNs with payloads, -0, subnormals, infinities and noise: nothing is converted, so nothing changes
        var odd: [Float] = [.nan, -.nan, Float(bitPattern: 0x7FC0_1234), Float(bitPattern: 0xFF80_0001), -0.0, 0,
                            .leastNonzeroMagnitude, -.leastNormalMagnitude, .infinity, -.infinity, 1, -1]
        odd += Self.noise(1, 500, seed: 7)[0]
        let input = [odd, odd.reversed()]
        let flat = EQBank.make(rate: 48000, key: "k", version: 1, on: true, correction: [], offsets: .zero,
                               bands: EQGraphic.flat, preamp: nil)
        let off = EQBank.make(rate: 48000, key: "k", version: 1, on: false,
                              correction: [EQFilter(id: 1, kind: .peak, fc: 1000, gain: 6, width: .q(1))],
                              offsets: .zero, bands: EQGraphic.presets[1].gains, preamp: nil)
        let zeroGain = EQBank.make(rate: 48000, key: "k", version: 1, on: true,
                                   correction: [EQFilter(id: 1, kind: .peak, fc: 1000, gain: 0, width: .q(1)),
                                                EQFilter(id: 2, kind: .highShelf, fc: 30000, gain: 3, width: .q(1))],
                                   offsets: .zero, bands: EQGraphic.flat, preamp: nil)
        let handZero = EQBank.make(rate: 48000, key: "k", version: 1, on: true, correction: [], offsets: .zero,
                                   bands: EQGraphic.flat, preamp: -0.0)
        for bank in [flat, off, zeroGain, handZero] {
            #expect(bank.isIdentity)
            for size in [1, 7, 512] {
                let (output, _) = Self.render(bank, input, blocks: size)
                #expect(Self.bits(output) == Self.bits(input))
            }
        }
        //? and nothing at all offered: the identity is live from the start
        let state = EQRender.make(rate: 48000, channels: 2, maximumFrames: 4096)
        defer { EQRender.free(state) }
        var signal = input
        Self.block(state, &signal, from: 0, frames: odd.count)
        #expect(Self.bits(signal) == Self.bits(input))
    }

    /// A 0.0001 dB band is a curve: not the identity, and it changes the samples.
    @Test func aTenThousandthOfADecibelIsNotTheIdentity() {
        var bands = EQGraphic.flat
        bands[5] = 0.0001
        let bank = EQBank.make(rate: 48000, key: "k", version: 1, on: true, correction: [], offsets: .zero, bands: bands,
                               preamp: 0)
        #expect(!bank.isIdentity && bank.left.count == 1)
        let input = Self.noise(2, 2000, seed: 3)
        let (output, _) = Self.render(bank, input, blocks: 512)
        #expect(Self.bits(output) != Self.bits(input))
        //? a level a hair under 1 is not the identity either
        let quieter = EQBank.make(rate: 48000, key: "k", version: 1, on: true, correction: [], offsets: .zero,
                                  bands: EQGraphic.flat, preamp: -0.0001)
        #expect(!quieter.isIdentity)
    }

    // ------------------------------------------------------------ crossfades (1.6)

    @Test func theCrossfadesWeightsAreARaisedCosine() {
        for (rate, frames) in [(48000.0, 960), (44100.0, 882), (192000.0, 3840), (384000.0, 7680)] {
            let state = EQRender.make(rate: rate, channels: 2, maximumFrames: 512)
            defer { EQRender.free(state) }
            #expect(state.pointee.fadeFrames == frames)
            let w = (0..<frames).map { state.pointee.weights[$0] }
            for n in 0..<frames { #expect(w[n] == 0.5 - 0.5 * cos(Double.pi * Double(n + 1) / Double(frames))) }
            #expect(w.last == 1)
            #expect(zip(w, w.dropFirst()).allSatisfy { $0 < $1 })
            //? smooth at both ends: the first step is far smaller than a straight line's
            #expect(w[0] < 1e-5 && 1 - w[frames - 2] < 1e-5)
        }
    }

    /// Bank A plays a block, then B is offered: the output is `(1 - w)·A + w·B` for 20 ms and B's after, B's sections
    /// taking A's states by id (and kind, and list) and any other starting from its own input's history - all
    /// computed again here, in blocks of `size`.
    static func crossfade(from a: EQBank, to b: EQBank, blocks size: Int, seed: UInt64) -> (got: [[Float]], expected: [[Float]], counters: EQRenderCounters) {
        let frames = 4000, first = 512
        let input = noise(2, frames, seed: seed)
        let state = EQRender.make(rate: 48000, channels: 2, maximumFrames: 4096)
        defer { EQRender.free(state) }
        var signal = input
        block(state, &signal, from: 0, frames: first, offering: a.packed)
        var start = first
        while start < frames {
            let n = min(size, frames - start)
            block(state, &signal, from: start, frames: n, offering: start == first ? b.packed : nil)
            start += n
        }

        let fade = 960
        let weights = (0..<fade).map { 0.5 - 0.5 * cos(Double.pi * Double($0 + 1) / Double(fade)) }
        var expected: [[Float]] = []
        for c in 0..<2 {
            let x = input[c].map(Double.init)
            var old = Reference(c == 0 ? a.left : a.right, level: a.levels[c])
            var out: [Float] = (0..<first).map { Float(old.run(x[$0])) }
            let listB = c == 0 ? b.left : b.right
            var states: [[Double]] = []
            for (i, s) in listB.enumerated() {
                if let j = old.sections.firstIndex(where: { $0.id == s.id && $0.kind == s.kind }) {
                    states.append(old.states[j])
                } else {
                    let h = i == 0 ? [x[first - 1], x[first - 2]] : [states[i - 1][2], states[i - 1][3]]
                    states.append([h[0], h[1], h[0], h[1]])
                }
            }
            var new = Reference(listB, level: b.levels[c], states: states)
            for n in first..<frames {
                let o = old.run(x[n]), y = new.run(x[n])
                let k = n - first
                out.append(Float(k < fade ? (1 - weights[k]) * o + weights[k] * y : y))
            }
            expected.append(out)
        }
        return (signal, expected, state.pointee.counters)
    }

    @Test func aCrossfadeWarmStartsBySectionID() {
        let a = Self.bank([Self.section(.filter(1), fc: 100, gain: 6, q: 1), Self.section(.filter(2), fc: 1000, gain: -4, q: 2),
                           Self.section(.band(3), fc: 250, gain: 3, q: 1.41)], level: 0.8)
        //? a filter added below the others, one changed, a band taken away and another put in
        let b = Self.bank([Self.section(.filter(3), fc: 50, gain: 3, q: 0.7), Self.section(.filter(1), fc: 100, gain: 6, q: 1),
                           Self.section(.filter(2), fc: 1000, gain: -2, q: 2), Self.section(.band(5), fc: 1000, gain: 2, q: 1.41)],
                          level: 0.7)
        for size in [7, 512, 4096] {
            let run = Self.crossfade(from: a, to: b, blocks: size, seed: 11)
            #expect(Self.bits(run.got) == Self.bits(run.expected), "blocks of \(size)")
            #expect(run.counters.crossfades == 1 && run.counters.waited == 0)
        }
        //? a band and a filter of the same number are two ids: band 1's state never goes to filter 1
        let band = Self.bank([Self.section(.band(1), fc: 62.5, gain: 6, q: 1.41)], level: 1)
        let filter = Self.bank([Self.section(.filter(1), fc: 62.5, gain: 6, q: 1.41)], level: 0.9)
        let run = Self.crossfade(from: band, to: filter, blocks: 512, seed: 12)
        #expect(Self.bits(run.got) == Self.bits(run.expected))
        #expect(EQSectionID.band(1).code != EQSectionID.filter(1).code)
        #expect(Set((0..<10).map { EQSectionID.band($0).code }).isDisjoint(with: (0...1000).map { EQSectionID.filter($0).code }))
    }

    /// Off and On are crossfades to and from the identity, and the identity passes through again once one ends.
    @Test func offAndOnAreCrossfades() {
        let on = Self.bank([Self.section(.filter(1), fc: 1000, gain: 6, q: 1)], level: 0.5)
        let off = EQBank.identity(rate: 48000, key: "test", version: 2)
        let toOn = Self.crossfade(from: off, to: on, blocks: 512, seed: 21)
        #expect(Self.bits(toOn.got) == Self.bits(toOn.expected) && toOn.counters.crossfades == 1)
        let toOff = Self.crossfade(from: on, to: off, blocks: 512, seed: 22)
        #expect(Self.bits(toOff.got) == Self.bits(toOff.expected) && toOff.counters.crossfades == 1)
        //? after it: the input's own samples, untouched
        let input = Self.noise(2, 4000, seed: 22)
        #expect(Self.bits(toOff.got).map { Array($0[(512 + 960)...]) } == Self.bits(input).map { Array($0[(512 + 960)...]) })
    }

    @Test func aBankMidCrossfadeWaitsAndTheNewestWins() {
        let input = Self.noise(2, 256 * 20, seed: 5)
        let state = EQRender.make(rate: 48000, channels: 2, maximumFrames: 4096)
        defer { EQRender.free(state) }
        var signal = input
        let levels = [0.5, 0.25, 0.125, 2.0]
        let banks = levels.map { Self.bank([], level: $0).packed }
        for i in 0..<20 {
            Self.block(state, &signal, from: i * 256, frames: 256, offering: i < 4 ? banks[i] : nil)
        }
        let c = state.pointee.counters
        //? 0.5 installed, 0.25 crossfaded to, 0.125 waited and was replaced by 2.0, which was crossfaded to
        #expect(c.crossfades == 2 && c.waited == 2)
        func scaled(_ n: Int, _ level: Double) -> Float { Float(Double(input[0][n]) * level) }
        #expect(signal[0][0] == scaled(0, 0.5) && signal[0][255] == scaled(255, 0.5))
        //? the first crossfade ends at 256 + 960, inside the fifth block; the rest of that block is 0.25's
        #expect(signal[0][256 + 960] == scaled(256 + 960, 0.25) && signal[0][1279] == scaled(1279, 0.25))
        //? the next starts at the next block's start, from 0.25 to 2.0 - never 0.125
        let w0 = 0.5 - 0.5 * cos(Double.pi / 960)
        let x = Double(input[0][1280])
        #expect(signal[0][1280] == Float((1 - w0) * (x * 0.25) + w0 * (x * 2.0)))
        #expect((1280 + 960..<5120).allSatisfy { signal[0][$0] == scaled($0, 2.0) && signal[1][$0] == Float(Double(input[1][$0]) * 2) })
    }

    @Test func aBankForAnotherRateIsIgnored() {
        let input = Self.noise(2, 1024, seed: 9)
        let state = EQRender.make(rate: 48000, channels: 2, maximumFrames: 4096)
        defer { EQRender.free(state) }
        var signal = input
        let other = Self.bank([Self.section(.filter(1), fc: 1000, gain: 6, q: 1, rate: 44100)], level: 1, rate: 44100)
        Self.block(state, &signal, from: 0, frames: 512, offering: other.packed)
        Self.block(state, &signal, from: 512, frames: 512, offering: other.packed)
        #expect(Self.bits(signal) == Self.bits(input))
        #expect(state.pointee.counters.otherRate == 2 && state.pointee.counters.crossfades == 0)
    }

    /// A bank equal to the live one, bit for bit, is taken with nothing done - but its ids are taken, so the next
    /// change warm-starts by them.
    @Test func anEqualBankTakesItsIDsAndNothingElse() {
        let input = Self.noise(2, 2048, seed: 13)
        let state = EQRender.make(rate: 48000, channels: 2, maximumFrames: 4096)
        defer { EQRender.free(state) }
        var signal = input
        let a = Self.bank([Self.section(.filter(1), fc: 300, gain: 4, q: 1)], level: 0.9)
        let renumbered = Self.bank([Self.section(.filter(7), fc: 300, gain: 4, q: 1)], level: 0.9)
        Self.block(state, &signal, from: 0, frames: 1024, offering: a.packed)
        Self.block(state, &signal, from: 1024, frames: 1024, offering: renumbered.packed)
        #expect(state.pointee.counters.crossfades == 0 && !state.pointee.fading)
        let (alone, _) = Self.render(a, input, blocks: 1024)
        #expect(Self.bits(signal) == Self.bits(alone))
        let live = state.pointee.live
        #expect(live[EQBank.header + 5] == EQSectionID.filter(7).code)
    }

    // ------------------------------------------------------------ the counters, and the largest block

    @Test func aBlockOverTheMostIsRefusedAndLeftUntouched() {
        let state = EQRender.make(rate: 48000, channels: 1, maximumFrames: 4096)
        defer { EQRender.free(state) }
        let bank = Self.bank([Self.section(.filter(1), fc: 1000, gain: 6, q: 1)], level: 1)
        var signal = Self.noise(1, 4097, seed: 1)
        let before = signal
        #expect(!Self.block(state, &signal, from: 0, frames: 4097, offering: bank.packed))
        #expect(Self.bits(signal) == Self.bits(before) && state.pointee.counters.refused == 1)
        #expect(Self.block(state, &signal, from: 0, frames: 4096, offering: bank.packed))
        #expect(Self.bits(signal) != Self.bits(before) && state.pointee.counters.refused == 1)
    }

    @Test func oversAndTheLargestAreCounted() {
        let input: [[Float]] = [[0.6, -0.4, 0.5, -0.7, 0.1], [0.2, 0.3, -0.55, 0, 0]]
        let (output, counters) = Self.render(Self.bank([], level: 2), input, blocks: 2)
        #expect(output == input.map { $0.map { Float(Double($0) * 2) } })
        //? 1.2, -1.4 and -1.1 are over; 1.0 is full scale, not over it
        #expect(counters.overs == 3)
        #expect(counters.largest == Double(Float(Double(Float(-0.7)) * 2).magnitude))
    }
}
