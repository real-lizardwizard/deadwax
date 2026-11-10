import Foundation

/// The Library's album lists as ui/src/app/albumIndex.ts keeps them, as a value the app holds and drives - one list
/// per scope, each asked in ONE request (`/album_index`) shared by every screen that shows it:
///
/// - Each scope has a GENERATION. A list asked for belongs to the generation it was asked on. `forget` moves it
///   (after an Add or a Remove, and when your library's starred count moves - never for a filing), and
///   `refreshIfOld` moves it only when the list in hand is older than `freshMs` and nothing is on its way.
/// - `list` is a screen's look: a new ask when none is held for this generation, else the one on its way to wait
///   for, else the list it brought.
/// - What lands is kept if it is for the generation the scope is on, or nothing is kept yet - an older ask landing
///   late keeps nothing. A failed ask isn't kept: it is let go, so the next look asks again.
/// - `kept` is the last list that landed for the scope - whatever its generation - drawn at once while a new one is
///   on its way, so a screen never empties and its scroll stays put.
/// - The phone's own addition: a 304 (the list unchanged since the ETag it was asked with) keeps the list and
///   renews its time; and `clear` - at sign-out, sign-in and a change of server - forgets everything, so a kept
///   `yours` never draws for another person, and nothing asked before it can land after it.
public struct AlbumIndexState: Sendable, Equatable {
    /// INDEX_FRESH_MS: how long a list in hand is fresh enough not to be asked again by `refreshIfOld`.
    public static let freshMs: Int64 = 60_000

    /// A list in hand: the answer, the ETag it came with, and when it landed (or a 304 said it still stands), in
    /// milliseconds since 1970.
    public struct Kept: Sendable, Equatable {
        public let answer: AlbumIndexAnswer
        public let etag: String?
        public internal(set) var at: Int64

        public init(answer: AlbumIndexAnswer, etag: String?, at: Int64) {
            self.answer = answer
            self.etag = etag
            self.at = at
        }
    }

    /// One request for a scope's list: send it with `If-None-Match: ifNoneMatch` when that isn't nil (the kept
    /// list's ETag, exactly as received), and hand back what came of it with the same Ask.
    public struct Ask: Sendable, Equatable, Hashable {
        public let id: Int
        public let scope: AlbumScope
        public let generation: Int
        public let ifNoneMatch: String?
        let epoch: Int
    }

    /// What a look at a scope's list calls for.
    public enum Look: Sendable, Equatable {
        /// make this request
        case ask(Ask)
        /// a request for this generation is on its way: wait for it (and draw `kept` meanwhile)
        case wait(Ask)
        /// this generation's list is in hand
        case have(Kept)
    }

    struct Scope: Sendable, Equatable {
        var generation = 0
        var held: Ask?
        var pending = false
        var kept: Kept?
    }

    var scopes: [AlbumScope: Scope] = [:]
    var nextID = 1
    var epoch = 0

    public init() {}

    func state(_ scope: AlbumScope) -> Scope { scopes[scope] ?? Scope() }

    /// The generation the scope is on - what a screen keys its list on.
    public func generation(_ scope: AlbumScope) -> Int { state(scope).generation }

    /// The last list that landed for the scope this session, whatever generation - for a first draw.
    public func kept(_ scope: AlbumScope) -> Kept? { state(scope).kept }

    /// The request on its way for the scope's current generation, if any.
    public func asking(_ scope: AlbumScope) -> Ask? {
        let state = state(scope)
        guard let held = state.held, state.pending, held.generation == state.generation else { return nil }
        return held
    }

    /// A screen's look at the scope's list (`albumIndex(scope)`): one request per generation, shared.
    public mutating func list(_ scope: AlbumScope) -> Look {
        var state = state(scope)
        defer { scopes[scope] = state }
        if let held = state.held, held.generation == state.generation {
            if state.pending { return .wait(held) }
            if let kept = state.kept { return .have(kept) }
        }
        let ask = Ask(id: nextID, scope: scope, generation: state.generation, ifNoneMatch: state.kept?.etag, epoch: epoch)
        nextID += 1
        state.held = ask
        state.pending = true
        return .ask(ask)
    }

    /// A request's list landed (a 200). True when it is kept - for the generation the scope is on, or with nothing
    /// kept yet; an older one landing late keeps nothing.
    @discardableResult
    public mutating func landed(_ ask: Ask, answer: AlbumIndexAnswer, etag: String?, now: Int64) -> Bool {
        guard ask.epoch == epoch else { return false }
        var state = state(ask.scope)
        defer { scopes[ask.scope] = state }
        if state.held?.id == ask.id { state.pending = false }
        guard ask.generation == state.generation || state.kept == nil else { return false }
        state.kept = Kept(answer: answer, etag: etag, at: now)
        return true
    }

    /// A request answered 304: the list is the one kept when it was asked. True when that list still stands - it
    /// is kept and its time renewed; false when it can't be used (a newer list has landed since, or nothing was
    /// held to compare), and the request is let go like a failure, so the next look asks again.
    @discardableResult
    public mutating func unchanged(_ ask: Ask, now: Int64) -> Bool {
        guard ask.epoch == epoch else { return false }
        var state = state(ask.scope)
        defer { scopes[ask.scope] = state }
        let isHeld = state.held?.id == ask.id
        if isHeld { state.pending = false }
        if let sent = ask.ifNoneMatch, let kept = state.kept, kept.etag == sent, ask.generation == state.generation {
            state.kept?.at = now
            return true
        }
        if isHeld { state.held = nil }
        return false
    }

    /// A request failed: let go, so the next look asks again; nothing is kept from it.
    public mutating func failed(_ ask: Ask) {
        guard ask.epoch == epoch else { return }
        var state = state(ask.scope)
        defer { scopes[ask.scope] = state }
        if state.held?.id == ask.id {
            state.pending = false
            state.held = nil
        }
    }

    /// `forgetIndex`: asked again at the next look (a new generation); the kept list stays to draw meanwhile.
    public mutating func forget(_ scope: AlbumScope) {
        var state = state(scope)
        state.generation += 1
        state.held = nil
        state.pending = false
        scopes[scope] = state
    }

    /// `refreshIfOld`: forgotten only when the kept list is older than `freshMs` and nothing is on its way for this
    /// generation. True when it was.
    @discardableResult
    public mutating func refreshIfOld(_ scope: AlbumScope, now: Int64) -> Bool {
        let state = state(scope)
        guard let kept = state.kept else { return false }
        if let held = state.held, held.generation == state.generation, state.pending { return false }
        guard now - kept.at > Self.freshMs else { return false }
        forget(scope)
        return true
    }

    /// A list kept from an earlier launch, drawn until the first look brings this session's (asked with its ETag,
    /// so an unchanged list is a 304). Only when nothing is kept yet.
    public mutating func restore(_ scope: AlbumScope, answer: AlbumIndexAnswer, etag: String?, at: Int64) {
        var state = state(scope)
        guard state.kept == nil else { return }
        state.kept = Kept(answer: answer, etag: etag, at: at)
        scopes[scope] = state
    }

    /// Everything forgotten - sign-out, sign-in, another server: no list kept, and nothing asked before lands after.
    public mutating func clear() {
        scopes = [:]
        epoch += 1
    }
}
