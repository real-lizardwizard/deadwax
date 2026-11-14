import Foundation
import Testing
@testable import DeadwaxCore

/// Slice 2's half of Fixtures/playlists/playlist-vectors.json (ios/scripts/export-playlist-vectors.cjs, never by hand):
/// the picker's playlists and order, the add's and the made playlist's words, the duplicate question, Edit's rows, moves
/// and removals, the body Done sends, the rearrangement rule and the words - what the web's lib/playlists.ts answers.
enum PlaylistChangeVectors {
    struct Vectors: Decodable {
        struct Named: Decodable { let name: String; let text: String }
        struct Words: Decodable {
            let PLAYLIST_CHANGED, SHARED_NOTE, NEEDS_A_NAME, DISCARD_QUESTION: String
            let deleteQuestion: [Named]
        }
        struct HiddenCase: Decodable { let hidden: Int; let text: String }
        struct PickerCase: Decodable { let name: String; let list: [Playlist]; let ids: [String] }
        struct Entry: Decodable { let id: String; let title: String; let artist: String? }
        struct Pick: Decodable { let label: String; let songs: [Entry] }
        struct Added: Decodable { let added: Int; let already: Int; let mode: String; let text: String }
        struct Choice: Decodable, Equatable { let label: String; let mode: String? }
        struct Question: Decodable { let already: Int; let asked: Int; let text: String; let yes: Choice; let no: Choice }
        struct PickCase: Decodable {
            let name: String
            let pick: Pick
            let pickLine: String
            let madeWords: String
            let added: [Added]
            let questions: [Question]
        }
        struct Row: Decodable { let key: String; let id: String; let title: String; let artist: String }
        struct State: Decodable { let rows: [Row]; let name: String; let comment: String; let `public`: Bool }
        struct Body: Decodable, Equatable {
            let base: [String]
            let song_ids: [String]
            let name: String?
            let comment: String?
            let `public`: Bool?
        }
        struct Move: Decodable { let from: Int; let to: Int; let keys: [String] }
        struct Remove: Decodable { let index: Int; let keys: [String] }
        struct BodyCase: Decodable {
            let name: String
            let start: State
            let now: State
            let changed: Bool
            let body: Body?
            let keys: [String]?
        }
        struct Rearrangement: Decodable { let base: [String]; let next: [String]; let `is`: Bool }
        struct Edit: Decodable {
            let songs: [Song]
            let playlist: Playlist
            let start: State
            let moves: [Move]
            let removes: [Remove]
            let bodies: [BodyCase]
            let rearrangements: [Rearrangement]
        }

        let words: Words
        let hiddenEditWords: [HiddenCase]
        let picker: [PickerCase]
        let picks: [PickCase]
        let edit: Edit
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("playlists/playlist-vectors.json"))
    }

    static func pick(_ pick: Vectors.Pick) -> PlaylistPick {
        PlaylistPick(label: pick.label, songs: pick.songs.map { (one: Vectors.Entry) -> PlaylistPick.Entry in
            PlaylistPick.Entry(id: one.id, title: one.title, artist: one.artist)
        })
    }

    static func state(_ state: Vectors.State) -> PlaylistEditState {
        PlaylistEditState(rows: state.rows.map { (row: Vectors.Row) -> PlaylistEditRow in
            PlaylistEditRow(key: row.key, id: row.id, title: row.title, artist: row.artist)
        }, name: state.name, comment: state.comment, isPublic: state.public)
    }

    static func body(_ body: PlaylistEditBody) -> Vectors.Body {
        Vectors.Body(base: body.base, song_ids: body.songIds, name: body.name, comment: body.comment, public: body.isPublic)
    }

    /// The keys the body's JSON has, sorted as the fixture sorts them (JavaScript's default sort: by UTF-16 unit).
    static func keys(_ body: PlaylistEditBody) throws -> [String] {
        let json = try JSONEncoder().encode(body)
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        return object.keys.sorted { (a: String, b: String) -> Bool in a.utf16.lexicographicallyPrecedes(b.utf16) }
    }
}

@Suite struct PlaylistChangeVectorTests {
    let vectors: PlaylistChangeVectors.Vectors

    init() throws {
        vectors = try PlaylistChangeVectors.load()
    }

    @Test func theWordsAreTheWebs() {
        #expect(PlaylistWords.playlistChanged == vectors.words.PLAYLIST_CHANGED)
        #expect(PlaylistWords.sharedNote == vectors.words.SHARED_NOTE)
        #expect(PlaylistWords.needsAName == vectors.words.NEEDS_A_NAME)
        #expect(PlaylistWords.discardQuestion == vectors.words.DISCARD_QUESTION)
        #expect(vectors.words.deleteQuestion.count == 3)
        for one in vectors.words.deleteQuestion {
            #expect(PlaylistRules.deleteQuestion(one.name) == one.text, "\(one.name)")
        }
        for one in vectors.hiddenEditWords {
            #expect(PlaylistRules.hiddenEditWords(one.hidden) == one.text, "\(one.hidden)")
        }
    }

    @Test func thePickerOffersYoursChangedLastFirst() {
        #expect(vectors.picker.count >= 6)
        for one in vectors.picker {
            #expect(PlaylistRules.picker(one.list).map(\.id) == one.ids, "\(one.name)")
        }
    }

    @Test func whatAnAddAndAMadePlaylistSay() {
        #expect(vectors.picks.count >= 7)
        for one in vectors.picks {
            let pick = PlaylistChangeVectors.pick(one.pick)
            #expect(PlaylistRules.pickLine(pick) == one.pickLine, "\(one.name)")
            #expect(PlaylistRules.madeWords("Late night", pick: pick) == one.madeWords, "\(one.name)")
            for added in one.added {
                guard let mode = PlaylistDuplicates(rawValue: added.mode) else {
                    Issue.record("a mode the app doesn't know: \(added.mode)")
                    continue
                }
                #expect(PlaylistRules.addedWords(added: added.added, already: added.already, mode: mode, pick: pick,
                                                 name: "Late night") == added.text,
                        "\(one.name): \(added.added) added, \(added.already) already, \(added.mode)")
            }
        }
    }

    @Test func theDuplicateQuestionAndWhatEachButtonSends() {
        var asked = 0
        for one in vectors.picks {
            let pick = PlaylistChangeVectors.pick(one.pick)
            for question in one.questions {
                asked += 1
                let made = PlaylistRules.duplicateQuestion(already: question.already, asked: question.asked, pick: pick,
                                                           name: "Late night")
                let said = "\(one.name): \(question.already) of \(question.asked)"
                #expect(made.text == question.text, "\(said)")
                #expect(PlaylistChangeVectors.Vectors.Choice(label: made.yes.label, mode: made.yes.mode?.rawValue) == question.yes,
                        "\(said)")
                #expect(PlaylistChangeVectors.Vectors.Choice(label: made.no.label, mode: made.no.mode?.rawValue) == question.no,
                        "\(said)")
            }
        }
        #expect(asked >= 50)
    }

    @Test func editBeginsWithTheSongsAsDrawn() {
        let edit = vectors.edit
        let start = PlaylistEdit.start(songs: edit.songs, playlist: edit.playlist)
        #expect(start == PlaylistChangeVectors.state(edit.start))
        // a song in twice is two rows, told apart by their place
        #expect(Set(start.rows.map(\.key)).count == start.rows.count)
        #expect(start.rows.count == 4 && start.rows[0].id == start.rows[2].id)
    }

    @Test func aRowMovedAndARowTakenOut() {
        let rows = PlaylistChangeVectors.state(vectors.edit.start).rows
        #expect(vectors.edit.moves.count >= 40)
        for move in vectors.edit.moves {
            #expect(PlaylistEdit.move(rows, from: move.from, to: move.to).map(\.key) == move.keys, "\(move.from) -> \(move.to)")
        }
        for one in vectors.edit.removes {
            #expect(PlaylistEdit.remove(rows, at: one.index).map(\.key) == one.keys, "\(one.index)")
        }
    }

    @Test func theOneBodyDoneSends() throws {
        #expect(vectors.edit.bodies.count >= 40)
        for one in vectors.edit.bodies {
            let start = PlaylistChangeVectors.state(one.start)
            let now = PlaylistChangeVectors.state(one.now)
            let body = PlaylistEdit.body(start: start, now: now)
            #expect(body.map(PlaylistChangeVectors.body) == one.body, "\(one.name)")
            #expect(PlaylistEdit.changed(start: start, now: now) == one.changed, "\(one.name)")
            // the JSON's keys, not only the values: an unchanged field must be left out, never sent as null
            #expect(try body.map(PlaylistChangeVectors.keys) == one.keys, "\(one.name)")
        }
    }

    @Test func onlyRemovingAndReorderingIsARearrangement() {
        #expect(vectors.edit.rearrangements.count >= 9)
        for one in vectors.edit.rearrangements {
            #expect(PlaylistEdit.isRearrangement(base: one.base, next: one.next) == one.is, "\(one.base) -> \(one.next)")
        }
    }
}
