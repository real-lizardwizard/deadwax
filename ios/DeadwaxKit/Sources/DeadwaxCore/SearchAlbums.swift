import Foundation

// MusicBrainz's albums in Search (Phase 5, slice 2 - notes/ios-specs/phase5-search.md 2.3, 6.2): the web's
// ui/src/lib/searchResults.ts (a group's year, kind and place, which of them the library holds), searchList.ts
// (heldUnlisted, groupYours, groupMaybe, studioOrder, allAlbumsQuery), idBridge.ts (heldReleases, heldInOrder: which
// pressing you hold a held album opens) and artistPage.ts (libraryArtistFor, everyOwned: the library's artist a
// MusicBrainz credit is). Held to the web by Fixtures/search/search-albums-vectors.json.

public enum SearchAlbums {
    /// How many albums MusicBrainz is asked for (Search.tsx `MUSICBRAINZ_LIMIT`): a screenful, with room for the ones
    /// you hold.
    public static let limit = 12

    /// The year an album first came out, or nil (`groupYear`).
    public static func year(_ group: ReleaseGroup) -> String? {
        let year = WebText.prefix(group.firstReleaseDate ?? "", 4)
        return WebText.fourDigits(year) ? year : nil
    }

    /// What an album is, in a word or two (`groupKind`): a secondary type says more than the primary one - "Live
    /// album", "Compilation" - else the primary type, else "Release".
    public static func kind(_ group: ReleaseGroup) -> String {
        let primary = group.primaryType ?? ""
        let base = primary.isEmpty ? "Album" : primary
        for secondary in group.secondaryTypes ?? [] {
            switch JSText.lowercase(secondary) {
            case "live": return "Live \(JSText.lowercase(base))"
            case "compilation": return "Compilation"
            case "soundtrack": return "Soundtrack"
            case "remix": return "Remix \(JSText.lowercase(base))"
            case "demo": return "Demo"
            case "dj-mix": return "DJ mix"
            case "mixtape/street": return "Mixtape"
            case "interview": return "Interview"
            case "audiobook": return "Audiobook"
            case "spokenword": return "Spoken word"
            default: continue
            }
        }
        return primary.isEmpty ? "Release" : primary
    }

    /// A group's kind word in a section, said only when it isn't a plain album (`groupWord`).
    public static func word(_ group: ReleaseGroup) -> String {
        let kind = self.kind(group)
        return kind == "Album" ? "" : kind
    }

    /// Whether the library holds the album by an id (`groupHeld`).
    public static func held(_ index: OwnedIndex?, _ groupId: String) -> Bool {
        guard let index else { return false }
        return !OwnedIndex.forGroup(index, groupId: groupId).held.isEmpty
    }

    /// Where a held album is (`groupPlace`): "in your library", or with a library of your own and none of it yours,
    /// "in the collection".
    public static func place(_ index: OwnedIndex?, _ groupId: String, personal: Bool) -> String {
        guard let index else { return Whose.inYourLibrary }
        let held = OwnedIndex.forGroup(index, groupId: groupId).held
        return Whose.heldPhrase(personal: personal, yours: held.contains { $0.yours != false })
    }

    /// Whose a held album is (`groupYours`): a folder of it yours.
    public static func yours(_ group: ReleaseGroup, _ marks: SearchMarks) -> Bool {
        if !marks.personal { return true }
        return OwnedIndex.forGroup(marks.index, groupId: group.id).held.contains { $0.yours != false }
    }

    /// An album no folder holds by its ids that a folder may be by its name alone (`groupMaybe`): "maybe in your
    /// library" / "maybe in the collection" - "" otherwise.
    public static func maybe(_ group: ReleaseGroup, _ marks: SearchMarks) -> String {
        guard let index = marks.index, !held(index, group.id) else { return "" }
        let guessed = OwnedIndex.forGroup(index, groupId: group.id, title: group.title ?? "",
                                          artists: [Credits.name(group.artistCredit), Credits.current(group.artistCredit)]).guessed
        guard !guessed.isEmpty else { return "" }
        return "maybe \(Whose.heldPhrase(personal: marks.personal, yours: guessed.contains { $0.yours != false }))"
    }

    /// The albums the library doesn't hold (`notInLibrary`) - all of them before it has answered.
    public static func notInLibrary(_ groups: [ReleaseGroup], _ index: OwnedIndex?) -> [ReleaseGroup] {
        guard let index else { return groups }
        return groups.filter { !held(index, $0.id) }
    }

    /// The albums MusicBrainz found that the library holds but search3 didn't list (`heldUnlisted`): brought into
    /// their holder's block, so a held album never shows nowhere.
    public static func heldUnlisted(_ groups: [ReleaseGroup], _ index: OwnedIndex?, _ libraryAlbums: [Album]) -> [ReleaseGroup] {
        guard let index else { return [] }
        let shown = Set(notInLibrary(groups, index).map(\.id))
        let listed = Set(libraryAlbums.map { JSText.lowercase(JSText.trim($0.musicBrainzId ?? "")) }.filter { !$0.isEmpty })
        return groups.filter { (group: ReleaseGroup) -> Bool in
            !shown.contains(group.id) && !heldReleases(index, group.id).contains { listed.contains($0) }
        }
    }

    /// The studio clause's answer in the order an artist's albums are read (`studioOrder`): Album before EP, no
    /// secondary type first, the earliest first - MusicBrainz's order breaking ties.
    public static func studioOrder(_ groups: [ReleaseGroup]) -> [ReleaseGroup] {
        func primary(_ group: ReleaseGroup) -> Int {
            let type = JSText.lowercase(group.primaryType ?? "")
            return type == "album" ? 0 : type == "ep" ? 1 : 2
        }
        func secondary(_ group: ReleaseGroup) -> Int { (group.secondaryTypes ?? []).isEmpty ? 0 : 1 }
        func date(_ group: ReleaseGroup) -> [UInt16] { Array(((group.firstReleaseDate ?? "") + "~").utf16) }
        return groups.enumerated().sorted { (a: (offset: Int, element: ReleaseGroup), b: (offset: Int, element: ReleaseGroup)) -> Bool in
            if primary(a.element) != primary(b.element) { return primary(a.element) < primary(b.element) }
            if secondary(a.element) != secondary(b.element) { return secondary(a.element) < secondary(b.element) }
            let (x, y) = (date(a.element), date(b.element))
            if x != y { return x.lexicographicallyPrecedes(y) }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// What the All view's Albums asks MusicBrainz (`allAlbumsQuery`): an artist you have alone is their studio albums
    /// and EPs (never Various Artists); anything else as read. `studio`: the studio clause is on, and named on screen.
    public static func allAlbumsQuery(_ plan: SearchPlan) -> (query: String, studio: Bool) {
        guard plan.kind == .artist, let artist = plan.artist, !artist.isEmpty,
              !WebText.same(artist, SearchReading.variousArtists) else { return (plan.query, false) }
        let filter = SearchReading.typeFilter(primary: ["Album", "EP"], studioOnly: true)
        return (SearchReading.withTypeFilter("artist:\(SearchReading.quoteTerm(artist))", filter), true)
    }

    // MARK: which pressing a held album opens (idBridge.ts)

    /// A folder's edition says it is the plain one (`plainEdition`): none, or "Standard".
    public static func plainEdition(_ edition: String?) -> Bool {
        let label = JSText.lowercase(JSText.trim(edition ?? ""))
        return label.isEmpty || label == "standard"
    }

    /// The copies of an album the library holds, in the order every screen opens one (`heldInOrder`): the plain
    /// edition first, then the oldest (no year last), then by folder.
    public static func heldInOrder(_ albums: [OwnedAlbum]) -> [OwnedAlbum] {
        func yearOf(_ year: String?) -> String {
            let found = WebText.prefix(JSText.trim(year ?? ""), 4)
            return WebText.fourDigits(found) ? found : ""
        }
        return albums.enumerated().sorted { (a: (offset: Int, element: OwnedAlbum), b: (offset: Int, element: OwnedAlbum)) -> Bool in
            let plain = (plainEdition(a.element.edition) ? 0 : 1) - (plainEdition(b.element.edition) ? 0 : 1)
            if plain != 0 { return plain < 0 }
            let (ya, yb) = (yearOf(a.element.year), yearOf(b.element.year))
            let dated = (ya.isEmpty ? 1 : 0) - (yb.isEmpty ? 1 : 0)
            if dated != 0 { return dated < 0 }
            if ya != yb { return ya < yb }
            //? localeCompare: ICU's collation, as ArtistPage collates ASCII keys - a path's non-ASCII aside
            let path = ArtistPage.asciiCollate(a.element.path, b.element.path)
            if path != 0 { return path < 0 }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The releases of an album the library holds, by its group id, in heldInOrder's order (`heldReleases`) - what the
    /// id bridge is asked about, the first Navidrome has opening.
    public static func heldReleases(_ index: OwnedIndex?, _ groupId: String?) -> [String] {
        guard let groupId, !groupId.isEmpty else { return [] }
        let ids = heldInOrder(OwnedIndex.forGroup(index, groupId: groupId).held)
            .map { JSText.lowercase(JSText.trim($0.releaseMbid ?? "")) }
        return WebText.unique(ids.filter { !$0.isEmpty })
    }

    // MARK: the library's artist a credit is (artistPage.ts)

    /// Every folder the index holds, each once by its path (`everyOwned`).
    public static func everyOwned(_ index: OwnedIndex?) -> [OwnedAlbum] {
        guard let index else { return [] }
        var seen = Set<[UInt16]>()
        var out: [OwnedAlbum] = []
        for map in [index.byRelease, index.byGroup, index.byName] {
            for albums in map.values {
                for album in albums where seen.insert(Array(album.path.utf16)).inserted { out.append(album) }
            }
        }
        return out
    }

    /// The one artist a folder is by, as its MusicBrainz ids say - nil for none, or a collaboration.
    static func soleArtist(_ album: OwnedAlbum) -> String? {
        let ids = (album.albumartistMbids ?? []).compactMap { MBID.of($0) }
        return ids.count == 1 ? ids[0] : nil
    }

    /// The library's artist for a MusicBrainz artist (`libraryArtistFor`): the one carrying the id; else, among those
    /// carrying none, the one named as the folders by them are filed - else as `name` - when exactly one answers.
    public static func libraryArtist(_ artists: [Artist], mbid: String?, index: OwnedIndex?, name: String?) -> Artist? {
        guard let id = MBID.of(mbid) else { return nil }
        let carrying = artists.filter { MBID.of($0.musicBrainzId) == id }
        if !carrying.isEmpty { return carrying.count == 1 ? carrying[0] : nil }
        func one(_ names: Set<FoldKey>) -> Artist? {
            if names.isEmpty { return nil }
            let found = artists.filter { names.contains(FoldKey(Fold.key($0.name))) && MBID.of($0.musicBrainzId) == nil }
            return found.count == 1 ? found[0] : nil
        }
        let filedUnder = Set(everyOwned(index).filter { soleArtist($0) == id }.map { Fold.key($0.artist) }
            .filter { !$0.isEmpty }.map(FoldKey.init))
        if !filedUnder.isEmpty { return one(filedUnder) }
        let named = Fold.key(name)
        return named.isEmpty ? nil : one([FoldKey(named)])
    }
}
