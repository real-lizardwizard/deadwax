/**
 * The player's Normalization on the page (2.0.0-player.62): lib/loudness.ts and the addresses player/api.ts
 * builds from a queue entry's level, compiled with the repo's TypeScript.
 *
 * What it pins:
 *  - levelFor() across the whole table: Automatic levels what was queued as an album by album and everything
 *    else song by song; By song and By album whatever was queued; Off asks for no level.
 *  - levelled(): under Off the SAME array of the same objects - so Off queues exactly what was queued before the
 *    setting existed - and otherwise copies, each with its level, the originals untouched.
 *  - levels(): a level, a FLAC, the file as it is - never an MP3, an Opus, a transcode; unlevelled() and
 *    levelParam(); describeLevel()'s words.
 *  - THE ADDRESSES: for every kind of song (FLAC 16/44.1, 24/96, 24/192, one with no rate, an MP3, an Opus) in
 *    Chromium and on an iPhone, under both caps, an entry with no level gets exactly the stream, fragment and
 *    window addresses deadwax's page built before levels existed - a table recorded from 2.0.0-player.61's own
 *    player/api.ts, frozen here. A levelled FLAC asks `wrap=mp4` in Chromium too, its `&level=` last; an MP3, an
 *    Opus or a transcode never carries one.
 *
 * Run it with:  node ui/test/loudness.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-loudness-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/loudness.ts', 'src/player/api.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/loudness.js'))
const api = require(path.join(OUT, 'player/api.js'))
const { resamples } = require(path.join(OUT, 'lib/streamWrap.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const DOT = String.fromCharCode(0xb7)

const base = { title: 't', artist: 'a', album: 'b', albumId: 'al', coverArt: null, duration: 1, channels: 2 }
const TRACKS = {
  'flac 16/44.1': { id: 'cd', contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16 },
  'flac 24/96': { id: 'h96', contentType: 'audio/flac', suffix: 'flac', sampleRate: 96000, bitDepth: 24 },
  'flac 24/192': { id: 'h192', contentType: 'audio/flac', suffix: 'flac', sampleRate: 192000, bitDepth: 24 },
  'mp3': { id: 'mp3', contentType: 'audio/mpeg', suffix: 'mp3', sampleRate: 44100, bitDepth: 0 },
  'opus': { id: 'op', contentType: 'audio/ogg', suffix: 'opus', sampleRate: 48000, bitDepth: 0 },
  'flac, no rate': { id: 'nr', contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0 },
}
//? Chromium plays everything and wraps nothing; an iPhone wraps FLAC in an MP4 and can't play Opus (a transcode)
const BROWSERS = {
  chromium: { wraps: false, canPlay: () => true },
  iphone: { wraps: true, canPlay: (type) => !/opus|vorbis/.test(type) },
}

//? every address a window is asked at, as the page's fetch sends it
const asked = []
globalThis.fetch = async (address) => {
  asked.push(address)
  return { ok: true, status: 200, headers: { get: () => '0/1/44100' }, arrayBuffer: async () => new ArrayBuffer(0), json: async () => ({}), text: async () => '{}' }
}

//? 2.0.0-player.61's addresses, recorded from its own player/api.ts (git 3458dbf) by the same matrix: [stream,
//? fragment, window] - what an entry with no level must still be asked at, string for string
const BEFORE = {
  "flac 16/44.1 | chromium | 48000": ["/deadwax/navidrome/stream/cd?format=raw", "/deadwax/navidrome/stream/cd?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/cd?at=12&seconds=40"],
  "flac 16/44.1 | chromium | original": ["/deadwax/navidrome/stream/cd?format=raw", "/deadwax/navidrome/stream/cd?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/cd?at=12&seconds=40"],
  "flac 16/44.1 | iphone | 48000": ["/deadwax/navidrome/stream/cd?format=raw&wrap=mp4", "/deadwax/navidrome/stream/cd?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/cd?at=12&seconds=40"],
  "flac 16/44.1 | iphone | original": ["/deadwax/navidrome/stream/cd?format=raw&wrap=mp4", "/deadwax/navidrome/stream/cd?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/cd?at=12&seconds=40"],
  "flac 24/96 | chromium | 48000": ["/deadwax/navidrome/stream/h96?format=raw&wrap=mp4&max_rate=48000", "/deadwax/navidrome/stream/h96?format=raw&wrap=fmp4&max_rate=48000", "/deadwax/navidrome/scrub/h96?at=12&seconds=40&max_rate=48000"],
  "flac 24/96 | chromium | original": ["/deadwax/navidrome/stream/h96?format=raw", "/deadwax/navidrome/stream/h96?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/h96?at=12&seconds=40"],
  "flac 24/96 | iphone | 48000": ["/deadwax/navidrome/stream/h96?format=raw&wrap=mp4&max_rate=48000", "/deadwax/navidrome/stream/h96?format=raw&wrap=fmp4&max_rate=48000", "/deadwax/navidrome/scrub/h96?at=12&seconds=40&max_rate=48000"],
  "flac 24/96 | iphone | original": ["/deadwax/navidrome/stream/h96?format=raw&wrap=mp4", "/deadwax/navidrome/stream/h96?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/h96?at=12&seconds=40"],
  "flac 24/192 | chromium | 48000": ["/deadwax/navidrome/stream/h192?format=raw&wrap=mp4&max_rate=48000", "/deadwax/navidrome/stream/h192?format=raw&wrap=fmp4&max_rate=48000", "/deadwax/navidrome/scrub/h192?at=12&seconds=40&max_rate=48000"],
  "flac 24/192 | chromium | original": ["/deadwax/navidrome/stream/h192?format=raw", "/deadwax/navidrome/stream/h192?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/h192?at=12&seconds=40"],
  "flac 24/192 | iphone | 48000": ["/deadwax/navidrome/stream/h192?format=raw&wrap=mp4&max_rate=48000", "/deadwax/navidrome/stream/h192?format=raw&wrap=fmp4&max_rate=48000", "/deadwax/navidrome/scrub/h192?at=12&seconds=40&max_rate=48000"],
  "flac 24/192 | iphone | original": ["/deadwax/navidrome/stream/h192?format=raw&wrap=mp4", "/deadwax/navidrome/stream/h192?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/h192?at=12&seconds=40"],
  "mp3 | chromium | 48000": ["/deadwax/navidrome/stream/mp3?format=raw", "/deadwax/navidrome/stream/mp3?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/mp3?at=12&seconds=40"],
  "mp3 | chromium | original": ["/deadwax/navidrome/stream/mp3?format=raw", "/deadwax/navidrome/stream/mp3?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/mp3?at=12&seconds=40"],
  "mp3 | iphone | 48000": ["/deadwax/navidrome/stream/mp3?format=raw", "/deadwax/navidrome/stream/mp3?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/mp3?at=12&seconds=40"],
  "mp3 | iphone | original": ["/deadwax/navidrome/stream/mp3?format=raw", "/deadwax/navidrome/stream/mp3?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/mp3?at=12&seconds=40"],
  "opus | chromium | 48000": ["/deadwax/navidrome/stream/op?format=raw", "/deadwax/navidrome/stream/op?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/op?at=12&seconds=40"],
  "opus | chromium | original": ["/deadwax/navidrome/stream/op?format=raw", "/deadwax/navidrome/stream/op?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/op?at=12&seconds=40"],
  "opus | iphone | 48000": ["/deadwax/navidrome/stream/op?format=mp3", "/deadwax/navidrome/stream/op?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/op?at=12&seconds=40"],
  "opus | iphone | original": ["/deadwax/navidrome/stream/op?format=mp3", "/deadwax/navidrome/stream/op?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/op?at=12&seconds=40"],
  "flac, no rate | chromium | 48000": ["/deadwax/navidrome/stream/nr?format=raw", "/deadwax/navidrome/stream/nr?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/nr?at=12&seconds=40"],
  "flac, no rate | chromium | original": ["/deadwax/navidrome/stream/nr?format=raw", "/deadwax/navidrome/stream/nr?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/nr?at=12&seconds=40"],
  "flac, no rate | iphone | 48000": ["/deadwax/navidrome/stream/nr?format=raw&wrap=mp4", "/deadwax/navidrome/stream/nr?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/nr?at=12&seconds=40"],
  "flac, no rate | iphone | original": ["/deadwax/navidrome/stream/nr?format=raw&wrap=mp4", "/deadwax/navidrome/stream/nr?format=raw&wrap=fmp4", "/deadwax/navidrome/scrub/nr?at=12&seconds=40"],
}

;(async () => {
  console.log('\nthe rule: what each setting levels, by how the songs were queued')
  {
    const table = ['auto', 'song', 'album', 'off'].map((setting) => [setting, L.levelFor(setting, 'album') ?? null, L.levelFor(setting, 'songs') ?? null])
    check('Automatic: an album by album, songs by song; By song and By album whatever; Off nothing', table,
      [['auto', 'album', 'track'], ['song', 'track', 'track'], ['album', 'album', 'album'], ['off', null, null]])
    check('the default is Automatic', L.DEFAULT_NORMALIZATION, 'auto')
  }

  console.log('\nlevelled(): Off queues exactly what it always did')
  {
    const tracks = [{ ...base, ...TRACKS['flac 16/44.1'] }, { ...base, ...TRACKS.mp3 }]
    const off = L.levelled(tracks, 'off', 'album')
    check('under Off: the same array, the same objects, nothing added', [off === tracks, off[0] === tracks[0], off[1] === tracks[1], 'level' in off[0]], [true, true, true, false])
    const auto = L.levelled(tracks, 'auto', 'album')
    check('otherwise copies, each with its level - the originals untouched',
      [auto === tracks, auto[0] === tracks[0], auto.map((track) => track.level), 'level' in tracks[0], auto[0].id], [false, false, ['album', 'album'], false, 'cd'])
    check('...queued as songs under Automatic: by song', L.levelled(tracks, 'auto', 'songs').map((track) => track.level), ['track', 'track'])
    check('atLevel() with no level: the same array', L.atLevel(tracks, undefined) === tracks, true)
  }

  console.log('\nlevels(): only a FLAC sent as it is, and only with a level')
  {
    const flac = { ...base, ...TRACKS['flac 16/44.1'] }
    check('a FLAC: levelled with a level, as it is; not as a transcode; not without a level',
      [L.levels({ ...flac, level: 'album' }, 'raw'), L.levels({ ...flac, level: 'track' }, 'mp3'), L.levels(flac, 'raw')], [true, false, false])
    check('never an MP3, an Opus or an AAC', ['mp3', 'opus'].map((kind) => L.levels({ ...base, ...TRACKS[kind], level: 'album' }, 'raw'))
      .concat(L.levels({ ...base, id: 'aac', contentType: 'audio/mp4', suffix: 'm4a', level: 'album' }, 'raw')), [false, false, false])
    check('...a FLAC known only by its type', L.levels({ ...base, id: 'x', contentType: 'audio/x-flac', suffix: null, level: 'track' }, 'raw'), true)
    const levelledTrack = { ...flac, level: 'album' }
    const plain = L.unlevelled(levelledTrack)
    check('unlevelled(): the track without its level - and the very object when it has none',
      [plain === levelledTrack, 'level' in plain, plain.id, L.unlevelled(flac) === flac, levelledTrack.level], [false, false, 'cd', true, 'album'])
    check('levelParam(): last in the query, or nothing', [L.levelParam(levelledTrack, 'raw'), L.levelParam({ ...flac, level: 'track' }, 'raw'), L.levelParam(flac, 'raw'),
      L.levelParam({ ...base, ...TRACKS.mp3, level: 'album' }, 'raw')], ['&level=album', '&level=track', '', ''])
  }

  console.log('\nthe addresses: an entry with no level is asked where it always was')
  {
    const now = {}
    for (const [name, t] of Object.entries(TRACKS)) for (const [browser, b] of Object.entries(BROWSERS)) for (const cap of ['48000', 'original']) {
      const track = { ...base, ...t }
      asked.length = 0
      await api.scrubWindow(track.id, 12, 40, undefined, resamples(track, cap, 'raw') ? 48000 : null)
      now[`${name} | ${browser} | ${cap}`] = [api.streamUrl(track, b.canPlay, b.wraps, cap), api.fragmentedUrl(track, cap), asked[0]]
    }
    const differ = Object.keys(BEFORE).filter((key) => JSON.stringify(now[key]) !== JSON.stringify(BEFORE[key]))
    check(`every one of the ${Object.keys(BEFORE).length} cases the same three strings as 2.0.0-player.61's`, [Object.keys(now).length, differ], [Object.keys(BEFORE).length, []])
  }

  console.log('\nthe addresses: a levelled entry')
  {
    const at = (name, level, browser = 'chromium', cap = 'original') => {
      const b = BROWSERS[browser]
      return api.streamUrl({ ...base, ...TRACKS[name], level }, b.canPlay, b.wraps, cap)
    }
    check('a levelled CD FLAC in Chromium: in deadwax\'s MP4 - a copy it made - its level last', at('flac 16/44.1', 'album'),
      '/deadwax/navidrome/stream/cd?format=raw&wrap=mp4&level=album')
    check('...on an iPhone the same address', at('flac 16/44.1', 'album', 'iphone'), '/deadwax/navidrome/stream/cd?format=raw&wrap=mp4&level=album')
    check('...resampled and levelled: the cap, then the level', at('flac 24/192', 'track', 'chromium', '48000'),
      '/deadwax/navidrome/stream/h192?format=raw&wrap=mp4&max_rate=48000&level=track')
    check('an MP3 or an Opus never carries a level - nor a song the iPhone gets as a transcode',
      [at('mp3', 'album'), at('opus', 'album'), at('opus', 'album', 'iphone')],
      ['/deadwax/navidrome/stream/mp3?format=raw', '/deadwax/navidrome/stream/op?format=raw', '/deadwax/navidrome/stream/op?format=mp3'])
    asked.length = 0
    await api.scrubWindow('cd', 12, 40, undefined, null, 'album')
    await api.scrubWindow('h192', 12, 40, undefined, 48000, 'track')
    check('a window at its song\'s level, last', asked, ['/deadwax/navidrome/scrub/cd?at=12&seconds=40&level=album', '/deadwax/navidrome/scrub/h192?at=12&seconds=40&max_rate=48000&level=track'])
    asked.length = 0
    await api.levelOf('cd', 'album', null)
    await api.levelOf('h192', 'track', 48000)
    check('Info\'s ask', asked, ['/deadwax/navidrome/level/cd?level=album', '/deadwax/navidrome/level/h192?level=track&max_rate=48000'])
  }

  console.log('\ndescribeLevel(): Info\'s words')
  {
    const flac = { ...base, ...TRACKS['flac 16/44.1'] }
    const answer = (more = {}) => ({ level: 'album', state: 'measured', gain_db: -7.42, wanted_db: -7.42, loudness_lufs: -10.6, peak_db: -1, held: false, songs: 3, measured_songs: 3, why: null, ...more })
    check('the words, state by state', [
      L.describeLevel(flac, 'raw', null),
      L.describeLevel({ ...base, ...TRACKS.mp3, level: 'album' }, 'raw', null),
      L.describeLevel({ ...flac, level: 'album' }, 'raw', null),
      L.describeLevel({ ...flac, level: 'album' }, 'raw', answer()),
      L.describeLevel({ ...flac, level: 'track' }, 'raw', answer({ level: 'track', gain_db: 1.2, wanted_db: 2.35, held: true })),
      L.describeLevel({ ...flac, level: 'album' }, 'raw', answer({ state: 'measuring', gain_db: null, measured_songs: 1 })),
      L.describeLevel({ ...flac, level: 'album' }, 'raw', answer({ state: 'unmeasured', gain_db: null })),
      L.describeLevel({ ...flac, level: 'album' }, 'raw', answer({ state: 'plain', gain_db: null })),
      L.describeLevel({ ...flac, level: 'album' }, 'raw', answer({ state: 'not_levelled', gain_db: null, why: "the player's cache can't be used on this server" })),
    ], [
      'Off', 'Not levelled - MP3 songs play as they are', "Asked for; deadwax hasn't said yet", `Album, -7.42 dB ${DOT} the album at -10.6 LUFS`,
      `Song, +1.20 dB ${DOT} held there by its peak (it wanted +2.35)`, 'Measuring its album… (1 of 3 songs)',
      'Not measured yet - it played as it is this time', 'Played as it is this time - its album was still being measured',
      "Not levelled - the player's cache can't be used on this server",
    ])
    check('a gain as it is said: its sign always, two places, never a minus zero', [L.signedDb(-7.42), L.signedDb(0.004), L.signedDb(-0.004), L.signedDb(12)],
      ['-7.42 dB', '+0.00 dB', '+0.00 dB', '+12.00 dB'])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()
