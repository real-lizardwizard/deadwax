/**
 * Reading the head of a song deadwax sends as fragmented MP4 (lib/fmp4.ts): the init segment's
 * end, the index's end, the timescale, the song's exact length, its FLAC format, and every
 * fragment's byte range and place in time.
 *
 * What it pins is what the one-stream engine rests on and a person hears only as a click, a stall
 * or silence on a locked phone: a fragment fetched from the wrong bytes, a song placed at the wrong
 * time, a 96 kHz song taken for 48 kHz because the sample entry's rate was believed, or a head that
 * isn't quite right streamed anyway instead of played the ordinary way. Heads are built here box
 * by box by a small writer that follows the server's layout (src/flac_mp4.py's fmp4_layout), and
 * then broken one way at a time. The heads the Python writer itself made
 * (tests/fixtures/fmp4_heads.json) are parsed too - that is what holds the writer and this reader
 * to each other, since each passes its own suite alone.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/fmp4.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-fmp4-'))
const FIXTURE = path.resolve(UI, '..', 'tests', 'fixtures', 'fmp4_heads.json')

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/fmp4.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const { parseHead, sameFormat, initBytes, piecesInside, HEAD_FETCH_BYTES } = require(path.join(OUT, 'lib/fmp4.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ========================================================================== */
/* A small MP4 writer, the server's layout box for box                        */

const u8 = (n) => Buffer.from([n & 0xff])
const u16 = (n) => { const b = Buffer.alloc(2); b.writeUInt16BE(n); return b }
const u24 = (n) => Buffer.from([(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff])
const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n >>> 0); return b }
const u64 = (n) => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b }
const text = (s) => Buffer.from(s, 'latin1')

/** A box: its size, its type, its contents. `size` 'large' writes a 64-bit size, 'zero' writes 0. */
function box(type, parts, size = 'plain') {
  const body = Buffer.concat(parts)
  if (size === 'large') return Buffer.concat([u32(1), text(type), u64(16 + body.length), body])
  if (size === 'zero') return Buffer.concat([u32(0), text(type), body])
  return Buffer.concat([u32(8 + body.length), text(type), body])
}
const full = (type, version, flags, parts, size) => box(type, [u32(((version << 24) | flags) >>> 0), ...parts], size)

const MATRIX = Buffer.concat([0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000].map(u32))

/** STREAMINFO's 34 bytes: block sizes, frame sizes, then rate / channels / bits / total, then MD5. */
function streaminfo({ rate, channels, bits, total }) {
  const packed = (BigInt(rate) << 44n) | (BigInt(channels - 1) << 41n) | (BigInt(bits - 1) << 36n) | BigInt(total)
  const eight = Buffer.alloc(8)
  eight.writeBigUInt64BE(packed)
  return Buffer.concat([u16(4096), u16(4096), u24(0), u24(0), eight, Buffer.alloc(16, 0xab)])
}

/** The sample entry's 16.16 rate, clamped as the Python writer clamps it (96 kHz -> 48000.0). */
function entryRate(rate) {
  let value = rate
  while (value > 0xffff && value % 2 === 0) value /= 2
  return (value <= 0xffff ? value : 0xffff) * 0x10000
}

/** A deterministic stream of frame sizes, so every run builds the same files. */
function sizes(seed) {
  let s = seed
  return () => { s = (s * 1103515245 + 12345) % 2147483648; return 300 + Math.floor((s / 2147483648) * 2700) }
}

/**
 * A whole fragmented MP4 and what parseHead must find in it. Every option is one way the head can
 * differ from the ordinary one - the good ones the server may write, the bad ones it must not.
 */
function build(o = {}) {
  const rate = o.rate ?? 44100
  const channels = o.channels ?? 2
  const bits = o.bits ?? 16
  const timescale = o.timescale ?? rate
  const seconds = o.seconds ?? 5.3
  const block = o.block ?? 4096
  const total = Math.round(seconds * rate)
  const nextSize = sizes(o.seed ?? 1)

  //? frames of `block` samples (the last short), grouped into ~1 s fragments as the server's _chunks
  const frames = []
  for (let done = 0; done < total; done += block) frames.push({ samples: Math.min(block, total - done), size: o.frameSize ?? nextSize() })
  const groups = []
  let held = [], samples = 0
  for (const frame of frames) {
    held.push(frame)
    samples += frame.samples
    if (samples >= (o.fragmentSeconds ?? 1) * rate) { groups.push(held); held = []; samples = 0 }
  }
  if (held.length) groups.push(held)

  const dfla = full('dfLa', o.dflaVersion ?? 0, 0, [u8(0x80 | (o.firstBlock ?? 0)), u24(34), streaminfo({ rate: o.infoRate ?? rate, channels, bits, total })])
  const entry = box(o.entryType ?? 'fLaC', [Buffer.alloc(6), u16(1), Buffer.alloc(8), u16(channels), u16(bits), u16(0), u16(0),
    u32(entryRate(rate)), ...(o.noDfla ? [] : [dfla])])
  const stsd = full('stsd', 0, 0, [u32(o.emptyStsd ? 0 : 1), ...(o.emptyStsd ? [] : [entry])])
  const stbl = box('stbl', [stsd, full('stts', 0, 0, [u32(0)]), full('stsc', 0, 0, [u32(0)]), full('stsz', 0, 0, [u32(0), u32(0)]), full('stco', 0, 0, [u32(0)])])
  const minf = box('minf', [full('smhd', 0, 0, [u32(0)]), box('dinf', [full('dref', 0, 0, [u32(1), full('url ', 0, 1, [])])]), stbl])
  const mdhd = (o.mdhdVersion ?? 0) === 1
    ? full('mdhd', 1, 0, [u64(0), u64(0), u32(o.mdhdTimescale ?? timescale), u64(0), u16(0x55c4), u16(0)])
    : full('mdhd', 0, 0, [u32(0), u32(0), u32(o.mdhdTimescale ?? timescale), u32(0), u16(0x55c4), u16(0)])
  const hdlr = full('hdlr', 0, 0, [u32(0), text(o.handler ?? 'soun'), Buffer.alloc(12), text('SoundHandler\0')])
  const mdia = box('mdia', [mdhd, hdlr, minf])
  const tkhd = full('tkhd', 0, 3, [u32(0), u32(0), u32(1), u32(0), u32(0), Buffer.alloc(8), u16(0), u16(1), u16(0x0100), u16(0), MATRIX, u32(0), u32(0)])
  const trak = box('trak', [tkhd, mdia])
  const mvhd = full('mvhd', 0, 0, [u32(0), u32(0), u32(timescale), u32(0), u32(0x10000), u16(0x0100), Buffer.alloc(10), MATRIX, Buffer.alloc(24), u32(2)])
  const mvex = box('mvex', [full('trex', 0, 0, [u32(1), u32(1), u32(0), u32(0), u32(0)])], o.mvexSize ?? 'plain')
  const moov = box('moov', [mvhd, ...(o.twoTraks ? [trak, trak] : [trak]), ...(o.noMvex ? [] : [mvex])], o.moovSize ?? 'plain')
  const ftyp = box('ftyp', [text('iso5'), u32(512), text('iso5'), text('iso6'), text('mp41')])

  //? each fragment: moof (mfhd, traf: tfhd, tfdt, trun) then mdat, the trun's data offset pointing
  //? past the moof and the mdat's header - so the moof is built twice, the second time knowing its size
  let t0 = 0
  const fragments = groups.map((group, i) => {
    const variable = group.some((f) => f.samples !== group[0].samples)
    const moofWith = (offset) => box('moof', [
      full('mfhd', 0, 0, [u32(i + 1)]),
      box('traf', [
        full('tfhd', 0, 0x020038, [u32(1), u32(group[0].samples), u32(group[0].size), u32(0x02000000)]),
        full('tfdt', 1, 0, [u64(t0)]),
        full('trun', 0, variable ? 0x301 : 0x201, [u32(group.length), u32(offset),
          ...group.map((f) => (variable ? Buffer.concat([u32(f.samples), u32(f.size)]) : u32(f.size)))]),
      ]),
    ])
    const moof = moofWith(moofWith(0).length + 8)
    const mdatBody = Buffer.concat(group.map((f, k) => Buffer.alloc(f.size, (i * 7 + k) & 0xff)))
    const mdat = i === groups.length - 1 && o.lastMdatZero ? box('mdat', [mdatBody], 'zero') : box('mdat', [mdatBody])
    const units = group.reduce((sum, f) => sum + f.samples, 0)
    const fragment = { bytes: Buffer.concat([moof, mdat]), t0, units }
    t0 += units
    return fragment
  })

  const gap = o.firstOffset ? box('free', [Buffer.alloc(o.firstOffset - 8)]) : Buffer.alloc(0)
  const refs = fragments.map((f, i) => Buffer.concat([
    u32(((i === 0 && o.referenceType1 ? 0x80000000 : 0) | (o.zeroSize && i === 1 ? 0 : f.bytes.length)) >>> 0),
    u32(o.zeroDuration && i === 1 ? 0 : f.units), u32(0x90000000),
  ]))
  const count = o.sidxCount ?? fragments.length
  const sidxVersion = o.sidxVersion ?? 0
  const sidx = full('sidx', sidxVersion, 0, [u32(1), u32(o.sidxTimescale ?? timescale),
    ...(sidxVersion === 1 ? [u64(o.earliest ?? 0), u64(o.firstOffset ?? 0)] : [u32(o.earliest ?? 0), u32(o.firstOffset ?? 0)]),
    u16(0), u16(count), ...refs.slice(0, o.sidxRefsWritten ?? refs.length)], o.sidxSize ?? 'plain')

  const heads = { ftyp, moov, sidx }
  const order = o.order ?? ['ftyp', 'moov', 'sidx']
  const head = Buffer.concat(order.map((name) => heads[name]))
  const file = Buffer.concat([head, gap, ...fragments.map((f) => f.bytes)])

  const initEnd = ftyp.length + moov.length
  const indexEnd = initEnd + sidx.length
  let at = indexEnd + (o.firstOffset ?? 0)
  const expect = {
    initEnd,
    indexEnd,
    timescale,
    units: total,
    format: { sampleRate: rate, channels, bitsPerSample: bits },
    fragments: fragments.map((f) => { const start = at; at += f.bytes.length; return { start, end: at, t0: f.t0, units: f.units } }),
  }
  return { file, head, expect, parts: { ftyp, moov, sidx } }
}

/** parseHead on a Buffer, the way the engine will call it: the first bytes, and the file's size. */
const parse = (file, total = file.length, upTo = HEAD_FETCH_BYTES) => parseHead(file.subarray(0, upTo), total)
const why = (answer) => (answer.kind === 'bad' ? answer.why : `(a head: ${JSON.stringify(answer.head).slice(0, 80)})`)
const isBad = (answer) => answer.kind === 'bad'

/* ========================================================================== */
console.log('\nheads the server writes')

{
  const song = build()
  const answer = parse(song.file)
  check('44.1 kHz / 16-bit / stereo: a head', answer.kind, 'head')
  check('...exactly the head written: init, index, timescale, length, format, every fragment', answer.head, song.expect)
  check('the init segment ends where the moov does', answer.head.initEnd, song.parts.ftyp.length + song.parts.moov.length)
  check('the song\'s length is every sample, from the index', answer.head.units, Math.round(5.3 * 44100))
  check('fragments follow one another from the end of the index', answer.head.fragments.every((f, i, all) => i === 0 ? f.start === answer.head.indexEnd : f.start === all[i - 1].end), true)
  check('each fragment\'s t0 is the samples before it', answer.head.fragments.every((f, i, all) => i === 0 ? f.t0 === 0 : f.t0 === all[i - 1].t0 + all[i - 1].units), true)
  check('~1 s fragments of whole 4096-sample frames: 11 frames each at 44.1 kHz', answer.head.fragments[0].units, 11 * 4096)
  check('the last fragment holds the short last frame', answer.head.fragments.at(-1).units, Math.round(5.3 * 44100) - 5 * 11 * 4096)
  check('the last fragment ends at the end of the file', answer.head.fragments.at(-1).end, song.file.length)
  check('without the file\'s size: the same head', parseHead(song.file.subarray(0, HEAD_FETCH_BYTES)), answer)
  check('...and null for the size says the same', parseHead(song.file, null), answer)
}
{
  const song = build({ rate: 48000, bits: 24, sidxVersion: 1, mdhdVersion: 1 })
  const answer = parse(song.file)
  check('48 kHz / 24-bit, a version 1 index and mdhd: the head written', answer.head, song.expect)
  check('...its format', answer.head.format, { sampleRate: 48000, channels: 2, bitsPerSample: 24 })
}
{
  //? the sample entry's 16.16 field can't hold 96000, so the server writes 48000.0 there: the real
  //? rate is only in STREAMINFO, and a reader that believed the entry would play it at half speed
  const song = build({ rate: 96000, bits: 24 })
  const entryAt = song.file.indexOf(Buffer.from('fLaC')) - 4
  check('96 kHz: the sample entry itself says 48000', song.file.readUInt32BE(entryAt + 8 + 24) / 0x10000, 48000)
  const answer = parse(song.file)
  check('...and the head reads 96000 from STREAMINFO', answer.head.format.sampleRate, 96000)
  check('...on a 96000 timescale', answer.head.timescale, 96000)
  check('...the whole head as written', answer.head, song.expect)
}
{
  const song = build({ rate: 192000, bits: 24, seconds: 2.2 })
  check('192 kHz: read from STREAMINFO too', parse(song.file).head.format.sampleRate, 192000)
}
{
  const song = build({ channels: 6, bits: 24, rate: 48000 })
  check('6 channels: read (streaming it is streamPlan\'s to refuse)', parse(song.file).head.format, { sampleRate: 48000, channels: 6, bitsPerSample: 24 })
}
{
  //? a stream with a block size that varies: a fragment with two frame lengths gets per-sample durations
  const song = build({ block: 4608, rate: 44100, seconds: 3.1 })
  check('another block size: the head written', parse(song.file).head, song.expect)
}
{
  const song = build({ moovSize: 'large' })
  check('a moov with a 64-bit size: read', parse(song.file).head, song.expect)
  check('...and the init segment includes its 16-byte header', parse(song.file).head.initEnd, song.parts.ftyp.length + song.parts.moov.length)
}
{
  //? a box whose size is 0 runs to the end of what holds it: the moov's last box here
  const song = build({ mvexSize: 'zero' })
  check('the moov\'s last box with size 0 (to the end of the moov): read', parse(song.file).head, song.expect)
}
{
  const song = build({ lastMdatZero: true })
  check('the file\'s last mdat with size 0 (to the end of the file): the head doesn\'t mind', parse(song.file).head, song.expect)
}
{
  const song = build({ firstOffset: 64 })
  check('an index whose first_offset skips a box: fragments start past it', parse(song.file).head, song.expect)
  check('...the first 64 bytes after the index', parse(song.file).head.fragments[0].start, song.expect.indexEnd + 64)
}
{
  const song = build({ sidxVersion: 1, firstOffset: 40 })
  check('the same with a version 1 index (64-bit offset)', parse(song.file).head, song.expect)
}
{
  //? an index longer than a few hundred fragments: the head fetch is sized for about six hours
  const song = build({ seconds: 60 * 60 * 2.2, frameSize: 40, rate: 8000, block: 8000 })
  const answer = parse(song.file)
  check(`a ${song.expect.fragments.length}-fragment index inside the first ${HEAD_FETCH_BYTES} bytes: read`, answer.kind, 'head')
  check('...every fragment', answer.head && answer.head.fragments.length, song.expect.fragments.length)
  check('...ending at the end of the file', answer.head && answer.head.fragments.at(-1).end, song.file.length)
}
{
  const song = build({ seconds: 60 * 60 * 6.2, frameSize: 20, rate: 8000, block: 8000 })
  const answer = parse(song.file)
  check('an index too long for the head fetch: bad, not a guess', answer.kind, 'bad')
  check('...saying it doesn\'t fit', /doesn't fit in the first 262144 bytes/.test(why(answer)), true)
  check('...and the same index read whole is fine', parse(song.file, song.file.length, song.file.length).kind, 'head')
}

/* ========================================================================== */
console.log('\nheads that are refused, each with its reason')

const refused = (label, file, pattern, total = file.length, upTo = HEAD_FETCH_BYTES) => {
  const answer = parse(file, total, upTo)
  check(`${label}: bad`, answer.kind, 'bad')
  check(`...saying so ("${why(answer)}")`, pattern.test(why(answer)), true)
}

refused('no ftyp: the moov first', build({ order: ['moov', 'sidx'] }).file, /doesn't start with an 'ftyp'.*'moov'/)
refused('no moov: the ftyp then the index', build({ order: ['ftyp', 'sidx'] }).file, /followed by 'sidx', not 'moov'/)
refused('no index: the moov then the first fragment', build({ order: ['ftyp', 'moov'] }).file, /followed by 'moof', not the index/)
refused('the index before the moov', build({ order: ['ftyp', 'sidx', 'moov'] }).file, /followed by 'sidx', not 'moov'/)
{
  const song = build()
  const sidxEnd = song.expect.indexEnd
  refused('the bytes end inside the index', song.file, /index \(sidx\) doesn't fit/, song.file.length, sidxEnd - 5)
  refused('the bytes end inside the moov', song.file, /moov doesn't fit/, song.file.length, song.expect.initEnd - 1)
  refused('the bytes end before the index starts', song.file, /bytes end before the sidx/, song.file.length, song.expect.initEnd + 3)
  //? cut anywhere before the index's end is bad; from its end on, the same head
  let cutBad = true, cutSame = true
  for (let upTo = 0; upTo < sidxEnd; upTo++) if (parse(song.file, song.file.length, upTo).kind !== 'bad') cutBad = false
  const whole = JSON.stringify(parse(song.file))
  for (let upTo = sidxEnd; upTo <= Math.min(song.file.length, sidxEnd + 400); upTo++) {
    if (JSON.stringify(parse(song.file, song.file.length, upTo)) !== whole) cutSame = false
  }
  check('cut at every byte before the index ends: bad every time', cutBad, true)
  check('cut anywhere after it: the same head every time', cutSame, true)
}
refused('an index that lists more fragments than it holds', build({ sidxRefsWritten: 2 }).file, /sidx is cut short: it lists \d+ fragments and holds 2/)
refused('an index pointing at another index (reference_type 1)', build({ referenceType1: true }).file, /reference_type 1/)
{
  const song = build()
  refused('the file one byte longer than the index says', song.file, /accounts for \d+ bytes and the file is \d+/, song.file.length + 1)
  refused('...one byte shorter', song.file, /accounts for/, song.file.length - 1)
}
refused('a FLAC sample entry with no dfLa', build({ noDfla: true }).file, /no 'dfLa' box/)
refused('samples that aren\'t FLAC', build({ entryType: 'mp4a' }).file, /'mp4a', not FLAC/)
refused('an empty sample description', build({ emptyStsd: true }).file, /describes no samples/)
refused('a dfLa of another version', build({ dflaVersion: 1 }).file, /dfLa box is version 1/)
refused('a dfLa that doesn\'t start with STREAMINFO', build({ firstBlock: 4 }).file, /doesn't start with STREAMINFO/)
refused('STREAMINFO with no sample rate', build({ infoRate: 0 }).file, /no sample rate/)
refused('no mvex: not a fragmented MP4', build({ noMvex: true }).file, /no 'mvex'/)
refused('two tracks', build({ twoTraks: true }).file, /holds 2 tracks/)
refused('a track that isn\'t sound', build({ handler: 'vide' }).file, /'vide', not sound/)
refused('a timescale of 0', build({ mdhdTimescale: 0, sidxTimescale: 0 }).file, /timescale of 0/)
refused('the index on another clock than the track', build({ sidxTimescale: 1000 }).file, /1\/1000 s, the track in 1\/44100 s/)
refused('the index not starting at time 0', build({ earliest: 4096 }).file, /starts at time 4096/)
refused('an index of no fragments', build({ sidxCount: 0, sidxRefsWritten: 0 }).file, /no fragments/)
refused('a fragment of 0 bytes', build({ zeroSize: true }).file, /fragment 2 of the index is 0 bytes/)
refused('a fragment holding no time', build({ zeroDuration: true }).file, /fragment 2 of the index holds no time/)
{
  //? the index's sizes drifting from the file: the second fragment isn't where it says
  const song = build()
  const moved = Buffer.from(song.file)
  const sidxAt = song.expect.initEnd
  //? grow the first fragment's referenced_size by 4 and shrink the second's by 4: the total still agrees
  const ref0 = sidxAt + 8 + 24, ref1 = ref0 + 12
  moved.writeUInt32BE(moved.readUInt32BE(ref0) + 4, ref0)
  moved.writeUInt32BE(moved.readUInt32BE(ref1) - 4, ref1)
  refused('an index whose sizes have drifted from the file', moved, /puts fragment 2 at byte \d+, and there is no 'moof' there/)
}
{
  const song = build({ firstOffset: 64 })
  const patched = Buffer.from(song.file)
  patched.writeUInt32BE(32, song.expect.initEnd + 8 + 16)
  //? no file size, or the index's own total would disagree first
  refused('a first_offset pointing into the middle of a box', patched, /puts fragment 1 at byte/, null)
}
{
  //? a top-level box of size 0 runs to the end of the FILE - which ends the head there
  refused('a moov of size 0 (to the end of the file)', build({ moovSize: 'zero' }).file, /moov doesn't fit|followed by/, null)
  const song = build({ moovSize: 'zero' })
  refused('...even when the whole file is given', song.file, /bytes end before the sidx|doesn't fit/, song.file.length, song.file.length)
  refused('an index of size 0 with no file size given', build({ sidxSize: 'zero' }).file, /index \(sidx\) doesn't fit/, null)
  const whole = build({ sidxSize: 'zero' })
  refused('...and with the whole file, it leaves no room for the audio', whole.file, /accounts for/, whole.file.length, whole.file.length)
}
{
  const song = build()
  const big = Buffer.from(song.file)
  //? a 64-bit moov size past 2^53: can't be read exactly, so it isn't guessed at
  const at = song.parts.ftyp.length
  refused('a 64-bit box size too large to hold exactly', Buffer.concat([big.subarray(0, at), u32(1), text('moov'), Buffer.from([0x00, 0x40, 0, 0, 0, 0, 0, 0])]), /too large to read exactly/)
  refused('a box that says it is smaller than its own header', Buffer.concat([big.subarray(0, at), u32(4), text('moov'), big.subarray(at + 8)]), /less than its own header/)
}
refused('nothing at all', Buffer.alloc(0), /too short/)
refused('seven bytes', Buffer.from('ftypiso'), /too short/)
refused('a page of HTML', Buffer.from('<!doctype html><html><body>not audio</body></html>'), /doesn't start with an 'ftyp'/)
refused('a FLAC file as it is', Buffer.concat([text('fLaC'), Buffer.alloc(300, 7)]), /doesn't start with an 'ftyp'/)
refused('zeros', Buffer.alloc(4096), /'ftyp'/)
refused('the plain MP4 deadwax makes for Safari (ftyp, moov, mdat)', (() => {
  const s = build()
  return Buffer.concat([s.parts.ftyp, s.parts.moov, box('mdat', [Buffer.alloc(100)])])
})(), /followed by 'mdat', not the index/)

{
  //? garbage and damage of every kind: an answer every time, never an exception
  let seed = 99
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 }
  const song = build()
  let threw = 0, answers = 0, heads = 0
  for (let trial = 0; trial < 3000; trial++) {
    let bytes
    if (trial % 3 === 0) {
      bytes = Buffer.alloc(Math.floor(rnd() * 600))
      for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(rnd() * 256)
    } else {
      bytes = Buffer.from(song.file.subarray(0, song.expect.indexEnd + 200))
      const flips = 1 + Math.floor(rnd() * 4)
      for (let f = 0; f < flips; f++) bytes[Math.floor(rnd() * song.expect.indexEnd)] = Math.floor(rnd() * 256)
    }
    try {
      const answer = parseHead(bytes, rnd() < 0.5 ? song.file.length : null)
      if (answer.kind === 'head' || (answer.kind === 'bad' && typeof answer.why === 'string' && answer.why.length > 0)) answers++
      if (answer.kind === 'head') heads++
    } catch (error) {
      threw++
    }
  }
  check('3000 garbled heads: never an exception', threw, 0)
  check('...always a head or a reason in words', answers, 3000)
  console.log(`  (of those, ${heads} still read as a head - a flipped byte in a field nothing checks, like a timestamp)`)
}

/* ========================================================================== */
console.log('\nthe init segment, and what the head fetch already holds')

{
  const song = build({ seconds: 30 })
  const head = parse(song.file).head
  const fetched = song.file.subarray(0, HEAD_FETCH_BYTES)
  const init = initBytes(head, fetched)
  check('the init segment is bytes [0, initEnd)', Buffer.from(init).equals(song.file.subarray(0, head.initEnd)), true)
  check('...ftyp then moov, and no index', [Buffer.from(init.subarray(4, 8)).toString(), Buffer.from(init.subarray(song.parts.ftyp.length + 4, song.parts.ftyp.length + 8)).toString(), init.length], ['ftyp', 'moov', head.initEnd])
  check('...a plain Uint8Array', Object.getPrototypeOf(init) === Uint8Array.prototype, true)
  //? kept for as long as the song is in the run: a view would keep the whole 256 KiB alive
  check('...a copy, not a view of the fetched bytes', init.buffer.byteLength, head.initEnd)
  const copy = Buffer.from(song.file)
  const kept = initBytes(head, copy)
  copy[4] = 0x58
  check('...unchanged when the fetched bytes change', Buffer.from(kept.subarray(4, 8)).toString(), 'ftyp')

  check('nothing past the index: no fragment inside', piecesInside(head, head.indexEnd), 0)
  check('up to the first fragment\'s last byte but one: none', piecesInside(head, head.fragments[0].end - 1), 0)
  check('up to the first fragment\'s end: one', piecesInside(head, head.fragments[0].end), 1)
  check('one byte short of the second\'s end: still one', piecesInside(head, head.fragments[1].end - 1), 1)
  check('the whole file: every fragment', piecesInside(head, song.file.length), head.fragments.length)
  check('more than the whole file: every fragment, no more', piecesInside(head, song.file.length * 2), head.fragments.length)
  const inHeadFetch = head.fragments.filter((f) => f.end <= HEAD_FETCH_BYTES).length
  check(`the ${HEAD_FETCH_BYTES}-byte head fetch holds the first ${inHeadFetch} fragments, appended at once`, piecesInside(head, HEAD_FETCH_BYTES), inHeadFetch)
  check('...some, for a CD song (the fast start)', inHeadFetch > 0, true)
  check('none at all for nothing fetched', piecesInside(head, 0), 0)
}
check('the head fetch is 256 KiB', HEAD_FETCH_BYTES, 262144)

/* ========================================================================== */
console.log('\nsame format')

const cd = { sampleRate: 44100, channels: 2, bitsPerSample: 16 }
check('the same', sameFormat(cd, { ...cd }), true)
check('another rate', sameFormat(cd, { ...cd, sampleRate: 48000 }), false)
check('another channel count', sameFormat(cd, { ...cd, channels: 1 }), false)
check('another depth', sameFormat(cd, { ...cd, bitsPerSample: 24 }), false)

/* ========================================================================== */
console.log('\nheads the Python writer made (tests/fixtures/fmp4_heads.json)')

if (!fs.existsSync(FIXTURE)) {
  //? never skipped: the fixture is what holds the Python writer and this parser to each other
  check(`the fixture ${FIXTURE} exists - it is made by tests/test_flac_mp4.py; without it the writer and this reader are held to nothing`, false, true)
} else {
  let fixture = null
  try { fixture = JSON.parse(fs.readFileSync(FIXTURE, 'utf8')) } catch (error) { check(`the fixture parses as JSON (${error.message})`, false, true) }
  const heads = fixture && Array.isArray(fixture.heads) ? fixture.heads : []
  check('the fixture holds heads', heads.length > 0, true)
  for (const entry of heads) {
    const bytes = new Uint8Array(Buffer.from(entry.b64, 'base64'))
    const answer = parseHead(bytes, entry.total)
    const e = entry.expect ?? {}
    const f = e.format ?? {}
    const expected = {
      initEnd: e.initEnd, indexEnd: e.indexEnd, timescale: e.timescale, units: e.units,
      format: { sampleRate: f.sampleRate, channels: f.channels, bitsPerSample: f.bitsPerSample },
      fragments: (e.fragments ?? []).map(([start, end, t0, units]) => [start, end, t0, units]),
    }
    const got = answer.kind === 'head' ? {
      initEnd: answer.head.initEnd, indexEnd: answer.head.indexEnd, timescale: answer.head.timescale, units: answer.head.units,
      format: answer.head.format,
      fragments: answer.head.fragments.map((x) => [x.start, x.end, x.t0, x.units]),
    } : { bad: answer.why }
    check(`"${entry.name}": what the Python writer says it wrote`, got, expected)
    if (answer.kind === 'head') {
      const init = initBytes(answer.head, bytes)
      check(`"${entry.name}": its init segment is ftyp + moov`, [Buffer.from(init.subarray(4, 8)).toString(), init.length], ['ftyp', answer.head.initEnd])
      check(`"${entry.name}": piecesInside of what was fetched counts whole fragments in it`,
        piecesInside(answer.head, bytes.length), answer.head.fragments.filter((x) => x.end <= bytes.length).length)
      check(`"${entry.name}": its timescale is its sample rate, so its units are samples`, answer.head.timescale, answer.head.format.sampleRate)
    }
  }
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
