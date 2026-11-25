import Foundation

// Now Playing's one sheet and its bottom row on the phone (the redesign, slice R3 - notes/ios.md "The redesign, slice
// R3: the side panel's tabs; the Now Playing sheet"; iNowPlaying.dc.html, iQueue.dc.html, iInfo.dc.html, iEQ.dc.html):
//
// - The sheet (NowPlayingSheet) replaces Now Playing's three - Up Next, Info and the EQ: `‹ Now Playing` at its top,
//   then the one-tap strip of its tabs, Queue, Info and EQ. James, 25 Nov (the build plan's 3.8, answer 2, "The cover's
//   place"): Lyrics is no tab of the sheet - the lyrics take the cover's place, as they do now, and the bottom row's
//   Lyrics turns them on and off.
// - The bottom row (in place of the footer): five labelled icons, as the tab bar's items with no bar - Queue, Lyrics,
//   the output (AirPlay, named for where the music plays), Info, EQ. Queue, Info and EQ open the sheet on their tab.
// - A file shared to deadwax while Now Playing is up (eq.md 3.9) opens the sheet on EQ, the import's preview over it: the
//   sheet up on another tab moves to EQ in place - nothing it held is lost to a close - and the cover full screen is
//   closed first, the sheet opening once it has gone (the wait kept).

public enum NowPlayingTabs {
    /// The sheet's tabs, in the strip's order. `upNext` is the Queue (James, 25 Nov: "Queue on both" - the word changed,
    /// the names kept).
    public enum Tab: String, Sendable, CaseIterable {
        case upNext
        case info
        case eq
    }

    /// The strip: Queue, Info, EQ - and no Lyrics (answer 2).
    public static let strip: [Tab] = [.upNext, .info, .eq]

    /// The bottom row's five, in order (iNowPlaying.dc.html).
    public enum Button: String, Sendable, CaseIterable {
        case upNext
        case lyrics
        case output
        case info
        case eq
    }

    /// The row, left to right: Queue, Lyrics, the output, Info, EQ.
    public static let row: [Button] = [.upNext, .lyrics, .output, .info, .eq]

    /// What a button of the row does.
    public enum Opens: Sendable, Equatable {
        /// The sheet, on this tab - or the sheet already up moved to it.
        case tab(Tab)
        /// The lyrics in the cover's place, turned on or off - never the sheet (answer 2).
        case lyrics
        /// The system's route picker (AirPlay): the output's column is AVRoutePickerView's own button.
        case output
    }

    /// Which button opens which.
    public static func opens(_ button: Button) -> Opens {
        switch button {
        case .upNext: return .tab(.upNext)
        case .lyrics: return .lyrics
        case .output: return .output
        case .info: return .tab(.info)
        case .eq: return .tab(.eq)
        }
    }

    /// The two buttons the speed chip sits between (turntable.md 5.1: over the gap, so nothing in the row moves as it
    /// comes and goes): the output and Info.
    public static let chipBetween: (Button, Button) = (.output, .info)

    /// (R3's review) Where across the row the chip is centred, as a share of its width: on the line between the output's
    /// column and Info's - the row's five are equal columns - in a band of its own just above the row, so its target
    /// overlaps neither the row's nor the transport's (tests/test_ios_nowplaying_row.py works the frames out).
    public static var chipAt: Double {
        guard let left = row.firstIndex(of: chipBetween.0) else { return 0.5 }
        return Double(left + 1) / Double(row.count)
    }

    /// What a file shared to deadwax does while Now Playing is up (eq.md 3.9).
    public enum Shared: Sendable, Equatable {
        /// The sheet shows this tab: opened on it, or - up already, on whichever tab - moved to it in place.
        case show(Tab)
        /// The cover full screen is up: it is closed first, and the sheet opens on this tab once it has gone.
        case waitThenShow(Tab)
    }

    /// A shared EQ file, with the sheet up on `sheet` (nil: no sheet) and the cover full screen up or not: always the EQ
    /// - never lost under the Queue or Info, which are moved from in place rather than closed.
    public static func shared(sheet: Tab?, coverUp: Bool) -> Shared {
        if sheet == nil && coverUp { return .waitThenShow(.eq) }
        return .show(.eq)
    }

    /// The SF Symbol each icon of the row is drawn with (the app's own glyphs, filled where on) - (R3's review) the
    /// output's too: AirPlay's own button lies under the whole column, its glyph hidden, so the column takes the tap as
    /// the other four do, and the glyph drawn over it is AirPlay's audio glyph, the one the picker drew.
    public static func symbol(_ button: Button, on: Bool = false) -> String? {
        switch button {
        case .upNext: return "list.bullet"
        case .lyrics: return on ? "quote.bubble.fill" : "quote.bubble"
        case .output: return "airplayaudio"
        case .info: return "info.circle"
        case .eq: return "slider.vertical.3"
        }
    }

    /// The sheet's and the row's words: the app's own for each, never retyped.
    public enum Words {
        /// The sheet's back link, to Now Playing under it (`‹ Now Playing`).
        public static let back = "Now Playing"
        /// What VoiceOver calls the strip.
        public static let spoken = "Now Playing's pages"

        /// A tab's name in the strip: Queue (Up Next's own word), Info, EQ.
        public static func tab(_ tab: Tab) -> String {
            switch tab {
            case .upNext: return UpNextWords.title
            case .info: return InfoWords.title
            case .eq: return EQWords.nowPlaying
            }
        }

        /// What VoiceOver calls the row's EQ: its word and the output now's setting, as the ••• item it was carried
        /// them ("EQ, Bass Boost").
        public static func eq(setting: String) -> String { "\(EQWords.nowPlaying), \(setting)" }

        /// A button's words under its icon - nil for the output, which is named for the route it plays to.
        public static func button(_ button: Button) -> String? {
            switch button {
            case .upNext: return UpNextWords.title
            case .lyrics: return LyricsWords.lyrics
            case .output: return nil
            case .info: return InfoWords.title
            case .eq: return EQWords.nowPlaying
            }
        }
    }
}
