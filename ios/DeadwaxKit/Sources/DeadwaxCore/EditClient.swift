import Foundation

// Edit album's routes (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 3.1-3.3): the library's scan without its
// tracks, the editor's MusicBrainz search and its two pressings' asks, the retag's preview and apply, the cover alone,
// the folder's cover, and the two marks. Every write is a plain JSON POST with no Origin or Referer - what deadwax's
// same-origin guard lets through (src/api/same_origin.py) - and every apply is sent the same body as its preview, the
// server working the plan out again.

extension DeadwaxClient {
    /// The library's scan, every album without its tracks (`GET /library/albums?tracks=false`, server 2.1.28) - its
    /// headers read (X-Scanned-At, X-Scan-Stale), `.unchanged` when the answer kept (its ETag) still is.
    public func libraryScan(ifNoneMatch etag: String?) async throws -> Fetched<ScanAnswer> {
        var built = request(Routes.libraryAlbums, query: [("tracks", "false")])
        if let etag, !etag.isEmpty { built.headers["If-None-Match"] = etag }
        let response = try await answer(built, accept: built.headers["If-None-Match"] == nil ? [200] : [200, 304])
        if response.status == 304 { return .unchanged }
        return .fresh(try decode(ScanAnswer.self, response).with(headers: response), etag: response.header("ETag"))
    }

    /// MusicBrainz's albums for the editor's query (`fullySearch(query, 25, false)`, as the web's editor asks: no
    /// `quick`, so MusicBrainz's ten attempts - given `Routes.editorSearchTimeout`). A 503 is MusicBrainz away.
    public func editorSearch(_ query: String) async throws -> FullySearchAnswer {
        var built = request(Routes.fullySearch, query: [("query", query), ("limit", String(Retag.searchLimit)),
                                                        ("releases", "false")])
        built.timeout = Routes.editorSearchTimeout
        return try decode(FullySearchAnswer.self, try await answer(built))
    }

    /// One group's pressings without their tracklists (`/search_musicbrainz/releases?tracks=false`) - what tells them
    /// apart (format, country, catalogue number, track count) and not the 58 tracklists.
    public func pressings(groupMbid: String) async throws -> ReleaseGroupAnswer {
        try await call(Routes.releases, as: ReleaseGroupAnswer.self,
                       query: [("release_group_mbid", groupMbid), ("tracks", "false")])
    }

    /// One pressing with its tracklist (`/search_musicbrainz/release`) - what a retag is built from. A 503 is
    /// MusicBrainz away.
    public func pressing(mbid: String) async throws -> PageRelease {
        try await call(Routes.release, as: PageRelease.self, query: [("release_mbid", mbid)])
    }

    /// What applying `release` to the folder would change (`POST /library/retag/preview`) - writes nothing. Each
    /// file's changes in the server's order.
    public func retagPreview(_ body: RetagRequestBody) async throws -> RetagPlan {
        let response = try await answer(request(Routes.retagPreview, json: try Self.json(body)))
        do {
            return try RetagPlan.read(response.body)
        } catch {
            throw APIFailure.other("deadwax's answer couldn't be read (RetagPlan\(Self.what(error))). Is the app"
                                   + " older or newer than the server?")
        }
    }

    /// Writes the tags and re-files the folder (`POST /library/retag/apply`) - the same body as the preview, the plan
    /// worked out again on the server. Its answer can take minutes (the pause before a rename, `Routes.timeouts`).
    public func retagApply(_ body: RetagRequestBody) async throws -> RetagResponse {
        let response = try await answer(request(Routes.retagApply, json: try Self.json(body)))
        do {
            var answer = try JSONDecoder().decode(RetagResponse.self, from: response.body)
            if let ordered = OrderedJSON.parse(response.body)?["plan"] { answer.reorder(ordered["files"]) }
            return answer
        } catch {
            throw APIFailure.other("deadwax's answer couldn't be read (RetagResponse\(Self.what(error))). Is the app"
                                   + " older or newer than the server?")
        }
    }

    /// The cover alone (`POST /library/art/fetch`): the pressing shown's front, replacing what is there.
    public func fetchCover(_ body: CoverFetchBody) async throws -> CoverFetched {
        try await call(Routes.artFetch, sending: body)
    }

    /// The folder's cover (`/library/art?album=`): the file beside the tracks, else a picture inside them.
    public func libraryArtRequest(path: String) -> HTTPRequest {
        var built = request(Routes.libraryArt, query: [("album", path)])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// The folder's cover's bytes - nil when it has none (a 404); anything else deadwax answers is thrown.
    public func libraryArt(path: String) async throws -> Data? {
        let response = try await answer(libraryArtRequest(path: path), accept: [200, 404])
        return response.status == 200 ? response.body : nil
    }

    /// It's fine as it is (`POST /library/queue/ignore`): exactly the issues shown.
    public func markFine(path: String, issues: [String]) async throws -> QueueMarked {
        try await call(Routes.queueIgnore, sending: QueueMarkBody(albumPath: path, issues: issues))
    }

    /// Ask about it again (`POST /library/queue/unignore`).
    public func askAgain(path: String) async throws -> QueueMarked {
        try await call(Routes.queueUnignore, sending: QueueMarkBody(albumPath: path, issues: nil))
    }

    // MARK: Tags (slice 2)

    /// What editing these tracks' tags would change (`POST /library/tags/preview`) - writes nothing. Each file's
    /// changes in the form's order (`TagEditFile`).
    public func tagsPreview(_ body: TagEditBody) async throws -> TagEditPlan {
        try await call(Routes.tagsPreview, sending: body)
    }

    /// Writes the edited tags and nothing else - no file renamed, no folder moved (`POST /library/tags/apply`): the
    /// same body as the preview, the plan worked out again on the server; the whole batch refused (a 400 with its
    /// problems) when any of it is wrong. Waited for by the files' size (`bytes`, EditWaits.tagsApply).
    public func tagsApply(_ body: TagEditBody, bytes: Double) async throws -> TagEditResponse {
        var built = request(Routes.tagsApply, json: try Self.json(body))
        built.timeout = EditWaits.tagsApply(bytes: bytes)
        return try decode(TagEditResponse.self, try await answer(built))
    }

    /// One picture inside one track (`/library/tracks/picture?album=&file=&index=`) - a 404 when the file or the
    /// picture isn't there.
    public func trackPictureRequest(path: String, file: String, index: Int) -> HTTPRequest {
        var built = request(Routes.trackPicture, query: [("album", path), ("file", file), ("index", String(index))])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// That picture's bytes - nil when it isn't there (a 404); anything else deadwax answers is thrown.
    public func trackPicture(path: String, file: String, index: Int) async throws -> Data? {
        let response = try await answer(trackPictureRequest(path: path, file: file, index: index), accept: [200, 404])
        return response.status == 200 ? response.body : nil
    }

    // MARK: Artwork and Lyrics (slice 3)

    /// Get cover (`POST /library/art/fetch`, GetArtButton's): the front of the release the folder is tagged with,
    /// never replacing one - a 404 when the Cover Art Archive has none for it.
    public func getCover(path: String) async throws -> CoverFetched {
        try await call(Routes.artFetch, sending: CoverFetchBody(albumPath: path, replace: false, releaseMbid: nil))
    }

    /// Get lyrics (`POST /library/lyrics/fetch`): LRCLIB asked for every track of `album` without a .lrc, none
    /// replaced, none re-timed - waited for by how many that is (EditWaits.lyrics).
    public func getLyrics(_ album: ScanAlbum) async throws -> LyricsSummary {
        var built = request(Routes.lyricsFetch, json: try Self.json(LyricsFetchBody(albumPath: album.path)))
        built.timeout = EditWaits.lyrics(album)
        return try decode(LyricsSummary.self, try await answer(built))
    }

    /// Get CD art (`POST /library/disc_art/fetch`): a picture of each disc of `album`, by the folder's own release - a
    /// 404 when neither the Archive nor fanart.tv has one, a 400 when the folder already has deadwax's own. Waited for
    /// by its discs (EditWaits.discArt).
    public func getDiscArt(_ album: ScanAlbum) async throws -> DiscArtFetched {
        var built = request(Routes.discArtFetch, json: try Self.json(DiscArtFetchBody(albumPath: album.path)))
        built.timeout = EditWaits.discArt(album)
        return try decode(DiscArtFetched.self, try await answer(built))
    }

    /// One CD art picture beside the tracks (`/library/disc_art?album=&file=`) - only a name the scan counts as disc art.
    public func libraryDiscArtRequest(path: String, file: String) -> HTTPRequest {
        var built = request(Routes.libraryDiscArt, query: [("album", path), ("file", file)])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// That picture's bytes - nil when it isn't there (a 404); anything else deadwax answers is thrown.
    public func libraryDiscArt(path: String, file: String) async throws -> Data? {
        let response = try await answer(libraryDiscArtRequest(path: path, file: file), accept: [200, 404])
        return response.status == 200 ? response.body : nil
    }

    // MARK: Delete (slice 4)

    /// What deleting the folder takes (`/library/deletion_summary?album=`), read live - touches nothing.
    public func deletionSummary(path: String) async throws -> DeletionSummary {
        try await call(Routes.deletionSummary, as: DeletionSummary.self, query: [("album", path)])
    }

    /// Delete permanently (`POST /library/delete`): the folder and everything in it. A refusal (outside the library,
    /// gone, no audio in it) is a 400 with its words.
    public func deleteAlbum(path: String) async throws -> AlbumDeleted {
        try await call(Routes.deleteAlbum, sending: DeleteAlbumBody(albumPath: path))
    }

    static func json<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw APIFailure.other("The app couldn't write what it meant to send (\(Body.self)).")
        }
    }
}

extension RetagResponse {
    /// The plan's files' changes put in the order the body wrote them.
    mutating func reorder(_ files: OrderedJSON?) {
        var plan = self.plan
        plan.order(files)
        self = RetagResponse(plan: plan, results: results)
    }
}
