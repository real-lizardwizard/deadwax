/**
 * The app's gesture rules (2.0.0-player.9 on), read off the source - the rules that keep the engine
 * working now that the player lives inside five tabs. "The one app" in CLAUDE.md says why each one
 * exists; in short:
 *
 *  - usePlayer() is called ONCE, in app/App.tsx, which never unmounts. The engine makes one audio
 *    element for the page's life, and iOS unlocks audio per element from a tap: a second call - a
 *    tab calling it - is a second element nobody unlocked. Only App imports it as a value, so a
 *    renamed import (`usePlayer as useEngine`) can't slip a second call past the count.
 *  - The playback actions (playTracks, toggle, next, previous, setGapless, showAirPlay) must be
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
  //? names them for ActionsContext and calls none (pickActions)
  'app/context.ts': ['playTracks', 'toggle', 'next', 'previous', 'setGapless', 'showAirPlay'],
}

/** Which playback actions a file's code reaches: by name, as a member, or taken apart from one. */
function actionsIn(text) {
  const found = new Set()
  for (const match of text.matchAll(/\b(playTracks|setGapless|showAirPlay)\b/g)) found.add(match[1])
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
    return href && !((href[1] ?? href[2] ?? '').startsWith('#'))
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
    'player/Turntable.tsx': ['toggle'],
  })
  check('app/context.ts names them and calls none',
    [...code(read('app/context.ts')).matchAll(/\.(playTracks|toggle|next|previous|setGapless|showAirPlay)\s*\(/g)].map((m) => m[1]), [])
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
  check('...what it watches worked out by watchingOf, from the tab, its stack, Now Playing and the page being shown',
    /const watching = watchingOf\(\{ shown: pageShown, tab: nav\.tab, depth: nav\.stacks\[nav\.tab\]\.length, sheetOpen \}\)/.test(app), true)
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
    [/const playingId = player\.track\?\.id \?\? null/.test(app), /\[nav, status, playingId, player\.playing, sourcesOpen, pageShown, desktop, sourcesGroup, sourcesPressing\],\s*\)/.test(app), /\[nav, player, status\]/.test(app)], [true, true, false])
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
  //? sidebar's Managing link came in 2.0.0-player.19
  check('...and there are links to look at (You, the gate, the desktop sidebar)',
    [...new Set(out.map(([file]) => file))].sort(), ['app/NeedsNavidrome.tsx', 'app/Sidebar.tsx', 'app/You.tsx'])
}

console.log('\nNow Playing covers everything behind it')
{
  const app = code(read('app/App.tsx'))
  //? 2.0.0-player.15: inert behind Now Playing OR the Sources sheet - each covers what would open the other
  const behind = /<div class="app-behind" aria-hidden=\{covered\} inert=\{covered\}>([\s\S]*?)<\/div>\s*(?:\{(?:\/\*[\s\S]*?\*\/)?\}\s*)?<Sources\b[^\n]*\/>\s*<NowPlaying/.exec(app)
  check('the panes, the mini player and the tab bar are inside one inert wrapper',
    [!!behind, /TABS\.map/.test(behind?.[1] ?? ''), /<MiniPlayer\b/.test(behind?.[1] ?? ''), /<TabBar\b/.test(behind?.[1] ?? '')], [true, true, true, true])
  //? 2.0.0-player.19: on a phone - a desktop's side panel leaves the page beside it as it is
  check('...inert while Now Playing or the Sources sheet shows, on a phone', /const covered = !desktop && \(sheetOpen \|\| sourcesOpen\)/.test(app), true)
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
  }
  const texts = Object.fromEntries(Object.keys(SHEETS).map((file) => [file, code(read(file))]))
  check('each calls useSheet with a scroll lock of its own',
    Object.fromEntries(Object.entries(texts).map(([file, text]) => [file, /useSheet\(\{[^}]*lockClass: '([^']+)'/.exec(text)?.[1] ?? null])), SHEETS)
  check('...and they are the only ones', files.filter((file) => /\buseSheet\(/.test(code(read(file))) && file !== 'app/useSheet.ts').sort(), Object.keys(SHEETS).sort())
  check('each is inert while closed', Object.values(texts).map((text) => /\binert=\{!open\b/.test(text)), [true, true, true, true])
  check('Now Playing is inert under the menu or Info, and they are hidden from it', /aria-hidden=\{!open \|\| covered\}\s*inert=\{!open \|\| covered\}/.test(texts['player/NowPlaying.tsx']), true)
  check('the menu, Info and the sources close on their backdrop',
    ['app/ActionMenu.tsx', 'app/InfoSheet.tsx', 'app/Sources.tsx'].map((file) => /<div class="app-backdrop" onClick=\{onClose\} \/>/.test(texts[file])), [true, true, true])
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
    [/requestAnimationFrame|setInterval|setTimeout/.test(table), /usePosition\(player\)/.test(table), /visibilitychange/.test(table),
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
  const wakes = files.filter((file) => APP_SIDE(file) && file !== 'player/deck.ts').flatMap((file) => {
    const text = code(read(file))
    return [...text.matchAll(/\b(wakeDeckAudio|resumeDeckAudio)\(\)/g)].map((match) => `${file}: ${enclosing(text, match.index)}: ${match[1]}`)
  })
  check('made or resumed only from gestures WebKit counts: the record\'s click and release, the transport, the look button, the mini player\'s tap', wakes.sort(), [
    'app/App.tsx: openSheet: resumeDeckAudio',
    'player/NowPlaying.tsx: onLook: wakeDeckAudio',
    'player/NowPlaying.tsx: onNext: wakeDeckAudio',
    'player/NowPlaying.tsx: onPrevious: wakeDeckAudio',
    'player/NowPlaying.tsx: onToggle: wakeDeckAudio',
    'player/Turntable.tsx: onRecordClick: wakeDeckAudio',
    'player/Turntable.tsx: onRelease: wakeDeckAudio',
  ])
  const made = files.filter((file) => /\bnew\s+(?:Context|AudioContext|webkitAudioContext)\b/.test(code(read(file))))
  check('...and made in one place, the deck', made, ['player/deck.ts'])
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
  const play = /const playSong = \([^)]*\) => \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('a song\'s tap plays its album from that song only when the album\'s songs are in hand',
    [/const album = song\.albumId \? ready\.get\(song\.albumId\) : undefined/.test(play), /if \(album && at >= 0\) \{\s*rememberPlayed\(album\)\s*actions\.playTracks\(album\.song!\.map\(\(each\) => toQueueTrack\(each, album\)\), at\)/.test(play)],
    [true, true])
  check('...nothing fetched or awaited in the tap - otherwise the album opens instead',
    [/\bawait\b|\.then\(|fetch|prefetchAlbum|searchLibrary/.test(play), /onOpenAlbum\(/.test(play)], [false, true])
  check('...and the albums are asked for as the answer lands, KEPT (a scroll can\'t call them off), kept only for the newest search',
    /for \(const id of albumsToPrefetch\(results\.songs\)\) \{\s*prefetchAlbum\(id, true\)\.then\(\s*\(album\) => \{\s*if \(request\.current\(\)\) setReady/.test(search), true)
  check('the song row\'s click is that tap, and its play mark only when it will play',
    [/onClick=\{\(\) => playSong\(song\)\}/.test(search), /\{plays \? <PlayIcon class="app-result-play" \/> : null\}/.test(search)], [true, true])
  check('album rows navigate, asking for the songs as the finger lands, as a tile does',
    /onPointerDown=\{\(\) => void prefetchAlbum\(album\.id\)\}\s*onPointerCancel=\{\(\) => dropPrefetch\(album\.id\)\}\s*onClick=\{\(\) => onOpenAlbum\(album\)\}/.test(search), true)
  const askLibrary = /function askLibrary\(term: string\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  const askMusicBrainz = /async function askMusicBrainz\(term: string\) \{([\s\S]*?)\n  \}/.exec(search)?.[1] ?? ''
  check('each half through its own latestOnly(), drawing only the newest answer',
    [/const libraryRequests = useMemo\(latestOnly, \[\]\)/.test(search), /const musicRequests = useMemo\(latestOnly, \[\]\)/.test(search),
      /const request = libraryRequests\.begin\(\)[\s\S]*if \(!request\.current\(\)\) return\s*setLibrary\(/.test(askLibrary),
      /const request = musicRequests\.begin\(\)[\s\S]*if \(!request\.current\(\)\) return\s*setMusicbrainz\(\{ state: 'done'/.test(askMusicBrainz),
      /catch \(reason\) \{\s*if \(!request\.current\(\) \|\| isAbort\(reason\)\) return/.test(askMusicBrainz)],
    [true, true, true, true, true])
  check('...with the fetch called off when superseded', [/searchLibrary\(term, request\.signal\)/.test(askLibrary), /fullySearch\(plan\.query, MUSICBRAINZ_LIMIT, false, request\.signal\)/.test(askMusicBrainz)], [true, true])
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
  check('...when the album page opens, and beside each MusicBrainz search, which waits a moment for its answer',
    [/const owned = useOwned\(true\)/.test(page), /const ownedAnswered = refreshOwned\(\)/.test(askMusicBrainz),
      /await Promise\.race\(\[ownedAnswered, wait\(OWNED_WAIT_MS\)\]\)/.test(askMusicBrainz)],
    [true, true, true])
  check('...and what MusicBrainz found is left out once, as drawn - never filtered again as the library\'s answer changes',
    [/shown: notInLibrary\(groups, ownedNow\(\)\?\.index \?\? null\)/.test(askMusicBrainz), /const found = musicbrainz\.state === 'done' \? musicbrainz\.shown : \[\]/.test(search)],
    [true, true])
  const picker = code(read('app/PressingPicker.tsx'))
  check('the pressing list is brought into view as it opens, and focus going nowhere doesn\'t close it',
    [/target\?\.focus\(\{ preventScroll: true \}\)\s*reveal\(target\)/.test(picker), /box\.scrollIntoView\(\{ block: 'nearest' \}\)/.test(picker),
      /if \(to && !root\.current\?\.contains\(to\)\) close\(false\)/.test(picker)],
    [true, true, true])
  check('the page\'s ONE solid purple button is Get (2.0.0-player.15); its picker and Search have none - a row\'s Get chip is tinted',
    [(code(read('app/ReleaseGroupPage.tsx')).match(/class="app-rg-get"/g) ?? []).length,
      ['app/ReleaseGroupPage.tsx', 'app/PressingPicker.tsx', 'app/Search.tsx'].filter((file) => /is-primary|app-primary/.test(code(read(file)))),
      /class=\{`app-result-get\b/.test(code(read('app/Search.tsx')))],
    [1, [], true])
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
  check('...the Sources element handed that, its opener, its own open and how it is drawn (2.0.0-player.19)',
    /<Sources open=\{sourcesOpen\} request=\{getting\} opener=\{sourcesOpener\} onClose=\{closeSources\} onQueued=\{gotten\} panel=\{panel\} \/>/.test(app), true)
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
    [/const onClose = \(\) => \{\s*state\.stop\(\)\s*closeSheet\(\)\s*\}/.test(sheet), /useSheet\(\{ open, onClose, lockClass: 'app-sources-open'/.test(sheet),
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
  check('the album page\'s chip row is drawn from the first frame, so a chip landing moves nothing below it',
    /<div class="app-album-chips">\s*<span class="app-held-badge">/.test(album), true)
  check('Search\'s held row opens the album you have with its credited artist, so the page\'s artist line holds its place',
    /const artist = creditName\(group\['artist-credit'\]\)\s*if \(album\) onOpenAlbum\(\{ id: album, name: group\.title \?\? '', \.\.\.\(artist \? \{ artist \} : \{\}\) \}\)/.test(code(read('app/Search.tsx'))), true)
  check('an artist\'s name that isn\'t a link is drawn plain: on an album page only once the album has said so, never in a flash',
    [/<p class=\{`pl-hero-artist\$\{album \? ' app-hero-plain' : ''\}`\}>\{artistName\}<\/p>/.test(album), /<p class="pl-hero-artist app-hero-plain">\{header\.artist\}<\/p>/.test(code(read('app/ReleaseGroupPage.tsx')))],
    [true, true])
  check('a row looking for its album fades: an artist\'s, Search\'s, a Done row',
    [/class=\{`app-artist-album\$\{opening === row\.key \? ' is-busy' : ''\}`\}/.test(page), /class=\{`app-result\$\{opening === group\.id \? ' is-busy' : ''\}`\}/.test(code(read('app/Search.tsx'))),
      /class=\{`app-done-open\$\{opening \? ' is-busy' : ''\}`\}/.test(code(read('app/JobCard.tsx')))],
    [true, true, true])
  check('Library\'s rows navigate: nothing there reaches a playback action, as a tile', [actionsIn(code(read('player/Library.tsx'))), actionsIn(code(read('app/LibraryViews.tsx')))], [[], []])
  const library = code(read('player/Library.tsx'))
  check('Songs only where Navidrome\'s empty search lists songs: asked once, for one, the chip left out on an empty answer (and the albums shown)',
    //? (2.0.0-player.19: told to the Library's store, app/libraryPick.ts, which the desktop sidebar reads too)
    [/librarySongs\(0, 1, request\.signal\)\.then\(\s*\(songs\) => \{\s*if \(request\.current\(\)\) setLibrarySongs\(songs\.length > 0\)/.test(library),
      /const views = VIEWS\.filter\(\(entry\) => entry\.id !== 'songs' \|\| hasSongs !== false\)/.test(library),
      /const showing: LibraryView = view === 'songs' && hasSongs === false \? 'albums' : view/.test(library)],
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
      /\[status, arriving, arrivingTrouble, homeShown\]/.test(app)],
    [true, true, true, true])
  check('...the shelves drawn once the pins have answered, or failed, or the wait - counted only while Home shows - is over',
    [/const ready = pins !== null \|\| problem !== null \|\| waited/.test(home), /<div class="app-home-shelves" hidden=\{!ready\}>/.test(home), /if \(!shown \|\| waited\) return/.test(home)], [true, true, true])
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
  check('...and nothing but Now Playing draws the turntable', files.filter((file) => /<Turntable\s/.test(code(read(file)))), ['player/NowPlaying.tsx'])
  //? a side panel is no sheet over the page: Sources and Info take how they are drawn from App, and
  //? are modal only as a sheet
  const sheet = code(read('app/Sources.tsx'))
  const info = code(read('app/InfoSheet.tsx'))
  check('Sources and Info: modal only as a sheet, the page beside a panel left as it is',
    [/<InfoSheet\b[^>]*\bpanel=\{panel\}/.test(app.replace(/\n\s*/g, ' ')),
      [sheet, info].map((text) => /const modal = panelIsModal\(panel\)/.test(text) && /useSheet\(\{[^}]*\bmodal, area: box \}\)/.test(text)),
      /export function panelIsModal\(panel: PanelStyle\): boolean \{\s*return panel === 'sheet'\s*\}/.test(code(read('lib/appFrame.ts')))],
    [true, [true, true], true])
  check('one side panel at a time: Sources puts Info away, and Info Sources',
    [/setSourcesOpen\(true\)[\s\S]{0,200}?infoOpener\.current = null\s*setInfoPanel\(false\)/.test(/const openSources = useCallback[\s\S]*?\}, \[\]\)/.exec(app)?.[0] ?? ''),
      /infoOpener\.current = takeOpener\(event\)\s*sourcesOpener\.current = null\s*setSourcesOpen\(false\)\s*setInfoPanel\(true\)/.test(app)],
    [true, true])
  //? (review) the player bar's Info closes the panel it opened - "the Info button again"
  check('...and the player bar\'s Info, pressed again, closes it',
    /const toggleInfo = useCallback\(\(event: MouseEvent\) => \{\s*if \(infoPanelOpen\.current\) \{\s*setInfoPanel\(false\)\s*return\s*\}/.test(app), true)
  //? (review) which panel shows feeds both the shell's classes: room made for a column, a drawer over the page
  check('what the panel shows - Sources or Info - makes room for a column (`.has-side`) and marks a drawer (`.has-drawer`)',
    [/const side = sideOf\(frame, \{ sources: sourcesOpen, info: infoPanel \}\)/.test(app),
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
      /if \(request\.again\) \{\s*state\.start\(request\.release, false\)\s*return\s*\}/.test(sheet),
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
    [/const \{ pick, hasSongs \} = useLibraryPick\(\)/.test(library), /<h1 class="pl-large-title">\{desktop \? LIBRARY_TITLES\[drawn\] : 'Library'\}<\/h1>/.test(library),
      /<div hidden=\{drawn !== 'recent'\}>\s*<AlbumsView order="newest"/.test(library), /const choose = \(next: LibraryView\) => \{\s*if \(next !== showing\) chooseLibrary\(next\)/.test(library)],
    [true, true, true, true])
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
  check('opening beside needs both target and noopener',
    [opensBeside('<a href="/" target="_blank" rel="noopener">'), opensBeside('<a href="/" target="_blank">'), opensBeside('<a href="/" rel="noopener">')], [true, false, false])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
