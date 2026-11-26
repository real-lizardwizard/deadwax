import DeadwaxCore
import SwiftUI

/// Library care on the Mac (the redesign, slice R13 - LibraryCare.dc.html; notes/ios.md "The redesign, slice R13: Library
/// care and the Event log"): the sidebar's Library care, drawn as the Mac's own page - its toolbar, its boxes and its
/// status bar - over the very model the phone's page is drawn from (CareRunModel, every decision Core's CareRuns).
///
/// - The toolbar: Rescan the library, then a Get for each kind with how many albums it would take ("Get CD art · 37") -
///   the one running lit, saying where it is ("Getting covers · 4 of 14") - and, while a run goes, Stop after this album
///   at its end. Narrower, the three Gets fold into one pop-up (the lit one stays); narrower still, everything is one
///   pop-up, Library care ▾ - reachable at the smallest window and beside the side panel.
/// - The boxes, two columns where there is room, one under another where there isn't: Rescan (why, and the scan's facts
///   in the readout face, moving on); Covers, CD art and lyrics (Narrow to, what the runs act on, and a row for each -
///   its meter and the album out while it runs, with Stop after this album; else what Get would take, with Get), one
///   album at a time and what quitting does; and with logins on, In nobody's library (Album and Artist, the folder as
///   its help, Show all) and Flagged downloads (who asked, where it already was, Add for them and Dismiss) - the phone's
///   pushed page, here in its boxes.
/// - The status bar: the album folders the runs act on and what each kind would take - the counts the Gets carry - and
///   the run under way.
///
/// Every gate is the phone's: Rescan with Look after the library, the runs with Edit albums, the collection with logins on
/// as well; nothing pressed out of reach or before a read to trust; Stop lands after the album under way, never before
/// (CareRuns' `next`). The runs outlive the page. Rows are View > Row Size's height at least; a row's buttons are its
/// VoiceOver actions; nothing opens on a double-click and nothing is offered on a right-click (the page has no •••).
struct MacLibraryCarePage: View {
    @Environment(CareRunModel.self) private var care
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var held = HeldModel()
    @State private var visible = false

    var body: some View {
        let parts = care.parts
        // (R13's review) the scan narrowed once a render, each kind's targets and Start from it - for the status bar,
        // the toolbar's three ways and the rows alike
        let snapshot = LibraryCare.Snapshot(care.runs, care.scan.albums, allowed: parts.bulk, online: reachability.online)
        MacPage {
            if parts.shown {
                MacCareTools(online: reachability.online, snapshot: snapshot)
            }
        } content: {
            if !parts.shown {
                MacCareNote(words: EditWords.noPermission)
            } else if !reachability.online && !care.scan.loaded && held.answer == nil {
                MacCareNote(words: EditWords.needsDeadwax)
            } else {
                page(parts, snapshot: snapshot)
            }
        }
        .macStatus(status(snapshot))
        .onAppear {
            care.shows()
            visible = true
        }
        .onDisappear {
            care.hides()
            visible = false
        }
        // a part given while the page is up: read now
        .onChange(of: parts.shown) { _, shown in
            if shown { care.shows() }
        }
        // signed in again over the app: what failed under it is read again
        .onChange(of: server.signInOver == nil) { _, clear in
            if clear { care.sessionBack() }
            guard clear, visible, care.heldShown else { return }
            Task { await held.read() }
        }
        .task(id: care.heldShown) {
            held.attach(server: server, navigation: navigation, reachability: reachability)
            guard care.heldShown else { return }
            await held.read()
        }
        .onChange(of: reachability.online) { _, now in
            if !now {
                held.outOfReach()
            } else if visible, care.heldShown {
                Task { await held.read() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, visible, care.heldShown else { return }
            Task { await held.read() }
        }
    }

    /// The status bar's facts (LibraryCare.status): the folders, each kind's count, the run under way.
    private func status(_ snapshot: LibraryCare.Snapshot) -> MacStatusItems.Items {
        guard care.parts.shown else { return MacStatusItems.Items(leading: []) }
        let said = LibraryCare.status(folders: snapshot.all, inScope: snapshot.inScope, typed: care.runs.narrow,
                                      loaded: care.scan.loaded, counts: snapshot.counts, under: care.runs.under)
        return MacStatusItems.Items(leading: said.leading, trailing: said.trailing)
    }

    // MARK: the page

    @ViewBuilder private func page(_ parts: Managing.CareParts, snapshot: LibraryCare.Snapshot) -> some View {
        let online = reachability.online
        GeometryReader { (room: GeometryProxy) in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: MacCareLook.boxGap) {
                    ladder(online: online)
                    // two columns only where every row fits its column (MacCareLook.twoColumns), else one
                    if room.size.width >= MacCareLook.twoColumns && care.heldShown {
                        HStack(alignment: .top, spacing: MacCareLook.columnGap) {
                            left(parts, online: online, snapshot: snapshot)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            right(online: online)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        left(parts, online: online, snapshot: snapshot)
                        if care.heldShown {
                            right(online: online)
                        }
                    }
                }
                // .page.pad, padding-top 26px: room above the first box's legend
                .padding(EdgeInsets(top: MacCareLook.pageTop, leading: MacCareLook.pageSide,
                                    bottom: MacCareLook.pageSide, trailing: MacCareLook.pageSide))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .editOutOfReach(!online && care.scan.loaded)
    }

    /// The web's ladder over the boxes: LIBRARY_PATH's problem, Reading the library, a first read failed.
    @ViewBuilder private func ladder(online: Bool) -> some View {
        switch care.state {
        case .problem(let problem):
            Text(problem)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.amberText)
                .fixedSize(horizontal: false, vertical: true)
        case .reading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(LibraryCare.reading)
                    .foregroundStyle(DWPalette.t2)
            }
            .font(Typeface.Mac.text(.base))
            .accessibilityElement(children: .combine)
        case .failed:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ErrorNote(text: care.failure ?? LibraryCare.readFailed)
                    .font(Typeface.Mac.text(.base))
                Button(LibraryCare.tryAgain) {
                    care.retry()
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(care.scan.reading || care.runs.rescanning || !online)
            }
        case .list:
            EmptyView()
        }
    }

    /// Rescan, and the runs - while the library is read to show.
    @ViewBuilder private func left(_ parts: Managing.CareParts, online: Bool,
                                   snapshot: LibraryCare.Snapshot) -> some View {
        if care.state == .list {
            VStack(alignment: .leading, spacing: MacCareLook.boxGap) {
                if parts.rescan {
                    MacRescanBox(online: online)
                }
                if parts.bulk {
                    MacRunsBox(online: online, rescanShown: parts.rescan, snapshot: snapshot)
                }
            }
        }
    }

    /// The collection: In nobody's library and Flagged downloads.
    private func right(online: Bool) -> some View {
        MacHeldBoxes(model: held, online: online)
    }
}

// MARK: the toolbar

/// Library care's toolbar (LibraryCare.dc.html's `.bar`): Rescan the library, the groove, the three Gets (the running
/// one lit), Stop after this album at its end while a run goes - folded as the window narrows.
private struct MacCareTools: View {
    let online: Bool
    let snapshot: LibraryCare.Snapshot

    @Environment(CareRunModel.self) private var care

    var body: some View {
        let parts = care.parts
        ViewThatFits(in: .horizontal) {
            // the drawing's: every button
            HStack(spacing: 6) {
                if parts.rescan { rescan }
                if parts.rescan && parts.bulk { MacGroove() }
                if parts.bulk {
                    ForEach(BulkTargets.kinds, id: \.self) { (kind: BulkTargets.Kind) in
                        get(kind)
                    }
                }
                Spacer(minLength: 8)
                stop
            }
            // narrower: the Gets in one pop-up, the lit one beside it
            HStack(spacing: 6) {
                if parts.rescan { rescan }
                if parts.rescan && parts.bulk { MacGroove() }
                if parts.bulk {
                    if let under = care.runs.under {
                        lit(under.kind, under.run)
                    } else {
                        DWPopUp(words: LibraryCare.getMenu) {
                            ForEach(BulkTargets.kinds, id: \.self) { (kind: BulkTargets.Kind) in
                                getItem(kind)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                stop
            }
            // narrowest: everything the page does, in one pop-up
            HStack(spacing: 6) {
                DWPopUp(words: LibraryCare.menuLabel) {
                    if parts.rescan {
                        Button(care.runs.rescanning ? LibraryCare.rescanning : LibraryCare.rescanLibrary) {
                            care.rescan()
                        }
                        .disabled(!care.rescanOpen(online: online))
                    }
                    if parts.bulk {
                        Divider()
                        ForEach(BulkTargets.kinds, id: \.self) { (kind: BulkTargets.Kind) in
                            getItem(kind)
                        }
                        if let under = care.runs.under {
                            Divider()
                            Button(LibraryCare.toolbarStop(under.run, stopping: care.runs.stopping(under.kind))) {
                                care.stop(under.kind)
                            }
                            .disabled(care.runs.stopping(under.kind))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rescan: some View {
        Button(care.runs.rescanning ? LibraryCare.rescanning : LibraryCare.rescanLibrary) {
            care.rescan()
        }
        .buttonStyle(DWButtonStyle())
        .disabled(!care.rescanOpen(online: online))
        .help(LibraryCare.rescanWords)
    }

    /// A kind's Get - lit while its run goes, else Get with how many it would take (none to take, dimmed).
    @ViewBuilder private func get(_ kind: BulkTargets.Kind) -> some View {
        if let under = care.runs.under, under.kind == kind {
            lit(kind, under.run)
        } else {
            let targets = snapshot.targets(kind)
            Button(Self.getWords(kind, targets: targets)) {
                care.start(kind)
            }
            .buttonStyle(DWButtonStyle())
            .disabled(targets?.isEmpty != false || !snapshot.startOpen(kind))
            .help(Self.getHelp(kind, care: care, targets: targets))
        }
    }

    /// The running kind's button, lit (`.btn.on`), saying where the run is - it presses nothing: Stop ends the run.
    private func lit(_ kind: BulkTargets.Kind, _ run: BulkTargets.Run) -> some View {
        Button(LibraryCare.getting(kind, run)) {}
            .buttonStyle(DWButtonStyle(kind: .on))
            .allowsHitTesting(false)
            .accessibilityRemoveTraits(.isButton)
    }

    /// A kind's Get in a pop-up.
    private func getItem(_ kind: BulkTargets.Kind) -> some View {
        let targets = snapshot.targets(kind)
        return Button(Self.getWords(kind, targets: targets)) {
            care.start(kind)
        }
        .disabled(targets?.isEmpty != false || !snapshot.startOpen(kind))
    }

    /// Stop after this album, while a run goes: the album under way finishes first (Stopping after 4 of 14, once pressed).
    @ViewBuilder private var stop: some View {
        if let under = care.runs.under {
            Button(LibraryCare.toolbarStop(under.run, stopping: care.runs.stopping(under.kind))) {
                care.stop(under.kind)
            }
            .buttonStyle(DWButtonStyle())
            .disabled(care.runs.stopping(under.kind))
            .help(LibraryCare.stopLabel(under.run, stopping: care.runs.stopping(under.kind)))
        }
    }

    /// Get with its count - "Get CD art · 37" - or its name alone while there is none to say.
    static func getWords(_ kind: BulkTargets.Kind, targets: [ScanAlbum]?) -> String {
        guard let targets, !targets.isEmpty else { return LibraryCare.label(kind) }
        return LibraryCare.startLabel(kind, count: targets.count)
    }

    /// What a Get will do - or why it can't, while another run goes.
    @MainActor static func getHelp(_ kind: BulkTargets.Kind, care: CareRunModel, targets: [ScanAlbum]?) -> String {
        if let other = care.runs.under?.kind, other != kind { return LibraryCare.waiting(for: other) }
        return LibraryCare.note(kind, targets: targets, typed: care.runs.narrow)
    }
}

// MARK: Rescan

/// Rescan's box (`.group.onbg`): why it is there, the scan's facts as `.kv` - Last read, in the readout face, its age
/// moving on - and a read again that failed, with Try again.
private struct MacRescanBox: View {
    let online: Bool

    @Environment(CareRunModel.self) private var care

    var body: some View {
        MacGroupBox(legend: LibraryCare.rescanTitle, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LibraryCare.rescanWords)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LibraryCare.lastRead)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 30)) { (context: TimelineViewDefaultContext) in
                        Text(care.facts(now: context.date.timeIntervalSince1970 * 1000))
                            .font(Typeface.Mac.mono(.label))
                            .foregroundStyle(DWPalette.head)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityElement(children: .combine)
                MacRereadFailure(online: online)
            }
        }
    }
}

/// A read again that failed over the scan on screen, with Try again.
private struct MacRereadFailure: View {
    let online: Bool

    @Environment(CareRunModel.self) private var care

    var body: some View {
        if let failure = care.failure, care.scan.loaded {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(failure)
                    .foregroundStyle(DWPalette.redChipText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(LibraryCare.tryAgain) {
                    care.retry()
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(care.scan.reading || care.runs.rescanning || !online)
            }
            .font(Typeface.Mac.text(.small))
        }
    }
}

// MARK: the runs

/// Covers, CD art and lyrics' box: Narrow to and what the runs act on, a row for each kind, and under them one album at
/// a time - with, while a run goes, what quitting does.
private struct MacRunsBox: View {
    let online: Bool
    let rescanShown: Bool
    let snapshot: LibraryCare.Snapshot

    @Environment(CareRunModel.self) private var care

    var body: some View {
        MacGroupBox(legend: LibraryCare.runsTitle, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 10) {
                DWFieldRow(label: LibraryCare.narrowTo) {
                    DWField(prompt: LibraryCare.narrowPrompt, text: Binding(
                        get: { care.narrow },
                        set: { (typed: String) -> Void in care.narrow = typed }
                    ), spoken: LibraryCare.narrowTo)
                    .frame(maxWidth: MacCareLook.narrowWidth)
                }
                Text(LibraryCare.scopeNote(real: care.runs.real, inScope: snapshot.inScope, all: snapshot.all,
                                           typed: care.runs.narrow))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                if !rescanShown {
                    MacRereadFailure(online: online)
                }
                ForEach(BulkTargets.kinds, id: \.self) { (kind: BulkTargets.Kind) in
                    MacKindRow(kind: kind, online: online, snapshot: snapshot)
                }
                Text(LibraryCare.runsNote)
                    .font(Typeface.Mac.text(.label))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                // (the Mac app, slice 7) what ⌘Q does to a run - nothing keeps it going past a quit
                if let under = care.runs.under, let quit = LibraryCare.quitNote(Platform.device, kind: under.kind) {
                    Text(quit)
                        .font(Typeface.Mac.text(.label))
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A kind's row (LibraryCare.dc.html's `.f` in the runs' box): its name, 60 wide; while it runs its meter with the count
/// beside it and the album out under it, and Stop after this album; else what Get would take and Get with its count.
/// Under it its last run's result, or that one run goes at a time. One VoiceOver element: its name and line, its button
/// its action in the whole words.
private struct MacKindRow: View {
    let kind: BulkTargets.Kind
    let online: Bool
    let snapshot: LibraryCare.Snapshot

    @Environment(CareRunModel.self) private var care

    var body: some View {
        let runs = care.runs
        let targets = snapshot.targets(kind)
        let under = runs.under?.kind == kind ? runs.under : nil
        let line = under.map(LibraryCare.runLine) ?? LibraryCare.rowLine(kind, count: targets?.count)
        let result = runs.result(kind)
        let waiting = runs.under.map { (other: CareRuns.Under) -> String? in
            other.kind != kind && targets?.isEmpty == false ? LibraryCare.waiting(for: other.kind) : nil
        } ?? nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(LibraryCare.heading(kind))
                    .font(Typeface.Mac.text(.base).weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                    .frame(width: MacCareLook.nameWidth, alignment: .leading)
                standing(under: under, line: line)
                button(under: under, targets: targets)
            }
            if let waiting {
                Text(waiting)
                    .font(Typeface.Mac.text(.label))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.isEmpty {
                Text(result)
                    .font(Typeface.Mac.text(.small).weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([LibraryCare.spokenRow(kind, line: line), waiting, result.isEmpty ? nil : result]
            .compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint(LibraryCare.note(kind, targets: targets, typed: runs.narrow))
        .accessibilityActions {
            if let stop = runs.stopLabel(kind) {
                if !runs.stopping(kind) {
                    Button(stop) { care.stop(kind) }
                }
            } else if let targets, !targets.isEmpty, snapshot.startOpen(kind) {
                Button(LibraryCare.startLabel(kind, count: targets.count)) { care.start(kind) }
            }
        }
    }

    @ViewBuilder private func standing(under: CareRuns.Under?, line: String) -> some View {
        if let under {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    DWMeter(fraction: LibraryCare.runFraction(under.run))
                        .centredOnWords(CGFloat(Typeface.Mac.Size.label.rawValue))
                    Text(LibraryCare.runCount(under.run))
                        .font(Typeface.Mac.mono(.label))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize()
                }
                if let album = LibraryCare.runAlbum(under) {
                    // (R13's review) cut to the row: the whole name its help
                    Text(album)
                        .font(Typeface.Mac.text(.label))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(album)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(line)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func button(under: CareRuns.Under?, targets: [ScanAlbum]?) -> some View {
        let runs = care.runs
        if let under {
            Button(LibraryCare.toolbarStop(under.run, stopping: runs.stopping(kind))) {
                care.stop(kind)
            }
            .buttonStyle(DWButtonStyle(size: .small))
            .disabled(runs.stopping(kind))
        } else if let targets, !targets.isEmpty {
            Button(LibraryCare.startLabel(kind, count: targets.count)) {
                care.start(kind)
            }
            .buttonStyle(DWButtonStyle(size: .small))
            .disabled(!snapshot.startOpen(kind))
        }
    }
}

// MARK: the collection

/// In nobody's library and Flagged downloads, each its box with its table (`.box`, `.cols`, `.row`) - the phone's pushed
/// page (HeldByNobodyScreen), drawn here over the same model and its one write at a time.
private struct MacHeldBoxes: View {
    let model: HeldModel
    let online: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MacCareLook.boxGap) {
            MacGroupBox(legend: Held.title, ground: DWPalette.bg) {
                if let answer = model.answer {
                    VStack(alignment: .leading, spacing: 8) {
                        MacCareTable(columns: [Held.columnAlbum, Held.columnArtist],
                                     widths: [nil, MacCareLook.artistWidth]) {
                            ForEach(Array(Held.listedAlbums(answer.albums, all: model.all).enumerated()),
                                    id: \.element.id) { (at: Int, album: Held.UnheldAlbum) in
                                MacHeldAlbumRow(album: album, striped: at % 2 == 1)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Held.line(answer.count))
                                .font(Typeface.Mac.text(.label))
                                .foregroundStyle(DWPalette.t3)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if let more = Held.showLabel(all: model.all, count: answer.albums.count) {
                                Button(more) {
                                    model.all.toggle()
                                }
                                .buttonStyle(DWButtonStyle(size: .small))
                            }
                        }
                    }
                } else if let problem = model.problem {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ErrorNote(text: problem)
                            .font(Typeface.Mac.text(.small))
                        Button(LibraryCare.tryAgain) {
                            Task { await model.read() }
                        }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .disabled(model.reading || !online)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(Held.loading)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .font(Typeface.Mac.text(.small))
                    .accessibilityElement(children: .combine)
                }
            }
            if let answer = model.answer, !answer.flags.isEmpty {
                MacGroupBox(legend: Held.flagged, ground: DWPalette.bg) {
                    MacCareTable(columns: [Held.columnAlbum, Held.columnFlag, ""],
                                 widths: [nil, MacCareLook.flagWidth, MacCareLook.flagButtonsWidth]) {
                        ForEach(Array(answer.flags.enumerated()), id: \.element.id) { (at: Int, flag: Held.Flag) in
                            MacFlagRow(flag: flag, model: model, online: online, striped: at % 2 == 1)
                        }
                    }
                }
            }
            if model.answer != nil, let words = model.refused ?? model.problem {
                ErrorNote(text: words)
                    .font(Typeface.Mac.text(.small))
            }
        }
    }
}

/// A box's small table (`.box`, its `.cols` and rows): the header strip as MacColumnList draws it, then the rows on the
/// row line's rules, the box's edge round them. A width nil grows.
private struct MacCareTable<Rows: View>: View {
    let columns: [String]
    let widths: [CGFloat?]
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(columns.indices, id: \.self) { (index: Int) in
                    MacCareCell(width: widths[index]) {
                        Text(columns[index])
                            .lineLimit(1)
                    }
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if index < columns.count - 1 {
                            DWRule(colour: MacPalette.columnsRule, vertical: true)
                        }
                    }
                }
            }
            .font(Typeface.Mac.text(.label).weight(.semibold))
            .foregroundStyle(DWPalette.label)
            .frame(height: CGFloat(MacLook.headerHeight))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacPalette.columnsFace)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.frame) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // (R13's review) lazy, as the List it was: Show all can be hundreds of albums, inside the page's one scroll
            LazyVStack(spacing: 0) {
                rows
            }
        }
        .clipShape(DWCorners.boxShape)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
    }
}

/// A table's cell: 10 in from its edges (`.row > div: padding 0 10px`), its width or the room left - the Album's, never
/// under MacCareLook.albumLeast.
private struct MacCareCell<Content: View>: View {
    let width: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        if let width {
            content
                .padding(.horizontal, 10)
                .frame(width: width, alignment: .leading)
        } else {
            content
                .padding(.horizontal, 10)
                .frame(minWidth: MacCareLook.albumLeast, maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    /// A box table's row: View > Row Size's height at least (`least` where the drawing's is taller), the stripe on every
    /// other one, the row line's rule under it.
    fileprivate func macCareRow(_ rowSize: MacRowSize, striped: Bool, least: CGFloat = 0) -> some View {
        frame(maxWidth: .infinity, minHeight: max(CGFloat(rowSize.rowHeight), least), alignment: .leading)
            .background {
                if striped { MacPalette.rowStripe }
            }
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
    }
}

/// An album nobody has: the album alone under Album (its artist is the next column's - an untagged one is "Unknown
/// album"), its artist - each cut to its column, its whole words and the folder its help - read once.
private struct MacHeldAlbumRow: View {
    let album: Held.UnheldAlbum
    let striped: Bool

    @Environment(\.macRowSize) private var rowSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            MacCareCell(width: nil) {
                Text(Held.albumCell(album))
                    .foregroundStyle(DWPalette.head)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(Held.albumHelp(album))
            }
            MacCareCell(width: MacCareLook.artistWidth) {
                Text(album.artist)
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(album.artist)
            }
        }
        .font(Typeface.Mac.text(.base))
        .macCareRow(rowSize, striped: striped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Held.albumName(album)), \(album.path)")
    }
}

/// A flagged download (the drawing's 44 tall row): its name and who asked; where every file already was, short, in amber
/// (the whole sentence its help); Add for them and Dismiss - one write at a time, both off while it is read. One
/// VoiceOver element, its buttons its actions.
private struct MacFlagRow: View {
    let flag: Held.Flag
    let model: HeldModel
    let online: Bool
    let striped: Bool

    @Environment(\.macRowSize) private var rowSize

    var body: some View {
        let open = model.flow.open(online: online, reading: model.reading)
        HStack(alignment: .center, spacing: 0) {
            MacCareCell(width: nil) {
                VStack(alignment: .leading, spacing: 1) {
                    // (R13's review) each cut to the column: its whole words its help
                    Text(Held.flagName(flag))
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.head)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(Held.flagName(flag))
                    Text(Held.askedBy(flag))
                        .font(Typeface.Mac.text(.label))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(Held.askedBy(flag))
                }
            }
            MacCareCell(width: MacCareLook.flagWidth) {
                Text(Held.flagShort(flag))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.amberText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(Held.flagWords(flag))
            }
            MacCareCell(width: MacCareLook.flagButtonsWidth) {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button(Held.addForThem) {
                        model.act(flag, .add, online: online)
                    }
                    .buttonStyle(DWButtonStyle(kind: .pri, size: .small))
                    Button(Held.dismiss) {
                        model.act(flag, .dismiss, online: online)
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
                .disabled(!open)
            }
        }
        .macCareRow(rowSize, striped: striped, least: MacCareLook.flagRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Held.flagName(flag)), \(Held.askedBy(flag)), \(Held.flagWords(flag))")
        .accessibilityActions {
            if open {
                Button(Held.addForThem) { model.act(flag, .add, online: online) }
                Button(Held.dismiss) { model.act(flag, .dismiss, online: online) }
            }
        }
    }
}

// MARK: the page's own pieces

/// What the page says in place of its boxes - no permission, or out of reach before anything was read.
private struct MacCareNote: View {
    let words: String

    var body: some View {
        Text(words)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(MacCareLook.pageSide)
    }
}

/// (R13) Library care's sizes on the Mac, from LibraryCare.dc.html: the page's room (`.page.pad`, 26 above), its two
/// columns' gap (18) and the page they need - every row of a column in its column, Flagged downloads' the widest
/// (tests/test_ios_care_look.py adds it up), so the window as it opens has two and the smallest one - the window beside
/// a side panel - has one - the boxes' gap (22), a kind's name (60), Narrow to's field, and the tables' columns: the
/// Album's least, Artist 130, The flag, the flag's buttons - and a flag's row (44).
enum MacCareLook {
    static let pageSide: CGFloat = 22
    static let pageTop: CGFloat = 26
    static let columnGap: CGFloat = 18
    static let twoColumns: CGFloat = 1014
    static let boxGap: CGFloat = 22
    static let albumLeast: CGFloat = 120
    static let nameWidth: CGFloat = 60
    static let narrowWidth: CGFloat = 300
    static let artistWidth: CGFloat = 130
    static let flagWidth: CGFloat = 150
    static let flagButtonsWidth: CGFloat = 180
    static let flagRow: CGFloat = 44
}
