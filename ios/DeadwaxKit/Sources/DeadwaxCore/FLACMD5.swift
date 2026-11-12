import Foundation

/// MD5 (RFC 1321), in plain Swift - Linux has no CryptoKit, and the check must be the same everywhere (spec 8.4). Fed a
/// piece at a time; `finish()` gives the 16 bytes. Used only to compare a FLAC's decoded sound with the MD5 its
/// STREAMINFO carries, never for anything that needs a secure hash.
public struct MD5: Sendable {
    private var a0: UInt32 = 0x6745_2301
    private var b0: UInt32 = 0xEFCD_AB89
    private var c0: UInt32 = 0x98BA_DCFE
    private var d0: UInt32 = 0x1032_5476
    /// Bytes not yet a whole 64-byte block.
    private var held: [UInt8] = []
    private var length: UInt64 = 0

    public init() {
        held.reserveCapacity(64)
    }

    static let shifts: [UInt32] = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                                   5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
                                   4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                                   6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]

    static let constants: [UInt32] = (0..<64).map { UInt32(truncatingIfNeeded: Int64(abs(sin(Double($0 + 1))) * 4_294_967_296)) }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    public mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update($0) }
    }

    public mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0 else { return }
        length &+= UInt64(bytes.count)
        var at = 0
        if !held.isEmpty {
            let take = min(64 - held.count, bytes.count)
            held.append(contentsOf: bytes[0..<take])
            at = take
            if held.count == 64 {
                held.withUnsafeBytes { block($0.baseAddress!) }
                held.removeAll(keepingCapacity: true)
            }
        }
        while bytes.count - at >= 64 {
            block(bytes.baseAddress! + at)
            at += 64
        }
        if at < bytes.count { held.append(contentsOf: bytes[at...]) }
    }

    /// The digest. The hash is spent: make a new one for more.
    public mutating func finish() -> [UInt8] {
        let bits = length &* 8
        var tail: [UInt8] = [0x80]
        let used = (held.count + 1) % 64
        tail += [UInt8](repeating: 0, count: used <= 56 ? 56 - used : 120 - used)
        for shift in stride(from: 0, to: 64, by: 8) { tail.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        let saved = length
        update(tail)
        length = saved
        var out: [UInt8] = []
        for word in [a0, b0, c0, d0] {
            for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8(truncatingIfNeeded: word >> UInt32(shift))) }
        }
        return out
    }

    /// The digest of `bytes`, in lower-case hex.
    public static func hex(_ bytes: [UInt8]) -> String {
        var hash = MD5()
        hash.update(bytes)
        return hash.finish().map { String($0, radix: 16).zeroPadded(to: 2) }.joined()
    }

    private mutating func block(_ pointer: UnsafeRawPointer) {
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 16) { m in
            for index in 0..<16 {
                m[index] = UInt32(littleEndian: pointer.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
            }
            var a = a0, b = b0, c = c0, d = d0
            Self.constants.withUnsafeBufferPointer { k in
                Self.shifts.withUnsafeBufferPointer { r in
                    for i in 0..<64 {
                        var f: UInt32
                        let g: Int
                        if i < 16 {
                            f = (b & c) | (~b & d)
                            g = i
                        } else if i < 32 {
                            f = (d & b) | (~d & c)
                            g = (5 &* i &+ 1) & 15
                        } else if i < 48 {
                            f = b ^ c ^ d
                            g = (3 &* i &+ 5) & 15
                        } else {
                            f = c ^ (b | ~d)
                            g = (7 &* i) & 15
                        }
                        f = f &+ a &+ k[i] &+ m[g]
                        a = d
                        d = c
                        c = b
                        let s = r[i]
                        b = b &+ ((f << s) | (f >> (32 &- s)))
                    }
                }
            }
            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }
    }
}

/// A FLAC's sound, as its STREAMINFO MD5 hashes it (spec 8.4): every sample as its integer, signed, little-endian in
/// `(bits + 7) / 8` bytes, the channels interleaved frame by frame. The phone's decoder gives Float32 at the file's
/// own scale (a sample over 2^(bits-1)), which holds any sample of 24 bits or fewer exactly - so each is turned back
/// to its integer by multiplying by 2^(bits-1), and the hash proves both the bytes and that iOS reads them as the
/// encoder meant.
public enum FLACMD5 {
    /// The bytes `frames` frames of `channels` (each a pointer to that channel's Float32 samples) add to the hash at
    /// `bits` per sample (4...24), appended to `out`.
    public static func pack(_ channels: [UnsafePointer<Float>], frames: Int, bits: Int, into out: inout [UInt8]) {
        let width = (bits + 7) / 8
        let scale = Float(1 << (bits - 1))
        let low = -Int32(1 << (bits - 1)), high = Int32(1 << (bits - 1)) - 1
        let start = out.count
        out.append(contentsOf: repeatElement(0, count: frames * channels.count * width))
        out.withUnsafeMutableBufferPointer { buffer in
            var at = start
            for frame in 0..<frames {
                for channel in channels {
                    let value = min(max(Int32((channel[frame] * scale).rounded()), low), high)
                    for byte in 0..<width {
                        buffer[at] = UInt8(truncatingIfNeeded: value >> Int32(8 * byte))
                        at += 1
                    }
                }
            }
        }
    }

    /// `pack` over arrays (the tests', and any caller holding samples).
    public static func pack(_ channels: [[Float]], bits: Int) -> [UInt8] {
        var out: [UInt8] = []
        let frames = channels.map(\.count).min() ?? 0
        withPointers(channels) { pack($0, frames: frames, bits: bits, into: &out) }
        return out
    }

    private static func withPointers(_ channels: [[Float]], _ body: ([UnsafePointer<Float>]) -> Void) {
        func next(_ index: Int, _ held: [UnsafePointer<Float>]) {
            guard index < channels.count else { return body(held) }
            channels[index].withUnsafeBufferPointer { next(index + 1, held + [$0.baseAddress!]) }
        }
        next(0, [])
    }

    /// What the decode found, against STREAMINFO.
    public enum Verdict: String, Sendable, Equatable {
        /// The sound is what the encoder hashed.
        case matched
        /// It isn't: the copy is deleted, and is a try.
        case mismatch
    }

    /// The hash of the decoded sound against STREAMINFO's.
    public static func verdict(_ digest: [UInt8], _ info: FLACStreamInfo) -> Verdict {
        digest == info.md5 ? .matched : .mismatch
    }
}
