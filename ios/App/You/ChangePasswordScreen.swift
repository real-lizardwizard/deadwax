import DeadwaxCore
import SwiftUI

/// Settings > Account > Change password (Phase 8, slice 10 - notes/ios-specs/phase8-managing.md 9; the web's
/// app/ChangePassword.tsx): your Navidrome password, changed by deadwax as you (POST /deadwax/me/password). Pushed from
/// Account, offered only with logins on and a Navidrome sign-in (Core's OwnPassword.changeOffered).
///
/// Top to bottom: the line saying whose password it is; Current password, New password and New password again (secure
/// fields the password manager knows - the current one's, then a new one's - no capitals, no autocorrection); under
/// them what's wrong as typed (People's rules for a new password, and not the one you have); then Change - on only when
/// the form is ready and deadwax is in reach, "Changing…" while it asks; then what came of it, announced once; and the
/// footer: on plain http the note that a password typed here crosses the network readable, and that Amperfy and other
/// apps need the new password too (from the start, so it is read before the change, not only after).
///
/// One change at a time (Core's OwnPasswordFlow takes its ticket synchronously in the tap), never sent again by itself.
/// While it is out the page can't be left by Back or a swipe, nor by its tab tapped again (AppNavigation): its answer is
/// said here. ServerModel.changeOwnPassword sends it and, when deadwax answers with this phone's new sign-in, keeps it
/// in the Keychain and hands it to the client at once. Every field is emptied once it changed, as the page goes, when
/// Now Playing comes over it, and when the sign-in comes over the app; a refusal keeps them to correct, the current one
/// emptied and focused when it was wrong. No password is ever logged, kept or put in an address: the fields live in
/// this page's state alone.
struct ChangePasswordScreen: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var flow = OwnPasswordFlow()
    @FocusState private var focused: Field?

    private enum Field: Hashable { case current, password, again }

    var body: some View {
        let user = server.me?.user ?? ""
        let offered = OwnPassword.changeOffered(server.me)
        // one Form whatever it shows: the page's shows and hides stay on one view
        Form {
            if offered || flow.changing || flow.said != nil {
                Section {
                    Text(OwnPassword.changeLine(user))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                fieldsSection(user)
                changeSection(user)
                if let said = flow.said {
                    saidSection(said)
                }
            }
        }
        .navigationTitle(OwnPassword.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.changing)
        .editOutOfReach(!reachability.online)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AlbumInfoWords.done) { focused = nil }
            }
        }
        .onChange(of: flow.changing) { _, changing in
            navigation.passwordChanging(changing)
        }
        .onChange(of: flow.focusCurrent) { _, _ in
            // deadwax said it isn't your current password: emptied, and the place to type it again - but not under
            // VoiceOver, where moving the focus would cut off what was just announced
            if !voiceOver { focused = .current }
        }
        .onChange(of: server.signInOver != nil) { _, over in
            if over { forget() }
        }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            // (review) Now Playing over the page: it went from view, so the fields go as they do when it goes
            if shown { forget() }
        }
        .onDisappear {
            forget()
        }
    }

    // MARK: the parts

    private func fieldsSection(_ user: String) -> some View {
        let problem = flow.problem(user: user)
        let note = OwnPassword.httpNote(at: server.address)
        return Section {
            SecureField(OwnPassword.currentLabel, text: typing(\.current))
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused, equals: .current)
                .onSubmit { focused = .password }
            SecureField(OwnPassword.newLabel, text: typing(\.password))
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused, equals: .password)
                .onSubmit { focused = .again }
            SecureField(OwnPassword.againLabel, text: typing(\.again))
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused, equals: .again)
                .onSubmit { change(user) }
            if let problem {
                // what's wrong as typed: read where it is, never announced at each key
                Text(problem)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let note {
                    Text(note)
                        .foregroundStyle(Palette.amber)
                }
                Text(OwnPassword.appsLine)
            }
            .font(Typeface.footnote)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func changeSection(_ user: String) -> some View {
        let on = flow.canChange(user: user, online: reachability.online, signInOver: server.signInOver != nil)
        return Section {
            Button {
                change(user)
            } label: {
                HStack(spacing: 8) {
                    if flow.changing {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(flow.changing ? OwnPassword.changing : OwnPassword.change)
                }
            }
            .disabled(!on)
        }
    }

    /// What came of the last change, as one element: done (and deadwax's warning), or what went wrong and how to fix it.
    @ViewBuilder private func saidSection(_ said: OwnPassword.Said) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                switch said {
                case .done(let words, let warning):
                    Text(words)
                        .foregroundStyle(Palette.held)
                    if let warning {
                        Text(warning)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.amber)
                    }
                case .problem(let words, let fix):
                    Text(words)
                        .foregroundStyle(Palette.danger)
                    if let fix {
                        Text(fix)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: what it does

    /// A field's binding: what is typed goes into the form, and clears what the last answer said (it was of the
    /// fields as they were) - the answer's own emptying of the fields doesn't come through here.
    private func typing(_ field: WritableKeyPath<OwnPasswordForm, String>) -> Binding<String> {
        Binding(
            get: { flow.form[keyPath: field] },
            set: { (typed: String) -> Void in
                flow.form[keyPath: field] = typed
                flow.typed()
            }
        )
    }

    /// Change pressed (or Done on the last field): the body and its ticket taken here, in the tap, before the Task - a
    /// second press finds one out. What came of it is announced once.
    private func change(_ user: String) {
        guard let (ticket, body) = flow.begin(user: user, online: reachability.online,
                                              signInOver: server.signInOver != nil) else {
            return
        }
        focused = nil
        Task {
            let outcome = await server.changeOwnPassword(body)
            // (review) nothing announced when the sign-in came over the app as it answered: the sign-in says it
            let words = flow.ended(ticket, outcome, signInOver: server.signInOver != nil, device: Platform.device)
            // told here too, not only by onChange: the answer may come while the page is off screen (another tab)
            navigation.passwordChanging(flow.changing)
            if let words {
                Notice.announce(words)
            }
        }
    }

    /// Every field emptied and nothing said kept: the page went, or the sign-in came over the app.
    private func forget() {
        focused = nil
        flow.hidden()
    }
}
