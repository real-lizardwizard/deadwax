"""
The redesign's slice R9 (notes/ios.md "The redesign, slice R9: Downloaded, Settings and Sign in"): Settings, Settings >
Downloads and the sign-in drawn as iSettings and iSignIn draw them on the phone, and as Settings.dc.html, Downloaded.dc.html
and SignIn.dc.html on the Mac - James's answer (25 Nov, the build plan's 3.8, answer 5): "Today's pages as cards" - today's
pages and every row, the account card on top, no Gapless or Quality floor.

Read from the Swift source, as the other ios tests read theirs. Core's rules - the account card's words, Sign in waiting for
Check, the Mac's Downloaded columns, widths and status bar, each device's cancel note - are held by SettingsCardsTests.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
CORE = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
YOU = APP / "You"
ROOT = YOU / "YouView.swift"
GETTING = YOU / "GettingAlbumsSection.swift"
PLAYBACK = YOU / "PlaybackSection.swift"
PASSWORD = YOU / "ChangePasswordScreen.swift"
DOWNLOADS = APP / "Downloads" / "DownloadsScreen.swift"
SIGN_IN = APP / "Root" / "SignInView.swift"
ADDRESS = APP / "Root" / "ServerAddressView.swift"
ROOT_VIEW = APP / "Root" / "RootView.swift"
MAC = APP / "Mac" / "Settings"
MAC_SETTINGS = MAC / "MacSettingsRoot.swift"
MAC_DOWNLOADED = MAC / "MacDownloadedPage.swift"
MAC_SIGN_IN = MAC / "MacSignIn.swift"
MAC_PAGES = MAC / "MacSettings.swift"

#? the phone's Settings files R9 drew flat
PHONE_FILES = [ROOT, GETTING, PLAYBACK, YOU / "AccountSection.swift", YOU / "ThisPhoneSection.swift",
               YOU / "ManageSection.swift", YOU / "DownloadsRow.swift", PASSWORD, SIGN_IN, ADDRESS]
#? every switch on them: the file, and how many - each the purple one
SWITCHES = {GETTING: 1, PLAYBACK: 1, DOWNLOADS: 2}


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def partner(text: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == text[opening]:
            depth += 1
        elif text[index] == {"(": ")", "{": "}"}[text[opening]]:
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unbalanced")


def struct(text: str, name: str) -> str:
    found = list(re.finditer(r"\bstruct\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"struct {name} is declared {len(found)} times"
    opening = found[0].end() - 1
    return text[opening + 1:partner(text, opening)]


def chained(text: str, call: str) -> list[str]:
    """Each `call` in `text` and the modifiers chained on after it, up to the next blank line or closing brace line."""
    found = []
    for match in re.finditer(r"\b" + re.escape(call), text):
        end = partner(text, text.index("(", match.start()))
        rest = text[end + 1:]
        # a trailing closure (a Toggle's label)
        trail = re.match(r"\s*\{", rest)
        if trail:
            close = partner(rest, trail.end() - 1)
            rest = rest[close + 1:]
        chain = re.match(r"(\s*\.[\w]+(?:\([^\n]*\))?)*", rest)
        found.append(rest[:chain.end()])
    return found


def test_every_settings_page_on_the_phone_is_flat():
    # no inset-grouped grey cells anywhere on Settings' pages: no Form, no List, no Section - a SettingsPage of
    # PhoneGroups and notes (iSettings' `.group`: no fill, no edge, hairlines)
    for path in PHONE_FILES:
        source = code(path)
        for grey in ("Form {", "List {", "Section {", ".insetGrouped", "listRowBackground(", "LabeledContent("):
            assert grey not in source, f"{path.name}: {grey}"
    page = flat(struct(code(ROOT), "SettingsPage"))
    assert "ScrollView { VStack(alignment: .leading, spacing: 0) { content }" in page
    assert ".padding(.horizontal, CGFloat(PhoneLook.bigSide))" in page
    # a row of Settings' own: the row's words, a .go row's height at least, the group's hairline under it
    root = code(ROOT)
    row = flat(root[root.index("func settingsRow() -> some View {"):root.index("enum SettingsLook")])
    assert ".settingsRowHeight() .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }" in row
    assert "if Platform.mac { padding(.vertical, SettingsLook.macRowRoom) } else { lookHeight(PhoneLook.goRow) }" in row
    # each page pushed from the root's rows is one too, Change password among them
    for path, view in ((GETTING, "GettingAlbumsPage"), (PLAYBACK, "PlaybackPage"), (YOU / "AccountSection.swift", "AccountPage"),
                       (YOU / "ThisPhoneSection.swift", "ThisPhonePage"), (ROOT, "AboutPage"), (ADDRESS, "ServerAddressView"),
                       (PASSWORD, "ChangePasswordScreen")):
        assert "SettingsPage {" in struct(code(path), view), view
    # Settings > Downloads: a plain list - its rows' swipes need one - each section's rows flat (no list hairline, no
    # cell, the page's sides), its legends and notes rows of their own
    downloads = code(DOWNLOADS)
    assert ".listStyle(.plain)" in downloads and ".insetGrouped" not in downloads and "} header: {" not in downloads
    assert "} footer: {" not in downloads
    assert downloads.count("Section {") == downloads.count(".flatRows()") == 9
    rows = flat(downloads[downloads.index("func flatRows() -> some View {"):])
    assert ("listRowSeparator(.hidden) .listSectionSeparator(.hidden) .listRowInsets(EdgeInsets(top: 0, leading: "
            "LibraryLook.side, bottom: 0, trailing: LibraryLook.side)) .listRowBackground(Color.clear)") in rows
    legend = flat(struct(downloads, "ListLegend"))
    assert ".font(Typeface.Phone.text(.legend).weight(.semibold))" in legend and ".accessibilityAddTraits(.isHeader)" in legend


def _phone_look():
    """test_ios_phone_look's own matcher (R1c's): what the phone runs of a file, and what it draws."""
    path = Path(__file__).resolve().parent / "test_ios_phone_look.py"
    spec = importlib.util.spec_from_file_location("_settings_look_phone_look", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


#? everything R9's phone files draw on the phone's path that has a fill, a face, an edge or a rule (R1c's DRAWS): the
#? hairlines - under a group's rows on Settings' root, under Settings > Downloads' legends and its rows - and the
#? sign-in's fields' well with its edge (FieldLook: anywhere you type is a box). No grey box: a card or a row is its
#? words on the page
R9_DRAWS = {
    "Downloads/DownloadsScreen.swift": ["DWRule: DWPalette.groupRule"] * 5 + ["DWRule: DWPalette.rowRule"] * 3,
    "Root/SignInView.swift": ["background: DWPalette.well", "strokeBorder: DWPalette.acc, DWPalette.line"],
    "You/YouView.swift": ["DWRule: DWPalette.groupRule"],
}


def test_settings_on_the_phone_draws_no_grey_box():
    look = _phone_look()
    assert {f"You/{path.name}" for path in PHONE_FILES if path.parent == YOU} < look.R9_PAGES
    found = {}
    for name in sorted(look.R9_PAGES):
        draws = look.drawn(look.phone_path(look.bare((APP / name).read_text(encoding="utf-8"))))
        if draws:
            found[name] = draws
    assert found == R9_DRAWS, found
    # a list's row given a ground of its own is a cell again: Settings > Downloads' rows are on the page's
    grounds = [re.findall(r"listRowBackground\(([^)]*)\)", code(APP / name)) for name in sorted(look.R9_PAGES)]
    assert [ground for each in grounds for ground in each] == ["Color.clear"]
    # and the matcher sees a face planted on one of them
    planted = look.bare("PhoneCard { Text(x) }.background(DWPalette.panel)")
    assert look.drawn(look.phone_path(planted)) == ["background: DWPalette.panel"]


def test_downloads_rows_are_iartists_rows():
    downloads = code(DOWNLOADS)
    # an album's, a playlist's and your library's: the cover (the mark) at 44, the name in the body's words, the line
    # under it in the second colour, the tall row's height and its hairline
    for name in ("AlbumLine", "PlaylistLineRow", "LibraryDownloadingRow"):
        row = flat(struct(downloads, name))
        assert "LibraryLook.rowCover" in row and "LibraryLook.rowTextSide" in row, name
        assert ".font(Typeface.body)" in row and "DWPalette.t2" in row, name
        # (R9's review) the tall row's height: the phone's 60 at least, the Mac's its content's (tallRow)
        assert (".padding(.vertical, 4) .tallRow()" if name == "AlbumLine" else ".tallRow(macRoom: 4)") in row, name
        assert "DWRule(colour: DWPalette.rowRule)" in row, name
        assert "@ScaledMetric" not in row and ".foregroundStyle(.primary)" not in row, name
    tall = flat(downloads[downloads.index("@ViewBuilder func tallRow(macRoom: CGFloat = 0) -> some View {"):])
    assert ("@ViewBuilder func tallRow(macRoom: CGFloat = 0) -> some View { if Platform.mac { padding(.vertical, macRoom) } "
            "else { lookHeight(DWLook.here.tallRowHeight) } }") in tall
    assert downloads.count("lookHeight(DWLook.here.tallRowHeight)") == 1
    # every row as before: its swipe, its VoiceOver element, the album's page or the playlist's opened - (R9's review)
    # and no right-click of its own (a right-click is only the ••• menus' items: test_ios_mac's rule)
    assert downloads.count(".removable(name:") == 5
    removable = flat(struct(downloads, "Removable"))
    assert "content.swipeActions(edge: .trailing, allowsFullSwipe: true) {" in removable
    assert "contextMenu" not in downloads
    assert flat(struct(downloads, "AlbumLine")).count(".accessibilityElement(children: .ignore)") == 1


def test_each_switch_is_the_purple_one():
    # every Toggle on Settings' pages is drawn with PhoneSwitchStyle on the phone - never iOS's green, never a picture
    # of one: the style itself, or (R9's review) settingsSwitch, whose phone half it is
    look = _phone_look()
    for path, count in SWITCHES.items():
        source = code(path)
        assert len(re.findall(r"\bToggle\(", source)) == count, path.name
        for chain in chained(source, "Toggle("):
            assert ".toggleStyle(.phoneSwitch)" in chain or ".settingsSwitch()" in chain, f"{path.name}: {chain[:80]}"
            # (R9's review) and each reads as a switch: iOS's own to VoiceOver (PhoneSwitchStyle's representation, the
            # Mac's Toggle), its name and state - never an element of our own made over it, a button with a value
            for over in (".accessibilityElement(", ".isButton", ".accessibilityValue(", ".accessibilityAction ",
                         ".accessibilityAction {", ".accessibilityAddTraits("):
                assert over not in chain, f"{path.name}: {over} on a switch"
    switch = flat(code(ROOT)[code(ROOT).index("@ViewBuilder func settingsSwitch() -> some View {"):])
    assert ("@ViewBuilder func settingsSwitch() -> some View { if Platform.mac { toggleStyle(.switch) "
            ".tint(DWPalette.acc) .settingsRow() } else { toggleStyle(.phoneSwitch) .settingsRow() } }") in switch
    for path in PHONE_FILES + [DOWNLOADS]:
        source = look.phone_path(code(path))
        assert not re.search(r'Image\(systemName: "(?:switch|togglepower|circle\.fill)', source), path.name
        assert ".toggleStyle(.switch)" not in source and "toggleStyle(.switch)" not in source, path.name
    # the switch itself: a button over the face, VoiceOver hearing iOS's own switch
    style = flat(code(APP / "Phone" / "PhoneSwitch.swift"))
    assert ".accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } .toggleStyle(.switch) }" in style
    # Settings > Downloads' two: their names and notes said to VoiceOver on the Toggle itself
    downloads = flat(code(DOWNLOADS))
    assert (".accessibilityLabel(AutoDownloadWords.switchName(scope)) .accessibilityHint(AutoDownloadWords.note(scope, "
            "device: Platform.device)) .settingsSwitch()") in downloads
    assert (".accessibilityLabel(AutoDownloadWords.onlyWhileCharging) .accessibilityHint(AutoDownloadWords.chargingNote("
            "scope, device: Platform.device)) .settingsSwitch()") in downloads


#? (R9's review) every row the Mac's Settings draws, by its label, in order: the phone's pages' rows and nothing else -
#? an added row (the drawing's Sound > Quality, say) is a row with no setting behind it until a change says otherwise
MAC_ROWS = ["YouWords.gapless", "Normalization.title", "EQWords.You.row", "GettingWords.modeTitle(Platform.device)",
            "GettingWords.floorTitle", "GettingWords.formatTitle", '""', "title", "SettingsWords.downloadsBox",
            "SettingsWords.freeSpace", "DownloadWords.storageLimit", "DownloadWords.downloadOver", '""', "YouWords.server",
            '""', "SettingsWords.signedInAs", "SettingsWords.keptLabel", '""', "YouWords.version", "YouWords.logins",
            "YouWords.app"]


def calls(text: str, name: str) -> list[str]:
    """Each call of `name` in `text`, its arguments and its trailing closure (a Toggle's label) - however it is laid
    out over lines."""
    found = []
    for match in re.finditer(r"\b" + re.escape(name) + r"\(", text):
        opened = match.end() - 1
        close = partner(text, opened)
        whole = text[match.start():close + 1]
        trail = re.match(r"\s*\{", text[close + 1:])
        if trail:
            start = close + trail.end()
            whole += text[close + 1:partner(text, start) + 1]
        found.append(flat(whole))
    return found


def test_no_row_has_no_setting_behind_it():
    # Gapless is the fact today's Playback page states - never a switch or a checkbox, there being no setting behind
    # one: (R9's review) however a call is laid out over lines, its label in its trailing closure included
    for path in (PLAYBACK, ROOT, MAC_SETTINGS, DOWNLOADS, GETTING):
        source = code(path)
        for name in ("Toggle", "MacCheckbox", "DWToggleStyle"):
            for call in calls(source, name):
                assert not re.search(r"YouWords\.gapless|\"Gapless\"|[Gg]apless", call), f"{path.name}: {call[:90]}"
    assert "PhoneKV(label: YouWords.gapless, value: YouWords.gaplessOn)" in code(PLAYBACK)
    assert "MacSettingsFact(label: YouWords.gapless, value: YouWords.gaplessOn, note: YouWords.gaplessLine)" in code(MAC_SETTINGS)
    # Quality floor is Getting albums' own choice, bound to deadwax's setting - nowhere else; the drawing's Sound >
    # Quality, Complete albums only, the library's runs and the sidebar's order have nothing behind them, and aren't drawn
    for path in (GETTING, MAC_SETTINGS):
        assert "choice(GettingWords.floorTitle, QualityFloor.allCases, chosen: settings?.floor, live: live," in code(path)
    for path in PHONE_FILES + [MAC_SETTINGS, DOWNLOADS]:
        assert code(path).count("QualityFloor") == (3 if path in (GETTING, MAC_SETTINGS) else 0), path.name
        # (R9's review) no words of a row with nothing behind it, in any string: Sound, Quality, Complete albums...
        for literal in re.findall(r'"((?:[^"\\\n]|\\.)*)"', code(path)):
            for undrawn in ("quality", "sound", "complete albums", "show albums as", "edit order", "playlists i follow",
                            "keyboard shortcuts", "open the guide"):
                assert undrawn not in literal.lower(), f"{path.name}: \"{literal}\""
    # the Mac's rows, every one: the phone's pages' and no other (MAC_ROWS) - and its controls, counted
    mac = code(MAC_SETTINGS)
    rows = [re.match(r"(?:MacSettingsRow|MacSettingsFact)\(label: ([^,)]+)", call).group(1)
            if not call.startswith("choice(") else call[len("choice("):].split(",")[0]
            for call in re.findall(r"\b(?:MacSettingsRow|MacSettingsFact)\(label: [^,)]+|\bchoice\(GettingWords[^,]+", mac)]
    assert rows == MAC_ROWS, rows
    for control, count in (("MacCheckbox(", 1), ("DWSegmented(", 1), ("DWPopUp(", 3), ("Toggle(", 0), ("Picker(", 3)):
        assert mac.count(control) == count, control


def test_download_over_and_the_storage_limit_stay():
    # James's Phase 0 decision: both on the phone's Settings > Downloads and on the Mac's This Mac - drawn, not only
    # declared: the screen's list holds both sections, and the Mac's This Mac box both rows
    screen = struct(code(DOWNLOADS), "DownloadsScreen")
    assert "StorageSection(shelf: shelf, free: free)" in screen
    assert "DownloadOverSection(waitingForIt: shelf.waitingForNetwork)" in screen
    mac = code(MAC_SETTINGS)
    this_mac = mac[mac.index("private func thisMac(debug: Bool) -> some View {"):mac.index("private func account(")]
    assert "MacSettingsRow(label: DownloadWords.storageLimit" in this_mac
    assert "MacSettingsRow(label: DownloadWords.downloadOver" in this_mac
    # (R9's review) drawn while the downloads can't be read too, as the phone's page draws them, the reason under them
    assert "storeProblem == nil" not in this_mac
    assert ("if downloads.storeProblem != nil { MacSettingsNote(words: DownloadWords.storeUnreadable(Platform.device), "
            "colour: DWPalette.amberText) }") in flat(this_mac)
    phone = struct(code(DOWNLOADS), "DownloadsScreen")
    assert phone.index("StorageSection(shelf: shelf, free: free)") < phone.index("if downloads.storeProblem == nil {")
    assert "if downloads.storeProblem == nil {\n                LibrarySection()\n            }\n            DownloadOverSection(" in phone
    assert "thisMac(debug: lines.debug)" in mac
    for path in (DOWNLOADS, MAC_SETTINGS):
        source = code(path)
        assert "Picker(DownloadWords.storageLimit, selection: $downloads.storageLimit)" in source, path.name
        assert re.search(r"Picker\(DownloadWords\.downloadOver,\s*selection: Binding<DownloadOver>", source), path.name
        assert "downloads.downloadOver = choice" in source, path.name


def test_a_rows_readout_is_settingsgos_on_the_words_baseline():
    # what a row holds at its right in the readout face - Downloads' size as songs come (test_ios_palette's ticking
    # numbers name SettingsGo's readout for it), the server's host, the app's version - is handed to SettingsGo, which
    # sets it beside the row's words on their first text baseline (test_ios_readout_rows holds the baseline)
    row = flat(struct(code(YOU / "DownloadsRow.swift"), "DownloadsRow"))
    assert ("SettingsGo(readout: downloads.storeProblem == nil && downloads.bytesHere > 0 ? "
            "Bytes.words(downloads.bytesHere) : nil) {") in row
    assert "Typeface.readout(" not in row and "Typeface.Phone.mono(" not in row
    go = flat(struct(code(ROOT), "SettingsGo"))
    assert ("PhoneGo { HStack(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.goGap)) { label "
            ".frame(maxWidth: .infinity, alignment: .leading) if let readout, !readout.isEmpty { Text(readout) "
            ".font(Typeface.Phone.mono(.small))") in go
    # every other value is words in the row's face: Needs a look's count, the EQ's preset
    assert "Typeface.Phone.mono(" not in code(YOU / "ManageSection.swift")
    assert "Typeface.Phone.mono(" not in code(PLAYBACK) and "Typeface.readout(" not in code(PLAYBACK)


def test_the_account_card_is_on_top():
    root = struct(code(ROOT), "YouView")
    body = root[root.index("var body: some View {"):]
    assert body.index("AccountCardView(") < body.index("NavigationLink(value: AppRoute.gettingAlbums)")
    card = flat(struct(code(ROOT), "AccountCardView"))
    # the round avatar, the name, the address in the readout face, the role's chip, Sign out - one VoiceOver element
    for part in ("Avatar(letter: card.letter, points: LibraryLook.rowCover)", "Text(card.name)",
                 ".font(Typeface.Phone.mono(.extraSmall))", "DWChip(words: role, tone: .marked)",
                 "if card.signsOut { Button { signOut() } label: { Text(row.label)",
                 ".accessibilityElement(children: .ignore) .accessibilityLabel(card.spoken) "
                 ".accessibilityAddTraits(.isHeader)"):
        assert part in card, part
    # (R9's review) Sign out is the card's action for VoiceOver - its one element's - while it can be pressed
    assert (".accessibilityActions { if card.signsOut && !row.busy { Button(row.label) { signOut() } } }") in card
    assert "Task { await server.signOut() }" in flat(struct(code(ROOT), "AccountCardView"))
    avatar = flat(struct(code(ROOT), "Avatar"))
    assert ".background(Palette.avatar, in: Circle())" in avatar


def test_sign_in_waits_for_check():
    # Check, then Sign in - today's calls in today's order: Sign in off, and its submit refused, until Check has answered
    # for the address shown and deadwax asked for a sign-in (Core's SignInGate)
    for path in (SIGN_IN, MAC_SIGN_IN):
        source = flat(code(path))
        assert ("let signInOn = SignInGate.signInOn(asksSignIn: asksSignIn, typed: shownAddress, inUse: server.address, "
                "checking: server.checkingAddress, busy: lines.disabled)") in source, path.name
        assert ".disabled(!signInOn)" in source, path.name
        submit = source[source.index("private func submit() {"):]
        assert submit.index("guard SignInGate.signInOn(") < submit.index("form.submit()"), path.name
        assert "await server.signIn(name: body.username, password: body.password)" in submit, path.name
        check = source[source.index("private func check() {"):source.index("private func submit() {")]
        assert "guard !over, !server.checkingAddress else { return }" in check, path.name
        assert "_ = await server.checkAddress()" in check, path.name
    # over the app the address is said, never typed (no Check, so no other deadwax under the app)
    assert "PhoneKV(label: SettingsWords.address" in code(SIGN_IN)


def test_the_dialog_is_the_macs_alone():
    root = flat(code(ROOT_VIEW))
    assert ("@ViewBuilder private func signIn(reason: String?, why: String?) -> some View { if Platform.mac { "
            "MacSignIn(reason: reason, reasonWhy: why) } else { SignInView(reason: reason, reasonWhy: why) } }") in root
    # drawn nowhere else
    for path in sorted(APP.rglob("*.swift")):
        if path in (ROOT_VIEW, MAC_SIGN_IN):
            continue
        assert "MacSignIn(" not in code(path), path.relative_to(APP)
    # every launch gate kept: no address, checking, can't reach, signed out, the app - and the sign-in over the app
    gate = root[root.index("@ViewBuilder private var gate: some View {"):root.index("@ViewBuilder private func signIn(")]
    for case in ("if showsSignIn {", "case .needsAddress, .signedOut:", "case .checking:", "case .unreachable(let failure):",
                 "UnreachableView(failure: failure)", "case .ready:"):
        assert case in gate, case
    assert "if server.launch == .ready, let over = server.signInOver { signIn(reason: over.reason, why: over.why)" in root
    # the one screen kept up through its own Check, put away by the app or can't-reach
    assert "case .checking: break" in root  # (R9's review: the whole switch, test_the_sign_in_is_held_on_both_devices)


def test_the_macs_cancel_note_names_the_macs_own_buttons():
    # each device's Getting albums says what its own Requests asks first for: the phone's ✕, the Mac's Cancel and Leave
    for path in (GETTING, MAC_SETTINGS):
        assert "RequestWords.cancelAsksNote(Platform.device)" in code(path), path.name
    for path in sorted(APP.rglob("*.swift")):
        assert "RequestWords.confirmCancelNote" not in code(path), path.relative_to(APP)
    # the Mac's Confirm before cancelling is the same setting Requests reads at the click
    mac = flat(code(MAC_SETTINGS))
    assert "@AppStorage(ConfirmCancel.storageKey) private var stored: String?" in mac
    assert ("MacCheckbox(words: RequestWords.confirmCancel, on: Binding<Bool>(get: { ConfirmCancel.read(stored) }, "
            "set: { (on: Bool) -> Void in stored = ConfirmCancel.stored(on) }))") in mac


def test_the_macs_settings_are_the_phones_pages_row_for_row():
    pages = code(MAC_PAGES)
    assert "static func root() -> some View {\n        MacSettingsRoot()\n    }" in pages
    mac = flat(code(MAC_SETTINGS))
    # Playback: Gapless (a fact), Normalization (its segments), the EQ - the side panel's
    for part in ("player.normalization = choice", "DWSegmented(options: Normalization.allCases", "EQLink(route: .now)",
                 "MacSettingsNote(words: YouWords.normalizationNote)", "MacSettingsNote(words: YouWords.kept(Platform.device))",
                 "MacSettingsNote(words: EQWords.You.footer(Platform.device))"):
        assert part in mac, part
    # Getting albums: the three over GetSettingsModel, their notes, the problem said
    for title, cases, chosen in (("GettingWords.modeTitle(Platform.device)", "GetMode.allCases", "settings?.mode"),
                                 ("GettingWords.floorTitle", "QualityFloor.allCases", "settings?.floor"),
                                 ("GettingWords.formatTitle", "FormatPreference.youOrder", "settings?.format")):
        assert f"choice({title}, {cases}, chosen: {chosen}, live: live," in mac, title
    assert "guard live, let now, now != chosen else { return }" in mac and ".disabled(!live)" in mac
    for part in ("MacSettingsNote(words: StoreLine.offline)", "MacSettingsNote(words: GettingWords.note)",
                 "GettingWords.unsavedLine(", "Notice.announce(said)"):
        assert part in mac, part
    # This Mac: Downloads' counts, the free space, the two choices, Downloaded and the lists, the address, Debug
    for part in ("SettingsWords.downloadsFact(albums: shelf.albumsHere, songs: shelf.songsHere, bytes: downloads.bytesHere)",
                 "DownloadStore.freeSpace()", "navigation.open(.downloaded)", "navigation.open(.downloads)",
                 "navigation.open(.serverAddress)", "if debug {", "navigation.open(.debug)"):
        assert part in mac, part
    # Account: who, the role, Kept, Change password while offered, Sign out and its footnote
    for part in ("card.role", "SettingsWords.kept(Platform.device)", "if OwnPassword.changeOffered(server.me) {",
                 "navigation.open(.changePassword)", "SignOutRow.footnote(user: me.user)", "Task { await server.signOut() }"):
        assert part in mac, part
    # About, and who asks what and when: /me once, Getting albums' three as the page shows and as deadwax comes back
    for part in ("lines.version", "if let logins = lines.logins", "YouView.appVersion", "ErrorNote(failure)",
                 "guard !asked else { return } asked = true await server.refreshMe()", ".onAppear { getting.ask() }",
                 "if back { getting.ask() }"):
        assert part in mac, part
    # the toolbar: Server settings by its permission, Sign out with logins on
    assert "let settings = Managing.tools(server.access).contains(.settings)" in mac
    assert "if settings { Button(ManagingWords.label(.settings)) { navigation.open(.serverSettings) }" in mac
    assert "if card.signsOut { Button(row.label) { signOut() }" in mac
    # the status bar: saved as you change them, the app's version
    assert ".macStatus(MacStatusItems.Items(leading: [SettingsWords.macSaved], trailing: [YouView.appVersion]))" in mac
    # two columns only where every row fits its column (test_the_macs_settings_take_two_columns_only_where_they_fit)
    assert "private static let twoColumns: CGFloat = 1072" in mac and "if room.size.width >= Self.twoColumns {" in mac


def test_the_macs_downloaded_is_downloadmodels():
    pages = code(MAC_PAGES)
    assert "case .downloaded: MacDownloadedPage()" in pages
    assert "case .downloadedPlaylists: MacDownloadedPage(tab: .playlists)" in pages
    page = flat(code(MAC_DOWNLOADED))
    # every row and number DownloadShelf's - Settings > Downloads' own records
    assert "let shelf = DownloadShelf(downloads, server: server)" in page
    assert ("MacDownloaded.status(albums: shelf.albumsHere, songs: shelf.songsHere, bytes: downloads.bytesHere, "
            "downloading: shelf.downloading.count, free: free, device: Platform.device)") in page
    assert "MacDownloaded.playlistsStatus(playlists: here.count," in page
    # the columns Core's, the cover as tall as View > Row Size says
    assert "MacListColumn(title: MacDownloaded.title(column, tab: tab, device: Platform.device), width: MacDownloaded.width(column))" in page
    assert page.count("CGFloat(rowSize.cover)") == 6
    # each cover beside its title in a centred stack, the cell on the title's baseline (test_ios_readout_rows'
    # test_a_tables_cover_rides_on_its_title holds the album's; the playlist's is here)
    assert len(re.findall(r"\b(?:CoverImage|PlaylistCover)\(", page)) == 2
    assert re.search(r"HStack\(spacing: 8\) \{ CoverImage\(id: row\.album\?\.coverArt[^{}]* Text\(row\.album\?\.name", page)
    assert re.search(r"HStack\(spacing: 8\) \{ PlaylistCover\(id: row\.coverArt[^{}]* Text\(row\.name\) \}", page)
    assert "MacDownloaded.songs(here: here.songs, of: here.total)" in page and "MacDownloaded.when(doneAt, now: now)" in page
    # a right-click is its page's •••'s items; a double-click or Return opens it
    assert "AlbumRightClick(route: route(row))" in page and "PlaylistRightClick(route: PlaylistRoute(id: row.id))" in page
    assert "navigation.open(.album(route(row)))" in page
    # Remove all…: Settings > Downloads' question and call
    assert ".confirmationDialog(DownloadWords.removeAllTitle, isPresented: $askingRemoveAll, titleVisibility: .visible)" in page
    assert "downloads.removeAll() player.say(DownloadWords.removedAll)" in page
    assert "Text(shelf.removeAllMessage(downloads, server: server))" in page
    assert "Text(shelf.removeAllMessage(downloads, server: server))" in flat(code(DOWNLOADS))
    # the meter while it downloads, progress followed while the page shows
    assert "DWMeter(fraction: fraction)" in page and ".task { await downloads.followProgress() }" in page


# ----------------------------------------------------------------------------- R9's review


def mac_path(text: str) -> str:
    """The code as the Mac runs it - test_ios_phone_look's phone_path turned round: each `if Platform.mac { A } else
    { B }` (or `if Platform.mac || <x> {`) as A, with no else as A too; `if !Platform.mac { A } else { B }` as B, with no
    else as nothing; `if Platform.mac && <x> {` as `if <x> {`. What else there is - an `else if`, a ternary - is kept
    whole, so nothing the Mac might run is dropped."""
    while True:
        both = re.search(r"\bif Platform\.mac && ", text)
        if both:
            text = text[:both.start()] + "if " + text[both.end():]
            continue
        found = re.search(r"\bif (!?)Platform\.mac((?: \|\| [^{]+)?) \{", text)
        if not found or (found.group(1) and found.group(2)):
            return text
        negated = bool(found.group(1))
        opened = found.end() - 1
        end = partner(text, opened)
        otherwise = re.match(r"\s*else \{", text[end + 1:])
        if otherwise:
            start = end + otherwise.end()
            close = partner(text, start)
            kept = text[start + 1:close] if negated else text[opened + 1:end]
            text = text[:found.start()] + kept + text[close + 1:]
        else:
            text = text[:found.start()] + ("" if negated else text[opened + 1:end]) + text[end + 1:]


#? the pages the Mac pushes under Settings (MacSettings.page, opened from MacSettingsRoot) that are the phone's own:
#? Settings > Downloads (and through it every row, switch and Remove of its), the server's address, Debug and Change
#? password - and the Settings pieces they draw (YouView.swift's settingsRow, settingsSwitch, SettingsNote) and the
#? phone's groups (PhoneCard.swift)
MAC_PUSHED = [DOWNLOADS, ADDRESS, PASSWORD, YOU / "DebugView.swift", ROOT, APP / "Phone" / "PhoneCard.swift"]


def test_the_pages_the_mac_pushes_under_settings_draw_at_the_macs_sizes():
    # (R9's review) lookHeight is exact on the Mac and DWLook's target there is 0: a phone switch's row 0 tall (no click
    # lands on it) and a tall row 30 (cutting its 44 cover) on the Mac's path would be a page drawn in the Mac's frames
    for path in MAC_PUSHED:
        mac = mac_path(code(path))
        for phone in (".phoneSwitch", "PhoneSwitchRow", "lookHeight(DWLook.here.target)", "tallRowHeight"):
            assert phone not in mac, f"{path.name}: {phone} on the Mac's path"
        # settingsRow's 46 is the phone's alone; PhoneGo's and PhoneKV's (PhoneCard.swift) are on no page the Mac
        # pushes - its one piece there, PhoneGroup, a legend's one line
        if path.parent != APP / "Phone":
            assert "lookHeight(PhoneLook.goRow)" not in mac, path.name
        if path != ROOT and path.parent != APP / "Phone":
            for piece in ("PhoneGo", "PhoneKV(", "SettingsGo", "PhoneCard {"):
                assert piece not in mac, f"{path.name}: {piece}"
    # what the Mac runs in their place: the Mac's own switch, rows their content's height
    you = mac_path(code(ROOT))
    assert "toggleStyle(.switch) .tint(DWPalette.acc) .settingsRow()" in flat(you)
    assert "padding(.vertical, SettingsLook.macRowRoom)" in you and "static let macRowRoom: CGFloat = 8" in you
    assert "padding(.vertical, macRoom)" in mac_path(code(DOWNLOADS))
    # the matcher sees each half: a phone piece planted on the Mac's half is found, one on the phone's isn't
    assert "lookHeight(DWLook.here.target)" in mac_path("if Platform.mac { x.lookHeight(DWLook.here.target) } else { y }")
    assert "target" not in mac_path("if Platform.mac { x } else { y.lookHeight(DWLook.here.target) }")
    assert "target" not in mac_path("if !Platform.mac { y.lookHeight(DWLook.here.target) }")
    assert "tallRowHeight" in mac_path("if !Platform.mac { y } else { x.lookHeight(DWLook.here.tallRowHeight) }")
    # which pages those are: what MacSettings.page draws for the routes the Mac's Settings opens - the phone's
    # Getting albums, Playback, Account, This phone and About pages are opened from the phone's root alone (the Mac's
    # are its boxes)
    pages = code(MAC_PAGES)
    for case, view in (("downloads", "DownloadsScreen()"), ("serverAddress", "ServerAddressView()"),
                       ("debug", "DebugView()"), ("changePassword", "ChangePasswordScreen()")):
        assert f"case .{case}: {view}" in pages, case
        assert f"navigation.open(.{case})" in code(MAC_SETTINGS), case
    for path in sorted(APP.rglob("*.swift")):
        source = code(path)
        for phone_only in ("gettingAlbums", "playback", "account", "thisPhone", "about"):
            if path != ROOT:
                assert not re.search(rf"AppRoute\.{phone_only}\b", source), f"{path.relative_to(APP)}: {phone_only}"
            assert not re.search(rf"\.open\(\.{phone_only}\b", source), f"{path.relative_to(APP)}: {phone_only}"


def _width(words: str, points: float, weight: str = "semibold") -> float:
    return _fonts().words(words, points, weight)


def _fonts():
    path = Path(__file__).resolve().parent / "ios_fonts.py"
    spec = importlib.util.spec_from_file_location("_settings_look_fonts", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _word(source: str, name: str) -> str:
    found = re.search(rf'static let {name} = "([^"]+)"', source)
    assert found, name
    return found.group(1).replace("\\u{2026}", "…")


def test_the_macs_settings_take_two_columns_only_where_they_fit():
    # (R9's review) every row added up from the bundled faces (semibold, from above for the buttons' 500): a row is
    # its label's 124 and the gap of 8, then its control - a button DWButtonStyle's words at 12.5 and 11 either side,
    # two of them 6 apart; Normalization's four segments at 11.5 with 8 either side and the groove's 1; a pop-up its
    # widest choice, the caret's 8 and 6, and 11 either side
    cards, levels = (CORE / "SettingsCards.swift").read_text(), (CORE / "Levels.swift").read_text()
    settings = (CORE / "GetSettings.swift").read_text()
    button = lambda words: _width(words, 12.5) + 2 * 11  # noqa: E731
    rows = {
        "This Mac's two": button(_word(cards, "showDownloaded")) + 6 + button(_word(cards, "downloadsList")),
        "the address's two": button(_word(cards, "changeAddress")) + 6 + button("Debug…"),
        "Account's two": button(_word(cards, "changePassword")) + 6 + button("Signing out…"),
        "the EQ": button(_word(cards, "openEQ")),
        "Normalization": sum(_width(label, 11.5) + 2 * 8
                             for label in re.findall(r'case \.\w+: return "([^"]+)"',
                                                     levels[levels.index("public var label: String {"):][:400])) + 2,
        "a pop-up": max(_width(label, 12.5) for label in re.findall(r'case \.\w+: return "([^"]+)"', settings)) + 6 + 8 + 22,
        "Confirm before cancelling": 13 + 6 + _width("Confirm before cancelling", 13, "regular"),
    }
    assert len(re.findall(r'case \.\w+: return "([^"]+)"', levels[levels.index("public var label: String {"):][:400])) == 4
    widest = max(rows.values()) + 124 + 8
    assert max(rows, key=rows.get) == "This Mac's two", rows
    # two columns: each the page less its 22 either side and the 18 between, inside its box's 12 either side
    need = 2 * (widest + 2 * 12) + 18 + 2 * 22
    mac = code(MAC_SETTINGS)
    threshold = float(re.search(r"private static let twoColumns: CGFloat = (\d+)", mac).group(1))
    assert need <= threshold <= need + 12, (need, threshold)
    # one column wherever it falls back: the smallest window's page (880 - 220), the window's opening one beside the
    # side panel (1280 - 220 - 400 - its hairline), and just under the threshold
    look = (CORE / "MacLook.swift").read_text()
    sidebar = float(re.search(r"public static let sidebarWidth: Double = (\d+)", look).group(1))
    panel = float(re.search(r"public static let panelWidth: Double = (\d+)", look).group(1))
    for page in (880 - sidebar, 1280 - sidebar - panel - 1, threshold - 1):
        assert widest <= page - 2 * 22 - 2 * 12, page
    assert 1280 - sidebar < threshold, "the window's opening page is one column: 478 of a 475 column did not fit"
    # each row's line under its control, lined up with it - never beside it, where it had what the control left
    row = flat(struct(mac, "MacSettingsRow"))
    assert ("VStack(alignment: .leading, spacing: 2) { HStack(alignment: .center, spacing: 8) { Text(label)") in row
    assert (".frame(width: MacSettingsLook.label, alignment: .trailing) .accessibilityHidden(true) control .fixedSize() "
            "Spacer(minLength: 0) } .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight)) if let note, !note.isEmpty "
            "{ MacSettingsNote(words: note) .accessibilityHidden(true) } }") in row
    fact = flat(struct(mac, "MacSettingsFact"))
    assert ".truncationMode(.middle) Spacer(minLength: 0) } .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight)) " \
           "if let note, !note.isEmpty { MacSettingsNote(words: note) } }" in fact
    note = flat(struct(mac, "MacSettingsNote"))
    assert ".padding(.leading, MacSettingsLook.label + 8)" in note


def test_the_account_card_stacks_from_the_largest_sizes():
    # (R9's review) at AX5 the card's row wanted 487 of the phone's 343, and at xxxLarge the name had 83 (39 while
    # "Signing out…"): from there the chip and Sign out go under the name, Sign out across it on up to three lines
    card = flat(struct(code(ROOT), "AccountCardView"))
    assert "let stacked = typeSize.isAccessibilitySize || typeSize == .xxxLarge" in card
    assert "HStack(alignment: stacked ? .top : .center, spacing: SettingsLook.cardGap) {" in card
    assert ("if stacked { VStack(alignment: .leading, spacing: SettingsLook.noteAbove) { trailing(row, stacked: true) } "
            ".padding(.top, SettingsLook.noteAbove) } } .frame(maxWidth: .infinity, alignment: .leading) "
            "if !stacked { trailing(row, stacked: false) } }") in card
    assert ("Text(row.label) .lineLimit(typeSize.isAccessibilitySize ? 3 : 1) .multilineTextAlignment(.center) } "
            ".buttonStyle(DWButtonStyle(size: .small, fills: stacked)) .disabled(row.busy)") in card
    assert card.count("DWChip(words: role, tone: .marked)") == 1 and card.count("Button {") == 1


def test_a_buttons_words_take_three_lines_at_the_accessibility_sizes():
    # (R9's review) Remove All Downloads, Try All Again, Keep Them and Remove, Change password, Signing in…: one line,
    # three at the accessibility sizes - the limit on the words inside the button (the innermost holds over
    # DWButtonStyle's one), the button across its row there so they can wrap
    downloads = flat(code(DOWNLOADS))
    words = flat(struct(code(DOWNLOADS), "ButtonWords"))
    assert "Text(words) .lineLimit(typeSize.isAccessibilitySize ? 3 : 1) .multilineTextAlignment(.center)" in words
    assert ("} label: { ButtonWords(words: DownloadWords.removeAll) } .buttonStyle(DWButtonStyle(kind: .danger, fills: "
            "true))") in downloads
    assert ("} label: { ButtonWords(words: DownloadWords.tryAllAgain) } "
            ".buttonStyle(DWButtonStyle(fills: typeSize.isAccessibilitySize))") in downloads
    question = flat(struct(code(DOWNLOADS), "QuestionRow"))
    assert ("let stacked = typeSize.isAccessibilitySize") in question
    assert ("if stacked { VStack(alignment: .leading, spacing: 10) { buttons(stacked: true) } } else { "
            "HStack(spacing: 12) { buttons(stacked: false) } }") in question
    assert "ButtonWords(words: AutoDownloadWords.keepThem) } .buttonStyle(DWButtonStyle(size: .small, fills: stacked))" in question
    assert ("ButtonWords(words: AutoDownloadWords.remove) } .buttonStyle(DWButtonStyle(kind: .danger, size: .small, "
            "fills: stacked))") in question
    password = flat(code(PASSWORD))
    assert ("Text(flow.changing ? OwnPassword.changing : OwnPassword.change) .lineLimit(typeSize.isAccessibilitySize ? 3 "
            ": 1) .multilineTextAlignment(.center) } } .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))") in password
    sign_in = flat(code(SIGN_IN))
    assert ("Text(lines.button) .lineLimit(typeSize.isAccessibilitySize ? 3 : 1) .multilineTextAlignment(.center) } "
            ".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))") in sign_in
    for path in (DOWNLOADS, PASSWORD, SIGN_IN, ROOT, ADDRESS):
        assert "@Environment(\\.dynamicTypeSize) private var typeSize" in code(path), path.name


def test_the_macs_downloaded_keeps_the_first_ask_and_find():
    # (R9's review) the phone's Downloaded's first ask, over the albums, as deadwax has answered with the Library's
    page = flat(code(MAC_DOWNLOADED))
    assert ("if shown == .albums, !Find.finding(typed), reachability.online, library.albums(library.scope)?.albums.isEmpty "
            "== false { FirstAskCard(macRoom: EdgeInsets(top: 16, leading: 22, bottom: 0, trailing: 22)) } "
            "content(albums: albums, playlists: playlists)") in page
    ask = flat(struct(code(APP / "Library" / "AlbumsScreen.swift"), "FirstAskCard"))
    assert "var macRoom = EdgeInsets()" in ask and ".padding(.bottom, 12) .padding(macRoom)" in ask
    # Find, as the Albums page's: at the toolbar's end, 230 wide - Core's rule (MacDownloaded.finds) on every row
    assert ("DWField(prompt: shown == .albums ? LibraryWords.findPlaceholder : LibrarySwitchWords.findPlaylists, text: "
            "$typed) .frame(width: 230)") in page
    assert "DWField(prompt: LibraryWords.findPlaceholder, text: $typed) .frame(width: 230)" in flat(code(APP / "Mac" / "Library" / "MacAlbumsPage.swift"))
    assert "MacDownloaded.finds(typed, name: row.album?.name, artist: row.album?.artist)" in page
    assert "MacDownloaded.finds(typed, name: row.name)" in page
    assert "Find.noMatchText(\"albums\", typed: typed) : LibrarySwitchWords.noPlaylistMatch(typed)" in page
    assert "selected = nil typed = \"\"" in page
    # what it still doesn't have, said in the notes: sort, Grid | List, the index, the headers
    notes = (REPO / "notes" / "ios.md").read_text(encoding="utf-8")
    section = notes[notes.index("## The redesign, slice R9"):]
    assert "What the Mac's Downloaded doesn't have" in section


def test_the_sign_in_is_held_on_both_devices():
    # (R9's review) each piece of the gate's wiring pinned, on each device: the address shown, whether deadwax asked
    # for a sign-in, the one screen kept up through its own Check and its reason with it
    for path in (SIGN_IN, MAC_SIGN_IN):
        source = flat(code(path))
        assert 'private var shownAddress: String { over ? (server.address?.description ?? "") : typed }' in source, path.name
        assert ("private var asksSignIn: Bool { if over { return server.signInOver != nil } if case .signedOut = "
                "server.launch { return true } return false }") in source, path.name
        assert "private var over: Bool { server.launch == .ready }" in source, path.name
        # the first field empty has the cursor; Check answered, the first of the two still empty
        assert ("private var firstEmpty: Field { if !over && typed.isEmpty { return .address } if form.username.isEmpty "
                "{ return .username } if form.password.isEmpty { return .password } return over ? .password : .address }") in source, path.name
        assert "DispatchQueue.main.async { focused = firstEmpty }" in source, path.name
        assert "if asks, checked { focused = form.username.isEmpty ? .username : .password }" in source, path.name
        # Return in the password: Sign in once Check has answered, Check until then - never nothing
        assert ".focused($focused, equals: .password) .onSubmit { returned() }" in source, path.name
        assert ("private func returned() { if SignInGate.returnSignsIn(asksSignIn: asksSignIn, typed: shownAddress, "
                "inUse: server.address) { submit() } else { check() } }") in source, path.name
    root = flat(code(ROOT_VIEW))
    assert ("private var showsSignIn: Bool { switch server.launch { case .needsAddress, .signedOut: return true "
            "case .checking: return signInUp case .unreachable, .ready: return false } }") in root
    assert ("case .signedOut(let reason, let why): return (reason, why) case .checking: return signInUp ? "
            "(keptReason, keptWhy) : (nil, nil) case .needsAddress, .unreachable, .ready: return (nil, nil)") in root
    assert ("case .signedOut(let reason, let why): signInUp = true keptReason = reason keptWhy = why case .needsAddress: "
            "signInUp = true keptReason = nil keptWhy = nil case .checking: break case .unreachable, .ready: signInUp = "
            "false keptReason = nil keptWhy = nil") in root
    assert "if showsSignIn { signIn(reason: signInReason.reason, why: signInReason.why) }" in root
    # the phone's Check on the address's first text baseline - flat words, no box - and under it at the largest sizes
    for path in (SIGN_IN, ADDRESS):
        source = flat(code(path))
        assert ("if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: SettingsLook.fieldGap) { "
                "addressField checkButton } } else { HStack(alignment: .firstTextBaseline, spacing: SettingsLook.fieldGap) "
                "{ addressField checkButton } }") in source, path.name
    # the Mac's dialog in a scroll view, centred while it fits: a short window or large text never loses Sign in
    mac = flat(code(MAC_SIGN_IN))
    assert ("GeometryReader { (room: GeometryProxy) in ScrollView { dialog(lines, signInOn: signInOn) "
            ".padding(.vertical, Self.side) .frame(maxWidth: .infinity, minHeight: room.size.height) } "
            ".scrollBounceBehavior(.basedOnSize) }") in mac
