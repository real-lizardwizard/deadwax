import Foundation

// The few rules the app's player wiring (app 0.2: PlayerModel, its LoudnessBook and its level gate) needs that the
// Core's ports didn't hold yet. Each is the phone's own - the web has no engine of its own to decide them for - and
// pure, so Linux tests it (PlayerWiringTests). notes/ios.md, "Phase 1: the player's wiring".

extension Song {
    /// A queue entry as the song the engine plays: what the entry carries and nothing more - its id, its file's
    /// suffix and type (so `isFlac`, `StreamFormat` and the stream cache's name read as the entry's), its album's id
    /// (so an album's entries share one level decision), its length, rate, bits and channels - and Navidrome's `size`
    /// when the app has it (the stream cache's length check), which an entry doesn't carry. Empty words are nil, as
    /// the entry holds "" for what Navidrome left out; a length, rate or bits of 0 is nil. For a queue put back from
    /// deadwax (resume), whose songs the app never fetched (D5), this is the only song there is.
    public init(track: QueueTrack, size: Int64? = nil) {
        func words(_ value: String) -> String? { value.isEmpty ? nil : value }
        func count(_ value: Int) -> Int? { value > 0 ? value : nil }
        self.init(id: track.id, title: words(track.title), album: words(track.album), albumId: track.albumId,
                  artist: words(track.artist), duration: track.duration > 0 ? track.duration : nil, suffix: track.suffix,
                  contentType: track.contentType, size: size, samplingRate: count(track.sampleRate),
                  bitDepth: count(track.bitDepth), channelCount: count(track.channels), coverArt: track.coverArt)
    }
}

extension LoudnessAsking {
    /// The albums the queue needs deadwax's loudness answer for (levels.md 4.2's "wanted", beside an album page that
    /// is open): the album of the entry playing, and of each of the next `wantedAhead` entries with a level - every
    /// one only for an entry that has a level and is a FLAC (Off, and an MP3, need no answer), in the order they play,
    /// once each. Nothing for a queue with nothing playing.
    public static func wanted(_ tracks: [QueueTrack], playing index: Int) -> [String] {
        guard tracks.indices.contains(index) else { return [] }
        var albums: [String] = []
        func want(_ track: QueueTrack) {
            guard track.level != nil, Loudness.isFlac(suffix: track.suffix, contentType: track.contentType),
                  let album = track.albumId, !album.isEmpty, !albums.contains(album) else { return }
            albums.append(album)
        }
        want(tracks[index])
        var ahead = 0
        for track in tracks[(index + 1)...] where track.level != nil {
            guard ahead < wantedAhead else { break }
            ahead += 1
            want(track)
        }
        return albums
    }

    /// What the book keeps once a warm has answered (levels.md 4.2): a warm that says "measuring" of an album the
    /// last read found not measured marks it as being measured - the album, and each of its songs not measured - so
    /// `LevelWait` waits on it from the warm's answer, not from the read 5 s later (until then the book held
    /// "unmeasured", which nothing waits on, and the first play of a never-measured album was fixed as it is: the
    /// levels slice's review). Nil - keep what is there - for any other answer, or an album not read yet (with no
    /// answer at all, LevelWait waits anyway).
    public static func warmed(_ answer: AlbumLoudness?, said: WarmAnswer) -> AlbumLoudness? {
        guard said.state == LoudnessState.measuring.rawValue, let answer, answer.state == .unmeasured else { return nil }
        let songs = answer.songs.map { song in
            song.state == .unmeasured ? SongLoudness(id: song.id, state: .measuring) : song
        }
        return AlbumLoudness(referenceLufs: answer.referenceLufs, algorithm: answer.algorithm, state: .measuring, why: nil,
                             whole: answer.whole, album: answer.album, songs: songs)
    }
}

extension LevelWait {
    /// `shouldWait`, with the phone's own end to it: a read of the album's loudness that FAILED, with no answer in
    /// hand, ends the wait at once - the song plays as it is this time (`.unanswered`: "deadwax didn't say in time")
    /// rather than standing silent for 20 s on a route that isn't answering. The book keeps reading; the album's next
    /// play picks the gain up. With an answer in hand (measuring), a failed read changes nothing.
    public static func shouldWait(level: Level?, song: Song, answer: AlbumLoudness?, waited: Double, readFailed: Bool) -> Bool {
        if answer == nil && readFailed { return false }
        return shouldWait(level: level, song: song, answer: answer, waited: waited)
    }
}

extension PlayerWords {
    /// afterFailure for the phone's engine. Two kinds stop the queue at the song, where the web's afterFailure would
    /// ask again and then skip: a stream deadwax refused with a 401 (`signedOut`, D7 - the app asks /me, and the
    /// sign-in comes up over the app from its answer), and a failure of the phone's own (`other`: its disk or memory,
    /// iOS refusing to start the audio), which every next song would only meet again, skipping through the queue in
    /// moments. Every other kind is afterFailure's.
    public static func afterEngineFailure(_ failure: Failure, intendsToPlay: Bool, retried: Bool) -> AfterFailure {
        switch failure {
        case .signedOut, .other: return .stop
        case .network, .decode, .unsupported: return afterFailure(failure, intendsToPlay: intendsToPlay, retried: retried)
        }
    }
}

extension LevelDecisions {
    /// An edit the engine took (EngineLink.replaceUpcoming answered true): what it kept of what it had scheduled after
    /// the entry heard - the same audio in the same places, from `current + 1` on, as the engine's own walk keeps it -
    /// takes the new list's keys, and each kept entry's decision goes with it (`carry(from:to:)`). The walk stops at
    /// the first place whose audio differs, or where either list ends.
    public mutating func carry(from old: [QueueEntry], to new: [QueueEntry], after current: Int) {
        var place = current + 1
        while place >= 0, place < old.count, place < new.count, old[place].audio == new[place].audio {
            carry(from: old[place].key, to: new[place].key)
            place += 1
        }
    }
}
