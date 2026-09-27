"""
The album folder's name, from a template (v0.9.17, one of the 1.0 features).

`ALBUM_FOLDER_TEMPLATE` names the ALBUM folder only - `{artist}/` above it stays the artist's
name, because the artist page, re-filing an artist, the disc merge and the metadata queue all
rely on albums sitting directly inside an artist folder. The default is exactly the name deadwax
has always written, so nothing already filed changes unless the setting does.

A template has to work in BOTH directions, which is most of this module:

- `render_album_folder` fills it in. A token that comes out empty takes the brackets around it
  with it - `Album ({year})` for an undated album is `Album`, not `Album ()` - which is what
  lets one template cover an album with an edition and one without.
- `edition_from_folder` reads the edition back OUT of a folder name. The scan shows an album's
  edition from its folder (for anything deadwax filed it is the label the user already sees), and
  the "folder off-convention" check rebuilds the expected name from the tags plus that edition -
  so under a template that moved the edition, a reader that only knew the old `[...]` suffix
  would flag every album in the library.

Pure: no config read, no filesystem. organizer.album_folder_template() is where the setting is.
"""

import re

#? the default, and exactly the convention deadwax has always filed by
DEFAULT_ALBUM_FOLDER = "{album} ({year}) [{edition}]"

#? what a template may use, and what each means - shown in the settings tab
TOKENS: dict[str, str] = {
    "album": "the album title",
    "artist": "who the album is by, in their current name",
    "year": "the album's own year (its first release), which is what the folder has always used",
    "release_year": "this pressing's year - a 2011 remaster says 2011",
    "edition": "the edition, when there is one to tell pressings apart: Deluxe edition, 2011 remaster",
    "format": "the release's format: CD, 12\" Vinyl, Digital Media",
    "country": "the release's country: GB, US, JP",
    "catalog": "the catalogue number",
}

_TOKEN = re.compile(r"\{(\w+)\}")
#? a token inside a bracket pair, and the whitespace before it - removed whole when it's empty
_WRAPPED = re.compile(r"(\s*)([(\[{])\{(\w+)\}([)\]}])")


def validate_template(template: str | None) -> str | None:
    """Why this can't be an album folder template, or None when it can."""
    text = (template or "").strip()
    if not text:
        return "a template can't be empty"
    if "/" in text or "\\" in text:
        return "it names the album folder only - the artist folder above it stays the artist's name"
    if ".." in text:
        return "it can't contain '..'"
    unknown = sorted({t for t in _TOKEN.findall(text) if t not in TOKENS})
    if unknown:
        return f"unknown {'tokens' if len(unknown) > 1 else 'token'}: {', '.join('{' + t + '}' for t in unknown)}"
    if "{album}" not in text:
        return "it needs {album} - without it, two albums by one artist could share a folder"
    if _TOKEN.sub("", text).count("{") or _TOKEN.sub("", text).count("}"):
        return "a { or } that isn't part of a token"
    return None


def render_album_folder(template: str, values: dict[str, str], discriminator: str = "") -> str:
    """
    Fill the template in. `values` are already-cleaned strings per token ('' when unknown).

    `discriminator` keeps two genuinely different releases apart when they would otherwise
    produce the same name (organizer.resolve_album_dir supplies it after seeing a collision).
    It joins the edition when the template has one, as it always did - `[Deluxe - 5b6c1a2d]` -
    and is appended in brackets when it hasn't, because a collision must never go unresolved.
    """
    values = {k: (v or "").strip() for k, v in values.items()}
    if discriminator:
        if "{edition}" in template:
            values["edition"] = " - ".join(p for p in (values.get("edition", ""), discriminator) if p)

    def wrapped(match: re.Match) -> str:
        space, opening, token, closing = match.groups()
        value = values.get(token, "")
        return f"{space}{opening}{value}{closing}" if value else ""

    text = _WRAPPED.sub(wrapped, template)
    text = _TOKEN.sub(lambda m: values.get(m.group(1), ""), text)
    #? what an empty BARE token leaves behind: doubled spaces, a dangling " - " at either end
    text = re.sub(r"\s{2,}", " ", text).strip()
    text = re.sub(r"^[\s\-–·,]+|[\s\-–·,]+$", "", text)

    if discriminator and "{edition}" not in template:
        text = f"{text} [{discriminator}]"
    return text


def folder_pattern(template: str) -> re.Pattern:
    """
    A regex that reads a folder name back into its tokens, made from the same template.

    A bracketed token is optional - render dropped it when it was empty - and everything else is
    literal. Tokens are non-greedy and the match is a FULL match, which is what splits
    `Album (Live) (1994)` at the right bracket: the year group must end the name.
    """
    parts: list[str] = []
    position = 0
    seen: set[str] = set()

    def group(token: str, closing: str = "") -> str:
        #? inside brackets a token can't run past its own closing one - which keeps the last
        #? `[...]` the edition in `Album (1994) [A] [B]`, as the old suffix reader had it
        body = f"[^{re.escape(closing)}]+?" if closing else ".+?"
        #? a token used twice can only be captured once
        if token in seen:
            return body
        seen.add(token)
        return f"(?P<{token}>{body})"

    for match in re.finditer(rf"{_WRAPPED.pattern}|{_TOKEN.pattern}", template):
        parts.append(re.escape(template[position:match.start()]))
        if match.group(3):  # a wrapped token
            space, opening, token, closing = match.group(1), match.group(2), match.group(3), match.group(4)
            parts.append(f"(?:{re.escape(space)}{re.escape(opening)}{group(token, closing)}{re.escape(closing)})?")
        else:
            parts.append(group(match.group(5)))
        position = match.end()
    parts.append(re.escape(template[position:]))
    return re.compile("".join(parts))


def edition_from_folder(template: str, name: str) -> str:
    """
    The edition a folder name carries under this template, or '' - for a template without
    {edition}, or a folder that doesn't follow the template (one from before it changed, or
    from another tool).
    """
    if "{edition}" not in template:
        return ""
    match = folder_pattern(template).fullmatch(name)
    return (match.group("edition") or "").strip() if match else ""
