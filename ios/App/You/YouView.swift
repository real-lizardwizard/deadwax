import DeadwaxCore
import SwiftUI

/// The You tab (screens.md 8, the web's app/You.tsx as Phase 1 has it), top to bottom: who is signed in - the
/// avatar's letter, the name, "No sign-in needed" with logins off - and the UNVERIFIED line under them when /me says
/// so; Playback (Gapless, Normalization, EQ); Downloads (Phase 2: what's on this phone, pushing You > Downloads); Account (Sign out, with logins on); About (deadwax's version, and for an
/// admin whether logins are on, and the app's own version and build - with /me's failure said under them); This phone
/// (the address, Change address, and Debug for an admin, D1).
///
/// Core's YouLines decides every line of it from what /me last said (ServerModel.me, its failure, whether it is being
/// asked again, Access); this only draws. /me is asked the first time You shows, as the web asks it, and on a pull.
struct YouView: View {
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @State private var asked = false

    init() {}

    private static let top = "you-top"

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        ScrollViewReader { proxy in
            List {
                Section {
                    headline(lines)
                        .id(Self.top)
                } footer: {
                    if let unverified = lines.unverified {
                        Text(unverified)
                            .foregroundStyle(Palette.amber)
                    }
                }
                PlaybackSection()
                DownloadsRow()
                if lines.account, let me = server.me {
                    AccountSection(user: me.user)
                }
                about(lines)
                ThisPhoneSection(debug: lines.debug)
            }
            .onChange(of: navigation.youScrollToTop) { _, _ in
                withAnimation { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .navigationTitle(YouWords.title)
        .refreshable { await server.refreshMe() }
        .task {
            guard !asked else { return }
            asked = true
            await server.refreshMe()
        }
    }

    private func headline(_ lines: YouLines) -> some View {
        HStack(spacing: 14) {
            Avatar(letter: lines.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(lines.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                if let identity = lines.identity {
                    Text(identity)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func about(_ lines: YouLines) -> some View {
        Section {
            LabeledContent(YouWords.version) {
                Text(lines.version).monospaced()
            }
            if let logins = lines.logins {
                LabeledContent(YouWords.logins, value: logins)
            }
            LabeledContent(YouWords.app) {
                Text(Self.appVersion).monospaced()
            }
            if lines.failed, let failure = server.meFailure {
                ErrorNote(failure)
            }
        } header: {
            Text(YouWords.about)
        }
    }

    /// About's App row: "0.5 (5)", from the bundle.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return YouWords.app(version: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String)
    }
}

/// The avatar: a letter in a round tile (the web's .app-avatar - 52 points, --dw-avatar #3b3547, title-size and
/// semibold), growing with the text size. The sign-in's "d" and You's initial. Hidden from VoiceOver: the name
/// beside it says who.
struct Avatar: View {
    let letter: String

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 52

    var body: some View {
        Text(letter)
            .font(.title.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(4)
            .frame(width: size, height: size)
            .background(Palette.avatar, in: Circle())
            .accessibilityHidden(true)
    }
}
