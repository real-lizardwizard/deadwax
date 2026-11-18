import SwiftUI

/// Every sheet and full-screen cover the app presents goes through `appSheet` and `appCover`, never SwiftUI's own
/// `.sheet` or `.fullScreenCover` (tests/test_ios_mac.py holds it). Why (the Mac app, 17 Nov - notes/ios.md "Every
/// sheet carries the app's models, on the Mac"): on the Mac a presentation is hosted in a scene of its own, and the page
/// in it starts with an EMPTY environment - none of the models DeadwaxApp puts on its root, so its first
/// `@Environment(PlayerModel.self)` is a crash ("No Observable object of type PlayerModel found"): Now Playing, and every
/// sheet with it. Putting them on the WindowGroup scene instead doesn't reach that scene either (tried). So the
/// presenter, which has them, hands them on - on the Mac alone (Platform's `carryingApp`); on the iPhone a presented
/// page inherits its presenter's environment as it always has, and `carryingApp` is nothing.
extension View {
    /// SwiftUI's `.sheet(isPresented:onDismiss:content:)`, the page in it given the app's models on the Mac.
    func appSheet<Sheet: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(CarriedPresentation(kind: .sheet, isPresented: isPresented, onDismiss: onDismiss, page: content))
    }

    /// SwiftUI's `.sheet(item:onDismiss:content:)`, the page in it given the app's models on the Mac.
    func appSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                   @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(CarriedItemPresentation(kind: .sheet, item: item, onDismiss: onDismiss, page: content))
    }

    /// SwiftUI's `.fullScreenCover(isPresented:onDismiss:content:)`, the page in it given the app's models on the Mac.
    func appCover<Cover: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> Cover) -> some View {
        modifier(CarriedPresentation(kind: .cover, isPresented: isPresented, onDismiss: onDismiss, page: content))
    }

    /// SwiftUI's `.fullScreenCover(item:onDismiss:content:)`, the page in it given the app's models on the Mac.
    func appCover<Item: Identifiable, Cover: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                   @ViewBuilder content: @escaping (Item) -> Cover) -> some View {
        modifier(CarriedItemPresentation(kind: .cover, item: item, onDismiss: onDismiss, page: content))
    }
}

/// Every model DeadwaxApp shares through the environment - one field for each `.environment(model)` on its root
/// (tests/test_ios_mac.py holds the two lists equal: a model left out here would be a crash on the Mac only).
@MainActor
struct AppModels {
    let server: ServerModel
    let player: PlayerModel
    let navigation: AppNavigation
    let library: LibraryModel
    let debug: DebugModel
    let reachability: Reachability
    let downloads: DownloadModel
    let lyrics: LyricsModel
    let eq: EQModel
    let deck: DeckController
    let history: HistoryModel
    let playlists: PlaylistsModel
    let shuffles: ShuffleModel
    let artists: ArtistsModel
    let songs: SongsModel
    let search: SearchModel
    let requests: RequestsModel
    let getSettings: GetSettingsModel
    let queueCount: QueueCountModel
    let care: CareRunModel
    let serverSettings: ServerSettingsModel
    let eventLog: EventLogModel
    let people: PeopleModel
}

extension EnvironmentValues {
    /// The app's models as one value, put on DeadwaxApp's root beside them - what a presenter hands its page on the Mac.
    @Entry var appModels: AppModels? = nil
}

/// What a presenter hands its page on the Mac: the app's models (this value among them, so a sheet over a sheet is
/// handed them too), the two layout values a page's sheets inherit on the iPhone, and (Mac slice 2) how many sheets deep
/// the presenter is drawn - `\.macSheetLevel`, which the sheet's root (`macSheet`) counts one on from, so a sheet over a
/// sheet is deeper than the first and the menus act on the page in front (MacRefresh). The root's font and tint are
/// constants, put on again by `CarriesApp` itself.
struct AppCarried {
    let models: AppModels?
    let tabBarRoom: CGFloat
    let playerClearance: CGFloat
    let sheetLevel: Int
}

/// The page presented on the Mac, given what its presenter had (Platform's `carryingApp`, the Mac's alone).
struct CarriesApp: ViewModifier {
    let carried: AppCarried

    func body(content: Content) -> some View {
        if let m = carried.models {
            content
                .environment(m.server)
                .environment(m.player)
                .environment(m.navigation)
                .environment(m.library)
                .environment(m.debug)
                .environment(m.reachability)
                .environment(m.downloads)
                .environment(m.lyrics)
                .environment(m.eq)
                .environment(m.deck)
                .environment(m.history)
                .environment(m.playlists)
                .environment(m.shuffles)
                .environment(m.artists)
                .environment(m.songs)
                .environment(m.search)
                .environment(m.requests)
                .environment(m.getSettings)
                .environment(m.queueCount)
                .environment(m.care)
                .environment(m.serverSettings)
                .environment(m.eventLog)
                .environment(m.people)
                .environment(\.appModels, m)
                .environment(\.tabBarRoom, carried.tabBarRoom)
                .environment(\.playerClearance, carried.playerClearance)
                .environment(\.macSheetLevel, carried.sheetLevel)
                .tint(Palette.accent)
                .font(Typeface.body)
        } else {
            content
        }
    }
}

private enum PresentationKind {
    case sheet
    case cover
}

/// A sheet or cover shown while a Bool says so, its page handed what this presenter has.
private struct CarriedPresentation<Page: View>: ViewModifier {
    let kind: PresentationKind
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let page: () -> Page

    @Environment(\.appModels) private var models
    @Environment(\.tabBarRoom) private var tabBarRoom
    @Environment(\.playerClearance) private var playerClearance
    @Environment(\.macSheetLevel) private var sheetLevel

    func body(content: Content) -> some View {
        let carried = AppCarried(models: models, tabBarRoom: tabBarRoom, playerClearance: playerClearance,
                                 sheetLevel: sheetLevel)
        switch kind {
        case .sheet:
            content.sheet(isPresented: isPresented, onDismiss: onDismiss) { page().carryingApp(carried) }
        case .cover:
            content.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) { page().carryingApp(carried) }
        }
    }
}

/// A sheet or cover shown while an item is set, its page handed what this presenter has.
private struct CarriedItemPresentation<Item: Identifiable, Page: View>: ViewModifier {
    let kind: PresentationKind
    let item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let page: (Item) -> Page

    @Environment(\.appModels) private var models
    @Environment(\.tabBarRoom) private var tabBarRoom
    @Environment(\.playerClearance) private var playerClearance
    @Environment(\.macSheetLevel) private var sheetLevel

    func body(content: Content) -> some View {
        let carried = AppCarried(models: models, tabBarRoom: tabBarRoom, playerClearance: playerClearance,
                                 sheetLevel: sheetLevel)
        switch kind {
        case .sheet:
            content.sheet(item: item, onDismiss: onDismiss) { (shown: Item) in page(shown).carryingApp(carried) }
        case .cover:
            content.fullScreenCover(item: item, onDismiss: onDismiss) { (shown: Item) in page(shown).carryingApp(carried) }
        }
    }
}
