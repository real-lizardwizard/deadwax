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
 * fetched ahead - with the AirPlay button left alone by the standby. And, per browser, which
 * addresses it asks for: FLAC inside an MP4 from Safari (lib/streamWrap), taken into memory by the
 * gapless switch like any file, and said in the readout; the file as it is from Chromium.
 *
 * It also holds a MediaSource of its own, for the one-stream engine (player/streamSource.ts):
 * page({ mse: 'managed' }) is WebKit's ManagedMediaSource, page({ mse: 'plain' }) Chromium's
 * MediaSource, and neither (the default) is what every check above the MediaSource section runs on.
 * Its SourceBuffers parse the real fragmented MP4 a fake deadwax serves (wrap=fmp4: ftyp, moov, sidx,
 * then a moof and mdat a second), place the frames where WebKit would, refuse a song's frames after
 * another song's initialization segment, evict under a byte cap from where Safari 27.0 thinks the
 * playhead is, and the element plays only through what is buffered: it waits at a hole and ends
 * only after endOfStream(). Seeks clamp to the duration and `seekable` as WebKit's do. What it does
 * is read from WebKit's and Chromium's source (cited beside each rule) and what the lab's iPhone
 * logged; the section of checks at the end drives the fake directly, so a scenario that passes has
 * passed against something that behaves like the platform. Its fragmented MP4 is byte for byte what
 * src/flac_mp4.py's fmp4_layout() writes for the same frames.
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
//? a value with cycles (a MediaSource where null was expected) is shown by its kind, so a failing
//? check says FAIL and the rest still run, rather than the whole script dying on JSON.stringify
function show(value) {
  try {
    return JSON.stringify(value)
  } catch {
    return JSON.stringify(value, (key, v) => (v && typeof v === 'object' && !Array.isArray(v) && Object.getPrototypeOf(v) !== Object.prototype ? `[${v.constructor?.name ?? 'object'}]` : v))
  }
}
function check(label, actual, expected) {
  const ok = show(actual) === show(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${show(actual)}` +
              (ok ? '' : `  (expected ${show(expected)})`))
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
//? code that feature-detects through window.* finds the same globals a page would
if (!('window' in globalThis)) define('window', globalThis)
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
const NET = { fetchDelay: 50, seekDelay: 300, staleClockWhileSeeking: false, answerEverySeek: false, landingError: 0, cannotPlay: /$^/,
  //? songs deadwax sends as FLAC even when asked for an MP4 - a file it won't repackage
  sentAsFlac: new Set(),
  //? the MediaSource fake: how long a source takes to open, a seek over buffered data to land, an
  //? append (a fixed part and bytes per ms) and a remove to run
  mseOpenDelay: 5, mseSeekDelay: 10, appendDelay: 2, appendRate: 50_000, removeDelay: 2,
  //? a SourceBuffer's byte cap - null is the engine's own (5.26 MiB managed, 12 MiB plain) - and the
  //? gaps buffered ranges merge across (WebKit's timeFudgeFactor, 2002/24000 s) and playback crosses
  sbCapBytes: null, mseFudge: 2002 / 24000, gapTolerance: 0.125,
  //? seconds ahead that make HAVE_ENOUGH_DATA; ManagedMediaSource's streaming marks (10 s, 30 s);
  //? and what an init segment whose mvhd says 0 makes a managed source's duration (NaN; the lab's
  //? iPhone logged 0 - set it to 0 to model that)
  enoughAhead: 5, mmsLow: 10, mmsHigh: 30, mmsInitDuration: NaN,
  //? the fake deadwax's wrap=fmp4 bodies: bytes a chunk, one chunk every chunkDelay ms (null: the
  //? fetchDelay), and where a body stops arriving (bytes, for every song or as { [id]: bytes })
  bytesPerChunk: 256 * 1024, chunkDelay: null, bodyStallAt: null,
  //? scripted wrap=fmp4 answers - { [id or '*']: { status, scope, retryAfter, detail, times } } -
  //? and a slow make: { [id]: ms before the headers }
  fmp4Answer: {}, headerDelay: {} }
const net = { ...NET }
const fetched = []
//? what the page let go of before its answer came - the same labels as `fetched`
const abandoned = []
const blobs = new Map()
//? object URLs of MediaSources, which an element given one attaches rather than fetches
const sources = new Map()
let blobCount = 0
URL.createObjectURL = (object) => {
  const address = `blob:deadwax.test/${++blobCount}`
  if (object instanceof FakeMediaSource) sources.set(address, object)
  else blobs.set(address, object.songId)
  return address
}
URL.revokeObjectURL = (address) => { blobs.delete(address); sources.delete(address) }

function lookup(src) {
  const id = src.startsWith('blob:') ? blobs.get(src) : decodeURIComponent(/\/stream\/([^?]+)/.exec(src)[1])
  const song = songs[id]
  if (!song) return { fail: 4, delay: 1 }
  return { id, duration: song.duration, delay: src.startsWith('blob:') ? 2 : (song.delay ?? 60) }
}

define('fetch', (address, init = {}) => {
  address = String(address)
  if (address.includes('/scrobble/')) return Promise.resolve({ ok: true, status: 200, json: async () => ({}) })
  if (/[?&]wrap=fmp4(&|$)/.test(address)) return fetchFmp4(address, init)
  const [, id, format] = /\/stream\/([^?]+)\?format=(\w+)/.exec(address)
  const wrap = /[?&]wrap=mp4(&|$)/.test(address)
  const range = init.headers?.Range
  const label = `${decodeURIComponent(id)}?${format}${wrap ? '+mp4' : ''}${range ? ` ${range}` : ''}`
  fetched.push(label)
  return new Promise((resolve, reject) => {
    let aborted = false
    init.signal?.addEventListener('abort', () => { aborted = true; abandoned.push(label); reject(new DOMException('aborted', 'AbortError')) })
    later(net.fetchDelay, () => {
      if (aborted) return
      const mp4 = wrap && !net.sentAsFlac.has(decodeURIComponent(id))
      const headers = { 'content-type': mp4 ? 'audio/mp4' : 'audio/flac', 'content-length': range ? '2' : '1000' }
      resolve({
        ok: true, status: 200, body: null,
        headers: { get: (name) => headers[name.toLowerCase()] ?? null },
        blob: () => new Promise((done) => later(net.fetchDelay, () => { if (!aborted) done({ songId: decodeURIComponent(id) }) })),
      })
    })
  })
})

/* ===== FLAC in fragmented MP4, as deadwax's wrap=fmp4 writes it ===== */

//? The bytes are real: ftyp (iso5), moov (mvhd, trak with the fLaC + dfLa sample entry, mvex/trex),
//? a sidx indexing the fragments, then a moof + mdat per ~second of whole 4096-sample frames - the
//? layout src/flac_mp4.py's fmp4_layout() copies from the lab's ffmpeg files. What isn't real is the
//? audio: each "FLAC frame" is a sync code, the song's identity (16 bytes, also written as the
//? STREAMINFO MD5), the frame's number and filler - which is what lets a fake SourceBuffer tell one
//? song's frames from another's.

const FMP4_BLOCK = 4096
//? each song's audio: its rate, and its exact length - never whole seconds unless a test says so
//? (Navidrome's durations are whole seconds; the audio behind them isn't) - and its size
function mseSong(id) {
  const song = songs[id] || {}
  const rate = song.rate ?? 44100
  const samples = song.samples ?? Math.round((song.seconds ?? ((song.duration ?? 10) + 0.3717)) * rate)
  return { id, rate, samples, seconds: samples / rate, channels: song.channels ?? 2, bits: song.bits ?? 16,
           bytesPerSecond: song.bytesPerSecond ?? 112_000, version: song.version ?? 1, audio: song.audio ?? id }
}

const hexOf = (bytes) => Buffer.from(bytes).toString('hex')
//? identity (hex) -> song id, so a SourceBuffer can say whose frames it was given
const identities = new Map()
const fmp4Files = new Map()

function joinBytes(...parts) {
  let size = 0
  for (const part of parts) size += part.length
  const out = new Uint8Array(size)
  let at = 0
  for (const part of parts) { out.set(part, at); at += part.length }
  return out
}
class ByteWriter {
  constructor() { this.parts = [] }
  push(bytes) { this.parts.push(bytes); return this }
  u8(n) { return this.push(Uint8Array.of(n & 255)) }
  u16(n) { return this.push(Uint8Array.of((n >>> 8) & 255, n & 255)) }
  u32(n) { return this.push(Uint8Array.of((n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255)) }
  u64(n) { this.u32(Math.floor(n / 2 ** 32)); return this.u32(n % 2 ** 32) }
  ascii(text) { return this.push(Uint8Array.from(text, (c) => c.charCodeAt(0))) }
  zeros(n) { return this.push(new Uint8Array(n)) }
  bytes() { return joinBytes(...this.parts) }
}
const writer = () => new ByteWriter()
const mp4Box = (type, ...parts) => { const body = joinBytes(...parts); return writer().u32(8 + body.length).ascii(type).push(body).bytes() }
const mp4FullBox = (type, version, flags, ...parts) => mp4Box(type, writer().u32(((version << 24) | flags) >>> 0).bytes(), ...parts)
//? the sample entry's 16.16 rate, as isoflac.txt (and flac_mp4._entry_rate) writes it
function entryRate(rate) {
  let value = rate
  while (value > 0xffff && value % 2 === 0) value /= 2
  return (value <= 0xffff ? value : 0xffff) * 65536
}

function fmp4Head(song, identity, sizes) {
  const ftyp = mp4Box('ftyp', writer().ascii('iso5').u32(512).ascii('iso5').ascii('iso6').ascii('mp41').bytes())
  const matrix = writer().u32(0x10000).u32(0).u32(0).u32(0).u32(0x10000).u32(0).u32(0).u32(0).u32(0x40000000).bytes()
  //? durations 0 and no mehd: the length is only in the fragments, as ffmpeg's empty_moov writes it
  const mvhd = mp4FullBox('mvhd', 0, 0, writer().u32(0).u32(0).u32(song.rate).u32(0).u32(0x10000).u16(0x0100).zeros(10)
    .push(matrix).zeros(24).u32(2).bytes())
  const tkhd = mp4FullBox('tkhd', 0, 3, writer().u32(0).u32(0).u32(1).u32(0).u32(0).zeros(8).u16(0).u16(1).u16(0x0100).zeros(2)
    .push(matrix).u32(0).u32(0).bytes())
  const und = ((117 - 0x60) << 10) | ((110 - 0x60) << 5) | (100 - 0x60)
  const mdhd = mp4FullBox('mdhd', 0, 0, writer().u32(0).u32(0).u32(song.rate).u32(0).u16(und).u16(0).bytes())
  const hdlr = mp4FullBox('hdlr', 0, 0, writer().u32(0).ascii('soun').zeros(12).ascii('SoundHandler').u8(0).bytes())
  //? STREAMINFO: block sizes, frame sizes, rate (20 bits), channels - 1 (3), bits - 1 (5), samples
  //? (36) and the MD5 - here the song's identity
  const info = new Uint8Array(34)
  info.set([0x10, 0x00, 0x10, 0x00])
  const smallest = Math.min(...sizes), largest = Math.max(...sizes)
  info.set([(smallest >> 16) & 255, (smallest >> 8) & 255, smallest & 255, (largest >> 16) & 255, (largest >> 8) & 255, largest & 255], 4)
  info[10] = (song.rate >> 12) & 255
  info[11] = (song.rate >> 4) & 255
  info[12] = ((song.rate & 15) << 4) | ((song.channels - 1) << 1) | ((song.bits - 1) >> 4)
  info[13] = (((song.bits - 1) & 15) << 4) | (Math.floor(song.samples / 2 ** 32) & 15)
  info.set(writer().u32(song.samples % 2 ** 32).bytes(), 14)
  info.set(identity, 18)
  const dfla = mp4FullBox('dfLa', 0, 0, Uint8Array.of(0x80, 0, 0, 34), info)
  const entry = mp4Box('fLaC', writer().zeros(6).u16(1).zeros(8).u16(song.channels).u16(song.bits).u16(0).u16(0).u32(entryRate(song.rate)).bytes(), dfla)
  const stbl = mp4Box('stbl', mp4FullBox('stsd', 0, 0, writer().u32(1).bytes(), entry), mp4FullBox('stts', 0, 0, writer().u32(0).bytes()),
    mp4FullBox('stsc', 0, 0, writer().u32(0).bytes()), mp4FullBox('stsz', 0, 0, writer().u32(0).u32(0).bytes()),
    mp4FullBox('stco', 0, 0, writer().u32(0).bytes()))
  const dinf = mp4Box('dinf', mp4FullBox('dref', 0, 0, writer().u32(1).bytes(), mp4FullBox('url ', 0, 1)))
  const minf = mp4Box('minf', mp4FullBox('smhd', 0, 0, new Uint8Array(4)), dinf, stbl)
  const trak = mp4Box('trak', tkhd, mp4Box('mdia', mdhd, hdlr, minf))
  const trex = mp4FullBox('trex', 0, 0, writer().u32(1).u32(1).u32(0).u32(0).u32(0).bytes())
  return joinBytes(ftyp, mp4Box('moov', mvhd, trak, mp4Box('mvex', trex)))
}

//? tfhd flags 0x020038 (base is the moof; default duration, size and flags - 0x02000000, every
//? frame a sync sample); trun 0x201 (offset + sizes), or 0x301 when a frame is short (the last)
function fmp4Moof(sequence, decodeTime, blocks, sizes) {
  const same = blocks.every((block) => block === blocks[0])
  const each = same ? 4 : 8
  const moofSize = 8 + 16 + (8 + 28 + 20 + (20 + blocks.length * each))
  const run = writer().u32(blocks.length).u32(moofSize + 8)
  blocks.forEach((block, i) => { if (!same) run.u32(block); run.u32(sizes[i]) })
  const traf = mp4Box('traf',
    mp4FullBox('tfhd', 0, 0x020038, writer().u32(1).u32(blocks[0]).u32(sizes[0]).u32(0x02000000).bytes()),
    mp4FullBox('tfdt', 1, 0, writer().u64(decodeTime).bytes()),
    mp4FullBox('trun', 0, same ? 0x000201 : 0x000301, run.bytes()))
  return mp4Box('moof', mp4FullBox('mfhd', 0, 0, writer().u32(sequence).bytes()), traf)
}

/** The wrap=fmp4 file for a song, built once: { bytes, initEnd (ftyp + moov), headEnd (+ sidx),
 *  fragments: [{ start, end, units, payload, first, frames }], song, identity }. */
function fmp4File(id) {
  const song = mseSong(id)
  const key = [id, song.rate, song.samples, song.channels, song.bits, song.bytesPerSecond, song.audio].join('|')
  if (fmp4Files.has(key)) return fmp4Files.get(key)
  const identity = new Uint8Array(require('crypto').createHash('md5').update(`deadwax-fake:${song.audio}:${song.rate}:${song.samples}`).digest())
  identities.set(hexOf(identity), id)
  const blocks = []
  for (let left = song.samples; left > 0; left -= FMP4_BLOCK) blocks.push(Math.min(FMP4_BLOCK, left))
  //? FLAC frames vary in size; these by a deterministic couple of hundred bytes either way
  const sizes = blocks.map((block, i) => Math.max(24, Math.round(song.bytesPerSecond * block / song.rate) + ((i * 7919) % 257) - 128))
  //? about a second of whole frames each, as the server's _chunks() groups them (11 at 44.1 kHz)
  const groups = []
  let held = [], got = 0
  blocks.forEach((block, i) => { held.push(i); got += block; if (got >= song.rate) { groups.push(held); held = []; got = 0 } })
  if (held.length) groups.push(held)
  const head = fmp4Head(song, identity, sizes)
  let decodeTime = 0
  const pieces = groups.map((group, n) => {
    const own = group.map((i) => blocks[i]), bytes = group.map((i) => sizes[i])
    const moof = fmp4Moof(n + 1, decodeTime, own, bytes)
    const units = own.reduce((sum, b) => sum + b, 0), payload = bytes.reduce((sum, b) => sum + b, 0)
    decodeTime += units
    return { moof, units, payload, first: group[0], frames: group.length }
  })
  const refs = writer()
  for (const piece of pieces) refs.u32(piece.moof.length + 8 + piece.payload).u32(piece.units).u32(0x90000000)
  const sidx = mp4FullBox('sidx', 0, 0, writer().u32(1).u32(song.rate).u32(0).u32(0).u16(0).u16(pieces.length).bytes(), refs.bytes())
  const size = head.length + sidx.length + pieces.reduce((sum, p) => sum + p.moof.length + 8 + p.payload, 0)
  const bytes = new Uint8Array(size)
  bytes.set(head, 0)
  bytes.set(sidx, head.length)
  let at = head.length + sidx.length
  const fragments = pieces.map((piece) => {
    const start = at
    bytes.set(piece.moof, at)
    at += piece.moof.length
    bytes.set(writer().u32(8 + piece.payload).ascii('mdat').bytes(), at)
    at += 8
    for (let i = piece.first; i < piece.first + piece.frames; i++) {
      bytes[at] = 0xff
      bytes[at + 1] = 0xf8
      bytes.set(identity, at + 2)
      bytes.set(writer().u32(i).bytes(), at + 18)
      bytes.fill(i & 255, at + 22, at + sizes[i])
      at += sizes[i]
    }
    return { start, end: at, units: piece.units, payload: piece.payload, first: piece.first, frames: piece.frames }
  })
  const file = { bytes, initEnd: head.length, headEnd: head.length + sidx.length, fragments, song, identity: hexOf(identity) }
  fmp4Files.set(key, file)
  return file
}

/* ===== the fake deadwax answering wrap=fmp4 ===== */

//? every wrap=fmp4 request: { label, id, format, range, ifRange, at, status }
const fmp4Requests = []
const abortError = () => new DOMException('The operation was aborted.', 'AbortError')

//? a request's header, whether the page sent a Headers, a plain object or pairs
function headerIn(headers, name) {
  if (!headers) return null
  const want = name.toLowerCase()
  if (typeof headers.get === 'function') return headers.get(name)
  const pairs = Array.isArray(headers) ? headers : Object.entries(headers)
  const hit = pairs.find(([key]) => String(key).toLowerCase() === want)
  return hit ? String(hit[1]) : null
}

const DETAILS = { 400: 'wrap=fmp4 needs format=raw', 404: 'Navidrome has no song by that id', 415: 'this song can\'t be repackaged as fragmented MP4',
                  429: 'too many requests', 500: 'something went wrong', 503: 'not ready yet - try again shortly' }
function errorAnswer({ status, scope: given, retryAfter, detail, body, contentType }) {
  if (status === 0) return { status: 0 }
  //? deadwax's 503 always says whose trouble it is: this song's, unless the cache can't be used at all
  const scope = given ?? (status === 503 ? 'song' : undefined)
  const text = body ?? JSON.stringify(scope ? { detail: detail ?? DETAILS[status] ?? 'refused', scope } : { detail: detail ?? DETAILS[status] ?? 'refused' })
  const bytes = new TextEncoder().encode(text)
  const headers = { 'content-type': contentType ?? 'application/json', 'content-length': String(bytes.length), 'cache-control': 'no-store' }
  if (status === 503 || status === 429 || retryAfter != null) headers['retry-after'] = String(retryAfter ?? (scope === 'server' ? 30 : 2))
  return { status, headers, body: bytes }
}

//? what deadwax's answer_fragmented() and ranged_file() would say: 206 with Content-Range for one
//? satisfiable range, 200 with the whole file for none, a malformed one or a stale If-Range, 416
//? past the end; or whatever a test scripted for the song
function fmp4Answer(id, format, range, ifRange) {
  const key = net.fmp4Answer[id] ? id : net.fmp4Answer['*'] ? '*' : null
  if (key) {
    const scripted = net.fmp4Answer[key]
    if (scripted.times !== undefined && --scripted.times <= 0) delete net.fmp4Answer[key]
    return errorAnswer(scripted)
  }
  if (format !== 'raw') return errorAnswer({ status: 400 })
  if (!songs[id]) return errorAnswer({ status: 404 })
  const file = fmp4File(id), size = file.bytes.length
  const etag = `"fmp4-${id}-v${mseSong(id).version}"`
  const common = { 'content-type': 'audio/mp4', 'accept-ranges': 'bytes', etag, 'cache-control': 'no-cache' }
  const whole = { status: 200, headers: { ...common, 'content-length': String(size) }, body: file.bytes }
  if (!range || (ifRange != null && ifRange !== etag)) return whole
  const asked = /^bytes=(\d*)-(\d*)$/.exec(range.trim())
  if (!asked || (asked[1] === '' && asked[2] === '')) return whole
  let start, end
  if (asked[1] === '') { start = Math.max(0, size - Number(asked[2])); end = size - 1; if (Number(asked[2]) === 0) start = size }
  else {
    start = Number(asked[1])
    end = asked[2] === '' ? size - 1 : Number(asked[2])
    if (end < start) return whole
    end = Math.min(end, size - 1)
  }
  if (start >= size) return { status: 416, headers: { 'content-range': `bytes */${size}`, 'content-length': '0' }, body: new Uint8Array(0) }
  const body = file.bytes.subarray(start, end + 1)
  return { status: 206, headers: { ...common, 'content-range': `bytes ${start}-${end}/${size}`, 'content-length': String(body.length) }, body }
}

function fetchFmp4(address, init) {
  //? an address of another shape is the sim's mistake, not a network's: thrown, loudly, as above
  const [, rawId] = /\/stream\/([^?]+)\?/.exec(address)
  const format = /[?&]format=(\w+)/.exec(address)?.[1] ?? null
  const id = decodeURIComponent(rawId)
  const range = headerIn(init.headers, 'Range'), ifRange = headerIn(init.headers, 'If-Range')
  const label = `${id}?${format}+fmp4${range ? ` ${range}` : ''}`
  fetched.push(label)
  const request = { label, id, format, range, ifRange, at: now, status: null }
  fmp4Requests.push(request)
  const signal = init.signal
  //? `until`: when the last byte of the body will have come - an abort before it was a let-go
  const exchange = { aborted: false, until: Infinity, onAbort: [] }
  return new Promise((resolve, reject) => {
    if (signal?.aborted) { abandoned.push(label); reject(abortError()); return }
    signal?.addEventListener('abort', () => {
      if (exchange.aborted) return
      exchange.aborted = true
      if (now < exchange.until) abandoned.push(label)
      for (const stop of exchange.onAbort.splice(0)) stop()
      reject(abortError())
    })
    later(net.headerDelay[id] ?? net.fetchDelay, () => {
      if (exchange.aborted) return
      const answer = fmp4Answer(id, format, range, ifRange)
      request.status = answer.status
      //? status 0: the network failed - fetch rejects, as a browser's does
      if (answer.status === 0) { exchange.until = now; reject(new TypeError('Failed to fetch')); return }
      resolve(fakeResponse(address, id, answer, exchange))
    })
  })
}

//? A Response: headers now, the body in chunks of net.bytesPerChunk arriving one every chunkDelay
//? (so a slow network makes holes), stopping for good at net.bodyStallAt; read by getReader(),
//? arrayBuffer(), json() or text(), once, and every read rejecting AbortError once aborted.
function fakeResponse(url, id, answer, exchange) {
  const body = answer.body ?? new Uint8Array(0)
  const every = net.chunkDelay ?? net.fetchDelay
  const per = Math.max(1, net.bytesPerChunk)
  const stall = net.bodyStallAt !== null && typeof net.bodyStallAt === 'object' ? net.bodyStallAt[id] : net.bodyStallAt
  const limit = stall == null ? body.length : Math.min(body.length, stall)
  const chunks = []
  for (let at = 0, k = 1; at < body.length; at += per, k++) {
    if (at >= limit) { chunks.push({ stalled: true }); break }
    const end = Math.min(body.length, at + per)
    chunks.push({ bytes: body.slice(at, Math.min(end, limit)), at: now + k * every })
    if (end > limit) { chunks.push({ stalled: true }); break }
  }
  const stalled = chunks.some((chunk) => chunk.stalled)
  exchange.until = stalled ? Infinity : chunks.length ? chunks[chunks.length - 1].at : now
  let used = false
  const take = () => {
    if (used) throw new TypeError('Failed to execute on \'Response\': body stream already read')
    used = true
  }
  const whole = () => new Promise((resolve, reject) => {
    if (exchange.aborted) { reject(abortError()); return }
    if (stalled) { exchange.onAbort.push(() => reject(abortError())); return }
    const task = later(Math.max(0, exchange.until - now), () => { if (!exchange.aborted) resolve(body.slice()) })
    exchange.onAbort.push(() => { task.dead = true; reject(abortError()) })
  })
  const headers = answer.headers ?? {}
  const entries = () => Object.entries(headers)
  return {
    ok: answer.status >= 200 && answer.status < 300,
    status: answer.status,
    statusText: '',
    url,
    redirected: false,
    type: 'basic',
    headers: {
      get: (name) => headers[String(name).toLowerCase()] ?? null,
      has: (name) => String(name).toLowerCase() in headers,
      forEach: (fn) => entries().forEach(([key, value]) => fn(value, key)),
      entries,
      [Symbol.iterator]: () => entries()[Symbol.iterator](),
    },
    get bodyUsed() { return used },
    body: {
      getReader() {
        take()
        let k = 0, cancelled = false
        return {
          read() {
            return new Promise((resolve, reject) => {
              if (exchange.aborted) { reject(abortError()); return }
              if (cancelled || k >= chunks.length) { resolve({ done: true, value: undefined }); return }
              const chunk = chunks[k]
              if (chunk.stalled) { exchange.onAbort.push(() => reject(abortError())); return }
              const task = later(Math.max(0, chunk.at - now), () => {
                if (exchange.aborted) return
                k++
                resolve({ done: false, value: chunk.bytes })
              })
              exchange.onAbort.push(() => { task.dead = true; reject(abortError()) })
            })
          },
          cancel() { cancelled = true; return Promise.resolve() },
          releaseLock() {},
        }
      },
    },
    arrayBuffer: () => { take(); return whole().then((bytes) => bytes.buffer) },
    json: () => { take(); return whole().then((bytes) => JSON.parse(new TextDecoder().decode(bytes))) },
    text: () => { take(); return whole().then((bytes) => new TextDecoder().decode(bytes)) },
  }
}

/* ===== audio elements, WebKit's way ===== */

const elements = []
class FakeAudio {
  constructor() {
    this.n = elements.length
    elements.push(this)
    this.attrs = {}
    this.listeners = {}
    this.muted = false
    this.volume = 1
    this.playbackRate = 1
    this.preload = ''
    //? an element made in a tap has no restriction to lift
    this.unlocked = gesture
    this.gen = 0
    this.seekGen = 0
    this.strays = 0
    //? a MediaSource given as srcObject; the one attached (either way in); whether AirPlay is off
    //? for it (a ManagedMediaSource won't open until it is); the last availability it announced;
    //? and every stall of playback over a MediaSource, { at, pos }
    this.srcObj = null
    this.ms = null
    this.remoteOff = false
    this.lastAvailability = null
    this.stalls = []
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
    //? over a MediaSource: where the playhead was when a seek began (what Safari 27.0 goes on
    //? taking for the time until it lands), the landing on its way, and when the playing tick last ran
    this.preSeek = 0
    this.landing = null
    this.lastTickAt = 0
  }

  get src() { return this.attrs.src ?? '' }
  set src(value) { this.attrs.src = value; this.loadResource() }
  setAttribute(name, value) { this.attrs[name] = value }
  getAttribute(name) { return this.attrs[name] ?? null }
  removeAttribute(name) { delete this.attrs[name] }
  canPlayType(type) { return net.cannotPlay.test(type) ? '' : 'probably' }
  //? as the DOM's: once and signal honoured, the same listener added twice kept once
  addEventListener(name, listener, options) { listen(this.listeners, name, listener, options) }
  removeEventListener(name, listener) { unlisten(this.listeners, name, listener) }
  dispatch(name, fields = {}) {
    if (name === 'webkitplaybacktargetavailabilitychanged') this.lastAvailability = fields.availability
    deliver(this, this.listeners, { type: name, target: this, currentTarget: this, ...fields })
  }
  //? events are tasks, dispatched after the state that raised them has been set
  queue(name) { later(0, () => this.dispatch(name)) }

  get srcObject() { return this.srcObj }
  set srcObject(value) {
    //? WebKit takes a ManagedMediaSource here; Chromium only a MediaStream - a MediaSource is a
    //? TypeError there, and a blob: address the way in
    if (value != null && !(value instanceof FakeManagedMediaSource)) {
      throw new TypeError('Failed to set the \'srcObject\' property on \'HTMLMediaElement\': The provided value is not of type \'MediaStream\'.')
    }
    this.srcObj = value ?? null
    this.loadResource()
  }
  get disableRemotePlayback() { return this.remoteOff }
  set disableRemotePlayback(value) {
    const was = this.remoteOff
    this.remoteOff = !!value
    if (!this.remoteOff || was) return
    //? WebKit stops this element's AirPlay availability, with one last "not available" if the last
    //? it said was "available" (HTMLMediaElement.cpp:7640-7668)...
    if (this.lastAvailability === 'available') {
      later(0, () => this.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'not-available' }))
    }
    //? ...and a ManagedMediaSource held back for want of it opens now (1103-1112)
    if (this.ms?.deferred) this.ms.scheduleOpen()
  }
  get currentSrc() { return this.srcObj ? '' : this.attrs.src ?? '' }
  get networkState() {
    if (this.error?.code === 4) return 3
    if (this.ms) return this.ms.readyState === 'ended' ? 1 : 2
    if (!this.srcObj && !this.attrs.src) return 0
    return this.readyState >= 4 ? 1 : 2
  }
  //? a file's is all of it once loaded; a MediaSource's is what its SourceBuffers hold
  bufferedList() {
    if (this.ms) return this.ms.bufferedForElement()
    return this.readyState >= 1 && Number.isFinite(this.duration) ? [[0, this.duration]] : []
  }
  get buffered() { return new FakeTimeRanges(this.bufferedList()) }
  //? over a MediaSource, [0, duration] for a finite duration and [0, the buffered end] otherwise
  seekableList() {
    if (!this.ms) return this.readyState >= 1 && Number.isFinite(this.duration) ? [[0, this.duration]] : []
    if (this.readyState === 0) return []
    if (Number.isFinite(this.duration)) return [[0, this.duration]]
    const ranges = this.bufferedList()
    return ranges.length ? [[0, ranges[ranges.length - 1][1]]] : []
  }
  get seekable() { return new FakeTimeRanges(this.seekableList()) }

  get currentTime() {
    //? before it has the song, what it reads is where it was asked to start
    if (this.readyState === 0) return this.startAt
    //? over a MediaSource the clock is where the audio is, and while seeking, the target
    if (this.ms) return this.clock
    //? an engine whose clock lags a seek: the time before it, still running, until it lands
    if (this.seeking && net.staleClockWhileSeeking) return Math.min(this.before, this.duration)
    return Math.min(this.clock, this.duration)
  }
  set currentTime(value) {
    //? HAVE_NOTHING: kept as where to begin - sought to at the metadata, and only if past 0
    if (this.readyState === 0) { this.startAt = value; return }
    if (this.ms) { this.mseSeek(value); return }
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
    //? any load detaches an attached MediaSource for good: closed, its SourceBuffers gone
    if (this.ms) { const source = this.ms; this.ms = null; source.detach() }
    this.reset()
    //? a MediaSource as srcObject beats the src attribute
    if (this.srcObj) { this.attachSource(this.srcObj); return }
    const src = this.attrs.src
    if (!src) return
    if (sources.has(src)) { this.attachSource(sources.get(src)); return }
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
      //? played to its end: back to the start - over a MediaSource a real seek, which waits if the
      //? start is no longer buffered
      if (this.ended) { this.ended = false; if (this.ms) this.mseSeek(0); else { this.clock = 0; this.heard = 0 } }
      this.pending.push({ resolve, reject })
      const wasPaused = this.paused
      if (this.paused) { this.paused = false; this.queue('play') }
      if (this.readyState >= 3) this.startPlaying()
      //? over a MediaSource 'waiting' comes only for a play() that unpaused it, as the spec says
      else if (wasPaused || !this.ms) this.queue('waiting')
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
    if (this.ms) { this.lastTickAt = now; this.tick = later(this.mseDelay(), () => this.mseStep(gen)); return }
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

  /* --- over a MediaSource --- */

  attachSource(source) {
    //? a source attached to another element can't be attached here: the media data cannot be fetched
    if (source.element) { const gen = this.gen; later(1, () => { if (gen === this.gen) this.mseError(4) }); return }
    this.ms = source
    source.attach(this)
  }

  //? the time eviction and ManagedMediaSource's streaming are judged at: Safari 27.0 takes its
  //? renderer's, which stays where the playhead was until a seek lands
  //? (MediaSourcePrivateAVFObjC::currentTime); Chromium its pipeline's, the seek's target
  mediaTime(managed) { return managed && this.seeking ? this.preSeek : this.clock }

  //? where playback from `t` runs out: the end of the buffered range holding it, carried across gaps
  //? under the gap tolerance, as WebKit bridges them; null when nothing is buffered at `t`
  playableEnd(t) {
    let end = null
    for (const [start, stop] of this.bufferedList()) {
      if (end === null) { if (start <= t + net.gapTolerance && stop > t) end = stop }
      else if (start <= end + net.gapTolerance) end = Math.max(end, stop)
      else break
    }
    return end
  }
  covered(t) { const end = this.playableEnd(t); return end !== null && end > t }

  //? WebKit's seek steps 6-8: no later than the duration, no earlier than 0, then the nearest point
  //? of `seekable` - so a seek past what is seekable lands at its end, and with nothing seekable the
  //? seek is dropped. Over buffered data it lands after mseSeekDelay; otherwise it waits for data.
  mseSeek(target) {
    let t = Number(target)
    if (t > this.duration) t = this.duration
    if (!(t > 0)) t = 0
    const seekable = this.seekableList()
    if (!seekable.length) { this.seeking = false; return }
    if (!seekable.some(([start, end]) => start <= t && t <= end)) t = nearestPoint(seekable, t, this.clock)
    if (!this.seeking) this.preSeek = this.clock
    this.clock = this.heard = t
    this.seeking = true
    this.ended = false
    this.seekGen++
    if (this.landing) { this.landing.dead = true; this.landing = null }
    this.queue('seeking')
    if (this.covered(t)) this.mseScheduleLanding()
    else this.mseWaitForSeek()
    this.ms.recheckStreaming()
  }
  //? WebKit completes a seek some hops after the data is there (prepare, re-enqueue, then 'seeked'),
  //? and until it has, the old playhead is the time - which an append in between is judged by
  mseScheduleLanding() {
    const gen = this.gen, mine = this.seekGen
    this.landing = later(net.mseSeekDelay, () => {
      this.landing = null
      if (gen !== this.gen || mine !== this.seekGen || !this.seeking) return
      if (this.covered(this.clock)) this.mseLand()
      else this.mseWaitForSeek()
    })
  }
  //? nothing at the target: HAVE_METADATA, and 'waiting' if it was playing
  mseWaitForSeek() {
    const was = this.readyState
    if (was > 1) this.readyState = 1
    if (this.playingNow) {
      if (this.tick) this.tick.dead = true
      this.playingNow = false
      if (was >= 3) this.queue('waiting')
    }
  }
  mseLand() {
    this.seeking = false
    this.landing = null
    //? fragmented MP4 seeks land exactly - unless a test says otherwise
    this.clock = this.heard = Math.max(0, this.clock + net.landingError)
    //? a tick still running counts its playing from here, not from before the seek
    this.lastTickAt = now
    this.queue('timeupdate')
    this.queue('seeked')
    this.ms.recheckStreaming()
    this.mseLevel()
  }

  /** After anything that changes what is buffered: the first init segment brings HAVE_METADATA, a
   *  seek waiting for data lands, and readyState follows the data at the playhead. */
  mseUpdate() {
    const source = this.ms
    if (!source || this.error) return
    if (this.readyState === 0) {
      if (!source.initReceived) return
      this.readyState = 1
      this.duration = source._duration
      this.queue('durationchange')
      this.queue('loadedmetadata')
      //? WebKit's setReadyState: a start past 0 is sought to, and none at 0
      const start = this.startAt
      this.startAt = 0
      if (start > 0) this.mseSeek(start)
    }
    if (this.seeking) { if (!this.landing && this.covered(this.clock)) this.mseScheduleLanding() }
    else this.mseLevel()
    source.recheckStreaming()
  }
  mseLevel() {
    const end = this.playableEnd(this.clock)
    let level = 1
    if (end !== null) {
      const ahead = end - this.clock
      const toTheEnd = this.ms.readyState === 'ended' && end >= this.duration - 1e-6
      level = toTheEnd || ahead >= net.enoughAhead ? 4 : ahead > 1e-6 ? 3 : 2
    }
    const was = this.readyState
    this.readyState = level
    if (was < 3 && level >= 3) {
      this.queue('canplay')
      if (!this.paused) this.startPlaying()
    } else if (was >= 3 && level < 3 && this.playingNow) this.mseStall()
    //? stalled at the end of the data, and the source has ended there: that is the end
    if (!this.paused && !this.playingNow && this.ms.readyState === 'ended' && this.clock >= this.duration - 1e-6) this.mseEnd()
  }
  mseStall() {
    if (this.tick) this.tick.dead = true
    this.playingNow = false
    this.stalls.push({ at: now, pos: this.clock })
    this.queue('waiting')
  }
  //? the next tick: a quarter second, or sooner when the data runs out sooner - so a stall or the end
  //? comes at the moment it would
  mseDelay() {
    if (this.seeking) return 250
    const end = this.playableEnd(this.clock)
    const room = end === null ? 0 : end - this.clock
    return Math.max(0, Math.min(250, room / this.playbackRate * 1000))
  }
  mseStep(gen) {
    if (gen !== this.gen || !this.playingNow || !this.ms) return
    const elapsed = (now - this.lastTickAt) / 1000
    this.lastTickAt = now
    if (this.seeking) { this.tick = later(250, () => this.mseStep(gen)); return }
    const end = this.playableEnd(this.clock)
    const room = end === null ? 0 : Math.max(0, end - this.clock)
    const step = Math.min(elapsed * this.playbackRate, room)
    const out = room - step <= 1e-9
    if (step > 0) {
      //? run out: exactly at the end of the data, not a rounding error short of it
      this.clock = this.heard = out ? end : this.clock + step
      this.queue('timeupdate')
    }
    this.ms.recheckStreaming()
    if (out) {
      //? out of data: the end only if the source has ended and this is its duration; otherwise a
      //? stall - HAVE_CURRENT_DATA at the end of what played, 'waiting', never 'ended'
      if (this.ms.readyState === 'ended' && this.clock >= this.duration - 1e-6) { this.mseEnd(); return }
      this.readyState = end === null ? 1 : 2
      this.mseStall()
      return
    }
    this.tick = later(this.mseDelay(), () => this.mseStep(gen))
  }
  mseEnd() {
    if (this.tick) this.tick.dead = true
    this.playingNow = false
    this.paused = true
    this.ended = true
    this.queue('pause')
    later(0, () => { graceUntil = now + 1000; this.dispatch('ended') })
  }
  //? the MediaSource's end-of-stream with an error: before metadata the media data cannot be fetched
  //? (4); after it the media is corrupt (3) or the network failed (2) - the error, then the pause
  mseError(code) {
    this.gen++
    if (this.tick) this.tick.dead = true
    if (this.landing) { this.landing.dead = true; this.landing = null }
    this.error = { code }
    this.seeking = false
    this.playingNow = false
    for (const promise of this.pending) promise.reject(new DOMException('failed', code === 4 ? 'NotSupportedError' : 'AbortError'))
    this.pending = []
    this.queue('error')
    if (!this.paused) { this.paused = true; this.queue('pause') }
  }
}

/* ===== MediaSource: WebKit's ManagedMediaSource, and Chromium's plain one ===== */

//? WebKit gives an audio-only SourceBuffer 5% of its 110,376,422-byte budget on iOS
//? (SourceBuffer.cpp:700-729); Chromium 12 MiB for audio (demuxer_memory_limit.h)
const MANAGED_CAP_BYTES = 5_518_821
const PLAIN_CAP_BYTES = 12 * 1024 * 1024
//? the lab's iPhone said yes to 'fLaC' only; Chromium's registry has both spellings
const MANAGED_TYPE = /^audio\/mp4;\s*codecs="?fLaC"?$/
const PLAIN_TYPE = /^audio\/mp4;\s*codecs="?(?:flac|fLaC)"?$/
//? what lets the fake make SourceBuffers when page code can't (new SourceBuffer() is a TypeError)
const INTERNAL = Symbol('made by the fake')
//? every MediaSource made on this page, for checks
const mediaSources = []
const dom = (name, message) => new DOMException(message, name)

function listen(store, name, listener, options) {
  if (!listener) return
  const settings = typeof options === 'object' && options !== null ? options : {}
  if (settings.signal?.aborted) return
  const list = (store[name] ||= [])
  if (list.some((entry) => entry.listener === listener)) return
  list.push({ listener, once: !!settings.once })
  settings.signal?.addEventListener('abort', () => unlisten(store, name, listener))
}
function unlisten(store, name, listener) {
  if (store[name]) store[name] = store[name].filter((entry) => entry.listener !== listener)
}
//? listeners removed by an earlier one aren't called; `on<name>` properties are, last
function deliver(target, store, event) {
  const name = event.type
  for (const entry of (store[name] || []).slice()) {
    if (!(store[name] || []).includes(entry)) continue
    if (entry.once) unlisten(store, name, entry.listener)
    if (typeof entry.listener === 'function') entry.listener.call(target, event)
    else entry.listener.handleEvent(event)
  }
  const handler = target[`on${name}`]
  if (typeof handler === 'function') handler.call(target, event)
}

class FakeTarget {
  constructor() { this.listeners = {} }
  addEventListener(name, listener, options) { listen(this.listeners, name, listener, options) }
  removeEventListener(name, listener) { unlisten(this.listeners, name, listener) }
  dispatchEvent(event) { deliver(this, this.listeners, event); return true }
  //? events are queued tasks, as the MSE spec queues them: they arrive after whatever the caller does next
  fire(name, fields = {}) { later(0, () => deliver(this, this.listeners, { type: name, target: this, currentTarget: this, ...fields })) }
  fireEvent(event) { later(0, () => { event.target = this; event.currentTarget = this; deliver(this, this.listeners, event) }) }
}

class FakeTimeRanges {
  constructor(list) { this.list = list.map(([start, end]) => [start, end]) }
  get length() { return this.list.length }
  start(i) { return this.list[this.index(i, 'start')][0] }
  end(i) { return this.list[this.index(i, 'end')][1] }
  index(i, name) {
    if (!(i >= 0 && i < this.list.length)) {
      throw dom('IndexSizeError', `Failed to execute '${name}' on 'TimeRanges': The index provided (${i}) is greater than or equal to the maximum bound (${this.list.length}).`)
    }
    return Math.floor(i)
  }
}

class FakeBufferedChangeEvent {
  constructor(type, init = {}) {
    this.type = type
    this.addedRanges = init.addedRanges ?? new FakeTimeRanges([])
    this.removedRanges = init.removedRanges ?? new FakeTimeRanges([])
    this.target = null
    this.currentTarget = null
  }
}

//? parts of `a` that aren't in `b`, and parts in both
function subtractRanges(a, b) {
  const out = []
  for (const [s0, e0] of a) {
    let pieces = [[s0, e0]]
    for (const [s1, e1] of b) {
      pieces = pieces.flatMap(([s, e]) => {
        if (e1 <= s || s1 >= e) return [[s, e]]
        const kept = []
        if (s1 > s) kept.push([s, s1])
        if (e1 < e) kept.push([e1, e])
        return kept
      })
    }
    out.push(...pieces)
  }
  return out.filter(([s, e]) => e - s > 1e-9)
}
function intersectRanges(a, b) {
  const out = []
  for (const [s0, e0] of a) for (const [s1, e1] of b) {
    const start = Math.max(s0, s1), end = Math.min(e0, e1)
    if (end > start) out.push([start, end])
  }
  return out.sort((x, y) => x[0] - y[0])
}
//? the point of `ranges` nearest `t`, the one nearer `from` on a tie (HTML's seek step 8)
function nearestPoint(ranges, t, from) {
  let best = null, distance = Infinity
  for (const [start, end] of ranges) for (const point of [start, end]) {
    const d = Math.abs(point - t)
    if (d < distance || (d === distance && Math.abs(point - from) < Math.abs(best - from))) { best = point; distance = d }
  }
  return best
}

class FakeSourceBufferList extends FakeTarget {
  constructor(token) {
    if (token !== INTERNAL) throw new TypeError('Illegal constructor')
    super()
    this.items = []
  }
  get length() { return this.items.length }
  [Symbol.iterator]() { return this.items[Symbol.iterator]() }
  _replace(items, added) {
    for (let i = 0; i < Math.max(this.items.length, items.length); i++) {
      if (i < items.length) this[i] = items[i]
      else delete this[i]
    }
    this.items = items
    this.fire(added ? 'addsourcebuffer' : 'removesourcebuffer')
  }
}

class FakeMediaSource extends FakeTarget {
  constructor() {
    super()
    this._readyState = 'closed'
    this._duration = NaN
    this.sourceBuffers = new FakeSourceBufferList(INTERNAL)
    this.activeSourceBuffers = new FakeSourceBufferList(INTERNAL)
    //? the element it is attached to; whether its open is held back (ManagedMediaSource without
    //? disableRemotePlayback); a count of attachments, so a stale open does nothing
    this.element = null
    this.deferred = false
    this.attachGen = 0
    mediaSources.push(this)
  }
  static isTypeSupported(type) { return PLAIN_TYPE.test(String(type)) }
  get managed() { return false }
  get readyState() { return this._readyState }
  get duration() { return this._readyState === 'closed' ? NaN : this._duration }
  set duration(value) {
    if (typeof value !== 'number' || Number.isNaN(value) || value < 0) {
      throw new TypeError(`Failed to set the 'duration' property on 'MediaSource': The value provided (${value}) is negative or NaN.`)
    }
    if (this._readyState !== 'open') throw dom('InvalidStateError', 'The MediaSource\'s readyState is not \'open\'.')
    if (this.anyUpdating()) throw dom('InvalidStateError', 'The \'updating\' attribute is true on one or more of this MediaSource\'s SourceBuffers.')
    const highest = this.highestStart()
    if (highest !== null && value < highest) {
      throw dom('InvalidStateError', `Setting duration below highest presentation timestamp of any buffered coded frames is disallowed. Instead, first do asynchronous remove(${value}, ${this._duration}) on all sourceBuffers, where each remove's updateend event triggers a set of the duration.`)
    }
    //? past the buffered end is allowed, and makes that much seekable
    this.durationChange(Math.max(value, this.highestEnd() ?? 0))
  }
  addSourceBuffer(type) {
    type = String(type)
    if (!type) throw new TypeError('The type provided is empty.')
    if (!this.constructor.isTypeSupported(type)) throw dom('NotSupportedError', `The type provided ('${type}') is unsupported.`)
    if (this._readyState !== 'open') throw dom('InvalidStateError', 'The MediaSource\'s readyState is not \'open\'.')
    const buffer = new (this.managed ? FakeManagedSourceBuffer : FakeSourceBuffer)(INTERNAL, this, type)
    this.sourceBuffers._replace([...this.sourceBuffers.items, buffer], true)
    return buffer
  }
  removeSourceBuffer(buffer) {
    if (!this.sourceBuffers.items.includes(buffer)) throw dom('NotFoundError', 'The SourceBuffer provided is not contained in this MediaSource.')
    buffer.leave()
    this.sourceBuffers._replace(this.sourceBuffers.items.filter((b) => b !== buffer), false)
    if (this.activeSourceBuffers.items.includes(buffer)) this.activeSourceBuffers._replace(this.activeSourceBuffers.items.filter((b) => b !== buffer), false)
    this.recheckStreaming()
  }
  endOfStream(error) {
    if (error !== undefined && error !== 'network' && error !== 'decode') {
      throw new TypeError(`Failed to execute 'endOfStream' on 'MediaSource': The provided value '${error}' is not a valid enum value of type EndOfStreamError.`)
    }
    if (this._readyState !== 'open') throw dom('InvalidStateError', 'The MediaSource\'s readyState is not \'open\'.')
    if (this.anyUpdating()) throw dom('InvalidStateError', 'The \'updating\' attribute is true on one or more of this MediaSource\'s SourceBuffers.')
    this.endWith(error)
  }

  /* --- the fake's own --- */

  anyUpdating() { return this.sourceBuffers.items.some((buffer) => buffer.updating) }
  get initReceived() { const all = this.sourceBuffers.items; return all.length > 0 && all.every((buffer) => buffer.initReceived) }
  highestEnd() {
    let end = null
    for (const buffer of this.sourceBuffers.items) if (buffer.frames.length) end = Math.max(end ?? 0, buffer.frames[buffer.frames.length - 1].end)
    return end
  }
  highestStart() {
    let start = null
    for (const buffer of this.sourceBuffers.items) if (buffer.frames.length) start = Math.max(start ?? 0, buffer.frames[buffer.frames.length - 1].start)
    return start
  }
  //? what the element's `buffered` is: the active SourceBuffers' ranges intersected, the last one
  //? carried to the highest end once the source has ended
  bufferedForElement() {
    const lists = this.activeSourceBuffers.items.map((buffer) => buffer.ranges())
    if (!lists.length) return []
    let out = lists[0]
    for (const list of lists.slice(1)) out = intersectRanges(out, list)
    if (this._readyState === 'ended' && out.length) out[out.length - 1][1] = Math.max(out[out.length - 1][1], this.highestEnd() ?? 0)
    return out
  }
  attach(element) {
    this.element = element
    this.attachGen++
    //? WebKit holds a ManagedMediaSource's open back until AirPlay is off for the element
    //? (MediaSource.cpp:323-324, 1147-1162): readyState stays 'closed', no sourceopen, no error
    if (this.managed && !element.disableRemotePlayback) { this.deferred = true; return }
    this.scheduleOpen()
  }
  scheduleOpen() {
    this.deferred = false
    const gen = this.attachGen
    later(net.mseOpenDelay, () => { if (gen === this.attachGen && this.element) this.open() })
  }
  open() {
    this._readyState = 'open'
    this.fire('sourceopen')
    this.recheckStreaming()
  }
  //? the MSE detaching algorithm, from any load of the element: closed, duration NaN, every
  //? SourceBuffer removed (an append in flight ends with 'abort' and 'updateend'), 'sourceclose'
  detach() {
    this.attachGen++
    for (const buffer of this.sourceBuffers.items) buffer.leave()
    if (this.sourceBuffers.length) this.sourceBuffers._replace([], false)
    if (this.activeSourceBuffers.length) this.activeSourceBuffers._replace([], false)
    this._duration = NaN
    this._readyState = 'closed'
    this.deferred = false
    this.element = null
    this.lostElement()
    this.fire('sourceclose')
  }
  lostElement() {}
  //? an append, remove, timestampOffset or changeType on an ended source opens it again
  reopenIfEnded() {
    if (this._readyState !== 'ended') return
    this._readyState = 'open'
    this.fire('sourceopen')
  }
  firstInit(buffer, init) {
    this.activeSourceBuffers._replace([...this.activeSourceBuffers.items, buffer], true)
    if (!Number.isNaN(this._duration)) return
    //? an init segment that gives a duration sets it; one that says 0 (deadwax's, like ffmpeg's
    //? empty_moov) leaves a managed source at net.mmsInitDuration, and makes Chromium's +Infinity
    if (init.movieDuration > 0) this._duration = init.movieDuration / init.movieScale
    else this._duration = this.managed ? net.mmsInitDuration : Infinity
  }
  durationChange(duration) {
    if (Object.is(duration, this._duration)) return
    this._duration = duration
    const element = this.element
    if (element && element.readyState >= 1) { element.duration = duration; element.queue('durationchange') }
    this.recheckStreaming()
  }
  afterAppend() {
    //? appended data past the duration grows it (never an infinite one), firing durationchange
    const end = this.highestEnd()
    const duration = this._duration
    if (end !== null && (Number.isNaN(duration) || (Number.isFinite(duration) && end > duration))) this.durationChange(end)
    this.element?.mseUpdate()
    this.recheckStreaming()
  }
  //? the end-of-stream algorithm: ended, 'sourceended'; with no error the duration is where the data
  //? ends, with one the element's error
  endWith(error) {
    this._readyState = 'ended'
    this.fire('sourceended')
    const element = this.element
    if (!error) {
      this.durationChange(this.highestEnd() ?? 0)
      element?.mseUpdate()
      this.recheckStreaming()
    } else if (element) element.mseError(element.readyState === 0 ? 4 : error === 'network' ? 2 : 3)
  }
  recheckStreaming() {}
}

class FakeManagedMediaSource extends FakeMediaSource {
  constructor() { super(); this._streaming = false }
  static isTypeSupported(type) { return MANAGED_TYPE.test(String(type)) }
  get managed() { return true }
  get streaming() { return this._streaming }
  /** A test's way to say what WebKit decided. */
  setStreaming(value) {
    if (value === this._streaming) return
    this._streaming = value
    this.fire(value ? 'startstreaming' : 'endstreaming')
  }
  lostElement() { this.setStreaming(false) }
  //? WebKit's rule (ManagedMediaSource.cpp:112-154, as 27.0 has it): streaming with no active
  //? SourceBuffer; otherwise on when [t, t + 10 s] isn't buffered, off once [t, t + 30 s] is (capped
  //? at the duration once ended) - t being the renderer's time, the OLD playhead during a seek
  recheckStreaming() {
    const element = this.element
    if (!element || this._readyState === 'closed') return
    if (!this.activeSourceBuffers.length) { this.setStreaming(true); return }
    const t = element.mediaTime(true)
    const cap = this._readyState === 'ended' ? this._duration : Infinity
    const ranges = this.bufferedForElement()
    const covers = (span) => {
      const to = Math.min(t + span, cap)
      return to <= t + 1e-9 || ranges.some(([start, end]) => start <= t + net.gapTolerance && end >= to - 1e-6)
    }
    this.setStreaming(this._streaming ? !covers(net.mmsHigh) : !covers(net.mmsLow))
  }
}

/* --- reading fragmented MP4, as a SourceBuffer's parser does --- */

const readU32 = (b, at) => b[at] * 2 ** 24 + ((b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3])
const readI32 = (b, at) => (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
const readU24 = (b, at) => (b[at] << 16) | (b[at + 1] << 8) | b[at + 2]
const readU64 = (b, at) => readU32(b, at) * 2 ** 32 + readU32(b, at + 4)
const typeAt = (b, at) => String.fromCharCode(b[at], b[at + 1], b[at + 2], b[at + 3])

//? the boxes inside a complete box - a child that runs past its parent is a parse error
function* boxesIn(b, start, end) {
  let at = start
  while (at + 8 <= end) {
    let size = readU32(b, at), header = 8
    const type = typeAt(b, at + 4)
    if (size === 1) { size = readU64(b, at + 8); header = 16 }
    else if (size === 0) size = end - at
    if (size < header || at + size > end) throw new Error(`a malformed ${type} box`)
    yield { type, start: at, body: at + header, end: at + size }
    at += size
  }
}
function childBox(b, parent, type) {
  for (const found of boxesIn(b, parent.body, parent.end)) if (found.type === type) return found
  return null
}
function needBox(b, parent, type) {
  const found = childBox(b, parent, type)
  if (!found) throw new Error(`no ${type} in ${parent.type}`)
  return found
}

//? an initialization segment: the timescales, the FLAC stream's own description from dfLa's
//? STREAMINFO (its MD5 is the song's identity here) and trex's defaults
function parseMoov(b, moov) {
  const mvhd = needBox(b, moov, 'mvhd'), trak = needBox(b, moov, 'trak')
  const mdia = needBox(b, trak, 'mdia'), mdhd = needBox(b, mdia, 'mdhd')
  const stsd = needBox(b, needBox(b, needBox(b, mdia, 'minf'), 'stbl'), 'stsd')
  const movieLong = b[mvhd.body] === 1, mediaLong = b[mdhd.body] === 1
  const [entry] = boxesIn(b, stsd.body + 8, stsd.end)
  if (!entry || entry.type !== 'fLaC') throw new Error(`the sample entry is ${entry?.type ?? 'missing'}, not fLaC`)
  //? an audio sample entry's fields take 28 bytes; its boxes follow
  const dfla = needBox(b, { type: 'fLaC', body: entry.body + 28, end: entry.end }, 'dfLa')
  const block = dfla.body + 4
  if ((b[block] & 0x7f) !== 0 || readU24(b, block + 1) !== 34) throw new Error('dfLa does not begin with STREAMINFO')
  const info = block + 4
  const identity = b.slice(info + 18, info + 34)
  let trex = { duration: 0, size: 0, flags: 0 }
  const mvex = childBox(b, moov, 'mvex')
  const found = mvex && childBox(b, mvex, 'trex')
  if (found) trex = { duration: readU32(b, found.body + 12), size: readU32(b, found.body + 16), flags: readU32(b, found.body + 20) }
  return {
    movieScale: readU32(b, mvhd.body + (movieLong ? 20 : 12)),
    movieDuration: movieLong ? readU64(b, mvhd.body + 24) : readU32(b, mvhd.body + 16),
    timescale: readU32(b, mdhd.body + (mediaLong ? 20 : 12)),
    rate: (b[info + 10] << 12) | (b[info + 11] << 4) | (b[info + 12] >> 4),
    channels: ((b[info + 12] >> 1) & 7) + 1,
    bits: (((b[info + 12] & 1) << 4) | (b[info + 13] >> 4)) + 1,
    samples: (b[info + 13] & 15) * 2 ** 32 + readU32(b, info + 14),
    identity,
    song: identities.get(hexOf(identity)) ?? null,
    trex,
  }
}

//? a moof: its decode time, where its samples start (from the moof, default-base-is-moof), and each
//? sample's duration, size and flags - trun's, else tfhd's defaults, else trex's
function parseMoof(b, moof, trex) {
  const traf = childBox(b, moof, 'traf')
  const tfhd = traf && childBox(b, traf, 'tfhd'), tfdt = traf && childBox(b, traf, 'tfdt'), trun = traf && childBox(b, traf, 'trun')
  if (!tfhd || !tfdt || !trun) throw new Error('a moof without tfhd, tfdt and trun')
  const tfhdFlags = readU24(b, tfhd.body + 1)
  if (tfhdFlags & 0x01) throw new Error('a tfhd base_data_offset, which the fake does not model')
  let at = tfhd.body + 8
  if (tfhdFlags & 0x02) at += 4
  let duration = trex.duration, size = trex.size, flags = trex.flags
  if (tfhdFlags & 0x08) { duration = readU32(b, at); at += 4 }
  if (tfhdFlags & 0x10) { size = readU32(b, at); at += 4 }
  if (tfhdFlags & 0x20) { flags = readU32(b, at); at += 4 }
  const base = b[tfdt.body] === 1 ? readU64(b, tfdt.body + 4) : readU32(b, tfdt.body + 4)
  const runFlags = readU24(b, trun.body + 1)
  const count = readU32(b, trun.body + 4)
  let r = trun.body + 8, dataOffset = 0, first = null
  if (runFlags & 0x01) { dataOffset = readI32(b, r); r += 4 }
  if (runFlags & 0x04) { first = readU32(b, r); r += 4 }
  const samples = []
  for (let i = 0; i < count; i++) {
    const sample = { duration, size, flags: i === 0 && first !== null ? first : flags }
    if (runFlags & 0x100) { sample.duration = readU32(b, r); r += 4 }
    if (runFlags & 0x200) { sample.size = readU32(b, r); r += 4 }
    if (runFlags & 0x400) { sample.flags = readU32(b, r); r += 4 }
    if (runFlags & 0x800) r += 4
    samples.push(sample)
  }
  if (r > trun.end) throw new Error('a trun longer than its box')
  return { base, dataOffset, samples }
}

class FakeSourceBuffer extends FakeTarget {
  constructor(token, source, type) {
    if (token !== INTERNAL) throw new TypeError('Illegal constructor')
    super()
    this.source = source
    this.type = type
    this.removed = false
    this._updating = false
    this.removing = false
    this.op = null
    this._tso = 0
    this._aws = 0
    this._awe = Infinity
    //? coded frames, in order: { start, end, size, id, frame, sync } - `buffered` is made from these
    this.frames = []
    this._ranges = null
    //? the parser: bytes not yet parsed, how many it has consumed since its last reset, a moof
    //? waiting for its mdat, the last initialization segment
    this.input = new Uint8Array(0)
    this.consumed = 0
    this.moof = null
    this.init = null
    this.initReceived = false
    this.needRandomAccess = true
    this.lastAppended = null
    //? for checks: every append as it completed ({ at, bytes, tso, inits, media, error }), every
    //? eviction ({ at, by: 'append' | 'mms', ranges, playhead }), and the last append error's words
    this.log = []
    this.evictions = []
    this.lastError = null
  }
  get updating() { return this._updating }
  get mode() { return 'segments' }
  set mode(value) {
    this.mayChange()
    this.source.reopenIfEnded()
    if (this.parsingMedia()) throw dom('InvalidStateError', 'The mode cannot be set in the middle of a media segment.')
    //? loud, not silently wrong: nothing here places frames the 'sequence' way
    if (value !== 'segments') throw dom('NotSupportedError', `the fake SourceBuffer models 'segments' only, not '${value}'`)
  }
  get timestampOffset() { return this._tso }
  set timestampOffset(value) {
    this.mayChange()
    this.source.reopenIfEnded()
    if (this.parsingMedia()) throw dom('InvalidStateError', 'The timestamp offset cannot be set in the middle of a media segment.')
    this._tso = Number(value)
  }
  get appendWindowStart() { return this._aws }
  set appendWindowStart(value) {
    this.mayChange()
    if (!(value >= 0) || value >= this._awe) throw new TypeError(`The value provided (${value}) is outside the range [0, ${this._awe}).`)
    this._aws = value
  }
  get appendWindowEnd() { return this._awe }
  set appendWindowEnd(value) {
    this.mayChange()
    if (Number.isNaN(value) || value <= this._aws) throw new TypeError(`The value provided (${value}) is less than or equal to the start (${this._aws}).`)
    this._awe = value
  }
  get buffered() {
    if (this.removed) throw dom('InvalidStateError', 'This SourceBuffer has been removed from the parent media source.')
    return new FakeTimeRanges(this.ranges())
  }
  appendBuffer(data) {
    const bytes = bytesFrom(data)
    this.mayChange()
    if (this.source.element?.error) throw dom('InvalidStateError', 'The HTMLMediaElement.error attribute is not null.')
    this.source.reopenIfEnded()
    //? coded frame eviction - which may throw QuotaExceededError from here, synchronously
    this.makeRoom(bytes.length)
    this.input = joinBytes(this.input, bytes)
    this.pendingBytes = bytes.length
    this._updating = true
    this.fire('updatestart')
    this.op = later(net.appendDelay + bytes.length / net.appendRate, () => this.appended())
  }
  abort() {
    if (this.removed) throw dom('InvalidStateError', 'This SourceBuffer has been removed from the parent media source.')
    //? only while the source is open, and never during a remove (SourceBuffer.cpp:344-354)
    if (this.source.readyState !== 'open') throw dom('InvalidStateError', 'The parent media source\'s readyState is not \'open\'.')
    if (this.removing) throw dom('InvalidStateError', 'The SourceBuffer is running a remove operation.')
    if (this._updating) {
      //? the append ends here: nothing of it lands, and its 'abort' and 'updateend' are queued -
      //? they arrive after whatever the caller does next
      if (this.op) this.op.dead = true
      this.op = null
      this._updating = false
      this.fire('abort')
      this.fire('updateend')
    }
    this.resetParser()
    this._aws = 0
    this._awe = Infinity
  }
  remove(start, end) {
    this.mayChange()
    const duration = this.source.duration
    if (Number.isNaN(duration)) throw new TypeError('Failed to execute \'remove\' on \'SourceBuffer\': The MediaSource\'s duration is NaN.')
    if (!(start >= 0) || start > duration) {
      throw new TypeError(`Failed to execute 'remove' on 'SourceBuffer': The start provided (${start}) is outside the range (0, ${duration}).`)
    }
    if (!(end > start)) throw new TypeError(`Failed to execute 'remove' on 'SourceBuffer': The end value provided (${end}) must be greater than the start value provided (${start}).`)
    this.source.reopenIfEnded()
    this._updating = true
    this.removing = true
    this.fire('updatestart')
    this.op = later(net.removeDelay, () => {
      this.op = null
      const before = this.ranges()
      //? the frames that START in [start, end) go (TrackBuffer::removeCodedFrames)
      this.frames = this.frames.filter((f) => !(f.start >= start && f.start < end))
      this._ranges = null
      this.bufferedChanged(before)
      this._updating = false
      this.removing = false
      this.source.element?.mseUpdate()
      this.source.recheckStreaming()
      this.fire('update')
      this.fire('updateend')
    })
  }
  changeType(type) {
    if (!type) throw new TypeError('The type provided is empty.')
    this.mayChange()
    if (!this.source.constructor.isTypeSupported(type)) throw dom('NotSupportedError', `The type provided ('${type}') is unsupported.`)
    this.source.reopenIfEnded()
    this.resetParser()
    this.type = type
  }

  /* --- the fake's own --- */

  /** A test's MMS eviction (memory pressure, or WebKit's own): the frames starting in [start, end) go. */
  evict(start = 0, end = Infinity) {
    const before = this.ranges()
    this.frames = this.frames.filter((f) => !(f.start >= start && f.start < end))
    this._ranges = null
    const removed = subtractRanges(before, this.ranges())
    if (removed.length) this.evictions.push({ at: now, by: 'mms', ranges: removed })
    this.bufferedChanged(before)
    this.source.element?.mseUpdate()
    this.source.recheckStreaming()
  }
  /** The bytes of coded frames held - what the cap counts. */
  heldBytes() { return this.frames.reduce((sum, f) => sum + f.size, 0) }
  mayChange() {
    if (this.removed) throw dom('InvalidStateError', 'This SourceBuffer has been removed from the parent media source.')
    if (this._updating) throw dom('InvalidStateError', 'This SourceBuffer is still processing an \'appendBuffer\' or \'remove\' operation.')
  }
  //? removed from its source: an operation in flight ends with 'abort' and 'updateend'
  leave() {
    if (this._updating) {
      if (this.op) this.op.dead = true
      this.op = null
      this._updating = false
      this.removing = false
      this.fire('abort')
      this.fire('updateend')
    }
    this.removed = true
  }
  ranges() {
    if (!this._ranges || this._rangesFudge !== net.mseFudge) {
      const out = []
      for (const f of this.frames) {
        const last = out[out.length - 1]
        if (last && f.start <= last[1] + net.mseFudge) last[1] = Math.max(last[1], f.end)
        else out.push([f.start, f.end])
      }
      this._ranges = out
      this._rangesFudge = net.mseFudge
    }
    return this._ranges.map(([start, end]) => [start, end])
  }
  //? a ManagedSourceBuffer says every change to `buffered`, with what was added and removed
  bufferedChanged(before) {
    if (!this.source.managed) return
    const after = this.ranges()
    const added = subtractRanges(after, before), removed = subtractRanges(before, after)
    if (!added.length && !removed.length) return
    this.fireEvent(new FakeBufferedChangeEvent('bufferedchange', { addedRanges: new FakeTimeRanges(added), removedRanges: new FakeTimeRanges(removed) }))
  }
  parsingMedia() { return this.moof !== null || (this.input.length >= 8 && ['moof', 'mdat'].includes(typeAt(this.input, 4))) }
  resetParser() {
    this.input = new Uint8Array(0)
    this.consumed = 0
    this.moof = null
    this.needRandomAccess = true
  }
  //? Where a frame goes. WebKit wraps the offset as given, then rounds it to the frame's timescale
  //? when that is within 1 us of it (TrackBuffer::roundTowardsTimeScaleWithRoundingMargin), and adds
  //? exactly - so an offset of N/rate places frames at exactly (N + units)/rate. Chromium truncates
  //? the offset to whole microseconds (web_source_buffer_impl.cc).
  placeTime(units) {
    const scale = this.init.timescale
    if (this.source.managed) {
      const n = Math.round(this._tso * scale)
      if (Math.abs(n / scale - this._tso) < 1e-6) return (n + units) / scale
      return units / scale + this._tso
    }
    return units / scale + Math.trunc(this._tso * 1e6) / 1e6
  }
  //? The coded frame eviction, before an append that would take it past the cap. What may go: frames
  //? ending before the playhead less 3 s (WebKit; the playhead itself for Chromium), then frames past
  //? the range holding the playhead, farthest first (Chromium sparing the last append). WebKit evicts
  //? only when that can make room at all (SourceBufferPrivate.cpp:703-782); Chromium frees what it
  //? can and then refuses. The playhead is element.mediaTime() - the OLD one during a seek in Safari.
  makeRoom(incoming) {
    const managed = this.source.managed
    const cap = net.sbCapBytes ?? (managed ? MANAGED_CAP_BYTES : PLAIN_CAP_BYTES)
    let held = this.heldBytes()
    if (held + incoming <= cap) return
    const element = this.source.element
    const t = element ? element.mediaTime(managed) : 0
    const behindTo = managed ? t - 3 : t
    const current = this.ranges().find(([start, end]) => start <= t + net.gapTolerance && end > t)
    const aheadFrom = current ? current[1] : t
    const last = this.lastAppended
    const spared = (f) => !managed && last && f.start >= last[0] - 1e-9 && f.end <= last[1] + 1e-9
    const behind = this.frames.filter((f) => f.end <= behindTo)
    const ahead = this.frames.filter((f) => f.end > behindTo && f.start >= aheadFrom - 1e-9 && !spared(f)).reverse()
    const bytesOf = (list) => list.reduce((sum, f) => sum + f.size, 0)
    const quota = () => dom('QuotaExceededError', 'The SourceBuffer is full, and cannot free space to append additional buffers.')
    if (managed && held - bytesOf(behind) - bytesOf(ahead) + incoming > cap) throw quota()
    const gone = new Set()
    for (const f of [...behind, ...ahead]) {
      if (held + incoming <= cap) break
      gone.add(f)
      held -= f.size
    }
    if (gone.size) {
      const before = this.ranges()
      this.frames = this.frames.filter((f) => !gone.has(f))
      this._ranges = null
      this.evictions.push({ at: now, by: 'append', ranges: subtractRanges(before, this.ranges()), playhead: t })
      this.bufferedChanged(before)
      element?.mseUpdate()
      this.source.recheckStreaming()
    }
    if (held + incoming > cap) throw quota()
  }
  //? the buffer append algorithm, once the append's time is up: the segment parser loop over
  //? every whole box there is, then 'update' and 'updateend' - or the append error algorithm
  appended() {
    this.op = null
    const before = this.ranges()
    const { inits, media, error } = this.parseInput()
    this.log.push({ at: now, bytes: this.pendingBytes, tso: this._tso, inits: inits.map((init) => init.song), media, error })
    this.bufferedChanged(before)
    if (error) {
      //? 'error', 'updateend', and the source ended with 'decode' - the element's error 3 (4 before metadata)
      this.lastError = error
      this.resetParser()
      this._updating = false
      this.fire('error')
      this.fire('updateend')
      this.source.endWith('decode')
      return
    }
    this._updating = false
    this.source.afterAppend()
    this.fire('update')
    this.fire('updateend')
  }
  parseInput() {
    const b = this.input
    const inits = [], media = []
    let at = 0, error = null
    try {
      while (at + 8 <= b.length) {
        let size = readU32(b, at), header = 8
        const type = typeAt(b, at + 4)
        if (!/^[\x20-\x7e]{4}$/.test(type)) throw new Error(`not an MP4 box at byte ${this.consumed + at}`)
        if (size === 1) { if (at + 16 > b.length) break; size = readU64(b, at + 8); header = 16 }
        if (size === 0) throw new Error(`a ${type} box that runs to the end`)
        if (size < header) throw new Error(`a ${type} box ${size} bytes long`)
        //? a box not all here yet waits for the next append, as a real parser's input does
        if (at + size > b.length) break
        const found = { type, start: at, body: at + header, end: at + size }
        if (type === 'moov') {
          if (this.moof) throw new Error('an initialization segment inside a media segment')
          const init = parseMoov(b, found)
          this.init = init
          this.needRandomAccess = true
          if (!this.initReceived) { this.initReceived = true; this.source.firstInit(this, init) }
          inits.push(init)
        } else if (type === 'moof') {
          if (!this.init) throw new Error('a media segment before any initialization segment')
          if (this.moof) throw new Error('a moof with no mdat after it')
          this.moof = { ...parseMoof(b, found, this.init.trex), start: this.consumed + at }
        } else if (type === 'mdat') media.push(this.mediaSegment(b, found))
        else if (type === 'ftyp' && this.moof) throw new Error('an ftyp inside a media segment')
        //? anything else - sidx, styp, free, emsg - is passed over, as both engines do
        at += size
      }
    } catch (problem) {
      error = problem.message
    }
    this.consumed += at
    this.input = b.slice(at)
    return { inits, media, error }
  }
  //? a moof's samples, out of the mdat after it: each a FLAC frame of the song whose init segment came
  //? last - a frame of another song is a decode error, which is what appending one song's media
  //? after another's init would be (the lab heard a click when it skipped the second init)
  mediaSegment(b, mdat) {
    const moof = this.moof
    if (!moof) throw new Error('an mdat with no moof before it')
    this.moof = null
    let at = moof.start + moof.dataOffset - this.consumed
    const total = moof.samples.reduce((sum, sample) => sum + sample.size, 0)
    if (at < mdat.body || at + total > mdat.end) throw new Error('a trun pointing outside its mdat')
    const init = this.init, identity = init.identity
    let units = moof.base
    const placed = []
    for (const sample of moof.samples) {
      if (sample.size < 22 || b[at] !== 0xff || (b[at + 1] & 0xfe) !== 0xf8) throw new Error('a sample that isn\'t a FLAC frame')
      for (let k = 0; k < 16; k++) {
        if (b[at + 2 + k] !== identity[k]) {
          const whose = identities.get(hexOf(b.subarray(at + 2, at + 18)))
          throw new Error(`a frame of ${whose ? `song ${whose}` : 'another song'} after the initialization segment of ${init.song ? `song ${init.song}` : 'another song'}`)
        }
      }
      placed.push({ start: this.placeTime(units), end: this.placeTime(units + sample.duration), size: sample.size,
                    id: init.song, frame: readU32(b, at + 18), sync: !(sample.flags & 0x00010000) })
      units += sample.duration
      at += sample.size
    }
    this.addFrames(placed)
    return { id: init.song, frames: placed.length, from: placed.length ? placed[0].start : null, to: placed.length ? placed[placed.length - 1].end : null }
  }
  addFrames(placed) {
    const kept = placed.filter((f) => {
      if (f.start < this._aws - 1e-9 || f.end > this._awe + 1e-9) { this.needRandomAccess = true; return false }
      //? after an init segment or a reset, frames wait for a sync sample - FLAC's are all flagged so
      if (this.needRandomAccess) { if (!f.sync) return false; this.needRandomAccess = false }
      return true
    })
    if (!kept.length) return
    const from = kept[0].start, to = kept[kept.length - 1].end
    //? what was there starting inside the new frames' span goes; no audio splicing, so a frame that
    //? starts a few microseconds before them stays (WebKit's 1 ms tolerance)
    this.frames = this.frames.filter((f) => f.start < from - 1e-6 || f.start >= to - 1e-6)
    let i = this.frames.findIndex((f) => f.start >= from)
    if (i < 0) i = this.frames.length
    this.frames.splice(i, 0, ...kept)
    this._ranges = null
    this.lastAppended = [from, to]
  }
}

class FakeManagedSourceBuffer extends FakeSourceBuffer {}

function bytesFrom(data) {
  if (data instanceof ArrayBuffer) return new Uint8Array(data.slice(0))
  if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength))
  throw new TypeError('Failed to execute \'appendBuffer\' on \'SourceBuffer\': The provided value is not of type \'(ArrayBuffer or ArrayBufferView)\'.')
}

//? which of them this page has: 'managed' (WebKit on an iPhone: no MediaSource), 'plain' (Chromium)
//? or null (neither - what every check before the MediaSource section runs on)
const MSE_GLOBALS = ['ManagedMediaSource', 'ManagedSourceBuffer', 'BufferedChangeEvent', 'MediaSource', 'SourceBuffer']
function mseGlobals(mode) {
  for (const name of MSE_GLOBALS) delete globalThis[name]
  if (mode === 'managed') {
    define('ManagedMediaSource', FakeManagedMediaSource)
    define('ManagedSourceBuffer', FakeManagedSourceBuffer)
    define('BufferedChangeEvent', FakeBufferedChangeEvent)
  } else if (mode === 'plain') {
    define('MediaSource', FakeMediaSource)
    define('SourceBuffer', FakeSourceBuffer)
  }
}

const storage = new Map()
define('localStorage', { getItem: (key) => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, String(value)) })
define('document', { createElement: () => new FakeAudio(), body: { appendChild() {} } })
const media = { metadata: null, playbackState: 'none', handlers: {}, setActionHandler(action, handler) { this.handlers[action] = handler }, setPositionState() {} }
const browser = { mediaSession: media }
define('navigator', browser)
//? what the real browsers send - see ui/test/wrap.sim.cjs for the rest
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1'
const ARC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
define('MediaMetadata', class { constructor(fields) { Object.assign(this, fields) } })
define('location', { href: 'http://deadwax.test/player/' })

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { usePlayer } = require(path.join(OUT, 'player/usePlayer.js'))
const { describeSeek, PENDING_MAX_MS } = require(path.join(OUT, 'lib/scrub.js'))
const { describeGaps } = require(path.join(OUT, 'lib/gapless.js'))
const { describeWrap } = require(path.join(OUT, 'lib/streamWrap.js'))

/** A fresh page with no player on it: no elements, nothing queued, the storage empty, and the
 *  MediaSource globals it has - `mse`: 'managed', 'plain' or null. A song's `durations` entry is
 *  its tagged length, or an object of its fields ({ duration, seconds, rate, ... }). */
function freshPage({ gapless = false, durations = {}, userAgent, maxTouchPoints, mse = null } = {}) {
  //? before the player is made: it decides once, for the page, whether FLAC comes in an MP4
  browser.userAgent = userAgent
  browser.maxTouchPoints = maxTouchPoints
  tasks = []
  elements.length = 0
  fetched.length = 0
  abandoned.length = 0
  blobs.clear()
  sources.clear()
  mediaSources.length = 0
  fmp4Requests.length = 0
  storage.clear()
  graceUntil = -1
  Object.assign(net, NET, { sentAsFlac: new Set(), fmp4Answer: {}, headerDelay: {} })
  for (const id of Object.keys(songs)) delete songs[id]
  for (const [id, song] of Object.entries(durations)) songs[id] = typeof song === 'object' ? { ...song } : { duration: song }
  if (gapless) storage.set('deadwax-player-gapless', 'on')
  //? before the player is made too: it decides once, for the page, whether there is a MediaSource
  mseGlobals(mse)
}

/** A fresh page - see freshPage() - and a player, and what its bar hears. */
function page(options = {}) {
  freshPage(options)
  const render = hooks.root(usePlayer)
  const heard = []
  render().onPosition((seconds) => heard.push({ at: now, s: seconds }))
  return {
    get player() { return render() },
    heard,
    lastHeard: () => heard[heard.length - 1].s,
    seekLine: () => describeSeek(render().lastSeek) + describeWrap(render().wrapped, render().track?.id ?? null),
    gapLine: () => describeGaps(render().gaps),
  }
}

const tracks = (ids, suffixes = {}) => ids.map((id) => ({
  id, title: `song ${id}`, artist: 'a', album: 'b', albumId: 'al', coverArt: null, duration: songs[id]?.duration ?? 0,
  contentType: suffixes[id] === 'opus' ? 'audio/ogg' : 'audio/flac', suffix: suffixes[id] ?? 'flac',
}))
const near = (value, target, within = 0.6) => Math.abs(value - target) <= within

/* ===== for checks over the MediaSource fake ===== */

const rangesOf = (timeRanges) => Array.from({ length: timeRanges.length }, (_, i) => [timeRanges.start(i), timeRanges.end(i)])
const r6 = (value) => Math.round(value * 1e6) / 1e6
//? a target's events by name, in the order they came
function watch(target, names) {
  const seen = []
  for (const name of names) target.addEventListener(name, () => seen.push(name))
  return seen
}
//? a song's init segment; its fragments [from, to); and where fragment k starts, exactly as placed
const initOf = (file) => file.bytes.slice(0, file.initEnd)
const fragmentsOf = (file, from, to = from + 1) => file.bytes.slice(file.fragments[from].start, file.fragments[to - 1].end)
const fragmentAt = (file, k) => file.fragments.slice(0, k).reduce((sum, fragment) => sum + fragment.units, 0) / file.song.rate
//? an element (made in a tap) with a MediaSource attached and open, and a SourceBuffer on it
async function openFake(mode) {
  const element = tap(() => document.createElement('audio'))
  const source = mode === 'managed' ? new ManagedMediaSource() : new MediaSource()
  if (mode === 'managed') { element.disableRemotePlayback = true; element.srcObject = source }
  else element.src = URL.createObjectURL(source)
  await run(20)
  const buffer = source.addSourceBuffer(mode === 'managed' ? 'audio/mp4; codecs="fLaC"' : 'audio/mp4; codecs="flac"')
  return { element, source, buffer }
}
async function appendNow(buffer, bytes) {
  buffer.appendBuffer(bytes)
  await run(Math.ceil(net.appendDelay + bytes.length / net.appendRate) + 1)
}
const playNow = (element) => tap(() => element.play()).catch(() => {})
//? what a promise came to within `ms` of the virtual clock
async function outcome(promise, ms = 1_000) {
  const result = { value: undefined, error: undefined }
  promise.then((value) => { result.value = value }, (error) => { result.error = error })
  await run(ms)
  return result
}

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
  {
    //? WebKit's answers are per element and a broadcast reaches only an element whose answer changes:
    //? the standby starts at "none" and is never told otherwise. After a handover it is the one
    //? playing, and when the speaker leaves only the FIRST element (now the standby) says so.
    const p = page({ gapless: true, durations: { 1: 8, 2: 8, 3: 8 } })
    const [e0, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    e0.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'available' })
    e1.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'not-available' })
    check('a speaker there: the button shows, whatever the standby\'s stale "none"', p.player.airplay, true)
    await run(8_500)
    check('handed over: the second element plays', p.player.track.id === '2' && e1.playingNow, true)
    e0.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'not-available' })
    check('the speaker leaves, heard only from the standby: the button goes', p.player.airplay, false)
  }
  {
    //? "next" while a seek is on its way, taken by the standby: the reading closes there too
    const p = page({ gapless: true, durations: { 1: 40, 2: 40 } })
    const [, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(3_500)
    check('the standby holds song 2 in memory', e1.src.startsWith('blob:') && e1.readyState === 4, true)
    net.seekDelay = 2_000
    tap(() => p.player.seek(20))
    await run(300)
    tap(() => p.player.next())
    await run(10_000)
    check('"next" before the seek landed: song 2, handed over to the second element', p.player.track.id === '2' && e1.playingNow && !e1.muted, true)
    check('the readout says the seek was interrupted, not "seeking…"', p.seekLine(), 'Last seek: asked 0:20, interrupted')
    check('the bar hears the second element\'s clock, not the old target', near(p.lastHeard(), e1.currentTime, 0.3) && p.lastHeard() < 11, true)
  }

  /* ======================================================================== */
  console.log('\nFLAC inside an MP4, for Safari only')
  {
    //? Arc on a Mac - Chromium - seeks FLAC exactly: the file as it is, and nothing asked about it
    const p = page({ gapless: true, durations: { 1: 8, 2: 8 }, userAgent: ARC, maxTouchPoints: 0 })
    const [e0, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    check('Chromium: the song asked for as it is', /\/stream\/1\?format=raw$/.test(e0.src), true)
    await run(3_500)
    check('...the next one downloaded as it is, and nothing else asked', fetched, ['2?raw'])
    check('...the readout says nothing about MP4s', p.seekLine(), 'No seek yet')
    check('...and nothing is recorded about one', p.player.wrapped, null)
    await run(5_000)
    check('...handed over from memory as before', /handed over, from memory$/.test(p.gapLine()) && e1.playingNow, true)
  }
  {
    //? an iPhone: every FLAC asked for in an MP4 - the element, the check, and the gapless download
    const p = page({ gapless: true, durations: { 1: 8, 2: 8, 3: 8 }, userAgent: IPHONE, maxTouchPoints: 5 })
    net.cannotPlay = /opus/
    const [e0, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3'], { 3: 'opus' }), 0))
    check('Safari: the song asked for in an MP4', /\/stream\/1\?format=raw&wrap=mp4$/.test(e0.src), true)
    check('...said as asked for until the answer is in', p.seekLine(), 'No seek yet · asked for FLAC in MP4')
    await run(100)
    check('...two bytes of it asked for, to see what came', fetched, ['1?raw+mp4 bytes=0-1'])
    check('...an MP4 came, and the readout says so', p.seekLine(), 'No seek yet · FLAC in MP4')
    await run(3_500)
    check('the next song downloaded in an MP4 too', fetched.slice(1), ['2?raw+mp4'])
    check('...and taken into memory, audio/mp4 like any audio', e1.src.startsWith('blob:') && e1.readyState === 4, true)
    await run(5_000)
    check('handed over from memory', p.player.track.id === '2' && e1.playingNow && /handed over, from memory$/.test(p.gapLine()), true)
    check('...asked what came for the new song, and said', [fetched[2], p.seekLine()], ['2?raw+mp4 bytes=0-1', 'No seek yet · FLAC in MP4'])
    tap(() => p.player.seek(4))
    await run(400)
    check('a seek: the line ends with how the song came', p.seekLine(), 'Last seek: asked 0:04, the player said 0:04 · FLAC in MP4')
    await run(4_000)
    const playing = elements.find((element) => element.playingNow)
    check('an Opus song, transcoded: no MP4 asked for, nothing said',
          [p.player.track.id, /\/stream\/3\?format=mp3$/.test(playing?.src ?? ''), p.player.wrapped], ['3', true, null])
  }
  {
    //? a FLAC deadwax won't repackage comes as FLAC, and the phone can see it did
    const p = page({ durations: { 1: 8 }, userAgent: IPHONE, maxTouchPoints: 5 })
    net.sentAsFlac.add('1')
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(100)
    check('sent as FLAC: the readout says so', p.seekLine(), 'No seek yet · sent as FLAC, not in an MP4')
  }
  {
    //? an answer for the song before, arriving after the change, says nothing about this one
    const p = page({ durations: { 1: 30, 2: 30 }, userAgent: IPHONE, maxTouchPoints: 5 })
    net.fetchDelay = 500
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(100)
    tap(() => p.player.next())
    //? deadwax stops making an MP4 nobody waits for, so a probe left running would keep song 1's going
    check('"next" let go of song 1\'s two bytes', abandoned, ['1?raw+mp4 bytes=0-1'])
    net.sentAsFlac.add('2')
    await run(450)
    check('song 1\'s answer came after "next": song 2 still only asked for', p.seekLine(), 'No seek yet · asked for FLAC in MP4')
    await run(200)
    check('...and then song 2\'s own answer', p.seekLine(), 'No seek yet · sent as FLAC, not in an MP4')
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake itself: opening, and which globals a page has')
  {
    freshPage({ mse: 'managed' })
    check('managed: ManagedMediaSource, ManagedSourceBuffer and BufferedChangeEvent, and no MediaSource',
      [typeof ManagedMediaSource, typeof ManagedSourceBuffer, typeof BufferedChangeEvent, typeof globalThis.MediaSource, typeof globalThis.SourceBuffer],
      ['function', 'function', 'function', 'undefined', 'undefined'])
    check('...isTypeSupported takes "fLaC" and not "flac", as the iPhone did; window.* finds the same',
      [ManagedMediaSource.isTypeSupported('audio/mp4; codecs="fLaC"'), ManagedMediaSource.isTypeSupported('audio/mp4; codecs="flac"'), window.ManagedMediaSource === ManagedMediaSource],
      [true, false, true])
    const element = tap(() => document.createElement('audio'))
    const source = new ManagedMediaSource()
    const seen = watch(source, ['sourceopen', 'sourceclose', 'startstreaming'])
    element.srcObject = source
    await run(5_000)
    check('without disableRemotePlayback it never opens, and says nothing', [source.readyState, seen, element.error], ['closed', [], null])
    element.disableRemotePlayback = true
    await run(50)
    check('...set it, and it opens - streaming, with no SourceBuffer yet', [source.readyState, seen], ['open', ['sourceopen', 'startstreaming']])
  }
  {
    freshPage({ mse: 'plain' })
    check('plain: MediaSource and SourceBuffer, and no ManagedMediaSource',
      [typeof MediaSource, typeof SourceBuffer, typeof globalThis.ManagedMediaSource, typeof globalThis.BufferedChangeEvent], ['function', 'function', 'undefined', 'undefined'])
    check('...isTypeSupported takes both spellings', [MediaSource.isTypeSupported('audio/mp4; codecs="flac"'), MediaSource.isTypeSupported('audio/mp4; codecs="fLaC"')], [true, true])
    const element = tap(() => document.createElement('audio'))
    const source = new MediaSource()
    let refused = null
    try { element.srcObject = source } catch (error) { refused = error.name }
    check('...srcObject refuses a MediaSource, as Chromium does', refused, 'TypeError')
    const seen = watch(source, ['sourceopen'])
    element.src = URL.createObjectURL(source)
    const atOnce = source.readyState
    await run(50)
    check('...a blob: address takes it, and it opens a moment later, with no disableRemotePlayback and no streaming attribute',
      [atOnce, source.readyState, seen, source.streaming], ['closed', 'open', ['sourceopen'], undefined])
    let unsupported = null, closed = null
    try { source.addSourceBuffer('audio/mp4; codecs="opus"') } catch (error) { unsupported = error.name }
    try { new MediaSource().addSourceBuffer('audio/mp4; codecs="flac"') } catch (error) { closed = error.name }
    check('addSourceBuffer: NotSupportedError for a type it can\'t play, InvalidStateError on a source that isn\'t open', [unsupported, closed], ['NotSupportedError', 'InvalidStateError'])
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake: srcObject over src, and every load detaching')
  {
    freshPage({ mse: 'managed', durations: { 1: 8 } })
    const { element, source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    const seen = watch(source, ['sourceopen', 'sourceclose'])
    element.src = '/navidrome/stream/1?format=raw'
    await run(200)
    check('src set while srcObject holds a source: a reload that detaches it and attaches it again - not the URL',
      [seen, element.ms === source, element.currentSrc, element.readyState], [['sourceclose', 'sourceopen'], true, '', 0])
    let dead = null
    try { buffer.appendBuffer(initOf(file)) } catch (error) { dead = error.name }
    check('...its SourceBuffer is gone for good: an append on it is InvalidStateError', [dead, source.sourceBuffers.length], ['InvalidStateError', 0])
    seen.length = 0
    element.load()
    await run(50)
    check('load() detaches it the same way', seen, ['sourceclose', 'sourceopen'])
    element.srcObject = null
    await run(200)
    check('srcObject = null: the src attribute plays now, and the source stays closed', [element.readyState, element.duration, source.readyState], [4, 8, 'closed'])
  }
  {
    freshPage({ mse: 'plain', durations: { 1: 8 } })
    const { element, source, buffer } = await openFake('plain')
    const seen = watch(source, ['sourceopen', 'sourceclose'])
    element.load()
    await run(50)
    let dead = null
    try { buffer.appendBuffer(new Uint8Array(8)) } catch (error) { dead = error.name }
    check('plain: load() on its blob: address detaches it too, its SourceBuffer gone', [seen, dead], [['sourceclose', 'sourceopen'], 'InvalidStateError'])
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake: fragmented MP4 parsed, and frames placed where WebKit puts them')
  {
    //? songs whose lengths aren't whole seconds, joined by timestampOffset = samples / rate
    freshPage({ mse: 'managed', durations: { 1: { duration: 7, seconds: 7.3217 }, 2: { duration: 9, seconds: 9.0001 } } })
    const { element, source, buffer } = await openFake('managed')
    const one = fmp4File('1'), two = fmp4File('2')
    const seen = watch(element, ['durationchange', 'loadedmetadata'])
    await appendNow(buffer, initOf(one))
    check('the first init segment: HAVE_METADATA, durationchange and loadedmetadata, the duration NaN (its mvhd says 0)',
      [element.readyState, seen, Number.isNaN(source.duration), Number.isNaN(element.duration)], [1, ['durationchange', 'loadedmetadata'], true, true])
    await appendNow(buffer, one.bytes.slice(one.headEnd))
    buffer.timestampOffset = one.song.samples / one.song.rate
    await appendNow(buffer, initOf(two))
    await appendNow(buffer, two.bytes.slice(two.headEnd))
    const end = (one.song.samples + two.song.samples) / 44100
    check('7.3217 s then 9.0001 s: one range, to their samples over the rate exactly', rangesOf(buffer.buffered), [[0, end]])
    const join = buffer.frames.findIndex((frame) => frame.id === '2')
    check('...song 2\'s first frame starts exactly where song 1\'s last ends, at song 1\'s samples over the rate',
      [buffer.frames[join].start === buffer.frames[join - 1].end, buffer.frames[join].start === one.song.samples / 44100], [true, true])
    check('...not whole seconds: 322887 samples, the last frame short of 4096',
      [one.song.samples, Math.round((buffer.frames[join - 1].end - buffer.frames[join - 1].start) * 44100)], [322887, 322887 % 4096])
    check('...and the duration grew to the end with the appends', [source.duration, element.duration], [end, end])
    check('what each append held, from its log', buffer.log.map((entry) => [entry.inits, [...new Set(entry.media.map((media) => media.id))]]),
      [[['1'], []], [[], ['1']], [['2'], []], [[], ['2']]])
  }
  {
    //? Chromium truncates the offset to whole microseconds: a join within one, merged all the same
    freshPage({ mse: 'plain', durations: { 1: { duration: 7, seconds: 7.3217 }, 2: { duration: 9, seconds: 9.0001 } } })
    const { buffer } = await openFake('plain')
    const one = fmp4File('1'), two = fmp4File('2')
    await appendNow(buffer, initOf(one))
    await appendNow(buffer, one.bytes.slice(one.headEnd))
    buffer.timestampOffset = one.song.samples / one.song.rate
    await appendNow(buffer, initOf(two))
    await appendNow(buffer, two.bytes.slice(two.headEnd))
    const join = buffer.frames.findIndex((frame) => frame.id === '2')
    check('plain: the same two songs make one range, the join within a microsecond',
      [buffer.buffered.length, Math.abs(buffer.frames[join].start - buffer.frames[join - 1].end) < 1e-6], [1, true])
  }
  {
    freshPage({ mse: 'managed', durations: { 1: 8, 2: 8 } })
    const { element, source, buffer } = await openFake('managed')
    const one = fmp4File('1'), two = fmp4File('2')
    await appendNow(buffer, initOf(one))
    await appendNow(buffer, fragmentsOf(one, 0))
    const seen = watch(buffer, ['updatestart', 'update', 'error', 'updateend'])
    const heard = watch(element, ['error'])
    await appendNow(buffer, fragmentsOf(two, 1))
    check('song 2\'s frames after song 1\'s init segment: the append error - error, then updateend', seen, ['updatestart', 'error', 'updateend'])
    check('...the source ended with decode: the element\'s error 3', [source.readyState, element.error?.code, heard], ['ended', 3, ['error']])
    check('...saying whose frames they were', buffer.lastError, 'a frame of song 2 after the initialization segment of song 1')
    let after = null
    try { buffer.appendBuffer(initOf(two)) } catch (error) { after = error.name }
    check('...and with the element in error, no more appends', after, 'InvalidStateError')
  }
  {
    freshPage({ mse: 'managed', durations: { 1: 8 } })
    const { element, buffer } = await openFake('managed')
    await appendNow(buffer, fragmentsOf(fmp4File('1'), 0))
    check('media before any init segment: an append error before metadata - the element\'s error 4',
      [element.error?.code, buffer.lastError], [4, 'a media segment before any initialization segment'])
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake: the byte cap, and eviction from where Safari 27.0 thinks the playhead is')
  {
    freshPage({ mse: 'managed', durations: { 1: 60 } })
    const { element, source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 13))
    playNow(element)
    await run(9_000)
    element.pause()
    source.duration = 60
    element.currentTime = 30.5
    check('played to 0:09, then a seek to 0:30.5, which isn\'t buffered: on its way, HAVE_METADATA',
      [element.currentTime, element.seeking, element.readyState], [30.5, true, 1])
    const held = buffer.heldBytes()
    const piece = fragmentsOf(file, 29)
    const behind = buffer.frames.filter((frame) => frame.end <= 9 - 3).reduce((sum, frame) => sum + frame.size, 0)
    net.sbCapBytes = held + piece.length - behind - 1000
    let refused = null
    try { buffer.appendBuffer(piece) } catch (error) { refused = error.name }
    check('more room wanted than is behind 0:06 (the OLD playhead less 3 s): QuotaExceededError, from appendBuffer itself', refused, 'QuotaExceededError')
    check('...and nothing evicted - WebKit evicts only when that makes room', [buffer.heldBytes() === held, buffer.updating, buffer.evictions], [true, false, []])
    net.sbCapBytes = held + piece.length - file.fragments[0].payload - file.fragments[1].payload
    buffer.appendBuffer(piece)
    check('room behind 0:06: the oldest two fragments go, and nothing near 0:09', rangesOf(buffer.buffered)[0][0], fragmentAt(file, 2))
    await run(50)
    check('...and the seek lands on the piece', [element.seeking, element.currentTime, rangesOf(buffer.buffered).length], [false, 30.5, 2])
  }
  {
    //? so an append made for a seek before it has landed can evict what the seek waits on: only the
    //? range around the OLD playhead is kept - which is why an engine appends nothing more until 'seeked'
    freshPage({ mse: 'managed', durations: { 1: 60 } })
    const { element, source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 13))
    playNow(element)
    await run(6_000)
    element.pause()
    source.duration = 60
    element.currentTime = 30.5
    const first = fragmentsOf(file, 29), second = fragmentsOf(file, 30, 32)
    net.sbCapBytes = buffer.heldBytes() + first.length
    let secondAppend = null
    buffer.addEventListener('updateend', () => {
      //? an engine appending its next piece the moment the first is in, before 'seeked'
      const behind = buffer.frames.filter((frame) => frame.end <= 6 - 3).reduce((sum, frame) => sum + frame.size, 0)
      net.sbCapBytes = buffer.heldBytes() + second.length - behind - Math.round(file.fragments[29].payload / 2)
      try { buffer.appendBuffer(second); secondAppend = 'appended' } catch (error) { secondAppend = error.name }
    }, { once: true })
    const seeked = watch(element, ['seeked'])
    buffer.appendBuffer(first)
    await run(200)
    check('the next piece appended before the seek landed evicted the target just appended for it: the seek waits on',
      [secondAppend, element.covered(30.5), element.seeking, seeked], ['appended', false, true, []])
    check('...taken from the far end of what lies past the old playhead\'s range', buffer.evictions[0].ranges.at(-1)[1], fragmentAt(file, 30))
  }
  {
    //? Chromium frees what is behind its playhead, then refuses if that wasn't enough - what it freed
    //? staying freed
    freshPage({ mse: 'plain', durations: { 1: 60 } })
    const { element, buffer } = await openFake('plain')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 13))
    playNow(element)
    await run(9_000)
    element.pause()
    const piece = fragmentsOf(file, 13)
    const behind = buffer.frames.filter((frame) => frame.end <= 9).reduce((sum, frame) => sum + frame.size, 0)
    net.sbCapBytes = buffer.heldBytes() + piece.length - behind - 20_000
    let refused = null
    try { buffer.appendBuffer(piece) } catch (error) { refused = error.name }
    check('plain: not room enough behind 0:09 - all of that freed, then QuotaExceededError', [refused, rangesOf(buffer.buffered)[0][0]], ['QuotaExceededError', 96 * 4096 / 44100])
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake: abort(), remove() and endOfStream()')
  {
    freshPage({ mse: 'managed', durations: { 1: 20 } })
    const { source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 3))
    const log = []
    for (const name of ['updatestart', 'update', 'abort', 'error', 'updateend']) buffer.addEventListener(name, () => log.push(`${name}:${buffer.updating}`))
    buffer.appendBuffer(fragmentsOf(file, 3, 6))
    buffer.abort()
    check('abort() during an append ends it at once', buffer.updating, false)
    buffer.timestampOffset = 0
    buffer.appendBuffer(initOf(file))
    check('...so the offset can be set and the next append begun straight away', buffer.updating, true)
    await run(50)
    check('...and the aborted append\'s abort and updateend come after that, while the next append runs', log,
      ['updatestart:true', 'abort:true', 'updateend:true', 'updatestart:true', 'update:false', 'updateend:false'])
    check('...none of the aborted append landed', rangesOf(buffer.buffered), [[0, fragmentAt(file, 3)]])
    buffer.remove(0, 1)
    let removing = null, ended = null
    try { buffer.abort() } catch (error) { removing = error.name }
    await run(20)
    source.endOfStream()
    try { buffer.abort() } catch (error) { ended = error.name }
    check('abort() is InvalidStateError while a remove runs, and once the source has ended', [removing, ended], ['InvalidStateError', 'InvalidStateError'])
  }
  {
    freshPage({ mse: 'managed', durations: { 1: 10 } })
    const { source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    const changes = []
    buffer.addEventListener('bufferedchange', (event) => changes.push([rangesOf(event.addedRanges), rangesOf(event.removedRanges)]))
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 4))
    const frame = (k) => k * 4096 / 44100
    check('bufferedchange on an append, with what it added', changes, [[[[0, frame(44)]], []]])
    buffer.remove(frame(5), frame(10))
    await run(20)
    check('remove(start, end) takes the frames that START in [start, end)', rangesOf(buffer.buffered), [[0, frame(5)], [frame(10), frame(44)]])
    check('...and bufferedchange says what went', changes[1], [[], [[frame(5), frame(10)]]])
    buffer.remove(frame(20) + 1e-6, frame(21) + 1e-6)
    await run(20)
    check('...a frame starting just before the start stays, one starting just before the end goes',
      rangesOf(buffer.buffered), [[0, frame(5)], [frame(10), frame(21)], [frame(22), frame(44)]])
    let late = null, busy = null
    try { buffer.remove(source.duration + 1, source.duration + 2) } catch (error) { late = error.name }
    buffer.remove(0, 0.1)
    try { buffer.remove(1, 2) } catch (error) { busy = error.name }
    await run(20)
    check('remove() past the duration is a TypeError, and during another an InvalidStateError', [late, busy], ['TypeError', 'InvalidStateError'])
    buffer.evict(0, frame(3))
    await run(0)
    check('evict() - a test\'s MMS eviction - takes frames, and bufferedchange says so', [rangesOf(buffer.buffered)[0][0], changes.at(-1)], [frame(3), [[], [[frame(2), frame(3)]]]])
  }
  {
    freshPage({ mse: 'managed', durations: { 1: 10 } })
    const { source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 3))
    const seen = watch(source, ['sourceopen', 'sourceended'])
    source.endOfStream()
    check('endOfStream(): ended, the duration where the data ends', [source.readyState, source.duration], ['ended', fragmentAt(file, 3)])
    buffer.appendBuffer(fragmentsOf(file, 3))
    check('...an append opens it again, at once', source.readyState, 'open')
    await run(20)
    check('...sourceended, then sourceopen again, and the duration grew with the data', [seen, source.duration], [['sourceended', 'sourceopen'], fragmentAt(file, 4)])
    source.endOfStream()
    buffer.timestampOffset = 0
    const byOffset = source.readyState
    source.endOfStream()
    buffer.remove(fragmentAt(file, 3), fragmentAt(file, 4))
    const byRemove = source.readyState
    let updating = null, twice = null
    try { source.endOfStream() } catch (error) { updating = error.name }
    await run(20)
    source.endOfStream()
    try { source.endOfStream() } catch (error) { twice = error.name }
    check('timestampOffset and remove() open it again too; endOfStream() while updating, or not open, is InvalidStateError',
      [byOffset, byRemove, updating, twice], ['open', 'open', 'InvalidStateError', 'InvalidStateError'])
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake: seeks clamped to the duration and seekable')
  {
    freshPage({ mse: 'plain', durations: { 1: 40 } })
    const { element, source, buffer } = await openFake('plain')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    check('plain: the first init segment makes the duration +Infinity', [String(source.duration), String(element.duration), element.readyState], ['Infinity', 'Infinity', 1])
    await appendNow(buffer, fragmentsOf(file, 0, 5))
    check('...so seekable is [0, the buffered end]', rangesOf(element.seekable), [[0, fragmentAt(file, 5)]])
    element.currentTime = 20
    check('a seek past what is seekable lands at its nearest point, the buffered end, and waits there for data',
      [element.currentTime, element.seeking], [fragmentAt(file, 5), true])
  }
  {
    freshPage({ mse: 'managed', durations: { 1: 40 } })
    const { element, source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 5))
    element.currentTime = 20
    check('managed: the duration is the buffered end, and a seek past it is clamped to it', [source.duration, element.currentTime], [fragmentAt(file, 5), fragmentAt(file, 5)])
    await run(0)
    const seen = watch(element, ['durationchange', 'seeking', 'play', 'waiting', 'timeupdate', 'seeked', 'canplay', 'playing'])
    source.duration = 30
    element.currentTime = 20
    playNow(element)
    await run(50)
    check('the duration raised past the data: seekable to it, and a seek there waits', [rangesOf(element.seekable), element.currentTime, element.seeking], [[[0, 30]], 20, true])
    await appendNow(buffer, fragmentsOf(file, 19))
    await run(50)
    check('...until data covers it: it lands exactly, and plays', [element.currentTime, element.seeking, seen],
      [20, false, ['durationchange', 'seeking', 'play', 'waiting', 'timeupdate', 'seeked', 'canplay', 'playing']])
    let busy = null, below = null
    buffer.appendBuffer(fragmentsOf(file, 20))
    try { source.duration = 35 } catch (error) { busy = error.name }
    await run(20)
    try { source.duration = 1 } catch (error) { below = error.name }
    check('the duration can\'t be set while updating, or below what is buffered', [busy, below], ['InvalidStateError', 'InvalidStateError'])
  }

  /* ======================================================================== */
  console.log('\nthe MediaSource fake: playing only through what is buffered')
  {
    freshPage({ mse: 'managed', durations: { 1: 20 } })
    const { element, source, buffer } = await openFake('managed')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 3))
    await appendNow(buffer, fragmentsOf(file, 5, 9))
    const seen = watch(element, ['playing', 'waiting', 'canplay', 'pause', 'ended'])
    playNow(element)
    await run(4_000)
    check('playing up to a hole: it waits there - HAVE_CURRENT_DATA, waiting, no ended, not paused',
      [element.readyState, seen, element.paused, element.stalls.map((stall) => stall.pos)], [2, ['playing', 'waiting'], false, [fragmentAt(file, 3)]])
    seen.length = 0
    await appendNow(buffer, fragmentsOf(file, 3, 5))
    check('...the hole filled: canplay, playing, on from where it stopped', [seen, element.currentTime], [['canplay', 'playing'], fragmentAt(file, 3)])
    await run(7_000)
    check('...to the end of the data, the source still open: waiting again, never ended', [seen.slice(2), element.currentTime, element.ended], [['waiting'], fragmentAt(file, 9), false])
    source.endOfStream()
    await run(10)
    check('endOfStream() there: now it ends - pause, then ended - at the duration',
      [seen.slice(3), element.ended, element.paused, element.currentTime === source.duration], [['pause', 'ended'], true, true, true])
  }
  {
    freshPage({ mse: 'managed', durations: { 1: 40 } })
    const element = tap(() => document.createElement('audio'))
    const source = new ManagedMediaSource()
    const seen = watch(source, ['startstreaming', 'endstreaming'])
    element.disableRemotePlayback = true
    element.srcObject = source
    await run(20)
    const buffer = source.addSourceBuffer('audio/mp4; codecs="fLaC"')
    const file = fmp4File('1')
    await appendNow(buffer, initOf(file))
    await appendNow(buffer, fragmentsOf(file, 0, 30))
    check('streaming: on at sourceopen, off once 30 s are ahead', [source.streaming, seen], [false, ['startstreaming', 'endstreaming']])
    source.duration = 100
    element.currentTime = 60
    check('...a seek to unbuffered time doesn\'t start it: Safari 27.0 judges at the old playhead', [element.seeking, source.streaming], [true, false])
    element.currentTime = 21
    await run(50)
    check('...landed at 0:21, under 10 s ahead: on again', [element.seeking, source.streaming, seen.at(-1)], [false, true, 'startstreaming'])
  }

  /* ======================================================================== */
  console.log('\nthe fake deadwax\'s wrap=fmp4')
  {
    freshPage({ mse: 'managed', durations: { 1: 8 } })
    const file = fmp4File('1'), address = '/deadwax/navidrome/stream/1?format=raw&wrap=fmp4'
    const response = (await outcome(fetch(address, { headers: { Range: 'bytes=0-262143' }, cache: 'no-store' }))).value
    check('a Range: 206, with its Content-Range, length, ETag and type',
      [response.status, response.headers.get('Content-Range'), response.headers.get('content-length'), response.headers.get('ETag'), response.headers.get('Content-Type')],
      [206, `bytes 0-262143/${file.bytes.length}`, '262144', '"fmp4-1-v1"', 'audio/mp4'])
    const bytes = new Uint8Array((await outcome(response.arrayBuffer())).value)
    check('...the file\'s own bytes, and recorded with its range', [Buffer.compare(Buffer.from(bytes), Buffer.from(file.bytes.subarray(0, 262144))), fetched], [0, ['1?raw+fmp4 bytes=0-262143']])
    check('...the file: ftyp, moov, then sidx; 44.1 kHz fragments of 11 frames', [file.bytes.subarray(4, 8), file.bytes.subarray(file.initEnd + 4, file.initEnd + 8), file.fragments[0].frames]
      .map((part) => (typeof part === 'number' ? part : Buffer.from(part).toString())), ['ftyp', 'sidx', 11])
    const current = (await outcome(fetch(address, { headers: { Range: 'bytes=1000-1999', 'If-Range': '"fmp4-1-v1"' } }))).value
    songs['1'].version = 2
    const stale = (await outcome(fetch(address, { headers: { Range: 'bytes=1000-1999', 'If-Range': '"fmp4-1-v1"' } }))).value
    check('If-Range that matches: the range; one that doesn\'t (the file changed): 200, all of it, the new ETag',
      [current.status, stale.status, stale.headers.get('content-length'), stale.headers.get('etag')], [206, 200, String(file.bytes.length), '"fmp4-1-v2"'])
    net.fmp4Answer['1'] = { status: 415, times: 1 }
    const refused = (await outcome(fetch(address, { headers: { Range: 'bytes=0-9' } }))).value
    const refusedBody = (await outcome(refused.json())).value
    const again = (await outcome(fetch(address, { headers: { Range: 'bytes=0-9' } }))).value
    check('a scripted 415, once: JSON with its detail, then the file again',
      [refused.status, refused.headers.get('content-type'), typeof refusedBody.detail, again.status], [415, 'application/json', 'string', 206])
    net.fmp4Answer['*'] = { status: 503, scope: 'server' }
    const down = (await outcome(fetch(address))).value
    const downBody = (await outcome(down.json())).value
    check('a scripted 503 for every song, scope server: Retry-After 30, the scope in the body', [down.status, down.headers.get('Retry-After'), downBody.scope], [503, '30', 'server'])
    net.fmp4Answer = {}
    net.bytesPerChunk = 65536
    const slow = (await outcome(fetch(address, { headers: { Range: 'bytes=0-262143' } }), 50)).value
    const sent = now
    const arrivals = []
    const reader = slow.body.getReader()
    ;(async () => { for (;;) { const { done, value } = await reader.read(); if (done) return; arrivals.push([now - sent, value.length]) } })()
    await run(300)
    check('a body read in chunks of net.bytesPerChunk, one every fetchDelay', arrivals, [[50, 65536], [100, 65536], [150, 65536], [200, 65536]])
    net.bodyStallAt = 100_000
    abandoned.length = 0
    const controller = new AbortController()
    const stalling = (await outcome(fetch(address, { headers: { Range: 'bytes=0-262143' }, signal: controller.signal }), 50)).value
    const got = []
    let failure = null
    const reader2 = stalling.body.getReader()
    ;(async () => { try { for (;;) { const { done, value } = await reader2.read(); if (done) return; got.push(value.length) } } catch (error) { failure = error.name } })()
    await run(5_000)
    check('net.bodyStallAt: the body stops arriving there, and the read just waits', [got, failure], [[65536, 34464], null])
    controller.abort()
    await run(10)
    check('...until the page lets go: AbortError, and the request recorded as let go of', [failure, abandoned], ['AbortError', ['1?raw+fmp4 bytes=0-262143']])
    net.bodyStallAt = null
    net.headerDelay['1'] = 5_000
    const early = new AbortController()
    let state = 'waiting'
    fetch(address, { signal: early.signal }).then(() => { state = 'answered' }, (error) => { state = error.name })
    await run(1_000)
    const before = state
    early.abort()
    await run(10)
    net.headerDelay = {}
    net.fmp4Answer['1'] = { status: 0 }
    const broken = await outcome(fetch(address))
    check('a slow make (net.headerDelay): no answer after 1 s, and let go of, AbortError; a scripted status 0: a TypeError',
      [before, state, broken.error?.name], ['waiting', 'AbortError', 'TypeError'])
  }

  /* ======================================================================== */
  //? The one-stream engine, driven through the REAL usePlayer: FLAC songs with the gapless switch on
  //? play as one MediaSource stream on one element (player/streamSource.ts). Every page here is an
  //? iPhone (ManagedMediaSource) unless it says Chromium (plain MediaSource).
  const scrobbles = []
  const positions = []
  const realFetch = globalThis.fetch
  define('fetch', (address, init) => {
    const match = /\/scrobble\/([^?]+)\?submission=(true|false)/.exec(String(address))
    if (match) scrobbles.push(`${match[1]}:${match[2] === 'true' ? 'played' : 'now'}`)
    return realFetch(address, init)
  })
  media.setPositionState = (state) => positions.push(state)
  const streamPage = (options = {}) => {
    scrobbles.length = 0
    positions.length = 0
    media.metadata = null
    return page({ gapless: true, mse: 'managed', userAgent: IPHONE, maxTouchPoints: 5, ...options })
  }
  const heads = (id) => fmp4Requests.filter((r) => r.id === id && /bytes=0-262143/.test(r.range ?? '')).length
  const starts = (ids) => ids.map((id) => mseSong(id)).reduce((acc, song) => [...acc, acc[acc.length - 1] + song.seconds], [0])
  const streamOf = (element) => element.ms

  console.log('\none stream: an album start to end, the songs joined on the timeline')
  {
    const p = streamPage({ durations: { 1: 6, 2: 5, 3: 7 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    check('the tap put a ManagedMediaSource on the element playing, remote playback off first', [mediaSources.length, e0.srcObject === mediaSources[0], e0.disableRemotePlayback], [1, true, true])
    await run(600)
    check('song 1 playing out of the stream', [p.player.track.id, e0.playingNow, p.player.playing], ['1', true, true])
    check('asked for as fragmented MP4, the head and its first fragments in one ask', heads('1') >= 1 && fmp4Requests.every((r) => r.format === 'raw'), true)
    check('the next song\'s head asked for early, in its own ask', heads('2'), 1)
    check('the length shown is the song\'s own, from its samples - not the tags\' whole seconds', near(p.player.duration, mseSong('1').seconds, 1e-9), true)
    check('the readout says the song plays in the stream', p.seekLine(), 'No seek yet · in one stream')
    const at = starts(['1', '2', '3'])
    await run((at[1] - e0.currentTime) * 1000 + 600)
    check('song 1 ran into song 2: the queue followed the clock', p.player.track.id, '2')
    check('no stall at the join', e0.stalls.length, 0)
    check('the lock screen shows song 2', media.metadata?.title, 'song 2')
    check('the bar hears song 2\'s own position', p.lastHeard() >= 0 && p.lastHeard() < 1.2, true)
    check('the lock screen\'s position is song 2\'s, not the stream\'s', positions.length > 0 && positions[positions.length - 1].position < 1.2 && near(positions[positions.length - 1].duration, mseSong('2').seconds, 1e-9), true)
    check('"now playing" for song 2 when it began', scrobbles.includes('2:now'), true)
    check('the join read: in one stream, 0 ms', p.gapLine(), 'Last song change 0 ms, in one stream')
    check('buffered is one range across the join', rangesOf(e0.buffered).length, 1)
    await run((at[3] - e0.currentTime) * 1000 + 1500)
    check('song 3 played to its end, and the queue stopped there', [p.player.track.id, p.player.playing, e0.ended], ['3', false, true])
    check('every join played through', [e0.stalls.length, p.gapLine()], [0, 'Last song change 0 ms, in one stream · before: 0 ms'])
    check('songs this short (30 s or less) never count as plays - Last.fm\'s rule, stream or not', scrobbles.filter((s) => s.endsWith(':played')), [])
    check('still one MediaSource for the whole album', mediaSources.length, 1)
  }

  console.log('\none stream: next, previous and seeks inside it')
  {
    const p = streamPage({ durations: { 1: 8, 2: 8, 3: 8 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    await run(1_500)
    tap(() => p.player.next())
    check('"next" to a song already placed: song 2 at once, no new source', [p.player.track.id, mediaSources.length], ['2', 1])
    await run(600)
    const at = starts(['1', '2', '3'])
    check('the element went to song 2\'s start and plays it', near(e0.currentTime - at[1], 0.35, 0.4) && e0.playingNow, true)
    tap(() => p.player.previous())
    check('"previous" early in song 2: back to song 1, in the stream', [p.player.track.id, mediaSources.length], ['1', 1])
    await run(600)
    tap(() => p.player.seek(4))
    await run(600)
    check('a seek in song 1 lands where asked', near(e0.currentTime, 4.3, 0.4), true)
    check('...and the readout says so, in the stream', p.seekLine(), 'Last seek: asked 0:04, the player said 0:04 · in one stream')
    //? what MMS threw away behind the playhead is fetched again when a seek needs it
    streamOf(e0).sourceBuffers[0].evict(0, e0.currentTime - 1)
    const before = fmp4Requests.length
    tap(() => p.player.seek(1))
    await run(800)
    check('a seek back into data the browser evicted: fetched again, and landed', fmp4Requests.length > before && near(e0.currentTime, 1.4, 0.5) && e0.playingNow, true)
    tap(() => { p.player.next(); p.player.next() })
    await run(1_000)
    check('"next" twice quickly: song 3, the stream rebuilt for it when it wasn\'t placed yet', p.player.track.id === '3' && e0.playingNow, true)
  }

  console.log('\none stream: a song that can\'t join ends the run, and the queue carries on the old way')
  {
    //? an Opus song is transcoded: no FLAC in it to stream. The run ends before it, it plays on the
    //? second element from the standby, and the FLAC after it goes the URL way - not a tap, so no stream
    const p = streamPage({ durations: { 1: 5, 2: 5, 3: 5, 4: 5 } })
    net.cannotPlay = /opus/
    const [e0, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3', '4'], { 3: 'opus' }), 0))
    const at = starts(['1', '2'])
    await run((at[2] - 1.5) * 1000)
    check('song 2 playing in the stream, the Opus song after it got ready on the standby by address', p.player.track.id === '2' && /\/stream\/3\?format=mp3$/.test(e1.src), true)
    await run(2_500)
    check('at the run\'s end: handed over to the standby, song 3 transcoded', [p.player.track.id, e1.playingNow], ['3', true])
    check('the stream element let go of its MediaSource', e0.srcObject, null)
    check('the change read as a handover', /^Last song change \d+ ms, handed over, streamed/.test(p.gapLine()), true)
    await run(6_500)
    check('song 4, a FLAC after it: the URL way, as an MP4 (Safari), not a new stream', p.player.track.id === '4' && mediaSources.length === 1, true)
  }
  {
    //? deadwax won't repackage song 2: 415. The run ends at song 1 and song 2 is never streamed again -
    //? nor asked for as an MP4, which deadwax would refuse the same way
    const p = streamPage({ durations: { 1: 5, 2: 5, 3: 5 } })
    net.fmp4Answer['2'] = { status: 415 }
    const [e0, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    await run((mseSong('1').seconds + 1) * 1000)
    check('song 2 refused for the stream: got ready on the standby as the file as it is, never as an MP4', fetched.includes('2?raw') && !fetched.some((f) => f.startsWith('2?raw+mp4')), true)
    check('...and played after song 1, handed over', p.player.track.id === '2' && e1.playingNow, true)
    check('song 1 played to its end in the stream first', e0.srcObject === null && e0.stalls.length === 0, true)
  }
  {
    //? refused at the very start: the song the listener tapped plays the URL way straight away
    const p = streamPage({ durations: { 1: 5, 2: 5 } })
    net.fmp4Answer['1'] = { status: 415 }
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(800)
    check('the first song refused: played the URL way, as it is', [p.player.track.id, e0.srcObject, /\/stream\/1\?format=raw$/.test(e0.getAttribute('src') ?? ''), e0.playingNow], ['1', null, true, true])
  }
  {
    //? song 2 at 48 kHz after song 1 at 44.1: a format change ends the run (not a refusal)
    const p = streamPage({ durations: { 1: 5, 2: { duration: 5, rate: 48000 } } })
    const [, e1] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run((mseSong('1').seconds + 1) * 1000)
    check('a format change ends the run: song 2 handed over the old way', p.player.track.id === '2' && e1.playingNow, true)
  }

  {
    //? a hi-res song: only its format keeps it out of the stream - Safari still gets it in an MP4, whose
    //? seeks land; only a song deadwax REFUSES is asked for as the plain file
    const p = streamPage({ durations: { 1: { duration: 5, rate: 96000 }, 2: 5 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    check('a 96 kHz first song: the URL way, in an MP4 for Safari', [e0.srcObject, /\/stream\/1\?format=raw&wrap=mp4$/.test(e0.getAttribute('src') ?? ''), e0.playingNow], [null, true, true])
  }

  console.log('\none stream: failures leave it for the song playing, at its position')
  {
    const p = streamPage({ durations: { 1: 60, 2: 5 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    //? from now on every ask for song 1 fails at the network: the stream plays the ~30 s it has,
    //? retries, and when the playhead runs out, leaves the stream for song 1 at where it had got to
    net.fmp4Answer['1'] = { status: 0, times: 999 }
    await run(50_000)
    check('left the stream: song 1 the URL way (as it is), carrying on from where the stream ran out', p.player.track.id === '1' && e0.srcObject === null && /\/stream\/1\?format=raw$/.test(e0.getAttribute('src') ?? '') && e0.currentTime > 25 && e0.playingNow, true)
  }
  {
    const p = streamPage({ durations: { 1: 8, 2: 8 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(2_000)
    const position = e0.currentTime
    e0.fail(3)
    await run(600)
    check('a decode error: the song leaves the stream, the URL way, from its position', e0.srcObject === null && /\/stream\/1\?format=raw$/.test(e0.getAttribute('src') ?? '') && e0.currentTime >= position - 0.3, true)
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(600)
    check('...and it is never streamed again this page', e0.srcObject === null && mediaSources.length === 1, true)
  }

  console.log('\none stream: AirPlay, the switch, and play after the end')
  {
    const p = streamPage({ durations: { 1: 8, 2: 8 } })
    const [e0] = elements
    e0.dispatch('webkitplaybacktargetavailabilitychanged', { availability: 'available' })
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    check('an AirPlay speaker there: the button stays while the stream plays (its remote playback off)', p.player.airplay, true)
    let picked = false
    e0.webkitShowPlaybackTargetPicker = () => { picked = true }
    const position = e0.currentTime
    tap(() => p.player.showAirPlay())
    await run(600)
    check('the AirPlay button: the song leaves the stream at its position, then the picker', [e0.srcObject, picked, e0.disableRemotePlayback], [null, true, false])
    check('...playing on from there', e0.playingNow && e0.currentTime >= position - 0.3, true)
  }
  {
    const p = streamPage({ durations: { 1: 8, 2: 8 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    const position = e0.currentTime
    tap(() => p.player.setGapless(false))
    await run(600)
    check('the switch off: the song leaves the stream where it was', e0.srcObject === null && e0.playingNow && e0.currentTime >= position - 0.3, true)
  }
  {
    const p = streamPage({ durations: { 1: 4, 2: 4 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run((starts(['1', '2'])[2] + 1.5) * 1000)
    check('the queue played out', [p.player.track.id, p.player.playing, e0.ended], ['2', false, true])
    streamOf(e0).sourceBuffers[0].evict(0, Infinity)
    tap(() => p.player.toggle())
    await run(1_500)
    check('play after the end: song 2 again from its start - not the run\'s first song - fetched again', p.player.track.id === '2' && e0.playingNow && near(e0.currentTime - starts(['1'])[1], 1.2, 0.8), true)
    await run(5_000)
    check('...and it ends again', [p.player.playing, e0.ended], [false, true])
  }

  console.log('\none stream: a seek before the song\'s head is in, and a full buffer')
  {
    const p = streamPage({ durations: { 1: 10, 2: 5 } })
    net.headerDelay['1'] = 1_500
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(100)
    tap(() => p.player.seek(3))
    check('asked at once, on its way', p.seekLine(), 'Last seek: asked 0:03, seeking… · in one stream')
    //? (the slow make slows every ask for the song, the piece after the head too)
    await run(4_000)
    check('applied once the head was in: song 1 from 0:03', e0.playingNow && near(e0.currentTime, 3.8, 0.8), true)
    check('...and the readout says it landed', p.seekLine(), 'Last seek: asked 0:03, the player said 0:03 · in one stream')
  }
  {
    //? a SourceBuffer holding only ~5 s: the stream clears what is behind and waits, and never loses a piece
    const p = streamPage({ durations: { 1: 9, 2: 9 } })
    net.sbCapBytes = 600_000
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run((starts(['1', '2'])[2] + 2) * 1000)
    check('a small buffer: the whole album played, to its end', [p.player.track.id, e0.ended], ['2', true])
    check('...joined without a stall', e0.stalls.length, 0)
  }
  {
    //? smaller still (~2 s): a piece is split, and its first half split again - each half kept, in order
    const p = streamPage({ durations: { 1: 20 } })
    net.sbCapBytes = 250_000
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run((starts(['1'])[1] + 3) * 1000)
    const asked = fmp4Requests.filter((r) => r.id === '1' && r.range !== 'bytes=0-262143').map((r) => /bytes=(\d+)-(\d+)/.exec(r.range).slice(1).map(Number)).sort((a, b) => a[0] - b[0])
    check('a tiny buffer: the song played to its end, and no byte of it was asked for twice', [e0.ended, asked.every(([a], k) => k === 0 || a > asked[k - 1][1])], [true, true])
  }

  console.log('\none stream in Chromium: plain MediaSource')
  {
    const p = streamPage({ mse: 'plain', userAgent: ARC, maxTouchPoints: 0, durations: { 1: 5, 2: 6 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(600)
    check('attached by a blob: address (Chromium takes no MediaSource as srcObject)', [e0.srcObject, (e0.getAttribute('src') ?? '').startsWith('blob:'), e0.playingNow], [null, true, true])
    await run((starts(['1', '2'])[2] + 1.5) * 1000)
    check('the album joined and ended', [p.player.track.id, e0.stalls.length, e0.ended], ['2', 0, true])
    check('the join read in one stream', /in one stream/.test(p.gapLine()), true)
  }
  {
    //? no MediaSource at all: the switch is today's two elements, untouched
    const p = page({ gapless: true, durations: { 1: 5, 2: 5 } })
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(600)
    check('without MediaSource: the two-element way, no stream', [mediaSources.length, elements[0].srcObject, elements[0].playingNow], [0, null, true])
  }
  /* ----- after the review: what a later song's trouble, a seek, a pause and the cache must not do ----- */
  //? streamFailed() says why it left a stream on console.warn: kept here, so a check can ask whether
  //? a stream was given up at all
  const warns = []
  const realWarn = console.warn
  console.warn = (...args) => { warns.push(args.join(' ')) }
  const leftStream = () => warns.filter((line) => /left the gapless stream/.test(line))
  //? the element the music comes out of: unmuted, holding something
  const playingElement = () => elements.find((e) => !e.muted && (e.srcObject || e.getAttribute('src')))
  const lastEnd = (element) => { const ranges = rangesOf(element.buffered); return ranges.length ? ranges[ranges.length - 1][1] : 0 }

  for (const at of [212_000, 222_000]) {
    for (const [label, trigger, refused] of [
      ['a piece of song 2 answered 404', () => { net.fmp4Answer['2'] = { status: 404, times: 999 } }, true],
      ['a piece of song 2 answered 401', () => { net.fmp4Answer['2'] = { status: 401, times: 999 } }, false],
      ['song 2 changed on the server (If-Range answered 200)', () => { songs['2'].version = 2 }, false],
      //? same ETag, other bytes: what the SourceBuffer is given for song 2 isn't what its head described
      ["song 2's bytes don't parse (an append error)", () => { songs['2'].samples = Math.round(250.3 * 44100) }, true],
    ]) {
      console.log(`\none stream: ${label}, with song 1 of 4 minutes at ${at / 1000} s`)
      const p = streamPage({ durations: { 1: 240, 2: 240, 3: 240 } })
      const [e0] = elements
      tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
      await run(at)
      warns.length = 0
      trigger()
      await run(5_000)
      const decode = /parse/.test(label)
      check(`${label}: 5 s later song 1 is still the song playing, from where it was`, [p.player.track.id, near(p.player.position(), at / 1000 + 5, 1), playingElement().playingNow], ['1', true, true])
      if (decode) {
        //? the bad bytes are met when song 2's pieces are fetched, 30 s or less before its turn
        await run((mseSong('1').seconds - 2 - p.player.position()) * 1000)
        check('...the stream given up by the browser once it met them: song 1 goes on the URL way, as it is, from where it was',
          [p.player.track.id, e0.srcObject === null, /\/stream\/1\?format=raw$/.test(e0.getAttribute('src') ?? ''), e0.playingNow], ['1', true, true, true])
      } else {
        check('...still in the stream, which now ends at song 1\'s end: nothing of song 2 left in it to play under song 1\'s title',
          [e0.srcObject === mediaSources[mediaSources.length - 1], lastEnd(e0) <= mseSong('1').seconds + 1e-6], [true, true])
      }
      const at2 = mseSong('1').seconds
      await run((at2 - p.player.position()) * 1000 + 3_000)
      check('...and at song 1\'s end song 2 plays, the URL way', [p.player.track.id, playingElement().playingNow, playingElement().srcObject === null], ['2', true, true])
      check(`...song 2 ${refused ? 'never streams again (asked for only as the file as it is)' : 'is not taken for refused'}`,
        fetched.filter((f) => /^2\?/.test(f) && !/\+fmp4/.test(f)).every((f) => !/mp4/.test(f)), refused)
    }
  }

  console.log('\none stream: a run cut short gets the song after its new end ready')
  {
    const p = streamPage({ durations: { 1: 240, 2: 240, 3: 30 } })
    net.cannotPlay = /opus/
    tap(() => p.player.playTracks(tracks(['1', '2', '3'], { 3: 'opus' }), 0))
    await run(222_000)
    net.fmp4Answer['2'] = { status: 404, times: 999 }
    await run((mseSong('1').seconds - p.player.position()) * 1000 + 2_000)
    check('song 2 was refused after the run\'s end was known (at song 2): it is got ready all the same, and handed over to', [p.player.track.id, /handed over/.test(p.gapLine())], ['2', true])
  }

  console.log('\none stream: song 2\'s bytes fail in the SourceBuffer early on - song 1 is not blamed')
  {
    const p = streamPage({ durations: { 1: 6, 2: 6, 3: 6 } })
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    //? between song 2's head and its first piece past it: the head is the old file, the pieces the new
    while (!fmp4Requests.some((r) => r.id === '2' && r.status !== null)) await run(5)
    songs['2'].samples = Math.round(6.7 * 44100)
    const mark = fetched.length
    //? song 1 goes on the URL way, then song 2 has its turn
    await run(8_000)
    const asked2 = fetched.slice(mark).filter((f) => /^2\?/.test(f) && !/\+fmp4/.test(f))
    check('song 2 is asked for as the file as it is, never as an MP4 again', asked2.length > 0 && asked2.every((f) => !/mp4/.test(f)), true)
    const before = mediaSources.length
    tap(() => p.player.playTracks(tracks(['1', '3']), 0))
    await run(600)
    check('a tap on song 1 starts a stream again: it was never refused', [mediaSources.length - before, elements.some((e) => e.srcObject === mediaSources[mediaSources.length - 1] && e.playingNow)], [1, true])
  }

  console.log('\none stream: every piece is pinned to the version its head came from')
  {
    const p = streamPage({ durations: { 1: 20, 2: 20 } })
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(3_000)
    const pieces = fmp4Requests.filter((r) => !/bytes=0-262143/.test(r.range ?? ''))
    check('each piece asked with If-Range = its song\'s head ETag', pieces.length > 0 && pieces.every((r) => r.ifRange === `"fmp4-${r.id}-v1"`), true)
  }

  console.log('\none stream: a seek to the very end of the last song placed, with a minute left')
  for (const [name, options] of [['iPhone', {}], ['Arc', { mse: 'plain', userAgent: ARC, maxTouchPoints: 0 }]]) {
    const p = streamPage({ ...options, durations: { 1: 120, 2: 30 } })
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(10_500)
    warns.length = 0
    check(`${name}: song 2's head not asked for yet - song 1 is the last placed`, heads('2'), 0)
    tap(() => p.player.seek(p.player.duration))
    await run(4_000)
    check(`${name}: the seek landed at the end and song 2 plays on, in the same stream`, [p.player.track.id, playingElement().playingNow, mediaSources.length, leftStream()], ['2', true, 1, []])
  }
  {
    const p = streamPage({ durations: { 1: 60 } })
    tap(() => p.player.playTracks(tracks(['1']), 0))
    await run(10_500)
    warns.length = 0
    tap(() => p.player.seek(p.player.duration))
    await run(3_000)
    check('a lone song: a seek to its end ends it, no stall', [elements[0].ended, leftStream()], [true, []])
  }

  console.log('\none stream: resumed after a pause, it is not taken for stuck')
  for (const before of [10, 240]) {
    const p = streamPage({ durations: { 1: 120, 2: 60 } })
    const [e0] = elements
    const t0 = now
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(8_000)
    tap(() => p.player.toggle())
    await run(40_000)
    //? play pressed just before one of the stream's 5 s watches
    await run(t0 + 5000 * (Math.ceil((now - t0) / 5000) + 1) - before - now)
    warns.length = 0
    tap(() => p.player.toggle())
    await run(2_000)
    check(`play ${before} ms before a watch: still the stream, playing`, [e0.srcObject === mediaSources[mediaSources.length - 1], e0.playingNow, leftStream()], [true, true, []])
  }

  console.log('\none stream: a first song deadwax is slow to make')
  {
    const p = streamPage({ durations: { 1: 30, 2: 5 } })
    net.headerDelay['1'] = 10_000
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(100)
    delete net.headerDelay['1']
    await run(11_000)
    check('10 s for its head: the stream waits for it, and plays', [e0.srcObject === mediaSources[0], e0.playingNow], [true, true])
  }
  {
    const p = streamPage({ durations: { 1: 60, 2: 5 } })
    net.headerDelay['1'] = 60_000
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(100)
    delete net.headerDelay['1']
    await run(32_000)
    check('a minute: after about 25 s of nothing it plays the URL way, as it is', [e0.srcObject === null, /\/stream\/1\?format=raw$/.test(e0.getAttribute('src') ?? ''), e0.playingNow], [true, true, true])
  }

  console.log('\none stream: the next song\'s head is asked for about a minute before its turn, not a song early')
  {
    const p = streamPage({ durations: { 1: 200, 2: 200, 3: 200 } })
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(60_000)
    const early = heads('2')
    await run(90_000)
    const late = heads('2')
    const asked = fmp4Requests.find((r) => r.id === '2')
    check('not at 60 s of 200, and by 150 s', [early, late], [0, 1])
    check('...with the feeding within 30 s of song 1\'s end: under 70 s before the join', asked && (mseSong('1').seconds * 1000 - (asked.at - fmp4Requests.find((r) => r.id === '1').at)) < 70_000, true)
  }

  console.log('\none stream: moving inside it')
  {
    const p = streamPage({ durations: { 1: 8, 2: 12, 3: 8 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    check('the element playing is not muted', e0.muted, false)
    await run(1_000)
    tap(() => p.player.next())
    await run(800)
    check('"next" in the stream: the lock screen shows song 2, "now playing" went for it', [media.metadata?.title, scrobbles.includes('2:now')], ['song 2', true])
    check('...and the lock screen\'s position is song 2\'s', near(positions[positions.length - 1].duration, mseSong('2').seconds, 1e-9) && positions[positions.length - 1].position < 1.5, true)
    tap(() => p.player.seek(5))
    await run(600)
    const at = starts(['1', '2', '3'])
    check('a seek in song 2 lands 5 s into song 2, the readout song-relative', [p.player.track.id, near(e0.currentTime - at[1], 5.3, 0.4), p.seekLine()], ['2', true, 'Last seek: asked 0:05, the player said 0:05 · in one stream'])
  }
  {
    const p = streamPage({ durations: { 1: 8, 2: 8 } })
    net.cannotPlay = /opus/
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2'], { 1: 'opus' }), 1))
    await run(1_000)
    tap(() => p.player.previous())
    await run(1_000)
    check('"previous" to an Opus song before the stream: that element lets the stream go and plays it by URL', [p.player.track.id, e0.srcObject === null, /\/stream\/1\?format=mp3$/.test(e0.getAttribute('src') ?? ''), e0.playingNow], ['1', true, true, true])
  }
  for (const tapAt of [60_000, 190_000]) {
    const p = streamPage({ durations: { 1: 200, 2: 200, 3: 30 } })
    net.cannotPlay = /opus/
    tap(() => p.player.playTracks(tracks(['1', '2', '3'], { 3: 'opus' }), 0))
    await run(tapAt)
    tap(() => p.player.next())
    await run(10_000)
    const standby = elements.find((e) => e !== playingElement())
    check(`"next" into the run's last song at ${tapAt / 1000} s: the Opus song after it is got ready`, /\/stream\/3\?format=mp3$/.test(standby?.getAttribute('src') ?? ''), true)
  }

  console.log('\none stream: when the run ends early, the song after it waits its turn for the connection')
  {
    const p = streamPage({ durations: { 1: 20, 2: 20 } })
    net.cannotPlay = /opus/
    tap(() => p.player.playTracks(tracks(['1', '2'], { 2: 'opus' }), 0))
    await run(1_500)
    check('nothing of song 2 in the first 1.5 s: not downloaded, no element given it', [fetched.filter((f) => /^2\?/.test(f)), elements.some((e) => /\/stream\/2\?/.test(e.getAttribute('src') ?? ''))], [[], false])
    await run(4_000)
    check('...then song 2 is got ready', elements.some((e) => /\/stream\/2\?format=mp3$/.test(e.getAttribute('src') ?? '')), true)
  }

  console.log('\none stream: a last song too short for any update to see')
  {
    const p = streamPage({ durations: { 1: 5, 2: 0.1, 3: 5 } })
    net.cannotPlay = /opus/
    tap(() => p.player.playTracks(tracks(['1', '2', '3'], { 3: 'opus' }), 0))
    await run(8_000)
    check('the run ended on it, and the song after it played - it was not played again the URL way', [p.player.track.id, fetched.some((f) => /^2\?(?!.*fmp4)/.test(f))], ['3', false])
  }

  console.log('\none stream: only a tap starts one')
  {
    const p = streamPage({ durations: { 2: 6 } })
    net.cannotPlay = /opus/
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2'], { 1: 'opus' }), 0))
    await run(6_000)
    check('a song change by itself goes the URL way, no MediaSource', [p.player.track.id, mediaSources.length, e0.playingNow], ['2', 0, true])
  }
  {
    const p = streamPage({ durations: { 1: 8, 2: 8 } })
    const [e0] = elements
    e0.webkitCurrentPlaybackTargetIsWireless = true
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(600)
    check('a tap while the sound goes to AirPlay starts none, and remote playback stays on', [mediaSources.length, e0.disableRemotePlayback, e0.playingNow], [0, false, true])
  }
  {
    const p = streamPage({ durations: { 1: 10, 2: 5 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    tap(() => media.handlers.pause())
    await run(500)
    const pausedAt = e0.currentTime
    tap(() => media.handlers.play())
    await run(1_000)
    check('the lock screen pauses and plays a stream', [e0.paused, e0.playingNow, e0.currentTime > pausedAt, e0.srcObject === mediaSources[0]], [false, true, true, true])
  }

  console.log('\none stream: what the network does to it')
  {
    const p = streamPage({ durations: { 1: 120, 2: 5 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    net.bodyStallAt = { 1: 50_000 }
    await run(60_000)
    check('a piece whose body stops arriving: given up and asked again, and song 1 plays on', [p.player.track.id, e0.playingNow], ['1', true])
    net.bodyStallAt = null
  }
  {
    const p = streamPage({ durations: { 1: 90, 2: 5 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    warns.length = 0
    net.fmp4Answer['1'] = { status: 0, times: 5 }
    await run(40_000)
    check('a piece failing five times in a row with music in hand is not a failure', [p.player.track.id, e0.srcObject === mediaSources[0], e0.playingNow, leftStream()], ['1', true, true, []])
  }
  {
    const p = streamPage({ durations: { 1: 5, 2: 5 } })
    net.fmp4Answer['1'] = { status: 503, times: 999 }
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(400)
    check('the first song\'s head answered 503 (this song, not ready): the URL way at once, no retrying', [e0.srcObject === null, e0.playingNow], [true, true])
  }
  {
    const p = streamPage({ durations: { 1: 5, 2: 5 } })
    net.fmp4Answer['*'] = { status: 503, scope: 'server', times: 999 }
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    const asks = fmp4Requests.length
    tap(() => p.player.playTracks(tracks(['1', '2']), 1))
    await run(1_000)
    check('deadwax\'s cache unusable (503, scope server): one fallback, then no stream tried for a while', [fmp4Requests.length - asks, mediaSources.length], [0, 1])
  }

  console.log('\none stream: three failed streams in a row, not three failures ever')
  {
    const p = streamPage({ durations: { 1: 5, 2: 5, 3: 5, 4: 5, 5: 5, 6: 5 } })
    //? heads 1, 3 and 5 refused as busy; 2 and 4 stream and play between them
    for (const [id, ok] of [['1', false], ['2', true], ['3', false], ['4', true], ['5', false], ['6', true]]) {
      net.fmp4Answer = ok ? {} : { [id]: { status: 503, times: 999 } }
      tap(() => p.player.playTracks(tracks([id]), 0))
      await run(1_500)
    }
    check('song 6 still streams: the failures had streams playing between them', elements[0].srcObject === mediaSources[mediaSources.length - 1] && elements[0].playingNow, true)
    net.fmp4Answer = {}
  }

  console.log('\none stream: the joins are sample-exact in the SourceBuffer')
  {
    const r9 = (x) => (x == null ? x : Math.round(x * 1e9) / 1e9)
    const p = streamPage({ durations: { 1: 6, 2: 5, 3: 7 } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2', '3']), 0))
    await run(1_500)
    const sb = streamOf(e0).sourceBuffers[0]
    const at = starts(['1', '2', '3'])
    const firsts = ['2', '3'].map((id) => sb.frames.find((f) => f.id === id)?.start)
    const lasts = ['1', '2'].map((id) => { const fs = sb.frames.filter((f) => f.id === id); return fs[fs.length - 1]?.end })
    check('song N+1\'s first frame starts exactly where song N\'s last ends, at its place', [firsts.map(r9), lasts.map(r9)], [[at[1], at[2]].map(r9), [at[1], at[2]].map(r9)])
    //? the head brings 256 KiB - two whole fragments of about 112 KB here - and those are appended from
    //? it: the first piece asked for begins at the third fragment, not the first
    const first = fmp4Requests.find((r) => r.id === '1' && r.range !== 'bytes=0-262143')
    check('the fragments that came with the head are appended from it, not fetched again', Number(/bytes=(\d+)/.exec(first?.range ?? '')?.[1]) > 131072, true)
  }
  {
    const p = streamPage({ durations: { 1: 5, 2: { duration: 5, rate: 48000 } } })
    const [e0] = elements
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    await run(1_000)
    tap(() => p.player.playTracks(tracks(['1', '2']), 1))
    await run(600)
    check('a song that only differs in format from the run starts a stream of its own, later', [p.player.track.id, mediaSources.length, e0.srcObject === mediaSources[1]], ['2', 2, true])
  }
  {
    const p = streamPage({ durations: { 1: 6, 2: 6 } })
    tap(() => p.player.playTracks(tracks(['1', '2']), 0))
    const seen = new Set()
    for (let k = 0; k < 40; k++) {
      await run(250)
      for (const e of elements.slice(1)) { const s = e.getAttribute('src'); if (s) seen.add(s) }
    }
    check('nothing of the run is downloaded a second time for the standby', [fetched.filter((f) => !/\+fmp4/.test(f)), [...seen]], [[], []])
  }
  console.warn = realWarn

  define('fetch', realFetch)

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
