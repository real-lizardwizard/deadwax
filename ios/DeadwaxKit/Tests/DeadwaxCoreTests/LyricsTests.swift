import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/lyrics/: what the web's TypeScript (lyrics-vectors.json, ios/scripts/export-lyrics-vectors.cjs) and the
/// server's song_lyrics() (answers.json, ios/scripts/lyrics_answers.py) answer - never written by hand - and the shapes
/// they are read into.
enum LyricsVectors {
    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Fixtures.data("lyrics/\(name).json"))
    }

    struct Vectors: Decodable {
        struct Words: Decodable {
            let LYRICS, LYRICS_NONE, LYRICS_NOT_KEPT, LOADING_LYRICS, NO_LYRICS, NOTHING_PLAYING, NOT_SYNCED: String
            let LYRICS_FAILED, SONG_GONE, LINE_HINT, GO_TO_LIT: String
        }
        struct Constants: Decodable {
            let LYRICS_ANCHOR, FOLLOW_AGAIN_MS, GAP_DOTS_S, NEXT_LYRICS_S, LANDED_WITHIN_S: Double
            let LYRICS_KEPT: Int
        }
        struct HaveCase: Decodable { let name: String; let lyrics: SongLyrics?; let have: String }
        struct LabelCase: Decodable { let have: String; let label: String }
        struct DimmedCase: Decodable { let have: String; let on: Bool; let dimmed: Bool }
        struct ClockCase: Decodable { let raw: Double; let reported: Double; let clock: Double }
        struct RunsCase: Decodable { let shows, playing, covered, visible, runs: Bool }
        struct Range: Decodable, Equatable { let first: Int; let last: Int }
        struct LitCase: Decodable { let range: Range?; let dots: Int }
        struct At: Decodable {
            let t: Double
            let litRange: Range?
            let drawnRange: Range?
            let litAt: LitCase
            let gapDots: [Int]
        }
        struct Outside: Decodable { let i: Int; let t: Double; let dots: Int }
        struct LineSet: Decodable {
            let name: String
            let lines: [LyricLine]
            let withIntro: [LyricLine]
            let sung: [Bool]
            let at: [At]
            let gapDotsOutside: [Outside]
        }
        struct SameCase: Decodable { let a: LitCase; let b: LitCase; let same: Bool }
        struct TopCase: Decodable { let lineTop: Double; let height: Double; let top: Double }
        struct RoomCase: Decodable { let height: Double; let room: Double }
        struct FollowsCase: Decodable { let now: Double; let heldAt: Double?; let playing: Bool; let focused: Bool?; let follows: Bool }
        struct ValueCase: Decodable { let time: Double; let lit: Bool; let value: String }
        struct AheadCase: Decodable { let position: Double; let duration: Double; let asks: Bool }
        struct KeptStep: Decodable {
            let op: String
            let id: String
            let value: SongLyrics?
            let returned: SongLyrics?
            let order: [String]
            let values: [SongLyrics]?
        }
        struct KeptRun: Decodable { let most: Int?; let steps: [KeptStep] }
        struct Kept: Decodable { let small: KeptRun; let standard: KeptRun }

        let words: Words
        let constants: Constants
        let have: [HaveCase]
        let label: [LabelCase]
        let dimmed: [DimmedCase]
        let clock: [ClockCase]
        let clockRuns: [RunsCase]
        let sets: [LineSet]
        let sameLit: [SameCase]
        let followTop: [TopCase]
        let endRoom: [RoomCase]
        let follows: [FollowsCase]
        let followsDefault: [FollowsCase]
        let lineValue: [ValueCase]
        let asksAhead: [AheadCase]
        let kept: Kept
    }

    struct Answers: Decodable {
        struct Case: Decodable {
            let name: String
            let answer: SongLyrics
        }
        let cases: [Case]
    }

    static func vectors() throws -> Vectors { try load(Vectors.self, "lyrics-vectors") }
}

extension LitRange {
    init(_ range: LyricsVectors.Vectors.Range) { self.init(first: range.first, last: range.last) }
}

extension Lit {
    init(_ lit: LyricsVectors.Vectors.LitCase) { self.init(range: lit.range.map(LitRange.init), dots: lit.dots) }
}

private func have(_ raw: String) throws -> LyricsHave {
    try #require(LyricsHave(rawValue: raw), "\(raw) isn't a LyricsHave")
}

/// The web's lyrics rules (lib/lyricsView.ts), ported: every case the TypeScript answers, replayed.
@Suite struct LyricsVectorTests {
    @Test func theWordsAreTheWebsVerbatim() throws {
        let words = try LyricsVectors.vectors().words
        #expect(LyricsWords.lyrics == words.LYRICS)
        #expect(LyricsWords.none == words.LYRICS_NONE)
        #expect(LyricsWords.notKept == words.LYRICS_NOT_KEPT)
        #expect(LyricsWords.loading == words.LOADING_LYRICS)
        #expect(LyricsWords.noLyrics == words.NO_LYRICS)
        #expect(LyricsWords.nothingPlaying == words.NOTHING_PLAYING)
        #expect(LyricsWords.notSynced == words.NOT_SYNCED)
        #expect(LyricsWords.failed == words.LYRICS_FAILED)
        #expect(LyricsWords.songGone == words.SONG_GONE)
        #expect(LyricsWords.lineHint == words.LINE_HINT)
        #expect(LyricsWords.goToLit == words.GO_TO_LIT)
        // and as the spec has them (notes/app-lyrics.md 2.1), so a change on both sides is a choice, not a slip
        #expect(LyricsWords.none == "Lyrics - none for this song")
        #expect(LyricsWords.notKept == "Lyrics - not on this phone")
        #expect(LyricsWords.songGone == "This song isn't here any more - it may have been moved or deleted.")
        #expect(LyricsWords.goToLit == "Go to the line being sung")
    }

    @Test func theNumbersAreTheWebs() throws {
        let constants = try LyricsVectors.vectors().constants
        #expect(Lyrics.anchor == constants.LYRICS_ANCHOR)
        #expect(Lyrics.followAgainMs == constants.FOLLOW_AGAIN_MS)
        #expect(Lyrics.gapDotsSeconds == constants.GAP_DOTS_S)
        #expect(Lyrics.nextLyricsSeconds == constants.NEXT_LYRICS_S)
        #expect(Lyrics.kept == constants.LYRICS_KEPT)
        #expect(Scrub.landedWithin == constants.LANDED_WITHIN_S)
    }

    @Test func theButtonsNameAndDimming() throws {
        let vectors = try LyricsVectors.vectors()
        for one in vectors.have {
            #expect(Lyrics.have(one.lyrics) == (try have(one.have)), "\(one.name)")
        }
        #expect(Set(vectors.label.map(\.have)) == Set(LyricsHave.allCases.map(\.rawValue)))
        for one in vectors.label {
            #expect(LyricsWords.label(try have(one.have)) == one.label, "\(one.have)")
        }
        for one in vectors.dimmed {
            #expect(Lyrics.dimmed(try have(one.have), on: one.on) == one.dimmed, "\(one.have) on \(one.on)")
        }
    }

    @Test func theClock() throws {
        let vectors = try LyricsVectors.vectors()
        for one in vectors.clock {
            #expect(Lyrics.clock(raw: one.raw, reported: one.reported) == one.clock, "raw \(one.raw) reported \(one.reported)")
        }
        #expect(vectors.clockRuns.count == 16)
        for one in vectors.clockRuns {
            #expect(Lyrics.clockRuns(shows: one.shows, playing: one.playing, covered: one.covered, visible: one.visible) == one.runs)
        }
    }

    @Test func theLitLineTheIntroAndTheDots() throws {
        let sets = try LyricsVectors.vectors().sets
        #expect(sets.count == 10)
        var checked = 0
        for set in sets {
            #expect(Lyrics.withIntro(set.lines) == set.withIntro, "\(set.name)")
            #expect(set.lines.map { Lyrics.sung($0) } == set.sung, "\(set.name)")
            for at in set.at {
                #expect(Lyrics.litRange(set.lines, at: at.t) == at.litRange.map(LitRange.init), "\(set.name) at \(at.t)")
                #expect(Lyrics.litRange(set.withIntro, at: at.t) == at.drawnRange.map(LitRange.init), "\(set.name) drawn at \(at.t)")
                #expect(Lyrics.litAt(set.withIntro, at: at.t) == Lit(at.litAt), "\(set.name) litAt \(at.t)")
                let dots = set.withIntro.indices.map { Lyrics.gapDots(set.withIntro, $0, at: at.t) }
                #expect(dots == at.gapDots, "\(set.name) dots at \(at.t)")
                checked += 1
            }
            for outside in set.gapDotsOutside {
                #expect(Lyrics.gapDots(set.withIntro, outside.i, at: outside.t) == outside.dots, "\(set.name) dots of \(outside.i)")
            }
        }
        #expect(checked >= 350)
        // the nil cases the Swift adds: no line, and a nil line
        #expect(!Lyrics.sung(nil))
    }

    @Test func twoMomentsDrawTheSameWhenEqual() throws {
        for one in try LyricsVectors.vectors().sameLit {
            #expect((Lit(one.a) == Lit(one.b)) == one.same)
        }
    }

    @Test func following() throws {
        let vectors = try LyricsVectors.vectors()
        for one in vectors.followTop {
            #expect(Lyrics.followTop(one.lineTop, height: one.height) == one.top, "\(one.lineTop) in \(one.height)")
        }
        for one in vectors.endRoom {
            #expect(Lyrics.endRoom(one.height) == one.room, "\(one.height)")
        }
        for one in vectors.follows {
            let made = Lyrics.follows(now: one.now, heldAt: one.heldAt, playing: one.playing, focused: one.focused ?? false)
            #expect(made == one.follows, "now \(one.now) held \(String(describing: one.heldAt)) playing \(one.playing) focused \(String(describing: one.focused))")
        }
        for one in vectors.followsDefault {
            #expect(Lyrics.follows(now: one.now, heldAt: one.heldAt, playing: one.playing) == one.follows)
        }
    }

    @Test func aLinesTimeAsVoiceOverSaysIt() throws {
        for one in try LyricsVectors.vectors().lineValue {
            #expect(LyricsWords.lineValue(one.time, lit: one.lit) == one.value, "\(one.time) \(one.lit)")
        }
    }

    @Test func theNextSongsAsk() throws {
        for one in try LyricsVectors.vectors().asksAhead {
            #expect(Lyrics.asksAhead(position: one.position, duration: one.duration) == one.asks, "\(one.position) of \(one.duration)")
        }
    }

    @Test func theAnswersKept() throws {
        let kept = try LyricsVectors.vectors().kept
        for run in [kept.small, kept.standard] {
            var memory = LyricsKept<SongLyrics>(most: run.most ?? Lyrics.kept)
            for (n, step) in run.steps.enumerated() {
                if step.op == "keep" {
                    memory.keep(step.id, try #require(step.value))
                } else {
                    #expect(memory.take(step.id) == step.returned, "step \(n)")
                }
                #expect(memory.order == step.order, "step \(n)")
                if let values = step.values {
                    #expect(memory.order.compactMap { memory.peek($0) } == values, "step \(n)")
                }
            }
        }
        #expect(kept.standard.most == nil)
        #expect(LyricsKept<SongLyrics>().most == 50)
    }
}

/// The server's answers (song_lyrics(), every case the route has), as the phone decodes them.
@Suite struct LyricsAnswerTests {
    @Test func everyAnswerTheRouteSendsIsDecoded() throws {
        let data = try Fixtures.data("lyrics/answers.json")
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(raw["cases"] as? [[String: Any]])
        let decoded = try LyricsVectors.load(LyricsVectors.Answers.self, "answers").cases
        #expect(cases.count == decoded.count)
        var kinds: Set<String> = []
        for (index, one) in decoded.enumerated() {
            // each answer read on its own, as the client reads a body
            let body = try JSONSerialization.data(withJSONObject: try #require(cases[index]["answer"]))
            let lyrics = try JSONDecoder().decode(SongLyrics.self, from: body)
            #expect(lyrics == one.answer, "\(one.name)")
            kinds.insert(lyrics.lines.isEmpty ? "none" : lyrics.synced ? "synced" : "plain")
            if lyrics.synced {
                #expect(lyrics.lines.allSatisfy { $0.time != nil }, "\(one.name)")
            } else {
                #expect(lyrics.lines.allSatisfy { $0.time == nil }, "\(one.name)")
            }
        }
        #expect(kinds == ["synced", "plain", "none"])
        let snapshot = try #require(decoded.first)
        #expect(snapshot.answer == SongLyrics(synced: true, lines: [
            LyricLine(time: 18.7, text: "The first line we sing"), LyricLine(time: 22.701, text: "And then the second"),
        ]))
        // a joined line keeps its newline; text outside ASCII is read as it is
        #expect(decoded.contains { $0.answer.lines.contains { $0.text == "A joined line\nkeeps its break" } })
        #expect(decoded.contains { $0.answer.lines.contains { $0.text.unicodeScalars.contains { $0.value == 0x266A } } })
    }
}

/// The phone's own lyrics rules (notes/app-lyrics.md 2.7, 4.2-4.7) - no TypeScript holds these.
@Suite struct LyricsPhoneTests {
    private let some = SongLyrics(synced: true, lines: [LyricLine(time: 1, text: "One")])
    private let none = SongLyrics(synced: false, lines: [])

    @Test func offlineWithNothingKeptIsNotOnThisPhone() {
        #expect(Lyrics.have(nil, online: true) == .unknown)
        #expect(Lyrics.have(nil, online: false) == .notKept)
        #expect(Lyrics.have(some, online: false) == .some)
        #expect(Lyrics.have(none, online: false) == .empty)
        #expect(Lyrics.have(none, online: true) == .empty)
        #expect(LyricsWords.label(Lyrics.have(nil, online: false)) == "Lyrics - not on this phone")
        // dimmed off, the same words selected on (2.7's last row)
        #expect(Lyrics.dimmed(.notKept, on: false))
        #expect(!Lyrics.dimmed(.notKept, on: true))
    }

    @Test func lyricsTakeTheCoversPlaceUnlessTheSongHasNone() {
        for have in LyricsHave.allCases {
            #expect(!Lyrics.shows(have, on: false))
        }
        #expect(Lyrics.shows(.unknown, on: true))
        #expect(Lyrics.shows(.some, on: true))
        #expect(!Lyrics.shows(.empty, on: true))
        #expect(!Lyrics.shows(.notKept, on: true))
    }

    @Test func whatTheFaceShows() {
        let path = "/navidrome/lyrics/so-1"
        let gone = APIFailure.answered(.init(status: 404, method: "GET", path: path, detail: "Navidrome has nothing by that id"))
        let down = APIFailure.answered(.init(status: 502, method: "GET", path: path))
        let server = ServerAddress(base: URL(string: "http://deadwax.test:8080")!)
        let offline = APIFailure.offline(.init(server: server, method: "GET", path: path, reason: "The Internet connection appears to be offline."))
        let plain = SongLyrics(synced: false, lines: [LyricLine(time: nil, text: "One")])
        #expect(Lyrics.face(nil, asking: true, failure: nil) == .loading)
        #expect(Lyrics.face(nil, asking: false, failure: nil) == .loading)
        // the failure once the ask is over - and Try again only for what trying again could mend
        #expect(Lyrics.face(nil, asking: true, failure: down) == .loading)
        #expect(Lyrics.face(nil, asking: false, failure: down) == .failed(tryAgain: true))
        #expect(Lyrics.face(nil, asking: false, failure: gone) == .failed(tryAgain: false))
        #expect(Lyrics.face(nil, asking: false, failure: offline) == .failed(tryAgain: true))
        // an answer in hand is drawn over a failure: a revalidation that failed is no news
        #expect(Lyrics.face(some, asking: false, failure: down) == .synced)
        #expect(Lyrics.face(plain, asking: true, failure: nil) == .plain)
        #expect(Lyrics.face(none, asking: false, failure: nil) == .cover)
        // and a gone song is said in the song's words, never the server's
        let said = ErrorWords.of(gone, gone: LyricsWords.songGone, failed: LyricsWords.failed, retry: true).said
        #expect(said == LyricsWords.songGone)
        #expect(ErrorWords.of(down, failed: LyricsWords.failed, retry: true).text == LyricsWords.failed)
        #expect(ErrorWords.of(offline, failed: LyricsWords.failed, retry: true).kind == .offline)
    }

    /// WCAG's contrast ratio of two sRGB greys (0...1).
    private func contrast(_ a: Double, _ b: Double) -> Double {
        func luminance(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func theDimLinesReadOverTheBrightestCover() {
        // a white sleeve, blurred, under the backdrop's black - and a white line at the dim opacity over that
        func over(_ dim: Double, increased: Bool) -> Double {
            let backdrop = 1 - Lyrics.backdropDim(lyrics: true, increased: increased)
            let line = dim + (1 - dim) * backdrop
            return contrast(line, backdrop)
        }
        #expect(Lyrics.backdropDim(lyrics: false, increased: false) == 0.55)
        #expect(Lyrics.backdropDim(lyrics: false, increased: true) == 0.55)
        #expect(Lyrics.backdropDim(lyrics: true, increased: false) == 0.7)
        #expect(Lyrics.backdropDim(lyrics: true, increased: true) == 0.75)
        // 3:1 is large text's floor (WCAG AA); the spec's 3.5:1, and 5.5:1 with Increase Contrast
        let dim = over(Lyrics.lineDim(increased: false), increased: false)
        let increased = over(Lyrics.lineDim(increased: true), increased: true)
        let lit = over(1, increased: false)
        #expect(dim >= 3.4 && dim < 3.6, "\(dim)")
        #expect(increased >= 5.4 && increased < 5.6, "\(increased)")
        #expect(lit >= 8.4, "\(lit)")
        // the draft's 0.4 over Phase 1's backdrop was 2.1:1 - why the backdrop darkens
        let draft = contrast(0.4 + 0.6 * 0.45, 0.45)
        #expect(draft < 3)
    }

    @Test func aFingerScrollingHoldsAndItsEndStartsTheWait() {
        var hold = LyricsHold()
        #expect(hold.follows(now: 0, playing: true))
        #expect(hold.wait(now: 0) == nil)
        // a tap on a line: tracking, then idle - holds nothing
        hold.phase(.tracking, at: 100)
        hold.phase(.idle, at: 150)
        #expect(hold == LyricsHold())
        // following's own scroll holds nothing
        hold.phase(.animating, at: 200)
        hold.phase(.idle, at: 700)
        #expect(hold == LyricsHold())
        // a finger moving them holds, however long it stays
        hold.phase(.interacting, at: 1000)
        #expect(!hold.follows(now: 1000, playing: true))
        #expect(!hold.follows(now: 60_000, playing: true))
        #expect(hold.wait(now: 2000) == nil)
        // its fling still holds, and the wait is counted from when it all stops
        hold.phase(.decelerating, at: 1500)
        #expect(hold.scrolling)
        hold.phase(.idle, at: 2500)
        #expect(!hold.scrolling)
        #expect(hold.heldAt == 2500)
        #expect(hold.wait(now: 2500) == 4000)
        #expect(hold.wait(now: 6000) == 500)
        #expect(hold.wait(now: 9000) == 0)
        #expect(!hold.follows(now: 6499, playing: true))
        #expect(hold.follows(now: 6500, playing: true))
        // paused, it stays put however long
        #expect(!hold.follows(now: 600_000, playing: false))
        // a finger put down on a fling keeps holding until it lifts
        hold.phase(.interacting, at: 7000)
        hold.phase(.decelerating, at: 7100)
        hold.phase(.tracking, at: 7200)
        #expect(hold.scrolling)
        hold.phase(.idle, at: 7300)
        #expect(hold.heldAt == 7300)
        hold.follow()
        #expect(hold.follows(now: 7301, playing: false))
    }

    @Test func voiceOversFocusHoldsWhileOnALineAndForTheWaitAfter() {
        var hold = LyricsHold()
        hold.focus(onLine: false, at: 10)
        #expect(hold == LyricsHold())
        hold.focus(onLine: true, at: 100)
        #expect(hold.focused)
        #expect(!hold.follows(now: 100_000, playing: true))
        #expect(hold.wait(now: 100) == nil)
        // a following tap or the song changing doesn't take VoiceOver's focus away: still held
        hold.follow()
        #expect(!hold.follows(now: 100_000, playing: true))
        hold.focus(onLine: false, at: 5000)
        #expect(hold.heldAt == 5000)
        #expect(!hold.follows(now: 8999, playing: true))
        #expect(hold.follows(now: 9000, playing: true))
    }
}
