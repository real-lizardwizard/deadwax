import Foundation
import Testing
@testable import DeadwaxCore

// Every word Phase 2 adds (spec 2.3, 2.4, 3, 4.4, 6, 7), and the vocabulary's rule over all of them.

@Suite struct DownloadWordsTests {
    @Test func theAlbumsLine() {
        #expect(DownloadWords.albumLine(.none) == nil)
        #expect(DownloadWords.albumLine(.partial(here: 3, of: 12)) == "3 of 12 songs downloaded")
        #expect(DownloadWords.albumLine(.downloading(here: 4, of: 12, fraction: 0.4)) == "Downloading - 4 of 12 songs")
        #expect(DownloadWords.albumLine(.downloading(here: 0, of: 1, fraction: 0)) == "Downloading - 0 of 1 song")
        #expect(DownloadWords.albumLine(.failed(count: 1, first: .unsaved)) == "1 song didn't download")
        #expect(DownloadWords.albumLine(.failed(count: 2, first: .unsaved)) == "2 songs didn't download")
        #expect(DownloadWords.albumLine(.downloaded(checking: true)) == "Downloaded")
        #expect(DownloadWords.controlValue(.downloading(here: 4, of: 12, fraction: 0.4)) == "Downloading, 40 percent")
        #expect(DownloadWords.controlValue(.downloading(here: 4, of: 12, fraction: 0.999)) == "Downloading, 99 percent", "100 only once it's here")
        #expect(DownloadWords.controlValue(.downloaded(checking: false)) == "Downloaded")
        #expect(DownloadWords.controlValue(.none) == nil)
        #expect(DownloadWords.controlLabel == "Download")
    }

    @Test func everyWait() {
        let expected: [DownloadWait: String] = [
            .queued: "Waiting to download", .connection: "Waiting for a connection", .deadwax: "Waiting for deadwax",
            .signIn: "Waiting for you to sign in", .wifi: "Waiting for Wi-Fi", .hotspot: "Waiting - this Wi-Fi is a hotspot",
            .lowData: "Waiting - Low Data Mode is on", .room: "Waiting for room - the storage limit is reached",
            .phoneFull: "Waiting for space on this phone",
        ]
        for wait in DownloadWait.allCases {
            #expect(DownloadWords.wait(wait) == expected[wait])
            #expect(DownloadWords.albumLine(.waiting(wait, here: 0, of: 3)) == expected[wait], "the album's line is the wait")
            #expect(DownloadWords.songLine(.waiting(wait)) == expected[wait], "and the song's")
            #expect(DownloadWords.tileLine(.waiting(wait, here: 0, of: 3), songCount: 3) == "Waiting")
        }
    }

    @Test func theWaitsASettingCausesNameIt() {
        for wait in DownloadWait.allCases {
            let line = DownloadWords.waitSetting(wait, limit: .gb20)
            #expect((line != nil) == wait.isTheSettings, "\(wait)")
        }
        #expect(DownloadWords.waitSetting(.wifi, limit: .gb20) == "Download over is Wi-Fi only - in You > Downloads.")
        #expect(DownloadWords.waitSetting(.hotspot, limit: .gb20) == "Download over is Wi-Fi only - in You > Downloads.")
        #expect(DownloadWords.waitSetting(.room, limit: .gb20) == "The storage limit is 20 GB - in You > Downloads.")
        #expect(DownloadWords.controlMenuTitle(.waiting(.wifi, here: 0, of: 12), limit: .gb20, bytesHere: 0)
                == "Waiting for Wi-Fi\nDownload over is Wi-Fi only - in You > Downloads.")
        #expect(DownloadWords.controlMenuTitle(.waiting(.queued, here: 0, of: 12), limit: .gb20, bytesHere: 0) == "Waiting to download")
        #expect(DownloadWords.controlMenuTitle(.downloaded(checking: false), limit: .gb20, bytesHere: 412_000_000) == "Downloaded \u{00B7} 412 MB")
        #expect(DownloadWords.controlMenuTitle(.downloading(here: 4, of: 12, fraction: 0.3), limit: .gb20, bytesHere: 0)
                == "Downloading - 4 of 12 songs")
        #expect(DownloadWords.controlMenuTitle(.failed(count: 2, first: .unsaved), limit: .gb20, bytesHere: 0,
                                               firstFailure: "This phone couldn't save it.")
                == "2 songs didn't download\nThis phone couldn't save it.")
    }

    @Test func aSongsAndATilesWords() {
        #expect(DownloadWords.songLine(.none) == nil)
        #expect(DownloadWords.songLine(.fetching(0.4)) == "Downloading, 40 percent")
        #expect(DownloadWords.songLine(.done(.unchecked)) == "Downloaded")
        #expect(DownloadWords.songLine(.failed(.wrongSize)) == "Didn't download")
        #expect(DownloadWords.tileLine(.none, songCount: 12) == nil)
        #expect(DownloadWords.tileLine(.partial(here: 3, of: 12), songCount: 12) == "3 of 12 songs")
        #expect(DownloadWords.tileLine(.downloading(here: 1, of: 12, fraction: 0.1), songCount: 12) == "Downloading")
        #expect(DownloadWords.tileLine(.failed(count: 1, first: .unsaved), songCount: 12) == "Didn't download")
        #expect(DownloadWords.tileLine(.downloaded(checking: false), songCount: 12) == "12 songs")
        #expect(DownloadWords.tileSpoken(.downloaded(checking: false)) == "Downloaded")
        #expect(DownloadWords.tileSpoken(.partial(here: 1, of: 2)) == "Partly downloaded")
        #expect(DownloadWords.tileSpoken(.downloading(here: 0, of: 2, fraction: 0)) == "Downloading")
        #expect(DownloadWords.tileSpoken(.waiting(.wifi, here: 0, of: 2)) == "Waiting to download")
        #expect(DownloadWords.tileSpoken(.failed(count: 1, first: .unsaved)) == "Didn't download")
        #expect(DownloadWords.tileSpoken(.none) == nil)
        #expect(DownloadWords.tileSpoken(.none, notHere: true) == "Not on this phone")
    }

    @Test func theMarks() {
        #expect(DownloadWords.mark(.none, control: true) == .control && DownloadWords.mark(.none) == nil)
        #expect(DownloadWords.mark(.partial(here: 1, of: 2), control: true) == .control, "a partial album's control downloads the rest")
        #expect(DownloadWords.mark(.partial(here: 1, of: 2)) == .downloaded, "a tile's: one mark for downloaded and partly")
        #expect(DownloadWords.mark(.waiting(.wifi, here: 0, of: 1)) == .waiting)
        #expect(DownloadWords.mark(.downloading(here: 0, of: 1, fraction: 0)) == .ring)
        #expect(DownloadWords.mark(.failed(count: 1, first: .unsaved)) == .failed)
        #expect(DownloadWords.mark(.downloaded(checking: true)) == .downloaded)
        #expect(DownloadWords.Mark.waiting.rawValue == "arrow.down.circle.dotted" && DownloadWords.Mark.failed.rawValue == "exclamationmark.circle.fill")
        #expect(DownloadWords.mark(.done(.matched)) == .downloaded && DownloadWords.mark(SongDownload.none) == nil)
    }

    @Test func theAlbumPagesLines() {
        #expect(DownloadWords.footer(here: 12, of: 12, bytes: 412_000_000) == "412 MB on this phone")
        #expect(DownloadWords.footer(here: 3, of: 12, bytes: 92_000_000) == "3 of 12 songs on this phone \u{00B7} 92 MB")
        #expect(DownloadWords.footer(here: 0, of: 12, bytes: 0) == nil)
        #expect(DownloadWords.removed("Dummy") == "Removed from this phone: Dummy")
        #expect(DownloadWords.downloadingSong("Roads") == "Downloading: Roads")
        #expect(DownloadWords.downloadingUpNext(23) == "Downloading 23 songs from Up Next")
        #expect(DownloadWords.downloadingUpNext(1) == "Downloading 1 song from Up Next")
        #expect(DownloadWords.ended("Dummy", failed: 0) == "Downloaded Dummy")
        #expect(DownloadWords.ended("Dummy", failed: 2) == "Dummy: 2 songs didn't download")
    }

    @Test func whyASongDidntDownload() {
        let server = try? ServerAddress.parse("10.0.0.2:8090").get()
        let gone = DownloadWords.failure(.answered(status: 404, detail: "Not Found"), songID: "s1", server: server, admin: false)
        #expect(gone.text == "This song isn't on deadwax any more.")
        let offline = DownloadWords.failure(.offline(reason: "The network connection was lost."), songID: "s1", server: server, admin: false)
        #expect(offline.text == "Can't connect to deadwax." && offline.detail == nil)
        let timeout = DownloadWords.failure(.timeout(reason: "slow"), songID: "s1", server: server, admin: true)
        #expect(timeout.text == "That took too long." && timeout.detail == "slow")
        #expect(DownloadWords.failure(.answered(status: 401, detail: nil), songID: "s", server: server, admin: false).text
                == "Your sign-in has ended - sign in again.")
        #expect(DownloadWords.failure(.answered(status: 503, detail: nil), songID: "s", server: server, admin: false).text
                == "Can't reach the music server right now.", "the stream's route is the music server's")
        let own = DownloadWords.failure(.wrongSize, songID: "s", server: server, admin: false)
        #expect(own.text == "The copy kept arriving the wrong size.")
        #expect(own.advice == "Try again - if it keeps happening, tell whoever runs deadwax." && own.detail == nil)
        let admins = DownloadWords.failure(.soundMismatch, songID: "s", server: server, admin: true)
        #expect(admins.text == "The copy's sound didn't match the original." && admins.advice == "Try again." && admins.detail != nil)
        #expect(DownloadWords.failure(.unreadable, songID: "s", server: nil, admin: false).text == "This phone couldn't read the copy.")
        #expect(DownloadWords.failure(.unsaved, songID: "s", server: nil, admin: false).text == "This phone couldn't save it.")
    }

    @Test func infosPlaysFromAndDebugs() {
        #expect(DownloadWords.playsFrom(.matched, isFLAC: true) == "This phone - checked")
        #expect(DownloadWords.playsFrom(.bySize, isFLAC: false) == "This phone - checked", "an MP3's size is all it allows")
        #expect(DownloadWords.playsFrom(.bySize, isFLAC: true) == "This phone - checked by size")
        #expect(DownloadWords.playsFrom(.unchecked, isFLAC: true) == "This phone - not checked yet")
        #expect(DownloadWords.playsFrom(nil, isFLAC: true) == "Streamed from deadwax")
        let record = DownloadRecord(id: "s", albumID: "a", suffix: "flac", state: .done, check: .matched,
                                    flac: FLACFacts(rate: 96_000, bits: 24, md5: "4f1c00000000000000000000000000e2"), wantedAt: 1)
        #expect(DownloadWords.debugOnPhone(record, channels: 2) == "matched - MD5 4f1c\u{2026}e2, 24-bit 96 kHz, 2 ch")
        #expect(DownloadWords.debugOnPhone(nil) == "not kept")
    }

    @Test func youAndTheDownloadsScreen() {
        #expect(DownloadWords.youFooter(fetching: 2, toGo: 6, firstWait: .wifi, failed: 1)! == ("Downloading - 6 songs to go", false))
        #expect(DownloadWords.youFooter(fetching: 0, toGo: 6, firstWait: .wifi, failed: 1)! == ("Waiting for Wi-Fi", false))
        #expect(DownloadWords.youFooter(fetching: 0, toGo: 0, firstWait: nil, failed: 2)! == ("2 songs didn't download", true))
        #expect(DownloadWords.youFooter(fetching: 0, toGo: 0, firstWait: nil, failed: 0) == nil, "You stays calm")
        #expect(DownloadWords.used(2_100_000_000, limit: .gb20) == ("2.1 GB", " of 20 GB"))
        #expect(DownloadWords.used(2_100_000_000, limit: .none) == ("2.1 GB", " downloaded"))
        #expect(DownloadWords.usageLine(albums: 12, songs: 148, free: 41_200_000_000) == "12 albums \u{00B7} 148 songs \u{00B7} 41.2 GB free on this phone")
        #expect(DownloadWords.usageLine(albums: 1, songs: 1, free: 41_200_000_000) == "1 album \u{00B7} 1 song \u{00B7} 41.2 GB free on this phone")
        #expect(DownloadWords.usageLine(albums: 0, songs: 0, free: 41_200_000_000) == "41.2 GB free on this phone")
        #expect(DownloadWords.overLimit(.gb10) == "More than the 10 GB limit - nothing is removed for it, but new downloads wait for room.")
        #expect(DownloadWords.usageSpoken(2_100_000_000, limit: .gb20, free: 41_200_000_000) == "2.1 GB of 20 GB used, 41.2 GB free on this phone")
        #expect(DownloadWords.removeOthersMessage(1_200_000_000).hasPrefix("1.2 GB of music downloaded by other accounts"))
        #expect(DownloadWords.over(.wifi).name == "Wi-Fi only" && DownloadWords.over(.any).name == "Wi-Fi and cellular")
        let cellular = NetworkPath(satisfied: true, cellular: true, expensive: true)
        #expect(DownloadWords.overNow(cellular, setting: .wifi) == "On mobile data now - downloads wait for Wi-Fi.")
        #expect(DownloadWords.overNow(cellular, setting: .any) == "On mobile data now - downloads use it.")
        #expect(DownloadWords.overNow(.wifiAtHome, setting: .wifi) == "On Wi-Fi now.")
        #expect(DownloadWords.overNow(NetworkPath(satisfied: true, wifi: true, expensive: true), setting: .wifi)
                == "On a hotspot now - downloads wait until you're off it.")
        #expect(DownloadWords.overNow(NetworkPath(satisfied: true, wifi: true, constrained: true), setting: .any)
                == "Low Data Mode is on - downloads use it.")
        #expect(DownloadWords.overNow(.none, setting: .any) == "No connection now.")
        #expect(DownloadWords.downloadingRow(here: 4, of: 12, wait: nil, onlySong: nil) == "4 of 12 songs")
        #expect(DownloadWords.downloadingRow(here: 4, of: 12, wait: .queued, onlySong: nil) == "4 of 12 songs")
        #expect(DownloadWords.downloadingRow(here: 0, of: 1, wait: nil, onlySong: "Roads") == "Roads", "never 1 of 1 song")
        #expect(DownloadWords.downloadingRow(here: 4, of: 12, wait: .wifi, onlySong: nil) == "Waiting for Wi-Fi")
        #expect(DownloadWords.downloadedRow(here: 12, of: 12, bytes: 412_000_000) == "12 songs \u{00B7} 412 MB")
        #expect(DownloadWords.downloadedRow(here: 3, of: 12, bytes: 92_000_000) == "3 of 12 songs \u{00B7} 92 MB")
        #expect(DownloadWords.verdict(.checked) == "Checked" && DownloadWords.verdict(.bySize) == "Checked by size")
        #expect(DownloadWords.verdict(.checking) == "Checking\u{2026}")
        #expect(DownloadWords.removeAllMessage(songs: 148, bytes: 2_100_000_000)
                == "148 songs (2.1 GB) go from this phone. They stay in the collection, and you can download them again.")
    }

    @Test func offlinesWords() {
        #expect(DownloadWords.banner(.online) == nil)
        #expect(DownloadWords.banner(.noNetwork)?.line == "Offline - showing what's on this phone")
        #expect(DownloadWords.banner(.noNetwork)?.symbol == "wifi.slash")
        #expect(DownloadWords.banner(.unreachable)?.line == "Can't reach deadwax - showing what's on this phone")
        #expect(DownloadWords.banner(.unreachable)?.symbol == "wifi.exclamationmark")
        #expect(DownloadWords.banner(.unreachable)?.more == "Check you're on the right network (or your VPN is on).")
        #expect(DownloadWords.skippedNotHere(title: "Roads") == "Skipped \"Roads\" - it isn't on this phone")
        #expect(DownloadWords.skippedNotHere(count: 3) == "Skipped 3 songs that aren't on this phone")
        #expect(DownloadWords.stoppedNotHere == "Not on this phone - it plays once deadwax is back.")
    }

    @Test func noLineHoldsAWordAListenerNeverReads() {
        // the vocabulary sim's rule (ui/test/vocabulary.sim.cjs), ported for these words
        let banned = ["Navidrome", "the store", "cache", "sync", "MD5", "offline mode", "everything", "checksum", "Browse"]
        let lines = DownloadWords.everyLine
        #expect(lines.count > 80)
        for line in lines {
            for word in banned { #expect(!line.localizedCaseInsensitiveContains(word), "\"\(line)\" says \(word)") }
            #expect(!line.isEmpty)
        }
    }
}
