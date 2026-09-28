/**
 * The phone player's engine - player/usePlayer.ts itself, not the pure rules under it - driven
 * through a fake DOM: audio elements that load, play, seek and end on a virtual clock the way
 * WebKit's do, taps that unlock them, the second of grace after a song ends, and a Navidrome that
 * answers after a delay.
 *
 * The other player sims hold lib/ to its answers. This one holds the WIRING, which is where the
 * review of the gapless and seek changes found what those sims couldn't: nothing reached the seek
 * handling in usePlayer, so the bar could hold a seek's target for twenty seconds after every seek,
 * or freeze at 0:00 when "previous" met a song still loading, and every sim would still pass. What
 * it pins: what the bar hears while a seek is on its way and after it lands (an update from before
 * it included), a 'seeked' that comes while another seek is still out, "previous" and "next" during
 * a seek, the readout across a song's end (on time, and landed early as Safari's engine does), a
 * seek on a song still loading, and a gapless handover - from memory, and for a transcode, never
 * fetched ahead - with the AirPlay button left alone by the standby.
 *
 * A script for the same reason as the other sims: there is no JS test runner here. It compiles
 * usePlayer.ts and what it imports with the repo's TypeScript into a temporary folder, beside a
 * ten-line preact/hooks that renders by calling the hook again.
 *
 * Run it with:  node ui/test/player.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-player-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/player/usePlayer.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

//? Hooks with a cursor, as Preact's are: rendering calls the hook again and gets the same engine and
//? the state as it is now. Effects run once, after the first render - usePlayer's has stable deps.
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f) => slot(() => ({ v: f() })).v
exports.useCallback = (f) => slot(() => ({ v: f })).v
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = (f) => { slot(() => { const e = { f }; current.effects.push(e); return e }) }
exports.root = (hook) => {
  const root = { slots: [], cursor: 0, effects: [] }
  return () => {
    const outer = current; current = root; root.cursor = 0
    try { const out = hook(); for (const e of root.effects.splice(0)) e.cleanup = e.f(); return out } finally { current = outer }
  }
}
`)

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== a virtual clock ===== */

let now = 0, seq = 0, tasks = []
function later(delay, fn) {
  const task = { at: now + Math.max(0, delay || 0), seq: ++seq, fn, dead: false }
  tasks.push(task)
  return task
}
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('setTimeout', (fn, delay) => later(delay, fn))
define('clearTimeout', (task) => { if (task) task.dead = true })
define('performance', { now: () => now })
//? promises settle between tasks, as they do between a browser's tasks
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

/* ===== taps, and WebKit's second of grace after a song ends ===== */

let gesture = false, graceUntil = -1
const inGesture = () => gesture || now <= graceUntil
function tap(fn) {
  gesture = true
  try { return fn() } finally { gesture = false }
}

/* ===== Navidrome, through deadwax ===== */

const songs = {}
const NET = { fetchDelay: 50, seekDelay: 300, staleClockWhileSeeking: false, answerEverySeek: false, landingError: 0, cannotPlay: /$^/ }
const net = { ...NET }
const fetched = []
const blobs = new Map()
let blobCount = 0
URL.createObjectURL = (blob) => { const address = `blob:deadwax.test/${++blobCount}`; blobs.set(address, blob.songId); return address }
URL.revokeObjectURL = (address) => { blobs.delete(address) }

function lookup(src) {
  const id = src.startsWith('blob:') ? blobs.get(src) : decodeURIComponent(/\/stream\/([^?]+)/.exec(src)[1])
  const song = songs[id]
  if (!song) return { fail: 4, delay: 1 }
  return { id, duration: song.duration, delay: src.startsWith('blob:') ? 2 : (song.delay ?? 60) }
}

define('fetch', (address, init = {}) => {
  address = String(address)
  if (address.includes('/scrobble/')) return Promise.resolve({ ok: true, status: 200, json: async () => ({}) })
  const [, id, format] = /\/stream\/([^?]+)\?format=(\w+)/.exec(address)
  fetched.push(`${decodeURIComponent(id)}?${format}`)
  return new Promise((resolve, reject) => {
    let aborted = false
    init.signal?.addEventListener('abort', () => { aborted = true; reject(new DOMException('aborted', 'AbortError')) })
    later(net.fetchDelay, () => {
      if (aborted) return
      const headers = { 'content-type': 'audio/flac', 'content-length': '1000' }
      resolve({
        ok: true, status: 200, body: null,
        headers: { get: (name) => headers[name.toLowerCase()] ?? null },
        blob: () => new Promise((done) => later(net.fetchDelay, () => { if (!aborted) done({ songId: decodeURIComponent(id) }) })),
      })
    })
  })
})

/* ===== audio elements, WebKit's way ===== */

const elements = []
class FakeAudio {
  constructor() {
    this.n = elements.length
    elements.push(this)
    this.attrs = {}
    this.listeners = {}
    this.muted = false
    this.playbackRate = 1
    this.preload = ''
    //? an element made in a tap has no restriction to lift
    this.unlocked = gesture
    this.gen = 0
    this.seekGen = 0
    this.strays = 0
    this.reset()
  }

  reset() {
    this.paused = true
    this.ended = false
    this.error = null
    this.readyState = 0
    this.duration = NaN
    this.seeking = false
    //? the clock currentTime reads (held at the song's length, as WebKit's is), where the audio
    //? really is (the two differ after a seek that landed off), and where to start once loaded
    this.clock = 0
    this.heard = 0
    this.before = 0
    this.startAt = 0
    this.playingNow = false
    this.pending = []
  }

  get src() { return this.attrs.src ?? '' }
  set src(value) { this.attrs.src = value; this.loadResource() }
  setAttribute(name, value) { this.attrs[name] = value }
  getAttribute(name) { return this.attrs[name] ?? null }
  removeAttribute(name) { delete this.attrs[name] }
  canPlayType(type) { return net.cannotPlay.test(type) ? '' : 'probably' }
  addEventListener(name, listener) { (this.listeners[name] ||= []).push(listener) }
  removeEventListener(name, listener) { this.listeners[name] = (this.listeners[name] || []).filter((l) => l !== listener) }
  dispatch(name, fields = {}) { for (const listener of (this.listeners[name] || []).slice()) listener({ type: name, target: this, ...fields }) }
  //? events are tasks, dispatched after the state that raised them has been set
  queue(name) { later(0, () => this.dispatch(name)) }

  get currentTime() {
    //? before it has the song, what it reads is where it was asked to start
    if (this.readyState === 0) return this.startAt
    //? an engine whose clock lags a seek: the time before it, still running, until it lands
    if (this.seeking && net.staleClockWhileSeeking) return Math.min(this.before, this.duration)
    return Math.min(this.clock, this.duration)
  }
  set currentTime(value) {
    //? HAVE_NOTHING: kept as where to begin - sought to at the metadata, and only if past 0
    if (this.readyState === 0) { this.startAt = value; return }
    this.seekTo(value)
  }

  seekTo(target) {
    if (!this.seeking) this.before = this.clock
    this.clock = target
    this.seeking = true
    this.ended = false
    const mine = ++this.seekGen, gen = this.gen
    this.queue('seeking')
    later(net.seekDelay, () => {
      if (gen !== this.gen) return
      if (mine !== this.seekGen) {
        //? an engine that answers every seek, with the newest still on its way
        if (net.answerEverySeek) { this.strays++; this.queue('seeked') }
        return
      }
      this.seeking = false
      this.heard = Math.max(0, Math.min(this.duration, target + net.landingError))
      this.queue('timeupdate')
      this.queue('seeked')
    })
  }

  load() { this.loadResource() }
  loadResource() {
    if (inGesture()) this.unlocked = true
    this.gen++
    if (this.tick) this.tick.dead = true
    for (const promise of this.pending) promise.reject(new DOMException('aborted', 'AbortError'))
    this.reset()
    const src = this.attrs.src
    if (!src) return
    const gen = this.gen, song = lookup(src)
    later(song.delay, () => {
      if (gen !== this.gen) return
      if (song.fail) {
        this.error = { code: song.fail }
        for (const promise of this.pending) promise.reject(new DOMException('failed', 'NotSupportedError'))
        this.pending = []
        this.queue('error')
        if (!this.paused) { this.paused = true; this.queue('pause') }
        return
      }
      this.duration = song.duration
      this.readyState = 4
      this.queue('durationchange')
      this.queue('loadedmetadata')
      //? WebKit's setReadyState: a start past 0 is sought to, and none at 0 - no 'seeked' for it
      const start = this.startAt
      this.startAt = 0
      if (start > 0) this.seekTo(start)
      this.queue('canplay')
      if (!this.paused) this.startPlaying()
    })
  }

  play() {
    return new Promise((resolve, reject) => {
      if (!(this.unlocked || inGesture())) { reject(new DOMException('refused', 'NotAllowedError')); return }
      if (inGesture()) this.unlocked = true
      if (this.error) { reject(new DOMException('failed', 'NotSupportedError')); return }
      if (this.ended) { this.ended = false; this.clock = 0; this.heard = 0 }
      this.pending.push({ resolve, reject })
      if (this.paused) { this.paused = false; this.queue('play') }
      if (this.readyState >= 3) this.startPlaying()
      else this.queue('waiting')
    })
  }

  /** The song fails part-way - the connection dropped, or a bad frame: the error, then (Chromium's
   *  order) the pause. A seek on its way never lands. */
  fail(code) {
    this.gen++
    if (this.tick) this.tick.dead = true
    this.error = { code }
    this.seeking = false
    this.playingNow = false
    this.queue('error')
    if (!this.paused) { this.paused = true; this.queue('pause') }
  }

  pause() {
    if (this.paused) return
    this.paused = true
    this.playingNow = false
    if (this.tick) this.tick.dead = true
    for (const promise of this.pending) promise.reject(new DOMException('aborted', 'AbortError'))
    this.pending = []
    this.queue('pause')
  }

  startPlaying() {
    if (this.playingNow) return
    this.playingNow = true
    for (const promise of this.pending) promise.resolve()
    this.pending = []
    this.queue('playing')
    const gen = this.gen
    const step = () => {
      if (gen !== this.gen || !this.playingNow) return
      const by = 0.25 * this.playbackRate
      if (this.seeking) {
        if (net.staleClockWhileSeeking) { this.before += by; this.queue('timeupdate') }
      } else {
        this.clock += by
        this.heard += by
        this.queue('timeupdate')
        //? the song ends when the AUDIO runs out, wherever the clock is
        if (this.heard >= this.duration - 1e-9) {
          this.playingNow = false
          this.paused = true
          this.ended = true
          this.queue('pause')
          later(0, () => { graceUntil = now + 1000; this.dispatch('ended') })
          return
        }
      }
      this.tick = later(250, step)
    }
    this.tick = later(250, step)
  }
}

const storage = new Map()
define('localStorage', { getItem: (key) => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, String(value)) })
define('document', { createElement: () => new FakeAudio(), body: { appendChild() {} } })
const media = { metadata: null, playbackState: 'none', handlers: {}, setActionHandler(action, handler) { this.handlers[action] = handler }, setPositionState() {} }
define('navigator', { mediaSession: media })
define('MediaMetadata', class { constructor(fields) { Object.assign(this, fields) } })
define('location', { href: 'http://deadwax.test/player/' })

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { usePlayer } = require(path.join(OUT, 'player/usePlayer.js'))
const { describeSeek, PENDING_MAX_MS } = require(path.join(OUT, 'lib/scrub.js'))
const { describeGaps } = require(path.join(OUT, 'lib/gapless.js'))

/** A fresh page: no elements, nothing queued, the storage empty - and a player, and what its bar hears. */
function page({ gapless = false, durations = {} } = {}) {
  tasks = []
  elements.length = 0
  fetched.length = 0
  blobs.clear()
  storage.clear()
  graceUntil = -1
  Object.assign(net, NET)
  for (const id of Object.keys(songs)) delete songs[id]
  for (const [id, duration] of Object.entries(durations)) songs[id] = { duration }
  if (gapless) storage.set('deadwax-player-gapless', 'on')
  const render = hooks.root(usePlayer)
  const heard = []
  render().onPosition((seconds) => heard.push({ at: now, s: seconds }))
  return {
    get player() { return render() },
    heard,
    lastHeard: () => heard[heard.length - 1].s,
    seekLine: () => describeSeek(render().lastSeek),
    gapLine: () => describeGaps(render().gaps),
  }
}

const tracks = (ids, suffixes = {}) => ids.map((id) => ({
  id, title: `song ${id}`, artist: 'a', album: 'b', albumId: 'al', coverArt: null, duration: songs[id]?.duration ?? 0,
  contentType: suffixes[id] === 'opus' ? 'audio/ogg' : 'audio/flac', suffix: suffixes[id] ?? 'flac',
}))
const near = (value, target, within = 0.6) => Math.abs(value - target) <= within

;(async () => {
  /* ======================================================================== */
  console.log('\na seek on its way: what the bar hears, and when it lets go')
  {
    //? an engine whose clock goes on reading the old time while it seeks, and says so in updates
    const p = page({ durations: { 1: 200, 2: 200 } })
    net.seekDelay = 2000
    net.staleClockWhileSeeking = true
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(10_000)
    const [e0] = elements
    check('song 1 playing, its clock running', e0.playingNow && near(e0.currentTime, 9.9, 0.5), true)
    const asked = now
    tap(() => p.player.seek(120))
    check('the bar hears the target the moment it is asked for', p.lastHeard(), 120)
    await run(1_900)
    const onItsWay = p.heard.filter((h) => h.at > asked && h.at < asked + 2_000)
    check('updates of the OLD time came while it was on its way', onItsWay.length >= 6 && near(e0.currentTime, 11.8, 0.5), true)
    check('...and through every one of them the bar heard only the target', onItsWay.every((h) => h.s === 120), true)
    check('the readout: asked, on its way', p.seekLine(), 'Last seek: asked 2:00, seeking…')
    await run(200)
    check('landed: what the element\'s clock said', p.seekLine(), 'Last seek: asked 2:00, the player said 2:00')
    await run(1_000)
    //? what fails if 'seeked' doesn't let go of the target: the bar would sit on 2:00 for PENDING_MAX_MS
    check('a second after it landed the bar follows the clock again, not the target', p.lastHeard() > 120.5, true)
    check(`...and well inside PENDING_MAX_MS (${PENDING_MAX_MS} ms)`, now - asked < PENDING_MAX_MS / 4, true)
  }

  /* ======================================================================== */
  console.log('\na \'seeked\' while another seek is still on its way')
  {
    const p = page({ durations: { 1: 200 } })
    net.seekDelay = 1_000
    net.answerEverySeek = true
    net.staleClockWhileSeeking = true
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(10_000)
    const [e0] = elements
    tap(() => p.player.seek(60))
    await run(500)
    tap(() => p.player.seek(150))
    await run(700)
    check('the first seek\'s \'seeked\' came, with the element still seeking', e0.strays === 1 && e0.seeking, true)
    check('the bar still hears the newest target, not the old clock', p.lastHeard(), 150)
    check('the readout isn\'t filled in from it', p.seekLine(), 'Last seek: asked 2:30, seeking…')
    await run(1_000)
    check('the newest one landed', p.seekLine(), 'Last seek: asked 2:30, the player said 2:30')
    check('...and the bar follows the clock from there', p.lastHeard() > 150.4, true)
  }

  /* ======================================================================== */
  console.log('\n"previous", "next" or a failure while a seek is on its way')
  {
    const p = page({ durations: { 1: 200, 2: 200 } })
    net.seekDelay = 2_000
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(10_000)
    const [e0] = elements
    tap(() => p.player.seek(120))
    await run(500)
    //? currentTime answers the target while seeking, so "previous" restarts - and its seek to 0:00
    //? takes the place of the one to 2:00, whose 'seeked' never comes
    tap(() => p.player.previous())
    await run(2_500)
    check('restarted: the readout says the seek was interrupted, not "the player said 0:00"',
      p.seekLine(), 'Last seek: asked 2:00, interrupted')
    check('the element is back at the top', near(e0.currentTime, 0.5, 0.6), true)
    check('...and so is the bar, following it', near(p.lastHeard(), 0.5, 0.6), true)

    tap(() => p.player.seek(90))
    await run(500)
    tap(() => p.player.next())
    await run(45_000)
    check('"next" before it landed: song 2', p.player.track.id, '2')
    check('45 s into song 2 the readout still says interrupted, not "seeking…"', p.seekLine(), 'Last seek: asked 1:30, interrupted')
    check('the bar hears song 2\'s clock, not the target', near(p.lastHeard(), 44.9, 0.6), true)
  }

  {
    //? the last song fails under a seek (a decode error, so no retry) and the queue stops there
    const p = page({ durations: { 1: 200 } })
    net.seekDelay = 2_000
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(10_000)
    tap(() => p.player.seek(120))
    await run(500)
    elements[0].fail(3)
    await run(30_000)
    check('the song failed before the seek landed and the queue stopped: interrupted', p.seekLine(), 'Last seek: asked 2:00, interrupted')
    check('...and nothing is playing', p.player.playing, false)
  }
  {
    //? a song that drops part-way under a seek is asked for again, and picks up where it stopped
    const p = page({ durations: { 1: 200 } })
    net.seekDelay = 1_000
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(10_000)
    tap(() => p.player.seek(120))
    await run(300)
    elements[0].fail(2)
    await run(4_000)
    check('dropped under the seek, then resumed at its target: the seek was interrupted', p.seekLine(), 'Last seek: asked 2:00, interrupted')
    check('playing again from where it was going', elements[0].playingNow && near(elements[0].currentTime, 121.5, 1), true)
    check('...the bar following it', near(p.lastHeard(), elements[0].currentTime, 0.01), true)
  }

  /* ======================================================================== */
  console.log('\nthe readout across a song\'s end')
  {
    const p = page({ durations: { 1: 20, 2: 20, 3: 30 } })
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    await run(2_000)
    tap(() => p.player.seek(15))
    await run(400)
    check('landed', p.seekLine(), 'Last seek: asked 0:15, the player said 0:15')
    await run(6_000)
    check('song 1 played to its end; song 2 playing', p.player.track.id, '2')
    check('its end says it landed where asked', p.seekLine(),
      'Last seek: asked 0:15, the player said 0:15 · the song ended on time, so it landed there')
    check('the change was timed, the one-element way', /^Last song change \d+ ms, one element$/.test(p.gapLine()), true)
    tap(() => p.player.seek(5))
    check('a seek in song 2 starts a new reading', p.seekLine(), 'Last seek: asked 0:05, seeking…')
    await run(400)
    check('...and it lands', p.seekLine(), 'Last seek: asked 0:05, the player said 0:05')

    //? Safari's engine landing 7 s early: its clock says the target, sits at the song's length while
    //? the song plays on, and 'ended' comes when the audio runs out
    net.landingError = -7
    tap(() => p.player.seek(10))
    await run(18_000)
    check('song 2 ended, song 3 playing', p.player.track.id, '3')
    check('its end says where it really landed', p.seekLine(),
      'Last seek: asked 0:10, the player said 0:10 · the song played on 7 s after its clock ended, so it really landed at about 0:03')
    net.landingError = 0
  }

  /* ======================================================================== */
  console.log('\na seek on a song still loading')
  {
    const p = page({ durations: { 1: 40, 2: 40 } })
    songs['1'].delay = 800
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(300)
    //? "previous" on the first song restarts it - a seek to 0:00, which an element still loading
    //? only keeps as where to start, and at the metadata doesn't seek to at all
    tap(() => p.player.previous())
    await run(5_000)
    check('it plays from the top', elements[0].playingNow && near(elements[0].currentTime, 4.5, 0.5), true)
    check('the bar follows the clock, not held at 0:00', near(p.lastHeard(), 4.5, 0.5), true)
    check('no seek of the listener\'s to report', p.seekLine(), 'No seek yet')
  }
  {
    const p = page({ durations: { 1: 40 } })
    songs['1'].delay = 800
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(300)
    tap(() => p.player.seek(30))
    check('a tap at 0:30 while it loads: on its way', p.seekLine(), 'Last seek: asked 0:30, seeking…')
    await run(1_500)
    check('sought when the song arrived, and landed', p.seekLine(), 'Last seek: asked 0:30, the player said 0:30')
    check('the bar follows from there', p.lastHeard() > 30, true)
  }
  {
    const p = page({ durations: { 1: 40 } })
    songs['1'].delay = 800
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(300)
    tap(() => p.player.seek(30))
    tap(() => p.player.seek(0))
    check('then Home before it arrived: the 0:30 seek was interrupted', p.seekLine(), 'Last seek: asked 0:30, interrupted')
    await run(5_000)
    check('it plays from the top, the bar following', near(elements[0].currentTime, 4.5, 0.5) && near(p.lastHeard(), 4.5, 0.5), true)
    check('...and the readout never says "seeking…" about the seek to 0:00', p.seekLine(), 'Last seek: asked 0:30, interrupted')
  }

  /* ======================================================================== */
  console.log('\na gapless handover')
  {
    const p = page({ gapless: true, durations: { 1: 8, 2: 8, 3: 8 } })
    check('the switch left on: two elements from the start', elements.length, 2)
    const [e0, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    check('the tap that played unlocked the second element too', e1.unlocked, true)
    e0.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'available' })
    check('the element playing says an AirPlay device is there: the button shows', p.player.airplay, true)
    await run(3_500)
    check('the next song downloaded once, as it is', fetched, ['2?raw'])
    check('the standby holds it in memory, muted and ready', e1.src.startsWith('blob:') && e1.muted && e1.readyState === 4, true)
    //? WebKit keeps the answer per element, and the standby was never told it: its loads repeat 'not-available'
    e1.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'not-available' })
    check('the standby\'s answer doesn\'t hide the AirPlay button', p.player.airplay, true)
    await run(5_000)
    check('song 1 ended: song 2 playing on the second element, heard', p.player.track.id === '2' && e1.playingNow && !e1.muted, true)
    check('the first muted and emptied', e0.muted && !e0.getAttribute('src'), true)
    check('the readout: handed over, from memory', /^Last song change \d+ ms, handed over, from memory$/.test(p.gapLine()), true)
    check('the bar hears the second element\'s clock', near(p.lastHeard(), e1.currentTime, 0.01) && p.lastHeard() < 1.5, true)
    tap(() => p.player.seek(5))
    await run(400)
    check('a seek goes to the element playing now', near(e1.currentTime, 5.25, 0.3) && e0.readyState === 0, true)
    check('...and lands', p.seekLine(), 'Last seek: asked 0:05, the player said 0:05')
  }
  {
    //? a song this browser can't play is transcoded, and a transcode never goes into memory: the
    //? standby is given its address, and nothing asks Navidrome for it ahead of that
    const p = page({ gapless: true, durations: { 1: 8, 2: 8 } })
    net.cannotPlay = /opus/
    const [, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2'], { 2: 'opus' }), 0))
    await run(3_500)
    check('the transcoded next song: nothing fetched ahead', fetched, [])
    check('the standby given its address, as MP3', /\/stream\/2\?format=mp3$/.test(e1.src), true)
    await run(5_000)
    check('handed over, streamed', p.player.track.id === '2' && e1.playingNow && /handed over, streamed$/.test(p.gapLine()), true)
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
