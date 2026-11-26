import Foundation
import Testing
@testable import DeadwaxCore

/// (Last.fm, slice A4 - lastfm.md 3.9 and 4's A4) About at the foot of the artist and album pages: describe.sim's rules
/// that apply, ported - the words, the link only to its own host, the kept minute, the newest answer - and the app's
/// own: the answer read loosely, what each page asks by and when, and the route asked with only what it takes. (Info's
/// About is AboutTests'; this block is AboutBlock.)
@Suite struct AboutBlockTests {
    static let artist = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
    static let group = "48140466-cff6-3222-bd55-63c27e43190d"
    static let release = "a0f0dbb7-4ea8-4b04-a3cb-0d8a1a8e3b26"

    static func drawn(_ text: String?, _ source: AboutBlock.Source? = .lastfm, url: String? = nil,
                      subtitle: String? = nil) -> AboutBlock.Drawn {
        AboutBlock.Drawn(paragraph: text.map { AboutBlock.Paragraph(text: $0, source: source ?? .lastfm, url: url) },
                         subtitle: subtitle)
    }

    static func read(_ json: String) throws -> DescribeAnswer {
        try JSONDecoder().decode(DescribeAnswer.self, from: Data(json.utf8))
    }

    // MARK: the words (describe.sim: SOURCE_WORDS, MORE, LESS)

    @Test func theWordsAreDescribesOwn() {
        #expect(AboutWords.heading == "About")
        #expect(AboutWords.more == "More")
        #expect(AboutWords.less == "Less")
        #expect(AboutWords.source(.wikipedia) == "From Wikipedia")
        #expect(AboutWords.source(.lastfm) == "More on Last.fm")
        #expect(AboutWords.moreWords == "More\u{2026}")
        // VoiceOver: every word - the four lines hide only what is drawn; (A4's review) the heading is an element of
        // its own, a header, so the words don't say it again
        let whole = Self.drawn("Portishead are an English band formed in 1991 in Bristol.", subtitle: "English band")
        #expect(AboutWords.spoken(whole) == "English band, Portishead are an English band formed in 1991 in Bristol.")
        #expect(AboutWords.spoken(Self.drawn("Words.")) == "Words.")
        #expect(AboutWords.spoken(Self.drawn(nil, subtitle: "1994 studio album by Portishead"))
            == "1994 studio album by Portishead")
        // Wikipedia's credit read with the words when it is words; a link is an action of its own, said by its name
        #expect(AboutWords.spoken(Self.drawn("Words.", .wikipedia)) == "Words., From Wikipedia")
        #expect(AboutWords.spoken(Self.drawn("Words.", .wikipedia, url: "https://en.wikipedia.org/wiki/X")) == "Words.")
        #expect(AboutWords.spoken(Self.drawn("Words.", .lastfm, url: "https://www.last.fm/music/X")) == "Words.")
    }

    // MARK: (A4's review) the credit: Wikipedia's always, Last.fm's only with its link

    @Test func wikipediasCreditIsNeverLeftOut() {
        let wikipedia = "https://en.wikipedia.org/wiki/Dummy_(album)"
        #expect(AboutBlock.credited(Self.drawn("W.", .wikipedia, url: wikipedia).paragraph) == .wikipedia)
        // no link, or one that wouldn't go where it says: the credit still drawn, as words
        #expect(AboutBlock.credited(Self.drawn("W.", .wikipedia).paragraph) == .wikipedia)
        #expect(AboutBlock.credited(Self.drawn("W.", .wikipedia, url: "https://evil.example/wiki/X").paragraph)
            == .wikipedia)
        // Last.fm's only with its link: Navidrome's words come as `lastfm` too, and may be Deezer's
        #expect(AboutBlock.credited(Self.drawn("W.", .lastfm, url: "https://www.last.fm/music/X").paragraph) == .lastfm)
        #expect(AboutBlock.credited(Self.drawn("W.", .lastfm).paragraph) == nil)
        #expect(AboutBlock.credited(Self.drawn("W.", .lastfm, url: "https://evil.example/").paragraph) == nil)
        #expect(AboutBlock.credited(nil) == nil)
        #expect(AboutBlock.credited(Self.drawn(nil, subtitle: "English band").paragraph) == nil)
    }

    // MARK: what is drawn of an answer (describe.sim: descriptionOf)

    @Test func anAnswerWithNoWordsDrawsNoBlock() {
        #expect(AboutBlock.of(nil) == nil)
        #expect(AboutBlock.of(DescribeAnswer()) == nil)
        #expect(AboutBlock.of(DescribeAnswer(text: "  \n ", source: "lastfm", subtitle: " ")) == nil)
        // words of a source this doesn't know, with no subtitle: nothing to draw
        #expect(AboutBlock.of(DescribeAnswer(text: "Words.", source: "deezer")) == nil)
        #expect(AboutBlock.of(DescribeAnswer(text: "Words.", source: nil)) == nil)
        // the subtitle alone heads a block of its own; words of an unknown source are left out of it
        #expect(AboutBlock.of(DescribeAnswer(text: "Words.", source: "deezer", subtitle: " English band "))
            == Self.drawn(nil, subtitle: "English band"))
        // trimmed as the web trims
        #expect(AboutBlock.of(DescribeAnswer(text: "\n Portishead are a band. \t", source: "wikipedia",
                                             url: "https://en.wikipedia.org/wiki/Portishead_(band)"))
            == Self.drawn("Portishead are a band.", .wikipedia, url: "https://en.wikipedia.org/wiki/Portishead_(band)"))
    }

    // MARK: the link only to its own host (describe.sim: linkFits)

    @Test func theLinkGoesOnlyToItsOwnHost() {
        let lastfm = ["https://www.last.fm/music/Portishead", "https://last.fm/music/Portishead",
                      "https://www.last.fm/music/Sigur+R%C3%B3s", "https://www.last.fm:443/music/X"]
        for link in lastfm { #expect(AboutBlock.link(.lastfm, link) == link, "\(link)") }
        // (A4's review) an `@` in the title is the page's own; only a name or password before the host is refused
        let wikipedia = ["https://en.wikipedia.org/wiki/Dummy_(album)", "https://en.wikipedia.org/wiki/Sigur_R%C3%B3s",
                         "https://EN.Wikipedia.org/wiki/Dummy_(album)", "https://en.wikipedia.org/wiki/@Home",
                         "https://en.wikipedia.org/wiki/Me@Home_(album)"]
        for link in wikipedia { #expect(AboutBlock.link(.wikipedia, link) == link, "\(link)") }
        // each source's link to the other's host, or anyone else's, is no link
        let refused: [(AboutBlock.Source, String)] = [
            (.lastfm, "https://en.wikipedia.org/wiki/Portishead_(band)"),
            (.wikipedia, "https://www.last.fm/music/Portishead"),
            (.lastfm, "http://www.last.fm/music/Portishead"), (.wikipedia, "http://en.wikipedia.org/wiki/Dummy"),
            (.lastfm, "https://notlast.fm/x"), (.lastfm, "https://a@last.fm/x"),
            (.lastfm, "https://evil.com%2elast.fm/"), (.lastfm, "https://%6Cast.fm/x"),
            (.wikipedia, "https://de.wikipedia.org/wiki/Portishead"), (.wikipedia, "https://en.m.wikipedia.org/wiki/Dummy"),
            (.wikipedia, "https://wikipedia.org/wiki/Dummy"), (.wikipedia, "https://en.wikipedia.org.evil.com/wiki/Dummy"),
            (.wikipedia, "https://en.wikipedia.org@evil.com/wiki/Dummy"), (.wikipedia, "https://evil.com/en.wikipedia.org"),
            (.wikipedia, "https://someone@en.wikipedia.org/wiki/Dummy"),
            (.wikipedia, "https://someone:secret@en.wikipedia.org/wiki/Dummy"),
            (.wikipedia, "https://:secret@en.wikipedia.org/wiki/Dummy"), (.wikipedia, "https://@en.wikipedia.org/wiki/X"),
            (.wikipedia, "https://evil.example\\.en.wikipedia.org/x"), (.wikipedia, "https://en%2ewikipedia.org/x"),
            (.wikipedia, "https://en.wikipedia.org/wiki/Sigur_Rós"), (.wikipedia, "javascript:alert(1)"),
            (.wikipedia, "https://en.wikipedia.org/" + String(repeating: "a", count: AboutBlock.linkMost)),
            (.wikipedia, ""), (.lastfm, ""),
        ]
        for (source, link) in refused { #expect(AboutBlock.link(source, link) == nil, "\(source) \(link)") }
        #expect(AboutBlock.link(.wikipedia, nil) == nil)
        // the paragraph is still drawn - without its link
        let drawn = AboutBlock.of(DescribeAnswer(text: "Words.", source: "wikipedia", url: "https://evil.example/wiki/X"))
        #expect(drawn == Self.drawn("Words.", .wikipedia, url: nil))
        #expect(AboutBlock.url(drawn?.paragraph) == nil)
        let opened = AboutBlock.of(DescribeAnswer(text: "Words.", source: "lastfm", url: "https://www.last.fm/music/Portishead"))
        #expect(AboutBlock.url(opened?.paragraph) == URL(string: "https://www.last.fm/music/Portishead"))
        // a paragraph made by hand with a link to elsewhere opens nothing either: url() checks again
        #expect(AboutBlock.url(AboutBlock.Paragraph(text: "x", source: .lastfm, url: "https://evil.example/")) == nil)
        #expect(AboutBlock.linkMost == 2048)
    }

    // MARK: the answer, read loosely

    @Test func theAnswerIsReadLoosely() throws {
        let whole = try Self.read(#"{"text": "Words.", "source": "lastfm", "url": "https://www.last.fm/music/X", "subtitle": "English band", "unavailable": false}"#)
        #expect(whole == DescribeAnswer(text: "Words.", source: "lastfm", url: "https://www.last.fm/music/X",
                                        subtitle: "English band", unavailable: false))
        // src/descriptions.py NONE: every field null - a sure "none"
        let none = try Self.read(#"{"text": null, "source": null, "url": null, "subtitle": null, "unavailable": false}"#)
        #expect(none == DescribeAnswer())
        #expect(AboutBlock.of(none) == nil)
        // a part of another type is absent; an answer that doesn't say it is whole is taken as not
        let odd = try Self.read(#"{"text": 12, "source": ["lastfm"], "url": {}, "subtitle": true}"#)
        #expect(odd == DescribeAnswer(unavailable: true))
        #expect(try Self.read(#"{"unavailable": "no"}"#).unavailable)
        #expect(try Self.read(#"{"text": "x", "source": "wikipedia", "unavailable": true}"#).unavailable)
    }

    // MARK: what is asked

    @Test func theAskTakesOnlyWhatTheRouteTakes() throws {
        let ask = try #require(AboutBlock.Ask(kind: .artist, mbid: " 8F6BD1E4-FBE1-4F50-AA9B-94C450EC0F11 ",
                                              navidromeId: "  ar-1  "))
        #expect(ask.mbid == Self.artist)
        #expect(ask.navidromeId == "ar-1")
        #expect(ask.key == "artist|\(Self.artist)|ar-1")
        #expect(ask.query.map(\.0) == ["mbid", "navidrome_id"])
        #expect(ask.query.map(\.1) == [Self.artist, "ar-1"])
        // a part the route wouldn't take is left out, never sent
        let idOnly = try #require(AboutBlock.Ask(kind: .album, mbid: "not-an-id", navidromeId: "al-9"))
        #expect(idOnly.mbid == nil && idOnly.query.map(\.0) == ["navidrome_id"])
        #expect(idOnly.key == "album||al-9")
        let long = String(repeating: "x", count: AboutBlock.idMost + 1)
        let mbidOnly = try #require(AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: long))
        #expect(mbidOnly.navidromeId == nil && mbidOnly.query.map(\.0) == ["mbid"])
        #expect(AboutBlock.Ask(kind: .album, mbid: nil, navidromeId: String(repeating: "x", count: AboutBlock.idMost))?
            .navidromeId?.count == AboutBlock.idMost)
        // with neither, nothing is asked
        #expect(AboutBlock.Ask(kind: .artist, mbid: nil, navidromeId: nil) == nil)
        #expect(AboutBlock.Ask(kind: .album, mbid: "", navidromeId: "   ") == nil)
        #expect(AboutBlock.Ask(kind: .album, mbid: "x", navidromeId: long) == nil)
        // the same ids under the other kind are another question
        #expect(AboutBlock.Ask(kind: .artist, mbid: Self.group, navidromeId: nil)?.key
            != AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: nil)?.key)
    }

    @Test func theRouteIsAskedWithOnlyWhatThereIs() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/describe/artist", 200,
                         #"{"text": "Words.", "source": "lastfm", "url": null, "subtitle": null, "unavailable": false}"#)
        transport.answer("/deadwax/describe/album", 200,
                         #"{"text": null, "source": null, "url": null, "subtitle": "1994 studio album", "unavailable": true}"#)
        let artist = try await deadwax.describe(try #require(AboutBlock.Ask(kind: .artist, mbid: Self.artist,
                                                                            navidromeId: "ar-1")))
        #expect(artist.text == "Words." && !artist.unavailable)
        let sent = try #require(transport.last)
        #expect(sent.method == "GET")
        #expect(sent.url.path == "/deadwax/describe/artist")
        #expect(URLComponents(url: sent.url, resolvingAgainstBaseURL: false)?.queryItems
            == [URLQueryItem(name: "mbid", value: Self.artist), URLQueryItem(name: "navidrome_id", value: "ar-1")])
        let album = try await deadwax.describe(try #require(AboutBlock.Ask(kind: .album, mbid: nil, navidromeId: "al-9")))
        #expect(album.subtitle == "1994 studio album" && album.unavailable)
        #expect(try #require(transport.last).url.path == "/deadwax/describe/album")
        #expect(try #require(transport.last).url.query == "navidrome_id=al-9")
        #expect(Routes.all.contains(Routes.describeArtist) && Routes.all.contains(Routes.describeAlbum))
        // nothing waits on the block: it is given the facts' time to land late rather than fail
        #expect(deadwax.request(Routes.describeArtist).timeout == Routes.timeouts[Routes.artistFacts])
        #expect(deadwax.request(Routes.describeAlbum).timeout == Routes.timeouts[Routes.artistFacts])
    }

    // MARK: when each page asks

    @Test func theArtistPageAsksOnceWhoTheyAreIsSettled() {
        func question(answered: Bool = true, gone: Bool = false, mbid: String? = Self.artist, indexKnown: Bool = true,
                      waited: Bool = false, factsSettled: Bool = true) -> AboutBlock.Question {
            AboutBlock.artist(answered: answered, gone: gone, navidromeId: "ar-1", mbid: mbid, indexKnown: indexKnown,
                              waited: waited, factsSettled: factsSettled)
        }
        let both = AboutBlock.Question.ask(AboutBlock.Ask(kind: .artist, mbid: Self.artist, navidromeId: "ar-1")!)
        #expect(question() == both)
        // their answer not in hand: unsettled; gone from Navidrome: nothing
        #expect(question(answered: false) == .unsettled)
        #expect(question(gone: true) == .nothing)
        // an id known: asked once MusicBrainz has said who they are (or failed to) - the lookup deadwax shares
        #expect(question(factsSettled: false) == .unsettled)
        #expect(question(indexKnown: false, factsSettled: true) == both)
        // no id: the library's folders may still say, until they answer or have been waited for
        #expect(question(mbid: nil, indexKnown: false) == .unsettled)
        let byId = AboutBlock.Question.ask(AboutBlock.Ask(kind: .artist, mbid: nil, navidromeId: "ar-1")!)
        #expect(question(mbid: nil, indexKnown: false, waited: true) == byId)
        #expect(question(mbid: nil, factsSettled: false) == byId)
        #expect(question(mbid: "not-one", indexKnown: true) == byId)
        #expect(AboutBlock.artist(answered: true, gone: false, navidromeId: " ", mbid: nil, indexKnown: true,
                                  waited: false, factsSettled: true) == .nothing)
    }

    @Test func theAlbumPageAsksByItsReleaseGroupAndNavidromesId() {
        let index = OwnedIndex([
            OwnedAlbum(path: "P/Dummy (no group)", releaseMbid: Self.release),
            OwnedAlbum(path: "P/Dummy", releaseMbid: Self.release, releaseGroupMbid: Self.group.uppercased()),
            OwnedAlbum(path: "P/Other", releaseMbid: "11111111-2222-3333-4444-555555555555",
                       releaseGroupMbid: "66666666-7777-8888-9999-000000000000"),
        ])
        func question(answered: Bool = true, gone: Bool = false, id: String? = "al-9", release: String? = Self.release,
                      storeGroup: String? = nil, index: OwnedIndex? = index,
                      ownedSettled: Bool = false) -> AboutBlock.Question {
            AboutBlock.album(answered: answered, gone: gone, navidromeId: id, release: release, storeGroup: storeGroup,
                             index: index, ownedSettled: ownedSettled)
        }
        // the group the first folder naming one says, lowercased as the route takes it, and Navidrome's id
        #expect(question() == .ask(AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: "al-9")!))
        #expect(question(ownedSettled: true) == question())
        #expect(question(release: Self.release.uppercased()) == question())
        #expect(question(answered: false) == .unsettled)
        #expect(question(gone: true) == .nothing)
        // (A4's review) a pressing to look up and no word of the folders in hand - /library/owned still out, or not yet
        // asked: unsettled, however long; asked by Navidrome's id alone only once it has answered without one, or failed
        #expect(question(index: nil) == .unsettled)
        let byId = AboutBlock.Question.ask(AboutBlock.Ask(kind: .album, mbid: nil, navidromeId: "al-9")!)
        #expect(question(index: nil, ownedSettled: true) == byId)
        // the id bridge's group, the web's own source, first - at once, the folders unasked, or naming another
        let bridged = "77777777-7777-7777-7777-777777777777"
        let byBridge = AboutBlock.Question.ask(AboutBlock.Ask(kind: .album, mbid: bridged, navidromeId: "al-9")!)
        #expect(question(storeGroup: bridged.uppercased(), index: nil) == byBridge)
        #expect(question(storeGroup: bridged) == byBridge)
        #expect(question(release: nil, storeGroup: bridged, index: nil) == byBridge)
        // a bridge with no group, or one not of MusicBrainz's shape, says nothing: the folders as before
        #expect(question(storeGroup: "", index: nil) == .unsettled)
        #expect(question(storeGroup: "not-one") == question())
        #expect(question(answered: false, storeGroup: bridged) == .unsettled)
        #expect(question(gone: true, storeGroup: bridged) == .nothing)
        // no pressing: nothing to wait for
        #expect(question(release: nil, index: nil) == byId)
        #expect(question(release: "22222222-2222-2222-2222-222222222222") == byId)
        // with neither id, nothing is asked
        #expect(question(id: nil, release: nil) == .nothing)
        #expect(question(id: "", release: "22222222-2222-2222-2222-222222222222") == .nothing)
        #expect(question(id: nil) == .ask(AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: nil)!))
    }

    /// (A4's review) The album page as it settles - the album, then the library's folders after their ask - draws
    /// one answer, never Navidrome's words and then Last.fm's in their place.
    @Test func theAlbumPageDrawsOneAnswerNeverTwo() {
        let index = OwnedIndex([OwnedAlbum(path: "P/Dummy", releaseMbid: Self.release, releaseGroupMbid: Self.group)])
        let byGroup = AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: "al-9")!
        let byId = AboutBlock.Ask(kind: .album, mbid: nil, navidromeId: "al-9")!
        let answers = [byGroup.key: Self.drawn("Last.fm's words.", subtitle: "1994 studio album by Portishead"),
                       byId.key: Self.drawn("Navidrome's words.")]
        // each moment: the album in hand, the folders' word (none yet; asked and out; answered), the bridge's group
        typealias Moment = (album: Bool, index: OwnedIndex?, settled: Bool, bridge: String?)
        func run(_ moments: [Moment]) -> (asked: [String], drawn: [AboutBlock.Drawn]) {
            var kept = AboutBlock.Kept()
            var showing = AboutBlock.Showing()
            var asked: [String] = []
            var drawn: [AboutBlock.Drawn] = []
            for (n, moment) in moments.enumerated() {
                let now = Double(n)
                let question = AboutBlock.album(answered: moment.album, gone: false, navidromeId: "al-9",
                                                release: moment.album ? Self.release : nil, storeGroup: moment.bridge,
                                                index: moment.index, ownedSettled: moment.settled)
                showing.update(page: "me|al-9", question: question, kept: &kept, own: nil, now: now)
                if let ask = AboutBlock.asks(question, kept: &kept, now: now) {
                    // deadwax answers before the next moment
                    asked.append(ask.key)
                    kept.keep(ask.key, answers[ask.key], unsure: false, now: now)
                    showing.update(page: "me|al-9", question: question, kept: &kept, own: (ask.key, answers[ask.key]),
                                   now: now)
                }
                if let now = showing.drawn(for: "me|al-9"), drawn.last != now { drawn.append(now) }
            }
            return (asked, drawn)
        }
        // opened cold: the album lands, /library/owned is asked and out for longer than the old 1.5 s, then answers
        let cold = run([(false, nil, false, nil), (true, nil, false, nil), (true, nil, false, nil),
                        (true, nil, false, nil), (true, index, true, nil), (true, index, true, nil)])
        #expect(cold.asked == [byGroup.key])
        #expect(cold.drawn == [answers[byGroup.key]!])
        // the bridge's group in hand: asked at once, and the folders landing later ask nothing more
        let bridged = run([(true, nil, false, Self.group), (true, index, true, Self.group)])
        #expect(bridged.asked == [byGroup.key] && bridged.drawn == [answers[byGroup.key]!])
        // the folders' ask failed (or named no group): Navidrome's id alone, once
        let failed = run([(true, nil, false, nil), (true, nil, true, nil), (true, nil, true, nil)])
        #expect(failed.asked == [byId.key] && failed.drawn == [answers[byId.key]!])
    }

    /// (A4's review) Each question has its own token - the page's task asks again on a new one - an ask's its key.
    @Test func eachQuestionHasATokenOfItsOwn() {
        let one = AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: "al-9")!
        let other = AboutBlock.Ask(kind: .album, mbid: nil, navidromeId: "al-9")!
        let artist = AboutBlock.Ask(kind: .artist, mbid: nil, navidromeId: "al-9")!
        let tokens = [AboutBlock.Question.unsettled, .nothing, .ask(one), .ask(other), .ask(artist)].map(\.token)
        #expect(Set(tokens).count == tokens.count)
        #expect(AboutBlock.Question.ask(one).token == one.key)
        #expect(AboutBlock.Question.ask(other).token == other.key)
        #expect(AboutBlock.Question.ask(one).key == one.key)
        #expect(AboutBlock.Question.unsettled.key == nil && AboutBlock.Question.nothing.key == nil)
    }

    // MARK: the kept minute (describe.sim: keepDescription, keptDescription, UNSURE_KEPT_MS)

    @Test func anUnsureAnswerIsKeptAMinuteAndASureOneTheSession() {
        #expect(AboutBlock.unsureKeptMs == 60_000)
        #expect(AboutBlock.kept == 200)
        var kept = AboutBlock.Kept()
        let words = Self.drawn("Words.")
        kept.keep("sure", words, unsure: false, now: 1_000)
        kept.keep("unsure", words, unsure: true, now: 1_000)
        kept.keep("failed", nil, unsure: true, now: 1_000)
        kept.keep("none", nil, unsure: false, now: 1_000)
        let ask = AboutBlock.Ask(kind: .artist, mbid: nil, navidromeId: "ar-1")!
        kept.keep(ask.key, words, unsure: true, now: 1_000)
        #expect(kept.found("unsure", now: 60_999) == .some(words))
        #expect(kept.found("failed", now: 60_999) == .some(nil))
        #expect(AboutBlock.asks(.ask(ask), kept: &kept, now: 60_999) == nil)
        // its minute over: as if never kept - asked again
        #expect(kept.found("unsure", now: 61_000) == nil)
        #expect(kept.found("failed", now: 61_000) == nil)
        #expect(AboutBlock.asks(.ask(ask), kept: &kept, now: 61_000) == ask)
        // a sure answer - a description or "none" - for the session
        #expect(kept.found("sure", now: 1_000_000_000) == .some(words))
        #expect(kept.found("none", now: 1_000_000_000) == .some(nil))
        #expect(kept.found("never", now: 0) == nil)
        // a sure answer over an unsure one is kept for the session; an unsure one over a sure one a minute
        kept.keep("unsure", words, unsure: false, now: 2_000)
        #expect(kept.found("unsure", now: 1_000_000) == .some(words))
        kept.keep("sure", nil, unsure: true, now: 2_000)
        #expect(kept.found("sure", now: 62_000) == nil)
    }

    @Test func theSessionKeepsTheMostRecentlyUsed() {
        var kept = AboutBlock.Kept()
        for n in 0..<AboutBlock.kept { kept.keep("k\(n)", nil, unsure: false, now: 0) }
        // read: the most recently used, so the oldest unread goes first
        #expect(kept.found("k0", now: 0) == .some(nil))
        kept.keep("new", nil, unsure: false, now: 0)
        #expect(kept.count == AboutBlock.kept)
        #expect(kept.found("k0", now: 0) != nil)
        #expect(kept.found("k1", now: 0) == nil)
        // each page's last question, the most recent `kept` pages
        kept.remember(page: "p0", key: "a")
        kept.remember(page: "p0", key: "b")
        #expect(kept.pageKey("p0") == "b")
        for n in 1...AboutBlock.kept { kept.remember(page: "p\(n)", key: "x") }
        #expect(kept.pageKey("p0") == nil)
        #expect(kept.pageKey("p\(AboutBlock.kept)") == "x")
    }

    // MARK: the newest answer (describe.sim: useDescription's rules)

    @Test func onlyTheAnswerToThePagesQuestionNowDraws() {
        var kept = AboutBlock.Kept()
        var showing = AboutBlock.Showing()
        let first = AboutBlock.Ask(kind: .artist, mbid: nil, navidromeId: "ar-1")!
        let second = AboutBlock.Ask(kind: .artist, mbid: Self.artist, navidromeId: "ar-1")!
        let old = Self.drawn("By Navidrome's id.")
        let new = Self.drawn("By their MusicBrainz id.")
        // asked: nothing yet, not settled
        showing.update(page: "me|ar-1", question: .ask(first), kept: &kept, own: nil, now: 0)
        #expect(showing.drawn == nil && !showing.settled)
        #expect(AboutBlock.asks(.ask(first), kept: &kept, now: 0) == first)
        // the question changed while the first was out: its answer, landing late, draws nothing
        showing.update(page: "me|ar-1", question: .ask(second), kept: &kept, own: (first.key, old), now: 1)
        #expect(showing.drawn == nil && !showing.settled)
        // the newest question's own answer draws
        showing.update(page: "me|ar-1", question: .ask(second), kept: &kept, own: (second.key, new), now: 2)
        #expect(showing.drawn == new && showing.settled)
        // a question that changes again keeps what is drawn until its answer replaces it - never gone and back
        showing.update(page: "me|ar-1", question: .unsettled, kept: &kept, own: (second.key, new), now: 3)
        #expect(showing.drawn == new)
        showing.update(page: "me|ar-1", question: .ask(first), kept: &kept, own: (second.key, new), now: 4)
        #expect(showing.drawn == new && !showing.settled)
        kept.keep(first.key, old, unsure: false, now: 5)
        showing.update(page: "me|ar-1", question: .ask(first), kept: &kept, own: (second.key, new), now: 5)
        #expect(showing.drawn == old)
        #expect(AboutBlock.asks(.ask(first), kept: &kept, now: 5) == nil)
        // nothing to ask by: no block
        showing.update(page: "me|ar-1", question: .nothing, kept: &kept, own: (second.key, new), now: 6)
        #expect(showing.drawn == nil && showing.settled)
        #expect(AboutBlock.asks(.nothing, kept: &kept, now: 6) == nil)
        #expect(AboutBlock.asks(.unsettled, kept: &kept, now: 6) == nil)
        // another page starts with nothing, whatever this one drew
        showing.update(page: "me|ar-1", question: .ask(first), kept: &kept, own: nil, now: 7)
        #expect(showing.drawn(for: "me|ar-1") == old)
        #expect(showing.drawn(for: "me|ar-2") == nil)
        showing.update(page: "me|ar-2", question: .unsettled, kept: &kept, own: nil, now: 8)
        #expect(showing.drawn == nil && showing.page == "me|ar-2")
    }

    @Test func aPageComeBackToDrawsItsKeptAnswerWhileItsIdsSettle() {
        var kept = AboutBlock.Kept()
        let ask = AboutBlock.Ask(kind: .album, mbid: Self.group, navidromeId: "al-9")!
        let words = Self.drawn("Dummy is the debut album.", subtitle: "1994 studio album by Portishead")
        var visit = AboutBlock.Showing()
        visit.update(page: "me|al-9", question: .ask(ask), kept: &kept, own: nil, now: 0)
        kept.keep(ask.key, words, unsure: false, now: 1)
        visit.update(page: "me|al-9", question: .ask(ask), kept: &kept, own: (ask.key, words), now: 1)
        #expect(visit.drawn == words)
        // the page opened again: its release group not yet looked up - what it was answered last time, at once
        var again = AboutBlock.Showing()
        again.update(page: "me|al-9", question: .unsettled, kept: &kept, own: nil, now: 2)
        #expect(again.drawn == words && again.settled)
        // ...but never another page's
        var other = AboutBlock.Showing()
        other.update(page: "me|al-10", question: .unsettled, kept: &kept, own: nil, now: 2)
        #expect(other.drawn == nil && !other.settled)
        // offline with nothing kept: nothing; an unsure answer past its minute is not drawn on a new visit
        kept.keep(ask.key, words, unsure: true, now: 10)
        var late = AboutBlock.Showing()
        late.update(page: "me|al-9", question: .ask(ask), kept: &kept, own: nil, now: 60_010)
        #expect(late.drawn == nil && !late.settled)
    }
}
