import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/artists/artist-manage-vectors.json: the web's lib/artistManage.ts run as it is, and app/ArtistPanel.tsx's
/// and app/ArtistPage.tsx's own read out of their source (ios/scripts/export-artist-manage-vectors.cjs) - replayed here
/// through ArtistManage and ArtistManageWords, case for case (Phase 8, slice 5). The plans, candidates, summaries and
/// matches are read by the phone's own decoders, as deadwax's answers are.
@Suite struct ArtistManageVectorTests {
    struct Vectors: Decodable {
        let madeBy: String
        let madeFrom: [String: String]
        let words: [String: String]
        let sentences: Sentences
        let names: [NamesCase]
        let toMove: [ToMoveCase]
        let folders: [FolderCase]
        let kinds: [KindsCase]
        let others: [OthersCase]
        let bests: [BestCase]
        let choices: [ChoiceCase]
        let slots: [SlotCase]
        let notes: [NotesCase]
        let saved: [SavedCase]
        let matches: [MatchCase]
        let showing: [ShowingCase]
        let whoShown: [WhoShownCase]
        let refile: [RefileCase]
        let listed: [ListedCase]
        let subtitles: [SubtitleCase]

        enum CodingKeys: String, CodingKey {
            case words, sentences, names, toMove, folders, kinds, others, bests, choices, slots, notes, saved, matches,
                 showing, whoShown, refile, listed, subtitles
            case madeBy = "made_by"
            case madeFrom = "made_from"
        }
    }

    struct Sentences: Decodable {
        struct Named: Decodable { let name: String; let text: String }
        struct Queried: Decodable { let query: String; let text: String }
        struct Note: Decodable { let toFolder: String; let currentName: String; let lead: String; let folder: String; let rest: String }
        struct Reason: Decodable { let reason: String; let text: String }
        struct Target: Decodable { let target: String; let text: String }
        struct Item: Decodable { let name: String; let web: String }
        struct Option: Decodable { let label: String; let source: String; let text: String }
        struct Label: Decodable { let label: String; let text: String }
        struct Count: Decodable { let count: Int; let text: String }
        let looking: [Named]
        let nothingGoesBy: [Queried]
        let whoNote: [Named]
        let moveNote: [Note]
        let nothingToMove: [Named]
        let stays: [Reason]
        let movesTo: [Target]
        let moveItem: [Item]
        let option: [Option]
        let onDisk: [Label]
        let useAnother: [Count]
    }

    struct Who: Decodable { let mbid: String?; let name: String?; let releases: [String] }
    struct NamesCase: Decodable { let who: Who; let folders: [OwnedAlbum]?; let names: [String] }
    struct ToMoveCase: Decodable { let names: [String]; let current: String?; let toMove: [String] }
    struct Pair: Decodable {
        let name: String
        let said: ArtistManage.Said
        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            name = try pair.decode(String.self)
            said = try pair.decodeNil() ? .unread : .answered(try pair.decode(ArtistSummary.self))
        }
    }
    struct Folder: Decodable { let name: String?; let reason: String? }
    struct FolderCase: Decodable { let names: [String]; let current: String?; let summaries: [Pair]; let folder: Folder }
    struct KindsCase: Decodable { let candidates: [ArtistImageCandidate]; let byKind: [String: [ArtistImageCandidate]] }
    struct OthersCase: Decodable {
        let candidates: [ArtistImageCandidate]
        let kind: String
        let others: [ArtistImageCandidate]
        let another: String?
    }
    struct BestCase: Decodable { let best: [String: ArtistImageCandidate]; let urls: [String: String] }
    struct ChoiceCase: Decodable { let chosen: [String: String]; let kind: String; let url: String; let next: [String: String] }
    struct SlotCase: Decodable { let existing: String?; let found: Int; let line: String }
    struct Sources: Decodable { let fanarttv: Bool }
    struct NotesCase: Decodable {
        let hasKey: Bool
        let sources: Sources?
        let notes: [String]
        enum CodingKeys: String, CodingKey { case sources, notes; case hasKey = "has_key" }
    }
    struct SavedCase: Decodable { let written: [String]; let problems: [String]; let line: String }
    struct MatchCase: Decodable { let match: MBArtistMatch; let line: String }
    struct ShowingCase: Decodable { let who: String; let disambiguation: String?; let text: String }
    struct WhoShownCase: Decodable { let factsName: String?; let name: String; let who: String }
    struct Named: Decodable { let name: String; let plan: ArtistRefilePlan }
    struct Applied: Decodable { let name: String; let plan: ArtistRefilePlan; let results: ArtistRefileResults }
    struct View: Decodable {
        let currentName: String
        let toFolder: String
        let moves: [RefileMove]
        let refused: [RefileRefused]
        let problems: [String]
        let empty: Bool
    }
    struct After: Decodable { let stayed: [String]; let emptied: [String] }
    struct Outcome: Decodable { let moved: Int; let text: String; let failures: [String] }
    struct RefileCase: Decodable {
        let name: String
        let plans: [Named]
        let view: View?
        let canMove: Bool
        let button: String
        let lines: [String]
        let namesApplied: [String]
        let applied: [Applied]
        let after: After?
        let outcome: Outcome?
    }
    struct ListedCase: Decodable { let items: [String]; let text: String }
    struct SubtitleCase: Decodable { let moveNames: [String]; let currentName: String?; let name: String; let subtitle: String }

    static let vectors = try! JSONDecoder().decode(Vectors.self, from: Fixtures.data("artists/artist-manage-vectors.json"))
    var fixture: Vectors { Self.vectors }

    @Test func theFixtureIsThere() {
        #expect(fixture.madeBy == "ios/scripts/export-artist-manage-vectors.cjs")
        for source in ["ui/src/lib/artistManage.ts", "ui/src/lib/artistPage.ts", "ui/src/lib/owned.ts",
                       "ui/src/app/ArtistPanel.tsx the subtitle", "ui/src/app/ArtistPanel.tsx the names Move applies",
                       "ui/src/app/ArtistPanel.tsx a slot's other pictures", "ui/src/app/ArtistPanel.tsx canSave",
                       "ui/src/app/ArtistPanel.tsx use another picture, when", "ui/src/app/ArtistPanel.tsx who is shown",
                       "ui/src/app/ArtistPage.tsx the Move albums button"] {
            #expect(fixture.madeFrom[source]?.utf8.count == 64, "made_from names \(source)")
        }
        #expect(fixture.names.count == 76)
        #expect(fixture.folders.count == 17)
        #expect(fixture.refile.count == 13)
    }

    // MARK: which names, which folder

    @Test func theLibrarysNamesForAnArtistAreTheWebs() {
        var some = 0
        for (at, each) in fixture.names.enumerated() {
            let index = each.folders.map { OwnedIndex($0) }
            let who = ArtistManage.Who(mbid: each.who.mbid, name: each.who.name, releases: each.who.releases)
            #expect(ArtistManage.libraryNames(index, who: who) == each.names, "case \(at): \(each.who)")
            if !each.names.isEmpty { some += 1 }
        }
        #expect(some > 30, "most cases find a name")
    }

    @Test func theNamesToMoveAreTheWebs() {
        for each in fixture.toMove {
            #expect(ArtistManage.namesToMove(each.names, current: each.current) == each.toMove,
                    "\(each.names) now \(String(describing: each.current))")
        }
    }

    @Test func theFolderForTheirPicturesIsTheWebs() {
        for each in fixture.folders {
            let folder = ArtistManage.imagesFolder(each.names, current: each.current,
                                                   summaries: each.summaries.map { ($0.name, $0.said) })
            #expect(folder == ArtistManage.ImagesFolder(name: each.folder.name, reason: each.folder.reason),
                    "\(each.names) now \(String(describing: each.current))")
        }
    }

    // MARK: Artist images

    @Test func thePicturesRulesAreTheWebs() {
        for each in fixture.kinds {
            #expect(ArtistManage.byKind(each.candidates) == each.byKind)
        }
        #expect(fixture.others.count == 10)
        for each in fixture.others {
            #expect(ArtistManage.others(each.candidates, kind: each.kind) == each.others, "\(each.kind)")
            // the button the sheet draws (ArtistImagesSheet's slotSection calls this), and when
            #expect(ArtistManage.anotherPicture(each.candidates, kind: each.kind) == each.another, "\(each.kind)")
        }
        for each in fixture.bests {
            #expect(ArtistManage.bestUrls(each.best) == each.urls)
        }
        #expect(fixture.choices.count == 7)
        for each in fixture.choices {
            #expect(ArtistManage.toggleChoice(each.chosen, kind: each.kind, url: each.url) == each.next,
                    "\(each.kind) \(each.url) over \(each.chosen)")
        }
        for each in fixture.slots {
            #expect(ArtistManage.slotLine(existing: each.existing, found: each.found) == each.line)
        }
        for each in fixture.notes {
            #expect(ArtistManage.imageNotes(hasKey: each.hasKey, fanarttv: each.sources?.fanarttv) == each.notes)
        }
        for each in fixture.saved {
            #expect(ArtistManage.savedLine(written: each.written, problems: each.problems) == each.line)
            #expect(ArtistImagesResults(written: each.written, problems: each.problems).line == each.line)
        }
        for each in fixture.matches {
            #expect(ArtistManage.matchLine(each.match) == each.line, "\(each.match)")
        }
        for each in fixture.showing {
            #expect(ArtistManage.showing(each.who, disambiguation: each.disambiguation ?? "") == each.text)
        }
        #expect(fixture.whoShown.count == 5)
        for each in fixture.whoShown {
            #expect(ArtistManage.showingWho(factsName: each.factsName, pageName: each.name) == each.who)
        }
    }

    // MARK: Move albums

    @Test func movingAlbumsIsTheWebs() {
        for each in fixture.refile {
            let plans = each.plans.map { ArtistManage.NamedPlan(name: $0.name, plan: $0.plan) }
            let view = ArtistManage.refileView(plans)
            if let web = each.view {
                #expect(view == ArtistManage.RefileView(currentName: web.currentName, toFolder: web.toFolder,
                                                        moves: web.moves, refused: web.refused, problems: web.problems,
                                                        empty: web.empty), "\(each.name): the view")
            } else {
                #expect(view == nil, "\(each.name): no view")
            }
            #expect(ArtistManage.canMove(view) == each.canMove, "\(each.name): Move")
            #expect(ArtistManage.moveButton(view?.moves.count ?? 0) == each.button, "\(each.name): the button")
            #expect((view?.moves ?? []).map(ArtistManage.moveLine) == each.lines, "\(each.name): the lines")
            guard let view else { continue }
            #expect(ArtistManage.namesApplied(plans, view: view).map(\.name) == each.namesApplied,
                    "\(each.name): the names applied")
            let applied = each.applied.map { ArtistManage.AppliedName(name: $0.name, plan: $0.plan, results: $0.results) }
            let after = ArtistManage.refileAfter(previewed: plans, applied: applied, view: view)
            #expect(after.stayed == each.after?.stayed && after.emptied == each.after?.emptied, "\(each.name): after")
            let outcome = ArtistManage.refileOutcome(applied.map(\.results), toFolder: view.toFolder)
            #expect(outcome.moved == each.outcome?.moved && outcome.text == each.outcome?.text
                    && outcome.failures == each.outcome?.failures, "\(each.name): the outcome")
        }
        for each in fixture.listed {
            #expect(ArtistManage.listed(each.items) == each.text)
        }
        for each in fixture.subtitles {
            #expect(ArtistManage.refileSubtitle(moveNames: each.moveNames, current: each.currentName, name: each.name)
                    == each.subtitle)
        }
    }

    // MARK: the words

    @Test func theWordsAreTheWebs() {
        let words = fixture.words
        let phone: [String: String] = [
            "imagesTitle": ArtistManageWords.imagesTitle, "refileTitle": ArtistManageWords.refileTitle,
            "whoTitle": ArtistManageWords.whoTitle, "noFolder": ArtistManageWords.noFolder,
            "lookFailed": ArtistManageWords.lookFailed, "searchFailed": ArtistManageWords.searchFailed,
            "saveFailed": ArtistManageWords.saveFailed, "notThem": ArtistManageWords.notThem,
            "searchLabel": ArtistManageWords.searchLabel, "search": ArtistManageWords.search,
            "replace": ArtistManageWords.replace, "saving": ArtistManageWords.saving, "save": ArtistManageWords.save,
            "whichArtist": ArtistManageWords.whichArtist, "searching": ArtistManageWords.searching,
            "artistsGoingBy": ArtistManageWords.artistsGoingBy, "working": ArtistManageWords.working,
            "albumsThatMove": ArtistManageWords.albumsThatMove, "albumsThatStay": ArtistManageWords.albumsThatStay,
            "nothingCanMove": ArtistManageWords.nothingCanMove, "previewFailed": ArtistManageWords.previewFailed,
            "moveFailed": ArtistManageWords.moveFailed, "moving": ArtistManageWords.moving,
            "done": ArtistManageWords.done, "cancel": ArtistManageWords.cancel,
            "imagesItem": ArtistManageWords.imagesItem, "whoItem": ArtistManageWords.whoItem,
            "chosen": ArtistManageWords.chosen,
        ]
        // Fewer folds a slot's other pictures away on the web; the phone pushes them as a page, so it has none
        let webOnly: Set<String> = ["fewer"]
        #expect(Set(words.keys) == Set(phone.keys).union(webOnly))
        for (key, web) in words where !webOnly.contains(key) {
            #expect(phone[key].map { WebText.same($0, web) } == true, "\(key): \(web)")
        }
        let said = fixture.sentences
        for each in said.looking { #expect(ArtistManageWords.looking(each.name) == each.text) }
        for each in said.nothingGoesBy { #expect(ArtistManageWords.nothingGoesBy(each.query) == each.text) }
        for each in said.whoNote { #expect(ArtistManageWords.whoNote(each.name) == each.text) }
        for each in said.moveNote {
            let note = ArtistManageWords.refileNote(toFolder: each.toFolder, currentName: each.currentName)
            #expect(note.lead == each.lead && note.folder == each.folder && note.rest == each.rest)
        }
        for each in said.nothingToMove { #expect(ArtistManageWords.nothingToMove(each.name) == each.text) }
        for each in said.stays { #expect(ArtistManageWords.stays(each.reason) == each.text) }
        for each in said.movesTo { #expect(ArtistManageWords.movesTo(each.target) == each.text) }
        // the menu item is the web's button with the ellipsis a menu item opening a sheet takes
        for each in said.moveItem { #expect(ArtistManageWords.moveItem(each.name) == each.web + "\u{2026}") }
        for each in said.option {
            #expect(ArtistManageWords.option(ArtistImageCandidate(kind: "thumb", url: "u", source: each.source,
                                                                  label: each.label)) == each.text)
        }
        for each in said.onDisk { #expect(ArtistManageWords.onDisk(each.label) == each.text) }
        for each in said.useAnother { #expect(ArtistManageWords.useAnother(each.count) == each.text) }
    }
}
