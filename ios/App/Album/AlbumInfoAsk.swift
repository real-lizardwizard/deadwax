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
///  - then those folders' files (GET /library/tracks?album=, the track viewer's route), at most AlbumInfo.foldersRead,
///    AlbumInfo.foldersAtOnce at a time - each read takes one of the server's threads and opens every file of the
///    folder: the media, catalogue number, barcode, country and status only the tags hold.
///
/// Held back for each other until every one has answered or AlbumInfoWords.settleSeconds has gone, so the sheet doesn't
/// grow under a finger; after that each lands as it comes. What failed is kept, for the sheet to say (album, bridge,
/// files - "couldn't be asked" is never drawn as "says nothing").
///
/// Called in a task the view starts for one album (`.task(id:)`): another album, deadwax going out of reach, or the
/// sheet going cancels it, and nothing more of it lands - the view marks what it last put as cut short.
enum AlbumInfoAsk {
    /// What deadwax has said of the album so far.
    struct Said {
        /// The album as getAlbum answers it now - nil until it has, or when it couldn't be had.
        var album: Album?
        var extras: AlbumExtras?
        /// getAlbum failed: its error, for ErrorWords.
        var albumFailure: (any Error)?
        /// getAlbum answered that Navidrome has no album by the id.
        var albumMissing = false
        var store: StoreAlbum?
        /// The bridge failed: its error.
        var storeFailure: (any Error)?
        /// Every folder's files that were read, in the bridge's order - nil until one has been.
        var files: [AlbumFile]?
        /// Every folder's read failed: the first one's error.
        var filesFailure: (any Error)?
        /// Something hasn't answered yet: the album, the bridge or a folder.
        var reading = true
        /// The asking stopped before everything had answered (deadwax out of reach, the sheet going).
        var cut = false

        /// Everything asked has answered, and nothing failed: what is drawn is all there is.
        var complete: Bool {
            !reading && !cut && albumFailure == nil && !albumMissing && storeFailure == nil && filesFailure == nil
        }
    }

    private enum Landed: Sendable {
        case album(Album?, AlbumExtras?, (any Error)?)
        case store(Result<StoreAlbum, any Error>)
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
        var waiting: [(index: Int, folder: String)] = []
        var running = 0
        var read: [Int: [AlbumFile]] = [:]
        var failures: [Int: any Error] = [:]
        await withTaskGroup(of: Landed.self) { group in
            group.addTask {
                do {
                    let answered = try await client.albumAnswered(id: albumID)
                    return .album(answered.album, try? JSONDecoder().decode(AlbumExtras.self, from: answered.body), nil)
                } catch {
                    return .album(nil, nil, error)
                }
            }
            group.addTask {
                do {
                    return .store(.success(try await client.storeAlbum(navidromeID: albumID)))
                } catch {
                    return .store(.failure(error))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(AlbumInfoWords.settleSeconds))
                return .settled
            }
            while let landed = await group.next() {
                if Task.isCancelled { return }
                switch landed {
                case .album(let album, let extras, let failure):
                    out -= 1
                    said.album = album
                    said.extras = extras
                    said.albumFailure = failure
                    said.albumMissing = failure == nil && album == nil
                case .store(let result):
                    out -= 1
                    switch result {
                    case .success(let store):
                        said.store = store
                        //? the files are asked for as soon as the bridge names their folders
                        folders = AlbumInfo.foldersToRead(store)
                        waiting = Array(folders.enumerated()).map { (index: $0.offset, folder: $0.element) }
                        out += folders.count
                    case .failure(let error):
                        said.storeFailure = error
                    }
                case .files(let index, let result):
                    out -= 1
                    running -= 1
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
                //? the next folders, AlbumInfo.foldersAtOnce at a time
                while running < AlbumInfo.foldersAtOnce, !waiting.isEmpty {
                    let next = waiting.removeFirst()
                    running += 1
                    group.addTask {
                        do {
                            return .files(next.index, .success(try await client.albumFiles(folder: next.folder)))
                        } catch {
                            return .files(next.index, .failure(error))
                        }
                    }
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
