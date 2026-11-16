import DeadwaxCore
import Observation
import SwiftUI

/// Edit album's Release (notes/ios-specs/phase8-managing.md 3.3; the web's components/MetadataEditor.tsx) for one folder:
/// the fields, the pressing chosen, the search, the preview and what the last apply did. Every rule is Core's - Retag
/// (the queries, the scores, the payload, the seeding), RetagFlow (which answer lands, when a preview goes, when Apply is
/// on), RetagWords and EditWords (every word) - this keeps the answers, makes the requests and hands the pages what the
/// rules say of them. EditAlbumModel holds it, one for each folder the editor holds, and carries out Apply.
///
/// As it opens it searches (unless the folder has neither artist nor album) and, when the pressing the folder is
/// tagged with is among the results, loads its tracklist WITHOUT seeding the fields - the folder already claims to be
/// that pressing, so opening the editor never rewrites what is on disk (MetadataEditor's `loadRelease(current, false)`).
/// A pressing picked by hand seeds them. Every change to what Apply would send is an edit (RetagFlow.changed), previewed
/// `Retag.previewDebounceMs` after the last.
@MainActor
@Observable
final class RetagModel {
    /// The folder, as the scan last read it.
    private(set) var album: ScanAlbum
    private(set) var fields: RetagFields
    /// "Download cover art" / "Replace cover.jpg": on by default only when the folder has no cover.
    private(set) var fetchArt: Bool
    /// What was typed in Choose a release's search field.
    var typed = ""
    /// The pressings found, best first.
    private(set) var candidates: [RetagCandidate] = []
    private(set) var searchError: String?
    /// The pressing chosen - its tracklist in hand once `selected` is it.
    private(set) var selectedId: String?
    /// The pressing chosen, with its tracklist (what the payload is built from).
    private(set) var selected: RetagCandidate?
    /// The pressing was picked here, by hand (typed work, as a field is): Close asks before it goes.
    private(set) var pickedByHand = false
    /// The preview in hand (RetagFlow says whether it describes what Apply would send now).
    private(set) var plan: RetagPlan?
    private(set) var previewError: String?
    /// What the last apply did, in the web's sentence - and what it couldn't do.
    private(set) var applied: String?
    private(set) var applyError: String?
    private(set) var appliedProblems: [String] = []
    /// What came of the cover alone (RetagFlow says while it is being saved).
    private(set) var coverResult: String?
    private(set) var flow: RetagFlow

    /// The client asked with - the editor's, set again when the person's changes.
    @ObservationIgnored var client: DeadwaxClient?
    /// Whoever runs deadwax: errors carry their own words in brackets.
    @ObservationIgnored let admin: Bool
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(album: ScanAlbum, online: Bool, admin: Bool, client: DeadwaxClient?) {
        self.album = album
        self.fields = RetagFields(album)
        self.fetchArt = album.art.isEmpty
        self.flow = RetagFlow(online: online)
        self.admin = admin
        self.client = client
    }

    // MARK: what the pages read

    /// The preview, only while it describes what Apply would send now.
    var currentPlan: RetagPlan? { flow.current ? plan : nil }
    var canApply: Bool { flow.canApply(plan) }
    /// A search has finished at least once (a cancelled one doesn't count).
    var searched: Bool { flow.searched }
    /// The cover alone is being saved.
    var savingCover: Bool { flow.savingCover }
    /// Typed work Close would throw away: a field changed from the folder's, the cover's toggle moved, a pressing picked.
    var unsaved: Bool { fields != RetagFields(album) || fetchArt != album.art.isEmpty || pickedByHand }
    /// The pressing whose cover Compare covers shows and the cover alone saves.
    var coverRelease: String? { Retag.coverRelease(selected: selectedId, album: album) }
    /// The search field's placeholder: the album and its artist (`plainAlbumQuery`).
    var searchPrompt: String { Retag.plainQuery(album: fields.album, artist: fields.artist) }
    /// The pressing the folder is tagged with is among the results.
    var foundCurrent: Bool { candidates.contains { Retag.isCurrent($0.release, album.releaseMbid) } }

    /// What Apply sends - and the preview, the same body: the server works the plan out again from it.
    var body: RetagRequestBody {
        RetagRequestBody(albumPath: album.path, release: Retag.payload(selected: selected, album: album, fields: fields),
                         fetchArt: fetchArt)
    }

    // MARK: opening

    /// The editor opened on this folder: the search, once - and the first preview.
    func start() {
        guard !started else { return }
        started = true
        if Retag.searchesAtOnce(album) {
            Task { await search() }
        }
        edited()
    }

    // MARK: the fields

    func set(_ field: WritableKeyPath<RetagFields, String>, _ value: String) {
        guard fields[keyPath: field] != value else { return }
        fields[keyPath: field] = value
        // the message describes a write that has already happened: changed, it no longer describes what Apply would do
        applied = nil
        appliedProblems = []
        edited()
    }

    func setFetchArt(_ on: Bool) {
        guard fetchArt != on else { return }
        fetchArt = on
        edited()
    }

    // MARK: the search

    /// MusicBrainz searched for this album (MetadataEditor's `search`): what was typed, else the fielded query, the
    /// loose words when the fielded finds nothing; the groups ranked against the fields, the first three's pressings
    /// listed, best first; the pressing the folder is tagged with loaded, its fields left alone.
    func search() async {
        guard let client else { return }
        let ticket = flow.beginSearch()
        let said = searchError
        searchError = nil
        do {
            // (a newer search owns the spinner and the list: an older one just stops)
            var groups = try await client.editorSearch(Retag.firstQuery(typed: typed, fields: fields)).releaseGroups
            guard flow.isNewest(search: ticket) else { return }
            if groups.isEmpty, let loose = Retag.looseQuery(typed: typed, fields: fields) {
                groups = try await client.editorSearch(loose).releaseGroups
                guard flow.isNewest(search: ticket) else { return }
            }
            var found: [RetagCandidate] = []
            for group in Retag.rankGroups(groups, fields: fields).prefix(Retag.groupsSearched) {
                let answer = try await client.pressings(groupMbid: group.id)
                guard flow.isNewest(search: ticket) else { return }
                found += RetagCandidate.found(answer.releases, in: group)
            }
            candidates = Retag.rankReleases(found, album: album)
            flow.searchEnded(ticket)
            if let current = candidates.first(where: { Retag.isCurrent($0.release, album.releaseMbid) }) {
                Task { await load(current, seed: false) }
            }
        } catch {
            guard flow.isNewest(search: ticket) else { return }
            // a cancellation is neither a failure nor an answer: the list and what was said stay as they were
            guard !APIFailure.isCancellation(error) else {
                flow.searchCancelled(ticket)
                searchError = said
                return
            }
            flow.searchEnded(ticket, failed: true)
            searchError = RetagWords.searchError(error, admin: admin)
            candidates = []
        }
    }

    /// A pressing picked in Choose a release: its tracklist fetched, the fields filled from it.
    func pick(_ candidate: RetagCandidate) {
        applied = nil
        appliedProblems = []
        pickedByHand = true
        Task { await load(candidate, seed: true) }
    }

    /// MetadataEditor's `loadRelease`: the pressing's tracklist, the newest pick's alone landing; a failure clears the
    /// choice rather than leave Apply pointing at a pressing with no tracklist.
    private func load(_ candidate: RetagCandidate, seed: Bool) async {
        guard let client else { return }
        let ticket = flow.beginLoad()
        selectedId = candidate.id
        searchError = nil
        edited()
        do {
            let full = try await client.pressing(mbid: candidate.id)
            guard flow.loadEnded(ticket) else { return }
            let chosen = candidate.with(full)
            selected = chosen
            if seed { fields = Retag.seeded(chosen, album: album) }
        } catch {
            guard flow.loadEnded(ticket) else { return }
            selectedId = nil
            selected = nil
            if seed { pickedByHand = false }
            searchError = RetagWords.tracklistError(error, admin: admin)
        }
        edited()
    }

    /// The pressing whose tracklist is on its way, if any.
    var loadingId: String? { flow.loadingRelease ? selectedId : nil }

    // MARK: the preview

    /// What Apply would send changed: the preview of it, once the changes stop.
    func edited() {
        flow.changed()
        schedulePreview()
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let edit = flow.edits
        // loading, out of reach or the folder to be read again: its end previews again
        guard flow.due(edit) else { return }
        let request = body
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Retag.previewDebounceMs))
            guard let self, !Task.isCancelled, self.flow.due(edit), let client = self.client else { return }
            do {
                let next = try await client.retagPreview(request)
                if self.flow.answered(edit) {
                    self.plan = next
                    self.previewError = nil
                }
            } catch {
                // cancelled (an edit since, deadwax gone out of reach): neither a failure nor an answer - the next
                // preview is scheduled by what cancelled it
                guard !APIFailure.isCancellation(error) else { return }
                if self.flow.failed(edit) {
                    self.plan = nil
                    self.previewError = EditWords.said(error, failed: RetagWords.previewFailed, admin: self.admin)
                }
            }
        }
    }

    // MARK: Apply

    /// Apply pressed: the body to send - nil when Apply isn't on.
    func beginApply() -> RetagRequestBody? {
        guard flow.beginApply(plan) else { return nil }
        applied = nil
        applyError = nil
        appliedProblems = []
        return body
    }

    /// The apply is over: what came of it said (MetadataEditor's `apply`), the flow told.
    func applyEnded(_ result: Result<RetagResponse, any Error>) -> RetagFlow.Outcome {
        let preview = plan
        let outcome: RetagFlow.Outcome
        switch result {
        case .success(let response):
            outcome = .applied
            appliedProblems = RetagWords.newProblems(response.results, over: preview)
            if response.results.failed != 0 {
                applyError = RetagWords.writeFailed(response.results.failed)
            } else {
                applied = RetagWords.applied(response.results)
                pickedByHand = false
            }
        case .failure(let error):
            // a 4xx refused (said); no answer or a 5xx may have gone ahead - said over the page, deadwax's own words
            // here when it sent some, and the folder read again
            outcome = RetagFlow.outcome(of: error)
            applyError = EditWords.writeFailure(error, failed: RetagWords.applyFailed, admin: admin)
        }
        flow.applyEnded(outcome)
        if outcome == .refused { schedulePreview() }
        return outcome
    }

    // MARK: the cover alone

    /// Replace cover only / Save cover only (MetadataEditor's `saveArtOnly`): the pressing's cover written into the
    /// folder, nothing else changed - off while a write runs or the folder is to be read again (RetagFlow.canSaveCover).
    /// What came of it, as an apply's: written, refused (said), or maybe written - no answer, or a 5xx - the folder
    /// read again. Nil when it couldn't start.
    func saveCoverOnly(path: String) async -> RetagFlow.Outcome? {
        guard let client, flow.beginCover() else { return nil }
        coverResult = nil
        let outcome: RetagFlow.Outcome
        do {
            let saved = try await client.fetchCover(CoverFetchBody(albumPath: path, replace: true, releaseMbid: coverRelease))
            coverResult = RetagWords.coverSaved(saved)
            outcome = .applied
        } catch {
            outcome = RetagFlow.outcome(of: error)
            coverResult = EditWords.writeFailure(error, failed: RetagWords.coverFailed, admin: admin)
                ?? EditWords.mayHaveFinished
        }
        flow.coverEnded(outcome)
        if outcome == .refused { schedulePreview() }
        return outcome
    }

    // MARK: the folder read again, and reach

    /// The folder as the scan read it again (after a write, a gap, Look again): the fields seeded afresh only when the
    /// folder's own values changed (MetadataEditor's effect on the album's values) - typed work is kept otherwise -
    /// and the preview asked again.
    func albumRead(_ fresh: ScanAlbum) {
        let reseed = fresh.path != album.path || RetagFields(fresh) != RetagFields(album) || fresh.art != album.art
        album = fresh
        if reseed {
            fields = RetagFields(fresh)
            fetchArt = fresh.art.isEmpty
        }
        flow.read()
        schedulePreview()
    }

    /// Another part of Edit album wrote to the folder (RetagFlow.folderChanged): no preview in flight lands, and Apply
    /// waits for the folder to be read again.
    func folderChanged() {
        previewTask?.cancel()
        flow.folderChanged()
    }

    func wentAway() {
        flow.wentAway()
        previewTask?.cancel()
    }

    /// Back in reach (section 2: everything asked again): nothing is offered until the folder is read again
    /// (EditAlbumModel reads it and calls albumRead); a search that failed or never finished searched again
    /// (RetagFlow.searchesOnReturn) - else the tagged pressing's tracklist loaded if it never came (Retag.currentToLoad).
    func cameBack() {
        flow.cameBack()
        if flow.searchesOnReturn(atOnce: Retag.searchesAtOnce(album)) {
            Task { await search() }
        } else if let current = Retag.currentToLoad(candidates, album: album, selectedId: selectedId,
                                                    loading: flow.loadingRelease) {
            Task { await load(current, seed: false) }
        }
    }

    /// The folder couldn't be read again: the wait for it ends, said with Look again (RetagFlow.couldNotRead).
    func couldNotRead() {
        flow.couldNotRead()
    }
}
