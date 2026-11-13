import Foundation

/// The kinds of output iOS names (`AVAudioSession.Port`), as eq.md 3.12 tells them apart - deadwax's names for them,
/// so Core and the settings file need nothing from AVFoundation (the app maps each `AVAudioSession.Port` to one).
public enum EQPort: String, Codable, Sendable, CaseIterable {
    case builtInSpeaker, headphones, bluetoothA2DP, bluetoothLE, usbAudio, carAudio, airPlay, hdmi, lineOut, other
}

/// One port of the route as iOS gives it: its kind, iOS's own port type (for `other`'s key and Debug), its
/// `portName` and its `uid`.
public struct EQRoutePort: Equatable, Sendable {
    public var port: EQPort
    public var portType: String
    public var name: String
    public var uid: String

    public init(port: EQPort, portType: String, name: String, uid: String) {
        self.port = port
        self.portType = portType
        self.name = name
        self.uid = uid
    }
}

/// An output: what each keeps its own EQ under (3.12).
public struct EQOutput: Equatable, Sendable {
    public var key: String
    public var port: EQPort
    /// iOS's port type, raw
    public var portType: String
    /// the UID as iOS gives it (several AirPlay outputs' joined by +)
    public var uid: String
    /// the name iOS gives it ("iPhone speaker", "Headphones", or its `portName`)
    public var name: String
    /// its SF Symbol
    public var symbol: String

    /// Headphones (Bluetooth, wired, USB) - the Correction footer's "these headphones".
    public var isHeadphones: Bool {
        [.bluetoothA2DP, .bluetoothLE, .headphones, .usbAudio].contains(port)
    }

    /// Bluetooth and USB, which AutoEq's suggestion is offered for (8, question 20).
    public var offersSuggestion: Bool { [.bluetoothA2DP, .bluetoothLE, .usbAudio].contains(port) }

    public var isAirPlay: Bool { port == .airPlay }
}

public enum EQOutputs {
    /// The speaker: always there, met or not.
    public static let speaker = EQOutput(key: "speaker", port: .builtInSpeaker, portType: "Speaker", uid: "",
                                         name: "iPhone speaker", symbol: "iphone")

    /// The output a route is (3.12's table): several AirPlay outputs at once (multi-room) are one, keyed by their
    /// UIDs sorted; anything else with several ports is its first. Nil for a route with none.
    public static func output(_ ports: [EQRoutePort]) -> EQOutput? {
        guard let first = ports.first else { return nil }
        if ports.count > 1 && ports.allSatisfy({ $0.port == .airPlay }) {
            let sorted = ports.sorted { $0.uid < $1.uid }
            let uids = sorted.map(\.uid).joined(separator: "+")
            return EQOutput(key: "airplay:" + uids, port: .airPlay, portType: first.portType, uid: uids,
                            name: sorted.map(\.name).joined(separator: " + "), symbol: "airplayaudio")
        }
        return output(first)
    }

    public static func output(_ p: EQRoutePort) -> EQOutput {
        func made(_ key: String, _ name: String, _ symbol: String) -> EQOutput {
            EQOutput(key: key, port: p.port, portType: p.portType, uid: p.uid, name: name, symbol: symbol)
        }
        switch p.port {
        case .builtInSpeaker: return made("speaker", "iPhone speaker", "iphone")
        case .headphones: return made("wired", "Headphones", "headphones")
        case .bluetoothA2DP, .bluetoothLE: return made("bluetooth:" + p.uid, p.name, symbol(bluetooth: p.name))
        case .usbAudio: return made("usb:" + p.uid, p.name, "cable.connector")
        case .carAudio: return made("car:" + p.uid, p.name, "car")
        case .airPlay: return made("airplay:" + p.uid, p.name, "airplayaudio")
        case .hdmi: return made("hdmi:" + p.uid, p.name, "tv")
        case .lineOut: return made("line:" + p.uid, p.name, "cable.connector")
        case .other: return made("other:\(p.portType):\(p.uid)", p.name, "speaker.wave.2")
        }
    }

    /// A Bluetooth output's symbol, by its name.
    static func symbol(bluetooth name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// What AutoEq is asked for an output (3.7): an owner's "James's " or "James’s " taken off the front, then its
    /// words - "James's AirPods Pro" asks "AirPods Pro".
    public static func suggestionQuery(_ name: String) -> String {
        var words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let curly = String(Character(Unicode.Scalar(0x2019)!)) + "s"
        if words.count > 1, words[0].hasSuffix("'s") || words[0].hasSuffix(curly) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// The rows whose names hold every word of the query, as whole words, folded (3.7) - EQSuggestion's own test,
    /// which says what is offered from them.
    public static func suggested(_ query: String, rows: [String]) -> [Int] {
        rows.indices.filter { (i: Int) -> Bool in EQSuggestion.holdsEveryWord(query, rows[i]) }
    }
}
