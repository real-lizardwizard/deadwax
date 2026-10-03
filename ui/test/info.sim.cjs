/**
 * Info, the ••• menu and Now Playing as sheets (2.0.0-player.10): Info > About's rows
 * (lib/aboutRows.ts), the store of albums played from (lib/playedAlbums.ts), and the three sheets
 * themselves - app/InfoSheet.tsx, app/ActionMenu.tsx and player/NowPlaying.tsx - compiled with the
 * repo's TypeScript and rendered by a small stand-in for Preact into plain objects, with a
 * document that knows which element has focus and which keys it is listening for.
 *
 * What it pins:
 *
 *  - About says what Navidrome sent and nothing it didn't: "Track 3 of 6 · 5:08" counted on the
 *    song's own disc, the disc's title as the album page heads it ("Disc 2 · Unreleased Tracks"),
 *    the album's year, format and song count, the album's own artist when it isn't the song's -
 *    and each left out when it wasn't sent, never guessed. An album not in hand leaves only what
 *    the queue knows.
 *  - The albums played from are kept, the newest last, and only PLAYED_KEPT of them - but every album
 *    of an artist's Play (a queue of several, up to QUEUE_ALBUMS_KEPT), the first to play kept
 *    longest, until the next queue starts (2.0.0-player.17, review).
 *  - About filled in (2.0.0-player.17): the card goes to the song's own artist - the album's only when
 *    that is the same person - and draws only that artist's facts and count; the folder is a row of
 *    its own at the end, in no button. useInfoDetails (app/useInfoDetails.ts) holds the song's and
 *    the store's answers back for each other (or INFO_SETTLE_MS), and of two artists says the
 *    album's is the card's only when their MusicBrainz ids are one.
 *  - Every sheet is a sheet (app/useSheet.ts): its own class on <html> while open, focus in as it
 *    opens, focus BACK to what opened it as it closes - by Done, Escape or the backdrop - Escape
 *    for the sheet on top only, and inert while closed. The menu doesn't give focus back when it
 *    closes because Info is opening; Info does, later.
 *  - Info's tabs: About first, Debug beside it, a tab list the arrows move round; Debug asks how
 *    the song was sent only when it is drawn; what was drawn stays drawn as the sheet slides away;
 *    its list is back at the top as it opens and as the tab changes, and not as it closes.
 *  - Now Playing is inert and deaf to Escape while the menu or Info is over it.
 *  - The menu's album pin (2.0.0-player.18): "Pin album to Home" or "Unpin album from Home" after Go
 *    to album, its tap handed to App; drawn but doing nothing until it is known whether the album is
 *    pinned, so no row moves as that lands; no row for an album that can't be pinned. The ••• button
 *    names what the menu holds: "More: info, go to album, pin" only when App says the menu will have
 *    the pin (`pinnable`) - "More: info, go to album" for an album with no release id, or while
 *    deadwax can't keep pins.
 *
 * Run it with:  node ui/test/info.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-info-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/InfoSheet.tsx', 'src/app/ActionMenu.tsx', 'src/player/NowPlaying.tsx', 'src/lib/playedAlbums.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the same stand-in as
//? settings.sim.cjs. Effects (layout ones too) run after a render whose deps changed.
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => {
    const outer = current; current = root; root.cursor = 0
    try { return component(props) } finally { current = outer }
  }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)
//? what the sheets draw inside them is not what is tested here: covers and glyphs stand in, and the
//? engine's position hook reads 0
fs.writeFileSync(path.join(OUT, 'player/Cover.js'), 'exports.Cover = function Cover() { return null }\n')
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `
const glyph = (name) => { const f = function () { return null }; Object.defineProperty(f, 'name', { value: name }); return f }
for (const name of ['ChevronRightIcon', 'ChevronDownIcon', 'AirPlayIcon', 'MoreIcon', 'NextIcon', 'PauseIcon', 'PlayIcon', 'PreviousIcon', 'CheckIcon', 'RecordIcon', 'SquareIcon']) exports[name] = glyph(name)
`)
fs.writeFileSync(path.join(OUT, 'player/usePlayer.js'), 'exports.usePosition = () => 0\n')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== a document that knows what has focus, and what listens for keys ===== */

class FakeElement {
  constructor(name) {
    this.name = name
    this.classes = new Set()
    this.classList = { toggle: (c, on) => (on ? this.classes.add(c) : this.classes.delete(c)) }
  }
  //? focus moves only when asked for - a tap doesn't, as in WebKit
  focus() { document.activeElement = this }
  querySelector() { return null }
}
const listeners = new Map()
const document = {
  body: new FakeElement('body'),
  documentElement: new FakeElement('html'),
  activeElement: null,
  addEventListener: (name, fn) => listeners.set(name, [...(listeners.get(name) ?? []), fn]),
  removeEventListener: (name, fn) => listeners.set(name, (listeners.get(name) ?? []).filter((f) => f !== fn)),
}
document.activeElement = document.body
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('document', document)
define('HTMLElement', FakeElement)

/** A key pressed, as the browser sends it to the document: every listener, in the order added. */
function press(key, { prevented = false } = {}) {
  const event = { key, defaultPrevented: prevented, preventDefault() { this.defaultPrevented = true } }
  for (const listener of [...(listeners.get('keydown') ?? [])]) listener(event)
  return event
}
const locks = () => [...document.documentElement.classes].sort()

/* ===== rendering ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

//? each element of a tree, found by where it sits, keeps one FakeElement across renders; a ref names it
function mount(component, name) {
  const render = hooks.root(component)
  const elements = new Map()
  let tree = null
  const walk = (node, where) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`)); return }
    if (typeof node.type === 'string') {
      const key = `${where}:${node.type}`
      if (!elements.has(key)) elements.set(key, new FakeElement(`${name} ${node.type} ${node.props.class ?? ''}`.trim()))
      node.element = elements.get(key)
      if (node.props.ref) node.props.ref.current = node.element
    }
    walk(node.props?.children, `${where}/`)
  }
  return {
    render(props) {
      tree = render(props)
      walk(tree, '')
      render.commit()
      return tree
    },
    find(test) {
      const hits = []
      const visit = (node) => {
        if (!node || typeof node !== 'object') return
        if (Array.isArray(node)) { node.forEach(visit); return }
        if (test(node)) hits.push(node)
        visit(node.props?.children)
      }
      visit(tree)
      return hits
    },
  }
}
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const one = (view, test) => view.find(test)[0]

/* ===== the songs ===== */

const DOT = String.fromCharCode(0xb7)
const { aboutRows, writtenBy, playedLine, labelLine } = require(path.join(OUT, 'lib/aboutRows.js'))
const { sharedFormat } = require(path.join(OUT, 'lib/format.js'))
const { createPlayedAlbums, PLAYED_KEPT, QUEUE_ALBUMS_KEPT } = require(path.join(OUT, 'lib/playedAlbums.js'))

function queueTrack(overrides = {}) {
  return {
    id: 'd2t3', title: 'Wish You Were Here (Live at Wembley)', artist: 'Pink Floyd', album: 'Wish You Were Here',
    albumId: 'wywh', coverArt: 'cover-wywh', duration: 308, contentType: 'audio/flac', suffix: 'flac',
    sampleRate: 44100, bitDepth: 16, channels: 2, ...overrides,
  }
}
const song = (id, disc, track, extra = {}) => ({ id, discNumber: disc, track, duration: 300, suffix: 'flac', artist: 'Pink Floyd', ...extra })
//? the Experience edition: five songs on disc 1, six on disc 2 - the second disc titled
const EXPERIENCE = {
  id: 'wywh', name: 'Wish You Were Here', artist: 'Pink Floyd', year: 1975, coverArt: 'cover-wywh',
  song: [
    ...[1, 2, 3, 4, 5].map((n) => song(`d1t${n}`, 1, n)),
    ...[1, 2, 3, 4, 5, 6].map((n) => song(`d2t${n}`, 2, n, n === 3 ? { duration: 308 } : {})),
  ],
  discTitles: [{ disc: 2, title: 'Unreleased Tracks' }],
}

console.log('\nAbout: the song')
{
  const about = aboutRows(queueTrack(), EXPERIENCE)
  check('title and artist', [about.song.title, about.song.artist], ['Wish You Were Here (Live at Wembley)', 'Pink Floyd'])
  check('"Track 3 of 6" - of its own disc - with its length, then its disc\'s title', about.song.lines, [`Track 3 of 6 ${DOT} 5:08`, `Disc 2 ${DOT} Unreleased Tracks`])
  check('a song on the untitled disc of a titled set is "Disc 1"', aboutRows(queueTrack({ id: 'd1t2' }), EXPERIENCE).song.lines, [`Track 2 of 5 ${DOT} 5:00`, 'Disc 1'])
  const plain = { id: 'dummy', name: 'Dummy', artist: 'Portishead', year: 1994, song: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((n) => song(`t${n}`, undefined, n)) }
  check('an ordinary one-disc album: no disc line', aboutRows(queueTrack({ id: 't4', album: 'Dummy', albumId: 'dummy' }), plain).song.lines, [`Track 4 of 11 ${DOT} 5:00`])
  const titledOne = { ...plain, song: plain.song.map((s) => ({ ...s, discNumber: 1 })), discTitles: [{ disc: 1, title: 'Live' }] }
  check('a one-disc album with a title: its heading', aboutRows(queueTrack({ id: 't4' }), titledOne).song.lines, [`Track 4 of 11 ${DOT} 5:00`, `Disc 1 ${DOT} Live`])
  const straight = { ...EXPERIENCE, song: EXPERIENCE.song.map((s, i) => ({ ...s, track: i + 1 })) }
  check('numbered straight through the set: counted against the whole album', aboutRows(queueTrack({ id: 'd2t3' }), straight).song.lines[0], `Track 8 of 11 ${DOT} 5:08`)
  //? a partly filed album keeps its real numbers: track 14 in an answer of three songs
  const partial = { ...plain, song: [song('p1', undefined, 1), song('p5', undefined, 5), song('p14', undefined, 14)] }
  check('a number past even the album\'s count: the count left out, not "of 3"', aboutRows(queueTrack({ id: 'p14' }), partial).song.lines, [`Track 14 ${DOT} 5:00`])
  check('no track number: only the length', aboutRows(queueTrack({ id: 'x' }), { ...plain, song: [{ id: 'x', duration: 61 }] }).song.lines, ['1:01'])
  check('no length either: nothing made up', aboutRows(queueTrack({ id: 'x', duration: 0 }), { ...plain, song: [{ id: 'x' }] }).song.lines, [])
  check('the album not in hand: only what the queue knows', aboutRows(queueTrack(), null).song.lines, ['5:08'])
}

console.log('\nAbout: the album and the artist')
{
  const about = aboutRows(queueTrack(), EXPERIENCE)
  check('the card: where it goes, its title, cover, and year, format and songs', about.album, { id: 'wywh', title: 'Wish You Were Here', coverArt: 'cover-wywh', line: `1975 ${DOT} FLAC ${DOT} 11 songs` })
  check('no year sent: left out, not guessed', aboutRows(queueTrack(), { ...EXPERIENCE, year: undefined }).album.line, `FLAC ${DOT} 11 songs`)
  check('...nor a year of 0', aboutRows(queueTrack(), { ...EXPERIENCE, year: 0 }).album.line, `FLAC ${DOT} 11 songs`)
  check('mixed formats: no format', aboutRows(queueTrack(), { ...EXPERIENCE, song: [song('a', 1, 1), song('d2t3', 1, 2, { suffix: 'mp3' })] }).album.line, `1975 ${DOT} 2 songs`)
  check('one song', aboutRows(queueTrack(), { ...EXPERIENCE, song: [song('d2t3', 1, 1)] }).album.line, `1975 ${DOT} FLAC ${DOT} 1 song`)
  check('not in hand: the queue\'s title and cover, no line', aboutRows(queueTrack(), null).album, { id: 'wywh', title: 'Wish You Were Here', coverArt: 'cover-wywh', line: '' })
  //? the queue carries the SONG's cover id (Navidrome ids them per file); the card is the album's
  check('the album\'s own cover over the song\'s', aboutRows(queueTrack({ coverArt: 'mf-d2t3' }), { ...EXPERIENCE, coverArt: 'al-wywh' }).album.coverArt, 'al-wywh')
  check('...and the song\'s only when the album sent none', aboutRows(queueTrack({ coverArt: 'mf-d2t3' }), { ...EXPERIENCE, coverArt: undefined }).album.coverArt, 'mf-d2t3')
  check('a song count sent without the songs', aboutRows(queueTrack(), { id: 'wywh', name: 'Wish You Were Here', year: 1975, songCount: 10 }).album.line, `1975 ${DOT} 10 songs`)
  check('no album id: a card that goes nowhere', aboutRows(queueTrack({ albumId: null }), null).album.id, null)
  check('no album named at all: no card', aboutRows(queueTrack({ album: '', albumId: null }), null).album, null)
  check('the artist, the same as the album\'s: no note', about.artist, { name: 'Pink Floyd', note: null })
  const various = { ...EXPERIENCE, artist: 'Various Artists', song: EXPERIENCE.song.map((s) => (s.id === 'd2t3' ? { ...s, artist: 'Pink Floyd' } : s)) }
  check('a compilation: the album\'s own artist noted', aboutRows(queueTrack(), various).artist, { name: 'Pink Floyd', note: 'The album is by Various Artists' })
  check('...case and spaces are not a difference', aboutRows(queueTrack(), { ...EXPERIENCE, artist: ' pink floyd ' }).artist.note, null)
  check('nobody named one: no artist', aboutRows(queueTrack({ artist: '' }), null).artist, null)
  check('the one format every song is in, or none', [sharedFormat([{ suffix: 'flac' }, { suffix: 'FLAC' }]), sharedFormat([{ suffix: 'flac' }, {}]), sharedFormat([])], ['FLAC', null, null])
}

console.log('\nAbout filled in (2.0.0-player.17): what Info asks for as it opens')
const WITH_IDS = { ...EXPERIENCE, artistId: 'ar-floyd', recordLabels: [{ name: 'Harvest' }, { name: ' Harvest ' }, { name: 'EMI' }] }
const DETAILS = {
  song: { id: 'd2t3', playCount: 12, displayComposer: 'Roger Waters, David Gilmour' },
  store: { present: [{ edition: 'Experience edition', year: '2011', formats: ['flac'], path: 'Pink Floyd/Wish You Were Here (1975) [Experience edition]' }] },
  artist: { id: 'ar-floyd', albumCount: 4 },
  facts: { type: 'Group', area: 'United Kingdom', begin_area: 'London', country: 'GB', began: '1965', ended: true, ended_on: '2014', disambiguation: '' },
}
{
  const full = aboutRows(queueTrack(), WITH_IDS, DETAILS)
  check('the song: "played 12 times" on its first line, and who wrote it', [full.song.lines[0], full.song.writtenBy],
    [`Track 3 of 6 ${DOT} 5:08 ${DOT} played 12 times`, 'Roger Waters, David Gilmour'])
  check('the album: its labels after the year, each once; this pressing; its folder', [full.album.line, full.album.pressing, full.album.folder],
    [`1975 ${DOT} Harvest / EMI ${DOT} FLAC ${DOT} 11 songs`, `This pressing: Experience edition ${DOT} 2011 ${DOT} FLAC`, 'Pink Floyd/Wish You Were Here (1975) [Experience edition]'])
  check('the artist: whose page the card goes to, who they are, how many of theirs you have', full.artist,
    { name: 'Pink Floyd', note: null, id: 'ar-floyd', pageName: 'Pink Floyd', facts: `Group ${DOT} London ${DOT} 1965 to 2014`, count: '4 albums in your library' })
  const renamed = { ...WITH_IDS, artist: 'Ye', song: WITH_IDS.song.map((each) => ({ ...each, artist: 'Kanye West' })) }
  check('a renamed artist\'s old credit: the card names the song\'s artist, and goes to the album\'s, by its name',
    [aboutRows(queueTrack({ artist: 'Kanye West' }), renamed).artist.name, aboutRows(queueTrack({ artist: 'Kanye West' }), renamed).artist.pageName, aboutRows(queueTrack({ artist: 'Kanye West' }), renamed).artist.note],
    ['Kanye West', 'Ye', 'The album is by Ye'])
  check('the song\'s details are this song\'s only', aboutRows(queueTrack(), WITH_IDS, { ...DETAILS, song: { id: 'other', playCount: 99, displayComposer: 'X' } }).song,
    { title: 'Wish You Were Here (Live at Wembley)', artist: 'Pink Floyd', lines: [`Track 3 of 6 ${DOT} 5:08`, `Disc 2 ${DOT} Unreleased Tracks`] })
  check('...the album answer\'s count as it was at the tap, until Navidrome answers', aboutRows(queueTrack(), { ...WITH_IDS, song: WITH_IDS.song.map((each) => (each.id === 'd2t3' ? { ...each, playCount: 1 } : each)) }).song.lines[0],
    `Track 3 of 6 ${DOT} 5:08 ${DOT} played once`)
  check('...and Navidrome\'s answer over it, even one saying fewer', aboutRows(queueTrack(), { ...WITH_IDS, song: WITH_IDS.song.map((each) => (each.id === 'd2t3' ? { ...each, playCount: 5 } : each)) }, { song: { id: 'd2t3' } }).song.lines[0],
    `Track 3 of 6 ${DOT} 5:08`)
  check('the count of another artist is not this one\'s', aboutRows(queueTrack(), WITH_IDS, { ...DETAILS, artist: { id: 'ar-x', albumCount: 9 } }).artist.count, undefined)
  check('nothing sent: none of it - no "played 0 times", no empty pressing, no "unknown"',
    JSON.stringify(aboutRows(queueTrack(), EXPERIENCE, { song: { id: 'd2t3', playCount: 0, displayComposer: ' ' }, store: { present: [] }, artist: null, facts: null })),
    JSON.stringify(aboutRows(queueTrack(), EXPERIENCE)))
  //? whose card it is (review): the song's own artist, the album's only when that is them
  const compilation = { ...WITH_IDS, artist: 'Various Artists', artistId: 'ar-va', song: WITH_IDS.song.map((each) => (each.id === 'd2t3' ? { ...each, artist: 'Portishead', artistId: 'ar-portishead' } : each)) }
  const portishead = queueTrack({ artist: 'Portishead' })
  check('a compilation\'s track: the card is the song\'s artist\'s - their page, their name - the album\'s artist a note',
    [aboutRows(portishead, compilation).artist.id, aboutRows(portishead, compilation).artist.pageName, aboutRows(portishead, compilation).artist.note],
    ['ar-portishead', 'Portishead', 'The album is by Various Artists'])
  check('...and only their facts and count: the album artist\'s never drawn under the song\'s name', [
    aboutRows(portishead, compilation, { ...DETAILS, artist: { id: 'ar-portishead', albumCount: 3 } }).artist.count,
    aboutRows(portishead, compilation, { ...DETAILS, artist: { id: 'ar-other', albumCount: 37 } }).artist,
  ], ['3 albums in your library', { name: 'Portishead', note: 'The album is by Various Artists', id: 'ar-portishead', pageName: 'Portishead' }])
  const yeAlbum = { ...WITH_IDS, artist: 'Ye', artistId: 'ar-ye', song: WITH_IDS.song.map((each) => ({ ...each, artist: 'Kanye West', artistId: 'ar-kanye' })) }
  const kanye = queueTrack({ artist: 'Kanye West' })
  check('a renamed artist\'s old credit, two Navidrome artists: the song\'s until Info has asked, Ye\'s once it says they are one',
    [aboutRows(kanye, yeAlbum).artist.id, aboutRows(kanye, yeAlbum, { artist: { id: 'ar-ye', albumCount: 2 } }).artist.id, aboutRows(kanye, yeAlbum, { artist: { id: 'ar-ye', albumCount: 2 } }).artist.pageName],
    ['ar-kanye', 'ar-ye', 'Ye'])
  check('the card goes to the album\'s own artist, else the song\'s; neither, no id', [
    aboutRows(queueTrack(), { ...WITH_IDS, song: WITH_IDS.song.map((each) => ({ ...each, artistId: 'ar-song' })) }).artist.id,
    aboutRows(queueTrack(), { ...EXPERIENCE, song: EXPERIENCE.song.map((each) => (each.id === 'd2t3' ? { ...each, artistId: 'ar-song' } : each)) }).artist.id,
    'id' in aboutRows(queueTrack(), EXPERIENCE).artist], ['ar-floyd', 'ar-song', false])
  check('the writers: the one line, else the composers among the contributors, each once',
    [writtenBy({ displayComposer: ' Geoff Barrow ' }), writtenBy({ contributors: [{ role: 'composer', artist: { name: 'A' } }, { role: 'lyricist', artist: { name: 'B' } }, { role: 'Composer', artist: { name: 'A' } }] }), writtenBy(null)],
    ['Geoff Barrow', 'A', ''])
  check('the plays and the labels', [playedLine(1), playedLine(2), playedLine(0), playedLine(undefined), labelLine([{ name: '' }]), labelLine(undefined)],
    ['played once', 'played 2 times', '', '', '', ''])
}

console.log('\nthe albums played from')
{
  const played = createPlayedAlbums()
  for (let n = 1; n <= PLAYED_KEPT + 1; n++) played.remember({ id: `a${n}` })
  check(`only the last ${PLAYED_KEPT} kept`, [played.get('a1'), played.get('a2')?.id, played.get(`a${PLAYED_KEPT + 1}`)?.id], [null, 'a2', `a${PLAYED_KEPT + 1}`])
  played.remember({ id: 'a2', again: true })
  played.remember({ id: 'b' })
  check('played from again, it is the newest - the next one out is another', [played.get('a2')?.again, played.get('a3')], [true, null])
  check('no id is no album', [played.get(null), played.get(undefined), played.get('')], [null, null, null])

  //? 2.0.0-player.17: an artist's Play queues every album of theirs at once
  const queue = createPlayedAlbums()
  const twelve = Array.from({ length: PLAYED_KEPT + 4 }, (_, n) => ({ id: `q${n + 1}` }))
  queue.rememberQueue(twelve)
  check(`an artist's Play: every album it queues kept, past ${PLAYED_KEPT} - the first to play among them`,
    twelve.map((album) => queue.get(album.id)?.id ?? null), twelve.map((album) => album.id))
  queue.remember({ id: 'next' })
  check(`...until the next queue starts: back to ${PLAYED_KEPT}, the queue's first to play kept longest`,
    [queue.get('next')?.id, queue.get('q1')?.id, queue.get(`q${PLAYED_KEPT}`), queue.get(`q${PLAYED_KEPT - 1}`)?.id],
    ['next', 'q1', null, `q${PLAYED_KEPT - 1}`])
  const small = createPlayedAlbums(2, 3)
  small.rememberQueue([{ id: 'b1' }, { id: 'b2' }, { id: 'b3' }, { id: 'b4' }, { id: 'b5' }])
  check(`...and never more than QUEUE_ALBUMS_KEPT (${QUEUE_ALBUMS_KEPT}) of one: the first to play kept`, ['b1', 'b2', 'b3', 'b4', 'b5'].map((id) => !!small.get(id)), [true, true, true, false, false])
}

/* ===== the sheets ===== */

const { InfoSheet } = require(path.join(OUT, 'app/InfoSheet.js'))
const { ActionMenu } = require(path.join(OUT, 'app/ActionMenu.js'))
const { NowPlaying } = require(path.join(OUT, 'player/NowPlaying.js'))

const player = {
  track: queueTrack(), gapless: true, maxRate: '48000', gaps: [], lastSeek: null,
  wrapped: { id: 'd2t3', got: 'stream', resampled: null, hiRes: null },
  playing: true, buffering: false, duration: 308, error: null, airplay: false,
  toggle() {}, previous() {}, showAirPlay() {}, seek() {}, position: () => 0, onPosition: () => () => {},
}

console.log('\nInfo: opens with focus in, closes with focus back - by Escape, Done and the backdrop')
{
  const opener = new FakeElement('the ••• button')
  const openerRef = { current: null }
  let closes = 0
  let formats = 0
  const albumTaps = { count: 0, handler: () => { albumTaps.count += 1 } }
  const view = mount(InfoSheet, 'info')
  const draw = (open) => view.render({
    open, opener: openerRef, onClose: () => { closes += 1 }, onAlbum: albumTaps.handler, player, album: EXPERIENCE,
    sentFormat: () => { formats += 1; return 'raw' },
  })
  const layer = () => one(view, byClass('app-layer'))
  const done = () => one(view, byClass('app-info-done'))
  const reopen = () => {
    //? what App does in the ••• tap: the button focuses itself first, then is kept to give focus back to
    opener.focus()
    openerRef.current = opener
    draw(true)
  }

  document.activeElement = document.body
  draw(false)
  check('closed: inert and hidden, no scroll lock, focus left where it was',
    [layer().props.inert, layer().props['aria-hidden'], locks(), document.activeElement === document.body], [true, true, [], true])
  check('...and deaf to Escape', [press('Escape').defaultPrevented, closes], [false, 0])

  reopen()
  const dialog = one(view, (node) => node.props?.role === 'dialog')
  check('open: its own lock on <html>, and focus on Done', [locks(), document.activeElement === done().element], [['app-info-open'], true])
  check('a modal dialog named by its title', [dialog.props['aria-modal'], one(view, (node) => node.props?.id === dialog.props['aria-labelledby']) && text(one(view, (node) => node.props?.id === dialog.props['aria-labelledby']))], ['true', 'Info'])
  check('not inert while open', [layer().props.inert, layer().props['aria-hidden']], [false, false])

  const escape = press('Escape')
  check('Escape closes it, once, and takes the key', [closes, escape.defaultPrevented], [1, true])
  draw(false)
  check('...and focus goes back to the ••• button, the lock comes off', [document.activeElement === opener, locks()], [true, []])
  check('closed, it listens for Escape no longer', [press('Escape').defaultPrevented, closes], [false, 1])

  reopen()
  check('an Escape something else already took is left alone', [press('Escape', { prevented: true }).defaultPrevented, closes], [true, 1])
  done().props.onClick()
  check('Done closes it', closes, 2)
  draw(false)
  check('...focus back on •••', document.activeElement === opener, true)

  reopen()
  const backdrop = one(view, byClass('app-backdrop'))
  check('the backdrop takes a tap', typeof backdrop?.props.onClick, 'function')
  backdrop?.props.onClick?.()
  check('a tap on the backdrop closes it', closes, 3)
  draw(false)
  check('...focus back on •••', document.activeElement === opener, true)

  console.log('\nInfo: its two tabs')
  formats = 0
  reopen()
  const tabs = () => view.find((node) => node.props?.role === 'tab')
  const list = () => one(view, (node) => node.props?.role === 'tablist')
  check('About, then Debug; About chosen, and the only tab stop', tabs().map((tab) => [text(tab), tab.props['aria-selected'], tab.props.tabIndex]), [['About', true, 0], ['Debug', false, -1]])
  check('About draws the song, the album and the artist', view.find((node) => node.type === 'h3').map(text), ['The song', 'The album', 'The artist'])
  check('...the song\'s lines as About worked them out', view.find(byClass('app-info-line')).map(text).slice(0, 3), ['Pink Floyd', `Track 3 of 6 ${DOT} 5:08`, `Disc 2 ${DOT} Unreleased Tracks`])
  const card = one(view, (node) => node.type === 'button' && byClass('is-link')(node))
  const closesBefore = closes
  card.props.onClick()
  check('...the album\'s card goes to the album (App closes the sheets as it opens it)', [card.props.onClick === albumTaps.handler, albumTaps.count, closes - closesBefore], [true, 1, 0])
  check('About never asks how the song was sent', formats, 0)

  //? 2.0.0-player.17: filled in, the artist's card goes to their page - App closes the sheets as it opens it
  const artistTaps = []
  view.render({
    open: true, opener: openerRef, onClose: () => { closes += 1 }, onAlbum: albumTaps.handler, player, album: WITH_IDS,
    sentFormat: () => 'raw', details: DETAILS, onArtist: (artist) => artistTaps.push(artist),
  })
  const links = view.find((node) => node.type === 'button' && byClass('is-link')(node))
  check('filled in: the album\'s card and the artist\'s are both links', links.length, 2)
  links[1].props.onClick()
  check('...the artist\'s opens their page, by Navidrome\'s id, named as the card names them', artistTaps, [{ id: 'ar-floyd', name: 'Pink Floyd' }])
  check('...and the card says who they are and what you have of theirs', view.find(byClass('app-info-line')).map(text).filter((line) => /Group|in your library|Written|pressing/.test(line)),
    ['Written by Roger Waters, David Gilmour', `This pressing: Experience edition ${DOT} 2011 ${DOT} FLAC`, `Group ${DOT} London ${DOT} 1965 to 2014`, '4 albums in your library'])
  check('...the folder in monospace, a row of its own at the end - in no button, so it can be copied',
    [view.find(byClass('app-info-folder')).map((node) => [node.type, text(node), /app-mono/.test(node.props.class)]),
      links.flatMap((link) => view.find(byClass('app-info-folder')).filter((folder) => JSON.stringify(link).includes(JSON.stringify(folder.props.children)))).length,
      view.find((node) => node.type === 'h3').map(text)],
    [[['dd', 'Pink Floyd/Wish You Were Here (1975) [Experience edition]', true]], 0, ['The song', 'The album', 'The artist', 'In your library']])
  draw(true)

  tabs()[1].props.onClick()
  reopen()
  check('Debug chosen', tabs().map((tab) => [tab.props['aria-selected'], tab.props.tabIndex]), [[false, -1], [true, 0]])
  check('Debug draws its five sections - the turntable\'s sound among them since 2.0.0-player.14', view.find((node) => node.type === 'h3').map(text), ['The file', 'What this device is sent', 'Last song change and seek', 'The turntable', 'Navidrome sent'])
  check('...as labelled rows', view.find(byClass('app-kv-label')).map(text), ['Format', 'Sent as', 'Resampled', 'Why', 'Gapless', 'Gap', 'Last seek', 'Turntable sound', 'Song', 'On other songs', 'Album'])
  check('...Gapless on, in one stream', text(view.find(byClass('app-kv-value'))[4]), 'On, in one stream')
  check('Debug asked how the song was sent', formats > 0, true)

  //? the turntable's sound (2.0.0-player.14), as App hands it from the deck's report
  const deckView = mount(InfoSheet, 'info with the turntable')
  const drawDeck = () => deckView.render({
    open: true, opener: { current: null }, onClose() {}, onAlbum: null, player, album: EXPERIENCE, sentFormat: () => 'raw',
    turntable: { context: 'running', problem: null, voice: 'worklet', voiceWhy: null, window: { start: 42, end: 72, kind: 'FLAC', decodedAt: 48000, bytes: 3_400_000 },
      loading: false, refused: null, failed: null, fetched: 0, lastFetchAt: 0 },
  })
  drawDeck()
  deckView.find((node) => node.props?.role === 'tab')[1].props.onClick()
  drawDeck()
  const deckRow = deckView.find(byClass('app-kv-label')).findIndex((node) => text(node) === 'Turntable sound')
  check('Debug says the turntable\'s sound from what it is handed', text(deckView.find(byClass('app-kv-value'))[deckRow]), 'Ready: 0:42-1:12, FLAC, decoded at 48 kHz')
  //? closed, so its lock and its Escape are no part of the checks after this
  deckView.render({ open: false, opener: { current: null }, onClose() {}, onAlbum: null, player, album: EXPERIENCE, sentFormat: () => 'raw' })

  //? the arrows, as the browser sends them to the tab list: its element finds the tab of that data-tab
  const keyOn = (key) => {
    let prevented = false
    const currentTarget = {
      querySelector(selector) {
        const id = /\[data-tab="([^"]+)"\]/.exec(selector)?.[1]
        return tabs().find((tab) => tab.props['data-tab'] === id)?.element ?? null
      },
    }
    list().props.onKeyDown({ key, currentTarget, preventDefault() { prevented = true } })
    draw(true)
    return prevented
  }
  check('ArrowLeft goes back to About, and takes the focus with it', [keyOn('ArrowLeft'), tabs()[0].props['aria-selected'], document.activeElement === tabs()[0].element], [true, true, true])
  check('ArrowRight to Debug', [keyOn('ArrowRight'), tabs()[1].props['aria-selected']], [true, true])
  check('ArrowRight wraps round', [keyOn('ArrowRight'), tabs()[0].props['aria-selected']], [true, true])
  check('another key is left alone', [keyOn('a'), tabs()[0].props['aria-selected']], [false, true])

  console.log('\nInfo: its list starts at the top')
  const scroller = () => one(view, byClass('app-info-scroll')).element
  //? on About, scrolled down: the tab changing puts the list back at the top
  scroller().scrollTop = 400
  tabs()[1].props.onClick()
  draw(true)
  check('a change of tab starts the list at the top', scroller().scrollTop, 0)
  scroller().scrollTop = 900
  draw(false)
  check('closing leaves it where it is, while it slides away in sight', scroller().scrollTop, 900)
  reopen()
  check('opening again, on the tab it was left on, starts at the top', [tabs()[1].props['aria-selected'], scroller().scrollTop], [true, 0])
  scroller().scrollTop = 300
  draw(true)
  check('...and a render while open, nothing changed, leaves the scroll alone', scroller().scrollTop, 300)
  draw(false)

  reopen()
  formats = 0
  const before = view.find(byClass('app-kv-value')).map(text)
  draw(false)
  check('closing: what was drawn stays drawn as it slides away, and nothing is asked again',
    [view.find(byClass('app-kv-value')).map(text), formats], [before, 0])
  check('...the scroller is a tab panel named by the tab showing', [one(view, byClass('app-info-scroll')).props.role, one(view, byClass('app-info-scroll')).props['aria-labelledby']], ['tabpanel', 'app-info-tab-debug'])
}

console.log('\nthe ••• menu')
{
  const opener = new FakeElement('the ••• button')
  const openerRef = { current: opener }
  const calls = []
  const view = mount(ActionMenu, 'menu')
  const draw = (open, extra = {}) => view.render({
    open, opener: openerRef, onClose: () => calls.push('close'), onInfo: () => calls.push('info'), onAlbum: () => calls.push('album'), ...extra,
  })
  const items = () => view.find(byClass('app-menu-item'))
  draw(false)
  check('closed: inert, no lock', [one(view, byClass('app-layer')).props.inert, locks()], [true, []])
  opener.focus()
  draw(true)
  check('open: Info and Go to album, focus on the first, its own lock', [items().map(text), document.activeElement === items()[0].element, locks()], [['Info', 'Go to album'], true, ['app-menu-open']])
  items()[0].props.onClick()
  items()[1].props.onClick()
  check('each row calls its own', calls, ['info', 'album'])
  press('Escape')
  check('Escape closes it', calls.slice(-1), ['close'])
  draw(false)
  check('...focus back on •••', document.activeElement === opener, true)
  draw(true)
  const upTo = calls.length
  one(view, byClass('app-backdrop')).props.onClick?.()
  check('a tap on the backdrop closes it', calls.slice(upTo), ['close'])
  one(view, byClass('app-menu-cancel')).props.onClick?.()
  check('...and so does Cancel', calls.slice(upTo), ['close', 'close'])
  //? closing because Info is opening: App leaves the opener out, and Info gives focus back later
  const done = new FakeElement("Info's Done")
  done.focus()
  draw(false, { opener: undefined })
  check('closed for Info: focus is left to Info', document.activeElement === done, true)
  draw(true, { onAlbum: null })
  check('no album to go to: the row is left out, not greyed', items().map(text), ['Info'])
  //? the album's pin (2.0.0-player.18): App's, handed in - the menu only draws it and hands the tap on
  draw(true, { pinned: false, onPin: () => calls.push('pin') })
  check('an album that can be pinned: "Pin album to Home", after Go to album', items().map(text), ['Info', 'Go to album', 'Pin album to Home'])
  items()[2].props.onClick()
  check('...its tap handed to App', calls.slice(-1), ['pin'])
  draw(true, { pinned: true, onPin: () => calls.push('unpin') })
  items()[2].props.onClick()
  check('pinned already: "Unpin album from Home", the same row', [items().map(text)[2], calls.slice(-1)], ['Unpin album from Home', ['unpin']])
  const asked = calls.length
  draw(true, { pinned: null, onPin: () => calls.push('pin') })
  items()[2].props.onClick()
  check('not known yet whether it is: drawn - so nothing moves as it is known - aria-disabled, its tap doing nothing',
    [items().map(text)[2], items()[2].props['aria-disabled'], calls.length - asked], ['Pin album to Home', true, 0])
  draw(true, { pinned: false, onPin: null })
  check('an album that can\'t be pinned: no row for it', items().map(text), ['Info', 'Go to album'])
  draw(false)
  check('closed again: its lock off, and deaf to Escape', [locks(), press('Escape').defaultPrevented], [[], false])
}

console.log('\nNow Playing is a sheet too, and deaf under the others')
{
  const opener = new FakeElement('the mini player')
  const openerRef = { current: opener }
  let closes = 0
  const view = mount(NowPlaying, 'now playing')
  const draw = (open, covered = false) => view.render({
    player, open, covered, opener: openerRef, onClose: () => { closes += 1 }, onMore: () => {}, onAlbum: () => {}, openAs: 'cover', pinnable: true,
  })
  const sheet = () => one(view, byClass('pl-sheet'))
  const close = () => one(view, byClass('pl-sheet-close'))
  draw(false)
  opener.focus()
  draw(true)
  check('open: focus on its close arrow, its own lock', [document.activeElement === close().element, locks()], [true, ['pl-sheet-open']])
  draw(true, true)
  check('the menu or Info over it: inert and hidden, still open', [sheet().props.inert, sheet().props['aria-hidden'], locks()], [true, true, ['pl-sheet-open']])
  check('...and Escape is not for it', [press('Escape').defaultPrevented, closes], [false, 0])
  draw(true, false)
  check('uncovered, Escape closes it', [press('Escape').defaultPrevented, closes], [true, 1])
  draw(false)
  check('...and focus goes back to the mini player', [document.activeElement === opener, locks()], [true, []])
  check('the album line goes to the album', one(view, (node) => node.type === 'button' && byClass('pl-sheet-artist')(node)).props['aria-label'], 'Go to the album: Pink Floyd — Wish You Were Here')
  check('the icon row: ••• only, with no speaker to send to', view.find((node) => node.type === 'button' && byClass('pl-icon-button')(node)).map((button) => button.props['aria-label']), ['More: info, go to album, pin'])
  view.render({ player, open: true, covered: false, opener: openerRef, onClose() {}, onMore() {}, onAlbum() {}, openAs: 'cover', pinnable: false })
  check('...an album the menu has no pin for (no release id, or deadwax can\'t keep pins): ••• doesn\'t promise one',
    view.find((node) => node.type === 'button' && byClass('pl-icon-button')(node)).map((button) => button.props['aria-label']), ['More: info, go to album'])
  let albums = 0
  view.render({ player, open: true, covered: false, opener: openerRef, onClose() {}, onMore() {}, onAlbum: () => { albums += 1 }, openAs: 'cover' })
  one(view, (node) => node.type === 'button' && byClass('pl-sheet-artist')(node)).props.onClick()
  check('...and a tap on it asks App to go there', albums, 1)
  //? a song whose album the queue has no id for: the same line, as words that go nowhere
  const lone = { ...player, track: queueTrack({ albumId: null }), airplay: true }
  view.render({ player: lone, open: true, covered: false, opener: openerRef, onClose() {}, onMore() {}, onAlbum: () => { albums += 1 }, openAs: 'cover', pinnable: true })
  check('no album id: the line is words, not a button, in the same box',
    [view.find((node) => node.type === 'button' && byClass('pl-sheet-artist')(node)).length, one(view, (node) => node.type === 'p' && byClass('pl-sheet-artist')(node)) && text(one(view, byClass('pl-sheet-byline')))],
    [0, 'Pink Floyd — Wish You Were Here'])
  check('...••• says the menu holds only Info, and AirPlay sits before it with a speaker there',
    view.find((node) => node.type === 'button' && byClass('pl-icon-button')(node)).map((button) => button.props['aria-label']), ['AirPlay', 'More: info'])
  view.render({ player: { ...player, error: 'Skipped "Shine On" - it wouldn\'t play' }, open: true, covered: false, opener: openerRef, onClose() {}, onMore() {}, onAlbum() {}, openAs: 'cover' })
  const titles = one(view, byClass('pl-sheet-titles')).props.children.filter(Boolean)
  check('a failure is drawn above the title, never under it', titles.map((node) => node.props.class.split(' ')[0]), ['pl-sheet-error', 'pl-sheet-title', 'pl-sheet-artist'])
}

/* ===== what Info asks for as it opens: app/useInfoDetails.ts, with every answer given by hand ===== */

const DETAILS_OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-info-details-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/useInfoDetails.ts', '--rootDir', 'src', '--outDir', DETAILS_OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })
fs.mkdirSync(path.join(DETAILS_OUT, 'node_modules/preact'), { recursive: true })
fs.copyFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), path.join(DETAILS_OUT, 'node_modules/preact/hooks.js'))
fs.writeFileSync(path.join(DETAILS_OUT, 'api/musicbrainz.js'), 'exports.getArtistFacts = (mbid) => globalThis.__info.ask("facts", mbid)\n')
fs.writeFileSync(path.join(DETAILS_OUT, 'api/store.js'), 'exports.storeAlbum = (by) => globalThis.__info.ask("store", by.navidrome_id)\n')
fs.writeFileSync(path.join(DETAILS_OUT, 'player/api.js'), `
exports.songDetails = (id) => globalThis.__info.ask('song', id)
exports.artistAlbums = (id) => globalThis.__info.ask('artist', id)
`)
fs.writeFileSync(path.join(DETAILS_OUT, 'app/useOwned.js'), 'exports.ownedNow = () => null\n')

const I = globalThis.__info = {
  asks: [], open: [],
  ask(name, arg) {
    I.asks.push([name, arg])
    return new Promise((resolve, reject) => I.open.push({ name, arg, resolve, reject }))
  },
}
const reply = (name, value, arg) => {
  const at = I.open.findIndex((one) => one.name === name && (arg === undefined || one.arg === arg))
  if (at < 0) throw new Error(`nothing asked of ${name} ${arg ?? ''}`)
  I.open.splice(at, 1)[0].resolve(value)
}
const timers = []
const realSetTimeout = globalThis.setTimeout
globalThis.setTimeout = (fn) => { const timer = { fn, live: true }; timers.push(timer); return timer }
globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
const detailsHooks = require(path.join(DETAILS_OUT, 'node_modules/preact/hooks.js'))
const { useInfoDetails, INFO_SETTLE_MS } = require(path.join(DETAILS_OUT, 'app/useInfoDetails.js'))

/** The hook in a component of its own: what it hands back, drawn after each answer lands. */
function detailsOf(album, track) {
  const render = detailsHooks.root((props) => useInfoDetails(props.open, props.track, props.album))
  let out = null
  const draw = () => { out = render({ open: true, track, album }); render.commit(); return out }
  return { draw, async after() { await settle(); draw(); return draw() } }
}

async function details() {
  console.log('\nwhat Info asks for as it opens, and when it is drawn')
  {
    I.asks.length = 0; I.open.length = 0; timers.length = 0
    const album = { ...WITH_IDS, id: 'wywh' }
    const track = queueTrack({ albumId: 'wywh' })
    const info = detailsOf(album, track)
    info.draw()
    check('the song, the store and the artist asked for as it opens', I.asks.map((one) => one[0]).sort(), ['artist', 'song', 'store'])
    reply('song', { id: 'd2t3', playCount: 12 })
    check('the song\'s answer held back for the store\'s: nothing drawn yet', await info.after(), null)
    reply('store', { present: [{ path: 'Pink Floyd/Wish You Were Here (1975)' }] })
    const both = await info.after()
    check('...both drawn together once the store answers', [both?.song?.playCount, both?.store?.present.length], [12, 1])
    reply('artist', { id: 'ar-floyd', albumCount: 4, musicBrainzId: '83d91898-7763-47d7-b03b-b92132375c47' })
    const theirs = await info.after()
    check('the artist\'s answer drawn as it lands, then who they are asked of MusicBrainz', [theirs?.artist, I.asks.filter((one) => one[0] === 'facts').length], [{ id: 'ar-floyd', albumCount: 4 }, 1])

    I.asks.length = 0; I.open.length = 0
    const slow = detailsOf(album, queueTrack({ id: 'd2t3', albumId: 'wywh' }))
    slow.draw()
    reply('song', { id: 'd2t3', playCount: 3 })
    await slow.after()
    for (const timer of timers.splice(0)) if (timer.live) timer.fn()
    check(`a store answer slower than ${INFO_SETTLE_MS} ms: the song's drawn when the wait is over`, (await slow.after())?.song?.playCount, 3)
    reply('store', { present: [] })
    check('...and the store\'s as it lands after', (await slow.after())?.store?.present, [])
  }
  {
    I.asks.length = 0; I.open.length = 0
    const YE_ID = '164f0d73-1234-4e2c-8743-d77bf2191051'
    const yeAlbum = { ...WITH_IDS, id: 'donda', artist: 'Ye', artistId: 'ar-ye', song: WITH_IDS.song.map((each) => ({ ...each, artist: 'Kanye West', artistId: 'ar-kanye' })) }
    const renamed = detailsOf(yeAlbum, queueTrack({ artist: 'Kanye West', albumId: 'donda' }))
    renamed.draw()
    check('two artists of different names and ids: both asked about', I.asks.filter((one) => one[0] === 'artist').map((one) => one[1]).sort(), ['ar-kanye', 'ar-ye'])
    reply('artist', { id: 'ar-kanye', name: 'Kanye West', musicBrainzId: YE_ID, album: [] }, 'ar-kanye')
    reply('artist', { id: 'ar-ye', name: 'Ye', musicBrainzId: YE_ID, albumCount: 2, album: [] }, 'ar-ye')
    await renamed.after()
    for (const timer of timers.splice(0)) if (timer.live) timer.fn()
    check('...one MusicBrainz id: the card is the album\'s artist\'s, Ye', (await renamed.after())?.artist, { id: 'ar-ye', albumCount: 2 })

    I.asks.length = 0; I.open.length = 0
    const various = { ...WITH_IDS, id: 'comp', artist: 'Various Artists', artistId: 'ar-va', song: WITH_IDS.song.map((each) => ({ ...each, artist: 'Portishead', artistId: 'ar-portishead' })) }
    const comp = detailsOf(various, queueTrack({ artist: 'Portishead', albumId: 'comp' }))
    comp.draw()
    reply('artist', { id: 'ar-portishead', name: 'Portishead', musicBrainzId: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', albumCount: 3, album: [] }, 'ar-portishead')
    reply('artist', { id: 'ar-va', name: 'Various Artists', musicBrainzId: '89ad4ac3-39f7-470e-963a-56509c546377', albumCount: 37, album: [] }, 'ar-va')
    await comp.after()
    for (const timer of timers.splice(0)) if (timer.live) timer.fn()
    check('...two people: the card is the song\'s artist\'s, Portishead - never Various Artists\'', [(await comp.after())?.artist, I.asks.filter((one) => one[0] === 'facts').map((one) => one[1])],
      [{ id: 'ar-portishead', albumCount: 3 }, ['8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11']])

    I.asks.length = 0; I.open.length = 0
    const unsure = { ...WITH_IDS, id: 'comp2', artist: 'Various Artists', artistId: 'ar-va', song: WITH_IDS.song.map((each) => ({ ...each, artist: 'Portishead' })) }
    detailsOf(unsure, queueTrack({ artist: 'Portishead', albumId: 'comp2' })).draw()
    check('...no song artist known and the names differ: nobody\'s details asked for, to draw under the wrong name', I.asks.filter((one) => one[0] === 'artist').length, 0)
  }
  globalThis.setTimeout = realSetTimeout
}

details().then(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})
