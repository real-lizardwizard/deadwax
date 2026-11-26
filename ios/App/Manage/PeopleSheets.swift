import DeadwaxCore
import SwiftUI

/// Add a person (Phase 8, slice 11; the web's AddPerson.tsx), a sheet from People's +: a Navidrome account for an
/// ordinary listener. User name, display name (optional) and the password twice - no capitals, no autocorrection, each
/// clipped as typed to a little past what its rule allows; what's wrong as typed under them (people.ts formProblem);
/// Make account, on only when every rule is met and the list is to be trusted; then what came of it - Made's words, with
/// deadwax's address to tell them, and the server's warning - or the refusal and its fix. The plain-http note under the
/// fields. Made, the form is emptied and Close says Done. People locked again under it, the names stay, the passwords
/// go, and it says to close and unlock. While Make is out, neither Close nor a swipe closes it.
///
/// (The redesign, slice R14 - notes/ios.md "The redesign, slice R14: People and Server settings") Flat, as Change
/// password is (R9): no Form - each field a box (PeopleField: the sign-in's own FieldLook on the phone, the Mac's own
/// field on the Mac), Make account the purple button; on the page's black on the phone (PeopleSheetPage), the Mac's
/// ground and sizes in its own window.
struct AddPersonSheet: View {
    @Environment(PeopleModel.self) private var people
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Field?

    private enum Field: Hashable { case user, name, password, again }

    /// (The Mac app, slice 7) The fields in the order the sheet draws them: Tab's on the Mac.
    private static let order: [Field] = [.user, .name, .password, .again]

    var body: some View {
        let flow = people.flow
        let writing = flow.writing(.create)
        let said = flow.said(at: .add)
        let made = said.map { !$0.problem } ?? false
        NavigationStack {
            PeopleSheetPage {
                PeopleLine(text: People.addLine, quiet: true)
                VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                    TextField(People.userLabel, text: people.typing(\.add.user, at: .add, most: People.userField))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .user)
                        .tabs($focused, in: Self.order)
                        .onSubmit { focused = .name }
                        .modifier(PeopleField(focused: focused == .user))
                    TextField(People.displayLabel, text: people.typing(\.add.name, at: .add, most: People.displayField))
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .tabs($focused, in: Self.order)
                        .onSubmit { focused = .password }
                        .modifier(PeopleField(focused: focused == .name))
                    SecureField(People.passwordLabel,
                                text: people.typing(\.add.password, at: .add, most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .password)
                        .tabs($focused, in: Self.order)
                        .onSubmit { focused = .again }
                        .modifier(PeopleField(focused: focused == .password))
                    SecureField(People.againLabel, text: people.typing(\.add.again, at: .add, most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused, equals: .again)
                        .tabs($focused, in: Self.order)
                        .onSubmit { focused = nil }
                        .modifier(PeopleField(focused: focused == .again))
                }
                .disabled(writing)
                if let problem = People.formProblem(flow.add) {
                    // what's wrong as typed: read where it is, never announced at each key
                    PeopleLine(text: problem, quiet: true)
                }
                if let note = People.httpNote(at: server.address) {
                    ManageNote(words: note, colour: DWPalette.amberText)
                }
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
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
                .disabled(!flow.canCreate(online: reachability.online, signInOver: people.signInOver))
                if let said {
                    PeopleSaidView(said: said)
                }
                if flow.view != .list {
                    PeopleLine(text: People.lockedNote, quiet: true)
                }
            }
            .navigationTitle(People.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .editOutOfReach(!reachability.online)
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
        .presentationBackground(ManageLook.sheetGround)
    }
}

/// Reset password… (the web's ResetPassword.tsx), a sheet from a person's page: the new password twice (the password
/// manager's new-password fields), what's wrong as typed, Reset password - on only when People's rules for a password are
/// met - and what went wrong. Done, the sheet goes and their page says they are signed out of deadwax and sign in with
/// it. The plain-http note under the fields. People locked again under it, the passwords go and it says to close and
/// unlock. While Reset is out, neither Cancel nor a swipe closes it. (R14) Flat, its fields boxes, Reset the purple one.
struct ResetPasswordSheet: View {
    let id: String

    @Environment(PeopleModel.self) private var people
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Whom it was opened for - kept, as People locked again lists nobody.
    @State private var opened: PeoplePerson?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case password, again }

    /// (The Mac app, slice 7) The fields in the order the sheet draws them: Tab's on the Mac.
    private static let order: [Field] = [.password, .again]

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
            PeopleSheetPage {
                VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                    SecureField(People.newPasswordLabel,
                                text: people.typing(\.resetPasswords.password, at: .reset(id), most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .password)
                        .tabs($focused, in: Self.order)
                        .onSubmit { focused = .again }
                        .modifier(PeopleField(focused: focused == .password))
                    SecureField(People.newAgainLabel,
                                text: people.typing(\.resetPasswords.again, at: .reset(id), most: People.passwordField))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused, equals: .again)
                        .tabs($focused, in: Self.order)
                        .onSubmit { focused = nil }
                        .modifier(PeopleField(focused: focused == .again))
                }
                .disabled(writing)
                if let problem = People.resetProblem(flow.resetPasswords, user: user) {
                    PeopleLine(text: problem, quiet: true)
                }
                if let note = People.httpNote(at: server.address) {
                    ManageNote(words: note, colour: DWPalette.amberText)
                }
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
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
                .disabled(person.map {
                    !flow.canReset($0, online: reachability.online, signInOver: people.signInOver)
                } ?? true)
                if let said = flow.said(at: .reset(id)) {
                    PeopleSaidView(said: said)
                }
                if flow.view != .list {
                    PeopleLine(text: People.lockedNote, quiet: true)
                } else if person == nil {
                    PeopleLine(text: People.gone, quiet: true)
                }
            }
            .navigationTitle(People.resetTitle(user))
            .navigationBarTitleDisplayMode(.inline)
            .editOutOfReach(!reachability.online)
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
        .presentationBackground(ManageLook.sheetGround)
    }
}

/// Remove… (the web's RemovePerson.tsx), a sheet from a person's page: what goes - in Navidrome, for good; in deadwax -
/// what stays, and that there's no undo; then their user name typed exactly (no capitals, no autocorrection; Return
/// never removes), and Remove {name}, destructive, on only once it matches. Removed, the sheet and their page go and
/// People says so. People locked again under it, what was typed stays and it says to close and unlock. While Remove is
/// out, neither Cancel nor a swipe closes it. (R14) Flat, the name's field a box, Remove the red one.
struct RemovePersonSheet: View {
    let id: String

    @Environment(PeopleModel.self) private var people
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize
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
            PeopleSheetPage {
                if let shown {
                    let lines = People.removeLines(shown)
                    VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                        PeopleLine(text: lines.navidrome)
                        PeopleLine(text: lines.deadwax)
                        PeopleLine(text: lines.stays)
                        Text(lines.undo)
                            .font(Typeface.Look.text(.field))
                            .foregroundStyle(DWPalette.redChipText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                TextField(People.typeTheName, text: people.typing(\.removeTyped, at: .remove(id)))
                    .font(Typeface.Look.mono(.field))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    // Return only puts the keyboard away: removing is the button's alone
                    .onSubmit { focused = false }
                    .accessibilityLabel(People.typeTheName)
                    .disabled(writing)
                    .modifier(PeopleField(focused: focused))
                Button {
                    focused = false
                    if let person { people.remove(person) }
                } label: {
                    HStack(spacing: 8) {
                        if writing {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                        Text(writing ? People.removing : People.removeButton(user))
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(DWButtonStyle(kind: .danger, size: .large, fills: true))
                .disabled(person.map {
                    !flow.canRemove($0, online: reachability.online, signInOver: people.signInOver)
                } ?? true)
                if let said = flow.said(at: .remove(id)) {
                    PeopleSaidView(said: said)
                }
                if flow.view != .list {
                    PeopleLine(text: People.lockedNote, quiet: true)
                } else if person == nil {
                    PeopleLine(text: People.gone, quiet: true)
                }
            }
            .navigationTitle(People.removeTitle(user))
            .navigationBarTitleDisplayMode(.inline)
            .editOutOfReach(!reachability.online)
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
        .presentationBackground(ManageLook.sheetGround)
    }
}

/// (R14) A People sheet's page, flat: its parts down the page 12 apart, 16 in from each edge (Change password's), the
/// keyboard put away by a drag - on the page's black on the phone (no sheet's grey behind it, as the manual search's),
/// the Mac's own ground in its window. (R14's review) On the Mac its words at the Mac's size (the field's 13): what a
/// write said, and anything else that sets no size of its own, would take the sheet root's 17 otherwise.
struct PeopleSheetPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLook.cardGap) {
                content
            }
            .padding(.horizontal, ManageLook.side)
            .padding(.vertical, SettingsLook.cardGap)
            .modifier(ManageMacText())
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ManageLook.sheetGround.ignoresSafeArea())
    }
}

/// (R14's review) On the Mac, words that set no size of their own at the Mac's (Typeface.Look's field, 13); on the phone
/// nothing - they keep the size they take there.
struct ManageMacText: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if Platform.mac {
            content
                .font(Typeface.Look.text(.field))
        } else {
            content
        }
    }
}
