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
            //? (R3) the app says Queue where the web says Up Next: read back as the web says it (QueueWord)
            diffs.text("\(label): title", QueueWord.web(pick.title), menu["title"])
            let queued = pick.choose(choice, setting: setting)
            let calls = menu["calls"].list
            diffs.check("\(label): a call", queued != nil, !calls.isEmpty)
            diffs.check("\(label): closed", queued != nil ? 1 : 0, menu["closed"].int ?? -1)
            guard let queued, let call = calls.first else { continue }
            diffs.check("\(label): which call", queued.choice == .next ? "playNext" : "playLast", call[0].string ?? "")
            diffs.check("\(label): songs queued", queued.tracks.count, call[1].list.count)
            for level in call[1].list { diffs.text("\(label): level", queued.level?.rawValue, level) }
            diffs.check("\(label): remembered", queued.remember, menu["remembered"][0].list.compactMap(\.string))
            diffs.text("\(label): notice", QueueWord.web(pick.notice(choice, started: started)), menu["notice"])
        }
        diffs.done()
    }

    /// (16 Nov) Where the phone departs from the web's menu, on purpose (notes/ios.md "Add to Queue: the swipe, and the
    /// menus' one item"; James: "Only Add to Queue"): the web's two items, Play Next and Play Last, are the phone's one,
    /// Add to Queue - the web's Play Last under the phone's own word, its call, levels, albums and notice the web's to
    /// the letter. Held against the fixture, so a change to the web's menu fails here until it is looked at.
    @Test func thePhonesOneItemIsTheWebsPlayLast() {
        let web = fixture["words"]["items"].list.compactMap(\.string)
        #expect(web == ["Play Next", "Play Last"], "the web's two, which the phone's menus no longer offer")
        #expect(AddToQueue.choice.label == web[1], "Add to Queue does what the web's Play Last does")
        #expect(!web.contains(AddToQueue.words), "under the phone's own word")
        let diffs = ScreenDiffs()
        var driven = 0
        for menu in fixture["menus"].list where menu["how"].string == AddToQueue.choice.rawValue {
            let tracks = (0..<(menu["count"].int ?? 0)).map { "s\($0)" }
            let pick = QueuePick(label: menu["label"].string!, tracks: tracks, albumIds: ["al-1"],
                                 queuedAs: menu["as"].string.flatMap(QueuedAs.init(rawValue:)))
            let setting = Normalization(rawValue: menu["setting"].string!)!
            let started = menu["started"].bool!
            let label = "Add to Queue: \(menu["name"].string ?? "?") / \(setting) / started \(started)"
            guard let queued = pick.choose(AddToQueue.choice, setting: setting), let call = menu["calls"].list.first else {
                diffs.check("\(label): a call", false, !menu["calls"].list.isEmpty)
                continue
            }
            driven += 1
            diffs.check("\(label): the web's call", "playLast", call[0].string ?? "")
            for level in call[1].list { diffs.text("\(label): level", queued.level?.rawValue, level) }
            diffs.check("\(label): remembered", queued.remember, menu["remembered"][0].list.compactMap(\.string))
            diffs.text("\(label): notice", QueueWord.web(pick.notice(AddToQueue.choice, started: started)), menu["notice"])
        }
        diffs.done()
        #expect(driven > 0, "the fixture drives the web's Play Last")
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
        //? AlbumPage.tsx: aria-disabled={!album || !tracks.length} - an answer with no songs in it offers nothing either
        #expect(QueuePick.album(Album(id: "al-3", name: "Empty", song: [])) == nil, "no ••• for an album with no songs")
        let one = QueuePick.song(songs[1], of: album)
        #expect(one.label == "Sour Times" && one.tracks.map(\.id) == ["b"] && one.queuedAs == nil)
        //? `albums: [album]`: the album is remembered as just added, so it opens at once from Up Next
        #expect(one.albumIds == ["al-1"])
        #expect(one.choose(.last, setting: .off)?.remember == ["al-1"] && whole?.choose(.next, setting: .off)?.remember == ["al-1"])
        #expect(one.choose(.next, setting: .auto)?.level == .track)
        #expect(whole?.choose(.last, setting: .auto)?.level == .album)
        #expect(QueuePickWords.playLevel(.auto) == .album && QueuePickWords.playLevel(.song) == .track && QueuePickWords.playLevel(.off) == nil)
        #expect(one.notice(.next, started: false) == "Playing next: Sour Times")
        #expect(one.notice(.last, started: false) == "Added to Queue: Sour Times")
        #expect(one.notice(.last, started: true) == nil)
    }
}
