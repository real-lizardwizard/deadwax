import DeadwaxCore
import SwiftUI
import UIKit

/// Settings > Manage > Event log (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8; the web's app/EventLog.tsx):
/// what deadwax has said since it started - the last 500 lines - newest first, live. (The redesign, slice R13 -
/// notes/ios.md "The redesign, slice R13: Library care and the Event log") Drawn flat, as iEventLog draws it:
///
/// - in the bar, where the stream stands as a chip ("Live", green; "Reconnecting…", amber; VoiceOver hears the line's
///   whole words), then Copy - every line shown, as drawn - and Clear, which empties this view only (its hint says so,
///   what the web's line under the bar said);
/// - the large title, then the level strip: Everything, Warnings (warnings and errors - never a strip that leaves an
///   error out) and Errors, each with how many lines it shows;
/// - the lines on hairlines, each its time (the readout face, the third colour), its level (errors red, warnings amber)
///   and which part of deadwax said it, in mono on one line - stacked at the largest text sizes - over its words. A long
///   press offers Copy of that one (the phone's own: the web has none).
///
/// Everything is the app's (EventLogModel, every decision Core's EventStream.Feed): the lines outlive the page, as the
/// web keeps them in its module, so coming back is the history joined by number - nothing twice, nothing cleared back,
/// under any level. The stream is held only while the page shows with the app in front. Without Settings and the log it
/// says so and asks nothing; opened out of reach before anything was heard, it says it needs deadwax; a history read
/// that failed says so with Try again, and the stream still says what happens from now. Gone out of reach, the lines are
/// how they were under the amber line Edit album has. With Reduce Motion new lines don't slide in; VoiceOver reads each
/// line once, its words first. The Mac draws its own page (MacEventLogPage): the drawing's toolbar, columns and
/// selection.
struct EventLogScreen: View {
    @Environment(EventLogModel.self) private var log
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The level strip's: every line, the warnings (and the errors), or the errors - this page's, for its life.
    @State private var level: EventLog.Shown = .everything

    /// Where the stream stands is worth saying: deadwax in reach, or something heard or held.
    private func live(_ feed: EventStream.Feed) -> Bool {
        reachability.online || feed.heard || !feed.log.lines.isEmpty
    }

    var body: some View {
        let feed = log.feed
        let shown = EventLog.shown(feed.log.lines, level)
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
                lines(feed, shown: shown)
            }
        }
        .navigationTitle(EventLog.title)
        .toolbar {
            if log.allowed {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // (R13's review) in the bar while it leaves Back, Copy and Clear their room; larger, under it
                    if live(feed) && LiveChip.inBar(typeSize) {
                        LiveChip(state: feed.stream)
                    }
                    Button(EventLog.copy) {
                        copy(shown)
                    }
                    .disabled(shown.isEmpty)
                    Button(EventLog.clear) {
                        log.clear()
                    }
                    .disabled(feed.log.lines.isEmpty)
                    .accessibilityHint(EventLog.clearHint)
                }
            }
        }
        .editOutOfReach(log.allowed && !reachability.online && (feed.heard || !feed.log.lines.isEmpty))
        .onAppear { log.shows() }
        .onDisappear { log.hides() }
        // Settings and the log given (or taken) while the page is up: asked for now, or called off
        .onChange(of: log.allowed) { _, _ in
            log.recheck()
        }
        // Now Playing over the page (a full-screen cover: the page stays shown under it) calls the stream off, as the
        // web's managingLive does; put away, it's rejoined from the last line held
        .onChange(of: navigation.nowPlayingShown) { _, _ in
            log.recheck()
        }
    }

    @ViewBuilder private func lines(_ feed: EventStream.Feed, shown: [EventLog.Line]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // (R13's review) the chip under the bar at the larger sizes, where the old line was (the lines are drawn
                // only while there is a stream to speak of: live(feed))
                if !LiveChip.inBar(typeSize) {
                    LiveChip(state: feed.stream)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, CGFloat(PhoneLook.bigSide))
                        .padding(.top, CareLook.lines)
                }
                PhoneStrip(options: EventLog.Shown.allCases, words: { (part: EventLog.Shown) -> String in
                    EventLog.stripWords(part, count: EventLog.count(feed.log.lines, part))
                }, shown: $level, spoken: EventLog.levels, said: { (part: EventLog.Shown) -> String in
                    EventLog.stripSaid(part, count: EventLog.count(feed.log.lines, part))
                })
                if let problem = feed.historyProblem {
                    Problem(words: problem)
                } else if feed.step == .halted, let problem = feed.streamProblem {
                    Problem(words: problem)
                }
                if feed.reading {
                    HStack(spacing: CareLook.gap) {
                        ProgressView()
                        Text(EventLog.reading)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .font(Typeface.Phone.text(.small))
                    .padding(.horizontal, CGFloat(PhoneLook.bigSide))
                    .padding(.top, CareLook.noteAbove)
                    .accessibilityElement(children: .combine)
                } else if shown.isEmpty {
                    Text(feed.log.lines.isEmpty ? EventLog.empty(feed.log) : EventLog.noneShown(level, find: ""))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, CGFloat(PhoneLook.bigSide))
                        .padding(.top, CareLook.noteAbove)
                } else {
                    // keyed by the line's identity (its run and number as it came, and when it was taken), never its
                    // place: a line coming above leaves every row below the row it was
                    ForEach(shown) { (line: EventLog.Line) in
                        LogRow(line: line)
                    }
                }
            }
        }
        // no label on the list itself (the web's aria-label): on a container that isn't an element of its own a label
        // can go to every row in it, over each line's own
        // Reduce Motion: a line coming in is drawn in place - disablesAnimations stops an `.animation` above adding one
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    /// Copy in the bar: every line shown, newest first as drawn - said once it is on the clipboard.
    private func copy(_ shown: [EventLog.Line]) {
        guard let text = EventLog.copyShown([], of: shown) else { return }
        UIPasteboard.general.string = text
        AccessibilityNotification.Announcement(EventLog.copied(shown.count)).post()
    }
}

/// Where the stream stands, as a chip (iEventLog's `.chip.green` "Live"): DWChip's - on the phone its dot and words, no
/// face - green live, amber while lost, plain connecting or not live; VoiceOver hears the whole line (EventLog.words),
/// "Lost the live feed - reconnecting…". Said as it changes the way that matters by EventLogModel. Shared with the Mac's
/// toolbar (MacEventLogPage), where the chip keeps its face.
///
/// (R13's review) It stops growing at xxxLarge as the bars do (plan 3.3, the tab bar's cap): grown with the accessibility
/// sizes, "Reconnecting…" was some 360 points wide and pushed Copy, Clear and Back out of reach. And it sits in the bar
/// only up to xLarge, where the widest (about 133 points) leaves Back, Copy and Clear their room on a 375 phone; larger
/// (148 at xxLarge, 164 capped), the page draws it under the bar, where the old line was. Held down in the bar, it shows
/// its words in the large content viewer, as the tab bar's items do.
struct LiveChip: View {
    let state: EventLog.StreamState

    /// The largest size the chip is drawn in the bar at.
    static let barsLargest = DynamicTypeSize.xLarge

    /// The chip is in the bar at `size` - else under it.
    static func inBar(_ size: DynamicTypeSize) -> Bool {
        size <= barsLargest
    }

    var body: some View {
        DWChip(words: EventLog.chipWords(state), tone: Self.tone(state))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EventLog.words(state))
            .accessibilityShowsLargeContentViewer {
                Text(EventLog.chipWords(state))
            }
    }

    static func tone(_ state: EventLog.StreamState) -> DWChip.Tone {
        switch state {
        case .live: return .good
        case .lost: return .caution
        case .connecting, .stopped: return .plain
        }
    }
}

/// What went wrong over the lines - the history not read, or the stream refused - with Try again beside it; (R13's
/// review) under it at the accessibility sizes, across the row, its words on up to three lines.
private struct Problem: View {
    let words: String

    @Environment(EventLogModel.self) private var log
    @Environment(Reachability.self) private var reachability
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
        .padding(.horizontal, CGFloat(PhoneLook.bigSide))
        .padding(.vertical, CareLook.logPad)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
    }

    private var said: some View {
        Text(words)
            .foregroundStyle(DWPalette.redChipText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tryAgain: some View {
        if log.feed.tryAgainShown {
            Button {
                log.tryAgain()
            } label: {
                CareButtonWords(words: EventLog.tryAgain)
            }
            .buttonStyle(DWButtonStyle(size: .small, fills: typeSize.isAccessibilitySize))
            .disabled(!reachability.online)
        }
    }
}

/// One line (iEventLog's row): its time, level and part in the readout face on one line - stacked at the largest text
/// sizes - over its words, which wrap; errors' level and words red, warnings' amber, on the row's hairline. VoiceOver
/// reads it once, words first (EventLog.spoken); a long press - or VoiceOver's Copy action - copies it as drawn.
private struct LogRow: View {
    let line: EventLog.Line

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tone = Self.tone(EventLog.level(line.eventType))
        VStack(alignment: .leading, spacing: CareLook.logGap) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    time
                    level(tone)
                    part
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: CareLook.gap) {
                    time
                    level(tone)
                    part
                }
            }
            Text(line.eventContent)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(tone ?? DWPalette.head)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // iEventLog: padding 9px 16px 10px, border-bottom 1px solid #1c1b22
        .padding(.horizontal, CGFloat(PhoneLook.bigSide))
        .padding(.top, CareLook.logPad)
        .padding(.bottom, CareLook.logPad + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EventLog.spoken(line))
        .accessibilityAction(named: Text(EventLog.copy)) { copy() }
        .contextMenu {
            Button(EventLog.copy, systemImage: "doc.on.doc") { copy() }
        }
    }

    private var time: some View {
        Text(EventLog.time(line))
            .font(Typeface.Phone.mono(.extraSmall))
            .foregroundStyle(DWPalette.t3)
    }

    private func level(_ tone: Color?) -> some View {
        Text(line.eventType)
            .font(Typeface.Phone.mono(.extraSmall))
            .foregroundStyle(tone ?? DWPalette.t2)
    }

    /// Which part said it: one line beside the time and level, cut short at its end - and at the largest text sizes,
    /// stacked on its own line, all of it, wrapping (nothing cut off).
    private var part: some View {
        Text(line.src ?? "")
            .font(Typeface.Phone.mono(.extraSmall))
            .foregroundStyle(DWPalette.t2)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }

    private func copy() {
        UIPasteboard.general.string = EventLog.copyText(line)
    }

    /// levelOf: errors the red chip's words, warnings amber, the rest their own.
    private static func tone(_ level: EventLog.Level) -> Color? {
        switch level {
        case .error: return DWPalette.redChipText
        case .warning: return DWPalette.amberText
        case .info: return nil
        }
    }
}
