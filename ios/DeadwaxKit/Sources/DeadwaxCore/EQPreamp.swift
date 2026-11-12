import Foundation

/// The automatic preamp (eq.md 1.4, James's decision): the curve's top over every ear taken away, rounded to 0.1 dB
/// toward quieter - and never a boost (8, question 10). One for both ears, so a per-ear correction keeps its balance.
public enum EQPreamp {
    /// `-ceil(top × 10) / 10` when the top is above 0 dB, else 0. A top within 1e-9 dB of a tenth counts as on it:
    /// oratory1990's HD 650 ParametricEQ.txt tops out at DC at 6.400000000025 dB (its shelves' gains, summed in
    /// floating point), which is 6.4, not a hair over it calling for 6.5.
    public static func automatic(top: Double) -> Double {
        if top <= 1e-9 { return 0 }
        return -(((top - 1e-9) * 10).rounded(.up) / 10)
    }

    /// The automatic preamp of the ears' curves at a rate.
    public static func automatic(_ ears: [EQResponse.Ear], rate: Double) -> Double {
        automatic(top: EQResponse.top(ears, rate: rate).db)
    }

    /// A level in dB as the multiplier the render applies.
    public static func linear(_ db: Double) -> Double { pow(10.0, db / 20) }
}

/// A correction's own preamp (4): the part both ears share, and what each ear has beyond it - so `left` and `right`
/// are offsets, one of them 0 and the other at or below it (APO's `Preamp:` lines after `Channel: L` or `R`).
/// Automatic replaces `all` with deadwax's own (a correction's level is headroom) and keeps the difference between
/// the ears; set by hand, an import sets the preamp to `all` (1.4).
public struct EQPreampParts: Codable, Equatable, Sendable {
    public var all: Double
    public var left: Double
    public var right: Double

    public static let zero = EQPreampParts(all: 0, left: 0, right: 0)

    public init(all: Double, left: Double, right: Double) {
        self.all = all
        self.left = left
        self.right = right
    }

    /// What a file's `Preamp:` lines add up to for each selection, as shared and per-ear parts: the larger ear's own
    /// part moves into the shared one, so an ear's offset is never a boost over the other. (The spec says only "the
    /// part they share"; this is how it is read - and it is what lets a written file read back to the same parts, bit
    /// for bit: written parts are already in this form, so nothing moves.)
    public static func normalised(all: Double, left: Double, right: Double) -> EQPreampParts {
        let extra = max(left, right)
        return EQPreampParts(all: all + extra, left: left - extra, right: right - extra)
    }

    /// The offset an ear's list plays at beyond the preamp: the shared list (channels 2 and up) none.
    public func offset(_ channel: EQChannel) -> Double {
        switch channel {
        case .all: 0
        case .left: left
        case .right: right
        }
    }

    /// One ear differs from the other.
    public var perEar: Bool { left != 0 || right != 0 }
}
