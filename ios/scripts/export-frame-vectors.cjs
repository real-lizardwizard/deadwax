#!/usr/bin/env node
/**
 * The Mac app's desktop frame (slice 3 - notes/ios.md "The Mac app, slice 3: the desktop frame"): the web desktop's
 * frame and sidebar rules, written as a fixture the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/MacFrame.swift and
 * MacSidebar.swift) replays in Tests/DeadwaxCoreTests/MacFrameVectorTests.swift, so the Mac's frame is the web's.
 *
 * Compiles, as export-gate-vectors.cjs does, lib/appFrame.ts, lib/appRoutes.ts, lib/playlists.ts and state/persisted.ts
 * with the repo's TypeScript (persisted.ts over a stand-in for localStorage), and runs them AS THEY ARE:
 * - frameFor at widths either side of both breakpoints, panelIsModal for each style;
 * - sideOf for the Mac's three panels (Info, Up Next, Lyrics) open in every combination, on either frame; makesRoom
 *   and liesOver for each style and each; closesOnCrossing both ways;
 * - the sidebar's rows (sidebarRows) for each side, with a library of your own and without; sideOfItem and foldOf for
 *   every item; sideShown and sideFlip for every item, side and whether a page is pushed above the view; foldCurrent
 *   for every fold, folds and item; manageHeadLabel; overLibraryView for stacks the Mac has (a section of All's at the
 *   foot, an album, a playlist); sidebarPlaylists for invented lists; playlistsMove for stacks and pages;
 * - the two choices kept on the device (readSidebarSide, readSidebarFolds, writeSidebarFolds) for raw values, and
 *   their keys;
 * and reads, out of the sources: Sidebar.tsx's group headings, its field's placeholder and the sidebar's name, and
 * app-desktop.css's frame sizes (the sidebar, the panel, the bar and its parts, the grid's cover, a phone page's
 * readable width). A pattern that no longer matches stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/frame/frame-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iosframe.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the
 * same bytes. Never edit the fixture by hand - change the TypeScript, then run this. Every playlist here is invented.
 *
 *   node ios/scripts/export-frame-vectors.cjs           write the fixture
 *   node ios/scripts/export-frame-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'frame', 'frame-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-frame-vectors.cjs'
const SOURCES = ['lib/appFrame.ts', 'lib/appRoutes.ts', 'lib/playlists.ts', 'state/persisted.ts']
const SIDEBAR = 'ui/src/app/Sidebar.tsx'
const CSS = 'interface/player/app-desktop.css'

const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex')
const madeFrom = Object.fromEntries(SOURCES.map((file) => [`ui/src/${file}`, sha256(fs.readFileSync(path.join(UI, 'src', file), 'utf8'))]))

/** A piece read out of a file by `pattern`: its match, hashed - the script stops when it is gone. */
function piece(file, pattern, what) {
  const found = pattern.exec(fs.readFileSync(path.join(REPO, file), 'utf8'))
  if (!found) throw new Error(`couldn't read ${what} out of ${file} - the web app's code moved; change this script with it`)
  madeFrom[`${file} ${what}`] = sha256(found[0])
  return found
}

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-frame-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

//? persisted.ts reads and writes the browser's storage: a stand-in, emptied for each case
const stored = new Map()
globalThis.localStorage = {
  getItem: (key) => (stored.has(key) ? stored.get(key) : null),
  setItem: (key, value) => { stored.set(key, String(value)) },
  removeItem: (key) => { stored.delete(key) },
}

const F = require(path.join(OUT, 'lib/appFrame.js'))
const R = require(path.join(OUT, 'lib/appRoutes.js'))
const P = require(path.join(OUT, 'lib/playlists.js'))
const S = require(path.join(OUT, 'state/persisted.js'))

/* ===== what is read out of the sources ===== */

function words() {
  const headings = {
    library: piece(SIDEBAR, /<h2 id="app-side-library" class="app-side-label">\s*(\w+)\s*<\/h2>/, 'the Library heading')[1],
    playlists: piece(SIDEBAR, /foldHead\('playlists', 'app-side-playlists', '([^']+)'\)/, 'the Playlists heading')[1],
    manage: piece(SIDEBAR, /foldHead\('manage', 'app-side-managing', '([^']+)', manageCount\)/, 'the Manage heading')[1],
  }
  return {
    headings,
    placeholder: piece(SIDEBAR, /placeholder="([^"]+)"/, "the field's placeholder")[1],
    sections: piece(SIDEBAR, /<nav class="app-side" aria-label="([^"]+)">/, "the sidebar's name")[1],
    SIDE_LABELS: F.SIDE_LABELS,
    LIBRARY_SIDES: F.LIBRARY_SIDES,
    SIDEBAR_PLAYLISTS: F.SIDEBAR_PLAYLISTS,
    SIDEBAR_YOURS_ROWS: F.SIDEBAR_YOURS_ROWS,
    SIDEBAR_ALL_ROWS: F.SIDEBAR_ALL_ROWS,
    MANAGE: [F.SIDEBAR_QUEUE, F.SIDEBAR_CARE, F.SIDEBAR_PEOPLE, F.SIDEBAR_SETTINGS, F.SIDEBAR_LOG],
    TAB_LABELS: { requests: R.TAB_LABELS.requests, you: R.TAB_LABELS.you },
  }
}

/** A size in app-desktop.css, in px - the first declaration of `token` (the desktop's own block). */
function token(name) {
  const escaped = name.replace(/[-]/g, '\\-')
  return Number(piece(CSS, new RegExp(`${escaped}:\\s*(\\d+)px;`), name)[1])
}

function sizes() {
  return {
    side: token('--app-desk-side'),
    panel: token('--app-desk-panel'),
    bar: token('--app-desk-bar'),
    barCover: token('--app-desk-bar-cover'),
    barSide: token('--app-desk-bar-side'),
    barSideWide: Number(piece(CSS, /@media \(min-width: 1280px\) \{\s*:root \{ --app-desk-bar-side: (\d+)px; \}/,
      "the bar's sides from 1280px")[1]),
    barPad: token('--app-desk-bar-pad'),
    barGap: token('--app-desk-bar-gap'),
    tileMin: token('--app-desk-tile-min'),
    contentMax: token('--app-desk-content-max'),
  }
}

/* ===== the cases ===== */

const STYLES = ['sheet', 'drawer', 'column']
const MAC_SIDES = ['none', 'upnext', 'lyrics', 'info']
const BOOLS = [false, true]
const ITEMS = ['home', 'requests', 'recent', 'albums', 'artists', 'songs', 'store', 'storeArtists', 'playlists', 'queue',
  'care', 'people', 'settings', 'log', 'you', null]

function frames() {
  return [0, 375, 390, 768, 880, 1023, 1023.5, 1024, 1100, 1279, 1279.5, 1280, 1440, 1920, 2560]
    .map((width) => ({ width, ...F.frameFor(width) }))
}

function panels() {
  const shown = []
  for (const frame of ['phone', 'desktop']) {
    for (const info of BOOLS) for (const upnext of BOOLS) for (const lyrics of BOOLS) {
      const open = { sources: false, info, edit: false, artist: false, upnext, lyrics }
      shown.push({ frame, info, upnext, lyrics, side: F.sideOf(frame, open) })
    }
  }
  const room = []
  for (const panel of STYLES) for (const side of MAC_SIDES) {
    room.push({ panel, side, makesRoom: F.makesRoom(panel, side), liesOver: F.liesOver(panel, side) })
  }
  return {
    modal: STYLES.map((panel) => ({ panel, modal: F.panelIsModal(panel) })),
    shown,
    room,
    crossing: { desktop: F.closesOnCrossing('desktop'), phone: F.closesOnCrossing('phone') },
  }
}

function sidebar() {
  const rows = []
  for (const personal of BOOLS) for (const side of F.LIBRARY_SIDES) {
    rows.push({ side, personal, rows: F.sidebarRows(side, null, personal) })
  }
  const items = ITEMS.map((item) => ({ item, side: F.sideOfItem(item), fold: F.foldOf(item) }))
  const shown = [], flips = []
  for (const current of ITEMS) for (const side of F.LIBRARY_SIDES) for (const over of BOOLS) {
    shown.push({ current, remembered: side, over, side: F.sideShown(current, side, over) })
    flips.push({ current, to: side, over, opens: F.sideFlip(current, side, over) })
  }
  const folds = []
  for (const playlists of BOOLS) for (const manage of BOOLS) {
    for (const fold of ['playlists', 'manage']) for (const current of ITEMS) {
      folds.push({ fold, folds: { playlists, manage }, current, marked: F.foldCurrent(fold, { playlists, manage }, current) })
    }
  }
  const heads = []
  for (const folded of BOOLS) for (const needsLook of [null, 0, 1, 2, 3, 12, -1]) {
    heads.push({ folded, needsLook, label: F.manageHeadLabel(folded, needsLook) })
  }
  //? the stacks the Mac has: a section of All's at the Library's foot, an album or an artist, a playlist
  const section = (id) => ({ kind: 'section', id })
  const album = { kind: 'album', id: 'a1' }
  const artist = { kind: 'artist', id: 'r1' }
  const playlist = { kind: 'playlist', id: 'p1' }
  const stacks = [[], [section('store')], [section('storeArtists')], [section('songs')], [album], [artist], [playlist],
    [section('store'), album], [section('storeArtists'), artist, album], [playlist, album], [section('store'), playlist]]
  const over = []
  for (const tab of ['library', 'search', 'requests', 'you']) for (const stack of stacks) {
    over.push({ tab, stack, over: F.overLibraryView(tab, stack) })
  }
  return { rows, items, shown, flips, folds, heads, over }
}

/** An invented playlist: Navidrome's fields, as api/playlists.ts gives them. */
const pl = (id, name, over = {}) => ({
  id, name, comment: '', songCount: 3, duration: 600, created: '2026-11-01T10:00:00Z', changed: '2026-11-01T10:00:00Z',
  owner: 'james', public: false, coverArt: null, mine: true, editable: true, ...over,
})

function playlists() {
  const shared = (id, name) => pl(id, name, { owner: 'sam', mine: false, editable: false, public: true })
  const files = (id, name) => pl(id, name, { mine: true, editable: false })
  const many = Array.from({ length: 25 }, (_, i) => pl(`y${String(i).padStart(2, '0')}`, `Mix ${i}`))
  const lists = {
    none: null,
    empty: [],
    mixed: [shared('s1', 'Autumn'), pl('y1', 'Breakfast'), files('f1', 'Car'), pl('y2', 'Dinner'), shared('s2', 'Evening')],
    filesOnly: [files('f1', 'A'), files('f2', 'B')],
    many: [...many.slice(0, 12), shared('s1', 'Shared one'), ...many.slice(12)],
  }
  const listed = Object.entries(lists).map(([name, list]) => ({ name, list, shown: P.sidebarPlaylists(list) }))
  //? playlistsMove: the Library's stack and the page asked for
  const page = (kind, id) => ({ kind, id })
  const stacks = [[], [page('album', 'a1')], [page('playlist', 'p1')], [page('playlist', 'p2')],
    [page('playlist', 'p1'), page('playlist', 'p2')], [page('album', 'a1'), page('playlist', 'p2')],
    [page('playlist', 'p2'), page('album', 'a1')], [page('section', 'store'), page('playlist', 'p1')]]
  const moves = []
  for (const stack of stacks) {
    for (const asked of [page('playlist', 'p1'), page('playlist', 'p2'), page('playlist', 'p3')]) {
      moves.push({ stack, page: asked, how: R.playlistsMove(stack, asked) })
    }
  }
  return { max: P.SIDEBAR_PLAYLISTS_MAX, listed, moves }
}

function kept() {
  const sides = [null, '', 'all', 'yours', 'ALL', ' all', 'x'].map((raw) => {
    stored.clear()
    if (raw !== null) stored.set(S.STORAGE_KEYS.sidebarSide, raw)
    return { raw, side: S.readSidebarSide() }
  })
  const folds = [null, '', 'playlists', 'manage', 'playlists,manage', 'manage, playlists', ' manage ', 'playlists,,manage',
    'Playlists', 'x'].map((raw) => {
    stored.clear()
    if (raw !== null) stored.set(S.STORAGE_KEYS.sidebarFolded, raw)
    return { raw, folds: S.readSidebarFolds() }
  })
  const written = []
  for (const playlists of BOOLS) for (const manage of BOOLS) {
    stored.clear()
    S.writeSidebarFolds({ playlists, manage })
    written.push({ folds: { playlists, manage }, raw: stored.get(S.STORAGE_KEYS.sidebarFolded) })
  }
  stored.clear()
  return { keys: { side: S.STORAGE_KEYS.sidebarSide, folded: S.STORAGE_KEYS.sidebarFolded }, sides, folds, written }
}

/* ===== output: plain ASCII ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(json) {
  let out = ''
  for (let i = 0; i < json.length; i++) {
    const unit = json.charCodeAt(i)
    out += unit < 0x7f ? json[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}

function main() {
  const fixture = {
    made_by: MADE_BY,
    made_from: null,
    constants: { DESKTOP_MIN: F.DESKTOP_MIN, COLUMN_MIN: F.COLUMN_MIN },
    sizes: sizes(),
    words: words(),
    frames: frames(),
    panels: panels(),
    sidebar: sidebar(),
    playlists: playlists(),
    kept: kept(),
  }
  fixture.made_from = madeFrom
  fs.rmSync(OUT, { recursive: true, force: true })

  const LISTS = new Set(['frames'])
  const body = '{\n' + Object.entries(fixture).map(([key, value]) => {
    if (LISTS.has(key)) {
      return `  ${JSON.stringify(key)}: [\n` + value.map((one) => '    ' + ascii(JSON.stringify(one))).join(',\n') + '\n  ]'
    }
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return `  ${JSON.stringify(key)}: {\n` + Object.entries(value).map(([k, v]) => {
        if (Array.isArray(v)) {
          return '    ' + ascii(JSON.stringify(k)) + ': [\n' + v.map((one) => '      ' + ascii(JSON.stringify(one))).join(',\n') + '\n    ]'
        }
        return '    ' + ascii(JSON.stringify(k)) + ': ' + ascii(JSON.stringify(v))
      }).join(',\n') + '\n  }'
    }
    return `  ${JSON.stringify(key)}: ${ascii(JSON.stringify(value))}`
  }).join(',\n') + '\n}\n'
  const cases = fixture.frames.length + fixture.panels.shown.length + fixture.panels.room.length
    + fixture.sidebar.shown.length + fixture.sidebar.flips.length + fixture.sidebar.folds.length
    + fixture.sidebar.over.length + fixture.playlists.moves.length

  if (CHECK) {
    if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
      console.log(`The desktop frame's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
      console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
      process.exit(1)
    }
    console.log(`The desktop frame's fixture matches the web app's TypeScript (${cases} cases).`)
    return
  }
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${cases} cases, ${Math.round(body.length / 1024)} KB`)
}

try {
  main()
} catch (caught) {
  console.error(caught && caught.stack)
  process.exit(1)
}
