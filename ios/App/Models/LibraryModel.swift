import DeadwaxCore
import Foundation
import Observation

/// The Library tab's lists, kept across its pages: the album index of each scope (Core's AlbumIndexState - the
/// newest answer only, an ETag to ask with, 60 s fresh). A seam the Library part fills; the shell asks once and keeps
/// the answer, so the tab shows something real.
@MainActor
@Observable
final class LibraryModel {
    /// The album index of each scope, as Core's state keeps it (what's kept, what's being asked).
    private(set) var index = AlbumIndexState()
    /// The last failure asking a scope, per scope; nil once it answers.
    private(set) var failures: [AlbumScope: APIFailure] = [:]

    private let server: ServerModel

    init(server: ServerModel) {
        self.server = server
    }

    /// The scope the Albums list shows for the person signed in (AlbumScope.albums(for: me)).
    var scope: AlbumScope { AlbumScope.albums(for: server.me) }

    /// What's kept of `scope`, newest answer first; nil before one has come.
    func albums(_ scope: AlbumScope) -> AlbumIndexAnswer? { index.kept(scope)?.answer }

    /// Asks for `scope`'s album index once per generation (AlbumIndexState.list), with the kept answer's ETag.
    func load(_ scope: AlbumScope) async {
        guard let client = server.client else { return }
        guard case .ask(let ask) = index.list(scope) else { return }
        do {
            let fetched = try await client.fetch(Routes.albumIndex, as: AlbumIndexAnswer.self,
                                                 query: [("scope", scope.rawValue)], ifNoneMatch: ask.ifNoneMatch)
            switch fetched {
            case .fresh(let answer, let etag): _ = index.landed(ask, answer: answer, etag: etag, now: Self.nowMs())
            case .unchanged: _ = index.unchanged(ask, now: Self.nowMs())
            }
            failures[scope] = nil
        } catch {
            index.failed(ask)
            if APIFailure.isCancellation(error) { return }
            failures[scope] = error as? APIFailure ?? .other(String(describing: error))
        }
    }

    /// The person changed: nothing of theirs kept.
    func reset() {
        index.clear()
        failures = [:]
    }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
