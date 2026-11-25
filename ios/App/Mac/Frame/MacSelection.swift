import DeadwaxCore
import SwiftUI

/// What is selected on the page in front (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1: the
/// frame and the shared pieces"): the album or artist row a list's selection is on (R2's lists), which the side panel's
/// Info shows (R3) - James, 24 Nov: "Selection, else playing": the selection on a page with a list, else the song
/// playing. The page in front's alone: a list says its selection with `.macSelects(_:)` as it comes on screen and as it
/// changes, and as the page goes from the screen - another pushed over it, another tab chosen - what it selected goes
/// with it, so Info never shows a row from a page no longer in front. A list off the screen that changes its selection
/// (a row gone from under a pushed album) changes nothing and is never put in front by it: it says it again as it comes
/// back (Core's MacInFront, tested). Nothing is selected on the iPhone, which never draws these pages.
@MainActor
@Observable
final class MacSelection {
    /// A row a list can select.
    enum Subject: Hashable {
        case album(AlbumRoute)
        case artist(ArtistRoute)
    }

    /// The pages on screen with a list, each with what it has selected (nil for none).
    private var pages = MacInFront<UUID, Subject?>()

    /// The selection: the page in front's - none while it has none, or no page with a list is on screen.
    var subject: Subject? { pages.front ?? nil }

    /// A page with a list came on screen with `subject` selected (nil for none): in front now.
    func appeared(_ page: UUID, selecting subject: Subject?) {
        pages.appeared(page, saying: subject)
    }

    /// A page's list selected `subject` - nil: nothing selected there now. Where the page is: in front, or on screen
    /// under the one in front; a page off the screen changes nothing.
    func select(_ subject: Subject?, by page: UUID) {
        pages.changed(page, to: subject)
    }

    /// A page went from the screen: its selection goes with it - another page's stays.
    func letGo(by page: UUID) {
        pages.gone(page)
    }
}

extension View {
    /// (The Mac redesign) This page's list has `subject` selected - nil for none - while the page is on screen.
    func macSelects(_ subject: MacSelection.Subject?) -> some View {
        modifier(MacSelecting(subject: subject))
    }
}

/// macSelects': the selection said as the page comes on screen and as it changes, let go as the page goes. Nothing in a
/// sheet, whose environment holds no selection.
private struct MacSelecting: ViewModifier {
    let subject: MacSelection.Subject?
    @Environment(MacSelection.self) private var selection: MacSelection?
    @State private var page = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { selection?.appeared(page, selecting: subject) }
            .onChange(of: subject) { (_: MacSelection.Subject?, now: MacSelection.Subject?) -> Void in
                selection?.select(now, by: page)
            }
            .onDisappear { selection?.letGo(by: page) }
    }
}
