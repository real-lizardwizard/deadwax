import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/managing/managing-vectors.json: the web's lib/permissions.ts (`managing`, `albumEdit`), app/access.ts
/// (`accessOf`, `seesDetail`), lib/ownPassword.ts (`changeOffered`) and lib/appRoutes.ts (`formatRoute`, `parseHash`)
/// run as they are, and You.tsx's Manage section read out of its source - replayed here through Managing and Access,
/// case for case (notes/ios-specs/phase7-managing.md 6).
@Suite struct ManagingVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("managing/managing-vectors.json"))

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-managing-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/permissions.ts", "ui/src/lib/appRoutes.ts", "ui/src/lib/ownPassword.ts",
                                 "ui/src/app/access.ts", "ui/src/app/You.tsx the Manage section",
                                 "ui/src/app/You.tsx the Manage title", "ui/src/app/You.tsx You's managing"])
        #expect(fixture["sets"].list.count == 64)
        #expect(fixture["me"].list.count == 20)
        #expect(fixture["albums"].list.count == 14)
    }

    private static func permissions(_ list: Web) -> Set<Access.Permission> {
        Set(list.list.compactMap { $0.string.flatMap(Access.Permission.init(rawValue:)) })
    }

    private static func parts(_ web: Web) -> Managing.Parts {
        Managing.Parts(queue: web["queue"].bool!, care: web["care"].bool!, people: web["people"].bool!,
                       settings: web["settings"].bool!, log: web["log"].bool!)
    }

    private static func albumEdit(_ web: Web) -> Managing.AlbumEdit {
        Managing.AlbumEdit(shown: web["shown"].bool!, editors: web["editors"].bool!, delete: web["delete"].bool!)
    }

    /// The section's title, its rows' labels in the web's order, and the permissions in /me's order.
    @Test func theWordsAndTheOrderAreTheWebs() {
        let words = fixture["words"]
        #expect(Screens.same(ManagingWords.title, words["title"].string))
        #expect(Screens.same(ManagingWords.changePassword, words["CHANGE_TITLE"].string))
        let rows = words["rows"].list
        // the web's five, in its order, after the phone's own first row
        #expect(rows.compactMap { $0["part"].string } == Managing.Tool.allCases.dropFirst().map(\.rawValue))
        for row in rows {
            let tool = Managing.Tool(rawValue: row["part"].string ?? "")
            #expect(tool != nil && tool != .edit)
            if let tool { #expect(Screens.same(ManagingWords.label(tool), row["label"].string), "\(tool)") }
        }
        #expect(words["PERMISSIONS"].list.compactMap(\.string) == Access.Permission.allCases.map(\.rawValue))
        // the phone's own row names none of the web's
        #expect(!rows.contains { $0["label"].string == ManagingWords.editAnAlbum })
    }

    @Test func everySetOfPermissionsShowsTheWebsParts() {
        let diffs = ScreenDiffs()
        for row in fixture["sets"].list {
            let permissions = Self.permissions(row["permissions"])
            let label = permissions.map(\.rawValue).sorted().joined(separator: ",")
            diffs.check("\(label), logins on", Managing.parts(permissions, loginsOn: true), Self.parts(row["on"]))
            diffs.check("\(label), logins off", Managing.parts(permissions, loginsOn: false), Self.parts(row["off"]))
            diffs.check("\(label): any, on", Managing.parts(permissions, loginsOn: true).any, row["on"]["any"].bool!)
            diffs.check("\(label): any, off", Managing.parts(permissions, loginsOn: false).any, row["off"]["any"].bool!)
            diffs.check("\(label): the album's Edit", Managing.albumEdit(permissions), Self.albumEdit(row["albumEdit"]))
        }
        #expect(diffs.checked == 64 * 5)
        diffs.done()
    }

    /// From /me to the rows: Access as the web reads the answer, You's own `managing` call, the album's Edit, who sees
    /// the detail and who is offered Change password - and the rows the phone draws from them.
    @Test func everyAnswerOfMeShowsTheWebsRows() {
        let diffs = ScreenDiffs()
        for row in fixture["me"].list {
            let who = row["me"]
            let me = Me(user: who["user"].string!, admin: who["admin"].bool!, auth: who["auth"].string!,
                        permissions: who["permissions"].isNull ? nil : who["permissions"].list.compactMap(\.string),
                        permissionsUnverified: who["permissions_unverified"].bool)
            let access = Access(me: me)
            let label = "\(me.user)/\(me.auth)/\(me.permissions?.joined(separator: ",") ?? "-")"
            diffs.check("\(label): permissions", access.permissions, Self.permissions(row["access"]["permissions"]))
            diffs.check("\(label): on", access.on, row["access"]["on"].bool!)
            diffs.check("\(label): admin", access.admin, row["access"]["admin"].bool!)
            diffs.check("\(label): unverified", access.unverified, row["access"]["unverified"].bool!)
            let parts = Self.parts(row["managing"])
            diffs.check("\(label): managing", Managing.parts(access.permissions, loginsOn: access.on), parts)
            let edit = Self.albumEdit(row["albumEdit"])
            diffs.check("\(label): the album's Edit", Managing.albumEdit(access.permissions), edit)
            diffs.check("\(label): sees the detail", access.seesDetail, row["seesDetail"].bool!)
            diffs.check("\(label): Change password", Managing.changeOffered(me), row["changeOffered"].bool!)
            // the rows: Edit an album by the album's Edit, then the web's five by its parts, in its order
            let web: [Managing.Tool] = (edit.shown ? [.edit] : []) + fixture["words"]["rows"].list.compactMap { rowWeb in
                guard let part = rowWeb["part"].string, row["managing"][part].bool == true else { return nil }
                return Managing.Tool(rawValue: part)
            }
            diffs.check("\(label): the rows", Managing.tools(access), web)
        }
        #expect(diffs.checked == 20 * 9)
        diffs.done()
    }

    /// Every Managing page's address as You opens it, the Library's and You's roots, an album's for every kind of id -
    /// and each one, opened cold in the web app, is that very page, its address kept.
    @Test func everyAddressIsTheWebsAndOpensAsItself() throws {
        let server = try ServerAddress.parse("http://192.168.3.20:8090").get()
        let addresses = fixture["addresses"]
        let base = "http://192.168.3.20:8090/player/"
        for tool in Managing.Tool.allCases where tool != .edit {
            let page = addresses["pages"][tool.rawValue]
            #expect("#" + Managing.fragment(tool) == page["hash"].string, "\(tool)")
            #expect(Managing.url(tool, at: server)?.absoluteString == base + (page["hash"].string ?? "?"), "\(tool)")
            #expect(page["kept"].bool == true && page["opens"]["page"]["kind"].string == tool.rawValue, "\(tool)")
            #expect(Screens.same(ManagingWords.label(tool), page["label"].string), "\(tool)'s page is named as its row")
        }
        #expect("#" + Managing.fragment(.edit) == addresses["library"]["hash"].string)
        #expect(addresses["library"]["kept"].bool == true && addresses["library"]["opens"]["page"].isNull)
        #expect("#" + Managing.youFragment == addresses["you"]["hash"].string)
        #expect(addresses["you"]["kept"].bool == true && addresses["you"]["opens"]["tab"].string == "you")
        #expect(Managing.youURL(at: server)?.absoluteString == base + "#/you")
        for album in fixture["albums"].list {
            let id = album["id"].string!
            #expect("#" + Managing.albumFragment(id: id) == album["hash"].string, "\(id)")
            #expect(Managing.albumURL(id: id, at: server)?.absoluteString == base + (album["hash"].string ?? "?"), "\(id)")
            #expect(album["kept"].bool == true && album["opens"]["page"]["id"].string == id, "\(id) opens as itself")
        }
    }
}
