import DeadwaxCore
import SwiftUI

/// The album you don't have on the Mac (the redesign, slice R7 - Get.dc.html; notes/ios.md "The redesign, slice R7:
/// Search, Get and Sources (2026-11-25)"), drawn in GroupView's place by MacSearch.page(for:): GroupView keeps the page's
/// model and every load, store ask, pick and announcement, and hands this its actions (GroupDesk) - so the Mac draws and
/// does nothing the phone's page doesn't.
///
/// - The toolbar (.bar): **Get the album** (the accent's), the groove, Pressing and the chosen pressing's pop-up
///   (today's picker, as on the phone), how many pressings there are, then **Open artist** at its end when the credit
///   leads anywhere. Get the album opens Choose a source in the side panel's Sources tab, beside the page
///   (AppNavigation.getSources); the tab closes when this page leaves the front. Should it not fit (a long pressing
///   beside the side panel), it folds: Get the album, the pressing's pop-up and Open artist. The drawing's ‹ Search is
///   the window's own back; its Pin is left out (no pin on the Mac yet).
/// - The hero: the cover (132), the title (.h1), the credit in the accent - a link to its page - the meta line (the
///   maybe dashed), the chosen pressing's facts in the readout face, the maybe in words, GET_OFF without Get albums, and
///   the store line (Join and Add in its box) - or why there is no Get while deadwax can't be reached.
/// - The tracklist (MacColumnList): #, Title, Against the usual tracklist, Length - a disc's heading row above its first
///   track, what the pressing leaves out under a heading of its own. A track's mark (its chip and note) or "the same";
///   the song it was opened from in the accent, selected as it is drawn. Rows play nothing: the album isn't here yet.
///   The box as tall as its rows, scrolling inside once there isn't room, at View > Row Size's height.
/// - The status bar: the tracks, their minutes, and the pressing.
struct MacGetPage: View {
    let desk: GroupDesk

    /// (The Mac's Row Size) The rows' height, which the tracklist's box adds up as MacColumnList draws them.
    @Environment(\.macRowSize) private var rowSize
    /// The track row selected.
    @State private var selected: String?
    /// The page as tall as the window gives it, and the hero as drawn: what the box has left (`boxRoom`).
    @State private var pageTall: Double = 0
    @State private var heroTall: Double = 0

    /// The columns (Get.dc.html's .cols): Title takes what the others leave.
    static let columns: [MacListColumn] = zip([GetPageWords.number, GetPageWords.title, GetPageWords.againstUsual,
                                               GetPageWords.length], GetPageWords.widths).map {
        (title: String, width: MacTable.Width) -> MacListColumn in MacListColumn(title: title, width: width)
    }

    /// The drawing's numbers: the page 20 down and 22 in, the cover 132 and 18 from the words, the box 18 under.
    private enum Drawn {
        static let top: CGFloat = 20            // drawn: Get .page.pad padding-top
        static let side: CGFloat = 22           // drawn: Get .page.pad padding-left
        static let cover: CGFloat = 132         // drawn: Get .cover width
        static let coverGap: CGFloat = 18       // drawn: Get hero gap
        static let boxAbove: CGFloat = 18       // drawn: Get .box margin-top
        static let bottom: CGFloat = 16         // own: the page's foot, as an album's
        static let storeWidth: CGFloat = 520    // own: the store line's box, a readable width
    }

    /// One line of the tracklist: a track of the pressing, or one it leaves out.
    struct Line: Identifiable {
        let id: String
        let number: String
        let title: String
        let mark: PressingTrack.Mark?
        let length: String
        let song: Bool
        let left: Bool
    }

    /// The toolbar as drawn, or folded.
    private enum Fit {
        case full, folded
    }

    private var boxRoom: Double? {
        MacRowSize.boxRoom(page: pageTall, around: Double(Drawn.top + Drawn.bottom + Drawn.boxAbove) + heroTall)
    }

    var body: some View {
        let page = desk.page
        MacPage {
            ViewThatFits(in: .horizontal) {
                tools(.full)
                tools(.folded)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in
                        Double(frame.size.height)
                    } action: { (now: Double) -> Void in
                        heroTall = now
                    }
                below
                    .padding(.top, Drawn.boxAbove)
            }
            .padding(EdgeInsets(top: Drawn.top, leading: Drawn.side, bottom: Drawn.bottom, trailing: Drawn.side))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: Double.self) { (frame: GeometryProxy) -> Double in
                Double(frame.size.height)
            } action: { (now: Double) -> Void in
                pageTall = now
            }
        }
        .macStatus(MacStatusItems.Items(leading: GetPageWords.status(page.tracks,
                                                                      pressing: page.view?.chosen?.label ?? "")))
        // the song it was opened from, selected as its track is drawn - and so brought into view
        .onChange(of: page.tracks.first(where: \.song)?.key, initial: true) { (_: String?, key: String?) -> Void in
            if let key, selected == nil { selected = key }
        }
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ fit: Fit) -> some View {
        let page = desk.page
        HStack(spacing: 6) {
            if desk.canGet && desk.allowed && desk.online {
                Button(SourcesWords.getTheAlbum, action: desk.get)
                    .buttonStyle(DWButtonStyle(kind: .pri))
            }
            if let view = page.view {
                if fit == .full {
                    MacGroove()
                    Text(Pressings.picker)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                Button(action: desk.pick) {
                    HStack(spacing: 6) {
                        Text(view.chosen?.label ?? "")
                            .lineLimit(1)
                        DWCaret(colour: DWPalette.t2)
                    }
                }
                .buttonStyle(DWButtonStyle())
                .help(view.chosen?.facts ?? "")
                .accessibilityLabel("\(Pressings.picker), \(view.chosen?.label ?? "")")
                .accessibilityHint(view.chosen?.facts ?? "")
                if fit == .full, desk.pressings > 1 {
                    DWChip(words: GetPageWords.pressings(desk.pressings))
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
            if let artist = desk.artist {
                Button(GetPageWords.openArtist, action: artist)
                    .buttonStyle(DWButtonStyle())
                    .fixedSize()
            }
        }
    }

    // MARK: the hero

    private var hero: some View {
        let page = desk.page
        return HStack(alignment: .top, spacing: Drawn.coverGap) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: page.chosenId, group: desk.route.id),
                         size: ArchiveCoverSize.hero)
                .frame(width: Drawn.cover, height: Drawn.cover)
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(page.title)
                    .font(Typeface.Mac.text(.h1).weight(.bold))
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(2)
                    .help(page.title)
                    .accessibilityAddTraits(.isHeader)
                if !page.artist.isEmpty {
                    artistLine
                        .padding(.top, 4)
                }
                metaLine
                    .padding(.top, 4)
                if !page.facts.isEmpty {
                    Text(page.facts)
                        .font(Typeface.Mac.mono(.label))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
                lines
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The credit: a link to its page in the accent, else words in the second colour.
    @ViewBuilder private var artistLine: some View {
        let words = Text(desk.page.artist)
            .font(Typeface.Mac.text(.h3))
            .lineLimit(1)
        if let open = desk.artist {
            Button(action: open) {
                words.foregroundStyle(DWPalette.acc)
            }
            .buttonStyle(.plain)
            .help(desk.page.artist)
        } else {
            words.foregroundStyle(DWPalette.t2)
        }
    }

    /// "1997 · Album · not in your library" - or its first parts and a dashed "maybe in your library".
    @ViewBuilder private var metaLine: some View {
        let page = desk.page
        if page.maybe.isEmpty {
            Text(page.meta.isEmpty ? " " : page.meta)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .accessibilityHidden(page.meta.isEmpty)
        } else {
            HStack(spacing: 6) {
                if !page.meta.isEmpty {
                    Text(page.meta + " \u{00B7}")
                }
                Text(page.maybe)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(DWCorners.chipShape.strokeBorder(DWPalette.t2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .accessibilityElement(children: .combine)
        }
    }

    /// The words under the facts: the maybe, GET_OFF, then the store line - or, deadwax out of reach, why no Get.
    @ViewBuilder private var lines: some View {
        let page = desk.page
        if !page.maybeNote.isEmpty {
            note(page.maybeNote)
        }
        if desk.getOff {
            note(RequestWords.getOff)
        }
        switch desk.storeLine {
        case .line(let line):
            line
                .frame(maxWidth: Drawn.storeWidth, alignment: .leading)
                .padding(.top, 10)
        case .offline:
            note(StoreLine.offline)
        case .nothing:
            EmptyView()
        }
    }

    private func note(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    // MARK: the tracklist

    /// No tracklist yet: its trouble (Try again), its wait, why nothing was asked, or no pressings - else the summary
    /// against the usual tracklist over the box.
    @ViewBuilder private var below: some View {
        let model = desk.model
        if let trouble = model.trouble {
            GroupTrouble(trouble: trouble, reload: desk.reload)
        } else if model.answer == nil {
            if desk.online {
                ProgressView()
                    .accessibilityLabel(Pressings.loading)
            } else {
                Text(Pressings.offline)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.t2)
            }
        } else if (model.answer?.releases ?? []).isEmpty {
            Text(Pressings.none)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = desk.page.summary, !summary.text.isEmpty {
                    Text(summary.text)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(summary.differs ? DWPalette.amberText : DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                tracklist
                    .layoutPriority(1)
            }
        }
    }

    private var tracklist: some View {
        let page = desk.page
        var rows: [Line] = page.tracks.map { (track: PressingTrack) -> Line in
            Line(id: track.key, number: track.number, title: track.title, mark: track.mark, length: track.length,
                 song: track.song, left: false)
        }
        var drawn: [MacTable.Line<String>] = []
        for track in page.tracks {
            if let heading = track.heading { drawn.append(.group(heading)) }
            drawn.append(.row(track.key))
        }
        if !page.missing.isEmpty {
            drawn.append(.group(Pressings.notOnThisPressing))
            for (at, left) in page.missing.enumerated() {
                let id = "left|\(at)"
                rows.append(Line(id: id, number: "\u{2013}", title: left.title, mark: nil, length: left.length,
                                 song: false, left: true))
                drawn.append(.row(id))
            }
        }
        let headings = drawn.count - rows.count
        let tall = CGFloat(rowSize.boxHeight(rows: rows.count, headings: headings))
        let least = CGFloat(rowSize.boxLeast(rows: rows.count, headings: headings, room: boxRoom))
        return MacColumnList(columns: Self.columns, rows: rows, lines: drawn, selected: $selected,
                             open: { (_: Line) -> Void in },
                             menu: { (_: Line) -> EmptyModifier in EmptyModifier() }) { (line: Line, column: Int) in
            cell(line, column)
        }
        .frame(minHeight: least, maxHeight: tall)
        .clipShape(DWCorners.boxShape)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.frame, lineWidth: 1))
    }

    @ViewBuilder private func cell(_ line: Line, _ column: Int) -> some View {
        switch column {
        case 0:
            Text(line.number)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
                .accessibilityHidden(line.left)
        case 1:
            Text(line.title)
                .foregroundStyle(line.left ? DWPalette.t2 : line.song ? DWPalette.acc : DWPalette.head)
                .fontWeight(line.song ? .semibold : nil)
                .lineLimit(1)
                .help(line.title)
                .accessibilityLabel(line.song ? line.title + SongSearch.songWords : line.title)
        case 2:
            HStack(spacing: 6) {
                if let mark = line.mark {
                    DWChip(words: mark.chip, tone: .caution)
                        .fixedSize()
                }
                let against = GetPageWords.against(line.mark, compared: desk.compared && !line.left)
                Text(against)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(line.mark == nil ? DWPalette.t3 : DWPalette.t2)
                    .lineLimit(1)
                    .help(against)
            }
        default:
            Text(line.length)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        }
    }
}
