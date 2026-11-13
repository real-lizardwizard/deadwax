#!/usr/bin/env node
/**
 * A recording of the record's sound made by the web's own TypeScript (notes/ios-specs/turntable.md 6.3, slice 4), for
 * the Swift replay (DeadwaxCore's DeckReplay.web) to be held to: player/deck.ts's Deck, real, driven through
 * ui/test/deckHarness.cjs (deck.sim's own harness) the way ios/scripts/export-deck-vectors.cjs drives it, its voice the
 * main-thread one (lib/deckVoice.ts on the page - a Safari's on plain http), and its own recorder (recordDeckSound) -
 * the tap fed what the voice's node wrote, block for block, as a ScriptProcessorNode hanging off it would be. The file
 * is deck.ts's own text, byte for byte; nothing is added to it.
 *
 * The window is the exporter's integer recipe (export-deck-vectors.cjs recipeChannel, 'sweep', seed 5, two channels,
 * as long as the window's bytes say), so the Swift makes the same samples without them being committed. Its decode
 * is held until the recording is under way, so the window's message is in the file - a replay is from rest.
 *
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/recording/web-script.json and web-script.made.json (who made
 * it, the sources' sha256 - tests/test_ios_deck_recording.py fails when one changes, until this is run again).
 *
 *   node ios/scripts/export-deck-recording.cjs           write them (on the deck fixtures' maker, Node 20.12.2)
 *   node ios/scripts/export-deck-recording.cjs --check   write nothing; exit 1 when the recording would differ
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FOLDER = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'recording')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-deck-recording-'))

const SOURCES = ['src/lib/platter.ts', 'src/lib/deckVoice.ts', 'src/player/deck.ts', 'src/lib/turntable.ts', 'src/lib/deckClock.ts']
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES,
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex')
const MADE_FROM = [...SOURCES.map((file) => `ui/${file}`), 'ui/test/deckHarness.cjs']
  .map((file) => [file, sha256(fs.readFileSync(path.join(REPO, file), 'utf8'))])

/** export-deck-vectors.cjs recipeChannel's 'sweep': a triangle whose step rises every 128 samples, in integer steps. */
function sweep(seed, ch, length) {
  const out = new Float32Array(length)
  let phase = 0
  for (let i = 0; i < length; i++) {
    phase = (phase + 1 + ((i >> 7) % 600) * (ch + 1)) & 0xffff
    const v = phase < 32768 ? phase * 2 - 32768 : (65535 - phase) * 2 - 32767
    out[i] = v / 32768
  }
  return out
}
const SEED = 5

async function make() {
  const H = require(path.join(UI, 'test', 'deckHarness.cjs')).install(OUT)
  //? the main-thread voice, as a page on plain http has it (no AudioWorklet)
  H.noWorklet = true
  globalThis.isSecureContext = false
  globalThis.navigator = { userAgent: 'deadwax export-deck-recording' }
  const fixedNow = Date.parse('2026-11-13T12:00:00.000Z')
  const RealDate = Date
  globalThis.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [fixedNow])) }
    static now() { return fixedNow }
  }
  let held = null
  H.decodeWith = (bytes, done) => {
    const length = Math.round((bytes.byteLength / H.BYTES_A_SECOND) * 48000)
    const channels = [sweep(SEED, 0, length), sweep(SEED, 1, length)]
    held = () => done({ numberOfChannels: 2, sampleRate: 48000, length, getChannelData: (c) => channels[c] })
  }
  let captured = null
  globalThis.URL.createObjectURL = (blob) => { captured = blob; return 'blob:deck-recording' }
  const { recordDeckSound } = H.deckModule
  const { SECONDS_PER_TURN } = require(path.join(OUT, 'lib/turntable.js'))

  const host = H.fakeHost()
  const deck = new H.Deck(host)
  deck.setShowing(true)
  deck.songChanged(host.song().id)
  H.wakeDeckAudio()
  for (let i = 0; i < 4; i++) await H.settle()
  const voiceNode = H.scripts.at(-1)
  H.pump(voiceNode, 1)
  for (let i = 0; i < 4; i++) await H.settle()
  if (!held) throw new Error('the window was never decoded')

  //? the recording, then the window - so its message is in the file
  const problem = recordDeckSound(1.5)
  if (problem) throw new Error(`the recording didn't start: ${problem}`)
  const tap = H.scripts.at(-1)
  held()
  for (let i = 0; i < 4; i++) await H.settle()

  //? the tap: what the voice's node wrote, 4,096 frames a block, each at the playback time of its first frame
  const pending = [[], []]
  let pendingTime = null
  const feed = (filled) => {
    for (const { channels, playbackTime } of filled) {
      if (pendingTime === null) pendingTime = playbackTime
      for (let c = 0; c < 2; c++) pending[c].push(...channels[c])
      while (pending[0].length >= 4096) {
        const block = [Float32Array.from(pending[0].splice(0, 4096)), Float32Array.from(pending[1].splice(0, 4096))]
        tap.onaudioprocess?.({ inputBuffer: { numberOfChannels: 2, getChannelData: (c) => block[c] }, playbackTime: pendingTime })
        pendingTime += 4096 / 48000
      }
    }
  }
  const context = voiceNode.context
  const startClock = H.clock
  const startContext = context.currentTime
  //? the browser keeps the voice's blocks coming with the clock
  const keepUp = () => {
    while (context.currentTime + 1024 / 48000 <= startContext + (H.clock - startClock) / 1000) feed(H.pump(voiceNode, 1))
  }

  //? a press of the playing record, a scratch back and forth at 120 Hz for 0.6 s, and a let-go - the rest of the 1.5 s
  //? the record running back to speed and the song handed back
  deck.pressed(H.clock)
  deck.takeOver()
  const from = host.at
  const turnedAt = (ms) => 1.2 * Math.sin((2 * Math.PI * 2 * ms) / 1000) - (ms / 1000) * 0.8
  for (let ms = 16; ms <= 600; ms += 16) {
    //? two samples a frame, 8 ms apart, as a phone's coalesced touches come
    for (const back of [8, 0]) {
      const turned = turnedAt(ms - back)
      deck.hand(H.clock + 16 - back, turned, from + (turned / (2 * Math.PI)) * SECONDS_PER_TURN)
    }
    H.runFrames(1)
    keepUp()
    await H.settle()
  }
  deck.release(H.clock, 'up')
  for (let frame = 0; frame < 120 && !captured; frame++) {
    H.runFrames(1)
    host.moveTo(host.at + 0.016)
    keepUp()
    await H.settle()
  }
  if (!captured) throw new Error('the recording never finished')
  deck.destroy()
  return Buffer.from(await captured.arrayBuffer())
}

make().then((file) => {
  const made = JSON.stringify({
    made_on: { node: process.version, platform: process.platform, arch: process.arch },
    made_with: [['ios/scripts/export-deck-recording.cjs', sha256(fs.readFileSync(__filename, 'utf8'))]],
    made_from: MADE_FROM,
    window: { recipe: 'sweep', seed: SEED, channels: 2 },
  }, null, 1) + '\n'
  const at = path.join(FOLDER, 'web-script.json')
  if (CHECK) {
    const same = fs.existsSync(at) && Buffer.compare(fs.readFileSync(at), file) === 0
    console.log(same ? 'web-script.json: the same' : 'web-script.json: DIFFERS - run without --check, and check the Swift replay')
    process.exit(same ? 0 : 1)
  }
  fs.mkdirSync(FOLDER, { recursive: true })
  fs.writeFileSync(at, file)
  fs.writeFileSync(path.join(FOLDER, 'web-script.made.json'), made)
  const parsed = JSON.parse(file.toString('utf8'))
  console.log(`web-script.json: ${file.length} bytes, ${parsed.audio.frames} frames, ${parsed.messages.length} messages, ${parsed.heard.length} reports`)
}).catch((error) => {
  console.error(error)
  process.exit(1)
})
