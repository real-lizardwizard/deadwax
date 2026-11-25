import Testing
@testable import DeadwaxCore

/// How Last.fm's answer comes onto an artist page (lastfm.md 3.1): the wait, the place judged once, what is drawn with
/// Last.fm on, off or refused and for whom, and what the session keeps.
@Suite struct LastfmPageTests {
    static let songs = LastfmArtist(listeners: 2_345_678, topSongs: [LastfmTrack(title: "Let It Happen")])
    static let none = LastfmArtist(listeners: 10, topSongs: [])

    @Test func theNumbersAreTheSpecs() {
        #expect(LastfmPage.waitMs == 800)
        #expect(LastfmPage.kept == 64)
        #expect(LastfmPage.unsureKeptMs == 60_000)
        #expect(TopSongs.shown == 5)
        #expect(TopSongs.most == 10)
    }

    @Test func thePlaceIsJudgedOnceAsDescribeTsJudgesIt() {
        #expect(LastfmPage.placeOf(was: nil, present: false, albumsDrawn: false) == nil)
        #expect(LastfmPage.placeOf(was: nil, present: false, albumsDrawn: true) == nil)
        #expect(LastfmPage.placeOf(was: nil, present: true, albumsDrawn: false) == .inPlace)
        #expect(LastfmPage.placeOf(was: nil, present: true, albumsDrawn: true) == .afterAlbums)
        // once put somewhere it stays there, whatever comes after
        #expect(LastfmPage.placeOf(was: .inPlace, present: true, albumsDrawn: true) == .inPlace)
        #expect(LastfmPage.placeOf(was: .afterAlbums, present: false, albumsDrawn: false) == .afterAlbums)
    }

    @Test func anAnswerInsideTheWaitGoesInPlace() {
        var arrival = LastfmPage.Arrival(state: .on, online: true, kept: nil)
        #expect(arrival.holding)
        #expect(arrival.place == nil)
        arrival.answered(present: true)
        #expect(!arrival.holding)
        #expect(arrival.place == .inPlace)
    }

    @Test func aLateAnswerGoesAfterTheAlbumsForThePagesLife() {
        var arrival = LastfmPage.Arrival(state: .on, online: true, kept: nil)
        arrival.release()
        #expect(!arrival.holding)
        arrival.answered(present: true)
        #expect(arrival.place == .afterAlbums)
        // a pull that brings another answer leaves it where it went
        arrival.answered(present: true)
        #expect(arrival.place == .afterAlbums)
    }

    @Test func anAnswerWithNothingToDrawReleasesThePageAndPlacesNothing() {
        var arrival = LastfmPage.Arrival(state: .on, online: true, kept: nil)
        arrival.answered(present: false)
        #expect(!arrival.holding)
        #expect(arrival.place == nil)
        // songs that come later (a pull) come after the albums
        arrival.answered(present: true)
        #expect(arrival.place == .afterAlbums)
    }

    @Test func aPageWaitsOnlyWithLastfmOnAndDeadwaxInReach() {
        #expect(LastfmPage.Arrival(state: .on, online: true, kept: nil).holding)
        for state in [LastfmState.off, .refused, .absent] {
            #expect(!LastfmPage.Arrival(state: state, online: true, kept: nil).holding, "\(state)")
        }
        #expect(!LastfmPage.Arrival(state: .on, online: false, kept: nil).holding)
    }

    @Test func aKeptAnswerDrawsAtOnceInPlace() {
        let kept = LastfmPage.Arrival(state: .on, online: true, kept: true)
        #expect(!kept.holding)
        #expect(kept.place == .inPlace)
        let keptEmpty = LastfmPage.Arrival(state: .on, online: true, kept: false)
        #expect(!keptEmpty.holding)
        #expect(keptEmpty.place == nil)
    }

    @Test func nothingOfLastfmsIsDrawnUnlessItIsOn() {
        for state in [LastfmState.off, .refused, .absent] {
            for online in [true, false] {
                let shown = LastfmPage.shown(state: state, online: online, answer: Self.songs, seesDetail: false)
                #expect(!shown.heroLine, "\(state) \(online)")
                #expect(shown.listeners == nil)
                #expect(!shown.topSongs)
                #expect(shown.foot == nil)
            }
        }
        let on = LastfmPage.shown(state: .on, online: true, answer: Self.songs, seesDetail: false)
        #expect(on == LastfmPage.Shown(heroLine: true, listeners: "2.3M listeners", topSongs: true, foot: nil))
    }

    @Test func theHeroLineKeepsItsHeightFromTheFirstFrame() {
        // online, before any answer: the line is there, blank
        let asking = LastfmPage.shown(state: .on, online: true, answer: nil, seesDetail: false)
        #expect(asking.heroLine && asking.listeners == nil && !asking.topSongs)
        // offline, an answer in hand: it stays; none: no line, and no gap
        #expect(LastfmPage.shown(state: .on, online: false, answer: Self.songs, seesDetail: false).heroLine)
        #expect(!LastfmPage.shown(state: .on, online: false, answer: nil, seesDetail: false).heroLine)
        // an answer with no listeners keeps the line blank; one with no songs draws no section
        let quiet = LastfmPage.shown(state: .on, online: true, answer: LastfmArtist(topSongs: nil), seesDetail: false)
        #expect(quiet.heroLine && quiet.listeners == nil && !quiet.topSongs)
        #expect(!LastfmPage.shown(state: .on, online: true, answer: Self.none, seesDetail: false).topSongs)
        // an answer that says Last.fm isn't enabled draws none of what it holds
        let disabled = LastfmArtist(enabled: false, listeners: 5, topSongs: [LastfmTrack(title: "Roads")])
        let off = LastfmPage.shown(state: .on, online: true, answer: disabled, seesDetail: false)
        #expect(off.listeners == nil && !off.topSongs)
    }

    /// (The review of A1) Once a page has drawn the hero's line, its height stays: Play never moves.
    @Test func theHeroLinesHeightStaysOnceThePageHasDrawnIt() {
        let refused = LastfmArtist(enabled: false, unavailable: true)
        // /me said on - the line drawn - then the answer says Last.fm refuses the key
        #expect(LastfmPage.drawsLine(state: .on, online: true, answer: nil))
        let state = LastfmPage.state(me: .on, answer: refused)
        #expect(!LastfmPage.shown(state: state, online: true, answer: refused, seesDetail: false).heroLine)
        #expect(LastfmPage.shown(state: state, online: true, answer: refused, seesDetail: true, reserved: true)
            == LastfmPage.Shown(heroLine: true, listeners: nil, topSongs: false, foot: LastfmWords.footRefused))
        let off = LastfmArtist(enabled: false, unavailable: false)
        #expect(LastfmPage.shown(state: LastfmPage.state(me: .on, answer: off), online: true, answer: off,
                                 seesDetail: false, reserved: true).heroLine)
        // deadwax out of reach before any answer
        #expect(!LastfmPage.shown(state: .on, online: false, answer: nil, seesDetail: false).heroLine)
        #expect(LastfmPage.shown(state: .on, online: false, answer: nil, seesDetail: false, reserved: true)
            == LastfmPage.Shown(heroLine: true, listeners: nil, topSongs: false, foot: nil))
        // the rule a page keeps the line by is the one it draws by
        for state in [LastfmState.on, .off, .refused, .absent] {
            for online in [true, false] {
                for answer in [nil, LastfmArtist(listeners: 3), off] {
                    #expect(LastfmPage.drawsLine(state: state, online: online, answer: answer)
                        == LastfmPage.shown(state: state, online: online, answer: answer, seesDetail: true).heroLine)
                }
            }
        }
        #expect(LastfmPage.drawsLine(state: .on, online: false, answer: LastfmArtist(listeners: 3)))
        #expect(!LastfmPage.drawsLine(state: .on, online: false, answer: off))
        #expect(!LastfmPage.drawsLine(state: .off, online: true, answer: LastfmArtist()))
    }

    @Test func theFootLineIsForWhoeverRunsDeadwaxOnly() {
        #expect(LastfmPage.shown(state: .off, online: true, answer: nil, seesDetail: true).foot == LastfmWords.footOff)
        #expect(LastfmPage.shown(state: .refused, online: true, answer: nil, seesDetail: true).foot
            == LastfmWords.footRefused)
        #expect(LastfmPage.shown(state: .on, online: true, answer: nil, seesDetail: true).foot == nil)
        // an older deadwax has no LASTFM_API_KEY to point at
        #expect(LastfmPage.shown(state: .absent, online: true, answer: nil, seesDetail: true).foot == nil)
        for state in [LastfmState.on, .off, .refused, .absent] {
            #expect(LastfmPage.shown(state: state, online: true, answer: nil, seesDetail: false).foot == nil)
        }
    }

    @Test func anAnswerSayingLastfmIsntEnabledIsBelievedOverAnOlderMe() {
        // /me said on; the route then found the key refused (its parts unavailable) or gone (nothing asked)
        let refused = LastfmArtist(enabled: false, unavailable: true, why: "Last.fm refused deadwax's API key")
        let noKey = LastfmArtist(enabled: false, unavailable: false, why: "No Last.fm API key is set")
        #expect(LastfmPage.state(me: .on, answer: refused) == .refused)
        #expect(LastfmPage.state(me: .on, answer: noKey) == .off)
        #expect(LastfmPage.state(me: .on, answer: Self.songs) == .on)
        #expect(LastfmPage.state(me: .on, answer: nil) == .on)
        // never the other way: /me's off or refused draws nothing, whatever an answer kept says
        #expect(LastfmPage.state(me: .off, answer: Self.songs) == .off)
        #expect(LastfmPage.state(me: .refused, answer: Self.songs) == .refused)
        #expect(LastfmPage.state(me: .absent, answer: Self.songs) == .absent)
    }

    @Test func whatIsPresentIsSongsToDraw() {
        #expect(LastfmPage.present(Self.songs))
        #expect(!LastfmPage.present(Self.none))
        #expect(!LastfmPage.present(nil))
        #expect(!LastfmPage.present(LastfmArtist(enabled: false, topSongs: [LastfmTrack(title: "Roads")])))
    }

    @Test func theSessionKeepsTheLast64AndAnUnsureAnswerAMinute() {
        func held(_ kept: LastfmPage.Kept, _ id: String, _ now: Double) -> LastfmPage.Kept.Held? {
            kept.entry(id, now: now)?.held
        }
        var kept = LastfmPage.Kept()
        kept.keep("a", Self.songs, asked: "|Tame Impala", now: 0)
        #expect(kept.entry("a", now: 10_000_000) == LastfmPage.Kept.Entry(held: .answer(Self.songs), asked: "|Tame Impala"))
        // unavailable, not enabled, or a failure: kept a minute, then asked again
        let unavailable = LastfmArtist(unavailable: true, topSongs: nil)
        kept.keep("b", unavailable, asked: "b", now: 1_000)
        #expect(held(kept, "b", 1_000 + 59_999) == .answer(unavailable))
        #expect(held(kept, "b", 1_000 + 60_000) == nil)
        kept.keep("c", LastfmArtist(enabled: false), asked: "c", now: 0)
        #expect(held(kept, "c", 60_000) == nil)
        kept.keep("d", nil, asked: "d", now: 0)
        #expect(held(kept, "d", 1) == .failed)
        #expect(held(kept, "d", 1)?.answer == nil)
        #expect(held(kept, "d", 60_000) == nil)
        // kept again: the newest, and sure again
        kept.keep("b", Self.songs, asked: "b", now: 2_000)
        #expect(held(kept, "b", 1_000_000) == .answer(Self.songs))
        // past 64 the oldest kept goes first
        var many = LastfmPage.Kept()
        for at in 0..<64 { many.keep("artist-\(at)", Self.songs, asked: "", now: 0) }
        many.keep("artist-0", Self.none, asked: "", now: 0)
        many.keep("artist-64", Self.songs, asked: "", now: 0)
        #expect(many.count == 64)
        #expect(held(many, "artist-1", 0) == nil)
        #expect(held(many, "artist-0", 0) == .answer(Self.none))
        #expect(held(many, "artist-64", 0) == .answer(Self.songs))
    }

    @Test func anAskIsWhatTheRouteTakes() {
        let mbid = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"
        #expect(LastfmPage.Ask(mbid: nil, name: nil) == nil)
        #expect(LastfmPage.Ask(mbid: "not-an-id", name: "  ") == nil)
        let both = LastfmPage.Ask(mbid: " 63AA26C3-D59B-4DA4-84AC-716B54F1EF4D ", name: "  Tame Impala ")
        #expect(both?.mbid == mbid)
        #expect(both?.name == "Tame Impala")
        #expect(both?.key == "\(mbid)|Tame Impala")
        // a name longer than the route's 200 is left out - asked by the id alone, or not at all
        let long = String(repeating: "a", count: 201)
        #expect(LastfmPage.Ask(mbid: mbid, name: long)?.name == nil)
        #expect(LastfmPage.Ask(mbid: nil, name: long) == nil)
        #expect(LastfmPage.Ask(mbid: nil, name: String(repeating: "a", count: 200))?.name?.count == 200)
    }
}
