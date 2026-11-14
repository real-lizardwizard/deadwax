/**
 * Play history that lasts (2.1.15): lib/playHistory.ts - a start, the join of deadwax's pages with the page's own
 * starts, the older rows above History - the queue's id (lib/upNext.ts queueId, shownFrom), and player/historyOutbox.ts,
 * which keeps this page's starts and sends them, against a fake deadwax on a virtual clock.
 *
 * What it pins:
 *
 *  - EACH START DRAWN ONCE, by property: 1,500 seeded runs of upnext.sim's moves - songs ending, Next, Previous (back
 *    before where listening began too), a tap on Up Next's rows and on History's (2.1.18: a roll-back), (2.1.18) a tap
 *    on an older row (broughtBack with the rows from it down, as Up Next hands them), Play Next and Last, removals,
 *    moves, Shuffle and Repeat with their top-ups, a reload's round trip through the snapshot (the window cut, the
 *    starts brought back with it), another queue now and then - a start recorded at every song begun, as the engine
 *    records it; after every step every start is either the queue's - its entry's, or (2.1.18) held by an entry a row
 *    was brought back as - and that entry among the rows upNextView really draws (History's units, the song playing's,
 *    the songs added, the list's first rows: 8 of them for half the runs, so rows past the limit come up often) or
 *    (2.1.18) moved back down into Up Next, at or before the furthest song played (counted in "And N more") - or one of
 *    the older rows above (exactly one, its run's), never both; and the queue's id the same through every edit, a new
 *    one only for a new queue.
 *  - The pure rules: queueId's shape and that it never calls startUpNext's `random` (a seeded shuffle the same with or
 *    without it); startOf; merged (newest first, once each, `counted` ORed); pastRows (oldest first, a run of one song
 *    one row keyed by its first start, the queue's own left out); withNewest (first page, joined, a gap started again
 *    from, the end, a full page after an empty first one); withOlder (appended, a stale cursor ignored); countedIn;
 *    afterFailure.
 *  - What the queue draws, and nothing more (the 2.1.15 review's probes; 2.1.18, Previous a roll-back): Repeat All into
 *    the next round, Previous twice - that start the queue's, drawn where it plays again; a long album, Previous back past
 *    the list's 100 rows - the starts past them moved down too, counted in "And N more", none above; another queue's
 *    older rows brought back - held, drawn below the card, never above, and above again once fallen past History's 50.
 *  - The outbox: a start kept and sent at once; one at a time, the next batch after the answer; at most 500 waiting
 *    (the oldest let go), so at most 500 a POST; no answer, a 5xx, a 408 or a 429 tried again 30 s on - doubling to
 *    10 min while it keeps failing, from 30 s again once one is taken - and at the next start; a 401 held - no timer -
 *    until the next start; another 4xx let go; counted while waiting sent counted, counted on its way sent again counted, counted after it was taken
 *    marked in the page's own and not sent again; a continuation's start dropped, any other ending it; the newest 500
 *    kept.
 *
 * Run it with:  node ui/test/history.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-history-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/playHistory.ts', 'src/lib/upNext.ts', 'src/lib/resume.ts', 'src/player/historyOutbox.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

//? a virtual clock for the outbox's retry; fetch the fake deadwax's
let now = 0
let timers = []
globalThis.setTimeout = (fn, delay) => { const timer = { at: now + delay, fn, dead: false }; timers.push(timer); return timer }
globalThis.clearTimeout = (timer) => { if (timer) timer.dead = true }
const settle = () => new Promise((resolve) => setImmediate(resolve))
async function run(ms) {
  const until = now + ms
  for (;;) {
    await settle()
    const due = timers.filter((t) => !t.dead && t.at <= until).sort((a, b) => a.at - b.at)[0]
    if (!due) break
    now = due.at
    due.dead = true
    due.fn()
  }
  now = until
  await settle()
}
//? deadwax: every POST kept, answered as `answer` says - a status, or 'never' (held until let go)
const posts = []
let answer = () => 200
globalThis.fetch = (address, init = {}) => {
  const body = init.body ? JSON.parse(init.body) : null
  posts.push({ address: String(address), method: init.method ?? 'GET', starts: body?.starts ?? null, at: now })
  const status = answer()
  if (status === 'offline') return Promise.reject(new TypeError('Failed to fetch'))
  return Promise.resolve({ ok: status < 300, status, json: async () => (status < 300 ? { taken: body.starts.length, skipped: 0 } : { detail: 'no' }) })
}

const P = require(path.join(OUT, 'lib/playHistory.js'))
const U = require(path.join(OUT, 'lib/upNext.js'))
const R = require(path.join(OUT, 'lib/resume.js'))
const H = require(path.join(OUT, 'player/historyOutbox.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

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
const T = 1_800_000_000_000
const played = (id, at, queue = 'q-old', entry = 0, counted = false) => ({ at, counted, queue, entry, song: track(id) })

;(async () => {
  console.log('\nthe queue\'s id')
  {
    const ids = Array.from({ length: 2000 }, () => U.queueId())
    check('queueId: [A-Za-z0-9_-], 1 to 64 characters, and 2,000 of them all different',
      [ids.every((id) => /^[A-Za-z0-9_-]{1,64}$/.test(id)), new Set(ids).size, U.queueId(0).startsWith('0-')], [true, 2000, true])
    const a = U.startUpNext(album(30), null, true, seeded(7))
    const b = U.startUpNext(album(30), null, true, seeded(7), undefined, 'given')
    check('...made after the shuffle, never from its `random`: the same seed the same order, with an id given or made',
      [a.tracks.map((t) => t.id).join() === b.tracks.map((t) => t.id).join(), b.upNext.id, a.upNext.id !== b.upNext.id], [true, 'given', true])
    const q = U.startUpNext(album(5), 1)
    const edited = U.toppedUp(U.withShuffle(U.withNext(U.withRepeat(q, 'all'), [track('a')]), true, seeded(3)), 'all')
    const jumped = U.jumpedTo(edited, edited.upNext.marks[edited.index + 2].key, 'all')
    check('...every edit keeps it: Repeat, Play Next, Shuffle, the top-up, a jump', [edited.upNext.id === q.upNext.id, jumped.queue.upNext.id === q.upNext.id], [true, true])
  }

  console.log('\nthe pure rules')
  {
    const q = U.withNext(U.startUpNext(album(4).map((t) => ({ ...t, level: 'album' })), 1), [track('a')])
    const s = P.startOf(q.tracks[q.index], T, q)
    check('startOf: the listen\'s time, not counted, the queue\'s id and the entry\'s key, the song without its level',
      [s.at, s.counted, s.queue === q.upNext.id, s.entry, 'level' in s.song, s.song.title], [T, false, true, 1, false, 'song 2'])
    check('...a plain queue (none of Up Next\'s account): no queue, no entry', [P.startOf(track('1'), T, { tracks: [track('1')], index: 0 })].map((x) => [x.queue, x.entry]), [[null, null]])

    const page = [played('b', T - 100), played('a', T - 200, 'q', 1, true)]
    const own = [played('c', T), played('a', T - 200, 'q', 1, false), played('b', T - 100, 'q', 2, true)]
    const m = P.merged(page, own)
    check('merged: newest first, each start once - by its moment and song - `counted` ORed whichever said it',
      m.map((x) => [x.at - T, x.song.id, x.counted]), [[0, 'c', false], [-100, 'b', true], [-200, 'a', true]])
    check('...two songs begun the same millisecond: deadwax\'s order, the song id descending', P.merged([played('a', T), played('b', T)], []).map((x) => x.song.id), ['b', 'a'])

    const q2 = U.startUpNext(album(3), 2)
    const id = q2.upNext.id
    const plays = [played('3', T, id, 2), played('x', T - 100), played('x', T - 200), played('y', T - 300), played('x', T - 400), played('2', T - 500, id, 1)]
    check('pastRows: oldest first; a run of one song one row, keyed by its first start; the queue\'s own song playing (3) left out - its 2, before where listening began in it (no row of its), kept',
      P.pastRows(plays, q2).map((row) => [row.key, row.track.id]), [[`${T - 500}:2`, '2'], [`${T - 400}:x`, 'x'], [`${T - 300}:y`, 'y'], [`${T - 200}:x`, 'x']])
    check('...nothing playing: every start an older row', P.pastRows([played('1', T, id, 0)], { tracks: [], index: 0 }).length, 1)

    const first = { plays: [played('3', T), played('2', T - 100)], next: { at: T - 100, id: '2' }, shared: false }
    let held = P.withNewest(P.NOTHING_HELD, first)
    check('withNewest: the first page, and where the one before it is', [held.plays.length, held.before, held.asked], [2, { at: T - 100, id: '2' }, true])
    held = P.withOlder(held, { at: T - 100, id: '2' }, { plays: [played('1', T - 200)], next: null, shared: false })
    check('withOlder: added below - none before it', [held.plays.map((x) => x.song.id), held.before], [['3', '2', '1'], null])
    check('...a cursor no longer held (the newest started again since): what is held, unchanged', P.withOlder(held, { at: 5, id: 'z' }, first) === held, true)
    const later = P.withNewest(held, { plays: [played('4', T + 100), played('3', T)], next: { at: T, id: '3' }, shared: false })
    check('withNewest again: joined above, the older pages kept, still none before them', [later.plays.map((x) => x.song.id), later.before], [['4', '3', '2', '1'], null])
    const partly = P.withNewest({ plays: [played('3', T), played('2', T - 100)], before: { at: T - 100, id: '2' }, asked: true },
      { plays: [played('4', T + 100), played('3', T)], next: { at: T, id: '3' }, shared: false })
    check('...reaching what is held: joined, asking on from the oldest held', [partly.plays.map((x) => x.song.id), partly.before], [['4', '3', '2'], { at: T - 100, id: '2' }])
    const gap = P.withNewest(later, { plays: [played('9', T + 900), played('8', T + 800)], next: { at: T + 800, id: '8' }, shared: false })
    check('...more played elsewhere since than a page holds: started again from it, asking on from it - nothing between left out',
      [gap.plays.map((x) => x.song.id), gap.before], [['9', '8'], { at: T + 800, id: '8' }])

    //? (review) an EMPTY first page - nothing played yet, a first open after upgrading - then, the panel left open while
    //? the phone played more than a page: the newest page is all there is, and asking on from its `next` still works
    const empty = P.withNewest(P.NOTHING_HELD, { plays: [], next: null, shared: false })
    const full = { plays: Array.from({ length: 100 }, (_, i) => played(`f${i}`, T - i)), next: { at: T - 99, id: 'f99' }, shared: false }
    const afterEmpty = P.withNewest(empty, full)
    check('withNewest after an empty first page: a full page with more before it - the older pages can still be asked for',
      [empty.asked, afterEmpty.plays.length, afterEmpty.before], [true, 100, { at: T - 99, id: 'f99' }])
    check('...and one more page after it joins on', P.withOlder(afterEmpty, afterEmpty.before, { plays: [played('g', T - 200)], next: null, shared: false }).plays.length, 101)

    const kept = [played('a', T), played('b', T - 100)]
    check('countedIn: the start the play names marked; none named, the same list', [P.countedIn(kept, 'b', T - 100).map((x) => x.counted), P.countedIn(kept, 'b', T) === kept], [[false, true], true])
    check('afterFailure: unreachable, 5xx, 401, 408 and 429 tried again; another 4xx let go',
      [null, 500, 502, 503, 401, 408, 429, 400, 404, 422].map(P.afterFailure), ['retry', 'retry', 'retry', 'retry', 'retry', 'retry', 'retry', 'drop', 'drop', 'drop'])
    check('retryAfter: 30 s, doubling, never past 10 min', [1, 2, 3, 4, 5, 6, 7, 50, 0].map(P.retryAfter), [30_000, 60_000, 120_000, 240_000, 480_000, 600_000, 600_000, 600_000, 30_000])
  }

  console.log('\nwhat the queue draws, and nothing more (the review\'s probes)')
  {
    //? Repeat All: into the next round's first song, then Previous twice - the round after isn't drawn (Up Next sums it
    //? up in a line), so that start is an older row above, never claimed by the queue and drawn nowhere
    let q = U.toppedUp(U.withRepeat(U.startUpNext(album(3, 'ra'), 0), 'all'), 'all')
    let at = T
    const starts = [P.startOf(q.tracks[q.index], at, q)]
    for (let i = 0; i < 3; i++) {
      q = U.toppedUp({ ...q, index: U.onward(q) }, 'all')
      starts.push(P.startOf(q.tracks[q.index], (at += 1000), q))
    }
    const nextRound = starts[3]
    for (let i = 0; i < 2; i++) q = U.wentBack(q, U.backward(q, 0).index)
    const view = U.upNextView(q, 'all')
    const viewKeys = [...view.history, ...view.added, ...(view.list?.rows ?? [])].map((row) => row.key)
    check('Repeat All, the next round\'s first song, Previous twice: (2.1.18) moved back down - a row of Up Next\'s where it plays again, the queue\'s; nothing above',
      [q.index, viewKeys.includes(nextRound.entry), P.shownByQueue(nextRound, P.queueShows(q)), P.pastRows(P.merged([], starts), q).map((row) => row.track.id)],
      [1, true, true, []])

    //? a long album: played to its 156th song, then Previous back 105 - the list draws its next 100, and the songs begun
    //? past them are older rows above (with their own row once they are drawn again)
    let long = U.startUpNext(album(160, 'l'), 0)
    const longStarts = [P.startOf(long.tracks[0], T, long)]
    for (let i = 1; i <= 155; i++) {
      long = { ...long, index: U.onward(long) }
      longStarts.push(P.startOf(long.tracks[long.index], T + i * 1000, long))
    }
    for (let i = 0; i < 105; i++) long = U.wentBack(long, U.backward(long, 0).index)
    const shows = P.queueShows(long)
    const above = P.pastRows(P.merged([], longStarts), long).map((row) => row.track.id)
    check('a long album, Previous back past the list\'s 100: History\'s 50, the song playing and the next 100 the queue\'s - (2.1.18) and the 5 begun past them, moved back down, among "And 9 more"; none above',
      [long.index, U.upNextView(long, 'off').list.rows.length, U.upNextView(long, 'off').list.more, above.length, longStarts.filter((s) => P.shownByQueue(s, shows)).length],
      [50, U.UP_NEXT_DRAWN, 9, 0, 156])

    //? (2.1.18) another queue's older rows brought back: held - drawn as songs to come, never above - and above again once
    //? the queue has played on past History's 50
    const old = U.startUpNext(album(3, 'o'), 0)
    let oq = old
    const oldStarts = [P.startOf(oq.tracks[0], T, oq)]
    for (let i = 1; i < 3; i++) { oq = { ...oq, index: i }; oldStarts.push(P.startOf(oq.tracks[i], T + i * 1000, oq)) }
    let now = U.startUpNext(album(60, 'b'), 0)
    const nowStarts = [...oldStarts, P.startOf(now.tracks[0], T + 5000, now)]
    const rows = P.pastRows(P.merged([], nowStarts), now)
    const brought = U.broughtBack(now, P.rowsFrom(rows, rows[1].key).map((row) => ({ track: row.track, starts: row.starts, entry: row.entry })), 'off')
    now = brought.queue
    const drawn = (q, plays) => P.pastRows(P.merged([], plays), q).map((row) => row.track.id)
    check('another queue\'s o2 tapped: o2 plays, o3 and b1 to come; above, o1 alone - o2\'s and o3\'s starts held',
      [now.tracks.slice(0, 3).map((t) => t.id), drawn(now, nowStarts), [...P.queueShows(now).held]], [['o2', 'o3', 'b1'], ['o1'], [`${T + 1000}:o2`, `${T + 2000}:o3`]])
    nowStarts.push(P.startOf(now.tracks[0], T + 6000, now))
    for (let i = 1; i < 60; i++) { now = { ...now, index: i }; nowStarts.push(P.startOf(now.tracks[i], T + 6000 + i * 1000, now)) }
    const fallen = drawn(now, nowStarts)
    check('...played on 59 songs: o2 and o3\'s entries past History\'s 50 - their starts, old and new, above again, in the order they were begun',
      [fallen.slice(0, 6), [...P.queueShows(now).held]], [['o1', 'o2', 'o3', 'b1', 'o2', 'o3'], []])
  }

  console.log('\neach start drawn once - by property, over 1,500 runs of upnext.sim\'s moves')
  {
    let problems = []
    let starts = 0
    let fellAbove = 0
    let reloads = 0
    let rolledBack = 0, broughtBack = 0, heldSeen = 0, movedDownSeen = 0
    const unitStart = (state, place) => { while (place > 0 && state.marks[place].from === 'one') place--; return place }
    for (let runNo = 0; runNo < 1500 && problems.length < 5; runNo++) {
      const random = seeded(runNo + 1)
      //? (2.1.18) the seed's first draw let go: from a small seed it is always near 0 - every run had begun with Repeat off
      random()
      //? the list's rows Up Next draws: 8 for half the runs, so the rows past it - never drawn - come up often
      const LIMIT = runNo < 750 ? 8 : U.UP_NEXT_DRAWN
      const pick = (n) => Math.floor(random() * n)
      let repeat = ['off', 'all', 'one'][pick(3)]
      let queue = U.toppedUp(U.startUpNext(album(3 + pick(70), `r${runNo}-`), random() < 0.3 ? null : 0, random() < 0.3, random), repeat, random)
      let id = queue.upNext.id
      let clock = T
      const recorded = []
      const begin = () => { clock += 1000; recorded.push(P.startOf(queue.tracks[queue.index], clock, queue)) }
      begin()
      for (let step = 0; step < 120; step++) {
        const roll = random()
        let began = true
        let fresh = false
        if (roll < 0.40) {
          const to = U.onward(queue)
          if (to === null) { began = false; if (random() < 0.5) { queue = U.toppedUp(U.startUpNext(album(2 + pick(30), `n${runNo}-${step}-`), 0), repeat, random); fresh = true; began = true } } else queue = U.toppedUp({ ...queue, index: to }, repeat, random)
        } else if (roll < 0.50) {
          const back = U.backward(queue, random() < 0.5 ? 0 : 10)
          queue = back.kind === 'go' ? U.wentBack(queue, back.index) : queue
        } else if (roll < 0.58) {
          const view = U.upNextView(queue, repeat, LIMIT)
          const rows = [...view.added, ...(view.list?.rows ?? [])]
          const row = rows[pick(rows.length)]
          const jump = row && U.jumpedTo(queue, row.key, repeat)
          if (jump) queue = U.toppedUp({ ...jump.queue, index: jump.index }, repeat, random)
          else began = false
        } else if (roll < 0.61) {
          //? (2.1.18) History's row: a roll-back
          const rows = U.historyRows(queue)
          const row = rows[pick(rows.length)]
          const jump = row && U.jumpedTo(queue, row.key, repeat)
          if (jump) { queue = U.toppedUp({ ...jump.queue, index: jump.index }, repeat, random); rolledBack++ }
          else began = false
        } else if (roll < 0.64) {
          //? (2.1.18) an older row: it and every older row below it brought back, as Up Next's replayPast hands them
          const rows = P.pastRows(P.merged([], recorded), queue, LIMIT)
          const row = rows[pick(rows.length)]
          const back = row ? P.rowsFrom(rows, row.key).map((each) => ({ track: each.track, starts: each.starts, entry: each.entry })) : []
          //? (2.1.18 review) with the floor the rows were read against, as replayPast passes it
          const jump = U.broughtBack(queue, back, repeat, U.historyRows(queue)[0]?.key ?? queue.upNext.marks[queue.index].key)
          if (jump) { queue = U.toppedUp({ ...jump.queue, index: jump.index }, repeat, random); broughtBack++ }
          else began = false
        } else if (roll < 0.70) {
          queue = (random() < 0.5 ? U.withNext : U.withLast)(queue, [track(`p${runNo}-${step}`)]); began = false
        } else if (roll < 0.74) {
          const rows = U.upNextView(queue, repeat, LIMIT).list?.rows ?? []
          if (rows.length) queue = (random() < 0.5 ? U.withoutKey(queue, rows[pick(rows.length)].key) : U.movedKey(queue, rows[pick(rows.length)].key, pick(rows.length)))
          began = false
        } else if (roll < 0.80) {
          queue = U.toppedUp(U.withShuffle(queue, !queue.upNext.shuffle, random), repeat, random); began = false
        } else if (roll < 0.85) {
          repeat = ['off', 'all', 'one'][pick(3)]
          queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, random); began = false
        } else if (roll < 0.90) {
          //? a reload: the window saved and put back from the snapshot - the same queue, its id with it
          const saving = R.toSave(queue, 30)
          const back = R.fromSnapshot(saving.snapshot, queue.tracks.slice(saving.start, saving.start + saving.ids.length), saving.index, 'auto')
          if (back) { queue = U.toppedUp(U.withRepeat(back, repeat), repeat, random); reloads++ }
          began = false
        } else if (roll < 0.93) {
          queue = U.toppedUp(U.startUpNext(album(2 + pick(30), `m${runNo}-${step}-`), pick(2)), repeat, random); fresh = true
        } else {
          //? Previous early - the song again - or Play on one that ended: a new listen of the same entry
        }
        if (fresh) id = queue.upNext.id
        else if (queue.upNext.id !== id) problems.push(`run ${runNo} step ${step}: the queue's id changed without a new queue`)
        if (began) begin()
        //? every start: the queue's (its row drawn) or exactly one older row's - never both, never neither. Drawn is the
        //? view's own rows: History's, the song playing's, the songs added and the list's first LIMIT - never a later round
        //? or a row past the limit (the review: once counted as drawn by being after the song playing)
        const state = queue.upNext
        const shows = P.queueShows(queue, LIMIT)
        const view = U.upNextView(queue, repeat, LIMIT)
        const viewKeys = new Set([...view.history, ...view.added, ...(view.list?.rows ?? [])].map((row) => row.key))
        const playingStart = unitStart(state, queue.index)
        const drawnByQueue = (place) => place >= 0 && (unitStart(state, place) === playingStart || viewKeys.has(state.marks[unitStart(state, place)].key))
        //? (2.1.18) moved back down into Up Next: after the song playing, at or before the furthest song played - drawn as a
        //? row, or past the rows drawn, counted in "And N more"
        const reachAt = state.marks.findIndex((mark) => mark.key === state.reached)
        const movedDown = (place) => place > queue.index && reachAt > queue.index && unitStart(state, place) <= reachAt
        //? (2.1.18) the entry holding a start brought back with an older row - the song and the moment its mark carries
        const holderOf = (s) => state.marks.findIndex((mark, at) => (mark.starts ?? []).includes(s.at) && queue.tracks[at].id === s.song.id)
        const past = P.pastRows(P.merged([], recorded), queue, LIMIT)
        const pastKeys = new Set(past.map((row) => row.key))
        const ordered = P.merged([], recorded)
        //? which past row stands for each start not the queue's: its run's first, walking oldest first
        const runOf = new Map()
        let current = null
        let lastSong = null
        for (let i = ordered.length - 1; i >= 0; i--) {
          const s = ordered[i]
          if (P.heldByQueue(s, shows)) continue
          if (s.song.id !== lastSong) { current = P.playedKey(s); lastSong = s.song.id }
          runOf.set(P.playedKey(s), current)
        }
        for (const s of recorded) {
          starts++
          const key = P.playedKey(s)
          const place = s.queue === state.id ? state.marks.findIndex((mark) => mark.key === s.entry) : -1
          const holder = holderOf(s)
          if (P.heldByQueue(s, shows)) {
            const own = P.shownByQueue(s, shows)
            const at = own ? place : holder
            if (!own) heldSeen++
            if (!drawnByQueue(at)) {
              if (movedDown(at)) movedDownSeen++
              else problems.push(`run ${runNo} step ${step}: ${key} the queue's, but no row of it draws it, nor is it to come`)
            }
            if (runOf.has(key)) problems.push(`run ${runNo} step ${step}: ${key} drawn twice`)
          } else {
            fellAbove++
            if (!pastKeys.has(runOf.get(key))) problems.push(`run ${runNo} step ${step}: ${key} drawn nowhere`)
            if (s.queue === state.id && (drawnByQueue(place) || movedDown(place))) problems.push(`run ${runNo} step ${step}: ${key} above, and its entry a row of the queue's too`)
            if (holder >= 0 && (drawnByQueue(holder) || movedDown(holder))) problems.push(`run ${runNo} step ${step}: ${key} above, and held by a row of the queue's too`)
          }
        }
      }
    }
    check(`every start drawn once, at every step, judged by the view's own rows (${starts.toLocaleString('en-US')} looked at, ${fellAbove.toLocaleString('en-US')} of them above History; ${reloads} reloads)`, problems, [])
    check(`...(2.1.18) History taps rolled back (${rolledBack}), older rows brought back (${broughtBack}); starts held by them (${heldSeen.toLocaleString('en-US')}) and moved down past the rows drawn (${movedDownSeen.toLocaleString('en-US')})`,
      [rolledBack > 3000 || rolledBack, broughtBack > 3000 || broughtBack, heldSeen > 10000 || heldSeen, movedDownSeen > 1000 || movedDownSeen], [true, true, true, true])
  }

  console.log('\nthe outbox: this page\'s starts, sent to deadwax')
  {
    const sent = () => posts.map((post) => post.starts.map((s) => `${s.song.id}${s.counted ? '+' : ''}`).join(','))
    H.forgetStarts(); posts.length = 0; answer = () => 200
    H.record(played('1', T, 'q', 0))
    await run(0)
    check('a start: kept, and sent at once - POST /deadwax/me/history', [H.ownStarts().map((s) => s.song.id), posts.map((p) => [p.address, p.method]), sent(), H.pendingStarts().length],
      [['1'], [['/deadwax/me/history', 'POST']], ['1'], 0])

    //? one at a time: the next waits for the answer
    H.forgetStarts(); posts.length = 0
    let release = null
    answer = () => 'held'
    const realFetch = globalThis.fetch
    globalThis.fetch = (address, init) => {
      posts.push({ address, method: init.method, starts: JSON.parse(init.body).starts })
      return new Promise((resolve) => { release = () => resolve({ ok: true, status: 200, json: async () => ({}) }) })
    }
    H.record(played('1', T))
    H.record(played('2', T + 1))
    H.record(played('3', T + 2))
    await run(0)
    check('one POST at a time: the first alone, the two after it waiting', [sent(), H.pendingStarts().length], [['1'], 3])
    release(); await run(0)
    check('...answered: the two waiting in one', [sent(), H.pendingStarts().length], [['1', '2,3'], 2])
    H.counted('3', T + 2)
    release(); await run(0)
    check('...3 counted while on its way: sent again, counted (deadwax ORs it in)', [sent(), H.pendingStarts().length], [['1', '2,3', '3+'], 1])
    release(); await run(0)
    check('...and nothing left', H.pendingStarts().length, 0)
    globalThis.fetch = realFetch

    //? at most 500 waiting (the oldest let go past it), so at most 500 a POST
    H.forgetStarts(); posts.length = 0
    answer = () => 'offline'
    for (let i = 0; i < 620; i++) H.record(played(`s${i}`, T + i))
    await run(0)
    const waiting = H.pendingStarts().length
    answer = () => 200
    H.record(played('last', T + 999))
    await run(0)
    const last = posts[posts.length - 1].starts
    check('620 started while unreachable: 500 kept waiting, the oldest let go; one more - one POST of the newest 500, the page keeping its newest 500',
      [waiting, last.length, last[0].song.id, last[499].song.id, H.pendingStarts().length, H.ownStarts().length, H.ownStarts()[0].song.id], [500, 500, 's121', 'last', 0, 500, 'last'])

    //? unreachable or a 5xx: again 30 s on, and at the next start
    H.forgetStarts(); posts.length = 0
    answer = () => 503
    H.record(played('1', T))
    await run(0)
    await run(29_000)
    check('a 503: held, not asked again before 30 s', [posts.length, H.pendingStarts().length], [1, 1])
    answer = () => 200
    await run(1_000)
    check('...30 s on: sent again, and taken', [posts.length, H.pendingStarts().length], [2, 0])
    answer = () => 'offline'
    H.record(played('2', T + 1))
    await run(0)
    answer = () => 200
    H.record(played('3', T + 2))
    await run(0)
    check('deadwax unreachable, then the next start: both sent with it, at once', [sent().slice(-1), H.pendingStarts().length], [['2,3'], 0])

    //? (review) a deadwax answering 503 for an hour (no database): the waits double from 30 s to 10 min, never the
    //? same starts every 30 s for ever; a send taken starts them again from 30 s
    H.forgetStarts(); posts.length = 0
    answer = () => 503
    H.record(played('1', T))
    await run(60 * 60_000)
    const gaps = posts.slice(1).map((post, i) => (post.at - posts[i].at) / 1000)
    check('an hour of 503s: tried again after 30 s, 1, 2, 4 and 8 min, then every 10 min', gaps, [30, 60, 120, 240, 480, 600, 600, 600, 600])
    answer = () => 200
    H.record(played('2', T + 1))
    await run(0)
    answer = () => 503
    H.record(played('3', T + 2))
    await run(0)
    const from = posts.length
    await run(30_000)
    check('...taken at the next start, then a 503 again: 30 s, not 10 min', [sent().slice(-3, -1), posts.length - from], [['1,2', '3'], 1])
    answer = () => 429
    H.forgetStarts(); posts.length = 0
    H.record(played('1', T))
    await run(30_000)
    check('a 429 (or a 408): held and tried again, not let go', [posts.length, H.pendingStarts().length], [2, 1])

    //? signed out: held, no timer - the next start sends them
    H.forgetStarts(); posts.length = 0
    answer = () => 401
    H.record(played('1', T))
    await run(120_000)
    check('a 401: held, and not asked again by a timer - each ask would bring the sign-in back', [posts.length, H.pendingStarts().length], [1, 1])
    answer = () => 200
    H.record(played('2', T + 1))
    await run(0)
    check('...the same person carrying on: the next start sends them both', [sent().slice(-1), H.pendingStarts().length], [['1,2'], 0])

    //? another 4xx: let go
    H.forgetStarts(); posts.length = 0
    answer = () => 422
    const warn = console.warn
    console.warn = () => {}
    H.record(played('1', T))
    await run(60_000)
    console.warn = warn
    check('a 422: let go - never taken - and kept on this page, drawn', [posts.length, H.pendingStarts().length, H.ownStarts().length], [1, 0, 1])

    //? counted while waiting, and after it was taken
    H.forgetStarts(); posts.length = 0
    answer = () => 503
    H.record(played('1', T))
    await run(0)
    H.counted('1', T)
    H.counted('1', T + 5)
    answer = () => 200
    await run(30_000)
    check('counted while waiting: sent counted; another time names no start', [sent(), H.ownStarts()[0].counted], [['1', '1+'], true])
    H.record(played('2', T + 10))
    await run(0)
    const before = posts.length
    H.counted('2', T + 10)
    await run(60_000)
    check('counted once taken: marked on the page, nothing sent - deadwax\'s scrobble route marks its own', [H.ownStarts()[0].counted, posts.length - before], [true, 0])
    let heard = 0
    const stop = H.onStarts(() => heard++)
    H.counted('2', T + 10)
    H.record(played('4', T + 20))
    stop()
    H.record(played('5', T + 30))
    check('...told of each change - none for a count already marked - until it stops listening', heard, 1)

    //? a continuation
    H.forgetStarts(); posts.length = 0
    const q = U.startUpNext(album(4), 2)
    H.continuing(q)
    H.record(P.startOf(q.tracks[2], T, q))
    H.record(P.startOf(q.tracks[2], T + 1, q))
    check('a queue of deadwax\'s put back mid-song: its song carrying on no start; a start after it (the song again) kept', H.ownStarts().map((s) => s.at - T), [1])
    H.continuing(q)
    H.record(P.startOf(q.tracks[3], T + 2, { ...q, index: 3 }))
    H.record(P.startOf(q.tracks[2], T + 3, q))
    check('...another song first: kept, and the mark gone with it', H.ownStarts().map((s) => s.at - T), [3, 2, 1])
    H.continuing(q)
    H.continuing(null)
    H.record(P.startOf(q.tracks[2], T + 4, q))
    check('...another queue put back after it (at 0 s, or another app\'s): the mark gone', H.ownStarts().length, 4)
    await run(0)
    H.forgetStarts()
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
