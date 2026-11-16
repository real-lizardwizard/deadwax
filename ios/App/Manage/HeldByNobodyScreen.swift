import DeadwaxCore
import Observation
import SwiftUI

/// Library care > In nobody's library (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; the web's
/// app/HeldByNobody.tsx, inline on its Library care): with logins on, an admin's (Look after the library) - how many
/// albums in the store are in nobody's library, the first 20 of them (Show all), and the downloads flagged for a look,
/// each with Add for them and Dismiss. Pushed here, where the web draws it under the runs.
///
/// One write at a time (Core's Held.Flow): a second tap asks nothing more, and nothing is asked out of reach or before a
/// read to trust. After each, whatever came of it, the list is read again. A refusal is said in deadwax's words (EditWords
/// .said over the web's "Couldn't add it for them."); one that never answered may have finished - said, and the list read
/// again to see. What a write did is spoken as the web's hidden line says it. Rows are known by their ids; VoiceOver reads
/// each once. Nothing is done past a sign-out: the model's session is AppNavigation's when the page opened. Nothing is
/// read under the sign-in over the app (its 401 would only be said as a failure); once it goes, the list is read again.
/// A flag's buttons stay off while the list is read - the read after a write included.
struct HeldByNobodyScreen: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = HeldModel()
    @State private var visible = false

    var body: some View {
        let shown = Managing.heldShown(loginsOn: server.access.on,
                                       parts: Managing.careParts(server.access.permissions))
        Group {
            if !shown {
                ContentUnavailableView {
                    Label(Held.title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if !reachability.online && model.answer == nil {
                ContentUnavailableView {
                    Label(Held.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                list
            }
        }
        .navigationTitle(Held.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.attach(server: server, navigation: navigation, reachability: reachability)
            visible = true
        }
        .task {
            model.attach(server: server, navigation: navigation, reachability: reachability)
            guard shown else { return }
            await model.read()
        }
        .onDisappear { visible = false }
        .onChange(of: reachability.online) { _, now in
            if !now {
                model.outOfReach()
            } else if visible, shown {
                Task { await model.read() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, visible, shown else { return }
            Task { await model.read() }
        }
        .onChange(of: shown) { _, now in
            guard now, visible else { return }
            Task { await model.read() }
        }
        // signed in again over the app: what failed under it is read again
        .onChange(of: server.signInOver == nil) { _, clear in
            guard clear, visible, shown else { return }
            Task { await model.read() }
        }
    }

    // MARK: the page

    private var list: some View {
        let online = reachability.online
        return List {
            if let answer = model.answer {
                Section {
                    Text(Held.line(answer.count))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Held.listedAlbums(answer.albums, all: model.all)) { (album: Held.UnheldAlbum) in
                        HeldAlbumRow(album: album)
                    }
                    if let more = Held.showLabel(all: model.all, count: answer.albums.count) {
                        Button(more) {
                            model.all.toggle()
                        }
                    }
                }
                if !answer.flags.isEmpty {
                    Section {
                        ForEach(answer.flags) { (flag: Held.Flag) in
                            flagRow(flag, online: online)
                        }
                    } header: {
                        Text(Held.flagged)
                            .font(Typeface.footnote)
                    }
                }
                if let words = model.refused ?? model.problem {
                    Section {
                        ErrorNote(text: words)
                    }
                }
            } else if let problem = model.problem {
                Section {
                    ErrorNote(text: problem)
                    Button(LibraryCare.tryAgain) {
                        Task { await model.read() }
                    }
                    .disabled(model.reading || !online)
                }
            } else {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(Held.loading).foregroundStyle(Palette.quiet)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .editOutOfReach(!online && model.answer != nil)
        .refreshable {
            guard online else { return }
            await model.read()
        }
    }

    /// A flagged download: its name, who asked and why nobody was given it, and its two buttons.
    private func flagRow(_ flag: Held.Flag, online: Bool) -> some View {
        let open = model.flow.open(online: online, reading: model.reading)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Held.flagName(flag))
                    .font(Typeface.body.weight(.semibold))
                Text(Held.flagWords(flag))
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            HStack(spacing: 16) {
                Button(Held.addForThem) {
                    model.act(flag, .add, online: online)
                }
                .buttonStyle(PrimaryFace())
                Button(Held.dismiss) {
                    model.act(flag, .dismiss, online: online)
                }
                .buttonStyle(.borderless)
            }
            .disabled(!open)
        }
        .padding(.vertical, 4)
    }
}

/// An album nobody has: its name, then its folder - read once.
private struct HeldAlbumRow: View {
    let album: Held.UnheldAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Held.albumName(album))
            Text(album.path)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}

/// In nobody's library's answer and its writes, for the page's life (HeldByNobody.tsx's state): every decision Core's
/// Held.Flow - this asks, keeps and says. Only the newest read lands; a read cancelled is neither an answer nor a
/// failure; nothing lands past a sign-out.
@MainActor
@Observable
final class HeldModel {
    private(set) var answer: Held.Answer?
    /// Why the list couldn't be read - kept apart from why the last write was refused.
    private(set) var problem: String?
    private(set) var refused: String?
    private(set) var reading = false
    private(set) var flow = Held.Flow()
    /// Show all.
    var all = false
    @ObservationIgnored private weak var server: ServerModel?
    @ObservationIgnored private weak var navigation: AppNavigation?
    @ObservationIgnored private weak var reachability: Reachability?
    /// AppNavigation's session when the page opened: nothing is done for the next person.
    @ObservationIgnored private var session: Int?

    func attach(server: ServerModel, navigation: AppNavigation, reachability: Reachability) {
        self.server = server
        self.navigation = navigation
        self.reachability = reachability
        if session == nil { session = navigation.session }
    }

    private var samePerson: Bool {
        guard let session, let navigation else { return false }
        return session == navigation.session
    }

    private var admin: Bool { server?.access.seesDetail ?? false }

    /// The list read (`GET /library/held`) - in reach only, and never under the sign-in over the app.
    func read() async {
        guard reachability?.online == true, samePerson, server?.signInOver == nil, let client = server?.client else {
            return
        }
        let ticket = flow.readBegan()
        reading = true
        do {
            let found = try await client.heldByNobody()
            guard ticket == flow.reads, samePerson else { return }
            reading = false
            answer = found
            problem = nil
            flow.readLanded(ticket)
        } catch {
            guard ticket == flow.reads, samePerson else { return }
            reading = false
            guard !APIFailure.isCancellation(error) else { return }
            problem = EditWords.said(error, failed: Held.readFailed, admin: admin)
        }
    }

    /// deadwax went out of reach: what is on screen is how it was, and nothing is asked until a read lands again.
    func outOfReach() {
        flow.outOfReach()
    }

    /// Add for them or Dismiss pressed: one at a time, its answer said, and the list read again whatever came of it.
    func act(_ flag: Held.Flag, _ write: Held.Write, online: Bool) {
        guard samePerson, let client = server?.client, flow.begin(flag.id, online: online, reading: reading) else {
            return
        }
        refused = nil
        let name = Held.saidName(answer?.flags.first { $0.id == flag.id })
        let hold = BackgroundHold(named: "In nobody's library")
        Task {
            defer { hold.end() }
            var said: String?
            do {
                switch write {
                case .add:
                    let added = try await client.addFlagged(flag.id)
                    said = Held.added(name, users: added.users)
                case .dismiss:
                    _ = try await client.dismissFlag(flag.id)
                    said = Held.dismissed(name)
                }
            } catch {
                guard samePerson else { return }
                if !APIFailure.isCancellation(error) {
                    if RetagFlow.outcome(of: error) == .refused {
                        refused = EditWords.said(error, failed: write.failed, admin: admin)
                    } else {
                        // never answered, or deadwax failed: it may have gone through - the list read again says
                        refused = EditWords.writeFailure(error, failed: write.failed, admin: admin)
                        said = EditWords.mayHaveFinished
                    }
                }
            }
            guard samePerson else { return }
            flow.ended()
            if let said { AccessibilityNotification.Announcement(said).post() }
            await read()
        }
    }
}
