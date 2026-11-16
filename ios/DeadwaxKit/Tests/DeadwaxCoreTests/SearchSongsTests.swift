import Foundation
import Testing
@testable import DeadwaxCore

/// Search's artists and songs from MusicBrainz, and a MusicBrainz artist's page (Phase 5, slice 3 -
/// notes/ios-specs/phase5-search.md 2.3, 2.4 and 6.3): the three kinds asked by the reading, a song's title-only
/// fallback, the Artists and Songs views' MusicBrainz parts, the album opened from a song, the artist's page, the answers
/// read leniently and the client's four calls. The web's rules themselves are held by SearchSongsVectorTests.
@Suite struct SearchSongsTests {
    static let portisheadMB = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
    static let bethMB = "6c8bcd5c-9a7f-4bd8-9d9e-3c0a1b1c2d3e"
    static let portishead = Artist(id: "ar-p", name: "Portishead", albumCount: 3, musicBrainzId: portisheadMB)
    static let credit = [MBArtistCredit(name: "Portishead", artist: .init(id: portisheadMB, name: "Portishead"))]
    static let beth = MBArtistMatch(mbid: bethMB, name: "Beth Gibbons", country: "GB", type: "Person")
    static let theirs = MBArtistMatch(mbid: portisheadMB, name: "Portishead", country: "GB", type: "Group")
    static let marks = SearchMarks(personal: false, index: OwnedIndex([]))

    static let dummyId = "48140466-cff6-3222-bd55-63c27e43190d"
    static let liveTake = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
    static let sourTimes = "1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e"
    static let cdRelease = "2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f"
    static let lpRelease = "3d4e5f6a-7b8c-4d9e-8f1a-2b3c4d5e6f7a"

    /// A state with `text` typed under the library's artist list (`owned`), its library answered with `results`.
    static func typed(_ text: String, _ results: LibraryResults = LibraryResults(), owned: [String] = ["Portishead"]) -> SearchState {
        var state = SearchState()
        state.ownedArtists = owned
        state.typed(text)
        let token = state.askingLibrary()
        state.libraryAnswered(token, state.query, results)
        return state
    }

    /// A kind view's state: `text` typed under the library's artists, the view chosen, its own search3 answered.
    static func viewing(_ text: String, _ view: SearchView, _ results: LibraryResults = LibraryResults()) throws -> SearchState {
        var state = SearchState()
        state.ownedArtists = ["Portishead"]
        state.typed(text)
        state.choose(view)
        let askedMade = state.askingKind()
        let asked = try #require(askedMade)
        state.kindAnswered(asked.token, results)
        return state
    }

    static func recording(_ id: String, _ title: String, group: ReleaseGroup?, release: String = "r-1") -> MBRecording {
        MBRecording(id: id, title: title, length: 305_000, artistCredit: credit, releases: [
            MBRecordingRelease(id: release, title: group?.title, status: "Official", date: "1994-08-22",
                               artistCredit: credit, releaseGroup: group,
                               media: [MBRecordingMedium(position: 1, format: "CD",
                                                         track: [MBRecordingTrack(id: "t-1", number: "1", title: title,
                                                                                  length: 305_000)])]),
        ])
    }

    // MARK: asking

    @Test func eachKindIsAskedByTheReading() throws {
        // an artist's name alone: their albums and MusicBrainz's artists by the name, no song
        var artist = Self.typed("portishead")
        let artistAsks = artist.askingMusicBrainz(artist.query, view: .all)
        let artistsAsk = try #require(artistAsks.artists)
        #expect(artistAsks.albums != nil && artistAsks.songs == nil)
        #expect(artistsAsk.name == "portishead")
        // a title beside an artist you have: no artist asked (the one named is the library's), the song by them -
        // falling back to the words as one title
        var titled = Self.typed("roads  portishead")
        let titledAsks = titled.askingMusicBrainz(titled.query, view: .all)
        let titledSong = try #require(titledAsks.songs)
        #expect(titledAsks.artists == nil && titledAsks.albums != nil)
        let plan = titledSong.plan
        #expect(plan.kind == .albumByArtist)
        let fielded = SongSearch.fieldedQuery(title: plan.title ?? "", artist: plan.artist ?? "")
        #expect(titledSong.first == fielded && fielded.hasPrefix("recording:"))
        let titleOnly = SongSearch.titleQuery("roads  portishead")
        #expect(titledSong.fallback == titleOnly && titleOnly == "recording:\"roads portishead\"")
        // anything else: all three, the words single-spaced, no fallback for the songs
        var free = Self.typed("glory  box")
        let freeAsks = free.askingMusicBrainz(free.query, view: .all)
        let freeSongs = try #require(freeAsks.songs)
        let freeArtists = try #require(freeAsks.artists)
        #expect(freeAsks.albums != nil)
        #expect(freeSongs.first == "glory box" && freeSongs.fallback == nil && freeArtists.name == "glory box")
        // asked again for the same words: nothing new, everything on its way
        let again = free.askingMusicBrainz(free.query, view: .all)
        #expect(again.isEmpty)
        // a kind view asks its own kind alone
        let songsView = free.askingMusicBrainz(free.query, view: .songs)
        #expect(songsView.isEmpty, "the songs are on their way for the same key")
        let artistsOnly = SearchState.wantedKinds("portishead", artistsAsk.plan, view: .artists)
        #expect(artistsOnly == [.artists])
        let songsOnly = SearchState.wantedKinds("portishead", artistsAsk.plan, view: .songs)
        #expect(songsOnly.isEmpty, "an artist's name alone asks no song")
    }

    @Test func anAnswerKeepsWhatWasAskedAndAnOlderOneIsDropped() throws {
        var state = Self.typed("roads portishead")
        let firstAsks = state.askingMusicBrainz(state.query, view: .all)
        let first = try #require(firstAsks.songs)
        // the words change before the songs answer: the first answer is no longer the newest
        state.typed("sour times portishead")
        let secondAsks = state.askingMusicBrainz(state.query, view: .all)
        let second = try #require(secondAsks.songs)
        #expect(!state.isNewestSongs(first.token) && state.isNewestSongs(second.token))
        let late = state.songsAnswered(first, SongSearchAnswer(recordings: [Self.recording("rec-a", "Roads", group: nil)]),
                                       query: first.first)
        #expect(!late, "an older ask's answer is dropped")
        let lateFailure = state.songsFailed(first, MBFailure.of(APIFailure.answered(.init(status: 503, method: "GET",
                                                                                           path: "/x")), admin: false))
        #expect(!lateFailure)
        // the fielded ask found nothing, so the title alone was asked: the answer says so
        let fallback = try #require(second.fallback)
        let group = ReleaseGroup(id: Self.dummyId, title: "Dummy", firstReleaseDate: "1994-08-22", primaryType: "Album",
                                 secondaryTypes: [], artistCredit: Self.credit)
        let kept = state.songsAnswered(second, SongSearchAnswer(recordings: [Self.recording(Self.liveTake, "Roads", group: group)],
                                                                count: 1), query: fallback)
        #expect(kept && secondAsks.artists == nil)
    }

    // MARK: the kind views

    @Test func theArtistsViewBringsInTheLibrarysArtistOnceAndMusicBrainzsOthersBelow() throws {
        // the library's own search found nobody: Portishead (by MusicBrainz id) is brought in at their place
        var state = try Self.viewing("portishead", .artists)
        let asks = state.askingMusicBrainz("portishead", view: .artists)
        let ask = try #require(asks.artists)
        #expect(asks.albums == nil && asks.songs == nil)
        state.artistsAnswered(ask, ArtistSearchAnswer(matches: [Self.theirs, Self.beth], count: 2))
        let viewMade = state.kindView(artistList: [Self.portishead], marks: Self.marks)
        let view = try #require(viewMade)
        let brought: KindView.Foot = .rows([.artist(Self.portishead), .mbArtist(Self.beth)])
        #expect(view.foot == brought && !view.nothing)
        // the library listed them: not drawn twice
        var listed = try Self.viewing("portishead", .artists, LibraryResults(artists: [Self.portishead]))
        let listedAsks = listed.askingMusicBrainz("portishead", view: .artists)
        let listedAsk = try #require(listedAsks.artists)
        listed.artistsAnswered(listedAsk, ArtistSearchAnswer(matches: [Self.theirs, Self.beth]))
        let listedMade = listed.kindView(artistList: [Self.portishead], marks: Self.marks)
        let listedView = try #require(listedMade)
        let rows: [String] = listedView.libraryRows.map(\.key)
        #expect(rows == ["artist:ar-p"])
        let below: KindView.Foot = .rows([.mbArtist(Self.beth)])
        #expect(listedView.foot == below)
        // MusicBrainz away: its words, and the library's rows still drawn
        var away = try Self.viewing("portishead", .artists, LibraryResults(artists: [Self.portishead]))
        let awayAsks = away.askingMusicBrainz("portishead", view: .artists)
        let awayAsk = try #require(awayAsks.artists)
        let failure = MBFailure.of(APIFailure.answered(.init(status: 503, method: "GET",
                                                             path: "/search_musicbrainz/artists")), admin: false)
        away.artistsFailed(awayAsk, failure)
        let awayMade = away.kindView(artistList: [Self.portishead], marks: Self.marks)
        let awayView = try #require(awayMade)
        #expect(awayView.foot == .failed(failure) && awayView.libraryRows.count == 1)
    }

    @Test func theSongsViewSaysWhatItCannotAskAndWhatItFoundNothingOf() throws {
        // an artist's name alone: a title is needed with it
        let artist = try Self.viewing("portishead", .songs)
        let artistMade = artist.kindView(artistList: [Self.portishead], marks: Self.marks)
        let artistView = try #require(artistMade)
        #expect(artistView.foot == .needATitle)
        #expect(SongSearch.needATitle.contains("\u{201C}roads portishead\u{201D}"))
        // songs found on no album, below the library's song of that name: nothing to get, said
        let glory = Song(id: "s-glory", title: "Glory Box", album: "Dummy", albumId: "nd-dummy", artist: "Portishead",
                         artistId: "ar-p")
        var bare = try Self.viewing("glory box", .songs, LibraryResults(songs: [glory]))
        let bareAsks = bare.askingMusicBrainz("glory box", view: .songs)
        let bareAsk = try #require(bareAsks.songs)
        let noAlbum = SongSearchAnswer(recordings: [Self.recording("rec-b", "Glory Box (demo)", group: nil)])
        bare.songsAnswered(bareAsk, noAlbum, query: bareAsk.first)
        let bareMade = bare.kindView(artistList: [Self.portishead], marks: Self.marks)
        let bareView = try #require(bareMade)
        let noRelease: KindView.Foot = .said(SongSearch.noRelease("glory box"))
        #expect(bareView.foot == noRelease && !bareView.nothing)
        // ...and with nothing in the library either: "No songs for …", as the web's kind view says it
        var none = try Self.viewing("glory box", .songs)
        let noneAsks = none.askingMusicBrainz("glory box", view: .songs)
        let noneAsk = try #require(noneAsks.songs)
        none.songsAnswered(noneAsk, noAlbum, query: noneAsk.first)
        let noneMade = none.kindView(artistList: [Self.portishead], marks: Self.marks)
        let noneView = try #require(noneMade)
        #expect(noneView.foot == nil && noneView.nothing)
        // songs on an album: MusicBrainz's song, below the library's
        var found = try Self.viewing("glory box", .songs)
        let foundAsks = found.askingMusicBrainz("glory box", view: .songs)
        let foundAsk = try #require(foundAsks.songs)
        let group = ReleaseGroup(id: Self.dummyId, title: "Dummy", firstReleaseDate: "1994-08-22", primaryType: "Album",
                                 secondaryTypes: [], artistCredit: Self.credit)
        found.songsAnswered(foundAsk, SongSearchAnswer(recordings: [Self.recording(Self.liveTake, "Glory Box", group: group)]),
                            query: foundAsk.first)
        let foundMade = found.kindView(artistList: [Self.portishead], marks: Self.marks)
        let foundView = try #require(foundMade)
        guard case .rows(let rows)? = foundView.foot, case .mbSong(let song)? = rows.first else {
            Issue.record("a MusicBrainz song below the library's")
            return
        }
        let albums: [String] = song.albums.map(\.id)
        #expect(rows.count == 1 && song.title == "Glory Box" && albums == [Self.dummyId])
        #expect(song.recordings == [Self.liveTake])
    }

    // MARK: the album opened from a song

    static func pressing(_ id: String, _ tracks: [(String, String)], format: String = "CD") -> PageRelease {
        PageRelease(id: id, title: "Dummy", status: "Official", date: "1994-08-22", country: "GB",
                    media: [MBMedium(position: 1, format: format, tracks: tracks.enumerated().map { (pair: (offset: Int, element: (String, String))) -> MBTrack in
                        MBTrack(number: String(pair.offset + 1), position: pair.offset + 1, title: pair.element.1,
                                length: 240_000, recording: MBTrack.Recording(id: pair.element.0, title: pair.element.1))
                    })])
    }

    @Test func theAlbumOpenedFromASongShowsAPressingWithItAndMarksIt() {
        let usual = [("9d0e1f2a-3b4c-4d5e-8f6a-7b8c9d0e1f2a", "Mysterons"), (Self.sourTimes, "Sour Times")]
        let answer = ReleaseGroupAnswer(id: Self.dummyId, releases: [
            Self.pressing("r-cd", usual), Self.pressing("r-lp", usual, format: "12\" Vinyl"),
            Self.pressing("r-live", usual + [(Self.liveTake, "Glory Box (live)")]),
        ])
        // the song only on one pressing: that pressing shown, its track marked
        let live = GroupPage(id: Self.dummyId, answer: answer, preview: nil, index: OwnedIndex([]), picked: nil,
                             personal: false, editors: false, fallbackTitle: "Dummy", song: [Self.liveTake])
        let liveMarks: [Bool] = live.tracks.map(\.song)
        #expect(live.chosenId == "r-live" && liveMarks == [false, false, true])
        // a pressing picked wins over the song's
        let picked = GroupPage(id: Self.dummyId, answer: answer, preview: nil, index: OwnedIndex([]), picked: "r-cd",
                               personal: false, editors: false, fallbackTitle: "Dummy", song: [Self.liveTake])
        let pickedMarks: [Bool] = picked.tracks.map(\.song)
        #expect(picked.chosenId == "r-cd" && pickedMarks == [false, false])
        // the song on the usual pressing: the usual pressing, its track marked
        let usualSong = GroupPage(id: Self.dummyId, answer: answer, preview: nil, index: OwnedIndex([]), picked: nil,
                                  personal: false, editors: false, fallbackTitle: "Dummy", song: [Self.sourTimes])
        let usualMarks: [Bool] = usualSong.tracks.map(\.song)
        #expect(usualSong.chosenId == "r-cd" && usualMarks == [false, true])
        // no song: nothing marked, and the title from Search while it loads
        let plain = GroupPage(id: Self.dummyId, answer: nil, preview: nil, index: nil, picked: nil, personal: false,
                              editors: false, fallbackTitle: "Dummy")
        #expect(plain.title == "Dummy" && plain.tracks.isEmpty)
        // the address's ids: lowercase, each once, MusicBrainz's alone
        let ids = SongSearch.ids("\(Self.liveTake.uppercased()),nope,\(Self.liveTake),\(Self.sourTimes)")
        #expect(ids == [Self.liveTake, Self.sourTimes])
    }

    // MARK: a MusicBrainz artist's page

    @Test func aMusicBrainzArtistsPageListsTheirAlbumsNewestFirstWithWhatIsHeld() {
        let dummy = ReleaseGroup(id: Self.dummyId, title: "Dummy", firstReleaseDate: "1994-08-22", primaryType: "Album",
                                 secondaryTypes: [], artistCredit: Self.credit)
        let third = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e01", title: "Third", firstReleaseDate: "2008-04-28",
                                 primaryType: "Album", secondaryTypes: [], artistCredit: Self.credit)
        let roseland = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03", title: "Roseland NYC Live",
                                    firstReleaseDate: "1998-11-02", primaryType: "Album", secondaryTypes: ["Live"],
                                    artistCredit: Self.credit)
        let undated = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e09", title: "Untitled", primaryType: "Album",
                                   secondaryTypes: [], artistCredit: Self.credit)
        let held = OwnedIndex([
            OwnedAlbum(path: "P/Dummy", artist: "Portishead", album: "Dummy", releaseMbid: Self.cdRelease,
                       releaseGroupMbid: Self.dummyId),
            OwnedAlbum(path: "P/Dummy (LP)", artist: "Portishead", album: "Dummy", releaseMbid: Self.lpRelease,
                       releaseGroupMbid: Self.dummyId, yours: false),
        ])
        let groups = [dummy, undated, third, roseland, dummy]
        let rows = MBArtistPage.rows(groups, index: held)
        let titles: [String] = rows.map(\.title)
        #expect(titles == ["Third", "Roseland NYC Live", "Dummy", "Untitled"], "each once, newest first, the undated last")
        let lines: [String] = rows.map { (row: MBArtistPage.Row) -> String in MBArtistPage.line(row, personal: false) }
        #expect(lines == ["2008 \u{00B7} not in your library", "1998 \u{00B7} Live album \u{00B7} not in your library",
                          "1994 \u{00B7} in your library \u{00B7} 2 pressings", "not in your library"])
        let dummyRow = rows[2]
        #expect(MBArtistPage.asksBridge(dummyRow) && !MBArtistPage.asksBridge(rows[0]))
        let bridged: [String] = dummyRow.releases
        #expect(bridged == [Self.cdRelease, Self.lpRelease] && MBArtistPage.marked(dummyRow, personal: true))
        // held by the collection alone: ticked without a library of your own (ArtistPage.tsx's CheckIcon rule), not with
        let collection = OwnedIndex([OwnedAlbum(path: "P/Third", artist: "Portishead", album: "Third",
                                                releaseGroupMbid: third.id, yours: false)])
        let theirs = MBArtistPage.rows([third], index: collection)
        let ticks: [Bool] = [MBArtistPage.marked(theirs[0], personal: false), MBArtistPage.marked(theirs[0], personal: true)]
        #expect(ticks == [true, false])
        let theirLine = MBArtistPage.line(theirs[0], personal: true)
        #expect(theirLine == "2008 \u{00B7} in the collection")
        // before /library/owned has answered: nothing said of the library, nothing marked, nothing bridged
        let early = MBArtistPage.rows([dummy], index: nil)
        #expect(MBArtistPage.line(early[0], personal: false) == "1994" && !MBArtistPage.marked(early[0], personal: false))
        #expect(!MBArtistPage.asksBridge(early[0]))
        // who they are, in a line
        let facts = MBArtistFacts(name: "Portishead", type: "Group", country: "GB", beginArea: "Bristol", began: "1991")
        #expect(MBArtistPage.factsLine(facts) == "Group \u{00B7} Bristol \u{00B7} since 1991")
        let ended = MBArtistFacts(type: "Group", area: "London", began: "1965-01", endedOn: "2014", ended: true)
        #expect(MBArtistPage.factsLine(ended) == "Group \u{00B7} London \u{00B7} 1965 to 2014")
        #expect(MBArtistPage.factsLine(nil).isEmpty)
        #expect(MBArtistPage.none(studio: true).contains("Studio only") && MBArtistPage.none(studio: false) == "No other albums found.")
    }

    // MARK: the answers and the calls

    @Test func musicBrainzsArtistsSongsAndAnArtistsPageAreReadLeniently() throws {
        let artists = #"{"matches":[{"mbid":"m1","name":"Portishead","matched_as":"Portishead","type":3},"junk",{"name":"no id"}],"count":"2"}"#
        let read = try JSONDecoder().decode(ArtistSearchAnswer.self, from: Data(artists.utf8))
        let names: [String] = read.matches.map(\.name)
        #expect(names == ["Portishead", "no id"] && read.matches[0].type.isEmpty && read.count == nil)
        #expect(read.matches[0].matchedAs == "Portishead" && read.matches[1].mbid.isEmpty)
        let songs = #"{"recordings":[{"id":"rec","title":"Roads","length":"long","releases":[{"id":"r1","release-group":{"id":"g1","title":"Dummy"},"media":[{"position":1,"track":[{"id":"t1","number":"10","title":"Roads","length":305000}]}]},7]},"junk"],"count":1}"#
        let found = try JSONDecoder().decode(SongSearchAnswer.self, from: Data(songs.utf8))
        #expect(found.recordings.count == 1 && found.recordings[0].length == nil && found.count == 1)
        let release = try #require(found.recordings[0].releases.first)
        #expect(found.recordings[0].releases.count == 1 && release.releaseGroup?.id == "g1")
        #expect(release.media.first?.track.first?.number == "10")
        let facts = #"{"mbid":"m1","name":"Portishead","type":"Group","begin_area":"Bristol","began":"1991","ended":"no","ended_on":null}"#
        let who = try JSONDecoder().decode(MBArtistFacts.self, from: Data(facts.utf8))
        #expect(who.beginArea == "Bristol" && who.began == "1991" && !who.ended && who.endedOn.isEmpty)
        let albums = #"{"release-groups":[{"id":"g1","title":"Dummy"},{"title":"no id"}],"truncated":true,"problem":"MusicBrainz went away"}"#
        let discography = try JSONDecoder().decode(DiscographyAnswer.self, from: Data(albums.utf8))
        let ids: [String] = discography.releaseGroups.map(\.id)
        #expect(ids == ["g1"] && discography.truncated && discography.brokenOff)
        let whole = try JSONDecoder().decode(DiscographyAnswer.self, from: Data(#"{"release-groups":[],"problem":""}"#.utf8))
        #expect(!whole.brokenOff && !whole.truncated)
        #expect(try JSONDecoder().decode(SongSearchAnswer.self, from: Data("{}".utf8)) == SongSearchAnswer())
    }

    static func query(_ transport: FakeTransport) -> [String] {
        let url = transport.last?.url
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return items.map { (item: URLQueryItem) -> String in "\(item.name)=\(item.value ?? "")" }
    }

    @Test func theArtistsSongsAndAnArtistsPageAreAskedAsTheWebAsksThem() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/search_musicbrainz/artists", 200, #"{"matches":[{"mbid":"m1","name":"Portishead"}],"count":1}"#)
        let artists = try await deadwax.searchArtists("portishead")
        #expect(artists.matches.count == 1)
        let artistQuery = Self.query(transport)
        #expect(artistQuery == ["name=portishead", "limit=10"])
        #expect(transport.last?.timeout == 20)
        transport.answer("/deadwax/search_musicbrainz/songs", 200, #"{"recordings":[],"count":0}"#)
        let songs = try await deadwax.searchSongs("recording:\"roads\"")
        #expect(songs.recordings.isEmpty)
        let songQuery = Self.query(transport)
        #expect(songQuery == ["query=recording:\"roads\"", "limit=25"])
        #expect(transport.last?.timeout == 20)
        transport.answer("/deadwax/search_musicbrainz/artist", 200, #"{"mbid":"m1","name":"Portishead","type":"Group"}"#)
        let facts = try await deadwax.artistFacts(mbid: Self.portisheadMB)
        #expect(facts.type == "Group")
        let factsQuery = Self.query(transport)
        // one MusicBrainz lookup at its worst, 111.5 s (ArtistWaits.musicBrainz): 120 since the artist tools' review
        #expect(factsQuery == ["mbid=\(Self.portisheadMB)"] && transport.last?.timeout == 120)
        transport.answer("/deadwax/search_musicbrainz/discography", 200, #"{"release-groups":[{"id":"g1"}],"truncated":false,"problem":null}"#)
        let studio = try await deadwax.discography(mbid: Self.portisheadMB, studioOnly: true)
        #expect(studio.releaseGroups.count == 1)
        let studioQuery = Self.query(transport)
        #expect(studioQuery == ["artist_mbid=\(Self.portisheadMB)", "types=album", "studio_only=true"])
        #expect(transport.last?.timeout == 60)
        _ = try await deadwax.discography(mbid: Self.portisheadMB, studioOnly: false)
        let allQuery = Self.query(transport)
        #expect(allQuery == ["artist_mbid=\(Self.portisheadMB)", "types=album"])
        // MusicBrainz away is the route's 503, said as MusicBrainz's
        transport.answer("/deadwax/search_musicbrainz/artist", 503, #"{"detail":"MusicBrainz is unavailable"}"#)
        await #expect(throws: APIFailure.self) { try await deadwax.artistFacts(mbid: Self.portisheadMB) }
    }
}
