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
    'app/GaplessChoice.tsx': ['setGapless'],
    'app/context.ts': ['next', 'playTracks', 'previous', 'setGapless', 'showAirPlay', 'toggle'],
    'player/AlbumPage.tsx': ['playTracks'],
    'player/MiniPlayer.tsx': ['next', 'toggle'],
    'player/NowPlaying.tsx': ['next', 'previous', 'showAirPlay', 'toggle'],
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
    [/const playingId = player\.track\?\.id \?\? null/.test(app), /\[nav, status, playingId, player\.playing\],\s*\)/.test(app), /\[nav, player, status\]/.test(app)], [true, true, false])
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
  check('...and there are links to look at (You, Search and Requests, the gate)',
    [...new Set(out.map(([file]) => file))].sort(), ['app/NeedsNavidrome.tsx', 'app/Placeholder.tsx', 'app/You.tsx'])
}

console.log('\nNow Playing covers everything behind it')
{
  const app = code(read('app/App.tsx'))
  const behind = /<div class="app-behind" aria-hidden=\{sheetOpen\} inert=\{sheetOpen\}>([\s\S]*?)<\/div>\s*<NowPlaying/.exec(app)
  check('the panes, the mini player and the tab bar are inside one inert wrapper',
    [!!behind, /TABS\.map/.test(behind?.[1] ?? ''), /<MiniPlayer\b/.test(behind?.[1] ?? ''), /<TabBar\b/.test(behind?.[1] ?? '')], [true, true, true, true])
  check('...which Now Playing, its menu and Info are not in',
    /<\/div>\s*<NowPlaying\b[\s\S]*?\/>\s*(?:\{\/\*[\s\S]*?\*\/\}\s*)?<ActionMenu\b[\s\S]*?\/>\s*<InfoSheet\b[\s\S]*?\/>\s*<\/div>\s*<\/ActionsContext/.test(read('app/App.tsx')), true)
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
  const SHEETS = { 'player/NowPlaying.tsx': 'pl-sheet-open', 'app/ActionMenu.tsx': 'app-menu-open', 'app/InfoSheet.tsx': 'app-info-open' }
  const texts = Object.fromEntries(Object.keys(SHEETS).map((file) => [file, code(read(file))]))
  check('each calls useSheet with a scroll lock of its own',
    Object.fromEntries(Object.entries(texts).map(([file, text]) => [file, /useSheet\(\{[^}]*lockClass: '([^']+)'/.exec(text)?.[1] ?? null])), SHEETS)
  check('...and they are the only ones', files.filter((file) => /\buseSheet\(/.test(code(read(file))) && file !== 'app/useSheet.ts').sort(), Object.keys(SHEETS).sort())
  check('each is inert while closed', Object.values(texts).map((text) => /\binert=\{!open\b/.test(text)), [true, true, true])
  check('Now Playing is inert under the menu or Info, and they are hidden from it', /aria-hidden=\{!open \|\| covered\}\s*inert=\{!open \|\| covered\}/.test(texts['player/NowPlaying.tsx']), true)
  check('the menu and Info close on their backdrop',
    ['app/ActionMenu.tsx', 'app/InfoSheet.tsx'].map((file) => /<div class="app-backdrop" onClick=\{onClose\} \/>/.test(texts[file])), [true, true])
  check('the hook: the lock on <html>, focus in, focus back, Escape for the one on top',
    [/document\.documentElement\.classList\.toggle\(lockClass, open\)/.test(hook),
      /first\.current\?\.focus\(/.test(hook),
      /opener\?\.current\?\.focus\(/.test(hook),
      /if \(!open \|\| covered\) return/.test(hook) && /event\.key !== 'Escape'/.test(hook)], [true, true, true, true])
  check('an opener focuses itself before it is taken (the WebKit rule)', /target\.focus\(\{ preventScroll: true \}\)\s*return target/.test(hook), true)
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
      has('InfoSheet', /\bopener=\{moreOpener\}/)], [true, true, true])
  check('never both over Now Playing, and neither without it',
    [has('ActionMenu', /\bopen=\{sheetOpen && over === 'menu'\}/), has('InfoSheet', /\bopen=\{sheetOpen && over === 'info'\}/),
      has('NowPlaying', /\bcovered=\{over !== 'none'\}/)], [true, true, true])
  //? "Go to album", from the menu, the album line and Info's card alike: every sheet closes (with no
  //? focus sent back to ••• in a sheet that is going), and the album opens on the tab showing
  const going = /const goToAlbum = \(track[^)]*\) => \{([\s\S]*?)\n  \}/.exec(app)?.[1] ?? ''
  check('Go to album closes every sheet and opens the album the way a tile does',
    [/moreOpener\.current = null\s*closeSheet\(\)\s*openAlbum\(/.test(going), /const closeSheet = useCallback\(\(\) => \{\s*setOver\('none'\)\s*setSheetOpen\(false\)/.test(app)],
    [true, true])
  check('...one handler for all three, each in its own props', ['NowPlaying', 'ActionMenu', 'InfoSheet'].map((tag) => has(tag, /\bonAlbum=\{toAlbum\b/)), [true, true, true])
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
  //? every player.seek in the file, by the handler it is in: the release and the arm's keys, never a move
  const handlers = [...table.matchAll(/const (\w+) = [^\n]*=> \{?[\s\S]*?\n  \}/g)].map((match) => [match[1], match[0]])
  check('it seeks only as a finger lets go or a key steps',
    handlers.filter(([, body]) => /player\.seek\(/.test(body)).map(([name]) => name).sort(), ['onArmKey', 'onRelease'])
  check('...and moving reaches the player not at all', /player\./.test(handlers.find(([name]) => name === 'onMove')?.[1] ?? 'player.'), false)
  check('no frame loop and nothing from the engine\'s clock: the spin is CSS, the arm usePosition',
    [/requestAnimationFrame|setInterval|setTimeout/.test(table), /usePosition\(player\)/.test(table), /visibilitychange/.test(table)], [false, true, true])
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
