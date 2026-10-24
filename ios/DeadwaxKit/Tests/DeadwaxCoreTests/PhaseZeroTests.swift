import Foundation
import Testing
@testable import DeadwaxCore

@Suite struct CheckReportTests {
    let ok = Health(status: "ok", version: "2.0.0", poller: "running")

    @Test func loginsOffSaysTheSharedAccount() {
        let report = CheckReport.from(health: .success(ok), me: .success(Me(user: "local", admin: true, auth: "off")))
        #expect(report.ok && !report.needsSignIn)
        #expect(report.lines == ["deadwax 2.0.0 answered: OK.",
                                 "Logins are off: everyone uses the shared account (local)."])
    }

    @Test func loginsOnSaysWho() {
        let report = CheckReport.from(health: .success(ok), me: .success(Me(user: "james", admin: true, auth: "on")))
        #expect(report.lines.last == "Logins are on: signed in as james, an admin.")
        let ethan = CheckReport.from(health: .success(ok), me: .success(Me(user: "ethan", admin: false, auth: "on")))
        #expect(ethan.lines.last == "Logins are on: signed in as ethan.")
    }

    @Test func a401IsASignInToDo() {
        let report = CheckReport.from(health: .success(ok), me: .failure(.signedOut("Sign in.")))
        #expect(report.needsSignIn && !report.ok)
        #expect(report.lines.last?.hasPrefix("Logins are on, and this phone isn't signed in.") == true)
    }

    @Test func nothingAnsweringIsOneLine() {
        let report = CheckReport.from(health: .failure(.unreachable("Couldn't reach deadwax.")), me: nil)
        #expect(report.lines == ["Couldn't reach deadwax."])
        #expect(!report.ok)
    }

    @Test func aStoppedPollerIsSaid() {
        let sick = Health(status: "unhealthy", version: "2.0.0", poller: "stopped")
        let report = CheckReport.from(health: .success(sick), me: .success(Me(user: "local", admin: true, auth: "off")))
        #expect(report.lines.first?.contains("download poller has stopped") == true)
    }
}

@Suite struct TestSoundsTests {
    @Test func theAlbumsSongsInOrder() {
        let songs = [
            Song(id: "x", title: "Start test", album: "Other", artist: "Someone", track: 1),
            Song(id: "3", title: "Three beeps, the first at 0.2 s", album: "Start test", artist: "deadwax test", track: 3),
            Song(id: "1", title: "Three beeps, the first at 0.0 s", album: "start test ", artist: "deadwax test", track: 1),
            Song(id: "2", title: "Three beeps, the first at 0.1 s", album: "Start test", artist: "Deadwax Test", track: 2),
            Song(id: "1", title: "Three beeps, the first at 0.0 s", album: "Start test", artist: "deadwax test", track: 1),
            Song(id: "y", title: "Start", album: "Start test", artist: "a covers band", track: 1),
        ]
        #expect(TestSounds.pick(songs).map(\.id) == ["1", "2", "3"])
    }

    @Test func discsComeBeforeTracks() {
        let songs = [
            Song(id: "b", album: "Start test", track: 1, discNumber: 2),
            Song(id: "a", album: "Start test", track: 2, discNumber: 1),
        ]
        #expect(TestSounds.pick(songs).map(\.id) == ["a", "b"])
    }
}

@Suite struct HiResTests {
    @Test func twentyFourOneNinetyTwoFirst() {
        let songs = [
            Song(id: "cd", suffix: "flac", samplingRate: 44_100, bitDepth: 16),
            Song(id: "96", suffix: "flac", samplingRate: 96_000, bitDepth: 24),
            Song(id: "192-16", suffix: "flac", samplingRate: 192_000, bitDepth: 16),
            Song(id: "192", suffix: "FLAC", samplingRate: 192_000, bitDepth: 24),
            Song(id: "dsd", suffix: "dsf", samplingRate: 2_822_400, bitDepth: 1),
        ]
        #expect(HiRes.best(songs)?.id == "192")
        #expect(HiRes.isTwentyFourOneNinetyTwo(HiRes.best(songs)!))
    }

    @Test func otherwiseTheHighestRateAbove48() {
        let songs = [
            Song(id: "88", suffix: "flac", samplingRate: 88_200, bitDepth: 24),
            Song(id: "176", suffix: "flac", samplingRate: 176_400, bitDepth: 24),
            Song(id: "96", suffix: "flac", samplingRate: 96_000, bitDepth: 24),
        ]
        #expect(HiRes.best(songs)?.id == "176")
        #expect(!HiRes.isTwentyFourOneNinetyTwo(HiRes.best(songs)!))
    }

    @Test func twentyFourOneNinetyTwoBeatsHigherRates() {
        let songs = [
            Song(id: "352", suffix: "flac", samplingRate: 352_800, bitDepth: 24),
            Song(id: "384", suffix: "flac", samplingRate: 384_000, bitDepth: 32),
            Song(id: "192", suffix: "flac", samplingRate: 192_000, bitDepth: 24),
        ]
        #expect(HiRes.best(songs)?.id == "192")
        #expect(HiRes.best(Array(songs.reversed()))?.id == "192")
    }

    @Test func otherwiseTheHighestRateThenTheMostBits() {
        let songs = [
            Song(id: "96-24", suffix: "flac", samplingRate: 96_000, bitDepth: 24),
            Song(id: "176-16", suffix: "flac", samplingRate: 176_400, bitDepth: 16),
            Song(id: "88-24", suffix: "flac", samplingRate: 88_200, bitDepth: 24),
        ]
        #expect(HiRes.best(songs)?.id == "176-16")
        let sameRate = [Song(id: "96-16", suffix: "flac", samplingRate: 96_000, bitDepth: 16),
                        Song(id: "96-24", suffix: "flac", samplingRate: 96_000, bitDepth: 24)]
        #expect(HiRes.best(sameRate)?.id == "96-24")
        #expect(HiRes.best(Array(sameRate.reversed()))?.id == "96-24")
    }

    @Test func noneWithoutAFlacAbove48OrWithoutRates() {
        #expect(HiRes.best([Song(id: "cd", suffix: "flac", samplingRate: 48_000, bitDepth: 24)]) == nil)
        #expect(HiRes.best([Song(id: "unknown", suffix: "flac")]) == nil)
        #expect(HiRes.best([Song(id: "m4a", suffix: "m4a", samplingRate: 96_000)]) == nil)
    }
}

@Suite struct InstallExpiryTests {
    static let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Name</key><string>iOS Team Provisioning Profile: net.lizardlounge.deadwax</string>
        <key>TeamName</key><string>James Barnett</string>
        <key>CreationDate</key><date>2026-10-23T14:02:00Z</date>
        <key>ExpirationDate</key><date>2026-10-30T14:02:00Z</date>
    </dict>
    </plist>
    """

    /// A profile as it is on disk: the plist inside a signed envelope's binary bytes.
    static func envelope(_ inner: String) -> Data {
        var data = Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x80])
        data.append(Data(inner.utf8))
        data.append(Data([0x00, 0x00, 0xA0, 0x82, 0x0A, 0x31, 0x3C, 0x2F, 0x00]))
        return data
    }

    @Test func theDatesAreReadOutOfTheEnvelope() throws {
        let profile = try #require(ProvisioningProfile.parse(Self.envelope(Self.plist)))
        #expect(profile.teamName == "James Barnett")
        #expect(profile.expiration == Date(timeIntervalSince1970: 1_793_368_920))
        #expect(profile.creation == Date(timeIntervalSince1970: 1_793_368_920 - 7 * 86_400))
    }

    @Test func noPlistIsNoProfile() {
        #expect(ProvisioningProfile.parse(Data([1, 2, 3])) == nil)
        #expect(ProvisioningProfile.parse(Self.envelope("<?xml version=\"1.0\"?><plist><dict></dict></plist>")) == nil)
    }

    @Test func theLineInTheCorner() {
        let utc = TimeZone(identifier: "UTC")!
        let end = Date(timeIntervalSince1970: 1_793_368_920) // Fri 30 Oct 2026, 14:02 UTC
        let now = end.addingTimeInterval(-6 * 86_400)
        #expect(InstallExpiry.line(expiration: end, now: now, timeZone: utc) == "This install runs until Fri 30 Oct, 14:02")
        #expect(InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-86_400), timeZone: utc)
                == "This install runs until Fri 30 Oct, 14:02. Run install.sh on the Mac before then.")
        #expect(InstallExpiry.line(expiration: end, now: end.addingTimeInterval(60), timeZone: utc)
                == "This install ran out on Fri 30 Oct, 14:02. Run install.sh on the Mac to put it back.")
        #expect(InstallExpiry.line(expiration: nil, now: now).hasPrefix("No install date to show"))
    }

    @Test func theTimeIsThePhonesOwnZone() {
        let end = Date(timeIntervalSince1970: 1_793_368_920)
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(InstallExpiry.format(end, timeZone: newYork) == "Fri 30 Oct, 10:02")
    }
}

@Suite struct PlayQueueTests {
    let songs = (1...3).map { Song(id: "\($0)") }

    @Test func previousPastThreeSecondsRestarts() {
        let queue = PlayQueue(songs: songs, index: 1)
        #expect(queue.previous(at: 3.01) == .restart)
        #expect(queue.previous(at: 3.0) == .go(0))
        #expect(queue.previous(at: 0.5) == .go(0))
    }

    @Test func theFirstSongOnlyRestarts() {
        #expect(PlayQueue(songs: songs, index: 0).previous(at: 0) == .restart)
    }

    @Test func nextStopsAtTheEnd() {
        #expect(PlayQueue(songs: songs, index: 1).nextIndex == 2)
        #expect(PlayQueue(songs: songs, index: 2).nextIndex == nil)
    }

    @Test func anIndexOutsideIsHeldInside() {
        #expect(PlayQueue(songs: songs, index: 9).index == 2)
        #expect(PlayQueue(songs: [], index: 4).current == nil)
        var queue = PlayQueue(songs: songs)
        queue.move(to: 7)
        #expect(queue.index == 0)
    }
}
