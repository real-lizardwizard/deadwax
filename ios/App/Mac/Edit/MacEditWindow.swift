import DeadwaxCore
import SwiftUI

/// Edit album on the Mac (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list
/// and Release"; Main.dc.html): one page, Settings' Edit an album - the library's folders at its left (MacFolderList),
/// the album's editor at its right: its header (MacEditHeader), its five folder tabs, the tab's own content (Release's,
/// MacReleaseTab) and the foot (MacEditFooter: Revert and Apply). Every Edit album on the Mac opens here
/// (AppNavigation.editAlbum - an album page's Edit, Needs a look's row), never the sheet.
///
/// - The editor is the sheet's own model (EditAlbumModel), made afresh for each opening as the sheet made it - a folder
///   picked in the list is an opening of its own, 200 ms after the pick rests (R2's rest) - and every write is its
///   own: Apply sends the preview's body and the server works the plan out again from it (EditAlbumModel.apply).
/// - Typed work, a write or a mark under way (EditAlbumModel.holdsWork): another folder picked, a step through the
///   queue and an opening from elsewhere each ask "Discard changes?" first, Discard destructive, Keep editing Return's;
///   the window can't be closed (`keepsWindowOpen`), Back isn't drawn, and the page is kept under any page opened over
///   it (AppNavigation's `kept`). While an apply runs nothing is asked: an opening waits for its end.
/// - (R10's review) The editor - its header, tabs, tab, foot and part sheet, and the tab chosen - is MacAlbumEditor,
///   which R12's MacNeedsALook hosts too; this page owns the model and its opening, the list, and every question.
/// - (R10's review) What typed work holds (the window kept open, no Back, the stacks told) is read in a modifier of its
///   own (MacEditHolding): holdsWork reads Release's fields, and this page's body - the list's rows filtered, sorted
///   and diffed over every folder of the library - never re-runs for a keystroke.
/// - Opened from Needs a look (queue mode): the queue's own scan, and the queue's bar under the header's chip - ‹, where it
///   is, Skip › - each step through the editor's gate as the sheet's. (R12 - notes/ios.md "The redesign, slice R12:
///   Needs a look") A row of the queue is edited on Needs a look's own page, beside it (MacNeedsALook,
///   AppNavigation.macEditHost); this page edits a queue's album only when its opening was asked for over this page's
///   work - Discard then opens it here - and never draws an opening edited there (`macEdit(on:)`). Either page's queue
///   opening ends where the Run decides it (NeedsLookModel.closeEditor: a step to an album gone, a facet chosen), never
///   read here from the session going (R12's review took R10's handler of that out).
struct MacEditWindow: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    /// The library's folders, as the list reads them - and the editor's scan, opened from anywhere but Needs a look.
    @State private var scan = LibraryScanModel()
    @State private var model: EditAlbumModel?
    /// The opening the model is for, and the queue's step (NeedsLookModel.steps): either changed, a model made afresh.
    @State private var opened: UUID?
    @State private var step = 0
    @State private var selected: String?
    @State private var typed = ""
    @State private var shown: EditAlbumPage.Shown = .all
    @State private var askingDiscard = false
    @State private var pending: Pending?
    /// The page's own width (the window less the sidebar, and the side panel when open): its layout.
    @State private var width: Double = MacFrame.openingWidth - MacLook.sidebarWidth

    /// (R2) A pick in the list rests this long before the editor opens on it: the arrow keys run past folders.
    private static let rest: UInt64 = 200_000_000

    /// What "Discard changes?" was asked for.
    private enum Pending: Equatable {
        /// another folder, picked in the list
        case folder(String)
        /// a step through the queue
        case step(Int)
        /// an opening from elsewhere (AppNavigation.macEditAsked)
        case opening
    }

    /// The task's key: a new opening, a step, deadwax in or out of reach.
    private struct Opening: Equatable {
        let id: UUID?
        let step: Int
        let online: Bool
    }

    var body: some View {
        let layout = EditAlbumPage.Layout(page: width)
        HStack(spacing: 0) {
            MacFolderList(scan: scan, typed: $typed, shown: $shown, selected: $selected,
                          artistColumn: layout.artistColumn, writing: model?.writing == true,
                          lookAgain: { Task { await readList() } })
                .frame(width: CGFloat(layout.list))
            DWRule(colour: DWPalette.frame, vertical: true)
            Group {
                if let model {
                    let queue = navigation.macEdit?.queue?.nav.map { (nav: NeedsLook.Nav) -> MacEditQueue in
                        MacEditQueue(nav: nav) { (delta: Int) -> Void in take(delta, model: model) }
                    }
                    MacAlbumEditor(model: model, layout: layout, queue: queue) {
                        if let queue { MacEditQueueBar(queue: queue, model: model) }
                    }
                } else {
                    MacEditNote(words: EditAlbumPage.Words.pickAFolder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DWPalette.bg)
        .onGeometryChange(for: Double.self) { (page: GeometryProxy) -> Double in
            Double(page.size.width)
        } action: { (now: Double) -> Void in
            width = now
        }
        // typed work isn't lost by closing the window, nor by Back: Discard is asked for every other way it could go
        .modifier(MacEditHolding(model: model))
        .task(id: Opening(id: navigation.macEdit?.id, step: navigation.macEdit?.queue?.steps ?? 0,
                          online: reachability.online)) {
            // (R12) an opening edited beside Needs a look's queue is that page's: none here
            await open(navigation.macEdit(on: .chooseFolder))
        }
        .task(id: selected) {
            guard let path = selected, path != model?.album?.path else { return }
            try? await Task.sleep(nanoseconds: Self.rest)
            guard !Task.isCancelled else { return }
            pick(path)
        }
        .onChange(of: model?.album?.path, initial: true) { (_: String?, now: String?) -> Void in
            if let now { selected = now }
        }
        // an opening asked for over work: asked about here - once any apply under way has ended and the folder has
        // been read again after it (`following`), so its typed work is weighed against what the folder now holds
        .onChange(of: navigation.macEditAsked?.id) { (_: UUID?, _: UUID?) -> Void in askAboutOpening() }
        .onChange(of: model?.applying == true) { (_: Bool, _: Bool) -> Void in askAboutOpening() }
        .onChange(of: model?.following ?? 0) { (_: Int, _: Int) -> Void in askAboutOpening() }
        .onChange(of: askingDiscard) { (_: Bool, _: Bool) -> Void in askAboutOpening() }
        // the folder deleted: nothing left to edit - the list read again; in queue mode the editor stays saying so
        .onChange(of: model?.deleted == true) { (_: Bool, gone: Bool) -> Void in
            guard gone else { return }
            if navigation.macEdit?.queue == nil {
                navigation.macEditEnded()
            } else {
                Task { await readList() }
            }
        }
        .onChange(of: reachability.online) { (_: Bool, now: Bool) -> Void in
            Task { await model?.reach(now) }
        }
        .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) -> Void in
            guard phase == .active else { return }
            Task { await model?.becameActive() }
        }
        .confirmationDialog(EditWords.discardTitle, isPresented: $askingDiscard, titleVisibility: .visible) {
            Button(EditWords.discard, role: .destructive) { discarded() }
            Button(EditWords.keepEditing, role: .cancel) { keptEditing() }
                .returnCancels()
        }
    }

    // MARK: opening

    /// The opening shown: its model made as the sheet makes it - the queue's folder and scan in queue mode, else the
    /// list's scan - and opened; none, the list read alone.
    private func open(_ request: AlbumEditRequest?) async {
        guard let request else {
            model = nil
            opened = nil
            await readList()
            return
        }
        let wanted = request.queue?.steps ?? 0
        if model == nil || opened != request.id || step != wanted {
            let made = EditAlbumModel(request: request, target: request.queue?.folder.map { .folder($0) },
                                      scan: request.queue?.scan ?? scan, client: server.client,
                                      admin: server.access.seesDetail, online: reachability.online)
            made.attach(navigation, library: library)
            model = made
            opened = request.id
            step = wanted
        }
        // (R10's review) the page come back - a tab switched, a page pushed over it - with its first read cut off: asked
        // again, never left finding the folder for good
        await model?.reopen()
        // in queue mode the editor reads the queue's scan: the list reads its own
        if request.queue != nil { await readList() }
    }

    /// The list's own read, once - and again after a delete in queue mode, or Look again.
    private func readList() async {
        guard reachability.online, !scan.reading else { return }
        await scan.read(client: server.client, admin: server.access.seesDetail)
    }

    /// A folder picked in the list, once the pick has rested: opened - over typed work, asked about first.
    private func pick(_ path: String) {
        guard let model else {
            navigation.editAlbum(AlbumEditRequest(target: .folder(path)))
            return
        }
        // never while an apply runs, nor until the folder is read again after it: typed work is weighed against what
        // the folder holds now
        guard !model.applying, model.following == 0 else {
            selected = model.album?.path
            return
        }
        if model.holdsWork {
            pending = .folder(path)
            askingDiscard = true
        } else {
            navigation.editAlbum(AlbumEditRequest(target: .folder(path)))
        }
    }

    /// An opening asked for from elsewhere while the editor holds work - never while an apply runs or its follow-up
    /// read is out (R10's review: an apply's end comes before that read, and typed work then still compares against the
    /// folder as it was, so Discard would be asked of work the apply wrote), nor over another question: asked once
    /// those end.
    private func askAboutOpening() {
        // (R12) asked by the page the editor is on - Needs a look's, beside its queue, asks there
        guard navigation.macEditHost == .chooseFolder else { return }
        guard navigation.macEditAsked != nil, model?.applying != true, (model?.following ?? 0) == 0,
              !askingDiscard else { return }
        if model?.holdsWork == true {
            pending = .opening
            askingDiscard = true
        } else {
            navigation.macEditAnswered(discard: true)
        }
    }

    private func discarded() {
        let asked = pending
        pending = nil
        switch asked {
        case .folder(let path):
            // the work let go: the page's own pick opens at once
            navigation.macEditHolding(false)
            navigation.editAlbum(AlbumEditRequest(target: .folder(path)))
        case .step(let delta):
            // the gate as it is now: a write may have started since the step was asked
            if let model { navigation.macEdit?.queue?.go(by: delta, gate: model.stepGate) }
        case .opening:
            navigation.macEditAnswered(discard: true)
        case nil:
            break
        }
    }

    private func keptEditing() {
        let asked = pending
        pending = nil
        switch asked {
        case .folder:
            selected = model?.album?.path
        case .opening:
            navigation.macEditAnswered(discard: false)
        case .step, nil:
            break
        }
    }

    // MARK: the queue

    /// A step through the queue, through the editor's gate: typed work asks first, as a pick does.
    private func take(_ delta: Int, model: EditAlbumModel) {
        guard let queue = navigation.macEdit?.queue, model.canStep else { return }
        if model.holdsWork {
            pending = .step(delta)
            askingDiscard = true
            return
        }
        queue.go(by: delta, gate: model.stepGate)
    }
}

/// (R10's review) What the page's typed work holds, read here alone (EditAlbumModel.holdsWork reads Release's fields):
/// the window kept open, Back not drawn, and the stacks told (AppNavigation.macEditHolding) - a keystroke re-runs this
/// modifier, never MacEditWindow's body, so the folder list isn't filtered, sorted and diffed again for each letter.
/// (R12) Needs a look's page holds its editor's work with it too (MacNeedsALook); a page drawing no editor (`model`
/// nil - the other page has the opening) says nothing, so it never says "no work" over the page that has some.
struct MacEditHolding: ViewModifier {
    let model: EditAlbumModel?
    @Environment(AppNavigation.self) private var navigation

    func body(content: Content) -> some View {
        let holds = model?.holdsWork == true
        content
            .keepsWindowOpen(holds)
            .navigationBarBackButtonHidden(holds)
            .onChange(of: holds, initial: true) { (_: Bool, now: Bool) -> Void in
                guard model != nil else { return }
                navigation.macEditHolding(now)
            }
    }
}

/// (R12) Queue mode as the Mac's editor needs it: where the session is, and a step - taken through its host's gate and
/// "Discard changes?" (MacEditWindow's `take`, MacNeedsALook's) - for the bar's ‹ and Skip › and the foot's Next album.
struct MacEditQueue {
    let nav: NeedsLook.Nav
    let take: (Int) -> Void
}

/// Queue mode's bar (R12 - notes/ios.md "The redesign, slice R12: Needs a look"; NeedsALook.dc.html): ‹ (Previous
/// album), where it is ("1 of 3", in the readout face as drawn), and Skip › - or Next album › once a write was told of
/// the album - small buttons 6 apart on one text baseline (the readout's), under the header's chip (MacEditHeader's
/// `bar`). A view of its own, so the step gate is read here, never in a host's body.
struct MacEditQueueBar: View {
    let queue: MacEditQueue
    let model: EditAlbumModel

    var body: some View {
        let nav = queue.nav
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button(NeedsLookPage.back) {
                queue.take(-1)
            }
            .buttonStyle(DWButtonStyle(size: .small))
            .accessibilityLabel(NeedsLookWords.previous)
            .help(NeedsLookWords.previous)
            .disabled(!nav.back || !model.canStep)
            Text(nav.place)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .fixedSize()
            Button(nav.forward) {
                queue.take(1)
            }
            .buttonStyle(DWButtonStyle(size: .small))
            .accessibilityLabel(nav.forwardSpoken)
            .accessibilityHint(nav.nextAlbum ? "" : NeedsLookWords.skipHint)
            .help(nav.nextAlbum ? nav.forwardSpoken : NeedsLookWords.skipHint)
            .disabled(!nav.on || !model.canStep)
        }
        .fixedSize()
    }
}
