import Foundation

/// Download your library, in a listener's words (notes/ios-specs/phase3-autodownload.md 1.2; slice 2): You >
/// Downloads' section, the first ask, Downloading's row, the album page's lines, Remove All's. "your library" with a
/// library of your own; "the collection" with logins off and for the break-glass admin, whose Albums are the
/// collection's. Never "sync": a check with deadwax is "checked".
public enum AutoDownloadWords {
    // MARK: the setting

    public static func switchName(_ scope: AlbumScope) -> String {
        scope == .yours ? "Download your library" : "Download the collection"
    }

    /// The switch's note.
    public static func note(_ scope: AlbumScope) -> String {
        scope == .yours
            ? "Keeps your library on this phone, newest first, as much as fits in the storage limit - albums you add come by themselves, and albums you remove go."
            : "Keeps the collection on this phone, newest first, as much as fits in the storage limit."
    }

    /// The section's header: what the switch keeps.
    public static func header(_ scope: AlbumScope) -> String { scope == .yours ? "Your library" : "The collection" }

    /// (slice 3) Only while charging's switch, under Download your library while it is on.
    public static let onlyWhileCharging = "Only while charging"

    /// Its note.
    public static func chargingNote(_ scope: AlbumScope) -> String {
        "\(scope == .yours ? "Your library's" : "The collection's") albums download only while the phone is charging. Albums you download yourself don't wait."
    }

    /// "1,240 albums" / "1 album".
    static func albums(_ n: Int) -> String { "\(UpNextWords.grouped(n)) \(n == 1 ? "album" : "albums")" }

    /// The fit line (3.1): "All 212 albums fit in 20 GB." / "1,240 of 3,010 albums fit in 20 GB. Raise the limit or
    /// download fewer." / "All 3,010 albums, 1.4 TB." (No limit) / "1,240 of 3,010 albums fit on this phone." - with
    /// " - 3 wait for space on this phone" when the phone is short as well. `bytes`: what the albums that fit take.
    public static func fit(_ plan: LibraryFill.Plan, limit: StorageLimit, bytes: Int64) -> String {
        let of = plan.of
        guard of > 0 else { return "Nothing to download yet." }
        let phone = plan.count(.phoneFull)
        let room = plan.count(.room)
        if plan.allFit {
            if limit.bytes == nil { return "All \(albums(of)), \(Bytes.words(bytes))." }
            return of == 1 ? "The 1 album fits in \(limit.label)." : "All \(albums(of)) fit in \(limit.label)."
        }
        let place = limit.bytes == nil ? "on this phone" : "in \(limit.label)"
        var line = "\(UpNextWords.grouped(plan.fit)) of \(albums(of)) fit \(place)"
        if phone > 0 && limit.bytes != nil { line += " - \(UpNextWords.grouped(phone)) wait for space on this phone" }
        line += "."
        if room > 0 { line += " Raise the limit or download fewer." }
        return line
    }

    /// While its albums' songs are read: "Reading your library - 1,240 of 3,010 albums".
    public static func reading(_ scope: AlbumScope, read: Int, of: Int) -> String {
        "Reading \(scope == .yours ? "your library" : "the collection") - \(UpNextWords.grouped(read)) of \(albums(of))"
    }

    /// The footer: "Checked just now" / "Checked 3 minutes ago" / "Checked at 14:02" (an hour on) / "Not checked yet".
    public static func checked(_ at: Int64?, now: Int64, zone: TimeZone = .current) -> String {
        guard let at else { return "Not checked yet" }
        let seconds = max(now - at, 0) / 1_000
        if seconds < 60 { return "Checked just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "Checked \(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(at) / 1_000))
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(Date(timeIntervalSince1970: Double(at) / 1_000),
                           inSameDayAs: Date(timeIntervalSince1970: Double(now) / 1_000)) {
            return "Checked at \(clock)"
        }
        let day = calendar.dateComponents([.day, .month], from: Date(timeIntervalSince1970: Double(at) / 1_000))
        return "Checked \(day.day ?? 1) \(AlbumTime.months[max(min((day.month ?? 1) - 1, 11), 0)].prefix(3)) at \(clock)"
    }

    /// The last check couldn't answer (ErrorWords' advice is drawn under it).
    public static let couldntCheck = "Couldn't check with deadwax - showing what was there last time."

    // MARK: the question (2.3)

    /// An empty list or a large drop, held back: nothing has gone - asked. `here`: the library's albums with songs on
    /// this phone.
    public static func question(_ held: LibraryFollow.Held, scope: AlbumScope, here: Int) -> String? {
        let whose = scope == .yours ? "your library" : "the collection"
        switch held {
        case .empty:
            return "deadwax says \(whose) is empty. Remove the \(albums(here)) downloaded with it from this phone?"
        case .drop(let gone, let of):
            return "deadwax's list of \(whose) lost \(UpNextWords.grouped(gone)) of \(albums(of)) at once. Remove them from this phone?"
        case .truncated:
            return nil
        }
    }

    /// What Remove does, under the question: never at once.
    public static let questionNote = "Nothing has been removed. Remove lets them go once deadwax says the same again, ten minutes or more from now."
    public static let keepThem = "Keep Them"
    public static let remove = "Remove"

    // MARK: Downloading (3.3)

    /// The row's title.
    public static func downloadingTitle(_ scope: AlbumScope) -> String { header(scope) }

    /// "38 of 412 albums to go · 12.4 GB".
    public static func downloadingRow(_ progress: LibraryDownloads.Progress) -> String {
        "\(UpNextWords.grouped(progress.toGo)) of \(albums(progress.of)) to go \u{00B7} \(Bytes.words(progress.bytes))"
    }

    /// Spoken: "Your library, 38 of 412 albums to go, 12.4 GB, 40 percent".
    public static func downloadingSpoken(_ scope: AlbumScope, _ progress: LibraryDownloads.Progress) -> String {
        "\(header(scope)), \(UpNextWords.grouped(progress.toGo)) of \(albums(progress.of)) to go, \(Bytes.words(progress.bytes)), \(DownloadWords.percent(progress.fraction))"
    }

    /// You's Downloads row footer while your library alone is downloading: "Your library: 38 of 412 albums to go".
    public static func youFooter(_ scope: AlbumScope, _ progress: LibraryDownloads.Progress) -> String {
        "\(header(scope)): \(UpNextWords.grouped(progress.toGo)) of \(albums(progress.of)) to go"
    }

    // MARK: the album page (3.4)

    /// In your library, no room: "Your library doesn't all fit in 20 GB - this one waits for room."
    public static func waitsForRoom(_ scope: AlbumScope, limit: StorageLimit) -> String {
        let what = scope == .yours ? "Your library" : "The collection"
        if limit.bytes == nil { return "\(what) doesn't all fit on this phone - this one waits for space." }
        return "\(what) doesn't all fit in \(limit.label) - this one waits for room."
    }

    public static func keptOff(_ scope: AlbumScope) -> String {
        "You removed this download - \(scope == .yours ? "your library" : "the collection") leaves it off this phone."
    }

    /// The control's menu's first line for an album here with your library.
    public static func menuTitle(_ scope: AlbumScope) -> String {
        "Downloaded with \(scope == .yours ? "your library" : "the collection")"
    }

    /// The control's menu title for a downloaded album of your library: its line, then the size.
    public static func controlMenuTitle(_ scope: AlbumScope, bytesHere: Int64) -> String {
        "\(menuTitle(scope))\n\(Bytes.words(bytesHere))"
    }

    /// Added to the mine block's Remove line when a download of the album came with your library and none by hand.
    public static let goesToo = "Its download goes from this phone too."

    /// Added to Remove All's message while the switch is on.
    public static func removeAllToo(_ scope: AlbumScope) -> String {
        "\(switchName(scope)) is turned off too, or it would download them again."
    }

    // MARK: what deletes asks first (after the review)

    /// Turning the switch off with albums of it here: "Remove the 412 albums downloaded with your library?"
    public static func offTitle(_ scope: AlbumScope, albums n: Int) -> String {
        let what = scope == .yours ? "your library" : "the collection"
        return n == 1 ? "Remove the album downloaded with \(what)?" : "Remove the \(albums(n)) downloaded with \(what)?"
    }

    /// Its message: what goes, and what stays.
    public static func offMessage(bytes: Int64) -> String {
        "They go from this phone (\(Bytes.words(bytes))). What you downloaded yourself stays."
    }

    /// Its destructive button.
    public static let offAndRemove = "Turn Off and Remove"

    /// Didn't download's Remove on an album your library downloaded, with songs of it here: what else goes.
    public static func keepOffTitle(_ name: String) -> String { "Leave \(name) off this phone?" }

    public static func keepOffMessage(_ scope: AlbumScope, songsHere n: Int) -> String {
        let what = scope == .yours ? "Your library" : "The collection"
        let songs = n == 1 ? "Its 1 song already here goes too" : "Its \(UpNextWords.grouped(n)) songs already here go too"
        return "\(what) leaves it off until you download it again. \(songs); songs of it you downloaded yourself stay."
    }

    // its destructive button is DownloadWords.removeDownload

    // MARK: the first ask (3.2)

    public static func askTitle(_ scope: AlbumScope) -> String {
        scope == .yours ? "Keep your library on this phone?" : "Keep the collection on this phone?"
    }

    public static func askLine(_ scope: AlbumScope, limit: StorageLimit) -> String {
        let fits = limit.bytes == nil ? "as much as fits on this phone" : "as much as fits in \(limit.label)"
        return scope == .yours
            ? "deadwax can download your library, newest first, \(fits), and keep it in step as you add and remove albums."
            : "deadwax can download the collection, newest first, \(fits), and keep it in step as it changes."
    }

    public static let turnOn = "Turn On"
    public static let notNow = "Not Now"

    /// Every line, both scopes, for the ban list.
    public static var everyLine: [String] {
        var lines: [String] = [couldntCheck, questionNote, keepThem, remove, goesToo, turnOn, notNow, offAndRemove,
                               offMessage(bytes: 12_400_000_000), keepOffTitle("Album"), onlyWhileCharging]
        let plan = LibraryFill.plan([.init(id: "a", bytes: 1), .init(id: "b", bytes: 30_000_000_000)],
                                    .init(limit: StorageLimit.gb20.bytes, freeSpace: 25_000_000_000))
        for scope in AlbumScope.allCases {
            lines += [switchName(scope), note(scope), header(scope), chargingNote(scope),
                      reading(scope, read: 1_240, of: 3_010),
                      waitsForRoom(scope, limit: .gb20), waitsForRoom(scope, limit: .none), keptOff(scope),
                      menuTitle(scope), controlMenuTitle(scope, bytesHere: 412_000_000), removeAllToo(scope), askTitle(scope), askLine(scope, limit: .gb20),
                      askLine(scope, limit: .none),
                      downloadingSpoken(scope, LibraryDownloads.Progress(toGo: 38, of: 412, bytes: 12_400_000_000)),
                      youFooter(scope, LibraryDownloads.Progress(toGo: 38, of: 412, bytes: 12_400_000_000)),
                      offTitle(scope, albums: 412), offTitle(scope, albums: 1), keepOffMessage(scope, songsHere: 9),
                      keepOffMessage(scope, songsHere: 1)]
            lines += [LibraryFollow.Held.empty(kept: 212), .drop(gone: 1_240, of: 3_010)]
                .compactMap { question($0, scope: scope, here: 212) }
        }
        lines += [fit(plan, limit: .gb20, bytes: 1), fit(plan, limit: .none, bytes: 1),
                  checked(nil, now: 0), checked(0, now: 5_000), checked(0, now: 180_000), checked(0, now: 7_200_000),
                  downloadingRow(LibraryDownloads.Progress(toGo: 38, of: 412, bytes: 12_400_000_000))]
        return lines
    }
}
