import Foundation

/// Artist images' state, as rules (Phase 8, slice 5 - phase8-managing.md 2 and 4): the web's ImagesBody
/// (app/ArtistPanel.tsx - its `load`, `search`, `canSave` and `save`) and section 2's rules for a page that needs deadwax.
/// Pure, so ArtistManageFlowTests holds it; the app's ArtistImagesModel drives it and draws.
///
/// NEWEST ANSWER. Each look for pictures and each search takes the next number, and only the newest lands (the web's
/// `latestOnly`): a pick made while another artist's pictures are coming, a search typed over another.
///
/// SAVE. On only with the pictures of the artist last asked about in hand - never while another's are coming, or after
/// that look failed and took them off the screen (the web's `canSave`) - a MusicBrainz id settled, a picture chosen,
/// deadwax in reach, and the folder looked at since the last gap. It sends what is drawn: the folder's name, the id the
/// preview answered with, the choices and Replace - the server checks each choice is a picture its sources offer.
///
/// THE LONG WAIT. A save that never answered, or answered a 5xx, may have written (the pictures are fetched and written
/// before the answer): said as maybe finished, and the folder looked at again before Save comes back - never offered
/// again on the old look. A 4xx wrote nothing, and is said as deadwax said it.
public struct ArtistImagesFlow: Sendable, Equatable {
    /// Who a look was for: the id (nil: let the files or a search say) and the name said while it comes.
    public struct Asked: Sendable, Equatable {
        public let mbid: String?
        public let name: String

        public init(mbid: String?, name: String) {
            self.mbid = mbid
            self.name = name
        }
    }

    /// The library name the images routes are asked about (ArtistManage.imagesFolder) - nil: none can be.
    public let folder: String?

    public private(set) var asks = 0
    public private(set) var searches = 0
    public private(set) var saves = 0
    /// The artist last asked about - what Look again and deadwax coming back ask for again.
    public private(set) var lastAsked: Asked
    /// Whose pictures are being looked for (nil: none).
    public private(set) var loading: String?
    /// The look failed: said, with Look again - and the pictures it would have replaced are off the screen.
    public private(set) var problem: String?
    public private(set) var preview: ArtistImagesPreview?
    /// The picture chosen for each slot (kind -> its address) - the best of each kind as a look lands.
    public private(set) var chosen: [String: String] = [:]
    /// Replace pictures that are already there.
    public var replace = false
    public private(set) var saving = false
    /// What the last save said (savedLine), or why it didn't.
    public private(set) var saved: String?
    /// The search: open when MusicBrainz couldn't say who this is, or asked for (Not them?).
    public private(set) var searchOpen = false
    public private(set) var matches: [MBArtistMatch] = []
    public private(set) var searching = false
    public private(set) var searchNote: String?
    /// The words of a search that failed - searched again when deadwax is back.
    public private(set) var searchFailedFor: String?
    public private(set) var online: Bool
    /// A gap or a save that may have written: the folder is looked at again before Save comes back.
    public private(set) var needsRead = false
    public private(set) var mayHaveFinished = false
    /// One more for each save that wrote, or may have: the artist page asks its pictures again.
    public private(set) var wrote = 0

    /// What the choices and Replace were when last written or offered: anything else is an unsaved edit.
    private var baseline: [String: String] = [:]
    private var savedReplace = false

    public init(folder: String?, mbid: String?, name: String, online: Bool) {
        self.folder = folder
        self.online = online
        lastAsked = Asked(mbid: mbid, name: name)
    }

    // MARK: looking

    /// A look for `mbid`'s pictures (Look again, a pick, the sheet opening): its ticket - nil when none is sent (no one
    /// folder for their pictures: said; deadwax out of reach: asked once it is back).
    public mutating func look(mbid: String?, name: String) -> Int? {
        lastAsked = Asked(mbid: mbid, name: name)
        guard folder != nil else {
            loading = nil
            problem = ArtistManageWords.noFolder
            return nil
        }
        guard online else {
            needsRead = true
            return nil
        }
        asks += 1
        loading = name
        problem = nil
        return asks
    }

    /// The look's answer: the pictures drawn, the best of each kind chosen; with no MusicBrainz id the search opens
    /// with the artists the name matched.
    public mutating func looked(_ ticket: Int, _ found: ArtistImagesPreview) {
        guard ticket == asks else { return }
        loading = nil
        preview = found
        chosen = ArtistManage.bestUrls(found.best)
        baseline = chosen
        saved = nil
        needsRead = false
        mayHaveFinished = false
        if found.mbid == nil {
            searchOpen = true
            matches = found.matches
        } else {
            matches = []
        }
    }

    /// The look failed (a cancellation is no failure - the app drops it): said, with Look again.
    public mutating func lookFailed(_ ticket: Int, words: String) {
        guard ticket == asks else { return }
        loading = nil
        problem = words
    }

    // MARK: choosing and saving

    /// A picture tapped for a slot: chosen - or, chosen already, taken back.
    public mutating func toggle(kind: String, url: String) {
        guard !saving else { return }
        chosen = ArtistManage.toggleChoice(chosen, kind: kind, url: url)
    }

    /// Whether `url` is the picture chosen for `kind`.
    public func isChosen(kind: String, url: String) -> Bool {
        chosen[kind].map { WebText.same($0, url) } ?? false
    }

    /// Save may be pressed.
    public var canSave: Bool {
        folder != nil && online && !needsRead && !saving && loading == nil && problem == nil && preview?.mbid != nil
            && !chosen.isEmpty
    }

    /// Choices or Replace changed and not saved: a swipe doesn't close the sheet, and Close asks.
    public var holdsWork: Bool {
        preview != nil && !saving && (chosen != baseline || replace != savedReplace)
    }

    /// Save pressed: its ticket and what it sends - nil when it isn't on.
    public mutating func beginSave() -> (ticket: Int, body: ArtistImagesBody)? {
        guard canSave, let folder, let preview else { return nil }
        saves += 1
        saving = true
        saved = nil
        mayHaveFinished = false
        return (saves, ArtistImagesBody(artist: folder, artistMbid: preview.mbid, choices: chosen, replace: replace))
    }

    /// The save answered: what it said, and the folder's pictures as it left them.
    public mutating func saveAnswered(_ ticket: Int, _ applied: ArtistImagesApplied) {
        guard ticket == saves else { return }
        saving = false
        preview = preview?.with(art: applied.art)
        saved = applied.results.line
        baseline = chosen
        savedReplace = replace
        wrote += 1
    }

    /// The save failed: a 4xx said as deadwax said it (`words`) - nothing written; anything else may have written:
    /// said as maybe finished (with deadwax's own words when it sent some), and true - look again.
    public mutating func saveFailed(_ ticket: Int, outcome: RetagFlow.Outcome, words: String?) -> Bool {
        guard ticket == saves else { return false }
        saving = false
        switch outcome {
        case .refused, .applied:
            saved = words ?? ArtistManageWords.saveFailed
            return false
        case .unanswered:
            saved = words
            mayHaveFinished = true
            needsRead = true
            wrote += 1
            return true
        }
    }

    // MARK: the search

    /// Not them?: the search shown.
    public mutating func openSearch() { searchOpen = true }

    /// A search for `query`: its ticket - nil for nothing typed, or deadwax out of reach.
    public mutating func beginSearch(_ query: String) -> Int? {
        let wanted = WebText.trim(query)
        guard !wanted.isEmpty, online else { return nil }
        searches += 1
        searching = true
        searchNote = nil
        return searches
    }

    public mutating func searched(_ ticket: Int, query: String, _ found: [MBArtistMatch]) {
        guard ticket == searches else { return }
        searching = false
        searchFailedFor = nil
        matches = found
        if found.isEmpty { searchNote = ArtistManageWords.nothingGoesBy(WebText.trim(query)) }
    }

    public mutating func searchFailed(_ ticket: Int, query: String, words: String) {
        guard ticket == searches else { return }
        searching = false
        searchNote = words
        searchFailedFor = WebText.trim(query)
    }

    // MARK: deadwax going and coming back

    public mutating func wentAway() { online = false }

    /// deadwax is back: everything asked again before Save comes back - the artist last asked about, and a search that
    /// failed.
    public mutating func cameBack() -> (look: Asked?, search: String?) {
        online = true
        guard folder != nil else { return (nil, searchFailedFor) }
        needsRead = true
        return (lastAsked, searchFailedFor)
    }
}

extension ArtistImagesPreview {
    /// The same look with the folder's pictures as a save left them.
    public func with(art: [String: String]) -> ArtistImagesPreview {
        ArtistImagesPreview(artist: artist, path: path, folderProblem: folderProblem, art: art, mbid: mbid,
                            mbidSource: mbidSource, matches: matches, facts: facts, candidates: candidates, best: best,
                            kinds: kinds, fanarttv: fanarttv, theaudiodb: theaudiodb, hasKey: hasKey,
                            problems: problems)
    }
}

/// Move albums' state, as rules (the web's RefileBody, app/ArtistPanel.tsx): each name's preview asked together, drawn
/// as one (ArtistManage.refileView); Move applying each name in turn - those with an album the preview shows moving -
/// stopping at the first that fails; then what became of it (refileOutcome, refileAfter). Pure, so
/// ArtistManageFlowTests holds it.
///
/// WHAT IT SENDS. Each name's apply sends what its preview did - the name and the page's id - and the server works the
/// plan out again. Move is on only while the previews in hand were made for the names, id and name now the page's: when
/// those change (the library's folders read again, who they are settled), the previews are asked again rather than
/// applied blind. An apply that never answered, or answered a 5xx, may have moved albums: said as maybe finished, and
/// the previews asked again before Move comes back.
public struct ArtistRefileFlow: Sendable, Equatable {
    /// What the previews are asked for: the names to move (namesToMove), the page's id and their name now.
    public struct Ask: Sendable, Equatable {
        public let names: [String]
        public let mbid: String?
        public let current: String?

        public init(names: [String], mbid: String?, current: String?) {
            self.names = names
            self.mbid = mbid
            self.current = current
        }
    }

    /// What became of a Move (refileOutcome, refileAfter).
    public struct Outcome: Sendable, Equatable {
        public let text: String
        public let failures: [String]
        public let moved: Int
        public let emptied: [String]
    }

    public private(set) var ask: Ask
    public private(set) var previews = 0
    /// What the plans in hand were made for.
    public private(set) var madeFor: Ask?
    public private(set) var plans: [ArtistManage.NamedPlan]?
    public private(set) var loading = false
    public private(set) var error: String?
    public private(set) var applying = false
    public private(set) var outcome: Outcome?
    /// What moved before an apply that never answered (refileOutcome's text), said over the maybe-finished line.
    public private(set) var partly: String?
    public private(set) var online: Bool
    public private(set) var needsRead = false
    public private(set) var mayHaveFinished = false
    /// One more for each Move that moved albums, or may have: the artist page asks again.
    public private(set) var wrote = 0

    private var asking: Ask?

    public init(_ ask: Ask, online: Bool) {
        self.ask = ask
        self.online = online
    }

    /// Every name's plan as one.
    public var view: ArtistManage.RefileView? { ArtistManage.refileView(plans ?? []) }

    /// Move may be pressed: previews made for what the page shows now, something to move and no problem.
    public var canMove: Bool {
        online && !applying && !loading && !needsRead && error == nil && outcome == nil && madeFor == ask
            && ArtistManage.canMove(view)
    }

    /// The previews asked for (the sheet opening, Look again, deadwax back, the page's names changed): its ticket, and
    /// the names and id - nil when nothing is sent (out of reach: asked once it is back; nothing to move).
    public mutating func preview() -> (ticket: Int, ask: Ask)? {
        guard !applying, !ask.names.isEmpty else { return nil }
        guard online else {
            needsRead = true
            return nil
        }
        previews += 1
        loading = true
        error = nil
        asking = ask
        return (previews, ask)
    }

    public mutating func previewed(_ ticket: Int, _ found: [ArtistManage.NamedPlan]) {
        guard ticket == previews else { return }
        loading = false
        plans = found
        madeFor = asking
        needsRead = false
        mayHaveFinished = false
    }

    public mutating func previewFailed(_ ticket: Int, words: String) {
        guard ticket == previews else { return }
        loading = false
        error = words
    }

    /// The page's names, id or their name now changed: true - preview again - unless a Move is under way or done.
    public mutating func changed(_ now: Ask) -> Bool {
        guard now != ask else { return false }
        ask = now
        return !applying && outcome == nil
    }

    /// Move pressed: the names to apply, in turn - nil when it isn't on.
    public mutating func beginMove() -> [ArtistManage.NamedPlan]? {
        guard canMove, let plans, let view else { return nil }
        applying = true
        mayHaveFinished = false
        partly = nil
        return ArtistManage.namesApplied(plans, view: view)
    }

    /// The applies are over - each name's answer in `applied`, and how the one that stopped them failed (nil: none did):
    /// a refusal said beside what became of the rest; one that may have moved albums said as maybe finished, and true -
    /// preview again.
    public mutating func moveEnded(applied: [ArtistManage.AppliedName], stopped: (outcome: RetagFlow.Outcome, words: String?)?)
        -> Bool {
        guard applying else { return false }
        applying = false
        let view = self.view ?? ArtistManage.RefileView(currentName: "", toFolder: "", moves: [], refused: [],
                                                         problems: [], empty: true)
        let told = ArtistManage.refileOutcome(applied.map(\.results), toFolder: view.toFolder)
        let after = ArtistManage.refileAfter(previewed: plans ?? [], applied: applied, view: view)
        if told.moved > 0 { wrote += 1 }
        if let stopped, stopped.outcome == .unanswered {
            partly = told.moved > 0 ? told.text : nil
            mayHaveFinished = true
            needsRead = true
            if told.moved == 0 { wrote += 1 }
            return true
        }
        var failures = told.failures + after.stayed
        if let stopped { failures.append(stopped.words ?? ArtistManageWords.moveFailed) }
        outcome = Outcome(text: told.text, failures: failures, moved: told.moved, emptied: after.emptied)
        return false
    }

    public mutating func wentAway() { online = false }

    /// deadwax is back: true - preview again before Move comes back (never while one is under way: its answer decides).
    public mutating func cameBack() -> Bool {
        online = true
        guard !applying, outcome == nil else { return false }
        needsRead = true
        return true
    }
}

/// Which artist is this?'s search (the web's WhoBody): only the newest search lands; a failed one is searched again
/// when deadwax is back.
public struct ArtistWhoFlow: Sendable, Equatable {
    public private(set) var searches = 0
    public private(set) var searching = false
    /// nil until a search answers.
    public private(set) var matches: [MBArtistMatch]?
    public private(set) var note: String?
    public private(set) var failedFor: String?
    public private(set) var online: Bool

    public init(online: Bool) { self.online = online }

    public mutating func begin(_ query: String) -> Int? {
        guard !WebText.trim(query).isEmpty, online else { return nil }
        searches += 1
        searching = true
        note = nil
        return searches
    }

    public mutating func answered(_ ticket: Int, query: String, _ found: [MBArtistMatch]) {
        guard ticket == searches else { return }
        searching = false
        failedFor = nil
        matches = found
        if found.isEmpty { note = ArtistManageWords.nothingGoesBy(WebText.trim(query)) }
    }

    public mutating func failed(_ ticket: Int, query: String, words: String) {
        guard ticket == searches else { return }
        searching = false
        note = words
        failedFor = query
    }

    public mutating func wentAway() { online = false }

    /// deadwax is back: the search that failed, to ask again.
    public mutating func cameBack() -> String? {
        online = true
        return failedFor
    }
}

/// How long the phone waits for the artist tools' two long writes - worked out for what is in hand from what the server
/// does, past its worst case with a minute's margin, never less than `Routes.timeouts` gives the route (as EditWaits).
/// A wait that still runs out is said as maybe finished and the folder looked at again, never sent again unseen. Each
/// figure is the server's own, held by tests/test_ios_artist_manage.py.
public enum ArtistWaits {
    /// The plan, the writes, the scan's cache and the answer's way back, over the network's worst case.
    public static var margin: Double { EditWaits.margin }
    /// The scan the route reads first: the saved one, or a walk of the library where there is none (the scan's wait).
    public static var scan: Double { Routes.timeouts[Routes.libraryArtist] ?? 120 }
    /// One MusicBrainz lookup with its ten attempts, 3 s apart while it is busy (an artist's facts' wait).
    public static var musicBrainz: Double { Routes.timeouts[Routes.artistFacts] ?? 60 }
    /// One source's answer - TheAudioDB's, fanart.tv's, Wikidata's, a Commons file's width: its connection (10 s) and
    /// its read (15 s), JSON_TIMEOUT.
    public static let sourceRequest: Double = 25
    /// The sources asked in turn for an artist's pictures: TheAudioDB, fanart.tv, Wikidata.
    public static let sources: Double = 3
    /// One picture fetched for writing: its connection (10 s) and its read (30 s), IMAGE_TIMEOUT.
    public static let pictureRequest: Double = 40
    /// The requests behind one picture's address: Commons' Special:FilePath redirects twice before its picture.
    public static let pictureHops: Double = 3

    /// Artist images' Save for `pictures` slots chosen, with `commons` Commons pictures among the candidates (each a
    /// width asked of Commons as the candidates are made again): the scan, the lookup, the sources and the widths, then
    /// each picture fetched in turn through its redirects.
    public static func imagesApply(pictures: Int, commons: Int) -> Double {
        let floor = Routes.timeouts[Routes.artistImagesApply]
        let candidates = sourceRequest * (sources + Double(max(0, commons)))
        let fetches = Double(max(1, pictures)) * pictureRequest * pictureHops
        return EditWaits.wait(scan + musicBrainz + candidates + fetches + margin, floor: floor)
    }

    /// Move albums' apply for one name whose albums hold `bytes`: the route's own (the scan, the lookup, every file
    /// read, tagged and moved, the saved scan and the store index), and on top every file written whole at a slow
    /// disk's pace (EditWaits.rewriteBytesPerSecond) - a retag whose tags outgrow their room rewrites the file.
    public static func refileApply(bytes: Double) -> Double {
        let floor = Routes.timeouts[Routes.refileApply] ?? 480
        let rewrite = bytes.isFinite && bytes > 0 ? bytes / EditWaits.rewriteBytesPerSecond : 0
        return EditWaits.wait(floor + rewrite, floor: floor)
    }

    /// The Commons pictures among a look's candidates, by address: one width asked for each as apply makes them again.
    public static func commons(_ candidates: [ArtistImageCandidate]) -> Int {
        Set(candidates.compactMap { (candidate: ArtistImageCandidate) -> [UInt16]? in
            candidate.url.contains("commons.wikimedia.org") ? Array(candidate.url.utf16) : nil
        }).count
    }

    /// The most of a candidate's picture the phone reads through the relay: the relay's own cap (PICTURE_MAX_BYTES).
    public static let pictureMostBytes = 8 * 1024 * 1024
}

/// The artist tools' words - the web's ArtistPanel.tsx's and ArtistPage.tsx's (held by ArtistManageVectorTests), and
/// the phone's own where it has a sheet and a menu where the web has a panel and buttons.
public enum ArtistManageWords {
    // the panel's titles (ArtistPanel.tsx TITLES)
    public static let imagesTitle = "Artist images"
    public static let refileTitle = "Move albums"
    public static let whoTitle = "Which artist is this?"

    // the bar's ••• (the phone's): the web's buttons, each opening a sheet
    public static let imagesItem = "Artist images…"
    public static let whoItem = "Which artist is this?"
    /// The web's "Move albums to {name}", with the ellipsis a menu item opening a sheet takes.
    public static func moveItem(_ name: String) -> String { "Move albums to \(name)…" }
    public static let more = "More for this artist"
    /// A choice made with Which artist is this?, for the page (ArtistPage.tsx).
    public static let chosen = "You chose who this is, for this visit."

    // Artist images (ImagesBody)
    public static let noFolder = "There's no one folder for their pictures."
    public static let notThem = "Not them?"
    public static let searchLabel = "Search MusicBrainz for an artist"
    public static let search = "Search"
    public static func nothingGoesBy(_ query: String) -> String { "Nothing in MusicBrainz goes by \"\(query)\"." }
    public static let searchFailed = "MusicBrainz couldn't be reached."
    public static let lookFailed = "Couldn't look for pictures just now."
    public static func looking(_ name: String) -> String { "Looking for pictures of \(name)…" }
    public static let saveFailed = "That couldn't be saved."
    public static let replace = "Replace pictures that are already there"
    public static let saving = "Saving…"
    public static let save = "Save"
    public static func useAnother(_ count: Int) -> String { "Use another picture (\(count))" }
    public static let whichArtist = "Which artist the pictures are of"
    /// A picture's name to VoiceOver: "Square image, from fanart.tv".
    public static func option(_ candidate: ArtistImageCandidate) -> String {
        "\(candidate.label), from \(candidate.source)"
    }
    /// The picture on disk when nothing was found for its slot: "Banner on disk".
    public static func onDisk(_ label: String) -> String { "\(label) on disk" }
    /// The phone's own: a candidate the relay couldn't pass on, drawn as words - its name, where it is from.
    public static func asWords(_ candidate: ArtistImageCandidate) -> String {
        [candidate.label, candidate.source].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    /// The phone's own: a candidate's picture the relay couldn't pass on, with nothing more to say - the relay's own
    /// words for a picture it couldn't get (routes/library.py PICTURE_WORDS' 502).
    public static let pictureFailed = "deadwax couldn't get that picture just now."
    /// The phone's own: what's in the folder now, its section.
    public static let inFolder = "In their folder now"
    public static let chosenMark = "Chosen"

    // Which artist is this? (WhoBody)
    public static func whoNote(_ name: String) -> String {
        "MusicBrainz knows several artists by names like this, or none from your files. Choose who \(name) is, and the "
            + "page shows their albums and who they are - for this visit. The release editor writes who an album is by "
            + "into its files."
    }
    public static let searching = "Searching MusicBrainz…"
    public static let artistsGoingBy = "Artists going by this name"

    // Move albums (RefileBody)
    public static let working = "Working out the moves…"
    /// "Each album moves into <strong>{toFolder}/</strong> keeping its own folder name, …" - the folder is the strong
    /// part (`folderStrong`).
    public static func refileNote(toFolder: String, currentName: String) -> (lead: String, folder: String, rest: String) {
        ("Each album moves into ", "\(toFolder)/",
         " keeping its own folder name, and its album artist tag becomes \(currentName) - where a download filed today "
            + "would put it. Each track's own artist is what the sleeve credited, and stays.")
    }
    public static let albumsThatMove = "Albums that move"
    public static let albumsThatStay = "Albums that stay"
    public static func stays(_ reason: String) -> String { "stays - \(reason)" }
    public static let nothingCanMove = "Nothing can move - every album stays where it is, for the reason beside it."
    public static func nothingToMove(_ currentName: String) -> String {
        "Nothing to move - every album is already filed under \(currentName)."
    }
    public static let previewFailed = "Couldn't work out the moves."
    public static let moveFailed = "The move didn't work."
    public static let moving = "Moving…"
    public static let done = "Done"
    public static let cancel = "Cancel"
    /// "→ Ye/Graduation (2007)": where a move goes.
    public static func movesTo(_ target: String) -> String { "→ \(target)" }
}
