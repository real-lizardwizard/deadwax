import Foundation
import Testing
@testable import DeadwaxCore

/// (R3) "Queue on both" (James, 25 Nov, the build plan's 3.8, answer 3): every word the phone and the Mac say for Up
/// Next says Queue instead - the page's name, Now Playing's button and its Shuffle and Repeat, the notice after Add to
/// Queue, Download the Queue, the queue menu's title, the side panel's tab and the View menu's item. The web keeps its
/// "Up Next", and so do its vectors (Fixtures/screens/queue.json, Fixtures/upnext/scenarios.json): the tests that hold
/// the app to them read the app's words back as the web says them, through `QueueWord.web`, so the web's every other
/// word is still held to the letter.
enum QueueWord {
    /// The app's words as the web says them: "Queue" as "Up Next", "Queue - Shuffle on" as "Up Next - Shuffle on",
    /// "Added to Queue: Dummy" as "Added to Up Next: Dummy" - anything else as it is.
    static func web(_ app: String?) -> String? {
        guard let app else { return nil }
        let title = UpNextWords.title
        if app == title { return "Up Next" }
        if app.hasPrefix("\(title) - ") { return "Up Next" + app.dropFirst(title.count) }
        if app.hasPrefix("Added to \(title): ") { return "Added to Up Next" + app.dropFirst("Added to \(title)".count) }
        return app
    }
}

@Suite struct QueueWordTests {
    @Test func theQueueIsUpNextsWordOnBoth() {
        #expect(UpNextWords.title == "Queue")
        #expect(upNextLabel(shuffle: false, repeat: .off) == "Queue")
        #expect(upNextLabel(shuffle: true, repeat: .all) == "Queue - Shuffle and Repeat all")
        #expect(queuedWords(.last, label: "Dummy") == "Added to Queue: Dummy")
        #expect(queuedWords(.next, label: "Dummy") == "Playing next: Dummy", "Play Next's own words stay")
        // (R3's review) the notice says what the swipe and the ••• said: "Add to Queue", then "Added to Queue: Roads"
        #expect(AddToQueue.words == "Add to Queue")
        #expect(queuedWords(.last, label: "Roads") == "Added to " + AddToQueue.words.dropFirst("Add to ".count) + ": Roads")
        #expect(DownloadWords.downloadUpNext == "Download the Queue")
        #expect(DownloadWords.downloadingUpNext(23) == "Downloading 23 songs from the Queue")
        #expect(QueuePick<String>(label: "", tracks: ["a"], albumIds: []).title == "Queue")
        #expect(MacDock.Words.tab(.upNext) == "Queue" && NowPlayingTabs.Words.tab(.upNext) == "Queue")
        #expect(NowPlayingTabs.Words.button(.upNext) == "Queue")
    }

    /// Every word Core says for either device: none says Up Next (DownloadWords' every line, the words fixtures').
    @Test func noWordTheAppSaysIsUpNext() {
        for device in Device.allCases {
            for line in DownloadWords.everyLine(device) {
                #expect(!line.contains("Up Next"), "\(device): \(line)")
            }
        }
        for mode in Repeat.allCases {
            for shuffle in [false, true] {
                #expect(!upNextLabel(shuffle: shuffle, repeat: mode).contains("Up Next"))
            }
        }
        for how in QueuedHow.allCases {
            #expect(!queuedWords(how, label: "Dummy").contains("Up Next"))
        }
    }

    /// The web's words read back: what the tests that hold the app to the web's vectors compare.
    @Test func theWebsWordsReadBack() {
        #expect(QueueWord.web("Queue") == "Up Next")
        #expect(QueueWord.web("Queue - Shuffle on") == "Up Next - Shuffle on")
        #expect(QueueWord.web("Queue - Shuffle and Repeat all") == "Up Next - Shuffle and Repeat all")
        #expect(QueueWord.web("Added to Queue: Sour Times") == "Added to Up Next: Sour Times")
        #expect(QueueWord.web("Playing next: Sour Times") == "Playing next: Sour Times")
        #expect(QueueWord.web("Dummy") == "Dummy")
        #expect(QueueWord.web(nil) == nil)
    }
}
