import DeadwaxCore
import Foundation
import Observation

/// One Soulseek search for a pressing, and a download from it - the Sources sheet's (Phase 6, slices 2 and 3 -
/// phase6-get-requests.md 2.10, 2.11; the web's hooks/useCandidateSearch.ts). Every rule is Core's (Sources, AutoPick,
/// StoreLine, GetSettings); this makes the requests and keeps the newest:
///
/// - ONE search, which only the newest becomes: each run lets the one before go (its request cancelled), and an answer
///   for a search let go lands nothing - `stop()` lets it go as the sheet goes.
/// - You > Getting albums asked of deadwax before every search (the web's `begin`), the Format it is scored by waited for
///   while that read is out (GetSettingsModel.format) - the search already showing as asking - and kept with it, so
///   Lossless only leaving nothing of Soulseek's answer is said as such (`Sources.nothingLossless`).
/// - Only an EDITED query overrides a search again (`Sources.queryOverride`): the field shows the first of the names
///   searched, and running it as typed would quietly drop the rest.
/// - One download per search, however fast the taps (`download`).
/// - (Slice 3) "PICK THE BEST SOURCE FOR ME" acts only on a FRESH Get (`start` - a Get, or Try again; never a search
///   again by hand): as the answer lands, When I tap Get and the chips are read as they are THEN (`Picking`), and
///   Sources.autoPick decides - never for a pressing held or on its way, nor one that can't be judged; the best match
///   through the chips at 75 or more, with the list it tops for its runners-up. A pick is downloaded as a card's Get
///   is (`Picking.picked`); when nothing qualifies, why is said (`notPicked`) and the sources show. Every search starts
///   with nothing said.
@MainActor
@Observable
final class SourcesSearch {
    /// What a search is for - and what a download from it files as - and how it stands.
    struct Search {
        let release: GetRelease
        var pending = true
        var answer: FindCandidatesAnswer?
        var error: (any Error)?
        /// The Format it was scored by - nil until deadwax's word on it is in.
        var format: FormatPreference?
    }

    /// (Slice 3) What a fresh Get's pick reads as its answer lands, and how it downloads.
    struct Picking {
        /// The chips as they are now, as filters.
        let filters: @MainActor () -> CandidateFilters
        /// The pick downloaded, with the list it tops: true once the download is asked for (the sheet then goes).
        let picked: @MainActor (Candidate, GetRelease, [Candidate]) -> Bool
    }

    private(set) var search: Search?
    /// (Slice 3) Why a fresh Get set to pick didn't ("… - choose a source yourself.") - nil otherwise, and at every search.
    private(set) var notPicked: String?
    /// One more for every answer that lands: what Add to my library added from is the answer of this number (the web's
    /// `addedFrom`, an answer's identity), so the next search's box is drawn as deadwax says it again.
    private(set) var landed = 0
    /// The query field: what it says now.
    var query = ""

    /// What the last answer said it searched for: a query typed is an edit only when it differs.
    @ObservationIgnored private var shownQuery = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    /// One more for each run and each stop: an answer of an older number lands nothing.
    @ObservationIgnored private var runs = 0
    /// This search has asked for a download.
    @ObservationIgnored private var asked = false

    /// A Get, or Try again: the pressing searched for afresh, the last album's query let go (a search again would take
    /// it for an edit) - and a pick made as it lands, when When I tap Get says so (`picking`).
    func start(_ release: GetRelease, client: DeadwaxClient?, settings: GetSettingsModel, picking: Picking? = nil) {
        query = ""
        shownQuery = ""
        run(release, override: "", client: client, settings: settings, picking: picking)
    }

    /// The same pressing searched again - with the field's query only when it was edited. Never picks.
    func requery(client: DeadwaxClient?, settings: GetSettingsModel) {
        guard let search else { return }
        run(search.release, override: Sources.queryOverride(query, shownQuery), client: client, settings: settings,
            picking: nil)
    }

    /// The search let go: the sheet closed (which stops it in slskd too, as its request goes).
    func stop() {
        runs += 1
        task?.cancel()
        task = nil
    }

    /// A card's Get: true the first time for this search's answer, false for a second tap before the sheet closed.
    func download() -> Bool {
        guard search?.answer != nil, !asked else { return false }
        asked = true
        return true
    }

    /// The Get couldn't be asked at all (nothing was sent): another tap may ask it.
    func downloadAgain() {
        asked = false
    }

    private func run(_ release: GetRelease, override: String, client: DeadwaxClient?, settings: GetSettingsModel,
                     picking: Picking?) {
        stop()
        let number = runs
        asked = false
        search = Search(release: release)
        notPicked = nil
        // asked before every search, so a Format changed elsewhere is the one searched by
        settings.ask()
        task = Task { [weak self] in
            let format = await settings.format()
            guard let self, number == self.runs, !Task.isCancelled else { return }
            guard let client else {
                self.search = Search(release: release, pending: false, error: URLError(.notConnectedToInternet))
                return
            }
            do {
                let answer = try await client.findCandidates(
                    FindCandidatesBody(release: release, format: format, queryOverride: override))
                guard number == self.runs, !Task.isCancelled else { return }
                self.landed += 1
                self.search = Search(release: release, pending: false, answer: answer, format: format)
                self.query = answer.query
                self.shownQuery = answer.query
                if let picking { self.pick(answer, release: release, settings: settings, picking: picking) }
            } catch {
                guard number == self.runs, !Task.isCancelled, !APIFailure.isCancellation(error) else { return }
                self.search = Search(release: release, pending: false, error: error)
            }
        }
    }

    /// A fresh Get's answer landed: When I tap Get and the chips read now (the web's `picking`, read as the answer
    /// lands), and the pick downloaded - or why not said. A pick that couldn't be asked at all (no deadwax to ask) says
    /// nothing here: the sheet says why, over the sources.
    private func pick(_ answer: FindCandidatesAnswer, release: GetRelease, settings: GetSettingsModel, picking: Picking) {
        let mode = (settings.settings ?? .defaults).mode
        switch Sources.autoPick(fresh: true, mode: mode, answer: answer, release: release, filters: picking.filters()) {
        case .off:
            return
        case .picked(let candidate, let list):
            _ = picking.picked(candidate, release, list)
        case .notPicked(let line):
            notPicked = line
        }
    }
}
