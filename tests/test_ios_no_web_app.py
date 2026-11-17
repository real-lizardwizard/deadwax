"""
Nothing in the iPhone app takes you to the web app (Phase 8, slice 12 - notes/ios-specs/phase8-managing.md 11;
notes/ios.md "No way out to the web app"). James, 2026-11-16: "nothing in the app should take you to the web app".
Slices 1-11 made every managing tool the app's own; slice 12 took out what was left of Phase 7's way out (WebAppRow,
`OpenURLAction.webApp`, Core's web-app addresses and Safari words) - and this keeps it out, by CI rather than by memory.

It reads every Swift source of the app (ios/App, and DeadwaxKit's Sources) with its comments blanked and refuses:
- an `openURL(...)` or `Link(...)` outside the allowlist below - three links out, each keyed by its file and what it
  opens (never a line number), each to a site that isn't deadwax's; the environment's `openURL` read anywhere else;
- any other way out to a browser - `OpenURLAction`, `UIApplication.shared.open`, `SFSafariViewController`, a web view,
  a sign-in web session, a markdown link in a string the app draws;
- anything opened or shared outside the app that is built from deadwax's own address (the server's origin) - even on
  the allowlist.
The matcher is held to made-up sources first, so a planted way out is shown to fail.
"""

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
KIT = IOS / "DeadwaxKit" / "Sources"
CORE = KIT / "DeadwaxCore"

#? the links out the app keeps, by file (under ios/App) and what each opens - the destination as written, or what the
#? name it opens was bound to: each a site that isn't deadwax's (test_each_way_out_goes_to_a_site_that_isnt_deadwax)
ALLOWED = {
    ("Album/AlbumInfoView.swift", "row.link"):
        "Album info's This pressing / Every pressing on MusicBrainz - AlbumInfo.page's https://musicbrainz.org/",
    ("EQ/EQProfileScreen.swift", "URL(string: EQWords.Profile.gitHubAddress)"):
        "the EQ's AutoEq on GitHub, under a correction's profile",
    ("Manage/PeopleScreen.swift", "URL(string: People.sharingDoc)"):
        "People's Sharing deadwax guide, shown when deadwax says People can't work (logins off)",
}

#? where the allowlist's Core addresses come from: file, name, and the whole address
ADDRESSES = {
    "EQWords.Profile.gitHubAddress": ("EQWords.swift", "gitHubAddress", "https://github.com/jaakkopasanen/AutoEq"),
    "People.sharingDoc": ("People.swift", "sharingDoc",
                          "https://github.com/real-lizardwizard/deadwax/blob/main/docs/sharing.md"),
}

#? ways out to a browser that nothing in the app may use at all
NEVER = {
    "OpenURLAction": r"\bOpenURLAction\b",
    "UIApplication's open": r"\b(?:UIApplication|shared|application)\s*\.\s*open(?:URL)?\s*\(",
    "SFSafariViewController": r"\bSFSafariViewController\b|\bimport\s+SafariServices\b",
    "a web view": r"\bWKWebView\b|\bWebView\b|\bimport\s+WebKit\b",
    "a sign-in web session": r"\bASWebAuthenticationSession\b",
    "markdown parsed into a link": r"AttributedString\(\s*markdown:",
}

#? what a URL built from deadwax's own address names on its way: the phone's address, its base, the origin, the web app
ORIGIN = re.compile(r"\b(?:ServerAddress|address|base|origin|appPath|absoluteString)\b|/player|\bserver\s*\.")
#? a markdown link in a string literal: SwiftUI's Text draws a literal's [words](address) as a link that opens
MARKDOWN_LINK = re.compile(r"\]\(\s*(?:https?|mailto|deadwax)\s*:", re.IGNORECASE)


# ---------------------------------------------------------------------------- reading Swift

def views(text: str) -> tuple[str, str]:
    """Two views of Swift source, each the same length with the same lines, so an offset in one is the source's:
    `code`, its comments blanked; and `bare`, its string literals' words blanked too (the quotes and any interpolated
    code kept) - where a use is looked for, so a word in a string or a comment is never one."""
    code, bare = list(text), list(text)
    n = len(text)

    def blank(into: list, start: int, end: int) -> None:
        for k in range(start, end):
            if into[k] != "\n":
                into[k] = " "

    def comment_end(i: int) -> int:
        depth = 0
        while i < n:
            if text.startswith("/*", i):
                depth, i = depth + 1, i + 2
            elif text.startswith("*/", i):
                depth, i = depth - 1, i + 2
                if depth == 0:
                    return i
            else:
                i += 1
        return n

    def literal(i: int) -> int:
        hashes = len(text[i:]) - len(text[i:].lstrip("#"))
        start = i + hashes
        quote = '"""' if text.startswith('"""', start) else '"'
        close, interpolation = quote + "#" * hashes, "\\" + "#" * hashes + "("
        j = segment = start + len(quote)
        while j < n:
            if text.startswith(close, j):
                blank(bare, segment, j)
                return j + len(close)
            if text.startswith(interpolation, j):
                blank(bare, segment, j)
                j = segment = code_from(j + len(interpolation), inside=True)
                continue
            if not hashes and text[j] == "\\":
                j += 2
                continue
            if quote == '"' and text[j] == "\n":
                break
            j += 1
        blank(bare, segment, j)
        return j

    def code_from(i: int, inside: bool = False) -> int:
        depth = 0
        while i < n:
            if text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end < 0 else end
                blank(code, i, end)
                blank(bare, i, end)
                i = end
            elif text.startswith("/*", i):
                end = comment_end(i)
                blank(code, i, end)
                blank(bare, i, end)
                i = end
            elif text[i] == '"' or (text[i] == "#" and re.match(r'#+"', text[i:i + 8])):
                i = literal(i)
            elif inside and text[i] == "(":
                depth, i = depth + 1, i + 1
            elif inside and text[i] == ")":
                if depth == 0:
                    return i + 1
                depth, i = depth - 1, i + 1
            else:
                i += 1
        return n

    code_from(0)
    return "".join(code), "".join(bare)


def closing(bare: str, opening: int) -> int:
    """The offset of the bracket that closes the one at `opening` (the bare view: no bracket in a string counts)."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    for k in range(opening, len(bare)):
        if bare[k] in pairs:
            stack.append(pairs[bare[k]])
        elif stack and bare[k] == stack[-1]:
            stack.pop()
            if not stack:
                return k
    raise AssertionError("unbalanced brackets")


def arguments(code: str, bare: str, opening: int) -> list[tuple[str | None, str]]:
    """A call's arguments at the top level, as (label, the argument as written) - the `(` at `opening`."""
    end = closing(bare, opening)
    out, depth, start = [], 0, opening + 1
    for k in range(opening + 1, end + 1):
        if k == end or (bare[k] == "," and depth == 0):
            raw = " ".join(code[start:k].split())
            label = re.match(r"^([A-Za-z_]\w*)\s*:\s*(?!:)", raw)
            out.append((label.group(1), raw[label.end():]) if label else (None, raw))
            start = k + 1
        elif bare[k] in "([{":
            depth += 1
        elif bare[k] in ")]}":
            depth -= 1
    return [arg for arg in out if arg[1]]


def resolved(code: str, at: int, expression: str) -> str:
    """What `expression` opens: as written - or, for a bare name, what it was last bound to before `at`
    (`let link = row.link`, `if let address = URL(string: ...) {`, `guard let link = row.link else`)."""
    if not re.fullmatch(r"[A-Za-z_]\w*", expression):
        return expression
    bound = [found for found in re.finditer(rf"\b(?:let|var)\s+{expression}\s*(?::[^=\n]*)?=(?!=)\s*([^\n]*)", code)
             if found.start() < at]
    if not bound:
        return expression
    rhs = bound[-1].group(1)
    rhs = re.sub(r"\s+else\b.*$", "", rhs)
    rhs = re.sub(r"\s*\{\s*$", "", rhs).rstrip(" ,")
    return " ".join(rhs.split())


def ways_out(text: str) -> list[tuple[str, int, str]]:
    """Every link out a Swift source makes: (what - "openURL", "Link" or "ShareLink" -, its line, what it opens)."""
    code, bare = views(text)
    found = []
    for match in re.finditer(r"(?<![\w.])openURL\s*\(", bare):
        args = arguments(code, bare, match.end() - 1)
        target = args[0][1] if args else ""
        found.append(("openURL", match.start(), resolved(code, match.start(), target)))
    for match in re.finditer(r"(?<![\w.])(Link|ShareLink)\s*\(", bare):
        args = arguments(code, bare, match.end() - 1)
        label = "destination" if match.group(1) == "Link" else "item"
        target = next((value for name, value in args if name == label), "")
        found.append((match.group(1), match.start(), resolved(code, match.start(), target)))
    return [(kind, text.count("\n", 0, at) + 1, target) for kind, at, target in sorted(found, key=lambda use: use[1])]


def refusals(name: str, text: str) -> list[str]:
    """What's wrong with one Swift source (`name` relative to ios/App, or a DeadwaxKit path): each way out to a browser
    the allowlist doesn't hold, anything deadwax's own address is opened or shared by, any way out NEVER names, and a
    markdown link in a string."""
    code, bare = views(text)
    wrong = []

    def line(at: int) -> int:
        return text.count("\n", 0, at) + 1

    uses = ways_out(text)
    for kind, number, target in uses:
        if ORIGIN.search(target):
            wrong.append(f"{name}:{number} {kind} opens what deadwax's own address makes: {target}")
        elif kind != "ShareLink" and (name, target) not in ALLOWED:
            wrong.append(f"{name}:{number} {kind} opens {target or 'something'} - not one of the app's links out")
    #? openURL itself: the environment's read, and its name declared, only where an allowed openURL is called; called,
    #? ways_out has it; anything else done with it (Phase 7's openURL.webApp, someone else's openURL) refused
    allowed_here = any(kind == "openURL" and (name, target) in ALLOWED for kind, _, target in uses)
    for match in re.finditer(r"\bopenURL\b", bare):
        before, after = bare[:match.start()].rstrip(), bare[match.end():].lstrip()
        if re.search(r"\\\s*\.$", before) or re.search(r"\b(?:var|let)$", before):
            if not allowed_here:
                wrong.append(f"{name}:{line(match.start())} has the environment's openURL, and no link out of its own")
        elif before.endswith("."):
            wrong.append(f"{name}:{line(match.start())} calls another openURL")
        elif not after.startswith("("):
            wrong.append(f"{name}:{line(match.start())} does something with openURL other than call it")
    for what, pattern in NEVER.items():
        for match in re.finditer(pattern, bare):
            wrong.append(f"{name}:{line(match.start())} {what}")
    #? the words of every string literal, and nothing else (where the bare view blanked what the code view kept)
    words = "".join(kept if kept != blanked else (" " if kept != "\n" else "\n") for kept, blanked in zip(code, bare))
    for number, said in enumerate(words.splitlines(), 1):
        if MARKDOWN_LINK.search(said):
            wrong.append(f"{name}:{number} a markdown link in a string: {said.strip()}")
    return wrong


def sources() -> dict[str, str]:
    """Every Swift source of the app, by its name here: under ios/App relative to it, DeadwaxKit's from ios/."""
    found = {}
    for path in sorted(APP.rglob("*.swift")):
        found[path.relative_to(APP).as_posix()] = path.read_text(encoding="utf-8")
    for path in sorted(KIT.rglob("*.swift")):
        found[path.relative_to(IOS).as_posix()] = path.read_text(encoding="utf-8")
    return found


# ---------------------------------------------------------------------------- the matcher, on made-up sources

#? Phase 7's way out as it was until slice 12 (ios/App/You/ManageSection.swift at e879995), cut down
PHASE_7 = """
extension OpenURLAction {
    @MainActor
    func webApp(_ url: URL, player: PlayerModel) {
        self(url) { (accepted: Bool) in
            guard let words = Managing.notice(opened: accepted) else { return }
            Task { @MainActor in player.say(words) }
        }
    }
}

struct WebAppRow: View {
    let url: URL
    @Environment(\\.openURL) private var openURL
    var body: some View {
        Button {
            openURL.webApp(url, player: player)
        } label: { Text(label) }
        .accessibilityHint(ManagingWords.opensInSafari)
    }
}
"""


def test_the_matcher_refuses_a_planted_way_out():
    #? each made-up source, and words of what it's refused for
    planted = {
        "a bare openURL": ("struct V: View {\n @Environment(\\.openURL) var openURL\n var body: some View { "
                           "Button(\"x\") { openURL(URL(string: \"https://example.org\")!) } }\n}",
                           'openURL opens URL(string: "https://example.org")!'),
        "a Link": ('Link("Help", destination: URL(string: "https://example.org/help")!)', "not one of the app's"),
        "a Link with only its destination": ("Link(destination: help) { Text(\"Help\") }", "Link opens help"),
        "the web app's address": ("let url = URL(string: server.address!.base.absoluteString + \"/player/#/you\")!\n"
                                  "openURL(url)", "deadwax's own address"),
        "Managing.url, as Phase 7 made it": ("guard let url = Managing.url(.queue, at: server.address) else { return }\n"
                                             "openURL(url)", "deadwax's own address"),
        "Phase 7's row": (PHASE_7, "OpenURLAction"),
        "Phase 7's row, without its extension": ("openURL.webApp(url, player: player)", "other than call it"),
        "UIApplication": ("UIApplication.shared.open(url)", "UIApplication's open"),
        "UIApplication's old openURL": ("UIApplication.shared.openURL(url)", "calls another openURL"),
        "openURL handed on": ("let open = openURL\nopen(url)", "other than call it"),
        "Safari's view": ("import SafariServices\nlet safari = SFSafariViewController(url: url)",
                          "SFSafariViewController"),
        "a web view": ("import WebKit\nlet view = WKWebView()", "a web view"),
        "SwiftUI's web view": ("WebView(url: url)", "a web view"),
        "a markdown link": ('Text("Read [the guide](https://example.org) first")', "a markdown link"),
        "a shared address of deadwax's": ("ShareLink(item: server.address!.base)", "deadwax's own address"),
        "an openURL handler": (".environment(\\.openURL, OpenURLAction { _ in .handled })", "OpenURLAction"),
    }
    for what, (text, reason) in planted.items():
        said = refusals("Library/Planted.swift", text)
        assert any(reason in line for line in said), f"{what}: {said}"
    # Phase 7's row reads the environment's openURL with no link out of its own, and does more than call it
    said = " ".join(refusals("You/ManageSection.swift", PHASE_7))
    assert "has the environment's openURL" in said and "other than call it" in said
    # an allowed link's own expression in another file is refused there
    said = refusals("Library/Planted.swift", "Link(People.sharing, destination: URL(string: People.sharingDoc)!)")
    assert any("not one of the app's links out" in line for line in said), said
    # and in its own file, opened from deadwax's address, it is refused too
    said = refusals("Manage/PeopleScreen.swift",
                    "let guide = URL(string: People.origin(server.address))\nLink(People.sharing, destination: guide)")
    assert any("deadwax's own address" in line for line in said), said


def test_the_matcher_passes_what_isnt_a_way_out():
    benign = "\n".join([
        "/// opens in Safari (openURL), and Link(destination:) in a comment",
        "// openURL(webApp) - a line comment",
        "/* a block /* nested */ openURL(x) */",
        'let words = "openURL(x) and Link(\\"a\\", destination: b) in a string"',
        'let raw = #"Link("x", destination: y) openURL(z)"#',
        'let multi = """\n  openURL(a)\n  Link(b)\n  """',
        "NavigationLink(value: AppRoute.people) { Text(\"People\") }",
        "EQLink(route: .now) { Text(\"EQ\") }",
        "creditLink(name) { open() }",
        "updateLink()",
        "ShareLink(item: url) { Text(action) }",
        "ShareLink(item: EQExportFile(setting: setting))",
        ".onOpenURL { (url: URL) -> Void in shared(url) }",
        "navigation.open(.album(route))",
        'Text("\\(name) - [1](2) is not a link")',
        'let interpolated = "\\(flag ? "openURL(a)" : "b")"',
    ])
    assert refusals("Library/Benign.swift", benign) == []
    # the three allowed, each in its own file and opening what the allowlist says
    album = ("@Environment(\\.openURL) private var openURL\n"
             "private func open(_ row: AlbumInfoRow) {\n guard let link = row.link else { return }\n"
             " openURL(link) { (accepted: Bool) in }\n}")
    assert refusals("Album/AlbumInfoView.swift", album) == []
    assert ways_out(album) == [("openURL", 4, "row.link")]
    eq = ("if let address = URL(string: EQWords.Profile.gitHubAddress) {\n"
          "    Link(EQWords.Profile.gitHub, destination: address)\n}")
    assert refusals("EQ/EQProfileScreen.swift", eq) == []
    people = ("if !state.on, let guide = URL(string: People.sharingDoc) {\n"
              "    Link(People.sharing, destination: guide)\n}")
    assert refusals("Manage/PeopleScreen.swift", people) == []


# ---------------------------------------------------------------------------- the app as it is

def test_nothing_in_the_app_opens_the_web_app():
    wrong, kept = [], set()
    for name, text in sources().items():
        wrong += refusals(name, text)
        kept |= {(name, target) for kind, _, target in ways_out(text) if kind != "ShareLink"}
    assert not wrong, "\n".join(wrong)
    # and each link out the allowlist keeps is there - an entry nothing uses is taken out with it
    assert kept == set(ALLOWED), sorted(kept ^ set(ALLOWED))


def test_each_way_out_goes_to_a_site_that_isnt_deadwax():
    for name, (file, constant, address) in ADDRESSES.items():
        code, _ = views((CORE / file).read_text(encoding="utf-8"))
        assert re.findall(rf"\bstatic let {constant} = \"([^\"]*)\"", code) == [address], name
        assert address.startswith("https://") and not ORIGIN.search(address.split("://", 1)[1]), name
    # Album info's links are AlbumInfo.page's alone: musicbrainz.org, an id's page, made nowhere else
    code, bare = views((CORE / "AlbumInfo.swift").read_text(encoding="utf-8"))
    page = code[code.index("static func page(_ kind: String, _ id: String) -> URL? {"):]
    page = page[:page.index("\n    }\n")]
    assert 'return URL(string: "https://musicbrainz.org/\\(kind)/\\(id.lowercased())")' in page
    assert not ORIGIN.search(page)
    links = re.findall(r"AlbumInfoRow\([^\n]*\blink:\s*([^)\n]+)\)", code)
    assert links == ["url", "url"], links
    assert len(re.findall(r"let url = page\(\"release(?:-group)?\", (?:release|group)\)", code)) == 2
    # nothing in the app sets a row's link of its own (Core's only is AlbumInfoRow's init)
    assert len(re.findall(r"\.link\s*=(?!=)", bare)) == 1 and "self.link = link" in bare
    for name, text in sources().items():
        if not name.startswith("DeadwaxKit/"):
            assert not re.search(r"\.link\s*=(?!=)", views(text)[1]), name


def test_the_web_apps_way_out_is_gone():
    # Core: Managing has no address of the web app's, nor the words of a row that opened it
    managing, bare = views((CORE / "Managing.swift").read_text(encoding="utf-8"))
    for gone in ("appPath", "func fragment(", "albumFragment", "youFragment", "func url(", "albumURL", "youURL",
                 "func notice(", "editLine", "editInWebApp", "changePasswordLine", "opensInSafari", "static let opens ",
                 "othersOpen", "signIn", "static let offline", "notOpened", "func footer(", "outSymbol",
                 "safariSymbol", "var native"):
        assert gone not in bare, gone
    assert "Safari" not in managing and "web app" not in managing
    # the App: Phase 7's row, the openURL extension (and its pause of the player), the album menu's web Edit
    for name, text in sources().items():
        bare = views(text)[1]
        for gone in ("WebAppRow", "webApp(", "webEdit", "Managing.url(", "Managing.albumURL(", "Managing.youURL(",
                     "Managing.notice("):
            assert gone not in bare, f"{name}: {gone}"
    # no Swift source builds a URL into the web app's page
    for name, text in sources().items():
        for literal in re.findall(r'"(?:[^"\\\n]|\\.)*"', views(text)[0]):
            assert not re.match(r'"/player/?(?:#|")', literal), f"{name}: {literal}"
    # the vectors keep only what Manage shows - not where the web app opened it
    fixture = json.loads((IOS / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "managing"
                          / "managing-vectors.json").read_text(encoding="utf-8"))
    assert "addresses" not in fixture and "albums" not in fixture
    assert not any("appRoutes" in source or "openManagingPage" in source for source in fixture["made_from"])
    assert {"words", "me", "sets"} <= set(fixture)
    exporter = (IOS / "scripts" / "export-managing-vectors.cjs").read_text(encoding="utf-8")
    assert "appRoutes" not in exporter and "formatRoute" not in exporter and "parseHash" not in exporter
