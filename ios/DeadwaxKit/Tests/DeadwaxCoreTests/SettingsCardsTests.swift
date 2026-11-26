import Foundation
import Testing
@testable import DeadwaxCore

/// The redesign, slice R9 (notes/ios.md "The redesign, slice R9: Downloaded, Settings and Sign in"): the account card,
/// Sign in's one screen in today's order (Check, then Sign in), the Mac's Downloaded, and the cancel note each device
/// says - SettingsCards.swift's rules, on Linux.
@Suite struct SettingsCardsTests {
    private static let server = try! ServerAddress.parse("http://deadwax.lan:8080").get()
    private static let other = try! ServerAddress.parse("http://192.168.1.20:8090").get()

    private static func card(_ me: Me?, failed: Bool = false) -> AccountCard {
        let access = me.map { Access(me: $0) } ?? Access(user: "", permissions: [], on: false, unverified: false, admin: false)
        return AccountCard(lines: YouLines(me: me, failed: failed, access: access), access: access, address: server)
    }

    @Test func theAccountCardSaysWhoWhereAndTheRole() {
        let james = Self.card(Me(user: "james", admin: true, auth: "on", version: "2.1.40"))
        #expect(james.letter == "J" && james.name == "james" && james.identity == nil)
        #expect(james.address == "http://deadwax.lan:8080")
        #expect(james.role == "Admin" && james.signsOut)
        #expect(james.spoken == "james, Admin, http://deadwax.lan:8080")
        // an ordinary listener: no chip, and Sign out
        let ethan = Self.card(Me(user: "ethan", admin: false, auth: "on", version: "2.1.40"))
        #expect(ethan.role == nil && ethan.signsOut && ethan.spoken == "ethan, http://deadwax.lan:8080")
        // break-glass is an admin signed in
        let glass = Self.card(Me(user: "deadwax", admin: true, auth: "on", version: "2.1.40"))
        #expect(glass.role == "Admin" && glass.signsOut)
    }

    @Test func withLoginsOffThereIsNoSignOutAndNoRole() {
        // AUTH_MODE off: no sign-in, and the admin is implicit - "No sign-in needed" says so, nothing to sign out of
        let off = Self.card(Me(user: "local", admin: false, auth: "off", version: "2.1.40"))
        #expect(off.name == "deadwax" && off.letter == "d" && off.identity == YouWords.noSignIn)
        #expect(off.role == nil && !off.signsOut)
        #expect(off.spoken == "deadwax, No sign-in needed, http://deadwax.lan:8080")
        // before /me has answered: "…", and nothing offered
        let none = Self.card(nil)
        #expect(none.identity == YouWords.asking && none.role == nil && !none.signsOut)
    }

    @Test func signInWaitsForCheckToAnswerForTheAddressShown() {
        let shown = "http://deadwax.lan:8080"
        // deadwax answered at this address and asked for a sign-in: Sign in is on
        #expect(SignInGate.signInOn(asksSignIn: true, typed: shown, inUse: Self.server, checking: false, busy: false))
        // the same address typed another way still is the one checked
        #expect(SignInGate.signInOn(asksSignIn: true, typed: " http://deadwax.lan:8080/ ", inUse: Self.server,
                                    checking: false, busy: false))
        // no Check has answered yet (a first run: no address in use), or it hasn't asked for a sign-in
        #expect(!SignInGate.signInOn(asksSignIn: false, typed: shown, inUse: nil, checking: false, busy: false))
        #expect(!SignInGate.signInOn(asksSignIn: false, typed: shown, inUse: Self.server, checking: false, busy: false))
        // Check still out
        #expect(!SignInGate.signInOn(asksSignIn: true, typed: shown, inUse: Self.server, checking: true, busy: false))
        // another address typed, not checked yet - Sign in would go to the old one
        #expect(!SignInGate.signInOn(asksSignIn: true, typed: "http://192.168.1.20:8090", inUse: Self.server,
                                     checking: false, busy: false))
        #expect(!SignInGate.signInOn(asksSignIn: true, typed: "not an address", inUse: Self.server, checking: false,
                                     busy: false))
        // a sign-in already on its way
        #expect(!SignInGate.signInOn(asksSignIn: true, typed: shown, inUse: Self.server, checking: false, busy: true))
        // the chip says deadwax answered only for the address it answered at
        #expect(SignInGate.answered(asksSignIn: true, typed: shown, inUse: Self.server, checking: false))
        #expect(!SignInGate.answered(asksSignIn: true, typed: "http://192.168.1.20:8090", inUse: Self.server,
                                     checking: false))
        #expect(!SignInGate.answered(asksSignIn: true, typed: shown, inUse: Self.server, checking: true))
        #expect(SignInGate.isChecked(typed: "http://192.168.1.20:8090", inUse: Self.other))
    }

    @Test func returnInThePasswordDoesWhatTheButtonThatIsOnWould() {
        // (R9's review) Sign in once deadwax answered at the address shown and asked for one - over the app too
        #expect(SignInGate.returnSignsIn(asksSignIn: true, typed: "http://deadwax.lan:8080", inUse: Self.server))
        #expect(SignInGate.returnSignsIn(asksSignIn: true, typed: " http://deadwax.lan:8080/ ", inUse: Self.server))
        // Check until then: no address checked yet, another typed, one that isn't an address, no sign-in asked for
        #expect(!SignInGate.returnSignsIn(asksSignIn: false, typed: "http://deadwax.lan:8080", inUse: nil))
        #expect(!SignInGate.returnSignsIn(asksSignIn: true, typed: "http://192.168.1.20:8090", inUse: Self.server))
        #expect(!SignInGate.returnSignsIn(asksSignIn: true, typed: "not an address", inUse: Self.server))
        #expect(!SignInGate.returnSignsIn(asksSignIn: false, typed: "http://deadwax.lan:8080", inUse: Self.server))
    }

    @Test func theMacsDownloadedFindsAsTheAlbumsPageDoes() {
        // (R9's review) every word, folded, in the name and the artist; nothing typed finds everything
        #expect(MacDownloaded.finds("", name: "Dummy", artist: "Portishead"))
        #expect(MacDownloaded.finds("   ", name: nil, artist: nil))
        #expect(MacDownloaded.finds("dum", name: "Dummy", artist: "Portishead"))
        #expect(MacDownloaded.finds("PORTIS dummy", name: "Dummy", artist: "Portishead"))
        #expect(MacDownloaded.finds("bjork", name: "Homogenic", artist: "Bj\u{00F6}rk"))
        #expect(!MacDownloaded.finds("dummy third", name: "Dummy", artist: "Portishead"))
        #expect(!MacDownloaded.finds("massive", name: "Dummy", artist: "Portishead"))
        // a playlist's name alone
        #expect(MacDownloaded.finds("road", name: "Road trip"))
        #expect(!MacDownloaded.finds("portishead", name: "Road trip"))
    }

    @Test func theMacsDownloadedHasTheDrawingsColumns() {
        #expect(MacDownloaded.columns(.albums) == [.name, .artist, .songs, .size, .here])
        #expect(MacDownloaded.columns(.playlists) == [.name, .songs, .size, .here])
        #expect(MacDownloaded.Column.allCases.map(MacDownloaded.width) == [.flexible, .fixed(132), .fixed(62), .fixed(82),
                                                                          .fixed(158)])
        #expect(MacDownloaded.columns(.albums).map { MacDownloaded.title($0, tab: .albums, device: .mac) }
                    == ["Album", "Artist", "Songs", "Size", "On this Mac"])
        #expect(MacDownloaded.title(.name, tab: .playlists, device: .mac) == "Playlist")
        #expect(MacDownloaded.Tab.allCases.map(MacDownloaded.tabWords) == ["Albums", "Playlists"])
        #expect(MacDownloaded.songs(here: 13, of: 13) == "13" && MacDownloaded.songs(here: 7, of: 13) == "7 of 13")
        // the widths fit the page at the window's opening size, the side panel open (589) and at its smallest (660)
        let fixed = MacDownloaded.Column.allCases.compactMap { (column: MacDownloaded.Column) -> Double? in
            if case .fixed(let points) = MacDownloaded.width(column) { return points }
            return nil
        }
        #expect(fixed.reduce(0, +) == 434)
        #expect(589 - fixed.reduce(0, +) >= 150, "the album's name keeps 150 beside the side panel")
    }

    @Test func anAlbumHereSaysWhenItsLastSongCame() {
        let utc = TimeZone(identifier: "UTC")!
        let now: Int64 = 1_764_072_000_000  // 25 Nov 2025, 12:00 UTC
        let day: Int64 = 86_400_000
        #expect(MacDownloaded.when([now - 3_600_000, nil], now: now, zone: utc) == "today")
        #expect(MacDownloaded.when([now - 9 * day, now - day], now: now, zone: utc) == "yesterday", "the last song's day")
        #expect(MacDownloaded.when([now - 4 * day], now: now, zone: utc) == "4 days ago")
        #expect(MacDownloaded.when([now - 20 * day], now: now, zone: utc) == "5 Nov")
        #expect(MacDownloaded.when([nil, nil], now: now, zone: utc).isEmpty && MacDownloaded.when([], now: now).isEmpty)
    }

    @Test func theMacsDownloadedStatusBarIsDownloadModelsNumbers() {
        let full = MacDownloaded.status(albums: 38, songs: 412, bytes: 11_400_000_000, downloading: 1,
                                        free: 182_000_000_000, device: .mac)
        #expect(full.leading == ["38 albums on this Mac", "412 songs", DeadwaxCore.Bytes.words(11_400_000_000), "1 downloading"])
        #expect(full.trailing == ["\(DeadwaxCore.Bytes.words(182_000_000_000)) free"])
        // nothing is said that is nothing
        let one = MacDownloaded.status(albums: 1, songs: 1, bytes: 9_000_000, downloading: 0, free: nil, device: .mac)
        #expect(one.leading == ["1 album on this Mac", "1 song", DeadwaxCore.Bytes.words(9_000_000)] && one.trailing.isEmpty)
        let empty = MacDownloaded.status(albums: 0, songs: 0, bytes: 0, downloading: 0, free: 1_000_000_000, device: .mac)
        #expect(empty.leading.isEmpty && empty.trailing == ["\(DeadwaxCore.Bytes.words(1_000_000_000)) free"])
        let playlists = MacDownloaded.playlistsStatus(playlists: 2, songs: 30, bytes: 500_000_000, free: nil, device: .mac)
        #expect(playlists.leading == ["2 playlists on this Mac", "30 songs", DeadwaxCore.Bytes.words(500_000_000)])
    }

    @Test func theMacsDownloadsBoxSaysWhatIsHere() {
        #expect(SettingsWords.downloadsFact(albums: 38, songs: 412, bytes: 11_400_000_000)
                == "38 albums \u{00B7} 412 songs \u{00B7} \(DeadwaxCore.Bytes.words(11_400_000_000))")
        #expect(SettingsWords.downloadsFact(albums: 1, songs: 1, bytes: 9_000_000)
                == "1 album \u{00B7} 1 song \u{00B7} \(DeadwaxCore.Bytes.words(9_000_000))")
        // nothing here: the phone's Storage words
        #expect(SettingsWords.downloadsFact(albums: 0, songs: 0, bytes: 0) == DownloadWords.nothingYetHeadline)
    }

    @Test func eachDevicesCancelNoteNamesItsOwnButton() {
        // the phone's words exactly as before: its ✕
        #expect(RequestWords.cancelAsksNote(.iPhone) == RequestWords.confirmCancelNote)
        #expect(RequestWords.cancelAsksNote(.iPhone).contains("\u{2715}"))
        // the Mac's table says Cancel (and Leave): its note names them, never the phone's ✕
        let mac = RequestWords.cancelAsksNote(.mac)
        #expect(!mac.contains("\u{2715}") && mac.contains("Cancel") && mac.contains("Leave") && mac.contains("this Mac"))
    }

    @Test func signInSaysWhereTheSignInIsKept() {
        #expect(SettingsWords.kept(.iPhone).contains("this phone's Keychain"))
        #expect(SettingsWords.kept(.mac).contains("a file on this Mac"))
        for device in Device.allCases { #expect(SettingsWords.kept(device).contains("never your password")) }
    }
}
