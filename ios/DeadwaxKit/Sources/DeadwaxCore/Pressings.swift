import Foundation

// The album you don't have (Phase 5, slice 2 - notes/ios-specs/phase5-search.md 3.6): the web's ui/src/lib/
// tracklistDiff.ts (one tracklist for an album, and what each pressing changes about it) and ui/src/lib/pressings.ts (the
// pressing picker, the chosen pressing's tracklist with what differs marked, the header and the meta line), with
// whose.ts' groupPagePlace and maybeLine - ported line for line and held to the web by Fixtures/search/
// search-albums-vectors.json (ios/scripts/export-search-albums-vectors.cjs), which runs the web's own functions over the
// real MusicBrainz groups in tests/fixtures/pressings/.

// MARK: one tracklist, and what each pressing changes (tracklistDiff.ts)

/// A track as a pressing prints it (`PressedTrack`).
public struct PressedTrack: Sendable, Equatable, Hashable {
    public let title: String
    /// Seconds; nil when MusicBrainz has no length.
    public let length: Int?
    /// The pressing's own numbering: "1", "A1", "B5".
    public let number: String
    public let disc: Int

    public init(title: String, length: Int?, number: String, disc: Int) {
        self.title = title
        self.length = length
        self.number = number
        self.disc = disc
    }
}

/// The usual tracklist (`Base`): the release that stands for it, its tracks, how many releases share it, how many list
/// any tracks.
public struct TracklistBase: Sendable, Equatable {
    public let index: Int
    public let tracks: [PressedTrack]
    public let count: Int
    public let total: Int
}

/// What one pressing changes about the usual tracklist (`TracklistDiff`).
public struct TracklistDiff: Sendable, Equatable {
    public struct Added: Sendable, Equatable {
        public let position: Int
        public let title: String
        public let length: Int?
        public let after: String?
    }

    public struct Removed: Sendable, Equatable {
        public let position: Int
        public let title: String
        public let length: Int?
    }

    public struct Renamed: Sendable, Equatable {
        public let position: Int
        public let from: String
        public let to: String
    }

    public struct Timed: Sendable, Equatable {
        public let position: Int
        public let title: String
        public let from: Int
        public let to: Int
        public let delta: Int
    }

    public let added: [Added]
    public let removed: [Removed]
    public let renamed: [Renamed]
    /// Another version of the song: past `otherVersionSeconds` or `otherVersionShare`.
    public let versions: [Timed]
    /// A length change past the tolerance, short of another version.
    public let lengths: [Timed]
    public let same: Int

    /// Whether it differs from the usual tracklist - a length's few seconds aside (pressings.ts `differs`).
    public var differs: Bool { !added.isEmpty || !removed.isEmpty || !renamed.isEmpty || !versions.isEmpty }
}

public enum Tracklist {
    /// Differences in length up to this many seconds are MusicBrainz rounding, not a change.
    public static let lengthToleranceSeconds = 2
    /// Past this (or 8% of the track) a difference is another recording of the song.
    public static let otherVersionSeconds = 15
    public static let otherVersionShare = 0.08

    /// A title as it is compared (`foldTitle`): lowercased, curly and straight apostrophes one apostrophe, anything but
    /// letters, numbers and apostrophes a space, trimmed.
    public static func foldTitle(_ title: String?) -> String {
        var out = String.UnicodeScalarView()
        var gap = false
        for scalar in JSText.lowercase(title ?? "").unicodeScalars {
            let kept: Unicode.Scalar?
            switch scalar.value {
            case 0x2019, 0x2018, 0x60, 0xB4, 0x27: kept = "'"
            default: kept = Fold.isLetterOrNumber(scalar) ? scalar : nil
            }
            if let kept {
                out.append(kept)
                gap = false
            } else if !gap {
                out.append(" ")
                gap = true
            }
        }
        //? only letters, numbers, apostrophes and single spaces are left: JavaScript's trim can take only the spaces
        var text = Substring(String(out)).unicodeScalars
        while text.first == " " { text = text.dropFirst() }
        while text.last == " " { text = text.dropLast() }
        return String(String.UnicodeScalarView(text))
    }

    /// `Math.round(ms / 1000)` for a finite length, else nil.
    static func seconds(_ ms: Double?) -> Int? {
        guard let ms, ms.isFinite else { return nil }
        return Int(WebText.round(ms / 1000))
    }

    /// A release's tracks in running order, as it prints them (`releaseTracks`).
    public static func tracks(_ release: PageRelease?) -> [PressedTrack] {
        var out: [PressedTrack] = []
        for medium in release?.media ?? [] {
            for track in medium.tracks {
                let title = Credits.first(track.title, track.recording?.title)
                out.append(PressedTrack(title: title, length: seconds(track.length ?? track.recording?.length),
                                        number: track.number ?? track.position.map { String($0) } ?? "",
                                        disc: medium.position ?? 1))
            }
        }
        return out
    }

    /// What makes two tracklists the same for choosing the base: the titles, in order (`tracklistKey`).
    public static func key(_ tracks: [PressedTrack]) -> String {
        tracks.map { foldTitle($0.title) }.joined(separator: "\n")
    }

    /// The usual tracklist (`chooseBase`): the most common among releases that list any tracks, a tie to whichever
    /// appears first - nil when fewer than two releases have tracks.
    public static func chooseBase(_ releases: [PageRelease]) -> TracklistBase? {
        var order: [[UInt16]] = []
        var counts: [[UInt16]: Int] = [:]
        var first: [[UInt16]: Int] = [:]
        for (index, release) in releases.enumerated() {
            let tracks = self.tracks(release)
            if tracks.isEmpty { continue }
            let key = Array(self.key(tracks).utf16)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
            if first[key] == nil { first[key] = index }
        }
        let withTracks = counts.values.reduce(0, +)
        guard withTracks >= 2 else { return nil }
        var best: [UInt16]?
        for key in order where best == nil || counts[key]! > counts[best!]! {
            best = key
        }
        let index = first[best!]!
        return TracklistBase(index: index, tracks: tracks(releases[index]), count: counts[best!]!, total: withTracks)
    }

    /// A rank's part: a number, or a string compared by UTF-16 code unit as JavaScript's `<` compares them.
    enum RankPart: Comparable {
        case number(Int)
        case text([UInt16])

        static func < (a: RankPart, b: RankPart) -> Bool {
            switch (a, b) {
            case (.number(let x), .number(let y)): return x < y
            case (.text(let x), .text(let y)): return x.lexicographicallyPrecedes(y)
            default: return false
            }
        }
    }

    /// The one pressing that stands for the album (`representativeRelease`): the usual tracklist, then Official, then
    /// a CD or digital release, then no disambiguation, then the earliest full date, then the id.
    public static func representative(_ releases: [PageRelease]) -> PageRelease? {
        let withTracks = releases.filter { !tracks($0).isEmpty }
        guard !withTracks.isEmpty else { return nil }
        let base = chooseBase(withTracks)
        let usual = base.map { Array(key($0.tracks).utf16) }
        let pool = usual.map { (usual: [UInt16]) -> [PageRelease] in
            withTracks.filter { Array(key(tracks($0)).utf16) == usual }
        } ?? withTracks
        func plain(_ release: PageRelease) -> Bool {
            !release.media.isEmpty && release.media.allSatisfy { $0.format == "CD" || $0.format == "Digital Media" }
        }
        func rank(_ release: PageRelease) -> [RankPart] {
            [.number(release.status == "Official" ? 0 : 1), .number(plain(release) ? 0 : 1),
             .number((release.disambiguation ?? "").isEmpty ? 0 : 1), .text(Array((release.knownDate + "~").utf16)),
             .text(Array(release.id.utf16))]
        }
        var best = pool[0]
        for release in pool.dropFirst() {
            let (a, b) = (rank(release), rank(best))
            for at in a.indices {
                if a[at] < b[at] { best = release; break }
                if b[at] < a[at] { break }
            }
        }
        return best
    }

    /// Whether a difference in length is another version of the song rather than rounding (`isOtherVersion`).
    public static func isOtherVersion(_ delta: Int, base: Int?) -> Bool {
        Double(abs(delta)) >= max(Double(otherVersionSeconds), Double(base ?? 0) * otherVersionShare)
    }

    /// What `tracks` changes about `base` (`diffTracklists`): paired by title along the longest common run; of what is
    /// left, an added and a removed track of about the same length are one renamed track.
    public static func diff(_ base: [PressedTrack], _ tracks: [PressedTrack],
                            tolerance: Int = lengthToleranceSeconds) -> TracklistDiff {
        let a = base.map { Array(foldTitle($0.title).utf16) }
        let b = tracks.map { Array(foldTitle($0.title).utf16) }
        let n = a.count
        let m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var added: [TracklistDiff.Added] = []
        var removed: [TracklistDiff.Removed] = []
        var versions: [TracklistDiff.Timed] = []
        var lengths: [TracklistDiff.Timed] = []
        var same = 0
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n && j < m && a[i] == b[j] {
                if let from = base[i].length, let to = tracks[j].length, abs(to - from) > tolerance {
                    let change = TracklistDiff.Timed(position: j + 1, title: tracks[j].title, from: from, to: to,
                                                     delta: to - from)
                    if isOtherVersion(to - from, base: from) { versions.append(change) } else { lengths.append(change) }
                } else {
                    same += 1
                }
                i += 1
                j += 1
            } else if j < m && (i >= n || lcs[i][j + 1] >= lcs[i + 1][j]) {
                added.append(TracklistDiff.Added(position: j + 1, title: tracks[j].title, length: tracks[j].length,
                                                 after: j > 0 ? tracks[j - 1].title : nil))
                j += 1
            } else {
                removed.append(TracklistDiff.Removed(position: i + 1, title: base[i].title, length: base[i].length))
                i += 1
            }
        }
        var renamed: [TracklistDiff.Renamed] = []
        var pairedAdds = Set<Int>()
        var pairedRemoves = Set<Int>()
        for (at, add) in added.enumerated() {
            let match = removed.indices.first { (index: Int) -> Bool in
                guard !pairedRemoves.contains(index) else { return false }
                guard let one = add.length, let other = removed[index].length else { return true }
                return abs(one - other) <= max(tolerance, 5)
            }
            if let match {
                pairedRemoves.insert(match)
                pairedAdds.insert(at)
                renamed.append(TracklistDiff.Renamed(position: add.position, from: removed[match].title, to: add.title))
            }
        }
        return TracklistDiff(added: added.enumerated().filter { !pairedAdds.contains($0.offset) }.map(\.element),
                             removed: removed.enumerated().filter { !pairedRemoves.contains($0.offset) }.map(\.element),
                             renamed: renamed, versions: versions, lengths: lengths, same: same)
    }

    /// `257` -> "4:17"; nil stays blank (`formatSeconds`).
    public static func clock(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let rest = String(seconds % 60)
        return "\(seconds / 60):\(rest.count < 2 ? "0" + rest : rest)"
    }
}

// MARK: the pressing picker (pressings.ts)

/// One pressing as the picker lists it (`PressingChoice`).
public struct PressingChoice: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case usual, differs, none
    }

    public let id: String
    /// "CD · 2008 · GB · Island"
    public let label: String
    /// "Official · 2008-04-28 · Cat. no. 1764013 · Barcode 602517640132"
    public let facts: String
    /// How it compares with the usual tracklist, in a few words.
    public let note: String
    public let kind: Kind
    /// The one the page opens on.
    public let isDefault: Bool
    /// A pressing your library holds: marked, never folded away.
    public let held: Bool
    /// Held by the collection but not yours (a library of your own): marked "In the collection".
    public let inStore: Bool

    /// What it says it holds: "In your library", "In the collection" - nothing when it holds none.
    public var heldLabel: String {
        held ? (inStore ? "In the collection" : "In your library") : ""
    }
}

/// Every pressing of an album as the picker lists them, and which is shown (`PressingsView`).
public struct PressingsView: Sendable, Equatable {
    public let base: TracklistBase?
    public let defaultId: String?
    /// The pressing shown: the one asked for when the album has it, else the default.
    public let chosenId: String?
    /// The picker's list, before "N more".
    public let shown: [PressingChoice]
    /// The pressings with the usual tracklist folded under "N more".
    public let more: [PressingChoice]
    /// Each pressing's differences from the usual tracklist (nil without a base, or tracks).
    public let diffs: [String: TracklistDiff?]

    /// The chosen pressing's row.
    public var chosen: PressingChoice? { (shown + more).first { $0.id == chosenId } }
}

/// A row of the chosen pressing's tracklist (`TrackRow`).
public struct PressingTrack: Sendable, Equatable, Identifiable {
    public struct Mark: Sendable, Equatable {
        public enum Kind: String, Sendable, Equatable {
            case bonus, version, renamed
        }

        public let kind: Kind
        public let chip: String
        /// The phone's line under the title: "Only on this pressing", "The usual version is 3:58".
        public let note: String
    }

    public let key: String
    /// The disc heading drawn above this track, or nil.
    public let heading: String?
    /// Its number on its own disc.
    public let number: String
    public let title: String
    /// m:ss, or "" when MusicBrainz has no length.
    public let length: String
    public let mark: Mark?

    public var id: String { key }
}

public enum Pressings {
    public static let filterMin = 30
    public static let trouble = "This album's details can't be loaded right now - try again in a few minutes."
    public static let none = "There are no pressings of this album to get."
    public static let notOnThisPressing = "Not on this pressing"
    public static let notAnAlbum = "That link isn't an album."
    public static let gone = "This album can't be found."
    public static let picker = "Pressing"
    public static let filterPrompt = "JP, CD, a label or catalogue no."
    public static let filterLabel = "Filter the pressings"
    public static let tracklist = "Tracklist"
    /// The picker's list, as VoiceOver names it (PressingPicker.tsx's listbox).
    public static let pressingsLabel = "Pressings"
    public static let loading = "Loading…"
    public static let tryAgain = "Try again"
    /// The picker's sheet closed (the phone's own: the web's is a popover).
    public static let done = "Done"
    /// Opened with nothing in hand while deadwax can't be reached (the phone's own, question 5's rule: nothing of these
    /// is drawn that wasn't answered).
    public static let offline = "This album's pressings load once deadwax is back."
    /// How many albums' pressing lists the session keeps (pressingLists.ts `PRESSINGS_KEPT`).
    public static let kept = 20

    static let formatWords = ["Digital Media": "Digital"]
    static let countryWords = ["XW": "", "XE": "Europe"]
    static let noCatalogue = "[none]"

    static func plural(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }

    /// Up to two names, then how many more: "Patience", "A and B", "A, B and 2 more".
    static func names(_ titles: [String]) -> String {
        if titles.count <= 2 { return titles.joined(separator: " and ") }
        return "\(titles.prefix(2).joined(separator: ", ")) and \(titles.count - 2) more"
    }

    /// A pressing's formats: "CD", "2×12\" Vinyl", "USB Flash Drive + 3×12\" Vinyl" (`pressingFormat`).
    public static func format(_ release: PageRelease) -> String {
        var runs: [(String, Int)] = []
        for medium in release.media {
            let format = formatWords[medium.format ?? ""] ?? medium.format ?? ""
            if format.isEmpty { continue }
            if let last = runs.last, WebText.same(last.0, format) {
                runs[runs.count - 1].1 += 1
            } else {
                runs.append((format, 1))
            }
        }
        return runs.map { $0.1 > 1 ? "\($0.1)\u{00D7}\($0.0)" : $0.0 }.joined(separator: " + ")
    }

    /// The year a pressing came out, or "" (`pressingYear`).
    public static func year(_ release: PageRelease) -> String {
        let year = WebText.prefix(release.knownDate, 4)
        return WebText.fourDigits(year) ? year : ""
    }

    /// "CD · 2008 · GB · Island": formats, year, country, then its disambiguation, else its first label
    /// (`pressingLabel`).
    public static func label(_ release: PageRelease) -> String {
        let country = (release.country ?? "").isEmpty ? "" : countryWords[release.country!] ?? release.country!
        let named = JSText.trim(release.disambiguation ?? "")
        let label = !named.isEmpty ? named : release.labelInfo.first(where: { !($0.label ?? "").isEmpty })?.label ?? ""
        let parts = [format(release), year(release), country, label].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " \u{00B7} ") }
        return Credits.first(release.title, "A pressing")
    }

    /// What else tells a pressing apart (`pressingFacts`): its status, full date, labels the label line doesn't show,
    /// catalogue numbers, barcode, and "Worldwide" - each once, nothing the label line says.
    public static func facts(_ release: PageRelease) -> String {
        var parts: [String] = []
        let status = JSText.trim(release.status ?? "")
        if !status.isEmpty { parts.append(status) }
        let date = JSText.trim(release.knownDate)
        if date.utf16.count > 4 { parts.append(date) }
        let named = JSText.trim(release.disambiguation ?? "").isEmpty
        let shown: String? = named
            ? release.labelInfo.first(where: { !($0.label ?? "").isEmpty }).map { JSText.trim($0.label ?? "") } : nil
        let labels = WebText.unique(release.labelInfo.map { JSText.trim($0.label ?? "") }.filter { !$0.isEmpty })
            .filter { (name: String) -> Bool in shown.map { !WebText.same(name, $0) } ?? true }
        if !labels.isEmpty { parts.append(labels.joined(separator: " / ")) }
        let numbers = WebText.unique(release.labelInfo.map { JSText.trim($0.catalogNumber ?? "") })
            .filter { !$0.isEmpty && !WebText.same($0, noCatalogue) }
        if !numbers.isEmpty { parts.append("Cat. no. \(numbers.joined(separator: " / "))") }
        let barcode = JSText.trim(release.barcode ?? "")
        if !barcode.isEmpty { parts.append("Barcode \(barcode)") }
        if release.country == "XW" { parts.append("Worldwide") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Text as the filter compares it: accents and case folded, anything but letters and digits a space.
    static func foldText(_ text: String) -> String {
        let scalars = text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !Fold.isMark($0) }
        var out = String.UnicodeScalarView()
        var gap = false
        for scalar in JSText.lowercase(String(String.UnicodeScalarView(scalars))).unicodeScalars {
            if Fold.isLetterOrNumber(scalar) {
                out.append(scalar)
                gap = false
            } else if !gap {
                out.append(" ")
                gap = true
            }
        }
        var trimmed = Substring(String(out)).unicodeScalars
        while trimmed.first == " " { trimmed = trimmed.dropFirst() }
        while trimmed.last == " " { trimmed = trimmed.dropLast() }
        return String(String.UnicodeScalarView(trimmed))
    }

    /// Whether `text` holds `part`, by UTF-16 code unit (`includes`).
    static func includes(_ text: String, _ part: String) -> Bool {
        let whole = Array(text.utf16)
        let piece = Array(part.utf16)
        if piece.isEmpty { return true }
        guard piece.count <= whole.count else { return false }
        for start in 0...(whole.count - piece.count) where whole[start] == piece[0] {
            if Array(whole[start..<(start + piece.count)]) == piece { return true }
        }
        return false
    }

    /// The picker's filter (`filterPressings`): the pressings whose label, facts or note hold every word typed - a word
    /// found as folded, or with the text's gaps closed up (a catalogue number typed without its dash) - in the list's
    /// own order; every pressing for nothing typed.
    public static func filter(_ rows: [PressingChoice], _ typed: String) -> [PressingChoice] {
        let words = foldText(typed).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if words.isEmpty { return rows }
        return rows.filter { (row: PressingChoice) -> Bool in
            let held = row.held ? (row.inStore ? "in the collection" : "in your library") : ""
            let text = foldText([row.label, row.facts, row.note, held].joined(separator: " "))
            let closed = String(text.unicodeScalars.filter { $0 != " " })
            return words.allSatisfy { includes(text, $0) || includes(closed, $0) }
        }
    }

    /// What the filter says as it narrows the list (`pressingFilterWords`).
    public static func filterWords(_ matching: Int, _ typed: String) -> String {
        let words = JSText.trim(typed)
        if words.isEmpty { return "" }
        if matching == 0 { return "No pressing matches \u{201C}\(words)\u{201D}." }
        return "\(matching) \(matching == 1 ? "pressing matches" : "pressings match")."
    }

    /// "N more pressing(s) with the usual tracklist" - the fold's button (PressingPicker.tsx).
    public static func moreWords(_ count: Int) -> String {
        "\(count) more \(count == 1 ? "pressing" : "pressings") with the usual tracklist"
    }

    /// "shared by 9 of 10 pressings", "shared by all 4 pressings" (`sharedBy`).
    public static func sharedBy(_ base: TracklistBase) -> String {
        base.count == base.total ? "shared by all \(base.total) pressings" : "shared by \(base.count) of \(base.total) pressings"
    }

    static func note(_ kind: PressingChoice.Kind, _ diff: TracklistDiff?, isDefault: Bool, base: TracklistBase?) -> String {
        if kind == .none { return "No tracklist listed" }
        guard let base, let diff else { return "The only tracklist listed" }
        if kind == .usual { return isDefault ? "The usual tracklist \u{00B7} \(sharedBy(base))" : "Same tracklist as the usual one" }
        var parts: [String] = []
        if !diff.added.isEmpty {
            parts.append("+\(plural(diff.added.count, "bonus track")): \(names(diff.added.map(\.title)))")
        }
        if !diff.removed.isEmpty {
            parts.append("Without \(diff.removed.count > 2 ? plural(diff.removed.count, "track") : names(diff.removed.map(\.title)))")
        }
        if !diff.renamed.isEmpty { parts.append("\(plural(diff.renamed.count, "track")) renamed") }
        if !diff.versions.isEmpty {
            if diff.versions.count == 1, let only = diff.versions.first {
                parts.append("1 other version: \(only.title), \(Tracklist.clock(only.to))")
            } else {
                parts.append("\(plural(diff.versions.count, "other version")): \(names(diff.versions.map(\.title)))")
            }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Which pressing is shown (`chosenPressingId`): the one asked for when the album has it, else the default.
    public static func chosenId(_ releases: [PageRelease], asked: String?, defaultId: String?) -> String? {
        if let asked, releases.contains(where: { WebText.same($0.id, asked) }) { return asked }
        return defaultId
    }

    /// The default: the representative pressing, else the first (`chosenPressingId`'s default).
    public static func defaultId(_ releases: [PageRelease]) -> String? {
        Tracklist.representative(releases)?.id ?? releases.first?.id
    }

    /// Every pressing as the picker lists them, and which is shown (`pressingsView`): `held` the release ids your
    /// library holds (lowercase), each marked and kept out of the fold; `yours` with a library of your own the ids of
    /// those that are yours (nil with logins off).
    public static func view(_ releases: [PageRelease], asked: String? = nil, held: Set<String> = [],
                            yours: Set<String>? = nil) -> PressingsView {
        let base = Tracklist.chooseBase(releases)
        let usualKey = base.map { Array(Tracklist.key($0.tracks).utf16) }
        let fallback = Tracklist.representative(releases)
        let defaultId = fallback?.id ?? releases.first?.id
        let chosenId = Pressings.chosenId(releases, asked: asked, defaultId: defaultId)
        //? every pressing compared with the usual titles at the DEFAULT pressing's lengths
        let fallbackTracks = fallback.map { Tracklist.tracks($0) } ?? []
        let reference: [PressedTrack]? = base.map { (base: TracklistBase) -> [PressedTrack] in
            !fallbackTracks.isEmpty && Array(Tracklist.key(fallbackTracks).utf16) == usualKey ? fallbackTracks : base.tracks
        }

        struct Made {
            let row: PressingChoice
            let format: [UInt16]
            let date: [UInt16]
            let label: [UInt16]
        }
        var diffs: [String: TracklistDiff?] = [:]
        let rows = releases.map { (release: PageRelease) -> Made in
            let tracks = Tracklist.tracks(release)
            let diff = reference.flatMap { (reference: [PressedTrack]) -> TracklistDiff? in
                tracks.isEmpty ? nil : Tracklist.diff(reference, tracks)
            }
            diffs[release.id] = .some(diff)
            let kind: PressingChoice.Kind
            if tracks.isEmpty {
                kind = .none
            } else if base == nil {
                kind = .usual
            } else if let diff, !diff.differs, Array(Tracklist.key(tracks).utf16) == usualKey {
                kind = .usual
            } else {
                kind = .differs
            }
            let isDefault = defaultId.map { WebText.same(release.id, $0) } ?? false
            let id = JSText.lowercase(release.id)
            let holds = held.contains(id)
            let row = PressingChoice(id: release.id, label: Pressings.label(release), facts: Pressings.facts(release),
                                  note: note(kind, diff, isDefault: isDefault, base: base), kind: kind,
                                  isDefault: isDefault, held: holds,
                                  inStore: holds && yours.map { !$0.contains(id) } == true)
            return Made(row: row, format: Array(Pressings.format(release).utf16), date: Array((release.knownDate + "~").utf16),
                        label: Array(row.label.utf16))
        }

        func byDate(_ list: [Made]) -> [Made] {
            list.enumerated().sorted { (a: (offset: Int, element: Made), b: (offset: Int, element: Made)) -> Bool in
                if a.element.date != b.element.date { return a.element.date.lexicographicallyPrecedes(b.element.date) }
                if a.element.label != b.element.label { return a.element.label.lexicographicallyPrecedes(b.element.label) }
                return a.offset < b.offset
            }.map(\.element)
        }
        let first = rows.first { $0.row.isDefault }
        let usual = byDate(rows.filter { !$0.row.isDefault && $0.row.kind == .usual })
        let differing = byDate(rows.filter { !$0.row.isDefault && $0.row.kind == .differs })
        let none = byDate(rows.filter { !$0.row.isDefault && $0.row.kind == .none })

        //? one pressing of each other format with the usual tracklist stays in view: a vinyl is one tap away
        var formats: Set<[UInt16]> = [first?.format ?? []]
        var formatShown: [Made] = []
        var shownIds = Set<String>()
        for row in usual where formats.insert(row.format).inserted {
            formatShown.append(row)
            shownIds.insert(row.row.id)
        }
        func keptOut(_ row: PressingChoice) -> Bool { chosenId.map { WebText.same(row.id, $0) } == true || row.held }
        let folded = usual.filter { !shownIds.contains($0.row.id) && !keptOut($0.row) }
        let chosenFolded = usual.filter { !shownIds.contains($0.row.id) && keptOut($0.row) }
        let shown = (first.map { [$0] } ?? []) + formatShown + chosenFolded + differing + none
        return PressingsView(base: base, defaultId: defaultId, chosenId: chosenId, shown: shown.map(\.row),
                             more: folded.map(\.row), diffs: diffs)
    }

    /// The line above the tracklist (`summaryLine`): what this pressing is against the usual one - `differs` drawn as a
    /// warning.
    public static func summary(_ view: PressingsView, releaseCount: Int) -> (text: String, differs: Bool) {
        guard let row = view.chosen else { return ("", false) }
        if row.kind == .none { return ("No tracks are listed for this pressing", false) }
        guard let base = view.base else {
            return (releaseCount == 1 ? "The only pressing" : "The only pressing with a tracklist", false)
        }
        if row.kind == .usual {
            return (row.isDefault ? "The usual tracklist, \(sharedBy(base))" : "Same tracklist as the usual one", false)
        }
        guard let found = view.diffs[row.id], let diff = found else { return ("", false) }
        var clauses: [String] = []
        if !diff.added.isEmpty { clauses.append("adds \(plural(diff.added.count, "track"))") }
        if !diff.removed.isEmpty { clauses.append("leaves out \(plural(diff.removed.count, "track"))") }
        if !diff.renamed.isEmpty { clauses.append("renames \(plural(diff.renamed.count, "track"))") }
        if !diff.versions.isEmpty { clauses.append("has another version of \(plural(diff.versions.count, "track"))") }
        let said = clauses.count > 1
            ? "\(clauses.dropLast().joined(separator: ", ")) and \(clauses[clauses.count - 1])" : clauses.first ?? ""
        return ("This pressing \(said)", true)
    }

    /// "Disc 2 · Unreleased Tracks", or "Disc 2" (`discHeading`).
    public static func discHeading(_ position: Int, _ title: String?) -> String {
        let named = JSText.trim(title ?? "")
        return named.isEmpty ? "Disc \(position)" : "Disc \(position) \u{00B7} \(named)"
    }

    /// The chosen pressing's tracklist, row by row, with its differences from the usual one marked (`trackRows`).
    public static func trackRows(_ release: PageRelease?, _ diff: TracklistDiff?) -> [PressingTrack] {
        guard let release else { return [] }
        let media = release.media.filter { !$0.tracks.isEmpty }
        let headings = media.count > 1 || media.contains { !JSText.trim($0.title ?? "").isEmpty }
        let bonus = Set(diff?.added.map(\.position) ?? [])
        var versions: [Int: TracklistDiff.Timed] = [:]
        for change in diff?.versions ?? [] { versions[change.position] = change }
        var renamed: [Int: TracklistDiff.Renamed] = [:]
        for change in diff?.renamed ?? [] { renamed[change.position] = change }
        var rows: [PressingTrack] = []
        var position = 0
        for (index, medium) in media.enumerated() {
            let disc = medium.position ?? index + 1
            for (onDisc, track) in medium.tracks.enumerated() {
                position += 1
                let mark: PressingTrack.Mark?
                if bonus.contains(position) {
                    mark = PressingTrack.Mark(kind: .bonus, chip: "Bonus", note: "Only on this pressing")
                } else if let version = versions[position] {
                    mark = PressingTrack.Mark(kind: .version, chip: "Other version",
                                              note: "The usual version is \(Tracklist.clock(version.from))")
                } else if let rename = renamed[position] {
                    mark = PressingTrack.Mark(kind: .renamed, chip: "Renamed", note: "Usually \u{201C}\(rename.from)\u{201D}")
                } else {
                    mark = nil
                }
                rows.append(PressingTrack(key: "\(disc):\(onDisc)",
                                          heading: headings && onDisc == 0 ? discHeading(disc, medium.title) : nil,
                                          number: String(onDisc + 1),
                                          title: Credits.first(track.title, track.recording?.title),
                                          length: Tracklist.clock(Tracklist.seconds(track.length ?? track.recording?.length)),
                                          mark: mark))
            }
        }
        return rows
    }

    /// What the chosen pressing leaves out of the usual tracklist, with the usual lengths (`leftOut`).
    public static func leftOut(_ diff: TracklistDiff?) -> [(title: String, length: String)] {
        (diff?.removed ?? []).map { ($0.title, Tracklist.clock($0.length)) }
    }

    /// The header (`pageHeader`): from the album Search handed over, else the one the pressings carry, else the
    /// pressings themselves.
    public static func header(_ releases: [PageRelease], chosen: PageRelease?, preview: ReleaseGroup?)
        -> (title: String, artist: String, year: String, kind: String) {
        let years = releases.map { Pressings.year($0) }.filter { !$0.isEmpty }.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
        let group = preview ?? releases.first(where: { $0.releaseGroup != nil })?.releaseGroup
        let title = Credits.first(group?.title, Credits.first(chosen?.title, releases.first?.title))
        let artist = Credits.first(Credits.name(group?.artistCredit), Credits.name(chosen?.artistCredit))
        let known = Credits.first(group.flatMap { SearchAlbums.year($0) }, years.first)
        return (title, artist, known, group.map { SearchAlbums.kind($0) } ?? "")
    }

    /// The meta line (`metaLine`): "2008 · Album · not in your library" - `held` nil until the library has said, and
    /// then neither.
    public static func metaLine(year: String, kind: String, held: Bool?, place: String = Whose.inYourLibrary) -> String {
        let holding = held.map { $0 ? place : "not in your library" } ?? ""
        return [year, kind, holding].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// What the meta line says of the library (`holdingOf`).
    public enum Holding: String, Sendable, Equatable {
        case held, maybe, not
    }

    public static func holding(_ found: (held: [OwnedAlbum], guessed: [OwnedAlbum])?) -> Holding? {
        guard let found else { return nil }
        return !found.held.isEmpty ? .held : !found.guessed.isEmpty ? .maybe : .not
    }

    /// Where the album is, for its meta line (whose.ts `groupPagePlace`): "in your library"; with a library of your own
    /// "in the collection" when none of it is yours, and "another pressing in your library" when the pressing on screen
    /// is the collection's and another is yours.
    public static func place(personal: Bool, holding: [OwnedAlbum], chosenId: String?) -> String {
        let any = holding.contains { $0.yours != false }
        if !personal || !any { return Whose.heldPhrase(personal: personal, yours: any) }
        let id = JSText.lowercase(JSText.trim(chosenId ?? ""))
        let chosen = id.isEmpty ? [] : holding.filter { WebText.same(JSText.lowercase(JSText.trim($0.releaseMbid ?? "")), id) }
        return !chosen.isEmpty && !chosen.contains { $0.yours != false } ? "another pressing in your library" : Whose.inYourLibrary
    }

    /// The maybe said in words, under Get's place (whose.ts `maybeLine`).
    public static func maybeLine(inCollection: Bool, editors: Bool) -> String {
        let lead = inCollection
            ? "It may already be here - an album with this name is in the collection, but it isn't matched to a pressing."
            : "You may already have this - an album with this name is in your library, but it isn't matched to a pressing."
        return editors ? "\(lead) Match it to a pressing in Edit album." : lead
    }
}

// MARK: the page as drawn

/// The album you don't have, as drawn from what is in hand (ReleaseGroupPage.tsx's render, slice 2's parts): the
/// header, the meta line, the pressing picker's view, the chosen pressing's facts, the summary, the tracklist and what
/// it leaves out. Pure: the page's model hands it the album's answer, the album Search handed over and the library's
/// folders.
public struct GroupPage: Sendable, Equatable {
    public let title: String
    public let artist: String
    /// "1994 · Album · not in your library" - "" until something is known.
    public let meta: String
    /// "maybe in your library" - drawn dashed after the meta line; "" when it isn't a maybe.
    public let maybe: String
    /// The maybe in words, under Get's place.
    public let maybeNote: String
    public let view: PressingsView?
    /// The chosen pressing's facts.
    public let facts: String
    public let summary: (text: String, differs: Bool)?
    public let tracks: [PressingTrack]
    public let missing: [(title: String, length: String)]
    /// The chosen pressing's id - the cover tried first.
    public let chosenId: String?

    public static func == (a: GroupPage, b: GroupPage) -> Bool {
        a.title == b.title && a.artist == b.artist && a.meta == b.meta && a.maybe == b.maybe
            && a.maybeNote == b.maybeNote && a.view == b.view && a.facts == b.facts
            && a.summary?.text == b.summary?.text && a.summary?.differs == b.summary?.differs && a.tracks == b.tracks
            && a.missing.map(\.title) == b.missing.map(\.title) && a.missing.map(\.length) == b.missing.map(\.length)
            && a.chosenId == b.chosenId
    }

    /// The page for album `id` (lowercase), from `answer` (nil while it loads), `preview` (the album Search showed),
    /// `index` (nil until `/library/owned` answers), the pressing picked (nil: the default).
    public init(id: String, answer: ReleaseGroupAnswer?, preview: ReleaseGroup?, index: OwnedIndex?, picked: String?,
                personal: Bool, editors: Bool, fallbackTitle: String = "") {
        let releases = answer?.releases ?? []
        let credited = preview ?? releases.first(where: { $0.releaseGroup != nil })?.releaseGroup
        let ownership = index.map { (index: OwnedIndex) -> (held: [OwnedAlbum], guessed: [OwnedAlbum]) in
            OwnedIndex.forGroup(index, groupId: id, releaseIds: releases.map(\.id),
                                title: Credits.first(credited?.title, Credits.first(releases.first?.title, fallbackTitle)),
                                artists: [Credits.name(credited?.artistCredit), Credits.current(credited?.artistCredit)])
        }
        let holding = ownership?.held
        let held: Bool? = holding.map { !$0.isEmpty }
        let isMaybe = Pressings.holding(ownership) == .maybe
        func releaseIds(_ albums: [OwnedAlbum]) -> Set<String> {
            Set(albums.map { JSText.lowercase(JSText.trim($0.releaseMbid ?? "")) }.filter { !$0.isEmpty })
        }
        let heldIds = releaseIds(holding ?? [])
        let yoursIds: Set<String>? = personal ? releaseIds((holding ?? []).filter { $0.yours != false }) : nil
        let view = releases.isEmpty ? nil : Pressings.view(releases, asked: picked, held: heldIds, yours: yoursIds)
        let chosen = releases.first { (release: PageRelease) -> Bool in view?.chosenId.map { WebText.same(release.id, $0) } == true }
        let place = Pressings.place(personal: personal, holding: holding ?? [], chosenId: view?.chosenId)
        let header = Pressings.header(releases, chosen: chosen, preview: preview)
        let diff: TracklistDiff? = chosen.flatMap { (chosen: PageRelease) -> TracklistDiff? in
            guard let found = view?.diffs[chosen.id] else { return nil }
            return found
        }
        title = Credits.first(header.title, fallbackTitle)
        artist = header.artist
        let known = preview != nil || answer != nil
        if !known {
            meta = ""
            maybe = ""
            maybeNote = ""
        } else if isMaybe {
            meta = Pressings.metaLine(year: header.year, kind: header.kind, held: nil)
            let guessed = ownership?.guessed ?? []
            let anyYours = guessed.contains { $0.yours != false }
            maybe = "maybe \(Whose.heldPhrase(personal: personal, yours: anyYours))"
            maybeNote = Pressings.maybeLine(inCollection: personal && !anyYours, editors: editors)
        } else {
            meta = Pressings.metaLine(year: header.year, kind: header.kind, held: held, place: place)
            maybe = ""
            maybeNote = ""
        }
        self.view = view
        facts = view?.chosen?.facts ?? ""
        summary = view.map { Pressings.summary($0, releaseCount: releases.count) }
        tracks = Pressings.trackRows(chosen, diff)
        missing = Pressings.leftOut(diff)
        chosenId = chosen?.id
    }
}

/// The session's pressing lists, by album (pressingLists.ts `kept`, `keep`): every pressing of an album with its
/// tracklist as `release_group` answered, so Back and an album opened again ask nothing. Only a complete answer is kept
/// (one MusicBrainz broke off part way - `problem` - would pass for the album's pressings), the newest last, the oldest
/// let go past `Pressings.kept`: a big album's tracklists are a large payload.
public struct KeptPressings: Sendable {
    private var order: [String] = []
    private var answers: [String: ReleaseGroupAnswer] = [:]

    public init() {}

    /// An album's pressings, if this session has them complete.
    public func kept(_ id: String) -> ReleaseGroupAnswer? { answers[id] }

    /// Kept as the newest - unless MusicBrainz broke the list off.
    public mutating func keep(_ id: String, _ answer: ReleaseGroupAnswer) {
        guard (answer.problem ?? "").isEmpty else { return }
        order.removeAll { $0 == id }
        order.append(id)
        answers[id] = answer
        while order.count > Pressings.kept {
            answers[order.removeFirst()] = nil
        }
    }

    public var count: Int { order.count }
}
