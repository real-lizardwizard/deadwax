"""
Edit album in the redesign's look (slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list and
Release"; the drawings Main.dc.html and iEdit.dc.html): on the Mac one page, Settings' Edit an album - the library's
folders at its left, the album's editor at its right (its header, five folder tabs, Release's tab, the foot's Revert and
Apply); on the phone the sheet's root redrawn flat - the header, the strip of five, Release's cards and the foot.

The app's Swift read as text, as the other look tests read it:

- Apply is the sheet's own on both devices (EditAlbumModel.apply): the preview's body sent - the folder, the release
  chosen, the fields and the cover's switch - and the server works the plan out again (CLAUDE.md's "every apply route
  recomputes the plan rather than taking one back over the wire"). No file of this slice asks deadwax to write.
- The Mac's page is never left mid-apply, nor with typed work: no Back, the window kept open, the page kept under
  anything opened over it, a folder picked or an opening asked for waiting for the apply's end and then asking
  "Discard changes?" first.
- A tab changed never touches typed work: the tab is the page's own state, the model made only for an opening; Revert
  is the only way Release's typed work is put back, and only by its button.
- The phone's foot is PhoneFoot (`.phoneFoot`): over the page's foot, under the keyboard, never riding up on a field.
- The phone is flat (R1c): only what iEdit gives a face or a line; the fields on the look's well (R1c's typing rule,
  held by test_ios_phone_look's TEXT_INPUTS).
- Tokens only in what this slice drew; "Queue", never "Up Next".

Core's EditAlbumPage (the folder list, the chip, the strip and the tabs, Revert's gate, the Mac's widths) is tested in
Swift (EditAlbumPageTests).

(R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork, Lyrics and Delete") Every part a tab on both devices now:
the phone's strip shows each under it (no part pushed), the Mac's editor draws each tab's own view, and the foot is the
tab's. Its rules are test_ios_edit_parts_look's; what this file held of R10's parts-still-pages is held there instead.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_edit_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
mac_look = _load("test_ios_mac_look")
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


SHEET = "Edit/EditAlbumSheet.swift"
RELEASE = "Edit/ReleasePage.swift"
MODEL = "Edit/EditAlbumModel.swift"
WINDOW = "Mac/Edit/MacEditWindow.swift"
EDITOR = "Mac/Edit/MacAlbumEditor.swift"
LIST = "Mac/Edit/MacFolderList.swift"
HEADER = "Mac/Edit/MacEditHeader.swift"
TAB = "Mac/Edit/MacReleaseTab.swift"
FOOTER = "Mac/Edit/MacEditFooter.swift"
ROUTES = "Shared/Routes.swift"
PHONE_FILES = (SHEET, RELEASE)
MAC_FILES = (WINDOW, EDITOR, LIST, HEADER, TAB, FOOTER)

#? what this slice drew of the phone's files (the rest - the queue bar, R12's; Choose a release, the changes, Compare
#? covers and the full cover, the pages pushed from the cards - as they were)
DRAWN_PARTS = {
    SHEET: ("struct EditAlbumRoot: View {", "private struct MatchedChip: ToolbarContent {"),
    RELEASE: ("struct ReleaseCards: View {", "struct ReleaseFoot: View {"),
}


def drawn_parts(name: str) -> list[str]:
    code = bare(source(name))
    return [body(code, start) for start in DRAWN_PARTS[name]]


# ----------------------------------------------------------------------------- Apply is the sheet's own

APPLY = "Button { Task { await model.apply() } } label: {"


def test_apply_is_the_sheets_own_and_sends_no_plan():
    # each device's Apply: the sheet's own call, in the tap, nothing before it
    foot = flat(body(bare(source(RELEASE)), "struct ReleaseFoot: View {"))
    mac = flat(bare(source(FOOTER)))
    for name, code in ((RELEASE, foot), (FOOTER, mac)):
        assert code.count(APPLY) == 1, name
        assert code.count("model.apply()") == 1, name
    # no file of this slice asks deadwax to write, builds a write's body or hands a plan to anything
    for name in PHONE_FILES + MAC_FILES + (ROUTES,):
        code = bare(source(name))
        for word in ("beginApply", "RetagRequestBody", "applyEnded", "TagEditBody", "CoverFetchBody"):
            assert word not in code, (name, word)
        # EditClient's every write and preview: the models' alone (a button calls the model's own markFine, never a
        # client's)
        asked = re.search(r"\bclient\??\.(retagApply|retagPreview|fetchCover|markFine|askAgain|tagsApply|tagsPreview|"
                          r"getCover|getLyrics|getDiscArt|deleteAlbum)\(", code)
        assert not asked, (name, asked and asked.group(0))
        # a plan is only ever drawn (the preview, the changes' page): never handed to the model, a client or a route
        assert not re.search(r"\b(model|client|retag|navigation|server)\??(\.\w+)*\([^)]*\bplan\b", code), name
    # the model's apply: the body RetagModel makes (the folder, the release, the fields, the cover's switch - no plan),
    # posted; the preview kept only to say what came of it
    model = flat(body(bare(source(MODEL)), "func apply() async {"))
    assert "let body = retag.beginApply()" in model
    assert "try await client.retagApply(body)" in model
    retag = flat(bare(source("Edit/RetagModel.swift")))
    assert ("var body: RetagRequestBody { RetagRequestBody(albumPath: album.path, release: Retag.payload(selected: "
            "selected, album: album, fields: fields), fetchArt: fetchArt) }") in retag
    request = body(bare((CORE / "Retag.swift").read_text(encoding="utf-8")), "public struct RetagRequestBody:")
    assert re.findall(r"public let (\w+):", request) == ["albumPath", "release", "fetchArt"]
    # Apply is off while any other write runs, on both devices alike
    gate = ".disabled(!retag.canApply || model.tagsApplying || model.getting || model.deleting)"
    assert gate in foot and gate in mac
    # the Mac's search field's Return finds releases, never applies
    tab = flat(bare(source(TAB)))
    assert re.findall(r"\.onSubmit \{ ([^}]*?) ?\}", tab) == ["findReleases()"]
    find = body(tab, "private func findReleases() {")
    assert "apply()" not in find and "await retag.search()" in find


# ----------------------------------------------------------------------------- the Mac's page, never left mid-apply

def test_the_macs_page_is_never_left_mid_apply_nor_with_typed_work():
    window = flat(bare(source(WINDOW)))
    # an apply holds work (writing is applying or a cover saving), so everything below holds through it
    model = flat(bare(source(MODEL)))
    assert "var holdsWork: Bool { retag?.unsaved == true || tags?.unsaved == true || writing || marking }" in model
    assert "var writing: Bool { applying || retag?.flow.savingCover == true }" in model
    # no Back, the window kept open, and the stacks told - (R10's review) in a modifier of its own, the page's body
    # never reading holdsWork (test_a_keystroke_never_runs_the_pages_body)
    # (R12) Needs a look's page wears it too: a page drawing no editor says nothing, never "no work" over the other's
    holding = flat(body(window, "struct MacEditHolding: ViewModifier {"))
    assert ("let holds = model?.holdsWork == true content .keepsWindowOpen(holds) .navigationBarBackButtonHidden(holds) "
            ".onChange(of: holds, initial: true) { (_: Bool, now: Bool) -> Void in guard model != nil else { return } "
            "navigation.macEditHolding(now) }") in holding
    assert window.count(".modifier(MacEditHolding(model: model))") == 1
    # a folder picked: never while an apply runs, nor (R10's review) until the folder has been read again after it
    # (the list's selection put back), asked first over work
    pick = flat(body(window, "private func pick(_ path: String) {"))
    assert pick.index("guard !model.applying, model.following == 0 else { selected = model.album?.path return }") < (
        pick.index("if model.holdsWork { pending = .folder(path) askingDiscard = true }"))
    # an opening from elsewhere: asked about once an apply has ended and (R10's review) its follow-up read with it -
    # the apply's end comes first, when typed work still compares against the folder as it was - never over another
    # question; asked again as each of those ends
    ask = flat(body(window, "private func askAboutOpening() {"))
    assert ("guard navigation.macEditAsked != nil, model?.applying != true, (model?.following ?? 0) == 0, "
            "!askingDiscard else { return }") in ask
    assert "onChange(of: model?.applying == true) { (_: Bool, _: Bool) -> Void in askAboutOpening() }" in window
    assert "onChange(of: model?.following ?? 0) { (_: Int, _: Int) -> Void in askAboutOpening() }" in window
    # following: up for an apply until its read is done (the read is inside it)
    model = flat(body(bare(source(MODEL)), "func apply() async {"))
    assert model.index("following += 1 defer { following -= 1 }") < model.index("await lookUp()")
    # Discard is the destructive one, Keep editing Return's
    assert ("Button(EditWords.discard, role: .destructive) { discarded() } "
            "Button(EditWords.keepEditing, role: .cancel) { keptEditing() } .returnCancels()") in window
    routes = flat(bare(source(ROUTES)))
    # the page kept under anything opened over it while it holds work - a tab's button, a sidebar row
    kept_pages = flat(body(bare(source(ROUTES)), "private func kept(_ stack: [AppRoute]) -> Int {"))
    # (R12) the page the editor is on: Edit an album's, or Needs a look's beside its queue (AppNavigation.macEditHost)
    assert ("let editing = macEditHolds ? (stack.lastIndex(of: macEditHost).map { (at: Int) -> Int in at + 1 } ?? 0)"
            " : 0") in kept_pages
    assert "People.pagesKept(people, writing: writingPeople), editing)" in kept_pages
    # an opening asked for over work: the page brought to the front, nothing let go, the question asked there
    page = flat(body(bare(source(ROUTES)), "private func macEditPage(_ request: AlbumEditRequest) {"))
    holding = page[page.index("if macEditHolds, let shown = macEdit, shown.id != request.id {"):]
    holding = holding[:holding.index("return }") + len("return }")]
    assert "macEditAsked = request backToEditPage() tab = .you return }" in holding
    assert "macEdit = request" not in holding
    assert "private func backToEditPage() { backTo(macEditHost) }" in routes
    back = flat(body(bare(source(ROUTES)), "private func backTo(_ page: AppRoute) {"))
    assert "guard let at = you.lastIndex(of: page) else { return } let keep = max(at + 1, kept(you))" in back
    # only Discard lets the work go
    answered = flat(body(bare(source(ROUTES)), "func macEditAnswered(discard: Bool) {"))
    assert "if discard { macEditHolds = false macEditPage(asked) }" in answered
    # its declaration, Discard, the page's end and a sign-out - and the page's own word as its work changes
    assert routes.count("macEditHolds = false") == 4
    assert "func macEditHolding(_ holds: Bool) { macEditHolds = holds }" in routes


# ----------------------------------------------------------------------------- a tab change keeps typed work

def test_a_tab_changed_never_touches_typed_work():
    window = flat(bare(source(WINDOW)))
    editor = flat(bare(source(EDITOR)))
    # the tab: (R10's review) the editor's own state, above the model - the page's model and its opening the host's
    assert "@State private var tab: AlbumEdit.Part = .release" in editor and "var tab" not in window
    # the model made only for an opening - a new one, a step, deadwax back in reach - never for a tab, and never by the
    # editor its hosts share
    assert window.count("EditAlbumModel(") == 1 and "EditAlbumModel(" not in editor
    opening = flat(body(bare(source(WINDOW)), "private struct Opening: Equatable {"))
    assert re.findall(r"let (\w+):", opening) == ["id", "step", "online"]
    made = flat(body(bare(source(WINDOW)), "private func open(_ request: AlbumEditRequest?) async {"))
    assert "if model == nil || opened != request.id || step != wanted {" in made
    assert "EditAlbumModel(" in made and "tab" not in made
    # nothing follows the tab but the content shown
    for code in (window, editor):
        assert not re.search(r"onChange\(of: tab\b|task\(id: tab\b|onChange\(of: self\.tab\b", code)
    # (R11) Artwork's Go to Release only shows the tab - on the Mac, and on the phone
    assert "showRelease: { tab = .release })" in editor
    assert "partPath" not in editor and "sheet = .part(" not in editor
    # Release's typed work put back only by Revert's own button, and only when there is some to put back
    for name in PHONE_FILES + MAC_FILES + (ROUTES, MODEL):
        code = bare(source(name))
        calls = len(re.findall(r"\brevertRelease\(\)", code)) - len(re.findall(r"func revertRelease\(\)", code))
        assert calls == {RELEASE: 1, FOOTER: 1}.get(name, 0), (name, calls)
    # (R10's review) Revert is the model's own: `retag` set nowhere outside it
    revert = flat(body(bare(source(MODEL)), "func revertRelease() {"))
    assert revert.startswith("func revertRelease() { guard canRevertRelease, let album = album ?? retag?.album else")
    assert "RetagModel(album: album, online: online, admin: admin, client: client)" in revert
    for code in (flat(body(bare(source(RELEASE)), "struct ReleaseFoot: View {")), flat(bare(source(FOOTER)))):
        assert ".disabled(!model.canRevertRelease)" in code
    gate = flat(body(bare(source(MODEL)), "var canRevertRelease: Bool {"))
    assert ("EditAlbumPage.canRevert(unsaved: retag.unsaved, online: online, writing: writing, marking: marking, "
            "needsRead: retag.flow.needsRead)") in gate
    # the phone: (R11) the strip's tab the root's own state too - every part shown under the strip, none pushed, and
    # nothing following the tab but what is shown
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    assert "@State private var tab: AlbumEdit.Part = .release" in root
    assert "let shown = EditAlbumPage.shown(tab, in: strip.tabs)" in root
    assert "shown: Binding(get: { shown }, set: { (part: AlbumEdit.Part) -> Void in tab = part })" in root
    assert "ArtworkPage(model: model, album: album) { tab = .release }" in root
    assert "private func open(_ part" not in root
    assert not re.search(r"path\.append\(\.(release|tags|artwork|lyrics|delete)\)", root)
    assert not re.search(r"onChange\(of: tab\b|task\(id: tab\b", root)
    # (R10's review) the model's Release is its own again: its setter private, Revert one of its methods
    model = flat(bare(source(MODEL)))
    assert "private(set) var retag: RetagModel?" in model
    assert "extension EditAlbumModel" not in bare(source(RELEASE))
    for name in PHONE_FILES + MAC_FILES + (ROUTES,):
        assert not re.search(r"(?<!let )(?<!var )\bretag\s*=(?!=)", bare(source(name))), name


# ----------------------------------------------------------------------------- the phone's sheet and its foot

def test_the_phones_sheet_keeps_its_rules():
    sheet = flat(body(bare(source(SHEET)), "struct EditAlbumSheet: View {"))
    # Close, the dialog, no swipe away with work, the window kept, as they were
    assert "ToolbarItem(placement: .cancellationAction) {" in sheet
    assert ".interactiveDismissDisabled(model?.holdsWork == true)" in sheet
    assert ".keepsWindowOpen(model?.holdsWork == true)" in sheet
    # (R12) queue mode's bar handed to the root, drawn above its foot
    assert "EditAlbumRoot(model: model, path: $path, queue: queue)" in sheet
    # the Matched chip in the top, its glass off on iOS 26
    assert ".matchedChip(model?.album)" in sheet
    assert "toolbar { MatchedChip(album: album).sharedBackgroundVisibility(.hidden) }" in flat(bare(source(SHEET)))


def test_the_phones_foot_never_rides_up_on_a_field():
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    # (R11) the page R10 kept for Artwork's pointer gone: Release's foot the root's alone - and each tab's foot its own
    assert "struct ReleasePage" not in bare(source(RELEASE))
    for name, code in ((SHEET, root),):
        # (R12) each tab's foot with queue mode's bar over it, when there is one - and the bar alone as a page's foot
        assert code.count(".phoneFoot { EditQueueBar.above(queue) { ReleaseFoot(model: model, retag: retag, "
                          "queue: queue) } }") == 1, name
        assert code.count(".phoneFoot { EditQueueBar.above(queue) { TagsFoot(model: model, tags: tags, "
                          "path: $path) } }") == 1, name
        assert code.count(".phoneFoot { EditQueueBar.above(queue) { DeleteButton(model: model, album: album)") == 1, name
        assert code.count("page.phoneFoot { queue }") == 1, name
        assert code.count(".phoneFoot") == 4, name
        assert "safeAreaInset" not in code and ".toolbar(" not in code.replace(".toolbar {", ""), name
        assert ".scrollDismissesKeyboard(.interactively)" in code, name
    # PhoneFoot's layer takes the keyboard's room, so the foot stays at the screen's foot under the keyboard, and the
    # page's room for it goes while the keyboard is up
    placing = flat(bare(source("Phone/PhoneFoot.swift")))
    assert ".ignoresSafeArea(.keyboard, edges: .bottom)" in placing
    assert ".frame(height: keyboardUp ? 0 : height)" in placing
    # Revert and Apply its two, the purple the one that fills - (R12) Apply Next album in its place in queue mode once
    # a write was told of the album (NeedsLookPage.movesOn), the same purple
    foot = flat(body(bare(source(RELEASE)), "struct ReleaseFoot: View {"))
    assert foot.count(".buttonStyle(DWButtonStyle(") == 3
    assert ".buttonStyle(DWButtonStyle(size: .large))" in foot
    assert foot.count(".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))") == 2
    # the words take three lines at the accessibility sizes, never cut to one
    assert ".lineLimit(typeSize.isAccessibilitySize ? 3 : 1)" in foot


# ----------------------------------------------------------------------------- the phone is flat

FLAT = {
    # the page's black (the folder's choice, the album's page); the folder menu's line; the out-of-reach band as it was
    SHEET: ["background: DWPalette.page", "background: DWPalette.page", "DWRule: DWPalette.groupRule", "fill: .bar",
            "fill: Palette.amberFill"],
    # the Fields card's rows' line (one row of Release's own for every field since R10's review) - (R11) the page's
    # black went with ReleasePage, the root's own; then the pages pushed from the cards, still iOS's (docs/ios.md's
    # "Not flat yet") - (R10's review: the wider matcher sees them) Choose a release's Current badge and its chosen
    # row's fill, the full cover's empty square and Compare covers', and the full cover on black, a photo's ground -
    # (R20) flat now: R10's Current badge as it was (RetagPressingRow stays R10's); Choose a release, Changes and
    # Compare covers each on the page's black, a cover that isn't there (and one still coming) its square's hairline,
    # the two lists' rows on a row's hairline, the chosen pressing marked by the accent's tick, no fill; the full cover
    # on the page's black, a photo's ground
    RELEASE: ["DWRule: DWPalette.groupRule", "background: Palette.badgeFill",
              "background: DWPalette.page", "background: DWPalette.page", "strokeBorder: DWPalette.line",
              "background: DWPalette.page", "strokeBorder: DWPalette.line", "DWRule: DWPalette.rowRule",
              "ZStack: DWPalette.page"],
}


def test_the_phone_is_flat_in_edit_album():
    found = {name: phone_look.drawn(phone_look.phone_path(bare(source(name)))) for name in PHONE_FILES}
    assert found == FLAT, {name: draws for name, draws in found.items() if draws != FLAT[name]}
    # what this slice drew: PhoneGroup's legends and PhoneCard's lines alone, the fields on the look's well
    cards = flat(body(bare(source(RELEASE)), "struct ReleaseCards: View {"))
    for legend in ("EditWords.release", "EditWords.fields", "EditWords.cover", "EditWords.whatApplyDoes"):
        assert f"PhoneGroup(legend: {legend})" in cards, legend
    assert cards.count("TextField(") == 1 and ".modifier(DWWellField(focus: $focused, field: name))" in cards
    assert ".toggleStyle(.phoneSwitch)" in cards
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    assert "PhoneStrip(options: strip.tabs," in root and "spoken: EditAlbumPage.Words.parts)" in root
    assert "pushes:" not in root
    assert "let strip = EditAlbumPage.strip(editors: edit.editors, delete: edit.delete)" in root
    # no List, no Form: the sheet's root is the page's own scroll
    for code in (root, cards):
        assert not re.search(r"\b(List|Form|Section)\s*[({]", code)


# ----------------------------------------------------------------------------- tokens only

PHONE_FONT = re.compile(r"Typeface\.(?:Phone\.(?:text|mono)|symbol|Look\.(?:text|mono))\(")


def test_edit_album_draws_no_value_of_its_own():
    left = []
    parts = {name: "\n".join(drawn_parts(name)) for name in PHONE_FILES}
    parts.update({name: bare(source(name)) for name in MAC_FILES})
    for name, code in parts.items():
        for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b"),
                              ("a font of its own", r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\.monospaced")):
            if re.search(pattern, code):
                left.append(f"{name}: {what}")
        named = mac_look.NAMED_COLOUR.search(re.sub(r"\bcase \.\w+:", "", code))
        if named:
            left.append(f"{name}: a named colour ({named.group(0)})")
        # the old palette nowhere in what this slice drew
        old = re.search(r"(?<![\w.])Palette\.\w+", code)
        if old:
            left.append(f"{name}: the old palette ({old.group(0)})")
    assert not left, left
    # the phone's fonts: Typeface.Phone's, the look's, the symbols'
    for name in PHONE_FILES:
        fonts = mac_look.font_arguments(parts[name])
        assert fonts and not [f for f in fonts if not PHONE_FONT.match(f)], (name, fonts)
    # the Mac's: the Mac's faces (a ternary's both)
    for name in MAC_FILES:
        fonts = [f for font in mac_look.font_arguments(parts[name])
                 for f in (re.fullmatch(r"[^?()]+ \? (\S+) : (\S+)", font).groups()
                           if re.fullmatch(r"[^?()]+ \? (\S+) : (\S+)", font) else [font])]
        assert not [f for f in fonts if not mac_look.MAC_FONT.match(f)], (name, fonts)


def test_the_queue_is_the_queue():
    for name in PHONE_FILES + MAC_FILES + (ROUTES,):
        assert "Up Next" not in kept(source(name)), name


# ----------------------------------------------------------------------------- (R10's review) the findings, held

def test_the_macs_page_asks_again_when_it_comes_back_with_nothing_read():
    # finding 1: a tab switched or a page pushed over the page cancels its task, the first read comes back `.dropped`
    # and nothing lands - the page come back asks again, never left finding the folder for good
    made = flat(body(bare(source(WINDOW)), "private func open(_ request: AlbumEditRequest?) async {"))
    assert "await model?.reopen()" in made and "model?.open()" not in made
    model = flat(bare(source(MODEL)))
    assert ("func reopen() async { guard opened else { await open() return } guard !answered, online else { return } "
            "await lookUp() }") in model
    # the opening's first read came back only when it landed or failed - a read cut off is neither
    look = flat(body(bare(source(MODEL)), "func lookUp() async {"))
    assert "case .landed: answered = true" in look and "case .failed: answered = true" in look
    assert "case .dropped: break" in look and model.count("answered = true") == 2
    # open() as it was: once, the phone's sheet calling it alone - its task goes with the sheet, and the model with it
    assert "func open() async { guard !opened else { return } opened = true guard online else { return } await lookUp() }" in model
    sheet = flat(body(bare(source(SHEET)), "struct EditAlbumSheet: View {"))
    assert "model?.open()" in sheet and "reopen" not in bare(source(SHEET))


def test_a_delete_on_the_mac_leaves_no_page_of_the_album_on_any_stack():
    # finding 2: on the Mac the tab shown is Settings, Edit an album on top - so the album's pages go from every stack,
    # as albumMoved follows them on every stack; the phone's rule (the tab shown's top) as it was
    leave = flat(body(bare(source(ROUTES)), "func leaveAlbum(_ id: String) {"))
    mac = leave[leave.index("if MacFrame.drawsDesktop(Platform.device) {"):leave.index("switch tab {")]
    assert ("stack.removeAll { (route: AppRoute) -> Bool in Self.isAlbum(route, id) }") in mac
    assert "gone(&library) gone(&search) gone(&requests) gone(&you) return }" in mac
    assert ("switch tab { case .library: left(&library) case .search: left(&search) case .requests: left(&requests) "
            "case .you: left(&you) }") in leave
    moved = flat(body(bare(source(ROUTES)), "func albumMoved(from: String, to: String) {"))
    assert "moved(&library) moved(&search) moved(&requests) moved(&you)" in moved
    album = flat(body(bare(source(ROUTES)), "private static func isAlbum(_ route: AppRoute, _ id: String) -> Bool {"))
    assert "if case .album(let shown) = route { return shown.id == id } return false" in album
    # the model asks it once nothing of the album is left in Navidrome
    assert "if all { navigation?.leaveAlbum(id) }" in flat(bare(source(MODEL)))


def test_needs_a_look_is_counted_as_the_queue_counts_it():
    # finding 3: the switch, the status bar and the row's mark through the queue's own function - never a count of
    # this page's (CLAUDE.md: "The tab badge and the queue never count different things")
    page = flat(bare((CORE / "EditAlbumPage.swift").read_text(encoding="utf-8")))
    assert "public static func waiting(_ album: ScanAlbum) -> Bool { !MetadataQueue.queueAlbums([album], nil).isEmpty }" in page
    assert "public static func needingALook(_ albums: [ScanAlbum]) -> Int { NeedsLook.summaryTotal(albums) }" in page
    assert "case .needsALook: return matching.filter(waiting)" in page
    assert "guard waiting(album) else { return nil }" in flat(body(page, "public static func mark(_ album: ScanAlbum)"))
    queue = flat(bare((CORE / "NeedsLook.swift").read_text(encoding="utf-8")))
    assert "public static func summaryTotal(_ albums: [ScanAlbum]) -> Int { MetadataQueue.queueAlbums(albums, nil).count }" in queue
    listing = flat(bare(source(LIST)))
    assert "EditAlbumPage.Words.needALook(EditAlbumPage.needingALook(scan.albums))" in listing
    assert "switch EditAlbumPage.mark(album) {" in listing and "MetadataQueue" not in listing
    assert "DWChip(words: NeedsLook.newWord, tone: .marked) .accessibilityLabel(EditAlbumPage.Words.newlyAdded)" in listing


def test_a_keystroke_never_runs_the_pages_body():
    # finding 4: holdsWork reads Release's fields - read in the page's body, a letter typed in Album would filter, sort
    # and diff the folder list's every row again. The page's body reads none of it; the list works its rows out itself
    window = bare(source(WINDOW))
    page = flat(body(window, "    var body: some View {"))
    for word in ("holdsWork", "unsaved", "fields", "retag", "EditAlbumPage.folders(", "needingALook", "macStatus"):
        assert word not in page, word
    # what reads holdsWork in the page's file: the modifier, and the three actions (a pick, an opening, a step)
    readers = [name for name in ("struct MacEditHolding: ViewModifier {", "private func pick(_ path: String) {",
                                 "private func askAboutOpening() {", "private func take(_ delta: Int,")
               if "holdsWork" in body(window, name)]
    assert len(readers) == 4 and window.count("holdsWork") == 4, readers
    # the queue's bar a view of its own: its step gate read there
    # (R12) its step the host's `take`, handed to the foot's Next album too (MacEditQueue)
    assert "MacEditQueue(nav: nav) { (delta: Int) -> Void in take(delta, model: model) }" in page
    assert "if let queue { MacEditQueueBar(queue: queue, model: model) }" in page
    assert ".disabled(!nav.back || !model.canStep)" in flat(body(window, "struct MacEditQueueBar: View {"))
    # the list: its rows and the status bar's counts from the scan, what was typed and the switch
    listing = flat(body(bare(source(LIST)), "    var body: some View {"))
    assert listing.strip().startswith("var body: some View { let rows = EditAlbumPage.folders(scan.albums, typed: typed, shown: shown)")
    assert "let rows:" not in bare(source(LIST))
    # the editor its hosts share reads no field either: the tab and the foot do, each its own view
    editor = flat(bare(source(EDITOR)))
    for word in ("holdsWork", "unsaved", ".fields"):
        assert word not in editor, word


def test_the_editor_is_one_view_its_hosts_share():
    # finding 5: the editor - header, waits, tabs, scroll, foot, part sheet - its own view, taking an EditAlbumModel,
    # its host's queue bar an optional slot: MacEditWindow hosts it, and R12's MacNeedsALook
    editor = flat(bare(source(EDITOR)))
    assert "struct MacAlbumEditor<Bar: View>: View { let model: EditAlbumModel let layout: EditAlbumPage.Layout let bar: Bar" in editor
    # (R12) and queue mode, for the foot: It's fine as it is and Apply moving on
    assert ("init(model: EditAlbumModel, layout: EditAlbumPage.Layout, queue: MacEditQueue? = nil, "
            "@ViewBuilder bar: () -> Bar) { self.model = model self.layout = layout self.queue = queue "
            "self.bar = bar() }") in editor
    assert ("extension MacAlbumEditor where Bar == EmptyView { init(model: EditAlbumModel, layout: EditAlbumPage.Layout) "
            "{ self.init(model: model, layout: layout) { EmptyView() } } }") in editor
    # (R12) the bar under the header's chip, as NeedsALook.dc.html draws it
    for part in ("MacEditHeader(model: model, album: album, beside: layout.headerBeside) { bar } waits", "MacFolderTabs(",
                 "MacReleaseTab(model: model, retag: retag, twoColumns: layout.twoColumns)", "MacEditFooter(model: model,",
                 ".appSheet(item: $sheet,", "@State private var sheet: MacEditSheet?", "@State private var sheetPath"):
        assert part in editor, part
    # the host owns the model and its opening; none of the editor's parts drawn there
    window = flat(bare(source(WINDOW)))
    assert "MacAlbumEditor(model: model, layout: layout, queue: queue) {" in window
    for part in ("MacEditHeader(", "MacFolderTabs(", "MacReleaseTab(", "MacEditFooter(", "appSheet(", "partCard("):
        assert part not in window, part
    # another opening (the host's next model): a part's sheet put away, the tab kept
    assert ("onChange(of: ObjectIdentifier(model)) { (_: ObjectIdentifier, _: ObjectIdentifier) -> Void in sheet = nil }"
            in editor)
    assert "onChange(of: model.deleted) { (_: Bool, gone: Bool) -> Void in if gone { sheet = nil } }" in editor


def test_the_macs_foot_is_the_persons_permissions():
    # finding 7: Release's Revert and Apply only with Edit albums, as the tab and the phone's foot are gated; (R11)
    # every other tab's foot its own - Delete's, with Look after the library alone
    editor = flat(bare(source(EDITOR)))
    assert "case .release: if editors, let retag = model.retag { MacReleaseTab(" in editor
    assert "tabContent(showing, album: album, editors: edit.editors)" in editor
    assert ("if showing != .release || edit.editors { MacEditFooter(model: model, album: album, part: showing, "
            "queue: queue) }") in editor
    assert editor.count("MacEditFooter(") == 1
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    assert ("if edit.editors, let retag = model.retag { page.phoneFoot { EditQueueBar.above(queue) { "
            "ReleaseFoot(model: model, retag: retag, queue: queue) } } }") in root


def test_the_macs_holding_rules_are_each_pinned():
    # finding 9: each of these passed every test before; each is held here
    window = flat(bare(source(WINDOW)))
    routes = bare(source(ROUTES))
    # the 200 ms rest before a pick opens (R2's): the arrow keys run past folders
    assert "private static let rest: UInt64 = 200_000_000" in window
    assert (".task(id: selected) { guard let path = selected, path != model?.album?.path else { return } "
            "try? await Task.sleep(nanoseconds: Self.rest) guard !Task.isCancelled else { return } pick(path) }") in window
    # the page gone only once Edit an album is on no stack
    gone = flat(body(routes, "private func editPageGone() {"))
    # (R12) the page the editor is on - Needs a look's, beside its queue, gone takes the queue's opening with it
    assert ("guard macEdit != nil || macEditAsked != nil, !(library + search + requests + you).contains(macEditHost) "
            "else { return }") in gone
    # every stack's move asks it: frontMoved first thing, and each stack's didSet calls frontMoved
    assert flat(body(routes, "private func frontMoved() {")).startswith("private func frontMoved() { editPageGone()")
    for stack in ("library", "search", "requests", "you"):
        assert f"var {stack}: [AppRoute] = [] {{ didSet {{ frontMoved() }} }}" in routes, stack
    # the sidebar's Edit an album goes back to the page while it is on the stack, before the Manage row's own move
    move = flat(body(routes, "func macMove(_ move: MacSidebar.Move) {"))
    edit = move.index("case .manage(.edit, _) where you.contains(.chooseFolder): tab = .you backTo(.chooseFolder)")
    assert edit < move.index("case .manage(let tool, let how):")
    # Discard on a folder pick lets the hold go before it opens the folder (else the page is kept and asks again)
    discarded = flat(body(window, "private func discarded() {"))
    assert ("case .folder(let path): navigation.macEditHolding(false) "
            "navigation.editAlbum(AlbumEditRequest(target: .folder(path)))") in discarded
    # Keep editing ends the asked opening's Needs a look session
    answered = flat(body(routes, "func macEditAnswered(discard: Bool) {"))
    assert "} else if asked.queue !== macEdit?.queue { asked.queue?.editorClosed() }" in answered
    # (R10's review) and an opening asked for, let go by an opening Discard opened meanwhile, ends its session too
    page = flat(body(routes, "private func macEditPage(_ request: AlbumEditRequest) {"))
    tail = page[page.rindex("you = stack"):]
    assert tail.index("if let asked = macEditAsked, asked.id != request.id, asked.queue !== request.queue "
                      "{ asked.queue?.editorClosed() }") < tail.index("macEditAsked = nil")
    # a delete outside queue mode ends the opening; in queue mode the editor stays, the list read again
    assert ("onChange(of: model?.deleted == true) { (_: Bool, gone: Bool) -> Void in guard gone else { return } "
            "if navigation.macEdit?.queue == nil { navigation.macEditEnded() } else { Task { await readList() } } }"
            ) in window
    # the queue's session over ends the opening - only an opening of the queue's. (R12's review) Where the Run decides
    # it, whichever page draws the editor (NeedsLookModel.closeEditor: a step to an album gone, a facet chosen) - R10's
    # handler of the session going, here, is gone
    assert "queue?.nav == nil" not in window
    close = flat(body(bare(source("Manage/NeedsLookModel.swift")), "private func closeEditor() {"))
    assert "if navigation.macEdit?.queue === self { navigation.macEditEnded() }" in close
    # a sign-out lets the opening go first - the next person's Edit an album never opens on the last one's folder -
    # and ends its sessions once the session has moved on
    reset = flat(body(routes, "func reset() {"))
    # (R12) and the editor's page back to Edit an album's, Needs a look's opening gone with the rest
    assert reset.startswith("func reset() { let asked = macEditAsked macEditAsked = nil macEdit = nil "
                            "macEditHolds = false macEditHost = .chooseFolder library.removeAll()")
    assert reset.index("session += 1") < reset.index("asked?.queue?.editorClosed()")
    # the list off while a write runs, so the folder can't change under it
    listing = flat(body(bare(source(LIST)), "    var body: some View {"))
    assert ".background(DWPalette.bg) .disabled(writing)" in listing
    assert "writing: model?.writing == true," in window


def test_the_macs_words_fit_and_say_themselves_whole():
    # the Find field's words fit its room in the narrow list (280, under a page of 1000): the toolbar's sides (12) and
    # gap (6), and the switch's - All and Needs a look at 12.5 semibold, 10 either side of each, its edge (1 a side)
    toolbar = flat(bare(source("Mac/Components/MacToolbar.swift")))
    assert "HStack(spacing: 6) {" in toolbar and ".padding(.horizontal, 12)" in toolbar
    assert "largeSegmentPadding: 10," in (CORE / "DWLook.swift").read_text(encoding="utf-8")
    page = (CORE / "EditAlbumPage.swift").read_text(encoding="utf-8")
    narrow = float(re.search(r"public static let narrowList: Double = (\d+)", page).group(1))
    switch = fonts.words("All", 12.5, "semibold") + fonts.words("Needs a look", 12.5, "semibold") + 4 * 10 + 2
    room = narrow - 2 * 12 - 6 - switch
    assert 110 <= room <= 118, room
    find = re.search(r'public static let findFolders = "([^"]+)"', page).group(1)
    assert fonts.words(find, 13) + 2 * 8 <= room, (find, room)
    # the words it replaced, which didn't fit, are still its name to VoiceOver and its help
    assert fonts.words("Folder, artist or album", 13) + 2 * 8 > room
    listing = flat(bare(source(LIST)))
    assert ("DWField(prompt: EditAlbumPage.Words.findFolders, text: $typed, spoken: EditWords.folderPrompt) "
            ".help(EditWords.folderPrompt)") in listing
    # a cell cut to its column says itself whole on the pointer
    assert ".foregroundStyle(DWPalette.t2) .lineLimit(1) .help(album.artist)" in listing
    assert ".foregroundStyle(DWPalette.t2) .lineLimit(1) .help(album.year)" in listing
    # the foot's applying words, one line, cut at the narrower editors: their whole words on the pointer
    footer = flat(bare(source(FOOTER)))
    assert ("let applying = RetagWords.applying(plan ?? retag.plan) ProgressView().controlSize(.small) Text(applying) "
            ".font(Typeface.Mac.text(.small)) .foregroundStyle(DWPalette.t2) .lineLimit(1) .help(applying)") in footer


def test_the_phones_header_and_fields_as_iedit_draws_them():
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    header = flat(body(root, "private func header(_ album: ScanAlbum) -> some View {"))
    # the byline and the path one line each (iEdit's `.ell`), their whole words to VoiceOver
    assert "Text(byline) .font(Typeface.Phone.text(.small)) .foregroundStyle(DWPalette.t2) .lineLimit(1) .accessibilityLabel(byline)" in header
    assert (".lineLimit(1) .truncationMode(.middle) .accessibilityLabel(album.path) .textSelection(.enabled)") in header
    cards = flat(body(bare(source(RELEASE)), "struct ReleaseCards: View {"))
    # the years in the readout face (`.in.mono`), at the field's 16
    field = flat(body(cards, "private func field(_ label: String,"))
    # - set inside the well's own face (an inner .font wins), the well still on the field's own chain
    assert field.endswith(".tabs($focused, in: Self.order) .modifier(ReleaseYearFace(digits: digits)) "
                          ".modifier(DWWellField(focus: $focused, field: name)) }")
    face = flat(body(bare(source(RELEASE)), "private struct ReleaseYearFace: ViewModifier {"))
    assert "if digits { content.font(Typeface.Look.mono(.field)) } else { content }" in face
    # every field's row stacks at the accessibility sizes, as the Year row does - Release's own rows, DWFieldRow (the
    # look's) keeping one line
    assert "DWFieldRow(" not in cards and cards.count("fieldRow(EditWords.") == 3
    row = flat(body(cards, "private func row<Content: View>("))
    assert ("typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) "
            ": AnyLayout(HStackLayout(spacing: 8))") in row
    assert ".frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))" in row
    for name in ("private func fieldRow(", "private func yearRow("):
        assert flat(body(cards, name)).count("row {") == 1, name
    # every change, a finger's 44 tall
    preview = flat(body(cards, "@ViewBuilder private func preview(_ plan: RetagPlan) -> some View {"))
    assert "PhoneChevron() } .frame(minHeight: CGFloat(DWLook.here.target)) .contentShape(Rectangle())" in preview
