import DeadwaxCore
import Foundation
import Observation

/// One album page's state (screens.md 4): the album's answer, the id bridge's (only with a library of your own, D12),
/// what this page just did with Add or Remove, and the ask out. Every rule is Core's - Whose (whose it is, the badge,
/// the mine block and when each is drawn), DiscHeadings, AlbumPageLines, QueuePick, AlbumGone, AddRelease - this keeps
/// the answers, makes the requests and hands the page what the rules say of them.
///
/// Phase 2 (phase2-downloads.md 3.7): an album with songs on this phone is drawn from the answer kept with them at once -
/// online or not - and deadwax is asked behind it; its answer replaces the kept one and is kept again. While deadwax
/// can't be reached nothing is asked (the page draws what it has, and asks once deadwax is back); the mine block, which
/// needs deadwax, isn't drawn, and the badge is the kept album's own. An album deadwax no longer has, with songs of it
/// here, keeps the kept answer drawn - it still plays what is here.
///
/// Only the newest answer draws (AlbumPage.tsx's two latestOnly): each ask takes the next number, and an answer for
/// an older one is dropped; the page's `.task` is cancelled when the page goes, which calls its requests off. What is
/// in hand is kept while the page is covered and shown again (a NavigationStack re-runs the task on the way back), so
/// only what isn't in hand is asked again then. A pull to refresh asks both afresh and draws over what is on screen,
/// as the web's refresh after an edit does: a refresh that fails keeps what is drawn.
@MainActor
@Observable
final class AlbumModel {
    /// Navidrome's album id, and what opened the page (drawn while the album loads).
    let route: AlbumRoute

    /// The album's answer, with its songs; nil until it comes, and when it is gone.
    private(set) var album: Album?
    /// The album's load failed (not gone): said through ErrorNote, `gone: ErrorWords.albumGone`.
    private(set) var failure: (any Error)?
    /// Navidrome answered `{}`: the album isn't there (AlbumGone).
    private(set) var empty = false
    /// The id bridge's answer (`GET /store/album?navidrome_id=`), asked only when `personal`.
    private(set) var store: StoreAlbum?
    /// The bridge failed: whose it is can't be told from it.
    private(set) var storeFailed = false
    /// A library of the person's own (`Access.hasLibrary`) as the page was loaded: Whose's `personal`, and whether the
    /// bridge is asked at all (D12).
    private(set) var personal = false
    /// What this page's last Add or Remove did, once deadwax took it (whose.ts's `changed`): said at once, over the
    /// album's own `starred` from before it.
    private(set) var changed: AlbumMine.Change?
    /// An Add or Remove is out (the button says "Adding…" / "Removing…" and takes no second tap).
    private(set) var busy = false
    /// deadwax refused the last Add or Remove: said under the button in ErrorWords' words, and announced.
    private(set) var refused: (any Error)?
    /// One more each time an Add or Remove is answered, taken or refused: the page moves VoiceOver to what it says.
    private(set) var answered = 0
    /// The album is drawn from the answer this phone kept with its downloads; deadwax's own replaces it as it comes.
    private(set) var fromPhone = false
    /// deadwax says the album is gone (a 404 or `{}`), and songs of it are on this phone: the kept answer stays drawn.
    private(set) var goneButHere = false
    /// deadwax can be reached (the page's Reachability, set as it draws): while not, nothing is asked, the mine block
    /// isn't drawn and the badge is the album's own `starred`.
    var online = true

    /// Who and which album the answers in hand are for (the page's task key): another resets everything.
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var albumAsks = 0
    @ObservationIgnored private var storeAsks = 0
    /// The album its levels were warmed for (once per album, as the web's effect on `album?.id`).
    @ObservationIgnored private var warmed: String?

    init(route: AlbumRoute) {
        self.route = route
    }

    // MARK: what the page draws, by Core's rules

    /// The album's songs, in Navidrome's order ([] until they come).
    var songs: [Song] { album?.song ?? [] }
    /// The album is gone - a `{}` answer or a 404 (AlbumGone): the page draws what opened it and the gone line alone.
    var gone: Bool { AlbumGone.isGone(empty: empty, failure: failure) }
    /// Whose.albumMine's `albumFailed`: the album's answer came and gave no album.
    private var albumFailed: Bool { failure != nil || empty }

    /// The hero's title, artist and cover: the album's own once it has answered, else what opened the page
    /// (AlbumPage.tsx's `shown = album ?? preview`).
    var name: String { album.map { $0.name ?? "" } ?? route.name ?? "" }
    var artist: String { album.map { $0.artist ?? "" } ?? route.artist ?? "" }
    var coverArt: String? { album.map(\.coverArt) ?? route.coverArt }
    /// (Phase 4, slice 4) The artist line's link to the artist's page (ArtistLink, AlbumPage.tsx's): the album's own
    /// artist id once it has answered, else the opener's - pending while it might still become one, plain once no
    /// answer is coming (the load failed or found nothing, or deadwax can't be reached and nothing of it is here).
    var artistLink: ArtistLink {
        ArtistLink.of(album: album, opened: route.artistId, name: artist, coming: !albumFailed && online)
    }
    /// The line under the artist: genre, year and the songs' one format (the opener's genre and year until the album
    /// answers, so the line only gains the format when it does).
    var meta: String {
        if let album { return AlbumPageLines.meta(album) }
        return AlbumPageLines.meta(genre: route.genre, year: route.year, format: nil)
    }
    /// The title a step smaller over 60 letters (titles.ts isLongTitle).
    var longTitle: Bool { Format.isLongTitle(name) }

    /// Whose it is, and what is offered (Whose.albumMine, wired as AlbumPage.tsx wires it).
    var mine: AlbumMine {
        // deadwax out of reach: the bridge can't be asked, so whose it is is the album's own `starred` (as when the
        // bridge fails)
        Whose.albumMine(personal: personal, album: album, albumFailed: albumFailed, store: store,
                        storeFailed: storeFailed || (!online && store == nil), changed: changed)
    }
    /// The badge is drawn (its place held, unseen, until then) - never for an album that is gone.
    var badgeShown: Bool {
        !gone && !goneButHere
            && Whose.badgeShown(mine, storeDone: store != nil || storeFailed || !online, bridgeAsked: personal)
    }
    /// The unseen placeholder holds the mine block's place.
    var placeholderShown: Bool {
        !gone && !goneButHere && online && Whose.placeholderShown(mine, albumIn: album != nil, refused: refused != nil)
    }
    /// The mine block is drawn - only while deadwax can be reached: it acts through deadwax, and nothing stale is shown
    /// as if it could.
    var mineBlockShown: Bool { !gone && !goneButHere && online && Whose.mineBlockShown(mine, refused: refused != nil) }

    /// The heading above each song, or nil (DiscHeadings: "Disc 2 · <title>", only on an album with more than one
    /// disc or a disc title).
    var headings: [String?] { album.map(DiscHeadings.headings) ?? [] }
    /// Under the songs: "12 songs, 48 min".
    var footer: String { AlbumPageLines.footer(songs) }
    /// The album's own •••: all its songs as an album - nil until they are in.
    var albumPick: QueuePick<Song>? { album.flatMap { QueuePick.album($0) } }

    // MARK: asking

    /// The page's task: the album and - with a library of your own - the bridge, at once, each as it isn't in hand;
    /// the album's levels warmed as its songs come (PlayerModel.albumShown: AlbumPageLines.warms decides). `key` is
    /// who and which album (the task's id): another than the answers in hand are for drops them all first.
    func load(key: String, client: DeadwaxClient?, personal: Bool, player: PlayerModel, downloads: DownloadModel) async {
        if key != self.key {
            self.key = key
            album = nil
            failure = nil
            empty = false
            store = nil
            storeFailed = false
            changed = nil
            refused = nil
            warmed = nil
            fromPhone = false
            goneButHere = false
        }
        self.personal = personal
        // the answer kept with its downloads, drawn at once - online or not
        if album == nil, let kept = downloads.keptAlbum(route.id) {
            album = kept
            fromPhone = true
        }
        // nothing that needs deadwax is asked while it can't be reached: the page asks again once it is back
        guard let client, online else { return }
        let wantsAlbum = (album == nil || fromPhone) && !empty && !goneButHere
        let wantsStore = personal && store == nil
        await withTaskGroup(of: Void.self) { group in
            if wantsAlbum { group.addTask { await self.askAlbum(client, player: player, downloads: downloads, again: false) } }
            if wantsStore { group.addTask { await self.askStore(client, again: false) } }
        }
    }

    /// A pull to refresh: both asked afresh, drawn over what is on screen (what the page last did is told by deadwax's
    /// answer now); a failure keeps what is drawn - and with nothing drawn, says it.
    func refresh(client: DeadwaxClient?, player: PlayerModel, downloads: DownloadModel) async {
        guard let client, online else { return }
        changed = nil
        refused = nil
        let asksStore = personal
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.askAlbum(client, player: player, downloads: downloads, again: true) }
            if asksStore { group.addTask { await self.askStore(client, again: true) } }
        }
    }

    private func askAlbum(_ client: DeadwaxClient, player: PlayerModel, downloads: DownloadModel, again: Bool) async {
        albumAsks += 1
        let asked = albumAsks
        do {
            let (found, body) = try await client.albumAnswered(id: route.id)
            guard asked == albumAsks else { return }
            failure = nil
            if let found {
                album = found
                empty = false
                fromPhone = false
                goneButHere = false
                downloads.albumAnswered(found, body: body)
                if warmed != found.id {
                    warmed = found.id
                    player.albumShown(found)
                }
            } else if keepsKept(downloads) {
                goneButHere = true
            } else {
                album = nil
                empty = true
                player.albumGone(id: route.id)
            }
        } catch {
            guard asked == albumAsks, !APIFailure.isCancellation(error) else { return }
            if AlbumGone.isGone(empty: false, failure: error), keepsKept(downloads) {
                goneButHere = true
                return
            }
            // a refresh that fails keeps the album drawn - and so does an ask behind the kept answer
            if again || fromPhone, album != nil { return }
            failure = error
            if AlbumGone.isGone(empty: false, failure: error) { player.albumGone(id: route.id) }
        }
    }

    /// deadwax says the album is gone: the kept answer stays drawn while songs of it are on this phone.
    private func keepsKept(_ downloads: DownloadModel) -> Bool {
        guard let album, fromPhone || downloads.keptAlbum(album.id) != nil else { return false }
        return downloads.here(album.song ?? []).count > 0
    }

    private func askStore(_ client: DeadwaxClient, again: Bool) async {
        storeAsks += 1
        let asked = storeAsks
        do {
            let answer = try await client.storeAlbum(navidromeID: route.id)
            guard asked == storeAsks else { return }
            store = answer
            storeFailed = false
        } catch {
            guard asked == storeAsks, !APIFailure.isCancellation(error) else { return }
            // a refresh that fails keeps what the bridge said before (AlbumPage.tsx: `if (!again) setStoreFailed`)
            if again, store != nil { return }
            storeFailed = true
        }
    }

    // MARK: Add and Remove

    /// Add to my library (`POST /me/library/add`, the pressing the bridge found - AddRelease.from) or Remove from my
    /// library (`POST /me/library/remove`, by Navidrome's id). Taken: `changed` says so at once, and the Library is
    /// told your library changed (LibraryModel.libraryChanged: Your albums and the New marks asked again - the web's
    /// announceAddedToLibrary / announceRemovedFromLibrary, which useMyLibrary.ts and useYourAlbums.ts hear) - and so are
    /// the downloads, whose library followed is checked at once (phase3-autodownload.md 2.2's `changedHere`). Refused:
    /// `refused`, and `changed` stays as it was. Not a page's request - it runs to its answer even if the page goes.
    func change(_ action: AlbumMine.Action, client: DeadwaxClient?, library: LibraryModel,
                downloads: DownloadModel) async {
        guard !busy, let client else { return }
        busy = true
        refused = nil
        do {
            switch action {
            case .add:
                _ = try await client.addToLibrary(AddRelease.from(store: store, artistName: artist, albumName: name))
            case .remove:
                _ = try await client.removeFromLibrary(navidromeID: route.id)
            }
            busy = false
            let done: AlbumMine.Change = action == .add ? .added : .removed
            changed = done
            answered += 1
            library.libraryChanged()
            downloads.libraryChanged(album: route.id, removed: action == .remove)
        } catch {
            busy = false
            if APIFailure.isCancellation(error) { return }
            refused = error
            answered += 1
        }
    }
}
