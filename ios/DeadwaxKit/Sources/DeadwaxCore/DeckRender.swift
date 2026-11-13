/// The voice as the deck engine's render calls it (notes/ios-specs/turntable.md 4.3): one concrete entry per
/// function, over `PlatformMaths`, so the render never reaches a generic function unspecialised - in this module, under
/// the release build's whole-module optimisation, the generic voice is specialised for PlatformMaths here, and no
/// generic metadata is looked up on the audio thread (a first use of one can take the runtime's lock). Every
/// argument is a pointer or a number: nothing here is counted, copied or allocated after `newState`.
///
/// And the message slot (`DeckSlot`): a VoiceMessage as plain numbers and pointers, the size the ring's storage is
/// made of, written on the main thread and read on the audio thread.
public enum DeckRender {
    /// A voice at rest (off the audio thread: it allocates).
    public static func newState() -> VoiceState { DeckVoice.newVoiceState(PlatformMaths()) }

    /// One message, applied as of voice time `now`.
    public static func command(_ state: UnsafeMutablePointer<VoiceState>, _ message: VoiceMessage, now: Double,
                               rate: Double) {
        DeckVoice.voiceCommand(&state.pointee, message, now, rate, PlatformMaths())
    }

    /// `frames` of the voice into `outputs` (one or two channels), from voice time `now`.
    public static func render(_ state: UnsafeMutablePointer<VoiceState>,
                              _ outputs: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>, frames: Int,
                              rate: Double, now: Double) {
        DeckVoice.renderVoice(&state.pointee, outputs, frames, rate, now, PlatformMaths())
    }

    /// What the voice says after a block, 30 times a second (or nil).
    public static func report(_ state: UnsafeMutablePointer<VoiceState>, frames: Int, rate: Double,
                              now: Double) -> VoiceHeard? {
        DeckVoice.voiceReport(&state.pointee, frames, rate, now, DeckVoice.reportsPerSecond)
    }

    /// Whether the voice is sounding, as its clock reads it (3.2): `L` moves freely only while it isn't. The render
    /// can't see the deck's motion - a hand, a plan, a handover - so it reads the voice's own gain: aiming above 0, or
    /// not yet under -100 dB.
    @inlinable public static func sounding(_ state: UnsafePointer<VoiceState>) -> Bool {
        state.pointee.gainTarget > 0 || state.pointee.gain > 1e-5
    }
}

/// A VoiceMessage as the ring carries it: a tag, five numbers, and a window's two pointers, its length and the
/// deck engine's id for it (which the render hands back when the voice lets go of the window). Trivial: copied by
/// bytes, nothing counted.
public struct DeckSlot {
    public enum Tag: Int32 { case window = 0, noWindow, take, drive, hand, fade, stop }

    public var tag: Int32 = Tag.stop.rawValue
    /// `drive`'s accel was given (the web's undefined, else a number)
    public var hasAccel = false
    public var id: UInt32 = 0
    public var a = 0.0, b = 0.0, c = 0.0, d = 0.0, e = 0.0
    public var first: UnsafePointer<Float>?
    public var second: UnsafePointer<Float>?
    public var length = 0

    public init() {}

    /// `message` as a slot; a window's `id` alongside.
    public init(_ message: VoiceMessage, id: UInt32 = 0) {
        self.id = id
        switch message {
        case .window(let window):
            if let window {
                tag = Tag.window.rawValue
                first = window.first
                second = window.second
                length = window.length
                a = window.start
                b = window.rate
            } else {
                tag = Tag.noWindow.rawValue
            }
        case let .take(at, rate, time, until):
            tag = Tag.take.rawValue
            (a, b, c, d) = (at, rate, time, until)
        case let .drive(at, rate, accel, time, until):
            tag = Tag.drive.rawValue
            (a, b, c, d, e) = (at, rate, accel ?? 0, time, until)
            hasAccel = accel != nil
        case let .hand(at, time):
            tag = Tag.hand.rawValue
            (a, b) = (at, time)
        case .fade(let seconds):
            tag = Tag.fade.rawValue
            a = seconds
        case .stop:
            tag = Tag.stop.rawValue
        }
    }

    /// Whether it carries a window (or says there is none): the voice lets go of the one it had.
    @inlinable public var replacesWindow: Bool { tag == Tag.window.rawValue || tag == Tag.noWindow.rawValue }

    /// The message again.
    public var message: VoiceMessage {
        switch Tag(rawValue: tag) ?? .stop {
        case .window:
            guard let first else { return .window(nil) }
            return .window(VoiceWindow(first: first, second: second, length: length, start: a, rate: b))
        case .noWindow: return .window(nil)
        case .take: return .take(at: a, rate: b, time: c, until: d)
        case .drive: return .drive(at: a, rate: b, accel: hasAccel ? c : nil, time: d, until: e)
        case .hand: return .hand(at: a, time: b)
        case .fade: return .fade(seconds: a)
        case .stop: return .stop
        }
    }
}

/// A report as the ring carries it back (4.3): the voice's `VoiceHeard`, and the render's block count when it was made.
public struct DeckHeardSlot {
    public var heard = VoiceHeard(pos: 0, rate: 0, gain: 0, time: 0, held: 0, peaks: 0, lowest: 1)
    public var block: UInt64 = 0
    public init() {}
}
