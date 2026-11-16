import Foundation
import Testing
@testable import DeadwaxCore

/// Delete album (Phase 8, slice 4 - phase8-managing.md 3.6): what is read and sent - the web's very asks - what the
/// answers read as, and the page's state: only the newest summary lands, Delete permanently is on only with this
/// folder's summary in hand and nothing under way, a refusal deleted nothing and says why, and no answer (or a 5xx)
/// may have deleted it - said as maybe, until the folder's next read says whether it went.
@Suite struct DeleteAlbumTests {
    @Test func theSummaryIsAskedForTheFolderAndTheDeleteSendsTheWebsBody() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/deletion_summary", 200,
                         #"{"audio_files": 12, "total_bytes": 314572800, "other_files": ["rip.log", "album.cue"], "other_file_count": 2, "holders": ["ana"], "yours": true}"#)
        let summary = try await deadwax.deletionSummary(path: "Portishead/Dummy (1994)")
        #expect(summary == DeletionSummary(audioFiles: 12, totalBytes: 314_572_800, otherFiles: ["rip.log", "album.cue"],
                                           otherFileCount: 2, holders: ["ana"], yours: true))
        #expect(transport.last?.method == "GET" && transport.last?.url.path == "/deadwax/library/deletion_summary")
        let query = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.map(\.name) == ["album"] && query.map(\.value) == ["Portishead/Dummy (1994)"])
        #expect(transport.last?.timeout == 60)
        #expect(DeleteWords.counts(summary) == "12 tracks \u{b7} 300 MB")
        #expect(DeleteWords.others(summary)?.lead == "and 2 other files:")
        #expect(DeleteWords.others(summary)?.names == "rip.log, album.cue")
        #expect(DeleteWords.holders(summary)
                == "In your library and ana's: deleting it takes it out, and ana will see it was removed by an admin.")

        transport.answer("/deadwax/library/delete", 200, #"{"deleted": true, "path": "Portishead/Dummy (1994)"}"#)
        #expect(try await deadwax.deleteAlbum(path: "Portishead/Dummy (1994)") == AlbumDeleted(deleted: true))
        #expect(transport.last?.method == "POST" && transport.last?.url.path == "/deadwax/library/delete")
        #expect(try sentJSON(transport.last) == ["album_path": .string("Portishead/Dummy (1994)")],
                "DeleteRequest's one field - what the web's libraryApi.deleteAlbum sends")
        #expect(transport.last?.headers["Origin"] == nil && transport.last?.headers["Referer"] == nil)
        #expect(transport.last?.timeout == 120)
    }

    @Test func aRefusalIsSaidInDeadwaxsWordsAndDeletedNothing() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/delete", 400, #"{"detail": "that folder holds no audio, so it isn't an album"}"#)
        do {
            _ = try await deadwax.deleteAlbum(path: "A/B")
            Issue.record("a 400 is thrown")
        } catch {
            #expect(RetagFlow.outcome(of: error) == .refused)
            #expect(EditWords.writeFailure(error, failed: DeleteWords.failed, admin: false)
                    == "That folder holds no audio, so it isn't an album.")
            var flow = DeleteFlow()
            let ticket = flow.beginRead("A/B")
            flow.read(ticket, DeletionSummary(audioFiles: 1))
            let started = flow.beginDelete("A/B")
            #expect(started)
            flow.deleteEnded(.refused, said: EditWords.writeFailure(error, failed: DeleteWords.failed, admin: false))
            #expect(!flow.deleting && !flow.mayHaveFinished)
            #expect(flow.failure == "That folder holds no audio, so it isn't an album.")
            #expect(flow.canDelete("A/B"), "a refusal changed nothing: it can be tried again")
        }

        transport.answer("/deadwax/library/deletion_summary", 400, #"{"detail": "that album is not inside the library"}"#)
        do {
            _ = try await deadwax.deletionSummary(path: "../B")
            Issue.record("a 400 is thrown")
        } catch {
            #expect(EditWords.said(error, failed: DeleteWords.readFailed, admin: false)
                    == "That album is not inside the library.")
        }
    }

    @Test func anAnswerMissingItsFieldsIsReadAsNothingAndUnreadHoldersStayUnread() throws {
        let bare = try JSONDecoder().decode(DeletionSummary.self, from: Data(#"{"audio_files": "3", "other_files": null}"#.utf8))
        #expect(bare == DeletionSummary(audioFiles: 0))
        #expect(DeleteWords.holders(bare) == nil, "logins off: nobody to name")
        let unread = try JSONDecoder().decode(DeletionSummary.self,
                                              from: Data(#"{"audio_files": 3, "total_bytes": 0, "holders_unknown": true}"#.utf8))
        #expect(unread.holdersUnknown && unread.holders == nil)
        #expect(DeleteWords.holders(unread)?.contains("couldn't read who has it") == true)
        #expect(DeleteWords.counts(unread) == "3 tracks", "no size for nothing")
        let nobody = DeletionSummary(audioFiles: 1, totalBytes: 2_097_152, holders: [], yours: false)
        #expect(DeleteWords.holders(nobody) == "Nobody has it in their library.")
        #expect(DeleteWords.counts(nobody) == "1 track \u{b7} 2 MB")
        let many = DeletionSummary(audioFiles: 2, otherFiles: Array(repeating: "x", count: 12), otherFileCount: 40)
        #expect(DeleteWords.others(many)?.lead == "and 40 other files:")
        #expect(DeleteWords.others(many)?.names.hasSuffix("x, \u{2026}") == true)
        #expect(DeleteWords.others(DeletionSummary(audioFiles: 2)) == nil)
        let gone = try JSONDecoder().decode(AlbumDeleted.self, from: Data(#"{"deleted": "yes"}"#.utf8))
        #expect(!gone.deleted)
    }

    /// DeleteAlbumDialog's read, and only the newest landing: a summary asked again (Look again, or another folder)
    /// drops the older one's answer, a cancelled read says nothing, and a failed one leaves no summary to delete by.
    @Test func onlyTheNewestSummaryLandsAndNothingIsDeletedWithout() {
        var flow = DeleteFlow()
        #expect(!flow.canDelete("A/B"), "no summary yet")
        let first = flow.beginRead("A/B")
        #expect(flow.reading && !flow.canDelete("A/B"))
        let second = flow.beginRead("A/B")
        let older = flow.read(first, DeletionSummary(audioFiles: 9))
        #expect(!older, "an older read is dropped")
        #expect(flow.summary == nil && flow.reading)
        let newer = flow.read(second, DeletionSummary(audioFiles: 3))
        #expect(newer)
        #expect(flow.summary?.audioFiles == 3 && !flow.reading && flow.canDelete("A/B"))
        #expect(!flow.canDelete("A/C"), "only the folder the summary is for")

        let failing = flow.beginRead("A/B")
        flow.readFailed(failing, said: "Couldn't read that folder. Check deadwax is running.")
        #expect(flow.summary == nil && !flow.reading && flow.readFailure != nil && !flow.canDelete("A/B"))
        let again = flow.beginRead("A/B")
        #expect(flow.readFailure == nil, "Look again clears what failed")
        flow.readCancelled(again)
        #expect(!flow.reading && flow.readFailure == nil && flow.summary == nil, "a cancelled read is neither")

        let other = flow.beginRead("C/D")
        flow.read(other, DeletionSummary(audioFiles: 1))
        #expect(flow.path == "C/D" && flow.canDelete("C/D") && !flow.canDelete("A/B"))
    }

    /// The delete's end, RetagFlow.outcome's rule: gone; refused (said, nothing deleted, it can be tried again); no
    /// answer or a 5xx - maybe gone, until the folder's next read says. Nothing starts while one runs.
    @Test func aDeleteThatNeverAnsweredIsSettledByTheNextRead() throws {
        var flow = DeleteFlow()
        flow.read(flow.beginRead("A/B"), DeletionSummary(audioFiles: 4))
        let started = flow.beginDelete("A/B")
        let twice = flow.beginDelete("A/B")
        #expect(started && flow.deleting && !flow.canDelete("A/B") && !twice, "one delete at a time")

        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        let lost = APIFailure.timeout(.init(server: server, method: "POST", path: "/library/delete",
                                            reason: "The request timed out."))
        #expect(RetagFlow.outcome(of: lost) == .unanswered)
        #expect(EditWords.writeFailure(lost, failed: DeleteWords.failed, admin: false) == nil,
                "no words of deadwax's: the page says it may have finished")
        flow.deleteEnded(.unanswered, said: nil)
        #expect(!flow.deleting && flow.mayHaveFinished && flow.failure == nil)
        flow.settled(gone: false)
        #expect(!flow.mayHaveFinished && flow.failure == DeleteWords.failed, "still there: it didn't go")

        let again = flow.beginDelete("A/B")
        #expect(again)
        let crashed = APIFailure.answered(.init(status: 500, method: "POST", path: "/library/delete",
                                                detail: "Error deleting the album: disk I/O error"))
        let said = EditWords.writeFailure(crashed, failed: DeleteWords.failed, admin: false)
        #expect(RetagFlow.outcome(of: crashed) == .unanswered && said == "Error deleting the album: disk I/O error.")
        flow.deleteEnded(.unanswered, said: said)
        #expect(flow.mayHaveFinished && flow.failure == said, "a 5xx after the folder went (the index's write) may have")
        flow.settled(gone: true)
        #expect(!flow.mayHaveFinished && flow.failure == nil, "gone: it went")

        var plain = DeleteFlow()
        plain.read(plain.beginRead("A/B"), DeletionSummary(audioFiles: 4))
        let plainStarted = plain.beginDelete("A/B")
        #expect(plainStarted)
        plain.deleteEnded(.applied, said: nil)
        #expect(!plain.deleting && plain.failure == nil && !plain.mayHaveFinished)
    }

    /// deletesAll: the album page goes back only when the folder was all Navidrome's album had.
    @Test func theAlbumPageGoesBackOnlyWhenNothingOfItIsLeft() {
        let album = AlbumEdit.Subject(id: "al-1", name: "Dummy", songCount: 11)
        #expect(AlbumEdit.deletesAll(nil, tracks: 11, album))
        #expect(AlbumEdit.deletesAll(AlbumEdit.Folders(paths: ["A/B"], from: .store), tracks: 3, album))
        let two = ["A/Dummy (1994)", "A/Dummy (1994) [Deluxe]"]
        #expect(!AlbumEdit.deletesAll(AlbumEdit.Folders(paths: two, from: .release), tracks: 11, album),
                "one pressing of several: the album stays")
        #expect(AlbumEdit.deletesAll(AlbumEdit.Folders(paths: two, from: .name), tracks: 11, album))
        #expect(!AlbumEdit.deletesAll(AlbumEdit.Folders(paths: two, from: .name), tracks: 10, album))
        #expect(!AlbumEdit.deletesAll(AlbumEdit.Folders(paths: two, from: .name), tracks: 11,
                                      AlbumEdit.Subject(id: "al-1", name: "Dummy")), "no song count: it stays")
    }

    /// What settles a delete that never answered: the next scan that read the library - one that couldn't (its
    /// `problem`, no albums listed) says nothing either way, and the delete stays maybe finished.
    @Test func onlyAScanThatReadTheLibrarySaysWhetherItWent() {
        let listed = ScanAnswer(albums: [ScanAlbum(path: "A/B"), ScanAlbum(path: "A/C")])
        #expect(DeleteFlow.went(listed, path: "A/B") == false)
        #expect(DeleteFlow.went(listed, path: "A/D") == true)
        #expect(DeleteFlow.went(ScanAnswer(albums: [], problem: "LIBRARY_PATH is not set"), path: "A/B") == nil)
        #expect(DeleteFlow.went(ScanAnswer(albums: [], problem: ""), path: "A/B") == true)
    }
}
