import DeadwaxCore
import SwiftUI

/// The sign-in (screens.md 3, the web's app/SignIn.tsx): alone at launch after a 401, or OVER the app when a session
/// ended mid-use - the app inert under it and the music playing on, since nothing here touches the player.
///
/// Top to bottom, as the web draws it: the "d" and "deadwax", the lede, why it is showing (`reason`, with `reasonWhy`
/// folded for whoever runs deadwax), the user name and the password (the password manager fills both; the app never
/// keeps the password), what went wrong (announced) with its own fold, and Sign in. Every rule is Core's SignInForm:
/// the name trimmed, the password cleared after any answer, nothing sent with a field empty, "Signing in…" while
/// asking, the reason never said twice. ServerModel.signIn sends it.
///
/// Shown alone, it also says which deadwax it is signing in to, with Change address - the web's address is its
/// browser's, the phone's is this app's, and a sign-in screen with no way back to it would be a dead end.
struct SignInView: View {
    let reason: String?
    let reasonWhy: String?

    @Environment(ServerModel.self) private var server
    @State private var form = SignInForm()
    @FocusState private var focused: Field?

    private enum Field: Hashable { case username, password }

    init(reason: String?, reasonWhy: String?) {
        self.reason = reason
        self.reasonWhy = reasonWhy
    }

    /// Over the app (a session ended mid-use), not the launch's own screen.
    private var over: Bool { server.launch == .ready }

    var body: some View {
        let lines = form.lines(reason: reason, reasonWhy: reasonWhy)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                head
                Text(SignInWords.lede)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                if let said = lines.reason {
                    Text(said)
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Palette.amberFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.amberEdge))
                    if let why = lines.reasonWhy { whoever(why) }
                }
                fields
                if let problem = lines.problem {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    if let why = lines.problemWhy { whoever(why) }
                }
                Button {
                    submit()
                } label: {
                    Text(lines.button).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFace(large: true))
                .disabled(lines.disabled)
                if !over { address }
            }
            .padding(24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // the user name takes focus as the screen comes up - it is the only thing to do here - and the reason is
            // read out with it (the web's dialog description), since VoiceOver goes straight to the field
            DispatchQueue.main.async { focused = .username }
            if let said = lines.reason { Notice.announce(said) }
        }
        .onChange(of: lines.problem) { _, problem in
            if let problem { Notice.announce(problem) }
        }
    }

    private var head: some View {
        HStack(spacing: 14) {
            Avatar(letter: SignInWords.avatar)
            Text(SignInWords.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.bottom, 4)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SignInWords.userName)
                    .font(.subheadline.weight(.medium))
                    .accessibilityHidden(true)
                TextField("", text: $form.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .username)
                    .onSubmit { focused = .password }
                    .modifier(FieldLook())
                    .accessibilityLabel(SignInWords.userName)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(SignInWords.password)
                    .font(.subheadline.weight(.medium))
                    .accessibilityHidden(true)
                SecureField("", text: $form.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focused, equals: .password)
                    .onSubmit { submit() }
                    .modifier(FieldLook())
                    .accessibilityLabel(SignInWords.password)
            }
        }
    }

    /// Which deadwax this signs in to, and the way back to the Server address screen.
    private var address: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(server.address?.description ?? "")
                .font(.footnote.monospaced())
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Button(YouWords.changeAddress) { server.changeAddress() }
                .font(.footnote)
                .disabled(lines.disabled)
        }
        .padding(.top, 8)
    }

    private var lines: SignInLines { form.lines(reason: reason, reasonWhy: reasonWhy) }

    private func whoever(_ words: String) -> some View {
        DisclosureGroup(ErrorWords.forWhoever) {
            Text(words)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
        .font(.footnote)
    }

    private func submit() {
        guard let body = form.submit() else { return }
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

/// A sign-in field: a filled, rounded box, its text never smaller than the body's.
private struct FieldLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(white: 0.24)))
    }
}
