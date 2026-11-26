import DeadwaxCore
import SwiftUI
import UIKit

/// The event log on the Mac (the redesign, slice R13 - EventLog.dc.html; notes/ios.md "The redesign, slice R13: Library
/// care and the Event log"): the sidebar's Event log, drawn as the Mac's own page over the very model the phone's is
/// (EventLogModel, every decision Core's EventStream.Feed).
///
/// - The toolbar: the levels (Everything | Warnings | Errors - Warnings is warnings and errors, never one that leaves an
///   error out), Find in the log (every word typed, in a line's words, its part or its level), then where the stream
///   stands as a chip (Live), Copy - the lines selected, or every line shown when none is - and Clear this view, which
///   empties this view only: deadwax keeps its lines, and nothing cleared comes back under any level. Narrower, the
///   levels fold into a pop-up and Find narrows; at the smallest, the chip goes (the status bar still says it).
/// - The columns (`.cols`): Time, Level, From, What happened - every line's in the readout face, its level a chip in its
///   tone, its words wrapping.
/// - The lines, newest first, selected as a Mac list's rows are - a click, ⌘-click, ⇧-click, Edit > Select All - and
///   Edit > Copy (⌘C) copies those selected, as shown (Platform's SelectingList and copiesSelection, slice 7's). Each row
///   View > Row Size's height at least, read once by VoiceOver, words first, its Copy an action. No right-click: the
///   page has no ••• menu, and Copy is in the toolbar.
/// - The status bar: the lines kept, the warnings and the errors, and where the stream stands, newest first.
///
/// Held only while the page shows with the app in front, as the phone's: shows, hides, rechecked as the permission
/// changes and as Now Playing covers it.
struct MacEventLogPage: View {
    @Environment(EventLogModel.self) private var log
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The lines selected: their identities, which stay the same lines as others come.
    @State private var selected: Set<EventLog.Line.ID> = []
    @State private var level: EventLog.Shown = .everything
    /// Find's words - the page's own.
    @State private var typed = ""

    var body: some View {
        let feed = log.feed
        let shown = EventLog.shown(feed.log.lines, level, find: typed)
        MacPage {
            if log.allowed {
                tools(feed, shown: shown)
            }
        } content: {
            // a ZStack, not a Group: the page's frame stays as the branches swap (the phone's, for the same reason)
            ZStack {
                if !log.allowed {
                    MacLogNote(words: EditWords.noPermission)
                } else if !reachability.online && !feed.heard && feed.log.lines.isEmpty {
                    MacLogNote(words: EditWords.needsDeadwax)
                } else {
                    lines(feed, shown: shown)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macStatus(status(feed))
        .editOutOfReach(log.allowed && !reachability.online && (feed.heard || !feed.log.lines.isEmpty))
        .onAppear { log.shows() }
        .onDisappear { log.hides() }
        // Settings and the log given (or taken) while the page is up: asked for now, or called off
        .onChange(of: log.allowed) { _, _ in
            log.recheck()
        }
        // Now Playing over the page calls the stream off; put away, it's rejoined from the last line held
        .onChange(of: navigation.nowPlayingShown) { _, _ in
            log.recheck()
        }
        // (R13's review) a line a level or Find hides, or that went (cleared, the oldest let go), is let go of: Copy and
        // Edit > Copy act on what is selected and shown, and nothing hidden comes back selected with Everything again
        .onChange(of: shown.map(\.id)) { _, ids in
            selected = EventLog.keptSelection(selected, shown: ids)
        }
    }

    private func status(_ feed: EventStream.Feed) -> MacStatusItems.Items {
        guard log.allowed else { return MacStatusItems.Items(leading: []) }
        let said = EventLog.status(feed.log.lines, stream: feed.stream)
        return MacStatusItems.Items(leading: said.leading, trailing: said.trailing)
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ feed: EventStream.Feed, shown: [EventLog.Line]) -> some View {
        let live = reachability.online || feed.heard || !feed.log.lines.isEmpty
        ViewThatFits(in: .horizontal) {
            // the drawing's
            HStack(spacing: 6) {
                DWSegmented(options: EventLog.Shown.allCases,
                            words: { (part: EventLog.Shown) -> String in EventLog.label(part) },
                            chosen: $level, spoken: EventLog.levels, large: true)
                find(width: MacLogLook.findWidth)
                Spacer(minLength: 8)
                if live { LiveChip(state: feed.stream) }
                copy(shown)
                clear(feed)
            }
            // narrower: the levels in a pop-up, Find narrower
            HStack(spacing: 6) {
                levelsMenu
                find(width: MacLogLook.narrowFindWidth)
                Spacer(minLength: 8)
                if live { LiveChip(state: feed.stream) }
                copy(shown)
                clear(feed)
            }
            // narrowest: the chip left to the status bar
            HStack(spacing: 6) {
                levelsMenu
                find(width: MacLogLook.leastFindWidth)
                Spacer(minLength: 8)
                copy(shown)
                clear(feed)
            }
        }
    }

    private var levelsMenu: some View {
        DWPopUp(words: EventLog.label(level)) {
            Picker(EventLog.levels, selection: $level) {
                ForEach(EventLog.Shown.allCases, id: \.self) { (part: EventLog.Shown) in
                    Text(EventLog.label(part)).tag(part)
                }
            }
            .pickerStyle(.inline)
        }
        .accessibilityLabel(EventLog.levels)
        .accessibilityValue(EventLog.label(level))
    }

    private func find(width: CGFloat) -> some View {
        DWField(prompt: EventLog.findPrompt, text: $typed)
            .frame(width: width)
    }

    /// Copy: the lines selected still shown, else every line shown - as drawn, newest first; said once copied.
    private func copy(_ shown: [EventLog.Line]) -> some View {
        Button(EventLog.copy) {
            let chosen = shown.contains { (line: EventLog.Line) -> Bool in selected.contains(line.id) }
            guard let text = EventLog.copyShown(selected, of: shown) else { return }
            UIPasteboard.general.string = text
            let count = chosen ? shown.filter { (line: EventLog.Line) -> Bool in selected.contains(line.id) }.count
                : shown.count
            AccessibilityNotification.Announcement(EventLog.copied(count)).post()
        }
        .buttonStyle(DWButtonStyle())
        .disabled(shown.isEmpty)
        .help(EventLog.copyHint)
    }

    /// Clear this view: this view only - deadwax keeps its lines, and new ones still come.
    private func clear(_ feed: EventStream.Feed) -> some View {
        Button(EventLog.clearView) {
            log.clear()
            selected = []
        }
        .buttonStyle(DWButtonStyle())
        .disabled(feed.log.lines.isEmpty)
        .help(EventLog.clearHint)
        .accessibilityHint(EventLog.clearHint)
    }

    // MARK: the lines

    @ViewBuilder private func lines(_ feed: EventStream.Feed, shown: [EventLog.Line]) -> some View {
        VStack(spacing: 0) {
            MacLogHeader()
            if let problem = feed.historyProblem {
                MacLogProblem(words: problem)
            } else if feed.step == .halted, let problem = feed.streamProblem {
                MacLogProblem(words: problem)
            }
            if feed.reading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(EventLog.reading)
                        .foregroundStyle(DWPalette.t2)
                }
                .font(Typeface.Mac.text(.base))
                .padding(MacLogLook.noteRoom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            } else if shown.isEmpty {
                Text(feed.log.lines.isEmpty ? EventLog.empty(feed.log) : EventLog.noneShown(level, find: typed))
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(MacLogLook.noteRoom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                SelectingList(selection: $selected) {
                    // keyed by the line's identity, never its place: a line coming above leaves every row below the
                    // row it was - and (R13's review) its stripe too (EventLog.striped: the line's own number)
                    ForEach(shown) { (line: EventLog.Line) in
                        MacLogRow(line: line, selected: selected.contains(line.id))
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(EventLog.striped(line) ? MacPalette.rowStripe : DWPalette.bg)
                            .tag(line.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                // Reduce Motion: a line coming in is drawn in place
                .transaction { (transaction: inout Transaction) -> Void in
                    if reduceMotion {
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                }
                // Edit > Copy and Select All: the lines selected, as shown, newest first
                .copiesSelection($selected, of: shown.map(\.id)) { (chosen: Set<EventLog.Line.ID>) -> String? in
                    EventLog.copyText(chosen, of: shown)
                }
            }
        }
    }
}

/// The columns' strip (`.cols`): Time, Level, From, What happened - MacColumnList's header, at the drawing's widths.
private struct MacLogHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(EventLog.columns.indices, id: \.self) { (index: Int) in
                MacLogCell(width: MacLogLook.widths[index]) {
                    Text(EventLog.columns[index])
                        .lineLimit(1)
                }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    if index < EventLog.columns.count - 1 {
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
    }
}

/// A column's cell: 10 in from its edges, its width or the room left.
private struct MacLogCell<Content: View>: View {
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One line (EventLog.dc.html's `.row`): its time, level (a chip in its tone), part and words, each in the readout face
/// on one first text baseline, the words wrapping - View > Row Size's height at least, the selection's fill and edge
/// when selected, on the row line's rule. VoiceOver reads it once, words first; Copy is its action.
private struct MacLogRow: View {
    let line: EventLog.Line
    let selected: Bool

    @Environment(\.macRowSize) private var rowSize

    var body: some View {
        let level = EventLog.level(line.eventType)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            MacLogCell(width: MacLogLook.widths[0]) {
                Text(EventLog.time(line))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
            }
            MacLogCell(width: MacLogLook.widths[1]) {
                DWChip(words: line.eventType, tone: Self.tone(level))
            }
            MacLogCell(width: MacLogLook.widths[2]) {
                // (R13's review) cut to its column: the whole part its help
                Text(line.src ?? "")
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(line.src ?? "")
            }
            MacLogCell(width: MacLogLook.widths[3]) {
                Text(line.eventContent)
                    .foregroundStyle(selected ? DWPalette.selt : Self.words(level))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Typeface.Mac.mono(.small))
        .padding(.vertical, MacLogLook.rowRoom)
        .frame(maxWidth: .infinity, minHeight: CGFloat(rowSize.rowHeight), alignment: .leading)
        .background {
            if selected {
                // .row.on: the selection's fill, its edge inset
                Rectangle()
                    .fill(DWPalette.selbg)
                    .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))
            }
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EventLog.spoken(line))
        .accessibilityAction(named: Text(EventLog.copy)) {
            UIPasteboard.general.string = EventLog.copyText(line)
        }
    }

    /// A level's chip: errors red, warnings amber, the rest plain.
    static func tone(_ level: EventLog.Level) -> DWChip.Tone {
        switch level {
        case .error: return .bad
        case .warning: return .caution
        case .info: return .plain
        }
    }

    /// A line's words: errors' and warnings' in their chips' colours, the rest the rows' own.
    static func words(_ level: EventLog.Level) -> Color {
        switch level {
        case .error: return DWPalette.redChipText
        case .warning: return DWPalette.amberText
        case .info: return DWPalette.head
        }
    }
}

/// What went wrong over the lines - the history not read, or the stream refused - with Try again beside it.
private struct MacLogProblem: View {
    let words: String

    @Environment(EventLogModel.self) private var log
    @Environment(Reachability.self) private var reachability

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(words)
                .foregroundStyle(DWPalette.redChipText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if log.feed.tryAgainShown {
                Button(EventLog.tryAgain) {
                    log.tryAgain()
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(!reachability.online)
            }
        }
        .font(Typeface.Mac.text(.small))
        .padding(.horizontal, MacLogLook.noteRoom)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
    }
}

/// What the page says in place of its lines - no permission, or out of reach before anything was heard.
private struct MacLogNote: View {
    let words: String

    var body: some View {
        Text(words)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(MacLogLook.noteRoom)
    }
}

/// (R13) The event log's sizes on the Mac, from EventLog.dc.html: the columns' widths (Time 92, Level 96 - the
/// drawing's 78 would cut the faced chip's WARNING, 73 wide - From 124, What happened the rest), Find's 260 and its
/// narrower widths, a row's room above and below its words, a note's room.
enum MacLogLook {
    static let widths: [CGFloat?] = [92, 96, 124, nil]
    static let findWidth: CGFloat = 260
    static let narrowFindWidth: CGFloat = 180
    static let leastFindWidth: CGFloat = 120
    static let rowRoom: CGFloat = 5
    static let noteRoom: CGFloat = 22
}
