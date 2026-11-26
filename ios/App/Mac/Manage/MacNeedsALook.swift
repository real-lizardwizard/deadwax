import DeadwaxCore
import SwiftUI

/// Needs a look on the Mac (the redesign, slice R12 - notes/ios.md "The redesign, slice R12: Needs a look";
/// NeedsALook.dc.html): the sidebar's Needs a look, one page - the queue at its left, the album's editor at its right,
/// the very editor Edit an album draws (MacAlbumEditor, R10's and R11's), never a second one.
///
/// - The left (MacNeedsLookList): its bar - Show, the facets as a pop-up with how many albums each has ("Every issue · 3
///   albums"), and Marked fine · N, a button of its own, on while it shows - then the web's ladder (LIBRARY_PATH's
///   problem, Reading the library, a first read failed with Try again) or the list: Album with its cover and its chips,
///   Artist (from a page of 1000), and Issues, how many each still has - each row one element to VoiceOver, the whole of
///   it on the pointer. Under the list what takes an album off it.
/// - A row picked (once the pick rests, R2's 200 ms) begins the session on it, as the phone's card does
///   (NeedsLookModel.open): Edit album opens beside the queue in queue mode (AppNavigation.macEditHost), the session's
///   rows held as they were. While it lasts, a row picked is a step to it, and ‹, Skip › and the foot's Next album are
///   steps - each through the editor's gate (EditAlbumModel.stepGate) and, over typed work, "Discard changes?" first;
///   another facet chosen ends the session, asked about the same way, and never while an apply runs or follows up. A
///   step the gate or Keep editing refuses leaves the album open selected.
/// - Typed work holds the page as Edit an album's does (MacEditHolding): the window kept open, no Back, the page kept
///   under any opened over it; an opening asked for from elsewhere is asked about here.
/// - The status bar: how many need a look - the sidebar's own count (NeedsLook.summaryTotal) - and how many are marked
///   fine, then Navidrome's note.
///
/// Every rule is the phone's page's, over the same model (NeedsLookModel, Core's Run): what it reads and when, who may
/// see it (Look after the library; Edit albums to fix), out of reach (the list kept under the amber line, ⌘R asking
/// nothing) - NeedsLookLife, which the phone's page wears too.
struct MacNeedsALook: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = NeedsLookModel()
    /// The album's editor, while the session has one open beside the queue.
    @State private var editor: EditAlbumModel?
    /// The opening the editor is for, and the session's step (NeedsLookModel.steps): either changed, one made afresh.
    @State private var opened: UUID?
    @State private var step = 0
    /// The row picked - the album open while a session lasts.
    @State private var selected: String?
    @State private var askingDiscard = false
    @State private var pending: Pending?
    /// The page's own width (the window less the sidebar, and the side panel when open): its layout.
    @State private var width: Double = MacFrame.openingWidth - MacLook.sidebarWidth

    /// (R2) A pick in the list rests this long before it opens: the arrow keys run past albums.
    private static let rest: UInt64 = 200_000_000

    /// What "Discard changes?" was asked for.
    private enum Pending: Equatable {
        /// a step through the session: ‹, Skip ›, Next album, a row picked
        case step(Int)
        /// another facet chosen while the session lasts (it ends the session)
        case facet(String?)
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
        let page = model.page
        ZStack {
            if !page.allowed {
                MacEditNote(words: EditWords.noPermission)
            } else if !reachability.online && !model.scan.loaded {
                MacEditNote(words: EditWords.needsDeadwax)
            } else {
                HStack(spacing: 0) {
                    MacNeedsLookList(model: model, selected: $selected, artistColumn: layout.artistColumn,
                                     writing: editor?.writing == true, choose: choose(facet:))
                        .frame(width: CGFloat(layout.list))
                    DWRule(colour: DWPalette.frame, vertical: true)
                    Group {
                        if let editor {
                            let queue = model.nav.map { (nav: NeedsLook.Nav) -> MacEditQueue in
                                MacEditQueue(nav: nav) { (delta: Int) -> Void in take(delta, editor: editor) }
                            }
                            MacAlbumEditor(model: editor, layout: layout, queue: queue) {
                                if let queue { MacEditQueueBar(queue: queue, model: editor) }
                            }
                        } else {
                            MacEditNote(words: NeedsLookPage.pickAnAlbum)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DWPalette.bg)
        .onGeometryChange(for: Double.self) { (room: GeometryProxy) -> Double in
            Double(room.size.width)
        } action: { (now: Double) -> Void in
            width = now
        }
        .macStatus(status(page))
        // ⌘R: the count asked and the library read again - never out of reach
        .pullToRefresh {
            await model.pulled()
        }
        .modifier(NeedsLookLife(model: model))
        // typed work isn't lost by closing the window, nor by Back: Discard is asked for every other way it could go
        .modifier(MacEditHolding(model: editor))
        .task(id: Opening(id: navigation.macEdit(on: .needsALook)?.id, step: model.steps,
                          online: reachability.online)) {
            await open(navigation.macEdit(on: .needsALook))
        }
        .task(id: selected) {
            guard let key = selected, key != current else { return }
            try? await Task.sleep(nanoseconds: Self.rest)
            guard !Task.isCancelled else { return }
            pick(key)
        }
        // the album open, selected: as a step moves it, and back on it when a step is refused
        .onChange(of: current, initial: true) { (_: String?, now: String?) -> Void in
            if let now { selected = now }
        }
        // the session over (Close, a facet chosen, a step to an album gone): nothing selected
        .onChange(of: model.session == nil) { (_: Bool, over: Bool) -> Void in
            if over { selected = nil }
        }
        // an opening asked for over work: asked about here - once any apply under way has ended and the folder has
        // been read again after it (`following`), so its typed work is weighed against what the folder now holds
        .onChange(of: navigation.macEditAsked?.id) { (_: UUID?, _: UUID?) -> Void in askAboutOpening() }
        .onChange(of: editor?.applying == true) { (_: Bool, _: Bool) -> Void in askAboutOpening() }
        .onChange(of: editor?.following ?? 0) { (_: Int, _: Int) -> Void in askAboutOpening() }
        .onChange(of: askingDiscard) { (_: Bool, _: Bool) -> Void in askAboutOpening() }
        .onChange(of: reachability.online) { (_: Bool, now: Bool) -> Void in
            Task { await editor?.reach(now) }
        }
        .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) -> Void in
            guard phase == .active else { return }
            Task { await editor?.becameActive() }
        }
        .confirmationDialog(EditWords.discardTitle, isPresented: $askingDiscard, titleVisibility: .visible) {
            Button(EditWords.discard, role: .destructive) { discarded() }
            Button(EditWords.keepEditing, role: .cancel) { keptEditing() }
                .returnCancels()
        }
    }

    /// The album the session has open: its row's key, the path it was listed at.
    private var current: String? {
        model.session?.current?.listed.path
    }

    /// The status bar's facts: how many need a look (the sidebar's count), how many are marked fine - then Navidrome's
    /// note, or the check under way. A failed read is said in the list, with Try again.
    private func status(_ page: Managing.NeedsLookPage) -> MacStatusItems.Items {
        guard page.allowed, model.scan.loaded else { return MacStatusItems.Items(leading: []) }
        let trailing: [String]
        switch model.status {
        case .checking?: trailing = [NeedsLook.checking]
        case .navidrome(let note)?: trailing = [note]
        case .failed?, nil: trailing = []
        }
        return MacStatusItems.Items(leading: NeedsLookPage.status(model.scan.albums), trailing: trailing)
    }

    // MARK: opening

    /// The opening shown beside the queue: its model made as the sheet makes it - the session's folder and the queue's
    /// scan - and opened; none (no session, or the opening Edit an album's), nothing beside the queue.
    private func open(_ request: AlbumEditRequest?) async {
        guard let request, request.queue === model else {
            editor = nil
            opened = nil
            return
        }
        let wanted = model.steps
        if editor == nil || opened != request.id || step != wanted {
            let made = EditAlbumModel(request: request, target: model.folder.map { .folder($0) }, scan: model.scan,
                                      client: server.client, admin: server.access.seesDetail,
                                      online: reachability.online)
            made.attach(navigation, library: library)
            editor = made
            opened = request.id
            step = wanted
        }
        // the page come back - a tab switched, a page pushed over it - with its first read cut off: asked again
        await editor?.reopen()
    }

    /// A row picked, once the pick has rested: with no session, the session begun on it (the editor opens beside the
    /// queue); in a session, a step to it - through the editor's gate, and over typed work asked about first.
    private func pick(_ key: String) {
        guard let row = model.rows.first(where: { (row: NeedsLook.DrawnRow) -> Bool in row.key == key }) else {
            selected = current
            return
        }
        guard model.session != nil else {
            model.open(row)
            // rows held after a session, or out of reach: nothing opened, nothing left selected
            if model.session == nil { selected = nil }
            return
        }
        let delta = model.step(to: row)
        guard delta != 0, let editor else {
            selected = current
            return
        }
        take(delta, editor: editor)
    }

    /// A step through the session (‹, Skip ›, Next album, a row picked), through the editor's gate: typed work asks
    /// first. A step refused leaves the album open selected.
    private func take(_ delta: Int, editor: EditAlbumModel) {
        guard model.session != nil, editor.canStep else {
            selected = current
            return
        }
        if editor.holdsWork {
            pending = .step(delta)
            askingDiscard = true
            return
        }
        model.go(by: delta, gate: editor.stepGate)
        selected = current
    }

    /// Show's facet, or Marked fine: while a session lasts, choosing ends it - asked about over typed work, and never
    /// while an apply runs or its follow-up read is out, nor while a step couldn't go (the album's write unsettled).
    private func choose(facet id: String?) {
        guard model.session != nil, let editor else {
            model.choose(facet: id)
            return
        }
        guard editor.canStep, !editor.applying, editor.following == 0 else { return }
        if editor.holdsWork {
            pending = .facet(id)
            askingDiscard = true
            return
        }
        model.choose(facet: id)
    }

    /// An opening asked for from elsewhere while the editor holds work - never while an apply runs or its follow-up read
    /// is out, nor over another question: asked once those end. Only by the page the editor is on.
    private func askAboutOpening() {
        guard navigation.macEditHost == .needsALook else { return }
        guard navigation.macEditAsked != nil, editor?.applying != true, (editor?.following ?? 0) == 0,
              !askingDiscard else { return }
        if editor?.holdsWork == true {
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
        case .step(let delta):
            // the gate as it is now: a write may have started since the step was asked
            if let editor { model.go(by: delta, gate: editor.stepGate) }
            selected = current
        case .facet(let id):
            model.choose(facet: id)
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
        case .step:
            selected = current
        case .opening:
            navigation.macEditAnswered(discard: false)
        case .facet, nil:
            break
        }
    }
}

/// Needs a look's left on the Mac (NeedsALook.dc.html's `.col`): its bar, the ladder, the list and the line under it -
/// a view of its own, so the rows are worked out from the scan here alone, never in the page's body, which an editor's
/// keystroke runs again.
private struct MacNeedsLookList: View {
    let model: NeedsLookModel
    @Binding var selected: String?
    let artistColumn: Bool
    let writing: Bool
    let choose: (String?) -> Void

    @Environment(Reachability.self) private var reachability
    @Environment(\.macRowSize) private var rowSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The columns, in the drawing's order.
    private enum Column {
        case album, artist, issues
    }

    var body: some View {
        let page = model.page
        VStack(alignment: .leading, spacing: 0) {
            MacToolbar {
                if model.state == .list {
                    tools
                }
            }
            notes(page)
            switch model.state {
            case .problem(let problem):
                Text(problem)
                    .foregroundStyle(DWPalette.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(MacNeedsLookLook.pad)
            case .reading:
                HStack(spacing: MacNeedsLookLook.gap) {
                    ProgressView().controlSize(.small)
                    Text(NeedsLook.reading)
                        .foregroundStyle(DWPalette.t2)
                }
                .accessibilityElement(children: .combine)
                .padding(MacNeedsLookLook.pad)
            case .failed:
                VStack(alignment: .leading, spacing: MacNeedsLookLook.gap) {
                    ErrorNote(text: model.failure ?? NeedsLook.readFailed)
                    tryAgain
                }
                .padding(MacNeedsLookLook.pad)
            case .list:
                list
            }
        }
        .font(Typeface.Mac.text(.base))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DWPalette.bg)
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        // out of reach, the list stays as last read under the amber line
        .editOutOfReach(!reachability.online && model.scan.loaded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NeedsLook.title)
    }

    private var tryAgain: some View {
        Button(NeedsLook.tryAgain) {
            model.retry()
        }
        .buttonStyle(DWButtonStyle(size: .small))
        .disabled(model.scan.reading || !reachability.online)
    }

    /// What the page says before its list: Edit albums missing (fixing needs it), and a mark that won't be kept.
    @ViewBuilder private func notes(_ page: Managing.NeedsLookPage) -> some View {
        if !page.canEdit {
            Text(NeedsLook.needsEdit)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MacNeedsLookLook.noteSide)
                .padding(.top, MacNeedsLookLook.gap)
        }
        if model.ignoresUnsaved {
            Text(NeedsLook.ignoresUnsavedWords)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.amberText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MacNeedsLookLook.noteSide)
                .padding(.top, MacNeedsLookLook.gap)
        }
    }

    // MARK: the bar

    /// Show, the pop-up and Marked fine · N - folded as the column narrows: Show's label first to go, then Marked fine
    /// into the pop-up's menu, then the pop-up's words to Show alone.
    private var tools: some View {
        let fine = NeedsLookPage.markedFine(model.chips)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: MacNeedsLookLook.toolGap) {
                Text(NeedsLook.show)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .accessibilityHidden(true)
                popUp(folded: false, words: shownWords)
                Spacer(minLength: 0)
                if let fine { markedFine(fine) }
            }
            HStack(spacing: MacNeedsLookLook.toolGap) {
                popUp(folded: false, words: shownWords)
                Spacer(minLength: 0)
                if let fine { markedFine(fine) }
            }
            HStack(spacing: MacNeedsLookLook.toolGap) {
                popUp(folded: true, words: shownWords)
                Spacer(minLength: 0)
            }
            HStack(spacing: MacNeedsLookLook.toolGap) {
                popUp(folded: true, words: NeedsLook.show)
                Spacer(minLength: 0)
            }
        }
    }

    /// The pop-up's words: the facet shown and how many albums it has ("Every issue · 3 albums").
    private var shownWords: String {
        model.pressedChip.map(NeedsLookPage.popUp) ?? NeedsLook.show
    }

    /// The facets, each with how many albums - folded, Marked fine among them, its button gone.
    private func popUp(folded: Bool, words: String) -> some View {
        let chips = folded ? model.chips : NeedsLookPage.strip(model.chips)
        return DWPopUp(words: words) {
            Picker(NeedsLook.show, selection: Binding<String?>(
                get: { model.pressed },
                set: { (picked: String?) -> Void in choose(picked) }
            )) {
                ForEach(chips, id: \.id) { (chip: NeedsLook.Facet) in
                    Text(NeedsLookPage.popUp(chip))
                        .accessibilityLabel(NeedsLookWords.facetSpoken(chip))
                        .tag(chip.id)
                }
            }
            .pickerStyle(.inline)
        }
        .accessibilityLabel(NeedsLook.show)
        .accessibilityValue(model.pressedChip.map(NeedsLookWords.facetSpoken) ?? "")
        .help(NeedsLookPage.popUpSpoken(model.pressedChip))
    }

    /// Marked fine · N: Marked fine shown - lit while it is, pressed again All.
    private func markedFine(_ fine: NeedsLook.Facet) -> some View {
        let on = NeedsLookPage.isMarkedFine(model.pressed)
        return Button(NeedsLookPage.markedFineWords(fine.count)) {
            choose(NeedsLookPage.markedFineTapped(model.pressed))
        }
        .buttonStyle(DWButtonStyle(kind: on ? .on : .normal))
        .accessibilityLabel(NeedsLookWords.facetSpoken(fine))
        .accessibilityAddTraits(on ? .isSelected : [])
        .fixedSize()
    }

    // MARK: the list

    @ViewBuilder private var list: some View {
        if model.status == .failed {
            HStack(alignment: .firstTextBaseline, spacing: MacNeedsLookLook.gap) {
                Text(model.failure ?? NeedsLook.checkFailed)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.redChipText)
                    .fixedSize(horizontal: false, vertical: true)
                tryAgain
            }
            .padding(.horizontal, MacNeedsLookLook.noteSide)
            .padding(.vertical, MacNeedsLookLook.gap)
        }
        let rows = model.rows
        if rows.isEmpty {
            Text(NeedsLook.nothing)
                .foregroundStyle(DWPalette.t2)
                .padding(MacNeedsLookLook.pad)
        } else {
            let columns = shownColumns
            let open = current
            MacColumnList(columns: columns.map(column), rows: rows,
                          voice: { (row: NeedsLook.DrawnRow) -> MacRowVoice in
                              MacRowVoice(label: NeedsLookWords.row(row, chips: chipWords(row), current: row.key == open),
                                          actions: [])
                          },
                          selected: $selected,
                          open: { (row: NeedsLook.DrawnRow) -> Void in selected = row.id },
                          menu: { (_: NeedsLook.DrawnRow) -> EmptyModifier in EmptyModifier() }
            ) { (row: NeedsLook.DrawnRow, at: Int) in
                if columns.indices.contains(at) { cell(row, columns[at]) }
            }
            .frame(maxHeight: .infinity)
            // rows held after a session until the read after it lands, out of reach, or while a write runs: off
            .disabled(model.ending != nil || !reachability.online || writing)
        }
        Text(NeedsLookPage.macLeaves)
            .font(Typeface.Mac.text(.label))
            .foregroundStyle(DWPalette.t3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MacNeedsLookLook.noteSide)
            .padding(.vertical, MacNeedsLookLook.notePad)
    }

    /// The album the session has open.
    private var current: String? {
        model.session?.current?.listed.path
    }

    private var shownColumns: [Column] {
        artistColumn ? [.album, .artist, .issues] : [.album, .issues]
    }

    private func column(_ column: Column) -> MacListColumn {
        switch column {
        case .album: return MacListColumn(title: EditWords.album, width: .flexible)
        case .artist: return MacListColumn(title: EditWords.artist, width: .fixed(MacNeedsLookLook.artistWidth))
        case .issues: return MacListColumn(title: NeedsLookPage.issuesColumn,
                                           width: .fixed(MacNeedsLookLook.issuesWidth))
        }
    }

    private func chips(_ row: NeedsLook.DrawnRow) -> [(words: String, kind: NeedsLookPage.ChipKind)] {
        NeedsLookPage.chips(row, pressed: model.pressed, issueTypes: model.issueTypes)
    }

    private func chipWords(_ row: NeedsLook.DrawnRow) -> [String] {
        chips(row).map(\.words)
    }

    @ViewBuilder private func cell(_ row: NeedsLook.DrawnRow, _ column: Column) -> some View {
        let album = row.album
        switch column {
        case .album:
            let chips = chips(row)
            let title = NeedsLook.title(album)
            HStack(spacing: MacNeedsLookLook.gap) {
                FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 80)
                    .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
                    .clipShape(DWCorners.chipShape)
                    .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                    .accessibilityHidden(true)
                // the title and every chip; else the first chip and how many more; else the title alone, cut
                ViewThatFits(in: .horizontal) {
                    titled(title, chips, shown: chips.count)
                    titled(title, chips, shown: 1)
                    Text(title)
                }
            }
            .opacity(row.mark == nil ? 1 : DWPalette.off)
            .help(NeedsLookPage.help(row, chips: chips.map(\.words)))
        case .artist:
            Text(album.artist)
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .help(album.artist)
        case .issues:
            let count = NeedsLookPage.issueCount(row)
            if count > 0 {
                Text("\(count)")
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
            }
        }
    }

    /// The title, then the first `shown` chips and how many more.
    private func titled(_ title: String, _ chips: [(words: String, kind: NeedsLookPage.ChipKind)],
                        shown: Int) -> some View {
        HStack(spacing: MacNeedsLookLook.gap) {
            Text(title)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: MacNeedsLookLook.chipGap) {
                ForEach(Array(chips.prefix(shown).enumerated()), id: \.offset) {
                    (_: Int, chip: (words: String, kind: NeedsLookPage.ChipKind)) in
                    DWChip(words: chip.words, tone: chip.kind.tone)
                }
                if let more = NeedsLookPage.more(chips.count, shown: shown) {
                    DWChip(words: more, tone: .caution)
                }
            }
        }
    }
}

/// (R12) Needs a look's sizes on the Mac, from NeedsALook.dc.html: the bar's gap (6), between a row's cover, title and
/// chips (8) and between its chips (4), the Artist (130) and Issues (62) columns, the room round the notes (16), the
/// line under the list's (12 by 10).
enum MacNeedsLookLook {
    static let toolGap: CGFloat = 6
    static let gap: CGFloat = 8
    static let chipGap: CGFloat = 4
    static let artistWidth: Double = 130
    static let issuesWidth: Double = 62
    static let pad: CGFloat = 16
    static let noteSide: CGFloat = 10
    static let notePad: CGFloat = 12
}
