import DeadwaxCore
import SwiftUI

/// Settings > Manage > People (Phase 8, slice 11 - notes/ios-specs/phase8-managing.md 10; the web's app/People.tsx):
/// Navidrome's accounts, managed from deadwax as you - a Navidrome admin's, with logins on (Core's People.offered).
///
/// Top to bottom, one List whatever it shows: without People's permission, `People.peopleOnly` alone; before the first
/// answer a spinner (or why it couldn't be read, with Try again; or, out of reach, that managing needs deadwax); when
/// People can't work here, deadwax's words, their fix and - logins off - the Sharing deadwax guide; locked, Unlock People
/// (PeopleUnlockSection: whose password, the field, Unlock, the plain-http note); unlocked, the unlocked line (with Lock
/// and + in the bar - Add a person, a sheet), the version note when Navidrome isn't the one People was checked with,
/// what the last write said, Everyone in Navidrome (you first, as the server lists them: each person's name, user name,
/// chips, deadwax sign-ins and library, and the no-library warning, read as one - a row pushes their page,
/// PersonScreen), and Known only to deadwax (each name, what deadwax keeps for it, and Forget… behind a question).
///
/// The state is the app's (PeopleModel) - a person's page and this list are one. One write at a time; while one is out,
/// Back is hidden and the tab tapped again keeps the page. Each write's answer is said once, where it was asked from.
struct PeopleScreen: View {
    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forgetting: PeopleKnownOnly?

    var body: some View {
        let flow = people.flow
        let online = reachability.online
        List {
            if !people.allowed {
                Section {
                    PeopleLine(text: People.peopleOnly)
                }
            } else {
                PeopleStatusSections()
                if flow.view == .list, let state = flow.state {
                    listSections(state, flow: flow, online: online)
                }
                PeopleReadAgainSection()
            }
        }
        .navigationTitle(People.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.writing != nil)
        .editOutOfReach(!online && flow.state != nil)
        .scrollDismissesKeyboard(.interactively)
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .refreshable {
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
        .sheet(item: addSheet) { (_: PeopleSheet) in
            AddPersonSheet()
        }
        .confirmationDialog(People.forgetQuestion(forgetting?.user ?? ""),
                            isPresented: Binding(get: { forgetting != nil },
                                                 set: { (up: Bool) -> Void in if !up { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { (entry: PeopleKnownOnly) in
            Button(People.forget, role: .destructive) {
                people.forget(entry)
            }
            Button(People.keepIt, role: .cancel) {}
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

    @ViewBuilder private func listSections(_ state: PeopleState, flow: PeopleFlow, online: Bool) -> some View {
        Section {
            PeopleLine(text: People.unlockedLine, quiet: true)
            if let note = People.versionNote(people.navidrome) {
                Text(note)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let said = flow.said(at: .list) {
            Section {
                PeopleSaidView(said: said)
            }
        }
        Section {
            ForEach(state.people) { (person: PeoplePerson) in
                NavigationLink(value: AppRoute.person(person.id)) {
                    PersonFacts(person: person)
                }
            }
        } header: {
            Text(People.everyone)
                .font(Typeface.footnote)
        }
        if !state.knownOnly.isEmpty {
            Section {
                PeopleLine(text: People.knownOnlyLine, quiet: true)
                ForEach(state.knownOnly) { (entry: PeopleKnownOnly) in
                    knownRow(entry, flow: flow, online: online)
                }
            } header: {
                Text(People.knownOnlyTitle)
                    .font(Typeface.footnote)
            }
        }
    }

    /// A name known only to deadwax: the name, what deadwax keeps for it (read once), Forget… behind a question, and
    /// what forgetting it said.
    private func knownRow(_ entry: PeopleKnownOnly, flow: PeopleFlow, online: Bool) -> some View {
        let busy = flow.writing(.forget, for: entry.user)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.user)
                    .font(Typeface.mono(.body))
                Text(People.knownWords(entry))
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Button(role: .destructive) {
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
            .buttonStyle(.borderless)
            .disabled(!flow.canWrite(online: online, signInOver: people.signInOver))
            if let said = flow.said(at: .known(entry.user)) {
                PeopleSaidView(said: said)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One of People's accounts (Phase 8, slice 11; a row of the web's People.tsx, its own page here): who they are, what
/// was last said of them, Permissions (five switches - an admin's all on and locked, a row People refuses permissions
/// for locked with the server's reason - and Save permissions, sending all five), then the changes the server offers
/// for them: Reset password… (a sheet), Make admin or No longer admin (behind a question saying what it gives or what
/// they keep), Remove… (a sheet where their user name is typed) - each refused change's reason said under them, as the
/// server gave it. Locked again, Unlock People shows here; an account the list no longer has says so.
struct PersonScreen: View {
    let id: String

    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Make admin / No longer admin asked, for the person as they were when it was asked.
    @State private var flipping: PeoplePerson?

    var body: some View {
        let flow = people.flow
        let person = flow.person(id)
        let online = reachability.online
        List {
            if !people.allowed {
                Section {
                    PeopleLine(text: People.peopleOnly)
                }
            } else if let person, flow.view == .list {
                personSections(person, flow: flow, online: online)
                PeopleReadAgainSection()
            } else if flow.view == .list {
                Section {
                    PeopleLine(text: People.gone)
                }
                PeopleReadAgainSection()
            } else {
                PeopleStatusSections()
                PeopleReadAgainSection()
            }
        }
        .navigationTitle(person?.name ?? People.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.writing != nil)
        .editOutOfReach(!online && flow.state != nil)
        .scrollDismissesKeyboard(.interactively)
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .refreshable {
            await people.refresh()
        }
        .sheet(item: personSheet) { (sheet: PeopleSheet) in
            // each sheet keeps whom it was opened for: People locked again under it lists nobody
            switch sheet {
            case .reset(let shown):
                ResetPasswordSheet(id: shown, person: people.flow.person(shown))
            case .remove(let shown):
                RemovePersonSheet(id: shown, person: people.flow.person(shown))
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

    @ViewBuilder private func personSections(_ person: PeoplePerson, flow: PeopleFlow, online: Bool) -> some View {
        let signInOver = people.signInOver
        Section {
            PersonFacts(person: person)
        }
        if let said = flow.said(at: .person(person.id)) {
            Section {
                PeopleSaidView(said: said)
            }
        }
        Section {
            ForEach(flow.checkboxes(for: person), id: \.category) { (box: People.Checkbox) in
                Toggle(isOn: people.ticked(person, box.category)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(box.label)
                        Text(box.line)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                        if let warning = box.warning {
                            Text(warning)
                                .font(Typeface.footnote)
                                .foregroundStyle(Palette.amber)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(box.locked || flow.writing != nil)
            }
            if People.savesPermissions(person) {
                let saving = flow.writing(.permissions, for: person.id)
                Button {
                    people.save(person)
                } label: {
                    HStack(spacing: 8) {
                        if saving {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                        Text(saving ? People.saving : People.savePermissions)
                    }
                }
                .disabled(!flow.canSave(person, online: online, signInOver: signInOver))
            }
        } header: {
            Text(People.permissionsTitle)
                .font(Typeface.footnote)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let reason = People.lockedReason(admin: person.admin, refused: person.can.permissions),
                   !reason.isEmpty {
                    Text(People.onPhone(reason))
                }
                Text(People.peopleLine)
            }
            .font(Typeface.footnote)
            .fixedSize(horizontal: false, vertical: true)
        }
        let offered = People.actions(person).filter(\.offered)
        let refusals = People.refusals(person)
        if !offered.isEmpty || !refusals.isEmpty {
            Section {
                ForEach(offered, id: \.kind) { (action: People.Action) in
                    actionButton(action, person, flow: flow, online: online)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(refusals, id: \.self) { (reason: String) in
                        Text(People.onPhone(reason))
                    }
                }
                .font(Typeface.footnote)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One of the server's changes for them: Reset password… and Remove… open their sheets; the flip asks first.
    private func actionButton(_ action: People.Action, _ person: PeoplePerson, flow: PeopleFlow,
                              online: Bool) -> some View {
        let flippingNow = action.kind == .admin && flow.writing(.admin, for: person.id)
        return Button(role: action.kind == .remove ? .destructive : nil) {
            switch action.kind {
            case .reset: people.open(.reset(person.id))
            case .admin: flipping = person
            case .remove: people.open(.remove(person.id))
            }
        } label: {
            HStack(spacing: 8) {
                if flippingNow {
                    ProgressView()
                        .accessibilityHidden(true)
                }
                Text(flippingNow ? People.changing : action.label)
            }
        }
        .disabled(!flow.canWrite(online: online, signInOver: people.signInOver))
    }
}

// MARK: - the parts both pages draw

/// Before the list: the first read's spinner, why it couldn't be read (Try again), that managing needs deadwax, why
/// People can't work here (and its fix, and - logins off - the Sharing deadwax guide), or Unlock People.
private struct PeopleStatusSections: View {
    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let flow = people.flow
        if let state = flow.state {
            if let problem = state.problem, !problem.isEmpty {
                Section {
                    PeopleLine(text: problem)
                    if let fix = state.fix, !fix.isEmpty {
                        PeopleLine(text: fix, quiet: true)
                    }
                    if !state.on, let guide = URL(string: People.sharingDoc) {
                        Link(People.sharing, destination: guide)
                    }
                }
            }
            if flow.view == .locked {
                PeopleUnlockSection(user: state.you)
            }
        } else if let problem = flow.readProblem {
            Section {
                ErrorNote(text: problem)
                Button(LibraryCare.tryAgain) {
                    Task { await people.refresh() }
                }
                .disabled(flow.reading || !reachability.online)
            }
        } else if !reachability.online {
            Section {
                PeopleLine(text: EditWords.needsDeadwax)
            }
        } else {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(People.loading)
            }
        }
    }
}

/// A read again that failed, under what still shows.
private struct PeopleReadAgainSection: View {
    @Environment(PeopleModel.self) private var people

    var body: some View {
        if people.flow.state != nil, let problem = people.flow.readProblem {
            Section {
                ErrorNote(text: problem)
            }
        }
    }
}

/// Unlock People (the web's UnlockPeople.tsx): whose password, the field (the password manager's current password), Unlock
/// - on only with something typed and deadwax in reach - and what came of it; the plain-http note under it. Refused, the
/// field is emptied and takes the focus again (not under VoiceOver, where it would cut off what was just said).
struct PeopleUnlockSection: View {
    let user: String

    @Environment(PeopleModel.self) private var people
    @Environment(ServerModel.self) private var server
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @FocusState private var focused: Bool

    var body: some View {
        let flow = people.flow
        let busy = flow.writing(.unlock)
        Section {
            PeopleLine(text: People.unlockLine(user), quiet: true)
            SecureField(People.unlockLabel, text: people.typing(\.unlockPassword, at: .unlock))
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { people.unlock() }
                .disabled(flow.writing != nil)
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
                }
            }
            .disabled(!flow.canUnlock(online: people.online, signInOver: people.signInOver))
            if let said = flow.said(at: .unlock) {
                PeopleSaidView(said: said)
            }
        } header: {
            Text(People.unlockTitle)
                .font(Typeface.footnote)
        } footer: {
            if let note = People.httpNote(at: server.address) {
                Text(note)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: flow.focusUnlock) { _, _ in
            if !voiceOver { focused = true }
        }
    }
}

/// Who someone is (a row of Everyone in Navidrome, the top of their page): their name, user name, chips, deadwax
/// sign-ins and library, and the warning when Navidrome gives them no library - read as one.
struct PersonFacts: View {
    let person: PeoplePerson

    var body: some View {
        let chips = People.chips(person)
        VStack(alignment: .leading, spacing: 3) {
            Text(person.name)
                .font(Typeface.body.weight(.semibold))
            Text(person.user)
                .font(Typeface.mono(.footnote))
                .foregroundStyle(Palette.quiet)
            if !chips.isEmpty {
                Text(chips.joined(separator: " · "))
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.accent)
            }
            Text(People.signInWords(person, now: Date().timeIntervalSince1970))
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
            Text(People.libraryWords(person))
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
            if let warning = People.librariesWarning(person) {
                Text(warning)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.amber)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// What a write said, as one element: done in green (and Made's warning in amber), or what went wrong in red and how to
/// fix it.
struct PeopleSaidView: View {
    let said: PeopleSaid

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(said.words)
                .foregroundStyle(said.problem ? Palette.danger : Palette.held)
            if let warning = said.warning {
                Text(warning)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.amber)
            }
            if let fix = said.fix {
                Text(fix)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// A line of People's words, wrapping at every size - footnote and quiet for what explains.
struct PeopleLine: View {
    let text: String
    var quiet = false

    var body: some View {
        Text(text)
            .font(quiet ? Typeface.footnote : Typeface.body)
            .foregroundStyle(quiet ? Palette.quiet : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
