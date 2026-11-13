#!/usr/bin/env node
/**
 * The iPhone app's Up Next and its resume are ports of the web app's (ui/src/lib/upNext.ts, the queue parts of
 * ui/src/lib/playQueue.ts, and ui/src/lib/resume.ts) to Swift (ios/DeadwaxKit/Sources/DeadwaxCore/UpNext*.swift,
 * Resume.swift, SnapshotJSON.swift). This records what the TypeScript does - the same inputs, the same random
 * numbers, the state after every step, the very text of every snapshot - so the Swift tests can replay it and hold
 * the ports to it (the plan's risk R12: a queue saved on one must come back the same on the other). Three files in
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/upnext/:
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
 * (2.1.3) A row's tap is recorded as jumpedTo's edit with the index it moves to (`index`), then the move (setIndex);
 * Previous as wentBack (startedAt following it down); History as historyRows, and in every view.
 *
 * and two in Fixtures/resume/:
 *
 *   cases.json      resume.ts function by function: the window, relevel, the notice's words, savedLevels; toSave of
 *                   every queue resume.sim.cjs builds and more (Repeat's copies and rounds, Shuffle with songs left
 *                   out, a library's shuffle with and without a level and its rounds, titles with every character
 *                   JSON escapes or doesn't, ids JavaScript lists first, durations of every shape), each snapshot
 *                   kept as the TEXT the web writes; that text read back under all four settings, and snapshots
 *                   broken or written otherwise (1.0, a key twice, pretty-printed, escapes) as the web reads them;
 *                   resumed() of every answer resume.sim gives it and more (as wire JSON, through shuffledTrack -
 *                   the real toQueueTrack); saveDue over a sweep of its clocks; the snapshot's cap in UTF-16 units,
 *                   from recipes rather than stored; and the constants the phone shares (the device id's letters,
 *                   the label, MARGIN_MS, OWED_ORDER, Object.prototype's names).
 *   roundtrip.json  every step of resume.sim.cjs's round trip, runs 0-39 whole: the queue, and the snapshot toSave
 *                   wrote for it - which the phone must write to the byte and read back as the web does; and all 500
 *                   runs digested (each snapshot's FNV-1a), so the Swift port of the run's generator is known to
 *                   write the web's very texts at every step.
 *
 * Every snapshot recorded is also written by a reference writer here (the snapshot's form written out key by key,
 * as Resume.swift writes it) and must be the TypeScript's text - so a change of the form fails here, by name.
 * (2.1.15; the phone's app 0.8) A queue has an `id` (UpNextState.id), which toSave writes second and fromSnapshot reads
 * back - the phone too since its play history port, so every snapshot here is written with it and every queue
 * recorded carries it. queueId()'s clock and random bytes are a counter while recording (ID_CLOCK, `madeIds`), so a
 * queue made without an id given has the same one every run; a queue READ that was given a new one (a snapshot saved
 * without an id - the web's before 2.1.15, the phone's before 0.8, which the phone still reads - or a plain list) is
 * recorded with `"id": null`, "a new one", which the Swift tests give their own. Such id-less snapshots are among
 * fromSnapshot's cases (`withoutId`), and those read while the queue they describe is held (`holding`, sameQueue).
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
 * ui/test/iostraces.sim.cjs runs --check, so tests.yml fails when upNext.ts, playQueue.ts or resume.ts change - in
 * what they do or only in their text (the files name the sources' hashes; for api.ts's toQueueTrack and
 * useShuffleFeed.ts's shuffledTrack, the hash of the function alone) - without the files made again; making them
 * again touches ios/**, which runs ios.yml's Swift replay. Never edit the files by hand.
 *
 * The two controllers are ported by hand and replay no traces: QueueController.swift (usePlayer.ts's queue rules -
 * catchUp, the edits and the held change, Repeat's top-up, Play Next/Last, Next, Previous, a row's tap, Shuffle,
 * Repeat, restoreQueue, onEnded's Repeat line, onFailure's skip) and ResumeController.swift (useResume.ts's
 * createResume). The pieces of the web they port are hashed into the files' made_from as well, each function alone,
 * so a change to one fails the check too, naming it and the Swift file to read it against - port it, THEN run this.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '../..')
const UI = path.join(REPO, 'ui')
const FIXTURES = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/upnext')
const RESUME_FIXTURES = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/resume')
const SOURCES = ['ui/src/lib/upNext.ts', 'ui/src/lib/playQueue.ts']
const RESUME_SOURCES = ['ui/src/lib/resume.ts', ...SOURCES]
const CHECK = process.argv.includes('--check')

/* ===== the TypeScript, compiled as ui/test/upnext.sim.cjs compiles it (no DOM, no JSX) ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-traces-'))
let U, Q, R, API
try {
  execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
    'src/lib/upNext.ts', 'src/lib/playQueue.ts', 'src/lib/resume.ts', '--rootDir', 'src', '--outDir', OUT,
    '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022',
  ], { cwd: UI, stdio: 'inherit' })
  U = require(path.join(OUT, 'lib/upNext.js'))
  Q = require(path.join(OUT, 'lib/playQueue.js'))
  R = require(path.join(OUT, 'lib/resume.js'))
  //? player/api.ts on its own, as resume.sim.cjs compiles it, for the real toQueueTrack (shuffledTrack's)
  execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
    'src/player/api.ts', '--rootDir', 'src', '--outDir', path.join(OUT, 'api'),
    '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
    '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
  ], { cwd: UI, stdio: 'inherit' })
  API = require(path.join(OUT, 'api/player/api.js'))
} finally {
  fs.rmSync(OUT, { recursive: true, force: true })
}

const realRandom = Math.random
Math.random = () => { throw new Error('Math.random was called while recording: every random number must come from a tape') }

//? (app 0.8) queueId()'s clock and random bytes, the same every run: its bytes are a count, written in base 36 by its
//? own letters - so the n-th queue made here without an id given is `<ID_CLOCK in base 36>-<n in eight base-36 digits>`
//? - and each made is noted (`madeIds`), so a queue read back that was given one is recorded as given a new one (null)
const ID_CLOCK = 1_762_000_000_000
const realNow = Date.now
const realCrypto = Object.getOwnPropertyDescriptor(globalThis, 'crypto')
const madeIds = []
Date.now = () => ID_CLOCK
Object.defineProperty(globalThis, 'crypto', {
  configurable: true,
  value: {
    getRandomValues(bytes) {
      const n = madeIds.length + 1
      for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(n / 36 ** (bytes.length - 1 - i)) % 36
      madeIds.push(`${ID_CLOCK.toString(36)}-${[...bytes].map((byte) => '0123456789abcdefghijklmnopqrstuvwxyz'[byte % 36]).join('')}`)
      return bytes
    },
  },
})

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex')
const madeFrom = Object.fromEntries(SOURCES.map((file) => [file, sha256(fs.readFileSync(path.join(REPO, file)))]))

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
    history: rows(view.history),
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
  /** (2.1.3) A row's tap: its edit (or the same queue) recorded with the index to move to - the caller moves there
   *  (setIndex), as the player does. The jump, or null. */
  jumpedTo(key) {
    const jump = U.jumpedTo(this.queue, key)
    if (jump === null) { this.query({ op: 'jumpedTo', key }, null); return null }
    this.edit({ op: 'jumpedTo', key, index: jump.index }, jump.queue)
    return jump
  }
  /** (2.1.3) Previous's move: startedAt following it down before where listening began. */
  wentBack(index) { return this.edit({ op: 'wentBack', index }, U.wentBack(this.queue, index)) }
  /** (scenarios) the sim's previous(): backward early, then wentBack. */
  previous() { const b = this.backward(1); if (b.kind === 'go') this.wentBack(b.index); return this.queue }
  /** (scenarios) the sim's ended(): the next entry, copies included. */
  ended() { return this.setIndex(Math.min(this.queue.index + 1, this.queue.tracks.length - 1)) }
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
  historyRows(back) {
    const fields = { op: 'historyRows' }
    if (back !== undefined) fields.back = back
    const rows = back === undefined ? U.historyRows(this.queue) : U.historyRows(this.queue, back)
    return this.query(fields, rows.map((row) => [row.key, row.track.id]))
  }
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
      //? (2.1.3) now and then a row of History's
      const history = U.historyRows(run.queue)
      const jump = run.jumpedTo(history.length && chance(0.3) ? history[pick(history.length)].key : someKey())
      if (jump !== null) run.setIndex(jump.index)
    } else if (op === 9) { const next = run.onward(); if (next !== null) run.setIndex(next); run.toppedUp(repeat) }
    else if (op === 10) { const next = run.nextIndex(); if (next !== null) run.setIndex(next); run.toppedUp(repeat) }
    else if (op === 11) {
      const action = run.backward([0, 1, 3, 3.5, 40][pick(5)])
      if (action.kind === 'go') run.wentBack(action.index)
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
  r.setIndex(r.jumpedTo(r.keyOf('4')).index)
  r.use('start')
  r.setIndex(r.jumpedTo(r.keyOf('b')).index)
  r.use('start')
  r.jumpedTo(r.queue.upNext.marks[0].key)
  r.toppedUp('one')
  r.jumpedTo(r.queue.upNext.marks[1].key)
  r.use('start')
  r.jumpedTo(77)
  r.start(album(3), 0)
  r.toppedUp('one')
  r.setIndex(r.jumpedTo(r.keyOf('3')).index)
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
  r.setIndex(r.jumpedTo(r.keyOf('10')).index)
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

// (2.1.3) History, and a tap that keeps what it passes (upnext.sim.cjs's 2.1.3 section)
scenario('(2.1.3) James\'s walk: tap 8 while 5 plays - Previous plays 7, then 6, as on the album', (r, { album }) => {
  r.start(album(12), 0)
  r.setIndex(4)
  r.setIndex(r.jumpedTo(r.keyOf('8')).index)
  r.view('off')
  for (let i = 0; i < 3; i++) r.previous()
  r.setIndex(r.onward())
  r.ended()
})
scenario('(2.1.3) a tap into the list with a song added: still next after it; after Previous drawn where it plays', (r, { album, track }) => {
  r.start(album(12), 0)
  r.setIndex(4)
  r.withNext([track('a', { album: 'Dummy', albumId: 'dum' })])
  r.setIndex(r.jumpedTo(r.keyOf('8')).index)
  r.view('off')
  r.previous()
  r.view('off')
  r.keep('back')
  r.withoutAdded()
  const aKey = r.keyOf('a')
  r.movedKey(aKey, 0)
  r.use('back')
  r.withoutKey(aKey)
  r.use('back')
  r.setIndex(r.jumpedTo(aKey).index)
})
scenario('(2.1.3) History: what is behind the song playing', (r, { album }) => {
  r.start(album(12), 4)
  r.keep('fromFive')
  r.view('off')
  r.backward(1)
  r.setIndex(6)
  r.view('off')
  r.wentBack(5)
  r.use('fromFive')
  r.previous()
  r.historyRows()
  r.ended()
  r.historyRows()
  r.plain(album(3), 2)
  r.wentBack(1)
  r.seeded(5).start(album(6), 3, true)
  r.setIndex(3)
  r.historyRows()
  r.start(album(3), 0, false, { token: 't', total: 9, fetched: 3, scope: 'yours' })
  r.setIndex(2)
  r.historyRows()
  r.start(album(5), 0)
  r.setIndex(1)
  r.toppedUp('one')
  r.ended()
  r.toppedUp('one')
  r.ended()
  r.withRepeat('off')
  r.toppedUp('off')
  r.setIndex(r.onward())
  r.setIndex(r.onward())
  r.view('off')
  r.setIndex(2)
  r.historyRows()
  r.start(album(3), 0)
  r.toppedUp('all')
  for (let i = 0; i < 4; i++) { r.ended(); r.toppedUp('all') }
  r.view('all')
  r.start(album(80), 0)
  r.setIndex(70)
  r.view('off')
  r.historyRows()
  r.historyRows(3)
  r.historyRows(0)
  r.empty()
  r.historyRows()
})
scenario('(2.1.3 review) a unit is one song: Shuffle and Repeat take a list song\'s copies with it', (r, { album }) => {
  r.start(album(5), 0)
  r.setIndex(1)
  r.toppedUp('one')
  r.previous()
  r.toppedUp('one')
  r.seeded(7).withShuffle(true)
  r.setIndex(r.onward())
  r.toppedUp('one')
  r.backward(0)
  r.historyRows()
  r.start(album(2), 0)
  r.setIndex(1)
  r.toppedUp('all')
  r.ended()
  r.toppedUp('all')
  r.withRepeat('one')
  r.toppedUp('one')
  r.previous()
  r.toppedUp('one')
  r.withRepeat('one')
  r.view('one')
})
scenario('(2.1.3) History\'s tap: the song again, then Up Next as it was', (r, { album, track }) => {
  r.start(album(9), 0)
  r.setIndex(6)
  r.withNext([track('a')])
  const k3 = r.queue.upNext.marks[2].key
  r.setIndex(r.jumpedTo(k3).index)
  r.view('off')
  r.keep('again')
  r.previous()
  r.use('again')
  r.setIndex(r.onward())
  r.historyRows()
  r.start(album(4), 0)
  r.setIndex(2)
  r.toppedUp('one')
  r.keep('one')
  r.setIndex(r.jumpedTo(r.queue.upNext.marks[0].key).index)
  r.toppedUp('one')
  r.use('one')
  r.jumpedTo(r.queue.upNext.marks[2].key)
  r.jumpedTo(r.queue.upNext.marks[3].key)
  r.jumpedTo(99)
  r.start(album(12), 4)
  r.setIndex(6)
  r.jumpedTo(r.queue.upNext.marks[1].key)
  r.start(album(80), 0)
  r.setIndex(70)
  r.jumpedTo(r.queue.upNext.marks[19].key)
  r.setIndex(r.jumpedTo(r.queue.upNext.marks[20].key).index)
  r.start(album(3), 0)
  r.setIndex(2)
  r.toppedUp('all')
  r.ended()
  r.toppedUp('all')
  r.setIndex(r.jumpedTo(r.queue.upNext.marks[0].key).index)
  r.withRepeat('off')
})
scenario('(2.1.3) Shuffle off after a jump in a shuffle: the album from that song\'s place', (r, { album }) => {
  r.seeded(2).start(album(6), 0, true)
  r.setIndex(r.jumpedTo(r.queue.upNext.marks[3].key).index)
  r.withShuffle(false)
})
scenario('(2.1.3) Previous across songs added: the list drawn through them, rows, moves and removals by unit', (r, { album, track }) => {
  //? 4 playing, a and b played next, then Previous to 3: the list is 4, a, b, 5, 6 (190ebaa drew only 4)
  r.start(album(6), 0)
  r.setIndex(3)
  r.withNext([track('a'), track('b')])
  r.previous()
  r.view('off')
  r.keep('across')
  r.movedKey(r.keyOf('b'), 0)
  r.use('across')
  r.withoutKey(r.keyOf('a'))
  r.use('across')
  r.withoutAdded()
  r.setIndex(r.jumpedTo(r.keyOf('5')).index)
  r.view('off')
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
  REPEATS: U.REPEATS, RESTART_AFTER_SECONDS: Q.RESTART_AFTER_SECONDS, HISTORY_BACK: U.HISTORY_BACK,
}

/* ===== upnext.sim.cjs's property loop (:207-262), its every call as there, each run's last queue digested ===== */

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
      const op = pick(14)
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
        if (op === 8 || op === 12) {
          //? (2.1.3) 12: a row of History's tap; 8: a row of Up Next's - its keys mostly, any key of the queue's, or none
          const drawnHistory = U.historyRows(queue)
          const key = op === 12 && drawnHistory.length ? drawnHistory[pick(drawnHistory.length)].key
            : random() < 0.5 ? someKey() : queue.upNext.marks[pick(queue.upNext.marks.length)].key
          const jumped = U.jumpedTo(queue, key)
          if (jumped) queue = at(jumped.queue, jumped.index)
        } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = at(queue, next) }
        else if (op === 13) {
          const b = U.backward(queue, 0)
          if (b.kind === 'go') queue = U.wentBack(queue, b.index)
        } else queue = ended(queue)
        queue = U.toppedUp(queue, repeat, random)
      }
    }
    digests.push(fnv1a(canonical(queue)))
  }
  return digests
}

/* ===== resume (lib/resume.ts): the snapshot the web writes and reads, and what is put back ===== */

const SETTINGS = ['auto', 'song', 'album', 'off']
const RESUME_TRIGGERS = ['wait', 'position', 'pause', 'hidden']
const PROTO = new Set(Object.getOwnPropertyNames(Object.prototype))

/** A piece of a source file the phone mirrors, found by its pattern - or the export stops, naming it. */
function piece(file, pattern, what) {
  const found = fs.readFileSync(path.join(REPO, file), 'utf8').match(pattern)
  if (!found) throw new Error(`${file} no longer has ${what} as the exporter reads it: update the exporter and the Swift port`)
  return found
}
//? shuffledTrack is one line over toQueueTrack: the line is checked as it is, and only the two functions are hashed
//? (api.ts and useShuffleFeed.ts change for everything else they hold)
const toQueueTrackText = piece('ui/src/player/api.ts', /export function toQueueTrack\([\s\S]*?\n}\n/, 'toQueueTrack')[0]
const shuffledTrackText = piece('ui/src/app/useShuffleFeed.ts', /export function shuffledTrack\([\s\S]*?\n}\n/, 'shuffledTrack')[0]
if (!shuffledTrackText.includes("return toQueueTrack(song, { id: song.albumId ?? '', name: song.album ?? '' })")) {
  throw new Error('useShuffleFeed.ts shuffledTrack changed: update the exporter and Resume.swift shuffledTrack')
}
const shuffledTrack = (song) => API.toQueueTrack(song, { id: song.albumId ?? '', name: song.album ?? '' })
const resumeMadeFrom = {
  ...Object.fromEntries(RESUME_SOURCES.map((file) => [file, sha256(fs.readFileSync(path.join(REPO, file)))])),
  'ui/src/player/api.ts toQueueTrack': sha256(toQueueTrackText),
  'ui/src/app/useShuffleFeed.ts shuffledTrack': sha256(shuffledTrackText),
}

/* ===== the controllers, ported by hand (see the header): their sources' pieces hashed ===== */

/** Pieces of a source file a hand port follows, each found exactly once - or the export stops, naming it. */
function handPieces(file, swift, patterns) {
  const text = fs.readFileSync(path.join(REPO, file), 'utf8')
  const hashes = {}
  for (const [what, pattern] of Object.entries(patterns)) {
    const found = [...text.matchAll(pattern)]
    if (found.length !== 1) {
      throw new Error(`${file} has ${found.length} of ${what} as the exporter finds it (1 wanted): update the exporter, and read ${swift} against the change`)
    }
    hashes[`${file} ${what}`] = sha256(found[0][0])
    BY_HAND[`${file} ${what}`] = swift
  }
  return hashes
}
/** made_from's names of a hand-ported piece -> the Swift file that ports it. */
const BY_HAND = {}
//? usePlayer.ts: an inner function of the hook (4 spaces in), or an action (6), whole - its own //? lines included
const playerFunction = (name) => new RegExp(`\\n {4}function ${name}\\([^\\n]*\\{\\n[\\s\\S]*?\\n {4}}\\n`, 'g')
const playerAction = (name) => new RegExp(`\\n {6}${name}\\([^\\n]*\\{\\n[\\s\\S]*?\\n {6}},\\n`, 'g')
const QUEUE_CONTROLLER = 'ios/DeadwaxKit/Sources/DeadwaxCore/QueueController.swift'
Object.assign(madeFrom, handPieces('ui/src/player/usePlayer.ts', QUEUE_CONTROLLER, {
  ...Object.fromEntries(['catchUp', 'replaceUpcoming', 'apply', 'edit', 'runHeld', 'topUp', 'addSongs', 'songLength']
    .map((name) => [name, playerFunction(name)])),
  ...Object.fromEntries(['playTracks', 'next', 'previous', 'setShuffle', 'setRepeat', 'playNext', 'playLast', 'jumpTo',
    'moveInQueue', 'removeFromQueue', 'clearPlayingNext', 'extendQueue', 'restoreQueue']
    .map((name) => [`actions.${name}`, playerAction(name)])),
  "onEnded's Repeat": /\n {6}if \(state\.repeat !== 'off' && nextIndex\(state\.queue\) === null\) state\.queue = toppedUp\(state\.queue, state\.repeat\)\n/g,
  "onFailure's skip": /\n {6}const skipTo = action\.kind === 'skip' \? pastCopies\(state\.queue, action\.index\) : null\n/g,
}))
//? useResume.ts: createResume whole, with the two helpers above it (sameIds, signature)
Object.assign(resumeMadeFrom, handPieces('ui/src/app/useResume.ts', 'ios/DeadwaxKit/Sources/DeadwaxCore/ResumeController.swift', {
  createResume: /\nconst sameIds = [\s\S]*?\nexport function createResume\(\): Resume \{\n[\s\S]*?\n}\n/g,
}))

const UA_IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1'
const resumeConstants = {
  RESUME_MAX: R.RESUME_MAX, RESUME_BEFORE: R.RESUME_BEFORE, RESUME_SNAPSHOT_MAX: R.RESUME_SNAPSHOT_MAX,
  RESUME_EVERY_S: R.RESUME_EVERY_S, RESUME_FULL_WAIT_MS: R.RESUME_FULL_WAIT_MS, RESUME_AT_WAIT_MS: R.RESUME_AT_WAIT_MS,
  RESUME_RECHECK_MS: R.RESUME_RECHECK_MS, DEADWAX_CLIENT: R.DEADWAX_CLIENT,
  //? what the web calls Safari on an iPhone - the phone's own label
  iPhoneLabel: R.deviceLabel(UA_IPHONE, 5),
  MARGIN_MS: Number(piece('ui/src/app/useResume.ts', /\nconst MARGIN_MS = (\d+)\n/, 'MARGIN_MS')[1]),
  OWED_ORDER: [...piece('ui/src/app/useResume.ts', /\nconst OWED_ORDER: readonly SaveTrigger\[\] = \[([^\]]*)\]/, 'OWED_ORDER')[1].matchAll(/'(\w+)'/g)].map((m) => m[1]),
  DEVICE_LETTERS: piece('ui/src/state/persisted.ts', /\nconst DEVICE_LETTERS = '([^']+)'\n/, 'DEVICE_LETTERS')[1],
  DEVICE_ID: piece('ui/src/state/persisted.ts', /\nconst DEVICE_ID = \/(.+)\/\n/, 'DEVICE_ID')[1],
  DEVICE_LENGTH: Number(piece('ui/src/state/persisted.ts', /const bytes = new Uint8Array\((\d+)\)/, 'the device id\'s length')[1]),
  playerDevice: piece('ui/src/state/persisted.ts', /\n {2}playerDevice: '([^']+)',\n/, 'STORAGE_KEYS.playerDevice')[1],
  playerNormalization: piece('ui/src/state/persisted.ts', /\n {2}playerNormalization: '([^']+)',\n/, 'STORAGE_KEYS.playerNormalization')[1],
  //? sorted: the set is what matters, and the order Node lists them in could change between versions
  prototypeNames: Object.getOwnPropertyNames(Object.prototype).sort(),
}

/** Resume's songs, one per (level, id, the rest): `"<level>:<id>"` names one ("album:1", ":x" for none) - and
 *  `"<level>:<id>#2"` another song under the same id and level (a case's variant of one); the table holds each
 *  whole, its level with it. The same id at two levels is two songs here, as the snapshot's readers make them. */
class LevelledSongs {
  constructor() { this.byKey = new Map() }
  key(track) {
    const fields = {
      id: track.id, title: track.title, artist: track.artist, album: track.album, albumId: track.albumId,
      coverArt: track.coverArt, duration: track.duration, contentType: track.contentType, suffix: track.suffix,
      sampleRate: track.sampleRate, bitDepth: track.bitDepth, channels: track.channels,
    }
    for (const name of Object.keys(track)) if (!(name in fields) && name !== 'level') throw new Error(`a song with a field ${name}`)
    for (const name of ['title', 'artist', 'album']) if (typeof fields[name] !== 'string') throw new Error(`a song with no ${name}`)
    if (track.level !== undefined) fields.level = track.level
    const base = `${track.level ?? ''}:${track.id}`
    for (let n = 1; ; n++) {
      const key = n === 1 ? base : `${base}#${n}`
      const known = this.byKey.get(key)
      if (!known) { this.byKey.set(key, fields); return key }
      if (JSON.stringify(known) === JSON.stringify(fields)) return key
    }
  }
  table() { return Object.fromEntries([...this.byKey].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) }
}

/** A queue as the Swift test rebuilds it: song keys, the index, and Up Next's account (absent for a plain queue) - its
 *  id among it, or null for one made since `madeFrom` (madeIds' length then: a queue read back that was given a new id -
 *  the Swift test gives it its own). */
function queueRecord(queue, songs, madeFrom = null) {
  const out = { tracks: queue.tracks.map((t) => songs.key(t)), index: queue.index }
  const state = queue.upNext
  if (!state) return out
  if (typeof state.id !== 'string') throw new Error('a queue with no id')
  const fresh = madeFrom !== null && madeIds.indexOf(state.id, madeFrom) >= 0
  out.upNext = {
    id: fresh ? null : state.id,
    marks: state.marks.map((m) => [m.key, FROM[m.from], m.at, m.pass]), source: state.source.map((t) => songs.key(t)),
    shuffle: state.shuffle, nextKey: state.nextKey, startedAt: state.startedAt, left: state.left.map((gone) => [gone.pass, gone.at]),
  }
  if (state.paged) out.upNext.paged = pagedOf(state.paged)
  if (state.pagedRounds) out.upNext.pagedRounds = state.pagedRounds.map((held) => ({ pass: held.pass, paged: pagedOf(held.paged) }))
  return out
}

/**
 * Snapshot v1 written out by hand, key by key, as Resume.swift's toSave writes it - the form the phone was built
 * to: keys in this order; `extra`'s songs with their four nullable fields written as null, the source's songs
 * outside the window only, the first of each id, none named as Object.prototype's own (`id in extra`), the keys
 * JavaScript lists first (array indexes) first; `paged`, its `level` and `pagedRounds` left out when absent. Every
 * snapshot recorded must be this text: a change of the form stops the export here rather than reaching the phone
 * as a mismatch.
 */
function referenceSnapshot(queue) {
  const state = queue.upNext
  if (!state) return null
  const { start, end } = R.windowOf(queue.tracks.length, queue.index)
  const entries = queue.tracks.slice(start, end)
  const inWindow = new Set(entries.map((t) => t.id))
  const order = []
  const kept = new Map()
  for (const t of state.source) if (!inWindow.has(t.id) && !kept.has(t.id) && !PROTO.has(t.id)) { kept.set(t.id, t); order.push(t.id) }
  const isIndex = (key) => /^(0|[1-9][0-9]*)$/.test(key) && Number(key) <= 4294967294
  const keys = [...order.filter(isIndex).sort((a, b) => Number(a) - Number(b)), ...order.filter((key) => !isIndex(key))]
  const q = (value) => JSON.stringify(value)
  const char = (t) => (t.level === 'album' ? 'a' : t.level === 'track' ? 't' : '-')
  const song = (t) => `{"id":${q(t.id)},"title":${q(t.title)},"artist":${q(t.artist)},"album":${q(t.album)},` +
    `"albumId":${q(t.albumId)},"coverArt":${q(t.coverArt)},"duration":${q(t.duration)},"contentType":${q(t.contentType)},` +
    `"suffix":${q(t.suffix)},"sampleRate":${q(t.sampleRate)},"bitDepth":${q(t.bitDepth)},"channels":${q(t.channels)}}`
  const paged = (p) => `{"token":${q(p.token)},"total":${q(p.total)},"fetched":${q(p.fetched)},"scope":${q(p.scope)}` +
    `${p.level !== undefined ? `,"level":${q(p.level)}` : ''}}`
  return `{"v":1,"id":${q(state.id)},"levels":${q(entries.map(char).join(''))},` +
    `"marks":[${state.marks.slice(start, end).map((m) => `[${m.key},"${FROM[m.from]}",${m.at},${m.pass}]`).join(',')}],` +
    `"source":[${state.source.map((t) => q(t.id)).join(',')}],"sourceLevels":${q(state.source.map(char).join(''))},` +
    `"extra":{${keys.map((key) => `${q(key)}:${song(kept.get(key))}`).join(',')}},` +
    `"shuffle":${q(state.shuffle)},"nextKey":${q(state.nextKey)},"startedAt":${q(Math.max(0, state.startedAt - start))},` +
    `"left":[${state.left.map((gone) => `[${gone.pass},${gone.at}]`).join(',')}]` +
    `${state.paged ? `,"paged":${paged(state.paged)}` : ''}` +
    `${state.pagedRounds ? `,"pagedRounds":[${state.pagedRounds.map((held) => `{"pass":${q(held.pass)},"paged":${paged(held.paged)}}`).join(',')}]` : ''}}`
}

/** (2.1.15) A queue id given by hand (startUpNext's `id`), where the Swift test makes the same queue itself - the
 *  recipes', the reading cases' base. A queue's id in the form queueId makes. */
const QUEUE_ID = 'mhyx7k2c-a1b2c3d4'
/** (2.1.15) A snapshot as written without the queue's id - by the web before 2.1.15 and the phone before 0.8, which the
 *  phone still reads (a new id given, or the held queue's: fromSnapshot's `holding`). */
const withoutId = (snapshot, id) => {
  const member = `"id":${JSON.stringify(id)},`
  if (!snapshot.startsWith(`{"v":1,${member}`)) throw new Error('a snapshot without its id second')
  return snapshot.replace(member, '')
}

/** toSave of a queue, its snapshot held to the reference writer's text - the form the phone writes, its id second (or,
 *  over the cap, to none). */
function saved(queue, position) {
  const saving = R.toSave(queue, position)
  const reference = referenceSnapshot(queue)
  const wanted = reference !== null && reference.length <= R.RESUME_SNAPSHOT_MAX ? reference : null
  if (saving.snapshot !== wanted) {
    throw new Error(`toSave's snapshot is not the form the phone writes:\n  ${String(saving.snapshot).slice(0, 300)}\n  ${String(wanted).slice(0, 300)}`)
  }
  return saving
}

/** 32-bit FNV-1a over a string's UTF-16 units, as eight hex digits (fnv1a's, for any text). */
const unitHash = (text) => fnv1a(text)

const resumeSongs = new LevelledSongs()
const record = (queue, madeFrom = null) => queueRecord(queue, resumeSongs, madeFrom)
const resumeCases = []
//? resume.sim.cjs's songs: Mezzanine's, with a cover
const rTrack = (id, fields = {}) => ({
  id, title: `song ${id}`, artist: 'Massive Attack', album: 'Mezzanine', albumId: 'mez', coverArt: 'al-mez',
  duration: 200, contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2, ...fields,
})
const rAlbum = (n, prefix = '', fields = {}) => Array.from({ length: n }, (_, i) => rTrack(`${prefix}${i + 1}`, fields))
const atIndex = (queue, index) => ({ ...queue, index })
const bareTrack = ({ level: _level, ...rest }) => rest
const parkMiller = (seed) => { const generator = new ParkMiller(seed); return () => generator.next() }
/** A song of Navidrome's as GET /queue sends it (SHUFFLE_FIELDS), from a queue entry - only the keys it has. */
const navidromeSong = (t) => {
  const song = { id: t.id, title: t.title, artist: t.artist, album: t.album, albumId: t.albumId, coverArt: t.coverArt,
    duration: t.duration, contentType: t.contentType, suffix: t.suffix, samplingRate: t.sampleRate, bitDepth: t.bitDepth, channelCount: t.channels }
  for (const name of Object.keys(song)) if (song[name] === null) delete song[name]
  return song
}

// the tables (resume.sim.cjs:288-290, 379, 402)
for (const [count, index] of [[10, 3], [5000, 0], [5000, 100], [2500, 2200], [3000, 9999], [0, 0], [1, 0], [1, -5],
  [51, 50], [52, 51], [2050, 2049], [-3, 0], [2000, 1999], [2001, 2000], [20, 5]]) {
  const { start, end } = R.windowOf(count, index)
  resumeCases.push({ kind: 'window', count, index, start, end })
}
for (const setting of SETTINGS) {
  for (const level of ['album', 'track', null]) resumeCases.push({ kind: 'relevel', level, setting, result: R.relevel(level ?? undefined, setting) ?? null })
}
for (const from of [{ device: 'Mac' }, { device: 'iPhone' }, { device: 'Android phone' }, { device: 'Echo' }, { device: 'ipad' },
  { device: 'Uber' }, { device: 'Windows PC' }, { device: 'browser' }, { app: 'Symfonium' }, { app: 'amperfy' }, null]) {
  for (const shared of [false, true]) resumeCases.push({ kind: 'pickedUp', from, shared, result: R.pickedUpWords(from, shared) })
}

/** A toSave case, and its snapshot read back at its index under every setting (the web's text the phone reads) - and,
 *  (2.1.15) as written before the queue's id (`withoutId`), read as a queue given a new one. */
function saveCase(label, queue, position) {
  const saving = saved(queue, position)
  resumeCases.push({ kind: 'toSave', label, queue: record(queue), position, saving })
  if (saving.snapshot !== null) {
    const tracks = queue.tracks.slice(saving.start, saving.start + saving.ids.length).map(bareTrack)
    for (const setting of SETTINGS) fromCase(`${label}: read back (${setting})`, saving.snapshot, tracks, saving.index, setting)
    fromCase(`${label}: as written before the queue's id, read back`, withoutId(saving.snapshot, queue.upNext.id), tracks, saving.index)
  }
  return saving
}
/** A fromSnapshot case - with `holding`, the queue the player holds (2.1.15), when it has one. */
function fromCase(label, snapshot, tracks, index, setting = 'auto', holding = null) {
  const madeFrom = madeIds.length
  const back = R.fromSnapshot(snapshot, tracks, index, setting, holding)
  resumeCases.push({
    kind: 'fromSnapshot', label, snapshot, tracks: tracks.map((t) => resumeSongs.key(t)), index, setting,
    ...(holding ? { holding: record(holding) } : {}), result: back && record(back, madeFrom),
  })
  return back
}
function resumedCase(label, answer, setting = 'auto', device = 'phone-1', holding = null) {
  const madeFrom = madeIds.length
  const back = R.resumed(answer, answer.tracks.map(shuffledTrack), setting, device, holding)
  resumeCases.push({
    kind: 'resumed', label, answer: JSON.stringify(answer), setting, device, ...(holding ? { holding: record(holding) } : {}),
    result: back && { queue: record(back.queue, madeFrom), position: back.position, from: back.from, exact: back.exact },
  })
  return back
}

// toSave: resume.sim.cjs's small queues (:286-290), and the spec's examples
saveCase('a 20-song list at 5: all of it, startedAt 5', U.startUpNext(rAlbum(20), 5), 3)
saveCase('a plain queue: no account to save', { tracks: rAlbum(2), index: 0 }, 0)
saveCase('the empty queue', Q.EMPTY_QUEUE, 0)
saveCase('an album of 3 tapped at its second, Play Next of one song at track level',
  U.withNext(U.startUpNext(rAlbum(3, '', { level: 'album' }), 1), [rTrack('x', { level: 'track' })]), 61.5)
saveCase('Repeat One over two songs (Normalization Off): a copy\'s at its original\'s place',
  U.toppedUp(U.withRepeat(U.startUpNext(rAlbum(2), 0), 'one'), 'one'), 12)
{
  let rounds = U.toppedUp(U.withRepeat(U.startUpNext(rAlbum(4, 'r', { level: 'album' }), 1), 'all'), 'all')
  rounds = U.toppedUp(atIndex(rounds, 3), 'all')
  saveCase('Repeat All, two rounds queued', rounds, 30)
  saveCase('...gone back by Previous before where the list began', atIndex(rounds, 0), 0)
}
{
  let shuffled = U.startUpNext(rAlbum(7, 'h'), 2, true, parkMiller(77))
  shuffled = U.withoutKey(shuffled, shuffled.upNext.marks[4].key)
  const jumped = U.jumpedTo(shuffled, shuffled.upNext.marks[5].key)
  shuffled = atIndex(jumped.queue, jumped.index)
  shuffled = U.toppedUp(U.withRepeat(shuffled, 'all'), 'all', parkMiller(78))
  saveCase('Shuffle on, songs left out of a round, Repeat All\'s next round shuffled', shuffled, 100.25)
}
{
  const page = rAlbum(3, 'p', { level: 'track' })
  const paged = U.startUpNext(page, 0, false, parkMiller(5), { token: 'tok', total: 9, fetched: 3, scope: 'yours', level: 'track' })
  saveCase('a library\'s shuffle, a page in, its level kept', paged, 5)
  const unlevelled = U.startUpNext(rAlbum(2, 'u'), 0, false, parkMiller(5), { token: 'tok2', total: 2, fetched: 2, scope: 'store' })
  saveCase('...Normalization Off: no level on it or its songs', unlevelled, 0)
  //? the order whole, Repeat All: a fresh order as the next round - the last one held by its round
  let more = U.withMore(unlevelled, 'tok2', rAlbum(2, 'v'), { token: 'tok3', total: 4, fetched: 0, scope: 'store' })
  saveCase('...a fresh order after the whole one: the round before held in pagedRounds', more, 0)
  more = U.withRepeat(atIndex(more, 2), 'off')
  saveCase('...Repeat off back in the later round', more, 0)
  let empty = U.withMore(unlevelled, 'tok2', rAlbum(1, 'w'), { token: 'tok4', total: 5, fetched: 0, scope: 'store' })
  empty = U.withRepeat(atIndex(empty, 0), 'off')
  saveCase('...back in the first round: pagedRounds left as []', empty, 0)
  if (!Array.isArray(empty.upNext.pagedRounds) || empty.upNext.pagedRounds.length !== 0) {
    throw new Error('the pagedRounds: [] case no longer makes one: find another way to it')
  }
}
{
  //? every character JSON.stringify escapes, and some it doesn't - in titles, artists, ids, and `extra`'s keys
  const odd = [
    ['a/b', 'AC/DC'], ['q"u', 'say "hi"'], ['b\\s', 'back\\slash'], ['t\tab', 'tab\there'], ['e\u001b', 'escape\u001bhere'],
    ['nul\u0000', 'nul\u0000x'], ['ctl\u001f\u0001', 'ctl\u001f\u0001'], ['accé', 'Beyoncé'], ['kana', '夜に駆ける'],
    ['emo', 'party 😀 time'], ['sep', 'line\u2028para\u2029'], ['del', 'del\u007f'], ['nl', 'two\nlines\r\n'],
    ['bf', 'b\bf\f'], ['bom', '\ufeffbom'],
  ].map(([id, title]) => rTrack(`odd-${id}`, { title, artist: `by ${title}`, album: `on ${title}` }))
  const playing = rAlbum(2, 'o')
  saveCase('titles and ids with what JSON escapes, and what it doesn\'t - in the window',
    U.startUpNext([...odd, ...playing], 0), 0)
  saveCase('...and outside it, kept whole in `extra`', atIndex(U.startUpNext([...odd, ...rAlbum(60, 'o')], 70), 70), 1)
}
{
  //? ids JavaScript lists first in an object (array indexes, ascending), and ids it doesn't
  const ids = ['60', '59', '58', 'abc', '57', '56', '55', '54', '53', '52', '01', '-1', '4294967294', '4294967295', '1.5', '0', '007', '1e3', ' 1']
  const tracks = [...ids.map((id) => rTrack(id)), ...rAlbum(60, 'in')]
  saveCase('ids that are array indexes, outside the window: first in `extra`, ascending', atIndex(U.startUpNext(tracks, ids.length + 55), ids.length + 55), 0)
}
{
  //? Object.prototype's own names as ids outside the window: the web's `id in extra` is true for them
  const tracks = [...['constructor', 'toString', '__proto__', 'hasOwnProperty', 'valueOf', 'plain'].map((id) => rTrack(id)), ...rAlbum(55, 'pn')]
  saveCase('ids that are Object.prototype\'s names, outside the window: never kept whole', atIndex(U.startUpNext(tracks, 60), 60), 0)
}
{
  //? durations of every shape a Number writes, and the four nullable fields as null
  const shapes = [200.5, 0.1 + 0.2, 1e-7, 1.5e-7, 0.000001, 123456789.123, 1e21, 1.5e300, 5e-324, 1.7976931348623157e308,
    2 ** 53, 2 ** 60, 1e20, 123e18, -0, -12.5, 0, 0.5, 1 / 3, 2.5e-5, 100]
  const tracks = shapes.map((duration, i) => rTrack(`dur${i}`, { duration }))
  const nulls = rTrack('nulls', { albumId: null, coverArt: null, contentType: null, suffix: null, sampleRate: 0, bitDepth: 0, channels: 0 })
  saveCase('durations of every shape, and a song with no album id, cover or format: outside the window',
    atIndex(U.startUpNext([...tracks, nulls, ...rAlbum(60, 'dd')], 80), 80), 0)
}
saveCase('120 songs played at 100: 50 before, `extra` the 50 before them', atIndex(U.startUpNext(rAlbum(120, 'w'), 30), 100), 42)

// toSave from recipes (too big to keep as queues): resume.sim.cjs:276 and :281, and the cap in UTF-16 units
/** The queue a recipe makes - rebuilt the same way by the Swift test, under the same id (QUEUE_ID). */
function fromRecipe(recipe) {
  const tracks = rAlbum(recipe.n, recipe.prefix)
  if (recipe.pad) {
    const at = tracks.findIndex((t) => t.id === recipe.pad.id)
    tracks[at] = { ...tracks[at], title: `${tracks[at].title}${recipe.pad.unit.repeat(recipe.pad.count)}${'x'.repeat(recipe.pad.tail)}` }
  }
  return atIndex(U.startUpNext(tracks, recipe.start, false, undefined, undefined, recipe.id ?? QUEUE_ID), recipe.index)
}
function recipeCase(label, given) {
  const recipe = { id: QUEUE_ID, ...given }
  const saving = saved(fromRecipe(recipe), recipe.position)
  resumeCases.push({
    kind: 'toSaveRecipe', label, recipe,
    saving: {
      count: saving.ids.length, first: saving.ids[0] ?? null, last: saving.ids[saving.ids.length - 1] ?? null, index: saving.index,
      start: saving.start, length: saving.snapshot === null ? null : saving.snapshot.length,
      hash: saving.snapshot === null ? null : unitHash(saving.snapshot), head: saving.snapshot === null ? null : saving.snapshot.slice(0, 120),
    },
  })
  return saving
}
recipeCase('a 5,000-song list from its first: its next 2,000, and a snapshot over the cap', { n: 5000, prefix: '', start: 0, index: 0, position: 0 })
recipeCase('playing the 101st of 2,500: 50 before it, 2,000 in all, startedAt floored at 0', { n: 2500, prefix: '', start: 30, index: 100, position: 7 })
for (const unit of ['x', '😀']) {
  const base = { n: 2400, prefix: 'cap-', start: 50, index: 50, position: 0 }
  const length = (pad) => R.toSave(fromRecipe({ ...base, pad }), 0).snapshot?.length ?? referenceSnapshot(fromRecipe({ ...base, pad })).length
  const bare = length({ id: 'cap-2400', unit, count: 0, tail: 0 })
  const count = Math.floor((R.RESUME_SNAPSHOT_MAX - bare) / unit.length)
  const tail = (R.RESUME_SNAPSHOT_MAX - bare) % unit.length
  const kept = recipeCase(`the cap: exactly ${R.RESUME_SNAPSHOT_MAX} UTF-16 units, padded with ${unit === 'x' ? 'x' : 'an emoji (two units, one code point, four bytes)'}: kept`,
    { ...base, pad: { id: 'cap-2400', unit, count, tail } })
  const over = recipeCase('...one unit more: left out', { ...base, pad: { id: 'cap-2400', unit, count, tail: tail + 1 } })
  if (kept.snapshot?.length !== R.RESUME_SNAPSHOT_MAX || over.snapshot !== null) throw new Error('the cap cases missed the cap')
}

// fromSnapshot: snapshots broken, or written another way than toSave writes them, as the web reads them
{
  const list = rAlbum(5)
  const queue = U.withNext(U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2, false, undefined, undefined, QUEUE_ID), [rTrack('x', { level: 'track' })])
  const base = saved(queue, 61).snapshot
  const tracks = queue.tracks.map(bareTrack)
  const made = () => JSON.parse(base)
  const text = (object) => JSON.stringify(object)
  const swap = (from, to) => { if (!base.includes(from)) throw new Error(`no ${from} in the base snapshot`); return base.replace(from, to) }
  const cases = [
    ['as toSave wrote it', base],
    ['v as 1.0', swap('{"v":1,', '{"v":1.0,')], ['v as 1e0', swap('{"v":1,', '{"v":1e0,')], ['v as "1"', swap('{"v":1,', '{"v":"1",')],
    ['v as true', swap('{"v":1,', '{"v":true,')], ['no v', text({ ...made(), v: undefined })], ['v 2', text({ ...made(), v: 2 })],
    ['a key twice: the last one read', `${swap('{"v":1,', '{"v":2,').slice(0, -1)},"v":1}`],
    ['...the last one wrong', `${base.slice(0, -1)},"v":2}`],
    ['pretty-printed with spaces', JSON.stringify(made(), null, 2)], ['with tabs and CRLF', JSON.stringify(made(), null, '\t').replace(/\n/g, '\r\n')],
    ['space before and after', ` \t\r\n${base}\n `], ['a byte-order mark first', `\ufeff${base}`], ['something after it', `${base}x`],
    ['a comma after its last key', `${base.slice(0, -1)},}`], ['cut short', base.slice(0, -1)],
    ['levels with an escape', swap('"levels":"aa', '"levels":"\\u0061a')], ['levels escaped in capitals', swap('"levels":"aa', '"levels":"\\u0041a')],
    ['a mark key 1.0', swap('[1,"s",1,0]', '[1.0,"s",1,0]')], ['a mark key 1e0', swap('[1,"s",1,0]', '[1e0,"s",1,0]')],
    ['a mark key -0', swap('[0,"s",0,0]', '[-0,"s",0,0]')], ['a mark key 0.5', swap('[0,"s",0,0]', '[0.5,"s",0,0]')],
    ['a mark key "0"', swap('[0,"s",0,0]', '["0","s",0,0]')], ['a mark key 01', swap('[1,"s",1,0]', '[01,"s",1,0]')],
    ['a mark of 3', swap('[0,"s",0,0]', '[0,"s",0]')], ['a mark of 5', swap('[0,"s",0,0]', '[0,"s",0,0,0]')],
    ['a mark from "source"', swap('[0,"s",0,0]', '[0,"source",0,0]')], ['a mark from "S"', swap('[0,"s",0,0]', '[0,"S",0,0]')],
    ['a source mark naming another song', swap('[0,"s",0,0]', '[0,"s",1,0]')], ['a source mark of pass -1', swap('[0,"s",0,0]', '[0,"s",0,-1]')],
    ['an added mark of pass 0', text({ ...made(), marks: made().marks.map((m) => (m[1] === 'a' ? [m[0], 'a', -1, 0] : m)) })],
    ['a copy mark at -1', text({ ...made(), marks: made().marks.map((m, i) => (i === 4 ? [m[0], 'o', -1, 7] : m)) })],
    ['a copy mark at -2', text({ ...made(), marks: made().marks.map((m, i) => (i === 4 ? [m[0], 'o', -2, 0] : m)) })],
    ['a key at nextKey', text({ ...made(), nextKey: 5 })], ['nextKey 6e0', swap('"nextKey":6', '"nextKey":6e0')],
    ['nextKey past a Double', swap('"nextKey":6', '"nextKey":1e400')], ['nextKey 6.5', swap('"nextKey":6', '"nextKey":6.5')],
    ['startedAt "2"', text({ ...made(), startedAt: '2' })], ['startedAt past the songs', text({ ...made(), startedAt: 40 })],
    ['shuffle 0', text({ ...made(), shuffle: 0 })], ['left an item of 1', text({ ...made(), left: [[0]] })],
    ['left an item of 3', text({ ...made(), left: [[0, 1, 2]] })], ['left an item of 0.5', text({ ...made(), left: [[0, 0.5]] })],
    ['left two items, any numbers', text({ ...made(), left: [[0, 1], [-4, 99]] })], ['left an object', text({ ...made(), left: {} })],
    ['levels one short', text({ ...made(), levels: made().levels.slice(1) })], ['levels one long', text({ ...made(), levels: `${made().levels}a` })],
    ['levels an emoji pair long', text({ ...made(), levels: `${made().levels.slice(2)}😀` })],
    ['levels of other letters', text({ ...made(), levels: 'xyzTA-' })],
    ['sourceLevels one short', text({ ...made(), sourceLevels: made().sourceLevels.slice(1) })],
    ['source a number', text({ ...made(), source: [...made().source.slice(0, -1), 5] })], ['source a string', text({ ...made(), source: '12345' })],
    ['extra an array', text({ ...made(), extra: [] })], ['extra null', text({ ...made(), extra: null })],
    ['marks one short', text({ ...made(), marks: made().marks.slice(1) })], ['marks an object', text({ ...made(), marks: {} })],
    ['paged null', text({ ...made(), paged: null })], ['pagedRounds null', text({ ...made(), pagedRounds: null })],
    ['pagedRounds an object', text({ ...made(), pagedRounds: {} })], ['pagedRounds []', text({ ...made(), pagedRounds: [] })],
    ['pagedRounds with one', text({ ...made(), pagedRounds: [{ pass: 0, paged: { token: 't', total: 1, fetched: 1, scope: 'store' } }] })],
    ['pagedRounds with one of no pass', text({ ...made(), pagedRounds: [{ paged: { token: 't', total: 1, fetched: 1, scope: 'store' } }] })],
    ['pagedRounds with a pass 1.5', text({ ...made(), pagedRounds: [{ pass: 1.5, paged: { token: 't', total: 1, fetched: 1, scope: 'store' } }] })],
    ['paged', text({ ...made(), paged: { token: 't', total: 9, fetched: 6, scope: 'yours', level: 'album' } })],
    ['paged, no level', text({ ...made(), paged: { token: 't', total: 9, fetched: 6, scope: 'yours' } })],
    ['paged, level null', text({ ...made(), paged: { token: 't', total: 9, fetched: 6, scope: 'yours', level: null } })],
    ['paged, level "song"', text({ ...made(), paged: { token: 't', total: 9, fetched: 6, scope: 'yours', level: 'song' } })],
    ['paged, scope "all"', text({ ...made(), paged: { token: 't', total: 9, fetched: 6, scope: 'all' } })],
    ['paged, total 9.5', text({ ...made(), paged: { token: 't', total: 9.5, fetched: 6, scope: 'yours' } })],
    ['paged, a token 7', text({ ...made(), paged: { token: 7, total: 9, fetched: 6, scope: 'yours' } })],
    ['paged, more keys', text({ ...made(), paged: { token: 't', total: 9, fetched: 6, scope: 'store', extra: true } })],
    ['more keys than v1 has', text({ ...made(), later: { anything: [1, 2] } })],
    ['nested 900 deep, where nothing reads', text({ ...made(), extra: { unused: JSON.parse(`${'['.repeat(900)}${']'.repeat(900)}`) } })],
    ['an array', '[]'], ['a string', '"{}"'], ['null', 'null'], ['nothing', ''], ['a number', '1'],
  ]
  for (const [label, snapshot] of cases) fromCase(`a snapshot ${label}`, snapshot, tracks, 2)
  //? (2.1.15) the queue's id: as written since (second), and before (none) - read as a queue given a new one, unless
  //? it is the queue held (`holding`, sameQueue). Then ids of every other shape, which the web reads as none, the rest
  //? read as ever
  const idMember = `"id":${JSON.stringify(QUEUE_ID)},`
  if (!base.startsWith(`{"v":1,${idMember}`)) throw new Error('the base snapshot has no id second')
  const noId = withoutId(base, QUEUE_ID)
  for (const setting of SETTINGS) fromCase(`a snapshot as written before the queue's id (${setting})`, noId, tracks, 2, setting)
  const withId = (id) => base.replace(idMember, `"id":${id},`)
  for (const [label, snapshot] of [
    ['an id of 64 characters', withId(JSON.stringify('a'.repeat(64)))], ['an id of 65 characters', withId(JSON.stringify('a'.repeat(65)))],
    ['an id empty', withId('""')], ['an id with a space', withId('"q 1"')], ['an id with a dot', withId('"q.1"')],
    ['an id with an emoji pair escaped', withId('"q\\ud83d\\ude00"')], ['an id a number', withId('5')], ['an id null', withId('null')],
    ['an id an object', withId('{"id":"q"}')], ['an id an array', withId('["q"]')], ['an id true', withId('true')],
    ['an id of every letter it may have', withId('"AZaz09_-"')], ['an id escaped', withId('"\\u0071-1"')],
    ['an id first, before v', noId.replace('{"v":1,', `{${idMember}"v":1,`)],
    ['an id last', `${noId.slice(0, -1)},"id":${JSON.stringify(QUEUE_ID)}}`],
    ['an id twice', withId(`${JSON.stringify(QUEUE_ID)},"id":"other"`)],
    ['an id twice, the last not one', withId(`${JSON.stringify(QUEUE_ID)},"id":"not one"`)],
  ]) fromCase(`a snapshot with ${label}`, snapshot, tracks, 2)
  //? (2.1.15) read while the player holds a queue: saved without an id, the held queue's id kept when it is that queue
  const heldElsewhere = U.withNext(U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2, false, undefined, undefined, 'held-1'), [rTrack('x', { level: 'track' })])
  const tappedAgain = U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2, false, undefined, undefined, 'tapped-again')
  const another = U.startUpNext(rAlbum(5, 'other'), 0, false, undefined, undefined, 'another')
  const shuffledHeld = U.startUpNext(list, 2, true, parkMiller(11), undefined, 'shuffled')
  const moved = U.movedKey(heldElsewhere, 5, 1)
  for (const [label, holding] of [
    ['the queue it describes', heldElsewhere], ['that queue moved on a song', atIndex(heldElsewhere, 3)],
    ['that queue with a song moved', moved], ['the same album tapped again (keys from 0 again): the one case it can\'t tell', tappedAgain],
    ['another album', another], ['the same album shuffled (another song under a key)', shuffledHeld],
    ['a plain queue', { tracks: list, index: 0 }], ['nothing', Q.EMPTY_QUEUE],
  ]) {
    fromCase(`a snapshot written before the queue's id, read while the player holds ${label}`, noId, tracks, 2, 'auto', holding)
    fromCase(`a snapshot with its id, read while the player holds ${label}: its own id`, base, tracks, 2, 'auto', holding)
  }
  for (const [label, held, put] of [
    ['the same queue', heldElsewhere, queue], ['moved on', atIndex(heldElsewhere, 4), queue], ['a song moved', moved, queue],
    ['tapped again', tappedAgain, queue], ['another album', another, queue], ['shuffled', shuffledHeld, queue],
    ['a song removed', U.withoutKey(heldElsewhere, 3), queue], ['the song added gone', U.withoutAdded(heldElsewhere), queue],
    ['no key in common', U.startUpNext(list, 0, false, undefined, undefined, 'k'), { ...queue, upNext: { ...queue.upNext, marks: queue.upNext.marks.map((m) => ({ ...m, key: m.key + 50 })) } }],
    ['a plain queue held', { tracks: list, index: 0 }, queue], ['nothing held', Q.EMPTY_QUEUE, queue],
    ['a source one longer', U.startUpNext([...list, rTrack('6')], 2, false, undefined, undefined, 'longer'), queue],
  ]) resumeCases.push({ kind: 'sameQueue', label, held: record(held), put: record(put), result: R.sameQueue(held, put) })
  fromCase('an index past the songs', base, tracks, 6)
  fromCase('an index below 0', base, tracks, -1)
  fromCase('Navidrome\'s songs one short', base, tracks.slice(0, 5), 2)
  fromCase('a song of the list in neither Navidrome\'s songs nor `extra`', base, [...tracks.slice(0, 4), rTrack('q'), tracks[5]], 2)
  fromCase('another song where Navidrome had the one played next (an added mark names no song): read with it', base,
    [...tracks.slice(0, 3), rTrack('q'), ...tracks.slice(4)], 2)
  //? a song kept whole, read as the web's readSong reads one
  const withExtra = (song, more = {}) => text({ ...made(), source: [...made().source, 'z'], sourceLevels: `${made().sourceLevels}a`, extra: { ...made().extra, z: song }, ...more })
  const z = bareTrack(rTrack('z'))
  for (const [label, song] of [
    ['as it should be', z], ['a duration "200"', { ...z, duration: '200' }], ['no title', { ...z, title: undefined }],
    ['an album id 7', { ...z, albumId: 7 }], ['no album id', { ...z, albumId: undefined }], ['no cover, null', { ...z, coverArt: null }],
    ['an id of another', { ...z, id: 'y' }], ['a duration -1', { ...z, duration: -1 }], ['a bit depth 24, a rate 192000', { ...z, bitDepth: 24, sampleRate: 192000 }],
    ['more fields than it keeps', { ...z, level: 'track', track: 4, size: 100 }], ['a title with an emoji pair escaped', { ...z, title: 'party 😀' }],
    ['a channel count null', { ...z, channels: null }], ['an array', [z]],
  ]) fromCase(`a song kept whole: ${label}`, withExtra(song), tracks, 2)
  fromCase('a song kept whole: its emoji written as escapes', withExtra(z).replace('"title":"song z"', '"title":"song \\ud83d\\ude00 z\\/"'), tracks, 2)
  fromCase('a song kept whole: a duration past a Double', withExtra(z).replace(/("z":\{[^}]*"duration":)200/, '$11e400'), tracks, 2)
}

// savedLevels (:220): the levels of a snapshot that doesn't read whole
{
  const base = saved(U.withNext(U.startUpNext(rAlbum(5).map((t) => ({ ...t, level: 'album' })), 2), [rTrack('x', { level: 'track' })]), 61).snapshot
  for (const [snapshot, count] of [[base, 6], [base, 5], [base, 7], [null, 3], ['{', 2], ['null', 1], ['[]', 1], ['{"v":2,"levels":"aa"}', 2],
    ['{"v":1,"levels":"at-x"}', 4], ['{"v":1,"levels":"😀a"}', 3], ['{"v":1,"levels":"\\ud800a"}', 2], ['{"v":1.0,"levels":"a"}', 1],
    ['{"v":true,"levels":"a"}', 1], ['{"v":1,"levels":5}', 1], ['{"v":1,"levels":"t"}', 0], ['{"v":1,"levels":""}', 0], [base, 0]]) {
    resumeCases.push({ kind: 'savedLevels', snapshot, count, result: R.savedLevels(snapshot, count).map((level) => level ?? null) })
  }
}

// shuffledTrack: a song of the answer as a queue entry - the real toQueueTrack
for (const song of [
  { id: 'a', title: 'A', artist: 'Portishead', album: 'Dummy', albumId: 'nd-dummy', coverArt: 'al-1', duration: 200, contentType: 'audio/flac', suffix: 'flac', samplingRate: 44100, bitDepth: 16, channelCount: 2, track: 1, discNumber: 1 },
  { id: 'b', title: 'B' }, { id: 'c', title: '', albumId: null, coverArt: null }, { id: 'd', title: 'D', duration: 199.5, samplingRate: 96000, bitDepth: 24 },
]) resumeCases.push({ kind: 'shuffledTrack', song: JSON.stringify(song), result: shuffledTrack(song) })

// resumed (:296-374): what is put back from GET /queue's answer, as the wire sends it
{
  const list = rAlbum(5)
  const saving = saved(U.withNext(U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2), [rTrack('x', { level: 'track' })]), 61)
  const kept = (more = {}) => ({ rev: 4, ids_rev: 3, ids: saving.ids, index: saving.index, position: 61, snapshot: saving.snapshot, device: 'phone-1', label: 'iPhone', ...more })
  const songOf = (id) => navidromeSong(bareTrack(id === 'x' ? rTrack('x') : list.find((t) => t.id === id)))
  const navidrome = (keep) => saving.ids.filter((id) => keep(id)).map(songOf)
  const all = navidrome(() => true)
  const answer = (tracks, index, position, changed_by, keptQueue, shared = false) => ({ tracks, index, position, changed_by, shared, kept: keptQueue })
  for (const t of [...list, rTrack('x')]) {
    if (JSON.stringify(shuffledTrack(navidromeSong(bareTrack(t)))) !== JSON.stringify(bareTrack(t))) throw new Error('the answer\'s songs aren\'t the sim\'s')
  }
  for (const setting of SETTINGS) resumedCase(`exact: the account back, at kept.position, from this device (${setting})`, answer(all, 2, 61, 'deadwax', kept()), setting)
  resumedCase('...from another device: named by its label', answer(all, 2, 61, 'deadwax', kept()), 'auto', 'desk-2')
  resumedCase('...logins off (shared): the same', answer(all, 2, 61, 'deadwax', kept(), true), 'auto', 'desk-2')
  const made = () => JSON.parse(saving.snapshot)
  const withExtra = (song) => JSON.stringify({ ...made(), source: [...made().source, 'z'], sourceLevels: `${made().sourceLevels}a`, extra: { ...made().extra, z: song } })
  for (const [label, snapshot] of [['not JSON', '{nope'], ['v2', JSON.stringify({ ...made(), v: 2 })],
    ['a mark out of its source', JSON.stringify({ ...made(), marks: made().marks.map((m, i) => (i === 0 ? [m[0], 's', 99, 0] : m)) })],
    ['a key twice', JSON.stringify({ ...made(), marks: made().marks.map((m) => [0, m[1], m[2], m[3]]) })],
    ['startedAt below 0', JSON.stringify({ ...made(), startedAt: -1 })],
    ['an added mark with a place in the list', JSON.stringify({ ...made(), marks: made().marks.map((m) => (m[1] === 'a' ? [m[0], 'a', 3, 0] : m)) })],
    ['a copy\'s mark past the list', JSON.stringify({ ...made(), marks: made().marks.map((m, i) => (i === 4 ? [m[0], 'o', 99, 0] : m)) })],
    ...[['a duration in words', { duration: '200' }], ['no title', { title: undefined }], ['an album id a number', { albumId: 7 }]].map(([what, change]) =>
      [`a song kept whole with ${what}`, withExtra({ ...bareTrack(rTrack('z')), ...change })]),
    ['none', null], ['levels the wrong length', JSON.stringify({ ...made(), marks: [] })]]) {
    resumedCase(`a snapshot that doesn't read back (${label}): the same songs as a plain list, at the same song and second`, answer(all, 2, 61, 'deadwax', kept({ snapshot })))
  }
  resumedCase('...and with that song kept whole as it should be: the account back, the song in the list', answer(all, 2, 61, 'deadwax', kept({ snapshot: withExtra(bareTrack(rTrack('z'))) })))
  //? (2.1.15) the queue's id: kept from the snapshot; saved without one (an app before ids), a new one - or the held
  //? queue's, when it is the queue held
  const heldQueue = U.withNext(U.startUpNext(list.map((t) => ({ ...t, level: 'album' })), 2), [rTrack('x', { level: 'track' })])
  const unsaid = withoutId(saving.snapshot, JSON.parse(saving.snapshot).id)
  resumedCase('exact, its snapshot saved without an id: the account back, a new id', answer(all, 2, 61, 'deadwax', kept({ snapshot: unsaid })))
  resumedCase('...while the player holds that queue: its id kept', answer(all, 2, 61, 'deadwax', kept({ snapshot: unsaid })), 'auto', 'phone-1', heldQueue)
  resumedCase('...while the player holds another: a new id', answer(all, 2, 61, 'deadwax', kept({ snapshot: unsaid })), 'auto', 'phone-1', U.startUpNext(rAlbum(3, 'n'), 0))
  resumedCase('exact, its snapshot with its id, while the player holds another queue: the id saved', answer(all, 2, 61, 'deadwax', kept()), 'auto', 'phone-1', heldQueue)
  resumedCase('another app\'s, while the player holds a queue: a plain list, a new id', answer(all, 1, 5, 'Symfonium', null), 'auto', 'phone-1', heldQueue)
  {
    //? (review) an album tapped at song 5, a song played next, then Previous: before where playTracks began
    let live = U.withNext(U.startUpNext(rAlbum(10), 4), [rTrack('n')])
    live = atIndex(live, U.backward(live, 0).index)
    const save = saved(live, 12)
    const tracks = live.tracks.slice(save.start, save.start + save.ids.length).map(bareTrack).map(navidromeSong)
    resumedCase('Previous before where the album was started, as an app before 2.1.3 saved it (startedAt past the index): the account back - startedAt lowered to the song playing',
      answer(tracks, save.index, 12, 'deadwax', kept({ ids: save.ids, index: save.index, position: 12, snapshot: save.snapshot })), 'off')
    //? (2.1.3 review) the iPhone's 0.2 or the web's 2.1.2: an album started at 5, Previous to 4 - picked up, startedAt 3
    const old = atIndex(U.startUpNext(rAlbum(10), 4), 3)
    const oldSave = saved(old, 12)
    resumedCase('an album started at 5, Previous to 4, as 0.2 saved it: picked up with startedAt at 4\'s place',
      answer(old.tracks.slice(oldSave.start, oldSave.start + oldSave.ids.length).map(bareTrack).map(navidromeSong), oldSave.index, 12, 'deadwax',
        kept({ ids: oldSave.ids, index: oldSave.index, position: 12, snapshot: oldSave.snapshot })), 'off')
    saveCase('(2.1.3) Previous before where the album was started, as wentBack moves it: startedAt with it',
      U.wentBack(U.startUpNext(rAlbum(10), 4), 3), 12)
    let rounds = U.toppedUp(U.withRepeat(U.startUpNext(rAlbum(10), 4), 'all'), 'all')
    rounds = U.toppedUp(atIndex(rounds, 9), 'all')
    rounds = atIndex(rounds, 3)
    const save2 = saved(rounds, 0)
    resumedCase('...and under Repeat All, gone back before it: the list still the album once',
      answer(rounds.tracks.slice(save2.start, save2.start + save2.ids.length).map(bareTrack).map(navidromeSong), save2.index, 0, 'deadwax',
        kept({ ids: save2.ids, index: save2.index, position: 0, snapshot: save2.snapshot })), 'off')
    //? the snapshot made at one song, kept.index moved by another device's position save since
    const moved = saved(U.startUpNext(rAlbum(6, 'm', { level: 'album' }), 1), 30)
    resumedCase('kept.index moved by a position save since the snapshot: exact, the account at kept.index',
      answer(rAlbum(6, 'm').map(navidromeSong), 3, 44, 'deadwax', kept({ ids: moved.ids, index: 3, position: 44, snapshot: moved.snapshot, device: 'desk-2', label: 'Mac', rev: 9 })))
  }
  resumedCase('songs dropped, the one playing still there: a plain list of what is left, at it, levels carried', answer(navidrome((id) => id !== '2'), 2, 0, 'deadwax', kept()))
  resumedCase('...the one playing gone: the first survivor after it, at 0:00', answer(navidrome((id) => id !== '3'), 2, 0, 'deadwax', kept()))
  resumedCase('...the last one gone, nothing after it: the last survivor, at 0:00', answer(navidrome((id) => id !== '5'), 2, 0, 'deadwax', kept({ index: 5 })))
  resumedCase('...Off: no levels', answer(navidrome((id) => id !== '2'), 2, 0, 'deadwax', kept()), 'off')
  resumedCase('...By album: album throughout', answer(navidrome((id) => id !== '2'), 2, 0, 'deadwax', kept()), 'album')
  resumedCase('...a snapshot that isn\'t one: levels by song', answer(navidrome((id) => id !== '2'), 2, 0, 'deadwax', kept({ snapshot: '{' })))
  resumedCase('...kept.index past its ids: held to its last', answer(navidrome((id) => id !== '2'), 2, 0, 'deadwax', kept({ index: 40 })))
  resumedCase('...kept.index below 0: held to its first', answer(navidrome((id) => id !== '2'), 2, 0, 'deadwax', kept({ index: -3 })))
  resumedCase('songs in another order than kept: anyone else\'s', answer([songOf('2'), songOf('1'), songOf('3')], 1, 50, 'deadwax', kept()))
  resumedCase('one song more than kept: anyone else\'s', answer([...all, songOf('1')], 1, 50, 'deadwax', kept()))
  const foreign = list.slice(0, 3).map(bareTrack).map(navidromeSong)
  resumedCase('another app\'s: a plain list at its index and second, as songs', answer(foreign, 1, 33, 'Symfonium', null))
  resumedCase('...an index past its end: held to the last song, at 0:00', answer(foreign, 7, 33, 'Symfonium', null))
  resumedCase('...an index below 0: held to the first, at 0:00', answer(foreign, -2, 33, 'Symfonium', null))
  resumedCase('...no index at all: the first song at 0:00; Off: no levels', answer(foreign, null, 33, 'Symfonium', null), 'off')
  resumedCase('...By album: album', answer(foreign, 1, 33, 'Symfonium', null), 'album')
  resumedCase('...nobody named (changed_by empty): no telling where from', answer(foreign, 0, 5, '', null))
  resumedCase('a deadwax queue with no record: a plain list, no telling where from', answer(foreign, 0, 10, 'deadwax', null))
  resumedCase('deadwax\'s ids at another index than the record\'s: a plain list at Navidrome\'s, said by the label', answer(all, 4, 20, 'deadwax', kept()), 'auto', 'desk-2')
  resumedCase('...from this device: no telling', answer(all, 4, 20, 'deadwax', kept()))
  resumedCase('...Navidrome saying no index: the first, at 0:00', answer(all, null, 20, 'deadwax', kept()), 'auto', 'desk-2')
  resumedCase('Navidrome\'s list empty: nothing', answer([], null, 0, '', null))
  resumedCase('...empty, with a record: nothing', answer([], 0, 0, 'deadwax', kept()))
  resumedCase('a song played to its end: the next one at 0:00', answer(foreign, 1, 199.5, 'Symfonium', null))
  resumedCase('...the queue\'s last song: it again at 0:00', answer(foreign, 2, 199.2, 'Symfonium', null))
  resumedCase('...a second short of its end: not played out', answer(foreign, 1, 198.9, 'Symfonium', null))
  resumedCase('...exact, kept.position at its end: the next entry at 0:00', answer(all, 2, 61, 'deadwax', kept({ position: 199 })))
  const unknown = [{ id: 'u1', title: 'one', duration: 0 }, { id: 'u2', title: 'two' }]
  resumedCase('a song of no known length at a great position: not moved on', answer(unknown, 0, 5000, 'Symfonium', null))
  resumedCase('a position below 0: 0', answer(foreign, 1, -5, 'Symfonium', null))
}

// saveDue (:410-438): a sweep of its clocks, every trigger playing and not
{
  const T = 100_000
  const queue = U.startUpNext(rAlbum(5, 's'), 1)
  const queues = { queue, edited: U.withNext(queue, [rTrack('sn')]), moved: atIndex(queue, 2), far: atIndex(queue, 4), empty: Q.EMPTY_QUEUE }
  const base = { queue: 'queue', index: 1, position: 10, start: 0, count: 5 }
  const clocks = [
    ['as saved', {}], ['changed 999 ms ago', { changedAt: T - 999 }], ['changed 1,000 ms ago', { changedAt: T - 1_000 }],
    ['changed 1,999 ms ago', { changedAt: T - 1_999 }], ['changed 2,000 ms ago', { changedAt: T - 2_000 }], ['changed 10 ms ago', { changedAt: T - 10 }],
    ['never changed', { changedAt: null }], ['no ids_rev', { idsRev: null }], ['never saved', { saved: null, idsRev: null }],
    ['never saved, an ids_rev', { saved: null }], ['the window two long', { saved: { ...base, count: 2 } }],
    ['the window from 3', { saved: { ...base, start: 3, count: 2 } }], ['failed 29,000 ms ago', { failedAt: T - 29_000 }],
    ['failed 29,999 ms ago', { failedAt: T - 29_999 }], ['failed 30,000 ms ago', { failedAt: T - 30_000 }],
    ['counted from nothing', { countFrom: null }], ['counted 29,999 ms', { countFrom: T - 29_999 }], ['counted 30,000 ms', { countFrom: T - 30_000 }],
    ['counted 90,000 ms', { countFrom: T - 90_000 }], ['saved at 40 s', { saved: { ...base, position: 40 } }],
    ['saved at song 2', { saved: { ...base, index: 2 } }],
  ]
  const clockOf = (fields) => ({ saved: base, idsRev: 3, countFrom: 0, changedAt: 0, failedAt: null, ...fields })
  const live = (clock) => ({
    ...clock, saved: clock.saved && { tracks: queues[clock.saved.queue].tracks, upNext: queues[clock.saved.queue].upNext,
      index: clock.saved.index, position: clock.saved.position, start: clock.saved.start, count: clock.saved.count },
  })
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)
  for (const [name, q] of Object.entries(queues)) {
    //? identity in the web, equality on the phone: never a queue where the two would disagree
    if ((q.tracks === queue.tracks) !== same(q.tracks, queue.tracks) || (q.upNext === queue.upNext) !== same(q.upNext, queue.upNext)) {
      throw new Error(`saveDue's ${name} queue is equal to the saved one but not the same objects`)
    }
  }
  resumeCases.push({ kind: 'saveQueues', queues: Object.fromEntries(Object.entries(queues).map(([name, q]) => [name, record(q)])) })
  for (const [label, fields] of clocks) {
    const clock = clockOf(fields)
    for (const [name, q] of Object.entries(queues)) {
      for (const position of [10, 10.6, 10.9, 11.5, 14, 40, 0]) {
        const results = [false, true].flatMap((playing) => RESUME_TRIGGERS.map((trigger) =>
          ({ full: 'f', at: 'a', null: '-' })[R.saveDue(live(clock), q, position, playing, T, trigger)]))
        resumeCases.push({ kind: 'saveDue', label, clock, queue: name, position, now: T, changed: R.changedSince(live(clock).saved, q, position), results: results.join('') })
      }
    }
  }
}


// JSON as the web writes and reads it, on its own (SnapshotJSON.swift): numbers, strings and texts of every shape
{
  const view = new DataView(new ArrayBuffer(8))
  const bitsOf = (x) => { view.setFloat64(0, x); return view.getBigUint64(0).toString(16).padStart(16, '0') }
  const fromBits = (hex) => { view.setBigUint64(0, BigInt(`0x${hex}`)); return view.getFloat64(0) }
  const special = [0, -0, 1, -1, 200, 200.5, 0.1, 0.1 + 0.2, 1 / 3, 2 / 3, 1e-7, 1.5e-7, 1e-6, 0.0000015, 123456789.123,
    1e20, 1e21, 1.5e21, 123e18, 2 ** 53, 2 ** 53 + 2, 2 ** 60, 2 ** 64, 9007199254740991, -9007199254740991, 1.5e300,
    5e-324, 2.2250738585072014e-308, 1.7976931348623157e308, 4.35, 0.5, 2.5e-5, 100, 1e16, 1e17, 12345678901234567890,
    0.001, 1e-5, 86400, 199.5, 61.5, 12.5, 95.25, -12.5, 1e-323, 4.9406564584124654e-324, 0.000123, 1234.5e10]
  const generator = new ParkMiller(424242)
  const random = []
  while (random.length < 400) {
    //? any 64 bits, from three draws - every exponent and every layout Number::toString has
    const word = ((BigInt(generator.int()) << 33n) ^ (BigInt(generator.int()) << 2n) ^ BigInt(generator.int() & 3)) & 0xffffffffffffffffn
    const x = fromBits(word.toString(16).padStart(16, '0'))
    if (Number.isFinite(x)) random.push(x)
  }
  //? and the sizes a queue holds: durations and positions to the millisecond
  const sized = Array.from({ length: 100 }, () => Math.round(generator.next() * 3_600_000) / 1000)
  for (const x of [...special, ...random, ...sized]) resumeCases.push({ kind: 'number', bits: bitsOf(x), text: JSON.stringify(x) })
  for (const x of [NaN, Infinity, -Infinity]) resumeCases.push({ kind: 'number', bits: bitsOf(x), text: JSON.stringify(x) })

  const C = (...codes) => String.fromCharCode(...codes)
  const strings = ['', 'plain', 'a/b', 'say "hi"', 'back\\slash', ...Array.from({ length: 32 }, (_, i) => `c${C(i)}c`),
    `del${C(0x7f)}`, `line${C(0x2028)}para${C(0x2029)}`, `${C(0xfeff)}bom`, 'Beyonc' + C(0xe9), C(0x591c, 0x306b, 0x99c6, 0x3051, 0x308b),
    'party ' + C(0xd83d, 0xde00) + ' time', 'e' + C(0x301) + ' and ' + C(0xe9), C(0xffff), C(0x80, 0x9f), C(0xd7ff, 0xe000)]
  for (const text of strings) resumeCases.push({ kind: 'string', text, json: JSON.stringify(text) })

  //? JSON.parse's answer, written canonically (keys sorted by UTF-16 unit, numbers and strings as JSON.stringify) so
  //? the phone's reading is compared as text - or null where JSON.parse throws
  const canonical = (value) => {
    if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
    if (value !== null && typeof value === 'object') {
      return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    }
    return JSON.stringify(value)
  }
  const parsed = (text) => { try { return canonical(JSON.parse(text)) } catch { return null } }
  const texts = ['{}', '[]', '1', '-0', '0', '01', '-01', '1.', '.5', '1.5', '1e5', '1E+5', '1e-5', '1e', '1e+', '-', '--1', '+1',
    '1e-400', '0.0000001', 'true', 'false', 'null', 'nul', 'True', 'NaN', 'Infinity', '"a"', "'a'", '"\\/"', '"\\u0041"',
    '"\\u00e9"', '"\\u00E9"', '"\\uD83D\\uDE00"', '"\\x41"', '"\\U0041"', '"\\u12"', '"\\u12G4"', '"\\a"', '"a', 'a"',
    `"a${C(1)}b"`, `"a${C(0x7f)}b"`, `"tab${C(9)}"`, '[1,]', '[,1]', '{"a":1,}', '{,"a":1}', '[1 2]', '{"a" 1}', '{a:1}',
    '{"a":1,"a":2}', '{"a":{"b":1},"a":[2]}', ` ${C(9, 10, 13)}[1] ${C(9, 10, 13)}`, `[1]${C(0x0b)}`, `[1]${C(0x0c)}`,
    `${C(0xa0)}[1]`, `${C(0xfeff)}[1]`, `[1]${C(0x2028)}`, '[1] x', '[1][2]', '', ' ', '{"a":[{"b":null,"c":[true,false]}]}',
    '{"__proto__":{"x":1},"constructor":2}', '{"":0," ":1}', '[-0.0,0e0,0E-0,1.0e+2]', '{"10":1,"2":2,"a":3,"1":4}',
    '[1e308,1.7976931348623157e308,5e-324,2e-324]', '[123456789012345678901234567890]',
    `${'['.repeat(1000)}${']'.repeat(1000)}`, `${'{"a":'.repeat(500)}1${'}'.repeat(500)}`]
  for (const text of texts) resumeCases.push({ kind: 'parse', text, canonical: parsed(text) })

  //? the device's id: what persisted.ts's DEVICE_ID takes
  const pattern = new RegExp(resumeConstants.DEVICE_ID)
  for (const candidate of ['kept_device-0001', 'not an id!', 'short', 'abcdefgh', 'abcdefg', 'A'.repeat(64), 'A'.repeat(65),
    'abcdefgh\n', `abc${C(10)}defgh`, `${C(0xc4)}bcdefgh`, '', 'abcdefg_-', '--------', '________', '0123456789', 'abc defgh',
    'abcdefgh ', 'abc.defgh', 'Zz09_-Zz09_-Zz09', `abcdefg${C(0x0130)}`]) {
    resumeCases.push({ kind: 'deviceId', candidate, valid: pattern.test(candidate) })
  }
  for (const bytes of [Array.from({ length: 16 }, (_, i) => i * 17), Array.from({ length: 16 }, () => 255), Array(16).fill(0),
    Array.from({ length: 16 }, (_, i) => 64 + i)]) {
    //? persisted.ts's own line: DEVICE_LETTERS[byte & 63] - read from its text, so a change of it shows here
    resumeCases.push({ kind: 'deviceIdMade', bytes, id: bytes.map((byte) => resumeConstants.DEVICE_LETTERS[byte & 63]).join('') })
  }
}
piece('ui/src/state/persisted.ts', /const made = Array\.from\(bytes, \(byte\) => DEVICE_LETTERS\[byte & 63\]\)\.join\(''\)/, 'the device id\'s making')

// the round trip (:169-267): every step of resume.sim.cjs's 500 runs - runs 0-39 in full (the queue, and the snapshot
// toSave wrote for it, which the phone must write to the byte and read back as the web does), every run's snapshots
// digested (the Swift test runs the same generator over its own Up Next and must write the very same texts)
const ROUND_TRIP_RUNS = 500
const ROUND_TRIP_KEPT = 40
const ROUND_TRIP_STEPS = 25
const ROUND_TRIP_POSITION = 12.5
const roundTripSongs = new LevelledSongs()
const roundTrip = []
const roundTripDigests = []
const roundTripCounts = { states: 0, behind: 0, paged: 0, pagedRounds: 0, left: 0, ones: 0, added: 0, shuffled: 0, extra: 0 }
for (let run = 0; run < ROUND_TRIP_RUNS; run++) {
  const random = parkMiller(run + 7)
  //? a small seed's first draw is always near 0 - which started every run from its first song, null: let it go
  random()
  const pick = (n) => Math.floor(random() * n)
  const level = () => (random() < 0.5 ? 'album' : 'track')
  const size = 1 + pick(7)
  let repeat = U.REPEATS[pick(3)]
  const paged = run % 5 === 0 ? { token: `t${run}`, total: size + 6, fetched: size, scope: 'yours', level: 'track' } : undefined
  //? (2.1.15) the run's queue under an id of its own, which the Swift run gives it too: every snapshot carries it
  let queue = U.toppedUp(U.startUpNext(rAlbum(size, '', { level: level() }), random() < 0.3 ? null : pick(size), random() < 0.5, random, paged, `rt-${run}`), repeat, random)
  let extra = 0
  const digests = []
  for (let step = 0; step < ROUND_TRIP_STEPS; step++) {
    const op = pick(12)
    const rowKeys = () => queue.upNext.marks.slice(queue.index + 1).map((m) => m.key)
    const someKey = () => { const keys = rowKeys(); return keys.length && random() < 0.85 ? keys[pick(keys.length)] : pick(queue.upNext.nextKey + 2) }
    if (op === 0) queue = U.withNext(queue, Array.from({ length: 1 + pick(2) }, () => rTrack(`n${extra++}`, { level: level() })))
    else if (op === 1) queue = U.withLast(queue, Array.from({ length: 1 + pick(2) }, () => rTrack(`l${extra++}`, { level: level() })))
    else if (op === 2) queue = U.withoutKey(queue, someKey())
    else if (op === 3) queue = U.movedKey(queue, someKey(), pick(6))
    else if (op === 4) queue = U.withoutAdded(queue)
    else if (op === 5) queue = U.withShuffle(queue, random() < 0.5, random)
    else if (op === 6) { repeat = U.REPEATS[pick(3)]; queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, random) }
    else if (op === 7) {
      const p = queue.upNext.paged
      if (p) queue = U.withMore(queue, p.token, Array.from({ length: 1 + pick(3) }, () => rTrack(`p${extra++}`, { level: 'track' })),
        p.fetched >= p.total && repeat === 'all' ? { token: `${p.token}+`, total: 3, fetched: 0, scope: p.scope, level: 'track' } : undefined)
      else queue = U.toppedUp(queue, repeat, random)
    } else if (op === 8) {
      //? (2.1.3) a row's tap - of History's now and then (an entry before the song playing)
      const before = queue.upNext.marks.slice(0, queue.index).map((m) => m.key)
      const jumped = U.jumpedTo(queue, before.length && random() < 0.3 ? before[pick(before.length)] : someKey())
      if (jumped) queue = atIndex(jumped.queue, jumped.index)
    } else if (op === 9) { const next = U.onward(queue); if (next !== null) queue = atIndex(queue, next) }
    else if (op === 10) {
      //? (2.1.3) as the engine moves now (wentBack), or - half the time - as an app before 2.1.3 saved it
      const back = U.backward(queue, 0)
      if (back.kind === 'go') queue = random() < 0.5 ? U.wentBack(queue, back.index) : atIndex(queue, back.index)
    } else queue = atIndex(queue, Math.min(queue.index + 1, queue.tracks.length - 1))
    queue = U.toppedUp(queue, repeat, random)

    const saving = saved(queue, ROUND_TRIP_POSITION)
    const { start } = saving
    const end = start + saving.ids.length
    //? the sim's own check, as the premise of what the phone is held to: the web reads its own snapshot back whole
    const back = R.fromSnapshot(saving.snapshot, queue.tracks.slice(start, end).map(bareTrack), saving.index, 'auto')
    const was = queue.upNext
    //? (2.1.3) startedAt past the song playing's run comes back lowered to it
    let unit = queue.index
    while (unit > 0 && was.marks[unit].from === 'one') unit--
    const wanted = {
      id: was.id, tracks: queue.tracks.slice(start, end), index: queue.index - start, marks: was.marks.slice(start, end), source: was.source,
      shuffle: was.shuffle, nextKey: was.nextKey, startedAt: Math.min(Math.max(0, was.startedAt - start), unit - start), left: was.left, paged: was.paged, pagedRounds: was.pagedRounds,
    }
    const got = back && {
      id: back.upNext.id, tracks: back.tracks, index: back.index, marks: back.upNext.marks, source: back.upNext.source, shuffle: back.upNext.shuffle,
      nextKey: back.upNext.nextKey, startedAt: back.upNext.startedAt, left: back.upNext.left, paged: back.upNext.paged, pagedRounds: back.upNext.pagedRounds,
    }
    if (JSON.stringify(got) !== JSON.stringify(wanted)) throw new Error(`the round trip's run ${run} step ${step} didn't read back in the TypeScript`)
    digests.push(saving.snapshot === null ? null : unitHash(saving.snapshot))
    if (run < ROUND_TRIP_KEPT) roundTrip.push({ run, step, queue: queueRecord(queue, roundTripSongs), index: saving.index, start, snapshot: saving.snapshot })
    const c = roundTripCounts
    c.states++
    if (was.startedAt > queue.index) c.behind++
    if (was.paged) c.paged++
    if (was.pagedRounds) c.pagedRounds++
    if (was.left.length) c.left++
    if (was.marks.some((m) => m.from === 'one')) c.ones++
    if (was.marks.some((m) => m.from === 'added')) c.added++
    if (was.shuffle) c.shuffled++
    if (saving.snapshot !== null && saving.snapshot.indexOf('"extra":{}') < 0) c.extra++
  }
  roundTripDigests.push(digests)
}

/* ===== written, or checked ===== */

const header = (extra) => JSON.stringify({ version: 1, made_by: 'ios/scripts/export-traces.cjs', made_from: madeFrom, ...extra })
const resumeHeader = (extra) => JSON.stringify({ version: 1, made_by: 'ios/scripts/export-traces.cjs', made_from: resumeMadeFrom, ...extra })
/** `{header..., "<key>":[` then one item a line, so a change reads as a diff of the items it touched - one list or
 *  more, in the order given. */
const lines = (head, ...lists) => {
  const body = []
  for (let i = 0; i < lists.length; i += 2) body.push(`"${lists[i]}":[\n${lists[i + 1].map((item) => JSON.stringify(item)).join(',\n')}\n]`)
  return `${head.slice(0, -1)},${body.join(',')}}\n`
}
/** A file's text as committed: DEL - the one control character JSON.stringify leaves raw - written as its escape,
 *  which reads back the same (tests/test_source_bytes.py refuses a raw one in any tracked file). */
const DEL = String.fromCharCode(0x7f)
const committed = (text) => text.split(DEL).join('\\' + 'u007f')

const traceSongs = new Songs()
const traces = Array.from({ length: TRACES }, (_, i) => trace(i + 1, traceSongs))
const digests = propertyDigests()
const files = {
  'traces.json': lines(header({ steps: STEPS, songs: traceSongs.table() }), 'traces', traces),
  'scenarios.json': lines(header({ constants }), 'scenarios', scenarios),
  'property.json': lines(header({ runs: PROPERTY_RUNS, steps: PROPERTY_STEPS }), 'digests',
    Array.from({ length: Math.ceil(digests.length / 10) }, (_, i) => digests.slice(i * 10, i * 10 + 10))),
}
const resumeFiles = {
  'cases.json': committed(lines(resumeHeader({ constants: resumeConstants, songs: resumeSongs.table() }), 'cases', resumeCases)),
  'roundtrip.json': committed(lines(resumeHeader({
    runs: ROUND_TRIP_RUNS, kept: ROUND_TRIP_KEPT, steps: ROUND_TRIP_STEPS, position: ROUND_TRIP_POSITION, counts: roundTripCounts,
    songs: roundTripSongs.table(),
  }), 'states', roundTrip, 'digests', roundTripDigests)),
}
Math.random = realRandom
Date.now = realNow
if (realCrypto) Object.defineProperty(globalThis, 'crypto', realCrypto)
else delete globalThis.crypto
const written = [
  ...Object.entries(files).map(([name, text]) => [FIXTURES, name, text]),
  ...Object.entries(resumeFiles).map(([name, text]) => [RESUME_FIXTURES, name, text]),
]
const where = (dir, name) => path.relative(REPO, path.join(dir, name))

if (CHECK) {
  const stale = []
  //? the hand-ported pieces whose hash isn't the one committed: they need a person, not only the exporter
  const handChanged = new Set()
  for (const [dir, name, text] of written) {
    const file = path.join(dir, name)
    const committedText = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
    if (committedText === text) continue
    let only = ''
    try {
      const [a, b] = [JSON.parse(committedText), JSON.parse(text)]
      for (const piece of Object.keys(BY_HAND)) if (a.made_from?.[piece] !== b.made_from?.[piece]) handChanged.add(piece)
      delete a.made_from
      delete b.made_from
      if (JSON.stringify(a) === JSON.stringify(b)) only = ' (only the sources\' hashes: every trace is the same)'
    } catch { /* missing, or not JSON: stale either way */ }
    stale.push(`${where(dir, name)}${committedText === null ? ' (missing)' : only}`)
  }
  if (stale.length) {
    const byHand = [...handChanged].sort()
    console.error(`The iPhone's traces are stale: ${stale.join(', ')}.\n` +
      (byHand.length
        ? `These pieces changed, and the Swift ports of them are written by hand - nothing replays them, so read each\n` +
          `change and port it first:\n${byHand.map((piece) => `  ${piece}  ->  ${BY_HAND[piece]}`).join('\n')}\nthen run\n`
        : `${[...new Set([...SOURCES, ...RESUME_SOURCES, ...Object.keys(madeFrom), ...Object.keys(resumeMadeFrom)])]
          .filter((name) => !(name in BY_HAND)).join(', ')} changed without them - run\n`) +
      '  node ios/scripts/export-traces.cjs  and commit what it writes\n' +
      '(then the Swift replay, swift test --package-path ios/DeadwaxKit, says whether the ports still agree).')
    process.exit(1)
  }
  console.log(`The iPhone's Up Next and resume traces are current: ${written.map(([dir, name]) => where(dir, name)).join(', ')}.`)
} else {
  fs.mkdirSync(FIXTURES, { recursive: true })
  fs.mkdirSync(RESUME_FIXTURES, { recursive: true })
  for (const [dir, name, text] of written) fs.writeFileSync(path.join(dir, name), text)
  const ops = traces.reduce((n, t) => n + t.ops.length, 0)
  const draws = traces.reduce((n, t) => n + t.ops.reduce((m, o) => m + (o.randoms?.length ?? 0), 0), 0)
  const kinds = {}
  for (const c of resumeCases) kinds[c.kind] = (kinds[c.kind] ?? 0) + 1
  console.log(`Wrote ${written.map(([dir, name, text]) => `${where(dir, name)} (${text.length} bytes)`).join(', ')}: ` +
    `${traces.length} traces of ${ops} ops and ${draws} draws, ${scenarios.length} scenarios, ${digests.length} property runs; ` +
    `resume: ${Object.entries(kinds).map(([kind, n]) => `${n} ${kind}`).join(', ')}; ${roundTrip.length} round-trip states kept whole, ` +
    `${roundTripDigests.length} runs digested (${JSON.stringify(roundTripCounts)}).`)
}
