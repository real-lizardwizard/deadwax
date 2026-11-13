import Foundation

// What a start of the output puts in, and the settings versions every bank is stamped with (notes/ios-specs/eq.md 1.6,
// 1.8; slice 2's review, items 1 and 2). Pure, so the order of things - the part that is easy to get wrong - is tested
// on Linux; the app keeps one book under a lock shared by the main thread and the engine's queue.

extension EQSound {
    /// The bank this sound makes at a rate - `EQSettings.bank`'s, from the sound alone.
    public func bank(key: String, rate: Double, version: Int) -> EQBank {
        let hand: Double?
        switch preamp {
        case .automatic: hand = nil
        case .hand(let dB): hand = dB
        }
        return EQBank.make(rate: rate, key: key, version: version, on: on, correction: correction, offsets: offsets,
                           bands: gains, preamp: hand)
    }
}

/// What a start does (1.8), as the book plans it.
public enum EQStartPlan: Equatable, Sendable {
    /// a bank made ahead - or Off, nothing to make - stamped with the start's own version: published as it is
    case ready(EQBank)
    /// no bank made ahead for this rate: made now, on the start's path, from this sound, with this version
    case make(key: String, sound: EQSound, version: Int)
    /// Debug's Muffle is on: the test curve, with this version
    case muffle(version: Int)
}

/// The EQ's book of versions and banks made ahead (1.6, 1.8), shared by the main thread and the engine's queue.
///
/// - **One version counter for everything**, raised under the book's lock: by every change the main thread publishes,
///   by every route change, and **by every start itself** - so a start's bank, made at the rate the unit has just
///   allocated at, always outranks a bank the main thread made a moment before at the rate it had read until then.
///   That is slice 2's review's item 2: the host drops a same-version bank made for another rate as "older", which is
///   right only if a bank for the right rate always comes with a version of its own. The main thread raises the
///   version **before** it reads the host's rate; a start raises it after the host has the new rate (the unit's
///   allocation, then `eqStart`). Under the lock one of them comes first: if the start does, the main thread's version
///   is the newer and it reads the new rate; if the main thread does, the start's is the newer, and it is the start's
///   bank - at the new rate - that plays.
/// - **Banks made ahead** (item 1): every output's bank for each rate it has started at, made off the start's path -
///   the preamp's search included, which is most of a bank's making - so a start only looks one up and stamps it.
///   Each is kept with the sound it was made from and dropped when that output's sound changes.
public struct EQStartBook: Sendable {
    /// the newest settings version handed out
    public private(set) var version = 0
    /// Debug's Muffle (slice 2's test curve)
    public var muffle = false
    /// each output's sound, as the settings last had it
    public private(set) var sounds: [String: EQSound] = [:]
    /// banks made ahead: by output, then rate
    public private(set) var ready: [String: [Double: EQBank]] = [:]
    /// the rates each output has started at, the most recent last
    public private(set) var rates: [String: [Double]] = [:]

    /// The rates every output's bank is made ahead for before it has started at any: the two iOS outputs run at.
    public static let usualRates: [Double] = [48_000, 44_100]
    /// How many rates are kept for each output.
    public static let keptRates = 3

    public init() {}

    /// A new version, for a change or a start.
    public mutating func bump() -> Int {
        version += 1
        return version
    }

    /// The settings changed: each output's sound brought up to date, and the banks made from a sound it no longer
    /// has dropped (a bank never outlives the setting it was made from).
    public mutating func update(_ settings: EQSettings) {
        var now: [String: EQSound] = [:]
        for o in settings.outputs { now[o.key] = settings.sound(o.key) }
        for key in Set(sounds.keys).union(now.keys) where sounds[key] != now[key] { ready[key] = nil }
        sounds = now
    }

    /// The rates an output's bank is made ahead for: those it has started at, the most recent first, then the usual
    /// two.
    public func rates(for key: String) -> [Double] {
        var out: [Double] = []
        for rate in (rates[key] ?? []).reversed() + Self.usualRates where !out.contains(rate) { out.append(rate) }
        return out
    }

    /// What is still to be made ahead for an output: each of its rates with no bank yet, and the sound to make it from
    /// - nothing while it is Off, whose bank is the identity, made in no time.
    public func wanted(_ key: String) -> [(rate: Double, sound: EQSound)] {
        guard let sound = sounds[key], sound.on else { return [] }
        return rates(for: key).filter { ready[key]?[$0] == nil }.map { ($0, sound) }
    }

    /// A bank made ahead from `sound` - kept only if that is still the output's sound (a change made while it was
    /// being made has dropped it). True when kept.
    @discardableResult
    public mutating func keep(_ bank: EQBank, from sound: EQSound) -> Bool {
        guard sounds[bank.key] == sound else { return false }
        ready[bank.key, default: [:]][bank.rate] = bank
        return true
    }

    /// A bank for an output at a rate, if one was made ahead - stamped with `version`.
    public func readyBank(_ key: String, rate: Double, version: Int) -> EQBank? {
        guard var bank = ready[key]?[rate] else { return nil }
        bank.version = version
        return bank
    }

    /// A start of the output (1.8), on the engine's queue: a version of its own, and the output's bank for the rate
    /// the unit runs at - made ahead, or Off for an output with no setting (one never met starts Off, 3.12), or to be
    /// made now. The rate is noted, so the output's next start finds its bank made.
    public mutating func start(_ key: String, rate: Double) -> EQStartPlan {
        let v = bump()
        if muffle { return .muffle(version: v) }
        var started = rates[key] ?? []
        started.removeAll { $0 == rate }
        started.append(rate)
        rates[key] = Array(started.suffix(Self.keptRates))
        guard let sound = sounds[key] else { return .ready(EQBank.identity(rate: rate, key: key, version: v)) }
        if let bank = readyBank(key, rate: rate, version: v) { return .ready(bank) }
        if !sound.on { return .ready(EQBank.identity(rate: rate, key: key, version: v)) }
        return .make(key: key, sound: sound, version: v)
    }
}

/// What the last start spent putting its curve in (Debug's "Start took"): seconds, and whether its bank was made ahead.
public struct EQStartTime: Equatable, Sendable {
    public var seconds: Double
    public var ready: Bool
    public var rate: Double

    public init(seconds: Double, ready: Bool, rate: Double) {
        self.seconds = seconds
        self.ready = ready
        self.rate = rate
    }

    public var words: String { EQWords.Debug.startTook(ms: seconds * 1_000, ready: ready, rate: rate) }
}

/// Where the EQ's banks go: the engine's EQHost (eq.md 1.6) as three calls - so the desk below is Core's and tested on
/// Linux, and against the real host on macOS (DeadwaxAudioTests' EQStartTests).
public struct EQTaker: Sendable {
    /// the output now (`EQHost.setOutput`)
    public var setOutput: @Sendable (String) -> Void
    /// a bank, taken under the host's rules - true when it was
    public var publish: @Sendable (EQBank) -> Bool
    /// the rate the unit last allocated at; nil before the output first started
    public var rate: @Sendable () -> Double?

    public init(setOutput: @escaping @Sendable (String) -> Void, publish: @escaping @Sendable (EQBank) -> Bool,
                rate: @escaping @Sendable () -> Double?) {
        self.setOutput = setOutput
        self.publish = publish
        self.rate = rate
    }
}

/// A version taken for a change, and whether Debug's Muffle was on when it was.
public struct EQTicket: Equatable, Sendable {
    public var version: Int
    public var muffle: Bool
}

/// The book behind its lock, and the two ways a bank reaches the host (eq.md 1.6, 1.8): a change on the main thread,
/// and a start on the engine's queue. Each is split into the steps whose order matters, so a test can put them in
/// every order; `changed` and `start` are those steps in one go.
public final class EQStartDesk: @unchecked Sendable {
    private let lock = NSLock()
    private var book = EQStartBook()
    private var last: EQStartTime?
    private let muffleKey: String
    private let muffleBank: @Sendable (Double, Int) -> EQBank
    private let clock: @Sendable () -> Double

    /// `muffleKey` and `muffleBank`: Debug's test curve (slice 2's EQTestCurve), its own output and its bank at a rate
    /// and version. `clock`: seconds, for the Start took row.
    public init(muffleKey: String, muffleBank: @escaping @Sendable (Double, Int) -> EQBank,
                clock: @escaping @Sendable () -> Double) {
        self.muffleKey = muffleKey
        self.muffleBank = muffleBank
        self.clock = clock
    }

    private func locked<T>(_ body: (inout EQStartBook) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&book)
    }

    /// The book as it stands (tests, Debug).
    public var snapshot: EQStartBook { locked { $0 } }

    /// What the last start spent putting its curve in.
    public var lastStart: EQStartTime? {
        lock.lock()
        defer { lock.unlock() }
        return last
    }

    // MARK: a change, on the main thread

    /// A change's first step: the book brought up to date and a version taken - **before** the host's rate is read.
    public func take(_ settings: EQSettings, muffle: Bool) -> EQTicket {
        locked { (b: inout EQStartBook) -> EQTicket in
            b.muffle = muffle
            b.update(settings)
            return EQTicket(version: b.bump(), muffle: muffle)
        }
    }

    /// A change's second step: the bank for `key` (the output now) at the rate read after the first step - made
    /// ahead, or made now and kept for the next start - or Muffle's; and the output it is for.
    public func bank(_ key: String, rate: Double, ticket: EQTicket) -> (output: String, bank: EQBank) {
        if ticket.muffle { return (muffleKey, muffleBank(rate, ticket.version)) }
        let (ready, sound) = locked { (b: inout EQStartBook) -> (EQBank?, EQSound?) in
            (b.readyBank(key, rate: rate, version: ticket.version), b.sounds[key])
        }
        if let ready { return (key, ready) }
        guard let sound else { return (key, EQBank.identity(rate: rate, key: key, version: ticket.version)) }
        let made = sound.bank(key: key, rate: rate, version: ticket.version)
        if sound.on { locked { (b: inout EQStartBook) -> Void in b.keep(made, from: sound) } }
        return (key, made)
    }

    /// A change (settings, the route, Muffle): a new version, then the output now's bank at the host's rate, put in.
    /// Before the output has first started there is no rate, and nothing to publish: its start puts the curve in.
    /// The bank published, if one was.
    @discardableResult
    public func changed(_ settings: EQSettings, route key: String, muffle: Bool, host: EQTaker) -> EQBank? {
        changed(settings, route: key, muffle: muffle, hosts: [host]).first ?? nil
    }

    /// The same for every output that plays (eq.md 1.9, 5.6: the song's and the turntable's deck engine): one version
    /// taken, then each host's bank made at **that host's own rate** - the deck engine may run at another rate than the
    /// song's unit (slice 2's review, question 5), and a bank's coefficients are for one rate. A host not yet started
    /// gets nothing (nil in its place): its own start puts the curve in.
    @discardableResult
    public func changed(_ settings: EQSettings, route key: String, muffle: Bool, hosts: [EQTaker]) -> [EQBank?] {
        let ticket = take(settings, muffle: muffle)
        return hosts.map { (host: EQTaker) -> EQBank? in
            guard let rate = host.rate() else { return nil }
            let (output, bank) = bank(key, rate: rate, ticket: ticket)
            host.setOutput(output)
            _ = host.publish(bank)
            return bank
        }
    }

    /// The banks still to be made ahead for these outputs, made outside the lock (off the main thread, normally) and
    /// kept unless a change made meanwhile has dropped them. How many were made.
    @discardableResult
    public func makeAhead(_ keys: [String]) -> Int {
        let wanted = locked { (b: inout EQStartBook) -> [(key: String, rate: Double, sound: EQSound)] in
            keys.flatMap { (key: String) -> [(key: String, rate: Double, sound: EQSound)] in
                b.wanted(key).map { (key: key, rate: $0.rate, sound: $0.sound) }
            }
        }
        for w in wanted {
            let bank = w.sound.bank(key: w.key, rate: w.rate, version: 0)
            locked { (b: inout EQStartBook) -> Void in b.keep(bank, from: w.sound) }
        }
        return wanted.count
    }

    // MARK: a start, on the engine's queue

    /// A start's first step: a version of its own, after the host has the new rate (the unit's allocation).
    public func plan(_ key: String, rate: Double) -> EQStartPlan {
        locked { $0.start(key, rate: rate) }
    }

    /// A start's second step: the bank its plan names - made now only when nothing was made ahead - and the output
    /// it is for.
    public func bank(_ plan: EQStartPlan, rate: Double) -> (output: String, bank: EQBank, ready: Bool) {
        switch plan {
        case .ready(let bank):
            return (bank.key, bank, true)
        case .muffle(let version):
            return (muffleKey, muffleBank(rate, version), false)
        case .make(let key, let sound, let version):
            let bank = sound.bank(key: key, rate: rate, version: version)
            locked { (b: inout EQStartBook) -> Void in b.keep(bank, from: sound) }
            return (key, bank, false)
        }
    }

    /// A start of the output (1.8), between prepare and start: the output now (`key`, from the route) and its curve
    /// at the unit's rate put in - made ahead, so the start only looks it up - and the time it took kept for Debug.
    /// `record` false: a second output's start (the deck engine's), which isn't the song's and so isn't Debug's Start
    /// took.
    public func start(_ key: String, rate: Double, host: EQTaker, record: Bool = true) {
        let began = clock()
        let (output, bank, ready) = bank(plan(key, rate: rate), rate: rate)
        host.setOutput(output)
        _ = host.publish(bank)
        guard record else { return }
        let took = EQStartTime(seconds: max(clock() - began, 0), ready: ready, rate: rate)
        lock.lock()
        last = took
        lock.unlock()
    }
}
