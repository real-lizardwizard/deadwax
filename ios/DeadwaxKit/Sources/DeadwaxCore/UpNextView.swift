import Foundation

// What Up Next draws, and its words: upNext.ts's upNextView and words, and the Up Next sheet's own words
// (ui/src/app/UpNext.tsx) - read-outs, row names, "And N more songs." - so the sheet is drawn from Core.

/// One row of Up Next: the entry's key (so a song in twice is two rows), and its song.
public struct UpNextRow: Sendable, Equatable {
    public let key: Int
    public let track: QueueTrack

    public init(key: Int, track: QueueTrack) {
        self.key = key
        self.track = track
    }
}

/// The list's songs still to play this time round: the first `limit`, and how many more.
public struct UpNextList: Sendable, Equatable {
    public let title: String
    public let rows: [UpNextRow]
    public let more: Int

    public init(title: String, rows: [UpNextRow], more: Int) {
        self.title = title
        self.rows = rows
        self.more = more
    }
}

public struct UpNextView: Sendable, Equatable {
    public let playing: QueueTrack?
    /// Playing Next: the songs added, after the copies - all of them
    public let added: [UpNextRow]
    public let list: UpNextList?
    /// what comes after: "Then … again from the top." or "Nothing after this song."
    public let then: String?
    public let repeatOne: Bool

    public init(playing: QueueTrack?, added: [UpNextRow], list: UpNextList?, then: String?, repeatOne: Bool) {
        self.playing = playing
        self.added = added
        self.list = list
        self.then = then
        self.repeatOne = repeatOne
    }
}

/// What Up Next draws: neither Repeat One's copies nor the later times round.
public func upNextView(_ queue: UpNextQueue, _ mode: Repeat, limit: Int = UpNext.drawn) -> UpNextView {
    let playing = queue.current
    guard let playing, let state = queue.upNext else {
        return UpNextView(playing: playing, added: [], list: nil, then: nil, repeatOne: false)
    }
    let (copiesEnd, addedEnd) = layout(queue, state)
    let row = { (place: Int) in UpNextRow(key: state.marks[place].key, track: queue.tracks[place]) }
    let addedRows = (copiesEnd..<addedEnd).map(row)
    let shown = shownPass(queue)
    var listed: [Int] = []
    var place = addedEnd
    while place < state.marks.count, state.marks[place].from == .source, state.marks[place].pass == shown {
        listed.append(place)
        place += 1
    }
    let paged = state.paged
    let pending = paged.map { max(0, $0.total - $0.fetched) } ?? 0
    let again = shown > passPlaying(state.marks, queue.index)
    let title: String
    if let paged {
        title = "\(paged.scope == .yours ? "Your library" : "All music"), shuffled\(again ? ", again" : "")"
    } else {
        title = listTitle(state.source, again: again)
    }
    let list = listed.isEmpty && pending == 0
        ? nil
        : UpNextList(title: title, rows: listed.prefix(max(limit, 0)).map(row),
                     more: max(0, listed.count - limit) + pending)
    //? (2.0.5) the collection's shuffle is "all music" here too, as its heading says - never "everything"
    let name = paged.map { $0.scope == .yours ? "your library" : "all music" } ?? oneAlbum(state.source) ?? "the list"
    let then: String?
    switch mode {
    case .all: then = state.shuffle ? "Then \(name) again, in a new order." : "Then \(name) again from the top."
    case .off: then = queue.index >= queue.tracks.count - 1 ? "Nothing after this song." : nil
    case .one: then = nil
    }
    return UpNextView(playing: playing, added: addedRows, list: list, then: then, repeatOne: mode == .one)
}

/// The list's heading in Up Next: "From Mezzanine" for one album's songs, else "Still to play" - with `again` (a
/// later time round than the song playing's), "From Mezzanine, again".
public func listTitle(_ source: [QueueTrack], again: Bool) -> String {
    let title = oneAlbum(source).map { "From \($0)" } ?? "Still to play"
    return again ? "\(title), again" : title
}

/// Which of the song menu's two the notice is for - also the queue menu's choice (QueuePick.swift's `QueueChoice`
/// is this type, under the screens' name).
public enum QueuedHow: String, Sendable, CaseIterable {
    case next, last

    /// The queue menu's row (QueueMenu.tsx).
    public var label: String {
        switch self {
        case .next: return "Play Next"
        case .last: return "Play Last"
        }
    }
}

/// The app's notice for what Play Next or Play Last did.
public func queuedWords(_ how: QueuedHow, label: String) -> String {
    how == .next ? "Playing next: \(label)" : "Added to Up Next: \(label)"
}

/// What the Repeat chip and Now Playing's Repeat button say.
public func repeatLabel(_ mode: Repeat) -> String {
    switch mode {
    case .all: return "Repeat all"
    case .one: return "Repeat one"
    case .off: return "Repeat"
    }
}

/// The Shuffle button's name: "Shuffle", or during a whole library's shuffle (`scope`, the queue's paged scope) -
/// whose order IS the shuffle, so it can't be turned off - named for why.
public func shuffleLabel(_ scope: PagedScope?) -> String {
    guard let scope else { return "Shuffle" }
    return "Shuffle - shuffling \(scope == .store ? "all music" : "your whole library")"
}

/// The Repeat button's next setting: off -> all -> one -> off.
public func nextRepeat(_ mode: Repeat) -> Repeat {
    let cycle = Repeat.allCases
    let at = cycle.firstIndex(of: mode) ?? 0
    return cycle[(at + 1) % cycle.count]
}

/// Now Playing's Up Next button, named with what is on: "Up Next - Shuffle and Repeat all".
public func upNextLabel(shuffle: Bool, repeat mode: Repeat) -> String {
    if shuffle && mode != .off { return "Up Next - Shuffle and \(repeatLabel(mode))" }
    if shuffle { return "Up Next - Shuffle on" }
    if mode != .off { return "Up Next - \(repeatLabel(mode))" }
    return "Up Next"
}

/// The Up Next sheet's own words (ui/src/app/UpNext.tsx), each as the web says it.
public enum UpNextWords {
    public static let title = "Up Next"
    public static let playingNext = "Playing Next"
    public static let clear = "Clear"
    public static let modesGroup = "Shuffle and repeat"
    /// REPEATING_ONE, under the song playing with Repeat One on
    public static let repeatingOne = "Repeat one: this song plays again until you skip it."
    /// SHUFFLING_LIBRARY, under the chips during a library's shuffle (either scope, as the web has it)
    public static let shufflingLibrary = "Shuffling your whole library"

    /// "And 3,997 more songs." / "And 1 more song." - the count grouped as en-US writes it.
    public static func more(_ count: Int) -> String {
        "And \(grouped(count)) more \(count == 1 ? "song" : "songs")."
    }

    /// A row's second line, and the song playing's: the artist and the album, the empty ones left out.
    public static func songLine(artist: String, album: String) -> String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A row's name: its tap plays it now.
    public static func playNow(_ title: String) -> String { "\(title), play now" }
    public static func moveUp(_ title: String) -> String { "Move \(title) up" }
    public static func moveDown(_ title: String) -> String { "Move \(title) down" }
    public static func remove(_ title: String) -> String { "Remove \(title)" }

    /// What VoiceOver is told after each change.
    public static func shuffleSaid(_ on: Bool) -> String { on ? "Shuffle on" : "Shuffle off" }
    public static func repeatSaid(_ mode: Repeat) -> String { mode == .off ? "Repeat off" : repeatLabel(mode) }
    public static let clearedSaid = "Playing Next cleared"
    /// A row moved: its new place (0-based `to`) of the rows drawn in its group.
    public static func movedSaid(_ title: String, to: Int, of count: Int) -> String { "\(title): \(to + 1) of \(count)" }
    public static func removedSaid(_ title: String) -> String { "\(title) removed" }

    /// SwiftUI's `.onMove(IndexSet{from}, destination)` as a place in the group: `destination` counts the row's own
    /// place before it is taken out, so a move down lands one before it.
    public static func movedTo(from: Int, destination: Int) -> Int { destination > from ? destination - 1 : destination }

    /// en-US grouping by thousands (toLocaleString('en-US')), with no Foundation formatter: the same on Linux.
    static func grouped(_ count: Int) -> String {
        let digits = String(count.magnitude)
        var out = ""
        for (i, digit) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return count < 0 ? "-" + out : out
    }
}
