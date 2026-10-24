import Foundation

/// How a song is asked for: `raw`, the file as it is, whenever iOS can decode it - and `mp3`,
/// Navidrome's transcode, only for what it can't (Ogg Vorbis and Opus, WMA), as the web app's
/// streamFormat does. "As it is" is asked for by name: Navidrome answers format=raw before anything
/// set on its Players page, so the bytes are the file.
public enum StreamFormat {
    static let undecodable: Set<String> = ["ogg", "oga", "opus", "wma"]
    static let undecodableTypes: Set<String> = ["audio/ogg", "audio/opus", "audio/x-ms-wma"]

    public static func format(for song: Song) -> String {
        if let suffix = song.suffix?.lowercased(), undecodable.contains(suffix) { return "mp3" }
        if let type = song.contentType?.lowercased(), undecodableTypes.contains(type) { return "mp3" }
        return "raw"
    }

    /// The file's suffix as it will arrive: the song's own when sent as it is, `mp3` for a transcode.
    public static func suffix(for song: Song) -> String {
        format(for: song) == "mp3" ? "mp3" : (song.suffix?.lowercased() ?? "bin")
    }
}

/// Rates and the Hi-res readout, in words.
public enum RateWords {
    /// 44100 -> "44.1 kHz", 192000 -> "192 kHz".
    public static func kHz(_ rate: Double) -> String {
        let k = rate / 1000
        let rounded = (k * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) kHz" }
        return String(format: "%.1f kHz", rounded)
    }

    /// "24-bit 192 kHz FLAC file -> 48 kHz output". Bits and the codec when known. When the two
    /// rates differ, the app's audio engine (its main mixer) converts the file's rate to the
    /// output's - as any app must for an output at 48 kHz, which an iPhone's own outputs and AirPods
    /// run at or under; this says so rather than hiding it.
    public static func readout(fileRate: Double, bits: Int?, codec: String?, outputRate: Double?) -> String {
        var file = ""
        if let bits, bits > 0 { file += "\(bits)-bit " }
        file += kHz(fileRate)
        if let codec, !codec.isEmpty { file += " \(codec.uppercased())" }
        file += " file"
        guard let outputRate, outputRate > 0 else { return file }
        if abs(outputRate - fileRate) < 0.5 {
            return "\(file) \u{2192} \(kHz(outputRate)) output, no rate conversion"
        }
        return "\(file) \u{2192} \(kHz(outputRate)) output"
    }
}

/// Names on the phone's disk for what deadwax sends.
public enum LocalFiles {
    /// `<id>.<suffix>`, both kept to safe characters so an id can never name a path elsewhere.
    /// Nil for an id with nothing usable in it.
    public static func name(songID: String, suffix: String?) -> String? {
        let id = String(songID.unicodeScalars.filter { safe($0) }.map(Character.init))
        guard !id.isEmpty, id.count <= 128 else { return nil }
        let cleaned = String((suffix ?? "").lowercased().unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }.map(Character.init).prefix(10))
        return "\(id).\(cleaned.isEmpty ? "bin" : cleaned)"
    }

    static func safe(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
            || scalar == "-" || scalar == "_"
    }

    /// Whether a finished download's length is the song's: Navidrome's `size`, when it says one.
    public static func lengthMatches(_ length: Int64, song: Song) -> Bool {
        guard let size = song.size, size > 0 else { return length > 0 }
        return length == size
    }
}
