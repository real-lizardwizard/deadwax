import DeadwaxCore
import SwiftUI

/// Settings on the Mac (the redesign, slice R9 - Settings.dc.html; notes/ios.md "The redesign, slice R9"): the Settings
/// tab's root, as boxes on the page's ground - row for row the phone's pages (James, 25 Nov: "Today's pages as cards"),
/// each row what the phone's row is and does, in the Mac's own faces.
///
/// - The toolbar: the lede (your own choices; where how deadwax runs is, when Server settings is yours), Server settings
///   (Managing's `.settings`, pushed as the sidebar's Manage row pushes it) and Sign out with logins on (Account's call,
///   ServerModel.signOut, in the click).
/// - Playback: Gapless - the fact the phone's Playback page states, never a checkbox (there is no setting behind one);
///   Normalization, the drawing's four segments over PlayerModel's own setting, its chosen one's line under them and the
///   phone's two notes under that; the EQ, which opens the side panel's (EQLink on the desktop), what is on now under it.
///   The drawing's Quality has no setting behind it either, and isn't drawn (the build plan's 3.8, answer 5, and 4).
/// - Getting albums: When I click Get, Quality floor and Format, each a pop-up over GetSettingsModel - nothing shown as
///   chosen and nothing choosable until deadwax has first answered, off while it can't be reached - their notes, and
///   Confirm before cancelling, this Mac's own (ConfirmCancel's key, read by R8's Requests at the click), its note naming
///   the Mac's own Cancel and Leave (RequestWords.cancelAsksNote). The drawing's Complete albums only has no setting.
/// - This Mac: what is downloaded (Settings > Downloads' counts, DownloadShelf) and the free space, the Storage limit and
///   Download over (DownloadModel's own two - never left out, James's Phase 0 decision, and drawn with the downloads
///   unreadable too, as the phone's page draws them, the reason under them), Show Downloaded, the lists
///   (Settings > Downloads, which keeps Download your library, the other accounts' downloads and Remove All), the address
///   with Change address… and, for an admin, Debug….
/// - Account: who is signed in with the role's chip - "No sign-in needed" with logins off - where the sign-in is kept,
///   Change password… while it's offered, Sign out and its footnote, what went wrong under it.
/// - About: deadwax's version, whether logins are on (an admin's), the app's version, /me's failure in a listener's words.
///
/// Each row's line - a choice's, a fact's - under its control, never beside it (R9's review: beside its four segments
/// Normalization's had 98 points at 1280). Two columns only where every row fits its column (`twoColumns`), else one.
/// The status bar: every choice is kept as it is made, and the app's version. /me is asked the first time the page
/// shows, Getting albums' three each time it shows and as deadwax comes back into reach - as the phone's pages ask them.
struct MacSettingsRoot: View {
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(GetSettingsModel.self) private var getting
    @Environment(Reachability.self) private var reachability
    @Environment(DownloadModel.self) private var downloads
    @Environment(AppNavigation.self) private var navigation
    @AppStorage(ConfirmCancel.storageKey) private var stored: String?
    @State private var asked = false
    /// This Mac's free space, read again as what's here changes.
    @State private var free: Int64? = DownloadStore.freeSpace()

    /// (R9's review) The page wide enough for two columns of boxes: the widest row - This Mac's Show Downloaded and
    /// Downloading and downloaded… side by side, 478 with the label's 124 and its gap of 8 - in each column, inside its
    /// box's 12 either side, the columns 18 apart and the page's 22 either side: 2 × (478 + 24) + 18 + 44 = 1066, and
    /// 1072 for the faces' semibold room. So one column at the window's opening 1280 (a page of 1060), beside the side
    /// panel's 400 and at the smallest window; two from a 1292 window, or 1693 with the side panel open
    /// (test_ios_settings_look.py adds it up from the faces).
    private static let twoColumns: CGFloat = 1072

    var body: some View {
        let lines = YouLines(me: server.me, failure: server.meFailure, asking: server.askingMe, access: server.access)
        let card = AccountCard(lines: lines, access: server.access, address: server.address)
        MacPage {
            tools(card)
        } content: {
            GeometryReader { (room: GeometryProxy) in
                ScrollView {
                    Group {
                        if room.size.width >= Self.twoColumns {
                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 24) { left }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 24) { right(lines, card: card) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 24) {
                                left
                                right(lines, card: card)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 28, leading: 22, bottom: 22, trailing: 22))
                }
            }
        }
        .macStatus(MacStatusItems.Items(leading: [SettingsWords.macSaved], trailing: [YouView.appVersion]))
        .task {
            guard !asked else { return }
            asked = true
            await server.refreshMe()
        }
        .onAppear { getting.ask() }
        .onChange(of: reachability.online) { _, back in
            if back { getting.ask() }
        }
        .task(id: downloads.bytesHere) { free = DownloadStore.freeSpace() ?? free }
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ card: AccountCard) -> some View {
        let settings = Managing.tools(server.access).contains(.settings)
        let row = server.signOutRow
        Text(SettingsWords.macLede(serverSettings: settings))
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t2)
            .lineLimit(1)
            .truncationMode(.tail)
        Spacer(minLength: 8)
        if settings {
            Button(ManagingWords.label(.settings)) { navigation.open(.serverSettings) }
                .buttonStyle(DWButtonStyle())
        }
        if card.signsOut {
            Button(row.label) { signOut() }
                .buttonStyle(DWButtonStyle())
                .disabled(row.busy)
        }
    }

    // MARK: the boxes

    @ViewBuilder private var left: some View {
        playback
        gettingAlbums
    }

    @ViewBuilder private func right(_ lines: YouLines, card: AccountCard) -> some View {
        thisMac(debug: lines.debug)
        account(lines, card: card)
        about(lines)
    }

    /// The phone's Playback page: Gapless (a fact), Normalization, the EQ.
    private var playback: some View {
        let now = eq.now
        return MacGroupBox(legend: YouWords.playback, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 4) {
                MacSettingsFact(label: YouWords.gapless, value: YouWords.gaplessOn, note: YouWords.gaplessLine)
                MacSettingsRow(label: Normalization.title, note: player.normalization.note) {
                    DWSegmented(options: Normalization.allCases,
                                words: { (choice: Normalization) -> String in choice.label },
                                chosen: Binding<Normalization>(get: { player.normalization },
                                                               set: { (choice: Normalization) -> Void in
                                                                   player.normalization = choice
                                                               }),
                                spoken: Normalization.title)
                        .accessibilityHint(player.normalization.note)
                }
                MacSettingsNote(words: YouWords.normalizationNote)
                MacSettingsNote(words: YouWords.kept(Platform.device))
                MacSettingsRow(label: EQWords.You.row, note: "\(now.name) \u{00B7} \(now.short)") {
                    EQLink(route: .now) {
                        Text(SettingsWords.openEQ)
                    }
                    .buttonStyle(DWButtonStyle())
                }
                MacSettingsNote(words: EQWords.You.footer(Platform.device))
            }
        }
    }

    /// The phone's Getting albums page: its three, their notes, Confirm before cancelling.
    private var gettingAlbums: some View {
        let settings = getting.settings
        let live = settings != nil && reachability.online
        let problem = getting.problem(admin: server.access.seesDetail)
        return MacGroupBox(legend: RequestWords.gettingAlbums, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 4) {
                choice(GettingWords.modeTitle(Platform.device), GetMode.allCases, chosen: settings?.mode, live: live,
                       name: { (mode: GetMode) -> String in mode.label }) { (mode: GetMode) -> Void in
                    getting.choose(GetChoice(mode: mode))
                }
                choice(GettingWords.floorTitle, QualityFloor.allCases, chosen: settings?.floor, live: live,
                       name: { (floor: QualityFloor) -> String in floor.label }) { (floor: QualityFloor) -> Void in
                    getting.choose(GetChoice(floor: floor))
                }
                choice(GettingWords.formatTitle, FormatPreference.youOrder, chosen: settings?.format, live: live,
                       name: { (format: FormatPreference) -> String in format.label }) { (format: FormatPreference) -> Void in
                    getting.choose(GetChoice(format: format))
                }
                if !reachability.online {
                    MacSettingsNote(words: StoreLine.offline)
                }
                MacSettingsNote(words: GettingWords.note)
                if !getting.canSave {
                    MacSettingsNote(words: GettingWords.unsavedLine(runsDeadwax: server.access.seesDetail),
                                    colour: DWPalette.redChipText)
                }
                if reachability.online, let problem {
                    MacSettingsNote(words: problem, colour: DWPalette.redChipText)
                }
                MacSettingsRow(label: "", note: RequestWords.cancelAsksNote(Platform.device)) {
                    MacCheckbox(words: RequestWords.confirmCancel,
                                on: Binding<Bool>(get: { ConfirmCancel.read(stored) },
                                                  set: { (on: Bool) -> Void in stored = ConfirmCancel.stored(on) }))
                }
            }
            // a choice that wasn't kept, heard as it goes back
            .onChange(of: problem) { _, said in
                if let said, reachability.online { Notice.announce(said) }
            }
        }
    }

    /// One of Getting albums' three: a pop-up of its choices, the chosen one its words - none until deadwax has answered,
    /// off while it can't be chosen. A choice already chosen chooses nothing (the phone's `choice`).
    private func choice<Choice: Hashable>(_ title: String, _ choices: [Choice], chosen: Choice?, live: Bool,
                                          name: @escaping (Choice) -> String,
                                          pick: @escaping (Choice) -> Void) -> some View {
        MacSettingsRow(label: title) {
            DWPopUp(words: chosen.map(name) ?? "") {
                Picker(title, selection: Binding<Choice?>(get: { chosen }, set: { (now: Choice?) -> Void in
                    guard live, let now, now != chosen else { return }
                    pick(now)
                })) {
                    ForEach(choices, id: \.self) { (option: Choice) in
                        Text(name(option)).tag(Choice?.some(option))
                    }
                }
                .pickerStyle(.inline)
            }
            .disabled(!live)
            .accessibilityLabel(title)
            .accessibilityValue(chosen.map(name) ?? "")
        }
        .opacity(live ? 1 : DWPalette.off)
    }

    /// The phone's Settings > Downloads row and This phone page: what is here, the free space, the Storage limit and
    /// Download over, Downloaded and the lists, the address, Debug.
    private func thisMac(debug: Bool) -> some View {
        @Bindable var downloads = downloads
        let shelf = DownloadShelf(downloads, server: server)
        let over = DownloadWords.over(downloads.downloadOver, device: Platform.device)
        return MacGroupBox(legend: YouWords.thisDevice(Platform.device), ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 4) {
                MacSettingsFact(label: SettingsWords.downloadsBox,
                                value: SettingsWords.downloadsFact(albums: shelf.albumsHere, songs: shelf.songsHere,
                                                                   bytes: downloads.bytesHere),
                                mono: true)
                if let free {
                    MacSettingsFact(label: SettingsWords.freeSpace, value: Bytes.words(free), mono: true)
                }
                // (R9's review) both drawn while the downloads can't be read too, as the phone's page draws them
                MacSettingsRow(label: DownloadWords.storageLimit, note: DownloadWords.storageFooter) {
                    DWPopUp(words: downloads.storageLimit.label) {
                        Picker(DownloadWords.storageLimit, selection: $downloads.storageLimit) {
                            ForEach(StorageLimit.allCases, id: \.self) { (choice: StorageLimit) in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .accessibilityLabel(DownloadWords.storageLimit)
                    .accessibilityValue(downloads.storageLimit.label)
                }
                MacSettingsRow(label: DownloadWords.downloadOver, note: over.note) {
                    DWPopUp(words: over.name) {
                        Picker(DownloadWords.downloadOver,
                               selection: Binding<DownloadOver>(get: { downloads.downloadOver },
                                                                set: { (choice: DownloadOver) -> Void in
                                                                    downloads.downloadOver = choice
                                                                })) {
                            ForEach(DownloadOver.allCases, id: \.self) { (choice: DownloadOver) in
                                Text(DownloadWords.over(choice, device: Platform.device).name).tag(choice)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .accessibilityLabel(DownloadWords.downloadOver)
                    .accessibilityValue(over.name)
                    .accessibilityHint(over.note)
                }
                MacSettingsNote(words: DownloadWords.overKept(Platform.device))
                if downloads.storeProblem != nil {
                    MacSettingsNote(words: DownloadWords.storeUnreadable(Platform.device), colour: DWPalette.amberText)
                }
                MacSettingsRow(label: "") {
                    HStack(spacing: 6) {
                        Button(SettingsWords.showDownloaded) { navigation.open(.downloaded) }
                            .buttonStyle(DWButtonStyle())
                        Button(SettingsWords.downloadsList) { navigation.open(.downloads) }
                            .buttonStyle(DWButtonStyle())
                    }
                }
                MacSettingsFact(label: YouWords.server, value: server.address?.description ?? "", mono: true)
                    .textSelection(.enabled)
                MacSettingsRow(label: "") {
                    HStack(spacing: 6) {
                        Button(SettingsWords.changeAddress) { navigation.open(.serverAddress) }
                            .buttonStyle(DWButtonStyle())
                        if debug {
                            Button("\(YouWords.debug)\u{2026}") { navigation.open(.debug) }
                                .buttonStyle(DWButtonStyle())
                        }
                    }
                }
            }
        }
    }

    /// The account card's and the phone's Account page: who, the role, where the sign-in is kept, Change password…, Sign
    /// out.
    private func account(_ lines: YouLines, card: AccountCard) -> some View {
        let row = server.signOutRow
        return MacGroupBox(legend: YouWords.account, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 4) {
                MacSettingsRow(label: SettingsWords.signedInAs) {
                    HStack(spacing: 8) {
                        Text(card.name)
                            .font(Typeface.Mac.text(.base).weight(.semibold))
                            .foregroundStyle(DWPalette.text)
                            .lineLimit(1)
                        if let role = card.role {
                            DWChip(words: role, tone: .marked)
                        }
                        if let identity = card.identity {
                            Text(identity)
                                .font(Typeface.Mac.text(.small))
                                .foregroundStyle(DWPalette.t2)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.spoken)
                }
                if let unverified = lines.unverified {
                    MacSettingsNote(words: unverified, colour: DWPalette.amberText)
                }
                if card.signsOut {
                    MacSettingsFact(label: SettingsWords.keptLabel, value: SettingsWords.kept(Platform.device))
                    MacSettingsRow(label: "") {
                        HStack(spacing: 6) {
                            if OwnPassword.changeOffered(server.me) {
                                Button(SettingsWords.changePassword) { navigation.open(.changePassword) }
                                    .buttonStyle(DWButtonStyle())
                            }
                            Button(row.label) { signOut() }
                                .buttonStyle(DWButtonStyle())
                                .disabled(row.busy)
                        }
                    }
                    if let problem = row.problem {
                        MacSettingsNote(words: problem, colour: DWPalette.redChipText)
                    }
                    if let me = server.me {
                        MacSettingsNote(words: SignOutRow.footnote(user: me.user)
                                        + (downloads.anythingHere ? DownloadWords.staysAfterSignOut(Platform.device) : ""))
                    }
                }
            }
            .onChange(of: row.problem) { _, problem in
                if let problem { Notice.announce(problem) }
            }
        }
    }

    /// The phone's About page.
    private func about(_ lines: YouLines) -> some View {
        MacGroupBox(legend: YouWords.about, ground: DWPalette.bg) {
            VStack(alignment: .leading, spacing: 4) {
                MacSettingsFact(label: YouWords.version, value: lines.version, mono: true)
                if let logins = lines.logins {
                    MacSettingsFact(label: YouWords.logins, value: logins)
                }
                MacSettingsFact(label: YouWords.app, value: YouView.appVersion, mono: true)
                if lines.failed, let failure = server.meFailure {
                    ErrorNote(failure)
                        .font(Typeface.Mac.text(.small))
                }
            }
        }
    }

    // MARK: doing

    /// Sign out (Account's call, in the click): leaving - the music stops, this Mac's session goes, the sign-in shows.
    private func signOut() {
        Task { await server.signOut() }
    }
}

/// The Mac's Settings' widths, from the drawing: a row's label 124 wide (`.field > label`).
private enum MacSettingsLook {
    static let label: CGFloat = 124
}

/// A row of a box (the drawing's `.field`): its label at the left, 124 wide and right-aligned, its control, and (R9's
/// review) the control's line under it, lined up with it, in the third colour, wrapping - beside it, it had what the
/// control left. The label is the control's for VoiceOver.
private struct MacSettingsRow<Control: View>: View {
    let label: String
    var note: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(width: MacSettingsLook.label, alignment: .trailing)
                    .accessibilityHidden(true)
                control
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            if let note, !note.isEmpty {
                MacSettingsNote(words: note)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A fact of a box (the drawing's `.kv`): its label, as a row's, and its value - in the readout face when the drawing sets
/// it so - and (R9's review) its line under it, lined up with the value. One element for VoiceOver: the label, then the
/// value, then the line.
private struct MacSettingsFact: View {
    let label: String
    let value: String
    var mono = false
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(width: MacSettingsLook.label, alignment: .trailing)
                Group {
                    if mono {
                        Text(value).font(Typeface.Mac.mono(.small))
                    } else {
                        Text(value).font(Typeface.Mac.text(.base))
                    }
                }
                .foregroundStyle(DWPalette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            if let note, !note.isEmpty {
                MacSettingsNote(words: note)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A box's note under its rows, lined up with the controls (the label's 124 and its gap in).
private struct MacSettingsNote: View {
    let words: String
    var colour: Color = DWPalette.t3

    var body: some View {
        Text(words)
            .font(Typeface.Mac.text(.label))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, MacSettingsLook.label + 8)
    }
}
