import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/edit/edit-parts-vectors.json: the web's lib/tagEdit.ts, lib/trackInspector.ts (over lib/trackFields.ts) and
/// lib/albumEdit.ts run as they are, and components/TrackTagEditor.tsx's, app/EditPanel.tsx's and app/TrackInspector.tsx's
/// words read out of their sources - replayed here through TagEdit, TagEditWords and TrackInspector, case for case
/// (notes/ios-specs/phase8-managing.md 3.4).
@Suite struct EditPartsVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("edit/edit-parts-vectors.json"))

    static func file(_ web: Web) -> AlbumFile { EditVectorTests.decoded(AlbumFile.self, web) }

    static func shared(_ web: Web) -> TagEdit.Shared { TagEdit.Shared(value: web["value"].string!, mixed: web["mixed"].bool!) }

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-edit-parts-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/tagEdit.ts", "ui/src/lib/trackInspector.ts", "ui/src/lib/trackFields.ts",
                                 "ui/src/lib/albumEdit.ts", "ui/src/components/TrackTagEditor.tsx the heading",
                                 "ui/src/app/EditPanel.tsx the Edit tracks button",
                                 "ui/src/app/TrackInspector.tsx edit this track"])
        #expect(fixture["tags"]["problems"].list.count == 399)
        #expect(fixture["tags"]["notes"].list.count == 112)
        #expect(fixture["tags"]["shared"].list.count == 47)
        #expect(fixture["inspector"]["tracks"].list.count == 33)
    }

    // MARK: Tags

    @Test func theFieldsAreTheWebsInItsOrder() {
        let web = fixture["tags"]["fields"].list
        #expect(web.compactMap { $0["key"].string } == TagEdit.fields.map(\.key))
        for (field, row) in zip(TagEdit.fields, web) {
            #expect(Screens.same(field.label, row["label"].string), "\(field.key)")
            #expect(field.short == (row["short"].bool ?? false), "\(field.key)")
            #expect(field.numeric == (row["numeric"].bool ?? false), "\(field.key)")
            #expect(TagEdit.label(field.key) == field.label)
        }
        // the phone's four sections hold every field once, each in the web's order
        let grouped = TagEdit.sections.flatMap(\.keys)
        #expect(grouped.sorted() == TagEdit.fields.map(\.key).sorted())
        for section in TagEdit.sections {
            let order = section.keys.map { key in TagEdit.fields.firstIndex { $0.key == key }! }
            #expect(order == order.sorted(), "\(section.title)")
        }
        #expect(TagEdit.label("conductor") == "conductor")
    }

    @Test func theWordsAreTheWebs() {
        let words = fixture["tags"]["words"]
        let diffs = ScreenDiffs()
        diffs.text("readingFiles", TagEditWords.readingFiles, words["readingFiles"])
        diffs.text("previewFailed", TagEditWords.previewFailed, words["previewFailed"])
        diffs.text("applyFailed", TagEditWords.applyFailed, words["applyFailed"])
        diffs.text("readFailed", TagEditWords.readFailed, words["readFailed"])
        diffs.text("whatWouldChange", TagEditWords.whatWouldChange, words["whatWouldChange"])
        diffs.text("changeAField", TagEditWords.changeAField, words["changeAField"])
        diffs.text("working", TagEditWords.working, words["working"])
        diffs.text("saving", TagEditWords.saving, words["saving"])
        diffs.text("apply", TagEditWords.apply, words["apply"])
        diffs.text("undo", TagEditWords.undo, words["undo"])
        diffs.text("undoHint", TagEditWords.undoHint, words["undoHint"])
        diffs.text("removed", TagEditWords.removed, words["removed"])
        diffs.text("none", TagEditWords.none, words["none"])
        diffs.text("title", TagEditWords.title, words["title"])
        diffs.text("selectNote", TagEditWords.selectNote, words["selectNote"])
        diffs.text("selectAll", TagEditWords.selectAll, words["selectAll"])
        diffs.text("deselectAll", TagEditWords.deselectAll, words["deselectAll"])
        for row in words["hint"].list {
            // the web's, its Release tab the phone's Release page
            let web = row["words"].string!.replacingOccurrences(of: "the Release tab", with: "the Release page")
            diffs.text("hint \(row["single"])", TagEditWords.hint(single: row["single"].bool!), .string(web))
        }
        for row in words["fixFirst"].list { diffs.text("fixFirst \(row["count"])", TagEditWords.fixFirst(row["count"].int!), row["words"]) }
        for row in words["nothing"].list {
            diffs.text("nothing \(row["single"])", TagEditWords.nothingToChange(single: row["single"].bool!), row["words"])
        }
        for row in words["editTracks"].list {
            diffs.text("editTracks \(row["count"])", TagEditWords.editTracks(row["count"].int!), row["words"])
        }
        for row in words["selected"].list {
            diffs.text("selected", TagEditWords.selected(row["count"].int!, of: row["total"].int!), row["words"])
        }
        for row in words["editingThese"].list {
            diffs.text("editingThese", TagEditWords.editingThese(row["count"].int!), row["words"])
        }
        diffs.done()
    }

    @Test func eachFieldHoldsWhatTheWebSaysTheFilesShare() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["tags"]["shared"].list.enumerated() {
            let files = row["files"].list.map(Self.file)
            for key in row["values"].keys {
                let shared = TagEdit.shared(files, key)
                diffs.text("shared \(at) \(key) value", shared.value, row["values"][key]["value"])
                diffs.flag("shared \(at) \(key) mixed", shared.mixed, row["values"][key]["mixed"])
            }
        }
        diffs.done()
    }

    @Test func theEditsSentAreTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["tags"]["edits"].list.enumerated() {
            var draft: [String: String] = [:]
            for key in row["draft"].keys { draft[key] = row["draft"][key].string! }
            let edits = TagEdit.edits(filenames: row["filenames"].list.compactMap(\.string), draft: draft)
            diffs.check("edits \(at)", EditVectorTests.same(EditVectorTests.json(edits), row["edits"]), true)
        }
        diffs.done()
    }

    @Test func aValueIsRefusedAsTheWebRefusesIt() {
        let diffs = ScreenDiffs()
        for row in fixture["tags"]["problems"].list {
            let key = row["key"].string!, value = row["value"].string!
            diffs.text("problem \(key) \(Screens.spelled(value).prefix(40))", TagEdit.problem(key, value), row["problem"])
        }
        diffs.done()
        // 333: "July 2022" is refused in words; "2024-13" is not (neither the web nor the server checks the month)
        #expect(TagEdit.problem("date", "July 2022") == "Has to be a year or a date, like 2022 or 2022-07-29")
        #expect(TagEdit.problem("date", "2024-13") == nil)
    }

    @Test func eachFieldSaysWhatTheWebSaysUnderIt() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["tags"]["notes"].list.enumerated() {
            let key = row["key"].string!, shared = Self.shared(row["shared"])
            let draft = row["draft"].string
            let problem = draft.flatMap { TagEdit.problem(key, $0) }
            diffs.text("note \(at) problem", problem, row["problem"])
            diffs.flag("note \(at) removes", TagEdit.removes(shared, draft: draft), row["removes"])
            diffs.text("note \(at) placeholder", TagEdit.placeholder(key, shared, edited: draft != nil), row["placeholder"])
            diffs.text("note \(at) note", TagEdit.note(key, shared, draft: draft, problem: problem), row["note"])
        }
        diffs.done()
    }

    @Test func aTracksNumberIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["tags"]["labels"].list {
            let label = TagEdit.trackLabel(position: row["position"].int, disc: row["disc"].int, discs: row["discs"].int!)
            diffs.text("label \(row["position"]) \(row["disc"]) \(row["discs"])", label, row["label"])
        }
        diffs.done()
    }

    @Test func thePreviewAndTheApplySayWhatTheWebSays() {
        let plans = fixture["tags"]["plans"]
        let diffs = ScreenDiffs()
        for (at, row) in plans["states"].list.enumerated() {
            let plan = row["plan"].isNull ? nil : EditVectorTests.decoded(TagEditPlan.self, row["plan"])
            diffs.flag("state \(at) canApply", TagEditWords.canApply(plan: plan, planning: row["planning"].bool!,
                                                                    applying: row["applying"].bool!, problems: row["problems"].int!),
                       row["canApply"])
            diffs.text("state \(at) words", plan.map(TagEditWords.wouldChange), row["words"])
        }
        for (at, row) in plans["saved"].list.enumerated() {
            let results = EditVectorTests.decoded(TagEditResults.self, row["results"])
            let saved = TagEditWords.saved(results, filenames: row["filenames"].list.compactMap(\.string))
            diffs.text("saved \(at)", saved.text, row["text"])
            diffs.flag("saved \(at) failed", saved.failed, row["failed"])
        }
        for (at, row) in plans["heading"].list.enumerated() {
            let heading = TagEditWords.heading(filenames: row["filenames"].list.compactMap(\.string),
                                               files: row["files"].list.map(Self.file))
            diffs.text("heading \(at)", heading, row["words"])
        }
        diffs.done()
    }

    // MARK: a track's page

    @Test func aTracksPageIsTheWebsInspector() {
        let words = fixture["inspector"]["words"]
        let diffs = ScreenDiffs()
        diffs.text("NO_PICTURES", TrackInspector.noPictures, words["NO_PICTURES"])
        diffs.text("pictures", TrackInspector.pictures, words["pictures"])
        diffs.text("noTitle", TrackInspector.noTitle, words["noTitle"])
        diffs.text("editThis", TrackInspector.editThis, words["editThis"])
        diffs.text("pictureLabel", TrackInspector.pictureLabel(EmbeddedPicture(index: 0, label: "Front cover")), words["pictureLabel"])
        for (at, row) in fixture["inspector"]["tracks"].list.enumerated() {
            let file = Self.file(row["file"])
            let groups = TrackInspector.groups(file)
            diffs.check("track \(at) groups", groups.map(\.group.rawValue), row["groups"].list.compactMap { $0["name"].string })
            for (group, web) in zip(groups, row["groups"].list) {
                diffs.check("track \(at) \(group.id) ids", group.fields.map(\.id), web["fields"].list.compactMap { $0["id"].string })
                for (field, cell) in zip(group.fields, web["fields"].list) {
                    diffs.text("track \(at) \(field.id) label", field.label, cell["label"])
                    diffs.text("track \(at) \(field.id) value", field.value, cell["value"])
                    diffs.flag("track \(at) \(field.id) mono", field.mono, cell["mono"])
                    diffs.text("track \(at) \(field.id) inferred", field.inferred, cell["inferred"])
                }
            }
            diffs.flag("track \(at) untitled", TrackInspector.untitled(file), row["untitled"])
            diffs.text("track \(at) title", TrackInspector.title(file), row["title"])
            for place in row["places"].list {
                diffs.text("track \(at) place \(place["discs"])", TrackInspector.place(file, discs: place["discs"].int!), place["words"])
            }
            diffs.text("track \(at) raw", TrackInspector.rawTitle(file), row["raw"])
            for (picture, web) in zip(file.pictures, row["pictures"].list) {
                diffs.text("track \(at) picture bytes", TrackInspector.pictureBytes(picture.size), web["bytes"])
                for facts in web["facts"].list {
                    diffs.text("track \(at) picture facts", TrackInspector.pictureFacts(picture, pixels: facts["pixels"].string),
                               facts["words"])
                }
            }
            diffs.check("track \(at) pictures", file.pictures.count, row["pictures"].list.count)
        }
        diffs.done()
        #expect(TrackInspector.pixels(width: 500, height: 500) == "500 \u{d7} 500")
    }
}
