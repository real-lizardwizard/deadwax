# Artist names, credits and renamed artists

Credits and their ids, renamed artists, and searching Soulseek under every name.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Artists who have renamed (v0.6.18)

James: "so Ye shows up as Kanye, that seems like a gap somewhere" - and then "I want to make
sure there won't be a ye folder and a kanye folder ... there should just be one folder with the
most up-to-date name".

- **MusicBrainz keeps ONE current name per artist and every other name as an alias, while each
  release keeps the name it was CREDITED under.** Those two disagree for everyone who has ever
  renamed, and deadwax writes the credit into the tags and the folder - rightly, the album
  really was credited that way - so **the name on disk is the one MusicBrainz no longer answers
  to**. Ye is credited "Kanye West" on all but two of his own albums.
- **`artist:"..."` matches the current name ONLY.** Measured against the live API:
  `artist:"Kanye West"` returned "Kanye West Tribute Band" (score 100) and "Kanye West &
  Hatsune Miku", and **Ye was not in the answer at all**. So the artist page could not resolve
  him, and the picker's search box - the documented escape hatch for exactly this - offered a
  tribute band as the first thing to click. `artist_query()` asks
  `(artist:"X" OR alias:"X")` now, which puts Ye back at 100. Bracketed, so anything ANDed on
  later cannot split the OR - the same trap as the type filter.
- **The exactness test had to learn the same thing, and the query alone would not have been
  enough.** `_resolve_artist_mbid` compared against `a["name"]`, which is "Ye" - so even with
  the artist found, "Kanye West" != "Ye" and it still refused. `answers_to()` compares against
  every name they go by (name, sort-name, aliases). **This makes the guard refuse MORE often,
  not less**: a second artist answering to the same name fails the `len(exact) == 1` test
  exactly as two bands called Nirvana always did. Verified live - Nirvana and Cat Stevens (the
  musician and a photographer) are both still refused and offered as a choice.
- **How a name was TYPED is not a difference.** MusicBrainz sets names properly: JAY-Z is
  `JAŸ‐Z` and is credited `Jay‐Z`, both with a U+2010 HYPHEN, while any folder a person typed
  has a plain hyphen-minus. MusicBrainz's own index folds this (it answers the search at score
  100); only our comparison missed. `_fold()` strips combining marks and maps the dash and
  quote families to ASCII before comparing, so `Motorhead` finds Motörhead and `Bjork` finds
  Björk. It is still WHOLE names only - "Bjork Gudmundsdottir" matches nothing - because the
  refusal-on-ambiguity guard is what makes an automatic match safe at all.
- **The match rows carry `matched_as`**, the name that matched in its own spelling, and the
  picker shows it when it differs from the artist's current name. Search for Kanye West, get an
  artist called Ye, and without it nothing on screen connects the two.
- **The artist page says "Now" when MusicBrainz calls them something else** than your folder
  does. Rendered only on a difference - unconditionally it would print the folder's own name on
  the page twice.
- **`facts["aliases"]` no longer lists the artist's own name**, and ranks MusicBrainz's "Artist
  name" aliases ahead of its "Search hint" ones (which are deliberate misspellings, there to be
  found by). It read "Ye, KanYeWest, Donda, Kanye, K. West, Kayne West" - their own name, then
  two typos, before "Kanye West" ever appeared. It reads "Kanye West, カニエ・ウェスト, Kanye,
  Yeezy" now.
- **An album is FILED under its artist's current name, and the credit stays where it is read.**
  Filing by the credit gave one artist a folder per name: Donda (credited "Kanye West") went to
  `Kanye West/` and BULLY (credited "Ye") to `Ye/` - and the library tree, which groups on the
  albumartist tag, showed two artists too. MusicBrainz carries both names in every credit:
  `artist-credit[].name` is the sleeve, `artist-credit[].artist.name` is the artist now. So the
  payload carries both, and they go to different places on purpose:
  - `artist` - AS CREDITED. The Soulseek search is built from it and the matcher scores against
    it, because a sharer's folder is called "Kanye West - Donda", never "Ye - Donda". It is also
    the track `artist` tag (via each track's own credit), which is what the sleeve says.
  - `album_artist` - the CURRENT names, joined with the credit's own join phrases. It names the
    folder AND the `albumartist` tag, through `filed_artist()` in organizer.py.
  **Those two must move together**: `_is_misfiled` compares the folder with the album artist,
  so renaming only the folder would put every renamed artist's whole discography in the queue.
  **Verified with live MusicBrainz payloads through the real `credits.mjs`**: Donda, BULLY and
  The College Dropout all file under `Ye/`, while Soulseek still searches "Kanye West".
- **There are TWO ways a download starts, and the first cut of this missed one.** Find on a
  release ROW goes through `buildExpectedFromRelease`; Find on the release-group CARD goes
  through `buildExpectedFromReleaseGroup`, which builds its own payload from the group's
  context and had never carried anything but the credit - not even the artist ids, so a
  download started from a card was tagged with no `musicbrainz_albumartistid` at all. Every
  test passed with the gap open, because no test reaches main.js: it was found by clicking Find
  on a card in the real page and reading the request, which had no `album_artist`. The group
  context now carries `albumArtist` and `artistMbids` from the group's own credit. **Anything
  added to a download's payload has to be added in BOTH builders** - and checked by clicking
  both buttons, since only one of them is on the path any sim can see. **Superseded in
  2.0.0-player.15: there is ONE builder now, `ui/src/lib/releasePayload.ts`**, used by both of
  main.js's Finds (through the bridge's `buildDownloadRelease`) and the app's Get, and pinned by
  `ui/test/payload.sim.cjs` to the bodies the two Finds sent before the move - anything added to a
  download's payload goes THERE (see "Sources and Get").
  **Verified in the real page** (scratch database and library, slskd stubbed as logged out):
  both Finds send `artist: "Kanye West"` and `album_artist: "Ye"` with Ye's id; the row's
  carries all 32 tracks, each still credited "Kanye West".
- **`album_artist` is DECLARED on `EnqueueRelease` and `RetagRelease`** - the pydantic trap a
  third time (after `disc` and the track artist). A job queued before it existed has only
  `artist` and files exactly where it always would have; `filed_artist()` falls back.
- **The editor seeds its artist field with the current name when a release is PICKED**, so a
  correction lands where a fresh download of the same release would. Only then - an album's
  own release auto-selected on opening still seeds nothing, so opening the editor never
  rewrites what is on disk by itself. **This is the only way an album already filed under an
  old name moves**; nothing finds them automatically (see below).
- **...which broke the editor's own search, and had to be fixed with it.** `artist:` on a
  RELEASE GROUP matches the credit only, so once the field held "Ye", `releasegroup:"Donda" AND
  artist:"Ye"` could no longer find the Donda credited to Kanye West - measured, through
  deadwax's own client: the old query found 2 groups and not that one. `fieldedAlbumQuery()`
  asks `(artist:"X" OR artistname:"X")`, and `artistname:` is what matches the current name:
  10 groups, the real Donda among them. Without it every album filed by its current name could
  no longer find its own release group. The placeholder shows the same string.
  **Verified in the real editor** on a legacy `Kanye West/Donda (2021)`: opening it changed
  nothing, picking a release seeded "Ye" and previewed `Kanye West/Donda (2021) → Ye/Donda
  (2021)`, and re-searching with "Ye" in the field still listed Donda's releases.
- **The rule for the current name lives in TWO places, and a sim holds them to one answer**:
  `getCurrentArtistNames()` in `interface/scripts/credits.mjs` names a download's folder and
  `currentName()` in `ui/src/lib/release.ts` seeds the editor's. The credit helpers moved out
  of main.js into `credits.mjs` for this - main.js touches the DOM at module scope and cannot
  be imported by a test, the same reason `sort.mjs` exists - and `ui/test/credits.sim.cjs` asks
  every case of BOTH copies. If they drift, one album goes to one folder when downloaded and
  another when corrected. **Superseded in 2.0.0-player.15**: a download's folder now comes from
  release.ts's `currentName()` too, through `lib/releasePayload.ts` (the one payload builder), so
  a download and a correction are one function and can't part. credits.mjs's
  `getCurrentArtistNames()` is left only DRAWING - it is a name the main page's card tries for
  its "in your library" match - so a drift between the two copies now marks a card wrong and
  files nothing anywhere. The sim still asks both.
- **Collaborations still get their own folder**, in current names: Watch the Throne files under
  `JAŸ‐Z & Ye/`. That was always so (it was `Jay‐Z & Kanye West/`); only the names changed.
- ~~NOT built: finding albums already filed under an old name~~ **Built in v0.9.14** - the scan
  reads the album-artist ids and notices, and the artist page moves them. See "One artist under
  two names".

### Searching Soulseek under every name (v0.6.19)

James: "make sure the same logic with ye works with the slskd search".

- **The matcher never looks at the artist; the QUERY is the only place a name decides
  anything.** `score_candidate` scores tracks, count, durations, edition, format and peer - not
  one signal reads the artist - so a share filed as `Ye/` and one filed as `Kanye West/` score
  identically once found. Finding them is the problem: Soulseek needs EVERY word of a query in a
  share's path, so "Ye BULLY" cannot find `Kanye West/BULLY` at all, and "Kanye West Donda"
  cannot find `Ye/Donda`.
- **So it searches under every name a share might carry**: the CREDIT (what the album said when
  the sharer got it), the CURRENT name (what deadwax and Picard's standardised names file
  under), and FORMER names (what someone who never re-filed still uses). `search_names()` in
  routes/download.py orders and dedupes them; an artist who never renamed is exactly one search.
- **A former name is one MusicBrainz itself marks as former: an ENDED "Artist name" alias.**
  Ye's record says exactly that of "Kanye West" (ended 2024). The rest of his aliases are not
  folder names - "Kanye" and "Yeezy" are live nicknames, "Kanye Omari West" is a legal name, the
  zh/ja entries are other languages' spellings - and each name costs a Soulseek search, so
  `former_names()` is deliberately that narrow. Where editors never marked a name as ended there
  is nothing to find and it degrades to credit + current, never to worse. Single-artist credits
  only: a collaboration's names multiply, and its credit and current names are searched anyway.
- **The alias lookup runs BESIDE the first round of searches, not before it.** It is a
  MusicBrainz request, and MusicBrainz takes 30-60s on a bad day; looked up first, every search
  of every album would have waited on it. Beside the first round (credit + current, which take
  their full search timeout anyway), an artist who never renamed pays nothing even when
  MusicBrainz is slow. A former name the first round didn't already cover is a SECOND round -
  the only case that costs a second search's wait. `FORMER_NAMES_BUDGET_SECONDS` bounds the
  lookup; past it, the search goes on without former names. `get_artist_aliases()` is its own
  light request (`inc=aliases`) rather than the artist page's heavy one, and its own cache key.
- **The searches in a round run side by side** (`SlskdClient.search_all`). slskd's
  one-at-a-time limiter covers only STARTING a search - `StartAsync` returns once the search is
  under way - so the starts go strictly in turn and the waiting is shared: two names cost barely
  more than one. A refusal with nothing running is the answer (a logged-out slskd refuses every
  search alike, so the rest are not asked); a refusal once one IS running narrows the search and
  is logged, rather than failing it. `search(query)` is now the one-query case of this.
- **The same file can come back from two searches**, from a share whose path holds both names
  (`Kanye West/Ye - Donda`). `group_files_by_directory` keeps each (user, file) once - otherwise
  the album counts its tracks twice, scores on a count it doesn't have, and is enqueued with
  every file requested twice.
- **`FindCandidatesRequest` had been DROPPING `album_artist` and `artist_mbids`** since v0.6.18:
  the browser sent them and pydantic discarded them without a word - the trap a fourth time.
  Both are declared now.
- **Re-search only overrides when the query was EDITED.** The box shows the first of possibly
  several queries, and re-searching sent the box's contents as an override - so pressing it
  unchanged would have quietly searched one name of several. Hovering the box lists the others,
  and "no matches" says every name it tried. That message is built with `textContent`: the
  queries are MusicBrainz's names, third-party text. (The vanilla half has `esc()` since v0.9.22
  for what still goes in as markup; text is still the better way where it fits.)
- **Verified** over real HTTP against a stub slskd holding one share of BULLY filed under
  `Kanye West/`, which matches the way Soulseek does, with the alias lookup going to LIVE
  MusicBrainz: before, "Ye BULLY" and nothing; after, MusicBrainz gave "Kanye West" as a former
  name, the second round searched "Kanye West BULLY", and the share came back scoring 1.0.
  **NOT verified: a real Soulseek network.** Whether its matching tokenises the way the stub
  does is inferred from the S&M2 failure (see "Never take a word apart"), and whether a
  two-letter term like "Ye" is honoured, ignored or too broad is unknown.

### Artist credits, and the ids behind them (v0.6.15)

Asked for as "better handling for multi-artist albums and tracks", and "get artist ID in the
metadata as well".

- **A credit's JOIN PHRASES are its punctuation.** MusicBrainz says "A / B" for a split, "A & B"
  for a collaboration, "A feat. B" for a guest spot, and it says so in `joinphrase` between the
  names. Joining on ", " - which every part of this interface did - invents punctuation nobody
  chose and flattens a duet into what reads as two separate acts. The rule lives in TWO places
  that must agree: `creditName()` in `ui/src/lib/release.ts` and `getArtistNames()` in
  `interface/scripts/credits.mjs` (moved out of main.js in v0.6.18 so a sim can reach it). One
  names a folder, the other writes the tag inside it - both in the browser, which sends the
  server names already joined. (A third copy, `credit_name()` in `src/artists.py`, was called by
  nothing but its own tests and went in the v0.9.19 audit.) Since 2.0.0-player.15 a download's
  artist comes from release.ts's `creditName()` (through `lib/releasePayload.ts`), and
  credits.mjs's `getArtistNames()` only draws the main page's card credit; its `getArtistIds()`,
  which only the deleted builders used, went in the review.
- **A track keeps its OWN artist.** `tag_values` gave every track the release's artist, so
  applying a release to a compilation rewrote eighteen artists into one. The track's credit wins
  where it has one; `albumartist` stays the release's, which is what the two tags are for.
  **Until v1.0.10 that held for downloads only.** `execute_retag` rebuilt each track from its
  plan entry's title, number and disc, so the editor PREVIEWED each track's own artist and then
  wrote the release's on every one - Various Artists over a whole compilation. A plan entry now
  carries the matched `track` whole and the apply writes that. `test_credits.py` had tested
  `write_tags` alone, which is why it never showed; the new test goes through plan and apply.
- **The artist ids are written at last**: `musicbrainz_albumartistid` and `musicbrainz_artistid`.
  Nothing deadwax filed had ever recorded WHO an artist was, only which release - which is why
  the artist page has to fall back to searching by name at all.
- **One id is a string, several are a list**, and `read_current_tags` reads back the same shape.
  Get that wrong and a file disagrees with itself on every preview: a bare string on one side, a
  one-item list on the other, and an album that can never again say "nothing to change". Pinned
  by a round-trip test that writes a file and re-previews it.
- **`Track` in the download request declares `artist` and `artist_mbids`.** Same trap as
  `disc`/`disc_position` before it: pydantic drops undeclared fields without a word, so a
  compilation would arrive correct from the browser and be filed under one artist anyway.
