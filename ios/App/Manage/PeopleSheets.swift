import DeadwaxCore
import SwiftUI

/// Add a person (Phase 8, slice 11; the web's AddPerson.tsx), a sheet from People's +: a Navidrome account for an
/// ordinary listener. User name, display name (optional) and the password twice - no capitals, no autocorrection, each
/// clipped as typed to a little past what its rule allows; what's wrong as typed under them (people.ts formProblem);
/// Make account, on only when every rule is met and the list is to be trusted; then what came of it - Made's words, with
/// deadwax's address to tell them, and the server's warning - or the refusal and its fix. The plain-http note under the
/// fields. Made, the form is emptied and Close says Done. People locked again under it, the names stay, the passwords
/// go, and it says to close and unlock. While Make is out, neither Close nor a swipe closes it.
struct AddPersonSheet: View {
    @Environment(PeopleModel.self) private var people
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @FocusState private var focused: Field?

    private enum Field: Hashable { case user, name, password, again }

    var body: some View {
        let flow = people.flow
        let writing = flow.writing(.create)
        let said = flow.said(at: .add)
        let made = said.map { !$0.problem } ?? false
        NavigationStack {
            Form {
                Section {
                    PeopleLine(text: People.addLine, quiet: true)
                }
                Section {
                    TextField(People.userLabel, text: people.typing(\.add.user, at: .add, most: People.userField))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .user)
                        .onSubmit { focused = .name }
                    TextField(People.displayLabel, text: people.typing(\.add.name, at: .add, most: People.displayField))
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .onSubmit { focused = .password }
                    SecureField(People.passwordLabel,
                                text: people.typing(\.add.password, at: .add, most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .password)
                        .onSubmit { focused = .again }
                    SecureField(People.againLabel, text: people.typing(\.add.again, at: .add, most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused, equals: .again)
                        .onSubmit { focused = nil }
                    if let problem = People.formProblem(flow.add) {
                        // what's wrong as typed: read where it is, never announced at each key
                        PeopleLine(text: problem, quiet: true)
                    }
                } footer: {
                    if let note = People.httpNote(at: server.address) {
                        Text(note)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(writing)
                Section {
                    Button {
                        focused = nil
                        people.create()
                    } label: {
                        HStack(spacing: 8) {
                            if writing {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                            Text(writing ? People.making : People.make)
                        }
                    }
                    .disabled(!flow.canCreate(online: reachability.online, signInOver: people.signInOver))
                }
                if let said {
                    Section {
                        PeopleSaidView(said: said)
                    }
                }
                if flow.view != .list {
                    Section {
                        PeopleLine(text: People.lockedNote, quiet: true)
                    }
                }
            }
            .navigationTitle(People.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .editOutOfReach(!reachability.online)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(made ? People.done : People.close) {
                        people.closed()
                    }
                    .disabled(writing)
                    // (the Mac app, slice 2) Escape is Close only with no password typed: Close forgets them without
                    // asking (PeopleFlow.closed - the names it keeps)
                    .escapeCloses(flow.add.password.isEmpty && flow.add.again.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AlbumInfoWords.done) { focused = nil }
                }
            }
        }
        .interactiveDismissDisabled(flow.writing != nil)
    }
}

/// Reset password… (the web's ResetPassword.tsx), a sheet from a person's page: the new password twice (the password
/// manager's new-password fields), what's wrong as typed, Reset password - on only when People's rules for a password are
/// met - and what went wrong. Done, the sheet goes and their page says they are signed out of deadwax and sign in with
/// it. The plain-http note under the fields. People locked again under it, the passwords go and it says to close and
/// unlock. While Reset is out, neither Cancel nor a swipe closes it.
struct ResetPasswordSheet: View {
    let id: String

    @Environment(PeopleModel.self) private var people
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    /// Whom it was opened for - kept, as People locked again lists nobody.
    @State private var opened: PeoplePerson?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case password, again }

    init(id: String, person: PeoplePerson?) {
        self.id = id
        _opened = State(initialValue: person)
    }

    var body: some View {
        let flow = people.flow
        let person = flow.person(id)
        let user = person?.user ?? opened?.user ?? ""
        let writing = flow.writing(.reset, for: id)
        NavigationStack {
            Form {
                Section {
                    SecureField(People.newPasswordLabel,
                                text: people.typing(\.resetPasswords.password, at: .reset(id), most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .password)
                        .onSubmit { focused = .again }
                    SecureField(People.newAgainLabel,
                                text: people.typing(\.resetPasswords.again, at: .reset(id), most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused, equals: .again)
                        .onSubmit { focused = nil }
                    if let problem = People.resetProblem(flow.resetPasswords, user: user) {
                        PeopleLine(text: problem, quiet: true)
                    }
                } footer: {
                    if let note = People.httpNote(at: server.address) {
                        Text(note)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(writing)
                Section {
                    Button {
                        focused = nil
                        if let person { people.resetPassword(person) }
                    } label: {
                        HStack(spacing: 8) {
                            if writing {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                            Text(writing ? People.resetting : People.resetButton)
                        }
                    }
                    .disabled(person.map {
                        !flow.canReset($0, online: reachability.online, signInOver: people.signInOver)
                    } ?? true)
                }
                if let said = flow.said(at: .reset(id)) {
                    Section {
                        PeopleSaidView(said: said)
                    }
                }
                if flow.view != .list {
                    Section {
                        PeopleLine(text: People.lockedNote, quiet: true)
                    }
                } else if person == nil {
                    Section {
                        PeopleLine(text: People.gone, quiet: true)
                    }
                }
            }
            .navigationTitle(People.resetTitle(user))
            .navigationBarTitleDisplayMode(.inline)
            .editOutOfReach(!reachability.online)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(People.cancel) {
                        people.closed()
                    }
                    .disabled(writing)
                    // (the Mac app, slice 2) Escape is Cancel only with nothing typed: Cancel forgets the passwords
                    // without asking
                    .escapeCloses(flow.resetPasswords.password.isEmpty && flow.resetPasswords.again.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AlbumInfoWords.done) { focused = nil }
                }
            }
        }
        .interactiveDismissDisabled(flow.writing != nil)
    }
}

/// Remove… (the web's RemovePerson.tsx), a sheet from a person's page: what goes - in Navidrome, for good; in deadwax -
/// what stays, and that there's no undo; then their user name typed exactly (no capitals, no autocorrection; Return
/// never removes), and Remove {name}, destructive, on only once it matches. Removed, the sheet and their page go and
/// People says so. People locked again under it, what was typed stays and it says to close and unlock. While Remove is
/// out, neither Cancel nor a swipe closes it.
struct RemovePersonSheet: View {
    let id: String

    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    /// Whom it was opened for - kept, as People locked again lists nobody.
    @State private var opened: PeoplePerson?
    @FocusState private var focused: Bool

    init(id: String, person: PeoplePerson?) {
        self.id = id
        _opened = State(initialValue: person)
    }

    var body: some View {
        let flow = people.flow
        let person = flow.person(id)
        let shown = person ?? opened
        let user = shown?.user ?? ""
        let writing = flow.writing(.remove, for: id)
        NavigationStack {
            Form {
                if let shown {
                    let lines = People.removeLines(shown)
                    Section {
                        PeopleLine(text: lines.navidrome)
                        PeopleLine(text: lines.deadwax)
                        PeopleLine(text: lines.stays)
                        Text(lines.undo)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    TextField(People.typeTheName, text: people.typing(\.removeTyped, at: .remove(id)))
                        .font(Typeface.mono(.body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        // Return only puts the keyboard away: removing is the button's alone
                        .onSubmit { focused = false }
                        .accessibilityLabel(People.typeTheName)
                        .disabled(writing)
                    Button(role: .destructive) {
                        focused = false
                        if let person { people.remove(person) }
                    } label: {
                        HStack(spacing: 8) {
                            if writing {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                            Text(writing ? People.removing : People.removeButton(user))
                        }
                    }
                    .disabled(person.map {
                        !flow.canRemove($0, online: reachability.online, signInOver: people.signInOver)
                    } ?? true)
                }
                if let said = flow.said(at: .remove(id)) {
                    Section {
                        PeopleSaidView(said: said)
                    }
                }
                if flow.view != .list {
                    Section {
                        PeopleLine(text: People.lockedNote, quiet: true)
                    }
                } else if person == nil {
                    Section {
                        PeopleLine(text: People.gone, quiet: true)
                    }
                }
            }
            .navigationTitle(People.removeTitle(user))
            .navigationBarTitleDisplayMode(.inline)
            .editOutOfReach(!reachability.online)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(People.cancel) {
                        people.closed()
                    }
                    .disabled(writing)
                    .escapeCloses()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AlbumInfoWords.done) { focused = false }
                }
            }
        }
        .interactiveDismissDisabled(flow.writing != nil)
    }
}
