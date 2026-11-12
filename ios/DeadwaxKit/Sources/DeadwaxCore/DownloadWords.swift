import Foundation

/// Every word Phase 2 adds (notes/ios-specs/phase2-downloads.md), each tested. "Download" is the verb, as Apple Music
/// has it; "Downloaded" the state; "this phone" wherever "download" alone could be read as deadwax fetching from
/// Soulseek. The web's words hold: "your library", "the collection" - never "Navidrome", "the store", "cache", "sync",
/// "MD5", "offline mode" or "everything" for a listener. A failed request is said by ErrorWords, through an
/// APIFailure for the stream's path; only the download's own failures are said here, in the same voice.
public enum DownloadWords {
    // MARK: menus (title case, as Play Next and Play Last)

    public static let download = "Download"
    public static let removeDownload = "Remove Download"
    public static let downloadAgain = "Download Again"
    public static let downloadUpNext = "Download Up Next"
    /// The control's, the download items' and Download Up Next's mark.
    public static let downloadSymbol = "arrow.down.circle"
    /// Play Next's and Play Last's (iOS 16.0), Info's and Go to album's (iOS 13.0) - every menu item carries one (3.4).
    public static let playNextSymbol = "text.line.first.and.arrowtriangle.forward"
    public static let playLastSymbol = "text.line.last.and.arrowtriangle.forward"
    public static let infoSymbol = "info.circle"
    public static let goToAlbumSymbol = "square.stack"

    // MARK: marks (1.2)

    /// The mark each state draws, SF Symbols (the ring is drawn by the app, so it has none).
    public enum Mark: String, Sendable, Equatable {
        case control = "arrow.down.circle"
        case waiting = "arrow.down.circle.dotted"
        case downloaded = "arrow.down.circle.fill"
        case failed = "exclamationmark.circle.fill"
        /// Drawn as the ring.
        case ring = ""
        case checked = "checkmark.circle"
    }

    /// A song's mark in its row (nil: nothing - not asked for).
    public static func mark(_ state: SongDownload) -> Mark? {
        switch state {
        case .none: return nil
        case .waiting: return .waiting
        case .fetching: return .ring
        case .done: return .downloaded
        case .failed: return .failed
        }
    }

    /// An album's mark - the control's (`none` and `partial` are the arrow there) and a tile's (nil: no mark).
    public static func mark(_ album: AlbumDownload, control: Bool = false) -> Mark? {
        switch album {
        case .none: return control ? .control : nil
        case .partial: return control ? .control : .downloaded
        case .downloading: return .ring
        case .waiting: return .waiting
        case .failed: return .failed
        case .downloaded: return .downloaded
        }
    }

    // MARK: the album's line (the hero, the control's VoiceOver value - 2.3)

    /// "3 of 12 songs downloaded", "Downloading - 4 of 12 songs", a wait's words, "2 songs didn't download",
    /// "Downloaded"; nil for none.
    public static func albumLine(_ album: AlbumDownload) -> String? {
        switch album {
        case .none: return nil
        case .partial(let here, let of): return "\(here) of \(songs(of)) downloaded"
        case .downloading(let here, let of, _): return "Downloading - \(here) of \(songs(of))"
        case .waiting(let reason, _, _): return wait(reason)
        case .failed(let count, _): return didntDownload(count)
        case .downloaded: return downloaded
        }
    }

    /// The control's VoiceOver value: "Downloading, 40 percent" while fetching, else the album's line.
    public static func controlValue(_ album: AlbumDownload) -> String? {
        if case .downloading(_, _, let fraction) = album { return downloading(percent: fraction) }
        return albumLine(album)
    }

    /// The control's label in every state (VoiceOver), and the Large Content Viewer's.
    public static let controlLabel = "Download"

    /// A song's words - its row's VoiceOver words after the title, its menu's - nil for none.
    public static func songLine(_ state: SongDownload) -> String? {
        switch state {
        case .none: return nil
        case .waiting(let reason): return wait(reason)
        case .fetching(let fraction): return downloading(percent: fraction)
        case .done: return downloaded
        case .failed: return didntDownloadOne
        }
    }

    /// A tile's one short line on Downloaded (5.1): "12 songs", "3 of 12 songs", "Downloading", "Waiting",
    /// "Didn't download". `songCount`: the album's songs.
    public static func tileLine(_ album: AlbumDownload, songCount: Int) -> String? {
        switch album {
        case .none: return nil
        case .partial(let here, let of): return "\(here) of \(songs(of))"
        case .downloading: return "Downloading"
        case .waiting: return "Waiting"
        case .failed: return didntDownloadOne
        case .downloaded: return songs(songCount)
        }
    }

    /// A tile's or a Library row's words for VoiceOver (5.3), after the artist: "Downloaded", "Partly downloaded",
    /// "Downloading", "Waiting to download", "Didn't download" - and, dimmed offline, "Not on this phone".
    public static func tileSpoken(_ album: AlbumDownload, notHere: Bool = false) -> String? {
        if notHere { return notOnPhone }
        switch album {
        case .none: return nil
        case .partial: return "Partly downloaded"
        case .downloading: return "Downloading"
        case .waiting: return "Waiting to download"
        case .failed: return didntDownloadOne
        case .downloaded: return downloaded
        }
    }

    public static let downloaded = "Downloaded"
    public static let didntDownloadOne = "Didn't download"
    public static let notOnPhone = "Not on this phone"

    /// "Downloading, 40 percent".
    public static func downloading(percent fraction: Double) -> String {
        "Downloading, \(percent(fraction))"
    }

    /// "40 percent" - rounded down, so 100 only once it's here. A Downloading row's VoiceOver words end with it (6.8:
    /// "Dummy, Portishead, 4 of 12 songs, 40 percent"), its section already saying it is downloading.
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down))) percent"
    }

    /// "1 song didn't download", "2 songs didn't download".
    public static func didntDownload(_ count: Int) -> String { "\(songs(count)) didn't download" }

    /// "1 song", "2 songs" - as AlbumPageLines.footer counts them.
    public static func songs(_ count: Int) -> String { "\(count) \(count == 1 ? "song" : "songs")" }

    /// A wait, in words (2.3).
    public static func wait(_ reason: DownloadWait) -> String {
        switch reason {
        case .queued: return "Waiting to download"
        case .connection: return "Waiting for a connection"
        case .deadwax: return "Waiting for deadwax"
        case .signIn: return "Waiting for you to sign in"
        case .wifi: return "Waiting for Wi-Fi"
        case .hotspot: return "Waiting - this Wi-Fi is a hotspot"
        case .lowData: return "Waiting - Low Data Mode is on"
        case .room: return "Waiting for room - the storage limit is reached"
        case .phoneFull: return "Waiting for space on this phone"
        }
    }

    /// A wait a setting causes, its second line in the control's menu (3.1): where the setting is - never a way round it.
    public static func waitSetting(_ reason: DownloadWait, limit: StorageLimit) -> String? {
        switch reason {
        case .wifi, .hotspot, .lowData: return "Download over is Wi-Fi only - in You > Downloads."
        case .room: return "The storage limit is \(limit.label) - in You > Downloads."
        default: return nil
        }
    }

    /// The control's menu's title (3.1): the album's line, a setting's line under it, and the size once downloaded -
    /// "Downloaded · 412 MB". One or two lines, a newline between them.
    public static func controlMenuTitle(_ album: AlbumDownload, limit: StorageLimit, bytesHere: Int64,
                                        firstFailure: String? = nil) -> String {
        var lines: [String] = []
        switch album {
        case .downloaded:
            lines.append("\(downloaded) \u{00B7} \(Bytes.words(bytesHere))")
        case .waiting(let reason, _, _):
            lines.append(wait(reason))
            if let setting = waitSetting(reason, limit: limit) { lines.append(setting) }
        case .failed:
            lines.append(albumLine(album) ?? "")
            if let firstFailure, !firstFailure.isEmpty { lines.append(firstFailure) }
        default:
            if let line = albumLine(album) { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: the album page (3.5, 3.6, 3.7)

    /// The footer's second line: "412 MB on this phone", or for a partial album "3 of 12 songs on this phone · 92 MB".
    public static func footer(here: Int, of total: Int, bytes: Int64) -> String? {
        guard here > 0 else { return nil }
        if here >= total { return "\(Bytes.words(bytes)) on this phone" }
        return "\(here) of \(songs(total)) on this phone \u{00B7} \(Bytes.words(bytes))"
    }

    /// An album deadwax no longer has, with songs of it on this phone.
    public static let albumGoneHere = "This album isn't in the collection any more - the songs on this phone still play."
    /// An album not on this phone, opened while deadwax can't be reached.
    public static let albumNotHere = "This album isn't on this phone - it plays once deadwax is back."

    /// "Removed from this phone: Dummy".
    public static func removed(_ name: String) -> String { "Removed from this phone: \(name)" }
    /// Now Playing's: "Downloading: Roads".
    public static func downloadingSong(_ title: String) -> String { "Downloading: \(title)" }
    /// "Downloading 23 songs from Up Next", "Downloading 1 song from Up Next".
    public static func downloadingUpNext(_ count: Int) -> String { "Downloading \(songs(count)) from Up Next" }
    /// What VoiceOver hears as a download asked for from an album page ends while the page is on top.
    public static func ended(_ album: String, failed: Int) -> String {
        failed > 0 ? "\(album): \(didntDownload(failed))" : "Downloaded \(album)"
    }

    // MARK: why a song didn't download (2.4)

    /// A 404's sentence.
    public static let songGone = "This song isn't on deadwax any more."
    public static let wrongSize = "The copy kept arriving the wrong size."
    public static let soundMismatch = "The copy's sound didn't match the original."
    public static let unreadable = "This phone couldn't read the copy."
    public static let unsaved = "This phone couldn't save it."

    /// Why a song didn't download, for the reader `admin` says (`Access.seesDetail`): an HTTP answer or no answer as
    /// ErrorWords says any failure of the stream's route, a 404 as `songGone`; the download's own in its words, with
    /// ErrorWords' advice for "other".
    public static func failure(_ failure: DownloadFailure, songID: String, server: ServerAddress?, admin: Bool) -> ErrorWords.Line {
        let path = "/navidrome/stream/\(DeadwaxClient.segment(songID))"
        let error: APIFailure
        switch failure {
        case .answered(let status, let detail):
            error = .answered(.init(status: status, method: "GET", path: path, detail: detail))
        case .offline(let reason), .timeout(let reason):
            guard let server else { return own(ErrorWords.offline, raw: reason, admin: admin) }
            let none = APIFailure.NoAnswer(server: server, method: "GET", path: path, reason: reason)
            if case .timeout = failure { error = .timeout(none) } else { error = .offline(none) }
        case .wrongSize: return own(wrongSize, raw: "the length wasn't Navidrome's size, three times", admin: admin)
        case .soundMismatch: return own(soundMismatch, raw: "the decoded audio's MD5 wasn't STREAMINFO's, three times", admin: admin)
        case .unreadable: return own(unreadable, raw: "iOS couldn't open or decode the file", admin: admin)
        case .unsaved: return own(unsaved, raw: "the file couldn't be written", admin: admin)
        }
        return ErrorWords.of(error, admin: admin, gone: songGone)
    }

    static func own(_ text: String, raw: String, admin: Bool) -> ErrorWords.Line {
        ErrorWords.Line(kind: .other, text: text, advice: admin ? "Try again." : "Try again - if it keeps happening, tell whoever runs deadwax.",
                        detail: admin && !raw.isEmpty ? raw : nil)
    }

    // MARK: Info (4.4)

    public static let playsFrom = "Plays from"
    public static let streamed = "Streamed from deadwax"

    /// Info's Plays from: "This phone - checked", "... - checked by size", "... - not checked yet", or streamed.
    public static func playsFrom(_ check: CopyCheck?, isFLAC: Bool) -> String {
        guard let check else { return streamed }
        switch DownloadRules.verdict(check, isFLAC: isFLAC) {
        case .checked: return "This phone - checked"
        case .bySize: return "This phone - checked by size"
        case .checking: return "This phone - not checked yet"
        }
    }

    /// Debug's "On this phone" (an admin's): "matched - MD5 4f1c…e2, 24-bit 96 kHz, 2 ch"; "not kept".
    public static func debugOnPhone(_ record: DownloadRecord?, channels: Int? = nil) -> String {
        guard let record, record.state == .done else { return "not kept" }
        var line = (record.check ?? .unchecked).rawValue.replacingOccurrences(of: "_", with: " ")
        if let flac = record.flac {
            let md5 = flac.md5.count == 32 ? "\(flac.md5.prefix(4))\u{2026}\(flac.md5.suffix(2))" : flac.md5
            line += " - MD5 \(md5), \(flac.bits)-bit \(RateWords.kHz(Double(flac.rate)))"
            if let channels { line += ", \(channels) ch" }
        }
        return line
    }

    // MARK: the Library (5)

    public static let downloadedTitle = "Downloaded"
    public static let onThisPhone = "On this phone"
    public static let nothingYet = "Nothing downloaded yet."
    public static let nothingYetHow = "Download an album from its page, and it plays here even when deadwax can't be reached."
    /// The root's one row while it is Downloaded and deadwax can't be reached (5.4).
    public static let onlyDownloadedPlay = "Only downloaded albums play until deadwax is back."

    // MARK: You (6.1)

    public static let downloads = "Downloads"

    /// You's Downloads row's footer, only while something is happening: "Downloading - 6 songs to go", the first wait,
    /// or "2 songs didn't download" (amber - `amber`).
    public static func youFooter(fetching: Int, toGo: Int, firstWait: DownloadWait?, failed: Int) -> (text: String, amber: Bool)? {
        if fetching > 0 { return ("Downloading - \(songs(toGo)) to go", false) }
        if let firstWait { return (wait(firstWait), false) }
        if failed > 0 { return (didntDownload(failed), true) }
        return nil
    }

    /// Added to You > Account's footnote when anything is on the phone.
    public static let staysAfterSignOut = " Your downloads stay on this phone for when you sign in again."

    // MARK: You > Downloads (6.2 - 6.7)

    public static let storage = "Storage"
    public static let storageLimit = "Storage limit"
    public static let noLimit = "No limit"

    /// The usage row's headline and its quiet rest: "2.1 GB" + " of 20 GB" (No limit: " downloaded").
    public static func used(_ bytes: Int64, limit: StorageLimit) -> (amount: String, rest: String) {
        (Bytes.words(bytes), limit.bytes == nil ? " downloaded" : " of \(limit.label)")
    }

    /// "12 albums · 148 songs · 41.2 GB free on this phone" (nothing here: the free space alone).
    public static func usageLine(albums: Int, songs count: Int, free: Int64) -> String {
        let freeWords = "\(Bytes.words(free)) free on this phone"
        guard count > 0 else { return freeWords }
        return "\(albums) \(albums == 1 ? "album" : "albums") \u{00B7} \(songs(count)) \u{00B7} \(freeWords)"
    }

    /// Over the limit (the limit lowered below what's here), amber.
    public static func overLimit(_ limit: StorageLimit) -> String {
        "More than the \(limit.label) limit - nothing is removed for it, but new downloads wait for room."
    }

    public static let nothingYetHeadline = "Nothing downloaded yet"

    /// The usage row's VoiceOver value: "2.1 GB of 20 GB used, 41.2 GB free on this phone".
    public static func usageSpoken(_ bytes: Int64, limit: StorageLimit, free: Int64) -> String {
        let of = limit.bytes == nil ? "downloaded" : "of \(limit.label) used"
        return "\(Bytes.words(bytes)) \(of), \(Bytes.words(free)) free on this phone"
    }

    public static let storageFooter = "The storage limit is what downloads may take - songs kept from streaming (up to 2 GB) are apart from it."

    public static let otherAccounts = "Other accounts on this phone"
    public static let remove = "Remove"
    public static let removeOthersTitle = "Remove other accounts' downloads?"
    public static func removeOthersMessage(_ bytes: Int64) -> String {
        "\(Bytes.words(bytes)) of music downloaded by other accounts goes from this phone. They can download it again when they sign in."
    }

    public static let downloadOver = "Download over"

    /// A choice's name and its note (6.4).
    public static func over(_ choice: DownloadOver) -> (name: String, note: String) {
        switch choice {
        case .wifi: return ("Wi-Fi only", "Downloads use Wi-Fi alone - never mobile data, a hotspot or Low Data Mode.")
        case .any: return ("Wi-Fi and cellular", "Downloads use mobile data too, whenever there's no Wi-Fi.")
        }
    }

    /// Download over's footer, first line: what's used now - amber while something waits for it (`amber`).
    public static func overNow(_ path: NetworkPath, setting: DownloadOver) -> String {
        let wifiOnly = setting == .wifi
        switch path.kind {
        case .wifi: return "On Wi-Fi now."
        case .mobileData: return wifiOnly ? "On mobile data now - downloads wait for Wi-Fi." : "On mobile data now - downloads use it."
        case .hotspot: return wifiOnly ? "On a hotspot now - downloads wait until you're off it." : "On a hotspot now - downloads use it."
        case .lowData: return wifiOnly ? "Low Data Mode is on - downloads wait until it's off." : "Low Data Mode is on - downloads use it."
        case .none: return "No connection now."
        }
    }

    /// Download over's footer, after what's used now (as Normalization's footer, YouWords.kept).
    public static let overKept = "These are kept on this phone."

    public static let downloadingHeader = "Downloading"
    public static let didntDownloadHeader = "Didn't download"
    public static let downloadedHeader = "Downloaded"

    /// A Downloading row's line (6.5): the wait's words; the song's title when only one song of the album is asked
    /// (never "1 of 1 song"); else "4 of 12 songs".
    public static func downloadingRow(here: Int, of total: Int, wait: DownloadWait?, onlySong: String?) -> String {
        if let wait, wait != .queued { return self.wait(wait) }
        if let onlySong { return onlySong }
        return "\(here) of \(songs(total))"
    }

    /// The Downloading section's footer: all waiting for Wi-Fi.
    public static let allWaitForWifi = "Downloads wait for Wi-Fi - Download over is set to Wi-Fi only."
    /// ... after a force quit, until the downloads it names have finished, or a day.
    public static let forceQuit = "Downloads stopped when deadwax was closed from the app switcher, and carried on when it opened again."
    /// How long the force-quit footer may show, at most.
    public static let forceQuitShownSeconds: Double = 24 * 60 * 60

    public static let tryAgain = "Try again"
    public static let tryAllAgain = "Try all again"

    /// A Downloaded row's line (6.6): "12 songs · 412 MB", or "3 of 12 songs · 92 MB".
    public static func downloadedRow(here: Int, of total: Int, bytes: Int64) -> String {
        let count = here >= total ? songs(here) : "\(here) of \(songs(total))"
        return "\(count) \u{00B7} \(Bytes.words(bytes))"
    }

    /// A Downloaded row's check (6.6).
    public static func verdict(_ verdict: DownloadRules.Verdict) -> String {
        switch verdict {
        case .checked: return "Checked"
        case .bySize: return "Checked by size"
        case .checking: return "Checking\u{2026}"
        }
    }

    public static let downloadedFooter = "Each song is checked once it's here: its size against deadwax's file, and a FLAC's sound against the fingerprint it carries. A song plays before its check is done."

    public static let removeAll = "Remove All Downloads"
    public static let removeAllTitle = "Remove all downloads?"
    /// "148 songs (2.1 GB) go from this phone. They stay in the collection, and you can download them again."
    public static func removeAllMessage(songs count: Int, bytes: Int64) -> String {
        "\(songs(count)) (\(Bytes.words(bytes))) go from this phone. They stay in the collection, and you can download them again."
    }
    public static let removedAll = "Removed all downloads"

    /// The screen's last footer.
    public static let lastFooter = "Closing deadwax from the app switcher stops downloads until you open it again; locking the phone doesn't. Downloads stay on this phone when you sign out."

    /// When the store can't be read: downloads are off for this launch, nothing is deleted.
    public static let storeUnreadable = "This phone couldn't read its downloads - close deadwax from the app switcher and open it again."

    // MARK: offline (7)

    /// The banner's line, its mark and its second line, by why (7.2).
    public static func banner(_ reach: Reach) -> (line: String, symbol: String, more: String)? {
        switch reach {
        case .online: return nil
        case .noNetwork:
            return ("Offline - showing what's on this phone", "wifi.slash",
                    "Turn off Airplane Mode or join a network to play what isn't on this phone.")
        case .unreachable:
            return ("Can't reach deadwax - showing what's on this phone", "wifi.exclamationmark",
                    "Check you're on the right network (or your VPN is on).")
        }
    }

    public static let trying = "Trying\u{2026}"
    public static let backOnline = "Back online"
    public static let showsMore = "Shows more"
    public static let showingMore = "Showing more"

    /// The player's: a song not on the phone, passed over while deadwax can't be reached (7.3).
    public static func skippedNotHere(title: String) -> String { "Skipped \"\(title)\" - it isn't on this phone" }
    /// A run of them within the notice's 5 s.
    public static func skippedNotHere(count: Int) -> String {
        count == 1 ? "Skipped 1 song that isn't on this phone" : "Skipped \(count) songs that aren't on this phone"
    }
    /// The player stopped on the first song not here, nothing after it here either.
    public static let stoppedNotHere = "Not on this phone - it plays once deadwax is back."

    /// Every listener's line above, for the vocabulary test.
    public static var everyLine: [String] {
        var lines = [download, removeDownload, downloadAgain, downloadUpNext, controlLabel, downloaded, didntDownloadOne,
                     notOnPhone, albumGoneHere, albumNotHere, songGone, wrongSize, soundMismatch, unreadable, unsaved,
                     playsFrom, streamed, downloadedTitle, onThisPhone, nothingYet, nothingYetHow, onlyDownloadedPlay,
                     downloads, staysAfterSignOut, storage, storageLimit, noLimit, nothingYetHeadline, storageFooter,
                     otherAccounts, remove, removeOthersTitle, removeOthersMessage(1_200_000_000), downloadOver, overKept,
                     downloadingHeader, didntDownloadHeader, downloadedHeader, allWaitForWifi, forceQuit, tryAgain,
                     tryAllAgain, downloadedFooter, removeAll, removeAllTitle, removeAllMessage(songs: 148, bytes: 2_100_000_000),
                     removedAll, lastFooter, storeUnreadable, trying, backOnline, showsMore, showingMore,
                     skippedNotHere(title: "Roads"), skippedNotHere(count: 3), stoppedNotHere,
                     removed("Dummy"), downloadingSong("Roads"), downloadingUpNext(23), ended("Dummy", failed: 0),
                     ended("Dummy", failed: 2), overLimit(.gb10), usageSpoken(2_100_000_000, limit: .gb20, free: 41_200_000_000),
                     usageLine(albums: 12, songs: 148, free: 41_200_000_000)]
        lines += DownloadWait.allCases.map(wait)
        lines += DownloadWait.allCases.compactMap { waitSetting($0, limit: .gb20) }
        lines += DownloadOver.allCases.flatMap { [over($0).name, over($0).note] }
        for kind in [NetworkPath(satisfied: true, wifi: true), NetworkPath(satisfied: true, cellular: true, expensive: true),
                     NetworkPath(satisfied: true, wifi: true, expensive: true), NetworkPath(satisfied: true, wifi: true, constrained: true),
                     .none] {
            lines += DownloadOver.allCases.map { overNow(kind, setting: $0) }
        }
        lines += [Reach.noNetwork, .unreachable].compactMap { banner($0) }.flatMap { [$0.line, $0.more] }
        lines += CopyCheck.allCases.flatMap { [playsFrom($0, isFLAC: true), playsFrom($0, isFLAC: false)] }
        lines += [DownloadRules.Verdict.checked, .bySize, .checking].map(verdict)
        return lines
    }
}
