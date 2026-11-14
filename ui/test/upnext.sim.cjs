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
 *    time round. (2.1.3) The runs also tap rows of Up Next and of History and go back by Previous (wentBack), and
 *    after every step: startedAt at or before the song playing; History exactly the units Previous walks back
 *    through, down to its floor, each row naming the song Previous plays there (review); every copy of the song its
 *    run began with (review: Shuffle and Repeat left a list song's copies behind it); every row drawn - Up
 *    Next's and History's - reached by its tap and nothing else before the song playing; Up Next drawing every
 *    song before the next time round (after Previous, songs added among the list's included) - (2.1.18) and after a
 *    roll-back every song up to the furthest played and what was drawn after it then, in order; an Up Next tap
 *    landing on its own key and keeping every song. (2.1.18) A History tap ROLLS BACK: the same queue, the place moved
 *    back to the row - outside Repeat One less the copies after it - every row from it on drawn as it was, now to come,
 *    History above it the rows above, and with no copies exactly Previous's walk to it; older rows brought back
 *    (broughtBack: entries of the queue before History's floor, out of order, copies, other songs, twice, and songs
 *    from elsewhere) play first, each moved or new by the rule, carrying its starts, with History's songs, the song
 *    that was playing and Up Next after them as drawn. Some runs are long albums, so History's 50 is in play.
 *  - Play Next and Play Last's places (after Repeat One's copies; Play Last after the songs added, still ahead
 *    of the list); a row out, moved within its group and refused across; Clear; (2.1.3) a jump into the list
 *    (the songs passed kept behind it in order, Playing Next carried after it, nothing noted as taken out) and
 *    into Playing Next (the same queue, the songs added above it behind it).
 *  - Shuffle on: the song playing and everything before it untouched, the songs added kept in order, the
 *    list's songs not yet heard this round shuffled (an album started at song 5 and shuffled at 7: 1-4 and
 *    8-12), a song removed or jumped over (behind the song jumped to) not among them, entries queued keeping their keys; at a round's last
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
 *  - (2.1.3) James's walk (playing 5, tap 8: Previous plays 7, 6, 5, then Next 6), with a song added (still next
 *    after 8; after Previous drawn in the list where it plays, Clear not taking it); History's rows (from where
 *    listening began - Previous before it moving that down - a Repeat One run one row, Repeat All's earlier round
 *    as it played, HISTORY_BACK) and (2.1.18) its tap, a roll-back (James's B, C, D with D playing and songs added - they keep their
 *    place; Previous from it the row above; Repeat One keeping copies, off and All letting them go; Repeat All's
 *    earlier round, Repeat off then keeping what played; Shuffle on not reshuffling; a row History doesn't draw
 *    refused) and older rows brought back (moved, new, a library's shuffle carrying on after them); Up Next rendered
 *    with History: opened at the song playing, History's heading and "play again" rows, the song's title a heading,
 *    one Tab stop and the arrow keys, a History tap holding the card where the row was and saying what plays, a
 *    list's or Playing Next's tap bringing the new card to the top with focus on what plays next, a song's end
 *    never creeping the view, Edit hiding History, a new queue opening at its card. (review) The scroller fake stops
 *    where the content ends, so: an album's last songs still opening at the card (.app-upnext-now) and never
 *    creeping; Shuffle, Edit's Move, drag and Remove leaving the scroll where it is; a tap the engine doesn't take
 *    moving, focusing and saying nothing; the same words said twice as two nodes of the live region.
 *  - (2.1.15) the play history above History (built and drawn only while open - those drawn as it closes kept until
 *    the queue changes): one list with no heading - the older rows, then History's - each start
 *    drawn once (the queue's own by its rows; one falling past HISTORY_BACK, or of another queue, above), one Tab stop
 *    across both, an older row's tap ((2.1.18) jumpTo with it and every older row below it, their songs at the setting's
 *    level, in the click - said, the card held where the row was, focus to what plays next), Edit hiding them, the next older page asked within the scroller's height of
 *    the top and a page landing above holding the view, the spinner while it comes, a failure in a listener's words
 *    with Try again and no more asks until it is pressed. (history.sim.cjs holds the rules by property.)
 *  - (2.1.18 review) Shuffle after a roll-back across Repeat All's rounds: on, the later round's songs moved back down
 *    kept after the round playing's, each round shuffled on its own (never starting with the song before it, over 200
 *    orders), Repeat One's copies with their song; off, the list's order; Repeat off keeping them. An older row's tap
 *    racing the engine's catchUp: the floor drawn goes with the rows (jumpTo's `floor`), so the song at History's top
 *    as drawn is kept - in broughtBack and through UpNext's tap. The rows' songs are copies at a level of their own
 *    (queued's), in the property too: a moved entry keeps its own track and level, a new one the row's.
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
write('player/api.js', `exports.rememberAdded = (albums, queued) => globalThis.__upnext.calls.push(['rememberAdded', albums.map((a) => a.id), (queued ?? []).map((t) => t.albumId)])\n`)
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
  //? (2.1.3) after Previous: the order behind the place as it played - copies, then a run of songs added, then units
  //? whose list songs' rounds never go down, songs added among them
  const loose = (queue) => {
    const marks = queue.upNext.marks.slice(queue.index + 1)
    let i = 0, pass = -Infinity
    while (marks[i]?.from === 'one') i++
    for (; i < marks.length; i++) {
      const mark = marks[i]
      if (mark.from === 'source') { if (mark.pass < pass) return `pass ${mark.pass} after ${pass}`; pass = mark.pass }
    }
    return null
  }
  //? (2.1.18) the key of the unit playing; the rows Up Next draws after it, every one (no cap); where History's rows begin
  const playingKey = (q) => { let p = q.index; while (p > 0 && q.upNext.marks[p].from === 'one') p--; return q.upNext.marks[p].key }
  const aheadKeys = (q, repeat) => { const v = U.upNextView(q, repeat, Infinity); return [...v.added, ...(v.list?.rows ?? [])].map((row) => row.key) }
  const firstShown = (q) => {
    const rows = U.historyRows(q)
    if (rows.length) return q.upNext.marks.findIndex((m) => m.key === rows[0].key)
    return q.upNext.marks.findIndex((m) => m.key === playingKey(q))
  }
  const strip = (q) => ({ tracks: q.tracks.map((t) => t.id), index: q.index, upNext: q.upNext })
  let walkedBack = 0, historyTaps = 0, drawnChecked = 0, walkedTo = 0, brought = 0, broughtMoved = 0, broughtNew = 0, longRuns = 0
  for (let run = 0; run < 2000; run++) {
    const random = seeded(run + 1)
    let back = false
    const pick = (n) => Math.floor(random() * n)
    //? (2.1.18) the seed's first draw let go: from a small seed it is always near 0 - every run had been a one-song
    //? album. And one run in twenty a long album, so History's 50 - and older rows of the queue before it - come in
    random()
    const long = run % 20 === 7
    if (long) longRuns++
    const size = long ? 55 + pick(20) : 1 + pick(6)
    let repeat = U.REPEATS[pick(3)]
    let queue = U.toppedUp(U.startUpNext(album(size), random() < 0.3 ? null : pick(size), random() < 0.5, random), repeat, random)
    let extra = 0
    for (let step = 0; step < 30; step++) {
      const before = queue
      const op = pick(15)
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
        if (op === 8 || op === 12) {
          //? (2.1.3) 12: a row of History's tap - a key History draws; 8: a row of Up Next's - its keys mostly, any key of
          //? the queue's (one before the song playing History doesn't draw too) or none at times
          const drawnHistory = U.historyRows(queue)
          const key = op === 12 && drawnHistory.length ? drawnHistory[pick(drawnHistory.length)].key
            : random() < 0.5 ? someKey() : queue.upNext.marks[pick(queue.upNext.marks.length)].key
          const place = queue.upNext.marks.findIndex((m) => m.key === key)
          const fromHistory = drawnHistory.some((row) => row.key === key)
          const jumped = U.jumpedTo(queue, key, repeat)
          if (jumped?.back) {
            //? (2.1.18) a roll-back: History's rows alone, and the same queue with the place moved back to the row - outside
            //? Repeat One less the copies after it (a row plays once) - the same objects, nothing added
            if (!fromHistory) note(run, step, `entry ${place}, not drawn in History, rolled back to`)
            historyTaps++
            const keeps = (i) => !(repeat !== 'one' && i > place && queue.upNext.marks[i].from === 'one')
            const wantTracks = queue.tracks.filter((_, i) => keeps(i)), wantMarks = queue.upNext.marks.filter((_, i) => keeps(i))
            const j = jumped.queue
            if (jumped.index !== place || j.index !== place || j.tracks.length !== wantTracks.length || j.tracks.some((t, i) => t !== wantTracks[i]) || j.upNext.marks.some((m, i) => m !== wantMarks[i]) || j.upNext.nextKey !== queue.upNext.nextKey) note(run, step, 'History\'s tap: not the same queue, moved back to the row')
            //? ...every row from it on drawn as it was, now to come: the row tapped the card, then History's rows after it,
            //? the song that was playing, Playing Next, the list - in that order
            const tappedAt = drawnHistory.findIndex((row) => row.key === key)
            const was = [...drawnHistory.slice(tappedAt).map((row) => row.key), playingKey(queue), ...aheadKeys(queue, repeat)]
            const now = [playingKey(j), ...aheadKeys(j, repeat)]
            if (was.join() !== now.join()) note(run, step, `History's tap: drawn ${now} where ${was} was`)
            //? ...History above it the rows above the row tapped (and further back, the floor moving down with it)
            const above = drawnHistory.slice(0, tappedAt).map((row) => row.key)
            const nowHistory = U.historyRows(j).map((row) => row.key)
            if (nowHistory.length < above.length || nowHistory.slice(nowHistory.length - above.length).join() !== above.join()) note(run, step, 'History\'s tap: History above it rewritten')
            //? ...and with no copies anywhere, exactly Previous's walk to it, one row at a time
            if (!queue.upNext.marks.some((m) => m.from === 'one')) {
              let w = queue
              while (w.index > place) { const b = U.backward(w, 0); if (b.kind !== 'go') break; w = U.wentBack(w, b.index) }
              if (JSON.stringify(strip(w)) !== JSON.stringify(strip(j))) note(run, step, 'History\'s tap: not where Previous walks to')
              walkedTo++
            }
            queue = j
            back = true
          } else if (jumped) {
            if (fromHistory) note(run, step, 'a row History draws jumped to, not rolled back to')
            const kept = jumped.queue.index === queue.index &&
              jumped.queue.tracks.slice(0, queue.index + 1).every((t, i) => t === queue.tracks[i]) &&
              jumped.queue.upNext.marks.slice(0, queue.index + 1).every((m, i) => m === queue.upNext.marks[i])
            if (!kept) note(run, step, 'a jump\'s edit touched the song playing or before it')
            if (!(jumped.index > queue.index && jumped.index < jumped.queue.tracks.length)) note(run, step, `a jump to ${jumped.index} from ${queue.index}`)
            if (place <= queue.index) note(run, step, `entry ${place}, not drawn in History, jumped to`)
            //? an Up Next tap lands on its own key and drops no song
            if (jumped.queue.upNext.marks[jumped.index].key !== key) note(run, step, 'an Up Next tap landed elsewhere')
            const songs = (q) => q.tracks.map((t) => t.id).sort().join()
            if (songs(jumped.queue) !== songs(queue)) note(run, step, 'an Up Next tap dropped or added a song')
            queue = at(jumped.queue, jumped.index)
          } else if (fromHistory) note(run, step, 'a row History draws refused')
        } else if (op === 14) {
          //? (2.1.18) older rows of the play history brought back, oldest first: entries of this queue (before History's
          //? floor or not, in order or not, copies, another song than theirs, one twice) and songs from elsewhere
          const from = firstShown(queue)
          const { marks } = queue.upNext
          const rows = Array.from({ length: 1 + pick(4) }, (_, i) => {
            const starts = Array.from({ length: 1 + pick(2) }, (_, k) => run * 1000 + step * 10 + i * 3 + k)
            if (random() < 0.6) {
              const p = pick(Math.max(1, random() < 0.8 ? from : queue.tracks.length))
              //? the row's song as UpNext.tsx passes it: queued(..., 'songs')'s copy, at a level of its own (the 2.1.18
              //? review) - so a moved entry is seen keeping its own track, a new one the row's
              return { track: random() < 0.9 ? { ...queue.tracks[p], level: random() < 0.5 ? 'album' : 'track' } : track(`x${extra++}`), starts, entry: marks[p].key }
            }
            return { track: track(`p${extra++}`), starts, entry: random() < 0.5 ? null : queue.upNext.nextKey + 5 }
          })
          const jump = U.broughtBack(queue, rows, repeat)
          if (!jump || !jump.back || jump.index !== 0 || jump.queue.index !== 0) note(run, step, 'older rows: not a roll-back to the first')
          else {
            brought++
            const j = jump.queue
            //? each row its own entry, first, in order: moved - the entry it names, kept whole - while that is before
            //? History's floor, not a copy, of the row's song and after the last moved; else a new song added; its starts
            let last = -1
            rows.forEach((row, i) => {
              const p = row.entry === null ? -1 : marks.findIndex((m) => m.key === row.entry)
              const moves = p > last && p < from && marks[p].from !== 'one' && queue.tracks[p].id === row.track.id
              if (moves) last = p
              const mark = j.upNext.marks[i]
              const right = moves
                ? mark.key === marks[p].key && mark.from === marks[p].from && mark.at === marks[p].at && mark.pass === marks[p].pass && j.tracks[i] === queue.tracks[p]
                : mark.from === 'added' && mark.key >= queue.upNext.nextKey && mark.at === -1 && mark.pass === -1 && j.tracks[i] === row.track
              if (moves) broughtMoved++; else broughtNew++
              if (!right || JSON.stringify(mark.starts) !== JSON.stringify(row.starts)) note(run, step, `older row ${i}: not ${moves ? 'moved' : 'a new song added'} with its starts`)
            })
            //? ...then the queue from History's first row on, as it was - outside Repeat One less its copies
            const keeps = (i) => i >= from && !(repeat !== 'one' && queue.upNext.marks[i].from === 'one')
            const rest = queue.tracks.map((t, i) => [t, queue.upNext.marks[i]]).filter((_, i) => keeps(i))
            if (j.tracks.length !== rows.length + rest.length || rest.some(([t, m], i) => j.tracks[rows.length + i] !== t || j.upNext.marks[rows.length + i] !== m)) note(run, step, 'older rows: the queue after them not as it was')
            //? ...drawn as they play: the rows, History's songs, the song that was playing, then Up Next as it was
            const was = [...j.upNext.marks.slice(0, rows.length).map((m) => m.key), ...U.historyRows(queue).map((row) => row.key), playingKey(queue), ...aheadKeys(queue, repeat)]
            const now = [playingKey(j), ...aheadKeys(j, repeat)]
            if (was.join() !== now.join()) note(run, step, `older rows: drawn ${now} where ${was} was`)
            if (j.upNext.startedAt !== 0 || U.historyRows(j).length || j.upNext.id !== queue.upNext.id) note(run, step, 'older rows: History, startedAt or the queue\'s id not as they should be')
            queue = j
            back = true
          }
        } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = at(queue, next) }
        else if (op === 13) {
          //? Previous, early: as the engine moves (wentBack - startedAt follows it down before where listening began)
          const b = U.backward(queue, 0)
          if (b.kind === 'go') { queue = U.wentBack(queue, b.index); back = true; walkedBack++ }
        } else queue = ended(queue)
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
      const wrong = back ? loose(queue) : shape(queue)
      if (wrong) note(run, step, `op ${op}: ${wrong}`)
      //? (2.1.3) History is where listening began or later, and exactly what Previous walks back through: each landing's
      //? unit, oldest first, down to the floor (startedAt, HISTORY_BACK entries back)
      if (queue.upNext.startedAt > queue.index) note(run, step, `startedAt ${queue.upNext.startedAt} past the song playing (${queue.index})`)
      {
        const floor = Math.max(queue.upNext.startedAt, queue.index - U.HISTORY_BACK, 0)
        const walk = [], heard = []
        for (let w = queue; ;) {
          const b = U.backward(w, 0)
          if (b.kind !== 'go') break
          let unit = b.index
          while (unit > 0 && marks[unit].from === 'one') unit--
          if (marks[unit].from === 'one' || unit < floor) break
          walk.unshift(unit)
          heard.unshift(queue.tracks[b.index].id)
          w = at(w, b.index)
        }
        const rows = U.historyRows(queue)
        const drawn = rows.map((row) => marks.findIndex((m) => m.key === row.key))
        if (drawn.join() !== walk.join()) note(run, step, `History at ${drawn} where Previous walks ${walk}`)
        //? (2.1.3 review) ...and by SONG: each row names the song Previous plays there - the last row the song Previous
        //? plays now. Places alone missed a run of copies left behind its song and joined to the row before it
        if (rows.map((row) => row.track.id).join() !== heard.join()) note(run, step, `History names ${rows.map((row) => row.track.id)} where Previous plays ${heard}`)
      }
      //? (2.1.3 review) every copy is of the song its run began with: a unit is one song, never two
      marks.forEach((m, i) => {
        if (m.from !== 'one') return
        let start = i
        while (start > 0 && marks[start].from === 'one') start--
        if (queue.tracks[start].id !== queue.tracks[i].id) note(run, step, `op ${op}: entry ${i}, a copy of ${queue.tracks[i].id}, in ${queue.tracks[start].id}'s run`)
      })
      //? every row drawn is one a tap reaches - Up Next's moves onto it, History's plays its song again; History's keys all
      //? before the song playing, Up Next's after it, none twice
      const view = U.upNextView(queue, repeat)
      const ahead = [...view.added, ...(view.list?.rows ?? [])]
      const placeOf = (key) => marks.findIndex((m) => m.key === key)
      if (view.history.some((row) => placeOf(row.key) >= queue.index) || ahead.some((row) => placeOf(row.key) <= queue.index)) note(run, step, 'a row on the wrong side of the song playing')
      if (new Set([...view.history, ...ahead].map((row) => row.key)).size !== view.history.length + ahead.length) note(run, step, 'a row drawn twice')
      //? ...and Up Next draws every song that plays before the next time round (up to its cap): none hidden behind a
      //? song added that Previous walked back across - (2.1.18) and after a roll-back (or Previous), every song up to the
      //? furthest played and what was drawn after it while it played, whatever its time round: in order, each once
      {
        const end = (q) => {
          const shown = U.shownPass(q)
          let p = q.index + 1
          while (q.upNext.marks[p]?.from === 'one') p++
          for (; p < q.upNext.marks.length; p++) {
            const m = q.upNext.marks[p]
            if (m.from === 'source' && m.pass !== shown) break
          }
          return p
        }
        const reachAt = marks.findIndex((m) => m.key === queue.upNext.reached)
        const stop = Math.max(end(queue), reachAt > queue.index ? end(at(queue, reachAt)) : 0)
        const want = []
        for (let p = queue.index + 1; p < stop; p++) if (marks[p].from !== 'one') want.push(marks[p].key)
        const drawn = view.added.length + (view.list ? view.list.rows.length + view.list.more - (queue.upNext.paged ? Math.max(0, queue.upNext.paged.total - queue.upNext.paged.fetched) : 0) : 0)
        if (drawn !== want.length) note(run, step, `Up Next draws ${drawn} of the ${want.length} songs to come`)
        if (aheadKeys(queue, repeat).join() !== want.join()) note(run, step, `Up Next draws ${aheadKeys(queue, repeat)} where ${want} play`)
      }
      for (const row of [...ahead, ...view.history]) {
        const jumped = U.jumpedTo(queue, row.key, repeat)
        drawnChecked++
        if (!jumped || jumped.queue.tracks[jumped.index] !== row.track) { note(run, step, `row ${row.key} not reached by its tap`); break }
      }
      marks.forEach((m, i) => {
        if (m.from === 'source' && m.at < 0) note(run, step, `entry ${i} of the list has no place in it`)
        //? a copy of a song added has no place in the list (-1); any other knows its own
        if (m.at >= 0 && queue.upNext.source[m.at]?.id !== queue.tracks[i].id) note(run, step, `entry ${i} is not its place in the list`)
      })
    }
  }
  check('every step of every run keeps it', problems, [])
  check(`...the runs walked back (${walkedBack} times), tapped History (${historyTaps}) and checked every row drawn (${drawnChecked})`, [walkedBack > 500 || walkedBack, historyTaps > 500 || historyTaps, drawnChecked > 10000 || drawnChecked], [true, true, true])
  check(`...(2.1.18) a History tap Previous's walk (${walkedTo}), older rows brought back (${brought}: ${broughtMoved} moved, ${broughtNew} new), long albums (${longRuns})`,
    [walkedTo > 300 || walkedTo, brought > 500 || brought, broughtMoved > 200 || broughtMoved, broughtNew > 500 || broughtNew, longRuns > 50 || longRuns], [true, true, true, true, true])
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
  const toList = U.jumpedTo(start, keyOf(start, '4'), 'off')
  const moved = at(toList.queue, toList.index)
  check('(2.1.3) into the list: it plays, the songs passed kept behind it in order, Playing Next after it', [playing(moved), ids(moved), moved.index, after(moved)], ['4', ['1', '2', '3', '4', 'a', 'b', '5'], 3, ['a', 'b', '5']])
  check('...nothing noted as taken out of the round: the songs passed are behind it, not gone', toList.queue.upNext.left, [])
  const toAdded = U.jumpedTo(start, keyOf(start, 'b'), 'off')
  const there = at(toAdded.queue, toAdded.index)
  check('(2.1.3) into Playing Next: the songs added above it kept behind it - the same queue, the place moved', [toAdded.queue === start, playing(there), ids(there).slice(0, there.index), after(there)], [true, 'b', ['1', 'a'], ['2', '3', '4', '5']])
  check('the song playing, a copy, a key it doesn\'t have: null', [U.jumpedTo(start, start.upNext.marks[0].key, 'off'), U.jumpedTo(U.toppedUp(start, 'one'), U.toppedUp(start, 'one').upNext.marks[1].key, 'one'), U.jumpedTo(start, 77, 'off')], [null, null, null])
  const one = U.toppedUp(U.startUpNext(album(3), 0), 'one')
  const jumped = U.jumpedTo(one, keyOf(one, '3'), 'one')
  check('with Repeat One on: past the copies, onto the row', [playing(at(jumped.queue, jumped.index)), ids(jumped.queue)], ['3', ['1', '1', '1', '2', '3']])
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
  const jumped = U.jumpedTo(at(start, 6), keyOf(start, '10'), 'off')
  const overJumped = U.withShuffle(at(jumped.queue, jumped.index), true, seeded(3))
  check('...nor songs jumped over (8 and 9) - (2.1.3) behind the song jumped to, heard this round as far as a shuffle goes',
    [playing(overJumped), after(overJumped).includes('8'), after(overJumped).includes('9'), ids(overJumped).slice(7, 9), after(overJumped).slice().sort((x, y) => x - y)], ['10', false, false, ['8', '9'], ['1', '2', '3', '4', '11', '12']])
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
  check('nothing playing: nothing drawn', U.upNextView(Q.EMPTY_QUEUE, 'all'), { history: [], playing: null, added: [], list: null, then: null, repeatOne: false })
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


/* ===== (2.1.3) History, and a tap that keeps what it passes ===== */

//? Previous early, as the engine moves: backward's place, startedAt following it down before where listening began
const previous = (queue) => { const b = U.backward(queue, 1); return b.kind === 'go' ? U.wentBack(queue, b.index) : queue }
const history = (queue) => U.historyRows(queue).map((row) => row.track.id)

console.log('\n(2.1.3) James\'s walk: tap 8 while 5 plays - Previous plays 7, then 6, as on the album')
{
  let q = at(U.startUpNext(album(12), 0), 4)
  const jump = U.jumpedTo(q, keyOf(q, '8'), 'off')
  check('nothing to edit - the same queue, and the place to move to: 8\'s', [jump.queue === q, jump.index], [true, 7])
  q = at(jump.queue, jump.index)
  check('8 plays; nothing moved, nothing dropped, nothing noted as taken out', [playing(q), ids(q).join(), q.upNext.left], ['8', '1,2,3,4,5,6,7,8,9,10,11,12', []])
  check('History: 1 to 7 (6 and 7 behind 8, where Previous finds them); Up Next 9 to 12', [U.upNextView(q, 'off').history.map((r) => r.track.id), U.upNextView(q, 'off').list.rows.map((r) => r.track.id)], [['1', '2', '3', '4', '5', '6', '7'], ['9', '10', '11', '12']])
  const walk = []
  for (let i = 0; i < 3; i++) { q = previous(q); walk.push(playing(q)) }
  check('Previous, early, three times: 7, 6, 5', walk, ['7', '6', '5'])
  q = at(q, U.onward(q))
  check('...then Next: 6, as on the album (and its end: 7)', [playing(q), playing(ended(q))], ['6', '7'])
}
{
  const start = U.withNext(at(U.startUpNext(album(12), 0), 4), [track('a', { album: 'Dummy', albumId: 'dum' })])
  const jump = U.jumpedTo(start, keyOf(start, '8'), 'off')
  let q = at(jump.queue, jump.index)
  check('with a song added: it goes after 8, still next', [jump.index, ids(q).slice(4, 10), U.upNextView(q, 'off').added.map((r) => r.track.id)], [7, ['5', '6', '7', '8', 'a', '9'], ['a']])
  q = previous(q)
  const v = U.upNextView(q, 'off')
  check('...Previous to 7: Up Next draws 8, the song added where it plays, then the rest - no Playing Next above them, no Clear to take what it doesn\'t head',
    [playing(q), v.added.length, v.list.title, v.list.rows.map((r) => r.track.id), U.withoutAdded(q) === q], ['7', 0, 'From Mezzanine', ['8', 'a', '9', '10', '11', '12'], true])
  const aKey = keyOf(q, 'a')
  const tapA = U.jumpedTo(q, aKey, 'off')
  check('...that row moves, comes out and is tapped like the list\'s', [after(U.movedKey(q, aKey, 0)).slice(0, 3), after(U.withoutKey(q, aKey)).slice(0, 2), tapA.queue === q, playing(at(tapA.queue, tapA.index))], [['a', '8', '9'], ['8', '9'], true, 'a'])
}

console.log('\n(2.1.3) History: what is behind the song playing')
{
  const fromFive = U.startUpNext(album(12), 4)
  check('an album started at song 5: nothing in History - 1 to 4 were never heard (Previous still plays 4)', [U.upNextView(fromFive, 'off').history, U.backward(fromFive, 1)], [[], { kind: 'go', index: 3 }])
  check('...at song 7: 5 and 6', U.upNextView(at(fromFive, 6), 'off').history.map((r) => r.track.id), ['5', '6'])
  let back = previous(fromFive)
  check('...Previous from 5 (wentBack): 4, where listening now began - History still empty, the same songs',
    [playing(back), back.upNext.startedAt, history(back), back.tracks === fromFive.tracks], ['4', 3, [], true])
  check('...once 4 has played: History 4', history(ended(back)), ['4'])
  const later = at(fromFive, 6)
  const wb = U.wentBack(later, 5)
  check('wentBack at or after where listening began: the place moves, the account the same but for how far it had got (2.1.18 reached, 7\'s key)',
    [wb.index, wb.tracks === later.tracks, { ...wb.upNext, reached: undefined }, wb.upNext.reached], [5, true, { ...later.upNext, reached: undefined }, later.upNext.marks[6].key])
  check('...and again from there: the same account, the furthest kept', U.wentBack(wb, 4).upNext === wb.upNext, true)
  const plainQueue = { tracks: album(3), index: 2 }
  const plainBack = U.wentBack(plainQueue, 1)
  check('...a plain queue: the place, nothing else', [plainBack.index, plainBack.tracks === plainQueue.tracks, 'upNext' in plainBack], [1, true, false])
  const shuffled = U.startUpNext(album(6), 3, true, seeded(5))
  check('Shuffle from a song: History is what played of the shuffle', history(at(shuffled, 3)), ids(shuffled).slice(0, 3))
  const library = U.startUpNext(album(3), 0, false, Math.random, { token: 't', total: 9, fetched: 3, scope: 'yours' })
  check('...a library\'s shuffle: from its first song', history(at(library, 2)), ['1', '2'])
  //? Repeat One on song 2 for three plays, then off, then on to 4
  let one = U.toppedUp(at(U.startUpNext(album(5), 0), 1), 'one')
  one = ended(one); one = U.toppedUp(one, 'one'); one = ended(one)
  one = U.toppedUp(U.withRepeat(one, 'off'), 'off')
  one = at(one, U.onward(one)); one = at(one, U.onward(one))
  const oneView = U.upNextView(one, 'off')
  check('Repeat One\'s copies: one row for the song, keyed by its first entry', [ids(one).slice(0, one.index + 1), oneView.history.map((r) => r.track.id), oneView.history[1].key === one.upNext.marks[1].key], [['1', '2', '2', '2', '3', '4'], ['1', '2', '3'], true])
  check('...playing a copy: History stops before the song\'s run (Previous passes it)', history(at(one, 2)), ['1'])
  let all = U.toppedUp(U.startUpNext(album(3), 0), 'all')
  for (let i = 0; i < 4; i++) { all = ended(all); all = U.toppedUp(all, 'all') }
  check('Repeat All: the earlier time round in History, as it played', [playing(all), U.upNextView(all, 'all').history.map((r) => r.track.id)], ['2', ['1', '2', '3', '1']])
  const long = at(U.startUpNext(album(80), 0), 70)
  const lv = U.upNextView(long, 'off')
  check(`as far back as a reload keeps: HISTORY_BACK (${U.HISTORY_BACK}) entries`, [U.HISTORY_BACK, lv.history.length, lv.history[0].track.id, lv.history.slice(-1)[0].track.id], [50, 50, '21', '70'])
  check('nothing playing: no History', U.historyRows(Q.EMPTY_QUEUE), [])
}
{
  //? (2.1.3 review) Repeat One on 2, Previous to 1 - 2 and its copies now after 1 - then Shuffle on: 2 goes into the
  //? shuffle WITH its copies. Left behind, they joined 1's run: History said 1 while Previous played 2, and 1 was
  //? out of Previous's reach
  let q = U.toppedUp(at(U.startUpNext(album(5), 0), 1), 'one')
  q = U.toppedUp(previous(q), 'one')
  check('Repeat One on 2, Previous: 1 and its copies, then 2\'s run, after it', ids(q), ['1', '1', '1', '2', '2', '2', '3', '4', '5'])
  q = U.withShuffle(q, true, seeded(7))
  check('...Shuffle on: 2\'s copies went with it, 1\'s stayed', [ids(q).slice(0, 3), ids(q).filter((id) => id === '2').length, q.upNext.marks.filter((m) => m.from === 'one').length], [['1', '1', '1'], 1, 2])
  q = U.toppedUp(at(q, U.onward(q)), 'one')
  const b = U.backward(q, 0)
  check('...Next, then Previous: History\'s row and the song Previous plays the same - 1', [history(q), q.tracks[b.index].id], [['1'], '1'])
  //? Repeat All's next round started, Repeat One on it, Previous back into the first round: Repeat One again (from All)
  //? drops the later round's song - with its copies
  let r = U.toppedUp(at(U.startUpNext(album(2), 0), 1), 'all')
  r = U.toppedUp(ended(r), 'all')
  r = U.toppedUp(U.withRepeat(r, 'one'), 'one')
  r = U.toppedUp(previous(r), 'one')
  check('Repeat All into round two, Repeat One there, Previous into round one: the second round\'s 1 and its copies after 2', [playing(r), froms(r)], ['2', ['o', 'o', 's1', 'o', 'o', 's1']])
  //? (the player never asks for the mode it has - usePlayer's setRepeat - but the rule holds for any queue)
  //? (2.1.18) Previous walked back from the second round's 1, so that round played: Repeat lets go only of rounds after it
  const kept = U.withRepeat(r, 'one')
  check('...Repeat One asked of it: the second round\'s 1 played (Previous walked back from it), so it stays - the same object', kept === r, true)
  const fresh = U.withRepeat({ ...r, upNext: { ...r.upNext, reached: undefined } }, 'one')
  check('...a later round nobody reached goes, its copies with it - only the song playing\'s own left', [ids(fresh).slice(fresh.index), froms(fresh)], [['2', '2', '2'], ['o', 'o']])
}

console.log('\n(2.1.18) History\'s tap rolls back: the playing point moves up the list, everything after it to come')
{
  //? James's: A, B, C, D played, D playing, songs added waiting - "Keep their place": tap B, then B, C, D, the songs added, the rest
  const abc = ['A', 'B', 'C', 'D', 'E', 'F'].map((id) => track(id))
  let q = U.withNext(at(U.startUpNext(abc, 0), 3), [track('n1'), track('n2')])
  const kB = q.upNext.marks[1].key
  const jump = U.jumpedTo(q, kB, 'off')
  check('tap B with D playing: a roll-back to B - the same songs, in the same order, the place moved back to it',
    [jump.back, jump.index, jump.queue.index, ids(jump.queue), jump.queue.tracks === q.tracks, jump.queue.upNext.marks === q.upNext.marks], [true, 1, 1, ['A', 'B', 'C', 'D', 'n1', 'n2', 'E', 'F'], true, true])
  q = jump.queue
  const v = U.upNextView(q, 'off')
  check('...Up Next: C, D, the songs added where they were, then the rest - History above it A',
    [playing(q), v.history.map((r) => r.track.id), v.added.map((r) => r.track.id), v.list.rows.map((r) => r.track.id), v.list.title], ['B', ['A'], [], ['C', 'D', 'n1', 'n2', 'E', 'F'], 'From Mezzanine'])
  check('...nothing above the card twice, nothing lost: every song after B is to come', [after(q)], [['C', 'D', 'n1', 'n2', 'E', 'F']])
  check('...Previous from it: A, the row above; Next: C, then D (from its start - a new play)', [playing(previous(q)), playing(at(q, U.onward(q))), playing(ended(ended(q)))], ['A', 'C', 'D'])
  check('...the furthest song played named (D), so the list runs on to it and past it', q.upNext.reached, q.upNext.marks[3].key)
  let walk = q
  const heard = []
  for (let i = 0; i < 6; i++) { walk = ended(walk); heard.push(playing(walk)) }
  check('...played on: C, D, n1, n2, E, F - and History grows as they play', [heard, history(walk)], [['C', 'D', 'n1', 'n2', 'E', 'F'], ['A', 'B', 'C', 'D', 'n1', 'n2', 'E']])
  check('...the songs added keep their place: Clear above the card doesn\'t reach them (they play after D)', U.withoutAdded(q) === q, true)
  //? a tap past it again, rolled back further, and forward: still one list
  const deeper = U.jumpedTo(at(q, 2), q.upNext.marks[0].key, 'off')
  check('C playing, tap A: the furthest played still D - the list to come B, C, D, the songs added, the rest',
    [deeper.queue.upNext.reached, U.upNextView(deeper.queue, 'off').list.rows.map((r) => r.track.id)], [q.upNext.marks[3].key, ['B', 'C', 'D', 'n1', 'n2', 'E', 'F']])
  check('...a list row tapped from there: the rows it passes behind it, as ever', ids(at(U.jumpedTo(deeper.queue, keyOf(deeper.queue, 'E'), 'off').queue, U.jumpedTo(deeper.queue, keyOf(deeper.queue, 'E'), 'off').index)).join(), 'A,B,C,D,n1,n2,E,F')
}
{
  //? with no copies, a History tap is Previous's walk to it, one row at a time
  const q = at(U.startUpNext(album(9), 0), 6)
  let w = q
  while (w.index > 2) w = previous(w)
  const jump = U.jumpedTo(q, q.upNext.marks[2].key, 'off')
  check('tap 3 with 7 playing: exactly where Previous, four times, lands - and Previous\'s account', JSON.stringify(jump.queue), JSON.stringify(w))
  check('...a roll-back nothing changes but the place uses the queue\'s own tracks - a seek in the stream, not a new one', jump.queue.tracks === q.tracks, true)
}
{
  //? Repeat One: the copies stay - the run played as drawn; off and All: a row plays once, the copies after it go
  let one = U.toppedUp(at(U.startUpNext(album(4), 0), 1), 'one')
  one = ended(one); one = U.toppedUp(one, 'one'); one = ended(one); one = U.toppedUp(one, 'one')
  one = U.toppedUp(U.withRepeat(one, 'off'), 'off'); one = at(one, U.onward(one))
  one = U.toppedUp(U.withRepeat(one, 'one'), 'one')
  check('2 three times under Repeat One, then 3 under Repeat One again', [ids(one), playing(one)], [['1', '2', '2', '2', '3', '3', '3', '4'], '3'])
  const kept = U.jumpedTo(one, one.upNext.marks[1].key, 'one')
  check('...tap 2 with Repeat One on: back to 2, every copy kept - 2 three times, then 3 three times, then 4', [kept.index, ids(kept.queue)], [1, ['1', '2', '2', '2', '3', '3', '3', '4']])
  const off = U.jumpedTo(U.toppedUp(U.withRepeat(one, 'off'), 'off'), one.upNext.marks[1].key, 'off')
  check('...with Repeat off: back to 2, the copies after it gone - 2, 3, 4 once each', [off.index, ids(off.queue), U.upNextView(off.queue, 'off').list.rows.map((r) => r.track.id)], [1, ['1', '2', '3', '4'], ['3', '4']])
  check('...the song playing, its copies, a key gone: null', [U.jumpedTo(one, one.upNext.marks[4].key, 'one'), U.jumpedTo(one, one.upNext.marks[5].key, 'one'), U.jumpedTo(one, 99, 'one')], [null, null, null])
  const fromFive = at(U.startUpNext(album(12), 4), 6)
  check('an entry before where listening began (History doesn\'t draw it): null', U.jumpedTo(fromFive, fromFive.upNext.marks[1].key, 'off'), null)
  const long = at(U.startUpNext(album(80), 0), 70)
  const oldest = U.jumpedTo(long, long.upNext.marks[20].key, 'off')
  check('past HISTORY_BACK: null; at it, rolled back - 22 to 80 to come, History reaching 50 back from 21',
    [U.jumpedTo(long, long.upNext.marks[19].key, 'off'), playing(oldest.queue), after(oldest.queue).length, U.upNextView(oldest.queue, 'off').list.more, U.historyRows(oldest.queue).length], [null, '21', 59, 0, 20])
}
{
  //? Repeat All: a roll-back into the earlier round - the rounds after it moved back down, drawn whole, Repeat off keeping them
  let rounds = U.toppedUp(at(U.startUpNext(album(3), 0), 2), 'all')
  rounds = U.toppedUp(ended(rounds), 'all')
  rounds = U.toppedUp(ended(rounds), 'all')
  check('Repeat All, the second time round\'s 2 playing', [playing(rounds), froms(rounds)], ['2', ['s1', 's2', 's2', 's2']])
  const back = U.jumpedTo(rounds, rounds.upNext.marks[0].key, 'all')
  const v = U.upNextView(back.queue, 'all')
  check('...tap 1 of the first time round: 2, 3, then the second round\'s 1 and 2 and the rest of it, 3 - one list, as drawn while 2 played',
    [playing(back.queue), v.list.rows.map((r) => r.track.id), v.list.title], ['1', ['2', '3', '1', '2', '3'], 'From Mezzanine'])
  const off = U.withRepeat(back.queue, 'off')
  check('...Repeat off: what played stays (the second round\'s 1 and 2), the rounds after it go', [after(off), U.upNextView(off, 'off').list.rows.map((r) => r.track.id)], [['2', '3', '1', '2', '3'], ['2', '3', '1', '2', '3']])
  check('...Repeat One from there: the same - what played stays, only copies are made', after(U.toppedUp(U.withRepeat(back.queue, 'one'), 'one')).slice(0, 7), ['1', '1', '2', '3', '1', '2', '3'])
  const movedUp = U.movedKey(back.queue, back.queue.upNext.marks[3].key, 0)
  check('...Edit moving the second round\'s 1 to the top of that one list: each place keeps its time round, so the rounds never go down - and every song is still drawn',
    [after(movedUp).slice(0, 5), froms(movedUp).slice(0, 5), U.upNextView(movedUp, 'all').list.rows.map((r) => r.track.id)], [['1', '2', '3', '2', '3'], ['s0', 's0', 's1', 's1', 's1'], ['1', '2', '3', '2', '3']])
  //? the furthest played (the second round's 2) taken out, or moved up: the list still runs on to every song that was
  //? at or before it - the reach handed to the unit before it, or to the last of them now
  const reachKey = back.queue.upNext.reached
  const removed = U.withoutKey(back.queue, reachKey)
  check('...Edit removing the furthest song played (the second round\'s 2): the second round\'s 1 the furthest now, and still drawn - 2, 3, 1, 3',
    [removed.upNext.reached === back.queue.upNext.marks[3].key, U.upNextView(removed, 'all').list.rows.map((r) => r.track.id)], [true, ['2', '3', '1', '3']])
  const reachUp = U.movedKey(back.queue, reachKey, 0)
  check('...Edit moving it to the top: the furthest now the second round\'s 1, the last of those at or before it - every song still drawn',
    [reachUp.upNext.reached === back.queue.upNext.marks[3].key, U.upNextView(reachUp, 'all').list.rows.map((r) => r.track.id)], [true, ['2', '2', '3', '1', '3']])
  //? (2.1.18 review) Shuffle on after it: the second round's songs it moved back down - 1 and 2, and the rest of that
  //? round, 3 - still to come, after the first round's 2 and 3; each round in a new order of its own (so the rounds never
  //? go down), none starting with the song before it; then off: the list's order, both rounds; Repeat off keeps them
  const turnedOn = U.withShuffle(back.queue, true, seeded(5))
  check('(2.1.18 review) Shuffle on: 2 and 3 of the first round, then 1, 2 and 3 of the second - each round shuffled on its own, all drawn',
    [playing(turnedOn), after(turnedOn).slice(0, 2).sort(), after(turnedOn).slice(2).sort(), froms(turnedOn), U.upNextView(turnedOn, 'all').list.rows.map((r) => r.track.id).join() === after(turnedOn).join(), turnedOn.upNext.shuffle],
    ['1', ['2', '3'], ['1', '2', '3'], ['s0', 's0', 's1', 's1', 's1'], true, true])
  //? (each seed's first draw let go: from a small seed it is always near 0)
  const orders = Array.from({ length: 200 }, (_, seed) => { const random = seeded(seed + 1); random(); return after(U.withShuffle(back.queue, true, random)) })
  check('...over 200 orders, each round in orders of its own - the first\'s 2 and 3 both ways, the second\'s all six - and the second never starting with the song that ends the first\'s (toppedUp\'s rule)',
    [new Set(orders.map((a) => a.slice(0, 2).join())).size, new Set(orders.map((a) => a.slice(2).join())).size, orders.filter((a) => a[1] === a[2]).length], [2, 6, 0])
  check('...Shuffle off again: the first round\'s 2 and 3, the second\'s 1, 2, 3 - the list\'s order; Repeat off from there keeps all five',
    [after(U.withShuffle(turnedOn, false)), froms(U.withShuffle(turnedOn, false)), after(U.withRepeat(U.withShuffle(turnedOn, false), 'off'))],
    [['2', '3', '1', '2', '3'], ['s0', 's0', 's1', 's1', 's1'], ['2', '3', '1', '2', '3']])
  check('...Repeat off with Shuffle on: all five kept', after(U.withRepeat(turnedOn, 'off')).length, 5)
  //? ...each unit whole: the second round's 1 three times over and its 2 twice (Repeat One), the first round's 2 tapped
  {
    let c = U.toppedUp(at(U.startUpNext(album(3), 0), 2), 'all')
    c = U.toppedUp(U.withRepeat(ended(c), 'one'), 'one')
    c = U.toppedUp(ended(c), 'one'); c = U.toppedUp(ended(c), 'one')
    c = U.toppedUp(at(c, U.onward(c)), 'one')
    const tapped = U.jumpedTo(c, c.upNext.marks[1].key, 'one').queue
    const runs = (q) => after(q).reduce((list, id, i) => (i && q.upNext.marks[q.index + 1 + i].from === 'one' ? list.slice(0, -1).concat(`${list[list.length - 1]}${id}`) : [...list, id]), [])
    const shuffles = Array.from({ length: 12 }, (_, seed) => runs(U.withShuffle(tapped, true, seeded(seed + 1))).slice(1).sort().join())
    check('...Repeat One\'s copies in the second round: shuffled with their song - each order the same units, whole; off, the list\'s order',
      [runs(tapped), [...new Set(shuffles)], runs(U.withShuffle(U.withShuffle(tapped, true, seeded(1)), false))],
      [['3', '11111', '222', '3'], ['11111,222,3'], ['3', '11111', '222', '3']])
  }
  {
    //? ...and past Up Next's 100: 200 songs under Repeat All begun at 150, played round to the second time's 10, the
    //? first time's 200 tapped in History, then Shuffle on - 1-149 shuffled, then the second round: wherever its 1-10
    //? (played, moved back down) land, the queue still holds every one (shownKeys - their starts never drawn above),
    //? the furthest played moved to whichever of them is last now
    let long = U.toppedUp(U.startUpNext(album(200), 149), 'all')
    while (long.index < 209) long = U.toppedUp(ended(long), 'all')
    const tapped = U.jumpedTo(long, long.upNext.marks[199].key, 'all').queue
    const played = tapped.upNext.marks.slice(200, 210).map((m) => m.key)
    const held = Array.from({ length: 6 }, (_, seed) => {
      const on = U.withShuffle(tapped, true, seeded(seed + 11))
      const shown = U.shownKeys(on)
      const places = played.map((key) => on.upNext.marks.findIndex((m) => m.key === key))
      return [played.every((key) => shown.has(key)), on.upNext.reached === on.upNext.marks[Math.max(...places)].key]
    })
    check('...past the 100 rows drawn, over six orders: the second round\'s 1-10 all held by the queue, the furthest played the last of them',
      [playing(tapped), after(tapped).length, held], ['200', 200, Array.from({ length: 6 }, () => [true, true])])
  }
  //? Shuffle on: a roll-back never reshuffles - what the tap moved down comes in the order it played
  const shuffledQ = at(U.startUpNext(album(6), 0, true, seeded(3)), 4)
  const rolled = U.jumpedTo(shuffledQ, shuffledQ.upNext.marks[1].key, 'off')
  check('a shuffle rolled back from its 5th song to its 2nd: its 3rd, 4th, 5th and 6th to come, in the shuffle\'s order, Shuffle still on',
    [after(rolled.queue), rolled.queue.upNext.shuffle], [ids(shuffledQ).slice(2), true])
  //? ...Shuffle turned on after one: the songs added keep their order; the list's songs to come, those moved back down
  //? among them, in a new order (the song playing and those above it heard)
  const plain = U.withNext(at(U.startUpNext(album(6), 0), 4), [track('a')])
  const turned = U.withShuffle(U.jumpedTo(plain, plain.upNext.marks[1].key, 'off').queue, true, seeded(4))
  check('...Shuffle on after rolling an album back from 5 to 2: 3-6 shuffled, the song added after 5 among them as Shuffle keeps songs added (first)',
    [playing(turned), after(turned)[0], after(turned).slice(1).sort().join()], ['2', 'a', '3,4,5,6'])
}
{
  //? older rows of the play history brought back - broughtBack
  const q = at(U.startUpNext(album(80).map((t) => ({ ...t, level: 'album' })), 0), 70)
  //? z played in another queue, then this album from its start - at 71 now, so its 1-20 are older rows (past History's 50);
  //? each row's song as UpNext.tsx passes it, queued(..., 'songs')'s copy - at the track level here
  const rows = Array.from({ length: 20 }, (_, i) => ({ track: { ...q.tracks[i], level: 'track' }, starts: [1000 + i], entry: q.upNext.marks[i].key }))
  const elsewhere = { track: track('z', { album: 'Dummy', albumId: 'dum', level: 'track' }), starts: [900, 901], entry: null }
  const jump = U.broughtBack(q, [elsewhere, ...rows], 'off')
  const v = U.upNextView(jump.queue, 'off', Infinity)
  check('an album at 71, older rows z (another queue\'s, played twice in a run) and 1-20 (this queue\'s, past History\'s 50): tap z - a roll-back to it',
    [jump.back, jump.index, playing(jump.queue), ids(jump.queue).slice(0, 4), jump.queue.tracks.length], [true, 0, 'z', ['z', '1', '2', '3'], 81])
  check('...z a song added; 1-20 moved - their own entries, the list\'s; each carrying the starts its row stood for',
    jump.queue.upNext.marks.slice(0, 3).map((m) => [m.key, m.from, m.starts]), [[80, 'added', [900, 901]], [0, 'source', [1000]], [1, 'source', [1001]]])
  check('(2.1.18 review) ...1-20 each their own track, the list\'s (its level, album) - not the row\'s copy at the track level; z the row\'s own',
    [jump.queue.tracks.slice(1, 21).every((t, i) => t === q.tracks[i]), jump.queue.tracks[1].level, jump.queue.tracks[0] === elsewhere.track, jump.queue.tracks[0].level], [true, 'album', true, 'track'])
  check('...to come, as drawn: 1-20, History\'s 21-70, 71 (the song that was playing), 72-80 - every song after it, in order',
    v.list.rows.map((r) => r.track.id).join(), album(80).map((t) => t.id).join())
  check('...the list\'s heading this time round\'s, as before the tap - not "again" (the round of the list\'s first song after the rows, which lead into it)',
    [v.list.title, U.upNextView(jump.queue, 'off').list.title], [U.upNextView(q, 'off').list.title, 'From Mezzanine'])
  check('...nothing before it: History empty, Previous the song again; where listening began, 0', [U.historyRows(jump.queue), U.backward(jump.queue, 0).kind, jump.queue.upNext.startedAt], [[], 'restart', 0])
  check('...the queue the same queue (its id, its list)', [jump.queue.upNext.id === q.upNext.id, jump.queue.upNext.source === q.upNext.source], [true, true])
  check('...the starts it holds, by song and moment', U.heldStarts(jump.queue).slice(0, 4), [{ id: 'z', at: 900 }, { id: 'z', at: 901 }, { id: '1', at: 1000 }, { id: '2', at: 1001 }])
  const one = U.broughtBack(q, [rows[12]], 'off')
  check('one older row, 13: it, then History\'s 21 on - the 1-12 and 14-20 never drawn below it go', [ids(one.queue).slice(0, 3), one.queue.tracks.length], [['13', '21', '22'], 61])
  const out = U.broughtBack(q, [rows[2], rows[0]], 'off')
  check('rows out of the queue\'s order: the first moved, the one before it a song added (the list keeps its order)', out.queue.upNext.marks.slice(0, 2).map((m) => m.from), ['source', 'added'])
  check('no rows, or nothing playing: null', [U.broughtBack(q, [], 'off'), U.broughtBack(Q.EMPTY_QUEUE, rows, 'off')], [null, null])
  //? a library's shuffle carries on: its pages still land at the end, and what is to come counts them
  const paged = { token: 't1', total: 40, fetched: 3, scope: 'yours' }
  const lib = at(U.startUpNext(album(3, 'p'), 0, false, Math.random, paged), 2)
  const libBack = U.broughtBack(lib, [{ track: track('old'), starts: [5], entry: null }], 'off')
  const more = U.withMore(libBack.queue, 't1', album(2, 'q'))
  check('a library\'s shuffle rolled back to an older row: its pages carry on, at the end, counted',
    [ids(more), U.upNextView(more, 'off').list.more, more.upNext.paged.fetched], [['old', 'p1', 'p2', 'p3', 'q1', 'q2'], 35, 5])
}
{
  //? (2.1.18 review) the tap racing the engine's catchUp: History at its 50 (10-59, 60 playing), older rows 5-9 tapped -
  //? and the stream had crossed into 61 before its timeupdate, so jumpTo's catchUp moves on first and History's floor
  //? with it (11). The rows were read against 10's: `floor`, the first entry drawn, keeps the queue from there
  const drawn = at(U.startUpNext(album(80), 0), 59)
  const floor = U.historyRows(drawn)[0].key
  const caught = at(drawn, 60)
  const rows = [4, 5, 6, 7, 8].map((i) => ({ track: drawn.tracks[i], starts: [2000 + i], entry: drawn.upNext.marks[i].key }))
  const withFloor = U.broughtBack(caught, rows, 'off', floor)
  const without = U.broughtBack(caught, rows, 'off')
  check('(2.1.18 review) a tap on 5 with 10-59 drawn, caught up to 61 first: with the floor drawn (10\'s), 5-80 in order, 10 once; without it, 10 lost',
    [U.historyRows(drawn)[0].track.id, U.historyRows(caught)[0].track.id, ids(withFloor.queue).join() === album(80).slice(4).map((t) => t.id).join(), ids(without.queue).includes('10'), without.queue.tracks.length],
    ['10', '11', true, false, 75])
  check('...the floor at or after History\'s own (no race), or a key it hasn\'t: as without it - History\'s floor',
    [ids(U.broughtBack(caught, rows, 'off', U.historyRows(caught)[0].key).queue).join() === ids(without.queue).join(), ids(U.broughtBack(caught, rows, 'off', caught.upNext.marks[70].key).queue).join() === ids(without.queue).join(),
      ids(U.broughtBack(caught, rows, 'off', 999).queue).join() === ids(without.queue).join()], [true, true, true])
}

console.log('\n(2.1.3) Shuffle off after a jump in a shuffle: the album from that song\'s place')
{
  const shuffled = U.startUpNext(album(6), 0, true, seeded(2))
  const order = ids(shuffled)
  const jump = U.jumpedTo(shuffled, shuffled.upNext.marks[3].key, 'off')
  const off = U.withShuffle(at(jump.queue, jump.index), false)
  check('the songs the tap passed behind it, as the shuffle played them; the album on from the song jumped to\'s place', [jump.queue === shuffled, ids(off).slice(0, 4), playing(off), after(off)],
    [true, order.slice(0, 4), order[3], album(6).map((t) => t.id).filter((id) => Number(id) > Number(order[3]))])
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
const { UpNext, REPEATING_ONE, SHUFFLING_LIBRARY, HISTORY } = require(path.join(OUT, 'app/UpNext.js'))
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
  let focused = []
  const all = () => ({ open: true, opener: { current: null }, onClose: () => W.calls.push(['close']), player: { ...player }, ...props })
  //? drawn and its effects run, as Preact does after each render - but a draw that asks focus somewhere is committed by the
  //? check, once the fakes its effect reaches are in place (focusables)
  const draw = (commit = true) => { tree = render(all()); if (commit) render.commit(); return tree }
  //? (2.1.3) the scroller as a browser lays it out: 400 px tall from y 100; every row ([data-key]) and the song playing's
  //? card ([data-playing]) 56 px tall, one under the other in the tree's order, less what is scrolled - never past the
  //? top, nor (review) past where the content ends: History's rows, then the card and what follows it, which in
  //? .app-upnext-now are at least the scroller's height (app.css min-height: 100% - test_app_css holds the rule)
  const PITCH = 56
  let scrolled = 0
  //? (2.1.15) the play history's older rows ([data-past]) too, above History's
  const laidOut = () => find((node) => (node.type === 'li' && (node.props?.['data-key'] !== undefined || node.props?.['data-past'] !== undefined)) || node.props?.['data-playing'] !== undefined, tree)
  const furthest = () => {
    const nodes = laidOut()
    const card = nodes.findIndex((node) => node.props?.['data-playing'] !== undefined)
    if (card < 0) return Math.max(0, nodes.length * PITCH - 400)
    const tail = (nodes.length - card) * PITCH
    return Math.max(0, card * PITCH + (find(byClass('app-upnext-now'), tree).length ? Math.max(tail, 400) : tail) - 400)
  }
  const element = (node, order) => ({
    dataset: node.props['data-key'] !== undefined ? { key: String(node.props['data-key']) } : node.props['data-past'] !== undefined ? { past: node.props['data-past'] } : {},
    getBoundingClientRect: () => ({ top: 100 + PITCH * order - scrolled, bottom: 100 + PITCH * (order + 1) - scrolled }),
    querySelector: (selector) => {
      if (/app-result/.test(selector)) {
        const button = find(byClass('app-result'), node)[0]
        return button ? { focus: () => focused.push(`play:${node.props['data-key'] ?? node.props['data-past']}`) } : null
      }
      const which = /app-pin-(up|down|remove)/.exec(selector)[1]
      const button = find(byClass(`app-pin-${which}`), node)[0]
      if (!button || (/aria-disabled/.test(selector) && button.props['aria-disabled'])) return null
      return { focus: () => focused.push(`${which}:${node.props['data-key']}`) }
    },
  })
  const box = {
    get scrollTop() { return scrolled },
    set scrollTop(value) { scrolled = Math.max(0, Math.min(value, furthest())) },
    clientHeight: 400,
    getBoundingClientRect: () => ({ top: 100, bottom: 500 }),
    querySelectorAll: (selector) => laidOut().map(element).filter((each) => each.dataset.key !== undefined || each.dataset.past !== undefined || /data-playing/.test(selector)),
  }
  return {
    draw,
    get tree() { return tree },
    get scrollTop() { return scrolled },
    commit: () => render.commit(),
    //? the listener scrolling the sheet: the scroller moved, and its 'scroll' heard
    scroll(to) { box.scrollTop = to; find(byClass('app-info-scroll'), tree)[0].props.onScroll() },
    //? the scroller, Done and the Shuffle chip as fakes - what the layout effects reach by their refs
    focusables(into) {
      focused = into
      find(byClass('app-info-scroll'), tree)[0].props.ref.current = box
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
      const jump = U.jumpedTo(player.queue, key, player.repeat)
      if (jump) player.queue = { ...jump.queue, index: jump.index }
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


console.log('\n(2.1.3) Up Next drawn with History above the song playing, opened at the song playing')
{
  //? the engine's jump, as usePlayer's jumpTo makes it: jumpedTo's queue, then the entry it names (a roll-back's queue is
  //? already there)
  const jumping = (queue) => {
    const player = upNextPlayer(queue)
    player.jumpTo = (key) => {
      player.calls.push(['jumpTo', key])
      const jump = U.jumpedTo(player.queue, key, player.repeat)
      if (jump) player.queue = { ...jump.queue, index: jump.index }
    }
    return player
  }
  //? a draw whose effects reach the fakes: drawn, the fakes put in, committed
  const shown = (view, focused = []) => { const tree = view.draw(false); view.focusables(focused); view.commit(); return tree }
  const historyOf = (tree) => find(byClass('app-result'), find(byClass('app-upnext-history'), tree)[0])
  const keyAt = (queue, id, from = 0) => queue.upNext.marks[queue.tracks.findIndex((t, i) => i >= from && t.id === id)].key

  {
    const player = jumping(U.withNext(at(U.startUpNext(album(6), 0), 2), [track('a')]))
    const view = mountUpNext(player)
    let tree = shown(view)
    check('opened at the song playing: its card at the top of the scroller, History\'s two rows above it (2 x 56 px)', view.scrollTop, 112)
    const titles = find((node) => node.type === 'section', tree).map((node) => words(find(byClass('app-section-title'), node)))
    //? (2.1.15) no heading over the songs played - James: one continuous list - its name for a screen reader alone
    check('History first - Apple Music\'s word, its list\'s name, no heading drawn - then Playing Next and the list',
      [HISTORY, find(byClass('app-upnext-history'), tree)[0].props['aria-label'], titles], ['History', 'History', ['', 'Playing Next', 'From Mezzanine']])
    check('...its rows the songs played, oldest first, each "play again"; Up Next\'s still "play now"',
      [historyOf(tree).map((row) => row.props['aria-label']), find(byClass('app-result'), tree).slice(2).map((row) => row.props['aria-label'])],
      [['song 1, play again', 'song 2, play again'], ['song a, play now', 'song 4, play now', 'song 5, play now', 'song 6, play now']])
    const name = find(byClass('app-info-name'), tree)[0]
    check('the song playing\'s title a heading - VoiceOver\'s headings the song, Playing Next, the list; no hidden heading of its own',
      [name.props.role, name.props['aria-level'], find((node) => node.type === 'h3' || node.props?.role === 'heading', tree).map(words), find(byClass('app-visually-hidden'), tree).filter((node) => node.type !== 'p').length],
      ['heading', 3, ['song 3', 'Playing Next', 'From Mezzanine'], 0])

    //? the keyboard: History one Tab stop, Up and Down inside it
    check('History is one Tab stop: its newest row', historyOf(tree).map((row) => row.props.tabIndex), [-1, 0])
    historyOf(tree)[0].props.onFocus()
    tree = shown(view)
    check('...the row last focused, once focused', historyOf(tree).map((row) => row.props.tabIndex), [0, -1])
    const moved = []
    const buttons = historyOf(tree).map((row) => ({ focus: () => moved.push(row.props['aria-label']) }))
    const list = { querySelectorAll: () => buttons }
    const key = (name, from) => { let prevented = false; find((node) => node.type === 'ul' && node.props.onKeyDown, find(byClass('app-upnext-history'), tree)[0])[0].props.onKeyDown({ key: name, currentTarget: list, target: buttons[from], preventDefault: () => { prevented = true } }); return prevented }
    const keys = [key('ArrowDown', 0), key('ArrowUp', 1), key('End', 0), key('Home', 1), key('a', 0)]
    check('...Down and Up move inside it, End and Home to its ends - each kept from scrolling the sheet; other keys left alone',
      [moved, keys], [['song 2, play again', 'song 1, play again', 'song 2, play again', 'song 1, play again'], [true, true, true, true, false]])

  }
  {
    //? (2.1.18) History's tap rolls back: 7 playing with a song added; scrolled up into History, 3 tapped
    const player = jumping(U.withNext(at(U.startUpNext(album(12), 0), 6), [track('a')]))
    const view = mountUpNext(player)
    let tree = shown(view)
    view.scroll(100)
    const order = (key) => find((node) => (node.type === 'li' && node.props?.['data-key'] !== undefined) || node.props?.['data-playing'] !== undefined, view.tree).findIndex((node) => key === 'card' ? node.props['data-playing'] !== undefined : node.props['data-key'] === key)
    const k3 = player.queue.upNext.marks[2].key, k4 = player.queue.upNext.marks[3].key
    const rowTop = 100 + 56 * order(k3) - view.scrollTop
    const focused = []
    historyOf(tree)[2].props.onClick()
    tree = shown(view, focused)
    //? (review) its words come with the draw that shows it taken - the next one
    tree = shown(view)
    const ahead = find(byClass('app-result'), tree).slice(historyOf(tree).length).map((row) => row.props['aria-label'])
    check('a row of History\'s tap (3, 7 playing): jumpTo by its key - rolled back to it, said aloud; History above it 1 and 2; what it moved down - 4 to 7, the song added, 8 to 12 - to come, "play now"',
      [player.calls, status(tree), playing(player.queue), historyOf(tree).map((row) => row.props['aria-label']), ahead],
      [[['jumpTo', k3]], 'Playing song 3', '3', ['song 1, play again', 'song 2, play again'], ['4', '5', '6', '7', 'a', '8', '9', '10', '11', '12'].map((id) => `song ${id}, play now`)])
    check('...the card where the row was, under the finger - nothing above it moved; focus to what plays next (4)', [100 + 56 * order('card') - view.scrollTop, rowTop, view.scrollTop, focused], [rowTop, 112, 100, [`play:${k4}`]])
  }
  {
    const player = jumping(at(U.startUpNext(album(80), 0), 70))
    const view = mountUpNext(player)
    let tree = shown(view)
    const focused = []
    const k22 = player.queue.upNext.marks[21].key
    historyOf(tree)[0].props.onClick()
    tree = shown(view, focused)
    check('History\'s oldest row (21, at HISTORY_BACK) tapped out of view: rolled back to it - History 1 to 20 above it now, the card at the top, focus to 22',
      [playing(player.queue), historyOf(tree).length, historyOf(tree)[0].props['aria-label'], view.scrollTop, focused], ['21', 20, 'song 1, play again', 20 * 56, [`play:${k22}`]])
  }
  {
    const player = jumping(U.withNext(at(U.startUpNext(album(6), 0), 2), [track('a')]))
    const view = mountUpNext(player)
    let tree = shown(view)
    const focused = []
    const aKey = keyAt(player.queue, 'a')
    find(byClass('app-result'), tree).find((row) => row.props['aria-label'] === 'song 5, play now').props.onClick()
    tree = shown(view, focused)
    check('a row of the list\'s tap (song 5): it plays, 4 behind it in History; Playing Next after it - focus to its head - and the card at the top (4 rows of History)',
      [playing(player.queue), historyOf(tree).map((row) => row.props['aria-label']).slice(-2), focused, view.scrollTop], ['5', ['song 3, play again', 'song 4, play again'], [`play:${aKey}`], 224])
    find(byClass('app-upnext-edit'), tree)[0].props.onClick()
    tree = shown(view)
    check('Edit: History hidden (it moves only what is still to play), the card at the top', [find(byClass('app-upnext-history'), tree).length, view.scrollTop], [0, 0])
    find(byClass('app-info-done'), tree)[0].props.onClick()
    tree = shown(view)
    check('...Done: History back above the card, the card still at the top', [historyOf(tree).length, view.scrollTop], [4, 224])
    player.queue = ended(player.queue)
    tree = shown(view)
    check('a song ending by itself with the card at the top: the new card at the top, the view a row further down - nothing creeps', [playing(player.queue), view.scrollTop], ['a', 280])
    view.scroll(0)
    player.queue = ended(player.queue)
    tree = shown(view)
    check('...scrolled to History\'s top: its first row stays where it is', [playing(player.queue), view.scrollTop], ['6', 0])
    view.scroll(0)
    player.queue = at(U.startUpNext(album(6), 0), 3)
    tree = shown(view)
    check('a new queue while open (another album, a queue put back): the card at the top - its keys are a new queue\'s, never held by the old one\'s',
      [history(player.queue), view.scrollTop], [['1', '2', '3'], 168])
  }
  {
    const player = jumping(U.withLast(U.startUpNext(album(4), 0), [track('a'), track('b')]))
    const view = mountUpNext(player)
    let tree = shown(view)
    const focused = []
    const twoKey = keyAt(player.queue, '2')
    find(byClass('app-result'), find(byClass('app-upnext-group'), tree)[0])[1].props.onClick()
    tree = shown(view, focused)
    check('a row of Playing Next\'s tap (b): the song added above it behind it, in History; focus to the list\'s first; the card at the top',
      [playing(player.queue), historyOf(tree).map((row) => row.props['aria-label']), focused, view.scrollTop], ['b', ['song 1, play again', 'song a, play again'], [`play:${twoKey}`], 112])
    const fresh = mountUpNext(upNextPlayer(U.startUpNext(album(3), 0)))
    check('nothing played yet: no History, the card at the top', [find(byClass('app-upnext-history'), shown(fresh)).length, fresh.scrollTop], [0, 0])
  }

  //? (2.1.3 review) a change below the card - Shuffle, Edit's moves, drags and removals - leaves the scroll where it is:
  //? holding the topmost row there followed it wherever the change put it, out of view
  const orderOf = (tree, key) => find((node) => (node.type === 'li' && node.props?.['data-key'] !== undefined) || node.props?.['data-playing'] !== undefined, tree).findIndex((node) => node.props['data-key'] === key)
  const topOf = (view, key) => 100 + 56 * orderOf(view.tree, key) - view.scrollTop
  {
    const player = jumping(at(U.startUpNext(album(30), 0), 2))
    const view = mountUpNext(player)
    let tree = shown(view)
    view.scroll(400)
    const topmost = find((node) => node.type === 'li' && node.props?.['data-key'] !== undefined, tree)[6].props['data-key']
    find(byClass('app-upnext-shuffle'), tree)[0].props.onClick()
    tree = shown(view)
    check('Shuffle (the chip), scrolled into the list: the rows reordered under a scroll that stays where it was - not chasing the row that was topmost',
      [player.calls, view.scrollTop, orderOf(tree, topmost) !== 6], [[['setShuffle', true]], 400, true])
    player.setShuffle(false)
    tree = shown(view)
    check('...the player bar\'s Shuffle, with Up Next open beside the page: the same', view.scrollTop, 400)
  }
  {
    const player = jumping(U.startUpNext(album(30), 0))
    const view = mountUpNext(player)
    let tree = shown(view)
    find(byClass('app-upnext-edit'), tree)[0].props.onClick()
    tree = shown(view)
    view.scroll(290)
    //? the card is 0, the list's rows 1 on: at 290, row 5 (song 6) topmost at 90, row 6 (song 7) under it at 146
    const seven = find(byClass('app-pin-row'), tree)[5].props['data-key']
    find(byClass('app-pin-up'), find(byClass('app-pin-row'), tree)[5])[0].props.onClick()
    tree = shown(view)
    check('Edit\'s Move up on the second row in view: the scroll stays, the row now where the first was - in view, its button with it',
      [view.scrollTop, topOf(view, seven)], [290, 90])
    view.scroll(290)
    const six = find(byClass('app-pin-row'), tree)[5].props['data-key']
    find(byClass('app-pin-remove'), find(byClass('app-pin-row'), tree)[4])[0].props.onClick()
    tree = shown(view)
    check('...Remove on the topmost row: the scroll stays, the row after it sliding up into its place - where Pinned\'s focus goes',
      [view.scrollTop, topOf(view, six)], [290, 90])
    view.scroll(290)
    const dragged = find(byClass('app-pin-row'), tree)[5]
    const key = dragged.props['data-key']
    const item = { offsetTop: 0, offsetHeight: 56, nextElementSibling: { offsetTop: 56 }, previousElementSibling: { offsetTop: -56 } }
    find(byClass('app-pin-grip'), dragged)[0].props.onPointerDown({ button: 0, pointerId: 4, clientY: 300, currentTarget: { closest: () => item, setPointerCapture() {} }, preventDefault() {} })
    tree = shown(view)
    find(byClass('app-pin-grip'), find((node) => node.type === 'li' && node.props?.['data-key'] === key, tree)[0])[0].props.onPointerUp({ pointerId: 4, clientY: 244 })
    tree = shown(view)
    check('...a row dragged up past the topmost: the scroll stays, the row put down where the topmost was', [player.calls.slice(-1)[0][0], view.scrollTop, topOf(view, key)], ['moveInQueue', 290, 90])
  }
  {
    //? a short album's end: the card and what follows it less than the scroller - they are drawn at least its height
    const player = jumping(at(U.startUpNext(album(12), 0), 8))
    const view = mountUpNext(player)
    let tree = shown(view)
    check('an album\'s last songs (12, at 9 - the card and three rows, less than the scroller): it still opens at the card, History\'s 8 rows above it',
      [find(byClass('app-upnext-now'), tree).length, view.scrollTop, find(byClass('app-upnext-now'), tree)[0] && find((node) => node.props?.['data-playing'] !== undefined, find(byClass('app-upnext-now'), tree)[0]).length], [1, 448, 1])
    const tops = []
    for (let i = 0; i < 3; i++) {
      player.queue = ended(player.queue)
      tree = shown(view)
      tops.push(100 + 56 * find((node) => node.type === 'li' && node.props?.['data-key'] !== undefined, find(byClass('app-upnext-history'), tree)[0]).length - view.scrollTop)
    }
    check('...songs ending by themselves keep the card at the top to the album\'s last - no creeping down a row a song', [playing(player.queue), tops], ['12', [100, 100, 100]])
  }

  //? (2.1.3 review) a tap the engine doesn't take - a key gone, an edit the stream can't make while a seek is on its way:
  //? nothing moved, focused or said, then or at the next change
  {
    const player = upNextPlayer(U.withNext(at(U.startUpNext(album(8), 0), 4), [track('a')]))
    const view = mountUpNext(player)
    let tree = shown(view)
    view.scroll(40)
    const focused = []
    find(byClass('app-result'), tree).find((row) => row.props['aria-label'] === 'song 7, play now').props.onClick()
    tree = shown(view, focused)
    const stayed = view.scrollTop
    player.queue = ended(player.queue)
    tree = shown(view, focused)
    check('a list tap not taken, then a song ending by itself: the view where the listener left it, focus left alone, nothing said',
      [player.calls.length, stayed, view.scrollTop, focused, status(tree)], [1, 40, 40, [], ''])
  }
  {
    const player = upNextPlayer(at(U.startUpNext(album(6), 0), 3))
    const view = mountUpNext(player)
    let tree = shown(view)
    const focused = []
    historyOf(tree)[0].props.onClick()
    tree = shown(view, focused)
    tree = shown(view, focused)
    check('a History tap not taken: nothing said to have started, focus left alone', [player.calls.length, playing(player.queue), status(tree), focused], [1, '4', '', []])
  }
  {
    const player = jumping(at(U.startUpNext(album(6), 0), 3))
    const view = mountUpNext(player)
    let tree = shown(view)
    const region = () => find((node) => node.props?.role === 'status', tree)[0].props.children
    historyOf(tree)[0].props.onClick()
    tree = shown(view)
    tree = shown(view)
    const first = region()
    //? (2.1.18) rolled back to 1, History is empty above it: once 1 has played, its row is there to tap again
    player.queue = ended(player.queue)
    tree = shown(view)
    historyOf(tree)[0].props.onClick()
    tree = shown(view)
    tree = shown(view)
    const second = region()
    check('the same History row tapped twice: said twice - the same words, each a new node in the live region (a reader speaks a change, never the same text again)',
      [words(first), words(second), first.type, first.key !== second.key], ['Playing song 1', 'Playing song 1', 'span', true])
  }
}

console.log('\n(2.1.15) the play history above History: one list, no heading - each start drawn once, older pages as it is scrolled, a tap plays it again')
{
  const P = require(path.join(OUT, 'lib/playHistory.js'))
  const L = require(path.join(OUT, 'lib/loudness.js'))
  const persisted = require(path.join(OUT, 'state/persisted.js'))
  const { LOADING_EARLIER } = require(path.join(OUT, 'app/UpNext.js'))
  //? the engine's jump, as usePlayer makes it: a key (jumpedTo) or (2.1.18) older rows brought back (broughtBack)
  //? (2.1.18 review) and the floor its rows were read against (player.floors); `catchUp` set, the engine's catchUp moving on
  //? a song first, as when the stream crossed into the next before its timeupdate
  const replaying = (queue) => {
    const player = upNextPlayer(queue)
    player.floors = []
    player.jumpTo = (to, floor) => {
      player.calls.push(['jumpTo', typeof to === 'number' ? to : to.map((row) => [row.track.id, row.track.level ?? null, row.starts, row.entry])])
      if (typeof to !== 'number') player.floors.push(floor)
      if (player.catchUp) player.queue = ended(player.queue)
      const jump = typeof to === 'number' ? U.jumpedTo(player.queue, to, player.repeat) : U.broughtBack(player.queue, to, player.repeat, floor)
      if (jump) player.queue = { ...jump.queue, index: jump.index }
    }
    return player
  }
  const shown = (view, focused = []) => { const tree = view.draw(false); view.focusables(focused); view.commit(); return tree }
  const listOf = (tree) => find(byClass('app-result'), find(byClass('app-upnext-history'), tree)[0])
  const labels = (tree) => listOf(tree).map((row) => row.props['aria-label'].replace(', play again', ''))
  const pastKeys = (tree) => find((node) => node.type === 'li' && node.props?.['data-past'] !== undefined, tree).map((node) => node.props['data-past'])
  const T = 1_800_000_000_000
  const start = (id, at, queue = 'an-old-queue', entry = 0) => ({ at, counted: false, queue, entry, song: track(id, { title: `song ${id}` }) })
  //? deadwax's pages and this page's starts, newest first, as usePlayHistory hands them
  const book = (plays, more = false) => {
    const history = { plays, more, loading: false, error: null, asked: 0, retried: 0, older() { history.asked++ }, retry() { history.retried++ } }
    return history
  }
  const playedHere = (queue) => {
    const id = queue.upNext.id
    return [start('3', T, id, 2), start('2', T - 100, id, 1), start('1', T - 200, id, 0), start('x', T - 300), start('x', T - 400), start('y', T - 500, 'an-old-queue', 3),
      { ...start('z', T - 600), queue: null, entry: null }]
  }

  {
    const player = replaying(at(U.startUpNext(album(6), 0), 2))
    const history = book(playedHere(player.queue))
    const view = mountUpNext(player, { history })
    let tree = shown(view)
    check('one list above the song playing, oldest at the top: the songs played before this queue, then its own History - no heading over either',
      [labels(tree), find((node) => node.type === 'h3', find(byClass('app-upnext-history'), tree)[0]).length, find((node) => node.type === 'ul', find(byClass('app-upnext-history'), tree)[0]).length],
      [['song z', 'song y', 'song x', 'song 1', 'song 2'], 0, 1])
    check('...each start drawn once: this queue\'s own (1, 2 and 3, playing) by its rows alone; x begun twice running one row, keyed by its first start',
      [pastKeys(tree), find((node) => node.type === 'li' && node.props?.['data-key'] !== undefined, find(byClass('app-upnext-history'), tree)[0]).length], [[`${T - 600}:z`, `${T - 500}:y`, `${T - 400}:x`], 2])
    check('...no times, nothing for a skip - a row is History\'s own: the cover, the title, "artist · album"',
      [words(listOf(tree)[0]), find((node) => node.type === 'time', tree).length], ['song zMassive Attack · Mezzanine', 0])
    check('opened at the song playing: its card at the top, the five rows above it (5 x 56 px)', view.scrollTop, 280)
    check('one Tab stop for all of it: the newest row', listOf(tree).map((row) => row.props.tabIndex), [-1, -1, -1, -1, 0])
    listOf(tree)[1].props.onFocus()
    tree = shown(view)
    check('...an older row, once focused', listOf(tree).map((row) => row.props.tabIndex), [-1, 0, -1, -1, -1])
    check('nothing more to ask for: no older page asked, however near the top', [history.asked, (view.scroll(0), history.asked)], [0, 0])

    //? (2.1.18) an older row's tap, scrolled so y is at the top: rolled back to it, everywhere
    view.scroll(56)
    const focused = []
    const next = player.queue.upNext.nextKey
    listOf(tree)[1].props.onClick()
    tree = shown(view, focused)
    tree = shown(view)
    const level = L.levelled([track('y')], persisted.readPlayerNormalization(), 'songs')[0].level ?? null
    const ahead = () => find(byClass('app-result'), tree).slice(listOf(tree).length).map((row) => row.props['aria-label'].replace(', play now', ''))
    check('an older row\'s tap (y): jumpTo with it and every older row below it (x, begun twice running), oldest first - each song at the setting\'s level, the starts it stood for - in the click, nothing else asked',
      [player.calls], [[['jumpTo', [['y', level, [T - 500], null], ['x', level, [T - 400, T - 300], null]]]]])
    check('...(2.1.18 review) and the first entry drawn for this queue (History\'s first row, 1)', player.floors, [0])
    check('...y plays; x, then this queue\'s 1, 2, 3 (that was playing) and on, to come, in the order drawn; above, only z - nothing drawn twice',
      [playing(player.queue), ahead(), labels(tree), pastKeys(tree), U.historyRows(player.queue)], ['y', ['song x', 'song 1', 'song 2', 'song 3', 'song 4', 'song 5', 'song 6'], ['song z'], [`${T - 600}:z`], []])
    check('...said, the card where the row was (nothing above it moved), focus to what plays next (x)',
      [status(tree), view.scrollTop, focused], ['Playing song y', 56, [`play:${next + 1}`]])
    history.plays = [start('y', T + 100, player.queue.upNext.id, next), ...history.plays]
    tree = shown(view)
    check('...its new start, the song playing, drawn by the queue alone: the older rows as they were',
      [labels(tree), pastKeys(tree), view.scrollTop], [['song z'], [`${T - 600}:z`], 56])
    player.queue = ended(player.queue)
    history.plays = [start('x', T + 200, player.queue.upNext.id, next + 1), ...history.plays]
    tree = shown(view)
    check('...y played, x playing: y back in History as a new start - its old one still held below, x\'s two with it',
      [labels(tree), pastKeys(tree), playing(player.queue)], [['song z', 'song y'], [`${T - 600}:z`], 'x'])
    find(byClass('app-upnext-edit'), tree)[0].props.onClick()
    tree = shown(view)
    check('Edit: the older rows hidden with History', find(byClass('app-upnext-history'), tree).length, 0)
  }
  {
    //? (2.1.18) an older row of THIS queue's - a long album's first songs, begun past History's 50: the tap moves their own
    //? entries back (an older key than any new one), and is known as taken by it - said, focus to what plays next
    const player = replaying(at(U.startUpNext(album(60), 0), 55))
    const id = player.queue.upNext.id
    const history = book(Array.from({ length: 56 }, (_, i) => start(String(i + 1), T - (56 - i) * 100, id, i)).reverse())
    const view = mountUpNext(player, { history })
    let tree = shown(view)
    check('a long album at 56: its first five, begun past History\'s 50, the older rows - this queue\'s',
      pastKeys(tree), [1, 2, 3, 4, 5].map((n) => `${T - (57 - n) * 100}:${n}`))
    const focused = []
    listOf(tree).find((row) => row.props['aria-label'] === 'song 3, play again').props.onClick()
    tree = shown(view, focused)
    tree = shown(view)
    check('...song 3\'s tapped: its own entry moved back, 4 and 5 with it, to come - taken: said, focus to what plays next (4)',
      [playing(player.queue), player.queue.upNext.marks.slice(0, 3).map((m) => [m.key, m.from]), status(tree), focused, pastKeys(tree)],
      ['3', [[2, 'source'], [3, 'source'], [4, 'source']], 'Playing song 3', ['play:3'], [1, 2].map((n) => `${T - (57 - n) * 100}:${n}`)])
  }
  {
    //? (2.1.18 review) ...the same tap racing the engine's catchUp (the stream into 57 before its timeupdate): History's
    //? first row as drawn (6) goes with the rows, so 6 still comes after 5 - nothing between the rows and History lost
    const player = replaying(at(U.startUpNext(album(60), 0), 55))
    const id = player.queue.upNext.id
    const history = book(Array.from({ length: 56 }, (_, i) => start(String(i + 1), T - (56 - i) * 100, id, i)).reverse())
    const view = mountUpNext(player, { history })
    let tree = shown(view)
    player.catchUp = true
    listOf(tree).find((row) => row.props['aria-label'] === 'song 3, play again').props.onClick()
    tree = shown(view)
    check('(2.1.18 review) song 3 tapped as the engine catches up into 57: the floor drawn (6\'s key) passed; 3 playing, 4-60 after it in order - 6 kept',
      [player.floors, playing(player.queue), after(player.queue).join() === album(60).slice(3).map((t) => t.id).join()], [[5], '3', true])
  }
  {
    //? (review) closed - Up Next stays mounted - the older rows are neither built nor drawn at a song's change: those
    //? drawn as it closed stay until the queue changes (nothing above the card moves as the sheet slides away)
    const player = replaying(at(U.startUpNext(album(6), 0), 2))
    const history = book(playedHere(player.queue))
    const opts = { history }
    const view = mountUpNext(player, opts)
    let tree = shown(view)
    const opened = pastKeys(tree).length
    opts.open = false
    tree = shown(view)
    const closing = pastKeys(tree).length
    player.queue = ended(player.queue)
    tree = shown(view)
    const closedOn = pastKeys(tree).length
    history.plays = [...history.plays, ...Array.from({ length: 50 }, (_, i) => start(`w${i}`, T - 1000 - i * 100))]
    player.queue = ended(player.queue)
    tree = shown(view)
    const later = pastKeys(tree).length
    opts.open = true
    tree = shown(view)
    check('closed: the older rows drawn as it closed stay, gone at the next song - none drawn while closed, 50 more played meanwhile included; open again, every one',
      [opened, closing, closedOn, later, pastKeys(tree).length], [3, 3, 0, 0, 53])
  }
  {
    //? a song ending, the queue's History reaching HISTORY_BACK: its oldest start, no longer the queue's row, moves above
    const queue = at(U.startUpNext(album(80), 0), 70)
    const id = queue.upNext.id
    const player = replaying(queue)
    const history = book([start('71', T, id, 70), start('21', T - 100, id, 20), start('20', T - 200, id, 19)])
    const view = mountUpNext(player, { history })
    let tree = shown(view)
    check('History\'s 50 (21 to 70): a start of 20, past it, is an older row; of 21, its own', [pastKeys(tree), labels(tree).length], [[`${T - 200}:20`], 51])
    history.plays = [start('72', T + 100, id, 71), ...history.plays]
    player.queue = ended(player.queue)
    tree = shown(view)
    check('...the next song: 21 falls past it and joins the older rows - still drawn once', [pastKeys(tree), labels(tree).length, labels(tree).filter((title) => title === 'song 21').length], [[`${T - 200}:20`, `${T - 100}:21`], 52, 1])
    check('...the card still at the top - the row that moved above it held', view.scrollTop, 52 * 56)
  }
  {
    //? another queue (an album tapped): every start of the old one is an older row
    const old = U.startUpNext(album(3), 0)
    const player = replaying(at(old, 2))
    const history = book([start('3', T, old.upNext.id, 2), start('2', T - 100, old.upNext.id, 1), start('1', T - 200, old.upNext.id, 0)])
    const view = mountUpNext(player, { history })
    let tree = shown(view)
    player.queue = U.startUpNext(album(2, 'b'), 0)
    history.plays = [start('b1', T + 100, player.queue.upNext.id, 0), ...history.plays]
    tree = shown(view)
    check('another queue: what was played in the last one all above the new song, oldest first', [labels(tree), view.scrollTop], [['song 1', 'song 2', 'song 3'], 168])
  }
  {
    //? paging: near the top the next older page asked for; a page landing above holds the view
    const player = replaying(at(U.startUpNext(album(6), 0), 2))
    const history = book(playedHere(player.queue), true)
    const view = mountUpNext(player, { history })
    let tree = shown(view)
    check('more to ask for: opened with the card under 400 px from the top - within the scroller\'s height - the next page asked for at once', [view.scrollTop, history.asked], [280, 1])
    history.plays = [...history.plays, ...Array.from({ length: 10 }, (_, i) => start(`w${i}`, T - 1000 - i * 100))]
    tree = shown(view)
    check('...it lands above: ten more rows, oldest first, and the card held at the top - nothing moves under the eye; far from the top now, nothing more asked',
      [labels(tree).slice(0, 3), labels(tree).length, view.scrollTop, history.asked], [['song w9', 'song w8', 'song w7'], 15, 280 + 560, 1])
    view.scroll(500)
    check('...scrolled to 500 px from the top: nothing yet', history.asked, 1)
    view.scroll(300)
    check('...to within 400 px: the next page', history.asked, 2)
    history.loading = true
    tree = shown(view)
    view.scroll(200)
    check('while it comes: a spinner at the list\'s top, said as such, and no second ask', [find(byClass('pl-spinner'), tree).map((node) => node.props['aria-label']), history.asked, LOADING_EARLIER], [[LOADING_EARLIER], 2, 'Loading earlier songs'])
    history.loading = false
    history.error = new TypeError('Failed to fetch')
    tree = shown(view)
    view.scroll(100)
    const notice = find(byClass('pl-notice'), find(byClass('app-upnext-history'), tree)[0])
    const again = find((node) => node.type === 'button', notice)[0]
    check('it couldn\'t come: said in a listener\'s words, with Try again - and scrolling asks no more until it is pressed',
      [find(byClass('pl-spinner'), tree).length, words(notice).startsWith("Can't connect to deadwax."), words(again), history.asked], [0, true, 'Try again', 2])
    again.props.onClick()
    check('...Try again: the ask that failed, again', history.retried, 1)
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
    //? (2.1.16) the queue as it stands: its albums handed to rememberAdded, so none is let go for the added ones
    queue: { tracks: [{ id: 'playing', albumId: 'mezz' }, { id: 'loose', albumId: null }], index: 0 },
  }
  const render = hooks.root(QueueMenu)
  const pick = { label: 'Roads', tracks: [track('roads')], albums: [{ id: 'dum', name: 'Dummy' }] }
  let closed = 0
  const tree = render({ open: true, pick, opener: { current: null }, onClose: () => { closed += 1 }, player })
  const items = find(byClass('app-menu-item'), tree)
  check('two rows and Cancel, named for what it was opened with; a sheet of its own', [items.map(words), words(find(byClass('app-menu-cancel'), tree)), find((node) => node.props?.role === 'dialog', tree)[0].props['aria-label'], W.sheets[0].lockClass],
    [['Play Next', 'Play Last'], 'Cancel', 'Roads', 'app-queue-menu-open'])
  items[0].props.onClick()
  check('Play Next: the album remembered (with the queue\'s songs, 2.1.16), then playNext with the songs, the menu closed, the notice (it queued them)',
    [W.calls, asked, closed], [[['rememberAdded', ['dum'], ['mezz', null]], ['playNext'], ['sayPins', 'Playing next: Roads']], [['playNext', ['roads']]], 1])
  W.calls.length = 0
  render({ open: true, pick: { ...pick, label: 'Dummy' }, opener: { current: null }, onClose: () => { closed += 1 }, player })
  find(byClass('app-menu-item'), render({ open: true, pick: { ...pick, label: 'Dummy' }, opener: { current: null }, onClose: () => { closed += 1 }, player }))[1].props.onClick()
  check('Play Last that started the music (nothing was playing): no notice - the mini player says so', [W.calls, closed], [[['rememberAdded', ['dum'], ['mezz', null]], ['playLast']], 2])
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
