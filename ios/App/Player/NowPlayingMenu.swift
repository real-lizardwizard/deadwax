import DeadwaxCore
import SwiftUI

/// Now Playing's ••• (app/ActionMenu.tsx): Info, Add to a playlist… (Phase 4, slice 2 - the song playing, into one of
/// your playlists: the picker opens over Now Playing; left out while deadwax can't be reached), and Go to album for a
/// song that names its album - left out, not greyed, for one that doesn't. The web's pin isn't here. The button's name says
/// what the menu holds (NowPlayingWords.more). A SwiftUI Menu on the button, opened from it, as the album page's •••
/// are (QueueMenu): it was a confirmationDialog on the button until the queue menus moved, and a menu has no Cancel
/// row - a tap anywhere else closes it. The order is fixed, Info first (after the speed's line, when it shows).
///
/// Phase 2 (phase2-downloads.md 4.1): a second section - the song playing's download items, and Download the Queue
/// (Download Up Next until R3's "Queue on both") for every song from the one playing to the queue's end that isn't on
/// this phone or didn't download, offered for two or more (one is "Download") and never during a library's shuffle
/// (that queue is your whole library; keeping it on the phone is Phase 3's own setting). Each is said over Now Playing
/// ("Downloading: Roads", "Downloading 23 songs from the Queue", "Removed from this phone: Roads"), which has no mark to
/// change. Every item carries its symbol.
///
/// The EQ (eq.md 3.1, app 0.5): a last section, one item - "EQ", `slider.vertical.3`, the output now's short setting
/// as its subtitle ("Off", "Bass Boost") - opening the EQ, as a page. "EQ", not "EQ…": it opens a page, as Info does.
/// (The redesign, R3) Not on the phone, where it left the menu for Now Playing's bottom row (`onEQ` nil): the Mac's
/// bar keeps it, opening the side panel's EQ tab.
///
/// The speed (app 0.7, notes/ios-specs/turntable.md 5.1): off 1x on the cover at the accessibility sizes, where the
/// chip isn't drawn, a first section of one item - "Speed 1.25x - back to normal speed", `speedometer` - the chip's
/// action.
///
/// Start Radio (Last.fm, slice A3 - deadwax-plans/lastfm.md 3.5): after Go to album, for the song playing - a new queue
/// of it, played from its start in the tap (PlayerModel.startRadio), similar songs of your library after it. Left out
/// while Last.fm isn't on and while deadwax can't be reached; the button's name says so when it is in (", start radio").
struct NowPlayingMenu: View {
    /// The song playing names its album: Go to album is in the menu.
    let hasAlbum: Bool
    /// The menu says the speed, the chip not drawn.
    let saysSpeed: Bool
    let onInfo: () -> Void
    /// The EQ - nil leaves it out (R3: the phone's, which Now Playing's bottom row has).
    let onEQ: (() -> Void)?
    /// Add to a playlist… - nil leaves it out (deadwax out of reach).
    let onPlaylist: (() -> Void)?
    let onAlbum: () -> Void

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let song = player.current.map { player.song(for: $0) ?? Song(queued: $0.track) }
        let upNext = player.songsFromCurrent
        let upNextCount = downloads.isOpen ? downloads.upNextCount(upNext, paged: player.paged != nil) : nil
        //? (Last.fm, slice A3) Start Radio for the song playing: while Last.fm is on and deadwax can be reached
        let radio = song != nil && reachability.online && server.access.lastfm == .on
        Menu {
            if saysSpeed {
                Section {
                    Button(TurntableWords.menuBackToNormal(player.speed), systemImage: "speedometer") {
                        player.setSpeed(PlaySpeed.normal)
                    }
                }
            }
            Button(NowPlayingWords.info, systemImage: DownloadWords.infoSymbol, action: onInfo)
            if let onPlaylist {
                Button(PlaylistWords.addToAPlaylistRow, systemImage: PlaylistWords.addSymbol,
                       action: onPlaylist)
            }
            if hasAlbum {
                Button(NowPlayingWords.goToAlbum, systemImage: DownloadWords.goToAlbumSymbol, action: onAlbum)
            }
            if radio, let song {
                Button(LastfmWords.startRadio, systemImage: LastfmWords.startRadioSymbol) {
                    player.startRadio(song)
                }
            }
            if let song {
                DownloadMenuSection(songs: [song], name: song.title ?? "",
                                    downloaded: { DownloadWords.downloadingSong($0.title ?? PlayerWords.untitled) })
                if let upNextCount {
                    Section {
                        Button(DownloadWords.downloadUpNext, systemImage: DownloadWords.downloadSymbol) {
                            downloadUpNext(upNext)
                            player.say(DownloadWords.downloadingUpNext(upNextCount))
                        }
                    }
                }
            }
            if let onEQ {
                Section {
                    Button(action: onEQ) {
                        Label {
                            Text(EQWords.nowPlaying)
                            Text(eq.now.short)
                        } icon: {
                            Image(systemName: "slider.vertical.3")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Typeface.symbol(.title3))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        // drawn as the plain button it was (no tint): a button-styled menu with .buttonStyle, as Apple pairs them
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(NowPlayingWords.more(hasAlbum: hasAlbum, download: downloads.isOpen, eq: onEQ != nil,
                                                 playlist: onPlaylist != nil, radio: radio))
    }

    /// Download the Queue: each song from the one playing on that isn't here or didn't download, asked for as a song.
    private func downloadUpNext(_ songs: [Song]) {
        let states = songs.map { downloads.state($0.id) }
        downloads.download(songs: DownloadChoice.asked(by: states).map { songs[$0] })
    }
}

/// The album a queue entry goes to, from Now Playing's byline, its ••• and Info's album card (App.tsx goToAlbum):
/// the album as its page last loaded it, when the queue was played from it - else a stub of what the entry knows
/// (its id, its album's name and its cover), which the page draws while the album loads.
@MainActor
enum PlayedAlbum {
    static func route(id: String?, track: QueueTrack, player: PlayerModel) -> AlbumRoute? {
        guard let id, !id.isEmpty else { return nil }
        if let album = player.playedAlbum(id: id) { return AlbumRoute(album) }
        return AlbumRoute(id: id, name: track.album.isEmpty ? nil : track.album, coverArt: track.coverArt)
    }

    static func route(_ track: QueueTrack, player: PlayerModel) -> AlbumRoute? {
        route(id: track.albumId, track: track, player: player)
    }
}
