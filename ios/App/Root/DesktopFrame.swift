import DeadwaxCore
import SwiftUI

/// The Mac's window, always (the Mac app, slice 3 - the Mac app's plan 1.2 and decision 3; notes/ios.md "The Mac app,
/// slice 3: the desktop frame"): the web's desktop frame (app-desktop.css, 2.1.35) in place of the iPhone's tabs.
///
/// - The sidebar at the left (MacSidebarView), MacFrame.sidebarWidth wide, put away and back by View > Hide Sidebar
///   (⌃⌘S); a rule at its right.
/// - The page: the tab the sidebar's rows lead to, as its stack stands (AppNavigation's four stacks, the iPhone's), in
///   the iPhone's TabView with its bar hidden - every tab's pages kept as the tabs keep them, only the one showing on
///   screen, so each page appears and goes as it does under the tab bar (⌘R's page, the counts, the event log's stream
///   all go by it). The Library's own top - its switch and its ••• - stays at the top of its page.
/// - The side panel - Up Next, Lyrics or Info, one at a time (MacPanel) - a third column 470 wide in a window 1280 wide
///   or more, a drawer over the page's right edge below that (MacFrame.panelStyle); drawn in one place either way, so
///   crossing 1280 keeps it as it is. Never modal: a drawer lies over the page's edge, the rest of the page and the
///   sidebar still answer. Opening an album from the player puts a drawer away (AppNavigation.openAlbum).
/// - The player bar along the foot (PlayerBar), always: "Nothing playing" while nothing is queued.
///
/// Now Playing never opens here (MacFrame.opensNowPlaying, decision 5): nothing in the frame opens it, and should
/// anything ask, it is put back at once. The sheets MainTabs presents over the tabs are presented over the frame:
/// the EQ (a shared file's, and the bar's ••• - one sheet), Add to a playlist and Edit album. What MainTabs watches,
/// this watches: the downloads RequestsModel paces its poll by, Needs a look's count after a managing write.
struct DesktopFrame: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(QueueCountModel.self) private var queueCount
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
                // (slice 3's review) the panel in one place whichever way it's drawn - over the page's edge or in a
                // column the page makes room for - so a window crossing 1280 keeps it as it was (Up Next's Edit, the
                // lyrics followed), never draws it afresh
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, MacFrame.makesRoom(style, panel) ? CGFloat(MacFrame.panelWidth) + hairline : 0)
                    .overlay(alignment: .trailing) {
                        if panel != .none {
                            HStack(spacing: 0) {
                                rule
                                MacPanel(panel: panel)
                            }
                            .shadow(color: MacFrame.liesOver(style, panel) ? Palette.well : Color.clear,
                                    radius: MacFrame.liesOver(style, panel) ? 16 : 0)
                        }
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
        // a shared file's EQ, Add to a playlist and Edit album, over the frame as they are over the tabs (MainTabs) -
        // and (slice 3's review) the bar's EQ the same sheet, so a shared file shows over the one that's up, never a second
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

    /// The page showing: the tab the sidebar leads to, its stack as it stands - the Library's with its own top. (Slice
    /// 3's review) The iPhone's TabView, its bar hidden (TabStack hides it on every stack, as on the iPhone, where the
    /// app draws its own): each tab's pages are kept as the tabs keep them - a playlist's Edit, Find's words, a list's
    /// place - while only the tab showing is on screen, so its pages appear and go as they do under the tab bar.
    private var page: some View {
        let paths = Bindable(navigation)
        return TabView(selection: Binding(get: { navigation.tab }, set: { (tab: AppTab) -> Void in navigation.select(tab) })) {
            TabStack(path: paths.library, ownTop: true) { LibraryView() }
                .tag(AppTab.library)
            TabStack(path: paths.search) { SearchScreen() }
                .tag(AppTab.search)
            TabStack(path: paths.requests) { RequestsScreen() }
                .tag(AppTab.requests)
            TabStack(path: paths.you) { YouView() }
                .tag(AppTab.you)
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
            .frame(width: hairline)
            .accessibilityHidden(true)
    }

    /// One pixel, in points.
    private var hairline: CGFloat {
        1 / max(displayScale, 1)
    }
}
