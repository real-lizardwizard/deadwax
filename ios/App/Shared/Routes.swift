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
    /// (Last.fm, slice A1) An artist's Top Songs (TopSongsScreen): all of Last.fm's ten - from their page's See All.
    case topSongs(ArtistRoute)
    /// (Last.fm, slice A2) An artist's Similar Artists (SimilarArtistsScreen): every tile in a grid - from their page's
    /// See All, so a mouse reaches every one.
    case similarArtists(ArtistRoute)
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

/// (R7) The Mac's Get in the dock (AppNavigation.macSources): the Get, the page it was asked from, and its chips and
/// sort - the Get's, so they outlast the dock's tab switched away from and back to (SourcesPage's `kept`).
@MainActor
struct MacSourcesGet {
    let page: GroupRoute
    let request: GetRequest
    let choices = SourcesChoices()
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
    /// The tab shown. (R7) Each of these five moving is the page in front moving: the dock's Get ends unless its page is
    /// still the one in front (`frontMoved`).
    private(set) var tab: AppTab = .library { didSet { frontMoved() } }
    /// The Library tab's pages, root first left out.
    var library: [AppRoute] = [] { didSet { frontMoved() } }
    /// (Phase 5) The Search tab's pages - an album, an artist, anything the Library pushes.
    var search: [AppRoute] = [] { didSet { frontMoved() } }
    /// (Phase 6) The Requests tab's pages - the album a Done row opens, and anything it pushes.
    var requests: [AppRoute] = [] { didSet { frontMoved() } }
    /// The Settings tab's pages (16 Nov: its groups' pages - Getting albums, Playback, Downloads, Account, This phone,
    /// About - and what they push). Tapped again, it goes back to its root as every tab does, then to the top.
    var you: [AppRoute] = [] { didSet { frontMoved() } }
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
    /// The EQ sheet over the tabs, opened for a shared file - over Now Playing, Now Playing opens its own. The phone's
    /// alone since R3's review: on the Mac a shared file shows in the dock's EQ tab (SharedEQFile), the one EQ there.
    var eqImportSheet = false
    /// A preview is drawn (EQImportSheetContent says so).
    var eqPreviewUp = false
    /// (The Mac app, slice 6) File > Import EQ File… (⌘O) asked for the Open panel: RootView shows it (Platform's
    /// `eqOpenPanel`), and the file chosen there comes the way a shared file does (`share`). Never set on the iPhone.
    var eqFileChoosing = false
    /// Add to a playlist (Phase 4, slice 2), opened from a page's ••• (QueueMenu): the picker over the tabs, with the
    /// songs in hand. Now Playing opens its own, over itself.
    var playlistPick: PlaylistPickRequest?
    /// (Phase 8, slice 1) Edit album, over the tabs (EditAlbumSheet): from an album page's ••• or Choose the folder.
    /// Over the tabs, not the album page, so the page beneath can be moved to the album's new id while it is up.
    var albumEdit: AlbumEditRequest?
    /// (slice 6's review) Edit album as last presented: whatever ends it - its sheet dismissed, another opening, a
    /// sign-out - tells its Needs a look session, which ends once however many say so (Core's NeedsLook.Run). (R10) On
    /// the Mac, the opening its page shows: the page leaving every stack ends it (`editPageGone`).
    @ObservationIgnored private var presentedEdit: AlbumEditRequest?
    /// (R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list and Release") Edit album on the Mac: the
    /// opening its page shows - Settings' Edit an album (`.chooseFolder`), the folder list beside the editor
    /// (MacEditWindow). The Mac never presents the sheet: `albumEdit` is never set there, nor this on the iPhone.
    private(set) var macEdit: AlbumEditRequest?
    /// (R10) An opening asked for while the Mac's editor holds work (typed work, a write or a mark): its page, brought to
    /// the front, asks "Discard changes?" first, as the sheet's Close does (`macEditAnswered`).
    private(set) var macEditAsked: AlbumEditRequest?
    /// (R10) The Mac's editor holds work: its page is kept as a playlist's Edit is (`kept`) - a tab's button never pops
    /// it, a sidebar row opens over it - and its page draws no Back meanwhile.
    private(set) var macEditHolds = false
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
    /// (R7) Search's Search Soulseek by hand… asked for Requests' manual search: its Artist field takes the cursor as
    /// it shows (`manualSearchTaken`). Never set on the iPhone, whose manual search is Requests' own sheet.
    private(set) var manualSearchWanted = false
    /// (The Mac app, slice 2) The Library switch's page as the Mac's window last showed it: a window closed and opened
    /// again from the Dock comes back on it, as the tab and its pages do (they are all the app's, not the window's).
    /// Only the Mac's window writes it (LibraryView) - and (slice 3) the sidebar's rows, which the Library's page follows.
    var macLibraryPage: LibraryPage?
    /// (The Mac app, slice 3) The desktop frame's sidebar is shown: View > Hide Sidebar (⌃⌘S) puts it away, Find brings
    /// it back. Never read on the iPhone.
    var macSidebarShown = true
    /// (The Mac app, slice 3) The side panel showing - (the Mac redesign, R3) the dock's tab: Queue, Lyrics, Info, the EQ,
    /// or Sources while a Get page is open, one at a time (MacDock.toggled); nil while it's closed. Always nil on the
    /// iPhone, where they are Now Playing's sheet and its face.
    private(set) var macPanel: MacDock.Tab?
    /// (R3) A Get page is open, so the dock draws Sources (MacDock.tabs) - (R7) a Get asked for on it, in the dock
    /// (`macSources`). Its going takes Sources with it (MacDock.kept).
    private(set) var macGetOpen = false {
        didSet { macPanel = MacDock.kept(macPanel, getOpen: macGetOpen) }
    }
    /// (R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)") The Mac's Get: Get the album on
    /// the album you don't have opens Sources in the dock, not the phone's sheet - this Get, and the page it was asked
    /// from. One at a time; it lasts only while that page is the one in front (MacDock.getLasts), its search let go as it
    /// ends (`endSources`). Always nil on the iPhone.
    private(set) var macSources: MacSourcesGet? {
        didSet { macGetOpen = macSources != nil }
    }
    /// (R3) A list on the page in front has a row selected (MacSelection, mirrored by DesktopFrame): Info is about it
    /// then, so View > Info opens with nothing queued, and it stays as the queue ends (MacDock.afterQueueEnds).
    var macSelected = false
    /// (The Mac app, slice 3) How the panel is drawn at the window's width (MacFrame.panelStyle): a drawer over the page's
    /// edge closes as an album is opened from the player (`openAlbum`). DesktopFrame keeps it.
    var macPanelStyle: MacFrame.PanelStyle = .column

    /// A file shared to deadwax (`.onOpenURL`): shown by the preview that is up, in place - else (SharedEQFile) on the
    /// phone by the EQ sheet, opened over Now Playing (by Now Playing) or over the tabs (here), and (R3's review) on the
    /// Mac by the dock's EQ tab, shown whatever was showing, its preview over it (DockEQ) - one EQ, never a second.
    func share(_ item: EQImportItem) {
        eqImport = item
        guard !eqPreviewUp else { return }
        eqImportPage = nil
        switch SharedEQFile.shows(device: Platform.device, nowPlayingShown: nowPlayingShown) {
        case .dock: showPanel(.eq)
        case .sheet: eqImportSheet = true
        case .nowPlaying: break
        }
    }

    /// (The Mac app, slice 6) File > Import EQ File… (⌘O): the Open panel, over the pages (MacMenu dims it over a sheet
    /// and the sign-in). (Slice 6's review) Asked again while it still reads as up - a panel that never came, because
    /// the EQ page's own Open or Save panel or an alert was up, or one SwiftUI hasn't said is gone - it is put down and
    /// asked again a moment later, so ⌘O never stays dead until a sign-out.
    func openEQFile() {
        guard eqFileChoosing else {
            eqFileChoosing = true
            return
        }
        eqFileChoosing = false
        Task { @MainActor [weak self] () async -> Void in
            try? await Task.sleep(for: .milliseconds(100))
            self?.openEQFile()
        }
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
    /// Now Playing closed, and its field to take the cursor as it shows. (Slice 3) In the desktop frame the field is the
    /// sidebar's: the sidebar shown, and its field given the cursor where the page is - typing there shows Search's
    /// results (`showSearch`), as the web's sidebar field does.
    func find() {
        if MacFrame.drawsDesktop(Platform.device) {
            macSidebarShown = true
        } else {
            nowPlayingShown = false
            tab = .search
            backToRoot(&search)
        }
        findWanted = true
    }

    /// (The Mac app, slice 3) Something typed in the sidebar's search field, or Return there: Search's results at its
    /// root (the web's `onSearch`) - an album opened from them popped, as the web's field pops it.
    func showSearch() {
        tab = .search
        if !search.isEmpty { backToRoot(&search) }
    }

    /// (The Mac app, slice 3) A panel's button in the bar, or its View menu item - (R3) a tab's key: the panel closed
    /// when that tab is showing, else switched to it - one at a time (MacDock.toggled).
    func togglePanel(_ tab: MacDock.Tab) {
        macPanel = MacDock.toggled(macPanel, tab, getOpen: macGetOpen)
    }

    /// (R3) A folder tab clicked, the bar's ••• Info or EQ, Settings > Playback's EQ row: that tab, whatever was showing.
    func showPanel(_ tab: MacDock.Tab) {
        macPanel = MacDock.shown(macPanel, asked: tab, getOpen: macGetOpen)
    }

    /// (The Mac app, slice 3) A panel's Done (or Escape): put away.
    func closePanel() {
        macPanel = nil
    }

    /// (R7) Get the album, on the Mac: Sources in the dock for `request`, shown - a Get before it ended, its search let go.
    func getSources(_ request: GetRequest, from page: GroupRoute) {
        macSources?.request.search.close()
        macSources = MacSourcesGet(page: page, request: request)
        showPanel(.sources)
    }

    /// (R7) The dock's Get over - its page left, its Close, a person changing: its search let go, and Sources gone with
    /// it (MacDock.kept).
    func endSources() {
        guard let ended = macSources else { return }
        macSources = nil
        ended.request.search.close()
    }

    /// (R7) A download asked for from the dock's Sources - only while the dock still shows that Get: the Get over and
    /// Requests shown at its root, its new row already up, as the phone's sheet hands over (`showRequestsRoot`).
    func sourcesQueued(_ id: Int) {
        guard macSources?.request.id == id else { return }
        endSources()
        showRequestsRoot()
    }

    /// (R7's review) Another pressing chosen on a Get page: the dock's Get for that page ends unless it is for the pressing
    /// now chosen (MacDock.getStands) - its search let go and Sources gone, so its cards' Get can never download a
    /// pressing the page no longer shows. Get the album asks again, for the one chosen.
    func pressingChosen(_ chosen: String?, on page: GroupRoute) {
        guard let get = macSources, get.page == page,
              !MacDock.getStands(asked: get.request.release.releaseMbid, chosen: chosen) else { return }
        endSources()
    }

    /// (R7) The page in front moved: the dock's Get ends unless its own page is still the one in front. (R10) And the
    /// Mac's Edit album ends once its page is on no stack.
    private func frontMoved() {
        editPageGone()
        guard let get = macSources, !MacDock.getLasts(AppRoute.group(get.page), front: shownStack.last) else { return }
        endSources()
    }

    /// (R7) Search's "Search Soulseek by hand…" on the Mac: Requests at its root, Now Playing closed, and its toolbar's
    /// Artist field to take the cursor as it shows (MacRequestsPage) - the way the manual search already opens there.
    func manualSearch() {
        nowPlayingShown = false
        tab = .requests
        backToRoot(&requests)
        manualSearchWanted = true
    }

    /// (R7) Requests' Artist field has the cursor `manualSearch` asked for.
    func manualSearchTaken() {
        manualSearchWanted = false
    }

    /// (The Mac app, slice 3) Nothing queued any more: Up Next and Info go with the queue (their sheets did); Lyrics stays.
    /// (R3) Info stays while a row is selected, which it is about; the EQ and Sources aren't the queue's.
    func queueEnded() {
        macPanel = MacDock.afterQueueEnds(macPanel, selected: macSelected)
    }

    /// (The Mac app, slice 3) A sidebar row's move (MacSidebar.move): the tab's own button, a page of the Library at its
    /// root, a section at its foot, a playlist's page or a Manage page put on its stack. A stack whose pages hold work
    /// (a playlist's Edit, a password or a People write out - as the tab tapped again keeps them) is never cleared under
    /// it: the move then goes no further than that page - and a page put on it never takes such a page's place, nor
    /// pops it, but opens over it (MacSidebar.put, slice 3's review).
    func macMove(_ move: MacSidebar.Move) {
        nowPlayingShown = false
        switch move {
        case .tab(.library) where tab == .library && library.first.map(Self.sidebarPage)?.section != nil:
            // a section at the Library's foot is the view the Library shows (the web's root drawn with the section's
            // pick): its row again goes back to it - never past it to the root, which shows Yours' pages alone here
            backToSection()
        case .tab(let tab):
            select(Self.appTab(tab))
        case .view(let page):
            tab = .library
            if !library.isEmpty { backToRoot(&library) }
            macLibraryPage = page
        case .section(let page):
            tab = .library
            if !library.isEmpty { backToRoot(&library) }
            if library.isEmpty, let route = Self.route(page) { library = [route] }
        case .playlist(let id, let how):
            tab = .library
            MacSidebar.put(AppRoute.playlist(PlaylistRoute(id: id)), how, on: &library, kept: kept(library))
        case .manage(.edit, _) where you.contains(.chooseFolder):
            // (R10) one Edit album page: back to it - the pages over it popped, those that hold work kept
            tab = .you
            backToEditPage()
        case .manage(let tool, let how):
            tab = .you
            if let route = Self.route(.manage(tool)) { MacSidebar.put(route, how, on: &you, kept: kept(you)) }
        }
    }

    /// Where the app is, as the sidebar reads it: the tab, the Library's page, and its stacks.
    func macWhere(page: LibraryPage) -> MacSidebar.Where {
        let tab: MacSidebar.Tab
        switch self.tab {
        case .library: tab = .library
        case .search: tab = .search
        case .requests: tab = .requests
        case .you: tab = .settings
        }
        return MacSidebar.Where(tab: tab, page: page, library: library.map(Self.sidebarPage),
                                settings: you.map(Self.sidebarPage), shown: shownStack.map(Self.sidebarPage))
    }

    private static func appTab(_ tab: MacSidebar.Tab) -> AppTab {
        switch tab {
        case .library: return .library
        case .search: return .search
        case .requests: return .requests
        case .settings: return .you
        }
    }

    /// A page as the sidebar reads it.
    static func sidebarPage(_ route: AppRoute) -> MacSidebar.Page {
        switch route {
        case .albums(.store): return .allAlbums
        case .artists(.store): return .allArtists
        case .allSongs: return .allSongs
        case .downloaded: return .downloaded
        case .playlist(let shown): return .playlist(shown.id)
        case .chooseFolder: return .manage(.edit)
        case .needsALook: return .manage(.queue)
        case .libraryCare: return .manage(.care)
        case .heldByNobody: return .under(.care)
        case .people: return .manage(.people)
        case .person: return .under(.people)
        case .serverSettings: return .manage(.settings)
        case .serverSettingsGroup: return .under(.settings)
        case .eventLog: return .manage(.log)
        default: return .other
        }
    }

    /// A sidebar row's own page.
    private static func route(_ page: MacSidebar.Page) -> AppRoute? {
        switch page {
        case .allAlbums: return .albums(.store)
        case .allArtists: return .artists(.store)
        case .allSongs: return .allSongs
        case .downloaded: return .downloaded
        case .playlist(let id): return .playlist(PlaylistRoute(id: id))
        case .manage(.edit): return .chooseFolder
        case .manage(.queue): return .needsALook
        case .manage(.care): return .libraryCare
        case .manage(.people): return .people
        case .manage(.settings): return .serverSettings
        case .manage(.log): return .eventLog
        case .under, .other: return nil
        }
    }

    /// The Library back to the section at its foot: the pages over it popped as the tab's button pops a stack, those
    /// that hold work kept.
    private func backToSection() {
        guard let base = library.first, library.count > 1 else { return }
        var above = Array(library.dropFirst())
        backToRoot(&above)
        library = [base] + above
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
        stack.removeLast(stack.count - kept(stack))
    }

    /// How many of a stack's pages, from its foot, hold work - a playlist's Edit, Change password's or a People write
    /// out, and the pages under each: the tab tapped again pops none of them, nor does a sidebar row (slice 3's review:
    /// MacSidebar.put, which once replaced or popped a playlist being edited).
    private func kept(_ stack: [AppRoute]) -> Int {
        let ids = stack.map { (route: AppRoute) -> String? in
            if case .playlist(let shown) = route { return shown.id }
            return nil
        }
        let password = stack.map { (route: AppRoute) -> Bool in route == .changePassword }
        let people = stack.map(\.isPeople)
        // (R10) the Mac's Edit album holding work, and the pages under it
        let editing = macEditHolds ? (stack.lastIndex(of: .chooseFolder).map { (at: Int) -> Int in at + 1 } ?? 0) : 0
        return max(PlaylistEdit.pagesKept(ids, editing: editingPlaylist),
                   OwnPassword.pagesKept(password, changing: changingPassword),
                   People.pagesKept(people, writing: writingPeople), editing)
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
        // (the Mac app, slice 3) a panel lying over the page's edge would lie over the album asked for: put away. A third
        // column stays beside it. Never on the iPhone, whose panel is always none.
        if MacDock.liesOver(macPanelStyle, macPanel) { macPanel = nil }
        guard case .album(let album) = followed(.album(album)) else { return }
        let top = shownStack.last
        if case .album(let shown)? = top, shown.id == album.id { return }
        open(.album(album))
    }

    // MARK: Edit album (Phase 8, slice 1)

    /// Edit album opened over the tabs (a page's ••• or Choose the folder; Now Playing is never over either). Put in
    /// place of another opening - still up, or going with its onDismiss yet to come - that one's Needs a look session
    /// ends: unless this is the same page's new session, which its Run began only once the last had ended. (R10) On the
    /// Mac, never the sheet: Settings' Edit an album page, on that folder (`macEditPage`).
    func editAlbum(_ request: AlbumEditRequest) {
        if MacFrame.drawsDesktop(Platform.device) {
            macEditPage(request)
            return
        }
        let was = presentedEdit
        presentedEdit = request
        albumEdit = request
        if let was, was.id != request.id, was.queue !== request.queue { was.queue?.editorClosed() }
    }

    /// (R10) Edit album on the Mac: Now Playing closed, Settings shown with its Edit an album page in front, opened for
    /// `request` - an album page's Edit, a folder picked in the page's own list, Needs a look's row. One page of it, ever:
    /// on top already it stays (its list and its place kept); one further down is let go and the page put on top - as
    /// Manage's row puts it, or over Needs a look when opened from there (Back is the queue's page again). While the editor
    /// holds work, nothing is let go: the page is brought to the front and asks "Discard changes?" for the new opening.
    /// The opening put in place of another ends that one's Needs a look session, as the sheet's does.
    private func macEditPage(_ request: AlbumEditRequest) {
        nowPlayingShown = false
        if macEditHolds, let shown = macEdit, shown.id != request.id {
            if let asked = macEditAsked, asked.id != request.id, asked.queue !== request.queue {
                asked.queue?.editorClosed()
            }
            macEditAsked = request
            backToEditPage()
            tab = .you
            return
        }
        let was = presentedEdit
        presentedEdit = request
        // the stack changed in one write, so it never reads as the page gone (`editPageGone`) on the way
        var stack = you
        if stack.last != .chooseFolder {
            stack.removeAll { (route: AppRoute) -> Bool in route == .chooseFolder }
            let how = request.queue != nil ? MacSidebar.StackMove.open
                : MacSidebar.managingMove(stack.map(Self.sidebarPage), .edit)
            MacSidebar.put(AppRoute.chooseFolder, how, on: &stack, kept: kept(stack))
        }
        you = stack
        tab = .you
        // (R10's review) an opening asked for and never answered - Discard said to a folder picked meanwhile: let go,
        // and the Needs a look session it began with it, as Keep editing lets it go
        if let asked = macEditAsked, asked.id != request.id, asked.queue !== request.queue {
            asked.queue?.editorClosed()
        }
        macEditAsked = nil
        macEdit = request
        if let was, was.id != request.id, was.queue !== request.queue { was.queue?.editorClosed() }
    }

    /// (R10) The Mac's editor answered "Discard changes?" for the opening asked (`macEditAsked`): Discard opens it, Keep
    /// editing lets it go - and the Needs a look session it began with it.
    func macEditAnswered(discard: Bool) {
        guard let asked = macEditAsked else { return }
        macEditAsked = nil
        if discard {
            macEditHolds = false
            macEditPage(asked)
        } else if asked.queue !== macEdit?.queue {
            asked.queue?.editorClosed()
        }
    }

    /// (R10) The Mac's editor holds work now, or no longer (MacEditWindow says so as it changes).
    func macEditHolding(_ holds: Bool) {
        macEditHolds = holds
    }

    /// (R10) The Mac's Edit album went with the album it showed - deleted, or the queue's session over (the sheet would
    /// close): the page stays, its editor shows nothing until a folder is picked.
    func macEditEnded() {
        guard let shown = macEdit else { return }
        macEdit = nil
        macEditHolds = false
        if presentedEdit?.id == shown.id { presentedEdit = nil }
        shown.queue?.editorClosed()
    }

    /// (R10) Settings' stack back to the Edit album page: the pages over it popped, but none that hold work.
    private func backToEditPage() {
        guard let at = you.lastIndex(of: .chooseFolder) else { return }
        let keep = max(at + 1, kept(you))
        if you.count > keep { you.removeLast(you.count - keep) }
    }

    /// (R10) The Mac's Edit album page is on no stack any more - Back, a tab's button, a sidebar row in its place: its
    /// opening over, and its Needs a look session with it, as the sheet's dismissal ends it.
    private func editPageGone() {
        guard macEdit != nil || macEditAsked != nil,
              !(library + search + requests + you).contains(.chooseFolder) else { return }
        if let asked = macEditAsked {
            macEditAsked = nil
            asked.queue?.editorClosed()
        }
        macEditEnded()
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

    /// (The Mac app, slice 2) The album `id`'s id now: the one an apply gave it (AlbumEdit.movedTo), or `id` - what a
    /// right-click on a tile drawn before the move asks for (MacRightClick).
    func albumId(_ id: String) -> String {
        AlbumEdit.movedTo(moves, id) ?? id
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
    /// (R10's review) On the Mac the editor is Settings' page, so the tab shown is Settings, with Edit an album on top:
    /// every page of the album goes, on every stack, as `albumMoved` follows it on every stack - the album page it was
    /// opened from left on its own tab's top, and any other, would show an album that is gone.
    func leaveAlbum(_ id: String) {
        func left(_ stack: inout [AppRoute]) {
            if case .album(let shown)? = stack.last, shown.id == id { stack.removeLast() }
        }
        if MacFrame.drawsDesktop(Platform.device) {
            func gone(_ stack: inout [AppRoute]) {
                guard stack.contains(where: { (route: AppRoute) -> Bool in Self.isAlbum(route, id) }) else { return }
                stack.removeAll { (route: AppRoute) -> Bool in Self.isAlbum(route, id) }
            }
            gone(&library)
            gone(&search)
            gone(&requests)
            gone(&you)
            return
        }
        switch tab {
        case .library: left(&library)
        case .search: left(&search)
        case .requests: left(&requests)
        case .you: left(&you)
        }
    }

    /// The album `id`'s page.
    private static func isAlbum(_ route: AppRoute, _ id: String) -> Bool {
        if case .album(let shown) = route { return shown.id == id }
        return false
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
        // (R10) the Mac's Edit album let go before its page goes, so its session ends below, once the session has moved
        // on - as the sheet's does
        let asked = macEditAsked
        macEditAsked = nil
        macEdit = nil
        macEditHolds = false
        library.removeAll()
        search.removeAll()
        requests.removeAll()
        you.removeAll()
        nowPlayingShown = false
        eqImportSheet = false
        eqFileChoosing = false
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
        manualSearchWanted = false
        macLibraryPage = nil
        // (R7) the dock's Get over before the panel is put away: its search let go, nothing picked for the next person
        endSources()
        macPanel = nil
        // (slice 6's review) Needs a look's session over - once the session has moved on, so nothing is noted, read or
        // asked for the next person
        editor?.queue?.editorClosed()
        asked?.queue?.editorClosed()
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
                // by its id: a page moved to an album's new id (AppNavigation.albumMoved) is that album's page afresh.
                // (The Mac app, slice 3) The album's page, an artist's and the album you don't have centred at a
                // readable width in the desktop frame (Platform's readableOnMac - the iPhone's page as before)
                case .album(let album): AlbumView(route: album).id(album.id).readableOnMac()
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
                case .artist(let artist): ArtistView(route: artist).readableOnMac()
                case .artists(let scope): ArtistsScreen(scope: scope)
                case .allSongs: SongsScreen()
                case .group(let group): GroupView(route: group).readableOnMac()
                case .mbArtist(let artist): MBArtistView(route: artist).readableOnMac()
                case .topSongs(let artist): TopSongsScreen(route: artist).readableOnMac()
                case .similarArtists(let artist): SimilarArtistsScreen(route: artist).readableOnMac()
                // (the Mac app, slice 7) Manage's pages at the same readable width - the web's desktop draws Needs a
                // look, Server settings, the event log and Library care so - their lists' rows never a window wide
                case .chooseFolder: ChooseFolderScreen().readableOnMac()
                case .needsALook: NeedsLookScreen().readableOnMac()
                case .libraryCare: LibraryCareScreen().readableOnMac()
                case .heldByNobody: HeldByNobodyScreen().readableOnMac()
                case .serverSettings: ServerSettingsScreen().readableOnMac()
                case .serverSettingsGroup(let id): ServerSettingsGroupScreen(id: id).readableOnMac()
                case .eventLog: EventLogScreen().readableOnMac()
                case .changePassword: ChangePasswordScreen()
                case .people: PeopleScreen().readableOnMac()
                case .person(let id): PersonScreen(id: id).readableOnMac()
                }
            }
            .clearsPlayer()
            .showsOfflineBanner()
            .toolbar(.hidden, for: .tabBar)
        }
    }
}
