import DeadwaxCore
import Observation
import SwiftUI

/// Library care > In nobody's library (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; the web's
/// app/HeldByNobody.tsx, inline on its Library care): with logins on, an admin's (Look after the library) - how many
/// albums in the store are in nobody's library, the first 20 of them (Show all), and the downloads flagged for a look,
/// each with Add for them and Dismiss. Pushed here, where the web draws it under the runs - from both of Library care's
/// collection rows (there is no route of Flagged downloads' own). (The redesign, slice R13 - notes/ios.md "The redesign,
/// slice R13: Library care and the Event log") Drawn flat, as Library care is: the large title, two groups on the page's
/// black, their rows on hairlines. The Mac draws all of it in Library care's own boxes (MacLibraryCarePage).
///
/// One write at a time (Core's Held.Flow): a second tap asks nothing more, and nothing is asked out of reach or before a
/// read to trust. After each, whatever came of it, the list is read again. A refusal is said in deadwax's words (EditWords
/// .said over the web's "Couldn't add it for them."); one that never answered may have finished - said, and the list read
/// again to see. What a write did is spoken as the web's hidden line says it. Rows are known by their ids; VoiceOver reads
/// each once, a flag's buttons its actions. Nothing is done past a sign-out: the model's session is AppNavigation's when
/// the page opened. Nothing is read under the sign-in over the app (its 401 would only be said as a failure); once it
/// goes, the list is read again. A flag's buttons stay off while the list is read - the read after a write included.
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
                page
            }
        }
        .navigationTitle(Held.title)
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

    private var page: some View {
        let online = reachability.online
        return SettingsPage {
            if let answer = model.answer {
                PhoneGroup(legend: Held.title) {
                    Text(Held.line(answer.count))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, CareLook.groupPad)
                        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                    // (R13's review) lazy, as the List it was: Show all can be hundreds of albums, inside the page's
                    // one scroll
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Held.listedAlbums(answer.albums, all: model.all)) { (album: Held.UnheldAlbum) in
                            HeldAlbumRow(album: album)
                        }
                    }
                    if let more = Held.showLabel(all: model.all, count: answer.albums.count) {
                        Button(more) {
                            model.all.toggle()
                        }
                        .buttonStyle(DWButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, CareLook.rowPad)
                    }
                }
                if !answer.flags.isEmpty {
                    PhoneGroup(legend: Held.flagged) {
                        ForEach(answer.flags) { (flag: Held.Flag) in
                            HeldFlagRow(flag: flag, model: model, online: online)
                        }
                    }
                }
                if let words = model.refused ?? model.problem {
                    ErrorNote(text: words)
                        .padding(.top, CareLook.noteAbove)
                }
            } else if let problem = model.problem {
                VStack(alignment: .leading, spacing: CareLook.lines) {
                    ErrorNote(text: problem)
                    Button(LibraryCare.tryAgain) {
                        Task { await model.read() }
                    }
                    .buttonStyle(DWButtonStyle())
                    .disabled(model.reading || !online)
                }
                .padding(.top, CareLook.noteAbove)
            } else {
                HStack(spacing: CareLook.gap) {
                    ProgressView()
                    Text(Held.loading)
                        .foregroundStyle(DWPalette.t2)
                }
                .font(Typeface.Phone.text(.small))
                .padding(.top, CareLook.noteAbove)
                .accessibilityElement(children: .combine)
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .editOutOfReach(!online && model.answer != nil)
        .pullToRefresh {
            guard online else { return }
            await model.read()
        }
    }
}

/// A flagged download: its name, who asked and why nobody was given it, and its two buttons - Add for them the
/// primary's face (a filled button keeps its face on the flat phone), Dismiss flat in the accent. One VoiceOver element,
/// its buttons its actions; at the accessibility sizes the buttons stack, each across the row, their words on up to three
/// lines.
private struct HeldFlagRow: View {
    let flag: Held.Flag
    let model: HeldModel
    let online: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let open = model.flow.open(online: online, reading: model.reading)
        VStack(alignment: .leading, spacing: CareLook.lines) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Held.flagName(flag))
                    .font(Typeface.Phone.text(.row).weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                Text(Held.flagWords(flag))
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // each button off on its own (R13's review): one gate on each, whichever way they are laid out
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CareLook.lines) {
                    buttons(open: open)
                }
            } else {
                HStack(spacing: CareLook.gap) {
                    buttons(open: open)
                }
            }
        }
        .padding(.vertical, CareLook.rowPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Held.flagName(flag)), \(Held.flagWords(flag))")
        .accessibilityActions {
            if open {
                Button(Held.addForThem) { model.act(flag, .add, online: online) }
                Button(Held.dismiss) { model.act(flag, .dismiss, online: online) }
            }
        }
    }

    @ViewBuilder private func buttons(open: Bool) -> some View {
        let across = typeSize.isAccessibilitySize
        Button {
            model.act(flag, .add, online: online)
        } label: {
            CareButtonWords(words: Held.addForThem)
        }
        .buttonStyle(DWButtonStyle(kind: .pri, size: .small, fills: across))
        .disabled(!open)
        Button {
            model.act(flag, .dismiss, online: online)
        } label: {
            CareButtonWords(words: Held.dismiss)
        }
        .buttonStyle(DWButtonStyle(size: .small, fills: across))
        .disabled(!open)
    }
}

/// An album nobody has: its name, then its folder - read once, on the group's hairline.
private struct HeldAlbumRow: View {
    let album: Held.UnheldAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Held.albumName(album))
                .font(Typeface.Phone.text(.row))
                .foregroundStyle(DWPalette.text)
            Text(album.path)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.vertical, CareLook.rowPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookHeight(PhoneLook.goRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
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
