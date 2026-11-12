import DeadwaxCore
import Foundation

/// Where the EQ is kept (eq.md 4): `Application Support/deadwax/eq.json` - backed up with the phone, so a restore keeps
/// it - written whole and moved into place. This phone's, per output: never per person, never sent anywhere.
///
/// A file this build can't read (or of a version it doesn't know) is set aside beside it as
/// `eq-unreadable-<day>.json` - never written over, never guessed at - and the phone starts with every output Off;
/// Debug's Kept row says what was set aside. A file that is there but can't be opened yet (a launch in the background
/// before the phone has been unlocked since it started, its data protection's) is left alone, and nothing is written
/// over it that launch.
struct EQStore {
    let url: URL?

    init(url: URL? = EQStore.defaultURL()) {
        self.url = url
    }

    static func defaultURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("deadwax", isDirectory: true)
            .appendingPathComponent("eq.json", isDirectory: false)
    }

    /// What was read at launch: the settings, the name a file that couldn't be read was set aside under, and the
    /// file's size.
    struct Loaded {
        var settings: EQSettings
        var setAside: String?
        var bytes: Int
        /// false when an unreadable file couldn't be moved aside, or the file can't be opened yet: nothing is written
        /// over it
        var writable = true
        /// there, but not to be opened until the phone is unlocked: read again then
        var locked = false
    }

    func load() -> Loaded {
        guard let url else { return Loaded(settings: EQSettings(), bytes: 0) }
        guard let data = try? Data(contentsOf: url) else {
            // none yet (a first launch) - or there but not to be opened yet, which an empty EQ must not replace
            let there = FileManager.default.fileExists(atPath: url.path)
            return Loaded(settings: EQSettings(), bytes: 0, writable: !there, locked: there)
        }
        if let settings = EQSettings.read(data) { return Loaded(settings: settings, bytes: data.count) }
        let aside = setAside(url)
        return Loaded(settings: EQSettings(), setAside: aside, bytes: 0, writable: aside != nil)
    }

    /// The settings written (keys sorted); the bytes written, or nil when they couldn't be.
    func save(_ settings: EQSettings) -> Int? {
        guard let url, let data = try? settings.written() else { return nil }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return data.count
        } catch {
            return nil
        }
    }

    /// The unreadable file moved aside, under a name no other file has.
    private func setAside(_ url: URL) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date())
        let folder = url.deletingLastPathComponent()
        for attempt in 1...99 {
            let name = EQSettings.unreadableName(day: day, attempt: attempt)
            let aside = folder.appendingPathComponent(name, isDirectory: false)
            if FileManager.default.fileExists(atPath: aside.path) { continue }
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                return name
            } catch {
                return nil
            }
        }
        return nil
    }
}
