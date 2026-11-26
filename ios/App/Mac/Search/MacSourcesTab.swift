import DeadwaxCore
import SwiftUI

/// The dock's Sources tab on the Mac (the redesign's slice R7 - notes/ios.md "The redesign, slice R7: Search, Get and
/// Sources (2026-11-25)"; Get.dc.html's panel): Choose a source for the Get the album you don't have asked for
/// (AppNavigation.macSources), beside its page rather than over it as the phone's sheet is. It is SourcesPage, the
/// sheet's very page, given the Get's own chips and sort (`kept`) so a tab switched away from and back finds it as it
/// was; its Close is the Get over and the panel put away, and a download asked for from it hands over to Requests as the
/// sheet does (AppNavigation.sourcesQueued). Its page leaving the front ends the Get, and the tab goes with it.
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
        }
    }
}
