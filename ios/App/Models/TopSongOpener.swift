import DeadwaxCore
import Foundation
import Observation

/// A top song you don't have, opened (lastfm.md 3.2; notes/ios.md "Last.fm, slice A1"): its row spins while
/// MusicBrainz's song search is asked for it (`TopSongs.searchQuery`: its title as keyed, and the page's artist, read with
/// `SongSearch.group`), and the album Core's TopSongs.album picks opens as the album you don't have, the song marked -
/// or the row says why not for the visit (LastfmWords.notFound, MusicBrainz away, ErrorWords for anything else).
///
/// As a MusicBrainz artist's row's id bridge (MBArtistModel.open): an answer opens only where it was tapped - the same
/// tab, the same pages, Now Playing away - and `standDown()` lets it go (a tab change, Now Playing, leaving). The album
/// found is kept for the session, so a song opened again opens at once.
@MainActor
@Observable
final class TopSongOpener {
    /// The row asking, by its key.
    private(set) var opening: String?
    /// What each row says in place of "Not in your library", for the visit.
    private(set) var troubles: [String: String] = [:]

    @ObservationIgnored private var asking: Task<Void, Never>?

    /// The session's albums found, by who was asked about and the song.
    private static var found: [String: SongAlbum] = [:]
    private static let foundKept = 256

    /// A top song's row, by its title as Last.fm wrote it.
    static func key(_ top: LastfmTrack) -> String { top.title }

    func trouble(_ top: LastfmTrack) -> String? { troubles[Self.key(top)] }

    /// The row tapped: its album asked for, then opened where it was tapped.
    func open(_ top: LastfmTrack, mbid: String?, name: String, client: DeadwaxClient?, online: Bool, admin: Bool,
              navigation: AppNavigation) {
        let row = Self.key(top)
        let kept = "\(MBID.of(mbid) ?? "")|\(Fold.key(name))|\(LastfmMatch.key(top.title))"
        asking?.cancel()
        if let album = Self.found[kept] {
            opening = nil
            navigation.open(.group(GroupRoute(album)))
            return
        }
        guard online, let client else { return }
        opening = row
        troubles[row] = nil
        let tab = navigation.tab
        let pages = navigation.shownStack
        asking = Task { [weak self] in
            let said: Result<SongAlbum?, any Error>
            do {
                let answer = try await client.searchSongs(TopSongs.searchQuery(title: top.title, artist: name))
                said = .success(TopSongs.album(SongSearch.group(answer.recordings), title: top.title, mbid: mbid,
                                               name: name))
            } catch {
                said = .failure(error)
            }
            guard !Task.isCancelled, let self, self.opening == row else { return }
            self.opening = nil
            switch said {
            case .success(let album?):
                if Self.found.count >= Self.foundKept { Self.found = [:] }
                Self.found[kept] = album
                guard navigation.tab == tab, navigation.shownStack == pages, !navigation.nowPlayingShown else { return }
                navigation.open(.group(GroupRoute(album)))
            case .success(nil):
                self.troubles[row] = LastfmWords.notFound
            case .failure(let error):
                if APIFailure.isCancellation(error) { return }
                self.troubles[row] = TopSongs.trouble(error, admin: admin)
            }
        }
    }

    /// Let go: nothing opens from an ask under way.
    func standDown() {
        asking?.cancel()
        asking = nil
        opening = nil
    }

    /// Another visit: the rows' troubles forgotten.
    func forget() {
        standDown()
        troubles = [:]
    }
}
