import Foundation

// The artist tools' routes (Phase 8, slice 5 - phase8-managing.md 4): one of the library's names as the scan knows it,
// a picture in their folder, Artist images' preview and apply, a candidate's picture through deadwax's relay, the
// MusicBrainz artist search, and Move albums' preview and apply. Every write is a plain JSON POST with no Origin or
// Referer (what deadwax's same-origin guard lets through), and every apply is sent the body its preview was - the
// server working the plan out again.

extension DeadwaxClient {
    /// One of the library's names for an artist, as the scan knows it - nil when it files no album under that name (a
    /// 404).
    public func libraryArtist(name: String) async throws -> ArtistSummary? {
        let response = try await answer(request(Routes.libraryArtist, query: [("name", name)]), accept: [200, 404])
        return response.status == 200 ? try decode(ArtistSummary.self, response) : nil
    }

    public func artistArtRequest(folder: String, kind: String) -> HTTPRequest {
        var built = request(Routes.artistArt, query: [("artist", folder), ("kind", kind)])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// A picture in their folder (`folder` the summary's path), of `kind` - nil for none.
    public func artistArt(folder: String, kind: String) async throws -> Data? {
        let response = try await answer(artistArtRequest(folder: folder, kind: kind), accept: [200, 404])
        return response.status == 200 ? response.body : nil
    }

    public func artistImagesPreview(_ body: ArtistImagesBody) async throws -> ArtistImagesPreview {
        try await call(Routes.artistImagesPreview, sending: body)
    }

    /// Save: the pictures chosen fetched and written - given as long as the pictures in hand need (ArtistWaits).
    public func artistImagesApply(_ body: ArtistImagesBody, commons: Int) async throws -> ArtistImagesApplied {
        var built = request(Routes.artistImagesApply, json: try Self.json(body))
        built.timeout = ArtistWaits.imagesApply(pictures: body.choices.count, commons: commons)
        return try decode(ArtistImagesApplied.self, try await answer(built))
    }

    public func artistPictureRequest(url: String) -> HTTPRequest {
        var built = request(Routes.artistPicture, query: [("url", url)])
        built.headers["Accept"] = "image/*"
        built.mostBytes = ArtistWaits.pictureMostBytes
        return built
    }

    /// A candidate's picture (its `preview`), passed on by deadwax: the bytes, or the relay's refusal thrown as the
    /// APIFailure it is (its `detail` the relay's own words).
    public func artistPicture(url: String) async throws -> Data {
        try await answer(artistPictureRequest(url: url)).body
    }

    public func artistSearch(_ query: String) async throws -> ArtistMatchesAnswer {
        try await call(Routes.artistSearch, sending: ArtistSearchBody(query: query))
    }

    public func refilePreview(_ body: ArtistRefileBody) async throws -> ArtistRefilePlan {
        try await call(Routes.refilePreview, sending: body)
    }

    /// One name's Move: its albums retagged and moved - given as long as the name's albums need (ArtistWaits).
    public func refileApply(_ body: ArtistRefileBody, bytes: Double) async throws -> ArtistRefileApplied {
        var built = request(Routes.refileApply, json: try Self.json(body))
        built.timeout = ArtistWaits.refileApply(bytes: bytes)
        return try decode(ArtistRefileApplied.self, try await answer(built))
    }
}
