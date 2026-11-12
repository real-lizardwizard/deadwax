import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 4: the file read and written back the same, filter ids and the counter kept; a new output Off; a version
/// this build doesn't know, or a file it can't read, refused (set aside, never guessed at).
@Suite struct EQSettingsTests {
    /// 4's own example, its "…" filled in.
    static let example = """
    {
      "version": 1,
      "advanced": false,
      "presets": [{"id": "p-7d1c", "name": "Late night", "gains": [0, 0, 1.5, 0, 0, 0, 0, -1, -2, -3]}],
      "outputs": [
        {
          "key": "bluetooth:60:F8:1D:01", "type": "bluetoothA2DP", "uid": "60:F8:1D:01", "name": "James's AirPods Pro",
          "renamed": null, "seen": "2026-11-12T10:41:00Z", "suggestion": "shown",
          "on": true,
          "correction": {
            "kind": "autoeq", "id": "3f2c9a0d1b7e4c55", "name": "Apple AirPods Pro", "source": "crinacle",
            "rig": "711", "form": "in-ear", "text": "Preamp: -6.0 dB\\nFilter 1: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70\\n", "changed": false,
            "preamp": {"all": -6.0, "left": 0, "right": 0},
            "nextFilterID": 11,
            "filters": [{"id": 1, "kind": "lowShelf", "written": "LSC", "fc": 105, "gain": 2.6, "width": {"q": 0.7},
                         "corner": false, "channel": "all", "on": true},
                        {"id": 7, "kind": "peak", "written": "PK", "fc": 8903, "gain": 6, "width": {"q": 1.66},
                         "corner": false, "channel": "left", "on": false},
                        {"id": 10, "kind": "lowPass", "written": "LP", "fc": 18000, "gain": 0, "width": null,
                         "corner": false, "channel": "all", "on": true}]
          },
          "tone": {"preset": "bassBoost"},
          "preamp": {"automatic": true}
        },
        {
          "key": "speaker", "type": "builtInSpeaker", "uid": "", "name": "iPhone speaker", "renamed": "Phone",
          "seen": "2026-11-11T08:00:00Z", "suggestion": null, "on": false, "correction": null,
          "tone": {"custom": [1, 0, 0, 0, 0, 0, 0, 0, 0, -1.5]}, "preamp": {"automatic": false, "dB": -6.0}
        }
      ]
    }
    """

    @Test func theFileIsReadAndWrittenBackTheSame() throws {
        let settings = try #require(EQSettings.read(Data(Self.example.utf8)))
        #expect(settings.version == 1 && !settings.advanced)
        #expect(settings.presets == [EQYourPreset(id: "p-7d1c", name: "Late night", gains: [0, 0, 1.5, 0, 0, 0, 0, -1, -2, -3])])
        let pods = try #require(settings.output("bluetooth:60:F8:1D:01"))
        #expect(pods.type == .bluetoothA2DP && pods.suggestion == .shown && pods.on && pods.shownName == "James's AirPods Pro")
        let c = try #require(pods.correction)
        #expect(c.kind == .autoeq && c.source == "crinacle" && c.rig == "711" && !c.changed && !c.converted)
        #expect(c.nextFilterID == 11 && c.filters.map(\.id) == [1, 7, 10])
        #expect(c.filters[1] == EQFilter(id: 7, kind: .peak, written: "PK", fc: 8903, gain: 6, width: .q(1.66), channel: .left, on: false))
        #expect(c.filters[2].width == nil && c.preamp == EQPreampParts(all: -6, left: 0, right: 0))
        #expect(pods.tone == .preset("bassBoost") && pods.preamp == .automatic)
        let speaker = try #require(settings.output("speaker"))
        #expect(speaker.shownName == "Phone" && speaker.correction == nil && speaker.suggestion == nil)
        #expect(speaker.tone == .custom([1, 0, 0, 0, 0, 0, 0, 0, 0, -1.5]) && speaker.preamp == .hand(-6))

        //? written and read again: the same, ids and counter kept
        let again = try #require(EQSettings.read(try settings.written()))
        #expect(again == settings)
        #expect(try again.written() == settings.written())
        //? a yours tone, a file correction, a converted one
        var more = settings
        more.outputs[1].tone = .yours("p-7d1c")
        more.outputs[1].correction = EQCorrection(kind: .file, name: "Wavelet.txt", text: "GraphicEQ: 20 1; 20000 1",
                                                  converted: true, nextFilterID: 3,
                                                  filters: [EQFilter(id: 2, kind: .peak, fc: 20, gain: 1, width: .q(4.32))])
        #expect(EQSettings.read(try more.written()) == more)
    }

    @Test func aNewOutputIsOff() {
        let output = EQOutputs.output([EQRoutePort(port: .bluetoothA2DP, portType: "BluetoothA2DPOutput", name: "Sennheiser HD 450BT", uid: "u")])!
        let setting = EQSettings.newOutput(output, seen: "2026-11-12T10:41:00Z")
        #expect(!setting.on && setting.correction == nil && setting.tone == .preset("flat") && setting.preamp == .automatic)
        #expect(setting.key == "bluetooth:u" && setting.type == .bluetoothA2DP && setting.renamed == nil && setting.suggestion == nil)
        let settings = EQSettings(outputs: [setting])
        #expect(settings.bank(setting, rate: 48000, version: 1).isIdentity)
        #expect(EQSettings() == EQSettings(version: 1, advanced: false, presets: [], outputs: []))
    }

    @Test func aFileThisBuildCantReadIsRefused() {
        #expect(EQSettings.read(Data(Self.example.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2").utf8)) == nil)
        #expect(EQSettings.read(Data("{}".utf8)) == nil)
        #expect(EQSettings.read(Data("not json".utf8)) == nil)
        #expect(EQSettings.read(Data(Self.example.replacingOccurrences(of: "\"bluetoothA2DP\"", with: "\"radio\"").utf8)) == nil)
        #expect(EQSettings.read(Data("{\"version\": 1, \"advanced\": false, \"presets\": [], \"outputs\": []}".utf8)) == EQSettings())
        #expect(EQSettings.unreadableName(day: "2026-11-12") == "eq-unreadable-2026-11-12.json")
    }

    @Test func tonesAndBanks() throws {
        var settings = try #require(EQSettings.read(Data(Self.example.utf8)))
        #expect(settings.gains(.preset("bassBoost")) == [5, 4.5, 3, 1, 0, 0, 0, 0, 0, 0])
        #expect(settings.gains(.preset("gone")) == EQGraphic.flat && settings.gains(.yours("gone")) == EQGraphic.flat)
        #expect(settings.gains(.yours("p-7d1c")) == [0, 0, 1.5, 0, 0, 0, 0, -1, -2, -3])
        let pods = settings.outputs[0]
        let bank = settings.bank(pods, rate: 44100, version: 7)
        //? the left ear's peak is off; the low pass and shelf play; Bass Boost's four bands after them
        #expect(bank.left.map(\.id) == [.filter(1), .filter(10), .band(0), .band(1), .band(2), .band(3)])
        #expect(bank.rate == 44100 && bank.version == 7 && bank.key == pods.key && bank.preamp < 0)
        var speaker = settings.outputs[1]
        speaker.on = true
        #expect(settings.bank(speaker, rate: 48000, version: 1).preamp == -6)
        //? deleting a preset an output uses leaves its sliders where they were, as Custom
        settings.outputs[1].tone = .yours("p-7d1c")
        settings.deletePreset("p-7d1c")
        #expect(settings.presets.isEmpty && settings.outputs[1].tone == .custom([0, 0, 1.5, 0, 0, 0, 0, -1, -2, -3]))
    }

    @Test func aPresetsName() throws {
        let settings = try #require(EQSettings.read(Data(Self.example.utf8)))
        #expect(settings.presetName("  Morning  ") == .success("Morning"))
        #expect(settings.presetName("   ") == .failure(.empty))
        #expect(settings.presetName("bass boost") == .failure(.taken("Bass Boost")))
        #expect(settings.presetName("Láte Night") == .failure(.taken("Late night")))
        #expect(settings.presetName("LATE NIGHT", renaming: "p-7d1c") == .success("LATE NIGHT"))
        #expect(settings.presetName(String(repeating: "a", count: 50)) == .success(String(repeating: "a", count: 40)))
    }

    @Test func aCorrectionFromAFile() throws {
        guard case .success(let reading) = EQFixtures.read("Preamp: -3 dB\nFilter: ON PK Fc 100 Hz Gain 2 dB Q 1\nFilter: ON PK Fc 200 Hz Gain 2 dB Q 1") else {
            Issue.record("refused")
            return
        }
        let c = EQCorrection.file(name: "HD650.txt", text: "…", reading: reading)
        #expect(c.kind == .file && c.filters.map(\.id) == [1, 2] && c.nextFilterID == 3 && !c.converted)
        #expect(c.preamp == EQPreampParts(all: -3, left: 0, right: 0))
        guard case .success(let graphic) = EQFixtures.read("GraphicEQ: 20 0; 1000 4; 20000 0") else { return }
        #expect(EQCorrection.file(name: "Wavelet.txt", text: "", reading: graphic).converted)
    }
}
