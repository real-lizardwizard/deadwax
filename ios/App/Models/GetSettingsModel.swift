import DeadwaxCore
import Foundation
import Observation

/// You > Getting albums as kept for you on deadwax (Phase 6, slice 2 - phase6-get-requests.md 2.10; the web's
/// app/useGetSettings.ts, read-only here until slice 3 gives You its three choices): `/me/preferences`, read leniently
/// (Core's GetSettings - the defaults for anything it doesn't say). The Sources sheet's chips start as the quality floor,
/// a search is scored by the Format, and the store line under Get the album judges somebody else's download against the
/// floor.
///
/// - Asked as the album you don't have shows, as the Sources sheet opens and before every search it starts, so a
///   Format changed on another device meanwhile is the one searched by (the web's `begin`); one read at a time - an ask
///   while one is out joins it.
/// - `format()` is the web's formatPreferenceNow: a read out is waited for, else the value in hand at once, else deadwax
///   is asked and its word waited for - the defaults when it can't say (a Get then shows the sources, the safe way round).
/// - A read that fails leaves what was known. Nothing is seeded from this phone: the web seeds a person's first answer
///   from the old main page's settings in its browser, and the phone never had them.
///
/// `reset()` - a new person - forgets everything, and nothing asked before it lands after it.
@MainActor
@Observable
final class GetSettingsModel {
    /// As deadwax last said them - nil until it has.
    private(set) var settings: GetSettings?

    private let server: ServerModel
    @ObservationIgnored private var asking: Task<Void, Never>?
    @ObservationIgnored private var epoch = 0

    init(server: ServerModel) {
        self.server = server
    }

    /// The quality floor the chips start as: deadwax's, else the default (Any) - the Sources sheet's
    /// `(settings ?? GET_SETTINGS_DEFAULT).quality_floor`.
    var floorNow: QualityFloor { (settings ?? .defaults).floor }

    /// deadwax asked for them - joining a read already out.
    @discardableResult
    func ask() -> Task<Void, Never> {
        if let asking { return asking }
        let epoch = self.epoch
        let client = server.client
        let task = Task { [weak self] in
            let read = try? await client?.getSettings()
            guard let self, epoch == self.epoch else { return }
            self.asking = nil
            if let read { self.settings = read }
        }
        asking = task
        return task
    }

    /// The Format a search is scored by, read as it begins.
    func format() async -> FormatPreference {
        if let asking {
            await asking.value
        } else if settings == nil {
            await ask().value
        }
        return (settings ?? .defaults).format
    }

    /// A new person: nothing of the last one's kept.
    func reset() {
        epoch += 1
        asking?.cancel()
        asking = nil
        settings = nil
    }
}
