"""
Needs a look in the redesign's look (slice R12 - notes/ios.md "The redesign, slice R12: Needs a look"; the drawings
NeedsALook.dc.html and iNeedsALook.dc.html): on the Mac one page, the queue at its left and R10's and R11's editor at
its right (MacNeedsALook - the very MacAlbumEditor, never a second editor); on the phone the page flat - the large
title, Marked fine · N, the facets as a strip with their counts, a card per album - and queue mode's bar above Edit
album's foot.

The app's Swift read as text, as the other look tests read it:

- Stepping (‹, Skip ›, Apply moving on, a row picked, a facet chosen, It's fine) never loses typed work without
  "Discard changes?" first - on the Mac's page and in the phone's sheet - each part pinned.
- The strip's count and the badge count the same albums: All's is NeedsLook.summaryTotal's on both devices (Core's
  NeedsLookPageTests holds the rule itself).
- It's fine marks this album's issues alone; Apply moves on only once a release was applied and an album follows.
- The phone is flat (R1c): nothing here draws a face; no field is drawn (the typing rule has nothing new to hold).
- Tokens only in what this slice drew; "Queue", never "Up Next".

Core's NeedsLook (the web's rules, from care-vectors.json) is NeedsLookTests'; what the redesign adds beside it,
NeedsLookPage, is NeedsLookPageTests'.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_needs_look_look_{name}",
                                                  Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")


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


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def core(name: str) -> str:
    return (CORE / name).read_text(encoding="utf-8")


SCREEN = "Manage/NeedsLookScreen.swift"
MODEL = "Manage/NeedsLookModel.swift"
MAC = "Mac/Manage/MacNeedsALook.swift"
SHEET = "Edit/EditAlbumSheet.swift"
RELEASE = "Edit/ReleasePage.swift"
WINDOW = "Mac/Edit/MacEditWindow.swift"
EDITOR = "Mac/Edit/MacAlbumEditor.swift"
HEADER = "Mac/Edit/MacEditHeader.swift"
FOOTER = "Mac/Edit/MacEditFooter.swift"
TAB = "Mac/Edit/MacReleaseTab.swift"
ROUTES = "Shared/Routes.swift"
EDIT_MODEL = "Edit/EditAlbumModel.swift"
MANAGE = "Mac/Manage/MacManage.swift"
SLICE_FILES = [SCREEN, MODEL, MAC, SHEET, RELEASE, WINDOW, EDITOR, HEADER, FOOTER, TAB]


# ----------------------------------------------------------------------------- the phone: flat

def test_the_phones_page_is_flat_and_drawn_as_iNeedsALook():
    assert {SCREEN} == phone_look.R12_PAGES and phone_look.R12_PAGES <= phone_look.SLICES
    screen = bare(source(SCREEN))
    # no grouped list, no grey row, none of the old palette or type: the large title, as drawn
    for grey in ("List {", "Section {", "listRowBackground(", ".insetGrouped", "Typeface.footnote", "Typeface.body",
                 "Typeface.subheadline", ".navigationBarTitleDisplayMode(.inline)", "Menu {"):
        assert grey not in screen, grey
    assert not re.search(r"(?<!DW)Palette\.", screen)
    # nothing on the phone's path draws a face, an edge or a rule of its own: PhoneCard's hairline is the card's
    assert phone_look.drawn(phone_look.phone_path(screen)) == []
    planted = bare("NeedsLookCard(row: row, chips: chips).background(DWPalette.panel)")
    assert phone_look.drawn(phone_look.phone_path(planted)) == ["background: DWPalette.panel"]
    page = flat(screen)
    # the page's one scroll: the notes, the ladder, the strip, the status line, the cards, what takes one off
    assert "ScrollView { LazyVStack(alignment: .leading, spacing: 0) { notes(page)" in page
    lazy = flat(body(screen, "@ViewBuilder private func list("))
    for before, after in (("strip status", "card(row,"), ("card(row,", "Text(NeedsLookPage.leaves)")):
        assert lazy.index(before) < lazy.index(after), (before, after)
    # a ZStack, not a Group: the page's shows and hides on one view as the branches swap (R13's rule)
    assert "ZStack { if !page.allowed {" in page and "Group { if !page.allowed" not in page
    # Marked fine · N at the top's right: its count the facet's, on while it shows, All again when pressed then
    fine = flat(body(screen, "private func markedFine("))
    assert "model.choose(facet: NeedsLookPage.markedFineTapped(model.pressed))" in fine
    assert "Text(NeedsLookPage.markedFineWords(fine.count)) .fontWeight(on ? .semibold : .regular)" in fine
    assert ".accessibilityAddTraits(on ? .isSelected : [])" in fine
    assert ("if page.allowed, model.state == .list, let fine = NeedsLookPage.markedFine(model.chips) { "
            "ToolbarItem(placement: .topBarTrailing) { markedFine(fine) } }") in page


def test_the_phones_card_is_drawn_as_iNeedsALook():
    screen = bare(source(SCREEN))
    card = flat(body(screen, "struct NeedsLookCard: View {"))
    # a PhoneCard: the cover at 48, the album, its artist and edition, the folder in the readout face, the chevron
    assert card.index("PhoneCard {") < card.index("FolderCover(") < card.index("PhoneChevron()")
    assert ".frame(width: NeedsLookLook.cover, height: NeedsLookLook.cover) .clipShape(Corners.artShape)" in card
    assert "Text(album.path) .font(Typeface.Phone.mono(.extraSmall)) .foregroundStyle(DWPalette.t3) .lineLimit(1)" in card
    assert card.count(".lineLimit(lines)") == 2 and "let lines = typeSize.isAccessibilitySize ? nil : 1" in card
    # its chips under them, wrapping - each its tone's flat chip; at the accessibility sizes each a line of its words
    assert "NeedsLookChipRows(spacing: NeedsLookLook.chipGap) {" in card
    assert "DWChip(words: chip.words, tone: chip.kind.tone)" in card
    assert ("Text(chip.words) .font(Typeface.Look.text(.chip).weight(.medium)) .foregroundStyle(chip.kind.colour) "
            ".fixedSize(horizontal: false, vertical: true)") in card
    assert card.index("if typeSize.isAccessibilitySize {") < card.index("Text(chip.words)") < card.index(
        "NeedsLookChipRows(")
    # faded once a session has said what became of it
    assert ".opacity(row.mark == nil ? 1 : DWPalette.off)" in card
    # the sizes as drawn: 48, 12, 10, 5
    sizes = flat(body(screen, "enum NeedsLookLook {"))
    for size in ("cover: CGFloat = 48", "coverGap: CGFloat = 12", "cardGap: CGFloat = 10", "chipGap: CGFloat = 5"):
        assert size in sizes, size
    # a card is one element to VoiceOver: its album, byline, chips - and Open on the one open
    tap = flat(body(screen, "private func card("))
    assert ("NeedsLookCard(row: row, chips: chips) .accessibilityElement(children: .ignore) "
            ".accessibilityLabel(NeedsLookWords.row(row, chips: chips.map(\\.words), current: current)) "
            ".accessibilityAddTraits(.isButton)") in tap
    assert ".disabled(!reachability.online || model.ending != nil)" in tap


def test_a_chips_tone_is_dwchips_own_colour():
    # the accessibility sizes draw a chip as its words, in the colour DWChip gives that tone's words - read from both
    screen = bare(source(SCREEN))
    tones = dict(re.findall(r"case (\.[\w, .]+): return (\.\w+)", flat(body(screen, "var tone: DWChip.Tone {"))))
    colours = dict(re.findall(r"case (\.[\w, .]+): return (DWPalette\.\w+)", flat(body(screen, "var colour: Color {"))))
    chip = bare(source("Look/DWChip.swift"))
    text = dict(re.findall(r"case (\.\w+): return (DWPalette\.\w+)", flat(body(chip, "private var text"))))
    assert len(text) == 5, text
    assert tones == {".issue": ".caution", ".new": ".marked", ".fixed": ".good", ".markedFine, .deleted": ".plain"}
    for kind, tone in tones.items():
        assert colours[kind] == text[tone], (kind, tone)


def test_the_strip_and_the_badge_count_the_same_albums():
    # the strip: every facet drawn but Marked fine (its button's), each "All 3" - All's count summaryTotal's
    screen = flat(bare(source(SCREEN)))
    assert "let chips = NeedsLookPage.strip(model.chips) return PhoneStrip(options: chips.map(\\.id)" in screen
    assert "NeedsLook.chip(chips, pressed: id).map(NeedsLookWords.facet)" in screen
    assert "shown: Binding(get: { model.pressed }, set: { (id: String?) -> Void in model.choose(facet: id) })" in screen
    model = flat(bare(source(MODEL)))
    assert "var liveChips: [NeedsLook.Facet] { NeedsLook.facets(scan.albums, issueTypes) }" in model
    # All's count and summaryTotal: the albums the queue lists, one rule (MetadataQueue.queueAlbums with no facet)
    core = kept((CORE / "NeedsLook.swift").read_text(encoding="utf-8"))
    facets = flat(body(core, "public static func facets("))
    assert facets.count("let waiting = MetadataQueue.queueAlbums(albums, nil)") == 1
    assert 'return [Facet(id: nil, label: "All", count: waiting.count)]' in facets
    assert ("public static func summaryTotal(_ albums: [ScanAlbum]) -> Int { MetadataQueue.queueAlbums(albums, nil).count }"
            in flat(core))
    page = flat(bare((CORE / "NeedsLookPage.swift").read_text(encoding="utf-8")))
    # the Mac's status bar: the same count, from the scan as it is
    assert "[EditAlbumPage.Words.needALook(NeedsLook.summaryTotal(albums))]" in page
    mac = flat(bare(source(MAC)))
    assert "MacStatusItems.Items(leading: NeedsLookPage.status(model.scan.albums), trailing: trailing)" in mac
    # Settings' row and the Mac's sidebar: the one count model, asked from the server's summary of the same rule
    assert "public static func needingALook(_ albums: [ScanAlbum]) -> Int { NeedsLook.summaryTotal(albums) }" in flat(
        bare((CORE / "EditAlbumPage.swift").read_text(encoding="utf-8")))


# ----------------------------------------------------------------------------- the phone's sheet: the bar over the foot

def test_the_sheets_queue_bar_is_above_the_foot():
    sheet = bare(source(SHEET))
    whole = flat(sheet)
    # the system's bottom toolbar gone with the grey: the bar is drawn in the foot's own layer
    assert "bottomBar" not in sheet and "queueBar(" not in sheet
    assert ("let queue = request.queue?.nav.map { (nav: NeedsLook.Nav) -> EditQueueBar in EditQueueBar(nav: nav, "
            "model: model) { (delta: Int) -> Void in take(delta, model: model) } } "
            "EditAlbumRoot(model: model, path: $path, queue: queue)") in whole
    bar = flat(body(sheet, "struct EditQueueBar: View {"))
    # ‹, "2 of 9" in the readout face, Skip › - flat accent words, each step's gate read here
    assert bar.count(".buttonStyle(DWButtonStyle())") == 2 and "kind:" not in bar
    assert ".accessibilityLabel(NeedsLookWords.previous) .disabled(!nav.back || !model.canStep)" in bar
    assert ".disabled(!nav.on || !model.canStep)" in bar
    assert "Text(nav.place) .font(Typeface.Phone.mono(.small)) .foregroundStyle(DWPalette.t2)" in bar
    assert ".lookHeight(DWLook.here.target)" in bar
    assert ("if let bar { VStack(spacing: 0) { bar HStack(spacing: CGFloat(PhoneLook.footGap)) { actions() } "
            ".lookHeight(PhoneLook.foot) } } else { actions() }") in bar
    root = flat(body(sheet, "struct EditAlbumRoot: View {"))
    # over each tab's foot; the foot alone where a tab has none, and with no album drawn (deleted, being found)
    assert ("page.phoneFoot { EditQueueBar.above(queue) { ReleaseFoot(model: model, retag: retag, queue: queue) } }"
            in root)
    assert "page.phoneFoot { EditQueueBar.above(queue) { TagsFoot(model: model, tags: tags, path: $path) } }" in root
    assert "page.phoneFoot { EditQueueBar.above(queue) { DeleteButton(model: model, album: album)" in root
    assert "case .artwork, .lyrics: barred(page)" in root
    assert root.count("barred(") == 5
    assert "if let queue { page.phoneFoot { queue } } else { page }" in root
    # the sheet's drawn nothing with a face for it
    assert phone_look.drawn(phone_look.phone_path(body(sheet, "struct EditQueueBar: View {"))) == []


def test_stepping_in_the_sheet_never_loses_typed_work():
    sheet = bare(source(SHEET))
    take = flat(body(sheet, "private func take(_ delta: Int, model: EditAlbumModel) {"))
    assert ("guard let queue = request.queue, model.canStep else { return } if model.holdsWork { pendingStep = delta "
            "askingDiscard = true return } queue.go(by: delta, gate: model.stepGate)") in take
    # ‹ and Skip › and Release's Next album are each this `take` - the bar's closure
    bar = flat(body(sheet, "struct EditQueueBar: View {"))
    assert bar.count("take(-1)") == 1 and bar.count("take(1)") == 1
    foot = flat(body(bare(source(RELEASE)), "struct ReleaseFoot: View {"))
    assert ("if let queue, NeedsLookPage.movesOn(queue.nav, applied: retag.applied != nil) { Button { queue.take(1) }"
            in foot)
    assert ".accessibilityLabel(NeedsLookWords.nextAlbumSpoken) .disabled(!model.canStep) } else {" in foot
    # Discard's step: through the gate as it is then
    assert "if let model { request.queue?.go(by: delta, gate: model.stepGate) }" in flat(sheet)


# ----------------------------------------------------------------------------- the Mac: one page, one editor

def test_the_macs_page_hosts_the_one_editor_beside_the_queue():
    assert "case .needsALook: MacNeedsALook()" in flat(bare(source(MANAGE)))
    assert "NeedsLookScreen()" not in bare(source(MANAGE))
    mac = bare(source(MAC))
    page = flat(body(mac, "struct MacNeedsALook: View {"))
    # the shared editor, with queue mode's bar in its slot - never its parts drawn here
    assert ("MacAlbumEditor(model: editor, layout: layout, queue: queue) { if let queue { MacEditQueueBar(queue: queue, "
            "model: editor) } }") in page
    for part in ("MacEditHeader(", "MacFolderTabs(", "MacReleaseTab(", "MacEditFooter(", "appSheet("):
        assert part not in mac, part
    assert "MacEditNote(words: NeedsLookPage.pickAnAlbum)" in page
    # its opening: the queue's own, edited on this page alone - the model made as the sheet makes it
    assert (".task(id: Opening(id: navigation.macEdit(on: .needsALook)?.id, step: model.steps, "
            "online: reachability.online)) { await open(navigation.macEdit(on: .needsALook)) }") in page
    opened = flat(body(mac, "private func open(_ request: AlbumEditRequest?) async {"))
    assert "guard let request, request.queue === model else { editor = nil opened = nil return }" in opened
    assert ("EditAlbumModel(request: request, target: model.folder.map { .folder($0) }, scan: model.scan, "
            "client: server.client, admin: server.access.seesDetail, online: reachability.online)") in opened
    assert "made.attach(navigation, library: library)" in opened and "await editor?.reopen()" in opened
    # the phone's page's life (reads, the count, reach, the scene, the sign-in) worn by both pages
    assert ".modifier(NeedsLookLife(model: model))" in page
    assert ".modifier(NeedsLookLife(model: model))" in flat(bare(source(SCREEN)))
    # the editor's work holds the page as Edit an album's does
    assert ".modifier(MacEditHolding(model: editor))" in page
    # ⌘R once; the status bar; the 200 ms rest before a pick opens
    assert mac.count(".pullToRefresh {") == 1 and "await model.pulled()" in page
    assert "private static let rest: UInt64 = 200_000_000" in mac
    assert (".task(id: selected) { guard let key = selected, key != current else { return } "
            "try? await Task.sleep(nanoseconds: Self.rest) guard !Task.isCancelled else { return } pick(key) }") in page


def test_the_macs_list_is_drawn_as_NeedsALook():
    mac = bare(source(MAC))
    listing = flat(body(mac, "private struct MacNeedsLookList: View {"))
    # Album, Artist (at a page of 1000), Issues - each row one element to VoiceOver, the whole of it on the pointer
    assert "artistColumn ? [.album, .artist, .issues] : [.album, .issues]" in listing
    assert "width: .fixed(MacNeedsLookLook.artistWidth)" in listing and "width: .fixed(MacNeedsLookLook.issuesWidth)" in listing
    assert ("MacRowVoice(label: NeedsLookWords.row(row, chips: chipWords(row), current: row.key == open), "
            "actions: [])") in listing
    assert ".help(NeedsLookPage.help(row, chips: chips.map(\\.words)))" in listing
    # the title and every chip; else the first and how many more; else the title alone
    assert ("ViewThatFits(in: .horizontal) { titled(title, chips, shown: chips.count) titled(title, chips, shown: 1) "
            "Text(title) }") in listing
    # the cover at View > Row Size's, never a height of the list's own
    assert ".frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))" in listing
    assert not re.search(r"\.frame\(height: \d", listing)
    # the bar: Show, the pop-up and Marked fine - folded as the column narrows, four ways
    tools = flat(body(mac, "private var tools: some View {"))
    assert tools.count("HStack(spacing: MacNeedsLookLook.toolGap) {") == 4
    assert tools.count("popUp(folded: false, words: shownWords)") == 2
    assert "popUp(folded: true, words: shownWords)" in tools and "popUp(folded: true, words: NeedsLook.show)" in tools
    assert tools.count("if let fine { markedFine(fine) }") == 2
    pop = flat(body(mac, "private func popUp(folded: Bool, words: String) -> some View {"))
    assert "let chips = folded ? model.chips : NeedsLookPage.strip(model.chips)" in pop
    assert "set: { (picked: String?) -> Void in choose(picked) }" in pop
    fine = flat(body(mac, "private func markedFine(_ fine: NeedsLook.Facet) -> some View {"))
    assert "choose(NeedsLookPage.markedFineTapped(model.pressed))" in fine
    assert ".buttonStyle(DWButtonStyle(kind: on ? .on : .normal))" in fine
    # rows off while a session's are held after it, out of reach, and while a write runs
    assert ".disabled(model.ending != nil || !reachability.online || writing)" in listing
    assert ".editOutOfReach(!reachability.online && model.scan.loaded)" in listing


def test_stepping_on_the_mac_never_loses_typed_work():
    mac = bare(source(MAC))
    page = flat(body(mac, "struct MacNeedsALook: View {"))
    # ‹, Skip ›, the foot's Next album: the bar's and the foot's step is this page's `take`
    assert ("MacEditQueue(nav: nav) { (delta: Int) -> Void in take(delta, editor: editor) }") in page
    take = flat(body(mac, "private func take(_ delta: Int, editor: EditAlbumModel) {"))
    assert ("guard model.session != nil, editor.canStep else { selected = current return } if editor.holdsWork { "
            "pending = .step(delta) askingDiscard = true return } model.go(by: delta, gate: editor.stepGate)") in take
    # a row picked in a session: a step to it, through `take`; refused, the album open stays selected
    pick = flat(body(mac, "private func pick(_ key: String) {"))
    assert "let delta = model.step(to: row) guard delta != 0, let editor else { selected = current return }" in pick
    assert pick.endswith("take(delta, editor: editor) }")
    assert pick.index("guard model.session != nil else { model.open(row)") < pick.index("model.step(to: row)")
    # a facet chosen in a session ends it: asked first over typed work, refused mid-apply and while a step couldn't go
    choose = flat(body(mac, "private func choose(facet id: String?) {"))
    assert ("guard editor.canStep, !editor.applying, editor.following == 0 else { return } if editor.holdsWork { "
            "pending = .facet(id) askingDiscard = true return } model.choose(facet: id)") in choose
    # an opening from elsewhere: asked here only when the editor is on this page
    ask = flat(body(mac, "private func askAboutOpening() {"))
    assert ask.index("guard navigation.macEditHost == .needsALook else { return }") < ask.index("holdsWork")
    assert ("guard navigation.macEditAsked != nil, editor?.applying != true, (editor?.following ?? 0) == 0, "
            "!askingDiscard else { return }") in ask
    # Discard: the gate as it is then; Keep editing: the album open selected again
    discarded = flat(body(mac, "private func discarded() {"))
    assert "case .step(let delta): if let editor { model.go(by: delta, gate: editor.stepGate) } selected = current" in discarded
    assert "case .facet(let id): model.choose(facet: id)" in discarded
    assert "case .opening: navigation.macEditAnswered(discard: true)" in discarded
    kept_editing = flat(body(mac, "private func keptEditing() {"))
    assert "case .step: selected = current" in kept_editing
    assert "case .opening: navigation.macEditAnswered(discard: false)" in kept_editing
    assert ("Button(EditWords.discard, role: .destructive) { discarded() } "
            "Button(EditWords.keepEditing, role: .cancel) { keptEditing() } .returnCancels()") in page
    # the page's body reads no typed work: holdsWork only in the actions and MacEditHolding
    body_only = flat(body(mac, "    var body: some View {"))
    for word in ("holdsWork", "unsaved", ".fields"):
        assert word not in body_only, word
    # the three actions that weigh it: a step, a facet chosen, an opening asked for (MacEditHolding's is MacEditWindow's)
    assert mac.count("holdsWork") == 3


def test_apply_moves_on_and_its_fine_marks_this_album_alone_on_the_mac():
    footer = flat(bare(source(FOOTER)))
    # queue mode: It's fine as it is at the foot's left on every tab (each of the foot's three ways); Apply moving on
    # under Release
    assert "var body: some View { Group { if queue != nil { queued } else {" in footer
    assert flat(body(bare(source(FOOTER)), "private var queued: some View {")).count("fine") == 3
    assert ("if let queue, NeedsLookPage.movesOn(queue.nav, applied: retag.applied != nil) { Button { queue.take(1) }"
            in footer)
    assert ".accessibilityLabel(NeedsLookWords.nextAlbumSpoken) .disabled(!model.canStep) } else {" in footer
    assert "if part == .release, queue?.nav.on == true { return NeedsLookPage.movesOnLine }" in footer
    fine = flat(body(bare(source(FOOTER)), "@ViewBuilder private var fine: some View {"))
    assert "if NeedsLookPage.offersFine(server.access.permissions), !MetadataQueue.outstanding(album).isEmpty {" in fine
    assert "Task { await model.markFine() }" in fine
    assert ".disabled(!model.online || model.marking || model.writing)" in fine
    # the Release tab's own It's fine hidden in queue mode - one button, not two
    assert "if !outstanding.isEmpty && model.queue == nil {" in flat(bare(source(TAB)))
    # It's fine marks exactly this album's outstanding issues, by its folder - never another's
    mark = flat(body(bare(source(EDIT_MODEL)), "func markFine() async {"))
    assert "client.markFine(path: album.path, issues: MetadataQueue.outstanding(album))" in mark
    # Core: Apply moves on only once applied, and never from the last album
    page = flat(bare((CORE / "NeedsLookPage.swift").read_text(encoding="utf-8")))
    assert "guard let nav else { return false } return applied && nav.on" in page
    # the editor takes queue mode from its host and hands it to the foot; the bar under the header's chip
    editor = flat(bare(source(EDITOR)))
    assert "MacEditFooter(model: model, album: album, part: showing, queue: queue)" in editor
    assert "MacEditHeader(model: model, album: album, beside: layout.headerBeside) { bar } waits" in editor


def test_the_mac_edit_is_drawn_on_one_page_its_host():
    routes = bare(source(ROUTES))
    whole = flat(routes)
    assert "queue && front == .needsALook ? .needsALook : .chooseFolder" in whole
    assert "func macEdit(on host: AppRoute) -> AlbumEditRequest? { macEditHost == host ? macEdit : nil }" in whole
    page = flat(body(routes, "private func macEditPage(_ request: AlbumEditRequest) {"))
    assert "let host = Self.macEditHost(queue: request.queue != nil, front: you.last)" in page
    assert ("if host == .needsALook { stack.removeAll { (route: AppRoute) -> Bool in route == .chooseFolder } } "
            "else if stack.last != .chooseFolder {") in page
    assert page.index("macEditHost = host") < page.index("macEdit = request")
    # what R10 does for its page is the host's: the work kept, the page brought back, the page gone
    assert "stack.lastIndex(of: macEditHost)" in flat(body(routes, "private func kept(_ stack: [AppRoute]) -> Int {"))
    assert "private func backToEditPage() { backTo(macEditHost) }" in whole
    assert "!(library + search + requests + you).contains(macEditHost)" in flat(body(routes, "private func editPageGone() {"))
    move = flat(body(routes, "func macMove(_ move: MacSidebar.Move) {"))
    assert ("case .manage(.queue, _) where macEditHost == .needsALook && macEdit != nil && you.contains(.needsALook): "
            "tab = .you backTo(.needsALook)") in move
    assert "macEditHost = .chooseFolder" in flat(body(routes, "func reset() {"))
    # each page draws only its own opening; Edit an album asks about an opening only when it is the host
    window = flat(bare(source(WINDOW)))
    assert "await open(navigation.macEdit(on: .chooseFolder))" in window
    ask = flat(body(bare(source(WINDOW)), "private func askAboutOpening() {"))
    assert ask.index("guard navigation.macEditHost == .chooseFolder else { return }") < ask.index("holdsWork")
    # a page drawing no editor says nothing of work, so it never says "no work" over the host's
    holding = flat(body(bare(source(WINDOW)), "struct MacEditHolding: ViewModifier {"))
    assert "guard model != nil else { return } navigation.macEditHolding(now)" in holding
    # (R10's note) the queue's end said where the Run decides it: the Mac's opening ended as the phone's sheet closes
    close = flat(body(bare(source(MODEL)), "private func closeEditor() {"))
    assert "if navigation.albumEdit?.queue === self { navigation.albumEdit = nil }" in close
    assert "if navigation.macEdit?.queue === self { navigation.macEditEnded() }" in close


def test_what_this_slice_drew_is_tokens_and_its_words():
    for name in (SCREEN, MAC):
        text = source(name)
        code = bare(text)
        assert "Up Next" not in text, name
        assert not re.search(r"(?<!\w)Palette\.", code), name
        assert not re.search(r"\bColor\.(?!clear\b)\w+|Color\(", code), name
        assert ".font(.system" not in code and ".font(.title" not in code and ".monospacedDigit()" not in code, name
    # no field drawn: the typing rule has nothing new of this slice's
    for name in (SCREEN, MAC):
        assert "TextField(" not in source(name) and "DWField(" not in source(name), name
    for name in (SHEET, RELEASE, FOOTER, WINDOW):
        assert "Up Next" not in kept(source(name)), name


# ----------------------------------------------------------------------------- after review (R12's, 26 Nov)

def _said(name: str, key: str) -> str:
    """A word of Core's, as the app says it: `static let key = "..."` in `name`, its \\u{...} escapes read."""
    found = re.search(rf'static let {key} = "((?:[^"\\]|\\.)*)"', core(name))
    assert found, (name, key)
    return re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda escape: chr(int(escape.group(1), 16)), found.group(1))


def test_a_refresh_never_strands_the_editor():
    # (finding 1) ⌘R is held as Try again and a sign-in again are - never while a read is out, nor while a session
    # lasts - by Core's rule (NeedsLookPageTests and ScanReadsTests drive it), the model's pull asking it with the facts
    pulled = flat(body(bare(source(MODEL)), "func pulled() async {"))
    assert pulled == ("func pulled() async { guard NeedsLookPage.pullReads(online: online, samePerson: samePerson, "
                      "allowed: page.allowed, session: session != nil, reading: scan.reading) else { return } "
                      "count?.pulled() await read() }")
    page = flat(bare(core("NeedsLookPage.swift")))
    assert ("public static func pullReads(online: Bool, samePerson: Bool, allowed: Bool, session: Bool, reading: Bool) "
            "-> Bool { online && samePerson && allowed && !session && !reading }") in page
    # Try again and a sign-in again, held as they were
    assert "func retry() { guard !scan.reading else { return }" in flat(bare(source(MODEL)))
    assert "func signedInAgain() async { guard shown, online, session == nil else { return }" in flat(bare(source(MODEL)))
    # the editor's look-up carries its read of the shared scan to an answer: one a newer read took over waits for it
    look = flat(body(bare(source(EDIT_MODEL)), "func lookUp() async {"))
    assert "group.addTask { await self.scan.readShared(client: self.client, admin: self.admin) }" in look
    assert "scan.read(" not in look
    scan = bare(source("Edit/LibraryScanModel.swift"))
    shared = flat(body(scan, "func readShared(client: DeadwaxClient?, admin: Bool) async -> Read {"))
    assert ("return await reads.answer(cancelled: { Task.isCancelled }) { (ticket: Int) -> Read in "
            "await self.fetch(client, admin: admin, ticket: ticket) }") in shared
    # every read and rescan takes its ticket from the one ScanReads, and tells it how the newest ended
    assert "reads += 1" not in scan and flat(scan).count("reads.begin()") == 2
    assert "private let reads = ScanReads()" in scan and "typealias Read = ScanRead" in scan
    fetch = flat(body(scan, "private func fetch(_ client: DeadwaxClient, admin: Bool, ticket: Int) async -> Read {"))
    for end in ("return reads.ended(ticket, .landed)", "return reads.ended(ticket, .dropped)",
                "return reads.ended(ticket, .failed)"):
        assert end in fetch, end
    assert fetch.count("guard reads.isNewest(ticket) else { return .dropped }") == 2
    rescan = flat(body(scan, "func rescan(client: DeadwaxClient?, admin: Bool) async -> CareRuns.Rescanned {"))
    assert rescan.count("reads.ended(ticket, ") == 3 and rescan.count("guard reads.isNewest(ticket)") == 2
    # Core's: a dropped read waits for the newest's end, and asks again once when that came to nothing
    reads = flat(bare(core("ScanReads.swift")))
    assert ("let own = await read(ticket) guard own == .dropped, !cancelled() else { return own } "
            "if let newer = await end(after: ticket), newer != .dropped || cancelled() { return newer } "
            "tries += 1 guard tries < Self.tries else { return .dropped }") in reads
    assert "guard newest > ticket else { return nil } guard out else { return last }" in reads
    assert "public static let tries = 2" in reads


def test_its_fine_needs_edit_albums_on_the_mac_as_on_the_phone():
    # (finding 2) the Mac's foot offers It's fine exactly as the phone does: Edit albums (the Release tab's section)
    # and Look after the library (marksFine, its route's) - Core's rule, every permission set driven by
    # NeedsLookPageTests.itsFineNeedsEditAlbumsToo
    fine = flat(body(bare(source(FOOTER)), "@ViewBuilder private var fine: some View {"))
    assert fine.startswith("@ViewBuilder private var fine: some View { if NeedsLookPage.offersFine("
                           "server.access.permissions), !MetadataQueue.outstanding(album).isEmpty {")
    assert "AlbumEdit.marksFine(" not in bare(source(FOOTER))
    assert ("public static func offersFine(_ permissions: Set<Access.Permission>) -> Bool { "
            "Managing.albumEdit(permissions).editors && AlbumEdit.marksFine(permissions) }") in flat(
        bare(core("NeedsLookPage.swift")))
    # the phone's gate, as it was: the section on the Release tab (Edit albums'), the button in it with marksFine
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    assert "if edit.editors { needsALook(album) }" in root
    section = flat(body(bare(source(SHEET)), "@ViewBuilder private func needsALook(_ album: ScanAlbum) -> some View {"))
    assert "let marks = AlbumEdit.marksFine(server.access.permissions)" in section
    assert "if marks, !outstanding.isEmpty { Button { Task { await model.markFine() } }" in section
    # Managing's editors is Edit albums alone
    assert ("let edit = permissions.contains(.edit), library = permissions.contains(.library) return AlbumEdit(shown: "
            "edit || library, editors: edit, delete: library)") in flat(bare(core("Managing.swift")))


def test_a_refused_mark_is_said_on_every_tab_in_queue_mode():
    # (finding 3) in queue mode the foot says a refused mark, over its buttons - the foot is on every tab, and is the
    # only foot a person without Edit albums has (Delete's); the Release tab's own says it only outside queue mode
    queued = flat(body(bare(source(FOOTER)), "private var queued: some View {"))
    assert queued.startswith("private var queued: some View { VStack(alignment: .leading, spacing: MacEditFootLook.gap) "
                             "{ if let failure = model.markFailure { Text(failure) .font(Typeface.Mac.text(.small)) "
                             ".foregroundStyle(DWPalette.redChipText) .fixedSize(horizontal: false, vertical: true) "
                             ".frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading) } ViewThatFits(")
    editor = flat(bare(source(EDITOR)))
    assert ("if showing != .release || edit.editors { MacEditFooter(model: model, album: album, part: showing, "
            "queue: queue) }") in editor
    tab = flat(bare(source(TAB)))
    assert "if model.queue == nil, let failure = model.markFailure { ErrorNote(text: failure) }" in tab
    assert tab.count("model.markFailure") == 1


def test_every_count_the_window_shows_reads_the_live_scan():
    # (finding 4) the strip's, the pop-up's and Marked fine's counts are the scan's as it is now - the status bar's
    # and the sidebar's - which facets still the session's (Core's NeedsLookPage.counted, driven by NeedsLookPageTests)
    model = flat(bare(source(MODEL)))
    assert ("var chips: [NeedsLook.Facet] { NeedsLookPage.counted(NeedsLook.chips(session: session, held: run.held, "
            "ending: ending, live: liveChips), live: liveChips, pressed: pressed) }") in model
    assert "var pressedChip: NeedsLook.Facet? { NeedsLook.chip(chips, pressed: pressed) }" in model
    assert model.count("run.held") == 1
    counted = flat(body(bare(core("NeedsLookPage.swift")), "public static func counted("))
    assert "count: NeedsLook.chip(live, pressed: chip.id)?.count ?? 0," in counted
    # both pages draw their counts from `chips` alone - the status bar from the scan
    for name in (SCREEN, MAC):
        code = bare(source(name))
        assert "run.held" not in code and "NeedsLook.chips(" not in code and "liveChips" not in code, name
    assert "NeedsLookPage.markedFine(model.chips)" in bare(source(SCREEN))
    assert "NeedsLookPage.markedFine(model.chips)" in bare(source(MAC))


def _mac_button(words: str, weight: str = "medium") -> float:
    """A Mac button (DWButtonBody): its words at .btn's 12.5, 11 either side."""
    return fonts.words(words, 12.5, weight) + 2 * 11


def _mac_primary(words: str) -> float:
    """Apply, Next album and Apply to N tracks: semibold, the label 72 wide at least, 11 either side."""
    return max(72, fonts.words(words, 12.5, "semibold")) + 2 * 11


def test_the_queue_foot_fits_every_editor():
    # (finding 5) queue mode's foot, the first of three ways that fits: the line whole beside It's fine and the
    # actions; the line over the two; the line, It's fine and the actions each a line of their own
    footer = bare(source(FOOTER))
    queued = flat(body(footer, "private var queued: some View {"))
    assert ("ViewThatFits(in: .horizontal) { HStack(spacing: 8) { fine line .fixedSize() Spacer(minLength: 8) actions } "
            "VStack(alignment: .leading, spacing: MacEditFootLook.gap) { wrapped HStack(spacing: 8) { fine "
            "Spacer(minLength: 8) actions } } VStack(alignment: .leading, spacing: MacEditFootLook.gap) { wrapped fine "
            "HStack(spacing: 8) { Spacer(minLength: 0) actions } } }") in queued
    assert queued.endswith(".padding(.vertical, MacEditFootLook.side) .frame(minHeight: 48) }")
    # the line never cut - whole on one line in the first way, wrapping in the others, measured as nothing wide so the
    # way chosen is the one whose buttons fit - and whole on the pointer and to VoiceOver (a Text says itself whole)
    assert flat(body(footer, "private var line: some View {")) == (
        "private var line: some View { Text(note) .font(Typeface.Mac.text(.small)) .foregroundStyle(DWPalette.t3) "
        ".help(note) }")
    assert flat(body(footer, "private var wrapped: some View {")) == (
        "private var wrapped: some View { line .fixedSize(horizontal: false, vertical: true) "
        ".frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading) }")
    # one line of buttons is the foot's 48: 11 over and under a 26-tall button
    look = flat(body(footer, "enum MacEditFootLook {"))
    assert "static let side: CGFloat = 11" in look and "static let gap: CGFloat = 6" in look
    assert "buttonHeight: Double = 26" in core("MacLook.swift")
    # the sizes measured at: the foot's sides (16), its gaps (8) and spacer (8), a button's type (12.5, medium; the
    # purple and the red semibold) and room (11), Apply's least (72), the line's 12
    whole = flat(footer)
    assert ".padding(.horizontal, 16)" in whole
    assert "Button { Task { await model.apply() } } label: { Text(RetagWords.apply) .frame(minWidth: 72) }" in whole
    assert "Text(NeedsLookWords.nextAlbum) .frame(minWidth: 72)" in whole
    assert "buttonPadding: 11," in core("DWLook.swift")
    typeface = source("Shared/Typeface.swift")
    for size in ("case control = 12.5", "case .button: return .control", "case small = 12"):
        assert size in typeface, size
    # the editor at the Mac's widths (EditAlbumPage.Layout): 661 at the window's opening, 379 at its smallest and 378
    # with the side panel open at 1280 - the narrowest
    sidebar, panel = 220, 400
    assert f"public static let sidebarWidth: Double = {sidebar}" in core("MacLook.swift")
    assert f"public static let panelWidth: Double = {panel}" in core("MacLook.swift")
    layout = flat(bare(core("EditAlbumPage.swift")))
    assert ("public static let narrowList: Double = 280 public static let wideList: Double = 1000" in layout
            and "public static let folderListWidth: Double = 398" in core("MacLook.swift"))

    def editor(page: float) -> float:
        return page - (398 if page >= 1000 else 280) - 1

    opening, smallest, narrowest = editor(1280 - sidebar), editor(880 - sidebar), editor(1280 - sidebar - panel - 1)
    assert (opening, smallest, narrowest) == (661, 379, 378)
    side, gap, least, spinner = 16, 8, 8, 16
    # every word the foot can say, read from Core - none falling back to another face
    fine = max(_mac_button(_said("RetagFlow.swift", "fine")), _mac_button(_said("RetagFlow.swift", "markingFine")))
    revert = _mac_button(_said("EditAlbumPage.swift", "revert"))
    apply = _mac_primary(_said("RetagFlow.swift", "apply"))
    following = _mac_primary(_said("NeedsLook.swift", "nextAlbum"))
    many = "Apply to all 1,234 tracks"
    assert re.search(r'"Apply to all \\\(AlbumInfo\.grouped\(total\)\) track', core("EditAlbumPage.swift"))
    saving = max(72, spinner + gap + fonts.words(_said("TagEdit.swift", "saving"), 12.5, "semibold")) + 2 * 11
    remove = max(_mac_button(_said("DeleteAlbum.swift", "confirm"), "semibold"),
                 spinner + gap + _mac_button(_said("DeleteAlbum.swift", "deleting"), "semibold"))
    for words in (_said("RetagFlow.swift", "fine"), _said("RetagFlow.swift", "markingFine"),
                  _said("NeedsLook.swift", "nextAlbum"), many, _said("DeleteAlbum.swift", "deleting")):
        assert not fonts.lacks(words, "LibreFranklin-Medium"), words
    actions = {"release": [revert, max(apply, following)], "tags": [revert, max(_mac_primary(many), saving)],
               "delete": [remove], "artwork": [], "lyrics": []}
    for tab, buttons in actions.items():
        # the last way, every tab's widest words: It's fine a line of its own, the actions one of theirs
        assert 2 * side + fine <= narrowest, tab
        row = 2 * side + sum(buttons) + gap * len(buttons)
        assert row <= narrowest, (tab, row)
    # Release at the narrowest: its line over It's fine and Revert and Next album - beside them it would be cut (the
    # review's "about 45")
    line = fonts.words(_said("NeedsLookPage.swift", "movesOnLine"), 12)
    release = revert + following + gap
    one_line = 2 * side + fine + gap + line + gap + least + gap + release
    two_lines = 2 * side + fine + gap + least + gap + release
    assert two_lines <= narrowest < one_line, (two_lines, one_line)
    # ...and at the window's opening the whole on one line, as drawn
    assert one_line <= opening, one_line
    # Tags' "Apply to all 10 tracks" beside It's fine (the review's 385 with the line between them): the second way
    # holds it at the narrowest, the line over them
    ten = 2 * side + _mac_button(_said("RetagFlow.swift", "fine")) + gap + least + gap + revert + gap + _mac_primary(
        "Apply to all 10 tracks")
    assert ten <= narrowest, ten


def test_each_struct_keeps_its_own_doc():
    # (finding 6) the phone's queue bar's doc on EditQueueBar, ReadAgainFailed's on ReadAgainFailed - none over 120
    sheet = source(SHEET).splitlines()

    def doc(decl: str) -> list[str]:
        at = sheet.index(decl)
        lines = []
        while sheet[at - 1 - len(lines)].startswith("///"):
            lines.insert(0, sheet[at - 1 - len(lines)])
        return lines

    bar = doc("struct EditQueueBar: View {")
    again = doc("struct ReadAgainFailed: View {")
    assert bar[0].startswith("/// (R12 - notes/ios.md") and "Queue mode's bar on the phone" in bar[0]
    assert not any("couldn't be read again" in line or "artist tools" in line for line in bar)
    assert again[0].startswith("/// The library couldn't be read again while an album is held")
    assert any("(Phase 8, slice 5) The artist tools' too" in line for line in again)
    assert not any("Queue mode" in line for line in again)
    assert all(len(line) <= 120 for line in bar + again), max(bar + again, key=len)


def test_the_queues_end_is_said_where_the_run_decides_it():
    # (finding 7) R10's handler of the session going, on Edit an album's page, is gone: the end is NeedsLookModel's
    # closeEditor's on either page (a step to an album gone, a facet chosen - the Run's `close`), and every other way
    # a session ends lets the Mac's opening go before it tells the page (macEditEnded, a new opening, a sign-out)
    window = flat(bare(source(WINDOW)))
    assert "nav == nil" not in window and ".onChange(of: navigation.macEdit?.queue" not in window
    close = flat(body(bare(source(MODEL)), "private func closeEditor() {"))
    assert "if navigation.macEdit?.queue === self { navigation.macEditEnded() }" in close
    carry = flat(body(bare(source(MODEL)), "private func carry(_ after: NeedsLook.After) {"))
    assert "if after.close { closeEditor() }" in carry
    ended = flat(body(bare(source(ROUTES)), "func macEditEnded() {"))
    assert ended.index("macEdit = nil") < ended.index("shown.queue?.editorClosed()")


def test_the_macs_page_keeps_its_selection_on_the_session():
    mac = bare(source(MAC))
    page = flat(body(mac, "struct MacNeedsALook: View {"))
    # (M2) the session over - Close, a facet chosen, a step to an album gone: nothing selected
    assert (".onChange(of: model.session == nil) { (_: Bool, over: Bool) -> Void in if over { selected = nil } }"
            in page)
    # (M3) an open refused - rows held after a session, out of reach: nothing left selected
    pick = flat(body(mac, "private func pick(_ key: String) {"))
    assert "guard model.session != nil else { model.open(row) if model.session == nil { selected = nil } return }" in pick
    assert ("guard let row = model.rows.first(where: { (row: NeedsLook.DrawnRow) -> Bool in row.key == key }) else { "
            "selected = current return }") in pick
    # (M4) the selection follows a step: the album open selected as it moves, and again after the step itself
    assert (".onChange(of: current, initial: true) { (_: String?, now: String?) -> Void in if let now { "
            "selected = now } }") in page
    assert "private var current: String? { model.session?.current?.listed.path }" in page
    take = flat(body(mac, "private func take(_ delta: Int, editor: EditAlbumModel) {"))
    assert take.endswith("model.go(by: delta, gate: editor.stepGate) selected = current }")
    # (M10) the rows off while a write runs: the page hands the list the editor's write, the list's rows take it
    assert ("MacNeedsLookList(model: model, selected: $selected, artistColumn: layout.artistColumn, "
            "writing: editor?.writing == true, choose: choose(facet:))") in page
    listing = flat(body(mac, "private struct MacNeedsLookList: View {"))
    assert "let writing: Bool" in listing
    assert ".frame(maxHeight: .infinity) .disabled(model.ending != nil || !reachability.online || writing)" in listing


def test_the_macs_queue_bar_waits_for_the_step_gate():
    # (M1) the Mac's ‹ and Skip › dimmed by the editor's gate, as the phone's are
    bar = flat(body(bare(source(WINDOW)), "struct MacEditQueueBar: View {"))
    assert ("Button(NeedsLookPage.back) { queue.take(-1) } .buttonStyle(DWButtonStyle(size: .small)) "
            ".accessibilityLabel(NeedsLookWords.previous) .help(NeedsLookWords.previous) "
            ".disabled(!nav.back || !model.canStep)") in bar
    assert ("Button(nav.forward) { queue.take(1) } .buttonStyle(DWButtonStyle(size: .small)) "
            ".accessibilityLabel(nav.forwardSpoken) .accessibilityHint(nav.nextAlbum ? \"\" : NeedsLookWords.skipHint) "
            ".help(nav.nextAlbum ? nav.forwardSpoken : NeedsLookWords.skipHint) "
            ".disabled(!nav.on || !model.canStep) }") in bar
    # the gate itself: Core's StepGate over the editor's writes, reads and waits
    gate = flat(body(bare(source(EDIT_MODEL)), "var stepGate: NeedsLook.StepGate {"))
    assert ("NeedsLook.StepGate(online: online, busy: writing || marking || following > 0, reading: scan.reading, "
            "needsRead: retag?.flow.needsRead == true || tags?.flow.needsRead == true, "
            "deletePending: unansweredDelete != nil)") in gate
    assert "var canStep: Bool { stepGate.open }" in flat(bare(source(EDIT_MODEL)))
