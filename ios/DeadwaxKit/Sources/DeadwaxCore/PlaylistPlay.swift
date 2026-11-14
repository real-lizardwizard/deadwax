import Foundation

/// Playing a playlist (Phase 4, phase4-library.md 2.3) - PlaylistPage.tsx's `tracks`, `albums` and `remembered`, with
/// lib/playlists.ts's playlistAlbums, withHeld and stubFor ported (held to the fixture) - as rules the app carries out
/// in the tap, nothing awaited first.
///
/// Each song is queued with its OWN album (the web's `toQueueTrack(song, stubFor(song))`): a playlist is not an album,
/// so nothing of one song fills another's gaps, and a song with no album id names none. They are queued at the songs
/// level (`queued(tracks, 'songs')`): under Normalization's Auto, each at its own track level. The albums Info and Go
/// to album know are stubs made from the songs (`albums`), an album's own answer held already kept over its stub
/// (`withHeld`) - remembered all at once (PlayedAlbums.rememberQueue).
public enum PlaylistPlay {
    /// stubFor: the album a song's gaps are filled from - its own, by id and name (every playlist entry carries its
    /// own cover and format, so nothing else is wanted).
    public static func stub(for song: Song) -> Album {
        Album(id: song.albumId ?? "", name: song.album ?? "")
    }

    /// One song as the queue takes it: its own album, cover and format - and no album id (nil) for a song that has
    /// none, as the web's `song.albumId ? track : { ...track, albumId: null }`.
    public static func track(_ song: Song, level: Level?) -> QueueTrack {
        let album = stub(for: song)
        var track = QueueTrack(song: song, albumId: album.id, albumName: album.name ?? "", albumArtist: album.artist,
                               albumCoverArt: album.coverArt, level: level)
        if (song.albumId ?? "").isEmpty { track.albumId = nil }
        return track
    }

    /// The playlist's songs as queue tracks, each at `level` - the songs level (`songsLevel(_:)`) for Play, Shuffle and
    /// a row's tap.
    public static func tracks(_ songs: [Song], level: Level?) -> [QueueTrack] {
        songs.map { track($0, level: level) }
    }

    /// The level a playlist's Play, Shuffle and a row's tap queue at: as songs (PlaylistPage.tsx `queued(tracks,
    /// 'songs')`) - each at its own track level under Auto, none with Off.
    public static func songsLevel(_ setting: Normalization) -> Level? {
        levelFor(setting, .songs)
    }

    /// playlistAlbums: one stub per album, in the order its first song appears, holding its songs in playlist order,
    /// `partial` - its songs only the playlist's, so Info counts none of the album's from it. No MusicBrainz id. A song
    /// with no album id gets none. The artist is the song's album artist, else its own; the cover and year the first
    /// song's (none for "" or 0, as JavaScript's truthiness reads them).
    public static func albums(_ songs: [Song]) -> [Album] {
        var order: [String] = []
        var stubs: [String: Album] = [:]
        var songsOf: [String: [Song]] = [:]
        for song in songs {
            guard let id = song.albumId, !id.isEmpty else { continue }
            if stubs[id] == nil {
                let artist = present(song.displayAlbumArtist) ?? present(song.artist)
                stubs[id] = Album(id: id, name: song.album ?? "", artist: artist, coverArt: present(song.coverArt),
                                  year: song.year.flatMap { $0 != 0 ? $0 : nil }, partial: true)
                order.append(id)
            }
            songsOf[id, default: []].append(song)
        }
        return order.compactMap { (id: String) -> Album? in
            guard let stub = stubs[id] else { return nil }
            return with(stub, songs: songsOf[id] ?? [])
        }
    }

    /// withHeld: what is remembered for a playlist's albums at the tap - the album's OWN answer where one is held already
    /// (`held`, PlayerModel's played albums: an album page's, every song, its disc titles and label) - a stub never put
    /// over it; else the stub, with the songs of an earlier playlist's stub of it kept beside the new ones (a song of it
    /// playing from that one still found).
    public static func withHeld(_ stubs: [Album], held: (String) -> Album?) -> [Album] {
        stubs.map { (stub: Album) -> Album in
            guard let have = held(stub.id) else { return stub }
            if !have.partial { return have }
            let fresh = Set((stub.song ?? []).map(\.id))
            return with(stub, songs: (have.song ?? []).filter { !fresh.contains($0.id) } + (stub.song ?? []))
        }
    }

    /// Play, Shuffle and a row's tap from a playlist's page: the tracks at the songs level, and the albums to
    /// remember (withHeld over the stubs).
    public static func plan(_ songs: [Song], setting: Normalization, held: (String) -> Album?)
        -> (tracks: [QueueTrack], albums: [Album]) {
        (tracks(songs, level: songsLevel(setting)), withHeld(albums(songs), held: held))
    }

    /// The bar's ••• - the whole playlist, queued as songs (no `queuedAs`), its albums remembered as just added.
    public static func pick(name: String, songs: [Song]) -> QueuePick<Song>? {
        guard !songs.isEmpty else { return nil }
        return QueuePick(label: name, tracks: songs, albumIds: albumIds(songs))
    }

    /// A row's ••• - the one song, queued as a song, with its own album.
    public static func pick(song: Song) -> QueuePick<Song> {
        QueuePick(label: song.title ?? "", tracks: [song], albumIds: albumIds([song]))
    }

    /// The songs' albums, each once, in the order they first appear - none for a song with no album id.
    static func albumIds(_ songs: [Song]) -> [String] {
        var seen = Set<String>()
        return songs.compactMap { (song: Song) -> String? in
            guard let id = song.albumId, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    /// `value` as JavaScript's `value ? ... : ...` keeps it: nil for none or "".
    private static func present(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// The album with `songs` in place of its own.
    static func with(_ album: Album, songs: [Song]) -> Album {
        Album(id: album.id, name: album.name, artist: album.artist, artistId: album.artistId, coverArt: album.coverArt,
              songCount: album.songCount, duration: album.duration, year: album.year, genre: album.genre,
              musicBrainzId: album.musicBrainzId, starred: album.starred, created: album.created, played: album.played,
              playCount: album.playCount, song: songs, discTitles: album.discTitles, recordLabels: album.recordLabels,
              partial: album.partial)
    }
}
