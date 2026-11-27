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


def test_no_session_stores_anything_and_covers_have_their_own_connections():
    transport = code(APP / "URLSessionTransport.swift")
    # every session - the covers' too - keeps nothing, exactly as before: ephemeral, no cache, never reading one
    assert flat(func(transport, "configuration")) == flat("""
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        return configuration""")
    # (after review) URLCache never stores on its own: no session is given one, none follows the protocol's policy
    assert re.findall(r"\.urlCache = [^\n]*", transport) == [".urlCache = nil"]
    assert "URLSessionConfiguration.default" not in transport and "useProtocolCachePolicy" not in transport
    assert "NetworkUsed" not in transport and "coverConfiguration" not in transport
    # a session per kind, the covers' its own URLSession (its own connections) from that same configuration
    session = flat(func(transport, "session"))
    assert "let kind = Kind(timeout: timeout, covers: covers)" in session and "sessions[kind] = session" in session
    assert ("let session = URLSession(configuration: Self.configuration(waiting: timeout), "
            "delegate: SameOriginRedirects.shared, delegateQueue: nil)") in session
    # the request's way: the viewer's full size first (its capped read), then a cover, then everything else
    send = flat(func(transport, "send"))
    assert flat("""
            if let most = request.mostBytes {
                (data, response) = try await CappedRead.read(sent, most: most,
                                                             configuration: Self.configuration(waiting: timeout))
            } else if CoverDisk.takes(request), let cache = Self.coverCache {
                (data, response, answered) = try await cover(request, sent: sent, cache: cache, timeout: timeout)
            } else {
                (data, response) = try await session(waiting: timeout).data(for: sent)
            }""") in send
    # a cover the disk answered without asking never says deadwax answered
    assert "if answered { heard(true) }" in send and send.count("heard(true)") == 2
    # the event log's stream keeps its own session
    assert "let configuration = Self.configuration(waiting: EventStream.silence)" in func(transport, "streamSession")
    # Core's rule names the two routes, and nothing else - never a download's cover, nor a caller's revalidation
    rule = code(CORE / "CoverDisk.swift")
    assert "public static let routes: [Endpoint] = [Routes.cover, Routes.archiveCover]" in rule
    assert flat("""guard request.method == "GET", request.mostBytes == nil, request.mayKeepOnDisk,
              header("If-None-Match", in: request.headers) == nil,
              header("If-Modified-Since", in: request.headers) == nil else { return false }""") in flat(rule)


def test_a_cover_is_stored_by_hand_under_its_address_alone_never_with_the_cookie():
    transport = code(APP / "URLSessionTransport.swift")
    # in a named place in Caches, bounded by Core's number, nothing of it in memory; the first build's folder - where
    # URLCache stored each request with its headers - removed
    cache = transport[transport.index("static let coverCache: URLCache? = {"):]
    cache = cache[:cache.index("}()")]
    assert "for: .cachesDirectory, in: .userDomainMask" in cache
    assert ("try? FileManager.default.removeItem(at: caches.appendingPathComponent(CoverDisk.oldFolder, "
            "isDirectory: true))") in cache
    assert "caches.appendingPathComponent(CoverDisk.folder, isDirectory: true)" in cache
    assert "URLCache(memoryCapacity: 0, diskCapacity: CoverDisk.diskBytes, directory: folder)" in cache
    # the key is Core's: the address alone, no header
    assert flat(func(transport, "coverKey")) == "URLRequest(CoverDisk.key(request))"
    # one place stores, and only under the key - never the request sent, which carries deadwax's session as Cookie:
    assert transport.count("storeCachedResponse(") == 1
    store = flat(func(transport, "store"))
    assert ("let answer = HTTPURLResponse(url: url, statusCode: 200, httpVersion: \"HTTP/1.1\", headerFields: headers)"
            in store)
    assert ("cache.storeCachedResponse(CachedURLResponse(response: answer, data: data, storagePolicy: .allowed), "
            "for: key)") in store
    cover = flat(func(transport, "cover", after="private func cover("))
    assert cover.startswith("let key = Self.coverKey(request) let held = cache.cachedResponse(for: key)")
    assert cover.count("in: cache)") == 2 and cover.count("under: key, in: cache)") == 2
    assert "Self.store(held.data, headers: again, under: key, in: cache)" in cover
    assert "Self.store(data, headers: kept, under: key, in: cache)" in cover
    assert "sent" not in cover.replace("var asked = sent", "")
    # what it asks is Core's: the copy while it stands (not deadwax answering), else deadwax with its validators
    assert "switch CoverDisk.ask(held: heldHeaders, now: Date().timeIntervalSince1970) {" in cover
    assert "case .kept: if let held { return (held.data, held.response, false) }" in cover
    assert ("case .revalidate(let validators): for (name, value) in validators "
            "{ asked.setValue(value, forHTTPHeaderField: name) } revalidating = true") in cover
    assert "try await session(waiting: timeout, covers: true).data(for: asked)" in cover
    # a 304 is the copy, kept again by Core's rule; a 200 kept by Core's rule; anything not kept takes the copy away
    assert ("if http.statusCode == 304, revalidating, let held, let heldHeaders {"
            " if let again = CoverDisk.revalidated(heldHeaders, by: Self.headers(http), now: now) {") in cover
    assert "if let kept = CoverDisk.kept(status: http.statusCode, headers: Self.headers(http), now: now) {" in cover
    assert cover.count("cache.removeCachedResponse(for: key)") == 2
    # Core's: the four headers kept, never Set-Cookie; a day at most
    rule = code(CORE / "CoverDisk.swift")
    assert 'public static let keptHeaders = ["Content-Type", "Cache-Control", "ETag", "Last-Modified"]' in rule
    assert flat(func(rule, "key")) == 'HTTPRequest(method: "GET", url: request.url)'
    assert "public static let freshMost = 24 * 60 * 60" in rule
    assert "return revalidate ? 0 : min(seconds, freshMost)" in rule


def test_a_downloaded_albums_cover_is_asked_exactly_as_before():
    model = code(APP / "Downloads" / "DownloadModel.swift")
    keep = flat(func(model, "keepAlbum"))
    assert ("var asked = client.coverRequest(coverID: cover, size: DownloadStore.coverSize)"
            " asked.mayKeepOnDisk = false let data = try await client.answer(asked).body") in keep
    assert "client.cover(" not in model


def test_a_cover_kept_on_disk_draws_while_deadwax_cant_be_reached():
    cover = code(APP / "Shared" / "CoverImage.swift")
    load = cover[cover.index("if self?.offline == true {"):]
    load = flat(load[:load.index("var data: Data?")])
    assert flat("""
                    if let image = await Task.detached(priority: .userInitiated, operation: { Self.onDisk(request) }).value {
                        self?.landed(key, flight, image, called: false)
                        self?.keptWhileOffline.insert(key)
                        return image
                    }
                    self?.landed(key, flight, nil, called: false, reached: false)
                    return nil""") in load
    assert "client.archiveCoverRequest(cover, size: size)" in load and "client.coverRequest(coverID: id, size: size)" in load
    # read under the transport's own key
    on_disk = flat(func(cover, "onDisk"))
    assert "URLSessionTransport.coverCache?.cachedResponse(for: URLSessionTransport.coverKey(request))" in on_disk
    # (after review) a failure for want of deadwax doesn't keep its minute while it still can't be reached: the disk is
    # read again
    assert ("if let at = failedAt[flight], Date().timeIntervalSince(at) < againAfter,"
            " !(offline && unreached.contains(flight)) { return nil }") in flat(cover)
    # (after review) and what the disk drew is let go as deadwax comes back, so the next look asks - the transport
    # revalidating it - rather than drawing the copy from memory for the rest of the run
    reach = flat(func(cover, "reach"))
    assert ("if online && offline { for flight in unreached { failedAt[flight] = nil } unreached = []"
            " for key in keptWhileOffline { images.removeObject(forKey: key as NSString) } keptWhileOffline = [] }") in reach
    assert "keptWhileOffline.remove(key)" in func(cover, "landed")


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
    # - and (after review) your library changing: an Add or a Remove anywhere, the store line's too, a delete, the
    # starred count moving
    assert flat(func(store, "stamp")) == flat("""
        let edits = navigation.albumWrites.values.reduce(0) { (sum: Int, each: Int) -> Int in sum + each }
        return KeptAnswers<Album>.Stamp(person: server.person, session: navigation.session,
                                        writes: edits + navigation.managingWrites + library.yoursChanged)""")
    library = code(APP / "Models" / "LibraryModel.swift")
    assert "index.forget(.yours) syncGeneration(.yours) yoursChanged += 1 Task { await askMine() }" in flat(
        func(library, "libraryChanged"))
    assert ("guard server.access.hasLibrary else { return } index.forget(.yours) syncGeneration(.yours)"
            " yoursChanged += 1 Task { await askMine() }") in flat(func(library, "albumDeleted"))
    assert ("if starredCount.saw(answer) { index.forget(.yours) syncGeneration(.yours) yoursChanged += 1 }"
            in flat(func(library, "askMine")))
    # the store line's Add is an Add: it goes through libraryChanged
    assert flat(func(library, "add")).endswith("libraryChanged()")
    # every reader of the stamp says whose library it is
    for path in [APP / "Album" / "AlbumView.swift", APP / "Artist" / "ArtistView.swift",
                 APP / "Library" / "ArtistsScreen.swift", APP / "Mac" / "Library" / "MacArtistsPage.swift",
                 APP / "Mac" / "Library" / "MacAlbumsPage.swift"]:
        text = code(path)
        calls = re.findall(r"KeptAlbumAnswers\.stamp\([^)]*\)", text)
        assert calls and all(call == "KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library)"
                             for call in calls), (path.name, calls)
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
    assert ("private var kept: KeptAnswers<Album>.Stamp {"
            " KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library) }") in flat(view)
    # (after review) the model's load and refresh take the stamp with no default, so no caller can leave it out - and
    # each of the page's says `kept`
    model_sig = flat(model)
    assert ("func load(key: String, client: DeadwaxClient?, personal: Bool, player: PlayerModel, downloads: DownloadModel,"
            " kept: KeptAnswers<Album>.Stamp?) async {") in model_sig
    assert ("func refresh(client: DeadwaxClient?, player: PlayerModel, downloads: DownloadModel,"
            " kept: KeptAnswers<Album>.Stamp?) async {") in model_sig
    loads = re.findall(r"await model\.(?:load|refresh)\([^)]*\)", view)
    assert loads and all(call.endswith("downloads: downloads, kept: kept)") for call in loads), loads
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
    assert ("private var keptStamp: KeptAnswers<Album>.Stamp {"
            " KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library) }") in flat(view)
    loads = re.findall(r"await model\.load\([^)]*\)", view)
    assert loads and all(flat(call).endswith("kept: keptStamp)") for call in loads), loads
    # (not `kept`: the body's own `kept` is the Last.fm answer, and its tasks and pull would read that one instead)
    assert "let kept = artists.keptLastfm(route.id)" in view


def test_the_macs_list_layouts_read_and_keep_the_kept_answers_too():
    # (after review) the Mac's Albums and Artists in List draw the selected one's Info from the same kept answers, and
    # fill them, as the pages do
    albums = flat(func(code(APP / "Mac" / "Library" / "MacAlbumsPage.swift"), "choose"))
    assert ("await model.load(key: \"\\(server.person)|\\(album.id)\", client: server.client, personal: false,"
            " player: player, downloads: downloads,"
            " kept: KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library))") in albums
    artists = flat(func(code(APP / "Mac" / "Library" / "MacArtistsPage.swift"), "choose"))
    assert ("await model.load(key: \"\\(server.person)|\\(artist.id)\", client: server.client,"
            " online: reachability.online, artists: artists,"
            " kept: KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library))") in artists


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
    # (after review) the request is the model's, an unstructured task a screen's cancellation can't reach: what
    # `asking` says is on its way always is, and lands
    assert ("defer { if asked == asks { asking = nil } } let request = Task<[Artist], Error> { try await client.artists() }"
            " do { let artists = try await request.value") in ask
    assert ask.count("client.artists()") == 1
    # another person starts with nothing kept
    assert "landed = nil told = 0 toldMoved = nil asking = nil" in flat(func(model, "reset"))
    # the phone's Artists: shown, or the app back in front on it, by the rule (the task's and the scene's); a pull,
    # and a failure's Try again (the note over the list, the one in its place), at once
    screen = code(APP / "Library" / "ArtistsScreen.swift")
    assert "await ask(fresh: false)" in screen and "Task { await ask(fresh: false) }" in screen
    assert "await ask(fresh: true)" in flat(func(screen, "pulled"))
    assert "RefreshProblemNote(failure: failure) { Task { await ask(fresh: true) } }" in screen
    assert "if reachability.online { Task { await ask(fresh: true) } } else { reachability.tryNow() }" in screen
    asking = flat(func(screen, "ask"))
    assert "if fresh { await artists.ask() } else { await artists.askIfOld(writes: writes) }" in asking
    assert "let writes = KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library).writes" in asking
    # nothing on the screen asks but through that
    assert "await ask()" not in screen and "artists.ask()" not in screen.replace("if fresh { await artists.ask() }", "")
    # the Mac's Artists page, by the same rule
    page = code(APP / "Mac" / "Library" / "MacArtistsPage.swift")
    assert "await artists.askIfOld(writes: writes)" in page and "artists.ask()" not in page
    assert "let writes = KeptAlbumAnswers.stamp(server: server, navigation: navigation, library: library).writes" in page
    # the Library's Refresh still asks at once
    assert "await artists.ask()" in code(APP / "Library" / "LibraryView.swift")
    # Core's minute is the album index's own
    assert "public static let freshMs: Int64 = AlbumIndexState.freshMs" in code(CORE / "ListFreshness.swift")


def test_an_edits_write_moves_the_count_again_once_navidrome_has_scanned():
    # (after review) as the page path's albumWritten does: an Edit opened by its folder (no page beneath) moved the
    # stamp only before the scan; a mark changes no file and moves it once
    edit = code(APP / "Edit" / "EditAlbumModel.swift")
    told = flat(func(edit, "told", after="private func told(from: String"))
    assert told.startswith("guard samePerson else { return } navigation?.managed()")
    assert told.endswith("guard filesChanged else { return } Task {"
                         " try? await Task.sleep(for: .milliseconds(AlbumEdit.settleMs))"
                         " guard self.samePerson else { return } self.navigation?.managed() }")
    assert "private func told(from: String, deleted: Bool = false, filesChanged: Bool = true) {" in edit
    assert "told(from: from, filesChanged: false)" in flat(func(edit, "mark"))
    assert "told(from: before.path)" in flat(func(edit, "wrote")) and "told(from: before.path, deleted: true)" in edit


# ---------------------------------------------------------------------------- fix 5: the artist page's requests in order


def test_an_artist_page_asks_which_albums_are_yours_only_when_it_has_to():
    view = code(APP / "Artist" / "ArtistView.swift")
    opened = view[view.index(".task(id: taskKey) {"):]
    opened = flat(block(opened, opened.index("{")))
    # as it opens: only when the index isn't in hand or a write was told of since a page last asked (Core's OwnedCheck)
    assert opened.startswith(
        "if reachability.online, artists.asksOwned(inHand: search.ownedIndex != nil, writes: keptStamp.writes) {"
        " search.refreshOwned() } await model.load(")
    # a pull asks it again, before the rest
    pull = view[view.index(".pullToRefresh {"):]
    pull = flat(block(pull, pull.index("{")))
    assert "search.refreshOwned() await model.load(key: taskKey, client: server.client, online: true" in pull
    model = code(APP / "Models" / "ArtistsModel.swift")
    assert flat(func(model, "asksOwned")) == (
        "guard OwnedCheck.asks(inHand: inHand, writes: writes, askedUnder: ownedAskedUnder) else { return false }"
        " ownedAskedUnder = writes return true")
    assert "ownedAskedUnder = nil" in flat(func(model, "reset"))
    # Play and Shuffle: the songs prefetch is as it was - begun with the artist's answer, every album, Play lit once
    # they are in hand (the covers have had their own session since fix 1, so the prefetch holds none of them back)
    page = code(APP / "Models" / "ArtistPageModel.swift")
    assert flat(func(page, "askAlbums")) == (
        "let order = ArtistPage.playOrder(ArtistPage.rows(answer?.album ?? [])) send(asks.want(order), client: client)")
    assert "if answer != nil { askAlbums(client) }" in page


# ---------------------------------------------------------------------------- fix 6: Requests' polling


def test_a_look_that_changes_nothing_redraws_nothing():
    model = code(APP / "Models" / "RequestsModel.swift")
    redraw = flat(func(model, "redraw"))
    # the board drawn again only when the look made a different one
    assert "if board != next { board = next } runLooks()" in redraw and "} board = next" not in redraw
    land = flat(func(model, "land"))
    assert ("if trackingEnabled != answer.trackingEnabled { trackingEnabled = answer.trackingEnabled }"
            " if failure != nil { failure = nil } if !answered { answered = true } redraw()") in land
    poll = flat(func(model, "poll"))
    assert "failure = error if !answered { answered = true } redraw()" in poll
    # the pace is Core's: the root once a second with nothing moving, the half second while something is
    assert ("let delay = RequestsPolling.delay(open: open, hasActive: hasActive, filing: filing,"
            " online: reachability.online, watching: watching)") in poll
    rules = code(CORE / "RequestsWatch.swift")
    assert "if open { return hasActive || filing ? openSeconds : idleOpenSeconds }" in rules
    assert "public static let idleOpenSeconds: Double = 1" in rules and "public static let openSeconds: Double = 0.5" in rules
