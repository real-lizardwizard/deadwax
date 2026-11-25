import DeadwaxCore
import SwiftUI

/// Now Playing's one sheet on the phone (the redesign, slice R3 - notes/ios.md "The redesign, slice R3: the side panel's
/// tabs; the Now Playing sheet"; iQueue.dc.html, iInfo.dc.html, iEQ.dc.html), in place of its three - Up Next, Info and
/// the EQ: the tab's page, each with `‹ Now Playing` at its top (PhoneBack - the sheet put down, Now Playing under it)
/// and the one-tap strip of the tabs under that (PhoneStrip: Queue, Info, EQ - NowPlayingTabs.strip; no Lyrics, which
/// take the cover's place - James, 25 Nov: "The cover's place"). (R3b) Each page is redrawn as its drawing has it - the
/// Queue (UpNextScreen), Info (InfoView) and the EQ (EQSheet, its own stack and a shared file's preview over it once it
/// has been up 400 ms, eq.md 3.9's wait) - and each puts its own buttons at the top's right (`sheetTop`).
///
/// One sheet: a tab tapped in the strip, a button of Now Playing's bottom row or a file shared to deadwax moves it to its
/// tab in place (`tab`, Now Playing's) - nothing it held lost to a close, and never a second sheet over it. (R3b) Info's
/// About or Debug is the sheet's, so the strip's taps keep it.
struct NowPlayingSheet: View {
    @Binding var tab: NowPlayingTabs.Tab

    /// The sheet's own (read outside every page's stack, so it puts the sheet down rather than popping a page).
    @Environment(\.dismiss) private var dismiss
    /// (R3b) Info's About or Debug, kept while another tab shows (R3's review, 9).
    @State private var infoTab: InfoTab = .about

    var body: some View {
        let top = SheetTop(tab: $tab, close: dismiss)
        //? one tab's page at a time, and only the one shown: the tab is the page drawn
        Group {
            switch tab {
            case .upNext:
                UpNextScreen(sheet: top)
            case .info:
                InfoView(sheet: top, picked: $infoTab)
            case .eq:
                EQSheet(sheet: top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // the drawings' ground (`.dw.ph`'s sheets): the panel's, under every page and its top alike
        .presentationBackground(DWPalette.panel)
    }
}

/// (R3b) What a page in Now Playing's sheet is handed: the tab the strip shows, and the sheet's own put-down - read
/// outside every page's stack, so `‹ Now Playing` puts the sheet down rather than popping a page.
struct SheetTop {
    let tab: Binding<NowPlayingTabs.Tab>
    let close: DismissAction
}

extension View {
    /// (R3b) A page's top in Now Playing's sheet (iQueue, iInfo, iEQ's `.topbar` and `.chips`): `‹ Now Playing` at its
    /// left, `trailing` - the page's own buttons - at its right, and the strip under it. The top is the page's stack's own
    /// bar, so a page pushed on it (Album info, the EQ's pages) has its own bar and Back as before, and the strip is the
    /// root page's first row - the tabs are moved between from a tab's own page. iOS 26's glass behind the top's two is
    /// taken away (the phone is square); the two capped at xxxLarge, as PhoneTop is.
    func sheetTop<Trailing: View>(_ top: SheetTop, @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(SheetTopBar(top: top, trailing: trailing()))
    }
}

private struct SheetTopBar<Trailing: View>: ViewModifier {
    let top: SheetTop
    let trailing: Trailing

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            PhoneStrip(options: NowPlayingTabs.strip, words: NowPlayingTabs.Words.tab, shown: top.tab,
                       spoken: NowPlayingTabs.Words.spoken)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheetTopItems(SheetTopItems(leading: PhoneBack(words: NowPlayingTabs.Words.back) { top.close() },
                                     trailing: trailing))
    }
}

/// The top's two: `‹ Now Playing` leading, the page's own trailing.
private struct SheetTopItems<Leading: View, Trailing: View>: ToolbarContent {
    let leading: Leading
    let trailing: Trailing

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            leading
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: CGFloat(PhoneLook.topGap)) {
                trailing
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

extension View {
    /// The top's items in the bar - on iOS 26 and later with no glass behind them, as the drawings' top has none.
    @ViewBuilder
    fileprivate func sheetTopItems<Leading: View, Trailing: View>(_ items: SheetTopItems<Leading, Trailing>) -> some View {
        if #available(iOS 26.0, *) {
            toolbar { items.sharedBackgroundVisibility(.hidden) }
        } else {
            toolbar { items }
        }
    }
}
