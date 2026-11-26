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
/// notes: on plain http the note that a password typed here crosses the network readable, and that Amperfy and other
/// apps need the new password too (from the start, so it is read before the change, not only after).
///
/// (The redesign, slice R9) Flat, a Settings page (SettingsPage) with no Form: each field still a box - the sign-in's
/// own (FieldLook, the look's well under it, its edge the accent's while focused) - and Change the purple button across
/// the page (the build plan's 3.6: the small sheets take the shared buttons and fields in R9).
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var flow = OwnPasswordFlow()
    @FocusState private var focused: Field?

    private enum Field: Hashable { case current, password, again }

    var body: some View {
        let user = server.me?.user ?? ""
        let offered = OwnPassword.changeOffered(server.me)
        // one page whatever it shows: the page's shows and hides stay on one view
        SettingsPage {
            if offered || flow.changing || flow.said != nil {
                SettingsNote(words: OwnPassword.changeLine(user))
                fieldsGroup(user)
                changeButton(user)
                if let said = flow.said {
                    saidNote(said)
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

    private func fieldsGroup(_ user: String) -> some View {
        let problem = flow.problem(user: user)
        let note = OwnPassword.httpNote(at: server.address)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                SecureField(OwnPassword.currentLabel, text: typing(\.current))
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .current)
                    .onSubmit { focused = .password }
                    .modifier(FieldLook(focused: focused == .current))
                SecureField(OwnPassword.newLabel, text: typing(\.password))
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .password)
                    .onSubmit { focused = .again }
                    .modifier(FieldLook(focused: focused == .password))
                SecureField(OwnPassword.againLabel, text: typing(\.again))
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused, equals: .again)
                    .onSubmit { change(user) }
                    .modifier(FieldLook(focused: focused == .again))
            }
            .padding(.top, CGFloat(PhoneLook.groupAbove) / 2)
            if let problem {
                // what's wrong as typed: read where it is, never announced at each key
                SettingsNote(words: problem)
            }
            if let note {
                SettingsNote(words: note, colour: DWPalette.amberText)
            }
            Text(OwnPassword.appsLine)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SettingsLook.noteAbove)
        }
    }

    private func changeButton(_ user: String) -> some View {
        let on = flow.canChange(user: user, online: reachability.online, signInOver: server.signInOver != nil)
        return Button {
            change(user)
        } label: {
            HStack(spacing: 8) {
                if flow.changing {
                    ProgressView()
                        .accessibilityHidden(true)
                }
                // (R9's review) the button's words on up to three lines at the accessibility sizes
                Text(flow.changing ? OwnPassword.changing : OwnPassword.change)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
        .disabled(!on)
        .padding(.top, CGFloat(PhoneLook.groupAbove))
    }

    /// What came of the last change, as one element: done (and deadwax's warning), or what went wrong and how to fix it.
    @ViewBuilder private func saidNote(_ said: OwnPassword.Said) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch said {
            case .done(let words, let warning):
                Text(words)
                    .foregroundStyle(DWPalette.greenText)
                if let warning {
                    Text(warning)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.amberText)
                }
            case .problem(let words, let fix):
                Text(words)
                    .foregroundStyle(DWPalette.redChipText)
                if let fix {
                    Text(fix)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
            }
        }
        .font(Typeface.Phone.text(.row))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CGFloat(PhoneLook.groupAbove) / 2)
        .accessibilityElement(children: .combine)
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
