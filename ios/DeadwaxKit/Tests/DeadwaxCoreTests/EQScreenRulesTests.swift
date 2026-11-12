import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.2-3.6, 3.12-3.14 and 8's question 30 (slice 3, the simple face): which output a page shows and when it may
/// switch, a change while Off turning the EQ on, the short setting, Other outputs' order, the line under the curve, a
/// slider's drag and steps, and Info's and Debug's rows.
@Suite struct EQScreenRulesTests {
    static let airpods = EQOutputs.output(EQRoutePort(port: .bluetoothA2DP, portType: "BluetoothA2DPOutput",
                                                      name: "James's AirPods Pro", uid: "60:F8:1D:01-tacl"))
    static let car = EQOutputs.output(EQRoutePort(port: .carAudio, portType: "CarAudio", name: "Golf", uid: "car-1"))
    static let kitchen = EQOutputs.output(EQRoutePort(port: .airPlay, portType: "AirPlay", name: "Kitchen", uid: "ap-1"))
    static let speaker = EQOutputs.speaker

    // MARK: which output a page shows (3.2; 8, question 30)

    /// The EQ page opened from You or the •••: on top and with no finger down, it follows the route at once.
    @Test func theEQPageFollowsTheRoute() {
        var page = EQPage.now(route: Self.speaker.key)
        #expect(page.output == "speaker" && page.connected && page.maySwitch)
        #expect(page.heard(route: Self.airpods.key) == true)
        #expect(page.output == Self.airpods.key && page.connected)
        //? the same route again is no switch
        #expect(page.heard(route: Self.airpods.key) == false)
        //? a route with no output leaves the last one standing
        #expect(page.heard(route: nil) == false)
        #expect(page.output == Self.airpods.key)
    }

    /// Covered (a page pushed over it, an alert, another tab), it keeps its output - and switches when shown again.
    @Test func onlyWhileOnTop() {
        var page = EQPage.now(route: Self.speaker.key)
        page.covered()
        #expect(!page.maySwitch)
        #expect(page.heard(route: Self.airpods.key) == false)
        #expect(page.output == "speaker" && !page.connected)
        #expect(page.shown() == true)
        #expect(page.output == Self.airpods.key && page.connected)
        //? shown again with nothing changed: no switch, no announcement
        page.covered()
        #expect(page.shown() == false)
    }

    /// Never under a finger: the page keeps the output it began on while a slider is held, and switches as it lets go
    /// (two fingers: the last one up).
    @Test func neverUnderAFinger() {
        var page = EQPage.now(route: Self.speaker.key)
        page.hold()
        #expect(page.heard(route: Self.airpods.key) == false)
        #expect(page.output == "speaker")
        page.hold()
        #expect(page.release() == false)
        #expect(page.output == "speaker")
        #expect(page.release() == true)
        #expect(page.output == Self.airpods.key)
        //? a release with nothing held is harmless
        #expect(page.release() == false)
        #expect(page.held == 0)
    }

    /// The mutation 5.3 names: every page pushed from an EQ page is bound to the output it was opened for, and stays so
    /// - on top, with no finger down, shown again, the route moving away and back. "Use for James's AirPods Pro" must
    /// do what it says, whatever connects while you read.
    @Test func aPushedPageStaysOnItsOutput() {
        var pushed = EQPage.pushed(Self.airpods.key, route: Self.airpods.key)
        #expect(pushed.connected && !pushed.maySwitch)
        #expect(pushed.heard(route: Self.speaker.key) == false)
        #expect(pushed.output == Self.airpods.key && !pushed.connected)
        pushed.covered()
        #expect(pushed.shown() == false)
        pushed.hold()
        #expect(pushed.release() == false)
        #expect(pushed.output == Self.airpods.key)
        #expect(EQScreenRules.goneLine(pushed, name: "James's AirPods Pro")
                == "James's AirPods Pro isn't connected: changes are kept for when it is.")
        //? the AirPods back: connected again, and the line goes
        #expect(pushed.heard(route: Self.airpods.key) == false)
        #expect(pushed.connected && EQScreenRules.goneLine(pushed, name: "x") == nil)
    }

    /// A page opened from Other outputs stays on its output too - and says "Not connected" its own way, with no
    /// pushed page's line.
    @Test func anOutputsOwnPageStaysOnIt() {
        var page = EQPage.of(Self.car.key, route: Self.airpods.key)
        #expect(!page.connected && !page.maySwitch)
        #expect(page.heard(route: Self.speaker.key) == false)
        #expect(page.shown() == false)
        #expect(page.output == Self.car.key)
        #expect(EQScreenRules.goneLine(page, name: "Golf") == nil)
        //? the car connecting makes it the connected page: Other outputs shows, Forget goes
        #expect(page.heard(route: Self.car.key) == false)
        #expect(page.connected && EQScreenRules.showsOthers(page))
        #expect(!EQScreenRules.forgets(page, met: true))
    }

    /// Other outputs only on the connected page; Forget This Output only on a page not connected, of an output met,
    /// never the speaker's.
    @Test func whatEachPageHolds() {
        let now = EQPage.now(route: Self.airpods.key)
        #expect(EQScreenRules.showsOthers(now) && !EQScreenRules.forgets(now, met: true))
        let car = EQPage.of(Self.car.key, route: Self.airpods.key)
        #expect(!EQScreenRules.showsOthers(car))
        #expect(EQScreenRules.forgets(car, met: true))
        #expect(!EQScreenRules.forgets(car, met: false))
        let speaker = EQPage.of(Self.speaker.key, route: Self.airpods.key)
        #expect(!EQScreenRules.forgets(speaker, met: true))
        #expect(EQScreenRules.forgets(Self.car.key) && !EQScreenRules.forgets(Self.speaker.key))
    }

    // MARK: changes (3.2, 3.5, 3.6)

    /// "While Off, every control still works, and any change turns the EQ on" (8, question 9) - and says so, once.
    @Test func aChangeWhileOffTurnsItOn() {
        var s = EQSettings()
        s.met(Self.airpods, at: "2026-11-12T10:00:00Z")
        #expect(s.output(Self.airpods.key)?.on == false)
        #expect(s.setBand(2, to: 3.2, for: Self.airpods) == true)
        let after = s.output(Self.airpods.key)!
        #expect(after.on && after.tone == .custom([0, 0, 3, 0, 0, 0, 0, 0, 0, 0]))
        //? already on: no second "EQ on"
        #expect(s.setBand(2, to: 4, for: Self.airpods) == false)
        //? the band already there changes nothing, and turns nothing on
        s.setOn(false, for: Self.airpods)
        #expect(s.setBand(2, to: 4, for: Self.airpods) == false)
        #expect(s.output(Self.airpods.key)?.on == false)
        //? a preset chosen is the EQ on, even the one it already has (Apple Music's way)
        #expect(s.choose(.custom([0, 0, 4, 0, 0, 0, 0, 0, 0, 0]), for: Self.airpods) == true)
        #expect(s.output(Self.airpods.key)?.on == true)
        s.setOn(false, for: Self.airpods)
        #expect(s.choose(.preset("bassBoost"), for: Self.airpods) == true)
        #expect(s.output(Self.airpods.key)?.tone == .preset("bassBoost"))
        //? the switch itself turns it off and on, and is no "change"
        s.setOn(false, for: Self.airpods)
        #expect(s.output(Self.airpods.key)?.on == false)
    }

    /// A change to an output never met gives it its setting first (Off, Flat) - then turns it on.
    @Test func aChangeToAnOutputNeverMet() {
        var s = EQSettings()
        #expect(s.setting(for: Self.car) == EQSettings.newOutput(Self.car, seen: ""))
        #expect(s.setBand(9, to: -2, for: Self.car) == true)
        #expect(s.outputs.count == 1 && s.output(Self.car.key)?.on == true)
        #expect(s.gains(s.output(Self.car.key)!.tone)[9] == -2)
    }

    /// A slider's value is snapped to 0.5 dB inside ±12, and moving one makes the tone Custom from where a preset was.
    @Test func aSliderMakesTheToneCustom() {
        var s = EQSettings()
        s.choose(.preset("bassBoost"), for: Self.airpods)
        s.setBand(5, to: 13.7, for: Self.airpods)
        #expect(s.output(Self.airpods.key)?.tone == .custom([5, 4.5, 3, 1, 0, 12, 0, 0, 0, 0]))
        s.setBand(0, to: 1.26, for: Self.airpods)
        #expect(s.gains(s.output(Self.airpods.key)!.tone)[0] == 1.5)
        //? a band that isn't one changes nothing
        #expect(s.setBand(10, to: 3, for: Self.airpods) == false)
    }

    @Test func theRouteMet() {
        var s = EQSettings()
        #expect(s.met(Self.airpods, at: "2026-11-12T10:00:00Z") == true)
        s.rename(Self.airpods.key, to: "  Pods  ")
        var renamed = Self.airpods
        renamed.name = "James's AirPods Pro (2)"
        #expect(s.met(renamed, at: "2026-11-12T11:00:00Z") == false)
        let o = s.output(Self.airpods.key)!
        #expect(o.seen == "2026-11-12T11:00:00Z" && o.name == "James's AirPods Pro (2)" && o.renamed == "Pods")
        #expect(o.shownName == "Pods" && !o.on)
    }

    /// Rename: trimmed; empty, or iOS's own name, puts iOS's back.
    @Test func rename() {
        var s = EQSettings()
        s.met(Self.airpods, at: "")
        s.rename(Self.airpods.key, to: " My buds ")
        #expect(s.output(Self.airpods.key)?.shownName == "My buds")
        s.rename(Self.airpods.key, to: "   ")
        #expect(s.output(Self.airpods.key)?.renamed == nil)
        s.rename(Self.airpods.key, to: "James's AirPods Pro")
        #expect(s.output(Self.airpods.key)?.renamed == nil)
        //? an output never met has nothing to rename
        s.rename(Self.car.key, to: "Golf")
        #expect(s.output(Self.car.key) == nil)
    }

    /// Forget: its setting deleted, met again Off - never the speaker.
    @Test func forget() {
        var s = EQSettings()
        s.met(Self.speaker, at: "")
        s.choose(.preset("vocal"), for: Self.car)
        s.forget(Self.car.key)
        #expect(s.output(Self.car.key) == nil)
        s.met(Self.car, at: "x")
        #expect(s.output(Self.car.key)?.on == false && s.output(Self.car.key)?.tone == .preset("flat"))
        s.choose(.preset("vocal"), for: Self.speaker)
        s.forget(Self.speaker.key)
        #expect(s.output(Self.speaker.key)?.tone == .preset("vocal"))
    }

    /// Save as Preset: the sliders kept under your name, and the output's tone that preset (same gains, same sound);
    /// a name's problem comes back. Rename Preset the same, its own name aside; Delete leaves users Custom.
    @Test func yourPresets() {
        var s = EQSettings()
        s.setBand(0, to: 4, for: Self.airpods)
        #expect(s.savePreset("  ", id: "p1", from: Self.airpods) == .empty)
        #expect(s.savePreset("bass boost", id: "p1", from: Self.airpods) == .taken("Bass Boost"))
        #expect(s.presets.isEmpty)
        let before = s.bank(s.output(Self.airpods.key)!, rate: 48_000, version: 1)
        #expect(s.savePreset("Mine", id: "p1", from: Self.airpods) == nil)
        #expect(s.presets == [EQYourPreset(id: "p1", name: "Mine", gains: [4, 0, 0, 0, 0, 0, 0, 0, 0, 0])])
        #expect(s.output(Self.airpods.key)?.tone == .yours("p1"))
        #expect(s.bank(s.output(Self.airpods.key)!, rate: 48_000, version: 1) == before)
        #expect(EQWords.shortSetting(s.output(Self.airpods.key)!, in: s) == "Mine")
        _ = s.savePreset("Other", id: "p2", from: Self.airpods)
        #expect(s.renamePreset("p1", to: "other") == .taken("Other"))
        #expect(s.renamePreset("p1", to: "MINE") == nil)
        #expect(s.presets[0].name == "MINE")
        #expect(s.renamePreset("gone", to: "x") == nil)
        s.deletePreset("p2")
        #expect(s.output(Self.airpods.key)?.tone == .custom([4, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    }

    // MARK: what the screens say (3.1, 3.3, 3.12, 3.13)

    @Test func theShortSettingAndTheOutputNow() {
        var s = EQSettings()
        #expect(EQScreenRules.now(s, route: Self.airpods) == ("James's AirPods Pro", "Off"))
        s.setOn(true, for: Self.airpods)
        #expect(EQScreenRules.now(s, route: Self.airpods).short == "Flat")
        s.choose(.preset("bassBoost"), for: Self.airpods)
        #expect(EQScreenRules.now(s, route: Self.airpods).short == "Bass Boost")
        s.setBand(9, to: 1, for: Self.airpods)
        #expect(EQScreenRules.now(s, route: Self.airpods).short == "Custom")
        s.rename(Self.airpods.key, to: "Pods")
        #expect(EQScreenRules.now(s, route: Self.airpods).name == "Pods")
    }

    /// Other outputs: every other output met, the most recent first, ties by name; the speaker always there (last when
    /// never met); never the page's own.
    @Test func otherOutputsOrder() {
        var s = EQSettings()
        s.met(Self.airpods, at: "2026-11-12T10:00:00Z")
        s.met(Self.car, at: "2026-11-10T08:00:00Z")
        s.met(Self.kitchen, at: "2026-11-12T10:00:00Z")
        let others = EQScreenRules.others(s, shown: Self.airpods.key).map(\.key)
        #expect(others == [Self.kitchen.key, Self.car.key, "speaker"])
        //? the AirPods and the Kitchen were last the output at the same moment: by name, "James's…" before "Kitchen"
        let fromCar = EQScreenRules.others(s, shown: Self.car.key).map(\.key)
        #expect(fromCar == [Self.airpods.key, Self.kitchen.key, "speaker"])
        //? the speaker met takes its place by when
        s.met(Self.speaker, at: "2026-11-11T00:00:00Z")
        #expect(EQScreenRules.others(s, shown: Self.airpods.key).map(\.key) == [Self.kitchen.key, "speaker", Self.car.key])
        //? on the speaker's own page, no speaker
        #expect(!EQScreenRules.others(s, shown: "speaker").contains { $0.key == "speaker" })
        //? a rename sorts by the name shown
        s.rename(Self.kitchen.key, to: "Attic")
        #expect(EQScreenRules.others(s, shown: Self.car.key).map(\.key).prefix(2) == [Self.kitchen.key, Self.airpods.key])
    }

    /// The line under the curve, state by state (3.3).
    @Test func theLineUnderTheCurve() {
        typealias R = EQScreenRules
        #expect(R.line(on: false, identity: true, preamp: .automatic, played: 0, top: 0, unitNotMade: false)
                == EQLine("Off: nothing changes the sound."))
        #expect(R.line(on: true, identity: true, preamp: .automatic, played: 0, top: 0, unitNotMade: false)
                == EQLine("Flat: nothing changes the sound yet."))
        #expect(R.line(on: true, identity: false, preamp: .automatic, played: -4.2, top: 4.2, unitNotMade: false)
                == EQLine("Preamp -4.2 dB, so loud songs don't clip."))
        #expect(R.line(on: true, identity: false, preamp: .hand(-6), played: -6, top: 5, unitNotMade: false)
                == EQLine("Preamp -6.0 dB, set by you."))
        #expect(R.line(on: true, identity: false, preamp: .hand(-3.6), played: -3.6, top: 6, unitNotMade: false)
                == EQLine("Loud songs may clip: the curve boosts 2.4 dB more than this preamp takes away.", .amber))
        //? the unit not made says so before anything - Off included
        #expect(R.line(on: false, identity: true, preamp: .automatic, played: 0, top: 0, unitNotMade: true).tone == .danger)
    }

    @Test func infoRows() {
        var s = EQSettings()
        s.met(Self.airpods, at: "")
        #expect(EQScreenRules.infoSound(s.output(Self.airpods.key)!, in: s, preamp: 0) == nil)
        s.choose(.preset("bassBoost"), for: Self.airpods)
        #expect(EQScreenRules.infoSound(s.output(Self.airpods.key)!, in: s, preamp: -6.1)
                == "Bass Boost on James's AirPods Pro, preamp -6.1 dB")
        s.choose(.preset("bassReduce"), for: Self.airpods)
        #expect(EQScreenRules.infoSound(s.output(Self.airpods.key)!, in: s, preamp: 0) == "Bass Reduce on James's AirPods Pro")
        #expect(EQScreenRules.infoDebug(nil) == nil)
        #expect(EQScreenRules.infoDebug(.passing) == "Off: every sample passed through untouched")
        #expect(EQScreenRules.infoDebug(.filtering(sections: 20, rate: 48_000, preamp: -6.4))
                == "Filtering: 20 filters at 48 kHz, preamp -6.4 dB")
        #expect(EQScreenRules.infoDebug(.crossfading) == "Changing: crossfading to the new curve")
        //? Debug's Sent to this device: EQ after the engine's rows
        let rows = InfoDebug.engineRows(InfoDebug.Engine(outputRate: 48_000, lastStartSeconds: 0.2, eq: "Off: every sample passed through untouched"))
        #expect(rows.map(\.label) == ["Output", "Last start", "EQ"])
        #expect(InfoDebug.engineRows(InfoDebug.Engine(outputRate: 48_000)).map(\.label) == ["Output"])
    }

    /// The ••• button's name gains ", EQ", always last (3.13).
    @Test func theMoreButtonsName() {
        #expect(NowPlayingWords.more(hasAlbum: true, download: true, eq: true) == "More: info, go to album, download, EQ")
        #expect(NowPlayingWords.more(hasAlbum: false, eq: true) == "More: info, EQ")
        #expect(NowPlayingWords.more(hasAlbum: true) == "More: info, go to album")
    }

    /// Debug's rows in 3.13's order, the settings' rows put among the unit's.
    @Test func debugRowsOrder() {
        let unit: [(label: String, value: String)] = [("Unit", "In the graph: filtering"), ("Render block", "iOS asked for it once"),
                                                      ("At this rate", "48 kHz: 10 sections a channel"), ("Changes", "c"),
                                                      ("Started with", "bluetooth:x's curve"), ("Over full scale", "o"),
                                                      ("Render", "r")]
        let rows = EQScreenRules.debugRows(unit: unit, output: "Bluetooth (A2DP) · Pods · x", key: "bluetooth:x",
                                           curve: "No filters", atRate: "48 kHz: 10 sections a channel; 1 left out",
                                           startedWith: "Pods's curve", start: "0.031 ms", kept: "eq.json")
        #expect(rows.map(\.label) == ["Output", "Key", "Unit", "Render block", "Curve", "At this rate", "Changes",
                                      "Started with", "Start took", "Over full scale", "Render", "Kept"])
        #expect(rows[5].value.hasSuffix("1 left out") && rows[7].value == "Pods's curve")
        //? before anything played: the unit's one row, then Curve and Kept
        let early = EQScreenRules.debugRows(unit: [("Unit", "No audio engine yet")], output: nil, key: nil, curve: "Off",
                                            atRate: nil, startedWith: nil, start: nil, kept: nil)
        #expect(early.map(\.label) == ["Unit", "Curve"])
    }

    @Test func debugsCurve() {
        var s = EQSettings()
        s.met(Self.airpods, at: "")
        #expect(EQScreenRules.debugCurve(s.output(Self.airpods.key)!, in: s, rate: 48_000) == "Off")
        s.choose(.preset("bassBoost"), for: Self.airpods)
        let words = EQScreenRules.debugCurve(s.output(Self.airpods.key)!, in: s, rate: 48_000)
        #expect(words.hasPrefix("4 tone bands; its top +6.0 dB at "))
        #expect(words.hasSuffix("preamp -6.1 dB (automatic)"))
        #expect(EQScreenRules.debugAtRate(s.output(Self.airpods.key)!, in: s, rate: 48_000, sections: 4)
                == "48 kHz: 4 sections a channel")
    }

    // MARK: the sliders (3.5, 3.14, 3.15)

    @Test func aDrag() {
        typealias S = EQSliderRules
        //? 24 dB over 200 pt: up 25 pt from 0 is +3 dB, rounded to 0.5
        #expect(S.value(from: 0, dy: -25) == 3)
        #expect(S.value(from: 0, dy: -26) == 3)
        #expect(S.value(from: 2, dy: 100) == -10)
        //? held to the range
        #expect(S.value(from: 10, dy: -100) == 12)
        #expect(S.value(from: -10, dy: 500) == -12)
        //? 6 pt up or down before the knob moves
        #expect(!S.engaged(dy: 5.9) && S.engaged(dy: -6) && S.engaged(dy: 6))
        //? the tick: into 0, not staying there
        #expect(S.ticks(from: 0.5, to: 0) && S.ticks(from: -0.5, to: 0) && !S.ticks(from: 0, to: 0) && !S.ticks(from: 0, to: 0.5))
        //? the knob's place: +12 at the top, 0 in the middle, -12 at the foot
        #expect(S.place(12) == 0 && S.place(0) == 0.5 && S.place(-12) == 1 && S.place(30) == 0)
        //? VoiceOver's swipe: 1 dB; a stepper row's 0.5; inside the range
        #expect(S.adjusted(3.5, up: true) == 4.5 && S.adjusted(-11.5, up: false) == -12)
        #expect(S.adjusted(0, up: false, step: 0.5) == -0.5)
    }

    @Test func theBandsWords() {
        #expect(EQWords.Tone.bandSaid(0) == "31 hertz" && EQWords.Tone.bandSaid(5) == "1 kilohertz")
        #expect(EQWords.Tone.bandSaid(9) == "16 kilohertz")
        #expect((0..<10).map(EQWords.Tone.bandLabel) == ["31 Hz", "63 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz",
                                                         "4 kHz", "8 kHz", "16 kHz"])
        #expect(EQWords.Screen.more == "More for this output")
        #expect(EQWords.Debug.startTook(ms: 0.0312, ready: true, rate: 48_000) == "0.031 ms, its curve made ahead")
        #expect(EQWords.Debug.startTook(ms: 1.9, ready: false, rate: 44_100) == "1.90 ms, its curve made then, for 44.1 kHz")
    }
}
