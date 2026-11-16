import DeadwaxCore
import Observation
import SwiftUI

/// Which of the artist tools a sheet is (the web's ArtistManageMode): one opening each.
struct ArtistToolSheet: Identifiable, Equatable {
    enum Kind: Equatable {
        case images, who, move
    }

    let id = UUID()
    let kind: Kind
}

/// What Artist images is opened for (the web's ArtistManageRequest, its images half): the library's name whose folder
/// takes their pictures - or why none does - who the page says they are, and their name as the page has it.
struct ArtistImagesRequest: Equatable {
    let folder: String?
    let reason: String?
    let mbid: String?
    let name: String
}

/// Artist images' asking (Phase 8, slice 5; the web's ImagesBody): the look for pictures, the search, Save - every rule
/// Core's ArtistImagesFlow's, this asks and keeps. The look and the search are asked from the sheet; Save is held with
/// a background task while iOS allows, and one whose answer never came (or came as a 5xx) is said as maybe finished and
/// the folder looked at again - never Save offered again on the old look. What comes after a save (the page's pictures
/// asked again) is never done past a sign-out (`session`, AppNavigation's when the sheet opened).
@MainActor
@Observable
final class ArtistImagesModel {
    private(set) var flow: ArtistImagesFlow
    /// The search's words (the web's `query`): the page's name to begin with.
    var query: String
    /// Why no folder takes their pictures - said in place of everything, nothing asked.
    let reason: String?

    @ObservationIgnored let client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    /// The page's: its pictures asked again once a save wrote, or may have.
    @ObservationIgnored var onSaved: (() -> Void)?
    @ObservationIgnored private weak var navigation: AppNavigation?
    @ObservationIgnored private var session: Int?
    @ObservationIgnored private var opened = false

    init(request: ArtistImagesRequest, client: DeadwaxClient?, admin: Bool, online: Bool) {
        flow = ArtistImagesFlow(folder: request.reason == nil ? request.folder : nil, mbid: request.mbid,
                                name: request.name, online: online)
        query = request.name
        reason = request.reason
        self.client = client
        self.admin = admin
    }

    func attach(_ navigation: AppNavigation) {
        self.navigation = navigation
        session = navigation.session
    }

    private var samePerson: Bool {
        guard let navigation, let session else { return false }
        return navigation.session == session
    }

    /// Replace pictures that are already there - off while a save runs (it sends what was on).
    var replace: Bool {
        get { flow.replace }
        set {
            guard !flow.saving else { return }
            flow.replace = newValue
        }
    }

    /// The sheet's task: the look, once (opened out of reach: once it is back).
    func open() async {
        guard !opened, reason == nil, flow.online else { return }
        opened = true
        await look(mbid: flow.lastAsked.mbid, name: flow.lastAsked.name)
    }

    /// A look for `mbid`'s pictures (opening, Look again, a match picked) - only the newest lands.
    func look(mbid: String?, name: String) async {
        guard reason == nil, let ticket = flow.look(mbid: mbid, name: name), let client,
              let folder = flow.folder else { return }
        do {
            let found = try await client.artistImagesPreview(ArtistImagesBody(artist: folder, artistMbid: mbid))
            flow.looked(ticket, found)
        } catch {
            // the sheet gone: neither a failure nor an answer
            guard !APIFailure.isCancellation(error) else { return }
            flow.lookFailed(ticket, words: EditWords.said(error, failed: ArtistManageWords.lookFailed, admin: admin))
        }
    }

    /// Look again: the artist last asked about.
    func lookAgain() async {
        await look(mbid: flow.lastAsked.mbid, name: flow.lastAsked.name)
    }

    func openSearch() { flow.openSearch() }

    /// The search (Not them?, or MusicBrainz couldn't say who this is) - only the newest lands.
    func search() async {
        let wanted = query
        guard let ticket = flow.beginSearch(wanted), let client else { return }
        do {
            let found = try await client.artistSearch(ArtistManage.searchWords(wanted))
            flow.searched(ticket, query: wanted, found.matches)
        } catch {
            guard !APIFailure.isCancellation(error) else { return }
            flow.searchFailed(ticket, query: wanted,
                              words: EditWords.said(error, failed: ArtistManageWords.searchFailed, admin: admin))
        }
    }

    func toggle(kind: String, url: String) { flow.toggle(kind: kind, url: url) }

    /// Save: what is drawn sent - the server checks each choice is a picture its sources offer - and what it wrote said.
    func save() async {
        guard let begun = flow.beginSave(), let client else { return }
        let (ticket, body) = begun
        let hold = BackgroundHold(named: "Artist images: Save")
        defer { hold.end() }
        let commons = ArtistWaits.commons(flow.preview?.candidates ?? [])
        do {
            let applied = try await client.artistImagesApply(body, commons: commons)
            flow.saveAnswered(ticket, applied)
            AccessibilityNotification.Announcement(flow.saved ?? "").post()
            guard samePerson else { return }
            onSaved?()
        } catch {
            // a cancellation of a write is no refusal: it may have written
            let outcome = APIFailure.isCancellation(error) ? RetagFlow.Outcome.unanswered : RetagFlow.outcome(of: error)
            let words = EditWords.writeFailure(error, failed: ArtistManageWords.saveFailed, admin: admin)
            let again = flow.saveFailed(ticket, outcome: outcome, words: words)
            guard again else {
                AccessibilityNotification.Announcement(flow.saved ?? ArtistManageWords.saveFailed).post()
                return
            }
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
            guard samePerson else { return }
            onSaved?()
            await lookAgain()
        }
    }

    /// Out of reach and back (phase8-managing.md 2): what is drawn stays and Save is off; back, the look asked again
    /// (and a search that failed) before Save comes back.
    func reach(_ now: Bool) async {
        guard now != flow.online else { return }
        guard now else {
            flow.wentAway()
            return
        }
        let back = flow.cameBack()
        // opened out of reach: this is its first look
        opened = true
        if let asked = back.look { await look(mbid: asked.mbid, name: asked.name) }
        if back.search != nil { await search() }
    }

    /// The app back in front with the folder still to be looked at (a save that ended while the phone was locked).
    func becameActive() async {
        guard flow.online, flow.needsRead, flow.loading == nil else { return }
        await lookAgain()
    }
}

/// Move albums' asking (Phase 8, slice 5; the web's RefileBody): each name's preview asked together, Move applying each
/// name in turn - every rule Core's ArtistRefileFlow's. Move is held with a background task while iOS allows; one whose
/// answer never came (or came as a 5xx) is said as maybe finished and the previews asked again. The page beneath is
/// asked again after a move (`onMoved`) - never past a sign-out.
@MainActor
@Observable
final class ArtistMoveModel {
    private(set) var flow: ArtistRefileFlow

    @ObservationIgnored let client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    /// Each name's albums' size (its summary's total), for how long its apply is given.
    @ObservationIgnored var sizes: [String: Double]
    @ObservationIgnored var onMoved: (() -> Void)?
    @ObservationIgnored private weak var navigation: AppNavigation?
    @ObservationIgnored private var session: Int?
    @ObservationIgnored private var opened = false

    init(ask: ArtistRefileFlow.Ask, sizes: [String: Double], client: DeadwaxClient?, admin: Bool, online: Bool) {
        flow = ArtistRefileFlow(ask, online: online)
        self.sizes = sizes
        self.client = client
        self.admin = admin
    }

    func attach(_ navigation: AppNavigation) {
        self.navigation = navigation
        session = navigation.session
    }

    private var samePerson: Bool {
        guard let navigation, let session else { return false }
        return navigation.session == session
    }

    func open() async {
        guard !opened, flow.online else { return }
        opened = true
        await preview()
    }

    /// Every name's preview, asked together (the web's Promise.all) - only the newest round lands.
    func preview() async {
        guard let begun = flow.preview(), let client else { return }
        let (ticket, ask) = begun
        do {
            let plans = try await withThrowingTaskGroup(of: (Int, ArtistManage.NamedPlan).self) { group in
                for (at, name) in ask.names.enumerated() {
                    group.addTask {
                        let plan = try await client.refilePreview(ArtistRefileBody(artist: name, artistMbid: ask.mbid))
                        return (at, ArtistManage.NamedPlan(name: name, plan: plan))
                    }
                }
                var found: [(Int, ArtistManage.NamedPlan)] = []
                for try await one in group { found.append(one) }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            flow.previewed(ticket, plans)
        } catch {
            guard !APIFailure.isCancellation(error) else { return }
            flow.previewFailed(ticket, words: EditWords.said(error, failed: ArtistManageWords.previewFailed,
                                                            admin: admin))
        }
    }

    /// The page's names, id or their name now changed: the previews asked again rather than applied blind.
    func changed(_ ask: ArtistRefileFlow.Ask) async {
        guard flow.changed(ask), opened else { return }
        await preview()
    }

    /// Move: each name with an album the preview shows moving, in turn - the same body its preview sent, the server
    /// working the plan out again - stopping at the first that fails.
    func move() async {
        guard let names = flow.beginMove(), let client else { return }
        let mbid = flow.ask.mbid
        let before = flow.wrote
        let hold = BackgroundHold(named: "Move albums")
        defer { hold.end() }
        var applied: [ArtistManage.AppliedName] = []
        var stopped: (outcome: RetagFlow.Outcome, words: String?)?
        for named in names {
            do {
                let answer = try await client.refileApply(ArtistRefileBody(artist: named.name, artistMbid: mbid),
                                                          bytes: sizes[named.name] ?? 0)
                applied.append(ArtistManage.AppliedName(name: named.name, plan: answer.plan, results: answer.results))
            } catch {
                let outcome = APIFailure.isCancellation(error) ? RetagFlow.Outcome.unanswered
                    : RetagFlow.outcome(of: error)
                stopped = (outcome, EditWords.writeFailure(error, failed: ArtistManageWords.moveFailed, admin: admin))
                break
            }
        }
        let again = flow.moveEnded(applied: applied, stopped: stopped)
        AccessibilityNotification.Announcement(again ? EditWords.mayHaveFinished : flow.outcome?.text ?? "").post()
        guard samePerson else { return }
        if flow.wrote > before { onMoved?() }
        if again { await preview() }
    }

    func reach(_ now: Bool) async {
        guard now != flow.online else { return }
        guard now else {
            flow.wentAway()
            return
        }
        let again = flow.cameBack()
        if !opened {
            opened = true
            await preview()
        } else if again {
            await preview()
        }
    }

    func becameActive() async {
        guard flow.online, flow.needsRead, !flow.loading, !flow.applying else { return }
        await preview()
    }
}

/// Which artist is this?'s search (the web's WhoBody): asked as it opens for the page's own name, only the newest
/// landing; a pick gives the page that id for this visit, and closes.
@MainActor
@Observable
final class ArtistWhoModel {
    private(set) var flow: ArtistWhoFlow
    var query: String

    @ObservationIgnored let client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    @ObservationIgnored private var opened = false

    init(name: String, client: DeadwaxClient?, admin: Bool, online: Bool) {
        flow = ArtistWhoFlow(online: online)
        query = name
        self.client = client
        self.admin = admin
    }

    func open() async {
        guard !opened, flow.online else { return }
        opened = true
        await search()
    }

    func search() async {
        let wanted = query
        guard let ticket = flow.begin(wanted), let client else { return }
        do {
            let found = try await client.artistSearch(ArtistManage.searchWords(wanted))
            flow.answered(ticket, query: wanted, found.matches)
        } catch {
            guard !APIFailure.isCancellation(error) else { return }
            flow.failed(ticket, query: wanted,
                        words: EditWords.said(error, failed: ArtistManageWords.searchFailed, admin: admin))
        }
    }

    func reach(_ now: Bool) async {
        guard now != flow.online else { return }
        guard now else {
            flow.wentAway()
            return
        }
        let failed = flow.cameBack()
        if !opened {
            opened = true
            await search()
        } else if let failed {
            query = failed
            await search()
        }
    }
}
