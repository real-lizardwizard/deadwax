import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac app, slice 7 (notes/ios.md "The Mac app, slice 7: managing on a big screen"): the event log's lines selected
/// and copied with Edit > Copy (\u{2318}C), and what quitting does to a run under way. Save changes on \u{2318}S and Tab are
/// MacMenuTests', the sheet's size MacFrameTests'. Both devices: the iPhone says none of it.
@Suite struct MacManagingTests {
    static let utc = TimeZone(identifier: "UTC")!

    /// The log as the page holds it: these lines joined one by one as the stream brings them - newest first.
    static func log(_ lines: [LogLine]) -> EventLog.State {
        lines.reduce(EventLog.State()) { (state: EventLog.State, line: LogLine) -> EventLog.State in state.joining(line) }
    }

    static let lines = log([
        LogLine(eventType: "INFO", eventContent: "Scan started", src: "library", seq: 1, time: 1_795_000_000, boot: "b1"),
        LogLine(eventType: "WARNING", eventContent: "slskd is slow", src: "poller", seq: 2, time: 1_795_000_061, boot: "b1"),
        LogLine(eventType: "ERROR", eventContent: "Couldn't move it", seq: 3, time: 1_795_000_122, boot: "b1"),
        LogLine(eventType: "INFO", eventContent: "Filed", src: "organizer", seq: 4, boot: "b1"),
    ]).lines

    // MARK: Edit > Copy in the event log

    @Test func copyPutsTheLinesSelectedAsShownOneToALine() {
        let shown = Self.lines
        #expect(shown.map(\.seq) == [4, 3, 2, 1], "newest first, as the page draws them")
        // two chosen, in either order: as the page shows them, each as the row's own Copy puts it
        let picked: Set<EventLog.Line.ID> = [shown[3].id, shown[1].id]
        let copied = EventLog.copyText(picked, of: shown, in: Self.utc)
        #expect(copied == EventLog.copyText(shown[1], in: Self.utc) + "\n" + EventLog.copyText(shown[3], in: Self.utc))
        #expect(copied?.components(separatedBy: "\n").count == 2)
        // the line as drawn: its time, level, part and words - no part, no time, left out, never a gap
        #expect(EventLog.copyText(shown[1], in: Self.utc).hasSuffix("ERROR Couldn't move it"))
        #expect(EventLog.copyText([shown[0].id], of: shown, in: Self.utc) == "INFO organizer Filed")
        // one line: exactly what its right-click Copy puts
        for line in shown {
            #expect(EventLog.copyText([line.id], of: shown, in: Self.utc) == EventLog.copyText(line, in: Self.utc))
        }
        // every line (Select All): all four, in the page's order
        let all = EventLog.copyText(Set(shown.map(\.id)), of: shown, in: Self.utc)
        #expect(all == shown.map { EventLog.copyText($0, in: Self.utc) }.joined(separator: "\n"))
    }

    @Test func nothingSelectedThatsStillListedCopiesNothing() {
        let shown = Self.lines
        #expect(EventLog.copyText([], of: shown, in: Self.utc) == nil)
        // Clear empties the view: the selection names no line still there
        #expect(EventLog.copyText(Set(shown.map(\.id)), of: [], in: Self.utc) == nil)
        // a line gone (the oldest, past the 500 kept) is left out; the rest still copy
        let kept = Array(shown.prefix(3))
        #expect(EventLog.copyText([shown[3].id, shown[2].id], of: kept, in: Self.utc) == EventLog.copyText(shown[2], in: Self.utc))
        #expect(EventLog.copyText([shown[3].id], of: kept, in: Self.utc) == nil)
        // the same words from another run keep their own identity: one line, not two
        let again = Self.log([LogLine(eventType: "INFO", eventContent: "Filed", src: "organizer", seq: 4, boot: "b2")]).lines
        #expect(EventLog.copyText([again[0].id], of: shown, in: Self.utc) == nil)
    }

    // MARK: quitting with a run under way

    @Test func aRunSaysOnTheMacWhatQuittingDoes() {
        for kind in BulkTargets.kinds {
            #expect(LibraryCare.quitNote(.iPhone, kind: kind) == nil, "\(kind): the phone says nothing new")
            let mac = LibraryCare.quitNote(.mac, kind: kind)
            #expect(mac == "Quitting deadwax stops the run - open deadwax again, and \(LibraryCare.label(kind)) carries on.")
        }
        #expect(LibraryCare.quitNote(.mac, kind: .covers) == "Quitting deadwax stops the run - open deadwax again, and Get covers carries on.")
        #expect(LibraryCare.quitNote(.mac, kind: .lyrics)?.contains("Get lyrics carries on") == true)
        // Re-time saved lyrics: running it again is safe, as its other stops say
        #expect(RetimeRun.quitNote(.iPhone) == nil)
        #expect(RetimeRun.quitNote(.mac) == "Quitting deadwax stops it - open deadwax again, and running it again carries on.")
        #expect(RetimeRun.stopped(.sessionEnded)?.hasSuffix(", and running it again carries on.") == true)
        // the Mac's words: nothing of the phone's
        for word in BulkTargets.kinds.compactMap({ LibraryCare.quitNote(.mac, kind: $0) }) + [RetimeRun.quitNote(.mac)!] {
            #expect(word.range(of: #"(?i)\b(i?phones?|app switcher|background|screen|tap)\b"#, options: .regularExpression) == nil, "\(word)")
        }
    }
}
