import DeadwaxCore
import SwiftUI

/// The dock's Sources tab on the Mac (the redesign's slice R7 - notes/ios.md "The redesign, slice R7: Search, Get and
/// Sources (2026-11-25)"; Get.dc.html's panel): Choose a source for the Get the album you don't have asked for
/// (AppNavigation.macSources), beside its page rather than over it as the phone's sheet is. It is SourcesPage, the
/// sheet's very page, given the Get's own chips and sort (`kept`) so a tab switched away from and back finds it as it
/// was; a download asked for from it hands over to Requests as the sheet does (AppNavigation.sourcesQueued). Its page
/// leaving the front ends the Get, and the tab goes with it.
///
/// (The panel review's R19 - notes/ios.md "The panel review, R19: Get, and old type left in redrawn pages
/// (2026-11-27)"; James, 26 Nov: "The dock's system bar and Done go") No bar: the page starts under the folder tabs, its
/// Search again in the dock's header (SourcesPage's `dockHeader`). Its Close is the dock's own - Escape (MacPanel's key
/// through MacFrame.escape, which a field with the cursor answers first) or a click on its open folder tab
/// (MacDock.clicked) - and the panel put away is the Get over, as Close was: its search let go and Sources gone
/// (`endSources`), so nothing is picked for a page no longer looked at. A tab switched to keeps the Get, as before.
/// While its words to search with are edited, the tab holds Escape (`dockHoldsEscape`) and neither does anything, as
/// Close's Escape did: putting the panel away would throw the edited words away unasked.
struct MacSourcesTab: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        if let get = navigation.macSources {
            NavigationStack {
                SourcesPage(request: get.request, pushed: false, kept: get.choices) {
                    navigation.sourcesQueued(get.request.id)
                }
            }
            // one Get's page at a time: another Get is a page afresh
            .id(get.request.id)
            // edited words: Escape is no Close
            .dockHoldsEscape(get.request.search.edited)
            // the panel put away with Sources showing - Escape, however it closed: the Get over (another tab chosen
            // keeps it; a Get already over is nothing to end)
            .onDisappear {
                if navigation.macPanel == nil { navigation.endSources() }
            }
        }
    }
}
