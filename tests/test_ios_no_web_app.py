"""
Nothing in the iPhone app takes you to the web app (Phase 8, slice 12 - notes/ios-specs/phase8-managing.md 11;
notes/ios.md "No way out to the web app"). James, 2026-11-16: "nothing in the app should take you to the web app".
Slices 1-11 made every managing tool the app's own; slice 12 took out what was left of Phase 7's way out (WebAppRow,
`OpenURLAction.webApp`, Core's web-app addresses and Safari words) - and this keeps it out, by CI rather than by memory.

It reads every Swift source of the app (ios/App, and DeadwaxKit's Sources) with its comments, string literals and
`#/.../#` regex literals blanked - a source it can't read to its end (a literal or comment that never closes) is refused
whole - and in each refuses:
- a call of `openURL`, `Link` or `ShareLink` (`Link` spelt `SwiftUI.Link`, `Link<...>` or `Link.init` too) whose file
  and what it opens (or, for ShareLink, shares) aren't on ALLOWED or SHARED below - keyed by what's written, never a
  line number - and any other mention of `Link` or `ShareLink`;
- anything one of those opens or shares that names deadwax's own address on its way (ORIGIN) - on the lists or not;
- the name `openURL` used for anything but such a call, and the environment's openURL read anywhere but once, as
  `openURL`, in a file whose own openURL call is on ALLOWED;
- UIApplication.shared held under a name (but DownloadModel's `application`), `open` called on what holds it, and any
  `open(..., options:)` (a scene's open or UIApplication's);
- what NEVER names - OpenURLAction, the environment's openURL set, Safari's view, a web view, a sign-in web session,
  the share sheet, markdown or a LocalizedStringKey made at run time, a link attribute;
- an attributed string given a link (`.link(...)` called on something, `.link =` set, `.link:` but as a case), and an
  argument labelled `link:` outside Core's AlbumInfo.swift - the one maker of Album info's rows' links;
- in the words of a string literal: a markdown link to an address, its address given apart, an autolink; and in
  ios/App's literals any address at all, but the one ALLOWED_WORDS keeps.
It holds the reading itself to two facts: ios/App is built in Swift 5 mode, where `/.../` is no regex literal (only
`#/.../#`, which it reads); and DeadwaxKit imports no UI framework, so Core - Swift 6, where `/.../` is one - has no way
out to write. The matcher is held to made-up sources first, so a planted way out is shown to fail.
"""

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
KIT = IOS / "DeadwaxKit" / "Sources"
CORE = KIT / "DeadwaxCore"

#? the one maker of Album info's links, and the one holder of UIApplication.shared, as sources() names them
ALBUM_INFO = "DeadwaxKit/Sources/DeadwaxCore/AlbumInfo.swift"
DOWNLOAD_MODEL = "Downloads/DownloadModel.swift"

#? the links out the app keeps, by file (under ios/App) and what each opens - the destination as written, or what the
#? name it opens was bound to: each a site that isn't deadwax's (test_each_way_out_goes_to_a_site_that_isnt_deadwax)
ALLOWED = {
    ("Album/AlbumInfoView.swift", "row.link"):
        "Album info's This pressing / Every pressing on MusicBrainz - AlbumInfo.page's https://musicbrainz.org/",
    ("EQ/EQProfileScreen.swift", "URL(string: EQWords.Profile.gitHubAddress)"):
        "the EQ's AutoEq on GitHub, under a correction's profile",
    ("Manage/PeopleScreen.swift", "URL(string: People.sharingDoc)"):
        "People's Sharing deadwax guide on GitHub, shown when logins are turned off on deadwax with the app open",
    ("Artist/TopSongsSection.swift", "LastfmLink.url(lastfmPage)"):
        "Top Songs' From Last.fm - the artist's page on last.fm (LastfmLink: https on last.fm only, as deadwax "
        "passes it on)",
    ("Shared/AboutSection.swift", "AboutBlock.url(drawn.paragraph)"):
        "(Last.fm, slice A4) About's More on Last.fm or From Wikipedia - the artist's or the album's page there, its "
        "Link and VoiceOver's action (AboutBlock.url: https on last.fm, or on en.wikipedia.org, only)",
}

#? what the app shares (ShareLink's item), the same way: each a file or words made on the phone, none an address
SHARED = {
    ("EQ/EQExport.swift", "file(item.whole)"):
        "the EQ's Export... - The Whole Curve or The Correction Alone (on a Mac Share the Whole Curve or Share the "
        "Correction Alone), a file made on the device",
    ("You/DebugView.swift", "url"): "Debug's recording of the turntable's sound, a file saved on the phone",
    ("You/DebugView.swift", "shown.text"): "Debug's engine log, as text",
}

#? the one address in an ios/App string literal: a text field's placeholder, an example of a private address
ALLOWED_WORDS = {
    ("Root/ServerAddressView.swift", "http://192.168.1.20:8090"): "the server address field's placeholder",
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
    "sets the environment's openURL": r"(?:(?<![@\w])environment|\btransformEnvironment)\s*\(\s*\\\s*\.\s*openURL\b",
    "SFSafariViewController": r"\bSFSafariViewController\b|\bimport\s+SafariServices\b",
    "a web view": r"\bWKWebView\b|\bWebView\b|\bimport\s+WebKit\b",
    "a sign-in web session": r"\bASWebAuthenticationSession\b",
    "the share sheet": r"\bUIActivityViewController\b",
    "markdown parsed at run time": r"[(,]\s*markdown\s*:",
    "a LocalizedStringKey made at run time": r"\bLocalizedStringKey\s*(?:\.\s*init\s*)?\(|\bText\s*\(\s*\.\s*init\s*\(",
    "a link attribute": r"\bLinkAttribute\b|\bAttributeContainer\b[^\n;]*\.\s*link\b|\bKey\s*\.\s*link\b"
                        r"|\bdataDetectorTypes\b",
}

#? in a string literal's words: SwiftUI's Text draws a literal's markdown, so each of these is a link that opens
SCHEME = r"(?:[A-Za-z][A-Za-z0-9+.\-]*\s*:|\\#*\()"
WORD_LINKS = {
    "a markdown link": rf"\]\(\s*<?\s*{SCHEME}",
    "a markdown link's address given apart": rf"\[[^\]\n]+\]\s*:\s*<?\s*{SCHEME}",
    "an autolink": r"<(?:[A-Za-z][A-Za-z0-9+.\-]{1,31}:|[^\s<>@\"]+@|\\#*\()",
}
#? and in ios/App's literals, any address at all (a Text may make a bare one tappable; Core holds the app's addresses)
APP_ADDRESS = re.compile(r"[A-Za-z][A-Za-z0-9+.\-]*://|\bwww\.")

#? what a URL built from deadwax's own address names on its way: the phone's address, its base, the origin, the web app
ORIGIN = re.compile(r"\b(?:ServerAddress|address|base|origin|appPath|absoluteString)\b|/player|\bserver\s*\.")

#? the calls read: openURL's, and Link's or ShareLink's - SwiftUI.Link, Link<Label>, Link.init too
OPEN_CALL = re.compile(r"(?<![\w.])(?P<name>openURL)\s*\(")
LINK_CALL = re.compile(r"(?<![\w.])(?:SwiftUI\s*\.\s*)?(?P<name>Link|ShareLink)"
                       r"(?:\s*<(?:[^<>()]|<[^<>()]*>)*>)?(?:\s*\.\s*init)?\s*\(")
#? the environment's openURL, read as a property
ENV_READ = re.compile(r"@\s*Environment\s*\(\s*\\\s*\.\s*(?P<key>openURL)\s*\)\s*"
                      r"(?:(?:private|fileprivate|internal)\s+)?var\s+(?P<name>\w+)\b")


# ---------------------------------------------------------------------------- reading Swift

def scan(text: str) -> tuple[str, str, str, list[tuple[int, int]], list[int]]:
    """Swift source read as the compiler lexes it, in views each the same length with the same lines, so an offset in
    one is the source's: `code`, its comments blanked; `bare`, its string and regex literals' contents blanked too (the
    quotes and any interpolated code kept) - where a use is looked for, so a word in a string or a comment is never
    one; and `words`, only the string literals' contents (each interpolation's opening kept, its code blanked). Then
    each string literal's span in `words`, and `lost`: where a string, comment or regex literal never closed - where the
    reading lost its place, so nothing after it can be trusted."""
    code, bare = list(text), list(text)
    words = [kept if kept == "\n" else " " for kept in text]
    spans: list[tuple[int, int]] = []
    lost: list[int] = []
    n = len(text)

    def blank(into: list, start: int, end: int) -> None:
        for k in range(start, end):
            if into[k] != "\n":
                into[k] = " "

    def keep(start: int, end: int) -> None:
        words[start:end] = text[start:end]

    def hashes_at(i: int) -> int:
        count = 0
        while i + count < n and text[i + count] == "#":
            count += 1
        return count

    def comment_end(i: int) -> int:
        start, depth = i, 0
        while i < n:
            if text.startswith("/*", i):
                depth, i = depth + 1, i + 2
            elif text.startswith("*/", i):
                depth, i = depth - 1, i + 2
                if depth == 0:
                    return i
            else:
                i += 1
        lost.append(start)
        return n

    def literal(i: int) -> int:
        hashes = hashes_at(i)
        start = i + hashes
        quote = '"""' if text.startswith('"""', start) else '"'
        close, interpolation = quote + "#" * hashes, "\\" + "#" * hashes + "("
        j = segment = content = start + len(quote)
        while j < n:
            if text.startswith(close, j):
                blank(bare, segment, j)
                keep(segment, j)
                spans.append((content, j))
                return j + len(close)
            if text.startswith(interpolation, j):
                blank(bare, segment, j)
                keep(segment, j + len(interpolation))
                j = segment = code_from(j + len(interpolation), inside=True)
                continue
            if not hashes and text[j] == "\\":
                j += 2
                continue
            if quote == '"' and text[j] == "\n":
                break
            j += 1
        blank(bare, segment, j)
        keep(segment, j)
        spans.append((content, j))
        lost.append(i)
        return j

    def regex(i: int) -> int:
        #? an extended regex literal, #/.../# (any number of #s): on one line, or from a #/ that ends its line to its /#.
        #? The first /# closes it - an escaped one closing it early only shows more as code, never less
        hashes = hashes_at(i)
        start, close = i + hashes + 1, "/" + "#" * hashes
        end_of_line = text.find("\n", start)
        end_of_line = n if end_of_line < 0 else end_of_line
        at = text.find(close, start, end_of_line)
        if at < 0 and not text[start:end_of_line].strip():
            at = text.find(close, end_of_line)
        if at < 0:
            lost.append(i)
            return n
        blank(bare, start, at)
        return at + len(close)

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
            elif text[i] == '"' or (text[i] == "#" and text[i + hashes_at(i):i + hashes_at(i) + 1] == '"'):
                i = literal(i)
            elif text[i] == "#" and text[i + hashes_at(i):i + hashes_at(i) + 1] == "/":
                i = regex(i)
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
    return "".join(code), "".join(bare), "".join(words), spans, lost


def views(text: str) -> tuple[str, str]:
    """scan()'s `code` and `bare`: the source with its comments blanked, and with its literals' contents blanked too."""
    code, bare, _, _, _ = scan(text)
    return code, bare


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


def calls(code: str, bare: str) -> list[tuple[str, int, int, str]]:
    """Every openURL, Link and ShareLink call: (which, its name's offset, the call's, what it opens or shares)."""
    found = []
    for match in OPEN_CALL.finditer(bare):
        args = arguments(code, bare, match.end() - 1)
        target = args[0][1] if args else ""
        found.append(("openURL", match.start("name"), match.start(), resolved(code, match.start(), target)))
    for match in LINK_CALL.finditer(bare):
        args = arguments(code, bare, match.end() - 1)
        label = "destination" if match.group("name") == "Link" else "item"
        target = next((value for name, value in args if name == label), "")
        found.append((match.group("name"), match.start("name"), match.start(), resolved(code, match.start(), target)))
    return sorted(found, key=lambda use: use[2])


def ways_out(text: str) -> list[tuple[str, int, str]]:
    """Every link out a Swift source makes: (what - "openURL", "Link" or "ShareLink" -, its line, what it opens)."""
    code, bare = views(text)
    return [(kind, text.count("\n", 0, at) + 1, target) for kind, _, at, target in calls(code, bare)]


def refusals(name: str, text: str) -> list[str]:
    """What's wrong with one Swift source (`name` relative to ios/App, or a DeadwaxKit path from ios/) - each of the
    module docstring's refusals, said with where it is."""
    code, bare, words, spans, lost = scan(text)

    def line(at: int) -> int:
        return text.count("\n", 0, at) + 1

    if lost:
        return [f"{name}:{line(lost[0])} can't be read past here - a string, comment or regex literal that never closes"]
    wrong = []
    uses = calls(code, bare)
    for kind, _, at, target in uses:
        if ORIGIN.search(target):
            wrong.append(f"{name}:{line(at)} {kind} opens what deadwax's own address makes: {target}")
        elif kind == "ShareLink":
            if (name, target) not in SHARED:
                wrong.append(f"{name}:{line(at)} ShareLink shares {target or 'something'} - not one of the app's shares")
        elif (name, target) not in ALLOWED:
            wrong.append(f"{name}:{line(at)} {kind} opens {target or 'something'} - not one of the app's links out")
    #? Link and ShareLink: a call the test reads, or nothing - a new spelling fails rather than passing unread
    called = {token for _, token, _, _ in uses}
    for match in re.finditer(r"\b(?:Link|ShareLink)\b", bare):
        if match.start() not in called:
            wrong.append(f"{name}:{line(match.start())} names {match.group()} other than in a call the test reads")
    #? openURL: the environment's read once, as openURL, where an allowed openURL is called - and called, ways_out has
    #? it; anything else done with it (Phase 7's openURL.webApp, someone else's openURL) refused
    allowed_here = any(kind == "openURL" and (name, target) in ALLOWED for kind, _, _, target in uses)
    reads = list(ENV_READ.finditer(bare))
    kept = set()
    if allowed_here and reads and reads[0].group("name") == "openURL":
        kept = {reads[0].start("key"), reads[0].start("name")}
    for match in re.finditer(r"\bopenURL\b", bare):
        if match.start() in kept:
            continue
        before, after = bare[:match.start()].rstrip(), bare[match.end():].lstrip()
        if re.search(r"\\\s*\.$", before):
            wrong.append(f"{name}:{line(match.start())} has the environment's openURL"
                         + (" other than once, as openURL" if allowed_here else ", and no link out of its own"))
        elif re.search(r"\b(?:var|let)$", before):
            wrong.append(f"{name}:{line(match.start())} declares an openURL of its own")
        elif before.endswith("."):
            wrong.append(f"{name}:{line(match.start())} calls another openURL")
        elif not after.startswith("("):
            wrong.append(f"{name}:{line(match.start())} does something with openURL other than call it")
    #? UIKit: UIApplication.shared held only as DownloadModel's application; open never called on what holds it; and
    #? no open(..., options:), a scene's or UIApplication's
    holders = {"UIApplication", "shared", "application"}
    for match in re.finditer(r"\bUIApplication\s*\.\s*shared\b(?!\s*\.\s*\w)", bare):
        bound = re.search(r"\b(?:let|var)\s+(\w+)\s*=\s*$", bare[:match.start()])
        holders |= {bound.group(1)} if bound else set()
        if not (name == DOWNLOAD_MODEL and bound and bound.group(1) == "application"):
            wrong.append(f"{name}:{line(match.start())} holds UIApplication.shared under a name of its own - "
                         "only DownloadModel's application may")
    holders |= set(re.findall(r"\b(\w+)\s*:\s*UIApplication\b(?!\s*\.)", bare))
    for match in re.finditer(rf"\b(?:{'|'.join(sorted(holders))})\s*[?!]?\s*\.\s*open(?:URL)?\b", bare):
        wrong.append(f"{name}:{line(match.start())} UIApplication's open")
    for match in re.finditer(r"(?<!\w)open\s*\(", bare):
        if any(label == "options" for label, _ in arguments(code, bare, match.end() - 1)):
            wrong.append(f"{name}:{line(match.start())} opens with options: - a scene's or UIApplication's open")
    for what, pattern in NEVER.items():
        for match in re.finditer(pattern, bare):
            wrong.append(f"{name}:{line(match.start())} {what}")
    #? a link given to an attributed string: .link(...) called on something (a case's .link(...) is no call), .link set
    #? (but AlbumInfoRow's own init), .link: as a key (but a case); and a link: argument but Core's AlbumInfo's
    for match in re.finditer(r"\.\s*link\s*\(", bare):
        before = bare[:match.start()].rstrip()
        implicit = re.search(r"(?:[(,=:\[{?&|<>+\-*/%^~]|\b(?:case|return|in|else|throw|try|await|yield|is|as|where"
                             r"|if|guard|while|switch))$", before)
        if bare[match.start() - 1:match.start()] in ("?", "!") or not implicit:
            wrong.append(f"{name}:{line(match.start())} gives something a link - an attribute container's link(...)")
    for match in re.finditer(r"\.\s*link\s*=(?!=)", bare):
        if not (name == ALBUM_INFO and re.match(r"self\.link = link\b", bare[match.start() - 4:])):
            wrong.append(f"{name}:{line(match.start())} sets a link")
    for match in re.finditer(r"\.\s*link\s*:(?!:)", bare):
        if not re.search(r"\bcase\b[^:{}\n]*$", bare[bare.rfind("\n", 0, match.start()) + 1:match.start()]):
            wrong.append(f"{name}:{line(match.start())} a link attribute's key")
    if name != ALBUM_INFO:
        for match in re.finditer(r"[(,]\s*link\s*:(?!:)", bare):
            wrong.append(f"{name}:{line(match.start())} gives a link: of its own - only Core's AlbumInfo makes an "
                         "Album info row's link")
    #? the words of each string literal
    for start, end in spans:
        said = words[start:end]
        shown = " ".join(said.split())
        for what, pattern in WORD_LINKS.items():
            for match in re.finditer(pattern, said):
                wrong.append(f"{name}:{line(start + match.start())} {what} in a string: {shown}")
        if not name.startswith("DeadwaxKit/") and (name, said) not in ALLOWED_WORDS:
            for match in APP_ADDRESS.finditer(said):
                wrong.append(f"{name}:{line(start + match.start())} an address in a string: {shown}")
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

#? Album info's own way out, as AlbumInfoView has it
ALBUM = ("@Environment(\\.openURL) private var openURL\n"
         "private func open(_ row: AlbumInfoRow) {\n guard let link = row.link else { return }\n"
         " openURL(link) { (accepted: Bool) in }\n}")


def test_the_matcher_refuses_a_planted_way_out():
    #? each made-up source (in Library/Planted.swift), and words of what it's refused for
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
        "a markdown link": ('Text("Read [the guide](https://example.org) first")', "a markdown link in a string"),
        "a shared address of deadwax's": ("ShareLink(item: server.address!.base)", "deadwax's own address"),
        "an openURL handler": (".environment(\\.openURL, OpenURLAction { _ in .handled })", "OpenURLAction"),
        # Link however it's spelt (review, finding 2)
        "SwiftUI.Link": ("SwiftUI.Link(\"Help\", destination: help)", "Link opens help - not one of"),
        "Link<Text>": ("Link<Text>(destination: help) { Text(\"Help\") }", "Link opens help - not one of"),
        "Link.init": ("Link.init(\"Help\", destination: help)", "Link opens help - not one of"),
        "SwiftUI.Link<Text>.init": ("SwiftUI.Link<Text>.init(destination: help) { Text(\"Help\") }",
                                    "Link opens help - not one of"),
        "Link under another name": ("typealias Way = SwiftUI.Link\nWay(\"Help\", destination: help)",
                                    "names Link other than in a call"),
        "Link's init handed on": ("let make = Link<Text>.init\nmake(destination: help) { Text(\"Help\") }",
                                  "names Link other than in a call"),
        # UIKit's opens (finding 3)
        "UIApplication.shared under a name": ("let ui = UIApplication.shared\nui.open(url)",
                                              "holds UIApplication.shared under a name of its own"),
        "and open called on it": ("let ui = UIApplication.shared\nui.open(url)", "UIApplication's open"),
        "a scene's open": ("scene.open(url, options: nil)", "opens with options:"),
        "the app delegate's UIApplication": ("func application(_ app: UIApplication) -> Bool {\n app.open(url)\n "
                                             "return true\n}", "UIApplication's open"),
        # tappable text with no ](https: in a literal (finding 4)
        "an attribute container's link": ('Text(AttributedString("Help", attributes: AttributeContainer().link(help)))',
                                          "a link attribute"),
        "a container's link, called on it": ("let container = AttributeContainer()\n"
                                             "Text(AttributedString(\"Help\", attributes: container.link(help)))",
                                             "an attribute container's link(...)"),
        "an inferred container's link": ('Text(AttributedString("Help", attributes: .init().link(help)))',
                                         "an attribute container's link(...)"),
        "a link set": ('var words = AttributedString("Help")\nwords.link = help\nText(words)', "sets a link"),
        "a link attribute's key": ('NSAttributedString(string: "Help", attributes: [.font: face, .link: help])',
                                   "a link attribute's key"),
        "a LocalizedStringKey": ("Text(LocalizedStringKey(words))", "a LocalizedStringKey made at run time"),
        "an inferred LocalizedStringKey": ("Text(.init(words))", "a LocalizedStringKey made at run time"),
        "markdown at run time": ("let said = try AttributedString(markdown: words)", "markdown parsed at run time"),
        "an autolink": ('Text("Read <https://example.org> first")', "an autolink in a string"),
        "an interpolated autolink": ('Text("Read <\\(guide)> first")', "an autolink in a string"),
        "a markdown link to an interpolated address": ('Text("Read [the guide](\\(guide)) first")',
                                                       "a markdown link in a string"),
        "a markdown link in a raw string": ('Text(#"Read [the guide](\\#(guide)) first"#)', "a markdown link in a"),
        "a markdown link's address given apart": ('Text("""\n[the guide][1]\n\n[1]: https://example.org\n""")',
                                                  "a markdown link's address given apart"),
        "a bare address": ('Text("See https://example.org")', "an address in a string"),
        # sharing (finding 5)
        "a ShareLink of its own": ("ShareLink(item: help) { Text(\"Share\") }", "not one of the app's shares"),
        "the share sheet": ("let sheet = UIActivityViewController(activityItems: [help], applicationActivities: nil)",
                            "the share sheet"),
        # inside an allowed file (finding 6) - and outside one
        "the environment's openURL set": (".environment(\\.openURL, handler)", "sets the environment's openURL"),
        "an Album info row with a link": ('rows.append(AlbumInfoRow(label: "Help", value: "", style: .link, '
                                          "link: help))", "gives a link: of its own"),
        "an inferred Album info row with a link": ('rows.append(.init(label: "Help", link: help))',
                                                   "gives a link: of its own"),
        # regex literals (finding 7)
        "a regex hiding the rest of its line": ("let pattern = #/a//b/#; openURL(URL(string: help)!)",
                                                "openURL opens URL(string: help)! - not one of"),
        "a regex of two #s": ('let pattern = ##/a/#"//b/##; Link("Help", destination: help)',
                              "Link opens help - not one of"),
        "a regex over lines": ("let pattern = #/\n  a // b \"\n/#\nLink(\"Help\", destination: help)",
                               "Link opens help - not one of"),
        "a regex that never closes": ("let pattern = #/a//b\nLink(\"Help\", destination: help)",
                                      "can't be read past here"),
        "a string that never closes": ("let pattern = /a\"/; Link(\"Help\", destination: help)",
                                       "can't be read past here"),
        "a comment that never closes": ("/* a comment\nLink(\"Help\", destination: help)", "can't be read past here"),
    }
    for what, (text, reason) in planted.items():
        said = refusals("Library/Planted.swift", text)
        assert any(reason in line for line in said), f"{what}: {said}"
    # Phase 7's row reads the environment's openURL with no link out of its own, and does more than call it
    said = " ".join(refusals("You/ManageSection.swift", PHASE_7))
    assert "has the environment's openURL, and no link out of its own" in said and "other than call it" in said
    # an allowed link's own expression in another file is refused there
    said = refusals("Library/Planted.swift", "Link(People.sharing, destination: URL(string: People.sharingDoc)!)")
    assert any("not one of the app's links out" in line for line in said), said
    # and in its own file, opened from deadwax's address, it is refused too
    said = refusals("Manage/PeopleScreen.swift",
                    "let guide = URL(string: People.origin(server.address))\nLink(People.sharing, destination: guide)")
    assert any("deadwax's own address" in line for line in said), said
    # a share the list keeps, in another file
    said = refusals("Library/Planted.swift", "ShareLink(item: shown.text) { Text(\"Share\") }")
    assert any("not one of the app's shares" in line for line in said), said
    # in Album info's own file: a second read of the environment's openURL, or the one under another name
    for read in ("@Environment(\\.openURL) private var openURL\n@Environment(\\.openURL) private var again\n",
                 "@Environment(\\.openURL) private var go\n"):
        text = read + ALBUM.split("\n", 1)[1]
        said = refusals("Album/AlbumInfoView.swift", text)
        assert any("has the environment's openURL other than once, as openURL" in line for line in said), said
    # an openURL of its own there, beside the environment's
    said = refusals("Album/AlbumInfoView.swift", ALBUM + "\nlet openURL = handler")
    assert any("declares an openURL of its own" in line for line in said), said
    # Album info's row link made in Album info's own file - the app's, not Core's
    said = refusals("Album/AlbumInfoView.swift", ALBUM + '\nlet row = AlbumInfoRow(label: "x", value: "", link: help)')
    assert any("gives a link: of its own" in line for line in said), said
    # UIApplication.shared held as DownloadModel holds it, in any other file
    said = refusals("Library/Planted.swift", "let application = UIApplication.shared")
    assert any("holds UIApplication.shared" in line for line in said), said


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
        ".onOpenURL { (url: URL) -> Void in shared(url) }",
        "navigation.open(.album(route))",
        'Text("\\(name) - [1](2) is not a link")',
        'let interpolated = "\\(flag ? "openURL(a)" : "b")"',
        # a case's .link(...), a switch's .link:, a row's style
        "switch credit { case .link(let id): open(id) default: break }",
        "return flag ? .link(id: id) : .plain",
        "switch row.style { case .link: open(row) case .plain: break }",
        'AlbumInfoRow(label: "x", value: "", style: .link)',
        # UIKit as the app uses it
        "if UIApplication.shared.applicationState == .background { pause() }",
        "let task = UIApplication.shared.beginBackgroundTask(withName: name) { }",
        "center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in }",
        "func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: "
        "[UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }",
        "let button = [NSAttributedString.Key.font: face]",
        'var badge = AttributedString(words)',
        # regex literals read whole
        "let pattern = #/a//b \"/#",
        'let wide = ##/a/#"//b/##',
        "let lines = #/\n  a // b \"\n/#",
    ])
    assert refusals("Library/Benign.swift", benign) == []
    # the three allowed links, each in its own file and opening what the allowlist says
    assert refusals("Album/AlbumInfoView.swift", ALBUM) == []
    assert ways_out(ALBUM) == [("openURL", 4, "row.link")]
    eq = ("if let address = URL(string: EQWords.Profile.gitHubAddress) {\n"
          "    Link(EQWords.Profile.gitHub, destination: address)\n}")
    assert refusals("EQ/EQProfileScreen.swift", eq) == []
    people = ("if !state.on, let guide = URL(string: People.sharingDoc) {\n"
              "    Link(People.sharing, destination: guide)\n}")
    assert refusals("Manage/PeopleScreen.swift", people) == []
    # the three allowed shares, the same way
    assert refusals("You/DebugView.swift", "if case .saved = status, let url {\n ShareLink(item: url) { Text(action) }\n}"
                    "\nShareLink(item: shown.text, preview: SharePreview(\"deadwax engine log\")) { }") == []
    export = "ShareLink(item: file(item.whole), preview: SharePreview(name)) {\n    Text(item.words)\n}"
    assert refusals("EQ/EQExport.swift", export) == []
    # DownloadModel's application, and the placeholder ALLOWED_WORDS keeps
    assert refusals(DOWNLOAD_MODEL, "let application = UIApplication.shared\n"
                                    "if application.applicationState == .background { }") == []
    assert refusals("Root/ServerAddressView.swift", 'TextField("http://192.168.1.20:8090", text: $typed)') == []
    # Album info's rows' links made where they're made
    assert refusals(ALBUM_INFO, 'rows.append(AlbumInfoRow(label: "x", value: "", style: .link, link: url))\n'
                                "self.link = link") == []


# ---------------------------------------------------------------------------- the app as it is

def test_nothing_in_the_app_opens_the_web_app():
    wrong, links, shares = [], set(), set()
    for name, text in sources().items():
        wrong += refusals(name, text)
        for kind, _, target in ways_out(text):
            (shares if kind == "ShareLink" else links).add((name, target))
    assert not wrong, "\n".join(wrong)
    # and each link out and share the lists keep is there - an entry nothing uses is taken out with it
    assert links == set(ALLOWED), sorted(links ^ set(ALLOWED))
    assert shares == set(SHARED), sorted(shares ^ set(SHARED))
    for name, said in ALLOWED_WORDS:
        _, _, words, spans, _ = scan((APP / name).read_text(encoding="utf-8"))
        assert said in [words[start:end] for start, end in spans], name


def test_the_app_is_read_as_swift_reads_it():
    # ios/App is built in Swift 5 mode, where /.../ is no regex literal - so a #/.../# is the only one it can have
    config = [path.read_text(encoding="utf-8") for path in sorted((IOS / "Config").glob("*.xcconfig"))]
    project = (IOS / "Deadwax.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    versions = [found for text in [*config, project] for found in re.findall(r"\bSWIFT_VERSION\s*=\s*([\w.]+)", text)]
    assert versions and set(versions) == {"5.0"}, versions
    for text in [*config, project, (IOS / "DeadwaxKit" / "Package.swift").read_text(encoding="utf-8")]:
        assert "BareSlashRegexLiterals" not in text and "bare-slash-regex" not in text
    # DeadwaxKit imports no UI framework: Core, in Swift 6 mode (where /.../ is a regex this doesn't read), has no way
    # out to write
    for name, text in sources().items():
        if name.startswith("DeadwaxKit/"):
            code, _ = views(text)
            imported = set(re.findall(r"^\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|"
                                      r"typealias)\s+)?(\w+)", code, re.MULTILINE))
            ui = imported & {"SwiftUI", "UIKit", "SafariServices", "WebKit", "AuthenticationServices", "AppKit"}
            assert not ui, f"{name}: {sorted(ui)}"


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
    # a row's link is set only by AlbumInfoRow's init (and refusals() refuses one set anywhere else)
    assert len(re.findall(r"\.link\s*=(?!=)", bare)) == 1 and "self.link = link" in bare
    # Top Songs' From Last.fm is LastfmLink.url's alone: an https address on last.fm or a host under it
    code, _ = views((CORE / "Lastfm.swift").read_text(encoding="utf-8"))
    link = code[code.index("public enum LastfmLink {"):]
    link = link[:link.index("\n}\n")]
    assert 'text.hasPrefix("https://")' in link and '!text.contains("@")' in link
    assert 'return host == "last.fm" || host.hasSuffix(".last.fm") ? text : nil' in link
    assert "checked(link).flatMap { URL(string: $0) }" in link
    # (Last.fm, slice A4) About's link is AboutBlock.url's alone: Last.fm's by LastfmLink, Wikipedia's an https address
    # on en.wikipedia.org itself, read the same way - (A4's review) but for its `@`: a title may hold one, so it is a
    # name or password before the host that is refused (the exact host stops "en.wikipedia.org@evil.com" as it is)
    code, _ = views((CORE / "AboutBlock.swift").read_text(encoding="utf-8"))
    about = code[code.index("public static func link(_ source: Source, _ url: String?) -> String? {"):]
    about = about[:about.index("\n    }\n")]
    assert "case .lastfm: return LastfmLink.checked(url)" in re.sub(r"\s+", " ", about)
    assert 'text.hasPrefix("https://")' in about and '!text.contains("@")' not in about
    assert ("let parts = URLComponents(string: text), parts.user == nil, parts.password == nil, let written = "
            "parts.percentEncodedHost, !written.contains(\"%\")") in re.sub(r"\s+", " ", about)
    assert 'return written.lowercased() == "en.wikipedia.org" ? text : nil' in about
    url = code[code.index("public static func url(_ paragraph: Paragraph?) -> URL? {"):]
    url = url[:url.index("\n    }\n")]
    assert "return link(paragraph.source, paragraph.url).flatMap { URL(string: $0) }" in url


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
