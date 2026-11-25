import DeadwaxCore
import SwiftUI

/// Requests on the Mac (the redesign, slice R8 - notes/ios.md "The redesign, slice R8: Requests"; Requests.dc.html): a
/// table of every download, under the toolbar's Search Soulseek and All | Active | Done, the status bar saying how many
/// there are and how fast they come.
///
/// - **The toolbar** (RequestTools): (with Get albums) "Search Soulseek", Artist and Album, and Search - the phone's
///   form's fields in the bar, Return in Artist moving to Album and Return in Album searching, Tab between them; Choose a
///   source opens over the page, as an album's Get does. Then All | Active | Done, and Clear done at the right. Where the
///   page is narrower it folds (the first that fits): the label goes and the fields narrow, then All | Active | Done and
///   Clear done become one pop-up - so every control is in reach from the smallest window up, and beside a side panel.
/// - **The table** (MacTable's rules, Core's RequestFilter, RequestColumns and RequestAction): Album, Artist, From,
///   Progress, Speed and the row's buttons, grouped Downloading, Waiting, Needs attention and Done - each heading only
///   over rows. Progress is a download's meter and its files, a place in the queue, why it stopped (in red), or how it
///   ended in a chip's few words (the whole sentence its help, and what VoiceOver hears) and when; nothing in it draws
///   past its cell. Speed is the rate as measured here, a dash for none. A click selects a row; ↑ ↓ Home End move the
///   selection; a double click or Return opens one done. In a window as it first opens the table fits its page. (The
///   Mac's Row Size) Its rows are View > Row Size's - Small its drawing's 34 with a 22 cover, Medium and Large every
///   list's 40 with 28 and 52 with 40 (MacRowSize.requestRowHeight and requestCover) - the meter as it is, centred;
///   the album's least grows with the cover (RequestColumns.albumLeast(_:)), so its title keeps its room.
/// - **The buttons** (RequestAction.buttons): a row's main one - Cancel (asking first with Confirm before cancelling on,
///   as the phone's ✕ does, and then cancelling only the row as it is by then), Another source - and a done row's Play
///   (its album from the first song, in the click, when its songs are in hand, else Open's) and Open. A refused row's
///   Same source again is its •••; every row's actions are its right-click too.
/// - **A row is one element for VoiceOver**: everything it shows, who asked and which try included
///   (RequestSpoken.row), its actions named as its buttons are.
/// - **The status bar**: "1 downloading", "2 waiting", "1 needs attention", "3 done", and the speed summed.
/// - The edges as the phone has them: deadwax out of reach, a look that failed (the rows below as last answered),
///   downloads not kept track of, nothing yet.
///
/// Left out: Other sources on a download's row (James: "just leave it out") and the drawing's Files, Other sources and
/// Log tabs (no route gives what they show); "slskd connected" (nothing says it); a done row's speed (deadwax doesn't
/// keep one).
struct MacRequestsPage: View {
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(PlayerModel.self) private var player
    /// (The Mac's Row Size) The rows' height and their cover, and the album's least - View > Row Size's.
    @Environment(\.macRowSize) private var rowSize

    @State private var filter: RequestFilter = .all
    @State private var selected: String?
    /// The row whose Cancel is asking first - kept as the board has it now (RequestFilter.cancellable), and let go
    /// once it can't be cancelled any more.
    @State private var confirming: RequestRow?
    @State private var artist = ""
    @State private var album = ""
    /// Choose a source, open over the page for the words in the toolbar.
    @State private var getting: GetRequest?
    @State private var searches = 0
    /// The toolbar's field with the cursor.
    @FocusState private var focused: Field?
    /// The table has the keyboard: ↑ ↓ Home End and Return are its.
    @FocusState private var tableFocused: Bool

    private enum Field: Hashable {
        case artist, album
    }

    /// The fields in the order the toolbar draws them: Tab's.
    private static let order: [Field] = [.artist, .album]

    var body: some View {
        let board = requests.board
        MacPage {
            tools(board)
        } content: {
            content(board)
        }
        .macStatus(MacStatusItems.Items(leading: reachability.online ? RequestFilter.status(board) : []))
        // the sheet let go - closed, or a Get asked for: its search goes as the dismissal begins
        .appSheet(item: Binding(get: { getting }, set: { (next: GetRequest?) in
            if next == nil { getting?.search.close() }
            getting = next
        })) { (request: GetRequest) in
            SourcesSheet(request: request) {
                // only while the sheet still shows this search: the download is in the table already
                guard getting?.id == request.id else { return }
                getting = nil
            }
            .macSheet()
        }
        .confirmationDialog(confirming?.cancelWords.question ?? "",
                            isPresented: Binding(get: { confirming != nil }, set: { (up: Bool) -> Void in
                                if !up { confirming = nil }
                            }), titleVisibility: .visible, presenting: confirming) { (row: RequestRow) in
            Button(row.cancelWords.action, role: .destructive) { confirmed(row.key) }
            Button(RequestWords.keepIt, role: .cancel) {}
                .returnCancels()
        }
        .onChange(of: board) { (_: RequestsView, now: RequestsView) -> Void in
            selected = MacTable.kept(selected, in: MacTable.rows(filter.lines(now)))
            // a question asked over a row that has moved on since (being filed, filed, gone) goes with it
            if let asked = confirming {
                confirming = RequestFilter.cancellable(asked.key, in: now)
            }
        }
        .onChange(of: filter) { (_: RequestFilter, now: RequestFilter) -> Void in
            // a selection the filter hides is let go, so Return never opens a row out of sight
            selected = MacTable.kept(selected, in: MacTable.rows(now.lines(requests.board)))
        }
    }

    // MARK: the toolbar

    /// The toolbar as drawn where it fits, then narrower, then folded (RequestTools).
    private func tools(_ board: RequestsView) -> some View {
        ViewThatFits(in: .horizontal) {
            toolbar(board, .full)
            toolbar(board, .compact)
            toolbar(board, .folded)
        }
    }

    private func toolbar(_ board: RequestsView, _ fit: RequestTools.Fit) -> some View {
        HStack(spacing: 6) {
            if server.access.can(.request) {
                if RequestTools.labelled(fit) {
                    Text(ManualSearch.title)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                field(ManualSearch.artistField, text: $artist, .artist, width: RequestTools.artistField(fit))
                field(ManualSearch.albumField, text: $album, .album, width: RequestTools.albumField(fit))
                Button(ManualSearch.search) { search() }
                    .buttonStyle(DWButtonStyle())
                    .disabled(!searchable)
                    .accessibilityLabel(ManualSearch.title)
                if !RequestTools.folds(fit) {
                    MacGroove()
                }
            }
            if RequestTools.folds(fit) {
                Spacer(minLength: 0)
                shownMenu(board)
            } else {
                DWSegmented(options: RequestFilter.allCases, words: { (option: RequestFilter) -> String in option.label },
                            chosen: $filter, spoken: RequestFilter.spoken, large: true)
                Spacer(minLength: 0)
                Button(RequestWords.clearDone) { clear() }
                    .buttonStyle(DWButtonStyle())
                    .disabled(!clearable(board))
            }
        }
    }

    /// A search field in its well (DWField's look), with the toolbar's own cursor: Return in Artist moves to Album, Return
    /// in Album searches, and Tab goes between them.
    private func field(_ prompt: String, text: Binding<String>, _ which: Field, width: Double) -> some View {
        TextField(prompt, text: text, prompt: Text(prompt).foregroundStyle(DWPalette.t3))
            .textFieldStyle(.plain)
            .font(Typeface.Look.text(.field))
            .foregroundStyle(DWPalette.fieldText)
            .autocorrectionDisabled()
            .focused($focused, equals: which)
            .tabs($focused, in: Self.order)
            .focusEffectDisabled()
            .onSubmit { submitted(which) }
            // .in: padding 0 8px
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background {
                DWWell(focused: focused == which)
                    .contentShape(DWTarget(face: DWCorners.buttonShape))
                    .onTapGesture { focused = which }
            }
            .frame(width: CGFloat(width))
    }

    /// The folded toolbar's pop-up, named for what the table shows: All, Active or Done, and Clear done under them.
    private func shownMenu(_ board: RequestsView) -> some View {
        DWPopUp(words: filter.label) {
            Picker(RequestFilter.spoken, selection: $filter) {
                ForEach(RequestFilter.allCases, id: \.self) { (option: RequestFilter) in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(RequestWords.clearDone) { clear() }
                .disabled(!clearable(board))
        }
        .accessibilityLabel(RequestFilter.spoken)
        .accessibilityValue(filter.label)
    }

    private func submitted(_ which: Field) {
        if which == .artist {
            focused = .album
        } else {
            search()
        }
    }

    private func clearable(_ board: RequestsView) -> Bool {
        board.clearable && reachability.online
    }

    private func clear() {
        confirming = nil
        requests.clear()
    }

    private var searchable: Bool {
        reachability.online && ManualSearch.canSearch(artist: artist, album: album)
    }

    /// Search: the words as typed, a new search each time - the Get is a card's, never the toolbar's.
    private func search() {
        guard searchable, getting == nil else { return }
        searches += 1
        getting = GetRequest(id: searches, release: GetRelease.manual(artist: artist, album: album),
                             subtitle: ManualSearch.subtitle, search: SourcesSearch())
    }

    // MARK: the page

    @ViewBuilder private func content(_ board: RequestsView) -> some View {
        if !reachability.online {
            note(RequestWords.offline)
        } else if !requests.trackingEnabled {
            notice(RequestWords.untracked,
                   line: server.access.seesDetail ? RequestWords.untrackedRuns : RequestWords.untrackedText)
        } else if board.empty && !requests.answered {
            ProgressView()
                .padding(20)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(AlbumPageLines.loading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let failure = requests.failure {
                    unreached(failure, empty: board.empty)
                }
                if board.empty {
                    if requests.failure == nil {
                        notice(RequestWords.nothingYet,
                               line: RequestWords.emptyLine(gets: server.access.can(.request), device: Platform.device))
                    }
                } else {
                    table(board)
                }
            }
        }
    }

    private func note(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
    }

    private func notice(_ title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typeface.Mac.text(.h3).weight(.semibold))
                .foregroundStyle(DWPalette.head)
            Text(line)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
    }

    /// A look that failed: what went wrong in a listener's words, the rows under it as the last answer had them.
    private func unreached(_ failure: any Error, empty: Bool) -> some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, service: .downloads)
        return VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.unreached)
                .font(Typeface.Mac.text(.h3).weight(.semibold))
                .foregroundStyle(DWPalette.head)
            ErrorNote(text: line.text, detail: line.detail)
            Text(RequestWords.keepsAsking(empty: empty))
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
    }

    // MARK: the table

    private func table(_ board: RequestsView) -> some View {
        let lines = filter.lines(board)
        let stripes = MacTable.stripes(lines)
        let rows = Self.byKey(board)
        let keys = MacTable.rows(lines)
        return GeometryReader { (page: GeometryProxy) in
            let total = Double(page.size.width)
            let widths = RequestColumns.widths(total, size: rowSize).map { CGFloat($0) }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header(widths)
                    if lines.isEmpty {
                        note(filter.nothing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ScrollViewReader { (proxy: ScrollViewProxy) in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(lines.enumerated()), id: \.element) {
                                    (index: Int, line: MacTable.Line<String>) in
                                    switch line {
                                    case .group(let title):
                                        groupLine(title)
                                    case .row(let key):
                                        if let row = rows[key] {
                                            rowLine(row, widths: widths, striped: stripes[index])
                                        }
                                    }
                                }
                            }
                        }
                        .onChange(of: selected) { (_: String?, now: String?) -> Void in
                            // a row the keys moved to, brought into view
                            if let now { proxy.scrollTo(MacTable.Line<String>.row(now)) }
                        }
                        // (the Mac's Row Size, after review) and the row selected, brought back into view as the rows
                        // grow or shrink under it
                        .onChange(of: rowSize) { (_: MacRowSize, _: MacRowSize) -> Void in
                            if let selected { proxy.scrollTo(MacTable.Line<String>.row(selected)) }
                        }
                    }
                }
                .frame(width: CGFloat(RequestColumns.width(total, size: rowSize)), height: page.size.height)
            }
            .scrollDisabled(RequestColumns.width(total, size: rowSize) <= total)
        }
        // the table takes the keyboard once a row is clicked: ↑ ↓ Home End move the selection, Return opens a done row
        .focusable()
        .focused($tableFocused)
        .focusEffectDisabled()
        .listKeys { (key: ListKey) -> KeyPress.Result in pressed(key, rows: keys, board: board) }
    }

    /// A key on the table: a move through its rows (MacTable.moved), or Return opening the row selected
    /// (MacTable.returned) as a double click does - a done row's album.
    private func pressed(_ key: ListKey, rows: [String], board: RequestsView) -> KeyPress.Result {
        let move: MacTable.Key
        switch key {
        case .up: move = .up
        case .down: move = .down
        case .home: move = .home
        case .end: move = .end
        case .open:
            guard let opened = MacTable.returned(selected, in: rows), let row = Self.byKey(board)[opened],
                  row.opens != nil else { return .ignored }
            requests.open(row)
            return .handled
        }
        guard !rows.isEmpty else { return .ignored }
        selected = MacTable.moved(selected, move, in: rows)
        return .handled
    }

    /// Every row on the board by its key.
    private static func byKey(_ board: RequestsView) -> [String: RequestRow] {
        let all = RequestSection.allCases.flatMap { (section: RequestSection) -> [RequestRow] in board.rows(section) }
        return Dictionary(all.map { (row: RequestRow) -> (String, RequestRow) in (row.key, row) },
                          uniquingKeysWith: { (first: RequestRow, _: RequestRow) -> RequestRow in first })
    }

    /// The columns' strip (.cols): its gradient, the frame's rule under it, each heading 10 in with a rule after it.
    private func header(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(RequestColumns.Column.allCases.enumerated()), id: \.element) {
                (index: Int, column: RequestColumns.Column) in
                Text(RequestColumns.title(column))
                    .font(Typeface.Mac.text(.label).weight(.semibold))
                    .foregroundStyle(DWPalette.label)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(width: widths[index], alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if index < widths.count - 1 {
                            DWRule(colour: MacPalette.columnsRule, vertical: true)
                        }
                    }
            }
        }
        .frame(height: CGFloat(MacLook.headerHeight))
        .background(MacPalette.columnsFace)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.frame) }
        .accessibilityHidden(true)
    }

    /// A heading's line (.row.grp): its words 10 in, on its own ground.
    private func groupLine(_ title: String) -> some View {
        Text(title)
            .font(Typeface.Mac.text(.label).weight(.semibold))
            .foregroundStyle(DWPalette.label)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CGFloat(DWLook.here.groupRowHeight))
            .background(MacPalette.groupRowFace)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
            .accessibilityAddTraits(.isHeader)
    }

    /// A row (.row, as tall as View > Row Size says - 34 at Small, its drawing's): its cells at the columns' widths,
    /// striped every other one, selected in the selection's colours - one element for VoiceOver, everything it shows its
    /// label, its actions its buttons'.
    private func rowLine(_ row: RequestRow, widths: [CGFloat], striped: Bool) -> some View {
        let on = selected == row.key
        let offered = RequestAction.offered(row, gets: server.access.can(.request), online: reachability.online)
        return HStack(spacing: 0) {
            cell(widths[0]) { albumCell(row) }
            cell(widths[1]) {
                Text(row.artist)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(on ? DWPalette.selt : DWPalette.t2)
                    .lineLimit(1)
            }
            cell(widths[2]) {
                Text(row.from ?? "")
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(on ? DWPalette.selt : DWPalette.t2)
                    .lineLimit(1)
            }
            cell(widths[3]) { progressCell(row) }
            cell(widths[4]) { speedCell(row) }
            cell(widths[5], alignment: .trailing) { buttons(row) }
        }
        .frame(height: CGFloat(rowSize.requestRowHeight))
        .foregroundStyle(on ? DWPalette.selt : DWPalette.head)
        .background {
            if on {
                Rectangle()
                    .fill(DWPalette.selbg)
                    .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))
            } else if striped {
                MacPalette.rowStripe
            }
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
        .opacity(row.dimmed ? DWPalette.off : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { clicked(row, count: 2) }
        .onTapGesture { clicked(row, count: 1) }
        // the right-click: everything the row offers, its buttons' and its •••'s
        .macContextMenu {
            ForEach(offered, id: \.self) { (action: RequestAction) in
                Button(action.words(row)) { act(action, row) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RequestSpoken.row(row, runs: server.access.seesDetail, note: openNote(row)))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityActions {
            ForEach(offered, id: \.self) { (action: RequestAction) in
                Button(action.words(row)) { act(action, row) }
            }
        }
    }

    private func cell<Content: View>(_ width: CGFloat, alignment: Alignment = .leading,
                                     @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .frame(width: width, alignment: alignment)
    }

    private func clicked(_ row: RequestRow, count: Int) {
        tableFocused = true
        switch MacTable.clicked(row.key, count: count) {
        case .select(let key):
            selected = key
        case .open(let key):
            selected = key
            if row.opens != nil { requests.open(row) }
        }
    }

    /// The cover (.cover: its 1 point edge, a chip's corners) and the title, the title's whole, which try and who asked
    /// its help.
    private func albumCell(_ row: RequestRow) -> some View {
        HStack(spacing: 8) {
            let addresses = row.cover.map { [ArchiveCoverID(.release, $0.lowercased())] } ?? []
            ArchiveCover(addresses: addresses, size: ArchiveCoverSize.row)
                .frame(width: CGFloat(rowSize.requestCover), height: CGFloat(rowSize.requestCover))
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                .accessibilityHidden(true)
            Text(row.title)
                .font(Typeface.Mac.text(.base))
                .lineLimit(1)
        }
        .help(RequestSpoken.help(row))
    }

    /// The Progress column: whatever a row says here is cut short in its cell, never past it - the whole of it the
    /// cell's help, and in what VoiceOver hears. A download's meter keeps its least width; its words beside it give way.
    @ViewBuilder private func progressCell(_ row: RequestRow) -> some View {
        switch row.section {
        case .downloading:
            HStack(spacing: 8) {
                DWMeter(fraction: row.progress / 100)
                    .frame(minWidth: CGFloat(RequestColumns.meterLeast))
                Text(row.progressWords ?? "")
                    .font(Typeface.Mac.mono(.label))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .help(row.progressWords ?? "")
        case .waiting:
            let words = row.progressWords ?? row.brief
            Text(words)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(row.lineTone == .warning ? DWPalette.amberText : DWPalette.t2)
                .lineLimit(1)
                .help(words)
        case .attention:
            let runs = server.access.seesDetail
            let reason = RequestSpoken.reason(row, runs: runs)
            Text(row.problem ?? reason ?? "")
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.redChipText)
                .lineLimit(1)
                .help(attentionHelp(row, reason: reason, runs: runs))
        case .done:
            // the chip's few words - what it means first (RequestWords.chipWords) - and when, or why it couldn't open,
            // beside it, cut short where the chip leaves too little
            let note = openNote(row)
            HStack(spacing: 8) {
                DWChip(words: row.chip ?? row.progressWords ?? row.line, tone: row.lineTone == .plain ? .good : .caution)
                    .layoutPriority(1)
                if let note {
                    Text(note)
                        .font(Typeface.Mac.text(.label))
                        .foregroundStyle(DWPalette.amberText)
                        .lineLimit(1)
                } else if let when = row.when {
                    Text(when)
                        .font(Typeface.Mac.text(.label))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(1)
                }
            }
            .help(doneHelp(row, note: note))
        }
    }

    /// Why a done row's Open couldn't open it, while it says so.
    private func openNote(_ row: RequestRow) -> String? {
        row.opens.flatMap { requests.notes[$0.key] }
    }

    /// What a refused row's line leaves out, over it: the reason under a retry's refusal, and for whoever runs deadwax
    /// the errors' own words.
    private func attentionHelp(_ row: RequestRow, reason: String?, runs: Bool) -> String {
        let shown = row.problem ?? reason
        var said = [row.problem != nil ? reason : nil, row.tries, row.askedBy]
        if runs { said += [row.reasonDetail, row.problemDetail] }
        if !server.access.can(.request) && (row.nextPeer != nil || row.askAgain != nil) { said.append(RequestWords.getOff) }
        return ([shown] + said).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// A done row's line in full - how it ended, the whole sentence, and when - how it was filed (a manual search's),
    /// and the rest the phone says under it.
    private func doneHelp(_ row: RequestRow, note: String?) -> String {
        let runs = server.access.seesDetail
        let said: [String?] = [row.line, ManualSearch.doneLine(row, edits: server.access.can(.edit)),
                               runs ? row.reasonDetail : nil, !runs && row.reasonTell ? ErrorWords.tell : nil,
                               row.askedBy, note]
        return said.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func speedCell(_ row: RequestRow) -> some View {
        let rate = RequestFilter.rate(row)
        return Text(RequestFilter.speedText(row))
            .font(Typeface.Mac.mono(.small))
            .foregroundStyle(rate == nil ? DWPalette.t3 : DWPalette.head)
            .lineLimit(1)
    }

    /// The buttons column (240): the row's main action - a done row's Play and Open - and its ••• for the rest.
    private func buttons(_ row: RequestRow) -> some View {
        let gets = server.access.can(.request)
        let more = RequestAction.more(row, gets: gets)
        return HStack(spacing: 6) {
            ForEach(RequestAction.buttons(row, gets: gets), id: \.self) { (action: RequestAction) in
                button(action, row)
            }
            if !more.isEmpty {
                Menu {
                    ForEach(more, id: \.self) { (action: RequestAction) in
                        Button(action.words(row)) { act(action, row) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Typeface.symbol(.caption2).weight(.semibold))
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(DWButtonStyle(size: .small))
                .fixedSize()
            }
        }
        .disabled(row.busy)
    }

    @ViewBuilder private func button(_ action: RequestAction, _ row: RequestRow) -> some View {
        switch action {
        case .cancel:
            Button(action.words(row)) { act(.cancel, row) }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(row.cancel == .cancelling || !reachability.online)
                // Leave's reason: who else asked for it
                .help([RequestWords.cancelLabel(row), row.askedBy].compactMap { $0 }.joined(separator: "\n"))
        case .nextPeer:
            Button(action.words(row)) { act(.nextPeer, row) }
                .buttonStyle(DWButtonStyle(kind: Self.nextKind(row), size: .small))
        case .askAgain:
            Button(action.words(row)) { act(.askAgain, row) }
                .buttonStyle(DWButtonStyle(size: .small))
        case .play:
            Button {
                play(row)
            } label: {
                HStack(spacing: 6) {
                    SharpSymbol(.play)
                        .font(Typeface.symbol(.caption2))
                    Text(action.words(row))
                }
            }
            .buttonStyle(DWButtonStyle(size: .small))
        case .open:
            Button(action.words(row)) { act(.open, row) }
                .buttonStyle(DWButtonStyle(size: .small))
                .opacity(requests.opening == row.key ? DWPalette.off : 1)
        }
    }

    /// Another source in the accent when it's the way on (Core's `primary`), plain otherwise.
    private static func nextKind(_ row: RequestRow) -> DWButtonStyle.Kind {
        guard let next = row.nextPeer, next.primary else { return .normal }
        return .pri
    }

    // MARK: what the buttons do

    /// An action, from its button, its •••, the right-click or VoiceOver.
    private func act(_ action: RequestAction, _ row: RequestRow) {
        switch action {
        case .cancel: tappedCancel(row)
        case .nextPeer: requests.retry(row, same: false)
        case .askAgain: requests.retry(row, same: true)
        case .play: play(row)
        case .open: requests.open(row)
        }
    }

    /// Cancel: at once, or with Confirm before cancelling on, asking first.
    private func tappedCancel(_ row: RequestRow) {
        guard row.jobId != nil, row.cancel == .ready else { return }
        if ConfirmCancel.read(UserDefaults.standard.string(forKey: ConfirmCancel.storageKey)) {
            confirming = row
        } else {
            confirmed(row.key)
        }
    }

    /// The cancel itself: of the row as the board has it now, and only while it can still be cancelled - a question
    /// answered after its download moved on (being filed, filed) cancels nothing.
    private func confirmed(_ key: String) {
        confirming = nil
        guard let live = RequestFilter.cancellable(key, in: requests.board) else { return }
        requests.cancel(live)
    }

    /// A done row's Play: its album from the first song, in the click with nothing awaited, when its songs are in hand -
    /// otherwise Open's.
    private func play(_ row: RequestRow) {
        if let plays = requests.plays(row) {
            player.play(songs: plays.songs, album: plays.album, at: 0)
        } else {
            requests.open(row)
        }
    }
}
