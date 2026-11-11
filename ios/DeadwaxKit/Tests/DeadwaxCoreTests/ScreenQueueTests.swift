import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/queue.json: app/QueueMenu.tsx driven - a pick under each Normalization setting, Play Next or Play
/// Last, the music started from it or not - and its words, with the album page's picks (AlbumPage.tsx, as written).
@Suite struct ScreenQueueTests {
    let fixture = try! Web.load("queue")

    @Test func theFixtureIsThere() {
        #expect(fixture["menus"].list.count == 80)
        expectMadeFrom(fixture, ["ui/src/app/QueueMenu.tsx", "ui/src/player/levelling.ts", "ui/src/lib/loudness.ts levelFor",
                                 "ui/src/lib/upNext.ts queuedWords", "ui/src/player/AlbumPage.tsx the album's pick"])
    }

    @Test func theMenusWordsAreTheWebs() {
        #expect(QueueChoice.allCases.map(\.label) == fixture["words"]["items"].list.compactMap(\.string))
        #expect(QueuePickWords.cancel == fixture["words"]["cancel"].string)
    }

    /// Every drive of the menu: which call, each song's level, whether it closed, the notice, the albums remembered.
    @Test func theMenuDrivenIsTheWebs() {
        let diffs = ScreenDiffs()
        for menu in fixture["menus"].list {
            let tracks = (0..<(menu["count"].int ?? 0)).map { "s\($0)" }
            let pick = QueuePick(label: menu["label"].string!, tracks: tracks, albumIds: ["al-1"],
                                 queuedAs: menu["as"].string.flatMap(QueuedAs.init(rawValue:)))
            let setting = Normalization(rawValue: menu["setting"].string!)!
            let choice = QueueChoice(rawValue: menu["how"].string!)!
            let started = menu["started"].bool!
            let label = "\(menu["name"].string ?? "?") / \(setting) / \(choice) / started \(started)"
            diffs.text("\(label): title", pick.title, menu["title"])
            let queued = pick.choose(choice, setting: setting)
            let calls = menu["calls"].list
            diffs.check("\(label): a call", queued != nil, !calls.isEmpty)
            diffs.check("\(label): closed", queued != nil ? 1 : 0, menu["closed"].int ?? -1)
            guard let queued, let call = calls.first else { continue }
            diffs.check("\(label): which call", queued.choice == .next ? "playNext" : "playLast", call[0].string ?? "")
            diffs.check("\(label): songs queued", queued.tracks.count, call[1].list.count)
            for level in call[1].list { diffs.text("\(label): level", queued.level?.rawValue, level) }
            diffs.check("\(label): remembered", queued.remember, menu["remembered"][0].list.compactMap(\.string))
            diffs.text("\(label): notice", pick.notice(choice, started: started), menu["notice"])
        }
        diffs.done()
    }

    /// The album page's picks: a row's one song as songs, the album's songs as an album - and Play and Shuffle, which
    /// queue as an album (AlbumPage.tsx's `queued(tracks, 'album')`).
    @Test func theAlbumPagesPicks() {
        #expect(fixture["picks"]["album"].string == "{ label: album.name, tracks, albums: [album], as: 'album' }")
        #expect(fixture["picks"]["song"].string == "{ label: song.title, tracks: [toQueueTrack(song, album)], albums: [album] }")
        #expect(fixture["picks"]["play"].string == "album")
        let songs = [Song(id: "a", title: "Mysterons"), Song(id: "b", title: "Sour Times")]
        let album = Album(id: "al-1", name: "Dummy", song: songs)
        let whole = QueuePick.album(album)
        #expect(whole?.label == "Dummy" && whole?.tracks.map(\.id) == ["a", "b"] && whole?.queuedAs == .album && whole?.albumIds == ["al-1"])
        #expect(QueuePick.album(Album(id: "al-2", name: "Empty")) == nil, "no ••• for an album whose songs aren't in")
        let one = QueuePick.song(songs[1], of: album)
        #expect(one.label == "Sour Times" && one.tracks.map(\.id) == ["b"] && one.queuedAs == nil)
        #expect(one.choose(.next, setting: .auto)?.level == .track)
        #expect(whole?.choose(.last, setting: .auto)?.level == .album)
        #expect(QueuePickWords.playLevel(.auto) == .album && QueuePickWords.playLevel(.song) == .track && QueuePickWords.playLevel(.off) == nil)
        #expect(one.notice(.next, started: false) == "Playing next: Sour Times")
        #expect(one.notice(.last, started: false) == "Added to Up Next: Sour Times")
        #expect(one.notice(.last, started: true) == nil)
    }
}
