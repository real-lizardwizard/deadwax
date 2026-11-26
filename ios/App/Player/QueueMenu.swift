import DeadwaxCore
import SwiftUI

/// What a ••• queues: one song (a row's - queued as a song) or an album's songs (the album's own - queued as an album),
/// always in hand (Core's QueuePick), and the album they are from, which the player remembers as just added (Info,
/// and the album opening at once from Up Next). A playlist's songs (Phase 4) name no album: each is queued with its own
/// (PlaylistPlay), and the playlist's ••• for all of them offers no download items until a playlist downloads as one
/// (slice 3 - phase4-library.md question 7).
struct QueueMenuRequest {
    let pick: QueuePick<Song>
    /// The album the songs are from - nil for a playlist's, each song with its own.
    let album: Album?
    /// The album is gone from the collection (its songs on this phone still play): no Download.
    var gone = false
    /// The download items under Add to Queue.
    var offersDownload = true
    /// (Phase 4, slice 3) The whole playlist the songs are - its page's bar •••: the playlist's own download items
    /// (PlaylistDownloadMenuSection) in place of the songs'.
    var playlist: PlaylistWithSongs?
    /// (Phase 8, slice 1) The album page's bar •••, for someone the web gives the album's Edit (Managing.albumEdit):
    /// "Edit album", which opens Edit album over the tabs. (Phase 7's Edit in the web app was here.)
    var editAlbum: (@MainActor () -> Void)?
    /// (Album info) The album page's bar •••: "Album info", which opens the album's sheet of everything known of it.
    var albumInfo: (@MainActor () -> Void)?
    /// (Pull to shuffle on an album's and a playlist's page) The page's bar •••: "Refresh" - the page asked again now
    /// or, while deadwax can't be reached, whether it is back - as the Library's ••• has it, the page's pull being the
    /// shuffle's now.
    var refresh: (@MainActor () -> Void)?
    /// (R5) The album page's own •••: a Download asked for from it - the page announces its end, as it did for the
    /// download control the ••• took the place of.
    var downloadAsked: (@MainActor () -> Void)?
    /// (Last.fm, slice A3) The whole of a playlist (its bar's •••, its right-click): never one song's, whatever it holds.
    var wholeList = false

    /// (A3) The song a one-song ••• is for - Start Radio's seed. Nil for an album's own •••, a playlist's, and any
    /// other of more than one song.
    var radioSong: Song? {
        pick.queuedAs == nil && !wholeList && pick.tracks.count == 1 ? pick.tracks.first : nil
    }
}

extension QueueMenuRequest {
    /// An album's own ••• (the album page's bar, screens.md 4): the whole album, as an album, with Album info - and
    /// (Phase 8, slice 1) Edit album, over the tabs, for someone the web gives the album's Edit (Managing.albumEdit).
    /// nil until the album's songs are in. (The Mac app, slice 2) The one list: the page's bar draws it, adding its
    /// Refresh, and on the Mac a right-click on the album's tile or row draws it as it is (AlbumRightClick), so the two
    /// never offer different things.
    @MainActor
    static func album(_ album: Album, gone: Bool, permissions: Set<Access.Permission>, navigation: AppNavigation,
                      info: @escaping @MainActor () -> Void) -> QueueMenuRequest? {
        guard let pick = QueuePick.album(album) else { return nil }
        var request = QueueMenuRequest(pick: pick, album: album, gone: gone)
        request.albumInfo = info
        if Managing.albumEdit(permissions).shown {
            request.editAlbum = {
                navigation.editAlbum(AlbumEditRequest(target: .album(AlbumEdit.Subject(album))))
            }
        }
        return request
    }

    /// A playlist's own ••• (its page's bar, Phase 4): the whole playlist, as songs, with the playlist's own download
    /// items (slice 3) - nil until its songs are in. (The Mac app, slice 2) The page's bar draws it, adding its Refresh,
    /// and on the Mac a right-click on the playlist's row (PlaylistRightClick).
    static func playlist(_ answer: PlaylistWithSongs?, name: String, songs: [Song]) -> QueueMenuRequest? {
        guard let pick = PlaylistPlay.pick(name: name, songs: songs) else { return nil }
        var request = QueueMenuRequest(pick: pick, album: nil, playlist: answer)
        request.wholeList = true
        return request
    }
}

/// The queue menu (screens.md 5; the web's app/QueueMenu.tsx): Add to Queue, opened FROM the ••• tapped - a SwiftUI
/// Menu on the button, as Apple's own ••• are. It was a confirmationDialog on the album page until James's check of 0.2
/// (2): since iOS 26 a confirmation dialog is a popover from the view it is attached to, here the page, so it came up
/// away from the ••• (notes/ios.md, "The ••• menus open from the •••"). Titled with what it queues (QueuePick.title -
/// the song's or the album's name, or "Queue"), as the dialog was. There is no Cancel row: a menu closes with a tap
/// anywhere else (QueuePickWords.cancel stays, the web's word, held to its fixture). The order is fixed
/// (`menuOrder(.fixed)`), so Add to Queue is first whichever way the menu opens.
///
/// ADD TO QUEUE (16 Nov, notes/ios.md "Add to Queue: the swipe, and the menus' one item"; James: "Only Add to Queue"):
/// the one item where Play Next and Play Last were - the web's Play Last (Core's AddToQueue), after the songs already
/// added, so the first added plays next. The web app keeps both. Whether it is offered, and what it adds, is Core's
/// AddToQueue.pick - the very rule a song row's swipe is offered by (AddToQueueSwipe.swift), so a row has the swipe
/// exactly where its ••• has the item.
///
/// It is carried out in its tap, nothing awaited first (the gesture rule - with nothing playing it starts the music):
/// `PlayerModel.addToQueue`, which queues the songs at the level QueuePick.choose says (an album's ••• as an album, a
/// song's as a song), remembers the album, and says the notice (D11, "Added to Queue: Roads") only when the music
/// didn't start from it - when it did, the mini player says so. The menu closes either way.
///
/// Phase 4, slice 2: "Add to a playlist…", after Add to Queue (the web's third, after its two) - the same songs into
/// one of your playlists: the menu closes and the picker opens over the tabs (AppNavigation.playlistPick,
/// PlaylistPicker) with them in hand. It plays nothing. Left out while deadwax can't be reached (a playlist is
/// Navidrome's, written through deadwax) and for an album gone from the collection.
///
/// `request` is nil while there is nothing to queue (the album's songs not in yet): the ••• is then dimmed and opens
/// nothing. The label is the •••, drawn by the caller; its VoiceOver name is the caller's too ("More for Roads").
///
/// Phase 2 (phase2-downloads.md 3.4): a second section under them, the song's or the album's download items
/// (DownloadMenuSection), and every item carries its symbol, as Apple's menus do. While deadwax can't be reached, Add
/// to Queue adds only what is on this phone - and is left out for a song that isn't - while Download stays (it waits
/// for deadwax).
///
/// Phase 4, slice 3: a playlist page's bar ••• (`request.playlist`) has the playlist's own download items instead -
/// Download, Download Again, Remove Download - the same as the control beside it.
///
/// Phase 8, slice 1 (phase8-managing.md 1): an album page's bar ••• (`request.editAlbum`) has "Edit album" in its last
/// section, after Album info - Edit album over the tabs (AppNavigation.albumEdit), the app's own since Phase 7's Edit in
/// the web app. Left out while deadwax can't be reached and for an album gone from the collection, as Add to a playlist
/// is. It plays nothing.
///
/// Album info (notes/ios.md "Album info"): the album page's bar ••• (`request.albumInfo`) has "Album info" in that last
/// section, above Edit album - offline too (it draws what the phone has), and for an album gone from the collection. It
/// plays nothing.
///
/// Refresh (notes/ios.md "Pull to shuffle on an album's and a playlist's page"): an album's and a playlist's bar •••
/// (`request.refresh`) end that last section with "Refresh", as the Library's ••• ends with it - online and off (off,
/// it asks whether deadwax is back). It plays nothing.
///
/// THE REDESIGN, SLICE R5 (notes/ios.md "The redesign, slice R5: an album, Playlists, a playlist"; James's answer 4,
/// "iOS's own menu"): on the phone an album's and a playlist's bar ••• hold Download in the download control's place -
/// the control left the bar - so their download section is headed with the control's own words for the state
/// (AlbumDownloadMenu, PlaylistDownloadMenuSection's `titled`), its items the control's. Edit album is the top row's
/// Edit on the phone (the page's bar clears `editAlbum`); the Mac's right-click keeps it here. Add to Queue stays the
/// one queue item on both: no Play Next or Play Last.
///
/// START RADIO (Last.fm, slice A3 - deadwax-plans/lastfm.md 3.5; notes/ios.md "Last.fm, slice A3"): every one-song •••
/// (`request.radioSong` - a song's row on an album, a playlist, Songs, Search, Top Songs) has "Start Radio" after Add to
/// a playlist… - and so a song's right-click on the Mac, which draws these items. It plays the song at once as a new
/// queue, in the tap (PlayerModel.startRadio: the play first, nothing awaited), and similar songs of your library come
/// after it. Left out while Last.fm isn't on (`access.lastfm`), while deadwax can't be reached, and for an album gone
/// from the collection. Playing needs no permission, so it asks none.
struct QueueMenu<Label: View>: View {
    let request: QueueMenuRequest?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            QueueMenuItems(request: request)
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .disabled(request == nil)
    }
}

/// The ••• menu's items (the Mac app, slice 2): the one list, drawn by the ••• (QueueMenu, above) and - on the Mac - by
/// a right-click on the same row, tile or page (Platform's `macContextMenu`, MacRightClick.swift), so the two can never
/// offer different things. Nothing for a nil request, which leaves a right-click with no menu, as the ••• is dimmed.
struct QueueMenuItems: View {
    let request: QueueMenuRequest?

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(ServerModel.self) private var server

    var body: some View {
        if let request {
            if let pick = AddToQueue.pick(request.pick, online: reachability.online, gone: request.gone,
                                          here: downloads.isHere) {
                Section(request.pick.title) {
                    Button(AddToQueue.words, systemImage: AddToQueue.symbol) {
                        player.addToQueue(pick, album: request.album)
                    }
                    if reachability.online, !request.gone, !request.pick.tracks.isEmpty {
                        Button(PlaylistWords.addToAPlaylistRow, systemImage: PlaylistWords.addSymbol) {
                            navigation.playlistPick = PlaylistPickRequest(PlaylistPick(request.pick))
                        }
                    }
                    if let seed = request.radioSong, reachability.online, !request.gone, server.access.lastfm == .on {
                        Button(LastfmWords.startRadio, systemImage: LastfmWords.startRadioSymbol) {
                            player.startRadio(seed)
                        }
                    }
                }
            }
            if let playlist = request.playlist {
                // (R5) headed as its control's menu is: on the phone the bar's ••• holds Download in the control's place
                PlaylistDownloadMenuSection(answer: playlist, titled: true)
            } else if request.offersDownload {
                DownloadMenuSection(songs: request.pick.tracks,
                                    album: request.pick.queuedAs == .album ? request.album : nil,
                                    gone: request.gone, name: request.pick.title, asked: request.downloadAsked)
            }
            let editAlbum = reachability.online && !request.gone ? request.editAlbum : nil
            if request.albumInfo != nil || editAlbum != nil || request.refresh != nil {
                Section {
                    if let albumInfo = request.albumInfo {
                        Button(AlbumInfoWords.title, systemImage: AlbumInfoWords.symbol) {
                            albumInfo()
                        }
                    }
                    if let editAlbum {
                        Button(EditWords.menuItem, systemImage: EditWords.symbol) {
                            editAlbum()
                        }
                    }
                    if let refresh = request.refresh {
                        // the Library's own Refresh, word and symbol
                        Button(LibrarySwitchWords.refresh, systemImage: "arrow.clockwise") {
                            refresh()
                        }
                    }
                }
            }
        }
    }
}
