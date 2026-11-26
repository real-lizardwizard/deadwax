"""
People and Server settings in the redesign's look (slice R14 - notes/ios.md "The redesign, slice R14: People and Server
settings"; the drawings People.dc.html and ServerSettings.dc.html, the Mac's, iPerson.dc.html and iServerSettings.dc.html,
the phone's, with iArtists.dc.html's rows for People's list).

The app's Swift read as text, as the other look tests read it:

- The phone is flat (R1c): no Form, no List, no grey cell - People's list on iArtists' rows, a person's permissions the
  purple switches with no lines under them, Account's rows, Revert and Save permissions in the fixed foot; Server
  settings' tabs a strip over the chosen tab's group rows, a card per setting on its hairline. Its fields are boxes: People's
  on PeopleField (the sign-in's FieldLook on the phone, the Mac's own well on the Mac), a setting's on the look's well
  (R1c's typing rule, test_ios_phone_look's TEXT_INPUTS).
- What is sent is as it was: only the ticks as the boxes show them (all five, from the flow's draft), never a permission
  the role can't hold (an admin's boxes and a refused row's locked, the flow refusing the tick); Revert drafted and sent as
  an explicit null, never a key left out; People unlocked with the admin's own Navidrome password; a secret's field a
  secure one showing its placeholder, never its value.
- The Mac's People is the list and the person chosen side by side, and its Server settings the three tabs over a box per
  setting - each drawn from the phone's own parts, so neither device decides anything apart. What the Mac reaches of the
  phone's files (the group page in Set up Navidrome, the sheets, the parts the Mac's pages draw) draws none of the
  phone's own pieces, whose sizes are 0 or the phone's on the Mac.
- Each Mac page takes two columns only where they fit, read from the bundled faces and MacLook's widths; People's list
  leaves columns out before a name loses its room, at every Row Size.
- VoiceOver hears a setting's name once (from its control) and a person's row as one element; a button whose words
  outgrow a phone's column goes across it and wraps (R14's review: DWButtonStyle holds a button that doesn't fill to one
  line), measured at the default size, xxxLarge and AX3-AX5.
- (R14's review) Each choice the review's mutations made unseen is held whole: which sheet each Account button opens on
  both devices, the set-here edge, the chips and their tones, the group marks' tones, the Mac's admin count, the person
  chosen through a lock, the time read per minute.
- Tokens only; "Queue", never "Up Next".
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_manage_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
settings_look = _load("test_ios_settings_look")
fonts = _load("ios_fonts")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def kept(text: str) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def code(name: str) -> str:
    return kept((APP / name).read_text(encoding="utf-8"))


def core(name: str) -> str:
    return kept((CORE / name).read_text(encoding="utf-8"))


def struct(text: str, name: str) -> str:
    return settings_look.struct(text, name)


def declaration(text: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = text.index(start)
    opened = text.index("{", at)
    return text[at:reader.closing(text, opened) + 1]


PEOPLE = "Manage/PeopleScreen.swift"
SHEETS = "Manage/PeopleSheets.swift"
ROOT = "Manage/ServerSettingsScreen.swift"
GROUP = "Manage/ServerSettingsGroupScreen.swift"
MAC_PEOPLE = "Mac/Manage/MacPeoplePage.swift"
MAC_SETTINGS = "Mac/Manage/MacServerSettingsPage.swift"
PHONE_FILES = (PEOPLE, SHEETS, ROOT, GROUP)
MAC_FILES = (MAC_PEOPLE, MAC_SETTINGS)
#? the phone's own pieces a page the Mac reaches must never draw there: on the Mac lookHeight is exact and DWLook's
#? target is 0 (a switch's row 0 tall, a tall row 30), and PhoneGo's, PhoneKV's and PhoneCard's sizes are the phone's;
#? (R14's review) FieldLook is the phone's sign-in field - the body's size, about 41 tall - and the Mac's fields are its own
#? well (PeopleField's Mac half, SettingWell)
PHONE_ONLY = (".phoneSwitch", "PhoneSwitchRow", "lookHeight(DWLook.here.target)", "tallRowHeight",
              "lookHeight(PhoneLook.goRow)", "PhoneGo", "PhoneKV(", "SettingsGo", "PhoneCard {", "PhoneGroup",
              "PhoneStrip", "phoneFoot", "PhoneFoot", "settingsSwitch", "Typeface.Phone", "FieldLook(")


# ----------------------------------------------------------------------------- the phone is flat

#? everything R14's files draw on the phone's path that has a fill, a face, an edge or a rule (R1c's DRAWS): a known name's
#? hairline (People), a setting card's hairline and its field's well with the set-here edge, Server settings' group rows'
#? hairlines, Connections' status dots and the save bar's hairline - PeopleFoot's and the save bar's grounds are the page's
#? own black (footFace). No grey box: a card or a row is its words on the page.
R14_DRAWS = {
    "Manage/PeopleScreen.swift": ["DWRule: DWPalette.rowRule"],
    "Manage/ServerSettingsGroupScreen.swift": ["DWRule: DWPalette.groupRule", "DWWell: focused: focus.wrappedValue",
                                               "strokeBorder: DWPalette.selbd"],
    "Manage/ServerSettingsScreen.swift": ["DWRule: DWPalette.groupRule", "fill: Self.dot(check.state)",
                                          "DWRule: DWPalette.line, DWPalette.footEdge"],
}


def test_people_and_server_settings_on_the_phone_are_flat():
    assert set(PHONE_FILES) == phone_look.R14_PAGES
    for name in PHONE_FILES:
        source = bare((APP / name).read_text(encoding="utf-8"))
        for grey in ("Form {", "List {", "Section {", ".insetGrouped", "listRowBackground(", "LabeledContent(",
                     "PhoneCard {", "DWRaised", ".listStyle("):
            assert grey not in source, f"{name}: {grey}"
    found = {}
    for name in sorted(phone_look.R14_PAGES):
        draws = phone_look.drawn(phone_look.phone_path(phone_look.bare((APP / name).read_text(encoding="utf-8"))))
        if draws:
            found[name] = draws
    assert found == R14_DRAWS, found
    # the matcher sees a face given back to a card
    card = struct(code(GROUP), "SettingCard")
    planted = phone_look.bare(card.replace(".frame(maxWidth: .infinity, alignment: .leading)",
                                           ".background(DWPalette.card, in: DWCorners.boxShape)", 1))
    assert "background: DWPalette.card" in phone_look.drawn(phone_look.phone_path(planted))
    # every page a ScrollView down the page's black, 16 in from each edge
    people = code(PEOPLE)
    for view in ("PeopleScreen", "PersonScreen"):
        page = flat(struct(people, view))
        assert "ScrollView { VStack(alignment: .leading, spacing: 0) {" in page, view
        assert ".padding(.horizontal, ManageLook.side)" in page, view
    root = flat(code(ROOT))
    assert ("ScrollView { VStack(alignment: .leading, spacing: 0) { VStack(alignment: .leading, spacing: 0) { "
            "ManageNote(words: ServerSettings.pageLine)") in root
    group = flat(declaration(code(GROUP), "private func cards("))
    assert "ScrollView { VStack(alignment: .leading, spacing: 0) {" in group and ".padding(.horizontal, ManageLook.side)" in group
    sheet = flat(struct(code(SHEETS), "PeopleSheetPage"))
    assert "ScrollView { VStack(alignment: .leading, spacing: SettingsLook.cardGap) { content }" in sheet
    assert ".background(ManageLook.sheetGround.ignoresSafeArea())" in sheet
    assert "static var sheetGround: Color { Platform.mac ? DWPalette.bg : DWPalette.page }" in code(GROUP)
    for name in ("AddPersonSheet", "ResetPasswordSheet", "RemovePersonSheet"):
        assert "NavigationStack { PeopleSheetPage {" in flat(struct(code(SHEETS), name)), name
    assert code(SHEETS).count(".presentationBackground(ManageLook.sheetGround)") == 3
    # (R14's review) Set up Navidrome's sheet - the Connections group page over the Library - on the same black, never
    # the system sheet's grey round the flat page
    navidrome = flat(struct(code(GROUP), "SetUpNavidromeSheet"))
    assert (".interactiveDismissDisabled(settings.flow.saving) .presentationBackground(ManageLook.sheetGround) }"
            in navidrome)
    assert code(GROUP).count(".presentationBackground(") == 1
    # the save bar drawn as PhoneFoot is, which the widened reading (R10's) sees as the page's own black under its
    # hairline: footFace on into the home indicator's room, under footEdge - the Mac's the panel under its line; never
    # the old `.background(.bar)`, a material's grey
    bar = flat(struct(code(ROOT), "SaveBar"))
    assert (".background { (Platform.mac ? DWPalette.panel : DWPalette.footFace) "
            ".ignoresSafeArea(.container, edges: .bottom) } "
            ".overlay(alignment: .top) { DWRule(colour: Platform.mac ? DWPalette.line : DWPalette.footEdge) }") in bar
    assert ".bar)" not in bare(code(ROOT)) and "Material" not in bare(code(ROOT))
    foot = flat(bare((APP / "Phone" / "PhoneFoot.swift").read_text(encoding="utf-8")))
    assert "DWPalette.footFace" in foot and "DWPalette.footEdge" in foot


def test_peoples_list_is_iartists_rows():
    people = flat(code(PEOPLE))
    assert ("PhoneGroup(legend: People.everyone) { ForEach(state.people) { (person: PeoplePerson) in "
            "NavigationLink(value: AppRoute.person(person.id)) { PersonRow(person: person) } .buttonStyle(.plain) } }") in people
    row = flat(struct(code(PEOPLE), "PersonRow"))
    assert "LibraryListRow(title: person.name, line: PeopleFacts.line(person)," in row
    assert "Avatar(letter: PeopleFacts.letter(person), points: LibraryLook.rowCover)" in row and "LibraryChevron()" in row
    # one element: the name, the user name and chips, the sign-ins, the library and the warning
    assert (".accessibilityElement(children: .ignore) "
            ".accessibilityLabel(PeopleFacts.spoken(person, now: Date().timeIntervalSince1970))") in row
    facts = flat(declaration(code(PEOPLE), "enum PeopleFacts"))
    assert '([person.user] + People.chips(person)).joined(separator: " \\u{00B7} ")' in facts
    assert ("([person.name, line(person), People.signInWords(person, now: now), People.libraryWords(person)] "
            "+ [People.librariesWarning(person)].compactMap { $0 }).joined(separator: \", \")") in facts


def test_a_persons_permissions_are_the_purple_switches_and_the_foot_saves():
    person = flat(struct(code(PEOPLE), "PersonScreen"))
    # iPerson: the switch says its label alone - its line is VoiceOver's hint, never drawn; a tick's warning stays
    assert ("Toggle(isOn: people.ticked(person, box.category)) { Text(box.label) } "
            ".disabled(box.locked || flow.writing != nil) .accessibilityHint(box.line) .settingsSwitch() "
            "if let warning = box.warning { ManageNote(words: warning, colour: DWPalette.amberText)") in person
    assert "Text(box.line)" not in person and code(PEOPLE).count(".settingsSwitch()") == 1
    # Account's rows: the server's changes but Make admin (the head's), Remove… in red - (R14's review) under Account's
    # legend only when there are rows: a person with refusals alone gets them as notes, no empty legend over them
    assert "let changes = offered.filter { $0.kind != .admin }" in person
    assert ".foregroundStyle(action.kind == .remove ? DWPalette.redChipText : DWPalette.text)" in person
    assert ("if !changes.isEmpty { PhoneGroup(legend: YouWords.account) { ForEach(changes, id: \\.kind) { "
            "(action: People.Action) in actionRow(action, person, flow: flow, online: online, signInOver: signInOver) "
            "} } } ForEach(People.refusals(person), id: \\.self) { (reason: String) in "
            "ManageNote(words: People.onPhone(reason)) } }") in person
    assert code(PEOPLE).count("PhoneGroup(legend: YouWords.account)") == 1
    # (R14's review) each row opens its own sheet - compared whole, so no two can trade
    assert ("Button { switch action.kind { case .reset: people.open(.reset(person.id)) case .admin: flipping = person "
            "case .remove: people.open(.remove(person.id)) } } label: { PhoneGo {") in person
    assert code(PEOPLE).count("people.open(.reset(") == 1 and code(PEOPLE).count("people.open(.remove(") == 1
    # the foot: Revert and Save permissions, only for an ordinary person whose permissions save - Save on only with a
    # change, nothing out and deadwax in reach. (R14's review) One view with the foot or without it - an inset that is
    # there or isn't - so the page keeps where it was scrolled to when the foot goes (someone made an admin): no
    # if/else round the page
    foot = flat(struct(code(PEOPLE), "PersonFoot"))
    assert ("func body(content: Content) -> some View { content .safeAreaInset(edge: .bottom, spacing: 0) { "
            "if let person, People.savesPermissions(person) { PhoneFoot { actions(person) } } } }") in foot
    assert "else" not in foot and "@ViewBuilder func body" not in foot
    assert ("Button(PeopleRevert.label) { PeopleRevert.revert(person, people: people) } "
            ".buttonStyle(DWButtonStyle(size: .large)) .disabled(!flow.dirty(person) || flow.writing != nil) "
            "Button { people.save(person) } label:") in foot
    assert (".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true)) "
            ".disabled(!flow.canSave(person, online: reachability.online, signInOver: people.signInOver))") in foot
    assert ".modifier(PersonFoot(person: flow.view == .list && people.allowed ? person : nil))" in person


def test_only_the_ticks_shown_are_sent_and_none_the_role_cant_hold():
    # each box is the flow's tick, on both devices: shown from the draft, set into it - nothing else ticks
    model = flat(code("Manage/PeopleModel.swift"))
    assert ("get: { self.flow.checkboxes(for: person).first { $0.category == category }?.checked ?? false }, "
            "set: { (on: Bool) -> Void in self.flow.tick(person, category, on) }") in model
    assert code(PEOPLE).count("people.ticked(person, box.category)") == 1
    mac = flat(code(MAC_PEOPLE))
    assert ("let off = box.locked || flow.writing != nil VStack(alignment: .leading, spacing: 2) { "
            "MacCheckbox(words: box.label, on: people.ticked(person, box.category)) .disabled(off)") in mac
    assert code(MAC_PEOPLE).count("people.ticked(") == 1
    # the flow: only an ordinary person whose permissions save, only the five, and the boxes an admin's all ticked and
    # locked (a refused row locked) - Core's, untouched by this slice
    flow = flat(core("PeopleFlow.swift"))
    assert ("guard writing == nil, People.savesPermissions(person), let saved = person.permissions, "
            "People.categories.contains(category) else { return }") in flow
    assert "People.checkboxes(admin: person.admin, refused: person.can.permissions, ticked: ticks(for: person))" in flow
    assert ("guard canSave(person, online: online, signInOver: signInOver), let ticks = ticks(for: person) else { return nil } "
            "return (begin(.permissions(id: person.id, user: person.user)), PeoplePermissionsBody(user: person.user, ticks))") in flow
    body = flat(declaration(core("People.swift"), "public struct PeoplePermissionsBody"))
    for field in ("request", "edit", "library", "downloads", "server"):
        assert f"{field} = ticks.{field}" in body, field
    # Revert puts each box back as saved through the same tick - nothing sent
    revert = flat(declaration(code(PEOPLE), "enum PeopleRevert"))
    assert ("guard let saved = person.permissions else { return } for category in People.categories { "
            "let tick = people.ticked(person, category) if tick.wrappedValue != saved[category] { "
            "tick.wrappedValue = saved[category] } }") in revert
    assert "save" not in revert.replace("saved", "")
    # both feet: Save sends the person's five, Revert is PeopleRevert's
    for name in (PEOPLE, MAC_PEOPLE):
        source = code(name)
        assert source.count("people.save(person)") == 1, name
        assert source.count("PeopleRevert.revert(person, people: people)") == 1, name
    assert "if People.savesPermissions(person) { foot(person, flow: flow, online: online) }" in mac
    foot = flat(declaration(code(MAC_PEOPLE), "private func foot("))
    assert ".disabled(!flow.dirty(person) || flow.writing != nil)" in foot
    assert ".disabled(!flow.canSave(person, online: online, signInOver: people.signInOver))" in foot


def test_people_stays_unlocked_with_the_admins_own_password():
    unlock = flat(struct(code(PEOPLE), "PeopleUnlock"))
    assert ("SecureField(People.unlockLabel, text: people.typing(\\.unlockPassword, at: .unlock)) "
            ".textContentType(.password)") in unlock
    assert ".modifier(PeopleField(focused: focused))" in unlock and unlock.count("people.unlock()") == 2
    assert ".disabled(!flow.canUnlock(online: people.online, signInOver: people.signInOver))" in unlock
    assert "if flow.view == .locked { PeopleUnlock(user: state.you) }" in flat(struct(code(PEOPLE), "PeopleStatus"))
    # (R14's review) People's fields: the sign-in's FieldLook on the phone (SignInView's own, untouched), the Mac's own
    # field on the Mac - the plain field at the field's 13 on the look's well, as SettingWell and DWField draw it
    field = flat(struct(code(PEOPLE), "PeopleField"))
    assert ("@ViewBuilder func body(content: Content) -> some View { if Platform.mac { content .textFieldStyle(.plain) "
            ".font(Typeface.Look.text(.field)) .foregroundStyle(DWPalette.fieldText) .focusEffectDisabled() "
            ".padding(.horizontal, 8) .lookHeight(DWLook.here.fieldHeight) .background { DWWell(focused: focused) } } "
            "else { content .modifier(FieldLook(focused: focused)) } }") in field
    assert code(PEOPLE).count("FieldLook(") == 1 and "FieldLook(" not in code(SHEETS)
    assert "struct FieldLook: ViewModifier" in code("Root/SignInView.swift")
    # the Mac's, locked: the phone's own parts - no field of its own
    mac = flat(code(MAC_PEOPLE))
    assert "} else { ScrollView { VStack(alignment: .leading, spacing: 0) { PeopleStatus() PeopleReadAgain() }" in mac
    assert "SecureField(" not in mac and "TextField(" not in mac
    assert "} else if flow.view == .list, let state = flow.state {" in mac


def test_a_revert_is_drafted_and_sent_as_an_explicit_null():
    revert = flat(struct(code(GROUP), "SettingRevert"))
    assert ("if let revert = row.revert { ManageWrapButton(size: .small, words: revert, action: { "
            "settings.revert(setting.key) }) { (across: Bool) in ManageButtonWords(words: revert, across: across) } }"
            in revert)
    assert code(GROUP).count("settings.revert(") == 1
    # both devices' setting: the phone's card and the Mac's box hang Revert on the chips
    card = flat(struct(code(GROUP), "SettingCard"))
    box = flat(struct(code(MAC_SETTINGS), "MacSettingBox"))
    for drawn in (card, box):
        assert ("SettingControl(setting: setting, row: row) SettingChips(row: row) { "
                "SettingRevert(setting: setting, row: row) }") in drawn
    model = flat(code("Manage/ServerSettingsModel.swift"))
    assert "func revert(_ key: String) { flow.revert(key)" in model
    settings = flat(core("ServerSettings.swift"))
    assert "case .revert: return SettingUpdate(key: entry.key, value: nil)" in settings
    update = flat(declaration(core("ServerSettings.swift"), "public func encode(to encoder: any Encoder) throws {"))
    assert "try fields.encode(value, forKey: .value)" in update and "encodeIfPresent" not in update
    # one Save sends them all: the bar's (⌘S on the Mac) - no other save on either page
    for name in (MAC_SETTINGS, GROUP):
        assert "settings.save()" not in code(name), name
    assert code(ROOT).count("settings.save()") == 1


def test_a_secret_is_shown_and_saved_as_today_and_every_field_is_a_box():
    control = flat(struct(code(GROUP), "SettingControl"))
    assert ("let value = Binding( get: { settings.flow.row(setting).value }, "
            "set: { (typed: String) -> Void in settings.edit(setting.key, typed) } )") in control
    assert ("case .field(let secret): if secret { SecureField(setting.key, text: value, prompt: Text(row.placeholder))") in control
    assert control.count(".modifier(SettingWell(focus: $focused, setHere: setHere))") == 2
    assert "TextField(setting.key, text: value, prompt: Text(row.placeholder))" in control
    # the look's well under a plain field, at the field's height on each device
    well = flat(struct(code(GROUP), "SettingWell"))
    assert (".textFieldStyle(.plain) .font(Typeface.Look.mono(.field)) .foregroundStyle(DWPalette.fieldText) "
            ".focusEffectDisabled()") in well
    assert ".lookHeight(DWLook.here.fieldHeight) .background { DWWell(focused: focus.wrappedValue)" in well
    # the Mac draws the phone's control - no field of its own
    mac = code(MAC_SETTINGS)
    assert "SecureField(" not in mac and "TextField(" not in mac
    # People's seven fields, each on PeopleField, Tab between them as before
    sheets = code(SHEETS)
    assert sheets.count(".modifier(PeopleField(focused:") == 7 and sheets.count(".textContentType(.newPassword)") == 4
    # (R14's review) and the sheets' words at the Mac's sizes there: what sets none of its own (what a write said, the
    # sheets' lines) at the Mac's field size, 13 - nothing on the phone
    page = flat(struct(sheets, "PeopleSheetPage"))
    assert (".padding(.horizontal, ManageLook.side) .padding(.vertical, SettingsLook.cardGap) "
            ".modifier(ManageMacText()) }") in page
    assert ("@ViewBuilder func body(content: Content) -> some View { if Platform.mac { content "
            ".font(Typeface.Look.text(.field)) } else { content } }") in flat(struct(sheets, "ManageMacText"))
    # the set-here edge: only while the row says Set here - never every setting with a source (R14's review's mutation)
    control = flat(struct(code(GROUP), "SettingControl"))
    assert control.count("let setHere = row.source == ServerSettings.setHere") == 1
    assert ("if setHere && !focus.wrappedValue { DWCorners.buttonShape .strokeBorder(DWPalette.selbd, lineWidth: 1)"
            in well)
    assert 'public static let setHere = "Set here"' in core("ServerSettings.swift")
    assert ("if setting.overridden && !edited { source = setHere } else if let from = setting.source, !from.isEmpty { "
            "source = \"From \\(from)\" } else { source = nil }") in flat(core("ServerSettings.swift"))


def test_the_macs_path_draws_none_of_the_phones_own_pieces():
    # the group page (Set up Navidrome's sheet) and People's sheets are drawn on the Mac whole
    for name in (GROUP, SHEETS):
        mac = settings_look.mac_path(bare((APP / name).read_text(encoding="utf-8")))
        for phone in PHONE_ONLY:
            if phone == "Typeface.Phone" and name == GROUP:
                continue
            assert phone not in mac, f"{name}: {phone} on the Mac's path"
    # the small size: the Mac's .s there, the phone's scaled one here - Typeface.Phone named only on its phone half
    group = code(GROUP)
    assert "static var small: Font { Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small) }" in group
    # a setting's key in the readout face, set where it is drawn so test_ios_readout_rows follows it to its line
    card = flat(struct(group, "SettingCard"))
    assert "Text(setting.key) .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))" in card
    assert group.count("Typeface.Phone") == 2
    # the parts of the phone's files the Mac's pages draw
    shared = {PEOPLE: ("PeopleStatus", "PeopleReadAgain", "PeopleUnlock", "PeopleField", "PeopleSaidView", "PeopleLine"),
              ROOT: ("OrganizingVerdictView", "ConnectionRow", "ServerSettingsFirstRead", "ServerSettingsRereadFailure",
                     "SaveBar", "ServerSettingsPageFrame"),
              GROUP: ("SettingControl", "SettingWell", "SettingChips", "SettingRevert", "ManageWrapButton",
                      "ManageButtonWords", "SettingWords", "RetimePart", "SavedAnswersPart", "ManageHeading",
                      "ManageNote")}
    for name, views in shared.items():
        source = bare((APP / name).read_text(encoding="utf-8"))
        for view in views:
            drawn = settings_look.mac_path(struct(source, view))
            for phone in PHONE_ONLY:
                assert phone not in drawn, f"{name} {view}: {phone}"
    for name in MAC_FILES:
        source = code(name)
        for phone in PHONE_ONLY:
            assert phone not in source, f"{name}: {phone}"
    # what each Mac page draws of them
    people = code(MAC_PEOPLE)
    for part in ("PeopleStatus()", "PeopleReadAgain()", "PeopleSaidView(said: said)", "PeopleLine(text: People.peopleOnly)",
                 "PeopleFacts.letter(person)", "MacPeopleWords.help(person, now: now)"):
        assert part in people, part
    settings = code(MAC_SETTINGS)
    for part in ("ServerSettingsRereadFailure(font: Typeface.Mac.text(.small))",
                 "OrganizingVerdictView(organizing: answer.organizing, font: Typeface.Mac.text(.small))",
                 "ConnectionRow(service: service, check: settings.checks.check(service),",
                 "SettingWords(row: row, font: Typeface.Mac.text(.small))",
                 "RetimePart(font: Typeface.Mac.text(.small), heading: false)",
                 "SavedAnswersPart(font: Typeface.Mac.text(.small))", "ServerSettingsFirstRead()"):
        assert part in settings, part


def test_the_macs_pages_are_the_phones_rules():
    settings = flat(code(MAC_SETTINGS))
    # framed as the phone's root: the save bar at its foot, ⌘S its Save, told to the model as it shows and goes
    assert code(MAC_SETTINGS).count(".serverSettingsPage(.root)") == 1
    assert ("MacFolderTabs(tabs: tabs, words: { (each: ServerSettings.Tab) -> String in "
            "ServerSettingsScreen.words(each, marks[each]) },") in settings
    assert "spoken: ServerSettings.title, ground: DWPalette.bg)" in settings
    assert "let shown = tabs.contains(tab) ? tab : tabs.first ?? tab" in settings
    # Re-time's and the saved answers' groups told to the model as their pages are on the phone - shown and hidden
    # each once, by the group drawn
    group = flat(struct(code(MAC_SETTINGS), "MacSettingsGroup"))
    assert (".onAppear { if Self.told(group.id) { settings.shows(.group(group.id)) } } "
            ".onDisappear { if Self.told(group.id) { settings.hides(.group(group.id)) } }") in group
    assert ("static func told(_ id: String) -> Bool { id == ServerSettings.lyricsGroup || "
            "id == ServerSettings.savedAnswersGroup }") in group
    assert "if group.id == ServerSettings.savedAnswersGroup && parts.answers {" in group
    # the tab a group's route opens at
    manage = flat(code("Mac/Manage/MacManage.swift"))
    assert "case .serverSettingsGroup(let id): MacServerSettingsPage(tab: ServerSettings.tab(forGroup: id))" in manage
    assert "case .person(let id): MacPeoplePage(chosen: id)" in manage
    # People: its own list over the flow's people, the person chosen kept while listed, else the first - (R14's review)
    # and kept by id while the list isn't loaded (locked again, or before the first read), let go of only when a loaded
    # list hasn't them: an unlock that runs out mid-edit no longer moves the admin off the person, and a route's person
    # isn't dropped by the empty list before the first read
    people = flat(code(MAC_PEOPLE))
    assert "MacColumnList(columns: Self.listColumns(shown), rows: state.people, selected: $selected," in people
    assert ("static func chosen(_ selected: String?, in ids: [String]?) -> String? { guard let ids else { return selected } "
            "if let selected, ids.contains(selected) { return selected } return ids.first }") in people
    assert (".onChange(of: flow.view == .list ? flow.state?.people.map(\\.id) : nil, initial: true) { "
            "(_: [String]?, ids: [String]?) -> Void in selected = Self.chosen(selected, in: ids) }") in people
    assert len(re.findall(r"\bselected = ", people)) == 2 and "selected = person.id" in people
    assert "init(chosen: String? = nil) { _selected = State(initialValue: chosen) }" in people

    def chosen(selected, ids):
        # Swift's, as pinned above
        if ids is None:
            return selected
        return selected if selected in ids else (ids[0] if ids else None)

    # a lock mid-edit, then the list read again: Kate stays chosen throughout
    assert chosen("kate", None) == "kate" and chosen(chosen("kate", None), ["ann", "kate"]) == "kate"
    # opened at a person before the first read: kept, then found
    assert chosen("kate", None) == "kate" and chosen("kate", ["ann", "kate"]) == "kate"
    # gone from a loaded list: the first; nobody in it: no one
    assert chosen("kate", ["ann", "bo"]) == "ann" and chosen("kate", []) is None and chosen(None, ["ann"]) == "ann"
    assert "if let id = selected, let person = flow.person(id) {" in people
    # the flow's one sheet, each kept for whom it was opened, its passwords gone as it goes
    assert "get: { people.flow.sheet }, set: { (shown: PeopleSheet?) -> Void in if shown == nil { people.closed() } }" in people
    for sheet in ("AddPersonSheet() .macSheet()", "ResetPasswordSheet(id: shown, person: people.flow.person(shown)) .macSheet()",
                  "RemovePersonSheet(id: shown, person: people.flow.person(shown)) .macSheet()"):
        assert sheet in people, sheet
    # Make admin asked first, flipped only as asked; Forget… asked first
    assert "if let now = people.flow.person(asked.id), now.admin == asked.admin { people.flip(now) }" in people
    assert "Button(People.forget, role: .destructive) { people.forget(entry) }" in people
    assert ".onAppear { people.shows() } .onDisappear { people.hides() people.pageGone() }" in people
    # (R14's review) the time Last signed in and the head's sign-ins are read against: the minute as it turns, never a
    # time kept from when the page opened
    assert ("TimelineView(.everyMinute) { (time: TimelineViewDefaultContext) in let now = time.date.timeIntervalSince1970 "
            "GeometryReader {") in people
    assert "@State private var now" not in people and "Date()" not in people
    assert people.count("now: now") >= 6
    # Add a person… and Lock only with the list shown, as the phone's bar
    tools = flat(declaration(code(MAC_PEOPLE), "@ViewBuilder private func tools("))
    assert "if people.allowed && flow.view == .list {" in tools
    assert ".disabled(!flow.canLock(online: online, signInOver: people.signInOver))" in tools
    # Account's changes: those the server offers, Remove… the red one, each its sheet
    account = flat(declaration(code(MAC_PEOPLE), "private func account("))
    assert "action.offered && action.kind != .admin" in account
    # (R14's review) each button and the sheet it opens, compared whole: Reset password… its own, Remove… (red) its own
    assert ("ForEach(changes.filter { $0.kind != .remove }, id: \\.kind) { (action: People.Action) in "
            "Button(action.label) { people.open(.reset(person.id)) } .buttonStyle(DWButtonStyle(size: .small)) "
            ".disabled(!open) }") in account
    assert ("ForEach(changes.filter { $0.kind == .remove }, id: \\.kind) { (action: People.Action) in "
            "Button(action.label) { people.open(.remove(person.id)) } "
            ".buttonStyle(DWButtonStyle(kind: .danger, size: .small)) .disabled(!open) }") in account
    assert account.count("people.open(") == 2
    # the only kinds besides Make admin (the head's) are those two
    assert "public enum Kind: String, Sendable, Hashable { case reset, admin, remove }" in core("People.swift")
    # (R14's review) the status bar: the people, and the admins among them - never everyone
    status = flat(declaration(code(MAC_PEOPLE), "static func status("))
    assert ("guard let state else { return [] } let admins = state.people.filter(\\.admin).count return "
            "[MacManageCount.words(state.people.count, one: MacPeopleWords.onePerson, many: MacPeopleWords.manyPeople), "
            "MacManageCount.words(admins, one: MacPeopleWords.oneAdmin, many: MacPeopleWords.manyAdmins)]") in status
    assert ".macStatus(MacStatusItems.Items(leading: Self.status(flow.view == .list ? flow.state : nil)," in people
    # (R14's review) the plan's section 4 leaves People's hints out (no data the drawing's hints come from): each
    # permission's line is its help and VoiceOver's hint on the Mac, as it is VoiceOver's alone on the phone - never drawn
    boxes = flat(declaration(code(MAC_PEOPLE), "private func permissions("))
    assert ("MacCheckbox(words: box.label, on: people.ticked(person, box.category)) .disabled(off) "
            ".opacity(off ? DWPalette.off : 1) .help(box.line) .accessibilityHint(box.line)") in boxes
    assert "Text(box.line)" not in people
    # Last signed in's cell, its whole in its help
    words = flat(declaration(code(MAC_PEOPLE), "enum MacPeopleWords"))
    assert ("if person.signedIn > 0 { return signedInNow } if let last = person.lastSignIn { "
            "return People.ago(max(0, now - last)) } return neverSignedIn") in words
    assert ".help(People.signInWords(person, now: now))" in people


def _mac_widths() -> tuple[float, float, float]:
    """The Mac's pages: at the window's opening (1280), at its smallest (880), and at its opening beside the side panel."""
    look = (CORE / "MacLook.swift").read_text(encoding="utf-8")
    sidebar = float(re.search(r"public static let sidebarWidth: Double = (\d+)", look).group(1))
    panel = float(re.search(r"public static let panelWidth: Double = (\d+)", look).group(1))
    return 1280 - sidebar, 880 - sidebar, 1280 - sidebar - panel - 1


def _number(source: str, name: str) -> float:
    found = re.search(rf"static let {name}: (?:CGFloat|Double) = (\d+(?:\.\d+)?)\b", source)
    assert found, name
    return float(found.group(1))


def _narrowest() -> float:
    """(R13's) the page beside the web's side panel at the window's opening - MacFrame's 470, wider than MacLook's 400."""
    frame = (CORE / "MacFrame.swift").read_text(encoding="utf-8")
    look = (CORE / "MacLook.swift").read_text(encoding="utf-8")
    column = float(re.search(r"public static let columnMin: Double = (\d+)", frame).group(1))
    web = float(re.search(r"public static let panelWidth: Double = (\d+)", frame).group(1))
    sidebar = float(re.search(r"public static let sidebarWidth: Double = (\d+)", look).group(1))
    return column - sidebar - web - 1


def _covers() -> dict[str, float]:
    """MacRowSize's cover at each Row Size, read from its switch."""
    rows = core("MacRowSize.swift")
    switch = declaration(rows, "public var cover: Double {")
    return {size: float(points) for size, points in re.findall(r"case \.(small|medium|large): return (\d+)", switch)}


#? the Mac's sizes the fit tests below measure at (Typeface.Mac's): the chips' (.chip: 11.5 semibold, 7 either side), a
#? small button's (.btn.sm: 12, medium for a plain one, 8 either side), the list's header (11.5 semibold) and its cells
#? (People's at .small, 12), each cell 10 in from either side of its column (.cols > div, .row > div)
MAC_CHIP, MAC_SMALL_BUTTON, MAC_HEADER, MAC_CELL, CELL_SIDE = 11.5, 12, 11.5, 12, 10


def _mac_chip(words: str) -> float:
    return fonts.words(words, MAC_CHIP, "semibold") + 2 * 7


def _mac_small_button(words: str) -> float:
    return fonts.words(words, MAC_SMALL_BUTTON, "medium") + 2 * 8


def test_each_mac_page_takes_two_columns_only_where_they_fit():
    opening, smallest, beside = _mac_widths()
    assert (opening, smallest, beside) == (1060, 660, 659)
    # the Mac's sizes measured at, as Typeface and the chip and button styles set them
    typeface = code("Shared/Typeface.swift")
    for size in ("case small = 12", "case label = 11.5", "case .chip: return .label", "case .smallButton: return .small"):
        assert size in typeface, size
    chip_style, button_style = code("Look/DWChip.swift"), code("Look/DWButtonStyle.swift")
    assert ".font(Typeface.Look.text(Platform.mac ? .chip : .facedChip).weight(.semibold))" in chip_style
    assert "smallButtonPadding: 8," in core("DWLook.swift")
    assert "case .normal, .on: return size == .large && !Platform.mac ? .semibold : .medium" in flat(button_style)
    # Server settings: two columns of boxes from the threshold, each column there holding on one line, inside its box's
    # 12 either side, the widest chips that can show together with Revert at their end. (R14's review) Every row Core
    # can make, read from its rule: where the value came from (Set here while overridden and nothing drafted, else the
    # server's source - "From the container environment" or "From .env"), Unsaved with a draft, Needs attention with an
    # error and no draft, and Revert while overridden, editable and no revert drafted - its words before what it brings
    # back, which the box folds under the chips (SettingChips' second way) and cuts, the whole in its help
    settings = code(MAC_SETTINGS)
    threshold, side, gap = (_number(settings, name) for name in ("twoColumns", "pageSide", "columnGap"))
    assert (side, gap) == (22, 18)
    assert "let columns = room.size.width >= Self.twoColumns ? 2 : 1" in settings
    cards = core("ServerSettings.swift")
    rule = flat(cards)
    assert "let edited = draft != nil let reverting = draft == .revert" in rule
    assert "unsaved: edited, attention: setting.status == \"error\" && !edited," in rule
    assert ("revert: setting.overridden && setting.editable && !reverting "
            "? revertLabel + (envValue.isEmpty ? \"\" : \" (\\(envValue))\") : nil,") in rule
    words = {name: re.search(rf'public static let {name} = "([^"]+)"', cards).group(1)
             for name in ("setHere", "unsavedBadge", "needsAttention", "revertLabel")}
    config = (REPO / "src" / "config.py").read_text(encoding="utf-8")
    body = config[config.index("def setting_source("):config.index("\ndef ", config.index("def setting_source(") + 1)]
    sources = re.findall(r'return "([^"]+)"', body)
    assert sources == ["the container environment", ".env"], sources
    chip_gap, end_gap = 6, 6 + 6  # ManageLook.chipGap between chips; the Spacer's two gaps before the end
    assert "static let chipGap: CGFloat = 6" in code(GROUP)
    assert ("HStack(alignment: .center, spacing: ManageLook.chipGap) { chips(stacked: false) Spacer(minLength: 0) end }"
            in flat(struct(code(GROUP), "SettingChips")))
    lines = {}
    for overridden in (False, True):
        for draft in (None, "text", "revert"):
            for error in (False, True):
                for source in sources:
                    edited = draft is not None
                    shown = [words["setHere"] if overridden and not edited else f"From {source}"]
                    shown += [words["unsavedBadge"]] if edited else []
                    shown += [words["needsAttention"]] if error and not edited else []
                    revert = overridden and draft != "revert"
                    line = sum(_mac_chip(chip) for chip in shown) + chip_gap * (len(shown) - 1)
                    if revert:
                        line += end_gap + _mac_small_button(words["revertLabel"])
                    lines[tuple(shown) + ((words["revertLabel"],) if revert else ())] = line
    widest = max(lines, key=lines.get)
    assert widest == ("From the container environment", "Unsaved", "Revert to the environment"), widest
    column = (threshold - 2 * side - gap) / 2
    assert lines[widest] <= column - 2 * 12, (lines[widest], column)
    # and no wider than that asks: a threshold 10 over what the widest needs
    assert threshold - 10 <= 2 * (lines[widest] + 2 * 12) + gap + 2 * side, (threshold, lines[widest])
    assert opening >= threshold > max(smallest, beside)
    # People: the list 398 at most, 42% of the page under that, 260 at least; the panel the rest less the rule. Its two
    # columns 1.15 : 1 inside its 16 either side, 14 apart - from the threshold, where Account still holds Reset
    # password… and Remove… on one line inside its box (small buttons at 12, 8 either side, 6 apart)
    people = code(MAC_PEOPLE)
    assert "min(398, max(260, page * 0.42))" in people
    panel_threshold, panel_side, column_gap = (_number(people, name) for name in ("twoColumns", "panelSide", "columnGap"))
    assert "return (inside * 1.15 / 2.15, inside / 2.15)" in people
    assert "let inside = max(0, width - 2 * panelSide - columnGap)" in people

    def panel(page: float) -> float:
        return page - min(398, max(260, page * 0.42)) - 1

    account = (panel_threshold - 2 * panel_side - column_gap) / 2.15
    buttons = sum(fonts.words(words, 12, "semibold") + 2 * 8 for words in ("Reset password…", "Remove…")) + 6
    assert buttons <= account - 2 * 12, (buttons, account)
    assert panel(opening) >= panel_threshold > max(panel(smallest), panel(beside)), (panel(opening), panel(smallest))
    assert "if room.size.width >= Self.twoColumns {" in people


#? (R14's review) the columns People's list draws, at each page the Mac shows it in - the window's opening, its
#? smallest, the opening beside MacLook's side panel and beside the web's wider one (R13's 589) - at each Row Size: all
#? three at the opening; Person and Role at the smallest and beside the panel; at 589 Person and Role at Small, Person
#? alone at Medium and Large, whose bigger marks take the room Role would
PEOPLE_COLUMNS = {
    1060: {"small": ["person", "role", "lastSignedIn"], "medium": ["person", "role", "lastSignedIn"],
           "large": ["person", "role", "lastSignedIn"]},
    660: {"small": ["person", "role"], "medium": ["person", "role"], "large": ["person", "role"]},
    659: {"small": ["person", "role"], "medium": ["person", "role"], "large": ["person", "role"]},
    589: {"small": ["person", "role"], "medium": ["person"], "large": ["person"]},
}
#? the room a name and user name keep in the Person cell at every Row Size: Playlist's (MacAlbumFacts.playlistLeast, 160
#? at Small) less its sides, its cover and the gap - a cover and a name, as People's cell is
NAME_ROOM = 112


def test_the_macs_people_list_leaves_columns_out_before_a_name_loses_its_room():
    # (R14's review) at 660 the list was 277 wide and Person 63 of it (46 at 589): no room for a name. Person keeps its
    # least beside the others; Last signed in is left out first, then Role - each still said in the Person cell's help
    people = code(MAC_PEOPLE)
    page = flat(people)
    assert "enum Column: CaseIterable { case person, role, lastSignedIn }" in page
    assert ("static func shown(width: Double, size: MacRowSize) -> [Column] { var shown = Column.allCases "
            "while shown.count > 1 && width - fixedWidth(shown) < personLeast(size) { shown.removeLast() } "
            "return shown }") in page
    assert "static func personLeast(_ size: MacRowSize) -> Double { personLeast + size.coverGrowth }" in page
    assert ("case .person: return sum case .role: return sum + roleWidth "
            "case .lastSignedIn: return sum + lastSignedInWidth") in page
    assert "let shown = Self.shown(width: Double(width), size: rowSize)" in page
    assert "if shown.indices.contains(column) { cell(person, shown[column], now: now) }" in page
    assert "list(state, width: width, now: now, flow: flow, online: online) .frame(width: width)" in page
    assert "let width = Self.listWidth(room.size.width)" in page
    role, last, least = (_number(people, name) for name in ("roleWidth", "lastSignedInWidth", "personLeast"))
    gap = _number(people, "markGap")
    covers = _covers()
    assert covers == {"small": 20, "medium": 28, "large": 40}
    assert "public var coverGrowth: Double { cover - Self.small.cover }" in core("MacRowSize.swift")
    assert "Avatar(letter: PeopleFacts.letter(person), points: CGFloat(rowSize.cover))" in page
    assert least - 2 * CELL_SIDE - covers["small"] - gap == NAME_ROOM
    fixed = {"person": 0, "role": role, "lastSignedIn": last}
    pages = dict(zip((1060, 660, 659), _mac_widths()))
    pages[589] = _narrowest()
    assert list(pages.values()) == [1060, 660, 659, 589]

    def shown(width: float, size: str) -> list[str]:
        # Swift's, as pinned above
        columns = ["person", "role", "lastSignedIn"]
        while len(columns) > 1 and width - sum(fixed[c] for c in columns) < least + covers[size] - covers["small"]:
            columns.pop()
        return columns

    for at, page_width in pages.items():
        width = min(398, max(260, page_width * 0.42))
        for size, cover in covers.items():
            drawn = shown(width, size)
            assert drawn == PEOPLE_COLUMNS[at][size], (at, size, drawn)
            person = width - sum(fixed[c] for c in drawn)
            assert person - 2 * CELL_SIDE - cover - gap >= NAME_ROOM, (at, size, person)
    # each column drawn holds its header and its words on one line
    words = declaration(code(MAC_PEOPLE), "enum MacPeopleWords")
    said = dict(re.findall(r'static let (\w+) = "([^"]+)"', words))
    for header, width in ((said["role"], role), (said["lastSignedIn"], last)):
        assert fonts.words(header, MAC_HEADER, "semibold") <= width - 2 * CELL_SIDE, header
    for cell in (said["admin"], said["ordinary"]):
        assert fonts.words(cell, MAC_CELL) <= role - 2 * CELL_SIDE, cell
    # Last signed in's cell: "now", "never", or how long ago (People.ago - the widest a minute short of an hour, or
    # ten years in months)
    for cell in (said["signedInNow"], said["neverSignedIn"], "just now", "59 minutes ago", "23 hours ago",
                 "59 days ago", "120 months ago"):
        assert fonts.words(cell, MAC_CELL) <= last - 2 * CELL_SIDE, cell
    # the Person cell: the name before the user name (the user name is cut first), and the whole in its help - their
    # display name, user name, role and sign-ins
    cell = flat(declaration(code(MAC_PEOPLE), "@ViewBuilder private func cell("))
    assert ("Text(person.name) .foregroundStyle(DWPalette.head) .lineLimit(1) .layoutPriority(1) Text(person.user) "
            ".font(Typeface.Mac.mono(.label)) .foregroundStyle(DWPalette.t2) .lineLimit(1) .truncationMode(.middle)") in cell
    assert ".help(MacPeopleWords.help(person, now: now)) case .role:" in cell
    assert ('[person.name, person.user, role(person), People.signInWords(person, now: now)]'
            '.joined(separator: " \\u{00B7} ")') in flat(words)
    assert ".help(People.signInWords(person, now: now))" in cell


def test_the_macs_person_head_gives_the_name_its_room():
    # (R14's review) at a one-column panel (382 at the smallest window) the chips beside the name left it some 100
    # points: there they go under the words, across the panel - beside them only in a two-column panel
    people = code(MAC_PEOPLE)
    page = flat(people)
    assert "head(person, now: now, beside: room.size.width >= Self.twoColumns, flow: flow, online: online)" in page
    head = flat(declaration(people, "private func head("))
    assert (".fixedSize(horizontal: false, vertical: true) .frame(maxWidth: .infinity, alignment: .leading) "
            ".accessibilityElement(children: .combine) if beside { VStack(alignment: .trailing, spacing: 8) { "
            "VStack(alignment: .trailing, spacing: 4) { chips(person) } flipButton(person, flow: flow, online: online) } "
            ".fixedSize() } }") in head
    assert ("if !beside { ViewThatFits(in: .horizontal) { HStack(spacing: 6) { chips(person) "
            "flipButton(person, flow: flow, online: online) } VStack(alignment: .leading, spacing: 6) { "
            "VStack(alignment: .leading, spacing: 4) { chips(person) } flipButton(person, flow: flow, online: online) "
            "} } }") in head
    mark, head_gap, side, threshold = (_number(people, name) for name in ("headMark", "headGap", "panelSide", "twoColumns"))
    chips = re.search(r"public static func chips\(_ person: PeoplePerson\) -> \[String\] \{(.*?)\n    \}",
                      core("People.swift"), re.S).group(1)
    every = re.findall(r'\["([^"]+)"\]', chips)
    assert every == ["You", "Admin", "deadwax's own account", "Can't sign in to deadwax"], every
    people_core = core("People.swift")
    assert 'Action(kind: .admin, label: person.admin ? "No longer admin" : "Make admin", refused: person.can.admin)' in \
        flat(people_core)
    flips = ["No longer admin", "Make admin", re.search(r'public static let changing = "([^"]+)"', people_core).group(1)]
    widest = max([_mac_chip(chip) for chip in every] + [_mac_small_button(flip) for flip in flips])
    opening, smallest, beside = _mac_widths()
    for page_width in (opening, smallest, beside, _narrowest()):
        panel = page_width - min(398, max(260, page_width * 0.42)) - 1
        words = panel - 2 * side - mark - head_gap
        if panel >= threshold:
            words -= head_gap + widest
        # the name at h2, 20 bold: "Christine McVie", say, in one line beside its mark - and 200 at the least, the
        # narrowest panel's (589's, beside the web's side panel); the chips beside it at 382 left some 100
        assert words >= fonts.words("Christine McVie", 20, "bold"), (page_width, panel, words)
        assert words >= 200, (page_width, panel, words)
    # a setting's name is read once, from its control: the card's and the box's legends are hidden from VoiceOver
    card = flat(struct(code(GROUP), "SettingCard"))
    assert ".textSelection(.enabled) .accessibilityHidden(true) SettingControl(" in card
    box = flat(struct(code(MAC_SETTINGS), "MacSettingBox"))
    assert ".help(setting.key) .accessibilityHidden(true)" in box
    control = flat(struct(code(GROUP), "SettingControl"))
    # the Mac's menu, the phone's, the secure field and the field each say the setting's name; Locked says it with why
    assert control.count(".accessibilityLabel(setting.key)") == 4
    assert '.accessibilityLabel("\\(setting.key), \\(ServerSettings.locked)")' in control
    assert ".accessibilityLabel(setting.key) .accessibilityValue(Self.chosen(choices, value: row.value))" in control
    # the chips read as one; on one line with the end, else the end under them (laid out in the width it's given, so a
    # long Revert wraps or is cut there), the chips on one line over it or a chip a line where even they don't fit
    chips = flat(struct(code(GROUP), "SettingChips"))
    assert ("ViewThatFits(in: .horizontal) { HStack(alignment: .center, spacing: ManageLook.chipGap) { "
            "chips(stacked: false) Spacer(minLength: 0) end } VStack(alignment: .leading, spacing: ManageLook.chipGap) { "
            "ViewThatFits(in: .horizontal) { chips(stacked: false) chips(stacked: true) } end } }") in chips
    assert chips.count("chips(stacked: false)") == 2 and chips.count("chips(stacked: true)") == 1
    assert ".accessibilityElement(children: .ignore) .accessibilityLabel(shown.map(\\.words).joined(separator: \", \"))" in chips
    # the sheets' buttons and the foot's Save take three lines at the accessibility sizes, across their row
    sheets = flat(code(SHEETS))
    assert sheets.count(".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)") == 3
    assert sheets.count("size: .large, fills: true))") == 3
    assert ".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)" in flat(struct(code(PEOPLE), "PersonFoot"))
    # a person's head stacks from xxxLarge, Make admin outside the words read as one
    head = flat(declaration(code(PEOPLE), "private func head("))
    assert "let stacked = typeSize.isAccessibilitySize || typeSize == .xxxLarge" in head
    assert ".accessibilityElement(children: .combine) if !stacked, let flip {" in head
    # the strip says what it is
    assert "spoken: ServerSettings.title" in flat(code(ROOT))


#? (R14's review) Apple's .footnote at the sizes the review measured at - the default (large), xxxLarge and AX3-AX5 - which
#? the phone's button type scales with (Typeface.Look's .button 14 and .smallButton 13.5, relativeTo .footnote)
FOOTNOTE = {"large": 13, "xxxLarge": 19, "AX3": 33, "AX4": 38, "AX5": 44}
#? a 375-point phone's page inside ManageLook.side either side - a card's width, and the save bar's inside its sides
COLUMN = 375 - 2 * 16
#? ProgressView's spinner beside a button's words, and the label's gap of 8
SPINNER = 20 + 8


def _phone_button(words: str, role: str = "button", faced: bool = False, spinner: bool = False) -> dict[str, float]:
    """A phone button's width on one line at each size: a flat one's words at medium, 6 either side; the purple and the
    red (faced) at semibold, 16 either side."""
    points = {"button": 14, "smallButton": 13.5}[role]
    padding = 16 if faced else 6
    return {size: fonts.words(words, points * footnote / FOOTNOTE["large"], "semibold" if faced else "medium")
            + 2 * padding + (SPINNER if spinner else 0) for size, footnote in FOOTNOTE.items()}


def test_a_button_whose_words_outgrow_a_phones_column_goes_across_it_and_wraps():
    # the sizes and rooms measured with, as Typeface, DWLook and DWButtonStyle set them
    typeface = code("Shared/Typeface.swift")
    assert "case .button: return (14, .footnote)" in typeface and "case .smallButton: return (13.5, .footnote)" in typeface
    look = (CORE / "DWLook.swift").read_text(encoding="utf-8")
    assert re.search(r"buttonPadding: 6,\s+// dw\.ph: \.btn padding-left", look)
    assert re.search(r"smallButtonPadding: 6,\s+// dw\.ph: \.btn\.sm padding-left", look)
    assert "public static let facedPadding: Double = 16" in look and "public static let smallFacedPadding: Double = 16" in look
    # (R14's review) why: DWButtonStyle holds a button that doesn't fill to its words on one line - a line limit on the
    # words can't wrap it (and it isn't R14's to change) - so a button that must wrap goes across its row (`fills`)
    style = flat(code("Look/DWButtonStyle.swift"))
    assert style.count(".lineLimit(1) .fixedSize(horizontal: !fills, vertical: false)") == 2
    # the buttons the review measured, as the phone draws them, from Core's words
    retime = core("ServerSettings.swift")
    running = re.search(r'total != 0 \? "(Re-timing [^"]+)"', retime).group(1)
    running = running.replace("\\(min(done + 1, total))", "4").replace("\\(total)", "60")
    assert running == "Re-timing 4 of 60 albums · Stop after this album", running
    said = {name: re.search(rf'public static let {name} = "([^"]+)"', retime).group(1)
            for name in ("button", "clear", "revertLabel", "discard", "save", "tryAgain")}
    widths = {
        "running": _phone_button(running, spinner=True),
        "revert": _phone_button(said["revertLabel"] + " (http://navidrome:4533)", "smallButton"),
        "retime": _phone_button(said["button"]),
        "clear": _phone_button(said["clear"], faced=True),
        # the save bar's two side by side, 12 apart
        "bar": {size: a + 12 + b for (size, a), b in zip(_phone_button(said["discard"]).items(),
                                                         _phone_button(said["save"], faced=True).values())},
    }
    # where each first outgrows the column: Re-time's running button at the default size (some 354), Revert and what it
    # brings back at xxxLarge (337 at the default, 487 there), Clear at xxxLarge (373), Re-time saved lyrics at AX3
    # (351), the save bar's pair at AX3 (418)
    first = {name: next(size for size, width in each.items() if width > COLUMN) for name, each in widths.items()}
    assert first == {"running": "large", "revert": "xxxLarge", "retime": "AX3", "clear": "xxxLarge", "bar": "AX3"}, first
    # each drawn so it goes across the card and wraps: ManageWrapButton - one line as drawn while it fits, else across
    # the width (fills), its words as many lines as they take on the phone, cut on one line on the Mac with the whole in
    # its help (a Mac button is 26 tall)
    group = code(GROUP)
    wrap = flat(struct(group, "ManageWrapButton"))
    assert ("var body: some View { ViewThatFits(in: .horizontal) { button(across: false) button(across: true) } "
            ".help(words) }") in wrap
    assert ("Button(action: action) { label(across) } .buttonStyle(DWButtonStyle(kind: kind, size: size, fills: across))"
            in wrap)
    assert ("Text(words) .lineLimit(across && !Platform.mac ? nil : 1) .multilineTextAlignment(.center) "
            ".fixedSize(horizontal: false, vertical: across && !Platform.mac)") in flat(struct(group, "ManageButtonWords"))
    part = flat(struct(group, "RetimePart"))
    assert ("ManageWrapButton(words: run.runningLabel, action: { settings.stopRetime() }) { (across: Bool) in "
            "HStack(spacing: 8) { ProgressView() .accessibilityHidden(true) "
            "ManageButtonWords(words: run.runningLabel, across: across) } } .disabled(run.stopping)") in part
    assert ("ManageWrapButton(words: RetimeRun.button, action: { settings.startRetime() }) { (across: Bool) in "
            "ManageButtonWords(words: RetimeRun.button, across: across) } "
            ".disabled(!settings.retimeOpen(online: reachability.online))") in part
    assert not re.search(r"\bButton\(", part) and "DWButtonStyle" not in part
    answers = flat(struct(group, "SavedAnswersPart"))
    assert ("ManageWrapButton(kind: .danger, words: answers.label, action: { asking = true }) { (across: Bool) in "
            "HStack(spacing: 8) { ManageButtonWords(words: answers.label, across: across)") in answers
    assert len(re.findall(r"\bButton\(", answers)) == 2 and "DWButtonStyle" not in answers  # the question's, iOS's
    assert "ManageWrapButton(size: .small, words: revert," in flat(struct(group, "SettingRevert"))
    # the save bar: beside its words while all of it fits; else the words over the buttons, side by side while they fit
    # the bar, else one over the other, each across it, its words wrapping
    bar = flat(struct(code(ROOT), "SaveBar"))
    assert ("ViewThatFits(in: .horizontal) { HStack(spacing: 12) { words(flow) Spacer(minLength: 8) "
            "buttons(flow, across: false) } VStack(alignment: .leading, spacing: 10) { words(flow) "
            "ViewThatFits(in: .horizontal) { HStack(spacing: 12) { buttons(flow, across: false) } "
            "VStack(spacing: 8) { buttons(flow, across: true) } } } }") in bar
    for words in ("ServerSettings.tryAgain", "ServerSettings.discard",
                  "flow.saving ? ServerSettings.saving : ServerSettings.save"):
        assert f"ManageButtonWords(words: {words}, across: across)" in bar, words
    assert bar.count("fills: across))") == 3 and bar.count(".buttonStyle(") == 3
    # one over the other, each alone across the bar, every one fits from the default to AX5 - Save changes wraps at AX5
    # (345), as across it may
    for alone in (_phone_button(said["discard"]), _phone_button(said["tryAgain"])):
        assert alone["AX5"] <= COLUMN, alone
    # every other button of R14's phone pages fits a column on one line at every size: Try again (the first read's
    # purple, a reread's small), Check again, Forget… (Forgetting… with its spinner), Clearing… with its spinner
    connections = re.search(r'public static let checkAgain = "([^"]+)"', retime)
    others = [_phone_button(said["tryAgain"], faced=True), _phone_button(said["tryAgain"], "smallButton"),
              _phone_button(connections.group(1)),
              _phone_button(re.search(r'public static let forgetting = "([^"]+)"', core("People.swift")).group(1),
                            "smallButton", spinner=True),
              _phone_button(re.search(r'public static let clearingLabel = "([^"]+)"', retime).group(1), faced=True,
                            spinner=True)]
    for other in others:
        assert other["AX5"] <= COLUMN, other


def test_the_chips_and_the_marks_say_what_they_mean_in_their_tones():
    # (R14's review) a setting's chips: where its value came from (Set here purple, a source plain), Unsaved purple,
    # Needs attention amber - each in the row's order, none left out
    chips = flat(struct(code(GROUP), "SettingChips"))
    assert ("static func chips(_ row: ServerSettings.Row) -> [SettingChip] { var chips: [SettingChip] = [] "
            "if let source = row.source { chips.append(SettingChip(words: source, "
            "tone: source == ServerSettings.setHere ? .marked : .plain)) } "
            "if row.unsaved { chips.append(SettingChip(words: ServerSettings.unsavedBadge, tone: .marked)) } "
            "if row.attention { chips.append(SettingChip(words: ServerSettings.needsAttention, tone: .caution)) } "
            "return chips }") in chips
    assert "ForEach(shown, id: \\.words) { (chip: SettingChip) in DWChip(words: chip.words, tone: chip.tone) }" in chips
    # a group's mark, on the phone's root and over the Mac's group: Needs attention amber, Unsaved purple
    mark = "DWChip(words: ServerSettings.markWords(mark), tone: mark == .attention ? .caution : .marked)"
    assert mark in flat(struct(code(ROOT), "GroupRow")) and mark in flat(struct(code(MAC_SETTINGS), "MacSettingsGroup"))
    assert ("public static func markWords(_ mark: Mark) -> String { mark == .attention ? needsAttention : unsavedBadge }"
            in flat(core("ServerSettings.swift")))
    # and what each tone is: .caution the amber chip, .marked the accent's purple
    tones = flat(code("Look/DWChip.swift"))
    assert "case .caution: return DWPalette.amberText" in tones and "case .marked: return DWPalette.acct" in tones


def test_a_choice_is_a_whole_row_to_tap_on_the_phone():
    # (R14's review) out of a Form's row a menu Picker takes a tap on its own words alone: on the phone the choice is a
    # Menu whose label is the whole row, at least a finger's 44 tall, the Picker's choices inline in it; the Mac keeps
    # its menu Picker
    control = struct(code(GROUP), "SettingControl")
    phone = flat(phone_look.phone_path(control))
    assert ("Menu { Picker(selection: value) { ForEach(choices) { (choice: ServerSettings.Choice) in "
            "Text(choice.label).tag(choice.value) } } label: { Text(setting.key) } .pickerStyle(.inline) } label: { "
            "HStack(spacing: 6) { Text(Self.chosen(choices, value: row.value)) .font(Typeface.Look.text(.field)) "
            ".foregroundStyle(DWPalette.acc) .multilineTextAlignment(.leading) DWCaret(colour: DWPalette.acc) "
            "Spacer(minLength: 0) } .frame(maxWidth: .infinity, minHeight: CGFloat(DWLook.here.target), alignment: .leading) "
            ".contentShape(Rectangle()) } .menuStyle(.button) .menuIndicator(.hidden) .buttonStyle(.plain)") in phone
    assert ".pickerStyle(.menu)" not in phone
    assert re.search(r"static let onPhone = DWLook\((?:(?!\)\n).)*?target: 44,", core("DWLook.swift"), re.S)
    mac = flat(settings_look.mac_path(bare(control)))
    assert ".pickerStyle(.menu) .labelsHidden()" in mac and "Menu {" not in mac
    # the row says the choice in its words; a value the choices don't hold, as itself
    assert ("static func chosen(_ choices: [ServerSettings.Choice], value: String) -> String { choices.first { "
            "(choice: ServerSettings.Choice) -> Bool in choice.value == value }?.label ?? value }") in flat(control)


def test_tokens_only_and_the_queue_is_the_queue():
    for name in PHONE_FILES + MAC_FILES:
        source = bare((APP / name).read_text(encoding="utf-8"))
        for raw in ("Color(", "Color.red", "Color.gray", ".opacity(0.", ".font(.system", "cornerRadius", "UIColor"):
            assert raw not in source, f"{name}: {raw}"
        # the redesign's palette alone - never the old Palette's
        assert not re.search(r"(?<![A-Za-z])Palette\.", source), name
        assert "Up Next" not in kept((APP / name).read_text(encoding="utf-8")), name
