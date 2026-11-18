import DeadwaxCore
import Observation
import SwiftUI

/// Needs a look's count (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; the web's app/useQueueSummary.ts):
/// how many albums need a look, from deadwax's saved scan alone (`GET /library/queue/summary`), drawn as the value of
/// Settings > Manage > Needs a look - never on a tab (James). Core's QueueCount holds every rule: one request out at a
/// time, and one more after it when asked meanwhile, so the answer that lands last is the newest question's; a failure
/// keeps the number in hand; nothing drawn while nobody knows it; never asked without Look after the library (the server
/// answers 403). Nothing polls.
///
/// Asked only while a page that uses it shows - Settings' root (its Manage row) or Needs a look (slice 6's review): as
/// one comes on screen, on its pull, as the app comes back from the background with one up, and when something may have
/// moved the count meanwhile - a managing write, an album noted as looked at, Look after the library given. Never at
/// start-up on another tab, and once for each of those (a page that comes on screen asks once, however often SwiftUI
/// says it appeared). Never under the sign-in over the app (slice 7's review: the pages under it still count as shown,
/// and Now Playing closing under it brings one on screen) - its 401 would only keep the old number; MainTabs asks again
/// as it goes. Another person: let go (`reset`), an answer still out for the last one dropped.
@MainActor
@Observable
final class QueueCountModel {
    /// The pages that use the count.
    enum Page: Hashable {
        case settings
        case needsLook
        /// (The Mac app, slice 3) The desktop frame's sidebar, its Needs a look row's count - while it shows.
        case sidebar
    }

    /// The count as deadwax last said it, and whether a request is out.
    private(set) var count = QueueCount()
    @ObservationIgnored private let server: ServerModel
    /// One more each time the person changes: an answer for the last one lands nowhere.
    @ObservationIgnored private var generation = 0
    /// The pages on screen that use the count.
    @ObservationIgnored private var showing: Set<Page> = []
    /// The app went to the background: coming back to the front asks again.
    @ObservationIgnored private var away = false

    init(server: ServerModel) {
        self.server = server
    }

    /// A page that uses the count came on screen: asked - once, until it goes.
    func shows(_ page: Page) {
        guard showing.insert(page).inserted else { return }
        ask()
    }

    /// That page went (another tab, a page pushed over it, popped).
    func hides(_ page: Page) {
        showing.remove(page)
    }

    /// A pull on one of them.
    func pulled() {
        ask()
    }

    /// Something may have moved the count - a managing write (AppNavigation.managed), an album noted as looked at, Look
    /// after the library given: asked while a page that uses it shows, else as one next comes on screen.
    func changed() {
        guard !showing.isEmpty else { return }
        ask()
    }

    /// The scene's phase: back from the background - never merely from the switcher or a launch - with a page up that
    /// uses the count, asked.
    func scene(_ phase: ScenePhase) {
        switch phase {
        case .background:
            away = true
        case .active:
            guard away else { return }
            away = false
            changed()
        default:
            break
        }
    }

    /// Ask (again) - when this person may, and not under the sign-in over the app: one request out at a time, one more
    /// once it is over when asked meanwhile.
    private func ask() {
        guard count.ask(allowed: Managing.asksQueueSummary(server.access.permissions) && server.signInOver == nil) else {
            return
        }
        let ticket = generation
        Task { await run(ticket) }
    }

    /// The requests, one after another while each was asked again meanwhile.
    private func run(_ ticket: Int) async {
        var again = true
        while again {
            guard ticket == generation else { return }
            // the sign-in came over the app meanwhile: the one asked again waits for it to go (MainTabs)
            guard let client = server.client, server.signInOver == nil else {
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

    /// The person changed: nothing of the last one's count kept - and their pages gone with them (every stack popped,
    /// the Library shown), so the next person's Settings asks as it comes on screen.
    func reset() {
        generation += 1
        count = QueueCount()
        showing = []
    }
}
