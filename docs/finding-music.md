# Finding music

The **Search** tab looks up artists, albums and songs - your library first, then MusicBrainz - and
opens any album MusicBrainz knows, with every pressing of it, so you choose the exact one you want.
That pressing is what **Get** downloads, what the sources found on Soulseek are matched against, and
what the album is tagged as when it's filed ([Downloading](downloading.md)).

It is **one list, as Apple Music shows one**: **Top results** first - the best artist, album or song,
yours or not - then **Artists**, **Albums** and **Songs**, each with **yours first, then what you
don't have yet** (MusicBrainz's). Before you type, the box says so: *Search your library and albums you
don't have yet.* (with logins on, *Search your library, the collection, and albums nobody has yet.*).
Chips over the list narrow it to one kind. An album MusicBrainz offers has **Get** at
the end of its row, and opens as [the album you don't have](#the-album-you-dont-have), with **Get the
album** under its **Pressing** button; **Requests** then follows the download.

On a desktop (a window 1024 pixels wide or more) the box is the sidebar's **search field**: typing there
shows these results in the main area, the chips under the large title, and Enter asks at once, as
**Search** on the keyboard does. Top results are tiles there, three across - two across beside a side
panel (Sources from a Get, or Info), so each keeps room for its title. An album you don't have shows its
tracklist as a table, with a **Compared with the usual** column whenever any pressing differs - see
[the app on a desktop](player.md#on-a-desktop).

An artist's name opens [their page](player.md#artist-pages): their albums as MusicBrainz lists them,
every one, oldest first, with what you have marked and a **Get** on the rest - **Studio only** narrows
it to their studio albums and EPs.

![Dance Gavin Dance's page: their albums from MusicBrainz, oldest first](../assets/images/discography.png)

## The box

Type an artist, an album, a song, or an artist and an album or song ("portishead third", "roads
portishead"), up to 200 characters.

- **Your library** is asked a fifth of a second after you stop typing.
- **MusicBrainz** is asked when you press **Search** on the keyboard, or 0.7 seconds after you stop
  typing once there are 3 characters or more - for its albums, then its artists, then its songs, at the
  same moment, read the way the box read as it was asked (an artist your library names only afterwards
  changes nothing already asked; **Search** reads it again). Fewer than 3, and it waits for Search: where its
  rows would go the list says *Type a little more, or press Search, to find albums you don't have yet.* - and cutting the
  box back below 3 clears what
  MusicBrainz found for the longer text (and calls off a search still on its way). MusicBrainz allows about
  one request a second, so it isn't asked on every key, and a search you have moved on from is called off
  on deadwax too, before it spends a turn.

Only the newest search is ever shown: an answer that arrives after you've typed something else is dropped.

A search MusicBrainz was asked before is answered at once from deadwax's
[saved answers](configuration.md#musicbrainzs-saved-answers-settings--connections), after a restart too - and everything in them is searched under any
words, [below](#what-deadwax-has-saved). And the app itself keeps the last 24 MusicBrainz answers it was
given while the page is open, so words you searched a moment ago - "portishead third" cut back to
"portishead", Back, a chip there and back - are drawn whole the moment your library answers, with nothing
asked at all.

## What deadwax has saved

Everything MusicBrainz has answered deadwax - every search, artist page and discography, and every album page
with all its pressings' tracklists - is kept on disk, and Search looks through all of it
**under any words**, not only the words asked before: search "portishead" and open Dummy, and later "glory
box" finds Glory Box at once, from Dummy's tracklist, before MusicBrainz has been asked - after a restart too.

- It's asked as the words settle, beside your library (for words MusicBrainz is asked for: 3 characters or
  more, or **Search**), and answers in a few milliseconds. **Every word must match** - in a name or a title, or
  in who it's by - the last one as you type it ("glory bo" finds Glory Box), accents aside ("bjork" finds
  Björk). A name typed exactly comes first ("bjork": Björk before Hera Björk; "kanye west": Ye, who went by
  it), words in the title before words only in the credit, and of songs with one title, the one on the most
  pressings (Portishead's Glory Box before a cover). At most 10 artists, 12 albums and 25 recordings.
- What it finds **leads each kind's MusicBrainz rows**, drawn exactly as MusicBrainz's own row would be -
  nothing on it says it was saved (until 2.0.6 a **saved** mark did, which read as "you saved this"). It is
  the row MusicBrainz's answer would draw, and does what that row does: an album opens its page, an artist theirs, a
  song the albums it's on (in Top results the album it names, the song marked), and Get gets the same - and
  those pages are saved answers too, so they open at once. MusicBrainz's own answer, when it lands, adds what
  it found that isn't there yet **below** them: nothing drawn moves, and the same artist, album or song is
  never shown twice. When it brings nothing new, a kind's place says *No more albums for "…".* In a chip's view the same holds whatever answers first: something saved that turns up after
  MusicBrainz's rows are drawn goes below them, and what's saved is looked up once for the words - a chip's
  tap, **Search** or **Try again** asks MusicBrainz again, not it.
- An album you have is left out of what's saved as it is out of MusicBrainz's rows. Until deadwax knows what
  your library holds - the first look after deadwax restarts can take a while on a sleeping disk - saved
  albums wait (saved artists and songs don't); MusicBrainz's albums come as ever.
- In **Top results** what's saved ranks after yours (and, with logins on, the collection's) and before
  MusicBrainz's answer, so a saved match can be drawn the moment your library answers, and never moves after
  - for "glory box": Glory Box, Dummy, Portishead, at once.
- It shows only the kinds MusicBrainz is asked for, read as the box is read: an artist you have typed alone
  ("portishead") shows their own saved albums - picked from every album of theirs that's saved, whatever
  else the words find: the studio ones, as the line under them says, earliest first, at most 12 - and no
  songs; a title and an artist you have ("roads portishead") no saved artists. (Saved first, then
  MusicBrainz's: the two blocks each read earliest first, not the section as a whole.)
- **When MusicBrainz is away** what's saved stays, with one line saying so: *Showing earlier results -
  searching for more isn't working right now.* (*Showing earlier results - try again in a moment for more.* when it is
  shedding searches; in a kind's place, short enough for a small phone, *Showing earlier results.*), with
  **Try again**.
- It's shared by everyone signed in: MusicBrainz's data is nobody's own, and nothing in it says who looked
  something up. With nothing saved for the words the list is exactly as it was. Your library's moment waits
  for it a little while at most (0.4 seconds); slower than that - a busy disk - it's left out for those words
  and MusicBrainz's answer stands alone. `MUSICBRAINZ_CACHE_MB` set to `0` (nothing saved) turns it off.
- What's saved is what MusicBrainz said when it was saved (a search is asked again after a week, the rest
  after a month), so an artist renamed since, or an album added since, shows as it was until MusicBrainz's
  own answer arrives - see [troubleshooting](troubleshooting.md#search-shows-an-old-name-or-misses-something-new).

## One list

- **Top results**: three rows on a phone, six tiles on a desktop. The best match comes first: an **exact
  match** - an artist named what you typed, an album or song titled it (case, accents, brackets and a
  leading "The" aside) - before one that is **by the artist you typed** before one that only **starts
  with** it. When two are as exact, **yours comes before MusicBrainz's** (with logins on, yours before the
  collection's before MusicBrainz's), and [what deadwax has saved](#what-deadwax-has-saved) before MusicBrainz's
  answer. Then what the best match belongs to, as Apple pulls it in: for "glory box"
  the song, then **Dummy**, then **Portishead**. Then one of each kind in turn. An artist you have, typed
  alone ("portishead"), is them first, then their albums and songs - their self-titled album is by them, not
  an exact match. Each row says what it is first: "Artist · 3 albums in your library", "Album · Portishead ·
  1994", "Song · Portishead · Dummy" - and on a desktop's tile a third line saying where it is: *In your
  library*, *In the collection*, or for something nobody here has *Not in your library* (*Not in the
  collection* with logins on; *Maybe in your library* for an album a folder of its name may be, which its row
  in Albums says too). An artist's tile says *Not in your library* only when no artist in your library has
  that name - otherwise it says nothing, since it may be the one you have, untagged. A tile with a **Get**
  leaves that line empty: there is no room for it beside the Get, which says it already. A song of yours plays from its tap (▶ once its album is in hand), and
  its **•••** has Play Next and Play Last ([Up Next](player.md#up-next-shuffle-and-repeat));
  a MusicBrainz song opens the album it's on, the song marked; everything else opens.
- **Artists**, **Albums**, **Songs**: a few of each - on a phone your first 2 artists and MusicBrainz's 2,
  3 and 3 albums, 3 and 3 songs (on a desktop 3 and 3, 4 and 4, 4 and 4), so MusicBrainz's show even beside
  many of yours. **See all**, in each heading, shows that kind in full. A section with nothing to show is
  left out.
- **Every row of yours says where it is**: "in your library" at the end of its line (with logins on, "in
  your library" or "in the collection", or nothing while that isn't known yet).

**Artists**: yours, with how many of their albums you have, then MusicBrainz's, so anyone can look an
artist up on MusicBrainz. Each MusicBrainz artist says who it is: "as Kanye
West" when it was found by a name it used to go by, then MusicBrainz's note, its type and country ("as
Kanye West · formerly Kanye West · Person · US"). A MusicBrainz artist your library has is shown once, as
yours - by MusicBrainz's id, or by name when only one MusicBrainz artist goes by it - so "kanye west" shows
your Kanye West and no "Ye", while two bands both called Nirvana stay two rows, each with its note. Tap
one for [their page](player.md#artist-pages): yours by your library, MusicBrainz's by its MusicBrainz id
(it opens with Navidrome down, and finds your copy itself if you have one after all). For a title and an
artist you have ("portishead third"), Artists leads with that artist and MusicBrainz isn't asked for
artists.

**Albums**: yours ("Portishead · 1994"), then MusicBrainz's ("Portishead · 2008", or "Live album ·
Portishead · 1998", "EP" and so on when it isn't a plain album), 12 asked a search, **leaving out any you
already have** - judged by MusicBrainz's own id for the album, so a folder deadwax filed (or one tagged by
Picard) is recognised; a folder with no MusicBrainz ids can't be, and nor can an **.m4a album deadwax
filed** (it carries the pressing's id but not the album's), so such an album is still offered, and its own
page says "in your library". To leave those out the list waits a moment (a second and a half at most) for
deadwax to say what you have; if it answers later - the first time after it restarts - an album it turns
out you have stays where it is and says "in your library" at the end of its line, rather than vanishing
from under your finger. An album you have that your library's own search didn't list (it finds 8, and
matches words its own way) is still shown, among yours, marked, with no Get, opening the album you have -
so an album you hold never shows nowhere. **Get**, at the end of a row MusicBrainz offers, gets the
album's usual pressing without opening it (it reads "Getting…" while it asks MusicBrainz for the pressings,
and gives up if you type, open something or switch tab meanwhile). For an **artist's name alone**, All
asks MusicBrainz for their **studio albums and EPs** - otherwise Portishead's first twelve are live albums,
an interview, compilations and singles, with no Dummy and no Third - and says so in one line under them:
*Studio albums and EPs - See all for everything they made.* **See all** (the Albums chip)
asks for everything, unfiltered. Various Artists ("va") is never filtered: its records are compilations by
nature.

## Songs

Your songs first - each plays straight away, from that song through the rest of its album, once its album
is in hand (as the answer arrives, the albums of the songs in Top results and then of the first songs are
fetched, five different ones; a song whose album has arrived shows ▶) - then the **songs MusicBrainz has**
, for people who know a song but not the album it's on. A MusicBrainz song you have
in your library by the same title and artist is left out - yours shows instead (its other albums are on
the artist's page).

- **One row per song.** MusicBrainz keeps every performance of a song as a recording of its own - the
  studio take, each live tape, each re-recording - and finds them all equally well, in no useful order
  ("Roads" by Portishead is 45 recordings, Queen's "Bohemian Rhapsody" over 200). So every recording of
  one title by one artist is **one row**, its albums put together; a remix ("Roads (Monk & Canatella
  mix)"), or the same title by someone else, is a row of its own. A take titled "(live)" or "(Remastered
  2015)" counts as the song itself. Each row is the song's title, then who it's by, its length on the album
  it names and that album: "Portishead · 4:56 · Dummy". When you have the song - a pressing of one of its
  albums that it's on - the row names that album and ends **in your library** (with logins on, **in the
  collection** when only the collection has it). deadwax knows you have it when the pressing you hold is one
  MusicBrainz's answer lists the song on, when your library's own search finds the song by that artist on
  that album, or when it already has the album's pressings from earlier (its page opened, say) and yours has
  the song in its tracklist. A pressing of the album without the song isn't having it: with The Slow Rush's
  usual CD in your library, Tame Impala's "Patience" (a bonus track on its Japanese CD alone) says nothing of
  the sort. A song MusicBrainz lists on no release at all isn't shown - there'd be nothing to get; when every
  song it found is like that, it says *Found songs called "…", but none is on an album yet - there's
  nothing to get.*
- **Get**, at the end of a MusicBrainz song you don't have, gets **the album it names, on a pressing that
  has the song** ("Get The Slow Rush, with Patience" gets its Japanese CD). It reads "Getting…" while it asks
  MusicBrainz for the album's pressings; if MusicBrainz can't list them, the album's page opens instead,
  the song marked, and its own Get takes over.
- **Tap a song** in the Songs section and it opens in place onto **the albums it's on**: albums and EPs
  first, then singles, each official release before a promotional one before a bootleg, the earliest first.
  Compilations, live albums, soundtracks, broadcasts and the rest wait behind one line saying what and how
  many there are - "On 24 compilations, live albums, broadcasts and other records" - which opens them, in the
  same order (a live radio or TV broadcast counts as a broadcast, not a live album). A song that's only on
  those (Elliott Smith's "Miss Misery") lists them at once, under those words. Each album says what it is
  and when ("Live album · Bootleg · 1997"), who it's by when that isn't the song's artist ("Compilation ·
  Various Artists · 2015"), the song's length there when it's another performance's ("· 5:36"), and **·
  in your library** when you have it with the song on it - **· a pressing in your library** when you have
  a pressing of it that nothing yet says has the song or hasn't (**· a pressing in the collection** with logins
  on, when it's only the collection's). That happens because MusicBrainz often keeps one song as several
  recordings across an album's pressings, and its answer names only some of them. Tap the song again to
  close it. (In Top results a MusicBrainz song goes straight to the album it names instead, the song
  marked.)
- **Tap an album** you don't have and it opens as [the album you don't have](#the-album-you-dont-have),
  on a pressing that **has the song**, with the song marked - [below](#opened-from-a-song). Tap one you
  have the song on and it opens **the album you have**, as the Library would (while Navidrome hasn't found
  it, or can't be asked, the album you don't have, which says "in your library"). Tap one that says **a
  pressing in your library** and deadwax first fetches the album's pressings - the row looks busy meanwhile;
  the album's page would fetch them anyway, and keeps them - then opens the album you have when the
  pressing you hold has the song, and otherwise the album you don't have, on a pressing with the song,
  where Get is. If MusicBrainz can't list the pressings, it opens the album you don't have.

**Why "portishead" alone shows no MusicBrainz songs**: an artist's name alone asks MusicBrainz for no songs
- every recording they ever made, in no useful order (Portishead's first 25 are remixes, live and
compilation takes), is no answer to it; their songs in your library still show, and the Songs chip says
*Type a song's title with the artist ("roads portishead") to find songs you don't have yet.* A title
beside an artist you have is that song by them ("roads portishead" is Roads by Portishead), and if that
finds nothing it's asked again as the words you typed taken as **one title**. **Words with no artist you
have are matched against song titles only**, so a famous title alone mostly finds covers: "hey jude"
alone finds tribute bands and string quartets, and no Beatles in its first pages - type the artist too.

## The chips and See all

**All** (pressed as you start typing) is the list above. **Artists**, **Albums** and **Songs** each show that
kind **in full**, with no Top results: first your library's (its own search for that kind - 50 artists,
50 albums or 100 songs - with **More from your library**, **More from the collection** with logins on, for the
next page when that one came back full, *Loading…* while it asks; *Searching…* stands where its rows will
go while it's asked), then MusicBrainz's, added at the foot as they arrive and never before your library's,
with **More artists**, **More albums** or **More songs** for the next
page of the same search. In the Albums view an album you have that your library's search didn't list is
among MusicBrainz's rows at its place, marked, with no Get. A chip asks MusicBrainz only for the kind it
shows that nobody has asked for these words.

**More** adds the next page below, so nothing you were looking at moves - leaving out the albums you have,
as the first page does. It reads **Loading…** while it asks; if MusicBrainz isn't answering it
says so and reads **Try again**. When every new album of the next 12 is one you have it says so; when
MusicBrainz sends nothing new, *No more results.* More songs says when a page brought only
albums ("No new songs - 7 more albums for the songs above."). The button goes once MusicBrainz has nothing
more, and if it had keyboard focus, focus moves to the first row the last page added - as **Show them**,
**Show 3 more albums** and any **Try again** hand it on as they go: to the first row they brought,
else a heading the list has drawn, never back to the top of the page. No page starts more
than 1,000 answers in; past that, *That's all for this search - add a word to narrow it.*

**See all**, in each section's heading, presses that kind's chip and brings the chips into view; pressed
from a keyboard, focus goes to the chip. The chip you chose stays while you type other words, goes back to
All when you empty the box, and isn't in the address - so Back doesn't undo it; the All chip does.

## Nothing moves under your finger

Your library answers in a fraction of a second, MusicBrainz a second or three later - and sometimes not at
all - so the list is drawn in steps that never move each other: **every row and button drawn for a search
keeps its place until you do something; a later answer lands only below everything you can tap, or inside a
place already drawn for it, one fixed height.**

- As your library answers, Top results are drawn as far as your library - and what deadwax has saved - can
  already tell (all three for "portishead" or "roads", or "glory box" once Dummy's page is saved); a row
  still waiting on MusicBrainz keeps a place with a moving bar, and *Searching…* stands where the
  sections will go.
- When every kind MusicBrainz was asked for has answered - or a second and a half after it was asked,
  whichever is first - Top results are completed and the sections drawn, in one go.
- A kind still out then gets a **place** at the end of its section, one fixed height, saying
  *Searching…*. When its answer comes: if nothing you can tap is below that section, its rows are drawn
  straight in; otherwise they wait in that place as **Show 3 more albums** (a tap opens them),
  or the place says why there are none (*No other artists for "…".*).
- After a search MusicBrainz was too slow for, or away for, the next searches draw your library's rows at
  once, MusicBrainz's arriving in those places - until it answers in time again.
- If your library itself is slow (a second and a half), the list is drawn without it, with a place at the
  top: *Searching your library…*, then **Show 3 from your library** - or, if Navidrome turns out not to
  be reachable, *Your library can't be searched just now.* (never that it found nothing).

## MusicBrainz busy or away

When MusicBrainz is shedding searches (it often does, for a few minutes) a kind's place says *Too many
searches just now - try again in a moment.*; when it isn't answering at all, *Can't search for more
right now.* - each with its own **Try again**, which draws the list afresh for the same words and asks only
what failed. When every kind failed, one block at the foot says so - *Searching for more isn't working
right now - try again in a few minutes. What's in your library is above.* - with **Try again** (the
last sentence only when something of your library is drawn above). Under rows
[deadwax has saved](#what-deadwax-has-saved) the words say these are earlier results instead. Pressing **Search** again (or
Enter in the desktop's field) does what Try again does. If MusicBrainz can't read
what you typed as a search, it says *That search couldn't be read - try other words*, with no Try
again (the same words would be refused again). A search gives up after three tries: about eight seconds
when MusicBrainz is turning searches away; longer when it doesn't
answer at all, as each try waits up to half a minute for an answer. If nothing at all was found, *No results for "…".* and *Check the spelling or try
a new search.* - never when MusicBrainz wasn't asked yet.

If Navidrome isn't set up or can't be reached, its notice (**Connect Navidrome** or **Can't reach
Navidrome**, as Home shows - **Your music isn't available** to anyone who doesn't run deadwax) sits once
above the list, and MusicBrainz's rows still fill every section below
it. If your library's search fails, it says why at the top in plain words ("Can't reach the music server
right now", "Can't connect to deadwax"), with **Try again** - which **Search**, or Navidrome
coming back, does too: the list is drawn afresh with your library in it.

**With logins on** your library's rows are the **collection's** - Navidrome's search finds
everything deadwax holds - so yours come first, then the collection's, each saying which; an artist's count is
yours when you have albums of theirs ("1 album in your library"), else the collection's ("3 albums in the
collection"); and adding an album to your library on its page re-marks its row here in place. A row whose
whose-it-is isn't known yet sits among yours and may say "in the collection" there once known, rather than move.
See [the player as you](player.md#the-player-as-you-with-logins-on).

## How the box is read

- **It starts or ends with an artist you have** (any folder in your library, by name, ignoring case,
  accents, a leading "The" and "&" against "and"): the rest is the title, and MusicBrainz is asked for that
  album, and that song, by that artist, under the name they had then or have now. "portishead third" and
  "third portishead" both find Third. The longest name that fits wins, so "pink floyd the wall" is The
  Wall by Pink Floyd even if you also have Pink. A dash, colon or slash between the two is ignored
  ("portishead - third").
- **It is an artist you have**: their studio albums and EPs in All (everything under the Albums chip), and
  MusicBrainz's artists of that name.
- **va**, or "various artists", is Various Artists.
- **Anything else** goes to MusicBrainz as you typed it, for albums, artists and songs.

If reading it as an artist and a title finds nothing (an artist's name that happens to begin a title),
it's asked again as the words you typed. *You already have everything found.* (*Everything found is in
the collection already.* with logins on) means just that.

## The album you don't have

It opens like an album you have: back, the cover in the middle (the Cover Art Archive's, for the
pressing shown, else for the album), the title, the artist (a link to
[their page](player.md#artist-pages) when the album is credited to one artist; a collaboration's
names stay plain), and "2008 · Album ·
not in your library" - "in your library" if you have some pressing of it after all (with logins on, "in
the collection" when the collection has a pressing of it but none is yours, and "another pressing in your library"
when one is but the pressing chosen is the collection's - the line speaks of the album, the one under Get of
the pressing, so it never says "in your library" over **In the collection, not in your library**; the
**Pressing** list marks each pressing **In your library** or **In the collection**). That last part
appears once deadwax has said what you have, never before, so it can't claim you don't have an
album you do; and it counts a folder tagged with any of the album's pressings, the .m4a albums
above included. When nothing is tagged as the album but a folder **with no
MusicBrainz ids at all** has its name and its artist's (as credited, or the name they go by now), it
says **maybe in your library**, in a dashed box (with logins on,
**maybe in the collection** when that folder isn't in your library) - the name can't tell which album that
folder is, let alone which pressing - and a line under **Get the album** says so in words: *You may
already have this - an album with this name is in your library, but it isn't matched to a pressing.* (*It
may already be here - … in the collection …* when the folder isn't yours). Whoever can Edit albums also
reads *Match it to a pressing in Edit album.*, and on a computer can point at the dashed box for the folder;
matching its release in **Edit → Release** settles it ([the library](library.md#editing-an-album)). Opened from a saved link or after a reload it
says the same, since the album's
title, kind and year come with its pressings. A link whose address isn't a MusicBrainz album says
*That link isn't an album.* Under it is the **Pressing** button, where an album you have has Play and
Shuffle; then **Get the album**, the page's one purple button, which gets **the pressing chosen**
([Get, and choosing a source](downloading.md#choosing-a-source)); under it,
what you already have of that pressing, if anything ("Already in your library", "Already
downloading", "You have 9 of 10 tracks of this pressing…", "You also have another pressing…" - or,
with logins on, "The collection also has another pressing…" for one that isn't yours -
asked of deadwax without searching Soulseek, for the pressing chosen, and again as you come back to
the page); and then **that pressing's tracklist**.

![Dummy, an album you don't have, on its 2017 vinyl: the Pressing list open, each pressing saying what it changes about the tracklist twelve of its twenty share](../assets/images/search.png)

It needs only MusicBrainz, so it works with Navidrome down. To work out the differences it fetches
**every pressing's tracklist** at once, which for an album with a lot of pressings can take
several seconds (**Loading…**); after that it's kept for as long as the app is open (the
last 20 albums you opened), so going back to it asks nothing again. If MusicBrainz isn't answering, it says
*This album's details can't be loaded right now - try again in a few minutes.* with **Try again**
rather than showing part of the list as if it were all of it.

**The Pressing button** says which pressing you're looking at: its format, year, country (left out
for a worldwide release; "Europe" for MusicBrainz's European ones) and its MusicBrainz
disambiguation, or else its label - "CD · 2020 · AU · Caroline International". It starts on **the
usual pressing**: one with the album's most common tracklist, an official release over a promo or
bootleg, a CD or digital release over vinyl, one with no disambiguation, then the earliest. That's
the pressing a row's **Get** gets.

Under it is what else tells that pressing apart, as MusicBrainz gives it: its
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
- **No tracklist listed** for one nobody has entered the tracks of;
- then **N more pressings with the usual tracklist**, folded away - tap it to show them.

Each pressing in the list says its facts under its label, the same ones as the
line under the button. An album with **more than 30 pressings** has a **filter** at the top of the list:
type a country's code as the list shows it, a format, a label, a catalogue number or a word of a note
("jp cd", "uicb 1004", "promotion", "bonus") and only the pressings holding every word show, folded ones
included; *No pressing matches "…"* when none does. With VoiceOver on, it says how many match as you type
("4 pressings match."). A catalogue number is found however its parts are typed - "UICB-1004", "uicb
1004" or "uicb1004". Opening the list still puts you on the chosen pressing,
not in the filter (on a phone the keyboard would cover the list); from the filter the down arrow goes to
the first pressing, the arrows never leave the pressing they move to under the filter, and closing the
list, however you close it, empties it.

Every pressing you already have says **In your library** under its note, in
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

"The usual tracklist" is the titles in order - the most common tracklist among the pressings, with a
curly and a straight apostrophe, case and punctuation counting as the same - at the lengths of the
pressing the page starts on, so that pressing is always the usual one, whatever order MusicBrainz lists
them in. A pressing whose tracks are a few seconds longer or shorter (MusicBrainz's rounding, or that
pressing's own timing) still has it: a small length change isn't marked at all, and such a pressing
reads *Same tracklist as the usual one*. Another version is 15 seconds (or 8% of the track, if that's
more) longer or shorter; a rename is a new title within 5 seconds of the old one's length.

At the foot of the page, after the words **On MusicBrainz**, **The album ↗** and
**This pressing ↗** open the album's page and the chosen pressing's on musicbrainz.org, beside the app -
in a new tab, so the music keeps playing.


### Opened from a song

An album opened from [a song](#songs) opens on a pressing that
has it: the usual one when that has the song, and otherwise the most usual of the pressings that do -
Tame Impala's "Patience" is a bonus track on The Slow Rush's Japanese CD alone, so The Slow Rush opens on
that CD (Get the album then gets it). The song is **marked** in the tracklist - tinted, barred and in the
accent, and a screen reader says "the song you searched for" - and the page scrolls to it as it opens. A
song MusicBrainz keeps as another recording on the usual pressing (Borderline's single mix) is found by
its title there. Choose another pressing and that's the one shown from then on, the song marked wherever
it is on it. The address keeps the song (`?song=`), so a reload or a link opens it the same way.

## Another pressing of an album you have

An album you have - its own page in the app, played from your library - ends
its row of chips under the meta line with **Pressings ›** (after **In your library** and any
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
held upright - the badge gives way, **In your library** or **In the collection** alike, so the Also chip has
room to say which pressing it is; a screen reader still hears it, and the page still says whose the album is
(with logins on, **Remove from my library** or **Add to my library** under Play). It's the row's own width that decides (420 pixels or less shortens), so a phone on its side, a
tablet and a computer - an album page with Info or the Edit panel open beside it included - say every word.
(Since 2.0.5 the chip is **Pressings** on every frame; it was "Other pressings" where there was room.)
