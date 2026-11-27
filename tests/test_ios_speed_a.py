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


# ---------------------------------------------------------------------------- fix 2: an album's answer kept


def test_an_album_opened_again_draws_its_kept_answer_and_asks_behind_it():
    model = code(APP / "Models" / "AlbumModel.swift")
    load = flat(func(model, "load"))
    # the phone's kept answer first, then the session's - both drawn at once, online or not, and deadwax asked behind
    phone = load.index("if album == nil, let kept = downloads.keptAlbum(route.id) {")
    session = load.index("if album == nil, let kept, let answer = KeptAlbumAnswers.shared.answer(route.id, stamp: kept) {"
                         " album = answer fromKept = true }")
    asked = load.index("guard let client, online else { return }")
    assert phone < session < asked
    assert "let wantsAlbum = (album == nil || fromPhone || fromKept) && !empty && !goneButHere" in load
    assert "await self.askAlbum(client, player: player, downloads: downloads, again: false, kept: kept)" in load
    # another album or person starts afresh
    assert "fromKept = false" in load[:load.index("self.personal = personal")]
    ask = flat(func(model, "askAlbum"))
    # deadwax's answer replaces it and is kept under the stamp it was asked under
    assert ("album = found empty = false fromPhone = false fromKept = false goneButHere = false"
            " if let kept { KeptAlbumAnswers.shared.keep(found, stamp: kept) }") in ask
    # an album deadwax says is gone is let go; a failure behind the kept answer keeps it drawn, but never a gone one
    assert ask.count("KeptAlbumAnswers.shared.forget(route.id)") == 3
    assert "if again || fromPhone || (fromKept && !gone), album != nil { return }" in ask
    assert "if gone { album = nil fromKept = false }" in ask
    assert "kept: kept)" in flat(func(model, "refresh"))
    # this page's Add or Remove changes the album's starred: its kept answer goes
    change = flat(func(model, "change"))
    assert change.index("KeptAlbumAnswers.shared.forget(route.id)") < change.index("changed = done")


def test_the_kept_answers_are_per_person_and_drop_on_every_write():
    model = code(APP / "Models" / "AlbumModel.swift")
    store = model[model.index("final class KeptAlbumAnswers {"):]
    assert "private var kept = KeptAnswers<Album>(most: KeptAlbums.most)" in store
    # who is signed in (the person counter and the pages' session, both moved by every sign-in change) and every write
    # deadwax was told of: Edit album's to a folder, and every managing write (an apply, a delete, a re-file, a Get)
    assert flat(func(store, "stamp")) == flat("""
        let edits = navigation.albumWrites.values.reduce(0) { (sum: Int, each: Int) -> Int in sum + each }
        return KeptAnswers<Album>.Stamp(person: server.person, session: navigation.session,
                                        writes: edits + navigation.managingWrites)""")
    rules = code(CORE / "KeptAnswers.swift")
    assert "(a.person, a.session, a.writes) < (b.person, b.session, b.writes)" in rules
    assert flat(func(rules, "adopt")) == flat("""
        if let held = self.stamp {
            if stamp == held { return true }
            if stamp < held { return false }
        }
        self.stamp = stamp
        answers = [:]
        order = []
        return true""")
    # the album page reads and keeps under the stamp of now, its Refresh too - and an Edit's write asks it again
    view = code(APP / "Album" / "AlbumView.swift")
    assert "private var kept: KeptAnswers<Album>.Stamp { KeptAlbumAnswers.stamp(server: server, navigation: navigation) }" in view
    loads = re.findall(r"await model\.load\(key: taskKey,[^)]*\)", view)
    assert len(loads) == 2 and all(call.endswith("downloads: downloads, kept: kept)") for call in loads), loads
    assert "Task { await model.refresh(client: server.client, player: player, downloads: downloads, kept: kept) }" in view
    assert ".onChange(of: navigation.albumWrites[route.id]) { _, _ in refresh() }" in view
    # Play and Shuffle take the songs drawn - a kept answer's at once - in the tap, nothing awaited first
    play = func(view, "play", after="private func play(at index: Int?, shuffle: Bool = false)")
    assert "await" not in play and "Task" not in play
    assert "player.play(songs: songs, album: album, at: index, shuffle: shuffle)" in play


def test_the_artist_pages_prefetch_fills_the_same_store():
    model = code(APP / "Models" / "ArtistPageModel.swift")
    send = flat(func(model, "send"))
    assert "let kept = self.kept" in send
    assert ("if let found { if let kept { KeptAlbumAnswers.shared.keep(found, stamp: kept) }"
            " next = self.asks.answered(ask, with: found)") in send
    assert "if let kept { self.kept = kept }" in flat(func(model, "load"))
    view = code(APP / "Artist" / "ArtistView.swift")
    assert "private var keptStamp: KeptAnswers<Album>.Stamp { KeptAlbumAnswers.stamp(server: server, navigation: navigation) }" in view
    loads = re.findall(r"await model\.load\([^)]*\)", view)
    assert len(loads) == 5 and all(flat(call).endswith("kept: keptStamp)") for call in loads), loads
    # (not `kept`: the body's own `kept` is the Last.fm answer, and its tasks and pull would read that one instead)
    assert "let kept = artists.keptLastfm(route.id)" in view
