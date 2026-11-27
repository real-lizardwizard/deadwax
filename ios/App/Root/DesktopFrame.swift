import DeadwaxCore
import SwiftUI

/// The Mac's window, always (the Mac app, slice 3 - the Mac app's plan 1.2 and decision 3; notes/ios.md "The Mac app,
/// slice 3: the desktop frame"): the web's desktop frame (app-desktop.css, 2.1.35) in place of the iPhone's tabs.
///
/// - (The Mac redesign, R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces") The title
///   strip across the top (MacTitleStrip), under the window's traffic lights: the page in front's name (MacTitle), which
///   names the window too (Platform.nameWindow). The frame is laid under the title bar for it - the strip as tall as the
///   bar is, 28 at least (MacLook.titleHeight).
/// - The sidebar at the left (MacSidebarView), MacLook.sidebarWidth (220, the redesign's) wide, put away and back by
///   View > Hide Sidebar (⌃⌘S); its rule at its right its own.
/// - The page: the tab the sidebar's rows lead to, as its stack stands (AppNavigation's four stacks, the iPhone's), in
///   the iPhone's TabView with its bar hidden - every tab's pages kept as the tabs keep them, only the one showing on
///   screen, so each page appears and goes as it does under the tab bar (⌘R's page, the counts, the event log's stream
///   all go by it). The Library's own top - its switch and its ••• - stays at the top of its page. (R1) Each stack is
///   the Mac's own (MacTabStack, the Mac's routes - MacRoutes), each tab's root its area's (MacLibrary, MacSearch,
///   MacRequests, MacSettings): the phone's pages until each slice redraws its own.
/// - (R1) The status bar under the page and its panel (MacStatusBar), while the page in front says something
///   (MacStatusItems); what a list on it selects is MacSelection's, for Info.
/// - The side panel - (R3) a dock of tabs, Queue, Lyrics, Info and EQ (Sources with a Get page), one at a time
///   (MacPanel, MacDock) - a third column 400 wide in a window 1280 wide or more, a drawer over the page's right
///   edge below that (MacFrame.panelStyle); drawn in one place either way, so crossing 1280 keeps it as it is. Never modal: a drawer lies over the page's edge, the rest of the page and the
///   sidebar still answer. Opening an album from the player puts a drawer away (AppNavigation.openAlbum).
/// - The player bar along the foot (PlayerBar), always: "Nothing playing" while nothing is queued.
/// - (The Mac's Row Size) Every list's rows as tall as View > Row Size says (Small, Medium or Large, kept on this Mac -
///   MacRowSizeStore): the one choice handed down to all of them (the environment's `macRowSize`), so they change
///   together; and Make Bigger's second key, ⌘=, held here (RowSizeAlternateKey), so it answers in the main window.
///
/// Now Playing never opens here (MacFrame.opensNowPlaying, decision 5): nothing in the frame opens it, and should
/// anything ask, it is put back at once. The sheets MainTabs presents over the tabs are presented over the frame: Add to
/// a playlist and Edit album - and not the EQ (R3's review), which is the dock's EQ tab here, a shared file's preview
/// over it. What MainTabs watches, this watches: the downloads RequestsModel paces its poll by, Needs a look's count
/// after a managing write.
struct DesktopFrame: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(QueueCountModel.self) private var queueCount
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    /// The window's width: how a panel is drawn (MacFrame.panelStyle).
    @State private var width: Double = MacFrame.openingWidth
    /// (Slice 7) And its height, under the title bar: with the width, Edit album's sheet's size (MacFrame.sheetSize).
    @State private var height: Double = MacFrame.openingHeight
    /// (The Mac redesign, R1) The window's title bar's height, the frame laid under it: the title strip's.
    @State private var titleBar: CGFloat = 0
    /// (R1) The page in front's facts for the status bar, and what its list selects.
    @State private var status = MacStatusItems()
    @State private var selection = MacSelection()
    /// (R1) The Library switch's order, as this Mac keeps it (LibraryView's own): where the app is, for the title.
    @AppStorage(LibraryPages.storageKey) private var savedOrder = ""

    private var style: MacFrame.PanelStyle { MacFrame.panelStyle(width: width) }

    var body: some View {
        @Bindable var navigation = navigation
        let panel = navigation.macPanel
        VStack(spacing: 0) {
            MacTitleStrip(title: title, height: strip)
            HStack(spacing: 0) {
                if navigation.macSidebarShown {
                    MacSidebarView()
                        .frame(width: CGFloat(MacLook.sidebarWidth))
                }
                // (slice 3's review) the panel in one place whichever way it's drawn - over the page's edge or in a
                // column the page makes room for - so a window crossing 1280 keeps it as it was (Up Next's Edit, the
                // lyrics followed), never draws it afresh
                VStack(spacing: 0) {
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // (R3) the dock, MacLook.panelWidth (400) wide, whichever of its tabs shows
                        .padding(.trailing, MacDock.makesRoom(style, panel) ? CGFloat(MacLook.panelWidth) + hairline : 0)
                        .overlay(alignment: .trailing) {
                            if let panel {
                                HStack(spacing: 0) {
                                    rule
                                    MacPanel(tab: panel)
                                }
                                // (the panel review's R19) the drawer's own drop, as dark as it always was
                                .shadow(color: MacDock.liesOver(style, panel) ? Self.drawerDrop : Color.clear,
                                        radius: MacDock.liesOver(style, panel) ? 16 : 0)
                            }
                        }
                    // (R1) the status bar under the page and the panel, while the page in front says something
                    if let items = status.shown {
                        MacStatusBar(items: items)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            PlayerBar()
        }
        // (R1) under the title bar, the strip where its gradient can't be: the bar's height read, the strip as tall
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGFloat.self) { (frame: GeometryProxy) -> CGFloat in
            frame.safeAreaInsets.top
        } action: { (now: CGFloat) -> Void in
            titleBar = now
        }
        .onChange(of: title, initial: true) { (_: String, now: String) -> Void in
            Platform.nameWindow(now)
        }
        .environment(status)
        .environment(selection)
        // (the Mac's Row Size) every list's rows at View > Row Size's height, as this Mac keeps it (MacRowSizeStore,
        // which the menus read too) - and Make Bigger's second key, ⌘= (MacCommands' menu draws ⌘+)
        .environment(\.macRowSize, rowSize)
        .modifier(RowSizeAlternateKey())
        .onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in
            Double(frame.size.width)
        } action: { (now: Double) -> Void in
            width = now
        }
        .onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in
            // (R1) the frame is laid under the title bar now: its height under it is what it is less the strip's
            Double(frame.size.height - max(CGFloat(MacLook.titleHeight), frame.safeAreaInsets.top))
        } action: { (now: Double) -> Void in
            height = now
        }
        .onChange(of: style, initial: true) { (_: MacFrame.PanelStyle, now: MacFrame.PanelStyle) -> Void in
            navigation.macPanelStyle = now
        }
        // Add to a playlist and Edit album, over the frame as they are over the tabs (MainTabs). (R3's review) No EQ sheet:
        // a shared file's EQ is the dock's EQ tab, its preview over it (SharedEQFile, DockEQ) - one EQ, never a second
        .appSheet(item: $navigation.playlistPick) { (request: PlaylistPickRequest) in
            // (the panel review's R19) a sheet's window is outside the frame's `macRowSize`: its rows' size handed in
            PlaylistPicker(request: request)
                .environment(\.sheetRowSize, SheetRowSize(height: CGFloat(rowSize.rowHeight),
                                                          cover: CGFloat(rowSize.cover)))
                .macSheet()
        }
        .appSheet(item: $navigation.albumEdit, onDismiss: { navigation.editorDismissed() }) { (request: AlbumEditRequest) in
            // (slice 7) its pages at the readable width, as tall as the window leaves: never past the window's edges
            EditAlbumSheet(request: request)
                .macSheet()
                .sizedSheet(MacFrame.sheetSize(width: width, height: height))
        }
        .onChange(of: navigation.nowPlayingShown, initial: true) { (_: Bool, shown: Bool) -> Void in
            //? Now Playing never opens on the Mac (MacFrame.opensNowPlaying): nothing here opens it, nor stays opened
            if shown && !MacFrame.opensNowPlaying(Platform.device) { navigation.nowPlayingShown = false }
        }
        .onChange(of: player.hasQueue) { (_: Bool, queued: Bool) -> Void in
            // nothing queued: the Queue and Info go with the queue, Lyrics and the EQ stay - (R3) and Info stays about a
            // row selected (MacDock.afterQueueEnds)
            if !queued { navigation.queueEnded() }
        }
        .onChange(of: selection.subject != nil, initial: true) { (_: Bool, selected: Bool) -> Void in
            // (R3) what the menus read: Info opens about a row selected with nothing queued (MacMenu)
            navigation.macSelected = selected
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
            MacTabStack(path: paths.library, ownTop: true) { MacLibrary.root() }
                .tag(AppTab.library)
            MacTabStack(path: paths.search) { MacSearch.root() }
                .tag(AppTab.search)
            MacTabStack(path: paths.requests) { MacRequests.root() }
                .tag(AppTab.requests)
            MacTabStack(path: paths.you) { MacSettings.root() }
                .tag(AppTab.you)
        }
    }

    /// (The Mac redesign, R1) The title strip's height: the title bar's, 28 at least (dw.css's .titlebar).
    private var strip: CGFloat {
        max(CGFloat(MacLook.titleHeight), titleBar)
    }

    /// (The Mac redesign, R1) The title strip's words and the window's name: the page in front's (MacTitle).
    private var title: String {
        MacTitle.title(navigation, personal: server.access.hasLibrary, savedOrder: savedOrder, playlists: playlists.list)
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

    /// View > Row Size, as this Mac keeps it (MacRowSizeStore, which the menus read too) - read here alone.
    private var rowSize: MacRowSize { MacRowSizeStore.shared.size }

    /// (R19's review) The drawer's shadow over the page: black at 0.2, the old palette's well's very value, named here -
    /// DWPalette's buttonDrop is a button's 1-px drop, more than twice as dark.
    private static let drawerDrop = Color.black.opacity(0.2)

    /// --dw-frame-border, a hairline down the panel's edge. (R19) The look's `--frame`, the very colour.
    private var rule: some View {
        DWPalette.frame
            .frame(width: hairline)
            .accessibilityHidden(true)
    }

    /// One pixel, in points.
    private var hairline: CGFloat {
        1 / max(displayScale, 1)
    }
}

/// (The panel review's R19 - notes/ios.md "The panel review, R19: Get, and old type left in redrawn pages (2026-11-27)")
/// View > Row Size's row height and cover side as plain numbers, for the sheet the frame puts up over itself (Add to a
/// playlist): a sheet's window is outside the frame's `macRowSize`, so the frame hands these in, and a shared file reads
/// them without naming the Mac's store. Nil wherever no frame did (the phone), where the sheet's own sizes hold.
struct SheetRowSize: Equatable {
    let height: CGFloat
    let cover: CGFloat
}

extension EnvironmentValues {
    @Entry var sheetRowSize: SheetRowSize? = nil
}
