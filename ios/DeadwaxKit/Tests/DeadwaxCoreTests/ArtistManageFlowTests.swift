import Foundation
import Testing
@testable import DeadwaxCore

/// The artist tools (Phase 8, slice 5 - phase8-managing.md 2 and 4): what is asked and sent - the web's very asks - what
/// deadwax's answers read as, and each sheet's state: only the newest answer lands, Save and Move are on only with a
/// current look in hand and nothing under way, a refusal wrote nothing and says why, and no answer (or a 5xx) may have
/// written - said as maybe, and looked at again before anything is offered.
@Suite struct ArtistManageFlowTests {
    static let ye = "5b11f4ce-a62d-471e-81fc-a69a8278c7da"

    static let previewJSON = #"""
    {"artist": "Ye", "path": "Ye", "folder_problem": null, "album_count": 2, "track_count": 24,
     "total_size": 1300000000, "first_year": "2021", "last_year": "2025", "albums": [],
     "art": {"thumb": "artist.jpg"}, "mbid": "5b11f4ce-a62d-471e-81fc-a69a8278c7da", "mbid_source": "tags",
     "matches": [], "facts": {"mbid": "5b11f4ce-a62d-471e-81fc-a69a8278c7da", "name": "Ye", "disambiguation": "rapper",
     "type": "Person", "aliases": [], "links": [], "members": [], "genres": []},
     "candidates": [
       {"kind": "thumb", "url": "https://assets.fanart.tv/a.jpg", "preview": "https://assets.fanart.tv/a.jpg", "source": "fanart.tv", "label": "Square image"},
       {"kind": "thumb", "url": "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=1000", "preview": "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=600", "source": "Wikimedia Commons", "label": "Photograph"},
       {"kind": "banner", "url": "https://r2.theaudiodb.com/b.jpg", "preview": "https://r2.theaudiodb.com/b.jpg", "source": "TheAudioDB", "label": "Banner"},
       {"kind": "logo", "url": 7}],
     "best": {"thumb": {"kind": "thumb", "url": "https://assets.fanart.tv/a.jpg", "preview": "https://assets.fanart.tv/a.jpg", "source": "fanart.tv", "label": "Square image"},
              "banner": {"kind": "banner", "url": "https://r2.theaudiodb.com/b.jpg", "preview": "https://r2.theaudiodb.com/b.jpg", "source": "TheAudioDB", "label": "Banner"}},
     "kinds": [{"kind": "thumb", "label": "Square image"}, {"kind": "banner", "label": "Banner"}, {"kind": "fanart", "label": "Background"},
               {"kind": "logo", "label": "Logo"}, {"kind": "landscape", "label": "Wide image"}, {"kind": "clearart", "label": "Clear art"}],
     "plan": {"files": []}, "sources": {"fanarttv": true, "theaudiodb": false}, "has_key": true, "problems": []}
    """#

    static var preview: ArtistImagesPreview {
        try! JSONDecoder().decode(ArtistImagesPreview.self, from: Data(previewJSON.utf8))
    }

    // MARK: what is asked and sent

    @Test func theRoutesAreAskedAsTheWebAsksThem() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/artist", 200,
                         #"{"artist": "Kanye West", "path": "Kanye West", "folder_problem": null, "album_count": 3, "track_count": 40, "total_size": 2000000000, "first_year": "2004", "last_year": "2016", "albums": [], "art": {"thumb": "artist.png", "logo": 3}}"#)
        let summary = try #require(try await deadwax.libraryArtist(name: "Kanye West"))
        #expect(summary == ArtistSummary(artist: "Kanye West", path: "Kanye West", albumCount: 3, trackCount: 40,
                                         totalSize: 2_000_000_000, firstYear: "2004", lastYear: "2016",
                                         art: ["thumb": "artist.png"]))
        let asked = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(asked?.map(\.name) == ["name"] && asked?.map(\.value) == ["Kanye West"])
        #expect(transport.last?.timeout == 120)
        transport.answer("/deadwax/library/artist", 404, #"{"detail": "no such artist"}"#)
        #expect(try await deadwax.libraryArtist(name: "Nobody") == nil, "a name with no album: none, not a failure")

        transport.answer("/deadwax/library/artist/images/preview", 200, Self.previewJSON)
        let preview = try await deadwax.artistImagesPreview(ArtistImagesBody(artist: "Ye", artistMbid: nil))
        #expect(preview.mbid == Self.ye && preview.facts?.name == "Ye" && preview.facts?.disambiguation == "rapper")
        #expect(preview.candidates.count == 3, "a candidate with no address is left out")
        #expect(preview.best.keys.sorted() == ["banner", "thumb"])
        #expect(preview.kinds.map(\.label) == ["Square image", "Banner", "Background", "Logo", "Wide image", "Clear art"])
        #expect(preview.fanarttv == true && preview.theaudiodb == false && preview.hasKey)
        #expect(preview.art == ["thumb": "artist.jpg"])
        #expect(try sentJSON(transport.last) == ["artist": .string("Ye"), "choices": .object([:]), "replace": .bool(false)],
                "previewArtistImages' body - no id: the files or a search say who")
        #expect(transport.last?.timeout == 660)
        _ = try await deadwax.artistImagesPreview(ArtistImagesBody(artist: "Ye", artistMbid: nil), commons: 9)
        #expect(transport.last?.timeout == ArtistWaits.imagesPreview(commons: 9) && transport.last?.timeout == 720)

        transport.answer("/deadwax/library/artist/images/apply", 200,
                         #"{"artist": "Ye", "path": "Ye", "results": {"mode": "apply", "dry_run": false, "written": ["artist.jpg"], "skipped": [], "problems": []}, "art": {"thumb": "artist.jpg", "banner": "banner.jpg"}}"#)
        let body = ArtistImagesBody(artist: "Ye", artistMbid: Self.ye, choices: ArtistManage.bestUrls(preview.best),
                                    replace: true)
        let applied = try await deadwax.artistImagesApply(body, commons: ArtistWaits.commons(preview.candidates))
        #expect(applied.results.line == "Saved artist.jpg." && applied.art["banner"] == "banner.jpg")
        let sent = try sentJSON(transport.last)
        #expect(Set(sent.keys) == ["artist", "artist_mbid", "choices", "replace"])
        #expect(sent["artist_mbid"] == .string(Self.ye) && sent["replace"] == .bool(true))
        #expect(sent["choices"] == .object(["thumb": .string("https://assets.fanart.tv/a.jpg"),
                                            "banner": .string("https://r2.theaudiodb.com/b.jpg")]))
        #expect(transport.last?.headers["Origin"] == nil && transport.last?.headers["Referer"] == nil)
        #expect(transport.last?.timeout == ArtistWaits.imagesApply(pictures: 2, commons: 1))

        transport.answer("/deadwax/library/artist/picture", 200, "JPEG")
        #expect(try await deadwax.artistPicture(url: "https://assets.fanart.tv/a.jpg") == Data("JPEG".utf8))
        let picture = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(picture?.map(\.name) == ["url"] && picture?.map(\.value) == ["https://assets.fanart.tv/a.jpg"])
        #expect(transport.last?.timeout == nil, "the transport's own 8 s, over the relay's 7 s deadline")
        #expect(transport.last?.mostBytes == 8 * 1024 * 1024)
        #expect(transport.last?.headers["Accept"] == "image/*")

        transport.answer("/deadwax/library/artist/art", 200, "PNG")
        #expect(try await deadwax.artistArt(folder: "Ye", kind: "thumb") == Data("PNG".utf8))
        let art = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(art?.map(\.name) == ["artist", "kind"] && art?.map(\.value) == ["Ye", "thumb"])
        transport.answer("/deadwax/library/artist/art", 404, #"{"detail": "no such image"}"#)
        #expect(try await deadwax.artistArt(folder: "Ye", kind: "logo") == nil)

        transport.answer("/deadwax/library/artist/search", 200,
                         #"{"query": "Nirvana", "matches": [{"mbid": "5b11f4ce-a62d-471e-81fc-a69a8278c7db", "name": "Nirvana", "disambiguation": "90s US grunge band", "country": "US", "type": "Group", "score": 100, "matched_as": "Nirvana"}, {"name": "no id"}]}"#)
        let found = try await deadwax.artistSearch("Nirvana")
        #expect(found.matches.map(\.name) == ["Nirvana"], "a match with no id is left out")
        #expect(found.matches.first?.line == "90s US grunge band \u{b7} Group \u{b7} US")
        #expect(try sentJSON(transport.last) == ["query": .string("Nirvana")])
        #expect(transport.last?.timeout == 120)

        transport.answer("/deadwax/library/artist/refile/preview", 200,
                         #"{"current_name": "Ye", "to_folder": "Ye", "artist_mbid": "5b11f4ce-a62d-471e-81fc-a69a8278c7da", "moves": [{"album": "Graduation", "path": "Kanye West/Graduation", "target_path": "Ye/Graduation", "files": 13, "retag": [{"filename": "01.flac", "changes": {"albumartist": {"from": "Kanye West", "to": "Ye"}}}]}], "refused": [], "problems": [], "empty": false}"#)
        let plan = try await deadwax.refilePreview(ArtistRefileBody(artist: "Kanye West", artistMbid: Self.ye))
        #expect(plan.moves.map(ArtistManage.moveLine) == ["13 tracks, 1 retagged"] && !plan.empty)
        #expect(try sentJSON(transport.last) == ["artist": .string("Kanye West"), "artist_mbid": .string(Self.ye)])
        #expect(transport.last?.timeout == 480)

        transport.answer("/deadwax/library/artist/refile/apply", 200,
                         #"{"plan": {"current_name": "Ye", "to_folder": "Ye", "moves": [], "refused": [], "problems": [], "empty": true}, "results": {"moved": [{"from": "Kanye West/Graduation", "to": "Ye/Graduation"}], "failed": [], "pictures_moved": ["artist.jpg"], "removed_folders": ["Kanye West"]}}"#)
        let moved = try await deadwax.refileApply(ArtistRefileBody(artist: "Kanye West", artistMbid: Self.ye),
                                                  bytes: 6_000_000_000)
        #expect(moved.results.moved == [.init(from: "Kanye West/Graduation", to: "Ye/Graduation")])
        #expect(try sentJSON(transport.last) == ["artist": .string("Kanye West"), "artist_mbid": .string(Self.ye)],
                "the apply sends the body its preview did")
        #expect(transport.last?.timeout == ArtistWaits.refileApply(bytes: 6_000_000_000))
    }

    @Test func aRefusalIsSaidInDeadwaxsWords() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/artist/images/apply", 400,
                         #"{"detail": "the thumb chosen is not one of this artist's own pictures"}"#)
        do {
            _ = try await deadwax.artistImagesApply(ArtistImagesBody(artist: "Ye", artistMbid: Self.ye,
                                                                     choices: ["thumb": "x"]), commons: 0)
            Issue.record("a 400 is thrown")
        } catch {
            #expect(RetagFlow.outcome(of: error) == .refused)
            #expect(EditWords.writeFailure(error, failed: ArtistManageWords.saveFailed, admin: false)
                    == "The thumb chosen is not one of this artist's own pictures.")
        }
        transport.answer("/deadwax/library/artist/refile/apply", 500, #"{"detail": "Internal Server Error"}"#)
        do {
            _ = try await deadwax.refileApply(ArtistRefileBody(artist: "Kanye West", artistMbid: Self.ye), bytes: 0)
            Issue.record("a 500 is thrown")
        } catch {
            #expect(RetagFlow.outcome(of: error) == .unanswered, "a 5xx may have moved albums")
        }
        transport.answer("/deadwax/library/artist/picture", 502, #"{"detail": "That picture's site won't let deadwax pass it on."}"#)
        do {
            _ = try await deadwax.artistPicture(url: "https://assets.fanart.tv/a.jpg")
            Issue.record("a 502 is thrown")
        } catch {
            #expect(EditWords.said(error, failed: "", admin: false) == "That picture's site won't let deadwax pass it on.")
        }
    }

    @Test func theWaitsAreTheServersWorstCaseAndMore() {
        // a picture fetched for writing is three requests of 40 s through Commons' redirects; the sources 25 s each
        let one = ArtistWaits.scan + ArtistWaits.musicBrainz + 25 * 3 + 120 + ArtistWaits.margin
        #expect(ArtistWaits.imagesApply(pictures: 1, commons: 0) == max(600, (one / 60).rounded(.up) * 60))
        let six = ArtistWaits.scan + ArtistWaits.musicBrainz + 25 * 5 + 6 * 120 + ArtistWaits.margin
        #expect(ArtistWaits.imagesApply(pictures: 6, commons: 2) == (six / 60).rounded(.up) * 60)
        #expect(ArtistWaits.imagesApply(pictures: 6, commons: 2) > ArtistWaits.imagesApply(pictures: 1, commons: 0))
        #expect(ArtistWaits.imagesApply(pictures: 0, commons: -3) >= 600)
        #expect(ArtistWaits.refileApply(bytes: 0) == 600)
        #expect(ArtistWaits.refileApply(bytes: .nan) == 600 && ArtistWaits.refileApply(bytes: -1) == 600)
        // a minute more for each 1.2 GB of the name's albums
        #expect(ArtistWaits.refileApply(bytes: 1_200_000_000) == 660)
        #expect(ArtistWaits.refileApply(bytes: 12_000_000_000) == 1200)
        // one MusicBrainz request at its worst: ten attempts, each the rate limiter's 5 s window and then its longest
        // pause - a 429's 6 s, or a failed connection's 2 s and half a second an attempt (6.5 and 7 at the last two)
        let pauses = (1...10).map { max(6, 3, 2 + 0.5 * Double($0)) }.reduce(0, +)
        #expect(pauses == 61.5 && ArtistWaits.musicBrainzPauses == pauses)
        #expect(ArtistWaits.musicBrainz == 10 * 5 + 61.5)
        // a look: the scan, a search and a lookup, three sources and a width for each Commons picture (five at least)
        let look = ArtistWaits.scan + 2 * ArtistWaits.musicBrainz + 25 * (3 + 5) + ArtistWaits.margin
        #expect(ArtistWaits.imagesPreview(commons: nil) == (look / 60).rounded(.up) * 60)
        #expect(ArtistWaits.imagesPreview(commons: nil) == 660 && ArtistWaits.imagesPreview(commons: 0) == 660)
        #expect(ArtistWaits.imagesPreview(commons: 9) == 720)
        #expect(Routes.timeouts[Routes.artistImagesPreview]! >= look)
        #expect(Routes.timeouts[Routes.artistSearch]! >= ArtistWaits.musicBrainz)
        #expect(Routes.timeouts[Routes.artistFacts]! >= ArtistWaits.musicBrainz)
        #expect(ArtistWaits.commons([
            ArtistImageCandidate(kind: "thumb", url: "https://commons.wikimedia.org/wiki/Special:FilePath/A.jpg?width=1000"),
            ArtistImageCandidate(kind: "fanart", url: "https://commons.wikimedia.org/wiki/Special:FilePath/A.jpg?width=1000"),
            ArtistImageCandidate(kind: "logo", url: "https://commons.wikimedia.org/wiki/Special:FilePath/L.svg?width=2000"),
            ArtistImageCandidate(kind: "thumb", url: "https://assets.fanart.tv/a.jpg"),
        ]) == 2)
    }

    // MARK: Artist images

    @Test func aLookChoosesTheBestAndOnlyTheNewestLands() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        #expect(!flow.canSave && !flow.holdsWork)
        let first = try given(flow.look(mbid: Self.ye, name: "Ye"))
        #expect(flow.loading == "Ye")
        let second = try given(flow.look(mbid: "other", name: "Another Ye"))
        flow.looked(first, Self.preview)
        #expect(flow.preview == nil && flow.loading == "Another Ye", "an older look lands nowhere")
        flow.looked(second, Self.preview)
        #expect(flow.loading == nil && flow.preview == Self.preview)
        #expect(flow.chosen == ["thumb": "https://assets.fanart.tv/a.jpg", "banner": "https://r2.theaudiodb.com/b.jpg"])
        #expect(flow.canSave && !flow.holdsWork && !flow.searchOpen)
        #expect(flow.lastAsked == .init(mbid: "other", name: "Another Ye"), "Look again asks for the artist last asked about")

        // a pick of another of the slot's pictures, and taking one back: unsaved
        flow.toggle(kind: "thumb", url: "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=1000")
        flow.toggle(kind: "banner", url: "https://r2.theaudiodb.com/b.jpg")
        #expect(flow.chosen == ["thumb": "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=1000"])
        #expect(flow.holdsWork && flow.canSave)
        #expect(flow.isChosen(kind: "thumb", url: "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=1000"))
        flow.toggle(kind: "thumb", url: "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=1000")
        #expect(!flow.canSave, "nothing chosen: nothing to save")

        // a look that fails takes the pictures off the screen: Save off until one lands
        let third = try given(flow.look(mbid: Self.ye, name: "Ye"))
        #expect(!flow.canSave, "never while another look is coming")
        flow.lookFailed(third, words: ArtistManageWords.lookFailed)
        #expect(flow.problem == ArtistManageWords.lookFailed && flow.loading == nil && !flow.canSave)
        let fourth = try given(flow.look(mbid: Self.ye, name: "Ye"))
        #expect(flow.problem == nil)
        flow.looked(fourth, Self.preview)
        #expect(flow.chosen.isEmpty && !flow.canSave, "the same artist again: what the person chose (nothing) kept")
        flow.toggle(kind: "thumb", url: "https://assets.fanart.tv/a.jpg")
        #expect(flow.canSave)
    }

    // MARK: after review (16 Nov) - each guard held by a test of its own

    /// Save is off while another look is coming - with everything else that would let it on.
    @Test func saveWaitsForALookUnderWay() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        #expect(flow.canSave && !flow.chosen.isEmpty)
        _ = try given(flow.look(mbid: "5b11f4ce-a62d-471e-81fc-a69a8278c7db", name: "Another Ye"))
        #expect(flow.loading == "Another Ye" && flow.problem == nil && flow.preview?.mbid != nil && !flow.chosen.isEmpty)
        #expect(!flow.canSave, "what Save would write is the last artist's while another's are coming")
    }

    /// Save is off once a look failed - the pictures it would write are off the screen.
    @Test func saveWaitsAfterALookFailed() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        flow.lookFailed(try given(flow.look(mbid: Self.ye, name: "Ye")), words: ArtistManageWords.lookFailed)
        #expect(flow.loading == nil && flow.preview?.mbid != nil && !flow.chosen.isEmpty && flow.problem != nil)
        #expect(!flow.canSave, "nothing is saved that isn't on the screen")
    }

    /// Save sends the id the look answered with - never the one it was asked for.
    @Test func saveSendsTheIdTheLookAnswered() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: nil, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: nil, name: "Ye")), Self.preview)
        #expect(flow.lastAsked.mbid == nil && flow.preview?.mbid == Self.ye, "the files said who")
        let body = try given(flow.beginSave()).body
        #expect(body.artistMbid == Self.ye)
    }

    /// Move is off once a Move is over - with the same names, previews and page as it began.
    @Test func moveIsOffOnceItIsOver() throws {
        let ask = ArtistRefileFlow.Ask(names: ["Kanye West"], mbid: Self.ye, current: "Ye")
        let plans = [Self.plan("Kanye West", moves: [Self.graduation])]
        var flow = ArtistRefileFlow(ask, online: true)
        flow.previewed(try given(flow.preview()).ticket, plans)
        _ = try given(flow.beginMove())
        let over = flow.moveEnded(applied: [], stopped: (.refused, "MusicBrainz could not be reached just now."))
        #expect(!over && flow.outcome != nil)
        #expect(flow.madeFor == flow.ask && ArtistManage.canMove(flow.view) && flow.online && !flow.loading)
        #expect(!flow.canMove, "Done is all that is left - never a second Move on the same look")
    }

    /// A look of the same artist again (a gap, Look again, after a save that may have written) keeps the person's
    /// choices still offered, what they started from and what the last save said; a choice no longer offered is
    /// dropped and said. Another artist starts from the best of each kind.
    @Test func aLookOfTheSameArtistKeepsTheChoicesStillOffered() throws {
        let photo = "https://commons.wikimedia.org/wiki/Special:FilePath/Ye.jpg?width=1000"
        let square = "https://assets.fanart.tv/a.jpg"
        let banner = "https://r2.theaudiodb.com/b.jpg"
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        flow.toggle(kind: "thumb", url: photo)
        flow.toggle(kind: "fanart", url: banner)
        let saving = try given(flow.beginSave())
        flow.saveAnswered(saving.ticket, ArtistImagesApplied(artist: "Ye", path: "Ye",
                                                             results: ArtistImagesResults(written: ["artist.jpg"]),
                                                             art: ["thumb": "artist.jpg"]))
        flow.toggle(kind: "thumb", url: square)
        #expect(flow.holdsWork && flow.saved == "Saved artist.jpg.")

        // a gap: back, the folder looked at again - nothing undone
        flow.wentAway()
        let asked = try given(flow.cameBack().look)
        flow.looked(try given(flow.look(mbid: asked.mbid, name: asked.name)), Self.preview)
        #expect(flow.chosen == ["thumb": square, "banner": banner, "fanart": banner])
        #expect(flow.holdsWork, "an edit not saved is still one: Close still asks")
        #expect(flow.saved == "Saved artist.jpg." && flow.notOffered == nil && flow.canSave)

        // TheAudioDB gone from the sources: its banner, chosen for two slots, is offered no more
        let fewer = ArtistImagesPreview(artist: "Ye", path: "Ye", art: ["thumb": "artist.jpg"], mbid: Self.ye,
                                        facts: Self.preview.facts,
                                        candidates: Self.preview.candidates.filter { $0.url != banner },
                                        best: ["thumb": Self.preview.candidates[0]], kinds: Self.preview.kinds)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), fewer)
        #expect(flow.chosen == ["thumb": square], "only what is still offered is kept")
        #expect(flow.notOffered == "The pictures you chose for the banner and the background aren't offered any more, "
                + "so they won't be saved - choose others.")
        #expect(flow.saved == "Saved artist.jpg." && flow.canSave)
        let saved = try given(flow.beginSave())
        #expect(saved.body.choices == ["thumb": square], "what is drawn is what is sent")
        flow.saveAnswered(saved.ticket, ArtistImagesApplied(artist: "Ye", path: "Ye",
                                                            results: ArtistImagesResults(written: ["artist.jpg"]),
                                                            art: ["thumb": "artist.jpg"]))
        #expect(flow.notOffered == nil && !flow.holdsWork)

        // another artist: the best of each kind, as the web
        let other = ArtistImagesPreview(artist: "Ye", path: "Ye", mbid: "5b11f4ce-a62d-471e-81fc-a69a8278c7db",
                                        candidates: Self.preview.candidates, best: Self.preview.best,
                                        kinds: Self.preview.kinds)
        flow.toggle(kind: "banner", url: banner)
        flow.looked(try given(flow.look(mbid: other.mbid, name: "Another Ye")), other)
        #expect(flow.chosen == ["thumb": square, "banner": banner] && flow.saved == nil && !flow.holdsWork)
    }

    /// A gap while Save runs: no look is sent until it answers - one could land after it with the folder as it was -
    /// and the look it owes is asked then, keeping what Save said.
    @Test func aGapWhileSavingLooksOnceTheSaveIsOver() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        let saving = try given(flow.beginSave())
        flow.wentAway()
        let back = flow.cameBack()
        #expect(back.look == nil && flow.needsRead, "owed, not sent")
        let during = flow.look(mbid: Self.ye, name: "Ye")
        #expect(during == nil && flow.loading == nil)
        let owed = flow.saveAnswered(saving.ticket, ArtistImagesApplied(
            artist: "Ye", path: "Ye", results: ArtistImagesResults(written: ["artist.jpg", "banner.jpg"]),
            art: ["thumb": "artist.jpg", "banner": "banner.jpg"]))
        #expect(owed && flow.saved == "Saved artist.jpg, banner.jpg." && !flow.canSave)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview.with(art: ["thumb": "artist.jpg",
                                                                                           "banner": "banner.jpg"]))
        #expect(flow.saved == "Saved artist.jpg, banner.jpg." && flow.canSave && !flow.needsRead)

        // with no gap, nothing is owed
        let again = try given(flow.beginSave())
        let none = flow.saveAnswered(again.ticket, ArtistImagesApplied(artist: "Ye", path: "Ye",
                                                                       results: ArtistImagesResults(), art: [:]))
        #expect(!none)

        // a refusal during a gap owes the look too; a look that fails after a save that may have written keeps it said
        let refused = try given(flow.beginSave())
        flow.wentAway()
        _ = flow.cameBack()
        let lookAfter = flow.saveFailed(refused.ticket, outcome: .refused, words: "No.")
        #expect(lookAfter)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        let lost = try given(flow.beginSave())
        let maybe = flow.saveFailed(lost.ticket, outcome: .unanswered, words: nil)
        #expect(maybe && flow.mayHaveFinished)
        flow.lookFailed(try given(flow.look(mbid: Self.ye, name: "Ye")), words: ArtistManageWords.lookFailed)
        #expect(flow.mayHaveFinished && flow.needsRead && !flow.canSave, "still said, and still not offered")
    }

    @Test func noIdOpensTheSearchWithItsMatchesAndSaveWaits() throws {
        var flow = ArtistImagesFlow(folder: "Nirvana", mbid: nil, name: "Nirvana", online: true)
        let ticket = try given(flow.look(mbid: nil, name: "Nirvana"))
        let unsettled = ArtistImagesPreview(artist: "Nirvana", path: "Nirvana",
                                            matches: [MBArtistMatch(mbid: Self.ye, name: "Nirvana", disambiguation: "US")],
                                            problems: ["more than one artist in MusicBrainz goes by this name"])
        flow.looked(ticket, unsettled)
        #expect(flow.searchOpen && flow.matches.count == 1 && !flow.canSave)

        // a search typed over another: only the newest lands, and none found is said
        let one = try given(flow.beginSearch("Nirvana"))
        let two = try given(flow.beginSearch("  Nirvana UK "))
        let blank = flow.beginSearch("   ")
        #expect(blank == nil, "nothing typed: nothing asked")
        flow.searched(one, query: "Nirvana", [MBArtistMatch(mbid: "x", name: "x")])
        #expect(flow.searching && flow.matches.count == 1)
        flow.searched(two, query: "  Nirvana UK ", [])
        #expect(!flow.searching && flow.matches.isEmpty && flow.searchNote == "Nothing in MusicBrainz goes by \"Nirvana UK\".")
        let three = try given(flow.beginSearch("Nirvana"))
        flow.searchFailed(three, query: "Nirvana", words: ArtistManageWords.searchFailed)
        #expect(flow.searchNote == ArtistManageWords.searchFailed && flow.searchFailedFor == "Nirvana")
    }

    @Test func noOneFolderSaysWhyAndAsksNothing() {
        var flow = ArtistImagesFlow(folder: nil, mbid: Self.ye, name: "Ye", online: true)
        let none = flow.look(mbid: Self.ye, name: "Ye")
        #expect(none == nil)
        #expect(flow.problem == ArtistManageWords.noFolder && !flow.canSave)
        let back = flow.cameBack()
        #expect(back.look == nil)
    }

    @Test func aSaveSaysWhatItWroteAndTheFolderAsItIsNow() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        flow.replace = true
        #expect(flow.holdsWork, "Replace turned on is an unsaved change")
        let (ticket, body) = try given(flow.beginSave())
        #expect(body == ArtistImagesBody(artist: "Ye", artistMbid: Self.ye, choices: flow.chosen, replace: true))
        let twice = flow.beginSave()
        #expect(flow.saving && !flow.canSave && !flow.holdsWork && twice == nil, "one write at a time")
        flow.toggle(kind: "thumb", url: "elsewhere")
        #expect(flow.chosen == body.choices, "the choices don't move while it saves")
        flow.saveAnswered(ticket, ArtistImagesApplied(artist: "Ye", path: "Ye",
                                                      results: ArtistImagesResults(written: ["artist.jpg", "banner.jpg"]),
                                                      art: ["thumb": "artist.jpg", "banner": "banner.jpg"]))
        #expect(!flow.saving && flow.saved == "Saved artist.jpg, banner.jpg." && flow.wrote == 1)
        #expect(flow.preview?.art == ["thumb": "artist.jpg", "banner": "banner.jpg"])
        #expect(!flow.holdsWork && flow.canSave, "saved: nothing left unsaved")
    }

    @Test func aRefusalWroteNothingAndNoAnswerMayHave() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        let refused = try given(flow.beginSave()).ticket
        let refusedAgain = flow.saveFailed(refused, outcome: .refused,
                                           words: "Which artist this is in MusicBrainz isn't settled.")
        #expect(!refusedAgain)
        #expect(flow.saved == "Which artist this is in MusicBrainz isn't settled." && flow.canSave && flow.wrote == 0)

        let lost = try given(flow.beginSave()).ticket
        let lostAgain = flow.saveFailed(lost, outcome: .unanswered, words: nil)
        #expect(lostAgain, "looked at again")
        #expect(flow.mayHaveFinished && flow.needsRead && !flow.canSave && flow.wrote == 1)
        let again = try given(flow.look(mbid: flow.lastAsked.mbid, name: flow.lastAsked.name))
        #expect(!flow.canSave, "never offered on the old look")
        flow.looked(again, Self.preview.with(art: ["thumb": "artist.jpg", "banner": "banner.jpg"]))
        #expect(!flow.mayHaveFinished && !flow.needsRead && flow.canSave)
        #expect(flow.preview?.art["banner"] == "banner.jpg")
    }

    @Test func outOfReachNothingWritesAndBackItLooksAgain() throws {
        var flow = ArtistImagesFlow(folder: "Ye", mbid: Self.ye, name: "Ye", online: true)
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        let failed = try given(flow.beginSearch("Ye"))
        flow.searchFailed(failed, query: "Ye", words: ArtistManageWords.searchFailed)
        flow.wentAway()
        #expect(!flow.canSave && flow.preview != nil, "what is drawn stays, nothing writes")
        let away = flow.beginSearch("Ye")
        #expect(away == nil)
        let unseen = flow.look(mbid: Self.ye, name: "Ye")
        #expect(unseen == nil && flow.needsRead)
        let back = flow.cameBack()
        #expect(back.look == .init(mbid: Self.ye, name: "Ye") && back.search == "Ye")
        #expect(!flow.canSave, "nothing is written against an answer from before the gap")
        flow.looked(try given(flow.look(mbid: Self.ye, name: "Ye")), Self.preview)
        #expect(flow.canSave)
    }

    // MARK: Move albums

    /// A mutating call's answer required outside the macro (#require can't call a mutating member).
    func given<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
        try #require(value, sourceLocation: sourceLocation)
    }

    static func plan(_ name: String, moves: [RefileMove], refused: [RefileRefused] = [], problems: [String] = [])
        -> ArtistManage.NamedPlan {
        .init(name: name, plan: ArtistRefilePlan(currentName: "Ye", toFolder: "Ye", artistMbid: ye, moves: moves,
                                                 refused: refused, problems: problems))
    }

    static let graduation = RefileMove(album: "Graduation", path: "Kanye West/Graduation", targetPath: "Ye/Graduation",
                                       files: 13, retag: ["01.flac"])
    static let yeezus = RefileMove(album: "Yeezus", path: "Kanye/Yeezus", targetPath: "Ye/Yeezus", files: 10)

    @Test func theMovesArePreviewedTogetherAndMoveSendsWhatWasShown() throws {
        let ask = ArtistRefileFlow.Ask(names: ["Kanye", "Kanye West"], mbid: Self.ye, current: "Ye")
        var flow = ArtistRefileFlow(ask, online: true)
        #expect(!flow.canMove)
        let first = try given(flow.preview())
        #expect(first.ask == ask && flow.loading)
        let second = try given(flow.preview())
        flow.previewed(first.ticket, [Self.plan("Kanye", moves: [])])
        #expect(flow.plans == nil, "an older preview lands nowhere")
        let plans = [Self.plan("Kanye", moves: [Self.yeezus]),
                     Self.plan("Kanye West", moves: [Self.graduation],
                               refused: [RefileRefused(album: "808s", path: "Kanye West/808s", reason: "already there")])]
        flow.previewed(second.ticket, plans)
        #expect(flow.canMove && flow.view?.moves.count == 2 && flow.view?.refused.count == 1)

        // the page's names changed since: previewed again, never applied blind
        let more = ArtistRefileFlow.Ask(names: ["Kanye", "Kanye West", "kanye west"], mbid: Self.ye, current: "Ye")
        let moved = flow.changed(more)
        #expect(moved && !flow.canMove)
        let same = flow.changed(more)
        #expect(!same, "the same again: nothing to do")
        let third = try given(flow.preview())
        #expect(third.ask == more)
        flow.previewed(third.ticket, plans + [Self.plan("kanye west", moves: [], refused: [
            RefileRefused(album: "Late", path: "kanye west/Late", reason: "a file in it could not be read")])])
        #expect(flow.canMove)

        let applying = try given(flow.beginMove())
        #expect(applying.map(\.name) == ["Kanye", "Kanye West"], "a name with nothing moving isn't asked")
        let twice = flow.beginMove()
        #expect(!flow.canMove && twice == nil, "one write at a time")
        let meanwhile = flow.changed(ask)
        #expect(!meanwhile, "nothing previews again while a Move is under way")
        let done = [
            ArtistManage.AppliedName(name: "Kanye", plan: plans[0].plan,
                                     results: ArtistRefileResults(moved: [.init(from: "Kanye/Yeezus", to: "Ye/Yeezus")],
                                                                  removedFolders: ["Kanye"])),
            ArtistManage.AppliedName(name: "Kanye West", plan: plans[1].plan,
                                     results: ArtistRefileResults(moved: [.init(from: "Kanye West/Graduation",
                                                                                to: "Ye/Graduation")])),
        ]
        let again = flow.moveEnded(applied: done, stopped: nil)
        #expect(!again)
        #expect(flow.outcome?.text == "Moved 2 albums into Ye/. Kanye/ was left empty and removed.")
        #expect(flow.outcome?.emptied == ["Kanye"] && flow.outcome?.failures == [] && flow.wrote == 1)
        let back = flow.cameBack()
        #expect(!flow.canMove && !back, "done: Done is all that is left")
    }

    @Test func aRefusalStopsTheRestAndNoAnswerLooksAgain() throws {
        let ask = ArtistRefileFlow.Ask(names: ["Kanye", "Kanye West"], mbid: Self.ye, current: "Ye")
        let plans = [Self.plan("Kanye", moves: [Self.yeezus]), Self.plan("Kanye West", moves: [Self.graduation])]
        var flow = ArtistRefileFlow(ask, online: true)
        flow.previewed(try given(flow.preview()).ticket, plans)
        _ = try given(flow.beginMove())
        let first = ArtistManage.AppliedName(name: "Kanye", plan: plans[0].plan,
                                             results: ArtistRefileResults(moved: [.init(from: "Kanye/Yeezus", to: "Ye/Yeezus")]))
        let refused = flow.moveEnded(applied: [first], stopped: (.refused, "MusicBrainz could not be reached just now."))
        #expect(!refused)
        #expect(flow.outcome?.text == "Moved 1 album into Ye/.")
        #expect(flow.outcome?.failures == ["MusicBrainz could not be reached just now."])
        #expect(flow.wrote == 1)

        var lost = ArtistRefileFlow(ask, online: true)
        lost.previewed(try given(lost.preview()).ticket, plans)
        _ = try given(lost.beginMove())
        let unanswered = lost.moveEnded(applied: [first], stopped: (.unanswered, nil))
        #expect(unanswered, "previewed again")
        #expect(lost.mayHaveFinished && lost.needsRead && lost.outcome == nil && !lost.canMove)
        #expect(lost.partly == "Moved 1 album into Ye/." && lost.wrote == 1)
        let again = try given(lost.preview())
        lost.previewed(again.ticket, [Self.plan("Kanye", moves: []), Self.plan("Kanye West", moves: [Self.graduation])])
        #expect(!lost.mayHaveFinished && lost.canMove, "what is left to move, offered on a look made since")

        var nothing = ArtistRefileFlow(ask, online: true)
        nothing.previewed(try given(nothing.preview()).ticket, plans)
        _ = try given(nothing.beginMove())
        let unknown = nothing.moveEnded(applied: [], stopped: (.unanswered, nil))
        #expect(unknown)
        #expect(nothing.partly == nil && nothing.wrote == 1, "nothing known to have moved - the page asks again anyway")
    }

    /// A Move whose answer never came, checked: the name deadwax no longer files anything under (its preview a 404)
    /// had finished - said with the outcome, and Done; never a Look again that asks for nothing.
    @Test func aMoveThatNeverAnsweredHadFinished() throws {
        let ask = ArtistRefileFlow.Ask(names: ["Kanye", "Kanye West"], mbid: Self.ye, current: "Ye")
        let plans = [Self.plan("Kanye", moves: [Self.yeezus]), Self.plan("Kanye West", moves: [Self.graduation])]
        let first = ArtistManage.AppliedName(name: "Kanye", plan: plans[0].plan,
                                             results: ArtistRefileResults(moved: [.init(from: "Kanye/Yeezus",
                                                                                        to: "Ye/Yeezus")]))

        // the previews asked again find nothing under Kanye West: a 404
        var gone = ArtistRefileFlow(ask, online: true)
        gone.previewed(try given(gone.preview()).ticket, plans)
        _ = try given(gone.beginMove())
        let lost = gone.moveEnded(applied: [first], stopped: (.unanswered, nil))
        #expect(lost && gone.settling?.name == "Kanye West" && gone.settling?.paths == ["Kanye West/Graduation"])
        // meanwhile the page's names catch up - the subtitle keeps naming what the Move was for
        let page = gone.changed(.init(names: ["Kanye West"], mbid: Self.ye, current: "Ye"))
        #expect(page && gone.shownFor == ask)
        let check = try given(gone.preview())
        #expect(check.ask.names == ["Kanye West"])
        gone.previewed(check.ticket, [], gone: ["Kanye West"])
        #expect(gone.outcome == .init(text: "Moved 1 album into Ye/. deadwax had finished: 1 album from Kanye West "
                                          + "moved into Ye/.", failures: [], moved: 2, emptied: ["Kanye West"]))
        #expect(!gone.mayHaveFinished && gone.settling == nil && !gone.canMove && gone.shownFor == ask)

        // the page's names no longer hold it - no name left to ask about: settled without a request
        var emptied = ArtistRefileFlow(ask, online: true)
        emptied.previewed(try given(emptied.preview()).ticket, plans)
        _ = try given(emptied.beginMove())
        _ = emptied.moveEnded(applied: [first], stopped: (.unanswered, nil))
        let none = emptied.changed(.init(names: [], mbid: Self.ye, current: "Ye"))
        #expect(none)
        let asked = emptied.preview()
        #expect(asked == nil && emptied.outcome?.moved == 2 && !emptied.mayHaveFinished, "Look again did something")
        #expect(emptied.outcome?.text.hasSuffix("deadwax had finished: 1 album from Kanye West moved into Ye/.") == true)

        // every album it was moving is gone from under the name, though the name still holds others that stay
        var moved = ArtistRefileFlow(ask, online: true)
        moved.previewed(try given(moved.preview()).ticket, plans)
        _ = try given(moved.beginMove())
        _ = moved.moveEnded(applied: [first], stopped: (.unanswered, nil))
        moved.previewed(try given(moved.preview()).ticket, [
            Self.plan("Kanye", moves: []),
            Self.plan("Kanye West", moves: [], refused: [RefileRefused(album: "808s", path: "Kanye West/808s",
                                                                       reason: "already there")]),
        ])
        #expect(moved.outcome?.moved == 2 && moved.outcome?.emptied == [] && !moved.canMove)
    }

    /// ...or it hadn't: what had moved said, and the plan for the rest with Move offered again.
    @Test func aMoveThatNeverAnsweredHadNotFinished() throws {
        let ask = ArtistRefileFlow.Ask(names: ["Kanye West"], mbid: Self.ye, current: "Ye")
        let late = RefileMove(album: "Late", path: "Kanye West/Late", targetPath: "Ye/Late", files: 12)
        let plans = [Self.plan("Kanye West", moves: [Self.graduation, late])]

        var none = ArtistRefileFlow(ask, online: true)
        none.previewed(try given(none.preview()).ticket, plans)
        _ = try given(none.beginMove())
        _ = none.moveEnded(applied: [], stopped: (.unanswered, nil))
        none.previewed(try given(none.preview()).ticket, plans)
        #expect(none.settled == "deadwax hadn't moved the albums under Kanye West - they're below, to move again.")
        #expect(none.outcome == nil && !none.mayHaveFinished && none.canMove)

        var half = ArtistRefileFlow(ask, online: true)
        half.previewed(try given(half.preview()).ticket, plans)
        _ = try given(half.beginMove())
        _ = half.moveEnded(applied: [], stopped: (.unanswered, nil))
        // a check that fails first: still said as maybe finished, and Look again asks
        half.previewFailed(try given(half.preview()).ticket, words: ArtistManageWords.previewFailed)
        #expect(half.mayHaveFinished && half.settling != nil && half.error != nil)
        half.previewed(try given(half.preview()).ticket, [Self.plan("Kanye West", moves: [late])])
        #expect(half.settled == "deadwax had moved 1 of the 2 albums under Kanye West - the rest are below, to move "
                + "again.")
        #expect(half.canMove && half.view?.moves == [late])
        let again = try given(half.beginMove())
        #expect(again.map(\.name) == ["Kanye West"] && half.settled == nil)

        // it had finished one name, and the names after it - never sent - still have albums to move
        let three = ArtistRefileFlow.Ask(names: ["Kanye", "Kanye West"], mbid: Self.ye, current: "Ye")
        var rest = ArtistRefileFlow(three, online: true)
        rest.previewed(try given(rest.preview()).ticket, [Self.plan("Kanye", moves: [Self.yeezus]),
                                                          Self.plan("Kanye West", moves: [Self.graduation])])
        _ = try given(rest.beginMove())
        _ = rest.moveEnded(applied: [], stopped: (.unanswered, nil))
        #expect(rest.settling?.name == "Kanye")
        rest.previewed(try given(rest.preview()).ticket, [Self.plan("Kanye West", moves: [Self.graduation])],
                       gone: ["Kanye"])
        #expect(rest.settled == "deadwax had finished: 1 album from Kanye moved into Ye/." && rest.outcome == nil)
        #expect(rest.canMove && rest.view?.moves == [Self.graduation])
    }

    /// Move's waits are worked out from each name's size: one the page hadn't read is read as Move starts, and
    /// without it Move doesn't start - nothing sent, said, and offered again.
    @Test func moveStartsOnlyWithEveryNamesSize() throws {
        let plans = [Self.plan("Kanye", moves: [Self.yeezus]), Self.plan("Kanye West", moves: [Self.graduation])]
        #expect(ArtistRefileFlow.unsized(plans, in: ["Kanye": 1e9, "Kanye West": 0]) == [])
        #expect(ArtistRefileFlow.unsized(plans, in: ["Kanye": 1e9]) == ["Kanye West"])
        #expect(ArtistRefileFlow.unsized(plans, in: ["Kanye": .nan, "Kanye West": -1]) == ["Kanye", "Kanye West"])
        var flow = ArtistRefileFlow(.init(names: ["Kanye", "Kanye West"], mbid: Self.ye, current: "Ye"), online: true)
        flow.previewed(try given(flow.preview()).ticket, plans)
        _ = try given(flow.beginMove())
        flow.moveNotStarted(words: ArtistManageWords.sizesFailed)
        #expect(!flow.applying && flow.notStarted == ArtistManageWords.sizesFailed && flow.canMove && flow.wrote == 0)
        _ = try given(flow.beginMove())
        #expect(flow.notStarted == nil)
    }

    @Test func theMenuOffersEachToolByItsOwnPermission() {
        let all = Managing.ArtistManaging(images: true, whichArtist: true, move: true, any: true)
        func offered(_ may: Managing.ArtistManaging, online: Bool = true, gone: Bool = false,
                     names: [String] = ["Kanye West"], answered: Bool = true, indexKnown: Bool = true,
                     mbid: String? = nil, byChoice: Bool = false, current: String? = "Ye",
                     moveNames: [String] = ["Kanye West"]) -> ArtistManage.Offered {
            ArtistManage.offered(may: may, online: online, gone: gone, names: names, answered: answered,
                                 indexKnown: indexKnown, mbid: mbid, byChoice: byChoice, current: current,
                                 moveNames: moveNames)
        }
        let nothing = ArtistManage.Offered(images: false, who: false, move: false)
        #expect(offered(all) == .init(images: true, who: true, move: true))
        #expect(offered(Managing.artistManaging([.edit])) == .init(images: true, who: true, move: false))
        #expect(offered(Managing.artistManaging([.library])) == .init(images: false, who: false, move: true))
        #expect(offered(.init(images: true, whichArtist: false, move: false, any: true)) == .init(images: true, who: false,
                                                                                                  move: false))
        #expect(offered(.init(images: false, whichArtist: true, move: false, any: true)) == .init(images: false, who: true,
                                                                                                  move: false))
        #expect(offered(all, online: false) == nothing && offered(all, gone: true) == nothing)
        #expect(!offered(all, online: false).any && offered(all).any)
        #expect(offered(all, names: []).images == false)
        #expect(offered(all, answered: false).who == false && offered(all, indexKnown: false).who == false)
        #expect(offered(all, mbid: Self.ye).who == false && offered(all, mbid: Self.ye, byChoice: true).who == true)
        #expect(offered(all, current: nil).move == false && offered(all, moveNames: []).move == false)
    }

    @Test func aFailedPreviewIsSaidAndOutOfReachNothingMoves() throws {
        let ask = ArtistRefileFlow.Ask(names: ["Kanye West"], mbid: Self.ye, current: "Ye")
        var flow = ArtistRefileFlow(ask, online: true)
        let ticket = try given(flow.preview())
        flow.previewFailed(ticket.ticket, words: ArtistManageWords.previewFailed)
        #expect(!flow.loading && flow.error == ArtistManageWords.previewFailed && !flow.canMove)
        flow.previewed(try given(flow.preview()).ticket, [Self.plan("Kanye West", moves: [Self.graduation])])
        #expect(flow.canMove && flow.error == nil)
        flow.wentAway()
        let away = flow.preview()
        #expect(!flow.canMove && away == nil && flow.needsRead)
        let back = flow.cameBack()
        #expect(back && !flow.canMove)
        flow.previewed(try given(flow.preview()).ticket, [Self.plan("Kanye West", moves: [Self.graduation])])
        #expect(flow.canMove)
        var empty = ArtistRefileFlow(.init(names: [], mbid: nil, current: "Ye"), online: true)
        let nothingAsked = empty.preview()
        #expect(nothingAsked == nil)
    }

    // MARK: Which artist is this?

    @Test func whoSearchesTheNewestAndAsksAgainWhenBack() throws {
        var flow = ArtistWhoFlow(online: true)
        let one = try given(flow.begin("Nirvana"))
        let two = try given(flow.begin("Nirvana"))
        flow.answered(one, query: "Nirvana", [])
        #expect(flow.searching && flow.matches == nil)
        flow.failed(two, query: "Nirvana", words: ArtistManageWords.searchFailed)
        #expect(!flow.searching && flow.note == ArtistManageWords.searchFailed)
        flow.wentAway()
        let away = flow.begin("Nirvana")
        #expect(away == nil)
        let back = flow.cameBack()
        #expect(back == "Nirvana")
        flow.answered(try given(flow.begin("Nirvana")), query: "Nirvana", [MBArtistMatch(mbid: Self.ye, name: "Nirvana")])
        let nothingLeft = flow.cameBack()
        #expect(flow.matches?.count == 1 && flow.note == nil && nothingLeft == nil)
        // a failed search is asked again as it was typed, trimmed - as the web searches it
        flow.failed(try given(flow.begin("  Nirvana UK ")), query: "  Nirvana UK ", words: ArtistManageWords.searchFailed)
        #expect(flow.failedFor == "Nirvana UK")
    }

    @Test func theArtistPagesToolsAreByPermission() {
        #expect(Managing.artistManaging([.edit]) == .init(images: true, whichArtist: true, move: false, any: true))
        #expect(Managing.artistManaging([.library]) == .init(images: false, whichArtist: false, move: true, any: true))
        #expect(Managing.artistManaging([.request]) == .init(images: false, whichArtist: false, move: false, any: false))
    }
}
