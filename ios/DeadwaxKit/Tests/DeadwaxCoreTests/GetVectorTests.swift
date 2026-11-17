import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/get/get-vectors.json: what the web's TypeScript (lib/releasePayload.ts, release.ts, pressings.ts getGroup,
/// candidates.ts, getSettings.ts, perPerson.ts, whose.ts withStoreLine, format.ts formatSize) answers for Phase 6's
/// slices 2 and 3, with the words Sources.tsx, SourceCard.tsx, ReleaseGroupPage.tsx, StoreState.tsx, GettingChoices.tsx,
/// You.tsx and useGetSettings.ts build inline read out of their source -
/// written by ios/scripts/export-get-vectors.cjs, never by hand. The MusicBrainz objects, store answers and folders in it
/// are decoded by the real models, as deadwax sends them.
enum GetVectors {
    struct Vectors: Decodable {
        let numbers: Numbers
        let words: Words
        let found: [Found]
        let groups: [GroupCase]
        let made: [Made]
        let editions: [Edition]
        let videos: [Video]
        let stores: [StoreCase]
        let whose: [WhoseCase]
        let cards: [Card]
        let lists: [ListCase]
        let chips: Chips
        let settings: [SettingsCase]
        let searching: [Searching]
        let overrides: [Override]
        let picks: [PickCase]
        let added: [AddedCase]
    }

    struct Numbers: Decodable {
        struct Band: Decodable { let percent: Double; let band: String }
        let speedBarFull: Double
        let bands: [Band]
        let autoGrabMinScore: Double
        let pickSort: String
    }

    struct Words: Decodable {
        struct Sheet: Decodable {
            let title, cancel, searchTakes, searchFor, search, tryAgain, clearFilters, searchAgain, sortLabel, chipsLabel: String
        }
        struct Card: Decodable {
            let get, getLabel, match, from, discs, speed, noSize, reasons, inItsName: String
            let facts: [String]
        }
        struct Page: Decodable { let get, getOff: String }
        struct Placed: Decodable { let place, said: String }
        struct Store: Decodable {
            let heldTitle, inTheStore, addNote: String
            let joinNotes, sharedNotes: [Placed]
        }
        struct Sort: Decodable { let sort, label: String }
        struct Floor: Decodable { let floor, label: String }
        struct Signal: Decodable { let signal, label, meaning: String }
        struct Count: Decodable { let count: Int; let said, none: String }
        struct Join: Decodable { let join, joining, joined, add, adding, added, addedShown: String }
        struct Choice: Decodable { let value, label: String }
        struct Getting: Decodable {
            let section, note, unsaved, unsavedTold, readFailed, notSaved: String
            let titles: [String]
            let modes, formats: [Choice]
        }
        let sheet: Sheet
        let card: Card
        let page: Page
        let store: Store
        let nothingLosslessNote: String
        let sorts: [Sort]
        let floors: [Floor]
        let signals: [Signal]
        let losslessFormats: [String]
        let sourcesCount: [Count]
        let join: Join
        let getting: Getting
    }

    struct Built: Decodable { let payload: JSONValue; let label: String }

    struct Found: Decodable {
        let name: String
        let group: ReleaseGroup
        let release: PageRelease
        let payload: JSONValue
        let label: String
        let whole: Built
    }

    /// A set of pressings (`releases`, by `name`), or a getGroup over one of them.
    struct GroupCase: Decodable {
        struct Out: Decodable {
            let id, title: String
            let firstReleaseDate: String
            let credit: [MBArtistCredit]?

            enum CodingKeys: String, CodingKey {
                case id, title, credit
                case firstReleaseDate = "first-release-date"
            }
        }
        let name: String
        let releases: [PageRelease]?
        let id: String?
        let preview: ReleaseGroup?
        let chosen: Int?
        let group: Out?
        let payload: JSONValue?
        let label: String?
    }

    struct Made: Decodable {
        let group: ReleaseGroup
        let release: PageRelease?
        let payload: JSONValue
        let label: String
    }

    struct Edition: Decodable {
        struct Release: Decodable { let title, disambiguation, packaging: String? }
        let release: Release
        let tags: [String]
    }

    struct Video: Decodable {
        struct Medium: Decodable { let format: String? }
        let medium: Medium
        let recording: MBTrack.Recording
        let video: Bool
    }

    struct Status: Decodable, Equatable {
        let kind, title: String
        let lines: [String]
        let joinJobId: Int?
        let add: Bool

        init(kind: String, title: String, lines: [String], joinJobId: Int?, add: Bool) {
            self.kind = kind
            self.title = title
            self.lines = lines
            self.joinJobId = joinJobId
            self.add = add
        }

        init(_ status: StoreStatus) {
            self.init(kind: status.kind.rawValue, title: status.title, lines: status.lines, joinJobId: status.joinJobId,
                      add: status.add)
        }

        var storeStatus: StoreStatus {
            StoreStatus(kind: StoreStatus.Kind(rawValue: kind)!, title: title, lines: lines, joinJobId: joinJobId, add: add)
        }
    }

    struct StoreCase: Decodable {
        struct ForFloor: Decodable { let floor: String?; let status: Status?; let withoutJoin: Status? }
        struct Verdict: Decodable { let floor: String; let verdict: String?; let note: String? }
        struct Download: Decodable { let beingFiled: Bool; let progress, copy: String; let verdicts: [Verdict] }
        let answer: StoreStateAnswer
        let cancelIn: String
        let status: Status?
        let heldTrackText: String?
        let notes: [String]
        let `for`: [ForFloor]
        let downloading: Download?
        let part: Download?
    }

    struct WhoseCase: Decodable {
        let holding: [OwnedAlbum]
        let said: StoreStateAnswer?
        let yours: [Bool?]
    }

    struct Card: Decodable {
        struct Speed: Decodable { let kind, text, note: String; let percent: Double }
        struct Starts: Decodable { let text: String; let waits: Bool }
        struct Chip: Decodable { let signal, label: String; let value: Double; let band, meaning: String }
        struct Tag: Decodable { let tag, tone: String }
        struct Copy: Decodable, Equatable {
            let formats: [String]
            let bitrates, bitDepths, sampleRates: [Double]
            let variableBitrate: Bool

            enum CodingKeys: String, CodingKey {
                case formats, bitrates
                case bitDepths = "bit_depths"
                case sampleRates = "sample_rates"
                case variableBitrate = "variable_bitrate"
            }
        }
        struct Facts: Decodable {
            let key: String
            let percent: Double
            let band: String
            let speed: Speed
            let starts: Starts
            let quality, tracks, size: String
            let signals: [Chip]
            let tags: [Tag]
            let missing: String?
            let everyTrack: Bool
            let rank: [Double]
            let copy: Copy
        }
        let candidate: Candidate
        let facts: Facts
    }

    struct Filters: Decodable {
        let lossless, bit24, freeSlot, kbps320, complete: Bool
        var source: SourceFilters {
            SourceFilters(lossless: lossless, bit24: bit24, freeSlot: freeSlot, kbps320: kbps320, complete: complete)
        }
    }

    struct ListCase: Decodable {
        struct Sorted: Decodable { let sort: String; let keys: [String] }
        let answer: FindCandidatesAnswer
        let filters: Filters
        let format: String?
        let passing: [String]
        let sorted: [Sorted]
        let best: String?
        let queries: String
        let nothingLossless: Bool
        let nothingLosslessLine, nothingFound, noneMatch, searched: String
        let status: Status?
        let notPicked: String?
        let announcement: String
    }

    struct Chips: Decodable {
        struct FloorCase: Decodable { let floor: String; let filters: Filters }
        struct Chip: Decodable { let key, label: String; let on: Bool }
        struct Quality: Decodable { let minBitrate, minBitDepth, minSampleRate, minSizeMb, maxSizeMb: Double }
        struct ChipCase: Decodable {
            let floor: String
            let filters: Filters
            let chips: [Chip]
            let pressed: Int
            let quality: Quality
        }
        let floors: [FloorCase]
        let chips: [ChipCase]
    }

    struct SettingsCase: Decodable {
        let answer: GetSettingsAnswer
        let mode, floor, format: String
        let canSave: Bool
    }

    /// (Slice 3) An answer, the release it was for and the chips: what a pick would ask for, and why not.
    struct PickCase: Decodable {
        struct Release: Decodable {
            let releaseMbid: String?
            let tracks: [JSONValue]?
            enum CodingKeys: String, CodingKey {
                case tracks
                case releaseMbid = "release_mbid"
            }
        }
        struct Grab: Decodable { let pick: String; let list: [String] }
        let answer: FindCandidatesAnswer?
        let release: Release?
        let filters: Filters
        let sort: String
        let blocked: String?
        let grab: Grab?
        let notPicked: String?
    }

    /// (Slice 3) A store answer's status at each floor, and the box once Add has added it.
    struct AddedCase: Decodable {
        struct ForFloor: Decodable { let floor: String?; let status: Status?; let added: Status? }
        let answer: StoreStateAnswer
        let `for`: [ForFloor]
    }

    struct Searching: Decodable {
        struct Release: Decodable {
            let artist, albumArtist, album: String
            enum CodingKeys: String, CodingKey {
                case artist, album
                case albumArtist = "album_artist"
            }
        }
        let release: Release
        let said: String
    }

    struct Override: Decodable { let typed, shown, override: String }

    static let vectors: Vectors = {
        do {
            return try JSONDecoder().decode(Vectors.self, from: Fixtures.data("get/get-vectors.json"))
        } catch {
            fatalError("get-vectors.json: \(error)")
        }
    }()

    /// What a body is as JSON, to compare with what the web sent.
    static func json(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}

@Suite struct GetVectorTests {
    let v = GetVectors.vectors

    @Test func theNumbersAreTheWebs() {
        #expect(Sources.speedBarFull == v.numbers.speedBarFull)
        for band in v.numbers.bands {
            #expect(Sources.band(band.percent).rawValue == band.band, "\(band.percent)")
        }
        #expect(Sources.autoGrabMinScore == v.numbers.autoGrabMinScore)
        #expect(Sources.pickSort.rawValue == v.numbers.pickSort)
    }

    @Test func theWordsAreTheWebs() {
        let words = v.words
        #expect(SourcesWords.title == words.sheet.title)
        #expect(SourcesWords.cancel == words.sheet.cancel)
        #expect(Sources.searchTakes == words.sheet.searchTakes)
        #expect(SourcesWords.searchFor == words.sheet.searchFor)
        #expect(SourcesWords.search == words.sheet.search)
        #expect(SourcesWords.tryAgain == words.sheet.tryAgain)
        #expect(SourcesWords.clearFilters == words.sheet.clearFilters)
        #expect(SourcesWords.searchAgain == words.sheet.searchAgain)
        #expect(SourcesWords.sortLabel == words.sheet.sortLabel)
        #expect(SourcesWords.chipsLabel == words.sheet.chipsLabel)

        let candidate = Candidate(username: "bob", directoryName: "Third [FLAC]", score: 0.92, discFolders: ["CD 1", "CD 2"])
        #expect(SourcesWords.get == words.card.get)
        // the card's inline templates, as the exporter read them from SourceCard.tsx
        #expect(words.card.getLabel == "aria-label={`Get ${candidate.directory_name} from ${candidate.username}`}")
        #expect(SourcesWords.getLabel(candidate) == "Get Third [FLAC] from bob")
        #expect(words.card.match == "aria-label={`${percent}% match`}")
        #expect(SourcesWords.match(92) == "92% match")
        #expect(words.card.from == "from {candidate.username}")
        #expect(words.card.discs == "{discs > 1 ? ` \u{00B7} in ${discs} parts, one per disc` : ''}")
        #expect(SourcesWords.from(candidate) == "from bob \u{00B7} in 2 parts, one per disc")
        #expect(SourcesWords.from(Candidate(username: "bob", score: 1, discFolders: ["CD 1"])) == "from bob")
        #expect(SourcesWords.speed == words.card.speed)
        #expect([SourcesWords.tracks, SourcesWords.quality, SourcesWords.size, SourcesWords.starts] == words.card.facts)
        #expect(SourcesWords.noSize == words.card.noSize)
        #expect(words.card.reasons == "Why it's a {percent}% match")
        #expect(SourcesWords.reasons(92) == "Why it's a 92% match")
        #expect(SourcesWords.inItsName == words.card.inItsName)

        #expect(SourcesWords.getTheAlbum == words.page.get)
        #expect(RequestWords.getOff == words.page.getOff)

        #expect(StoreLine.heldTitle == words.store.heldTitle)
        #expect(StoreLine.inTheStore == words.store.inTheStore)
        #expect(StoreLine.addNote == words.store.addNote)
        for note in words.store.joinNotes {
            #expect(StoreLine.joinNote(CancelPlace(rawValue: note.place)!) == note.said)
        }
        for note in words.store.sharedNotes {
            #expect(StoreLine.sharedNote(CancelPlace(rawValue: note.place)!) == note.said)
        }
        // the web's word for word - the tab named Settings on both since the web's 2.1.35
        #expect(Sources.nothingLosslessNote == words.nothingLosslessNote)
        #expect(CandidateSort.allCases.map(\.rawValue) == words.sorts.map(\.sort))
        #expect(CandidateSort.allCases.map(\.label) == words.sorts.map(\.label))
        #expect(QualityFloor.allCases.map(\.rawValue) == words.floors.map(\.floor))
        #expect(QualityFloor.allCases.map(\.label) == words.floors.map(\.label))
        #expect(Sources.signals.map(\.signal) == words.signals.map(\.signal))
        #expect(Sources.signals.map(\.label) == words.signals.map(\.label))
        #expect(Sources.signals.map(\.meaning) == words.signals.map(\.meaning))
        #expect(Sources.losslessFormats == Set(words.losslessFormats))
        for count in words.sourcesCount {
            #expect(Sources.sourcesCount(count.count) == count.said)
            #expect(Sources.noneMatchLine(count.count) == count.none)
        }
    }

    @Test func joinAddAndGettingAlbumsSayWhatTheWebSays() {
        let join = v.words.join
        #expect(StoreWords.join == join.join && StoreWords.joining == join.joining && StoreWords.joined == join.joined)
        #expect(StoreWords.add == join.add && StoreWords.adding == join.adding && StoreWords.added == join.added)
        #expect(join.addedShown == "{ADDED_WORDS}")
        // the album page's own Add says the same as the line's
        #expect(Whose.button(.add, busy: false) == join.add && Whose.button(.add, busy: true) == join.adding)

        let getting = v.words.getting
        #expect(RequestWords.gettingAlbums == getting.section)
        #expect([GettingWords.modeTitle, GettingWords.floorTitle, GettingWords.formatTitle] == getting.titles)
        #expect(GetMode.allCases.map(\.rawValue) == getting.modes.map(\.value))
        #expect(GetMode.allCases.map(\.label) == getting.modes.map(\.label))
        #expect(FormatPreference.youOrder.map(\.rawValue) == getting.formats.map(\.value))
        #expect(FormatPreference.youOrder.map(\.label) == getting.formats.map(\.label))
        #expect(Set(FormatPreference.youOrder) == Set(FormatPreference.allCases))
        #expect(GettingWords.note == getting.note)
        #expect(GettingWords.unsaved == getting.unsaved)
        #expect(getting.unsavedTold == "{GETTING_UNSAVED}{runsDeadwax ? '' : ` ${TELL}`}")
        #expect(GettingWords.unsavedLine(runsDeadwax: true) == getting.unsaved)
        #expect(GettingWords.unsavedLine(runsDeadwax: false) == "\(getting.unsaved) \(ErrorWords.tell)")
        #expect(GettingWords.readFailed == getting.readFailed && GettingWords.notSaved == getting.notSaved)
    }

    @Test func aGetSendsWhatTheMainPagesFindButtonsSent() throws {
        #expect(v.found.count == 8)
        for found in v.found {
            let release = GetRelease.build(group: found.group, release: found.release)
            #expect(try GetVectors.json(release) == found.payload, "\(found.name)")
            #expect(release.label == found.label, "\(found.name)")
            let whole = GetRelease.build(group: found.group, release: nil)
            #expect(try GetVectors.json(whole) == found.whole.payload, "\(found.name), the album as a whole")
            #expect(whole.label == found.whole.label, "\(found.name)")
        }
    }

    @Test func theGroupAGetBuildsFromIsGetGroups() throws {
        var sets: [String: [PageRelease]] = [:]
        for set in v.groups { if let releases = set.releases { sets[set.name] = releases } }
        #expect(sets.count == 8)
        var cases = 0
        for one in v.groups where one.releases == nil {
            let releases = try #require(sets[one.name], "\(one.name)")
            let chosen = one.chosen.map { releases[$0] }
            let group = GetRelease.group(id: one.id ?? "", preview: one.preview, releases: releases, chosen: chosen)
            let out = try #require(one.group)
            let named = "\(one.name), chosen \(one.chosen.map(String.init) ?? "none"), preview \(one.preview == nil ? "none" : "given")"
            #expect(group.id == out.id, "\(named)")
            #expect(group.title == out.title, "\(named)")
            #expect(group.firstReleaseDate == out.firstReleaseDate, "\(named)")
            #expect(group.artistCredit == out.credit, "\(named)")
            if let chosen, let payload = one.payload {
                let release = GetRelease.build(group: group, release: chosen)
                #expect(try GetVectors.json(release) == payload, "\(named)")
                #expect(release.label == one.label, "\(named)")
            }
            cases += 1
        }
        #expect(cases > 60)
    }

    @Test func madeGroupsAndPressingsSendWhatTheWebsBuilderSends() throws {
        #expect(v.made.count == 120)
        for (at, made) in v.made.enumerated() {
            let release = GetRelease.build(group: made.group, release: made.release)
            #expect(try GetVectors.json(release) == made.payload, "made \(at)")
            #expect(release.label == made.label, "made \(at)")
        }
    }

    @Test func editionWordsAreDetectEditionTags() {
        for edition in v.editions {
            let tags = EditionTags.detect(title: edition.release.title, disambiguation: edition.release.disambiguation,
                                          packaging: edition.release.packaging)
            #expect(tags == edition.tags, "\(String(describing: edition.release.title)) / \(String(describing: edition.release.disambiguation))")
        }
    }

    @Test func videoIsIsVideoTrack() {
        #expect(v.videos.count == 65)
        for video in v.videos {
            #expect(GetRelease.isVideo(format: video.medium.format, recording: video.recording) == video.video,
                    "\(String(describing: video.medium.format)) \(String(describing: video.recording.video))")
        }
    }

    @Test func theStoreLineIsTheWebs() {
        #expect(v.stores.count == 200)
        for (at, store) in v.stores.enumerated() {
            let place = CancelPlace(rawValue: store.cancelIn)!
            #expect(StoreLine.status(store.answer, cancelIn: place).map(GetVectors.Status.init) == store.status, "store \(at)")
            #expect(store.answer.held.map(StoreLine.heldTrackText) == store.heldTrackText, "store \(at)")
            #expect(StoreLine.notes(store.answer) == store.notes, "store \(at)")
            for each in store.for {
                let floor = each.floor.map { QualityFloor(rawValue: $0)! }
                let status = StoreLine.statusFor(store.answer, cancelIn: place, floor: floor)
                #expect(status.map(GetVectors.Status.init) == each.status, "store \(at), floor \(String(describing: each.floor))")
                #expect(status.map(StoreLine.withoutJoin).map(GetVectors.Status.init) == each.withoutJoin,
                        "store \(at), floor \(String(describing: each.floor)), without Join")
            }
            for (download, said) in [(store.answer.downloading, store.downloading), (store.answer.downloadingPart, store.part)] {
                #expect((download == nil) == (said == nil), "store \(at)")
                guard let download, let said else { continue }
                #expect(StoreLine.beingFiled(download) == said.beingFiled, "store \(at)")
                #expect(StoreLine.progressText(download) == said.progress, "store \(at)")
                #expect(StoreLine.copyText(download) == said.copy, "store \(at)")
                for verdict in said.verdicts {
                    let floor = QualityFloor(rawValue: verdict.floor)!
                    #expect(StoreLine.floorVerdict(download, floor)?.rawValue == verdict.verdict, "store \(at), \(verdict.floor)")
                    #expect(StoreLine.floorNote(download, floor) == verdict.note, "store \(at), \(verdict.floor)")
                }
            }
        }
    }

    @Test func theMetaLineTakesTheStoreLinesWord() {
        #expect(v.whose.count == 80)
        for (at, whose) in v.whose.enumerated() {
            #expect(Whose.withStoreLine(whose.holding, whose.said).map(\.yours) == whose.yours, "whose \(at)")
        }
    }

    @Test func aCardSaysWhatTheWebsSays() {
        #expect(v.cards.count == 200)
        for (at, card) in v.cards.enumerated() {
            let candidate = card.candidate, facts = card.facts
            #expect(Sources.key(candidate) == facts.key, "card \(at)")
            #expect(Sources.percent(candidate) == facts.percent, "card \(at)")
            #expect(Sources.band(Sources.percent(candidate)).rawValue == facts.band, "card \(at)")
            let speed = Sources.speedFact(candidate)
            #expect(speed.kind.rawValue == facts.speed.kind && speed.text == facts.speed.text, "card \(at): \(speed.text)")
            #expect(speed.note == facts.speed.note && speed.percent == facts.speed.percent, "card \(at)")
            let starts = Sources.startsFact(candidate)
            #expect(starts.text == facts.starts.text && starts.waits == facts.starts.waits, "card \(at)")
            #expect(Sources.qualityText(candidate) == facts.quality, "card \(at)")
            #expect(Sources.tracksText(candidate) == facts.tracks, "card \(at)")
            #expect(Sources.size(candidate.totalSize) == facts.size, "card \(at)")
            let chips = Sources.signalChips(candidate)
            #expect(chips.map(\.signal) == facts.signals.map(\.signal), "card \(at)")
            #expect(chips.map(\.label) == facts.signals.map(\.label), "card \(at)")
            #expect(chips.map(\.value) == facts.signals.map(\.value), "card \(at)")
            #expect(chips.map(\.band.rawValue) == facts.signals.map(\.band), "card \(at)")
            #expect(chips.map(\.meaning) == facts.signals.map(\.meaning), "card \(at)")
            let tags = Sources.editionTags(candidate)
            #expect(tags.map(\.tag) == facts.tags.map(\.tag) && tags.map(\.tone.rawValue) == facts.tags.map(\.tone), "card \(at)")
            #expect(Sources.missingLine(candidate) == facts.missing, "card \(at)")
            #expect(Sources.everyTrackPresent(candidate) == facts.everyTrack, "card \(at)")
            #expect(Sources.qualityRank(candidate) == facts.rank, "card \(at)")
            let copy = Sources.quality(candidate)
            #expect(GetVectors.Card.Copy(formats: copy.formats, bitrates: copy.bitrates, bitDepths: copy.bitDepths,
                                         sampleRates: copy.sampleRates, variableBitrate: copy.variableBitrate) == facts.copy,
                    "card \(at)")
        }
    }

    @Test func theListPassesSortsAndSaysWhatTheWebsDoes() {
        #expect(v.lists.count == 120)
        for (at, list) in v.lists.enumerated() {
            let answer = list.answer
            let chosen = GetSettings.candidateFilters(list.filters.source)
            let passing = answer.candidates.filter { Sources.passes($0, chosen) }
            #expect(passing.map(Sources.key) == list.passing, "list \(at)")
            for sorted in list.sorted {
                let sort = CandidateSort(rawValue: sorted.sort)!
                #expect(Sources.sorted(passing, sort).map(Sources.key) == sorted.keys, "list \(at), \(sorted.sort)")
            }
            #expect(Sources.best(passing) == list.best, "list \(at)")
            let format = list.format.map { FormatPreference(rawValue: $0)! }
            #expect(Sources.queriesText(answer) == list.queries, "list \(at)")
            #expect(Sources.nothingLossless(answer, format) == list.nothingLossless, "list \(at)")
            #expect(Sources.nothingLosslessLine(answer) == list.nothingLosslessLine, "list \(at)")
            #expect(Sources.nothingFoundLine(answer) == list.nothingFound, "list \(at)")
            #expect(Sources.noneMatchLine(answer.candidates.count) == list.noneMatch, "list \(at)")
            #expect(Sources.searchedLine(answer, shown: passing.count) == list.searched, "list \(at)")
            let said = Sources.announcement(pending: false, release: nil, error: nil, status: list.status?.storeStatus,
                                            answer: answer, shown: passing.count, notPicked: list.notPicked, format: format)
            #expect(said == list.announcement, "list \(at)")
        }
    }

    @Test func theChipsAreTheWebs() {
        for floor in v.chips.floors {
            let filters = GetSettings.floorFilters(QualityFloor(rawValue: floor.floor)!)
            #expect(filters == floor.filters.source, "\(floor.floor)")
        }
        #expect(v.chips.chips.count == 4 * 32)
        for each in v.chips.chips {
            let floor = QualityFloor(rawValue: each.floor)!
            let chips = GetSettings.chips(floor, each.filters.source)
            #expect(chips.map(\.key.rawValue) == each.chips.map(\.key), "\(each.floor)")
            #expect(chips.map(\.label) == each.chips.map(\.label), "\(each.floor)")
            #expect(chips.map(\.on) == each.chips.map(\.on), "\(each.floor)")
            #expect(GetSettings.pressedCount(each.filters.source) == each.pressed)
            let quality = GetSettings.candidateFilters(each.filters.source).quality
            #expect(quality.minBitrate == each.quality.minBitrate && quality.minBitDepth == each.quality.minBitDepth)
            #expect(quality.minSampleRate == each.quality.minSampleRate && quality.minSizeMb == each.quality.minSizeMb
                    && quality.maxSizeMb == each.quality.maxSizeMb)
        }
    }

    @Test func theSettingsAreReadAsTheWebReadsThem() {
        #expect(v.settings.count == 13)
        for each in v.settings {
            #expect(each.answer.settings.mode.rawValue == each.mode)
            #expect(each.answer.settings.floor.rawValue == each.floor)
            #expect(each.answer.settings.format.rawValue == each.format)
            #expect(each.answer.canSave == each.canSave)
        }
    }

    @Test func aPickIsTheWebsAndSoIsWhyNot() {
        #expect(v.picks.count == 161)
        for (at, each) in v.picks.enumerated() {
            let release = each.release.map { (releaseMbid: $0.releaseMbid, trackCount: $0.tracks?.count ?? 0) }
            let blocked = Sources.autoPickBlocked(each.answer?.store, release: release)
            #expect(blocked == each.blocked, "pick \(at)")
            let filters = GetSettings.candidateFilters(each.filters.source)
            let grab = Sources.autoGrabPick(each.answer?.candidates ?? [], filters, CandidateSort(rawValue: each.sort)!)
            #expect(grab.map { Sources.key($0.pick) } == each.grab?.pick, "pick \(at)")
            #expect(grab.map { $0.list.map(Sources.key) } == each.grab?.list, "pick \(at)")
            #expect(Sources.notPickedLine(blocked, found: each.answer?.candidates.count ?? 0) == each.notPicked, "pick \(at)")
        }
    }

    @Test func theBoxOnceAddedIsTheWebs() {
        #expect(v.added.count == 120)
        for (at, each) in v.added.enumerated() {
            for floor in each.for {
                let status = StoreLine.statusFor(each.answer, cancelIn: .requests,
                                                 floor: floor.floor.map { QualityFloor(rawValue: $0)! })
                #expect(status.map(GetVectors.Status.init) == floor.status, "added \(at)")
                #expect(status.map(StoreLine.addedStatus).map(GetVectors.Status.init) == floor.added, "added \(at)")
            }
        }
    }

    @Test func theSearchingLineIsTheWebs() {
        for each in v.searching {
            #expect(Sources.searchingLine(artist: each.release.artist, albumArtist: each.release.albumArtist,
                                          album: each.release.album) == each.said)
        }
    }

    @Test func onlyAnEditedQueryOverrides() {
        #expect(v.overrides.count == 24)
        for each in v.overrides {
            #expect(Sources.queryOverride(each.typed, each.shown) == each.override, "\(each.typed) / \(each.shown)")
        }
    }
}
