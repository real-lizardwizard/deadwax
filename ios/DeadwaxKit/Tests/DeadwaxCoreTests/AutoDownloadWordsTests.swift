import Foundation
import Testing
@testable import DeadwaxCore

// Download your library in a listener's words (phase3-autodownload.md 1.2, slice 2): every line, and the ban list over
// them.

private let gb: Int64 = 1_000_000_000

private func plan(_ sizes: [Int64], limit: StorageLimit, free: Int64 = 10_000 * gb) -> LibraryFill.Plan {
    LibraryFill.plan(sizes.enumerated().map { LibraryFill.AlbumFacts(id: "a\($0)", bytes: $1) },
                     .init(limit: limit.bytes, freeSpace: free))
}

@Suite struct AutoDownloadWordsTests {
    @Test func theSwitchAndItsNoteByScope() {
        #expect(AutoDownloadWords.switchName(.yours) == "Download your library")
        #expect(AutoDownloadWords.switchName(.store) == "Download the collection")
        #expect(AutoDownloadWords.note(.yours).hasPrefix("Keeps your library on this phone, newest first"))
        #expect(AutoDownloadWords.note(.store)
                == "Keeps the collection on this phone, newest first, as much as fits in the storage limit.")
        #expect(AutoDownloadWords.header(.yours) == "Your library" && AutoDownloadWords.header(.store) == "The collection")
    }

    @Test func theFitLine() {
        let all = plan(Array(repeating: 400_000_000, count: 212), limit: .gb100)
        #expect(AutoDownloadWords.fit(all, limit: .gb100, bytes: all.bytes) == "All 212 albums fit in 100 GB.")
        // 99 MB each: 200 of them leave the 200 MB a new album must leave spare under 20 GB
        let some = plan(Array(repeating: 99_000_000, count: 3_010), limit: .gb20)
        #expect(some.fit == 200)
        #expect(AutoDownloadWords.fit(some, limit: .gb20, bytes: some.bytes)
                == "200 of 3,010 albums fit in 20 GB. Raise the limit or download fewer.")
        let none = plan(Array(repeating: 50 * gb, count: 3), limit: .none, free: 10_000 * gb)
        #expect(AutoDownloadWords.fit(none, limit: .none, bytes: none.bytes) == "All 3 albums, 150 GB.")
        let phone = plan(Array(repeating: 4 * gb, count: 3_010), limit: .none, free: 42_100_000_000)
        #expect(AutoDownloadWords.fit(phone, limit: .none, bytes: phone.bytes) == "10 of 3,010 albums fit on this phone.")
        // the limit not reached, the phone short as well
        let both = plan([5 * gb, 5 * gb, 5 * gb, 30 * gb], limit: .gb20, free: 12_200_000_000)
        #expect(AutoDownloadWords.fit(both, limit: .gb20, bytes: both.bytes)
                == "2 of 4 albums fit in 20 GB - 1 wait for space on this phone. Raise the limit or download fewer.")
        #expect(AutoDownloadWords.fit(plan([], limit: .gb20), limit: .gb20, bytes: 0) == "Nothing to download yet.")
        #expect(AutoDownloadWords.fit(plan([gb], limit: .gb20), limit: .gb20, bytes: gb) == "The 1 album fits in 20 GB.")
    }

    @Test func readingAndChecked() {
        #expect(AutoDownloadWords.reading(.yours, read: 1_240, of: 3_010) == "Reading your library - 1,240 of 3,010 albums")
        #expect(AutoDownloadWords.reading(.store, read: 1, of: 1) == "Reading the collection - 1 of 1 album")
        let now: Int64 = 1_800_000_000_000
        let utc = TimeZone(identifier: "UTC")!
        #expect(AutoDownloadWords.checked(nil, now: now) == "Not checked yet")
        #expect(AutoDownloadWords.checked(now - 59_000, now: now) == "Checked just now")
        #expect(AutoDownloadWords.checked(now + 9_000, now: now) == "Checked just now", "a clock ahead isn't the future")
        #expect(AutoDownloadWords.checked(now - 60_000, now: now) == "Checked 1 minute ago")
        #expect(AutoDownloadWords.checked(now - 3 * 60_000, now: now) == "Checked 3 minutes ago")
        // 1_800_000_000_000 is 2027-01-15 08:00 UTC
        #expect(AutoDownloadWords.checked(now - 2 * 3_600_000, now: now, zone: utc) == "Checked at 06:00")
        #expect(AutoDownloadWords.checked(now - 26 * 3_600_000, now: now, zone: utc) == "Checked 14 Jan at 06:00")
    }

    @Test func theQuestions() {
        #expect(AutoDownloadWords.question(.empty(kept: 212), scope: .yours, here: 212)
                == "deadwax says your library is empty. Remove the 212 albums downloaded with it from this phone?")
        #expect(AutoDownloadWords.question(.drop(gone: 1_240, of: 3_010), scope: .yours, here: 9)
                == "deadwax's list of your library lost 1,240 of 3,010 albums at once. Remove them from this phone?")
        #expect(AutoDownloadWords.question(.empty(kept: 1), scope: .store, here: 1)
                == "deadwax says the collection is empty. Remove the 1 album downloaded with it from this phone?")
        #expect(AutoDownloadWords.question(.truncated, scope: .yours, here: 3) == nil)
        #expect(AutoDownloadWords.keepThem == "Keep Them" && AutoDownloadWords.remove == "Remove")
    }

    @Test func downloadingsRow() {
        let progress = LibraryDownloads.Progress(toGo: 38, of: 412, bytes: 12_400_000_000)
        #expect(AutoDownloadWords.downloadingTitle(.yours) == "Your library")
        #expect(AutoDownloadWords.downloadingRow(progress) == "38 of 412 albums to go \u{00B7} 12.4 GB")
        #expect(AutoDownloadWords.downloadingSpoken(.yours, progress)
                == "Your library, 38 of 412 albums to go, 12.4 GB, 90 percent")
        #expect(AutoDownloadWords.youFooter(.store, progress) == "The collection: 38 of 412 albums to go")
    }

    @Test func theAlbumPageAndRemoveAll() {
        #expect(AutoDownloadWords.waitsForRoom(.yours, limit: .gb20)
                == "Your library doesn't all fit in 20 GB - this one waits for room.")
        #expect(AutoDownloadWords.waitsForRoom(.store, limit: .none)
                == "The collection doesn't all fit on this phone - this one waits for space.")
        #expect(AutoDownloadWords.keptOff(.yours) == "You removed this download - your library leaves it off this phone.")
        #expect(AutoDownloadWords.menuTitle(.yours) == "Downloaded with your library")
        #expect(AutoDownloadWords.controlMenuTitle(.store, bytesHere: 412_000_000) == "Downloaded with the collection\n412 MB")
        #expect(AutoDownloadWords.goesToo == "Its download goes from this phone too.")
        #expect(AutoDownloadWords.removeAllToo(.yours)
                == "Download your library is turned off too, or it would download them again.")
    }

    @Test func theFirstAsk() {
        #expect(AutoDownloadWords.askTitle(.yours) == "Keep your library on this phone?")
        #expect(AutoDownloadWords.askLine(.yours, limit: .gb20)
                == "deadwax can download your library, newest first, as much as fits in 20 GB, and keep it in step as you add and remove albums.")
        #expect(AutoDownloadWords.askLine(.store, limit: .none).contains("as much as fits on this phone"))
        #expect(AutoDownloadWords.turnOn == "Turn On" && AutoDownloadWords.notNow == "Not Now")
    }

    @Test func noLineSaysAWordAListenerNeverReads() {
        let banned = ["Navidrome", "the store", "cache", "sync", "MD5", "offline mode", "everything", "checksum", "Browse"]
        let lines = AutoDownloadWords.everyLine
        #expect(lines.count > 40)
        for line in lines {
            #expect(!line.isEmpty)
            for word in banned { #expect(!line.localizedCaseInsensitiveContains(word), "\"\(line)\" says \(word)") }
        }
    }
}
