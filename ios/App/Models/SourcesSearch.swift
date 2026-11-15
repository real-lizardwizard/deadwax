import DeadwaxCore
import Foundation
import Observation

/// One Soulseek search for a pressing, and a download from it - the Sources sheet's (Phase 6, slice 2 -
/// phase6-get-requests.md 2.10; the web's hooks/useCandidateSearch.ts, less "Pick the best source for me", which is slice
/// 3's). Every rule is Core's (Sources, StoreLine, GetSettings); this makes the requests and keeps the newest:
///
/// - ONE search, which only the newest becomes: each run lets the one before go (its request cancelled), and an answer
///   for a search let go lands nothing - `stop()` lets it go as the sheet goes.
/// - You > Getting albums asked of deadwax before every search (the web's `begin`), the Format it is scored by waited for
///   while that read is out (GetSettingsModel.format) - the search already showing as asking - and kept with it, so
///   Lossless only leaving nothing of Soulseek's answer is said as such (`Sources.nothingLossless`).
/// - Only an EDITED query overrides a search again (`Sources.queryOverride`): the field shows the first of the names
///   searched, and running it as typed would quietly drop the rest.
/// - One download per search, however fast the taps (`download`).
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

    private(set) var search: Search?
    /// The query field: what it says now.
    var query = ""

    /// What the last answer said it searched for: a query typed is an edit only when it differs.
    @ObservationIgnored private var shownQuery = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    /// One more for each run and each stop: an answer of an older number lands nothing.
    @ObservationIgnored private var runs = 0
    /// This search has asked for a download.
    @ObservationIgnored private var asked = false

    /// A Get: the pressing searched for afresh, the last album's query let go (a search again would take it for an edit).
    func start(_ release: GetRelease, client: DeadwaxClient?, settings: GetSettingsModel) {
        query = ""
        shownQuery = ""
        run(release, override: "", client: client, settings: settings)
    }

    /// The same pressing searched again - with the field's query only when it was edited.
    func requery(client: DeadwaxClient?, settings: GetSettingsModel) {
        guard let search else { return }
        run(search.release, override: Sources.queryOverride(query, shownQuery), client: client, settings: settings)
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

    private func run(_ release: GetRelease, override: String, client: DeadwaxClient?, settings: GetSettingsModel) {
        stop()
        let number = runs
        asked = false
        search = Search(release: release)
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
                self.search = Search(release: release, pending: false, answer: answer, format: format)
                self.query = answer.query
                self.shownQuery = answer.query
            } catch {
                guard number == self.runs, !Task.isCancelled, !APIFailure.isCancellation(error) else { return }
                self.search = Search(release: release, pending: false, error: error)
            }
        }
    }
}
