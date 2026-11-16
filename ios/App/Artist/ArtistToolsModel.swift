import DeadwaxCore
import Observation
import SwiftUI
import UIKit

/// What the artist tools need, as an artist page is now (ArtistView.managing): the person's permissions, the library's
/// names for the artist and whether deadwax's word on them is in, the folder Artist images writes to (or why none can
/// be), the names Move albums moves, their name now, and each name's albums' size (how long a move is given).
struct ArtistManaged {
    let may: Managing.ArtistManaging
    var names: [String] = []
    var known = false
    var folder = ArtistManage.ImagesFolder(name: nil, reason: nil)
    var folderSummary: ArtistSummary?
    var moveNames: [String] = []
    var current: String?
    var sizes: [String: Double] = [:]

    /// The folder holding the square the page draws in place of Navidrome's picture - once Artist images wrote to that
    /// folder while the app runs (`written`, ArtistFolderVersions), or where Navidrome has none (the web's `square`) -
    /// nil: Navidrome's.
    func square(navidrome: String?, written: (String) -> Int) -> String? {
        guard let summary = folderSummary, let path = summary.path, !path.isEmpty,
              !(summary.art["thumb"] ?? "").isEmpty, written(path) > 0 || navidrome == nil else { return nil }
        return path
    }
}

/// What an artist page knows for its artist tools (Phase 8, slice 5 - phase8-managing.md 4; the web's ArtistPage.tsx
/// "as the main page had it"): the names the library files their albums under (ArtistManage.libraryNames over
/// `/library/owned`, which the page reads already) and deadwax's word on each (`GET /library/artist?name=`, asked
/// together, only the newest round landing), from which the folder Artist images writes to (imagesFolder) and the
/// names Move albums moves (namesToMove). Asked only for someone the ••• has something for, and only while deadwax is
/// in reach; nothing is kept past the page.
@MainActor
@Observable
final class ArtistToolsModel {
    /// deadwax's word on each name, in the names' order - for the names `summaryKey` says.
    private(set) var summaries: [(name: String, said: ArtistManage.Said)] = []
    /// The names (joined) the summaries answer - nil before any answer.
    private(set) var summaryKey: String?
    private(set) var asking = false

    @ObservationIgnored private var asks = 0
    /// The names as last made, with what they were made from: `/library/owned` reads every folder of the library.
    @ObservationIgnored private var namesMade: (owned: Int, who: ArtistManage.Who, names: [String])?

    /// libraryNames, made again only when the owned index or who they are changed.
    func names(_ index: OwnedIndex?, version: Int, who: ArtistManage.Who) -> [String] {
        if let made = namesMade, made.owned == version, made.who == who { return made.names }
        let names = ArtistManage.libraryNames(index, who: who)
        namesMade = (version, who, names)
        return names
    }

    static func key(_ names: [String]) -> String { names.joined(separator: "\n") }

    /// The summaries for `names` are in hand (or every one of them couldn't be read).
    func known(_ names: [String]) -> Bool { summaryKey == Self.key(names) }

    /// The summaries, for `names` as they are now - none for names since changed (the web's `summaryMap`).
    func said(for names: [String]) -> [(name: String, said: ArtistManage.Said)] {
        known(names) ? summaries : []
    }

    /// A name's summary, when deadwax answered for it.
    func summary(_ name: String?, names: [String]) -> ArtistSummary? {
        guard let name else { return nil }
        for one in said(for: names) where one.name == name {
            if case .answered(let summary) = one.said { return summary }
        }
        return nil
    }

    /// Every name asked (as the web's summaries effect): only when they changed, or `again` (after a write, a pull,
    /// deadwax back). Not one answered: each said as unread - what was said of the same names before staying.
    func summarize(_ names: [String], client: DeadwaxClient?, online: Bool, again: Bool = false) async {
        let key = Self.key(names)
        if key == summaryKey && !again { return }
        guard !names.isEmpty else {
            asks += 1
            asking = false
            summaries = []
            summaryKey = key
            return
        }
        guard online, let client else { return }
        asks += 1
        let asked = asks
        asking = true
        let answers = await withTaskGroup(of: (Int, ArtistManage.Said?).self) { group in
            for (at, name) in names.enumerated() {
                group.addTask {
                    do {
                        let found = try await client.libraryArtist(name: name)
                        return (at, found.map { ArtistManage.Said.answered($0) } ?? .unread)
                    } catch {
                        return (at, APIFailure.isCancellation(error) ? nil : .unread)
                    }
                }
            }
            var said = [ArtistManage.Said?](repeating: nil, count: names.count)
            for await (at, one) in group { said[at] = one }
            return said
        }
        guard asked == asks else { return }
        asking = false
        // the page gone (a cancellation): nothing said of anything
        if answers.contains(where: { $0 == nil }) { return }
        let said = answers.compactMap { $0 }
        let none = said.allSatisfy { $0 == .unread }
        if none && summaryKey == key { return }
        summaries = zip(names, said).map { (name: $0, said: $1) }
        summaryKey = key
    }
}

/// How many times Artist images (or a Move, which carries the pictures along) wrote each artist folder's pictures, or
/// may have, while the app runs - by server and folder. The folder pictures' cache keys on it, so a picture replaced
/// under the same file name is asked again everywhere it is drawn, whichever sheet or page wrote it and however they
/// came and went; it lives as long as ArtistPictureCache.shared. The page draws its square from the folder once its
/// folder's count is past nought (the web's `square`): Navidrome keeps its own copy of the picture it had.
@MainActor
@Observable
final class ArtistFolderVersions {
    static let shared = ArtistFolderVersions()

    private var counts: [String: Int] = [:]

    private init() {}

    private static func key(_ client: DeadwaxClient, path: String) -> String { "\(client.server.key)|\(path)" }

    func version(_ client: DeadwaxClient, path: String) -> Int { counts[Self.key(client, path: path)] ?? 0 }

    /// The folder's pictures were written, or may have been.
    func wrote(_ client: DeadwaxClient, path: String) {
        guard !path.isEmpty else { return }
        counts[Self.key(client, path: path), default: 0] += 1
    }
}

/// A picture the artist tools draw - a candidate's preview through deadwax's relay (`GET /library/artist/picture`), or
/// one in their folder (`GET /library/artist/art`) - kept in memory by the server and the address (and, for their
/// folder, its count of writes - ArtistFolderVersions), never on disk. One fetch however many views wait, at most
/// `atOnce` at a time (the relay takes six at once and refuses past 64 waiting); a relay that is busy (503) asked again
/// twice, a moment apart. One that couldn't be had answers deadwax's words, kept a minute. A fetch nobody waits for any
/// more - its views gone with the grid or the sheet - is cancelled, or never sent once its turn comes, and nothing is
/// kept of it.
@MainActor
final class ArtistPictureCache {
    enum Answer: Sendable {
        case image(UIImage)
        /// Nothing to draw: deadwax's words for why (nil: none at all - a folder with no such picture).
        case none(String?)
    }

    static let shared = ArtistPictureCache()
    static let atOnce = 4

    private let images = NSCache<NSString, UIImage>()
    /// Each fetch under way, and how many views wait for it.
    private var loading: [String: (task: Task<Answer, Never>, waiters: Int)] = [:]
    private var failed: [String: (at: Date, words: String?)] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private init() {
        images.totalCostLimit = 32 * 1024 * 1024
    }

    func cached(_ key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    static func relayKey(_ client: DeadwaxClient, url: String) -> String { "\(client.server.key)|relay|\(url)" }

    static func folderKey(_ client: DeadwaxClient, path: String, kind: String, version: Int) -> String {
        "\(client.server.key)|folder|\(path)|\(kind)|\(version)"
    }

    /// A candidate's preview, passed on by deadwax.
    func relayed(client: DeadwaxClient, url: String, admin: Bool) async -> Answer {
        await load(Self.relayKey(client, url: url)) {
            var tries = 0
            while true {
                do {
                    return try await client.artistPicture(url: url)
                } catch {
                    // the relay busy: asked again, twice, a moment apart
                    if (error as? APIFailure)?.status == 503, tries < 2 {
                        tries += 1
                        try await Task.sleep(for: .milliseconds(1500))
                        continue
                    }
                    throw error
                }
            }
        } words: { (error: any Error) -> String? in
            EditWords.said(error, failed: ArtistManageWords.pictureFailed, admin: admin)
        }
    }

    /// A picture in their folder (nil data: none of that kind).
    func folder(client: DeadwaxClient, path: String, kind: String, version: Int) async -> Answer {
        await load(Self.folderKey(client, path: path, kind: kind, version: version)) {
            try await client.artistArt(folder: path, kind: kind)
        } words: { (_: any Error) -> String? in nil }
    }

    private func load(_ key: String, fetch: @escaping @Sendable () async throws -> Data?,
                      words: @escaping @MainActor (any Error) -> String?) async -> Answer {
        if let image = cached(key) { return .image(image) }
        if let held = failed[key], Date().timeIntervalSince(held.at) < CoverCache.againAfter { return .none(held.words) }
        let task: Task<Answer, Never>
        if let asking = loading[key] {
            task = asking.task
            loading[key] = (asking.task, asking.waiters + 1)
        } else {
            task = Task<Answer, Never> { @MainActor in
                await self.turn()
                defer { self.done() }
                // every view that wanted it gone while it waited its turn: never sent
                guard !Task.isCancelled else { return .none(nil) }
                do {
                    guard let data = try await fetch(), let raw = UIImage(data: data) else { return .none(nil) }
                    let side: CGFloat = 900
                    let scale = min(side / max(raw.size.width, raw.size.height, 1), 1)
                    let size = CGSize(width: raw.size.width * scale, height: raw.size.height * scale)
                    return .image(await raw.byPreparingThumbnail(ofSize: size) ?? raw)
                } catch {
                    return .none(words(error))
                }
            }
            loading[key] = (task, 1)
        }
        let answer = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.leave(key, task) }
        }
        if loading[key]?.task == task { loading[key] = nil }
        // cancelled: nothing learned of the picture, so nothing kept - asked afresh when it is drawn again
        if task.isCancelled { return .none(nil) }
        switch answer {
        case .image(let image):
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            images.setObject(image, forKey: key as NSString, cost: max(cost, 1))
            failed[key] = nil
        case .none(let said):
            failed[key] = (Date(), said)
        }
        return answer
    }

    /// A view waiting for `task` went away: the fetch cancelled once none is left.
    private func leave(_ key: String, _ task: Task<Answer, Never>) {
        guard let asking = loading[key], asking.task == task else { return }
        if asking.waiters > 1 {
            loading[key] = (task, asking.waiters - 1)
        } else {
            loading[key] = nil
            task.cancel()
        }
    }

    private func turn() async {
        if running < Self.atOnce {
            running += 1
            return
        }
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in waiting.append(waiter) }
    }

    private func done() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// A candidate's picture through deadwax's relay, fitted in a box of its slot's shape - square for the square image,
/// wide for the rest - so one arriving moves nothing beside it. While it comes, the empty box; one the relay couldn't
/// pass on, the candidate in words (its name and where it is from) with deadwax's words under them - never blank.
/// Hidden from VoiceOver: its button says what it is.
struct RelayedArtistPicture: View {
    let candidate: ArtistImageCandidate
    let square: Bool

    @Environment(ServerModel.self) private var server
    @State private var answer: ArtistPictureCache.Answer?

    var body: some View {
        let key = server.client.map { ArtistPictureCache.relayKey($0, url: candidate.preview) } ?? ""
        let held = key.isEmpty ? nil : ArtistPictureCache.shared.cached(key)
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            if let held {
                Image(uiImage: held)
                    .resizable()
                    .scaledToFit()
            } else if case .image(let image)? = answer {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if case .none(let said)? = answer {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(Typeface.symbol(.title3))
                    Text(ArtistManageWords.asWords(candidate))
                        .font(Typeface.footnote.weight(.semibold))
                    if let said, !said.isEmpty {
                        Text(said)
                            .font(Typeface.caption)
                    }
                }
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .padding(8)
            }
        }
        .aspectRatio(square ? 1 : 16 / 9, contentMode: .fit)
        .clipShape(Corners.artShape)
        .accessibilityHidden(true)
        .task(id: key) {
            guard held == nil, let client = server.client else { return }
            answer = nil
            let got = await ArtistPictureCache.shared.relayed(client: client, url: candidate.preview,
                                                              admin: server.access.seesDetail)
            guard !Task.isCancelled else { return }
            answer = got
        }
    }
}

/// A picture in the artist's folder (`/library/artist/art`), fitted in its slot's box - the empty box while it comes and
/// when there is none - asked again whenever the folder's pictures are written (ArtistFolderVersions), a picture replaced
/// under the same name included. Hidden from VoiceOver: what is around it says what it is.
struct ArtistFolderPicture: View {
    let path: String
    let kind: String
    let square: Bool
    /// Round, for the page's hero.
    var round = false

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        let version = server.client.map { ArtistFolderVersions.shared.version($0, path: path) } ?? 0
        let key = server.client.map {
            ArtistPictureCache.folderKey($0, path: path, kind: kind, version: version)
        } ?? ""
        let shown = image ?? (key.isEmpty ? nil : ArtistPictureCache.shared.cached(key))
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            if let shown {
                if round {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFit()
                }
            }
        }
        .aspectRatio(square ? 1 : 16 / 9, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
        .task(id: key) {
            image = nil
            guard let client = server.client else { return }
            let got = await ArtistPictureCache.shared.folder(client: client, path: path, kind: kind, version: version)
            guard !Task.isCancelled, case .image(let found) = got else { return }
            image = found
        }
    }
}
