import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac's menus and keys (the Mac app's plan 1.3; notes/ios.md "The Mac app, slice 2"): each item's words, its
/// shortcut and whether it can be used, from the player's state and the window's - nothing queued, playing and paused,
/// Repeat's three, a library's shuffle, a text field with the cursor, Now Playing open, a sheet up. The App draws
/// MacMenu's items and nothing else (tests/test_ios_mac.py holds MacCommands.swift to them).
@Suite struct MacMenuTests {
    private static let playing = MacMenu.State(queued: true, playing: true, length: 240, hasAlbum: true)

    private static func items(_ state: MacMenu.State) -> [MacMenu.Item] { MacMenu.controls(state).flatMap { $0 } }

    @Test func nothingQueuedDimsEveryControl() {
        let state = MacMenu.State()
        for item in Self.items(state) {
            #expect(!item.enabled, "\(item.command) with nothing queued")
            #expect(!item.ticked, "\(item.command): nothing to tick")
        }
        // the words still say what each would do
        #expect(MacMenu.item(.playPause, state).words == "Play")
        #expect(MacMenu.item(.shuffle, state).words == "Shuffle")
        // Settings… and Find go to the tabs, queued or not; Refresh only where a page has one
        #expect(MacMenu.item(.settings, state).enabled && MacMenu.item(.find, state).enabled)
        #expect(!MacMenu.item(.refresh, state).enabled)
        // even with Repeat or Shuffle left on from before, nothing is ticked with nothing queued
        let kept = MacMenu.State(shuffle: true, repeatMode: .all)
        #expect(Self.items(kept).allSatisfy { !$0.ticked && !$0.enabled })
    }

    @Test func playingAndPaused() {
        let playing = MacMenu.item(.playPause, Self.playing)
        #expect(playing.words == "Pause" && playing.words == PlayerWords.playPause(playing: true))
        #expect(playing.enabled && playing.shortcut == MacMenu.Shortcut(.space) && playing.shortcut?.said == "Space")
        var paused = Self.playing
        paused.playing = false
        let item = MacMenu.item(.playPause, paused)
        #expect(item.words == "Play" && item.words == PlayerWords.playPause(playing: false) && item.enabled)
        // the rest are as they were, playing or paused
        for command in [MacMenu.Command.next, .previous, .forward, .back, .shuffle, .goToCurrentSong] {
            #expect(MacMenu.item(command, paused) == MacMenu.item(command, Self.playing), "\(command)")
            #expect(MacMenu.item(command, paused).enabled, "\(command)")
        }
        #expect(MacMenu.item(.next, paused).words == PlayerWords.next)
        #expect(MacMenu.item(.previous, paused).words == NowPlayingWords.previous)
    }

    @Test func repeatsThreeStatesEachTickedAlone() {
        #expect(MacMenu.Words.repeatMenu == repeatLabel(.off) && MacMenu.Words.repeatMenu == "Repeat")
        let words = MacMenu.Command.repeats.map { MacMenu.item($0, Self.playing).words }
        #expect(words == ["Repeat off", "Repeat all", "Repeat one"])
        #expect(words == Repeat.allCases.map(UpNextWords.repeatSaid), "Up Next's own, in Up Next's order")
        for mode in Repeat.allCases {
            var state = Self.playing
            state.repeatMode = mode
            let ticked = MacMenu.Command.repeats.filter { MacMenu.item($0, state).ticked }
            #expect(ticked.map(\.repeatMode) == [mode], "\(mode): its own item ticked, and only it")
            #expect(MacMenu.Command.repeats.allSatisfy { MacMenu.item($0, state).enabled })
            #expect(MacMenu.Command.repeats.allSatisfy { MacMenu.item($0, state).shortcut == nil })
        }
        #expect(MacMenu.Command.repeats.compactMap(\.repeatMode) == Repeat.allCases)
        #expect(MacMenu.Command.allCases.filter { $0.repeatMode != nil } == MacMenu.Command.repeats)
    }

    @Test func shuffleIsUpNextsAndALibrarysCantBeTurnedOff() {
        var state = Self.playing
        #expect(MacMenu.item(.shuffle, state) == MacMenu.Item(command: .shuffle, words: shuffleLabel(nil), shortcut: nil,
                                                              enabled: true, ticked: false))
        state.shuffle = true
        #expect(MacMenu.item(.shuffle, state).ticked && MacMenu.item(.shuffle, state).enabled)
        for scope in [PagedScope.yours, .store] {
            state.paged = scope
            let item = MacMenu.item(.shuffle, state)
            #expect(item.words == shuffleLabel(scope), "named for why, as Now Playing's")
            #expect(item.ticked && !item.enabled, "on, and can't be turned off")
        }
        // the words check 416 names
        #expect(shuffleLabel(.yours) == "Shuffle - shuffling your whole library")
        #expect(shuffleLabel(.store) == "Shuffle - shuffling all music")
    }

    @Test func aTextFieldKeepsItsOwnKeys() {
        var state = Self.playing
        state.typing = true
        // Space types a space, ⌘→ and ⌘← move in the field: off their items while it has the cursor
        for command in [MacMenu.Command.playPause, .next, .previous] {
            let item = MacMenu.item(command, state)
            #expect(item.shortcut == nil, "\(command)'s key is the field's")
            #expect(item.enabled && item.words == MacMenu.item(command, Self.playing).words, "still a click away")
            #expect(MacMenu.yieldsToTyping(command))
        }
        // the rest keep theirs - no field moves on ⌥⌘ or types with ⌘
        for command in MacMenu.Command.allCases where !MacMenu.yieldsToTyping(command) {
            #expect(MacMenu.item(command, state).shortcut == MacMenu.key(command), "\(command)")
        }
        #expect(MacMenu.item(.playPause, Self.playing).shortcut == MacMenu.Shortcut(.space))
        #expect(MacMenu.item(.next, Self.playing).shortcut?.said == "\u{2318}\u{2192}")
        #expect(MacMenu.item(.previous, Self.playing).shortcut?.said == "\u{2318}\u{2190}")
    }

    @Test func theKeysAsThePlanHasThem() {
        let said = Dictionary(uniqueKeysWithValues: MacMenu.Command.allCases.compactMap { command in
            MacMenu.key(command).map { (command, $0.said) }
        })
        #expect(said == [.settings: "\u{2318},", .find: "\u{2318}F", .refresh: "\u{2318}R", .playPause: "Space",
                         .next: "\u{2318}\u{2192}", .previous: "\u{2318}\u{2190}",
                         .forward: "\u{2325}\u{2318}\u{2192}", .back: "\u{2325}\u{2318}\u{2190}",
                         .goToCurrentSong: "\u{2318}L",
                         // (slice 3) the View menu's frame
                         .sidebar: "\u{2303}\u{2318}S", .upNext: "\u{2325}\u{2318}U", .lyrics: "\u{2325}\u{2318}L",
                         .info: "\u{2318}I"])
        // no two items share a key
        let keys = MacMenu.Command.allCases.compactMap(MacMenu.key)
        for (i, key) in keys.enumerated() {
            #expect(!keys[(i + 1)...].contains(key), "\(key.said) twice")
        }
        // the Mac's order for the modifiers
        #expect(MacMenu.Modifiers([.command, .shift, .option, .control]).said == "\u{2303}\u{2325}\u{21E7}\u{2318}")
        // none of ⌘Q, ⌘W, ⌘H, ⌘M, ⌃⌘F - the system's own
        for taken in ["q", "w", "h", "m"] {
            #expect(!keys.contains(MacMenu.Shortcut(.character(Character(taken)), .command)), "\(taken)")
        }
        #expect(!keys.contains(MacMenu.Shortcut(.character("f"), [.control, .command])))
    }

    @Test func theWordsAreTheAppsOwn() {
        let state = Self.playing
        #expect(MacMenu.item(.settings, state).words == "Settings\u{2026}" && YouWords.title == "Settings")
        #expect(MacMenu.item(.find, state).words == "Find")
        #expect(MacMenu.item(.refresh, state).words == LibrarySwitchWords.refresh)
        #expect(MacMenu.item(.forward, state).words == "Forward 10 Seconds")
        #expect(MacMenu.item(.back, state).words == "Back 10 Seconds")
        #expect(MacMenu.item(.goToCurrentSong, state).words == "Go to Current Song")
        #expect(MacMenu.Words.controls == "Controls")
        // the menu's sections, in order
        let sections = MacMenu.controls(state).map { $0.map(\.command) }
        #expect(sections == [[.playPause, .next, .previous], [.forward, .back],
                             [.shuffle, .repeatOff, .repeatAll, .repeatOne], [.goToCurrentSong]])
    }

    @Test func forwardAndBackStayInTheSong() {
        #expect(MacMenu.skip(.forward, from: 30, length: 240) == 40)
        #expect(MacMenu.skip(.back, from: 30, length: 240) == 20)
        #expect(MacMenu.skip(.back, from: 4, length: 240) == 0, "never before the start")
        #expect(MacMenu.skip(.forward, from: 235, length: 240) == 240, "never past the end")
        #expect(MacMenu.skip(.forward, from: 300, length: 240) == 240, "a position past the end is the end")
        #expect(MacMenu.skip(.back, from: -3, length: 240) == 0)
        #expect(MacMenu.skip(.forward, from: 30, length: 0) == nil, "no length known: nowhere to go")
        #expect(MacMenu.skip(.next, from: 30, length: 240) == nil)
        // dimmed while the length isn't known
        var state = Self.playing
        state.length = 0
        #expect(!MacMenu.item(.forward, state).enabled && !MacMenu.item(.back, state).enabled)
        #expect(MacMenu.item(.next, state).enabled)
    }

    @Test func goToCurrentSongNeedsItsAlbumAndTheTabs() {
        var state = Self.playing
        #expect(MacMenu.item(.goToCurrentSong, state).enabled)
        state.hasAlbum = false
        #expect(!MacMenu.item(.goToCurrentSong, state).enabled, "a song that names no album")
        state = Self.playing
        state.tabs = false
        // the sign-in over the app: the music plays on and its controls work, but nothing opens a page
        #expect(!MacMenu.item(.goToCurrentSong, state).enabled)
        #expect(!MacMenu.item(.settings, state).enabled && !MacMenu.item(.find, state).enabled)
        #expect(MacMenu.item(.playPause, state).enabled && MacMenu.item(.next, state).enabled)
    }

    @Test func refreshWhereThePageHasOneAndOneAtATime() {
        var state = Self.playing
        state.refresh = .ready
        #expect(MacMenu.item(.refresh, state).enabled)
        state.refresh = .running
        #expect(!MacMenu.item(.refresh, state).enabled, "one on its way: a second waits for it")
        state.refresh = .none
        #expect(!MacMenu.item(.refresh, state).enabled)
        state.refresh = .ready
        state.tabs = false
        #expect(!MacMenu.item(.refresh, state).enabled)
        state = MacMenu.State(refresh: .ready)
        #expect(MacMenu.item(.refresh, state).enabled, "nothing queued doesn't matter to it")
        // Now Playing over the pages: the page under it isn't refreshed unseen - Find and Settings… still go (closing it)
        state = MacMenu.State(queued: true, playing: true, length: 240, hasAlbum: true, refresh: .ready, nowPlaying: true)
        #expect(!MacMenu.item(.refresh, state).enabled)
        #expect(MacMenu.item(.find, state).enabled && MacMenu.item(.settings, state).enabled)
        #expect(MacMenu.item(.goToCurrentSong, state).enabled && MacMenu.item(.playPause, state).enabled)
    }

    @Test func aSheetUpKeepsThePageUnderItAsItIs() {
        // a sheet over the page (Edit album, Up Next, Add to a playlist…): the page under it isn't refreshed unseen, and
        // nothing changes the tab under the sheet - Settings…, Find and Go to Current Song wait for it to close
        var state = Self.playing
        state.refresh = .ready
        state.sheet = true
        for command in [MacMenu.Command.refresh, .settings, .find, .goToCurrentSong] {
            #expect(!MacMenu.item(command, state).enabled, "\(command) with a sheet up")
            #expect(MacMenu.item(command, state).shortcut == MacMenu.key(command), "\(command): its key stays drawn")
        }
        // the music's own controls carry on
        for command in [MacMenu.Command.playPause, .next, .previous, .forward, .back, .shuffle] + MacMenu.Command.repeats {
            #expect(MacMenu.item(command, state) == MacMenu.item(command, Self.playing), "\(command)")
        }
        #expect(MacMenu.item(.playPause, state).enabled && MacMenu.item(.playPause, state).words == "Pause")
        // the sheet gone: each as it was
        state.sheet = false
        for command in [MacMenu.Command.refresh, .settings, .find, .goToCurrentSong] {
            #expect(MacMenu.item(command, state).enabled, "\(command) with the sheet gone")
        }
        // a sheet over Now Playing (Up Next, Info): the same
        state = MacMenu.State(queued: true, playing: true, length: 240, hasAlbum: true, refresh: .ready, nowPlaying: true,
                              sheet: true)
        #expect(!MacMenu.item(.find, state).enabled && !MacMenu.item(.settings, state).enabled)
        #expect(!MacMenu.item(.refresh, state).enabled && !MacMenu.item(.goToCurrentSong, state).enabled)
        #expect(MacMenu.item(.next, state).enabled)
    }

    // MARK: (slice 3) the View menu's frame

    @Test func theSidebarItemSaysWhatItWillDo() {
        var state = Self.playing
        #expect(MacMenu.item(.sidebar, state).words == "Hide Sidebar", "shown: Hide")
        state.sidebarShown = false
        #expect(MacMenu.item(.sidebar, state).words == "Show Sidebar")
        #expect(MacMenu.item(.sidebar, state).enabled && !MacMenu.item(.sidebar, state).ticked)
        // nothing queued doesn't matter to it; the sign-in over the app and a sheet up do
        #expect(MacMenu.item(.sidebar, MacMenu.State()).enabled)
        #expect(!MacMenu.item(.sidebar, MacMenu.State(tabs: false)).enabled)
        #expect(!MacMenu.item(.sidebar, MacMenu.State(sheet: true)).enabled)
        // Find shows the sidebar to put the cursor in its field: it is never dimmed for a sidebar hidden
        #expect(MacMenu.item(.find, state).enabled)
    }

    @Test func thePanelsOneAtATimeEachTickedWhileItShows() {
        let words = MacMenu.Command.panels.map { MacMenu.item($0, Self.playing).words }
        #expect(words == [UpNextWords.title, LyricsWords.lyrics, InfoWords.title])
        #expect(words == ["Up Next", "Lyrics", "Info"])
        #expect(MacMenu.Command.panels.compactMap(\.panel) == [.upNext, .lyrics, .info])
        #expect(MacMenu.Command.allCases.filter { $0.panel != nil } == MacMenu.Command.panels)
        for panel in MacFrame.Panel.allCases {
            var state = Self.playing
            state.panel = panel
            let ticked = MacMenu.Command.panels.filter { MacMenu.item($0, state).ticked }
            #expect(ticked.compactMap(\.panel) == (panel == .none ? [] : [panel]), "\(panel): its own item ticked alone")
            #expect(MacMenu.Command.panels.allSatisfy { MacMenu.item($0, state).enabled }, "\(panel)")
        }
        let sections = MacMenu.view(Self.playing).map { $0.map(\.command) }
        #expect(sections == [[.sidebar], [.upNext, .lyrics, .info]])
    }

    @Test func aPanelOpensWithSomethingQueuedAndAlwaysCloses() {
        // nothing queued: none opens - but one left open (Lyrics saying Nothing playing) can be put away
        let none = MacMenu.State()
        for command in MacMenu.Command.panels {
            #expect(!MacMenu.item(command, none).enabled, "\(command) with nothing queued")
            var open = none
            open.panel = command.panel ?? .none
            #expect(MacMenu.item(command, open).enabled && MacMenu.item(command, open).ticked, "\(command) open")
        }
        // Lyrics dimmed while it is known the song has none (or none kept here offline), as the bar's button is
        for have in LyricsHave.allCases {
            var state = Self.playing
            state.lyrics = have
            #expect(MacMenu.item(.lyrics, state).enabled == !Lyrics.dimmed(have, on: false), "\(have)")
            state.panel = .lyrics
            #expect(MacMenu.item(.lyrics, state).enabled, "\(have): open, it can be put away")
        }
        // a sheet up or the sign-in over the app: no panel is opened or closed under it
        for command in MacMenu.Command.panels + [.sidebar] {
            var state = Self.playing
            state.panel = command.panel ?? .none
            state.sheet = true
            #expect(!MacMenu.item(command, state).enabled, "\(command) under a sheet")
            state.sheet = false
            state.tabs = false
            #expect(!MacMenu.item(command, state).enabled, "\(command) under the sign-in")
        }
        // a text field with the cursor keeps none of these keys from the field: ⌥⌘, ⌃⌘ and ⌘I type nothing
        for command in MacMenu.Command.panels + [.sidebar] {
            #expect(!MacMenu.yieldsToTyping(command), "\(command)")
        }
    }
}
