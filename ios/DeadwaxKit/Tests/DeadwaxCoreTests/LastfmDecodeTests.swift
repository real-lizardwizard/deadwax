import Foundation
import Testing
@testable import DeadwaxCore

/// deadwax's Last.fm answers as the app reads them. FROM THE SPEC'S SAMPLE: `specSample` is deadwax-plans/lastfm.md
/// 2.5's answer, written before the route (server 2.1.41, built on main beside this slice) existed on this branch -
/// tests/test_ios_contract.py holds LastfmArtist and LastfmTrack to the route itself once main is merged.
@Suite struct LastfmDecodeTests {
    /// lastfm.md 2.5's sample answer, as the spec wrote it (S4's `similar` and `top_albums` included: A1 reads neither).
    static let specSample = """
    {
      "enabled": true,
      "unavailable": false,
      "why": null,
      "url": "https://www.last.fm/music/Tame+Impala",
      "listeners": 2345678,
      "top_songs": [
        {"title": "The Less I Know the Better", "playcount": 98765432, "listeners": 2100000,
         "url": "https://www.last.fm/music/Tame+Impala/_/The+Less+I+Know+the+Better"}
      ],
      "similar": [
        {"name": "MGMT", "mbid": "a3b8...", "match": 0.83, "url": "https://www.last.fm/music/MGMT"}
      ],
      "top_albums": [
        {"title": "Currents", "mbid": "b6a3...", "plays": 456789012, "counted": "plays"}
      ]
    }
    """

    static func read(_ json: String) throws -> LastfmArtist {
        try JSONDecoder().decode(LastfmArtist.self, from: Data(json.utf8))
    }

    @Test func theSpecsSampleReads() throws {
        let answer = try Self.read(Self.specSample)
        #expect(answer.enabled && !answer.unavailable && answer.why == nil)
        #expect(answer.url == "https://www.last.fm/music/Tame+Impala")
        #expect(answer.listeners == 2_345_678)
        #expect(answer.topSongs == [LastfmTrack(title: "The Less I Know the Better", playcount: 98_765_432,
                                                listeners: 2_100_000,
                                                url: "https://www.last.fm/music/Tame+Impala/_/The+Less+I+Know+the+Better")])
    }

    @Test func noKeyAndRefusedRead() throws {
        // the route with no LASTFM_API_KEY (lastfm.py no_key_answer), and refused with nothing kept
        let noKey = try Self.read("""
            {"enabled": false, "unavailable": false, "why": "No Last.fm API key is set", "url": null, "listeners": null,
             "top_songs": null}
            """)
        #expect(!noKey.enabled && !noKey.unavailable && noKey.why == "No Last.fm API key is set")
        #expect(noKey.url == nil && noKey.listeners == nil && noKey.topSongs == nil)
        let refused = try Self.read(#"{"enabled": false, "unavailable": true, "why": "refused", "top_songs": null}"#)
        #expect(!refused.enabled && refused.unavailable)
    }

    @Test func aPartAbsentOrMalformedIsNone() throws {
        let odd = try Self.read("""
            {"enabled": true, "unavailable": false, "why": 3, "url": "http://www.last.fm/music/X", "listeners": "12",
             "top_songs": [{"title": "Roads", "playcount": "many", "listeners": -1, "url": "https://evil.example/x"},
                           {"title": "   "}, {"playcount": 3}, "Glory Box", {"title": "Sour Times", "url": 4}]}
            """)
        #expect(odd.why == nil)
        // only https on last.fm
        #expect(odd.url == nil)
        #expect(odd.listeners == nil)
        #expect(odd.topSongs == [LastfmTrack(title: "Roads"), LastfmTrack(title: "Sour Times")])
        // an answer that says nothing of itself draws nothing and is kept a moment only
        let bare = try Self.read("{}")
        #expect(!bare.enabled && bare.unavailable && bare.topSongs == nil)
        // top_songs not a list: none could be had
        #expect(try Self.read(#"{"enabled": true, "unavailable": false, "top_songs": {}}"#).topSongs == nil)
        #expect(try Self.read(#"{"enabled": true, "unavailable": false, "top_songs": []}"#).topSongs == [])
    }

    /// deadwax's OWN answers (server 2.1.41): Fixtures/lastfm/answers/artist.json, exported by
    /// tests/fixtures/lastfm/answers.py from the route over Last.fm's recorded answers (recorded 2026-11-25) - and
    /// tests/test_lastfm_routes.py holds that copy to the route. Never edited by hand.
    struct Exported: Decodable {
        struct Case: Decodable {
            let name: String
            let query: [String: String]
            let answer: LastfmArtist
        }
        let fixtures: String
        let cases: [Case]
    }

    static func exported() throws -> (cases: [String: Exported.Case], raw: [String: Data], order: [Exported.Case]) {
        let data = try Fixtures.data("lastfm/answers/artist.json")
        let file = try JSONDecoder().decode(Exported.self, from: data)
        #expect(file.fixtures == "recorded")
        let whole = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(whole["cases"] as? [[String: Any]])
        var raw: [String: Data] = [:]
        for row in rows {
            let name = try #require(row["name"] as? String)
            raw[name] = try JSONSerialization.data(withJSONObject: try #require(row["answer"]))
        }
        var cases: [String: Exported.Case] = [:]
        for one in file.cases { cases[one.name] = one }
        return (cases, raw, file.cases)
    }

    static func named(_ cases: [String: Exported.Case], _ start: String) throws -> Exported.Case {
        try #require(cases.first { (name: String, _) -> Bool in name.hasPrefix(start) }?.value, "\(start)")
    }

    @Test func theRoutesOwnAnswersRead() throws {
        let (cases, _, order) = try Self.exported()
        #expect(order.count == 9)
        // Tame Impala: their page, their listeners, Last.fm's ten in its order - drawn whole, nothing waiting on it
        let tame = try Self.named(cases, "Tame Impala, by MusicBrainz id").answer
        #expect(tame.enabled && !tame.unavailable && tame.why == nil)
        #expect(tame.url == "https://www.last.fm/music/Tame+Impala")
        #expect(LastfmWords.listeners(tame.listeners) == "4.7M listeners")
        let songs = try #require(tame.topSongs)
        #expect(songs.count == TopSongs.most)
        #expect(songs.prefix(4).map(\.title) == ["The Less I Know the Better", "Borderline",
                                                 "New Person, Same Old Mistakes", "Let It Happen"])
        #expect(songs.allSatisfy { (song: LastfmTrack) -> Bool in song.url?.hasPrefix("https://www.last.fm/music/") == true })
        #expect(LastfmPage.present(tame))
        let shown = LastfmPage.shown(state: LastfmPage.state(me: .on, answer: tame), online: true, answer: tame,
                                     seesDetail: true)
        #expect(shown == LastfmPage.Shown(heroLine: true, listeners: "4.7M listeners", topSongs: true, foot: nil))
        // their real top songs met with Currents and Lonerism: each one the album has, in Last.fm's order
        let rows = TopSongs.rows(songs, albums: [TopSongsTests.currents, TopSongsTests.lonerism])
        #expect(TopSongsTests.kinds(rows) == ["c2@cur", "missing", "missing", "c1@cur", "l2@lon", "c3@cur", "missing",
                                              "l1@lon", "missing", "missing"])
        // the other two artists: ten each, no title twice by its key - the server's fold, as the app keys them
        for start in ["Dance Gavin Dance", "Portishead"] {
            let theirs = try #require(try Self.named(cases, start).answer.topSongs)
            #expect(theirs.count == TopSongs.most, "\(start)")
            #expect(Set(theirs.map { LastfmMatch.key($0.title) }).count == theirs.count, "\(start)")
        }
        // an id Last.fm doesn't know, asked again by name: the same artist as by the id
        let byName = try Self.named(cases, "an id Last.fm doesn't know").answer
        #expect(byName.url == tame.url && byName.topSongs?.map(\.title) == songs.map(\.title))
    }

    @Test func theRoutesOwnAnswersSayWhatThePageDoes() throws {
        let (cases, _, _) = try Self.exported()
        var kept = LastfmPage.Kept()
        // an artist Last.fm doesn't know: a sure answer with nothing in it - nothing drawn but the line's blank height,
        // and kept for the session
        let unknown = try Self.named(cases, "an artist Last.fm doesn't know").answer
        #expect(!LastfmPage.present(unknown) && !unknown.unavailable)
        #expect(LastfmPage.shown(state: .on, online: true, answer: unknown, seesDetail: true)
            == LastfmPage.Shown(heroLine: true, listeners: nil, topSongs: false, foot: nil))
        kept.keep("ar-1", unknown, asked: "x", now: 0)
        #expect(kept.entry("ar-1", now: 3_600_000) != nil)
        // getInfo failing: the songs, no listeners figure - unavailable, so kept a minute only
        let partly = try Self.named(cases, "getInfo failing").answer
        #expect(partly.unavailable && partly.listeners == nil && partly.topSongs?.count == TopSongs.most)
        #expect(LastfmPage.shown(state: .on, online: true, answer: partly, seesDetail: false)
            == LastfmPage.Shown(heroLine: true, listeners: nil, topSongs: true, foot: nil))
        kept.keep("ar-2", partly, asked: "x", now: 0)
        #expect(kept.entry("ar-2", now: LastfmPage.unsureKeptMs - 1) != nil)
        #expect(kept.entry("ar-2", now: LastfmPage.unsureKeptMs + 1) == nil)
        // Last.fm down with nothing kept: nothing to draw, kept a minute
        let down = try Self.named(cases, "Last.fm down").answer
        #expect(down.enabled && down.unavailable && down.topSongs == nil && !LastfmPage.present(down))
        // refused, nothing kept: refused, though /me still says on - the foot line for whoever runs deadwax alone
        let refused = try Self.named(cases, "Last.fm refusing the key").answer
        #expect(LastfmPage.state(me: .on, answer: refused) == .refused)
        #expect(LastfmPage.shown(state: .refused, online: true, answer: refused, seesDetail: true)
            == LastfmPage.Shown(heroLine: false, listeners: nil, topSongs: false, foot: LastfmWords.footRefused))
        #expect(LastfmPage.shown(state: .refused, online: true, answer: refused, seesDetail: false).foot == nil)
        // no key: off
        let none = try Self.named(cases, "no key").answer
        #expect(LastfmPage.state(me: .on, answer: none) == .off)
        #expect(LastfmPage.shown(state: .off, online: true, answer: none, seesDetail: true).foot == LastfmWords.footOff)
    }

    @Test func eachOfTheRoutesAnswersIsAskedAsTheAppAsksIt() async throws {
        let (_, raw, order) = try Self.exported()
        let (deadwax, transport) = client()
        for one in order {
            transport.answer("/deadwax/lastfm/artist", 200, String(decoding: try #require(raw[one.name]), as: UTF8.self))
            let answer = try await deadwax.lastfmArtist(mbid: one.query["mbid"], name: one.query["name"])
            #expect(answer == one.answer, "\(one.name)")
            let sent = URLComponents(url: try #require(transport.last).url, resolvingAgainstBaseURL: false)?.queryItems
            let wanted = ["mbid", "name"].compactMap { (key: String) -> URLQueryItem? in
                one.query[key].map { URLQueryItem(name: key, value: $0) }
            }
            #expect(sent == wanted, "\(one.name)")
        }
    }

    @Test func aLinkGoesOnlyToLastfm() {
        #expect(LastfmLink.checked("https://www.last.fm/music/Portishead") == "https://www.last.fm/music/Portishead")
        #expect(LastfmLink.checked("https://last.fm/music/Portishead") == "https://last.fm/music/Portishead")
        #expect(LastfmLink.checked("  https://WWW.LAST.FM/music/X  ") == "https://WWW.LAST.FM/music/X")
        #expect(LastfmLink.checked("http://www.last.fm/music/X") == nil)
        #expect(LastfmLink.checked("https://notlast.fm/music/X") == nil)
        #expect(LastfmLink.checked("https://last.fm.example.com/x") == nil)
        #expect(LastfmLink.checked("https://www.last.fm@evil.example/x") == nil)
        #expect(LastfmLink.checked("javascript:alert(1)") == nil)
        // lastfm.py lastfm_url's letters: a backslash (read as "/"), a space, a letter past ASCII, past 2048
        #expect(LastfmLink.checked(#"https://evil.example\.last.fm/x"#) == nil)
        #expect(LastfmLink.checked("https://www.last.fm/music/Tame Impala") == nil)
        #expect(LastfmLink.checked("https://www.last.fm/music/Sigur_R\u{F3}s") == nil)
        let long = "https://www.last.fm/" + String(repeating: "a", count: LastfmLink.most - 20)
        #expect(long.count == LastfmLink.most && LastfmLink.checked(long) == long)
        #expect(LastfmLink.checked(long + "a") == nil)
        // (the review of A1) a host as written: percent-encoded, it's no host on last.fm - as Python's urlparse reads
        // it - while a path's percents are a path's
        #expect(LastfmLink.checked("https://evil.com%2elast.fm/") == nil)
        #expect(LastfmLink.checked("https://%6Cast.fm/x") == nil)
        #expect(LastfmLink.checked("https://www.%6Cast.fm/x") == nil)
        #expect(LastfmLink.checked("https://www.last.fm/music/Sigur+R%C3%B3s") == "https://www.last.fm/music/Sigur+R%C3%B3s")
        #expect(LastfmLink.checked("https://www.last.fm:443/music/X") == "https://www.last.fm:443/music/X")
        #expect(LastfmLink.checked(nil) == nil)
        #expect(LastfmLink.url("https://www.last.fm/music/Tame+Impala")?.host == "www.last.fm")
    }

    @Test func meSaysWhatLastfmIs() throws {
        func me(_ json: String) throws -> Me { try JSONDecoder().decode(Me.self, from: Data(json.utf8)) }
        #expect(try me(#"{"user": "james", "admin": true, "auth": "on", "lastfm": "on"}"#).lastfmState == .on)
        #expect(try me(#"{"user": "james", "admin": true, "auth": "on", "lastfm": "off"}"#).lastfmState == .off)
        #expect(try me(#"{"user": "james", "admin": true, "auth": "on", "lastfm": "refused"}"#).lastfmState == .refused)
        // an older deadwax, or a word this app doesn't know - and read leniently: a number is no failed /me
        #expect(try me(#"{"user": "james", "admin": true, "auth": "on"}"#).lastfmState == .absent)
        #expect(try me(#"{"user": "james", "admin": true, "auth": "on", "lastfm": "limited"}"#).lastfmState == .absent)
        #expect(try me(#"{"user": "james", "admin": true, "auth": "on", "lastfm": 1}"#).lastfmState == .absent)
        // the rest as strictly as before
        #expect(throws: (any Error).self) { try me(#"{"user": "james", "admin": true}"#) }
        #expect(throws: (any Error).self) { try me(#"{"user": "james", "admin": true, "auth": "on", "version": 2}"#) }
        // kept as me.json and read back the same
        let said = Me(user: "ethan", admin: false, auth: "on", version: "2.1.41", permissions: ["request"],
                      permissionsUnverified: false, lastfm: "on")
        #expect(try JSONDecoder().decode(Me.self, from: JSONEncoder().encode(said)) == said)
        #expect(Access(me: said).lastfm == .on)
        #expect(Access(me: Me(user: "ethan", admin: false, auth: "on")).lastfm == .absent)
        #expect(Access(user: "", permissions: [], on: false, unverified: false, admin: false).lastfm == .absent)
    }

    @Test func theAskSendsOnlyWhatTheRouteTakes() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/lastfm/artist", 200, Self.specSample)
        let answer = try await deadwax.lastfmArtist(mbid: "63AA26C3-D59B-4DA4-84AC-716B54F1EF4D", name: " Tame Impala ")
        #expect(answer.listeners == 2_345_678)
        let sent = try #require(transport.last)
        #expect(sent.method == "GET")
        let items = URLComponents(url: sent.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items == [URLQueryItem(name: "mbid", value: "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"),
                          URLQueryItem(name: "name", value: "Tame Impala")])
        // a part it hasn't is left out, never sent empty: the route answers a 422 for `mbid=` or `name=` (1-200 each)
        _ = try await deadwax.lastfmArtist(mbid: nil, name: "Portishead")
        #expect(URLComponents(url: try #require(transport.last).url, resolvingAgainstBaseURL: false)?.queryItems
            == [URLQueryItem(name: "name", value: "Portishead")])
        #expect(try #require(transport.last).url.query?.contains("mbid") == false)
        _ = try await deadwax.lastfmArtist(mbid: "63aa26c3-d59b-4da4-84ac-716b54f1ef4d", name: "   ")
        #expect(URLComponents(url: try #require(transport.last).url, resolvingAgainstBaseURL: false)?.queryItems
            == [URLQueryItem(name: "mbid", value: "63aa26c3-d59b-4da4-84ac-716b54f1ef4d")])
        _ = try await deadwax.lastfmArtist(mbid: "", name: "Portishead")
        #expect(try #require(transport.last).url.query == "name=Portishead")
        // with neither, nothing is asked
        let before = transport.sent.count
        await #expect(throws: APIFailure.self) { try await deadwax.lastfmArtist(mbid: "x", name: "") }
        #expect(transport.sent.count == before)
        #expect(Routes.all.contains(Routes.lastfmArtist))
        #expect(deadwax.request(Routes.lastfmArtist).timeout == nil)
    }
}
