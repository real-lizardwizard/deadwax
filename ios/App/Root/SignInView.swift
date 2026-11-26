import DeadwaxCore
import SwiftUI

/// The sign-in (screens.md 3, the web's app/SignIn.tsx): alone at launch after a 401, or OVER the app when a session
/// ended mid-use - the app inert under it and the music playing on, since nothing here touches the player.
///
/// (The redesign, slice R9 - iSignIn; the build plan's section 8: "Sign in is one screen, as drawn, over today's two
/// screens' calls") One screen for where deadwax is and who you are, the Server address screen's calls and the
/// sign-in's in today's order: Check first - ServerModel.checkAddress, /health and then /me, exactly the Server address
/// screen's - and only once deadwax has answered at the address shown and asked for a sign-in, Sign in -
/// ServerModel.signIn (Core's SignInGate). RootView keeps this one screen up through its own Check - the launch's
/// `.checking` while it asks - so what is typed stays; with logins off, Check alone lets you in. A Check that can't
/// reach deadwax says so here, under the address, in Phase 0's words (CheckReport.lines), as the Server address screen
/// did; deadwax answering with something else than a sign-in's 401 is the can't-reach screen, as before.
///
/// Top to bottom: "deadwax" and the lede; Where deadwax is - the address (its own box) and Check, then what Check
/// found, or the green "deadwax answered", and the local network's note; Who you are - the user name and the password
/// (the password manager fills both; the app never keeps the password); why it is showing (`reason`, with `reasonWhy`
/// folded for whoever runs deadwax); what went wrong (announced) with its own fold; Sign in, the purple button across
/// the page; and where the sign-in is kept. Every rule of the form is Core's SignInForm: the name trimmed, the password
/// cleared after any answer, nothing sent with a field empty, "Signing in…" while asking, the reason never said twice.
///
/// Over the app the address is the one in use, said and not typed: signing in to another deadwax there would change the
/// server under the app (the Server address screen, from This phone, does that). Each field stays a box (FieldLook).
struct SignInView: View {
    let reason: String?
    let reasonWhy: String?

    @Environment(ServerModel.self) private var server
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var form = SignInForm()
    /// The address as typed, handed to ServerModel at Check (the Server address screen's `typed`).
    @State private var typed = ""
    /// Check pressed on this screen: only then is what it found shown.
    @State private var checked = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case address, username, password }

    init(reason: String?, reasonWhy: String?) {
        self.reason = reason
        self.reasonWhy = reasonWhy
    }

    /// Over the app (a session ended mid-use), not the launch's own screen.
    private var over: Bool { server.launch == .ready }

    /// deadwax answered at the address in use and asked for a sign-in: the launch's 401, or a session ended under the app.
    private var asksSignIn: Bool {
        if over { return server.signInOver != nil }
        if case .signedOut = server.launch { return true }
        return false
    }

    /// The address Sign in would go to, as shown: over the app the one in use, else what is typed.
    private var shownAddress: String { over ? (server.address?.description ?? "") : typed }

    /// (R9's review) The field to start in: the first one empty - the address (none over the app), the user name, the
    /// password - and with all of them filled, the address at the launch (Check is next), the password over the app.
    private var firstEmpty: Field {
        if !over && typed.isEmpty { return .address }
        if form.username.isEmpty { return .username }
        if form.password.isEmpty { return .password }
        return over ? .password : .address
    }

    var body: some View {
        let lines = form.lines(reason: reason, reasonWhy: reasonWhy)
        let signInOn = SignInGate.signInOn(asksSignIn: asksSignIn, typed: shownAddress, inUse: server.address,
                                           checking: server.checkingAddress, busy: lines.disabled)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                PhoneGroup(legend: SettingsWords.whereTitle) {
                    whereCard
                }
                PhoneGroup(legend: SettingsWords.whoTitle) {
                    fields
                }
                if let said = lines.reason {
                    SettingsNote(words: said, colour: DWPalette.amberText)
                    if let why = lines.reasonWhy { whoever(why) }
                }
                if let problem = lines.problem {
                    SettingsNote(words: problem, colour: DWPalette.redChipText)
                    if let why = lines.problemWhy { whoever(why) }
                }
                Button {
                    submit()
                } label: {
                    // (R9's review) "Signing in…" on up to three lines at the accessibility sizes
                    Text(lines.button)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
                .disabled(!signInOn)
                .padding(.top, CGFloat(PhoneLook.groupAbove))
                Text(SettingsWords.kept(Platform.device))
                    .font(Typeface.Phone.text(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, SettingsLook.fieldGap)
            }
            .padding(.horizontal, CGFloat(PhoneLook.bigSide))
            .padding(.bottom, CGFloat(PhoneLook.groupAbove))
            .frame(maxWidth: SignInLook.width)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // what ServerModel holds: the saved address, or the one Change address put back
            typed = server.addressText.isEmpty ? (server.address?.description ?? "") : server.addressText
            // the one thing to do first takes focus as the screen comes up - (R9's review) the first field empty - and
            // the reason is read out with it (the web's dialog description), since VoiceOver goes to the field
            DispatchQueue.main.async { focused = firstEmpty }
            if let said = lines.reason { Notice.announce(said) }
        }
        .onChange(of: lines.problem) { _, problem in
            if let problem { Notice.announce(problem) }
        }
        .onChange(of: server.addressReport) { _, report in
            if checked, let line = report?.lines(Platform.device).first { Notice.announce(line) }
        }
        .onChange(of: asksSignIn) { _, asks in
            // Check answered and deadwax asks who you are: (R9's review) the first of the two still empty is next - the
            // password with both filled, where Return now signs in
            if asks, checked { focused = form.username.isEmpty ? .username : .password }
        }
    }

    private var head: some View {
        VStack(spacing: 6) {
            Text(SignInWords.title)
                .font(Typeface.Phone.text(.big).weight(.bold))
                .foregroundStyle(DWPalette.text)
                .accessibilityAddTraits(.isHeader)
            Text(SignInWords.lede)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SignInLook.headAbove)
    }

    /// Where deadwax is: the address and Check (the Server address screen's), what Check found, the local network's note.
    @ViewBuilder private var whereCard: some View {
        if over {
            PhoneKV(label: SettingsWords.address, value: server.address?.description ?? "", mono: true)
        } else {
            VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                // (R9's review) Check - flat words, no box of its own - on the address's first text baseline; at the
                // accessibility sizes under the field, which keeps the page's width
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
                        addressField
                        checkButton
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: SettingsLook.fieldGap) {
                        addressField
                        checkButton
                    }
                }
                if checked, let report = server.addressReport {
                    ForEach(report.lines(Platform.device), id: \.self) { line in
                        Text(line)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                } else if SignInGate.answered(asksSignIn: asksSignIn, typed: typed, inUse: server.address,
                                              checking: server.checkingAddress) {
                    DWChip(words: SettingsWords.answered, tone: .good)
                }
                Text(AddressWords.footer(Platform.device))
                    .font(Typeface.Phone.text(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, SettingsLook.fieldGap)
        }
    }

    private var addressField: some View {
        TextField(SettingsWords.addressExample, text: $typed)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focused, equals: .address)
            .onSubmit { check() }
            .font(Typeface.Phone.mono(.row))
            .modifier(FieldLook(focused: focused == .address))
            .accessibilityLabel(SettingsWords.address)
    }

    private var checkButton: some View {
        Button(server.checkingAddress ? SettingsWords.checking : SettingsWords.check) { check() }
            .buttonStyle(DWButtonStyle())
            .disabled(server.checkingAddress)
    }

    /// Who you are: the user name and the password, each its own box, its name over it.
    private var fields: some View {
        VStack(alignment: .leading, spacing: SettingsLook.fieldGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SignInWords.userName)
                    .font(Typeface.Phone.text(.small).weight(.medium))
                    .foregroundStyle(DWPalette.t2)
                    .accessibilityHidden(true)
                TextField("", text: $form.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .username)
                    .onSubmit { focused = .password }
                    .modifier(FieldLook(focused: focused == .username))
                    .accessibilityLabel(SignInWords.userName)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(SignInWords.password)
                    .font(Typeface.Phone.text(.small).weight(.medium))
                    .foregroundStyle(DWPalette.t2)
                    .accessibilityHidden(true)
                SecureField("", text: $form.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focused, equals: .password)
                    .onSubmit { returned() }
                    .modifier(FieldLook(focused: focused == .password))
                    .accessibilityLabel(SignInWords.password)
            }
        }
        .padding(.vertical, SettingsLook.fieldGap)
    }

    private func whoever(_ words: String) -> some View {
        DisclosureGroup(ErrorWords.forWhoever) {
            Text(words)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
        .font(Typeface.Phone.text(.small))
        .tint(DWPalette.acc)
        .padding(.top, SettingsLook.noteAbove)
    }

    // MARK: what it does

    /// Check (the Server address screen's): the address typed handed to ServerModel, which asks /health and, when
    /// deadwax answers, saves it and goes on from /me - a sign-in asked for, the app, or the can't-reach screen.
    private func check() {
        guard !over, !server.checkingAddress else { return }
        checked = true
        focused = nil
        server.addressText = typed
        Task {
            _ = await server.checkAddress()
            typed = server.addressText
        }
    }

    /// (R9's review) Return in the password: what the button that is on would do - Sign in once Check has answered for
    /// the address shown, Check until then (SignInGate.returnSignsIn).
    private func returned() {
        if SignInGate.returnSignsIn(asksSignIn: asksSignIn, typed: shownAddress, inUse: server.address) {
            submit()
        } else {
            check()
        }
    }

    /// Sign in: only once Check has answered for the address shown (SignInGate) - the form's body taken here, in the tap.
    private func submit() {
        let lines = form.lines(reason: reason, reasonWhy: reasonWhy)
        guard SignInGate.signInOn(asksSignIn: asksSignIn, typed: shownAddress, inUse: server.address,
                                  checking: server.checkingAddress, busy: lines.disabled),
              let body = form.submit() else { return }
        focused = nil
        Task {
            if let problem = await server.signIn(name: body.username, password: body.password) {
                form.failed(problem.error)
            } else {
                form.signedIn()
            }
        }
    }
}

/// The sign-in's measures (iSignIn): the page's widest (the old screen's 440, for a Mac window or an iPad's), and the
/// room above "deadwax" (`padding: 84px 16px 0`, less the status bar's).
private enum SignInLook {
    static let width: CGFloat = 440
    static let headAbove: CGFloat = 40
}

/// A field you type in on the sign-in, the Server address screen and Change password: its own box - the look's well's
/// fill and an edge, the accent's while it has the cursor - its text never smaller than the body's. An address is in the
/// readout face: set on its field, before this, where the readout rule can see it beside Check.
struct FieldLook: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .font(Typeface.body)
            .foregroundStyle(DWPalette.fieldText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DWPalette.well, in: DWCorners.buttonShape)
            .overlay(DWCorners.buttonShape.strokeBorder(focused ? DWPalette.acc : DWPalette.line, lineWidth: 1))
    }
}
