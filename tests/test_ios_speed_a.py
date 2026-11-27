"""
The app's first speed slice, Speed A - what's asked again (notes/ios.md "Speed A: what's asked again";
~/Desktop/Code/deadwax-plans/speed-app.md). Read from the Swift source, as the other ios tests read theirs: the app's
wiring of each fix. Core's rules for them are SpeedATests.swift's.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
CORE = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of the lines read here holds a // in a string)."""
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


def func(text: str, name: str, after: str = "") -> str:
    """The body of the first `func <name>` (after `after`, when given)."""
    start = text.index(after) if after else 0
    found = re.search(r"func " + re.escape(name) + r"\b[^{]*\{", text[start:])
    assert found, name
    return block(text, start + found.end() - 1)


def flat(text: str) -> str:
    """Whitespace folded to single spaces - a body compared whole, never by a substring of it."""
    return " ".join(text.split())


# ---------------------------------------------------------------------------- fix 1: covers kept on disk


def test_covers_alone_go_through_a_session_whose_cache_is_on_disk():
    transport = code(APP / "URLSessionTransport.swift")
    # every other route's sessions keep nothing, exactly as before: ephemeral, no cache, never reading one
    assert flat(func(transport, "configuration")) == flat("""
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        return configuration""")
    # the covers': a disk cache, used as each answer's headers say, cookies off as every other's
    assert flat(func(transport, "coverConfiguration")) == flat("""
        guard let cache = coverCache else { return configuration(waiting: timeout) }
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = cache
        configuration.timeoutIntervalForRequest = timeout
        return configuration""")
    # in a named place in Caches, bounded by Core's number; nothing of it in memory (CoverCache holds the decoded ones)
    cache = transport[transport.index("static let coverCache: URLCache? = {"):]
    cache = cache[:cache.index("}()")]
    assert "for: .cachesDirectory, in: .userDomainMask" in cache
    assert "caches.appendingPathComponent(CoverDisk.folder, isDirectory: true)" in cache
    assert "URLCache(memoryCapacity: 0, diskCapacity: CoverDisk.diskBytes, directory: folder)" in cache
    # a session per kind, the covers' its own - one URLSession made for both, with the redirect rule
    session = flat(func(transport, "session"))
    assert ("let configuration = covers ? Self.coverConfiguration(waiting: timeout) : Self.configuration(waiting: timeout)"
            in session)
    assert "let kind = Kind(timeout: timeout, covers: covers)" in session and "sessions[kind] = session" in session
    # the request's way: the viewer's full size first (its capped read), then a cover, then everything else
    send = flat(func(transport, "send"))
    assert flat("""
            if let most = request.mostBytes {
                (data, response) = try await CappedRead.read(sent, most: most,
                                                             configuration: Self.configuration(waiting: timeout))
            } else if CoverDisk.takes(request) {
                let used = NetworkUsed()
                (data, response) = try await session(waiting: timeout, covers: true).data(for: sent, delegate: used)
                answered = used.overNetwork
            } else {
                (data, response) = try await session(waiting: timeout).data(for: sent)
            }""") in send
    # a cover the cache answered without asking never says deadwax answered
    assert "if answered { heard(true) }" in send and send.count("heard(true)") == 2
    used = transport[transport.index("private final class NetworkUsed"):]
    used = used[:used.index("\n}\n")]
    assert "each.resourceFetchType == .networkLoad" in used
    assert "SameOriginRedirects.shared.urlSession(session, task: task, willPerformHTTPRedirection: response," in used
    # the event log's stream keeps its own session, as every route's but the covers'
    assert "let configuration = Self.configuration(waiting: EventStream.silence)" in func(transport, "streamSession")
    # Core's rule names the two routes, and nothing else
    rule = code(CORE / "CoverDisk.swift")
    assert "public static let routes: [Endpoint] = [Routes.cover, Routes.archiveCover]" in rule
    assert 'guard request.method == "GET", request.mostBytes == nil else { return false }' in rule


def test_a_cover_kept_on_disk_draws_while_deadwax_cant_be_reached():
    cover = code(APP / "Shared" / "CoverImage.swift")
    load = cover[cover.index("if self?.offline == true {"):]
    load = flat(load[:load.index("var data: Data?")])
    assert flat("""
                    if let image = await Task.detached(priority: .userInitiated, operation: { Self.onDisk(request) }).value {
                        self?.landed(key, flight, image, called: false)
                        return image
                    }
                    self?.landed(key, flight, nil, called: false, reached: false)
                    return nil""") in load
    assert "client.archiveCoverRequest(cover, size: size)" in load and "client.coverRequest(coverID: id, size: size)" in load
    on_disk = flat(func(cover, "onDisk"))
    assert "URLSessionTransport.coverCache?.cachedResponse(for: URLRequest(request))" in on_disk
