import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac app's words (notes/ios.md "The Mac app, slice 4: the Mac's words"): every word the app shows that says
/// phone or iPhone - and every word made from one of them - by name, with the arguments that reach each way it can be
/// said. Fixtures/words/iphone.json is what each said on the iPhone at c97a824, before the Mac's words were made: the
/// phones' words don't change (check 438), and this holds them to it, word for word.
///
/// The App's own literals that became Core's words (Debug's, the downloads log's, the address screen's) are listed
/// under `App.`: at c97a824 their values copied from the App's source as it was, and since then Core's word for each
/// (DebugWords, AddressWords, LibraryFollowWords' log lines, DownloadWords.notHereUnreached).
///
/// Fixtures/words/mac.json is every one of them as the Mac says it - written by `DEADWAX_WORDS_WRITE=mac` when a Mac word
/// is changed on purpose, and read in review: it is the one place every word the Mac says differently is seen at once.
enum DeviceWords {
    /// Every word, by name, as `device` says it.
    static func all(_ device: Device) -> [(String, String)] {
        var w: [(String, String)] = []
        func add(_ key: String, _ value: String?) { w.append((key, value ?? "<nil>")) }
        let server = try! ServerAddress.parse("http://192.168.1.20:8090").get()
        let reasons = DownloadWait.allCases
        let albums: [(String, AlbumDownload)] = [
            ("none", .none), ("partial", .partial(here: 3, of: 12)),
            ("downloading", .downloading(here: 4, of: 12, fraction: 0.4)),
            ("failed", .failed(count: 2, first: .wrongSize)), ("downloaded", .downloaded(checking: false)),
            ("checking", .downloaded(checking: true)),
        ] + reasons.map { ("waiting.\($0.rawValue)", AlbumDownload.waiting($0, here: 3, of: 12)) }
        let songs: [(String, SongDownload)] = [
            ("none", .none), ("fetching", .fetching(0.4)), ("done", .done(.matched)), ("failed", .failed(.unreadable)),
        ] + reasons.map { ("waiting.\($0.rawValue)", SongDownload.waiting($0)) }

        // MARK: Settings

        add("YouWords.kept", YouWords.kept(device))
        add("YouWords.thisPhone", YouWords.thisDevice(device))

        // MARK: Downloads

        add("DownloadWords.notOnPhone", DownloadWords.notOnDevice(device))
        for (name, album) in albums {
            add("DownloadWords.tileSpoken(\(name))", DownloadWords.tileSpoken(album, device: device))
            add("DownloadWords.tileSpoken(\(name), notHere)", DownloadWords.tileSpoken(album, notHere: true, device: device))
            add("DownloadWords.albumLine(\(name))", DownloadWords.albumLine(album, device: device))
            add("DownloadWords.controlValue(\(name))", DownloadWords.controlValue(album, device: device))
            for limit in [StorageLimit.gb20, .none] {
                add("DownloadWords.controlMenuTitle(\(name), \(limit.rawValue))",
                    DownloadWords.controlMenuTitle(album, limit: limit, bytesHere: 412_000_000, firstFailure: "It broke.",
                                                   device: device))
            }
            add("PlaylistDownloadWords.heroLine(\(name))", PlaylistDownloadWords.heroLine(album, device: device))
            add("PlaylistDownloadWords.heroLine(\(name), smart)", PlaylistDownloadWords.heroLine(album, smart: true, device: device))
            add("AlbumInfo.onPhone(\(name))", Self.row(AlbumInfo.onPhone(album, here: 3, of: 12, bytes: 92_000_000, device: device)))
        }
        for (name, song) in songs {
            add("DownloadWords.songLine(\(name))", DownloadWords.songLine(song, device: device))
        }
        for reason in reasons {
            add("DownloadWords.wait(\(reason.rawValue))", DownloadWords.wait(reason, device: device))
            add("DownloadWords.youFooter(\(reason.rawValue))",
                DownloadWords.youFooter(fetching: 0, toGo: 0, firstWait: reason, failed: 0, device: device)?.text)
            add("DownloadWords.downloadingRow(\(reason.rawValue))",
                DownloadWords.downloadingRow(here: 4, of: 12, wait: reason, onlySong: nil, device: device))
            let progress = PlaylistDownloads.Progress(toGo: 3, of: 12)
            add("PlaylistDownloadWords.downloadingRow(\(reason.rawValue))",
                PlaylistDownloadWords.downloadingRow(progress, wait: reason, device: device))
            add("PlaylistDownloadWords.downloadingSpoken(\(reason.rawValue))",
                PlaylistDownloadWords.downloadingSpoken("Late night", progress, wait: reason, device: device))
        }
        add("DownloadWords.youFooter(fetching)",
            DownloadWords.youFooter(fetching: 1, toGo: 6, firstWait: nil, failed: 0, device: device)?.text)
        add("DownloadWords.youFooter(failed)",
            DownloadWords.youFooter(fetching: 0, toGo: 0, firstWait: nil, failed: 2, device: device)?.text)
        add("DownloadWords.downloadingRow(nil)", DownloadWords.downloadingRow(here: 4, of: 12, wait: nil, onlySong: nil, device: device))
        add("DownloadWords.downloadingRow(nil, Roads)",
            DownloadWords.downloadingRow(here: 0, of: 1, wait: nil, onlySong: "Roads", device: device))
        add("DownloadWords.footer(0 of 10)", DownloadWords.footer(here: 0, of: 10, bytes: 0, device: device))
        add("DownloadWords.footer(10 of 10)", DownloadWords.footer(here: 10, of: 10, bytes: 412_000_000, device: device))
        add("DownloadWords.footer(3 of 12)", DownloadWords.footer(here: 3, of: 12, bytes: 92_000_000, device: device))
        add("DownloadWords.albumGoneHere", DownloadWords.albumGoneHere(device))
        add("DownloadWords.albumNotHere", DownloadWords.albumNotHere(device))
        add("DownloadWords.removed", DownloadWords.removed("Dummy", device: device))
        add("DownloadWords.unreadable", DownloadWords.unreadable(device))
        add("DownloadWords.unsaved", DownloadWords.unsaved(device))
        for (name, failure) in [("unreadable", DownloadFailure.unreadable), ("unsaved", .unsaved), ("wrongSize", .wrongSize),
                                ("offline", .offline(reason: "The network connection was lost."))] {
            for admin in [false, true] {
                let line = DownloadWords.failure(failure, songID: "tr-1", server: server, admin: admin, device: device)
                add("DownloadWords.failure(\(name), admin: \(admin))", "\(line.text) | \(line.advice) | \(line.detail ?? "-")")
            }
        }
        add("DownloadWords.playsFrom(nil)", DownloadWords.playsFrom(nil, isFLAC: true, device: device))
        for check in CopyCheck.allCases {
            for flac in [true, false] {
                add("DownloadWords.playsFrom(\(check.rawValue), flac: \(flac))",
                    DownloadWords.playsFrom(check, isFLAC: flac, device: device))
            }
        }
        add("DownloadWords.onThisPhone", DownloadWords.onThisDevice(device))
        add("DownloadWords.staysAfterSignOut", DownloadWords.staysAfterSignOut(device))
        add("DownloadWords.usageLine", DownloadWords.usageLine(albums: 12, songs: 148, free: 41_200_000_000, device: device))
        add("DownloadWords.usageLine(none)", DownloadWords.usageLine(albums: 0, songs: 0, free: 41_200_000_000, device: device))
        add("DownloadWords.usageSpoken(gb20)",
            DownloadWords.usageSpoken(2_100_000_000, limit: .gb20, free: 41_200_000_000, device: device))
        add("DownloadWords.usageSpoken(none)",
            DownloadWords.usageSpoken(2_100_000_000, limit: .none, free: 41_200_000_000, device: device))
        add("DownloadWords.otherAccounts", DownloadWords.otherAccounts(device))
        add("DownloadWords.removeOthersMessage", DownloadWords.removeOthersMessage(1_200_000_000, device: device))
        add("DownloadWords.overKept", DownloadWords.overKept(device))
        add("DownloadWords.forceQuit", DownloadWords.forceQuit)
        add("DownloadWords.removeAllMessage", DownloadWords.removeAllMessage(songs: 148, bytes: 2_100_000_000, device: device))
        add("DownloadWords.lastFooter", DownloadWords.lastFooter(device))
        add("DownloadWords.storeUnreadable", DownloadWords.storeUnreadable(device))
        for reach in Reach.allCases {
            let banner = DownloadWords.banner(reach, device: device)
            add("DownloadWords.banner(\(reach.rawValue))", banner.map { "\($0.line) | \($0.symbol) | \($0.more)" })
        }
        add("DownloadWords.skippedNotHere(title)", DownloadWords.skippedNotHere(title: "Roads", device: device))
        add("DownloadWords.skippedNotHere(1)", DownloadWords.skippedNotHere(count: 1, device: device))
        add("DownloadWords.skippedNotHere(3)", DownloadWords.skippedNotHere(count: 3, device: device))
        add("DownloadWords.stoppedNotHere", DownloadWords.stoppedNotHere(device))
        for (i, line) in DownloadWords.everyLine(device).enumerated() { add("DownloadWords.everyLine[\(i)]", line) }

        // MARK: Download your library

        let full = LibraryFill.plan([.init(id: "a", bytes: 1_000_000_000), .init(id: "b", bytes: 5_000_000_000),
                                     .init(id: "c", bytes: 5_000_000_000)],
                                    .init(limit: 50_000_000_000, freeSpace: 4_000_000_000))
        let noRoom = LibraryFill.plan([.init(id: "a", bytes: 1_000_000_000), .init(id: "b", bytes: 30_000_000_000)],
                                      .init(limit: StorageLimit.gb20.bytes, freeSpace: 100_000_000_000))
        let noLimit = LibraryFill.plan([.init(id: "a", bytes: 1_000_000_000), .init(id: "b", bytes: 30_000_000_000)],
                                       .init(limit: nil, freeSpace: 25_000_000_000))
        let plans = [("phoneFull", full), ("room", noRoom), ("noLimit", noLimit)]
        for scope in AlbumScope.allCases {
            let s = scope.rawValue
            add("AutoDownloadWords.note(\(s))", AutoDownloadWords.note(scope, device: device))
            add("AutoDownloadWords.chargingNote(\(s))", AutoDownloadWords.chargingNote(scope, device: device))
            for held in [LibraryFollow.Held.empty(kept: 212), .drop(gone: 1_240, of: 3_010), .truncated] {
                add("AutoDownloadWords.question(\(s), \(held))",
                    AutoDownloadWords.question(held, scope: scope, here: 212, device: device))
            }
            for limit in [StorageLimit.gb20, .none] {
                add("AutoDownloadWords.waitsForRoom(\(s), \(limit.rawValue))",
                    AutoDownloadWords.waitsForRoom(scope, limit: limit, device: device))
                add("AutoDownloadWords.askLine(\(s), \(limit.rawValue))", AutoDownloadWords.askLine(scope, limit: limit, device: device))
            }
            add("AutoDownloadWords.keptOff(\(s))", AutoDownloadWords.keptOff(scope, device: device))
            add("AutoDownloadWords.askTitle(\(s))", AutoDownloadWords.askTitle(scope, device: device))
        }
        for (name, plan) in plans {
            for limit in [StorageLimit.gb20, .gb100, .none] {
                add("AutoDownloadWords.fit(\(name), \(limit.rawValue))",
                    AutoDownloadWords.fit(plan, limit: limit, bytes: 1_000_000_000, device: device))
                add("LibraryFollowWords.wouldFit(\(name), \(limit.rawValue))",
                    LibraryFollowWords.wouldFit(plan, limit: limit, device: device))
            }
            add("LibraryFollowWords.fitDetail(\(name))", LibraryFollowWords.fitDetail(plan, device: device))
        }
        add("AutoDownloadWords.goesToo", AutoDownloadWords.goesToo(device))
        add("AutoDownloadWords.offMessage", AutoDownloadWords.offMessage(bytes: 12_400_000_000, device: device))
        add("AutoDownloadWords.keepOffTitle", AutoDownloadWords.keepOffTitle("Dummy", device: device))
        add("LibraryFollowWords.followNote", LibraryFollowWords.followNote(device))
        add("LibraryFollowWords.notFollowing", LibraryFollowWords.notFollowing)
        for (name, held) in [("nil", LibraryFollow.Held?.none), ("empty", .empty(kept: 212)),
                             ("drop", .drop(gone: 1_240, of: 3_010)), ("truncated", .truncated)] {
            add("LibraryFollowWords.held(\(name))", LibraryFollowWords.held(held, device: device))
        }

        // MARK: playlists

        add("PlaylistDownloadWords.removeAllToo(1)", PlaylistDownloadWords.removeAllToo(playlists: 1, device: device))
        add("PlaylistDownloadWords.removeAllToo(3)", PlaylistDownloadWords.removeAllToo(playlists: 3, device: device))
        for (i, line) in PlaylistDownloadWords.everyLine(device).enumerated() { add("PlaylistDownloadWords.everyLine[\(i)]", line) }

        // MARK: Album info

        add("AlbumInfoWords.phoneTitle", AlbumInfoWords.deviceTitle(device))
        let album = try! JSONDecoder().decode(Album.self, from: Data(#"{"id": "al-1", "name": "Dummy", "artist": "Portishead"}"#.utf8))
        let here = AlbumInfo.onPhone(.partial(here: 3, of: 12), here: 3, of: 12, bytes: 92_000_000, device: device)
        add("AlbumInfo.local", AlbumInfo.local(album: album, onPhone: here, device: device).map(\.title).joined(separator: " | "))

        // MARK: the EQ

        add("EQWords.Import.fromFiles", EQWords.Import.fromFiles(device))
        add("EQWords.Import.frequencyHigh", EQWords.Import.frequencyHigh(line: 2, hz: 30_000, device: device).text)
        let centre = [Array("C".unicodeScalars)]
        let rear = [Array("RL".unicodeScalars), Array("RR".unicodeScalars)]
        add("EQWords.Import.channels(C, 12-20)", EQWords.Import.channels(first: 12, last: 20, words: centre, device: device).text)
        add("EQWords.Import.channels(RL RR, 4)", EQWords.Import.channels(first: 4, last: 4, words: rear, device: device).text)
        add("EQWords.Import.channels(none, 4)", EQWords.Import.channels(first: 4, last: 4, words: [], device: device).text)
        let high = "Preamp: -3 dB\nFilter: ON PK Fc 30000 Hz Gain 3 dB Q 1\n"
        let channel = "Preamp: -3 dB\nChannel: C\nFilter: ON PK Fc 1000 Hz Gain 3 dB Q 1\nChannel: L R\nFilter: ON PK Fc 100 Hz Gain 3 dB Q 1\n"
        for (name, text) in [("high", high), ("channel", channel)] {
            switch APOReader.read(Data(text.utf8), device: device) {
            case .success(let reading): add("APOReader.read(\(name))", reading.notes.map(\.text).joined(separator: " | "))
            case .failure(let refusal): add("APOReader.read(\(name))", "refused: \(refusal.text)")
            }
        }
        add("EQWords.You.footer", EQWords.You.footer(device))
        add("EQWords.Screen.unitNotMade", EQWords.Screen.unitNotMade(device))
        add("EQScreenRules.line(unitNotMade)", EQScreenRules.line(on: true, identity: false, preamp: .automatic, played: 0, top: 0,
                                                                  unitNotMade: true, device: device).text)
        add("EQWords.Outputs.speaker", EQWords.Outputs.speaker(device))
        add("EQOutputs.speaker", Self.output(EQOutputs.speaker(device)))
        for port in EQPort.allCases {
            let p = EQRoutePort(port: port, portType: "Type", name: "James's AirPods Pro", uid: "u-1")
            add("EQOutputs.output(\(port.rawValue))", Self.output(EQOutputs.output(p, device: device)))
        }
        add("EQOutputs.output([])", EQOutputs.output([EQRoutePort](), device: device).map(Self.output))
        let speakerPort = EQRoutePort(port: .builtInSpeaker, portType: "Speaker", name: "Speaker", uid: "")
        add("EQOutputs.output([speaker])", EQOutputs.output([speakerPort], device: device).map(Self.output))
        let kept = EQSettings.newOutput(EQOutputs.speaker(device), seen: "")
        add("EQSettings.newOutput(speaker)", "\(kept.key) | \(kept.name) | \(kept.shownName) | \(kept.type.rawValue)")
        add("EQOutputSetting.output(speaker)", Self.output(kept.output(device)))
        let wired = EQOutputs.output(EQRoutePort(port: .headphones, portType: "Headphones", name: "Headphones", uid: ""), device: device)
        add("EQScreenRules.others(wired)", EQScreenRules.others(EQSettings(), shown: wired.key, device: device)
            .map { "\($0.key) | \($0.shownName) | \(Self.output($0.output(device)))" }.joined(separator: " / "))
        add("EQScreenRules.output(speaker)",
            Self.output(EQScreenRules.output("speaker", route: wired, in: EQSettings(), lastDrawn: nil, device: device)))
        add("EQScreenRules.output(speaker, route)", Self.output(EQScreenRules.output("speaker", route: EQOutputs.speaker(device),
                                                                                     in: EQSettings(), lastDrawn: nil,
                                                                                     device: device)))
        let now = EQScreenRules.now(EQSettings(), route: EQOutputs.speaker(device))
        add("EQScreenRules.now(speaker)", "\(now.name) | \(now.short)")

        // MARK: reaching deadwax

        add("unreachableWords", unreachableWords(server, reason: "The request timed out.", device: device))
        add("unreachableWords(no reason)", unreachableWords(server, reason: nil, device: device))
        let none = APIFailure.NoAnswer(server: server, method: "GET", path: "/me", reason: "The request timed out.", device: device)
        add("APIFailure.offline.words", APIFailure.offline(none).words)
        add("APIFailure.timeout.words", APIFailure.timeout(none).words)
        let signedOut = APIFailure.answered(.init(status: 401, method: "GET", path: "/me"))
        let report = CheckReport.from(health: .success(Health(status: "ok", version: "2.1.35", poller: nil)), me: .failure(signedOut))
        add("CheckReport.lines(needsSignIn)", report.lines(device).joined(separator: " | "))
        add("App.ServerAddressView.footer", AddressWords.footer(device))

        // MARK: the Library's gate

        add("NavidromeGate.navidromeRequired", NavidromeGate.navidromeRequired(device))
        let unset = NavidromeGate.Checked(status: NavidromeStatus(configured: false, ok: false, problem: "No address."))
        for (who, me) in [("admin", Me(user: "james", admin: true, auth: "on")),
                          ("settings", Me(user: "sam", admin: false, auth: "on", permissions: ["settings", "log"])),
                          ("listener", Me(user: "ethan", admin: false, auth: "on", permissions: ["request"]))] {
            for (name, shown) in [("shown", NavidromeGate.shown(unset, access: Access(me: me), device: device)),
                                  ("shownOnPhone", NavidromeGate.shownOnPhone(unset, access: Access(me: me), device: device))] {
                if case .closed(let closed) = shown {
                    add("NavidromeGate.\(name)(unset, \(who))", ([closed.title] + closed.lines).joined(separator: " | "))
                } else {
                    add("NavidromeGate.\(name)(unset, \(who))", "\(shown)")
                }
            }
        }

        // MARK: Lyrics, Pull to shuffle

        add("LyricsWords.notKept", LyricsWords.notKept(device))
        for have in LyricsHave.allCases { add("LyricsWords.label(\(have.rawValue))", LyricsWords.label(have, device: device)) }
        add("PullShuffleWords.pullHere", PullShuffleWords.pullHere(device))
        add("PullShuffleWords.releaseHere", PullShuffleWords.releaseHere(device))
        add("PullShuffleWords.nothingHere", PullShuffleWords.nothingHere(device))
        let cans: [(String, ShuffleCan)] = [("ready", .ready), ("downloads", .downloads), ("gettingReady", .gettingReady),
                                            ("failed", .failed("It broke.")), ("nothingHere", .nothingHere), ("none", .none)]
        for (phase, p) in [("idle", PullShuffle.Phase.idle), ("pulling", .pulling(0.5)), ("armed", .armed), ("released", .released)] {
            for (can, c) in cans {
                for (of, o) in [("library", PullShuffleOf.library), ("page", .page)] {
                    add("PullShuffleWords.line(\(phase), \(can), \(of))", PullShuffleWords.line(p, can: c, of: o, device: device))
                }
            }
        }

        // MARK: Change password

        add("OwnPassword.notRenewed", OwnPassword.notRenewed(device))
        add("OwnPassword.endedWhileChanging", OwnPassword.endedWhileChanging(device))
        var flow = OwnPasswordFlow()
        flow.form = OwnPasswordForm(current: "old one", password: "a new password 1", again: "a new password 1")
        if let (ticket, _) = flow.begin(user: "james", online: true, signInOver: false) {
            let told = flow.ended(ticket, .notRenewed(signedOut: 0, warning: nil), signInOver: false, device: device)
            add("OwnPasswordFlow.ended(notRenewed)", "\(Self.said(flow.said)) | told \(told ?? "<nil>")")
        } else {
            add("OwnPasswordFlow.ended(notRenewed)", "<not begun>")
        }
        for (name, outcome) in [("notRenewed", OwnPassword.Outcome.notRenewed(signedOut: 0, warning: nil)),
                                ("failed", .failed(words: "Timed out.", fix: nil)), ("cancelled", .cancelled)] {
            var rekey = PasswordRekey()
            _ = rekey.began(under: "s.old")
            _ = rekey.holds(reason: "held", session: "s.old")
            add("PasswordRekey.ended(\(name), held)", Self.after(rekey.ended(outcome, device: device)))
        }

        // MARK: Debug

        let utc = TimeZone(identifier: "UTC")!
        let end = Date(timeIntervalSince1970: 1_793_455_320)
        add("InstallExpiry.line(nil)", InstallExpiry.line(expiration: nil, now: end, timeZone: utc, device: device))
        add("InstallExpiry.line(days)",
            InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-5 * 86_400), timeZone: utc, device: device))
        add("InstallExpiry.line(soon)",
            InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-86_400), timeZone: utc, device: device))
        add("InstallExpiry.line(ran out)",
            InstallExpiry.line(expiration: end, now: end.addingTimeInterval(60), timeZone: utc, device: device))
        add("App.DebugView.footer", DebugWords.footer(version: "0.13 (13)", device: device))
        add("App.DebugView.onThePhone", DebugWords.onThe(device))
        add("App.DebugView.testSoundsFooter", DebugWords.testSoundsFooter(trial: TurntableDebugRows.trialFooter, device: device))
        add("App.DebugView.engineLogFooter", DebugWords.engineLogFooter(capacity: 400, total: 37, device: device))
        add("App.DownloadModel.unreadableAtLaunch", LibraryFollowWords.unreadableAtLaunch(device))
        add("App.DownloadModel.underReserve", LibraryFollowWords.underReserveNoted(device))
        add("App.PlayerModel.notHereUnreached", DownloadWords.notHereUnreached(device))
        add("Resume.label", Resume.label(for: device))
        return w
    }

    static func output(_ o: EQOutput) -> String { "\(o.key) | \(o.name) | \(o.symbol) | \(o.port.rawValue)" }

    static func said(_ said: OwnPassword.Said?) -> String {
        switch said {
        case .done(let words, let warning)?: return "done: \(words) | \(warning ?? "<nil>")"
        case .problem(let words, let fix)?: return "problem: \(words) | \(fix ?? "<nil>")"
        case nil: return "<nil>"
        }
    }

    static func after(_ after: PasswordRekey.After) -> String {
        switch after {
        case .nothing: return "nothing"
        case .signIn(let reason): return "signIn: \(reason ?? "<nil>")"
        case .askMe: return "askMe"
        }
    }

    static func row(_ r: AlbumInfoRow) -> String { "\(r.label) | \(r.value) | \(r.lines.joined(separator: "; "))" }

    /// As a JSON object, keys sorted.
    static func json(_ words: [(String, String)]) throws -> Data {
        try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: words),
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

@Suite struct DeviceWordsTests {
    /// Check 438: every word an iPhone shows, as it was. Each name once; the fixture's every name said still, and
    /// said the same. `DEADWAX_WORDS_WRITE=iphone` wrote the fixture once, at c97a824 - never again: a word of the
    /// phone's changes only when a change asks for it, and then by hand here.
    @Test func theIPhonesWordsAreAsTheyWere() throws {
        let words = DeviceWords.all(.iPhone)
        let names = words.map(\.0)
        #expect(Set(names).count == names.count, "a name listed twice")
        if ProcessInfo.processInfo.environment["DEADWAX_WORDS_WRITE"] == "iphone" {
            try DeviceWords.json(words).write(to: Fixtures.checkout.appendingPathComponent("words/iphone.json"))
            return
        }
        let kept = try JSONDecoder().decode([String: String].self, from: Fixtures.data("words/iphone.json"))
        let now = Dictionary(uniqueKeysWithValues: words)
        for name in kept.keys.sorted() {
            #expect(now[name] == kept[name], "\(name)")
        }
        for name in now.keys.sorted() where kept[name] == nil {
            Issue.record("\(name) isn't in words/iphone.json")
        }
        #expect(kept.count >= 400)
    }

    /// Checks 434-437, as far as Core says them: every word the Mac says, as it is - Fixtures/words/mac.json, written by
    /// `DEADWAX_WORDS_WRITE=mac` whenever a Mac word changes on purpose - the same names as the phone's.
    @Test func theMacsWordsAreTheOnesWritten() throws {
        let words = DeviceWords.all(.mac)
        let names = words.map(\.0)
        #expect(Set(names).count == names.count, "a name listed twice")
        #expect(names == DeviceWords.all(.iPhone).map(\.0), "the Mac says every word the phone does, under the same name")
        if ProcessInfo.processInfo.environment["DEADWAX_WORDS_WRITE"] == "mac" {
            try DeviceWords.json(words).write(to: Fixtures.checkout.appendingPathComponent("words/mac.json"))
            return
        }
        let kept = try JSONDecoder().decode([String: String].self, from: Fixtures.data("words/mac.json"))
        let now = Dictionary(uniqueKeysWithValues: words)
        #expect(Set(kept.keys) == Set(now.keys))
        for name in kept.keys.sorted() {
            #expect(now[name] == kept[name], "\(name)")
        }
    }

    /// Slice 5's, left saying the phone's words on the Mac for now (notes/ios.md "The Mac app, slice 4 after review"):
    /// Download over's choices and notes and what's used now, the force-quit footer - and an admin's raw "iOS
    /// couldn't…" (DeadwaxAudio's own words, which have no diff). Listed so a phone word outside them is noticed.
    static let slice5Leftovers: [String] = [
        DownloadWords.forceQuit, DownloadWords.over(.wifi).note, DownloadWords.over(.any).name,
        DownloadWords.over(.any).note,
        DownloadWords.overNow(NetworkPath(satisfied: true, cellular: true, expensive: true), setting: .wifi),
        DownloadWords.overNow(NetworkPath(satisfied: true, cellular: true, expensive: true), setting: .any),
        "iOS couldn't open or decode the file",
    ]

    /// No word OF THIS SNAPSHOT (DeviceWords.all - the words that named the device at c97a824, and the downloads' lists
    /// of every line) calls the Mac a phone or an iPhone (headphones are headphones), nor says iOS, the app switcher,
    /// cellular, mobile data or Airplane Mode - but slice 5's leftovers, named above. A word outside the snapshot isn't
    /// read here (Debug's "ended by iOS" is one, notes/ios.md has the rest).
    @Test func noWordOfTheSnapshotSaysThePhonesOnTheMac() {
        let words = DeviceWords.all(.mac)
        for (name, word) in words {
            var said = word
            for left in Self.slice5Leftovers { said = said.replacingOccurrences(of: left, with: "") }
            let phone = said.range(of: #"(?i)\b(i?phones?|ios|app switcher|cellular|mobile data|airplane mode)\b"#,
                                   options: .regularExpression)
            #expect(phone == nil, "\(name): \(word)")
        }
        // each leftover is still said: a stale list is noticed
        for left in Self.slice5Leftovers { #expect(words.contains { $0.1.contains(left) }, "\(left)") }
    }

    /// What differs between the two, and how: every word the phone says with "phone" in it says "Mac" on the Mac - and
    /// the rest are the same word for word but for the few written for the Mac on purpose, listed here.
    @Test func theMacsWordsDifferWhereThePhonesSayPhone() {
        let phone = Dictionary(uniqueKeysWithValues: DeviceWords.all(.iPhone))
        let mac = Dictionary(uniqueKeysWithValues: DeviceWords.all(.mac))
        // written for the Mac, not swapped word for word (notes/ios.md "The Mac app, slice 4: the Mac's words")
        let ownWords: Set<String> = [
            "DownloadWords.lastFooter", "DownloadWords.storeUnreadable", "DownloadWords.banner(noNetwork)",
            "EQWords.You.footer", "EQWords.Screen.unitNotMade", "EQScreenRules.line(unitNotMade)",
            "EQWords.Import.fromFiles", "EQWords.Import.channels(C, 12-20)", "EQWords.Import.channels(RL RR, 4)",
            "APOReader.read(channel)", "unreachableWords", "unreachableWords(no reason)", "APIFailure.offline.words",
            "APIFailure.timeout.words", "App.ServerAddressView.footer", "App.DebugView.footer",
            "App.DebugView.engineLogFooter", "InstallExpiry.line(nil)",
            "InstallExpiry.line(soon)", "InstallExpiry.line(ran out)", "Resume.label",
        ]
        // a line of the downloads' everyLine (the banned-words checks' list) is no word of its own: one that differs
        // repeats a named word - or one part of one, a banner's line - on both devices, and is held where that is
        let named = phone.keys.filter { !$0.contains(".everyLine[") }
        func parts(_ word: String) -> [String] { [word] + word.components(separatedBy: " | ") }
        func repeatsANamedWord(_ name: String) -> Bool {
            named.contains { other in
                let (p, m) = (parts(phone[other]!), parts(mac[other]!))
                return p.count == m.count && zip(p, m).contains { $0 == phone[name] && $1 == mac[name] }
            }
        }
        var differ: Set<String> = []
        for (name, word) in phone where mac[name] != word {
            differ.insert(name)
            if ownWords.contains(name) { continue }
            if name.hasPrefix("DownloadWords.everyLine[") {
                #expect(repeatsANamedWord(name), "\(name) differs and repeats no named word: \(word)")
                continue
            }
            // the rest: "phone" said "Mac", "This phone" "This Mac", the speaker named for the Mac, and nothing else
            let swapped = word.replacingOccurrences(of: "This phone", with: "This Mac")
                .replacingOccurrences(of: "this phone", with: "this Mac")
                .replacingOccurrences(of: "the phone", with: "the Mac")
                .replacingOccurrences(of: "a phone", with: "a Mac")
                .replacingOccurrences(of: "iPhone speaker", with: "Mac speakers")
                .replacingOccurrences(of: "| iphone |", with: "| hifispeaker |")
            #expect(mac[name] == swapped, "\(name): \(word) -> \(mac[name] ?? "<none>")")
        }
        // every word that says phone on the phone is different on the Mac
        for (name, word) in phone where word.lowercased().range(of: #"\b(i)?phones?\b"#, options: .regularExpression) != nil {
            #expect(differ.contains(name), "\(name) says phone on the phone and the same on the Mac")
        }
        // the Mac's own words are each different from the phone's (a name listed here that isn't is a stale list)
        for name in ownWords { #expect(differ.contains(name), "\(name)") }
    }

    /// Check 437: the Local Network words point to the Mac's System Settings; the phone's to the iPhone's Settings.
    @Test func theLocalNetworkWordsPointToEachDevicesSettings() throws {
        let server = try ServerAddress.parse("http://192.168.1.20:8090").get()
        let mac = unreachableWords(server, reason: nil, device: .mac)
        #expect(mac.hasSuffix(" turn deadwax on in System Settings > Privacy & Security > Local Network."))
        #expect(mac.contains("Is the Mac on your home network, or on WireGuard?"))
        // slice 4's review: the Mac's asking began with macOS 15 (Apple's TN3179), and the app opens from macOS 14
        #expect(mac.contains("On macOS 15 or later, if you said no when asked about the local network"))
        #expect(AddressWords.footer(.mac).contains("The first time, macOS 15 or later asks to let deadwax find devices"))
        #expect(AddressWords.footer(.iPhone).contains("The first time, iOS asks"))
        #expect(unreachableWords(server, reason: nil, device: .iPhone)
            .hasSuffix(" turn deadwax on in the iPhone's Settings > Privacy & Security > Local Network."))
        // the device rides on the failure itself, so every place that says one says it right
        let none = APIFailure.NoAnswer(server: server, method: "GET", path: "/me", reason: "Offline.", device: .mac)
        #expect(APIFailure.offline(none).words == unreachableWords(server, reason: "Offline.", device: .mac))
        #expect(APIFailure.noAnswer(URLError(.cannotFindHost), to: HTTPRequest(method: "GET", url: server.base), server: server, device: .mac)
            .words.contains("System Settings > Privacy & Security > Local Network"))
    }

    /// Check 434: Debug's install line on the Mac. No profile read - install-mac.sh's build - and it doesn't run out;
    /// a build that carries one (--allow-profile) says its date, and install-mac.sh where the phone's says install.sh.
    @Test func theMacsInstallLineReadsItsProfile() {
        let end = Date(timeIntervalSince1970: 1_793_455_320)
        let utc = TimeZone(identifier: "UTC")!
        for now in [end.addingTimeInterval(-5 * 86_400), end.addingTimeInterval(60)] {
            #expect(InstallExpiry.line(expiration: nil, now: now, device: .mac) == InstallExpiry.mac)
        }
        #expect(InstallExpiry.mac.contains("doesn't expire"))
        #expect(InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-5 * 86_400), timeZone: utc, device: .mac)
                == "This install runs until Sat 31 Oct, 14:02")
        #expect(InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-86_400), timeZone: utc, device: .mac)
                == "This install runs until Sat 31 Oct, 14:02. Run install-mac.sh before then.")
        #expect(InstallExpiry.line(expiration: end, now: end.addingTimeInterval(60), timeZone: utc, device: .mac)
                == "This install ran out on Sat 31 Oct, 14:02. Run install-mac.sh to put it back.")
    }

    /// Check 436: the speaker keeps its key on both - only its name and mark are the Mac's - so nothing stored moves.
    @Test func theSpeakerKeepsItsKey() {
        #expect(EQOutputs.speaker(.iPhone).key == EQOutputs.speaker(.mac).key)
        #expect(EQOutputs.speakerKey == "speaker")
        #expect(EQOutputs.speaker(.mac).name == "Mac speakers")
        let port = EQRoutePort(port: .builtInSpeaker, portType: "Speaker", name: "MacBook Air Speakers", uid: "BuiltInSpeakerDevice")
        let o = EQOutputs.output(port, device: .mac)
        #expect(o.key == "speaker" && o.name == "Mac speakers" && o.symbol == "hifispeaker")
        // a speaker kept under the phone's old name, met on the Mac: named the Mac's from then on, its EQ kept
        var settings = EQSettings()
        settings.outputs = [EQSettings.newOutput(EQOutputs.speaker(.iPhone), seen: "")]
        settings.outputs[0].on = true
        settings.met(o, at: "2026-11-18T10:00:00Z")
        #expect(settings.outputs.count == 1 && settings.outputs[0].name == "Mac speakers" && settings.outputs[0].on)
    }
}
