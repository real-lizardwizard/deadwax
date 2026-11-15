import DeadwaxCore
import Foundation

/// What Album info asks deadwax for while it is open (notes/ios.md "Album info"), for one album - every one a route the
/// app already had, so the server is unchanged:
///
///  - the album again (GET /navidrome/albums/{id}, getAlbum): the whole album, with every song - Info's album may be a
///    playlist's stub of it - and, read from the same answer, OpenSubsonic's fields the Album model doesn't keep
///    (AlbumExtras: the release types and dates, the version, the genres, the labels);
///  - the id bridge (GET /store/album by Navidrome's id): the release and release group, the store's folders of it, its
///    edition, when deadwax first saw it - asked whether or not there is a library of one's own, unlike the album page's
///    and Info's (D12): it is a user's route either way, and the folders are the only way to the files' own tags;
///  - then each of those folders' files (GET /library/tracks?album=, the track viewer's route), at most
///    AlbumInfo.foldersRead, all at once: the media, catalogue number, barcode, country and status only the tags hold.
///
/// Held back for each other until every one has answered or AlbumInfoWords.settleSeconds has gone, so the sheet doesn't
/// grow under a finger; after that each lands as it comes. A failure leaves its lines out, as everything nobody says
/// is - only the files' failing is said (every folder failed), since what it loses is the sheet's point.
///
/// Called in a task the view starts for one album (`.task(id:)`): another album, or the sheet going, cancels it, and
/// nothing of it lands.
enum AlbumInfoAsk {
    /// What deadwax has said of the album so far.
    struct Said {
        /// The album as getAlbum answers it now - nil until it has, or when it couldn't be had.
        var album: Album?
        var extras: AlbumExtras?
        var store: StoreAlbum?
        /// Every folder's files that were read, in the bridge's order - nil until one has been.
        var files: [AlbumFile]?
        /// Every folder's read failed: the first one's error, for ErrorWords.
        var filesFailure: (any Error)?
        /// Something hasn't answered yet: the album, the bridge or a folder.
        var reading = true
    }

    private enum Landed: Sendable {
        case album(Album?, AlbumExtras?)
        case store(StoreAlbum?)
        case files(Int, Result<[AlbumFile], any Error>)
        case settled
    }

    /// Asks for everything Album info says of `albumID` beyond what the phone has - `put` called with what is known,
    /// once all of it is in or the wait is over, then again as the rest lands.
    @MainActor
    static func ask(albumID: String, client: DeadwaxClient, put: @escaping @MainActor (Said) -> Void) async {
        var said = Said()
        var holding = true
        var out = 2
        var folders: [String] = []
        var read: [Int: [AlbumFile]] = [:]
        var failures: [Int: any Error] = [:]
        await withTaskGroup(of: Landed.self) { group in
            group.addTask {
                guard let answered = try? await client.albumAnswered(id: albumID) else { return .album(nil, nil) }
                return .album(answered.album, try? JSONDecoder().decode(AlbumExtras.self, from: answered.body))
            }
            group.addTask {
                .store(try? await client.storeAlbum(navidromeID: albumID))
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(AlbumInfoWords.settleSeconds))
                return .settled
            }
            while let landed = await group.next() {
                if Task.isCancelled { return }
                switch landed {
                case .album(let album, let extras):
                    out -= 1
                    said.album = album
                    said.extras = extras
                case .store(let store):
                    out -= 1
                    said.store = store
                    //? the files are asked for as soon as the bridge names their folders
                    folders = AlbumInfo.foldersToRead(store)
                    out += folders.count
                    for (index, folder) in folders.enumerated() {
                        group.addTask {
                            do {
                                return .files(index, .success(try await client.albumFiles(folder: folder)))
                            } catch {
                                return .files(index, .failure(error))
                            }
                        }
                    }
                case .files(let index, let result):
                    out -= 1
                    switch result {
                    case .success(let files): read[index] = files
                    case .failure(let error): failures[index] = error
                    }
                    said.files = read.isEmpty ? nil : read.keys.sorted().flatMap { read[$0] ?? [] }
                    said.filesFailure = read.isEmpty && failures.count == folders.count
                        ? failures.keys.sorted().first.flatMap { failures[$0] } : nil
                case .settled:
                    if !holding { continue }
                    holding = false
                    said.reading = out > 0
                    put(said)
                    continue
                }
                said.reading = out > 0
                if !holding {
                    put(said)
                } else if out == 0 {
                    holding = false
                    put(said)
                    //? all in: the wait has nothing left to hold back
                    group.cancelAll()
                }
            }
        }
    }
}
