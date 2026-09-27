# Finding music

The **Search** tab looks up albums on MusicBrainz and lists every pressing of each. You choose
the exact one you want, and that's what the download is matched against and tagged as.

## Searching

Fill in either box or both:

- **Release title**: the album's name.
- **Artist name**: who it's by. With both filled in, the search asks for that album by that
  artist, which is far more precise than typing both into one box.

Then press **Search**, or Enter in either box.

- **Type** narrows what's asked for: albums, singles, EPs, or other, and **studio albums only**,
  which leaves out live albums, compilations, interviews, demos, remixes and DJ mixes. It
  narrows the *question* rather than hiding answers. MusicBrainz returns a limited number of
  results, so for a prolific artist most of them would otherwise be live albums and
  compilations. When a type filter is on, the button, the results summary and its tooltip all
  say so.
- **Limit** is how many albums to ask for (1-100). The default is set in Settings → Search.

## The results

Each result is a card for one album (a *release group*):

- the **cover**, **title** and **year**, and the **type** (Album, Single, Live, Compilation…);
- the **artist**. Tap or click the name to browse the artist's whole discography (below);
  the **↗** beside it opens the artist on MusicBrainz;
- a **match** percentage, MusicBrainz's own relevance score for your search. Green is a strong
  match; a faded card is a weaker one;
- **In your library** when you already hold some pressing of it, with a count of editions, or
  **Maybe in your library** (dashed) when a folder of that name exists but carries no MusicBrainz
  ids to prove it;
- **Find**, which searches Soulseek for the album as a whole (see below).

**Sort** orders the cards: year (oldest or newest first), best match, title or artist. Albums
with no known date go to the end whichever way the list runs.

## An artist's discography

A search can't answer "everything this artist released, in order": MusicBrainz answers in
relevance order and spends the limit on whatever matched, which for a well-known artist is
mostly bootlegs. So clicking an **artist's name** *browses* instead. It lists every album
credited to them, in the order **Sort** says (oldest first by default), with **studio albums
only** on to start with. **Back** returns to your search.

A browse stops at 500 albums, and says so if it did, so an enormous catalogue ("Various
Artists") isn't presented as complete.

## Every pressing of an album

Under each card is a list of its **releases**: every pressing MusicBrainz knows of. The best
match comes with them already fetched, marked **Specific releases (N)**; for the others, press
**Fetch releases**. MusicBrainz can take a few seconds, sometimes much longer on a bad day, and
the button shows it's working.

The list is a table on a desktop and one block per pressing on a phone. Its columns:
**Edition**, **Title**, **Format**, **Tracks**, **Status**, **Country**, **Date**, **Label**,
**Catalog#**, **Barcode**, **Quality**, **Language/Script** and **Disambiguation**. **Columns**
chooses which are shown. On a desktop, drag a column's header to move it and its edge to
resize it; the layout is remembered.

### What's different about each pressing

Above the list is **the tracklist most of the pressings share**, and each pressing then says
only what *it* changes:

- **The tracklist above**: this pressing is the shared one.
- **+1 track** / **−1 track**: bonus tracks, or missing ones.
- **1 other version**: a track that's a different recording (much longer or shorter), such as
  a single mix.
- **3 lengths**: tracks whose lengths differ slightly; rounding within 2 seconds doesn't count.
- An **edition** label, such as *ANNIVERSARY*, *REMASTER* or *DELUXE*, when the release names one.

Click (or tap) a pressing to see its changes in full, and click **Show this release's full
tracklist** for the whole thing, sides and discs included.

### Pressings you already have

A pressing whose MusicBrainz id matches an album in your library is marked **In your library**,
with a purple edge. The marks update by themselves when a download is filed while you're
looking.

## The filter column

On the left (behind **Show** on a phone), the filter column is built from whatever release
lists are open: every edition, format, status, country, label and so on that appears, with
counts. Click a value once to show **only** pressings with it, again to **exclude** it, and a
third time to clear it. The text box filters on anything in a row. **Clear** resets everything.
The results summary says how many pressings are shown out of how many were listed.

## Find: starting a download

There are two **Find** buttons, and the difference matters:

- **Find on a pressing's row** (recommended) searches Soulseek for that exact release, and ranks
  every folder found against **its real tracklist**: titles, count and lengths. When the
  download is filed, each track gets that release's title, number, disc and ids.
- **Find on the album card** searches for the album without a particular release. It's quicker
  when you don't mind which pressing, but there's no tracklist to compare against, so
  candidates are ranked on what's left (format, edition words, the peer), and the files are
  tagged with the album's details only.

Either opens the **candidates panel**; see [Downloading](downloading.md).
