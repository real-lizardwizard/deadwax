import DeadwaxCore
import SwiftUI

/// The Mac's window, always (the Mac app, slice 3 - the Mac app's plan 1.2 and decision 3; notes/ios.md "The Mac app,
/// slice 3: the desktop frame"): the web's desktop frame (app-desktop.css, 2.1.35) in place of the iPhone's tabs.
///
/// - The sidebar at the left (MacSidebarView), MacFrame.sidebarWidth wide, put away and back by View > Hide Sidebar
///   (⌃⌘S); a rule at its right.
/// - The page: the tab the sidebar's rows lead to, as its stack stands (AppNavigation's four stacks, the iPhone's) -
///   only the one showing is drawn, so each page appears and goes as it did under the tab bar (⌘R's page, the counts,
///   the event log's stream all go by it). The Library's own top - its switch and its ••• - stays at the top of its page.
/// - The side panel - Up Next, Lyrics or Info, one at a time (MacPanel) - a third column 470 wide in a window 1280 wide
///   or more, a drawer over the page's right edge below that (MacFrame.panelStyle). Never modal: a drawer lies over the
///   page's edge, the rest of the page and the sidebar still answer. Opening an album from the player puts a drawer away
///   (AppNavigation.openAlbum).
/// - The player bar along the foot (PlayerBar), always: "Nothing playing" while nothing is queued.
///
/// Now Playing never opens here (MacFrame.opensNowPlaying, decision 5): nothing in the frame opens it, and should
/// anything ask, it is put back at once. The sheets MainTabs presents over the tabs are presented over the frame:
/// a shared file's EQ, Add to a playlist and Edit album. What MainTabs watches, this watches: the downloads RequestsModel
/// paces its poll by, Needs a look's count after a managing write. Search's asks stand down when another page shows.
struct DesktopFrame: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(QueueCountModel.self) private var queueCount
    @Environment(SearchModel.self) private var search
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    /// The window's width: how a panel is drawn (MacFrame.panelStyle).
    @State private var width: Double = MacFrame.openingWidth

    private var style: MacFrame.PanelStyle { MacFrame.panelStyle(width: width) }

    var body: some View {
        @Bindable var navigation = navigation
        let panel = navigation.macPanel
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if navigation.macSidebarShown {
                    MacSidebarView()
                        .frame(width: CGFloat(MacFrame.sidebarWidth))
                    rule
                }
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if MacFrame.liesOver(style, panel) {
                            HStack(spacing: 0) {
                                rule
                                MacPanel(panel: panel)
                            }
                            .shadow(color: Palette.well, radius: 16)
                        }
                    }
                if MacFrame.makesRoom(style, panel) {
                    rule
                    MacPanel(panel: panel)
                }
            }
            .frame(maxHeight: .infinity)
            PlayerBar()
        }
        .onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in
            Double(frame.size.width)
        } action: { (now: Double) -> Void in
            width = now
        }
        .onChange(of: style, initial: true) { (_: MacFrame.PanelStyle, now: MacFrame.PanelStyle) -> Void in
            navigation.macPanelStyle = now
        }
        // a shared file's EQ, Add to a playlist and Edit album, over the frame as they are over the tabs (MainTabs)
        .appSheet(isPresented: $navigation.eqImportSheet) {
            EQSheet()
                .macSheet()
        }
        .appSheet(item: $navigation.playlistPick) { (request: PlaylistPickRequest) in
            PlaylistPicker(request: request)
                .macSheet()
        }
        .appSheet(item: $navigation.albumEdit, onDismiss: { navigation.editorDismissed() }) { (request: AlbumEditRequest) in
            EditAlbumSheet(request: request)
                .macSheet()
        }
        .onChange(of: navigation.nowPlayingShown, initial: true) { (_: Bool, shown: Bool) -> Void in
            //? Now Playing never opens on the Mac (MacFrame.opensNowPlaying): nothing here opens it, nor stays opened
            if shown && !MacFrame.opensNowPlaying(Platform.device) { navigation.nowPlayingShown = false }
        }
        .onChange(of: player.hasQueue) { (_: Bool, queued: Bool) -> Void in
            // nothing queued: Up Next and Info go with the queue, Lyrics stays (MacFrame.afterQueueEnds)
            if !queued { navigation.queueEnded() }
        }
        .onChange(of: navigation.tab) { (_: AppTab, tab: AppTab) -> Void in
            // another page than Search's: a held album's row asking the id bridge lets go (SearchScreen's own, which
            // isn't drawn now to hear it)
            if tab != .search { search.standDown() }
        }
        .onChange(of: watching, initial: true) { (_: Watching, now: Watching) -> Void in requests.watch(now) }
        .onAppear { requests.watch(watching) }
        .onDisappear { requests.watch(.hidden) }
        .onChange(of: navigation.managingWrites) { (_: Int, _: Int) -> Void in queueCount.changed() }
        .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) -> Void in queueCount.scene(phase) }
        .onChange(of: Managing.asksQueueSummary(server.access.permissions)) { (_: Bool, asks: Bool) -> Void in
            if asks { queueCount.changed() }
        }
        .onChange(of: server.signInOver == nil) { (_: Bool, clear: Bool) -> Void in
            if clear { queueCount.changed() }
        }
    }

    /// The page showing: the tab the sidebar leads to, its stack as it stands - the Library's with its own top.
    @ViewBuilder private var page: some View {
        let paths = Bindable(navigation)
        switch navigation.tab {
        case .library:
            TabStack(path: paths.library, ownTop: true) { LibraryView() }
        case .search:
            TabStack(path: paths.search) { SearchScreen() }
        case .requests:
            TabStack(path: paths.requests) { RequestsScreen() }
        case .you:
            TabStack(path: paths.you) { YouView() }
        }
    }

    /// What the app is looking at, as far as downloads go (MainTabs' own): nothing in the background or under the
    /// sign-in; the page showing at its root - Now Playing is never over it here.
    private var watching: Watching {
        let tab: String
        switch navigation.tab {
        case .requests: tab = "requests"
        case .library: tab = "library"
        case .search: tab = "search"
        case .you: tab = "you"
        }
        return RequestsWatch.watching(shown: scenePhase != .background && server.signInOver == nil, tab: tab,
                                      depth: navigation.shownStack.count, sheetOpen: false)
    }

    /// --dw-frame-border, a hairline down the sidebar's edge and the panel's.
    private var rule: some View {
        Palette.frameBorder
            .frame(width: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}
