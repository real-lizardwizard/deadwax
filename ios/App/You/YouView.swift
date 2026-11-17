import DeadwaxCore
import SwiftUI

/// The Settings tab's root - the You tab until 16 Nov (screens.md 8, the web's app/You.tsx as Phase 1 has it; James:
/// "instead of "you", let's just use settings", "with maybe some better organization, and maybe some dropdowns instead
/// of big lists", and, of the ways shown him, "Pages, like iOS Settings"). A short list of groups, each opening its own
/// page, top to bottom:
///
/// - who is signed in - the avatar's letter, the name, "No sign-in needed" with logins off - and the UNVERIFIED line
///   under them when /me says so;
/// - Getting albums, Playback and Downloads, each pushing its page (GettingAlbumsPage, PlaybackPage, DownloadsScreen):
///   Downloads with what's on this phone at its right and, under the three, its footer while something is happening
///   (DownloadsRow, DownloadsFooter);
/// - Manage (Phase 7; Phase 8 made each row the app's own page): the managing tools this person may use
///   (ManageSection) - drawn only with a row to draw;
/// - Account (logins on), This phone - the server's name or IP at its right - and About - the app's own version at its
///   right - each pushing its page (AccountPage, ThisPhonePage, AboutPage).
///
/// Core's YouLines decides every line of it from what /me last said (ServerModel.me, its failure, whether it is being
/// asked again, Access); this only draws. /me is asked the first time Settings shows, as the web asks it, and on a pull.
/// Getting albums' three are asked by their own page (GettingAlbumsPage): the root draws none of them. Tapped again, the
/// tab goes back here and then to the top, as every tab does (AppNavigation.select).
struct YouView: View {
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(QueueCountModel.self) private var queueCount
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
                    Group {
                        if let unverified = lines.unverified {
                            Text(unverified)
                                .foregroundStyle(Palette.amber)
                        }
                    }
                    .font(Typeface.footnote)
                }
                // (Phase 6) Getting albums before Playback, the web's order; Downloads after them, as before - last, so
                // its footer is under its row
                Section {
                    NavigationLink(value: AppRoute.gettingAlbums) {
                        Text(RequestWords.gettingAlbums)
                    }
                    NavigationLink(value: AppRoute.playback) {
                        Text(YouWords.playback)
                    }
                    DownloadsRow()
                } footer: {
                    DownloadsFooter()
                        .font(Typeface.footnote)
                }
                // (Phase 7) before Account, as the web's Manage is
                ManageSection()
                Section {
                    if lines.account {
                        NavigationLink(value: AppRoute.account) {
                            Text(YouWords.account)
                        }
                    }
                    NavigationLink(value: AppRoute.thisPhone) {
                        LabeledContent(YouWords.thisPhone) {
                            Text(server.address?.host ?? "")
                                .font(Typeface.mono(.body))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    NavigationLink(value: AppRoute.about) {
                        LabeledContent(YouWords.about) {
                            Text(Self.appVersion)
                                .font(Typeface.mono(.body))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .onChange(of: navigation.youScrollToTop) { _, _ in
                withAnimation { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .navigationTitle(YouWords.title)
        .refreshable {
            // (Phase 8, slice 6) Needs a look's count, on the pull too - asked before /me, so Look after the library
            // given by its answer asks it once, not twice (MainTabs)
            queueCount.pulled()
            await server.refreshMe()
        }
        .task {
            guard !asked else { return }
            asked = true
            await server.refreshMe()
        }
        // (slice 6) Needs a look's count asked as Settings comes on screen (useQueueSummary.ts: as You mounts) - and,
        // while it is, back from the background, after a managing write and once /me says Look after the library is
        // theirs (QueueCountModel, MainTabs)
        .onAppear {
            queueCount.shows(.settings)
        }
        .onDisappear {
            queueCount.hides(.settings)
        }
    }

    private func headline(_ lines: YouLines) -> some View {
        HStack(spacing: 14) {
            Avatar(letter: lines.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(lines.name)
                    .font(Typeface.title2.bold())
                    .lineLimit(2)
                if let identity = lines.identity {
                    Text(identity)
                        .font(Typeface.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// About's App row, and the About row's value on the root: "0.13 (13)", from the bundle.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return YouWords.app(version: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String)
    }
}

/// Settings > About (16 Nov, its own page; About's section on You before): deadwax's version, and for an admin whether
/// logins are on, then the app's own version and build - with /me's failure said under them, in a listener's words.
/// A pull asks /me again, as the root's does: the failure's own way to try again, here where it's said.
struct AboutPage: View {
    @Environment(ServerModel.self) private var server

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        List {
            Section {
                LabeledContent(YouWords.version) {
                    Text(lines.version).font(Typeface.mono(.body))
                }
                if let logins = lines.logins {
                    LabeledContent(YouWords.logins, value: logins)
                }
                LabeledContent(YouWords.app) {
                    Text(YouView.appVersion).font(Typeface.mono(.body))
                }
                if lines.failed, let failure = server.meFailure {
                    ErrorNote(failure)
                }
            }
        }
        .navigationTitle(YouWords.about)
        .refreshable {
            await server.refreshMe()
        }
    }
}

/// The avatar: a letter in a round tile (the web's .app-avatar - 52 points, --dw-avatar #3b3547, title-size and
/// semibold), growing with the text size. The sign-in's "d" and Settings' initial. Hidden from VoiceOver: the name
/// beside it says who.
struct Avatar: View {
    let letter: String

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 52

    var body: some View {
        Text(letter)
            .font(Typeface.title.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(4)
            .frame(width: size, height: size)
            .background(Palette.avatar, in: Circle())
            .accessibilityHidden(true)
    }
}
