"""
The panel review's R16 - the Mac's dock tabs (notes/ios.md "The panel review, R16: the Mac's dock tabs (2026-11-26)";
panel-review.md's checks 617-624). James, 26 Nov: "on mac, if i go to "info" next to the play bar, everything is still
rounded." No slice had redrawn the inside of the dock's tabs; this holds what R16 drew there:

  - No tab's page has a system bar, a title or a Done; Escape still puts the panel away - MacPanel's own key, through
    MacFrame.escape, the one owner - standing aside while a page holds Escape itself (the Queue's Done in Edit,
    Sources' Close until R19). The EQ hides only its root's bar: its pushed pages keep the system's until R17.
  - DockHeader and DockBack, the dock's two pieces R17 and R19 build on: a row of `.btn.sm`s, and `‹ <where you came
    from>` in the accent in a pushed page's bar's place (`.dockBack`).
  - Info (a song, an album, an artist), the Queue and Lyrics in the dock's own type, tokens only - no inset list, no
    LabeledContent, no material, no system type - and Album info flat on the phone too.
  - Every play an existing PlayerModel call made in the click, nothing awaited first.
  - The lit line follows the song in the dock as on the phone, with no Follow button.
  - The phone's Queue and Info as R3b drew them: their phone-only parts pinned by digest, as at 8696ce8a.
  - The Queue's header fits the panel's 400: History and Clear fold into a ••• only where the three toggles leave
    them no room.
"""

import hashlib
import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"
PANELS = "Player/MacPanels.swift"
INFO = "Info/InfoView.swift"
ALBUM_INFO = "Album/AlbumInfoView.swift"
QUEUE = "UpNext/UpNextScreen.swift"
LYRICS = "Player/LyricsView.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_dock_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def code(text: str) -> str:
    """Swift as code: its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


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


def member(text: str, declaration: str) -> str:
    """The body of the one member declared as `declaration`."""
    found = list(re.finditer(r"(?<![\w.])" + re.escape(declaration) + r"\b[^{]*\{", text))
    assert len(found) == 1, f"{declaration} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


#? the old look's names - none in what R16 drew for the Mac (and nowhere in Album info): the old palette and corners,
#? the system's text styles, its bordered buttons, its inset list, its grouped rows, its materials
OLD_LOOK = re.compile(r"(?<![\w.])Palette\.|(?<![\w.])Corners\.|(?<![\w.])MacCorners\.|Typeface\.(?:headline|footnote|"
                      r"subheadline|body|title|caption|callout)\b|\.bordered\w*|\.borderless|\.insetGrouped|"
                      r"LabeledContent|Material\b|\.regularMaterial|\bForm\s*\{|cornerRadius:\s*\d")


def old_look(text: str) -> list[str]:
    return [found.group(0) for found in OLD_LOOK.finditer(text)]


# ----------------------------------------------------------------------------- no bar, no Done; Escape the panel's

def test_no_dock_tab_has_a_bar_a_title_or_a_done():
    panels = code(source(PANELS))
    for page in ("struct MacPanel: View", "struct DockEmpty: View", "struct DockInfo: View", "struct DockAlbumInfo: View",
                 "struct DockArtistInfo: View", "struct LyricsPanel: View"):
        drawn = member(panels, page)
        for gone in ("NavigationStack", ".navigationTitle(", "DockDone(", ".toolbar {", "ToolbarItem"):
            assert gone not in drawn, f"{page}: {gone}"
    #? the EQ's root alone loses its bar: its pushed pages keep the system's, and DockDone, until R17
    dock_eq = flat(member(panels, "struct DockEQ: View"))
    assert ("EQScreen(opened: .now) .toolbar(.hidden, for: .navigationBar) .navigationDestination(for: EQRoute.self)"
            in dock_eq)
    assert "DockDone(words: EQWords.Screen.done)" in flat(code(source("EQ/EQRoute.swift")))
    #? Info's and the Queue's Mac pages hide the stack's bar; neither has a toolbar of its own now
    info = flat(code(source(INFO)))
    assert "macPage(tabs: tabs, tab: tab, admin: admin) .toolbar(.hidden, for: .navigationBar)" in info
    queue = code(source(QUEUE))
    top = flat(member(queue, "fileprivate func queueTop"))
    assert "let top = mac() self.toolbar(.hidden, for: .navigationBar) .safeAreaInset(edge: .top, spacing: 0) { top }" in top
    for name, text in ((INFO, info), (QUEUE, queue), (PANELS, panels)):
        assert "ToolbarItem" not in text and "InfoWords.done" not in text, name
    #? Album info pushed in the dock goes back with `‹ Info`; the phone keeps the system's Back
    assert "AlbumInfoList(album: push.album) .dockBack(inSidePanel ? InfoWords.title : nil)" in info
    #? a tab with nothing to be about: its words alone
    assert "DockEmpty(words: words)" in panels


def test_escape_is_the_panels_own_key_through_the_one_owner():
    panels = code(source(PANELS))
    panel = flat(member(panels, "struct MacPanel: View"))
    assert ".background { DockEscapeKey(held: holds.any) } .environment(holds)" in panel
    assert "@State private var holds = DockEscapeHolds()" in panel
    key = flat(member(panels, "struct DockEscapeKey: View"))
    assert "Button(action: { navigation.closePanel() }) { DWPalette.panel }" in key
    assert (".escapeCloses(!held && MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == "
            ".panel) .focusable(false) .frame(width: 0, height: 0) .opacity(0) .accessibilityHidden(true)") in key
    #? a page holds Escape through the environment - never a preference a NavigationStack may not pass up - and lets go
    #? as it goes
    holds = flat(member(panels, "struct DockHoldsEscape: ViewModifier"))
    for part in (".onAppear { holds?.hold(holder, held) }", "holds?.hold(holder, now)",
                 ".onDisappear { holds?.hold(holder, false) }"):
        assert part in holds, part
    assert "PreferenceKey" not in panels
    #? the Queue's Done in Edit, and Sources' Close until R19
    queue = flat(member(code(source(QUEUE)), "private func macTop"))
    assert (".escapeCloses(editing && MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == "
            ".panel) } .background(DWPalette.panel) .dockHoldsEscape(editing)") in queue
    assert "MacSourcesTab() .dockHoldsEscape()" in flat(member(panels, "var page: some View"))
    #? MacFrame.escape is the one owner still, and Routes.swift's is untouched
    assert "MacDock.escape(typing: typing, shown: panel)" in flat((CORE / "MacDock.swift").read_text(encoding="utf-8"))


# ----------------------------------------------------------------------------- the two pieces

def test_dock_header_and_dock_back_are_the_docks_two_pieces():
    panels = code(source(PANELS))
    header = flat(member(panels, "struct DockHeader<Leading: View, Trailing: View>: View"))
    assert "init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing)" in header
    assert ("HStack(spacing: DockLook.headerGap) { leading Spacer(minLength: 0) trailing } "
            ".buttonStyle(DWButtonStyle(size: .small))") in header
    assert ("EdgeInsets(top: DockLook.headerTop, leading: DockLook.headerSide, bottom: DockLook.headerFoot, "
            "trailing: DockLook.headerSide)") in header
    assert "extension DockHeader where Trailing == EmptyView" in panels and "extension DockHeader where Leading == EmptyView" in panels
    #? Album.dc.html's header: 10 above, 12 in, 2 below, 6 between
    look = flat(member(panels, "enum DockLook"))
    for size in ("headerTop: CGFloat = 10", "headerSide: CGFloat = 12", "headerFoot: CGFloat = 2", "headerGap: CGFloat = 6"):
        assert size in look, size
    back = flat(member(panels, "struct DockBack: View"))
    assert 'Text("\\(Image(systemName: "chevron.left")) \\(words)")' in back
    assert ".foregroundStyle(DWPalette.acc)" in back and ".buttonStyle(.plain)" in back
    assert ".help(MacDock.Words.back(to: words)) .accessibilityLabel(MacDock.Words.back(to: words))" in back
    top = flat(member(panels, "struct DockBackTop: ViewModifier"))
    assert "if let words { content .toolbar(.hidden, for: .navigationBar) .safeAreaInset(edge: .top, spacing: 0) {" in top
    assert "DockBack(words: words) { dismiss() }" in top and "} else { content }" in top
    words = flat((CORE / "MacDock.swift").read_text(encoding="utf-8"))
    assert 'public static func back(to page: String) -> String { "\\(page), Back" }' in words


# ----------------------------------------------------------------------------- the tabs' pages

def test_the_tabs_draw_in_the_looks_tokens_only():
    #? MacPanels and Album info whole, and the Mac's half of each shared page (its Mac members, by name)
    found = {PANELS: old_look(code(source(PANELS))), ALBUM_INFO: old_look(code(source(ALBUM_INFO)))}
    info = code(source(INFO))
    found[INFO] = old_look("".join(member(info, name) for name in (
        "private func macPage", "private func macSong", "private func macAbout", "private func macDebug",
        "struct InfoEQFact: View")))
    queue = code(source(QUEUE))
    found[QUEUE] = old_look("".join(member(queue, name) for name in (
        "private func macTop", "private var macModes", "private func macPlaying", "private func macHeading",
        "private func macWords", "struct QueueTryAgain: ViewModifier")).replace(".buttonStyle(.borderless)", "", 1))
    found[LYRICS] = old_look(member(code(source(LYRICS)), "private func dockedLine"))
    assert found == {name: [] for name in found}, found
    #? the Queue's list on the panel's ground on the Mac: a plain list, no inset rows, no material over it
    look = flat(member(queue, "struct QueueListLook: ViewModifier"))
    assert "} else { content .listStyle(.plain) .scrollContentBackground(.hidden)" in look
    assert ".insetGrouped" not in queue and "Material" not in queue
    overlay = flat(queue[queue.index("if history.loading && !editing {"):queue.index(".accessibilityLabel(UpNextWords.loadingEarlier)")])
    assert ".background(DWPalette.card, in: DWCorners.boxShape) .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line))" in overlay
    #? the old chips and the inset card are gone
    for gone in ("struct Chip: View", "private func playingCard", "private var modes:", "private func macToolbar"):
        assert gone not in queue, gone


def test_info_for_a_song_is_the_albums_panel_for_a_song():
    info = code(source(INFO))
    song = flat(member(info, "private func macSong"))
    for part in ("CoverImage(id: track.coverArt, size: DockLook.cover)", ".clipShape(DWCorners.chipShape)",
                 ".font(DockType.title)", ".foregroundStyle(DWPalette.acc)", ".font(DockType.readout)",
                 "MacDock.Words.facts([format, AboutCard.sizeLine(size: song.size, bitRate: song.bitRate)])"):
        assert part in song, part
    about = flat(member(info, "private func macAbout"))
    #? Info's own ways on, the primary first, each where there is somewhere to go
    assert about.index("DWButtonStyle(kind: .pri)") < about.index("AboutFactWords.goToArtist") < about.index(
        "NavigationLink(value: AlbumInfoPush(album: album))")
    assert "navigation.openAlbum(route)" in about and "goToArtist(artistID, name: track.artist)" in about
    assert "DockGroup(legend: MacAlbumFacts.Words.properties)" in about and "DockGroup(legend: AboutFactWords.theAlbum)" in about
    assert "DockFact(label: DownloadWords.playsFrom, value: playsFrom(track.id))" in about and "InfoEQFact()" in about
    page = flat(member(info, "private func macPage"))
    assert "DWSegmented(options: tabs, words:" in page and "ScrollView {" in page
    assert "List {" not in info and ".listStyle(" not in info
    #? the dock's sizes: Albums.dc.html's 16 in, 14 between, the cover 112, the title 18 bold
    panels = code(source(PANELS))
    look = flat(member(panels, "enum DockLook"))
    for size in ("side: CGFloat = 16", "gap: CGFloat = 14", "cover: CGFloat = 112", "picture: CGFloat = 96",
                 "factLabel: CGFloat = 76", "playingRow: CGFloat = 44", "playingCover: CGFloat = 30"):
        assert size in look, size
    assert "static var title: Font { Typeface.Mac.text(.h3).weight(.bold) }" in flat(member(panels, "enum DockType"))


def test_info_for_an_album_and_an_artist():
    album = code(source(ALBUM_INFO))
    body = flat(member(member(album, "struct AlbumInfoList: View"), "var body: some View"))
    assert "if Platform.mac { macHeader(whole ?? album) if inSidePanel { macTools(whole, online: online) } }" in body
    assert "List {" not in album and ".listStyle(" not in album
    #? Album info's own rules, as before
    assert "folders: server.access.isAdmin" in body and "played: played(whole)" in body
    section = flat(member(album, "private func infoSection"))
    assert "DockGroup(legend: section.title)" in section and "PhoneGroup(legend: section.title)" in section
    phone = flat(member(album, "private func phoneRow"))
    assert "case .plain where row.lines.isEmpty: PhoneKV(label: row.label, value: row.value)" in phone
    assert "PhoneGo {" in phone and "ErrorNote(text: AlbumInfoWords.notOpened)" in phone
    #? the artist: Artists.dc.html's round picture, the name, Go to artist, and A4's About - no Play without songs
    artist = flat(member(code(source(PANELS)), "struct DockArtistInfo: View"))
    assert "ArtistPicture(id: artist.preview?.coverArt, side: DockLook.picture, pixels: CoverSize.tile)" in artist
    assert "Button(MacDock.Words.goToArtist) { navigation.open(.artist(artist)) }" in artist
    assert "AboutBlockView(drawn: drawn, faces: Self.faces)" in artist
    assert ("about.ask(page: page, person: server.person, question: question, client: server.client, "
            "online: reachability.online)") in artist
    assert "player." not in artist, "no Play or Shuffle: the row holds none of the artist's songs"


def test_every_play_is_an_existing_call_made_in_the_click():
    tools = flat(member(code(source(ALBUM_INFO)), "private func macTools"))
    for call in ("player.play(songs: songs, album: whole, at: nil)", "player.play(songs: songs, album: whole, at: nil, shuffle: true)",
                 "_ = player.addToQueue(queued, album: whole)",
                 "navigation.editAlbum(AlbumEditRequest(target: .album(AlbumEdit.Subject(whole))))"):
        assert call in tools, call
    for awaited in ("await", "Task", "async"):
        assert awaited not in tools, awaited
    #? each behind its own gate: the songs in hand (offline those on this Mac), Add to Queue's pick, Edit's permission
    assert "if Managing.albumEdit(server.access.permissions).shown, online, let whole {" in tools
    playable = flat(member(code(source(ALBUM_INFO)), "private func playable"))
    assert "let songs = whole?.song ?? [] return online ? songs : OfflineAlbum.playable(songs, here: downloads.isHere)" in playable
    assert "AddToQueue.pick($0, online: online, gone: false, here: downloads.isHere)" in tools
    #? the Queue's and Lyrics' plays are as they were
    queue = flat(code(source(QUEUE)))
    assert "if player.jump(to: row.key) { focusAtCard = next.map { .row($0.key) } ?? .done }" in queue
    lyrics = flat(member(code(source(LYRICS)), "private func playFrom"))
    assert "player.seek(to: time) if !player.isPlaying { player.toggle() }" in lyrics


def test_the_lit_line_follows_the_song_in_the_dock_with_no_follow_button():
    lyrics = code(source(LYRICS))
    row = flat(member(lyrics, "private func row"))
    assert "if docked { dockedLine(line.text, time: time, lit: isLit) } else { lineText(line.text, color: isLit ? Color.primary : dim) }" in row
    #? following, the hold and the tap are the phone's own: nothing of them reads `docked`
    for name in ("private func follow", "private func playFrom"):
        assert "docked" not in member(lyrics, name), name
    body = flat(member(member(lyrics, "struct LyricsView: View"), "var body: some View"))
    assert ".onChange(of: lit.range?.first) { guard hold.follows(now: Self.nowMs(), playing: player.isPlaying) else { return } hold.follow() follow(proxy, smooth: placed) }" in body
    line = flat(member(lyrics, "private func dockedLine"))
    for part in ("Text(LyricsWords.time(time)) .font(DockType.smallReadout)", ".frame(minHeight: DockLyricsLook.line)",
                 ".background { if isLit { DWPalette.selbg } }", "isLit ? DWPalette.selt"):
        assert part in line, part
    assert "line: CGFloat = 40" in flat(member(lyrics, "enum DockLyricsLook"))
    panel = flat(member(code(source(PANELS)), "struct LyricsPanel: View"))
    assert "DWChip(words: MacDock.Words.synced, tone: .good)" in panel
    assert "lyrics.face == .synced && lyrics.shown?.synced == true" in panel
    assert "Button(LibraryWords.tryAgain) { lyrics.retry() } .buttonStyle(DWButtonStyle())" in panel
    assert "Follow" not in panel


# ----------------------------------------------------------------------------- the phone's, as R3b drew them

#? (R16) the phone-only parts of the Queue, Info and Lyrics, digested (comments out, spacing made one) as at 8696ce8a,
#? before R16: the dock's redraw changes none of them. A deliberate change to one changes its digest here, in its commit.
PHONE_PARTS = {
    QUEUE: ("private func phoneTop", "static func folds", "private func toHistory", "private func phoneFoot",
            "private var modeButtons", "private func playingRow", "private func heading", "struct QueueTimeLeftLine: View",
            "private func playRow", "private func historyRow", "private func pastRow"),
    INFO: ("private func phonePage", "private func songRow", "private func phoneAbout", "private func goes",
           "private func goToArtist", "private func phoneDebug", "struct InfoKV: View", "struct InfoEQRow: View",
           "struct InfoDebugRow: View", "struct InfoButtonWords: View", "private func aboutFacts",
           "private func debugSections"),
    LYRICS: ("private func lineText", "private func follow", "private func playFrom"),
}
PHONE_DIGESTS = {
    "UpNext/UpNextScreen.swift: private func phoneTop": "d5aec659e73791bc",
    "UpNext/UpNextScreen.swift: static func folds": "29b296f91966c534",
    "UpNext/UpNextScreen.swift: private func toHistory": "23b724ff3327f9eb",
    "UpNext/UpNextScreen.swift: private func phoneFoot": "495633d5019e55d6",
    "UpNext/UpNextScreen.swift: private var modeButtons": "7c1d438b6c32aa36",
    "UpNext/UpNextScreen.swift: private func playingRow": "743aa1ca8cd47dc9",
    "UpNext/UpNextScreen.swift: private func heading": "aae93a2e92b250f7",
    "UpNext/UpNextScreen.swift: struct QueueTimeLeftLine: View": "6142a5aa35cb8482",
    "UpNext/UpNextScreen.swift: private func playRow": "7ea15e0e3732e8c3",
    "UpNext/UpNextScreen.swift: private func historyRow": "6bd384e5e9d81847",
    "UpNext/UpNextScreen.swift: private func pastRow": "a65e039fd1424741",
    "Info/InfoView.swift: private func phonePage": "7431faec1698024c",
    "Info/InfoView.swift: private func songRow": "6d6ccd0fe3dcf0a7",
    "Info/InfoView.swift: private func phoneAbout": "88ace1dcfb2bad74",
    "Info/InfoView.swift: private func goes": "e596f866d32b1c67",
    "Info/InfoView.swift: private func goToArtist": "b1d22ee308700e66",
    "Info/InfoView.swift: private func phoneDebug": "56bb0bbfde2655f7",
    "Info/InfoView.swift: struct InfoKV: View": "5da77226ea8940c6",
    "Info/InfoView.swift: struct InfoEQRow: View": "f562d790b525cac3",
    "Info/InfoView.swift: struct InfoDebugRow: View": "ffc3415906246ab4",
    "Info/InfoView.swift: struct InfoButtonWords: View": "209cdc0e9314cbb8",
    "Info/InfoView.swift: private func aboutFacts": "09b8435ec67a5a34",
    "Info/InfoView.swift: private func debugSections": "442818dcb0b15004",
    "Player/LyricsView.swift: private func lineText": "a9f8af0b0e48c416",
    "Player/LyricsView.swift: private func follow": "c4bdb009da5be438",
    "Player/LyricsView.swift: private func playFrom": "907054811cb935f0",
}


def phone_digests(text_of) -> dict[str, str]:
    found = {}
    for name, parts in PHONE_PARTS.items():
        text = code(text_of(name))
        for part in parts:
            found[f"{name}: {part}"] = hashlib.sha256(flat(member(text, part)).strip().encode("utf-8")).hexdigest()[:16]
    return found


def test_the_phones_queue_and_info_are_as_r3b_drew_them():
    assert phone_digests(source) == PHONE_DIGESTS
    #? the shared row modifiers' phone halves as R3b drew them: the Mac's halves are the dock's (R16)
    queue = code(source(QUEUE))
    row = flat(member(queue, "struct QueuePhoneRow: ViewModifier"))
    assert ("if phone { content .overlay(alignment: .bottom) { if rule { DWRule(colour: DWPalette.rowRule) } } "
            ".listRowInsets(EdgeInsets()) .listRowSeparator(.hidden) .listRowBackground(DWPalette.panel) } else {") in row
    look = flat(member(queue, "struct QueueListLook: ViewModifier"))
    assert ("if phone { content .listStyle(.plain) .scrollContentBackground(.hidden) .listSectionSpacing(0) "
            ".environment(\\.defaultMinListRowHeight, 0) } else {") in look
    #? the phone's Edit row's minus as R3b drew it
    edit = flat(member(queue, "private func editRow"))
    assert (".foregroundStyle(.white, .red) .font(Typeface.symbol(.title3)) .frame(minWidth: 44, minHeight: 44)"
            in edit[:edit.index("} else {")])


def test_album_info_is_flat_on_the_phone():
    #? (R16) Album info's phone half: PhoneGroups on hairlines, no face drawn - only the page's own black under it
    phone = phone_look.phone_path(phone_look.bare(source(ALBUM_INFO)))
    #? the Mac's own members (its header, its tools and track box, its rows) never drawn on the phone
    for mac in (r"private func macHeader\(", r"private func macTools\(", r"private func macRow\("):
        phone = phone_look.cut(phone, mac)
    drawn = phone_look.drawn(phone)
    assert drawn == ALBUM_INFO_DRAWS, drawn
    assert ALBUM_INFO in phone_look.R16_PAGES and phone_look.R16_PAGES <= phone_look.SLICES
    #? Lyrics' docked rows draw with the look's pieces, the phone's rows as they were
    assert LYRICS in phone_look.R16_PAGES


#? the page's ground (the panel's on the Mac, the page's black on the phone) and the groups' hairlines - no card, no face
ALBUM_INFO_DRAWS = ["background: DWPalette.panel, DWPalette.page", "DWRule: DWPalette.groupRule"]


# ----------------------------------------------------------------------------- the Queue's header fits

#? Typeface.Look's small button (12, medium) on the Mac and DWLook's Mac `.btn.sm` (8 either side), the header's 12
#? either side and 6 between, the ••• glyph taken wide (an SF Symbol at its words' size, test_ios_library_look.py's 1.3)
SMALL_BUTTON = 12
SMALL_PADDING = 8
SYMBOL = 1.3


def small_button(words: str) -> float:
    return 2 * SMALL_PADDING + fonts.words(words, SMALL_BUTTON, "medium")


def test_the_queues_header_fits_the_dock():
    look = flat((CORE / "DWLook.swift").read_text(encoding="utf-8"))
    mac = look[look.index("static let mac"):look.index("static let phone")] if "static let phone" in look else look
    assert re.search(r"smallButtonPadding: (?:MacLook\.\w+|8)\b", mac), "the Mac's .btn.sm: 8 either side"
    assert float(re.search(r"public static let panelWidth: Double = (\d+)",
                           flat((CORE / "MacLook.swift").read_text(encoding="utf-8"))).group(1)) == 400
    room = 400 - 2 * 12
    gap = 6
    repeats = re.findall(r'case \.(?:off|all|one): return "([^"]+)"', flat((CORE / "UpNextView.swift").read_text(encoding="utf-8")))
    assert sorted(repeats) == ["Repeat", "Repeat all", "Repeat one"], repeats
    more = 2 * SMALL_PADDING + SYMBOL * SMALL_BUTTON
    for autoplay in (False, True):
        for said in repeats:
            for edit in ("Edit", "Done"):
                toggles = [small_button("Shuffle"), small_button(said)] + ([small_button("Autoplay")] if autoplay else [])
                full = sum(toggles) + small_button("History") + small_button("Clear") + small_button(edit)
                full += gap * (len(toggles) + 2)
                folded = sum(toggles) + more + small_button(edit) + gap * (len(toggles) + 1)
                #? folded always fits; unfolded where it can
                assert folded <= room, (autoplay, said, edit, folded)
                if not autoplay:
                    assert full <= room, (said, edit, full)
    #? with Autoplay and "Repeat one" the five don't fit: the ••• is what the dock draws then
    widest = (small_button("Shuffle") + small_button("Repeat one") + small_button("Autoplay") + small_button("History")
              + small_button("Clear") + small_button("Done") + 5 * gap)
    assert widest > room, widest
    top = flat(member(code(source(QUEUE)), "private func macTop"))
    assert top.index("ViewThatFits(in: .horizontal) {") < top.index("Button(UpNextWords.history)") < top.index("Menu {")
    assert "Image(systemName: \"ellipsis\") .accessibilityLabel(QueuePageWords.more)" in top
