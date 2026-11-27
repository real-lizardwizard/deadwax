import DeadwaxCore
import SwiftUI

/// What the store and the downloads already have of a pressing (Phase 6, slices 2 and 3 - phase6-get-requests.md 2.9,
/// 2.11; the web's app/StoreState.tsx): its box - the title (green for a pressing held), its lines, the last of several
/// the detail under them - and the notes under it (a part held, a part downloading, other pressings held). Under Get the
/// album, and in the Sources sheet where the sources would be. Every word is Core's (StoreLine, StoreWords). A path is a
/// stranger's folder name as often as not, so every line wraps rather than run off the screen. Nothing at all for
/// nothing to say.
///
/// (Slice 3) In the box, under its words:
/// - **Join this download**, under a download somebody else asked for (`joinJobId`), when the page gives `onJoin` -
///   without one, the box says nothing of joining (StoreLine.withoutJoin, as the web's StoreState). What a join leads to
///   is the page's: the Sources sheet hands over to Requests, the album page asks the store again.
/// - **Add to my library**, under a pressing the store holds that isn't yours (`add`), when the page gives `onAdd`.
///
/// Each asks deadwax in the tap; while it is out the button waits ("Joining…", faded, a second tap nothing), then gives
/// way to its words ("Joined - it's in your Requests.", "Added to your library."), said to VoiceOver too; a refusal is
/// said under it in a listener's words, and the button is there to try again. Each is keyed on what it acts on - Join
/// on the download, Add on the first folder - so another download's Join starts afresh, as the web's keys do.
///
/// (Slice 3's review) An answer that never came - the phone stopped waiting, or a proxy between gave up
/// (RequestOverlays.unanswered) - may have gone through, so it is never said as refused: the button says it may have
/// (StoreWords.joinUnanswered, addUnanswered), and stays for a second try, which deadwax takes harmlessly. While the
/// page says deadwax is out of reach (`live` false), both are off.
///
/// (R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)") Flat on the phone, as every page
/// it stands on now is: its words on the page's black in the look's colours, no grey box, Join and Add the look's flat
/// buttons.
///
/// (The panel review's R19 - notes/ios.md "The panel review, R19: Get, and old type left in redrawn pages
/// (2026-11-27)"; James chose it redrawn, 26 Nov) On the Mac Get.dc.html's box: the card's raised ground, the line's
/// edge, a box's corners (DWCorners' 5), its words in the look's type and colours, Join and Add the look's `.btn`. Every
/// word, what each button does and when it is off are as they were.
struct StoreLineView: View {
    let status: StoreStatus?
    let notes: [String]
    /// Join the download the box is about; returns once deadwax has it, throws its refusal. Nil: no Join.
    var onJoin: ((Int) async throws -> Void)?
    /// Add the pressing the box is about to your library; returns once deadwax has it. Nil: no Add.
    var onAdd: (() async throws -> Void)?
    /// (Slice 3's review) deadwax can be asked: false, Join and Add are off.
    var live = true

    var body: some View {
        if status != nil || !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let status {
                    // no Join to draw - no "Join it" either
                    box(onJoin == nil ? StoreLine.withoutJoin(status) : status)
                }
                ForEach(notes.indices, id: \.self) { (at: Int) in
                    Text(notes[at])
                        .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func box(_ status: StoreStatus) -> some View {
        if Platform.mac {
            // (R19) Get.dc.html's `.box`: the card's ground, the line's edge, a box's 5 corners
            inside(status)
                .fixedSize(horizontal: false, vertical: true)
                .padding(StoreLineLook.inside)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DWPalette.card, in: DWCorners.boxShape)
                .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
                .accessibilityElement(children: .contain)
        } else {
            // (R7) flat: its words on the page's own black
            inside(status)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
        }
    }

    private func inside(_ status: StoreStatus) -> some View {
        // (R19) the look's colours on both: the held title green, the rest the heading's (the Mac's) or white, the lines
        // the second colour, the detail the third
        let title: Color = Platform.mac ? DWPalette.head : DWPalette.text
        return VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row))
                    .fontWeight(.semibold)
                    .foregroundStyle(status.kind == .held ? DWPalette.greenText : title)
                ForEach(status.lines.indices, id: \.self) { (at: Int) in
                    // the folders (or the peer) first; the last of several the detail under them
                    Text(status.lines[at])
                        .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                        .foregroundStyle(at > 0 && at == status.lines.count - 1 ? DWPalette.t3 : DWPalette.t2)
                }
            }
            .accessibilityElement(children: .combine)
            if let jobId = status.joinJobId, let onJoin {
                StoreActionButton(words: .join, live: live) { try await onJoin(jobId) }
                    .id("join-\(jobId)")
            }
            if status.add, let onAdd {
                StoreActionButton(words: .add, live: live, act: onAdd)
                    .id("add-\(status.lines.first ?? "")")
            }
        }
    }
}

/// Join this download, or Add to my library (StoreState.tsx's JoinDownload and AddToLibrary): idle, waiting on deadwax,
/// then done - the done words in the button's place until the page's next look draws the box again.
private struct StoreActionButton: View {
    struct Words {
        let idle, busy, done, unanswered: String

        static let join = Words(idle: StoreWords.join, busy: StoreWords.joining, done: StoreWords.joined,
                                unanswered: StoreWords.joinUnanswered)
        static let add = Words(idle: StoreWords.add, busy: StoreWords.adding, done: StoreWords.added,
                               unanswered: StoreWords.addUnanswered)
    }

    private enum Phase { case idle, busy, done }

    let words: Words
    /// deadwax can be asked: false, the button is off.
    let live: Bool
    let act: () async throws -> Void

    @Environment(ServerModel.self) private var server
    @State private var phase = Phase.idle
    @State private var refused: (any Error)?
    /// (Slice 3's review) The last try got no answer in time: it may have gone through.
    @State private var unanswered = false

    var body: some View {
        if phase == .done {
            Text(words.done)
                .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // (R19) the look's button on both: the phone's flat accent words, the Mac's `.btn`
                Button(phase == .busy ? words.busy : words.idle, action: tap)
                    .buttonStyle(DWButtonStyle())
                    // waiting, it stays where it is and keeps VoiceOver's focus: faded, a second tap nothing
                    .opacity(phase == .busy ? DWPalette.off : 1)
                    // out of reach, off - unless already asked, whose answer is still coming
                    .disabled(!live && phase == .idle)
                if unanswered {
                    // not a refusal: it may have gone through
                    Text(words.unanswered)
                        .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let refused {
                    ErrorNote(refused)
                        .foregroundStyle(DWPalette.redChipText)
                }
            }
            .padding(.top, 8)
        }
    }

    private func tap() {
        guard phase == .idle, live else { return }
        phase = .busy
        refused = nil
        unanswered = false
        Task {
            do {
                try await act()
                phase = .done
                Notice.announce(words.done)
            } catch {
                phase = .idle
                guard !APIFailure.isCancellation(error) else { return }
                if RequestOverlays.unanswered(error) {
                    unanswered = true
                    Notice.announce(words.unanswered)
                } else {
                    refused = error
                    Notice.announce(ErrorWords.of(error, admin: server.access.seesDetail).said)
                }
            }
        }
    }
}

/// (R19) The store line's Mac box: its words in from its edge - Get.dc.html's boxes' 12 (the panel's column, a card's 10
/// and 12 about it).
enum StoreLineLook {
    static let inside: CGFloat = 12         // drawn: Get panel .col padding
}
