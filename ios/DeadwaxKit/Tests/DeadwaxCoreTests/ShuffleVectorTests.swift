import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/shuffle/shuffle-vectors.json: what the web's TypeScript answers - app/useShuffleFeed.ts driven as the hook
/// it is, app/usePaged.ts's appendPage, Songs' words - written by ios/scripts/export-shuffle-vectors.cjs, never by hand,
/// and the shapes it is read into.
enum ShuffleVectors {
    struct Vectors: Decodable {
        let words: Words
        let elsewhere: [Elsewhere]
        let ahead: [Ahead]
        let runs: [Run]
        let append: [Append]
    }

    struct Words: Decodable {
        struct Titles: Decodable { let songs, allSongs: String }
        struct Line: Decodable {
            struct Of: Decodable { let artist: String?; let album: String? }
            let song: Of
            let line: String
        }
        struct Count: Decodable { let count: Int?; let text: String }

        let FEED_BELOW, FEED_RETRY_MS, SONGS_PAGE: Int
        let SHUFFLE_STARTED_OVER, librarySongs, NO_SONGS, hidden: String
        let titles: Titles
        let browse: [String]
        let lines: [Line]
        let counts: [Count]
    }

    struct Elsewhere: Decodable {
        let ids: [String]
        let ending: String?
        let seed: Int64
        let drew: Int
        let out: [String]
    }

    struct Ahead: Decodable {
        let how: String
        let index: Int
        let count: Int
        let froms: String?
        let ahead: Int
    }

    struct Then: Decodable {
        struct Queue: Decodable { let index: Int; let count: Int; let paged: JSONValue }
        let asks: [JSONValue]
        let extended: [JSONValue]
        let said: [String]
        let draws: [Int64]
        let retries: Int
        let queue: Queue
    }

    struct Step: Decodable {
        let op: String
        let to: Int?
        let mode: String?
        let ids: [String]?
        let ask: Int?
        let token: String?
        let total: Int?
        let first: [String]?
        let songs: [String]?
        let then: Then
    }

    struct Run: Decodable {
        let name: String
        let scope: String
        let level: String?
        let `repeat`: String
        let index: Int
        let token: String
        let total: Int
        let first: [String]
        let steps: [Step]
    }

    struct Append: Decodable { let shown, page, out: [String] }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("shuffle/shuffle-vectors.json"))
    }
}

/// What the hook drew from Math.random in one step, handed out in turn as the Swift draws - and how many it took.
private final class Draws {
    private let ints: [Int64]
    private(set) var taken = 0
    init(_ ints: [Int64]) { self.ints = ints }
    func next() -> Double {
        defer { taken += 1 }
        guard taken < ints.count else { return 0.5 }
        return Double(ints[taken] - 1) / 2_147_483_646
    }
}

/// The phone's feed and Songs against the web's own answers (export-shuffle-vectors.cjs).
@Suite struct ShuffleVectorTests {
    /// The exporter's song: `Song id`, of album A - only its id and level are compared.
    private static func song(_ id: String) -> Song { Song(id: id, title: "Song \(id)", album: "A", albumId: "al") }
    private static func ids(_ tracks: [QueueTrack]) -> [String] { tracks.map { (track: QueueTrack) -> String in track.id } }
    private static func never() -> Double {
        Issue.record("nothing here should draw a random number")
        return 0
    }

    @Test func theWordsAndNumbersAreTheWebs() throws {
        let words = try ShuffleVectors.load().words
        #expect(ShuffleFeed.below == words.FEED_BELOW)
        #expect(ShuffleFeed.retrySeconds * 1000 == words.FEED_RETRY_MS)
        #expect(ShuffleWords.startedOver == words.SHUFFLE_STARTED_OVER)
        #expect(SongsPaging.pageSize == words.SONGS_PAGE)
        // librarySongs' query, as written: every song (q ''), no artists or albums - what the client's search asks with
        // (ClientTests' songsAskForEverySong holds its names, in this order)
        #expect(words.librarySongs == "q: '', artistCount: '0', albumCount: '0', songCount: String(count), songOffset: String(offset)")
        #expect(SongWords.noSongs == words.NO_SONGS)
        #expect(SongWords.songs == words.titles.songs && LibraryPage.songs.title == words.titles.songs)
        #expect(SongWords.title(personal: false) == words.titles.songs)
        #expect(SongWords.title(personal: true) == words.titles.allSongs && SongWords.allSongs == words.titles.allSongs)
        #expect(words.browse.last == SongWords.allSongs, "All music's last list")
        #expect(LibraryMenu.allMusic.map { (item: LibraryMenuItem) -> String in item.words(personal: true) } == words.browse)
        #expect(", " + SongWords.opensItsAlbum == words.hidden)
        for each in words.lines {
            let song = Song(id: "x", title: "Roads", album: each.song.album, artist: each.song.artist)
            #expect(PlaylistRules.songLine(song) == each.line, "\(String(describing: each.song.artist)) \(String(describing: each.song.album))")
        }
        for each in words.counts {
            #expect(SongWords.count(each.count) == each.text, "\(String(describing: each.count))")
        }
    }

    @Test func startingElsewhereIsTheWebs() throws {
        let cases = try ShuffleVectors.load().elsewhere
        #expect(cases.count > 400)
        for each in cases {
            let random = Seeded(each.seed)
            var drew = 0
            let tracks = each.ids.map { (id: String) -> QueueTrack in shuffledTrack(Song(id: id)) }
            let out = ShuffleFeed.startingElsewhere(tracks, ending: each.ending, random: { () -> Double in
                drew += 1
                return random.next()
            })
            #expect(Self.ids(out) == each.out, "\(each.ids) ending \(String(describing: each.ending))")
            #expect(drew == each.drew, "\(each.ids) ending \(String(describing: each.ending)): draws")
        }
    }

    @Test func songsAheadIsTheWebs() throws {
        let cases = try ShuffleVectors.load().ahead
        #expect(cases.count > 200)
        for each in cases {
            let tracks = (0..<each.count).map { (at: Int) -> QueueTrack in simTrack("t\(at)") }
            var queue = UpNextQueue(tracks: tracks, index: each.index)
            if let froms = each.froms {
                let marks = froms.enumerated().map { (pair: (offset: Int, element: Character)) -> Mark in
                    let from: MarkFrom = pair.element == "s" ? .source : pair.element == "a" ? .added : .one
                    return Mark(key: pair.offset, from: from, at: pair.offset, pass: 0)
                }
                queue.upNext = UpNextState(id: "q", marks: marks, source: tracks, shuffle: true, nextKey: marks.count, startedAt: 0)
            }
            #expect(ShuffleFeed.songsAhead(queue) == each.ahead, "\(each.how)")
        }
    }

    @Test func appendedIsTheWebsAppendPage() throws {
        let cases = try ShuffleVectors.load().append
        for each in cases {
            let shown = each.shown.map { (id: String) -> Song in Song(id: id) }
            let page = each.page.map { (id: String) -> Song in Song(id: id) }
            let out = SongsPaging.appended(shown, page).map { (song: Song) -> String in song.id }
            #expect(out == each.out, "\(each.shown) + \(each.page)")
        }
    }

    /// Every run of the hook, replayed through ShuffleFeedRun as the app drives it (PlayerModel's feed, held by
    /// ShuffleFeedLoopTests): the step carried out on the queue as the exporter did, each answer handed to the run, the
    /// queue looked at again after every step - and the asks made, what was handed to extendQueue, what was said, the
    /// draws taken, the retries waiting and the queue after, each the web's.
    @Test func theFeedRunsAsTheWebsHookRuns() throws {
        let runs = try ShuffleVectors.load().runs
        #expect(runs.count > 50)
        var answered = 0, extendedNext = 0, said = 0, retried = 0
        for run in runs {
            let level = run.level.flatMap(Level.init(rawValue:))
            let scope = try #require(PagedScope(rawValue: run.scope))
            var mode = try #require(Repeat(rawValue: run.repeat))
            let tracks = { (ids: [String]) -> [QueueTrack] in
                ids.map { (id: String) -> QueueTrack in ShuffleFeed.track(Self.song(id), level: level) }
            }
            var queue = startUpNext(tracks(run.first), start: run.index, shuffle: false, random: Self.never,
                                    paged: Paged(token: run.token, total: run.total, fetched: run.first.count, scope: scope,
                                                 level: level),
                                    id: "q")
            var feed = ShuffleFeedRun()
            var asks: [FeedAsk] = []
            var retries = 0
            for (number, step) in run.steps.enumerated() {
                let at = "\(run.name), step \(number) (\(step.op))"
                let draws = Draws(step.then.draws)
                var made: [FeedAsk] = []
                var extended: [JSONValue] = []
                var notices: [String] = []
                let carry = { (outcome: FeedStep) -> Void in
                    switch outcome {
                    case .extend(let token, let more, let next, let notice):
                        let ids = more.map { (track: QueueTrack) -> JSONValue in .string(track.id) }
                        let levels = more.map { (track: QueueTrack) -> JSONValue in
                            guard let level = track.level else { return JSONValue.null }
                            return JSONValue.string(level.rawValue)
                        }
                        extended.append(.array([.string(token), .array(ids), .array(levels), Self.json(next)]))
                        queue = withMore(queue, token: token, tracks: more, next: next)
                        if let notice { notices.append(notice) }
                    case .ask(let ask): made.append(ask)
                    case .retry: retries += 1
                    case .nothing: break
                    }
                }
                switch step.op {
                case "begin": break
                case "next": queue = queue.at(try #require(step.to))
                case "repeat":
                    mode = try #require(step.mode.flatMap(Repeat.init(rawValue:)))
                    queue = toppedUp(withRepeat(queue, mode), mode, random: Self.never)
                case "playNext":
                    queue = withNext(queue, try #require(step.ids).map { (id: String) -> QueueTrack in shuffledTrack(Self.song(id)) })
                case "shuffle":
                    let first = try #require(step.first)
                    queue = startUpNext(tracks(first), start: 0, shuffle: false, random: Self.never,
                                        paged: Paged(token: try #require(step.token), total: try #require(step.total),
                                                     fetched: first.count, scope: scope, level: level),
                                        id: "q")
                case "clear": queue = startUpNext([], start: 0, id: "q")
                case "answer":
                    let ask = asks[try #require(step.ask)]
                    let songs = try #require(step.songs).map { (id: String) -> Song in Self.song(id) }
                    answered += 1
                    switch ask.kind {
                    case .page: carry(feed.page(ask, songs: songs))
                    case .fresh:
                        let first = ShuffleStart(token: try #require(step.token), total: try #require(step.total), songs: songs)
                        carry(feed.fresh(ask, first, repeat: mode, random: draws.next))
                    }
                case "fail": carry(feed.failed(asks[try #require(step.ask)]))
                case "gone": carry(feed.gone(asks[try #require(step.ask)]))
                case "retry":
                    retries -= 1
                    retried += 1
                    feed.retried()
                default: Issue.record("\(at): no such step")
                }
                //? the app looks again whenever the queue or Repeat changes, and after an answer or a retry
                if let ask = feed.look(queue, repeat: mode) { made.append(ask) }
                asks += made

                #expect(made.map { (ask: FeedAsk) -> JSONValue in Self.json(ask) } == step.then.asks, "\(at): asks")
                #expect(extended == step.then.extended, "\(at): extended")
                #expect(notices == step.then.said, "\(at): said")
                #expect(draws.taken == step.then.draws.count, "\(at): draws")
                #expect(retries == step.then.retries, "\(at): retries waiting")
                #expect(queue.index == step.then.queue.index && queue.tracks.count == step.then.queue.count, "\(at): the queue")
                #expect(Self.json(queue.upNext?.paged) == step.then.queue.paged, "\(at): the queue's paged")
                extendedNext += extended.filter { (each: JSONValue) -> Bool in each.array?.last != .null }.count
                said += notices.count
            }
        }
        // the runs reach every way the feed can go
        #expect(answered > 100 && extendedNext > 20 && said >= 2 && retried > 10, "\(answered) \(extendedNext) \(said) \(retried)")
    }

    /// An ask as the web's fake recorded it: ["page", token, offset] or ["start", scope, {claim: true}].
    private static func json(_ ask: FeedAsk) -> JSONValue {
        switch ask.kind {
        case .page(let offset): return .array([.string("page"), .string(ask.token), .number(Double(offset))])
        case .fresh: return .array([.string("start"), .string(ask.scope.rawValue), .object(["claim": .bool(true)])])
        }
    }

    /// A Paged as the exporter wrote it (pagedOf), or null.
    private static func json(_ paged: Paged?) -> JSONValue {
        guard let paged else { return .null }
        var fields: [String: JSONValue] = [
            "token": .string(paged.token), "total": .number(Double(paged.total)),
            "fetched": .number(Double(paged.fetched)), "scope": .string(paged.scope.rawValue),
        ]
        if let level = paged.level { fields["level"] = .string(level.rawValue) }
        return .object(fields)
    }
}
