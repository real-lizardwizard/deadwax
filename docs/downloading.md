# Downloading

**Find**, on a pressing or an album, opens the **Soulseek candidates** panel. It searches
Soulseek through slskd, ranks every folder that comes back, and lets you download the one you
want. The **Downloads** panel then follows it until it's filed.

## The search it runs

The query is the artist and the album title. It's searched under **every name the artist goes
by**, because a sharer's folder is named however the album was credited when they got it:

- the name on the release (the credit, as in "Kanye West" on *Donda*);
- the artist's current name ("Ye"), which is what deadwax files under;
- former names MusicBrainz marks as ended.

The searches run side by side, so an artist with two names costs barely more than one. The
**Query** box shows the first query; hover over it to see the others. Edit the query and
press **Re-search** (or Enter) to search for exactly what you typed instead. An unedited
**Re-search** searches every name again. How long each search waits for answers is
`SLSKD_SEARCH_TIMEOUT`, 8 seconds by default.

Close the panel or start another **Find** mid-search, and the search is stopped in slskd as
well: only the newest search's answer is ever shown.

## Reading a candidate

Each row is one folder on one user's share:

- **The score**, 0 to 100, is how well the folder matches the release you picked. Green is
  good, yellow is middling, red is poor. How it's worked out is in
  [How matching works](matching.md).
- **The folder's name**, and below it the **user**, how many **files**, the **format and
  quality** (`flac 24-bit 96kHz`, `mp3 320kbps`, with ranges when files differ, and `VBR` for
  variable bitrate), and the folder's total **size**.
- **Peer speed.** `peer avg 1.2 MB/s` is the user's own average upload rate over their whole
  history, shared between everyone they're serving; it isn't a prediction. When you've
  downloaded from this user before, **the rate you actually got** is shown first, in green. A
  **free slot** means they'll start sending straight away; otherwise **queue N** is how many
  people are ahead of you.
- **Edition words** found in the folder's name (REMASTER, DELUXE, …).
- **Signal chips**, the score broken down: titles, count, lengths, edition, format, peer.

![The candidates panel for Dummy: each folder's score, its user, format and size, the peer's speed and slot, and the six signal chips](../assets/images/candidates.png)

## Narrowing the list

- **Free slot only** and **Complete albums only** hide busy peers and folders missing tracks.
- **Min score** hides anything below a score.
- **Format chips** (flac, mp3, …) show only those formats. They're built from what the search
  found.
- **Signals** sets a minimum for each part of the score separately. The number on the button
  counts how many are set.
- **Quality** sets floors: a minimum **bitrate**, **bit depth** and **sample rate**, and an
  album **size** range in MB. A folder is judged by its *worst* file, and a folder whose files
  don't report a value doesn't pass a floor for it, with one exception: a lossless folder
  passes any bitrate floor, because lossless beats any lossy bitrate.
- **Sort**: best match, highest quality (lossless first, then bit depth, sample rate and
  bitrate), largest, or smallest.

The filters' starting values, and the sort, are set in Settings → Downloads.

## Downloading

Press **Download** on a row. The folder's audio files are queued in slskd, and a row appears in
the Downloads panel **straight away**, reading "asking slskd…" while slskd looks the user up
and connects. That can take several seconds for a firewalled peer. If slskd refuses (the user is
offline, say), the row says so in slskd's own words.

Only the audio is downloaded. The rest of the list is kept with the download, in the order
you were looking at it, for **Try next peer** (below).

**Auto-grab** (Settings → Downloads) downloads the top candidate by itself on a new **Find**,
when it scores 75 or more. The panel says when it has done so.

## The Downloads panel

The **Downloads** button (top right) opens the list, with a badge counting what's still going.
Each download shows the album, the user, a progress bar, and a line of detail: files done out of
files wanted, **queue #N** while waiting in the user's queue, and the live download speed.

| status | means |
| --- | --- |
| queued | slskd has it, and it's waiting for the user to start sending |
| downloading | files are arriving |
| complete | every file arrived, and organizing hasn't started yet |
| organizing | being tagged and filed |
| organized | filed into your library (or, in dry run, checked) |
| failed | it stopped for good, and the line says why |
| cancelled | you cancelled it |

When a download is filed, the library tab picks the new album up by itself.

![The downloads panel: downloading, queued at #4, failed with the next peer offered, and organized](../assets/images/downloads.png)

### When a download fails

The reason is shown on the row: the user refused the transfer, stopped responding, the transfer
errored, or slskd never reported the transfers at all (after about two minutes of looking).

**↻ next peer** moves the download to the next user from the list you picked it from,
skipping any user already tried. It asks up to three in turn until one accepts, and the row
then reads **try 2**, **try 3** and so on. The old attempt's transfers are cleared out of
slskd. The button disappears when there's nobody left to try. With `AUTO_RETRY_PEER` on, this
happens by itself when a download fails.

### Cancelling

**✕** on a running download cancels it (with a confirmation, unless you've turned that off).
The row shows "cancelling…" at once, and the transfers are removed from slskd's own list too.
If `SLSKD_INCOMPLETE_PATH` is set, the half-finished file slskd was writing is deleted as well;
otherwise slskd keeps it, which is its normal behaviour.

**Clear finished** removes finished, failed and cancelled downloads from the list.

## The event log

The **Log** button shows what's happening behind the scenes: searches, how many answers came
back, queueing, filing, and anything that went wrong, with slskd's or MusicBrainz's own words
where there are any. A badge counts warnings and errors you haven't seen.
