import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/whose.json: lib/whose.ts's albumMine over every combination of its inputs, ui/test/whose.sim.cjs's
/// cases by name, heldPhrase and heldLabel, the words, the album page's mine button and placeholder, and the page's
/// states wired into albumMine as AlbumPage.tsx wires them.
@Suite struct ScreenWhoseTests {
    let fixture = try! Web.load("whose")

    /// The words by the names the fixture gives them.
    var notes: [String: String] {
        ["ADD_FROM_PAGE": Whose.addFromPage, "ADDED_FROM_PAGE": Whose.addedFromPage, "REMOVED_FROM_PAGE": Whose.removedFromPage,
         "REMOVED_STAR_TO_RETURN": Whose.removedStarToReturn, "NO_RELEASE_TO_ADD": Whose.noReleaseToAdd,
         "NOT_FOUND_TO_ADD": Whose.notFoundToAdd]
    }

    /// [personal, starred, storeDone, bridgeFailed, bridgeYours, present, release, releaseSaid, changed]
    func mine(_ input: Web) -> AlbumMine {
        Whose.albumMine(personal: input[0].bool!, starred: input[1].bool, storeDone: input[2].bool!, bridgeFailed: input[3].bool!,
                        bridgeYours: input[4].bool, present: input[5].int!, release: input[6].string, releaseSaid: input[7].string,
                        changed: input[8].string.flatMap(AlbumMine.Change.init(rawValue:)))
    }

    /// [yours, badge, action, note (by its name), pending]
    func compare(_ label: String, _ swift: AlbumMine, _ web: Web, _ diffs: ScreenDiffs) {
        diffs.flag("\(label): yours", swift.yours, web[0])
        diffs.text("\(label): badge", swift.badge, web[1])
        diffs.text("\(label): action", swift.action?.rawValue, web[2])
        let named = web[3].string.map { notes[$0] ?? "?\($0)" }
        diffs.check("\(label): note", swift.note, named)
        diffs.flag("\(label): pending", swift.pending, web[4])
    }

    @Test func theFixtureIsThere() {
        #expect(fixture["product"].list.count == 3888)
        #expect(fixture["sim"].list.count == 14)
        #expect(fixture["wired"].list.count > 400)
        expectMadeFrom(fixture, ["ui/src/lib/whose.ts", "ui/src/player/AlbumPage.tsx the mine wiring",
                                 "ui/src/player/AlbumPage.tsx release and storeDone", "ui/src/player/AlbumPage.tsx the mine button",
                                 "ui/src/player/AlbumPage.tsx the badge shown", "ui/src/player/AlbumPage.tsx the placeholder shown",
                                 "ui/src/player/AlbumPage.tsx the mine block shown"])
    }

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        #expect(Whose.inYourLibrary == words["IN_YOUR_LIBRARY"].string)
        #expect(Whose.inTheCollection == words["IN_THE_STORE"].string)
        for (name, text) in notes { #expect(Screens.same(text, words[name].string), "\(name)") }
        //? vocabulary.sim.cjs: none of what a listener reads names the store, starring, Subsonic or Navidrome
        let banned = [#"(?i)\bstore\b"#, #"(?i)\bstar(?:s|red|ring)?\b"#, #"\bSubsonic\b"#, #"\bNavidrome\b"#, #"(?i)\b(?:the|in the|from the) store\b"#]
        let said = Array(notes.values) + [Whose.inYourLibrary, Whose.inTheCollection, Whose.placeholderButton]
            + AlbumMine.Action.allCases.flatMap { [Whose.button($0, busy: false), Whose.button($0, busy: true)] }
        for pattern in banned {
            let regex = try! NSRegularExpression(pattern: pattern)
            for text in said {
                #expect(regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) == nil, "\(pattern) in \(text)")
            }
        }
    }

    @Test func heldPhraseAndLabelAreTheWebs() {
        for row in fixture["held"].list {
            //? "undefined" and null both: nothing said of whose it is
            let yours = row["yours"].bool
            #expect(Whose.heldPhrase(personal: row["personal"].bool!, yours: yours) == row["phrase"].string, "\(row)")
            #expect(Whose.heldLabel(personal: row["personal"].bool!, yours: yours) == row["label"].string, "\(row)")
        }
    }

    @Test func theMineButtonAndPlaceholderAreTheWebs() {
        for row in fixture["buttons"].list {
            let action = AlbumMine.Action(rawValue: row["action"].string!)!
            #expect(Whose.button(action, busy: row["busy"].bool!) == row["words"].string, "\(row)")
        }
        #expect(Whose.placeholderButton == fixture["placeholder"].string)
    }

    /// whose.sim.cjs's cases, each by its name.
    @Test func theSimsCases() {
        let diffs = ScreenDiffs()
        for named in fixture["sim"].list {
            for (index, one) in named["cases"].list.enumerated() {
                compare("\(named["name"].string ?? "?") #\(index)", mine(one[0]), one[1], diffs)
            }
        }
        diffs.done()
    }

    @Test func everyCombinationOfItsInputs() {
        let diffs = ScreenDiffs()
        for row in fixture["product"].list { compare("albumMine(\(row[0]))", mine(row[0]), row[1], diffs) }
        diffs.done()
    }

    /// The album page's state - its album answer (or none, or its failure), the id bridge's answer (or its failure),
    /// the last change - into albumMine as AlbumPage.tsx wires it; and what the page draws of it, and when: the badge,
    /// the unseen placeholder and the mine block, with this page's last Add or Remove refused and not.
    @Test func thePagesWiringIsTheWebs() {
        let diffs = ScreenDiffs()
        var drawn = 0
        for row in fixture["wired"].list {
            let album: Album? = row["album"].isNull ? nil
                : Album(id: row["album"]["id"].string!, musicBrainzId: row["album"]["musicBrainzId"].string, starred: row["album"]["starred"].string)
            let store: StoreAlbum? = row["store"].isNull ? nil : StoreAlbum(
                releaseMbid: row["store"]["release_mbid"].string,
                present: (0..<(row["store"]["present"].int ?? 0)).map { StoreRow(id: $0, path: "/music/\($0)") },
                yours: row["store"]["yours"].bool)
            let swift = Whose.albumMine(personal: row["personal"].bool!, album: album, albumFailed: row["error"].bool!, store: store,
                                        storeFailed: row["storeFailed"].bool!,
                                        changed: row["changed"].string.flatMap(AlbumMine.Change.init(rawValue:)))
            compare("wired \(row)", swift, row["mine"], diffs)
            //? the web asks the bridge always: its badge waits for it, as ours does whenever we ask it
            let storeDone = store != nil || row["storeFailed"].bool!
            let shown = row["shown"]
            diffs.flag("wired \(row): badge shown", Whose.badgeShown(swift, storeDone: storeDone, bridgeAsked: true), shown["badge"])
            for (index, refused) in [false, true].enumerated() {
                diffs.flag("wired \(row): placeholder (refused \(refused))", Whose.placeholderShown(swift, albumIn: album != nil, refused: refused),
                           shown["placeholder"][index])
                diffs.flag("wired \(row): mine block (refused \(refused))", Whose.mineBlockShown(swift, refused: refused), shown["block"][index])
            }
            if shown["placeholder"][0].bool == true { drawn += 1 }
        }
        diffs.done()
        #expect(drawn > 0, "some state draws the placeholder")
    }

    /// The phone's Phase 1 asks the id bridge only with a library of its own (screens.md, open question 10): without
    /// one there is nothing to wait for, so the badge - "In your library" - is drawn at once, which the web's
    /// `storeDone && !mine.pending` would never do with no bridge asked.
    @Test func withNoLibraryTheBadgeIsDrawnAtOnce() {
        let noLibrary = Whose.albumMine(personal: false, album: nil, albumFailed: false, store: nil, storeFailed: false, changed: nil)
        #expect(noLibrary.badge == "In your library" && !noLibrary.pending)
        #expect(Whose.badgeShown(noLibrary, storeDone: false, bridgeAsked: false))
        #expect(!Whose.badgeShown(noLibrary, storeDone: false, bridgeAsked: true), "the web's rule: waits for the bridge it asked")
        #expect(!Whose.placeholderShown(noLibrary, albumIn: true, refused: false) && !Whose.mineBlockShown(noLibrary, refused: false))
        //? with a library the bridge is asked, and the badge waits for it and for whose it is
        let pending = Whose.albumMine(personal: true, album: Album(id: "al", starred: nil), albumFailed: false, store: nil, storeFailed: false,
                                      changed: nil)
        #expect(pending.pending && !Whose.badgeShown(pending, storeDone: false, bridgeAsked: true))
        #expect(Whose.placeholderShown(pending, albumIn: true, refused: false) && !Whose.placeholderShown(pending, albumIn: true, refused: true))
        #expect(!Whose.mineBlockShown(pending, refused: false) && Whose.mineBlockShown(pending, refused: true))
    }

    @Test("logins off: \"In your library\", nothing offered - as it always was")
    func loginsOff() {
        let mine = Whose.albumMine(personal: false, starred: nil, storeDone: false, bridgeYours: nil, present: 1, release: "r", changed: nil)
        #expect(mine == AlbumMine(yours: true, badge: "In your library", action: nil, note: nil, pending: false))
    }

    @Test("a Remove just taken: \"In the collection\", saying nothing was deleted, Add to undo it - even over a stale `starred`")
    func removedOverAStaleStar() {
        let mine = Whose.albumMine(personal: true, starred: true, storeDone: true, bridgeYours: true, present: 1, release: "rel-third",
                                   releaseSaid: "rel-third", changed: .removed)
        #expect(mine == AlbumMine(yours: false, badge: "In the collection", action: .add, note: Whose.removedFromPage, pending: false))
    }
}
