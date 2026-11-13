import Foundation

/// AutoEq's suggestion for an output with no correction (eq.md 3.7): what deadwax's search for the output's cleaned
/// name (`EQOutputs.suggestionQuery`) offers - one headphone, a choice of several, or nothing. Never applied without
/// you; and never the first of several, which for "AirPods Pro" is the first generation's, offered to a Pro 2's owner
/// (iOS names both "AirPods Pro" - the design review's case).
///
/// The rows looked at are those whose names hold **every word of the cleaned name**, as whole words - folded as the
/// Library folds (`Fold.findText`: marks off, lowercased, `&` as "and", anything not a letter or a digit a gap) - so
/// "AirPods Pro" holds "Apple AirPods Pro 2 (ANC mode)" but not Rtings' "Apple AirPods Pro2". deadwax's own search is
/// wider (its words run together, so "hd650" finds "Sennheiser HD 650"); the picker shows all of it.
///
/// **One** is offered when only one row holds them, or when every row is one headphone - its name exactly, or its name
/// with a qualifier in parentheses (AutoEq's "Sennheiser HD 650 (2020)", "(balanced)", "(pre-2020, worn earpads)") -
/// and exactly one of them is the name alone: "Sennheiser HD 650" is offered the HD 650. (Departure from 3.7's
/// "exactly one row": AutoEq's real list has six HD 650 rows, so that rule offered 3.7's own example nothing.) A row
/// with another word outside parentheses is another model ("Apple AirPods Pro 2" beside "Apple AirPods Pro"), so an
/// output named "Apple AirPods Pro" is still offered the choice. And only from a whole answer: when deadwax found more
/// than the limit let through, a row not seen could be another model, so it is a choice.
public enum EQSuggestion: Equatable, Sendable {
    case none
    /// the one row, offered
    case one(AutoEqResult)
    /// the cleaned name, and the rows that hold it - for "pick yours"
    case several(query: String, rows: [AutoEqResult])

    /// The suggestion for `query` (the output's cleaned name) from deadwax's answer to it.
    public static func of(_ query: String, answer: AutoEqResults) -> EQSuggestion {
        let rows = answer.results.filter { holdsEveryWord(query, $0.name) }
        guard let first = rows.first else { return .none }
        if rows.count == 1 && answer.complete { return .one(first) }
        let asked = Fold.findText(query)
        let headphone = Fold.key(query)
        let alone = rows.filter { Fold.findText($0.name) == asked }
        if answer.complete, alone.count == 1, rows.allSatisfy({ Fold.key($0.name) == headphone }) {
            return .one(alone[0])
        }
        return .several(query: query, rows: rows)
    }

    /// Whether `name` holds every word of `query` as a whole word, folded. A query with no word holds nothing.
    public static func holdsEveryWord(_ query: String, _ name: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return false }
        let have = Set(words(name))
        return wanted.allSatisfy { have.contains($0) }
    }

    static func words(_ text: String) -> [String] {
        Fold.findText(text).split(separator: " ").map(String.init)
    }

    /// The rows the picker's "Suggested for" section shows: the one, or the several - none for nothing.
    public var rows: [AutoEqResult] {
        switch self {
        case .none: return []
        case .one(let row): return [row]
        case .several(_, let rows): return rows
        }
    }

    /// What the picker's field opens holding: the cleaned name for a choice, nothing otherwise (3.7).
    public var searched: String? {
        if case .several(let query, _) = self { return query }
        return nil
    }

    /// The suggestion row's two lines (3.7): "AutoEq has a correction for Apple AirPods Pro" / "Measured by
    /// crinacle"; "AutoEq has corrections for AirPods Pro" / "16 models - pick yours". None for nothing.
    public var lines: (title: String, detail: String)? {
        switch self {
        case .none:
            return nil
        case .one(let row):
            return (EQWords.Correction.suggestion(row.name), EQWords.Correction.measuredBy(row.source))
        case .several(let query, let rows):
            return (EQWords.Correction.suggestions(query), EQWords.Correction.models(rows.count))
        }
    }
}

/// Whether the suggestion is asked for and shown (3.7): Bluetooth and USB outputs only (8, question 20), with no
/// correction, not put away with "Not now" - and shown only once answered with something, online.
public enum EQSuggestionRules {
    /// Whether the EQ screen asks deadwax for this output's suggestion.
    public static func asks(_ output: EQOutput, _ setting: EQOutputSetting) -> Bool {
        output.offersSuggestion && setting.correction == nil && setting.suggestion != .notNow
            && !EQOutputs.suggestionQuery(setting.name.isEmpty ? output.name : setting.name).isEmpty
    }

    /// Whether its row is drawn: asked, answered with one or several, and online (an offer, not an error - so
    /// offline it simply isn't there).
    public static func shows(_ output: EQOutput, _ setting: EQOutputSetting, _ suggestion: EQSuggestion?,
                             online: Bool) -> Bool {
        guard asks(output, setting), online, let suggestion else { return false }
        return suggestion != .none
    }

    /// The query asked for an output: the name iOS gives it (yours from Rename is yours, not the model's), cleaned.
    public static func query(_ output: EQOutput, _ setting: EQOutputSetting) -> String {
        EQOutputs.suggestionQuery(setting.name.isEmpty ? output.name : setting.name)
    }
}
