import Foundation

// Resume what was playing - ui/src/lib/resume.ts, function by function. The person's play queue is kept in two
// places written and read together (src/play_queue.py): Navidrome's play queue as them (the ids, the index, the
// position: what any Subsonic app sees, and the authority on what was played last), and deadwax's record beside it
// (`kept`: the same, and the snapshot below - the account of Up Next, which Navidrome can't hold). The phone and the
// web app share both: a queue saved on one is picked up on the other.
//
// What is saved is a WINDOW: at most `Resume.before` entries before the song playing and `Resume.maxEntries` in
// all. The snapshot (v1, made only by toSave, read only by fromSnapshot) lists the source by id, with the whole
// song (`extra`) only for source songs outside the window, one character a level per entry. It is written as
// JSON.stringify writes it, to the byte (SnapshotJSON.swift), and read as the web reads it: every check of
// fromSnapshot in its order. ios/scripts/export-traces.cjs records what the TypeScript writes and reads, and
// ResumeTraceTests holds this file to it.
//
// The web compares queues by object identity (`queue !== saved.tracks`); Up Next's edits hand back the very object
// when nothing changes, so there identity means "the same queue". Here it is value equality (Array's == returns at
// once for the same storage) - which differs only for an edit that ends exactly where it began, then no change.
//
// Pure: no I/O, no clock; built and tested on Linux. ResumeController.swift acts on it.

/// Resume's numbers (resume.ts, app/useResume.ts, src/play_queue.py).
public enum Resume {
    /// RESUME_MAX: the most entries saved (play_queue.py RESUME_MAX).
    public static let maxEntries = 2000
    /// RESUME_BEFORE: of them, the most before the song playing - the history Previous walks.
    public static let before = 50
    /// RESUME_SNAPSHOT_MAX: the snapshot's most characters, counted as JavaScript counts them (UTF-16 units) -
    /// never fewer than the server's code points, so a snapshot kept here is never one it refuses.
    public static let snapshotMax = 262_144
    /// RESUME_EVERY_S: seconds of playing between two saves of where it is.
    public static let everySeconds = 30
    /// RESUME_FULL_WAIT_MS, RESUME_AT_WAIT_MS: a change of the songs or of Up Next is saved this long after the last
    /// of a burst; a song change this long after.
    public static let fullWaitMs: Int64 = 2000
    public static let atWaitMs: Int64 = 1000
    /// RESUME_RECHECK_MS: coming back to the front asks again at most this often.
    public static let recheckMs: Int64 = 15_000
    /// MARGIN_MS (useResume.ts): a wait's few ms over its rule, so the clock it is judged by has always passed it.
    public static let marginMs: Int64 = 50
    /// DEADWAX_CLIENT: what Navidrome records deadwax's saves as (navidrome_endpoint.py CLIENT_NAME).
    public static let deadwaxClient = "deadwax"
    /// What this phone is called in deadwax's record, and so in the notice on another device: what the web's
    /// deviceLabel says for Safari on an iPhone ("Picked up from your iPhone"). Inside play_queue.py's LABEL_PATTERN.
    public static let label = "iPhone"
    /// play_queue.py POSITION_MAX: the furthest position a save may name, in seconds.
    public static let positionMax = 86_400.0
    /// OWED_ORDER (useResume.ts): the triggers held while a request was out, asked again in this order.
    public static let owedOrder: [SaveTrigger] = [.pause, .wait, .position]

    /// A position as a save sends it: inside the server's 0...86,400, and 0 for one that isn't a number. The web
    /// can't make another; a 422 on a position save would be read as "save in full", which would 422 again.
    public static func sent(_ position: Double) -> Double {
        guard position.isFinite else { return 0 }
        return Swift.min(Swift.max(position, 0), positionMax)
    }
}

/* ===== the window, and the snapshot ===== */

/// The window of a queue of `count` entries playing `index`: [start, end) - play_queue.py's `window` too.
public func windowOf(_ count: Int, _ index: Int) -> (start: Int, end: Int) {
    if count <= 0 { return (0, 0) }
    let at = min(max(index, 0), count - 1)
    let start = max(0, at - Resume.before)
    return (start, min(count, start + Resume.maxEntries))
}

/// What a full save sends of a queue.
public struct Saving: Sendable, Equatable {
    public var ids: [String]
    /// the song playing, in `ids`
    public var index: Int
    public var position: Double
    /// the account of Up Next - nil for a queue without one, or one over `Resume.snapshotMax`
    public var snapshot: String?
    /// where `ids` begin in the queue
    public var start: Int

    public init(ids: [String], index: Int, position: Double, snapshot: String?, start: Int) {
        self.ids = ids
        self.index = index
        self.position = position
        self.snapshot = snapshot
        self.start = start
    }
}

private func levelChar(_ level: Level?) -> String {
    switch level {
    case .album: return "a"
    case .track: return "t"
    case nil: return "-"
    }
}

/// A level's character as fromSnapshot reads one, a UTF-16 unit at a time: 'a' album, 't' track, else none.
private func charLevel(_ unit: UInt16?) -> Level? {
    switch unit {
    case 0x61: return .album
    case 0x74: return .track
    default: return nil
    }
}

private func fromChar(_ from: MarkFrom) -> String {
    switch from {
    case .source: return "s"
    case .added: return "a"
    case .one: return "o"
    }
}

/// A song as the queue needs it, without its level - what `extra` keeps.
private func bare(_ track: QueueTrack) -> QueueTrack {
    var out = track
    out.level = nil
    return out
}

/// `"key":` and then the value - a member of an object after the first.
private extension WebJSON.Writer {
    mutating func member(_ name: String, first: Bool = false, _ value: (inout WebJSON.Writer) -> Void) {
        if !first { comma() }
        key(name)
        value(&self)
    }

    /// A song of `extra`: its twelve fields in bare()'s order, the four that may be none written as null (the web's
    /// readSong refuses one left out).
    mutating func song(_ track: QueueTrack) {
        open()
        member("id", first: true) { $0.string(track.id) }
        member("title") { $0.string(track.title) }
        member("artist") { $0.string(track.artist) }
        member("album") { $0.string(track.album) }
        member("albumId") { $0.nullableString(track.albumId) }
        member("coverArt") { $0.nullableString(track.coverArt) }
        member("duration") { $0.number(track.duration) }
        member("contentType") { $0.nullableString(track.contentType) }
        member("suffix") { $0.nullableString(track.suffix) }
        member("sampleRate") { $0.int(track.sampleRate) }
        member("bitDepth") { $0.int(track.bitDepth) }
        member("channels") { $0.int(track.channels) }
        close()
    }

    /// A Paged as the web's objects have it: token, total, fetched, scope, and level only when there is one (the
    /// web's readPaged refuses a null).
    mutating func paged(_ paged: Paged) {
        open()
        member("token", first: true) { $0.string(paged.token) }
        member("total") { $0.int(paged.total) }
        member("fetched") { $0.int(paged.fetched) }
        member("scope") { $0.string(paged.scope.rawValue) }
        if let level = paged.level { member("level") { $0.string(level.rawValue) } }
        close()
    }
}

/// The marks or tracks [start, end), held inside what there is (the TypeScript's `slice`).
private func sliced<T>(_ list: [T], _ start: Int, _ end: Int) -> ArraySlice<T> {
    let from = min(max(start, 0), list.count)
    return list[from..<max(from, min(end, list.count))]
}

/// What a full save sends of a queue: its window - entries [start, end), the index and `startedAt` moved down by
/// `start` (startedAt floored at 0), the marks sliced with them - and the snapshot of its Up Next, `left`, `source`,
/// `paged` as they are.
public func toSave(_ queue: UpNextQueue, position: Double) -> Saving {
    let (start, end) = windowOf(queue.tracks.count, queue.index)
    let entries = Array(sliced(queue.tracks, start, end))
    let ids = entries.map(\.id)
    let index = queue.index - start
    guard let state = queue.upNext else { return Saving(ids: ids, index: index, position: position, snapshot: nil, start: start) }
    //? `extra`: the source's songs outside the window, the first of each id. The web asks `id in extra`, which is
    //? true for an object's own names too (constructor, toString...) - such a song is never kept whole there, so
    //? here neither: the same text, and the web reads it as it reads its own
    let inWindow = Set(ids)
    var extraOrder: [String] = []
    var extra: [String: QueueTrack] = [:]
    for track in state.source where !inWindow.contains(track.id) && extra[track.id] == nil
        && !WebJSON.prototypeNames.contains(track.id) {
        extra[track.id] = bare(track)
        extraOrder.append(track.id)
    }
    var made = WebJSON.Writer()
    made.open()
    made.member("v", first: true) { $0.int(1) }
    made.member("levels") { $0.string(entries.map { levelChar($0.level) }.joined()) }
    made.member("marks") { writer in
        writer.array(Array(sliced(state.marks, start, end))) { item, mark in
            item.raw("[\(mark.key),\"\(fromChar(mark.from))\",\(mark.at),\(mark.pass)]")
        }
    }
    made.member("source") { $0.array(state.source) { item, track in item.string(track.id) } }
    made.member("sourceLevels") { $0.string(state.source.map { levelChar($0.level) }.joined()) }
    made.member("extra") { writer in
        writer.open()
        for (place, id) in WebJSON.ordered(extraOrder).enumerated() {
            writer.member(id, first: place == 0) { $0.song(extra[id]!) }
        }
        writer.close()
    }
    made.member("shuffle") { $0.bool(state.shuffle) }
    made.member("nextKey") { $0.int(state.nextKey) }
    made.member("startedAt") { $0.int(max(0, state.startedAt - start)) }
    made.member("left") { $0.array(state.left) { item, gone in item.raw("[\(gone.pass),\(gone.at)]") } }
    if let paged = state.paged { made.member("paged") { $0.paged(paged) } }
    if let rounds = state.pagedRounds {
        made.member("pagedRounds") { writer in
            writer.array(rounds) { item, held in
                item.open()
                item.member("pass", first: true) { $0.int(held.pass) }
                item.member("paged") { $0.paged(held.paged) }
                item.close()
            }
        }
    }
    made.close()
    let snapshot = made.text
    return Saving(ids: ids, index: index, position: position,
                  snapshot: snapshot.utf16.count <= Resume.snapshotMax ? snapshot : nil, start: start)
}

/* ===== reading it back ===== */

/// JavaScript's Number.isInteger, as an Int: nil for anything else (and, unlike the web, for an integer past
/// Int's range - which no writer makes).
private func int(_ value: WebJSON.Value?) -> Int? {
    guard case .number(let number)? = value, number.isFinite, number == number.rounded(),
          abs(number) < 9.2e18 else { return nil }
    return Int(number)
}

private func finite(_ value: WebJSON.Value?) -> Double? {
    guard case .number(let number)? = value, number.isFinite else { return nil }
    return number
}

private func text(_ value: WebJSON.Value?) -> String? {
    guard case .string(let text)? = value else { return nil }
    return text
}

/// null or a string, present: `.some(nil)` for null, nil for anything else (a missing key among them).
private func nullableText(_ value: WebJSON.Value?) -> String?? {
    switch value {
    case .null?: return .some(nil)
    case .string(let text)?: return .some(text)
    default: return nil
    }
}

/// A song kept whole in `extra`, as the web's readSong takes one: an object naming `id`, title, artist and album
/// strings, the four that may be none null or a string, the four numbers finite. Only its twelve fields are kept.
/// (A rate, depth or count that isn't a whole number - the web keeps one - is taken toward zero; no writer makes
/// one.)
private func readSong(_ value: WebJSON.Value?, _ id: String) -> QueueTrack? {
    guard case .object(let fields)? = value, text(fields["id"]) == id,
          let title = text(fields["title"]), let artist = text(fields["artist"]), let album = text(fields["album"]),
          let albumId = nullableText(fields["albumId"]), let coverArt = nullableText(fields["coverArt"]),
          let contentType = nullableText(fields["contentType"]), let suffix = nullableText(fields["suffix"]),
          let duration = finite(fields["duration"]), let sampleRate = finite(fields["sampleRate"]),
          let bitDepth = finite(fields["bitDepth"]), let channels = finite(fields["channels"]) else { return nil }
    func whole(_ number: Double) -> Int? { abs(number) < 9.2e18 ? Int(number.rounded(.towardZero)) : nil }
    guard let rate = whole(sampleRate), let bits = whole(bitDepth), let count = whole(channels) else { return nil }
    return QueueTrack(id: id, title: title, artist: artist, album: album, albumId: albumId, coverArt: coverArt,
                      duration: duration, contentType: contentType, suffix: suffix, sampleRate: rate, bitDepth: bits,
                      channels: count)
}

/// A Paged as the web's readPaged takes one, its level re-fitted to `setting` (a paged saved with none reads as
/// track under Automatic, none under Off). A `level` of null is refused, as the web refuses it.
private func readPaged(_ value: WebJSON.Value?, _ setting: Normalization) -> Paged? {
    guard case .object(let fields)? = value, let token = text(fields["token"]), let total = int(fields["total"]),
          let fetched = int(fields["fetched"]) else { return nil }
    guard let scope = text(fields["scope"]).flatMap(PagedScope.init(rawValue:)) else { return nil }
    var saved: Level?
    if let raw = fields["level"] {
        guard let level = text(raw).flatMap(Level.init(rawValue:)) else { return nil }
        saved = level
    }
    return Paged(token: token, total: total, fetched: fetched, scope: scope, level: relevel(saved, setting))
}

/// The levels a snapshot saved for its `count` entries - none for each where it can't say. As the web's: the
/// string must be `count` UTF-16 units long, and is then read a code point at a time (`[...levels]`), so a
/// character outside the BMP - which no writer makes - leaves the list one short.
public func savedLevels(_ snapshot: String?, count: Int) -> [Level?] {
    if let snapshot, case .object(let made)? = WebJSON.parse(snapshot), case .number(1)? = made["v"],
       let levels = text(made["levels"]), levels.utf16.count == count {
        return levels.unicodeScalars.map { scalar -> Level? in scalar == "a" ? .album : scalar == "t" ? .track : nil }
    }
    return Array(repeating: nil, count: max(0, count))
}

/// The queue a snapshot describes, over `tracks` - Navidrome's songs, the window's entries, in order - playing
/// `index`, every level re-fitted to `setting`. Nil when it doesn't read back: not JSON, another version, a source
/// song in neither Navidrome's songs nor `extra`, or a rebuilt state failing its checks - marks as long as the
/// entries, each mark's `from` one of the three, a source mark's `at` inside the source and naming its song, an
/// added mark's at and pass -1, keys unique and below nextKey, startedAt not below 0 (and past the song playing's
/// run, lowered to it).
public func fromSnapshot(_ snapshot: String?, tracks: [QueueTrack], index: Int, setting: Normalization) -> UpNextQueue? {
    guard let snapshot, case .object(let made)? = WebJSON.parse(snapshot), case .number(1)? = made["v"] else { return nil }
    let n = tracks.count
    guard let levels = text(made["levels"]), levels.utf16.count == n,
          case .array(let marks)? = made["marks"], marks.count == n else { return nil }
    guard case .array(let sourceValues)? = made["source"] else { return nil }
    let source = sourceValues.compactMap { text($0) }
    guard source.count == sourceValues.count else { return nil }
    guard let sourceLevels = text(made["sourceLevels"]), sourceLevels.utf16.count == source.count,
          case .object(let extra)? = made["extra"] else { return nil }
    guard case .bool(let shuffle)? = made["shuffle"], let nextKey = int(made["nextKey"]),
          let startedAt = int(made["startedAt"]), case .array(let left)? = made["left"] else { return nil }
    //? startedAt is where listening began - where withShuffle's first round's heard songs begin and (2.1.3) History's
    //? floor - so any place at or after 0 reads back; one past the song playing's run is lowered to it, below
    guard index >= 0, index < n, startedAt >= 0 else { return nil }
    //? the songs: Navidrome's where it has them (the last of an id, as a Map keeps it), `extra` for the source's
    //? outside the window
    let navidrome = Dictionary(tracks.map { ($0.id, bare($0)) }, uniquingKeysWith: { _, last in last })
    let levelUnits = Array(levels.utf16)
    let sourceUnits = Array(sourceLevels.utf16)
    func song(_ id: String, _ unit: UInt16?) -> QueueTrack? {
        guard var base = navidrome[id] ?? readSong(extra[id], id) else { return nil }
        base.level = relevel(charLevel(unit), setting)
        return base
    }
    var entries: [QueueTrack] = []
    entries.reserveCapacity(n)
    for (place, track) in tracks.enumerated() {
        guard let found = song(track.id, levelUnits[place]) else { return nil }
        entries.append(found)
    }
    var list: [QueueTrack] = []
    list.reserveCapacity(source.count)
    for (place, id) in source.enumerated() {
        guard let found = song(id, sourceUnits[place]) else { return nil }
        list.append(found)
    }
    var keys = Set<Int>()
    var rebuilt: [Mark] = []
    rebuilt.reserveCapacity(n)
    for (place, raw) in marks.enumerated() {
        guard case .array(let fields) = raw, fields.count == 4 else { return nil }
        guard let key = int(fields[0]), let at = int(fields[2]), let pass = int(fields[3]),
              key >= 0, key < nextKey, !keys.contains(key) else { return nil }
        keys.insert(key)
        let from: MarkFrom
        switch text(fields[1]) {
        case "s"?: from = .source
        case "a"?: from = .added
        case "o"?: from = .one
        default: return nil
        }
        if from == .source && (at < 0 || at >= list.count || list[at].id != entries[place].id || pass < 0) { return nil }
        if from == .added && (at != -1 || pass != -1) { return nil }
        if from == .one && (at < -1 || at >= list.count) { return nil }
        rebuilt.append(Mark(key: key, from: from, at: at, pass: pass))
    }
    //? (2.1.3) wentBack keeps startedAt at or before the song playing's run; a queue saved before 2.1.3 - the web's
    //? 2.1.2, the iPhone's 0.2 - whose Previous went back before where the album began has it past that. Lowered to
    //? the run: everything from there to the song playing was heard, so History shows it once it has played
    var run = index
    while run > 0 && rebuilt[run].from == .one { run -= 1 }
    var gone: [LeftOut] = []
    for raw in left {
        guard case .array(let pair) = raw, pair.count == 2, let pass = int(pair[0]), let at = int(pair[1]) else { return nil }
        gone.append(LeftOut(pass: pass, at: at))
    }
    var paged: Paged?
    if let raw = made["paged"] {
        guard let read = readPaged(raw, setting) else { return nil }
        paged = read
    }
    var pagedRounds: [PagedRound]?
    if let raw = made["pagedRounds"] {
        guard case .array(let held) = raw else { return nil }
        var rounds: [PagedRound] = []
        for round in held {
            guard case .object(let fields) = round, let pass = int(fields["pass"]),
                  let read = readPaged(fields["paged"], setting) else { return nil }
            rounds.append(PagedRound(pass: pass, paged: read))
        }
        pagedRounds = rounds
    }
    let state = UpNextState(marks: rebuilt, source: list, shuffle: shuffle, nextKey: nextKey,
                            startedAt: min(startedAt, run),
                            left: gone, paged: paged, pagedRounds: pagedRounds)
    return UpNextQueue(tracks: entries, index: index, upNext: state)
}

/// A plain list: the songs in order, from `index`, as playTracks(tracks, index) queues them - each at its level,
/// re-fitted to this device (`levels` the ones saved, where known; a song with no level to give is left as it is).
private func plainQueue(_ tracks: [QueueTrack], _ index: Int, _ levels: [Level?], _ setting: Normalization) -> UpNextQueue {
    let levelled = tracks.enumerated().map { place, track -> QueueTrack in
        guard let level = relevel(place < levels.count ? levels[place] : nil, setting) else { return track }
        var out = bare(track)
        out.level = level
        return out
    }
    return startUpNext(levelled, start: index)
}

/// A song of GET /queue's answer as a queue entry - the web's shuffledTrack (app/useShuffleFeed.ts), its album known
/// only by its id and name: `toQueueTrack(song, {id: albumId ?? "", name: album ?? ""})`. (A title Navidrome left
/// out is "" here; the web carries it as undefined - Navidrome always sends one.)
public func shuffledTrack(_ song: Song) -> QueueTrack {
    QueueTrack(id: song.id, title: song.title ?? "", artist: song.artist ?? "", album: song.album ?? "",
               albumId: song.albumId ?? "", coverArt: song.coverArt, duration: song.duration ?? 0,
               contentType: song.contentType, suffix: song.suffix, sampleRate: song.samplingRate ?? 0,
               bitDepth: song.bitDepth ?? 0, channels: song.channelCount ?? 0)
}

/// Where a queue came from, for the notice: another device of deadwax's (by its label), or another app.
public enum PickedFrom: Sendable, Equatable {
    case device(String)
    case app(String)
}

public struct Resumed: Sendable, Equatable {
    public var queue: UpNextQueue
    public var position: Double
    /// nil: this device, or no telling
    public var from: PickedFrom?
    /// the ids deadwax kept are Navidrome's - its record believed, a position save against its ids_rev possible
    public var exact: Bool

    public init(queue: UpNextQueue, position: Double, from: PickedFrom?, exact: Bool) {
        self.queue = queue
        self.position = position
        self.from = from
        self.exact = exact
    }
}

/// What is put back from GET /queue's answer (its songs made entries by shuffledTrack).
public func resumed(_ answer: QueueAnswer, setting: Normalization, device: String) -> Resumed? {
    resumed(index: answer.index, position: answer.position, changedBy: answer.changed_by, kept: answer.kept,
            tracks: answer.tracks.map(shuffledTrack), setting: setting, device: device)
}

/// What is put back, from the answer's parts and its songs:
///
///  - Navidrome's list empty: nothing (another app may have cleared it - Navidrome is the authority).
///  - deadwax's own, exact (kept, ids equal, index equal): the whole account from the snapshot at kept.position -
///    or, a snapshot that doesn't read back, the plain list of the same songs at the same index and position.
///  - deadwax's own less songs Navidrome dropped (its ids a subsequence of kept.ids, every copy of a survivor
///    kept): a plain list of what is left, levels carried by entry; the song kept.index's if it survived (at
///    kept.position), else the first survivor after it at 0, else the last survivor at 0.
///  - anyone else's: a plain list at Navidrome's index held into the list - at 0 when it had to be held - at its
///    position.
///  - a song played to its end (within a second of its length): the next entry at 0, or - the queue's last - it at 0.
public func resumed(index said: Int?, position answered: Double, changedBy: String, kept: KeptQueue?,
                    tracks: [QueueTrack], setting: Normalization, device: String) -> Resumed? {
    let n = tracks.count
    if n == 0 { return nil }
    let ids = tracks.map(\.id)
    var keptFrom: PickedFrom?
    if let kept, kept.device != device { keptFrom = .device(kept.label) }
    var queue: UpNextQueue
    var position: Double
    let from: PickedFrom?
    var exact = false
    let present = Set(ids)
    let survivors = kept?.ids.filter { present.contains($0) } ?? []
    if let kept, ids == kept.ids, kept.index == said {
        exact = true
        queue = fromSnapshot(kept.snapshot, tracks: tracks, index: kept.index, setting: setting)
            ?? plainQueue(tracks, kept.index, savedLevels(kept.snapshot, count: n), setting)
        position = kept.position
        from = keptFrom
    } else if let kept, survivors.count < kept.ids.count, survivors == ids {
        let levels = savedLevels(kept.snapshot, count: kept.ids.count).enumerated()
            .filter { present.contains(kept.ids[$0.offset]) }.map(\.element)
        let at = min(max(kept.index, 0), kept.ids.count - 1)
        let before = kept.ids[0..<at].filter { present.contains($0) }.count
        let index: Int
        if present.contains(kept.ids[at]) {
            index = before
            position = kept.position
        } else {
            index = before < n ? before : n - 1
            position = 0
        }
        queue = plainQueue(tracks, index, levels, setting)
        from = keptFrom
    } else {
        let index = said.map { min(max($0, 0), n - 1) } ?? 0
        position = said == index ? answered : 0
        queue = plainQueue(tracks, index, [], setting)
        if let kept, ids == kept.ids {
            from = keptFrom
        } else if !changedBy.isEmpty && changedBy != Resume.deadwaxClient {
            from = .app(changedBy)
        } else {
            from = nil
        }
    }
    if let track = queue.current, track.duration > 0, position >= track.duration - 1 {
        if queue.index + 1 < queue.tracks.count { queue.index += 1 }
        position = 0
    }
    return Resumed(queue: queue, position: max(0, position), from: from, exact: exact)
}

/* ===== the notice ===== */

/// The app's one notice, as a queue is picked up from elsewhere: "Picked up from your Mac" - with logins off, when
/// the queue is everyone's, "Picked up from a Mac" - or "Picked up from Symfonium". Nil for this device's own.
public func pickedUpWords(_ from: PickedFrom?, shared: Bool) -> String? {
    switch from {
    case nil: return nil
    case .app(let name)?: return "Picked up from \(name)"
    case .device(let label)?:
        let vowel = label.utf16.first.map { [0x61, 0x65, 0x69, 0x6F, 0x75].contains($0 | 0x20) } ?? false
        let whose = shared ? (vowel ? "an" : "a") : "your"
        return "Picked up from \(whose) \(label)"
    }
}

/* ===== when it saves ===== */

/// What was last saved, or put back - the baseline a change is measured from.
public struct SaveBaseline: Sendable, Equatable {
    /// the queue's songs and Up Next then: a change of either is a change of the songs or of Up Next
    public var tracks: [QueueTrack]
    public var upNext: UpNextState?
    public var index: Int
    public var position: Double
    /// the window its full save sent: the queue's entries [start, start + count)
    public var start: Int
    public var count: Int

    public init(tracks: [QueueTrack], upNext: UpNextState?, index: Int, position: Double, start: Int, count: Int) {
        self.tracks = tracks
        self.upNext = upNext
        self.index = index
        self.position = position
        self.start = start
        self.count = count
    }
}

/// What saveDue reads. Times are ms on any clock that only goes forward (only differences are read).
public struct SaveClock: Sendable, Equatable {
    public var saved: SaveBaseline?
    /// the last full save's ids_rev - nil while there is none a position save could be made against
    public var idsRev: Int?
    /// the 30 s are counted from here: the last save, or playing starting since - nil for neither
    public var countFrom: Int64?
    /// when the queue last changed - its songs, Up Next or the song
    public var changedAt: Int64?
    /// when a save last failed - nil when the last one didn't
    public var failedAt: Int64?

    public init(saved: SaveBaseline? = nil, idsRev: Int? = nil, countFrom: Int64? = nil, changedAt: Int64? = nil,
                failedAt: Int64? = nil) {
        self.saved = saved
        self.idsRev = idsRev
        self.countFrom = countFrom
        self.changedAt = changedAt
        self.failedAt = failedAt
    }
}

/// What moved since the baseline.
public enum QueueChange: String, Sendable {
    /// the songs, or Up Next
    case songs
    /// the song playing
    case song
    /// the second, by more than 1 s
    case position
}

/// What moved since the baseline - or nothing.
public func changedSince(_ saved: SaveBaseline?, _ queue: UpNextQueue, position: Double) -> QueueChange? {
    guard let saved, queue.tracks == saved.tracks, queue.upNext == saved.upNext else { return .songs }
    if queue.index != saved.index { return .song }
    if abs(position - saved.position) > 1 { return .position }
    return nil
}

/// What started the question: a wait running out, the player's own position report while playing, a pause (or
/// anything else that wants it now), the app going to the background.
public enum SaveTrigger: String, Sendable, Hashable {
    case wait, position, pause, hidden
}

/// Which save: the ids, index, position and snapshot (`full`), or the position only, against the last full save's
/// ids (`at`).
public enum SaveKind: String, Sendable {
    case full, at
}

/// Whether a save is due, and which - nil for none. Nothing for an empty queue, nothing while nothing changed (a
/// queue merely put back is the baseline), nothing for 30 s after a save failed. A change of the songs or of Up
/// Next: in full, RESUME_FULL_WAIT_MS after the last of them. A song change: RESUME_AT_WAIT_MS after. The second
/// alone: while paused, at the wait after it moved (a scrub); while playing, every RESUME_EVERY_S, counted by the
/// player's own position reports. A pause and going to the background: whatever is due, at once. A position save
/// needs an ids_rev and the song inside the window saved; else it is a full one.
public func saveDue(_ clock: SaveClock, _ queue: UpNextQueue, position: Double, playing: Bool, now: Int64,
                    trigger: SaveTrigger) -> SaveKind? {
    guard queue.current != nil else { return nil }
    if let failedAt = clock.failedAt, now - failedAt < Int64(Resume.everySeconds) * 1000 { return nil }
    guard let change = changedSince(clock.saved, queue, position: position) else { return nil }
    let saved = clock.saved
    let at = change != .songs && clock.idsRev != nil && saved != nil
        && queue.index >= saved!.start && queue.index < saved!.start + saved!.count
    let kind: SaveKind = at ? .at : .full
    if trigger == .pause || trigger == .hidden { return kind }
    let since = clock.changedAt.map { now - $0 } ?? .max
    switch change {
    case .songs: return since >= Resume.fullWaitMs ? .full : nil
    case .song: return since >= Resume.atWaitMs ? kind : nil
    case .position:
        if !playing { return trigger == .wait ? kind : nil }
        let counted = clock.countFrom.map { now - $0 >= Int64(Resume.everySeconds) * 1000 } ?? true
        return trigger == .position && counted ? kind : nil
    }
}
