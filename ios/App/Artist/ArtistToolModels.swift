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
    /// The page's name for them: who "Showing …" names when MusicBrainz gave none (the web's `request.name`).
    let pageName: String

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
        pageName = request.name
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
            // as long as the Commons pictures the last look found need (a width asked of Commons for each)
            let commons = flow.preview.map { ArtistWaits.commons($0.candidates) }
            let found = try await client.artistImagesPreview(ArtistImagesBody(artist: folder, artistMbid: mbid),
                                                             commons: commons)
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
    /// The folder's pictures are drawn again everywhere once it wrote, or may have (ArtistFolderVersions); a look owed
    /// by a gap while it ran is asked once it is over.
    func save() async {
        guard let begun = flow.beginSave(), let client else { return }
        let (ticket, body) = begun
        let folder = flow.preview?.path ?? ""
        let hold = BackgroundHold(named: "Artist images: Save")
        defer { hold.end() }
        let commons = ArtistWaits.commons(flow.preview?.candidates ?? [])
        do {
            let applied = try await client.artistImagesApply(body, commons: commons)
            let owed = flow.saveAnswered(ticket, applied)
            ArtistFolderVersions.shared.wrote(client, path: folder)
            AccessibilityNotification.Announcement(flow.saved ?? "").post()
            guard samePerson else { return }
            onSaved?()
            // (slice 6) a write anywhere in managing: Needs a look's count asked again
            navigation?.managed()
            if owed { await lookAgain() }
        } catch {
            // a cancellation of a write is no refusal: it may have written
            let outcome = APIFailure.isCancellation(error) ? RetagFlow.Outcome.unanswered : RetagFlow.outcome(of: error)
            let words = EditWords.writeFailure(error, failed: ArtistManageWords.saveFailed, admin: admin)
            let maybe = outcome == .unanswered
            let again = flow.saveFailed(ticket, outcome: outcome, words: words)
            guard maybe else {
                AccessibilityNotification.Announcement(flow.saved ?? ArtistManageWords.saveFailed).post()
                guard again, samePerson else { return }
                await lookAgain()
                return
            }
            ArtistFolderVersions.shared.wrote(client, path: folder)
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
            guard samePerson else { return }
            onSaved?()
            navigation?.managed()
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
/// answer never came (or came as a 5xx) is said as maybe finished and the previews asked again, which work out what
/// became of it (a name deadwax no longer files anything under - its preview a 404 - counts as moved). Each name's wait
/// is worked out from its albums' size as Move starts: a size the page hadn't read is asked for then, and Move doesn't
/// start without it. The page beneath is asked again after a move (`onMoved`) - never past a sign-out, and no name is
/// applied once the person has changed.
@MainActor
@Observable
final class ArtistMoveModel {
    private(set) var flow: ArtistRefileFlow

    @ObservationIgnored let client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    /// Each name's albums' size (its summary's total), for how long its apply is given - the page's, kept current.
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

    /// Every name's preview, asked together (the web's Promise.all) - only the newest round lands. A name deadwax no
    /// longer files anything under answers a 404: nothing to move under it (`gone`).
    func preview() async {
        guard let begun = flow.preview(), let client else { return }
        let (ticket, ask) = begun
        do {
            let answers = try await withThrowingTaskGroup(of: (Int, ArtistRefilePlan?).self) { group in
                for (at, name) in ask.names.enumerated() {
                    group.addTask {
                        do {
                            return (at, try await client.refilePreview(ArtistRefileBody(artist: name,
                                                                                        artistMbid: ask.mbid)))
                        } catch let failure as APIFailure where failure.status == 404 {
                            return (at, nil)
                        }
                    }
                }
                var found: [(Int, ArtistRefilePlan?)] = []
                for try await one in group { found.append(one) }
                return found.sorted { $0.0 < $1.0 }
            }
            var plans: [ArtistManage.NamedPlan] = []
            var gone: [String] = []
            for (at, plan) in answers {
                if let plan {
                    plans.append(ArtistManage.NamedPlan(name: ask.names[at], plan: plan))
                } else {
                    gone.append(ask.names[at])
                }
            }
            flow.previewed(ticket, plans, gone: gone)
        } catch {
            guard !APIFailure.isCancellation(error) else { return }
            flow.previewFailed(ticket, words: EditWords.said(error, failed: ArtistManageWords.previewFailed,
                                                            admin: admin))
        }
    }

    /// The page's names, id or their name now changed: the previews asked again rather than applied blind (and, with
    /// no name left, a check under way settled by that alone).
    func changed(_ ask: ArtistRefileFlow.Ask) async {
        guard flow.changed(ask), opened else { return }
        await preview()
    }

    /// Move: each name with an album the preview shows moving, in turn - the same body its preview sent, the server
    /// working the plan out again - stopping at the first that fails, or once the person has changed.
    func move() async {
        guard let names = flow.beginMove(), let client else { return }
        let mbid = flow.ask.mbid
        let toFolder = flow.view?.toFolder ?? ""
        let before = flow.wrote
        let hold = BackgroundHold(named: "Move albums")
        defer { hold.end() }
        // each name's wait is worked out from its albums' size: one the page hadn't read is asked for now
        for name in ArtistRefileFlow.unsized(names, in: sizes) {
            do {
                sizes[name] = try await client.libraryArtist(name: name)?.totalSize ?? 0
            } catch {
                flow.moveNotStarted(words: EditWords.said(error, failed: ArtistManageWords.sizesFailed, admin: admin))
                return
            }
        }
        var applied: [ArtistManage.AppliedName] = []
        var stopped: (outcome: RetagFlow.Outcome, words: String?)?
        for named in names {
            // signed out, or someone else signed in, since Move was pressed: nothing more sent
            guard samePerson else {
                stopped = (.refused, ArtistManageWords.moveStopped)
                break
            }
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
        // a move carries the pictures along into their folder now: drawn again wherever they are
        if flow.wrote > before { ArtistFolderVersions.shared.wrote(client, path: toFolder) }
        AccessibilityNotification.Announcement(again ? EditWords.mayHaveFinished : flow.outcome?.text ?? "").post()
        guard samePerson else { return }
        if flow.wrote > before { onMoved?() }
        // (slice 6) a write anywhere in managing, or one that may have been: Needs a look's count asked again
        if flow.wrote > before || again { navigation?.managed() }
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
