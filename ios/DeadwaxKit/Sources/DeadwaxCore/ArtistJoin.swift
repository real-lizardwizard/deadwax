import Foundation

// The library's artist page with the albums of theirs you don't have (15 Nov - James: "also on the artists page I'd like
// to also see albums I don't have yet"). The web's ArtistPage.tsx lists an artist's albums as lib/artistPage.ts's
// artistRows makes them: MusicBrainz's discography with what you hold of each, and every album you have of theirs that
// MusicBrainz's list doesn't claim. The phone keeps your albums' rows as they were (ArtistPage.rows: Navidrome's title,
// year and line, one row per album, drawn without waiting for MusicBrainz) and adds among them, in the web's order, each
// of MusicBrainz's albums that no album of yours claims, as a MusicBrainz artist's page draws it (MBArtistPage.Row).
// Which of MusicBrainz's albums yours claim is artistRows' own rule; who the artist is on MusicBrainz is artistMbid. Both
// are held to the web by Fixtures/artists/artist-vectors.json's `joined` and `mbids` (ios/scripts/export-artist-vectors.cjs).

/// An artist's page in the library, joined with their discography (ArtistPage.tsx's rows, notes/ios.md "The artist's
/// albums you don't have").
public enum ArtistJoin {
    /// One row of the page: an album of theirs you have (Phase 4's row, unchanged), or one of MusicBrainz's albums none of
    /// yours claims.
    public enum Row: Sendable, Equatable, Identifiable {
        case yours(ArtistPage.Row)
        case theirs(MBArtistPage.Row)

        /// `album:<id>` for yours, `group:<id>` for theirs - never the same, and stable as answers land.
        public var id: String { key }

        public var key: String {
            switch self {
            case .yours(let row): return row.key
            case .theirs(let row): return row.key
            }
        }

        var title: String {
            switch self {
            case .yours(let row): return row.title
            case .theirs(let row): return row.title
            }
        }

        var year: String? {
            switch self {
            case .yours(let row): return row.year
            case .theirs(let row): return row.year
            }
        }
    }

    // MARK: who they are on MusicBrainz

    /// `artistMbid`: the artist's MusicBrainz id - Navidrome's own `musicBrainzId` for them, else what the library's
    /// folders of the albums Navidrome has of theirs say they are by (a folder of one of those albums' releases, or -
    /// with no album of theirs carrying a release id - a folder filed under their name), only when every folder that
    /// says agrees, and only a single artist's id (a collaboration's ids say who else, not who this is). Nil otherwise,
    /// and while the artist hasn't answered: then there is no discography, rather than a guess.
    public static func mbid(_ artist: ArtistWithAlbums?, index: OwnedIndex?) -> String? {
        guard let artist else { return nil }
        if let own = MBID.of(artist.musicBrainzId) { return own }
        let releases = Set(artist.album.compactMap { (album: Album) -> FoldKey? in MBID.of(album.musicBrainzId).map(FoldKey.init) })
        let name = FoldKey(Fold.key(artist.name))
        var says: [String] = []
        for album in everyOwned(index) {
            let release = album.releaseMbid ?? ""
            //? `release_mbid.toLowerCase()` - lowercased, not trimmed, as the web has it
            let byRelease = !release.isEmpty && releases.contains(FoldKey(JSText.lowercase(release)))
            let byName = releases.isEmpty && !name.units.isEmpty && FoldKey(Fold.key(album.artist)) == name
            guard byRelease || byName, let id = soleArtist(album), !says.contains(id) else { continue }
            says.append(id)
        }
        return says.count == 1 ? says[0] : nil
    }

    /// Every folder the index holds (`everyOwned`) - a folder in two of its maps more than once, which no rule here
    /// counts twice.
    static func everyOwned(_ index: OwnedIndex?) -> [OwnedAlbum] {
        guard let index else { return [] }
        return [index.byRelease, index.byGroup, index.byName].flatMap { (map: [FoldKey: [OwnedAlbum]]) -> [OwnedAlbum] in
            map.values.flatMap { $0 }
        }
    }

    /// The one artist a folder is by, as its MusicBrainz ids say - nil for none, or a collaboration (`soleArtist`).
    static func soleArtist(_ album: OwnedAlbum) -> String? {
        let ids = (album.albumartistMbids ?? []).compactMap { MBID.of($0) }
        return ids.count == 1 ? ids[0] : nil
    }

    // MARK: which of MusicBrainz's albums are yours

    /// The groups an album of yours claims (artistRows' own claim, group by group in MusicBrainz's order, each once):
    /// one whose folders' releases are an album Navidrome has of theirs, none claimed yet; and - only a group no other
    /// in the list shares its folded title with - an album of that exact title that no folder ties to a group of its own
    /// (no release id, or a folder carrying no group id).
    static func claimed(_ albums: [Album], _ groups: [ReleaseGroup], index: OwnedIndex?) -> Set<FoldKey> {
        var byRelease: [FoldKey: Album] = [:]
        for album in albums {
            guard let release = MBID.of(album.musicBrainzId), byRelease[FoldKey(release)] == nil else { continue }
            byRelease[FoldKey(release)] = album
        }
        //? every group as given counts - a group listed twice shares its title with itself
        var titles: [FoldKey: Int] = [:]
        for group in groups { titles[FoldKey(Fold.key(group.title)), default: 0] += 1 }
        var albumsClaimed = Set<FoldKey>()
        var groupsClaimed = Set<FoldKey>()
        var seen = Set<FoldKey>()
        for group in groups {
            let id = FoldKey(group.id)
            guard !group.id.isEmpty, seen.insert(id).inserted else { continue }
            let holding = SearchAlbums.heldInOrder(OwnedIndex.forGroup(index, groupId: group.id).held)
            let releases = WebText.unique(holding.compactMap { MBID.of($0.releaseMbid) })
            var mine = Set(releases.compactMap { byRelease[FoldKey($0)].map { FoldKey($0.id) } }.filter { !albumsClaimed.contains($0) })
            let title = FoldKey(Fold.key(group.title))
            if !title.units.isEmpty, titles[title] == 1 {
                for album in albums where !albumsClaimed.contains(FoldKey(album.id))
                    && FoldKey(Fold.key(album.name)) == title && !knownGroup(index, album.musicBrainzId) {
                    mine.insert(FoldKey(album.id))
                }
            }
            albumsClaimed.formUnion(mine)
            if !mine.isEmpty { groupsClaimed.insert(id) }
        }
        return groupsClaimed
    }

    /// Whether the library's folders of a release say which group it is (`knownGroup`) - false for no release id.
    static func knownGroup(_ index: OwnedIndex?, _ release: String?) -> Bool {
        guard let id = MBID.of(release) else { return false }
        return OwnedIndex.forRelease(index, id).contains { !($0.releaseGroupMbid ?? "").isEmpty }
    }

    /// Their albums MusicBrainz lists that no album of yours claims, as a MusicBrainz artist's page has them
    /// (MBArtistPage.rows, in its order): what the library holds of each by its folders - one held only by the store's
    /// word (Navidrome hasn't found it, or files it under another artist) is ticked and opens through the id bridge.
    public static func theirs(albums: [Album], groups: [ReleaseGroup], index: OwnedIndex?) -> [MBArtistPage.Row] {
        let claimed = claimed(albums, groups, index: index)
        return MBArtistPage.rows(groups, index: index).filter { !claimed.contains(FoldKey($0.group.id)) }
    }

    // MARK: the page's rows

    /// The page's rows: your albums as ArtistPage.rows makes them, in that order whatever lands - and, once MusicBrainz
    /// has answered (`groups`), theirs merged in among them by the web's order: the newest year first, the undated last,
    /// then by folded title, then by key. Your albums never wait for MusicBrainz, and never move among themselves as its
    /// answer lands: its rows come in between. `groups` nil: MusicBrainz hasn't answered, can't, or doesn't know who this
    /// is - your albums alone.
    public static func rows(albums: [Album], groups: [ReleaseGroup]?, index: OwnedIndex?) -> [Row] {
        let yours = ArtistPage.rows(albums).map { Row.yours($0) }
        guard let groups else { return yours }
        let theirs = theirs(albums: albums, groups: groups, index: index).map { Row.theirs($0) }
        var merged: [Row] = []
        merged.reserveCapacity(yours.count + theirs.count)
        var (mine, other) = (0, 0)
        while mine < yours.count && other < theirs.count {
            if before(theirs[other], yours[mine]) {
                merged.append(theirs[other])
                other += 1
            } else {
                merged.append(yours[mine])
                mine += 1
            }
        }
        merged.append(contentsOf: yours[mine...])
        merged.append(contentsOf: theirs[other...])
        return merged
    }

    /// artistRows' order: the undated last, the newest year first (as words, as the web compares them), then the folded
    /// titles and then the keys in localeCompare's order (WebCollation).
    static func before(_ a: Row, _ b: Row) -> Bool {
        switch (a.year, b.year) {
        case (nil, .some): return false
        case (.some, nil): return true
        case let (.some(first), .some(second)) where first != second:
            return FoldKey(second) < FoldKey(first)
        default: break
        }
        let title = SongSearch.collate(Fold.key(a.title), Fold.key(b.title))
        if title != 0 { return title < 0 }
        return WebCollation.compare(a.key, b.key) < 0
    }

    /// What Play and Shuffle play: your albums alone, in the page's order (`playOrder` - the rows MusicBrainz adds have
    /// nothing to play), the same as ArtistPage.playOrder over your rows.
    public static func playOrder(_ rows: [Row]) -> [String] {
        ArtistPage.playOrder(rows.compactMap { (row: Row) -> ArtistPage.Row? in
            if case .yours(let mine) = row { return mine }
            return nil
        })
    }

    /// Whether MusicBrainz's rows are drawn: online (offline the page is your albums alone, and nothing is asked), and
    /// once `/library/owned` has answered or the page has waited `SearchPacing.ownedWaitMs` for it - so an album of
    /// yours only the library's folders tie to MusicBrainz's is never drawn as one you don't have and then taken away.
    public static func drawsTheirs(online: Bool, indexKnown: Bool, waited: Bool) -> Bool {
        online && (indexKnown || waited)
    }

    /// What the page says under the rows of MusicBrainz's part, once (the web's foot of its albums, a MusicBrainz artist's
    /// page's words): asking, and the moment its rows wait for the library (`holding`) - "Loading their albums…"; its
    /// trouble, with Try again; the cut at 500; with no row at all, that there are none (Studio only's way out); else
    /// nothing.
    public enum Foot: Sendable, Equatable {
        case loading, trouble, truncated, noAlbums, nothing
    }

    /// `answered`: an answer for the question asked now is in hand; `failed`: the last ask failed; `rows`: every row the
    /// page draws, yours among them.
    public static func foot(asking: Bool, answered: Bool, failed: Bool, truncated: Bool, holding: Bool, rows: Int) -> Foot {
        if asking { return .loading }
        if failed { return .trouble }
        if !answered || holding { return .loading }
        if truncated { return .truncated }
        return rows == 0 ? .noAlbums : .nothing
    }
}
