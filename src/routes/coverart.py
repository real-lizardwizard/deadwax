"""
The Cover Art Archive's front covers through deadwax, for the iPhone app (2.1.24):
`GET /deadwax/coverart/{kind}/{mbid}`, a user's route (tests/test_logins.py ROUTES), so the app draws a MusicBrainz
album's cover in Search (Phase 5's slice 2, notes/ios-specs/phase5-search.md question 8 on `phase5-search`) while
talking only to deadwax. The web app doesn't call it: it still loads those covers from coverartarchive.org itself. src/coverart_cache.py answers and keeps them,
src/api/coverart_endpoint.py ArchiveFronts asks the Archive; notes/ios.md "The Cover Art Archive relay (2.1.24)".

NOT A GENERAL PROXY: `kind` is exactly `release` or `release-group`, `mbid` a lowercase UUID as MusicBrainz writes one
(MBID_PATTERN, every other route's), `size` 250 (Search's rows: a 44 pt cover, 132 px on a 3x screen), 500 or 1200,
each a 422 otherwise, before anything is asked. The address is made from those three alone, a redirect is followed only
to the Archive's own hosts, and only an image type is passed on.

Answers: 200 with the image, its type (jpeg, png, gif or webp), an ETag of its bytes and COVER_CACHE - 304 with no body
for an If-None-Match that names it; 404 when the Archive has no front; 502 when it couldn't be had (the Archive away or
in trouble, a redirect off its hosts, not an image, too big); 504 when the Archive was too slow. The failures are
quick and say little (`detail`): a phone draws the empty cover either way. Served under GuardMedia's headers (nosniff,
a sandbox, same-origin) and never gzipped, as the player's covers are (src/api/app.py MEDIA_PREFIXES).
"""

from typing import Literal

from fastapi import APIRouter, HTTPException, Request, Response
from fastapi import Path as PathParam

from src.coverart_cache import CoverRelay
from src.routes.search_musicbrainz import MBID_PATTERN

router = APIRouter()

#? A front can change (an editor uploads a better one), so not immutable; a week, then revalidated with the ETag
COVER_CACHE = "private, max-age=604800"
#? Nothing about a failure is kept by anyone but deadwax, which remembers it briefly itself
FAILED_CACHE = "no-store"

WORDS = {
    404: "The Cover Art Archive has no front cover for that.",
    502: "deadwax couldn't get that cover from the Cover Art Archive just now.",
    504: "The Cover Art Archive took too long to answer.",
}


def relay_of(request: Request) -> CoverRelay:
    """The app's relay, made at its first ask."""
    state = request.app.state
    relay = getattr(state, "coverart", None)
    if relay is None:
        relay = state.coverart = CoverRelay()
    return relay


async def stop(app) -> None:
    """The fetches under way cancelled - deadwax is stopping."""
    relay = getattr(app.state, "coverart", None)
    if relay is not None:
        await relay.stop()


def names(header: str | None, etag: str) -> bool:
    """Whether an If-None-Match names this ETag (weak or strong - a GET compares them weakly), or is `*`."""
    for tag in (header or "").split(","):
        tag = tag.strip()
        if tag == "*" or tag.removeprefix("W/") == etag:
            return True
    return False


@router.get("/{kind}/{mbid}")
async def front_cover(
    request: Request,
    kind: Literal["release", "release-group"],
    mbid: str = PathParam(..., pattern=MBID_PATTERN),
    size: Literal["250", "500", "1200"] = "250",
):
    """A release's or a release group's front cover from the Cover Art Archive, at one of its thumbnail sizes."""
    answer = await relay_of(request).answer(kind, mbid, size)
    if answer.status != 200 or answer.front is None:
        raise HTTPException(status_code=answer.status, detail=WORDS.get(answer.status, WORDS[502]),
                            headers={"Cache-Control": FAILED_CACHE})
    front = answer.front
    etag = front.etag
    headers = {"ETag": etag, "Cache-Control": COVER_CACHE}
    if names(request.headers.get("if-none-match"), etag):
        return Response(status_code=304, headers=headers)
    return Response(front.data, media_type=front.mime, headers=headers)
