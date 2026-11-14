#!/usr/bin/env node
/**
 * The iPhone app's play history rules, as the web app's own TypeScript answers them (app 0.8, notes/ios.md "Play
 * history on the phone"): ui/src/lib/playHistory.ts compiled with the repo's TypeScript - with lib/upNext.ts,
 * lib/playQueue.ts and lib/resume.ts, which it stands on - and run over every case below. Written to
 *
 *   ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/history/vectors.json
 *
 * which DeadwaxCoreTests' HistoryVectorTests replays against DeadwaxCore's PlayHistory.swift - the port - so a rule
 * changed on the web and not in the app (or the other way about) fails a test:
 *
 *   - Up Next's words for them, read from app/UpNext.tsx (Loading earlier songs, the failure's, Try again, a played
 *     row's name and what its tap says);
 *   - the numbers (a page, a POST's most, the starts kept, the retry's), a start's key;
 *   - merged: seeded pools of starts, ties of moment and song among them, ids that sort differently by UTF-16 unit
 *     than by Unicode scalar, `counted` said by either side;
 *   - withNewest and withOlder: history.sim.cjs's own cases, then seeded helds and pages;
 *   - countedIn, afterFailure, retryAfter, over their ranges;
 *   - EACH START DRAWN ONCE: 300 seeded runs of 50 moves - songs ending, Previous, a tap on Up Next's rows, on
 *     History's (2.1.18: a roll-back) and on an older row's (2.1.18: broughtBack with the rows from it down - rowsFrom
 *     - and the floor, as Up Next's replayPast hands them), Play Next and Last, Shuffle, Repeat, a reload's round trip
 *     through the snapshot, another queue - a start recorded at every song begun; after every step a line of what
 *     queueShows (its keys and, 2.1.18, the starts it holds) and pastRows (each row's starts and entry) answer
 *     (limits 8 and 100 by turns), each run's lines as one FNV-1a digest, run 0's lines in full. The Swift test runs the same moves from the same Park-Miller
 *     numbers through DeadwaxCore's own Up Next (held to the web's by export-traces.cjs) and must make every line.
 *     Each line also says what an older row's tap hands the roll-back (review of the port: PlayHistory.brought) - the
 *     rows from the middle row tapped, each song at the level of a setting taken by turns, and the floor - made as
 *     app/UpNext.tsx's replayPast makes it, from the web's own parts;
 *   - brought: the same over rows given whole, a song's own level among them (kept under Off, as queued() keeps it),
 *     a key no row has, a queue with no History, a plain queue. replayPast's text is hashed in (`replayPast`): a change
 *     to it fails the check, to be ported to PlayHistory.brought.
 *
 * Every queue here is given its id (`q<run>-<n>`), so nothing calls queueId()'s clock or random - the export stops if
 * anything does.
 *
 *   node ios/scripts/export-history.cjs           writes the fixture
 *   node ios/scripts/export-history.cjs --check   fails when the fixture isn't what the TypeScript says now
 *                                                 (ui/test/ioshistory.sim.cjs runs this in CI)
 *
 * Needs ui/node_modules (npm install in ui/) and a writable TMPDIR.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/history/vectors.json')
const CHECK = process.argv.includes('--check')

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-ios-history-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/playHistory.ts', 'src/lib/upNext.ts', 'src/lib/playQueue.ts', 'src/lib/resume.ts', 'src/lib/loudness.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

const P = require(path.join(OUT, 'lib/playHistory.js'))
const U = require(path.join(OUT, 'lib/upNext.js'))
const R = require(path.join(OUT, 'lib/resume.js'))
const L = require(path.join(OUT, 'lib/loudness.js'))
fs.rmSync(OUT, { recursive: true, force: true })

//? a queue's id made by the clock and random here would differ every run: every queue is given one, and this says so
const realCrypto = Object.getOwnPropertyDescriptor(globalThis, 'crypto')
Object.defineProperty(globalThis, 'crypto', {
  configurable: true,
  value: { getRandomValues: () => { throw new Error('a queue was given no id - queueId() would make a different one every run') } },
})

/* ===== Park-Miller, as the sims' seeded() and the Swift tests' ParkMiller ===== */

const M = 2147483647
class ParkMiller {
  constructor(seed) {
    if (!(seed >= 1 && seed < M)) throw new Error(`Park-Miller needs a seed in 1...2147483646, not ${seed}`)
    this.s = seed
  }
  next() { this.s = (this.s * 16807) % M; return (this.s - 1) / 2147483646 }
}
const seeded = (seed) => { const generator = new ParkMiller(seed); return () => generator.next() }

/** export-traces.cjs's fnv1a: 32-bit FNV-1a over a text's UTF-16 units, as eight hex digits. */
function fnv1a(text) {
  let hash = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash.toString(16).padStart(8, '0')
}

/* ===== songs and starts ===== */

/** upnext.sim.cjs's track() - the Swift tests' simTrack(id): every start's song here is one, named by its id alone. */
const track = (id) => ({
  id, title: `song ${id}`, artist: 'Massive Attack', album: 'Mezzanine', albumId: 'mez', coverArt: null,
  duration: 200, contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2,
})
const album = (n, prefix = '') => Array.from({ length: n }, (_, i) => track(`${prefix}${i + 1}`))
const T = 1_800_000_000_000

/** A start as the fixture holds it: [at, counted, queue, entry, song id]. */
const row = (played) => [played.at, played.counted, played.queue, played.entry, played.song.id]
const start = ([at, counted, queue, entry, id]) => ({ at, counted, queue, entry, song: track(id) })
const held = (h) => ({ plays: h.plays.map(row), before: h.before, asked: h.asked })
const page = (p) => ({ plays: p.plays.map(row), next: p.next, shared: p.shared })

/** Song ids whose order by UTF-16 unit isn't their order by scalar (an astral letter against one just below it), ties
 *  of one moment among them. */
const IDS = ['a', 'b', 'B', '10', '9', 'z', '\u00e9', 'e\u0301', '\uffef', '\u{1F3B5}', 'song-1', 'song-10']

/* ===== the rules, case by case ===== */

function mergedCases() {
  const random = seeded(4242)
  const pick = (n) => Math.floor(random() * n)
  const cases = []
  for (let n = 0; n < 160; n++) {
    const moments = 1 + pick(6)
    const pool = Array.from({ length: pick(14) }, () =>
      start([T + pick(moments) * 1000, random() < 0.3, random() < 0.2 ? null : `q${pick(3)}`, random() < 0.2 ? null : pick(8), IDS[pick(IDS.length)]]))
    const pages = pool.filter(() => random() < 0.6)
    const own = pool.filter(() => random() < 0.6)
    cases.push({ pages: pages.map(row), own: own.map(row), merged: P.merged(pages, own).map(row) })
  }
  return cases
}

function heldCases() {
  const played = (id, at, queue = 'q-old', entry = 0, counted = false) => ({ at, counted, queue, entry, song: track(id) })
  const steps = []
  const newest = (h, p) => { const out = P.withNewest(h, p); steps.push({ op: 'newest', held: held(h), page: page(p), out: held(out) }); return out }
  const older = (h, from, p) => { const out = P.withOlder(h, from, p); steps.push({ op: 'older', held: held(h), from, page: page(p), out: held(out) }); return out }

  //? history.sim.cjs's own cases, in its order
  const first = { plays: [played('3', T), played('2', T - 100)], next: { at: T - 100, id: '2' }, shared: false }
  let h = newest(P.NOTHING_HELD, first)
  h = older(h, { at: T - 100, id: '2' }, { plays: [played('1', T - 200)], next: null, shared: false })
  older(h, { at: 5, id: 'z' }, first)
  const later = newest(h, { plays: [played('4', T + 100), played('3', T)], next: { at: T, id: '3' }, shared: false })
  newest({ plays: [played('3', T), played('2', T - 100)], before: { at: T - 100, id: '2' }, asked: true },
    { plays: [played('4', T + 100), played('3', T)], next: { at: T, id: '3' }, shared: false })
  newest(later, { plays: [played('9', T + 900), played('8', T + 800)], next: { at: T + 800, id: '8' }, shared: false })
  const empty = newest(P.NOTHING_HELD, { plays: [], next: null, shared: false })
  const full = { plays: Array.from({ length: 100 }, (_, i) => played(`f${i}`, T - i)), next: { at: T - 99, id: 'f99' }, shared: false }
  const afterEmpty = newest(empty, full)
  older(afterEmpty, afterEmpty.before, { plays: [played('g', T - 200)], next: null, shared: false })

  //? seeded: helds and pages over a few moments and ids, so a page's oldest ties, passes or falls short of the newest held
  const random = seeded(777)
  const pick = (n) => Math.floor(random() * n)
  const some = (count) => P.merged(Array.from({ length: count }, () =>
    start([T + pick(8) * 1000, random() < 0.3, 'q', pick(4), IDS[pick(IDS.length)]])), [])
  const cursorOf = (list) => (list.length ? { at: list[list.length - 1].at, id: list[list.length - 1].song.id } : null)
  for (let n = 0; n < 200; n++) {
    const plays = some(pick(7))
    const h = { plays, before: random() < 0.6 ? cursorOf(plays) : random() < 0.5 ? null : { at: T + pick(8) * 1000, id: IDS[pick(IDS.length)] }, asked: random() < 0.85 }
    const pagePlays = some(pick(7))
    const p = { plays: pagePlays, next: random() < 0.6 ? cursorOf(pagePlays) : null, shared: random() < 0.2 }
    if (random() < 0.5) newest(h, p)
    else older(h, random() < 0.7 && h.before ? { ...h.before } : { at: T + pick(8) * 1000, id: IDS[pick(IDS.length)] }, p)
  }
  return steps
}

function countedCases() {
  const random = seeded(99)
  const pick = (n) => Math.floor(random() * n)
  const cases = []
  for (let n = 0; n < 80; n++) {
    //? ids 9, z, the two spellings of e-acute, and B: one the same song by Swift's `==`, another by JavaScript's
    const own = Array.from({ length: pick(6) }, () => start([T + pick(4) * 1000, random() < 0.4, 'q', pick(3), IDS[4 + pick(4)]]))
    const songId = IDS[[4, 5, 6, 7, 2][pick(5)]]
    const at = T + pick(5) * 1000
    const out = P.countedIn(own, songId, at)
    cases.push({ own: own.map(row), songId, at, out: out.map(row), same: out === own })
  }
  return cases
}

/* ===== what an older row's tap hands the roll-back (app/UpNext.tsx replayPast) ===== */

//? replayPast is a component's inline handler, so nothing can call it: it is read from UpNext.tsx exactly as it is
//? written - the export stops when it isn't - hashed into the fixture, and made below from the very parts it calls
const REPLAY_PAST = (() => {
  const text = fs.readFileSync(path.join(UI, 'src/app/UpNext.tsx'), 'utf8')
  const found = [...text.matchAll(/\n {2}const replayPast = \(row: PastRow\) => \{\n[\s\S]*?\n {2}\}\n/g)]
  if (found.length !== 1) throw new Error(`ui/src/app/UpNext.tsx has ${found.length} replayPast (1 wanted): update the exporter, and PlayHistory.brought with it`)
  const body = [
    '    tapped.current = rolledTo(row, { entry: row.entry })',
    '    const floor = view.history[0]?.key ?? player.queue.upNext?.marks[player.queue.index]?.key',
    '    const back = rowsFrom(past, row.key)',
    "    const tracks = queued(back.map((each) => each.track), 'songs')",
    '    player.jumpTo(back.map((each, i) => ({ track: tracks[i]!, starts: each.starts, entry: each.entry })), floor)',
  ].join('\n')
  if (!found[0][0].includes(body)) throw new Error('app/UpNext.tsx replayPast changed: port it to PlayHistory.brought, then update the exporter')
  return require('crypto').createHash('sha256').update(found[0][0]).digest('hex')
})()
const SETTINGS = ['auto', 'song', 'album', 'off']

/** replayPast's hand-over, from the web's own parts: `past` its pastRows (the default limit, as Up Next draws them),
 *  view.history historyRows (upNextView's), queued() levelled at `setting` (queued reads it from storage). */
function replayed(plays, queue, key, setting) {
  const past = P.pastRows(plays, queue)
  const floor = U.historyRows(queue)[0]?.key ?? queue.upNext?.marks[queue.index]?.key
  const back = P.rowsFrom(past, key)
  const tracks = L.levelled(back.map((each) => each.track), setting, 'songs')
  return { rows: back.map((each, i) => ({ track: tracks[i], starts: each.starts, entry: each.entry })), floor }
}
const handedLine = (handed) => `${handed.floor ?? '-'}>` +
  handed.rows.map((r) => `${r.track.id}:${r.track.level ?? '-'}/${r.starts.join('.')}/${r.entry ?? '-'}`).join(',')

/** Rows given whole - [key, song id, level or null, starts, entry or null] - through replayPast's hand-over: its
 *  floor read from the queue, the rows from the key. pastRows isn't asked: rowsFrom and the levels are. */
function broughtCases() {
  const cases = []
  const level = (t, l) => (l ? { ...t, level: l } : t)
  const given = [
    ['k3', '3', null, [T + 3], 2], ['k2', '2', 'album', [T + 2, T + 1], null], ['k1', 'x', 'track', [T], null], ['k0', '1', null, [T - 1], 0],
  ]
  const past = given.map(([key, id, l, starts, entry]) => ({ key, track: level(track(id), l), starts, entry }))
  const queues = {
    history: { ...U.startUpNext(album(4), 0, false, undefined, undefined, 'qb-1'), index: 2 },
    none: U.startUpNext(album(4), 1, false, undefined, undefined, 'qb-2'),
    plain: { tracks: album(2), index: 1 },
  }
  for (const [name, queue] of Object.entries(queues)) {
    for (const setting of SETTINGS) {
      for (const key of ['k3', 'k1', 'k0', 'nope']) {
        const floor = U.historyRows(queue)[0]?.key ?? queue.upNext?.marks[queue.index]?.key
        const back = P.rowsFrom(past, key)
        const tracks = L.levelled(back.map((each) => each.track), setting, 'songs')
        const rows = back.map((each, i) => ({ track: tracks[i], starts: each.starts, entry: each.entry }))
        cases.push({ queue: name, setting, key, out: handedLine({ rows, floor }) })
      }
    }
  }
  return { past: given, queues: Object.keys(queues), cases }
}

/* ===== each start drawn once: the property, line by line ===== */

const RUNS = 300
const STEPS = 50

function propertyRun(run) {
  const random = seeded((run * 1_000_003) % 2147483646 + 1)
  random()
  const pick = (n) => Math.floor(random() * n)
  const limit = run % 2 === 0 ? 8 : U.UP_NEXT_DRAWN
  let repeat = U.REPEATS[pick(3)]
  let made = 0
  const fresh = (songs, start, shuffle) => U.startUpNext(songs, start, shuffle, random, undefined, `q${run}-${made++}`)
  let queue = U.toppedUp(fresh(album(2 + pick(40), `r${run}-`), random() < 0.3 ? null : 0, random() < 0.3), repeat, random)
  const at = (q, index) => ({ ...q, index })
  let clock = T
  const recorded = []
  const begin = () => { clock += 1000; recorded.push(P.startOf(queue.tracks[queue.index], clock, queue)) }
  const jumpTo = (q, key) => {
    const jump = U.jumpedTo(q, key, repeat)
    if (!jump) return false
    queue = U.toppedUp(at(jump.queue, jump.index), repeat, random)
    return true
  }
  begin()
  const lines = []
  for (let step = 0; step < STEPS; step++) {
    const op = pick(13)
    let began = false
    if (op <= 2) {
      const to = U.onward(queue)
      if (to !== null) { queue = U.toppedUp(at(queue, to), repeat, random); began = true }
    } else if (op === 3) {
      const back = U.backward(queue, 0)
      if (back.kind === 'go') { queue = U.wentBack(queue, back.index); began = true }
    } else if (op === 4) {
      const view = U.upNextView(queue, repeat, limit)
      const rows = [...view.added, ...(view.list?.rows ?? [])]
      if (rows.length) began = jumpTo(queue, rows[pick(rows.length)].key)
    } else if (op === 5) {
      const rows = U.historyRows(queue)
      if (rows.length) began = jumpTo(queue, rows[pick(rows.length)].key)
    } else if (op === 6) {
      //? (2.1.18) an older row tapped: it and every older row below it brought back (rowsFrom), with the floor the rows
      //? were read against - History's first row, else the song playing's - as Up Next's replayPast hands them
      const rows = P.pastRows(P.merged([], recorded), queue, limit)
      if (rows.length) {
        const back = P.rowsFrom(rows, rows[pick(rows.length)].key).map((row) => ({ track: row.track, starts: row.starts, entry: row.entry }))
        const jump = U.broughtBack(queue, back, repeat, U.historyRows(queue)[0]?.key ?? queue.upNext.marks[queue.index].key)
        if (jump) { queue = U.toppedUp({ ...jump.queue, index: jump.index }, repeat, random); began = true }
      }
    } else if (op === 7) {
      queue = (random() < 0.5 ? U.withNext : U.withLast)(queue, [track(`p${run}-${step}`)])
    } else if (op === 8) {
      queue = U.toppedUp(U.withShuffle(queue, !queue.upNext.shuffle, random), repeat, random)
    } else if (op === 9) {
      repeat = U.REPEATS[pick(3)]
      queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, random)
    } else if (op === 10) {
      //? a reload: the window saved and read back from the snapshot - the same queue, its id with it
      const saving = R.toSave(queue, 30)
      const back = R.fromSnapshot(saving.snapshot, queue.tracks.slice(saving.start, saving.start + saving.ids.length), saving.index, 'auto')
      if (!back) throw new Error(`run ${run} step ${step}: a snapshot that doesn't read back`)
      queue = U.toppedUp(U.withRepeat(back, repeat), repeat, random)
    } else if (op === 11) {
      queue = U.toppedUp(fresh(album(2 + pick(20), `m${run}-${step}-`), pick(2), random() < 0.3), repeat, random)
      began = true
    } else {
      //? Previous early - the song again - or Play on one that ended: a new listen of the same entry
      began = true
    }
    if (began) begin()
    //? the pages hold every third start, counted; this phone's own every start, not
    const pages = recorded.filter((_, i) => i % 3 === 0).map((s) => ({ ...s, counted: true }))
    const plays = P.merged(pages, recorded)
    const shows = P.queueShows(queue, limit)
    const rows = P.pastRows(plays, queue, limit)
    //? (review of the port) the middle row of Up Next's as drawn tapped: what replayPast hands the roll-back, at a
    //? setting by turns - nothing drawn
    const drawn = P.pastRows(plays, queue)
    const tapped = drawn[Math.floor(drawn.length / 2)]
    const handed = tapped ? handedLine(replayed(plays, queue, tapped.key, SETTINGS[step % 4])) : '-'
    //? (2.1.18) the starts the queue holds (sorted: a Set's order is its own), each row's starts and its entry
    lines.push([
      `${step}:${op}`, queue.index, shows.id ?? '-', [...shows.keys].sort((a, b) => a - b).join(','), [...shows.held].sort().join(','),
      rows.map((r) => `${r.key}=${r.track.id}/${r.starts.join('.')}/${r.entry ?? '-'}`).join(','), plays.filter((s) => s.counted).length, plays.length,
      handed,
    ].join('|'))
  }
  return { lines, starts: recorded.length }
}

function property() {
  const digests = []
  let starts = 0
  let sample = null
  for (let run = 0; run < RUNS; run++) {
    const { lines, starts: begun } = propertyRun(run)
    if (run === 0) sample = lines
    starts += begun
    digests.push(fnv1a(lines.join('\n')))
  }
  return { runs: RUNS, steps: STEPS, starts, digests, sample }
}

/* ===== Up Next's words for them (app/UpNext.tsx), read from its source ===== */

/** A piece of UpNext.tsx, found exactly as often as `count` - or the export stops, naming it. */
function piece(pattern, what, count = 1) {
  const text = fs.readFileSync(path.join(UI, 'src/app/UpNext.tsx'), 'utf8')
  const found = [...text.matchAll(pattern)]
  if (found.length !== count) throw new Error(`ui/src/app/UpNext.tsx has ${found.length} of ${what} (${count} wanted): update the exporter, and UpNextWords with it`)
  return found[0][1]
}

function words() {
  return {
    //? the heading the sheet no longer draws (2.1.15): the list's region is named by it
    history: piece(/\nexport const HISTORY = '([^']+)'\n/g, 'HISTORY'),
    loadingEarlier: piece(/\nexport const LOADING_EARLIER = '([^']+)'\n/g, 'LOADING_EARLIER'),
    earlierFailed: piece(/\nexport const EARLIER_FAILED = "([^"]+)"\n/g, 'EARLIER_FAILED'),
    tryAgain: piece(/onClick=\{history\?\.retry\}>\n\s*([^<\n]+?)\n/g, 'the older rows\' Try again'),
    //? an older row's name and a History row's, and what is said once its tap took - the title before and after
    //? (", play now" is a list row's: the two rows above the song playing are History's and an older row's; 2.1.18,
    //? both roll back, their words said by the one rolledTo)
    playAgain: piece(/aria-label=\{`\$\{row\.track\.title\}(, play again)`\}/g, 'a played row\'s name', 2),
    playing: piece(/said: `([^`$]*)\$\{row\.track\.title\}`/g, 'a played row\'s words', 1),
  }
}

/* ===== writing ===== */

function vectors() {
  return {
    madeBy: 'ios/scripts/export-history.cjs - never edit by hand',
    words: words(),
    constants: {
      page: P.HISTORY_PAGE, postMax: P.HISTORY_POST_MAX, ownKept: P.OWN_KEPT, retryMs: P.RETRY_MS, retryMaxMs: P.RETRY_MAX_MS,
      drawn: U.UP_NEXT_DRAWN, historyBack: U.HISTORY_BACK,
    },
    keys: [[T, 'a'], [0, '1'], [T + 999, 'e\u0301'], [T, '\u{1F3B5}']].map(([at, id]) => ({ at, id, key: P.playedKey({ at, song: track(id) }) })),
    merged: mergedCases(),
    held: heldCases(),
    counted: countedCases(),
    afterFailure: [null, 0, 100, 200, 204, 301, 399, 400, 401, 403, 404, 408, 409, 413, 422, 429, 499, 500, 502, 503, 599]
      .map((status) => ({ status, out: P.afterFailure(status) })),
    retryAfter: Array.from({ length: 28 }, (_, i) => i - 2).map((failures) => ({ failures, ms: P.retryAfter(failures) })),
    replayPast: REPLAY_PAST,
    brought: broughtCases(),
    property: property(),
  }
}

/** JSON with every character outside ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[\u0080-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (realCrypto) Object.defineProperty(globalThis, 'crypto', realCrypto)
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-history.cjs, then port the change to DeadwaxCore's PlayHistory.swift and see HistoryVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
