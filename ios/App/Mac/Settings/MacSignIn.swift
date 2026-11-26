import DeadwaxCore
import SwiftUI

/// The Mac's sign-in (the redesign, slice R9 - SignIn.dc.html; notes/ios.md "The redesign, slice R9"): one dialog, 440
/// wide in the window, for where deadwax is and who you are - RootView's `Platform.mac` branch draws it wherever the
/// iPhone draws its one screen (SignInView): no address yet, a sign-in asked for, through its own Check, and over the
/// app when a session ended under it. The same calls in the same order: Check - ServerModel.checkAddress, /health then
/// /me, saving the address once deadwax answered - and only once deadwax has answered at the address shown and asked for
/// a sign-in, Sign in - ServerModel.signIn (Core's SignInGate, SignInForm's every rule). A Check that can't reach
/// deadwax says so in the dialog, in Phase 0's words (CheckReport.lines); deadwax answering otherwise than with a
/// sign-in's 401 is the can't-reach screen, as before; with logins off Check alone opens the app.
///
/// Top to bottom: the wordmark and the lede; Where deadwax is - the address and Check, then what Check found, or the
/// green "deadwax answered" with the local network's note; Who you are - Name and Password, each a field in its well
/// (DWFieldRow's label at its left); why it shows and what went wrong, each with its fold for whoever runs deadwax; and
/// the foot - where the sign-in is kept (a file on this Mac) and Sign in, the purple button. Return in the address is
/// Check, Return in the password what the button that is on would do - Sign in once Check has answered, Check until
/// then (SignInGate.returnSignsIn) - and no default button: Return never confirms in the app. Over the app the address
/// is said, not typed: another deadwax there would change the server under the app. (R9's review) In a scroll view,
/// centred while it fits, so a short window or large text never loses Sign in under the window's foot; the first empty
/// field has the cursor as it comes up.
struct MacSignIn: View {
    let reason: String?
    let reasonWhy: String?

    @Environment(ServerModel.self) private var server
    @State private var form = SignInForm()
    @State private var typed = ""
    @State private var checked = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case address, username, password }

    private static let width: CGFloat = 440
    private static let side: CGFloat = 24

    init(reason: String?, reasonWhy: String?) {
        self.reason = reason
        self.reasonWhy = reasonWhy
    }

    private var over: Bool { server.launch == .ready }

    private var asksSignIn: Bool {
        if over { return server.signInOver != nil }
        if case .signedOut = server.launch { return true }
        return false
    }

    private var shownAddress: String { over ? (server.address?.description ?? "") : typed }

    /// (R9's review) The field to start in: the first one empty - the address (none over the app), the name, the
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
        GeometryReader { (room: GeometryProxy) in
            ScrollView {
                dialog(lines, signInOn: signInOn)
                    .padding(.vertical, Self.side)
                    .frame(maxWidth: .infinity, minHeight: room.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(DWPalette.bg)
        .onAppear {
            typed = server.addressText.isEmpty ? (server.address?.description ?? "") : server.addressText
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
            if asks, checked { focused = form.username.isEmpty ? .username : .password }
        }
    }

    /// The dialog itself, 440 wide.
    private func dialog(_ lines: SignInLines, signInOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SignInWords.title)
                    .font(Typeface.Mac.text(.h1).weight(.bold))
                    .foregroundStyle(DWPalette.head)
                    .accessibilityAddTraits(.isHeader)
                Text(SignInWords.lede)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 22, leading: Self.side, bottom: 4, trailing: Self.side))
            VStack(alignment: .leading, spacing: 24) {
                MacGroupBox(legend: SettingsWords.whereTitle) {
                    whereBox
                }
                MacGroupBox(legend: SettingsWords.whoTitle) {
                    VStack(alignment: .leading, spacing: 4) {
                        DWFieldRow(label: SignInWords.userName) {
                            TextField("", text: $form.username)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .focused($focused, equals: .username)
                                .onSubmit { focused = .password }
                                .font(Typeface.Look.text(.field))
                                .modifier(MacSignInField(focused: focused == .username))
                        }
                        DWFieldRow(label: SignInWords.password) {
                            SecureField("", text: $form.password)
                                .textContentType(.password)
                                .focused($focused, equals: .password)
                                .onSubmit { returned() }
                                .font(Typeface.Look.text(.field))
                                .modifier(MacSignInField(focused: focused == .password))
                        }
                    }
                }
                if lines.reason != nil || lines.problem != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if let said = lines.reason {
                            Text(said).foregroundStyle(DWPalette.amberText)
                            if let why = lines.reasonWhy { whoever(why) }
                        }
                        if let problem = lines.problem {
                            Text(problem).foregroundStyle(DWPalette.redChipText)
                            if let why = lines.problemWhy { whoever(why) }
                        }
                    }
                    .font(Typeface.Mac.text(.small))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 24, leading: Self.side, bottom: 22, trailing: Self.side))
            HStack(spacing: 8) {
                Text(SettingsWords.kept(Platform.device))
                    .font(Typeface.Mac.text(.label))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    submit()
                } label: {
                    Text(lines.button)
                        .frame(minWidth: 72)
                }
                .buttonStyle(DWButtonStyle(kind: .pri))
                .disabled(!signInOn)
            }
            .padding(.horizontal, Self.side)
            .frame(height: 52)
            .background(MacPalette.statusFace)
            .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
        }
        .frame(width: Self.width)
        .background(DWPalette.panel)
        .clipShape(DWCorners.boxShape)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
    }

    /// Where deadwax is: the address and Check, what Check found or "deadwax answered", the local network's note.
    @ViewBuilder private var whereBox: some View {
        if over {
            Text(server.address?.description ?? "")
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(SettingsWords.address)
                .accessibilityValue(server.address?.description ?? "")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField(SettingsWords.address, text: $typed,
                              prompt: Text(SettingsWords.addressExample).foregroundStyle(DWPalette.t3))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .address)
                        .onSubmit { check() }
                        .font(Typeface.Mac.mono(.base))
                        .modifier(MacSignInField(focused: focused == .address))
                    Button(server.checkingAddress ? SettingsWords.checking : SettingsWords.check) { check() }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .disabled(server.checkingAddress)
                }
                if checked, let report = server.addressReport {
                    ForEach(report.lines(Platform.device), id: \.self) { line in
                        Text(line)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                } else {
                    HStack(spacing: 6) {
                        if SignInGate.answered(asksSignIn: asksSignIn, typed: typed, inUse: server.address,
                                               checking: server.checkingAddress) {
                            DWChip(words: SettingsWords.answered, tone: .good)
                        }
                        Text(AddressWords.footer(Platform.device))
                            .font(Typeface.Mac.text(.label))
                            .foregroundStyle(DWPalette.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func whoever(_ words: String) -> some View {
        DisclosureGroup(ErrorWords.forWhoever) {
            Text(words)
                .foregroundStyle(DWPalette.t2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(DWPalette.acc)
    }

    // MARK: what it does - SignInView's calls

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

    /// Return in the password: Sign in once Check has answered for the address shown, Check until then.
    private func returned() {
        if SignInGate.returnSignsIn(asksSignIn: asksSignIn, typed: shownAddress, inUse: server.address) {
            submit()
        } else {
            check()
        }
    }

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

/// A field in the Mac's sign-in: the look's field on its well (DWField's own drawing: plain, 8 in, the Mac's field
/// height, the well's edge the accent's while it has the cursor). Its face is set on the field: the field's words, the
/// address in the readout face.
private struct MacSignInField: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(DWPalette.fieldText)
            .focusEffectDisabled()
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background { DWWell(focused: focused) }
    }
}
