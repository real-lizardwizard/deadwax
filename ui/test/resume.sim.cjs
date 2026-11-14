/**
 * Resume what was playing (2.0.0-player.64): lib/resume.ts - what a save sends, what is put back from what deadwax
 * answers, and when a save is due - and app/useResume.ts, the hook App calls once, rendered by a small stand-in for
 * Preact against a fake player and a faked deadwax whose every ask is kept and answered as the check says, on a
 * virtual clock (Date.now, setTimeout and the page's events all the sim's).
 *
 * What it pins:
 *
 *  - toSave then fromSnapshot gives the queue back - the same ids, index, marks, source, Shuffle, nextKey, startedAt,
 *    left, paged, pagedRounds and levels - over 1,000 seeded runs (500 before 2.1.18) of upnext.sim's edits (Play Next and Last, moves,
 *    removals, Shuffle on and off, jumps, Previous - back before where playTracks began, too - Repeat's top-ups, the
 *    paged feed), the result keeping whatever of upnext.sim's invariant the queue had, its songs one object per (id,
 *    level) shared by the entries and the source.
 *  - The window: 50 before the song playing, 2,000 in all, startedAt moved down (floored at 0), the marks sliced; a
 *    snapshot over the cap left out; a plain queue none.
 *  - resumed(): exact (the account back, at kept.position); a snapshot that doesn't read (not JSON, v3, a broken
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
 *  - (2.1.3) History - Up Next's songs behind the one playing - the same rows, keys and songs after the round trip, at
 *    every step of those runs (a row's tap of History's among them; Previous moving startedAt down as the engine does
 *    now, and half the time leaving it as apps before 2.1.3 saved it), and at the window's edge (a run of copies cut by
 *    it); HISTORY_BACK equal to RESUME_BEFORE.
 *  - (2.1.15) the queue's id back with it at every step of those runs; a snapshot without one, or with one that isn't,
 *    given a new one - unless, saved without one (the iPhone app before its port), it is the queue the page holds:
 *    then the page's (the review: else the web's own songs in it showed twice in Up Next).
 *  - (2.1.18) a roll-back's account back with it at every step of those runs (History's taps and older rows brought
 *    back among them): how far it had got (`reached`, while it is after the song playing) and the starts each row
 *    brought back carries - Up Next drawing the same songs to come and holding the same starts after a reload; a queue
 *    never rolled back saved with neither key, as before; `starts` and `reached` that don't read, null. (2.1.18 review)
 *    The version: v2 whenever a reader before 2.1.18 would read the queue back wrong (starts, reached, or no list song
 *    at or before the song playing - snapshotVersion), else v1; v2 read as v1 is. And THE READER BEFORE 2.1.18 - 5e3460c's
 *    lib files, frozen in fixtures/resume-2.1.17 (James's tabs opened before 2.1.18 run it; the iPhone app's 0.9 a port
 *    of it) - given each kind: a v1 read whole, as before; a v2 the plain list of every song in the window, in order, at
 *    the song playing, kept whole by restoreQueue's Repeat (off, One, All); the same snapshots written v1 losing songs.
 *  - (2.1.22) a library's shuffle played long: its list saved as the window's own songs (savedList), so 2,000 songs in -
 *    and 20,000 - it is still saved (2.1.17's toSave, which 2.1.21's was, left it out from 750), put back exactly and
 *    paged, and its feed carries on from where it was: the songs it plays from there those it would have played with no
 *    reload - on to the order's end and every song heard once (Repeat off), a fresh order as the next round (All) - and
 *    the reader before 2.1.18 reads it whole too; the window beginning among a song's Repeat One copies; at every step
 *    of the 1,000 runs a library's shuffle's list the songs its window names, and nothing it took out one of them.
 *  - (2.1.23) gone back twice with a full save between while how far it had got played (the iPhone port's review's
 *    probe): the second tap a song change alone, saved by its position, and deadwax's record - that save at the song
 *    tapped - carrying the reach (v2), so it puts back what a full save would (Repeat off 1 2 3 1 2 x 3, not
 *    1 2 3 x; Repeat All drawing every song moved down), the reader before 2.1.18 the plain list; played past the
 *    reach, left out. And at every step of the 1,000 runs, History's first row tapped and Previous: each one saved by
 *    its position alone reads back from this step's snapshot as a full save of it would.
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

console.log('\ntoSave then fromSnapshot: 1,000 seeded runs of every edit, the queue back as it was')
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
  let compared = 0, shared = 0, behind = 0, histories = 0, rolled = 0, brought = 0, reachedKept = 0, startsKept = 0, pagedSaved = 0, pagedNamed = 0
  let pagedLeft = 0, leftNamed = 0, positionOnly = 0, positionReach = 0
  for (let run = 0; run < 1000; run++) {
    const random = seeded(run + 7)
    //? a small seed's first draw is always near 0 - which started every run from its first song, null: let it go
    random()
    //? (2.1.18) older rows brought back in every other run, the rest as before - so Previous before where playTracks
    //? began (which a roll-back to an older row, starting the queue over at 0, makes rarer) still comes up by the hundred
    const bringsBack = run % 2 === 0
    const pick = (n) => Math.floor(random() * n)
    const level = () => (random() < 0.5 ? 'album' : 'track')
    const size = 1 + pick(7)
    let repeat = U.REPEATS[pick(3)]
    const paged = run % 5 === 0 ? { token: `t${run}`, total: size + 6, fetched: size, scope: 'yours', level: 'track' } : undefined
    let queue = U.toppedUp(U.startUpNext(album(size, '', { level: level() }), random() < 0.3 ? null : pick(size), random() < 0.5, random, paged), repeat, random)
    let extra = 0
    for (let step = 0; step < 25; step++) {
      const op = pick(13)
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
        //? (2.1.3) a row's tap - of History's now and then (an entry before the song playing)
        const before = queue.upNext.marks.slice(0, queue.index).map((m) => m.key)
        const jumped = U.jumpedTo(queue, before.length && random() < 0.3 ? before[pick(before.length)] : someKey(), repeat)
        if (jumped) { queue = at(jumped.queue, jumped.index); if (jumped.back) rolled++ }
      } else if (op === 12 && bringsBack) {
        //? (2.1.18) older rows brought back: entries of the queue's (moved, while before History's floor) and songs from elsewhere
        const rows = Array.from({ length: 1 + pick(3) }, (_, i) => {
          const starts = Array.from({ length: 1 + pick(2) }, (_, k) => 1_800_000_000_000 + compared * 100 + i * 3 + k)
          //? the row's song as UpNext.tsx passes it - queued(..., 'songs')'s copy, at a level of its own (the 2.1.18 review)
          if (queue.index > 0 && random() < 0.5) { const p = pick(queue.index); return { track: { ...queue.tracks[p], level: level() }, starts, entry: queue.upNext.marks[p].key } }
          return { track: track(`b${extra++}`, { level: level() }), starts, entry: null }
        })
        const jumped = U.broughtBack(queue, rows, repeat)
        if (jumped) { queue = jumped.queue; brought++ }
      } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = at(queue, next) }
      else if (op === 10) {
        //? Previous, early in the song: back past Repeat One's copies - before where playTracks began, too
        const back = U.backward(queue, 0)
        //? (2.1.3) as the engine moves now (wentBack: startedAt follows it down), or - half the time - as an app before
        //? 2.1.3, or the iPhone's 0.2, saved it: startedAt left above the song playing
        if (back.kind === 'go') queue = random() < 0.5 ? U.wentBack(queue, back.index) : at(queue, back.index)
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
      //? (2.1.3 review) startedAt past the song playing's run - an app before 2.1.3 saved it so - comes back lowered to it
      let runStart = queue.index
      while (runStart > 0 && was.marks[runStart].from === 'one') runStart--
      //? (2.1.18) how far it had got, while that is after the song playing (and in the window); the marks' starts with them
      const reachAt = was.marks.findIndex((m) => m.key === was.reached)
      const reached = reachAt > queue.index && reachAt < end ? was.reached : undefined
      //? (2.1.22) a library's shuffle: its list back as the songs the window's entries are (a copy its song's), in the
      //? list's order - each place counted among those - and nothing of what was taken out: none of it is one of
      //? those places (leftNamed, below), and a library's shuffle never reads it
      const named = was.paged ? [...new Set(was.marks.slice(start, end).filter((m) => m.at >= 0).map((m) => m.at))].sort((a, b) => a - b) : null
      const placed = (at) => (named && at >= 0 ? named.indexOf(at) : at)
      if (named) {
        pagedSaved++
        if (named.length < was.source.length) pagedNamed++
        if (was.left.length) pagedLeft++
        if (was.left.some((gone) => named.includes(gone.at))) leftNamed++
      }
      const wanted = {
        tracks: queue.tracks.slice(start, end), index: queue.index - start,
        marks: was.marks.slice(start, end).map((m) => (named && m.at >= 0 ? { ...m, at: placed(m.at) } : m)),
        source: named ? named.map((at) => was.source[at]) : was.source, shuffle: was.shuffle, nextKey: was.nextKey,
        startedAt: Math.min(Math.max(0, was.startedAt - start), runStart - start),
        left: named ? [] : was.left,
        paged: was.paged, pagedRounds: was.pagedRounds, reached,
      }
      const got = {
        tracks: back.tracks, index: back.index, marks: back.upNext.marks, source: back.upNext.source, shuffle: back.upNext.shuffle,
        nextKey: back.upNext.nextKey, startedAt: back.upNext.startedAt, left: back.upNext.left, paged: back.upNext.paged, pagedRounds: back.upNext.pagedRounds,
        reached: back.upNext.reached,
      }
      if (reached !== undefined) reachedKept++
      if (wanted.marks.some((m) => m.starts)) startsKept++
      if (JSON.stringify(got) !== JSON.stringify(wanted)) { note(run, step, `not the same: ${JSON.stringify(got).slice(0, 160)}`); continue }
      //? (2.1.15) the same queue: its id back with it
      if (back.upNext.id !== was.id) note(run, step, `its id came back as ${back.upNext.id} for ${was.id}`)
      //? (2.1.3) History after a reload is History before it - the same rows, keys and songs
      const rows = (q) => U.upNextView(q, repeat).history.map((row) => `${row.key}:${row.track.id}`).join()
      if (rows(back) !== rows(queue)) note(run, step, `History came back otherwise: ${rows(back)} for ${rows(queue)}`)
      if (rows(queue)) histories++
      //? (2.1.18) ...and Up Next the same songs to come, every one, holding the same starts
      const ahead = (q) => { const v = U.upNextView(q, repeat, Infinity); return [...v.added, ...(v.list?.rows ?? [])].map((row) => `${row.key}:${row.track.id}`).join() }
      if (ahead(back) !== ahead(queue)) note(run, step, `Up Next came back otherwise: ${ahead(back)} for ${ahead(queue)}`)
      if (JSON.stringify(U.heldStarts(back)) !== JSON.stringify(U.heldStarts(queue))) note(run, step, 'the starts held came back otherwise')
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
      //? (2.1.23) a move that leaves the queue's account as it was - History's first row tapped, or Previous, with the
      //? furthest unit what it was - is a song change alone (changedSince), saved by its position: deadwax's record is
      //? then THIS step's snapshot at the song moved to, which must read back as a full save of the move would - how far
      //? it had got, Up Next's songs to come, what restoreQueue keeps under every Repeat. No draw of `random`: the runs
      //? go on as before
      const history = U.upNextView(queue, repeat).history
      const tap = history.length ? U.jumpedTo(queue, history[0].key, repeat) : null
      const prev = U.backward(queue, 0)
      for (const moved of [tap?.queue ?? null, prev.kind === 'go' ? U.wentBack(queue, prev.index) : null]) {
        const baseline = { tracks: queue.tracks, upNext: queue.upNext, index: queue.index, position: 12.5, start, count: end - start }
        if (!moved || R.changedSince(baseline, moved, 12.5) !== 'song' || moved.index < start || moved.index >= end) continue
        positionOnly++
        if (moved.upNext.reached !== undefined && moved.upNext.marks.findIndex((m) => m.key === moved.upNext.reached) > moved.index) positionReach++
        const asRecord = R.fromSnapshot(saving.snapshot, navidrome, moved.index - start, 'auto')
        const full = R.toSave(moved, 12.5)
        const asFull = R.fromSnapshot(full.snapshot, moved.tracks.slice(full.start, full.start + full.ids.length).map(bare), full.index, 'auto')
        //? (Repeat All's time round shuffled by one seeded draw each, so the two put-backs are asked alike)
        const kept = (q) => q && ['off', 'one', 'all'].map((r) => { const t = U.toppedUp(U.withRepeat(q, r), r, seeded(1)); return t.tracks.slice(t.index).map((x) => x.id).join(' ') })
        const said = (q) => q && JSON.stringify([q.upNext.reached ?? null, ahead(q), kept(q)])
        if (said(asRecord) !== said(asFull)) note(run, step, `a move saved by its position reads back otherwise: ${said(asRecord)} for ${said(asFull)}`)
      }
    }
  }
  check('every step of every run read back the same, keeping the invariant', problems, [])
  check('...thousands of steps compared, and entries shared with the source', [compared >= 12_000, shared > 1_000], [true, true])
  check(`...hundreds of them gone back by Previous before where playTracks began (${behind})`, behind > 100 ? true : behind, true)
  check(`...thousands with a History, back the same (${histories})`, histories > 5_000 ? true : histories, true)
  check(`...(2.1.18) roll-backs (${rolled} History taps, ${brought} older rows brought back) - saved with how far they had got (${reachedKept}) and the starts held (${startsKept})`,
    [rolled > 100 || rolled, brought > 300 || brought, reachedKept > 1000 || reachedKept, startsKept > 1000 || startsKept], [true, true, true, true])
  check(`...(2.1.23) moves saved by their position alone (${positionOnly}) read back as a full save of them would - every one back before how far it had got (any other move back names a new furthest)`,
    [positionOnly > 3000 || positionOnly, positionReach === positionOnly], [true, true])
  check(`...(2.1.22) libraries' shuffles (${pagedSaved}), their lists saved as the window's own songs - fewer than they had in ${pagedNamed}; songs taken out of ${pagedLeft}, none of them a place the window keeps`,
    [pagedSaved > 2000 || pagedSaved, pagedNamed > 300 || pagedNamed, pagedLeft > 300 || pagedLeft, leftNamed], [true, true, true, 0])
}

/* ===== the window ===== */

console.log('\nthe window: 50 before, 2,000 in all')
{
  //? (2.1.3) History at the window's edge: song 100 played three times under Repeat One, its first play the 51st
  //? entry back - History stops short of it, before a reload and after, so a reload never shrinks what it showed
  {
    let q = at(U.startUpNext(album(200), 0), 99)
    q = U.toppedUp(q, 'one'); q = at(q, 100); q = U.toppedUp(q, 'one'); q = at(q, 101)
    q = U.withRepeat(q, 'off')
    q = at(q, 151)
    const saving = R.toSave(q, 0)
    const back = R.fromSnapshot(saving.snapshot, q.tracks.slice(saving.start, saving.start + saving.ids.length).map(bare), saving.index, 'auto')
    const rows = (x) => U.upNextView(x, 'off').history.map((row) => `${row.key}:${row.track.id}`)
    check('History at the window\'s edge, a run of copies cut by it: the same before and after a reload', [rows(q).length, rows(q)[0], rows(back).join() === rows(q).join()], [49, `${q.upNext.marks[102].key}:101`, true])
    check('...History goes back as far as a reload keeps: HISTORY_BACK is RESUME_BEFORE', [U.HISTORY_BACK, U.HISTORY_BACK === R.RESUME_BEFORE], [50, true])
  }
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

  //? (2.1.18) a roll-back's account: written only when there is one, read back strictly
  const plain = U.startUpNext(album(6), 0)
  const keysOf = (snapshot) => Object.keys(JSON.parse(snapshot))
  const playedOn = at(plain, 4)
  const rolledBack = U.jumpedTo(playedOn, playedOn.upNext.marks[1].key, 'off').queue
  const passedIt = at(rolledBack, 5)
  check('a queue never rolled back - and one played on past where it had got - saved as before, with neither `reached` nor `starts`',
    [keysOf(R.toSave(plain, 0).snapshot).filter((k) => k === 'reached' || k === 'starts'), keysOf(R.toSave(passedIt, 0).snapshot).filter((k) => k === 'reached' || k === 'starts')], [[], []])
  const brought = U.broughtBack(playedOn, [{ track: track('x'), starts: [11, 12], entry: null }], 'off').queue
  const made = JSON.parse(R.toSave(brought, 0).snapshot)
  check('...one rolled back to an older row: how far it had got (5\'s key) and the starts of the row it brought back, by key; the marks four apiece',
    [made.reached, made.starts, made.marks.every((m) => m.length === 4)], [playedOn.upNext.marks[4].key, [[brought.upNext.marks[0].key, [11, 12]]], true])
  const read = (edit) => {
    const snapshot = JSON.parse(R.toSave(brought, 0).snapshot)
    edit(snapshot)
    return R.fromSnapshot(JSON.stringify(snapshot), brought.tracks.map(bare), 0, 'auto')
  }
  const xKey = brought.upNext.marks[0].key
  check('...read back: its starts on their mark again, how far it had got', [read(() => {}).upNext.marks[0].starts, read(() => {}).upNext.reached], [[11, 12], playedOn.upNext.marks[4].key])
  check('...`starts` that don\'t read - not a list, an entry not a pair, no moments, a moment not a whole number or below 0, a key it hasn\'t, a key twice - null',
    [read((x) => { x.starts = {} }), read((x) => { x.starts = [[xKey]] }), read((x) => { x.starts = [[xKey, []]] }), read((x) => { x.starts = [[xKey, [1.5]]] }),
      read((x) => { x.starts = [[xKey, [-1]]] }), read((x) => { x.starts = [[99, [1]]] }), read((x) => { x.starts = [[xKey, [1]], [xKey, [2]]] }), read((x) => { x.starts = [['0', [1]]] })],
    [null, null, null, null, null, null, null, null])
  const one = U.toppedUp(U.broughtBack(playedOn, [{ track: track('x'), starts: [11], entry: null }], 'off').queue, 'one')
  const onCopy = JSON.parse(R.toSave(one, 0).snapshot)
  onCopy.starts = [[one.upNext.marks[1].key, [5]]]
  check('...a copy\'s key: null', R.fromSnapshot(JSON.stringify(onCopy), one.tracks.map(bare), 0, 'auto'), null)
  check('...`reached` not a whole number: null; one at or before the song playing, or a key it hasn\'t: let go',
    [read((x) => { x.reached = 'far' }), read((x) => { x.reached = xKey }).upNext.reached, read((x) => { x.reached = 999 }).upNext.reached], [null, undefined, undefined])

  //? (2.1.18 review) the version: v2 whenever a reader before 2.1.18 would read the queue back wrong, v1 otherwise
  const vOf = (queue) => JSON.parse(R.toSave(queue, 0).snapshot).v
  const mark = (key, from) => ({ key, from, at: from === 'source' ? 0 : -1, pass: from === 'source' ? 0 : -1 })
  const listThenAdded = [mark(0, 'source'), mark(1, 'added')]
  check('(2.1.18 review) snapshotVersion: a list song at or before the song playing, nothing brought back, not rolled back - v1; `reached`, `starts`, or the only list songs after it - v2',
    [R.snapshotVersion(listThenAdded, 1, false, false), R.snapshotVersion(listThenAdded, 0, false, false), R.snapshotVersion(listThenAdded, 1, true, false),
      R.snapshotVersion(listThenAdded, 1, false, true), R.snapshotVersion([mark(0, 'added'), mark(1, 'source')], 0, false, false), R.snapshotVersion([mark(0, 'one'), mark(1, 'added')], 1, false, false)],
    [1, 1, 2, 2, 2, 2])
  check('...toSave: a queue never rolled back (Playing Next too), one played on past where it had got - v1; rolled back, rows brought back - v2',
    [vOf(plain), vOf(U.withNext(plain, [track('n')])), vOf(passedIt), vOf(rolledBack), vOf(brought)], [1, 1, 1, 2, 2])
  const v2read = R.fromSnapshot(R.toSave(rolledBack, 0).snapshot, rolledBack.tracks.map(bare), rolledBack.index, 'auto')
  const levelledBack = U.jumpedTo(at(U.startUpNext(album(4, '', { level: 'album' }), 0), 3), 1, 'off').queue
  check('...a v2 read as a v1 is: the account back, how far it had got with it; its levels for a list put back plain',
    [v2read?.upNext.marks.length, v2read?.upNext.reached, R.savedLevels(R.toSave(levelledBack, 0).snapshot, 4)], [6, playedOn.upNext.marks[4].key, ['album', 'album', 'album', 'album']])

  //? (2.1.18 review) THE READER BEFORE 2.1.18 - what James's tabs opened before it run, and what the iPhone app's 0.9
  //? ports (DeadwaxCore's Resume.swift reads v1 alone too, in fromSnapshot and savedLevels, its resumed falling back to
  //? plainQueue - read, not run here): 5e3460c's lib files, frozen. The page and deadwax ship together, so it is only
  //? ever a READER of what 2.1.18 writes
  const OLD = require(path.join(__dirname, 'fixtures/resume-2.1.17/resume.cjs'))
  const OLDU = require(path.join(__dirname, 'fixtures/resume-2.1.17/upNext.cjs'))
  const oldReads = (queue, v, setting = 'auto') => {
    const saving = R.toSave(queue, 30)
    const snapshot = v === undefined ? saving.snapshot : JSON.stringify({ ...JSON.parse(saving.snapshot), v })
    const tracks = queue.tracks.slice(saving.start, saving.start + saving.ids.length).map(bare)
    const back = OLD.resumed({ index: saving.index, position: 30, changed_by: 'deadwax', kept: { rev: 1, ids_rev: 1, ids: saving.ids, index: saving.index, position: 30, snapshot, device: 'desk-2', label: 'Mac' } },
      tracks, setting, 'phone-1')
    //? then restoreQueue's, in both: toppedUp(withRepeat(saved, repeat), repeat) - under each Repeat, the songs it holds
    //? (Repeat One's copies of the song playing left out) and the song playing
    const repeats = ['off', 'one', 'all'].map((repeat) => {
      const q = OLDU.toppedUp(OLDU.withRepeat(back.queue, repeat), repeat)
      return [q.tracks.filter((_, i) => q.upNext.marks[i].from !== 'one').map((t) => t.id).join(' '), q.tracks[q.index].id]
    })
    return { saved: [saving.ids.join(' '), saving.ids[saving.index]], back, repeats }
  }
  const whole = (read) => read.repeats.every(([songs, playing]) => songs === read.saved[0] && playing === read.saved[1])
  //? never rolled back: v1, read whole - the account, Playing Next and the levels with it
  const plainOld = oldReads(U.withNext(U.startUpNext(album(6, '', { level: 'album' }), 2), [track('x', { level: 'track' })]))
  check('(2.1.18 review) the reader before 2.1.18, given a queue never rolled back (v1): read whole, as before - Playing Next added, the levels kept, every song under each Repeat',
    [plainOld.back.queue.upNext.marks[3].from, plainOld.back.queue.tracks.map((t) => t.level).join(' '), whole(plainOld)], ['added', 'album album album track album album album', true])
  //? the review's: older rows from another queue - X then Y, brought back ahead of an album at its first song
  const abc = U.startUpNext(['A', 'B', 'C', 'D', 'E', 'F'].map((id) => track(id)), 0)
  const other = (id, starts) => ({ track: track(id, { album: 'Dummy', albumId: 'dum' }), starts, entry: null })
  const xy = U.broughtBack(abc, [other('X', [5]), other('Y', [6])], 'off').queue
  //? a roll-back across Repeat All's rounds: A B C twice round, the second's B playing - its first B tapped
  let rounds = U.toppedUp(at(U.startUpNext(['A', 'B', 'C'].map((id) => track(id)), 0), 2), 'all')
  rounds = U.toppedUp(at(rounds, U.onward(rounds)), 'all')
  rounds = U.toppedUp(at(rounds, U.onward(rounds)), 'all')
  const acrossRounds = U.jumpedTo(rounds, rounds.upNext.marks[1].key, 'all').queue
  //? and no list song in the window at or before the song playing: an album's first song, then 60 played next, the
  //? 55th playing - nothing rolled back (2.1.17 itself put this one back without the album's 2 and 3, Repeat off or One)
  const added60 = at(U.withNext(U.startUpNext(album(3, '', { level: 'album' }), 0), album(60, 'n', { level: 'track' })), 55)
  const kinds = [['older rows from another queue (X Y, then the album)', xy], ['rolled back across Repeat All\'s rounds', acrossRounds],
    ['rolled back on one time round', rolledBack], ['an older row from another queue, the album\'s History moved down after it', brought], ['60 songs played next, the 55th playing', added60]]
  check('...given each kind 2.1.18 writes as v2: v2, the songs in the window as saved, the song playing',
    kinds.map(([, queue]) => [JSON.parse(R.toSave(queue, 30).snapshot).v, oldReads(queue).saved]),
    [[2, ['X Y A B C D E F', 'X']], [2, ['A B C A B C A B C', 'B']], [2, ['1 2 3 4 5 6', '2']], [2, ['x 1 2 3 4 5 6', 'x']], [2, [[...album(60, 'n').slice(4).map((t) => t.id), '2', '3'].join(' '), 'n55']]])
  for (const [label, queue] of kinds) {
    const read = oldReads(queue)
    check(`...${label}: not read (another version) - the plain list of every one, in order, at the song playing and its second, kept whole under Repeat off, One and All`,
      [read.back.exact, read.back.position, read.back.queue.upNext.marks.every((m) => m.from === 'source' && m.pass === 0), whole(read)], [true, 30, true, true])
  }
  check('...what it costs: the account (songs added, Shuffle, the starts brought back, how far it had got) and the levels - from the setting, as for another app\'s list',
    ['auto', 'album', 'track', 'off'].map((setting) => oldReads(levelledBack, undefined, setting).back.queue.tracks.map((t) => t.level ?? '-').join(' ')),
    ['track track track track', 'album album album album', 'track track track track', '- - - -'])
  //? ...why: the same snapshots written v1, as b38d557 wrote them - read, and read wrong
  check('...the same written v1 (as b38d557 did): Repeat off and One keep X and Y alone; across the rounds, only the first round; 60 played next, the album\'s 2 and 3 gone',
    [xy, acrossRounds, added60].map((queue) => oldReads(queue, 1).repeats.map(([songs]) => songs.split(' ').length)), [[2, 2, 8], [3, 3, 9], [56, 56, 58]])
  {
    //? ...the last one 2.1.17's own: its toSave (v1) of the 60 played next, put back by its own reader
    const saving = OLD.toSave(added60, 30)
    const back = OLD.resumed({ index: saving.index, position: 30, changed_by: 'deadwax', kept: { rev: 1, ids_rev: 1, ids: saving.ids, index: saving.index, position: 30, snapshot: saving.snapshot, device: 'desk-2', label: 'Mac' } },
      added60.tracks.slice(saving.start, saving.start + saving.ids.length).map(bare), 'auto', 'phone-1')
    const lost = (L, queue) => ['off', 'one', 'all'].map((repeat) => { const q = L.toppedUp(L.withRepeat(queue, repeat), repeat); return q.tracks.filter((_, i) => q.upNext.marks[i].from !== 'one').length })
    const now = R.resumed({ index: saving.index, position: 30, changed_by: 'deadwax', kept: { rev: 1, ids_rev: 1, ids: saving.ids, index: saving.index, position: 30, snapshot: saving.snapshot, device: 'desk-2', label: 'Mac' } },
      added60.tracks.slice(saving.start, saving.start + saving.ids.length).map(bare), 'auto', 'phone-1')
    check('...2.1.17 putting back its own v1 of it lost the album\'s 2 and 3 too (Repeat off, One); 2.1.18 reading that same v1 keeps all 58 (passPlaying\'s fallback)',
      [JSON.parse(saving.snapshot).v, lost(OLDU, back.queue), lost(U, now.queue), now.queue.upNext.marks[3].from], [1, [56, 56, 58], [58, 58, 58], 'added'])
  }
  check('the window helper on its own', [R.windowOf(10, 3), R.windowOf(5000, 100), R.windowOf(2500, 2200), R.windowOf(0, 0)],
    [{ start: 0, end: 10 }, { start: 50, end: 2050 }, { start: 2150, end: 2500 }, { start: 0, end: 0 }])
}

/* ===== (2.1.22) a library's shuffle, played long ===== */

console.log('\n(2.1.22) a library\'s shuffle 2,000 songs in: saved, put back paged, its feed carrying on')
{
  //? the review's: the list kept whole, every song played before the window whole in `extra` - over RESUME_SNAPSHOT_MAX
  //? some 750 songs in, the queue came back a plain list with no `paged`: Repeat off, the shuffle stopped after the
  //? songs it had; Repeat All, those songs went round again instead of a fresh order
  const F = require(path.join(OUT, 'app/useShuffleFeed.js'))
  const OLD = require(path.join(__dirname, 'fixtures/resume-2.1.17/resume.cjs'))
  const PAGE = 200 // src/routes/navidrome.py SHUFFLE_PAGE
  //? songs as Navidrome sends them: 22-character ids, a cover's id with its stamp, ordinary titles
  const id22 = (prefix, n) => `${prefix}${String(n).padStart(22 - prefix.length, '0')}`
  const libSong = (n) => track(id22('s', n), {
    title: `An ordinary song title ${n}`, artist: 'An artist of ordinary name', album: `An album title ${Math.floor(n / 12)}`,
    albumId: id22('a', Math.floor(n / 12)), coverArt: `al-${id22('a', Math.floor(n / 12))}_67a1b2c3`, duration: 241.53, level: 'track',
  })
  //? deadwax's orders: each token's its own shuffle of the library, made once
  const orders = new Map()
  const orderOf = (token, size) => {
    const name = `${token}:${size}`
    if (!orders.has(name)) {
      const random = seeded(Number(token.split('-')[1]) * 7919)
      const order = Array.from({ length: size }, (_, n) => libSong(n))
      for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(random() * (i + 1)); [order[i], order[j]] = [order[j], order[i]] }
      orders.set(name, order)
    }
    return orders.get(name)
  }
  //? useShuffleFeed, as it asks: fewer than FEED_BELOW of the shuffle's songs ahead - the next page from `fetched`, or,
  //? the order whole and Repeat All, a fresh order (claimed, never starting with the song that ends this one)
  const feed = (queue, repeat, size) => {
    const p = queue.upNext.paged
    if (!p || F.songsAhead(queue) >= F.FEED_BELOW) return queue
    if (p.fetched < p.total) return U.withMore(queue, p.token, orderOf(p.token, size).slice(p.fetched, p.fetched + PAGE))
    if (repeat !== 'all') return queue
    const token = `order-${Number(p.token.split('-')[1]) + 1}`
    const first = F.startingElsewhere(orderOf(token, size).slice(0, PAGE), queue.tracks[queue.tracks.length - 1].id, () => 0.5)
    return U.withMore(queue, p.token, first, { token, total: size, fetched: 0, scope: 'yours', level: 'track' })
  }
  //? `count` songs on, as the engine moves, the feed asked after each; the songs heard
  const play = (queue, count, repeat, size) => {
    const heard = []
    for (let i = 0; i < count; i++) {
      const next = U.onward(queue)
      if (next === null) break
      queue = U.toppedUp(feed(at(queue, next), repeat, size), repeat)
      heard.push(queue.tracks[queue.index].id)
    }
    return { queue, heard }
  }
  const start = (size) => feed(U.startUpNext(orderOf('order-1', size).slice(0, PAGE), 0, false, seeded(1),
    { token: 'order-1', total: size, fetched: PAGE, scope: 'yours', level: 'track' }), 'off', size)
  const kept = (saving) => ({ index: saving.index, position: 42, changed_by: 'deadwax',
    kept: { rev: 1, ids_rev: 1, ids: saving.ids, index: saving.index, position: 42, snapshot: saving.snapshot, device: 'desk-2', label: 'Mac' } })
  const navidromeOf = (queue, saving) => queue.tracks.slice(saving.start, saving.start + saving.ids.length).map(bare)
  const pagedOf = (queue) => JSON.stringify(queue.upNext.paged ?? null)

  //? before: the measure the review took, 2.1.17's toSave (2.1.21's wrote the list the same)
  {
    const size = 5000
    const at700 = play(start(size), 700, 'off', size).queue
    const at750 = play(at700, 50, 'off', size).queue
    const old700 = OLD.toSave(at700, 42).snapshot
    check(`before 2.1.22, the list kept whole: ${old700?.length} units 700 songs in, none from 750 - now ${R.toSave(at700, 42).snapshot.length} and ${R.toSave(at750, 42).snapshot?.length}`,
      [old700 !== null && old700.length > 200_000, OLD.toSave(at750, 42).snapshot, R.toSave(at750, 42).snapshot !== null], [true, null, true])
  }

  for (const [repeat, size, on] of [['off', 5000, 4000], ['all', 1500, 1500]]) {
    const before = play(start(size), 2000, repeat, size)
    const q = before.queue
    const saving = R.toSave(q, 42)
    const made = JSON.parse(saving.snapshot ?? 'null')
    const back = R.resumed(kept(saving), navidromeOf(q, saving), 'auto', 'phone-1')
    check(`Repeat ${repeat}, a library of ${size}, 2,000 songs in (${q.upNext.source.length} fetched): saved (${saving.snapshot?.length} units) - the list the window's own songs, nothing kept whole, v1`,
      [saving.snapshot !== null, made?.source.length, Object.keys(made?.extra ?? {}).length, made?.v, made && made.source.every((id) => saving.ids.includes(id))],
      [true, new Set(made?.marks.map((m) => m[2])).size, 0, 1, true])
    check('...put back exactly, a library\'s shuffle still - the same order (token), fetched, total, scope and level - at the song playing',
      [back?.exact, pagedOf(back.queue), back.queue.tracks.map((t) => t.id).join() === saving.ids.join(), back.queue.tracks[back.queue.index].id],
      [true, pagedOf(q), true, q.tracks[q.index].id])
    //? ...and on: the songs it plays from there are the ones it would have played had nothing been reloaded
    const carried = play(back.queue, on, repeat, size)
    const unbroken = play(q, on, repeat, size)
    const tokens = (queue) => (queue.upNext.paged ? [queue.upNext.paged.token, queue.upNext.paged.fetched] : null)
    check(`...its feed carrying on from where it was: the songs it plays from there (${unbroken.heard.length}) those it would have played without the reload, the order as far`,
      [carried.heard.length, carried.heard.join() === unbroken.heard.join(), tokens(carried.queue)], [unbroken.heard.length, true, tokens(unbroken.queue)])
    if (repeat === 'off') {
      check('...Repeat off: on to the order\'s end, then nothing - every song of the library heard once', [U.onward(carried.queue), new Set([...before.heard, ...carried.heard, q.upNext.source[0].id]).size, before.heard.length + carried.heard.length + 1], [null, size, size])
    } else {
      //? the second order's last song, then the third's first page as the feed handed it on
      const third = carried.queue.upNext.marks.findIndex((m) => m.pass === 2)
      check('...Repeat All: past its order\'s end a fresh order as the next time round (order-3, its own round) - not the songs it had going round',
        [tokens(carried.queue)?.[0], third > back.queue.index, carried.queue.tracks.slice(third, third + PAGE).map((t) => t.id).join() === F.startingElsewhere(orderOf('order-3', size).slice(0, PAGE), carried.queue.tracks[third - 1].id, () => 0.5).map((t) => t.id).join()],
        ['order-3', true, true])
      //? ...and on, eighteen thousand songs later: no bigger than the window
      const later = play(q, 18_000, repeat, size).queue
      const far = R.toSave(later, 42).snapshot
      check(`...20,000 songs in (${later.upNext.source.length} fetched, round ${later.upNext.paged.token}): still saved, ${far?.length} units - under RESUME_SNAPSHOT_MAX by half`,
        [far !== null && far.length < R.RESUME_SNAPSHOT_MAX / 2, !!far && JSON.parse(far).source.length <= 2000], [true, true])
    }
    //? the reader before 2.1.18 (James's tabs opened before, the iPhone's 0.9): a valid snapshot of the same queue - read
    //? whole, a library's shuffle too
    const old = OLD.resumed(kept(saving), navidromeOf(q, saving), 'auto', 'phone-1')
    check('...the reader before 2.1.18 (2.1.17\'s) reads it whole too: exact, paged, the same marks and list',
      [old?.exact, pagedOf(old.queue), JSON.stringify(old.queue.upNext.marks) === JSON.stringify(back.queue.upNext.marks), old.queue.upNext.source.map((t) => t.id).join() === made.source.join()],
      [true, pagedOf(q), true, true])
  }
  {
    //? the window's edge among a song's copies: Repeat One on the 30th song, 60 times round as it ends each time - the window begins 50
    //? entries back, among its copies, its own entry before it - the copies still name its place
    const size = 500
    let q = play(start(size), 29, 'off', size).queue
    q = U.toppedUp(q, 'one')
    for (let i = 0; i < 60; i++) q = U.toppedUp(at(q, q.index + 1), 'one')
    const saving = R.toSave(q, 42)
    const back = R.resumed(kept(saving), navidromeOf(q, saving), 'auto', 'phone-1')
    const firstCopy = q.upNext.marks[saving.start]
    check('...the window beginning among Repeat One\'s copies of a song, its own entry before the window: saved and put back exactly, paged, the copies the same song',
      [firstCopy.from, q.upNext.marks.findIndex((m) => m.from === 'source' && m.at === firstCopy.at) < saving.start, back?.exact, pagedOf(back.queue),
        back.queue.upNext.marks.filter((m) => m.from === 'one').every((m) => back.queue.upNext.source[m.at]?.id === q.tracks[q.index].id)],
      ['one', true, true, pagedOf(q), true])
  }
  //? a list as played is kept whole as before: Repeat All's rounds and Shuffle are made from it
  const listed = at(U.startUpNext(album(2500), 0), 100)
  const listSaved = JSON.parse(R.toSave(listed, 0).snapshot ?? 'null')
  check('...a list that isn\'t a library\'s shuffle: kept whole, as before', [listSaved?.source.length, Object.keys(listSaved?.extra ?? {}).length], [2500, 500])
}

/* ===== (2.1.23) gone back twice, a save between ===== */

console.log('\n(2.1.23) gone back twice, a full save between while how far it had got played: the record still carries it')
{
  //? the iPhone port's review (its Core probe): Repeat All, 3 songs, the second time round's 2 playing; History's
  //? first 1 tapped (rolled back, `reached` the later 2); played on to that 2 again; Play Next x - a full save, while
  //? the reach is the song playing; the first 1 tapped again - the reach the same, so a song change alone, saved by
  //? its position: deadwax's record is that full save at the song tapped
  const OLD = require(path.join(__dirname, 'fixtures/resume-2.1.17/resume.cjs'))
  const on = (q) => U.toppedUp(at(q, U.onward(q)), 'all')
  let q = U.toppedUp(U.startUpNext(album(3), 0), 'all')
  for (let i = 0; i < 4; i++) q = on(q)
  const first1 = q.upNext.marks[0].key
  const later2 = q.upNext.marks[4].key
  q = U.jumpedTo(q, first1, 'all').queue
  for (let i = 0; i < 4; i++) q = on(q)
  const played = U.withNext(q, [track('x')])
  const between = R.toSave(played, 30)
  const tapped = U.jumpedTo(played, first1, 'all').queue
  const baseline = { tracks: played.tracks, upNext: played.upNext, index: played.index, position: 30, start: between.start, count: between.ids.length }
  check('the setup: the reach (the later 2) playing at the save between, then the first 1 tapped - the reach the same, a song change alone',
    [played.tracks[played.index].id, played.upNext.reached === later2, played.upNext.marks[played.index].key === later2, tapped.upNext.reached === later2, R.changedSince(baseline, tapped, 30)],
    ['2', true, true, true, 'song'])
  //? deadwax's record: the save between's ids and snapshot, the index the position save sent
  const record = (snapshot, index, ids = between.ids) => ({ index, position: 0, changed_by: 'deadwax',
    kept: { rev: 2, ids_rev: 1, ids, index, position: 0, snapshot, device: 'phone-1', label: 'iPhone' } })
  const navidrome = between.ids.map((id) => bare(id === 'x' ? track('x') : album(3).find((t) => t.id === id)))
  const back = R.resumed(record(between.snapshot, tapped.index - between.start), navidrome, 'auto', 'desk-2')
  const full = R.toSave(tapped, 0)
  const wholly = R.resumed(record(full.snapshot, full.index, full.ids), full.ids.map((id) => bare(id === 'x' ? track('x') : album(3).find((t) => t.id === id))), 'auto', 'desk-2')
  const under = (queue, repeat) => { const t = U.toppedUp(U.withRepeat(queue, repeat), repeat); return t.tracks.slice(t.index).map((x) => x.id).join(' ') }
  const drawn = (queue) => { const v = U.upNextView(queue, 'all', Infinity); return (v.list?.rows ?? []).map((row) => row.track.id).join(' ') }
  check('...the save between written with how far it had got (the song playing\'s own unit) - v2',
    [JSON.parse(between.snapshot).reached === later2, JSON.parse(between.snapshot).v], [true, 2])
  check('...put back from the record at the song tapped: how far it had got with it - Repeat off keeps the songs moved back down (1 2 3 1 2 x 3, not 1 2 3 x), as a full save of it would',
    [back.queue.upNext.reached === later2, under(back.queue, 'off'), under(wholly.queue, 'off'), under(back.queue, 'one') === under(wholly.queue, 'one')], [true, '1 2 3 1 2 x 3', '1 2 3 1 2 x 3', true])
  check('...and Repeat All\'s Up Next draws every song moved back down (x among them, added after the 2 it moved down with), as with a full save',
    [drawn(back.queue), drawn(back.queue) === drawn(wholly.queue)], ['2 3 1 2 x 3', true])
  //? the reader before 2.1.18 (James's tabs opened before it, the iPhone's 0.9 before its port): v2, so the plain list
  const old = OLD.resumed(record(between.snapshot, tapped.index - between.start), navidrome, 'auto', 'desk-2')
  check('...the reader before 2.1.18 given it: not read (v2) - the plain list of the window, in order, at the song tapped',
    [old.queue.upNext.marks.every((m) => m.from === 'source' && m.pass === 0), old.queue.tracks.map((t) => t.id).join(' '), old.queue.index], [true, between.ids.join(' '), tapped.index - between.start])
  //? played on past the reach, then back: a new furthest - a change saved in full - so the reach is left out there
  const past = on(on(played))
  check('...played on past it: left out (any move back from there names a new furthest, saved in full)',
    ['reached' in JSON.parse(R.toSave(past, 0).snapshot), U.jumpedTo(past, first1, 'all').queue.upNext === past.upNext], [false, false])
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
  //? (2.1.15) the queue's id, saved and put back - so the starts of its songs on one device are the same queue's on the
  //? other; a snapshot without one (the web before 2.1.15, the phone before its port) or with one that isn't: a new one
  {
    const made = JSON.parse(saved.snapshot)
    const put = (snapshot) => R.resumed({ index: 2, position: 61, changed_by: 'deadwax', kept: kept({ snapshot }) }, all, 'auto', 'phone-1').queue.upNext.id
    const fresh = [put(JSON.stringify({ ...made, id: undefined })), put(JSON.stringify({ ...made, id: 'not one!' })), put(JSON.stringify({ ...made, id: 'x'.repeat(65) }))]
    check('(2.1.15) the queue\'s id saved in the snapshot and put back with it; none, or one that isn\'t, a new one each time',
      [/^[A-Za-z0-9_-]{1,64}$/.test(made.id), put(saved.snapshot) === made.id, fresh.every((id) => /^[A-Za-z0-9_-]{1,64}$/.test(id) && id !== made.id), new Set(fresh).size],
      [true, true, true, 3])
  }
  {
    //? (2.1.15 review) saved WITHOUT an id by an app that keeps none (the iPhone app before its port) - but of the queue
    //? this page holds (the same list, the same songs under the keys both have): the page's id kept, so the starts this
    //? page made in it stay its rows rather than being drawn again above. Any other queue held, or none: a new one
    const made = JSON.parse(saved.snapshot)
    const noId = JSON.stringify({ ...made, id: undefined })
    const put = (snapshot, holding) => R.resumed({ index: 2, position: 61, changed_by: 'deadwax', kept: kept({ snapshot }) }, all, 'auto', 'desk-2', holding).queue.upNext.id
    const holding = U.withNext(U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2), [track('x', { level: 'track' })])
    const otherAlbum = U.startUpNext(album(5, 'o'), 2)
    const otherSong = U.withNext(U.startUpNext(list, 2), [track('y')])
    const reordered = U.startUpNext([...list].reverse(), 2)
    const fresh = [put(noId, otherAlbum), put(noId, otherSong), put(noId, reordered), put(noId, null), put(noId, { tracks: [], index: -1 })]
    check('(2.1.15 review) no id saved, of the queue this page holds: its id kept; another album, another song under a key, the list reordered, or nothing held: a new one',
      [put(noId, holding) === holding.upNext.id, fresh.every((id) => /^[A-Za-z0-9_-]{1,64}$/.test(id) && ![holding.upNext.id, otherAlbum.upNext.id, otherSong.upNext.id, reordered.upNext.id].includes(id))],
      [true, true])
    check('...an id saved wins over the queue held, the same queue or not', [put(saved.snapshot, holding), put(saved.snapshot, otherAlbum)], [made.id, made.id])
    check('...sameQueue: the same queue a step on (one song further, one more added) still is', R.sameQueue(holding, U.withLast({ ...holding, index: 3 }, [track('z')])), true)
  }
  for (const [label, snapshot] of [['not JSON', '{nope'], ['v3', JSON.stringify({ ...JSON.parse(saved.snapshot), v: 3 })],
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
    check('Previous before where the album was started, as an app before 2.1.3 saved it (startedAt past the index): the account back, Playing Next still added - startedAt lowered to the song playing',
      [live.upNext.startedAt, back.queue.index, back.queue.upNext.startedAt, back.queue.upNext.marks.map((m) => m.from)],
      [4, 3, 3, ['source', 'source', 'source', 'source', 'source', 'added', 'source', 'source', 'source', 'source', 'source']])
    //? (2.1.3 review) ...so, played on here, the song it went back to is in History: on the iPhone's 0.2 (or the web's
    //? 2.1.2) an album started at 5, Previous to 4; picked up here, 4 ends, then 5 - at 6, History 4 and 5. Left past the
    //? index, startedAt kept 4 out of it for good
    let old = at(U.startUpNext(album(10), 4), 3)
    const oldSaving = R.toSave(old, 12)
    back = R.resumed({ index: oldSaving.index, position: 12, changed_by: 'deadwax', kept: kept({ ids: oldSaving.ids, index: oldSaving.index, position: 12, snapshot: oldSaving.snapshot }) },
      old.tracks.slice(oldSaving.start, oldSaving.start + oldSaving.ids.length).map(bare), 'off', 'phone-1')
    let on = back.queue
    on = at(on, U.onward(on)); on = at(on, U.onward(on))
    check('...played on after such a pick-up: the song gone back to, then 5, in History at 6', [old.upNext.startedAt, on.tracks[on.index].id, U.historyRows(on).map((row) => row.track.id)], [4, '6', ['4', '5']])
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
    //? (2.1.15) deadwax's own queue put back mid-song: the song playing on from there is the listen it was - its start was
    //? kept when it began - so the play history keeps none for it (player/historyOutbox.ts)
    {
      const H = require(path.join(OUT, 'player/historyOutbox.js'))
      const PH = require(path.join(OUT, 'lib/playHistory.js'))
      const queue = p.player.queue
      H.record(PH.startOf(queue.tracks[queue.index], Date.now(), queue))
      check('(2.1.15) put back at 95 s and played on: no start kept for the song carrying on', [H.ownStarts().length, H.pendingStarts().length], [0, 0])
      H.forgetStarts()
    }
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
