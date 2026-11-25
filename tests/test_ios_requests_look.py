"""
Requests in the redesign's look (slice R8 - notes/ios.md "The redesign, slice R8: Requests"; the drawings
Requests.dc.html and iRequests.dc.html): the Mac's table under its toolbar, the phone's cards, and the meter both draw.

The app's Swift read as text, as the other look tests read it, and the meter held to dw.css as the cascade resolves it:

- DWMeter (App/Look) is dw.css's `.meter`: the well, the line's edge, the inset shade, the fill inside the edge in its
  tone's gradient; its height DWLook's (.meter's 6 on the Mac, .dw.ph's 8 on the phone, grown with the text there), its
  corners DWCorners' (the Mac's 2 and 1, the phone's 0). A fill never passes its track: it takes Core's meterShare.
- The phone's cards: round stays round - the ✕ and the ▶ - and everything else is square; the data line in mono at .xs;
  the headings Core's RequestFilter.all.shown, so never one over nothing; a Done row's ▶ plays in the tap; a card's
  buttons, stacked, take up to 3 lines at the accessibility sizes.
- The Mac's page: the table's columns, rows and headings as Requests.dc.html draws them (Core's RequestColumns, whose
  numbers DeadwaxKit's RequestFilterTests hold too), its toolbar's Search Soulseek, All | Active | Done and Clear done,
  the status bar's counts and speed - and nothing the drawing shows that no route gives.
- (R8's review) A cancel that asked first acts on the row as it is now; nothing in the Progress column draws past its
  cell; the table fits the window as it opens, and the toolbar folds to every page down to the smallest - each added up
  here from Core's numbers and the words' lengths; a row is one element for VoiceOver on both devices; the Mac's keys.
- Tokens only, in every file Requests draws: no colour, radius or font of its own.
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_requests_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
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
    """The source with its comments blanked, its literals kept (some of what's held is words)."""
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


METER = "Look/DWMeter.swift"
CARDS = "Requests/RequestCards.swift"
SCREEN = "Requests/RequestsScreen.swift"
MAC_PAGE = "Mac/Requests/MacRequestsPage.swift"
FILTER = CORE / "RequestFilter.swift"


# ----------------------------------------------------------------------------- the meter

def test_the_meter_is_dw_css_meter():
    meter = flat(bare(source(METER)))
    # the track: the well, sunk by the inset shade along its top, inside the line's 1 pt edge - DWPalette's tokens
    rule = mac_look.rule(".meter")
    assert (rule["background"], rule["border"]) == ("var(--well)", "1px solid var(--line)"), rule
    assert rule["box-shadow"] == "inset 0 1px 2px rgba(0, 0, 0, 0.7)"
    assert ("DWCorners.meterShape .fill(DWPalette.well.shadow(.inner(color: DWPalette.meterShade, radius: 1, x: 0, y: 1)))"
            " .overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, lineWidth: 1) }") in meter
    # the fill: inside the edge (`.meter > i` sits in .meter's border), its corners its own, its tone's gradient
    assert ("GeometryReader { (track: GeometryProxy) in DWCorners.meterFillShape .fill(fill) "
            ".frame(width: track.size.width * share) } .padding(1)") in meter
    tones = body(meter, "private var fill: LinearGradient {")
    assert ("case .plain: return DWPalette.meterFill case .marked: return DWPalette.meterMarked "
            "case .good: return DWPalette.meterGood") in tones
    # dw.css's three fills, by the palette's own lines: .meter > i, .meter.pur > i, .meter.grn > i
    lines = phone_look.palette_lines()
    assert [lines[n][1] for n in ("meterFill", "meterMarked", "meterGood")] == [
        "dw: .meter > i background", "dw: .meter.pur > i background", "dw: .meter.grn > i background"]
    # a download's is the purple: the tone's default, and what both devices' rows draw
    assert "var tone: Tone = .marked" in meter
    assert "DWMeter(fraction: row.progress / 100)" in bare(source(CARDS))
    assert "DWMeter(fraction: row.progress / 100)" in bare(source(MAC_PAGE))
    # read by its words beside it, once
    assert ".accessibilityHidden(true)" in meter


def test_a_meters_fill_never_passes_its_track():
    meter = flat(bare(source(METER)))
    # the share is Core's, clamped - the fill's width is that share of the track, and nothing else
    assert "let share = CGFloat(DWLook.meterShare(fraction))" in meter
    assert meter.count("share") == 3, "the share made once, its width and its animation"
    look = flat(bare((CORE / "DWLook.swift").read_text(encoding="utf-8")))
    share = body(look, "public static func meterShare(_ fraction: Double) -> Double {")
    assert share == ("public static func meterShare(_ fraction: Double) -> Double { guard fraction.isFinite else "
                     "{ return 0 } return min(max(fraction, 0), 1) }"), share
    # the fill moves as the bytes come, and stands still with Reduce Motion
    assert ".animation(reduceMotion ? nil : .linear(duration: 0.25), value: share)" in meter


def test_the_meters_height_and_corners_are_each_devices():
    # 6 on the Mac, exactly; 8 on the phone (.dw.ph .meter), grown with the text there - DWLook's own fields, each held
    # to its rule by the look tests
    mac = dict((name, (value, src)) for name, value, src in mac_look.lookfields("static let onMac = DWLook("))
    assert mac["meterHeight"] == ("6", "dw: .meter height")
    assert phone_look.px(phone_look.css(".meter", "height")) == 8
    assert phone_look.px(mac_look.rule(".meter")["height"]) == 6
    meter = flat(bare(source(METER)))
    assert "@ScaledMetric(relativeTo: .footnote) private var grown: CGFloat = 1" in meter
    assert "CGFloat(DWLook.here.meterHeight) * (DWLook.here.grows ? grown : 1)" in meter
    assert ".frame(height: height)" in meter
    # rounded on the Mac (.meter 2px, its fill 1px), square on the phone: DWCorners' meter and meterFill
    assert phone_look.px(mac_look.rule(".meter")["border-radius"]) == 2
    assert phone_look.px(mac_look.rule(".meter > i")["border-radius"]) == 1
    assert phone_look.px(phone_look.css(".meter", "border-radius")) == 0
    assert phone_look.px(phone_look.css(".meter > i", "border-radius")) == 0
    corners = flat((APP / "Look" / "DWCorners.swift").read_text(encoding="utf-8"))
    assert ("static var meterShape: RoundedRectangle { RoundedRectangle(cornerRadius: meter, style: .circular) }"
            in corners)
    assert ("static var meterFillShape: RoundedRectangle { RoundedRectangle(cornerRadius: meterFill, style: .circular) }"
            in corners)


# ----------------------------------------------------------------------------- the phone's cards

def test_round_stays_round_and_the_rest_is_square():
    cards = bare(source(CARDS))
    # the ✕: a round face 32 across (.btn.sm's 32 on the phone) raised as a button is, in a finger's 44
    cancel = flat(body(cards, "private struct CancelButton: View {"))
    assert ("DWRaised(shape: Circle(), face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen, "
            "edge: DWPalette.buttonEdge, drop: DWPalette.buttonDrop)") in cancel
    assert phone_look.px(phone_look.css(".btn.sm", "height")) == 32
    assert "static let face: CGFloat = 32" in cards
    assert ".frame(width: CardSizes.face, height: CardSizes.face)" in cancel
    assert ".frame(minWidth: CGFloat(DWLook.here.target), minHeight: CGFloat(DWLook.here.target))" in cancel
    # the ▶: round, the phone's purple, the sharp glyph
    done = flat(body(cards, "struct DoneRowView: View {"))
    assert "SharpSymbol(.play)" in done and ".background(DWPalette.phonePrimaryFace, in: Circle())" in done
    # nothing else round: the two circles are the ✕'s and the ▶'s, every cover Corners' art (square), every card
    # PhoneCard's (square) - and no corner of their own
    assert cards.count("Circle()") == 2
    assert not re.search(r"cornerRadius|RoundedRectangle\(|\bCapsule\b|\.capsule\b", cards)
    assert ".clipShape(Corners.artShape)" in cards
    assert cards.count("PhoneCard {") == 2, "a download's card and a refused one's"


def test_the_cards_say_what_the_drawing_says():
    cards = bare(source(CARDS))
    job = flat(body(cards, "struct JobCardView: View {"))
    # the data line, "3 of 11 files · 244 KB/s": mono at .xs (.dw.ph's 12), one line, always drawn
    assert ('Text(row.data ?? " ") .font(Typeface.Phone.mono(.extraSmall)) .foregroundStyle(DWPalette.t2) '
            ".lineLimit(1)") in job
    assert phone_look.px(phone_look.css(".xs", "font-size")) == 12
    # the meter under the lines, 5 from them (its margin-top), only while downloading
    assert re.search(r"if downloading \{ DWMeter\(fraction: row\.progress / 100\) "
                     r"\.padding\(\.top, CardSizes\.aboveMeter - CardSizes\.lines\)", job)
    assert "static let lines: CGFloat = 3" in cards and "static let aboveMeter: CGFloat = 5" in cards
    # the covers: 48 on a card, 44 on a done row (the drawing's)
    assert "static let cover: CGFloat = 48" in cards and "static let doneCover: CGFloat = 44" in cards
    # a title .b at 16, a line .s at 13 in the second colour, a reason in red
    assert ".font(Typeface.Phone.text(.row).weight(.semibold))" in cards
    assert phone_look.px(phone_look.css(".s", "font-size")) == 13
    assert "CardLine(words: text, colour: DWPalette.redChipText)" in cards
    # Needs attention keeps both ways on, across the card (.btn.pri.grow and .btn.grow)
    attention = flat(body(cards, "struct AttentionCardView: View {"))
    assert ("Button { onRetry(false) } label: { ButtonWords(words: next.label, stacked: stacked) } "
            ".buttonStyle(DWButtonStyle(kind: next.primary ? .pri : .normal, fills: true))") in attention
    assert ("Button { onRetry(true) } label: { ButtonWords(words: again.label, stacked: stacked) } "
            ".buttonStyle(DWButtonStyle(fills: true))") in attention
    assert ".disabled(row.busy)" in attention
    # a done row: .row.tall's 60 at least, on the row's hairline
    done = flat(body(cards, "struct DoneRowView: View {"))
    assert ".lookHeight(DWLook.here.tallRowHeight) .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }" \
        in done


def test_a_cards_buttons_take_more_lines_at_the_accessibility_sizes():
    # (R8's review) slice 1's fix kept: a pair side by side while both fit on one line, each at its words' width; one
    # over the other otherwise, each across the card on up to 3 lines at the accessibility sizes
    cards = flat(bare(source(CARDS)))
    pair = body(cards, "private struct ButtonPair<Buttons: View>: View {")
    assert ("ViewThatFits(in: .horizontal) { HStack(spacing: 8) { buttons(false) } "
            "VStack(alignment: .leading, spacing: 8) { buttons(true) } }") in pair
    words = body(cards, "private struct ButtonWords: View {")
    # the limit on the words themselves, inside the button: the innermost is the one that holds over DWButtonStyle's one
    assert ("Text(words) .lineLimit(typeSize.isAccessibilitySize ? CardSizes.titleLines : 1) "
            ".multilineTextAlignment(.center) .fixedSize(horizontal: !stacked, vertical: stacked)") in words
    assert "static let titleLines = 3" in cards
    style = flat(bare(source("Look/DWButtonStyle.swift")))
    assert "configuration.label .font(Typeface.Look.text(role).weight(weight)) .foregroundStyle(words) .lineLimit(1)" in style
    assert ".fixedSize(horizontal: !fills, vertical: false)" in style, "a filling button's words may wrap"
    # every button in a pair: its words ButtonWords', and - stacked - filling the card, so they can wrap
    pairs = [body(cards[at:], "ButtonPair {") for at in [m.start() for m in re.finditer(r"ButtonPair \{", cards)]]
    assert len(pairs) == 2, "the cancel question's and Needs attention's"
    for found in pairs:
        buttons = re.findall(r"Button(?:\(action: \w+\))? \{.*?\} \.buttonStyle\(DWButtonStyle\(([^)]*)\)\)", found)
        assert len(buttons) == 2, found
        assert found.count("ButtonWords(words: ") == 2 and found.count("stacked: stacked)") == 2, found
        for style_args in buttons:
            assert "fills: stacked" in style_args or "fills: true" in style_args, style_args
    question = body(cards, "private struct CancelQuestion: View {")
    assert "DWButtonStyle(size: .small, fills: stacked)" in question
    assert "DWButtonStyle(kind: .danger, size: .small, fills: stacked)" in question


def test_every_heading_has_rows_under_it():
    screen = flat(bare(source(SCREEN)))
    # the phone's headings are Core's, each only over rows - the Mac's table's lines likewise
    assert "ForEach(RequestFilter.all.shown(board), id: \\.self) { (section: RequestSection) in" in screen
    assert "RequestSection.allCases" not in screen
    assert "let lines = filter.lines(board)" in flat(bare(source(MAC_PAGE)))
    filtered = flat(bare(FILTER.read_text(encoding="utf-8")))
    assert ("public func shown(_ board: RequestsView) -> [RequestSection] { sections.filter { (section: RequestSection) "
            "-> Bool in !board.rows(section).isEmpty } }") in filtered
    assert "shown(board).flatMap" in filtered
    # .row.grp on the phone: 38 at least, its words at its foot (6 up), the head's colour, 15 and semibold
    heading = body(screen, "private func heading(_ section: RequestSection) -> some View {")
    assert (".font(Typeface.subheadline.weight(.semibold)) .foregroundStyle(DWPalette.head) "
            ".padding(.bottom, Sizes.headingFoot) .frame(maxWidth: .infinity, "
            "minHeight: CGFloat(DWLook.here.groupRowHeight), alignment: .bottomLeading) "
            ".accessibilityAddTraits(.isHeader)") in heading
    grp = phone_look.resolved(".row.grp")
    assert (grp["font-size"], grp["font-weight"], grp["padding-bottom"], grp["align-items"]) == (
        "15px", "600", "6px", "flex-end")
    assert grp["color"] == phone_look.resolved(".dw")["--head"]
    # the list 16 in either side (the drawing's padding: 0 16px)
    assert "static let side: CGFloat = 16" in bare(source(SCREEN))


def test_every_play_is_in_the_tap():
    # a done row's ▶ (the phone) and Play (the Mac): the player's own call, in the tap, nothing awaited before it
    for name in (SCREEN, MAC_PAGE):
        code = bare(source(name))
        play = body(code, "private func play(_ row: RequestRow) {")
        call = play.index("player.play(songs: plays.songs, album: plays.album, at: 0)")
        assert "await" not in play[:call] and "Task" not in play[:call], name
        assert "await" not in play and "Task" not in play, name
    assert "onPlay: { play(row) }" in bare(source(SCREEN))
    assert "Button(action: onPlay) {" in bare(source(CARDS))
    assert re.search(r"Button \{\s*play\(row\)\s*\} label:", bare(source(MAC_PAGE)))
    # VoiceOver's Play, the right-click's and the •••'s reach the same call, nothing awaited either
    act = flat(body(bare(source(MAC_PAGE)), "private func act(_ action: RequestAction, _ row: RequestRow) {"))
    assert "case .play: play(row)" in act and "await" not in act and "Task" not in act
    done = flat(body(bare(source(CARDS)), "struct DoneRowView: View {"))
    assert "if action == .play { onPlay() } else { onOpen() }" in done


# ----------------------------------------------------------------------------- a cancel that asked first

def test_a_cancel_that_asked_acts_on_the_row_as_it_is_now():
    # (R8's review) a question answered after its download moved on (being filed, filed) cancels nothing: the cancel is
    # of the row as the board has it then, only while it can still be cancelled - deadwax's route takes any job
    page = flat(bare(source(MAC_PAGE)))
    assert "Button(row.cancelWords.action, role: .destructive) { confirmed(row.key) }" in page
    confirmed = body(page, "private func confirmed(_ key: String) {")
    assert confirmed == ("private func confirmed(_ key: String) { confirming = nil guard let live = "
                         "RequestFilter.cancellable(key, in: requests.board) else { return } requests.cancel(live) }")
    # the page's one cancel, and the question let go as its row moves on
    assert page.count("requests.cancel(") == 1
    board = body(page, ".onChange(of: board) {")
    assert "if let asked = confirming { confirming = RequestFilter.cancellable(asked.key, in: now) }" in board
    tapped = body(page, "private func tappedCancel(_ row: RequestRow) {")
    assert "confirming = row" in tapped and "confirmed(row.key)" in tapped and "requests.cancel" not in tapped
    # the phone's ✕ the same: its one cancel, of the live row
    screen = flat(bare(source(SCREEN)))
    assert screen.count("requests.cancel(") == 1
    now = body(screen, "private func cancelNow(_ row: RequestRow) {")
    assert "guard let live = RequestFilter.cancellable(row.key, in: requests.board) else { return } requests.cancel(live)" in now
    # Core's: a job downloading or waiting, its cancel ready - nothing else
    cancellable = flat(body(bare(FILTER.read_text(encoding="utf-8")),
                            "public static func cancellable(_ key: String, in board: RequestsView) -> RequestRow? {"))
    assert "for section in [RequestSection.downloading, .waiting] {" in cancellable
    assert "return row.jobId != nil && row.cancel == .ready ? row : nil" in cancellable


# ----------------------------------------------------------------------------- the Mac's page

def test_the_macs_table_is_the_drawings():
    code = FILTER.read_text(encoding="utf-8")
    # Requests.dc.html's .cols: Album (grow), Artist 160, From 124, Progress 226, Speed 92, and the buttons' 240
    widths = re.findall(r"^\s*\.(flexible|fixed\(([0-9]+)\)),\s*// drawn: (.+)$",
                        code[code.index("public static let widths"):], re.M)[:6]
    assert [w[1] or w[0] for w in widths] == ["flexible", "160", "124", "226", "92", "240"], widths
    assert [w[2] for w in widths] == ["Requests .cols > div.grow"] + [f"Requests .cols > div width {n}" for n in range(2, 7)]
    titles = re.findall(r'case \.(\w+): return "([^"]*)"', code[code.index("public static func title(_ column"):])[:6]
    assert titles == [("album", "Album"), ("artist", "Artist"), ("from", "From"), ("progress", "Progress"),
                      ("speed", "Speed"), ("actions", "")]
    # the drawing's rows 34 tall with a 22 cover; its toolbar's fields 170 and 210
    for line in ("public static let rowHeight: Double = 34", "public static let cover: Double = 22",
                 "fit == .full ? 170 : 120    // drawn: Requests .bar .in width 1",
                 "fit == .full ? 210 : 140    // drawn: Requests .bar .in width 2"):
        assert line in code, line
    page = flat(bare(source(MAC_PAGE)))
    # the columns' strip (.cols: 24 tall, its gradient, the frame's rule, its labels 11.5 semibold, a rule after each)
    cols = mac_look.rule(".cols")
    assert (cols["height"], cols["font-size"], cols["font-weight"]) == ("24px", "11.5px", "600")
    assert ".frame(height: CGFloat(MacLook.headerHeight)) .background(MacPalette.columnsFace)" in page
    assert ".overlay(alignment: .bottom) { DWRule(colour: DWPalette.frame) }" in page
    assert "DWRule(colour: MacPalette.columnsRule, vertical: true)" in page
    # a heading (.row.grp: 26, its own ground, the label's colour) and a row (34, striped every other one, selected in
    # the selection's colours, the row line under it)
    assert ".frame(height: CGFloat(DWLook.here.groupRowHeight)) .background(MacPalette.groupRowFace)" in page
    assert "let stripes = MacTable.stripes(lines)" in page and "MacPalette.rowStripe" in page
    #? (the Mac's Row Size) 34 at Small, its drawing's - MacRowSize.requestRowHeight, View > Row Size's (test_ios_mac_rows)
    assert ".frame(height: CGFloat(rowSize.requestRowHeight))" in page
    assert ("Rectangle() .fill(DWPalette.selbg) .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))"
            in page)
    palette = (APP / "Mac" / "Look" / "MacPalette.swift").read_text(encoding="utf-8")
    for line in ("static let columnsFace = vertical(hex(0x1a1822), hex(0x131219))   // dw: .cols background",
                 "static let columnsRule = hex(0x262430)                            // dw: .cols > div border-right",
                 "static let rowStripe = rgba(255, 255, 255, 0.018)                 // dw: .row.alt background",
                 "static let groupRowFace = hex(0x100f15)                           // dw: .row.grp background",
                 "static let coverEdge = hex(0x34323c)                              // dw: .cover border"):
        assert line in palette, line
    # (R8's review) the cover: .cover's 1 px edge, a chip's corners (.cover's 3)
    cover = mac_look.rule(".cover")
    assert (cover["border"], cover["border-radius"]) == ("1px solid #34323c", "3px"), cover
    assert (".clipShape(DWCorners.chipShape) .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, "
            "lineWidth: 1))") in page
    # the Speed column is the rate the data line says, a dash for none - each row's rate counted only while it comes
    assert "Text(RequestFilter.speedText(row))" in page and ".font(Typeface.Mac.mono(.small))" in page
    # a finished row says how it ended as a chip, and how long ago beside it
    assert "DWChip(words: row.chip ?? row.progressWords ?? row.line, tone: row.lineTone == .plain ? .good : .caution)" in page


def test_nothing_in_the_macs_progress_column_draws_past_it():
    # (R8's review) "12 of 12 files · adding to your library…" and a warning's whole sentence once ran past the cell's
    # 206: every word in it is cut short in the cell now - its whole the cell's help, and in what VoiceOver hears - and
    # a done row's chip says what it means in a few words
    page = flat(bare(source(MAC_PAGE)))
    progress = body(page, "@ViewBuilder private func progressCell(_ row: RequestRow) -> some View {")
    assert ".fixedSize()" not in progress
    assert progress.count(".lineLimit(1)") == 5, "the files, a wait, a refusal, a note, when"
    assert progress.count(".help(") == 4, "each kind of row's whole words"
    # the meter keeps its least width; its words give way (the meter centred on their line, the row on their baseline -
    # test_ios_readout_rows.py)
    assert ("DWMeter(fraction: row.progress / 100) .frame(minWidth: CGFloat(RequestColumns.meterLeast)) "
            ".centredOnWords(CGFloat(Typeface.Mac.Size.base.rawValue)) "
            'Text(row.progressWords ?? "") .font(Typeface.Mac.mono(.label)) .foregroundStyle(DWPalette.t2) '
            ".lineLimit(1) .layoutPriority(1)") in progress
    # the chip (DWChip's fixed size) first, what's beside it giving way
    assert ".good : .caution) .layoutPriority(1)" in progress
    # every chip fits the cell: the words Core can say, at the chip's 11.5 semibold, with its 7 either side
    chips = set(re.findall(r'return (?:theirs[^?]*\? )?"([^"]+)"(?: : "([^"]+)")?',
                           body(core("Requests.swift"), "public static func chipWords(_ job: DownloadJob) -> String {")))
    words = {w for pair in chips for w in pair if w}
    assert words == {"In their library", "In your library", "Added to their library", "Added to your library",
                     "Not added", "You already had it", "Partly in their library", "Partly in your library",
                     "Stopped"}, words
    # (the app's fonts, 25 Nov) the Progress column's width read from Core's table (RequestColumns.widths: Artist,
    # From, Progress, Speed, the buttons), its 10 either side - a narrower column is measured, not assumed
    code = FILTER.read_text(encoding="utf-8")
    columns = [float(n) for n in re.findall(r"\.fixed\((\d+)\),", code[code.index("public static let widths"):])[:5]]
    assert len(columns) == 5, columns
    cell = columns[2] - 2 * 10
    for chip in words:
        assert estimate(chip, 11.5) + 2 * 7 <= cell, chip
    # and the whole sentence stays the row's: its help, and VoiceOver's
    assert "let said: [String?] = [row.line," in page
    spoken = flat(body(bare(FILTER.read_text(encoding="utf-8")), "public static func row(_ row: RequestRow, runs: Bool"))
    assert "case .done: said += [row.line, note]" in spoken


def estimate(words: str, size: float, weight: str = "semibold") -> float:
    """A width for `words` at `size` in Libre Franklin, measured from the bundled face (tests/ios_fonts.py, 25 Nov - it
    was 0.55 of the size a letter in Noto Sans until then): SemiBold unless said - a chip's, a segment's and a primary
    button's weight, the heaviest these words take - so from above for the 500 of a plain button too."""
    return fonts.words(words, size, weight)


def test_the_table_fits_its_page_and_the_toolbar_folds_to_every_page():
    # (R8's review) a window as it first opens (1280, beside the sidebar's 220: a page of 1060) scrolls nothing sideways
    code = FILTER.read_text(encoding="utf-8")
    look, frame = core("MacLook.swift"), core("MacFrame.swift")
    sidebar = float(re.search(r"public static let sidebarWidth: Double = (\d+)", look).group(1))
    opening = float(re.search(r"public static let openingWidth: Double = (\d+)", frame).group(1))
    smallest = float(re.search(r"public static let smallestWidth: Double = (\d+)", frame).group(1))
    panel = float(re.search(r"public static let panelWidth: Double = (\d+)", frame).group(1))
    page = opening - sidebar
    assert page == 1060
    fixed = [float(n) for n in re.findall(r"\.fixed\((\d+)\),", code[code.index("public static let widths"):])[:5]]
    least = float(re.search(r"public static let albumLeast: Double = (\d+)", code).group(1))
    assert sum(fixed) + least <= page, (sum(fixed), least)
    # the buttons column holds its widest main action and the ••• beside it, in its 10 either side: Another source with
    # two figures left, at .btn.sm's 12 with its 8 either side
    requests = core("Requests.swift")
    another = re.search(r'anotherSource\(_ left: Int\) -> String \{ "([^"]+)" \}', requests).group(1)
    another = another.replace("\\(left)", "99").replace("\\u{00B7}", "·")
    trying = re.search(r'tryingAnother = "([^"]+)"', requests).group(1).replace("\\u{2026}", "…")
    same = re.search(r'sameSource = "([^"]+)"', requests).group(1)
    small = 12.0
    button = lambda words: estimate(words, small) + 2 * 8  # noqa: E731
    more = button("•••")
    actions = fixed[4]
    assert actions == 240
    for main in (another, trying, same):
        assert button(main) + 6 + more + 2 * 10 <= actions, main
    assert button("Play") + 14 + 6 + button("Open") + 2 * 10 <= actions, "a done row's two"
    # the toolbar's three, added up: what each draws, 6 apart, 12 in either side
    title = re.search(r'public static let title = "([^"]+)"', core("ManualSearch.swift")).group(1)
    search = re.search(r'public static let search = "([^"]+)"', core("ManualSearch.swift")).group(1)
    clear = re.search(r'public static let clearDone = "([^"]+)"', requests).group(1)
    labels = re.findall(r'case \.\w+: return "(All|Active)"', code) + ["Done"]
    control = 12.5
    parts = {
        "label": estimate(title, 12),
        "search": estimate(search, control) + 2 * 11,
        "groove": 2 + 2 * 5,
        "segments": sum(estimate(w, control) + 2 * 10 for w in labels) + 2,
        "clear": estimate(clear, control) + 2 * 11,
        "popup": estimate(max(labels, key=len), control) + 6 + 8 + 2 * 11,
    }
    fields = {"full": (170.0, 210.0), "compact": (120.0, 140.0), "folded": (120.0, 140.0)}

    def toolbar(fit: str) -> float:
        artist, album = fields[fit]
        drawn = [artist, album, parts["search"]]
        if fit == "full":
            drawn = [parts["label"]] + drawn
        if fit == "folded":
            drawn += [0, parts["popup"]]
        else:
            drawn += [parts["groove"], parts["segments"], 0, parts["clear"]]
        return sum(drawn) + 6 * (len(drawn) - 1) + 2 * 12

    # as drawn in a window as it opens; narrower in the smallest window's page; folded beside a side panel's column
    # (from 1280 the panel makes room: the page is 1280 - 220 - 470 - its rule) - every control in reach on each
    assert toolbar("full") <= page
    assert toolbar("compact") <= smallest - sidebar, toolbar("compact")
    assert toolbar("folded") <= opening - sidebar - panel - 1, toolbar("folded")
    assert toolbar("full") > smallest - sidebar, "so the smallest window's page does fold"
    # the numbers are Core's, the page draws the first that fits
    tools = flat(bare(code[code.index("public enum RequestTools"):]))
    assert "fit == .full ? 170 : 120" in tools and "fit == .full ? 210 : 140" in tools
    assert "public static func labelled(_ fit: Fit) -> Bool { fit == .full }" in tools
    assert "public static func folds(_ fit: Fit) -> Bool { fit == .folded }" in tools


def test_the_macs_toolbar_and_status_bar():
    page = flat(bare(source(MAC_PAGE)))
    tools = body(page, "private func tools(_ board: RequestsView) -> some View {")
    assert ("ViewThatFits(in: .horizontal) { toolbar(board, .full) toolbar(board, .compact) toolbar(board, .folded) }"
            in tools)
    bar = body(page, "private func toolbar(_ board: RequestsView, _ fit: RequestTools.Fit) -> some View {")
    # Search Soulseek in the bar, with Get albums: Artist, Album, Search
    assert bar.startswith("private func toolbar(_ board: RequestsView, _ fit: RequestTools.Fit) -> some View { "
                          "HStack(spacing: 6) { if server.access.can(.request) { if RequestTools.labelled(fit) {")
    for part in ("field(ManualSearch.artistField, text: $artist, .artist, width: RequestTools.artistField(fit))",
                 "field(ManualSearch.albumField, text: $album, .album, width: RequestTools.albumField(fit))",
                 "Button(ManualSearch.search) { search() } .buttonStyle(DWButtonStyle()) .disabled(!searchable)",
                 "if !RequestTools.folds(fit) { MacGroove() }",
                 "if RequestTools.folds(fit) { Spacer(minLength: 0) shownMenu(board) } else { "
                 "DWSegmented(options: RequestFilter.allCases, words: { (option: RequestFilter) -> String in option.label }, "
                 "chosen: $filter, spoken: RequestFilter.spoken, large: true) Spacer(minLength: 0) "
                 "Button(RequestWords.clearDone) { clear() } .buttonStyle(DWButtonStyle()) .disabled(!clearable(board)) }"):
        assert part in bar, part
    # folded: All, Active and Done, and Clear done under them, in one pop-up named for what the table shows
    menu = body(page, "private func shownMenu(_ board: RequestsView) -> some View {")
    for part in ("DWPopUp(words: filter.label) {", "Picker(RequestFilter.spoken, selection: $filter) {",
                 ".pickerStyle(.inline) Divider() Button(RequestWords.clearDone) { clear() } .disabled(!clearable(board))",
                 ".accessibilityLabel(RequestFilter.spoken) .accessibilityValue(filter.label)"):
        assert part in menu, part
    assert "board.clearable && reachability.online" in body(page, "private func clearable(_ board: RequestsView) -> Bool {")
    # the search is the words as typed, a new one each time; the Get is a card's, never the bar's
    search = body(page, "private func search() {")
    assert "guard searchable, getting == nil else { return }" in search
    assert "GetRelease.manual(artist: artist, album: album)" in search and "search: SourcesSearch()" in search
    assert "download" not in search and "enqueue" not in search
    assert "reachability.online && ManualSearch.canSearch(artist: artist, album: album)" in page
    # Choose a source over the page, its search let go with the sheet - GroupView's way
    assert ("if next == nil { getting?.search.close() }" in page and "SourcesSheet(request: request) {" in page
            and ".macSheet()" in page)
    # Cancel asks first with Confirm before cancelling on; the dialog's Keep it is Return's
    cancel = body(page, "private func tappedCancel(_ row: RequestRow) {")
    assert "ConfirmCancel.read(UserDefaults.standard.string(forKey: ConfirmCancel.storageKey))" in cancel
    assert "Button(RequestWords.keepIt, role: .cancel) {} .returnCancels()" in page
    # the status bar: the counts and the speed summed, Core's - (the app's fonts, 25 Nov) the speed in the readout face,
    # as it ticks (test_ios_palette.py's TICKING)
    assert (".macStatus(MacStatusItems.Items(leading: reachability.online ? RequestFilter.status(board) : [], "
            "readouts: [RequestWords.speed(RequestFilter.speed(board))]))") in page


def test_the_toolbars_fields_take_tab_and_return_as_the_phones_form_does():
    # (R8's review) Return in Artist moves to Album, Return in Album searches, Tab between them - Platform's one helper
    page = flat(bare(source(MAC_PAGE)))
    assert "private static let order: [Field] = [.artist, .album]" in page
    field = body(page, "private func field(_ prompt: String, text: Binding<String>, _ which: Field, width: Double)")
    assert (".focused($focused, equals: which) .tabs($focused, in: Self.order) .focusEffectDisabled() "
            ".onSubmit { submitted(which) }") in field
    # DWField's look: the well, its edge the accent's while it has the cursor, a tap in the well puts the cursor there
    assert "DWWell(focused: focused == which)" in field and ".onTapGesture { focused = which }" in field
    assert ".font(Typeface.Look.text(.field)) .foregroundStyle(DWPalette.fieldText)" in field
    assert ".lookHeight(DWLook.here.fieldHeight)" in field
    submitted = body(page, "private func submitted(_ which: Field) {")
    assert submitted == "private func submitted(_ which: Field) { if which == .artist { focused = .album } else { search() } }"
    assert "keyboardShortcut" not in page and "onKeyPress" not in page


def test_the_macs_keys_move_through_the_rows_and_return_opens_one_done():
    # (R8's review) ↑ ↓ Home End move the selection (MacTable.moved), Return opens the row selected as a double click
    # does (MacTable.returned) - through Platform's helper, on the table while it has the keyboard
    page = flat(bare(source(MAC_PAGE)))
    table = body(page, "private func table(_ board: RequestsView) -> some View {")
    assert (".focusable() .focused($tableFocused) .focusEffectDisabled() .listKeys { (key: ListKey) -> KeyPress.Result in "
            "pressed(key, rows: keys, board: board) }") in table
    assert "let keys = MacTable.rows(lines)" in table
    assert "if let now { proxy.scrollTo(MacTable.Line<String>.row(now)) }" in table
    pressed = body(page, "private func pressed(_ key: ListKey, rows: [String], board: RequestsView) -> KeyPress.Result {")
    for part in ("case .up: move = .up", "case .down: move = .down", "case .home: move = .home", "case .end: move = .end",
                 "guard let opened = MacTable.returned(selected, in: rows), let row = Self.byKey(board)[opened], "
                 "row.opens != nil else { return .ignored } requests.open(row) return .handled",
                 "selected = MacTable.moved(selected, move, in: rows)"):
        assert part in pressed, part
    assert "tableFocused = true" in body(page, "private func clicked(_ row: RequestRow, count: Int) {")
    # a selection a filter hides is let go
    assert ("selected = MacTable.kept(selected, in: MacTable.rows(now.lines(requests.board)))"
            in body(page, ".onChange(of: filter) {"))
    # Platform's: the Mac's keys, nothing on the iPhone
    platform = (APP / "Shared" / "Platform.swift").read_text(encoding="utf-8")
    mac, phone = platform.split("\n#else\n")
    assert "onKeyPress(keys: [.upArrow, .downArrow, .home, .end, .return])" in mac
    assert re.search(r"func listKeys\(_ press: @escaping \(ListKey\) -> KeyPress\.Result\) -> some View \{\s*self\s*\}",
                     phone)
    assert "enum ListKey: Sendable, Hashable {\n    case up, down, home, end, open\n}" in platform


def test_a_row_is_one_element_for_voiceover_its_actions_its_buttons():
    # (R8's review, plan 3.3) the Mac's row and each phone card are one element: everything they show, and their actions
    # named as their buttons are - Cancel or Leave, Another source, Same source again, Play, Open
    page = flat(bare(source(MAC_PAGE)))
    row = body(page, "private func rowLine(_ row: RequestRow, widths: [CGFloat], striped: Bool) -> some View {")
    assert ("let offered = RequestAction.offered(row, gets: server.access.can(.request), online: reachability.online)"
            in row)
    assert (".accessibilityElement(children: .ignore) .accessibilityLabel(RequestSpoken.row(row, runs: "
            "server.access.seesDetail, note: openNote(row))) .accessibilityAddTraits(on ? .isSelected : []) "
            ".accessibilityActions { ForEach(offered, id: \\.self) { (action: RequestAction) in "
            "Button(action.words(row)) { act(action, row) } } }") in row
    assert ".accessibilityElement(children: .contain)" not in page
    # the right-click holds the same, and the ••• the rest
    assert (".macContextMenu { ForEach(offered, id: \\.self) { (action: RequestAction) in Button(action.words(row)) "
            "{ act(action, row) } } }") in row
    buttons = body(page, "private func buttons(_ row: RequestRow) -> some View {")
    assert "ForEach(RequestAction.buttons(row, gets: gets), id: \\.self)" in buttons
    assert "let more = RequestAction.more(row, gets: gets)" in buttons and "if !more.isEmpty { Menu {" in buttons
    act = body(page, "private func act(_ action: RequestAction, _ row: RequestRow) {")
    assert act.count("case .") == 5
    # who asked and which try: the album's help, and Leave's reason on its button
    assert ".help(RequestSpoken.help(row))" in body(page, "private func albumCell(_ row: RequestRow) -> some View {")
    assert ".help([RequestWords.cancelLabel(row), row.askedBy].compactMap { $0 }.joined(separator: " in page
    # the phone's three cards
    cards = flat(bare(source(CARDS)))
    job = body(cards, "struct JobCardView: View {")
    assert (".accessibilityElement(children: .ignore) .accessibilityLabel(RequestSpoken.card(row, runs: false, gets: true)) "
            ".accessibilityActions { ForEach(RequestAction.offered(row, gets: true, online: true), id: \\.self)") in job
    # the question, while it asks, its own group under the card's words
    assert job.index(".accessibilityElement(children: .ignore)") < job.index("if asking { CancelQuestion(")
    attention = body(cards, "struct AttentionCardView: View {")
    assert (".accessibilityElement(children: .ignore) .accessibilityLabel(RequestSpoken.card(row, runs: runs, gets: gets))"
            in attention)
    assert "ForEach(RequestAction.offered(row, gets: gets, online: true), id: \\.self)" in attention
    assert "Button(action.words(row)) { onRetry(action == .askAgain) }" in attention
    done = body(cards, "struct DoneRowView: View {")
    assert (".accessibilityElement(children: .ignore) .accessibilityLabel(RequestSpoken.card(row, runs: runs, gets: true, "
            "filed: filed, note: note))") in done
    assert ".accessibilityAction { if row.opens != nil { onOpen() } }" in done
    assert ".accessibilityElement(children: .combine)" not in cards


def test_what_no_route_gives_is_left_out():
    page = kept(source(MAC_PAGE))
    # Other sources on a download (James: "just leave it out"), the Files, Other sources and Log tabs, slskd's state
    for words in (r"Other sources", r"\bFiles\b", r"\bLog\b", r"slskd connected", r"\bMacFolderTabs\b"):
        assert not re.search(words, page), words
    # and the old phone page is the Mac's no more
    assert "MacRequestsPage()" in bare(source("Mac/Requests/MacRequests.swift"))


# ----------------------------------------------------------------------------- tokens only

PHONE_FONT = re.compile(r"Typeface\.(?:Phone\.(?:text|mono)|symbol)\(")


def test_requests_draws_no_value_of_its_own():
    left = []
    for name in (CARDS, SCREEN, MAC_PAGE, METER):
        code = bare(source(name))
        for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                              ("the iPhone's old palette", r"(?<![\w.])Palette\."),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b"),
                              ("a font of its own", r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\.monospaced")):
            if re.search(pattern, code):
                left.append(f"{name}: {what}")
        if mac_look.NAMED_COLOUR.search(code):
            left.append(f"{name}: a named colour ({mac_look.NAMED_COLOUR.search(code).group(0)})")
        fonts = mac_look.font_arguments(code)
        if name == MAC_PAGE:
            left += [f"{name}: .font({f})" for f in fonts if not mac_look.MAC_FONT.match(f)]
        else:
            # the phone's: Typeface.Phone's sizes - and the heading's 15 (.row.grp), iOS's subheadline, which
            # Typeface.Phone has no size for
            left += [f"{name}: .font({f})" for f in fonts
                     if not PHONE_FONT.match(f) and f != "Typeface.subheadline.weight(.semibold)"]
    assert not left, left
    # the heading alone takes the subheadline; the phone's corners are Corners' art, square
    assert bare(source(SCREEN)).count("Typeface.subheadline") == 1
    assert re.findall(r"(?<!DW)Corners\.\w+", bare(source(CARDS))) == ["Corners.artShape"]
    assert not re.findall(r"(?<!DW)Corners\.\w+", bare(source(SCREEN)))


def test_up_next_is_the_queue_in_what_requests_says():
    # (the redesign) "Queue", never "Up Next", in anything a person reads here
    for name in (CARDS, SCREEN, MAC_PAGE):
        code = kept(source(name))
        assert "Up Next" not in code, name
