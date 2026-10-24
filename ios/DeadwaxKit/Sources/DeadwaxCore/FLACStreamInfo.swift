import Foundation

/// A FLAC file's STREAMINFO block - its rate, bits, channels, length and the MD5 of its decoded
/// audio - read from the first bytes of the file. Phase 0 shows the rate and bits in the Hi-res
/// readout; Phase 2 checks each download's MD5 against it.
public struct FLACStreamInfo: Sendable, Equatable {
    public let minBlockSize: Int
    public let maxBlockSize: Int
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int
    /// 0 when the encoder didn't know.
    public let totalSamples: Int64
    /// 16 bytes; all zero when the encoder didn't compute it.
    public let md5: [UInt8]

    public var duration: Double? {
        totalSamples > 0 && sampleRate > 0 ? Double(totalSamples) / Double(sampleRate) : nil
    }

    /// The STREAMINFO of the FLAC that `data` begins (an ID3v2 tag in front is skipped), or nil when
    /// it isn't a FLAC or not enough of it has arrived (42 bytes after the tag).
    public static func parse(_ data: Data) -> FLACStreamInfo? {
        let bytes = [UInt8](data.prefix(64 * 1024))
        var at = 0
        if bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            // "ID3": a syncsafe size in bytes 6-9, plus the 10-byte header (and 10 more for a footer)
            let size = (Int(bytes[6] & 0x7F) << 21) | (Int(bytes[7] & 0x7F) << 14)
                | (Int(bytes[8] & 0x7F) << 7) | Int(bytes[9] & 0x7F)
            at = 10 + size + ((bytes[5] & 0x10) != 0 ? 10 : 0)
        }
        // "fLaC", then a block header: last-block flag and type (0 = STREAMINFO), a 24-bit length (34)
        guard bytes.count >= at + 8 + 34,
              bytes[at] == 0x66, bytes[at + 1] == 0x4C, bytes[at + 2] == 0x61, bytes[at + 3] == 0x43,
              bytes[at + 4] & 0x7F == 0 else { return nil }
        let length = (Int(bytes[at + 5]) << 16) | (Int(bytes[at + 6]) << 8) | Int(bytes[at + 7])
        guard length >= 34 else { return nil }
        let s = Array(bytes[(at + 8)..<(at + 8 + 34)])
        let minBlock = (Int(s[0]) << 8) | Int(s[1])
        let maxBlock = (Int(s[2]) << 8) | Int(s[3])
        // bytes 10-17: 20 bits of rate, 3 of channels - 1, 5 of bits - 1, 36 of total samples
        let rate = (Int(s[10]) << 12) | (Int(s[11]) << 4) | (Int(s[12]) >> 4)
        let channels = ((Int(s[12]) >> 1) & 0x07) + 1
        let bits = (((Int(s[12]) & 0x01) << 4) | (Int(s[13]) >> 4)) + 1
        var total = Int64(s[13] & 0x0F)
        for byte in s[14...17] { total = (total << 8) | Int64(byte) }
        guard rate > 0 else { return nil }
        return FLACStreamInfo(minBlockSize: minBlock, maxBlockSize: maxBlock, sampleRate: rate,
                              channels: channels, bitsPerSample: bits, totalSamples: total,
                              md5: Array(s[18..<34]))
    }

    public var md5Known: Bool { md5.contains { $0 != 0 } }
}
