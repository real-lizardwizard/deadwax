import DeadwaxCore
import SwiftUI

/// The sign-in (SignIn.tsx): alone at launch after a 401, or over the app when a session ended mid-use. Core's
/// SignInForm holds what was typed and says what went wrong; ServerModel.signIn sends it. `reason` is why it shows -
/// a 401's words, or the launch's - with `reasonWhy` for whoever runs deadwax. STUB (the Root part's): working, plain.
struct SignInView: View {
    let reason: String?
    let reasonWhy: String?

    @Environment(ServerModel.self) private var server
    @State private var form = SignInForm()

    init(reason: String?, reasonWhy: String?) {
        self.reason = reason
        self.reasonWhy = reasonWhy
    }

    var body: some View {
        let lines = form.lines(reason: reason, reasonWhy: reasonWhy)
        NavigationStack {
            Form {
                Section {
                    Text(SignInWords.lede)
                    if let said = lines.reason { Text(said).font(.callout) }
                    if let why = lines.reasonWhy { whoever(why) }
                }
                Section {
                    TextField(SignInWords.userName, text: $form.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(SignInWords.password, text: $form.password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                    Button(lines.button) { submit() }
                        .disabled(lines.disabled)
                    if let problem = lines.problem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                    if let why = lines.problemWhy { whoever(why) }
                }
            }
            .navigationTitle(SignInWords.title)
            .onChange(of: lines.problem) { _, problem in
                if let problem { Notice.announce(problem) }
            }
        }
    }

    private func whoever(_ words: String) -> some View {
        DisclosureGroup(ErrorWords.forWhoever) {
            Text(words).font(.footnote).foregroundStyle(Palette.quiet)
        }
        .font(.footnote)
    }

    private func submit() {
        guard let body = form.submit() else { return }
        Task {
            if let problem = await server.signIn(name: body.username, password: body.password) {
                form.failed(problem.error)
            } else {
                form.signedIn()
            }
        }
    }
}
