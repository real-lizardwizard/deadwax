import Foundation

/// Needs a look as the redesign draws it (slice R12 - notes/ios.md "The redesign, slice R12: Needs a look";
/// NeedsALook.dc.html, iNeedsALook.dc.html): what the Mac's page (MacNeedsALook) and the phone's (NeedsLookScreen) draw
/// beside the web's own rules (NeedsLook, NeedsLookWords, from care-vectors.json), never in their place. Every count here
/// is one of NeedsLook's: All's is `summaryTotal`'s, the count the sidebar's row and Settings' Manage row say, so the
/// queue and the badge never count different things.
public enum NeedsLookPage {
    // MARK: Marked fine, a button of its own

    /// The facets the strip (the phone) and the Show pop-up (the Mac) offer: every facet drawn but Marked fine, which is a
    /// button of its own at the top (the drawings' "Marked fine · 2").
    public static func strip(_ chips: [NeedsLook.Facet]) -> [NeedsLook.Facet] {
        chips.filter { (chip: NeedsLook.Facet) -> Bool in !isMarkedFine(chip.id) }
    }

    /// Marked fine among the facets drawn - nil with no album marked fine, when its button isn't drawn.
    public static func markedFine(_ chips: [NeedsLook.Facet]) -> NeedsLook.Facet? {
        chips.first { (chip: NeedsLook.Facet) -> Bool in isMarkedFine(chip.id) }
    }

    /// A facet's id is Marked fine's (`IGNORED_FACET`, code unit by code unit).
    public static func isMarkedFine(_ id: String?) -> Bool {
        id.map { (facet: String) -> Bool in WebText.same(facet, NeedsLook.ignoredFacet) } ?? false
    }

    /// Marked fine's button pressed: Marked fine shown - or, shown already, All again (the button is on while it shows).
    public static func markedFineTapped(_ pressed: String?) -> String? {
        isMarkedFine(pressed) ? nil : NeedsLook.ignoredFacet
    }

    /// Its words: "Marked fine · 2".
    public static func markedFineWords(_ count: Int) -> String { "\(NeedsLook.markedFine) · \(count)" }

    // MARK: the Mac's Show pop-up

    /// The pop-up's words for a facet (NeedsALook.dc.html's "Every issue · 3 albums"): All as Every issue, the rest by
    /// their labels, with how many albums each has.
    public static func popUp(_ chip: NeedsLook.Facet) -> String {
        "\(chip.id == nil ? everyIssue : chip.label) · \(albums(chip.count))"
    }

    /// The pop-up to VoiceOver: "Show, Every issue, 3 albums".
    public static func popUpSpoken(_ chip: NeedsLook.Facet?) -> String {
        guard let chip else { return NeedsLook.show }
        return "\(NeedsLook.show), \(chip.id == nil ? everyIssue : chip.label), \(albums(chip.count))"
    }

    public static let everyIssue = "Every issue"

    static func albums(_ count: Int) -> String { "\(AlbumInfo.grouped(count)) album\(count == 1 ? "" : "s")" }

    // MARK: the counts

    /// The Mac's status bar: how many albums need a look - `summaryTotal`, the queue's own count and the sidebar's, from
    /// the scan as it is now - and how many are marked fine, when any are (the drawing's "3 need a look", "2 marked fine").
    public static func status(_ albums: [ScanAlbum]) -> [String] {
        let fine = albums.filter(NeedsLook.isIgnoredOnly).count
        return [EditAlbumPage.Words.needALook(NeedsLook.summaryTotal(albums))]
            + (fine > 0 ? ["\(AlbumInfo.grouped(fine)) marked fine"] : [])
    }

    /// (R12's review - notes/ios.md "The redesign, slice R12: Needs a look", "After review") The facets drawn - which ones
    /// as `shown` has them (held as a session began, the ending's, or the live ones) - each counted from the scan as it
    /// is now (`live`): All's is summaryTotal's, the status bar's and the sidebar's, Marked fine's the status bar's
    /// "N marked fine". So after It's fine on one album the pop-up, Marked fine · N and the status bar say one number
    /// each (the decision: "The tab badge and the queue never count different things"). A live facet `shown` lacks -
    /// Marked fine, once It's fine took an album there - joins them, Marked fine last; drawn are All, the one pressed,
    /// and the rest with an album now. The albums a session steps through stay its own (NeedsLook.Run).
    public static func counted(_ shown: [NeedsLook.Facet], live: [NeedsLook.Facet],
                               pressed: String?) -> [NeedsLook.Facet] {
        let joined = shown + live.filter { (chip: NeedsLook.Facet) -> Bool in
            NeedsLook.chip(shown, pressed: chip.id) == nil
        }
        let now = joined.map { (chip: NeedsLook.Facet) -> NeedsLook.Facet in
            NeedsLook.Facet(id: chip.id, label: chip.label, count: NeedsLook.chip(live, pressed: chip.id)?.count ?? 0,
                            hint: chip.hint)
        }
        let ordered = now.filter { (chip: NeedsLook.Facet) -> Bool in !isMarkedFine(chip.id) }
            + now.filter { (chip: NeedsLook.Facet) -> Bool in isMarkedFine(chip.id) }
        return ordered.filter { (chip: NeedsLook.Facet) -> Bool in
            chip.id == nil || chip.count > 0 || NeedsLook.chip([chip], pressed: pressed) != nil
        }
    }

    // MARK: reading

    /// (R12's review) A pull - the phone's, the Mac's ⌘R - asks the count and reads the library again: in reach, for the
    /// person the page opened for, with Look after the library - and, as Try again and a sign-in again are held, never
    /// while a read is out nor while a session lasts. The editor beside the queue reads this same scan: a read of the
    /// page's begun under its read, or the follow-up read after its Apply, took over from it (the editor's then came
    /// back with nothing - ScanReads, its other half).
    public static func pullReads(online: Bool, samePerson: Bool, allowed: Bool, session: Bool, reading: Bool) -> Bool {
        online && samePerson && allowed && !session && !reading
    }

    // MARK: It's fine as it is

    /// (R12's review) Whether the Mac's foot offers It's fine as it is in queue mode - exactly as the phone does: its
    /// button sits in the Release tab's Needs a look section, which is Edit albums' (Managing.albumEdit's `editors`), and
    /// is drawn there only with Look after the library too, its route's permission (AlbumEdit.marksFine). Both, as the
    /// web has them (docs/sharing.md: "with Edit albums too, Edit album's It's fine as it is").
    public static func offersFine(_ permissions: Set<Access.Permission>) -> Bool {
        Managing.albumEdit(permissions).editors && AlbumEdit.marksFine(permissions)
    }

    // MARK: a row

    /// A row's issue count, the Mac list's Issues column: its outstanding issues (none drawn for none, or once a session
    /// has said what became of it).
    public static func issueCount(_ row: NeedsLook.DrawnRow) -> Int {
        row.mark == nil ? MetadataQueue.outstanding(row.album).count : 0
    }

    /// What a chip of a row's says, by meaning - the app colours each: an issue still to look at, a new import, what
    /// became of it in a session, or an album marked fine as it is.
    public enum ChipKind: Sendable, Equatable {
        case issue, new, fixed, markedFine, deleted
    }

    /// A row's chips (NeedsLook.chipWords), each with its kind.
    public static func chips(_ row: NeedsLook.DrawnRow, pressed: String?,
                             issueTypes: [String: MetadataIssueType]) -> [(words: String, kind: ChipKind)] {
        let words = NeedsLook.chipWords(row, pressed: pressed, issueTypes: issueTypes)
        if let mark = row.mark {
            let kind: ChipKind
            switch mark {
            case .fixed: kind = .fixed
            case .ignored: kind = .markedFine
            case .deleted: kind = .deleted
            }
            return words.map { (said: String) -> (words: String, kind: ChipKind) in (said, kind) }
        }
        let fresh = MetadataQueue.isNewImport(row.album)
        let issues = MetadataQueue.outstanding(row.album).count
        return words.enumerated().map { (at: Int, said: String) -> (words: String, kind: ChipKind) in
            if fresh && at == 0 { return (said, .new) }
            return (said, at < (fresh ? 1 : 0) + issues ? .issue : .markedFine)
        }
    }

    /// The Mac's row, its chips folded to fit (NeedsALook.dc.html's "+2"): the first `shown` of them, then how many more.
    public static func more(_ count: Int, shown: Int) -> String? {
        count > shown ? "+\(count - shown)" : nil
    }

    /// The Mac's row on the pointer: its folder, then every chip's words - the whole of what a narrow row folds away.
    public static func help(_ row: NeedsLook.DrawnRow, chips: [String]) -> String {
        ([row.album.path] + (chips.isEmpty ? [] : [chips.joined(separator: " \u{00B7} ")])).joined(separator: "\n")
    }

    // MARK: a session

    /// A row picked while a session lasts (the Mac's list, beside the editor): the step from the album open to it - 0 for
    /// that album, or a row the session doesn't hold.
    public static func step(to key: String, in session: NeedsLook.Session) -> Int {
        guard let at = session.rows.firstIndex(where: { (row: NeedsLook.SessionRow) -> Bool in
            WebText.same(row.listed.path, key)
        }) else { return 0 }
        return at - session.index
    }

    /// Apply moves on (the web's `applied && queue && queue.position < queue.total`, MetadataEditor.tsx): once a release
    /// was applied to the album, the foot's purple button is Next album - the last album keeps Apply.
    public static func movesOn(_ nav: NeedsLook.Nav?, applied: Bool) -> Bool {
        guard let nav else { return false }
        return applied && nav.on
    }

    // MARK: the words

    /// Under the list (iNeedsALook.dc.html).
    public static let leaves = "An album leaves this list once its issues are fixed or marked fine."
    /// Under the Mac's list (NeedsALook.dc.html): the count beside Needs a look in the sidebar is this list's.
    public static let macLeaves = "The count in the sidebar and this list always agree: an album leaves once its issues "
        + "are fixed or marked fine."
    /// Queue mode's bar's ‹ (both drawings' `‹` button), Previous album to VoiceOver (NeedsLookWords.previous): words,
    /// as Skip › is, so the bar's three sit on one baseline beside its readout.
    public static let back = "\u{2039}"
    /// The Mac's list's last column: how many issues each album still has.
    public static let issuesColumn = "Issues"
    /// The Mac's editor with no album open beside the queue.
    public static let pickAnAlbum = "Choose an album at the left to look at it here."
    /// The Mac's foot under Release in queue mode, beside It's fine as it is, while there is an album after this one.
    public static let movesOnLine = "After Apply, Next album takes its place."
}
