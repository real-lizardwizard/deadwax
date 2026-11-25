import DeadwaxCore
import SwiftUI

/// One of the desktop frame's four stacks (the Mac redesign, slice R1 - the build plan's section 1, notes/ios.md "The Mac
/// redesign, slice R1: the frame and the shared pieces"): TabStack's own, with the Mac's routes (`.macRoutes()`, never
/// appRoutes) - so the Mac's pages are the Mac's to redraw and the iPhone's TabStack and routes keep no diff. As TabStack
/// on the Mac: the system's tab bar hidden on the stack and every page, the offline banner under the root unless it draws
/// its own top (the Library's switch), and the notice over the page's foot for its 5 s with the room it takes given to
/// the pages. The frame has no tab bar, so there is no tab bar's room to add (TabStack's `tabBarRoom`, 0 here).
struct MacTabStack<Root: View>: View {
    @Binding var path: [AppRoute]
    /// The root draws its own top, with the offline banner under it (the Library's switch): not drawn here.
    var ownTop = false
    @ViewBuilder var root: Root

    @Environment(PlayerModel.self) private var player
    /// The notice's height as last drawn, with its padding.
    @State private var noticeHeight: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            root
                .clearsPlayer()
                .showsOfflineBanner(!ownTop)
                .toolbar(.hidden, for: .tabBar)
                .macRoutes()
        }
        .toolbar(.hidden, for: .tabBar)
        .environment(\.playerClearance, player.notice != nil ? noticeHeight : 0)
        .overlay(alignment: .bottom) {
            MacNotice { (height: CGFloat) -> Void in noticeHeight = height }
        }
    }
}

/// The notice over the page's foot, for its 5 s (MainTabs' NoticeInset, the same drawing): it says its height as drawn,
/// for the pages' room under it.
private struct MacNotice: View {
    @Environment(PlayerModel.self) private var player

    let measured: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let notice = player.notice {
                Notice(text: notice)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .onGeometryChange(for: CGFloat.self) { (frame: GeometryProxy) -> CGFloat in
            frame.size.height
        } action: { (height: CGFloat) -> Void in
            measured(height)
        }
        .animation(.default, value: player.notice)
    }
}
