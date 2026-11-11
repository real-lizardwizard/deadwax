import Foundation

/// This phone's id for its saves of the play queue - what deadwax's record says saved it (src/play_queue.py
/// DEVICE_PATTERN), so a queue the phone saved comes back as its own and one another device saved is said as a
/// pick-up. Made as the web app makes its own (ui/src/state/persisted.ts readPlayerDevice): 16 characters, each
/// `alphabet[byte & 63]` of a random byte, kept under the web's key name - in UserDefaults, which the app holds (it
/// survives install.sh's install over the app and a sign-out; a deleted app is a new device). Not
/// identifierForVendor (UIKit's, and nil before the first unlock) and not the phone's name (private).
public enum DeviceID {
    /// The UserDefaults key: the web's localStorage key.
    public static let storageKey = "deadwax-player-device"
    public static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    public static let length = 16
    /// What the server takes: `^[A-Za-z0-9_-]{8,64}$`.
    public static let lengths = 8...64

    /// Whether `id` is one the server takes.
    public static func isValid(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard lengths.contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39)
                || byte == 0x5F || byte == 0x2D
        }
    }

    /// A new id from `generator`'s bytes.
    public static func make<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<length).map { _ in alphabet[Int(UInt8.random(in: .min ... .max, using: &generator) & 63)] })
    }

    /// The id kept, read with care: a kept one as it is; nothing kept, or a value that isn't one, a new one - which
    /// the app stores (`isNew`).
    public static func read<G: RandomNumberGenerator>(_ stored: String?, using generator: inout G) -> (id: String, isNew: Bool) {
        if let stored, isValid(stored) { return (stored, false) }
        return (make(using: &generator), true)
    }

    public static func read(_ stored: String?) -> (id: String, isNew: Bool) {
        var generator = SystemRandomNumberGenerator()
        return read(stored, using: &generator)
    }
}
