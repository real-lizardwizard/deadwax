// The player's display (the Mac and iPhone redesign, slice R4 - notes/ios.md "The redesign, slice R4: the player bar,
// the mini player and the tab bar"): what the Mac's player bar draws in its lcd beside the song - "Next" and the song
// that then plays, "3 of 11", the format ("FLAC 16/44.1") - from the queue and the song in hand, with nothing asked of
// deadwax or Navidrome. Pure, so every rule is held here, on Linux; R4b's Now Playing reads the same.

/// The player bar's display: the song after this one, its place in its list, and its format.
public enum BarDisplay {
    /// "3 of 11": the song playing's place in the list it is from, this time round.
    public struct Place: Sendable, Equatable {
        public let number: Int
        public let of: Int

        public init(number: Int, of: Int) {
            self.number = number
            self.of = of
        }
    }

    // MARK: Next

    /// The song that plays when this one ends, as the queue stands - nil for none: the queue's next entry (UpNext's
    /// `nextIndex`, the engine's own step: so under Shuffle the shuffled order's next, and a song added with Play Next
    /// first). At the queue's end nothing with Repeat off; with Repeat All the list's first song, which toppedUp puts
    /// there when the song ends (the list's own order - a shuffled round isn't drawn until then, so nothing is named
    /// for it but a list of one song). Repeat One plays this song again: nothing is named. A library's shuffle is
    /// topped up by its feed, never here: nothing past what is queued.
    public static func next(_ queue: UpNextQueue, repeat mode: Repeat) -> QueueTrack? {
        guard mode != .one, queue.current != nil else { return nil }
        if let index = nextIndex(queue) {
            //? Repeat One's copy (Repeat just turned off, the queue not yet let go of it): this song again
            if let mark = queue.upNext.flatMap({ markAt($0.marks, index) }), mark.from == .one { return nil }
            return queue.tracks[index]
        }
        guard mode == .all, let state = queue.upNext, state.paged == nil, let first = state.source.first else {
            return nil
        }
        return !state.shuffle || state.source.count == 1 ? first : nil
    }

    // MARK: 3 of 11

    /// The song playing's place in its list this time round, and how many songs the round has: the round's songs less
    /// those taken out of it (`left`) - a library's shuffle's its whole order (Paged's total). So an album from its
    /// third song is "3 of 11", as Shuffle's third song is; Repeat All's second time round counts afresh; a Repeat One
    /// copy is its song's place. Nil for nothing playing, a song added (Play Next, Play Last: not one of the list's), or
    /// a place the queue can't know - never a wrong one.
    ///
    /// A reload (Resume) brings back a WINDOW of the queue: at most `Resume.before` entries before the song playing and
    /// `Resume.maxEntries` in all (windowOf), so a queue can come back without its front, its end or both. The list
    /// itself is kept whole, and so is `left` - but a library's shuffle keeps only the window's songs, and no `left`
    /// (Resume's savedList). So:
    /// - **In the list's own order** (Shuffle off, not a library's shuffle) the place is the song's among the list's
    ///   songs not taken out - its index in the list less those taken out before it - which holds however much of the
    ///   queue came back: a 2,100-song playlist reloaded is still "1 of 2,100".
    /// - **Shuffled, or a library's shuffle**, it is counted back from the round's songs still to come - only while the
    ///   queue holds every song the round has had (a library's shuffle: has fetched), or has them in `left`. A reload
    ///   that trimmed the round's front or cut its end can't be told apart, and a library's shuffle's `left` is gone:
    ///   nil then, until a round the queue holds whole.
    public static func place(_ queue: UpNextQueue) -> Place? {
        guard queue.current != nil, let state = queue.upNext, state.marks.count == queue.tracks.count else { return nil }
        let song = unitStart(state, queue.index)
        guard let mark = markAt(state.marks, song), mark.from == .source else { return nil }
        let round = mark.pass
        let taken = Set(state.left.filter { $0.pass == round }.map(\.at))
        if state.paged == nil && !state.shuffle {
            let list = state.source.indices
            guard list.contains(mark.at), !taken.contains(mark.at) else { return nil }
            let out = taken.filter { list.contains($0) }
            let before = mark.at - out.filter { $0 < mark.at }.count
            return Place(number: before + 1, of: state.source.count - out.count)
        }
        // the round: its whole order, and how many of it there have been to hold
        let size: Int
        let had: Int
        if let paged = state.paged {
            let last = lastSourceAt(state.marks, state.marks.count - 1)
            let lastRound = last < 0 ? -1 : state.marks[last].pass
            if round == lastRound {
                size = paged.total
                had = paged.fetched
            } else if let earlier = state.pagedRounds?.first(where: { $0.pass == round }) {
                size = earlier.paged.total
                had = earlier.paged.fetched
            } else {
                return nil
            }
        } else {
            size = state.source.count
            had = size
        }
        var held = taken
        var after = 0
        let end = unitEnd(state, song)
        for (place, later) in state.marks.enumerated() where later.from == .source && later.pass == round {
            held.insert(later.at)
            if place >= end { after += 1 }
        }
        //? a song the round has had that the queue neither holds nor took out: a reload's window left it behind -
        //? played or still to come, nobody can say
        guard held.count == had else { return nil }
        let of = size - taken.count
        let number = had - taken.count - after
        guard of > 0, number >= 1, number <= of else { return nil }
        return Place(number: number, of: of)
    }

    // MARK: the format

    /// The song's format as the song in hand says it (Navidrome's, read from the file): "FLAC 16/44.1" for a lossless
    /// file with its depth and rate, "FLAC 16-bit" or "FLAC 44.1 kHz" with one, "FLAC" with neither; a lossy file's
    /// format alone ("MP3") - its depth isn't one (a tag reader says 16 for an AAC), and the song carries no bitrate.
    /// An MP4 is ALAC only when its type says so (AlbumInfo weighs an album's bitrates; one song can't): else its
    /// suffix. Nil when nothing names a format.
    public static func format(_ track: QueueTrack) -> String? {
        guard let (format, bits, rate) = facts(track) else { return nil }
        if !bits.isEmpty && !rate.isEmpty { return "\(format) \(bits)/\(rate)" }
        if !bits.isEmpty { return "\(format) \(bits)-bit" }
        if !rate.isEmpty { return "\(format) \(rate) kHz" }
        return format
    }

    /// The format to VoiceOver: "FLAC, 16-bit, 44.1 kHz" - never "16 slash 44.1".
    public static func formatSpoken(_ track: QueueTrack) -> String? {
        guard let (format, bits, rate) = facts(track) else { return nil }
        return [format, bits.isEmpty ? "" : "\(bits)-bit", rate.isEmpty ? "" : "\(rate) kHz"]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The format's name, and for a lossless file its depth and its rate in kHz ("16", "44.1"; "" for one not known).
    private static func facts(_ track: QueueTrack) -> (String, String, String)? {
        let named = LevelWords.kindOf(FileFacts(suffix: WebText.trim(track.suffix ?? ""), contentType: track.contentType))
        guard !named.isEmpty else { return nil }
        let type = (track.contentType ?? "").lowercased()
        let format = AlbumInfo.mp4.contains(named.lowercased()) && type.contains("alac") ? "ALAC" : named
        guard Sources.losslessFormats.contains(format.lowercased()) else { return (format, "", "") }
        let bits = track.bitDepth > 0 ? WebText.number(Double(track.bitDepth)) : ""
        let rate = track.sampleRate > 0 ? Sources.trimRate(Double(track.sampleRate) / 1000) : ""
        return (format, bits, rate)
    }

    // MARK: the words

    public enum Words {
        /// The label before the song after this one.
        public static let next = "Next"
        /// "3 of 11" (thousands grouped: "3 of 1,612").
        public static func place(_ place: Place) -> String {
            "\(UpNextWords.grouped(place.number)) of \(UpNextWords.grouped(place.of))"
        }
        /// "Next: Bull Black Nova", VoiceOver's.
        public static func nextSpoken(_ title: String) -> String { "\(next): \(title)" }
    }

    /// The display's readout: "3 of 11 · FLAC 16/44.1" - either alone when the other isn't known; nil with neither.
    public static func readout(_ queue: UpNextQueue) -> String? {
        let parts = [place(queue).map(Words.place), queue.current.flatMap(format)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: DiscHeadings.dot)
    }

    /// The readout to VoiceOver: "3 of 11, FLAC, 16-bit, 44.1 kHz".
    public static func readoutSpoken(_ queue: UpNextQueue) -> String? {
        let parts = [place(queue).map(Words.place), queue.current.flatMap(formatSpoken)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
