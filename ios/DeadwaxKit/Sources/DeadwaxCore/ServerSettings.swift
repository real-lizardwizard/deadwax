import Foundation

// Server settings on the phone (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; notes/ios.md "Server settings
// on the phone"): every group `GET /deadwax/settings` answers, each setting's row, the drafts and the one save, the
// organizing verdict, Re-time saved lyrics, MusicBrainz's saved answers and Connections - the web's app/ServerSettings.tsx,
// components/SettingsView.tsx, components/RetimeLyrics.tsx, components/MusicBrainzAnswers.tsx and You.tsx's Connections,
// over ui/src/lib/serverSettings.ts, musicbrainzAnswers.ts, lyrics.ts and errorWords.ts. Every rule and word here is the
// web's, held to it by Tests/DeadwaxCoreTests/Fixtures/server/server-vectors.json (ios/scripts/export-server-vectors.cjs
// runs the TypeScript as it is; ui/test/iosserver.sim.cjs checks it is current) - but for the phone's own few, said where
// they are: each group a page of its own with its own mark (`groupMarks`), a value the server sends that isn't among a
// setting's choices kept in its menu (`pickerChoices`), a save that never answered read again (`SettingsFlow`), Re-time's
// stops of the phone's own (`RetimeRun.Stop`), and who may re-time (`Parts.retime`).

// MARK: the answers

/// One setting as the server reports it (src/routes/settings.py `_setting`; ui/src/api/settings.ts ServerSetting).
public struct ServerSetting: Decodable, Sendable, Equatable, Identifiable {
    /// The environment variable's name, shown as it is - what you go and edit.
    public let key: String
    /// The value in force, or nil - for a secret only "set" or nil, never what it is.
    public let value: String?
    /// "the container environment", ".env", or nil: which file supplied it.
    public let source: String?
    /// "ok", "unset" or "error" - only "error" is worth a mark.
    public let status: String
    /// What is wrong, in words, when something is.
    public let detail: String?
    /// What it controls.
    public let effect: String
    public let required: Bool
    public let secret: Bool
    /// Whether it can be changed here at all - and, when not, why (`lockedReason`, said as it comes).
    public let editable: Bool
    public let lockedReason: String?
    /// Saved here, overriding the environment - with what a revert brings back (`envValue`, never a secret's).
    public let overridden: Bool
    public let envValue: String?
    /// For a secret, whether compose or .env holds one (2.0.0-player.65) - never what.
    public let envSet: Bool?
    /// The values it takes, each with its label, in the web's order (`Object.entries`) - nil for a free one.
    public internal(set) var choices: [ServerSettings.Choice]?

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, value, source, status, detail, effect, required, secret, editable, overridden, choices
        case lockedReason = "locked_reason"
        case envValue = "env_value"
        case envSet = "env_set"
    }

    public init(key: String, value: String? = nil, source: String? = nil, status: String = "ok", detail: String? = nil,
                effect: String = "", required: Bool = false, secret: Bool = false, editable: Bool = true,
                lockedReason: String? = nil, overridden: Bool = false, envValue: String? = nil, envSet: Bool? = nil,
                choices: [ServerSettings.Choice]? = nil) {
        self.key = key
        self.value = value
        self.source = source
        self.status = status
        self.detail = detail
        self.effect = effect
        self.required = required
        self.secret = secret
        self.editable = editable
        self.lockedReason = lockedReason
        self.overridden = overridden
        self.envValue = envValue
        self.envSet = envSet
        self.choices = choices
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        key = try fields.decode(String.self, forKey: .key)
        value = fields.looseField(String.self, .value)
        source = fields.looseField(String.self, .source)
        status = fields.looseField(String.self, .status) ?? "ok"
        detail = fields.looseField(String.self, .detail)
        effect = fields.looseField(String.self, .effect) ?? ""
        required = fields.looseField(Bool.self, .required) ?? false
        secret = fields.looseField(Bool.self, .secret) ?? false
        editable = fields.looseField(Bool.self, .editable) ?? false
        lockedReason = fields.looseField(String.self, .lockedReason)
        overridden = fields.looseField(Bool.self, .overridden) ?? false
        envValue = fields.looseField(String.self, .envValue)
        envSet = fields.looseField(Bool.self, .envSet)
        //? JSONDecoder keeps no key order: put in the web's order by `ServerSettingsAnswer.read` from the body itself -
        //? until then, the order JavaScript gives keys it has no order for
        choices = fields.looseMap(String.self, .choices).map { map in
            ServerSettings.jsOrder(map.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) })
                .map { ServerSettings.Choice(value: $0, label: map[$0] ?? "") }
        }
    }
}

/// A group of settings (`{id, label, note, settings}`) - each a page of its own on the phone.
public struct ServerSettingGroup: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let note: String
    public internal(set) var settings: [ServerSetting]

    enum CodingKeys: String, CodingKey { case id, label, note, settings }

    public init(id: String, label: String = "", note: String = "", settings: [ServerSetting] = []) {
        self.id = id
        self.label = label
        self.note = note
        self.settings = settings
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        label = fields.looseField(String.self, .label) ?? ""
        note = fields.looseField(String.self, .note) ?? ""
        settings = fields.looseList(ServerSetting.self, .settings) ?? []
    }
}

/// Whether organizing can file anything, and every reason it can't (`organizing`).
public struct Organizing: Decodable, Sendable, Equatable {
    public let enabled: Bool
    public let blockers: [String]

    enum CodingKeys: String, CodingKey { case enabled, blockers }

    public init(enabled: Bool, blockers: [String] = []) {
        self.enabled = enabled
        self.blockers = blockers
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        blockers = fields.looseList(String.self, .blockers) ?? []
        enabled = fields.looseField(Bool.self, .enabled) ?? blockers.isEmpty
    }
}

/// `GET /deadwax/settings` (and `PUT`'s answer): the settings as the asker may change them.
public struct ServerSettingsAnswer: Decodable, Sendable, Equatable {
    public let version: String
    public let editable: Bool
    public internal(set) var groups: [ServerSettingGroup]
    public let organizing: Organizing

    enum CodingKeys: String, CodingKey { case version, editable, groups, organizing }

    public init(version: String = "", editable: Bool = false, groups: [ServerSettingGroup] = [],
                organizing: Organizing = Organizing(enabled: true)) {
        self.version = version
        self.editable = editable
        self.groups = groups
        self.organizing = organizing
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        version = fields.looseField(String.self, .version) ?? ""
        editable = fields.looseField(Bool.self, .editable) ?? false
        groups = fields.looseList(ServerSettingGroup.self, .groups) ?? []
        organizing = fields.looseField(Organizing.self, .organizing) ?? Organizing(enabled: true)
    }

    /// Every setting, group by group (the web's `groups.flatMap((group) => group.settings)`).
    public var settings: [ServerSetting] { groups.flatMap(\.settings) }

    /// The first setting by that name (the web's `settings.find`).
    public func setting(_ key: String) -> ServerSetting? {
        settings.first { WebText.same($0.key, key) }
    }

    /// The setting an edit is compared with: the last by that name (ServerSettings.tsx's `settingsByKey`, a Map each
    /// setting is set into in turn).
    public func committed(_ key: String) -> ServerSetting? {
        settings.last { WebText.same($0.key, key) }
    }

    /// A body read, each setting's choices in the order the web lists them: `Object.entries` of the object as
    /// JSON.parse makes it - its keys as written, but those that are array indices first, in ascending order.
    public static func read(_ body: Data) throws -> ServerSettingsAnswer {
        var answer = try JSONDecoder().decode(ServerSettingsAnswer.self, from: body)
        answer.order(OrderedJSON.parse(body)?["groups"])
        return answer
    }

    /// Each setting's choices put in the order `groups` (the body's own, read in order) writes them - matched by the
    /// group's id and the setting's key, as a group or a setting read leniently may have been left out.
    mutating func order(_ ordered: OrderedJSON?) {
        guard case .array(let rows)? = ordered else { return }
        var written: [String: [String: [ServerSettings.Choice]]] = [:]
        for row in rows {
            guard case .string(let group)? = row["id"], case .array(let settings)? = row["settings"] else { continue }
            for setting in settings {
                guard case .string(let key)? = setting["key"], case .object(let choices)? = setting["choices"] else {
                    continue
                }
                guard written[group]?[key] == nil else { continue }
                //? a value written twice keeps its first place with its LAST label, as JSON.parse makes it - read
                //? from the body, as JSONDecoder's pick between the two is its own (Foundation's kept the first);
                //? a label that isn't a string is left out, as looseMap leaves it
                written[group, default: [:]][key] = ServerSettings.jsOrder(WebText.unique(choices.map(\.0)))
                    .compactMap { value in
                        let last = choices.last { WebText.same($0.0, value) }?.1
                        guard case .string(let label)? = last else { return nil }
                        return ServerSettings.Choice(value: value, label: label)
                    }
            }
        }
        for g in groups.indices {
            for s in groups[g].settings.indices where groups[g].settings[s].choices != nil {
                guard let choices = written[groups[g].id]?[groups[g].settings[s].key] else { continue }
                groups[g].settings[s].choices = choices
            }
        }
    }
}

/// One setting to change, as `PUT /deadwax/settings` takes it (src/routes/settings.py SettingUpdate): its value, or nil
/// to revert it to the environment's - sent as null, never left out.
public struct SettingUpdate: Encodable, Sendable, Equatable {
    public let key: String
    public let value: String?

    enum CodingKeys: String, CodingKey { case key, value }

    public init(key: String, value: String?) {
        self.key = key
        self.value = value
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(key, forKey: .key)
        try fields.encode(value, forKey: .value)
    }
}

/// MusicBrainz's saved answers (`GET /settings/musicbrainz_cache`, and Clear's answer; ui/src/api/musicbrainzCache.ts).
public struct SavedAnswersStats: Decodable, Sendable, Equatable {
    public let enabled: Bool
    public let path: String
    public let bytes: Double
    public let answers: Double
    public let limitMb: Double
    public let problem: String?

    enum CodingKeys: String, CodingKey {
        case enabled, path, bytes, answers, problem
        case limitMb = "limit_mb"
    }

    public init(enabled: Bool = true, path: String = "", bytes: Double = 0, answers: Double = 0, limitMb: Double = 0,
                problem: String? = nil) {
        self.enabled = enabled
        self.path = path
        self.bytes = bytes
        self.answers = answers
        self.limitMb = limitMb
        self.problem = problem
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        enabled = fields.looseField(Bool.self, .enabled) ?? false
        path = fields.looseField(String.self, .path) ?? ""
        bytes = fields.looseField(Double.self, .bytes) ?? 0
        answers = fields.looseField(Double.self, .answers) ?? 0
        limitMb = fields.looseField(Double.self, .limitMb) ?? 0
        problem = fields.looseField(String.self, .problem)
    }
}

/// A ping's answer (`/search_musicbrainz/ping`, `/monitor_slskd/ping`; ui/src/api/connections.ts PingAnswer): `status`
/// "ok", or "failed" with `code` (a name, or slskd's HTTP status as a number) and `error`, the sentence under it.
public struct PingAnswer: Decodable, Sendable, Equatable {
    public let status: String
    public let code: String?
    public let error: String?

    enum CodingKeys: String, CodingKey { case status, code, error }

    public init(status: String, code: String? = nil, error: String? = nil) {
        self.status = status
        self.code = code
        self.error = error
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        //? String(answer.status): a missing one is "undefined", never ok
        status = fields.looseField(String.self, .status) ?? "undefined"
        //? a number as JavaScript's String() writes it (401, not 401.0)
        code = fields.looseField(String.self, .code) ?? fields.looseField(Double.self, .code).map(WebText.number)
        error = fields.looseField(String.self, .error)
    }
}

/// What Re-time saved lyrics sends for one album (LyricsRequest): its folder, the lyrics already there re-timed to the
/// lead that is saved - none fetched, none replaced.
public struct RetimeBody: Encodable, Sendable, Equatable {
    public let albumPath: String
    public let replace: Bool
    public let retime: Bool

    public init(albumPath: String) {
        self.albumPath = albumPath
        self.replace = false
        self.retime = true
    }

    enum CodingKeys: String, CodingKey {
        case replace, retime
        case albumPath = "album_path"
    }
}

/// What a re-time of one album did (the lyrics fetch's summary, with `retime`): `retimed` rewritten, `unchanged` already
/// at the lead, `custom` left alone - not LRCLIB's timings any more - and `failed`.
public struct RetimeSummary: Decodable, Sendable, Equatable {
    public let retimed: Int
    public let unchanged: Int
    public let custom: Int
    public let failed: Int

    enum CodingKeys: String, CodingKey { case retimed, unchanged, custom, failed }

    public init(retimed: Int = 0, unchanged: Int = 0, custom: Int = 0, failed: Int = 0) {
        self.retimed = retimed
        self.unchanged = unchanged
        self.custom = custom
        self.failed = failed
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        retimed = fields.looseField(Int.self, .retimed) ?? 0
        unchanged = fields.looseField(Int.self, .unchanged) ?? 0
        custom = fields.looseField(Int.self, .custom) ?? 0
        failed = fields.looseField(Int.self, .failed) ?? 0
    }
}

// MARK: the rules

/// Server settings' rules and words (serverSettings.ts, SettingsView.tsx, ServerSettings.tsx).
public enum ServerSettings {
    /// One of a setting's values, with the words its menu says for it.
    public struct Choice: Sendable, Equatable, Hashable, Identifiable {
        public let value: String
        public let label: String

        public var id: String { value }

        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }

    /// The order `Object.entries` lists an object's keys in, given them as written: array indices ("0", "250" - a
    /// whole number below 2^32 - 1 written without a leading zero) first, ascending, then the rest as written.
    public static func jsOrder(_ keys: [String]) -> [String] {
        let indices = keys.compactMap { key in arrayIndex(key).map { (key, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
        return indices + keys.filter { arrayIndex($0) == nil }
    }

    static func arrayIndex(_ key: String) -> UInt64? {
        let units = Array(key.utf16)
        guard !units.isEmpty, units.count <= 10, units.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        guard units.count == 1 || units[0] != 0x30, let value = UInt64(key), value < 4_294_967_295 else { return nil }
        return value
    }

    // MARK: the tabs, as sections

    /// `SettingsTab`: Server settings' three tabs - on the phone, the root's three sections of group rows.
    public enum Tab: String, Sendable, CaseIterable, Hashable {
        case library, downloads, connections
    }

    /// `SERVER_TABS`: the tabs in the web's order, each with its label and hint.
    public static let tabs: [Tab] = [.library, .downloads, .connections]

    public static func label(_ tab: Tab) -> String {
        switch tab {
        case .library: return "Library"
        case .downloads: return "Downloads"
        case .connections: return "Connections"
        }
    }

    public static func hint(_ tab: Tab) -> String {
        switch tab {
        case .library: return "Paths, organizing, covers and lyrics"
        case .downloads: return "Choosing and fetching from Soulseek"
        case .connections: return "slskd, MusicBrainz, Navidrome and the picture sources"
        }
    }

    /// `SAVED_ANSWERS_GROUP` and `SAVED_ANSWERS_PATH` (musicbrainzAnswers.ts): the group Clear is drawn under, and the
    /// setting whose draft holds Clear back.
    public static let savedAnswersGroup = "musicbrainz-cache"
    public static let savedAnswersPath = "MUSICBRAINZ_CACHE_PATH"
    /// The group Re-time saved lyrics is drawn under, and the setting whose draft holds it back (ServerSettings.tsx).
    public static let lyricsGroup = "lyrics"
    public static let leadKey = "LYRICS_LEAD_MS"
    /// The group the Library's Set up Navidrome opens (`showServerSettingsTab('connections')`'s, as a page).
    public static let connectionsGroup = "connections"
    /// The group organizing being blocked marks (the phone's own: the web marks its Library tab).
    public static let organizingGroup = "organizing"

    /// `tabForGroup(groupId)`: which tab a group sits on - one this doesn't know under Library, never nowhere.
    public static func tab(forGroup id: String) -> Tab {
        if id == "connections" || id == "logins" || id == savedAnswersGroup { return .connections }
        if id == "downloads" || id == "soulseek" { return .downloads }
        return .library
    }

    /// A tab's (or, on the phone, a group's) mark: a setting there needs attention, else it holds an unsaved change.
    public enum Mark: String, Sendable, Equatable {
        case attention, unsaved
    }

    /// `tabMarks(server, draftEnv)`: 'attention' where a setting has status error (and Library while organizing is
    /// blocked), else 'unsaved' where a draft's setting sits - a draft of no setting the answer lists under Library.
    public static func tabMarks(_ answer: ServerSettingsAnswer?, _ drafts: Drafts) -> [Tab: Mark] {
        var marks: [Tab: Mark] = [:]
        var groupOf: [String: String] = [:]
        for group in answer?.groups ?? [] {
            for setting in group.settings {
                groupOf[setting.key] = group.id
                if setting.status == "error" { marks[tab(forGroup: group.id)] = .attention }
            }
        }
        if let answer, !answer.organizing.enabled, !answer.organizing.blockers.isEmpty { marks[.library] = .attention }
        for key in drafts.keys {
            let at = tab(forGroup: groupOf[key] ?? "")
            if marks[at] == nil { marks[at] = .unsaved }
        }
        return marks
    }

    /// The phone's own, `tabMarks` taken per group: a group's row is marked 'attention' where one of its settings has
    /// status error - and the Organizing group while organizing is blocked, the verdict's own group - else 'unsaved'
    /// where it holds a draft. A tab's mark is then its groups' (a draft of no setting listed marks no group).
    public static func groupMarks(_ answer: ServerSettingsAnswer?, _ drafts: Drafts) -> [String: Mark] {
        var marks: [String: Mark] = [:]
        var groupOf: [String: String] = [:]
        for group in answer?.groups ?? [] {
            for setting in group.settings {
                groupOf[setting.key] = group.id
                if setting.status == "error" { marks[group.id] = .attention }
            }
        }
        if let answer, !answer.organizing.enabled, !answer.organizing.blockers.isEmpty,
           answer.groups.contains(where: { $0.id == organizingGroup }) {
            marks[organizingGroup] = .attention
        }
        for key in drafts.keys {
            guard let group = groupOf[key] else { continue }
            if marks[group] == nil { marks[group] = .unsaved }
        }
        return marks
    }

    /// The root's sections: each tab with its groups, in the order the server sends them.
    public static func sections(_ answer: ServerSettingsAnswer) -> [(tab: Tab, groups: [ServerSettingGroup])] {
        tabs.map { tab in (tab, answer.groups.filter { self.tab(forGroup: $0.id) == tab }) }.filter { !$0.groups.isEmpty }
    }

    /// A group's mark said: "Needs attention", "Unsaved" - the rows' badges' words.
    public static func markWords(_ mark: Mark) -> String {
        mark == .attention ? needsAttention : unsavedBadge
    }

    // MARK: the drafts

    /// Every edit not yet saved, in the order the web's object holds them (`{ ...current, [key]: value }`: a key edited
    /// again keeps its place, one dropped and edited again goes last) - so the save's batch, and the order a refusal
    /// names its settings in, are the web's. A value, or a revert to the environment's (the web's `null`).
    public struct Drafts: Sendable, Equatable {
        public enum Value: Sendable, Equatable {
            case text(String)
            case revert
        }

        public struct Entry: Sendable, Equatable {
            public let key: String
            public let value: Value
        }

        public private(set) var entries: [Entry] = []

        public init() {}

        public init(_ entries: [(String, Value)]) {
            for (key, value) in entries { set(key, value) }
        }

        public var keys: [String] { entries.map(\.key) }
        public var count: Int { entries.count }
        public var isEmpty: Bool { entries.isEmpty }

        public subscript(key: String) -> Value? {
            entries.first { WebText.same($0.key, key) }?.value
        }

        public func has(_ key: String) -> Bool { self[key] != nil }

        /// `[key]: value`: in its place when it is there, else last.
        public mutating func set(_ key: String, _ value: Value) {
            if let at = entries.firstIndex(where: { WebText.same($0.key, key) }) {
                entries[at] = Entry(key: key, value: value)
            } else {
                entries.append(Entry(key: key, value: value))
            }
        }

        /// `delete next[key]`.
        public mutating func remove(_ key: String) {
            entries.removeAll { WebText.same($0.key, key) }
        }

        /// The save's batch (`Object.entries(sent).map(([key, value]) => ({ key, value }))`).
        public var updates: [SettingUpdate] {
            entries.map { entry in
                switch entry.value {
                case .text(let text): return SettingUpdate(key: entry.key, value: text)
                case .revert: return SettingUpdate(key: entry.key, value: nil)
                }
            }
        }
    }

    /// `editedEnvDraft(current, key, value, committed)`: the drafts after typing `value` into a setting - one set back
    /// to the value already saved is no change, and leaves the drafts, except a secret's (it has no value to compare).
    public static func edited(_ drafts: Drafts, key: String, value: String, committed: ServerSetting?) -> Drafts {
        var next = drafts
        next.set(key, .text(value))
        if let committed, !committed.secret, WebText.same(committed.value ?? "", value) { next.remove(key) }
        return next
    }

    /// Revert to the environment pressed (`{ ...state.drafts, [key]: null }`).
    public static func reverted(_ drafts: Drafts, key: String) -> Drafts {
        var next = drafts
        next.set(key, .revert)
        return next
    }

    /// `draftsAfterSave(current, sent)`: what is left once a save of `sent` answered - only what was sent, and still as
    /// it was sent, goes; a key typed again meanwhile, or one the save never carried, stays a draft.
    public static func afterSave(_ current: Drafts, sent: Drafts) -> Drafts {
        var left = Drafts()
        for entry in current.entries where sent[entry.key] != entry.value {
            left.set(entry.key, entry.value)
        }
        return left
    }

    /// The phone's own: what is left once a save that never answered (or answered a 5xx) has been read again - each
    /// draft still as it was sent goes when the settings now hold it (a value saved, a revert no longer overridden); a
    /// secret, whose value the settings never show, stays, to be saved again (the same key again is harmless); a key
    /// typed again meanwhile, or never sent, stays.
    public static func stillDiffering(_ current: Drafts, sent: Drafts, now answer: ServerSettingsAnswer) -> Drafts {
        var left = Drafts()
        for entry in current.entries {
            guard sent[entry.key] == entry.value, let setting = answer.setting(entry.key) else {
                left.set(entry.key, entry.value)
                continue
            }
            let landed: Bool
            switch entry.value {
            case .text(let text): landed = !setting.secret && WebText.same(setting.value ?? "", text)
            case .revert: landed = !setting.overridden
            }
            if !landed { left.set(entry.key, entry.value) }
        }
        return left
    }

    /// The batch's wait (`PUT /settings`): the settings read again (`settingsRead`, as the GET is given), and before it
    /// each setting's row written and the overrides read back - each its own SQLite connection, which may wait out the
    /// busy timeout (store._connect's 10 s) first; never less than Routes.timeouts gives the route.
    public static func saveWait(_ count: Int) -> Double {
        EditWaits.wait(settingsRead + storeBusy * Double(count + 1), floor: Routes.timeouts[Routes.saveServerSettings])
    }

    /// The settings' read: no bound on the server - each path stat'ed and slskd's folder probed (at most PROBE_VISITS
    /// folders walked) - so the value is pinned (Routes.timeouts), not worked out.
    public static var settingsRead: Double { Routes.timeouts[Routes.serverSettings] ?? 30 }
    /// store._connect's busy timeout: how long one SQLite connection may wait for the database.
    public static let storeBusy: Double = 10

    // MARK: a secret retyped with its address

    /// `RETYPE_WITH_ADDRESS`: a secret sent to an address with every request - its address, and what its row says.
    struct Retype {
        let address: String
        let note: String
        let reverted: String
    }

    static let retype: [String: Retype] = [
        "NAVIDROME_PASSWORD": Retype(
            address: "NAVIDROME_URL",
            note: "Type the password again to go with the new address - deadwax won't send the saved one to an address "
                + "it wasn't entered for.",
            reverted: "Reverting brings back the environment's password, which was given for the environment's address "
                + "- type the password again, or revert NAVIDROME_URL in the same save."),
        "SLSKD_APIKEY": Retype(
            address: "SLSKD_URL",
            note: "Type the API key again to go with the new address - deadwax won't send the saved one to an address "
                + "it wasn't entered for.",
            reverted: "Reverting brings back the environment's API key, which was given for the environment's address - "
                + "type the key again, or revert SLSKD_URL in the same save."),
    ]

    /// `retypeSecretNote(key, server, draftEnv)`: what a secret's row says while its address has a new value and the
    /// secret hasn't been typed to go with it - or (2.0.0-player.65) the secret is reverted while the address after the
    /// save isn't the environment's. The server refuses both saves; this says so beside the field first.
    public static func retypeNote(_ key: String, _ answer: ServerSettingsAnswer?, _ drafts: Drafts) -> String? {
        guard let rule = retype[key] else { return nil }
        let row = answer?.setting(rule.address)
        let current = row?.value ?? ""
        let secret = answer?.setting(key)
        let url = drafts[rule.address]

        if drafts[key] == .revert {
            if secret?.envSet != true || url == .revert { return nil }
            let environments = (row?.overridden == true ? row?.envValue : row?.value) ?? ""
            let after: String
            if case .text(let typed)? = url { after = JSText.trim(typed) } else { after = JSText.trim(current) }
            return !after.isEmpty && !WebText.same(after, JSText.trim(environments)) ? rule.reverted : nil
        }

        guard case .text(let typed)? = url else { return nil }
        let address = JSText.trim(typed)
        if address.isEmpty || WebText.same(address, JSText.trim(current)) { return nil }
        if (secret?.value ?? "").isEmpty { return nil }
        if case .text(let secretTyped)? = drafts[key], !JSText.trim(secretTyped).isEmpty { return nil }
        return rule.note
    }

    // MARK: a row

    /// What a setting's row draws (SettingRow): its control, the value in it, where the value came from, its badges,
    /// what it does, why it's locked, the revert, and what another row's edit asks of it.
    public struct Row: Sendable, Equatable {
        public enum Control: Sendable, Equatable {
            /// Not editable here: "Locked", with `locked`.
            case locked
            /// A menu of the values it takes.
            case choices
            /// A field - a secure one for a secret.
            case field(secret: Bool)
        }

        public let key: String
        public let control: Control
        /// The value in the field (or chosen): the draft, else the saved value - a secret's always empty.
        public let value: String
        public let placeholder: String
        /// "Set here", "From the container environment", or nil.
        public let source: String?
        public let unsaved: Bool
        public let attention: Bool
        public let effect: String
        /// Why it can't be changed, as the server says it.
        public let locked: String?
        /// Revert to the environment's label, with what it brings back - nil where there is nothing to revert.
        public let revert: String?
        /// A revert is drafted: "Will revert to the environment on save."
        public let reverting: Bool
        /// What another row's edit asks of this one (`retypeNote`).
        public let note: String?
        /// What is wrong, while it isn't being edited.
        public let detail: String?
    }

    /// `SettingRow`'s own rules, for `setting` under `drafts`.
    public static func row(_ setting: ServerSetting, _ answer: ServerSettingsAnswer?, _ drafts: Drafts) -> Row {
        let draft = drafts[setting.key]
        let edited = draft != nil
        let reverting = draft == .revert
        let value: String
        if case .text(let typed)? = draft { value = typed } else { value = setting.secret ? "" : setting.value ?? "" }
        let control: Row.Control = !setting.editable ? .locked : setting.choices != nil ? .choices
            : .field(secret: setting.secret)
        let placeholder = setting.secret ? ((setting.value ?? "").isEmpty ? notSet : secretSet) : notSet
        let source: String?
        if setting.overridden && !edited {
            source = setHere
        } else if let from = setting.source, !from.isEmpty {
            source = "From \(from)"
        } else {
            source = nil
        }
        let envValue = setting.envValue ?? ""
        return Row(
            key: setting.key, control: control, value: value, placeholder: placeholder, source: source,
            unsaved: edited, attention: setting.status == "error" && !edited, effect: setting.effect,
            locked: !setting.editable && !(setting.lockedReason ?? "").isEmpty ? setting.lockedReason : nil,
            revert: setting.overridden && setting.editable && !reverting
                ? revertLabel + (envValue.isEmpty ? "" : " (\(envValue))") : nil,
            reverting: reverting, note: retypeNote(setting.key, answer, drafts),
            detail: !edited && !(setting.detail ?? "").isEmpty ? setting.detail : nil)
    }

    /// The phone's own: a setting typed as an address (SLSKD_URL, NAVIDROME_URL...) takes the URL keyboard.
    public static func isAddress(_ key: String) -> Bool {
        key.utf16.count > 4 && key.utf16.reversed().starts(with: "_URL".utf16.reversed())
    }

    /// The phone's own: a menu's values - the setting's choices, and first the value in force when it isn't one of them
    /// (unset, or one the server doesn't know - its row says what is wrong), so the menu shows what is there rather than
    /// a value that isn't. (The web's dropdown shows its first choice then.)
    public static func pickerChoices(_ setting: ServerSetting, value: String) -> [Choice] {
        let choices = setting.choices ?? []
        if choices.contains(where: { WebText.same($0.value, value) }) { return choices }
        return [Choice(value: value, label: value.isEmpty ? notSetChoice : value)] + choices
    }

    // MARK: the words (ServerSettings.tsx, SettingsView.tsx)

    public static let title = "Server settings"
    /// The page's line - the web's: your own choices are in Settings (the web's tab too since its 2.1.35).
    public static let pageLine = "How deadwax runs, as your compose file or .env sets it. A change saved here takes "
        + "effect at once, with no restart, and is used instead of what the file says until you revert it. Your own "
        + "choices - what Get does, the quality floor, Format and whether cancelling asks first - are in Settings, under "
        + "Getting albums."
    public static let reading = "Reading the settings"
    public static let readFailed = "Couldn't read the settings."
    public static let rereadFailed = "Couldn't read the settings again just now."
    public static let saveFailed = "Couldn't save the settings."
    public static let tryAgain = "Try again"
    public static let discard = "Discard"
    public static let save = "Save changes"
    public static let saving = "Saving…"
    public static let saved = "Saved."
    public static let notSaved = "Not saved: "
    public static let setHere = "Set here"
    public static let unsavedBadge = "Unsaved"
    public static let needsAttention = "Needs attention"
    public static let locked = "Locked"
    public static let revertLabel = "Revert to the environment"
    public static let willRevert = "Will revert to the environment on save."
    public static let secretSet = "•••••••• (set)"
    public static let notSet = "not set"
    /// The phone's own: a menu's entry for a value that isn't one of its choices, when there is none.
    public static let notSetChoice = "Not set"
    /// The phone's own: a group's page whose group deadwax's settings no longer have (another version answered).
    public static let groupGone = "deadwax's settings have no such part any more. Go back to Server settings."
    public static let organizingOn = "Organizing is active — finished downloads will be moved into the library, tagged "
        + "and filed."
    public static let organizingOff = "Organizing will not file anything right now."

    /// The organizing verdict's heading.
    public static func verdict(_ organizing: Organizing) -> String {
        organizing.enabled ? organizingOn : organizingOff
    }

    /// "1 unsaved change", "2 unsaved changes".
    public static func unsavedCount(_ count: Int) -> String {
        "\(count) unsaved change\(count == 1 ? "" : "s")"
    }

    /// The save bar's words: the refusal, "Saved." once nothing is left, else how many are unsaved - "" with nothing to
    /// say.
    public static func barText(saveError: String?, justSaved: Bool, dirty: Int) -> String {
        if let saveError { return notSaved + saveError }
        if justSaved && dirty == 0 { return saved }
        if dirty != 0 { return unsavedCount(dirty) }
        return ""
    }

    /// A read that failed, as the page says it: "Couldn't read the settings." with nothing on screen (and Try again
    /// beside it), "Couldn't read the settings again just now." over the settings shown.
    public static func readFailure(_ error: any Error, admin: Bool, first: Bool) -> String {
        ErrorWords.notice("", error, admin: admin, failed: first ? readFailed : rereadFailed, retry: first)
    }

    /// What a save that didn't work says in the bar: deadwax's refusal (a 400) as it came - the rows' own words,
    /// "SLSKD_SEARCH_TIMEOUT: expected whole seconds, 3 to 60 - 8 is the default" - else in a listener's words, its own
    /// in brackets for whoever runs deadwax. A 403, the phone's own: a Managing page's NO_PERMISSION.
    public static func saveFailure(_ error: any Error, admin: Bool) -> String {
        if case .answered(let answer)? = error as? APIFailure {
            if answer.status == 400, let detail = answer.detail, !detail.isEmpty { return detail }
            if answer.status == 403 { return EditWords.noPermission }
        }
        return ErrorWords.notice("", error, admin: admin, failed: saveFailed)
    }

    /// The phone's own: a save that may have landed (no answer, or a 5xx) - deadwax's own words when it sent some (the
    /// bar says "deadwax may have finished this" while the settings are read again, and these after, should a draft
    /// still differ), else nil.
    public static func unansweredWords(_ error: any Error, admin: Bool) -> String? {
        EditWords.writeFailure(error, failed: saveFailed, admin: admin)
    }

    /// `onServerSettingsSaved`'s listener (App.tsx): a save that carried one of Navidrome's settings asks Navidrome
    /// again, so the Library's gate opens by itself.
    public static func asksNavidromeAgain(_ keys: [String]) -> Bool {
        keys.contains { $0.utf16.starts(with: "NAVIDROME_".utf16) }
    }

    /// The phone's own: a save that carried a setting of the Connections group checks the Connections rows again -
    /// they are on the page the save was made from.
    public static func checksConnectionsAgain(_ keys: [String], _ answer: ServerSettingsAnswer?) -> Bool {
        let group = answer?.groups.first { $0.id == connectionsGroup }?.settings.map(\.key) ?? []
        return keys.contains { key in group.contains { WebText.same($0, key) } }
    }

    // MARK: who may

    /// Who sees which part (App.tsx's `allowed={perms.has('server')}`; You.tsx's Connections for whoever runs deadwax -
    /// access.ts seesDetail, which Settings and the log is part of), and the phone's own: Re-time runs only with Edit
    /// albums, the permission of the route it asks for each album (the web offers it to everyone here, and each album is
    /// then refused).
    public struct Parts: Sendable, Equatable {
        public let page: Bool
        public let connections: Bool
        public let retime: Bool
        public let answers: Bool

        public init(page: Bool, connections: Bool, retime: Bool, answers: Bool) {
            self.page = page
            self.connections = connections
            self.retime = retime
            self.answers = answers
        }
    }

    public static func parts(_ access: Access) -> Parts {
        let page = access.can(.server)
        return Parts(page: page, connections: page && access.seesDetail, retime: page && access.can(.edit), answers: page)
    }

    /// Re-time with Settings and the log but not Edit albums: why it can't be started.
    public static let retimeNeedsEdit = "Re-timing needs Edit albums, which an admin hasn't given you."
}

// MARK: MusicBrainz's saved answers

/// MusicBrainz's saved answers, under their two settings (MusicBrainzAnswers.tsx, musicbrainzAnswers.ts): the file's size
/// and count, read each time the page shows (and afresh once a save changes either setting - `key`), and Clear - asked
/// first on the phone - refused while the path is a draft, while there is nothing to clear and while it goes. Every
/// decision here; the App only asks and keeps.
public struct SavedAnswers: Sendable, Equatable {
    public private(set) var stats: SavedAnswersStats?
    /// Why the file couldn't be read, or cleared.
    public private(set) var error: String?
    public private(set) var clearing = false
    public private(set) var cleared = false
    /// A Clear that never answered (or answered a 5xx): read again to see.
    public private(set) var checking = false
    /// The two settings as saved when the file was last read (`savedAnswersKey`).
    public private(set) var key: String?
    public private(set) var reads = 0

    public init() {}

    /// A state as the web's component holds it (the vectors' cases).
    init(stats: SavedAnswersStats?, error: String?, clearing: Bool, cleared: Bool) {
        self.stats = stats
        self.error = error
        self.clearing = clearing
        self.cleared = cleared
    }

    /// `savedAnswersKey(group)`: what the line is read again on - the group's settings as saved.
    public static func key(_ group: ServerSettingGroup) -> String {
        group.settings.map { "\($0.key)=\($0.value ?? "")" }.joined(separator: "|")
    }

    /// `describeBytes(bytes)`: bytes, KB, then MB to one place (1024s).
    public static func describeBytes(_ bytes: Double) -> String {
        if bytes < 1024 { return "\(WebText.number(bytes)) bytes" }
        if bytes < 1024 * 1024 { return "\(WebText.number(JSMath.round(bytes / 1024))) KB" }
        return "\(jsFixed(bytes / (1024 * 1024), 1)) MB"
    }

    /// "1,234 answers".
    static func answersCount(_ count: Double) -> String {
        let whole = count == count.rounded(.towardZero) && abs(count) < 1e15
            ? UpNextWords.grouped(Int(count)) : WebText.number(count)
        return "\(whole) answer\(count == 1 ? "" : "s")"
    }

    /// `describeSavedAnswers(stats, cleared)`: the line under Clear.
    public static func describe(_ stats: SavedAnswersStats, cleared: Bool) -> String {
        if let problem = stats.problem, !problem.isEmpty { return "Nothing is being saved: \(problem)." }
        let held = "\(answersCount(stats.answers)) in \(describeBytes(stats.bytes))"
        if !stats.enabled {
            return stats.answers != 0
                ? "Saving is off (MUSICBRAINZ_CACHE_MB is 0), and the file still holds \(held)."
                : "Saving is off (MUSICBRAINZ_CACHE_MB is 0): answers are kept in memory only, for an hour."
        }
        if stats.answers == 0 {
            return cleared ? "Cleared. The next answers are asked of MusicBrainz again." : "Nothing saved yet."
        }
        return "\(held) saved, of \(WebText.number(stats.limitMb)) MB."
    }

    // the words (MusicBrainzAnswers.tsx)
    public static let clear = "Clear MusicBrainz's saved answers"
    public static let clearingLabel = "Clearing…"
    public static let readingLine = "Reading the saved answers…"
    public static let saveFirst = "Save the new path first."
    public static let readFailed = "Couldn't read MusicBrainz's saved answers."
    public static let clearFailed = "Couldn't clear MusicBrainz's saved answers."
    /// Clear's title on the web, by its state - its hint, and (the last) what the phone's question says.
    public static let saveFirstHint = "Save the new path first - this clears the file that is saved"
    public static let clearingHint = "Clearing them…"
    public static let emptyHint = "Nothing saved to clear"
    public static let clearHint = "Every saved answer gone, on disk and in memory. Only speed is lost: the next answers "
        + "are asked of MusicBrainz again."
    /// The phone's question before a Clear (the web clears at once).
    public static let clearQuestion = "Clear MusicBrainz's saved answers?"
    public static let clearConfirm = "Clear"
    public static let cancel = "Cancel"

    /// The read's failure, as the web's `sayError(reason, '', { failed: READ_FAILED })`.
    public static func readFailure(_ error: any Error, admin: Bool) -> String {
        ErrorWords.notice("", error, admin: admin, failed: readFailed)
    }

    /// A Clear refused (a 4xx), as the web's `sayError(reason, '', { failed: CLEAR_FAILED })` - but a 403, the phone's
    /// own, in the words Save's 403 says: a Managing page's NO_PERMISSION.
    public static func clearFailure(_ error: any Error, admin: Bool) -> String {
        if case .answered(let answer)? = error as? APIFailure, answer.status == 403 { return EditWords.noPermission }
        return ErrorWords.notice("", error, admin: admin, failed: clearFailed)
    }

    /// The phone's own: a Clear that may have cleared (no answer, or a 5xx) - deadwax's own words when it sent some.
    public static func clearUnansweredWords(_ error: any Error, admin: Bool) -> String? {
        EditWords.writeFailure(error, failed: clearFailed, admin: admin)
    }

    /// Nothing to clear: nothing read, or no answers held (an empty file is a few KB of its own table, and stays).
    public var empty: Bool { stats == nil || stats?.answers == 0 }

    /// Clear refused: while it goes, while the path is a draft, with nothing to clear - and (the phone's) out of reach.
    public func refused(unsaved: Bool, online: Bool = true) -> Bool {
        clearing || unsaved || empty || !online
    }

    /// Clear's hint for its state (the web's title).
    public func hint(unsaved: Bool) -> String {
        unsaved ? Self.saveFirstHint : clearing ? Self.clearingHint : empty ? Self.emptyHint : Self.clearHint
    }

    /// The button's words.
    public var label: String { clearing ? Self.clearingLabel : Self.clear }

    /// The line beside Clear.
    public func line(unsaved: Bool) -> String {
        if unsaved { return Self.saveFirst }
        if let error { return error }
        if checking { return EditWords.mayHaveFinished }
        if let stats { return Self.describe(stats, cleared: cleared) }
        return Self.readingLine
    }

    /// Whether to read the file now: the group's page shows, in reach, nothing clearing - it is read each time the page
    /// shows (the web's `live`), afresh when a save named a different file (`readBegan`'s key), and after a Clear that
    /// never answered.
    public func readsNow(shown: Bool, online: Bool) -> Bool {
        shown && online && !clearing
    }

    /// A read begun, for the settings as saved now: a different file than last read starts afresh (the web re-keys
    /// the component on them).
    public mutating func readBegan(key now: String) -> Int {
        if key != now {
            stats = nil
            error = nil
            cleared = false
        }
        key = now
        reads += 1
        return reads
    }

    public mutating func readLanded(_ ticket: Int, _ answer: SavedAnswersStats) {
        guard ticket == reads else { return }
        stats = answer
        error = nil
        //? what the file holds now - a Clear's "Cleared." is the line only until the next read
        cleared = false
        checking = false
    }

    public mutating func readFailed(_ ticket: Int, _ words: String) {
        guard ticket == reads else { return }
        error = words
        checking = false
    }

    /// Clear pressed (and confirmed): false, and nothing asked, when it is refused.
    public mutating func clearBegan(unsaved: Bool, online: Bool) -> Int? {
        guard !refused(unsaved: unsaved, online: online) else { return nil }
        clearing = true
        error = nil
        reads += 1
        return reads
    }

    public mutating func clearLanded(_ ticket: Int, _ answer: SavedAnswersStats) {
        clearing = false
        guard ticket == reads else { return }
        stats = answer
        error = nil
        cleared = true
    }

    /// Clear refused (a 4xx): its words.
    public mutating func clearRefused(_ ticket: Int, _ words: String) {
        clearing = false
        guard ticket == reads else { return }
        error = words
    }

    /// Clear never answered, or answered a 5xx: it may have cleared - said, and read again (true: read now).
    public mutating func clearUnanswered(_ ticket: Int, _ words: String?) -> Bool {
        clearing = false
        guard ticket == reads else { return false }
        error = words
        checking = true
        return true
    }

    /// Clear cancelled: nothing came of it that is known.
    public mutating func clearDropped() {
        clearing = false
    }
}

// MARK: Re-time saved lyrics

/// Re-time saved lyrics (RetimeLyrics.tsx, lib/lyrics.ts describeRetime): the lyrics already saved moved to the lead that
/// is saved now - the library read (the real scan, not the saved one), then each album with lyrics, one at a time,
/// through the lyrics fetch with `retime`. Refused while the lead has a draft (it re-times to the SAVED lead). Kept
/// beyond the page, as the web keeps it in its module; how it ended is said once - let go as the page that showed it goes
/// (`pageGone`), and as soon as a new lead is drafted, and a run a new lead was drafted during has its words let go as it
/// ends (`leadMoved`: some of it is at each lead). Every decision here, the App only carrying them out
/// (ServerSettingsModel): each album asked for only through `next`, so a Stop, the app going to the background, deadwax
/// going out of reach, Edit albums going or the session ending lands after the album out, never during it.
public struct RetimeRun: Sendable, Equatable {
    /// Why a run stops before its last album (the phone's own, but `pressed` - the web's `stop`).
    public enum Stop: String, Sendable, Equatable {
        case pressed, background, outOfReach, notAllowed, sessionEnded
    }

    /// What a run has done so far (`RetimeTotals`).
    public struct Totals: Sendable, Equatable {
        public var retimed = 0
        public var unchanged = 0
        public var custom = 0
        public var failed = 0

        public init(retimed: Int = 0, unchanged: Int = 0, custom: Int = 0, failed: Int = 0) {
            self.retimed = retimed
            self.unchanged = unchanged
            self.custom = custom
            self.failed = failed
        }
    }

    /// Where it is.
    public enum Phase: Sendable, Equatable {
        /// Nothing to say: the prompt.
        case idle
        /// The library being read (`total` 0 - "Reading the library…").
        case reading
        /// An album at a time.
        case running
        /// Over: its words said until let go.
        case ended
    }

    /// What one album came to.
    public enum Step: Sendable, Equatable {
        /// It answered.
        case answered(RetimeSummary)
        /// deadwax refused it (a 4xx): every lyric of the album counted failed, as the web counts a throw.
        case refused
        /// It never answered, timed out or answered a 5xx: counted failed as the web does - and it may have re-timed
        /// all the same (the server carries on when the phone goes).
        case unanswered
        /// A 403: Edit albums isn't this person's - counted failed, and the run stops after it.
        case forbidden
    }

    /// What `next` says: the album to re-time now, the run just ended (say its words), or nothing to do.
    public enum Next: Sendable, Equatable {
        case album(ScanAlbum)
        case ended
        case nothing
    }

    public private(set) var phase: Phase = .idle
    public private(set) var albums: [ScanAlbum] = []
    public private(set) var total = 0
    public private(set) var done = 0
    public private(set) var totals = Totals()
    public private(set) var stop: Stop?
    public private(set) var out: ScanAlbum?
    /// The library's read failed: why (the run is over, with only this to say).
    public private(set) var error: String?
    /// A new lead was drafted while it ran: its words are let go as it ends.
    public private(set) var leadMoved = false
    /// An album never answered: it may have re-timed.
    public private(set) var maybe = false
    /// One more each run: a read for an older run lands nowhere.
    public private(set) var number = 0

    public init() {}

    /// A run is under way - the library read, or albums.
    public var running: Bool { phase == .reading || phase == .running }

    /// Start may be pressed: Edit albums, in reach, no draft of the lead, nothing running.
    public func startOpen(allowed: Bool, online: Bool, unsaved: Bool) -> Bool {
        allowed && online && !unsaved && !running
    }

    /// Start pressed: the run's number (its library read's ticket), or nil when it may not start.
    public mutating func start(allowed: Bool, online: Bool, unsaved: Bool) -> Int? {
        guard startOpen(allowed: allowed, online: online, unsaved: unsaved) else { return nil }
        number += 1
        phase = .reading
        albums = []
        total = 0
        done = 0
        totals = Totals()
        stop = nil
        out = nil
        error = nil
        leadMoved = false
        maybe = false
        return number
    }

    /// The library read for run `ticket`: the albums with lyrics are the run's.
    public mutating func read(_ ticket: Int, _ library: [ScanAlbum]) {
        guard ticket == number, phase == .reading else { return }
        albums = library.filter { $0.lyricsCount > 0 }
        total = albums.count
        phase = .running
    }

    /// The library's read failed for run `ticket`: the run over, with its words - or, a new lead drafted meanwhile,
    /// nothing.
    public mutating func readFailed(_ ticket: Int, _ words: String) {
        guard ticket == number, phase == .reading else { return }
        error = words
        end()
    }

    /// Asked before each album (the web's `if (stop || !ticket.current()) break`): the album to re-time now - or the
    /// run over, when it was told to stop, the permission went, deadwax is out of reach, or every album is done.
    public mutating func next(allowed: Bool, online: Bool) -> Next {
        guard phase == .running, out == nil else { return .nothing }
        if stop == nil, !allowed { stop = .notAllowed }
        if stop == nil, !online { stop = .outOfReach }
        if stop != nil || done >= total {
            end()
            return .ended
        }
        let album = albums[done]
        out = album
        return .album(album)
    }

    /// The album out came to `step`.
    public mutating func finished(_ step: Step) {
        guard phase == .running, let album = out else { return }
        out = nil
        switch step {
        case .answered(let summary):
            totals.retimed += summary.retimed
            totals.unchanged += summary.unchanged
            totals.custom += summary.custom
            totals.failed += summary.failed
        case .refused:
            totals.failed += album.lyricsCount
        case .unanswered:
            totals.failed += album.lyricsCount
            maybe = true
        case .forbidden:
            totals.failed += album.lyricsCount
            if stop == nil { stop = .notAllowed }
        }
        done += 1
    }

    /// What a failure is, for a step.
    public static func step(failure error: any Error) -> Step {
        if case .answered(let answer)? = error as? APIFailure, answer.status == 403 { return .forbidden }
        return RetagFlow.outcome(of: error) == .refused ? .refused : .unanswered
    }

    /// Stop pressed: once, while it runs.
    @discardableResult
    public mutating func stopPressed() -> Bool {
        stopUnder(.pressed)
    }

    /// The app went to the background, deadwax out of reach, the session ended: the run stops after the album out.
    public mutating func suspended() { stopUnder(.background) }
    public mutating func outOfReach() { stopUnder(.outOfReach) }
    public mutating func sessionEnded() { stopUnder(.sessionEnded) }

    @discardableResult
    private mutating func stopUnder(_ why: Stop) -> Bool {
        guard running, stop == nil else { return false }
        stop = why
        //? before the library has answered there is no album to finish: it ends as the read lands
        return true
    }

    /// The library answered after the run was told to stop: over before its first album.
    public var stopping: Bool { running && stop != nil }

    /// A new lead drafted: a run that ended was at the old one - let go; one running is let go as it ends.
    public mutating func leadDrafted() {
        if running { leadMoved = true } else if phase == .ended { letGo() }
    }

    /// The last page showing it went: an ended run has been said, and the next visit says the prompt.
    public mutating func pageGone() {
        if phase == .ended { letGo() }
    }

    private mutating func end() {
        out = nil
        phase = .ended
        //? (`ended(last)`) a new lead was typed while it ran: some of it is at each lead, so nothing is said of it
        if leadMoved { letGo() }
    }

    private mutating func letGo() {
        phase = .idle
        error = nil
        stop = nil
        maybe = false
        leadMoved = false
    }

    /// The screen stays on: a run under way and its page in front.
    public func keepsScreenOn(visible: Bool) -> Bool {
        visible && running
    }

    // MARK: the words (RetimeLyrics.tsx)

    public static let button = "Re-time saved lyrics"
    public static let readingLibrary = "Reading the library…"
    public static let saveFirst = "Save the new lead first."
    public static let prompt = "Lyrics saved before the lead changed keep their old timings until re-timed."
    public static let readFailed = "Couldn't read the library."

    /// The library's read failing, as the web's `sayError(caught, '', { failed: "Couldn't read the library.", retry:
    /// true })`.
    public static func readFailure(_ error: any Error, admin: Bool) -> String {
        ErrorWords.notice("", error, admin: admin, failed: readFailed, retry: true)
    }
    /// The button's hint (the web's title): what it does, or why it can't.
    public static let hint = "Move the timings of lyrics already saved to the lead above. Only files that are still "
        + "exactly LRCLIB's lyrics are touched."
    public static let saveFirstHint = "Save the new lead first - this re-times to the lead that is saved."

    /// `describeRetime(totals)`: one sentence for what a run did.
    public static func describe(_ totals: Totals) -> String {
        var parts = ["Re-timed \(totals.retimed) track\(totals.retimed == 1 ? "" : "s")"]
        if totals.unchanged != 0 { parts.append("\(totals.unchanged) already at this lead") }
        if totals.custom != 0 {
            parts.append("\(totals.custom) left alone - not LRCLIB's timings any more, so edited by hand or from "
                + "somewhere else")
        }
        if totals.failed != 0 { parts.append("\(totals.failed) failed - try again") }
        return parts.joined(separator: ", ")
    }

    /// The running button's words: "Re-timing 4 of 60 albums · Stop after this album", or the library being read.
    public static func runningLabel(done: Int, total: Int) -> String {
        total != 0 ? "Re-timing \(min(done + 1, total)) of \(total) albums · Stop after this album" : readingLibrary
    }

    public var runningLabel: String { Self.runningLabel(done: done, total: total) }

    /// The web's note under the button: the draft, the read's failure, how it ended, or the prompt.
    public static func note(unsaved: Bool, error: String?, ended: (totals: Totals, done: Int, total: Int)?) -> String {
        if unsaved { return saveFirst }
        if let error { return error }
        if let ended {
            return ErrorWords.asSentence(describe(ended.totals))
                + (ended.done < ended.total ? " Stopped at \(ended.done) of \(ended.total) albums." : "")
        }
        return prompt
    }

    /// The note, and - the phone's own - why it stopped short, and that an album may have re-timed unanswered.
    public func note(unsaved: Bool) -> String {
        let over: (totals: Totals, done: Int, total: Int)? = phase == .ended && error == nil ? (totals, done, total) : nil
        let said = Self.note(unsaved: unsaved, error: phase == .ended ? error : nil, ended: over)
        guard !unsaved, phase == .ended, error == nil else { return said }
        return ([said] + [stop.flatMap(Self.stopped), maybe ? Self.mayHaveRetimed : nil].compactMap { $0 })
            .joined(separator: " ")
    }

    /// The phone's own stops, said after the web's "Stopped at 14 of 60 albums.": running it again is safe - an album
    /// already at the lead is left as it is.
    public static func stopped(_ stop: Stop) -> String? {
        switch stop {
        case .pressed: return nil
        case .background: return "It stopped as the app went to the background - running it again carries on."
        case .outOfReach: return "It stopped as deadwax went out of reach - running it again once it's back carries on."
        case .notAllowed: return "It stopped: re-timing needs Edit albums, which an admin hasn't given you."
        case .sessionEnded: return "It stopped as your session ended - sign in again, and running it again carries on."
        }
    }

    /// An album that never answered may have been re-timed all the same.
    public static let mayHaveRetimed = "An album that didn't answer may have been re-timed all the same - running it "
        + "again is safe."
    /// Said while a run is under way and its page is in front.
    public static let screenOnNote = "The screen stays on while it runs and this page shows."
    /// (The Mac app, slice 7) Under a run under way on the Mac: ⌘Q stops it (the app's own, an album at a time), and
    /// running it again is safe. None on the iPhone, where closing the app is going to the background, said as it stops.
    public static func quitNote(_ device: Device) -> String? {
        device == .mac ? "Quitting deadwax stops it - open deadwax again, and running it again carries on." : nil
    }
}

// MARK: Connections

/// Connections (You.tsx's three rows, at the top of the phone's Server settings): MusicBrainz and slskd by their pings,
/// Navidrome by its status, each "Connected" or what is wrong in a word with the sentence under it - for whoever runs
/// deadwax alone. Asked the first time the page shows (the MusicBrainz ping is a real request to a rate-limited
/// service, never asked at start-up), and on Check again.
public enum Connections {
    /// `SERVICES`, in the web's order.
    public enum Service: String, Sendable, CaseIterable, Hashable {
        case musicbrainz, slskd, navidrome

        public var label: String {
            switch self {
            case .musicbrainz: return "MusicBrainz"
            case .slskd: return "slskd"
            case .navidrome: return "Navidrome"
            }
        }
    }

    /// A row's state (`CheckState`).
    public struct Check: Sendable, Equatable {
        public enum State: String, Sendable { case pending, ok, failed }

        public let state: State
        public let text: String
        public let detail: String?

        public init(state: State, text: String, detail: String? = nil) {
            self.state = state
            self.text = text
            self.detail = detail
        }

        /// VoiceOver's one reading of the row: "slskd, Connected", and the sentence under it.
        public func spoken(_ service: Service) -> String {
            [service.label, text, detail ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    public static let title = "Connections"
    public static let checkAgain = "Check again"
    public static let connected = "Connected"
    public static let cantReach = "Can't reach it"
    public static let notSetUp = "Not set up"

    /// `PENDING`.
    public static let pending = Check(state: .pending, text: "Checking…")

    /// `fromPing(service, answer)`: a ping's answer as its row says it.
    public static func fromPing(_ service: ErrorWords.Ping, _ answer: PingAnswer) -> Check {
        if JSText.lowercase(answer.status) == "ok" { return Check(state: .ok, text: connected) }
        let words = ErrorWords.pingWords(service, code: answer.code, error: answer.error)
        return Check(state: .failed, text: words.text, detail: words.line)
    }

    /// `fromNavidrome(status)`.
    public static func fromNavidrome(_ status: NavidromeStatus) -> Check {
        if status.ok {
            let server = status.server ?? ""
            return Check(state: .ok, text: server.isEmpty ? connected : server)
        }
        let problem = status.problem ?? ""
        return Check(state: .failed, text: status.configured ? cantReach : notSetUp,
                     detail: problem.isEmpty ? nil : problem)
    }

    /// The ask itself failing (`failed`): "Couldn't check", and what went wrong - the ask's own words in brackets.
    public static func unanswered(_ error: any Error) -> Check {
        Check(state: .failed, text: ErrorWords.pingUnanswered, detail: ErrorWords.unansweredLine(error))
    }

    /// The phone's own: a row whose only ask was called off - "Couldn't check", with no reason to give.
    public static let notChecked = Check(state: .failed, text: ErrorWords.pingUnanswered)
}

/// Connections' three rows as the app keeps them (You.tsx's `checks` and `pingRequests`): none until the first check,
/// each "Checking…" until its own answer, and only the newest check's answers landing. Checked the first time a page
/// that draws them shows for this person, on Check again, and - the phone's own - once more as such a page shows after
/// deadwax came back into reach, after the sign-in over the app went, or after a save that carried one of the
/// Connections group's settings (`want`).
public struct ConnectionChecks: Sendable, Equatable {
    public private(set) var rows: [Connections.Service: Connections.Check]?
    public private(set) var asks = 0
    /// Checked again the next time a page that draws them shows.
    public private(set) var wanted = false
    /// Each row's last answer, for an ask called off (`dropped`).
    private var last: [Connections.Service: Connections.Check] = [:]

    public init() {}

    /// A row's check: "Checking…" until it answers.
    public func check(_ service: Connections.Service) -> Connections.Check {
        rows?[service] ?? Connections.pending
    }

    /// Check again may be pressed: rows drawn (the web's `disabled={!checks}`), and - the phone's own - in reach.
    public func againOpen(online: Bool) -> Bool {
        rows != nil && online
    }

    /// Whether to check now: a page drawing them shows, whoever runs deadwax, in reach - never checked yet, or wanted.
    public func checksNow(shown: Bool, allowed: Bool, online: Bool) -> Bool {
        shown && allowed && online && (rows == nil || wanted)
    }

    /// A check begun: every row "Checking…", its number.
    public mutating func began() -> Int {
        asks += 1
        wanted = false
        rows = Dictionary(uniqueKeysWithValues: Connections.Service.allCases.map { ($0, Connections.pending) })
        return asks
    }

    /// One row's answer, for check `ticket` - dropped unless it is the newest.
    public mutating func settled(_ ticket: Int, _ service: Connections.Service, _ check: Connections.Check) {
        guard ticket == asks else { return }
        rows?[service] = check
        last[service] = check
    }

    /// The phone's own: one row's ask called off (a cancellation - neither an answer nor a failure). Never left on
    /// "Checking…": the row goes back to its last answer, or - never answered - says it couldn't check, with nothing
    /// more to say; and they are checked again the next time a page drawing them shows.
    public mutating func dropped(_ ticket: Int, _ service: Connections.Service) {
        guard ticket == asks else { return }
        rows?[service] = last[service] ?? Connections.notChecked
        wanted = true
    }

    /// Checked again the next time a page drawing them shows.
    public mutating func want() {
        wanted = true
    }
}

// MARK: the page, as one state

/// Server settings' page as the app keeps it (ServerSettings.tsx's `kept`, which outlives the page): the settings as
/// last answered, the drafts made against them, a save on its way and how the last ended - and every decision about
/// reading and saving, the App only carrying them out. Only the newest read lands, and a save calls any read out off.
/// The phone's own: a read to trust is one begun since deadwax was last out of reach - Save waits for one - and a save
/// that never answered (or answered a 5xx) may have landed: said, the settings read again, and only the drafts that still
/// differ from them kept (`ServerSettings.stillDiffering`).
public struct SettingsFlow: Sendable, Equatable {
    public private(set) var answer: ServerSettingsAnswer?
    public private(set) var drafts = ServerSettings.Drafts()
    public private(set) var saving = false
    public private(set) var saveError: String?
    public private(set) var justSaved = false
    /// The last read failed: its words (nil once one lands, or a save answers).
    public private(set) var readError: String?
    /// A save that never answered: what it sent, until the settings have been read again.
    public private(set) var checking: ServerSettings.Drafts?
    /// What the save out carries.
    public private(set) var sent: ServerSettings.Drafts?
    public private(set) var reads = 0
    public private(set) var landed = 0
    public private(set) var gap = 0
    /// A read is out.
    public private(set) var reading = false

    public init() {}

    /// A read to trust: one landed (or a save answered) since deadwax was last out of reach.
    public var real: Bool { landed > gap }
    public var dirty: Int { drafts.count }

    /// Whether to read now - asked as a page shows (`again` once it has shown before), as deadwax comes back into reach,
    /// as the sign-in over the app goes, and as a read lands: the page shows, in reach, its permission, no read or save
    /// out - with nothing read yet; with a read not to trust (one begun before deadwax was last out of reach, which is
    /// how a read landing too early is caught); after a save that never answered; and shown again with no draft (the
    /// web reads each time it shows, never over a draft).
    public func readsNow(shown: Bool, online: Bool, allowed: Bool, again: Bool) -> Bool {
        guard shown, online, allowed, !reading, !saving else { return false }
        return answer == nil || !real || checking != nil || (again && drafts.isEmpty)
    }

    public mutating func readBegan() -> Int {
        reads += 1
        reading = true
        return reads
    }

    /// Read `ticket` answered - dropped unless it is the newest. After a save that never answered, the drafts that
    /// landed go, and "Saved." is said only when everything the save SENT is now what the settings hold - never from
    /// what is left: a draft discarded, or typed back to the value saved, while it was looked at is no sign the save
    /// landed. True when this read settled such a save, so the App says how it came out.
    @discardableResult
    public mutating func readLanded(_ ticket: Int, _ found: ServerSettingsAnswer) -> Bool {
        guard ticket == reads else { return false }
        reading = false
        answer = found
        readError = nil
        landed = ticket
        guard let sent = checking else { return false }
        checking = nil
        drafts = ServerSettings.stillDiffering(drafts, sent: sent, now: found)
        let landedWhole = ServerSettings.stillDiffering(sent, sent: sent, now: found).isEmpty
        justSaved = landedWhole && drafts.isEmpty
        if landedWhole { saveError = nil }
        return true
    }

    public mutating func readFailed(_ ticket: Int, _ words: String) {
        guard ticket == reads else { return }
        reading = false
        readError = words
    }

    /// A read cancelled: neither an answer nor a failure.
    public mutating func readDropped(_ ticket: Int) {
        guard ticket == reads else { return }
        reading = false
    }

    /// deadwax went out of reach: a read from before it isn't trusted, and Save waits for one after.
    public mutating func outOfReach() {
        gap = reads
    }

    /// A value typed or chosen.
    public mutating func edit(_ key: String, _ value: String) {
        justSaved = false
        drafts = ServerSettings.edited(drafts, key: key, value: value, committed: answer?.committed(key))
    }

    /// Revert to the environment.
    public mutating func revert(_ key: String) {
        justSaved = false
        drafts = ServerSettings.reverted(drafts, key: key)
    }

    /// Discard: every draft gone, and the refusal with them. While a save that never answered is being looked at, it
    /// also ends that look, with no word on how the save came out - "Saved." is never said for it - and as what is shown
    /// may be from before the save, the settings are read again (`real` is false until a read lands that is newer than
    /// the one shown: a read already out began after the save, and settles it).
    public mutating func discard() {
        guard !saving else { return }
        drafts = ServerSettings.Drafts()
        saveError = nil
        justSaved = false
        guard checking != nil else { return }
        checking = nil
        gap = max(gap, landed)
    }

    /// The look at a save that never answered is stuck: its read failed, and none is out. The bar says the read's
    /// failure and offers Try again; Discard ends the look.
    public var checkStalled: Bool { checking != nil && readError != nil && !reading }

    /// Save and Discard may be pressed: drafts, nothing saving - and Save, in reach with a read to trust.
    public func saveOpen(online: Bool, allowed: Bool) -> Bool {
        allowed && online && real && !saving && !drafts.isEmpty && checking == nil
    }

    /// Save pressed: the batch to send (every draft, in order), or nil when it may not go. Any read out is called off.
    public mutating func save(online: Bool, allowed: Bool) -> ServerSettings.Drafts? {
        guard saveOpen(online: online, allowed: allowed) else { return nil }
        saving = true
        saveError = nil
        sent = drafts
        //? a read still out would land over what the save answers
        reads += 1
        reading = false
        return drafts
    }

    /// The save answered: what is left, "Saved." when nothing is.
    public mutating func saved(_ found: ServerSettingsAnswer) {
        guard saving, let sent else { return }
        saving = false
        self.sent = nil
        answer = found
        readError = nil
        landed = reads
        drafts = ServerSettings.afterSave(drafts, sent: sent)
        justSaved = drafts.isEmpty
    }

    /// The save refused (a 4xx): none of the batch was taken - every draft stays, and the bar says why.
    public mutating func refused(_ words: String) {
        guard saving else { return }
        saving = false
        sent = nil
        saveError = words
    }

    /// The save never answered, or answered a 5xx: it may have landed - the settings read again (`readsNow`), and the
    /// bar says so meanwhile (`words`: deadwax's own, when it sent some).
    public mutating func unanswered(_ words: String?) {
        guard saving, let sent else { return }
        saving = false
        self.sent = nil
        saveError = words
        checking = sent
    }

    /// The save cancelled: nothing known came of it.
    public mutating func saveDropped() {
        guard saving else { return }
        saving = false
        sent = nil
    }

    /// The bar's words: deadwax may have finished this while it is looked at again - or, the look's read having failed,
    /// that failure (Try again beside it); else the web's.
    public var barText: String {
        if checkStalled, let readError { return readError }
        if checking != nil { return EditWords.mayHaveFinished }
        return ServerSettings.barText(saveError: saveError, justSaved: justSaved, dirty: dirty)
    }

    /// The bar is up: something to say, or to save.
    public var barShown: Bool { !barText.isEmpty || dirty > 0 }

    /// The marks, per group and per tab.
    public var groupMarks: [String: ServerSettings.Mark] { ServerSettings.groupMarks(answer, drafts) }
    public var tabMarks: [ServerSettings.Tab: ServerSettings.Mark] { ServerSettings.tabMarks(answer, drafts) }

    /// A group's page: the group as last answered.
    public func group(_ id: String) -> ServerSettingGroup? {
        answer?.groups.first { $0.id == id }
    }

    /// A setting's row.
    public func row(_ setting: ServerSetting) -> ServerSettings.Row {
        ServerSettings.row(setting, answer, drafts)
    }
}

// MARK: the routes

extension DeadwaxClient {
    /// The settings (`GET /settings`), as the asker may change them - each setting's choices in the web's order.
    public func serverSettings() async throws -> ServerSettingsAnswer {
        try readSettings(try await answer(request(Routes.serverSettings)))
    }

    /// The one save (`PUT /settings`): every draft at once, a revert sent as null - answered with the settings as they
    /// are after it, or refused whole (a 400, its words naming each setting). Waited for by how many it carries
    /// (ServerSettings.saveWait).
    public func saveServerSettings(_ drafts: ServerSettings.Drafts) async throws -> ServerSettingsAnswer {
        var built = request(Routes.saveServerSettings, json: try Self.json(drafts.updates))
        built.timeout = ServerSettings.saveWait(drafts.count)
        return try readSettings(try await answer(built))
    }

    /// MusicBrainz's saved answers (`GET /settings/musicbrainz_cache`).
    public func savedAnswers() async throws -> SavedAnswersStats {
        try await call(Routes.savedAnswers)
    }

    /// Clear them (`POST /settings/musicbrainz_cache/clear`): every one gone, on disk and in memory - the file after.
    public func clearSavedAnswers() async throws -> SavedAnswersStats {
        try await call(Routes.clearSavedAnswers)
    }

    /// Whether deadwax can reach MusicBrainz now (`GET /search_musicbrainz/ping`).
    public func pingMusicBrainz() async throws -> PingAnswer {
        try await call(Routes.pingMusicBrainz)
    }

    /// Whether deadwax can search through slskd now (`GET /monitor_slskd/ping`).
    public func pingSlskd() async throws -> PingAnswer {
        try await call(Routes.pingSlskd)
    }

    /// Navidrome's status (`GET /navidrome/status`) - Connections' third row.
    public func navidromeStatus() async throws -> NavidromeStatus {
        try await call(Routes.navidromeStatus)
    }

    /// One album's lyrics re-timed to the lead that is saved (`POST /library/lyrics/fetch` with `retime`) - waited for
    /// by its lyrics (EditWaits.retime).
    public func retime(_ album: ScanAlbum) async throws -> RetimeSummary {
        var built = request(Routes.lyricsFetch, json: try Self.json(RetimeBody(albumPath: album.path)))
        built.timeout = EditWaits.retime(album)
        return try decode(RetimeSummary.self, try await answer(built))
    }

    func readSettings(_ response: HTTPResponse) throws -> ServerSettingsAnswer {
        do {
            return try ServerSettingsAnswer.read(response.body)
        } catch {
            throw APIFailure.other("deadwax's answer couldn't be read (ServerSettingsAnswer\(Self.what(error))). Is the "
                                   + "app older or newer than the server?")
        }
    }
}
