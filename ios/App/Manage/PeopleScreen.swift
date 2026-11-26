import DeadwaxCore
import SwiftUI

/// Settings > Manage > People (Phase 8, slice 11 - notes/ios-specs/phase8-managing.md 10; the web's app/People.tsx):
/// Navidrome's accounts, managed from deadwax as you - a Navidrome admin's, with logins on (Core's People.offered).
///
/// Top to bottom, one page whatever it shows: without People's permission, `People.peopleOnly` alone; before the first
/// answer a spinner (or why it couldn't be read, with Try again; or, out of reach, that managing needs deadwax); when
/// People can't work here, deadwax's words, their fix and - logins off - the Sharing deadwax guide; locked, Unlock People
/// (PeopleUnlock: whose password, the field, Unlock, the plain-http note); unlocked, the unlocked line (with Lock and + in
/// the bar - Add a person, a sheet), the version note when Navidrome isn't the one People was checked with, what the
/// last write said, Everyone in Navidrome (you first, as the server lists them: each person's mark, name, user name and
/// chips - their sign-ins, library and the no-library warning read with them - a row pushing their page,
/// PersonScreen), and Known only to deadwax (each name, what deadwax keeps for it, and Forget… behind a question).
///
/// The state is the app's (PeopleModel) - a person's page and this list are one. One write at a time; while one is out,
/// Back is hidden and the tab tapped again keeps the page. Each write's answer is said once, where it was asked from.
///
/// (The redesign, slice R14 - notes/ios.md "The redesign, slice R14: People and Server settings") Flat: no List - the
/// page's black, Everyone in Navidrome iArtists' rows (a round mark of 44, the name, the line under it, the chevron, on
/// the row's hairline), the unlock field a box (FieldLook). The phone's alone: the Mac's People is MacPeoplePage, the
/// list and a person side by side.
struct PeopleScreen: View {
    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forgetting: PeopleKnownOnly?

    var body: some View {
        let flow = people.flow
        let online = reachability.online
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !people.allowed {
                    PeopleLine(text: People.peopleOnly)
                        .padding(.top, ManageLook.cardAbove)
                } else {
                    PeopleStatus()
                    if flow.view == .list, let state = flow.state {
                        listParts(state, flow: flow, online: online)
                    }
                    PeopleReadAgain()
                }
            }
            .padding(.horizontal, ManageLook.side)
            .padding(.bottom, ManageLook.cardAbove)
        }
        .navigationTitle(People.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.writing != nil)
        .editOutOfReach(!online && flow.state != nil)
        .scrollDismissesKeyboard(.interactively)
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .pullToRefresh {
            await people.refresh()
        }
        .toolbar {
            if people.allowed && flow.view == .list {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(People.lock) {
                        people.lock()
                    }
                    .disabled(!flow.canLock(online: online, signInOver: people.signInOver))
                    Button {
                        people.open(.add)
                    } label: {
                        Image(systemName: People.addSymbol)
                    }
                    .accessibilityLabel(People.addTitle)
                    .disabled(flow.writing != nil)
                }
            }
        }
        .appSheet(item: addSheet) { (_: PeopleSheet) in
            AddPersonSheet()
                .macSheet()
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
        .onAppear { people.shows() }
        .onDisappear {
            people.hides()
            people.pageGone()
        }
        .onChange(of: people.allowed) { _, now in
            if now { Task { await people.refresh() } }
        }
    }

    /// Add a person's sheet, up while the flow says so; a swipe or Close puts it away (and its passwords).
    private var addSheet: Binding<PeopleSheet?> {
        Binding(
            get: { people.flow.sheet == .add ? .add : nil },
            set: { (shown: PeopleSheet?) -> Void in if shown == nil { people.closed() } }
        )
    }

    // MARK: unlocked

    @ViewBuilder private func listParts(_ state: PeopleState, flow: PeopleFlow, online: Bool) -> some View {
        ManageNote(words: People.unlockedLine)
        if let note = People.versionNote(people.navidrome) {
            ManageNote(words: note, colour: DWPalette.amberText)
        }
        if let said = flow.said(at: .list) {
            PeopleSaidView(said: said)
                .padding(.top, ManageLook.cardGap)
        }
        PhoneGroup(legend: People.everyone) {
            ForEach(state.people) { (person: PeoplePerson) in
                NavigationLink(value: AppRoute.person(person.id)) {
                    PersonRow(person: person)
                }
                .buttonStyle(.plain)
            }
        }
        if !state.knownOnly.isEmpty {
            PhoneGroup(legend: People.knownOnlyTitle) {
                ManageNote(words: People.knownOnlyLine)
                    .padding(.bottom, ManageLook.cardGap)
                ForEach(state.knownOnly) { (entry: PeopleKnownOnly) in
                    knownRow(entry, flow: flow, online: online)
                }
            }
        }
    }

    /// A name known only to deadwax: the name, what deadwax keeps for it (read once), Forget… behind a question, and
    /// what forgetting it said - on the row's hairline.
    private func knownRow(_ entry: PeopleKnownOnly, flow: PeopleFlow, online: Bool) -> some View {
        let busy = flow.writing(.forget, for: entry.user)
        return VStack(alignment: .leading, spacing: ManageLook.wordsGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.user)
                    .font(Typeface.Phone.mono(.small))
                    .foregroundStyle(DWPalette.text)
                Text(People.knownWords(entry))
                    .font(ManageLook.small)
                    .foregroundStyle(DWPalette.t2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Button {
                forgetting = entry
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(busy ? People.forgetting : People.forgetEllipsis)
                }
            }
            .buttonStyle(DWButtonStyle(size: .small))
            .disabled(!flow.canWrite(online: online, signInOver: people.signInOver))
            if let said = flow.said(at: .known(entry.user)) {
                PeopleSaidView(said: said)
            }
        }
        .padding(.vertical, ManageLook.cardGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
    }
}

/// A person's row in Everyone in Navidrome (iArtists' `.row.tall`): their mark - the initial on a round 44 - their name,
/// their user name and chips under it in the second colour, the chevron; the row's hairline. One element for VoiceOver:
/// the name, the user name and chips, their deadwax sign-ins, their library and the no-library warning, in words.
struct PersonRow: View {
    let person: PeoplePerson

    var body: some View {
        LibraryListRow(title: person.name, line: PeopleFacts.line(person),
                       lineColour: People.librariesWarning(person) == nil ? DWPalette.t2 : DWPalette.amberText) {
            Avatar(letter: PeopleFacts.letter(person), points: LibraryLook.rowCover)
        } trailing: {
            LibraryChevron()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PeopleFacts.spoken(person, now: Date().timeIntervalSince1970))
    }
}

/// (R14) What a person's row and head say, on both devices: the initial their mark draws, the line under their name -
/// their user name and chips ("robin · You · Admin") - and everything VoiceOver reads for them, in order.
enum PeopleFacts {
    /// The first letter of their name, else of their user name - capitalised.
    static func letter(_ person: PeoplePerson) -> String {
        let name = person.name.trimmingCharacters(in: .whitespaces)
        return String((name.isEmpty ? person.user : name).prefix(1)).uppercased()
    }

    /// Their user name and their chips, one line.
    static func line(_ person: PeoplePerson) -> String {
        ([person.user] + People.chips(person)).joined(separator: " \u{00B7} ")
    }

    /// Their name, the line, their deadwax sign-ins, their library and - Navidrome giving them none - the warning.
    static func spoken(_ person: PeoplePerson, now: Double) -> String {
        ([person.name, line(person), People.signInWords(person, now: now), People.libraryWords(person)]
            + [People.librariesWarning(person)].compactMap { $0 }).joined(separator: ", ")
    }
}

/// One of People's accounts (Phase 8, slice 11; a row of the web's People.tsx, its own page here): who they are, what
/// was last said of them, Permissions (five switches - an admin's all on and locked, a row People refuses permissions
/// for locked with the server's reason - and Save permissions, sending all five), then the changes the server offers
/// for them: Reset password… (a sheet), Make admin or No longer admin (behind a question saying what it gives or what
/// they keep), Remove… (a sheet where their user name is typed) - each refused change's reason said under them, as the
/// server gave it. Locked again, Unlock People shows here; an account the list no longer has says so.
///
/// (R14) Flat, as iPerson draws it: their head (the mark at 60, the name, their user name and sign-ins, Make admin), What
/// they can do as the purple switches with no lines under them (a tick's warning kept), Account's rows, and Revert and
/// Save permissions in the fixed foot (PhoneFoot) - Revert putting the switches back as saved, nothing sent.
struct PersonScreen: View {
    let id: String

    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Make admin / No longer admin asked, for the person as they were when it was asked.
    @State private var flipping: PeoplePerson?

    var body: some View {
        let flow = people.flow
        let person = flow.person(id)
        let online = reachability.online
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !people.allowed {
                    PeopleLine(text: People.peopleOnly)
                        .padding(.top, ManageLook.cardAbove)
                } else if let person, flow.view == .list {
                    personParts(person, flow: flow, online: online)
                    PeopleReadAgain()
                } else if flow.view == .list {
                    PeopleLine(text: People.gone)
                        .padding(.top, ManageLook.cardAbove)
                    PeopleReadAgain()
                } else {
                    PeopleStatus()
                    PeopleReadAgain()
                }
            }
            .padding(.horizontal, ManageLook.side)
            .padding(.bottom, ManageLook.cardAbove)
        }
        .modifier(PersonFoot(person: flow.view == .list && people.allowed ? person : nil))
        .navigationTitle(person?.name ?? People.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.writing != nil)
        .editOutOfReach(!online && flow.state != nil)
        .scrollDismissesKeyboard(.interactively)
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .pullToRefresh {
            await people.refresh()
        }
        .appSheet(item: personSheet) { (sheet: PeopleSheet) in
            // each sheet keeps whom it was opened for: People locked again under it lists nobody
            switch sheet {
            case .reset(let shown):
                ResetPasswordSheet(id: shown, person: people.flow.person(shown))
                    .macSheet()
            case .remove(let shown):
                RemovePersonSheet(id: shown, person: people.flow.person(shown))
                    .macSheet()
            case .add:
                EmptyView()
            }
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
        .onAppear { people.shows() }
        .onDisappear {
            people.hides()
            people.pageGone()
        }
    }

    /// Reset password…'s or Remove…'s sheet, for this person - up while the flow says so.
    private var personSheet: Binding<PeopleSheet?> {
        Binding(
            get: {
                guard let sheet = people.flow.sheet, sheet == .reset(id) || sheet == .remove(id) else { return nil }
                return sheet
            },
            set: { (shown: PeopleSheet?) -> Void in if shown == nil { people.closed() } }
        )
    }

    @ViewBuilder private func personParts(_ person: PeoplePerson, flow: PeopleFlow, online: Bool) -> some View {
        let signInOver = people.signInOver
        let offered = People.actions(person).filter(\.offered)
        head(person, flip: offered.first { $0.kind == .admin }, flow: flow, online: online)
        if let said = flow.said(at: .person(person.id)) {
            PeopleSaidView(said: said)
                .padding(.top, ManageLook.cardGap)
        }
        PhoneGroup(legend: People.permissionsTitle) {
            ForEach(flow.checkboxes(for: person), id: \.category) { (box: People.Checkbox) in
                VStack(alignment: .leading, spacing: 0) {
                    // the switch says its label alone (iPerson: no line under it); a tick's warning stays
                    Toggle(isOn: people.ticked(person, box.category)) {
                        Text(box.label)
                    }
                    .disabled(box.locked || flow.writing != nil)
                    .accessibilityHint(box.line)
                    .settingsSwitch()
                    if let warning = box.warning {
                        ManageNote(words: warning, colour: DWPalette.amberText)
                            .padding(.bottom, ManageLook.cardGap)
                    }
                }
            }
        }
        if let reason = People.lockedReason(admin: person.admin, refused: person.can.permissions), !reason.isEmpty {
            ManageNote(words: People.onPhone(reason))
        }
        ManageNote(words: People.peopleLine, colour: DWPalette.t3)
        let changes = offered.filter { $0.kind != .admin }
        // (R14's review) Account's legend only over its rows: refusals alone are notes under the switches
        if !changes.isEmpty {
            PhoneGroup(legend: YouWords.account) {
                ForEach(changes, id: \.kind) { (action: People.Action) in
                    actionRow(action, person, flow: flow, online: online, signInOver: signInOver)
                }
            }
        }
        ForEach(People.refusals(person), id: \.self) { (reason: String) in
            ManageNote(words: People.onPhone(reason))
        }
    }

    /// Their head (iPerson's): the mark at 60, the name at 20 bold, their user name and sign-ins, their library and the
    /// no-library warning under it - read as one - and Make admin (or No longer admin) at its end; from xxxLarge the
    /// button under the words, across them.
    private func head(_ person: PeoplePerson, flip: People.Action?, flow: PeopleFlow, online: Bool) -> some View {
        let stacked = typeSize.isAccessibilitySize || typeSize == .xxxLarge
        let now = Date().timeIntervalSince1970
        return VStack(alignment: .leading, spacing: ManageLook.cardGap) {
            HStack(alignment: stacked ? .top : .center, spacing: ManageLook.headGap) {
                Avatar(letter: PeopleFacts.letter(person), points: ManageLook.headMark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(Typeface.title3.weight(.bold))
                        .foregroundStyle(DWPalette.text)
                        .lineLimit(stacked ? 3 : 1)
                    Text(PeopleFacts.line(person))
                        .font(ManageLook.small)
                        .foregroundStyle(DWPalette.t2)
                    Text("\(People.signInWords(person, now: now)) \u{00B7} \(People.libraryWords(person))")
                        .font(ManageLook.small)
                        .foregroundStyle(DWPalette.t3)
                    if let warning = People.librariesWarning(person) {
                        Text(warning)
                            .font(ManageLook.small)
                            .foregroundStyle(DWPalette.amberText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if !stacked, let flip {
                    flipButton(flip, person, flow: flow, online: online, fills: false)
                }
            }
            if stacked, let flip {
                flipButton(flip, person, flow: flow, online: online, fills: true)
            }
        }
        .padding(.top, ManageLook.headAbove)
    }

    /// Make admin / No longer admin: asked first (the question says what it gives or what they keep).
    private func flipButton(_ action: People.Action, _ person: PeoplePerson, flow: PeopleFlow, online: Bool,
                            fills: Bool) -> some View {
        let busy = flow.writing(.admin, for: person.id)
        return Button {
            flipping = person
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .accessibilityHidden(true)
                }
                Text(busy ? People.changing : action.label)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(DWButtonStyle(size: .small, fills: fills))
        .disabled(!flow.canWrite(online: online, signInOver: people.signInOver))
    }

    /// One of the server's changes for them, an Account row (iPerson's `.go`): Reset password… opens its sheet, Remove…
    /// (in red) its own.
    private func actionRow(_ action: People.Action, _ person: PeoplePerson, flow: PeopleFlow, online: Bool,
                           signInOver: Bool) -> some View {
        Button {
            switch action.kind {
            case .reset: people.open(.reset(person.id))
            case .admin: flipping = person
            case .remove: people.open(.remove(person.id))
            }
        } label: {
            PhoneGo {
                Text(action.label)
                    .foregroundStyle(action.kind == .remove ? DWPalette.redChipText : DWPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PhoneChevron()
            }
        }
        .buttonStyle(.plain)
        .disabled(!flow.canWrite(online: online, signInOver: signInOver))
        .opacity(flow.canWrite(online: online, signInOver: signInOver) ? 1 : DWPalette.off)
    }
}

/// (R14) A person's fixed foot (iPerson's `.foot2`): Revert - the switches put back as saved, nothing sent - and Save
/// permissions, the purple one across the rest, sending all five as the switches show them. Only for an ordinary
/// person People lets permissions be saved for (People.savesPermissions) - and none while the page shows no one.
///
/// (R14's review) The page is the same view with the foot and without it - the foot an inset at its foot that is there
/// or isn't - so someone made an admin (the foot going) keeps the page where it was scrolled to: `if` round the page
/// made it a new one. The inset is the page's room under its content, as `phoneFoot`'s is; a person's page has no field
/// while it has a foot (Unlock People shows only while locked, with no one shown), so riding up on a keyboard - the one
/// way this differs from `phoneFoot`'s layer - never comes up.
private struct PersonFoot: ViewModifier {
    let person: PeoplePerson?

    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let person, People.savesPermissions(person) {
                    PhoneFoot {
                        actions(person)
                    }
                }
            }
    }

    @ViewBuilder private func actions(_ person: PeoplePerson) -> some View {
        let flow = people.flow
        let saving = flow.writing(.permissions, for: person.id)
        Button(PeopleRevert.label) {
            PeopleRevert.revert(person, people: people)
        }
        .buttonStyle(DWButtonStyle(size: .large))
        .disabled(!flow.dirty(person) || flow.writing != nil)
        Button {
            people.save(person)
        } label: {
            HStack(spacing: 8) {
                if saving {
                    ProgressView()
                        .accessibilityHidden(true)
                }
                Text(saving ? People.saving : People.savePermissions)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
        .disabled(!flow.canSave(person, online: reachability.online, signInOver: people.signInOver))
    }
}

/// (R14) Revert on a person's foot, both devices': each switch put back as last saved, through the switches' own
/// binding (PeopleModel.ticked - the flow's tick, which drafts only an ordinary person's five) - nothing sent, and Save
/// off again once nothing differs.
enum PeopleRevert {
    /// The drawings' Revert - the same word Server settings' revert starts with.
    static let label = "Revert"

    @MainActor static func revert(_ person: PeoplePerson, people: PeopleModel) {
        guard let saved = person.permissions else { return }
        for category in People.categories {
            let tick = people.ticked(person, category)
            if tick.wrappedValue != saved[category] { tick.wrappedValue = saved[category] }
        }
    }
}

// MARK: - the parts both pages draw (and the Mac's People)

/// Before the list: the first read's spinner, why it couldn't be read (Try again), that managing needs deadwax, why
/// People can't work here (and its fix, and - logins off - the Sharing deadwax guide), or Unlock People. (R14) Flat, the
/// look's pieces alone, so the Mac's People draws it too.
struct PeopleStatus: View {
    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let flow = people.flow
        VStack(alignment: .leading, spacing: ManageLook.cardGap) {
            if let state = flow.state {
                if let problem = state.problem, !problem.isEmpty {
                    PeopleLine(text: problem)
                    if let fix = state.fix, !fix.isEmpty {
                        PeopleLine(text: fix, quiet: true)
                    }
                    if !state.on, let guide = URL(string: People.sharingDoc) {
                        Link(People.sharing, destination: guide)
                            .font(ManageLook.small.weight(.semibold))
                            .foregroundStyle(DWPalette.acc)
                    }
                }
                if flow.view == .locked {
                    PeopleUnlock(user: state.you)
                }
            } else if let problem = flow.readProblem {
                ErrorNote(text: problem)
                Button(LibraryCare.tryAgain) {
                    Task { await people.refresh() }
                }
                .buttonStyle(DWButtonStyle())
                .disabled(flow.reading || !reachability.online)
            } else if !reachability.online {
                PeopleLine(text: EditWords.needsDeadwax)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(People.loading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ManageLook.cardAbove)
    }
}

/// A read again that failed, under what still shows.
struct PeopleReadAgain: View {
    @Environment(PeopleModel.self) private var people

    var body: some View {
        if people.flow.state != nil, let problem = people.flow.readProblem {
            ErrorNote(text: problem)
                .padding(.top, ManageLook.cardAbove)
        }
    }
}

/// Unlock People (the web's UnlockPeople.tsx): whose password, the field (the password manager's current password), Unlock
/// - on only with something typed and deadwax in reach - and what came of it; the plain-http note under it. Refused, the
/// field is emptied and takes the focus again (not under VoiceOver, where it would cut off what was just said). (R14)
/// Flat, on both devices: its heading, the field a box (PeopleField), Unlock the purple button.
struct PeopleUnlock: View {
    let user: String

    @Environment(PeopleModel.self) private var people
    @Environment(ServerModel.self) private var server
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Bool

    var body: some View {
        let flow = people.flow
        let busy = flow.writing(.unlock)
        VStack(alignment: .leading, spacing: ManageLook.cardGap) {
            ManageHeading(words: People.unlockTitle)
            PeopleLine(text: People.unlockLine(user), quiet: true)
            SecureField(People.unlockLabel, text: people.typing(\.unlockPassword, at: .unlock))
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { people.unlock() }
                .disabled(flow.writing != nil)
                .modifier(PeopleField(focused: focused))
            Button {
                focused = false
                people.unlock()
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(busy ? People.unlocking : People.unlock)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(DWButtonStyle(kind: .pri, fills: !Platform.mac))
            .disabled(!flow.canUnlock(online: people.online, signInOver: people.signInOver))
            if let said = flow.said(at: .unlock) {
                PeopleSaidView(said: said)
            }
            if let note = People.httpNote(at: server.address) {
                ManageNote(words: note, colour: DWPalette.amberText)
            }
        }
        .onChange(of: flow.focusUnlock) { _, _ in
            if !voiceOver { focused = true }
        }
    }
}

/// (R14's review) A field of People's - Unlock People's password and the sheets' seven - in its box: on the phone the
/// sign-in's own (FieldLook, the body's size, about 41 tall); on the Mac the Mac's own field, as DWField and SettingWell
/// draw it - the plain field at the field's 13 on the look's well, 24 tall, 8 in either side, the system's focus ring off
/// and the well's edge the accent's while it has the cursor. A field's own font (Remove's typed name, in the readout
/// face) is set before this, so it holds on both.
struct PeopleField: ViewModifier {
    var focused = false

    @ViewBuilder func body(content: Content) -> some View {
        if Platform.mac {
            content
                .textFieldStyle(.plain)
                .font(Typeface.Look.text(.field))
                .foregroundStyle(DWPalette.fieldText)
                .focusEffectDisabled()
                .padding(.horizontal, 8)
                .lookHeight(DWLook.here.fieldHeight)
                .background {
                    DWWell(focused: focused)
                }
        } else {
            content
                .modifier(FieldLook(focused: focused))
        }
    }
}

/// What a write said, as one element: done in green (and Made's warning in amber), or what went wrong in red and how to
/// fix it.
struct PeopleSaidView: View {
    let said: PeopleSaid

    var body: some View {
        VStack(alignment: .leading, spacing: ManageLook.wordsGap) {
            Text(said.words)
                .foregroundStyle(said.problem ? DWPalette.redChipText : DWPalette.greenText)
            if let warning = said.warning {
                Text(warning)
                    .font(ManageLook.small)
                    .foregroundStyle(DWPalette.amberText)
            }
            if let fix = said.fix {
                Text(fix)
                    .font(ManageLook.small)
                    .foregroundStyle(DWPalette.t2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A line of People's words, wrapping at every size - the small size and the second colour for what explains.
struct PeopleLine: View {
    let text: String
    var quiet = false

    var body: some View {
        Text(text)
            .font(quiet ? ManageLook.small : Typeface.Look.text(.field))
            .foregroundStyle(quiet ? DWPalette.t2 : DWPalette.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
