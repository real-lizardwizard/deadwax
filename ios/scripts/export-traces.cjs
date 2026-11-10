#!/usr/bin/env node
/**
 * The iPhone app's Up Next is a port of the web app's (ui/src/lib/upNext.ts and the queue parts of
 * ui/src/lib/playQueue.ts) to Swift (ios/DeadwaxKit/Sources/DeadwaxCore/UpNext*.swift). This records what the
 * TypeScript does - the same inputs, the same random numbers, the state after every step - so the Swift tests can
 * replay it and hold the port to it (the plan's risk R12: a queue saved on one must come back the same on the
 * other). Three files, in ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/upnext/:
 *
 *   traces.json     150 seeded runs of 40 steps each: every edit, top-up, move and query the player makes, chosen
 *                   by one generator and fed another's numbers, one trace a line.
 *   scenarios.json  each check of ui/test/upnext.sim.cjs's rules (lines 133-465), built as the sim builds it, plus
 *                   cases the sim doesn't reach (Previous back across another song's copies, Repeat One on a song
 *                   added, a list of one song twice under Shuffle and Repeat All, Shuffle before where the list
 *                   began, a queue with none of the list at or before the song playing), the words, the constants.
 *   property.json   a digest of the final queue of each of upnext.sim's 2,000 property runs, so the Swift port of
 *                   that loop is known to run the very same 2,000 queues the sim checks.
 *
 * Every number a function draws is recorded as the Park-Miller generator's integer state s (the number itself is
 * (s - 1) / 2147483646 in both languages, bit for bit), so nothing depends on how a double prints. Math.random is
 * refused while recording: a function reaching for it would make the files differ run to run.
 *
 * Run it from anywhere, with ui/node_modules installed (npm ci in ui/):
 *
 *     node ios/scripts/export-traces.cjs           # writes the three files
 *     node ios/scripts/export-traces.cjs --check   # makes them in memory; exit 1 if the committed ones differ
 *
 * ui/test/iostraces.sim.cjs runs --check, so tests.yml fails when upNext.ts or playQueue.ts change - in what they
 * do or only in their text (the files name the sources' hashes) - without the files made again; making them again
 * touches ios/**, which runs ios.yml's Swift replay. Never edit the files by hand.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '../..')
const UI = path.join(REPO, 'ui')
const FIXTURES = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/upnext')
const SOURCES = ['ui/src/lib/upNext.ts', 'ui/src/lib/playQueue.ts']
const CHECK = process.argv.includes('--check')

/* ===== the TypeScript, compiled as ui/test/upnext.sim.cjs compiles it (no DOM, no JSX) ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-traces-'))
let U, Q
try {
  execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
    'src/lib/upNext.ts', 'src/lib/playQueue.ts', '--rootDir', 'src', '--outDir', OUT,
    '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022',
  ], { cwd: UI, stdio: 'inherit' })
  U = require(path.join(OUT, 'lib/upNext.js'))
  Q = require(path.join(OUT, 'lib/playQueue.js'))
} finally {
  fs.rmSync(OUT, { recursive: true, force: true })
}

const realRandom = Math.random
Math.random = () => { throw new Error('Math.random was called while recording: every random number must come from a tape') }

const madeFrom = Object.fromEntries(SOURCES.map((file) =>
  [file, crypto.createHash('sha256').update(fs.readFileSync(path.join(REPO, file))).digest('hex')]))

/* ===== Park-Miller, as the sims' seeded() - and the tape that records what is drawn from it ===== */

const M = 2147483647
class ParkMiller {
  constructor(seed) {
    if (!(seed >= 1 && seed < M)) throw new Error(`Park-Miller needs a seed in 1...2147483646, not ${seed}`)
    this.s = seed
  }
  int() { this.s = (this.s * 16807) % M; return this.s }
  next() { return (this.int() - 1) / 2147483646 }
}

/** A function's random: each number drawn from `generator`, its integer state kept for the op's record. */
class Tape {
  constructor(generator) { this.generator = generator; this.used = [] }
  get random() { return () => { const s = this.generator.int(); this.used.push(s); return (s - 1) / 2147483646 } }
  take() { const used = this.used; this.used = []; return used }
}

/* ===== songs: a table by id, the same song wherever its id comes up ===== */

/** The traces' songs: the first letter of the id says the album - m Mezzanine, d Dummy, x Loose (no album id, so
 *  a list of them is "Still to play") - and the level it was queued at (album, track, none). */
const ALBUMS = { m: ['Mezzanine', 'mez', 'album'], d: ['Dummy', 'dum', 'track'], x: ['Loose', null, null] }
function traceSong(id) {
  const [album, albumId, level] = ALBUMS[id[0]]
  const song = {
    id, title: `song ${id}`, artist: 'Massive Attack', album, albumId, coverArt: albumId, duration: 200,
    contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2,
  }
  if (level) song.level = level
  return song
}

/** upnext.sim.cjs's track(): Mezzanine's, unless the fields say otherwise. */
const simTrack = (id, fields = {}) => ({
  id, title: `song ${id}`, artist: 'Massive Attack', album: 'Mezzanine', albumId: 'mez', coverArt: null,
  duration: 200, contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2, ...fields,
})

class Songs {
  constructor() { this.byId = new Map() }
  /** The song, registered - an id names one song, so the same id with other fields is a mistake here. */
  add(song) {
    const known = this.byId.get(song.id)
    if (known && JSON.stringify(known) !== JSON.stringify(song)) throw new Error(`two songs under the id ${song.id}`)
    if (!known) this.byId.set(song.id, song)
    return known ?? song
  }
  table() { return Object.fromEntries([...this.byId].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) }
}

/* ===== what is recorded ===== */

const FROM = { source: 's', added: 'a', one: 'o' }
const FROM_BACK = { s: 'source', a: 'added', o: 'one' }

function pagedOf(paged) {
  const out = { token: paged.token, total: paged.total, fetched: paged.fetched, scope: paged.scope }
  if (paged.level !== undefined) out.level = paged.level
  return out
}

/** The queue as the Swift test compares it: ids for songs (the table has the rest), marks as resume's snapshot
 *  writes them. Without an Up Next account (EMPTY_QUEUE, a plain queue) only the index and the ids. */
function stateOf(queue) {
  const out = { index: queue.index, ids: queue.tracks.map((t) => t.id) }
  const state = queue.upNext
  if (!state) return out
  out.marks = state.marks.map((m) => [m.key, FROM[m.from], m.at, m.pass])
  out.source = state.source.map((t) => t.id)
  out.shuffle = state.shuffle
  out.nextKey = state.nextKey
  out.startedAt = state.startedAt
  out.left = state.left.map((gone) => [gone.pass, gone.at])
  if (state.paged) out.paged = pagedOf(state.paged)
  if (state.pagedRounds) out.pagedRounds = state.pagedRounds.map((held) => ({ pass: held.pass, paged: pagedOf(held.paged) }))
  return out
}

function viewOf(view) {
  const rows = (list) => list.map((row) => [row.key, row.track.id])
  return {
    playing: view.playing?.id ?? null,
    added: rows(view.added),
    list: view.list && { title: view.list.title, rows: rows(view.list.rows), more: view.list.more },
    then: view.then,
    repeatOne: view.repeatOne,
  }
}

/**
 * One run of ops on one queue, each recorded with what it was given, the numbers it drew, and the queue after it
 * (or `same`: the very queue it was given, which the Swift port must answer with an equal one).
 */
class Run {
  constructor(songs, tape) {
    this.songs = songs
    this.tape = tape
    this.queue = Q.EMPTY_QUEUE
    this.ops = []
    this.kept = new Map()
  }

  tracks(ids, make) { return ids.map((id) => this.songs.add(make(id))) }

  /** A fresh generator for the next op alone, as the sim's `seeded(n)` in a call. */
  seeded(seed) { this.tape = new Tape(new ParkMiller(seed)); return this }

  record(entry) {
    const used = this.tape.take()
    if (used.length) entry.randoms = used
    this.ops.push(entry)
    return entry
  }

  edit(fields, next) {
    const same = next === this.queue
    const entry = this.record({ ...fields, same })
    if (!same) entry.state = stateOf(next)
    this.queue = next
    return next
  }

  query(fields, result) {
    this.record({ ...fields, result })
    return result
  }

  get random() { return this.tape.random }

  start(tracks, start, shuffle = false, paged) {
    const fields = { op: 'start', ids: tracks.map((t) => t.id), start, shuffle }
    if (paged) fields.paged = pagedOf(paged)
    return this.edit(fields, U.startUpNext(tracks, start, shuffle, this.random, paged))
  }
  toppedUp(repeat) { return this.edit({ op: 'toppedUp', repeat }, U.toppedUp(this.queue, repeat, this.random)) }
  withRepeat(repeat) { return this.edit({ op: 'withRepeat', repeat }, U.withRepeat(this.queue, repeat)) }
  withShuffle(on) { return this.edit({ op: 'withShuffle', on }, U.withShuffle(this.queue, on, this.random)) }
  withNext(tracks) { return this.edit({ op: 'withNext', ids: tracks.map((t) => t.id) }, U.withNext(this.queue, tracks)) }
  withLast(tracks) { return this.edit({ op: 'withLast', ids: tracks.map((t) => t.id) }, U.withLast(this.queue, tracks)) }
  withoutKey(key) { return this.edit({ op: 'withoutKey', key }, U.withoutKey(this.queue, key)) }
  movedKey(key, to) { return this.edit({ op: 'movedKey', key, to }, U.movedKey(this.queue, key, to)) }
  withoutAdded() { return this.edit({ op: 'withoutAdded' }, U.withoutAdded(this.queue)) }
  jumpedTo(key) {
    const next = U.jumpedTo(this.queue, key)
    if (next === null) { this.query({ op: 'jumpedTo', key }, null); return null }
    return this.edit({ op: 'jumpedTo', key }, next)
  }
  withMore(token, tracks, next) {
    const fields = { op: 'withMore', token, ids: tracks.map((t) => t.id) }
    if (next) fields.next = pagedOf(next)
    return this.edit(fields, U.withMore(this.queue, token, tracks, next))
  }
  /** The engine moving: `{ ...queue, index }`. */
  setIndex(index) { return this.edit({ op: 'setIndex', index }, { ...this.queue, index }) }
  /** (scenarios) the sim's `{ ...first, upNext: { ...first.upNext, paged } }`. */
  setPaged(paged) {
    return this.edit({ op: 'setPaged', paged: pagedOf(paged) }, { ...this.queue, upNext: { ...this.queue.upNext, paged } })
  }
  /** (scenarios) a queue with no Up Next account, as the sim's `{ tracks: album(3), index: 0 }`. */
  plain(tracks, index) { return this.edit({ op: 'plain', ids: tracks.map((t) => t.id), index }, { tracks, index }) }
  empty() { return this.edit({ op: 'empty' }, Q.EMPTY_QUEUE) }
  /** (scenarios) a queue made by hand from a state record - one no sequence of edits reaches. */
  set(state) {
    const song = (id) => this.songs.byId.get(id) ?? (() => { throw new Error(`set: no song ${id}`) })()
    const queue = {
      tracks: state.ids.map(song), index: state.index,
      upNext: {
        marks: state.marks.map(([key, from, at, pass]) => ({ key, from: FROM_BACK[from], at, pass })),
        source: state.source.map(song), shuffle: state.shuffle, nextKey: state.nextKey, startedAt: state.startedAt,
        left: state.left.map(([pass, at]) => ({ pass, at })),
      },
    }
    this.ops.push({ op: 'set', state })
    this.queue = queue
    return queue
  }
  keep(name) { this.kept.set(name, this.queue); this.ops.push({ op: 'keep', name }); return this.queue }
  use(name) {
    if (!this.kept.has(name)) throw new Error(`use: nothing kept as ${name}`)
    this.queue = this.kept.get(name)
    this.ops.push({ op: 'use', name })
    return this.queue
  }

  onward() { return this.query({ op: 'onward' }, U.onward(this.queue)) }
  nextIndex() { return this.query({ op: 'nextIndex' }, Q.nextIndex(this.queue)) }
  shownPass() { return this.query({ op: 'shownPass' }, U.shownPass(this.queue)) }
  backward(position) { return this.query({ op: 'backward', position }, U.backward(this.queue, position)) }
  pastCopies(from) { return this.query({ op: 'pastCopies', from }, U.pastCopies(this.queue, from)) }
  view(repeat, limit) {
    const fields = { op: 'upNextView', repeat }
    if (limit !== undefined) fields.limit = limit
    return this.query(fields, viewOf(limit === undefined ? U.upNextView(this.queue, repeat) : U.upNextView(this.queue, repeat, limit)))
  }
  /** The key of the entry after the song playing with this id (the nth such), as upnext.sim's keyOf. */
  keyOf(id, from = 'any', nth = 0) {
    const q = this.queue
    const places = q.tracks.map((t, i) => (i > q.index && t.id === id && (from === 'any' || q.upNext.marks[i].from === from) ? i : -1)).filter((i) => i >= 0)
    return places.length > nth ? q.upNext.marks[places[nth]].key : null
  }
}

/* ===== the random traces ===== */

const TRACES = 150
const STEPS = 40

function trace(seed, songs) {
  const driver = new ParkMiller(seed)
  const run = new Run(songs, new Tape(new ParkMiller(seed + 1_000_000)))
  const pick = (n) => Math.floor(driver.next() * n)
  const chance = (p) => driver.next() < p
  const song = (id) => songs.add(traceSong(id))

  //? most traces lean one way on Shuffle, so Shuffle with Repeat All - the draws that matter most - comes up often
  const leansShuffled = chance(0.75)
  const repeatOf = () => { const r = driver.next(); return r < 0.45 ? 'all' : r < 0.7 ? 'one' : 'off' }
  let repeat = repeatOf()
  const letter = ['m', 'd', 'x'][pick(3)]
  const sizeDraw = driver.next()
  const size = sizeDraw < 0.02 ? 130 : sizeDraw < 0.12 ? 12 : 1 + pick(6)
  const list = Array.from({ length: size }, (_, i) => {
    const from = chance(0.15) ? ['m', 'd', 'x'][pick(3)] : letter
    //? sometimes a song already in the list: an id twice is two entries, each its own place
    return song(`${from}${chance(0.2) ? 1 + pick(size) : i + 1}`)
  })
  const start = chance(0.3) ? null : pick(size)
  const shuffle = chance(leansShuffled ? 0.7 : 0.3)
  let paged
  if (chance(0.1)) {
    const level = [undefined, 'album', 'track'][pick(3)]
    paged = { token: 't1', total: size + 3 * pick(4), fetched: size, scope: chance(0.5) ? 'yours' : 'store' }
    if (level) paged.level = level
  }
  let extra = 0
  let tokens = 1
  run.start(list, start, shuffle, paged)
  run.toppedUp(repeat)

  const rowKeys = () => (run.queue.upNext ? run.queue.upNext.marks.slice(run.queue.index + 1).map((m) => m.key) : [])
  //? mostly a row after the song playing; else any key up to two past nextKey - the song playing, one before it, a
  //? copy, a later round, a key the queue doesn't have
  const someKey = () => {
    const keys = rowKeys()
    return keys.length && chance(0.85) ? keys[pick(keys.length)] : pick((run.queue.upNext?.nextKey ?? 0) + 2)
  }
  const added = (kind) => Array.from({ length: 1 + pick(2) }, () => {
    if (chance(0.2) && run.queue.tracks.length) return run.queue.tracks[pick(run.queue.tracks.length)]
    return song(`${['m', 'd', 'x'][pick(3)]}${kind}${extra++}`)
  })

  for (let step = 0; step < STEPS; step++) {
    const isPaged = !!run.queue.upNext?.paged
    const op = pick(isPaged ? 16 : 15)
    if (op === 0) run.withNext(added('n'))
    else if (op === 1) run.withLast(added('l'))
    else if (op === 2) run.withoutKey(someKey())
    else if (op === 3) { const key = someKey(); run.movedKey(key, chance(0.1) ? 9 : pick(6)) }
    else if (op === 4) run.withoutAdded()
    else if (op === 5) { run.withShuffle(chance(leansShuffled ? 0.7 : 0.3)); run.toppedUp(repeat) }
    else if (op === 6) { repeat = repeatOf(); run.withRepeat(repeat); run.toppedUp(repeat) }
    else if (op === 7) run.toppedUp(repeat)
    else if (op === 8) {
      if (run.jumpedTo(someKey()) !== null) { const next = run.onward(); if (next !== null) run.setIndex(next) }
    } else if (op === 9) { const next = run.onward(); if (next !== null) run.setIndex(next); run.toppedUp(repeat) }
    else if (op === 10) { const next = run.nextIndex(); if (next !== null) run.setIndex(next); run.toppedUp(repeat) }
    else if (op === 11) {
      const action = run.backward([0, 1, 3, 3.5, 40][pick(5)])
      if (action.kind === 'go') run.setIndex(action.index)
    } else if (op === 12) run.pastCopies(run.queue.index + pick(2))
    else if (op === 13) run.shownPass()
    else if (op === 14) run.view(['off', 'all', 'one'][pick(3)], [1, 3, 100][pick(3)])
    else {
      const paged = run.queue.upNext.paged
      const token = chance(0.8) ? paged.token : 't0'
      const tracks = Array.from({ length: 1 + pick(3) }, () => song(`${['m', 'd', 'x'][pick(3)]}p${extra++}`))
      let next
      if (paged.fetched >= paged.total && chance(0.7)) {
        next = { token: `t${++tokens}`, total: paged.total, fetched: 0, scope: paged.scope }
        if (paged.level !== undefined) next.level = paged.level
      }
      run.withMore(token, tracks, next)
    }
  }
  return { seed, ops: run.ops }
}

/* ===== the named scenarios: upnext.sim.cjs's checks, built as it builds them ===== */

const scenarios = []
function scenario(name, build) {
  const songs = new Songs()
  //? a function's numbers for an op the sim gives no seeded() of its own: none are drawn there (each such op is
  //? unshuffled), and one would show up in the record
  const run = new Run(songs, new Tape(new ParkMiller(1)))
  build(run, {
    album: (n, prefix = '') => run.tracks(Array.from({ length: n }, (_, i) => `${prefix}${i + 1}`), simTrack),
    track: (id, fields) => songs.add(simTrack(id, fields)),
  })
  scenarios.push({ name, songs: songs.table(), ops: run.ops })
}

// startUpNext: exactly startQueue's queue (upnext.sim.cjs:133)
for (const [start, shuffle] of [[0, false], [3, false], [null, false], [3, true], [null, true], [0, true], [6, true]]) {
  scenario(`startUpNext from ${start} ${shuffle ? 'shuffled' : 'in order'}: what startQueue plays for the same random`, (r, { album }) => {
    r.seeded(11).start(album(7), start, shuffle)
  })
}
scenario('no songs: the empty queue, a plain one', (r) => { r.start([], 0) })
scenario('one song, shuffled: that song', (r, { track }) => { r.seeded(3).start([track('x')], 0, true) })
scenario('every mark the list\'s, the first time round; keys 0 to n-1; startedAt 0 shuffled, the start when not', (r, { album }) => {
  r.seeded(5).start(album(7), 2, true)
  r.start(album(7), 4)
})
scenario('a list with the same song twice: each entry its own place', (r, { track }) => {
  r.seeded(9).start([track('a'), track('b'), track('a')], 0, true)
})

// Play Next and Play Last (:235)
scenario('Play Next and Play Last: where they go', (r, { album, track }) => {
  r.start(album(4), 0)
  r.keep('start')
  r.withNext([track('n')])
  r.withNext([track('m')])
  r.withLast([track('z')])
  r.use('start')
  r.toppedUp('one')
  r.keep('one')
  r.withNext([track('n')])
  r.use('one')
  r.withLast([track('z')])
  r.use('start')
  r.withNext([track('a'), track('b')])
  r.use('start')
  r.withNext([])
  r.empty()
  r.withLast([track('a')])
})

// a row out, a row moved, Clear (:249)
scenario('a row out, a row moved, Clear', (r, { album, track }) => {
  r.start(album(4), 0)
  r.withLast([track('a'), track('b')])
  r.keep('start')
  r.withoutKey(r.keyOf('a'))
  r.use('start')
  r.withoutKey(r.keyOf('3'))
  r.use('start')
  r.withoutKey(r.queue.upNext.marks[0].key)
  const second = r.queue.upNext.marks[1].key
  r.setIndex(2)
  r.withoutKey(second)
  r.use('start')
  r.withoutKey(999)
  r.movedKey(r.keyOf('b'), 0)
  r.use('start')
  r.movedKey(r.keyOf('2'), 2)
  r.use('start')
  r.movedKey(r.keyOf('2'), 9)
  r.use('start')
  r.movedKey(r.keyOf('3'), 1)
  r.toppedUp('one')
  const copy = r.queue.upNext.marks[1].key
  r.movedKey(copy, 3)
  r.withoutKey(copy)
  r.use('start')
  r.withoutAdded()
  r.withoutAdded()
})

// a row's tap: jumped to (:268)
scenario('a row\'s tap: jumped to', (r, { album, track }) => {
  r.start(album(5), 0)
  r.withLast([track('a'), track('b')])
  r.keep('start')
  r.jumpedTo(r.keyOf('4'))
  r.setIndex(r.onward())
  r.use('start')
  r.jumpedTo(r.keyOf('b'))
  r.setIndex(r.onward())
  r.use('start')
  r.jumpedTo(r.queue.upNext.marks[0].key)
  r.toppedUp('one')
  r.jumpedTo(r.queue.upNext.marks[1].key)
  r.use('start')
  r.jumpedTo(77)
  r.start(album(3), 0)
  r.toppedUp('one')
  r.jumpedTo(r.keyOf('3'))
  r.setIndex(r.onward())
})

// Shuffle on (:286)
scenario('Shuffle on: the songs not yet heard this round', (r, { album, track }) => {
  r.start(album(12), 4)
  r.keep('start')
  r.setIndex(6)
  r.keep('at6')
  r.seeded(4).withShuffle(true)
  r.use('at6')
  r.withLast([track('a')])
  r.withNext([track('b')])
  r.seeded(2).withShuffle(true)
  r.use('at6')
  r.withoutKey(r.keyOf('9'))
  r.seeded(3).withShuffle(true)
  r.use('at6')
  r.jumpedTo(r.keyOf('10'))
  r.setIndex(r.onward())
  r.seeded(3).withShuffle(true)
  r.use('start')
  r.withShuffle(false)
  r.empty()
  r.withShuffle(true)
})
scenario('Shuffle on at a round\'s last song: the next round is the shuffled one; later rounds go', (r, { album }) => {
  r.start(album(3), 0)
  r.setIndex(0)
  r.toppedUp('all')
  r.keep('all')
  r.setIndex(2)
  r.toppedUp('all')
  r.seeded(8).withShuffle(true)
  r.seeded(8).toppedUp('all')
  r.use('all')
  r.seeded(1).withShuffle(true)
})

// Shuffle off (:313)
scenario('Shuffle off: the list\'s own order from the song playing\'s place', (r, { album, track }) => {
  r.seeded(6).start(album(8), null, true)
  r.setIndex(2)
  r.keep('now')
  r.withShuffle(false)
  r.use('now')
  const place = r.queue.upNext.marks[2].at
  const expected = Array.from({ length: 8 }, (_, i) => `${i + 1}`).slice(place + 1)
  r.withoutKey(r.keyOf(expected[0] ?? 'none') ?? -1)
  r.withShuffle(false)
  r.use('now')
  r.withNext([track('a')])
  r.keep('added')
  r.withShuffle(false)
  r.use('added')
  r.setIndex(3)
  r.withShuffle(false)
})

// Repeat All (:333)
scenario('Repeat All: the list again, ahead of where anything looks', (r, { album, track }) => {
  r.start(album(3), 0)
  r.keep('start')
  r.toppedUp('all')
  r.setIndex(1)
  r.toppedUp('all')
  r.toppedUp('all')
  r.start([track('x')], 0)
  r.toppedUp('all')
  r.use('start')
  r.setIndex(2)
  r.withNext([track('a')])
  r.toppedUp('all')
  r.use('start')
  r.setIndex(2)
  r.toppedUp('off')
})
scenario('Repeat All with Shuffle on: a fresh order of the whole list', (r, { album }) => {
  r.seeded(3).start(album(6), 0, true)
  r.setIndex(5)
  r.seeded(9).toppedUp('all')
})
for (const seed of [1, 2, 3, 7, 11, 42, 99, 1000]) {
  for (const size of [2, 4]) {
    scenario(`Repeat All shuffled, seed ${seed}, ${size} songs: never starting with the song that ended the round before`, (r, { album }) => {
      r.seeded(seed).start(album(size), 0, true)
      r.setIndex(size - 1)
      r.seeded(seed * 7).toppedUp('all')
    })
  }
}

// Repeat One (:359)
scenario('Repeat One: copies of the song, straight after it', (r, { album, track }) => {
  r.start(album(3), 0)
  r.withLast([track('a')])
  r.toppedUp('one')
  r.setIndex(Math.min(r.queue.index + 1, r.queue.tracks.length - 1))
  r.toppedUp('one')
  r.toppedUp('one')
})

// Repeat changed (:369)
scenario('Repeat changed: what goes', (r, { album }) => {
  r.start(album(3), 0)
  r.toppedUp('one')
  r.withRepeat('off')
  r.start(album(3), 0)
  r.setIndex(1)
  r.toppedUp('all')
  r.keep('all')
  r.withRepeat('off')
  r.use('all')
  r.setIndex(2)
  r.toppedUp('all')
  r.withRepeat('off')
  r.start(album(3), 0)
  r.setIndex(1)
  r.toppedUp('one')
  r.withRepeat('all')
  r.toppedUp('all')
  r.use('all')
  r.withRepeat('one')
  r.toppedUp('one')
  r.start(album(3), 0)
  r.withRepeat('off')
  r.use('all')
  r.withRepeat('all')
})

// Next, Previous and a failure's skip pass Repeat One's copies (:384)
scenario('Next, Previous and a failure\'s skip pass Repeat One\'s copies', (r, { album }) => {
  r.start(album(3), 0)
  r.setIndex(1)
  r.toppedUp('one')
  r.keep('one')
  r.onward()
  r.pastCopies(2)
  r.start(album(2), 0)
  r.setIndex(1)
  r.toppedUp('one')
  r.onward()
  r.pastCopies(2)
  r.plain(album(3), 1)
  r.onward()
  r.plain(album(3), 2)
  r.onward()
  r.plain(album(3), 0)
  r.pastCopies(2)
  r.pastCopies(3)
  r.backward(1)
  r.use('one')
  r.setIndex(2)
  r.backward(10)
  r.backward(1)
  r.start(album(2), 0)
  r.toppedUp('one')
  r.setIndex(1)
  r.backward(1)
  r.start(album(3), 0)
  r.backward(1)
  r.setIndex(2)
  r.backward(1)
  r.backward(3)
  r.backward(3.5)
  r.empty()
  r.onward()
  r.backward(1)
  r.pastCopies(0)
  r.shownPass()
})

// what Up Next draws (:401)
scenario('what Up Next draws', (r, { album, track }) => {
  r.start(album(4), 0)
  r.keep('start')
  r.view('off')
  r.withNext([track('a', { album: 'Dummy', albumId: 'dum' })])
  r.toppedUp('one')
  r.toppedUp('one')
  r.view('one')
  r.use('start')
  r.setIndex(3)
  r.toppedUp('all')
  r.view('all')
  r.use('start')
  r.setIndex(2)
  r.toppedUp('all')
  r.view('all')
  r.use('start')
  r.setIndex(3)
  r.view('off')
  r.empty()
  r.view('all')
})
scenario('Shuffle on with Repeat All: a new order next time', (r, { album }) => {
  r.seeded(1).start(album(4), null, true)
  r.toppedUp('all')
  r.view('all')
})
scenario('the cap: the first 100 drawn, the rest counted', (r, { album }) => {
  r.start(album(130), 0)
  r.view('off')
  r.view('off', 5)
  r.view('off', 1)
})
scenario('several albums: "Still to play", and "the list" again', (r, { track }) => {
  r.start([track('1'), track('2', { albumId: 'dum', album: 'Dummy' })], 0)
  r.view('off')
  r.setIndex(1)
  r.toppedUp('all')
  r.view('all')
})

// (Part B) a library's shuffle, fed a page at a time (:437)
scenario('(Part B) a library\'s shuffle, fed a page at a time', (r, { album }) => {
  const paged = { token: 't1', total: 450, fetched: 3, scope: 'store' }
  r.start(album(3, 'p'), 0, false, paged)
  r.keep('first')
  r.withMore('t1', album(2, 'q'))
  r.use('first')
  r.withMore('t0', album(2, 'q'))
  r.setPaged({ ...paged, fetched: 450 })
  r.keep('whole')
  r.withMore('t1', album(2, 'r'), { token: 't2', total: 450, fetched: 0, scope: 'store' })
  r.keep('fresh')
  r.use('whole')
  r.withMore('t1', [], { token: 't9', total: 0, fetched: 0, scope: 'store' })
  r.use('first')
  r.withMore('t1', [])
  r.use('fresh')
  r.setIndex(2)
  r.keep('atLast')
  r.withRepeat('off')
  r.use('atLast')
  r.withRepeat('one')
  r.use('atLast')
  r.withRepeat('all')
  r.use('first')
  r.withMore('t1', album(2, 'r'), { token: 't3', total: 450, fetched: 0, scope: 'store' })
  r.use('first')
  r.setIndex(2)
  r.toppedUp('all')
  r.use('first')
  r.withShuffle(false)
  r.toppedUp('one')
  r.use('first')
  r.view('off')
  r.view('all')
  r.setPaged({ ...paged, scope: 'yours' })
  r.view('all')
  r.view('off')
})
scenario('(Part B) a paged shuffle at a level, a fresh round past it, and Repeat off going back', (r, { album }) => {
  const paged = { token: 't1', total: 4, fetched: 2, scope: 'yours', level: 'album' }
  r.start(album(2, 'p'), 1, false, paged)
  r.withMore('t1', album(2, 'q'))
  r.withMore('t1', album(2, 'r'), { token: 't2', total: 4, fetched: 0, scope: 'yours', level: 'album' })
  r.setIndex(3)
  r.withMore('t2', album(2, 's'))
  r.withMore('t2', album(2, 'u'), { token: 't3', total: 4, fetched: 0, scope: 'yours', level: 'album' })
  r.keep('two rounds')
  r.view('all')
  r.withRepeat('off')
  r.use('two rounds')
  r.setIndex(5)
  r.withRepeat('off')
})

// what the sim doesn't reach
scenario('Previous back across another song\'s copies', (r, { album, track }) => {
  r.start(album(3), 0)
  r.toppedUp('one')
  r.setIndex(r.onward())
  r.toppedUp('one')
  r.setIndex(4)
  r.toppedUp('one')
  r.backward(1)
  r.setIndex(2)
  r.toppedUp('one')
  r.view('one')
  r.onward()
  r.pastCopies(3)
  r.shownPass()
  r.withNext([track('n')])
  r.withLast([track('l')])
  r.view('one')
  r.withRepeat('off')
  r.backward(1)
  r.withRepeat('all')
  r.toppedUp('all')
  r.view('all')
})
scenario('Repeat One while a song added plays', (r, { album, track }) => {
  r.start(album(3), 0)
  r.withNext([track('a')])
  r.setIndex(1)
  r.toppedUp('one')
  r.view('one')
  r.setIndex(2)
  r.toppedUp('one')
  r.backward(1)
  r.withShuffle(true)
  r.withRepeat('all')
  r.toppedUp('all')
  r.withRepeat('off')
})
scenario('a list of one song twice under Shuffle and Repeat All: the draw with nothing else to start with', (r, { track }) => {
  r.seeded(5).start([track('a'), track('a')], 0, true)
  r.setIndex(1)
  r.seeded(7).toppedUp('all')
  r.seeded(8).toppedUp('all')
  r.setIndex(3)
  r.seeded(9).toppedUp('all')
})
scenario('Shuffle on at a song before where the list began', (r, { album }) => {
  r.start(album(5), 3)
  r.setIndex(2)
  r.seeded(2).withShuffle(true)
  r.withShuffle(false)
  r.setIndex(0)
  r.seeded(12).withShuffle(true)
})
scenario('a queue with none of the list at or before the song playing (round -1)', (r, { album, track }) => {
  album(3)
  track('a')
  r.set({
    index: 0, ids: ['a', '1', '2', '3'],
    marks: [[0, 'a', -1, -1], [1, 's', 0, 0], [2, 's', 1, 0], [3, 's', 2, 0]],
    source: ['1', '2', '3'], shuffle: false, nextKey: 4, startedAt: 0, left: [],
  })
  r.keep('set')
  r.seeded(4).withShuffle(true)
  r.withShuffle(false)
  r.use('set')
  r.withShuffle(false)
  r.use('set')
  r.withRepeat('off')
  r.toppedUp('all')
  r.view('all')
  r.use('set')
  r.toppedUp('one')
  r.view('one')
  r.backward(1)
})
scenario('a song removed, then Shuffle off and on: it stays out of its round', (r, { album }) => {
  r.start(album(6), 0)
  r.withoutKey(r.keyOf('3'))
  r.seeded(21).withShuffle(true)
  r.withShuffle(false)
  r.seeded(22).withShuffle(true)
  r.setIndex(r.onward())
  r.withShuffle(false)
  r.toppedUp('all')
  r.setIndex(r.queue.tracks.length - 1)
  r.toppedUp('all')
  r.seeded(23).withShuffle(true)
})

/* ===== the words and the constants ===== */

const words = []
{
  const songs = new Songs()
  const list = (fieldsList) => fieldsList.map(([id, fields]) => songs.add(simTrack(id, fields)))
  for (const [tracks, again] of [
    [list([['1'], ['2']]), false], [list([['1'], ['2']]), true],
    [list([['1'], ['2b', { albumId: 'x' }]]), true], [list([['1n', { albumId: null }]]), false],
    [list([['1e', { albumId: '' }]]), false], [list([['1q', { album: '', albumId: 'q' }]]), false], [[], false],
  ]) words.push({ fn: 'listTitle', ids: tracks.map((t) => t.id), again, result: U.listTitle(tracks, again) })
  for (const how of ['next', 'last']) words.push({ fn: 'queuedWords', how, label: 'Roads', result: U.queuedWords(how, 'Roads') })
  for (const repeat of U.REPEATS) {
    words.push({ fn: 'repeatLabel', repeat, result: U.repeatLabel(repeat) })
    words.push({ fn: 'nextRepeat', repeat, result: U.nextRepeat(repeat) })
    for (const shuffle of [false, true]) words.push({ fn: 'upNextLabel', shuffle, repeat, result: U.upNextLabel(shuffle, repeat) })
  }
  for (const scope of [null, 'store', 'yours']) words.push({ fn: 'shuffleLabel', scope, result: U.shuffleLabel(scope ?? undefined) })
  scenarios.push({ name: 'the words', songs: songs.table(), ops: [] })
  scenarios[scenarios.length - 1].words = words
}

const constants = {
  REPEAT_AHEAD: U.REPEAT_AHEAD, UP_NEXT_DRAWN: U.UP_NEXT_DRAWN, TOP_UP_HEARD_S: U.TOP_UP_HEARD_S,
  REPEATS: U.REPEATS, RESTART_AFTER_SECONDS: Q.RESTART_AFTER_SECONDS,
}

/* ===== upnext.sim.cjs's property loop (:175-229), its every call as there, each run's last queue digested ===== */

/** 32-bit FNV-1a over the canonical line's character codes (ASCII), as eight hex digits. */
function fnv1a(text) {
  let hash = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash.toString(16).padStart(8, '0')
}

/** The line the Swift test builds the same way: index; ids; marks; source; shuffle, nextKey, startedAt; left. */
function canonical(queue) {
  const s = queue.upNext
  return [
    queue.index,
    queue.tracks.map((t) => t.id).join(','),
    s.marks.map((m) => `${m.key}${FROM[m.from]}${m.at}/${m.pass}`).join(','),
    s.source.map((t) => t.id).join(','),
    `${s.shuffle ? 1 : 0},${s.nextKey},${s.startedAt}`,
    s.left.map((gone) => `${gone.pass}/${gone.at}`).join(','),
  ].join(';')
}

const PROPERTY_RUNS = 2000
const PROPERTY_STEPS = 30
function propertyDigests() {
  const seeded = (seed) => { const generator = new ParkMiller(seed); return () => generator.next() }
  const album = (n) => Array.from({ length: n }, (_, i) => simTrack(`${i + 1}`))
  const at = (queue, index) => ({ ...queue, index })
  const ended = (queue) => ({ ...queue, index: Math.min(queue.index + 1, queue.tracks.length - 1) })
  const digests = []
  for (let run = 0; run < PROPERTY_RUNS; run++) {
    const random = seeded(run + 1)
    const pick = (n) => Math.floor(random() * n)
    const size = 1 + pick(6)
    let repeat = U.REPEATS[pick(3)]
    let queue = U.toppedUp(U.startUpNext(album(size), random() < 0.3 ? null : pick(size), random() < 0.5, random), repeat, random)
    let extra = 0
    for (let step = 0; step < PROPERTY_STEPS; step++) {
      const op = pick(12)
      const rowKeys = () => queue.upNext.marks.slice(queue.index + 1).map((m) => m.key)
      const someKey = () => { const keys = rowKeys(); return keys.length && random() < 0.85 ? keys[pick(keys.length)] : pick(queue.upNext.nextKey + 2) }
      if (op === 0) queue = U.withNext(queue, Array.from({ length: 1 + pick(2) }, () => simTrack(`n${extra++}`)))
      else if (op === 1) queue = U.withLast(queue, Array.from({ length: 1 + pick(2) }, () => simTrack(`l${extra++}`)))
      else if (op === 2) queue = U.withoutKey(queue, someKey())
      else if (op === 3) queue = U.movedKey(queue, someKey(), pick(6))
      else if (op === 4) queue = U.withoutAdded(queue)
      else if (op === 5) queue = U.withShuffle(queue, random() < 0.5, random)
      else if (op === 6) { repeat = U.REPEATS[pick(3)]; queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, random) }
      else if (op === 7) queue = U.toppedUp(queue, repeat, random)
      else {
        if (op === 8) {
          const jumped = U.jumpedTo(queue, someKey())
          if (jumped) {
            const next = U.onward(jumped)
            if (next !== null) queue = at(jumped, next)
          }
        } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = at(queue, next) }
        else queue = ended(queue)
        queue = U.toppedUp(queue, repeat, random)
      }
    }
    digests.push(fnv1a(canonical(queue)))
  }
  return digests
}

/* ===== written, or checked ===== */

const header = (extra) => JSON.stringify({ version: 1, made_by: 'ios/scripts/export-traces.cjs', made_from: madeFrom, ...extra })
/** `{header..., "<key>":[` then one item a line, so a change reads as a diff of the items it touched. */
const lines = (head, key, items) => `${head.slice(0, -1)},"${key}":[\n${items.map((item) => JSON.stringify(item)).join(',\n')}\n]}\n`

const traceSongs = new Songs()
const traces = Array.from({ length: TRACES }, (_, i) => trace(i + 1, traceSongs))
const digests = propertyDigests()
const files = {
  'traces.json': lines(header({ steps: STEPS, songs: traceSongs.table() }), 'traces', traces),
  'scenarios.json': lines(header({ constants }), 'scenarios', scenarios),
  'property.json': lines(header({ runs: PROPERTY_RUNS, steps: PROPERTY_STEPS }), 'digests',
    Array.from({ length: Math.ceil(digests.length / 10) }, (_, i) => digests.slice(i * 10, i * 10 + 10))),
}
Math.random = realRandom

if (CHECK) {
  const stale = []
  for (const [name, text] of Object.entries(files)) {
    const file = path.join(FIXTURES, name)
    const committed = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
    if (committed === text) continue
    let only = ''
    try {
      const [a, b] = [JSON.parse(committed), JSON.parse(text)]
      delete a.made_from
      delete b.made_from
      if (JSON.stringify(a) === JSON.stringify(b)) only = ' (only the sources\' hashes: every trace is the same)'
    } catch { /* missing, or not JSON: stale either way */ }
    stale.push(`${name}${committed === null ? ' (missing)' : only}`)
  }
  if (stale.length) {
    console.error(`The Up Next traces are stale: ${stale.join(', ')}.\n` +
      `${SOURCES.join(' or ')} changed without them - run  node ios/scripts/export-traces.cjs  and commit what it writes\n` +
      '(then the Swift replay, swift test --package-path ios/DeadwaxKit, says whether the port still agrees).')
    process.exit(1)
  }
  console.log(`The Up Next traces are current: ${Object.keys(files).join(', ')}.`)
} else {
  fs.mkdirSync(FIXTURES, { recursive: true })
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(FIXTURES, name), text)
  const ops = traces.reduce((n, t) => n + t.ops.length, 0)
  const draws = traces.reduce((n, t) => n + t.ops.reduce((m, o) => m + (o.randoms?.length ?? 0), 0), 0)
  console.log(`Wrote ${Object.entries(files).map(([name, text]) => `${name} (${text.length} bytes)`).join(', ')} to ${path.relative(REPO, FIXTURES)}: ` +
    `${traces.length} traces of ${ops} ops and ${draws} draws, ${scenarios.length} scenarios, ${digests.length} property runs.`)
}
