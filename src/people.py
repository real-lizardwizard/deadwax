"""
People's rules (2.0.0-player.61) - PURE: no I/O, nothing asked of Navidrome or the database. What a new
account's name, display name and password must be, which changes People refuses for whom (`refusals`), and
what the page is sent of each person (`person`, `known_only`). src/routes/people.py asks Navidrome and the
store, and decides with these; ui/src/lib/people.ts mirrors the name and password rules for typing feedback
(tests/test_people.py holds the two to one), but the server decides.

THE GUARDS mirror Navidrome - which lets any admin change any other, and guards nothing else - and add
deadwax's own safety rules, first match winning (`refusals`):

  - logins off, or the break-glass sign-in: People needs a Navidrome sign-in to ask Navidrome as;
  - NAVIDROME_USER: changing it would cut deadwax off from what is nobody's in particular;
  - yourself: Navidrome's own UI won't delete you, and demoting yourself mid-task is never what was meant -
    nor is a password changed here (it needs your current one: since 2.0.2 that is You > Change password,
    src/routes/own_password.py, which keeps this device signed in);
  - the LAST Navidrome admin, unmade or removed: an install with no admin can only be fixed from Navidrome's
    command line. (You can't change yourself, and you are an admin, so this can't trigger through People
    today; it is kept as belt and braces.)
  - everyone else - another admin included, as Navidrome allows - is allowed; a reserved name only in
    Navidrome (deadwax keeps nothing for `local` or `deadwax` to forget).
"""

import re
import unicodedata
from datetime import datetime, timezone

#? A user name People makes: lowercase letters, digits, dot, underscore, hyphen - 1 to NAME_MAX, starting
#? with a letter or digit. deadwax's identity is the lowercased name and Navidrome matches names whatever
#? their case, so making them lowercase from the start avoids "James"/"james"; the small set rules out
#? whitespace, look-alike letters and anything awkward in a log line. Keep in step with ui/src/lib/people.ts.
NAME_PATTERN = r"^[a-z0-9][a-z0-9._-]{0,31}$"
NAME_MAX = 32
DISPLAY_MAX = 64
#? Navidrome has no password rule at all; 8 stops "1234" without getting in a household's way
PASSWORD_MIN = 8
PASSWORD_MAX = 128

#? How long a name the page is sent may be, at most
SHOWN_MAX = 64

_NAME = re.compile(NAME_PATTERN)

#? The guards' words, as the page shows them
NEEDS_LOGINS = "People needs logins on - with them off, anyone who can reach deadwax is its admin."
BREAK_GLASS = ("The break-glass sign-in has no Navidrome account, so People can't ask Navidrome as you - sign in "
               "with your own account.")
SHARED_ACCOUNT = "That's deadwax's own account (NAVIDROME_USER) - deadwax would lose its way into Navidrome."
YOUR_PASSWORD = "That's you - change your own password in You → Change password."
YOUR_ACCOUNT = "deadwax doesn't remove the account you're signed in with."
YOUR_ROLE = "You can't take away your own admin role."
YOUR_PERMISSIONS = "That's you - an admin has every permission."
LAST_ADMIN = "{user} is Navidrome's last admin - make someone else one first."
ADMIN_PERMISSIONS = "Admins have every permission - that changes with Make admin."
RESERVED_PERMISSIONS = "deadwax keeps that name for itself - nobody signs in to deadwax as it."


def _control(text: str) -> bool:
    return any(unicodedata.category(ch) in ("Cc", "Cf", "Zl", "Zp") for ch in text)


def clean_name(typed: str) -> str:
    """A user name as People makes it: trimmed and lowercased."""
    return (typed or "").strip().lower()


def name_problem(name: str, reserved: frozenset[str] | set[str]) -> str | None:
    """Why `name` (already cleaned) can't be a new account's - or None."""
    if not name:
        return "Type a user name."
    if len(name) > NAME_MAX:
        return f"A user name is at most {NAME_MAX} characters."
    if not _NAME.match(name):
        return ("A user name is lowercase letters, digits, dots, underscores and hyphens, starting with a letter "
                "or a digit.")
    if name in reserved:
        return f"'{name}' is a name deadwax keeps for itself - choose another."
    return None


def clean_display(typed: str) -> str:
    return (typed or "").strip()


def display_problem(display: str) -> str | None:
    """Why a display name (already cleaned) won't do - or None. Empty is fine: it means the user name."""
    if len(display) > DISPLAY_MAX:
        return f"A display name is at most {DISPLAY_MAX} characters."
    if _control(display):
        return "A display name can't have control characters in it."
    return None


def password_problem(password: str, again: str, name: str) -> str | None:
    """Why `password` won't do for the account `name` - or None. Never trimmed."""
    if len(password) < PASSWORD_MIN:
        return f"A password is at least {PASSWORD_MIN} characters."
    if len(password) > PASSWORD_MAX:
        return f"A password is at most {PASSWORD_MAX} characters."
    if _control(password):
        return "A password can't have control characters in it."
    if name and password.lower() == name.lower():
        return "A password can't be the user name."
    if password != again:
        return "The two passwords aren't the same."
    return None


def shown(text) -> str:
    """A name as the page is sent it: text, at most SHOWN_MAX characters."""
    return str(text or "")[:SHOWN_MAX]


def last_admin(admins: set[str], target: str) -> bool:
    """Whether taking `target`'s admin role away (or the account) would leave Navidrome no admin: the fresh list's
    admins, less the target, are none."""
    return not (set(admins) - {target})


def refusals(actor: str, target: dict, ctx: dict) -> dict[str, str | None]:
    """
    What People refuses to do to `target` ({"user", "admin"} - the account as Navidrome answered just now), asked
    by `actor`: for each of reset, remove, admin (make or unmake) and permissions, the words - or None, allowed.
    `ctx`: {"logins": bool, "break_glass": bool, "shared": NAVIDROME_USER lowercased, "admins": the fresh list's
    admins (lowercased), "reserved": the reserved names}. First match wins.
    """
    user = (target.get("user") or "").lower()
    is_admin = bool(target.get("admin"))
    if not ctx.get("logins"):
        return dict.fromkeys(("reset", "remove", "admin", "permissions"), NEEDS_LOGINS)
    if ctx.get("break_glass"):
        return dict.fromkeys(("reset", "remove", "admin", "permissions"), BREAK_GLASS)
    if ctx.get("shared") and user == ctx["shared"]:
        return dict.fromkeys(("reset", "remove", "admin", "permissions"), SHARED_ACCOUNT)
    if user == actor.lower():
        return {"reset": YOUR_PASSWORD, "remove": YOUR_ACCOUNT, "admin": YOUR_ROLE, "permissions": YOUR_PERMISSIONS}
    last = is_admin and last_admin(set(ctx.get("admins") or ()), user)
    said = LAST_ADMIN.format(user=user)
    return {
        "reset": None,
        "remove": said if last else None,
        "admin": said if last else None,
        "permissions": (RESERVED_PERMISSIONS if user in (ctx.get("reserved") or ()) else
                        ADMIN_PERMISSIONS if is_admin else None),
    }


def person(account: dict, facts: dict | None, ctx: dict, actor: str, ticked: dict | None) -> dict:
    """
    One row of People's list: the account as Navidrome lists it, joined with what deadwax knows of it (`facts`:
    store.people_facts' row) and what an admin ticked for it (`ticked`) - never its email, Navidrome's login
    times, or anything about its password.
    """
    user = (account.get("userName") or "").lower()
    target = {"user": user, "admin": bool(account.get("isAdmin"))}
    facts = facts or {}
    libraries = account.get("libraries")
    return {
        "id": account.get("id"),
        "user": shown(user),
        "name": shown(account.get("name") or user),
        "admin": target["admin"],
        "shared_account": bool(ctx.get("shared")) and user == ctx["shared"],
        "reserved": user in (ctx.get("reserved") or ()),
        "you": user == actor.lower(),
        "signed_in": int(facts.get("signed_in") or 0),
        "last_sign_in": facts.get("last_sign_in"),
        "library": int(facts.get("library") or 0),
        "waiting_alone": int(facts.get("waiting_alone") or 0),
        "libraries": len(libraries) if isinstance(libraries, list) else None,
        "permissions": ticked,
        "can": refusals(actor, target, ctx),
    }


def known_only(known: dict[str, dict], listed: set[str]) -> list[dict]:
    """The names deadwax keeps something for that the fresh list has no account for, by name - each with what is
    kept (store.known_users' row). Reserved names never: store.known_users leaves them out."""
    return [{**{key: value for key, value in facts.items() if key != "user"}, "user": shown(user)}
            for user, facts in sorted(known.items()) if user not in listed]


#? Navidrome's createdAt as Go writes a time.Time (RFC 3339, up to nine digits of fraction)
_CREATED = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})$")
#? Before this, a createdAt is Go's zero time (a record written back without one) - known to be no date at all
_EARLIEST = datetime(2000, 1, 1, tzinfo=timezone.utc).timestamp()


def made_at(account: dict) -> float | None:
    """
    (2.0.0-player.61 review) When Navidrome says an account was made (its `createdAt`), as epoch seconds - None
    when it says nothing usable (missing, not RFC 3339, or Go's zero time). What People's heal binds sessions by:
    only those begun since the account was made can be its own, so an account removed and made again under the
    same name never has an earlier one's sessions handed to it - and with None, none is healed (fail closed).
    """
    found = _CREATED.match(str(account.get("createdAt") or ""))
    if not found:
        return None
    whole, fraction, zone = found.groups()
    try:
        at = datetime.fromisoformat(whole + (fraction or "")[:7] + ("+00:00" if zone == "Z" else zone)).timestamp()
    except ValueError:
        return None
    return at if at >= _EARLIEST else None
