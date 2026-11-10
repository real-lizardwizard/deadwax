/**
 * Playlists (2.0.0-player.58): the pure rules (lib/playlists.ts), the app's one list of them (app/usePlaylists.ts,
 * the real one, against a faked deadwax), the picker (app/PlaylistPicker.tsx), the Playlists page
 * (app/PlaylistsPage.tsx), a playlist's page (app/PlaylistPage.tsx) and its two leaves (app/NewPlaylistForm.tsx,
 * app/ConfirmLine.tsx) - compiled with the repo's TypeScript and rendered by a small stand-in for Preact into plain
 * objects, one component at a time: a child component is a node whose props are checked, and called.
 *
 * What it pins:
 *
 *  - The rules: the three groups in Navidrome's order; the picker's - editable only, changed last first; the
 *    sidebar's - yours then shared, capped, never From files; what each row, owner line and read-only line says; the
 *    albums a playlist's songs are remembered under (by first appearance, one stub an album however split, NO
 *    musicBrainzId key, none for a song without an album id); Edit's rows keyed by place, its moves and removals,
 *    and Done's body - only what changed, '' for a description cleared, nothing when nothing changed; the
 *    rearrangement rule the server holds; the page scrolling itself near an edge, and a drag counting that scroll;
 *    the words of an add, a made playlist and the duplicates question.
 *  - The store: nothing until asked; a held answer asks nothing without `fresh`; a newer ask supersedes an older
 *    (an answer landing late draws nothing); a failure keeps the last list; a write here asks again and tells a
 *    playlist page of its id; a page's answers kept, the last eight - an add here letting its answer go, a Done keeping
 *    what it answered.
 *  - The picker: asked afresh as it opens; New playlist… first, then yours by change; a tap asks (`ask`), one write
 *    at a time; done - the notice and closed; some there already - the question, its three wordings and what each
 *    button sends; refused - said, the sheet open, a gone playlist asking the list again; New playlist… makes it WITH
 *    the songs; its own sheet.
 *  - The Playlists page: the groups, From files folded behind "From files (N)" and opened in place, the empty notice
 *    with New playlist, a row opening its playlist and nothing else, New playlist opening what it made, Try again.
 *  - A playlist's page: the kept answer on the FIRST render, the newer one over it, Edit waiting for it (and after a
 *    409, a refused Done left, or an add here); the hero from the row that opened
 *    it otherwise; rows by place (a song twice drawn twice); Play, Shuffle and a row each remembering the albums then
 *    calling playTracks at once with the songs in hand; Edit only for yours and editable; the read-only, hidden, empty
 *    and gone words; Edit's fields, moves and removals said aloud, a drag landing where its distance - the page's
 *    scroll included - says; Done sending only what changed; a 409 closing Edit with the words and asking again; a
 *    failure keeping Edit and its changes; Cancel asking only when something changed; Delete's two steps.
 *
 * Run it with:  node ui/test/playlists.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-playlists-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/playlists.ts', 'src/app/usePlaylists.ts', 'src/app/PlaylistPicker.tsx', 'src/app/PlaylistsPage.tsx', 'src/app/PlaylistPage.tsx',
  'src/app/NewPlaylistForm.tsx', 'src/app/ConfirmLine.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - pins.sim.cjs's stand-in
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
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
exports.useCallback = (f) => f
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => { const outer = current; current = root; root.cursor = 0; try { return component(props) } finally { current = outer } }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  return render
}
`)

//? deadwax's playlist routes, the notice, the sheet and the player's helpers: every ask kept, answered when told
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('api/playlists.js', `
exports.playlists = () => globalThis.__pl.ask('list')
exports.playlist = (id) => globalThis.__pl.ask('one', id)
exports.createPlaylist = (name, ids) => globalThis.__pl.ask('create', { name, ids: [...ids] })
exports.addToPlaylist = (id, ids, duplicates) => globalThis.__pl.ask('add', { id, ids: [...ids], duplicates })
exports.editPlaylist = (id, body) => globalThis.__pl.ask('edit', { id, body })
exports.deletePlaylist = (id) => globalThis.__pl.ask('delete', id)
`)
write('api/http.js', `
//? (2.0.4) api/http.ts's shape: the route it answered (a playlist route: the music server's - lib/errorWords.ts), and
//? deadwax's own split (why), as the real one has them
class ApiError extends Error {
  constructor(status, detail, fallback = 'failed', busy = false, kind = null, why = null, path = '/navidrome/playlists') {
    super(detail || fallback); this.name = 'ApiError'; this.status = status; this.detail = detail; this.why = why; this.path = path
  }
}
exports.ApiError = ApiError
`)
write('app/usePins.js', `exports.sayPins = (text) => globalThis.__pl.calls.push(['sayPins', text])\n`)
write('app/useSheet.js', `exports.useSheet = (options) => { globalThis.__pl.sheets.push(options) }\nexports.takeOpener = () => null\n`)
write('player/Cover.js', `exports.Cover = function Cover(props) { return { type: 'img', props: { class: props.class, 'data-cover': props.id } } }\n`)
write('player/api.js', `
exports.rememberQueue = (albums) => {
  globalThis.__pl.remembered = albums
  globalThis.__pl.calls.push(['rememberQueue', albums.map((album) => album.id)])
}
exports.playedAlbum = (id) => globalThis.__pl.held.get(id) ?? null
exports.toQueueTrack = (song, fallback) => ({ id: song.id, title: song.title, artist: song.artist ?? '', album: song.album ?? fallback.name, albumId: song.albumId ?? fallback.id })
`)

const W = globalThis.__pl = {
  asks: [], open: [], calls: [], sheets: [], held: new Map(), remembered: null,
  ask(name, body) {
    W.asks.push(body === undefined ? [name] : [name, body])
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    W.open.push({ name, body, resolve, reject })
    return promise
  },
}
function answer(name, value, which = 0) {
  const all = W.open.filter((one) => one.name === name)
  const one = which === 'last' ? all[all.length - 1] : all[which]
  if (!one) throw new Error(`nothing asked of ${name}`)
  W.open.splice(W.open.indexOf(one), 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
const settle = async () => { for (let i = 0; i < 6; i++) await new Promise((resolve) => setImmediate(resolve)) }

//? what of a page the components touch
let scrollY = 0
const scrolled = []
globalThis.window = { get scrollY() { return scrollY }, scrollBy: (x, y) => { scrolled.push(y); scrollY += y }, scrollTo: (x, y) => { scrolled.push(['to', y]); scrollY = y }, innerHeight: 800 }
globalThis.document = { querySelectorAll: () => [] }
const frames = []
globalThis.requestAnimationFrame = (f) => { frames.push(f); return frames.length }
globalThis.cancelAnimationFrame = () => {}

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const L = require(path.join(OUT, 'lib/playlists.js'))
const S = require(path.join(OUT, 'app/usePlaylists.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const { PlaylistPicker } = require(path.join(OUT, 'app/PlaylistPicker.js'))
const { PlaylistsPage } = require(path.join(OUT, 'app/PlaylistsPage.js'))
const { PlaylistPage } = require(path.join(OUT, 'app/PlaylistPage.js'))
const { NewPlaylistForm } = require(path.join(OUT, 'app/NewPlaylistForm.js'))
const { ConfirmLine } = require(path.join(OUT, 'app/ConfirmLine.js'))

let failures = 0
let finished = false
process.on('exit', () => {
  if (!finished) {
    console.log('\nSTOPPED before the end - a check was left waiting')
    process.exitCode = 1
  }
})
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
function find(test, within) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  if (typeof node.type === 'function') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const byType = (type) => (node) => node.type === type

/* ===== the playlists deadwax answers with ===== */

const pl = (id, more = {}) => ({ id, name: id, comment: '', songCount: 3, duration: 600, created: '2026-10-01T00:00:00Z', changed: '2026-10-01T00:00:00Z',
  owner: 'james', public: false, coverArt: `pl-${id}_x`, mine: true, editable: true, ...more })
const song = (id, more = {}) => ({ id, title: `Song ${id}`, artist: 'Portishead', album: 'Dummy', albumId: 'dum', coverArt: 'al-dum', duration: 200, ...more })
const LATE = pl('Late night', { id: 'late', changed: '2026-10-20T10:00:00Z', public: true })
const ROAD = pl('Road trip', { id: 'road', changed: '2026-10-19T10:00:00Z' })
const ALPHA = pl('Alpha', { id: 'alpha', changed: '2026-10-19T10:00:00Z' })
const SUNDAY = pl('Sunday', { id: 'sunday', owner: 'ethan', mine: false, editable: false, songCount: 20, duration: 3900 })
const SMART = pl('Recently played', { id: 'smart', editable: false, songCount: 30 })
const LIST = [ALPHA, LATE, SMART, ROAD, SUNDAY]

;(async () => {

console.log('\nthe rules: whose, where, and what each row says')
{
  const groups = L.groupPlaylists(LIST)
  check('three groups, each in Navidrome\'s order', [groups.yours.map((p) => p.id), groups.shared.map((p) => p.id), groups.files.map((p) => p.id)],
    [['alpha', 'late', 'road'], ['sunday'], ['smart']])
  check('the picker: editable only, the one changed last first, ties by name', L.pickerPlaylists(LIST).map((p) => p.id), ['late', 'alpha', 'road'])
  check('the sidebar: yours then shared, never From files, capped', [L.sidebarPlaylists(LIST).map((p) => p.id), L.sidebarPlaylists(LIST, 2), L.sidebarPlaylists(null)],
    [['alpha', 'late', 'road', 'sunday'], [{ id: 'alpha', name: 'Alpha' }, { id: 'late', name: 'Late night' }], []])
  check('a row\'s line: yours (shared said), somebody else\'s, from a file',
    [L.rowLine(pl('a', { songCount: 12, duration: 2880 })), L.rowLine(LATE), L.rowLine(SUNDAY), L.rowLine(SMART)],
    ['12 songs · 48 min', '3 songs · 10 min · Shared', 'ethan · 20 songs · 1h 5m', 'From a file · 30 songs'])
  check('whose: yours, shared by you, somebody else\'s, from a file',
    [L.ownerLine(ROAD), L.ownerLine(LATE), L.ownerLine(SUNDAY), L.ownerLine(SMART)],
    ['Yours', 'Yours · Shared with everyone', "ethan's · Shared with you", 'From a file in the music folders'])
  check('why there is no Edit - and none for yours',
    [L.readOnlyWords(SUNDAY, 3), L.readOnlyWords(SMART, 3)?.startsWith('Navidrome made this playlist from a file'), L.readOnlyWords(ROAD, 2001), L.readOnlyWords(ROAD, 2000), L.canEdit(ROAD, 2000), L.canEdit(SUNDAY, 1)],
    ['Only ethan can change this playlist.', true, 'deadwax edits playlists of up to 2,000 songs - edit this one in Amperfy or Navidrome.', null, true, false])
  check('the count and the length; songs not in the library just now',
    [L.songsLine(12, 2880), L.songsLine(1, 0), L.hiddenWords(2), L.hiddenWords(1), L.hiddenWords(0), L.hiddenEditWords(2)],
    ['12 songs, 48 min', '1 song', "2 songs in this playlist aren't in the library just now - deleted, or being moved.", "1 song in this playlist isn't in the library just now - deleted, or being moved.", '',
      "2 songs that aren't in the library just now will be dropped if you change the songs."])
  check('the limits the server holds', [L.PLAYLIST_NAME_MAX, L.PLAYLIST_COMMENT_MAX, L.PLAYLIST_SONGS_MAX, L.SIDEBAR_PLAYLISTS_MAX], [200, 1000, 2000, 20])
}

console.log('\nthe rules: the albums a playlist\'s songs are remembered under')
{
  const songs = [song('a', { albumId: 'x', album: 'X', displayAlbumArtist: 'Various', year: 1994 }), song('b', { albumId: 'y', album: 'Y' }), song('c', { albumId: 'x', album: 'X' }), song('d', { albumId: undefined })]
  const stubs = L.playlistAlbums(songs)
  check('one stub an album, by first appearance - split by other songs still one', stubs.map((stub) => [stub.id, stub.song.map((s) => s.id)]), [['x', ['a', 'c']], ['y', ['b']]])
  check('...its name, artist (the album\'s own first), cover and year from its first song', [stubs[0].name, stubs[0].artist, stubs[0].coverArt, stubs[0].year, stubs[1].artist],
    ['X', 'Various', 'al-dum', 1994, 'Portishead'])
  check('...and NO musicBrainzId key at all (an empty one would make the ••• menu\'s pin unpinnable)', stubs.map((stub) => 'musicBrainzId' in stub), [false, false])
  check('a song with no album id: no stub; its fallback stub empty', [stubs.length, L.stubFor(songs[3])], [2, { id: '', name: 'Dummy' }])
  check('...each stub `partial` - its songs only the playlist\'s, so Info counts none of the album\'s from it', stubs.map((stub) => stub.partial), [true, true])
  //? (review) an album's own answer held already is remembered as it is - a stub over it lost the playing disc's art
  const full = { id: 'x', name: 'X', song: [song('a', { albumId: 'x', discNumber: 1 }), song('c', { albumId: 'x', discNumber: 1 }), song('e', { albumId: 'x', discNumber: 2 })], discTitles: [{ disc: 2, title: 'Two' }] }
  const earlier = { id: 'y', name: 'Y', song: [song('q', { albumId: 'y' })], partial: true }
  const held = new Map([['x', full], ['y', earlier]])
  const kept = L.withHeld(stubs, (id) => held.get(id) ?? null)
  check('withHeld: the album\'s own answer kept, whole - never the stub over it', [kept[0] === full, kept[0].song.length, kept[0].partial], [true, 3, undefined])
  check('...an earlier playlist\'s stub: its songs kept beside the new ones, still partial', [kept[1].song.map((s) => s.id), kept[1].partial], [['q', 'b'], true])
  check('...nothing held: the stub itself', L.withHeld(stubs, () => null).map((stub, at) => stub === stubs[at]), [true, true])
}

console.log('\nthe rules: Edit, and what Done sends')
{
  const songs = [song('a'), song('b'), song('a'), song('c')]
  const start = L.startEdit(songs, pl('mine', { name: 'Late night', comment: 'Words.', public: false }))
  check('rows keyed by place - a song in twice is two rows', start.rows.map((row) => row.key), ['0:a', '1:b', '2:a', '3:c'])
  check('a move, clamped at the ends; a removal', [L.moveRow(start.rows, 3, 0).map((row) => row.key), L.moveRow(start.rows, 0, -5).map((row) => row.key), L.removeRow(start.rows, 2).map((row) => row.key)],
    [['3:c', '0:a', '1:b', '2:a'], ['0:a', '1:b', '2:a', '3:c'], ['0:a', '1:b', '3:c']])
  check('nothing changed: no body - and a name only re-typed the same is nothing', [L.editBody(start, start), L.editBody(start, { ...start, name: ' Late night ' }), L.editChanged(start, start)], [null, null, false])
  check('the name alone: base, the songs, and the name - nothing else', L.editBody(start, { ...start, name: 'Later' }), { base: ['a', 'b', 'a', 'c'], song_ids: ['a', 'b', 'a', 'c'], name: 'Later' })
  check('the description cleared: "" sent; sharing turned on', [L.editBody(start, { ...start, comment: '  ' }), L.editBody(start, { ...start, public: true })],
    [{ base: ['a', 'b', 'a', 'c'], song_ids: ['a', 'b', 'a', 'c'], comment: '' }, { base: ['a', 'b', 'a', 'c'], song_ids: ['a', 'b', 'a', 'c'], public: true }])
  const swapped = { ...start, rows: L.moveRow(start.rows, 2, 0) }
  check('the two copies of a song swapped is a change of the songs (by place, not id)', L.editBody(start, swapped), { base: ['a', 'b', 'a', 'c'], song_ids: ['a', 'a', 'b', 'c'] })
  check('the server\'s rearrangement rule, mirrored', [L.isRearrangement(['a', 'b', 'a'], ['a', 'a', 'b']), L.isRearrangement(['a', 'b'], []), L.isRearrangement(['a', 'b'], ['a', 'c']), L.isRearrangement(['a', 'b', 'a'], ['a', 'a', 'a'])],
    [true, true, false, false])
}

console.log('\nthe rules: the page scrolls itself under a drag near an edge')
{
  check('nothing away from the edges', [L.edgeScroll(400, 100, 800), L.edgeScroll(157, 100, 800), L.edgeScroll(743, 100, 800)], [0, 0, 0])
  check('upward near the top, downward near the bottom - more the nearer, never past the step',
    [L.edgeScroll(150, 100, 800) < 0, L.edgeScroll(750, 100, 800) > 0, L.edgeScroll(100, 100, 800), L.edgeScroll(800, 100, 800), L.edgeScroll(40, 100, 800), L.edgeScroll(900, 100, 800),
      Math.abs(L.edgeScroll(150, 100, 800)) < Math.abs(L.edgeScroll(110, 100, 800))],
    [true, true, -16, 16, -16, 16, true])
  check('a dragged row\'s distance counts the page\'s scroll since it began', [L.dragDistance(500, 300, 0, 0), L.dragDistance(500, 300, 480, 0), L.dragDistance(300, 300, 0, 200)], [200, 680, -200])
}

console.log('\nthe rules: the words of an add')
{
  const one = { label: 'Roads', songs: [{ id: 'r', title: 'Roads', artist: 'Portishead' }] }
  const album = { label: 'Dummy', songs: Array.from({ length: 11 }, (_, at) => ({ id: `s${at}`, title: `S${at}` })) }
  check('what the picker is adding', [L.pickLine(one), L.pickLine(album)], ['Roads · Portishead', 'Dummy · 11 songs'])
  check('what became of it', [L.addedWords({ added: 1, already: 0 }, 'ask', one, 'Late night'), L.addedWords({ added: 11, already: 2 }, 'add', album, 'Late night'),
    L.addedWords({ added: 9, already: 2 }, 'skip', album, 'Late night'), L.addedWords({ added: 0, already: 11 }, 'skip', album, 'Late night'), L.addedWords({ added: 0, already: 1 }, 'skip', one, 'Late night')],
    ['Added Roads to Late night', 'Added 11 songs to Late night', 'Added 9 songs to Late night - 2 were in it already', "Nothing added - they're all in Late night already", 'Nothing added - Roads is in Late night already'])
  check('a playlist made with them', [L.madeWords('Late night', one), L.madeWords('Late night', album)], ['Made Late night with Roads', 'Made Late night with 11 songs'])
  const asked = (already, n, pick) => { const q = L.duplicateQuestion(already, n, pick, 'Late night'); return [q.text, q.yes.label, q.yes.mode, q.no.label, q.no.mode] }
  check('the question: one song, all of several, some',
    [asked(1, 1, one), asked(11, 11, album), asked(2, 11, album), asked(1, 11, album)[3]],
    [['Roads is in Late night already.', 'Add it again', 'add', 'Cancel', null], ['These 11 songs are all in Late night already.', 'Add them again', 'add', 'Cancel', null],
      ['2 of these 11 songs are in Late night already.', 'Add them all', 'add', 'Skip those 2', 'skip'], 'Skip that one'])
}

console.log('\nthe store: one list, asked as it is wanted')
{
  check('nothing asked until something asks', [W.asks.length, S.playlistsNow()], [0, { list: null, problem: null, asking: false }])
  const told = []
  S.onPlaylistChanged((id) => told.push(id))
  S.askPlaylists()
  check('asked', W.asks, [['list']])
  answer('list', { playlists: [LATE] })
  await settle()
  check('answered: the list', S.playlistsNow().list.map((p) => p.id), ['late'])
  S.askPlaylists()
  check('a held answer under 30 s old asks nothing without fresh', W.asks.length, 1)
  S.askPlaylists({ fresh: true })
  S.askPlaylists({ fresh: true })
  check('fresh asks - a newer ask superseding the one before', W.asks.length, 3)
  answer('list', { playlists: [ROAD] }, 1)
  answer('list', { playlists: [ALPHA] }, 0)
  await settle()
  check('...the older answer landing late draws nothing', S.playlistsNow().list.map((p) => p.id), ['road'])
  S.askPlaylists({ fresh: true })
  answer('list', new ApiError(502, 'Navidrome answered 502'))
  await settle()
  //? (2.0.4) in a listener's words - the music server can't be reached - with (logins off: everyone runs deadwax) Navidrome's own in brackets
  check('a failure keeps the last list and says why', [S.playlistsNow().list.map((p) => p.id), S.playlistsNow().problem], [['road'], "Can't reach the music server right now. Try again in a minute. (Navidrome answered 502)"])
  S.announcePlaylistChanged('late')
  check('a write here: the list asked again, a page of that id told', [W.asks.slice(-1), told], [[['list']], ['late']])
  answer('list', { playlists: [LATE, ROAD] })
  await settle()
  check('...and the next answer clears the failure', [S.playlistsNow().list.length, S.playlistsNow().problem], [2, null])
  for (let n = 0; n < 10; n++) S.keepPlaylist({ playlist: pl(`k${n}`), songs: [], hidden: 0 })
  check('a page\'s answers kept, the last eight', [S.keptPlaylist('k0'), S.keptPlaylist('k1'), !!S.keptPlaylist('k2'), !!S.keptPlaylist('k9')], [null, null, true, true])
  S.forgetPlaylist('k9')
  check('...a deleted one let go', S.keptPlaylist('k9'), null)
  //? (review) a write here without the playlist's answer (an add) lets its kept answer go - drawn later it would be
  //? the songs as they were; one with it (Done, New playlist) keeps that answer
  S.announcePlaylistChanged('k8')
  const now = { playlist: pl('k3'), songs: [song('n')], hidden: 0 }
  S.announcePlaylistChanged('k3', now)
  check('...an add here lets that playlist\'s kept answer go; a Done here keeps what it answered, the page told it',
    [S.keptPlaylist('k8'), S.keptPlaylist('k3') === now, told.slice(-2)], [null, true, ['k8', 'k3']])
  for (let n = 0; n < 2; n++) answer('list', { playlists: [LATE, ROAD] }, 'last')
  await settle()
}

console.log('\nthe picker')
{
  W.asks.length = 0
  W.sheets.length = 0
  W.calls.length = 0
  const render = hooks.root(PlaylistPicker)
  let closed = 0
  const pick = { key: 1, label: 'Dummy', songs: [{ id: 's1', title: 'Roads', artist: 'Portishead' }, { id: 's2', title: 'Sour Times', artist: 'Portishead' }] }
  const props = { open: true, pick, opener: { current: null }, onClose: () => { closed += 1 } }
  let tree = render(props)
  render.commit()
  check('a sheet of its own, focus in to New playlist…', [W.sheets.slice(-1)[0].lockClass, W.sheets.slice(-1)[0].first === find(byClass('app-playlist-new'), tree)[0].props.ref], ['app-picker-open', true])
  check('...asked afresh as it opens', W.asks, [['list']])
  answer('list', { playlists: LIST })
  await settle()
  tree = render(props)
  const rows = () => find(byClass('app-playlist-pick'), tree)
  check('named "Add to a playlist", saying what it adds', [find((node) => node.props?.role === 'dialog', tree)[0].props['aria-labelledby'], words(find(byClass('app-playlist-picker-what'), tree))],
    ['app-playlist-picker-title', 'Dummy · 2 songs'])
  check('New playlist… first, then yours you can add to - the one changed last on top', rows().map(words), ['New playlist…', 'Late night3 songs', 'Alpha3 songs', 'Road trip3 songs'])
  rows()[1].props.onClick()
  rows()[2].props.onClick()
  tree = render(props)
  check('a tap asks - `ask` - and a second tap while it is out sends nothing', W.asks.filter(([name]) => name === 'add'), [['add', { id: 'late', ids: ['s1', 's2'], duplicates: 'ask' }]])
  check('...its row says Adding…, every row aria-disabled', [words(rows()[1]), rows().map((row) => row.props['aria-disabled'])], ['Late nightAdding…', [true, true, true, true]])
  answer('add', { done: false, already: 2, asked: 2 })
  await settle()
  tree = render(props)
  render.commit()
  const buttons = () => find(byClass('app-button'), find(byClass('app-playlist-question'), tree))
  check('all of them there already: the question in place of the list, nothing written', [words(find(byClass('app-playlist-question-words'), tree)), buttons().map(words), closed],
    ['These 2 songs are all in Late night already.', ['Add them again', 'Cancel'], 0])
  buttons()[1].props.onClick()
  tree = render(props)
  check('Cancel: back to the list, nothing sent', [rows().length, W.asks.filter(([name]) => name === 'add').length], [4, 1])
  rows()[1].props.onClick()
  answer('add', { done: false, already: 1, asked: 2 })
  await settle()
  tree = render(props)
  check('some there: "Add them all" or "Skip that one"', buttons().map(words), ['Add them all', 'Skip that one'])
  buttons()[1].props.onClick()
  check('...Skip sends `skip`', W.asks.filter(([name]) => name === 'add').slice(-1), [['add', { id: 'late', ids: ['s1', 's2'], duplicates: 'skip' }]])
  answer('add', { done: true, added: 1, already: 1 })
  await settle()
  check('done: the notice says it, the list asked again, the sheet closed', [W.calls.slice(-1), W.asks.slice(-1), closed],
    [[['sayPins', 'Added 1 song to Late night - 1 was in it already']], [['list']], 1])
  answer('list', { playlists: LIST })
  await settle()
  tree = render(props)
  rows()[3].props.onClick()
  answer('add', new ApiError(404, "That playlist isn't on Navidrome any more"))
  await settle()
  tree = render(props)
  check('refused: said under the list, as an alert, the sheet open - a gone one asking the list again',
    [words(find(byClass('app-playlist-picker-problem'), tree)), find(byClass('app-playlist-picker-problem'), tree)[0].props.role, closed, W.asks.slice(-1)],
    ["That playlist isn't on Navidrome any more", 'alert', 1, [['list']]])
  answer('list', { playlists: LIST })
  await settle()
  tree = render(props)
  rows()[0].props.onClick()
  tree = render(props)
  const form = find(byType(NewPlaylistForm), tree)[0]
  check('New playlist…: the form in place of its row', [!!form, find(byClass('app-playlist-new'), tree)[0].props.hidden], [true, true])
  const made = form.props.onCreate('Late night 2')
  check('...Create makes it WITH the songs', W.asks.slice(-1), [['create', { name: 'Late night 2', ids: ['s1', 's2'] }]])
  answer('create', { playlist: pl('new', { name: 'Late night 2' }), songs: [], hidden: 0 })
  await made
  await settle()
  check('...made: kept, the notice, closed', [!!S.keptPlaylist('new'), W.calls.slice(-1), closed], [true, [['sayPins', 'Made Late night 2 with 2 songs']], 2])
  //? closed while an add is out: it isn't called off - the notice still says how it went
  const second = { ...props, pick: { ...pick, key: 2 } }
  tree = render(second)
  render.commit()
  answer('list', { playlists: LIST })
  await settle()
  tree = render(second)
  rows()[1].props.onClick()
  tree = render({ ...second, open: false })
  answer('add', { done: true, added: 2, already: 0 })
  await settle()
  check('closed while an add was out: still said, nothing closed twice', [W.calls.slice(-1), closed], [[['sayPins', 'Added 2 songs to Late night']], 2])
  answer('list', { playlists: LIST })
  await settle()
  //? (review) closed while an add was out, then opened again: the rows freed once it answers, New playlist… working
  const third = { ...props, pick: { ...pick, key: 3 } }
  tree = render(third)
  render.commit()
  answer('list', { playlists: LIST })
  await settle()
  tree = render(third)
  rows()[1].props.onClick()
  tree = render({ ...third, open: false })
  render.commit()
  const fourth = { ...props, pick: { ...pick, key: 4 } }
  tree = render(fourth)
  render.commit()
  answer('add', new ApiError(502, 'Navidrome answered 502'))
  await settle()
  answer('list', { playlists: LIST })
  await settle()
  tree = render(fourth)
  check('closed while an add was out and opened again: once it answers, every row free', [rows().map((row) => row.props['aria-disabled']), words(rows()[1])],
    [[false, false, false, false], 'Late night3 songs'])
  rows()[0].props.onClick()
  tree = render(fourth)
  check('...and New playlist… opens its form', find(byType(NewPlaylistForm), tree).length, 1)
  //? the question's buttons: the one pressed says Adding…; refused, focus back to the list's first row
  tree = render({ ...fourth, pick: { ...pick, key: 5 } })
  render.commit()
  answer('list', { playlists: LIST })
  await settle()
  const fifth = { ...props, pick: { ...pick, key: 5 } }
  tree = render(fifth)
  rows()[1].props.onClick()
  answer('add', { done: false, already: 1, asked: 2 })
  await settle()
  tree = render(fifth)
  render.commit()
  buttons()[1].props.onClick()
  tree = render(fifth)
  check('Skip pressed: Skip says Adding…, Add them all doesn\'t', buttons().map(words), ['Add them all', 'Adding…'])
  const landed = []
  W.sheets.slice(-1)[0].first.current = { focus: () => landed.push('first row') }
  answer('add', new ApiError(502, 'Navidrome answered 502'))
  await settle()
  tree = render(fifth)
  render.commit()
  check('...refused from the question: the list back, the words on the card, focus to its first row', [rows().length, words(find(byClass('app-playlist-picker-problem'), find(byClass('app-playlist-picker-head'), tree))), landed],
    [4, "Can't reach the music server right now. Try again in a minute. (Navidrome answered 502)", ['first row']])
  answer('list', { playlists: LIST }, 'last')
  await settle()
}

console.log('\nNew playlist\'s form, and the question asked in place')
{
  const render = hooks.root(NewPlaylistForm)
  const asked = []
  let cancelled = 0
  let resolveIt, rejectIt
  const props = { onCreate: (name) => { asked.push(name); return new Promise((yes, no) => { resolveIt = yes; rejectIt = no }) }, onCancel: () => { cancelled += 1 } }
  let tree = render(props)
  const field = () => find(byClass('app-new-playlist-input'), tree)[0]
  const create = () => find(byClass('app-new-playlist-create'), tree)[0]
  check('a Name field: bounded, done on the keyboard, sentences; Create aria-disabled while blank',
    [field().props.maxLength, field().props.enterKeyHint, field().props.autoCapitalize, create().props['aria-disabled']], [200, 'done', 'sentences', true])
  find(byType('form'), tree)[0].props.onSubmit({ preventDefault() {} })
  check('...a blank name creates nothing', asked, [])
  field().props.onInput({ currentTarget: { value: '  Late night ' } })
  tree = render(props)
  find(byType('form'), tree)[0].props.onSubmit({ preventDefault() {} })
  find(byType('form'), tree)[0].props.onSubmit({ preventDefault() {} })
  tree = render(props)
  check('Enter (the form\'s submit) creates it trimmed - once, Creating… while it is out', [asked, words(create()), create().props['aria-disabled']], [['Late night'], 'Creating…', true])
  rejectIt(new ApiError(502, 'Navidrome answered 502'))
  await settle()
  tree = render(props)
  check('refused: the form stays, the reason under it as an alert', [words(find(byClass('is-refused'), tree)), find(byClass('is-refused'), tree)[0].props.role, words(create())], ["Can't reach the music server right now. Try again in a minute. (Navidrome answered 502)", 'alert', 'Create'])
  let prevented = false
  field().props.onKeyDown({ key: 'Escape', preventDefault: () => { prevented = true } })
  check('Escape cancels the form and nothing else (preventDefault - the sheet around it stays)', [cancelled, prevented], [1, true])

  const line = hooks.root(ConfirmLine)
  const said = []
  const lineProps = { words: 'Delete "Late night"?', confirm: 'Delete playlist', keep: 'Keep it', danger: true, onConfirm: () => said.push('yes'), onKeep: () => said.push('keep') }
  let lineTree = line(lineProps)
  const focusedKeep = []
  find(byClass('app-confirm-keep'), lineTree)[0].props.ref.current = { focus: () => focusedKeep.push('keep') }
  line.commit()
  check('the question: the words, the red go-ahead, Keep it - focus on Keep it', [words(find(byClass('app-confirm-words'), lineTree)), find(byClass('app-confirm-yes'), lineTree)[0].props.class.includes('is-danger'), focusedKeep],
    ['Delete "Late night"?', true, ['keep']])
  find(byClass('app-confirm-yes'), lineTree)[0].props.onClick()
  find(byClass('app-confirm-keep'), lineTree)[0].props.onClick()
  lineTree = line({ ...lineProps, busy: true, busyLabel: 'Deleting…', problem: 'refused' })
  find(byClass('app-confirm-yes'), lineTree)[0].props.onClick()
  check('...each button its own; busy, the go-ahead says so and does nothing; refused, why', [said, words(find(byClass('app-confirm-yes'), lineTree)), words(find(byClass('is-refused'), lineTree))],
    [['yes', 'keep'], 'Deleting…', 'refused'])
}

console.log('\nthe Playlists page')
{
  W.asks.length = 0
  const render = hooks.root(PlaylistsPage)
  const opened = []
  const props = { onBack() {}, backLabel: 'Library', shown: true, onOpenPlaylist: (p) => opened.push(p.id) }
  let tree = render(props)
  render.commit()
  check('asked afresh as it shows', W.asks, [['list']])
  answer('list', { playlists: LIST })
  await settle()
  tree = render(props)
  check('Yours, Shared with you, then From files folded behind one row', [find(byType('h2'), tree).map(words), find(byClass('app-playlists-fold'), tree)[0].props['aria-expanded'], find(byClass('app-playlist-row'), tree).length],
    [['Yours', 'Shared with you', 'From files (1)'], false, 4])
  find(byClass('app-playlists-fold'), tree)[0].props.onClick()
  tree = render(props)
  check('...opened in place', [find(byClass('app-playlists-fold'), tree)[0].props['aria-expanded'], find(byClass('app-playlist-row'), tree).map((row) => words(row))[4]], [true, 'Recently playedFrom a file · 30 songs'])
  find(byClass('app-playlist-row'), tree)[3].props.onClick()
  check('a row opens its playlist - and plays nothing', [opened, W.calls.filter(([name]) => name === 'rememberQueue')], [['sunday'], []])
  check('...a playlist\'s square its mosaic', find(byClass('app-playlist-art'), tree).map((art) => art.props.children.props?.class).slice(0, 1), ['app-playlist-art-img'])
  find(byClass('app-playlists-new'), tree)[0].props.onClick()
  tree = render(props)
  const form = find(byType(NewPlaylistForm), tree)[0]
  const made = form.props.onCreate('Fresh')
  check('New playlist: the form at the top; Create makes an empty one', W.asks.slice(-1), [['create', { name: 'Fresh', ids: [] }]])
  answer('create', { playlist: pl('fresh'), songs: [], hidden: 0 })
  await made
  check('...made: its page opened over this one, its answer kept to draw at once', [opened.slice(-1), !!S.keptPlaylist('fresh')], [['fresh'], true])
  //? (review) made after the page stopped showing (another tab tapped): said, never pushed on what shows now
  tree = render(props)
  find(byClass('app-playlists-new'), tree)[0].props.onClick()
  tree = render(props)
  const late = find(byType(NewPlaylistForm), tree)[0].props.onCreate('Later')
  render({ ...props, shown: false })
  answer('create', { playlist: pl('later', { name: 'Later' }), songs: [], hidden: 0 })
  await late
  check('...made once it stopped showing: not opened, the notice says it', [opened.slice(-1), W.calls.slice(-1)], [['fresh'], [['sayPins', 'Made Later']]])
  render(props)
  answer('list', { playlists: [] }, 'last')
  await settle()
  tree = render(props)
  check('none yet: the notice, and New playlist in it', [words(find(byClass('app-playlists-empty'), tree)).startsWith('No playlists yet.'), find(byClass('app-playlists-empty-new'), tree).length], [true, 1])
  //? a page with nothing held and the ask failing: why, and Try again - a store of its own, as a page load's
  for (const file of ['app/usePlaylists.js', 'app/PlaylistsPage.js']) delete require.cache[path.join(OUT, file)]
  const { PlaylistsPage: FreshPage } = require(path.join(OUT, 'app/PlaylistsPage.js'))
  const fresh = hooks.root(FreshPage)
  fresh(props)
  fresh.commit()
  answer('list', new ApiError(502, 'Navidrome isn\'t answering'), 'last')
  await settle()
  let failed = fresh(props)
  check('nothing held and the ask failed: why, and Try again', words(find(byClass('pl-notice'), failed)), "Couldn't list your playlists. Navidrome isn't answering" + 'Try again')
  find(byClass('pl-text-button'), failed)[0].props.onClick()
  check('...Try again asks afresh', W.asks.slice(-1), [['list']])
  answer('list', { playlists: [ROAD] }, 'last')
  await settle()
  failed = fresh(props)
  check('...and draws what comes', find(byClass('app-playlist-row'), failed).length, 1)
}

console.log('\na playlist\'s page: drawn at once, then asked')
{
  W.asks.length = 0
  W.calls.length = 0
  const songs = [song('a'), song('b'), song('a'), song('c', { albumId: 'x', album: 'X' })]
  const kept = { playlist: pl('Late night', { id: 'late', songCount: 4 }), songs, hidden: 0 }
  S.keepPlaylist(kept)
  const played = []
  const player = { playTracks: (tracks, start, shuffle) => { played.push([tracks.map((t) => t.id), start, shuffle]); W.calls.push(['playTracks']) }, playing: true, track: { id: 'a' } }
  const render = hooks.root(PlaylistPage)
  const deleted = []
  const props = { id: 'late', preview: null, player, onBack() {}, backLabel: 'Playlists', shown: true, onDeleted: (name) => deleted.push(name), onQueueMenu: () => {} }
  let tree = render(props)
  check('the kept answer drawn on the FIRST render - before anything is asked, so Back finds its place',
    [words(find(byClass('pl-hero-title'), tree)), find(byClass('app-playlist-track'), tree).length, W.asks.length], ['Late night', 4, 0])
  render.commit()
  check('...then asked', W.asks, [['one', 'late']])
  //? (review) the kept answer is for Back's place and for playing - Edit waits for this mount's own answer
  let toggle = find(byClass('app-playlist-edit-toggle'), tree)[0]
  toggle.props.onClick()
  tree = render(props)
  check('...Edit shown but aria-disabled until it answers, and a tap meanwhile begins nothing',
    [toggle.props['aria-disabled'], find(byClass('app-playlist-edit-row'), tree).length, words(find(byClass('app-playlist-edit-toggle'), tree))], [true, 0, 'Edit'])
  answer('one', { ...kept, songs: [...songs, song('d')] })
  await settle()
  tree = render(props)
  check('...and the newer answer drawn over it', find(byClass('app-playlist-track'), tree).length, 5)
  check('...Edit offered once it has', find(byClass('app-playlist-edit-toggle'), tree)[0].props['aria-disabled'], false)
  const rows = find(byClass('app-track-row'), find(byClass('app-playlist-tracks'), tree))
  check('rows keyed by place - the song twice drawn twice, both marked playing', [rows.map((row) => row.key), find(byClass('is-current'), tree).length],
    [['0:a', '1:b', '2:a', '3:c', '4:d'], 2])
  find(byClass('pl-pill'), tree)[0].props.onClick()
  find(byClass('pl-pill'), tree)[1].props.onClick()
  find(byClass('app-playlist-track'), tree)[3].props.onClick()
  check('Play, Shuffle and a row: the albums remembered, then playTracks at once with the songs in hand',
    [W.calls, played],
    [[['rememberQueue', ['dum', 'x']], ['playTracks'], ['rememberQueue', ['dum', 'x']], ['playTracks'], ['rememberQueue', ['dum', 'x']], ['playTracks']],
      [[['a', 'b', 'a', 'c', 'd'], 0, false], [['a', 'b', 'a', 'c', 'd'], null, true], [['a', 'b', 'a', 'c', 'd'], 3, false]]])
  //? (review) an album played from its own page is held whole: Play and a row's ••• keep it, never a stub over it
  const picks = []
  const whole = { id: 'dum', name: 'Dummy', song: [song('a'), song('b'), song('c'), song('z', { discNumber: 2 })] }
  W.held.set('dum', whole)
  tree = render({ ...props, onQueueMenu: (event, pick) => picks.push(pick) })
  find(byClass('pl-pill'), tree)[0].props.onClick()
  find(byClass('app-row-more'), tree)[0].props.onClick({})
  find(byClass('app-album-more'), tree)[0].props.onClick({})
  check('an album held whole: remembered as it is on Play, and handed so to a row\'s ••• and the bar\'s',
    [W.remembered[0] === whole, picks[0].albums[0] === whole, picks[1].albums[0] === whole, picks[1].albums[1].partial], [true, true, true, true])
  W.held.clear()
  tree = render(props)
  check('Edit offered for yours and editable; whose it is; the count at the foot',
    [words(find(byClass('app-playlist-edit-toggle'), tree)), words(find(byClass('app-playlist-owner'), tree)), words(find(byClass('pl-album-footer'), tree))], ['Edit', 'Yours', '5 songs, 17 min'])
  const before = W.asks.filter(([name]) => name === 'one').length
  S.announcePlaylistChanged('road')
  tree = render(props)
  render.commit()
  check('another playlist changed here: this page asks nothing', W.asks.filter(([name]) => name === 'one').length - before, 0)
  S.announcePlaylistChanged('late')
  tree = render(props)
  render.commit()
  check('this one changed here: asked again', W.asks.filter(([name]) => name === 'one').slice(before), [['one', 'late']])
  //? (review) an add from the picker over this page: what is drawn isn't how it stands - no Edit from it meanwhile
  tree = render(props)
  check('...its kept answer let go, and no Edit until the ask answers', [S.keptPlaylist('late'), find(byClass('app-playlist-edit-toggle'), tree)[0].props['aria-disabled']], [null, true])
  answer('one', kept)
  await settle()
  tree = render({ ...props, shown: false })
  render.commit()
  tree = render(props)
  render.commit()
  //? (the stand-in draws again only when told: the state the effect set is read by the next render, as Preact's would)
  tree = render(props)
  render.commit()
  check('shown again after not showing: asked again', W.asks.filter(([name]) => name === 'one').length - before, 2)
  answer('one', kept)
  await settle()
  answer('list', { playlists: LIST })
}

//? (review) the reviewer's case: a page's answer kept, a song added to it from an album's ••• (the picker), the page
//? opened again - it draws nothing stale, and Edit waits for its own answer, so Done's base is how it stands
{
  W.asks.length = 0
  const old = { playlist: pl('Road trip', { id: 'trip', songCount: 2 }), songs: [song('a'), song('b')], hidden: 0 }
  S.keepPlaylist(old)
  S.announcePlaylistChanged('trip')
  const render = hooks.root(PlaylistPage)
  const props = { id: 'trip', preview: old.playlist, player: { playTracks() {}, playing: false, track: null }, onBack() {}, backLabel: 'Playlists', shown: true, onDeleted() {}, onQueueMenu() {} }
  let tree = render(props)
  render.commit()
  check('an add here, then the page again: none of the old songs drawn, no Edit, asked',
    [find(byClass('app-playlist-track'), tree).length, find(byClass('app-playlist-edit-toggle'), tree).length, W.asks.filter(([name]) => name === 'one')], [0, 0, [['one', 'trip']]])
  answer('one', { ...old, songs: [...old.songs, song('c')] })
  await settle()
  tree = render(props)
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = render(props)
  check('...its answer drawn, and Edit from it', [find(byClass('app-playlist-edit-row'), tree).length], [3])
  for (const one of W.open.filter((each) => each.name === 'list')) answer('list', { playlists: LIST })
  await settle()
}

console.log('\na playlist\'s page: the preview, theirs, from a file, hidden songs, empty, gone')
{
  W.asks.length = 0
  const player = { playTracks() { throw new Error('nothing should play') }, playing: false, track: null }
  const page = (id, preview = null) => {
    const render = hooks.root(PlaylistPage)
    const props = { id, preview, player, onBack() {}, backLabel: 'Playlists', shown: true, onDeleted() {}, onQueueMenu() {} }
    const draw = () => { const tree = render(props); render.commit(); return tree }
    return { draw }
  }
  const sunday = page('sunday', SUNDAY)
  let tree = sunday.draw()
  check('the hero from the row that opened it at once', [words(find(byClass('pl-hero-title'), tree)), words(find(byClass('app-playlist-owner'), tree))], ['Sunday', "ethan's · Shared with you"])
  answer('one', { playlist: SUNDAY, songs: [song('a')], hidden: 3 })
  await settle()
  tree = sunday.draw()
  check('somebody else\'s: no Edit, why in its place; and the hidden note', [find(byClass('app-playlist-edit-toggle'), tree).length, words(find(byClass('app-playlist-readonly'), tree)), words(find(byClass('app-playlist-line'), tree))],
    [0, 'Only ethan can change this playlist.', "3 songs in this playlist aren't in the library just now - deleted, or being moved."])
  const smart = page('smart', SMART)
  smart.draw()
  answer('one', { playlist: SMART, songs: [song('a')], hidden: 0 })
  await settle()
  tree = smart.draw()
  check('from a file: no Edit, why', [find(byClass('app-playlist-edit-toggle'), tree).length, words(find(byClass('app-playlist-readonly'), tree)).startsWith('Navidrome made this playlist from a file')], [0, true])
  const big = page('big')
  big.draw()
  answer('one', { playlist: pl('big'), songs: Array.from({ length: 2001 }, (_, at) => song(`s${at}`)), hidden: 0 })
  await settle()
  tree = big.draw()
  check('over 2,000 songs: plays, no Edit, why', [find(byClass('app-playlist-edit-toggle'), tree).length, words(find(byClass('app-playlist-readonly'), tree)), find(byClass('pl-pill'), tree)[0].props.disabled],
    [0, 'deadwax edits playlists of up to 2,000 songs - edit this one in Amperfy or Navidrome.', false])
  const empty = page('empty')
  empty.draw()
  answer('one', { playlist: pl('empty', { coverArt: null, songCount: 0 }), songs: [], hidden: 0 })
  await settle()
  tree = empty.draw()
  check('empty: how to add songs, Play and Shuffle disabled, the glyph for a cover',
    [words(find(byClass('app-playlist-empty'), tree)).startsWith('Nothing in this playlist yet.'), find(byClass('pl-pill'), tree).map((pill) => pill.props.disabled), find(byClass('app-playlist-hero-empty'), tree).length],
    [true, [true, true], 1])
  //? a song with no album id: no stub remembered for it, and its queue track names no album (null, never '')
  const lone = []
  const loneRender = hooks.root(PlaylistPage)
  const loneProps = { id: 'lone', preview: null, player: { playTracks: (tracks) => lone.push(tracks.map((t) => t.albumId)), playing: false, track: null }, onBack() {}, backLabel: 'Playlists', shown: true, onDeleted() {} }
  loneRender(loneProps)
  loneRender.commit()
  answer('one', { playlist: pl('lone'), songs: [song('z', { albumId: undefined, album: undefined }), song('y')], hidden: 0 })
  await settle()
  W.calls.length = 0
  find(byClass('pl-pill'), loneRender(loneProps))[0].props.onClick()
  check('a song with no album id: none remembered for it, its track\'s album null', [W.calls[0], lone], [['rememberQueue', ['dum']], [[null, 'dum']]])
  //? (review) nothing in hand and the first ask failing: why, and Try again - no empty hero saying "again"
  const cold = page('cold')
  cold.draw()
  answer('one', new ApiError(502, 'Navidrome answered 502'))
  await settle()
  tree = cold.draw()
  check('nothing in hand and the first ask failed: why, Try again, no hero', [words(find(byClass('app-playlist-failed'), tree)), find(byClass('pl-album-hero'), tree).length, find(byClass('app-playlist-line'), tree).length],
    ["Couldn't open this playlist. Can't reach the music server right now. Try again in a minute. (Navidrome answered 502)Try again", 0, 0])
  find(byClass('pl-text-button'), find(byClass('app-playlist-failed'), tree))[0].props.onClick()
  tree = cold.draw()
  check('...Try again asks again, the spinner meanwhile', [W.asks.slice(-1), find(byClass('pl-spinner'), tree).length], [[['one', 'cold']], 1])
  answer('one', { playlist: pl('cold', { name: 'Cold' }), songs: [song('a')], hidden: 0 })
  await settle()
  tree = cold.draw()
  check('...and draws what comes', words(find(byClass('pl-hero-title'), tree)), 'Cold')
  const gone = page('gone', pl('gone', { name: 'Gone' }))
  gone.draw()
  answer('one', new ApiError(404, 'gone'))
  await settle()
  tree = gone.draw()
  check('gone (deleted in another app): said in place of the songs, the hero as the preview had it, nothing to play',
    [words(find(byClass('app-playlist-gone'), tree)), words(find(byClass('pl-hero-title'), tree)), find(byClass('pl-pill'), tree).map((pill) => pill.props.disabled)],
    ["This playlist isn't on Navidrome any more - deleted in another app, maybe.", 'Gone', [true, true]])
}

console.log('\na playlist\'s page: Edit')
{
  W.asks.length = 0
  W.calls.length = 0
  const songs = [song('a', { title: 'Roads' }), song('b', { title: 'Teardrop' }), song('c', { title: 'Glory Box' })]
  const playlist = pl('Late night', { id: 'mine', comment: 'Words.', songCount: 3 })
  const player = { playTracks() { W.calls.push(['playTracks']) }, playing: false, track: null }
  const render = hooks.root(PlaylistPage)
  const deleted = []
  const props = { id: 'mine', preview: null, player, onBack() {}, backLabel: 'Playlists', shown: true, onDeleted: (name, id) => deleted.push([name, id]), onQueueMenu() {} }
  const draw = () => { const tree = render(props); render.commit(); return tree }
  let tree = draw()
  answer('one', { playlist, songs, hidden: 1 })
  await settle()
  tree = draw()
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = draw()
  check('Edit: Cancel where Back was, Done where Edit was; the fields filled; the rows; the songs\' rows gone',
    [words(find(byClass('app-playlist-cancel'), tree)), words(find(byClass('app-playlist-edit-toggle'), tree)), find(byClass('app-playlist-input'), tree).map((field) => field.props.value),
      find(byClass('app-playlist-edit-row'), tree).length, find(byClass('app-playlist-track'), tree).length],
    ['Cancel', 'Done', ['Late night', 'Words.'], 3, 0])
  check('...the bar\'s ••• aria-disabled, Play and Shuffle too, and what Done does to songs not in the library said',
    [find(byClass('app-album-more'), tree)[0].props['aria-disabled'], find(byClass('pl-pill'), tree).map((pill) => pill.props.disabled), words(find(byClass('app-playlist-line'), tree))],
    [true, [true, true], "1 song that isn't in the library just now will be dropped if you change the songs."])
  find(byClass('app-pin-row'), tree)[0].props.onClick?.()
  check('Edit\'s rows play nothing', W.calls.filter(([name]) => name === 'playTracks'), [])
  find(byClass('app-check-row'), tree)[0].props.onClick()
  find(byClass('app-pin-down'), tree)[0].props.onClick()
  const moveFocus = []
  find(byClass('app-playlist-edit'), tree)[0].props.ref.current = { querySelectorAll: () => ['1:b', '0:a', '2:c'].map((key) => ({ dataset: { row: key }, querySelector: (selector) => ({ focus: () => moveFocus.push(`${key} ${selector.match(/app-pin-(up|down|remove)/)[1]}`) }) })) }
  tree = draw()
  check('a move by a button: focus back on that button, in the row where it went', moveFocus, ['0:a down'])
  check('a move: said aloud, the ends\' buttons aria-disabled', [words(find((node) => node.props?.role === 'status' && byClass('app-visually-hidden')(node), tree)), find(byClass('app-pin-up'), tree).map((b) => b.props['aria-disabled'])],
    ['Roads: 2 of 3', [true, false, false]])
  //? the page the browser would have drawn: each row's buttons, focus recorded (pins.sim's way)
  const focused = []
  const fakeRow = (key) => ({ dataset: { row: key }, querySelector: (selector) => ({ focus: () => focused.push(`${key} ${selector.match(/app-pin-(up|down|remove)/)[1]}`) }) })
  const lay = (keys) => {
    find(byClass('app-playlist-edit'), tree)[0].props.ref.current = { querySelectorAll: () => keys.map(fakeRow) }
    find(byClass('app-playlist-edit-toggle'), tree)[0].props.ref.current = { focus: () => focused.push('done') }
  }
  lay(['1:b', '0:a', '2:c'])
  find(byClass('app-pin-remove'), tree)[2].props.onClick()
  tree = draw()
  check('a removal at the end: focus to the remove of the row before', focused, ['0:a remove'])
  check('a removal: said, the row gone', [words(find((node) => node.props?.role === 'status' && byClass('app-visually-hidden')(node), tree)), find(byClass('app-pin-title'), tree).map(words)],
    ['Glory Box removed', ['Teardrop', 'Roads']])
  //? the drag: the rows 60px apart, the page scrolling 480px under it as it is held near the bottom
  const rowAt = (index) => ({ offsetTop: index * 60, offsetHeight: 52, get nextElementSibling() { return index < 1 ? rowAt(index + 1) : null }, get previousElementSibling() { return index > 0 ? rowAt(index - 1) : null } })
  const pointer = (y, index = 0) => ({ button: 0, pointerId: 3, clientY: y, preventDefault() {}, currentTarget: { closest: () => rowAt(index), setPointerCapture() {} } })
  scrollY = 0
  find(byClass('app-pin-grip'), tree)[1].props.onPointerDown(pointer(500, 1))
  tree = draw()
  scrollY = -120
  find(byClass('app-pin-grip'), tree)[1].props.onPointerUp(pointer(560, 1))
  tree = draw()
  check('a drag lands where its distance says - the page\'s scroll since it began counted (60px down, 120px scrolled up: up a row)', find(byClass('app-pin-title'), tree).map(words), ['Roads', 'Teardrop'])
  scrollY = 0
  find(byClass('app-pin-grip'), tree)[0].props.onPointerDown(pointer(500, 0))
  tree = draw()
  check('...held, the page scrolls by itself - a frame loop only while a drag is held', frames.length > 0, true)
  find(byClass('app-pin-grip'), tree)[0].props.onPointerCancel(pointer(500, 0))
  tree = draw()
  find(byClass('app-playlist-input'), tree)[0].props.onInput({ currentTarget: { value: 'Later' } })
  find(byClass('app-playlist-input'), tree)[1].props.onInput({ currentTarget: { value: '' } })
  tree = draw()
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = draw()
  check('Done: base as drawn when Edit began, the songs now, and only what changed', W.asks.filter(([name]) => name === 'edit'),
    [['edit', { id: 'mine', body: { base: ['a', 'b', 'c'], song_ids: ['a', 'b'], name: 'Later', comment: '', public: true } }]])
  check('...Saving… and aria-disabled while it is out', [words(find(byClass('app-playlist-edit-toggle'), tree)), find(byClass('app-playlist-edit-toggle'), tree)[0].props['aria-disabled']], ['Saving…', true])
  answer('edit', new ApiError(502, 'Navidrome answered 502'))
  await settle()
  tree = draw()
  check('refused: Edit stays with the changes and the reason, as an alert', [find(byClass('app-playlist-edit-row'), tree).length, find(byClass('app-playlist-input'), tree)[0].props.value, words(find((node) => node.props?.role === 'alert', tree))],
    [2, 'Later', "Can't reach the music server right now. Try again in a minute. (Navidrome answered 502)"])
  check('...the reason in the bar, which stays in view', words(find((node) => node.props?.role === 'alert', find(byType('header'), tree))), "Can't reach the music server right now. Try again in a minute. (Navidrome answered 502)")
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  check('Done again: `tried`, the songs the refused one sent - Navidrome may have taken them', W.asks.filter(([name]) => name === 'edit').slice(-1)[0][1].body.tried, ['a', 'b'])
  scrolled.length = 0
  answer('edit', new ApiError(409, 'changed'))
  await settle()
  tree = draw()
  check('changed in another app meanwhile (409): Edit closed, the words under the actions, asked again',
    [find(byClass('app-playlist-edit-row'), tree).length, words(find(byClass('app-playlist-line'), tree).filter((node) => node.props.role === 'status')), W.asks.filter(([name]) => name === 'one').length],
    [0, "This playlist changed in another app while you were editing it - here it is now. Your changes weren't saved.", 2])
  check('...the page at its top, where that is said', scrolled, [['to', 0]])
  check('...and no Edit from what is drawn until the playlist as it is now has come', find(byClass('app-playlist-edit-toggle'), tree)[0].props['aria-disabled'], true)
  answer('one', { playlist, songs, hidden: 0 })
  await settle()
  tree = draw()
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = draw()
  find(byClass('app-playlist-cancel'), tree)[0].props.onClick()
  tree = draw()
  check('Cancel with nothing changed: out of Edit at once', find(byClass('app-playlist-edit-row'), tree).length, 0)
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = draw()
  find(byClass('app-pin-remove'), tree)[0].props.onClick()
  tree = draw()
  find(byClass('app-playlist-cancel'), tree)[0].props.onClick()
  tree = draw()
  const ask = find(byType(ConfirmLine), tree)[0]
  check('Cancel with changes: asks first', [ask?.props.words, ask?.props.confirm, ask?.props.keep], ['Discard your changes?', 'Discard', 'Keep editing'])
  check('...in the bar, which stays in view however far down the rows are', find(byType(ConfirmLine), find(byType('header'), tree)).length, 1)
  ask.props.onKeep()
  tree = draw()
  check('...Keep editing: still in Edit, the change kept', [find(byType(ConfirmLine), tree).length, find(byClass('app-playlist-edit-row'), tree).length], [0, 2])
  find(byClass('app-playlist-cancel'), tree)[0].props.onClick()
  tree = draw()
  find(byType(ConfirmLine), tree)[0].props.onConfirm()
  tree = draw()
  check('...Discard: out of Edit, the songs as they were, nothing sent', [find(byClass('app-playlist-track'), tree).length, W.asks.filter(([name]) => name === 'edit').length], [3, 2])
  //? a Done refused, then Cancel: Navidrome may have the songs it sent - asked again as Edit closes
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = draw()
  find(byClass('app-pin-remove'), tree)[0].props.onClick()
  tree = draw()
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  answer('edit', new ApiError(502, 'The songs were saved, but Navidrome didn\'t take the name, description or sharing.', 'failed', false, null, 'Navidrome said: locked'))
  await settle()
  tree = draw()
  const asked = W.asks.filter(([name]) => name === 'one').length
  find(byClass('app-playlist-cancel'), tree)[0].props.onClick()
  tree = draw()
  find(byType(ConfirmLine), tree)[0].props.onConfirm()
  tree = draw()
  check('a Done refused, then Discard: the playlist asked again - it may hold what that Done sent', W.asks.filter(([name]) => name === 'one').length - asked, 1)
  check('...no Edit from what is drawn until it answers', find(byClass('app-playlist-edit-toggle'), tree)[0].props['aria-disabled'], true)
  answer('one', { playlist, songs: songs.slice(1), hidden: 0 })
  await settle()
  tree = draw()
  find(byClass('app-playlist-edit-toggle'), tree)[0].props.onClick()
  tree = draw()
  find(byClass('app-playlist-delete'), tree)[0].props.onClick()
  tree = draw()
  const del = find(byType(ConfirmLine), tree)[0]
  check('Delete playlist: asks first, saying it goes from Amperfy too and the songs stay - red, Keep it to keep it',
    [del.props.words, del.props.confirm, del.props.keep, del.props.danger, W.asks.filter(([name]) => name === 'delete').length],
    ['Delete "Late night"? It goes from Navidrome for good - from Amperfy and every other app too, and for everyone it\'s shared with. The songs stay in the library.', 'Delete playlist', 'Keep it', true, 0])
  del.props.onConfirm()
  tree = draw()
  check('...the second step deletes it, Deleting… meanwhile', [W.asks.filter(([name]) => name === 'delete'), find(byType(ConfirmLine), tree)[0].props.busy], [[['delete', 'mine']], true])
  answer('delete', { deleted: true })
  await settle()
  check('...deleted: App told the name and the id, its answer let go, the list asked again', [deleted, S.keptPlaylist('mine'), W.asks.slice(-1)], [[['Late night', 'mine']], null, [['list']]])
  answer('list', { playlists: LIST })
  await settle()
}

finished = true
console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
})()
