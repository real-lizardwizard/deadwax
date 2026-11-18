import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/frame/frame-vectors.json: the web's lib/appFrame.ts, lib/appRoutes.ts's playlistsMove, lib/playlists.ts's
/// sidebarPlaylists and state/persisted.ts's two sidebar choices run as they are, app/Sidebar.tsx's words and
/// app-desktop.css's sizes read out of their sources (ios/scripts/export-frame-vectors.cjs) - replayed here through
/// MacFrame and MacSidebar, case for case (notes/ios.md "The Mac app, slice 3: the desktop frame"). The web's sidebar
/// items are the Mac's rows by `row(_:)`; Home and Recently added, which the app has no page for, are left out where a
/// case names them.
@Suite struct MacFrameVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("frame/frame-vectors.json"))

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-frame-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/appFrame.ts", "ui/src/lib/appRoutes.ts", "ui/src/lib/playlists.ts",
                                 "ui/src/state/persisted.ts", "ui/src/app/Sidebar.tsx the Library heading",
                                 "ui/src/app/Sidebar.tsx the Manage heading", "interface/player/app-desktop.css --app-desk-side",
                                 "interface/player/app-desktop.css the bar's sides from 1280px"])
        #expect(fixture["frames"].list.count == 15)
    }

    /// The web's sidebar item as the Mac's row: nil for Home and Recently added (no such page in the app) and for none.
    static func row(_ web: Web) -> MacSidebar.Row?? {
        guard let id = web.string else { return .some(nil) }
        switch id {
        case "requests": return .requests
        case "albums": return .view(.albums)
        case "artists": return .view(.artists)
        case "store": return .allAlbums
        case "storeArtists": return .allArtists
        case "songs": return .allSongs
        case "playlists": return .playlists
        case "queue": return .manage(.queue)
        case "care": return .manage(.care)
        case "people": return .manage(.people)
        case "settings": return .manage(.settings)
        case "log": return .manage(.log)
        case "you": return .settings
        default: return nil
        }
    }

    // MARK: the frame

    @Test func theBreakpointsAndSizesAreTheWebs() {
        #expect(MacFrame.desktopMin == fixture["constants"]["DESKTOP_MIN"].num)
        #expect(MacFrame.columnMin == fixture["constants"]["COLUMN_MIN"].num)
        let sizes = fixture["sizes"]
        #expect(MacFrame.sidebarWidth == sizes["side"].num)
        #expect(MacFrame.panelWidth == sizes["panel"].num)
        #expect(MacFrame.barHeight == sizes["bar"].num)
        #expect(MacFrame.barCover == sizes["barCover"].num)
        #expect(MacFrame.barSideNarrow == sizes["barSide"].num && MacFrame.barSideWide == sizes["barSideWide"].num)
        #expect(MacFrame.barPad == sizes["barPad"].num && MacFrame.barGap == sizes["barGap"].num)
        #expect(MacFrame.tileMin == sizes["tileMin"].num)
        #expect(MacFrame.readableWidth == sizes["contentMax"].num)
    }

    @Test func eachWidthsFrameAndPanel() {
        let diffs = ScreenDiffs()
        for row in fixture["frames"].list {
            let width = row["width"].num!
            let frame = MacFrame.frame(width: width)
            diffs.check("\(width): the frame", frame.frame.rawValue, row["frame"].string!)
            diffs.check("\(width): the panel", frame.panel.rawValue, row["panel"].string!)
            // the Mac's: the web's from DESKTOP_MIN, and below it the desktop's drawer - never a sheet (decision 3)
            let mac = MacFrame.panelStyle(width: width)
            diffs.check("\(width): the Mac's panel", mac, width < MacFrame.desktopMin ? .drawer : frame.panel)
            diffs.check("\(width): the bar's sides", MacFrame.barSide(width: width),
                        width < MacFrame.columnMin ? MacFrame.barSideNarrow : MacFrame.barSideWide)
        }
        for row in fixture["panels"]["modal"].list {
            let style = MacFrame.PanelStyle(rawValue: row["panel"].string!)!
            diffs.check("\(style): modal", MacFrame.panelIsModal(style), row["modal"].bool!)
        }
        diffs.done()
    }

    @Test func whichPanelShowsAndWhereItLies() {
        let diffs = ScreenDiffs()
        let panels = fixture["panels"]
        for row in panels["shown"].list {
            let frame = MacFrame.Frame(rawValue: row["frame"].string!)!
            let shown = MacFrame.panel(frame, info: row["info"].bool!, upNext: row["upnext"].bool!, lyrics: row["lyrics"].bool!)
            diffs.check("\(frame) \(row): shown", shown.rawValue, row["side"].string!)
        }
        #expect(panels["shown"].list.count == 16)
        for row in panels["room"].list {
            let style = MacFrame.PanelStyle(rawValue: row["panel"].string!)!
            let panel = MacFrame.Panel(rawValue: row["side"].string!)!
            diffs.check("\(style) \(panel): makes room", MacFrame.makesRoom(style, panel), row["makesRoom"].bool!)
            diffs.check("\(style) \(panel): lies over", MacFrame.liesOver(style, panel), row["liesOver"].bool!)
        }
        for (name, frame) in [("desktop", MacFrame.Frame.desktop), ("phone", .phone)] {
            let web = panels["crossing"][name]
            let crossing = MacFrame.closesOnCrossing(to: frame)
            diffs.check("into \(name)", crossing, MacFrame.Crossing(
                nowPlaying: web["nowPlaying"].bool!, infoPanel: web["infoPanel"].bool!,
                upNextPanel: web["upNextPanel"].bool!, lyricsPanel: web["lyricsPanel"].bool!))
        }
        diffs.done()
        // decision 5, from the web's own rule: the desktop has no Now Playing - and the Mac never leaves it
        #expect(panels["crossing"]["desktop"]["nowPlaying"].bool == true)
        #expect(!MacFrame.opensNowPlaying(.mac) && MacFrame.opensNowPlaying(.iPhone))
    }

    // MARK: the sidebar

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        #expect(Screens.same(MacSidebar.Words.library, words["headings"]["library"].string))
        #expect(Screens.same(MacSidebar.Words.playlists, words["headings"]["playlists"].string))
        #expect(Screens.same(MacSidebar.Words.manage, words["headings"]["manage"].string))
        #expect(Screens.same(MacSidebar.Words.searchPlaceholder, words["placeholder"].string))
        #expect(Screens.same(MacSidebar.Words.sections, words["sections"].string))
        #expect(Screens.same(MacSidebar.Words.allPlaylists, words["SIDEBAR_PLAYLISTS"]["label"].string))
        #expect(MacSidebar.Side.allCases.map(\.rawValue) == words["LIBRARY_SIDES"].list.compactMap(\.string))
        for side in MacSidebar.Side.allCases {
            #expect(Screens.same(side.label, words["SIDE_LABELS"][side.rawValue].string), "\(side)")
        }
        // each Manage row's words, and Requests' and Settings'
        for item in words["MANAGE"].list {
            guard case .some(.some(let row)) = Self.row(item["id"]) else {
                Issue.record("\(item) has no row")
                continue
            }
            #expect(Screens.same(MacSidebar.label(row), item["label"].string), "\(row)")
        }
        #expect(Screens.same(MacSidebar.label(.requests), words["TAB_LABELS"]["requests"].string))
        #expect(Screens.same(MacSidebar.label(.settings), words["TAB_LABELS"]["you"].string))
        // All's rows plainly named, the switch saying whose
        for item in words["SIDEBAR_ALL_ROWS"].list {
            guard case .some(.some(let row)) = Self.row(item["id"]) else { continue }
            #expect(Screens.same(MacSidebar.label(row), item["label"].string), "\(row)")
        }
    }

    @Test func theLibraryGroupsRowsForEachSide() {
        let diffs = ScreenDiffs()
        for row in fixture["sidebar"]["rows"].list {
            let side = MacSidebar.Side(rawValue: row["side"].string!)!
            let personal = row["personal"].bool!
            // the web's rows the Mac has (Recently added aside), in the app's standard order - then the Mac's Downloaded
            let web = row["rows"].list.compactMap { (item: Web) -> String? in
                guard case .some(.some(let mapped)) = Self.row(item["id"]) else { return nil }
                _ = mapped
                return item["label"].string
            }
            let mac = MacSidebar.rows(side, order: LibraryPages.standard, personal: personal)
            #expect(mac.last == .downloaded, "\(side), personal \(personal): Downloaded closes the group")
            diffs.check("\(side), personal \(personal): the rows' words", mac.dropLast().map(MacSidebar.label), web)
        }
        diffs.done()
    }

    @Test func eachItemsSideAndFold() {
        let diffs = ScreenDiffs()
        for row in fixture["sidebar"]["items"].list {
            guard case .some(let mapped) = Self.row(row["item"]) else { continue }
            diffs.check("\(row["item"]): its side", MacSidebar.side(of: mapped)?.rawValue, row["side"].string)
            diffs.check("\(row["item"]): its fold", MacSidebar.fold(of: mapped)?.rawValue, row["fold"].string)
        }
        diffs.done()
    }

    @Test func theSideShownAndWhatATurnOpens() {
        let diffs = ScreenDiffs()
        for row in fixture["sidebar"]["shown"].list {
            guard case .some(let current) = Self.row(row["current"]) else { continue }
            let remembered = MacSidebar.Side(rawValue: row["remembered"].string!)!
            let side = MacSidebar.sideShown(current, remembered: remembered, over: row["over"].bool!)
            diffs.check("\(row): shown", side.rawValue, row["side"].string!)
        }
        for row in fixture["sidebar"]["flips"].list {
            guard case .some(let current) = Self.row(row["current"]) else { continue }
            let to = MacSidebar.Side(rawValue: row["to"].string!)!
            let opens = MacSidebar.sideFlip(current, to: to, over: row["over"].bool!)
            guard case .some(let web) = Self.row(row["opens"]) else {
                Issue.record("\(row): opens a page the Mac hasn't")
                continue
            }
            diffs.check("\(row): opens", opens, web)
        }
        diffs.done()
    }

    @Test func whatFoldsAndWhatAFoldedHeadingSays() {
        let diffs = ScreenDiffs()
        for row in fixture["sidebar"]["folds"].list {
            guard case .some(let current) = Self.row(row["current"]) else { continue }
            let fold = MacSidebar.Fold(rawValue: row["fold"].string!)!
            let folds = MacSidebar.Folds(playlists: row["folds"]["playlists"].bool!, manage: row["folds"]["manage"].bool!)
            diffs.check("\(row): marked", MacSidebar.foldCurrent(fold, folds, current), row["marked"].bool!)
            // each playlist is its group's as All playlists is
            if current == .playlists {
                diffs.check("\(row): a playlist", MacSidebar.foldCurrent(fold, folds, .playlist("p1")), row["marked"].bool!)
            }
        }
        for row in fixture["sidebar"]["heads"].list {
            let label = MacSidebar.manageHeadLabel(folded: row["folded"].bool!, needsLook: row["needsLook"].int)
            diffs.text("\(row): Manage's heading", label, row["label"])
        }
        diffs.done()
    }

    @Test func aPagePushedAboveALibraryView() {
        let diffs = ScreenDiffs()
        for row in fixture["sidebar"]["over"].list {
            let tab: MacSidebar.Tab
            switch row["tab"].string {
            case "library": tab = .library
            case "search": tab = .search
            case "requests": tab = .requests
            default: tab = .settings
            }
            let stack = row["stack"].list.map { (page: Web) -> MacSidebar.Page in
                switch (page["kind"].string, page["id"].string) {
                case ("section", "store"): return .allAlbums
                case ("section", "storeArtists"): return .allArtists
                case ("section", "songs"): return .allSongs
                case ("playlist", let id?): return .playlist(id)
                default: return .other
                }
            }
            let at = MacSidebar.Where(tab: tab, library: stack)
            diffs.check("\(row): over", MacSidebar.overLibraryView(at), row["over"].bool!)
        }
        #expect(diffs.checked == 44)
        diffs.done()
    }

    @Test func thePlaylistsListedAndHowOneOpens() {
        #expect(MacSidebar.playlistsMax == fixture["playlists"]["max"].int)
        let diffs = ScreenDiffs()
        for row in fixture["playlists"]["listed"].list {
            let list: [Playlist]? = row["list"].isNull ? nil : row["list"].list.map { (one: Web) -> Playlist in
                Playlist(id: one["id"].string!, name: one["name"].string!, owner: one["owner"].string ?? "",
                         mine: one["mine"].bool!, editable: one["editable"].bool!)
            }
            diffs.check("\(row["name"]): the ids", MacSidebar.playlists(list).map(\.id),
                        row["shown"].list.compactMap { $0["id"].string })
            diffs.check("\(row["name"]): the names", MacSidebar.playlists(list).map(\.name),
                        row["shown"].list.compactMap { $0["name"].string })
        }
        for row in fixture["playlists"]["moves"].list {
            let page = { (web: Web) -> MacSidebar.Page in
                switch web["kind"].string {
                case "playlist": return .playlist(web["id"].string!)
                case "section": return .allAlbums
                default: return .other
                }
            }
            let how = MacSidebar.playlistsMove(row["stack"].list.map(page), page(row["page"]))
            diffs.check("\(row): how", how.rawValue, row["how"].string!)
        }
        diffs.done()
    }

    @Test func theTwoChoicesKeptOnTheDevice() {
        let kept = fixture["kept"]
        #expect(MacSidebar.sideKey == kept["keys"]["side"].string)
        #expect(MacSidebar.foldedKey == kept["keys"]["folded"].string)
        let diffs = ScreenDiffs()
        for row in kept["sides"].list {
            diffs.check("\(row): the side", MacSidebar.side(saved: row["raw"].string).rawValue, row["side"].string!)
        }
        for row in kept["folds"].list {
            let folds = MacSidebar.folds(saved: row["raw"].string)
            diffs.check("\(row): the folds", folds, MacSidebar.Folds(playlists: row["folds"]["playlists"].bool!,
                                                                     manage: row["folds"]["manage"].bool!))
        }
        for row in kept["written"].list {
            let folds = MacSidebar.Folds(playlists: row["folds"]["playlists"].bool!, manage: row["folds"]["manage"].bool!)
            diffs.text("\(row): written", MacSidebar.saved(folds), row["raw"])
            // and read back as they were
            diffs.check("\(row): read back", MacSidebar.folds(saved: MacSidebar.saved(folds)), folds)
        }
        diffs.done()
    }
}
