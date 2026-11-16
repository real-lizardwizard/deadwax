import DeadwaxCore
import Foundation
import Observation

/// You > Getting albums as kept for you on deadwax (Phase 6, slices 2 and 3 - phase6-get-requests.md 2.10, 2.12; the
/// web's app/useGetSettings.ts): `/me/preferences`, read leniently (Core's GetSettingsAnswer - the defaults for anything
/// it doesn't say). When I tap Get decides whether a Get picks for you, the Sources sheet's chips start as the quality
/// floor, a search is scored by the Format, and the store line under Get the album judges somebody else's download
/// against the floor.
///
/// - ASKED as Settings > Getting albums shows, on its pull and as deadwax comes back into reach, as the album you don't have shows, as the Sources sheet opens and before every
///   search it starts, so a Format changed on another device meanwhile is the one searched by (the web's `begin`); one
///   read at a time - an ask while one is out joins it. An answer in hand stands until the next lands.
/// - (Slice 3) A CHOICE (`choose`) shows at once and is saved behind it: what shows is deadwax's last word with every
///   choice still being saved laid over it, in the order made (GetSettingsAnswer.shown) - so an answer for an older
///   choice can't put a newer one back, and a choice deadwax won't keep goes back, saying so, to what it holds.
/// - ONE AT A TIME: every save and every read goes in turn, each once the one before has answered, so they reach
///   deadwax - and come back - in the order they were asked. A read's answer is never older than a save before it.
/// - `format()` is the web's formatPreferenceNow: a read out is waited for, else the value in hand at once, else deadwax
///   is asked and its word waited for - the defaults when it can't say (a Get then shows the sources, the safe way round).
/// - A read that fails leaves what was known; with nothing known, Getting albums says deadwax didn't answer. Nothing is seeded from
///   this phone: the web seeds a person's first answer from the old main page's settings in its browser, and the phone
///   never had them (a save here marks them seeded on deadwax, as any save does).
///
/// `reset()` - a new person - forgets everything, and nothing asked before it lands after it.
@MainActor
@Observable
final class GetSettingsModel {
    /// A choice still being saved.
    private struct Pending {
        let id: Int
        let choice: GetChoice
    }

    /// deadwax's last word: its answer to the latest read or save, in the order they were sent - nil until it has said.
    private(set) var confirmed: GetSettingsAnswer?
    /// The choices still being saved, oldest first.
    private var pending: [Pending] = []
    /// The first read failed, with nothing in hand.
    private(set) var readProblem: (any Error)?
    /// The last choice deadwax wouldn't keep, until the next choice.
    private(set) var saveProblem: (any Error)?

    private let server: ServerModel
    @ObservationIgnored private var asking: Task<Void, Never>?
    /// Every read and save, one after another: the last one asked.
    @ObservationIgnored private var line: Task<Void, Never>?
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var choices = 0

    init(server: ServerModel) {
        self.server = server
    }

    /// What shows: deadwax's last word with each choice still being saved laid over it - nil until either is in hand.
    var answer: GetSettingsAnswer? {
        GetSettingsAnswer.shown(confirmed, pending: pending.map(\.choice))
    }

    /// The settings as deadwax has them (and as chosen since) - nil until it has answered or a choice is made.
    var settings: GetSettings? { answer?.settings }

    /// deadwax's database can keep them (true until it has said otherwise).
    var canSave: Bool { answer?.canSave != false }

    /// The quality floor the chips start as: deadwax's, else the default (Any) - the Sources sheet's
    /// `(settings ?? GET_SETTINGS_DEFAULT).quality_floor`.
    var floorNow: QualityFloor { (settings ?? .defaults).floor }

    /// What went wrong last, in a listener's words (useGetSettings' `problem`): a choice not kept, else the first read
    /// unanswered.
    func problem(admin: Bool) -> String? {
        if let saveProblem { return ErrorWords.notice(GettingWords.notSaved, saveProblem, admin: admin) }
        if let readProblem { return ErrorWords.notice(GettingWords.readFailed, readProblem, admin: admin) }
        return nil
    }

    /// deadwax asked for them - joining a read already out, in turn with the saves.
    @discardableResult
    func ask() -> Task<Void, Never> {
        if let asking { return asking }
        let epoch = self.epoch
        let task = inTurn { [weak self] in
            guard let self, epoch == self.epoch else { return }
            defer { if epoch == self.epoch { self.asking = nil } }
            guard let client = self.server.client else { return }
            do {
                let read = try await client.getSettings()
                guard epoch == self.epoch else { return }
                self.confirmed = read
                self.readProblem = nil
            } catch {
                guard epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                // an answer in hand stands, said nothing against; with none, Getting albums says deadwax didn't answer
                if self.confirmed == nil { self.readProblem = error }
            }
        }
        asking = task
        return task
    }

    /// One of the three chosen in You: shown at once, saved behind it in turn - and put back if deadwax won't keep it,
    /// to what it holds, with any later choice still being saved kept over it.
    func choose(_ choice: GetChoice) {
        choices += 1
        let id = choices
        pending.append(Pending(id: id, choice: choice))
        saveProblem = nil
        let epoch = self.epoch
        inTurn { [weak self] in
            guard let self, epoch == self.epoch else { return }
            defer { if epoch == self.epoch { self.pending.removeAll { $0.id == id } } }
            do {
                guard let client = self.server.client else { throw URLError(.notConnectedToInternet) }
                // the answer to a save is all of the settings, as they stand after it
                let saved = try await client.saveSettings(choice)
                guard epoch == self.epoch else { return }
                self.confirmed = saved
            } catch {
                guard epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                self.saveProblem = error
            }
        }
    }

    /// The Format a search is scored by, read as it begins.
    func format() async -> FormatPreference {
        if let asking {
            await asking.value
        } else if answer == nil {
            await ask().value
        }
        return (settings ?? .defaults).format
    }

    /// A new person: nothing of the last one's kept.
    func reset() {
        epoch += 1
        asking = nil
        line = nil
        confirmed = nil
        pending = []
        readProblem = nil
        saveProblem = nil
    }

    /// `work` run once everything asked before it has answered, failed or not.
    @discardableResult
    private func inTurn(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let before = line
        let task = Task { @MainActor in
            await before?.value
            await work()
        }
        line = task
        return task
    }
}
