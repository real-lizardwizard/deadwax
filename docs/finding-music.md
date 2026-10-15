# Finding music

The **Search** tab looks up albums on MusicBrainz and lists every pressing of each. You choose
the exact one you want, and that's what the download is matched against and tagged as.

This page is about the main page's Search tab first. The [phone app](player.md) has a Search tab
of its own, with one box that looks in your library first and then on MusicBrainz, and a page for
an album you don't have: see [On the phone](#on-the-phone-the-apps-search-tab).

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

![Dance Gavin Dance's eleven studio albums, oldest first](../assets/images/discography.png)

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

![Dummy's twenty pressings under the tracklist twelve of them share, the 2017 vinyl opened to show what it changes](../assets/images/search.png)

### Pressings you already have

A pressing whose MusicBrainz id matches an album in your library is marked **In your library**,
with a purple edge. The marks update by themselves when a download is filed while you're
looking.

**Find** on a pressing you already have complete, or one that's already downloading in full,
says so instead of searching Soulseek. See [when you already have it](downloading.md#when-you-already-have-it).

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
- **Find on the album card** is for when you don't mind which pressing. It picks one for you:
  a pressing with the album's most common tracklist, preferring an official CD or digital
  release, then the earliest. It then searches exactly as that pressing's own Find would. If the
  card hasn't listed its pressings yet, the button shows a sweep while it asks MusicBrainz, and
  if MusicBrainz can't answer, it falls back to searching for the album as a whole.

Either opens the **candidates panel**; see [Downloading](downloading.md). If the pressing is
already in your library, or already downloading in full, the panel says so and doesn't search.

## On the phone: the app's Search tab

The [phone app](player.md) at `/player/` has its own **Search** tab (since 2.0.0-player.13): one
box, **your library first, then MusicBrainz** - its songs (since 2.0.0-player.53: find a song, see the
albums it's on, open one on a pressing that has it) and its albums. Since 2.0.0-player.15 it gets albums too: **Get** on
a row of albums you don't have, or **Get the album** on an album's page, opens the sources found on
Soulseek to choose from - see [Get, and choosing a source](downloading.md#on-the-phone-get-and-choosing-a-source) -
and the app's Requests tab follows the download from there.

On a desktop (since 2.0.0-player.19; a window 1024 pixels wide or more) the box is the sidebar's
**search field**: typing there shows these results in the main area, and Enter asks both halves at
once, as **Search** on the keyboard does. An album you don't have shows its tracklist as a table there,
with an **Against the usual tracklist** column whenever any pressing differs - see
[the phone player guide](player.md#on-a-desktop).

### The box

Type an artist, an album, a song, or an artist and an album ("portishead third"), up to 200
characters. Each half is asked by itself:

- **Your library** is asked a fifth of a second after you stop typing.
- **MusicBrainz** is asked when you press **Search** on the keyboard, or 0.7 seconds after you stop
  typing once there are 3 characters or more - for its songs and its albums at the same moment. Fewer
  than 3, and it waits for Search: it says *Type a little more, or press Search, to ask MusicBrainz.* -
  and cutting the box back below 3 clears what MusicBrainz found for the longer text, songs and albums
  (and calls off a search still on its way), so nothing sits under words it doesn't answer.
  MusicBrainz allows about one request a second, so it isn't asked on every key.

Only the newest search is ever shown: an answer that arrives after you've typed something else,
and searched again, is dropped.

A search MusicBrainz was asked before is answered at once from deadwax's
[saved answers](configuration.md#musicbrainzs-saved-answers-settings--connections) (since
2.0.0-player.54), after a restart too - refreshed behind itself once it is a week old.

### In your library

Navidrome's own search of your library, in three parts:

- **Top result**: an artist whose name is exactly what you typed, with how many of their albums
  you have ("Artist · 2 albums in your library"). Tap it for [their page](player.md#artist-pages)
  (since 2.0.0-player.17).
- **In your library**: the other artists found (up to 5 in all, each opening their page), albums
  ("Album · Portishead · 1994"), which open the album, and songs ("Song · Portishead · Dummy"). Up
  to 8 albums and 12 songs.
- **A song** plays straight away, from that song through the rest of its album, once its album is
  in hand: as the answer arrives, the songs' albums are fetched - the first five different ones -
  and a song whose album has arrived shows a play mark (▶) at its right. Tap one without it, and
  its album opens instead, where Play is one tap away.

If nothing matches, it says *Nothing in your library matches "…"*. If Navidrome isn't set up or
can't be reached, this half says so (**Connect Navidrome** or **Can't reach Navidrome**, as Home
does) and MusicBrainz is still searched below it.

**With logins on** (since 2.0.0-player.52) this half is the **store** - Navidrome's search finds everything
deadwax holds - so it is titled **In the store**, each album row ends **· in your library** or **· in the
store** (yours: starred by you, or in your library), an artist's count is the store's ("Artist · 2 albums in
the store"), and the half below is **Not in the store yet**. With logins off, everything here is as
written - [the player as you](player.md#the-player-as-you-with-logins-on).

### Songs on MusicBrainz

Since 2.0.0-player.53, between your library and MusicBrainz's albums: the **songs** MusicBrainz has for
the box - for people who know a song but not the album it's on. They come first because a phone shows
them first, but only **three** of them, so when what you typed is an album's name the albums are still on
the screen under them. When no song matches at all, there's no songs section - the albums answer for what
you typed.

- **One row per song.** MusicBrainz keeps every performance of a song as a recording of its own - the
  studio take, each live tape, each re-recording - and finds them all equally well, in no useful order
  ("Roads" by Portishead is 45 recordings, Queen's "Bohemian Rhapsody" over 200). So every recording of
  one title by one artist is **one row**, its albums put together; a remix ("Roads (Monk & Canatella
  mix)"), or the same title by someone else, is a row of its own. A take titled "(live)" or "(Remastered
  2015)" counts as the song itself. Each row is the song's title, then who it's by, its length on the album
  it names and that album: "Roads · Portishead · 4:56 · Dummy". When you have the song - a pressing of one
  of its albums that it's on - the row names that album and ends **· in your library** (with logins on,
  **· in the store** when only the store has it). deadwax knows you have it when the pressing you hold is
  one MusicBrainz's answer lists the song on, when your library's own search - the half above - finds the
  song by that artist on that album, or when it already has the album's pressings from earlier (its page
  opened, say) and yours has the song in its tracklist. A pressing of the album without the song isn't
  having it: with The Slow Rush's usual CD in your library, Tame Impala's "Patience" (a bonus track on its
  Japanese CD alone) says nothing of the sort. A song MusicBrainz lists on no release at all isn't shown -
  there'd be nothing to get; when every song it found is like that, it says *MusicBrainz has songs for
  "…", but on no release yet - nothing to get.*
- **Tap a song** and it opens in place onto **the albums it's on**: albums and EPs first, then singles,
  each official release before a promotional one before a bootleg, the earliest first. Compilations,
  live albums, soundtracks, broadcasts and the rest wait behind one line saying what and how many there
  are - "On 24 compilations, live albums, broadcasts and other records" - which opens them, in the same
  order (a live radio or TV broadcast counts as a broadcast, not a live album). A song that's only on
  those (Elliott Smith's "Miss Misery") lists them at once, under those words. Each album says what it is
  and when ("Live album · Bootleg · 1997"), who it's by when that isn't the song's artist ("Compilation ·
  Various Artists · 2015"), the song's length there when it's another performance's ("· 5:36"), and **·
  in your library** when you have it with the song on it - **· a pressing in your library** when you have
  a pressing of it that nothing yet says has the song or hasn't (**· a pressing in the store** with logins
  on, when it's only the store's). That happens because MusicBrainz often keeps one song as several
  recordings across an album's pressings, and its answer names only some of them: Dummy's 1994 CD has Roads
  as a recording the first answer for "roads portishead" doesn't bring, while The Slow Rush's usual CD
  hasn't "Patience" at all. Tap the song again to close it.
- **Tap an album** you don't have and it opens as [the album you don't have](#the-album-you-dont-have),
  on a pressing that **has the song**, with the song marked - [below](#opened-from-a-song). Tap one you
  have the song on and it opens **the album you have**, as the Library would (while Navidrome hasn't found
  it, or can't be asked, the album you don't have, which says "in your library"). Tap one that says **a
  pressing in your library** and deadwax first fetches the album's pressings - the row looks busy meanwhile;
  the album's page would fetch them anyway, and keeps them - then opens the album you have when the
  pressing you hold has the song (the row then says **in your library** while the app keeps that album's
  pressings), and otherwise the album you don't have, on a pressing with the song, where Get is. If
  MusicBrainz can't list the pressings, it opens the album you don't have.
- **More songs**, under the rows, shows the rest of the songs MusicBrainz sent (25 recordings a request),
  then asks for the next 25 of the same search: a later take of a song already listed adds its albums to
  that row, and new songs come after the others (a song whose earlier takes were on no release among
  them), so nothing you were looking at moves. It reads **Asking
  MusicBrainz…** while it asks, and says when a page brought only albums ("No new songs - 7 more albums
  for the songs above.") or nothing (*MusicBrainz sent nothing new.*). No page starts more than 1,000
  answers in.

The box is read as it is for albums ([below](#not-in-your-library-yet)): a title beside an artist you
have is that song by them ("roads portishead" is Roads by Portishead), and if that finds nothing it's
asked again as the words you typed taken as **one title** - so a song whose title starts with the name of
an artist you have is still found - not the words loose, which would bring strangers' songs named after
the artist above an album's words. An **artist's name alone** asks for no songs - every
recording they ever made, in no useful order, is no answer to it; their albums are below. **Words with no
artist you have are matched against song titles only**, so a famous title alone mostly finds covers:
"hey jude" alone finds tribute bands and string quartets, and no Beatles in its first pages. Type the
artist too - an artist in your library is read as the artist. While it asks it says **Asking
MusicBrainz…**; if MusicBrainz isn't answering it says so, with its own **Try again**.

The albums below don't wait for the songs: they're drawn the moment MusicBrainz has answered for them,
as they always were. Songs that arrive after the albums are on the screen never push them down - they
stay folded in the line that was saying *Asking MusicBrainz…*, the same height, as a **Show songs**
button that opens them (or *No songs on MusicBrainz for "…"* when none matched, or *MusicBrainz isn't
answering.* with **Try again**, which opens the songs once they come).

### Not in your library yet

From MusicBrainz, 12 albums at a time, **leaving out any you already have** - judged by MusicBrainz's
own id for the album, so a folder deadwax filed as FLAC or MP3 (or one tagged by Picard) is
recognised. A folder with no MusicBrainz ids in its tags can't be, and nor can an **.m4a album
deadwax filed**: it carries the pressing's id but not the album's (Picard writes that one; deadwax
can't yet), so its album still shows here - its own page then says "in your library". To leave
those out the list waits a moment (a second and a half at most) for deadwax to say what you have,
showing **Asking MusicBrainz…** meanwhile; if deadwax answers later than that - the first time
after it restarts, when it looks through the whole library - a row it turns out you have stays
where it is and says "· in your library" at the end of its second line, rather than vanishing from
under your finger. Each row is the
cover (from the Cover Art Archive, so a phone with no internet shows a plain square), the title,
and what it is, who by and when ("Live album · Portishead · 1998"). Tap one to open
[the album you don't have](#the-album-you-dont-have). **Get**, at the end of the row, gets the
album's usual pressing without opening it (it reads "Get…" while it asks MusicBrainz for the
album's pressings, which an album opened before already has, and gives up if you type, open
something or switch tab meanwhile); a row that turns out to be in your library has none, and a tap
on it opens **the album you have** (since 2.0.0-player.17: deadwax looks up which album Navidrome
holds for the pressing you have) - or, while Navidrome hasn't found it, the album you don't have,
which says "in your library". To get **another pressing** of an album you have, open the album you
have and tap **Other pressings** ([below](#another-pressing-of-an-album-you-have)) - the list here
keeps to albums you haven't got, and an artist's page opens the albums you have as yours.

**More from MusicBrainz** (since 2.0.0-player.50), under the rows, asks for the next 12 of the same
search and adds them below, so nothing you were looking at moves - leaving out the albums you have, as
the first 12 do (and never showing one twice). It reads **Asking MusicBrainz…** while it asks; if
MusicBrainz isn't answering it says so and reads **Try again**. When every new album of the next 12 is
one you have it says so ("The next 12 albums MusicBrainz found are all in your library already"); when
MusicBrainz sends nothing it hasn't already shown you, it says *MusicBrainz sent nothing new.* The
button goes once MusicBrainz has nothing more for the search, and if it had keyboard focus, focus moves
to the first album the last page added (or to the words said in its place). No page starts more than
1,000 answers in; a search with more than that says *That's as far into one search as deadwax goes -
add a word to narrow it.* Typing something else, or searching again, drops a page still on its way.

How the box is read, since there's only one:

- **It starts or ends with an artist you have** (any folder in your library, by name, ignoring
  case, accents, a leading "The" and "&" against "and"): the rest is the album's title, and
  MusicBrainz is asked for that album by that artist, under the name they had then or have now.
  "portishead third" and "third portishead" both find Third. The longest name that fits wins, so
  "pink floyd the wall" is The Wall by Pink Floyd even if you also have Pink. A dash, colon or
  slash between the two is ignored ("portishead - third").
- **It is an artist you have**: their albums.
- **va**, or "various artists", is Various Artists, as the main page's artist box reads it.
- **Anything else** goes to MusicBrainz as you typed it.

[Songs on MusicBrainz](#songs-on-musicbrainz) read the box the same way - for a song by that title
instead of an album - except that an artist's name alone asks for no songs.

If reading it as an artist and an album finds nothing (an artist's name that happens to begin a
title), it's asked again as the words you typed. While it asks, it says **Asking MusicBrainz…**
with a moving bar. If MusicBrainz isn't answering - it often goes away for a few minutes - it says
so, with **Try again**; that's not the same as *Nothing on MusicBrainz for "…"*, which means it
answered and found nothing. *Everything MusicBrainz found is in your library already* means just
that.

### The album you don't have

It opens like an album you have: back, the cover in the middle (the Cover Art Archive's, for the
pressing shown, else for the album), the title, the artist (since 2.0.0-player.17 a link to
[their page](player.md#artist-pages) when the album is credited to one artist; a collaboration's
names stay plain), and "2008 · Album ·
not in your library" - "in your library" if you have some pressing of it after all (with logins on, "in
the store" when the store has a pressing of it but none is yours, and "another pressing in your library"
when one is but the pressing chosen is the store's - the line speaks of the album, the one under Get of
the pressing, so it never says "in your library" over **In the store, not in your library**; the
**Pressing** list marks each pressing **In your library** or **In the store**). That last part
appears once deadwax has said what you have, never before, so it can't claim you don't have an
album you do; and it counts a folder tagged with any of the album's pressings, the .m4a albums
above included. Since 2.0.0-player.50, when nothing is tagged as the album but a folder **with no
MusicBrainz ids at all** has its name and its artist's (as credited, or the name they go by now), it
says **maybe in your library**, in a dashed box, as the main page's card does (with logins on,
**maybe in the store** when that folder isn't in your library) - the name can't tell which album that
folder is, let alone which pressing. Point at it (on a computer) for the folder;
matching its release in the metadata editor settles it. Opened from a saved link or after a reload it
says the same, since the album's
title, kind and year come with its pressings. A link whose address isn't a MusicBrainz album says
*That isn't a link to an album on MusicBrainz.* Under it is the **Pressing** button, where an album you have has Play and
Shuffle; then **Get the album**, the page's one purple button, which gets **the pressing chosen**
([Get, and choosing a source](downloading.md#on-the-phone-get-and-choosing-a-source)); under it,
what you already have of that pressing, if anything ("Already in your library", "Already
downloading", "You have 9 of 10 tracks of this pressing…", "You also have another pressing…" - or,
with logins on, "The store also has another pressing…" for one that isn't yours -
asked of deadwax without searching Soulseek, for the pressing chosen, and again as you come back to
the page); and then **that pressing's tracklist**.

It needs only MusicBrainz, so it works with Navidrome down. To work out the differences it fetches
**every pressing's tracklist** at once, which for an album with a lot of pressings can take
several seconds (**Asking MusicBrainz…**); after that it's kept for as long as the app is open (the
last 20 albums you opened), so going back to it asks nothing again. If MusicBrainz isn't answering, it says so with **Try again**
rather than showing part of the list as if it were all of it.

**The Pressing button** says which pressing you're looking at: its format, year, country (left out
for a worldwide release; "Europe" for MusicBrainz's European ones) and its MusicBrainz
disambiguation, or else its label - "CD · 2020 · AU · Caroline International". It starts on **the
usual pressing**: one with the album's most common tracklist, an official release over a promo or
bootleg, a CD or digital release over vinyl, one with no disambiguation, then the earliest. That's
the pressing a card's **Find** on the main page downloads as, and the one a row's **Get** gets.

Under it (since 2.0.0-player.50) is what else tells that pressing apart, as MusicBrainz gives it: its
**status** (Official, Promotion, Bootleg), its **full date** when MusicBrainz has more than the year,
its **labels** when the button shows a disambiguation in their place (and any after the first one it
shows), its **catalogue number** and its **barcode**, and "Worldwide" for a release whose country the
button leaves off - "Official · 2008-04-28 · Cat. no. 1764013 · Barcode 602517640132". It keeps two
lines' room on a phone (one on a computer) whatever it says, so choosing another pressing moves nothing
under it; the whole of it is in its tooltip, and in the list.

Tap it for the list of pressings, each with a note of how it compares. It opens below the button
and, on a phone, scrolls the page so the whole list is in view above the tab bar and the mini
player (it's never taller than that, and scrolls inside itself past that):

- **The usual tracklist · shared by 9 of 10 pressings** on the one it starts on;
- **Same tracklist as the usual one**: one pressing of each other format that has it (so a vinyl
  is a tap away);
- every pressing that differs, its note in amber: **+1 bonus track: Patience**, **Without It's a
  Fire**, **1 other version: Borderline, 4:34**, **2 tracks renamed**;
- **No tracklist on MusicBrainz** for one nobody has entered the tracks of;
- then **N more pressings with the usual tracklist**, folded away - tap it to show them.

Each pressing in the list says its facts under its label (since 2.0.0-player.50), the same ones as the
line under the button. An album with **more than 30 pressings** has a **filter** at the top of the list:
type a country's code as the list shows it, a format, a label, a catalogue number or a word of a note
("jp cd", "uicb 1004", "promotion", "bonus") and only the pressings holding every word show, folded ones
included; *No pressing matches "…"* when none does. With VoiceOver on, it says how many match as you type
("4 pressings match."). A catalogue number is found however its parts are typed - "UICB-1004", "uicb
1004" or "uicb1004". Opening the list still puts you on the chosen pressing,
not in the filter (on a phone the keyboard would cover the list); from the filter the down arrow goes to
the first pressing, the arrows never leave the pressing they move to under the filter, and closing the
list, however you close it, empties it.

Since 2.0.0-player.41 every pressing you already have says **In your library** under its note, in
green, and is never folded away - judged by the pressing's MusicBrainz id in your folders' tags, once
deadwax has said what you have.

Choosing one shows its tracklist and closes the list, and the page's address remembers it, so a
reload or a saved link shows the same pressing; Back still leaves the page in one step. A tap
outside the list, or Escape, closes it without choosing.

**The tracklist** is the chosen pressing's own: its titles and lengths, numbered on each disc, with
disc headings for a set - "Disc 2 · Unreleased Tracks" when MusicBrainz gives the disc a title, as
an album you have shows the titles deadwax writes into your files. The line above it says what this
pressing is against the usual tracklist: *The usual tracklist, shared by 9 of 10 pressings*, *Same
tracklist as the usual one*, or, in amber, *This pressing adds 1 track* (or *leaves out*, *renames*,
*has another version of*). A track that differs is marked in its row:

- **Bonus**, in green, *Only on this pressing*: a track the usual tracklist hasn't got.
- **Other version**, in amber, *The usual version is 3:58*: the same title, but a different
  recording - 15 seconds or more longer or shorter (or 8% of the track, if that's more), like a
  single mix.
- **Renamed**, in amber, *Usually "…"*: a new title at about the same length.
- **Not on this pressing**, after the list: the usual tracks this one leaves out.

"The usual tracklist" is the titles in order, as on the main page, at the lengths of the pressing
the page starts on - so that pressing is always the usual one, whatever order MusicBrainz lists
them in. A pressing whose tracks are a few seconds longer or shorter (MusicBrainz's rounding, or
that pressing's own timing) still has it. The thresholds are the main page's own ([What's
different about each pressing](#whats-different-about-each-pressing)) - 15 seconds (or 8% of the
track, if that's more) for another version, within 5 seconds for a rename - but the app doesn't
mark a small length change at all, where the main page shows it as an "N lengths" chip: such a
pressing reads *Same tracklist as the usual one* here.

At the foot of the page (since 2.0.0-player.50), after the words **On MusicBrainz**, **The album ↗** and
**This pressing ↗** open the album's page and the chosen pressing's on musicbrainz.org, beside the app -
in a new tab, so the music keeps playing.


#### Opened from a song

An album opened from [a song](#songs-on-musicbrainz) (since 2.0.0-player.53) opens on a pressing that
has it: the usual one when that has the song, and otherwise the most usual of the pressings that do -
Tame Impala's "Patience" is a bonus track on The Slow Rush's Japanese CD alone, so The Slow Rush opens on
that CD (Get the album then gets it). The song is **marked** in the tracklist - tinted, barred and in the
accent, and a screen reader says "the song you searched for" - and the page scrolls to it as it opens. A
song MusicBrainz keeps as another recording on the usual pressing (Borderline's single mix) is found by
its title there. Choose another pressing and that's the one shown from then on, the song marked wherever
it is on it. The address keeps the song (`?song=`), so a reload or a link opens it the same way.
### Another pressing of an album you have

Since 2.0.0-player.41 an album you have - its own page in the app, played from your library - ends
its row of chips under the meta line with **Other pressings ›** (after **In your library** and any
**Also: …** chips for other pressings you hold). It opens [the album you don't
have](#the-album-you-dont-have) for that album: every pressing MusicBrainz lists, the ones you have
marked **In your library**, and **Get the album** for whichever you choose - the deluxe beside the
standard you hold, say. Its title is the album's name until MusicBrainz's own arrives with the
pressings. Choose a pressing you already have and the line under Get says **Already in your
library**, as it always did; Get then shows that in the sources rather than searching.

The chip appears once deadwax has said which MusicBrainz album yours is - from the album id in your
folder's tags. Its row (**In your library** and the chips beside it) has its place kept from the
start and shows once deadwax has answered, so nothing in it or under it moves as the chip lands. A
folder tagged with no album id (an .m4a deadwax filed carries the pressing's id but not the
album's) has no chip. Beside an **Also** chip, in a row too narrow for all three whole - a phone
held upright, or a computer's album page with a panel open beside it - it reads **Pressings** and
**In your library** keeps only its green tick, so the Also chip has room to say which pressing it
is; a screen reader still hears "Other pressings" and "In your library". With logins on, **In the
store** - grey words with no tick to keep - gives way whole there instead, and a screen reader still
hears it. It's the row's own width
that decides (600 pixels or less shortens), so a phone on its side, a tablet and a wide computer
window say every word.
