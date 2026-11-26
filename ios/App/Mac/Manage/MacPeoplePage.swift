import DeadwaxCore
import SwiftUI

/// People on the Mac (the redesign, slice R14 - People.dc.html; notes/ios.md "The redesign, slice R14: People and Server
/// settings"): the phone's two pages as one - Everyone in Navidrome at the left, the person chosen beside it.
///
/// - The toolbar: Add a person… (the purple one - its sheet, as the phone's +), and Lock at its end - only with People
///   unlocked, as the phone's bar.
/// - Locked, or before the first answer: the phone's own parts (PeopleStatus - why it can't work here, Unlock People
///   with the admin's own password - and PeopleReadAgain), at a readable width.
/// - Unlocked, the list (MacColumnList): Person (their round mark, their name and user name), Role and Last signed in
///   ("now", "2 hours ago", "never"); a click chooses, as does ↑ and ↓. (R14's review) Person keeps its least beside the
///   others (`personLeast`, the name's 112 at every Row Size): Last signed in is left out first, then Role, as the
///   Playlists page leaves Whose and Changed out - and the Person cell's help says all of it (their display name, user
///   name, role and sign-ins). Under it the unlocked line, the version note, what the list's last write said, and Known
///   only to deadwax with Forget… behind a question. Opened at a person (`.person(id)`, the phone's route) with them
///   chosen; with no one chosen, the first. The person chosen is kept by id while the list isn't loaded - locked again,
///   or not yet read - and let go of only when a list read says they've gone.
/// - The person chosen, in the panel beside it: their head (the mark at 72, the name, the user name, their sign-ins and
///   library in the readout face, the no-library warning; their chips and Make admin or No longer admin - behind the
///   phone's question - at its end, or under the words in a one-column panel, so the name keeps its room); what was
///   last said of them; Permissions (MacCheckbox - a tick's warning, the locked reason, the admins' line; each
///   permission's line in its help and VoiceOver's hint, not drawn - the plan's section 4 leaves People's hints out, as
///   the phone does) and Account (their user name, Reset password… and Remove… as the server offers them, the
///   refusals) - side by side once the panel is `twoColumns` wide, else one over the other; and for an ordinary person
///   People saves permissions for, the foot: Revert (PeopleRevert - the boxes put back as saved, nothing sent) and Save
///   permissions, sending all five as the boxes show them (PeopleFlow).
/// - Last signed in and the head's sign-ins are read against the minute (a TimelineView), never a time kept from when
///   the page opened.
/// - Every rule is the phone's (Core's PeopleFlow, the app's PeopleModel): one write at a time, an admin's boxes all
///   ticked and locked, the role's own refusals locked, the unlock the admin's own Navidrome password.
/// - The status bar: how many people and admins, and Navidrome's version.
///
/// Left out of the drawing: the Unlocked chip (nothing tells how long the unlock has left), "First seen" and Display name
/// (not in the answer), Their library's box past the albums the head says (no requests or playlists per person in the
/// answer), and the foot's count of ticks.
struct MacPeoplePage: View {
    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.macRowSize) private var rowSize
    /// The person chosen, by id.
    @State private var selected: String?
    @State private var forgetting: PeopleKnownOnly?
    /// Make admin / No longer admin asked, for the person as they were when it was asked.
    @State private var flipping: PeoplePerson?

    init(chosen: String? = nil) {
        _selected = State(initialValue: chosen)
    }

    /// The panel wide enough for Permissions and Account side by side (1.15 : 1, 14 apart inside its 16 either side):
    /// Account 266 at least - Reset password… and Remove… on one line inside its box's 12 either side - so 620. Side by
    /// side at the window's opening (a page of 1060, a panel of 661); one over the other at the smallest window and
    /// beside the side panel (pages of 660 and 659, panels of 382 and 381).
    static let twoColumns: CGFloat = 620
    /// The panel's sides and the gap between its two columns (People.dc.html's padding 24px 16px, gap 14px).
    static let panelSide: CGFloat = 16
    static let columnGap: CGFloat = 14

    /// The two columns' widths in a panel `width` wide: Permissions 1.15 to Account's 1.
    static func shares(_ width: CGFloat) -> (permissions: CGFloat, account: CGFloat) {
        let inside = max(0, width - 2 * panelSide - columnGap)
        return (inside * 1.15 / 2.15, inside / 2.15)
    }

    /// The list's width (People.dc.html's 398), 42% of the page's below that, and never under 260.
    static func listWidth(_ page: CGFloat) -> CGFloat {
        min(398, max(260, page * 0.42))
    }

    /// The parts before the list, at most this wide.
    private static let statusWidth: CGFloat = 520

    /// The list's columns (People.dc.html's .cols): Person takes what the others leave.
    enum Column: CaseIterable {
        case person, role, lastSignedIn
    }

    static let roleWidth: Double = 96
    static let lastSignedInWidth: Double = 118
    /// (R14's review) Person's least at Small: 10 in either side, the mark (20), 8, and 112 for the name and user name -
    /// Playlist's 160 (MacAlbumFacts.playlistLeast), as its cell is a cover and a name too.
    static let personLeast: Double = 160

    /// Person's least at a Row Size: the mark's growth on top, so the name keeps its 112 at every size (168 at Medium,
    /// 180 at Large).
    static func personLeast(_ size: MacRowSize) -> Double {
        personLeast + size.coverGrowth
    }

    /// The columns a list `width` wide draws: all three while Person keeps its least beside them; else Last signed in
    /// left out, then Role too - each still in the Person cell's help, and in the panel.
    static func shown(width: Double, size: MacRowSize) -> [Column] {
        var shown = Column.allCases
        while shown.count > 1 && width - fixedWidth(shown) < personLeast(size) {
            shown.removeLast()
        }
        return shown
    }

    /// The fixed columns' widths together.
    static func fixedWidth(_ columns: [Column]) -> Double {
        columns.reduce(0.0) { (sum: Double, column: Column) -> Double in
            switch column {
            case .person: return sum
            case .role: return sum + roleWidth
            case .lastSignedIn: return sum + lastSignedInWidth
            }
        }
    }

    private static func listColumns(_ shown: [Column]) -> [MacListColumn] {
        shown.map { (column: Column) -> MacListColumn in
            switch column {
            case .person: return MacListColumn(title: MacPeopleWords.person, width: .flexible)
            case .role: return MacListColumn(title: MacPeopleWords.role, width: .fixed(roleWidth))
            case .lastSignedIn: return MacListColumn(title: MacPeopleWords.lastSignedIn, width: .fixed(lastSignedInWidth))
            }
        }
    }

    /// The person chosen against a list: kept while the list isn't loaded (`ids` nil - locked again, or not yet read)
    /// and while they're in it; let go of only when a loaded list hasn't them, for its first.
    static func chosen(_ selected: String?, in ids: [String]?) -> String? {
        guard let ids else { return selected }
        if let selected, ids.contains(selected) { return selected }
        return ids.first
    }

    var body: some View {
        let flow = people.flow
        let online = reachability.online
        MacPage {
            tools(flow, online: online)
        } content: {
            if !people.allowed {
                PeopleLine(text: People.peopleOnly)
                    .padding(22)
            } else if flow.view == .list, let state = flow.state {
                // Last signed in and the head's sign-ins read against the minute, as it turns
                TimelineView(.everyMinute) { (time: TimelineViewDefaultContext) in
                    let now = time.date.timeIntervalSince1970
                    GeometryReader { (room: GeometryProxy) in
                        let width = Self.listWidth(room.size.width)
                        HStack(spacing: 0) {
                            list(state, width: width, now: now, flow: flow, online: online)
                                .frame(width: width)
                            DWRule(colour: DWPalette.line, vertical: true)
                            panel(state, now: now, flow: flow, online: online)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PeopleStatus()
                        PeopleReadAgain()
                    }
                    .frame(maxWidth: Self.statusWidth, alignment: .leading)
                    .padding(EdgeInsets(top: 4, leading: 22, bottom: 22, trailing: 22))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .macStatus(MacStatusItems.Items(leading: Self.status(flow.view == .list ? flow.state : nil),
                                        trailing: Self.version(people.navidrome)))
        .navigationBarBackButtonHidden(flow.writing != nil)
        .editOutOfReach(!online && flow.state != nil)
        .pullToRefresh {
            await people.refresh()
        }
        .appSheet(item: sheet) { (sheet: PeopleSheet) in
            // each sheet keeps whom it was opened for: People locked again under it lists nobody
            switch sheet {
            case .add:
                AddPersonSheet()
                    .macSheet()
            case .reset(let shown):
                ResetPasswordSheet(id: shown, person: people.flow.person(shown))
                    .macSheet()
            case .remove(let shown):
                RemovePersonSheet(id: shown, person: people.flow.person(shown))
                    .macSheet()
            }
        }
        .confirmationDialog(People.forgetQuestion(forgetting?.user ?? ""),
                            isPresented: Binding(get: { forgetting != nil },
                                                 set: { (up: Bool) -> Void in if !up { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { (entry: PeopleKnownOnly) in
            Button(People.forget, role: .destructive) {
                people.forget(entry)
            }
            Button(People.keepIt, role: .cancel) {}
                .returnCancels()
        }
        .confirmationDialog(flipping.map { People.flipWords($0).question } ?? "",
                            isPresented: Binding(get: { flipping != nil },
                                                 set: { (up: Bool) -> Void in if !up { flipping = nil } }),
                            titleVisibility: .visible, presenting: flipping) { (asked: PeoplePerson) in
            Button(People.flipButton(asked)) {
                // only as asked: a list read since that says they changed asks again rather than flipping back
                if let now = people.flow.person(asked.id), now.admin == asked.admin { people.flip(now) }
            }
            Button(People.keepAsItIs, role: .cancel) {}
                .returnCancels()
        } message: { (asked: PeoplePerson) in
            Text(People.flipWords(asked).body)
        }
        .onChange(of: flow.view == .list ? flow.state?.people.map(\.id) : nil, initial: true) {
            (_: [String]?, ids: [String]?) -> Void in
            // the person chosen, kept through a lock and before the first read: let go of only when a loaded list
            // hasn't them
            selected = Self.chosen(selected, in: ids)
        }
        .onAppear {
            people.shows()
        }
        .onDisappear {
            people.hides()
            people.pageGone()
        }
        .onChange(of: people.allowed) { _, allowed in
            if allowed { Task { await people.refresh() } }
        }
    }

    /// The flow's sheet - Add a person, Reset password, Remove - up while the flow says so; Close or Escape puts it away
    /// (and its passwords).
    private var sheet: Binding<PeopleSheet?> {
        Binding(
            get: { people.flow.sheet },
            set: { (shown: PeopleSheet?) -> Void in if shown == nil { people.closed() } }
        )
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ flow: PeopleFlow, online: Bool) -> some View {
        if people.allowed && flow.view == .list {
            Button("\(People.addTitle)\u{2026}") {
                people.open(.add)
            }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .disabled(flow.writing != nil)
            Spacer(minLength: 8)
            Button(People.lock) {
                people.lock()
            }
            .buttonStyle(DWButtonStyle())
            .disabled(!flow.canLock(online: online, signInOver: people.signInOver))
        } else {
            Spacer(minLength: 8)
        }
    }

    // MARK: the list

    private func list(_ state: PeopleState, width: CGFloat, now: Double, flow: PeopleFlow, online: Bool) -> some View {
        // the columns that keep the name its room at this width and Row Size
        let shown = Self.shown(width: Double(width), size: rowSize)
        return VStack(spacing: 0) {
            MacColumnList(columns: Self.listColumns(shown), rows: state.people, selected: $selected,
                          open: { (person: PeoplePerson) -> Void in selected = person.id },
                          menu: { (_: PeoplePerson) -> EmptyModifier in EmptyModifier() }
            ) { (person: PeoplePerson, column: Int) in
                if shown.indices.contains(column) { cell(person, shown[column], now: now) }
            }
            DWRule(colour: DWPalette.line)
            // the list's notes: as tall as they are while that's no more than the room the stack gives them (half of
            // what the list's header and the rule leave - the list is as flexible as they come), scrolling past it
            ViewThatFits(in: .vertical) {
                notes(state, flow: flow, online: online)
                ScrollView {
                    notes(state, flow: flow, online: online)
                }
            }
        }
    }

    @ViewBuilder private func cell(_ person: PeoplePerson, _ column: Column, now: Double) -> some View {
        switch column {
        case .person:
            HStack(spacing: Self.markGap) {
                Avatar(letter: PeopleFacts.letter(person), points: CGFloat(rowSize.cover))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // the name before the user name: the user name is cut first
                    Text(person.name)
                        .foregroundStyle(DWPalette.head)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(person.user)
                        .font(Typeface.Mac.mono(.label))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .help(MacPeopleWords.help(person, now: now))
        case .role:
            Text(MacPeopleWords.role(person))
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
        case .lastSignedIn:
            Text(MacPeopleWords.lastSignIn(person, now: now))
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .help(People.signInWords(person, now: now))
        }
    }

    /// Between a row's mark and its words.
    static let markGap: CGFloat = 8

    /// Under the list: the unlocked line, the version note, what the list's last write said, and Known only to deadwax.
    private func notes(_ state: PeopleState, flow: PeopleFlow, online: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(People.unlockedLine)
                .foregroundStyle(DWPalette.t3)
            if let note = People.versionNote(people.navidrome) {
                Text(note)
                    .foregroundStyle(DWPalette.amberText)
            }
            if let said = flow.said(at: .list) {
                PeopleSaidView(said: said)
            }
            if !state.knownOnly.isEmpty {
                MacGroupBox(legend: People.knownOnlyTitle) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(People.knownOnlyLine)
                            .foregroundStyle(DWPalette.t2)
                        ForEach(state.knownOnly) { (entry: PeopleKnownOnly) in
                            known(entry, flow: flow, online: online)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .font(Typeface.Mac.text(.label))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10))
    }

    /// A name known only to deadwax: the name, what deadwax keeps for it, Forget… behind a question, what it said.
    private func known(_ entry: PeopleKnownOnly, flow: PeopleFlow, online: Bool) -> some View {
        let busy = flow.writing(.forget, for: entry.user)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.user)
                        .font(Typeface.Mac.mono(.label))
                        .foregroundStyle(DWPalette.head)
                    Text(People.knownWords(entry))
                        .foregroundStyle(DWPalette.t2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button(busy ? People.forgetting : People.forgetEllipsis) {
                    forgetting = entry
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(!flow.canWrite(online: online, signInOver: people.signInOver))
            }
            if let said = flow.said(at: .known(entry.user)) {
                PeopleSaidView(said: said)
            }
        }
    }

    // MARK: the person chosen

    @ViewBuilder private func panel(_ state: PeopleState, now: Double, flow: PeopleFlow, online: Bool) -> some View {
        Group {
            if let id = selected, let person = flow.person(id) {
                GeometryReader { (room: GeometryProxy) in
                    VStack(spacing: 0) {
                        head(person, now: now, beside: room.size.width >= Self.twoColumns, flow: flow, online: online)
                        DWRule(colour: DWPalette.line)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                if let said = flow.said(at: .person(person.id)) {
                                    PeopleSaidView(said: said)
                                        .font(Typeface.Mac.text(.small))
                                }
                                if room.size.width >= Self.twoColumns {
                                    // People.dc.html's flex 1.15 : 1, each its share of what the sides and the gap leave
                                    let shares = Self.shares(room.size.width)
                                    HStack(alignment: .top, spacing: Self.columnGap) {
                                        permissions(person, flow: flow)
                                            .frame(width: shares.permissions)
                                        account(person, flow: flow, online: online)
                                            .frame(width: shares.account)
                                    }
                                } else {
                                    permissions(person, flow: flow)
                                    account(person, flow: flow, online: online)
                                }
                            }
                            .padding(EdgeInsets(top: 24, leading: Self.panelSide, bottom: Self.panelSide, trailing: Self.panelSide))
                        }
                        if People.savesPermissions(person) {
                            foot(person, flow: flow, online: online)
                        }
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DWPalette.panel)
    }

    /// The head's mark, and between it and the words.
    static let headMark: CGFloat = 72
    static let headGap: CGFloat = 14

    /// Their head: the mark at 72, the name, the user name, their sign-ins and library, the warning - read as one - and
    /// their chips and Make admin (or No longer admin): at its end `beside` (a panel of two columns), else under the
    /// words, across the panel - a wide chip ("Can't sign in to deadwax") beside the name in a one-column panel would
    /// leave the name some 100 points.
    private func head(_ person: PeoplePerson, now: Double, beside: Bool, flow: PeopleFlow, online: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: Self.headGap) {
                Avatar(letter: PeopleFacts.letter(person), points: Self.headMark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(Typeface.Mac.text(.h2).weight(.bold))
                        .foregroundStyle(DWPalette.head)
                        .lineLimit(2)
                    Text(person.user)
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.t2)
                    Text("\(People.signInWords(person, now: now)) \u{00B7} \(People.libraryWords(person))")
                        .font(Typeface.Mac.mono(.small))
                        .foregroundStyle(DWPalette.t3)
                        .padding(.top, 3)
                    if let warning = People.librariesWarning(person) {
                        Text(warning)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.amberText)
                            .padding(.top, 3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if beside {
                    VStack(alignment: .trailing, spacing: 8) {
                        // one over the other: side by side they would take the name's room
                        VStack(alignment: .trailing, spacing: 4) {
                            chips(person)
                        }
                        flipButton(person, flow: flow, online: online)
                    }
                    .fixedSize()
                }
            }
            if !beside {
                // across the panel under the words: on one line while they fit, else a chip a line
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        chips(person)
                        flipButton(person, flow: flow, online: online)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            chips(person)
                        }
                        flipButton(person, flow: flow, online: online)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: Self.panelSide, bottom: 12, trailing: Self.panelSide))
    }

    @ViewBuilder private func chips(_ person: PeoplePerson) -> some View {
        ForEach(People.chips(person), id: \.self) { (chip: String) in
            DWChip(words: chip, tone: .plain)
        }
    }

    /// Make admin / No longer admin, where the server offers it: asked first.
    @ViewBuilder private func flipButton(_ person: PeoplePerson, flow: PeopleFlow, online: Bool) -> some View {
        let flip = People.actions(person).first { (action: People.Action) -> Bool in action.offered && action.kind == .admin }
        if let flip {
            let busy = flow.writing(.admin, for: person.id)
            Button {
                flipping = person
            } label: {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(busy ? People.changing : flip.label)
                }
            }
            .buttonStyle(DWButtonStyle(size: .small))
            .disabled(!flow.canWrite(online: online, signInOver: people.signInOver))
        }
    }

    /// Permissions: a box per permission - an admin's all ticked and locked, a row People refuses locked - each one's line
    /// in its help and VoiceOver's hint (the plan's section 4: People's hints aren't drawn, as on the phone), a tick's
    /// warning under it; the locked reason and the admins' line under them.
    private func permissions(_ person: PeoplePerson, flow: PeopleFlow) -> some View {
        MacGroupBox(legend: People.permissionsTitle) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(flow.checkboxes(for: person), id: \.category) { (box: People.Checkbox) in
                    let off = box.locked || flow.writing != nil
                    VStack(alignment: .leading, spacing: 2) {
                        MacCheckbox(words: box.label, on: people.ticked(person, box.category))
                            .disabled(off)
                            .opacity(off ? DWPalette.off : 1)
                            .help(box.line)
                            .accessibilityHint(box.line)
                        if let warning = box.warning {
                            Text(warning)
                                .font(Typeface.Mac.text(.label))
                                .foregroundStyle(DWPalette.amberText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 19)
                        }
                    }
                }
                Group {
                    if let reason = People.lockedReason(admin: person.admin, refused: person.can.permissions),
                       !reason.isEmpty {
                        Text(People.onPhone(reason))
                            .foregroundStyle(DWPalette.t2)
                    }
                    Text(People.peopleLine)
                        .foregroundStyle(DWPalette.t3)
                }
                .font(Typeface.Mac.text(.label))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }
        }
        .layoutPriority(1.15)
    }

    /// Account: their user name, the changes the server offers - Reset password…, Remove… in red - and the refusals.
    private func account(_ person: PeoplePerson, flow: PeopleFlow, online: Bool) -> some View {
        let changes = People.actions(person).filter { (action: People.Action) -> Bool in
            action.offered && action.kind != .admin
        }
        let open = flow.canWrite(online: online, signInOver: people.signInOver)
        return MacGroupBox(legend: YouWords.account) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(People.userLabel)
                        .foregroundStyle(DWPalette.t2)
                    Spacer(minLength: 8)
                    Text(person.user)
                        .font(Typeface.Mac.mono(.label))
                        .foregroundStyle(DWPalette.head)
                        .textSelection(.enabled)
                }
                .font(Typeface.Mac.text(.small))
                .accessibilityElement(children: .combine)
                if !changes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(changes.filter { $0.kind != .remove }, id: \.kind) { (action: People.Action) in
                            Button(action.label) {
                                people.open(.reset(person.id))
                            }
                            .buttonStyle(DWButtonStyle(size: .small))
                            .disabled(!open)
                        }
                        Spacer(minLength: 0)
                        ForEach(changes.filter { $0.kind == .remove }, id: \.kind) { (action: People.Action) in
                            Button(action.label) {
                                people.open(.remove(person.id))
                            }
                            .buttonStyle(DWButtonStyle(kind: .danger, size: .small))
                            .disabled(!open)
                        }
                    }
                    .padding(.top, 6)
                }
                ForEach(People.refusals(person), id: \.self) { (reason: String) in
                    Text(People.onPhone(reason))
                        .font(Typeface.Mac.text(.label))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .layoutPriority(1)
    }

    /// The foot (48 tall, on the line): Revert - the boxes put back as saved, nothing sent - and Save permissions,
    /// sending all five as the boxes show them.
    private func foot(_ person: PeoplePerson, flow: PeopleFlow, online: Bool) -> some View {
        let saving = flow.writing(.permissions, for: person.id)
        return HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(PeopleRevert.label) {
                PeopleRevert.revert(person, people: people)
            }
            .buttonStyle(DWButtonStyle())
            .disabled(!flow.dirty(person) || flow.writing != nil)
            Button {
                people.save(person)
            } label: {
                HStack(spacing: 6) {
                    if saving {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(saving ? People.saving : People.savePermissions)
                }
            }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .disabled(!flow.canSave(person, online: online, signInOver: people.signInOver))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(MacPalette.statusFace)
        .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
    }

    // MARK: the status bar

    /// "4 people", "1 admin" - with the list in hand.
    static func status(_ state: PeopleState?) -> [String] {
        guard let state else { return [] }
        let admins = state.people.filter(\.admin).count
        return [MacManageCount.words(state.people.count, one: MacPeopleWords.onePerson, many: MacPeopleWords.manyPeople),
                MacManageCount.words(admins, one: MacPeopleWords.oneAdmin, many: MacPeopleWords.manyAdmins)]
    }

    /// "Navidrome 0.65.0", once People has read it.
    static func version(_ navidrome: String?) -> [String] {
        guard let navidrome, !navidrome.isEmpty else { return [] }
        return ["Navidrome \(navidrome)"]
    }
}

/// (R14) The Mac's People's own words: the list's headers, a role, Last signed in's, the status bar's.
enum MacPeopleWords {
    static let person = "Person"
    static let role = "Role"
    static let lastSignedIn = "Last signed in"
    static let admin = "Admin"
    static let ordinary = "Person"
    static let signedInNow = "now"
    static let neverSignedIn = "never"
    static let onePerson = "person"
    static let manyPeople = "people"
    static let oneAdmin = "admin"
    static let manyAdmins = "admins"

    /// Last signed in's cell: "now" while they're signed in, how long ago the last was ("2 hours ago"), or "never" -
    /// People.signInWords whole in its help.
    static func lastSignIn(_ person: PeoplePerson, now: Double) -> String {
        if person.signedIn > 0 { return signedInNow }
        if let last = person.lastSignIn { return People.ago(max(0, now - last)) }
        return neverSignedIn
    }

    /// Role's cell.
    static func role(_ person: PeoplePerson) -> String {
        person.admin ? admin : ordinary
    }

    /// (R14's review) The Person cell's help: their display name and user name, their role and their sign-ins - "Kate
    /// Bush · kate · Person · Last signed in 2 hours ago" - so a name cut short, or a column left out, is said whole.
    static func help(_ person: PeoplePerson, now: Double) -> String {
        [person.name, person.user, role(person), People.signInWords(person, now: now)].joined(separator: " \u{00B7} ")
    }
}

/// (R14) A count and its noun, for Manage's status bars on the Mac: "1 person", "4 people", "19 settings".
enum MacManageCount {
    static func words(_ count: Int, one: String, many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }
}
