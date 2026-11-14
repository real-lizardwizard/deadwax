import Foundation
import Testing
@testable import DeadwaxCore

/// Slice 2 by hand (phase4-library.md 2.4): what the four writes send - exactly the keys deadwax's extra="forbid"
/// models declare - and what they answer, the picks the menus make, and the phone's own rules beside the web's (a typed
/// name's bound, a blank name).
@Suite struct PlaylistChangeTests {
    /// A scalar as a string - written so, never as an escape in this file (the file tools write escapes raw).
    static func scalar(_ value: UInt32) -> String { String(Character(Unicode.Scalar(value)!)) }

    static func json(_ value: some Encodable) throws -> [String: Any] {
        try object(JSONEncoder().encode(value))
    }

    /// JSON as an object - [:] for anything else.
    static func object(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: what the writes send

    @Test func aNewPlaylistSendsItsNameAndSongs() throws {
        let sent = try Self.json(NewPlaylistBody(name: "Late night", songIds: ["s1", "s1", "s2"]))
        #expect(Set(sent.keys) == ["name", "song_ids"])
        #expect(sent["name"] as? String == "Late night")
        #expect(sent["song_ids"] as? [String] == ["s1", "s1", "s2"])
        // none is an empty list, never left out
        let empty = try Self.json(NewPlaylistBody(name: "Empty", songIds: []))
        #expect(empty["song_ids"] as? [String] == [])
    }

    @Test func anAddSendsItsSongsAndWhatToDoWithOnesThereAlready() throws {
        for mode in PlaylistDuplicates.allCases {
            let sent = try Self.json(PlaylistAddBody(songIds: ["s1"], duplicates: mode))
            #expect(Set(sent.keys) == ["song_ids", "duplicates"])
            #expect(sent["duplicates"] as? String == mode.rawValue)
        }
        #expect(PlaylistDuplicates.allCases.map(\.rawValue) == ["ask", "add", "skip"])
    }

    @Test func doneSendsOnlyWhatChangedAndTriedOnlyAfterAFailure() throws {
        let bare = try Self.json(PlaylistEditBody(base: ["a", "b"], songIds: ["b"]))
        #expect(Set(bare.keys) == ["base", "song_ids"])
        let all = try Self.json(PlaylistEditBody(base: ["a"], songIds: [], tried: [], name: "N", comment: "", isPublic: false))
        #expect(Set(all.keys) == ["base", "song_ids", "tried", "name", "comment", "public"])
        // an emptying sends an empty list of songs; a failed emptying's tried is an empty list, not left out
        #expect(all["song_ids"] as? [String] == [] && all["tried"] as? [String] == [])
        #expect(all["comment"] as? String == "" && all["public"] as? Bool == false)
        // trying keeps every field and only sets tried
        let body = PlaylistEditBody(base: ["a"], songIds: ["a"], name: "N", comment: "C", isPublic: true)
        let retried = body.trying(["x"])
        #expect(retried.base == body.base && retried.songIds == body.songIds && retried.name == "N"
                && retried.comment == "C" && retried.isPublic == true && retried.tried == ["x"])
        #expect(body.trying(nil) == body)
    }

    // MARK: what they answer

    @Test func theAddsThreeAnswers() throws {
        let decode = { (text: String) throws -> PlaylistAddAnswer in
            try JSONDecoder().decode(PlaylistAddAnswer.self, from: Data(text.utf8))
        }
        // asked to ask, some there already: nothing written
        #expect(try decode(#"{"done": false, "already": 2, "asked": 5}"#) == PlaylistAddAnswer(done: false, already: 2, asked: 5))
        // all there with skip: done, none added
        #expect(try decode(#"{"done": true, "added": 0, "already": 3}"#) == PlaylistAddAnswer(done: true, already: 3, added: 0))
        #expect(try decode(#"{"done": true, "added": 4, "already": 0}"#) == PlaylistAddAnswer(done: true, already: 0, added: 4))
        // read leniently, but `done` must be there
        #expect(try decode(#"{"done": true, "already": "x", "added": -1}"#) == PlaylistAddAnswer(done: true, already: 0, added: -1))
        #expect(try decode(#"{"done": true, "added": 2, "already": -3}"#) == PlaylistAddAnswer(done: true, already: 0, added: 2))
        #expect(throws: (any Error).self) { try decode(#"{"already": 1}"#) }
        #expect(try JSONDecoder().decode(PlaylistDeleted.self, from: Data(#"{"deleted": true}"#.utf8)).deleted)
    }

    @Test func theClientAsksEachWriteAsTheSessionsPerson() async throws {
        let (client, transport) = client(session: "s")
        let made = #"{"playlist": \#(PlaylistPlayTests.summary), "songs": [{"id": "s1", "title": "Roads"}], "hidden": 0}"#
        transport.answer("/deadwax/navidrome/playlists", 200, made)
        let new = try await client.createPlaylist(name: "Late night", songIDs: ["s1"])
        #expect(new.playlist.id == "pl1" && new.songs.map(\.id) == ["s1"])
        var last = try #require(transport.last)
        #expect(last.method == "POST" && last.headers["Content-Type"] == "application/json")
        #expect(last.headers["Cookie"] != nil)
        let body = try Self.object(last.body)
        #expect(body["name"] as? String == "Late night" && body["song_ids"] as? [String] == ["s1"])

        transport.answer("/deadwax/navidrome/playlists/pl 1/add", 200, #"{"done": false, "already": 1, "asked": 2}"#)
        let added = try await client.addToPlaylist(id: "pl 1", songIDs: ["s1", "s2"], duplicates: .ask)
        #expect(added == PlaylistAddAnswer(done: false, already: 1, asked: 2))
        last = try #require(transport.last)
        #expect(last.method == "POST" && last.url.absoluteString.hasSuffix("/deadwax/navidrome/playlists/pl%201/add"))

        transport.answer("/deadwax/navidrome/playlists/pl1/edit", 200, made)
        let edited = try await client.editPlaylist(id: "pl1", body: PlaylistEditBody(base: ["s1", "s2"], songIds: ["s1"]))
        #expect(edited.songs.map(\.id) == ["s1"])
        last = try #require(transport.last)
        #expect(last.url.path == "/deadwax/navidrome/playlists/pl1/edit")
        let sent = try Self.object(last.body)
        #expect(Set(sent.keys) == ["base", "song_ids"])

        transport.answer("/deadwax/navidrome/playlists/pl1/delete", 200, #"{"deleted": true}"#)
        try await client.deletePlaylist(id: "pl1")
        last = try #require(transport.last)
        #expect(last.method == "POST" && last.body == nil && last.url.path == "/deadwax/navidrome/playlists/pl1/delete")
    }

    @Test func aRefusalIsTheServersOwnWords() async throws {
        let (client, transport) = client(session: "s")
        transport.answer("/deadwax/navidrome/playlists/pl1/edit", 409,
                         #"{"detail": "That playlist changed in another app since you started editing it - nothing was saved."}"#)
        do {
            _ = try await client.editPlaylist(id: "pl1", body: PlaylistEditBody(base: [], songIds: []))
            Issue.record("a 409 answered")
        } catch {
            #expect((error as? APIFailure)?.answer?.status == 409)
            #expect(ErrorWords.kind(of: error) == .refused)
            #expect(ErrorWords.of(error).said.hasPrefix("That playlist changed in another app"))
        }
        transport.answer("/deadwax/navidrome/playlists/pl2/delete", 403, #"{"detail": "That playlist is sam's - only they can change it."}"#)
        do {
            try await client.deletePlaylist(id: "pl2")
            Issue.record("a 403 answered")
        } catch {
            #expect(ErrorWords.kind(of: error) == .notAllowed)
            #expect(ErrorWords.of(error).said == "That playlist is sam's - only they can change it.")
        }
        transport.answer("/deadwax/navidrome/playlists", 422, #"{"detail": "A playlist needs a name."}"#)
        do {
            _ = try await client.createPlaylist(name: " ", songIDs: [])
            Issue.record("a 422 answered")
        } catch {
            #expect(ErrorWords.of(error).said == PlaylistWords.needsAName)
        }
    }

    @Test func anAddsAnswerIsTheQuestionOrTheNotice() {
        let pick = PlaylistPick(label: "Dummy", songs: [.init(id: "a", title: "Roads"), .init(id: "b", title: "Sour Times")])
        // nothing written: the question, of the answer's own count - or the songs sent when it names none
        #expect(PlaylistRules.outcome(of: PlaylistAddAnswer(done: false, already: 1, asked: 2), mode: .ask, pick: pick,
                                      name: "Late night") == .asks(already: 1, asked: 2))
        #expect(PlaylistRules.outcome(of: PlaylistAddAnswer(done: false, already: 1), mode: .ask, pick: pick,
                                      name: "Late night") == .asks(already: 1, asked: 2))
        // nothing written is never read as written, whatever the answer counts
        #expect(PlaylistRules.outcome(of: PlaylistAddAnswer(done: false, already: 0, asked: 2), mode: .ask, pick: pick,
                                      name: "Late night") == .asks(already: 0, asked: 2))
        // written: what the notice says
        #expect(PlaylistRules.outcome(of: PlaylistAddAnswer(done: true, already: 1, added: 1), mode: .skip, pick: pick,
                                      name: "Late night") == .added("Added 1 song to Late night - 1 was in it already"))
        #expect(PlaylistRules.outcome(of: PlaylistAddAnswer(done: true, already: 0, added: 2), mode: .ask, pick: pick,
                                      name: "Late night") == .added("Added 2 songs to Late night"))
        #expect(PlaylistRules.outcome(of: PlaylistAddAnswer(done: true, already: 2), mode: .skip, pick: pick,
                                      name: "Late night") == .added("Nothing added - they're all in Late night already"))
    }

    @Test func whatARefusedDoneMeans() {
        let answered = { (status: Int) -> APIFailure in
            .answered(.init(status: status, method: "POST", path: "/navidrome/playlists/pl1/edit", detail: "Words."))
        }
        #expect(PlaylistEdit.refusal(of: answered(409)) == .changedElsewhere)
        #expect(PlaylistEdit.refusal(of: answered(404)) == .gone)
        for status in [400, 403, 422, 500, 502, 503] {
            #expect(PlaylistEdit.refusal(of: answered(status)) == .refused, "\(status)")
        }
        #expect(PlaylistEdit.refusal(of: APIFailure.other("x")) == .refused)
        #expect(PlaylistEdit.refusal(of: URLError(.notConnectedToInternet)) == .refused)
    }

    @Test func thePickersTieOnNamesEqualOnceFoldedIsTheWholeName() {
        // The one picker rule the fixture can't hold: names equal once case and accents are folded, changed at the same
        // moment, go by the whole name in UTF-16 - not the list's order. The web's ICU localeCompare puts lowercase
        // first here ("same" before "Same"); the phone's own, noted in notes/ios.md (slice 2, "Decided here").
        let changed = "2026-11-01T10:00:00Z"
        let yours = { (id: String, name: String) -> Playlist in
            Playlist(id: id, name: name, changed: changed, mine: true, editable: true)
        }
        let list = [yours("lower", "same"), yours("accent", Self.scalar(0xC9) + "clair"), yours("title", "Same"),
                    yours("plain", "eclair"), yours("upper", "SAME")]
        #expect(PlaylistRules.picker(list).map(\.id) == ["plain", "accent", "upper", "title", "lower"])
    }

    // MARK: the picks the menus make

    @Test func aQueueMenusSongsAndTheSongPlaying() {
        let roads = Song(id: "s1", title: "Roads", artist: "Portishead")
        let untitled = Song(id: "s2")
        let pick = PlaylistPick(QueuePick(label: "Dummy", tracks: [roads, untitled], albumIds: ["al-d"], queuedAs: .album))
        #expect(pick == PlaylistPick(label: "Dummy", songs: [.init(id: "s1", title: "Roads", artist: "Portishead"),
                                                             .init(id: "s2", title: "", artist: nil)]))
        #expect(pick.ids == ["s1", "s2"])
        #expect(PlaylistRules.pickLine(pick) == "Dummy · 2 songs")
        let track = QueueTrack(id: "s1", title: "Roads", artist: "", album: "Dummy")
        let playing = PlaylistPick(playing: track)
        #expect(playing.label == "Roads" && playing.ids == ["s1"])
        // the playing song with no artist is its title alone
        #expect(PlaylistRules.pickLine(playing) == "Roads")
    }

    // MARK: Edit, the phone's own

    @Test func editsRowsAreTheSongsWithTheirPlaces() {
        let start = PlaylistEdit.start(songs: [Song(id: "a"), Song(id: "a", title: "Again", artist: "Them")],
                                       playlist: Playlist(id: "p", name: "N", comment: "C", isPublic: true))
        #expect(start.rows == [PlaylistEditRow(key: "0:a", id: "a", title: "", artist: ""),
                               PlaylistEditRow(key: "1:a", id: "a", title: "Again", artist: "Them")])
        #expect(start.name == "N" && start.comment == "C" && start.isPublic)
        #expect(PlaylistEdit.body(start: start, now: start) == nil)
        // nothing to move in none
        #expect(PlaylistEdit.move([], from: 0, to: 0).isEmpty)
        #expect(PlaylistEdit.remove([], at: 0).isEmpty)
    }

    @Test func aBlankNameWaitsAndATypedOneIsBounded() {
        let state = { (name: String) -> PlaylistEditState in PlaylistEditState(rows: [], name: name, comment: "", isPublic: false) }
        #expect(PlaylistEdit.needsName(state("")))
        #expect(PlaylistEdit.needsName(state("  \t ")))
        // JavaScript trims a byte-order mark and a no-break space; it keeps a next-line
        #expect(PlaylistEdit.needsName(state(Self.scalar(0xFEFF) + Self.scalar(0xA0))))
        #expect(!PlaylistEdit.needsName(state(Self.scalar(0x85))))
        #expect(!PlaylistEdit.needsName(state(" a ")))
        #expect(PlaylistEdit.trimmed(" \tLate night" + Self.scalar(0xA0)) == "Late night")
        #expect(PlaylistEdit.trimmed("Late night" + Self.scalar(0x85)) == "Late night" + Self.scalar(0x85))

        #expect(PlaylistEdit.clamped("abc", to: 3) == "abc")
        #expect(PlaylistEdit.clamped("abcd", to: 3) == "abc")
        #expect(PlaylistEdit.clamped("", to: 0) == "")
        // a character of two UTF-16 units is never cut in half: kept whole, or left out
        let note = Self.scalar(0x1F3B5)
        #expect(PlaylistEdit.clamped("ab" + note, to: 4) == "ab" + note)
        #expect(PlaylistEdit.clamped("ab" + note, to: 3) == "ab")
        #expect(PlaylistEdit.clamped(String(repeating: "x", count: 250), to: PlaylistRules.nameMax).utf16.count == 200)
        #expect(PlaylistRules.nameMax == 200 && PlaylistRules.commentMax == 1000)
    }

    @Test func theWordsAPersonReads() {
        #expect(PlaylistWords.someAlready("Late night") == "Nothing added - some are in Late night already")
        #expect(PlaylistWords.couldntAdd("Late night") == "Couldn't add to Late night.")
        #expect(PlaylistWords.made("Late night") == "Made Late night")
        #expect(PlaylistWords.deleted("Late night") == "Deleted Late night")
        #expect(NowPlayingWords.more(hasAlbum: true, download: true, eq: true, playlist: true)
                == "More: info, add to a playlist, go to album, download, EQ")
        #expect(NowPlayingWords.more(hasAlbum: false, playlist: true) == "More: info, add to a playlist")
        #expect(NowPlayingWords.more(hasAlbum: true) == "More: info, go to album")
        // the vocabulary: the phone's own words name nothing a listener never reads
        for line in [PlaylistWords.newPlaylistTitle, PlaylistWords.songsHeading, PlaylistWords.noPlaylistsYet,
                     PlaylistWords.someAlready("X"), PlaylistWords.couldntAdd("X")] {
            for banned in ["Navidrome", "the store", "Browse", "everything", "sync", "cache"] {
                #expect(!line.contains(banned), "\(line)")
            }
        }
    }
}
