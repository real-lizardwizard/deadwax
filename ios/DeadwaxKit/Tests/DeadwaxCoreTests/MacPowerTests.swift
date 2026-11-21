import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac's sleep, power and outputs (the Mac app's plan, slice 5; notes/ios.md "The Mac app, slice 5: sleep, power and
/// downloads"): what IOKit's power messages ask, the player at will-sleep and at the wake, which source powers the Mac
/// as Only while charging reads it, whether the output in use went away - and each word slice 5 gave the Mac, beside
/// the phone's, which stay as they were. The App's IOKit and CoreAudio calls follow these and nothing else
/// (tests/test_ios_mac.py holds Platform.swift and PlayerModel to them).
@Suite struct MacPowerTests {
    // MARK: sleep

    @Test func theMessagesAreIOMessageHs() {
        // iokit_common_msg(n) = sys_iokit (err_system(0x38) = 0x38 << 26) | sub_iokit_common (0) | n
        func common(_ n: UInt32) -> UInt32 { (0x38 << 26) | n }
        #expect(MacPower.canSystemSleep == common(0x270) && MacPower.canSystemSleep == 0xe000_0270)
        #expect(MacPower.systemWillSleep == common(0x280) && MacPower.systemWillSleep == 0xe000_0280)
        #expect(MacPower.systemHasPoweredOn == common(0x300) && MacPower.systemHasPoweredOn == 0xe000_0300)
    }

    @Test func aSleepIsAllowedAndNeverRefused() {
        #expect(MacPower.answer(to: MacPower.canSystemSleep) == .allowNow)
        #expect(MacPower.answer(to: MacPower.systemWillSleep) == .pauseThenAllow)
        #expect(MacPower.answer(to: MacPower.systemHasPoweredOn) == .woke)
        // will-not-sleep (0x290), will-power-on (0x320), a device's own messages, nothing: nothing to do or answer
        for other: UInt32 in [0xe000_0290, 0xe000_0320, 0xe000_0010, 0, .max] {
            #expect(MacPower.answer(to: other) == .nothing, "\(String(other, radix: 16))")
        }
    }

    @Test func willSleepPausesAndDisarmsTheResume() {
        for playing in [false, true] {
            for retrying in [false, true] {
                for interrupted in [false, true] {
                    let at = MacPower.willSleep(playing: playing, retrying: retrying, interrupted: interrupted)
                    #expect(at.pause == (playing || retrying), "playing \(playing), retrying \(retrying)")
                    // an interruption that began before the sleep never resumes at the wake
                    #expect(!at.interrupted)
                    #expect(at.sleptSincePlay)
                }
            }
        }
        #expect(MacPower.sleepNote(MacPower.willSleep(playing: true, retrying: false, interrupted: false))
                == "power: the Mac will sleep - paused, no resume at the wake")
        #expect(MacPower.sleepNote(MacPower.willSleep(playing: false, retrying: false, interrupted: true))
                == "power: the Mac will sleep - nothing playing, no resume at the wake")
        #expect(MacPower.wakeNote == "power: the Mac woke - nothing started")
    }

    @Test func noInterruptionArmsAResumeSinceASleep() {
        // the phone's rule, as it was: playing or a retry waiting arms the resume
        #expect(MacPower.interruptionArms(playing: true, retrying: false, sleptSincePlay: false))
        #expect(MacPower.interruptionArms(playing: false, retrying: true, sleptSincePlay: false))
        #expect(!MacPower.interruptionArms(playing: false, retrying: false, sleptSincePlay: false))
        // since a sleep, until the listener plays again: never - even while the engine's pause hasn't landed yet
        for playing in [false, true] {
            for retrying in [false, true] {
                #expect(!MacPower.interruptionArms(playing: playing, retrying: retrying, sleptSincePlay: true))
            }
        }
    }

    // MARK: power

    @Test func thePowerSourceIsPluggedInUnlessItSaysBattery() {
        #expect(MacPower.power(source: "AC Power") == .pluggedIn)
        #expect(MacPower.power(source: "Battery Power") == .unplugged)
        // a UPS powering the Mac: the mains are gone
        #expect(MacPower.power(source: "UPS Power") == .unplugged)
        // unknown means plugged in: a Mac with no battery never waits for a charge it can't have
        for unknown: String? in [nil, "", "ac power", "Battery", "Solar", " AC Power"] {
            #expect(MacPower.power(source: unknown) == .pluggedIn, "\(unknown ?? "nil")")
        }
        #expect([MacPower.acPower, MacPower.batteryPower, MacPower.upsPower] == ["AC Power", "Battery Power", "UPS Power"])
        // plugged in lets Only while charging's songs go; on battery holds them
        #expect(PowerState.pluggedIn.charging && !PowerState.unplugged.charging)
    }

    @Test func thePowerIsSaidAsTheMacHasIt() {
        #expect(LibraryFollowWords.power(.pluggedIn, device: .mac) == "Plugged in")
        #expect(LibraryFollowWords.power(.unplugged, device: .mac) == "On battery")
        #expect(LibraryFollowWords.power(.unknown, device: .mac) == "Not known")
        // the phone's, as they were
        #expect(LibraryFollowWords.power(.unplugged, device: .iPhone) == "Not charging")
        #expect(LibraryFollowWords.power(.charging, device: .iPhone) == "Charging")
        #expect(LibraryFollowWords.power(.full, device: .iPhone) == "Full, on the charger")
        let now: Int64 = 10 * 3_600_000
        let ran = LibraryBackground.Run(task: LibraryBackground.refreshID, began: now, seconds: 1,
                                        outcome: .ran(checked: true, read: 0, downloading: 0, charging: true))
        let unplugged = LibraryBackground.Run(task: LibraryBackground.refreshID, began: now, seconds: 1,
                                              outcome: .ran(checked: true, read: 0, downloading: 0, charging: false))
        let expired = LibraryBackground.Run(task: LibraryBackground.chargingID, began: now, seconds: 30, outcome: .expired)
        #expect(LibraryFollowWords.backgroundRun(ran, now: now, device: .mac).hasPrefix("Refresh \u{00B7} checked, plugged in \u{00B7}"))
        #expect(LibraryFollowWords.backgroundRun(unplugged, now: now, device: .mac).hasPrefix("Refresh \u{00B7} checked, on battery \u{00B7}"))
        #expect(LibraryFollowWords.backgroundRun(expired, now: now, device: .mac) == "Charger \u{00B7} ended by macOS \u{00B7} 30.00 s \u{00B7} just now")
        #expect(LibraryFollowWords.backgroundRun(expired, now: now, device: .iPhone) == "Charger \u{00B7} ended by iOS \u{00B7} 30.00 s \u{00B7} just now")
    }

    // MARK: outputs

    @Test func theOutputInUseGoneIsGone() {
        let speakers: UInt32 = 41, headphones: UInt32 = 77, airPods: UInt32 = 90
        // headphones out (Apple silicon: "External Headphones" is a device of its own, gone with the plug)
        #expect(MacPower.outputGone(previous: headphones, now: speakers, devices: [speakers]))
        // AirPods disconnected, the speakers taken over
        #expect(MacPower.outputGone(previous: airPods, now: speakers, devices: [speakers, headphones]))
        // another output chosen, the old one still there: nothing pauses
        #expect(!MacPower.outputGone(previous: speakers, now: airPods, devices: [speakers, airPods]))
        #expect(!MacPower.outputGone(previous: airPods, now: speakers, devices: [speakers, airPods]))
        // headphones plugged in: the speakers are still there
        #expect(!MacPower.outputGone(previous: speakers, now: headphones, devices: [speakers, headphones]))
        // no change, no reading before (the first), CoreAudio's unknown object: nothing
        #expect(!MacPower.outputGone(previous: speakers, now: speakers, devices: []))
        #expect(!MacPower.outputGone(previous: nil, now: speakers, devices: [speakers]))
        #expect(!MacPower.outputGone(previous: 0, now: speakers, devices: [speakers]))
        // the last output gone, none in its place
        #expect(MacPower.outputGone(previous: headphones, now: nil, devices: []))
        #expect(MacPower.outputGone(previous: headphones, now: 0, devices: [speakers]))
    }

    @Test func eachPauseSaysWhoSaidTheOutputWent() {
        #expect(MacPower.outputGoneNote(.session, playing: true) == "output gone: the session said so - paused")
        #expect(MacPower.outputGoneNote(.coreAudio, playing: true) == "output gone: CoreAudio - paused")
        #expect(MacPower.outputGoneNote(.coreAudio, playing: false) == "output gone: CoreAudio - nothing playing")
        #expect(MacPower.OutputGoneBy.allCases == [.session, .coreAudio])
    }

    // MARK: the words slice 5 gave the Mac (the phone's beside them, as they were)

    @Test func downloadOverOnAMac() {
        #expect(DownloadWords.over(.wifi, device: .mac) == ("Wi-Fi or Ethernet only",
                                                            "Downloads use Wi-Fi or a cable alone - never a hotspot or Low Data Mode."))
        #expect(DownloadWords.over(.any, device: .mac) == ("Any connection", "Downloads use a hotspot too, when this Mac is on one."))
        #expect(DownloadWords.over(.wifi, device: .iPhone) == ("Wi-Fi only",
                                                               "Downloads use Wi-Fi alone - never mobile data, a hotspot or Low Data Mode."))
        #expect(DownloadWords.over(.any, device: .iPhone) == ("Wi-Fi and cellular", "Downloads use mobile data too, whenever there's no Wi-Fi."))
        let wired = NetworkPath(satisfied: true), tethered = NetworkPath(satisfied: true, expensive: true)
        let cellular = NetworkPath(satisfied: true, cellular: true, expensive: true)
        for setting in DownloadOver.allCases {
            // a cable counts as Wi-Fi, and NetworkPath can't tell the two apart
            #expect(DownloadWords.overNow(.wifiAtHome, setting: setting, device: .mac) == "On Wi-Fi or Ethernet now.")
            #expect(DownloadWords.overNow(wired, setting: setting, device: .mac) == "On Wi-Fi or Ethernet now.")
            #expect(DownloadWords.overNow(.wifiAtHome, setting: setting, device: .iPhone) == "On Wi-Fi now.")
            // a Mac's mobile data is a phone's: said as a hotspot
            let hotspot = DownloadWords.overNow(NetworkPath(satisfied: true, wifi: true, expensive: true), setting: setting, device: .mac)
            #expect(DownloadWords.overNow(tethered, setting: setting, device: .mac) == hotspot)
            #expect(DownloadWords.overNow(cellular, setting: setting, device: .mac) == hotspot)
            #expect(hotspot == DownloadWords.overNow(NetworkPath(satisfied: true, wifi: true, expensive: true), setting: setting,
                                                     device: .iPhone))
            // Low Data Mode and no connection: the phone's
            for path in [NetworkPath(satisfied: true, wifi: true, constrained: true), .none] {
                #expect(DownloadWords.overNow(path, setting: setting, device: .mac)
                        == DownloadWords.overNow(path, setting: setting, device: .iPhone))
            }
        }
        #expect(DownloadWords.overNow(tethered, setting: .wifi, device: .mac) == "On a hotspot now - downloads wait until you're off it.")
        #expect(DownloadWords.overNow(cellular, setting: .wifi, device: .iPhone) == "On mobile data now - downloads wait for Wi-Fi.")
        // the waits that name the setting name it as the Mac does
        #expect(DownloadWords.waitSetting(.wifi, limit: .gb20, device: .mac)
                == "Download over is Wi-Fi or Ethernet only - in Settings > Downloads.")
        #expect(DownloadWords.wait(.wifi, device: .mac) == "Waiting for Wi-Fi or Ethernet")
        #expect(DownloadWords.allWaitForWifi(.mac) == "Downloads wait for Wi-Fi or Ethernet - Download over is set to Wi-Fi or Ethernet only.")
        #expect(DownloadWords.allWaitForWifi(.iPhone) == "Downloads wait for Wi-Fi - Download over is set to Wi-Fi only.")
    }

    @Test func theForceQuitOnAMac() {
        #expect(DownloadWords.forceQuit(.mac) == "Downloads stopped when deadwax was force quit, and carried on when it opened again.")
        #expect(DownloadWords.forceQuit(.iPhone)
                == "Downloads stopped when deadwax was closed from the app switcher, and carried on when it opened again.")
    }

    @Test func aMacClicksWhereAPhoneTaps() {
        let words: [(Device) -> String] = [
            RequestWords.empty, RequestWords.notLookedUp, TagEditWords.selectNote, PlaylistDownloadWords.noneYetHow,
            GettingWords.modeTitle,
            { DebugWords.testSoundsFooter(trial: "", device: $0) },
            { InfoDebug.engineRows(InfoDebug.Engine(lastStartSeconds: 0.306), device: $0).map(\.value).joined() },
        ]
        let tap = #"(?i)\btap(s|ped|ping)?\b"#
        for word in words {
            #expect(word(.iPhone).range(of: tap, options: .regularExpression) != nil, "\(word(.iPhone))")
            #expect(word(.mac).range(of: tap, options: .regularExpression) == nil, "\(word(.mac))")
            #expect(word(.mac).range(of: #"(?i)\bclick\b"#, options: .regularExpression) != nil, "\(word(.mac))")
        }
        #expect(RequestWords.notLookedUp(.mac) == "Couldn't open it - click to try again.")
        #expect(TagEditWords.selectNote(.mac) == "Select tracks to edit only those. Click a track's name to see everything in its file.")
        #expect(GettingWords.modeTitle(.mac) == "When I click Get")
        // People's: whoever was changed may be on a phone, the web or a Mac - so neither a click nor a tap
        #expect(People.savedWords("ethan", device: .mac) == "Saved - ethan has them from the next thing they do in deadwax.")
        #expect(People.savedWords("ethan", device: .iPhone) == "Saved - ethan has them from their next tap.")
        #expect(RequestWords.emptyLine(gets: true, device: .mac).hasSuffix("find one in Search and click Get."))
        #expect(RequestWords.emptyLine(gets: false, device: .mac) == RequestWords.emptyLine(gets: false, device: .iPhone))
    }
}
