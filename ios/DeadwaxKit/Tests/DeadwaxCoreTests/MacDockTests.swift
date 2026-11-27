import Foundation
import Testing
@testable import DeadwaxCore

/// (R3) The Mac's side panel as a dock of tabs (MacDock.swift; notes/ios.md "The redesign, slice R3: the side panel's
/// tabs; the Now Playing sheet"): Queue, Lyrics, Info and EQ - Sources only with a Get page open - one at a time, a
/// tab's key closing the panel when that tab shows, Escape closing it, Info about the selection or else the song playing.
@Suite struct MacDockTests {
    private static let every: [MacDock.Tab?] = [nil] + MacDock.Tab.allCases

    @Test func theTabsAndTheirWords() {
        #expect(MacDock.tabs(getOpen: false) == [.upNext, .lyrics, .info, .eq])
        #expect(MacDock.tabs(getOpen: true) == [.sources, .upNext, .lyrics, .info, .eq])
        #expect(MacDock.tabs(getOpen: false).map(MacDock.Words.tab) == ["Queue", "Lyrics", "Info", "EQ"])
        #expect(MacDock.Words.tab(.sources) == "Sources")
        // each the app's own word for it, never retyped
        #expect(MacDock.Words.tab(.upNext) == UpNextWords.title && MacDock.Words.tab(.lyrics) == LyricsWords.lyrics)
        #expect(MacDock.Words.tab(.info) == InfoWords.title && MacDock.Words.tab(.eq) == EQWords.nowPlaying)
        // no two tabs share a name
        let names = MacDock.Tab.allCases.map(MacDock.Words.tab)
        #expect(Set(names).count == names.count)
    }

    /// (R16) The dock's own words for its pages' tops: a page's way back read as iOS reads its own back button, the
    /// page it goes back to first; and Lyrics' synced chip, in the drawing's own lower case.
    @Test func theDocksWayBackAndItsSyncedChip() {
        #expect(MacDock.Words.back(to: InfoWords.title) == "Info, Back")
        #expect(MacDock.Words.back(to: EQWords.nowPlaying) == "EQ, Back")
        #expect(MacDock.Words.synced == "synced")
        #expect(MacDock.Words.facts(["FLAC 16/44.1", "290 MB · 921 kbps"]) == "FLAC 16/44.1 · 290 MB · 921 kbps")
        #expect(MacDock.Words.facts([LevelWords.notKnown, " 24 MB "]) == "24 MB")
        #expect(MacDock.Words.facts([nil, "", "  "]) == "")
    }

    @Test func theWebsThreePanelsAreThreeOfTheTabs() {
        #expect(MacDock.Tab.allCases.compactMap(\.panel) == [.upNext, .lyrics, .info])
        #expect(MacDock.Tab.eq.panel == nil && MacDock.Tab.sources.panel == nil, "the Mac's own two")
        for tab in MacDock.Tab.allCases {
            if let panel = tab.panel { #expect(panel != MacFrame.Panel.none) }
        }
    }

    /// A tab's key, its View item, the bar's buttons: the panel closed when that tab is showing, switched to it
    /// otherwise - and only ever one tab.
    @Test func aTabsKeyClosesItsOwnAndSwitchesFromAnother() {
        for getOpen in [false, true] {
            for shown in Self.every {
                for asked in MacDock.Tab.allCases {
                    let after = MacDock.toggled(shown, asked, getOpen: getOpen)
                    if asked == shown {
                        #expect(after == nil, "\(String(describing: shown)) asked again: closed")
                    } else if asked == .sources && !getOpen {
                        #expect(after == shown, "Sources with no Get page: nothing changes")
                    } else {
                        #expect(after == asked, "\(String(describing: shown)) -> \(asked)")
                    }
                    // pressed again it closes - Sources' with none open aside
                    if after == asked { #expect(MacDock.toggled(after, asked, getOpen: getOpen) == nil) }
                }
            }
        }
        // the web's own rule for its three, to the letter
        for shown in MacFrame.Panel.allCases {
            for asked in MacFrame.Panel.allCases where asked != MacFrame.Panel.none {
                let tab = MacDock.Tab.allCases.first { $0.panel == shown }
                let askedTab = MacDock.Tab.allCases.first { $0.panel == asked }!
                #expect(MacDock.toggled(tab, askedTab, getOpen: false)?.panel ?? MacFrame.Panel.none == MacFrame.toggled(shown, asked))
            }
        }
    }

    /// (R19 - James's decision 1, 26 Nov) A folder tab clicked is a tab's key: the open one closes the panel, another is
    /// switched to - save Sources' open tab while its words are edited, which stays, as Escape leaves it then.
    @Test func aFolderTabClickedClosesTheOpenTabAndSwitchesFromAnother() {
        for getOpen in [false, true] {
            for shown in Self.every {
                for asked in MacDock.Tab.allCases {
                    let key = MacDock.toggled(shown, asked, getOpen: getOpen)
                    #expect(MacDock.clicked(shown, asked, getOpen: getOpen, sourcesEdited: false) == key)
                    let held = MacDock.clicked(shown, asked, getOpen: getOpen, sourcesEdited: true)
                    if asked == .sources && shown == .sources {
                        #expect(held == .sources, "Sources' edited words: its open tab's click does nothing")
                    } else {
                        #expect(held == key, "\(String(describing: shown)) -> \(asked): edited words hold no other")
                    }
                }
            }
        }
        #expect(MacDock.clicked(.sources, .sources, getOpen: true, sourcesEdited: false) == nil)
        #expect(MacDock.clicked(.upNext, .upNext, getOpen: true, sourcesEdited: true) == nil)
        #expect(MacDock.clicked(.sources, .upNext, getOpen: true, sourcesEdited: true) == .upNext)
    }

    /// The bar's ••• Info and EQ, Settings' Open the EQ: the tab, whatever was showing.
    @Test func aTabShownWhateverWasShowing() {
        for getOpen in [false, true] {
            for shown in Self.every {
                for asked in MacDock.Tab.allCases {
                    let after = MacDock.shown(shown, asked: asked, getOpen: getOpen)
                    #expect(after == (asked == .sources && !getOpen ? shown : asked))
                }
            }
        }
    }

    @Test func sourcesOnlyWithAGetPageOpen() {
        #expect(!MacDock.tabs(getOpen: false).contains(.sources))
        #expect(MacDock.tabs(getOpen: true).first == .sources)
        #expect(!MacDock.opens(.sources, getOpen: false) && MacDock.opens(.sources, getOpen: true))
        for tab in MacDock.Tab.allCases where tab != .sources {
            #expect(MacDock.opens(tab, getOpen: false) && MacDock.opens(tab, getOpen: true))
        }
        #expect(MacDock.toggled(nil, .sources, getOpen: false) == nil)
        #expect(MacDock.shown(.lyrics, asked: .sources, getOpen: false) == .lyrics)
        // the Get page gone: Sources goes with it, any other tab stays
        #expect(MacDock.kept(.sources, getOpen: false) == nil)
        #expect(MacDock.kept(.sources, getOpen: true) == .sources)
        for tab in Self.every where tab != .sources {
            #expect(MacDock.kept(tab, getOpen: false) == tab && MacDock.kept(tab, getOpen: true) == tab)
        }
    }

    /// (R7) The dock's Get lasts only while its page is the one in front: another page, another tab's, or none ends it.
    @Test func theDocksGetLastsOnlyWhileItsPageIsInFront() {
        #expect(MacDock.getLasts("group:a", front: "group:a"))
        #expect(!MacDock.getLasts("group:a", front: "artist:b"))
        #expect(!MacDock.getLasts("group:a", front: "group:b"))
        #expect(!MacDock.getLasts("group:a", front: nil))
        // and the tab goes with it: Sources isn't kept once no Get is open, whichever tab was showing
        #expect(MacDock.kept(.sources, getOpen: false) == nil && MacDock.kept(.upNext, getOpen: false) == .upNext)
    }

    /// (R7's review) Another pressing chosen on its page ends the dock's Get: its Get is for the pressing it was asked for.
    @Test func theDocksGetStandsOnlyForThePressingItWasAskedFor() {
        #expect(MacDock.getStands(asked: "re-1997", chosen: "re-1997"))
        #expect(!MacDock.getStands(asked: "re-1997", chosen: "re-2008"), "another pressing chosen")
        #expect(!MacDock.getStands(asked: "re-1997", chosen: nil), "none chosen")
        #expect(!MacDock.getStands(asked: nil, chosen: nil) && !MacDock.getStands(asked: nil, chosen: "re-1997"))
    }

    @Test func escapeClosesThePanelAfterAFieldAndBeforeThePage() {
        for shown in Self.every {
            #expect(MacDock.escape(typing: true, shown: shown) == .field, "a field with the cursor first")
            #expect(MacDock.escape(typing: false, shown: shown) == (shown == nil ? .page : .panel))
        }
        // the web's three as MacFrame has them
        for panel in MacFrame.Panel.allCases {
            let tab = MacDock.Tab.allCases.first { $0.panel == panel }
            for typing in [false, true] {
                #expect(MacDock.escape(typing: typing, shown: tab) == MacFrame.escape(typing: typing, panel: panel))
            }
        }
        // under the name its owners call it by, with the dock's tab: the same rule, the EQ's and Sources' too
        for shown in Self.every {
            for typing in [false, true] {
                #expect(MacFrame.escape(typing: typing, panel: shown) == MacDock.escape(typing: typing, shown: shown))
            }
        }
        #expect(MacFrame.escape(typing: false, panel: MacDock.Tab.eq) == .panel, "the EQ's tab owns it as the others do")
    }

    @Test func theQueueEndingTakesQueueAndInfoWithoutASelection() {
        #expect(MacDock.afterQueueEnds(.upNext, selected: false) == nil)
        #expect(MacDock.afterQueueEnds(.upNext, selected: true) == nil)
        #expect(MacDock.afterQueueEnds(.info, selected: false) == nil)
        #expect(MacDock.afterQueueEnds(.info, selected: true) == .info, "about the row selected, it stays")
        for tab: MacDock.Tab? in [.lyrics, .eq, .sources, nil] {
            for selected in [false, true] {
                #expect(MacDock.afterQueueEnds(tab, selected: selected) == tab)
            }
        }
        // the web's three as MacFrame has them, nothing selected
        for panel in MacFrame.Panel.allCases {
            let tab = MacDock.Tab.allCases.first { $0.panel == panel }
            #expect(MacDock.afterQueueEnds(tab, selected: false)?.panel ?? MacFrame.Panel.none == MacFrame.afterQueueEnds(panel))
        }
    }

    @Test func aColumnMakesRoomADrawerLiesOver() {
        for style in MacFrame.PanelStyle.allCases {
            for shown in Self.every {
                #expect(MacDock.makesRoom(style, shown) == (style == .column && shown != nil))
                #expect(MacDock.liesOver(style, shown) == (style == .drawer && shown != nil))
            }
        }
        // beside the page from 1280 wide, over it below that - never a sheet on the Mac
        #expect(MacFrame.panelStyle(width: 1280) == .column && MacFrame.panelStyle(width: 1279) == .drawer)
        #expect(MacFrame.panelStyle(width: MacFrame.smallestWidth) == .drawer)
        #expect(MacLook.panelWidth == 400)
    }

    /// Section 7's answer 2 (James, 24 Nov: "Selection, else playing").
    @Test func infoIsAboutTheSelectionElseTheSongPlaying() {
        for playing in [false, true] {
            #expect(MacDock.infoSubject(selected: .album, playing: playing) == .selected(.album))
            #expect(MacDock.infoSubject(selected: .artist, playing: playing) == .selected(.artist))
        }
        #expect(MacDock.infoSubject(selected: nil, playing: true) == .playing)
        #expect(MacDock.infoSubject(selected: nil, playing: false) == .nothing)
        // and its heading says which
        #expect(MacDock.Words.heading(.selected(.album)) == "Selected album")
        #expect(MacDock.Words.heading(.selected(.artist)) == "Selected artist")
        #expect(MacDock.Words.heading(.playing) == "Playing")
        #expect(MacDock.Words.heading(.nothing) == nil)
        // the selected artist's page, worded as Info's Go to album
        #expect(MacDock.Words.goToArtist == "Go to artist" && NowPlayingWords.goToAlbum == "Go to album")
    }

    /// R3's review: a tab with nothing to be about says so, never a blank page with no heading - the Queue with nothing
    /// queued, Info with nothing selected and nothing playing.
    @Test func aTabWithNothingToBeAboutSaysSo() {
        for tab in MacDock.Tab.allCases {
            for playing in [false, true] {
                for selected in [false, true] {
                    let empty = MacDock.empty(tab, playing: playing, selected: selected)
                    switch tab {
                    case .upNext:
                        #expect(empty == (playing ? nil : "Nothing playing"), "the Queue, playing \(playing)")
                    case .info:
                        #expect((empty == nil) == (MacDock.infoSubject(selected: selected ? .artist : nil,
                                                                       playing: playing) != .nothing))
                        #expect(empty == (playing || selected ? nil : "Nothing playing"), "Info, \(playing) \(selected)")
                    case .lyrics, .eq, .sources:
                        #expect(empty == nil, "\(tab): its own page")
                    }
                }
            }
        }
        // Lyrics' words then, and the bar's
        #expect(MacDock.Words.nothingPlaying == LyricsWords.nothingPlaying)
        // Info's empty is exactly when it has no heading: never a page without one
        for playing in [false, true] {
            for selected in [false, true] {
                let subject = MacDock.infoSubject(selected: selected ? .album : nil, playing: playing)
                #expect((MacDock.Words.heading(subject) == nil) == (MacDock.empty(.info, playing: playing,
                                                                                   selected: selected) != nil))
            }
        }
    }

    /// R3's review: one EQ - a shared file on the Mac shows in the dock's EQ tab, never a second EQ page over it; the
    /// phone's path as it was (Now Playing's sheet while it is up, else the EQ sheet over the tabs).
    @Test func aSharedEQFileShowsInTheOneEQ() {
        for shown in [false, true] {
            #expect(SharedEQFile.shows(device: .mac, nowPlayingShown: shown) == .dock)
        }
        #expect(SharedEQFile.shows(device: .iPhone, nowPlayingShown: true) == .nowPlaying)
        #expect(SharedEQFile.shows(device: .iPhone, nowPlayingShown: false) == .sheet)
        for device in Device.allCases {
            #expect((SharedEQFile.shows(device: device, nowPlayingShown: false) == .dock) == MacFrame.drawsDesktop(device))
        }
    }
}
