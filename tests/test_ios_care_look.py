"""
The redesign's slice R13 (notes/ios.md "The redesign, slice R13: Library care and the Event log"): Library care, In
nobody's library and the event log drawn as iLibraryCare and iEventLog draw them on the phone - flat - and as
LibraryCare.dc.html and EventLog.dc.html on the Mac, in its toolbar and boxes (MacLibraryCarePage, MacEventLogPage).

Read from the Swift source, as the other ios tests read theirs. Core's rules - a run's row and line, Get · N, the Mac's
lit button and its Stop, the status bars, Warnings taking errors too, Find, Copy, the chip's words, cleared lines never
coming back under any level, Stop waiting for the album under way - are held by CarePagesTests (and LibraryCareTests,
EventStreamTests before it).
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
CORE = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
CARE = APP / "Manage" / "LibraryCareScreen.swift"
HELD = APP / "Manage" / "HeldByNobodyScreen.swift"
LOG = APP / "Manage" / "EventLogScreen.swift"
MAC_CARE = APP / "Mac" / "Manage" / "MacLibraryCarePage.swift"
MAC_LOG = APP / "Mac" / "Manage" / "MacEventLogPage.swift"
MANAGE = APP / "Mac" / "Manage" / "MacManage.swift"
PHONE_FILES = [CARE, HELD, LOG]
MAC_FILES = [MAC_CARE, MAC_LOG]


def _load(name: str):
    path = Path(__file__).resolve().parent / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"_care_look_{name}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def partner(text: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(text)):
        if text[index] in "({":
            depth += 1
        elif text[index] in ")}":
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unbalanced")


def struct(text: str, name: str) -> str:
    found = list(re.finditer(r"\bstruct\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"struct {name} is declared {len(found)} times"
    opening = found[0].end() - 1
    return text[opening + 1:partner(text, opening)]


def body(text: str, start: str) -> str:
    """From `start` to the close of the brace it opens."""
    at = text.index(start)
    opening = text.index("{", at)
    return text[at:partner(text, opening) + 1]


def core_word(name: str, source: str = "CarePages.swift") -> str:
    found = re.search(rf'static let {name} = "([^"]+)"', (CORE / source).read_text(encoding="utf-8"))
    assert found, name
    return found.group(1).replace("\\u{2026}", "…")


# ----------------------------------------------------------------------------- the phone: flat

def test_library_care_and_the_log_are_flat_on_the_phone():
    # no inset-grouped grey cells: no Form, no List, no Section - SettingsPage's groups and notes on the page's black
    # (iLibraryCare), the log a scroll view of its strip and its lines (iEventLog) - and none of the iPhone's old palette
    # or type left in them
    for path in PHONE_FILES:
        source = code(path)
        for grey in ("Form {", "List {", "Section {", ".insetGrouped", "listRowBackground(", "LabeledContent(",
                     "SelectingList(", "Palette.", "Typeface.footnote", "Typeface.body", "Typeface.caption",
                     "Typeface.mono(", "Typeface.readout(", "PrimaryFace(", ".buttonStyle(.borderless)"):
            if grey == "Palette.":
                assert not re.search(r"(?<!DW)Palette\.", source), f"{path.name}: {grey}"
            else:
                assert grey not in source, f"{path.name}: {grey}"
        # the large title, as drawn - never the inline one
        assert ".navigationBarTitleDisplayMode(.inline)" not in source, path.name
    for path, view in ((CARE, "LibraryCareScreen"), (HELD, "HeldByNobodyScreen")):
        assert "SettingsPage {" in struct(code(path), view), view
    log = flat(struct(code(LOG), "EventLogScreen"))
    # the page's one scroll, the strip first - after (R13's review) the chip, when it is under the bar
    assert "ScrollView { LazyVStack(alignment: .leading, spacing: 0) { if !LiveChip.inBar(typeSize) {" in log
    assert log.index("if !LiveChip.inBar(typeSize) {") < log.index("PhoneStrip(")


#? everything R13's phone files draw on the phone's path that has a fill, a face, an edge or a rule (R1c's DRAWS): the
#? hairlines alone - under Narrow to's note and each run's row, under In nobody's library's line, each album and each
#? flag, under the log's problem and each line. Narrow to's well is DWField's own (FLAT_DRAWS), the meter DWMeter's,
#? Add for them the purple's, the strip PhoneStrip's
R13_DRAWS = {
    "Manage/EventLogScreen.swift": ["DWRule: DWPalette.rowRule"] * 2,
    "Manage/HeldByNobodyScreen.swift": ["DWRule: DWPalette.groupRule"] * 3,
    "Manage/LibraryCareScreen.swift": ["DWRule: DWPalette.groupRule"] * 2,
}


def test_the_phones_pages_draw_no_grey_box():
    assert {f"Manage/{path.name}" for path in PHONE_FILES} == look.R13_PAGES
    found = {}
    for name in sorted(look.R13_PAGES):
        draws = look.drawn(look.phone_path(look.bare((APP / name).read_text(encoding="utf-8"))))
        if draws:
            found[name] = draws
    assert found == R13_DRAWS, found
    # the matcher sees a face planted on one of the groups
    planted = look.bare("PhoneGroup(legend: x) { Text(y) }.background(DWPalette.panel)")
    assert look.drawn(look.phone_path(planted)) == ["background: DWPalette.panel"]
    # only the purple keeps a face: Add for them; every other button is the flat accent's
    buttons = {path.name: re.findall(r"DWButtonStyle\(([^)]*)\)", code(path)) for path in PHONE_FILES}
    faced = [(name, style) for name, styles in buttons.items() for style in styles if "kind:" in style]
    assert faced == [("HeldByNobodyScreen.swift", "kind: .pri, size: .small, fills: across")], faced
    # Narrow to: the look's well (DWField) in a field's row - anywhere you type is a box
    care = flat(code(CARE))
    assert "DWFieldRow(label: LibraryCare.narrowTo) { DWField(prompt: LibraryCare.narrowPrompt, text: Binding(" in care
    assert "TextField(" not in care


def test_the_phones_rows_are_the_drawings():
    care = code(CARE)
    # Rescan: the flat button and the scan's facts beside it on its first baseline, in the readout face's third colour -
    # (R13's review) the drawing's short ones ("140 albums · 2 min ago"), the whole line VoiceOver's
    rescan = flat(struct(care, "RescanRow"))
    assert "HStack(alignment: .firstTextBaseline, spacing: CareLook.gap) { button facts }" in rescan
    assert ("let now = context.date.timeIntervalSince1970 * 1000 Text(LibraryCare.shortFacts(care.scan.albums, "
            "loaded: care.scan.loaded, scannedAt: care.scan.answer?.scannedAt, rescanning: care.runs.rescanning, "
            "now: now)) .font(Typeface.Phone.mono(.extraSmall)) .foregroundStyle(DWPalette.t3) "
            ".fixedSize(horizontal: false, vertical: true) .frame(maxWidth: .infinity, alignment: .leading) "
            ".accessibilityLabel(care.facts(now: now))") in rescan
    assert "LibraryCare.rescanLibrary" in rescan
    # a run's row (iLibraryCare's `.go`): its name 62 wide at least, what Get would take or the meter and the album out,
    # and Get · N or Stop - on the group's hairline, a `.go` row's height at least
    row = flat(struct(care, "KindRow"))
    assert ".frame(minWidth: typeSize.isAccessibilitySize ? nil : CareLook.nameWidth, alignment: .leading)" in row
    assert "DWMeter(fraction: LibraryCare.runFraction(under.run)) Text(line) .font(Typeface.Phone.mono(.extraSmall))" in row
    assert "let line = under.map(LibraryCare.runLine) ?? LibraryCare.rowLine(kind, count: targets?.count)" in row
    assert "CareButtonWords(words: LibraryCare.getShort(count: targets.count))" in row
    assert "CareButtonWords(words: LibraryCare.stopShort(stopping: runs.stopping(kind)))" in row
    assert ".lookHeight(PhoneLook.goRow) .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }" in row
    # under the three: one album at a time, then the screen kept on
    assert "SettingsNote(words: LibraryCare.runsNote, colour: DWPalette.t3)" in care
    words = (CORE / "CarePages.swift").read_text(encoding="utf-8")
    assert 'public static var runsNote: String { "\\(oneAtATime) \\(screenOnNote)" }' in words
    # the collection: In nobody's library and Flagged downloads, each with its count, both to In nobody's library's page
    collection = flat(body(care, "private var collection: some View {"))
    assert collection.count("NavigationLink(value: AppRoute.heldByNobody) {") == 2
    assert "CollectionRow(title: Held.title, count: answer?.count)" in collection
    assert "CollectionRow(title: Held.flagged, count: answer?.flags.count)" in collection
    assert 'DWCount(count: "' in code(CARE).replace("\\(count)", "")
    # the log's line: its time, level and part in mono on one first baseline, its words under them, on the row's
    # hairline (iEventLog's `padding: 9px 16px 10px`)
    line = flat(struct(code(LOG), "LogRow"))
    assert "HStack(alignment: .firstTextBaseline, spacing: CareLook.gap) { time level(tone) part }" in line
    assert (".padding(.horizontal, CGFloat(PhoneLook.bigSide)) .padding(.top, CareLook.logPad) "
            ".padding(.bottom, CareLook.logPad + 1)") in line
    sizes = flat(body(care, "enum CareLook {"))
    assert "static let logPad: CGFloat = 9" in sizes and "static let logGap: CGFloat = 3" in sizes
    assert "static let nameWidth: CGFloat = 62" in sizes


def test_the_level_strip_counts_what_it_shows():
    log = flat(code(LOG))
    # the strip's levels, each with the count of the very lines it would show (Core's count, its shows)
    assert ("PhoneStrip(options: EventLog.Shown.allCases, words: { (part: EventLog.Shown) -> String in "
            "EventLog.stripWords(part, count: EventLog.count(feed.log.lines, part)) }, shown: $level, "
            "spoken: EventLog.levels, said: { (part: EventLog.Shown) -> String in "
            "EventLog.stripSaid(part, count: EventLog.count(feed.log.lines, part)) })") in log
    words = flat((CORE / "CarePages.swift").read_text(encoding="utf-8"))
    count = words[words.index("public static func count("):]
    assert "shows(shown, line) ? sum + 1 : sum" in count[:300]
    shown = words[words.index("public static func shown("):]
    assert "shows(shown, line) && finds(line, typed: typed)" in shown[:300]
    # and the bar's Copy takes the lines shown - never the ones a level hides
    assert "Button(EventLog.copy) { copy(shown) } .disabled(shown.isEmpty)" in log
    assert "guard let text = EventLog.copyShown([], of: shown) else { return }" in log


# ----------------------------------------------------------------------------- gates, on both

def test_every_part_is_gated_as_the_phones_page_was_on_both():
    for path in (CARE, MAC_CARE):
        source = flat(code(path))
        # without the part, nothing asked; out of reach before a read, needs deadwax
        assert "if !parts.shown {" in source and "EditWords.noPermission" in source, path.name
        assert "EditWords.needsDeadwax" in source, path.name
        assert ".editOutOfReach(!online && care.scan.loaded)" in source, path.name
        assert "if reduceMotion { transaction.animation = nil }" in source, path.name
        # Rescan with Look after the library, the runs with Edit albums, the collection with logins on too
        assert "if parts.rescan {" in source and "if parts.bulk {" in source and "care.heldShown" in source, path.name
        # nothing pressed before a read to trust or out of reach
        assert ".disabled(!care.rescanOpen(online: online))" in source, path.name
        # the page's hooks: shown, hidden, a part given, signed in again
        for hook in (".onAppear { care.shows()", ".onDisappear { care.hides()",
                     ".onChange(of: parts.shown) { _, shown in if shown { care.shows() } }",
                     ".onChange(of: server.signInOver == nil) { _, clear in if clear { care.sessionBack() }",
                     ".task(id: care.heldShown) { held.attach(server: server, navigation: navigation, "
                     "reachability: reachability) guard care.heldShown else { return } await held.read() }"):
            assert hook in source, (path.name, hook)
    mac = flat(code(MAC_CARE))
    tools = flat(struct(code(MAC_CARE), "MacCareTools"))
    assert tools.count("if parts.rescan { rescan }") == 2 and tools.count("if parts.bulk {") == 3
    # the toolbar's Get and the pop-up's: each dimmed with nothing to take or while it may not start - (R13's review)
    # from the page's one snapshot of the scan
    assert tools.count("let targets = snapshot.targets(kind)") == 2
    assert tools.count(".disabled(targets?.isEmpty != false || !snapshot.startOpen(kind))") == 2
    assert "if parts.shown { MacCareTools(online: reachability.online, snapshot: snapshot) }" in mac
    # a run's row's Get, on both: never pressed before a read to trust or out of reach - as its action too
    phone = flat(struct(code(CARE), "KindRow"))
    assert phone.count("care.startOpen(kind, online: online)") == 2
    assert ".disabled(!care.startOpen(kind, online: online))" in phone
    row = flat(struct(code(MAC_CARE), "MacKindRow"))
    assert row.count("snapshot.startOpen(kind)") == 2 and ".disabled(!snapshot.startOpen(kind))" in row
    assert "let targets = snapshot.targets(kind)" in row
    # the collection's writes: one at a time, never while it is read (Held.Flow), on both - (R13's review) the phone's
    # each button on its own, whichever way they are laid out; the Mac's row has one layout, its two buttons in one
    for path, view in ((HELD, "HeldFlagRow"), (MAC_CARE, "MacFlagRow")):
        row = flat(struct(code(path), view))
        assert "let open = model.flow.open(online: online, reading: model.reading)" in row, view
        assert ".accessibilityActions { if open {" in row, view
    held = flat(struct(code(HELD), "HeldFlagRow"))
    assert held.count("buttons(open: open)") == 2 and held.count(".disabled(!open)") == 2
    assert ("CareButtonWords(words: Held.addForThem) } .buttonStyle(DWButtonStyle(kind: .pri, size: .small, "
            "fills: across)) .disabled(!open)") in held
    assert "CareButtonWords(words: Held.dismiss) } .buttonStyle(DWButtonStyle(size: .small, fills: across)) .disabled(!open)" in held
    flags = flat(struct(code(MAC_CARE), "MacFlagRow"))
    assert flags.count(".disabled(!open)") == 1
    assert (".buttonStyle(DWButtonStyle(size: .small)) } .disabled(!open) } } .macCareRow(rowSize, striped: striped, "
            "least: MacCareLook.flagRow)") in flags
    # the log: Settings and the log's
    for path in (LOG, MAC_LOG):
        source = flat(code(path))
        assert "if !log.allowed {" in source and "EditWords.noPermission" in source, path.name
        assert "if log.allowed {" in source, path.name
        for hook in (".onAppear { log.shows() }", ".onDisappear { log.hides() }",
                     ".onChange(of: log.allowed) { _, _ in log.recheck() }",
                     ".onChange(of: navigation.nowPlayingShown) { _, _ in log.recheck() }"):
            assert hook in source, (path.name, hook)


def test_stop_waits_for_the_album_under_way_everywhere():
    # every Stop - the phone's row, the Mac's row, its toolbar, its pop-up - is CareRunModel.stop, which only asks Core
    # to end the run after the album out (CareRuns.stop; its `next` holds while one is out - CarePagesTests,
    # LibraryCareTests): nothing cancels the album under way
    model = flat(code(APP / "Manage" / "CareRunModel.swift"))
    assert "func stop(_ kind: BulkTargets.Kind) { runs.stop(kind) }" in model
    for path, stops in ((CARE, 2), (MAC_CARE, 4)):
        source = code(path)
        calls = re.findall(r"care\.stop\(([^)]*)\)", source)
        assert len(calls) == stops, (path.name, calls)
        assert ".cancel()" not in source and "Task.cancel" not in source, path.name
    # Stopping… once pressed: the button off, as the album finishes - (R13's review) each Stop's own chain
    assert flat(code(CARE)).count(".disabled(runs.stopping(kind))") == 1
    phone = flat(struct(code(CARE), "KindRow"))
    assert ("Button { care.stop(kind) } label: { CareButtonWords(words: LibraryCare.stopShort(stopping: "
            "runs.stopping(kind))) } .buttonStyle(DWButtonStyle(size: .small, fills: across)) "
            ".disabled(runs.stopping(kind))") in phone
    row = flat(struct(code(MAC_CARE), "MacKindRow"))
    assert ("Button(LibraryCare.toolbarStop(under.run, stopping: runs.stopping(kind))) { care.stop(kind) } "
            ".buttonStyle(DWButtonStyle(size: .small)) .disabled(runs.stopping(kind))") in row
    tools = flat(struct(code(MAC_CARE), "MacCareTools"))
    assert tools.count(".disabled(care.runs.stopping(under.kind))") == 2
    assert ("Button(LibraryCare.toolbarStop(under.run, stopping: care.runs.stopping(under.kind))) { care.stop(under.kind) "
            "} .buttonStyle(DWButtonStyle()) .disabled(care.runs.stopping(under.kind))") in tools
    assert ("Button(LibraryCare.toolbarStop(under.run, stopping: care.runs.stopping(under.kind))) { care.stop(under.kind) "
            "} .disabled(care.runs.stopping(under.kind))") in tools


def test_each_stop_and_get_acts_on_its_own_kind():
    # (R13's review) CareRuns.stop and start check the kind: a Stop or Get wired to a kind of its own choosing - Stop on
    # a CD art run asking covers to stop - does nothing. Every call's argument is its row's kind, or the run under way's
    for path, view, stop, start, stops, starts in (
            (CARE, "KindRow", "kind", "kind", 2, 2),
            (MAC_CARE, "MacKindRow", "kind", "kind", 2, 2),
            (MAC_CARE, "MacCareTools", "under.kind", "kind", 2, 2)):
        drawn = struct(code(path), view)
        stopped = re.findall(r"care\.stop\(([^)]*)\)", drawn)
        started = re.findall(r"care\.start\(([^)]*)\)", drawn)
        assert stopped == [stop] * stops, (view, stopped)
        assert started == [start] * starts, (view, started)
    # and no other Stop or Get anywhere on the pages
    assert len(re.findall(r"care\.stop\(", code(CARE))) == 2 and len(re.findall(r"care\.start\(", code(CARE))) == 2
    assert len(re.findall(r"care\.stop\(", code(MAC_CARE))) == 4 and len(re.findall(r"care\.start\(", code(MAC_CARE))) == 4


def test_clear_empties_this_view_only_on_both():
    # Clear is EventLogModel.clear on both - the view emptied, deadwax's lines kept, nothing cleared coming back under
    # any level (EventStream's emptied/joining, CarePagesTests' clearedLinesNeverComeBackUnderAnyLevel)
    phone, mac = flat(code(LOG)), flat(code(MAC_LOG))
    assert "Button(EventLog.clear) { log.clear() }" in phone
    assert "Button(EventLog.clearView) { log.clear() selected = [] }" in mac
    for source in (phone, mac):
        assert ".accessibilityHint(EventLog.clearHint)" in source
        assert source.count("log.clear()") == 1
    assert core_word("clearView") == "Clear this view"
    # the Mac's levels and Find narrow what is shown, the status bar counting what is kept
    assert "let shown = EventLog.shown(feed.log.lines, level, find: typed)" in mac
    assert "let said = EventLog.status(feed.log.lines, stream: feed.stream)" in mac
    assert ("DWSegmented(options: EventLog.Shown.allCases, words: { (part: EventLog.Shown) -> String in "
            "EventLog.label(part) }, chosen: $level, spoken: EventLog.levels, large: true)") in mac
    assert "DWField(prompt: EventLog.findPrompt, text: $typed)" in mac
    # Copy: the lines selected still shown, else every line shown
    assert "guard let text = EventLog.copyShown(selected, of: shown) else { return }" in mac
    # (R13's review) the narrower toolbars' levels pop-up chooses the level - bound, never a copy of it
    menu = flat(body(code(MAC_LOG), "private var levelsMenu: some View {"))
    assert ("DWPopUp(words: EventLog.label(level)) { Picker(EventLog.levels, selection: $level) { "
            "ForEach(EventLog.Shown.allCases, id: \\.self) { (part: EventLog.Shown) in "
            "Text(EventLog.label(part)).tag(part) } } .pickerStyle(.inline) }") in menu
    assert flat(body(code(MAC_LOG), "@ViewBuilder private func tools(")).count("levelsMenu") == 2


def test_a_selection_the_level_or_find_hides_is_let_go_of():
    # (R13's review) an INFO line selected, Errors picked: it was kept, so Edit > Copy was dimmed while the toolbar's
    # Copy took every error, and with Everything again Copy took the stale line alone. Now every change to the lines
    # shown - a level, Find, a line in or out, Clear - lets go of what they hide (Core's keptSelection:
    # CarePagesTests' aSelectionTheLevelOrFindHidesIsLetGo)
    mac = flat(code(MAC_LOG))
    assert ".onChange(of: shown.map(\\.id)) { _, ids in selected = EventLog.keptSelection(selected, shown: ids) }" in mac
    assert mac.count("selected = ") == 2, "the change above, and Clear's"
    words = flat((CORE / "CarePages.swift").read_text(encoding="utf-8"))
    kept = words[words.index("public static func keptSelection("):]
    assert "return selected.intersection(ids)" in kept[:300]


def test_the_live_logs_stripes_stay_with_their_lines():
    # (R13's review) striped by its place, every row flipped as a line came in at the top: by the line's own number now
    lines = flat(body(code(MAC_LOG), "@ViewBuilder private func lines("))
    assert ".listRowBackground(EventLog.striped(line) ? MacPalette.rowStripe : DWPalette.bg)" in lines
    assert "enumerated()" not in lines and "% 2" not in lines
    words = flat((CORE / "CarePages.swift").read_text(encoding="utf-8"))
    assert "public static func striped(_ line: Line) -> Bool { (line.seq ?? line.id.taken) % 2 == 0 }" in words


def test_every_cut_mac_cell_has_its_whole_words_as_help():
    # (R13's review) a cell cut to its column (a truncation mode) says the whole as its help, before the next Text
    for path in MAC_FILES:
        source = flat(code(path))
        for found in re.finditer(r"\.truncationMode\(", source):
            rest = source[found.end():]
            nxt = min((at for at in (rest.find("Text("), rest.find("} "), rest.find("MacCareCell(")) if at >= 0),
                      default=len(rest))
            assert ".help(" in rest[:nxt], (path.name, source[max(0, found.start() - 120):found.start()])
    care = flat(code(MAC_CARE))
    for help_ in (".help(album)", ".help(Held.flagName(flag))", ".help(Held.askedBy(flag))",
                  ".help(Held.albumHelp(album))", ".help(album.artist)", ".help(Held.flagWords(flag))"):
        assert help_ in care, help_
    assert ".help(line.src ?? \"\")" in flat(code(MAC_LOG))
    # (R13's review) the Album cell names the album alone - its artist is the next column's
    album = flat(struct(code(MAC_CARE), "MacHeldAlbumRow"))
    assert "Text(Held.albumCell(album))" in album and "Held.albumName(album) :" not in album
    words = flat((CORE / "CarePages.swift").read_text(encoding="utf-8"))
    assert "album.album.isEmpty ? name(album: nil, artist: nil) : album.album" in words


def test_show_all_is_lazy_on_both():
    # (R13's review) Show all can be hundreds of albums: lazy rows, as the List was, inside the page's one scroll
    held = flat(body(code(HELD), "private var page: some View {"))
    assert ("LazyVStack(alignment: .leading, spacing: 0) { ForEach(Held.listedAlbums(answer.albums, all: model.all)) "
            "{ (album: Held.UnheldAlbum) in HeldAlbumRow(album: album) } }") in held
    table = flat(struct(code(MAC_CARE), "MacCareTable"))
    assert "LazyVStack(spacing: 0) { rows }" in table
    assert "MacCareTable(columns: [Held.columnAlbum, Held.columnArtist]" in flat(code(MAC_CARE))


def test_the_mac_narrows_the_scan_once_a_render():
    # (R13's review) the status bar, the toolbar's three ways and the rows each narrowed the scan again - some 40 times
    # a render: one LibraryCare.Snapshot now, passed down (CarePagesTests holds its answers CareRuns')
    mac = code(MAC_CARE)
    assert mac.count("LibraryCare.Snapshot(") == 1
    assert ("let snapshot = LibraryCare.Snapshot(care.runs, care.scan.albums, allowed: parts.bulk, "
            "online: reachability.online)") in flat(mac)
    for again in ("care.targets(", "care.startOpen(", "care.scopeNote", "LibraryCare.narrow(", "runs.targets(",
                  "runs.startOpen("):
        assert again not in mac, again
    for view in ("MacCareTools", "MacRunsBox", "MacKindRow"):
        assert "let snapshot: LibraryCare.Snapshot" in struct(mac, view), view


def test_getting_never_applies_a_release():
    # a run is CareRunModel.start - client-driven, one album at a time; the pages apply, retag or choose nothing
    for path in (CARE, MAC_CARE):
        source = code(path)
        assert re.findall(r"care\.start\(([^)]*)\)", source), path.name
        for writer in ("retag", "apply(", "RetagFlow", "releaseMbid"):
            assert writer not in source, (path.name, writer)


# ----------------------------------------------------------------------------- the Mac's pages

def test_the_mac_routes_to_its_own_pages():
    manage = code(MANAGE)
    assert "case .libraryCare: MacLibraryCarePage()\n" in manage
    assert "case .heldByNobody: MacLibraryCarePage()\n" in manage
    assert "case .eventLog: MacEventLogPage()\n" in manage
    # the Mac's pages draw no phone piece (a phone row's 46, a strip, a group) - its own boxes and toolbars
    for path in MAC_FILES:
        source = code(path)
        for phone in ("PhoneGroup", "PhoneStrip", "PhoneGo", "SettingsPage", "SettingsGo", "SettingsNote", "PhoneLook",
                      "Typeface.Phone", ".settingsRow("):
            assert phone not in source, (path.name, phone)
        assert not re.search(r"(?<!Mac)CareLook\.", source), path.name
        assert "MacPage {" in source and ".macStatus(" in source, path.name
        # one scroll each - never a list in a scroll view
        assert source.count("ScrollView(") + source.count("SelectingList(") == 1, path.name
        # no right-click of its own: the pages have no •••
        assert "contextMenu" not in source and "macContextMenu" not in source, path.name


def test_the_macs_rows_take_the_row_size():
    for path, rows in ((MAC_CARE, ("MacHeldAlbumRow", "MacFlagRow")), (MAC_LOG, ("MacLogRow",))):
        source = code(path)
        for row in rows:
            drawn = flat(struct(source, row))
            assert "@Environment(\\.macRowSize) private var rowSize" in drawn, row
    care = flat(code(MAC_CARE))
    assert "frame(maxWidth: .infinity, minHeight: max(CGFloat(rowSize.rowHeight), least), alignment: .leading)" in care
    assert ".macCareRow(rowSize, striped: striped)" in care
    assert ".macCareRow(rowSize, striped: striped, least: MacCareLook.flagRow)" in care
    log = flat(struct(code(MAC_LOG), "MacLogRow"))
    assert ".frame(maxWidth: .infinity, minHeight: CGFloat(rowSize.rowHeight), alignment: .leading)" in log
    # every cell of a log line on one first baseline, in the readout face
    assert "HStack(alignment: .firstTextBaseline, spacing: 0) {" in log and ".font(Typeface.Mac.mono(.small))" in log


def test_voiceover_reads_each_row_once_with_its_buttons_as_actions():
    for path, view, actions in (
            (CARE, "KindRow", ("Button(stop) { care.stop(kind) }",
                               "Button(LibraryCare.startLabel(kind, count: targets.count)) { care.start(kind) }")),
            (MAC_CARE, "MacKindRow", ("Button(stop) { care.stop(kind) }",
                                      "Button(LibraryCare.startLabel(kind, count: targets.count)) { care.start(kind) }")),
            (HELD, "HeldFlagRow", ("Button(Held.addForThem) { model.act(flag, .add, online: online) }",
                                   "Button(Held.dismiss) { model.act(flag, .dismiss, online: online) }")),
            (MAC_CARE, "MacFlagRow", ("Button(Held.addForThem) { model.act(flag, .add, online: online) }",
                                      "Button(Held.dismiss) { model.act(flag, .dismiss, online: online) }"))):
        row = flat(struct(code(path), view))
        assert ".accessibilityElement(children: .ignore)" in row, view
        assert ".accessibilityActions {" in row, view
        for action in actions:
            assert action in row, (view, action)
    # a run's row: its name and line spoken once, the long words its hint; Stop offered only before it is pressed
    for path, view in ((CARE, "KindRow"), (MAC_CARE, "MacKindRow")):
        row = flat(struct(code(path), view))
        assert ".accessibilityLabel([LibraryCare.spokenRow(kind, line: line), waiting, result.isEmpty ? nil : result]" in row
        assert ".accessibilityHint(LibraryCare.note(kind, targets: targets, typed: runs.narrow))" in row
        assert "if !runs.stopping(kind) { Button(stop)" in row
    # the collection's rows: their counts said, the badges hidden
    assert ".accessibilityLabel(Held.spokenRow(title, count: count))" in flat(struct(code(CARE), "CollectionRow"))
    # a log line: once, words first, Copy its action - on both
    for path, view in ((LOG, "LogRow"), (MAC_LOG, "MacLogRow")):
        row = flat(struct(code(path), view))
        assert ".accessibilityElement(children: .ignore) .accessibilityLabel(EventLog.spoken(line))" in row, view
        assert ".accessibilityAction(named: Text(EventLog.copy))" in row, view
    # the chip: one element, the line's whole words - (R13's review) its whole chain, so no part of it goes alone
    assert ("DWChip(words: EventLog.chipWords(state), tone: Self.tone(state)) "
            ".dynamicTypeSize(...DynamicTypeSize.xxxLarge) .accessibilityElement(children: .ignore) "
            ".accessibilityLabel(EventLog.words(state)) .accessibilityShowsLargeContentViewer { "
            "Text(EventLog.chipWords(state)) }") in flat(struct(code(LOG), "LiveChip"))


#? Dynamic Type's footnote (Apple's table) - the chip's words are footnote-relative: 13 at Large
FOOTNOTE = {"large": 13, "xLarge": 15, "xxLarge": 17, "xxxLarge": 19, "AX3": 33, "AX5": 44}


def test_the_chip_in_the_bar_stops_growing_at_xxxlarge():
    # (R13's review) a bar caps at xxxLarge (plan 3.3, the tab bar's): uncapped, "Reconnecting…" grew with the
    # accessibility sizes to some 360 points and from AX3 pushed Copy, Clear or Back out of reach. Capped at xxxLarge
    # it is still some 164 points, more than a 375 phone's bar leaves beside Back, Copy and Clear (the bar's own buttons
    # at 17, which don't grow; an estimate of the bar: its 16 either side, Back's 44, 8 between items) - so it is in the
    # bar up to xLarge, where it fits, and under the bar larger, where the old line was, across the page
    log = code(LOG)
    chip = flat(struct(log, "LiveChip"))
    assert chip.count(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)") == 1
    assert "static let barsLargest = DynamicTypeSize.xLarge" in chip
    assert "static func inBar(_ size: DynamicTypeSize) -> Bool { size <= barsLargest }" in chip
    toolbar = flat(body(log, ".toolbar {"))
    assert toolbar.count("LiveChip(state: feed.stream)") == 1
    assert "if live(feed) && LiveChip.inBar(typeSize) { LiveChip(state: feed.stream) }" in toolbar
    lines = flat(log[log.index("@ViewBuilder private func lines"):log.index("struct LiveChip")])
    assert lines.count("LiveChip(state: feed.stream)") == 1
    assert ("if !LiveChip.inBar(typeSize) { LiveChip(state: feed.stream) .frame(maxWidth: .infinity, alignment: .leading)"
            " .padding(.horizontal, CGFloat(PhoneLook.bigSide))") in lines
    assert lines.index("LiveChip(state: feed.stream)") < lines.index("PhoneStrip(")
    assert "@Environment(\\.dynamicTypeSize) private var typeSize" in flat(struct(log, "EventLogScreen"))

    def width(points: float) -> float:
        scale = points / FOOTNOTE["large"]
        words = max(_width(said, points, "medium") for said in ("Connecting…", "Live", "Reconnecting…", "Not live"))
        return words + 6 * scale + 5 + 2 * 5   # the dot (6, growing), its gap, 5 either side

    room = 375 - 2 * 16 - 44 - (_width("Copy", 17) + 2 * 12) - (_width("Clear", 17) + 2 * 12) - 3 * 8
    assert width(FOOTNOTE["xLarge"]) <= room, (width(FOOTNOTE["xLarge"]), room)
    assert width(FOOTNOTE["xxLarge"]) > room, "the first size under the bar is one the bar has no room for"
    # under the bar it has the page's width, and capped it fits that at every size
    assert width(FOOTNOTE["xxxLarge"]) <= 375 - 2 * 16
    assert width(FOOTNOTE["AX3"]) > room and width(FOOTNOTE["AX5"]) > 300, "what the cap stops"


def test_at_the_accessibility_sizes_rows_stack_and_buttons_take_three_lines():
    words = flat(struct(code(CARE), "CareButtonWords"))
    assert "Text(words) .lineLimit(typeSize.isAccessibilitySize ? CareLook.buttonLines : 1) .multilineTextAlignment(.center)" in words
    assert "static let buttonLines = 3" in flat(code(CARE))
    for path, view in ((CARE, "RescanRow"), (CARE, "KindRow"), (HELD, "HeldFlagRow"), (LOG, "LogRow"),
                       (CARE, "RereadFailure"), (LOG, "Problem")):
        row = flat(struct(code(path), view))
        assert "if typeSize.isAccessibilitySize { VStack(alignment: .leading," in row, view
    # (R13's review) Try again under its words, across the row, its words on up to three lines - the read again that
    # failed, and the log's problem
    for path, view, words in ((CARE, "RereadFailure", "LibraryCare.tryAgain"), (LOG, "Problem", "EventLog.tryAgain")):
        row = flat(struct(code(path), view))
        assert ("if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: CareLook.lines) { said tryAgain } "
                "} else { HStack(alignment: .firstTextBaseline, spacing: CareLook.gap) { said tryAgain } }") in row, view
        assert (f"CareButtonWords(words: {words}) }} .buttonStyle(DWButtonStyle(size: .small, "
                "fills: typeSize.isAccessibilitySize))") in row, view
    # stacked, every button across the row, its words wrapping
    care, held = flat(code(CARE)), flat(code(HELD))
    assert ".buttonStyle(DWButtonStyle(fills: typeSize.isAccessibilitySize))" in care
    assert care.count(".buttonStyle(DWButtonStyle(size: .small, fills: across))") == 2
    assert held.count("fills: across))") == 2 and held.count("CareButtonWords(words:") == 2


# ----------------------------------------------------------------------------- fits

def _width(words: str, points: float, weight: str = "medium") -> float:
    return fonts.words(words, points, weight)


def _mac_widths():
    look = (CORE / "MacLook.swift").read_text(encoding="utf-8")
    frame = (CORE / "MacFrame.swift").read_text(encoding="utf-8")
    sidebar = float(re.search(r"public static let sidebarWidth: Double = (\d+)", look).group(1))
    opening = float(re.search(r"public static let openingWidth: Double = (\d+)", frame).group(1))
    smallest = float(re.search(r"public static let smallestWidth: Double = (\d+)", frame).group(1))
    panel = float(re.search(r"public static let panelWidth: Double = (\d+)", frame).group(1))
    return opening - sidebar, smallest - sidebar, opening - sidebar - panel - 1


def _number(source: str, name: str) -> float:
    found = re.search(rf"static let {name}: CGFloat = (\d+)", source)
    assert found, name
    return float(found.group(1))


def test_the_macs_toolbars_fold_to_every_page():
    # a window as it opens (a page of 1060), the smallest window's (660) and beside a side panel (589): every control
    # in reach on each, the toolbar's 12 in either side and its buttons 6 apart - a button its words at 12.5 (medium,
    # semibold for the lit one) and 11 either side, the groove 12, a pop-up its words, the caret's 6 and 8, and 22
    page, smallest, beside = _mac_widths()
    assert (page, smallest, beside) == (1060, 660, 589)
    care = (CORE / "LibraryCare.swift").read_text(encoding="utf-8")
    button = lambda words, weight="medium": _width(words, 12.5, weight) + 2 * 11  # noqa: E731
    popup = lambda words: _width(words, 12.5) + 6 + 8 + 2 * 11  # noqa: E731
    rescan = button(core_word("rescanLibrary"))
    groove = 12
    gets = [button(f"{label} · 140") for label in re.findall(r'case \.\w+: return "(Get [^"]+)"', care)]
    assert len(gets) == 3
    lit = button("Getting CD art · 140 of 140", "semibold")
    stop = max(button("Stop after this album"), button("Stopping after 141 of 140"))

    def bar(*parts: float) -> float:
        return sum(parts) + 6 * (len(parts) - 1) + 2 * 12

    idle = bar(rescan, groove, *gets, 8)
    running = bar(rescan, groove, lit, *gets[1:], 8, stop)
    folded = bar(rescan, groove, lit, 8, stop)
    assert idle <= beside, idle
    assert running <= page, running
    assert folded <= beside, folded
    # the event log: the levels' segments (11.5's large ones: 12.5 semibold, 10 either side), Find, the chip at its
    # widest (Reconnecting…, 11.5 semibold and 7 either side), Copy and Clear this view
    log = (CORE / "CarePages.swift").read_text(encoding="utf-8")
    levels = re.findall(r'case \.\w+: return "(Everything|Warnings|Errors)"', log)
    assert levels == ["Everything", "Warnings", "Errors"]
    segments = sum(_width(level, 12.5, "semibold") + 2 * 10 for level in levels) + 2
    chip = max(_width(words, 11.5, "semibold") for words in ("Connecting…", "Live", "Reconnecting…", "Not live")) + 2 * 7
    copy, clear = button("Copy"), button(core_word("clearView"))
    mac = (APP / "Mac" / "Manage" / "MacEventLogPage.swift").read_text(encoding="utf-8")
    find, narrow, least = (_number(mac, name) for name in ("findWidth", "narrowFindWidth", "leastFindWidth"))
    assert find == 260, "the drawing's Find"
    full = bar(segments, find, 8, chip, copy, clear)
    narrower = bar(popup("Everything"), narrow, 8, _width("Live", 11.5, "semibold") + 14, copy, clear)
    narrowest = bar(popup("Everything"), least, 8, copy, clear)
    assert full <= page and full > smallest, full
    assert narrower <= smallest, narrower
    assert narrowest <= beside, narrowest


def test_the_macs_boxes_take_two_columns_only_where_they_fit():
    # Flagged downloads' row is the widest of a column: the Album's least, The flag, and Add for them and Dismiss (12's
    # small buttons, 8 either side, 6 apart) in their cell's 10 either side - in its box's 12 either side and edge
    mac = (APP / "Mac" / "Manage" / "MacLibraryCarePage.swift").read_text(encoding="utf-8")
    small = lambda words, weight="medium": _width(words, 12, weight) + 2 * 8  # noqa: E731
    add = re.search(r'public static let addForThem = "([^"]+)"', (CORE / "LibraryCare.swift").read_text()).group(1)
    dismiss = re.search(r'public static let dismiss = "([^"]+)"', (CORE / "LibraryCare.swift").read_text()).group(1)
    buttons = small(add, "semibold") + 6 + small(dismiss) + 2 * 10
    assert buttons <= _number(mac, "flagButtonsWidth"), buttons
    flags = _number(mac, "albumLeast") + _number(mac, "flagWidth") + _number(mac, "flagButtonsWidth")
    # a run's row: its name, Stop after this album (the widest button), and room for the meter's line between
    runs = _number(mac, "nameWidth") + 10 + 150 + 10 + small("Stop after this album")
    column = max(flags, runs) + 2 * 12 + 2
    need = 2 * column + _number(mac, "columnGap") + 2 * _number(mac, "pageSide")
    threshold = _number(mac, "twoColumns")
    assert need <= threshold <= need + 12, (need, threshold)
    page, smallest, beside = _mac_widths()
    assert page >= threshold, "two columns in the window as it opens, as drawn"
    for narrow in (smallest, beside, threshold - 1):
        assert column <= narrow - 2 * _number(mac, "pageSide"), narrow
    # the log's columns: the faced chip's widest level in its cell's 10 either side; the rest grows
    log = (APP / "Mac" / "Manage" / "MacEventLogPage.swift").read_text(encoding="utf-8")
    widths = re.search(r"static let widths: \[CGFloat\?\] = \[(\d+), (\d+), (\d+), nil\]", log)
    time, level, part = (float(n) for n in widths.groups())
    assert (time, part) == (92, 124), "the drawing's Time and From"
    for name in ("WARNING", "CRITICAL", "ERROR", "INFO", "DEBUG"):
        assert _width(name, 11.5, "semibold") + 2 * 7 <= level - 2 * 10, name
    assert fonts.readout("00:00:00", 12) <= time - 2 * 10
    assert time + level + part + 120 <= beside


def test_the_phones_rows_fit_a_phone():
    # an iPhone's 375 less the page's 16 either side: a run's row - its name 62, Get · N (13.5's flat small button, 6
    # either side), 8 apart - leaves its line room; Rescan the library and its facts side by side
    room = 375 - 2 * 16
    get = max(_width("Get · 999", 13.5) + 12, 44)
    line = room - 62 - 8 - get - 8
    assert _width("14 albums without a cover", 13, "regular") <= line, line
    assert fonts.readout("4 of 14 · Post · Björk", 12) <= line, line
    # (R13's review) Rescan the library and its facts side by side: the real facts, in the 12-point readout - the whole
    # line (LibraryCare.facts) would take three lines there, so the drawing's short ones (shortFacts) are beside it
    rescan = _width(core_word("rescanLibrary"), 14) + 12
    beside = room - rescan - 8
    whole = "140 albums · 1412 tracks · 38.2 GB · Scanned 2 min ago in 0.8s"
    assert fonts.readout(whole, 12) > 2 * beside, (fonts.readout(whole, 12), beside)
    for short in ("140 albums · 2 min ago", "1412 albums · 23 days ago", "Reading every file again…",
                  "Reading the library…"):
        assert fonts.readout(short, 12) <= beside, (short, fonts.readout(short, 12), beside)
    words = (CORE / "CarePages.swift").read_text(encoding="utf-8")
    assert 'if rescanning { return "Reading every file again…" }' in words
    assert 'return age.isEmpty ? groups : "\\(groups) · \\(age)"' in words
