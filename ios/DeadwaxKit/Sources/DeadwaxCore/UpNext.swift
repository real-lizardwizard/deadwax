import Foundation

// Up Next, shuffle and repeat: what plays after the song playing, and how Play Next, Play Last, a move, a removal,
// Shuffle and Repeat change it - ui/src/lib/upNext.ts, function by function, with playQueue.ts's nextIndex and
// previousAction. The engine plays `tracks` one to one from `index`; Up Next's account rides beside them as
// `upNext`, one Mark per entry.
//
// REPEAT IS THE QUEUE, UNROLLED: Repeat All puts the next time round of the list into the queue ahead of where the
// engine looks (toppedUp, once a song has been heard), and Repeat One puts copies of the song after it. The engine
// plays them as any next song, joined sample to sample. Up Next shows neither the copies nor the later times round.
//
// THE INVARIANT, held by every function here: after `index` the entries run Repeat One's copies, then the songs
// added, then the list's songs time round by time round (`pass` never going down) - and every edit keeps
// `tracks[0...index]`, `marks[0...index]` and `index` exactly. An edit that changes nothing hands back the very
// queue it was given, so `==` (an array's identical storage compares at once) tells the player there is nothing to
// do. (jumpedTo's list edit puts the list's songs down to the row ahead of Playing Next, for the moment until the
// player moves to its index.) Previous can leave the order after the song playing as it played (a list's rounds
// never going down, songs added among them); Up Next draws it as it will play. A queue with no `upNext` -
// `UpNextQueue.empty`, or a plain queue - is handed back as it is by every edit, and onward, backward and
// pastCopies answer as nextIndex and previousAction would.
//
// HISTORY (2.1.3) is the queue's entries before the song playing - exactly what Previous walks back through, so the
// two never disagree: from where listening began (`startedAt`; Previous back before it moves it down, wentBack) and
// at most UpNext.historyBack entries back (what a reload keeps, so History after one is the same). A UNIT - an entry
// and the Repeat One copies straight after it - is one row there as in Up Next, keyed by its first entry, and every
// row either draws is reached by its tap (jumpedTo): Up Next's moves the place onto it, History's plays its song
// again. A unit is ONE song: whatever takes a song out of the queue takes its copies with it (withShuffle,
// withRepeat), or they'd join the row before them. UpNextPropertyTests holds all of it, by upnext.sim's property.
//
// RANDOMNESS comes in only through startUpNext, toppedUp and withShuffle, each as `random` (a number in [0, 1)),
// drawn in exactly the TypeScript's order, so the same numbers make the same queue: ios/scripts/export-traces.cjs
// records what the TypeScript drew and did, and UpNextTraceTests replays it.
//
// THE QUEUE'S ID (app 0.8, the web's 2.1.15): made as a queue starts - startUpNext's `id`, else `newQueueId()`, the
// time and eight random characters, never a draw of `random`, so a shuffle's order is the same as before ids were -
// and carried by every edit (UpNextState is a value: an edit copies it). What a start of a song names its queue by
// (PlayHistory.swift).
//
// Pure: no I/O; built and tested on Linux. The clock and the system's random numbers are read only by the two
// defaults below - systemRandom() and newQueueId() - which a caller (and every test) can pass in place of.

extension UpNext {
    /// The system's random number in [0, 1), Math.random's stand-in.
    public static func systemRandom() -> Double { Double.random(in: 0..<1) }

    /// queueId()'s letters: a byte's place among them is the byte modulo 36.
    static let idDigits = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// (2.1.15) A queue's id as the web's queueId() makes one: the time in milliseconds in base 36 (0 for a time
    /// before 1970), a hyphen, and a letter for each of eight bytes (`bytes[i] % 36` of "0-9a-z"). Pure - the
    /// time and the bytes given (newQueueId reads them).
    public static func queueId(nowMs: Int64, bytes: [UInt8]) -> String {
        let letters = bytes.map { String(idDigits[Int($0) % idDigits.count]) }.joined()
        return "\(String(max(0, nowMs), radix: 36))-\(letters)"
    }

    /// A new queue's id: now, and eight bytes of the system's random numbers (the web's crypto.getRandomValues).
    public static func newQueueId() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<8).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return queueId(nowMs: Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)), bytes: bytes)
    }

    /// What a queue's id is (resume.ts QUEUE_ID, src/play_history.py's): 1 to 64 of [A-Za-z0-9_-]. A snapshot's id
    /// that isn't one is read as none.
    public static func isQueueId(_ text: String) -> Bool {
        let units = text.utf16
        guard !units.isEmpty, units.count <= 64 else { return false }
        return units.allSatisfy { unit in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D: return true
            default: return false
            }
        }
    }
}

/* ===== playQueue.ts ===== */

/// The song playing, or nil for none.
public func current(_ queue: UpNextQueue) -> QueueTrack? { queue.current }

/// The entry after this one, or nil at the end of the queue - where playing stops.
public func nextIndex(_ queue: UpNextQueue) -> Int? {
    let next = queue.index + 1
    return next < queue.tracks.count ? next : nil
}

/// What "previous" does `position` seconds into the song: past RESTART_AFTER_SECONDS the song again, else the
/// entry before - and the first song only ever restarts.
public func previousAction(_ queue: UpNextQueue, position: Double) -> PreviousAction {
    if position > UpNext.restartAfterSeconds || queue.index <= 0 { return .restart }
    return .go(queue.index - 1)
}

/* ===== helpers ===== */

/// `floor(random() * count)`, the TypeScript's draw. The `min` can't change a result for any number below
/// 1 - 2^-40 (neither Math.random nor Park-Miller reaches one); it keeps an index in range.
private func drawn(_ random: () -> Double, _ count: Int) -> Int {
    min(Int((random() * Double(count)).rounded(.down)), max(count - 1, 0))
}

/// Fisher-Yates over a copy, exactly as startQueue() shuffles: one call of `random` per place from the last down
/// to the second, in that order.
private func shuffled<T>(_ list: [T], _ random: () -> Double) -> [T] {
    var out = list
    var i = out.count - 1
    while i > 0 {
        out.swapAt(i, drawn(random, i + 1))
        i -= 1
    }
    return out
}

/// The queue with new entries after the song playing - tracks and marks in step - and what else of the state
/// changed; the index kept.
private func rebuilt(_ queue: UpNextQueue, _ state: UpNextState, _ tracks: [QueueTrack], _ marks: [Mark],
                     _ more: (inout UpNextState) -> Void = { _ in }) -> UpNextQueue {
    var next = state
    next.marks = marks
    more(&next)
    return UpNextQueue(tracks: tracks, index: queue.index, upNext: next)
}

/// The mark at `place`, or nil outside the marks (the TypeScript's `marks[place]?`).
func markAt(_ marks: [Mark], _ place: Int) -> Mark? {
    marks.indices.contains(place) ? marks[place] : nil
}

/// The end (exclusive) of the UNIT at `place`: the entry and the Repeat One copies straight after it - one row of
/// Up Next or History, what Next and Previous step over as one song.
func unitEnd(_ state: UpNextState, _ place: Int) -> Int {
    var end = place + 1
    while markAt(state.marks, end)?.from == .one { end += 1 }
    return end
}

/// Where the unit at `index` begins: back over the copies before it - backward()'s run.
func unitStart(_ state: UpNextState, _ index: Int) -> Int {
    var place = index
    while place > 0 && markAt(state.marks, place)?.from == .one { place -= 1 }
    return place
}

/// Where Repeat One's copies after the song playing end, where the songs added after them (Playing Next) end, and
/// where the list Up Next draws after those ends - the shown round's songs, and any song added among them (Previous
/// walked back across it: it plays where it played).
func layout(_ queue: UpNextQueue, _ state: UpNextState) -> (copiesEnd: Int, addedEnd: Int, listEnd: Int) {
    var copiesEnd = queue.index + 1
    while markAt(state.marks, copiesEnd)?.from == .one { copiesEnd += 1 }
    var addedEnd = copiesEnd
    while markAt(state.marks, addedEnd)?.from == .added { addedEnd = unitEnd(state, addedEnd) }
    let shown = shownPass(queue)
    var listEnd = addedEnd
    while listEnd < state.marks.count {
        let mark = state.marks[listEnd]
        if mark.from == .source ? mark.pass != shown : mark.from != .added { break }
        listEnd = unitEnd(state, listEnd)
    }
    return (copiesEnd, addedEnd, listEnd)
}

/// The unit starts in [start, end).
func unitsIn(_ state: UpNextState, _ start: Int, _ end: Int) -> [Int] {
    var units: [Int] = []
    var place = start
    while place < end {
        units.append(place)
        place = unitEnd(state, place)
    }
    return units
}

/// The place of the last of the list's songs at or before `index`; -1 for none.
func lastSourceAt(_ marks: [Mark], _ index: Int) -> Int {
    var i = min(index, marks.count - 1)
    while i >= 0 {
        if marks[i].from == .source { return i }
        i -= 1
    }
    return -1
}

/// The time round the song playing is in: the last of the list's songs at or before it (a song added, or a copy,
/// is in the round of the list's song before it); -1 for none.
func passPlaying(_ marks: [Mark], _ index: Int) -> Int {
    let at = lastSourceAt(marks, index)
    return at < 0 ? -1 : marks[at].pass
}

/// The one album every song of the list is from, by name - or nil for a list of several. An album id the
/// TypeScript reads as false (none, or "") makes it nil too.
func oneAlbum(_ source: [QueueTrack]) -> String? {
    guard let first = source.first, let albumId = first.albumId, !albumId.isEmpty else { return nil }
    return source.allSatisfy { $0.albumId == albumId } ? first.album : nil
}

/// The marks and tracks kept where `keep(mark, place)` says so, in step.
private func kept(_ queue: UpNextQueue, _ state: UpNextState, _ keep: (Mark, Int) -> Bool) -> ([QueueTrack], [Mark]) {
    var tracks: [QueueTrack] = []
    var marks: [Mark] = []
    tracks.reserveCapacity(queue.tracks.count)
    marks.reserveCapacity(state.marks.count)
    for (place, mark) in state.marks.enumerated() where keep(mark, place) {
        marks.append(mark)
        if place < queue.tracks.count { tracks.append(queue.tracks[place]) }
    }
    return (tracks, marks)
}

/* ===== upNext.ts ===== */

/// The queue playTracks plays: startQueue()'s tracks and index for the same `random` - the shuffle done over the
/// list's places, with the same Fisher-Yates and the same calls, so every entry knows its place in the list. Every
/// entry the list's, in its first time round; `startedAt` the index it starts at (0 when shuffled). `paged` (Part
/// B): the first page of a whole library's shuffle - its order is the shuffle, so Shuffle reads on. `id` (2.1.15):
/// the new queue's own - `UpNext.newQueueId()` when none is given, made after the shuffle.
public func startUpNext(_ tracks: [QueueTrack], start: Int?, shuffle: Bool = false,
                        random: () -> Double = UpNext.systemRandom, paged: Paged? = nil,
                        id: String? = nil) -> UpNextQueue {
    if tracks.isEmpty { return .empty }
    let index = min(max(start ?? 0, 0), tracks.count - 1)
    let places = Array(tracks.indices)
    let order: [Int]
    if !shuffle {
        order = places
    } else if start == nil {
        order = shuffled(places, random)
    } else {
        order = [index] + shuffled(places.filter { $0 != index }, random)
    }
    let state = UpNextState(
        id: id ?? UpNext.newQueueId(),
        marks: order.enumerated().map { Mark(key: $0.offset, from: .source, at: $0.element, pass: 0) },
        source: tracks, shuffle: shuffle || paged != nil, nextKey: order.count, startedAt: shuffle ? 0 : index,
        left: [], paged: paged)
    return UpNextQueue(tracks: order.map { tracks[$0] }, index: shuffle ? 0 : index, upNext: state)
}

/// Repeat's songs, queued ahead of where anything looks. `.all`: while fewer than REPEAT_AHEAD entries follow the
/// song playing, one more time round of the list - in its own order, or freshly shuffled with Shuffle on, never
/// starting with the song that ended the round before (with any other to start with). Songs added are never
/// copied. `.one`: the song playing's copies after it, made up to REPEAT_AHEAD at the end of the copies there are.
/// `.off`, or topped up already: the same queue. (Part B) A library's shuffle is topped up by its feed, not here.
public func toppedUp(_ queue: UpNextQueue, _ mode: Repeat, random: () -> Double = UpNext.systemRandom) -> UpNextQueue {
    guard let state = queue.upNext, mode != .off, let playing = queue.current,
          state.marks.indices.contains(queue.index) else { return queue }
    if mode == .one {
        //? the copies of THIS song straight after it (Previous back across a run of another song's leaves those)
        var end = queue.index + 1
        while markAt(state.marks, end)?.from == .one && end < queue.tracks.count && queue.tracks[end].id == playing.id {
            end += 1
        }
        let have = end - queue.index - 1
        if have >= UpNext.repeatAhead { return queue }
        let count = UpNext.repeatAhead - have
        let original = state.marks[queue.index]
        let copies = (0..<count).map { Mark(key: state.nextKey + $0, from: .one, at: original.at, pass: original.pass) }
        var tracks = queue.tracks
        tracks.insert(contentsOf: repeatElement(playing, count: count), at: min(end, tracks.count))
        var marks = state.marks
        marks.insert(contentsOf: copies, at: end)
        return rebuilt(queue, state, tracks, marks) { $0.nextKey = state.nextKey + count }
    }
    if state.paged != nil || state.source.isEmpty || queue.tracks.count - queue.index - 1 >= UpNext.repeatAhead {
        return queue
    }
    var tracks = queue.tracks
    var marks = state.marks
    var nextKey = state.nextKey
    while tracks.count - queue.index - 1 < UpNext.repeatAhead {
        let last = lastSourceAt(marks, marks.count - 1)
        let pass = (last < 0 ? -1 : marks[last].pass) + 1
        let order = Array(state.source.indices)
        var round = state.shuffle ? shuffled(order, random) : order
        //? a new order never starts with the song that ended the round before - with any other song to start with
        let ending: String? = last < 0 || last >= tracks.count ? nil : tracks[last].id
        if state.shuffle && round.count > 1, let ending, state.source[round[0]].id == ending {
            let later = round.indices.filter { $0 > 0 && state.source[round[$0]].id != ending }
            //? the draw is made even with nothing to pick (a list of one song twice): `later[floor(r * 0)]`
            let r = random()
            let pick = Int((r * Double(later.count)).rounded(.down))
            if pick < later.count { round.swapAt(0, later[pick]) }
        }
        for at in round {
            tracks.append(state.source[at])
            marks.append(Mark(key: nextKey, from: .source, at: at, pass: pass))
            nextKey += 1
        }
    }
    return rebuilt(queue, state, tracks, marks) { $0.nextKey = nextKey }
}

/// Repeat changed to `mode`: anything but One lets go of the copies after the song playing; anything but All lets
/// go of the later times round (the list's songs after the song playing of a round later than its own), each with
/// its own copies. The player then tops the queue up for the new mode (toppedUp).
public func withRepeat(_ queue: UpNextQueue, _ mode: Repeat) -> UpNextQueue {
    guard let state = queue.upNext else { return queue }
    let round = passPlaying(state.marks, queue.index)
    //? (2.1.3 review) a later round's song goes with its own copies (Previous walked back across it): left, they'd
    //? join the row before them - History naming one song where Previous plays another
    func goes(_ mark: Mark, _ place: Int) -> Bool {
        if place <= queue.index { return false }
        if mark.from == .one {
            if mode != .one { return true }
            let song = unitStart(state, place)
            return song > queue.index && goes(state.marks[song], song)
        }
        return mode != .all && mark.from == .source && mark.pass > round
    }
    if !state.marks.enumerated().contains(where: { goes($0.element, $0.offset) }) { return queue }
    let (tracks, marks) = kept(queue, state) { !goes($0, $1) }
    //? (Part B) a library's shuffle whose later rounds went: back to the order of the last round left, so its feed
    //? judges that round's order - not the next round's
    let last = lastSourceAt(marks, marks.count - 1)
    let pass = last < 0 ? -1 : marks[last].pass
    let back = state.paged == nil ? nil : state.pagedRounds?.first { $0.pass == pass }
    return rebuilt(queue, state, tracks, marks) { next in
        if let back {
            next.paged = back.paged
            next.pagedRounds = (state.pagedRounds ?? []).filter { $0.pass < pass }
        }
    }
}

/// Shuffle on or off for the queue playing; the song playing goes on, the songs added keep their order (and Repeat
/// One's copies of the song playing their place; a list's song's copies go with it). The later times round go - toppedUp grows them again in the new order. The round is
/// the song playing's (the list's song at or before it).
///
/// - ON: the list's songs not yet heard this round, in a new order: every place but the song playing's, the places
///   heard this round (from where the round began - `startedAt` for the first - up to the song playing) and the
///   places taken out of it (`left`). Entries already queued for those places keep their keys.
/// - OFF: the list's own order from the song playing's place in it - the places after the last of the list's songs
///   at or before it, less those taken out this round - as new entries.
///
/// (Part B) A library's shuffle is left as it is: its order IS the shuffle.
public func withShuffle(_ queue: UpNextQueue, _ on: Bool, random: () -> Double = UpNext.systemRandom) -> UpNextQueue {
    guard let state = queue.upNext, state.paged == nil, state.shuffle != on, queue.current != nil,
          state.marks.indices.contains(queue.index) else { return queue }
    let index = queue.index
    let round = passPlaying(state.marks, index)
    let left = Set(state.left.filter { $0.pass == round }.map(\.at))
    let places = Array(state.source.indices)
    var wanted: [Int]
    if on {
        var roundStart = round == 0
            ? state.startedAt
            : (state.marks.firstIndex { $0.from == .source && $0.pass == round } ?? -1)
        if roundStart < 0 { roundStart = index }
        var heard = Set<Int>()
        var place = roundStart
        while place <= index {
            let mark = state.marks[place]
            if mark.from == .source && mark.pass == round { heard.insert(mark.at) }
            place += 1
        }
        let playingAt = state.marks[index].at
        if playingAt >= 0 { heard.insert(playingAt) }
        wanted = shuffled(places.filter { !heard.contains($0) && !left.contains($0) }, random)
    } else {
        let last = lastSourceAt(state.marks, index)
        let lastAt = last < 0 ? -1 : state.marks[last].at
        wanted = places.filter { $0 > lastAt && !left.contains($0) }
    }
    //? shuffled ON, the entries already queued this round for those places keep their keys
    var queued: [Int: Mark] = [:]
    if on {
        for place in (index + 1)..<max(index + 1, state.marks.count) {
            let mark = state.marks[place]
            if mark.from == .source && mark.pass == round { queued[mark.at] = mark }
        }
    }
    var nextKey = state.nextKey
    let fresh: [Mark] = wanted.map { at in
        if let mark = queued[at] { return mark }
        defer { nextKey += 1 }
        return Mark(key: nextKey, from: .source, at: at, pass: max(round, 0))
    }
    //? the list's songs after the song playing go - each with its Repeat One copies (Previous walked back across
    //? it), which left would join the row before them (2.1.3 review); the song playing's own copies and the songs
    //? added, theirs with them, stay
    var (tracks, marks) = kept(queue, state) { mark, place in
        if place <= index { return true }
        let song = mark.from == .one ? unitStart(state, place) : place
        return song <= index || state.marks[song].from != .source
    }
    tracks += fresh.map { state.source[$0.at] }
    marks += fresh
    return rebuilt(queue, state, tracks, marks) { next in
        next.shuffle = on
        next.nextKey = nextKey
    }
}

/// New entries, the songs added, at `place`.
private func added(_ queue: UpNextQueue, _ state: UpNextState, _ tracks: [QueueTrack], at place: Int) -> UpNextQueue {
    let marks = tracks.indices.map { Mark(key: state.nextKey + $0, from: .added, at: -1, pass: -1) }
    var allTracks = queue.tracks
    allTracks.insert(contentsOf: tracks, at: min(place, allTracks.count))
    var allMarks = state.marks
    allMarks.insert(contentsOf: marks, at: place)
    return rebuilt(queue, state, allTracks, allMarks) { $0.nextKey = state.nextKey + tracks.count }
}

/// Play Next: `tracks`, in their order, straight after the song playing's copies - the head of Playing Next.
public func withNext(_ queue: UpNextQueue, _ tracks: [QueueTrack]) -> UpNextQueue {
    guard let state = queue.upNext, !tracks.isEmpty, queue.current != nil else { return queue }
    return added(queue, state, tracks, at: layout(queue, state).copiesEnd)
}

/// Play Last: after the songs already added (after the copies, with none) - the end of Playing Next, still ahead
/// of the rest of the list, as Apple Music has it.
public func withLast(_ queue: UpNextQueue, _ tracks: [QueueTrack]) -> UpNextQueue {
    guard let state = queue.upNext, !tracks.isEmpty, queue.current != nil else { return queue }
    return added(queue, state, tracks, at: layout(queue, state).addedEnd)
}

/// Where the entry `key` is, and the group of Up Next's rows it is in: Playing Next (the songs added), or the list
/// as Up Next shows it (the shown round). Nil for a key at or before the song playing, a copy, a later round, or one
/// the queue doesn't have.
private func groupOf(_ queue: UpNextQueue, _ state: UpNextState, _ key: Int)
    -> (place: Int, start: Int, end: Int, added: Bool)? {
    guard let place = state.marks.firstIndex(where: { $0.key == key }) else { return nil }
    let (copiesEnd, addedEnd, listEnd) = layout(queue, state)
    if place < copiesEnd || state.marks[place].from == .one { return nil }
    if place < addedEnd { return (place, copiesEnd, addedEnd, true) }
    return place < listEnd ? (place, addedEnd, listEnd, false) : nil
}

/// A row of Up Next out - with its copies. One of the list's is noted as taken out of its round (`left`).
public func withoutKey(_ queue: UpNextQueue, _ key: Int) -> UpNextQueue {
    guard let state = queue.upNext, let group = groupOf(queue, state, key) else { return queue }
    let gone = state.marks[group.place]
    let end = unitEnd(state, group.place)
    let (tracks, marks) = kept(queue, state) { $1 < group.place || $1 >= end }
    return rebuilt(queue, state, tracks, marks) { next in
        if gone.from == .source { next.left.append(LeftOut(pass: gone.pass, at: gone.at)) }
    }
}

/// A row of Up Next to place `to` (0-based) of its own group - Playing Next, or the list - held inside the group,
/// counted in rows (units: a song and its copies move together).
public func movedKey(_ queue: UpNextQueue, _ key: Int, to: Int) -> UpNextQueue {
    guard let state = queue.upNext, let group = groupOf(queue, state, key) else { return queue }
    let units = unitsIn(state, group.start, group.end)
    guard let from = units.firstIndex(of: group.place) else { return queue }
    let dest = max(0, min(units.count - 1, to))
    if dest == from { return queue }
    var order = units.map { (start: $0, end: unitEnd(state, $0)) }
    order.insert(order.remove(at: from), at: dest)
    func move<T>(_ list: [T]) -> [T] {
        var out = Array(list[..<group.start])
        for unit in order { out += list[unit.start..<unit.end] }
        return out + Array(list[group.end...])
    }
    return rebuilt(queue, state, move(queue.tracks), move(state.marks))
}

/// Clear: Playing Next out - the songs added straight after the song playing, the group Clear heads (a song added
/// further on, that Previous walked back across, plays where it played and stays).
public func withoutAdded(_ queue: UpNextQueue) -> UpNextQueue {
    guard let state = queue.upNext else { return queue }
    let (copiesEnd, addedEnd, _) = layout(queue, state)
    if addedEnd == copiesEnd { return queue }
    let (tracks, marks) = kept(queue, state) { $1 < copiesEnd || $1 >= addedEnd }
    return rebuilt(queue, state, tracks, marks)
}

/// A row's tap, as the player makes it: the queue to put in place first (an edit of what comes after the song
/// playing, or the same queue), and the entry to move to then.
public struct Jump: Sendable, Equatable {
    public let queue: UpNextQueue
    public let index: Int

    public init(queue: UpNextQueue, index: Int) {
        self.queue = queue
        self.index = index
    }
}

/// A row's tap (James, 2026-11-11: "6 and 7 stay behind 8: Previous from 8 plays 7, then 6, as on the album").
/// Nothing is dropped: the place moves to the row, and the rows it passes stay where they are, behind it.
///
/// - A row of the list: the place moves there; Playing Next goes straight after it (and its copies) - songs added
///   still play next - and the list's rows above it stay behind it, in their order, where Previous finds them.
/// - A row of Playing Next: the place moves there; the songs added above it stay behind it.
/// - A row of History (an entry before the song playing's unit): the song AGAIN - a new entry of it, a song added,
///   straight after the song playing's copies (where Play Next goes), moved to; the songs after are as they were,
///   and History is never rewritten: it is what played, and the song played again joins it as played.
///
/// `index` is the entry to move to, in `queue`; the edit keeps `tracks[0...index]` of the queue it was given (the
/// player's replaceUpcoming takes it as any edit). Nil for the song playing (or one of its copies), a key it doesn't
/// have, a row Up Next doesn't draw (a later time round, a copy), or one History doesn't (before where listening
/// began, past UpNext.historyBack) - every row drawn is one a tap reaches, and nothing else is.
public func jumpedTo(_ queue: UpNextQueue, _ key: Int) -> Jump? {
    guard let state = queue.upNext, queue.current != nil,
          let place = state.marks.firstIndex(where: { $0.key == key }) else { return nil }
    let (copiesEnd, addedEnd, _) = layout(queue, state)
    if place < unitStart(state, queue.index) {
        guard historyRows(queue).contains(where: { $0.key == key }) else { return nil }
        return Jump(queue: added(queue, state, [queue.tracks[place]], at: copiesEnd), index: copiesEnd)
    }
    guard let group = groupOf(queue, state, key) else { return nil }
    if group.added || addedEnd == copiesEnd { return Jump(queue: queue, index: group.place) }
    //? into the list with songs added: they go after the row's unit; by old place, up to the copies, the list up to
    //? and including the row, Playing Next, the rest
    let end = unitEnd(state, group.place)
    let places = Array(0..<copiesEnd) + Array(addedEnd..<end) + Array(copiesEnd..<addedEnd)
        + Array(end..<max(end, state.marks.count))
    return Jump(queue: rebuilt(queue, state, places.map { queue.tracks[$0] }, places.map { state.marks[$0] }),
                index: group.place - (addedEnd - copiesEnd))
}

/// History: the units before the song playing's, oldest first - from `startedAt` (the list's songs before where
/// listening began were never heard) and no further back than `back` entries before the song playing - what a
/// reload keeps (Resume.before), so it draws the same after one. One row a unit, keyed by its first entry. A run of
/// copies at that edge, its song further back, isn't a row.
public func historyRows(_ queue: UpNextQueue, back: Int = UpNext.historyBack) -> [UpNextRow] {
    guard let state = queue.upNext, queue.current != nil else { return [] }
    var rows: [UpNextRow] = []
    var place = historyFloor(queue, state, back: back)
    let stop = unitStart(state, queue.index)
    while place < stop {
        if state.marks[place].from != .one { rows.append(UpNextRow(key: state.marks[place].key, track: queue.tracks[place])) }
        place = unitEnd(state, place)
    }
    return rows
}

/// How far back History reaches: from where listening began, no further than `back` entries before the song playing.
func historyFloor(_ queue: UpNextQueue, _ state: UpNextState, back: Int = UpNext.historyBack) -> Int {
    max(state.startedAt, queue.index - back, 0)
}

/// (2.1.15) Where the entries Up Next's rows stand for begin - History's first row (its floor, past a run of copies
/// there whose song is further back, never a row), or the song playing's unit if that comes first. The queue's length
/// with nothing playing.
func shownFrom(_ queue: UpNextQueue, _ state: UpNextState) -> Int {
    guard queue.current != nil else { return queue.tracks.count }
    let playing = unitStart(state, queue.index)
    var place = historyFloor(queue, state)
    while place < playing && markAt(state.marks, place)?.from == .one { place += 1 }
    return min(place, playing)
}

/// (2.1.15) The keys of the entries Up Next's rows stand for - exactly what upNextView(queue, _, limit:) draws, each
/// row's entry with its copies: History's units, the song playing's, the songs added, and the list's first `limit`
/// rows. One run, from shownFrom to the end of the last list row drawn - NEVER a later time round (Repeat All's, which
/// Up Next sums up in a line) or a list row past `limit` ("And N more songs"), though Previous can leave songs begun
/// there. PlayHistory.swift draws a start of any other entry among the older plays above History, so each is drawn
/// once. None with nothing playing.
public func shownKeys(_ queue: UpNextQueue, limit: Int = UpNext.drawn) -> Set<Int> {
    guard let state = queue.upNext, queue.current != nil else { return [] }
    let (_, addedEnd, listEnd) = layout(queue, state)
    let listed = unitsIn(state, addedEnd, listEnd)
    let end = listed.count > limit ? listed[limit] : listEnd
    var keys = Set<Int>()
    var place = shownFrom(queue, state)
    while place < end {
        keys.insert(state.marks[place].key)
        place += 1
    }
    return keys
}

/// Previous's move: the queue at `index` - and, back before where listening began, `startedAt` moved down to the
/// unit landed in, so History shows the songs played from there. The same tracks: the engine's skip still applies.
public func wentBack(_ queue: UpNextQueue, _ index: Int) -> UpNextQueue {
    var next = queue
    next.index = index
    if let state = queue.upNext {
        let start = unitStart(state, index)
        if start < state.startedAt { next.upNext?.startedAt = start }
    }
    return next
}

/// Next: the first entry after the song playing that isn't one of Repeat One's copies; nil if none.
public func onward(_ queue: UpNextQueue) -> Int? {
    guard let state = queue.upNext else { return nextIndex(queue) }
    var place = max(queue.index + 1, 0)
    while place < state.marks.count {
        if state.marks[place].from != .one { return place }
        place += 1
    }
    return nil
}

/// Previous: previousAction()'s rule - the song again past RESTART_AFTER_SECONDS or at the first song - but going
/// back passes over the run of Repeat One's copies the song playing is part of (the copies before it, and its
/// original) to the entry before them; with none before them, the song again.
public func backward(_ queue: UpNextQueue, position: Double) -> PreviousAction {
    let action = previousAction(queue, position: position)
    guard case .go = action, let state = queue.upNext else { return action }
    var place = queue.index
    while place > 0 && markAt(state.marks, place)?.from == .one { place -= 1 }
    return place > 0 ? .go(place - 1) : .restart
}

/// A failed song's skip: the first entry at or after `from` that isn't one of Repeat One's copies - a song that
/// won't play isn't asked for again once per copy. Nil if none: the queue stops there, as at its end.
public func pastCopies(_ queue: UpNextQueue, from: Int) -> Int? {
    guard let state = queue.upNext else { return from >= 0 && from < queue.tracks.count ? from : nil }
    var place = max(from, 0)
    while place < state.marks.count {
        if state.marks[place].from != .one { return place }
        place += 1
    }
    return nil
}

/// The time round of the list Up Next shows: the first of the list's songs after the song playing's; -1 for none.
public func shownPass(_ queue: UpNextQueue) -> Int {
    guard let state = queue.upNext else { return -1 }
    var place = max(queue.index + 1, 0)
    while place < state.marks.count {
        if state.marks[place].from == .source { return state.marks[place].pass }
        place += 1
    }
    return -1
}

/// (Part B) More of a library's shuffle, from its feed - unless the queue playing is no longer that shuffle
/// (`token`), the same queue. Appended at the END as the list's songs: the rest of this time round, or - the whole
/// order fetched already, `next` a fresh one (Repeat All) - the next time round, `next` the shuffle from then on. A
/// fresh order for one that went (deadwax restarted) is the rest of this round.
public func withMore(_ queue: UpNextQueue, token: String, tracks: [QueueTrack], next: Paged? = nil) -> UpNextQueue {
    //? nothing to append - a fresh order of an emptied library too: the same queue, so its feed asks no more
    guard let state = queue.upNext, let paged = state.paged, paged.token == token, !tracks.isEmpty else { return queue }
    let round = next != nil && paged.fetched >= paged.total
    let last = lastSourceAt(state.marks, state.marks.count - 1)
    let before = last < 0 ? 0 : state.marks[last].pass
    let pass = before + (round ? 1 : 0)
    let marks = tracks.indices.map { Mark(key: state.nextKey + $0, from: .source, at: state.source.count + $0, pass: pass) }
    //? a next round: the order of the round before kept by its round, for a Repeat turned off (withRepeat); rounds
    //? before the song playing's can no longer be gone back to
    let playing = passPlaying(state.marks, queue.index)
    return rebuilt(queue, state, queue.tracks + tracks, state.marks + marks) { more in
        more.source += tracks
        more.nextKey = state.nextKey + tracks.count
        if var fresh = next {
            fresh.fetched = tracks.count
            more.paged = fresh
        } else {
            var same = paged
            same.fetched += tracks.count
            more.paged = same
        }
        if round {
            more.pagedRounds = (state.pagedRounds ?? []).filter { $0.pass >= playing } + [PagedRound(pass: before, paged: paged)]
        }
    }
}
