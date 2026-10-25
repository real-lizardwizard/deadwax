/**
 * Up Next, shuffle and repeat (2.0.0-player.57): lib/upNext.ts - Up Next's account of the queue, beside the
 * engine's `{ tracks, index }` - and the two components drawn from it, app/UpNext.tsx (the list) and
 * app/QueueMenu.tsx (a song's or an album's Play Next and Play Last), rendered by a small stand-in for Preact
 * as pins.sim.cjs renders Pinned's Edit.
 *
 * What it pins:
 *
 *  - startUpNext plays exactly what startQueue() would for the same random - tracks and index - and knows
 *    every entry's place in the list (a song in it twice included).
 *  - THE INVARIANT, by property: 2,000 seeded runs of every edit, top-up and forward move, each checked after
 *    every step - marks in step with tracks, keys unique, an edit never touching the song playing or anything
 *    before it, and after the song playing copies, then added songs, then the list's songs time round by
 *    time round.
 *  - Play Next and Play Last's places (after Repeat One's copies; Play Last after the songs added, still ahead
 *    of the list); a row out, moved within its group and refused across; Clear; a jump into the list (Playing
 *    Next kept, after it) and into Playing Next (only the songs added above it dropped).
 *  - Shuffle on: the song playing and everything before it untouched, the songs added kept in order, the
 *    list's songs not yet heard this round shuffled (an album started at song 5 and shuffled at 7: 1-4 and
 *    8-12), a song removed or jumped over not among them, entries queued keeping their keys; at a round's last
 *    song the next round shuffled; off: the list from the song playing's place, in order, less what was taken
 *    out.
 *  - Repeat: All appends whole times round until REPEAT_AHEAD follow (a fresh order with Shuffle on, never
 *    starting with the song that ended the round before - a two-song list included, over a thousand seeds),
 *    never copies a song added, gives a one-song list enough times round; One makes copies at the end of the
 *    copies, before the songs added; off and a queue already topped up are the same object; leaving One drops
 *    copies, leaving All the later times round.
 *  - Next passes Repeat One's copies; Previous passes back over the run of them; a failed song's skip passes
 *    them too.
 *  - The view: copies and later times round never drawn; the next round shown at a round's end ("…, again");
 *    the cap and "and N more"; what comes after, for each mode; the words.
 *  - (Part B) a library's shuffle: more appended at the end of its round by token, a fresh order as the next
 *    round, Shuffle and Repeat All leaving it to its feed, the count of what is still to come.
 *  - (review) Up Next's focus as Edit starts and after a row's tap; the grip's drag; the player bar's Shuffle,
 *    Repeat and Up Next buttons, rendered (Repeat cycling off -> all -> one -> off, Shuffle pressed and toggling,
 *    aria-disabled during a library's shuffle; Up Next opening the panel, pressed while it shows).
 *  - UpNext and QueueMenu: what each draws for a view, a row's tap jumping by its key and nothing else, Edit's
 *    rows (the ends' moves aria-disabled), focus after a move and after a removal as Pinned keeps it, the
 *    read-out words; the menu's rows remembering the albums and then playing next or last, the notice only
 *    when the music didn't start from it.
 *
 * Run it with:  node ui/test/upnext.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-upnext-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/upNext.ts', 'src/lib/playQueue.ts', 'src/app/UpNext.tsx', 'src/app/QueueMenu.tsx', 'src/player/PlayerBar.tsx', '--rootDir', 'src', '--outDir', OUT,
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
  return render
}
`)
//? what the components reach outside themselves: the sheet hook (its options kept), the album memory, the notice, a cover
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('app/useSheet.js', `exports.useSheet = (options) => { globalThis.__upnext.sheets.push(options) }\nexports.takeOpener = () => null\n`)
write('player/api.js', `exports.rememberAdded = (albums) => globalThis.__upnext.calls.push(['rememberAdded', albums.map((a) => a.id)])\n`)
write('app/usePins.js', `exports.sayPins = (text) => globalThis.__upnext.calls.push(['sayPins', text])\n`)
//? the player bar's neighbours it needs nothing of here: the scrubber and the speed chip
write('player/NowPlaying.js', `exports.Scrubber = function Scrubber() { return null }\n`)
write('player/SpeedChip.js', `exports.SpeedChip = function SpeedChip() { return null }\n`)
write('player/Cover.js', `exports.Cover = function Cover(props) { return { type: 'img', props: { class: props.class, 'data-cover': props.id } } }\n`)
const W = globalThis.__upnext = { sheets: [], calls: [] }

const U = require(path.join(OUT, 'lib/upNext.js'))
const Q = require(path.join(OUT, 'lib/playQueue.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/** A deterministic "random", as playqueue.sim.cjs's. */
function seeded(seed) {
  return () => {
    seed = (seed * 16807) % 2147483647
    return (seed - 1) / 2147483646
  }
}

const track = (id, fields = {}) => ({
  id, title: `song ${id}`, artist: 'Massive Attack', album: 'Mezzanine', albumId: 'mez', coverArt: null,
  duration: 200, contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2, ...fields,
})
const album = (n, prefix = '') => Array.from({ length: n }, (_, i) => track(`${prefix}${i + 1}`))
const ids = (queue) => queue.tracks.map((t) => t.id)
const after = (queue) => queue.tracks.slice(queue.index + 1).map((t) => t.id)
const froms = (queue) => queue.upNext.marks.slice(queue.index + 1).map((m) => m.from[0] + (m.from === 'source' ? m.pass : ''))
const at = (queue, index) => ({ ...queue, index })
const playing = (queue) => Q.current(queue)?.id ?? null
const keyOf = (queue, id, from = 'any') => {
  const place = queue.tracks.findIndex((t, i) => i > queue.index && t.id === id && (from === 'any' || queue.upNext.marks[i].from === from))
  return place < 0 ? null : queue.upNext.marks[place].key
}
//? the song after `queue` ends on its own: the next entry, copies included (onEnded's nextIndex)
const ended = (queue) => ({ ...queue, index: Math.min(queue.index + 1, queue.tracks.length - 1) })
const roomy = (queue) => queue.tracks.length - queue.index - 1

/* ===== startUpNext: exactly startQueue's queue ===== */

console.log('\nstartUpNext plays what startQueue would')
{
  const list = album(7)
  const cases = [[0, false], [3, false], [null, false], [3, true], [null, true], [0, true], [6, true]]
  const same = cases.map(([start, shuffle]) => {
    const a = Q.startQueue(list, start, shuffle, seeded(11))
    const b = U.startUpNext(list, start, shuffle, seeded(11))
    return JSON.stringify([ids(a), a.index]) === JSON.stringify([ids(b), b.index])
  })
  check('tracks and index the same for the same random - in order, from a song, shuffled from a song and from none', same, cases.map(() => true))
  check('no songs: the empty queue, a plain one', [U.startUpNext([], 0) === Q.EMPTY_QUEUE, 'upNext' in U.startUpNext([], 0)], [true, false])
  const one = U.startUpNext([track('x')], 0, true, seeded(3))
  check('one song, shuffled: that song', [ids(one), one.index], [['x'], 0])
  const shuffled = U.startUpNext(list, 2, true, seeded(5))
  check('every mark the list\'s, the first time round, knowing its place', shuffled.upNext.marks.every((m, i) => m.from === 'source' && m.pass === 0 && list[m.at].id === shuffled.tracks[i].id), true)
  check('...the keys 0 to n-1, the next one after; startedAt 0 when shuffled, the start when not',
    [shuffled.upNext.marks.map((m) => m.key).sort((a, b) => a - b).join(), shuffled.upNext.nextKey, shuffled.upNext.startedAt, U.startUpNext(list, 4).upNext.startedAt], ['0,1,2,3,4,5,6', 7, 0, 4])
  const twice = U.startUpNext([track('a'), track('b'), track('a')], 0, true, seeded(9))
  check('a list with the same song twice: each entry its own place', twice.upNext.marks.map((m) => m.at).sort().join(), '0,1,2')
  check('the source is the list in its own order, and Shuffle as asked', [shuffled.upNext.source.map((t) => t.id), shuffled.upNext.shuffle, U.startUpNext(list, 0).upNext.shuffle], [list.map((t) => t.id), true, false])
}

/* ===== the invariant, by property ===== */

console.log('\nthe invariant: 2,000 random runs of every edit, top-up and forward move')
{
  const problems = []
  const note = (run, step, what) => { if (problems.length < 8) problems.push(`run ${run} step ${step}: ${what}`) }
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
    return null
  }
  for (let run = 0; run < 2000; run++) {
    const random = seeded(run + 1)
    const pick = (n) => Math.floor(random() * n)
    const size = 1 + pick(6)
    let repeat = U.REPEATS[pick(3)]
    let queue = U.toppedUp(U.startUpNext(album(size), random() < 0.3 ? null : pick(size), random() < 0.5, random), repeat, random)
    let extra = 0
    for (let step = 0; step < 30; step++) {
      const before = queue
      const op = pick(12)
      let edit = true
      const rowKeys = () => queue.upNext.marks.slice(queue.index + 1).map((m) => m.key)
      const someKey = () => { const keys = rowKeys(); return keys.length && random() < 0.85 ? keys[pick(keys.length)] : pick(queue.upNext.nextKey + 2) }
      if (op === 0) queue = U.withNext(queue, Array.from({ length: 1 + pick(2) }, () => track(`n${extra++}`)))
      else if (op === 1) queue = U.withLast(queue, Array.from({ length: 1 + pick(2) }, () => track(`l${extra++}`)))
      else if (op === 2) queue = U.withoutKey(queue, someKey())
      else if (op === 3) queue = U.movedKey(queue, someKey(), pick(6))
      else if (op === 4) queue = U.withoutAdded(queue)
      else if (op === 5) queue = U.withShuffle(queue, random() < 0.5, random)
      else if (op === 6) { repeat = U.REPEATS[pick(3)]; queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, random) }
      else if (op === 7) queue = U.toppedUp(queue, repeat, random)
      else {
        edit = false
        if (op === 8) {
          const jumped = U.jumpedTo(queue, someKey())
          if (jumped) {
            const same = jumped.tracks.slice(0, queue.index + 1).every((t, i) => t === queue.tracks[i]) && jumped.index === queue.index
            if (!same) note(run, step, 'a jump touched the song playing or before it')
            const next = U.onward(jumped)
            if (next === null) note(run, step, 'a jump with nothing to move onto')
            else queue = at(jumped, next)
          }
        } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = at(queue, next) }
        else queue = ended(queue)
        queue = U.toppedUp(queue, repeat, random)
      }
      const { marks } = queue.upNext
      if (marks.length !== queue.tracks.length) note(run, step, `marks ${marks.length} for ${queue.tracks.length} songs`)
      if (new Set(marks.map((m) => m.key)).size !== marks.length) note(run, step, 'a key twice')
      if (marks.some((m) => m.key >= queue.upNext.nextKey)) note(run, step, 'a key past nextKey')
      if (edit) {
        if (queue.index !== before.index) note(run, step, `op ${op} moved the index`)
        for (let i = 0; i <= before.index; i++) {
          if (queue.tracks[i] !== before.tracks[i] || marks[i] !== before.upNext.marks[i]) { note(run, step, `op ${op} changed entry ${i} of the played`); break }
        }
      }
      const wrong = shape(queue)
      if (wrong) note(run, step, `op ${op}: ${wrong}`)
      marks.forEach((m, i) => {
        if (m.from === 'source' && m.at < 0) note(run, step, `entry ${i} of the list has no place in it`)
        //? a copy of a song added has no place in the list (-1); any other knows its own
        if (m.at >= 0 && queue.upNext.source[m.at]?.id !== queue.tracks[i].id) note(run, step, `entry ${i} is not its place in the list`)
      })
    }
  }
  check('every step of every run keeps it', problems, [])
}

/* ===== Play Next and Play Last ===== */

console.log('\nPlay Next and Play Last: where they go')
{
  const start = U.startUpNext(album(4), 0)
  const next = U.withNext(start, [track('n')])
  check('Play Next with nothing added: straight after the song playing', after(next), ['n', '2', '3', '4'])
  const both = U.withLast(U.withNext(next, [track('m')]), [track('z')])
  check('...Play Next again goes first; Play Last after the songs added, still ahead of the list', after(both), ['m', 'n', 'z', '2', '3', '4'])
  check('...the songs added are marked so, outside the list', froms(both), ['a', 'a', 'a', 's0', 's0', 's0'])
  const one = U.toppedUp(start, 'one')
  check('Repeat One\'s copies stay next to the song: Play Next goes after them, Play Last too', [after(U.withNext(one, [track('n')])), after(U.withLast(one, [track('z')]))], [['1', '1', 'n', '2', '3', '4'], ['1', '1', 'z', '2', '3', '4']])
  check('several songs, in their order', after(U.withNext(start, [track('a'), track('b')])), ['a', 'b', '2', '3', '4'])
  check('nothing to add, or nothing playing: the same object', [U.withNext(start, []) === start, U.withLast(Q.EMPTY_QUEUE, [track('a')]) === Q.EMPTY_QUEUE], [true, true])
}

console.log('\na row out, a row moved, Clear')
{
  const start = U.withLast(U.startUpNext(album(4), 0), [track('a'), track('b')])
  check('a song added, out', after(U.withoutKey(start, keyOf(start, 'a'))), ['b', '2', '3', '4'])
  const gone = U.withoutKey(start, keyOf(start, '3'))
  check('one of the list\'s, out - and noted as taken out of its round', [after(gone), gone.upNext.left], [['a', 'b', '2', '4'], [{ pass: 0, at: 2 }]])
  const later = at(start, 2)
  check('the song playing, one before it, a key it doesn\'t have: the same object',
    [U.withoutKey(start, start.upNext.marks[0].key) === start, U.withoutKey(later, start.upNext.marks[1].key) === later, U.withoutKey(start, 999) === start], [true, true, true])
  check('a move within Playing Next', after(U.movedKey(start, keyOf(start, 'b'), 0)), ['b', 'a', '2', '3', '4'])
  check('a move within the list', after(U.movedKey(start, keyOf(start, '2'), 2)), ['a', 'b', '3', '4', '2'])
  check('...past its end held to it, and to where it is: the same object', [after(U.movedKey(start, keyOf(start, '2'), 9)), U.movedKey(start, keyOf(start, '3'), 1) === start], [['a', 'b', '3', '4', '2'], true])
  const one = U.toppedUp(start, 'one')
  check('a copy can\'t be moved or taken out', [U.movedKey(one, one.upNext.marks[1].key, 3) === one, U.withoutKey(one, one.upNext.marks[1].key) === one], [true, true])
  check('Clear: every song added out, the list as it was', after(U.withoutAdded(start)), ['2', '3', '4'])
  const cleared = U.withoutAdded(start)
  check('...with none added, the same object', U.withoutAdded(cleared) === cleared, true)
}

console.log('\na row\'s tap: jumped to')
{
  const start = U.withLast(U.startUpNext(album(5), 0), [track('a'), track('b')])
  const toList = U.jumpedTo(start, keyOf(start, '4'))
  const moved = at(toList, U.onward(toList))
  check('into the list: it plays next, Playing Next kept after it, the songs jumped over gone', [playing(moved), after(moved)], ['4', ['a', 'b', '5']])
  check('...and noted as taken out of the round', toList.upNext.left, [{ pass: 0, at: 1 }, { pass: 0, at: 2 }])
  const toAdded = U.jumpedTo(start, keyOf(start, 'b'))
  const there = at(toAdded, U.onward(toAdded))
  check('into Playing Next: only the songs added above it dropped', [playing(there), after(there)], ['b', ['2', '3', '4', '5']])
  check('the song playing, a copy, a key it doesn\'t have: null', [U.jumpedTo(start, start.upNext.marks[0].key), U.jumpedTo(U.toppedUp(start, 'one'), U.toppedUp(start, 'one').upNext.marks[1].key), U.jumpedTo(start, 77)], [null, null, null])
  const one = U.toppedUp(U.startUpNext(album(3), 0), 'one')
  const jumped = U.jumpedTo(one, keyOf(one, '3'))
  check('with Repeat One on: the row after the copies, and Next lands on it', playing(at(jumped, U.onward(jumped))), '3')
}

/* ===== Shuffle on and off ===== */

console.log('\nShuffle on: the songs not yet heard this round')
{
  const start = U.startUpNext(album(12), 4)
  let queue = at(start, 6)
  queue = U.withShuffle(queue, true, seeded(4))
  check('the song playing and everything before it untouched', [ids(queue).slice(0, 7), queue.index], [['1', '2', '3', '4', '5', '6', '7'], 6])
  check('an album started at song 5, shuffled at song 7: songs 1-4 and 8-12, in a new order', after(queue).slice().sort((a, b) => a - b), ['1', '2', '3', '4', '8', '9', '10', '11', '12'])
  check('...not in their own order', after(queue).join() !== '1,2,3,4,8,9,10,11,12', true)
  const keys = new Map(start.upNext.marks.slice(7).map((m) => [m.at, m.key]))
  check('...the songs queued already keep their keys', queue.upNext.marks.slice(7).filter((m) => keys.has(m.at)).every((m) => keys.get(m.at) === m.key), true)
  check('...Shuffle said on', queue.upNext.shuffle, true)
  const added = U.withNext(U.withLast(at(start, 6), [track('a')]), [track('b')])
  const kept = U.withShuffle(added, true, seeded(2))
  check('the songs added keep their order, ahead of the list', after(kept).slice(0, 2), ['b', 'a'])
  const removed = U.withShuffle(U.withoutKey(at(start, 6), keyOf(start, '9')), true, seeded(3))
  check('a song taken out of the round isn\'t brought back', after(removed).includes('9'), false)
  const jumped = U.jumpedTo(at(start, 6), keyOf(start, '10'))
  const overJumped = U.withShuffle(at(jumped, U.onward(jumped)), true, seeded(3))
  check('...nor songs jumped over (8 and 9)', [playing(overJumped), after(overJumped).includes('8'), after(overJumped).includes('9')], ['10', false, false])
  const all = U.toppedUp(at(U.startUpNext(album(3), 0), 0), 'all')
  const lastSong = U.toppedUp(at(all, 2), 'all')
  const shuffledEnd = U.toppedUp(U.withShuffle(lastSong, true, seeded(8)), 'all', seeded(8))
  check('at a round\'s last song: the next round is the shuffled one', [froms(shuffledEnd).every((f) => f === 's1'), after(shuffledEnd).slice().sort().join()], [true, '1,2,3'])
  check('later times round go (toppedUp grows them again)', U.withShuffle(all, true, seeded(1)).upNext.marks.some((m) => m.pass > 0), false)
  check('Shuffle already as asked, or a plain queue: the same object', [U.withShuffle(start, false) === start, U.withShuffle(Q.EMPTY_QUEUE, true) === Q.EMPTY_QUEUE], [true, true])
}

console.log('\nShuffle off: the list\'s own order from the song playing\'s place')
{
  const shuffled = U.startUpNext(album(8), null, true, seeded(6))
  const now = at(shuffled, 2)
  const place = now.upNext.marks[2].at
  const off = U.withShuffle(now, false)
  const expected = album(8).map((t) => t.id).slice(place + 1)
  check('the songs after its place in the list, in order, as new entries', [after(off), off.upNext.marks.slice(3).every((m) => m.key >= shuffled.upNext.nextKey)], [expected, true])
  const lessLeft = U.withShuffle(U.withoutKey(now, keyOf(now, expected[0] ?? 'none') ?? -1), false)
  check('...less those taken out this round', expected.length ? after(lessLeft).includes(expected[0]) : false, false)
  const withAdded = U.withShuffle(U.withNext(now, [track('a')]), false)
  check('the songs added stay first', after(withAdded)[0], 'a')
  const onAdded = at(U.withNext(now, [track('a')]), 3)
  const fromAdded = U.withShuffle(onAdded, false)
  check('a song added playing: from the list\'s song before it', after(fromAdded), expected)
  check('Shuffle said off', off.upNext.shuffle, false)
}

/* ===== Repeat ===== */

console.log('\nRepeat All: the list again, ahead of where anything looks')
{
  const start = U.startUpNext(album(3), 0)
  check('two songs follow already: nothing appended', U.toppedUp(start, 'all') === start, true)
  const late = U.toppedUp(at(start, 1), 'all')
  check('one song follows: one whole time round more, in its own order', [after(late), froms(late)], [['3', '1', '2', '3'], ['s0', 's1', 's1', 's1']])
  check('...topped up already: the same object', U.toppedUp(late, 'all') === late, true)
  const single = U.toppedUp(U.startUpNext([track('x')], 0), 'all')
  check('a one-song list gets enough times round', [after(single), froms(single)], [['x', 'x'], ['s1', 's2']])
  const added = U.toppedUp(U.withNext(at(start, 2), [track('a')]), 'all')
  check('a song added is never copied into the next round', [after(added), added.tracks.filter((t) => t.id === 'a').length], [['a', '1', '2', '3'], 1])
  const shuffledRounds = U.toppedUp(at(U.startUpNext(album(6), 0, true, seeded(3)), 5), 'all', seeded(9))
  check('with Shuffle on: a fresh order of the whole list', after(shuffledRounds).slice().sort().join(), '1,2,3,4,5,6')
  let starts = 0
  for (let seed = 1; seed <= 1000; seed++) {
    for (const size of [2, 4]) {
      const list = U.startUpNext(album(size), 0, true, seeded(seed))
      const end = U.toppedUp(at(list, size - 1), 'all', seeded(seed * 7))
      if (end.tracks[size].id === end.tracks[size - 1].id) starts++
    }
  }
  check('...never starting with the song that ended the round before (a two-song list included, 1,000 seeds)', starts, 0)
  const last = at(start, 2)
  check('Repeat off: the same object', U.toppedUp(last, 'off') === last, true)
}

console.log('\nRepeat One: copies of the song, straight after it')
{
  const start = U.withLast(U.startUpNext(album(3), 0), [track('a')])
  const one = U.toppedUp(start, 'one')
  check('copies up to REPEAT_AHEAD, at the end of the copies, before the songs added', [after(one), froms(one)], [['1', '1', 'a', '2', '3'], ['o', 'o', 'a', 's0', 's0']])
  check('...the same song, knowing the original\'s place', [one.tracks[1] === one.tracks[0], one.upNext.marks[1].at, one.upNext.marks[1].pass], [true, 0, 0])
  const moved = U.toppedUp(ended(one), 'one')
  check('a copy playing: one more made at the end of the copies', [after(moved), U.toppedUp(moved, 'one') === moved], [['1', '1', 'a', '2', '3'], true])
}

console.log('\nRepeat changed: what goes')
{
  const one = U.toppedUp(U.startUpNext(album(3), 0), 'one')
  check('one -> off: the copies go', after(U.withRepeat(one, 'off')), ['2', '3'])
  const all = U.toppedUp(at(U.startUpNext(album(3), 0), 1), 'all')
  check('all -> off: the later times round go, this one stays', after(U.withRepeat(all, 'off')), ['3'])
  check('...at a round\'s last song too: nothing after it', after(U.withRepeat(U.toppedUp(at(all, 2), 'all'), 'off')), [])
  check('one -> all: the copies go, the next round comes', after(U.toppedUp(U.withRepeat(U.toppedUp(at(U.startUpNext(album(3), 0), 1), 'one'), 'all'), 'all')), ['3', '1', '2', '3'])
  check('all -> one: the later rounds go, the copies come', after(U.toppedUp(U.withRepeat(all, 'one'), 'one')), ['2', '2', '3'])
  const plain = U.startUpNext(album(3), 0)
  check('nothing to drop: the same object', [U.withRepeat(plain, 'off') === plain, U.withRepeat(all, 'all') === all], [true, true])
}

/* ===== Next, Previous, a failure's skip ===== */

console.log('\nNext, Previous and a failure\'s skip pass Repeat One\'s copies')
{
  const one = U.toppedUp(at(U.startUpNext(album(3), 0), 1), 'one')
  check('Next: past the copies to the next song', U.onward(one), 4)
  check('...only copies after it: none', U.onward(U.toppedUp(at(U.startUpNext(album(2), 0), 1), 'one')), null)
  check('a plain queue: nextIndex', [U.onward(at({ tracks: album(3), index: 0 }, 1)), U.onward(at({ tracks: album(3), index: 0 }, 2))], [2, null])
  const onCopy = ended(one)
  check('Previous past 3 s: the song again', U.backward(onCopy, 10), { kind: 'restart' })
  check('...early: the entry before the run of copies and its original', U.backward(onCopy, 1), { kind: 'go', index: 0 })
  check('...the first song\'s copy early: the song again', U.backward(ended(U.toppedUp(U.startUpNext(album(2), 0), 'one')), 1), { kind: 'restart' })
  check('...no copies: previousAction\'s rule', [U.backward(at(U.startUpNext(album(3), 0), 2), 1), U.backward(U.startUpNext(album(3), 0), 1)], [{ kind: 'go', index: 1 }, { kind: 'restart' }])
  check('a failure\'s skip: past the copies; none after them: null', [U.pastCopies(one, 2), U.pastCopies(U.toppedUp(at(U.startUpNext(album(2), 0), 1), 'one'), 2)], [4, null])
  check('...a plain queue: the index itself, or null past the end', [U.pastCopies({ tracks: album(3), index: 0 }, 2), U.pastCopies({ tracks: album(3), index: 0 }, 3)], [2, null])
}

/* ===== the view ===== */

console.log('\nwhat Up Next draws')
{
  const start = U.startUpNext(album(4), 0)
  const view = U.upNextView(start, 'off')
  check('the song playing, no Playing Next, the album\'s rest', [view.playing.id, view.added, view.list.title, view.list.rows.map((r) => r.track.id), view.list.more, view.then], ['1', [], 'From Mezzanine', ['2', '3', '4'], 0, null])
  const full = U.toppedUp(U.toppedUp(U.withNext(start, [track('a', { album: 'Dummy', albumId: 'dum' })]), 'one'), 'one')
  const drawn = U.upNextView(full, 'one')
  check('copies never drawn; Playing Next its own group; Repeat One said', [drawn.added.map((r) => r.track.id), drawn.list.rows.map((r) => r.track.id), drawn.repeatOne], [['a'], ['2', '3', '4'], true])
  const rounds = U.toppedUp(at(start, 3), 'all')
  const end = U.upNextView(rounds, 'all')
  check('at a round\'s end the next round, "again"; and what comes after', [end.list.title, end.list.rows.map((r) => r.track.id), end.then], ['From Mezzanine, again', ['1', '2', '3', '4'], 'Then Mezzanine again from the top.'])
  const mid = U.upNextView(U.toppedUp(at(start, 2), 'all'), 'all')
  check('...mid-round, the later round never drawn', mid.list.rows.map((r) => r.track.id), ['4'])
  check('Shuffle on with Repeat All: a new order next time', U.upNextView(U.toppedUp(U.startUpNext(album(4), null, true, seeded(1)), 'all'), 'all').then, 'Then Mezzanine again, in a new order.')
  check('Repeat off, the last song: nothing after it', U.upNextView(at(start, 3), 'off').then, 'Nothing after this song.')
  const long = U.startUpNext(album(130), 0)
  const capped = U.upNextView(long, 'off')
  check('the cap: the first 100 drawn, the rest counted', [capped.list.rows.length, capped.list.more], [100, 29])
  check('...a smaller limit', U.upNextView(long, 'off', 5).list.more, 124)
  const mixed = U.startUpNext([track('1'), track('2', { albumId: 'dum', album: 'Dummy' })], 0)
  check('several albums: "Still to play", and "the list" again', [U.upNextView(mixed, 'off').list.title, U.upNextView(U.toppedUp(at(mixed, 1), 'all'), 'all').then], ['Still to play', 'Then the list again from the top.'])
  check('nothing playing: nothing drawn', U.upNextView(Q.EMPTY_QUEUE, 'all'), { playing: null, added: [], list: null, then: null, repeatOne: false })
  check('listTitle', [U.listTitle(album(2), false), U.listTitle(album(2), true), U.listTitle([track('1'), track('2', { albumId: 'x' })], true), U.listTitle([track('1', { albumId: null })], false)],
    ['From Mezzanine', 'From Mezzanine, again', 'Still to play, again', 'Still to play'])
  check('queuedWords', [U.queuedWords('next', 'Roads'), U.queuedWords('last', 'Dummy')], ['Playing next: Roads', 'Added to Up Next: Dummy'])
  check('repeatLabel, and the cycle', [U.REPEATS.map(U.repeatLabel), U.REPEATS.map(U.nextRepeat)], [['Repeat', 'Repeat all', 'Repeat one'], ['all', 'one', 'off']])
  //? (2.0.7) "Up Next", as the sheet and the player bar say it - it was "Up next" here
  //? (2.0.14) the icon-alone Shuffle's name - the player bar's and Now Playing's - in Up Next's words
  check('the Shuffle button\'s name: plain, or during a whole library\'s shuffle named for why',
    [U.shuffleLabel(undefined), U.shuffleLabel('store'), U.shuffleLabel('yours')], ['Shuffle', 'Shuffle - shuffling all music', 'Shuffle - shuffling your whole library'])
  check('the Up Next button\'s name', [U.upNextLabel(false, 'off'), U.upNextLabel(true, 'off'), U.upNextLabel(false, 'all'), U.upNextLabel(false, 'one'), U.upNextLabel(true, 'all')],
    ['Up Next', 'Up Next - Shuffle on', 'Up Next - Repeat all', 'Up Next - Repeat one', 'Up Next - Shuffle and Repeat all'])
}

/* ===== Part B: a library's shuffle, a page at a time ===== */

console.log('\n(Part B) a library\'s shuffle, fed a page at a time')
{
  const paged = { token: 't1', total: 450, fetched: 3, scope: 'store' }
  const first = U.startUpNext(album(3, 'p'), 0, false, Math.random, paged)
  check('the first page: its order is the shuffle - Shuffle reads on', [first.upNext.shuffle, first.upNext.paged.token], [true, 't1'])
  const more = U.withMore(first, 't1', album(2, 'q'))
  check('more of it: at the end, the same round, counted', [after(more), froms(more), more.upNext.paged.fetched], [['p2', 'p3', 'q1', 'q2'], ['s0', 's0', 's0', 's0'], 5])
  check('...another token\'s page: the same object', U.withMore(first, 't0', album(2, 'q')) === first, true)
  const whole = { ...first, upNext: { ...first.upNext, paged: { ...paged, fetched: 450 } } }
  const fresh = U.withMore(whole, 't1', album(2, 'r'), { token: 't2', total: 450, fetched: 0, scope: 'store' })
  check('a fresh order once all of it is in: the next round, the shuffle from then on', [froms(fresh).slice(-2), fresh.upNext.paged], [['s1', 's1'], { token: 't2', total: 450, fetched: 2, scope: 'store' }])
  check('...a fresh order with no songs (a library emptied): the same object - nothing for its feed to ask again on',
    [U.withMore(whole, 't1', [], { token: 't9', total: 0, fetched: 0, scope: 'store' }) === whole, U.withMore(first, 't1', []) === first], [true, true])
  const off = U.withRepeat(at(fresh, 2), 'off')
  check('...Repeat off with the next round queued: that round let go, the shuffle back on the order of the round playing',
    [after(off), off.upNext.paged, off.upNext.pagedRounds], [[], { ...paged, fetched: 450 }, []])
  const atLast = at(fresh, 2)
  check('...Repeat One the same; All keeps the round (the same object)', [U.withRepeat(atLast, 'one').upNext.paged.token, U.withRepeat(atLast, 'all') === atLast], ['t1', true])
  const restarted = U.withMore(first, 't1', album(2, 'r'), { token: 't3', total: 450, fetched: 0, scope: 'store' })
  check('a fresh order for one that went mid-round (deadwax restarted): the rest of this round', [froms(restarted).slice(-2), restarted.upNext.paged.token], [['s0', 's0'], 't3'])
  const atEnd = at(first, 2)
  check('Repeat All leaves it to its feed; Shuffle leaves it as it is', [U.toppedUp(atEnd, 'all') === atEnd, U.withShuffle(first, false) === first], [true, true])
  check('...Repeat One as ever', after(U.toppedUp(first, 'one')).slice(0, 2), ['p1', 'p1'])
  const view = U.upNextView(first, 'off')
  check('Up Next counts what is still to come, and names it', [view.list.title, view.list.more, U.upNextView({ ...first, upNext: { ...first.upNext, paged: { ...paged, scope: 'yours' } } }, 'all').then],
    ['All music, shuffled', 447, 'Then your library again, in a new order.'])
  //? (2.0.5 review) the collection's round named as its heading names it - "all music", never "everything"
  check('...and of all music, Repeat All: then all music again', U.upNextView(first, 'all').then, 'Then all music again, in a new order.')
}

/* ===== the components: Up Next and the song menu ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { UpNext, REPEATING_ONE, SHUFFLING_LIBRARY } = require(path.join(OUT, 'app/UpNext.js'))
const { QueueMenu } = require(path.join(OUT, 'app/QueueMenu.js'))

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
const status = (tree) => words(find((node) => node.props?.role === 'status', tree))

/** A player for Up Next: its queue and modes, every call it is asked kept - and its edits made, as the engine's are. */
function upNextPlayer(queue, repeat = 'off') {
  const player = {
    queue, repeat, track: Q.current(queue), playing: true, shuffle: queue.upNext?.shuffle ?? false, calls: [],
    setShuffle(on) { player.calls.push(['setShuffle', on]); player.queue = U.toppedUp(U.withShuffle(player.queue, on, seeded(1)), player.repeat); player.shuffle = on },
    setRepeat(mode) { player.calls.push(['setRepeat', mode]); player.queue = U.toppedUp(U.withRepeat(player.queue, mode), mode); player.repeat = mode },
    jumpTo(key) { player.calls.push(['jumpTo', key]) },
    moveInQueue(key, to) { player.calls.push(['moveInQueue', key, to]); player.queue = U.movedKey(player.queue, key, to) },
    removeFromQueue(key) { player.calls.push(['removeFromQueue', key]); player.queue = U.withoutKey(player.queue, key) },
    clearPlayingNext() { player.calls.push(['clearPlayingNext']); player.queue = U.withoutAdded(player.queue) },
  }
  return player
}
function mountUpNext(player, props = {}) {
  const render = hooks.root(UpNext)
  let tree = null
  const all = () => ({ open: true, opener: { current: null }, onClose: () => W.calls.push(['close']), player: { ...player }, ...props })
  //? drawn and its effects run, as Preact does after each render - but a draw that asks focus somewhere is committed by the
  //? check, once the fakes its effect reaches are in place (focusables)
  const draw = (commit = true) => { tree = render(all()); if (commit) render.commit(); return tree }
  return {
    draw,
    get tree() { return tree },
    commit: () => render.commit(),
    //? the scroller's rows, Done and the Shuffle chip as focusable fakes - what the layout effect reaches by its refs
    focusables(focused) {
      const rows = find((node) => node.props?.['data-key'] !== undefined && node.type === 'li', tree)
      const fakeRow = (row) => ({
        dataset: { key: String(row.props['data-key']) },
        querySelector: (selector) => {
          if (/app-result/.test(selector)) {
            const button = find(byClass('app-result'), row)[0]
            return button ? { focus: () => focused.push(`play:${row.props['data-key']}`) } : null
          }
          const which = /app-pin-(up|down|remove)/.exec(selector)[1]
          const button = find(byClass(`app-pin-${which}`), row)[0]
          if (!button || (/aria-disabled/.test(selector) && button.props['aria-disabled'])) return null
          return { focus: () => focused.push(`${which}:${row.props['data-key']}`) }
        },
      })
      find(byClass('app-info-scroll'), tree)[0].props.ref.current = { querySelectorAll: () => rows.map(fakeRow), scrollTop: 0 }
      find(byClass('app-info-done'), tree)[0].props.ref.current = { focus: () => focused.push('done') }
      const chip = find(byClass('app-upnext-shuffle'), tree)[0]
      if (chip) chip.props.ref.current = { focus: () => focused.push('shuffle') }
    },
  }
}

console.log('\nUp Next drawn: the song playing, Shuffle and Repeat, Playing Next, the list, what comes after')
{
  W.sheets.length = 0
  const queue = U.toppedUp(U.withNext(U.startUpNext(album(4), 0), [track('a', { title: 'Roads', artist: 'Portishead', album: 'Dummy', albumId: 'dum' })]), 'all')
  const view = mountUpNext(upNextPlayer(queue, 'all'))
  const tree = view.draw()
  check('the song playing in Info\'s card: its title, "artist · album"', [words(find(byClass('app-info-name'), tree)), words(find(byClass('app-info-line'), tree))], ['song 1', 'Massive Attack · Mezzanine'])
  const chips = find(byClass('app-chip'), tree)
  check('Shuffle and Repeat: the chips\' words, pressed and tinted as they are', chips.map((chip) => [words(chip), chip.props['aria-pressed'], byClass('is-on')(chip)]), [['Shuffle', false, false], ['Repeat all', true, true]])
  check('Playing Next with Clear, the song added in it', [words(find(byClass('app-section-title'), tree)), words(find(byClass('app-upnext-clear'), tree)), find(byClass('app-upnext-group'), tree)[0] && words(find(byClass('app-result-title'), find(byClass('app-upnext-group'), tree)[0]))],
    ['Playing NextFrom Mezzanine', 'Clear', 'Roads'])
  check('the list\'s rows, each "play now"; the later round and the copies never drawn; then what comes after',
    [find(byClass('app-result'), tree).map((row) => row.props['aria-label']), words(find(byClass('app-upnext-then'), tree))],
    [['Roads, play now', 'song 2, play now', 'song 3, play now', 'song 4, play now'], 'Then Mezzanine again from the top.'])
  check('a sheet by the one hook: its own lock, Done first, modal as a sheet', [W.sheets[0].lockClass, W.sheets[0].first === find(byClass('app-info-done'), tree)[0].props.ref, W.sheets[0].modal], ['app-upnext-open', true, true])
  const none = mountUpNext(upNextPlayer(U.startUpNext(album(3), 0))).draw()
  check('nothing added: no Playing Next, no Clear', [find(byClass('app-upnext-clear'), none).length, words(find(byClass('app-section-title'), none))], [0, 'From Mezzanine'])
  const long = mountUpNext(upNextPlayer(U.startUpNext(album(130), 0))).draw()
  check('a long list: the first 100 drawn, "And 29 more songs."', [find(byClass('app-result'), long).length, words(find(byClass('app-store-line'), long))], [100, 'And 29 more songs.'])
  const one = mountUpNext(upNextPlayer(U.toppedUp(U.startUpNext(album(2), 0), 'one'), 'one')).draw()
  check('Repeat One: said under the song, the copies not drawn', [words(find(byClass('app-store-line'), one)), find(byClass('app-result'), one).length, words(find(byClass('app-upnext-repeat'), one))], [REPEATING_ONE, 1, 'Repeat one'])
  const last = mountUpNext(upNextPlayer(at(U.startUpNext(album(2), 0), 1))).draw()
  check('Repeat off, the last song: "Nothing after this song."', words(find(byClass('app-upnext-then'), last)), 'Nothing after this song.')
  const paged = mountUpNext(upNextPlayer(U.startUpNext(album(3), 0, false, Math.random, { token: 't', total: 4000, fetched: 3, scope: 'yours' }))).draw()
  check('a whole library\'s shuffle: Shuffle on and aria-disabled, said so, the real count to come',
    [find(byClass('app-upnext-shuffle'), paged)[0].props['aria-disabled'], words(find(byClass('app-store-line'), paged)), words(find(byClass('app-section-title'), paged))],
    [true, `${SHUFFLING_LIBRARY}And 3,997 more songs.`, 'Your library, shuffled'])
  check('nothing playing: no card, no chips', [find(byClass('app-info-card'), mountUpNext(upNextPlayer(Q.EMPTY_QUEUE)).draw()).length], [0])
}

console.log('\nUp Next\'s taps: a row plays now, the chips change the modes, said aloud')
{
  const player = upNextPlayer(U.withNext(U.startUpNext(album(4), 0), [track('a')]))
  const view = mountUpNext(player)
  let tree = view.draw()
  const third = find(byClass('app-result'), tree)[2]
  third.props.onClick()
  check('a row\'s tap: jumpTo with its own key, and nothing else', player.calls, [['jumpTo', player.queue.upNext.marks[3].key]])
  player.calls.length = 0
  find(byClass('app-upnext-shuffle'), tree)[0].props.onClick()
  tree = view.draw()
  check('the Shuffle chip: Shuffle on, read out', [player.calls, status(tree)], [[['setShuffle', true]], 'Shuffle on'])
  player.calls.length = 0
  find(byClass('app-upnext-repeat'), tree)[0].props.onClick()
  tree = view.draw()
  check('the Repeat chip: off, then all - read out', [player.calls, status(tree)], [[['setRepeat', 'all']], 'Repeat all'])
  const paged = upNextPlayer(U.startUpNext(album(3), 0, false, Math.random, { token: 't', total: 9, fetched: 3, scope: 'store' }))
  const pagedView = mountUpNext(paged)
  find(byClass('app-upnext-shuffle'), pagedView.draw())[0].props.onClick()
  check('...a library\'s shuffle\'s chip does nothing', paged.calls, [])
}

console.log('\nUp Next\'s Edit: moves within a group, removals, Clear - focus kept as Pinned keeps it')
{
  const player = upNextPlayer(U.withLast(U.startUpNext(album(4), 0), [track('a'), track('b')]))
  const view = mountUpNext(player)
  let tree = view.draw()
  find(byClass('app-upnext-edit'), tree)[0].props.onClick()
  tree = view.draw()
  const rows = find(byClass('app-pin-row'), tree)
  check('Edit: each group\'s rows to move and remove, a grip each; one Done (Edit gone)', [rows.length, find(byClass('app-pin-grip'), tree).length, find(byClass('app-upnext-edit'), tree).length, words(find(byClass('app-info-done'), tree))], [5, 5, 0, 'Done'])
  check('...the ends\' moves aria-disabled, group by group', [find(byClass('app-pin-up'), tree).map((b) => b.props['aria-disabled']), find(byClass('app-pin-down'), tree).map((b) => b.props['aria-disabled'])],
    [[true, false, true, false, false], [false, true, false, false, true]])
  check('...named for their song', find(byClass('app-pin-move'), rows[2]).map((b) => b.props['aria-label']), ['Move song 2 up', 'Move song 2 down', 'Remove song 2'])
  const focused = []
  const song2 = rows[2].props['data-key']
  find(byClass('app-pin-down'), rows[2])[0].props.onClick()
  tree = view.draw(false)
  view.focusables(focused)
  view.commit()
  check('a move down: moveInQueue to its new place in its group, read out, focus on its button where the row went',
    [player.calls.slice(-1)[0], status(tree), focused], [['moveInQueue', song2, 1], 'song 2: 2 of 3', [`down:${song2}`]])
  focused.length = 0
  const listRows = find(byClass('app-pin-row'), tree).slice(2)
  const lastKey = listRows[2].props['data-key']
  find(byClass('app-pin-remove'), listRows[2])[0].props.onClick()
  tree = view.draw(false)
  view.focusables(focused)
  view.commit()
  check('a removal at the end: removeFromQueue, read out, focus on the row before\'s Remove', [player.calls.slice(-1)[0], status(tree), focused], [['removeFromQueue', lastKey], 'song 4 removed', [`remove:${listRows[1].props['data-key']}`]])
  focused.length = 0
  find(byClass('app-upnext-clear'), tree)[0].props.onClick()
  tree = view.draw(false)
  view.focusables(focused)
  view.commit()
  check('Clear: every song added out, focus to the Shuffle chip, read out', [player.calls.slice(-1)[0], focused, status(tree)], [['clearPlayingNext'], ['shuffle'], 'Playing Next cleared'])
  const lone = upNextPlayer(U.startUpNext(album(2), 0))
  const loneView = mountUpNext(lone)
  find(byClass('app-upnext-edit'), loneView.draw())[0].props.onClick()
  tree = loneView.draw()
  focused.length = 0
  find(byClass('app-pin-remove'), tree)[0].props.onClick()
  tree = loneView.draw(false)
  loneView.focusables(focused)
  loneView.commit()
  check('...the last row out: focus to Done', focused, ['done'])
  find(byClass('app-info-done'), tree)[0].props.onClick()
  tree = loneView.draw()
  check('Done in Edit ends Edit, closing nothing', [find(byClass('app-pin-row'), tree).length, W.calls.filter(([what]) => what === 'close').length], [0, 0])
}

console.log('\nUp Next\'s focus never left on nothing, and the grip\'s drag (2.0.0-player.57 review)')
{
  //? the engine's jump, as usePlayer's jumpTo does it: jumpedTo, then Next onto it
  const jumping = (queue) => {
    const player = upNextPlayer(queue)
    player.jumpTo = (key) => {
      player.calls.push(['jumpTo', key])
      const edited = U.jumpedTo(player.queue, key)
      if (edited) player.queue = { ...edited, index: U.onward(edited) }
    }
    return player
  }
  const focused = []
  {
    const player = jumping(U.startUpNext(album(4), 0))
    const view = mountUpNext(player)
    let tree = view.draw()
    find(byClass('app-upnext-edit'), tree)[0].props.onClick()
    tree = view.draw(false)
    view.focusables(focused)
    view.commit()
    check('Edit pressed: focus to Done, which now ends Edit - not dropped to the page as the Edit button goes', [find(byClass('app-upnext-edit'), tree).length, focused], [0, ['done']])
  }
  {
    focused.length = 0
    const player = jumping(U.startUpNext(album(4), 0))
    const view = mountUpNext(player)
    let tree = view.draw()
    const second = find(byClass('app-result'), tree)[1]
    const [, , third] = find((node) => node.type === 'li' && node.props?.['data-key'] !== undefined, tree)
    second.props.onClick()
    tree = view.draw(false)
    view.focusables(focused)
    view.commit()
    check('a row\'s tap: it plays, so it leaves the list - focus to the row after it', [playing(player.queue), focused], ['3', [`play:${third.props['data-key']}`]])
    focused.length = 0
    find(byClass('app-result'), tree).slice(-1)[0].props.onClick()
    tree = view.draw(false)
    view.focusables(focused)
    view.commit()
    check('...the last row\'s tap: focus to Done', [playing(player.queue), focused], ['4', ['done']])
  }
  {
    focused.length = 0
    const player = jumping(U.withNext(U.startUpNext(album(3), 0), [track('a')]))
    const view = mountUpNext(player)
    let tree = view.draw()
    const listFirst = find(byClass('app-result'), find(byClass('app-upnext-group'), tree)[1])[0]
    const firstKey = player.queue.upNext.marks[2].key
    find(byClass('app-result'), find(byClass('app-upnext-group'), tree)[0])[0].props.onClick()
    tree = view.draw(false)
    view.focusables(focused)
    view.commit()
    check('...Playing Next\'s last row: focus to the list\'s first', [playing(player.queue), listFirst.props['aria-label'], focused], ['a', 'song 2, play now', [`play:${firstKey}`]])
  }
  {
    const { dropIndex } = require(path.join(OUT, 'lib/pins.js'))
    const player = upNextPlayer(U.startUpNext(album(5), 0))
    const view = mountUpNext(player)
    find(byClass('app-upnext-edit'), view.draw())[0].props.onClick()
    let tree = view.draw()
    const rows = () => find(byClass('app-pin-row'), tree)
    const grip = () => find(byClass('app-pin-grip'), rows()[0])[0]
    const key = rows()[0].props['data-key']
    //? the row's box as the browser would lay it out: 56 px apart
    const item = { offsetTop: 0, offsetHeight: 56, nextElementSibling: { offsetTop: 56 }, previousElementSibling: null }
    let captured = null
    grip().props.onPointerDown({ button: 0, pointerId: 7, clientY: 100, currentTarget: { closest: () => item, setPointerCapture: (id) => { captured = id } }, preventDefault() {} })
    tree = view.draw()
    grip().props.onPointerMove({ pointerId: 7, clientY: 220 })
    tree = view.draw()
    check('the grip\'s drag: the pointer captured, the row lifted and following it', [captured, byClass('is-dragging')(rows()[0]), rows()[0].props.style], [7, true, { transform: 'translateY(120px)' }])
    grip().props.onPointerMove({ pointerId: 8, clientY: 400 })
    tree = view.draw()
    check('...another pointer moves nothing', rows()[0].props.style, { transform: 'translateY(120px)' })
    grip().props.onPointerUp({ pointerId: 7, clientY: 220 })
    tree = view.draw()
    const to = dropIndex(0, 120, 56, 4)
    check('...let go: moveInQueue to where it landed, read out, the row put down', [to, player.calls.slice(-1)[0], status(tree), rows().some((row) => byClass('is-dragging')(row))], [2, ['moveInQueue', key, 2], 'song 2: 3 of 4', false])
    player.calls.length = 0
    grip().props.onPointerDown({ button: 0, pointerId: 9, clientY: 100, currentTarget: { closest: () => item }, preventDefault() {} })
    tree = view.draw()
    grip().props.onPointerUp({ pointerId: 9, clientY: 110 })
    tree = view.draw()
    check('...a drag that lands where it began moves nothing', player.calls, [])
  }
}

console.log('\nthe player bar\'s Shuffle, Repeat and Up Next, rendered (2.0.0-player.57 review)')
{
  const { PlayerBar } = require(path.join(OUT, 'player/PlayerBar.js'))
  const bar = (player, props = {}) => PlayerBar({ player, onAlbum: null, onInfo() {}, infoOpen: false, onVisualizer() {}, ...props })
  const player = upNextPlayer(U.startUpNext(album(3), 0))
  const button = (tree, name) => find(byClass(name), tree)[0]
  let tree = bar({ ...player })
  const repeatOf = (tree) => [button(tree, 'app-playbar-repeat').props['aria-label'], button(tree, 'app-playbar-repeat').props['aria-pressed'], byClass('is-on')(button(tree, 'app-playbar-repeat'))]
  const seen = [repeatOf(tree)]
  for (let i = 0; i < 3; i++) {
    button(tree, 'app-playbar-repeat').props.onClick()
    tree = bar({ ...player })
    seen.push(repeatOf(tree))
  }
  check('Repeat cycles off -> all -> one -> off, named and pressed for each', [seen, player.calls.map(([, mode]) => mode)],
    [[['Repeat: off', false, false], ['Repeat: all', true, true], ['Repeat: one', true, true], ['Repeat: off', false, false]], ['all', 'one', 'off']])
  player.calls.length = 0
  const shuffleOf = (tree) => [button(tree, 'app-playbar-shuffle').props['aria-pressed'], byClass('is-on')(button(tree, 'app-playbar-shuffle')), button(tree, 'app-playbar-shuffle').props['aria-disabled']]
  const off = shuffleOf(tree)
  button(tree, 'app-playbar-shuffle').props.onClick()
  tree = bar({ ...player })
  check('Shuffle: off, then pressed - setShuffle(true) - and on', [off, player.calls, shuffleOf(tree)], [[false, false, false], [['setShuffle', true]], [true, true, false]])
  const paged = upNextPlayer(U.startUpNext(album(3), 0, false, Math.random, { token: 't', total: 9, fetched: 3, scope: 'store' }))
  tree = bar({ ...paged })
  button(tree, 'app-playbar-shuffle').props.onClick()
  check('...a whole library\'s shuffle: on, aria-disabled and named for it, the click doing nothing',
    [shuffleOf(tree), button(tree, 'app-playbar-shuffle').props['aria-label'], paged.calls], [[true, true, true], 'Shuffle - shuffling all music', []])
  //? (second review) named by its scope, in Up Next's words: Browse's Songs (store) is everything, your albums yours
  const yours = upNextPlayer(U.startUpNext(album(3), 0, false, Math.random, { token: 't', total: 9, fetched: 3, scope: 'yours' }))
  check('...of your albums: named for your library',
    button(bar({ ...yours }), 'app-playbar-shuffle').props['aria-label'], 'Shuffle - shuffling your whole library')
  const opened = []
  tree = bar({ ...player }, { onUpNext: (event) => opened.push(event), upNextOpen: false })
  const upNext = find((node) => node.props?.['aria-label'] === 'Up Next', tree)[0]
  upNext.props.onClick('the click')
  const shown = find((node) => node.props?.['aria-label'] === 'Up Next', bar({ ...player }, { onUpNext() {}, upNextOpen: true }))[0]
  check('Up Next: its click to App with the event; pressed and expanded while the panel shows', [opened, upNext.props['aria-expanded'], shown.props['aria-expanded'], byClass('is-on')(shown)], [['the click'], false, true, true])
  //? (2.0.0-player.58) Add to a playlist: in the tools, before Info, its click to App with the event - nothing of the player
  const added = []
  player.calls.length = 0
  tree = bar({ ...player }, { onAddToPlaylist: (event) => added.push(event) })
  const toPlaylist = find((node) => node.props?.['aria-label'] === 'Add to a playlist', tree)
  const tools = find(byClass('app-playbar-tools'), tree)[0]
  const named = find((node) => node.type === 'button', tools).map((node) => node.props['aria-label'])
  toPlaylist[0]?.props.onClick('the click')
  check('Add to a playlist: one button in the tools, before Info; its click to App with the event, the player untouched',
    [toPlaylist.length, named.indexOf('Add to a playlist') === named.indexOf('Info') - 1, added, player.calls], [1, true, ['the click'], []])
  check('...and none without the handler', find((node) => node.props?.['aria-label'] === 'Add to a playlist', bar({ ...player })).length, 0)
}

console.log('\nthe song menu: Play Next, Play Last - the albums remembered, then the player, then the notice only when queued')
{
  W.sheets.length = 0
  W.calls.length = 0
  const asked = []
  const player = {
    playNext: (tracks) => { asked.push(['playNext', tracks.map((t) => t.id)]); W.calls.push(['playNext']); return false },
    playLast: (tracks) => { asked.push(['playLast', tracks.map((t) => t.id)]); W.calls.push(['playLast']); return true },
  }
  const render = hooks.root(QueueMenu)
  const pick = { label: 'Roads', tracks: [track('roads')], albums: [{ id: 'dum', name: 'Dummy' }] }
  let closed = 0
  const tree = render({ open: true, pick, opener: { current: null }, onClose: () => { closed += 1 }, player })
  const items = find(byClass('app-menu-item'), tree)
  check('two rows and Cancel, named for what it was opened with; a sheet of its own', [items.map(words), words(find(byClass('app-menu-cancel'), tree)), find((node) => node.props?.role === 'dialog', tree)[0].props['aria-label'], W.sheets[0].lockClass],
    [['Play Next', 'Play Last'], 'Cancel', 'Roads', 'app-queue-menu-open'])
  items[0].props.onClick()
  check('Play Next: the album remembered, then playNext with the songs, the menu closed, the notice (it queued them)',
    [W.calls, asked, closed], [[['rememberAdded', ['dum']], ['playNext'], ['sayPins', 'Playing next: Roads']], [['playNext', ['roads']]], 1])
  W.calls.length = 0
  render({ open: true, pick: { ...pick, label: 'Dummy' }, opener: { current: null }, onClose: () => { closed += 1 }, player })
  find(byClass('app-menu-item'), render({ open: true, pick: { ...pick, label: 'Dummy' }, opener: { current: null }, onClose: () => { closed += 1 }, player }))[1].props.onClick()
  check('Play Last that started the music (nothing was playing): no notice - the mini player says so', [W.calls, closed], [[['rememberAdded', ['dum']], ['playLast']], 2])
  //? (2.0.0-player.58) Add to a playlist…, third: App's, handed what the menu was opened with - nothing of the player
  W.calls.length = 0
  const picked = []
  const rows = find(byClass('app-menu-item'), render({ open: true, pick, opener: { current: null }, onClose: () => { closed += 1 }, player, onPlaylist: (what) => picked.push([what.label, what.tracks.map((t) => t.id)]) }))
  check('with App\'s onPlaylist: Play Next, Play Last, Add to a playlist…', rows.map(words), ['Play Next', 'Play Last', 'Add to a playlist…'])
  rows[2].props.onClick()
  check('...its tap hands App the songs it was opened with, and calls nothing of the player', [picked, W.calls, asked.length], [[['Roads', ['roads']]], [], 2])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
