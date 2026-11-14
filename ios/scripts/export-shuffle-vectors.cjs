#!/usr/bin/env node
/**
 * The Library's Shuffle's feed and Songs, for the iPhone app (Phase 4, slice 5 - notes/ios-specs/phase4-library.md 2.7,
 * 5.2 and question 24): what the web app's own TypeScript answers, written as one fixture the Swift ports in
 * ios/DeadwaxKit/Sources/DeadwaxCore replay (Tests/DeadwaxCoreTests/ShuffleVectorTests.swift) - Shuffle.swift's
 * ShuffleFeed and ShuffleFeedRun (app/useShuffleFeed.ts) and Songs.swift (app/usePaged.ts, app/LibraryViews.tsx's
 * SongsView) - so the phone brings a library's shuffle in, and pages every song, exactly as the web does, and a change
 * to the web's rules shows up as a fixture that no longer matches.
 *
 * useShuffleFeed.ts and usePaged.ts are hooks, which import Preact: they are compiled with the repo's TypeScript and
 * run under ui/test/shuffle.sim.cjs's own stand-in for Preact (JSX as plain objects, hooks with a cursor whose effects
 * run on commit), against a faked deadwax whose every ask is kept and answered when the run says - the hook itself,
 * driven, not a copy of it. Compiled with them: lib/upNext.ts (the queue the feed reads and extends), lib/yourLibrary.ts,
 * lib/appFrame.ts and lib/artistPage.ts (Songs' words); read from source: SONGS_PAGE and librarySongs' query
 * (player/api.ts, which is stood in for), and the expressions SongsView draws a row with (LibraryViews.tsx). Writes
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/shuffle/shuffle-vectors.json:
 *
 *   words      FEED_BELOW, FEED_RETRY_MS, SHUFFLE_STARTED_OVER; SONGS_PAGE, librarySongs' query, NO_SONGS, the
 *              titles, the row's hidden words and line, countText over counts
 *   elsewhere  startingElsewhere over every list of up to four songs of three ids (and one never in them) under
 *              every ending, and longer seeded ones - each with the seed its random draws from (Park-Miller, as the
 *              sims' seeded()) and how many it drew
 *   ahead      songsAhead over queues lib/upNext.ts made by seeded runs of its own edits (Play Next and Last, Repeat
 *              and its copies, Shuffle, the next page, a next round, a song moving on), and the edge cases - each
 *              queue as its index and its marks' kinds
 *   runs       the hook driven: shuffle.sim.cjs's own cases scripted, and seeded runs - a song moving on, Repeat,
 *              Play Next, another shuffle, the queue cleared, each ask answered, failed, a page's 404, a retry -
 *              with what the hook did after each step: the asks made, what it handed extendQueue (the token, the
 *              songs' ids and levels, the next order), what it said, and the retries waiting
 *   append     appendPage over pages that repeat what is drawn, and themselves
 *
 * The one place the phone departs, kept out of the seeded runs: a page that wouldn't come waits out its 30 s on the
 * phone (ShuffleFeedRun.retried) whatever changes meanwhile, and it keeps one retry, never two; the web's effect runs
 * again when Repeat or the shuffle changes, so it can ask again sooner and keeps every timer it started. So no run
 * changes Repeat, or starts another shuffle, while a retry waits (notes/ios.md, "Phase 4, slice 5").
 *
 * Every random choice is seeded, and the output is plain ASCII, so a run on any machine writes the same bytes. Never
 * edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-shuffle-vectors.cjs           write the fixture
 *   node ios/scripts/export-shuffle-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'shuffle', 'shuffle-vectors.json')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-shuffle-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/useShuffleFeed.ts', 'src/app/usePaged.ts', 'src/lib/upNext.ts', 'src/lib/yourLibrary.ts',
  'src/lib/appFrame.ts', 'src/lib/artistPage.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck',
  '--moduleResolution', 'node', '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - shuffle.sim.cjs's stand-in
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

//? deadwax's shuffle routes, faked: every ask kept and answered when the run says; the notice; a song as the queue
//? takes it (shuffle.sim.cjs's)
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('player/api.js', `
exports.shuffleStart = (scope, signal, how) => globalThis.__feed.ask('start', scope, how && how.claim ? { claim: true } : {})
exports.shufflePage = (token, offset) => globalThis.__feed.ask('page', token, offset)
exports.toQueueTrack = (song, album) => ({ id: song.id, title: song.title, artist: song.artist ?? '', album: song.album ?? album.name, albumId: song.albumId ?? album.id,
  coverArt: null, duration: 1, contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0 })
`)
write('app/usePins.js', `exports.sayPins = (text) => globalThis.__feed.said.push(text)\n`)
write('api/http.js', `class ApiError extends Error { constructor(status, detail) { super(detail); this.status = status } }\nexports.ApiError = ApiError\n`)

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const F = require(path.join(OUT, 'app/useShuffleFeed.js'))
const P = require(path.join(OUT, 'app/usePaged.js'))
const U = require(path.join(OUT, 'lib/upNext.js'))
const Y = require(path.join(OUT, 'lib/yourLibrary.js'))
const AF = require(path.join(OUT, 'lib/appFrame.js'))
const A = require(path.join(OUT, 'lib/artistPage.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))

/** A piece of a source file the exporter can't compile (it is stood in for, or a component): the match, or stop. */
function piece(file, pattern, what) {
  const found = fs.readFileSync(path.join(UI, file), 'utf8').match(pattern)
  if (!found) throw new Error(`${file} has no ${what} any more`)
  return found
}

/* ===== Park-Miller, as the sims' seeded() ===== */

const M = 2147483647
class ParkMiller {
  constructor(seed) {
    if (!(seed >= 1 && seed < M)) throw new Error(`Park-Miller needs a seed in 1...2147483646, not ${seed}`)
    this.s = seed
  }
  int() { this.s = (this.s * 16807) % M; return this.s }
  next() { return (this.int() - 1) / 2147483646 }
}
const never = () => { throw new Error('nothing here should draw a random number') }

/* ===== the words ===== */

function wordVectors() {
  const query = piece('src/player/api.ts', /new URLSearchParams\(\{ (q: '', artistCount: '0', albumCount: '0', songCount: String\(count\), songOffset: String\(offset\)) \}\)/, "librarySongs' query")[1]
  const views = 'src/app/LibraryViews.tsx'
  const line = piece(views, /<span class="app-result-line">\{(\[song\.artist, song\.album\]\.filter\(Boolean\)\.join\(' · '\))\}<\/span>/, "SongsView's line")[1]
  const hidden = piece(views, /<span class="app-visually-hidden">(, opens its album)<\/span>/, "SongsView's hidden words")[1]
  //? the expression as written, evaluated over each case
  const lineOf = new Function('song', `return ${line}`)
  const lineCases = [
    { artist: 'Portishead', album: 'Dummy' }, { artist: 'Portishead' }, { album: 'Dummy' }, {}, { artist: '', album: 'Dummy' },
    { artist: 'Portishead', album: '' }, { artist: '', album: '' }, { artist: 'Simon & Garfunkel', album: 'Bookends' },
  ]
  return {
    FEED_BELOW: F.FEED_BELOW,
    FEED_RETRY_MS: F.FEED_RETRY_MS,
    SHUFFLE_STARTED_OVER: F.SHUFFLE_STARTED_OVER,
    SONGS_PAGE: Number(piece('src/player/api.ts', /\nexport const SONGS_PAGE = (\d+)\n/, 'SONGS_PAGE')[1]),
    librarySongs: query,
    NO_SONGS: Y.NO_SONGS,
    titles: { songs: AF.libraryTitle('songs', false), allSongs: AF.libraryTitle('songs', true) },
    browse: AF.SIDEBAR_BROWSE.map((item) => item.label),
    hidden,
    lines: lineCases.map((song) => ({ song, line: lineOf(song) })),
    counts: [null, 0, 1, 2, 100, 12480].map((count) => ({ count, text: A.countText(count, 'song', 'songs') })),
  }
}

/* ===== startingElsewhere ===== */

const plain = (id) => ({ id, title: `song ${id}`, artist: '', album: 'A', albumId: 'al', coverArt: null, duration: 1,
  contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0 })

function elsewhereVectors() {
  const out = []
  let seed = 101
  const one = (ids, ending) => {
    const generator = new ParkMiller(seed)
    let drew = 0
    const random = () => { drew++; return generator.next() }
    const made = F.startingElsewhere(ids.map(plain), ending, random).map((track) => track.id)
    out.push({ ids, ending, seed, drew, out: made })
    seed += 7
  }
  //? shuffle.sim.cjs's own three, as it writes them (its random 0, and Math.random where it gives none)
  const lists = [[]]
  for (let length = 1; length <= 4; length++) {
    for (const before of lists.filter((list) => list.length === length - 1)) for (const id of ['a', 'b', 'c']) lists.push([...before, id])
  }
  for (const ids of lists) for (const ending of [null, 'a', 'b', 'z']) one(ids, ending)
  //? longer: the ending first, and among the rest - none of it, a little of it, most of it
  for (let n = 0; n < 40; n++) {
    const generator = new ParkMiller(9001 + n)
    const length = 2 + Math.floor(generator.next() * 300)
    const share = [0, 0.05, 0.5, 0.95, 1][n % 5]
    const ids = Array.from({ length }, (_, at) => (at === 0 || generator.next() < share ? 'e' : `s${at}`))
    one(ids, n % 7 === 6 ? `s${length - 1}` : 'e')
  }
  return out
}

/* ===== songsAhead ===== */

const FROM = { source: 's', added: 'a', one: 'o' }
const REPEATS = ['off', 'all', 'one']

function aheadVectors() {
  const out = []
  const record = (queue, how) => out.push({
    how, index: queue.index, count: queue.tracks.length,
    froms: queue.upNext ? queue.upNext.marks.map((mark) => FROM[mark.from]).join('') : null,
    ahead: F.songsAhead(queue),
  })
  record(U.startUpNext([], 0), 'the empty queue')
  record({ tracks: [plain('x'), plain('y')], index: 0 }, 'a plain queue, no Up Next')
  for (let seed = 1; seed <= 120; seed++) {
    const generator = new ParkMiller(seed * 131)
    const r = () => generator.next()
    const pick = (n) => Math.floor(r() * n)
    const length = 1 + pick(70)
    const paged = r() < 0.75 ? { token: 't', total: length + pick(400), fetched: length, scope: r() < 0.5 ? 'yours' : 'store' } : undefined
    let queue = U.startUpNext(Array.from({ length }, (_, at) => plain(`s${at}`)), pick(length), r() < 0.25, r, paged, 'q')
    let repeat = 'off'
    let added = 0
    const steps = 1 + pick(14)
    for (let step = 0; step < steps; step++) {
      const roll = r()
      if (roll < 0.2) queue = U.withNext(queue, [plain(`n${added++}`)])
      else if (roll < 0.32) queue = U.withLast(queue, [plain(`n${added++}`), plain(`n${added++}`)])
      else if (roll < 0.5) {
        repeat = REPEATS[pick(3)]
        queue = U.toppedUp(U.withRepeat(queue, repeat), repeat, r)
      } else if (roll < 0.58) queue = U.toppedUp(U.withShuffle(queue, r() < 0.5, r), repeat, r)
      else if (roll < 0.72 && queue.upNext?.paged) {
        const more = Array.from({ length: 1 + pick(60) }, (_, at) => plain(`m${step}-${at}`))
        const whole = queue.upNext.paged.fetched >= queue.upNext.paged.total
        queue = U.withMore(queue, 't', more, whole ? { token: 't', total: 300, fetched: 0, scope: 'store' } : undefined)
      } else {
        queue = { ...queue, index: Math.min(queue.tracks.length - 1, queue.index + 1 + pick(12)) }
        queue = U.toppedUp(queue, repeat, r)
      }
    }
    record(queue, `seeded run ${seed}`)
    //? the song playing at the very end, and at the very start
    record({ ...queue, index: queue.tracks.length - 1 }, `seeded run ${seed}, its last song playing`)
    if (seed % 4 === 0) record({ ...queue, index: 0 }, `seeded run ${seed}, its first song playing`)
  }
  return out
}

/* ===== the hook, driven ===== */

const SHUFFLE_PAGE = 200

/** A song of deadwax's: `s` and its number in the library, or another letter for another library's. */
const song = (id) => ({ id, title: `Song ${id}`, album: 'A', albumId: 'al' })

/**
 * One run of the feed: deadwax's orders by token (each the library's songs, shuffled by the run's generator), the
 * player (its queue, Repeat and extendQueue, as App hands them over), the asks the hook makes (the fake's, kept open
 * until a step answers them), the retries it starts, and what it says. `step` carries one step out and records what
 * the hook did after it.
 */
class Run {
  constructor({ name, seed, total, scope = 'store', level, repeat = 'off', index = 0 }) {
    this.generator = new ParkMiller(seed)
    this.r = () => this.generator.next()
    this.total = total
    this.scope = scope
    this.level = level
    this.orders = new Map()
    this.made = 0
    this.asks = []
    this.timers = []
    this.said = []
    this.extended = []
    this.draws = []
    this.steps = []
    this.queued = 0
    const token = this.order()
    const page = this.orders.get(token).slice(0, SHUFFLE_PAGE)
    const tracks = U.startUpNext(this.tracksOf(page), index, false, never,
      { token, total: this.orders.get(token).length, fetched: page.length, scope, ...(level ? { level } : {}) }, 'q')
    this.player = { queue: tracks, repeat }
    //? the whole first order, for a run that answers with songs of its own
    this.first = [...this.orders.get(token)]
    this.record = { name, seed, scope, level: level ?? null, repeat, index, token, total: this.first.length, first: page, steps: this.steps }
    const self = this
    globalThis.__feed = {
      said: this.said,
      ask(name, ...args) {
        const n = self.asks.length
        let resolve, reject
        const promise = new Promise((yes, no) => { resolve = yes; reject = no })
        self.asks.push({ n, name, args, resolve, reject, settled: false })
        return promise
      },
    }
    this.feed = hooks.root(() => F.useShuffleFeed({
      queue: this.player.queue,
      repeat: this.player.repeat,
      extendQueue: (token, more, next) => {
        this.extended.push([token, more.map((track) => track.id), more.map((track) => track.level ?? null), next ? pagedOf(next) : null])
        this.player.queue = U.withMore(this.player.queue, token, more, next)
      },
    }))
  }

  /** A new order of the library: its token, every song once in a random order - or, given, those songs as they are. */
  order(given) {
    const token = `o${++this.made}`
    const ids = given ? [...given] : Array.from({ length: this.total }, (_, at) => `s${at + 1}`)
    if (!given) {
      for (let i = ids.length - 1; i > 0; i--) {
        const j = Math.floor(this.r() * (i + 1))
        ;[ids[i], ids[j]] = [ids[j], ids[i]]
      }
    }
    this.orders.set(token, ids)
    return token
  }

  tracksOf(ids) {
    const tracks = ids.map((id) => F.shuffledTrack(song(id)))
    return this.level ? tracks.map((track) => ({ ...track, level: this.level })) : tracks
  }

  /** What deadwax answers ask `n`: a page of the order it names, or a new order's first page. */
  answerOf(n) {
    const ask = this.asks[n]
    if (ask.name === 'page') {
      const [token, offset] = ask.args
      const ids = this.orders.get(token)
      return { total: ids.length, songs: ids.slice(offset, offset + SHUFFLE_PAGE).map(song) }
    }
    const token = this.order()
    const ids = this.orders.get(token)
    return { token, total: ids.length, songs: ids.slice(0, SHUFFLE_PAGE).map(song) }
  }

  async turn() {
    for (let i = 0; i < 6; i++) await new Promise((resolve) => setImmediate(resolve))
    this.feed()
    this.feed.commit()
    for (let i = 0; i < 6; i++) await new Promise((resolve) => setImmediate(resolve))
  }

  /** One step carried out, and what the hook did after it recorded with it. */
  async step(op) {
    const askedBefore = this.asks.length
    const extendedBefore = this.extended.length
    const saidBefore = this.said.length
    this.draws = []
    const recorded = { ...op }
    if ('ask' in op && !this.asks[op.ask]) throw new Error(`${this.record.name}: step ${this.steps.length} names ask ${op.ask}, of ${this.asks.length} made`)
    switch (op.op) {
      case 'begin':
        break
      case 'next':
        this.player.queue = { ...this.player.queue, index: op.to }
        break
      case 'repeat':
        this.player.queue = U.toppedUp(U.withRepeat(this.player.queue, op.mode), op.mode, never)
        this.player.repeat = op.mode
        break
      case 'playNext':
        this.player.queue = U.withNext(this.player.queue, op.ids.map((id) => F.shuffledTrack(song(id))))
        break
      case 'shuffle': {
        //? another shuffle tapped: a new order's first page, from its first song
        const token = this.order()
        const ids = this.orders.get(token)
        const page = ids.slice(0, SHUFFLE_PAGE)
        this.player.queue = U.startUpNext(this.tracksOf(page), 0, false, never,
          { token, total: ids.length, fetched: page.length, scope: this.scope, ...(this.level ? { level: this.level } : {}) }, 'q')
        recorded.token = token
        recorded.total = ids.length
        recorded.first = page
        break
      }
      case 'clear':
        this.player.queue = U.startUpNext([], 0, false, never, undefined, 'q')
        break
      case 'answer': {
        const ask = this.asks[op.ask]
        if (ask.name === 'page' && !this.orders.has(ask.args[0])) throw new Error(`a page of ${ask.args[0]}, which deadwax no longer holds, answered`)
        const answer = op.songs ? { ...(ask.name === 'start' ? { token: this.order(op.songs) } : {}), total: op.total ?? op.songs.length, songs: op.songs.map(song) } : this.answerOf(op.ask)
        if (ask.name === 'start') recorded.token = answer.token
        recorded.total = answer.total
        recorded.songs = answer.songs.map((one) => one.id)
        ask.settled = true
        ask.resolve(answer)
        break
      }
      case 'fail':
        this.asks[op.ask].settled = true
        this.asks[op.ask].reject(new Error('the network dropped'))
        break
      case 'gone': {
        const ask = this.asks[op.ask]
        this.orders.delete(ask.args[0])
        ask.settled = true
        ask.reject(new ApiError(404, 'gone'))
        break
      }
      case 'retry':
        this.timers.shift()()
        break
      default:
        throw new Error(`no step ${op.op}`)
    }
    const random = Math.random
    Math.random = () => { const s = this.generator.int(); this.draws.push(s); return (s - 1) / 2147483646 }
    try {
      await this.turn()
    } finally {
      Math.random = random
    }
    recorded.then = {
      asks: this.asks.slice(askedBefore).map((ask) => [ask.name, ...ask.args]),
      extended: this.extended.slice(extendedBefore),
      said: this.said.slice(saidBefore),
      draws: this.draws,
      retries: this.timers.length,
      queue: { index: this.player.queue.index, count: this.player.queue.tracks.length, paged: this.player.queue.upNext?.paged ? pagedOf(this.player.queue.upNext.paged) : null },
    }
    this.steps.push(recorded)
    return recorded.then
  }

  /** The asks still open whose answer the hook would take - the newest of them. */
  get open() { return this.asks.filter((ask) => !ask.settled) }
}

function pagedOf(paged) {
  const out = { token: paged.token, total: paged.total, fetched: paged.fetched, scope: paged.scope }
  if (paged.level !== undefined) out.level = paged.level
  return out
}

//? the hook's retries, run by hand: each a timer the run fires
globalThis.setTimeout = (fn, ms) => {
  if (ms !== F.FEED_RETRY_MS) throw new Error(`a timer of ${ms} ms`)
  current.timers.push(fn)
  return current.timers.length
}
let current = null

/** shuffle.sim.cjs's own cases, scripted. */
async function scriptedRuns() {
  const runs = []
  const run = async (spec, steps) => {
    current = new Run(spec)
    await current.step({ op: 'begin' })
    for (const step of steps) {
      const op = typeof step === 'function' ? step(current) : step
      await current.step(op)
    }
    runs.push(current.record)
  }
  const newest = (r) => r.asks.length - 1

  //? 450 songs, Repeat off: the next page at 49 ahead, one ask at a time, a failure retried from the same place, the
  //? last page, nothing more under Off, a fresh claimed round under All never starting with the song ending
  await run({ name: 'the feed through a whole order', seed: 11, total: 450 }, [
    { op: 'next', to: 149 }, { op: 'next', to: 150 },
    { op: 'repeat', mode: 'all' }, { op: 'repeat', mode: 'off' },
    (r) => ({ op: 'fail', ask: newest(r) }),
    { op: 'next', to: 160 },
    { op: 'retry' },
    (r) => ({ op: 'answer', ask: newest(r) }),
    { op: 'next', to: 352 },
    (r) => ({ op: 'answer', ask: newest(r) }),
    { op: 'next', to: 420 },
    { op: 'repeat', mode: 'all' },
    (r) => ({ op: 'answer', ask: newest(r), songs: [r.first[449], ...r.first.slice(0, 199)], total: 450 }),
  ])
  //? an order deadwax no longer holds: a fresh claimed order as the rest of this round, said once
  await run({ name: 'a 404 starts over, said once', seed: 12, total: 450, scope: 'yours', index: 160 }, [
    (r) => ({ op: 'gone', ask: newest(r) }),
    (r) => ({ op: 'answer', ask: newest(r) }),
  ])
  //? a whole order in hand under Repeat All: the next round; Repeat off lets it go
  await run({ name: 'Repeat All at the end of a whole order, then off', seed: 13, total: 60, repeat: 'all', index: 20 }, [
    (r) => ({ op: 'answer', ask: newest(r) }),
    { op: 'repeat', mode: 'off' },
    { op: 'next', to: 40 },
  ])
  //? Repeat turned off while a fresh round is on its way: let go; its answer dropped; All again asks afresh
  await run({ name: 'Repeat off while the next round is on its way', seed: 14, total: 60, repeat: 'all', index: 20 }, [
    { op: 'repeat', mode: 'off' },
    { op: 'answer', ask: 0 },
    { op: 'repeat', mode: 'all' },
    (r) => ({ op: 'answer', ask: newest(r) }),
  ])
  //? a fresh order with no songs: appended as nothing, asked once
  await run({ name: 'an empty fresh order', seed: 15, total: 60, repeat: 'all', index: 20 }, [
    { op: 'answer', ask: 0, songs: [], total: 0 },
    { op: 'next', to: 30 },
    { op: 'next', to: 59 },
  ])
  //? the shuffle's level: its pages and its next round at that level
  for (const level of ['track', 'album', undefined]) {
    await run({ name: `a shuffle queued at ${level ?? 'no level'}`, seed: 16, total: 260, level, repeat: 'all', index: 190 }, [
      (r) => ({ op: 'answer', ask: newest(r) }),
      { op: 'next', to: 255 },
      (r) => ({ op: 'answer', ask: newest(r) }),
    ])
  }
  //? another shuffle, and none, while an ask is out: let go, its answer dropped
  await run({ name: 'another shuffle, and none, let an ask go', seed: 17, total: 500, index: 160 }, [
    { op: 'shuffle' },
    { op: 'answer', ask: 0 },
    { op: 'next', to: 151 },
    { op: 'clear' },
    { op: 'answer', ask: 1 },
  ])
  //? Play Next adds no song of the list: still 49 ahead asks
  await run({ name: 'Play Next is no song of the list', seed: 18, total: 300, index: 140 }, [
    { op: 'playNext', ids: ['x1', 'x2', 'x3'] },
    { op: 'next', to: 150 },
    { op: 'next', to: 155 },
    { op: 'playNext', ids: ['x4'] },
    (r) => ({ op: 'answer', ask: newest(r) }),
  ])
  //? a page's failure, the song moving on meanwhile: nothing asked until the retry
  await run({ name: 'a failure waits for its retry', seed: 19, total: 700, index: 151 }, [
    (r) => ({ op: 'fail', ask: newest(r) }),
    { op: 'next', to: 170 }, { op: 'next', to: 190 }, { op: 'playNext', ids: ['x1'] },
    { op: 'retry' },
    (r) => ({ op: 'fail', ask: newest(r) }),
    { op: 'retry' },
    (r) => ({ op: 'answer', ask: newest(r) }),
  ])
  //? the fresh order after a 404 failing: the page asked again on the retry, its 404 again, and the fresh order then
  await run({ name: 'a fresh order after a 404 that fails', seed: 20, total: 450, index: 160 }, [
    (r) => ({ op: 'gone', ask: newest(r) }),
    (r) => ({ op: 'fail', ask: newest(r) }),
    { op: 'retry' },
    (r) => ({ op: 'gone', ask: newest(r) }),
    (r) => ({ op: 'answer', ask: newest(r) }),
  ])
  return runs
}

/** Seeded runs: whatever a listener and deadwax might do, in any order - but change Repeat, or start another
 *  shuffle, while a retry waits (the phone's one departure, above). */
async function seededRuns() {
  const runs = []
  for (let n = 0; n < 48; n++) {
    const seed = 3001 + n * 17
    const pickFrom = new ParkMiller(seed + 5)
    const r = () => pickFrom.next()
    const pick = (k) => Math.floor(r() * k)
    const total = [30, 199, 200, 201, 260, 450, 640, 900][n % 8]
    const level = [undefined, 'track', 'album'][n % 3]
    const repeat = REPEATS[pick(3)]
    current = new Run({ name: `seeded run ${n}`, seed, total, level, repeat, scope: n % 2 ? 'yours' : 'store',
      index: pick(Math.min(total, SHUFFLE_PAGE)) })
    await current.step({ op: 'begin' })
    let extra = 0
    for (let step = 0; step < 70; step++) {
      const queue = current.player.queue
      const waiting = current.timers.length > 0
      const open = current.open
      const roll = r()
      let op
      if (roll < 0.3 && queue.tracks.length) {
        const to = Math.min(queue.tracks.length - 1, queue.index + 1 + pick(roll < 0.1 ? 120 : 25))
        op = { op: 'next', to }
      } else if (roll < 0.36 && !waiting) {
        op = { op: 'repeat', mode: REPEATS[pick(3)] }
      } else if (roll < 0.41 && queue.tracks.length) {
        op = { op: 'playNext', ids: [`x${extra++}`] }
      } else if (roll < 0.43 && !waiting) {
        op = { op: 'shuffle' }
      } else if (roll < 0.44) {
        op = { op: 'clear' }
      } else if (roll < 0.75 && open.length) {
        //? mostly the newest ask, sometimes an older one the hook has let go
        const ask = r() < 0.85 ? open[open.length - 1] : open[pick(open.length)]
        const kind = r()
        const held = ask.name !== 'page' || current.orders.has(ask.args[0])
        if (kind < 0.12) op = { op: 'fail', ask: ask.n }
        else if (ask.name === 'page' && (!held || kind < 0.18)) op = { op: 'gone', ask: ask.n }
        else op = { op: 'answer', ask: ask.n }
      } else if (roll < 0.85 && waiting) {
        op = { op: 'retry' }
      } else if (queue.tracks.length) {
        op = { op: 'next', to: Math.min(queue.tracks.length - 1, queue.index + 1) }
      } else {
        op = { op: 'shuffle' }
        if (waiting) continue
      }
      await current.step(op)
    }
    runs.push(current.record)
  }
  return runs
}

/* ===== appendPage ===== */

function appendVectors() {
  const cases = [
    [[], []], [[], ['a', 'b']], [['a', 'b'], ['c']], [['a', 'b'], ['b', 'c']], [['a', 'b'], ['a', 'b']],
    [['a'], ['b', 'b']], [['a', 'a'], ['a', 'c', 'c']], [['a', 'b', 'c'], []], [['x'], ['y', 'x', 'z', 'y']],
  ]
  const generator = new ParkMiller(777)
  for (let n = 0; n < 30; n++) {
    const ids = (count) => Array.from({ length: count }, () => `s${Math.floor(generator.next() * 40)}`)
    cases.push([ids(Math.floor(generator.next() * 60)), ids(Math.floor(generator.next() * 30))])
  }
  return cases.map(([shown, page]) => ({ shown, page, out: P.appendPage(shown.map((id) => ({ id })), page.map((id) => ({ id }))).map((item) => item.id) }))
}

/* ===== writing ===== */

async function vectors() {
  return {
    made_from: 'ui/src/app/useShuffleFeed.ts and app/usePaged.ts (compiled, run under shuffle.sim.cjs\'s Preact stand-in), lib/upNext.ts, lib/yourLibrary.ts, lib/appFrame.ts and lib/artistPage.ts (compiled); player/api.ts and app/LibraryViews.tsx (read)',
    words: wordVectors(),
    elsewhere: elsewhereVectors(),
    ahead: aheadVectors(),
    runs: [...await scriptedRuns(), ...await seededRuns()],
    append: appendVectors(),
  }
}

/** JSON with one case a line - each run's head, then one step a line - and every character outside ASCII as an
 *  escape, so the file holds none raw and a change to the web shows as the lines it moves. */
function say(value) {
  const one = (v) => JSON.stringify(v)
  const lines = ['{']
  const keys = Object.keys(value)
  keys.forEach((key, k) => {
    const v = value[key]
    const comma = k < keys.length - 1 ? ',' : ''
    if (key === 'runs') {
      lines.push(` ${one(key)}: [`)
      v.forEach((run, r) => {
        const { steps, ...head } = run
        lines.push(`  ${one(head).slice(0, -1)}, "steps": [`)
        steps.forEach((step, n) => lines.push(`   ${one(step)}${n < steps.length - 1 ? ',' : ''}`))
        lines.push(`  ]}${r < v.length - 1 ? ',' : ''}`)
      })
      lines.push(` ]${comma}`)
    } else if (Array.isArray(v)) {
      lines.push(` ${one(key)}: [`)
      v.forEach((item, i) => lines.push(`  ${one(item)}${i < v.length - 1 ? ',' : ''}`))
      lines.push(` ]${comma}`)
    } else {
      lines.push(` ${one(key)}: ${one(v)}${comma}`)
    }
  })
  lines.push('}')
  return lines.join('\n').replace(/[\u0080-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'
}

vectors().then((value) => {
  const made = say(value)
  if (CHECK) {
    const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
    if (committed !== made) {
      console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-shuffle-vectors.cjs, then port the change to DeadwaxCore's Shuffle.swift or Songs.swift and see ShuffleVectorTests pass`)
      process.exit(1)
    }
    console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
  } else {
    fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
    fs.writeFileSync(FIXTURE, made)
    console.log(`wrote ${path.relative(REPO, FIXTURE)} (${made.length} bytes)`)
  }
}, (error) => {
  console.error(error)
  process.exit(1)
})
