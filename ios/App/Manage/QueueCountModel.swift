import DeadwaxCore
import Observation

/// Needs a look's count (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; the web's app/useQueueSummary.ts):
/// how many albums need a look, from deadwax's saved scan alone (`GET /library/queue/summary`), drawn as the value of
/// Settings > Manage > Needs a look - never on a tab (James). Core's QueueCount holds every rule: one request out at a
/// time, and one more after it when asked meanwhile, so the answer that lands last is the newest question's; a failure
/// keeps the number in hand; nothing drawn while nobody knows it; never asked without Look after the library (the server
/// answers 403). Asked when Settings shows and on its pull, as the app comes to the front, when Look after the library
/// is given, and after every managing write (AppNavigation.managed) - nothing polls. Another person: let go (`reset`),
/// an answer still out for the last one dropped.
@MainActor
@Observable
final class QueueCountModel {
    /// The count as deadwax last said it, and whether a request is out.
    private(set) var count = QueueCount()
    @ObservationIgnored private let server: ServerModel
    /// One more each time the person changes: an answer for the last one lands nowhere.
    @ObservationIgnored private var generation = 0

    init(server: ServerModel) {
        self.server = server
    }

    /// Ask (again) - when this person may: one request out at a time, one more once it is over when asked meanwhile.
    func ask() {
        guard count.ask(allowed: Managing.asksQueueSummary(server.access.permissions)) else { return }
        let ticket = generation
        Task { await run(ticket) }
    }

    /// The requests, one after another while each was asked again meanwhile.
    private func run(_ ticket: Int) async {
        var again = true
        while again {
            guard ticket == generation else { return }
            guard let client = server.client else {
                again = count.failed()
                continue
            }
            do {
                let summary = try await client.queueSummary()
                guard ticket == generation else { return }
                again = count.answered(summary)
            } catch {
                guard ticket == generation else { return }
                // a failure (or a call called off) keeps the last number - the web's catch
                again = count.failed()
            }
        }
    }

    /// The person changed: nothing of the last one's count kept.
    func reset() {
        generation += 1
        count = QueueCount()
    }
}
