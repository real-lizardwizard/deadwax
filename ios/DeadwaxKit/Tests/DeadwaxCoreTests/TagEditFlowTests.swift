import Foundation
import Testing
@testable import DeadwaxCore

/// Tags' rules (Phase 8, slice 2 - phase8-managing.md 2 and 3.4): RetagFlow's for a tag edit - only the newest preview
/// draws, Apply is on only for a current preview that changes something with no problem on either side, an apply that
/// never answered (or answered a 5xx) is said as maybe finished and the files read again before Apply comes back, a
/// refusal writes nothing - and Tags' routes as the phone asks them.
@Suite struct TagEditFlowTests {
    static let plan = TagEditPlan(albumPath: "A/B", source: "/music/A/B",
                                  files: [TagEditFile(filename: "01.flac", changes: [TagChange(tag: "genre", from: "", to: "Rock")])],
                                  fileCount: 2, changedFileCount: 1, problems: [], empty: false)
    static let empty = TagEditPlan(albumPath: "A/B", source: "/music/A/B", files: [], fileCount: 2, changedFileCount: 0,
                                   problems: [], empty: true)
    static let refused = TagEditPlan(albumPath: "A/B", source: "/music/A/B", files: [], fileCount: 2, changedFileCount: 2,
                                     problems: ["05.flac is not an audio file in this album"], empty: false)

    static func take(_ flow: inout RetagFlow, _ call: (inout RetagFlow) -> Bool) -> Bool { call(&flow) }

    static func previewed() -> RetagFlow {
        var flow = RetagFlow()
        let edit = flow.changed()
        #expect(flow.due(edit))
        #expect(Self.take(&flow) { $0.answered(edit) })
        return flow
    }

    @Test func applyIsOnOnlyForACurrentPreviewThatChangesSomethingWithNoProblem() {
        var flow = Self.previewed()
        #expect(flow.canApply(Self.plan, problems: 0))
        #expect(!flow.canApply(nil, problems: 0), "no preview, no Apply")
        #expect(!flow.canApply(Self.empty, problems: 0), "nothing to change")
        #expect(!flow.canApply(Self.refused, problems: 0), "the plan's problems refuse the whole batch, as the server does")
        #expect(!flow.canApply(Self.plan, problems: 1), "a field wrong as typed")
        // typing again: the preview in hand no longer describes what Apply would send
        let next = flow.changed()
        #expect(!flow.canApply(Self.plan, problems: 0))
        #expect(Self.take(&flow) { $0.answered(next) })
        #expect(flow.canApply(Self.plan, problems: 0))
        // out of reach: off; back: off until the files are read again and previewed
        flow.wentAway()
        #expect(!flow.canApply(Self.plan, problems: 0))
        flow.cameBack()
        #expect(!flow.canApply(Self.plan, problems: 0) && flow.needsRead)
        flow.read()
        #expect(!flow.canApply(Self.plan, problems: 0), "the read is an edit: its preview first")
        let reread = flow.edits
        #expect(Self.take(&flow) { $0.answered(reread) })
        #expect(flow.canApply(Self.plan, problems: 0))
    }

    @Test func nothingTypedIsAnAnswerOfItsOwn() {
        // the editor asks no preview with nothing typed over or a field wrong (TrackTagEditor's effect): it answers the
        // edit with no plan, so nothing spins and Apply stays off
        var flow = RetagFlow()
        let edit = flow.changed()
        #expect(flow.planning)
        #expect(Self.take(&flow) { $0.answered(edit) })
        #expect(!flow.planning && !flow.canApply(nil, problems: 0))
    }

    @Test func anApplyWithNoAnswerIsSaidAndReadAgainBeforeAnythingIsOffered() {
        var flow = Self.previewed()
        #expect(Self.take(&flow) { $0.beginApply(Self.plan, problems: 0) })
        #expect(!Self.take(&flow) { $0.beginApply(Self.plan, problems: 0) }, "never two at once")
        #expect(!flow.planning && !flow.canApply(Self.plan, problems: 0))
        flow.applyEnded(.unanswered)
        #expect(flow.mayHaveFinished && flow.needsRead)
        #expect(!flow.canApply(Self.plan, problems: 0), "never the same Apply on the old preview")
        #expect(!flow.due(flow.edits), "no preview of the files as they were")
        // the read failed: said with Look again, nothing planning, nothing offered
        flow.couldNotRead()
        #expect(flow.readFailed && !flow.planning && !flow.canApply(Self.plan, problems: 0))
        flow.read()
        #expect(!flow.mayHaveFinished && !flow.readFailed && flow.due(flow.edits))
    }

    @Test func aRefusalWroteNothingAndAnAnswerIsReadAgain() {
        var flow = Self.previewed()
        #expect(Self.take(&flow) { $0.beginApply(Self.plan, problems: 0) })
        flow.applyEnded(.refused)
        #expect(!flow.needsRead && !flow.mayHaveFinished && flow.canApply(Self.plan, problems: 0),
                "a 4xx wrote nothing: the preview in hand still describes the files")
        #expect(Self.take(&flow) { $0.beginApply(Self.plan, problems: 0) })
        flow.applyEnded(.applied)
        #expect(flow.needsRead && !flow.mayHaveFinished && !flow.canApply(Self.plan, problems: 0))
        // a 5xx: deadwax may have written - maybe finished
        let failure = APIFailure.answered(.init(status: 500, method: "POST", path: "/deadwax/library/tags/apply",
                                                detail: "Error editing the tags: disk full"))
        #expect(RetagFlow.outcome(of: failure) == .unanswered)
        let bad = APIFailure.answered(.init(status: 400, method: "POST", path: "/deadwax/library/tags/apply",
                                            detail: "05.flac is not an audio file in this album"))
        #expect(RetagFlow.outcome(of: bad) == .refused)
        #expect(EditWords.writeFailure(bad, failed: TagEditWords.applyFailed, admin: false)
                == "05.flac is not an audio file in this album.")
        #expect(EditWords.writeFailure(failure, failed: TagEditWords.applyFailed, admin: false)
                == "Error editing the tags: disk full.")
        #expect(EditWords.writeFailure(APIFailure.other("timed out"), failed: TagEditWords.applyFailed, admin: false) == nil,
                "no answer: the line over the page says it may have finished")
    }

    @Test func aWriteBesideItWaitsForTheRead() {
        // Release applied beside Tags (or a tag edit beside Release): the preview in hand describes the files as they
        // were - nothing offered, nothing previewed, until the folder is read again; and no "may have finished" here,
        // which is the writer's page's to say
        var flow = Self.previewed()
        flow.folderChanged()
        #expect(flow.needsRead && !flow.mayHaveFinished && !flow.canApply(Self.plan, problems: 0))
        #expect(!flow.due(flow.edits) && !flow.current)
        flow.read()
        let reread = flow.edits
        #expect(flow.due(reread))
        #expect(Self.take(&flow) { $0.answered(reread) })
        #expect(flow.canApply(Self.plan, problems: 0))
    }

    // MARK: the routes, as the phone asks them

    @Test func theTagRoutesAreAskedAsTheServerTakesThem() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/tags/preview", 200, #"""
            {"album_path": "A/B", "source": "/music/A/B", "files": [
              {"filename": "01.flac", "changes": {"genre": {"from": "", "to": "Rock"}, "title": {"from": "One", "to": "Uno"},
                                                   "conductor": {"from": "x", "to": ""}}},
              {"filename": "02.flac", "changes": {}}],
             "file_count": 2, "changed_file_count": 1, "problems": [], "empty": false}
            """#)
        let body = TagEditBody(albumPath: "A/B", edits: TagEdit.edits(filenames: ["01.flac", "02.flac"],
                                                                      draft: ["genre": " Rock ", "title": "Uno"]))
        let plan = try await deadwax.tagsPreview(body)
        #expect(transport.last?.method == "POST")
        let sent = try sentJSON(transport.last)
        #expect(Set(sent.keys) == ["album_path", "edits"])
        #expect(sent["edits"] == .list([
            .object(["filename": .string("01.flac"), "tags": .object(["genre": .string("Rock"), "title": .string("Uno")])]),
            .object(["filename": .string("02.flac"), "tags": .object(["genre": .string("Rock"), "title": .string("Uno")])]),
        ]))
        // the form's order: Title before Genre; a tag the form doesn't offer after them
        #expect(plan.changed.map(\.filename) == ["01.flac"])
        #expect(plan.files[0].changes.map(\.tag) == ["title", "genre", "conductor"])
        #expect(TagEditWords.wouldChange(plan) == "1 of 2 files would change")

        transport.answer("/deadwax/library/tags/apply", 200, #"""
            {"plan": {"album_path": "A/B", "source": "/music/A/B", "files": [], "file_count": 2, "changed_file_count": 1,
                      "problems": [], "empty": false},
             "results": {"mode": "apply", "dry_run": false, "written": 1, "failed": 0,
                         "problems": ["originaldate can't be written to 01.flac"]}}
            """#)
        let response = try await deadwax.tagsApply(body)
        #expect(try sentJSON(transport.last) == sent, "Apply sends the preview's very body; the server works it out again")
        let saved = TagEditWords.saved(response.results, filenames: ["01.flac", "02.flac"])
        #expect(saved.text == "Saved 1 file. Originaldate can't be written to 01.flac." && !saved.failed)

        transport.answer("/deadwax/library/tracks/picture", 404, #"{"detail": "no such picture"}"#)
        #expect(try await deadwax.trackPicture(path: "A/B", file: "01 & 02.flac", index: 1) == nil)
        #expect(transport.last?.url.path == "/deadwax/library/tracks/picture")
        let query = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.map(\.name) == ["album", "file", "index"])
        #expect(query.map(\.value) == ["A/B", "01 & 02.flac", "1"])
        transport.answer("/deadwax/library/tracks/picture", 200, "JPEG")
        #expect(try await deadwax.trackPicture(path: "A/B", file: "01.flac", index: 0) == Data("JPEG".utf8))
    }

    @Test func aTracksFileReadsEverythingTheRouteSends() throws {
        let json = #"""
            {"album": "A/B", "files": [{"filename": "01.flac", "format": "flac", "size": 31457280, "length": 245.4,
              "bitrate": 1024000, "sample_rate": 44100, "bits_per_sample": 16, "channels": 2, "codec": "FLAC",
              "position": 1, "disc": null, "tags": {"title": "One"}, "raw": [["title", "One"]],
              "pictures": [{"index": 0, "type": 3, "label": "Front cover", "mime": "image/jpeg", "size": 62000,
                            "description": ""}, {"index": "x"}]},
              {"filename": 7}]}
            """#
        let files = try JSONDecoder().decode(AlbumFiles.self, from: Data(json.utf8)).files
        #expect(files.count == 2, "read leniently: a file with an odd field is kept, the field left out")
        let file = files[0]
        #expect(file.filename == "01.flac" && file.format == "flac" && file.size == 31457280 && file.length == 245.4)
        #expect(file.bitrate == 1024000 && file.sampleRate == 44100 && file.bitsPerSample == 16 && file.channels == 2)
        #expect(file.codec == "FLAC" && file.position == 1 && file.disc == nil && file.title == "One")
        #expect(file.pictures.count == 2 && file.pictures[0].label == "Front cover" && file.pictures[0].type == 3)
        #expect(files[1].filename == "" && files[1].title == nil)
        // the track's page says what the web's inspector says
        #expect(TrackInspector.place(file, discs: 1) == "Track 1 · 4:05 · FLAC")
        #expect(TrackInspector.rawTitle(file) == "All tags in this file (1)")
    }
}
