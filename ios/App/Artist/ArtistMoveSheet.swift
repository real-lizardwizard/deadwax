import DeadwaxCore
import SwiftUI

/// Move albums to {name} (Phase 8, slice 5 - phase8-managing.md 4; the web's RefileBody): a sheet from the artist page's
/// •••. Under the web's subtitle ("Kanye West → Ye", refileSubtitle), each name the library files them under that
/// isn't their name now (namesToMove) previewed together and drawn as one (refileView): where every album goes, the
/// folder in bold, the problems, Albums that move (each its folder, where it goes and moveLine) and Albums that stay
/// (each with why). Move N albums - on only as Core's ArtistRefileFlow.canMove
/// says, for previews made of the names the page shows now - applies each name in turn, then what became of it
/// (refileOutcome, and refileAfter's albums that stayed) with Done. The artist page is asked again (and once Navidrome
/// has scanned).
///
/// The eighth writer, plan/execute: the apply sends what its preview did, and the server works the plan out again. It
/// needs deadwax (section 2's rules, as Artist images'); while Move runs, Cancel is off and a swipe doesn't close it.
/// A Move that never answered is said as maybe finished, with what is known to have moved, and the moves previewed
/// again - which say whether it had finished (the outcome, and Done, when nothing is left) or how far it got (the plan
/// for the rest, Move offered again). The subtitle keeps naming what a Move was made for while it runs and once it is
/// over, as the page's names change under it.
struct ArtistMoveSheet: View {
    let ask: ArtistRefileFlow.Ask
    /// The page's name for them: the subtitle's when no name moves (the web's `request.name`).
    let name: String
    let sizes: [String: Double]
    let onMoved: () -> Void

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ArtistMoveModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    ArtistMoveRoot(model: model, name: name)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(ArtistManageWords.refileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model?.flow.outcome != nil {
                        Button(ArtistManageWords.done) { dismiss() }
                    } else {
                        Button(ArtistManageWords.cancel) { dismiss() }
                            .disabled(model?.flow.applying == true)
                    }
                }
            }
        }
        .interactiveDismissDisabled(model?.flow.applying == true)
        .task {
            if model == nil {
                let made = ArtistMoveModel(ask: ask, sizes: sizes, client: server.client,
                                           admin: server.access.seesDetail, online: reachability.online)
                made.attach(navigation)
                made.onMoved = onMoved
                model = made
            }
            await model?.open()
        }
        // the page's names, id or their name now changed: previewed again, never applied blind
        .onChange(of: ask) { _, now in
            Task { await model?.changed(now) }
        }
        // each name's size as the page reads it, for how long its apply is given - read as Move starts
        .onChange(of: sizes) { _, now in
            model?.sizes.merge(now) { (_: Double, read: Double) -> Double in read }
        }
        .onChange(of: reachability.online) { _, now in
            Task { await model?.reach(now) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model?.becameActive() }
        }
    }
}

private struct ArtistMoveRoot: View {
    let model: ArtistMoveModel
    let name: String

    var body: some View {
        let flow = model.flow
        Group {
            if !flow.online && flow.plans == nil && flow.outcome == nil && flow.error == nil {
                ContentUnavailableView {
                    Label(ArtistManageWords.refileTitle, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                List {
                    // the web's subtitle: whose albums move, and to which name ("Kanye West → Ye") - what a Move was
                    // made for while it runs and once it is over, the page's names emptied by it or not
                    Section {
                        let shown = flow.shownFor
                        Text(ArtistManage.refileSubtitle(moveNames: shown.names, current: shown.current, name: name))
                            .font(Typeface.subheadline)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let outcome = flow.outcome {
                        Section {
                            Text(outcome.text)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(outcome.failures.enumerated()), id: \.offset) { (_: Int, failure: String) in
                                Text(failure)
                                    .foregroundStyle(Palette.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        if flow.mayHaveFinished {
                            Section {
                                if let partly = flow.partly {
                                    Text(partly)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                MayHaveFinished(reading: flow.loading)
                            }
                        }
                        if let settled = flow.settled {
                            // what the check after a Move that never answered found
                            Section {
                                Text(settled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let error = flow.error {
                            Section {
                                ReadAgainFailed(failure: error, disabled: !flow.online || flow.loading) {
                                    Task { await model.preview() }
                                }
                            }
                        } else if flow.loading && flow.plans == nil {
                            Section {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(ArtistManageWords.working)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        } else if let view = flow.view {
                            plan(view)
                        } else if flow.plans != nil {
                            // no name left to move them from
                            Section {
                                Text(ArtistManageWords.nothingToMove(flow.ask.current ?? name))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Section {
                            Button {
                                Task { await model.move() }
                            } label: {
                                HStack(spacing: 10) {
                                    if flow.applying || (flow.loading && flow.plans != nil) { ProgressView() }
                                    Text(flow.applying ? ArtistManageWords.moving
                                        : ArtistManage.moveButton(flow.view?.moves.count ?? 0))
                                }
                            }
                            .disabled(!flow.canMove)
                            if let words = flow.notStarted {
                                Text(words)
                                    .font(Typeface.footnote)
                                    .foregroundStyle(Palette.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .editOutOfReach(!flow.online && (flow.plans != nil || flow.outcome != nil || flow.error != nil))
    }

    /// The previews, drawn as one (refileView).
    @ViewBuilder private func plan(_ view: ArtistManage.RefileView) -> some View {
        let note = ArtistManageWords.refileNote(toFolder: view.toFolder, currentName: view.currentName)
        Section {
            Text(Self.note(note))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(view.problems.enumerated()), id: \.offset) { (_: Int, problem: String) in
                Text(problem)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if view.empty && view.problems.isEmpty {
                Text(view.refused.isEmpty ? ArtistManageWords.nothingToMove(view.currentName)
                    : ArtistManageWords.nothingCanMove)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !view.moves.isEmpty {
            Section {
                ForEach(view.moves, id: \.path) { (move: RefileMove) in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(move.path)
                            .font(Typeface.mono(.footnote))
                        Text(ArtistManageWords.movesTo(move.targetPath))
                            .font(Typeface.mono(.footnote))
                            .foregroundStyle(Palette.quiet)
                        Text(ArtistManage.moveLine(move))
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(ArtistManageWords.albumsThatMove)
                    .font(Typeface.footnote)
            }
        }
        if !view.refused.isEmpty {
            Section {
                ForEach(view.refused, id: \.path) { (refused: RefileRefused) in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(refused.path)
                            .font(Typeface.mono(.footnote))
                        Text(ArtistManageWords.stays(refused.reason))
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.amber)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(ArtistManageWords.albumsThatStay)
                    .font(Typeface.footnote)
            }
        }
    }

    /// The note with its folder in bold, as the web's <strong>.
    private static func note(_ parts: (lead: String, folder: String, rest: String)) -> AttributedString {
        var folder = AttributedString(parts.folder)
        folder.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(parts.lead) + folder + AttributedString(parts.rest)
    }
}

/// Which artist is this? (Phase 8, slice 5; the web's WhoBody): a sheet from the artist page's •••, for a page that
/// can't say who its artist is on MusicBrainz. What choosing does, the search - asked as it opens for the page's own
/// name - and every artist going by it, each with what tells them apart (matchLine). A pick gives the page that id for
/// this visit (ArtistsModel.choose: their albums, and the folder's pictures asked by it), and closes. It writes
/// nothing; it needs deadwax to search.
struct ArtistWhoSheet: View {
    let name: String
    let onChosen: (MBArtistMatch) -> Void

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(\.dismiss) private var dismiss
    @State private var model: ArtistWhoModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    root(model)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(ArtistManageWords.whoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EditWords.close) { dismiss() }
                }
            }
        }
        .task {
            if model == nil {
                model = ArtistWhoModel(name: name, client: server.client, admin: server.access.seesDetail,
                                       online: reachability.online)
            }
            await model?.open()
        }
        .onChange(of: reachability.online) { _, now in
            Task { await model?.reach(now) }
        }
    }

    @ViewBuilder private func root(_ model: ArtistWhoModel) -> some View {
        @Bindable var model = model
        let flow = model.flow
        if !flow.online && flow.matches == nil && flow.note == nil {
            ContentUnavailableView {
                Label(ArtistManageWords.whoTitle, systemImage: "wifi.slash")
            } description: {
                Text(EditWords.needsDeadwax)
            }
        } else {
            List {
                Section {
                    Text(ArtistManageWords.whoNote(name))
                        .font(Typeface.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    HStack(spacing: 10) {
                        TextField(ArtistManageWords.searchLabel, text: $model.query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await model.search() } }
                        Button(ArtistManageWords.search) {
                            Task { await model.search() }
                        }
                        .disabled(ArtistManage.searchWords(model.query).isEmpty || !flow.online)
                    }
                    if flow.searching {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(ArtistManageWords.searching)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let note = flow.note {
                        Text(note)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(ArtistManageWords.searchLabel)
                        .font(Typeface.footnote)
                }
                if let matches = flow.matches, !matches.isEmpty {
                    Section {
                        ForEach(matches, id: \.mbid) { (match: MBArtistMatch) in
                            ArtistMatchRow(match: match) {
                                onChosen(match)
                                dismiss()
                            }
                        }
                    } header: {
                        Text(ArtistManageWords.artistsGoingBy)
                            .font(Typeface.footnote)
                    }
                }
            }
            .editOutOfReach(!flow.online)
        }
    }
}
