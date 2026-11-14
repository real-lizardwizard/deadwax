/// Pull to shuffle (Phase 4, slice 3b - notes/ios-specs/phase4-library.md 2.8 and 3.5): James's "if you drag down far
/// enough there can be a cool little shuffle graphic that changes as you pull down, and then once you go far enough, it
/// changes, and starts shuffling when you release". A state machine, as TurntablePress, Scrub and LyricsHold are: the
/// app feeds it how far the page shown is pulled past its top and whether a finger is on it, draws what it says, plays
/// the haptic tick on `.armed` and starts the shuffle on `.shuffle` - in that same call, nothing awaited first.
///
/// idle -> pulling(progress) -> armed at `line` -> back under `line - slack`: pulling -> lifted while armed: released,
/// then idle once the page is back at rest. A pull no finger began (a fling's bounce at the top) stays idle, and it arms
/// only when a release would shuffle (`ready`).
public struct PullShuffle: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        /// pulled, under the line: how far towards it, 0 to under 1 (1 exactly when pulled past it unready)
        case pulling(Double)
        /// past the line: a release shuffles
        case armed
        /// let go while armed: the shuffle has started; until the page is back at rest
        case released
    }

    /// What a move or a lift asks of the app.
    public enum Event: Sendable, Equatable {
        /// the line crossed: the haptic tick
        case armed
        /// let go armed: start the shuffle, now
        case shuffle
    }

    /// The pull, in points past the page's top, at which it arms.
    public static let line = 110.0
    /// How far back under the line a pull goes before it disarms - so a finger resting on the line ticks once.
    public static let slack = 10.0

    public private(set) var phase: Phase = .idle

    public init() {}

    /// How far the graphic is drawn towards the line: 0 at idle, 1 armed and released.
    public var progress: Double {
        switch phase {
        case .idle: return 0
        case .pulling(let progress): return progress
        case .armed, .released: return 1
        }
    }

    /// The graphic is drawn (anything but idle).
    public var shown: Bool { phase != .idle }

    /// The page moved: `pull` points past its top (0 or less at rest), `touching` a finger on it, `ready` a release
    /// would shuffle. `.armed` once each time the line is crossed by the finger.
    public mutating func moved(_ pull: Double, touching: Bool, ready: Bool) -> Event? {
        let past = pull.isFinite ? pull : 0
        switch phase {
        case .released:
            if past <= 0 { phase = .idle }
            return nil
        case .armed:
            if past <= 0 {
                phase = .idle
            } else if touching && past < Self.line - Self.slack {
                phase = .pulling(Self.towards(past))
            } else if !ready {
                phase = .pulling(1)
            }
            return nil
        case .idle, .pulling:
            if past <= 0 {
                phase = .idle
                return nil
            }
            // a fling's bounce: no finger began it
            if phase == .idle && !touching { return nil }
            if touching && ready && past >= Self.line {
                phase = .armed
                return .armed
            }
            phase = .pulling(past >= Self.line ? 1 : Self.towards(past))
            return nil
        }
    }

    /// The finger lifted. `.shuffle` when it was armed and a release would shuffle; otherwise the graphic follows the
    /// page back to rest.
    public mutating func lifted(ready: Bool) -> Event? {
        guard phase == .armed else { return nil }
        guard ready else {
            phase = .pulling(1)
            return nil
        }
        phase = .released
        return .shuffle
    }

    /// The page is no longer the one shown (or the shuffle went away): nothing drawn.
    public mutating func reset() {
        phase = .idle
    }

    /// The system took the touch (slice 3b's review) - a call, Siri, the app leaving the front: the finger's going is
    /// no release, so nothing shuffles; the graphic goes, and the next move from rest starts afresh. A release already
    /// made stays released.
    public mutating func interrupted() {
        if phase != .released { phase = .idle }
    }

    /// `pull` towards the line - only ever asked of a pull past the top and under the line, so above 0 and under 1.
    static func towards(_ pull: Double) -> Double {
        pull / line
    }
}

/// What the pull's graphic says under its mark (3.5) - the phone's own words, but the Shuffle's (ShuffleWords).
public enum PullShuffleWords {
    public static let pull = "Pull to shuffle"
    public static let release = "Release to shuffle"
    public static let shuffling = "Shuffling"
    public static let pullDownloads = "Pull to shuffle your downloads"
    public static let releaseDownloads = "Release to shuffle your downloads"
    public static let nothingHere = "Nothing on this phone to shuffle"

    /// The line for `phase`, as the Shuffle `can` - "" when there is nothing to shuffle at all (nothing is drawn).
    public static func line(_ phase: PullShuffle.Phase, can: ShuffleCan) -> String {
        if phase == .released { return shuffling }
        switch can {
        case .none: return ""
        case .gettingReady: return ShuffleWords.gettingReady
        case .failed(let why): return why
        case .nothingHere: return nothingHere
        case .ready: return phase == .armed ? release : pull
        case .downloads: return phase == .armed ? releaseDownloads : pullDownloads
        }
    }
}
