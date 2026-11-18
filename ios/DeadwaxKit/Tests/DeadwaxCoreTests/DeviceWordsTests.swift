import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac app's words (notes/ios.md "The Mac app, slice 4: the Mac's words"): every word the app shows that says
/// phone or iPhone - and every word made from one of them - by name, with the arguments that reach each way it can be
/// said. Fixtures/words/iphone.json is what each said on the iPhone at c97a824, before the Mac's words were made: the
/// phones' words don't change (check 438), and this holds them to it, word for word.
///
/// The App's own literals that became Core's words (Debug's, the downloads log's, the address screen's) are listed
/// under `App.`, their values at c97a824 copied from the App's source as it was.
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

        add("YouWords.kept", YouWords.kept)
        add("YouWords.thisPhone", YouWords.thisPhone)

        // MARK: Downloads

        add("DownloadWords.notOnPhone", DownloadWords.notOnPhone)
        for (name, album) in albums {
            add("DownloadWords.tileSpoken(\(name))", DownloadWords.tileSpoken(album))
            add("DownloadWords.tileSpoken(\(name), notHere)", DownloadWords.tileSpoken(album, notHere: true))
            add("DownloadWords.albumLine(\(name))", DownloadWords.albumLine(album))
            add("DownloadWords.controlValue(\(name))", DownloadWords.controlValue(album))
            for limit in [StorageLimit.gb20, .none] {
                add("DownloadWords.controlMenuTitle(\(name), \(limit.rawValue))",
                    DownloadWords.controlMenuTitle(album, limit: limit, bytesHere: 412_000_000, firstFailure: "It broke."))
            }
            add("PlaylistDownloadWords.heroLine(\(name))", PlaylistDownloadWords.heroLine(album))
            add("PlaylistDownloadWords.heroLine(\(name), smart)", PlaylistDownloadWords.heroLine(album, smart: true))
            add("AlbumInfo.onPhone(\(name))", Self.row(AlbumInfo.onPhone(album, here: 3, of: 12, bytes: 92_000_000)))
        }
        for (name, song) in songs {
            add("DownloadWords.songLine(\(name))", DownloadWords.songLine(song))
        }
        for reason in reasons {
            add("DownloadWords.wait(\(reason.rawValue))", DownloadWords.wait(reason))
            add("DownloadWords.youFooter(\(reason.rawValue))",
                DownloadWords.youFooter(fetching: 0, toGo: 0, firstWait: reason, failed: 0)?.text)
            add("DownloadWords.downloadingRow(\(reason.rawValue))",
                DownloadWords.downloadingRow(here: 4, of: 12, wait: reason, onlySong: nil))
            let progress = PlaylistDownloads.Progress(toGo: 3, of: 12)
            add("PlaylistDownloadWords.downloadingRow(\(reason.rawValue))",
                PlaylistDownloadWords.downloadingRow(progress, wait: reason))
            add("PlaylistDownloadWords.downloadingSpoken(\(reason.rawValue))",
                PlaylistDownloadWords.downloadingSpoken("Late night", progress, wait: reason))
        }
        add("DownloadWords.youFooter(fetching)", DownloadWords.youFooter(fetching: 1, toGo: 6, firstWait: nil, failed: 0)?.text)
        add("DownloadWords.youFooter(failed)", DownloadWords.youFooter(fetching: 0, toGo: 0, firstWait: nil, failed: 2)?.text)
        add("DownloadWords.downloadingRow(nil)", DownloadWords.downloadingRow(here: 4, of: 12, wait: nil, onlySong: nil))
        add("DownloadWords.downloadingRow(nil, Roads)", DownloadWords.downloadingRow(here: 0, of: 1, wait: nil, onlySong: "Roads"))
        add("DownloadWords.footer(0 of 10)", DownloadWords.footer(here: 0, of: 10, bytes: 0))
        add("DownloadWords.footer(10 of 10)", DownloadWords.footer(here: 10, of: 10, bytes: 412_000_000))
        add("DownloadWords.footer(3 of 12)", DownloadWords.footer(here: 3, of: 12, bytes: 92_000_000))
        add("DownloadWords.albumGoneHere", DownloadWords.albumGoneHere)
        add("DownloadWords.albumNotHere", DownloadWords.albumNotHere)
        add("DownloadWords.removed", DownloadWords.removed("Dummy"))
        add("DownloadWords.unreadable", DownloadWords.unreadable)
        add("DownloadWords.unsaved", DownloadWords.unsaved)
        for (name, failure) in [("unreadable", DownloadFailure.unreadable), ("unsaved", .unsaved), ("wrongSize", .wrongSize),
                                ("offline", .offline(reason: "The network connection was lost."))] {
            for admin in [false, true] {
                let line = DownloadWords.failure(failure, songID: "tr-1", server: server, admin: admin)
                add("DownloadWords.failure(\(name), admin: \(admin))", "\(line.text) | \(line.advice) | \(line.detail ?? "-")")
            }
        }
        add("DownloadWords.playsFrom(nil)", DownloadWords.playsFrom(nil, isFLAC: true))
        for check in CopyCheck.allCases {
            for flac in [true, false] {
                add("DownloadWords.playsFrom(\(check.rawValue), flac: \(flac))", DownloadWords.playsFrom(check, isFLAC: flac))
            }
        }
        add("DownloadWords.onThisPhone", DownloadWords.onThisPhone)
        add("DownloadWords.staysAfterSignOut", DownloadWords.staysAfterSignOut)
        add("DownloadWords.usageLine", DownloadWords.usageLine(albums: 12, songs: 148, free: 41_200_000_000))
        add("DownloadWords.usageLine(none)", DownloadWords.usageLine(albums: 0, songs: 0, free: 41_200_000_000))
        add("DownloadWords.usageSpoken(gb20)", DownloadWords.usageSpoken(2_100_000_000, limit: .gb20, free: 41_200_000_000))
        add("DownloadWords.usageSpoken(none)", DownloadWords.usageSpoken(2_100_000_000, limit: .none, free: 41_200_000_000))
        add("DownloadWords.otherAccounts", DownloadWords.otherAccounts)
        add("DownloadWords.removeOthersMessage", DownloadWords.removeOthersMessage(1_200_000_000))
        add("DownloadWords.overKept", DownloadWords.overKept)
        add("DownloadWords.forceQuit", DownloadWords.forceQuit)
        add("DownloadWords.removeAllMessage", DownloadWords.removeAllMessage(songs: 148, bytes: 2_100_000_000))
        add("DownloadWords.lastFooter", DownloadWords.lastFooter)
        add("DownloadWords.storeUnreadable", DownloadWords.storeUnreadable)
        for reach in Reach.allCases {
            let banner = DownloadWords.banner(reach)
            add("DownloadWords.banner(\(reach.rawValue))", banner.map { "\($0.line) | \($0.symbol) | \($0.more)" })
        }
        add("DownloadWords.skippedNotHere(title)", DownloadWords.skippedNotHere(title: "Roads"))
        add("DownloadWords.skippedNotHere(1)", DownloadWords.skippedNotHere(count: 1))
        add("DownloadWords.skippedNotHere(3)", DownloadWords.skippedNotHere(count: 3))
        add("DownloadWords.stoppedNotHere", DownloadWords.stoppedNotHere)
        for (i, line) in DownloadWords.everyLine.enumerated() { add("DownloadWords.everyLine[\(i)]", line) }

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
            add("AutoDownloadWords.note(\(s))", AutoDownloadWords.note(scope))
            add("AutoDownloadWords.chargingNote(\(s))", AutoDownloadWords.chargingNote(scope))
            for held in [LibraryFollow.Held.empty(kept: 212), .drop(gone: 1_240, of: 3_010), .truncated] {
                add("AutoDownloadWords.question(\(s), \(held))", AutoDownloadWords.question(held, scope: scope, here: 212))
            }
            for limit in [StorageLimit.gb20, .none] {
                add("AutoDownloadWords.waitsForRoom(\(s), \(limit.rawValue))", AutoDownloadWords.waitsForRoom(scope, limit: limit))
                add("AutoDownloadWords.askLine(\(s), \(limit.rawValue))", AutoDownloadWords.askLine(scope, limit: limit))
            }
            add("AutoDownloadWords.keptOff(\(s))", AutoDownloadWords.keptOff(scope))
            add("AutoDownloadWords.askTitle(\(s))", AutoDownloadWords.askTitle(scope))
        }
        for (name, plan) in plans {
            for limit in [StorageLimit.gb20, .gb100, .none] {
                add("AutoDownloadWords.fit(\(name), \(limit.rawValue))", AutoDownloadWords.fit(plan, limit: limit, bytes: 1_000_000_000))
                add("LibraryFollowWords.wouldFit(\(name), \(limit.rawValue))", LibraryFollowWords.wouldFit(plan, limit: limit))
            }
            add("LibraryFollowWords.fitDetail(\(name))", LibraryFollowWords.fitDetail(plan))
        }
        add("AutoDownloadWords.goesToo", AutoDownloadWords.goesToo)
        add("AutoDownloadWords.offMessage", AutoDownloadWords.offMessage(bytes: 12_400_000_000))
        add("AutoDownloadWords.keepOffTitle", AutoDownloadWords.keepOffTitle("Dummy"))
        add("LibraryFollowWords.followNote", LibraryFollowWords.followNote)
        add("LibraryFollowWords.notFollowing", LibraryFollowWords.notFollowing)
        for (name, held) in [("nil", LibraryFollow.Held?.none), ("empty", .empty(kept: 212)),
                             ("drop", .drop(gone: 1_240, of: 3_010)), ("truncated", .truncated)] {
            add("LibraryFollowWords.held(\(name))", LibraryFollowWords.held(held))
        }

        // MARK: playlists

        add("PlaylistDownloadWords.removeAllToo(1)", PlaylistDownloadWords.removeAllToo(playlists: 1))
        add("PlaylistDownloadWords.removeAllToo(3)", PlaylistDownloadWords.removeAllToo(playlists: 3))
        for (i, line) in PlaylistDownloadWords.everyLine.enumerated() { add("PlaylistDownloadWords.everyLine[\(i)]", line) }

        // MARK: Album info

        add("AlbumInfoWords.phoneTitle", AlbumInfoWords.phoneTitle)
        let album = try! JSONDecoder().decode(Album.self, from: Data(#"{"id": "al-1", "name": "Dummy", "artist": "Portishead"}"#.utf8))
        let here = AlbumInfo.onPhone(.partial(here: 3, of: 12), here: 3, of: 12, bytes: 92_000_000)
        add("AlbumInfo.local", AlbumInfo.local(album: album, onPhone: here).map(\.title).joined(separator: " | "))

        // MARK: the EQ

        add("EQWords.Import.fromFiles", EQWords.Import.fromFiles)
        add("EQWords.Import.frequencyHigh", EQWords.Import.frequencyHigh(line: 2, hz: 30_000).text)
        let centre = [Array("C".unicodeScalars)]
        let rear = [Array("RL".unicodeScalars), Array("RR".unicodeScalars)]
        add("EQWords.Import.channels(C, 12-20)", EQWords.Import.channels(first: 12, last: 20, words: centre).text)
        add("EQWords.Import.channels(RL RR, 4)", EQWords.Import.channels(first: 4, last: 4, words: rear).text)
        add("EQWords.Import.channels(none, 4)", EQWords.Import.channels(first: 4, last: 4, words: []).text)
        let high = "Preamp: -3 dB\nFilter: ON PK Fc 30000 Hz Gain 3 dB Q 1\n"
        let channel = "Preamp: -3 dB\nChannel: C\nFilter: ON PK Fc 1000 Hz Gain 3 dB Q 1\nChannel: L R\nFilter: ON PK Fc 100 Hz Gain 3 dB Q 1\n"
        for (name, text) in [("high", high), ("channel", channel)] {
            switch APOReader.read(Data(text.utf8)) {
            case .success(let reading): add("APOReader.read(\(name))", reading.notes.map(\.text).joined(separator: " | "))
            case .failure(let refusal): add("APOReader.read(\(name))", "refused: \(refusal.text)")
            }
        }
        add("EQWords.You.footer", EQWords.You.footer)
        add("EQWords.Screen.unitNotMade", EQWords.Screen.unitNotMade)
        add("EQScreenRules.line(unitNotMade)", EQScreenRules.line(on: true, identity: false, preamp: .automatic, played: 0, top: 0,
                                                                  unitNotMade: true).text)
        add("EQWords.Outputs.speaker", EQWords.Outputs.speaker)
        add("EQOutputs.speaker", Self.output(EQOutputs.speaker))
        for port in EQPort.allCases {
            let p = EQRoutePort(port: port, portType: "Type", name: "James's AirPods Pro", uid: "u-1")
            add("EQOutputs.output(\(port.rawValue))", Self.output(EQOutputs.output(p)))
        }
        add("EQOutputs.output([])", EQOutputs.output([EQRoutePort]()).map(Self.output))
        let speakerPort = EQRoutePort(port: .builtInSpeaker, portType: "Speaker", name: "Speaker", uid: "")
        add("EQOutputs.output([speaker])", EQOutputs.output([speakerPort]).map(Self.output))
        let kept = EQSettings.newOutput(EQOutputs.speaker, seen: "")
        add("EQSettings.newOutput(speaker)", "\(kept.key) | \(kept.name) | \(kept.shownName) | \(kept.type.rawValue)")
        add("EQOutputSetting.output(speaker)", Self.output(kept.output))
        let wired = EQOutputs.output(EQRoutePort(port: .headphones, portType: "Headphones", name: "Headphones", uid: ""))
        add("EQScreenRules.others(wired)", EQScreenRules.others(EQSettings(), shown: wired.key)
            .map { "\($0.key) | \($0.shownName) | \(Self.output($0.output))" }.joined(separator: " / "))
        add("EQScreenRules.output(speaker)", Self.output(EQScreenRules.output("speaker", route: wired, in: EQSettings(), lastDrawn: nil)))
        add("EQScreenRules.output(speaker, route)", Self.output(EQScreenRules.output("speaker", route: EQOutputs.speaker,
                                                                                     in: EQSettings(), lastDrawn: nil)))
        let now = EQScreenRules.now(EQSettings(), route: EQOutputs.speaker)
        add("EQScreenRules.now(speaker)", "\(now.name) | \(now.short)")

        // MARK: reaching deadwax

        add("unreachableWords", unreachableWords(server, reason: "The request timed out."))
        add("unreachableWords(no reason)", unreachableWords(server, reason: nil))
        let none = APIFailure.NoAnswer(server: server, method: "GET", path: "/me", reason: "The request timed out.")
        add("APIFailure.offline.words", APIFailure.offline(none).words)
        add("APIFailure.timeout.words", APIFailure.timeout(none).words)
        let signedOut = APIFailure.answered(.init(status: 401, method: "GET", path: "/me"))
        let report = CheckReport.from(health: .success(Health(status: "ok", version: "2.1.35", poller: nil)), me: .failure(signedOut))
        add("CheckReport.lines(needsSignIn)", report.lines.joined(separator: " | "))
        add("App.ServerAddressView.footer",
            "The address you open deadwax at, by IP or by name. The first time, iOS asks to let deadwax find devices on your local network: say yes.")

        // MARK: the Library's gate

        add("NavidromeGate.navidromeRequired", NavidromeGate.navidromeRequired)
        let unset = NavidromeGate.Checked(status: NavidromeStatus(configured: false, ok: false, problem: "No address."))
        for (who, me) in [("admin", Me(user: "james", admin: true, auth: "on")),
                          ("settings", Me(user: "sam", admin: false, auth: "on", permissions: ["settings", "log"])),
                          ("listener", Me(user: "ethan", admin: false, auth: "on", permissions: ["request"]))] {
            for (name, shown) in [("shown", NavidromeGate.shown(unset, access: Access(me: me))),
                                  ("shownOnPhone", NavidromeGate.shownOnPhone(unset, access: Access(me: me)))] {
                if case .closed(let closed) = shown {
                    add("NavidromeGate.\(name)(unset, \(who))", ([closed.title] + closed.lines).joined(separator: " | "))
                } else {
                    add("NavidromeGate.\(name)(unset, \(who))", "\(shown)")
                }
            }
        }

        // MARK: Lyrics, Pull to shuffle

        add("LyricsWords.notKept", LyricsWords.notKept)
        for have in LyricsHave.allCases { add("LyricsWords.label(\(have.rawValue))", LyricsWords.label(have)) }
        add("PullShuffleWords.pullHere", PullShuffleWords.pullHere)
        add("PullShuffleWords.releaseHere", PullShuffleWords.releaseHere)
        add("PullShuffleWords.nothingHere", PullShuffleWords.nothingHere)
        let cans: [(String, ShuffleCan)] = [("ready", .ready), ("downloads", .downloads), ("gettingReady", .gettingReady),
                                            ("failed", .failed("It broke.")), ("nothingHere", .nothingHere), ("none", .none)]
        for (phase, p) in [("idle", PullShuffle.Phase.idle), ("pulling", .pulling(0.5)), ("armed", .armed), ("released", .released)] {
            for (can, c) in cans {
                for (of, o) in [("library", PullShuffleOf.library), ("page", .page)] {
                    add("PullShuffleWords.line(\(phase), \(can), \(of))", PullShuffleWords.line(p, can: c, of: o))
                }
            }
        }

        // MARK: Change password

        add("OwnPassword.notRenewed", OwnPassword.notRenewed)
        add("OwnPassword.endedWhileChanging", OwnPassword.endedWhileChanging)
        var flow = OwnPasswordFlow()
        flow.form = OwnPasswordForm(current: "old one", password: "a new password 1", again: "a new password 1")
        if let (ticket, _) = flow.begin(user: "james", online: true, signInOver: false) {
            let told = flow.ended(ticket, .notRenewed(signedOut: 0, warning: nil), signInOver: false)
            add("OwnPasswordFlow.ended(notRenewed)", "\(Self.said(flow.said)) | told \(told ?? "<nil>")")
        } else {
            add("OwnPasswordFlow.ended(notRenewed)", "<not begun>")
        }
        for (name, outcome) in [("notRenewed", OwnPassword.Outcome.notRenewed(signedOut: 0, warning: nil)),
                                ("failed", .failed(words: "Timed out.", fix: nil)), ("cancelled", .cancelled)] {
            var rekey = PasswordRekey()
            _ = rekey.began(under: "s.old")
            _ = rekey.holds(reason: "held", session: "s.old")
            add("PasswordRekey.ended(\(name), held)", Self.after(rekey.ended(outcome)))
        }

        // MARK: Debug

        let utc = TimeZone(identifier: "UTC")!
        let end = Date(timeIntervalSince1970: 1_793_455_320)
        add("InstallExpiry.line(nil)", InstallExpiry.line(expiration: nil, now: end, timeZone: utc))
        add("InstallExpiry.line(days)", InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-5 * 86_400), timeZone: utc))
        add("InstallExpiry.line(soon)", InstallExpiry.line(expiration: end, now: end.addingTimeInterval(-86_400), timeZone: utc))
        add("InstallExpiry.line(ran out)", InstallExpiry.line(expiration: end, now: end.addingTimeInterval(60), timeZone: utc))
        add("App.DebugView.footer", "deadwax for iPhone 0.13 (13)")
        add("App.DebugView.onThePhone", "on the phone")
        add("App.DebugView.testSoundsFooter",
            "Songs 1 to 8 are three beeps each: tap one to play the album from it and count the beeps - all three, every time? Songs 9 and 10 are one tone cut in two: played one into the other, the tone should never break. A song downloaded to this phone plays from there, as every song does; \"Stream even when downloaded\" (under Downloads) streams it instead, to hear the two side by side. \(TurntableDebugRows.trialFooter)")
        let capacity = 400, total = 37
        add("App.DebugView.engineLogFooter",
            "The engine's last \(capacity) lines, the newest last (\(total) so far); once there are \(capacity), the oldest go as new ones come, so the lines move up while you read - Copy keeps them as they are. Each line starts with a time in seconds on the phone's clock: the gaps between lines are what count. Console on a Mac shows them too, as they happen: choose the iPhone, turn on Action > Include Info Messages, press Start, then search for subsystem:net.lizardlounge.deadwax.")
        add("App.DownloadModel.unreadableAtLaunch",
            "background: this launch couldn't read the settings (before the phone's first unlock) - nothing asked")
        add("App.DownloadModel.underReserve", "library: the phone is under its reserve - looked at again in 3 minutes")
        add("App.PlayerModel.notHereUnreached", "Not on this phone, and deadwax can't be reached.")
        add("Resume.label", Resume.label(for: .iPhone))
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
}
