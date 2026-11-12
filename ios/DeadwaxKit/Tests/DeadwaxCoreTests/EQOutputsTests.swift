import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.12 and 3.7: what an output is - its key, name and symbol for each kind of port, several AirPlay outputs as
/// one - and what AutoEq is asked for it.
@Suite struct EQOutputsTests {
    static func port(_ p: EQPort, _ name: String, _ uid: String, type: String = "") -> EQRoutePort {
        EQRoutePort(port: p, portType: type, name: name, uid: uid)
    }

    @Test func theTable() {
        let rows: [(EQRoutePort, String, String, String)] = [
            (Self.port(.builtInSpeaker, "Speaker", "Built-In Speaker"), "speaker", "iPhone speaker", "iphone"),
            (Self.port(.headphones, "Headphones", "Wired Headphones"), "wired", "Headphones", "headphones"),
            (Self.port(.bluetoothA2DP, "James's AirPods Pro", "60:F8:1D:01-tacl"), "bluetooth:60:F8:1D:01-tacl",
             "James's AirPods Pro", "airpodspro"),
            (Self.port(.bluetoothLE, "James's AirPods Max", "60:F8:1D:02"), "bluetooth:60:F8:1D:02", "James's AirPods Max",
             "airpodsmax"),
            (Self.port(.bluetoothA2DP, "AirPods", "a"), "bluetooth:a", "AirPods", "airpods"),
            (Self.port(.bluetoothA2DP, "Beats Studio Pro", "b"), "bluetooth:b", "Beats Studio Pro", "beats.headphones"),
            (Self.port(.bluetoothA2DP, "Sennheiser HD 450BT", "c"), "bluetooth:c", "Sennheiser HD 450BT", "headphones"),
            (Self.port(.usbAudio, "FiiO KA3", "usb-1"), "usb:usb-1", "FiiO KA3", "cable.connector"),
            (Self.port(.carAudio, "Golf", "car-1"), "car:car-1", "Golf", "car"),
            (Self.port(.airPlay, "Kitchen", "ap-1"), "airplay:ap-1", "Kitchen", "airplayaudio"),
            (Self.port(.hdmi, "LG TV", "h-1"), "hdmi:h-1", "LG TV", "tv"),
            (Self.port(.lineOut, "Dock", "l-1"), "line:l-1", "Dock", "cable.connector"),
            (Self.port(.other, "Something", "o-1", type: "Receiver"), "other:Receiver:o-1", "Something", "speaker.wave.2"),
        ]
        for (p, key, name, symbol) in rows {
            let o = EQOutputs.output([p])!
            #expect(o.key == key && o.name == name && o.symbol == symbol, "\(p.port)")
            #expect(o.port == p.port && o.uid == p.uid)
        }
        #expect(EQOutputs.output([]) == nil)
        #expect(EQOutputs.speaker == EQOutputs.output([Self.port(.builtInSpeaker, "Speaker", "")])!.withPortType("Speaker"))
    }

    @Test func severalAirPlayOutputsAreOne() {
        let o = EQOutputs.output([Self.port(.airPlay, "Living Room", "B-2"), Self.port(.airPlay, "Kitchen", "A-1")])!
        #expect(o.key == "airplay:A-1+B-2" && o.name == "Kitchen + Living Room" && o.symbol == "airplayaudio")
        #expect(o.isAirPlay && !o.isHeadphones && !o.offersSuggestion)
        //? the same rooms in either order are the same output
        let again = EQOutputs.output([Self.port(.airPlay, "Kitchen", "A-1"), Self.port(.airPlay, "Living Room", "B-2")])!
        #expect(again.key == o.key)
        //? anything else with several ports is its first
        let mixed = EQOutputs.output([Self.port(.usbAudio, "DAC", "u"), Self.port(.airPlay, "Kitchen", "A-1")])!
        #expect(mixed.key == "usb:u")
    }

    @Test func headphonesAndTheSuggestion() {
        for p in EQPort.allCases {
            let o = EQOutputs.output(Self.port(p, "x", "1"))
            #expect(o.isHeadphones == [.bluetoothA2DP, .bluetoothLE, .headphones, .usbAudio].contains(p), "\(p)")
            #expect(o.offersSuggestion == [.bluetoothA2DP, .bluetoothLE, .usbAudio].contains(p), "\(p)")
        }
    }

    @Test func theSuggestionsQuery() {
        let curly = String(Character(Unicode.Scalar(0x2019)!))
        #expect(EQOutputs.suggestionQuery("James's AirPods Pro") == "AirPods Pro")
        #expect(EQOutputs.suggestionQuery("James\(curly)s AirPods Pro") == "AirPods Pro")
        #expect(EQOutputs.suggestionQuery("Sennheiser HD 650") == "Sennheiser HD 650")
        #expect(EQOutputs.suggestionQuery("  JBL   Flip 6 ") == "JBL Flip 6")
        #expect(EQOutputs.suggestionQuery("James's") == "James's")
        let rows = ["Apple AirPods Pro", "Apple AirPods Pro 2 (ANC mode)", "Apple AirPods Pro 2 (transparency mode)",
                    "Apple AirPods Max", "Sennheiser HD 650", "Sennheiser HD 6XX"]
        //? several: a choice, never the first picked
        #expect(EQOutputs.suggested("AirPods Pro", rows: rows) == [0, 1, 2])
        #expect(EQOutputs.suggested("Sennheiser HD 650", rows: rows) == [4])
        #expect(EQOutputs.suggested("airpods max", rows: rows) == [3])
        #expect(EQOutputs.suggested("JBL Flip 6", rows: rows).isEmpty)
        #expect(EQOutputs.suggested("", rows: rows).isEmpty)
    }
}

extension EQOutput {
    func withPortType(_ t: String) -> EQOutput {
        var o = self
        o.portType = t
        return o
    }
}
