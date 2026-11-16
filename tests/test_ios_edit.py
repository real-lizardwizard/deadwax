"""
The iPhone app's Edit album, as the App draws and opens it (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 1-3,
14; notes/ios.md "Edit album on the phone"). James: "nothing in the app should take you to the web app", "maybe some
dropdowns instead of big lists".

Read from the Swift source, as the other ios tests read theirs: an album page's ••• has Edit album (with the album's
Edit, deadwax in reach, the album not gone), between Album info and Refresh, and opens the sheet over the tabs
(AppNavigation.albumEdit, MainTabs' one `.sheet(item:)`); Settings > Manage > Edit an album pushes Choose the folder,
whose folder opens the same sheet; the sheet is its own NavigationStack, can't be swiped away with work in it, asks
before discarding, and Close is off while an apply runs; the apply holds a background task; the album page asks again
after a write and follows a new id; the choices are menu Pickers; nothing in Edit album opens a URL (the last row
in the web app, Delete album…, became a page of the phone's own in slice 4); the scan is asked without its tracks. Core's rules and words are held by EditVectorTests and
RetagModelTests, the routes by tests/test_ios_edit_contract.py.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
EDIT = APP / "Edit"
SHEET = EDIT / "EditAlbumSheet.swift"
MODEL = EDIT / "EditAlbumModel.swift"
RETAG = EDIT / "RetagModel.swift"
RELEASE = EDIT / "ReleasePage.swift"
FOLDERS = EDIT / "ChooseFolderView.swift"
SCAN = EDIT / "LibraryScanModel.swift"
MENU = APP / "Player" / "QueueMenu.swift"
ALBUM = APP / "Album" / "AlbumView.swift"
TABS = APP / "Root" / "MainTabs.swift"
ROUTES = APP / "Shared" / "Routes.swift"
MANAGE = APP / "You" / "ManageSection.swift"


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def block(text: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:index]
    raise AssertionError("unbalanced braces")


def declared(text: str, kind: str, name: str) -> str:
    found = list(re.finditer(r"\b" + kind + r"\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"{kind} {name} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def test_an_albums_menu_has_edit_album_with_the_albums_edit():
    menu = code(MENU)
    request = declared(menu, "struct", "QueueMenuRequest")
    assert "var editAlbum: (@MainActor () -> Void)?" in request
    # offered only while deadwax can be reached, and never for an album gone from the collection
    assert "let editAlbum = reachability.online && !request.gone ? request.editAlbum : nil" in menu
    info = menu.index("Button(AlbumInfoWords.title, systemImage: AlbumInfoWords.symbol)")
    edit = menu.index("Button(EditWords.menuItem, systemImage: EditWords.symbol)")
    refresh = menu.index("Button(LibrarySwitchWords.refresh")
    assert info < edit < refresh
    # it opens nothing in Safari any more
    assert "openURL" not in menu and "webEdit" not in menu
    album = code(ALBUM)
    menu_request = album[album.index("private var albumMenu: QueueMenuRequest?"):]
    menu_request = block(menu_request, menu_request.index("{"))
    assert "if Managing.albumEdit(server.access.permissions).shown {" in menu_request
    assert "navigation.editAlbum(AlbumEditRequest(target: .album(AlbumEdit.Subject(album))))" in menu_request


def test_the_sheet_is_opened_over_the_tabs_once():
    tabs = code(TABS)
    assert tabs.count(".sheet(item: $navigation.albumEdit, onDismiss: { navigation.editorDismissed() })") == 1
    assert "EditAlbumSheet(request: request)" in tabs
    routes = code(ROUTES)
    navigation = declared(routes, "class", "AppNavigation")
    assert "var albumEdit: AlbumEditRequest?" in navigation
    assert "albumEdit = request" in block(navigation, navigation.index("{", navigation.index("func editAlbum(")))
    # signing out or changing server forgets it
    reset = block(navigation, navigation.index("{", navigation.index("func reset(")))
    assert "albumEdit = nil" in reset and "albumWrites = [:]" in reset


def test_manage_pushes_choose_the_folder_which_opens_the_sheet():
    routes = code(ROUTES)
    route = block(routes, routes.index("{", routes.index("enum AppRoute")))
    assert re.search(r"\bcase chooseFolder\n", route)
    assert "case .chooseFolder: ChooseFolderScreen()" in routes
    assert "NavigationLink(value: AppRoute.chooseFolder)" in code(MANAGE)
    screen = declared(code(FOLDERS), "struct", "ChooseFolderScreen")
    assert "navigation.editAlbum(AlbumEditRequest(target: .folder(path)))" in screen
    # asked as it opens and on a pull, and not while deadwax can't be reached
    assert ".task(id: reachability.online)" in screen and "guard reachability.online else { return }" in screen
    assert ".refreshable {" in screen


def test_the_sheet_keeps_typed_work_and_a_running_apply():
    sheet = code(SHEET)
    view = declared(sheet, "struct", "EditAlbumSheet")
    assert "NavigationStack(path: $path)" in view
    assert ".navigationDestination(for: EditPage.self)" in view
    assert ".interactiveDismissDisabled(model?.holdsWork == true)" in view
    # Close in the cancellation place, off while an apply runs, asking first with work in hand
    assert "ToolbarItem(placement: .cancellationAction)" in view
    assert ".disabled(model?.applying == true)" in view
    assert ".confirmationDialog(EditWords.discardTitle, isPresented: $askingDiscard" in view
    # (Phase 8, slice 6) Discard closes the sheet - or, asked by a step through Needs a look's queue, takes the step
    # (slice 6's review: through the gate as it is then); closing ends the queue's session, then dismisses
    discard = view[view.index("Button(EditWords.discard, role: .destructive) {"):view.index("Button(EditWords.keepEditing")]
    assert "closeSheet()" in discard and "request.queue?.go(by: delta, gate: model.stepGate)" in discard
    assert "pendingStep = nil" in discard
    assert "dismiss()" in view[view.index("private func closeSheet()"):]
    assert "Button(EditWords.keepEditing, role: .cancel) { pendingStep = nil }" in view
    close = block(view, view.index("{", view.index("private func close()")))
    assert "guard let model, !model.applying else { return }" in close
    assert close.index("if model.holdsWork {") < close.index("askingDiscard = true")
    # out of reach and back, and back to the front after a lock
    assert ".onChange(of: reachability.online)" in view and "model?.reach(now)" in view
    assert ".onChange(of: scenePhase)" in view and "model?.becameActive()" in view


def test_an_apply_holds_a_background_task_and_says_an_answer_that_never_came():
    model = code(MODEL)
    assert "UIApplication.shared.beginBackgroundTask(withName:" in model
    assert "UIApplication.shared.endBackgroundTask(task)" in model
    apply = block(model, model.index("{", model.index("func apply()")))
    assert "BackgroundHold(" in apply
    # VoiceOver hears it, and the folder is read again
    assert "AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()" in model
    assert "await lookUp()" in apply
    # a new id followed and said
    assert "AccessibilityNotification.Announcement(EditWords.followed).post()" in model
    assert "navigation?.albumMoved(" in model or "navigation.albumMoved(" in model


def test_the_album_page_asks_again_after_a_write_and_follows_a_move():
    album = code(ALBUM)
    assert ".onChange(of: navigation.albumWrites[route.id]) { _, _ in refresh() }" in album
    routes = code(ROUTES)
    # a page for a new id is a new page (its model made again)
    assert "case .album(let album): AlbumView(route: album).id(album.id)" in routes
    navigation = declared(routes, "class", "AppNavigation")
    assert "albumWrites[id, default: 0] += 1" in block(navigation, navigation.index("{", navigation.index("func albumWritten(")))
    moved = block(navigation, navigation.index("{", navigation.index("func albumMoved(")))
    # every tab's stack, and a page opened by the old id from now on opens the new one
    for stack in ("library", "search", "requests", "you"):
        assert f"moved(&{stack})" in moved, stack
    assert "AlbumEdit.noteMove(&moves, from: from, to: to)" in moved
    assert "followed(" in block(navigation, navigation.index("{", navigation.index("func open(")))


def test_nothing_after_a_write_reaches_the_next_persons_pages():
    # (review, 16 Nov) an apply in flight at a sign-out carries on on the server, but its read, its page refreshes and
    # its follow stop there: the model keeps the session the sheet opened in (AppNavigation's, moved on by reset)
    routes = code(ROUTES)
    navigation = declared(routes, "class", "AppNavigation")
    assert "private(set) var session = 0" in navigation
    assert "session += 1" in block(navigation, navigation.index("{", navigation.index("func reset(")))
    assert "made.attach(navigation, library: library)" in code(SHEET)
    model = code(MODEL)
    assert "session = navigation.session" in block(model, model.index("{", model.index("func attach(")))
    for name in ("func apply()", "func saveCoverOnly()", "private func wrote(", "private func lookForMove(",
                 "private func moved("):
        assert "samePerson" in block(model, model.index("{", model.index(name))), name
    apply = block(model, model.index("{", model.index("func apply()")))
    assert apply.index("guard samePerson else { return }") < apply.index("await lookUp()")
    follow = block(model, model.index("{", model.index("private func lookForMove(")))
    assert follow.count("self.samePerson") == 2, "before each look, and before its answer moves anything"


def test_a_read_never_drops_the_album_mid_write():
    # (review, 16 Nov) settle lets neither the album nor its Release go while an apply or the cover alone runs - Close
    # would come back on and the write's end would land on a dropped model - and no folder is picked meanwhile
    model = code(MODEL)
    assert "var writing: Bool { applying || retag?.flow.savingCover == true }" in model
    settle = block(model, model.index("{", model.index("private func settle()")))
    assert settle.lstrip().startswith("guard !writing, let answer = scan.answer else { return }")
    assert "guard !writing," in block(model, model.index("{", model.index("func choose(")))
    sheet = code(SHEET)
    assert ".disabled(model.writing)" in block(sheet, sheet.index("{", sheet.index("private func folderMenu(")))
    assert sheet.count(".disabled(!model.online || model.marking || model.writing)") == 2
    # a write's end reads the folder only when it wrote, or a gap asked for it
    for name in ("func apply()", "func saveCoverOnly()"):
        body = block(model, model.index("{", model.index(name)))
        assert body.index("guard retag.flow.needsRead else { return }") < body.index("await lookUp()"), name
        assert "if outcome != .refused { wrote(before: before) }" in body, name


def test_a_failed_read_is_said_with_look_again():
    # (review, 16 Nov) a read after a write or a gap that fails ends the wait (RetagFlow.couldNotRead) and is said in
    # the phone's words with Look again - on the root (no longer hidden while an album is held) and on Release
    model = code(MODEL)
    look = block(model, model.index("{", model.index("func lookUp()")))
    assert "case .failed:" in look and "retag?.couldNotRead()" in look
    sheet = code(SHEET)
    root = declared(sheet, "struct", "EditAlbumRoot")
    sections = block(root, root.index("{", root.index("private func albumSections(")))
    assert "if model.scan.failure != nil {" in sections and "ReadAgainFailed(model: model)" in sections
    failed = declared(sheet, "struct", "ReadAgainFailed")
    assert "ErrorNote(text: failure)" in failed and "Button(EditWords.lookAgain)" in failed
    assert "await model.lookUp()" in failed
    # whichever part's read is waited for (review, 16 Nov): the Release's or Tags', else the scan's
    assert "failure = model.readBlocking ?? model.scan.failure" in failed
    model = code(MODEL)
    blocking = block(model, model.index("{", model.index("var readBlocking: String?")))
    assert "if tags?.flow.readFailed == true, let said = tags?.readFailure { return said }" in blocking
    assert "guard retag?.flow.readFailed == true || tags?.flow.readFailed == true else { return nil }" in blocking
    assert "return scan.failure ?? EditWords.readFailed" in blocking
    release = code(RELEASE)
    assert "if retag.flow.readFailed {" in release and "ReadAgainFailed(model: model)" in release
    # the cover alone: off while the folder is to be read again or a write runs
    assert re.search(r"\.disabled\(incoming == nil \|\| !retag\.flow\.canSaveCover \|\| model\.tagsApplying \|\| "
                     r"model\.getting\s*\|\| model\.deleting\)", release)


def test_a_cancellation_is_neither_failure_nor_answer():
    # (review, 16 Nov) the search, the preview (wentAway cancels one in flight) and the scan's read each leave what was
    # there when cancelled
    retag = code(RETAG)
    search = block(retag, retag.index("{", retag.index("func search()")))
    assert "guard !APIFailure.isCancellation(error) else {" in search and "flow.searchCancelled(ticket)" in search
    assert search.index("isCancellation") < search.index("candidates = []")
    preview = block(retag, retag.index("{", retag.index("private func schedulePreview()")))
    assert "guard !APIFailure.isCancellation(error) else { return }" in preview
    assert preview.index("isCancellation") < preview.index("self.flow.failed(edit)")
    scan = code(SCAN)
    read = block(scan, scan.index("{", scan.index("func read(")))
    assert "guard !APIFailure.isCancellation(error) else { return .dropped }" in read
    assert read.index("isCancellation") < read.index("failed = (error, admin)")


def test_back_in_reach_the_search_and_the_pressing_are_asked_again():
    # (review, 16 Nov) section 2: everything asked again - Core's rules (RetagFlow.searchesOnReturn,
    # Retag.currentToLoad) held by RetagModelTests
    retag = code(RETAG)
    back = block(retag, retag.index("{", retag.index("func cameBack()")))
    assert "flow.searchesOnReturn(atOnce: Retag.searchesAtOnce(album))" in back
    assert "Retag.currentToLoad(candidates, album: album, selectedId: selectedId," in back
    assert "await load(current, seed: false)" in back


def test_each_part_of_the_root_is_its_permissions():
    # the web's issues and marks are on its Release tab (Edit albums'), the marks Look after the library's too - so with
    # Look after the library alone the editor has Delete album… only, with Edit albums alone no marks (checks 338, 342)
    sheet = code(SHEET)
    root = declared(sheet, "struct", "EditAlbumRoot")
    sections = block(root, root.index("{", root.index("private func albumSections(")))
    assert "let edit = Managing.albumEdit(server.access.permissions)" in sections
    gate = sections.index("if edit.editors {")
    assert "needsALook(album)" in block(sections, sections.index("{", gate))
    assert sections.count("needsALook(album)") == 1
    assert "if edit.editors, let retag = model.retag {" in sections
    assert "if edit.delete {" in sections
    assert "NavigationLink(value: EditPage.delete)" in block(sections, sections.index("{", sections.index("if edit.delete {")))
    marks = block(root, root.index("{", root.index("private func needsALook(")))
    assert "let marks = AlbumEdit.marksFine(server.access.permissions)" in marks
    assert "if marks, !outstanding.isEmpty {" in marks and "if marks {" in marks


def test_every_choice_is_a_menu():
    sheet = code(SHEET)
    assert "Picker(EditWords.folder" in sheet and ".pickerStyle(.menu)" in sheet
    for path in (SHEET, RELEASE, FOLDERS):
        text = code(path)
        for style in (".pickerStyle(.inline)", ".pickerStyle(.wheel)", ".pickerStyle(.segmented)"):
            assert style not in text, f"{path.name} has {style}"


def test_nothing_in_edit_album_opens_a_url():
    # James: "nothing in the app should take you to the web app" - Tags since slice 2, Artwork and Lyrics since slice 3,
    # Delete album… since slice 4 (tests/test_ios_edit_parts.py): no WebAppRow is left in Edit album
    for path in sorted(EDIT.glob("*.swift")):
        text = code(path)
        for word in ("openURL", "UIApplication.shared.open(", "Link(destination:", "SFSafariViewController", "WKWebView",
                     "WebAppRow", "Managing.albumURL(", "Managing.url("):
            assert word not in text, f"{path.name} has {word}"
    core = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "RetagFlow.swift").read_text(encoding="utf-8")
    assert "inWebApp" not in core, "the words of a row that is gone"


def test_the_scan_is_the_editors_own_and_asked_without_tracks():
    scan = code(SCAN)
    assert "client.libraryScan(ifNoneMatch:" in scan
    # never written to disk: managing shows nothing stale as live
    for word in ("FileManager", "UserDefaults", "write(to:"):
        assert word not in scan, word
    core = (REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "EditClient.swift").read_text(encoding="utf-8")
    assert 'request(Routes.libraryAlbums, query: [("tracks", "false")])' in core


def test_rows_read_as_one_and_grow_with_the_text():
    folders = code(FOLDERS)
    row = declared(folders, "struct", "FolderRow")
    assert ".accessibilityElement(children: .ignore)" in row and ".accessibilityLabel(EditWords.folderRow(album))" in row
    assert ".fixedSize(horizontal: false, vertical: true)" in row
    release = code(RELEASE)
    pressing = declared(release, "struct", "RetagPressingRow")
    assert ".accessibilityLabel(EditWords.releaseRow(" in pressing
    # no fixed text sizes anywhere in Edit album: Dynamic Type sizes every word
    for path in sorted(EDIT.glob("*.swift")):
        assert not re.search(r"\.font\(\.system\(size:", code(path)), path.name
