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
                         .info: "\u{2318}I",
                         // (R3) the dock's EQ tab
                         .eq: "\u{2325}\u{2318}E",
                         // (slice 6) File's - and (slice 7) Server settings' Save changes
                         .importEQFile: "\u{2318}O", .saveChanges: "\u{2318}S",
                         // (the Mac's Row Size) View > Row Size's two steps
                         .biggerRows: "\u{2318}+", .smallerRows: "\u{2318}-"])
        // no two items share a key
        let keys = MacMenu.Command.allCases.compactMap(MacMenu.key)
        for (i, key) in keys.enumerated() {
            #expect(!keys[(i + 1)...].contains(key), "\(key.said) twice")
        }
        // the Mac's order for the modifiers
        #expect(MacMenu.Modifiers([.command, .shift, .option, .control]).said == "\u{2303}\u{2325}\u{21E7}\u{2318}")
        // none of ⌘Q, ⌘W, ⌘H, ⌘M, ⌃⌘F - the system's own - nor (slice 7) Edit's ⌘Z, ⌘X, ⌘C, ⌘V and ⌘A, which the event
        // log's Copy and Select All ride rather than drawing a second of
        for taken in ["q", "w", "h", "m", "z", "x", "c", "v", "a"] {
            #expect(!keys.contains(MacMenu.Shortcut(.character(Character(taken)), .command)), "\(taken)")
        }
        #expect(!keys.contains(MacMenu.Shortcut(.character("f"), [.control, .command])))
    }

    // MARK: (R3) the dock's EQ tab: its key, free of the system's

    @Test func theEQsKeyIsFreeOfTheSystems() {
        #expect(MacMenu.key(.eq) == MacMenu.Shortcut(.character("e"), [.option, .command]))
        #expect(MacMenu.key(.eq)?.said == "\u{2325}\u{2318}E")
        // the keys a Catalyst window or macOS keeps whatever the app asks: Command-E (Use Selection for Find), and with
        // Option-Command, H (Hide Others), M (Minimize All), W (Close All), D (the Dock), T (View > Show Toolbar), Space
        // (Finder's search) and Escape (Force Quit) - none of them any item's
        let keys = MacMenu.Command.allCases.compactMap(MacMenu.key)
        let taken: [MacMenu.Shortcut] = [MacMenu.Shortcut(.character("e"), .command)]
            + ["h", "m", "w", "d", "t"].map { MacMenu.Shortcut(.character(Character($0)), [.option, .command]) }
            + [MacMenu.Shortcut(.space, [.option, .command]), MacMenu.Shortcut(.character("\u{1B}"), [.option, .command])]
        for key in taken {
            #expect(!keys.contains(key), "\(key.said) is the system's")
        }
        // and a field with the cursor keeps it from nothing: it types nothing
        #expect(!MacMenu.yieldsToTyping(.eq))
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
        #expect(words == [UpNextWords.title, LyricsWords.lyrics, InfoWords.title, EQWords.nowPlaying])
        // (R3) Queue, Up Next's word on the phone and the Mac since James's "Queue on both"
        #expect(words == ["Queue", "Lyrics", "Info", "EQ"])
        #expect(words == MacDock.tabs(getOpen: false).map(MacDock.Words.tab), "the dock's tabs' own words")
        #expect(MacMenu.Command.panels.compactMap(\.panel) == [.upNext, .lyrics, .info, .eq])
        #expect(MacMenu.Command.panels.compactMap(\.panel) == MacDock.tabs(getOpen: false), "every tab but Sources")
        #expect(MacMenu.Command.allCases.filter { $0.panel != nil } == MacMenu.Command.panels)
        for panel in [nil] + MacDock.Tab.allCases {
            var state = Self.playing
            state.panel = panel
            let ticked = MacMenu.Command.panels.filter { MacMenu.item($0, state).ticked }
            // Sources, the Get page's own, has no item: none ticked while it shows
            let own: [MacDock.Tab] = panel.map { $0 == .sources ? [] : [$0] } ?? []
            #expect(ticked.compactMap(\.panel) == own, "\(String(describing: panel)): its own item ticked alone")
            #expect(MacMenu.Command.panels.allSatisfy { MacMenu.item($0, state).enabled }, "\(String(describing: panel))")
        }
        let sections = MacMenu.view(Self.playing).map { $0.map(\.command) }
        #expect(sections == [[.sidebar], [.upNext, .lyrics, .info, .eq]])
    }

    @Test func aPanelOpensWithSomethingQueuedAndAlwaysCloses() {
        // nothing queued: none of the queue's three opens - but one left open (Lyrics saying Nothing playing) can be put
        // away; (R3) the EQ, the output's, opens whatever is queued, and Info with a row selected, which it is about
        let none = MacMenu.State()
        for command in MacMenu.Command.panels {
            #expect(MacMenu.item(command, none).enabled == (command == .eq), "\(command) with nothing queued")
            var open = none
            open.panel = command.panel
            #expect(MacMenu.item(command, open).enabled && MacMenu.item(command, open).ticked, "\(command) open")
        }
        #expect(MacMenu.item(.info, MacMenu.State(selected: true)).enabled, "Info about the row selected")
        #expect(!MacMenu.item(.upNext, MacMenu.State(selected: true)).enabled, "a selection queues nothing")
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
            state.panel = command.panel
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

    // MARK: (slice 6) File's Import EQ File…

    @Test func importEQFileOpensThePanelFromThePages() {
        let item = MacMenu.item(.importEQFile, Self.playing)
        #expect(item.words == "Import EQ File\u{2026}" && item.words == MacMenu.Words.importEQFile)
        #expect(item.shortcut == MacMenu.Shortcut(.character("o"), .command) && item.shortcut?.said == "\u{2318}O")
        #expect(item.enabled && !item.ticked)
        // the music doesn't matter to it: nothing queued, paused, a library's shuffle, Repeat one
        for state in [MacMenu.State(), MacMenu.State(queued: true), MacMenu.State(queued: true, paged: .yours, repeatMode: .one)] {
            #expect(MacMenu.item(.importEQFile, state).enabled, "\(state)")
        }
        // never over the sign-in (the tabs not drawn), and never over a sheet - as Settings… and Find
        #expect(!MacMenu.item(.importEQFile, MacMenu.State(tabs: false)).enabled)
        var sheet = Self.playing
        sheet.sheet = true
        #expect(!MacMenu.item(.importEQFile, sheet).enabled)
        #expect(MacMenu.item(.importEQFile, sheet).shortcut == MacMenu.key(.importEQFile), "its key stays drawn")
        for state in [MacMenu.State(tabs: false), sheet, Self.playing, MacMenu.State()] {
            #expect(MacMenu.item(.importEQFile, state).enabled == MacMenu.item(.settings, state).enabled, "\(state)")
            #expect(MacMenu.item(.importEQFile, state).enabled == MacMenu.item(.find, state).enabled, "\(state)")
        }
        // a text field with the cursor keeps its key: ⌘O types nothing
        var typing = Self.playing
        typing.typing = true
        #expect(!MacMenu.yieldsToTyping(.importEQFile))
        #expect(MacMenu.item(.importEQFile, typing).shortcut?.said == "\u{2318}O" && MacMenu.item(.importEQFile, typing).enabled)
        // a page whose Refresh is on its way, a panel open, the sidebar hidden: still there
        let busy = MacMenu.State(queued: true, playing: true, refresh: .running, sidebarShown: false, panel: .lyrics)
        #expect(MacMenu.item(.importEQFile, busy).enabled)
        // no Controls or View item: it's File's alone
        #expect(!(MacMenu.controls(Self.playing) + MacMenu.view(Self.playing)).flatMap { $0 }.contains { $0.command == .importEQFile })
    }

    // MARK: (slice 7) File's Save changes, and Tab

    @Test func saveChangesIsServerSettingsOwnButtonOnItsPage() {
        let open = MacMenu.State(serverSettings: true, saveOpen: true)
        let item = MacMenu.item(.saveChanges, open)
        #expect(item.words == "Save changes" && item.words == ServerSettings.save, "the button's own words")
        #expect(item.shortcut == MacMenu.Shortcut(.character("s"), .command) && item.shortcut?.said == "\u{2318}S")
        #expect(item.enabled && !item.ticked)
        // every way it can be: only with the tabs drawn, not under Now Playing, Server settings' page in front and its
        // button's own rule open - nothing else matters (the music, a sheet that holds the page, a field typing)
        for tabs in [true, false] {
            for nowPlaying in [true, false] {
                for settings in [true, false] {
                    for saveOpen in [true, false] {
                        for sheet in [true, false] {
                            for typing in [true, false] {
                                let state = MacMenu.State(queued: typing, playing: sheet, typing: typing, tabs: tabs,
                                                          nowPlaying: nowPlaying, sheet: sheet,
                                                          serverSettings: settings, saveOpen: saveOpen)
                                let now = MacMenu.item(.saveChanges, state)
                                #expect(now.enabled == (tabs && !nowPlaying && settings && saveOpen), "\(state)")
                                // its key stays drawn, dimmed or not: ⌘S types nothing, so a field keeps it off nothing
                                #expect(now.shortcut == MacMenu.key(.saveChanges), "\(state)")
                                #expect(now.words == ServerSettings.save, "never Saving…: dimmed while a save is out")
                            }
                        }
                    }
                }
            }
        }
        #expect(!MacMenu.yieldsToTyping(.saveChanges))
        // nothing unsaved (or a save out, or out of reach): dimmed, as the button is
        #expect(!MacMenu.item(.saveChanges, MacMenu.State(serverSettings: true)).enabled)
        // another page in front, or another sheet over Server settings (the App says serverSettings false for both)
        #expect(!MacMenu.item(.saveChanges, MacMenu.State(saveOpen: true)).enabled)
        // in Set up Navidrome's sheet, which holds Server settings' Connections page: its page is the one in front
        #expect(MacMenu.item(.saveChanges, MacMenu.State(sheet: true, serverSettings: true, saveOpen: true)).enabled)
        // File's alone: no Controls or View item
        #expect(!(MacMenu.controls(open) + MacMenu.view(open)).flatMap { $0 }.contains { $0.command == .saveChanges })
        // what Settings…, Find and Import EQ File… do is as it was with Server settings in front
        for command in [MacMenu.Command.settings, .find, .importEQFile, .refresh] {
            #expect(MacMenu.item(command, open) == MacMenu.item(command, MacMenu.State()), "\(command)")
        }
    }

    @Test func tabMovesToTheNextFieldInThePagesOrderAndLeavesTheEndsToTheSystem() {
        enum Field: Equatable { case artist, album, year, originalYear, edition }
        let release: [Field] = [.artist, .album, .year, .originalYear, .edition]
        #expect(MacMenu.tab(release, from: .artist, back: false) == .album)
        #expect(MacMenu.tab(release, from: .year, back: false) == .originalYear)
        #expect(MacMenu.tab(release, from: .year, back: true) == .album)
        // the ends: nothing of the page's - the key left to the system, which moves on out of the fields
        #expect(MacMenu.tab(release, from: .edition, back: false) == nil)
        #expect(MacMenu.tab(release, from: .artist, back: true) == nil)
        // no field of the page's with the cursor: the key isn't the page's at all
        #expect(MacMenu.tab(release, from: nil, back: false) == nil && MacMenu.tab(release, from: nil, back: true) == nil)
        #expect(MacMenu.tab([Field](), from: .artist, back: false) == nil)
        #expect(MacMenu.tab([Field.album], from: .artist, back: false) == nil)
        // from the first, Tab reaches every field once, in order; from the last, Shift-Tab every one back - each walk
        // held to one step past the fields, so a Tab that went round would fail here rather than walk for ever
        var at: Field? = .artist
        var forward: [Field] = []
        while let now = at, forward.count <= release.count {
            forward.append(now)
            at = MacMenu.tab(release, from: now, back: false)
        }
        #expect(forward == release)
        at = .edition
        var back: [Field] = []
        while let now = at, back.count <= release.count {
            back.append(now)
            at = MacMenu.tab(release, from: now, back: true)
        }
        #expect(back == release.reversed())
        // Edit tags' fields, in the order the page draws them - its four sections' - across each section's end
        let tags = TagEdit.sections.flatMap { (section: (title: String, keys: [String])) -> [String] in section.keys }
        #expect(tags.count == TagEdit.fields.count && Set(tags) == Set(TagEdit.fields.map(\.key)))
        #expect(MacMenu.tab(tags, from: "tracknumber", back: false) == "album")
        #expect(MacMenu.tab(tags, from: "album", back: true) == "tracknumber")
        #expect(MacMenu.tab(tags, from: "originaldate", back: false) == "genre")
        #expect(MacMenu.tab(tags, from: "composer", back: false) == nil && MacMenu.tab(tags, from: "title", back: true) == nil)
    }
}
