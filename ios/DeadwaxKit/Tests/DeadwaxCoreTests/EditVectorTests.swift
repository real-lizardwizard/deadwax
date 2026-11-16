import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/edit/edit-vectors.json: the web's lib/albumEdit.ts, lib/release.ts, lib/retagPlan.ts, lib/metadataQueue.ts,
/// lib/typedMatch.ts and lib/releasePayload.ts run as they are, and components/MetadataEditor.tsx's own rules and words
/// read out of its source - replayed here through AlbumEdit, TypedMatch, MetadataQueue, Retag and RetagWords, case for
/// case (notes/ios-specs/phase8-managing.md 3.1-3.3, 3.7).
@Suite struct EditVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("edit/edit-vectors.json"))

    // MARK: reading the fixture

    /// A fixture's value as JSON, for a model's own decoder.
    static func data(_ web: Web) -> Data {
        try! JSONSerialization.data(withJSONObject: foundation(web), options: [.fragmentsAllowed])
    }

    static func foundation(_ web: Web) -> Any {
        switch web {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .number(let number): return number
        case .string(let text): return text
        case .array(let list): return list.map(foundation)
        case .object(let fields): return fields.mapValues(foundation)
        }
    }

    static func decoded<T: Decodable>(_ type: T.Type, _ web: Web) -> T {
        try! JSONDecoder().decode(type, from: data(web))
    }

    /// What the phone sends, as the fixture holds the web's.
    static func json(_ value: some Encodable) -> Web {
        try! JSONDecoder().decode(Web.self, from: JSONEncoder().encode(value))
    }

    /// Two JSON values the same: every key, strings by UTF-16 unit, numbers by value.
    static func same(_ a: Web, _ b: Web) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.string(let x), .string(let y)): return Screens.same(x, y)
        case (.array(let x), .array(let y)): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        case (.object(let x), .object(let y)):
            return Set(x.keys) == Set(y.keys) && x.keys.allSatisfy { same(x[$0]!, y[$0]!) }
        default: return false
        }
    }

    static func scanAlbum(_ web: Web) -> ScanAlbum { decoded(ScanAlbum.self, web) }

    static func fields(_ web: Web) -> RetagFields {
        RetagFields(artist: web["artist"].string!, album: web["album"].string!, year: web["year"].string!,
                    originalYear: web["originalYear"].string!, editionLabel: web["editionLabel"].string!)
    }

    static func folders(_ web: Web) -> AlbumEdit.Folders {
        AlbumEdit.Folders(paths: web["paths"].list.compactMap(\.string), from: AlbumEdit.From(rawValue: web["from"].string!)!)
    }

    // MARK: the fixture, the numbers, the words

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-edit-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/albumEdit.ts", "ui/src/lib/release.ts", "ui/src/lib/retagPlan.ts",
                                 "ui/src/lib/metadataQueue.ts", "ui/src/lib/typedMatch.ts", "ui/src/lib/releasePayload.ts",
                                 "ui/src/components/MetadataEditor.tsx the payload",
                                 "ui/src/components/MetadataEditor.tsx the fields a pick seeds",
                                 "ui/src/components/MetadataEditor.tsx the first search",
                                 "ui/src/components/MetadataEditor.tsx the loose search",
                                 "tests/fixtures/pressings/third.json"])
        #expect(fixture["folders"].list.count == 160)
        #expect(fixture["statuses"].list.count == 220)
        #expect(fixture["payloads"].list.count == 140)
        #expect(fixture["plans"]["plans"].list.count == 120)
        #expect(fixture["pressings"].list.count == 4)
    }

    @Test func theNumbersAreTheWebs() {
        let words = fixture["words"]
        #expect(words["GROUPS_SEARCHED"].int == Retag.groupsSearched)
        #expect(words["PREVIEW_DEBOUNCE_MS"].int == Retag.previewDebounceMs)
        #expect(words["SEARCH_LIMIT"].int == Retag.searchLimit)
        #expect(words["FOLDER_CHOICES_SHOWN"].int == AlbumEdit.folderChoicesShown)
        #expect(words["EDIT_SETTLE_MS"].int == AlbumEdit.settleMs)
        #expect(words["FOLLOW_LOOKS_MS"].list.compactMap(\.int) == AlbumEdit.followLooksMs)
        // the editors, in the web's order and words
        let tabs = words["EDIT_TABS"].list
        #expect(tabs.compactMap { $0["id"].string } == AlbumEdit.Part.allCases.map(\.rawValue))
        for tab in tabs {
            let part = AlbumEdit.Part(rawValue: tab["id"].string ?? "")
            #expect(part != nil && Screens.same(part?.label, tab["label"].string))
        }
        // Apply's off by exactly what RetagFlow.canApply reads (the exporter stops when it changes)
        #expect(words["applyOff"].string == "!plan || plan.empty || planning || applying || loadingRelease")
    }

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        let diffs = ScreenDiffs()
        diffs.text("searching", RetagWords.searching, words["searching"])
        diffs.text("noReleases", RetagWords.noReleases, words["noReleases"])
        diffs.text("currentMissing", RetagWords.currentMissing, words["currentMissing"])
        diffs.text("notSearched", RetagWords.notSearched, words["notSearched"])
        diffs.text("searchAway", RetagWords.searchAway, words["searchAway"])
        diffs.text("tracklistAway", RetagWords.tracklistAway, words["tracklistAway"])
        diffs.text("searchFailed", RetagWords.searchFailed, words["searchFailed"])
        diffs.text("releaseFailed", RetagWords.releaseFailed, words["releaseFailed"])
        diffs.text("coverFailed", RetagWords.coverFailed, words["coverFailed"])
        diffs.text("fieldsHint", RetagWords.fieldsHint, words["fieldsHint"])
        diffs.text("current", RetagWords.current, words["current"])
        diffs.text("apply", RetagWords.apply, words["apply"])
        diffs.text("fine", RetagWords.fine, words["fine"])
        diffs.text("markingFine", RetagWords.markingFine, words["markingFine"])
        diffs.text("askAgain", RetagWords.askAgain, words["askAgain"])
        diffs.text("PREVIEW_FAILED", RetagWords.previewFailed, words["PREVIEW_FAILED"])
        diffs.text("APPLY_FAILED", RetagWords.applyFailed, words["APPLY_FAILED"])
        diffs.text("NOTHING_TO_CHANGE", RetagWords.nothingToChange, words["NOTHING_TO_CHANGE"])
        // the library unread, as EditPanel says it, and a Managing page's 403
        diffs.text("READ_FAILED", EditWords.readFailed, words["READ_FAILED"])
        diffs.text("NO_PERMISSION", EditWords.noPermission, words["NO_PERMISSION"])
        let compare = words["compare"]
        diffs.text("compare current", RetagWords.compareCurrent, compare["current"])
        diffs.text("compare none", RetagWords.compareNoCover, compare["noCover"])
        diffs.text("compare this", RetagWords.compareFromThis, compare["fromThis"])
        diffs.text("compare tagged", RetagWords.compareFromTagged, compare["fromTagged"])
        diffs.text("compare archive", RetagWords.compareArchiveNone, compare["archiveNone"])
        diffs.text("compare pick", RetagWords.comparePick, compare["pick"])
        for row in words["planning"].list {
            diffs.text("planning \(row["loading"])", RetagWords.planningLabel(loadingRelease: row["loading"].bool!), row["label"])
        }
        // "Marked fine: " and the labels, joined as the web joins them
        #expect(words["markedFine"].string?.hasPrefix("Marked fine: {markedFine.map") == true)
        #expect(words["markedFine"].string?.hasSuffix(".join(', ')}") == true)
        #expect(RetagWords.markedFine(["No cover", "No release"]) == "Marked fine: No cover, No release")
        diffs.done()
    }

    // MARK: which folder

    @Test func everyAlbumFindsTheWebsFolders() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["folders"].list.enumerated() {
            let raw = row["raw"]
            let subject = AlbumEdit.Subject(id: raw["id"].string!, name: raw["name"].string!, artist: raw["artist"].string,
                                            songCount: raw["songCount"].int, musicBrainzId: raw["musicBrainzId"].string)
            let web = row["album"]
            diffs.text("\(at): artist", subject.artist, web["artist"])
            diffs.check("\(at): songCount", subject.songCount, web["songCount"].int)
            diffs.text("\(at): musicBrainzId", subject.musicBrainzId, web["musicBrainzId"])
            let answer = row["answer"]
            let bridge = answer.isNull ? nil : AlbumEdit.Bridge(releaseMbid: answer["release_mbid"].string,
                                                                 present: answer["present"].list.compactMap { $0["path"].string })
            let scan = row["scan"].list.map(Self.scanAlbum)
            let found = AlbumEdit.folders(bridge, scan, subject)
            diffs.check("\(at): folders", found, Self.folders(row["folders"]))
            diffs.check("\(at): needs a choice", AlbumEdit.needsChoice(found), row["needsChoice"].bool!)
        }
        #expect(AlbumEdit.folderOnly("A/B") == AlbumEdit.Folders(paths: ["A/B"], from: .folder))
        #expect(AlbumEdit.folderOnly("") == .nowhere)
        diffs.done()
    }

    @Test func chooseTheFolderListsTheWebsFolders() {
        let diffs = ScreenDiffs()
        let choices = fixture["choices"]
        let scan = choices["scan"].list.map(Self.scanAlbum)
        for row in choices["cases"].list {
            let typed = row["typed"].string!, limit = row["limit"].int!
            let (shown, matching) = AlbumEdit.folderChoices(scan, typed: typed, limit: limit)
            let label = "\(Screens.spelled(typed)) limit \(limit)"
            // by index: two folders of one path are told apart by where they were
            let indices = shown.map { album in scan.indices.first { scan[$0] == album }! }
            diffs.check("\(label): shown", indices, row["shown"].list.compactMap(\.int))
            diffs.check("\(label): matching", matching, row["matching"].int!)
            diffs.text("\(label): words", AlbumEdit.folderChoicesWords(shown: shown.count, matching: matching, typed: typed),
                       row["words"])
        }
        for row in choices["many"].list {
            diffs.text("many \(row["shown"]) of \(row["matching"])",
                       AlbumEdit.folderChoicesWords(shown: row["shown"].int!, matching: row["matching"].int!,
                                                    typed: row["typed"].string!), row["words"])
        }
        for row in fixture["typed"].list {
            let label = "\(Screens.spelled(row["hay"].string)) / \(Screens.spelled(row["typed"].string))"
            diffs.check("\(label): matches", TypedMatch.matches(row["hay"].string!, typed: row["typed"].string!), row["matches"].bool!)
            diffs.text("\(label): fold", TypedMatch.fold(row["typed"].string), row["fold"])
        }
        diffs.done()
    }

    // MARK: what the editor says, following the album

    @Test func everyStatusIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["statuses"].list.enumerated() {
            let facts = row["facts"]
            let status = AlbumEdit.status(AlbumEdit.StatusFacts(
                deleted: facts["deleted"].string, problem: facts["problem"].string, error: facts["error"].string,
                albums: facts["albums"].int!, loaded: facts["loaded"].bool!, stale: facts["stale"].bool!,
                asked: facts["asked"].bool!, folders: facts["folders"].isNull ? nil : Self.folders(facts["folders"]),
                holding: facts["holding"].bool!, listed: facts["listed"].bool == true, release: facts["release"].string))
            let web = row["status"]
            if web.isNull {
                diffs.check("\(at): no status", status == nil, true)
                continue
            }
            diffs.text("\(at): text", status?.text, web["text"])
            diffs.check("\(at): busy", status?.busy, web["busy"].bool == true)
            diffs.check("\(at): retry", status?.retry, web["retry"].bool == true)
            diffs.check("\(at): choose", status?.choose, web["choose"].bool == true)
        }
        diffs.done()
    }

    @Test func theAlbumIsFollowedAsTheWebFollowsIt() {
        let diffs = ScreenDiffs()
        let follow = fixture["follow"]
        for row in follow["releases"].list {
            diffs.text("follow \(row["before"]) -> \(row["after"])",
                       AlbumEdit.followRelease(before: row["before"].string, after: row["after"].string), row["follow"])
        }
        for row in follow["to"].list {
            diffs.text("to \(row["page"]) / \(row["found"])",
                       AlbumEdit.followsTo(pageId: row["page"].string!, found: row["found"].string), row["to"])
        }
        for (at, run) in follow["runs"].list.enumerated() {
            var moves: [String: String] = [:]
            for step in run["steps"].list { AlbumEdit.noteMove(&moves, from: step[0].string!, to: step[1].string!) }
            let web = Dictionary(uniqueKeysWithValues: run["moves"].list.map { ($0[0].string!, $0[1].string!) })
            diffs.check("run \(at): moves", moves, web)
            for end in run["ends"].list {
                diffs.text("run \(at): \(end[0])", AlbumEdit.movedTo(moves, end[0].string!), end[1])
            }
        }
        diffs.done()
    }

    // MARK: the editors, what is wrong

    @Test func thePartsAndTheMarksAreTheWebs() {
        let parts = fixture["parts"]
        for row in parts["tabs"].list {
            let shown = AlbumEdit.parts(editors: row["editors"].bool!, remove: row["remove"].bool!).map(\.rawValue)
            #expect(shown == row["tabs"].list.compactMap(\.string))
        }
        let fine = parts["fine"].list
        #expect(fine.count == 64)
        for row in fine {
            let permissions = Set(row["permissions"].list.compactMap { $0.string.flatMap(Access.Permission.init(rawValue:)) })
            #expect(AlbumEdit.marksFine(permissions) == row["marksFine"].bool!, "\(permissions)")
        }
        let queue = fixture["queue"]
        let types = Self.decoded([String: MetadataIssueType].self, queue["types"])
        for row in queue["cases"].list {
            let album = ScanAlbum(path: "A/B", issues: row["issues"].list.compactMap(\.string),
                                  ignoredIssues: row["ignored"].list.compactMap(\.string))
            #expect(MetadataQueue.outstanding(album) == row["outstanding"].list.compactMap(\.string))
            #expect(MetadataQueue.markedFine(album) == row["markedFine"].list.compactMap(\.string))
            #expect(album.issues.map { MetadataQueue.label($0, types) } == row["labels"].list.compactMap(\.string))
        }
    }

    // MARK: the search

    @Test func theQueriesAreTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["queries"]["cases"].list.enumerated() {
            let fields = Self.fields(row["fields"])
            let typed = row["query"].string!
            diffs.text("\(at): fielded", Retag.fieldedQuery(album: fields.album, artist: fields.artist), row["fielded"])
            diffs.text("\(at): plain", Retag.plainQuery(album: fields.album, artist: fields.artist), row["plain"])
            diffs.text("\(at): first", Retag.firstQuery(typed: typed, fields: fields), row["first"])
            diffs.text("\(at): loose", Retag.looseQuery(typed: typed, fields: fields), row["loose"])
            // groups found: never the loose words (the model asks looseQuery only when none were)
            diffs.check("\(at): loose with groups", row["looseWithGroups"].bool!, false)
        }
        for row in fixture["queries"]["opens"].list {
            let album = ScanAlbum(path: "A/B", artist: row["artist"].string!, album: row["album"].string!)
            diffs.check("opens \(row["artist"]) \(row["album"])", Retag.searchesAtOnce(album), row["searches"].bool!)
        }
        diffs.done()
    }

    @Test func theGroupsAreRankedAsTheWebRanksThem() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["groupScores"].list.enumerated() {
            let fields = Self.fields(row["fields"])
            let groups = row["groups"].list.map { Self.decoded(ReleaseGroup.self, $0) }
            for (index, group) in groups.enumerated() {
                diffs.number("\(at).\(index): score", Retag.score(group, fields: fields), row["scores"][index])
            }
            let ranked = Retag.rankGroups(groups, fields: fields).map { group in groups.firstIndex { $0.id == group.id }! }
            diffs.check("\(at): ranked", ranked, row["ranked"].list.compactMap(\.int))
        }
        diffs.done()
    }

    @Test func thePressingsAreRankedAndSaidAsTheWebDoes() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["releaseScores"].list.enumerated() {
            let album = Self.scanAlbum(row["album"])
            let releases = row["releases"].list.map { Self.decoded(PageRelease.self, $0) }
            for (index, release) in releases.enumerated() {
                let web = row["rows"][index], label = "\(at).\(index)"
                diffs.check("\(label): score", Retag.score(release, album: album), web["score"].int!)
                diffs.check("\(label): tracks", Retag.trackCount(release), web["tracks"].int!)
                diffs.text("\(label): described", Retag.describe(release), web["described"])
                diffs.text("\(label): detail", Retag.detail(release), web["detail"])
                diffs.text("\(label): track words", Retag.trackWords(release), web["trackWords"])
                diffs.check("\(label): mismatch", Retag.countDiffers(release, album: album), web["mismatch"].bool!)
                diffs.check("\(label): current", Retag.isCurrent(release, album.releaseMbid), web["current"].bool!)
            }
            // by index: made pressings can share an id
            let found = releases.enumerated().map { RetagCandidate(release: $0.element, groupMbid: "\($0.offset)", firstReleaseDate: nil) }
            let ranked = Retag.rankReleases(found, album: album).map { Int($0.groupMbid!)! }
            diffs.check("\(at): ranked", ranked, row["ranked"].list.compactMap(\.int))
        }
        diffs.done()
    }

    // MARK: the payload

    static func candidate(_ row: Web) -> RetagCandidate? {
        guard !row["release"].isNull else { return nil }
        let group = row["group"]
        return RetagCandidate(release: decoded(PageRelease.self, row["release"]),
                              groupMbid: group.isNull ? nil : group["id"].string,
                              firstReleaseDate: group.isNull ? nil : group["first-release-date"].string)
    }

    @Test func applySendsWhatTheWebSends() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["payloads"].list.enumerated() {
            let album = Self.scanAlbum(row["album"])
            let fields = Self.fields(row["fields"])
            let selected = Self.candidate(row)
            let payload = Retag.payload(selected: selected, album: album, fields: fields)
            diffs.check("\(at): payload", Self.same(Self.json(payload), row["payload"]), true)
            if let selected {
                let built = Retag.release(selected.release, context: Retag.Context(
                    artist: album.artist, album: album.album, releaseGroupMbid: selected.groupMbid,
                    firstReleaseDate: selected.firstReleaseDate))
                diffs.check("\(at): built", Self.same(Self.json(built), row["built"]), true)
                let seeded = Retag.seeded(selected, album: album)
                diffs.check("\(at): seeded", seeded, Self.fields(row["seeded"]))
            }
        }
        diffs.done()
    }

    /// The editor's payload is not a Get's (phase8-managing.md 3.3): the web's own two builders, over the same pressing,
    /// differ exactly as Retag.release keeps them apart from GetRelease.payload - no album artist, a track credited to
    /// nobody null where a Get says "N/A", and the country by `??`.
    @Test func thePayloadIsNotAGets() {
        var nobody = 0, emptyCountry = 0
        for row in fixture["payloads"].list where !row["release"].isNull {
            let built = row["built"], download = row["download"]
            #expect(built["album_artist"].isNull && !download["album_artist"].isNull)
            // no credit at all is null in both; a credit naming nobody is null here and "N/A" in a Get
            for (mine, theirs) in zip(built["tracks"].list, download["tracks"].list) where mine["artist"].isNull {
                #expect(theirs["artist"].isNull || theirs["artist"].string == "N/A")
                if theirs["artist"].string == "N/A" { nobody += 1 }
            }
            if built["country"].string == "" {
                #expect(download["country"].string != "")
                emptyCountry += 1
            }
            // and the phone's own builder answers as the editor's, never as a Get's
            let release = Self.decoded(PageRelease.self, row["release"])
            let phone = Self.json(Retag.release(release, context: .init(artist: "", album: "")))
            #expect(phone["album_artist"].isNull)
            for track in phone["tracks"].list { #expect(track["artist"].string != "N/A") }
        }
        #expect(nobody > 0, "a credit of nobody was tried")
        #expect(emptyCountry > 0, "an empty event country was tried")
    }

    @Test func theRealPressingsAreRankedAndBuiltAsTheWebDoes() {
        let diffs = ScreenDiffs()
        for set in fixture["pressings"].list {
            let name = set["name"].string!
            // tests/fixtures/pressings/<name>.json's, as MusicBrainz answered them (the exporter hashes each file)
            let releases = set["releases"].list.map { Self.decoded(PageRelease.self, $0) }
            let album = Self.scanAlbum(set["album"])
            let group = set["group"]
            let found = releases.map { RetagCandidate(release: $0, groupMbid: group["id"].string,
                                                      firstReleaseDate: group["first-release-date"].string) }
            diffs.check("\(name): ranked", Retag.rankReleases(found, album: album).map(\.id),
                        set["ranked"].list.compactMap(\.string))
            let fields = RetagFields(album)
            for (index, web) in set["built"].list.enumerated() {
                let candidate = found[index]
                diffs.check("\(name) \(index): id", candidate.id, web["id"].string!)
                diffs.check("\(name) \(index): payload",
                            Self.same(Self.json(Retag.payload(selected: candidate, album: album, fields: fields)), web["payload"]), true)
                diffs.check("\(name) \(index): seeded", Retag.seeded(candidate, album: album), Self.fields(web["seeded"]))
                diffs.text("\(name) \(index): described", Retag.describe(candidate.release), web["described"])
                diffs.text("\(name) \(index): detail", Retag.detail(candidate.release), web["detail"])
            }
        }
        diffs.done()
    }

    @Test func theEditorOpensSeededAsTheWebDoes() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["seeds"].list.enumerated() {
            let album = Self.scanAlbum(row["album"])
            diffs.check("\(at): fields", RetagFields(album), Self.fields(row["fields"]))
            diffs.check("\(at): fetch art", album.art.isEmpty, row["fetchArt"].bool!)
            let payload = Retag.payload(selected: nil, album: album, fields: RetagFields(album))
            diffs.check("\(at): no pressing", Self.same(Self.json(payload), row["unselected"]), true)
        }
        diffs.done()
    }

    // MARK: the preview's and the apply's words

    @Test func thePreviewIsSaidAsTheWebSaysIt() throws {
        let diffs = ScreenDiffs()
        let plans = fixture["plans"]
        for (at, row) in plans["plans"].list.enumerated() {
            let body = try #require(row["body"].string)
            let plan = try RetagPlan.read(Data(body.utf8))
            let order = plan.files.map { $0.changes.map(\.tag) }
            diffs.check("\(at): order", order, row["order"].list.map { $0.list.compactMap(\.string) })
            diffs.text("\(at): move", RetagWords.moveLabel(plan), row["moveLabel"])
            diffs.text("\(at): rename wait", RetagWords.renameWait(plan), row["renameWait"])
            diffs.text("\(at): merge", RetagWords.merge(plan), row["merge"])
            diffs.text("\(at): summary", RetagWords.changeSummary(plan), row["summary"])
            diffs.text("\(at): applying", RetagWords.applying(plan), row["applying"])
            diffs.text("\(at): cover box", RetagWords.coverToggle(existing: plan.art.existing), row["coverToggle"])
            diffs.text("\(at): cover line", RetagWords.coverHint(existing: plan.art.existing, size: plan.art.size), row["coverHint"])
            diffs.text("\(at): edition", RetagWords.editionPlaceholder(plan), row["editionPlaceholder"])
        }
        for (at, row) in plans["results"].list.enumerated() {
            let results = Self.decoded(RetagResults.self, row["results"])
            let plan = row["plan"].isNull ? nil : Self.decoded(RetagPlan.self, row["plan"])
            diffs.text("\(at): applied", RetagWords.applied(results), row["applied"])
            diffs.text("\(at): write failed", RetagWords.writeFailed(results.failed), row["writeFailed"])
            diffs.check("\(at): new problems", RetagWords.newProblems(results, over: plan), row["newProblems"].list.compactMap(\.string))
        }
        for row in plans["discs"].list {
            diffs.text("discs", RetagWords.discWords(row["discs"].list.compactMap(\.int)), row["words"])
        }
        let none = plans["noPlan"]
        diffs.text("no plan: applying", RetagWords.applying(nil), none["applying"])
        diffs.text("no plan: cover box", RetagWords.coverToggle(existing: nil), none["coverToggle"])
        diffs.text("no plan: cover line", RetagWords.coverHint(existing: nil, size: nil), none["coverHint"])
        diffs.text("no plan: edition", RetagWords.editionPlaceholder(nil), none["editionPlaceholder"])
        for row in plans["covers"].list {
            let art = row["art"].string!
            diffs.text("cover only \(art)", RetagWords.coverOnly(hasArt: !art.isEmpty), row["label"])
            diffs.text("cover only line \(art)", RetagWords.coverOnlyHint(hasArt: !art.isEmpty), row["hint"])
        }
        for row in plans["saved"].list {
            diffs.text("saved", RetagWords.coverSaved(CoverFetched(written: row["written"].string, replaced: row["replaced"].string)),
                       row["said"])
        }
        for row in plans["originals"].list {
            diffs.text("original \(row["year"])", RetagWords.originalPlaceholder(row["year"].string!), row["placeholder"])
        }
        for row in plans["incoming"].list {
            let album = ScanAlbum(path: "A/B", releaseMbid: row["release"].string!)
            diffs.text("incoming", Retag.coverRelease(selected: row["selectedId"].string, album: album), row["incoming"])
        }
        diffs.done()
    }
}
