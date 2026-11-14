import Foundation

/// The library's shuffle's feed carried out (Phase 4, slice 3b's review; useShuffleFeed.ts's effect): what PlayerModel
/// did with ShuffleFeedRun by hand, here so the whole loop runs over a real QueueController in tests
/// (ShuffleFeedLoopTests) - when it looks (the queue changed, Repeat changed, a retry came due), what each answer does to
/// the queue (its songs handed over first, the queue caught up with the engine, then added as an edit like Play Last,
/// and the notice said), and what is let go when the player stops or the person changes.
///
/// The app makes each ask of deadwax (`send`) and hands its answer back (`page`, `gone`, `fresh`, `failed`); keeps the
/// retry's timer (`retry`: true starts it afresh, false calls it off), calling `retryDue` when it fires; and calls
/// `look` from the queue's and Repeat's changes and `stopped` from its stop. It only ever adds to the queue: nothing in
/// it plays.
public final class ShuffleFeedLoop {
    /// Make this ask of deadwax, as the person signed in, and hand its answer back.
    public var send: ((FeedAsk) -> Void)?
    /// These songs are about to be added (PlayerModel keeps them, for Info and the stream cache).
    public var adding: (([Song]) -> Void)?
    /// Say this (the notice: the order started over).
    public var say: ((String) -> Void)?
    /// Start the retry's timer afresh, `ShuffleFeed.retrySeconds` long (true), or call it off (false).
    public var retry: ((Bool) -> Void)?

    /// The feed's state.
    public private(set) var run = ShuffleFeedRun()

    public init() {}

    /// The queue changed (QueueController.onChange), or Repeat did (onRepeatChange): the ask it wants now, sent.
    public func look(_ controller: QueueController) {
        guard let ask = run.look(controller.queue, repeat: controller.repeatMode) else { return }
        make(ask)
    }

    /// A page came for `ask`.
    public func page(_ ask: FeedAsk, songs: [Song], into controller: QueueController?) {
        carry(run.page(ask, songs: songs), songs: songs, into: controller)
    }

    /// `ask`'s page answered 404: the order gone from deadwax.
    public func gone(_ ask: FeedAsk, into controller: QueueController?) {
        carry(run.gone(ask), songs: [], into: controller)
    }

    /// A fresh order came for `ask` - taken with Repeat as the queue's controller has it now.
    public func fresh(_ ask: FeedAsk, _ first: ShuffleStart, into controller: QueueController?,
                      random: () -> Double = UpNext.systemRandom) {
        // no controller: the player stopped, and its stop let every ask go
        guard let controller else { return }
        carry(run.fresh(ask, first, repeat: controller.repeatMode, random: random), songs: first.songs, into: controller)
    }

    /// `ask` failed (not cancelled).
    public func failed(_ ask: FeedAsk, into controller: QueueController?) {
        carry(run.failed(ask), songs: [], into: controller)
    }

    /// The retry's timer fired: the failed ask let go, and the queue looked at again while there is one.
    public func retryDue(_ controller: QueueController?) {
        run.retried()
        guard let controller, !controller.queue.tracks.isEmpty else { return }
        look(controller)
    }

    /// The player stopped - and so the person changed (PlayerModel.reset stops it): every ask let go, the retry with it.
    public func stopped() {
        retry?(false)
        run.reset()
    }

    private func make(_ ask: FeedAsk) {
        retry?(false)
        send?(ask)
    }

    private func carry(_ step: FeedStep, songs: [Song], into controller: QueueController?) {
        switch step {
        case .extend(let token, let tracks, let next, let notice):
            guard let controller else { return }
            adding?(songs)
            // an edit like Play Last: the queue caught up with the engine first (QueueController.edit), so a song
            // that has finished is never what it is added after
            controller.extendQueue(token: token, tracks: tracks, next: next)
            if let notice { say?(notice) }
        case .ask(let next):
            make(next)
        case .retry:
            retry?(true)
        case .nothing:
            break
        }
    }
}
