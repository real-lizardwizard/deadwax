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
}
