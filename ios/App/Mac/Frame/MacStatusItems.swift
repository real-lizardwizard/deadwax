import DeadwaxCore
import SwiftUI

/// What the page in front says in the status bar (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1:
/// the frame and the shared pieces"): "140 albums · 1,612 songs ... Navidrome up to date". A page says its facts with
/// `.macStatus(_:)`; the desktop frame draws the bar under the page while the page in front has said something, and none
/// while it hasn't - every page the phone's still, until its slice says its facts.
///
/// Kept here, an observed model the frame holds, rather than as a SwiftUI preference: the pages are drawn inside the
/// frame's TabView and NavigationStacks, each a UIKit controller of its own on Catalyst, and a preference isn't carried
/// up out of them. The page that came on screen last is the one in front - a page pushed over another, a tab chosen - and
/// as it goes, the one under it is in front again; a page off the screen changes nothing (Core's MacInFront, tested).
@MainActor
@Observable
final class MacStatusItems {
    /// A page's facts: those at the bar's left, and those at its right - and (the app's fonts, 25 Nov) those of them
    /// that tick, a speed that changes as it's read, which the bar sets in the readout face so their figures hold still.
    struct Items: Equatable, Sendable {
        var leading: [String]
        var trailing: [String] = []
        var readouts: Set<String> = []

        var isEmpty: Bool { leading.isEmpty && trailing.isEmpty }
    }

    /// Each page on screen that has said something, by its own id.
    private var pages = MacInFront<UUID, Items>()

    /// The bar's: the page in front's, if it said anything.
    var shown: Items? {
        guard let items = pages.front, !items.isEmpty else { return nil }
        return items
    }

    /// A page came on screen saying `items`: in front now.
    func say(_ items: Items, from page: UUID) {
        pages.appeared(page, saying: items)
    }

    /// A page saying something new: its facts change where they are, in front or not - none while it is off the screen.
    func change(_ items: Items, from page: UUID) {
        pages.changed(page, to: items)
    }

    /// A page went from the screen.
    func forget(_ page: UUID) {
        pages.gone(page)
    }
}

extension View {
    /// (The Mac redesign) This page's facts in the status bar under it, while it is on screen.
    func macStatus(_ items: MacStatusItems.Items) -> some View {
        modifier(MacStatusSaying(items: items))
    }
}

/// macStatus's: the page's facts said as it comes on screen, changed as they change, forgotten as it goes. Nothing in a
/// sheet, whose environment holds no status bar.
private struct MacStatusSaying: ViewModifier {
    let items: MacStatusItems.Items
    @Environment(MacStatusItems.self) private var status: MacStatusItems?
    @State private var page = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { status?.say(items, from: page) }
            .onChange(of: items) { (_: MacStatusItems.Items, now: MacStatusItems.Items) -> Void in
                status?.change(now, from: page)
            }
            .onDisappear { status?.forget(page) }
    }
}
