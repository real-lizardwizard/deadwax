import DeadwaxCore
import SwiftUI

/// The Settings tab's root - the You tab until 16 Nov (screens.md 8, the web's app/You.tsx as Phase 1 has it; James:
/// "instead of "you", let's just use settings", "with maybe some better organization, and maybe some dropdowns instead
/// of big lists", and, of the ways shown him, "Pages, like iOS Settings"). (The redesign, slice R9 - James, 25 Nov:
/// "Today's pages as cards") Drawn flat, as iSettings draws its cards: no grey box, each group's rows on their
/// hairlines, top to bottom:
///
/// - the account card (AccountCardView): the round avatar, the name, the address deadwax is at in the readout face, the
///   role as a chip and Sign out - and the UNVERIFIED line under it when /me says so;
/// - Getting albums, Playback and Downloads, each pushing its page (GettingAlbumsPage, PlaybackPage, DownloadsScreen):
///   Downloads with what's on this phone at its right and, under the three, its footer while something is happening
///   (DownloadsRow, DownloadsFooter);
/// - Manage (Phase 7; Phase 8 made each row the app's own page): the managing tools this person may use
///   (ManageSection) - drawn only with a row to draw;
/// - Account (logins on), This phone - the server's name or IP at its right - and About - the app's own version at its
///   right - each pushing its page (AccountPage, ThisPhonePage, AboutPage).
///
/// Core's YouLines decides every line of it from what /me last said (ServerModel.me, its failure, whether it is being
/// asked again, Access), AccountCard the card's; this only draws. /me is asked the first time Settings shows, as the web
/// asks it, and on a pull. Getting albums' three are asked by their own page (GettingAlbumsPage): the root draws none of
/// them. Tapped again, the tab goes back here and then to the top, as every tab does (AppNavigation.select). The drawing's
/// Sound and Getting albums rows on the root (its Gapless switch, its Quality floor) aren't drawn: there is no setting
/// behind a Gapless switch, and the choices are their pages' (the build plan's 3.6 and 3.8, answer 5).
struct YouView: View {
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(QueueCountModel.self) private var queueCount
    @State private var asked = false
    /// The root on screen: a Sign out from its card that couldn't reach deadwax is announced only then (Account's page,
    /// pushed over it, announces its own).
    @State private var shown = false

    init() {}

    private static let top = "you-top"

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        ScrollViewReader { proxy in
            SettingsPage {
                AccountCardView(card: AccountCard(lines: lines, access: server.access, address: server.address),
                                unverified: lines.unverified, announces: shown)
                    .id(Self.top)
                // (Phase 6) Getting albums before Playback, the web's order; Downloads after them, as before - last, so
                // its footer is under its row
                PhoneGroup {
                    NavigationLink(value: AppRoute.gettingAlbums) {
                        SettingsGo { Text(RequestWords.gettingAlbums) }
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: AppRoute.playback) {
                        SettingsGo { Text(YouWords.playback) }
                    }
                    .buttonStyle(.plain)
                    DownloadsRow()
                }
                DownloadsFooter()
                // (Phase 7) before Account, as the web's Manage is
                ManageSection()
                PhoneGroup {
                    if lines.account {
                        NavigationLink(value: AppRoute.account) {
                            SettingsGo { Text(YouWords.account) }
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink(value: AppRoute.thisPhone) {
                        SettingsGo(readout: server.address?.host) {
                            Text(YouWords.thisDevice(Platform.device))
                        }
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: AppRoute.about) {
                        SettingsGo(readout: Self.appVersion) {
                            Text(YouWords.about)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .onChange(of: navigation.youScrollToTop) { _, _ in
                withAnimation { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .navigationTitle(YouWords.title)
        .pullToRefresh {
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
            shown = true
            queueCount.shows(.settings)
        }
        .onDisappear {
            shown = false
            queueCount.hides(.settings)
        }
    }

    /// About's App row, and the About row's value on the root: "0.13 (13)", from the bundle.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return YouWords.app(version: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String)
    }
}

/// (R9) The account card, iSettings' first: the round avatar, the name (bold) with the line under it - "No sign-in
/// needed" with logins off - and the address deadwax is at in the readout face, the role's chip ("Admin") and Sign out,
/// a flat button in the accent, only with logins on (AccountCard.signsOut). One VoiceOver element - its words
/// (AccountCard.spoken) as a heading, Sign out its action - since the card is who you are. Sign out is Account's own
/// call (ServerModel.signOut, in the tap): "Signing out…" while it asks, what went wrong under the card, announced while
/// the root is on screen. (R9's review) From xxxLarge and at every accessibility size the chip and Sign out go under
/// the name, Sign out across the card on up to three lines: beside them the name had 83 points at xxxLarge (39 while
/// "Signing out…"), and at AX5 the row wanted 487 of the phone's 343.
struct AccountCardView: View {
    let card: AccountCard
    let unverified: String?
    let announces: Bool

    @Environment(ServerModel.self) private var server
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let row = server.signOutRow
        let stacked = typeSize.isAccessibilitySize || typeSize == .xxxLarge
        VStack(alignment: .leading, spacing: 0) {
            PhoneCard {
                HStack(alignment: stacked ? .top : .center, spacing: SettingsLook.cardGap) {
                    Avatar(letter: card.letter, points: LibraryLook.rowCover)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.name)
                            .font(Typeface.Phone.text(.row).weight(.bold))
                            .foregroundStyle(DWPalette.text)
                            .lineLimit(stacked ? 3 : 2)
                        if let identity = card.identity {
                            Text(identity)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                        }
                        if let address = card.address {
                            Text(address)
                                .font(Typeface.Phone.mono(.extraSmall))
                                .foregroundStyle(DWPalette.t3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if stacked {
                            VStack(alignment: .leading, spacing: SettingsLook.noteAbove) {
                                trailing(row, stacked: true)
                            }
                            .padding(.top, SettingsLook.noteAbove)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !stacked {
                        trailing(row, stacked: false)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(card.spoken)
                .accessibilityAddTraits(.isHeader)
                .accessibilityActions {
                    if card.signsOut && !row.busy {
                        Button(row.label) { signOut() }
                    }
                }
            }
            if let unverified {
                SettingsNote(words: unverified, colour: DWPalette.amberText)
            }
            if card.signsOut, let problem = row.problem {
                SettingsNote(words: problem, colour: DWPalette.redChipText)
            }
        }
        .onChange(of: row.problem) { _, problem in
            if announces, let problem { Notice.announce(problem) }
        }
    }

    /// The role's chip and Sign out: at the card's right, or (`stacked`) under the name, Sign out across the card, its
    /// words on up to three lines.
    @ViewBuilder private func trailing(_ row: SignOutRow, stacked: Bool) -> some View {
        if let role = card.role {
            DWChip(words: role, tone: .marked)
        }
        if card.signsOut {
            Button {
                signOut()
            } label: {
                Text(row.label)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(DWButtonStyle(size: .small, fills: stacked))
            .disabled(row.busy)
        }
    }

    /// Account's Sign out, from the card: leaving (the music stops, the Keychain's session goes, the sign-in shows) -
    /// only no answer at all keeps you signed in, and the card says so.
    private func signOut() {
        Task { await server.signOut() }
    }
}

/// Settings > About (16 Nov, its own page; About's section on You before): deadwax's version, and for an admin whether
/// logins are on, then the app's own version and build - with /me's failure said under them, in a listener's words.
/// A pull asks /me again, as the root's does: the failure's own way to try again, here where it's said. (R9) Flat: the
/// facts on their hairlines, each its value in the readout face.
struct AboutPage: View {
    @Environment(ServerModel.self) private var server

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        SettingsPage {
            PhoneGroup {
                PhoneKV(label: YouWords.version, value: lines.version, mono: true)
                if let logins = lines.logins {
                    PhoneKV(label: YouWords.logins, value: logins)
                }
                PhoneKV(label: YouWords.app, value: YouView.appVersion, mono: true)
            }
            if lines.failed, let failure = server.meFailure {
                ErrorNote(failure)
                    .font(Typeface.Phone.text(.small))
                    .padding(.top, SettingsLook.noteAbove)
            }
        }
        .navigationTitle(YouWords.about)
        .pullToRefresh {
            await server.refreshMe()
        }
    }
}

/// The avatar: a letter in a round tile (the web's .app-avatar - --dw-avatar #3b3547, semibold), growing with the text
/// size - 52 points on the sign-in, (R9) 44 on the account card, iSettings' cover. Hidden from VoiceOver: the name beside
/// it says who.
struct Avatar: View {
    let letter: String

    @ScaledMetric private var size: CGFloat

    init(letter: String, points: CGFloat = 52) {
        self.letter = letter
        _size = ScaledMetric(wrappedValue: points, relativeTo: .title)
    }

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

// MARK: Settings' flat pieces (R9)

/// (R9) A Settings page on the phone: its groups and notes down the page's own black, 16 in from each edge (iSettings'
/// `padding: 0 16px`) - no List, no grey cells. A ScrollView, so a pull still asks again (`pullToRefresh`).
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, CGFloat(PhoneLook.bigSide))
            .padding(.bottom, CGFloat(PhoneLook.groupAbove))
        }
    }
}

/// (R9) A row that opens a page (`.dw.ph .go`): its words, what it holds at its right, the chevron - PhoneGo's, one
/// element for VoiceOver (the NavigationLink around it is the button). A `readout` - the server's host, the app's
/// version, what's downloaded, the EQ's preset - is in the readout face and the third colour (iSettings' `.mono.xs.q3`),
/// on the words' first text baseline: Courier Prime centred beside Libre Franklin sits 1 to 2 points high (notes/ios.md
/// "The app's fonts"). A `value` of other words, or a badge, is PhoneGo's, centred.
struct SettingsGo<Label: View, Value: View>: View {
    var readout: String? = nil
    @ViewBuilder let label: Label
    @ViewBuilder let value: Value

    var body: some View {
        PhoneGo {
            HStack(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.goGap)) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let readout, !readout.isEmpty {
                    Text(readout)
                        .font(Typeface.Phone.mono(.small))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            value
            PhoneChevron()
        }
    }
}

extension SettingsGo where Value == EmptyView {
    init(readout: String? = nil, @ViewBuilder label: () -> Label) {
        self.init(readout: readout, label: label, value: { EmptyView() })
    }
}

/// (R9) A choice's row (iSettings' `.go` with the choice at its right): its name, and iOS's menu of the choices
/// (`.pickerStyle(.menu)`, given as `choice`) showing the chosen one in the second colour. The name is the Picker's own
/// for VoiceOver - its words here are hidden from it - so the row is one element: "Quality floor, Lossless, pop-up
/// button".
struct SettingsChoiceRow<Choice: View>: View {
    let title: String
    @ViewBuilder let choice: Choice

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.goGap)) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            choice
                .labelsHidden()
                .tint(DWPalette.t2)
        }
        .settingsRow()
    }
}

/// (R9) A note under a group (iOS Settings' footer, flat): the small size, the second colour unless said, wrapping.
struct SettingsNote: View {
    let words: String
    var colour: Color = DWPalette.t2

    var body: some View {
        Text(words)
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, SettingsLook.noteAbove)
    }
}

extension View {
    /// (R9) A row of Settings' own on the phone - a switch, a choice: the row's words, a `.go` row's height at least,
    /// and the group's hairline under it (PhoneGo's and PhoneKV's). (R9's review) On the Mac, which pushes Settings >
    /// Downloads too, the row is its content's own height with SettingsLook.macRowRoom above and below: lookHeight is
    /// exact there, and a switch's two lines would be cut at 46.
    func settingsRow() -> some View {
        font(Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowHeight()
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }

    /// (R9's review) A switch's row on a page the Mac pushes too (Settings > Downloads' two): on the phone the purple
    /// switch (PhoneSwitchStyle) on Settings' row; on the Mac the Mac's own, a plain Toggle tinted the accent, on a row
    /// its content's height - PhoneSwitchRow is DWLook's target tall, the Mac's target is 0, and no click lands on a
    /// switch 0 tall. Either is the system's switch to VoiceOver, its name and its state.
    @ViewBuilder func settingsSwitch() -> some View {
        if Platform.mac {
            toggleStyle(.switch)
                .tint(DWPalette.acc)
                .settingsRow()
        } else {
            toggleStyle(.phoneSwitch)
                .settingsRow()
        }
    }

    /// A Settings row's height: a `.go` row's at least on the phone; on the Mac its content's, with room round it.
    @ViewBuilder fileprivate func settingsRowHeight() -> some View {
        if Platform.mac {
            padding(.vertical, SettingsLook.macRowRoom)
        } else {
            lookHeight(PhoneLook.goRow)
        }
    }
}

/// (R9) Settings' own spacing on the phone, from iSettings: between the account card's avatar, words, chip and Sign out
/// (`.card.f` gap 12), above a note under a group (the EQ's card note's 6), and between fields you type in and round them
/// (iSignIn's `.f` gap 8, its `.group.pad` 10 - one 10). (R9's review) And the room above and below a row of Settings'
/// own on the Mac, which sizes it to its content (settingsRow).
enum SettingsLook {
    static let cardGap: CGFloat = 12
    static let noteAbove: CGFloat = 6
    static let fieldGap: CGFloat = 10
    static let macRowRoom: CGFloat = 8
}
