/**
 * The app's gesture rules (2.0.0-player.9 on), read off the source - the rules that keep the engine
 * working now that the player lives inside five tabs. "The one app" in CLAUDE.md says why each one
 * exists; in short:
 *
 *  - usePlayer() is called ONCE, in app/App.tsx, which never unmounts. The engine makes one audio
 *    element for the page's life, and iOS unlocks audio per element from a tap: a second call - a
 *    tab calling it - is a second element nobody unlocked. Only App imports it as a value, so a
 *    renamed import (`usePlayer as useEngine`) can't slip a second call past the count.
 *  - The playback actions (playTracks, toggle, next, previous, setGapless, showAirPlay - and since
 *    2.0.0-player.39 setSpeed, which is no gesture-gated action but IS a player action) must be
 *    called straight from a tap, play() in the same turn as the gesture. So they are reached only
 *    from the files allowed below, each a screen whose buttons call them from their click. Adding
 *    a file is a deliberate edit to this list, like the Navidrome route list. app/context.ts may
 *    NAME them (for ActionsContext) and calls none: a helper there that fetched and then played
 *    would start playback outside the tap for whichever page called it.
 *  - Nothing outside app/ and player/ can reach the player at all (usePlayer or the contexts).
 *  - Nothing in app/ touches audio itself: no Media Session handlers, no new audio elements, no
 *    source or load() on one - all of that is the engine's (usePlayer.ts, streamSource.ts).
 *  - A link out of the app opens BESIDE it (target="_blank" rel="noopener"): followed in the same
 *    page it would unload the player, the music and the queue with it.
 *  - While Now Playing is open everything behind it is inert, and focus goes into it.
 *  - Each sheet - Now Playing, its ••• menu, Info (2.0.0-player.10) - is a sheet by the one hook
 *    (app/useSheet.ts): a scroll lock of its own, inert while closed, focus in and back to an
 *    opener that focused itself in the tap, Escape for the one on top, a tap on the backdrop.
 *  - Gapless is a checkbox in You > Playback (app/GaplessChoice.tsx) since 2.0.0-player.10, and
 *    its tap still calls setGapless in the same turn: that tap is what unlocks the second audio
 *    element on iOS. It is the ONE new file on the list below, and Now Playing left it.
 *  - Nothing in Now Playing's body that can change height sits below the song's title: no
 *    readouts, the failure line above the title, the icon row a fixed height.
 *  - The turntable (2.0.0-player.11, player/Turntable.tsx) plays or pauses from its record's
 *    click, in the tap - the one more file on the list below - and seeks only as a finger lets
 *    go or a key steps, never on the way. Its record and arm are OUTSIDE Now Playing's grip, so
 *    neither starts the sheet's drag; the look is chosen in Now Playing, below App, and App keeps
 *    only the setting; the time line takes the bar's place at one fixed height.
 *  - The turntable's momentum and its own sound (2.0.0-player.14, player/deck.ts): the deck reaches
 *    the song only through Turntable's two named functions (holdSong, resumeSong - the player's own
 *    toggle: pause as a hand takes the record, play at speed after a coast) and the seeks Turntable
 *    makes of what a release or a pause returns; it calls no playback action itself. Its audio context
 *    is made or resumed ONLY from gestures WebKit counts - the record's click and release, Now
 *    Playing's transport and look button, the mini player's tap (App) - never a pointerdown. And none
 *    of it - deck.ts, lib/deckVoice.ts, Turntable.tsx - touches the player's own audio element: no
 *    createMediaElementSource, no element looked up, nothing set, loaded, played or paused on one.
 *    Its main-thread voice (2.0.0-player.16: a ScriptProcessorNode, where the page has no AudioWorklet)
 *    and the page's audio session it sets are made in the deck alone, as its context is.
 *  - The downloads are watched ONCE, in App (2.0.0-player.12): useDownloadJobs is called there and
 *    in no other file of the app, polling fast only while the Requests tab's root shows (watchingOf)
 *    or a failed look left something arriving (stallsOn), so the tab, Home's Arriving and the badge
 *    are one poll; App takes this page's download requests, and asks again as Home comes into view
 *    or the app comes back - never on a timer of its own.
 *  - No blocking dialog anywhere in the app (confirm, alert, prompt): it holds the page's
 *    JavaScript, and this page plays the music - the next song would wait for it.
 *  - Each tab's top page is memoised on what AlbumPage reads of the player, and AlbumPage reads no
 *    more than that, so a poll of the downloads never re-renders an album page.
 *  - App moves the browser's history only through lib/appHistory.ts's router, which the routes
 *    sim drives end to end.
 *  - Search (2.0.0-player.13) plays a song within its album from the tap - the one more file on the
 *    list below - and only with that album's songs already in hand (prefetched, KEPT, as the answer
 *    landed); its rows otherwise navigate. Both its halves, and the album-you-don't-have page, draw
 *    only the newest answer (latestOnly). That page needs no Navidrome, so it is outside the gate,
 *    and has no solid purple button until Get comes (S5). What the library holds is asked when
 *    Search first shows, when the page opens, and beside each MusicBrainz search - never as the
 *    app starts - and a filing asks again once anything has; search.sim.cjs drives the store
 *    itself (one ask out, "ask again", what a refresh waits for).
 *  - Get (2.0.0-player.15): the album page's "Get the album" - the page's ONE solid purple button -
 *    and the Get chip on a Search row open the Sources sheet, a sheet by the one hook like the others,
 *    over everything and with the page behind it inert. A source's Get asks for the download in the
 *    tap (requestDownload, nothing awaited before it, so the pending row is up from the tap) and then
 *    hands over to Requests; a pick made for you goes the same way, only on a fresh Get and never
 *    for a pressing held or on its way, or with no tracklist or release id to judge it by. Each fetch
 *    that draws - the search, the page's store state, a chip's pressings - goes through its own
 *    latestOnly(). In the sheet the best match's Get is the one solid purple button, wherever the
 *    sort puts it. After review: the two sheets can't stack - Search is told when its root stops
 *    being what shows and calls a chip's lookup off, and openSources refuses while Now Playing is
 *    open; the sheet's Cancel, backdrop and Escape let the search go in the gesture; and the album
 *    page is told whether it is what shows, so its store line is asked again as it comes back.
 *  - Artists, and the id bridge (2.0.0-player.17): the artist page's Play and Shuffle call playTracks
 *    straight from the tap - the one more file on the list below, app/ArtistPage.tsx - and only once
 *    every album they play has had its songs asked for (KEPT) and answered, and the library has said
 *    which are copies of one: disabled until then; every album played remembered for Info. A
 *    Requests Done row's ▶ - app/Requests.tsx, the other new file - plays its album only with its
 *    songs already in hand (the first few asked for while the tab's root is what shows, never as the
 *    app starts, and looked for again until found), and otherwise opens it. Every new fetch that
 *    draws - the artist page's seven, the album page's store answer, Search's held row, Requests'
 *    Done rows, Info's details - goes through a latestOnly() of its own, and a row's look still out
 *    when its page or tab stops showing opens nothing. An artist Navidrome knows is drawn inside the
 *    gate, one MusicBrainz knows outside it.
 *  - Pins, and a finished Home (2.0.0-player.18): pins are deadwax's own - nothing in the app ever
 *    asks Navidrome to star or unstar - and nothing about them reaches a playback action: a pinned
 *    card opens its album (asked for as the finger lands, as a tile is) or its artist, and the pin on
 *    an album, an artist and in Now Playing's menu only saves. The app's one store of pins asks only
 *    when asked - afresh each time Home comes into view, from a page only when nothing recent is in
 *    hand, as Now Playing opens for its menu, never as the app starts - and sends every read and
 *    change in turn, so the newest answer is the last to land; Home's shelves wait for the pins (or a
 *    moment) so Pinned landing moves nothing; Not played in a while draws only the newest answer
 *    (latestOnly). The menu's pin closes the menu and saves. Edit's drag is the grip's alone and never
 *    reorders the list under the pointer.
 *  - The desktop frame (2.0.0-player.19): from 1024px the same App draws a sidebar, a player bar
 *    and side panels - chosen BELOW the engine (useFrame, after usePlayer), so crossing 1024px swaps
 *    the chrome around the panes (each keyed on its tab, in the same place) and never runs the engine
 *    again. The player bar is the one more file on the list below (player/PlayerBar.tsx: its
 *    transport, from the click). Into the desktop Now Playing closes, and nothing on a desktop opens
 *    it - the mini player is its only opener and isn't drawn there - so the turntable is the phone's
 *    alone. Sources and Info are side panels there, NOT modal: nothing behind them goes inert and no
 *    scroll lock is taken (useSheet's `modal`), Escape closes one only from inside it, and one shows
 *    at a time - the player bar's Info, pressed again, closing its own; which shows makes room for a
 *    column (`.has-side`) or marks a drawer (`.has-drawer`), and the Info drawer goes as Go to album
 *    or Info's artist opens a page under it. The album you don't have follows the pressing with the
 *    panel open for it, searching again for each (`again`: no pick) - App handing it the pressing the
 *    panel searched, not just the album. The sidebar's Managing reads /deadwax/me (latestOnly). The sidebar reaches no playback action, and its one link
 *    opens beside the app.
 *  - The desktop visualizer (2.0.0-player.20, player/Visualizer.tsx): NOTHING IN THE APP - no file
 *    under ui/src at all - calls createMediaElementSource; what it sees is a silent, separately decoded
 *    copy of the song (player/vizAudio.ts: the turntable's FLAC window, through an analyser into a
 *    gain of 0), and none of its files touches a media element. It is the one more file on the list
 *    below: its play/pause is the player's own toggle, called only in its onToggle - from the button's
 *    click and the Space key - and none of its files reaches any other action. Its audio context is
 *    made only in wakeVisualizerAudio, from the click that opens it (App's openVisualizer, handed to
 *    the player bar, which only a desktop draws), and closed with it; nothing of it needs a secure
 *    page (no AudioWorklet), nothing of it is random, its frame loop stops while the page is hidden,
 *    and everything behind it is inert while it shows. Crossing back to a phone's width closes it.
 *  - Get, as the main page had it (2.0.0-player.41): the album you have's "Other pressings" chip, last
 *    in the row drawn from the first frame, opens its group's page through App with no preview (the
 *    header and Get MusicBrainz's own; the album's name the title meanwhile); the pressing list marks
 *    what the page's one /library/owned answer holds; Search's MusicBrainz half still leaves held
 *    groups out and the artist page's held rows still open the album you have (James's decision,
 *    pinned both ways); a card's reasons behind the score in a phone's sheet; Format sent from You's
 *    store with every search (the main page's storage read only to seed it); Confirm before
 *    cancelling read from this device at the tap; and Search again a disclosure closed as a search
 *    starts. Nothing on the list below gains a file.
 *  - Editing an album on a desktop (2.0.0-player.21): the album page's Edit - handed to it only in the
 *    desktop frame and for an admin (/deadwax/me) - opens the Edit panel (app/EditPanel.tsx), a third
 *    kind of side panel by the same rule: drawn only in the desktop's frame (crossing to the phone
 *    closes it), one panel at a time (Edit puts Sources and Info away, either puts Edit away, Edit
 *    pressed again closes it), not modal (the one hook, `modal` from the panel style), and the album
 *    page's own - closed as that page stops being the one showing. Its editors are the main page's,
 *    handed a close that passes over an Escape from the page (they listen on the whole document); the
 *    album it edits is held and updated from what a reload resolves with, never derived from the list
 *    a write reloads; what it fetches goes through latestOnly(); and it calls no playback action -
 *    nothing on the list below gains a file. A page an apply gave a new id becomes it through the
 *    router (`become`), and only while it is the page showing. After review: the move is remembered,
 *    and a page of the old id back on top becomes the new one's; the look for the new id has a
 *    latestOnly of its own, so a later write doesn't call it off; the editors are let go once the
 *    panel has closed (a cover viewer left open took the next Escape anywhere); an Escape in the tag
 *    editor or the delete confirmation closes that layer alone; a control that removes itself hands
 *    focus on inside the panel; the library is read again underneath on each Edit after the first; a
 *    delete of one folder of several asks the page again once Navidrome has scanned; and the state
 *    rules each pinned (the release editor keyed on the session, several by name a choice, the album
 *    from a real scan, the library read only once the panel opens, the files read only for Tags).
 *  - Needs a look (2.0.0-player.25): the review queue's page (app/NeedsALook.tsx) calls no playback
 *    action; it reads the library through the main page's hook only once it shows on a desktop, and on
 *    a phone draws a note before any row; it is the one file in the app that marks an album reviewed,
 *    and asks the count again when it does; the count is one store (app/useQueueSummary.ts), asked by
 *    App as the desktop frame shows for an admin and the page comes back, after every change the Edit
 *    panel reports, and on a filed album - never on a timer. The sidebar's item is Managing's first and
 *    an admin's; You's row a desktop's. A row opens the Edit panel on its folder by the one-panel rule,
 *    and the panel asks no bridge for a folder, reads the library again only for a session's first
 *    album, gives the release editor the queue, and tells the page and App by path.
 *  - Server settings and the log (2.0.0-player.33, app/ServerSettings.tsx, app/EventLog.tsx) call no
 *    playback action. The log's stream (an EventSource, held open: one of the six connections a browser
 *    allows the host, which the player's audio uses too) is opened by EventLog alone, in an effect that
 *    opens nothing unless the page is what shows (a desktop, an admin, the app in front, the visualizer
 *    not over it - App's `live`) and closes it as that stops; its lines are text, never HTML. The
 *    settings page reads through latestOnly(), never over a draft, and a save calls a read still out
 *    off. What both pages hold - the drafts, the refusal, the tab, the lines - is kept in their modules,
 *    never as component state, so a page left and come back to still has it. The sidebar's Settings and
 *    Log are an admin's, after Needs a look; You's rows a desktop's.
 *  - The artist page as the main page had it (2.0.0-player.45): its panel (app/ArtistPanel.tsx) plays
 *    nothing and reads no player; a sheet on a phone (the page behind inert - App's `covered`) and a
 *    side panel on a desktop, under the visualizer inert; one panel at a time with Sources, Info and
 *    Edit, pressed again for its job closed, the page's own (closed off its page, left open across
 *    1024px); albums moved, a page whose name has none left follows them by the artist's MusicBrainz
 *    id (the guard, the old id's page redirected, focus to the back link, the scroll put back once the
 *    page has drawn - review), and the page moved from is asked again after the panel's wait, under the
 *    id it has now (App holds no timer); a write never called off; every preview and search
 *    through a latestOnly with its signal; the managing an admin's, App asking /me on a phone as an
 *    artist page comes on top; the page's summaries through their own latestOnly.
 *  - Looking after the library (2.0.0-player.42): Library care (app/LibraryCare.tsx) calls no playback
 *    action, reads the library through the main page's hook only once it shows on a desktop, and on a
 *    phone draws a note before anything; its runs are app/useLibraryCare.ts's - kept in the module, never
 *    component state, each through a latestOnly() of its own, one album at a time through the routes a
 *    single click uses (never a loop of its own on the server), started and stopped from a click - and
 *    the targets are lib/bulkTargets.ts's, which the main page's Library tab takes too; a run that
 *    wrote leaves its kind behind, held back until the library is read again; focus moving on from a
 *    run's button is asked after the blur of its removal. Re-time saved lyrics is one component
 *    (components/RetimeLyrics.tsx) both settings pages draw beside the lead, its run in its module,
 *    reading a REAL scan, an ended run let go once said and as a new lead is typed. The sidebar's
 *    Library care is an admin's, after Needs a look; You's row a desktop's; it is a sibling of the other
 *    Managing pages. Needs a look warns when ignores can't be saved. The Edit panel has no link to the
 *    main page left ("Choose the folder"), and its Lyrics note names Managing's Settings; the sidebar's
 *    "Open the main page" names nothing left only there (2.0.0-player.45).
 *  - Search extras (2.0.0-player.50): More from MusicBrainz through the MusicBrainz half's own
 *    latestOnly, appended by the first page's held rule to the search it was asked for, its button a
 *    secondary one under the rows; the chosen pressing's facts drawn with the picker (the store line
 *    still last); the maybe from owned's name match only when nothing is held by id; the album's and
 *    the pressing's links to musicbrainz.org opening beside; the pressing list's filter outside the
 *    listbox, only for a long list, emptied as it closes, its field's own keys left to it. After review:
 *    More's last page handing focus on when it had it; the Pressing button's close emptying the filter
 *    too; a pressing the list reveals kept clear of the filter by its scroll-padding.
 *  - Search like Apple Music (2.0.0-player.55): one list - its rows app/SearchRows.tsx's, stateless, reaching no
 *    playback action (a library song's tap is Search's playSong, synchronously); its rules lib/searchList.ts's, pure;
 *    Top results and the sections frozen at the draw (drawn from `drawn`, never picked at render), the frame kept with
 *    them; each MusicBrainz kind through its own latestOnly (the artists' new), albums then artists then songs, each
 *    waiting a moment for the library, the sections at moment 2; held albums search3 didn't list brought into their
 *    holder's block with no Get; the chips outside the form; the Navidrome gate above the list, MusicBrainz outside it;
 *    App's MusicBrainz artist by `mb:`.
 *  - Song search (2.0.0-player.53): Search's songs through a latestOnly of their own, asked beside the albums
 *    from the same reading (and once a text) - after the album half's own request, the albums never waiting
 *    for them (review) - the library waited for as the albums wait; a title beside an artist that finds no
 *    song asked again as the words typed as one title, free text never twice; songs landing after the albums
 *    were drawn folded, by an answer drawn (an effect), never by its own Try again; More songs through it
 *    too, merged with the drawn songs kept in place, only for its search; called off and emptied with the box;
 *    drawn in a section of their own before the albums', a few at first; a song's album you have opening the
 *    album you have through the held rows' latestOnly - else, the bridge answering nothing or failing, its page
 *    with the song's recordings - App passing them in the address with the album's name, no preview and a
 *    fresh scroll; the page choosing a pressing with the song, marking it on both frames, writing every pick,
 *    and bringing it into view once, only while it shows and from its top; lib/songs.ts pure.
 *  - Inside a track (2.0.0-player.44): the Edit panel's track inspector (app/TrackInspector.tsx), the cover
 *    viewer (app/CoverViewer.tsx) and an album page's Properties (app/AlbumProperties.tsx) call no playback
 *    action - nothing on the list below gains a file. The inspector is drawn by the Edit panel alone, in
 *    its Tags tab, over the list (the tag editor over it): a track's NAME opens it, its tick box still
 *    ticks; it is a layer - the panel covered under it, an Escape inside the panel taking it back to the
 *    list (one layer at a time; Escape out in the page the page's); focus goes to its Back as it opens,
 *    back to the track's own name (the list scrolled where it was, by an effect once drawn, then that
 *    name brought into view - review) as it closes, stays on Previous and Next (aria-disabled at the
 *    ends, never disabled), and back to "Edit this track…" as the tag editor it opened closes - which is
 *    the tag editor on that one file alone (review); it starts afresh for every Edit and folder, and
 *    follows a rename. Its lyrics go through a latestOnly(). The cover viewer is the main page's
 *    ArtViewer, reached only through CoverViewer - from an album page's cover (both frames), Artwork's
 *    cover and CD art, and the inspector's pictures, each opener taken in the tap; the panel's drawn
 *    inside the panel; closed by a move through the history (review). Properties come from the bridge
 *    answer the album page asks already (no new request), and the unresized cover is asked for by the
 *    viewer alone, first, the sized one its fallback (review).
 *  - The page's entry renders App, and the old shell and settings sheet are gone.
 *
 * Run it with:  node ui/test/app-rules.sim.cjs
 */

const fs = require('fs'), path = require('path')

const SRC = path.resolve(__dirname, '../src')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/** Every .ts and .tsx under ui/src, as paths relative to it. */
function sources(dir = SRC) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) return sources(full)
    return /\.tsx?$/.test(entry.name) ? [path.relative(SRC, full).split(path.sep).join('/')] : []
  })
}

const read = (file) => fs.readFileSync(path.join(SRC, file), 'utf8')

/**
 * The code without its comments, strings kept - so a comment explaining a rule can name what the
 * rule is about. A small scanner, good for this repo's source: line and block comments, and
 * quoted and template strings, whose contents are kept as they are.
 */
function code(text) {
  let out = ''
  let state = 'code'
  for (let i = 0; i < text.length; i++) {
    const c = text[i], d = text[i + 1]
    if (state === 'code') {
      if (c === '/' && d === '/') { state = 'line'; i++; continue }
      if (c === '/' && d === '*') { state = 'block'; i++; continue }
      if (c === "'") state = 'single'
      else if (c === '"') state = 'double'
      else if (c === '`') state = 'template'
      out += c
    } else if (state === 'line') {
      if (c === '\n') { state = 'code'; out += c }
    } else if (state === 'block') {
      if (c === '*' && d === '/') { state = 'code'; i++ } else if (c === '\n') out += c
    } else {
      out += c
      if (c === '\\') { out += d ?? ''; i++; continue }
      if ((state === 'single' && c === "'") || (state === 'double' && c === '"') || (state === 'template' && c === '`')) state = 'code'
    }
  }
  return out
}

const ENGINE = new Set(['player/usePlayer.ts', 'player/streamSource.ts'])
const APP_SIDE = (file) => file.startsWith('app/') || file.startsWith('player/')

/** The only files the playback actions may be reached from - see the header. */
const ALLOWED = {
  'player/AlbumPage.tsx': ['playTracks'],
  'player/MiniPlayer.tsx': ['toggle', 'next'],
  'player/NowPlaying.tsx': ['toggle', 'next', 'previous', 'showAirPlay'],
  //? the Gapless checkbox in You > Playback, since 2.0.0-player.10: its click calls setGapless
  'app/GaplessChoice.tsx': ['setGapless'],
  //? the turntable's record, since 2.0.0-player.11: its click plays or pauses (a tap)
  'player/Turntable.tsx': ['toggle'],
  //? a song found by Search, since 2.0.0-player.13: its tap plays its album from it, the album in hand
  'app/Search.tsx': ['playTracks'],
  //? an artist's Play and Shuffle, since 2.0.0-player.17: every album of theirs you have, all in hand
  'app/ArtistPage.tsx': ['playTracks'],
  //? a Done row's ▶ on Requests, since 2.0.0-player.17: its album, in hand, else it opens it
  'app/Requests.tsx': ['playTracks'],
  //? the desktop's player bar, since 2.0.0-player.19: its transport and AirPlay, from the click
  'player/PlayerBar.tsx': ['toggle', 'next', 'previous', 'showAirPlay'],
  //? the desktop's visualizer, since 2.0.0-player.20: its play/pause, from the click or the Space key
  'player/Visualizer.tsx': ['toggle'],
  //? names them for ActionsContext and calls none (pickActions)
  'app/context.ts': ['playTracks', 'toggle', 'next', 'previous', 'setGapless', 'showAirPlay'],
  //? the speed (2.0.0-player.39): the turntable's fader - each move, a key, its readout's tap back to 1x -
  //? and the chip on the cover and the desktop's player bar, whose tap puts it back to 1x
  'player/SpeedFader.tsx': ['setSpeed'],
  'player/SpeedChip.tsx': ['setSpeed'],
}

/** Which playback actions a file's code reaches: by name, as a member, or taken apart from one. */
function actionsIn(text) {
  const found = new Set()
  for (const match of text.matchAll(/\b(playTracks|setGapless|showAirPlay|setSpeed)\b/g)) found.add(match[1])
  //? toggle, next and previous are ordinary words, so only as a member - classList.toggle aside
  for (const match of text.matchAll(/(?<!classList)\.(toggle|next|previous)\b/g)) found.add(match[1])
  //? and taken out of an object: const { toggle } = player (the KEY taken - `{ nav: next }` takes nav)
  for (const match of text.matchAll(/\{([^{}]*)\}\s*=/g)) {
    for (const part of match[1].split(',')) {
      const key = part.split(/[:=]/)[0].replace(/^\s*\.\.\./, '').trim()
      if (['toggle', 'next', 'previous'].includes(key)) found.add(key)
    }
  }
  return [...found].sort()
}

/** Whether a file's code imports usePlayer as a VALUE from the engine - renamed or not. A
 *  type-only import, and usePosition beside it, are fine: they make no audio element. */
function importsUsePlayer(text) {
  for (const match of text.matchAll(/import\s+(type\s+)?([^;]*?)\s+from\s+['"]([^'"]+)['"]/gs)) {
    if (match[1] || !/(^|\/)usePlayer$/.test(match[3])) continue
    const named = /\{([^}]*)\}/.exec(match[2])?.[1] ?? ''
    const names = named.split(',').map((part) => part.trim()).filter((part) => part && !part.startsWith('type '))
    if (names.some((part) => part.split(/\s+as\s+/)[0].trim() === 'usePlayer')) return true
    if (/\*\s+as\s+\w+/.test(match[2])) return true
  }
  return false
}

/** Every <a ...> opening tag in a file's code, and whether it goes somewhere outside the app. */
function linksOut(text) {
  return [...text.matchAll(/<a\b[^>]*>/g)].map((match) => match[0]).filter((tag) => {
    const href = /\bhref=(?:"([^"]*)"|'([^']*)'|\{)/.exec(tag)
    //? a link that SAVES a file (`download`) leaves nothing: Debug's recording (2.0.0-player.32)
    return href && !((href[1] ?? href[2] ?? '').startsWith('#')) && !/\bdownload\b/.test(tag)
  })
}

const opensBeside = (tag) => /\btarget="_blank"/.test(tag) && /\brel="[^"]*\bnoopener\b[^"]*"/.test(tag)

const files = sources()

console.log('\nusePlayer() is called once, in App')
{
  const calls = files.flatMap((file) => {
    const text = code(read(file)).replace(/\bfunction usePlayer\(/g, ENGINE.has(file) ? '' : 'function usePlayer(')
    const count = (text.match(/\busePlayer\(/g) ?? []).length
    return count ? [[file, count]] : []
  })
  check('the only call, and only one there', calls, [['app/App.tsx', 1]])
  check('...inside App, the root', /export function App\(\) \{\s*const player = usePlayer\(\)/.test(read('app/App.tsx')), true)
  check('only App imports it as a value, under any name',
    files.filter((file) => !ENGINE.has(file) && importsUsePlayer(code(read(file)))), ['app/App.tsx'])
}

console.log('\nthe playback actions only from the files allowed')
{
  const reached = files
    .filter((file) => APP_SIDE(file) && !ENGINE.has(file))
    .map((file) => [file, actionsIn(code(read(file)))])
    .filter(([, found]) => found.length)
  const outside = reached.filter(([file, found]) => found.some((name) => !(ALLOWED[file] ?? []).includes(name)))
  check('no file reaches one it isn\'t allowed', outside, [])
  check('where they are reached', Object.fromEntries(reached), {
    'app/ArtistPage.tsx': ['playTracks'],
    'app/GaplessChoice.tsx': ['setGapless'],
    'app/Requests.tsx': ['playTracks'],
    'app/Search.tsx': ['playTracks'],
    'app/context.ts': ['next', 'playTracks', 'previous', 'setGapless', 'showAirPlay', 'toggle'],
    'player/AlbumPage.tsx': ['playTracks'],
    'player/MiniPlayer.tsx': ['next', 'toggle'],
    'player/NowPlaying.tsx': ['next', 'previous', 'showAirPlay', 'toggle'],
    'player/PlayerBar.tsx': ['next', 'previous', 'showAirPlay', 'toggle'],
    'player/SpeedChip.tsx': ['setSpeed'],
    'player/SpeedFader.tsx': ['setSpeed'],
    'player/Turntable.tsx': ['toggle'],
    'player/Visualizer.tsx': ['toggle'],
  })
  check('app/context.ts names them and calls none',
    [...code(read('app/context.ts')).matchAll(/\.(playTracks|toggle|next|previous|setGapless|showAirPlay)\s*\(/g)].map((m) => m[1]), [])
}

console.log('\nthe speed (2.0.0-player.39): set from the fader and the chip alone, put on the elements by the engine alone')
{
  //? by name, from exactly the files that call it - and each calls it straight from its handler
  const fader = code(read('player/SpeedFader.tsx'))
  const chip = code(read('player/SpeedChip.tsx'))
  check('the fader sets it from a move, a key and its readout\'s tap - nothing awaited before',
    [/const onPointerMove = \(event: PointerEvent\) => \{[\s\S]*?if \(to !== null\) player\.setSpeed\(to\)\s*\}/.test(fader),
      /const onKeyDown = \(event: KeyboardEvent\) => \{[\s\S]*?player\.setSpeed\(to\)\s*\}/.test(fader),
      /onClick=\{\(\) => player\.setSpeed\(SPEED_NORMAL\)\}/.test(fader), /\bawait\b|\.then\(/.test(fader)],
    [true, true, true, false])
  //? (its handler hands focus on to the next button after it, as the chip goes - review of 2.0.0-player.39)
  check('the chip\'s tap puts it back to exactly 1x, and nothing else - from its handler, nothing awaited',
    [/const onTap = \(event: MouseEvent\) => \{[\s\S]*?player\.setSpeed\(SPEED_NORMAL\)[\s\S]*?\}/.test(chip), /onClick=\{onTap\}/.test(chip), (chip.match(/setSpeed\(/g) ?? []).length, /\bawait\b|\.then\(/.test(chip)],
    [true, true, 1, false])
  //? where each is drawn: the fader in the turntable alone (outside Now Playing's grip, as the record and
  //? the arm are), the chip in Now Playing's icon row and the desktop's player bar's tools
  const drawnIn = (name) => files.filter((file) => APP_SIDE(file) && new RegExp(`<${name}\\b`).test(code(read(file))))
  check('the fader is drawn by the turntable alone; the chip by Now Playing and the player bar', [drawnIn('SpeedFader'), drawnIn('SpeedChip')],
    [['player/Turntable.tsx'], ['player/NowPlaying.tsx', 'player/PlayerBar.tsx']])
  const nowPlaying = code(read('player/NowPlaying.tsx'))
  check('...the chip at the start of the icon row - one fixed height, its buttons at its right end - never above the title or in the grip',
    [/<div class="pl-sheet-footer">\s*<SpeedChip player=\{player\} \/>/.test(nowPlaying), nowPlaying.indexOf('<SpeedChip') > nowPlaying.indexOf('class="pl-sheet-body"')],
    [true, true])
  const bar = code(read('player/PlayerBar.tsx'))
  check('...and first in the player bar\'s tools', /<div class="app-playbar-tools">\s*<SpeedChip player=\{player\} \/>/.test(bar), true)
  //? only the engine puts a rate or a pitch switch on an element: the visualizer's own silent copy is a
  //? node of its own (its playbackRate an AudioParam, `.playbackRate.value`), never the player's element
  const SETS = /\.(playbackRate|defaultPlaybackRate)\s*=(?!=)|\b(preservesPitch|webkitPreservesPitch|mozPreservesPitch)\b/
  check('nothing outside the engine sets a rate or a pitch switch on an element', files.filter((file) => APP_SIDE(file) && !ENGINE.has(file) && SETS.test(code(read(file)))), [])
  const engine = code(read('player/usePlayer.ts'))
  check('...the engine on every element: the page\'s at the start, the spare as it is made, all of them as it changes, and whatever plays just before its play()',
    [/applySpeed\(elements\[0\]!\)/.test(engine), /spare\.muted = true\s*applySpeed\(spare\)/.test(engine), /elements\.forEach\(applySpeed\)/.test(engine),
      /applySpeed\(audio\)\s*audio\.play\(\)/.test(engine)],
    [true, true, true, true])
}

console.log('\nnothing outside app/ and player/ can reach the player')
{
  const reaching = files.filter((file) => !APP_SIDE(file)).filter((file) =>
    /from\s+['"][^'"]*(player\/usePlayer|app\/context|app\/App)['"]/.test(code(read(file))))
  check('no import of usePlayer, the contexts or App', reaching, [])
}

console.log('\nthe downloads are watched once, in App')
{
  const calls = files.filter(APP_SIDE).flatMap((file) => {
    const count = (code(read(file)).match(/\buseDownloadJobs\(/g) ?? []).length
    return count ? [[file, count]] : []
  })
  check('useDownloadJobs( only in App, and once there', calls, [['app/App.tsx', 1]])
  const app = code(read('app/App.tsx'))
  check('...fast only while the Requests tab\'s root shows, or a failed look left something arriving; and taking this page\'s download requests',
    [/useDownloadJobs\(watching === 'requests' \|\| stalled\)/.test(app), /useEffect\(\(\) => handleDownloadRequests\(enqueue\), \[enqueue\]\)/.test(app)], [true, true])
  //? (2.0.0-player.20: the desktop's visualizer covers the screen as Now Playing does a phone's - nothing
  //? behind it is watched, and Requests' fast poll stops under it)
  check('...what it watches worked out by watchingOf, from the tab, its stack, Now Playing or the desktop\'s visualizer, and the page being shown',
    [/const watching = watchingOf\(\{ shown: pageShown, tab: nav\.tab, depth: nav\.stacks\[nav\.tab\]\.length, sheetOpen: sheetOpen \|\| \(desktop && visualizing\) \}\)/.test(app),
      app.indexOf('const [visualizing, setVisualizing] = useState(false)') >= 0 && app.indexOf('const [visualizing, setVisualizing] = useState(false)') < app.indexOf('const watching = watchingOf(')],
    [true, true])
  check('...a failed look keeps it asking while something is arriving (stallsOn), turned off by the next answer',
    [/const stalls = stallsOn\(watching, downloadsError, view\.arriving\.length\)/.test(app), /useEffect\(\(\) => setStalled\(stalls\), \[stalls\]\)/.test(app)], [true, true])
  check('...asked again as Home comes into view or the app comes back - the last look moved on each time - never on a timer of its own',
    [/const before = watched\.current\s*watched\.current = watching\s*if \(asksAgain\(before, watching\)\) refresh\(\)/.test(app), /setInterval|setTimeout/.test(app)], [true, false])
  check('...and Requests told when deadwax has first answered, so it never says "nothing" before it knows',
    /answered=\{answered\.current\}/.test(app), true)
}

console.log('\nno blocking dialog in the app')
{
  //? confirm(), alert() and prompt() hold the page's JavaScript until answered, and this page plays
  //? the music: a song ending under one waits for it, and a stream stops being fed
  const dialogs = files.filter(APP_SIDE).flatMap((file) =>
    [...code(read(file)).matchAll(/(?<![\w.])(?:window\.)?(confirm|alert|prompt)\s*\(/g)].map((match) => `${file}: ${match[1]}`))
  check('none of confirm(), alert() or prompt() in app/ or player/', dialogs, [])
  check('...found where it is (the check sees one)', [...code('if (!window.confirm(x)) return').matchAll(/(?<![\w.])(?:window\.)?(confirm|alert|prompt)\s*\(/g)].length, 1)
}

console.log('\nan album page is memoised on what it reads of the player')
{
  const app = code(read('app/App.tsx'))
  //? usePlayer returns a new object on every render, so a memo keyed on `player` held for no poll
  check('the pages are memoised on the playing song and whether it plays - never the whole player',
    //? (2.0.0-player.15: and the Sources sheet and whether the app is in front, which the group page's `shown` reads;
    //? 2.0.0-player.19: and the frame, and which album - and pressing - a desktop's Sources panel shows)
    //? 2.0.0-player.21: and the Edit toggle's state - admin, the panel, its album - and an edit's refresh)
    //? 2.0.0-player.33: and the visualizer, which the server settings' and the log's `live` read)
    //? 2.0.0-player.45: and the artist page's panel - open, its request - and an artist page's refresh)
    //? 2.0.0-player.47: and Now Playing, which a phone's Managing pages' `live` reads as the visualizer)
    [/const playingId = player\.track\?\.id \?\? null/.test(app), /\[nav, status, playingId, player\.playing, sourcesOpen, pageShown, desktop, sourcesGroup, sourcesPressing, admin, editOpen, edit, refreshes, visualizerShown, sheetOpen, artistOpen, artistManage, artistRefreshes\],\s*\)/.test(app), /\[nav, player, status\]/.test(app)], [true, true, false])
  const page = code(read('player/AlbumPage.tsx'))
  check('...which is all an album page reads of it (read more there, and key the memo on it too)',
    [...new Set([...page.matchAll(/\bplayer\.(\w+)/g)].map((match) => match[1]))].sort(), ['playTracks', 'playing', 'track'])
  check('...the playing song only by its id', [...page.matchAll(/\bplayer\.track\b(\?\.\w+)?/g)].map((match) => match[1]), ['?.id'])
}

console.log('\nnothing in app/ touches audio itself')
{
  const FORBIDDEN = [
    ['setActionHandler', /setActionHandler/],
    ['new Audio', /new\s+Audio\b/],
    ['<audio', /<audio\b/i],
    ['.src =', /\.src\s*=(?!=)/],
    ['srcObject', /srcObject/],
    ['.load(', /\.load\s*\(/],
  ]
  const hits = files.filter((file) => file.startsWith('app/')).flatMap((file) => {
    const text = read(file)  //? the whole file, comments included: none of these belongs in app/ at all
    return FORBIDDEN.filter(([, pattern]) => pattern.test(text)).map(([name]) => `${file}: ${name}`)
  })
  check('none of setActionHandler, new Audio, <audio, .src =, srcObject, .load(', hits, [])
  check('the app/ files were looked at', files.filter((file) => file.startsWith('app/')).length >= 8, true)
}

console.log('\na link out of the app opens beside it')
{
  const out = files.filter(APP_SIDE).flatMap((file) => linksOut(code(read(file))).map((tag) => [file, tag]))
  check('every one opens in a new tab, rel="noopener"', out.filter(([, tag]) => !opensBeside(tag)), [])
  //? the Search placeholder's link went with it in 2.0.0-player.13 (Requests' in .12); the desktop
  //? sidebar's Managing link came in 2.0.0-player.19, and the Edit panel's to the main page's library
  //? (an album it can't find a folder for) in 2.0.0-player.21, and Needs a look's phone note in .25
  //? and (2.0.0-player.33) the server settings' line and its phone note, and the log's phone note
  //? (2.0.0-player.36: and Info > Debug's link to the turntable's test bench, a page of its own)
  //? (2.0.0-player.45: and an artist page's links - their site, their socials - in its About)
  //? (2.0.0-player.47: the four phone notes went - Needs a look, Library care, the settings and the log are
  //? drawn on a phone - and so did the gate's link to the main page's settings tab: "Set up Navidrome" opens
  //? the app's own Settings at Connections)
  check('...and there are links to look at (You, the desktop sidebar, the server settings\' line, Info > Debug\'s test bench, an artist\'s About, an album\'s Properties, the album you don\'t have)',
    //? (2.0.0-player.42: the Edit panel's went - "Choose the folder" took its place - and Library care's
    //? phone note came; 2.0.0-player.44: an album page's Properties, its release on musicbrainz.org;
    //? 2.0.0-player.50: the album you don't have, its group and its pressing on musicbrainz.org)
    [...new Set(out.map(([file]) => file))].sort(), ['app/AlbumProperties.tsx', 'app/ArtistPage.tsx', 'app/InfoSheet.tsx', 'app/ReleaseGroupPage.tsx', 'app/ServerSettings.tsx', 'app/Sidebar.tsx', 'app/You.tsx'])
}

console.log('\nNow Playing covers everything behind it')
{
  const app = code(read('app/App.tsx'))
  //? 2.0.0-player.15: inert behind Now Playing OR the Sources sheet - each covers what would open the other
  const behind = /<div class="app-behind" aria-hidden=\{covered\} inert=\{covered\}>([\s\S]*?)<\/div>\s*(?:\{(?:\/\*[\s\S]*?\*\/)?\}\s*)?<Sources\b[^\n]*\/>\s*<NowPlaying/.exec(app)
  check('the panes, the mini player and the tab bar are inside one inert wrapper',
    [!!behind, /TABS\.map/.test(behind?.[1] ?? ''), /<MiniPlayer\b/.test(behind?.[1] ?? ''), /<TabBar\b/.test(behind?.[1] ?? '')], [true, true, true, true])
  //? 2.0.0-player.19: on a phone - a desktop's side panel leaves the page beside it as it is
  //? (2.0.0-player.20: and behind the desktop's visualizer, which covers the whole screen)
  check('...inert while Now Playing, the Sources sheet, the artist page\'s or the Edit sheet shows, on a phone - or the visualizer, on a desktop',
    //? (2.0.0-player.33: visualizerShown is worked out earlier now - the pages memo reads it)
    //? (2.0.0-player.45: the artist page's panel is a sheet over the whole screen on a phone)
    //? (2.0.0-player.47: and so is the Edit panel)
    [/const visualizerShown = desktop && visualizing\n/.test(app), /const covered = \(!desktop && \(sheetOpen \|\| sourcesOpen \|\| artistOpen \|\| editOpen\)\) \|\| visualizerShown/.test(app),
      (app.match(/const visualizerShown =/g) ?? []).length], [true, true, 1])
  //? (2.0.0-player.20) ...and a desktop's Sources or Info panel left open goes inert under the visualizer
  //? too - outside that wrapper, each takes it as `covered`, as Now Playing takes what is over it
  check('...and a desktop\'s Sources and Info panels, outside it, are inert under the visualizer',
    [/<Sources\b[^\n]*\bcovered=\{visualizerShown\}[^\n]*\/>/.test(app), /<InfoSheet\b[^>]*\bcovered=\{visualizerShown\}/.test(app),
      ...['app/Sources.tsx', 'app/InfoSheet.tsx'].flatMap((file) => [/aria-hidden=\{!open \|\| covered\} inert=\{!open \|\| covered\}/.test(code(read(file))),
        /useSheet\(\{ open, covered, onClose/.test(code(read(file)))])],
    [true, true, true, true, true, true])
  //? (2.0.0-player.21, after the rebase onto .20) ...and the Edit panel the same: built beside the
  //? visualizer, it had no `covered`, and stayed live and tabbable under it
  check('...and so is the Edit panel',
    [/<EditPanel\b[^\n]*\bcovered=\{visualizerShown\}[^\n]*\/>/.test(app),
      /aria-hidden=\{!open \|\| covered\} inert=\{!open \|\| covered\}/.test(code(read('app/EditPanel.tsx'))),
      /useSheet\(\{ open, covered: inner \|\| covered, onClose/.test(code(read('app/EditPanel.tsx')))],
    [true, true, true])
  check('...which the Sources sheet, Now Playing, its menu and Info are not in',
    /<\/div>\s*(?:\{\/\*[\s\S]*?\*\/\}\s*)?<Sources\b[^\n]*\/>\s*<NowPlaying\b[\s\S]*?\/>\s*(?:\{\/\*[\s\S]*?\*\/\}\s*)?<ActionMenu\b[\s\S]*?\/>\s*<InfoSheet\b[\s\S]*?\/>\s*<\/div>\s*<\/ActionsContext/.test(read('app/App.tsx')), true)
  const sheet = code(read('player/NowPlaying.tsx'))
  check('Now Playing takes focus to its close button as it opens, and gives it back to its opener',
    [/useSheet\(\{ open, covered, onClose, lockClass: 'pl-sheet-open', first: closeButton, opener \}\)/.test(sheet),
      /<button ref=\{closeButton\}[^>]*class="pl-sheet-close"/.test(sheet)], [true, true])
  check('the opener is taken in the tap, focusing itself first',
    [/const openSheet = useCallback\(\(event: MouseEvent\) => \{\s*sheetOpener\.current = takeOpener\(event\)\s*setSheetOpen\(true\)/.test(app),
      /onClick=\{onOpen\}/.test(code(read('player/MiniPlayer.tsx')))], [true, true])
}

console.log('\nevery sheet is a sheet by the one hook')
{
  const hook = code(read('app/useSheet.ts'))
  const SHEETS = {
    'player/NowPlaying.tsx': 'pl-sheet-open', 'app/ActionMenu.tsx': 'app-menu-open', 'app/InfoSheet.tsx': 'app-info-open',
    //? Get's sources (2.0.0-player.15)
    'app/Sources.tsx': 'app-sources-open',
    //? the desktop's Edit panel (2.0.0-player.21) - never a sheet, so its lock is never taken
    'app/EditPanel.tsx': 'app-edit-open',
    //? the artist page's panel (2.0.0-player.45) - a sheet on a phone, a side panel on a desktop
    'app/ArtistPanel.tsx': 'app-artist-panel-open',
  }
  const texts = Object.fromEntries(Object.keys(SHEETS).map((file) => [file, code(read(file))]))
  check('each calls useSheet with a scroll lock of its own',
    Object.fromEntries(Object.entries(texts).map(([file, text]) => [file, /useSheet\(\{[^}]*lockClass: '([^']+)'/.exec(text)?.[1] ?? null])), SHEETS)
  check('...and they are the only ones', files.filter((file) => /\buseSheet\(/.test(code(read(file))) && file !== 'app/useSheet.ts').sort(), Object.keys(SHEETS).sort())
  check('each is inert while closed', Object.values(texts).map((text) => /\binert=\{!open\b/.test(text)), [true, true, true, true, true, true])
  check('Now Playing is inert under the menu or Info, and they are hidden from it', /aria-hidden=\{!open \|\| covered\}\s*inert=\{!open \|\| covered\}/.test(texts['player/NowPlaying.tsx']), true)
  check('the menu, Info, the sources and the artist page\'s close on their backdrop (a panel\'s is not drawn)',
    ['app/ActionMenu.tsx', 'app/InfoSheet.tsx', 'app/Sources.tsx', 'app/ArtistPanel.tsx'].map((file) => /<div class="app-backdrop" onClick=\{onClose\} \/>/.test(texts[file])), [true, true, true, true])
  //? (2.0.0-player.47, review: beside a phone's Edit sheet - a phone on its side, an iPad upright - a stray
  //? tap on the backdrop threw away an edit half made)
  check('...the Edit sheet\'s takes a tap and closes nothing - it holds typed work; its close button and Escape close it',
    [/<div class="app-backdrop" \/>/.test(texts['app/EditPanel.tsx']), /class="app-backdrop"[^>]*onClick/.test(texts['app/EditPanel.tsx']),
      /class="app-edit-close"[^>]*onClick=\{onClose\}/.test(texts['app/EditPanel.tsx']), /useSheet\(\{ open, covered: inner \|\| covered, onClose,/.test(texts['app/EditPanel.tsx'])],
    [true, false, true, true])
  //? (2.0.0-player.19: a desktop's side panel is no sheet over the page - no lock - and Escape closes
  //? it only from inside it; a sheet is modal unless it says otherwise)
  check('the hook: the lock on <html> (a sheet\'s, never a panel\'s), focus in, focus back, Escape for the one on top',
    [/document\.documentElement\.classList\.toggle\(lockClass, open && modal\)/.test(hook) && /modal = true,/.test(hook),
      /first\.current\?\.focus\(/.test(hook),
      /opener\?\.current\?\.focus\(/.test(hook),
      /if \(!open \|\| covered\) return/.test(hook) && /event\.key !== 'Escape'/.test(hook)], [true, true, true, true])
  check('an opener focuses itself before it is taken (the WebKit rule)', /target\.focus\(\{ preventScroll: true \}\)\s*return target/.test(hook), true)
  check('a panel beside the page closes on Escape only from inside it (2.0.0-player.19)',
    /if \(!modal && area\?\.current && !area\.current\.contains\(event\.target as Node \| null\)\) return/.test(hook), true)
  const app = code(read('app/App.tsx'))
  //? each element's own props, up to its `/>`, so a check can't be answered by the NEXT element's
  //? props (App's props for these hold no '>'; one that did would fail here, loudly)
  const propsOf = (tag) => new RegExp(`<${tag}\\b([^>]*)/>`).exec(app)?.[1] ?? null
  const sheets = { NowPlaying: propsOf('NowPlaying'), ActionMenu: propsOf('ActionMenu'), InfoSheet: propsOf('InfoSheet') }
  check('each sheet\'s props are found, on their own', Object.values(sheets).map((props) => typeof props === 'string' && props.includes('onClose=')), [true, true, true])
  const has = (tag, pattern) => pattern.test(sheets[tag] ?? '')
  check('the ••• button is the menu\'s opener and Info\'s',
    [/const openMenu = useCallback\(\(event: MouseEvent\) => \{\s*moreOpener\.current = takeOpener\(event\)/.test(app),
      has('ActionMenu', /\bopener=\{over === 'info' \? undefined : moreOpener\}/),
      //? 2.0.0-player.19: a desktop's Info panel gives focus back to the player bar's Info
      has('InfoSheet', /\bopener=\{desktop \? infoOpener : moreOpener\}/)], [true, true, true])
  //? 2.0.0-player.19: on a desktop Info is the side panel the player bar opens, with no Now Playing
  check('never both over Now Playing, and neither without it - on a phone',
    [has('ActionMenu', /\bopen=\{sheetOpen && over === 'menu'\}/), has('InfoSheet', /\bopen=\{infoOpen\}/),
      /const infoOpen = desktop \? infoPanel : sheetOpen && over === 'info'/.test(app),
      has('NowPlaying', /\bcovered=\{over !== 'none'\}/)], [true, true, true, true])
  //? "Go to album", from the menu, the album line and Info's card alike: every sheet closes (with no
  //? focus sent back to ••• in a sheet that is going), and the album opens on the tab showing
  const going = /const goToAlbum = \(track[^)]*\) => \{([\s\S]*?)\n  \}/.exec(app)?.[1] ?? ''
  check('Go to album closes every sheet and opens the album the way a tile does',
    [/moreOpener\.current = null\s*closeSheet\(\)\s*openAlbum\(/.test(going), /const closeSheet = useCallback\(\(\) => \{\s*setOver\('none'\)\s*setSheetOpen\(false\)/.test(app)],
    [true, true])
  check('...one handler for all three, each in its own props', ['NowPlaying', 'ActionMenu', 'InfoSheet'].map((tag) => has(tag, /\bonAlbum=\{toAlbum\b/)), [true, true, true])
  check('the menu is handed the album\'s pin (2.0.0-player.18)', [has('ActionMenu', /\bpinned=\{menuPinned\}/), has('ActionMenu', /\bonPin=\{pinPlaying\}/)], [true, true])
  //? 2.0.0-player.14: Info's "Turntable sound" from the deck's report, which App is told of as it
  //? changes; and Now Playing handed "Pause winds the record down"
  check('Info is handed the turntable\'s sound, App told of it as it changes; Now Playing the wind-down setting',
    [has('InfoSheet', /\bturntable=\{turntableSound\}/), /useEffect\(\(\) => onDeckReport\(setTurntableSound\), \[\]\)/.test(app),
      has('NowPlaying', /\bwindDown=\{windDown\}/)], [true, true, true])
}

console.log('\nGapless is a checkbox in You, and its tap is still the gesture')
{
  const choice = code(read('app/GaplessChoice.tsx'))
  check('setGapless is called straight from the click', /onClick=\{\(\) => player\.setGapless\(!player\.gapless\)\}/.test(choice), true)
  check('...with nothing awaited, and no change event', [/\bawait\b/.test(choice), /\.then\(/.test(choice), /onChange=/.test(choice)], [false, false, false])
  check('a checkbox, not a switch', [/role="checkbox"/.test(choice), /role="switch"/.test(choice)], [true, false])
  const you = code(read('app/You.tsx'))
  check('You hands it the player, and names no playback action itself', [/<GaplessChoice player=\{player\} \/>/.test(you), actionsIn(you)], [true, []])
  check('Now Playing has no Gapless control left', /[Gg]apless/.test(code(read('player/NowPlaying.tsx'))), false)
}

console.log('\nnothing below the title in Now Playing can change height')
{
  const sheet = code(read('player/NowPlaying.tsx'))
  const body = sheet.slice(sheet.indexOf('<div class="pl-sheet-body">'))
  const at = (needle) => body.indexOf(needle)
  check('the readouts are gone from it', [/describe(Gaps|Seek|Wrap)/.test(sheet), /pl-readouts/.test(sheet)], [false, false])
  check('the failure line is above the title', [at('class="pl-sheet-error"') !== -1, at('class="pl-sheet-error"') < at('class="pl-sheet-title"')], [true, true])
  check('then the title, the album line, the bar, the transport, the icons',
    ['class="pl-sheet-title"', 'pl-sheet-artist', '<Scrubber ', 'class="pl-transport"', 'class="pl-sheet-footer"'].map(at).every((place, index, all) => place !== -1 && (index === 0 || place > all[index - 1])), true)
  check('...the turntable\'s time line in the bar\'s place, one or the other',
    /\{turntable \? <TurntableTime player=\{player\} previewing=\{previewing\} \/> : <Scrubber player=\{player\} \/>\}/.test(body), true)
  check('the album line is one box, link or not', (body.match(/<span class="pl-sheet-byline">\{byline\}<\/span>/g) ?? []).length, 2)
  const footer = body.slice(at('class="pl-sheet-footer"'))
  check('the icon row: AirPlay only with a speaker, ••• always, and no dead Lyrics or Up next',
    [/\{player\.airplay && \(\s*<button[^>]*onClick=\{player\.showAirPlay\}/.test(footer), /onClick=\{onMore\}/.test(footer), /Lyrics|Up next/.test(footer)], [true, true, false])
  const css = fs.readFileSync(path.resolve(SRC, '../../interface/player/player.css'), 'utf8')
  check('...a fixed height, so AirPlay coming and going moves nothing', /\.pl-sheet-footer \{[^}]*(?<![-\w])height: var\(--pl-hit\);/.test(css), true)
  const appCss = fs.readFileSync(path.resolve(SRC, '../../interface/player/app.css'), 'utf8')
  check('...and the time line one line, whatever it says', /\.app-tt-time \{[^}]*white-space: nowrap;/.test(appCss), true)
}

console.log('\nthe turntable: a tap in the click, a seek as it lets go, and none of it the grip\'s')
{
  const table = code(read('player/Turntable.tsx'))
  const click = /const onRecordClick = \(\) => \{([\s\S]*?)\n  \}/.exec(table)?.[1] ?? ''
  check('the record plays or pauses from its click, nothing awaited before it',
    [/<button\b[^>]*class="app-tt-record"[\s\S]*?onClick=\{onRecordClick\}/.test(table), /player\.toggle\(\)/.test(click), /\bawait\b|\.then\(/.test(click)], [true, true, false])
  //? every player.seek in the file, by the handler it is in: the release, the arm's keys and - since
  //? 2.0.0-player.14 - the tap's pause, to where its wind-down stops; never a move
  const handlers = [...table.matchAll(/const (\w+) = [^\n]*=> \{?[\s\S]*?\n  \}/g)].map((match) => [match[1], match[0]])
  check('it seeks only as a finger lets go, a key steps, or its tap pauses (to where the wind-down stops)',
    handlers.filter(([, body]) => /player\.seek\(/.test(body)).map(([name]) => name).sort(), ['onArmKey', 'onRecordClick', 'onRelease'])
  check('...and moving reaches the player not at all', /player\./.test(handlers.find(([name]) => name === 'onMove')?.[1] ?? 'player.'), false)
  //? 2.0.0-player.14: the toggle reached from the tap, from a release with no coast to wait for (its own
  //? gesture), and from the deck's two moves of the song - pause as a hand takes the record, play at
  //? speed after a coast - each a named function, each only when the song is the other way
  check('the toggle is reached from the tap, a release, and the deck\'s two named moves - nowhere else',
    handlers.filter(([, body]) => /\.toggle\(\)/.test(body)).map(([name]) => name).sort(), ['holdSong', 'onRecordClick', 'onRelease', 'resumeSong'])
  check('...the deck\'s, only when the song is playing (hold) or paused (resume)',
    [/const holdSong = \(\) => \{\s*if \(latest\.current\.playing\) latest\.current\.toggle\(\)\s*\}/.test(table),
      /const resumeSong = \(\) => \{\s*if \(!latest\.current\.playing\) latest\.current\.toggle\(\)\s*\}/.test(table),
      /hold: \(\) => holdSong\(\),\s*resume: \(\) => resumeSong\(\),/.test(table)], [true, true, true])
  check('...and a release plays only when the deck says there is no coast to wait for',
    /if \(play && !player\.playing\) player\.toggle\(\)/.test(handlers.find(([name]) => name === 'onRelease')?.[1] ?? ''), true)
  check('no frame loop of its own and nothing from the engine\'s clock: the platter is the deck\'s, the arm usePosition',
    //? (2.0.0-player.36: usePosition handed the turntable's narrower player, which is all it reads of one)
    [/requestAnimationFrame|setInterval|setTimeout/.test(table), /usePosition\(player( as Player)?\)/.test(table), /visibilitychange/.test(table),
      /requestAnimationFrame/.test(code(read('player/deck.ts')))], [false, true, true, true])
  const sheet = code(read('player/NowPlaying.tsx'))
  //? the element, not the type TurntablePreview or TurntableTime
  const drawn = sheet.search(/<Turntable\s/)
  const grip = sheet.slice(sheet.indexOf('class={`pl-sheet-grip'), drawn)
  //? from inside the grip's opening tag to the turntable: every <div> opened there closed, and one
  //? more - the grip's own
  check('the record and the arm are outside the grip - drawn after it closes, never inside it',
    [drawn > sheet.indexOf('class={`pl-sheet-grip'), (grip.match(/<\/div>/g) ?? []).length - (grip.match(/<div\b/g) ?? []).length], [true, 1])
  check('the look is Now Playing\'s, opened as the setting says',
    [/const \[look, setLook\] = useState<Look>\(openAs\)/.test(sheet), /useLayoutEffect\(\(\) => \{\s*if \(open\) setLook\(openAs\)\s*\}, \[open\]\)/.test(sheet)], [true, true])
  const app = code(read('app/App.tsx'))
  check('...App keeps only the setting, and never draws the turntable', [/<Turntable\b/.test(app), /setLook|otherLook/.test(app), /openAs=\{opensAs\}/.test(app)], [false, false, true])
}

console.log('\nthe turntable\'s sound: its audio context only from a gesture, and never the player\'s element')
{
  //? every call of the two outside the deck itself, by the handler it is in: the `const name = ... => {`
  //? block, closed at its own indent, that holds it
  const enclosing = (text, at) => {
    const blocks = [...text.matchAll(/\n( *)const (\w+) = [^\n]*=> \{[\s\S]*?\n\1\}/g)]
    const holding = blocks.filter((block) => block.index <= at && at < block.index + block[0].length)
    return holding.at(-1)?.[2] ?? null
  }
  //? (2.0.0-player.36: and the turntable's test bench's, a page of its own whose deck is the app's own -
  //? its play button and Start the sound, as the spec has them, and its motions', Record's, the device
  //? check's and Carry on's buttons, each a click)
  const wakes = files.filter((file) => (APP_SIDE(file) || file.startsWith('lab/')) && file !== 'player/deck.ts').flatMap((file) => {
    const text = code(read(file))
    return [...text.matchAll(/\b(wakeDeckAudio|resumeDeckAudio)\(\)/g)].map((match) => `${file}: ${enclosing(text, match.index)}: ${match[1]}`)
  })
  check('made or resumed only from gestures WebKit counts: the record\'s click and release, the transport, the look button, the mini player\'s tap - and the test bench\'s own buttons', wakes.sort(), [
    'app/App.tsx: openSheet: resumeDeckAudio',
    'app/App.tsx: openSheet: wakeDeckAudio',
    'lab/Bench.tsx: onCarryOn: wakeDeckAudio',
    'lab/Bench.tsx: onCheck: wakeDeckAudio',
    'lab/Bench.tsx: onMotion: wakeDeckAudio',
    'lab/Bench.tsx: onPlay: wakeDeckAudio',
    'lab/Bench.tsx: onRecord: wakeDeckAudio',
    'lab/Bench.tsx: onStart: wakeDeckAudio',
    'player/NowPlaying.tsx: onLook: wakeDeckAudio',
    'player/NowPlaying.tsx: onNext: wakeDeckAudio',
    'player/NowPlaying.tsx: onPrevious: wakeDeckAudio',
    'player/NowPlaying.tsx: onToggle: wakeDeckAudio',
    'player/Turntable.tsx: onRecordClick: wakeDeckAudio',
    'player/Turntable.tsx: onRelease: wakeDeckAudio',
  ])
  //? 2.0.0-player.30: the mini player's tap MAKES the sound when Now Playing will open as the turntable
  //? (James: "the scrubbing audio doesn't seem to load ever until after the first scrub" - until then only
  //? a tap on the turntable itself made it), and only resumes one otherwise
  check('...the mini player\'s tap makes it only when Now Playing opens as the turntable, else resumes',
    /if \(opensAsNow\.current === 'turntable'\) wakeDeckAudio\(\)\s*else resumeDeckAudio\(\)/.test(code(read('app/App.tsx'))), true)
  const made = files.filter((file) => /\bnew\s+(?:Context|AudioContext|webkitAudioContext)\b/.test(code(read(file))))
  //? (2.0.0-player.20: and the desktop visualizer's, its own - see "the desktop visualizer" below)
  check('...and made in two places, the deck and the visualizer\'s silent copy', made, ['player/deck.ts', 'player/vizAudio.ts'])
  //? 2.0.0-player.16: the main-thread voice (a page with no AudioWorklet) and the audio session it sets
  //? while it lives are the deck's too - nothing else makes a node or touches the page's session
  check('...as are its main-thread voice and the page\'s audio session (2.0.0-player.16)',
    [files.filter((file) => /createScriptProcessor/.test(code(read(file)))), files.filter((file) => /\baudioSession\b/.test(code(read(file))))],
    [['player/deck.ts'], ['player/deck.ts']])
  const deck = code(read('player/deck.ts'))
  const inDeck = [...deck.matchAll(/\n(export )?function (\w+)\([^)]*\)[^{]*\{[\s\S]*?\n\}/g)]
  const madeIn = inDeck.filter((fn) => /\bnew Context\(/.test(fn[0])).map((fn) => fn[2])
  const resumedIn = inDeck.filter((fn) => /\.resume\(\)/.test(fn[0])).map((fn) => fn[2])
  check('...inside wakeDeckAudio, which resumes it through resumeDeckAudio - the only two that start it',
    [madeIn, resumedIn, inDeck.filter((fn) => /\bresumeDeckAudio\(\)/.test(fn[0]) && fn[2] !== 'resumeDeckAudio').map((fn) => fn[2])],
    [['wakeDeckAudio'], ['resumeDeckAudio'], ['wakeDeckAudio']])
  check('the deck reaches no playback action of its own - only the host Turntable hands it', actionsIn(deck), [])
  const TOUCHES = [
    ['createMediaElementSource', /createMediaElementSource|createMediaStreamSource/],
    ['an element looked up', /querySelector\(\s*['"]audio|getElementsByTagName/],
    ['a media element', /HTMLMediaElement|HTMLAudioElement|new\s+Audio\b|<audio\b/],
    ['.src =', /\.src\s*=(?!=)/],
    ['srcObject', /srcObject/],
    ['.load(', /\.load\s*\(/],
    ['.play(', /\.play\s*\(/],
    ['.pause(', /\.pause\s*\(/],
  ]
  const touched = ['player/deck.ts', 'lib/deckVoice.ts', 'player/Turntable.tsx'].flatMap((file) =>
    TOUCHES.filter(([, pattern]) => pattern.test(code(read(file)))).map(([name]) => `${file}: ${name}`))
  check('nothing of it touches the player\'s own audio element', touched, [])
  const nowPlaying = code(read('player/NowPlaying.tsx'))
  check('the cover\'s pause is the plain toggle, as ever; only the turntable\'s asks the deck',
    /const onToggle = \(\) => \{\s*if \(!turntable\) \{\s*player\.toggle\(\)\s*return\s*\}/.test(nowPlaying), true)
  //? and the cover's previous and next wake nothing: with no turntable mounted, a context made there
  //? would run on unsuspended and unclosed - nothing of the deck runs while the cover shows
  check('...the cover\'s previous and next wake no audio context: only on the turntable',
    ['onPrevious', 'onNext'].map((name) => new RegExp(`const ${name} = \\(\\) => \\{\\s*if \\(turntable\\) wakeDeckAudio\\(\\)\\s*player\\.\\w+\\(\\)\\s*\\}`).test(nowPlaying)),
    [true, true])
}

console.log('\nthe turntable\'s test bench (2.0.0-player.36): its own player and windows, contexts only from a tap, nothing of the app\'s player')
{
  const bench = code(read('lab/Bench.tsx'))
  const handler = (name) => new RegExp(`\\n( *)const ${name} = [^\\n]*=> \\{([\\s\\S]*?)\\n\\1\\}`).exec(bench)?.[2] ?? ''
  //? the deck's recording may make its context (recordDeckSound wakes it): the Record button's click wakes
  //? the sound in the tap, and the recording starts once it runs (review: the first tap on a cold page was
  //? refused, "the sound has not started", though that tap had started it) - and from a motion only once
  //? the deck is live, its context running already
  const motion = /const motion = async \([\s\S]*?\n {2}\}\n/.exec(bench)?.[0] ?? ''
  const starting = handler('startRecording')
  check('the deck\'s recording: the Record button\'s click wakes the sound in the tap, and records once it runs; a motion records once the deck is live (its context running)',
    [/wakeDeckAudio\(\)\s*void startRecording\(\)/.test(handler('onRecord')),
      starting.indexOf("await until(() => deckReport()?.context === 'running'") >= 0 && starting.indexOf("await until(() => deckReport()?.context === 'running'") < starting.indexOf('recordDeckSound(RECORD_SECONDS, true)'),
      (bench.match(/recordDeckSound\(/g) ?? []).length,
      motion.indexOf('await until(() => deck.live()') >= 0 && motion.indexOf('await until(() => deck.live()') < motion.indexOf('recordDeckSound(')],
    [true, true, 2, true])
  check('the bench\'s play button pauses and plays as Now Playing\'s does on the turntable: the deck\'s pausing() and resuming()',
    [/const landing = deck\?\.pausing\(\) \?\? null\s*player\.toggle\(\)\s*if \(landing !== null\) player\.seek\(landing\)/.test(handler('onPlay')),
      /const from = deck\?\.resuming\(\) \?\? null\s*if \(from !== null\) player\.seek\(from\)\s*player\.toggle\(\)/.test(handler('onPlay'))], [true, true])
  //? ...and not while a motion or the check turns it (review): played under the hand, the song and the
  //? record's sound were heard together, and the release sought the playing song on and left the record
  //? still beside it. A motion is busy from its tap, its making ready included - before it turns - and one
  //? tap starts one
  check('...and the play button is refused, and said to be, while a motion (from its tap) or the check runs - and a motion\'s tap starts one motion',
    [/^\s*if \(!madeRef\.current \|\| busy\) return\s*wakeDeckAudio\(\)/.test(handler('onPlay')), /onClick=\{onPlay\} aria-disabled=\{!made \|\| busy\}/.test(bench),
      /const busy = !!running \|\| preparing \|\| !!check\?\.running/.test(bench),
      /if \(busy \|\| !made \|\| motionGoing\.current\) return\s*motionGoing\.current = true\s*setPreparing\(true\)/.test(handler('onMotion')),
      /\.finally\(\(\) => \{\s*motionGoing\.current = false\s*setPreparing\(false\)/.test(handler('onMotion')),
      /<div ref=\{deckBox\} class="lab-deck" inert=\{busy\}>/.test(bench)],
    [true, true, true, true, true, true])
  //? the runner asks for the player as it is - at the release too, after the take paused it: the bench's
  //? player is a new object each time it starts or stops (review: handed the one of the motion's start, a
  //? song the take paused was never played again)
  check('...a motion handed the player as it is when asked, never the one of its start; a check\'s run counted by runCounts, its blocks said by blocksLine',
    [/runMotion\(deck, \(\) => playerRef\.current, def,/.test(motion), /runMotion\(deck, playerRef\.current/.test(bench),
      /\.\.\.runCounts\(done\.data\.voice, before, after\?\.health\)/.test(bench), /\{ label: 'Blocks late', value: blocksLine\(run\) \}/.test(bench)],
    [true, false, true, true])
  //? its listening room: an AudioContext of its own, made only in make(), which only play() reaches,
  //? which only toggle() does - from the bench's Play button and Space's keyup, each a gesture
  const room = code(read('lab/listen.ts'))
  const roomMethods = [...room.matchAll(/\n {2}(?:private )?(\w+)\([^)]*\)[^{\n]*\{[\s\S]*?\n {2}\}/g)]
  check('its listening room makes its context only in make(), reached only from play(), reached only from toggle()',
    [roomMethods.filter((m) => /\bnew Room\(/.test(m[0])).map((m) => m[1]), roomMethods.filter((m) => /this\.make\(\)/.test(m[0])).map((m) => m[1]),
      roomMethods.filter((m) => /this\.play\(\)/.test(m[0])).map((m) => m[1]).sort()],
    [['make'], ['play'], ['restart', 'toggle']])
  check('...toggled only from the Play buttons\' click and Space\'s keyup (a gesture WebKit counts)',
    [[...bench.matchAll(/room\.toggle\(\)/g)].length, /const onListen = \(\) => \{\s*room\.toggle\(\)\s*\}/.test(bench), /const up = \(event: KeyboardEvent\) => \{\s*if \(event\.key !== ' '[^\n]*\n\s*event\.preventDefault\(\)\s*room\.toggle\(\)/.test(bench), (bench.match(/onClick=\{onListen\}/g) ?? []).length],
    [2, true, true, 2])
  //? the comparison's keys (review): on the document while a comparison shows - Space and 1-3 wherever the
  //? focus is (a click in WebKit focuses nothing, and a control the bench takes away drops it to the page),
  //? but never where something is typed into, and Space not on another control (whose own Space presses
  //? it): the comparison's own controls carry data-room, where Space plays or pauses it
  const keys = /useEffect\(\(\) => \{\s*if \(!compared\) return([\s\S]*?)\n {2}\}, \[compared\]\)/.exec(bench)?.[1] ?? ''
  check('...its keys on the document while a comparison shows - not where something is typed into, Space not on another control; on none of the sections',
    [/document\.addEventListener\('keydown', down\)/.test(keys) && /document\.addEventListener\('keyup', up\)/.test(keys), /document\.removeEventListener\('keyup', up\)/.test(keys),
      /INPUT\|SELECT\|TEXTAREA/.test(keys), /closest\('\[data-room\]'\)/.test(keys), /<section[^>]*onKey/.test(bench),
      (bench.match(/data-room/g) ?? []).length >= 5],
    [true, true, true, true, false, true])
  //? focus never dropped to the page (review): busy controls are aria-disabled, never disabled, their taps
  //? refused; a control the bench takes away hands focus to what replaces it; a comparison landing takes it
  check('...focus handed on: what the blind test takes away hands it to its next control, a comparison landing to its Play; the chips one tab stop, moved by the arrows',
    [/useLayoutEffect\(\(\) => \{\s*const next = focusNext\.current/.test(bench),
      ['startAbx', 'nextTrial'].map((name) => /focusNext\.current = \{ name: 'abx-play'/.test(handler(name))),
      /focusNext\.current = \{ name: answers\.length >= abx\.trials \? 'abx-back' : 'abx-next'/.test(handler('guess')),
      /focusNext\.current = \{ name: 'compare-play', force: false \}/.test(handler('backToCompare')),
      /focusNext\.current = \{ name: 'compare-play', force: true \}/.test(bench),
      ['compare-play', 'abx-play', 'abx-next', 'abx-back'].map((name) => bench.includes(`data-focus="${name}"`)),
      (bench.match(/tabIndex=\{room\.selected === index \? 0 : -1\}/g) ?? []).length, (bench.match(/onKeyDown=\{onChipKey\}/g) ?? []).length],
    [true, [true, true], true, true, true, [true, true, true, true], 2, 2])
  //? the song held still while anything records (review: a signal changed mid-recording was measured
  //? against the old one); a hidden page's run or recording thrown away, the check waiting for a tap to
  //? carry on; a check that stops part way still gives its file
  check('...the song held still while anything records; a hidden page\'s run or recording thrown away; a check that stops part way still gives its file',
    [/const recording = recorded\?\.state === 'recording' \|\| startingRecord/.test(bench), /const locked = busy \|\| recording/.test(bench),
      (bench.match(/<fieldset class="lab-fieldset" disabled=\{locked\}>/g) ?? []).length, /accept="audio\/\*"\s*disabled=\{locked\}/.test(bench), /onClick=\{onCheck\} aria-disabled=\{locked\}/.test(bench),
      /watchForHide\(\(\) => \{\s*run\?\.stop\(\)\s*if \(recordingIt\) stopDeckRecording\(\)/.test(motion) && motion.indexOf('watchForHide(') < motion.indexOf('await until(() => deck.live()'), /const watch = watchForHide\(\(\) => stopDeckRecording\(\)\)/.test(starting),
      /if \(what\.watch\?\.hidden\) \{\s*setComparing\(HIDDEN_RECORDING\)/.test(bench),
      /const hiding = watchForHide\(\)[\s\S]{0,900}done = await motion\(id, true, null\)[\s\S]{0,200}if \(!done\?\.interrupted && !hiding\.hidden\) break\s*setCheck\(state\(HIDDEN_CHECK, \{ waiting: true \}\)\)\s*await new Promise<void>\(\(go, stop\) => \{ carryOn\.current = \{ go, stop \} \}\)/.test(bench),
      /\} catch \(error\) \{[\s\S]{0,200}href: await save\(\{ complete: false/.test(bench)],
    [true, true, 2, true, true, true, true, true, true, true])
  //? what the bench says by reading.ts's rules (review): a recording nothing took said so before anything is
  //? worked out (it was told as a stall of the page), the check's runs by their verdict, the transport's
  //? line by transportLine (its "stopped" stayed up after Play brought the sound back)
  check('...a recording nothing took said so before it is compared; the check\'s runs say why they want recording again; the transport\'s line kept by transportLine',
    [/if \(!tookTheRecord\(data\.messages\)\) \{\s*setComparing\(NOT_TAKEN\)\s*return\s*\}/.test(handler('analyse')) && handler('analyse').indexOf('tookTheRecord(') < handler('analyse').indexOf('compareRecording('),
      /\{ label: 'Record it again', value: againLine\(run\.numbers\) \?\? NOT_HELD \}/.test(bench),
      /setStatus\(\(line\) => transportLine\(line, was, now, hidden\)\)/.test(bench), /setStatus\(SOUND_STOPPED\)/.test(bench)],
    [true, true, true, false])
  check('...and no other audio context in the bench but the decoder\'s, an OfflineAudioContext, in decode.ts alone',
    [files.filter((file) => file.startsWith('lab/') && /\bnew\s+(?:Context|AudioContext|webkitAudioContext|Room|Decoder)\b/.test(code(read(file)))).sort(), files.filter((file) => /OfflineAudioContext/.test(code(read(file))))],
    [['lab/decode.ts', 'lab/listen.ts'], ['lab/decode.ts']])
  //? its player is its own: one <audio> of the bench's, never usePlayer; the turntable reaches it through
  //? the narrow TurntablePlayer, and the deck its windows through the bench's source
  check('its player is its own <audio>, made once; no part of the bench reaches the app\'s player',
    [(code(read('lab/benchPlayer.ts')).match(/document\.createElement\('audio'\)/g) ?? []).length,
      files.filter((file) => file.startsWith('lab/') && /usePlayer|app\/context|app\/App/.test(code(read(file))))],
    [1, []])
  //? (2.0.0-player.37) - and a song from the library on a turntable of its own with NO window source, so its
  //? deck asks deadwax's scrub route as the app's does: keyed apart, so the deck is made afresh between them
  check('the turntable drawn with the bench\'s windows and its deck - and for a song from the library, keyed apart, with none',
    [/<Turntable key="made" player=\{player\} open=\{true\} discArt=\{null\} onPreview=\{setPreviewing\} windDown=\{windDown\} deck=\{deckRef\} windowSource=\{windowSource\} \/>/.test(bench),
      /\{fromLibrary\s*\?\s*<Turntable key="library" player=\{player\} open=\{true\} discArt=\{null\} onPreview=\{setPreviewing\} windDown=\{windDown\} deck=\{deckRef\} \/>\s*:\s*<Turntable key="made"/.test(bench),
      /const fromLibrary = !!made\?\.song\.library\n/.test(bench), (bench.match(/<Turntable\s/g) ?? []).length],
    [true, true, true, 2])
  //? a song from the library (2.0.0-player.37): played at the address the app asks for it at - the app's
  //? helpers, the device's Maximum quality and what the bench's one element can play; held still while
  //? anything records, as the bench's own signals are; the last one picked asked of Navidrome again through
  //? latestOnly; and the comparison's windows asked at the cap the deck asks at
  const pickLibrary = handler('pickLibrary')
  check('...a song from the library: the app\'s address for it, held still while anything records, remembered through latestOnly, its comparison read at the deck\'s cap',
    [/url: libraryAddress\(track, browser, maxRate\), library: \{ track, maxRate \}/.test(bench), /const maxRate = readPlayerMaxRate\(\)/.test(bench),
      /canPlayType: playerRef\.current\.canPlayType/.test(bench),
      /^\s*if \(locked\) return\s*writePick\(song\)/.test(pickLibrary), /<LibraryPicker disabled=\{locked\}/.test(bench),
      /onClick=\{\(\) => pickLibrary\(offer\.song\)\} aria-disabled=\{locked\}/.test(bench),
      /const ticket = remembering\.begin\(\)\s*checkPick\(\(id\) => songDetails\(id, ticket\.signal\)\)\.then\(\(checked\) => \{\s*if \(ticket\.current\(\)\) setOffer\(checked\)/.test(bench),
      /const cap = deckCap\(library\.track, library\.maxRate\)\s*const ask = \(at: number\) => scrubWindow\(library\.track\.id, at, WINDOW_S, undefined, cap\)/.test(bench),
      (bench.match(/scrubWindow\(/g) ?? []).length],
    [true, true, true, true, true, true, true, true, 1])
  //? ...and what a library song changes: the turntable made afresh says so (a tap starts its sound again);
  //? the check, which runs on the bench's own sines, takes the bench back to them and waits for a tap to
  //? start the sound; the comparison says music has no "what isn't the signal"; the voice's windows asked
  //? again must be the very ones it had
  const runCheck = /const runCheck = async \(\) => \{([\s\S]*?)\n {2}\}\n/.exec(bench)?.[1] ?? ''
  check('...the turntable made afresh said so; the check from a library song back on the sines, waiting for a tap; music said to have no "what isn\'t the signal"; the voice\'s windows the very ones',
    [/if \(kindWas\.current === fromLibrary\) return\s*kindWas\.current = fromLibrary\s*setStatus\(SOUND_AGAIN\)/.test(bench),
      /if \(madeRef\.current\?\.song\.library\) \{[\s\S]*?setSignalId\(CHECK_SIGNALS\[0\]!\)[\s\S]*?if \(deckReport\(\)\?\.context !== 'running'\) \{\s*setCheck\(state\(SWITCHED_CHECK, \{ waiting: true \}\)\)\s*await new Promise<void>\(\(go, stop\) => \{ carryOn\.current = \{ go, stop \} \}\)/.test(runCheck)
        && runCheck.indexOf('madeRef.current?.song.library') < runCheck.indexOf("until(() => !!deckReport()?.voice"),
      /music: !what\.made\.signal \|\| what\.made\.signal\.id === 'file'/.test(bench), /numberRows\(compared\.result\.numbers, compared\.music\)/.test(bench),
      /if \(!signal && channels\[0\]\?\.length !== shape\.length\) continue/.test(bench), /return Math\.abs\(got\.first \/ got\.rate - start\) < 1e-9 \? got\.bytes : null/.test(bench)],
    [true, true, true, true, true, true])
  const picker = code(read('lab/LibraryPicker.tsx'))
  check('...its search Navidrome\'s, through librarySearch (paced, latestOnly); Navidrome\'s status through latestOnly; its rows aria-disabled while the song is held',
    [/librarySearch\(\{ search: \(query, signal\) => searchLibrary\(query, signal\), onAnswer: setAnswer \}\)/.test(picker),
      /const ticket = statuses\.begin\(\)\s*navidromeStatus\(ticket\.signal\)/.test(picker), /if \(ticket\.current\(\)\) setNavidrome/.test(picker),
      /aria-disabled=\{disabled\} onClick=\{\(\) => !disabled && onPick\(song\)\}/.test(picker),
      /useEffect\(\(\) => \(\) => search\.stop\(\), \[\]\)/.test(picker)],
    [true, true, true, true, true])
  const table = code(read('player/Turntable.tsx'))
  check('Turntable takes the windows only where they are given - the app\'s deck asks deadwax as ever',
    [/if \(windows\.current\) host\.window = /.test(table), (code(read('app/App.tsx') + read('player/NowPlaying.tsx')).match(/windowSource/g) ?? []).length],
    [true, 0])
}

console.log('\nwhat Info reads is taken in the tap, and asks the engine\'s element only')
{
  //? About needs the album answer the queue was played from; the album page keeps it as it plays,
  //? in the same turn as playTracks - nothing awaited between, or the tap's gesture is lost
  const page = code(read('player/AlbumPage.tsx'))
  const play = /const play = \([^)]*\) => \{([\s\S]*?)\n  \}/.exec(page)?.[1] ?? ''
  check('AlbumPage remembers the album, then plays, in the tap',
    [/rememberPlayed\(album\)\s*player\.playTracks\(/.test(play), /\bawait\b|\.then\(/.test(play)], [true, false])
  //? "Sent as" asks the engine's own element what it can play: never a new one (iOS unlocks audio
  //? per element), and nothing set or started on it
  const api = code(read('player/api.ts'))
  const sent = /export function sentFormat\([\s\S]*?\n\}/.exec(api)?.[0] ?? ''
  check('sentFormat asks the element that is there, and makes or touches nothing',
    [/document\.querySelector\('audio'\)/.test(sent), /createElement|new Audio|\.src\b|srcObject|\.load\(|\.play\(|\.pause\(/.test(sent), /canPlayType\(/.test(sent)],
    [true, false, true])
}

console.log('\nSearch: a song plays from the tap, with its album in hand; the newest answer only')
{
  const search = code(read('app/Search.tsx'))
  const rows = code(read('app/SearchRows.tsx'))
  const play = /const playSong = \([^)]*\) => \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('a song\'s tap plays its album from that song only when the album\'s songs are in hand',
    [/const album = song\.albumId \? ready\.get\(song\.albumId\) : undefined/.test(play), /if \(album && at >= 0\) \{\s*rememberPlayed\(album\)\s*actions\.playTracks\(album\.song!\.map\(\(each\) => toQueueTrack\(each, album\)\), at\)/.test(play)],
    [true, true])
  check('...nothing fetched or awaited in the tap - otherwise the album opens instead',
    [/\bawait\b|\.then\(|fetch|prefetchAlbum|searchLibrary/.test(play), /onOpenAlbum\(/.test(play)], [false, true])
  //? (2.0.0-player.55) the albums of the library songs in Top results' decided picks first, worked out from the very answer
  check('...and the albums are asked for as the answer lands, KEPT (a scroll can\'t call them off), Top results\' songs first, kept only for the newest search',
    /if \(!request\.current\(\)\) return\s*putLibrary\(\{ text: term, state: 'answered', results \}\)[\s\S]*?const top = preferredSongs\(decidedPrefix\(term, results\)\)\s*for \(const id of albumsToPrefetch\(results\.songs, top\)\) \{\s*prefetchAlbum\(id, true\)\.then\(\s*\(album\) => \{\s*if \(request\.current\(\)\) setReady/.test(search), true)
  //? (2.0.0-player.55) the rows are app/SearchRows.tsx's: a library song's tap calls Search's playSong, synchronously
  check('the song row\'s click is that tap - SearchRows calls onPlay in the click, Search hands it playSong - and its play mark only when it will play',
    [/case 'song':\s*return \(\) => context\.onPlay\(row\.song\)/.test(rows), /onClick=\{tap\(row, context, (true|false)\)\}/.test(rows), /onPlay: playSong,/.test(search),
      /\{will \? <PlayIcon class="app-result-play" \/> : null\}/.test(rows)], [true, true, true, true])
  check('album rows navigate, asking for the songs as the finger lands, as a tile does',
    [/onPointerDown: \(\) => void prefetchAlbum\(row\.album\.id\), onPointerCancel: \(\) => dropPrefetch\(row\.album\.id\)/.test(rows), /case 'album':\s*return \(\) => context\.onOpenAlbum\(row\.album\)/.test(rows)],
    [true, true])
  const askLibrary = /function askLibrary\(term: string\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askAlbums = /async function askAlbums\([^)]*\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askMusicBrainz = /function askMusicBrainz\(term: string, inView: View = viewNow\.current, reread = false\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('each kind through its own latestOnly(), drawing only the newest answer',
    [/const libraryRequests = useMemo\(latestOnly, \[\]\)/.test(search), /const musicRequests = useMemo\(latestOnly, \[\]\)/.test(search),
      /const request = libraryRequests\.begin\(\)[\s\S]*if \(!request\.current\(\)\) return\s*putLibrary\(/.test(askLibrary),
      /const request = musicRequests\.begin\(\)[\s\S]*if \(!request\.current\(\)\) return\s*putAlbums\(\{ state: 'done'/.test(askAlbums),
      /catch \(reason\) \{\s*if \(!request\.current\(\) \|\| isAbort\(reason\)\) return/.test(askAlbums)],
    [true, true, true, true, true])
  check('...with the fetch called off when superseded', [/searchLibrary\(term, request\.signal\)/.test(askLibrary), /fullySearch\(first, MUSICBRAINZ_LIMIT, false, request\.signal, 0, true\)/.test(askAlbums)], [true, true])
  const page = code(read('app/ReleaseGroupPage.tsx'))
  const load = /function load\(\) \{([\s\S]*?)\n  \}/.exec(page)?.[1] ?? ''
  check('the album you don\'t have: its pressings through latestOnly(), a problem never drawn as the pressings',
    [/const requests = useMemo\(latestOnly, \[\]\)/.test(page), /getReleaseGroup\(mbid, request\.signal\)/.test(load),
      /if \(!request\.current\(\)\) return\s*if \(found\.problem\) \{\s*setTrouble\([^)]*\)\s*return\s*\}/.test(load), /keep\(mbid, found\)\s*setAnswer\(found\)/.test(load),
      (load.match(/keep\(/g) ?? []).length],
    [true, true, true, true, 1])
  const app = code(read('app/App.tsx'))
  check('...drawn outside the Navidrome gate, the album you have inside it',
    /page\.kind === 'group' \? \(\s*<ReleaseGroupPage\b[\s\S]*?\) : \(\s*<NeedsNavidrome\b[\s\S]*?<AlbumPage\b/.test(app), true)
  check('...and a pressing chosen is the page\'s address replaced, through the router',
    /const pickPressing = useCallback\(\(groupId: string, release: string \| null\) => \{\s*router\.update\(/.test(app), true)
  //? the first /library/owned after a restart walks the whole library: never asked as the app starts
  const owned = code(read('app/useOwned.ts'))
  check('what the library holds is asked when Search first shows, never as the app starts',
    [/const owned = useOwned\(shown\)/.test(search), /<Search shown=\{searchSeen\}/.test(app), /if \(nav\.tab === 'search'\) setSearchSeen\(true\)/.test(app),
      /useEffect\(\(\) => \{\s*if \(ask && !held && !asking\) void refreshOwned\(\)\s*\}, \[ask\]\)/.test(owned),
      /onAlbumsFiled\(\(\) => \{\s*if \(wanted\) void refreshOwned\(\)/.test(owned)],
    [true, true, true, true, true])
  //? (2.0.0-player.52, second review) the album page asks EVERY time it shows, as its store line is asked; (2.0.0-player.55) every
  //? kind's answer waits a moment for the library's - an answer kept from before draws at once - and the sections draw at
  //? moment 2 (lib/searchList.ts sectionsReady: every kind asked, or RESULTS_WAIT_MS), replacing song53's "never waits for the songs"
  const askArtists = /async function askArtists\([^)]*\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askSongs = /function askSongs\(term: string, plan: SearchPlan, ownedAnswered: Promise<unknown>\): void \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const race = /if \(request\.current\(\) && !found\.kept\) await Promise\.race\(\[ownedAnswered, wait\(OWNED_WAIT_MS\)\]\)/
  check('...whenever the album page shows, and beside each MusicBrainz search, whose every kind waits a moment for its answer; the sections at moment 2',
    [/const owned = useOwned\(false\)\s*useEffect\(\(\) => \{\s*if \(shown\) void refreshOwned\(\)\s*\}, \[shown\]\)/.test(page), /const ownedAnswered = refreshOwned\(\)/.test(askMusicBrainz),
      race.test(askAlbums) && race.test(askArtists) && race.test(askSongs),
      /if \(!sectionsReady\(\{ librarySettled: settled, musicBrainz, asked: run\.asked \|\| !out\.length, out, capPassed: run\.capPassed \}\)\) return \{ drawn: was, said: null \}/.test(search)],
    [true, true, true, true])
  check('...and what MusicBrainz found is left out once, as it lands - never filtered again as the library\'s answer changes - and drawn from that',
    [/shown: notInLibrary\(groups, ownedNow\(\)\?\.index \?\? null\)/.test(askAlbums), /albums: albums \? \{ groups: albums\.groups, shown: albums\.shown \} : null/.test(search),
      /albums\.musicbrainz = input\.albums\.shown\.map\(/.test(code(read('lib/searchList.ts')))],
    [true, true, true])
  const picker = code(read('app/PressingPicker.tsx'))
  check('the pressing list is brought into view as it opens, and focus going nowhere doesn\'t close it',
    [/target\?\.focus\(\{ preventScroll: true \}\)\s*reveal\(target\)/.test(picker), /box\.scrollIntoView\(\{ block: 'nearest' \}\)/.test(picker),
      /if \(to && !root\.current\?\.contains\(to\)\) close\(false\)/.test(picker)],
    [true, true, true])
  check('the page\'s ONE solid purple button is Get (2.0.0-player.15); its picker and Search have none - a row\'s Get chip is tinted',
    [(code(read('app/ReleaseGroupPage.tsx')).match(/class="app-rg-get"/g) ?? []).length,
      ['app/ReleaseGroupPage.tsx', 'app/PressingPicker.tsx', 'app/Search.tsx', 'app/SearchRows.tsx'].filter((file) => /is-primary|app-primary/.test(code(read(file)))),
      /class=\{`app-result-get\b/.test(rows)],
    [1, [], true])
}

console.log('\nsearch extras (2.0.0-player.50): More from MusicBrainz, the pressing facts, the maybe, the links out')
{
  const search = code(read('app/Search.tsx'))
  const more = /async function askMore\(\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('More from MusicBrainz goes through the albums\' own latestOnly(), the fetch called off when superseded, drawing only while newest',
    [/const request = musicRequests\.begin\(\)/.test(more), /fullySearch\(was\.query, MUSICBRAINZ_LIMIT, false, request\.signal, was\.nextOffset, true\)/.test(more),
      /const found = await fullySearch\([^)]*\)\s*if \(!request\.current\(\)\) return/.test(more), /catch \(reason\) \{\s*if \(!request\.current\(\) \|\| isAbort\(reason\)\) return/.test(more)],
    [true, true, true, true])
  check('...appended by the first page\'s rule (held albums left out by the library\'s answer), and only to the search it was asked for',
    [/appendPage\(now\.groups, now\.shown, page, ownedNow\(\)\?\.index \?\? null\)/.test(more), /now\.state === 'done' && now\.key === was\.key/.test(more)],
    [true, true])
  //? (2.0.0-player.55) More is a kind view's - under that kind's MusicBrainz rows
  check('...and its button under the rows (a kind view\'s), a secondary button (no solid purple on Search), drawn only while morePages says there is more',
    [/\{mbRows\.length > 0 \? \([\s\S]*?<\/ul>[\s\S]*?\{pages === 'more' \? \(\s*<button/.test(search), /class=\{`app-button app-search-more\b/.test(search),
      /const pages = mine\?\.state === 'done' \? morePages\(/.test(search)],
    [true, true, true])
  //? (review) a song's key holds a newline, which no CSS string may: a row is found by comparing its key, never by a
  //? selector built from it (querySelector threw, and the commit's other effects went with it)
  check('a row focus is handed to is found by comparing keys - never a key put into a selector', [/function rowNamed\(box: Element \| null \| undefined, key: string\): HTMLElement \| null \{\s*if \(!box\) return null\s*for \(const each of Array\.from\(box\.querySelectorAll<HTMLElement>\('\[data-row\]'\)\)\) if \(each\.getAttribute\('data-row'\) === key\) return each/.test(search),
    /\[data-row="\$\{/.test(search)], [true, false])
  check('...its last page landing with focus on it hands focus on (review): only when the button had it, never over focus gone elsewhere',
    [/const focused = focusedOn\('\.app-search-more-musicbrainz'\)/.test(more), /if \(focused && morePages\(next\.nextOffset, next\.count, next\.last, MUSICBRAINZ_LIMIT\) !== 'more'\) \{/.test(more),
      /useLayoutEffect\(\(\) => \{\s*const hand = handFocus\.current\s*if \(!hand \|\| typeof document === 'undefined'\) return\s*const now = document\.activeElement\s*if \(hand\.control && now === hand\.control && hand\.control\.isConnected\) return\s*if \(now && now !== document\.body\) \{\s*handFocus\.current = null\s*return\s*\}/.test(search)],
    [true, true, true])
  const page = code(read('app/ReleaseGroupPage.tsx'))
  check('the chosen pressing\'s facts drawn with the picker - under it on a phone, under Get and it on a desktop - and the store line still last',
    [/\{!desktop && picker\}\s*\{!desktop && facts\}\s*\{download && \(/.test(page), /\{desktop && picker\}\s*\{desktop && facts\}\s*<div class="app-rg-store"/.test(page)],
    [true, true])
  check('"maybe in your library" from lib/owned.ts\'s name match, said only when nothing is held by an id',
    [/title: credited\?\.title \|\| releases\[0\]\?\.title \|\| title,\s*artists: \[creditName\(credited\?\.\['artist-credit'\]\), currentName\(credited\?\.\['artist-credit'\]\)\]/.test(page),
      /const maybe = holdingOf\(ownership\) === 'maybe' \? describeGroupOwnership\(ownership!\) : null/.test(page)],
    [true, true])
  check('the album and the chosen pressing on musicbrainz.org, each opening beside the app',
    [...page.matchAll(/<a class="app-rg-link" href=\{([^}]*)\}[^>]*>/g)].map((match) => [match[1], opensBeside(match[0])]),
    [['releaseGroupUrl(mbid)', true], ['releaseUrl(chosen.id)', true]])
  const picker = code(read('app/PressingPicker.tsx'))
  check('the pressing list\'s filter: outside the listbox, only past PRESSING_FILTER_MIN, emptied as the list closes - by the Pressing button too (review) - the field\'s own keys left to it',
    [/\{filterable && \([\s\S]*?<input[\s\S]*?\)\}\s*<div id=\{listId\} ref=\{list\} role="listbox"/.test(picker), /const filterable = all\.length > PRESSING_FILTER_MIN/.test(picker),
      /const close = \(focus = true\) => \{\s*setOpen\(false\)\s*setTyped\(''\)/.test(picker) && /onClick=\{\(\) => \(open \? close\(false\) : setOpen\(true\)\)\}/.test(picker),
      /if \(field\.current && document\.activeElement === field\.current\) \{\s*if \(event\.key !== 'ArrowDown' \|\| !options\.length\) return/.test(picker)],
    [true, true, true, true])
  check('...a pressing revealed by the list itself kept clear of the filter, by the list\'s own scroll-padding the arrows\' focus scrolling honours (review)',
    /const clear = typeof getComputedStyle === 'function' \? parseFloat\(getComputedStyle\(box\)\.scrollPaddingTop\) \|\| 0 : 0[\s\S]*?if \(top - clear < box\.scrollTop\) box\.scrollTop = top - clear/.test(picker), true)
}

console.log('\nsong search (2.0.0-player.53): Songs on MusicBrainz, and the album opened from a song')
{
  const search = code(read('app/Search.tsx'))
  const rowsFile = code(read('app/SearchRows.tsx'))
  const askSongs = /function askSongs\(term: string, plan: SearchPlan, ownedAnswered: Promise<unknown>\): void \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askMoreSongs = /async function askMoreSongs\(\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askMusicBrainz = /function askMusicBrainz\(term: string, inView: View = viewNow\.current, reread = false\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('the songs through a latestOnly of their own, the fetch called off when superseded, drawn only while newest, never rejecting',
    [/const songRequests = useMemo\(latestOnly, \[\]\)/.test(search), /const request = songRequests\.begin\(\)/.test(askSongs),
      /searchSongs\(query, SONG_SEARCH_LIMIT, request\.signal\)/.test(askSongs), /if \(!request\.current\(\)\) return\s*setOpenSongs\(new Set\(\)\)/.test(askSongs),
      /catch \(reason\) \{\s*if \(!request\.current\(\) \|\| isAbort\(reason\)\) return/.test(askSongs)],
    [true, true, true, true, true])
  //? (2.0.0-player.55) albums, then artists, then songs - one reading, each kind asked once for a text and how it read
  check('...asked with the albums and the artists from the same reading - albums first, then artists, then songs - the library waited for, asked once for a text',
    [/const SEND_ORDER: readonly Kind\[\] = \['albums', 'artists', 'songs'\]/.test(search), /for \(const kind of SEND_ORDER\) \{/.test(askMusicBrainz),
      /if \(request\.current\(\) && !found\.kept\) await Promise\.race\(\[ownedAnswered, wait\(OWNED_WAIT_MS\)\]\)/.test(askSongs), /if \(askedFor\(songsNow\.current, key\)\) return\n/.test(askSongs),
      /const query = songSearchQuery\(term, plan\)/.test(askSongs)],
    [true, true, true, true, true])
  //? (review) the fallback: the words typed as one title, for a title beside an artist alone
  check('...a title beside an artist finding no song asked again as the words typed, as ONE title - free text never asked twice',
    [/const again = plan\.kind === 'album-by-artist' \? songTitleQuery\(term\) : null\s*if \(!found\.answer\.recordings\?\.length && again && request\.current\(\)\) \{\s*asking = again\s*found = await keptOr\(searchSongsPath\(again, SONG_SEARCH_LIMIT\), \(\) => searchSongs\(again, SONG_SEARCH_LIMIT, request\.signal\)\)/.test(askSongs),
      /export function songTitleQuery\(text: string\): string \| null \{\s*const words = text\.trim\(\)\.split\(\/\\s\+\/\)\.filter\(Boolean\)\.join\(' '\)\s*return words \? `recording:\$\{quoteTerm\(words\)\}` : null/.test(code(read('lib/searchQuery.ts')))],
    [true, true])
  //? (2.0.0-player.55) song53's fold for songs landing after the albums went: every kind late at moment 2 has a slot, and lands in it
  check('...a kind landing late lands in its slot - drawn in when its section is the last, folded when something is below - song53\'s songs-only fold gone',
    [/const where = drawInOrFold\(kind, order\)/.test(search), /const landing = lateRows\(rows\[kind\], \[Math\.max\(0, cap\[0\] - libraryDrawn\), cap\[1\]\]\)/.test(search),
      /albumsShown|showSongs|app-song-slot|app-song-show/.test(search)],
    [true, true, false])
  check('...More songs through the same latestOnly, by offset, merged in, drawing only for the search it was asked for',
    [/const request = songRequests\.begin\(\)/.test(askMoreSongs), /searchSongs\(was\.query, SONG_SEARCH_LIMIT, request\.signal, was\.nextOffset\)/.test(askMoreSongs),
      /const found = await searchSongs\([^)]*\)\s*if \(!request\.current\(\)\) return/.test(askMoreSongs), /appendSongs\(now\.recordings, page, now\.songs\)/.test(askMoreSongs),
      /now\.state === 'done' && now\.key === was\.key/.test(askMoreSongs)],
    [true, true, true, true, true])
  check('...every kind called off and emptied as the box empties or is cut back, and as the tab goes',
    [/setReady\(new Map\(\)\)\s*dropMusicBrainz\(\)/.test(search), /if \(musicBrainz === 'drop'\) dropMusicBrainz\(\)/.test(search),
      /function dropMusicBrainz\(\) \{\s*musicRequests\.supersede\(\)\s*artistRequests\.supersede\(\)\s*songRequests\.supersede\(\)\s*asked\.current = null\s*askedPlan\.current = null/.test(search),
      /musicRequests\.supersede\(\)\s*artistRequests\.supersede\(\)\s*songRequests\.supersede\(\)\s*getRequests\.supersede\(\)/.test(search)],
    [true, true, true, true])
  //? (2.0.0-player.55) Apple's order: Top results, then Artists, Albums, Songs - songs last now (step 7 drew them above the albums)
  check('...drawn in Apple\'s order - Top results, then Artists, Albums, Songs, each section labelled by its own heading',
    [/export const KINDS: readonly Kind\[\] = \['artists', 'albums', 'songs'\]/.test(code(read('lib/searchList.ts'))), /for \(const kind of KINDS\) \{\s*const drawnRows = sectionRows\(/.test(search),
      /aria-labelledby="app-search-top"[\s\S]*?sections\.map\(\(section\) => \{/.test(search), /aria-labelledby=\{sectionId\(section\.kind\)\}/.test(search)],
    [true, true, true, true])
  const openSongAlbum = /function openSongAlbum\(song: FoundSong, album: SongAlbum\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('a song\'s album you have opens the album you have, through the held rows\' latestOnly (called off as the box changes); else its page, with the song\'s recordings',
    [/const releases = songAlbumHeldReleases\(index, album, song, evidence\)/.test(openSongAlbum),
      /const yours = \(releases: readonly string\[\], request = heldRequests\.begin\(\)\) => \{\s*setOpening\(key\)/.test(openSongAlbum),
      /navidromeAlbumFor\(releases, request\.signal\)/.test(openSongAlbum), /const open = \(\) => onOpenSongAlbum\(\{ id: album\.id, title: album\.title \}, album\.recordings\)/.test(openSongAlbum),
      //? (review) the bridge answering nothing, or failing: its page all the same
      /if \(found\) onOpenAlbum\([^\n]*\)\s*else open\(\)/.test(openSongAlbum), /if \(!request\.current\(\) \|\| isAbort\(reason\)\) return\s*setOpening\(null\)\s*open\(\)/.test(openSongAlbum)],
    [true, true, true, true, true, true])
  //? (second review) what you hold of a song's album told by more than the releases the song was found on: the library half's
  //? songs and the session's kept pressings, in every line; a pressing the library half vouches for opens its album at once;
  //? one nothing vouches for has the album's pressings asked first, through the same latestOnly, and kept
  check('...what you hold told by the library half\'s songs and the kept pressings too, in every line; one it vouches for opened at once; one nothing vouches for: the pressings asked first, through the same latestOnly, kept, then the bridge or its page',
    [/const evidence: SongEvidence = \{ heard: results\?\.songs \?\? null, pressings: \(id\) => kept\(id\)\?\.releases \?\? null \}/.test(search),
      /songAlbumLine\(album, song, context\.index, context\.personal, context\.evidence\)/.test(rowsFile), /evidence = \{\}[\s\S]*?const \{ album, held \} = namedAlbum\(row\.song, marks\.index, evidence\)/.test(code(read('lib/searchList.ts'))),
      /namedAlbum\(song, context\.index, context\.evidence\)/.test(rowsFile),
      /const holding = songAlbumHolding\(index, album, song, evidence\)\s*if \(holding\.albums\.length\) \{\s*heldRequests\.supersede\(\)\s*setOpening\(null\)\s*onOpenAlbum\(\{ id: holding\.albums\[0\]!/.test(openSongAlbum),
      /if \(!holding\.other\.length \|\| kept\(album\.id\)\) \{\s*open\(\)\s*return\s*\}/.test(openSongAlbum),
      /const request = heldRequests\.begin\(\)\s*setOpening\(key\)\s*getReleaseGroup\(album\.id, request\.signal\)\.then\(/.test(openSongAlbum),
      /\(found\) => \{\s*if \(!request\.current\(\)\) return\s*if \(!found\.problem\) keep\(album\.id, found\)/.test(openSongAlbum),
      /const held = songAlbumHeldReleases\(ownedNow\(\)\?\.index \?\? index, album, song, \{ \.\.\.evidence, pressings: \(\) => found\.releases \}\)\s*if \(held\.length\) \{\s*yours\(held, request\)\s*return\s*\}\s*setOpening\(null\)\s*open\(\)/.test(openSongAlbum)],
    [true, true, true, true, true, true, true, true, true])
  const app = code(read('app/App.tsx'))
  check('App: the song\'s album opened with its recordings in the address, no preview (a Get builds from MusicBrainz\'s own group), and handed to the page',
    [/const openSongAlbum = useCallback\(\(album: \{ id: string; title: string \}, song: readonly string\[\]\) => \{\s*const ids = songIds\(song\)/.test(app),
      /\.\.\.\(ids\.length \? \{ song: ids\.join\(','\) \} : \{\}\)/.test(app), /<Search\b[^>]*onOpenSongAlbum=\{openSongAlbum\}/.test(app),
      /<ReleaseGroupPage\b[\s\S]*?song=\{page\.song \?\? null\}/.test(app),
      //? (review) the album's name standing in as the title, and a fresh scroll - unless it is the page on screen
      /const page: Page = \{ kind: 'group', id: album\.id, \.\.\.\(album\.title \? \{ label: album\.title \} : \{\}\), \.\.\.\(ids\.length/.test(app),
      /const address = scrollKey\(\{ tab: router\.nav\.tab, page \}\)\s*if \(address !== scrollKey\(currentRoute\(router\.nav\)\)\) scrolls\.current\.delete\(address\)\s*router\.open\(page\)/.test((/const openSongAlbum = useCallback\([\s\S]*?\n  \}, \[\]\)/.exec(app) ?? [''])[0]),
      /const openSongAlbum = useCallback\([\s\S]*?groupPreviews\.current\.set/.test((/const openSongAlbum = useCallback\([\s\S]*?\n  \}, \[\]\)/.exec(app) ?? [''])[0])],
    [true, true, true, true, true, true, false])
  const page = code(read('app/ReleaseGroupPage.tsx'))
  check('the page: the pressing asked for the address\'s, else one with the song; marked rows on both frames; a pick written whatever it is',
    [/const asked = useMemo\(\(\) => release \?\? \(songKey \? songPressing\(releases, songKey\.split\(','\)\) : null\), \[answer, release, songKey\]\)/.test(page),
      /const rows = trackRows\(chosen, diff, isSong\)/.test(page), (page.match(/\$\{row\.song \? ' is-song' : ''\}/g) ?? []).length,
      (page.match(/\{row\.song && <span class="app-visually-hidden">\{SONG_WORDS\}<\/span>\}/g) ?? []).length,
      /onPick=\{\(picked\) => onPick\(id, songKey \|\| picked !== view\.defaultId \? picked : null\)\}/.test(page)],
    [true, true, 2, 2, true])
  check('...brought into view once, only while it shows, only from the page\'s top, a row already in view left still',
    /if \(songShown\.current \|\| !shown \|\| !rows\.some\(\(row\) => row\.song\)\) return\s*const row = page\.current\?\.querySelector<HTMLElement>\('\.is-song'\)\s*if \(!row\) return\s*songShown\.current = true\s*if \(typeof window === 'undefined' \|\| window\.scrollY > 0\) return\s*row\.scrollIntoView\(\{ block: 'nearest' \}\)/.test(page), true)
  check('lib/songs.ts is pure: no fetch, no playback, no DOM', /fetch\(|playTracks|document\.|window\./.test(code(read('lib/songs.ts'))), false)
}

console.log('\nsearch like Apple Music (2.0.0-player.55): one list, its rows stateless, its rules pure')
{
  const search = code(read('app/Search.tsx'))
  const rows = code(read('app/SearchRows.tsx'))
  const list = code(read('lib/searchList.ts'))
  const app = code(read('app/App.tsx'))
  //? James's held-groups decision extended (for him to confirm): an album you hold that search3 didn't list is brought in, at
  //? the end of its holder's block - marked, no Get, opening the album you have
  check('a held album search3 didn\'t list: brought in to the yours (or the store\'s) block, never MusicBrainz\'s - with no Get',
    [/albums\.brought = heldUnlisted\(input\.albums\.groups, index, libraryAlbums\)/.test(list),
      /const ofHolder = \(who: 'yours' \| 'store'\) => \[\.\.\.kind\.library, \.\.\.kind\.brought\]\.filter\(\(each\) => each\.holder === who\)/.test(list),
      /if \(row\.type === 'group'\) \{\s*if \(groupHeld\(context\.index, row\.group\.id\)\) return null/.test(rows),
      /const openAnyGroup = \(group: ReleaseGroup\) => \(groupHeld\(owned\?\.index \?\? null, group\.id\) \? openGroup\(group\) : onOpenGroup\(group\)\)/.test(search)],
    [true, true, true, true])
  const askArtists = /async function askArtists\([^)]*\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askMoreArtists = /async function askMoreArtists\(\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('MusicBrainz\'s artists through a latestOnly of their own, the fetch called off when superseded, drawn only while newest',
    [/const artistRequests = useMemo\(latestOnly, \[\]\)/.test(search), /const request = artistRequests\.begin\(\)/.test(askArtists),
      /searchArtists\(name, ARTIST_SEARCH_LIMIT, request\.signal\)/.test(askArtists), /if \(!request\.current\(\)\) return\s*putArtists\(artistsDone\(/.test(askArtists),
      /catch \(reason\) \{\s*if \(!request\.current\(\) \|\| isAbort\(reason\)\) return/.test(askArtists),
      /const request = artistRequests\.begin\(\)/.test(askMoreArtists) && /if \(!request\.current\(\)\) return/.test(askMoreArtists)],
    [true, true, true, true, true, true])
  check('the chips outside the form (a desktop doesn\'t draw the form - its box is the sidebar\'s): the Library\'s view chips, verbatim',
    [/<\/form>\s*(\{\s*\}\s*)?\{query && \(\s*<div ref=\{chips\} class="app-library-views app-search-kinds" role="group" aria-label="Show">/.test(search),
      /class=\{`app-chip app-library-view\$\{view === each \? ' is-on' : ''\}`\}\s*aria-pressed=\{view === each\}/.test(search)],
    [true, true])
  check('the Navidrome gate above the results, once, MusicBrainz\'s list outside it (it works with Navidrome down)',
    /\{status && !status\.ok && <NeedsNavidrome status=\{status\} onRetry=\{onRetry\}>\{null\}<\/NeedsNavidrome>\}\s*(\{\s*\}\s*)?\{view === 'all' \? allView\(\) : kindView\(view\)\}/.test(search), true)
  check('App: a MusicBrainz artist opens by `mb:` - its openCreditedArtist, outside the gate', /<Search\b[^>]*onOpenMusicBrainzArtist=\{openCreditedArtist\}/.test(app), true)
  check('app/SearchRows.tsx reaches no playback action: no player context, no playTracks - a song\'s tap is Search\'s onPlay',
    [/from '\.\/context'|usePlayerActions|usePlayer\b|playTracks|actions\./.test(rows)], [false])
  check('lib/searchList.ts is pure: no fetch, no playback, no DOM', /fetch\(|playTracks|document\.|window\.|localStorage/.test(list), false)
  //? Top results frozen at the draw: picked in advance() alone, drawn from `drawn.top` - never recomputed at render
  const allView = /function allView\(\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const kindView = /function kindView\(kind: Kind\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('Top results drawn from drawn.top - never picked at render (topResults and decidedTop only where the list advances)',
    [/\{drawn\.top\.map\(\(row\) => topRow\(row, context, tiles\)\)\}/.test(allView), /topResults\(|decidedTop\(/.test(allView + kindView),
      (search.match(/\btopResults\(/g) ?? []).length, (search.match(/\bdecidedTop\(/g) ?? []).length],
    [true, false, 2, 2])
  check('the sections drawn from drawn.sections - their rows decided at the draw, never re-sorted', /sections\.map\(\(section\) => \{[\s\S]*?section\.rows\.map\(\(row, at\) => sectionRow\(row, context, at\)\)/.test(allView), true)
  check('...and the frame read when the list is drawn, kept with it: tiles by drawn.frame, never the frame now', [/const tiles = drawn\.frame === 'desktop'/.test(allView), /TOP_RESULTS\[was\.frame\]/.test(search)], [true, true])
}

console.log('\nGet: the Sources sheet, a download from the tap, and Requests')
{
  const app = code(read('app/App.tsx'))
  const sheet = code(read('app/Sources.tsx'))
  const card = code(read('app/SourceCard.tsx'))
  const hook = code(read('hooks/useCandidateSearch.ts'))
  const page = code(read('app/ReleaseGroupPage.tsx'))
  const search = code(read('app/Search.tsx'))
  check('the page and Search open the sheet through App, the opener taken in the tap',
    [/<ReleaseGroupPage\b[\s\S]*?onGet=\{openSources\}/.test(app), /<Search\b[^>]*onGet=\{openSources\}/.test(app),
      /const openSources = useCallback\(\(request: Omit<GetRequest, 'key'>, opener: HTMLElement \| null\) => \{\s*if \(nowPlayingOpen\.current\) return\s*sourcesOpener\.current = opener/.test(app),
      /onGet\(\{[\s\S]*?\}, takeOpener\(event\)\)/.test(page), /const opener = takeOpener\(event\)\s*const request = getRequests\.begin\(\)/.test(search)],
    [true, true, true, true, true])
  check('a download asked for: the sheet goes, focus with nowhere to land, and Requests shows at its root',
    /const gotten = useCallback\(\(\) => \{\s*sourcesOpener\.current = null\s*setSourcesOpen\(false\)\s*router\.root\('requests'\)/.test(app), true)
  check('...the Sources element handed that, its opener, its own open and how it is drawn (2.0.0-player.19), and the visualizer over it (.20)',
    /<Sources open=\{sourcesOpen\} request=\{getting\} opener=\{sourcesOpener\} onClose=\{closeSources\} onQueued=\{gotten\} panel=\{panel\} covered=\{visualizerShown\} \/>/.test(app), true)
  check('a card\'s Get asks for the download, then hands over - in the tap, nothing awaited',
    [/onClick=\{\(\) => onGet\(candidate\)\}/.test(card), /const get = \(candidate: Candidate\) => \{\s*if \(state\.download\(candidate, shown\)\) onQueued\(\)\s*\}/.test(sheet)], [true, true])
  const ask = /function ask\([^)]*\): boolean \{([\s\S]*?)\n  \}/.exec(hook)?.[1] ?? ''
  check('...and the hook asks requestDownload straight away (the pending row is up from the tap), with up to ten runners-up as shown',
    [/requestDownload\(\{/.test(ask), /\bawait\b/.test(ask.slice(0, ask.indexOf('requestDownload('))), /release: \{ \.\.\.release \}/.test(ask), /\.slice\(0, 10\)/.test(ask)],
    [true, false, true, true])
  const run = /async function run\([^)]*\) \{([\s\S]*?)\n  \}/.exec(hook)?.[1] ?? ''
  check('the search: the newest answer only, its fetch called off when superseded',
    [/const requests = useMemo\(latestOnly, \[\]\)/.test(hook), /const request = requests\.begin\(\)/.test(run), /request\.signal/.test(run),
      /if \(!request\.current\(\)\) return\s*setSearch\(\{ release, pending: false, result/.test(run), /if \(!request\.current\(\) \|\| isAbort\(caught\)\) return/.test(run)],
    [true, true, true, true, true])
  check('a pick only on a fresh Get, never for a pressing held or on its way, and said when it isn\'t made',
    [/if \(!fresh \|\| !rule\.pick\) return/.test(run), /const blocked = autoPickBlocked\(result, release\)/.test(run), /autoGrabPick\(result\.candidates, rule\.filters, rule\.sort\)/.test(run),
      /setNotPicked\(notPickedLine\(blocked\)\)/.test(run), /requery\(\) \{\s*if \(search\) void run\(search\.release, queryOverride\(query, shownQuery\), false\)/.test(hook)],
    [true, true, true, true, true])
  check('...the settings read as the answer lands, the safe default until they\'re in',
    /pick: getSettingsNow\(\)\.get_mode === 'pick'/.test(sheet), true)
  check('the page\'s store state, and a chip\'s pressings, each through a latestOnly() of its own',
    [/const stateRequests = useMemo\(latestOnly, \[\]\)/.test(page), /storeState\(download\.release, request\.signal\)/.test(page), /if \(request\.current\(\)\) setStore\(/.test(page),
      /const getRequests = useMemo\(latestOnly, \[\]\)/.test(search), /getReleaseGroup\(group\.id, request\.signal\)/.test(search), /if \(!request\.current\(\)\) return\s*setResolving\(null\)/.test(search)],
    [true, true, true, true, true, true])
  check('in the sheet, the best match\'s Get is the one solid purple button - the top by score, wherever the sort puts it',
    [/class=\{`app-source-get \$\{best \? 'is-primary' : 'is-tinted'\}`\}/.test(card), /best=\{candidateKey\(candidate\) === best\}/.test(sheet),
      /const top = sortCandidates\(passing, 'score'\)\[0\]/.test(sheet), /best=\{index === 0\}/.test(sheet), /is-primary|app-primary/.test(sheet)], [true, true, true, false, false])
  //? review: the two sheets never stack, however late a chip's lookup lands
  check('a chip\'s lookup is called off when Search\'s root stops being what shows, and Sources never opens over Now Playing',
    //? (2.0.0-player.19: the Sources SHEET - a phone's; a desktop's panel leaves Search's root showing)
    [/const searchActive = nav\.tab === 'search' && nav\.stacks\.search\.length === 0 && !sheetOpen && !sourcesOver/.test(app) && /const sourcesOver = sourcesOpen && !desktop/.test(app),
      /<Search\b[^>]*\bactive=\{searchActive\}/.test(app),
      /useEffect\(\(\) => \{\s*if \(!active\) standDown\(\)\s*\}, \[active\]\)/.test(search), /function standDown\(\) \{\s*getRequests\.supersede\(\)\s*setResolving\(null\)/.test(search),
      /const openSources = useCallback\([^)]*\) => \{\s*if \(nowPlayingOpen\.current\) return/.test(app), /nowPlayingOpen\.current = sheetOpen/.test(app)],
    [true, true, true, true, true, true])
  check('Cancel, the backdrop and Escape let the search go in the gesture, the effect a backstop',
    [/const onClose = \(\) => \{\s*state\.stop\(\)\s*closeSheet\(\)\s*\}/.test(sheet), /useSheet\(\{ open, covered, onClose, lockClass: 'app-sources-open'/.test(sheet),
      /onClose: closeSheet,/.test(sheet), /if \(!open\) state\.stop\(\)/.test(sheet)], [true, true, true, true])
  check('the album page is told whether it is what shows, and asks the store again as it comes back - Get above what is already here',
    [/shown=\{pageShown && nav\.tab === tab && !sourcesOver\}/.test(app), /\}, \[chosen\?\.id, group\?\.id, filed, shown\]\)/.test(page), /if \(!shown\) return/.test(page),
      page.indexOf('class="app-rg-get"') < page.indexOf('class="app-rg-store"'), /setStore\(null\)/.test(page)], [true, true, true, true, false])
}

console.log('\nArtists and the id bridge: Play from the tap with every album in hand; the newest answer only')
{
  const page = code(read('app/ArtistPage.tsx'))
  const play = /const play = \(shuffle: boolean\) => \{([\s\S]*?)\n  \}/.exec(page)?.[1] ?? ''
  check('the artist\'s Play and Shuffle play straight from the tap: every album remembered at once, then playTracks - nothing fetched or awaited',
    [/if \(!playable\) return/.test(play), /rememberQueue\(albums\)\s*actions\.playTracks\(tracks, shuffle \? null : 0, shuffle\)/.test(play),
      /\bawait\b|\.then\(|fetch|prefetchAlbum|artistAlbums/.test(play)],
    [true, true, false])
  check('...disabled until every album they play has answered, the library has said which are copies of one, and one has its songs',
    [/const settled = playing\.every\(\(album\) => ready\.has\(album\) \|\| unsent\.has\(album\)\)/.test(page) && /const wanted = ownedKnown \? playing\.filter/.test(page), /const playable = settled && inHand\.length > 0/.test(page),
      (page.match(/disabled=\{!playable\}/g) ?? []).length, /onClick=\{\(\) => play\(false\)\}/.test(page), /onClick=\{\(\) => play\(true\)\}/.test(page)],
    [true, true, 2, true, true])
  check('...their songs asked for KEPT as the albums are known, a few at a time, only the newest set kept',
    /const request = prefetches\.begin\(\)\s*inTurns\(wanted, PREFETCH_AT_ONCE, \(album\) => prefetchAlbum\(album, true\)\.then\(\s*\(answer\) => \{\s*if \(request\.current\(\)\) setReady[\s\S]*?\(\) => request\.current\(\)\)/.test(page), true)
  const begins = ['findRequests', 'libraryRequests', 'factsRequests', 'discRequests', 'prefetches', 'openRequests', 'getRequests']
  check('every fetch on the page through a latestOnly() of its own', begins.map((name) =>
    new RegExp(`const ${name} = useMemo\\(latestOnly, \\[\\]\\)`).test(page) && new RegExp(`${name}\\.begin\\(\\)`).test(page)), begins.map(() => true))
  check('a row\'s Get and a row\'s bridge: the opener taken in the tap, both lookups called off when the page stops being what shows - and a late answer opens nothing',
    [/const opener = takeOpener\(event\)\s*const request = getRequests\.begin\(\)/.test(page),
      /if \(!shown\) \{\s*getRequests\.supersede\(\)\s*setResolving\(null\)\s*openRequests\.supersede\(\)\s*setOpening\(null\)/.test(page),
      (page.match(/if \(!showing\.current\) return/g) ?? []).length], [true, true, 2])
  const app = code(read('app/App.tsx'))
  check('App: an artist Navidrome knows inside the gate, one MusicBrainz knows outside it, told whether it shows',
    [/return page\.id\.startsWith\(MB_PREFIX\) \? artist : \(\s*<NeedsNavidrome\b/.test(app), /page\.kind === 'artist' \? artistView\(tab, page\)/.test(app),
      /<ArtistPage\b[\s\S]*?shown=\{pageShown && nav\.tab === tab && !sourcesOver\}[\s\S]*?onGet=\{openSources\}/.test(app)],
    [true, true, true])

  const requests = code(read('app/Requests.tsx'))
  const playRow = /const playRow = \(row: RequestRow\) => \{([\s\S]*?)\n  \}/.exec(requests)?.[1] ?? ''
  check('a Done row\'s ▶ plays its album only with its songs in hand - nothing awaited - and opens it otherwise',
    [/const album = row\.release \? ready\.get\(row\.release\)\?\.answer : undefined/.test(playRow),
      /if \(album && album\.song\?\.length\) \{\s*rememberPlayed\(album\)\s*actions\.playTracks\(album\.song\.map\(\(song\) => toQueueTrack\(song, album\)\), 0\)\s*return\s*\}\s*openRow\(row\)/.test(playRow),
      /\bawait\b|\.then\(|fetch|navidromeAlbumFor|prefetchAlbum/.test(playRow)],
    [true, true, false])
  check('...the first few asked for ahead (KEPT), only while the tab\'s root shows - never as the app starts - and looked for again when due',
    [/const request = period\.current\s*if \(!active \|\| !request \|\| !ahead\.length\) return\s*const \{ look, songs, nextIn \} = doneLooks\(/.test(requests),
      /prefetchAlbum\(album, true, fresh\)/.test(requests), /setTimeout\(\(\) => setDue\(\(count\) => count \+ 1\), nextIn\)/.test(requests),
      /active=\{requestsActive\}/.test(app), /const requestsActive = watching === 'requests' && !sourcesOver/.test(app), /requestsSeen/.test(app)],
    [true, true, true, true, true, false])
  check('...a tap\'s look called off as the tab stops showing, and one answering late opens nothing',
    [/\} else \{\s*aheadRequests\.supersede\(\)\s*period\.current = null\s*openRequests\.supersede\(\)\s*setOpening\(null\)/.test(requests), /if \(showing\.current\) onOpenAlbum\(/.test(requests)],
    [true, true])
  check('...each look through a latestOnly() of its own', ['aheadRequests', 'openRequests'].map((name) =>
    new RegExp(`const ${name} = useMemo\\(latestOnly, \\[\\]\\)`).test(requests) && new RegExp(`${name}\\.begin\\(\\)`).test(requests)), [true, true])

  const album = code(read('player/AlbumPage.tsx'))
  check('the album page\'s store answer, Search\'s held row and Info\'s details: each through a latestOnly() of its own',
    [/const storeRequests = useMemo\(latestOnly, \[\]\)/.test(album), /storeAlbum\(\{ navidrome_id: id \}, request\.signal\)\.then\(\s*\(answer\) => \{\s*if \(request\.current\(\)\) setStore/.test(album),
      /const request = heldRequests\.begin\(\)/.test(code(read('app/Search.tsx'))), /const request = requests\.begin\(\)/.test(code(read('app/useInfoDetails.ts')))],
    [true, true, true, true])
  check('...a held row\'s look called off with the chip\'s, when the box changes or the root stops showing',
    /function standDown\(\) \{\s*getRequests\.supersede\(\)\s*setResolving\(null\)\s*heldRequests\.supersede\(\)/.test(code(read('app/Search.tsx'))), true)
  check('the album page\'s chip row is drawn from the first frame, so a chip landing moves nothing below it - unseen until the bridge has answered or failed (2.0.0-player.41), so nothing in it slides',
    //? (2.0.0-player.52) the badge says whose it is - "In the store" (is-store) when, with logins on, it isn't yours -
    //? and (review) with logins on the row waits for whose it is too (the album's own answer), so the badge doesn't flip
    [/<div class=\{`app-album-chips\$\{storeDone && !mine\.pending \? '' : ' is-waiting'\}`\}>\s*<span class=\{`app-held-badge\$\{mine\.yours === true \? '' : ' is-store'\}`\}>/.test(album),
      /const storeDone = store !== null \|\| storeFailed/.test(album)],
    [true, true])
  check('Search\'s held row opens the album you have with its credited artist, so the page\'s artist line holds its place',
    /const artist = creditName\(group\['artist-credit'\]\)\s*if \(album\) onOpenAlbum\(\{ id: album, name: group\.title \?\? '', \.\.\.\(artist \? \{ artist \} : \{\}\) \}\)/.test(code(read('app/Search.tsx'))), true)
  check('an artist\'s name that isn\'t a link is drawn plain: on an album page only once the album has said so, never in a flash',
    [/<p class=\{`pl-hero-artist\$\{album \? ' app-hero-plain' : ''\}`\}>\{artistName\}<\/p>/.test(album), /<p class="pl-hero-artist app-hero-plain">\{header\.artist\}<\/p>/.test(code(read('app/ReleaseGroupPage.tsx')))],
    [true, true])
  check('a row looking for its album fades: an artist\'s, Search\'s, a Done row',
    [/class=\{`app-artist-album\$\{opening === row\.key \? ' is-busy' : ''\}`\}/.test(page), /class=\{`app-result\$\{looking \? ' is-busy' : ''\}`\}/.test(code(read('app/SearchRows.tsx'))),
      /class=\{`app-done-open\$\{opening \? ' is-busy' : ''\}`\}/.test(code(read('app/JobCard.tsx')))],
    [true, true, true])
  check('Library\'s rows navigate: nothing there reaches a playback action, as a tile', [actionsIn(code(read('player/Library.tsx'))), actionsIn(code(read('app/LibraryViews.tsx')))], [[], []])
  const library = code(read('player/Library.tsx'))
  check('Songs only where Navidrome\'s empty search lists songs: asked once, for one, the chip left out on an empty answer (and the albums shown)',
    //? (2.0.0-player.19: told to the Library's store, app/libraryPick.ts, which the desktop sidebar reads too)
    [/librarySongs\(0, 1, request\.signal\)\.then\(\s*\(songs\) => \{\s*if \(request\.current\(\)\) setLibrarySongs\(songs\.length > 0\)/.test(library),
      //? (2.0.0-player.52) the chips are yours or Browse's with a library of your own; Songs falls back by shownPick
      /const views = \(personal \? \(browsing \? BROWSE_VIEWS : YOUR_VIEWS\) : VIEWS\)\.filter\(\(entry\) => entry\.id !== 'songs' \|\| hasSongs !== false\)/.test(library),
      /const showing: LibraryPick = shownPick\(pick, hasSongs, 'phone', personal\)/.test(library)],
    [true, true, true])
}

console.log('\npins: deadwax\'s own, asked when asked, and nothing about them plays')
{
  const PIN_FILES = ['app/Pinned.tsx', 'app/PinToggle.tsx', 'app/PinNotice.tsx', 'app/usePins.ts', 'lib/pins.ts', 'lib/home.ts', 'app/Home.tsx', 'app/ActionMenu.tsx']
  check('nothing about pins, or Home, reaches a playback action', PIN_FILES.map((file) => [file, actionsIn(code(read(file)))]), PIN_FILES.map((file) => [file, []]))
  //? stars are a Navidrome user's own, and will be the personal library (step 5): a pin is never one
  check('never Navidrome\'s stars: nothing in the app asks Navidrome to star, unstar or list them',
    files.filter((file) => /['"`/](un)?star['"`?/]|getStarred/.test(code(read(file)))), [])
  check('...and the pins are deadwax\'s routes', [/get<PinsAnswer>\('\/me\/pins'/.test(code(read('api/me.ts'))), /put<PinsAnswer>\('\/me\/pins'/.test(code(read('api/me.ts'))),
    /post<PinsAnswer>\('\/me\/pins\/toggle'/.test(code(read('api/me.ts')))], [true, true, true])

  const store = code(read('app/usePins.ts'))
  check('every read and every change through the store, one after another, so the newest answer lands last',
    [/confirmed = await getPins\(\)/.test(store) && /asking = inTurn\(async \(\) => \{/.test(store), /confirmed = await inTurn\(request\)/.test(store),
      /togglePin\(toggleBody\(target, true\)\)/.test(store),
      //? Edit's PUT made at send time from the server's word, with that word beside it (`known`)
      /const word = confirmed\?\.pins \?\? \[\]\s*return putPins\(orderBody\(applyPinOp\(word, op\), word\)\)/.test(store)],
    [true, true, true, true])
  check('...asked only when a component asks: afresh, or only when nothing recent is in hand',
    [/if \(ask\) void askPins\(ask === 'fresh'\)/.test(store), /if \(!fresh && confirmed && Date\.now\(\) - confirmedAt < PINS_KEPT_MS\) return Promise\.resolve\(\)/.test(store)], [true, true])

  const home = code(read('app/Home.tsx'))
  const app = code(read('app/App.tsx'))
  check('Home asks afresh as it comes into view, and App says when that is - never as the app starts',
    [/const \{ pins, problem \} = usePins\(shown \? 'fresh' : false\)/.test(home), /const homeShown = watching === 'home'/.test(app), /<Home\b[^>]*?shown=\{homeShown\}/.test(app.replace(/\n\s*/g, ' ')),
      //? (2.0.0-player.51) and what is new in your library, which it draws too
      /\[status, arriving, arrivingTrouble, homeShown, newAlbums\]/.test(app)],
    [true, true, true, true])
  check('...the shelves drawn once the pins have answered, or failed, or the wait - counted only while Home shows - is over',
    //? (2.0.0-player.51) and, as the pins are, what is new in your library - so its shelf never moves those under it
    [/const ready = \(pins !== null \|\| problem !== null \|\| waited\) && \(newAlbums !== null \|\| waited\)/.test(home), /<div class="app-home-shelves" hidden=\{!ready\}>/.test(home), /if \(!shown \|\| waited\) return/.test(home)], [true, true, true])
  check('...New in your library (2.0.0-player.51) under Pinned and over Recently added, drawn only with something new; App asks for it as Home - or the Library tab, whose tiles carry the marks - comes into view, and an album opened is new no longer',
    [home.indexOf('<Pinned ') < home.indexOf('<NewInYourLibrary ') && home.indexOf('<NewInYourLibrary ') < home.indexOf('{recent}'),
      /\{!!newAlbums\?\.length && <NewInYourLibrary albums=\{newAlbums\} onOpen=\{onOpen\} \/>\}/.test(home),
      /const libraryShown = pageShown && nav\.tab === 'library'/.test(app),
      /useEffect\(\(\) => \{\s*if \(homeShown \|\| libraryShown\) askMyLibrary\(\)\s*\}, \[homeShown, libraryShown\]\)/.test(app),
      /const openAlbum = useCallback\(\(album: Album\) => \{\s*seenAlbum\(album\)/.test(app)],
    [true, true, true, true, true])
  check('...and the album page on top seen - reached by its address too - again as an answer lands (review)',
    [/const topAlbum = topPage\?\.kind === 'album' \? topPage\.id : null/.test(app),
      /if \(topAlbum === null \|\| !pageShown\) return[\s\S]{0,200}seenAlbum\(\{ id: topAlbum,[\s\S]{0,160}\}, \[topAlbum, pageShown, myLibrary\]\)/.test(app)],
    [true, true])
  check('...with logins off (no library) Home is handed nothing new at once - never left waiting out its spinner for an answer never asked',
    /const newAlbums = useMemo\(\(\) => \(!hasLibrary\(\) \? NOTHING_NEW : myLibrary \? newShelf\(myLibrary\) : null\), \[myLibrary\]\)/.test(app), true)
  check('...and Library care draws Held by nobody only with logins on',
    /\{sessionMe\(\)\?\.auth === 'on' && <HeldByNobody live=\{live\} \/>\}/.test(code(read('app/LibraryCare.tsx'))), true)
  check('...Pinned first, then Recently added, then Not played in a while, all inside the gate',
    /<NeedsNavidrome\b[^>]*>\s*<Shelves\b/.test(home) && home.indexOf('<Pinned ') < home.indexOf('{recent}') && home.indexOf('{recent}') < home.indexOf('{notPlayed}'), true)
  const notPlayed = home.slice(home.indexOf('function NotPlayedInAWhile('), home.indexOf('function Shelves('))
  check('Not played in a while: recent at 500, only the newest answer drawn',
    [/const requests = useMemo\(latestOnly, \[\]\)/.test(notPlayed), /albumPage\('recent', 0, request\.signal, RECENT_LISTED\)/.test(notPlayed), /if \(request\.current\(\)\) setAlbums\(notPlayedInAWhile\(/.test(notPlayed)],
    [true, true, true])

  const pinned = code(read('app/Pinned.tsx'))
  check('a pinned album opens as a tile does - asked for as the finger lands, called off for a scroll, opened on the click',
    /onPointerDown=\{\(\) => pin\.kind === 'album' && pin\.navidrome_id && prefetchAlbum\(pin\.navidrome_id\)\}\s*onPointerCancel=\{\(\) => pin\.kind === 'album' && pin\.navidrome_id && dropPrefetch\(pin\.navidrome_id\)\}\s*onClick=\{\(\) => open\(pin\)\}/.test(pinned), true)
  check('Edit\'s drag is the grip\'s, and moves rows by transform only - the list never reorders under the pointer',
    [/<span\s+class="app-pin-grip"[\s\S]*?onPointerDown=/.test(pinned), (pinned.match(/onPointerDown=/g) ?? []).length, /\{pins\.map\(\(pin, index\) => \{\s*const key = pinKey\(pin\)\s*const dragging/.test(pinned), /moveTo\(/.test(pinned)],
    [true, 2, true, false])

  const album = code(read('player/AlbumPage.tsx')).replace(/\n\s*/g, ' ')
  check('the album page\'s pin: by the release the bridge says, drawn until it says there is none, live only once it has - and the pins have',
    [/release_mbid: release, navidrome_id: id/.test(album), /\{!\(storeDone && !release\) && \(/.test(album), /ready=\{storeDone && !!release && pinsKnown\}/.test(album),
      /onToggle=\{\(\) => void setPinned\(pinTarget, !pinned\)\}/.test(album), /const \{ pins, known: pinsKnown, canSave \} = usePins\(true\)/.test(album),
      /onRefused=\{\(\) => sayPins\(PINS_UNSAVED\)\}/.test(album)],
    [true, true, true, true, true, true])
  const artist = code(read('app/ArtistPage.tsx')).replace(/\n\s*/g, ' ')
  check('the artist\'s pin: by MusicBrainz id, else name and Navidrome\'s id - live once that is settled, and the pins have answered',
    [/const pinTarget: ArtistPinTarget = \{ kind: 'artist', mbid, navidrome_id: libraryId, name, cover: picture \}/.test(artist),
      /const pinReady = pinsKnown && !!name && \(mbid !== null \|\| \(library\.state !== 'asking' && ownedKnown && libraryId !== null\)\)/.test(artist),
      /<PinToggle look="chip" pinned=\{pinned\} ready=\{pinReady\}/.test(artist), /const \{ pins, known: pinsKnown, canSave \} = usePins\(true\)/.test(artist),
      /onRefused=\{\(\) => sayPins\(PINS_UNSAVED\)\}/.test(artist)],
    [true, true, true, true, true])
  const appLine = app.replace(/\n\s*/g, ' ')
  check('the ••• menu\'s pin: asked as Now Playing opens, its tap closing the menu, saving and saying so - App\'s, handed to the menu',
    [/const pins = usePins\(sheetOpen\)/.test(app), /const pinPlaying = menuPin \? \(\) => \{\s*closeOver\(\)\s*void setPinned\(menuPin, !menuPinned, true\)/.test(app),
      /aria-disabled=\{pinned === null\}/.test(code(read('app/ActionMenu.tsx'))), /if \(pinned !== null\) onPin\(\)/.test(code(read('app/ActionMenu.tsx')))],
    [true, true, true, true])
  check('...only for a song whose album can be pinned: its album named, Navidrome not saying it has no release id (""), deadwax able to keep pins',
    /menuPinNow\.current = playing\?\.albumId && playingRelease !== '' && pins\.canSave \? \{/.test(appLine), true)
  check('...decided as the menu OPENS - nothing coming or going, nor changing album, while it is up - and inactive once pins can\'t be kept',
    [/const openMenu = useCallback\(\(event: MouseEvent\) => \{ moreOpener\.current = takeOpener\(event\) setMenuPin\(menuPinNow\.current\) setOver\('menu'\) \}, \[\]\)/.test(appLine),
      /const menuPinned = menuPin && pins\.pins && pins\.canSave \? pinOf\(pins\.pins, menuPin\) !== null : null/.test(app),
      /onPin=\{pinPlaying\}/.test(app)],
    [true, true, true])
  check('...and the ••• button promises the pin only then', /pinnable=\{menuPinNow\.current !== null\}/.test(app), true)
  check('the app\'s one notice for pins, drawn once - by App', [(app.match(/<PinNotice \/>/g) ?? []).length,
    files.filter((file) => file !== 'app/App.tsx' && /<PinNotice\b/.test(code(read(file))))], [1, []])
}

console.log('\nthe desktop frame: chosen below the engine, panels beside the page, the turntable the phone\'s')
{
  const app = code(read('app/App.tsx'))
  check('the frame is chosen in App, after the engine is made - so crossing 1024px never makes it again',
    [/export function App\(\) \{\s*const player = usePlayer\(\)\s*\/\/[^\n]*\n\s*const actions = useMemo\(\(\) => pickActions\(player\), \[\]\)\s*\/\/[^\n]*\n\s*const \{ frame, panel \} = useFrame\(\)/.test(read('app/App.tsx')),
      /const desktop = frame === 'desktop'/.test(app)], [true, true])
  //? the chrome around the panes swaps; the panes - each keyed on its tab, in the same place - don't
  const behind = /<div class="app-behind"[^>]*>([\s\S]*?)<\/div>\s*(?:\{(?:\/\*[\s\S]*?\*\/)?\}\s*)?<Sources\b/.exec(app)?.[1] ?? ''
  const at = (needle) => behind.search(needle)
  check('the sidebar, then the panes, then the player - the mini player or the bar - then the tab bar, each in its own slot',
    [at(/\{desktop && \(\s*<Sidebar\b/), at(/\{TABS\.map\(/), at(/\{desktop \? \(\s*<PlayerBar\b[^>]*\/>\s*\) : \(\s*<MiniPlayer\b[^>]*\/>\s*\)\}/), at(/\{!desktop && <TabBar\b/)]
      .every((place, index, all) => place !== -1 && (index === 0 || place > all[index - 1])), true)
  check('...each pane keyed on its tab', /<div key=\{tab\} class="app-pane" data-tab=\{tab\}/.test(behind), true)
  //? Now Playing - and its turntable - opens only from the mini player, which a desktop doesn't draw
  check('nothing on a desktop opens Now Playing: openSheet is the mini player\'s alone, and crossing into the desktop closes it',
    [(app.match(/\bopenSheet\b/g) ?? []).length, /<MiniPlayer player=\{player\} onOpen=\{openSheet\} \/>/.test(app),
      /const closes = closesOnCrossing\(frame\)\s*if \(closes\.nowPlaying\) \{[\s\S]*?setOver\('none'\)\s*setSheetOpen\(false\)/.test(app),
      /if \(closes\.infoPanel\) \{[\s\S]*?setInfoPanel\(false\)/.test(app)],
    [2, true, true, true])
  //? (2.0.0-player.36: and the turntable's test bench at /player/lab/ - a page of its own, no part of the app's frame)
  check('...and nothing but Now Playing draws the turntable - in the app; the test bench is a page of its own', files.filter((file) => /<Turntable\s/.test(code(read(file)))), ['lab/Bench.tsx', 'player/NowPlaying.tsx'])
  //? a side panel is no sheet over the page: Sources and Info take how they are drawn from App, and
  //? are modal only as a sheet
  const sheet = code(read('app/Sources.tsx'))
  const info = code(read('app/InfoSheet.tsx'))
  check('Sources and Info: modal only as a sheet, the page beside a panel left as it is',
    [/<InfoSheet\b[^>]*\bpanel=\{panel\}/.test(app.replace(/\n\s*/g, ' ')),
      [sheet, info].map((text) => /const modal = panelIsModal\(panel\)/.test(text) && /useSheet\(\{[^}]*\bmodal, area: box \}\)/.test(text)),
      /export function panelIsModal\(panel: PanelStyle\): boolean \{\s*return panel === 'sheet'\s*\}/.test(code(read('lib/appFrame.ts')))],
    [true, [true, true], true])
  //? (2.0.0-player.21: and the Edit panel, each putting it away too)
  //? (2.0.0-player.45: and the artist page's panel, each putting it away and it every other)
  check('one side panel at a time: Sources puts Info, Edit and the artist\'s away, and Info Sources, Edit and the artist\'s',
    [/setSourcesOpen\(true\)[\s\S]{0,250}?infoOpener\.current = null\s*setInfoPanel\(false\)\s*editOpener\.current = null\s*setEditOpen\(false\)\s*artistOpener\.current = null\s*setArtistOpen\(false\)/.test(/const openSources = useCallback[\s\S]*?\}, \[\]\)/.exec(app)?.[0] ?? ''),
      /infoOpener\.current = takeOpener\(event\)\s*sourcesOpener\.current = null\s*setSourcesOpen\(false\)\s*editOpener\.current = null\s*setEditOpen\(false\)\s*artistOpener\.current = null\s*setArtistOpen\(false\)\s*setInfoPanel\(true\)/.test(app)],
    [true, true])
  //? (review) the player bar's Info closes the panel it opened - "the Info button again"
  check('...and the player bar\'s Info, pressed again, closes it',
    /const toggleInfo = useCallback\(\(event: MouseEvent\) => \{\s*if \(infoPanelOpen\.current\) \{\s*setInfoPanel\(false\)\s*return\s*\}/.test(app), true)
  //? (review) which panel shows feeds both the shell's classes: room made for a column, a drawer over the page
  check('what the panel shows - Sources or Info - makes room for a column (`.has-side`) and marks a drawer (`.has-drawer`)',
    [/const side = sideOf\(frame, \{ sources: sourcesOpen, info: infoPanel, edit: editOpen, artist: artistOpen \}\)/.test(app),
      /\$\{makesRoom\(panel, side\) \? ' has-side' : ''\}\$\{liesOver\(panel, side\) \? ' has-drawer' : ''\}/.test(app)],
    [true, true])
  //? (review) a drawer lies over the page Go to album and Info's artist open: the Info drawer goes with them
  const leave = /const leaveInfoDrawer = \(\) => \{([\s\S]*?)\n  \}/.exec(app)?.[1] ?? ''
  check('Go to album and an artist from Info close the Info drawer first - a column stays beside the page',
    [/if \(!liesOver\(panel, infoPanel \? 'info' : 'none'\)\) return\s*infoOpener\.current = null\s*setInfoPanel\(false\)/.test(leave),
      /const goToAlbum = \(track[^)]*\) => \{\s*if \(!track\.albumId\) return\s*leaveInfoDrawer\(\)\s*moreOpener\.current = null/.test(app),
      /const toArtist = \(artist[^)]*\) => \{\s*leaveInfoDrawer\(\)\s*moreOpener\.current = null/.test(app)],
    [true, true, true])
  //? (review) the sidebar's Managing reads deadwax's answer, as You's row does
  check('the sidebar\'s Managing follows /deadwax/me: asked as the desktop frame shows, through latestOnly(), and handed over',
    [/const meRequests = useMemo\(latestOnly, \[\]\)/.test(app),
      /if \(!desktop\) return\s*const request = meRequests\.begin\(\)\s*me\(request\.signal\)\.then\(\s*\(who\) => \{\s*if \(request\.current\(\)\) setAdmin\(who\.admin\)/.test(app),
      /<Sidebar\b[\s\S]*?admin=\{admin\}/.test(app), /\{admin && \(\s*<section class="app-side-group" aria-labelledby="app-side-managing">/.test(code(read('app/Sidebar.tsx')))],
    [true, true, true, true])
  //? the player bar's transport, straight from the click, nothing awaited
  const bar = code(read('player/PlayerBar.tsx'))
  check('the player bar calls the player straight from the click',
    ['previous', 'toggle', 'next', 'showAirPlay'].map((name) => new RegExp(`onClick=\\{\\(\\) => player\\.${name}\\(\\)\\}`).test(bar)).concat(/\bawait\b|\.then\(/.test(bar)),
    [true, true, true, true, false])
  check('...and the sidebar reaches none, nor any context', [actionsIn(code(read('app/Sidebar.tsx'))), /useContext|usePlayerActions|PlayerContext/.test(code(read('app/Sidebar.tsx')))], [[], false])
  //? the album you don't have follows the pressing chosen while a desktop's panel shows its Get
  const page = code(read('app/ReleaseGroupPage.tsx'))
  //? (review: the album's group alone said Get was pressed for any pressing of it - now the pressing searched too)
  check('a desktop\'s Sources panel follows the pressing: searched again as another is chosen - `again`, no pick',
    [/const sourcesGroup = desktop && sourcesOpen \? getting\?\.from \?\? null : null\s*const sourcesPressing = sourcesGroup \? getting\?\.release\.release_mbid \?\? null : null/.test(app),
      /sourcesPressing=\{sourcesGroup === page\.id \? sourcesPressing : null\}/.test(app),
      /if \(!shown \|\| sourcesPressing === null \|\| !download \|\| !chosen \|\| sourcesPressing === chosen\.id\) return\s*onGet\(\s*\{[^}]*from: id, again: true \},\s*getButton\.current,\s*\)\s*\}, \[shown, sourcesPressing, chosen\?\.id\]\)/.test(page),
      /if \(request\.again\) \{\s*begin\(request\.release, false\)\s*return\s*\}/.test(sheet),
      /start\(release, fresh = true\) \{[\s\S]*?void run\(release, '', fresh\)/.test(code(read('hooks/useCandidateSearch.ts')))],
    [true, true, true, true, true])
  //? the sidebar: its field types into Search's box and shows Search's results; its Library views are
  //? the Library's own store; the Library, on a desktop, titled by its view
  const side = code(read('app/Sidebar.tsx'))
  check('the sidebar\'s field is Search\'s box: typing goes to it and shows Search\'s results, Enter asks it',
    [/setText\(next\)\s*typeSearch\(next\)\s*if \(next\.trim\(\)\) onSearch\(\)/.test(side), /onSearch\(\)\s*submitSearch\(\)/.test(side),
      /<Sidebar\b[\s\S]*?onSearch=\{showSearch\}/.test(app), /const showSearch = useCallback\(\(\) => \{\s*if \(router\.nav\.tab === 'search' && !router\.nav\.stacks\.search\.length\) return\s*router\.root\('search'\)/.test(app)],
    [true, true, true, true])
  const library = code(read('player/Library.tsx'))
  check('the Library reads its view from the store the sidebar chooses from, titled by it on a desktop, Recently added the albums newest first',
    //? (2.0.0-player.52) titled yours or the store's with a library of your own (lib/appFrame.ts libraryTitle)
    [/const \{ pick, hasSongs \} = useLibraryPick\(\)/.test(library), /<h1 class="pl-large-title" ref=\{title\} tabIndex=\{-1\}>\{desktop \? libraryTitle\(drawn, personal\) : 'Library'\}<\/h1>/.test(library),
      /<div hidden=\{drawn !== 'recent'\}>\s*<AlbumsView order="newest"/.test(library), /const choose = \(next: LibraryPick\) => \{\s*if \(next !== showing\) chooseLibrary\(next\)/.test(library)],
    [true, true, true, true])
}

console.log('\nthe desktop visualizer: a silent copy, never the player\'s element; its toggle from the click')
{
  const VIZ = ['player/Visualizer.tsx', 'player/vizAudio.ts', 'player/vizDraw.ts', 'player/vizGl.ts', 'lib/vizSync.ts', 'lib/musicFeel.ts', 'lib/visualizer.ts', 'lib/vizShaders.ts']
  check('its files are all there', VIZ.filter((file) => !files.includes(file)), [])
  //? the one hard rule: createMediaElementSource reroutes the song through Web Audio (and breaks locked
  //? playback on an iPhone) - not one file under ui/src may call it, the old page's included
  const ROUTES_THE_SONG = /createMediaElementSource|createMediaStreamSource/
  check('nothing in the app calls createMediaElementSource - no file at all', files.filter((file) => ROUTES_THE_SONG.test(code(read(file)))), [])
  check('...found where it is (the check sees one)', ROUTES_THE_SONG.test(code('const tap = context.createMediaElementSource(element)')), true)
  const TOUCHES = [
    ['an element looked up', /querySelector\(\s*['"]audio|getElementsByTagName/],
    ['a media element', /HTMLMediaElement|HTMLAudioElement|new\s+Audio\b|<audio\b/],
    ['.src =', /\.src\s*=(?!=)/],
    ['srcObject', /srcObject/],
    ['.load(', /\.load\s*\(/],
    ['.play(', /\.play\s*\(/],
    ['.pause(', /\.pause\s*\(/],
  ]
  check('none of its files touches a media element: nothing looked up, set, loaded, played or paused',
    VIZ.flatMap((file) => TOUCHES.filter(([, pattern]) => pattern.test(code(read(file)))).map(([name]) => `${file}: ${name}`)), [])
  //? James opens deadwax over plain http: nothing that only a secure page has
  const SECURE_ONLY = /audioWorklet|AudioWorkletNode|randomUUID|crypto\.subtle|navigator\.clipboard|getUserMedia|serviceWorker/
  check('nothing of it needs a secure page (no AudioWorklet, nothing else only HTTPS has)', VIZ.filter((file) => SECURE_ONLY.test(code(read(file)))), [])
  check('nothing of it is random - the styles rotate in a fixed order', VIZ.filter((file) => /Math\.random|getRandomValues/.test(code(read(file)))), [])

  const screen = code(read('player/Visualizer.tsx'))
  check('its files reach no playback action but the screen\'s toggle',
    VIZ.map((file) => [file, actionsIn(code(read(file)))]).filter(([, found]) => found.length), [['player/Visualizer.tsx', ['toggle']]])
  const toggle = /const onToggle = \(\) => \{([\s\S]*?)\n  \}/.exec(screen)?.[1] ?? ''
  check('...called only in onToggle, nothing awaited - from the button\'s click and the Space key',
    [(screen.match(/\.toggle\(\)/g) ?? []).length, /player\.toggle\(\)/.test(toggle), /\bawait\b|\.then\(/.test(toggle),
      /<button type="button" class="app-viz-play" onClick=\{onToggle\}/.test(screen),
      /if \(key === ' ' \|\| key === 'Spacebar' \|\| event\.code === 'Space'\) \{\s*event\.preventDefault\(\)\s*if \(event\.repeat\) return\s*onToggle\(\)/.test(screen)],
    [1, true, false, true, true])
  //? one press, one toggle: a held Space's repeats would play and pause the song over and over
  check('...a held Space\'s repeats ignored - the one key handler that reaches onToggle',
    [(screen.match(/\bonToggle\(\)/g) ?? []).length, (screen.match(/event\.repeat/g) ?? []).length], [1, 1])

  //? its audio context: made only in wakeVisualizerAudio, which only the click that opens it calls
  const audio = code(read('player/vizAudio.ts'))
  const inAudio = [...audio.matchAll(/\n(export )?function (\w+)\([^)]*\)[^{]*\{[\s\S]*?\n\}/g)]
  check('its audio context is made only inside wakeVisualizerAudio', inAudio.filter((fn) => /\bnew Context\(/.test(fn[0])).map((fn) => fn[2]), ['wakeVisualizerAudio'])
  //? ...by the one constructor contextClass() finds, looked up there alone - nor made any other way:
  //? no `new (something)()`, no AudioContext named anywhere else in the file
  check('...the constructor looked up only there, named only where it is found, and nothing built from an expression',
    [inAudio.filter((fn) => /\bcontextClass\(\)/.test(fn[0]) && fn[2] !== 'contextClass').map((fn) => fn[2]),
      inAudio.filter((fn) => /\b(?:webkit)?AudioContext\b(?!\s*[|>)])/.test(fn[0].replace(/:\s*AudioContext\b/g, ''))).map((fn) => fn[2]),
      /\bnew\s*\((?!\))/.test(audio)],
    [['wakeVisualizerAudio'], ['contextClass'], false])
  //? ...and nowhere in the WHOLE file - the class's methods included, which the function scan above
  //? doesn't reach: contextClass() defined and called once (in wakeVisualizerAudio), AudioContext named
  //? only where contextClass looks it up (and as a type), and nothing made with `new` but the one
  //? context, typed arrays and errors
  const wakeBody = inAudio.find((fn) => fn[2] === 'wakeVisualizerAudio')?.[0] ?? ''
  const madeWithNew = [...audio.matchAll(/\bnew\s+([A-Za-z_$][\w$]*)\s*[<(]/g)].map((m) => m[1])
    .filter((name) => !/^(?:Uint8Array|Float32Array|Uint8ClampedArray|Int16Array|Float64Array|Map|Set|Error|ApiError)$/.test(name))
  const contextBody = inAudio.find((fn) => fn[2] === 'contextClass')?.[0] ?? ''
  check('...the whole file: contextClass() once besides its own name, AudioContext named only in it, `new Context(` the only thing made, inside wakeVisualizerAudio',
    [(audio.match(/\bcontextClass\(\)/g) ?? []).length, /\bcontextClass\(\)/.test(wakeBody),
      (audio.replace(contextBody, '').replace(/:\s*(?:AudioContext|ContextClass)\b(?:\s*\|\s*null)?/g, '').replace(/type ContextClass = new \(\) => AudioContext/, '').match(/\b(?:webkit)?AudioContext\b/g) ?? []).length,
      madeWithNew, /\bnew Context\(\)/.test(wakeBody)],
    [2, true, 0, ['Context'], true])
  check('...found where it is (the whole-file check sees a context made in a method)',
    [...code('class X { tick() { const C = contextClass(); if (C) audio.context = new C() } }').matchAll(/\bnew\s+([A-Za-z_$][\w$]*)\s*[<(]/g)].map((m) => m[1]), ['C'])
  const enclosing = (text, at) => {
    const blocks = [...text.matchAll(/\n( *)const (\w+) = [^\n]*=> \{[\s\S]*?\n\1\}/g)]
    return blocks.filter((block) => block.index <= at && at < block.index + block[0].length).at(-1)?.[2] ?? null
  }
  const wakes = files.filter((file) => file !== 'player/vizAudio.ts').flatMap((file) => {
    const text = code(read(file))
    return [...text.matchAll(/\bwakeVisualizerAudio\(\)/g)].map((match) => `${file}: ${enclosing(text, match.index)}`)
  })
  check('...and wakeVisualizerAudio is called only from App\'s openVisualizer - the player bar\'s click', wakes, ['app/App.tsx: openVisualizer'])
  const app = code(read('app/App.tsx'))
  check('...which takes the button as where focus goes back, wakes the audio and opens it - in the click',
    /const openVisualizer = useCallback\(\(event: MouseEvent\) => \{\s*visualizerOpener\.current = takeOpener\(event\)\s*wakeVisualizerAudio\(\)\s*setVisualizing\(true\)\s*\}, \[\]\)/.test(app), true)
  const bar = code(read('player/PlayerBar.tsx'))
  check('the entry is the player bar\'s button - and only a desktop draws the bar', [/<button type="button" class="app-playbar-button" onClick=\{onVisualizer\} aria-label="Full-screen visualizer">/.test(bar),
    /<PlayerBar\b[^>]*\bonVisualizer=\{openVisualizer\}[^>]*\/>/.test(app), /\{desktop \? \(\s*<PlayerBar\b/.test(app),
    files.filter((file) => /\bonVisualizer\b/.test(code(read(file)))).sort()], [true, true, true, ['app/App.tsx', 'player/PlayerBar.tsx']])
  check('...and the screen is drawn by App alone, only on a desktop, closed as the window crosses to a phone\'s width',
    [files.filter((file) => /<Visualizer\b/.test(code(read(file)))), /<Visualizer open=\{visualizerShown\} player=\{player\} opener=\{visualizerOpener\} onClose=\{closeVisualizer\} \/>/.test(app),
      /const visualizerShown = desktop && visualizing/.test(app), /if \(closes\.infoPanel\) \{[^}]*setVisualizing\(false\)/.test(app),
      /export function Visualizer\([^)]*\) \{\s*if \(!open\) return null/.test(code(read('player/Visualizer.tsx')).replace(/\{ open, player, opener, onClose \}: \{[\s\S]*?\}\)/, '{ open, player, opener, onClose })'))],
    [['app/App.tsx'], true, true, true, true])

  //? the silent copy: through an analyser into a gain of 0 - nothing of it reaches the speakers
  check('the copy plays into the analyser, the analyser into a gain of 0, and only that gain reaches the destination',
    [/node\.connect\(this\.analyser\)/.test(audio), /analyser\.connect\(silent\)/.test(audio), /silent\.gain\.value = 0/.test(audio),
      (audio.match(/\.connect\(context\.destination\)/g) ?? []).length, /silent\.connect\(context\.destination\)/.test(audio)],
    [true, true, true, 1, true])
  //? ...however it is spelled: `destination` named once in the whole file (so no other node reaches it
  //? through a variable or another context), and the gain written once, to 0 - nothing ramps it, sets it
  //? at a time, or assigns it again
  const GAIN_WRITES = /\.gain\s*\.\s*(?:value\s*=(?!=)|setValueAtTime|linearRampToValueAtTime|exponentialRampToValueAtTime|setTargetAtTime|setValueCurveAtTime|cancelScheduledValues|cancelAndHoldAtTime)|\.gain\s*=(?!=)|\bconnect\([^)]*\.gain\b/g
  check('...the destination named once in the whole file, and the gain written once - to 0',
    [(audio.match(/\bdestination\b/g) ?? []).length, audio.match(GAIN_WRITES) ?? [], (audio.match(/\.gain\.value = 0\b/g) ?? []).length],
    [1, ['.gain.value ='], 1])
  check('...found where it is (the checks see another way to the destination, and a gain ramped up)',
    [(code('const out = this.madeFor!.destination; node.connect(out)').match(/\bdestination\b/g) ?? []).length,
      code('silent.gain.value = 0; silent.gain.setValueAtTime(1, 0)').match(GAIN_WRITES)],
    [1, ['.gain.value =', '.gain.setValueAtTime']])
  check('...its windows the turntable\'s (scrubWindow), only the newest asked and decoded',
    [/await scrubWindow\(song\.id, from, VIZ_WINDOW_S, request\.signal, song\.maxRate\)/.test(audio), /const request = this\.requests\.begin\(\)/.test(audio),
      /if \(!request\.current\(\)\) return/.test(audio), /const ticket = this\.decodes\.begin\(\)/.test(audio)],
    [true, true, true, true])
  check('the screen asks for the queue\'s next song too, so its first window is fetched ahead (lib/vizSync.ts prefetch)',
    [/const after = nextIndex\(p\.queue\)/.test(screen), /listener\.tick\(song, following \? syncSong\(following, following\.duration, p\.maxRate\) : null, playing && !p\.buffering, p\.position\(\), p\.speed\(\)\)/.test(screen),
      /else if \(plan\.prefetch !== null && following\) void this\.fetchWindow\(following, plan\.prefetch\)/.test(audio), /const taken = takeAhead\(this\.held, this\.ahead, this\.current, following\?\.id \?\? null\)/.test(audio)],
    [true, true, true, true])
  //? a tap on a touch screen (an iPad on its side is a desktop frame) moves no pointer: a press brings
  //? the faded controls back, and its click is swallowed so it presses nothing hidden under it
  check('a press brings the faded controls back, and only that - its click swallowed while they were hidden',
    [/const onPointerDown = \(event: PointerEvent\) => \{\s*wokeByPress\.current = latest\.current\.visible \? 0 : performance\.now\(\)\s*wake\(\)/.test(screen),
      /if \(woke && performance\.now\(\) - woke < WAKE_CLICK_MS\) \{\s*event\.stopPropagation\(\)\s*event\.preventDefault\(\)/.test(screen),
      /onClickCapture=\{onClickCapture\}/.test(screen), /onPointerDown=\{onPointerDown\}/.test(screen)],
    [true, true, true, true])
  //? a control that goes with focus on it - the style list's option, the Style button leaving with
  //? Ambient - leaves focus on <body>, where none of the screen's keys reach: focus comes back
  check('focus never falls out of it: after every render, back to the screen; the list closed by a pick or Escape gives it to its button',
    [/useLayoutEffect\(\(\) => \{\s*const element = root\.current\s*if \(element && !element\.contains\(document\.activeElement\)\) element\.focus\(\{ preventScroll: true \}\)\s*\}\)/.test(screen),
      /const closeMenu = \(\) => \{\s*setMenuOpen\(false\)\s*styleButton\.current\?\.focus\(\{ preventScroll: true \}\)\s*\}/.test(screen),
      /if \(menuOpen\) closeMenu\(\)\s*else onClose\(\)/.test(screen), /setChoice\(next\)\s*closeMenu\(\)/.test(screen)],
    [true, true, true, true])
  //? closed while still full screen (Leave full screen, V..., an Escape the page gets), Chromium keeps the
  //? page outside the full-screen element inert until it has left: focus given back then goes nowhere
  check('focus goes back to the player bar\'s button - again once the browser has left full screen',
    [/const giveBack = \(\) => opener\.current\?\.focus\(\{ preventScroll: true \}\)/.test(screen),
      /const left = \(\) => \{\s*doc\.removeEventListener\('fullscreenchange', left\)\s*doc\.removeEventListener\('webkitfullscreenchange', left\)\s*clearTimeout\(giveUp\)\s*giveBack\(\)\s*\}/.test(screen),
      /doc\.addEventListener\('fullscreenchange', left\)/.test(screen), (screen.match(/\bgiveBack\(\)/g) ?? []).length],
    [true, true, true, 2])
  check('the page behind doesn\'t scroll while it shows - its own class on <html>, taken off as it goes',
    /useLayoutEffect\(\(\) => \{\s*const page = document\.documentElement\s*page\.classList\.add\(SCROLL_LOCK\)\s*return \(\) => page\.classList\.remove\(SCROLL_LOCK\)\s*\}, \[\]\)/.test(screen), true)
  //? the cover's colours and Halo's record stay until the next song's come: asked for only as their
  //? own address changes, nothing cleared before the answer
  check('the pictures asked for only as their own address changes, the last kept until the next has come',
    [/\}, \[coverAddress\]\)/.test(screen), /\}, \[discAddress\]\)/.test(screen), /track\?\.id\]/.test(screen),
      /const request = coverRequests\.begin\(\)\s*if \(!coverAddress/.test(screen), /if \(!art\) noDiscArt\.current\.add\(discAddress\)/.test(screen)],
    [true, true, false, true, true])
  check('...stopped, let go and its context closed as the screen goes',
    /useEffect\(\(\) => \(\) => \{\s*listener\.destroy\(\)\s*closeVisualizerAudio\(\)/.test(screen), true)
  check('its frame loop runs only while the page shows: hidden, it stops and the audio context is suspended',
    /if \(document\.visibilityState === 'hidden'\) \{\s*stop\(\)\s*suspendVisualizerAudio\(\)\s*\} else \{\s*resumeVisualizerAudio\(\)\s*start\(\)/.test(screen), true)
  check('...and the only frame loops in the app are the deck\'s and the visualizer\'s',
    files.filter((file) => APP_SIDE(file) && /requestAnimationFrame\(/.test(code(read(file)))).sort(), ['player/Visualizer.tsx', 'player/deck.ts'])
}

console.log('\nediting an album on a desktop: the Edit panel, a side panel by the same rule (2.0.0-player.21)')
{
  const app = code(read('app/App.tsx'))
  const panel = code(read('app/EditPanel.tsx'))
  const page = code(read('player/AlbumPage.tsx'))
  //? (2.0.0-player.47: drawn on both frames - a phone's sheet, as the artist page's panel is)
  check('drawn after Info, on both frames - a side panel on a desktop, a sheet over the whole screen on a phone',
    [/\n\s*<EditPanel open=\{editOpen\} request=\{edit\} opener=\{editOpener\} onClose=\{closeEdit\} onChanged=\{albumChanged\} panel=\{panel\} covered=\{visualizerShown\} \/>\n/.test(app),
      /desktop && <EditPanel\b/.test(app), app.indexOf('<EditPanel') > app.indexOf('<InfoSheet'), files.filter((file) => file !== 'app/App.tsx' && /<EditPanel\b/.test(code(read(file))))],
    [true, false, true, []])
  //? (2.0.0-player.47: an admin's on both frames - after Play and Shuffle on a desktop, in the bar beside the pin on a phone)
  check('Edit is on the album page for an admin, on both frames, and drawn only when handed - where the frame says',
    [/onEdit=\{admin \? toggleEdit : undefined\}/.test(app), /editAt=\{desktop \? 'actions' : 'bar'\}/.test(app),
      /\{onEdit && editAt === 'actions' && \(\s*<button\b[^>]*class="pl-pill app-edit-toggle"\s*aria-pressed=\{editing\}/.test(page),
      /editing=\{editOpen && edit\?\.album\?\.id === page\.id\}/.test(app)],
    [true, true, true, true])
  //? a phone's Edit: in the bar, after the back link and before the pin - above the title, so nothing under
  //? it moves as it comes or goes (the spec) - with the toggle's class and state, so App's focus re-point
  //? after a move (`.app-edit-toggle[aria-pressed="true"]`) finds it there too
  const bar = /<header class="pl-nav-bar app-album-bar">([\s\S]*?)<\/header>/.exec(page)?.[1] ?? ''
  check('...a phone\'s in the album page\'s bar: after the back link, before the pin, the toggle\'s class and pressed state, live once the album answers',
    [/\{onEdit && editAt === 'bar' && \(\s*<button\b[^>]*class="app-edit-toggle app-edit-chip"\s*aria-pressed=\{editing\}\s*disabled=\{!album\}/.test(bar),
      bar.indexOf('pl-back') < bar.indexOf('app-edit-chip') && bar.indexOf('app-edit-chip') < bar.indexOf('<PinToggle'),
      /if \(album\) onEdit\(event as unknown as MouseEvent, editAlbum\(album\)\)/.test(bar), (page.match(/class="[^"]*app-edit-toggle/g) ?? []).length],
    [true, true, true, 2])
  const toggle = /const toggleEdit = useCallback\(\(event: MouseEvent, album: EditAlbum\) => \{([\s\S]*?)\n  \}, \[\]\)/.exec(app)?.[1] ?? ''
  check('Edit opens it - a new request each press - putting Sources and Info away; pressed again on its album, closes it',
    [/if \(editOpenNow\.current && editNow\.current\?\.album\?\.id === album\.id\) \{\s*setEditOpen\(false\)\s*return\s*\}/.test(toggle),
      /editOpener\.current = takeOpener\(event\)\s*editKeys\.current \+= 1\s*setEdit\(\{ album, key: editKeys\.current \}\)\s*setEditOpen\(true\)/.test(toggle),
      /sourcesOpener\.current = null\s*setSourcesOpen\(false\)\s*infoOpener\.current = null\s*setInfoPanel\(false\)/.test(toggle)],
    [true, true, true])
  //? (2.0.0-player.47: crossing leaves it open - a panel one side, a sheet the other, as the artist page's)
  check('crossing 1024px leaves it open, either way; its page stopping being the one showing closes it',
    [!/closes\.editPanel/.test(app),
      /const editShown = edit !== null && \(isFolderRequest\(edit\) \? topNow\?\.kind === 'queue' : topNow\?\.kind === 'album' && topNow\.id === edit\.album\.id\)/.test(app),
      /if \(!editOpen \|\| editShown\) return\s*editOpener\.current = null\s*setEditOpen\(false\)/.test(app)],
    [true, true, true])
  //? (2.0.0-player.47: modal as a phone's sheet - its scroll lock, every Escape its own, a box with no tabindex)
  check('one hook: a side panel on a desktop (Escape from inside it), a modal sheet on a phone; focus in to its close and back to Edit',
    [/const modal = panelIsModal\(panel\)/.test(panel), /useSheet\(\{ open, covered: inner \|\| covered, onClose, lockClass: 'app-edit-open', first: closeButton, opener, modal, area: box \}\)/.test(panel),
      /<button ref=\{closeButton\} type="button" class="app-edit-close"/.test(panel),
      /<div ref=\{box\} class="app-edit" role="dialog" aria-modal=\{modal \? 'true' : 'false'\} aria-labelledby="app-edit-title" tabIndex=\{modal \? undefined : -1\}>/.test(panel),
      /class=\{`app-layer app-edit-layer\$\{open \? ' is-open' : ''\}\$\{modal \? ' is-sheet' : ` is-panel is-\$\{panel\}`\}`\}/.test(panel)],
    [true, true, true, true, true])
  //? (review) the direction pinned, and each handler's guard - not only that they exist
  check('an editor\'s own Escape (they listen on the document) passed over when it came from the page beside',
    [/document\.addEventListener\('keydown', onKeyDown, true\)/.test(panel), /at !== null && at\.event\.eventPhase !== 0 \? at\.from : null/.test(panel),
      //? (2.0.0-player.47: a sheet has no page beside it - an Escape from outside its box is its own)
      /const from = !modal\.current && !box\.current\?\.contains\(event\.target as Node \| null\) \? 'page' : inner\.current \? 'inner' : 'panel'/.test(panel),
      ['onClose={closeFromEditor}', 'onClose={closeTagEditor}', 'onCancel={cancelDelete}'].map((prop) => panel.includes(prop)),
      /const closeFromEditor = useMemo\(\(\) => \(\) => \{\s*const from = escapeFrom\(\)\s*if \(from !== 'page' && from !== 'inner'\) close\.current\(\)/.test(panel),
      /const closeTagEditor = useMemo\(\(\) => \(\) => \{\s*if \(escapeFrom\(\) === 'page'\) return\s*setEditingTags\(null\)/.test(panel),
      /const cancelDelete = useMemo\(\(\) => \(\) => \{\s*if \(escapeFrom\(\) === 'page'\) return\s*setTab\('release'\)/.test(panel)],
    [true, true, true, [true, true, true], true, true, true])
  //? (2.0.0-player.44: the track inspector is a layer over the Tags tab too - below, "inside a track")
  check('(review) an Escape in the tag editor or the delete confirmation closes that layer alone: the panel covered under it, the release editor\'s close passing it over',
    [/const tagEditorShown = drawn && editingTags !== null && editingTags\.path === subject!\.path\n/.test(panel),
      /const inner = drawn && \(\(tab === 'tags' && \(tagEditorShown \|\| inspected !== null\)\) \|\| tab === 'delete'\)/.test(panel),
      /innerNow\.current = inner/.test(panel), /const escapeFrom = useEscapeFrom\(box, innerNow, modalNow\)/.test(panel) && /modalNow\.current = modal\n/.test(panel)],
    [true, true, true, true])
  check('(review) the editors let go once the panel has closed - at once as a column, once a drawer or a phone\'s sheet has slid away - so no cover viewer outlives it',
    [/if \(open\) \{\s*setLetGo\(false\)\s*return\s*\}\s*const timer = setTimeout\(\(\) => setLetGo\(true\), panel === 'column' \? 0 : EDIT_SLIDE_MS\)/.test(panel),
      /const drawn = !!subject && !!request && !deleted && !letGo/.test(panel), /\{drawn && subject && request && \(/.test(panel),
      (panel.match(/<MetadataEditor\b/g) ?? []).length],
    [true, true, true, 1])
  check('(review) a control that removes itself hands focus on inside the panel, never to the page',
    [/useLayoutEffect\(\(\) => \{\s*const pick = focusNext\.current\s*if \(!pick\) return\s*focusNext\.current = null\s*const active = document\.activeElement\s*if \(active && active !== document\.body\) return\s*pick\(\)\?\.focus\(\{ preventScroll: true \}\)/.test(panel),
      //? (2.0.0-player.44: back to the track inspector's "Edit this track…" when it was opened from there)
      /setEditingTags\(null\)\s*const opener = \(\) => tagsPane\.current\?\.querySelector<HTMLElement>\('\.app-inspect-edit'\)\s*\?\? tagsPane\.current\?\.querySelector<HTMLElement>\('\.app-edit-tags-open'\)\s*focusNext\.current = opener\n/.test(panel),
      /setTab\('release'\)\s*focusNext\.current = toTab\('release'\)/.test(panel),
      /setEditingTags\(\{ path, filenames \}\)\s*focusNext\.current = /.test(panel),
      /void library\.reload\(false\)\s*focusNext\.current = \(\) => scroller\.current/.test(panel),
      /chooseFolder\(path\)\s*focusNext\.current = toTab\(tab\)/.test(panel),
      /editOpener\.current = document\.querySelector<HTMLElement>\(`\.app-pane\[data-tab="\$\{nav\.tab\}"\] \.app-edit-toggle\[aria-pressed="true"\]`\)/.test(app)],
    [true, true, true, true, true, true, true])
  check('the main page\'s editors, reused - not rewritten, nor copied',
    ['MetadataEditor', 'TrackTagEditor', 'DeleteAlbumDialog', 'LibraryParts'].map((name) => new RegExp(`from '\\.\\./components/${name}'`).test(panel)),
    [true, true, true, true])
  check('what it asks goes through latestOnly(): the album\'s folders, and what follows a write',
    [/const lookups = useMemo\(latestOnly, \[\]\)/.test(panel), /const ticket = lookups\.begin\(\)/.test(panel),
      /const afterWrites = useMemo\(latestOnly, \[\]\)/.test(panel), /const ticket = afterWrites\.begin\(\)/.test(panel)],
    [true, true, true, true])
  const writeBody = /const afterWrite = \(at: EditRequest, release: string \| null, lookFor: string \| null\) => \{([\s\S]*?)\n  \}\n/.exec(panel)?.[1] ?? ''
  const lookBody = /const lookForMove = \(from: string, release: string\) => \{([\s\S]*?)\n  \}\n/.exec(panel)?.[1] ?? ''
  check('(review) the look for the album\'s new id has a latestOnly of its own: a write after the apply (CD art, a hand edit) never calls it off',
    [/const follows = useMemo\(latestOnly, \[\]\)/.test(panel), /const ticket = follows\.begin\(\)/.test(lookBody), /afterWrites/.test(lookBody),
      /if \(lookFor\) lookForMove\(idOf\(at\), lookFor\)/.test(writeBody), /follows\.begin|FOLLOW_LOOKS_MS/.test(writeBody),
      /follows\.supersede\(\)/.test(panel), /for \(const delay of FOLLOW_LOOKS_MS\)/.test(lookBody)],
    [true, true, false, true, false, true, true])
  check('(verified in the page) the page\'s own id found is no answer: the look goes on until Navidrome has scanned the rename',
    [/const to = followsTo\(from, found\.navidrome_id\)\s*if \(!to\) continue\s*changed\.current\(\{ kind: 'moved', id: from, to \}\)\s*return/.test(lookBody)],
    [true])
  check('(review) each Edit after the first reads the library again underneath, the album followed to the fresh read - unless a write was made meanwhile',
    [/lookUp\(request\)\s*if \(!library\.loaded \|\| library\.loading\) return/.test(panel),
      /void library\.reload\(false\)\.then\(\(fresh\) => \{\s*if \(!fresh\.length \|\| lookedUp\.current !== key \|\| writes\.current !== since\) return\s*setSubject\(\(current\) => \(current \? fresh\.find\(\(album\) => album\.path === current\.path\) \?\? null : current\)\)/.test(panel),
      /\}, \[folders, subject\]\)/.test(panel), /const asked = request !== null && askedFor === request\.key/.test(panel)],
    [true, true, true, true])
  //? (review) the state rules the panel restates from the main page, each one pinned
  check('(review) the release editor keyed on the session (never per apply); several by name a choice; the album only from a REAL scan; the library read only once the panel opens; the files only for Tags',
    [/<MetadataEditor\s+key=\{session\}/.test(panel), /if \(subject \|\| deleted \|\| !folders \|\| !folders\.paths\.length \|\| needsChoice\(folders\)\) return/.test(panel),
      /const libraryReady = library\.loaded && !library\.stale/.test(panel), /const library = useLibrary\(open\)/.test(panel),
      /useTrackDetails\(subject && tagsSeen \? subject\.path : null, library\.albums\)/.test(panel),
      /editStatus\(\{[\s\S]*?holding: !!subject,/.test(panel)],
    [true, true, true, true, true, true])
  check('the album held, and followed from what a reload resolves with - only while it is still the one shown',
    [/const \[subject, setSubject\] = useState<LibraryAlbum \| null>\(null\)/.test(panel),
      /setSubject\(\(current\) => \(current && current\.path === oldPath \? updated : current\)\)/.test(panel),
      /const fresh = await library\.reload\(false\)\s*const updated = follow\(fresh, album\.path, newPath\)/.test(panel)],
    [true, true, true])
  const changed = /const albumChanged = useCallback\(\(change: AlbumChange\) => \{([\s\S]*?)\n  \}, \[\]\)/.exec(app)?.[1] ?? ''
  check('a page an apply gave a new id becomes it through the router, only while it shows; a write tells the library\'s listeners',
    [/if \(!showing\) return[\s\S]*?router\.become\(\{ kind: 'album', id: change\.id \}, \{ kind: 'album', id: change\.to/.test(changed),
      /if \(change\.kind === 'written'\) announceAlbumsFiled\(\)/.test(changed), /else if \(showing\) router\.back\(\)/.test(changed)],
    [true, true, true])
  //? (review) what albumChanged does to the page and the panel, each pinned
  check('(review) a move: remembered, the panel following it; a write and its settle ask the page again (by its id now); a delete closes the panel',
    [/noteMove\(moves\.current, change\.id, change\.to\)/.test(changed),
      /if \(at && !isFolderRequest\(at\) && at\.album\.id === change\.id\) setEdit\(\{ \.\.\.at, album: \{ \.\.\.at\.album, id: change\.to \} \}\)/.test(changed),
      /const now = movedTo\(moves\.current, id\) \?\? id\s*setRefreshes\(\(was\) => new Map\(was\)\.set\(now, \(was\.get\(now\) \?\? 0\) \+ 1\)\)/.test(changed),
      /if \(change\.kind === 'written' \|\| change\.kind === 'settled'\) \{\s*if \(change\.kind === 'written'\) announceAlbumsFiled\(\)\s*ask\(change\.id\)\s*return/.test(changed),
      /if \(editNow\.current\?\.album\?\.id === change\.id\) \{\s*if \(change\.last\) editOpener\.current = null\s*setEditOpen\(false\)\s*\}\s*if \(!change\.last\) ask\(change\.id\)/.test(changed)],
    [true, true, true, true, true])
  check('(review) a page of an album that moved, back on top (back, forward, its tab chosen), becomes the album\'s page as it is now',
    [/useEffect\(\(\) => \{\s*if \(topNow\?\.kind !== 'album'\) return\s*const to = movedTo\(moves\.current, topNow\.id\)\s*if \(!to\) return[\s\S]*?router\.become\(topNow, \{ kind: 'album', id: to,[\s\S]*?\}, \[nav\]\)/.test(app)],
    [true])
  check('(review) a delete: Navidrome left with nothing of the album by `deletesAll`; one folder of several asked again once Navidrome has scanned',
    [/onDeleted=\{albumDeleted\(request, subject, deletesAll\(folders, subject\.track_count, request\.album\)\)\}/.test(panel),
      /changed\.current\(\{ kind: 'deleted', id: idOf\(at\), last \}\)\s*if \(!last\) settleLater\(at\)/.test(panel),
      /const settleLater = \(at: EditRequest\) => \{\s*const ticket = afterWrites\.begin\(\)\s*void wait\(EDIT_SETTLE_MS, ticket\.signal\)\.then\(\(\) => \{\s*if \(ticket\.current\(\)\) changed\.current\(\{ kind: 'settled', id: idOf\(at\) \}\)/.test(panel)],
    [true, true, true])
  check('...and it calls no playback action, nor reads a context', [actionsIn(panel), /useContext|PlayerContext|ActionsContext/.test(panel)], [[], false])
  check('the page is followed only after an apply changed the release; tags, art and lyrics keep the id - and each write carries the Edit it was made under',
    [/afterWrite\(at, release, followRelease\(album\.release_mbid, release\)\)/.test(panel),
      /const wrote = \(at: EditRequest, album: LibraryAlbum\) => async \(\) => \{\s*writes\.current \+= 1\s*follow\(await library\.reload\(false\), album\.path\)\s*afterWrite\(at, album\.release_mbid \|\| null, null\)/.test(panel)],
    [true, true])
  check('the folder is asked for as the panel opens on a new Edit - never for a request kept from before; the delete confirmation drawn only while its tab shows',
    [/if \(!open \|\| !request \|\| lookedUp\.current === request\.key\) return/.test(panel), /\{tab === 'delete' && \(\s*<DeleteAlbumDialog\b/.test(panel)],
    [true, true])
  check('an edit asks the album page again - afresh, keeping what it drew, a failed refresh silent - per album',
    [/\}, \[id, refresh, requests\]\)/.test(page), /\}, \[id, refresh, storeRequests\]\)/.test(page),
      /if \(!again\) \{\s*setAlbum\(null\)\s*setError\(null\)\s*\}/.test(page), /if \(!request\.current\(\) \|\| isAbort\(reason\) \|\| again\) return/.test(page),
      /refresh=\{refreshes\.get\(page\.id\) \?\? 0\}/.test(app),
      /const answer = again \? prefetchAlbum\(id, false, true\)\.then\(\(\) => fetchAlbum\(id, request\.signal\)\) : fetchAlbum\(id, request\.signal\)/.test(page)],
    [true, true, true, true, true, true])
}

console.log('\nNeeds a look: the review queue in the app, on a desktop (2.0.0-player.25)')
{
  const app = code(read('app/App.tsx'))
  const page = code(read('app/NeedsALook.tsx'))
  const store = code(read('app/useQueueSummary.ts'))
  const side = code(read('app/Sidebar.tsx'))
  const you = code(read('app/You.tsx'))
  const panel = code(read('app/EditPanel.tsx'))
  check('no playback action from any of its files, nor a context',
    ['app/NeedsALook.tsx', 'app/useQueueSummary.ts', 'lib/needsLook.ts'].map((file) => [actionsIn(code(read(file))), /useContext|PlayerContext|ActionsContext/.test(code(read(file)))]),
    [[[], false], [[], false], [[], false]])
  //? (2.0.0-player.47: told `admin`, never the frame - a phone draws the page as a desktop does)
  check('the page reads the library through the main page\'s hook, only once it shows, for the admin - and nothing else of it',
    [/const library = useLibrary\(admin && shown\)/.test(page), (page.match(/useLibrary\(/g) ?? []).length, /listAlbums|loadScan|queueSummary\(/.test(page), /\bdesktop\b/.test(page.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, ''))],
    [true, 1, false, false])
  check('...anyone else a note and nothing more: its return comes before any row is drawn',
    [/if \(!admin\) \{\s*return \(/.test(page), page.indexOf('if (!admin)') < page.indexOf('app-queue-list')], [true, true])
  check('the list is queueAlbums, through lib/needsLook.ts, and its session the pure rules\'',
    [/from '\.\.\/lib\/needsLook'/.test(page), /export function facetAlbums[\s\S]*?queueAlbums\(albums, facet\)/.test(code(read('lib/needsLook.ts'))),
      /const begun = startSession\(albums, path, showing\)/.test(page), /const target = stepTarget\(was, index,/.test(page)],
    [true, true, true, true])
  check('stepping away marks the album left reviewed, and asks the count again - the only markReviewed in the app',
    [/const review = \(path: string \| null\): Promise<void> =>\s*path \? libraryApi\.markReviewed\(path\)\.then\(\(\) => askQueueSummary\(\), \(\) => undefined\) : Promise\.resolve\(\)/.test(page),
      /const marked = review\(target\.leaving\)\s*if \(target\.kind === 'end'\) \{\s*end\(false, marked\)/.test(page),
      files.filter((file) => APP_SIDE(file) && /markReviewed\(/.test(code(read(file))))],
    [true, true, ['app/NeedsALook.tsx']])
  check('the panel closing ends the session; so does the page going',
    [/if \(editing !== null\) \{\s*opened\.current = true\s*return\s*\}\s*if \(opened\.current\) end\(true\)/.test(page),
      /useEffect\(\(\) => \(\) => \{\s*const was = sessionNow\.current\s*if \(was\) \{\s*const path = leavingAtEnd\(was\)\s*if \(path\) review\(path\)/.test(page)],
    [true, true])
  check('the count: one store - asked as the desktop frame shows for an admin and the page comes back, after every change the panel reports, by the page\'s reviews and on a filed album; no timer',
    //? (2.0.0-player.47: and on a phone as You's tab shows, where its row draws it - by ONE flag, true on a
    //? desktop all along, so a desktop moving to and from You asks nothing more: review)
    [/const asksQueueSummary = desktop \|\| nav\.tab === 'you'\s*useEffect\(\(\) => \{\s*if \(asksQueueSummary && admin && pageShown\) askQueueSummary\(\)\s*\}, \[asksQueueSummary, admin, pageShown\]\)/.test(app),
      /const albumChanged = useCallback\(\(change: AlbumChange\) => \{\s*\/\/[^\n]*\n\s*askQueueSummary\(\)/.test(read('app/App.tsx')),
      /onAlbumsFiled\(\(\) => askQueueSummary\(\)\)/.test(store), /if \(asking\) again = true\s*else ask\(\)/.test(store),
      files.filter((file) => APP_SIDE(file) && /askQueueSummary\(|\(askQueueSummary\)/.test(code(read(file)))).sort(),
      /setTimeout|setInterval/.test(store), (app.match(/useQueueSummary\(\)/g) ?? []).length],
    [true, true, true, true, ['app/App.tsx', 'app/NeedsALook.tsx', 'app/useQueueSummary.ts'], false, 1])
  check('...the page\'s own count standing in only while it shows with a real scan and no session',
    [/setPageQueueCount\(admin && shown && real && !session && !ending \? summaryTotal\(library\.albums\) : null\)/.test(page), /return page \?\? server/.test(store)],
    [true, true])
  check('the sidebar\'s item: Managing\'s first, an admin\'s, with the count',
    [/\{admin && \(\s*<section class="app-side-group" aria-labelledby="app-side-managing">[\s\S]*?<ul class="app-side-list">\s*\{item\(SIDEBAR_QUEUE\)\}/.test(side),
      /<Sidebar\b[\s\S]*?needsLook=\{needsLook\}/.test(app), /sidebarCurrent\(nav\.tab, libraryView, hasSongs, topNow, hasLibrary\(\)\)/.test(app)],
    [true, true, true])
  //? (2.0.0-player.47: on both frames - You is told no frame at all now)
  check('You\'s row: in Managing (an admin\'s), above the link to the main page - on a phone as on a desktop',
    [/<div class="app-group">\s*<button\b[^>]*class="app-row app-link-row app-queue-link-row"/.test(you), you.indexOf('app-queue-link-row') < you.indexOf('Open the main page'),
      /\{admin && \([\s\S]*?app-queue-link-row/.test(you), /onWindDown=\{chooseWindDown\}\s*needsLook=\{needsLook\}\s*onNeedsLook=\{openQueue\}/.test(app), /\bdesktop\b/.test(you.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, ''))],
    [true, true, true, true, false])
  //? (2.0.0-player.33: through openManagingPage, which also replaces another Managing page on top)
  check('its page opened on You - the tab as left, the page pushed only when it isn\'t on top there',
    [/const openQueue = useCallback\(\(\) => openManagingPage\(QUEUE_PAGE\), \[\]\)/.test(app)
      && /const top = stack\[stack\.length - 1\] \?\? null\s*if \(router\.nav\.tab !== 'you'\) router\.tab\('you'\)\s*if \(top\?\.kind === page\.kind\) return/.test(app),
      /if \(move\.how === 'queue'\) \{\s*openQueue\(\)/.test(app)],
    [true, true])
  check('a row opens the Edit panel on its folder by the one-panel rule - Sources and Info put away',
    [/const openFolderEdit = useCallback\([\s\S]*?setEdit\(\{ \.\.\.request, key: editKeys\.current \}\)\s*setEditOpen\(true\)\s*sourcesOpener\.current = null\s*setSourcesOpen\(false\)\s*infoOpener\.current = null\s*setInfoPanel\(false\)/.test(app),
      /onEdit=\{openFolderEdit\}/.test(app), /editing=\{editOpen && isFolderRequest\(edit\) \? edit\.folder : null\}/.test(app)],
    [true, true, true])
  check('...the panel: no bridge for a folder (an earlier lookup still out superseded), the library read again only for a session\'s first album, the release editor given the queue',
    [/if \(isFolderRequest\(at\)\) \{\s*(?:\/\/[^\n]*\n\s*)?lookups\.supersede\(\)\s*setAnswer\(null\)\s*setAskedFor\(at\.key\)\s*return\s*\}/.test(panel), /if \(isFolderRequest\(request\) && !request\.reread\) return/.test(panel),
      /isFolderRequest\(request\) \? folderOnly\(request\.folder\)/.test(panel), /queue=\{queue\}/.test(panel)],
    [true, true, true, true])
  check('...and what became of the album told to the page that opened it and to App, by path - never an album page\'s id',
    [/at\.onChange\?\.\(\{ from, album, deleted, wrote \}\)\s*changed\.current\(\{ kind: 'folder', from, path:/.test(panel),
      /if \(isFolderRequest\(at\)\) \{\s*toFolder\(at, album\.path, updated, true\)\s*return\s*\}/.test(panel),
      /if \(isFolderRequest\(at\)\) \{\s*toFolder\(at, album\.path, null, true, true\)\s*return\s*\}/.test(panel),
      /if \(change\.kind === 'folder'\) \{\s*if \(change\.wrote\) announceAlbumsFiled\(\)\s*return\s*\}/.test(app)],
    [true, true, true, true])
  check('after review: the ending\'s scan asked only once the note is written; the list worked out again only with no read still out',
    [/void noted\s*\.then\(\(\) => libraryNow\.current\.reload\(false\)\)\s*\.then\(\(\) => setEnding\(/.test(page),
      /if \(ending\?\.read && !library\.loading\) \{\s*setEnding\(null\)\s*setHeldChips\(null\)/.test(page)],
    [true, true])
  check('...focus kept in the page: a Try again that worked, a row the ended session was on gone from the list - only when focus fell to the page',
    [/if \(retrying\.current && !library\.loading\) \{\s*retrying\.current = false\s*if \(focusLost\(\)\) body\.current\?\.focus/.test(page),
      /if \(endedAt\.current !== null && !session && !ending\) \{[\s\S]*?if \(focusLost\(\)\) \{[\s\S]*?buttons\[Math\.min\(at, buttons\.length - 1\)\] : body\.current\s*target\?\.focus\(\{ preventScroll: true \}\)/.test(page),
      /endedAt\.current = was\.index/.test(page), /<div ref=\{body\} class="app-queue-body" tabIndex=\{-1\}>/.test(page),
      /\sdisabled=\{/.test(page), (page.match(/aria-disabled=\{library\.loading \? 'true' : undefined\} onClick=\{retry\}/g) ?? []).length,
      /const retry = \(\) => \{\s*if \(library\.loading\) return\s*retrying\.current = true/.test(page)],
    [true, true, true, true, false, 2, true])
  check('...the panel: a step through the queue hands focus on to the Release tab, never the page; listing the folder, it says it is finding it',
    [/if \(isFolderRequest\(request\)\) \{\s*const active = document\.activeElement\s*if \(!active \|\| active === document\.body \|\| box\.current\?\.contains\(active\)\) focusNext\.current = toTab\('release'\)/.test(panel),
      panel.indexOf("focusNext.current = toTab('release')") < panel.indexOf('setSubject(null)\n'),
      /listed: !!folders && folders\.paths\.length === 1 && library\.albums\.some\(\(album\) => album\.path === folders\.paths\[0\]\)/.test(panel)],
    [true, true, true])
  check('...and every way the panel reports on a folder: an ignore and an un-ignore told (no file written), tags/art/lyrics through wroteFolder, Next album after a delete',
    [(panel.match(/const updated = follow\(await library\.reload\(false\), album\.path\)\s*if \(isFolderRequest\(at\)\) toFolder\(at, album\.path, updated, false\)/g) ?? []).length,
      /const ignoreAlbum = async[\s\S]*?toFolder\(at, album\.path, updated, false\)[\s\S]*?const unignoreAlbum = async[\s\S]*?toFolder\(at, album\.path, updated, false\)/.test(panel),
      /const written = \(at: EditRequest \| FolderRequest, album: LibraryAlbum\) =>\s*isFolderRequest\(at\) \? wroteFolder\(at, album\) : wrote\(at, album\)/.test(panel),
      /const wroteFolder = \(at: FolderRequest, album: LibraryAlbum\) => async \(\) => \{\s*writes\.current \+= 1\s*const updated = follow\(await library\.reload\(false\), album\.path\)\s*toFolder\(at, album\.path, updated, true\)/.test(panel),
      /\{deleted && queue && queue\.position < queue\.total && \(\s*<button type="button" class="app-edit-button" onClick=\{queue\.onNext\}>\s*Next album ▷/.test(panel),
      (panel.match(/onApplied=\{written\(request, subject\)\}|onDone=\{written\(request, subject\)\}/g) ?? []).length],
    [2, true, true, true, true, 3])
  check('the pages memo is keyed on what the queue page reads (admin, the page shown, the panel and its request)',
    [/\[nav, status, playingId, player\.playing, sourcesOpen, pageShown, desktop, sourcesGroup, sourcesPressing, admin, editOpen, edit, refreshes, visualizerShown, sheetOpen, artistOpen, artistManage, artistRefreshes\]/.test(app),
      /page\.kind === 'queue' \? queueView\(tab, page\)/.test(app)],
    [true, true])
}

console.log('\nApp moves history only through the router')
{
  const app = code(read('app/App.tsx'))
  check('no pushState, replaceState or go() of its own', [/pushState/.test(app), /replaceState/.test(app), /history\.go\(/.test(app)], [false, false, false])
  check('popstate and hashchange both go to router.moved()',
    [/const onMove = \(\) => router\.moved\(\)/.test(app), /addEventListener\('popstate', onMove\)/.test(app), /addEventListener\('hashchange', onMove\)/.test(app)], [true, true, true])
}

console.log('\nthe page renders the app')
{
  const main = code(read('player/main.tsx'))
  check('player/main.tsx renders <App /> from app/App', [/from '\.\.\/app\/App'/.test(main), /render\(<App \/>/.test(main)], [true, true])
  check('the old shell and settings sheet are gone',
    ['player/PlayerApp.tsx', 'player/Settings.tsx'].filter((file) => fs.existsSync(path.join(SRC, file))), [])
}

console.log('\nServer settings and the log in the app, on a desktop (2.0.0-player.33)')
{
  const settings = code(read('app/ServerSettings.tsx'))
  const log = code(read('app/EventLog.tsx'))
  const app = code(read('app/App.tsx'))
  const sidebar = code(read('app/Sidebar.tsx'))
  const you = code(read('app/You.tsx'))
  check('no playback action from either page', [actionsIn(settings), actionsIn(log)], [[], []])
  //? a held stream is one of the six connections a browser allows the host - the player's audio uses them too
  const opening = files.filter((file) => /\bnew EventSource\b/.test(code(read(file))))
  check('the log is the one file in the app that opens a stream', opening, ['app/EventLog.tsx'])
  check('...in an effect that opens nothing unless the page is what shows, keyed on exactly that, and closes it as that stops',
    //? (2.0.0-player.47: an admin's, on either frame)
    [/useEffect\(\(\) => \{\s*if \(!admin \|\| !live\) return\b[\s\S]*?new EventSource\([\s\S]*?return \(\) => \{\s*closed = true\s*reads\.supersede\(\)\s*source\?\.close\(\)[\s\S]*?\}, \[admin, live\]\)/.test(log),
      (log.match(/new EventSource\(/g) ?? []).length],
    [true, 1])
  check('...a history answering after it stopped showing opens nothing (`closed` asked first)',
    [/recentLog\(ticket\.signal\)\.then\(\s*\(recent\) => \{\s*if \(!ticket\.current\(\) \|\| closed\) return/.test(log)], [true])
  //? (2.0.0-player.47: an admin's on both frames - and a phone's Now Playing over the page is as the visualizer)
  check('App\'s `live`: the page\'s tab current, the app in front, neither the visualizer nor a phone\'s Now Playing over it; both an admin\'s, on either frame',
    [/const managingLive = \(tab: Tab\) => pageShown && nav\.tab === tab && !visualizerShown && !sheetOpen\n/.test(app),
      /<ServerSettings admin=\{admin\} live=\{managingLive\(tab\)\}/.test(app),
      /<EventLog admin=\{admin\} live=\{managingLive\(tab\)\}/.test(app)],
    [true, true, true])
  check('the log\'s lines and the settings\' rows are text: nothing set as HTML in either',
    [/dangerouslySetInnerHTML|innerHTML|insertAdjacentHTML/.test(log), /dangerouslySetInnerHTML|innerHTML|insertAdjacentHTML/.test(settings),
      /<span class="app-log-words">\{line\.event_content\}<\/span>/.test(log)],
    [false, false, true])
  check('the settings read through latestOnly, never over a draft, and a save calls a read still out off',
    [/const ticket = reads\.begin\(\)\s*setLoading\(true\)\s*getServerSettings\(ticket\.signal\)/.test(settings),
      /if \(!admin \|\| !live \|\| Object\.keys\(kept\.drafts\)\.length\) return\s*read\(\)/.test(settings),
      /const save = async \(\) => \{[\s\S]*?reads\.supersede\(\)[\s\S]*?saveServerSettings\(/.test(settings)],
    [true, true, true])
  //? App draws only a tab's top page: a page left for a sibling, Back or Go to album goes - and with it any
  //? state of its own (review: the drafts the bar had counted, dropped without a word)
  check('what the pages hold outlives them: the drafts, the refusal, the tab and the lines kept in their modules, never component state',
    [/^let kept: PageState = freshPage\(\)$/m.test(settings), /const \{ server, drafts: draftEnv, tab, saving, saveError, justSaved \} = kept/.test(settings),
      /useState<Record<string, string \| null>>|useState<SettingsTab>|useState<Settings \| null>/.test(settings),
      /^let kept: LogState = emptyLog\(\)$/m.test(log), /const log = kept\b/.test(log), /useState<LogState>/.test(log)],
    [true, true, false, true, true, false])
  check('...drawn from the main page\'s settings tab\'s own parts, not copies',
    [/from '\.\.\/components\/SettingsView'/.test(settings), /<ServerGroup\b/.test(settings), /\bfunction SettingRow\b|settings-env-head/.test(settings)],
    [true, true, false])
  //? (2.0.0-player.42: Library care between Needs a look and them)
  check('the sidebar\'s Settings and Log: an admin\'s, after Needs a look and Library care, before the main page',
    [/\{admin && \([\s\S]*?\{item\(SIDEBAR_QUEUE\)\}\s*\{item\(SIDEBAR_CARE\)\}\s*\{item\(SIDEBAR_SETTINGS\)\}\s*\{item\(SIDEBAR_LOG\)\}\s*<li>\s*<a/.test(sidebar)], [true])
  check('You\'s rows: opening the pages through App - on a phone as on a desktop (2.0.0-player.47)',
    //? (2.0.0-player.42: and Library care's)
    [(you.match(/\n\s*<button type="button" class="app-row app-link-row app-queue-link-row" onClick=\{\(\) => onManaging\?\.\('(care|settings|log)'\)\}>/g) ?? []).length,
      /onManaging=\{openManaging\}/.test(app), /move\.how === 'managing'\) \{\s*openManaging\(move\.kind\)/.test(app)],
    [3, true, true])
  check('the Managing pages are siblings: each opened through one helper, one over another REPLACING it (never piled up)',
    [/const openQueue = useCallback\(\(\) => openManagingPage\(QUEUE_PAGE\), \[\]\)/.test(app),
      //? (2.0.0-player.42: Library care one of them)
      /const openManaging = useCallback\(\(kind: ManagingKind\) => openManagingPage\(kind === 'care' \? CARE_PAGE : kind === 'settings' \? SETTINGS_PAGE : LOG_PAGE\), \[\]\)/.test(app),
      /if \(top\?\.kind === page\.kind\) return[\s\S]{0,120}if \(top && MANAGING_KINDS\.includes\(top\.kind\)\) router\.become\(top, page\)\s*else router\.open\(page\)/.test(app),
      /const MANAGING_KINDS: readonly PageKind\[\] = \['queue', 'care', 'settings', 'log'\]/.test(app)],
    [true, true, true, true])
  check('the pages memo is keyed on what they read - the visualizer, and Now Playing, too',
    [/page\.kind === 'settings' \? settingsView\(tab\) : page\.kind === 'log' \? logView\(tab\)/.test(app), /refreshes, visualizerShown, sheetOpen, artistOpen, artistManage, artistRefreshes\]/.test(app)], [true, true])
}

console.log('\nthe artist page, as the main page had it (2.0.0-player.45)')
{
  const app = code(read('app/App.tsx'))
  const panel = code(read('app/ArtistPanel.tsx'))
  const page = code(read('app/ArtistPage.tsx'))
  check('the artist page\'s panel plays nothing and reads no player',
    [actionsIn(panel), /useContext|usePlayerActions|PlayerContext/.test(panel)], [[], false])
  check('it is the frame\'s side panel on a desktop and a sheet on a phone: modal only as a sheet, inert while closed or under the visualizer',
    [/const modal = panelIsModal\(panel\)/.test(panel), /useSheet\(\{ open, covered, onClose, lockClass: 'app-artist-panel-open', first: close, opener, modal, area: box \}\)/.test(panel),
      /aria-hidden=\{!open \|\| covered\} inert=\{!open \|\| covered\}/.test(panel), /<ArtistPanel\b[^\n]*\bcovered=\{visualizerShown\}[^\n]*\/>/.test(app),
      /<ArtistPanel\b[^\n]*\bpanel=\{panel\}[^\n]*\/>/.test(app)],
    [true, true, true, true, true])
  const toggle = /const toggleArtistManage = useCallback[\s\S]*?\}, \[\]\)/.exec(app)?.[0] ?? ''
  check('one panel at a time: it puts Sources, Info and Edit away - and Edit, on an album or a folder, puts it away',
    [/sourcesOpener\.current = null\s*setSourcesOpen\(false\)\s*infoOpener\.current = null\s*setInfoPanel\(false\)\s*editOpener\.current = null\s*setEditOpen\(false\)/.test(toggle),
      /setEdit\(\{ album, key: editKeys\.current \}\)[\s\S]{0,300}?artistOpener\.current = null\s*setArtistOpen\(false\)\s*\}, \[\]\)/.test(app),
      /setEdit\(\{ \.\.\.request, key: editKeys\.current \}\)[\s\S]{0,300}?artistOpener\.current = null\s*setArtistOpen\(false\)\s*\}, \[\]\)/.test(app)],
    [true, true, true])
  check('...pressed again for the job it shows on that page, it closes',
    /if \(artistOpenNow\.current && now\?\.page === request\.page && now\.mode === request\.mode\) \{\s*setArtistOpen\(false\)\s*return\s*\}/.test(toggle), true)
  check('it is the page\'s: it closes as that page stops being the one on top',
    [/const artistShown = artistManage !== null && nav\.tab === artistManage\.tab && topNow\?\.kind === 'artist' && topNow\.id === artistManage\.page/.test(app),
      /if \(!artistOpen \|\| artistShown\) return\s*artistOpener\.current = null\s*setArtistOpen\(false\)/.test(app)], [true, true])
  //? review: the same artist on top of two tabs - the panel stayed open over the other tab's copy, pressed
  //? there, while its answers went to the hidden one
  check('...the page on the tab it was opened on: the request keeps its tab, the panel closes on another, and only that tab\'s copy shows it pressed',
    [/setArtistManage\(\{ \.\.\.request, key: artistKeys\.current, tab: router\.nav\.tab \}\)/.test(toggle),
      /managing=\{artistOpen && artistManage\?\.tab === tab && artistManage\.page === page\.id \? artistManage\.mode : null\}/.test(app)], [true, true])
  //? (2.0.0-player.47: and so does the Edit panel - crossing closes only Now Playing and Info now)
  check('...and it stays open across 1024px - a panel one side, a sheet the other (crossing closes only Now Playing and Info)',
    [/if \(closes\.infoPanel\) \{\s*infoOpener\.current = null\s*setInfoPanel\(false\)/.test(app), /closes\.\w+\) \{[^}]*setArtistOpen/.test(app), /closes\.\w+\) \{[^}]*setEditOpen/.test(app)], [true, false, false])
  //? review: the conditions were unpinned - the guard could go and the page never follow, or follow from any page
  const moved = /const artistMoved = useCallback[\s\S]*?\}, \[\]\)/.exec(app)?.[0] ?? ''
  check('albums moved: the library told; the page follows by the artist\'s MusicBrainz id only when it said to (its name has no album left) and that id is another',
    [/^const artistMoved = useCallback\(\(from: string, to: \{ mbid: string; name: string \}, follow: boolean\) => \{\s*announceAlbumsFiled\(\)/.test(moved),
      /const id = artistPageId\(\{ mbid: to\.mbid \}\)\s*if \(!follow \|\| !id \|\| id === from\) return\s*[\s\S]*?artistMoves\.current\.set\(from, id\)/.test(moved),
      /setArtistManage\(\(was\) => \(was && was\.page === from \? \{ \.\.\.was, page: id \} : was\)\)/.test(moved),
      /if \(top\?\.kind === 'artist' && top\.id === from\) \{[\s\S]*?router\.become\(top, \{ kind: 'artist', id, label: to\.name \}\)\s*\}\s*\}, \[\]\)$/.test(moved),
      /onMoved=\{artistMoved\}/.test(app)],
    [true, true, true, true, true])
  check('...the page it became has its scroll put back once it has drawn (App\'s first try lands on a page with nothing drawn), only while still showing - and on that page\'s own word',
    [/const key = scrollKey\(\{ tab: router\.nav\.tab, page: \{ kind: 'artist', id \} \}\)\s*scrolls\.current\.set\(key, window\.scrollY\)\s*artistScroll\.current = \{ key, y: window\.scrollY \}\s*router\.become/.test(moved),
      /const artistDrawn = useCallback\(\(drawn: string, all: boolean\) => \{\s*const want = artistScroll\.current\s*if \(!want \|\| drawn !== want\.key\) return\s*if \(want\.key !== scrollKey\(currentRoute\(router\.nav\)\)\) \{\s*artistScroll\.current = null\s*return\s*\}\s*if \(window\.scrollY < want\.y\) window\.scrollTo\(0, want\.y\)\s*if \(all \|\| window\.scrollY >= want\.y\) artistScroll\.current = null/.test(app),
      //? review: on the page's own word - its route, which App knows - so a hidden tab's artist page drawing can't use it up
      /onDrawn=\{\(all\) => artistDrawn\(scrollKey\(\{ tab, page \}\), all\)\}/.test(app), /useLayoutEffect\(\(\) => \{\s*if \(drawRows\) onDrawn\?\.\(drawAbout\)\s*\}, \[drawRows, drawAbout\]\)/.test(page)],
    [true, true, true, true])
  check('...a page of the old id back on top becomes the new one - and the panel\'s focus goes back to the page it became\'s back link',
    [/useEffect\(\(\) => \{\s*if \(topNow\?\.kind !== 'artist'\) return\s*const to = artistMoves\.current\.get\(topNow\.id\)\s*if \(to\) router\.become\(topNow, \{ kind: 'artist', id: to, [^\n]*\}\)\s*\}, \[nav\]\)/.test(app),
      /const was = artistOpener\.current\s*if \(!artistOpen \|\| !was \|\| was\.isConnected\) return\s*artistOpener\.current = document\.querySelector<HTMLElement>\(`\.app-pane\[data-tab="\$\{nav\.tab\}"\] \.app-artist-back`\)/.test(app)],
    [true, true])
  check('...the page\'s own word on following: a page by MusicBrainz id, or one whose Navidrome name every album of moved',
    /const own = artist\?\.name \?\? null\s*const follow = ref\.navidrome === null \|\| \(own !== null && emptied\.some\(\(one\) => foldName\(one\) === foldName\(own\)\)\)\s*onMoved\?\.\(id, \{ mbid: to, name: now \}, follow\)/.test(page), true)
  check('...the page moved from asked again once Navidrome has had time to scan - under the id it has now; the wait the panel\'s (never unmounted), never a timer in App',
    [/onSettle=\{\(page\) => setTimeout\(\(\) => onSettled\?\.\(page\), EDIT_SETTLE_MS\)\}/.test(panel), /onSettled=\{artistSettled\}/.test(app), /setInterval|setTimeout/.test(app),
      /const artistSettled = useCallback\(\(page: string\) => \{\s*const id = artistMoves\.current\.get\(page\) \?\? page\s*setArtistRefreshes\(\(was\) => new Map\(was\)\.set\(id, \(was\.get\(id\) \?\? 0\) \+ 1\)\)\s*\}, \[\]\)/.test(app),
      /refresh=\{artistRefreshes\.get\(page\.id\) \?\? 0\}/.test(app)],
    [true, true, false, true, true])
  check('a write is never called off: the moves and the save are sent with no signal, and what they did is told whether the panel still shows or not',
    [/applyArtistRefile\(name, request\.mbid\)\)/.test(panel),
      /if \(told\.moved && request\.mbid\) \{\s*request\.onMoved\?\.\(\{[^}]*\}\)\s*onSettle\?\.\(request\.page\)\s*\}\s*if \(!ticket\.current\(\)\) return/.test(panel),
      /applyArtistImages\(request\.imagesName, chosen, \{ artistMbid: preview\.mbid, replace \}\)\s*\/\/\?[^\n]*\s*request\.onSaved\?\.\(\)\s*if \(!ticket\.current\(\)\) return/.test(read('app/ArtistPanel.tsx'))],
    [true, true, true])
  const asks = [...panel.matchAll(/\b(previewArtistRefile|previewArtistImages|searchArtists)\(([^;]*?)\)\.then/g)]
  check('every fetch that draws goes through a latestOnly(): each preview and search sent with its ticket\'s signal',
    [asks.length, asks.every((match) => /ticket\.signal/.test(match[2]))], [4, true])
  check('the managing is an admin\'s: handed `admin` and the panel\'s opener by App, each control drawn only for an admin',
    [/admin=\{admin\}\s*onManage=\{toggleArtistManage\}/.test(app), /const manages = admin && !!onManage/.test(page),
      (page.match(/\{manages && (?:\(shownLibrary \|\| summariesFailed\) && )?\(/g) ?? []).length, (page.match(/manage\('(?:who|images|refile)', event\)/g) ?? []).length],
    [true, true, 4, 4])
  //? (2.0.0-player.47: and as anything else an admin's comes on top there - an album page, a Managing page, You)
  check('...and a phone asks /deadwax/me as an artist page - or an album page, a Managing page, You - comes on top there (the desktop frame asks as it shows)',
    [/const adminsOnTop = nav\.tab === 'you' \|\| topNow\?\.kind === 'artist' \|\| topNow\?\.kind === 'album' \|\| \(!!topNow && MANAGING_KINDS\.includes\(topNow\.kind\)\)\s*useEffect\(\(\) => \{\s*if \(desktop \|\| !adminsOnTop\) return\s*const request = meRequests\.begin\(\)\s*me\(request\.signal\)\.then\(\s*\(who\) => \{\s*if \(request\.current\(\)\) setAdmin\(who\.admin\)/.test(app),
      /\}, \[desktop, adminsOnTop\]\)/.test(app)], [true, true])
  check('the page\'s summaries are asked through their own latestOnly()',
    [/const summaryRequests = useMemo\(latestOnly, \[\]\)/.test(page), /fetchArtist\(name, request\.signal\)/.test(page), /if \(!request\.current\(\)\) return\s*setSummaryAsking\(false\)[\s\S]{0,400}?const answered: Summaries/.test(page)],
    [true, true, true])
}

console.log('\nLooking after the library in the app, on a desktop (2.0.0-player.42)')
{
  const care = code(read('app/LibraryCare.tsx'))
  const store = code(read('app/useLibraryCare.ts'))
  const targets = code(read('lib/bulkTargets.ts'))
  const retime = code(read('components/RetimeLyrics.tsx'))
  const main = code(read('components/LibraryView.tsx'))
  const tab = code(read('components/SettingsView.tsx'))
  const server = code(read('app/ServerSettings.tsx'))
  const panel = code(read('app/EditPanel.tsx'))
  const queue = code(read('app/NeedsALook.tsx'))
  const app = code(read('app/App.tsx'))
  check('no playback action from Library care, its store, the targets or Re-time', [actionsIn(care), actionsIn(store), actionsIn(targets), actionsIn(retime)], [[], [], [], []])
  //? (2.0.0-player.47: told `admin`, never the frame - a phone draws the page; its note went)
  check('the library read through the main page\'s hook, only once the page shows, for the admin; anyone else\'s note drawn before anything',
    [/const library = useLibrary\(admin && live\)/.test(care), care.indexOf('if (!admin) {') < care.indexOf('const real = library.loaded'), /app-care-phone/.test(care),
      /\bdesktop\b/.test(care.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, ''))],
    [true, true, false, false])
  check('App draws it an admin\'s, on either frame, `live` as the other Managing pages\' - from the pages memo\'s one view',
    [/<LibraryCare admin=\{admin\} live=\{managingLive\(tab\)\}/.test(app), /page\.kind === 'care' \? careView\(tab\)/.test(app)],
    [true, true])
  check('Rescan is the scan that ignores the cache - refused while one is out; the library\'s listeners told once it has answered',
    [/void library\.reload\(true\)\.then\(/.test(care), /if \(scanBusy \|\| library\.problem\) return/.test(care), /if \(albums\.length\) announceAlbumsFiled\(\)/.test(care)],
    [true, true, true])
  //? the bulk runs are driven from the client, one album at a time (notes/decisions.md): each step is the
  //? route a single click uses, in a plain for loop, the next only once the last has answered
  check('a run: one album at a time, the next only once the last has answered, Stop asked before each',
    [/for \(const album of targets\) \{\s*if \(stopped\(\)\) break\s*let outcome: BulkOutcome\s*try \{\s*outcome = await step\(album\)/.test(targets), /Promise\.all|allSettled/.test(targets + store)],
    [true, false])
  check('...each step the route a single click uses - Get cover, Get CD art, Get lyrics - and no route of its own',
    [/covers: pictureStep\(\(path\) => libraryApi\.fetchCoverArt\(path\)\)/.test(store), /disc: pictureStep\(\(path\) => libraryApi\.fetchDiscArt\(path\)\)/.test(store),
      /await libraryApi\.fetchLyrics\(album\.path\)/.test(store), /\bpost\(|\bfetch\(/.test(store)],
    [true, true, true, false])
  check('...a 404 told apart from a failure, as the main page tells them',
    [/caught instanceof ApiError && caught\.status === 404 \? \{ missing: 1 \} : \{ failed: 1 \}/.test(store)], [true])
  check('...kept in the module (it outlives the page), each kind through a latestOnly() of its own, nothing of an older run drawn',
    [/^let kept: CareState = fresh\(\)$/m.test(store), /useState<BulkRun|useState<CareState/.test(care + store), /tickets\[kind\]\.begin\(\)/.test(store),
      /if \(!ticket\.current\(\)\) return\s*if \(now\.running\) keep\(\{ runs: \{ \.\.\.kept\.runs, \[kind\]: now \} \}\)/.test(store), /\(\) => kept\.stopping\[kind\] \|\| !ticket\.current\(\)/.test(store)],
    [true, false, true, true, true])
  check('...started and stopped from a click, over the targets worked out as it is pressed; the library told once at its end',
    [/onClick=\{\(\) => void startBulk\(kind, targets\)\}/.test(care), /onClick=\{\(\) => stopBulk\(kind\)\}/.test(care), /if \(run\.written > 0\) announceAlbumsFiled\(\)/.test(store)],
    [true, true, true])
  check('...offered only from a REAL scan', [/const targets = real && !care\.behind\[kind\] \? bulkTargets\(kind, inScope\) : null/.test(care), /const real = library\.loaded && !library\.stale/.test(care)], [true, true])
  //? (review: right after a run that wrote, its button came back over the albums it had just done)
  check('...and not while a run of that kind that wrote is newer than the scan in hand: its kind behind as it ends, the library read again at once, a page drawn fresh behind nothing',
    [/behind: now\.written > 0 \? \{ \.\.\.kept\.behind, \[kind\]: true \} : kept\.behind/.test(store),
      /const kinds = BULK_KINDS\.filter\(\(kind\) => libraryCareNow\(\)\.behind\[kind\]\)[\s\S]{0,200}void library\.reload\(false\)\.then\(/.test(care),
      /if \(pending\.answered && !library\.loading\) \{\s*catchUp\.current = null\s*caughtUp\(pending\.kinds\)/.test(care),
      /useEffect\(\(\) => \{\s*caughtUp\(BULK_KINDS\)\s*\}, \[\]\)/.test(care)],
    [true, true, true, true])
  //? (review: Chromium blurs a focused button AS it removes it, still in the page - read at once, that
  //? blur cleared the run whose words focus was to go to, and focus fell to the page)
  check('...focus moving on from a run\'s button asked once the turn is over, never during the blur of its removal',
    [/const leftRun = \(kind: BulkKind\) => \(event: FocusEvent\) => \{\s*const button = event\.currentTarget as HTMLElement\s*void Promise\.resolve\(\)\.then\(\(\) => \{\s*if \(focusedRun\.current === kind && button\.isConnected\) focusedRun\.current = null/.test(care)],
    [true])
  check('the targets are lib/bulkTargets.ts\'s, on BOTH pages - the main page\'s Library tab keeps no copy of its own',
    [/coverTargets\(visibleGroups\.flatMap/.test(main), /lyricsTargets\(visibleGroups\.flatMap/.test(main), /discTargets\(visibleGroups\.flatMap/.test(main),
      /!album\.art && album\.release_mbid|startsWith\('disc'\)|!album\.lyrics_count/.test(main)],
    [true, true, true, false])
  check('Re-time saved lyrics: one component both settings pages draw beside the lead, refused while the lead is a draft',
    [/import \{ RetimeLyrics \} from '\.\/RetimeLyrics'/.test(tab), /\bfunction RetimeLyrics\b/.test(tab), /import \{ RetimeLyrics \} from '\.\.\/components\/RetimeLyrics'/.test(server),
      (tab.match(/\{group\.id === 'lyrics' && \(?\s*<RetimeLyrics unsaved=\{draftEnv\['LYRICS_LEAD_MS'\] !== undefined\} \/>/g) ?? []).length,
      (server.match(/\{group\.id === 'lyrics' && <RetimeLyrics unsaved=\{draftEnv\['LYRICS_LEAD_MS'\] !== undefined\} \/>\}/g) ?? []).length],
    [true, false, true, 1, 1])
  check('...reading a REAL scan (never the saved one), its run in its module, through a latestOnly()',
    [/albums = \(await libraryApi\.listAlbums\(\)\)\.albums/.test(retime), /snapshot/.test(retime.replace(/\/\/.*$/gm, '')), /^let run: RetimeRun \| null = null$/m.test(retime), /const ticket = runs\.begin\(\)/.test(retime), /useState<RetimeRun/.test(retime)],
    [true, false, true, true, false])
  //? (review: kept in the module, an ended run's words outlived every later visit to the main page's tab)
  check('...how a run ended said once: let go as the last thing drawing it goes, and as a new lead is typed',
    [/listeners\.delete\(listener\)\s*if \(!listeners\.size && run && !run\.running\) run = null/.test(retime),
      /useEffect\(\(\) => \{\s*if \(!unsaved \|\| !run\) return\s*if \(run\.running\) leadMoved = true\s*else run = null\s*\}\)/.test(retime)],
    [true, true])
  //? (second review: a lead typed AND saved while it ran left "re-timed 5 tracks." under the new lead, part
  //? of it timed to the old - the server reads the lead as each album is asked for)
  check('...and a lead typed while it ran lets it go as it ends: every ending through ended(), the flag cleared as a run starts',
    [/const ended = \(last: RetimeRun\): RetimeRun \| null => \(leadMoved \? null : last\)/.test(retime),
      (retime.match(/keep\(ended\(\{/g) ?? []).length, (retime.match(/keep\(\{[^}]*running: false/g) ?? []).length,
      /if \(run\?\.running\) return\s*stop = false\s*leadMoved = false/.test(retime)],
    [true, 2, 0, true])
  //? (2.0.0-player.47: You's row on a phone too - straight after "Albums that need a look")
  check('the sidebar\'s Library care: an admin\'s, straight after Needs a look; You\'s row too, on both frames',
    [/\{admin && \([\s\S]*?\{item\(SIDEBAR_QUEUE\)\}\s*\{item\(SIDEBAR_CARE\)\}/.test(code(read('app/Sidebar.tsx'))),
      /<\/button>\s*<button type="button" class="app-row app-link-row app-queue-link-row" onClick=\{\(\) => onManaging\?\.\('care'\)\}>/.test(code(read('app/You.tsx')))],
    [true, true])
  check('Needs a look warns when ignores can\'t be saved: the library\'s answer or the count\'s',
    [/\{ignoresUnsaved\(library, tracking\) && <p class="app-queue-warning">\{IGNORES_UNSAVED\}<\/p>\}/.test(queue), /const tracking = useQueueTracking\(\)/.test(queue)],
    [true, true])
  //? the spec: "the two places that send you to the main page for it (ServerSettings.tsx, EditPanel.tsx) stop
  //? doing so" - ServerSettings' line is pinned in settingslog.sim; the Edit panel's Lyrics note is words, not a
  //? link, so the links-out count can't see it (review). Read raw: an apostrophe in JSX text isn't a string
  const lyricsNote = (read('app/EditPanel.tsx').match(/<h3 id="app-edit-lyrics"[\s\S]*?<\/section>/) ?? [''])[0]
  check('the Edit panel\'s Lyrics tab: re-timing named where it is - Managing\'s Settings, under Library - never the main page',
    [/re-timing the lyrics already saved, are in Managing's Settings, under Library\./.test(lyricsNote), /main page/i.test(lyricsNote)], [true, false])
  //? and the sidebar's link to the main page names nothing left only there (2.0.0-player.45: an artist's
  //? pictures and re-filing came to the artist page), as You's footnote says (you.sim)
  const mainLink = (read('app/Sidebar.tsx').match(/<a\s+class="app-side-item"\s+href="\/"[\s\S]*?>/) ?? [''])[0]
  check('the sidebar\'s "Open the main page": its title says everything is in the app now - not the bulk runs, Rescan, re-timing, artist images or re-filing',
    [/title="The main page, until it retires - everything here is in the app now"/.test(mainLink), /bulk|covers|CD art|lyrics|rescan|re-tim|artist images|re-fil/i.test(mainLink)], [true, false])
  check('the Edit panel: no link to the main page left - "Choose the folder" over the scan, the folder chosen its subject for that Edit',
    [linksOut(panel).length, /status\.choose && !pickingNow/.test(panel), /chosenPath \? folderOnly\(chosenPath\)/.test(panel),
      /setChosen\(\{ key: request\.key, path \}\)\s*setPicking\(null\)\s*chooseFolder\(path\)\s*focusNext\.current = toTab\(tab\)/.test(panel),
      /setChosen\(null\)\s*setPicking\(null\)\s*lookUp\(request\)/.test(panel)],
    [0, true, true, true, true])
}

console.log('\ninside a track (2.0.0-player.44): the track inspector, the cover viewer, an album\'s Properties')
{
  const panel = code(read('app/EditPanel.tsx'))
  const inspector = code(read('app/TrackInspector.tsx'))
  const viewer = code(read('app/CoverViewer.tsx'))
  const page = code(read('player/AlbumPage.tsx'))
  const drawnIn = (name) => files.filter((file) => APP_SIDE(file) && new RegExp(`<${name}\\b`).test(code(read(file))))
  check('none of the three calls a playback action', ['app/TrackInspector.tsx', 'app/CoverViewer.tsx', 'app/AlbumProperties.tsx'].map((file) => actionsIn(code(read(file)))), [[], [], []])
  check('the inspector is the Edit panel\'s alone, in the Tags pane - the tag editor over it, the list under it',
    [drawnIn('TrackInspector'),
      /\{editingTags && editingTags\.path === subject\.path \? \(\s*<TrackTagEditor[\s\S]*?\) : inspected \? \(\s*<TrackInspector[\s\S]*?\) : \(\s*<TagsList[\s\S]*?onInspect=\{inspect\}/.test(panel)],
    [['app/EditPanel.tsx'], true])
  check('...a track\'s NAME opens it - a button of its own, its tick box still ticking',
    [/<button type="button" class="app-edit-track-open" data-file=\{track\.filename\} onClick=\{\(\) => onInspect\(track\.filename\)\}>/.test(panel),
      /onClick=\{\(event\) => onTick\(track\.filename, event\.shiftKey\)\}/.test(panel)],
    [true, true])
  check('...only a track still in the folder shown, of this folder',
    /const inspected = drawn && inspecting && inspecting\.path === subject!\.path && subject!\.tracks\.some\(\(track\) => track\.filename === inspecting\.filename\)\s*\? inspecting\.filename\s*: null/.test(panel), true)
  check('...a layer: Escape inside the panel back to the list (the page\'s own Escape passed over, one taken by another listener left), only while it is the Tags tab\'s top',
    [/const inspectorTop = open && !covered && tab === 'tags' && inspected !== null && !tagEditorShown/.test(panel),
      /useEffect\(\(\) => \{\s*if \(!inspectorTop\) return\s*const onKeyDown = \(event: KeyboardEvent\) => \{\s*if \(event\.key !== 'Escape' \|\| event\.defaultPrevented\) return\s*if \(escapeFrom\(\) === 'page'\) return\s*event\.preventDefault\(\)\s*backToList\(\)\s*\}\s*document\.addEventListener\('keydown', onKeyDown\)\s*return \(\) => document\.removeEventListener\('keydown', onKeyDown\)\s*\}, \[inspectorTop\]\)/.test(panel)],
    [true, true])
  check('...focus to Back as it opens; back to the track\'s own name, the list where it was, as it closes; kept on Previous and Next',
    [/setInspecting\(\{ path: subject\.path, filename, listTop: scroller\.current\?\.scrollTop \?\? 0 \}\)\s*scrollTop\(\)\s*focusNext\.current = \(\) => tagsPane\.current\?\.querySelector<HTMLElement>\('\.app-inspect-back'\)/.test(panel),
      /const trackName = \(filename: string\) => \[\.\.\.\(tagsPane\.current\?\.querySelectorAll<HTMLElement>\('\.app-edit-track-open'\) \?\? \[\]\)\]\s*\.find\(\(button\) => button\.dataset\['file'\] === filename\)/.test(panel),
      /setInspecting\(null\)\s*restoreView\.current = \{ top: was\.listTop, show: \(\) => trackName\(was\.filename\) \}\s*focusNext\.current = \(\) => trackName\(was\.filename\)/.test(panel),
      /const stepTo = \(filename: string\) => \{\s*setInspecting\(\(was\) => \(was \? \{ \.\.\.was, filename \} : was\)\)\s*scrollTop\(\)\s*\}/.test(panel),
      (inspector.match(/aria-disabled=\{steps\.(before|after) \? undefined : 'true'\}/g) ?? []).length, /\bdisabled=/.test(inspector.replace(/aria-disabled=/g, ''))],
    [true, true, true, true, 2, false])
  //? (review) the list put back where it was by an effect once it has drawn - and the track focus goes back
  //? to then brought into view: Previous and Next may have moved on past the rows that were in view
  check('(review) ...the list put back where it was once drawn, then the track focus goes back to brought into view',
    [/useLayoutEffect\(\(\) => \{\s*const back = restoreView\.current\s*if \(!back\) return\s*restoreView\.current = null\s*const box = scroller\.current\s*if \(!box\) return\s*box\.scrollTop = back\.top\s*const shown = back\.show\(\)\s*if \(!shown\) return\s*const seen = box\.getBoundingClientRect\(\)\.top \+ box\.clientTop\s*box\.scrollTop \+= revealBy\(\{ top: seen, bottom: seen \+ box\.clientHeight \}, shown\.getBoundingClientRect\(\)\)\s*\}\)/.test(panel),
      //? ...and after focus has gone to it: the focus hand-on's effect is the earlier one
      panel.indexOf('const pick = focusNext.current') < panel.indexOf('const back = restoreView.current')],
    [true, true])
  //? (review) the tag editor's scroll stayed on the view under it as it closed - the inspector, taller, kept
  //? the editor's offset and "Edit this track…" was focused above the panel's top, out of sight: the editor
  //? opens from its top, keeping where the view under it was, and closes back to there, the button focus
  //? goes back to brought into view by the same effect
  check('(review) the tag editor from its top, the view under it kept - and as it closes put back, the button focus goes back to in view',
    [/const openTagEditor = \(path: string, filenames: string\[\]\) => \{\s*editorOver\.current = scroller\.current\?\.scrollTop \?\? 0\s*scrollTop\(\)\s*setEditingTags\(\{ path, filenames \}\)/.test(panel),
      /focusNext\.current = opener\s*restoreView\.current = \{ top: editorOver\.current, show: opener \}\s*\}, \[\]\)/.test(panel),
      (panel.match(/editorOver\.current = /g) ?? []).length, (panel.match(/restoreView\.current = \{/g) ?? []).length],
    [true, true, 1, 2])
  //? (review) "Edit this track…" the tag editor on that one file - its one way to a writer - and the list's
  //? Edit N tracks… on the ticked ones
  check('(review) "Edit this track…" opens the tag editor on that one file alone',
    [/<TrackInspector[\s\S]*?onEdit=\{\(filename\) => openTagEditor\(subject\.path, \[filename\]\)\}/.test(panel),
      /<TagsList[\s\S]*?onEdit=\{\(filenames\) => openTagEditor\(subject\.path, filenames\)\}/.test(panel),
      (panel.match(/openTagEditor\(subject\.path, /g) ?? []).length],
    [true, true, 2])
  check('...afresh for every Edit and every folder, following a rename',
    [/setEditingTags\(null\)\s*setInspecting\(null\)\s*setDeleted\(null\)/.test(panel), /setTicked\(null\)\s*setEditingTags\(null\)\s*setInspecting\(null\)\s*scrollTop\(\)/.test(panel),
      /setInspecting\(\(was\) => \(was && was\.path === oldPath \? \{ \.\.\.was, path: newPath \} : was\)\)/.test(panel)],
    [true, true, true])
  check('...its lyrics through a latestOnly(), only the newest answer drawn; read only - no writer reached',
    [/const requests = useMemo\(latestOnly, \[\]\)/.test(inspector), /const ticket = requests\.begin\(\)/.test(inspector),
      /trackLyrics\(album\.path, filename, ticket\.signal\)/.test(inspector), (inspector.match(/if \(ticket\.current\(\)/g) ?? []).length,
      /\b(fetchLyrics|fetchCoverArt|fetchDiscArt|applyTagEdits|applyRetag|deleteAlbum|previewTagEdits)\b/.test(inspector)],
    [true, true, true, 2, false])
  check('the cover viewer: the main page\'s ArtViewer, reached in the app only through CoverViewer',
    [files.filter((file) => APP_SIDE(file) && /from '\.\.\/components\/ArtViewer'/.test(code(read(file))) && !/import type/.test((code(read(file)).match(/import[^\n]*components\/ArtViewer'/) ?? [''])[0])),
      drawnIn('ArtViewer'), drawnIn('CoverViewer')],
    [['app/CoverViewer.tsx'], ['app/CoverViewer.tsx'], ['app/EditPanel.tsx', 'app/TrackInspector.tsx', 'player/AlbumPage.tsx']])
  check('...opened from an album page\'s cover, Artwork\'s cover and CD art, and the inspector\'s pictures - each opener taken in the tap',
    [(page.match(/viewOpener\.current = takeOpener\(event\)/g) ?? []).length, (panel.match(/opener\.current = takeOpener\(event\)/g) ?? []).length,
      (inspector.match(/opener\.current = takeOpener\(event\)/g) ?? []).length,
      (panel.match(/onClick=\{\(event\) => view\(event as unknown as MouseEvent, \[/g) ?? []).length],
    [1, 1, 1, 2])
  //? (review) what each of Artwork's two opens, pinned, not only that they open: the cover as the main page
  //? opens it (its own file, then the Cover Art Archive's), each CD art picture the very file its thumbnail shows
  const coverOpen = panel.match(/class="app-edit-cover-open"[\s\S]*?view\(event as unknown as MouseEvent, \[\{\s*label: album\.album,\s*sources: ([^\n]*),\n[\s\S]*?<img class="app-edit-cover" src=\{([^}]*)\}/)
  const discOpen = panel.match(/class="app-edit-disc"[\s\S]*?view\(event as unknown as MouseEvent, \[\{ label: name, sources: \[([^\]]*)\] \}\]\)\}\s*>\s*<img class="app-edit-disc-img" src=\{([^}]*)\}/)
  check('(review) ...Artwork\'s cover opening the cover as the main page does, each CD art picture the file its thumbnail shows',
    [coverOpen?.slice(1), discOpen?.slice(1), (panel.match(/class="app-edit-disc"/g) ?? []).length],
    [["coverSources(album, 'full')", 'albumArtUrl(album)'], ['discArtUrl(album.path, name, album.modified_at)', 'discArtUrl(album.path, name, album.modified_at)'], 1])
  check('...its own lock, focus in to Close and back to the opener, Tab kept inside',
    [/page\.classList\.add\(VIEWER_LOCK\)/.test(viewer), /box\.current\?\.querySelector<HTMLElement>\('\.window-close'\)\?\.focus\(\{ preventScroll: true \}\)/.test(viewer),
      /opener\?\.current\?\.focus\(\{ preventScroll: true \}\)/.test(viewer), /if \(event\.key !== 'Tab' \|\| !box\.current\) return/.test(viewer)],
    [true, true, true, true])
  //? (review) a tab's page is kept mounted, hidden: a viewer left open in one after Back held its lock on the
  //? page shown and took its next Escape (inspector.sim.cjs moves through the history)
  check('(review) ...closed by a move through the history while it shows',
    [/useEffect\(\(\) => \{\s*if \(!open\) return\s*const moved = \(\) => closeNow\.current\(\)\s*window\.addEventListener\('popstate', moved\)\s*window\.addEventListener\('hashchange', moved\)/.test(viewer),
      /window\.removeEventListener\('popstate', moved\)\s*window\.removeEventListener\('hashchange', moved\)/.test(viewer)],
    [true, true])
  check('an album page\'s Properties: from the bridge answer it asks already - no new request - drawn under the songs',
    [(page.match(/storeAlbum\(/g) ?? []).length, /<AlbumProperties rows=\{albumProperties\(store, storeFailed, releaseSaid\)\} \/>/.test(page),
      page.indexOf('<AlbumProperties') > page.indexOf('class="pl-album-footer"')],
    [1, true, true])
  //? (review) "not tagged" only on Navidrome's own word for the album - the bridge's null is also its answer for
  //? an id Navidrome doesn't have (an old address, "Navidrome has nothing by that id" above it), and a failed
  //? ask: the album's own answer's id, '' when it came without one, a preview's until it comes, else nothing
  check('(review) ...the release as the album\'s own answer said it, none when it came without one - never from the bridge\'s null',
    /const releaseSaid = album \? album\.musicBrainzId \?\? '' : shown\?\.musicBrainzId\n/.test(page), true)
  check('...the unresized cover asked for by the viewer alone - every screen still sharing the three sizes',
    files.filter((file) => /\bcoverFullUrl\(/.test(code(read(file)))), ['player/AlbumPage.tsx', 'player/api.ts'])
  //? (review) the viewer shows its sources in order, moving on only when one fails to load: the unresized
  //? cover first, the page's own sized one its fallback
  check('(review) ...shown first, the page\'s own sized cover its fallback',
    /sources: \[coverFullUrl\(shown\.coverArt\), coverUrl\(shown\.coverArt, 800\)\]/.test(page), true)
}

console.log('\nthe checks themselves')
{
  check('a comment is not code', code('a // usePlayer(\nb /* toggle */ c'), 'a \nb  c')
  check('a string is kept', code("x = 'http://a' // gone"), "x = 'http://a' ")
  check('a member call is found', actionsIn('onClick={player.toggle}'), ['toggle'])
  check('classList.toggle is not a playback action', actionsIn("el.classList.toggle('x', on)"), [])
  check('taken apart from the player is found', actionsIn('const { next, queue } = player'), ['next'])
  check('...and a key renamed to the word is not', actionsIn('const { nav: next, action } = selectTab(now, tab)'), [])
  check('...but the word renamed away still is', actionsIn('const { toggle: flip } = player'), ['toggle'])
  check('by name is found', actionsIn('actions.playTracks(tracks, 0)'), ['playTracks'])
  check('a renamed import of usePlayer is still usePlayer', importsUsePlayer("import { usePlayer as useEngine } from '../player/usePlayer'"), true)
  check('...across lines, beside others', importsUsePlayer("import {\n  usePosition,\n  usePlayer,\n} from './usePlayer'"), true)
  check('a namespace import counts', importsUsePlayer("import * as engine from '../player/usePlayer'"), true)
  check('usePosition and a type are not', importsUsePlayer("import { usePosition, type Player } from './usePlayer'"), false)
  check('nor is a type-only import', importsUsePlayer("import type { Player } from '../player/usePlayer'"), false)
  check('nor another module\'s usePlayer', importsUsePlayer("import { usePlayer } from '../lib/somethingElse'"), false)
  check('a link out is found; an in-app # link is not', [linksOut('<a href="/">x</a> <a href="#/home">y</a>').length, linksOut('<a class="b"\n href="/x">').length], [1, 1])
  check('...nor a link that saves a file', linksOut('<a href={row.action.href} download={row.action.download}>save</a>').length, 0)
  check('opening beside needs both target and noopener',
    [opensBeside('<a href="/" target="_blank" rel="noopener">'), opensBeside('<a href="/" target="_blank">'), opensBeside('<a href="/" rel="noopener">')], [true, false, false])
}

console.log('\nGet, as the main page had it (2.0.0-player.41)')
{
  const app = code(read('app/App.tsx'))
  const album = code(read('player/AlbumPage.tsx'))
  const page = code(read('app/ReleaseGroupPage.tsx'))
  const sheet = code(read('app/Sources.tsx'))
  const hook = code(read('hooks/useCandidateSearch.ts'))
  //? another pressing of an album you hold: the album page's last chip, to the group's page with no preview
  check('the album you have: "Other pressings" last in the chip row drawn from the first frame, opening its group',
    [album.indexOf('<div class={`app-album-chips') >= 0 && album.indexOf('<div class={`app-album-chips') < album.indexOf('{chips.map(') && album.indexOf('{chips.map(') < album.indexOf('app-other-pressings')
      && album.indexOf('app-other-pressings') < album.indexOf('<div class="pl-hero-actions">'),
      /\{group && onOpenGroup && \(\s*<button\s+type="button"\s+class="app-chip app-other-pressings"\s+aria-label="Other pressings"\s+onClick=\{\(\) => onOpenGroup\(\{ id: group, title: shown\?\.name \?\? '' \}\)\}/.test(album),
      /const group = otherPressingsGroup\(store\)/.test(album), /onOpenGroup=\{openHeldGroup\}/.test(app)],
    [true, true, true, true])
  const held = /const openHeldGroup = useCallback\(\(group: \{ id: string; title: string \}\) => \{([\s\S]*?)\n  \}, \[\]\)/.exec(app)?.[1] ?? ''
  check('...App opens it as a page on the tab showing, its name the label - and no preview, so the header and Get are MusicBrainz\'s own',
    [/const page: Page = \{ kind: 'group', id: group\.id, \.\.\.\(group\.title \? \{ label: group\.title \} : \{\}\) \}/.test(held), /router\.open\(page\)/.test(held), /groupPreviews/.test(held),
      /title=\{page\.label \?\? ''\}/.test(app), /<h1 class="pl-hero-title">\{header\.title \|\| title\}<\/h1>/.test(page), /getGroup\(mbid, preview, releases, chosen\)/.test(page)],
    [true, true, false, true, true, true])
  check('the pressing list marks what the library holds, from the page\'s one /library/owned answer (whose each is, as the store line last said - second review)',
    [/const ownership = owned \? ownedForGroup\(owned\.index, \{\s*groupId: mbid,\s*releaseIds: releases\.map\(\(release\) => release\.id\),[\s\S]*?\}\) : null\s*(?:const [^\n]*\n\s*){3}const holding = ownership \? withStoreLine\(ownership\.held, said\) : null/.test(page),
      //? (2.0.0-player.52) and which of those are yours: "In the store" for one that isn't, with a library of your own
      //? (2.0.0-player.53) the pressing asked for: the address's, else - opened from a song - one with the song
      /pressingsView\(releases, asked, heldIds, yoursIds\)/.test(page),
      /\{row\.held && <span class=\{`app-picker-held\$\{row\.inStore \? ' is-store' : ''\}`\}>\{row\.inStore \? 'In the store' : 'In your library'\}<\/span>\}/.test(code(read('app/PressingPicker.tsx')))],
    [true, true, true])
  //? James's decision kept (pin both): Search's MusicBrainz half leaves held groups out, and the artist
  //? page's held rows still open the album you have - the way to another pressing is the album page's
  check('Search\'s MusicBrainz half still leaves out what the library holds by group; its held row still opens the album you have',
    [/shown: notInLibrary\(groups, ownedNow\(\)\?\.index \?\? null\)/.test(code(read('app/Search.tsx'))),
      /const releases = heldReleases\(owned\?\.index \?\? null, group\.id\)[\s\S]*?if \(album\) onOpenAlbum\(/.test(code(read('app/Search.tsx')))],
    [true, true])
  check('...and the artist page\'s held rows still open the album you have',
    /if \(row\.albumId\) onOpenAlbum\(\{ id: row\.albumId[\s\S]*?navidromeAlbumFor\(row\.releases, request\.signal\)[\s\S]*?if \(album\) onOpenAlbum\(/.test(code(read('app/ArtistPage.tsx'))), true)
  //? the score's reasons: on the card, behind the score on a phone
  check('each card told how its reasons show: behind the score in a phone\'s sheet, always on a desktop\'s panel',
    /<SourceCard\s+key=\{candidateKey\(candidate\)\}[\s\S]*?reasons=\{modal \? 'tap' : 'shown'\}/.test(sheet), true)
  //? Format: You's, kept on deadwax, sent with every search - the main page's storage never read for it
  const run = /async function run\([^)]*\) \{([\s\S]*?)\n  \}/.exec(hook)?.[1] ?? ''
  check('Format: the search sends You\'s, read as it begins - waited for only while deadwax is being asked - and nothing after a superseded wait',
    [/formatPreference: formatPreferenceNow/.test(sheet), /const asked = formatNow\.current\(\)\s*const format = typeof asked === 'string' \? asked : await asked\s*if \(!request\.current\(\)\) return\s*const result = await api\.findCandidates\(\s*\{ \.\.\.release, query_override: override, format_preference: format \}/.test(run),
      /readDownloadDefaults/.test(hook)],
    [true, true, false])
  //? (review) a desktop panel stays open across Gets and pressings: only its opening asked, so a Format
  //? changed elsewhere meanwhile never reached a search - every search the sheet starts asks first
  check('...and every search the sheet starts asks deadwax for the settings first: one way to start one, which asks before it starts',
    [/const begin = \(release: DownloadRelease, fresh\?: boolean\) => \{\s*void askGetSettings\(\)\s*state\.start\(release, fresh\)\s*\}/.test(sheet),
      (sheet.match(/state\.start\(/g) || []).length, (sheet.match(/\bbegin\(/g) || []).length, (sheet.match(/state\.requery\(\)/g) || []).length],
    [true, 1, 3, 1])
  check('...and the app reads the main page\'s Format only to carry it over once (the seed), nowhere else',
    files.filter((file) => (file.startsWith('app/') || file.startsWith('hooks/') || file.startsWith('player/')) && /readDownloadDefaults/.test(code(read(file)))), ['app/useGetSettings.ts'])
  //? Confirm before cancelling: this device's, read at the tap
  check('Confirm before cancelling: Requests reads this device\'s at the tap; the main page\'s preferences only seed (Getting albums)',
    [/else if \(readConfirmCancel\(\)\) setAsking\(row\.key\)/.test(code(read('app/Requests.tsx'))),
      files.filter((file) => file.startsWith('app/') && /readPreferences\(/.test(code(read(file))))], [true, ['app/useGetSettings.ts']])
  //? Search again: a disclosure under folders found, its field focused as it opens, closed as a search starts
  check('Search again: a disclosure controlling the query form, focus to its field as it opens, closed as a search starts',
    [/<button type="button" class="app-text-button" aria-expanded=\{again\} aria-controls=\{againId\} onClick=\{\(\) => setAgain\(\(was\) => !was\)\}>/.test(sheet),
      /useLayoutEffect\(\(\) => \{\s*if \(again\) againField\.current\?\.focus\(/.test(sheet),
      /const requery = \(\) => \{\s*keepFocus\(\)\s*setAgain\(false\)\s*void askGetSettings\(\)\s*state\.requery\(\)/.test(sheet),
      /if \(scroller\.current\) scroller\.current\.scrollTop = 0\s*setAgain\(false\)/.test(sheet)],
    [true, true, true, true])
}

//? LOADING (the audit): the Library asks Navidrome for nothing until its tab has been shown once, and a
//? cover is asked for at one of three sizes, so the screens share what they fetch
{
  const app = code(read('app/App.tsx'))
  const api = read('player/api.ts')
  check('the Library is drawn - and so asks for its albums, covers and songs - only once its tab has shown',
    [/\{librarySeen && <Library onOpen=\{openAlbum\}/.test(app), /if \(nav\.tab === 'library'\) setLibrarySeen\(true\)/.test(app),
      /useState\(nav\.tab === 'library'\)/.test(app), (app.match(/<Library /g) || []).length], [true, true, true, 1])
  const sizes = JSON.parse(/export const COVER_SIZES: readonly number\[\] = (\[[^\]]+\])/.exec(api)[1])
  const step = (size) => sizes.find((s) => s >= size) ?? sizes[sizes.length - 1]
  check('covers come in three sizes', sizes, [128, 400, 1024])
  check('...every place a cover is drawn asking for the step that covers it: rows and the mini player one, tiles and the turntable\'s label one, the album page, Now Playing and the lock screen one',
    [96, 112, 120, 260, 300, 400, 512, 800, 1000, 4000].map(step), [128, 128, 128, 400, 400, 400, 1024, 1024, 1024, 1024])
  check('...and coverUrl asks through it, nothing else building a cover\'s address',
    [/size=\$\{coverSize\(size\)\}/.test(api), /COVER_SIZES\.find\(\(step\) => step >= size\) \?\? COVER_SIZES\[COVER_SIZES\.length - 1\]/.test(api)], [true, true])
}

//? LOOKING AFTER DEADWAX FROM A PHONE (2.0.0-player.47): the Edit panel a phone's sheet, the four Managing pages
//? drawn on a phone (handed `admin`, never the frame), You's rows on both frames, and the Navidrome gate's
//? "Set up Navidrome" opening the app's own Settings at Connections - a save there asking Navidrome again
console.log('\nlooking after deadwax from a phone (2.0.0-player.47)')
{
  const app = code(read('app/App.tsx'))
  const gate = code(read('app/NeedsNavidrome.tsx'))
  const setUp = code(read('app/navidromeSetUp.ts'))
  const pages = ['app/NeedsALook.tsx', 'app/LibraryCare.tsx', 'app/ServerSettings.tsx', 'app/EventLog.tsx']
  check('no playback action from the gate\'s new module, nor a player read',
    [actionsIn(setUp), /useContext|usePlayer|PlayerContext/.test(setUp)], [[], false])
  check('the four Managing pages know no frame - each told `admin`, and anyone else\'s note says so, with no link out',
    pages.map((file) => {
      const text = code(read(file))
      return [/\bdesktop\b/.test(text.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '')), /if \(!admin\) \{\s*return \(/.test(text), /\{MANAGING_ADMINS_ONLY\}/.test(text), /is-phone|_PHONE\b/.test(text)]
    }),
    pages.map(() => [false, true, true, false]))
  check('...App hands each `admin` alone: Needs a look, Library care, the settings and the log',
    [/<NeedsALook\s+admin=\{admin\}/.test(app), /<LibraryCare admin=\{admin\}/.test(app), /<ServerSettings admin=\{admin\}/.test(app), /<EventLog admin=\{admin\}/.test(app),
      /desktop=\{desktop && admin\}/.test(app)],
    [true, true, true, true, false])
  //? a phone's sheet has no Shift: the Tags tab's note offers none
  const panel = code(read('app/EditPanel.tsx'))
  check('the Edit sheet\'s Tags note says nothing of Shift - a phone has none to tick a run with',
    [/<TagsList\s+album=\{subject\}\s+sheet=\{modal\}/.test(panel),
      /\{count \? `\$\{count\} of \$\{tracks\.length\} ticked` : sheet \? 'Tick tracks to edit only those\.' : 'Tick tracks to edit only those; Shift ticks a run\.'\}/.test(panel)],
    [true, true])
  check('the gate: no link out - "Set up Navidrome", the app\'s secondary button, calls the module\'s setUpNavidrome',
    [linksOut(gate).length, /import \{ setUpNavidrome \} from '\.\/navidromeSetUp'/.test(gate),
      /<button type="button" class="app-button app-needs-setup" onClick=\{setUpNavidrome\}>\s*Set up Navidrome\s*<\/button>/.test(gate)],
    [0, true, true])
  check('...which App says opens Server settings at Connections - the Managing page, on You, as You\'s row opens it',
    [/useEffect\(\(\) => setUpNavidromeBy\(\(\) => \{\s*showServerSettingsTab\('connections'\)\s*openManaging\('settings'\)\s*\}\), \[\]\)/.test(app),
      files.filter((file) => APP_SIDE(file) && /setUpNavidromeBy\(/.test(code(read(file)))), files.filter((file) => APP_SIDE(file) && /showServerSettingsTab\(/.test(code(read(file)))).sort()],
    [true, ['app/App.tsx', 'app/navidromeSetUp.ts'], ['app/App.tsx', 'app/ServerSettings.tsx']])
  check('...and a save the server took that touched Navidrome\'s settings asks Navidrome again - so the gate opens by itself - quietly (review)',
    [/useEffect\(\(\) => onServerSettingsSaved\(\(keys\) => \{\s*if \(keys\.some\(\(key\) => key\.startsWith\('NAVIDROME_'\)\)\) navidromeAsks\.recheck\(\)\s*\}\), \[\]\)/.test(app),
      /for \(const listener of \[\.\.\.saved\]\) listener\(Object\.keys\(sent\)\)/.test(code(read('app/ServerSettings.tsx'))),
      code(read('app/ServerSettings.tsx')).indexOf('listener(Object.keys(sent))') > code(read('app/ServerSettings.tsx')).indexOf('const answer = await saveServerSettings(updates)')
        && code(read('app/ServerSettings.tsx')).indexOf('listener(Object.keys(sent))') < code(read('app/ServerSettings.tsx')).indexOf('} catch (caught: unknown)')],
    [true, true, true])
  //? (review: the re-ask after a save was the first that could overlap another - a save made while the last
  //? ask still waited out an address that didn't answer - and it put the status away first, so every gate
  //? on every tab unmounted what it guarded for a password retyped. lib/navidromeCheck.ts holds both rules;
  //? settingslog.sim.cjs drives it)
  const checks = code(read('lib/navidromeCheck.ts'))
  check('...App asks Navidrome only through lib/navidromeCheck.ts, made once: as it starts and from Try again with the status put away, after a save quietly',
    [/const navidromeAsks = useMemo\(\(\) => navidromeChecks\(navidromeStatus, setStatus\), \[\]\)/.test(app), /const checkNavidrome = navidromeAsks\.check\b/.test(app),
      /useEffect\(\(\) => \{\s*navidromeAsks\.check\(\)\s*return navidromeAsks\.stop\s*\}, \[\]\)/.test(app),
      (app.match(/navidromeStatus\(/g) ?? []).length, (app.match(/\bsetStatus\(/g) ?? []).length,
      files.filter((file) => APP_SIDE(file) && /navidromeChecks\(/.test(code(read(file)))).sort()],
    [true, true, true, 0, 0, ['app/App.tsx']])
  check('...where each ask is a latestOnly ticket, drawing only while it is the newest - its answer and its failure alike',
    [/const asks = latestOnly\(\)/.test(checks), /const ticket = asks\.begin\(\)/.test(checks), /ask\(ticket\.signal\)/.test(checks),
      (checks.match(/if \(ticket\.current\(\)\) show\(/g) ?? []).length, /show\(\(now\) => \(quiet && now\?\.ok \? now : null\)\)/.test(checks)],
    [true, true, true, 2, true])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
