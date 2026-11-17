import DeadwaxCore
import SwiftUI
import UIKit

/// Settings > Manage > Event log (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8; the web's app/EventLog.tsx):
/// what deadwax has said since it started - the last 500 lines - newest first, live. Under the bar, where the stream
/// stands ("Connecting…", "Live", "Lost the live feed - reconnecting…": one line, never a column of failures in the log);
/// then the web's line saying what the page is, and the lines - each its time, its level (errors in the danger red,
/// warnings amber, their words with them) and which part of deadwax said it, over its words. A long press offers Copy
/// (the phone's own: the web has none); Clear, in the bar, empties this view only.
///
/// Everything is the app's (EventLogModel, every decision Core's EventStream.Feed): the lines outlive the page, as the
/// web keeps them in its module, so coming back is the history joined by number - nothing twice, nothing cleared back.
/// The stream is held only while the page shows with the app in front. Without Settings and the log it says so and asks
/// nothing; opened out of reach before anything was heard, it says it needs deadwax; a history read that failed says so
/// with Try again, and the stream still says what happens from now. Gone out of reach, the lines are how they were under
/// the amber line Edit album has. With Reduce Motion new lines don't slide in; VoiceOver reads each line once, its words
/// first; at the largest text sizes a line's time, level and part stack over its words.
struct EventLogScreen: View {
    @Environment(EventLogModel.self) private var log
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let feed = log.feed
        // a ZStack, not a Group: the page's frame (its shows and hides) is on one view that stays as the branches swap -
        // on a Group it would go to each branch, and the swap would hide and show the page, and read again
        ZStack {
            if !log.allowed {
                ContentUnavailableView {
                    Label(EventLog.title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if !reachability.online && !feed.heard && feed.log.lines.isEmpty {
                ContentUnavailableView {
                    Label(EventLog.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                lines(feed)
            }
        }
        .navigationTitle(EventLog.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if log.allowed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(EventLog.clear) {
                        log.clear()
                    }
                    .disabled(feed.log.lines.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if log.allowed && (reachability.online || feed.heard || !feed.log.lines.isEmpty) {
                StreamLine(state: feed.stream)
            }
        }
        .editOutOfReach(log.allowed && !reachability.online && (feed.heard || !feed.log.lines.isEmpty))
        .onAppear { log.shows() }
        .onDisappear { log.hides() }
        // Settings and the log given (or taken) while the page is up: asked for now, or called off
        .onChange(of: log.allowed) { _, _ in
            log.recheck()
        }
    }

    @ViewBuilder private func lines(_ feed: EventStream.Feed) -> some View {
        List {
            Section {
                Text(EventLog.pageLine)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = feed.historyProblem {
                Problem(words: problem)
            } else if feed.step == .halted, let problem = feed.streamProblem {
                Problem(words: problem)
            }
            Section {
                if feed.reading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(EventLog.reading)
                            .foregroundStyle(Palette.quiet)
                    }
                    .accessibilityElement(children: .combine)
                } else if feed.log.lines.isEmpty {
                    Text(EventLog.empty(feed.log))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // keyed by the line's identity (its run and number as it came, and when it was taken), never its
                    // place: a line coming above leaves every row below the row it was
                    ForEach(feed.log.lines) { (line: EventLog.Line) in
                        LogRow(line: line)
                    }
                }
            }
        }
        .accessibilityLabel(EventLog.listLabel)
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
    }
}

/// Where the stream stands (the web's `.app-log-stream`), under the bar: its dot - grey connecting or not live, green
/// live, amber lost - and its words, amber while lost. Said by VoiceOver as it changes the way that matters
/// (EventLogModel), and read here as one.
private struct StreamLine: View {
    let state: EventLog.StreamState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Self.dot(state))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(EventLog.words(state))
                .foregroundStyle(state == .lost ? Palette.amber : Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Typeface.footnote)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
    }

    /// `.app-log-dot`: text-3, green-icon live, amber-icon lost.
    private static func dot(_ state: EventLog.StreamState) -> Color {
        switch state {
        case .live: return Palette.greenIcon
        case .lost: return Palette.amberIcon
        case .connecting, .stopped: return Palette.textTertiary
        }
    }
}

/// What went wrong over the lines - the history not read, or the stream refused - with Try again beside it.
private struct Problem: View {
    let words: String

    @Environment(EventLogModel.self) private var log
    @Environment(Reachability.self) private var reachability

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(words)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if log.feed.tryAgainShown {
                    Button(EventLog.tryAgain) {
                        log.tryAgain()
                    }
                    .buttonStyle(.borderless)
                    .font(Typeface.footnote.weight(.semibold))
                    .disabled(!reachability.online)
                }
            }
        }
    }
}

/// One line (the web's `.app-log-row`): its time (the data face), level and part on one line - stacked at the largest
/// text sizes - over its words, which wrap; errors' level and words in the danger red, warnings' amber. VoiceOver reads
/// it once, words first (EventLog.spoken); a long press - or VoiceOver's Copy action - copies it as drawn.
private struct LogRow: View {
    let line: EventLog.Line

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tone = Self.tone(EventLog.level(line.eventType))
        VStack(alignment: .leading, spacing: 3) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    time
                    level(tone)
                    part
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    time
                    level(tone)
                    part
                }
            }
            Text(line.eventContent)
                .font(Typeface.footnote)
                .foregroundStyle(tone ?? .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EventLog.spoken(line))
        .accessibilityAction(named: Text(EventLog.copy)) { copy() }
        .contextMenu {
            Button(EventLog.copy, systemImage: "doc.on.doc") { copy() }
        }
    }

    private var time: some View {
        Text(EventLog.time(line))
            .font(Typeface.mono(.caption))
            .foregroundStyle(Palette.textTertiary)
    }

    private func level(_ tone: Color?) -> some View {
        Text(line.eventType)
            .font(Typeface.caption.weight(.semibold))
            .foregroundStyle(tone ?? Palette.quiet)
    }

    private var part: some View {
        Text(line.src ?? "")
            .font(Typeface.caption)
            .foregroundStyle(Palette.quiet)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func copy() {
        UIPasteboard.general.string = EventLog.copyText(line)
    }

    /// levelOf: errors the danger text's red, warnings amber, the rest their own.
    private static func tone(_ level: EventLog.Level) -> Color? {
        switch level {
        case .error: return Palette.danger
        case .warning: return Palette.amber
        case .info: return nil
        }
    }
}
