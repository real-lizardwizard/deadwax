import Foundation

// The Mac's sleep, power and outputs (the Mac app's plan, slice 5; notes/ios.md "The Mac app, slice 5: sleep, power and
// downloads"): the rules the App's IOKit and CoreAudio calls follow on the Mac (ios/App/Shared/Platform.swift, its Mac
// half), here with no platform condition so every one is tested on Linux. Core never asks which build it is: these are
// read only where the App reads IOKit or CoreAudio, which only the Mac's build does.
//
// - Sleep: playing when the Mac goes to sleep pauses it, and it wakes paused at the same place - never music out of a
//   laptop opened in a meeting. A sleep is never refused.
// - Power: Only while charging on a Mac reads which source powers it - plugged in, or on battery - and a reading that
//   says nothing it knows is plugged in (a Mac with no battery must never wait for a charge it can't have).
// - Outputs: the output in use going away (headphones out, AirPods or a speaker gone, a USB DAC pulled) pauses, as the
//   phone does; another output chosen, the old one still there, doesn't.

public enum MacPower {
    // MARK: sleep (IOKit's IORegisterForSystemPower)

    /// IOMessage.h's three, which Swift doesn't import (each a C macro, `iokit_common_msg(n)`: sys_iokit, 0x38 << 26 =
    /// 0xe0000000, with sub_iokit_common, 0, and the message's own number): may the Mac sleep (idle sleep, which
    /// anything may refuse), it will sleep (it can't be refused), and it has woken.
    public static let canSystemSleep: UInt32 = 0xe000_0270
    public static let systemWillSleep: UInt32 = 0xe000_0280
    public static let systemHasPoweredOn: UInt32 = 0xe000_0300

    /// What a power message asks of deadwax.
    public enum Answer: Sendable, Equatable {
        /// May the Mac sleep: yes, at once - deadwax never refuses a sleep (IOAllowPowerChange, never
        /// IOCancelPowerChange).
        case allowNow
        /// It will sleep: the player paused first (`willSleep`), then the sleep allowed (it waits up to 30 s for that).
        case pauseThenAllow
        /// It has woken: nothing starts - it stays paused where the sleep left it.
        case woke
        /// Any other message (a sleep called off, waking about to begin): nothing to do or to answer.
        case nothing
    }

    /// The answer to IOKit's `message`.
    public static func answer(to message: UInt32) -> Answer {
        switch message {
        case canSystemSleep: return .allowNow
        case systemWillSleep: return .pauseThenAllow
        case systemHasPoweredOn: return .woke
        default: return .nothing
        }
    }

    /// What the player does as the Mac goes to sleep.
    public struct AtSleep: Sendable, Equatable {
        /// Pause now: something is playing, or waiting to be asked for again (a retry), which would start the music
        /// once the Mac woke.
        public let pause: Bool
        /// What the player's `interrupted` mark is left as: never set. An interruption that began before the sleep (if
        /// macOS posts one around it) would otherwise end at the wake with "should resume" and start the music.
        public let interrupted: Bool
        /// Slept since the listener last played: set, until they next do (Play, or a new queue). One that begins after
        /// the pause can't set `interrupted` meanwhile (`interruptionArms`) - the engine's pause lands a moment after
        /// it's asked for, so "playing" alone could still say yes then.
        public let sleptSincePlay: Bool
    }

    /// At will-sleep, given what the player is doing now.
    public static func willSleep(playing: Bool, retrying: Bool, interrupted: Bool) -> AtSleep {
        AtSleep(pause: playing || retrying, interrupted: false, sleptSincePlay: true)
    }

    /// An interruption begins (a call, an alarm): whether its end, saying "should resume", plays again - something was
    /// playing, or a retry waited (the phone's rule, as it was), and not since a sleep paused it. On the iPhone nothing
    /// sets `sleptSincePlay`, so this is the phone's rule exactly.
    public static func interruptionArms(playing: Bool, retrying: Bool, sleptSincePlay: Bool) -> Bool {
        (playing || retrying) && !sleptSincePlay
    }

    /// The engine log's line for a sleep, so Debug shows what the Mac did and what deadwax did about it.
    public static func sleepNote(_ at: AtSleep) -> String {
        "power: the Mac will sleep - " + (at.pause ? "paused" : "nothing playing") + ", no resume at the wake"
    }

    /// ...and for the wake (`.woke`), where nothing is done: the player stays as the sleep left it, paused at the same
    /// place, until Play.
    public static let wakeNote = "power: the Mac woke - nothing started"

    /// IORegisterForSystemPower refused (in the sandbox, say): the sleep isn't followed, said once in the engine log.
    public static let sleepUnwatched = "power: can't follow the Mac's sleep (IORegisterForSystemPower refused) - playing on"

    // MARK: power (IOKit's IOPSGetProvidingPowerSourceType)

    /// IOPowerSources.h's three answers: the mains, the battery, a UPS.
    public static let acPower = "AC Power"
    public static let batteryPower = "Battery Power"
    public static let upsPower = "UPS Power"

    /// Only while charging's reading on a Mac, from the source IOKit says powers it: the mains is plugged in (charging or
    /// not - IOKit's answer says which source, not whether a battery charges); the battery is on battery; a UPS is the
    /// mains gone, so on battery too. Anything else - no answer, an empty one, one it doesn't know - is plugged in: a Mac
    /// with no battery (a Mac mini, an iMac, a Studio) must never wait for a charge it can't have.
    public static func power(source: String?) -> PowerState {
        switch source {
        case batteryPower?, upsPower?: return .unplugged
        default: return .pluggedIn
        }
    }

    // MARK: outputs (CoreAudio's default output device)

    /// CoreAudio's default output changed from `previous` to `now`, with `devices` the devices there are now: whether the
    /// one in use went away (headphones unplugged - on Apple silicon "External Headphones" is a device of its own -
    /// AirPods or a Bluetooth speaker disconnected, a USB DAC pulled), when the player pauses as the phone does. Another
    /// output chosen, the old one still there, isn't: nothing pauses, as on the phone for a route you chose. No previous
    /// reading (0 is CoreAudio's unknown object), or no change, is nothing.
    public static func outputGone(previous: UInt32?, now: UInt32?, devices: [UInt32]) -> Bool {
        guard let previous, previous != 0, previous != now else { return false }
        return !devices.contains(previous)
    }

    /// Who said the output went: the audio session (AVAudioSession's route change, the phone's - whether Catalyst posts
    /// it is check 440's) or CoreAudio's default output (the Mac's own).
    public enum OutputGoneBy: String, Sendable, CaseIterable {
        case session
        case coreAudio
    }

    /// The engine log's line for a pause because the output went, so check 440 tells which macOS posts. Said again for
    /// the second when both do - the pause twice is harmless (the engine's pause is nothing while paused).
    public static func outputGoneNote(_ by: OutputGoneBy, playing: Bool) -> String {
        let who = by == .session ? "the session said so" : "CoreAudio"
        return "output gone: \(who) - " + (playing ? "paused" : "nothing playing")
    }

    /// CoreAudio's listener refused: the default output isn't followed, said once in the engine log.
    public static let outputsUnwatched = "output: can't follow CoreAudio's default output - only the session's route changes pause"
}
