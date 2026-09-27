# Troubleshooting

By symptom. Two places answer most questions before anything else: **Settings → Library**,
which checks every path from inside the container and says whether organizing is ready and what's
stopping it, and the **Log**, which has the reasons behind anything that failed, in slskd's or
MusicBrainz's own words where there are any.

## Downloads finish, but nothing appears in my library

In order of likelihood:

1. **Organizing is in dry run.** It's the default. The log says where each file *would* have
   gone. Set `ORGANIZE_MODE` to `copy` or `move` in Settings → Library → Organizing.
2. **`/downloads` isn't slskd's downloads folder.** The host folder mounted at `/downloads` has
   to be the same one slskd writes finished downloads into. If they differ, the files are
   downloaded but deadwax can't find them. Compare the two containers' volume lines. See
   [the three folders](getting-started.md#the-three-folders).
3. **`LIBRARY_PATH` isn't set, or isn't writable.** Settings → Library shows whether it
   exists and can be written, as the container sees it. A path that exists on the host but
   isn't mounted into the container looks perfectly correct from outside.
4. **Permissions.** Files are written as `PUID`/`PGID`. If the library folder belongs to someone
   else, writing fails and the log says so.
5. **The album was already there.** A track is never written over one of the same name, so a
   second copy of an album is skipped, and the download says so.

## The slskd pill is red

- **`CONNECTION_ERROR`**: slskd can't be reached at `SLSKD_URL` from inside the container. Use
  the address the *container* would use (`http://slskd:5030` on a shared Docker network), with
  the `http://`.
- **`NOT_LOGGED_IN` / `NOT_CONNECTED` / `CONNECTING`**: slskd is running but isn't signed in
  to Soulseek. Check slskd's own page. If slskd runs behind a VPN container, it may be waiting
  for the VPN, and the pill says so.
- **`401`**: slskd rejected the API key. Check `SLSKD_APIKEY` against the key in slskd's
  configuration.
- **`UNKNOWN_HTTP_ERROR` / `UNKNOWN_ERROR` / `UNEXPECTED`**: slskd answered with something
  unexpected. The log has the details.

## The MusicBrainz pill is red

- **`VALUE_ERROR`**: no contact is set. Set `MUSICBRAINZ_EMAIL` (Settings → Connections).
- **`CONNECTION_ERROR` / `MAX_RETRIES_EXCEEDED` / `UNKNOWN_ERROR`**: MusicBrainz couldn't be
  reached, or kept failing. It goes away for minutes at a time now and then (below); if it
  persists, check the container can reach the internet.

## A search fails with "not logged in", or slskd refused it

Searches are refused while slskd isn't signed in to Soulseek; it answers with a `409`, which the
panel explains. It also runs one search at a time, so a search started while another is still
running can be refused with "Only one concurrent operation is permitted": wait and search again.

## A search finds nothing

- Soulseek only returns folders whose paths contain **every word** of the query. Edit the
  **Query** to fewer words (the album title alone, say) and **Re-search**.
- Try a longer `SLSKD_SEARCH_TIMEOUT` (Settings → Downloads): slow and firewalled peers answer
  last.
- The panel says every name it searched under; hover over the query box to see them.

## A download sits at "queued"

It's waiting in the user's upload queue: **queue #N** says how far back you are. A user with a
**free slot** starts straight away. If slskd stops reporting the transfers altogether, the
download fails after about two minutes. Use **↻ next peer** to move it to someone else.

## MusicBrainz is slow, or searches fail

MusicBrainz goes slow or unreachable for minutes at a time, sometimes taking 30-60 seconds a
request. A failed search says it couldn't reach MusicBrainz, which is different from finding
nothing. Try again in a minute. Set `MUSICBRAINZ_EMAIL`: without a contact address, MusicBrainz
may throttle or refuse requests, and the log says so.

A search MusicBrainz rejects as invalid (odd punctuation in a fielded search) says so at once,
rather than retrying.

## The library tab is empty, or doesn't show a change

- **"LIBRARY_PATH is not set"**: set it (Settings → Library → Paths) and mount the folder.
- **An empty library** when you know it isn't empty usually means the volume isn't mounted in
  the container. Settings → Library shows whether the path exists.
- **A change made by another program doesn't show up**: tags edited elsewhere don't change a
  folder's date, which is what the library watches. Press **Rescan**.

## Lots of albums say "Folder off-convention"

Their folder names don't match what the template makes from their tags: albums filed by
another tool, or filed before you changed `ALBUM_FOLDER_TEMPLATE`. Changing the template never
moves anything. Applying the album's release in the metadata editor re-files it.

## No cover, or "No cover on the Archive"

The Cover Art Archive has no front cover for that release. It's a fact about the release, not
a failure. Pick a different release in the metadata editor if a sibling pressing has one. If it
says the request **failed**, the Archive was unreachable; try again later.

## Lyrics are missing, or land late

- LRCLIB doesn't have every song, and instrumentals get no `.lrc` by design. When LRCLIB is under
  load it asks clients to back off, and a track is retried a few times before it's counted as
  failed; **Get lyrics** tries again.
- If lines light up a beat after they're sung, set `LYRICS_LEAD_MS` (try `300`) and press
  **Re-time saved lyrics**.

## A song shows a different picture from its album

Your player is showing a picture embedded in the file, or a disc scan (`cd.jpg`) for songs with a
disc number. The album's **Properties** list which tracks carry their own pictures, and the
track view shows them. **Get CD art** saves a proper `disc.jpg`, which Navidrome prefers over a
`cd.jpg`.

## The artist page can't work out who this is

When the files have no MusicBrainz artist ids and the name is shared by more than one artist,
the page asks you to choose, with each one's description. Choosing one uses its id from then on.

## Settings I changed in compose don't take effect

A value saved in the settings tab **overrides** compose and `.env`, and the row says so. Press
**Revert** on it to go back to the compose value. Also check you didn't write
`SETTING=${SETTING}` in `environment:`, which quietly sets it to empty when compose has no such
variable of its own; the log warns about this at start-up.

## The page looks wrong after an update

Reload it. The page is never cached without checking, but a tab left open across an upgrade
keeps the old page until it's reloaded.
