/**
 * The app's gesture rules (2.0.0-player.9), read off the source - the rules that keep the engine
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
  'player/NowPlaying.tsx': ['toggle', 'next', 'previous', 'setGapless', 'showAirPlay'],
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
    'app/context.ts': ['next', 'playTracks', 'previous', 'setGapless', 'showAirPlay', 'toggle'],
    'player/AlbumPage.tsx': ['playTracks'],
    'player/MiniPlayer.tsx': ['next', 'toggle'],
    'player/NowPlaying.tsx': ['next', 'previous', 'setGapless', 'showAirPlay', 'toggle'],
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
  check('...which Now Playing is not in', /<NowPlaying\b[^>]*\/>\s*<\/div>\s*<\/ActionsContext/.test(app), true)
  check('focus given back to what opened it as it closes', /opener\.current\.focus\(/.test(app), true)
  const sheet = code(read('player/NowPlaying.tsx'))
  check('Now Playing takes focus to its close button as it opens',
    [/if \(open\) closeButton\.current\?\.focus\(/.test(sheet), /<button ref=\{closeButton\}[^>]*class="pl-sheet-close"/.test(sheet)], [true, true])
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
