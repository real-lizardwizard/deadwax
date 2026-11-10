#!/usr/bin/env node
/**
 * The vectors the iPhone app's Normalization, plays and Info words are held to (notes/ios.md, Phase 1):
 * what the web app's own TypeScript and the server's own Python answer, written where the Swift tests read
 * them - ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/levels/:
 *
 *   levels-vectors.json  `python_gain_for`: src/loudness.py gain_for() over 44 cases (written by
 *                        ios/scripts/level_vectors.py, run here); `typescript`: lib/loudness.ts levelFor(),
 *                        levels(), signedDb() and describeLevel() (Debug), lib/resume.ts relevel(),
 *                        lib/streamWrap.ts isFlac(), lib/aboutSound.ts volumeChange(), aboutLevel() and
 *                        soundRows() (About's Sound group), lib/debugRows.ts formatWords(), app/
 *                        NormalizationChoice.tsx's four choices, and JS's own toFixed().
 *   info-vectors.json    lib/aboutRows.ts aboutRows() - Info > About's song, album and artist cards - and its
 *                        helpers (writtenBy, playedLine, labelLine), lib/format.ts trackTime() and sharedFormat().
 *   plays-vectors.json   lib/playQueue.ts countsAsPlayed(), listenedStep(), listenStarted() and listenHeard(),
 *                        lib/streamPlan.ts splitAcrossJoin(): when a play is a play.
 *
 * Three readers hold each side to the others: the Swift tests (DeadwaxCoreTests/LevelsTests.swift,
 * LevelWordsTests.swift, AboutTests.swift, PlaysTests.swift), tests/test_ios_levels.py (gain_for recomputed
 * over the committed cases), and ui/test/ioslevels.sim.cjs, which runs this script with --check: the
 * TypeScript halves are made again and compared byte for byte with the committed files, so a change to a web
 * rule the Swift ports mirror fails in tests.yml until the vectors are written again (and the Swift then fails
 * until it is ported). Never edit the files by hand.
 *
 *   node ios/scripts/export-level-vectors.cjs           write all three (runs Python: $PYTHON, else the
 *                                                       repo's .venv/bin/python, else python3)
 *   node ios/scripts/export-level-vectors.cjs --check   compare; exits 1 on any difference. Needs no Python:
 *                                                       the committed `python_gain_for` is kept as it is
 *
 * Needs ui/node_modules (npm install in ui/) and a writable TMPDIR.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURES = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'levels')
const CHECK = process.argv.includes('--check')

// ---------------------------------------------------------------- the web's TypeScript, compiled

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-level-vectors-'))
execFileSync(path.join(UI, 'node_modules', '.bin', 'tsc'), [
  'src/lib/loudness.ts', 'src/lib/aboutSound.ts', 'src/lib/aboutRows.ts', 'src/lib/resume.ts', 'src/lib/playQueue.ts',
  'src/lib/streamPlan.ts', 'src/lib/format.ts', 'src/app/NormalizationChoice.tsx',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })
//? NormalizationChoice.tsx is a component: only its NORMALIZATIONS table is read, so Preact is a stand-in
fs.mkdirSync(path.join(OUT, 'node_modules', 'preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules', 'preact', 'jsx-runtime.js'), 'exports.jsx = exports.jsxs = () => null\nexports.Fragment = null\n')
fs.writeFileSync(path.join(OUT, 'node_modules', 'preact', 'hooks.js'), 'exports.useState = (v) => [v, () => {}]\n')
fs.writeFileSync(path.join(OUT, 'node_modules', 'preact', 'index.js'), 'exports.h = () => null\n')

const load = (name) => require(path.join(OUT, name))
const L = load('lib/loudness.js')
const S = load('lib/aboutSound.js')
const W = load('lib/streamWrap.js')
const R = load('lib/resume.js')
const D = load('lib/debugRows.js')
const A = load('lib/aboutRows.js')
const F = load('lib/format.js')
const Q = load('lib/playQueue.js')
const P = load('lib/streamPlan.js')
const { NORMALIZATIONS } = load('app/NormalizationChoice.js')

/** The same numbers every run: a small LCG, so the sweeps below never change unless their rule does. */
function seeded(seed) {
  let state = seed >>> 0
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0
    return state / 4294967296
  }
}

// ---------------------------------------------------------------- levels-vectors.json: typescript

function levelsHalf() {
  const v = {}
  v.levelFor = []
  for (const setting of ['auto', 'song', 'album', 'off']) {
    for (const as of ['album', 'songs']) v.levelFor.push({ setting, as, level: L.levelFor(setting, as) ?? null })
  }
  v.relevel = []
  for (const setting of ['auto', 'song', 'album', 'off']) {
    for (const saved of ['album', 'track', null]) v.relevel.push({ setting, saved, level: R.relevel(saved ?? undefined, setting) ?? null })
  }
  const flacCases = [
    ['flac', 'audio/flac'], ['FLAC', null], [null, 'audio/x-flac'], [null, 'Audio/FLAC; charset=x'], ['mp3', 'audio/mpeg'],
    ['m4a', 'audio/mp4'], ['opus', 'audio/ogg'], [null, null], ['', 'audio/flac '], ['Flac', 'audio/mpeg'], [null, ' audio/x-flac ;x'],
    [null, ';audio/flac'], ['flac ', null], [null, 'audio/flacx'],
  ]
  const entry = (suffix, contentType, level) => ({ suffix, contentType, ...(level ? { level } : {}) })
  v.isFlac = flacCases.map(([suffix, contentType]) => ({ suffix, contentType, isFlac: W.isFlac(entry(suffix, contentType)) }))
  v.levels = []
  for (const [suffix, contentType] of flacCases.slice(0, 6)) {
    for (const level of ['album', 'track', null]) {
      for (const format of ['raw', 'mp3']) v.levels.push({ suffix, contentType, level, format, levels: L.levels(entry(suffix, contentType, level), format) })
    }
  }
  v.signedDb = [-7.42, 0.004, -0.004, 12, -0.25, 0.125, -0.125, 0.005, -0.005, 1.005, -1.005, 2.675, 0, 3.49, -0.01, 5.81, -6.57, 22]
    .map((value) => ({ value, words: L.signedDb(value) }))
  v.volumeChange = [-7.42, 2.35, -0.04, 0, -0.25, 0.25, 0.75, -1.75, 2.25, 0.05, -0.05, 0.15, -3.56, 0.95, -0.94, -3.25, 3.75, 1.45,
    12.65, -0.01, 0.04, 3.49, -6.57, 5.81]
    .map((gain) => ({ gain, words: S.volumeChange(gain) }))

  //? JS's toFixed itself, which every one of these words rounds with: at an exact tie it takes the larger
  //? digits (printf takes the even ones) - the hundredths a gain is made of hit ties all the time
  const fixed = []
  const fix = (value, digits) => fixed.push({ value, digits, fixed: value.toFixed(digits) })
  for (const value of [0.25, 3.25, 0.75, 3.75, 2.35, 0.15, 1.45, 0.05, 0.04, 12.65, 0.45, 10.25, 17.75, 0, 0.5, 1.5, 2.5, 99.95, 7.425]) fix(value, 1)
  for (const value of [0.125, 1.005, 2.675, 0.005, 0.004, 7.425, 0.015, 1.125, 0.375, 1e-7, 123456.785, 22, 0.0078125]) fix(value, 2)
  for (const value of [0.5, 1.5, 2.5, 0.49999999999999994, 3.5]) fix(value, 0)
  fix(0.0078125, 6)
  fix(-0.25, 1)
  fix(-0.004, 2)
  const random = seeded(62)
  for (let i = 0; i < 150; i++) {
    const hundredths = Math.floor(random() * 6001) - 3000
    fix(Math.abs(hundredths / 100), 1)
    fix(Math.abs(hundredths / 100 - 18), 1)
    fix(Math.abs(random() * 60 - 30), 2)
  }
  v.toFixed = fixed

  const flac = { suffix: 'flac', contentType: 'audio/flac' }
  const ans = (more = {}) => ({ level: 'album', state: 'measured', gain_db: -7.42, wanted_db: -7.42, loudness_lufs: -10.6, peak_db: -1, held: false,
    songs: 3, measured_songs: 3, why: null, ...more })
  const words = [
    ['off: no level', { ...flac }, 'raw', null],
    ['mp3 asked album', { suffix: 'mp3', contentType: 'audio/mpeg', level: 'album' }, 'raw', null],
    ['m4a asked album', { suffix: 'm4a', contentType: 'audio/mp4', level: 'album' }, 'raw', null],
    ['opus asked track, sent as mp3', { suffix: 'opus', contentType: 'audio/ogg', level: 'track' }, 'mp3', null],
    ['no suffix, not flac', { suffix: null, contentType: 'audio/mpeg', level: 'track' }, 'raw', null],
    ['flac sent as mp3', { ...flac, level: 'album' }, 'mp3', null],
    ['flac, no format said', { ...flac, level: 'album' }, null, null],
    ['flac, no answer yet', { ...flac, level: 'album' }, 'raw', null],
    ['flac by its type alone', { suffix: null, contentType: 'audio/x-flac', level: 'album' }, 'raw', ans()],
    ['album measured', { ...flac, level: 'album' }, 'raw', ans()],
    ['song measured', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', gain_db: 1.2, wanted_db: 1.2, loudness_lufs: -19.2 })],
    ['song measured -3.10', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', gain_db: -3.1, wanted_db: -3.1, loudness_lufs: -14.9 })],
    ['album -3.56 from -14.4', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -3.56, wanted_db: -3.56, loudness_lufs: -14.4, songs: 10, measured_songs: 10 })],
    ['song held', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', gain_db: 1.2, wanted_db: 2.35, held: true })],
    ['album held at -0.01, wanted +4', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -0.01, wanted_db: 4, loudness_lufs: -22, held: true })],
    ['song held at +0.04, wanted 1.5', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', gain_db: 0.04, wanted_db: 1.5, held: true })],
    ['album held, wanted null', { ...flac, level: 'album' }, 'raw', ans({ gain_db: 2, wanted_db: null, held: true })],
    ['album held at 0, wanted -2', { ...flac, level: 'album' }, 'raw', ans({ gain_db: 0, wanted_db: -2, held: true })],
    ['album unheld -0.01', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -0.01, wanted_db: -0.01, held: false })],
    ['album silent', { ...flac, level: 'album' }, 'raw', ans({ gain_db: 0, wanted_db: 0, loudness_lufs: null })],
    ['song silent', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', gain_db: 0, wanted_db: 0, loudness_lufs: null })],
    ['gain -0.25 (tie)', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -0.25, wanted_db: -0.25, loudness_lufs: -17.75 })],
    ['gain -3.25 (tie)', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -3.25, wanted_db: -3.25, loudness_lufs: -14.75 })],
    ['lufs -10.25 (tie)', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -7.75, wanted_db: -7.75, loudness_lufs: -10.25 })],
    ['lufs -0.04', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -17.96, wanted_db: -17.96, loudness_lufs: -0.04 })],
    ['lufs +1.5', { ...flac, level: 'album' }, 'raw', ans({ gain_db: -19.5, wanted_db: -19.5, loudness_lufs: 1.5 })],
    ['album measuring 1 of 3', { ...flac, level: 'album' }, 'raw', ans({ state: 'measuring', gain_db: null, measured_songs: 1 })],
    ['album measuring 7 of 12', { ...flac, level: 'album' }, 'raw', ans({ state: 'measuring', gain_db: null, songs: 12, measured_songs: 7 })],
    ['album measuring 0 of 1', { ...flac, level: 'album' }, 'raw', ans({ state: 'measuring', gain_db: null, measured_songs: 0, songs: 1 })],
    ['song measuring', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', state: 'measuring', gain_db: null })],
    ['album unmeasured', { ...flac, level: 'album' }, 'raw', ans({ state: 'unmeasured', gain_db: null })],
    ['song unmeasured', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', state: 'unmeasured', gain_db: null })],
    ['measured but no gain', { ...flac, level: 'album' }, 'raw', ans({ gain_db: null })],
    ['album plain', { ...flac, level: 'album' }, 'raw', ans({ state: 'plain', gain_db: null })],
    ['song plain', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', state: 'plain', gain_db: null })],
    ['not levelled: no libraries', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: 'deadwax is running without numpy and soundfile' })],
    ['not levelled: no cache', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: "the player's cache can't be used on this server" })],
    ['not levelled: not flac', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: "it isn't a FLAC file" })],
    ['not levelled: unreadable', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: "its file can't be read as FLAC by deadwax (20- or 32-bit)" })],
    ['not levelled: 6 channels', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: 'it has 6 channels - only mono and stereo are levelled' })],
    ['not levelled: no length', { ...flac, level: 'track' }, 'raw', ans({ level: 'track', state: 'not_levelled', gain_db: null, why: "its STREAMINFO doesn't say how long it is" })],
    ['not levelled: too large', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: 'it is 412 MiB, more than the 256 MiB a song is held in memory to repackage' })],
    ['not levelled: empty file', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: 'the file is empty' })],
    ['not levelled: first bytes', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: "its first bytes aren't a FLAC file's" })],
    ['not levelled: libsndfile', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: 'Error opening: unknown format' })],
    ['not levelled: why null', { ...flac, level: 'album' }, 'raw', ans({ state: 'not_levelled', gain_db: null, why: null })],
  ]
  v.words = words.map(([name, track, format, answer]) => ({
    name, track, format, answer, debug: L.describeLevel(track, format, answer), about: S.aboutLevel(track, format, answer),
  }))

  const queueTrack = (more = {}) => ({
    id: 'so-1', title: 'Glory Box', artist: 'Portishead', album: 'Dummy', albumId: 'al-1', coverArt: null, duration: 308,
    contentType: 'audio/flac', suffix: 'flac', sampleRate: 44100, bitDepth: 16, channels: 2, ...more,
  })
  const formats = [
    {}, { sampleRate: 192000, bitDepth: 24 }, { sampleRate: 88200, bitDepth: 24 }, { sampleRate: 22050, channels: 6 },
    { suffix: 'm4a', contentType: 'audio/mp4' }, { suffix: null, contentType: 'audio/x-flac' }, { suffix: null, contentType: 'Audio/MPEG; charset=x' },
    { suffix: null, contentType: 'video/mp4' }, { suffix: '', contentType: 'audio/flac' }, { suffix: null, contentType: null, sampleRate: 0, bitDepth: 0, channels: 0 },
    { channels: 1, bitDepth: 0 }, { sampleRate: 11025, channels: 3 }, { sampleRate: 48000, bitDepth: 32, suffix: 'wav', contentType: 'audio/x-wav' },
    { suffix: 'mp3', contentType: 'audio/mpeg', bitDepth: 0, sampleRate: 44100 }, { sampleRate: 0, bitDepth: 16, channels: 2 },
  ]
  v.formatWords = formats.map((more) => ({ track: queueTrack(more), words: D.formatWords(queueTrack(more)) }))
  const sound = [
    [{ level: 'album', sampleRate: 192000, bitDepth: 24 }, true, 'raw', ans({ gain_db: -3.56, loudness_lufs: -14.4 })],
    [{ suffix: null, contentType: null, sampleRate: 0, bitDepth: 0, channels: 0 }, false, 'raw', null],
    [{ level: 'track' }, true, 'raw', ans()],
    [{ level: 'album' }, true, 'raw', null],
    [{ level: 'album', suffix: 'mp3', contentType: 'audio/mpeg' }, true, 'raw', null],
    [{ level: 'track' }, true, 'raw', ans({ level: 'track', state: 'measuring', gain_db: null })],
  ]
  v.soundRows = sound.map(([more, gapless, format, level]) => ({
    track: queueTrack(more), gapless, format, level, rows: S.soundRows({ track: queueTrack(more), gapless, format, level }),
  }))
  v.constants = { SOUND_TITLE: S.SOUND_TITLE, LEVEL_CHECKING: S.LEVEL_CHECKING, LEVEL_NOT_KNOWN_YET: L.LEVEL_NOT_KNOWN_YET, OFF_WORDS: S.OFF_WORDS,
    NOT_KNOWN: D.NOT_KNOWN, DEFAULT_NORMALIZATION: L.DEFAULT_NORMALIZATION }
  v.settings = NORMALIZATIONS.map(({ value, label, note }) => ({ value, label, note }))
  return v
}

// ---------------------------------------------------------------- info-vectors.json: Info > About

function infoVectors() {
  const queueTrack = (more = {}) => ({
    id: 'd2t3', title: 'Wish You Were Here (Live at Wembley)', artist: 'Pink Floyd', album: 'Wish You Were Here',
    albumId: 'wywh', coverArt: 'cover-wywh', duration: 308, contentType: 'audio/flac', suffix: 'flac',
    sampleRate: 44100, bitDepth: 16, channels: 2, ...more,
  })
  const song = (id, disc, track, extra = {}) => ({ id, discNumber: disc, track, duration: 300, suffix: 'flac', artist: 'Pink Floyd', ...extra })
  const EXPERIENCE = {
    id: 'wywh', name: 'Wish You Were Here', artist: 'Pink Floyd', year: 1975, coverArt: 'cover-wywh',
    song: [...[1, 2, 3, 4, 5].map((n) => song(`d1t${n}`, 1, n)), ...[1, 2, 3, 4, 5, 6].map((n) => song(`d2t${n}`, 2, n, n === 3 ? { duration: 308 } : {}))],
    discTitles: [{ disc: 2, title: 'Unreleased Tracks' }],
  }
  const plain = { id: 'dummy', name: 'Dummy', artist: 'Portishead', year: 1994, song: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((n) => song(`t${n}`, undefined, n)) }
  const titledOne = { ...plain, song: plain.song.map((each) => ({ ...each, discNumber: 1 })), discTitles: [{ disc: 1, title: 'Live' }] }
  const straight = { ...EXPERIENCE, song: EXPERIENCE.song.map((each, i) => ({ ...each, track: i + 1 })) }
  const partial = { ...plain, song: [song('p1', undefined, 1), song('p5', undefined, 5), song('p14', undefined, 14)] }
  const stub = { id: 'dummy', name: 'Dummy', artist: 'Portishead', year: 1994, song: [song('t4', 2, 4)], partial: true }
  const various = { ...EXPERIENCE, artist: 'Various Artists', song: EXPERIENCE.song.map((each) => (each.id === 'd2t3' ? { ...each, artist: 'Pink Floyd' } : each)) }
  const WITH_LABELS = { ...EXPERIENCE, artistId: 'ar-floyd', recordLabels: [{ name: 'Harvest' }, { name: ' Harvest ' }, { name: 'EMI' }, { name: '' }, {}] }
  const DETAILS = {
    song: { id: 'd2t3', playCount: 12, displayComposer: 'Roger Waters, David Gilmour' },
    store: { present: [{ edition: 'Experience edition', year: '2011', formats: ['flac'], path: 'Pink Floyd/Wish You Were Here (1975) [Experience edition]' }] },
  }
  const present = (row, album = WITH_LABELS) => ['pressing: ' + JSON.stringify(row), queueTrack(), album, { ...DETAILS, store: { present: [{ path: 'x', ...row }] } }, false]
  const cases = [
    ['a song on the titled disc of a set', queueTrack(), EXPERIENCE, null, false],
    ['the untitled disc of a titled set', queueTrack({ id: 'd1t2' }), EXPERIENCE, null, false],
    ['an ordinary one-disc album', queueTrack({ id: 't4', album: 'Dummy', albumId: 'dummy' }), plain, null, false],
    ['a one-disc album with a title', queueTrack({ id: 't4' }), titledOne, null, false],
    ['numbered straight through the set', queueTrack({ id: 'd2t3' }), straight, null, false],
    ['a number past the album\'s count', queueTrack({ id: 'p14' }), partial, null, false],
    ['no track number', queueTrack({ id: 'x' }), { ...plain, song: [{ id: 'x', duration: 61 }] }, null, false],
    ['no length either', queueTrack({ id: 'x', duration: 0 }), { ...plain, song: [{ id: 'x' }] }, null, false],
    ['a length that rounds up', queueTrack({ id: 'x' }), { ...plain, song: [{ id: 'x', duration: 59.5, track: 2 }] }, null, false],
    ['the album not in hand', queueTrack(), null, null, false],
    ['played from a playlist\'s stub', queueTrack({ id: 't4', album: 'Dummy', albumId: 'dummy' }), stub, null, false],
    ['no year sent', queueTrack(), { ...EXPERIENCE, year: undefined }, null, false],
    ['a year of 0', queueTrack(), { ...EXPERIENCE, year: 0 }, null, false],
    ['mixed formats', queueTrack(), { ...EXPERIENCE, song: [song('a', 1, 1), song('d2t3', 1, 2, { suffix: 'mp3' })] }, null, false],
    ['a song with no suffix', queueTrack(), { ...EXPERIENCE, song: [song('a', 1, 1), song('d2t3', 1, 2, { suffix: undefined })] }, null, false],
    ['one song', queueTrack(), { ...EXPERIENCE, song: [song('d2t3', 1, 1)] }, null, false],
    ['the album\'s own cover over the song\'s', queueTrack({ coverArt: 'mf-d2t3' }), { ...EXPERIENCE, coverArt: 'al-wywh' }, null, false],
    ['the song\'s cover when the album sent none', queueTrack({ coverArt: 'mf-d2t3' }), { ...EXPERIENCE, coverArt: undefined }, null, false],
    ['a song count sent without the songs', queueTrack(), { id: 'wywh', name: 'Wish You Were Here', year: 1975, songCount: 10 }, null, false],
    ['a song count of one', queueTrack(), { id: 'wywh', name: 'Wish You Were Here', songCount: 1 }, null, false],
    ['no album id', queueTrack({ albumId: null }), null, null, false],
    ['the queue\'s album id over the album\'s', queueTrack({ albumId: 'q-id' }), { ...EXPERIENCE, id: 'a-id' }, null, false],
    ['no album named at all', queueTrack({ album: '', albumId: null }), null, null, false],
    ['the album\'s name over the queue\'s', queueTrack({ album: 'Queue name' }), { ...EXPERIENCE, name: 'Album name' }, null, false],
    ['an empty album name falls to the queue\'s', queueTrack({ album: 'Queue name' }), { ...EXPERIENCE, name: '' }, null, false],
    ['a compilation', queueTrack(), various, null, false],
    ['case and spaces are not a difference', queueTrack(), { ...EXPERIENCE, artist: ' pink floyd ' }, null, false],
    ['nobody named an artist', queueTrack({ artist: '' }), null, null, false],
    ['the album\'s artist when the song names none', queueTrack({ artist: '' }), { ...EXPERIENCE, song: [] }, null, false],
    ['the song\'s artist over the queue\'s', queueTrack({ artist: 'Queue artist' }), { ...EXPERIENCE, song: EXPERIENCE.song.map((each) => (each.id === 'd2t3' ? { ...each, artist: 'Song artist' } : each)) }, null, false],
    ['filled in, with the folder', queueTrack(), WITH_LABELS, DETAILS, true],
    ['filled in, without the folder', queueTrack(), WITH_LABELS, DETAILS, false],
    present({ edition: '', year: '1975', formats: ['flac'] }),
    present({ edition: null, year: '1975-09-12', formats: ['FLAC'] }),
    present({ edition: 'Experience edition', year: '1975', formats: ['flac'] }),
    present({ edition: '', year: '2011', formats: ['flac'] }),
    present({ edition: '', year: '1975', formats: ['flac', 'mp3'] }),
    present({ edition: '', year: '1975', formats: ['flac'] }, { ...WITH_LABELS, year: undefined }),
    present({ edition: '  ', year: '19x5', formats: [] }),
    ['two folders of a set', queueTrack(), EXPERIENCE, { store: { present: [{ path: 'A/Disc 1', edition: '', year: '1975', formats: ['flac'] }, { path: 'A/Disc 2', edition: '', year: '1975', formats: ['flac', 'mp3'] }, { path: '' }] } }, true],
    ['the song\'s details are this song\'s only', queueTrack(), WITH_LABELS, { ...DETAILS, song: { id: 'other', playCount: 99, displayComposer: 'X' } }, false],
    ['the album\'s count until Navidrome answers', queueTrack(), { ...WITH_LABELS, song: WITH_LABELS.song.map((each) => (each.id === 'd2t3' ? { ...each, playCount: 1 } : each)) }, null, false],
    ['Navidrome\'s answer over it, even one saying fewer', queueTrack(), { ...WITH_LABELS, song: WITH_LABELS.song.map((each) => (each.id === 'd2t3' ? { ...each, playCount: 5 } : each)) }, { song: { id: 'd2t3' } }, false],
    ['nothing sent', queueTrack(), EXPERIENCE, { song: { id: 'd2t3', playCount: 0, displayComposer: ' ' }, store: { present: [] }, artist: null, facts: null }, true],
    ['writers from the contributors', queueTrack(), EXPERIENCE, { song: { id: 'd2t3', contributors: [{ role: 'Composer', artist: { name: ' Geoff Barrow ' } }, { role: 'composer', artist: { name: 'Geoff Barrow' } }, { role: 'lyricist', artist: { name: 'Beth Gibbons' } }, { role: 'composer', artist: { name: 'Adrian Utley' } }, { role: 'composer' }] } }, false],
    ['the album\'s song\'s writers before Navidrome answers', queueTrack(), { ...EXPERIENCE, song: EXPERIENCE.song.map((each) => (each.id === 'd2t3' ? { ...each, displayComposer: 'Roger Waters' } : each)) }, null, false],
    ['a disc number of 0 is disc 1', queueTrack({ id: 'z2' }), { ...plain, song: [song('z1', 0, 1), song('z2', 2, 1)], discTitles: [{ disc: '2', title: ' Bonus ' }, { disc: 2, title: 'Second' }, { disc: 0, title: 'None' }, { disc: 'x', title: 'Bad' }, { disc: 1, title: '' }] }, null, false],
    ['a disc title given as a string disc', queueTrack({ id: 'z1' }), { ...plain, song: [song('z1', 1, 1), song('z2', 1, 2)], discTitles: [{ disc: '1', title: 'Live' }] }, null, false],
    ['a fractional track number', queueTrack({ id: 'z1' }), { ...plain, song: [song('z1', 1, 2.5), song('z2', 1, 2)] }, null, false],
  ]
  const aboutRows = cases.map(([name, track, album, details, folders]) => {
    const about = A.aboutRows(track, album, details, false, folders)
    //? Phase 1's artist card is the name (and the album artist's note): its link, facts and count are Phase 4's
    const artist = about.artist ? { name: about.artist.name, note: about.artist.note } : null
    return { name, track, album, details, folders, about: { song: about.song, album: about.album, artist } }
  })
  return {
    aboutRows,
    writtenBy: [
      { displayComposer: ' Geoff Barrow ' }, { contributors: [{ role: 'composer', artist: { name: 'A' } }, { role: 'lyricist', artist: { name: 'B' } }, { role: 'Composer', artist: { name: 'A' } }] },
      null, { displayComposer: '', contributors: [{ role: 'COMPOSER', artist: { name: 'C' } }, { role: 'composer', artist: { name: 'D' } }] }, { contributors: [] }, {},
    ].map((song) => ({ song, words: A.writtenBy(song) })),
    playedLine: [1, 2, 0, null, 2.5, -1, 12, 1e3].map((count) => ({ count, words: A.playedLine(count) })),
    labelLine: [[{ name: 'Harvest' }], [{ name: 'Go! Beat' }, { name: 'London' }, { name: 'Go! Beat ' }], [{ name: '' }], null, [], [{}, { name: ' EMI ' }]]
      .map((labels) => ({ labels, words: A.labelLine(labels) })),
    trackTime: [0, 61, 308, 59.5, 0.4, 0.5, 3600.5, 125.49, null, 1.5, 7199.6].map((seconds) => ({ seconds, words: F.trackTime(seconds) })),
    sharedFormat: [[{ suffix: 'flac' }, { suffix: 'FLAC' }], [{ suffix: 'flac' }, {}], [], [{ suffix: 'mp3' }], [{}], [{ suffix: '' }, { suffix: '' }]]
      .map((songs) => ({ songs, format: F.sharedFormat(songs) })),
  }
}

// ---------------------------------------------------------------- plays-vectors.json: when a play is a play

function playsVectors() {
  const counts = []
  for (const duration of [0, 29.9, 30, 30.0001, 31, 60, 200, 479.9, 480, 481, 1200, 7200]) {
    for (const listened of [0, 15, 29.99, 30, 99, 99.999, 100, 120, 239.99, 240, 500]) counts.push({ listened, duration, played: Q.countsAsPlayed(listened, duration) })
  }
  const steps = [
    [10, 10.25, 0.25, 1, false], [20, 20.5, 0.25, 1, false], [10, 150, 0.25, 1, true], [150, 10, 0.25, 1, false], [10, 150, 0.25, 1, false],
    [10, 12, 0, 1, false], [40, 45, 5, 1, false], [20, 24, 1, 4, false], [20, 24, 1, 1, false], [20, 24, 1, 0, false], [10, 18, 4, 2, false],
    [10, 11, 4, 0.25, false], [10, 100, 4, 0.25, false], [10, 100, 4, 2, false], [5, 5, 1, 1, false], [5, 6, -3, 1, false], [0, 0.4, 0.5, 1, false],
    [100, 100.5, 0.5, -1, false], [0, 300, 3600, 1, false],
  ]
  const listenedStep = steps.map(([previous, now, elapsed, rate, seeked]) => ({ previous, now, elapsed, rate, seeked, step: Q.listenedStep({ previous, now, elapsed, rate, seeked }) }))
  const joins = [
    [198.7, 200, 0.3, 1.6, 1, false], [198.7, 200, 0.3, 1.6, 1, true], [199, 200, 2, 1, 1, false], [190, 200, 5, 1, 1, false], [199, 200, 3, 1, 2, false],
    [199, 200, 2, 1, 0, false], [199, 200, 2, -3, 1, false], [200.2, 200, 0.4, 0.5, 1, false], [198.7, 200, -0.1, 1.6, 1, false], [0, 0, 1, 1, 1, false],
    [150, 200, 30, 60, 1, false],
  ]
  const splitAcrossJoin = joins.map(([previous, oldLength, now, elapsed, rate, seeked]) => ({ previous, oldLength, now, elapsed, rate, seeked,
    split: P.splitAcrossJoin({ previous, oldLength, now, elapsed, rate, seeked }) }))
  //? a listen's life, a step at a time: started (ms since the epoch), heard (seconds of a song this long)
  const scripts = [
    [['started', 11000], ['started', 12000], ['heard', 50, 200], ['heard', 49.5, 200], ['heard', 0.5, 200], ['heard', 100, 200]],
    [['started', 5000], ['heard', 60, 200], ['heard', 60, 200]],
    [['started', 1], ['heard', 99, 200]],
    [['started', 1], ['heard', 30, 30], ['heard', 30, 30]],
    [['heard', 150, 200], ['started', 7]],
    [['started', 3], ['heard', 239, 1200], ['heard', 1, 1200], ['heard', 500, 1200]],
  ]
  const listens = scripts.map((steps) => {
    let listen = Q.NEW_LISTEN
    const after = steps.map(([kind, a, b]) => {
      if (kind === 'started') {
        const { listen: next, nowPlaying } = Q.listenStarted(listen, a)
        listen = next
        return { kind, now: a, listen, nowPlaying }
      }
      const { listen: next, submit } = Q.listenHeard(listen, a, b)
      listen = next
      return { kind, seconds: a, duration: b, listen, submit }
    })
    return { steps: after }
  })
  return { constants: { LISTEN_SLACK_SECONDS: Q.LISTEN_SLACK_SECONDS, RESTART_AFTER_SECONDS: Q.RESTART_AFTER_SECONDS, NEW_LISTEN: Q.NEW_LISTEN },
    countsAsPlayed: counts, listenedStep, splitAcrossJoin, listens }
}

// ---------------------------------------------------------------- the server's half, and writing

function pythonHalf() {
  const venv = path.join(REPO, '.venv', 'bin', 'python')
  const python = process.env.PYTHON || (fs.existsSync(venv) ? venv : 'python3')
  const text = execFileSync(python, [path.join(__dirname, 'level_vectors.py')], { cwd: REPO, encoding: 'utf8' })
  return JSON.parse(text)
}

const say = (value) => JSON.stringify(value, null, 1) + '\n'
const files = {
  'levels-vectors.json': (committed) => say({ python_gain_for: committed ? committed.python_gain_for : pythonHalf(), typescript: levelsHalf() }),
  'info-vectors.json': () => say(infoVectors()),
  'plays-vectors.json': () => say(playsVectors()),
}

let failed = false
for (const [name, make] of Object.entries(files)) {
  const where = path.join(FIXTURES, name)
  if (CHECK) {
    const committedText = fs.existsSync(where) ? fs.readFileSync(where, 'utf8') : null
    const made = committedText === null ? null : make(JSON.parse(committedText))
    const same = made !== null && made === committedText
    if (!same) failed = true
    console.log(`  ${same ? 'PASS' : 'FAIL'}  ${name} is what the web's TypeScript answers today` +
      (same ? '' : ' - run node ios/scripts/export-level-vectors.cjs, then port the change to the Swift (DeadwaxCore) and see its tests pass'))
  } else {
    fs.mkdirSync(FIXTURES, { recursive: true })
    fs.writeFileSync(where, make(null))
    console.log(`wrote ${path.relative(REPO, where)}`)
  }
}
fs.rmSync(OUT, { recursive: true, force: true })
if (failed) process.exit(1)
