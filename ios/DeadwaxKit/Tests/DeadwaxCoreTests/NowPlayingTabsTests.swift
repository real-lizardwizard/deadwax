import Foundation
import Testing
@testable import DeadwaxCore

/// (R3) Now Playing's one sheet and its bottom row on the phone (NowPlayingTabs.swift; notes/ios.md "The redesign,
/// slice R3: the side panel's tabs; the Now Playing sheet").
@Suite struct NowPlayingTabsTests {
    @Test func theStripIsQueueInfoAndEQWithNoLyrics() {
        #expect(NowPlayingTabs.strip == [.upNext, .info, .eq])
        #expect(NowPlayingTabs.strip == NowPlayingTabs.Tab.allCases)
        #expect(NowPlayingTabs.strip.map(NowPlayingTabs.Words.tab) == ["Queue", "Info", "EQ"])
        // James, 25 Nov (3.8, answer 2, "The cover's place"): Lyrics is no tab of the phone's sheet
        #expect(!NowPlayingTabs.strip.map(NowPlayingTabs.Words.tab).contains(LyricsWords.lyrics))
        #expect(NowPlayingTabs.Words.back == "Now Playing")
    }

    @Test func theRowIsFiveLabelledIconsInOrder() {
        #expect(NowPlayingTabs.row == [.upNext, .lyrics, .output, .info, .eq])
        #expect(NowPlayingTabs.row == NowPlayingTabs.Button.allCases)
        #expect(NowPlayingTabs.row.map(NowPlayingTabs.Words.button) == ["Queue", "Lyrics", nil, "Info", "EQ"])
        // every icon is the app's glyph - (R3's review) the output's too, drawn over AirPlay's own button, whose glyph
        // is hidden under it: AirPlay's audio glyph, the one the picker drew
        for button in NowPlayingTabs.row {
            #expect(NowPlayingTabs.symbol(button) != nil, "\(button)")
        }
        #expect(NowPlayingTabs.symbol(.output) == "airplayaudio")
        #expect(Set(NowPlayingTabs.row.compactMap { NowPlayingTabs.symbol($0) }).count == NowPlayingTabs.row.count)
        #expect(NowPlayingTabs.symbol(.lyrics, on: true) == "quote.bubble.fill")
        #expect(NowPlayingTabs.symbol(.lyrics, on: false) == "quote.bubble")
        // the EQ's VoiceOver name carries the output's setting, as the ••• item's subtitle did
        #expect(NowPlayingTabs.Words.eq(setting: "Bass Boost") == "EQ, Bass Boost")
    }

    /// Which button opens which: Queue, Info and EQ the sheet on their tab; Lyrics never the sheet - the cover's place.
    @Test func whichButtonOpensWhich() {
        #expect(NowPlayingTabs.opens(.upNext) == .tab(.upNext))
        #expect(NowPlayingTabs.opens(.info) == .tab(.info))
        #expect(NowPlayingTabs.opens(.eq) == .tab(.eq))
        #expect(NowPlayingTabs.opens(.lyrics) == .lyrics)
        #expect(NowPlayingTabs.opens(.output) == .output)
        // every tab of the strip has its button, and no button opens a tab the strip hasn't
        let opened = NowPlayingTabs.row.compactMap { button -> NowPlayingTabs.Tab? in
            if case .tab(let tab) = NowPlayingTabs.opens(button) { return tab }
            return nil
        }
        #expect(opened == NowPlayingTabs.strip)
        // each button's words are its tab's
        for button in NowPlayingTabs.row {
            if case .tab(let tab) = NowPlayingTabs.opens(button) {
                #expect(NowPlayingTabs.Words.button(button) == NowPlayingTabs.Words.tab(tab))
            }
        }
    }

    @Test func theSpeedChipSitsBetweenTheOutputAndInfo() {
        let (left, right) = NowPlayingTabs.chipBetween
        #expect(left == .output && right == .info)
        let at = NowPlayingTabs.row.firstIndex(of: left)!
        #expect(NowPlayingTabs.row[at + 1] == right, "neighbours: over the gap between them")
        // (R3's review) centred on the line between their columns: the output's is the third of five, so 3/5 across -
        // past the output's centre (2.5/5) and short of Info's (3.5/5)
        #expect(NowPlayingTabs.chipAt == 0.6)
        let count = Double(NowPlayingTabs.row.count)
        #expect(NowPlayingTabs.chipAt > (Double(at) + 0.5) / count && NowPlayingTabs.chipAt < (Double(at) + 1.5) / count)
    }

    /// eq.md 3.9 kept: a shared EQ file opens the sheet on EQ - never lost under Queue or Info, which are moved from in
    /// place - and waits for the cover full screen to go.
    @Test func aSharedEQFileOpensTheSheetOnEQ() {
        for sheet: NowPlayingTabs.Tab? in [nil] + NowPlayingTabs.Tab.allCases {
            for coverUp in [false, true] {
                let shared = NowPlayingTabs.shared(sheet: sheet, coverUp: coverUp)
                switch shared {
                case .show(let tab), .waitThenShow(let tab):
                    #expect(tab == .eq, "\(String(describing: sheet)), cover \(coverUp): on EQ")
                }
                if sheet == nil && coverUp {
                    #expect(shared == .waitThenShow(.eq), "the cover closed first, then the sheet")
                } else {
                    #expect(shared == .show(.eq), "\(String(describing: sheet)): moved to EQ in place")
                }
            }
        }
    }
}
