import Foundation

// The Mac's desktop frame (the Mac app's plan 1.2; notes/ios.md "The Mac app, slice 3: the desktop frame"): the web's
// desktop frame (lib/appFrame.ts) on the Mac, always (decision 3) - a sidebar down the left, the page, a player bar along
// the foot, and one side panel at the right. No tab bar, no mini player and no Now Playing (decision 5: the bar and the
// panels are the player, as on the web's desktop).
//
// The web's rules are held here by Fixtures/frame/frame-vectors.json (ios/scripts/export-frame-vectors.cjs runs
// lib/appFrame.ts as it is): which frame and panel a width gives (frameFor, panelIsModal), which panel shows of those
// open (sideOf), whether the page makes room for it (makesRoom) or it lies over the page's edge (liesOver), what
// crossing into the desktop closes (closesOnCrossing), and the frame's sizes read out of app-desktop.css. The Mac's own,
// tested in MacFrameTests: the frame is the desktop's at every width (`panelStyle` - a drawer below COLUMN_MIN, never a
// sheet), one panel of three at a time (`toggled`), and the window's sizes.

public enum MacFrame {
    /// The web's two breakpoints (lib/appFrame.ts): from DESKTOP_MIN the desktop frame...
    public static let desktopMin: Double = 1024
    /// ...and from COLUMN_MIN a side panel is a third column rather than a drawer over the page.
    public static let columnMin: Double = 1280

    /// The web's two frames.
    public enum Frame: String, Sendable, CaseIterable {
        case phone, desktop
    }

    /// How a panel is drawn: a sheet (the phone's), a drawer over the page's right edge, or a third column beside it.
    public enum PanelStyle: String, Sendable, CaseIterable {
        case sheet, drawer, column
    }

    public struct FrameState: Sendable, Equatable {
        public let frame: Frame
        public let panel: PanelStyle

        public init(frame: Frame, panel: PanelStyle) {
            self.frame = frame
            self.panel = panel
        }
    }

    /// The web's frame for a viewport `width` wide (frameFor).
    public static func frame(width: Double) -> FrameState {
        if width < desktopMin { return FrameState(frame: .phone, panel: .sheet) }
        return FrameState(frame: .desktop, panel: width < columnMin ? .drawer : .column)
    }

    /// A sheet is modal, the page behind it inert; a desktop panel leaves the page as it is (panelIsModal).
    public static func panelIsModal(_ style: PanelStyle) -> Bool {
        style == .sheet
    }

    /// The side panel's three on the Mac - Up Next, Lyrics and Info (the web's `upnext`, `lyrics`, `info`), or none. The
    /// web's other three - Sources, the Edit panel, the artist page's - are sheets on the Mac, as on the phone (the Mac
    /// app's plan 1.2: "Sheets").
    public enum Panel: String, Sendable, CaseIterable {
        case none
        case upNext = "upnext"
        case lyrics
        case info
    }

    /// Which panel shows of those open (sideOf): Info over Up Next over Lyrics; none on a phone.
    public static func panel(_ frame: Frame, info: Bool, upNext: Bool, lyrics: Bool) -> Panel {
        guard frame == .desktop else { return .none }
        return info ? .info : upNext ? .upNext : lyrics ? .lyrics : .none
    }

    /// Whether the page makes room for the panel: only a third column does; a drawer lies over it (makesRoom).
    public static func makesRoom(_ style: PanelStyle, _ panel: Panel) -> Bool {
        style == .column && panel != .none
    }

    /// Whether the panel lies over the page's right edge - a drawer, showing (liesOver). Such a panel closes as an album
    /// is opened from the player (the bar's "Artist — Album", Info's album, Go to Current Song): it would lie over the
    /// page asked for. A third column stays beside it.
    public static func liesOver(_ style: PanelStyle, _ panel: Panel) -> Bool {
        style == .drawer && panel != .none
    }

    /// What crossing into a frame closes (closesOnCrossing) - the web's four.
    public struct Crossing: Sendable, Equatable {
        public let nowPlaying: Bool
        public let infoPanel: Bool
        public let upNextPanel: Bool
        public let lyricsPanel: Bool

        public init(nowPlaying: Bool, infoPanel: Bool, upNextPanel: Bool, lyricsPanel: Bool) {
            self.nowPlaying = nowPlaying
            self.infoPanel = infoPanel
            self.upNextPanel = upNextPanel
            self.lyricsPanel = lyricsPanel
        }
    }

    /// Into the desktop: Now Playing closes (the desktop has none - its bar is the player); back to the phone, the
    /// three panels, which are Now Playing's own there.
    public static func closesOnCrossing(to frame: Frame) -> Crossing {
        frame == .desktop
            ? Crossing(nowPlaying: true, infoPanel: false, upNextPanel: false, lyricsPanel: false)
            : Crossing(nowPlaying: false, infoPanel: true, upNextPanel: true, lyricsPanel: true)
    }

    // MARK: the Mac's own

    /// Decision 3: the desktop frame on the Mac at every size; the iPhone's tabs on the iPhone, as they always were.
    public static func drawsDesktop(_ device: Device) -> Bool {
        device == .mac
    }

    /// Decision 5: Now Playing opens only where the phone's frame is drawn - crossing into the desktop closes it
    /// (closesOnCrossing), and the Mac never leaves the desktop. On the Mac the bar is the player.
    public static func opensNowPlaying(_ device: Device) -> Bool {
        !drawsDesktop(device)
    }

    /// The panel's place at a window `width` wide on the Mac: the web's from DESKTOP_MIN - a drawer, then a column from
    /// COLUMN_MIN - and below DESKTOP_MIN, where the web would draw the phone's frame, still the desktop's drawer: the
    /// Mac is always the desktop (decision 3), and its panel never a sheet.
    public static func panelStyle(width: Double) -> PanelStyle {
        frame(width: max(width, desktopMin)).panel
    }

    /// One panel at a time (the web's: opening any puts the others away): the panel shown after `asked`'s button or
    /// menu item - it, or none when it was the one showing.
    public static func toggled(_ shown: Panel, _ asked: Panel) -> Panel {
        asked == shown ? .none : asked
    }

    /// The panel shown once nothing is queued: Up Next and Info go (as their sheets did on the phone - Up Next's closes
    /// with the queue, and Info is the song playing's); Lyrics stays, saying "Nothing playing", as the web's panel does.
    public static func afterQueueEnds(_ shown: Panel) -> Panel {
        shown == .lyrics ? .lyrics : .none
    }

    /// Who Escape is for in the Mac's window - one at a time (slice 3's review: a panel's Done and a playlist's Edit
    /// Cancel both had it, and Escape went to either).
    public enum Escape: String, Sendable, CaseIterable {
        /// A text field with the cursor: the sidebar's search field empties itself; any other keeps Escape for itself.
        case field
        /// The side panel showing: its Done.
        case panel
        /// The page: a playlist's Edit, its Cancel.
        case page
    }

    /// Escape's one owner, in this order: typing first, then the side panel, then the page.
    public static func escape(typing: Bool, panel: Panel) -> Escape {
        if typing { return .field }
        return panel == .none ? .page : .panel
    }

    /// (Slice 3's review) A page drawn at the readable width (an album's, an artist's, the album you don't have): the
    /// room left either side of its content in a page `width` wide - the scroll view spans the page, so its margins
    /// still scroll and its scroll bar is at the page's edge; none on a page narrower than readableWidth.
    public static func readableMargin(width: Double) -> Double {
        max(0, (width - readableWidth) / 2)
    }

    /// (Slice 7, notes/ios.md "The Mac app, slice 7: managing on a big screen") A sheet's size.
    public struct Size: Sendable, Equatable {
        public let width: Double
        public let height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// (Slice 7) A sheet that holds pages of its own - Edit album, its Release, Tags, Artwork, Lyrics and Delete album -
    /// over a window whose page is `width` x `height` (the frame under the title bar): the readable width, as a page drawn
    /// for a phone is kept on the Mac, and the window's height, each less the room kept round a sheet (sheetRoom), so it
    /// fits inside the window at every size down to the smallest, and is never wider than its pages read well.
    public static func sheetSize(width: Double, height: Double) -> Size {
        Size(width: max(0, min(readableWidth, width - 2 * sheetRoom)), height: max(0, height - 2 * sheetRoom))
    }

    // MARK: sizes, in points - the web's CSS px (app-desktop.css, held by the fixture)

    /// --app-desk-side: the sidebar.
    public static let sidebarWidth: Double = 232
    /// --app-desk-panel: a side panel.
    public static let panelWidth: Double = 470
    /// --app-desk-bar: the player bar.
    public static let barHeight: Double = 72
    /// --app-desk-bar-cover: the bar's cover.
    public static let barCover: Double = 48
    /// --app-desk-bar-side at 1024-1279, and from COLUMN_MIN: the bar's song and its tools, either side of the controls.
    public static let barSideNarrow: Double = 240
    public static let barSideWide: Double = 320
    /// --app-desk-bar-pad: the bar's ends; --app-desk-bar-gap: between its three parts.
    public static let barPad: Double = 20
    public static let barGap: Double = 24
    /// --app-desk-tile-min: an album's cover in a grid, as small as a phone's grid draws one.
    public static let tileMin: Double = 150
    /// --app-desk-content-max: a page drawn for a phone, kept readable (the album, the artist, the album you don't have).
    public static let readableWidth: Double = 760

    /// The bar's song and tools, at a window `width` wide.
    public static func barSide(width: Double) -> Double {
        width < columnMin ? barSideNarrow : barSideWide
    }

    /// The window's smallest: the bar's song and tools (240 each), its gaps and ends, and the 300 of controls and
    /// scrubber between them - 868, made 880; under the bar a page 528 high, under the title bar. The sidebar (232)
    /// leaves the page 648: more than a phone's page.
    public static let smallestWidth: Double = 880
    public static let smallestHeight: Double = 600
    /// The controls and the scrubber between the bar's two sides, at the smallest.
    public static let barMiddleMin: Double = 300
    /// The window as it first opens - a column's width, so a panel opens beside the page; macOS remembers it after.
    public static let openingWidth: Double = 1280
    public static let openingHeight: Double = 820
    /// (Slice 7) The room kept between a sheet and the window's edges, either side.
    public static let sheetRoom: Double = 40
}
