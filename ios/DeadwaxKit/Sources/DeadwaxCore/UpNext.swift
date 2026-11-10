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
// do. (jumpedTo alone puts the row first, ahead of the songs added, until the engine moves onto it.) A queue with no
// `upNext` - `UpNextQueue.empty`, or a plain queue - is handed back as it is by every edit, and onward, backward
// and pastCopies answer as nextIndex and previousAction would.
//
// RANDOMNESS comes in only through startUpNext, toppedUp and withShuffle, each as `random` (a number in [0, 1)),
// drawn in exactly the TypeScript's order, so the same numbers make the same queue: ios/scripts/export-traces.cjs
// records what the TypeScript drew and did, and UpNextTraceTests replays it.
//
// Pure: no I/O, no clock; built and tested on Linux.

extension UpNext {
    /// The system's random number in [0, 1), Math.random's stand-in.
    public static func systemRandom() -> Double { Double.random(in: 0..<1) }
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

/// Where Repeat One's copies after the song playing end, and where the songs added after them end.
func layout(_ queue: UpNextQueue, _ state: UpNextState) -> (copiesEnd: Int, addedEnd: Int) {
    var copiesEnd = queue.index + 1
    while markAt(state.marks, copiesEnd)?.from == .one { copiesEnd += 1 }
    var addedEnd = copiesEnd
    while markAt(state.marks, addedEnd)?.from == .added { addedEnd += 1 }
    return (copiesEnd, addedEnd)
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
/// B): the first page of a whole library's shuffle - its order is the shuffle, so Shuffle reads on.
public func startUpNext(_ tracks: [QueueTrack], start: Int?, shuffle: Bool = false,
                        random: () -> Double = UpNext.systemRandom, paged: Paged? = nil) -> UpNextQueue {
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
/// go of the later times round (the list's songs after the song playing of a round later than its own). The player
/// then tops the queue up for the new mode (toppedUp).
public func withRepeat(_ queue: UpNextQueue, _ mode: Repeat) -> UpNextQueue {
    guard let state = queue.upNext else { return queue }
    let round = passPlaying(state.marks, queue.index)
    let goes = { (mark: Mark, place: Int) -> Bool in
        place > queue.index &&
            ((mode != .one && mark.from == .one) || (mode != .all && mark.from == .source && mark.pass > round))
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
/// One's copies their place). The later times round go - toppedUp grows them again in the new order. The round is
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
    var (tracks, marks) = kept(queue, state) { mark, place in place <= index || mark.from != .source }
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
private func groupOf(_ queue: UpNextQueue, _ state: UpNextState, _ key: Int) -> (place: Int, start: Int, end: Int)? {
    guard let place = state.marks.firstIndex(where: { $0.key == key }), place > queue.index else { return nil }
    let found = state.marks[place]
    let (copiesEnd, addedEnd) = layout(queue, state)
    if found.from == .added { return place < addedEnd ? (place, copiesEnd, addedEnd) : nil }
    guard found.from == .source, let shown = markAt(state.marks, addedEnd)?.pass, found.pass == shown else { return nil }
    var end = addedEnd
    while let next = markAt(state.marks, end), next.from == .source, next.pass == shown { end += 1 }
    return place < end ? (place, addedEnd, end) : nil
}

/// A row of Up Next out. One of the list's is noted as taken out of its round (`left`).
public func withoutKey(_ queue: UpNextQueue, _ key: Int) -> UpNextQueue {
    guard let state = queue.upNext, let group = groupOf(queue, state, key) else { return queue }
    let gone = state.marks[group.place]
    let (tracks, marks) = kept(queue, state) { $1 != group.place }
    return rebuilt(queue, state, tracks, marks) { next in
        if gone.from == .source { next.left.append(LeftOut(pass: gone.pass, at: gone.at)) }
    }
}

/// A row of Up Next to place `to` (0-based) of its own group - Playing Next, or the list - held inside the group.
public func movedKey(_ queue: UpNextQueue, _ key: Int, to: Int) -> UpNextQueue {
    guard let state = queue.upNext, let group = groupOf(queue, state, key) else { return queue }
    let from = group.place - group.start
    let dest = max(0, min(group.end - group.start - 1, to))
    if dest == from { return queue }
    func move<T>(_ list: [T]) -> [T] {
        var inside = Array(list[group.start..<group.end])
        inside.insert(inside.remove(at: from), at: dest)
        return Array(list[..<group.start]) + inside + Array(list[group.end...])
    }
    return rebuilt(queue, state, move(queue.tracks), move(state.marks))
}

/// Clear: every song added, after the song playing, out.
public func withoutAdded(_ queue: UpNextQueue) -> UpNextQueue {
    guard let state = queue.upNext else { return queue }
    let goes = { (mark: Mark, place: Int) -> Bool in place > queue.index && mark.from == .added }
    if !state.marks.enumerated().contains(where: { goes($0.element, $0.offset) }) { return queue }
    let (tracks, marks) = kept(queue, state) { !goes($0, $1) }
    return rebuilt(queue, state, tracks, marks)
}

/// A row's tap: the row `key` moved straight after the copies (where Play Next goes), and the rows ABOVE it in its
/// own group dropped - jumping into the list keeps Playing Next (it plays after the song jumped to), jumping into
/// Playing Next drops only the songs added above it. The list's songs jumped over are noted as taken out of their
/// round. Nil for a key it can't jump to. The player then moves onto it as Next does (onward).
public func jumpedTo(_ queue: UpNextQueue, _ key: Int) -> UpNextQueue? {
    guard let state = queue.upNext, let group = groupOf(queue, state, key) else { return nil }
    let copiesEnd = layout(queue, state).copiesEnd
    let jumped = state.marks[group.place]
    let over = state.marks[group.start..<group.place]
    //? the new order, by old place: up to the copies, the row, then everything else but the rows above it
    var places = Array(0..<copiesEnd)
    places.append(group.place)
    for place in copiesEnd..<max(copiesEnd, state.marks.count) where !(place >= group.start && place <= group.place) {
        places.append(place)
    }
    return rebuilt(queue, state, places.map { queue.tracks[$0] }, places.map { state.marks[$0] }) { next in
        if jumped.from == .source { next.left += over.map { LeftOut(pass: $0.pass, at: $0.at) } }
    }
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
