import Foundation

/// The index down the Albums screen's edge (ui/src/lib/shelves.ts; app/ShelfIndex.tsx draws it): the letters for
/// Artist and Title, the decades for the year sorts, none for Recently added - drawn only with `minimum` albums or
/// more and nothing typed into Find; thinned to the slots there is room for, a dot standing for those left out;
/// and the entry under a finger.
public enum ShelfIndex {
    /// INDEX_MIN: an index needs a list this long, at least; a shorter one is a scroll away.
    public static let minimum = 50
    /// One entry's height, in points (`--app-index-entry: 15px`).
    public static let entryHeight: Double = 15

    public enum Kind: Sendable, Equatable {
        case letters
        case decades
    }

    /// One entry: its words, what VoiceOver says, and the group it jumps to (its place in the groups).
    public struct Entry: Sendable, Equatable {
        public let label: String
        public let accessibility: String
        public let group: Int

        public init(label: String, accessibility: String, group: Int) {
            self.label = label
            self.accessibility = accessibility
            self.group = group
        }
    }

    /// One place on the drawn strip: an entry (and its place among all the entries), or a dot standing for those
    /// left out between two.
    public enum Slot: Sendable, Equatable {
        case entry(Entry, at: Int)
        case dot
    }

    static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    /// `indexKind`.
    public static func kind(_ sort: AlbumSort) -> Kind? {
        switch sort {
        case .alphabeticalByArtist, .alphabeticalByName: return .letters
        case .byYearDesc, .byYearAsc: return .decades
        case .newest: return nil
        }
    }

    /// `showsIndex`: a sort that has one, nothing typed into Find, and at least `minimum` albums in the SORTED list.
    public static func shows(_ sort: AlbumSort, count: Int, typed: String) -> Bool {
        kind(sort) != nil && !Find.finding(typed) && count >= minimum
    }

    /// How many entries a strip `height` points tall has room for.
    public static func slots(height: Double) -> Int {
        guard height.isFinite, height > 0 else { return 1 }
        return max(1, Int((height / entryHeight).rounded(.down)))
    }

    /// `indexEntries`. Letters: all 27, A-Z then #, each jumping to its own group - or, with none, the next group
    /// after it, or the last group when there is none after. Decades: one per decade present, in the sort's
    /// direction, labelled with its first year, jumping to its first group; "No year" gets none. No groups, none.
    public static func entries(_ groups: [ShelfGroup], _ sort: AlbumSort) -> [Entry] {
        guard let kind = kind(sort), !groups.isEmpty else { return [] }
        switch kind {
        case .letters:
            func rank(_ label: String?) -> Int {
                label == Fold.otherInitial ? letters.count : (letters.firstIndex(of: label ?? "") ?? -1)
            }
            let ranks = groups.map { rank($0.label) }
            return (letters + [Fold.otherInitial]).enumerated().map { at, label in
                Entry(label: label,
                      accessibility: label == Fold.otherInitial ? "Jump to numbers and symbols" : "Jump to \(label)",
                      group: ranks.firstIndex { $0 >= at } ?? groups.count - 1)
            }
        case .decades:
            var entries: [Entry] = []
            for (at, group) in groups.enumerated() {
                guard let label = group.label, label != Shelf.noYear, let year = Int(label) else { continue }
                let decade = String(Int((Double(year) / 10).rounded(.down)) * 10)
                if entries.last?.label == decade { continue }
                entries.append(Entry(label: decade, accessibility: "Jump to the \(decade)s", group: at))
            }
            return entries
        }
    }

    /// `fitIndex`: the entries as `slots` places can draw them - all, when they fit; else as many as fit with a
    /// dot between each two, the first and last always kept, the rest spread evenly.
    public static func fit(_ entries: [Entry], slots: Int) -> [Slot] {
        let all = entries.enumerated().map { Slot.entry($1, at: $0) }
        if entries.count <= max(1, slots) { return all }
        let kept = max(2, (slots + 1) / 2)
        var drawn: [Slot] = []
        var before = -1
        for n in 0..<kept {
            //? Math.round on a value that is never negative: halves up
            let at = Int((Double(n * (entries.count - 1)) / Double(kept - 1)).rounded(.toNearestOrAwayFromZero))
            if at == before { continue }
            if before != -1 && at - before > 1 { drawn.append(.dot) }
            drawn.append(.entry(entries[at], at: at))
            before = at
        }
        return drawn
    }

    /// `entryAt`: the entry (its place among all the entries) under a finger at `y`, the drawn slots spread evenly
    /// from `top` over `height`. An entry's slot gives that entry, so a drawn letter always jumps to itself; a dot's
    /// slot spreads the entries it stands for over its own height, so a drag across it reaches each in turn.
    public static func entryAt(_ drawn: [Slot], y: Double, top: Double, height: Double) -> Int? {
        guard !drawn.isEmpty, height > 0 else { return nil }
        let place = (y - top) / height * Double(drawn.count)
        guard !place.isNaN else { return nil }
        let index = Int(min(Double(drawn.count - 1), max(0, place.rounded(.down))))
        func at(_ i: Int) -> Int? {
            guard i >= 0, i < drawn.count, case let .entry(_, at) = drawn[i] else { return nil }
            return at
        }
        if let own = at(index) { return own }
        guard let before = at(index - 1), let after = at(index + 1) else {
            //? fitIndex never draws a dot at an end or beside another dot; a hand-made list falls back to a neighbour
            return at(index - 1) ?? at(index + 1)
        }
        let between = after - before - 1
        if between <= 0 { return before }
        let within = min(1, max(0, place - Double(index)))
        return before + 1 + min(between - 1, Int((within * Double(between)).rounded(.down)))
    }
}
