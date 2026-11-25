import Testing
@testable import DeadwaxCore

/// Last.fm's words (lastfm.md 3.3, 3.6): the listeners line rounded DOWN at every boundary, the rows' lines, and the
/// spec's sentences as written.
@Suite struct LastfmWordsTests {
    @Test func theListenersLineNeverSaysMoreThanLastfmDid() {
        let said: [(Int?, String?)] = [
            (nil, nil), (0, nil), (-3, nil),
            (1, "1 listener"), (2, "2 listeners"), (850, "850 listeners"), (999, "999 listeners"),
            (1_000, "1K listeners"), (1_001, "1K listeners"), (1_099, "1K listeners"), (1_100, "1.1K listeners"),
            (2_345, "2.3K listeners"), (9_999, "9.9K listeners"), (10_000, "10K listeners"), (10_999, "10K listeners"),
            (230_456, "230K listeners"), (999_999, "999K listeners"),
            (1_000_000, "1M listeners"), (2_345_678, "2.3M listeners"), (2_399_999, "2.3M listeners"),
            (9_999_999, "9.9M listeners"), (10_000_000, "10M listeners"), (23_456_789, "23M listeners"),
            (999_999_999, "999M listeners"),
            (1_000_000_000, "1B listeners"), (1_234_567_890, "1.2B listeners"), (12_345_678_901, "12B listeners"),
        ]
        for (count, words) in said {
            #expect(LastfmWords.listeners(count) == words, "\(String(describing: count))")
        }
    }

    @Test func aSongYouHavesLineIsItsAlbumAndYear() {
        #expect(LastfmWords.albumLine("Currents", year: 2015) == "Currents · 2015")
        #expect(LastfmWords.albumLine("Currents", year: 0) == "Currents")
        #expect(LastfmWords.albumLine("Currents", year: nil) == "Currents")
        #expect(LastfmWords.albumLine(nil, year: 2015) == "2015")
        #expect(LastfmWords.albumLine("", year: nil) == "")
    }

    @Test func theWordsAreTheSpecs() {
        #expect(LastfmWords.topSongs == "Top Songs")
        #expect(LastfmWords.seeAll == "See All")
        #expect(LastfmWords.credit == "From Last.fm")
        #expect(LastfmWords.notInLibrary == "Not in your library")
        #expect(LastfmWords.notFound == "Couldn't find its album on MusicBrainz.")
        #expect(LastfmWords.away == "MusicBrainz isn't answering - try again in a few minutes.")
        #expect(LastfmWords.footOff == "Top songs, similar artists and radio come from Last.fm - add a Last.fm API key in "
            + "Server settings to see them.")
        #expect(LastfmWords.footRefused == "Last.fm refused deadwax's API key - check LASTFM_API_KEY in Server settings. "
            + "It's the API key, not the shared secret.")
        // the button's word is the page it opens: Server settings' own title
        #expect(LastfmWords.serverSettings == "Server settings")
        #expect(LastfmWords.serverSettings == ServerSettings.title)
    }
}
