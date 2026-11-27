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
                            .escapeCloses()
                    } else {
                        Button(ArtistManageWords.cancel) { dismiss() }
                            .disabled(model?.flow.applying == true)
                            .escapeCloses()
                    }
                }
            }
        }
        // (R20) the page's ground under the sheet, not the system's raised grey
        .presentationBackground(HoldoutLook.ground)
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

/// (R20 - notes/ios.md "The panel review, R20: the known holdouts (2026-11-26)") Move albums' page, no List: the holdouts'
/// pieces (DebugView's) - on the phone flat (R1c), the subtitle, the outcome, the plan's parts and Move each a group on the
/// page's black; on the Mac the Mac's group boxes on --bg. The plan is still the confirmation: Move is the primary button,
/// under the preview it applies, on only as canMove says - nothing moves from anywhere else.
private struct ArtistMoveRoot: View {
    let model: ArtistMoveModel
    let name: String

    var body: some View {
        let flow = model.flow
        Group {
            if !flow.online && flow.plans == nil && flow.outcome == nil && flow.error == nil {
                HoldoutUnavailable(title: ArtistManageWords.refileTitle, symbol: "wifi.slash", words: EditWords.needsDeadwax)
            } else {
                HoldoutPage {
                    // the web's subtitle: whose albums move, and to which name ("Kanye West → Ye") - what a Move was
                    // made for while it runs and once it is over, the page's names emptied by it or not
                    HoldoutGroup {
                        let shown = flow.shownFor
                        HoldoutLine(ArtistManage.refileSubtitle(moveNames: shown.names, current: shown.current, name: name))
                    }
                    if let outcome = flow.outcome {
                        HoldoutGroup {
                            HoldoutLine(outcome.text, tone: DWPalette.text)
                            ForEach(Array(outcome.failures.enumerated()), id: \.offset) { (_: Int, failure: String) in
                                HoldoutLine(failure, tone: DWPalette.amberText)
                            }
                        }
                    } else {
                        if flow.mayHaveFinished {
                            HoldoutGroup {
                                if let partly = flow.partly {
                                    HoldoutLine(partly, tone: DWPalette.text)
                                }
                                MayHaveFinished(reading: flow.loading)
                                    .font(HoldoutLook.words)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .holdoutRow()
                            }
                        }
                        if let settled = flow.settled {
                            // what the check after a Move that never answered found
                            HoldoutGroup {
                                HoldoutLine(settled, tone: DWPalette.text)
                            }
                        }
                        if let error = flow.error {
                            HoldoutGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ReadAgainFailed(failure: error, disabled: !flow.online || flow.loading) {
                                        Task { await model.preview() }
                                    }
                                }
                                .buttonStyle(DWButtonStyle(size: .small))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .holdoutRow()
                            }
                        } else if flow.loading && flow.plans == nil {
                            HoldoutGroup {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(ArtistManageWords.working)
                                        .font(HoldoutLook.words)
                                        .foregroundStyle(DWPalette.text)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .holdoutRow()
                                .accessibilityElement(children: .combine)
                            }
                        } else if let view = flow.view {
                            plan(view)
                        } else if flow.plans != nil {
                            // no name left to move them from
                            HoldoutGroup {
                                HoldoutLine(ArtistManageWords.nothingToMove(flow.ask.current ?? name), tone: DWPalette.text)
                            }
                        }
                        HoldoutGroup {
                            HoldoutButtons {
                                Button {
                                    Task { await model.move() }
                                } label: {
                                    HStack(spacing: 10) {
                                        if flow.applying || (flow.loading && flow.plans != nil) { ProgressView() }
                                        HoldoutWords(flow.applying ? ArtistManageWords.moving
                                            : ArtistManage.moveButton(flow.view?.moves.count ?? 0))
                                    }
                                }
                                .buttonStyle(DWButtonStyle(kind: .pri, size: .small))
                                .disabled(!flow.canMove)
                            }
                            if let words = flow.notStarted {
                                HoldoutLine(words, tone: DWPalette.amberText)
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
        HoldoutGroup {
            Text(Self.note(note))
                .font(HoldoutLook.words)
                .foregroundStyle(DWPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holdoutRow()
            ForEach(Array(view.problems.enumerated()), id: \.offset) { (_: Int, problem: String) in
                HoldoutLine(problem, tone: DWPalette.amberText)
            }
            if view.empty && view.problems.isEmpty {
                HoldoutLine(view.refused.isEmpty ? ArtistManageWords.nothingToMove(view.currentName)
                    : ArtistManageWords.nothingCanMove, tone: DWPalette.text)
            }
        }
        if !view.moves.isEmpty {
            HoldoutGroup(legend: ArtistManageWords.albumsThatMove) {
                ForEach(view.moves, id: \.path) { (move: RefileMove) in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(move.path)
                            .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                            .foregroundStyle(DWPalette.text)
                        Text(ArtistManageWords.movesTo(move.targetPath))
                            .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                            .foregroundStyle(DWPalette.t2)
                        Text(ArtistManage.moveLine(move))
                            .font(HoldoutLook.small)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .holdoutRow()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        if !view.refused.isEmpty {
            HoldoutGroup(legend: ArtistManageWords.albumsThatStay) {
                ForEach(view.refused, id: \.path) { (refused: RefileRefused) in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(refused.path)
                            .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                            .foregroundStyle(DWPalette.text)
                        Text(ArtistManageWords.stays(refused.reason))
                            .font(HoldoutLook.small)
                            .foregroundStyle(DWPalette.amberText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .holdoutRow()
                    .accessibilityElement(children: .combine)
                }
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
///
/// (R20) Drawn as Artist images' search is, from the holdouts' pieces: flat on the phone, its field in the well; the
/// Mac's group boxes on the Mac.
struct ArtistWhoSheet: View {
    let name: String
    let onChosen: (MBArtistMatch) -> Void

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(\.dismiss) private var dismiss
    @State private var model: ArtistWhoModel?

    private enum Typing: Hashable { case search }
    @FocusState private var typing: Typing?

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
                        // (the Mac app, slice 2) Escape is Close only while the search is the page's name, as it opened:
                        // Close throws away other words without asking
                        .escapeCloses(model.map { (model: ArtistWhoModel) -> Bool in model.query == name } ?? true)
                }
            }
        }
        // (R20) the page's ground under the sheet, not the system's raised grey
        .presentationBackground(HoldoutLook.ground)
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
            HoldoutUnavailable(title: ArtistManageWords.whoTitle, symbol: "wifi.slash", words: EditWords.needsDeadwax)
        } else {
            HoldoutPage {
                HoldoutGroup {
                    HoldoutLine(ArtistManageWords.whoNote(name))
                }
                HoldoutGroup(legend: ArtistManageWords.searchLabel) {
                    HStack(spacing: 10) {
                        TextField(ArtistManageWords.searchLabel, text: $model.query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($typing, equals: .search)
                            .modifier(HoldoutField(focus: $typing, field: .search))
                            .onSubmit { Task { await model.search() } }
                        Button {
                            Task { await model.search() }
                        } label: {
                            HoldoutWords(ArtistManageWords.search)
                        }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .disabled(ArtistManage.searchWords(model.query).isEmpty || !flow.online)
                    }
                    .holdoutRow()
                    if flow.searching {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(ArtistManageWords.searching)
                                .font(HoldoutLook.words)
                                .foregroundStyle(DWPalette.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .holdoutRow()
                        .accessibilityElement(children: .combine)
                    }
                    if let note = flow.note {
                        HoldoutLine(note)
                    }
                }
                if let matches = flow.matches, !matches.isEmpty {
                    HoldoutGroup(legend: ArtistManageWords.artistsGoingBy) {
                        ForEach(matches, id: \.mbid) { (match: MBArtistMatch) in
                            ArtistMatchRow(match: match) {
                                onChosen(match)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .editOutOfReach(!flow.online)
        }
    }
}
