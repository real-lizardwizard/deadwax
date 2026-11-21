import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/edit/edit-parts-vectors.json: the web's lib/tagEdit.ts, lib/trackInspector.ts (over lib/trackFields.ts) and
/// lib/albumEdit.ts run as they are, and components/TrackTagEditor.tsx's, app/EditPanel.tsx's and app/TrackInspector.tsx's
/// words read out of their sources - replayed here through TagEdit, TagEditWords and TrackInspector, case for case
/// (notes/ios-specs/phase8-managing.md 3.4); and lib/getResults.ts, lib/lyrics.ts and components/LibraryParts.tsx's
/// three Get buttons through GetResults and GetRun (3.5); and Delete album - lib/albumEdit.ts's delete words and deletesAll,
/// lib/myLibrary.ts's holdersText and components/DeleteAlbumDialog.tsx's flow - through DeleteWords and AlbumEdit (3.6).
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
        #expect(fixture["tags"]["problems"].list.count == 471, "the separators below 0x20 too (review, 16 Nov)")
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
        diffs.text("selectNote", TagEditWords.selectNote(.iPhone), words["selectNote"])
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

    // MARK: Artwork and Lyrics (slice 3)

    /// An error as the fixture describes it, made as the app meets it: deadwax's answer, no answer, none in time, another.
    static func failure(_ spec: Web) -> APIFailure {
        spec["answer"].isNull ? screenFailure(spec, path: "/library/art/fetch")
            : screenFailure(spec["answer"], path: "/library/art/fetch")
    }

    static func album(_ web: Web) -> ScanAlbum {
        ScanAlbum(path: "A/B", releaseMbid: web["release_mbid"].string!, art: web["art"].string!,
                  trackCount: web["track_count"].int!, lyricsCount: web["lyrics_count"].int!,
                  discArt: web["disc_art"].list.compactMap(\.string))
    }

    static func summary(_ web: Web) -> LyricsSummary {
        LyricsSummary(written: web["written"].int!, replaced: web["replaced"].int!, kept: web["kept"].int!,
                      instrumental: web["instrumental"].int!, missing: web["missing"].int!, failed: web["failed"].int!,
                      untagged: web["untagged"].int!, synced: web["synced"].int!)
    }

    @Test func theArtworkAndLyricsWordsAreTheWebs() {
        let words = fixture["artwork"]["words"]
        let diffs = ScreenDiffs()
        for kind in GetResults.Kind.allCases {
            diffs.text("getting \(kind)", GetResults.getting(kind), words["GETTING"][kind.rawValue])
            diffs.text("failed \(kind)", GetResults.failed(kind), words["GET_FAILED"][kind.rawValue])
        }
        diffs.text("COVER_MISSING", GetResults.coverMissing, words["COVER_MISSING"])
        diffs.text("DISC_ART_BESIDE", GetResults.discArtBeside, words["DISC_ART_BESIDE"])
        diffs.text("NO_DISC_ART", GetResults.noDiscArt, words["NO_DISC_ART"])
        diffs.text("RETIME_POINTER", GetResults.retimePointer, words["RETIME_POINTER"])
        diffs.text("cover", GetResults.cover, words["cover"])
        diffs.text("discArt", GetResults.discArt, words["discArt"])
        diffs.text("lyrics", GetResults.lyrics, words["lyrics"])
        diffs.text("seeCover", GetResults.seeCover, words["seeCover"])
        diffs.text("seeDiscArt", GetResults.seeDiscArt("disc2.png"), words["seeDiscArt"])
        diffs.done()
        #expect(fixture["artwork"]["albums"].list.count == 81)
        #expect(fixture["artwork"]["problems"].list.count == 126)
        expectMadeFrom(fixture, ["ui/src/lib/getResults.ts", "ui/src/lib/lyrics.ts",
                                 "ui/src/components/LibraryParts.tsx the cover button",
                                 "ui/src/components/LibraryParts.tsx a 404 is none"])
    }

    @Test func eachFolderSaysWhatTheWebsArtworkAndLyricsTabsSay() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["artwork"]["albums"].list.enumerated() {
            let album = Self.album(row["album"])
            diffs.text("\(at) coverNote", GetResults.coverNote(album.art), row["coverNote"])
            diffs.text("\(at) coverPointer", GetResults.webCoverPointer(album), row["coverPointer"])
            diffs.text("\(at) discArtPointer", GetResults.webDiscArtPointer(album), row["discArtPointer"])
            diffs.text("\(at) lyricsLine", GetResults.lyricsLine(album.lyricsCount, album.trackCount), row["lyricsLine"])
            diffs.text("\(at) allLyricsNote", GetResults.allLyricsNote(album), row["allLyricsNote"])
            diffs.flag("\(at) offersCover", GetResults.offersCover(album), row["offersCover"])
            diffs.flag("\(at) hasOwnDiscArt", GetResults.hasOwnDiscArt(album), row["hasOwnDiscArt"])
            diffs.flag("\(at) offersDiscArt", GetResults.offersDiscArt(album), row["offersDiscArt"])
            for (ran, web) in zip([false, true], row["offersLyrics"].list) {
                diffs.flag("\(at) offersLyrics \(ran)", GetResults.offersLyrics(album, ran: ran), web)
            }
            // on the phone: the Release page, and its Compare covers…
            if let web = row["coverPointer"].string {
                diffs.check("\(at) phone cover", GetResults.coverPointer(album) ?? "",
                            web.replacingOccurrences(of: "in the Release tab (Compare full size\u{2026})",
                                                     with: "on the Release page (Compare covers\u{2026})")
                                .replacingOccurrences(of: "in the Release tab", with: "on the Release page"))
            }
        }
        diffs.done()
        let tagged = ScanAlbum(path: "A", releaseMbid: "x", art: "file")
        #expect(GetResults.coverPointer(tagged) == "To replace it, compare it with the release's on the Release page (Compare covers\u{2026}).")
        #expect(GetResults.discArtPointer(ScanAlbum(path: "A")) == "To get CD art, first match the album to a release on the Release page.")
    }

    @Test func aGetThatDidntWorkIsSaidAsTheWebSaysIt() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["artwork"]["problems"].list.enumerated() {
            let kind = GetResults.Kind(rawValue: row["kind"].string!)!
            diffs.text("\(at) \(kind) admin \(row["admin"])",
                       GetResults.problem(Self.failure(row["error"]), kind, admin: row["admin"].bool!), row["said"])
        }
        diffs.done()
    }

    @Test func whatGetLyricsCameToIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["artwork"]["summaries"].list.enumerated() {
            let summary = Self.summary(row["summary"])
            diffs.text("\(at) described", GetResults.describeLyrics(summary), row["described"])
            diffs.text("\(at) result", GetResults.lyricsResult(summary), row["result"])
            diffs.check("\(at) on disk", GetResults.lyricsOnDisk(summary), row["onDisk"].int!)
        }
        diffs.done()
    }

    @Test func eachButtonSaysWhatTheWebsSays() {
        let diffs = ScreenDiffs()
        let refused = APIFailure.answered(.init(status: 400, method: "POST", path: "/x", detail: "no"))
        let missing = APIFailure.answered(.init(status: 404, method: "POST", path: "/x", detail: "none"))
        for row in fixture["artwork"]["labels"].list {
            let kind = GetResults.Kind(rawValue: row["kind"].string!)!
            let tracks = row["tracks"].int!
            var run = GetRun(kind: kind, path: "A")
            switch row["state"].string! {
            case "working": break
            case "none": run.failed(missing, admin: false)
            case "failed": run.failed(refused, admin: false)
            case "done": run.done(Self.summary(row["summary"]))
            default:
                diffs.text("\(kind) idle \(tracks)", GetResults.label(kind, nil, trackCount: tracks), row["label"])
                continue
            }
            diffs.text("\(kind) \(row["state"]) \(tracks)", GetResults.label(kind, run, trackCount: tracks), row["label"])
        }
        diffs.done()
        // the phone's own: an answer that never came, or a 5xx, is Try again too - and the folder is read again
        var lost = GetRun(kind: .cover, path: "A")
        lost.failed(APIFailure.answered(.init(status: 502, method: "POST", path: "/x", detail: "the Cover Art Archive couldn't be reached - try again")), admin: false)
        #expect(lost.state == .unanswered && lost.wrote && GetResults.label(.cover, lost, trackCount: 1) == "Try again")
        #expect(lost.said?.hasPrefix("The Cover Art Archive couldn't be reached - try again.") == true, "the route's words")
        var none = GetRun(kind: .disc, path: "A")
        none.failed(missing, admin: false)
        #expect(none.state == .none && !none.wrote)
        var lyrics = GetRun(kind: .lyrics, path: "A")
        lyrics.failed(missing, admin: false)
        #expect(lyrics.state == .failed && !lyrics.wrote, "a lyrics fetch has no 404 of its own: the web's failed")
        var cover = GetRun(kind: .cover, path: "A")
        cover.done()
        #expect(cover.wrote && cover.said == nil && GetResults.label(.cover, cover, trackCount: 1) == "Get cover")
    }

    // MARK: Delete album (slice 4)

    static func deletion(_ web: Web) -> DeletionSummary {
        EditVectorTests.decoded(DeletionSummary.self, web)
    }

    @Test func theDeleteWordsAreTheWebs() {
        let words = fixture["delete"]["words"]
        let diffs = ScreenDiffs()
        diffs.text("DELETE_TITLE", DeleteWords.title, words["DELETE_TITLE"])
        diffs.text("DELETE_CHECKING", DeleteWords.checking, words["DELETE_CHECKING"])
        diffs.text("DELETE_READ_FAILED", DeleteWords.readFailed, words["DELETE_READ_FAILED"])
        diffs.text("DELETE_FAILED", DeleteWords.failed, words["DELETE_FAILED"])
        diffs.text("DELETE_WARNING", DeleteWords.warning, words["DELETE_WARNING"])
        diffs.text("DELETE_CONFIRM", DeleteWords.confirm, words["DELETE_CONFIRM"])
        diffs.text("DELETING", DeleteWords.deleting, words["DELETING"])
        diffs.text("Cancel", DeleteWords.cancel, words["cancel"])
        diffs.text("deleted", DeleteWords.deleted("Portishead/Dummy (1994)"), words["deleted"])
        diffs.done()
        expectMadeFrom(fixture, ["ui/src/lib/myLibrary.ts", "ui/src/components/DeleteAlbumDialog.tsx the Cancel button",
                                 "ui/src/components/DeleteAlbumDialog.tsx the button off until the summary"])
    }

    @Test func whatGoesAndWhoHoldsItAreSaidAsTheWebSaysThem() {
        let diffs = ScreenDiffs()
        let rows = fixture["delete"]["summaries"].list
        #expect(rows.count >= 100)
        for (at, row) in rows.enumerated() {
            let summary = Self.deletion(row["summary"])
            diffs.text("\(at) counts", DeleteWords.counts(summary), row["counts"])
            let others = DeleteWords.others(summary)
            diffs.text("\(at) others lead", others?.lead, row["others"]["lead"])
            diffs.text("\(at) others names", others?.names, row["others"]["names"])
            diffs.text("\(at) holders", DeleteWords.holders(summary), row["holders"])
        }
        diffs.done()
        // unread is never "nobody", whatever else came with it
        let unread = DeletionSummary(audioFiles: 1, holders: [], yours: false, holdersUnknown: true)
        #expect(DeleteWords.holders(unread)?.hasPrefix("deadwax couldn't read who has it") == true)
        #expect(DeleteWords.holders(nil) == nil && DeleteWords.holders(DeletionSummary(audioFiles: 1)) == nil)
    }

    @Test func whetherTheAlbumPageGoesBackIsTheWebs() {
        let diffs = ScreenDiffs()
        let rows = fixture["delete"]["deletesAll"].list
        #expect(rows.count > 200)
        for (at, row) in rows.enumerated() {
            let folders: AlbumEdit.Folders? = row["folders"].isNull ? nil
                : AlbumEdit.Folders(paths: row["folders"]["paths"].list.compactMap(\.string),
                                    from: AlbumEdit.From(rawValue: row["folders"]["from"].string!)!)
            let subject = AlbumEdit.Subject(id: "al-1", name: "B", songCount: row["songCount"].int)
            diffs.flag("\(at)", AlbumEdit.deletesAll(folders, tracks: row["tracks"].int!, row["folders"].isNull ? nil : subject),
                       row["all"])
        }
        diffs.done()
    }
}
