import DeadwaxCore
import Observation
import SwiftUI

/// The app's tabs (D1): Library, Search (Phase 5 - phase5-search.md 3.1, question 1: the web's order, Settings at the
/// end), Requests (Phase 6 - phase6-get-requests.md 3.1, question 1: the web's order less Home) and Settings - You on
/// the phone until 16 Nov and on the web until its 2.1.35 (the case keeps its name, `you`). The one list of them: the tab bar draws `allCases`
/// in this order and MainTabs builds a stack for each, so a tab is one case here, with its words and symbol below and
/// its stack in MainTabs.
enum AppTab: Hashable, CaseIterable {
    case library
    case search
    case requests
    /// Settings (YouWords.title), the web's name for its tab too since its 2.1.35.
    case you

    /// Its words in the tab bar, and to VoiceOver.
    var title: String {
        switch self {
        case .library: return "Library"
        case .search: return SearchWords.title
        case .requests: return RequestWords.tab
        case .you: return YouWords.title
        }
    }

    /// Its symbol in the tab bar (drawn filled, as iOS's tab bar draws them).
    var symbol: String {
        switch self {
        case .library: return "square.stack"
        case .search: return "magnifyingglass"
        // the web's RequestsIcon: an arrow into an open box
        case .requests: return "square.and.arrow.down"
        // (16 Nov) Settings' gear, as iOS's own Settings has it - the person's circle was You's
        case .you: return "gearshape"
        }
    }

    /// (15 Nov, actual corners) Its sharp-cornered glyph, drawn where its symbol was: the Library's squared stack
    /// (SharpGlyph). The others keep their SF Symbols.
    var sharp: SharpGlyph? {
        switch self {
        case .library: return .library
        case .search, .requests, .you: return nil
        }
    }
}

/// A page pushed on a tab's NavigationStack. Every page the parts add is a case here, drawn in `appRoutes()`.
enum AppRoute: Hashable {
    /// An album's page, by Navidrome's album id (with what the list knew, to draw before it loads).
    case album(AlbumRoute)
    /// An Albums screen of a scope, pushed: All music's All albums (the store's) - and, while the Albums page is
    /// Downloaded, the way back to your albums (both from the Library's •••, slice 3b).
    case albums(AlbumScope)
    /// The Library's Downloaded (Phase 2): every album on this phone, as an Albums screen - from the Library's •••.
    case downloaded
    /// Settings > Downloads (Phase 2): what's on this phone, the two settings, what's on its way and what didn't arrive.
    case downloads
    /// Settings > This phone > Change address: the Server address screen, pushed.
    case serverAddress
    /// Settings > This phone > Debug (admins only).
    case debug
    /// Settings > Playback > EQ, and the EQ's own pages (eq.md 3.1-3.2): the EQ page, an output's, the presets.
    case eq(EQRoute)
    /// (16 Nov) Settings' own pages, each a row of its root (YouView): Getting albums (When I tap Get, Quality floor,
    /// Format, Confirm before cancelling), Playback (Gapless, Now Playing opens as, Pause winds the record down,
    /// Normalization, EQ), Account (logins on: Change password, Sign out), This phone (the address, Change address,
    /// Debug) and About (the versions, Logins).
    case gettingAlbums
    case playback
    case account
    case thisPhone
    case about
    /// One playlist's page (3.3), by Navidrome's playlist id. (The Playlists list itself is a page of the Library's
    /// switch since slice 3b, not a page pushed.)
    case playlist(PlaylistRoute)
    /// (Phase 4, slice 3) The playlists downloaded to this phone - reached from Downloaded.
    case downloadedPlaylists
    /// (Phase 4, slice 4) An artist's page (phase4-library.md 2.6), by Navidrome's artist id - from an artists list's row
    /// and an album page's artist line.
    case artist(ArtistRoute)
    /// (slice 4) An artists list of a scope, pushed: All music's All artists (the store's), from the Library's •••.
    case artists(AlbumScope)
    /// (slice 5, question 32) Every song of the collection, pushed: All music's All songs, from the Library's ••• with a
    /// library of your own (without one, Songs is a page of the switch).
    case allSongs
    /// (Phase 5, slice 2) The album you don't have (phase5-search.md 3.6): a MusicBrainz album's page, by its release
    /// group's id - from Search's MusicBrainz rows.
    case group(GroupRoute)
    /// (Phase 5, slice 3) A MusicBrainz artist's page (question 9): their albums, by their MusicBrainz id - from Search's
    /// MusicBrainz artists and the album you don't have's credit.
    case mbArtist(MBArtistRoute)
    /// (Phase 8, slice 1) Settings > Manage > Edit an album: Choose the folder - any folder of the library, its Edit
    /// album opened over the tabs.
    case chooseFolder
    /// (Phase 8, slice 6) Settings > Manage > Needs a look: the review queue (NeedsLookScreen), its rows opening Edit
    /// album over the tabs in queue mode.
    case needsALook
    /// (Phase 8, slice 7) Settings > Manage > Library care (LibraryCareScreen): Rescan, and Get covers, CD art and lyrics
    /// for every album without - its runs held by the app (CareRunModel).
    case libraryCare
    /// (Phase 8, slice 7) Library care > In nobody's library (HeldByNobodyScreen): the albums nobody has and the flagged
    /// downloads - an admin's, with logins on.
    case heldByNobody
    /// (Phase 8, slice 8) Settings > Manage > Server settings (ServerSettingsScreen): Connections, the organizing verdict
    /// and the groups of settings under Library, Downloads and Connections - the drafts held by the app
    /// (ServerSettingsModel).
    case serverSettings
    /// (Phase 8, slice 8) A group of Server settings, its own page (ServerSettingsGroupScreen), by the group's id.
    case serverSettingsGroup(String)
    /// (Phase 8, slice 9) Settings > Manage > Event log (EventLogScreen): what deadwax has said since it started, newest
    /// first, live - the lines held by the app (EventLogModel), so they outlive the page.
    case eventLog
    /// (Phase 8, slice 10) Settings > Account > Change password (ChangePasswordScreen): your Navidrome password, changed
    /// in Navidrome as you - its answer re-keys this phone (ServerModel.changeOwnPassword).
    case changePassword
    /// (Phase 8, slice 11) Settings > Manage > People (PeopleScreen): Navidrome's accounts, unlocked with your own
    /// password - the state held by the app (PeopleModel), so a person's page and the list under it are one.
    case people
    /// (Phase 8, slice 11) One of People's accounts, by Navidrome's id (PersonScreen): its permissions, Reset
    /// password…, Make admin or No longer admin, Remove….
    case person(String)

    /// One of People's pages.
    var isPeople: Bool {
        switch self {
        case .people, .person: return true
        default: return false
        }
    }
}

/// The album you don't have's address: its release group's id as MusicBrainz gave it (lowercase - deadwax's routes take
/// no other), and the album Search showed, drawn at once while its pressings load (ReleaseGroupPage.tsx's `preview`) -
/// or, opened from a song (slice 3), its title alone and the song's recordings (`song`, SongSearch.ids: at most eight,
/// lowercase), the song then marked on a pressing that has it. `id` and `song` decide the page.
struct GroupRoute: Hashable {
    let id: String
    var preview: ReleaseGroup?
    /// The title drawn while the pressings load, when there is no preview (the web's `{ id, title }`).
    var title: String?
    /// The recordings of the song it was opened from - none: no song.
    var song: [String]

    init(id: String, preview: ReleaseGroup? = nil, title: String? = nil, song: [String] = []) {
        self.id = id
        self.preview = preview
        self.title = title
        self.song = song
    }

    /// An album a MusicBrainz song is on, opened from the song (Search.tsx `openSongAlbum`'s `open`).
    init(_ album: SongAlbum) {
        self.init(id: album.id, title: album.title, song: SongSearch.ids(album.recordings))
    }

    /// A Search row's album.
    init(_ group: ReleaseGroup) {
        self.init(id: group.id, preview: group)
    }
}

/// A MusicBrainz artist's page's address: their MusicBrainz id, and the name they were found by - drawn at once, while
/// who they are loads. Only `mbid` decides which artist.
struct MBArtistRoute: Hashable {
    let mbid: String
    var name: String

    init(mbid: String, name: String) {
        self.mbid = mbid
        self.name = name
    }

    /// A Search row's MusicBrainz artist.
    init(_ match: MBArtistMatch) {
        self.init(mbid: match.mbid, name: match.name)
    }
}

/// An artist page's address: Navidrome's artist id, and what opened it - the name and picture drawn at once while the
/// artist loads. Only `id` decides which artist.
struct ArtistRoute: Hashable {
    let id: String
    var preview: Artist?

    init(id: String, preview: Artist? = nil) {
        self.id = id
        self.preview = preview
    }

    /// An artists list's row.
    init(_ artist: Artist) {
        self.init(id: artist.id, preview: artist)
    }
}

/// A playlist page's address: its id, and the row that opened it - the hero drawn at once while the playlist loads.
/// Only `id` decides which playlist.
struct PlaylistRoute: Hashable {
    let id: String
    var preview: Playlist?

    init(id: String, preview: Playlist? = nil) {
        self.id = id
        self.preview = preview
    }

    /// A row of the Playlists screen.
    init(_ playlist: Playlist) {
        self.init(id: playlist.id, preview: playlist)
    }
}

/// The album page's address: the album's id, and what the row that opened it already knew - drawn at once, while
/// the album loads (screens.md's album page). Only `id` decides which album; the rest is a head start.
struct AlbumRoute: Hashable {
    let id: String
    var name: String?
    var artist: String?
    var coverArt: String?
    var year: Int?
    /// The album's genre, as the opener knew it: the meta line's first part before the album answers (AlbumPage.tsx's
    /// `[shown?.genre, shown?.year, format]`, shown = album ?? preview), so the line only gains the format when it does.
    var genre: String?
    /// The album's MusicBrainz release id, as the opener knew it: what the page tells your library it opened with
    /// (MyLibraryState.opened - the web's preview's musicBrainzId).
    var musicBrainzId: String?
    /// (Phase 4, slice 4) The album artist's Navidrome id, as the opener knew it: the hero's artist line is their link
    /// before the album answers (ArtistLink - the web's `shown?.artistId`).
    var artistId: String?

    init(id: String, name: String? = nil, artist: String? = nil, coverArt: String? = nil, year: Int? = nil,
         genre: String? = nil, musicBrainzId: String? = nil, artistId: String? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.coverArt = coverArt
        self.year = year
        self.genre = genre
        self.musicBrainzId = musicBrainzId
        self.artistId = artistId
    }

    /// A Library row's album.
    init(_ album: IndexAlbum) {
        self.init(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year,
                  genre: album.genre, musicBrainzId: album.musicBrainzId, artistId: album.artistId)
    }

    /// An album already loaded.
    init(_ album: Album) {
        self.init(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year,
                  genre: album.genre, musicBrainzId: album.musicBrainzId, artistId: album.artistId)
    }

    /// A queue entry's album (Now Playing's Go to the album, Info's album line); nil when the track names none.
    init?(track: QueueTrack) {
        guard let id = track.albumId, !id.isEmpty else { return nil }
        self.init(id: id, name: track.album, artist: track.artist, coverArt: track.coverArt)
    }
}

/// Where the app is: the tab shown, each tab's pages, and Now Playing open or not. RootView and MainTabs draw it;
/// a screen opens a page on its own tab with `open(_:)`, and the player goes to an album with `openAlbum(_:)` - on the
/// tab shown, as a screen's page would be.
@MainActor
@Observable
final class AppNavigation {
    /// The tab shown.
    private(set) var tab: AppTab = .library
    /// The Library tab's pages, root first left out.
    var library: [AppRoute] = []
    /// (Phase 5) The Search tab's pages - an album, an artist, anything the Library pushes.
    var search: [AppRoute] = []
    /// (Phase 6) The Requests tab's pages - the album a Done row opens, and anything it pushes.
    var requests: [AppRoute] = []
    /// The Settings tab's pages (16 Nov: its groups' pages - Getting albums, Playback, Downloads, Account, This phone,
    /// About - and what they push). Tapped again, it goes back to its root as every tab does, then to the top.
    var you: [AppRoute] = []
    /// Now Playing is open (a full-screen cover over the tabs).
    var nowPlayingShown = false
    /// One more each time a tab already at its root is tapped again: its root list scrolls to the top.
    private(set) var libraryScrollToTop = 0
    private(set) var searchScrollToTop = 0
    private(set) var requestsScrollToTop = 0
    private(set) var youScrollToTop = 0

    /// An EQ import's preview (eq.md 3.9), one at a time: a file shared to deadwax, or one an EQ page read from Files or
    /// the clipboard. A second arriving while a preview is up takes its place there.
    private(set) var eqImport: EQImportItem?
    /// The EQ page whose own preview shows it (its import from Files or Paste) - nil: the EQ sheet's, for a shared
    /// file.
    private(set) var eqImportPage: UUID?
    /// The EQ sheet over the tabs, opened for a shared file - over Now Playing, Now Playing opens its own.
    var eqImportSheet = false
    /// A preview is drawn (EQImportSheetContent says so).
    var eqPreviewUp = false
    /// Add to a playlist (Phase 4, slice 2), opened from a page's ••• (QueueMenu): the picker over the tabs, with the
    /// songs in hand. Now Playing opens its own, over itself.
    var playlistPick: PlaylistPickRequest?
    /// (Phase 8, slice 1) Edit album, over the tabs (EditAlbumSheet): from an album page's ••• or Choose the folder.
    /// Over the tabs, not the album page, so the page beneath can be moved to the album's new id while it is up.
    var albumEdit: AlbumEditRequest?
    /// (slice 6's review) Edit album as last presented: whatever ends it - its sheet dismissed, another opening, a
    /// sign-out - tells its Needs a look session, which ends once however many say so (Core's NeedsLook.Run).
    @ObservationIgnored private var presentedEdit: AlbumEditRequest?
    /// (Phase 8, slice 1) One more each time Edit album wrote to an album's folder, by the album's id: its page asks
    /// again (now, and once Navidrome has scanned - EditAlbumModel).
    private(set) var albumWrites: [String: Int] = [:]
    /// (Phase 8, slice 1) Albums an apply gave a new id in Navidrome (AlbumEdit.noteMove): a page opened by the old id
    /// opens the new one.
    private var moves: [String: String] = [:]
    /// (Phase 8, slice 1) One more each time the person changes (`reset`): an Edit album opened for one person stops
    /// writing into these pages - its page refreshes, its follow - once it isn't theirs (EditAlbumModel).
    private(set) var session = 0
    /// (Phase 8, slice 6) One more after every write anywhere in managing - an editor's apply, a Get, a delete, a mark,
    /// the artist tools' Save and Move: Needs a look's count is asked again (MainTabs, QueueCountModel).
    private(set) var managingWrites = 0
    /// The playlist whose Edit is open on a tab's page: the tab tapped again goes back no further than that page, so
    /// Edit's changes are never thrown away without Cancel's question (PlaylistEdit.pagesKept).
    private(set) var editingPlaylist: String?
    /// (Phase 8, slice 10) A Change password is out: the tab tapped again goes back no further than its page, where its
    /// answer is said (OwnPassword.pagesKept).
    private(set) var changingPassword = false
    /// (Phase 8, slice 11) A People write is out: the tab tapped again goes back no further than People's last page,
    /// where its answer is said (People.pagesKept).
    private(set) var writingPeople = false
    /// (The Mac app, slice 2) Edit > Find (⌘F) asked for Search's field: Search takes it as it shows (FindFocus), and
    /// says so (`findTaken`). Never set on the iPhone.
    private(set) var findWanted = false
    /// (The Mac app, slice 2) The Library switch's page as the Mac's window last showed it: a window closed and opened
    /// again from the Dock comes back on it, as the tab and its pages do (they are all the app's, not the window's).
    /// Only the Mac's window writes it (LibraryView).
    var macLibraryPage: LibraryPage?

    /// A file shared to deadwax (`.onOpenURL`): shown by the preview that is up, in place - else by the EQ sheet,
    /// opened over Now Playing (by Now Playing) or over the tabs (here).
    func share(_ item: EQImportItem) {
        eqImport = item
        guard !eqPreviewUp else { return }
        eqImportPage = nil
        if !nowPlayingShown { eqImportSheet = true }
    }

    /// An EQ page's own import (Files, Paste): its preview, over that page.
    func importOnPage(_ page: UUID, _ item: EQImportItem) {
        eqImportPage = page
        eqImport = item
    }

    /// The preview answered - Import, Cancel, Done - or gone with what it showed.
    func importAnswered(_ id: UUID? = nil) {
        guard id == nil || eqImport?.id == id else { return }
        eqImport = nil
        eqImportPage = nil
    }

    /// A tab tapped. The tab already shown: back to its root - and, at its root already, to the top of its list.
    func select(_ tapped: AppTab) {
        guard tapped == tab else {
            tab = tapped
            return
        }
        switch tapped {
        case .library:
            if library.isEmpty { libraryScrollToTop += 1 } else { backToRoot(&library) }
        case .search:
            if search.isEmpty { searchScrollToTop += 1 } else { backToRoot(&search) }
        case .requests:
            if requests.isEmpty { requestsScrollToTop += 1 } else { backToRoot(&requests) }
        case .you:
            if you.isEmpty { youScrollToTop += 1 } else { backToRoot(&you) }
        }
    }

    /// (The Mac app, slice 2) Edit > Find (⌘F): Search at its root - its pages popped as the tab tapped again pops them -
    /// Now Playing closed, and its field to take the cursor as it shows.
    func find() {
        nowPlayingShown = false
        tab = .search
        backToRoot(&search)
        findWanted = true
    }

    /// (The Mac app, slice 2) Search's field has the cursor Find asked for.
    func findTaken() {
        findWanted = false
    }

    /// (The Mac app, slice 2) deadwax > Settings… (⌘,): the Settings tab, its pages as they were - as a tap on the tab
    /// from another - and Now Playing closed.
    func showSettings() {
        nowPlayingShown = false
        tab = .you
    }

    /// (Phase 6, slice 2) A download asked for from the Sources sheet (App.tsx `gotten`, `router.root('requests')`):
    /// Requests shown at its root, its new row already up - Now Playing closed, and a playlist being edited there kept,
    /// as the tab tapped again keeps it.
    func showRequestsRoot() {
        nowPlayingShown = false
        tab = .requests
        backToRoot(&requests)
    }

    /// Every page popped - but none of a playlist being edited, nor the pages under it; nor Change password's while its
    /// change is out; nor People's while one of its writes is.
    private func backToRoot(_ stack: inout [AppRoute]) {
        let ids = stack.map { (route: AppRoute) -> String? in
            if case .playlist(let shown) = route { return shown.id }
            return nil
        }
        let password = stack.map { (route: AppRoute) -> Bool in route == .changePassword }
        let people = stack.map(\.isPeople)
        let kept = max(PlaylistEdit.pagesKept(ids, editing: editingPlaylist),
                       OwnPassword.pagesKept(password, changing: changingPassword),
                       People.pagesKept(people, writing: writingPeople))
        stack.removeLast(stack.count - kept)
    }

    /// (Phase 8, slice 10) Change password's change went out, or answered.
    func passwordChanging(_ out: Bool) {
        changingPassword = out
    }

    /// (Phase 8, slice 11) A People write went out, or answered.
    func peopleWriting(_ out: Bool) {
        writingPeople = out
    }

    /// (slice 11) A page of People is on a tab - PeopleModel keeps People's state while one is.
    var holdsPeople: Bool {
        (library + search + requests + you).contains(where: \.isPeople)
    }

    /// (slice 11) A person removed: their page gone from the top of any tab it is on top of - only while it is what
    /// shows there, so a removal answering after another page was opened over it pops nothing.
    func leavePerson(_ id: String) {
        func left(_ stack: inout [AppRoute]) {
            if case .person(let shown)? = stack.last, shown == id { stack.removeLast() }
        }
        left(&library)
        left(&search)
        left(&requests)
        left(&you)
    }

    /// A playlist's page opened or closed its Edit.
    func editing(_ id: String, _ open: Bool) {
        if open {
            editingPlaylist = id
        } else if editingPlaylist == id {
            editingPlaylist = nil
        }
    }

    /// A playlist's page went away: popped (no page of it left on any tab), its Edit with it.
    func pageGone(_ id: String) {
        guard editingPlaylist == id else { return }
        let held = (library + search + requests + you).contains { (route: AppRoute) -> Bool in
            if case .playlist(let shown) = route { return shown.id == id }
            return false
        }
        if !held { editingPlaylist = nil }
    }

    /// `route` pushed on the tab shown - an album an apply gave a new id opened by that id (AlbumEdit.movedTo).
    func open(_ route: AppRoute) {
        let route = followed(route)
        switch tab {
        case .library: library.append(route)
        case .search: search.append(route)
        case .requests: requests.append(route)
        case .you: you.append(route)
        }
    }

    /// The pages of the tab shown - what a page's late answer checks is still as it was before it opens anything.
    var shownStack: [AppRoute] {
        switch tab {
        case .library: return library
        case .search: return search
        case .requests: return requests
        case .you: return you
        }
    }

    /// Go to album, from the player (Now Playing's byline and •••, Info's album card): Now Playing closes - Info and
    /// Up Next with it - and the album's page is pushed on the tab shown, its pages kept (screens.md 7, the web's
    /// goToAlbum: "opens the album page on the current tab"). An album already on top of it isn't pushed twice.
    func openAlbum(_ album: AlbumRoute) {
        nowPlayingShown = false
        guard case .album(let album) = followed(.album(album)) else { return }
        let top = shownStack.last
        if case .album(let shown)? = top, shown.id == album.id { return }
        open(.album(album))
    }

    // MARK: Edit album (Phase 8, slice 1)

    /// Edit album opened over the tabs (a page's ••• or Choose the folder; Now Playing is never over either). Put in
    /// place of another opening - still up, or going with its onDismiss yet to come - that one's Needs a look session
    /// ends: unless this is the same page's new session, which its Run began only once the last had ended.
    func editAlbum(_ request: AlbumEditRequest) {
        let was = presentedEdit
        presentedEdit = request
        albumEdit = request
        if let was, was.id != request.id, was.queue !== request.queue { was.queue?.editorClosed() }
    }

    /// (slice 6's review) Edit album's sheet went (MainTabs' onDismiss) - Close, a swipe, Discard, a step to an album
    /// gone, a sign-out: its Needs a look session told it is over, unless the sheet up now is that same opening. The
    /// sheet's dismissal, not its content disappearing - a full-screen cover over it (Compare covers, a picture full
    /// size) does that too, and the session lasts through it.
    func editorDismissed() {
        guard let was = presentedEdit, albumEdit?.id != was.id else { return }
        presentedEdit = albumEdit
        was.queue?.editorClosed()
    }

    /// Edit album wrote to the album `id`'s folder: its page asks again.
    func albumWritten(_ id: String) {
        albumWrites[id, default: 0] += 1
    }

    /// (Phase 8, slice 6) A managing write landed, or may have: what counts the albums that need a look asks again.
    func managed() {
        managingWrites += 1
    }

    /// An apply gave the album `from` a new id in Navidrome, `to` (EditPanel's 'moved'): every page of it, on every
    /// tab, now the page of `to` - what it knew of the album kept to draw while it loads - and a page opened by `from`
    /// from now on opens `to`.
    func albumMoved(from: String, to: String) {
        AlbumEdit.noteMove(&moves, from: from, to: to)
        func moved(_ stack: inout [AppRoute]) {
            for index in stack.indices {
                guard case .album(let shown) = stack[index], shown.id == from else { continue }
                stack[index] = .album(AlbumRoute(id: to, name: shown.name, artist: shown.artist, year: shown.year,
                                                 genre: shown.genre, artistId: shown.artistId))
            }
        }
        moved(&library)
        moved(&search)
        moved(&requests)
        moved(&you)
    }

    /// An album route by the id its album has now (AlbumEdit.movedTo); every other route as it is.
    private func followed(_ route: AppRoute) -> AppRoute {
        guard case .album(let album) = route, let to = AlbumEdit.movedTo(moves, album.id) else { return route }
        return .album(AlbumRoute(id: to, name: album.name, artist: album.artist, year: album.year, genre: album.genre,
                                 artistId: album.artistId))
    }

    /// A playlist's page gone from the top of the tab shown (deleted on it, Phase 4 slice 2) - only while it is still
    /// what shows: a delete answering after another page was opened over it pops nothing (App.tsx playlistDeleted).
    func leavePlaylist(_ id: String) {
        switch tab {
        case .library:
            if case .playlist(let shown)? = library.last, shown.id == id { library.removeLast() }
        case .search:
            if case .playlist(let shown)? = search.last, shown.id == id { search.removeLast() }
        case .requests:
            if case .playlist(let shown)? = requests.last, shown.id == id { requests.removeLast() }
        case .you:
            if case .playlist(let shown)? = you.last, shown.id == id { you.removeLast() }
        }
    }

    /// (Phase 8, slice 4) An album Edit album deleted, nothing of it left in Navidrome (AlbumEdit.deletesAll): its page
    /// gone from the top of the tab shown - only while it is what shows (App.tsx's `else if (showing) router.back()`).
    func leaveAlbum(_ id: String) {
        func left(_ stack: inout [AppRoute]) {
            if case .album(let shown)? = stack.last, shown.id == id { stack.removeLast() }
        }
        switch tab {
        case .library: left(&library)
        case .search: left(&search)
        case .requests: left(&requests)
        case .you: left(&you)
        }
    }

    /// Back to the EQ page a page was pushed from ("Use for …", eq.md 3.7): every page over the topmost EQ page on the
    /// tab shown popped at once. Nothing when the tab holds no EQ page.
    func backToEQPage() {
        func popped(_ stack: inout [AppRoute]) {
            guard let page = stack.lastIndex(where: { (route: AppRoute) -> Bool in
                if case .eq(let eq) = route { return eq.isPage }
                return false
            }) else { return }
            stack.removeSubrange((page + 1)...)
        }
        switch tab {
        case .library: popped(&library)
        case .search: popped(&search)
        case .requests: popped(&requests)
        case .you: popped(&you)
        }
    }

    /// The person changed: every page popped, Now Playing closed, Library shown.
    func reset() {
        library.removeAll()
        search.removeAll()
        requests.removeAll()
        you.removeAll()
        nowPlayingShown = false
        eqImportSheet = false
        playlistPick = nil
        editingPlaylist = nil
        changingPassword = false
        writingPeople = false
        let editor = presentedEdit
        presentedEdit = nil
        albumEdit = nil
        albumWrites = [:]
        moves = [:]
        session += 1
        importAnswered()
        tab = .library
        findWanted = false
        macLibraryPage = nil
        // (slice 6's review) Needs a look's session over - once the session has moved on, so nothing is noted, read or
        // asked for the next person
        editor?.queue?.editorClosed()
    }
}

extension View {
    /// Every AppRoute's page, for a tab's NavigationStack - each given room at its foot for the player and the tab bar
    /// over it (`clearsPlayer()`, MainTabs.swift), the offline banner at its top (`showsOfflineBanner()`), and iOS's own
    /// tab bar kept hidden under the app's (the squared look: on the stack and on each page, so a push never brings it
    /// back).
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            Group {
                switch route {
                // by its id: a page moved to an album's new id (AppNavigation.albumMoved) is that album's page afresh
                case .album(let album): AlbumView(route: album).id(album.id)
                case .albums(let scope): AlbumsScreen(scope: scope)
                case .downloaded: AlbumsScreen(list: .downloaded)
                case .downloads: DownloadsScreen()
                case .serverAddress: ServerAddressView()
                case .debug: DebugView()
                case .eq(let page): EQDestination(route: page)
                case .gettingAlbums: GettingAlbumsPage()
                case .playback: PlaybackPage()
                case .account: AccountPage()
                case .thisPhone: ThisPhonePage()
                case .about: AboutPage()
                case .playlist(let playlist): PlaylistView(route: playlist)
                case .downloadedPlaylists: DownloadedPlaylistsScreen()
                case .artist(let artist): ArtistView(route: artist)
                case .artists(let scope): ArtistsScreen(scope: scope)
                case .allSongs: SongsScreen()
                case .group(let group): GroupView(route: group)
                case .mbArtist(let artist): MBArtistView(route: artist)
                case .chooseFolder: ChooseFolderScreen()
                case .needsALook: NeedsLookScreen()
                case .libraryCare: LibraryCareScreen()
                case .heldByNobody: HeldByNobodyScreen()
                case .serverSettings: ServerSettingsScreen()
                case .serverSettingsGroup(let id): ServerSettingsGroupScreen(id: id)
                case .eventLog: EventLogScreen()
                case .changePassword: ChangePasswordScreen()
                case .people: PeopleScreen()
                case .person(let id): PersonScreen(id: id)
                }
            }
            .clearsPlayer()
            .showsOfflineBanner()
            .toolbar(.hidden, for: .tabBar)
        }
    }
}
