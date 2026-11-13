import Foundation

/// AutoEq's suggestion for an output with no correction (eq.md 3.7): what deadwax's search for the output's cleaned
/// name (`EQOutputs.suggestionQuery`) offers - one headphone, a choice of several, or nothing. Never applied without
/// you; and never the first of several, which for "AirPods Pro" is the first generation's, offered to a Pro 2's owner
/// (iOS names both "AirPods Pro" - the design review's case).
///
/// The rows looked at are those whose names hold **every word of the cleaned name**, as whole words - folded as the
/// Library folds (`Fold.findText`: marks off, lowercased, `&` as "and", anything not a letter or a digit a gap), and a
/// `+` as the word "plus" (`folded`) - so "AirPods Pro" holds "Apple AirPods Pro 2 (ANC mode)" but not Rtings' "Apple
/// AirPods Pro2", and "Beats Studio Buds +" doesn't hold "Beats Studio Buds". deadwax's own search is wider (its words
/// run together, so "hd650" finds "Sennheiser HD 650", and it drops a `+`); the picker shows all of it.
///
/// **One** is offered when only one row holds them and it is this headphone - its name, or its name after a maker's
/// ("Apple AirPods Max" for "AirPods Max"), a qualifier in parentheses aside - or when every row is one headphone -
/// its name exactly, or its name with a qualifier in parentheses (AutoEq's "Sennheiser HD 650 (2020)", "(balanced)",
/// "(pre-2020, worn earpads)") - and exactly one of them is the name alone: "Sennheiser HD 650" is offered the HD 650.
/// (Departure from 3.7's "exactly one row": AutoEq's real list has six HD 650 rows, so that rule offered 3.7's own
/// example nothing.) A row with another word after the name, or among its words, outside parentheses, is another
/// model ("Apple AirPods Pro 2" beside "Apple AirPods Pro"; "Samsung Galaxy Buds 2 Pro" for "Galaxy Buds Pro"), so it
/// is a choice even when it is the only row - an output named "Apple AirPods Pro" is still offered the choice. And
/// only from a whole answer: when deadwax found more than the limit let through, a row not seen could be another
/// model, so it is a choice.
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
        let several = EQSuggestion.several(query: query, rows: rows)
        guard answer.complete else { return several }
        let headphone = folded(query, key: true)
        guard !headphone.isEmpty else { return several }
        if rows.count == 1 {
            // the one row is offered only when it is this headphone: a word after the name, or among its words, is
            // another model - "Apple AirPods Pro 2 (ANC mode)" alone isn't the AirPods Pro's
            let name = folded(first.name, key: true)
            return name == headphone || name.hasSuffix(" " + headphone) ? .one(first) : several
        }
        let asked = folded(query, key: false)
        let alone = rows.filter { folded($0.name, key: false) == asked }
        if alone.count == 1, rows.allSatisfy({ folded($0.name, key: true) == headphone }) {
            return .one(alone[0])
        }
        return several
    }

    /// Whether `name` holds every word of `query` as a whole word, folded. A query with no word holds nothing.
    public static func holdsEveryWord(_ query: String, _ name: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return false }
        let have = Set(words(name))
        return wanted.allSatisfy { have.contains($0) }
    }

    static func words(_ text: String) -> [String] {
        folded(text, key: false).split(separator: " ").map(String.init)
    }

    /// A name as the suggestion compares it: `Fold.findText` (or `Fold.key`, a bracketed aside dropped), with a `+` as
    /// the word "plus" - which Fold drops as punctuation, and which names another model: Apple's "Beats Studio Buds +"
    /// isn't the Beats Studio Buds, and AutoEq's "T2+" is the "T2 Plus".
    static func folded(_ text: String, key: Bool) -> String {
        let plus = text.replacingOccurrences(of: "+", with: " plus ")
        return key ? Fold.key(plus) : Fold.findText(plus)
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

/// Choosing a correction (3.7) and the suggestion's two marks (4), as the settings keep them.
extension EQSettings {
    /// A correction used ("Use for …"): the output's correction from now on, crossfaded, and the EQ turned on if it was
    /// Off - true when it turned it on, for VoiceOver's "EQ on". `nil` ("None"): the correction taken away, the switch
    /// left as it is (nothing new to hear is turned on for). An output never met is given its setting first.
    @discardableResult
    public mutating func use(_ correction: EQCorrection?, for o: EQOutput) -> Bool {
        guard let correction else {
            if let i = outputs.firstIndex(where: { $0.key == o.key }) { outputs[i].correction = nil }
            return false
        }
        return change(o, always: true) { $0.correction = correction }
    }

    /// The suggestion's mark (4): "Not now", for good; "shown", the first time it is drawn - never over a Not now.
    /// True when anything changed (the file is written; nothing is heard differently).
    @discardableResult
    public mutating func mark(_ suggestion: EQOutputSetting.Suggestion, for o: EQOutput) -> Bool {
        if output(o.key) == nil { outputs.append(EQSettings.newOutput(o, seen: "")) }
        guard let i = outputs.firstIndex(where: { $0.key == o.key }) else { return false }
        let now: EQOutputSetting.Suggestion = suggestion == .notNow || outputs[i].suggestion == .notNow ? .notNow : .shown
        guard outputs[i].suggestion != now else { return false }
        outputs[i].suggestion = now
        return true
    }
}

extension EQOutputSetting {
    /// Whether AutoEq's profile `id` is this output's correction now ("Used for …").
    public func uses(_ id: String) -> Bool {
        correction?.kind == .autoeq && correction?.id == id
    }
}

extension EQDrawing {
    /// A profile's page's curve (3.7): the correction alone - no tone, the EQ on - at 48 kHz, with its own automatic
    /// preamp, whatever the output's own setting is.
    public static func profile(_ correction: EQCorrection, for o: EQOutput, in settings: EQSettings) -> EQDrawing {
        var alone = EQSettings.newOutput(o, seen: "")
        alone.on = true
        alone.correction = correction
        alone.tone = .preset("flat")
        alone.preamp = .automatic
        return make(alone, in: settings, rate: 48_000)
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
