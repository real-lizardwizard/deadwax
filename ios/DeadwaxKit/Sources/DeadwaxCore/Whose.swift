import Foundation

/// "In your library" meaning YOURS - the web app's ui/src/lib/whose.ts (heldPhrase, heldLabel, albumMine and the
/// album page's words), ported line for line, with the album page's wiring of it (AlbumPage.tsx: which of its answers
/// feeds which input) beside it. Held to what the TypeScript answers: Tests/DeadwaxCoreTests/Fixtures/screens/
/// whose.json, written by ios/scripts/export-screen-vectors.cjs - every combination of albumMine's inputs, the page's
/// states as AlbumPage.tsx turns them into inputs, and ui/test/whose.sim.cjs's cases by name.
///
/// With logins on and a library of your own (`Access.hasLibrary`: signed in through Navidrome, not the break-glass
/// admin), your library is your starred albums and the collection is everything deadwax holds - so an album the
/// collection has that isn't yours reads "In the collection", never "In your library". Without one (logins off, the
/// break-glass admin) the collection IS your library, and every word is what deadwax always said. A `yours` the
/// server left out (it couldn't read your library) is never read as "not yours" on a guess.
public enum Whose {
    public static let inYourLibrary = "in your library"
    public static let inTheCollection = "in the collection"

    /// Beside Add, for an album of the collection that isn't yours.
    public static let addFromPage = "It's already here - add it to your library to keep it with your music."
    /// After an Add.
    public static let addedFromPage = "Added to your library."
    /// After a Remove - nothing on disk is touched by it.
    public static let removedFromPage = "Removed from your library - it's still in the collection, and nothing was deleted."
    /// After a Remove of an album Add can't put back, and how to have it back.
    public static let removedStarToReturn = removedFromPage + " To add it back, make it a favourite in another music app."
    /// No release id to keep it by.
    public static let noReleaseToAdd = "This album can't be added from here - make it a favourite in another music app, and it joins your library."
    /// A release the collection has no folder of (yet).
    public static let notFoundToAdd = "This album can't be added from here yet - make it a favourite in another music app, and it joins your library."

    /// What an album the collection holds is to you, in a line's words (heldPhrase): "in your library", or with a
    /// library of your own and it not yours, "in the collection". Only `false` is "not yours".
    public static func heldPhrase(personal: Bool, yours: Bool?) -> String {
        personal && yours == false ? inTheCollection : inYourLibrary
    }

    /// The same as a label's words (heldLabel): "In your library" / "In the collection".
    public static func heldLabel(personal: Bool, yours: Bool?) -> String {
        let phrase = heldPhrase(personal: personal, yours: yours)
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    /// The album page's "In your library", for an album Navidrome has - so in the collection, always (albumMine):
    ///
    ///  - `personal` false (logins off, or the break-glass admin): "In your library", nothing offered;
    ///  - held by your library (the id bridge's `yours`) or starred by you in the album's OWN answer (`starred`; nil
    ///    until that answer has come): "In your library", with Remove from my library;
    ///  - the bridge saying it isn't yours: "In the collection", with Add to my library when the collection has its
    ///    folder by a release id - else a line saying why it can't be added, and how to have it all the same;
    ///  - nothing known yet: pending (the page holds the place of the likely line and Add); the bridge unable to say
    ///    (it failed; no `yours` for a folder it has; no release where Navidrome names one): "In the collection",
    ///    true either way, and nothing.
    ///
    /// `changed`: what this page just did - an Add or a Remove deadwax has taken, said at once over what the page was
    /// told before it. `release` and `releaseSaid` count as none when empty, as JS's `!` reads them.
    public static func albumMine(personal: Bool, starred: Bool?, storeDone: Bool, bridgeFailed: Bool = false,
                                 bridgeYours: Bool?, present: Int, release: String?, releaseSaid: String? = nil,
                                 changed: AlbumMine.Change?) -> AlbumMine {
        func said(_ yours: Bool?, _ action: AlbumMine.Action?, _ note: String?, pending: Bool = false) -> AlbumMine {
            AlbumMine(yours: yours, badge: heldLabel(personal: true, yours: yours == true), action: action, note: note, pending: pending)
        }
        if !personal { return AlbumMine(yours: true, badge: heldLabel(personal: false, yours: true), action: nil, note: nil, pending: false) }
        let hasRelease = !(release ?? "").isEmpty
        let addable = hasRelease && present > 0
        if changed == .added { return said(true, .remove, addedFromPage) }
        if changed == .removed { return said(false, addable ? .add : nil, addable ? removedFromPage : removedStarToReturn) }
        if bridgeYours == true || starred == true { return said(true, .remove, nil) }
        if starred == nil || !storeDone { return said(nil, nil, nil, pending: true) }
        if bridgeFailed || (!hasRelease && !(releaseSaid ?? "").isEmpty) { return said(nil, nil, nil) }
        let why = hasRelease ? notFoundToAdd : noReleaseToAdd
        if bridgeYours == false { return addable ? said(false, .add, addFromPage) : said(false, nil, why) }
        if present > 0 { return said(nil, nil, nil) }
        return said(false, nil, why)
    }

    /// The same from the album page's state, wired as AlbumPage.tsx wires it: `starred` from the album's own answer
    /// (false once that answer has failed - `albumFailed` - nil until it comes), the bridge done once it has answered
    /// or failed, its `yours`, its folders of the release, its release; `releaseSaid` the album answer's
    /// `musicBrainzId` ("" for none, nil until it comes). `personal` is `Access.hasLibrary`.
    public static func albumMine(personal: Bool, album: Album?, albumFailed: Bool, store: StoreAlbum?, storeFailed: Bool,
                                 changed: AlbumMine.Change?) -> AlbumMine {
        albumMine(personal: personal,
                  starred: album.map(\.isStarred) ?? (albumFailed ? false : nil),
                  storeDone: store != nil || storeFailed,
                  bridgeFailed: storeFailed,
                  bridgeYours: store?.yours,
                  present: store?.present.count ?? 0,
                  release: store?.releaseMbid,
                  releaseSaid: album.map { $0.musicBrainzId ?? "" },
                  changed: changed)
    }

    /// The mine block's button: "Add to my library" / "Adding…", "Remove from my library" / "Removing…".
    public static func button(_ action: AlbumMine.Action, busy: Bool) -> String {
        switch action {
        case .add: return busy ? "Adding…" : "Add to my library"
        case .remove: return busy ? "Removing…" : "Remove from my library"
        }
    }

    /// The invisible placeholder held while whose it is is still to come: `addFromPage` over this button's words.
    public static let placeholderButton = "Add to my library"

    // MARK: what the album page draws of it, and when (AlbumPage.tsx)

    /// Whether the badge is drawn yet (AlbumPage.tsx: `storeDone && !mine.pending`): until then its place is held,
    /// unseen, so "In your library" first shows where it stays and never flips. `storeDone`: the id bridge has
    /// answered or failed. `bridgeAsked`: whether the page asks the bridge at all - the web always does; the phone in
    /// Phase 1 only with a library of its own (screens.md, open question 10: without one nothing on the page reads
    /// it), so pass `personal` - and without a library there is no answer to wait for, and the badge is drawn at once.
    /// With one, the bridge must be asked: `albumMine` pends until it is done.
    public static func badgeShown(_ mine: AlbumMine, storeDone: Bool, bridgeAsked: Bool) -> Bool {
        (storeDone || !bridgeAsked) && !mine.pending
    }

    /// Whether the unseen placeholder holds the mine block's place (AlbumPage.tsx: `mine.pending && album &&
    /// !mineRefused`): while whose it is is still to come and the album's answer is in (`albumIn`) - not after a
    /// refusal of this page's last Add or Remove (`refused`), which the block says instead.
    public static func placeholderShown(_ mine: AlbumMine, albumIn: Bool, refused: Bool) -> Bool {
        mine.pending && albumIn && !refused
    }

    /// Whether the mine block is drawn (AlbumPage.tsx: `mine.action || mine.note || !!mineRefused`): with an action
    /// to offer, a line to say, or this page's last Add or Remove refused (`refused`, said in it).
    public static func mineBlockShown(_ mine: AlbumMine, refused: Bool) -> Bool {
        mine.action != nil || !(mine.note ?? "").isEmpty || refused
    }
}

/// What the album page says of whose an album is, and offers (whose.ts AlbumMine).
public struct AlbumMine: Sendable, Equatable {
    /// What the page offers.
    public enum Action: String, Sendable, CaseIterable { case add, remove }
    /// What this page just did.
    public enum Change: String, Sendable, CaseIterable { case added, removed }

    /// Whether it is yours - nil while that can't be told.
    public let yours: Bool?
    /// The badge under the title: "In your library", or "In the collection" - always true of an album Navidrome has.
    public let badge: String
    /// Add to my library, Remove from my library, or neither.
    public let action: Action?
    /// The line beside it.
    public let note: String?
    /// What it says is still to come: the page holds the place of the line and Add most likely to land, so the songs
    /// below don't move under a finger, and draws the badge only once this is false.
    public let pending: Bool

    public init(yours: Bool?, badge: String, action: Action?, note: String?, pending: Bool) {
        self.yours = yours
        self.badge = badge
        self.action = action
        self.note = note
        self.pending = pending
    }
}
