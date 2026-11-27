import Foundation

// The Mac's side panel as a dock of folder tabs (the Mac redesign, slice R3 - notes/ios.md "The redesign, slice R3: the
// side panel's tabs; the Now Playing sheet"; dw.css's .panel and .tabs, Albums.dc.html and Get.dc.html): Queue, Lyrics,
// Info and EQ, and Sources while a Get page is open - one tab at a time, MacLook.panelWidth (400) wide, beside the page
// in a window 1280 wide or more and over the page's right edge below that (MacFrame.panelStyle). Never modal.
//
// Three of its tabs are the web's three panels (MacFrame.Panel's upnext, lyrics and info - `Tab.panel`), and keep the
// web's rules, held by its vectors (MacFrameVectorTests): one at a time, a third column makes room and a drawer lies
// over, Queue and Info go with the queue. The EQ (a sheet on the Mac until now) and Sources (R7's) are the Mac's own.
//
// - A tab's key - View > Queue (⌥⌘U), Lyrics (⌥⌘L), Info (⌘I), EQ (⌥⌘E), MacMenu's - and the player bar's buttons
//   close the panel when that tab is the one showing, and switch to it otherwise (`toggled`). A folder tab clicked, the
//   bar's ••• Info and EQ and Settings' EQ show their tab, whatever was showing (`shown`).
// - Escape closes it: after a text field with the cursor, before the page's own Escape (`escape` - MacFrame's one owner).
// - Info's subject is the selection on the page in front, or the song playing while nothing is selected (James, 24 Nov:
//   "Selection, else playing"), and its heading says which (`infoSubject`, `Words.heading`).
// - Sources is drawn only while a Get page is open (`tabs`): it never opens without one, and goes as the page does.
//   (R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)") Its Get is the one Get the
//   album asked for on the Mac, in the dock rather than a sheet: it lasts only while its own page is the one in front
//   (`getLasts`) - a tab chosen, a page pushed over it, the page popped or the person changing ends it, its search let
//   go and the tab gone with it (`kept`).
// - (R3's review) A tab with nothing to be about says so in words, its page not drawn (`empty`): the Queue with nothing
//   queued, Info with nothing selected and nothing playing - a folder tab clicked to either, or Info's selection gone.
// - (R3's review) A file shared to deadwax, or chosen in File > Import EQ File…, shows its preview over the dock's EQ tab
//   on the Mac - one EQ, never a second EQ page over the first (slice 3's review) - and on the phone as before
//   (`SharedEQFile`).

public enum MacDock {
    /// The dock's tabs. The three the web has are named as the web names its panels - `upNext` is the Queue (James, 25
    /// Nov: "Queue on both" - the word changed, the names kept).
    public enum Tab: String, Sendable, CaseIterable {
        case sources
        case upNext
        case lyrics
        case info
        case eq

        /// The web's panel this tab is (MacFrame.Panel): Queue, Lyrics and Info are; the EQ and Sources, the Mac's own, nil.
        public var panel: MacFrame.Panel? {
            switch self {
            case .upNext: return .upNext
            case .lyrics: return .lyrics
            case .info: return .info
            case .eq, .sources: return nil
            }
        }
    }

    /// The tabs drawn, in order (Get.dc.html, Albums.dc.html): Sources first while a Get page is open, then Queue,
    /// Lyrics, Info and the EQ.
    public static func tabs(getOpen: Bool) -> [Tab] {
        (getOpen ? [.sources] : []) + [.upNext, .lyrics, .info, .eq]
    }

    /// A tab's key, its View item or the bar's button (`asked`), with `shown` showing (nil: the panel closed): the panel
    /// closed when it was the one showing, else `asked` - one tab at a time. Sources is never opened without a Get page:
    /// asked with none, nothing changes.
    public static func toggled(_ shown: Tab?, _ asked: Tab, getOpen: Bool) -> Tab? {
        if asked == shown { return nil }
        return opens(asked, getOpen: getOpen) ? asked : shown
    }

    /// A tab shown whatever was showing - its folder tab clicked, the bar's ••• Info or EQ, Settings' EQ: `asked`, and
    /// one tab at a time. Sources not without a Get page.
    public static func shown(_ shown: Tab?, asked: Tab, getOpen: Bool) -> Tab? {
        opens(asked, getOpen: getOpen) ? asked : shown
    }

    /// Whether `tab` can be opened now: every tab but Sources, and Sources while a Get page is open.
    public static func opens(_ tab: Tab, getOpen: Bool) -> Bool {
        tab != .sources || getOpen
    }

    /// The tab still showing once a Get page has gone (`getOpen` false): Sources goes with it, the panel closed; any
    /// other tab stays as it was.
    public static func kept(_ shown: Tab?, getOpen: Bool) -> Tab? {
        shown == .sources && !getOpen ? nil : shown
    }

    /// (R7) Whether the dock's Get lasts as the page in front moves: only while `front` - the page now in front of the tab
    /// shown - is the page it was asked from. Anything else in front (another tab, a page over it, its page popped) ends
    /// it, so a search never runs on, nor picks, for a page no longer there.
    public static func getLasts<Page: Equatable>(_ page: Page, front: Page?) -> Bool {
        front == page
    }

    /// (R7's review) Whether the dock's Get stands as its page's chosen pressing changes: only while the pressing it was
    /// asked for (`asked`) is still the one chosen. Another chosen ends it - its cards and its Get are for the pressing
    /// asked, so they can never download one the page no longer shows; a Get for no pressing never stands.
    public static func getStands(asked: String?, chosen: String?) -> Bool {
        asked != nil && asked == chosen
    }

    /// The tab showing once nothing is queued: Queue goes with the queue, as the web's panel does, and Info - unless a
    /// row is selected, which Info is about while one is (`infoSubject`); Lyrics stays, saying "Nothing playing", as the
    /// web's does (MacFrame.afterQueueEnds); the EQ and Sources aren't the queue's, and stay.
    public static func afterQueueEnds(_ shown: Tab?, selected: Bool) -> Tab? {
        switch shown {
        case .upNext?: return nil
        case .info?: return selected ? .info : nil
        case .lyrics?, .eq?, .sources?, nil: return shown
        }
    }

    /// Whether the page makes room for the panel: a third column showing a tab does, a drawer lies over it (MacFrame's
    /// makesRoom, for every tab).
    public static func makesRoom(_ style: MacFrame.PanelStyle, _ shown: Tab?) -> Bool {
        style == .column && shown != nil
    }

    /// Whether the panel lies over the page's right edge - a drawer, showing a tab (MacFrame's liesOver): put away as an
    /// album is opened from the player.
    public static func liesOver(_ style: MacFrame.PanelStyle, _ shown: Tab?) -> Bool {
        style == .drawer && shown != nil
    }

    /// Escape's one owner with the dock (MacFrame.escape's order): a text field with the cursor first, then the panel -
    /// whichever tab shows - then the page.
    public static func escape(typing: Bool, shown: Tab?) -> MacFrame.Escape {
        if typing { return .field }
        return shown == nil ? .page : .panel
    }

    /// What a list on the page in front has selected (MacSelection's subject's kind).
    public enum Selected: String, Sendable, CaseIterable {
        case album, artist
    }

    /// What Info is about.
    public enum Subject: Sendable, Equatable {
        /// The row selected on the page in front.
        case selected(Selected)
        /// The song playing: nothing is selected.
        case playing
        /// Nothing selected and nothing playing.
        case nothing
    }

    /// Info's subject (James, 24 Nov, section 7's answer 2: "Selection, else playing"): the selection on a page with a
    /// list - whatever is playing - else the song playing, else nothing.
    public static func infoSubject(selected: Selected?, playing: Bool) -> Subject {
        if let selected { return .selected(selected) }
        return playing ? .playing : .nothing
    }

    /// (R3's review) What a tab says in its page's place when it has nothing to be about - nil: its page. The Queue
    /// with nothing queued, and Info with nothing selected and nothing playing (`infoSubject`'s `nothing`), say
    /// "Nothing playing" - Lyrics' words then, and the bar's - so a folder tab clicked to either, or Info's selection
    /// gone, never draws a blank page with no heading. Lyrics says its own (LyricsPanel); the EQ and Sources aren't the
    /// queue's.
    public static func empty(_ tab: Tab, playing: Bool, selected: Bool) -> String? {
        switch tab {
        case .upNext: return playing ? nil : Words.nothingPlaying
        case .info: return infoSubject(selected: selected ? .album : nil, playing: playing) == .nothing
            ? Words.nothingPlaying : nil
        case .lyrics, .eq, .sources: return nil
        }
    }

    /// The dock's words: each tab's name is the app's own word for it, never retyped.
    public enum Words {
        /// What VoiceOver calls the strip of tabs.
        public static let spoken = "Side panel"
        /// The headings Info's page carries, saying what it is about.
        public static let selectedAlbum = "Selected album"
        public static let selectedArtist = "Selected artist"
        public static let playing = "Playing"
        /// The selected artist's Info: their page (as Info's "Go to album" goes to the album's).
        public static let goToArtist = "Go to artist"
        /// (R3's review) A tab with nothing to be about (`empty`): Lyrics' own words for it, and the player bar's.
        public static let nothingPlaying = LyricsWords.nothingPlaying

        /// A tab's name on its folder tab: the View menu's words for the four (Queue is Up Next's own word), and Sources.
        public static func tab(_ tab: Tab) -> String {
            switch tab {
            case .sources: return sources
            case .upNext: return UpNextWords.title
            case .lyrics: return LyricsWords.lyrics
            case .info: return InfoWords.title
            case .eq: return EQWords.nowPlaying
            }
        }

        /// The Sources tab (Get.dc.html's): the sources found for the album being got.
        public static let sources = "Sources"

        /// (R16) What VoiceOver calls a page's way back inside the dock (DockBack, "‹ Info"): the page it goes back to,
        /// then "Back", as iOS's own back button is read ("Info, Back").
        public static func back(to page: String) -> String {
            "\(page), Back"
        }

        /// (R16) Lyrics' chip in the dock's header while the song's lines are synced (Playlist.dc.html's panel).
        public static let synced = "synced"

        /// (R16) Info's line of facts under a song's name in the dock (Albums.dc.html's "FLAC 16/44.1 · 290 MB"): the
        /// parts known, " · " between them - none empty, none "Not known" - and "" for none.
        public static func facts(_ parts: [String?]) -> String {
            parts.compactMap { (part: String?) -> String? in
                guard let part = part?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !part.isEmpty, part != LevelWords.notKnown else { return nil }
                return part
            }.joined(separator: " · ")
        }

        /// Info's heading - what it is about: the selected album, the selected artist, or the song playing; none with
        /// nothing.
        public static func heading(_ subject: Subject) -> String? {
            switch subject {
            case .selected(.album): return selectedAlbum
            case .selected(.artist): return selectedArtist
            case .playing: return playing
            case .nothing: return nil
            }
        }
    }
}

/// (R3's review) Where a file shared to deadwax shows its preview (eq.md 3.9) - Finder's Open With, the share sheet, a
/// drop on the window or File > Import EQ File… on the Mac. One EQ at a time (slice 3's review): on the Mac the dock's
/// EQ tab, shown whatever was showing, the preview over it - never the EQ sheet over the window, a second EQ page over
/// the dock's; on the phone, Now Playing's sheet while Now Playing is up (NowPlayingTabs.shared), else the EQ sheet
/// over the tabs - as before. (A preview already up shows it in place, before any of these.)
public enum SharedEQFile: Sendable, Equatable {
    /// The Mac: the dock's EQ tab.
    case dock
    /// The phone with Now Playing up: its sheet, on EQ.
    case nowPlaying
    /// The phone with Now Playing shut: the EQ sheet over the tabs.
    case sheet

    public static func shows(device: Device, nowPlayingShown: Bool) -> SharedEQFile {
        if MacFrame.drawsDesktop(device) { return .dock }
        return nowPlayingShown ? .nowPlaying : .sheet
    }
}

extension MacFrame {
    /// Escape's one owner with the dock's tab showing (nil: the panel closed) - MacDock.escape, under the name every
    /// owner of it calls (a panel's Done, a playlist's Edit Cancel): the Queue's, Info's, Lyrics' and the EQ's Done own
    /// it while their tab shows, the page while none does.
    public static func escape(typing: Bool, panel: MacDock.Tab?) -> Escape {
        MacDock.escape(typing: typing, shown: panel)
    }
}
