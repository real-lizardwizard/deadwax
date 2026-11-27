import Foundation

/// (Speed A, fix 2 - notes/ios.md "Speed A: what's asked again") The last answers of one kind, kept in memory by id for
/// the app's run - the albums' (`KeptAlbums.most` of them): an album page opened again draws its songs at once and asks
/// deadwax behind them, and the artist page's songs prefetch fills the same store.
///
/// Every answer is kept under a `Stamp` - who is signed in and how many writes deadwax has been told of - and is drawn
/// only under that same stamp. A newer stamp (another person, a sign-in again, an Edit's apply, a delete, a re-file)
/// drops everything at its first look; an answer asked under an older stamp lands nowhere, so nothing from before a
/// write, or from the person before, is ever drawn after it. The oldest kept is let go past `most`.
public struct KeptAnswers<Answer: Sendable>: Sendable {
    /// Who the answers are for, and as of which write: compared in that order, each only ever growing.
    public struct Stamp: Sendable, Equatable, Comparable {
        /// One more each time the person changes (the app's ServerModel.person).
        public let person: Int
        /// One more each time the app's pages are reset for a person (AppNavigation.session).
        public let session: Int
        /// Every write deadwax was told of this session: Edit album's to a folder (AppNavigation.albumWrites, summed)
        /// and every managing write - an apply, a Get, a delete, a mark, an artist's re-file (managingWrites).
        public let writes: Int

        public init(person: Int, session: Int, writes: Int) {
            self.person = person
            self.session = session
            self.writes = writes
        }

        public static func < (a: Stamp, b: Stamp) -> Bool {
            (a.person, a.session, a.writes) < (b.person, b.session, b.writes)
        }
    }

    public let most: Int
    /// The stamp the answers kept are under - nil before the first.
    public private(set) var stamp: Stamp?
    private var answers: [String: Answer] = [:]
    /// The ids kept, the most recently kept last.
    private var order: [String] = []

    public init(most: Int) {
        self.most = max(most, 1)
    }

    /// The answers kept now.
    public var count: Int { answers.count }

    /// The answer kept for `id` under `stamp` - nil when none is, and for an older stamp than the store's. A newer
    /// stamp drops everything first.
    public mutating func answer(_ id: String, stamp: Stamp) -> Answer? {
        guard adopt(stamp) else { return nil }
        return answers[id]
    }

    /// `answer` kept for `id`, asked under `stamp`: none for an older stamp than the store's (asked before a write, or
    /// for the person before); a newer one drops everything first. The oldest let go past `most`.
    public mutating func keep(_ id: String, _ answer: Answer, stamp: Stamp) {
        guard adopt(stamp) else { return }
        answers[id] = answer
        order.removeAll { (kept: String) -> Bool in kept == id }
        order.append(id)
        while order.count > most {
            answers[order.removeFirst()] = nil
        }
    }

    /// `id`'s answer let go (deadwax says it is gone, or this page changed it - an Add or a Remove).
    public mutating func forget(_ id: String) {
        answers[id] = nil
        order.removeAll { (kept: String) -> Bool in kept == id }
    }

    /// Whether answers may be read or kept under `stamp` - after dropping everything for a newer one.
    private mutating func adopt(_ stamp: Stamp) -> Bool {
        if let held = self.stamp {
            if stamp == held { return true }
            if stamp < held { return false }
        }
        self.stamp = stamp
        answers = [:]
        order = []
        return true
    }
}

/// (Speed A, fix 2) The albums' answers kept: the last few dozen.
public enum KeptAlbums {
    public static let most = 40
}
