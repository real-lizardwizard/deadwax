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


# ---------------------------------------------------------------------------- fix 3: Edit opens without the whole scan


def test_a_pages_first_read_asks_with_the_scan_kept_on_disk():
    scan = code(APP / "Edit" / "LibraryScanModel.swift")
    fetch = flat(func(scan, "fetch"))
    # the first read of a page (nothing in hand) sends the kept copy's ETag; later ones the one in hand, as before
    assert fetch.startswith("reading = true do { let first = answer == nil let disk = first ? await Self.kept(client) : nil"
                            " var got = try await client.libraryScanKeeping(ifNoneMatch: first ? disk?.etag : etag)")
    # the copy is the scan only after deadwax's 304 to its ETag - read with the 304's headers; unreadable, asked again
    assert ("if first, let disk, case .unchanged(let unchanged) = got { if let scan = await Self.decoded(disk, unchanged)"
            " { copy = (scan, disk.etag) } else { got = try await client.libraryScanKeeping(ifNoneMatch: nil) } }") in fetch
    # only the newest read lands, the copy or a fresh answer - which is kept on disk in its place
    assert ("guard reads.isNewest(ticket) else { return .dropped } if let copy { answer = copy.answer etag = copy.etag }"
            " if case .fresh(let fresh, let tag, let body) = got { answer = fresh etag = tag"
            " Self.keep(client, etag: tag, body: body) }") in fetch
    # per server and per session, off the main actor; written only with an ETag to ask by
    kept = flat(func(scan, "kept"))
    assert "ScanFiles.inCaches()?.read(server: server, session: session)" in kept and "Task.detached" in kept
    keep = flat(func(scan, "keep"))
    assert keep.startswith("guard let etag, !etag.isEmpty else { return }")
    assert "ScanKept(server: client.server.key, session: client.session, etag: etag, body: body)" in keep
    assert "Task.detached(priority: .utility) { ScanFiles.inCaches()?.write(record) }" in keep
    assert "disk.answer(unchanged)" in func(scan, "decoded") and "Task.detached" in func(scan, "decoded")
    # Core's: the copy is read back only for the server and session that wrote it, in Caches, the cookie never written
    rules = code(CORE / "ScanKept.swift")
    assert "head.server.utf16.elementsEqual(server.utf16), head.who.utf16.elementsEqual(who(session).utf16)" in rules
    assert "return SessionFile.fnv1a(session)" in rules
    assert "FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)" in rules


# ---------------------------------------------------------------------------- fix 4: Artists' one-minute rule


def test_the_artists_are_asked_as_they_show_by_the_album_indexs_rule():
    model = code(APP / "Models" / "ArtistsModel.swift")
    # the screen showing asks only when Core's rule says - none in hand, over a minute old, a write told of, a failure
    # - and nothing asked under the same writes is on its way
    # (the writes noted, and when they moved - the settle that follows is Navidrome's scan of them)
    assert flat(func(model, "askIfOld")) == (
        "if writes != told { told = writes toldMoved = Int64(Self.now) }"
        " guard ListFreshness.asks(landed: landed, writes: writes, failed: failure != nil, onItsWay: asking,"
        " now: Int64(Self.now)) else { return } await ask()")
    ask = flat(func(model, "ask"))
    # every ask - a pull's too - says what it was asked under, and the newest one landing stamps the list in hand
    assert ("failure = nil let writes = told"
            " let settled = ListFreshness.settled(askedAt: Int64(Self.now), writesMovedAt: toldMoved)"
            " asking = writes defer { if asked == asks { asking = nil } }") in ask
    assert ("guard asked == asks, epoch == self.epoch else { return }"
            " landed = ListFreshness.Landed(at: Int64(Self.now), writes: writes, settled: settled)") in ask
    # another person starts with nothing kept
    assert "landed = nil told = 0 toldMoved = nil asking = nil" in flat(func(model, "reset"))
    # the phone's Artists: shown, or the app back in front on it, by the rule (the task's and the scene's); a pull,
    # and a failure's Try again (the note over the list, the one in its place), at once
    screen = code(APP / "Library" / "ArtistsScreen.swift")
    assert screen.count("await ask(fresh: false)") == 2 and "Task { await ask(fresh: false) }" in screen
    assert "await ask(fresh: true)" in flat(func(screen, "pulled"))
    assert "RefreshProblemNote(failure: failure) { Task { await ask(fresh: true) } }" in screen
    assert "if reachability.online { Task { await ask(fresh: true) } } else { reachability.tryNow() }" in screen
    asking = flat(func(screen, "ask"))
    assert asking.count("if fresh { await artists.ask() } else { await artists.askIfOld(writes: writes) }") == 2
    assert "let writes = KeptAlbumAnswers.stamp(server: server, navigation: navigation).writes" in asking
    assert "await ask()" not in screen and "artists.ask()" not in screen.replace("if fresh { await artists.ask() }", "")
    # the Mac's Artists page, by the same rule
    page = code(APP / "Mac" / "Library" / "MacArtistsPage.swift")
    assert "group.addTask { await artists.askIfOld(writes: writes) }" in page and "artists.ask()" not in page
    assert "let writes = KeptAlbumAnswers.stamp(server: server, navigation: navigation).writes" in page
    # the Library's Refresh still asks at once
    assert "Task { await artists.ask() }" in code(APP / "Library" / "LibraryView.swift")
    # Core's minute is the album index's own
    assert "public static let freshMs: Int64 = AlbumIndexState.freshMs" in code(CORE / "ListFreshness.swift")
