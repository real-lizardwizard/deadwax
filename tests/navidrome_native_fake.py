"""
A fake Navidrome 0.64.2 for People (2.0.0-player.61) - its native API as its web UI uses it, and Subsonic's
getUser, over ONE set of accounts, so a reset changes what getUser accepts and an admin flag what `adminRole`
says. Shaped from Navidrome's source (server/auth.go, server/nativeapi/native_api.go,
persistence/user_repository.go, server/subsonic/users.go, conf/configuration.go, consts/consts.go) and
deluan/rest at the commit Navidrome pins - never recorded from a real one.

What it holds to, as Navidrome does:

  - `POST /auth/login`: a JSON body, 422 for one that isn't; 401 {"error": "Invalid username or password"};
    200 {id, name, username, isAdmin, token, subsonicSalt, subsonicToken}. Rate limited PER CLIENT ADDRESS: 5
    requests per 20 s, EVERY request counted (successful ones too), 429 in plain text.
  - JWTs carry the account's name, id and token epoch. Every authenticated answer - errors too - carries a
    refreshed one in `X-ND-Authorization` (no "Bearer"), and only the newest two of an account's are taken,
    so a client that keeps the first is caught. A password write bumps the epoch: every JWT of it dies.
    Admin-ness is read from the account on every request, never the token.
  - `/api/user`: list, create and delete an admin's; get and put an admin's or that user's own; the PUT
    REPLACES THE WHOLE RECORD (fields not sent are blanked, isAdmin false, createdAt zeroed); a PUT to an id
    it doesn't have INSERTS one; names unique whatever their case; no name or password rule; every save of
    an admin gives it every library; a new non-admin gets the `default_new_users` libraries; a DELETE records
    the cascade (stars, playlists, plays...). 403 {"error": "...Permission denied"}, 404 {"error": "user(id:X)
    not found"}, 400 {"errors": {field: code}}.
  - (2.0.2) A PUT of your OWN record wants `currentPassword` with a `password` (validatePasswordChange - admins too),
    400 {"errors": {"currentPassword": "ra.validation.passwordDoesNotMatch"}} when it's wrong; a non-admin's is refused
    403 with EnableUserEditing off (`enable_user_editing`), and keeps its name and never becomes an admin's; the
    refreshed JWT of your own password change carries the bumped epoch.
  - Subsonic getUser with token auth (md5(password + salt)): error 40 for a wrong login; and Navidrome's
    Subsonic auth limiter - 5 failed logins per name per address in 20 s, then every login of that name
    refused (correct ones too) until the window passes.

THE TEST'S CHECKS: every request is recorded (method, path, headers, body); `acting` names the person the test
says is acting, and an /api request whose JWT is anyone else's - or anything ever signed in as NAVIDROME_USER
(`shared`) - is a violation the fixture fails the test on.
"""

import hashlib
import json
from collections import deque
from datetime import datetime, timezone
from urllib.parse import parse_qs, urlparse

import httpx

LIBRARIES = [{"id": 1, "name": "Music"}, {"id": 2, "name": "Audiobooks"}]
DEFAULT_NEW_USERS = {1}

LOGIN_LIMIT, LOGIN_WINDOW = 5, 20.0
SUBSONIC_FAILURES, SUBSONIC_WINDOW = 5, 20.0


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome", **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


class FakeNavidromeNative:
    def __init__(self, clock: list[float], shared: str = "demo"):
        self.clock = clock
        self.shared = shared
        self.accounts: dict[str, dict] = {}
        self.passwords: dict[str, str] = {}
        self.epochs: dict[str, int] = {}
        self.made = 0
        self.requests: list[dict] = []
        self.logins: deque[float] = deque()
        self.subsonic_failed: dict[str, deque] = {}
        #? how many times getUser refused each name (a wrong login, or the limiter) - "never refused maya 5 times"
        self.refused: dict[str, int] = {}
        self.issued: dict[str, list[str]] = {}
        self.tokens: dict[str, dict] = {}
        self.cascades: list[dict] = []
        self.acting: str | None = None
        self.violations: list[str] = []
        self.down = False
        self.timeout: set[str] = set()          # methods that time out ("PUT", "DELETE", "POST")
        self.dropped: set[str] = set()          # methods Navidrome CARRIES OUT, its answer then lost (a dropped connection)
        self.one_unread = False                 # GET /api/user/{id} can't connect (Navidrome gone a moment)
        self.ignore_password = False            # a Navidrome that renamed `password`
        self.ignore_admin = False               # ...or `isAdmin`
        self.refuse_delete = False              # a DELETE answered 500
        self.hide_from_list: set[str] = set()   # accounts the list leaves out (a test forcing the last-admin rule)
        self.answer_login_as: str | None = None  # /auth/login answering for another account
        #? (2.0.2) Navidrome's EnableUserEditing (conf/configuration.go: true by default) - off, a non-admin may not PUT
        #? even their own record (persistence/user_repository.go Update: rest.ErrPermissionDenied)
        self.enable_user_editing = True
        for name, password, admin in (("admin", "admin-navidrome-pw", True), ("james", "james-navidrome-pw", False),
                                      ("ethan", "ethan-navidrome-pw", False), (shared, "shared-pw", False)):
            self.add(name, password, admin)

    # ----- the accounts

    def add(self, name: str, password: str, admin: bool = False, libraries: set | None = None,
            account_id: str | None = None) -> str:
        self.made += 1
        account_id = account_id or f"nd{self.made:020d}"
        #? as Navidrome's user repository stamps a new row (CreatedAt = time.Now()), written as Go writes a time.Time
        created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f") + "123Z"
        self.accounts[account_id] = {
            "id": account_id, "userName": name, "name": name.title(), "email": f"{name}@example.com",
            "isAdmin": admin, "lastLoginAt": None, "lastAccessAt": None, "createdAt": created,
            "updatedAt": "2026-01-01T00:00:00Z", "scrobbleFilter": "",
            "libraries": [lib for lib in LIBRARIES if admin or lib["id"] in (DEFAULT_NEW_USERS if libraries is None else libraries)],
        }
        self.passwords[account_id] = password
        self.epochs[account_id] = 0
        return account_id

    def by_name(self, name: str) -> dict | None:
        return next((a for a in self.accounts.values() if a["userName"].lower() == name.lower()), None)

    def id_of(self, name: str) -> str:
        return self.by_name(name)["id"]

    def set_password(self, name: str, password: str) -> None:
        """A password changed in Navidrome itself: its epoch bumped, every JWT of it dead."""
        account = self.by_name(name)
        self.passwords[account["id"]] = password
        self.epochs[account["id"]] += 1

    def remove(self, name: str) -> None:
        """An account deleted in Navidrome's own Users page."""
        account = self.by_name(name)
        del self.accounts[account["id"]]

    def native(self, method: str | None = None) -> list[dict]:
        """Every native API request seen (not /rest), optionally of one method."""
        return [r for r in self.requests if not r["path"].startswith("/rest") and (method is None or r["method"] == method)]

    def writes(self) -> list[dict]:
        return [r for r in self.native() if r["method"] in ("POST", "PUT", "DELETE") and r["path"].startswith("/api")]

    def subsonic(self, name: str | None = None) -> list[dict]:
        return [r for r in self.requests if r["path"].startswith("/rest") and (name is None or r["query"].get("u", "").lower() == name)]

    # ----- the transport

    def handle(self, request: httpx.Request) -> httpx.Response:
        body = None
        if request.content:
            try:
                body = json.loads(request.content)
            except ValueError:
                body = request.content.decode("utf-8", "replace")
        query = {k: v[0] for k, v in parse_qs(urlparse(str(request.url)).query).items()}
        self.requests.append({"method": request.method, "path": request.url.path, "headers": dict(request.headers),
                              "body": body, "query": query})
        if self.down:
            raise httpx.ConnectError("connection refused")
        if request.method in self.timeout and request.url.path.startswith("/api"):
            raise httpx.ReadTimeout("timed out")
        path = request.url.path
        if path.startswith("/rest/"):
            return self.get_user(query)
        if path == "/auth/login" and request.method == "POST":
            return self.login(request, body)
        if path == "/api/user" or path.startswith("/api/user/"):
            if self.one_unread and request.method == "GET" and path.startswith("/api/user/"):
                raise httpx.ConnectError("connection refused")
            answer = self.users(request, body)
            if request.method in self.dropped:
                raise httpx.RemoteProtocolError("Server disconnected without sending a response.")
            return answer
        return httpx.Response(404, text="404 page not found")

    # ----- Subsonic

    def get_user(self, query: dict) -> httpx.Response:
        name = query.get("u", "").lower()
        if self.shared and name == self.shared:
            self.violations.append("getUser was asked as NAVIDROME_USER")
        account = self.by_name(name)
        window = self.subsonic_failed.setdefault(name, deque())
        while window and self.clock[0] - window[0] >= SUBSONIC_WINDOW:
            window.popleft()
        blocked = len(window) >= SUBSONIC_FAILURES
        token = hashlib.md5((self.passwords.get(account["id"], "") if account else "").encode() + query.get("s", "").encode()).hexdigest()
        if blocked or account is None or query.get("t") != token:
            window.append(self.clock[0])
            self.refused[name] = self.refused.get(name, 0) + 1
            return httpx.Response(200, json=failed(40, "Wrong username or password"))
        if query.get("username", "").lower() != name:
            return httpx.Response(200, json=failed(50, "not allowed"))
        return httpx.Response(200, json=ok(user={"username": account["userName"], "adminRole": account["isAdmin"]}))

    # ----- the native sign-in

    def jwt(self, account: dict, line: str | None = None) -> str:
        """A JWT for `account` - of a new line (a sign-in) or refreshing one: each line's newest two are taken."""
        self.made += 1
        token = f"jwt.{account['userName']}.{self.made}"
        line = line or token
        self.tokens[token] = {"sub": account["userName"], "uid": account["id"], "epoch": self.epochs[account["id"]],
                              "line": line}
        self.issued.setdefault(line, []).append(token)
        return token

    def login(self, request: httpx.Request, body) -> httpx.Response:
        while self.logins and self.clock[0] - self.logins[0] >= LOGIN_WINDOW:
            self.logins.popleft()
        if len(self.logins) >= LOGIN_LIMIT:
            return httpx.Response(429, text="Too Many Requests\n")
        self.logins.append(self.clock[0])
        if not isinstance(body, dict):
            return httpx.Response(422, json={"error": "invalid body"})
        name = str(body.get("username", ""))
        if self.shared and name.lower() == self.shared:
            self.violations.append("/auth/login was asked as NAVIDROME_USER")
        if self.acting is not None and name.lower() != self.acting:
            self.violations.append(f"/auth/login as {name} while {self.acting} was acting")
        account = self.by_name(name)
        if account is None or body.get("password") != self.passwords[account["id"]]:
            return httpx.Response(401, json={"error": "Invalid username or password"})
        answered = self.by_name(self.answer_login_as) if self.answer_login_as else account
        return httpx.Response(200, json={"id": answered["id"], "name": answered["name"], "username": answered["userName"],
                                         "isAdmin": answered["isAdmin"], "token": self.jwt(answered),
                                         "subsonicSalt": "a1b2c3", "subsonicToken": "0123456789abcdef0123456789abcdef"})

    # ----- /api/user

    def caller(self, request: httpx.Request) -> dict | None:
        header = request.headers.get("x-nd-authorization", "")
        token = header.removeprefix("Bearer ").strip()
        claims = self.tokens.get(token)
        if claims is None:
            return None
        account = self.accounts.get(claims["uid"])
        #? another epoch (a password changed), another account under the name, or an old token: not authenticated
        if account is None or account["userName"] != claims["sub"] or self.epochs[claims["uid"]] != claims["epoch"]:
            return None
        if token not in self.issued.get(claims["line"], [])[-2:]:
            return None
        if self.shared and claims["sub"].lower() == self.shared:
            self.violations.append("the native API was asked as NAVIDROME_USER")
        if self.acting is not None and claims["sub"].lower() != self.acting:
            self.violations.append(f"the native API was asked as {claims['sub']} while {self.acting} was acting")
        return account

    def users(self, request: httpx.Request, body) -> httpx.Response:
        account = self.caller(request)
        if account is None:
            return httpx.Response(401, json={"error": "Not authenticated"})
        line = self.tokens[request.headers["x-nd-authorization"].removeprefix("Bearer ").strip()]["line"]
        refreshed = {"X-ND-Authorization": self.jwt(account, line)}

        def answer(status: int, payload) -> httpx.Response:
            return httpx.Response(status, json=payload, headers=refreshed)

        denied = {"error": "Error reading user: Permission denied"}
        parts = request.url.path.split("/")
        target_id = parts[3] if len(parts) > 3 else None
        admin = account["isAdmin"]
        if request.method == "GET" and target_id is None:
            if not admin:
                return answer(403, denied)
            return answer(200, [dict(a) for a in self.accounts.values() if a["userName"] not in self.hide_from_list])
        if request.method == "GET":
            found = self.accounts.get(target_id)
            if found is None or not (admin or found["id"] == account["id"]):
                return answer(404, {"error": f"user(id:{target_id}) not found"})
            return answer(200, dict(found))
        if request.method == "POST" and target_id is None:
            if not admin:
                return answer(403, denied)
            if not isinstance(body, dict):
                return answer(422, {"error": "invalid"})
            if self.by_name(str(body.get("userName", ""))) is not None:
                return answer(400, {"errors": {"userName": "ra.validation.unique"}})
            new_id = self.add(str(body.get("userName", "")), "" if self.ignore_password else str(body.get("password", "")),
                              bool(body.get("isAdmin")))
            made = self.accounts[new_id]
            made.update(name=str(body.get("name", "")), email=str(body.get("email", "")))
            return answer(200, {"id": new_id})
        if request.method == "PUT" and target_id:
            if not (admin or target_id == account["id"]):
                return answer(403, denied)
            if not admin and not self.enable_user_editing:
                return answer(403, denied)
            if not isinstance(body, dict):
                return answer(422, {"error": "invalid"})
            if not admin:
                #? (2.0.2) Update: a non-admin's own record keeps its name and is never an admin's, whatever was sent
                body = {**body, "isAdmin": False, "userName": account["userName"]}
            if target_id == account["id"]:
                #? (2.0.2) validatePasswordChange: anyone changing their OWN password - an admin too - sends the current one
                errors = {}
                if not body.get("password") and body.get("currentPassword"):
                    errors["password"] = "ra.validation.required"
                if body.get("password"):
                    if not body.get("currentPassword"):
                        errors["currentPassword"] = "ra.validation.required"
                    if body.get("currentPassword") != self.passwords[target_id]:
                        errors["currentPassword"] = "ra.validation.passwordDoesNotMatch"
                if errors:
                    return answer(400, {"errors": errors})
            other = self.by_name(str(body.get("userName", "")))
            if other is not None and other["id"] != target_id:
                return answer(400, {"errors": {"userName": "ra.validation.unique"}})
            was = self.accounts.get(target_id)
            #? Put writes every column from the body: what isn't sent is blanked
            record = {"id": target_id, "userName": str(body.get("userName", "")), "name": str(body.get("name", "")),
                      "email": str(body.get("email", "")),
                      "isAdmin": (was or {}).get("isAdmin", False) if self.ignore_admin else bool(body.get("isAdmin", False)),
                      "lastLoginAt": body.get("lastLoginAt"), "lastAccessAt": body.get("lastAccessAt"),
                      "createdAt": body.get("createdAt") or "0001-01-01T00:00:00Z", "updatedAt": "2026-10-21T12:00:00Z",
                      "scrobbleFilter": str(body.get("scrobbleFilter", "")),
                      "libraries": list((was or {}).get("libraries", []))}
            if record["isAdmin"]:
                record["libraries"] = list(LIBRARIES)
            if was is None:
                #? a PUT to an id it doesn't have: the UPDATE matches nothing, so it INSERTS
                self.passwords[target_id] = ""
                self.epochs[target_id] = 0
            self.accounts[target_id] = record
            if body.get("password") and not self.ignore_password:
                self.passwords[target_id] = str(body["password"])
                self.epochs[target_id] += 1
                if target_id == account["id"]:
                    #? (2.0.2) the refreshed JWT of your own password change carries the bumped epoch, as Navidrome's
                    #? does (server/nativeapi/user_password_token_refresh_test.go); every older one is dead
                    refreshed = {"X-ND-Authorization": self.jwt(self.accounts[target_id], line)}
            return answer(200, dict(record))
        if request.method == "DELETE" and target_id:
            if not admin:
                return answer(403, denied)
            if self.refuse_delete:
                return answer(500, {"error": "database is locked"})
            gone = self.accounts.pop(target_id, None)
            if gone is None:
                return answer(404, {"error": f"user(id:{target_id}) not found"})
            self.cascades.append({"user": gone["userName"], "took": ["play counts", "ratings", "stars", "playlists",
                                                                   "play queue", "players", "shares", "scrobbler links"]})
            return answer(200, {})
        return answer(405, {"error": "method not allowed"})
