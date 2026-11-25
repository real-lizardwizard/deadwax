import DeadwaxCore
import SwiftUI

/// Now Playing's one sheet on the phone (the redesign, slice R3 - notes/ios.md "The redesign, slice R3: the side panel's
/// tabs; the Now Playing sheet"; iQueue.dc.html, iInfo.dc.html, iEQ.dc.html), in place of its three - Up Next, Info and
/// the EQ: `‹ Now Playing` at its top (PhoneBack - the sheet put down, Now Playing under it), the one-tap strip of its
/// tabs under that (PhoneStrip: Queue, Info, EQ - NowPlayingTabs.strip; no Lyrics, which take the cover's place - James,
/// 25 Nov: "The cover's place"), then the tab's page. Each page is today's until R3b redraws it: the Queue (UpNextScreen),
/// Info (InfoView) and the EQ (EQSheet - its own stack, its Done, and a shared file's preview over it once it has been up
/// 400 ms, eq.md 3.9's wait). Their Done puts the sheet down, as before.
///
/// One sheet: a tab tapped in the strip, a button of Now Playing's bottom row or a file shared to deadwax moves it to its
/// tab in place (`tab`, Now Playing's) - nothing it held lost to a close, and never a second sheet over it.
struct NowPlayingSheet: View {
    @Binding var tab: NowPlayingTabs.Tab

    /// The sheet's own (read outside every page's stack, so it puts the sheet down rather than popping a page).
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            PhoneTop(leading: {
                PhoneBack(words: NowPlayingTabs.Words.back) { dismiss() }
            }, trailing: {
                EmptyView()
            })
            PhoneStrip(options: NowPlayingTabs.strip, words: NowPlayingTabs.Words.tab, shown: $tab,
                       spoken: NowPlayingTabs.Words.spoken)
            //? one tab's page at a time, and only the one shown: the tab is the page drawn
            Group {
                switch tab {
                case .upNext:
                    UpNextScreen()
                case .info:
                    InfoView()
                case .eq:
                    EQSheet()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
