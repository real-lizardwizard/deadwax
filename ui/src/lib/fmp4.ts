/**
 * Reading the head of a FLAC song deadwax repackaged as FRAGMENTED MP4 (`wrap=fmp4`,
 * src/flac_mp4.py's fmp4_layout): what the one-stream engine needs to know before it appends a
 * byte of it.
 *
 * The file is ftyp, moov, sidx, then one moof+mdat pair per second or so of audio. The first two
 * are the INIT SEGMENT, appended to the SourceBuffer before each song's media (without it the
 * join clicks). The sidx is never appended: it is the file's INDEX - the byte range and the length
 * in samples of every fragment - and it is the only way to turn a time (a seek, a range the
 * browser evicted) into the bytes to fetch without walking every moof. And the dfLa box inside the
 * moov carries the FLAC STREAMINFO, which says the song's real format: a run of songs in one
 * stream holds ONE format, so this is what decides whether the next song can join it.
 *
 * The whole head has to be inside the first HEAD_FETCH_BYTES of the file, which is one request.
 * There is no "fetch more and try again": a head that doesn't fit is 'bad', and that song plays
 * the way every song plays without the stream. 256 KiB of sidx is about 21,000 fragments - some
 * six hours of audio, longer than anything deadwax will repackage at CD rate.
 *
 * Strict on purpose. The only writer this has to read is deadwax's own, and anything that isn't
 * exactly that shape - a box missing or out of order, an index that disagrees with the file's size
 * or points at something other than a moof - is a reason not to stream the song, said in plain
 * words, rather than a guess that ends as a click, a stall or silence on a locked phone. It never
 * throws: every answer is a head or a reason.
 *
 * Pure, like the rest of lib/, so ui/test/fmp4.sim.cjs can hold it to heads built box by box, and
 * to heads the Python writer made (tests/fixtures/fmp4_heads.json) - which is what keeps the writer
 * and this reader from drifting apart while each passes its own suite.
 */

/** How much of a song is asked for first: the whole head, and the first fragments with it. */
export const HEAD_FETCH_BYTES = 262144

/** A FLAC stream's format, from its STREAMINFO. */
export interface FlacFormat {
  sampleRate: number
  channels: number
  bitsPerSample: number
}

/**
 * One fragment of the song: its moof+mdat, which is what is fetched and appended as a unit.
 * `start`/`end` are the byte range [start, end) in the file; `t0` is how many time units of the
 * song come before it, and `units` how many it holds (samples, with the timescale at the rate).
 */
export interface Fragment {
  start: number
  end: number
  t0: number
  units: number
}

export interface Fmp4Head {
  /** the init segment is bytes [0, initEnd): ftyp + moov */
  initEnd: number
  /** where the sidx ends - the first fragment starts here (plus the index's first_offset) */
  indexEnd: number
  /** the track's timescale, from mdhd: time units a second */
  timescale: number
  /** the song's length in time units: its fragments', summed. Exact, unlike any tag */
  units: number
  format: FlacFormat
  fragments: Fragment[]
}

export type HeadParse = { kind: 'head'; head: Fmp4Head } | { kind: 'bad'; why: string }

/** Thrown inside the parser only, and always caught: the reason a head isn't usable. */
class Bad {
  readonly why: string

  constructor(why: string) {
    this.why = why
  }
}

function bad(why: string): never {
  throw new Bad(why)
}

interface Box {
  type: string
  start: number
  /** where its contents begin: after the 8-byte header, or 16 with a 64-bit size */
  body: number
  end: number
}

/** A box type as text, with anything unprintable shown as '?' - garbage says it is garbage. */
function typeAt(bytes: Uint8Array, at: number): string {
  let text = ''
  for (let i = at; i < at + 4; i++) {
    const code = bytes[i] ?? 0
    text += code >= 0x20 && code <= 0x7e ? String.fromCharCode(code) : '?'
  }
  return text
}

class Reader {
  readonly bytes: Uint8Array
  private readonly view: DataView

  constructor(bytes: Uint8Array) {
    this.bytes = bytes
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  }

  u8(at: number): number {
    return this.view.getUint8(at)
  }

  u16(at: number): number {
    return this.view.getUint16(at)
  }

  u32(at: number): number {
    return this.view.getUint32(at)
  }

  /** A 64-bit field, as a number - refused past what a number holds exactly (2^53). */
  u64(at: number, what: string): number {
    const high = this.view.getUint32(at)
    const low = this.view.getUint32(at + 4)
    if (high >= 0x200000) bad(`the ${what} is too large to read exactly`)
    return high * 0x100000000 + low
  }

  /**
   * The box starting at `at`, which has to end by `limit`. A size of 1 means a 64-bit size follows
   * the type; 0 means the box runs to the end of what holds it - `limit`, which for a top-level box
   * is the end of the FILE, not known unless the caller said how big the file is.
   */
  box(at: number, limit: number, where: string): Box {
    if (at + 8 > this.bytes.length) bad(`the bytes end before ${where}`)
    const size = this.u32(at)
    const type = typeAt(this.bytes, at + 4)
    let body = at + 8
    let end: number
    if (size === 1) {
      if (at + 16 > this.bytes.length) bad(`the '${type}' box's 64-bit size is cut short`)
      end = at + this.u64(at + 8, `'${type}' box's size`)
      body = at + 16
    } else if (size === 0) {
      end = limit
    } else {
      end = at + size
    }
    if (end < body) bad(`the '${type}' box says it is ${end - at} bytes, less than its own header`)
    if (end > limit) bad(`the '${type}' box runs past the end of what holds it`)
    return { type, start: at, body, end }
  }

  /** The boxes inside [from, to), in order. */
  children(from: number, to: number, where: string): Box[] {
    const found: Box[] = []
    for (let at = from; at < to; ) {
      if (at + 8 > to) bad(`stray bytes at the end of ${where}`)
      const child = this.box(at, to, `a box inside ${where}`)
      found.push(child)
      at = child.end
    }
    return found
  }

  /** The first child of this type - refused when there is none. */
  child(parent: Box, type: string): Box {
    const found = this.children(parent.body, parent.end, `the ${parent.type}`).find((b) => b.type === type)
    return found ?? bad(`the ${parent.type} has no '${type}' box`)
  }

  /** At least `n` bytes of the box's contents, or the box is cut short. */
  need(box: Box, n: number): void {
    if (box.body + n > box.end) bad(`the '${box.type}' box is cut short`)
  }

  version(box: Box): number {
    this.need(box, 4)
    return this.u8(box.body)
  }
}

/** The format STREAMINFO gives, from the dfLa box inside the fLaC sample entry. */
function readFormat(r: Reader, stbl: Box): FlacFormat {
  const stsd = r.child(stbl, 'stsd')
  r.need(stsd, 8)
  if (r.u32(stsd.body + 4) === 0) bad('the track describes no samples (an empty stsd)')
  //? the entries follow the version, flags and count; the first is the one the fragments use
  //? (trex's sample description 1)
  const [entry] = r.children(stsd.body + 8, stsd.end, 'the stsd')
  if (!entry) bad('the track describes no samples (an empty stsd)')
  if (entry.type !== 'fLaC') bad(`the track's samples are '${entry.type}', not FLAC ('fLaC')`)
  //? an AudioSampleEntry: 6 reserved, the data reference, 8 reserved (a version, which must be
  //? 0 - a QuickTime v1/v2 entry is longer), channels, sample size, 4 more, the 16.16 rate
  r.need(entry, 28)
  if (r.u16(entry.body + 8) !== 0) bad("the FLAC sample entry is of a version this doesn't read")
  const dfla = r.children(entry.body + 28, entry.end, 'the FLAC sample entry').find((b) => b.type === 'dfLa')
  if (!dfla) bad("the FLAC sample entry has no 'dfLa' box, so no STREAMINFO")
  if (r.version(dfla) !== 0) bad(`the dfLa box is version ${r.u8(dfla.body)}, not 0`)
  //? then FLAC's own metadata blocks, STREAMINFO first: a byte of last-flag and type, 3 of length
  r.need(dfla, 4 + 4 + 34)
  const block = r.u8(dfla.body + 4)
  const length = (r.u8(dfla.body + 5) << 16) | r.u16(dfla.body + 6)
  if ((block & 0x7f) !== 0) bad("the dfLa box doesn't start with STREAMINFO")
  if (length < 34) bad(`the STREAMINFO block is ${length} bytes, not 34`)
  //? bytes 10-13 of STREAMINFO: 20 bits of sample rate, 3 of channels - 1, 5 of bits - 1. The
  //? rate is read HERE and never from the sample entry, whose 16.16 field can't hold 96 kHz
  const at = dfla.body + 8 + 10
  const b2 = r.u8(at + 2)
  const b3 = r.u8(at + 3)
  const sampleRate = (r.u8(at) << 12) | (r.u8(at + 1) << 4) | (b2 >> 4)
  const channels = ((b2 >> 1) & 0x7) + 1
  const bitsPerSample = (((b2 & 0x1) << 4) | (b3 >> 4)) + 1
  if (sampleRate === 0) bad('STREAMINFO gives no sample rate')
  return { sampleRate, channels, bitsPerSample }
}

/** The track's timescale and format, from the moov. */
function readMoov(r: Reader, moov: Box): { timescale: number; format: FlacFormat } {
  const inside = r.children(moov.body, moov.end, 'the moov')
  //? without mvex the file isn't fragmented - the plain MP4 deadwax makes for Safari's seeks
  if (!inside.some((b) => b.type === 'mvex')) bad("the moov has no 'mvex': this isn't a fragmented MP4")
  const traks = inside.filter((b) => b.type === 'trak')
  if (traks.length !== 1) bad(`the moov holds ${traks.length} tracks, not one`)
  const mdia = r.child(traks[0]!, 'mdia')

  const mdhd = r.child(mdia, 'mdhd')
  const version = r.version(mdhd)
  if (version > 1) bad(`the mdhd box is version ${version}, not 0 or 1`)
  //? after version and flags: creation and modification times, 4 bytes each in v0, 8 in v1
  r.need(mdhd, version === 1 ? 24 : 16)
  const timescale = r.u32(mdhd.body + (version === 1 ? 20 : 12))
  if (timescale === 0) bad('the track has a timescale of 0')

  const hdlr = r.child(mdia, 'hdlr')
  r.need(hdlr, 12)
  const handler = typeAt(r.bytes, hdlr.body + 8)
  if (handler !== 'soun') bad(`the track is '${handler}', not sound`)

  const stbl = r.child(r.child(mdia, 'minf'), 'stbl')
  return { timescale, format: readFormat(r, stbl) }
}

/** The fragments the sidx lists, placed one after another from where it says the first begins. */
function readIndex(r: Reader, sidx: Box, timescale: number): Fragment[] {
  const version = r.version(sidx)
  if (version > 1) bad(`the sidx box is version ${version}, not 0 or 1`)
  //? version, flags, reference_ID, timescale; then earliest time and first offset (4 bytes each
  //? in v0, 8 in v1); 2 reserved and the count; then 12 bytes a fragment
  const head = version === 1 ? 32 : 24
  r.need(sidx, head)
  const scale = r.u32(sidx.body + 8)
  const earliest = version === 1 ? r.u64(sidx.body + 12, "index's earliest time") : r.u32(sidx.body + 12)
  const firstOffset = version === 1 ? r.u64(sidx.body + 20, "index's first offset") : r.u32(sidx.body + 16)
  const count = r.u16(sidx.body + head - 2)
  //? a run is placed on the track's clock, and every span is read on it: an index on another
  //? clock, or one that doesn't start at 0, would put every fragment at the wrong time
  if (scale !== timescale) bad(`the index counts time in 1/${scale} s, the track in 1/${timescale} s`)
  if (earliest !== 0) bad(`the index starts at time ${earliest}, not 0`)
  if (count === 0) bad('the index lists no fragments')
  if (sidx.body + head + count * 12 > sidx.end) {
    bad(`the sidx is cut short: it lists ${count} fragments and holds ${Math.floor((sidx.end - sidx.body - head) / 12)}`)
  }

  const fragments: Fragment[] = []
  let start = sidx.end + firstOffset
  let t0 = 0
  for (let i = 0; i < count; i++) {
    const at = sidx.body + head + i * 12
    const word = r.u32(at)
    const units = r.u32(at + 4)
    //? reference_type 1 points at another sidx - an index of indexes, which isn't what deadwax
    //? writes and would need more fetching to follow
    if (word >>> 31) bad('the index points at another index (reference_type 1), not at fragments')
    const size = word & 0x7fffffff
    if (size === 0) bad(`fragment ${i + 1} of the index is 0 bytes`)
    if (units === 0) bad(`fragment ${i + 1} of the index holds no time`)
    fragments.push({ start, end: start + size, t0, units })
    start += size
    t0 += units
  }
  return fragments
}

/**
 * The head of a `wrap=fmp4` song, from its first bytes (`bytes` start at the file's byte 0).
 * `total` is the whole file's size when the answer said it (Content-Range): the index must then
 * account for every byte of it, exactly. Every fragment that starts inside the bytes given must
 * start with a moof - which is what catches an index whose sizes have drifted from the file.
 */
export function parseHead(bytes: Uint8Array, total: number | null = null): HeadParse {
  try {
    const r = new Reader(bytes)
    if (bytes.length < 8) bad(`${bytes.length} bytes is too short to be an MP4`)
    //? only a box whose end can be seen counts: a top-level box that runs "to the end of the file"
    //? ends at `total`, and nowhere knowable without it
    const fileEnd = total ?? Infinity
    //? the type is judged before the size, so what isn't an MP4 at all is named as that - a page of
    //? HTML reads as a box of a billion bytes otherwise - and then the box has to be all there
    const top = (at: number, want: string, where: string, what: string, wrong: (type: string) => string): Box => {
      if (at + 8 > bytes.length) bad(`the bytes end before ${where}`)
      const type = typeAt(bytes, at + 4)
      if (type !== want) bad(wrong(type))
      const found = r.box(at, fileEnd, where)
      if (found.end > bytes.length) bad(`the ${what} doesn't fit in the first ${bytes.length} bytes`)
      return found
    }

    const ftyp = top(0, 'ftyp', 'the first box', 'ftyp', (type) => `it doesn't start with an 'ftyp' box (it starts with '${type}')`)
    const moov = top(ftyp.end, 'moov', 'the moov', 'moov', (type) => `the ftyp is followed by '${type}', not 'moov'`)
    const sidx = top(moov.end, 'sidx', 'the sidx', 'index (sidx)', (type) => `the moov is followed by '${type}', not the index ('sidx')`)

    const { timescale, format } = readMoov(r, moov)
    const fragments = readIndex(r, sidx, timescale)
    const last = fragments[fragments.length - 1]!
    if (total !== null && last.end !== total) {
      bad(`the index accounts for ${last.end} bytes and the file is ${total}`)
    }
    for (const [i, fragment] of fragments.entries()) {
      if (fragment.start + 8 > bytes.length) break
      if (typeAt(bytes, fragment.start + 4) !== 'moof') {
        bad(`the index puts fragment ${i + 1} at byte ${fragment.start}, and there is no 'moof' there`)
      }
    }
    return {
      kind: 'head',
      head: {
        initEnd: moov.end,
        indexEnd: sidx.end,
        timescale,
        units: last.t0 + last.units,
        format,
        fragments,
      },
    }
  } catch (error) {
    if (error instanceof Bad) return { kind: 'bad', why: error.why }
    //? a read past the end of the buffer, or anything else unforeseen: still an answer, never a throw
    return { kind: 'bad', why: `unreadable (${error instanceof Error ? error.message : String(error)})` }
  }
}

/** Whether two songs have the same format: one run of the stream holds one. */
export function sameFormat(a: FlacFormat, b: FlacFormat): boolean {
  return a.sampleRate === b.sampleRate && a.channels === b.channels && a.bitsPerSample === b.bitsPerSample
}

/**
 * The init segment, bytes [0, initEnd). A COPY, not a view: a song's init is kept for as long as
 * the song is in the run (it is appended again after any abort), and a view would keep the whole
 * 256 KiB it was read from alive with it.
 */
export function initBytes(head: Fmp4Head, bytes: Uint8Array): Uint8Array {
  //? new Uint8Array(view) copies; `slice` would too on a Uint8Array, but not on a Node Buffer
  return new Uint8Array(bytes.subarray(0, head.initEnd))
}

/**
 * How many of the song's first fragments lie wholly inside its first `have` bytes - what the head's
 * own answer already holds and can be appended at once, without asking again.
 */
export function piecesInside(head: Fmp4Head, have: number): number {
  let count = 0
  while (count < head.fragments.length && head.fragments[count]!.end <= have) count++
  return count
}
