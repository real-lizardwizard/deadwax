import Foundation

// "Pick the best source for me" (Phase 6, slice 3 - phase6-get-requests.md 2.11): You > Getting albums' When I tap Get
// set to pick, a Get asks for the best match itself and Requests shows - unless nothing scores well enough through the
// chips, or the pressing is held or on its way, when the sources show with a line saying why. The web's rules -
// candidates.ts AUTO_GRAB_MIN_SCORE, autoGrabPick and autoPickBlocked, getSettings.ts PICK_SORT and notPickedLine - held
// to them by Fixtures/get/get-vectors.json; and hooks/useCandidateSearch.ts's decision on an answer landing (`autoPick`),
// which lives in a hook the exporter can't compile, held by hand (GetTests).

/// What a search's answer leads to, when it lands (useCandidateSearch.ts `run`, after the answer).
public enum AutoPick: Equatable, Sendable {
    /// Nothing to pick: When I tap Get shows the sources, or this search isn't a fresh Get (a search again by hand).
    case off
    /// The best match, asked for straight away - with the list it tops, for its runners-up.
    case picked(Candidate, list: [Candidate])
    /// Wanted, and not made: the sources show, with why (nil when nothing was found at all - the empty state says it).
    case notPicked(String?)
}

/// Which search the Sources sheet ran - and so what runs again as deadwax comes back (slice 3's review, finding 1). A
/// phone's own: the web has no out of reach to come back from.
public enum SourcesRun: Equatable, Sendable {
    /// A Get, or Try again: searched afresh, and a pick made as the answer lands when When I tap Get says so.
    case fresh
    /// Search again by hand, with the query it sent (`Sources.queryOverride` - "" for the field left as it was): you
    /// are choosing, so it never picks.
    case requery(override: String)

    /// Only a fresh Get picks (useCandidateSearch.ts `fresh`).
    public var picks: Bool { self == .fresh }

    /// The query the search sends: none of its own for a fresh Get.
    public var override: String {
        if case .requery(let override) = self { return override }
        return ""
    }

    /// What runs again by itself as deadwax comes back: the very run that failed for want of it - nothing answered, or
    /// not in time - so a search again stays one, never picking, with the words it sent; a Get or Try again stays a
    /// fresh Get. Nothing for a search that answered, or one deadwax refused in words (Try again is there for it).
    public static func onReturn(_ run: SourcesRun?, error: (any Error)?) -> SourcesRun? {
        guard let run, let error, [.offline, .timeout].contains(ErrorWords.kind(of: error)) else { return nil }
        return run
    }
}

extension Sources {
    /// The "good" band of the score colours (`AUTO_GRAB_MIN_SCORE`): below it, a pick leaves the choice to you.
    public static let autoGrabMinScore: Double = 75

    /// A pick is always by best match (`PICK_SORT`): "the best match that passes your quality floor".
    public static let pickSort = CandidateSort.score

    /// What a pick would ask for (`autoGrabPick`): the top of the list as the filters and the sort show it, only when it
    /// scores `autoGrabMinScore` or better - a weak best match is exactly when you want to choose. The pick and the list
    /// it tops (its runners-up), or nil.
    public static func autoGrabPick(_ candidates: [Candidate], _ filters: CandidateFilters,
                                    _ sort: CandidateSort) -> (pick: Candidate, list: [Candidate])? {
        let list = sorted(candidates.filter { passes($0, filters) }, sort)
        guard let pick = list.first, percent(pick) >= autoGrabMinScore else { return nil }
        return (pick, list)
    }

    /// Why no pick may be made from an answer, as a sentence's start, or nil (`autoPickBlocked`): the pressing already
    /// downloading or held - whole or in part - read off the answer itself; and, for the release searched for (nil for
    /// none given), no tracklist to judge the folders by, or no release id to tell whether you have it.
    public static func autoPickBlocked(_ store: StoreStateAnswer?, release: (releaseMbid: String?, trackCount: Int)?) -> String? {
        guard let store else { return nil }
        if store.downloading != nil { return "It's already downloading" }
        if store.held?.complete == true { return "It's already in your library" }
        if store.downloadingPart != nil { return "Part of it is already downloading" }
        if store.held != nil { return "You already have part of it" }
        //? no tracklist: nothing to match the sources against, so no score can be trusted
        if let release, release.trackCount == 0 { return "This pressing has no tracklist to check the sources against" }
        //? no release id: whether you have it already can't be told
        if let release, (release.releaseMbid ?? "").isEmpty { return "It can't be told whether you already have this pressing" }
        return nil
    }

    /// `autoPickBlocked` for a search's answer and the release it was for.
    public static func autoPickBlocked(_ answer: FindCandidatesAnswer?, release: GetRelease?) -> String? {
        autoPickBlocked(answer?.store, release: release.map { ($0.releaseMbid, $0.tracks.count) })
    }

    /// Why Get showed the sources when it was set to pick one (`notPickedLine`) - nil when nothing was found at all:
    /// there is nothing to choose, and the empty state says so.
    public static func notPickedLine(_ blocked: String?, found: Int) -> String? {
        if found == 0 { return nil }
        guard let blocked else { return "No close match that passes your filters - choose a source yourself." }
        return "\(blocked) - choose a source yourself."
    }

    /// (Slice 3's review, finding 2; the phone's own) A pick made as deadwax went out of reach: not asked for - a Get
    /// that would hand over to a Requests that can't show it - and never made later by itself: the sources show, and
    /// the choice is yours once deadwax is back.
    public static let notPickedOffline = "deadwax went out of reach as the sources came in - choose a source yourself once it's back."

    /// What an answer landing leads to (useCandidateSearch.ts): only for a FRESH Get - never a search again you are
    /// steering by hand - with When I tap Get set to pick, both read as the answer lands; never for a pressing held or on
    /// its way, or with no tracklist or release id; the top of the list through `filters` by best match, at
    /// `autoGrabMinScore` or more - else why not. (Manual search, slice A1) Never for a manual search, and nothing said:
    /// the folder is yours to choose, as James asked - not "no tracklist to check the sources against".
    public static func autoPick(fresh: Bool, mode: GetMode, answer: FindCandidatesAnswer, release: GetRelease,
                                filters: CandidateFilters) -> AutoPick {
        guard fresh, mode == .pick, !release.manual else { return .off }
        let blocked = autoPickBlocked(answer, release: release)
        if blocked == nil, let grab = autoGrabPick(answer.candidates, filters, pickSort) {
            return .picked(grab.pick, list: grab.list)
        }
        return .notPicked(notPickedLine(blocked, found: answer.candidates.count))
    }
}
