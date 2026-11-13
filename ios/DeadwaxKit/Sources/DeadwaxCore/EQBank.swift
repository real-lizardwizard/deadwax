import Foundation

/// What the render plays (eq.md 1.6): made on the main thread or the engine's queue, never the audio thread - the rate
/// it was made for, the output key and settings version it was made from, each channel list's sections and level, and
/// whether it is the identity (no sections, every level exactly 1), which the render passes through untouched (1.7).
///
/// Channel 0 plays the left's list, channel 1 the right's, the rest the shared list (`Channel: all`); a one-channel
/// output plays the left's (1.5).
public struct EQBank: Equatable, Sendable {
    public var rate: Double
    /// the output it was made for (`EQOutputs.key`)
    public var key: String
    /// the settings version it was made from
    public var version: Int
    public var left: [EQSection]
    public var right: [EQSection]
    /// channels 2 and up: the shared filters and the bands
    public var shared: [EQSection]
    /// the preamp as it plays, dB: deadwax's automatic one or yours
    public var preamp: Double
    /// each list's level, linear: the preamp and that ear's offset; the shared list's the preamp alone - or, automatic,
    /// lower where its own curve tops above the ears' (1.4)
    public var levels: [Double]

    public init(rate: Double, key: String, version: Int, left: [EQSection], right: [EQSection], shared: [EQSection],
                preamp: Double, levels: [Double]) {
        let most = EQLimits.sectionsPerChannel
        self.rate = rate
        self.key = key
        self.version = version
        //? never more than the render holds: a file is held to 74 filters an ear and the tone adds 10
        self.left = Array(left.prefix(most))
        self.right = Array(right.prefix(most))
        self.shared = Array(shared.prefix(most))
        self.preamp = preamp
        self.levels = levels
    }

    /// Off: nothing plays, nothing is changed.
    public static func identity(rate: Double, key: String, version: Int) -> EQBank {
        EQBank(rate: rate, key: key, version: version, left: [], right: [], shared: [], preamp: 0, levels: [1, 1, 1])
    }

    /// No sections and every level exactly 1 - Off, or a curve that is flat at this rate (1.7).
    public var isIdentity: Bool {
        left.isEmpty && right.isEmpty && shared.isEmpty && levels.allSatisfy { $0 == 1 }
    }

    /// An output's curve at a rate (1.4, 1.6): the correction's filters for each list (`all` and the ear's own, in the
    /// correction's order) that play at this rate, then the tone's bands that aren't at 0; the preamp - deadwax's
    /// automatic one over both ears, or `preamp` when it is set by hand - and each ear's offset from the correction's
    /// own parts (`offsets.left`, `offsets.right`; its `all` is replaced by the preamp); the shared list (channels 2 and
    /// up) at the preamp, or under it where its own top needs it. Off is the identity.
    public static func make(rate: Double, key: String, version: Int, on: Bool, correction: [EQFilter],
                            offsets: EQPreampParts, bands: [Double], preamp hand: Double?) -> EQBank {
        guard on else { return identity(rate: rate, key: key, version: version) }
        let tone = EQGraphic.sections(gains: bands, rate: rate)
        func list(_ ear: EQChannel?) -> [EQSection] {
            sections(correction.filter { $0.channel == .all || $0.channel == ear }, rate: rate) + tone
        }
        let left = list(.left), right = list(.right), shared = list(nil)
        let preamp = hand ?? EQPreamp.automatic([EQResponse.Ear(sections: left, offset: offsets.left),
                                                 EQResponse.Ear(sections: right, offset: offsets.right)], rate: rate)
        //? channels 2 and up play the shared list, with no ear's filters or offset. When it is neither ear's list at
        //  that ear's level - per-ear filters left out of it, or both ears' offsets below 0 - its own top can be above
        //  the ears', so the automatic preamp counts it for that list alone: no channel over 0 dB, and the ears' level
        //  (a stereo output's whole sound) not lowered for channels it doesn't have. By hand, the preamp is yours.
        var sharedPreamp = preamp
        if hand == nil && (left.count != shared.count || right.count != shared.count || max(offsets.left, offsets.right) < 0) {
            sharedPreamp = min(preamp, EQPreamp.automatic([EQResponse.Ear(sections: shared)], rate: rate))
        }
        let levels = [preamp + offsets.left, preamp + offsets.right, sharedPreamp].map(EQPreamp.linear)
        return EQBank(rate: rate, key: key, version: version, left: left, right: right, shared: shared,
                      preamp: preamp, levels: levels)
    }

    /// The filters that play at a rate, as sections `.filter(id)`.
    public static func sections(_ filters: [EQFilter], rate: Double) -> [EQSection] {
        filters.compactMap { (f: EQFilter) -> EQSection? in
            let d = f.design(rate: rate)
            guard d.outcome == .plays, let f0 = d.f0, let c = d.coefficients else { return nil }
            return EQSection(id: .filter(f.id), kind: f.kind, f0: f0, coefficients: c)
        }
    }

    /// 1.6's rule, one output at a time: a bank is published only if it was made for the output now and from a
    /// settings version at least the last one published.
    public static func publishable(key: String, version: Int, keyNow: String?, lastPublished: Int?) -> Bool {
        key == keyNow && version >= (lastPublished ?? Int.min)
    }

    // ------------------------------------------------------------ packed, as the render reads it

    /// Each section's slot: b0 b1 b2 a1 a2, its id's code, its kind's code, one spare.
    public static let slot = 8
    /// rate, identity (1 or 0), the three levels, the three counts
    public static let header = 8
    /// The doubles a packed bank takes: the header, then three lists of 84 slots (left, right, shared).
    public static let packedCount = header + 3 * EQLimits.sectionsPerChannel * slot

    /// The bank as the render copies it, into `packedCount` doubles.
    public func pack(into p: UnsafeMutablePointer<Double>) {
        p.update(repeating: 0, count: Self.packedCount)
        p[0] = rate
        p[1] = isIdentity ? 1 : 0
        for (i, list) in [left, right, shared].enumerated() {
            p[2 + i] = levels[i]
            p[5 + i] = Double(list.count)
            for (s, section) in list.enumerated() {
                let q = p + Self.header + (i * EQLimits.sectionsPerChannel + s) * Self.slot
                let c = section.coefficients
                q[0] = c.b0
                q[1] = c.b1
                q[2] = c.b2
                q[3] = c.a1
                q[4] = c.a2
                q[5] = section.id.code
                q[6] = section.kind.code
            }
        }
    }

    /// The bank packed, in an array the caller owns.
    public var packed: [Double] {
        var out = [Double](repeating: 0, count: Self.packedCount)
        out.withUnsafeMutableBufferPointer { pack(into: $0.baseAddress!) }
        return out
    }
}
