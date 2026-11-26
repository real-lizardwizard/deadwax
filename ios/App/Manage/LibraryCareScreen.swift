import DeadwaxCore
import SwiftUI

/// Settings > Manage > Library care (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; the web's
/// app/LibraryCare.tsx). (The redesign, slice R13 - notes/ios.md "The redesign, slice R13: Library care and the Event
/// log") Drawn flat, as iLibraryCare draws it: the large title, then its groups on the page's black, their rows on
/// hairlines - no List, no grey cells:
///
/// - the web's ladder first: LIBRARY_PATH's problem said plainly, Reading the library, a first read failed with Try
///   again;
/// - **Rescan** (Look after the library's): why it is there, Rescan the library with the scan's facts beside it in the
///   readout face, a read again that failed with Try again;
/// - **Covers, CD art and lyrics** (Edit albums'): Narrow to (a box - anywhere you type is one) and what the runs act on,
///   then a row for each - its name, how many albums its Get would take ("37 albums without CD art"), and Get · N; while
///   it runs, its meter and where it is ("4 of 14 · Post · Björk") with Stop. Under a row, what its last run did, or that
///   one run goes at a time; under the three, one album at a time and the screen kept on;
/// - **The collection** (logins on, Look after the library): In nobody's library and Flagged downloads, each with its
///   count, both pushing In nobody's library's page (HeldByNobodyScreen - there is no route of Flagged downloads' own).
///
/// The runs are the app's (CareRunModel, every decision Core's CareRuns): leaving the page doesn't stop one, and its
/// result stays; Stop ends a run after the album under way. Out of reach, what is drawn is how it was under the amber
/// line Edit album has, and nothing can be pressed until it is back and the library read again. Without either part it
/// says so and asks nothing; opened out of reach before anything was read, it says it needs deadwax. Nothing is read
/// under the sign-in over the app; once it goes, the page reads again. With Reduce Motion nothing slides; VoiceOver reads
/// each row once - its buttons its actions - and hears each run's result as it ends. The Mac draws its own page
/// (MacLibraryCarePage), the drawing's toolbar and boxes.
struct LibraryCareScreen: View {
    @Environment(CareRunModel.self) private var care
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The collection's counts: In nobody's library's answer, read as the page shows - its page's own model, the page
    /// reading its own again when it opens.
    @State private var held = HeldModel()
    @State private var visible = false

    var body: some View {
        let parts = care.parts
        Group {
            if !parts.shown {
                ContentUnavailableView {
                    Label(LibraryCare.title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if !reachability.online && !care.scan.loaded {
                ContentUnavailableView {
                    Label(LibraryCare.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                page(parts)
            }
        }
        .navigationTitle(LibraryCare.title)
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
        // the collection's counts: as the page shows (and back from In nobody's library), and as its part is given
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

    // MARK: the page

    @ViewBuilder private func page(_ parts: Managing.CareParts) -> some View {
        let online = reachability.online
        SettingsPage {
            switch care.state {
            case .problem(let problem):
                SettingsNote(words: problem, colour: DWPalette.amberText)
            case .reading:
                HStack(spacing: CareLook.gap) {
                    ProgressView()
                    Text(LibraryCare.reading)
                        .foregroundStyle(DWPalette.t2)
                }
                .font(Typeface.Phone.text(.small))
                .padding(.top, CareLook.noteAbove)
                .accessibilityElement(children: .combine)
            case .failed:
                VStack(alignment: .leading, spacing: CareLook.lines) {
                    ErrorNote(text: care.failure ?? LibraryCare.readFailed)
                    Button(LibraryCare.tryAgain) {
                        care.retry()
                    }
                    .buttonStyle(DWButtonStyle())
                    .disabled(care.scan.reading || care.runs.rescanning || !online)
                }
                .padding(.top, CareLook.noteAbove)
            case .list:
                if parts.rescan {
                    rescanSection(online: online)
                }
                if parts.bulk {
                    runsSection(parts, online: online)
                }
            }
            if care.heldShown {
                collection
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .editOutOfReach(!online && care.scan.loaded)
    }

    // MARK: Rescan

    private func rescanSection(online: Bool) -> some View {
        PhoneGroup(legend: LibraryCare.rescanTitle) {
            VStack(alignment: .leading, spacing: CareLook.lines) {
                Text(LibraryCare.rescanWords)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RescanRow(online: online)
                rereadFailure(online: online)
            }
            .padding(.vertical, CareLook.groupPad)
        }
    }

    /// A read again that failed over the scan on screen, with Try again - under Rescan, or under the runs for someone
    /// without Rescan.
    @ViewBuilder private func rereadFailure(online: Bool) -> some View {
        if care.failure != nil, care.scan.loaded {
            RereadFailure(online: online)
        }
    }

    // MARK: the runs

    private func runsSection(_ parts: Managing.CareParts, online: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PhoneGroup(legend: LibraryCare.runsTitle) {
                DWFieldRow(label: LibraryCare.narrowTo) {
                    DWField(prompt: LibraryCare.narrowPrompt, text: Binding(
                        get: { care.narrow },
                        set: { (typed: String) -> Void in care.narrow = typed }
                    ), spoken: LibraryCare.narrowTo)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                }
                VStack(alignment: .leading, spacing: CareLook.lines) {
                    Text(care.scopeNote)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !parts.rescan {
                        rereadFailure(online: online)
                    }
                }
                .padding(.vertical, CareLook.groupPad)
                .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                ForEach(BulkTargets.kinds, id: \.self) { (kind: BulkTargets.Kind) in
                    KindRow(kind: kind, online: online)
                }
            }
            SettingsNote(words: LibraryCare.runsNote, colour: DWPalette.t3)
        }
    }

    // MARK: the collection

    /// In nobody's library and Flagged downloads, each with its count once read, both to In nobody's library's page.
    private var collection: some View {
        let answer = held.answer
        return PhoneGroup(legend: LibraryCare.collection) {
            NavigationLink(value: AppRoute.heldByNobody) {
                CollectionRow(title: Held.title, count: answer?.count)
            }
            .buttonStyle(.plain)
            NavigationLink(value: AppRoute.heldByNobody) {
                CollectionRow(title: Held.flagged, count: answer?.flags.count)
            }
            .buttonStyle(.plain)
        }
    }
}

/// (R13's review) A read again that failed, with Try again beside it - under it at the accessibility sizes, across the
/// row, its words on up to three lines.
private struct RereadFailure: View {
    let online: Bool

    @Environment(CareRunModel.self) private var care
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CareLook.lines) {
                    said
                    tryAgain
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: CareLook.gap) {
                    said
                    tryAgain
                }
            }
        }
        .font(Typeface.Phone.text(.small))
    }

    private var said: some View {
        Text(care.failure ?? "")
            .foregroundStyle(DWPalette.redChipText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tryAgain: some View {
        Button {
            care.retry()
        } label: {
            CareButtonWords(words: LibraryCare.tryAgain)
        }
        .buttonStyle(DWButtonStyle(size: .small, fills: typeSize.isAccessibilitySize))
        .disabled(care.scan.reading || care.runs.rescanning || !online)
    }
}

/// Rescan the library, a flat button in the accent, and the scan's facts beside it on its first text baseline - the
/// readout face (`mono xs`), its age moving on while the page shows; under it at the accessibility sizes. (R13's review)
/// The drawing's short facts, "140 albums · 2 min ago" (LibraryCare.shortFacts) - the whole line, its tracks, size and
/// how long the scan took, is some 450 points in the readout face beside a button that leaves about 200, so it is what
/// VoiceOver reads.
private struct RescanRow: View {
    let online: Bool

    @Environment(CareRunModel.self) private var care
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: CareLook.lines) {
                button
                facts
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: CareLook.gap) {
                button
                facts
            }
        }
    }

    private var button: some View {
        Button {
            care.rescan()
        } label: {
            CareButtonWords(words: care.runs.rescanning ? LibraryCare.rescanning : LibraryCare.rescanLibrary)
        }
        .buttonStyle(DWButtonStyle(fills: typeSize.isAccessibilitySize))
        .disabled(!care.rescanOpen(online: online))
    }

    private var facts: some View {
        TimelineView(.periodic(from: .now, by: 30)) { (context: TimelineViewDefaultContext) in
            let now = context.date.timeIntervalSince1970 * 1000
            Text(LibraryCare.shortFacts(care.scan.albums, loaded: care.scan.loaded, scannedAt: care.scan.answer?.scannedAt,
                                        rescanning: care.runs.rescanning, now: now))
                .font(Typeface.Phone.mono(.extraSmall))
                .foregroundStyle(DWPalette.t3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(care.facts(now: now))
        }
    }
}

/// Covers, CD art or Lyrics (iLibraryCare's `.go`): its name; how many albums its Get would take - or, while it runs,
/// its meter and where it is; and Get · N (none to take, no button) or Stop. Under it what its last run did, or that one
/// run goes at a time. One VoiceOver element: its name and line, its Get or Stop its action in their whole words
/// (startLabel, stopLabel), what Get will do its hint. At the accessibility sizes its parts stack, the button across.
private struct KindRow: View {
    let kind: BulkTargets.Kind
    let online: Bool

    @Environment(CareRunModel.self) private var care
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let runs = care.runs
        let targets = care.targets(kind)
        let under = runs.under?.kind == kind ? runs.under : nil
        let line = under.map(LibraryCare.runLine) ?? LibraryCare.rowLine(kind, count: targets?.count)
        let result = runs.result(kind)
        let waiting = runs.under.map { (other: CareRuns.Under) -> String? in
            other.kind != kind && targets?.isEmpty == false ? LibraryCare.waiting(for: other.kind) : nil
        } ?? nil
        VStack(alignment: .leading, spacing: CareLook.lines) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CareLook.lines) {
                    name
                    standing(under: under, line: line)
                    button(under: under, targets: targets)
                }
            } else {
                HStack(alignment: .center, spacing: CareLook.gap) {
                    name
                    standing(under: under, line: line)
                    button(under: under, targets: targets)
                }
            }
            if let waiting {
                CareLine(words: waiting, colour: DWPalette.t3)
            }
            if !result.isEmpty {
                CareLine(words: result, colour: DWPalette.text, strong: true)
            }
        }
        .padding(.vertical, CareLook.rowPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookHeight(PhoneLook.goRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([LibraryCare.spokenRow(kind, line: line), waiting, result.isEmpty ? nil : result]
            .compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint(LibraryCare.note(kind, targets: targets, typed: runs.narrow))
        .accessibilityActions {
            if let stop = runs.stopLabel(kind) {
                if !runs.stopping(kind) {
                    Button(stop) { care.stop(kind) }
                }
            } else if let targets, !targets.isEmpty, care.startOpen(kind, online: online) {
                Button(LibraryCare.startLabel(kind, count: targets.count)) { care.start(kind) }
            }
        }
    }

    private var name: some View {
        Text(LibraryCare.heading(kind))
            .font(Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.text)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            // iLibraryCare's `width: 62px`, at least: the three lines start one under another
            .frame(minWidth: typeSize.isAccessibilitySize ? nil : CareLook.nameWidth, alignment: .leading)
    }

    /// The row's middle: how many albums Get would take - or the run's meter and where it is, the album out.
    @ViewBuilder private func standing(under: CareRuns.Under?, line: String) -> some View {
        if let under {
            VStack(alignment: .leading, spacing: CareLook.meterGap) {
                DWMeter(fraction: LibraryCare.runFraction(under.run))
                Text(line)
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(line)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Stop while it runs (Stopping… once pressed - the album under way finishes first), else Get · N.
    @ViewBuilder private func button(under: CareRuns.Under?, targets: [ScanAlbum]?) -> some View {
        let runs = care.runs
        let across = typeSize.isAccessibilitySize
        if under != nil {
            Button {
                care.stop(kind)
            } label: {
                CareButtonWords(words: LibraryCare.stopShort(stopping: runs.stopping(kind)))
            }
            .buttonStyle(DWButtonStyle(size: .small, fills: across))
            .disabled(runs.stopping(kind))
        } else if let targets, !targets.isEmpty {
            Button {
                care.start(kind)
            } label: {
                CareButtonWords(words: LibraryCare.getShort(count: targets.count))
            }
            .buttonStyle(DWButtonStyle(size: .small, fills: across))
            .disabled(!care.startOpen(kind, online: online))
        }
    }
}

/// A row of the collection (iLibraryCare's `.go`): its words, its count once read (the badge, hidden from VoiceOver -
/// the row's label says it), the chevron. One element, the link round it its button.
private struct CollectionRow: View {
    let title: String
    let count: Int?

    var body: some View {
        SettingsGo {
            Text(title)
        } value: {
            if let count, count > 0 {
                DWCount(count: "\(count)")
            }
        }
        .accessibilityLabel(Held.spokenRow(title, count: count))
    }
}

/// A line under a run's row: the small size, wrapping - its last run's result in the words' own colour, semibold.
struct CareLine: View {
    let words: String
    var colour: Color = DWPalette.t2
    var strong = false

    var body: some View {
        Text(words)
            .font(Typeface.Phone.text(.small).weight(strong ? .semibold : .regular))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A button's words on Library care's and In nobody's library's pages: one line, up to three at the accessibility sizes,
/// centred - the innermost limit is the one that holds, so the style's one line round the label never cuts them; the
/// caller lets the button fill the width there.
struct CareButtonWords: View {
    let words: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? CareLook.buttonLines : 1)
            .multilineTextAlignment(.center)
    }
}

/// (R13) Library care's, In nobody's library's and the event log's spacing on the phone, from iLibraryCare and
/// iEventLog: between a row's parts (`.f` gap 8), between its lines, a padded group's room (`.group.pad` 10), a row's
/// room above and below inside its 46, the meter over its line, the room above a note, a button's lines at the largest
/// sizes, a log line's room above (`padding: 9px 16px 10px`) and between its two lines (`gap: 3px`), and a run's name's
/// width (`width: 62px`).
enum CareLook {
    static let gap: CGFloat = 8
    static let lines: CGFloat = 6
    static let groupPad: CGFloat = 10
    static let rowPad: CGFloat = 8
    static let meterGap: CGFloat = 4
    static let noteAbove: CGFloat = 12
    static let buttonLines = 3
    static let logPad: CGFloat = 9
    static let logGap: CGFloat = 3
    static let nameWidth: CGFloat = 62
}
