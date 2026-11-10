#!/usr/bin/env node
/**
 * The Library's vectors for the iPhone app (app 0.2, Phase 1): what the web app's own TypeScript answers, written as
 * fixtures the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore replay (Tests/DeadwaxCoreTests/Library*.swift) -
 * so the phone sorts, heads, finds and indexes a library exactly as the web does, and a change to the web's rules
 * shows up as a fixture that no longer matches.
 *
 * Compiles, as the sims do, ui/src/lib/shelves.ts (and lib/owned.ts's foldName), lib/myLibrary.ts, lib/appFrame.ts,
 * lib/yourLibrary.ts, app/albumIndex.ts and app/useMyLibrary.ts, and runs the last two as they are against stand-ins
 * for the network (as ui/test/whose.sim.cjs and mylibrary.sim.cjs do). Writes, under
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/library/:
 *
 *   fold.json     foldName, findText and the header initial of ~4,000 names (fixed awkward ones, and seeded random
 *                 strings from many scripts, marks, ligatures, spaces and brackets)
 *   dates.json    Date.parse and monthLabel of ~1,150 date strings in four time zones (UTC, New York, London, Lord
 *                 Howe), the clocks' changes included
 *   shelves.json  album lists (the sims' fixtures, and seeded random ones with stars seconds apart across month
 *                 ends) under the five sorts x both `by`: the order, the headers, the index, and Find's
 *   index.json    fitIndex over the 27 letters at 0-40 slots, and entryAt swept every half point down each strip
 *   marks.json    newMarks / isNew over answers and albums
 *   store.json    traces of app/albumIndex.ts driven step by step (asks, landings, failures, forgets, the clock)
 *   seen.json     traces of app/useMyLibrary.ts's seenAlbum and its first answer (what deadwax is told, what stays new)
 *   words.json    the words and numbers the Swift copies say (titles, notices, constants)
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any
 * machine writes the same bytes. Never edit a fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-library-vectors.cjs           write the fixtures
 *   node ios/scripts/export-library-vectors.cjs --check   write nothing; exit 1 when a fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

//? every Date.parse below runs in a zone this script sets, never the machine's
process.env.TZ = 'UTC'

const ROOT = path.resolve(__dirname, '..', '..')
const UI = path.join(ROOT, 'ui')
const FIXTURES = path.join(ROOT, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'library')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-library-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/shelves.ts', 'src/lib/artistPage.ts', 'src/lib/myLibrary.ts', 'src/lib/appFrame.ts', 'src/lib/yourLibrary.ts',
  'src/app/albumIndex.ts', 'src/app/useMyLibrary.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

//? the stand-ins: Preact's hooks, the network, the session - each step of a trace says what they answer
const write = (file, body) => {
  fs.mkdirSync(path.dirname(path.join(OUT, file)), { recursive: true })
  fs.writeFileSync(path.join(OUT, file), body)
}
write('node_modules/preact/hooks.js', 'exports.useState = (v) => [v, () => {}]\nexports.useEffect = () => {}\n')
write('player/api.js', 'exports.albumIndexOf = (scope) => globalThis.__vectors.albumIndexOf(scope)\n')
write('api/me.js', [
  'exports.myLibrary = (signal) => globalThis.__vectors.myLibrary(signal)',
  'exports.markLibrarySeen = (by) => globalThis.__vectors.markLibrarySeen(by)',
  '',
].join('\n'))
write('app/session.js', 'exports.sessionMe = () => globalThis.__vectors.me\nexports.permissionsUntilAsked = () => new Set()\n')
write('lib/libraryEvents.js', [
  'exports.onAlbumsFiled = () => () => {}',
  'exports.onAddedToLibrary = () => () => {}',
  'exports.onRemovedFromLibrary = () => () => {}',
  '',
].join('\n'))
const V = (globalThis.__vectors = {})

const owned = require(path.join(OUT, 'lib/owned.js'))
const S = require(path.join(OUT, 'lib/shelves.js'))
const W = require(path.join(OUT, 'lib/myLibrary.js'))
const F = require(path.join(OUT, 'lib/appFrame.js'))
const Y = require(path.join(OUT, 'lib/yourLibrary.js'))
const A = require(path.join(OUT, 'lib/artistPage.js'))
const fresh = (file) => {
  const full = path.join(OUT, file)
  delete require.cache[require.resolve(full)]
  return require(full)
}

/* ===== output: plain ASCII, one vector a line ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(text) {
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i)
    out += unit < 0x7f ? text[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const flat = (value) => ascii(JSON.stringify(value))
const primitive = (value) => value === null || typeof value !== 'object'
//? objects and arrays laid out to `depth` levels, one member a line; deeper, and arrays of plain values, on one line
function laid(value, depth, indent = '') {
  if (primitive(value) || depth === 0 || (Array.isArray(value) && value.every(primitive))) return flat(value)
  const inner = indent + '  '
  if (Array.isArray(value)) {
    if (!value.length) return '[]'
    return '[\n' + value.map((item) => inner + laid(item, depth - 1, inner)).join(',\n') + '\n' + indent + ']'
  }
  const keys = Object.keys(value)
  if (!keys.length) return '{}'
  return '{\n' + keys.map((key) => inner + flat(key) + ': ' + laid(value[key], depth - 1, inner)).join(',\n') + '\n' + indent + '}'
}
const files = {}
const emit = (name, value, depth) => {
  files[name] = laid(value, depth) + '\n'
}

/* ===== seeded randomness ===== */

let seed = 12345
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const cp = (...points) => String.fromCodePoint(...points)
const chars = (text) => [...text]

/* ===== fold ===== */

const FIXED_NAMES = [
  'The Beatles', 'Björk', 'Simon & Garfunkel', 'Dummy (Deluxe Edition)', 'AC/DC', "Guns N' Roses", 'Sigur Rós', 'Mötley Crüe',
  '坂本龍一', 'ΟΔΟΣ', 'ΑΣ ΣΑ', 'Σ', 'ΣΣ', 'ΆΣ', 'ΟΔΟΣ' + cp(0x2019) + 'Α', 'ΟΔΟΣ' + cp(0xad) + 'Α', 'ΟΔΟΣ.', 'ΟΔΟΣ' + cp(0x2b0),
  cp(0x2b0) + 'Σ', 'aΣb', 'aΣ', 'İstanbul', cp(0xfb01) + 've', 'Ｆｕｌｌ', cp(0xbd) + ' Life', 'x' + cp(0xb2), 'Æther', 'Œuvre',
  'Straße', 'Øresund', 'Łódź', 'Đorđe', cp(0x149), cp(0xfb00), cp(0xfb06), 'Ⅳ', cp(0x1c5) + 'emal', cp(0x24b6) + 'rt',
  'The The', 'The', '  the  beatles ', 'Thé Band', 'The' + cp(0x301) + ' Band', 'The-Band', 'THE BEATLES', 'the\tbeatles',
  'the' + cp(0x3000) + 'beatles', 'the' + cp(0xa0) + 'beatles', 'Theatre', 'Thea', '(The) Beatles', 'the beatles', 'The &', '&', 'R&B',
  '[Remastered] Album', 'Album (unclosed', 'x (a] y', 'a (b) c (d) e', 'Kid A [Deluxe] (2009)', 'Plaid & Co (Live)', 'a ((b) c) d',
  'a (b [c] d', 'a ] b ) c', "Rock 'n' Roll", 'Hello ' + cp(0x2018) + 'World' + cp(0x2019), '$uicideboy$', '!!!', '', null,
  cp(0x2026) + 'And You Will Know Us', cp(0x1f3b5) + ' Music', '방탄', '방탄소년단', '가각', 'ㄱ', '가', 'Мумий Тролль', 'Ёлка',
  cp(0x1c4), cp(0x1e9e), 'K', 'Ω', cp(0x2126), cp(0x212a), cp(0x663), cp(0x967, 0x968), cp(0x217b), cp(0x1d43), cp(0xff76, 0xff9e),
  'Ｔｈｅ Ｂｅａｔｌｅｓ', cp(0x20000) + 'x', cp(0xfa0e) + 'y', 'Zz Top', 'a', 'A', 'ä', 'Ä', 'a' + cp(0x308), '10cc', '2Pac',
  'Beatles Tribute', 'bjork', 'BJÖRK', cp(0x130), 'ı', 'ǅ', cp(0x345) + 'Σ', 'Σ' + cp(0x345), cp(0xd4e) + ' x',
]

const POOLS = [
  'abcXYZ ', 'Tthe ', 'éÉüÜñçøØłŁßæœ', 'ΑΣΒΓΔσςΟ', 'АБВЁёй', '坂本龍一' + cp(0xfa0e), '방탄소년단가', 'ＡＢｃ１２',
  '()[]&`"-./!?\'' + cp(0x2019, 0x2018, 0xb4, 0x2026), '0123456789' + cp(0xb2, 0xbd, 0x2163), cp(0xfb01, 0xfb00, 0xfb06, 0x1c5, 0x149),
  cp(0x301, 0x308, 0x20dd, 0x345), ' \t\n' + cp(0x3000, 0xa0), cp(0x1f3b5, 0x1f44d, 0x1f3fd), cp(0x20000, 0x2a6d6), cp(0x2bc, 0xad, 0x2b0, 0x1d43),
  'İıIi', 'ㄱ' + cp(0xff76, 0xff9e), 'ΣΣΣΣ ',
].map(chars)

function randomName(maxLength) {
  let text = rand() < 0.2 ? 'The ' : ''
  const length = 1 + Math.floor(rand() * maxLength)
  for (let k = 0; k < length; k++) text += pick(pick(POOLS))
  return text
}

const foldNames = [...FIXED_NAMES]
for (let n = 0; n < 2000; n++) foldNames.push(randomName(14))
emit('fold.json', {
  about: 'lib/owned.ts foldName, lib/shelves.ts findText and initialOf(foldName) of each name: [name, foldName, findText, initial]. Written by ios/scripts/export-library-vectors.cjs.',
  names: foldNames.map((name) => {
    const key = owned.foldName(name)
    return [name, key, S.findText(name), S.initialOf(key)]
  }),
}, 2)

/* ===== dates ===== */

const ZONES = ['UTC', 'America/New_York', 'Europe/London', 'Australia/Lord_Howe']
const pad = (value, width) => String(value).padStart(width, '0')
const dateTexts = [
  '2026-10-05T14:22:31Z', '2026-10-05T14:22:31.1Z', '2026-10-05T14:22:31.12Z', '2026-10-05T14:22:31.123Z', '2026-10-05T14:22:31.123456789Z',
  '2026-10-05T14:22:31.9999Z', '2026-10-05T14:22:31+01:00', '2026-10-05T14:22:31.5-05:30', '2026-10-05T14:22:31', '2026-10-05',
  '2026-10-05T14:22Z', '2026-10-05 14:22:31Z', '2026-10-05t14:22:31z', '2026-10-05T14:22:31.123456+00:00', '0001-01-01T00:00:00Z',
  '0000-01-01T00:00:00Z', '2026', '2026-10', '2026-10-05T24:00:00Z', '2026-10-05T24:00Z', '2026-10-05T24:00', '2026-10-05T24:00:01Z',
  '2026-10-05T24:00:00.001Z', '2026-02-30T00:00:00Z', '2026-02-31', '2026-04-31T12:00:00Z', '2026-10-05T14:22:31.123456789+02:00',
  '2026-10-31T23:30:00-05:00', '2026-01-01T00:00:00Z', '1969-12-31T23:59:59.999Z', '1900-02-28T12:00:00Z', '2000-02-29T00:00:00Z',
  '2026-08-31T23:59:59Z', '2026-10-05 14:22', '2026-10-05T14:22', '2026-10-05T14:22:31+14:00', '2026-10-05T14:22:31-12:00',
  '2026-10-05T14:22:31+23:59', '0001-01-01T00:00:00', '1883-11-18T12:00:00', '1960-06-15T12:00:00',
  //? the expanded years, out to the edges of a JS Date (8.64e15 ms either side of 1970)
  '+002026-10-05T00:00:00Z', '+002026-10-05', '+002026-10-05T12:00:00', '-000001-01-01T00:00:00Z', '+275760-09-13T00:00:00Z',
  '-271821-04-20T00:00:00Z', '+010000-01-01T00:00:00Z',
  //? NaN in V8
  '2026-13-05T00:00:00Z', '2026-00-05T00:00:00Z', '2026-10-00T00:00:00Z', '2026-10-32T00:00:00Z', '2026-10-05T14:60:00Z',
  '2026-10-05T25:00:00Z', '2026-10-05T14:22:60Z', '2026-10-05T14:22:31.Z', '2026-10-05T14:22:31,5Z', '2026-10-05T14:22:31 Z',
  '2026-10-05T1:22:31Z', '26-10-05', '2026-10-05T', '2026-10-05T14', '2026-10-05T14:22:31+01',
  '2026-10-05T14:22:31ZZ', 'not a date', '', '20261005', '2026-10-05T14:22:31.123x',
  '-000000-01-01T00:00:00Z', '+275760-09-13T00:00:00.001Z', '-271821-04-19T23:59:59.999Z', '2026-10-05T14:22:31+01:00Z',
]
//? forms outside the ISO format that V8 reads anyway, with its legacy parser - which the port deliberately doesn't (Navidrome
//? sends RFC 3339, nothing else): written down so the Swift tests can say each is read as no date there, and so a change in
//? what V8 does with them shows here
const legacyTexts = ['2026-1-05', '2026-10-05T14:22:31+0100', '2026-10-05Z', ' 2026-10-05', '2026-10-05 ', '+02026-10-05']
//? the clocks' changes, 2024-2028: New York (second Sunday of March, first of November, 2am), London (last Sundays of
//? March and October, 1am), Lord Howe (first Sundays of October and April, 2am, half an hour)
const sunday = (year, month, nth) => {
  //? nth Sunday of the month (1-based), or the last with nth = -1
  const days = new Date(Date.UTC(year, month, 0)).getUTCDate()
  const sundays = []
  for (let day = 1; day <= days; day++) if (new Date(Date.UTC(year, month - 1, day)).getUTCDay() === 0) sundays.push(day)
  return nth === -1 ? sundays[sundays.length - 1] : sundays[nth - 1]
}
for (let year = 2024; year <= 2028; year++) {
  const changes = [[3, sunday(year, 3, 2)], [11, sunday(year, 11, 1)], [3, sunday(year, 3, -1)], [10, sunday(year, 10, -1)],
    [10, sunday(year, 10, 1)], [4, sunday(year, 4, 1)]]
  for (const [month, day] of changes) {
    for (const hour of [0, 1, 2, 3]) for (const minute of [0, 15, 30, 45]) {
      dateTexts.push(`${year}-${pad(month, 2)}-${pad(day, 2)}T${pad(hour, 2)}:${pad(minute, 2)}:00`)
    }
  }
}
for (let n = 0; n < 600; n++) {
  const year = 1950 + Math.floor(rand() * 80), month = 1 + Math.floor(rand() * 12), day = 1 + Math.floor(rand() * 28)
  const hour = Math.floor(rand() * 24), minute = Math.floor(rand() * 60), second = Math.floor(rand() * 60)
  const fraction = rand() < 0.5 ? '' : '.' + String(Math.floor(rand() * 1e9)).padStart(9, '0').slice(0, 1 + Math.floor(rand() * 9))
  const zone = pick(['Z', '+00:00', '-05:00', '+05:30', '+14:00', '-12:00', '', 'z'])
  dateTexts.push(`${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}T${pad(hour, 2)}:${pad(minute, 2)}:${pad(second, 2)}${fraction}${zone}`)
}
const dateRows = dateTexts.map((text) => ({ text, ms: [], month: [] }))
const legacyRows = legacyTexts.map((text) => ({ text, ms: [], month: [] }))
for (const zone of ZONES) {
  process.env.TZ = zone
  for (const row of [...dateRows, ...legacyRows]) {
    const parsed = Date.parse(row.text)
    row.ms.push(Number.isNaN(parsed) ? null : parsed)
    row.month.push(S.monthLabel(row.text))
  }
}
process.env.TZ = 'UTC'
//? the zone set at run time must have taken (Node reads TZ again when it is assigned): a local time differs
if (dateRows.find((row) => row.text === '2026-10-05T14:22:31').ms.join() === '1791210151000,1791210151000,1791210151000,1791210151000') {
  throw new Error('process.env.TZ had no effect on Date.parse - the zones above are all one')
}
emit('dates.json', {
  about: 'Date.parse (ms, null for NaN) and lib/shelves.ts monthLabel of each string, in each of `zones`; `legacy` the same for forms only V8\'s legacy parser reads, which the port reads as no date. Written by ios/scripts/export-library-vectors.cjs.',
  zones: ZONES,
  dates: dateRows,
  legacy: legacyRows,
}, 2)

/* ===== shelves ===== */

const SORTS = ['alphabeticalByArtist', 'alphabeticalByName', 'newest', 'byYearDesc', 'byYearAsc']
const BYS = ['collection', 'you']

//? the sims' own lists (shelves.sim, whose.sim)
const NAMED = {
  sim: [
    { id: 'abbey', name: 'Abbey Road', artist: 'The Beatles', year: 1969, created: '2026-09-02T10:00:00Z', played: '2026-10-01T10:00:00Z', playCount: 3 },
    { id: 'help', name: 'Help!', artist: 'The Beatles', year: 1965, created: '2026-10-05T10:00:00Z' },
    { id: 'tribute', name: 'Tribute', artist: 'Beatles Tribute', year: 2001, created: '2026-10-06T10:00:00Z', played: '2026-10-15T10:00:00Z', playCount: 1 },
    { id: 'debut', name: 'Debut', artist: 'Björk', year: 1993, created: 'not a date' },
    { id: 'post', name: 'Post', artist: 'bjork', year: 0, created: '2026-10-06T11:00:00Z' },
    { id: 'cc', name: 'Sheet Music', artist: '10cc', year: 1974, created: '2026-08-31T23:59:59Z', played: '2026-10-14T10:00:00Z', playCount: 3 },
    { id: 'pac', name: 'Me Against the World', artist: '2Pac', created: '2026-10-07T10:00:00Z' },
    { id: 'sakamoto', name: 'async', artist: '坂本龍一', year: 2017 },
    { id: 'nobody', name: 'Untitled', artist: '', year: 1999, created: 1729000000.5 },
    { id: 'simon', name: 'Bookends', artist: 'Simon & Garfunkel', year: 1968, created: '2026-10-06T10:00:00Z', playCount: 0 },
    { id: 'debut2', name: 'Debut', artist: 'Björk', year: 1993 },
  ],
  yours: [
    { id: 'late', name: 'Old in the collection, new to you', artist: 'a', starred: '2026-10-20T10:00:00Z', created: '2024-01-01T00:00:00Z' },
    { id: 'tA', name: 'Starred together A', artist: 'a', starred: '2026-10-10T00:00:00Z', created: '2026-03-01T00:00:00Z' },
    { id: 'tB', name: 'Starred together B', artist: 'a', starred: '2026-10-10T00:00:00Z', created: '2026-05-01T00:00:00Z' },
    { id: 'amperfy', name: 'Starred in Amperfy', artist: 'a', starred: '2026-10-05T09:00:00Z', created: '2026-10-04T00:00:00Z' },
    { id: 'noStar', name: 'No star (never in your list)', artist: 'a', created: '2026-09-15T00:00:00Z' },
    { id: 'far', name: 'A minute after the seed', artist: 'a', starred: '2026-09-01T12:01:00Z', created: '2020-01-01T00:00:00Z' },
    { id: 's3', name: 'Seed 3', artist: 'a', starred: '2026-09-01T12:00:03Z', created: '2026-08-15T00:00:00Z' },
    { id: 's4', name: 'Seed 4', artist: 'a', starred: '2026-09-01T12:00:03.000Z' },
    { id: 's2', name: 'Seed 2', artist: 'a', starred: '2026-09-01T11:59:50Z', created: '2026-06-01T00:00:00Z' },
    { id: 's1', name: 'Seed 1', artist: 'a', starred: '2026-09-01T11:59:25Z', created: '2026-08-01T00:00:00Z' },
    { id: 'none', name: 'No date at all', artist: 'a' },
  ],
  over: [
    { id: 'm2', name: 'm2', artist: 'a', starred: '2026-09-01T00:00:05Z', created: '2025-01-01T00:00:00Z' },
    { id: 'm1', name: 'm1', artist: 'a', starred: '2026-08-31T23:59:50Z', created: '2026-01-01T00:00:00Z' },
    { id: 'aug', name: 'aug', artist: 'a', starred: '2026-08-20T00:00:00Z', created: '2026-01-02T00:00:00Z' },
  ],
  seed: [
    { id: 'a', name: 'Alpha', artist: 'x', starred: '2026-09-01T00:00:10Z', created: '2025-01-01T00:00:00Z' },
    { id: 'b', name: 'Beta', artist: 'x', starred: '2026-08-31T23:59:50Z', created: '2026-03-01T00:00:00Z' },
    { id: 'c', name: 'Gamma', artist: 'x', starred: '2026-08-31T23:59:30Z', created: '2026-06-01T00:00:00Z' },
    { id: 'd', name: 'Delta', artist: 'x', starred: '2026-08-20T00:00:00Z', created: '2026-01-02T00:00:00Z' },
  ],
  tied: [
    { id: 'older', name: 'older', artist: 'a', starred: '2026-09-01T12:00:00Z', created: '2026-01-01T00:00:00Z' },
    { id: 'newer', name: 'newer', artist: 'a', starred: '2026-09-01T12:00:05Z', created: '2026-01-01T00:00:00Z' },
    { id: 'olderBare', name: 'olderBare', artist: 'a', starred: '2026-09-01T11:59:50Z' },
    { id: 'newerBare', name: 'newerBare', artist: 'a', starred: '2026-09-01T11:59:55Z' },
  ],
  store: [
    { id: 'c1', name: 'c1', artist: 'a', created: '2026-10-01T00:00:00Z', starred: '2026-10-20T00:00:00Z' },
    { id: 'c2', name: 'c2', artist: 'a', created: '2026-10-10T00:00:00Z' },
    { id: 'c3', name: 'c3', artist: 'a', created: '2026-09-01T00:00:00Z', starred: '2026-10-22T00:00:00Z' },
  ],
  whose: [
    { id: 'a', name: 'The Slow Rush', artist: 'Tame Impala', year: 2020, created: '2026-10-01T00:00:00Z', played: '2026-10-14T00:00:00Z' },
    { id: 'b', name: 'Dummy', artist: 'Portishead', year: 1994, created: '2026-10-10T00:00:00Z' },
    { id: 'c', name: 'Third', artist: 'Portishead', year: 2008, created: '2026-09-01T00:00:00Z', played: '2026-10-15T00:00:00Z' },
    { id: 'd', name: 'Abbey Road', artist: 'The Beatles', year: 1969 },
  ],
  collation: [
    { id: 'one', name: 'One', artist: '一' },
    { id: 'bts', name: 'Map of the Soul', artist: '방탄' },
    { id: 'fa0e', name: 'x', artist: cp(0xfa0e) },
    { id: 'astral', name: 'y', artist: cp(0x20000) },
    { id: 'btsLong', name: 'Proof', artist: '방탄소년단' },
  ],
  dlx: [
    { id: 'dlx', name: 'Dummy (Deluxe Edition)', artist: 'Portishead' },
    { id: 'dummy', name: 'Dummy', artist: 'Portishead', year: 1994 },
  ],
  empty: [],
}
const NAMED_TYPED = {
  sim: ['', '   ', 'beatles road', 'road BEATLES', 'help', 'beatles', 'bjork', 'BJÖRK post', 'simon and', '&', 'the beatles abbey', 'eat', 'zzz'],
  yours: ['', 'seed', 'seed 1', 'starred', 'a'],
  over: ['', 'm1', 'm2', 'aug'],
  seed: ['', 'alpha', 'gamma', 'a', 'beta'],
  tied: ['', 'older', 'bare'],
  store: ['', 'c1'],
  whose: ['', 'portishead', 'the'],
  collation: ['', '바', '방탄', '一', 'one'],
  dlx: ['', 'deluxe', 'dummy', 'edition dummy'],
  empty: ['', 'x'],
}

//? random lists: awkward names, missing and zero years, unreadable dates and floats, and runs of stars a few seconds
//? apart over a month's end (the first admin's seed), some gaps over the thirty seconds
const ARTISTS = ['The Beatles', 'Björk', 'bjork', '10cc', '2Pac', '坂本龍一', '', null, 'Simon & Garfunkel', 'ΟΔΟΣ', '방탄소년단', 'Sigur Rós',
  'The The', 'AC/DC', 'Æther', '$uicideboy$', 'Ｔｈｅ Ｂｅａｔｌｅｓ', cp(0x20000) + 'x', cp(0xfa0e) + 'y', 'Zz Top', 'a', 'A', 'ä', 'Ä',
  'Portishead', 'Massive Attack', 'Thé Band', 'Boards of Canada', '!!!']
const TITLES = ['Dummy', 'Third', 'Dummy (Deluxe Edition)', 'Abbey Road', 'Help!', 'async', '', null, 'Kid A [Deluxe] (2009)', 'The Album',
  'Seed', 'Untitled', '½', 'Ⅳ', 'ΟΔΟΣ', 'Post', 'Debut', '1999', 'Zebra', 'zebra', 'Ångström']
const iso = (ms, form) => {
  const text = new Date(ms).toISOString()
  if (form === 0) return text.replace('.000Z', 'Z')
  if (form === 1) return text
  //? the same instant two hours east
  const shifted = new Date(ms + 2 * 3600000).toISOString().replace('.000Z', '').replace('Z', '')
  return shifted + '+02:00'
}
function randomList(count) {
  const albums = []
  let star = Date.UTC(2026, 7, 31, 23, 58, 0) + Math.floor(rand() * 4) * 86400000 * 30
  for (let n = 0; n < count; n++) {
    const album = { id: `al${n}` }
    if (rand() < 0.97) album.name = rand() < 0.75 ? pick(TITLES) : randomName(8)
    if (rand() < 0.97) album.artist = rand() < 0.8 ? pick(ARTISTS) : randomName(8)
    const year = rand()
    if (year < 0.08) album.year = 0
    else if (year < 0.85) album.year = 1950 + Math.floor(rand() * 77)
    const created = rand()
    if (created < 0.04) album.created = 1729000000.5
    else if (created < 0.07) album.created = pick(['not a date', '', '2026-13-01T00:00:00Z'])
    else if (created < 0.9) album.created = iso(Date.UTC(2025, 0, 1) + Math.floor(rand() * 600) * 86400000 + Math.floor(rand() * 86400) * 1000, Math.floor(rand() * 3))
    if (rand() < 0.75) {
      //? the next star: mostly seconds after the last, sometimes a jump - a new moment
      star -= rand() < 0.85 ? Math.floor(rand() * 35000) : Math.floor(rand() * 86400000 * 20)
      album.starred = iso(star, Math.floor(rand() * 3))
    }
    if (rand() < 0.1) album.musicBrainzId = rand() < 0.5 ? '' : `rel-${n}`
    albums.push(album)
  }
  //? Navidrome's own order for yours: the newest star first - shuffled a little, as a filing between pages may
  for (let n = 0; n < count / 10; n++) {
    const i = Math.floor(rand() * count), j = Math.floor(rand() * count)
    ;[albums[i], albums[j]] = [albums[j], albums[i]]
  }
  return albums
}
function randomTyped(albums) {
  const typed = ['', '  ', 'a', 'the', 'zzzz', 'BJÖRK', '바', 'seed']
  for (let n = 0; n < 3; n++) {
    if (!albums.length) break
    const album = pick(albums)
    const words = S.findText(rand() < 0.5 ? album.name : album.artist).split(' ').filter(Boolean)
    if (words.length) typed.push(words.slice(0, 1 + Math.floor(rand() * 2)).join(' ').slice(0, 1 + Math.floor(rand() * 6)))
  }
  return typed
}

const lists = Object.keys(NAMED).map((name) => ({ name, albums: NAMED[name], typed: NAMED_TYPED[name] }))
for (const count of [1, 2, 5, 12, 30, 49, 50, 64, 90, 140]) {
  const albums = randomList(count)
  lists.push({ name: `random-${count}`, albums, typed: randomTyped(albums) })
}

const places = (albums, subset) => subset.map((album) => albums.indexOf(album))
const heads = (groups) => ({ heads: groups.map((group) => group.label), sizes: groups.map((group) => group.items.length) })
const shelves = lists.map(({ name, albums, typed }) => ({
  name,
  albums,
  typed,
  noMatch: typed.map((text) => S.noMatchText('albums', text)),
  sorts: SORTS.flatMap((sort) => BYS.map((by) => {
    const sorted = S.sortAlbums(albums, sort, by)
    const groups = S.groupAlbums(sorted, sort, by, sorted)
    return {
      sort,
      by,
      order: places(albums, sorted),
      ...heads(groups),
      index: S.indexEntries(groups, sort).map((entry) => [entry.label, entry.group]),
      finds: typed.map((text) => {
        const found = S.finding(text) ? S.filterAlbums(sorted, text) : sorted
        const foundGroups = S.groupAlbums(found, sort, by, sorted)
        return {
          found: places(albums, found),
          ...heads(foundGroups),
          shows: S.showsIndex(sort, sorted.length, text),
          count: S.finding(text) ? S.filteredCountText(found.length, sorted.length, 'album', 'albums') : A.countText(sorted.length, 'album', 'albums'),
        }
      }),
    }
  })),
}))
emit('shelves.json', {
  about: 'lib/shelves.ts over each album list: noMatchText of each `typed`; for each sort and `by`, the order (places in `albums`), the headers (groupAlbums with whole = the sorted list), indexEntries ([label, group]; the words index.json has), and for each `typed` what filterAlbums keeps of the sorted list, its headers (months from the whole), showsIndex and the count. Written by ios/scripts/export-library-vectors.cjs.',
  lists: shelves,
}, 4)

/* ===== the index ===== */

const LETTER_ENTRIES = S.indexEntries([{ key: 'A', label: 'A', items: [0] }], 'alphabeticalByArtist')
const DECADE_ENTRIES = S.indexEntries(Array.from({ length: 9 }, (_, n) => ({ key: String(2020 - n * 10), label: String(2020 - n * 10), items: [0] })), 'byYearDesc')
const drawnOf = (slots) => slots.map((slot) => (slot.kind === 'dot' ? -1 : slot.at))
const indexFits = []
for (const [kind, entries] of [['letters', LETTER_ENTRIES], ['decades', DECADE_ENTRIES]]) {
  for (let count = -1; count <= 40; count++) {
    const drawn = S.fitIndex(entries, count)
    //? entryAt down the strip and past both ends, every half point: 15 points a slot from 100
    const top = 100, height = drawn.length * 15
    const at = []
    for (let y = top - 5; y <= top + height + 5; y += 0.5) at.push(S.entryAt(drawn, y, top, height))
    indexFits.push({ kind, slots: count, drawn: drawnOf(drawn), top, height, from: top - 5, step: 0.5, at })
  }
}
emit('index.json', {
  about: 'lib/shelves.ts fitIndex of the 27 letter entries and 9 decade entries at each slot count (drawn: each slot\'s place among the entries, -1 a dot), and entryAt swept from `from` every `step` points down a strip of `height` from `top`. Written by ios/scripts/export-library-vectors.cjs.',
  letters: LETTER_ENTRIES.map((entry) => [entry.label, entry.aria]),
  decades: DECADE_ENTRIES.map((entry) => [entry.label, entry.aria]),
  fits: indexFits,
}, 2)

/* ===== New marks ===== */

const entry = (id, album, more = {}) => ({ album_id: id, artist: 'Portishead', album, release_mbid: `rel-${id}`, release_group_mbid: `grp-${id}`,
  navidrome_id: null, added_at: '2026-10-15T09:00:00+00:00', how: 'grabbed', ...more })
const ANSWERS = [
  null,
  { on: false },
  { on: true, library: false, kept: false },
  { on: true, library: true, kept: true, count: 12, starred: 10, new: [entry(1, 'Dummy', { navidrome_id: 'nd-dummy' }), entry(3, 'Third')] },
  { on: true, library: true, kept: true, count: 3, starred: 3, new: [entry(4, 'Mixed', { release_mbid: 'REL-Mixed-ABC', navidrome_id: '' }),
    entry(5, 'No release', { release_mbid: null, navidrome_id: 'nd-5' }), entry(6, 'Empty', { release_mbid: '', navidrome_id: null }),
    entry(7, 'Spaced', { release_mbid: ' rel-7 ', navidrome_id: 'ND-7' })] },
  { on: true, library: true, kept: true, count: 0, starred: 0, new: [] },
]
const MARK_ALBUMS = [
  { id: 'nd-dummy' }, { id: 'nd-x', musicBrainzId: 'REL-3' }, { id: 'nd-x', musicBrainzId: 'rel-4' }, { id: 'nd-x', musicBrainzId: 'rel-1' },
  { id: 'nd-x', musicBrainzId: '  REL-1  ' }, { id: 'nd-x', musicBrainzId: '' }, { id: '' }, { id: 'nd-5' }, { id: 'ND-5' }, { id: 'nd-7' },
  { id: 'ND-7' }, { id: 'nd-y', musicBrainzId: 'rel-mixed-abc' }, { id: 'nd-y', musicBrainzId: ' rel-7 ' }, { id: 'nd-y', musicBrainzId: 'rel-7' },
  { id: 'nd-y', musicBrainzId: 'REL-MIXED-ABC' }, { id: 'nd-dummy', musicBrainzId: 'other' },
]
emit('marks.json', {
  about: 'lib/myLibrary.ts isNew(newMarks(answer), album) for each answer (rows) and album (columns). Written by ios/scripts/export-library-vectors.cjs.',
  answers: ANSWERS,
  albums: MARK_ALBUMS,
  isNew: ANSWERS.map((answer) => MARK_ALBUMS.map((album) => W.isNew(W.newMarks(answer), album))),
}, 2)

/* ===== traces of the real modules ===== */

const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

//? app/albumIndex.ts: each step, then what the module holds - how many asks in all, each scope's generation, the kept
//? list (its one album names the ask that brought it) and when it landed
async function storeTrace(steps) {
  const lands = []
  let asks = 0
  let clock = 1_000_000
  const realNow = Date.now
  Date.now = () => clock
  V.albumIndexOf = (scope) => {
    const n = asks++
    return new Promise((resolve, reject) => lands.push({ scope, n, resolve, reject }))
  }
  const AI = fresh('app/albumIndex.js')
  const seen = []
  try {
    for (let step of steps) {
      if (step.op === 'list') AI.albumIndex(step.scope).catch(() => {})
      else if (step.op === 'forget') AI.forgetIndex(step.scope)
      else if (step.op === 'refreshIfOld') AI.refreshIfOld(step.scope)
      else if (step.op === 'tick') clock += step.ms
      else if (step.op === 'land' || step.op === 'fail') {
        //? (a random walk's landing with nothing out is a step that does nothing - the replay checks it has none either)
        const one = step.newest ? lands.pop() : lands.shift()
        if (one && step.op === 'fail') one.reject(new Error('away'))
        else if (one) one.resolve({ albums: [{ id: `ask-${one.n}` }], truncated: one.n % 3 === 0 })
        else step = { ...step, none: true }
      }
      await settle()
      const kept = (scope) => AI.keptIndex(scope)
      seen.push({
        ...step,
        asks,
        generation: [AI.useIndexGeneration('yours'), AI.useIndexGeneration('store')],
        kept: [kept('yours')?.albums[0]?.id ?? null, kept('store')?.albums[0]?.id ?? null],
        at: [kept('yours')?.at ?? null, kept('store')?.at ?? null],
        truncated: [kept('yours')?.truncated ?? null, kept('store')?.truncated ?? null],
      })
    }
  } finally {
    Date.now = realNow
  }
  return seen
}

const STORE_TRACES = {
  //? whose.sim's "your albums, the module itself"
  shared: [
    { op: 'list', scope: 'yours' }, { op: 'list', scope: 'yours' }, { op: 'land' },
    { op: 'forget', scope: 'yours' }, { op: 'list', scope: 'yours' }, { op: 'land' },
    { op: 'forget', scope: 'yours' }, { op: 'list', scope: 'yours' }, { op: 'land' },
    { op: 'refreshIfOld', scope: 'yours' }, { op: 'tick', ms: 60_000 }, { op: 'refreshIfOld', scope: 'yours' },
    { op: 'tick', ms: 1 }, { op: 'refreshIfOld', scope: 'yours' }, { op: 'list', scope: 'yours' }, { op: 'tick', ms: 120_000 },
    { op: 'refreshIfOld', scope: 'yours' }, { op: 'land' },
    { op: 'forget', scope: 'yours' }, { op: 'list', scope: 'yours' }, { op: 'forget', scope: 'yours' }, { op: 'list', scope: 'yours' },
    { op: 'land', newest: true }, { op: 'land' },
    { op: 'list', scope: 'store' }, { op: 'fail' }, { op: 'list', scope: 'store' }, { op: 'land' },
  ],
  //? nothing kept yet: an older ask landing first is kept, then the newer replaces it
  olderFirst: [
    { op: 'list', scope: 'store' }, { op: 'forget', scope: 'store' }, { op: 'list', scope: 'store' }, { op: 'land' }, { op: 'land' },
    { op: 'list', scope: 'store' }, { op: 'refreshIfOld', scope: 'store' },
  ],
  //? an older ask failing after a newer one is out leaves the newer one held
  olderFails: [
    { op: 'list', scope: 'yours' }, { op: 'forget', scope: 'yours' }, { op: 'list', scope: 'yours' }, { op: 'fail' },
    { op: 'list', scope: 'yours' }, { op: 'land' }, { op: 'list', scope: 'yours' },
  ],
  //? refreshIfOld with nothing kept; one landing late after a refresh; the two scopes apart
  apart: [
    { op: 'refreshIfOld', scope: 'store' }, { op: 'list', scope: 'store' }, { op: 'list', scope: 'yours' }, { op: 'tick', ms: 70_000 },
    { op: 'land', newest: true }, { op: 'refreshIfOld', scope: 'store' }, { op: 'refreshIfOld', scope: 'yours' }, { op: 'land' },
    { op: 'tick', ms: 60_001 }, { op: 'refreshIfOld', scope: 'store' }, { op: 'refreshIfOld', scope: 'yours' }, { op: 'list', scope: 'store' },
    { op: 'list', scope: 'yours' }, { op: 'land' }, { op: 'fail' },
  ],
}
//? seeded random walks over both scopes
for (let walk = 0; walk < 8; walk++) {
  const steps = []
  for (let n = 0; n < 60; n++) {
    const roll = rand()
    const scope = rand() < 0.5 ? 'yours' : 'store'
    if (roll < 0.3) steps.push({ op: 'list', scope })
    else if (roll < 0.45) steps.push({ op: 'forget', scope })
    else if (roll < 0.6) steps.push({ op: 'refreshIfOld', scope })
    else if (roll < 0.7) steps.push({ op: 'tick', ms: pick([1, 1000, 30_000, 59_999, 60_000, 61_000]) })
    else steps.push({ op: rand() < 0.8 ? 'land' : 'fail', newest: rand() < 0.3 })
  }
  STORE_TRACES[`walk-${walk}`] = steps
}

//? useMyLibrary.ts: who is signed in, an ask and its answer, an album opened - then what deadwax was told and what
//? stays new
async function seenTrace(steps) {
  const open = []
  const told = []
  V.me = null
  V.myLibrary = () => new Promise((resolve, reject) => open.push({ resolve, reject }))
  V.markLibrarySeen = (by) => {
    told.push(by)
    return Promise.resolve({ cleared: 1 })
  }
  const store = fresh('app/useMyLibrary.js')
  const seen = []
  for (const step of steps) {
    const before = told.length
    if (step.op === 'me') V.me = step.me
    else if (step.op === 'ask') store.askMyLibrary()
    else if (step.op === 'answer') {
      //? only the newest ask is answered here: which answer counts among several is latestOnly's (the app's own)
      const one = open.pop()
      open.length = 0
      if (one) one.resolve(step.answer)
    } else if (step.op === 'open') store.seenAlbum(step.album)
    await settle()
    const now = store.myLibraryNow()
    seen.push({ ...step, told: told.slice(before), news: now ? (now.new ?? []).map((one) => one.album_id) : null })
  }
  return seen
}

const ETHAN = { user: 'ethan', admin: false, auth: 'on', version: 'x' }
const LIBRARY = { on: true, library: true, kept: true, count: 12, starred: 10, waiting: 2, incomplete: 1, login: 'ok',
  new: [entry(1, 'Dummy', { navidrome_id: 'nd-dummy' }), entry(3, 'Third')] }
const SEEN_TRACES = {
  //? mylibrary.sim's "the store (app/useMyLibrary.ts)" and "...opened before deadwax first said"
  sim: [
    { op: 'me', me: null }, { op: 'ask' }, { op: 'me', me: { user: 'deadwax', admin: true, auth: 'on', version: 'x' } }, { op: 'ask' },
    { op: 'me', me: ETHAN }, { op: 'ask' }, { op: 'answer', answer: LIBRARY },
    { op: 'open', album: { id: 'nd-elsewhere', musicBrainzId: 'rel-77' } }, { op: 'open', album: { id: 'nd-dummy', musicBrainzId: 'REL-1' } },
    { op: 'open', album: { id: 'nd-third-has-no-release-here', musicBrainzId: '' } }, { op: 'me', me: null },
    { op: 'open', album: { id: 'x', musicBrainzId: 'rel-3' } }, { op: 'me', me: ETHAN }, { op: 'ask' }, { op: 'answer', answer: LIBRARY },
    { op: 'open', album: { id: 'nd-dummy' } },
  ],
  before: [
    { op: 'me', me: ETHAN }, { op: 'open', album: { id: 'nd-dummy', musicBrainzId: 'rel-1' } }, { op: 'ask' }, { op: 'answer', answer: LIBRARY },
  ],
  //? the last twenty opened before any answer are looked at, each once; logins off opens nothing
  many: [
    { op: 'me', me: ETHAN },
    ...Array.from({ length: 25 }, (_, n) => ({ op: 'open', album: { id: `nd-${n % 23}`, musicBrainzId: n % 4 === 0 ? `REL-${n}` : undefined } })),
    { op: 'ask' },
    { op: 'answer', answer: { ...LIBRARY, new: Array.from({ length: 25 }, (_, n) => entry(n, `Album ${n}`, { navidrome_id: n % 3 ? `nd-${n}` : null, release_mbid: n % 2 ? `rel-${n}` : null })) } },
    { op: 'open', album: { id: 'nd-22' } }, { op: 'open', album: { id: 'nd-1' } },
  ],
}
for (let walk = 0; walk < 6; walk++) {
  const steps = [{ op: 'me', me: ETHAN }]
  for (let n = 0; n < 30; n++) {
    const roll = rand()
    if (roll < 0.08) steps.push({ op: 'me', me: pick([ETHAN, ETHAN, null, { user: 'deadwax', admin: true, auth: 'on' }, { user: 'local', admin: true, auth: 'off' }]) })
    else if (roll < 0.25) steps.push({ op: 'ask' })
    else if (roll < 0.4) {
      const news = Array.from({ length: Math.floor(rand() * 6) }, () => {
        const id = Math.floor(rand() * 8)
        return entry(id, `Album ${id}`, { navidrome_id: rand() < 0.6 ? `nd-${id}` : null, release_mbid: rand() < 0.6 ? (rand() < 0.5 ? `REL-${id}` : `rel-${id}`) : null })
      })
      steps.push({ op: 'answer', answer: { ...LIBRARY, new: news } })
    } else {
      const id = Math.floor(rand() * 8)
      const album = { id: rand() < 0.8 ? `nd-${id}` : `nd-other-${id}` }
      const release = rand()
      if (release < 0.3) album.musicBrainzId = `rel-${id}`
      else if (release < 0.45) album.musicBrainzId = ` REL-${id} `
      else if (release < 0.55) album.musicBrainzId = ''
      steps.push({ op: 'open', album })
    }
  }
  SEEN_TRACES[`walk-${walk}`] = steps
}

/* ===== words ===== */

const section = fs.readFileSync(path.join(UI, 'src/app/LibrarySection.tsx'), 'utf8')
const views = fs.readFileSync(path.join(UI, 'src/app/LibraryViews.tsx'), 'utf8')
const tile = fs.readFileSync(path.join(UI, 'src/app/AlbumTile.tsx'), 'utf8')
const myLibrarySource = fs.readFileSync(path.join(UI, 'src/app/useMyLibrary.ts'), 'utf8')
const read = (source, pattern, what) => {
  const found = pattern.exec(source)
  if (!found) throw new Error(`couldn't read ${what} - the web app's words moved; change this script with them`)
  return found[1]
}
const albumIndexSource = require(path.join(OUT, 'app/albumIndex.js'))

async function main() {
  const store = {}
  for (const [name, steps] of Object.entries(STORE_TRACES)) store[name] = await storeTrace(steps)
  emit('store.json', {
    about: 'app/albumIndex.ts driven a step at a time (list = albumIndex(scope); land/fail = the oldest ask answered, or the newest; tick = the clock moved, ms): after each, the asks made in all, [yours, store] generations, kept lists (an ask\'s one album is ask-N, N counting from 0), their `at` and `truncated` (ask N says truncated when N % 3 == 0). The clock starts at 1000000. Written by ios/scripts/export-library-vectors.cjs.',
    traces: store,
  }, 3)

  const seenTraces = {}
  for (const [name, steps] of Object.entries(SEEN_TRACES)) seenTraces[name] = await seenTrace(steps)
  emit('seen.json', {
    about: 'app/useMyLibrary.ts driven a step at a time (me = who sessionMe() says; ask = askMyLibrary(); answer = the newest ask answered; open = seenAlbum(album)): after each, what POST /me/library/seen was sent and the album_ids still new (null before any answer). Written by ios/scripts/export-library-vectors.cjs.',
    openedKept: Number(read(myLibrarySource, /const OPENED_KEPT = (\d+)/, 'OPENED_KEPT')),
    traces: seenTraces,
  }, 3)

  emit('words.json', {
    about: 'The words and numbers the Swift copies say, read from the web app. Written by ios/scripts/export-library-vectors.cjs.',
    sorts: S.ALBUM_SORTS.filter((sort) => SORTS.includes(sort.id)).map((sort) => [sort.id, sort.label]),
    defaultSort: S.DEFAULT_ALBUM_SORT,
    sameMomentMs: S.SAME_MOMENT_MS,
    indexMin: S.INDEX_MIN,
    otherInitial: S.OTHER_INITIAL,
    dateUnknown: S.DATE_UNKNOWN,
    noYear: S.NO_YEAR,
    freshMs: albumIndexSource.INDEX_FRESH_MS,
    allMusic: F.ALL_MUSIC,
    titles: {
      yours: F.libraryTitle('albums', true), albums: F.libraryTitle('albums', false), store: F.libraryTitle('store', true),
      recent: F.libraryTitle('recent', true),
    },
    allAlbumsRow: F.SIDEBAR_BROWSE.find((item) => item.id === 'store').label,
    emptyLibrary: Y.EMPTY_LIBRARY,
    emptyLibraryHow: Y.EMPTY_LIBRARY_HOW,
    noAlbums: Y.NO_ALBUMS,
    couldntRefresh: read(section, /export const COULDNT_REFRESH = "([^"]+)"/, 'COULDNT_REFRESH'),
    truncated: read(section, /export const TRUNCATED_NOTICE = '([^']+)'/, 'TRUNCATED_NOTICE'),
    findPlaceholder: read(section, /placeholder: '([^']+)'/, 'Find\'s placeholder'),
    sortLabel: read(section, /label: '(Album order)'/, 'the sort picker\'s label'),
    tryAgain: read(section, />\s*(Try again)\s*</, 'Try again'),
    loading: read(section, /class="pl-spinner" aria-label="([^"]+)"/, 'the spinner\'s label'),
    seeAllMusic: read(views, />\s*(See All music)\s*</, 'See All music'),
    newMark: read(tile, /\n\s*(New)<span class="app-visually-hidden">/, 'the New mark'),
    newMarkSpoken: 'New' + read(tile, /<span class="app-visually-hidden">([^<]+)<\/span>/, 'the New mark\'s spoken words'),
    breakGlassUser: require(path.join(OUT, 'lib/signIn.js')).BREAK_GLASS_USER,
  }, 2)

  fs.rmSync(OUT, { recursive: true, force: true })

  if (CHECK) {
    const differ = []
    for (const [name, text] of Object.entries(files)) {
      const at = path.join(FIXTURES, name)
      if (!fs.existsSync(at)) differ.push(`${name} (missing)`)
      else if (fs.readFileSync(at, 'utf8') !== text) differ.push(name)
    }
    if (differ.length) {
      console.log(`The Library's fixtures differ from what the web app's TypeScript answers now: ${differ.join(', ')}.`)
      console.log('Run node ios/scripts/export-library-vectors.cjs, and see what the Swift ports must follow.')
      process.exit(1)
    }
    console.log(`The Library's ${Object.keys(files).length} fixtures match the web app's TypeScript.`)
    return
  }
  fs.mkdirSync(FIXTURES, { recursive: true })
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(FIXTURES, name), text)
  console.log(`Wrote ${Object.keys(files).length} fixtures to ${path.relative(ROOT, FIXTURES)}: ${Object.entries(files).map(([name, text]) => `${name} ${Math.round(text.length / 1024)} KB`).join(', ')}`)
}

main().catch((caught) => {
  console.error(caught && caught.stack)
  process.exit(1)
})
