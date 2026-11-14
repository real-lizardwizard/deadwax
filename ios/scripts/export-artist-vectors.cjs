#!/usr/bin/env node
/**
 * The artists' vectors for the iPhone app (Phase 4, slice 4 - notes/ios-specs/phase4-library.md 2.6 and 5.2): what the
 * web app's own TypeScript answers, written as one fixture the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore
 * (Artists.swift) replay (Tests/DeadwaxCoreTests/ArtistVectorTests.swift) - so the phone sorts, heads, finds and indexes
 * a list of artists, and lines up and plays an artist's albums, exactly as the web does, and a change to the web's
 * rules shows up as a fixture that no longer matches.
 *
 * Compiles, as the sims do, ui/src/lib/shelves.ts (sortArtistsBy, groupArtists, filterArtists, artistOrderFrom and the
 * index), lib/artistPage.ts (artistRows over Navidrome's albums alone, rowLine, playOrder, playsLine, inTurns,
 * albumCountLine, countText, ARTIST_ORDERS), lib/yourLibrary.ts (yourArtists and the empty words), lib/appFrame.ts (the
 * titles) and lib/whose.ts; and reads the few words and numbers that live in components (LibrarySection.tsx's Find
 * placeholder and sort label, ArtistPage.tsx's PREFETCH_AT_ONCE, ARTISTS_KEPT and ARTIST_GONE, persisted.ts's storage
 * key) from their source. Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/artists/artist-vectors.json:
 *
 *   lists      artist lists - fixed awkward names (a leading "The", accents, digits and symbols, other scripts, nameless,
 *              ties, counts missing) and seeded random ones either side of the index's 50 - under both orders: the
 *              order, the groups, the index, and Find's for several words typed (one, "e", keeping 50 or more of the
 *              larger lists, where the index hides only because something is typed)
 *   yours      yourArtists over artists and albums (unknown ids, none, an album twice, an artist with no id)
 *   rows       artistRows(held, null, null) over album lists: the rows, each row's line both ways, playOrder
 *   playOrders playOrder over rows as they come - an album twice, an empty id
 *   playsLine  every albums / in hand / settled / library / personal there is
 *   turns      inTurns driven step by step: what has been started after each settle and stop
 *   words      the words and numbers the Swift copies say - ARTIST_ORDERS and artistOrderFrom over saved values among
 *              them
 *
 * The rows' ties are ICU's localeCompare on the web (foldName(title), then the row's key), which nothing on Linux has:
 * the phone compares folded titles by code unit and keys as ASCII collates. Every row vector here is checked to be one
 * where the two agree - a list that would hold the phone to ICU itself throws, rather than writing a vector the port
 * can't meet (notes/ios.md, "Phase 4, slice 4").
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-artist-vectors.cjs           write the fixture
 *   node ios/scripts/export-artist-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'artists', 'artist-vectors.json')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-artist-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/shelves.ts', 'src/lib/artistPage.ts', 'src/lib/yourLibrary.ts', 'src/lib/appFrame.ts', 'src/lib/whose.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

const S = require(path.join(OUT, 'lib/shelves.js'))
const A = require(path.join(OUT, 'lib/artistPage.js'))
const Y = require(path.join(OUT, 'lib/yourLibrary.js'))
const F = require(path.join(OUT, 'lib/appFrame.js'))
const W = require(path.join(OUT, 'lib/whose.js'))
const owned = require(path.join(OUT, 'lib/owned.js'))

/** One constant out of a component's source, which the exporter can't compile without Preact: `export const NAME = …`. */
function sourceConst(file, name) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(new RegExp(`export const ${name} = (.+)`))
  if (!found) throw new Error(`${file} has no ${name} any more`)
  return JSON.parse(found[1].trim().replace(/^'(.*)'$/, (_, inner) => JSON.stringify(inner)))
}

/** One quoted string that follows `key:` inside a component's source - the first after `after`. */
function sourceText(file, after, key) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const from = text.indexOf(after)
  if (from < 0) throw new Error(`${file} has no ${after} any more`)
  const found = text.slice(from).match(new RegExp(`${key}: '([^']*)'`))
  if (!found) throw new Error(`${file}'s ${after} has no ${key} any more`)
  return found[1]
}

/* ===== seeded randomness ===== */

let seed = 4141
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const cp = (...points) => String.fromCodePoint(...points)

/* ===== the lists ===== */

/** Names that each test something: the article, accents, case, digits and symbols (`#`), other scripts, ligatures and
 *  fullwidth (NFKD), brackets (foldName drops the aside), "&", spaces, nothing. */
const AWKWARD = [
  'The Beatles', 'Beatles', 'beatles', 'Björk', 'Bjork', 'ABBA', 'a-ha', 'AC/DC', '!!!', '2Pac', '50 Cent', '808 State',
  'The The', 'The', 'the the', 'La Dispute', 'Sigur Rós', 'Ólafur Arnalds', 'Æthenor', 'Ølafur', 'Øyvind',
  '宇多田ヒカル', 'BTS (방탄소년단)', '(Untitled)', 'Мумий Тролль', 'Ἀφροδίτη', 'Sinéad O’Connor', "Guns N' Roses",
  'Simon & Garfunkel', 'Simon and Garfunkel', '&', cp(0x2163) + ' Play', cp(0xfb01) + 've', 'Ｆｕｌｌ', '  Spaces  ',
  'Zola Jesus', 'zZz', 'Ásgeir', 'Édith Piaf', 'edith piaf', '...And You Will Know Us', 'Ã', '',
]

function awkwardList() {
  return AWKWARD.map((name, at) => {
    const artist = { id: `ar-${at}`, name }
    //? counts with ties, a zero, and some missing (Navidrome leaves out what it doesn't count)
    if (at % 7 !== 3) artist.albumCount = [1, 3, 3, 12, 0, 2, 7][at % 7]
    if (at % 5 === 0) artist.coverArt = `ar-ar-${at}`
    return artist
  })
}

const WORDS = ['Black', 'Sabbath', 'Low', 'Cure', 'Portishead', 'Massive', 'Attack', 'Air', 'Blur', 'Pulp', 'Suede',
  'Orbital', 'Slowdive', 'Ride', 'Lush', 'Moby', 'Tricky', 'Burial', 'Bonobo', 'Caribou', 'Mogwai', 'Yo La Tengo']
const DECOR = ['Ö', 'é', 'ñ', 'ç', 'Å', 'ø', 'ß', '&', '!', '-', '.', "'", '(Live)', '[Remix]']
const SCRIPTS = ['坂本龍一', 'ΟΔΟΣ', 'Кино', 'שלום', 'نور', 'ไทย', '방탄', 'カネコアヤノ']

function randomName() {
  const roll = rand()
  if (roll < 0.06) return ''
  if (roll < 0.14) return pick(SCRIPTS) + (rand() < 0.5 ? '' : ` ${pick(WORDS)}`)
  if (roll < 0.22) return `${between(1, 999)} ${pick(WORDS)}`
  if (roll < 0.28) return `${pick(['!', '#', '$', '(', '.', '"'])}${pick(WORDS)}`
  const words = Array.from({ length: between(1, 3) }, () => pick(WORDS))
  let name = (rand() < 0.2 ? 'The ' : '') + words.join(' ')
  if (rand() < 0.3) name += ` ${pick(DECOR)}`
  if (rand() < 0.15) name = name.toUpperCase()
  if (rand() < 0.15) name = name.toLowerCase()
  return name
}

function randomList(size, tag) {
  return Array.from({ length: size }, (_, at) => {
    const artist = { id: `${tag}-${at}`, name: randomName() }
    if (rand() < 0.9) artist.albumCount = between(0, 6)
    return artist
  })
}

/** What a list draws under one order: the order, the groups and the index (whether it is drawn or not). */
function under(list, order) {
  const sorted = S.sortArtistsBy(list, order)
  const groups = S.groupArtists(sorted, order)
  return {
    ids: sorted.map((artist) => artist.id),
    groups: groups.map((group) => ({ key: group.key, label: group.label, ids: group.items.map((artist) => artist.id) })),
    index: S.indexEntries(groups, order).map((entry) => ({ label: entry.label, aria: entry.aria, group: entry.group })),
    showsIndex: S.showsIndex(order, sorted.length, ''),
    count: A.countText(sorted.length, 'artist', 'artists'),
  }
}

/** Find's, typed over one order: what it keeps, its groups, whether the index shows, the count, the no-match words. */
function finds(list, order, typed) {
  const sorted = S.sortArtistsBy(list, order)
  const found = S.finding(typed) ? S.filterArtists(sorted, typed) : sorted
  const groups = S.groupArtists(found, order)
  return {
    typed,
    finding: S.finding(typed),
    ids: found.map((artist) => artist.id),
    heads: groups.map((group) => group.label),
    sizes: groups.map((group) => group.items.length),
    showsIndex: S.showsIndex(order, sorted.length, typed),
    count: S.finding(typed) ? S.filteredCountText(found.length, sorted.length, 'artist', 'artists') : A.countText(sorted.length, 'artist', 'artists'),
    noMatch: S.noMatchText('artists', typed),
  }
}

const TYPED_FIXED = ['', '   ', 'the', 'beatles', 'BEATLES the', 'bjork', 'björk', 'ac dc', 'and', '&', 'sigur ros', 'o',
  '50', '方', 'ヒカル', '방탄', 'untitled', 'zzz zola', 'nothing like it', ' piaf  edith ', 'ö']

function listVectors() {
  const cases = [{ name: 'awkward', list: awkwardList(), typed: TYPED_FIXED }]
  cases.push({ name: 'empty', list: [], typed: ['', 'x'] })
  cases.push({ name: 'one', list: [{ id: 'solo', name: 'Portishead', albumCount: 2 }], typed: ['', 'port', 'x'] })
  cases.push({
    name: 'ties',
    list: [
      { id: 't1', name: 'Low', albumCount: 4 }, { id: 't2', name: 'low', albumCount: 4 }, { id: 't3', name: 'LOW', albumCount: 9 },
      { id: 't4', name: 'Lów' }, { id: 't5', name: 'The Low', albumCount: 4 }, { id: 't6', name: 'Low', albumCount: 0 },
      { id: 't7', name: '#Low', albumCount: 4 }, { id: 't8', albumCount: 4 }, { id: 't9', name: 'Low (Band)', albumCount: -1 },
    ],
    typed: ['', 'low', 'band'],
  })
  for (const size of [2, 49, 50, 51, 64, 150]) {
    const list = randomList(size, `r${size}`)
    const typed = ['', ...Array.from({ length: 4 }, () => {
      const name = list[Math.floor(rand() * list.length)].name
      const cut = Math.max(1, Math.floor(name.length / 2))
      return rand() < 0.5 ? name.slice(0, cut) : name.slice(cut)
    }), pick(WORDS).toLowerCase(), 'e']
    cases.push({ name: `random ${size}`, list, typed })
  }
  return cases.map(({ name, list, typed }) => ({
    name,
    list,
    name_order: under(list, 'name'),
    albums_order: under(list, 'albums'),
    finds: typed.flatMap((each) => [{ order: 'name', ...finds(list, 'name', each) }, { order: 'albums', ...finds(list, 'albums', each) }]),
  }))
}

/* ===== your artists ===== */

function yourVectors() {
  const artists = [
    { id: 'ar-1', name: 'Portishead', albumCount: 5, coverArt: 'ar-ar-1', musicBrainzId: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11' },
    { id: 'ar-2', name: 'Massive Attack', albumCount: 7 },
    { id: 'ar-3', name: 'Tricky' },
    { id: 'ar-4', name: 'Björk', albumCount: 10, coverArt: 'ar-ar-4' },
  ]
  const albums = (...pairs) => pairs.map(([id, artistId]) => (artistId === undefined ? { id, name: id } : { id, name: id, artistId }))
  return [
    { name: 'some of each', artists, albums: albums(['al-1', 'ar-1'], ['al-2', 'ar-1'], ['al-3', 'ar-4'], ['al-4', 'ar-1']) },
    { name: 'none of yours', artists, albums: [] },
    { name: 'no artists', artists: [], albums: albums(['al-1', 'ar-1']) },
    { name: 'albums naming nobody listed', artists, albums: albums(['al-1', 'ar-9'], ['al-2', ''], ['al-3', undefined], ['al-4', 'ar-3']) },
    { name: 'an album twice', artists, albums: albums(['al-1', 'ar-2'], ['al-1', 'ar-2'], ['al-5', 'ar-2']) },
    { name: 'an artist twice', artists: [...artists, { id: 'ar-1', name: 'Portishead (again)', albumCount: 1 }], albums: albums(['al-1', 'ar-1']) },
    { name: 'an artist with no id', artists: [...artists, { id: '', name: 'Nobody', albumCount: 2 }], albums: albums(['al-1', ''], ['al-2', 'ar-2'], ['al-3', '']) },
  ].map((each) => ({ ...each, yours: Y.yourArtists(each.artists, each.albums) }))
}

/* ===== an artist's rows ===== */

/** ICU's order and the code unit's: the phone has only the second (see the header), so a vector must not need the first. */
function sign(n) { return n < 0 ? -1 : n > 0 ? 1 : 0 }
function units(a, b) { return a < b ? -1 : a > b ? 1 : 0 }
//? the phone's order for a row's key: as ASCII collates - letters by their case folded, digits before them, the
//? lowercase first only when nothing else differs
function asciiCollate(a, b) {
  const lower = units(a.toLowerCase(), b.toLowerCase())
  if (lower) return lower
  for (let at = 0; at < Math.min(a.length, b.length); at++) {
    if (a[at] !== b[at]) return a[at] === a[at].toLowerCase() ? -1 : 1
  }
  return units(a, b)
}

function checkTies(name, rows) {
  for (const first of rows) {
    for (const second of rows) {
      if (first === second || first.year !== second.year) continue
      const a = owned.foldName(first.title), b = owned.foldName(second.title)
      if (sign(a.localeCompare(b)) !== units(a, b)) throw new Error(`${name}: "${a}" and "${b}" order differently under ICU and by code unit`)
      if (a === b && sign(first.key.localeCompare(second.key)) !== asciiCollate(first.key, second.key)) {
        throw new Error(`${name}: keys ${first.key} and ${second.key} order differently under ICU and as ASCII`)
      }
    }
  }
}

const TITLES = ['Dummy', 'dummy', 'Dümmy', 'The Dummy', 'Third', 'Portishead', 'Roseland NYC Live', 'Roseland NYC Live (Deluxe)',
  'Glory Times', 'Ålbum', 'Album', 'album 2', 'Album 10', '', 'Ä', 'Zebra', '3 Songs', '...Baby One More Time']
const YEARS = [1994, 1994, 1997, 1998, 2008, 2008, 0, undefined, 999, 10000, -3]
const ID_CHARS = 'abcABC0129xyzXYZ'

function randomAlbums(size) {
  return Array.from({ length: size }, () => {
    const id = Array.from({ length: between(1, 4) }, () => pick(ID_CHARS.split(''))).join('')
    const album = { id, name: pick(TITLES) }
    const year = pick(YEARS)
    if (year !== undefined) album.year = year
    if (rand() < 0.6) album.coverArt = `al-${id}`
    if (rand() < 0.5) album.starred = rand() < 0.15 ? '' : '2026-10-01T12:00:00Z'
    return album
  })
}

function rowVectors() {
  const cases = [
    { name: 'none', held: [] },
    {
      name: 'Portishead',
      held: [
        { id: 'al-1', name: 'Dummy', year: 1994, coverArt: 'al-1', musicBrainzId: '76df3287-6cda-33eb-8e9a-044b5e15ffdd', starred: '2026-10-01T12:00:00Z' },
        { id: 'al-2', name: 'Third', year: 2008, coverArt: 'al-2' },
        { id: 'al-3', name: 'Portishead', year: 1997 },
        { id: 'al-4', name: 'Roseland NYC Live', year: 1998, starred: '2026-10-02T12:00:00Z' },
        { id: 'al-5', name: 'Dummy', year: 1994, coverArt: 'al-5' },
      ],
    },
    {
      name: 'ties and the undated',
      held: [
        { id: 'B1', name: 'Dummy', year: 1994 }, { id: 'a1', name: 'dummy', year: 1994 }, { id: 'A1', name: 'Dümmy', year: 1994 },
        { id: 'b1', name: 'DUMMY', year: 1994 }, { id: 'a10', name: 'Dummy', year: 1994 }, { id: 'a2', name: 'Dummy', year: 1994 },
        { id: 'aB', name: 'The Dummy', year: 1994 }, { id: 'Ab', name: 'Dummy', year: 1994 },
        { id: 'u1', name: 'Zebra' }, { id: 'u2', name: 'Album', year: 0 }, { id: 'u3', name: 'Ålbum', year: -3 }, { id: 'u4' },
        { id: 'old', name: 'Old', year: 999 }, { id: 'far', name: 'Far', year: 10000 }, { id: 'new', name: 'New', year: 2026 },
      ],
    },
    {
      name: 'twice, and other scripts in years of their own',
      held: [
        { id: 'x1', name: 'Dummy', year: 1994 }, { id: 'x1', name: 'Dummy again', year: 2000 },
        { id: 'x2', name: '坂本龍一', year: 1978 }, { id: 'x3', name: 'Кино', year: 1988, starred: '' },
        { id: 'x4', name: 'Æther', year: 2001 }, { id: 'x5', name: 'Øyvind', year: 2002, coverArt: '' },
      ],
    },
  ]
  for (const size of [1, 2, 8, 30]) cases.push({ name: `random ${size}`, held: randomAlbums(size) })
  return cases.map(({ name, held }) => {
    const rows = A.artistRows(held, null, null)
    checkTies(name, rows)
    return {
      name,
      held,
      rows: rows.map((row) => ({
        key: row.key, title: row.title, year: row.year, albumId: row.albumId, coverArt: row.coverArt, yours: row.yours,
        line: A.rowLine(row, false), personalLine: A.rowLine(row, true),
      })),
      playOrder: A.playOrder(rows),
    }
  })
}

/** playOrder over rows as they come, not only as artistRows makes them: each album once, in order, an empty id none. */
function playOrderVectors() {
  return [[], ['a'], ['a', 'b', 'a', '', 'c', 'b'], ['', ''], ['x', 'x', 'x'], ['b', 'a', 'B', 'a']]
    .map((albumIds) => ({ albumIds, playOrder: A.playOrder(albumIds.map((albumId) => ({ albumId }))) }))
}

/* ===== the line under Play ===== */

function playsVectors() {
  const out = []
  for (const albums of [0, 1, 2, 5]) {
    for (const inHand of [0, 1, 2, 5]) {
      for (const settled of [false, true]) {
        for (const library of ['asking', 'done', 'failed']) {
          for (const personal of [false, true]) out.push({ albums, inHand, settled, library, personal, text: A.playsLine(albums, inHand, settled, library, personal) })
        }
      }
    }
  }
  return out
}

/* ===== inTurns, step by step ===== */

/** inTurns over `count` items `limit` at a time, driven by `script`: each step settles the n-th of those started and not
 *  yet settled (`ok` resolving, else rejecting), or stops it (`going` false from then). After the start and after each
 *  step, every item started so far, in the order started. */
async function turnTrace(name, count, limit, script, goingAtStart = true) {
  const items = Array.from({ length: count }, (_, at) => at)
  const started = []
  const waiting = []
  let going = goingAtStart
  const flush = () => new Promise((done) => setTimeout(done, 0))
  A.inTurns(items, limit, (item) => {
    started.push(item)
    return new Promise((resolve, reject) => waiting.push({ item, resolve, reject }))
  }, () => going)
  await flush()
  const steps = [{ op: 'begin', started: [...started] }]
  for (const step of script) {
    if (step === 'stop') {
      going = false
      steps.push({ op: 'stop', started: [...started] })
      continue
    }
    if (step === 'go') {
      going = true
      steps.push({ op: 'go', started: [...started] })
      continue
    }
    const [which, ok] = step
    const settling = waiting.splice(which, 1)[0] //? -1: the last started
    if (!settling) throw new Error(`${name}: nothing waiting at ${which}`)
    if (ok) settling.resolve(settling.item)
    else settling.reject(new Error('no'))
    await flush()
    steps.push({ op: ok ? 'answered' : 'failed', item: settling.item, started: [...started] })
  }
  return { name, count, limit, goingAtStart, steps }
}

async function turnVectors() {
  const inOrder = (n, ok = true) => Array.from({ length: n }, () => [0, ok])
  const traces = [
    await turnTrace('ten, four at a time, in order', 10, 4, inOrder(10)),
    await turnTrace('ten, four at a time, the last started settling first', 10, 4, Array.from({ length: 10 }, (_, at) => [-1, at % 2 === 0])),
    await turnTrace('none', 0, 4, []),
    await turnTrace('one', 1, 4, [[0, true]]),
    await turnTrace('three under four', 3, 4, [[2, false], [0, true], [0, true]]),
    await turnTrace('exactly four', 4, 4, inOrder(4)),
    await turnTrace('five', 5, 4, [[3, true], [0, false], [2, true], [0, true], [0, true]]),
    await turnTrace('a limit of 0 is one', 3, 0, inOrder(3)),
    await turnTrace('a limit below 0 is one', 3, -2, inOrder(3, false)),
    await turnTrace('a limit past the items', 3, 10, inOrder(3)),
    await turnTrace('every one failing', 6, 2, inOrder(6, false)),
    await turnTrace('stopped midway', 9, 3, [[0, true], 'stop', [0, true], [0, false], [0, true]]),
    await turnTrace('stopped, then going again', 9, 3, [[1, true], 'stop', [0, true], 'go', [0, true], [0, true], [0, true]]),
    await turnTrace('never going', 5, 4, [], false),
  ]
  for (let at = 0; at < 6; at++) {
    const count = between(0, 14)
    const limit = between(-1, 6)
    const script = []
    let open = Math.min(count, Math.max(1, limit))
    let going = true
    let started = open
    while (open > 0) {
      if (rand() < 0.08) {
        going = !going
        script.push(going ? 'go' : 'stop')
        continue
      }
      script.push([Math.floor(rand() * open), rand() < 0.75])
      open--
      if (going && started < count) {
        open++
        started++
      }
    }
    traces.push(await turnTrace(`random ${at}`, count, limit, script))
  }
  return traces
}

/* ===== the words ===== */

function wordVectors() {
  return {
    orders: A.ARTIST_ORDERS.map((order) => ({ id: order.id, label: order.label })),
    saved: [null, '', 'name', 'albums', 'Albums', 'albums ', 'newest', 'most', 'Name'].map((saved) => ({ saved, order: S.artistOrderFrom(saved) })),
    storageKey: (() => {
      const text = fs.readFileSync(path.join(UI, 'src/state/persisted.ts'), 'utf8')
      const found = text.match(/playerArtistOrder: '([^']+)'/)
      if (!found) throw new Error('persisted.ts has no playerArtistOrder any more')
      return found[1]
    })(),
    titles: {
      artists: F.libraryTitle('artists', false),
      yourArtists: F.libraryTitle('artists', true),
      allArtists: F.libraryTitle('storeArtists', true),
      allMusic: F.ALL_MUSIC,
    },
    find: sourceText('src/app/LibrarySection.tsx', 'function ArtistSection', 'placeholder'),
    sortLabel: sourceText('src/app/LibrarySection.tsx', 'function ArtistSection', 'label'),
    noArtists: Y.NO_ARTISTS,
    noArtistsOfYours: Y.NO_ARTISTS_OF_YOURS,
    emptyLibraryHow: Y.EMPTY_LIBRARY_HOW,
    noMatch: ['dumy', '  the  ', '“quoted”'].map((typed) => ({ typed, text: S.noMatchText('artists', typed) })),
    counts: [null, 0, 1, 2, 3012].map((count) => ({ count, text: A.countText(count, 'artist', 'artists') })),
    albumCountLine: [null, 0, 1, 2, 12, -1].flatMap((count) => [
      { count, place: null, text: A.albumCountLine(count) },
      { count, place: W.IN_THE_STORE, text: A.albumCountLine(count, W.IN_THE_STORE) },
      { count, place: '', text: A.albumCountLine(count, '') },
    ]),
    inYourLibrary: W.IN_YOUR_LIBRARY,
    inTheCollection: W.IN_THE_STORE,
    artistGone: sourceConst('src/app/ArtistPage.tsx', 'ARTIST_GONE'),
    prefetchAtOnce: sourceConst('src/app/ArtistPage.tsx', 'PREFETCH_AT_ONCE'),
    artistsKept: sourceConst('src/app/ArtistPage.tsx', 'ARTISTS_KEPT'),
    indexMin: S.INDEX_MIN,
  }
}

/* ===== writing ===== */

async function vectors() {
  return {
    made_from: 'ui/src/lib/shelves.ts, lib/artistPage.ts, lib/yourLibrary.ts, lib/appFrame.ts and lib/whose.ts (compiled); LibrarySection.tsx, ArtistPage.tsx and persisted.ts (read)',
    words: wordVectors(),
    lists: listVectors(),
    yours: yourVectors(),
    rows: rowVectors(),
    playOrders: playOrderVectors(),
    playsLine: playsVectors(),
    turns: await turnVectors(),
  }
}

/** JSON with every character outside ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[\u0080-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

vectors().then((value) => {
  const made = say(value)
  if (CHECK) {
    const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
    if (committed !== made) {
      console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-artist-vectors.cjs, then port the change to DeadwaxCore's Artists.swift and see ArtistVectorTests pass`)
      process.exit(1)
    }
    console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
  } else {
    fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
    fs.writeFileSync(FIXTURE, made)
    console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
  }
}, (error) => {
  console.error(error)
  process.exit(1)
})
