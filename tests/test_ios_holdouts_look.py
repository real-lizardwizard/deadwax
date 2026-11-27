"""
The panel review's slice R20, the known holdouts (notes/ios.md "The panel review, R20: the known holdouts
(2026-11-26)"): the pages docs/ios.md listed as "Not flat yet" - Settings > Debug, an artist's Artist images, Move
albums and Which artist is this? sheets, and the pages Edit album's Release pushes (Choose a release, Changes, Compare
covers, the full cover) - drawn from the canvas's pieces, since no drawing has them (James, 26 Nov): flat on the phone
(R1c), the Mac's groups on the Mac. Read from the Swift source, as the other ios tests read theirs.

What it holds: no List, Form, Section, grey row or old type left in what was redrawn; what each draws on the phone,
pinned (only marks: the page's black, hairlines, the chosen outline); the Mac's groups as MacGroupBox draws them, and no
phone piece on the Mac's path; Debug's measurements in Courier Prime, its words not; each writer's confirmation as it
was (Move under its preview, Save, Replace cover only) and Choose a release only choosing; every place you type on the
look's well; and R10's pieces of the Release file - ReleaseCards, its year's face, ReleaseFoot, RetagPressingRow - byte
for byte as R10 drew them.
"""

import hashlib
import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
DEBUG = "You/DebugView.swift"
IMAGES = "Artist/ArtistImagesSheet.swift"
MOVE = "Artist/ArtistMoveSheet.swift"
RELEASE = "Edit/ReleasePage.swift"
DOCS = REPO / "docs" / "ios.md"


def _load(name: str):
    path = Path(__file__).resolve().parent / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"_holdouts_look_{name}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
settings_look = _load("test_ios_settings_look")


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def kept(text: str) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def body(code: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = code.index(start)
    opened = code.index("{", at)
    return code[at:reader.closing(code, opened) + 1]


def redrawn(name: str) -> str:
    """What R20 redrew in a file, comments blanked and literals kept: Debug and Move albums' whole (Move albums' sheet
    keeps its bars), Artist images from its root on (the sheet's toolbar, escape and dialog are as they were), and the
    Release file from Choose a release on (what is before it is R10's)."""
    text = kept(source(name))
    start = {IMAGES: "/// Artist images' page", RELEASE: "/// Choose a release (phase8-managing.md 3.3)"}.get(name)
    if start:
        text = text[source(name).index(start):]
    return text


#? what a grouped list or iOS's grey was drawn with, and the old type and palette - none of it in what R20 redrew
OLD = re.compile(r"\b(Form|List|Section)\s*[({]|ContentUnavailableView|\.insetGrouped|\.(bordered|borderless)\b|"
                 r"Material\b|listRowBackground|LabeledContent|labeledContentStyle|(?<![\w.])Palette\.|"
                 r"(?<![\w.])Corners\.|MacCorners|Typeface\.(headline|footnote|subheadline|title3|title2|body|caption2?|"
                 r"callout)\b|Typeface\.(readout|mono)\(|PrimaryFace|SecondaryPill|\.foregroundStyle\(\.(primary|red)\)|"
                 r"Color\.(black|white|red|gray)\b|\.font\(\.system")


def test_no_list_form_or_grey_is_left_in_what_was_redrawn():
    for name in (DEBUG, IMAGES, MOVE, RELEASE):
        found = [match.group(0) for match in OLD.finditer(bare(redrawn(name)))]
        assert not found, f"{name}: {found}"
    # the pages are the holdouts' pieces: HoldoutPage of HoldoutGroups (Release's are phone pages of their own)
    assert flat(bare(source(DEBUG))).count("HoldoutPage {") == 1  # Debug's body
    images = bare(redrawn(IMAGES))
    assert images.count("HoldoutPage {") == 2 and "HoldoutUnavailable(title: ArtistManageWords.imagesTitle" in images
    move = bare(redrawn(MOVE))
    assert move.count("HoldoutPage {") == 2
    assert "HoldoutUnavailable(title: ArtistManageWords.refileTitle" in move
    assert "HoldoutUnavailable(title: ArtistManageWords.whoTitle" in move
    # each sheet on the page's ground, not the system's raised grey
    assert source(IMAGES).count(".presentationBackground(HoldoutLook.ground)") == 1
    assert source(MOVE).count(".presentationBackground(HoldoutLook.ground)") == 2
    assert "static var ground: Color { Platform.mac ? DWPalette.bg : DWPalette.page }" in source(DEBUG)


#? (R1c) what each draws on the phone that has a fill or an edge: only marks - the page's black, a group row's hairline,
#? the chosen picture's outline in the accent (its square edge, Corners.artShape's 0) - and on the Release file R10's
#? Current badge, the pages' black, a missing cover's square hairline, a list row's hairline and the full cover's black
R20_DRAWS = {
    DEBUG: ["background: DWPalette.page", "DWRule: DWPalette.groupRule"],
    IMAGES: ["DWRule: DWPalette.groupRule", "strokeBorder: DWPalette.acc"],
    MOVE: [],
    RELEASE: ["DWRule: DWPalette.groupRule", "background: Palette.badgeFill",
              "background: DWPalette.page", "background: DWPalette.page", "strokeBorder: DWPalette.line",
              "background: DWPalette.page", "strokeBorder: DWPalette.line", "DWRule: DWPalette.rowRule",
              "ZStack: DWPalette.page"],
}


def test_the_phone_draws_only_marks():
    found = {name: phone_look.drawn(phone_look.phone_path(bare(source(name)))) for name in R20_DRAWS}
    assert found == R20_DRAWS, {name: draws for name, draws in found.items() if draws != R20_DRAWS[name]}
    # the phone's group is PhoneGroup with Settings' note, its page SettingsPage on the black
    page = bare(body(bare(source(DEBUG)), "struct HoldoutPage<Content: View>: View {"))
    mac, phone = phone_look.halves(page, "if Platform.mac {")
    assert phone == " SettingsPage { content } .background(DWPalette.page) ", phone
    group = bare(body(bare(source(DEBUG)), "struct HoldoutGroup<Content: View>: View {"))
    mac, phone = phone_look.halves(group, "if Platform.mac {")
    assert "PhoneGroup(legend: legend) { content }" in phone and "SettingsNote(words: note)" in phone
    # a row: 10 above and below its words, 42 tall at least (.kv), on the group's hairline
    row = flat(bare(body(bare(source(DEBUG)), "@ViewBuilder func holdoutRow() -> some View {")))
    mac, phone = phone_look.halves(row, "if Platform.mac {")
    assert mac == " padding(.vertical, HoldoutLook.macRowRoom) ", mac
    assert phone == (" padding(.vertical, HoldoutLook.rowRoom) .frame(maxWidth: .infinity, alignment: .leading) "
                     ".lookHeight(PhoneLook.kvRow) .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) } "), phone


def test_the_macs_groups_are_the_macs():
    group = flat(bare(body(bare(source(DEBUG)), "struct HoldoutGroup<Content: View>: View {")))
    mac, _ = phone_look.halves(group, "if Platform.mac {")
    # .group.onbg: the box's corners in the line's edge, the legend 11.5 semibold in the label's colour, set 10 in and 8
    # up into the top edge on --bg, 6 either side and 16 tall; 14 12 12 12 inside
    assert ".padding(HoldoutLook.macGroup)" in mac
    assert ".overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))" in mac
    assert (".font(Typeface.Look.text(.chip).weight(.semibold)) .foregroundStyle(DWPalette.label) .lineLimit(1) "
            ".padding(.horizontal, HoldoutLook.macLegendSide) .frame(height: HoldoutLook.macLegendHeight) "
            ".background(DWPalette.bg) .offset(x: HoldoutLook.macLegendIn, y: HoldoutLook.macLegendUp) "
            ".accessibilityAddTraits(.isHeader)") in mac
    # (R20's review) and the box whole is MacGroupBox's own, its names put back - a fill, an edge or a padding added to
    # either fails: a shared file can't name MacGroupBox, so the two are held together here
    box = mac[mac.index("{ ") + 2:mac.index(" if let note")]
    for name, value in (("HoldoutLook.macGroup", "EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12)"),
                        ("Typeface.Look.text(.chip)", "Typeface.Mac.text(.label)"),
                        ("HoldoutLook.macLegendSide", "6"), ("HoldoutLook.macLegendHeight", "16"),
                        ("DWPalette.bg", "ground"), ("HoldoutLook.macLegendIn", "10"), ("HoldoutLook.macLegendUp", "-8")):
        box = box.replace(name, value)
    box = re.sub(r"\{ if let legend \{ (.*?) \} \}", r"{ \1 }", box)
    macs = flat(bare(body(bare((APP / "Mac" / "Components" / "MacGroupBox.swift").read_text(encoding="utf-8")),
                          "var body: some View {")))
    assert f"var body: some View {{ {box} }}" == macs, (box, macs)
    # the page: a scroll of the groups 24 apart, padded as Settings' page, on --bg
    page = flat(bare(body(bare(source(DEBUG)), "struct HoldoutPage<Content: View>: View {")))
    mac_page, _ = phone_look.halves(page, "if Platform.mac {")
    assert mac_page == (" ScrollView { VStack(alignment: .leading, spacing: HoldoutLook.macGroupGap) { content } "
                        ".padding(HoldoutLook.macPage) .frame(maxWidth: .infinity, alignment: .leading) } "
                        ".background(DWPalette.bg) "), mac_page
    look = source(DEBUG)
    assert "static let macPage = EdgeInsets(top: 28, leading: 22, bottom: 22, trailing: 22)" in look
    for said in ("static let macGroup = EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12)",
                 "static let macLegendSide: CGFloat = 6", "static let macLegendHeight: CGFloat = 16",
                 "static let macLegendIn: CGFloat = 10", "static let macLegendUp: CGFloat = -8",
                 "static let macLabel: CGFloat = 124", "static let macGroupGap: CGFloat = 24"):
        assert said in look, said
    # a fact as the Mac's Settings draws one (MacSettingsFact): the label right-aligned at 124 in the second colour,
    # the value beside it on its baseline, 28 tall at least - lookHeight is exact on the Mac, so none on its rows
    fact = flat(bare(body(bare(source(DEBUG)), "struct HoldoutFact: View {")))
    mac, _ = phone_look.halves(fact, "if Platform.mac {")
    assert mac.startswith(" HStack(alignment: .firstTextBaseline, spacing: HoldoutLook.macGap) { Text(label) "
                          ".font(Typeface.Look.text(.fieldLabel)) .foregroundStyle(DWPalette.t2) .lineLimit(2) "
                          ".multilineTextAlignment(.trailing) .frame(width: HoldoutLook.macLabel, alignment: .trailing)"), mac
    assert ".frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))" in mac
    # no phone piece on the Mac's path of any of them (a ternary's phone half is the Mac's to skip)
    for name in (DEBUG, IMAGES, MOVE):
        path = settings_look.mac_path(bare(source(name)))
        for piece in ("PhoneGroup", "SettingsPage", "SettingsNote", "PhoneChevron", "DWWellField", "settingsSwitch",
                      "phoneSwitch", "PhoneKV", "PhoneGo", "PhoneCard", "lookHeight(PhoneLook", "lookHeight(DWLook.here.target"):
            assert piece not in path, f"{name}: {piece}"
    # and the shared files name no Mac-only piece (test_ios_mac_reach's zones): the Mac's sizes through Typeface.Look
    for name in (DEBUG, IMAGES, MOVE, RELEASE):
        code = bare(source(name))
        assert not re.search(r"\bMac(GroupBox|SettingsFact|SettingsRow|Look|Table|InFront)\b|Typeface\.Mac\b|"
                             r"DWCorners\.Mac\b", code), name


def test_debugs_measurements_are_in_courier_prime_and_its_words_are_not():
    debug = source(DEBUG)
    code = bare(debug)
    # a fact's value: the readout face unless it is words - PhoneKV's (.mono.s, the small 13) and MacSettingsFact's
    fact = flat(bare(body(code, "struct HoldoutFact: View {")))
    assert ("if words { Text(value) .font(HoldoutLook.words) } else { Text(value) .font(Platform.mac ? "
            "Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small)) }") in fact
    # the facts given as words are those that were in the words' face before: Up Next's edit, the last failure, the
    # EQ's rows, the recording, Following, Held back, Power - and the turntable's as each row says
    words = re.findall(r'HoldoutFact\(([^,]+),[^\n]*?words: true', kept(debug))
    assert words == ["UpNextWords.title", '"Last failure"', "row.label", "said.row.label", '"Following"'], words
    multiline = kept(debug)
    for label in ('"Held back"', '"Power"'):
        call = multiline[multiline.index(f"HoldoutFact({label}"):]
        call = call[:reader.closing(bare(call), call.index("(")) + 1]
        assert "words: true" in call, label
    assert "HoldoutFact(row.label, row.value, words: !row.mono, note: row.note)" in debug
    # the log's lines, each in the readout face; the clock of what plays and the background runs on lines of their own
    assert code.count(".font(Platform.mac ? Typeface.Look.mono(.chip) : Typeface.Phone.mono(.extraSmall))") == 2
    assert code.count(".font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))") == 4
    # a problem's own words in the readout face, selectable, as they were
    line = flat(bare(body(code, "struct HoldoutLine: View {")))
    assert ("if readout { Text(words) .font(Platform.mac ? Typeface.Look.mono(.smallButton) : "
            "Typeface.Phone.mono(.small)) .textSelection(.enabled) }") in line
    assert debug.count("readout: true)") == 2
    # every line it showed still there, in its order
    order = ["server", "testSounds", "hiRes", "playing", "TurntableDebugSection()", "EQDebugSection()",
             "EngineLogSection()", "DownloadsDebugSection()", "LibraryFollowDebugSection()", "libraryLists",
             "HoldoutLine(model.installLine)"]
    page = body(code, "var body: some View {")
    places = [page.index(part) for part in order]
    assert places == sorted(places), order
    for kept_line in (".navigationTitle(", ".task { if model.report == nil { await model.check() } }",
                      "eq.muffle = false", "deckTrial.stop()"):
        assert kept_line in flat(page), kept_line


def test_each_writer_keeps_its_confirmation():
    # Move albums (the eighth writer): one call to Move, the primary button under the preview it applies, on only as
    # canMove says - nothing moves from anywhere else
    move = bare(source(MOVE))
    assert move.count("model.move()") == 1
    root = body(move, "private struct ArtistMoveRoot: View {")
    tail = root[root.index("await model.move()"):]
    assert flat(tail).count(".buttonStyle(DWButtonStyle(kind: .pri, size: .small)) .disabled(!flow.canMove)") == 1
    assert root.index("plan(view)") < root.index("await model.move()"), "the preview over its Move"
    # Artist images' Save (the fifth writer's caller): one, the primary, on only as canSave says
    images = bare(source(IMAGES))
    assert images.count("await model.save()") == 1
    assert ".buttonStyle(DWButtonStyle(kind: .pri, size: .small)) .disabled(!flow.canSave)" in flat(images)
    # Replace cover only: the same condition as before, the primary at the page's width
    release = bare(source(RELEASE))
    compare = flat(body(release, "struct CompareCoversView: View {"))
    assert (".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true)) .disabled(incoming == nil || "
            "!retag.flow.canSaveCover || model.tagsApplying || model.getting || model.deleting)") in compare
    assert compare.count("model.saveCoverOnly()") == 1


def test_choose_a_release_only_chooses():
    choose = body(bare(source(RELEASE)), "struct ChooseReleaseView: View {")
    # a tap chooses and goes back, as it did: nothing applied, nothing written
    action = choose[choose.index("Button {") + len("Button {"):choose.index("} label: {")]
    assert flat(action) == " retag.pick(candidate) if path.last == .chooseRelease { path.removeLast() } ", action
    assert not re.search(r"\b(apply|applyTags|save\w*|write\w*|retag)\(", choose.replace("retag.pick(candidate)", "")), \
        "Choose a release's tap only chooses"
    # the chosen one marked by the accent's tick and said selected; off while a write runs or out of reach
    assert ".accessibilityAddTraits(chosen ? .isSelected : [])" in choose
    assert ".disabled(retag.flow.applying || !retag.flow.online)" in choose
    # iOS's search field kept (a field keeps its well), its Return a search
    assert ".searchable(text: $retag.typed, placement: .navigationBarDrawer(displayMode: .always)" in flat(choose)
    assert ".pullToRefresh {" in choose


def test_every_place_you_type_is_on_the_looks_well():
    debug = bare(source(DEBUG))
    field = flat(body(debug, "struct HoldoutField<Field: Hashable>: ViewModifier {"))
    mac, phone = phone_look.halves(field, "if Platform.mac {")
    # the phone's is DWWellField's own; the Mac's the plain field on DWWell, 24 tall, the accent's edge with the cursor
    assert phone == " content .modifier(DWWellField(focus: focus, field: field)) ", phone
    assert ".textFieldStyle(.plain)" in mac and "DWWell(focused: focus.wrappedValue == field)" in mac
    assert ".lookHeight(DWLook.here.fieldHeight)" in mac and ".font(Typeface.Look.text(.field))" in mac
    # (R20's review) a click on the well's room beside the words puts the cursor in it, as DWField's does
    assert (".background { DWWell(focused: focus.wrappedValue == field) .contentShape(DWTarget(face: "
            "DWCorners.buttonShape)) .onTapGesture { focus.wrappedValue = field } }") in mac
    # each field its own focus, which the well reads
    for name in (IMAGES, MOVE):
        code = flat(bare(source(name)))
        assert code.count(".focused($typing, equals: .search) .modifier(HoldoutField(focus: $typing, field: .search))") == 1
        assert code.count("TextField(") == 1, name


def test_buttons_rows_and_voiceover():
    debug = bare(source(DEBUG))
    # a button's words take three lines at the accessibility sizes; stacked buttons fill the width - (R20's review) on
    # the phone side by side only while they fit (ButtonPair's rule: Debug's recording pair is 368 at xLarge, on a 375
    # phone's 343), always stacked at the accessibility sizes, 12 apart so no 44 reaches over the next button's face;
    # the Mac's side by side
    assert ".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)" in body(debug, "struct HoldoutWords: View {")
    buttons = flat(body(debug, "struct HoldoutButtons<Content: View>: View {"))
    assert buttons == (
        "struct HoldoutButtons<Content: View>: View { @ViewBuilder let content: Content "
        "@Environment(\\.dynamicTypeSize) private var typeSize var body: some View { Group { if Platform.mac { side } "
        "else if typeSize.isAccessibilitySize { stack } else { ViewThatFits(in: .horizontal) { side stack } } } "
        ".frame(maxWidth: .infinity, alignment: .leading) .holdoutRow() } private var side: some View { "
        "HStack(spacing: Platform.mac ? HoldoutLook.macButtonGap : HoldoutLook.buttonGap) { content } "
        ".buttonStyle(DWButtonStyle(size: .small)) } private var stack: some View { VStack(alignment: .leading, "
        "spacing: HoldoutLook.buttonGap) { content } .buttonStyle(DWButtonStyle(size: .small, fills: true)) } }"), buttons
    assert "static let buttonGap: CGFloat = 12" in source(DEBUG)
    widths = _load("ios_fonts")
    small = 13.5 * 15 / 13  # .btn.sm at xLarge (the footnote's 13 to 15)
    pair = sum(widths.words(said, small, "medium") + 2 * 6 for said in ("Save the recording (1.2 MB)", "Record 20 s again"))
    assert pair + 12 > 375 - 2 * 16, "the case the fit is for"
    # every button R20 drew is the look's (flat on the phone, its target 44 by 44 - DWFlatButtonBody's) or a row
    for name in (DEBUG, IMAGES, MOVE):
        code = bare(source(name))
        styles = re.findall(r"\.buttonStyle\(([^\n]*?)\)\n", code)
        assert set(styles) <= {"DWButtonStyle(size: .small)", "DWButtonStyle()", ".plain",
                               "DWButtonStyle(kind: .danger, size: .small)", "DWButtonStyle(kind: .pri, size: .small)",
                               "DWButtonStyle(size: .small, fills: true)"}, (name, styles)
    # a fact, a control's row and the out-of-reach page are one element each - (R20's review) on each device: a fact
    # and a control's row end their Mac half and their phone half in it; a match row is its button
    for piece in ("struct HoldoutFact: View {", "struct HoldoutControlRow<Control: View>: View {"):
        mac, phone = phone_look.halves(flat(body(debug, piece)), "if Platform.mac {")
        for half in (mac, phone):
            assert half.endswith(" .accessibilityElement(children: .combine) "), (piece, half)
    assert ".accessibilityElement(children: .combine)" in body(debug, "struct HoldoutUnavailable: View {")
    match = flat(body(bare(source(IMAGES)), "struct ArtistMatchRow: View {"))
    assert ".buttonStyle(.plain) .accessibilityElement(children: .combine)" in match
    # the Mac's switch is the checkbox, the phone's Settings' own
    switch = flat(body(debug, "struct HoldoutSwitch: View {"))
    mac, phone = phone_look.halves(switch, "if Platform.mac {")
    assert "DWCheckbox(words: words, on: $on)" in mac and ".settingsSwitch()" in phone


#? R10's pieces of the Release file, as R10 drew them (sha-256 of each declaration's text, its first 16): R20 redrew
#? only the pages they push
R10_PIECES = {
    "struct ReleaseCards: View {": "a9e19eea5d3c4f63",
    "private struct ReleaseYearFace: ViewModifier {": "2013f7572b2c2cac",
    "struct ReleaseFoot: View {": "abd7fd67de36f384",
    "struct RetagPressingRow: View {": "4fb3234280c25323",
}


def test_r10s_pieces_are_as_r10_drew_them():
    text = source(RELEASE)
    code = bare(text)
    for start, digest in R10_PIECES.items():
        at = code.index(start)
        end = reader.closing(code, code.index("{", at)) + 1
        assert hashlib.sha256(text[at:end].encode("utf-8")).hexdigest()[:16] == digest, start


def test_docs_say_what_is_left():
    docs = DOCS.read_text(encoding="utf-8")
    left = docs[docs.index("**Not flat yet**"):]
    left = left[:left.index("\n\n")]
    assert "Correction's search and a filter's editor" in left
    said = left[:left.index("(")]
    for page in ("Debug", "Artist images", "Move albums", "Choose a release", "Compare covers"):
        assert page not in said, page
    assert "#### The known holdouts (645-648)" in docs
    for number in (645, 646, 647, 648):
        assert re.search(rf"^- \*\*{number} [^*]+\.\*\* \*\*Not done yet\.\*\*", docs, re.M), number
    assert "- **648 Both phones.** **Not done yet.**" in docs
