"""
Asking GitHub for AutoEq's list and its profiles (2.1.7) - the I/O half of src/autoeq.py, for src/routes/eq.py.

Only GitHub's three kinds of address are ever asked, each made by src/autoeq.py: master's commit
(api.github.com, `Accept: application/vnd.github.sha` - a bare 40-hex answer), `results/INDEX.md` at that commit,
and one result's ParametricEQ.txt at that commit, its path from deadwax's own list (raw.githubusercontent.com).
Nothing from a request is ever part of an address.

One client, 15 s (10 s to connect), redirects NOT followed. Every request carries the user agent
`deadwax/<version>` - GitHub's API refuses a request with none - and nothing more: not
Config.musicbrainz_user_agent(), which Wikipedia's client sends (wikipedia_endpoint.py), since that one carries the
contact address MUSICBRAINZ_EMAIL gives it, which MusicBrainz and Wikimedia ask callers for and GitHub doesn't.

Three outcomes kept apart, as wikipedia_endpoint.py keeps them: an answer, a definite 404 (a profile GitHub doesn't
have at that commit - None), and Unreachable (nothing answered, any other status, a redirect, an answer too big or
not what was asked for), which the route keeps nothing of. An answer is read a piece at a time and refused as soon
as it passes its size (src/autoeq.py LIST_MAX_BYTES, PROFILE_MAX_BYTES), never read whole first.
"""

import httpx

from src import __version__
from src.autoeq import COMMIT_ACCEPT, COMMIT_URL, LIST_MAX_BYTES, PROFILE_MAX_BYTES, SHA, index_url, profile_url

#? A person is waiting on the first list and on a profile; the list is 851 KB
TIMEOUT = httpx.Timeout(15.0, connect=10.0)
#? the commit's answer is 40 letters
COMMIT_MAX_BYTES = 1024


class Unreachable(Exception):
    """GitHub gave no usable answer - nothing to keep, ask again next time."""


class AutoEqClient:
    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            #? a redirect is never followed: every address is GitHub's own, at a commit, and should simply answer
            self._client = httpx.AsyncClient(follow_redirects=False, timeout=TIMEOUT)
        return self._client

    async def close_client(self) -> None:
        if self._client is not None:
            await self._client.aclose()

    @staticmethod
    def user_agent() -> str:
        return f"deadwax/{__version__}"

    async def _get(self, url: str, what: str, limit: int, accept: str | None = None) -> bytes | None:
        """The body GitHub answered `url` with, None for its 404 - or Unreachable."""
        headers = {"User-Agent": self.user_agent()}
        if accept:
            headers["Accept"] = accept
        try:
            async with self._http().stream("GET", url, headers=headers) as response:
                if response.status_code == 404:
                    return None
                if response.status_code != 200:
                    raise Unreachable(f"GitHub answered {response.status_code} for {what}")
                body = bytearray()
                async for piece in response.aiter_bytes():
                    body += piece
                    if len(body) > limit:
                        raise Unreachable(f"{what} was refused: more than {limit} bytes (at least {len(body)})")
                return bytes(body)
        except httpx.HTTPError as e:
            raise Unreachable(f"GitHub couldn't be reached for {what}: {str(e) or type(e).__name__}") from e

    async def master_commit(self) -> str:
        """AutoEq's master's commit now, as 40 lowercase hex digits."""
        body = await self._get(COMMIT_URL, "AutoEq's commit", COMMIT_MAX_BYTES, accept=COMMIT_ACCEPT)
        if body is None:
            raise Unreachable("GitHub answered 404 for AutoEq's commit")
        sha = body.decode("ascii", errors="replace").strip()
        if not SHA.match(sha):
            raise Unreachable("GitHub's answer for AutoEq's commit wasn't a commit")
        return sha

    async def index(self, sha: str) -> str:
        """results/INDEX.md at the commit, as text."""
        body = await self._get(index_url(sha), f"AutoEq's list at {sha[:7]}", LIST_MAX_BYTES)
        if body is None:
            raise Unreachable(f"GitHub answered 404 for AutoEq's list at {sha[:7]}")
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError as e:
            raise Unreachable(f"AutoEq's list at {sha[:7]} wasn't UTF-8") from e

    async def profile(self, sha: str, path: str) -> str | None:
        """A result's ParametricEQ.txt at the commit, as AutoEq wrote it - None when GitHub has no such file."""
        body = await self._get(profile_url(sha, path), f"{path} at {sha[:7]}", PROFILE_MAX_BYTES)
        if body is None:
            return None
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError as e:
            raise Unreachable(f"{path} at {sha[:7]} wasn't UTF-8") from e


autoeq_client = AutoEqClient()
