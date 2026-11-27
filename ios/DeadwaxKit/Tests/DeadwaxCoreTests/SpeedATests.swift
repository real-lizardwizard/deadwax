import Foundation
import Testing
@testable import DeadwaxCore

/// Speed A - what's asked again (notes/ios.md "Speed A: what's asked again"): the pure parts of its six fixes.
@Suite struct SpeedATests {
    // MARK: fix 1 - covers kept on disk

    @Test func onlyTheCoversAreKeptOnDisk() {
        let (deadwax, _) = client(session: "s")
        // Navidrome's covers at a size, and the Cover Art Archive's fronts through the relay
        #expect(CoverDisk.takes(deadwax.coverRequest(coverID: "al-1_6566", size: 300)))
        #expect(CoverDisk.takes(deadwax.coverRequest(coverID: "a/b c", size: 300)), "an id with a slash is one segment")
        #expect(CoverDisk.takes(deadwax.archiveCoverRequest(ArchiveCoverID(.release, "b84ee12a-09ef-421b-82de-0441a926375b"),
                                                            size: 250)))
        // never the viewer's full size (its own capped read), nor anything else
        #expect(!CoverDisk.takes(deadwax.fullCoverRequest(coverID: "al-1")))
        #expect(!CoverDisk.takes(deadwax.streamRequest(songID: "s1", format: "raw")))
        #expect(!CoverDisk.takes(deadwax.discArtRequest(albumID: "al-1", disc: 1)))
        #expect(!CoverDisk.takes(deadwax.request(Routes.album, path: ["album_id": "al-1"])))
        #expect(!CoverDisk.takes(deadwax.request(Routes.libraryAlbums, query: [("tracks", "false")])))
        #expect(!CoverDisk.takes(deadwax.request(Routes.libraryArt, query: [("album", "A/B")])),
                "a folder's cover is asked by its path: an Edit replaces it under the same address")
        var posted = deadwax.coverRequest(coverID: "al-1", size: 300)
        posted.method = "POST"
        #expect(!CoverDisk.takes(posted))
        // the place and the bound
        #expect(CoverDisk.folder == "deadwax-covers")
        #expect(CoverDisk.diskBytes == 256 * 1024 * 1024)
    }

    @Test func aTemplatesPartsAreEachOneSegment() {
        #expect(CoverDisk.matches("/deadwax/navidrome/cover/al-1", "/deadwax/navidrome/cover/{cover_id}"))
        #expect(!CoverDisk.matches("/deadwax/navidrome/cover/", "/deadwax/navidrome/cover/{cover_id}"))
        #expect(!CoverDisk.matches("/deadwax/navidrome/cover/a/b", "/deadwax/navidrome/cover/{cover_id}"))
        #expect(CoverDisk.matches("/deadwax/coverart/release/x", "/deadwax/coverart/{kind}/{mbid}"))
        #expect(!CoverDisk.matches("/deadwax/coverart/release", "/deadwax/coverart/{kind}/{mbid}"))
    }

    // MARK: fix 2 - an album's answer kept

    private typealias Stamp = KeptAnswers<String>.Stamp

    @Test func anAnswerKeptIsReadUnderTheSameStampAlone() {
        var kept = KeptAnswers<String>(most: KeptAlbums.most)
        let now = Stamp(person: 1, session: 1, writes: 0)
        kept.keep("al-1", "Dummy", stamp: now)
        #expect(kept.answer("al-1", stamp: now) == "Dummy")
        #expect(kept.answer("al-2", stamp: now) == nil)
        // a write deadwax was told of (an Edit's apply, a delete, a re-file) drops everything at the next look
        let written = Stamp(person: 1, session: 1, writes: 1)
        #expect(kept.answer("al-1", stamp: written) == nil)
        #expect(kept.count == 0)
        // and an answer asked before it, landing after, keeps nothing - nor is anything read under the old stamp
        kept.keep("al-1", "Dummy (before the write)", stamp: now)
        #expect(kept.answer("al-1", stamp: written) == nil)
        #expect(kept.answer("al-1", stamp: now) == nil)
        kept.keep("al-1", "Dummy", stamp: written)
        #expect(kept.answer("al-1", stamp: written) == "Dummy")
        // an older ask landing late takes nothing away from what is kept under the newer stamp
        kept.keep("al-2", "Third (before the write)", stamp: now)
        #expect(kept.answer("al-1", stamp: written) == "Dummy")
        #expect(kept.answer("al-2", stamp: written) == nil)
    }

    @Test func anotherPersonNeverReadsTheAnswersOfTheOneBefore() {
        var kept = KeptAnswers<String>(most: KeptAlbums.most)
        let james = Stamp(person: 1, session: 1, writes: 5)
        kept.keep("al-1", "James's", stamp: james)
        // signed out, someone else signed in: the person counter and the pages' session move, the writes start again
        let ethan = Stamp(person: 2, session: 2, writes: 0)
        #expect(kept.answer("al-1", stamp: ethan) == nil)
        // James's ask landing late keeps nothing for Ethan
        kept.keep("al-2", "James's late one", stamp: james)
        #expect(kept.answer("al-2", stamp: ethan) == nil)
        // a sign-in again as the same person is another person to the store too
        kept.keep("al-1", "Ethan's", stamp: ethan)
        #expect(kept.answer("al-1", stamp: Stamp(person: 3, session: 3, writes: 0)) == nil)
    }

    @Test func theOldestKeptGoesPastTheMostAndOneCanBeForgotten() {
        var kept = KeptAnswers<String>(most: 3)
        let now = Stamp(person: 1, session: 1, writes: 0)
        for id in ["a", "b", "c"] { kept.keep(id, id, stamp: now) }
        // kept again moves it to the newest
        kept.keep("a", "a again", stamp: now)
        kept.keep("d", "d", stamp: now)
        #expect(kept.answer("b", stamp: now) == nil)
        #expect(kept.answer("a", stamp: now) == "a again")
        #expect(kept.count == 3)
        kept.forget("a")
        #expect(kept.answer("a", stamp: now) == nil)
        #expect(kept.count == 2)
        #expect(KeptAlbums.most == 40)
    }
}
