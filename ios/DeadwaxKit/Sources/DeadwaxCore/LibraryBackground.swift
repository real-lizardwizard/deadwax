import Foundation

/// The phone's power as the app reads it (UIDevice.batteryState, monitoring on) - Only while charging's (Phase 3, slice
/// 3, phase3-autodownload.md 2.8). Core's own, so the rules have no UIKit.
public enum PowerState: String, Sendable, CaseIterable {
    /// Not known: monitoring off, or iOS can't tell. Not charging - Only while charging is literal.
    case unknown
    case unplugged
    case charging
    /// On the charger, full.
    case full

    /// Charging, or full on the charger: Only while charging lets the library's songs go.
    public var charging: Bool { self == .charging || self == .full }
}

/// Your library in the background (phase3-autodownload.md 2.9): the two tasks iOS may run with the app suspended, when
/// each is asked for, and what a run did - Debug keeps the last few, so check 61 can tell whether iOS ran one at all.
///
/// Both run the same check and the same plan as the app in front: nothing about the rules differs in the background.
/// A run deletes nothing the app in front wouldn't - the two checks 10 minutes apart and the phone's deficit seen on
/// plans 3 minutes apart (on the uptime clock, in the run's own process) hold as they do there.
public enum LibraryBackground {
    /// The refresh (`BGAppRefreshTask`, UIBackgroundModes `fetch`): a check, and what the fill lets go handed over.
    public static let refreshID = "net.lizardlounge.deadwax.library"
    /// The charger's (`BGProcessingTask` with requiresExternalPower, UIBackgroundModes `processing`): Only while
    /// charging's first batch, handed over once the phone is plugged in.
    public static let chargingID = "net.lizardlounge.deadwax.charging"
    /// Both, as Info.plist's BGTaskSchedulerPermittedIdentifiers lists them (check_project.py checks it does).
    public static let identifiers = [refreshID, chargingID]

    /// The refresh is asked for no sooner than this after the app goes to the background (`earliestBeginDate`): the
    /// checks' own 15 minutes.
    public static let refreshAfterMs: Int64 = LibraryFollow.everyMs
    /// iOS gives a refresh about 30 seconds: a run reads at most this many albums' songs, the rest at the next chance.
    public static let readsPerRun = 20
    /// How long a run waits for the store to open and deadwax to be askable, the app having just launched for it.
    public static let openWaitMs: Int64 = 10_000
    /// (slice 3's review) A run's own deadline, well inside iOS's ~30 s: the check and the reads are waited for this
    /// long (the store's opening wait within it), and stopped there...
    public static let followMs: Int64 = 15_000
    /// ...and the plan that hands over what they let go within the rest of this.
    public static let runMs: Int64 = 20_000
    /// A relaunch for the background session's events: its events and the plan after them within this, one budget
    /// (iOS gives about 30 s).
    public static let eventsMs: Int64 = 25_000

    /// What is left of `budgetMs` after `elapsedMs` - never below nothing.
    public static func left(_ budgetMs: Int64, elapsedMs: Int64) -> Int64 { max(budgetMs - max(elapsedMs, 0), 0) }
    /// Debug keeps this many runs.
    public static let kept = 5
    /// ...in UserDefaults, under this key (`raw`'s JSON), per phone.
    public static let runsKey = "libraryBackgroundRuns"

    /// What to do with each task's request.
    public enum Ask: String, Sendable, Equatable {
        /// Ask for it (a request already asked for is replaced).
        case ask
        /// Cancel its request.
        case cancel
        /// Leave it as it is: what it is for can't be read now.
        case leave
    }

    /// (slice 3's review) What to do with each task's request: the refresh with the switch on; the charger's with Only
    /// while charging on and songs only the library wants still to come - whatever wait they show (a Wi-Fi, deadwax or
    /// network wait hides the charger's, and the request needs the network anyway), and whether or not the phone is
    /// charging now (it may be unplugged while the app is suspended). `libraryToCome` nil: the store isn't open, so the
    /// charger's is left as it is. `ran`: the task iOS is running now - its request was used up, so one left as it is
    /// is asked for again. Unreadable (`stateReadable`): every request is left as it is, but the one used up.
    public static func asks(readable: Bool, on: Bool, onlyWhileCharging: Bool, libraryToCome: Bool?,
                            ran: String? = nil) -> [String: Ask] {
        var out: [String: Ask]
        if !readable {
            out = [refreshID: .leave, chargingID: .leave]
        } else {
            let charger: Ask
            if !on || !onlyWhileCharging {
                charger = .cancel
            } else if let libraryToCome {
                charger = libraryToCome ? .ask : .cancel
            } else {
                charger = .leave
            }
            out = [refreshID: on ? .ask : .cancel, chargingID: charger]
        }
        if let ran, out[ran] == .leave { out[ran] = .ask }
        return out
    }

    /// Songs only your library wants are still to come (asked for, not here): what the charger's task is for.
    public static func libraryToCome(_ songs: [DownloadPlan.Asked]) -> Bool {
        songs.contains { (song: DownloadPlan.Asked) -> Bool in song.isLibrary }
    }

    /// (slice 3's review) Whether this launch read the phone's settings: UserDefaults can't be read before the phone's
    /// first unlock (iOS may launch the app in the background then), when every switch would read as off. `kept`: the
    /// mark every launch that could read them leaves (`readableKey`) was read at launch; `protectedDataAvailable`: the
    /// phone is unlocked now (a first launch ever has no mark yet, and is unlocked).
    public static func stateReadable(kept: Bool, protectedDataAvailable: Bool) -> Bool { kept || protectedDataAvailable }

    /// The mark, in UserDefaults.
    public static let readableKey = "libraryStateReadable"

    /// One run, for Debug.
    public struct Run: Codable, Sendable, Equatable {
        /// `refreshID` or `chargingID`.
        public let task: String
        /// When it began (ms).
        public let began: Int64
        /// How long it took (s).
        public let seconds: Double
        /// What came of it: a check made (and answered), albums read, albums downloading, or why nothing was done.
        public let outcome: Outcome

        public init(task: String, began: Int64, seconds: Double, outcome: Outcome) {
            self.task = task
            self.began = began
            self.seconds = seconds
            self.outcome = outcome
        }
    }

    public enum Outcome: Codable, Sendable, Equatable {
        /// The check answered (or a check of the store's opening stood), `read` albums' songs read, `downloading`
        /// albums of the library with tasks out at its end (handed to iOS); `charging` the phone's power at its end.
        case ran(checked: Bool, read: Int, downloading: Int, charging: Bool)
        /// Download your library is off (a request left from before it was turned off).
        case off
        /// No store opened, or deadwax couldn't be asked, within `openWaitMs`.
        case couldntAsk
        /// iOS ended it before it finished.
        case expired
    }

    /// The runs kept, newest first, with `run` added - at most `kept`.
    public static func keep(_ run: Run, in runs: [Run]) -> [Run] {
        Array(([run] + runs).prefix(kept))
    }

    /// Debug's lines kept as UserDefaults keeps them: JSON; nil for none. Read back, a list that can't be read is none.
    public static func raw(_ runs: [Run]) -> Data? {
        guard !runs.isEmpty else { return nil }
        return try? JSONEncoder().encode(runs)
    }

    public static func runs(raw: Data?) -> [Run] {
        guard let raw else { return [] }
        return (try? JSONDecoder().decode([Run].self, from: raw)) ?? []
    }
}
