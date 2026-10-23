/**
 * Resume what was playing (2.0.0-player.64): lib/resume.ts - what a save sends, what is put back from what deadwax
 * answers, and when a save is due - and app/useResume.ts, the hook App calls once, rendered by a small stand-in for
 * Preact against a fake player and a faked deadwax whose every ask is kept and answered as the check says, on a
 * virtual clock (Date.now, setTimeout and the page's events all the sim's).
 *
 * What it pins:
 *
 *  - toSave then fromSnapshot gives the queue back - the same ids, index, marks, source, Shuffle, nextKey, startedAt,
 *    left, paged, pagedRounds and levels - over 500 seeded runs of upnext.sim's edits (Play Next and Last, moves,
 *    removals, Shuffle on and off, jumps, Previous - back before where playTracks began, too - Repeat's top-ups, the
 *    paged feed), the result keeping whatever of upnext.sim's invariant the queue had, its songs one object per (id,
 *    level) shared by the entries and the source.
 *  - The window: 50 before the song playing, 2,000 in all, startedAt moved down (floored at 0), the marks sliced; a
 *    snapshot over the cap left out; a plain queue none.
 *  - resumed(): exact (the account back, at kept.position); a snapshot that doesn't read (not JSON, v2, a broken
 *    state) a plain list of the same songs; songs dropped, the current one surviving or not (the next survivor at
 *    0, else the last); another app's list at its index, held into the list at 0; ids equal at another index;
 *    nothing for an empty list; a song played to its end the next at 0, or the last at 0; where it came from.
 *  - relevel under the four settings; deviceLabel for each device; the notice's words, logins on and off.
 *  - saveDue for every trigger: nothing for a queue put back and untouched, nothing while nothing changed.
 *  - The hook: nothing saved on open; one full save after a tap, 2 s on; a position save at a song change (1 s on), a
 *    pause (at once), every 30 s of play counted by the player's position updates - none from a timer alone - and a
 *    scrub while paused; a 409 then a full save; the page going away (a beacon; a full save keepalive, or plain past
 *    BEACON_MAX); one request at a time; a 401 stopping it until another session; no rev stopping it for good; a GET
 *    answer dropped when a tap came first; the re-check's three cases (empty or put back and untouched; paused with
 *    logins on; paused with logins off, untouched), at most every 15 s, never while playing, unsaved changes saved
 *    instead; the notice once; the album remembered only while its song still shows.
 *  - (review) a window's focus asked only after its grace, so the click that focused it lands first; the notice not
 *    said again for the same pick-up followed; keepalive by bytes, and by the bytes of every keepalive out; a Repeat
 *    One record under Repeat off saved in full; the 30 s from playing starting; a 422 then a full save; a scrubbed
 *    put-back queue kept; and the real persisted.ts and player/api.ts - the device id, post()'s keepalive, the beacon.
 *
 * Run it with:  node ui/test/resume.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-resume-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/resume.ts', 'src/app/useResume.ts', 'src/lib/upNext.ts', 'src/lib/playQueue.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? hooks with a cursor whose effects run on commit - pins.sim.cjs's stand-in
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
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

//? what the hook reaches outside itself: deadwax's three queue routes and the album ask (faked, every ask kept), the
//? session counter, the device's id and setting, the notice - and the real toQueueTrack, for useShuffleFeed's
//? shuffledTrack
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
fs.copyFileSync(path.join(OUT, 'player/api.js'), path.join(OUT, 'player/api-real.js'))
write('player/api.js', `
const real = require('./api-real')
const W = () => globalThis.__resume
exports.toQueueTrack = real.toQueueTrack
exports.shufflePage = () => new Promise(() => {})
exports.shuffleStart = () => new Promise(() => {})
exports.resumeQueue = (signal) => W().ask('get', null, signal)
exports.saveQueue = (body, keepalive) => W().ask('full', body, null, { keepalive: !!keepalive })
exports.saveQueueAt = (body, beacon) => (beacon ? (W().beacons.push(body), Promise.resolve(null)) : W().ask('at', body))
exports.album = (id, signal) => W().ask('album', id, signal)
exports.rememberAdded = (albums) => W().remembered.push(...albums.map((a) => a.id))
exports.playedAlbum = (id) => (W().remembered.includes(id) ? { id } : null)
`)
write('api/http.js', `
class ApiError extends Error { constructor(status, detail) { super(detail || 'failed'); this.name = 'ApiError'; this.status = status; this.detail = detail } }
exports.ApiError = ApiError
exports.currentSession = () => globalThis.__resume.session
`)
write('state/persisted.js', `
exports.readPlayerDevice = () => globalThis.__resume.device
exports.readPlayerNormalization = () => globalThis.__resume.setting
`)
write('app/usePins.js', `exports.sayPins = (text) => globalThis.__resume.said.push(text)\n`)

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== a virtual clock, and the page's events ===== */

let now = 1_700_000_000_000, seq = 0, tasks = []
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('setTimeout', (fn, delay) => { const task = { at: now + Math.max(0, delay || 0), seq: ++seq, fn, dead: false }; tasks.push(task); return task })
define('clearTimeout', (task) => { if (task) task.dead = true })
Date.now = () => now
const settle = () => new Promise((resolve) => setImmediate(resolve))
async function run(ms) {
  const until = now + ms
  for (;;) {
    await settle(); await settle()
    tasks = tasks.filter((task) => !task.dead).sort((a, b) => a.at - b.at || a.seq - b.seq)
    const next = tasks[0]
    if (!next || next.at > until) { now = until; await settle(); return }
    tasks.shift()
    now = next.at
    next.fn()
  }
}
const listeners = { document: new Map(), window: new Map() }
const on = (where) => ({
  addEventListener: (name, fn) => { if (!listeners[where].has(name)) listeners[where].set(name, new Set()); listeners[where].get(name).add(fn) },
  removeEventListener: (name, fn) => listeners[where].get(name)?.delete(fn),
})
const doc = { visibilityState: 'visible', ...on('document') }
define('document', doc)
globalThis.addEventListener = on('window').addEventListener
globalThis.removeEventListener = on('window').removeEventListener
const fire = (where, name) => { for (const fn of [...(listeners[where].get(name) ?? [])]) fn({ type: name }) }
define('navigator', { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1', maxTouchPoints: 5 })

const R = require(path.join(OUT, 'lib/resume.js'))
//? a window's focus, and the grace after it that its click lands in (RESUME_FOCUS_GRACE_MS)
const focus = async () => { fire('window', 'focus'); await run(R.RESUME_FOCUS_GRACE_MS + 10) }
const U = require(path.join(OUT, 'lib/upNext.js'))
const Q = require(path.join(OUT, 'lib/playQueue.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { useResume } = require(path.join(OUT, 'app/useResume.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))

/** A deterministic "random", as upnext.sim.cjs's. */
function seeded(seed) {
  return () => {
    seed = (seed * 16807) % 2147483647
    return (seed - 1) / 2147483646
  }
}
const track = (id, fields = {}) => ({
  id, title: `song ${id}`, artist: 'Massive Attack', album: 'Mezzanine', albumId: 'mez', coverArt: 'al-mez',
  duration: 200, contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2, ...fields,
})
const album = (n, prefix = '', fields = {}) => Array.from({ length: n }, (_, i) => track(`${prefix}${i + 1}`, fields))
const ids = (queue) => queue.tracks.map((t) => t.id)
const bare = ({ level: _level, ...rest }) => rest
const at = (queue, index) => ({ ...queue, index })

/* ===== the round trip, by property ===== */

console.log('\ntoSave then fromSnapshot: 500 seeded runs of every edit, the queue back as it was')
{
  const problems = []
  const note = (run, step, what) => { if (problems.length < 8) problems.push(`run ${run} step ${step}: ${what}`) }
  //? upnext.sim's invariant, re-stated
  const shape = (queue) => {
    const marks = queue.upNext.marks.slice(queue.index + 1)
    let stage = 0, pass = -Infinity
    for (const mark of marks) {
      const s = mark.from === 'one' ? 0 : mark.from === 'added' ? 1 : 2
      if (s < stage) return `${mark.from} after a later kind`
      stage = s
      if (s === 2) {
        if (mark.pass < pass) return `pass ${mark.pass} after ${pass}`
        pass = mark.pass
      }
    }
    if (queue.upNext.marks.length !== queue.tracks.length) return 'marks out of step'
    if (new Set(queue.upNext.marks.map((m) => m.key)).size !== queue.upNext.marks.length) return 'a key twice'
    if (queue.upNext.marks.some((m, i) => m.at >= 0 && queue.upNext.source[m.at]?.id !== queue.tracks[i].id)) return 'an entry not its place in the list'
    return null
  }
  let compared = 0, shared = 0, behind = 0
  for (let run = 0; run < 500; run++) {
    const random = seeded(run + 7)
    //? a small seed's first draw is always near 0 - which started every run from its first song, null: let it go
    random()
    const pick = (n) => Math.floor(random() * n)
    const level = () => (random() < 0.5 ? 'album' : 'track')
    const size = 1 + pick(7)
    let repeat = U.REPEATS[pick(3)]
    const paged = run % 5 === 0 ? { token: `t${run}`, total: size + 6, fetched: size, scope: 'yours', level: 'track' } : undefined
    let queue = U.toppedUp(U.startUpNext(album(size, '', { level: level() }), random() < 0.3 ? null : pick(size), random() < 0.5, random, paged), repeat, random)
    let extra = 0
    for (let step = 0; step < 25; step++) {
      const op = pick(12)
      const rowKeys = () => queue.upNext.marks.slice(queue.index + 1).map((m) => m.key)
      const someKey = () => { const keys = rowKeys(); return keys.length && random() < 0.85 ? keys[pick(keys.length)] : pick(queue.upNext.nextKey + 2) }
      if (op === 0) queue = U.withNext(queue, Array.from({ length: 1 + pick(2) }, () => track(`n${extra++}`, { level: level() })))
      else if (op === 1) queue = U.withLast(queue, Array.from({ length: 1 + pick(2) }, () => track(`l${extra++}`, { level: level() })))
      else if (op === 2) queue = U.withoutKey(queue, someKey())
      else if (op === 3) queue = U.movedKey(queue, someKey(), pick(6))
      else if (op === 4) queue = U.withoutAdded(queue)
      else if (op === 5) queue = U.withShuffle(queue, random() < 0.5, random)
      else if (op === 6) { repeat = U.REPEATS[pick(3)]; queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, random) }
      else if (op === 7) {
        //? the paged feed: the next page, or - the order whole - a fresh one as the next round
        const p = queue.upNext.paged
        if (p) queue = U.withMore(queue, p.token, Array.from({ length: 1 + pick(3) }, () => track(`p${extra++}`, { level: 'track' })),
          p.fetched >= p.total && repeat === 'all' ? { token: `${p.token}+`, total: 3, fetched: 0, scope: p.scope, level: 'track' } : undefined)
        else queue = U.toppedUp(queue, repeat, random)
      } else if (op === 8) {
        const jumped = U.jumpedTo(queue, someKey())
        const next = jumped ? U.onward(jumped) : null
        if (jumped && next !== null) queue = at(jumped, next)
      } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = at(queue, next) }
      else if (op === 10) {
        //? Previous, early in the song: back past Repeat One's copies - before where playTracks began, too
        const back = U.backward(queue, 0)
        if (back.kind === 'go') queue = at(queue, back.index)
      } else queue = at(queue, Math.min(queue.index + 1, queue.tracks.length - 1))
      queue = U.toppedUp(queue, repeat, random)

      const saving = R.toSave(queue, 12.5)
      const { start } = saving
      const end = start + saving.ids.length
      const navidrome = queue.tracks.slice(start, end).map(bare)
      const back = R.fromSnapshot(saving.snapshot, navidrome, saving.index, 'auto')
      compared++
      if (!back) { note(run, step, 'did not read back'); continue }
      const was = queue.upNext
      const wanted = {
        tracks: queue.tracks.slice(start, end), index: queue.index - start,
        marks: was.marks.slice(start, end), source: was.source, shuffle: was.shuffle, nextKey: was.nextKey,
        startedAt: Math.max(0, was.startedAt - start), left: was.left, paged: was.paged, pagedRounds: was.pagedRounds,
      }
      const got = {
        tracks: back.tracks, index: back.index, marks: back.upNext.marks, source: back.upNext.source, shuffle: back.upNext.shuffle,
        nextKey: back.upNext.nextKey, startedAt: back.upNext.startedAt, left: back.upNext.left, paged: back.upNext.paged, pagedRounds: back.upNext.pagedRounds,
      }
      if (JSON.stringify(got) !== JSON.stringify(wanted)) { note(run, step, `not the same: ${JSON.stringify(got).slice(0, 160)}`); continue }
      //? (Previous leaves played songs after the one playing, which upnext.sim's invariant - a property of what is
      //? still to come - doesn't describe: the round trip must keep whatever the queue had)
      const wrong = shape(back)
      if (wrong !== shape(queue)) note(run, step, wrong ?? 'the invariant changed')
      //? one object per (id, level), shared by the entries and the source
      const byKey = new Map()
      for (const song of [...back.tracks, ...back.upNext.source]) {
        const key = `${song.id}:${song.level}`
        if (byKey.has(key) && byKey.get(key) !== song) { note(run, step, `two objects for ${key}`); break }
        byKey.set(key, song)
      }
      if (back.tracks.some((song) => back.upNext.source.includes(song))) shared++
      if (queue.upNext.startedAt > queue.index) behind++
    }
  }
  check('every step of every run read back the same, keeping the invariant', problems, [])
  check('...thousands of steps compared, and entries shared with the source', [compared >= 12_000, shared > 1_000], [true, true])
  check('...hundreds of them gone back by Previous before where playTracks began', behind > 200 ? true : behind, true)
}

/* ===== the window ===== */

console.log('\nthe window: 50 before, 2,000 in all')
{
  const long = U.startUpNext(album(5000), 0)
  let saving = R.toSave(long, 0)
  check('a 5,000-song list from its first song: its next 2,000 - and a snapshot over the cap, left out',
    [saving.ids.length, saving.start, saving.index, saving.snapshot, saving.ids[1999]], [2000, 0, 0, null, '2000'])
  const mid = { ...U.startUpNext(album(2500), 30), index: 100 }
  saving = R.toSave(mid, 7)
  const snap = JSON.parse(saving.snapshot ?? 'null')
  check('playing the 101st of 2,500: 50 before it, 2,000 in all, the index and startedAt moved down - startedAt floored at 0',
    [saving.start, saving.ids.length, saving.index, saving.ids[saving.index], snap?.startedAt, snap?.marks.length, snap?.marks[0]],
    [50, 2000, 50, '101', 0, 2000, [50, 's', 50, 0]])
  check('...the source songs outside the window kept whole in `extra`, those inside by id alone',
    [Object.keys(snap.extra).length, '1' in snap.extra, '51' in snap.extra, '2051' in snap.extra, snap.extra['1'].title, 'level' in snap.extra['1']], [500, true, false, true, 'song 1', false])
  const small = U.startUpNext(album(20), 5)
  saving = R.toSave(small, 3)
  check('a short list: all of it, as it is', [saving.start, saving.ids.length, saving.index, JSON.parse(saving.snapshot).startedAt], [0, 20, 5, 5])
  check('a plain queue has no account to save', R.toSave({ tracks: album(2), index: 0 }, 0).snapshot, null)
  check('the window helper on its own', [R.windowOf(10, 3), R.windowOf(5000, 100), R.windowOf(2500, 2200), R.windowOf(0, 0)],
    [{ start: 0, end: 10 }, { start: 50, end: 2050 }, { start: 2150, end: 2500 }, { start: 0, end: 0 }])
}

/* ===== what is put back ===== */

console.log('\nresumed(): what is put back from what deadwax answers')
{
  const list = album(5)
  const saved = R.toSave(U.withNext(U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2), [track('x', { level: 'track' })]), 61)
  const kept = (more = {}) => ({ rev: 4, ids_rev: 3, ids: saved.ids, index: saved.index, position: 61, snapshot: saved.snapshot, device: 'phone-1', label: 'iPhone', ...more })
  const navidrome = (keep) => saved.ids.filter((id) => keep(id)).map((id) => (id === 'x' ? bare(track('x')) : bare(list.find((t) => t.id === id))))
  const all = navidrome(() => true)
  //? the snapshot with one more song in its list, outside what Navidrome holds - kept whole in `extra` as `song`
  const withExtra = (song) => {
    const made = JSON.parse(saved.snapshot)
    return JSON.stringify({ ...made, source: [...made.source, 'z'], sourceLevels: `${made.sourceLevels}a`, extra: { ...made.extra, z: song } })
  }
  let back = R.resumed({ index: 2, position: 61, changed_by: 'deadwax', kept: kept() }, all, 'auto', 'phone-1')
  check('exact: the account back - Playing Next, the levels - at kept.position, from this device',
    [back.exact, ids(back.queue), back.queue.index, back.position, back.from, back.queue.upNext.marks[3].from, back.queue.tracks.map((t) => t.level)],
    [true, ['1', '2', '3', 'x', '4', '5'], 2, 61, null, 'added', ['album', 'album', 'album', 'track', 'album', 'album']])
  back = R.resumed({ index: 2, position: 61, changed_by: 'deadwax', kept: kept() }, all, 'auto', 'desk-2')
  check('...from another device: named by its label', back.from, { device: 'iPhone' })
  for (const [label, snapshot] of [['not JSON', '{nope'], ['v2', JSON.stringify({ ...JSON.parse(saved.snapshot), v: 2 })],
    ['a mark out of its source', JSON.stringify({ ...JSON.parse(saved.snapshot), marks: JSON.parse(saved.snapshot).marks.map((m, i) => (i === 0 ? [m[0], 's', 99, 0] : m)) })],
    ['a key twice', JSON.stringify({ ...JSON.parse(saved.snapshot), marks: JSON.parse(saved.snapshot).marks.map((m) => [0, m[1], m[2], m[3]]) })],
    ['startedAt below 0', JSON.stringify({ ...JSON.parse(saved.snapshot), startedAt: -1 })],
    ['an added mark with a place in the list', JSON.stringify({ ...JSON.parse(saved.snapshot), marks: JSON.parse(saved.snapshot).marks.map((m) => (m[1] === 'a' ? [m[0], 'a', 3, 0] : m)) })],
    ['a copy\'s mark past the list', JSON.stringify({ ...JSON.parse(saved.snapshot), marks: JSON.parse(saved.snapshot).marks.map((m, i) => (i === 4 ? [m[0], 'o', 99, 0] : m)) })],
    ...[['a duration in words', { duration: '200' }], ['no title', { title: undefined }], ['an album id a number', { albumId: 7 }]].map(([what, change]) =>
      [`a song kept whole with ${what}`, withExtra({ ...bare(track('z')), ...change })])]) {
    back = R.resumed({ index: 2, position: 61, changed_by: 'deadwax', kept: kept({ snapshot }) }, all, 'auto', 'phone-1')
    check(`a snapshot that doesn't read back (${label}): the same songs as a plain list, at the same song and second`,
      [back.exact, ids(back.queue), back.queue.index, back.position, back.queue.upNext.marks.every((m) => m.from === 'source'), back.queue.upNext.startedAt],
      [true, ['1', '2', '3', 'x', '4', '5'], 2, 61, true, 2])
  }
  back = R.resumed({ index: 2, position: 61, changed_by: 'deadwax', kept: kept({ snapshot: withExtra(bare(track('z'))) }) }, all, 'auto', 'phone-1')
  check('...and the same with that song kept whole as it should be: the account back, the song in the list',
    [back.queue.upNext.marks[3].from, back.queue.upNext.source.map((t) => t.id), back.queue.upNext.source[5].title, back.queue.upNext.source[5].level], ['added', ['1', '2', '3', '4', '5', 'z'], 'song z', 'album'])
  {
    //? (review) an album tapped at song 5, a song played next, then Previous: the song playing is before where
    //? playTracks began - a queue the player really holds, put back as it was, Playing Next included
    let live = U.withNext(U.startUpNext(album(10), 4), [track('n')])
    live = at(live, U.backward(live, 0).index)
    const saving = R.toSave(live, 12)
    const tracks = live.tracks.slice(saving.start, saving.start + saving.ids.length).map(bare)
    back = R.resumed({ index: saving.index, position: 12, changed_by: 'deadwax', kept: kept({ ids: saving.ids, index: saving.index, position: 12, snapshot: saving.snapshot }) }, tracks, 'off', 'phone-1')
    check('Previous before where the album was started (startedAt past the index): the account back, Playing Next still added',
      [live.upNext.startedAt, back.queue.index, back.queue.upNext.startedAt, back.queue.upNext.marks.map((m) => m.from)],
      [4, 3, 4, ['source', 'source', 'source', 'source', 'source', 'added', 'source', 'source', 'source', 'source', 'source']])
    let rounds = U.toppedUp(U.withRepeat(U.startUpNext(album(10), 4), 'all'), 'all')
    rounds = U.toppedUp(at(rounds, 9), 'all')
    rounds = at(rounds, 3)
    const kept2 = R.toSave(rounds, 0)
    back = R.resumed({ index: kept2.index, position: 0, changed_by: 'deadwax', kept: kept({ ids: kept2.ids, index: kept2.index, position: 0, snapshot: kept2.snapshot }) },
      rounds.tracks.slice(kept2.start, kept2.start + kept2.ids.length).map(bare), 'off', 'phone-1')
    check('...and under Repeat All, gone back before it: the list still the album once, not both rounds', back.queue.upNext.source.length, 10)
  }
  //? songs Navidrome dropped as gone
  back = R.resumed({ index: 2, position: 0, changed_by: 'deadwax', kept: kept() }, navidrome((id) => id !== '2'), 'auto', 'phone-1')
  check('songs dropped, the one playing still there: a plain list of what is left, at it and kept.position, levels carried',
    [back.exact, ids(back.queue), back.queue.index, back.position, back.queue.tracks.map((t) => t.level)], [false, ['1', '3', 'x', '4', '5'], 1, 61, ['album', 'album', 'track', 'album', 'album']])
  back = R.resumed({ index: 2, position: 0, changed_by: 'deadwax', kept: kept() }, navidrome((id) => id !== '3'), 'auto', 'phone-1')
  check('...the one playing gone: the first survivor after it, at 0:00', [ids(back.queue), back.queue.index, back.position, back.queue.tracks[back.queue.index].id], [['1', '2', 'x', '4', '5'], 2, 0, 'x'])
  back = R.resumed({ index: 2, position: 0, changed_by: 'deadwax', kept: kept({ index: 5 }) }, navidrome((id) => id !== '5'), 'auto', 'phone-1')
  check('...the last one gone, nothing after it: the last survivor, at 0:00', [back.queue.tracks[back.queue.index].id, back.position], ['4', 0])
  //? another app's
  const foreign = list.slice(0, 3).map(bare)
  back = R.resumed({ index: 1, position: 33, changed_by: 'Symfonium', kept: null }, foreign, 'auto', 'phone-1')
  check('another app\'s: a plain list at its index and second, as songs (Automatic: each its own level)',
    [back.exact, ids(back.queue), back.queue.index, back.position, back.from, back.queue.tracks.map((t) => t.level), back.queue.upNext.shuffle], [false, ['1', '2', '3'], 1, 33, { app: 'Symfonium' }, ['track', 'track', 'track'], false])
  back = R.resumed({ index: 7, position: 33, changed_by: 'Symfonium', kept: null }, foreign, 'auto', 'phone-1')
  check('...an index past its end: held to the last song, at 0:00', [back.queue.index, back.position], [2, 0])
  back = R.resumed({ index: null, position: 33, changed_by: 'Symfonium', kept: null }, foreign, 'off', 'phone-1')
  check('...no index at all: the first song at 0:00; Off: no levels, the songs as Navidrome sent them', [back.queue.index, back.position, back.queue.tracks[0] === foreign[0]], [0, 0, true])
  back = R.resumed({ index: 0, position: 10, changed_by: 'deadwax', kept: null }, foreign, 'auto', 'phone-1')
  check('a deadwax queue with no record (another deadwax, or from before logins): a plain list, no telling where from', [back.exact, back.from], [false, null])
  back = R.resumed({ index: 4, position: 20, changed_by: 'deadwax', kept: kept() }, all, 'auto', 'desk-2')
  check('deadwax\'s ids at another index than the record\'s: a plain list at Navidrome\'s', [back.exact, back.queue.index, back.position, back.from], [false, 4, 20, { device: 'iPhone' }])
  check('Navidrome\'s list empty: nothing', R.resumed({ index: null, position: 0, changed_by: '', kept: null }, [], 'auto', 'phone-1'), null)
  back = R.resumed({ index: 1, position: 199.5, changed_by: 'Symfonium', kept: null }, foreign, 'auto', 'phone-1')
  check('a song played to its end: the next one at 0:00', [back.queue.index, back.position], [2, 0])
  back = R.resumed({ index: 2, position: 199.2, changed_by: 'Symfonium', kept: null }, foreign, 'auto', 'phone-1')
  check('...the queue\'s last song: it again at 0:00', [back.queue.index, back.position], [2, 0])
}

console.log('\nlevels, devices, the notice')
{
  check('relevel: Off none; By song track; By album album; Automatic the saved level, or track',
    ['off', 'song', 'album', 'auto'].map((setting) => [R.relevel('album', setting), R.relevel('track', setting), R.relevel(undefined, setting)]),
    [[undefined, undefined, undefined].map(() => null), ['track', 'track', 'track'], ['album', 'album', 'album'], ['album', 'track', 'track']])
  const saved = R.toSave(U.startUpNext(album(2).map((t) => ({ ...t, level: 'album' })), 0, false, Math.random, { token: 't', total: 9, fetched: 2, scope: 'store', level: 'album' }), 0)
  const levelsUnder = (setting) => {
    const back = R.fromSnapshot(saved.snapshot, album(2), 0, setting)
    return [back.tracks.map((t) => t.level ?? null), back.upNext.source.map((t) => t.level ?? null), back.upNext.paged.level ?? null]
  }
  check('...entries, the source and a paged shuffle\'s level re-fitted together', ['off', 'song', 'album', 'auto'].map(levelsUnder),
    [[[null, null], [null, null], null], [['track', 'track'], ['track', 'track'], 'track'], [['album', 'album'], ['album', 'album'], 'album'], [['album', 'album'], ['album', 'album'], 'album']])
  check('...under Off, the songs as Navidrome sent them - no copies made', R.fromSnapshot(saved.snapshot, album(2), 0, 'off').tracks.every((t) => !('level' in t)), true)
  const UA = {
    iPhone: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1',
    mac: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15',
    windows: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    android: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36',
    linux: 'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0',
    chromebook: 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  }
  check('deviceLabel: an iPhone, an iPad on iPadOS\'s Mac user agent, a Mac, Windows, Android, Linux, a Chromebook, anything else',
    [R.deviceLabel(UA.iPhone, 5), R.deviceLabel(UA.mac, 5), R.deviceLabel(UA.mac, 0), R.deviceLabel(UA.windows, 0), R.deviceLabel(UA.android, 5),
      R.deviceLabel(UA.linux, 0), R.deviceLabel(UA.chromebook, 0), R.deviceLabel('curl/8', 0)],
    ['iPhone', 'iPad', 'Mac', 'Windows PC', 'Android phone', 'Linux PC', 'Chromebook', 'browser'])
  check('the notice with logins on: "your"; with them off "a"/"an"; another app by its name; this device nothing',
    [R.pickedUpWords({ device: 'Mac' }, false), R.pickedUpWords({ device: 'Mac' }, true), R.pickedUpWords({ device: 'iPhone' }, true),
      R.pickedUpWords({ device: 'Android phone' }, true), R.pickedUpWords({ app: 'Symfonium' }, false), R.pickedUpWords({ app: 'Symfonium' }, true), R.pickedUpWords(null, false)],
    ['Picked up from your Mac', 'Picked up from a Mac', 'Picked up from an iPhone', 'Picked up from an Android phone', 'Picked up from Symfonium', 'Picked up from Symfonium', null])
}

/* ===== saveDue ===== */

console.log('\nsaveDue: which save, when')
{
  const queue = U.startUpNext(album(5), 1)
  const base = { tracks: queue.tracks, upNext: queue.upNext, index: 1, position: 10, start: 0, count: 5 }
  const clock = (more = {}) => ({ saved: base, idsRev: 3, countFrom: 0, changedAt: 0, failedAt: null, ...more })
  const T = 100_000
  check('nothing for a queue put back and untouched, whatever the trigger, playing or not',
    ['wait', 'position', 'pause', 'hidden'].flatMap((trigger) => [R.saveDue(clock(), queue, 10, false, T, trigger), R.saveDue(clock(), queue, 10.6, true, T, trigger)]),
    [null, null, null, null, null, null, null, null])
  check('nothing for an empty queue', R.saveDue(clock({ saved: null }), Q.EMPTY_QUEUE, 0, false, T, 'pause'), null)
  const edited = U.withNext(queue, [track('n')])
  check('the songs changed: in full, 2 s after the last change - not before, at once on a pause or going away',
    [R.saveDue(clock({ changedAt: T - 1_999 }), edited, 10, true, T, 'position'), R.saveDue(clock({ changedAt: T - 2_000 }), edited, 10, true, T, 'position'),
      R.saveDue(clock({ changedAt: T - 2_000 }), edited, 10, false, T, 'wait'), R.saveDue(clock({ changedAt: T - 10 }), edited, 10, false, T, 'pause'), R.saveDue(clock({ changedAt: T - 10 }), edited, 10, true, T, 'hidden')],
    [null, 'full', 'full', 'full', 'full'])
  const moved = at(queue, 2)
  check('a song change: a position save 1 s after; in full with no ids_rev, or the song outside the window saved',
    [R.saveDue(clock({ changedAt: T - 999 }), moved, 0, true, T, 'position'), R.saveDue(clock({ changedAt: T - 1_000 }), moved, 0, true, T, 'position'),
      R.saveDue(clock({ changedAt: T - 1_000, idsRev: null }), moved, 0, true, T, 'position'), R.saveDue(clock({ changedAt: T - 1_000, saved: { ...base, count: 2 } }), moved, 0, true, T, 'wait')],
    [null, 'at', 'full', 'full'])
  check('playing on: every 30 s by the player\'s own position updates - never by a wait alone',
    [R.saveDue(clock({ countFrom: T - 29_999 }), queue, 40, true, T, 'position'), R.saveDue(clock({ countFrom: T - 30_000 }), queue, 40, true, T, 'position'),
      R.saveDue(clock({ countFrom: T - 90_000 }), queue, 40, true, T, 'wait')],
    [null, 'at', null])
  check('paused, a scrub: at the wait after it, not from a position update; under a second moved, nothing',
    [R.saveDue(clock(), queue, 40, false, T, 'wait'), R.saveDue(clock(), queue, 40, false, T, 'position'), R.saveDue(clock(), queue, 10.9, false, T, 'wait')], ['at', null, null])
  check('a pause and the page going away: whatever moved, at once', [R.saveDue(clock(), queue, 14, false, T, 'pause'), R.saveDue(clock(), moved, 14, true, T, 'hidden')], ['at', 'at'])
  check('a failure: nothing for 30 s after it, then the next trigger', [R.saveDue(clock({ failedAt: T - 29_000 }), queue, 40, false, T, 'pause'), R.saveDue(clock({ failedAt: T - 30_000 }), queue, 40, false, T, 'pause')], [null, 'at'])
  check('a fresh page\'s first queue: in full', R.saveDue(clock({ saved: null, idsRev: null, changedAt: T - 5_000 }), queue, 1, true, T, 'position'), 'full')
}

/* ===== the hook ===== */

//? deadwax, faked: every ask kept as [kind, body, extra], answered by the check (answer / refuse), or by `auto`
const W = globalThis.__resume = {
  session: 1, device: 'phone-device-1', setting: 'auto', said: [], remembered: [], beacons: [], asks: [], auto: null,
  ask(kind, body, signal, extra = {}) {
    return new Promise((resolve, reject) => {
      const entry = { kind, body, extra, resolve, reject, done: false, aborted: false }
      signal?.addEventListener?.('abort', () => { entry.aborted = true })
      W.asks.push(entry)
      if (W.auto) {
        const answer = W.auto(entry)
        if (answer !== undefined) setTimeout(() => answerAsk(entry, answer), 20)
      }
    })
  },
}
function answerAsk(entry, answer) {
  if (entry.done) return
  entry.done = true
  if (answer instanceof Error) entry.reject(answer)
  else entry.resolve(answer)
}
const asked = (kind) => W.asks.filter((entry) => entry.kind === kind)
const open = (kind) => asked(kind).filter((entry) => !entry.done)

/** The fake player: the hook's view of the engine - the queue and play state it draws, the position its updates
 *  report, and restoreQueue as the engine's (fitted to Repeat off, refused while playing). */
function fakePlayer() {
  const heard = new Set()
  const P = {
    queue: Q.EMPTY_QUEUE, playing: false, at: 0, restored: [],
    position: () => P.at,
    onPosition: (listener) => { heard.add(listener); return () => heard.delete(listener) },
    restoreQueue(queue, position) {
      if (P.playing) return null
      const next = U.toppedUp(U.withRepeat(queue, 'off'), 'off')
      if (!Q.current(next)) return null
      P.restored.push({ ids: ids(next), index: next.index, position })
      P.queue = next
      P.at = position
      return next
    },
    report(seconds) { P.at = seconds; heard.forEach((listener) => listener(seconds)) },
  }
  return P
}

/** A page with the hook, drawn: `draw()` after each change of the player, as App re-renders. */
async function page({ answer = null, playing = false } = {}) {
  W.said.length = 0; W.remembered.length = 0; W.beacons.length = 0; W.asks.length = 0; W.auto = null
  doc.visibilityState = 'visible'
  const player = fakePlayer()
  player.playing = playing
  const render = hooks.root(() => useResume({ ...player }))
  const draw = () => { render(); render.commit() }
  W.auto = (entry) => (entry.kind === 'get' && answer ? answer : undefined)
  draw()
  await run(100)
  W.auto = null
  return { player, draw, render }
}
//? Navidrome's queue as GET /queue answers it: songs, index, position, who saved it, and deadwax's record
const songOf = (id) => ({ id, title: `song ${id}`, artist: 'Portishead', album: 'Dummy', albumId: 'nd-dummy', coverArt: 'al-1', duration: 200, contentType: 'audio/flac', suffix: 'flac' })
const answerOf = (songIds, index, position, more = {}) => ({ tracks: songIds.map(songOf), index, position, changed_by: 'deadwax', shared: false, kept: null, ...more })
const keptOf = (songIds, index, position, more = {}) => {
  const saving = R.toSave(U.startUpNext(songIds.map((id) => ({ ...require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }), level: 'album' })), index), position)
  return { rev: 5, ids_rev: 4, ids: saving.ids, index: saving.index, position, snapshot: saving.snapshot, device: 'desk-device-2', label: 'Mac', ...more }
}
const ok = (entry, rev = 6, idsRev = 6) => answerAsk(entry, { rev, ids_rev: idsRev })
//? the player playing: its position reported every 250 ms, as 'timeupdate' does, for `ms`
async function play(p, ms, from = p.player.at) {
  let t = 0
  while (t < ms) {
    await run(250)
    t += 250
    p.player.report(from + t / 1000)
  }
}

;(async () => {
  console.log('\nthe hook: putting back on open, and nothing saved for it')
  {
    const answer = answerOf(['1', '2', '3'], 1, 95, { kept: keptOf(['1', '2', '3'], 1, 95) })
    const p = await page({ answer })
    check('on open, the queue empty: deadwax asked once, and what it holds put back paused at its second',
      [asked('get').length, p.player.restored], [1, [{ ids: ['1', '2', '3'], index: 1, position: 95 }]])
    p.draw()
    check('...said where it came from, once; its song\'s album asked', [W.said, asked('album').map((entry) => entry.body)], [['Picked up from your Mac'], ['nd-dummy']])
    answerAsk(asked('album')[0], { id: 'nd-dummy', name: 'Dummy' })
    await run(10)
    check('...and remembered, its song still showing', W.remembered, ['nd-dummy'])
    await run(120_000)
    p.draw()
    doc.visibilityState = 'hidden'
    fire('document', 'visibilitychange')
    fire('window', 'pagehide')
    doc.visibilityState = 'visible'
    fire('document', 'visibilitychange')
    check('two minutes on, drawn again, hidden and shown: nothing saved for a queue merely put back', W.asks.filter((entry) => entry.kind === 'full' || entry.kind === 'at').length + W.beacons.length, 0)
    p.render.unmount()
  }
  {
    const answer = answerOf(['1', '2'], 0, 10, { kept: keptOf(['1', '2'], 0, 10, { device: 'phone-device-1' }) })
    const p = await page({ answer })
    check('this device\'s own queue back: no notice', [p.player.restored.length, W.said], [1, []])
    p.render.unmount()
  }
  {
    //? a tap before deadwax answered wins
    W.said.length = 0; W.asks.length = 0
    const player = fakePlayer()
    const render = hooks.root(() => useResume({ ...player }))
    const draw = () => { render(); render.commit() }
    draw()
    const tapped = U.startUpNext([songOf('9')].map((s) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(s, { id: 'a', name: 'A' })), 0)
    player.queue = tapped
    player.playing = true
    draw()
    answerAsk(asked('get')[0], answerOf(['1', '2'], 0, 50, { kept: keptOf(['1', '2'], 0, 50) }))
    await run(100)
    check('a tap before the answer came: the answer dropped, nothing put back, nothing said', [player.restored, W.said, player.queue === tapped], [[], [], true])
    render.unmount()
  }
  {
    //? the album remembered only while its song still shows
    const answer = answerOf(['1', '2'], 0, 50, { kept: keptOf(['1', '2'], 0, 50) })
    const p = await page({ answer })
    p.draw()
    p.player.queue = U.startUpNext([require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf('7'), { id: 'b', name: 'B' })], 0)
    p.draw()
    answerAsk(asked('album')[0], { id: 'nd-dummy', name: 'Dummy' })
    await run(10)
    check('another song showing by the time its album came: not remembered', W.remembered, [])
    p.render.unmount()
  }

  console.log('\nthe hook: what this page saves as it plays')
  {
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2', '3', '4'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.player.at = 0
    p.draw()
    await play(p, 1_750)
    check('a tap played an album: nothing yet, 1.75 s on', W.asks.length, 0)
    await play(p, 500)
    check('...one full save 2 s after it: the ids, the song, the second, this device, the snapshot',
      [asked('full').length, asked('full')[0]?.body.ids, asked('full')[0]?.body.index, asked('full')[0]?.body.device, asked('full')[0]?.body.label, typeof asked('full')[0]?.body.snapshot],
      [1, ['1', '2', '3', '4'], 0, 'phone-device-1', 'iPhone', 'string'])
    ok(asked('full')[0], 1, 1)
    await play(p, 20_000)
    check('...nothing more for 20 s of playing', W.asks.length, 1)
    await play(p, 10_000)
    check('...and at 30 s, one position save against its ids', [asked('at').length, asked('at')[0]?.body.ids_rev, asked('at')[0]?.body.index], [1, 1, 0])
    ok(asked('at')[0], 2, 1)
    //? a song change: a position save 1 s after it
    p.player.queue = { ...p.player.queue, index: 1 }
    p.player.at = 0
    p.draw()
    await play(p, 750, 0)
    check('a song change: nothing at once', asked('at').length, 1)
    await play(p, 500, 0.75)
    check('...a position save a second after it, naming the next song', [asked('at').length, asked('at')[1]?.body.index], [2, 1])
    ok(asked('at')[1], 3, 1)
    //? a pause: at once
    await play(p, 5_000, 1.25)
    p.player.playing = false
    p.draw()
    await run(10)
    check('a pause: a position save at once, at the second it paused', [asked('at').length, asked('at')[2]?.body.position], [3, 6.25])
    ok(asked('at')[2], 4, 1)
    await run(60_000)
    check('...then nothing while paused', W.asks.length, 4)
    //? a scrub while paused
    p.player.report(120)
    await run(500)
    check('a scrub while paused: nothing at once', W.asks.length, 4)
    await run(700)
    check('...a position save a second after it', [asked('at').length, asked('at')[3]?.body.position], [4, 120])
    ok(asked('at')[3], 5, 1)
    //? an edit: in full, 2 s after the last of a burst
    p.player.queue = U.withNext(p.player.queue, [list[3]])
    p.draw()
    await run(1_000)
    p.player.queue = U.withLast(p.player.queue, [list[2]])
    p.draw()
    await run(1_900)
    check('two edits a second apart: nothing until 2 s after the second', asked('full').length, 1)
    await run(200)
    check('...then one full save of both', [asked('full').length, asked('full')[1]?.body.ids], [2, ['1', '2', '4', '3', '3', '4']])
    p.render.unmount()
  }
  {
    //? none from a timer alone: playing, no position updates (a locked phone whose 'timeupdate' stopped too)
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.draw()
    await run(2_100)
    ok(asked('full')[0], 1, 1)
    p.player.at = 70
    await run(90_000)
    check('playing with no position update for 90 s: no position save - the 30 s are counted by updates only', asked('at').length, 0)
    p.player.report(70.25)
    await run(10)
    check('...the next update makes it', asked('at').length, 1)
    p.render.unmount()
  }
  {
    //? a 409, then a full save; one request at a time
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2', '3'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    ok(asked('full')[0], 1, 1)
    p.player.queue = { ...p.player.queue, index: 1 }
    p.draw()
    await play(p, 1_250, 0)
    check('a song change\'s position save', asked('at').length, 1)
    p.player.queue = { ...p.player.queue, index: 2 }
    p.draw()
    await play(p, 1_250, 0)
    check('...another due while the first is still out: it waits', [asked('at').length, asked('full').length], [1, 1])
    answerAsk(asked('at')[0], new ApiError(409, 'The queue changed on another device or in another app'))
    await run(10)
    check('the first answered 409: a full save now, of the queue as it is', [asked('full').length, asked('full')[1]?.body.index, asked('at').length], [2, 2, 1])
    p.render.unmount()
  }
  {
    //? the page going away
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    ok(asked('full')[0], 1, 1)
    await play(p, 5_000)
    doc.visibilityState = 'hidden'
    fire('document', 'visibilitychange')
    fire('window', 'pagehide')
    check('hidden while playing: the position by beacon at once - once for hidden and pagehide together', [W.beacons.length, W.beacons[0]?.ids_rev, W.beacons[0]?.position > 7], [1, 1, true])
    p.player.queue = U.withNext(p.player.queue, [list[1]])
    p.draw()
    fire('window', 'pagehide')
    check('...an edit then going away: a full save at once, keepalive (its body inside BEACON_MAX)', [asked('full').length, asked('full')[1]?.extra.keepalive], [2, true])
    ok(asked('full')[1], 3, 3)
    await run(10)
    const big = Array.from({ length: 1900 }, (_, i) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack({ ...songOf(`s${i}`), id: `a-very-long-navidrome-song-id-${i}` }, { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(big, 0)
    p.draw()
    fire('window', 'pagehide')
    check('...a full save over BEACON_MAX going away: a plain fetch, not keepalive', [asked('full').length, asked('full')[2]?.extra.keepalive], [3, false])
    doc.visibilityState = 'visible'
    p.render.unmount()
  }
  {
    //? a 401: no saving until another session; no rev: no saving for good
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    answerAsk(asked('full')[0], new ApiError(401, 'Sign in to use deadwax.'))
    await play(p, 60_000)
    check('a 401: no save tried again under the same session, a minute of playing on', asked('full').length, 1)
    W.session = 2
    await play(p, 500)
    check('...signed in again (another session): saved at the next trigger', asked('full').length, 2)
    answerAsk(asked('full')[1], { rev: null, ids_rev: null })
    await run(10)
    p.player.queue = { ...p.player.queue, index: 1 }
    p.draw()
    await play(p, 60_000, 0)
    p.player.playing = false
    p.draw()
    await run(16_000)
    await focus()
    await run(100)
    check('an answer with no rev (the break-glass admin keeps no queue): nothing saved or asked again, back at the front included', W.asks.filter((e) => e.kind !== 'album').length, 2)
    W.session = 1
    p.render.unmount()
  }

  console.log('\nthe hook: coming back to the front')
  {
    //? the player empty - the open's ask failed - then Navidrome holds something
    W.asks.length = 0
    W.said.length = 0
    const player = fakePlayer()
    const render = hooks.root(() => useResume({ ...player }))
    const draw = () => { render(); render.commit() }
    draw()
    answerAsk(asked('get')[0], new ApiError(502, 'Navidrome couldn\'t be reached'))
    await run(100)
    await focus()
    check('the open\'s ask failed; back to the front at once: not asked again inside 15 s', asked('get').length, 1)
    await run(15_000)
    await focus()
    check('...15 s on, empty: asked again', asked('get').length, 2)
    answerAsk(asked('get')[1], answerOf(['1', '2'], 1, 30, { kept: keptOf(['1', '2'], 1, 30) }))
    await run(10)
    check('...and what it holds put back', player.restored.map((r) => [r.ids, r.index, r.position]), [[['1', '2'], 1, 30]])
    draw()
    //? put back and untouched: a newer save elsewhere is taken
    await run(16_000)
    fire('document', 'visibilitychange')
    answerAsk(asked('get')[2], answerOf(['1', '2', '3'], 2, 12, { kept: keptOf(['1', '2', '3'], 2, 12, { rev: 9 }) }))
    await run(10)
    check('put back and untouched, another device saved since: that taken, said', [player.restored.length, player.restored[1]?.ids, W.said.slice(-1)], [2, ['1', '2', '3'], ['Picked up from your Mac']])
    draw()
    await run(16_000)
    fire('window', 'pageshow')
    answerAsk(asked('get')[3], answerOf(['1', '2', '3'], 2, 12, { kept: keptOf(['1', '2', '3'], 2, 12, { rev: 9 }) }))
    await run(10)
    check('...the same answer again: not put back twice, not said twice', [player.restored.length, W.said.length], [2, 2])
    render.unmount()
  }
  {
    //? paused after playing here, logins on: only what another device or app saved since
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    ok(asked('full')[0], 7, 7)
    await play(p, 5_000)
    p.player.playing = false
    p.draw()
    await run(10)
    ok(asked('at')[0], 8, 7)
    await run(20_000)
    await focus()
    check('paused after playing here: asked as it comes back', asked('get').length, 1)
    //? rev 9: a beacon of its own as it went away - nobody read that answer, so this page's last rev is still 8
    answerAsk(asked('get')[0], answerOf(['1', '2'], 0, 7.25, { kept: keptOf(['1', '2'], 0, 7.25, { rev: 9, device: 'phone-device-1' }) }))
    await run(10)
    check('...its own save the newest (a beacon since, its rev unread): kept as it is', p.player.restored.length, 0)
    //? never while playing - logins on, so it would otherwise ask
    p.player.playing = true
    p.draw()
    await run(16_000)
    await focus()
    check('...never asked while playing', asked('get').length, 1)
    p.player.playing = false
    p.draw()
    await run(10)
    //? a tap meanwhile wins: the queue changed (Next, paused) while the ask was out
    await run(16_000)
    await focus()
    check('...asked again, paused', asked('get').length, 2)
    p.player.queue = { ...p.player.queue, index: 1 }
    p.draw()
    answerAsk(asked('get')[1], answerOf(['7'], 0, 5, { changed_by: 'Symfonium' }))
    await run(10)
    check('...the queue changed by a tap while that ask was out: its answer dropped', p.player.restored.length, 0)
    await run(2_000)
    //? that tap's own position save, answered
    check('...the tap\'s song change saved', asked('at').length, 2)
    ok(asked('at')[1], 10, 7)
    await run(16_000)
    await focus()
    answerAsk(asked('get').slice(-1)[0], answerOf(['2'], 0, 77, { changed_by: 'Symfonium' }))
    await run(10)
    check('...another app saved since: taken, paused, said by the app\'s name', [p.player.restored.map((r) => r.ids), W.said.slice(-1)], [[['2']], ['Picked up from Symfonium']])
    p.draw()
    p.render.unmount()
  }
  {
    const p = await page()
    W.asks.length = 0
    const list = ['1', '2'].map((id) => require(path.join(OUT, 'player/api-real.js')).toQueueTrack(songOf(id), { id: 'nd-dummy', name: 'Dummy' }))
    p.player.queue = U.startUpNext(list, 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    ok(asked('full')[0], 7, 7)
    await play(p, 5_000)
    p.player.playing = false
    p.draw()
    await run(10)
    ok(asked('at')[0], 8, 7)
    await run(20_000)
    await focus()
    answerAsk(asked('get').slice(-1)[0], answerOf(['1', '2', '3'], 2, 12, { shared: true, kept: keptOf(['1', '2', '3'], 2, 12, { rev: 12 }) }))
    await run(10)
    check('paused here, logins off (one queue for everyone): someone else\'s newer queue never taken', p.player.restored.length, 0)
    await run(16_000)
    await focus()
    check('...and, known to be shared, not even asked for again', asked('get').length, 1)
    //? never while playing
    p.player.playing = true
    p.draw()
    await run(16_000)
    await focus()
    check('never asked while playing', asked('get').length, 1)
    //? unsaved changes, paused: saved instead, nothing asked
    p.player.playing = false
    p.draw()
    await run(10)
    const fulls = asked('full').length
    p.player.queue = U.withNext(p.player.queue, [list[0]])
    p.draw()
    await run(10)
    await focus()
    check('changes not yet saved, back to the front: saved at once, nothing asked', [asked('full').length - fulls, asked('get').length], [1, 1])
    p.render.unmount()
  }

  console.log('\nthe hook (review): a focusing click, the notice once, keepalive by bytes, and the save rules the build chose')
  const realApi = require(path.join(OUT, 'player/api-real.js'))
  const queueOf = (songIds, fields = {}) => songIds.map((id) => realApi.toQueueTrack({ ...songOf(id), ...fields }, { id: 'nd-dummy', name: 'Dummy' }))
  //? a page that played two songs here and paused, both saves answered - what a desktop tab left open is
  async function playedThenPaused() {
    const p = await page()
    W.asks.length = 0
    p.player.queue = U.startUpNext(queueOf(['1', '2']), 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    ok(asked('full')[0], 7, 7)
    await play(p, 5_000)
    p.player.playing = false
    p.draw()
    await run(10)
    ok(asked('at')[0], 8, 7)
    await run(20_000)
    return p
  }
  {
    //? a desktop: the mousedown that focuses the window fires 'focus'; its click, ~100 ms on, is the Play
    const p = await playedThenPaused()
    fire('window', 'focus')
    await run(100)
    p.player.playing = true
    p.draw()
    await run(R.RESUME_FOCUS_GRACE_MS + 100)
    check('focus, then the click that focused the window pressing Play: nothing asked - no other queue can land under it',
      [asked('get').length, p.player.restored.length], [0, 0])
    p.player.playing = false
    p.draw()
    await run(16_000)
    fire('window', 'focus')
    await run(R.RESUME_FOCUS_GRACE_MS - 50)
    check('...focus with no click: not asked inside the grace', asked('get').length, 0)
    await run(60)
    check('...asked once it has passed', asked('get').length, 1)
    fire('document', 'visibilitychange')
    p.render.unmount()
  }
  {
    //? the phone plays on and saves every 30 s; the desktop's tab, put back from it and untouched, comes to the front
    const answer = answerOf(['1', '2', '3'], 1, 95, { kept: keptOf(['1', '2', '3'], 1, 95, { label: 'iPhone' }) })
    const p = await page({ answer })
    p.draw()
    answerAsk(asked('album')[0], { id: 'nd-dummy', name: 'Dummy' })
    await run(10)
    await run(16_000)
    fire('document', 'visibilitychange')
    answerAsk(asked('get')[1], answerOf(['1', '2', '3'], 1, 125, { kept: keptOf(['1', '2', '3'], 1, 125, { rev: 6, label: 'iPhone' }) }))
    await run(10)
    p.draw()
    check('a queue put back and untouched, taken again from the same device with the same songs: its second moved, nothing said again, its album not asked again',
      [p.player.restored.map((r) => r.position), W.said, asked('album').length], [[95, 125], ['Picked up from your iPhone'], 1])
    await run(16_000)
    fire('document', 'visibilitychange')
    answerAsk(asked('get')[2], answerOf(['1', '2', '3'], 2, 5, { kept: keptOf(['1', '2', '3'], 2, 5, { rev: 7, label: 'iPhone' }) }))
    await run(10)
    p.draw()
    check('...the next song there: still the same pick-up, nothing said', [p.player.restored.length, W.said.length], [3, 1])
    await run(16_000)
    fire('document', 'visibilitychange')
    answerAsk(asked('get')[3], answerOf(['4', '5'], 0, 5, { kept: keptOf(['4', '5'], 0, 5, { rev: 8, label: 'iPhone' }) }))
    await run(10)
    p.draw()
    check('...other songs played there since: said again', [p.player.restored.length, W.said], [4, ['Picked up from your iPhone', 'Picked up from your iPhone']])
    await run(16_000)
    fire('document', 'visibilitychange')
    answerAsk(asked('get')[4], answerOf(['4', '5'], 0, 50, { kept: keptOf(['4', '5'], 0, 50, { rev: 9, label: 'Mac', device: 'desk-device-3' }) }))
    await run(10)
    check('...the same songs from another device: said, by it', [p.player.restored.length, W.said.slice(-1)], [5, ['Picked up from your Mac']])
    p.render.unmount()
  }
  {
    //? picked up, then played HERE and paused: the same songs taken from the same device later are a pick-up again
    const answer = answerOf(['1', '2', '3'], 1, 95, { kept: keptOf(['1', '2', '3'], 1, 95, { label: 'iPhone' }) })
    const p = await page({ answer })
    p.draw()
    p.player.playing = true
    p.draw()
    await play(p, 3_000, 95)
    p.player.playing = false
    p.draw()
    await run(10)
    ok(asked('at')[0], 6, 4)
    await run(16_000)
    await focus()
    answerAsk(asked('get').slice(-1)[0], answerOf(['1', '2', '3'], 2, 5, { kept: keptOf(['1', '2', '3'], 2, 5, { rev: 9, label: 'iPhone' }) }))
    await run(10)
    check('picked up from the iPhone, played here, then the iPhone again with the same songs: said again', [p.player.restored.length, W.said], [2, ['Picked up from your iPhone', 'Picked up from your iPhone']])
    p.render.unmount()
  }
  {
    //? keepalive by bytes: a playlist whose titles are Japanese, played far enough in that the songs before the window
    //? are kept whole - fewer characters than BEACON_MAX, more bytes
    const p = await page()
    W.asks.length = 0
    const name = '夜に駆ける'.repeat(8)
    const list = queueOf(Array.from({ length: 190 }, (_, i) => `j${i}`), { title: name, artist: name, album: name })
    p.player.queue = U.startUpNext(list, 185)
    p.draw()
    fire('window', 'pagehide')
    const sent = asked('full')[0]?.body
    const text = JSON.stringify(sent)
    check('a body under BEACON_MAX in characters but over it in bytes (the case itself)', [text.length <= R.BEACON_MAX, Buffer.byteLength(text) > R.BEACON_MAX], [true, true])
    check('...going away, it goes as an ordinary request - a keepalive over the budget would be refused outright', asked('full')[0]?.extra.keepalive, false)
    check('utf8Length counts what Buffer does: ASCII, accents, kana, an emoji, the body', [R.utf8Length('abc'), R.utf8Length('é'), R.utf8Length('夜'), R.utf8Length('😀'), R.utf8Length(text) === Buffer.byteLength(text)],
      [3, 2, 3, 4, true])
    p.render.unmount()
  }
  {
    //? two keepalive saves out at once share the browser's 64 KiB: the second over it goes as an ordinary request
    const p = await page()
    W.asks.length = 0
    const long = (n, tag) => queueOf(Array.from({ length: n }, (_, i) => `a-long-navidrome-song-id-${tag}-${i}`))
    p.player.queue = U.startUpNext(long(420, 'a'), 0)
    p.draw()
    fire('window', 'pagehide')
    p.player.queue = U.startUpNext(long(420, 'b'), 0)
    p.draw()
    fire('window', 'pagehide')
    const bytes = asked('full').map((entry) => Buffer.byteLength(JSON.stringify(entry.body)))
    check('two full saves going away, each well inside BEACON_MAX, together over it (the case itself)', [bytes.every((b) => b > 25_000 && b < R.BEACON_MAX), bytes[0] + bytes[1] > R.BEACON_MAX], [true, true])
    check('...the first keepalive, the second - the first still out - an ordinary request', asked('full').map((entry) => entry.extra.keepalive), [true, false])
    ok(asked('full')[0], 1, 1)
    ok(asked('full')[1], 2, 2)
    await run(10)
    p.player.queue = U.startUpNext(long(420, 'c'), 0)
    p.draw()
    fire('window', 'pagehide')
    check('...both answered: the next keepalive again', asked('full')[2]?.extra.keepalive, true)
    p.render.unmount()
  }
  {
    //? (7a) a record made under Repeat One - its copies in its ids - put back under Repeat off: the queue put back isn't
    //? the record's ids, so a song change is saved in full, never as a position against ids it doesn't match
    const one = U.toppedUp(U.withRepeat(U.startUpNext(queueOf(['1', '2', '3']), 0), 'one'), 'one')
    const saving = R.toSave(one, 40)
    const kept = { rev: 5, ids_rev: 4, ids: saving.ids, index: 0, position: 40, snapshot: saving.snapshot, device: 'desk-device-2', label: 'Mac' }
    const p = await page({ answer: answerOf(saving.ids, 0, 40, { kept }) })
    p.draw()
    check('a record with Repeat One\'s copies, put back under Repeat off: the copies dropped (the case itself)', [saving.ids.length, p.player.restored[0]?.ids], [3 + U.REPEAT_AHEAD, ['1', '2', '3']])
    W.asks.length = 0
    p.player.queue = { ...p.player.queue, index: 1 }
    p.draw()
    await run(1_200)
    check('...then a song change: saved in full, no position save', [asked('full').length, asked('at').length, asked('full')[0]?.body.ids], [1, 0, ['1', '2', '3']])
    p.render.unmount()
  }
  {
    //? (7b) the 30 s are counted from playing starting: a pause's save, a minute paused, then play
    const p = await playedThenPaused()
    await run(40_000)
    const before = asked('at').length
    p.player.playing = true
    p.draw()
    await play(p, 25_000)
    check('paused a minute after its save, then played 25 s: no position save yet', asked('at').length - before, 0)
    await play(p, 6_000)
    check('...one at 30 s of playing', asked('at').length - before, 1)
    p.render.unmount()
  }
  {
    //? (7c) a position save the server refuses as past the ids it kept (a 422): saved in full at once, as a 409's
    const p = await page()
    W.asks.length = 0
    p.player.queue = U.startUpNext(queueOf(['1', '2', '3']), 0)
    p.player.playing = true
    p.draw()
    await play(p, 2_250)
    ok(asked('full')[0], 1, 1)
    p.player.queue = { ...p.player.queue, index: 1 }
    p.draw()
    await play(p, 1_250, 0)
    answerAsk(asked('at')[0], new ApiError(422, 'That song isn\'t in the queue deadwax kept'))
    await run(10)
    check('a position save answered 422: a full save at once, of the queue as it is', [asked('full').length, asked('full')[1]?.body.index], [2, 1])
    p.render.unmount()
  }
  {
    //? (7e) paused, saved: an Up Next edit, then a song change inside its 2 s - the edit is still owed in full, 2 s
    //? after the song change (the last change), with no position updates while paused to ask for it
    const p = await playedThenPaused()
    const fulls = asked('full').length
    const ats = asked('at').length
    p.player.queue = U.withNext(p.player.queue, queueOf(['9']))
    p.draw()
    await run(1_500)
    p.player.queue = { ...p.player.queue, index: 1 }
    p.player.at = 0
    p.draw()
    await run(1_900)
    check('paused, an edit then Next 1.5 s later: nothing until 2 s after the Next', [asked('full').length - fulls, asked('at').length - ats], [0, 0])
    await run(200)
    check('...then one full save of both, at the song Next went to, and no position save', [asked('full').length - fulls, asked('full').at(-1)?.body.ids, asked('full').at(-1)?.body.index, asked('at').length - ats],
      [1, ['1', '9', '2'], 1, 0])
    p.render.unmount()
  }
  {
    //? (7d) a queue put back from this device, scrubbed (so no longer merely put back) and saved: a newer save of this
    //? device's own - a beacon it never read - must not replace it at the front
    const answer = answerOf(['1', '2'], 0, 10, { kept: keptOf(['1', '2'], 0, 10, { device: 'phone-device-1' }) })
    const p = await page({ answer })
    p.draw()
    W.asks.length = 0
    p.player.report(120)
    await run(1_200)
    check('a queue put back, scrubbed while paused: a position save of it', [asked('at').length, asked('at')[0]?.body.position], [1, 120])
    ok(asked('at')[0], 6, 4)
    await run(16_000)
    await focus()
    answerAsk(asked('get')[0], answerOf(['1', '2'], 0, 30, { kept: keptOf(['1', '2'], 0, 30, { rev: 7, device: 'phone-device-1' }) }))
    await run(10)
    check('...back to the front, a save of this device\'s own since: the scrubbed queue kept', [p.player.restored.length, p.player.at], [1, 120])
    p.render.unmount()
  }

  console.log('\nthe device\'s id, and the saves as they go out (the real persisted.ts, api/http.ts and player/api.ts)')
  {
    const OUT2 = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-resume-real-'))
    execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
      'src/state/persisted.ts', 'src/player/api.ts', '--rootDir', 'src', '--outDir', OUT2,
      '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
      '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
    ], { cwd: UI, stdio: 'inherit' })
    fs.mkdirSync(path.join(OUT2, 'node_modules/preact'), { recursive: true })
    fs.writeFileSync(path.join(OUT2, 'node_modules/preact/hooks.js'), `exports.useState = (v) => [v, () => {}]\nexports.useCallback = (f) => f\n`)
    const stored = new Map()
    let refusing = false
    define('localStorage', {
      getItem(key) { if (refusing) throw new Error('SecurityError'); return stored.has(key) ? stored.get(key) : null },
      setItem(key, value) { if (refusing) throw new Error('QuotaExceededError'); stored.set(key, String(value)) },
      removeItem(key) { stored.delete(key) },
    })
    const persisted = require(path.join(OUT2, 'state/persisted.js'))
    const KEY = persisted.STORAGE_KEYS.playerDevice
    const ID = /^[A-Za-z0-9_-]{16}$/
    stored.set(KEY, 'kept_device-0001')
    check('its key; a kept id read back as it is, and not written again', [KEY, persisted.readPlayerDevice(), stored.get(KEY)], ['deadwax-player-device', 'kept_device-0001', 'kept_device-0001'])
    stored.set(KEY, 'not an id!')
    const remade = persisted.readPlayerDevice()
    check('...a kept value that isn\'t one: made again, 16 characters, and kept', [ID.test(remade), stored.get(KEY) === remade, persisted.readPlayerDevice() === remade], [true, true, true])
    stored.delete(KEY)
    const first = persisted.readPlayerDevice()
    check('...nothing kept: made once - the next read is the same', [ID.test(first), persisted.readPlayerDevice()], [true, first])
    refusing = true
    check('...storage refused: an id all the same', ID.test(persisted.readPlayerDevice()), true)
    refusing = false
    stored.delete(KEY)
    const crypto = globalThis.crypto
    const random = Math.random
    define('crypto', undefined)
    Math.random = () => 0.999
    const fallback = persisted.readPlayerDevice()
    Math.random = random
    define('crypto', crypto)
    check('...no crypto.getRandomValues (an old browser): Math.random makes it', fallback, '-'.repeat(16))

    const api = require(path.join(OUT2, 'player/api.js'))
    const sent = []
    define('fetch', async (address, init = {}) => {
      sent.push({ address, method: init.method, keepalive: init.keepalive, type: init.headers?.['Content-Type'], body: init.body })
      return { ok: true, status: 200, json: async () => ({ rev: 1, ids_rev: 1 }) }
    })
    const full = { ids: ['1'], index: 0, position: 3, device: 'phone-device-1', label: 'iPhone', snapshot: null }
    await api.saveQueue(full, true)
    await api.saveQueue(full)
    check('a full save going away reaches fetch keepalive; an ordinary one doesn\'t',
      sent.map((r) => [r.address, r.method, r.keepalive ?? null, r.type]),
      [['/deadwax/navidrome/queue', 'POST', true, 'application/json'], ['/deadwax/navidrome/queue', 'POST', null, 'application/json']])
    sent.length = 0
    const beacons = []
    const at = { ids_rev: 1, index: 0, position: 3, device: 'phone-device-1', label: 'iPhone' }
    define('navigator', { ...navigator, sendBeacon: (address, blob) => { beacons.push([address, blob.type, blob.size]); return true } })
    await api.saveQueueAt(at, true)
    check('a position save going away: sendBeacon, its body JSON, and no fetch', [beacons, sent.length], [[['/deadwax/navidrome/queue/at', 'application/json', JSON.stringify(at).length]], 0])
    define('navigator', { ...navigator, sendBeacon: () => false })
    await api.saveQueueAt(at, true)
    check('...sendBeacon refusing it: a keepalive fetch instead', sent.map((r) => [r.address, r.method, r.keepalive, r.body]), [['/deadwax/navidrome/queue/at', 'POST', true, JSON.stringify(at)]])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
