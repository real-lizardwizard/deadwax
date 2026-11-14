#!/usr/bin/env node
/**
 * Search's vectors for the iPhone app (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 2 and 5.2): what the web
 * app's own TypeScript answers, written as one fixture the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore
 * (SearchReading.swift, SearchList.swift, Owned.swift) replay (Tests/DeadwaxCoreTests/SearchVectorTests.swift) - so the
 * phone reads the box, says whose a row is, makes the sections and Top results, and says every line exactly as the web
 * does, and a change to the web's rules shows up as a fixture that no longer matches.
 *
 * Compiles, as ui/test/searchList.sim.cjs does, ui/src/lib/searchList.ts with what it imports - lib/searchQuery.ts
 * (artistNames, searchQuery), lib/searchResults.ts (albumsToPrefetch, songIndex, artistLine, searchWords), lib/songs.ts
 * (titleKey), lib/whose.ts (navidromeYours, libraryPlace), lib/owned.ts (foldName, buildOwnedIndex and its lookups) -
 * and reads the few numbers and words that live elsewhere (api.ts's SEARCH_COUNTS, Search.tsx's placeholder, "Check the
 * spelling..." and More's words) from their source. Writes
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-vectors.json:
 *
 *   numbers   the counts, caps, pauses and limits
 *   words     the hint's neighbours, the busy words, countWords, libraryWords, viewWords, nothingWords, artistLine
 *   fold      foldName and titleKey over hard names and titles (asides of every kind, accents, ligatures, Final Sigma,
 *             JavaScript's white space, the long s)
 *   names     artistNames over lists of names (its keys and the spellings kept)
 *   readings  searchQuery over texts and name lists: the kind, the artist, the title, the query
 *   owned     buildOwnedIndex over folder lists, and every lookup (ownedForRelease, ownedForGroup)
 *   whose     navidromeYours, albumYours, songYours, artistYours and libraryPlace over the marks' combinations
 *   prefetch  albumsToPrefetch and songIndex
 *   cases     whole searches - a library answer, the full artist list, the folders, the marks, the words - each with
 *             what the web's functions make of it: the reading, the pool (each row's key, holder and position), every
 *             candidate's tier, Top results' three, the sections as a phone's All view caps them and in full, every
 *             row's line in a section and in Top results, the words said, the albums asked for first
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-search-vectors.cjs           write the fixture
 *   node ios/scripts/export-search-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'search', 'search-vectors.json')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchList.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/searchList.js'))
const Q = require(path.join(OUT, 'lib/searchQuery.js'))
const R = require(path.join(OUT, 'lib/searchResults.js'))
const S = require(path.join(OUT, 'lib/songs.js'))
const W = require(path.join(OUT, 'lib/whose.js'))
const O = require(path.join(OUT, 'lib/owned.js'))

/** A line of a component's source, which the exporter can't compile without Preact - the first match's group. */
function sourceMatch(file, pattern) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(pattern)
  if (!found) throw new Error(`${file} no longer has ${pattern}`)
  return found[1]
}

/* ===== seeded randomness ===== */

let seed = 5151
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p
const cp = (...points) => String.fromCodePoint(...points)

/* ===== the numbers and the words ===== */

function numbers() {
  const counts = sourceMatch('src/player/api.ts', /export const SEARCH_COUNTS = (\{[^}]*\})/)
  const all = JSON.parse(counts.replace(/(\w+):/g, '"$1":'))
  return {
    searchCounts: all,
    chipCounts: L.CHIP_LIBRARY_COUNTS,
    topResults: L.TOP_RESULTS.phone,
    preview: Object.fromEntries(L.KINDS.map((kind) => [kind, L.PREVIEW.phone[kind][0]])),
    albumsPrefetched: R.SONG_ALBUMS_PREFETCHED,
    librarySettleMs: Q.LIBRARY_SETTLE_MS,
    musicBrainzSettleMs: Q.MUSICBRAINZ_SETTLE_MS,
    musicBrainzMinChars: Q.MUSICBRAINZ_MIN_CHARS,
    maxCharacters: Q.SEARCH_MAX_CHARS,
    variousArtists: Q.VARIOUS_ARTISTS,
    kinds: L.KINDS,
  }
}

function words() {
  const personal = R.searchWords(true), plain = R.searchWords(false)
  const countsList = [{}, { artists: 1 }, { albums: 2 }, { songs: 1 }, { artists: 2, albums: 1, songs: 11 }, { artists: 0, albums: 0, songs: 3 }, { artists: 5, albums: 8, songs: 12 }]
  const texts = ['dummy', 'glory box', '\u201cquoted\u201d', 'Bj\u00f6rk']
  return {
    prompt: sourceMatch('src/app/Search.tsx', /placeholder="([^"]+)"/),
    label: plain.label,
    labelPersonal: personal.label,
    searching: plain.searching(false),
    searchingPersonal: personal.searching(false),
    checkSpelling: sourceMatch('src/app/Search.tsx', /<p class="app-search-empty">(Check the spelling[^<]*)<\/p>/),
    moreFromLibrary: sourceMatch('src/app/Search.tsx', /personal \? 'More from the collection' : '(More from your library)'/),
    moreFromCollection: sourceMatch('src/app/Search.tsx', /personal \? '(More from the collection)' : 'More from your library'/),
    topResults: sourceMatch('src/app/Search.tsx', />(Top results)<\/h2>/),
    inYourLibrary: W.IN_YOUR_LIBRARY,
    inTheCollection: W.IN_THE_STORE,
    counts: countsList.map((counts) => ({
      counts, said: L.countWords(counts), library: L.libraryWords(counts, false), libraryPersonal: L.libraryWords(counts, true),
    })),
    views: ['all', 'artists', 'albums', 'songs'].map((view) => ({
      view, said: L.viewWords(view), nothing: texts.map((text) => ({ text, said: L.nothingWords(view, text) })),
    })),
    artistLine: [null, 0, 1, 2, 12, -1].flatMap((count) => [false, true].flatMap((personal) => [false, true].map((top) => ({
      count, personal, top, said: R.artistLine(count, personal, top),
    })))),
  }
}

/* ===== folding ===== */

const HARD = [
  '', 'Roads', 'roads', 'ROADS', 'Roads (live)', 'Roads (Live at Roseland NYC)', 'Roads (lively)', 'Roads (live)(mono)',
  'Roads [Mono]', 'Roads ( mono )', 'Roads (monophonic)', 'Roads (Stereo)', 'Roads (stereo mix)', 'Roads (2015 Remaster)',
  'Roads (Remastered 2015)', 'Roads (remastered)', 'Roads (remasters)', 'Roads (Remastereds)', 'Roads (unremastered)',
  'Roads (re-master)', 'Roads (Remaster', 'Roads Remaster)', 'Roads (Max Cooper remix)', 'Roads [Deluxe]', 'Roads (live]',
  'Roads [live)', '(live) Roads', '  (live)  Roads  ', 'Roads\u00a0(live)', 'Roads\u2003(Live)', 'Roads\u2028(live)',
  'Roads (\u017fTEREO)', 'Roads (rema\u017fter)', 'Roads (LIVE_1)', 'Roads (live1)', 'Roads (live-1)', 'Roads (live (at) x)',
  'Glory Box', 'Glory Box (stereo )', 'Sour Times (Live at Roseland NYC)', 'Sour Times (Airbus Reconstruction)',
  'Don\u2019t Stop', "Don't Stop", 'Don`t Stop', 'Don\u00b4t Stop', 'Simon & Garfunkel', 'Simon and Garfunkel',
  'The National', 'the the', 'The', 'Thelonious', 'Bj\u00f6rk', 'BJ\u00d6RK', 'Sigur R\u00f3s', '\u00c1g\u00e6tis byrjun', '\u00c6thenor', 'R\u00f8yksopp',
  '\u03a3\u0399\u0393\u039c\u0391', '\u039f\u0394\u039f\u03a3', '\ufb01ve', '\u2160\u2161', '\uff2d\uff4f\uff4e\uff4f', 'AC/DC', '!!!', '...And Justice for All',
  '\u0130stanbul', 'Stra\u00dfe', '\u00e9t\u00e9 (live)', 'Mrs. Robinson', 'Hey Jude [Remastered 2009]', 'Live Forever',
  'Live (live)', '(stereo)', 'Remaster', '\ufeffRoads\ufeff', 'Roads\u0085', cp(0x1F3B5) + ' Roads', 'Roads (live\u0301)',
]

function fold() {
  return HARD.map((text) => ({ text, foldName: O.foldName(text), titleKey: S.titleKey(text) }))
}

/* ===== names and readings ===== */

const NAME_LISTS = [
  [],
  ['Portishead'],
  ['Portishead', 'The National', 'Bj\u00f6rk'],
  ['Portishead', 'portishead', ' Portishead '],
  ['The National', 'National'],
  ['Massive Attack', 'Mass', 'Attack'],
  ['Simon & Garfunkel'],
  ['Various Artists', 'VA'],
  ['Sigur R\u00f3s', 'Sigur Ros'],
  ['', null, '   ', 'Ye', 'Kanye West'],
  ['Death Cab for Cutie', 'Cutie', 'Death'],
  ['AC/DC', '!!!'],
]

function names() {
  return NAME_LISTS.map((list) => {
    const map = Q.artistNames(list)
    return { names: list, entries: [...map.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)) }
  })
}

const TEXTS = [
  '', '   ', 'portishead', 'Portishead', 'PORTISHEAD', 'portishead dummy', 'dummy portishead', 'portishead - dummy',
  'dummy \u2013 portishead', 'portishead : dummy', 'portishead -', '- portishead', 'portishead | dummy | x', 'portishead \u00b7 third',
  'the national boxer', 'national boxer', 'boxer the national', 'national', 'bjork homogenic', 'bj\u00f6rk', 'BJORK',
  'massive attack mezzanine', 'mass attack', 'attack mass', 'mezzanine massive attack', 'simon and garfunkel bookends',
  'simon & garfunkel', 'va now', 'various artists', 'now va', 'va', 'sigur ros', 'sigur r\u00f3s \u00e1g\u00e6tis byrjun',
  'death cab for cutie', 'cutie death', 'roads', 'glory box', 'por', 'po', 'portishead\u00a0dummy',
  'portishead\u3000third', 'portishead\tdummy\n', '\u201cdummy\u201d', 'du"mmy portishead', 'back\\slash portishead', 'ye',
  'kanye west donda', 'donda ye', 'ac/dc back in black', '!!! myth takes', 'portishead portishead',
  //? separators a longer name can't take in: before a title with the artist at the end, after one with them first
  '- dummy portishead', '-- : dummy portishead', '| third | portishead', 'portishead dummy -', 'portishead third : |',
]

function readings() {
  const out = []
  for (const list of NAME_LISTS) {
    for (const text of TEXTS) out.push({ names: list, text, plan: Q.searchQuery(text, list) })
  }
  return out
}

/* ===== the folders ===== */

const FOLDER_LISTS = [
  [],
  [{ path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_mbid: 'rel-dummy', release_group_mbid: 'rg-dummy', albumartist_mbids: ['mb-p'] }],
  [
    { path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_mbid: 'rel-dummy', release_group_mbid: 'rg-dummy', yours: true },
    { path: 'Portishead/Dummy (2014)', artist: 'Portishead', album: 'Dummy', release_mbid: 'rel-dummy', release_group_mbid: 'rg-dummy', yours: false },
    { path: 'Portishead/Third', artist: 'Portishead', album: 'Third', release_mbid: 'rel-third', yours: false },
    { path: 'Portishead/Roseland', artist: 'Portishead', album: 'Roseland NYC Live', release_group_mbid: 'rg-roseland' },
    { path: 'Unknown/Untitled', artist: 'Bj\u00f6rk', album: 'Homogenic' },
    { path: 'Unknown/Untitled 2', artist: 'Bjork', album: 'Homogenic (Deluxe)' },
    { path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_mbid: 'rel-dummy', release_group_mbid: 'rg-dummy', yours: true },
  ],
  [
    { path: 'A/1', artist: ' The National ', album: 'Boxer', release_mbid: '', release_group_mbid: '' },
    { path: 'A/2', artist: 'The National', album: 'Boxer', year: 2007 },
    { path: 'A/3', artist: '', album: 'Untitled' },
    { path: 'A/4', album: 'No artist', yours: true },
  ],
]

function ownedVectors() {
  return FOLDER_LISTS.map((albums) => {
    const index = O.buildOwnedIndex(albums)
    const paths = (list) => list.map((album) => album.path)
    const releases = ['rel-dummy', 'rel-third', 'rel-none', '', null]
    const groups = [
      { groupId: 'rg-dummy' }, { groupId: 'rg-roseland' }, { groupId: 'rg-none' }, { groupId: null },
      { groupId: 'rg-none', releaseIds: ['rel-third'] }, { groupId: 'rg-dummy', releaseIds: ['rel-dummy', 'rel-third'] },
      { groupId: 'rg-none', title: 'Homogenic', artists: ['Bj\u00f6rk', 'Bjork', 'Bj\u00f6rk', null, ''] },
      { groupId: 'rg-none', title: 'Boxer', artists: ['The National'] },
      { groupId: 'rg-none', title: 'Untitled', artists: [''] },
      { groupId: 'rg-dummy', title: 'Homogenic', artists: ['Bj\u00f6rk'] },
      //? a folder with ids is never a guess by its name
      { groupId: 'rg-none', title: 'Third', artists: ['Portishead'] },
      { groupId: 'rg-none', title: 'Dummy', artists: ['Portishead'] },
    ]
    return {
      albums,
      artists: [...new Set(albums.map((album) => (album.artist ?? '').trim()).filter(Boolean))],
      total: index.total,
      releases: releases.map((id) => ({ id, held: paths(O.ownedForRelease(index, id)) })),
      groups: groups.map((query) => {
        const found = O.ownedForGroup(index, query)
        return { query, held: paths(found.held), guessed: paths(found.guessed) }
      }),
    }
  })
}

/* ===== the library ===== */

const STAR = '2026-01-02T03:04:05Z'
const P = { id: 'ar-p', name: 'Portishead', albumCount: 3, coverArt: 'ar-p', musicBrainzId: 'mb-p' }
const N = { id: 'ar-n', name: 'The National', albumCount: 8, coverArt: 'ar-n' }
const B = { id: 'ar-b', name: 'Bj\u00f6rk', albumCount: 1 }
const dummy = { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', artistId: 'ar-p', year: 1994, musicBrainzId: 'rel-dummy', coverArt: 'al-dummy' }
const third = { id: 'nd-third', name: 'Third', artist: 'Portishead', artistId: 'ar-p', year: 2008, musicBrainzId: 'rel-third', coverArt: 'al-third' }
const selfTitled = { id: 'nd-self', name: 'Portishead', artist: 'Portishead', artistId: 'ar-p', year: 1997, musicBrainzId: 'rel-self' }
const boxer = { id: 'nd-boxer', name: 'Boxer', artist: 'The National', artistId: 'ar-n', year: 2007, starred: STAR }
const homogenic = { id: 'nd-homo', name: 'Homogenic', artist: 'Bj\u00f6rk', artistId: 'ar-b', year: 0 }
const song = (id, title, album, extra = {}) => ({
  id, title, artist: album.artist, artistId: album.artistId, album: album.name, albumId: album.id, coverArt: album.coverArt, ...extra,
})
const roads = song('s-roads', 'Roads', dummy), glory = song('s-glory', 'Glory Box', dummy), sour = song('s-sour', 'Sour Times', dummy)
const roadsLive = song('s-roads-live', 'Roads (live)', selfTitled)
const machine = song('s-machine', 'The Rip', third)
const fake = song('s-fake', 'Fake Empire', boxer)
const joga = song('s-joga', 'J\u00f3ga', homogenic)
const loose = { id: 's-loose', title: 'Roads', artist: 'Portishead' }
const strayArtist = { id: 's-stray', title: 'Glory Box', artist: 'Portishead', artistId: 'ar-elsewhere', album: 'Glory Box (single)', albumId: 'nd-single' }
const withSongs = (album, songs) => ({ ...album, song: songs })

const lib = (artists = [], albums = [], songs = []) => ({ artists, albums, songs })

/** What the web's Search hands the rules for one search (Search.tsx's marksNow, familyFor, readBox). */
function webCase({ text, library, failed = false, artistList = null, folders = [], personal = false, yourAlbums = null, yourArtists = null, ready = [] }) {
  const index = O.buildOwnedIndex(folders)
  const ownedArtists = [...new Set(folders.map((album) => (album.artist ?? '').trim()).filter(Boolean))]
  const results = failed ? null : library
  const known = new Map()
  for (const album of results?.albums ?? []) known.set(album.id, album)
  const readyMap = new Map(ready.map((album) => [album.id, album]))
  const marks = {
    personal, index,
    yourAlbums: personal && yourAlbums ? new Set(yourAlbums) : null,
    yourArtists: personal && yourArtists ? new Map(yourArtists) : null,
    albumOf: (id) => known.get(id) ?? readyMap.get(id) ?? null,
    artists: artistList,
  }
  const term = text.trim()
  const plan = Q.searchQuery(term, Q.artistNames([...ownedArtists, ...(results?.artists ?? []).map((artist) => artist.name)]))
  const out = {
    text, library, failed, artistList, folders, personal, yourAlbums, yourArtists, ready, plan,
  }
  if (!plan) return out
  const rows = L.pool({ reading: plan, library: results, artistList, index, marks, artists: null, albums: null, songs: null })
  const candidates = L.candidatesOf(rows, term, plan)
  const family = { library: results, artistList, index, groups: [] }
  const top = L.topResults(candidates, L.TOP_RESULTS.phone, family).map((each) => each.row)
  const decided = L.decidedTop(candidates, [], L.TOP_RESULTS.phone, family).prefix
  const line = (row, isTop) => {
    const { line, place } = L.rowLine(row, { marks }, isTop)
    return { key: row.key, line, place }
  }
  out.pool = Object.fromEntries(L.KINDS.map((kind) => [kind, rows[kind].library.map((each) => [each.row.key, each.holder, each.position])]))
  out.candidates = candidates.map((each) => [each.key, each.tier, each.source, each.position])
  out.top = top.map((row) => line(row, true))
  out.decided = decided.map((row) => row.key)
  out.sections = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind], L.PREVIEW.phone[kind]).map((row) => line(row, false))]))
  out.full = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind]).map((row) => row.key)]))
  out.whose = L.KINDS.flatMap((kind) => rows[kind].library.map((each) => [each.row.key, L.rowYours(each.row, marks)]))
  const counts = results ? { artists: results.artists.length, albums: results.albums.length, songs: results.songs.length } : {}
  out.said = L.libraryWords(counts, personal)
  out.prefetch = results ? R.albumsToPrefetch(results.songs, L.preferredSongs(decided)) : []
  //? a kind view's Artists, as Search.tsx's kindModel leads it with the artist the box named
  const named = L.namedArtist(plan, L.knownArtists(artistList, results?.artists ?? []))
  out.named = named ? named.id : null
  return out
}

const FIXED = [
  //? the worked examples (notes/app-requests-search-get.md): "portishead" held -> Portishead, Dummy, Roads
  { text: 'portishead', library: lib([P], [dummy], [roads, glory]), artistList: [P], folders: FOLDER_LISTS[1] },
  { text: 'roads', library: lib([], [], [roads]), artistList: [P] },
  { text: 'glory box', library: lib([], [], [glory]), artistList: [P] },
  { text: 'glory box', library: lib([], [dummy], [glory]), artistList: null },
  { text: 'dummy', library: lib([], [dummy], [glory, sour]), artistList: [P] },
  { text: 'portishead dummy', library: lib([], [dummy], []), artistList: [P, N], folders: FOLDER_LISTS[1] },
  { text: 'dummy portishead', library: lib([], [], []), artistList: [P], folders: FOLDER_LISTS[1] },
  { text: 'portishead third', library: lib([P], [third, dummy, selfTitled], [machine]), artistList: [P] },
  { text: 'portishead dummy', library: null, failed: true, artistList: [P], folders: FOLDER_LISTS[1] },
  { text: 'portishead', library: lib([P], [selfTitled, dummy], [roadsLive, roads]), artistList: [P] },
  { text: 'national', library: lib([N], [boxer], [fake]), artistList: [N, P] },
  { text: 'bjork', library: lib([B], [homogenic], [joga]), artistList: [B] },
  { text: 'po', library: lib([P], [dummy], [roads]), artistList: [P] },
  { text: 'por', library: lib([P], [dummy], [roads]), artistList: [P] },
  { text: 'roads', library: lib([], [], [loose, roads]), artistList: null },
  { text: 'glory', library: lib([], [], [strayArtist, glory]), artistList: [P] },
  { text: 'nothing at all', library: lib(), artistList: [P] },
  { text: '  roads  ', library: lib([], [], [roads]), artistList: [P] },
  //? whose, with a library of your own
  { text: 'portishead', library: lib([P], [dummy, third, selfTitled], [roads, machine]), artistList: [P], personal: true },
  { text: 'portishead', library: lib([P], [dummy, third, selfTitled], [roads, machine]), artistList: [P], personal: true, yourAlbums: ['nd-third'], yourArtists: [['ar-p', 1]] },
  { text: 'portishead', library: lib([P], [dummy, third, selfTitled], [roads, machine]), artistList: [P], personal: true, folders: FOLDER_LISTS[2], yourAlbums: [], yourArtists: [] },
  { text: 'roads', library: lib([], [], [roads, roadsLive, loose]), artistList: [P], personal: true, folders: FOLDER_LISTS[2], ready: [withSongs(dummy, [roads]), withSongs(selfTitled, [roadsLive])] },
  { text: 'boxer', library: lib([N], [boxer], [fake]), artistList: [N], personal: true, yourAlbums: ['nd-boxer'], yourArtists: [['ar-n', 2]] },
  { text: 'roads', library: lib([], [], [roads]), artistList: [P], personal: true, yourAlbums: ['nd-dummy'], yourArtists: [['ar-p', 1]] },
]

/* ===== seeded searches ===== */

const ARTISTS = [
  P, N, B,
  { id: 'ar-ma', name: 'Massive Attack', albumCount: 5 },
  { id: 'ar-m', name: 'Mass', albumCount: 1 },
  { id: 'ar-sg', name: 'Simon & Garfunkel', albumCount: 6 },
  { id: 'ar-sg2', name: 'Simon and Garfunkel' },
  { id: 'ar-va', name: 'Various Artists', albumCount: 40 },
  { id: 'ar-ye', name: 'Ye', albumCount: 2 },
  { id: 'ar-mono', name: 'Mono', albumCount: 0 },
  { id: 'ar-sr', name: 'Sigur R\u00f3s', albumCount: 7 },
  { id: 'ar-p2', name: 'portishead' },
  { id: 'ar-nameless' },
]
const ALBUM_NAMES = ['Dummy', 'Third', 'Portishead', 'Boxer', 'Homogenic', '\u00c1g\u00e6tis byrjun', 'Mezzanine', 'Bookends', 'Mono',
  'Live', 'Dummy (Remastered)', 'Third [Deluxe]', 'Donda', 'Roads', 'Glory Box', '']
const SONG_NAMES = ['Roads', 'Glory Box', 'Sour Times', 'Roads (live)', 'Roads (Remastered 2015)', 'Roads [Mono]',
  'Roads (Max Cooper remix)', 'Fake Empire', 'J\u00f3ga', 'Teardrop', 'Angel', 'Mrs. Robinson', 'Don\u2019t Stop', "Don't Stop",
  'Live Forever', 'Glory Box (stereo )', 'The Rip', 'Mezzanine', 'Dummy', 'Portishead', '']
const WORDS = ['portishead', 'dummy', 'roads', 'glory', 'box', 'national', 'the', 'mass', 'attack', 'massive', 'simon',
  'garfunkel', 'and', '&', 'va', 'ye', 'donda', 'mono', 'live', 'sigur', 'ros', 'r\u00f3s', 'third', 'po', 'ro', '-', 'boxer',
  'mezzanine', 'teardrop', 'angel', 'j\u00f3ga', 'BJ\u00d6RK', 'Portishead']

function seededCase(number) {
  const artists = ARTISTS.filter(() => chance(0.35))
  const albums = []
  for (let i = 0; i < between(0, 6); i++) {
    const by = pick(ARTISTS)
    const album = { id: `al-${number}-${i}`, name: pick(ALBUM_NAMES), artist: by.name, artistId: by.id }
    if (chance(0.15)) delete album.artist
    if (chance(0.1)) album.artistId = ''
    if (chance(0.7)) album.year = pick([1994, 2008, 0, -1, 2026])
    if (chance(0.5)) album.musicBrainzId = pick(['rel-dummy', 'rel-third', `rel-${number}-${i}`, '', ' REL-DUMMY '])
    if (chance(0.3)) album.starred = pick([STAR, ''])
    if (chance(0.6)) album.coverArt = `al-${number}-${i}`
    albums.push(album)
  }
  const songs = []
  for (let i = 0; i < between(0, 8); i++) {
    const album = albums.length && chance(0.7) ? pick(albums) : null
    const by = pick(ARTISTS)
    const one = { id: `s-${number}-${i}`, title: pick(SONG_NAMES), artist: album ? album.artist : by.name, artistId: album ? album.artistId : by.id }
    if (album) {
      one.album = album.name
      one.albumId = album.id
      if (album.coverArt) one.coverArt = album.coverArt
    } else if (chance(0.6)) {
      one.album = pick(ALBUM_NAMES)
      one.albumId = pick(['nd-dummy', 'nd-elsewhere', `nd-${number}-${i}`, ''])
    }
    if (chance(0.1)) delete one.artist
    if (chance(0.1)) delete one.artistId
    songs.push(one)
  }
  if (chance(0.15) && songs.length) songs.push({ ...songs[0] })
  const artistList = chance(0.7) ? ARTISTS.filter(() => chance(0.6)) : null
  const folders = []
  for (const album of albums) {
    if (!chance(0.5)) continue
    const folder = { path: `${album.artist ?? 'x'}/${album.name}/${number}`, artist: album.artist, album: album.name }
    const release = (album.musicBrainzId ?? '').trim().toLowerCase()
    if (release && chance(0.8)) folder.release_mbid = release
    if (chance(0.4)) folder.release_group_mbid = `rg-${album.id}`
    const yours = pick([true, false, undefined])
    if (yours !== undefined) folder.yours = yours
    folders.push(folder)
  }
  if (chance(0.3)) folders.push({ path: `Loose/${number}`, artist: pick(ARTISTS).name ?? '', album: pick(ALBUM_NAMES) })
  const personal = chance(0.6)
  const yourAlbums = personal && chance(0.7) ? albums.filter(() => chance(0.4)).map((album) => album.id).concat(chance(0.2) ? ['al-elsewhere'] : []) : null
  let yourArtists = null
  if (personal && chance(0.7)) {
    const counts = new Map()
    for (const album of albums.filter(() => chance(0.5))) if (album.artistId) counts.set(album.artistId, (counts.get(album.artistId) ?? 0) + 1)
    yourArtists = [...counts.entries()]
  }
  const ready = albums.filter(() => chance(0.3)).map((album) => withSongs({ ...album, starred: chance(0.3) ? STAR : undefined }, songs.filter((each) => each.albumId === album.id)))
  for (const album of ready) if (album.starred === undefined) delete album.starred
  //? the words: a name or title in hand as often as not, so every tier is reached - else words at random
  const named = (list) => (list.length ? pick(list) : pick(WORDS))
  const artistOf = () => named([...artists, ...(artistList ?? [])].map((artist) => artist.name ?? '').filter(Boolean))
  const roll = rand()
  const text = roll < 0.15 ? artistOf()
    : roll < 0.3 ? named(albums.map((album) => album.name))
    : roll < 0.45 ? named(songs.map((each) => each.title))
    : roll < 0.6 ? `${artistOf()}${pick([' ', ' - ', ' : '])}${named(albums.map((album) => album.name))}`
    : roll < 0.65 ? named(songs.map((each) => each.title)).slice(0, between(1, 4))
    : Array.from({ length: between(1, 3) }, () => pick(WORDS)).join(pick([' ', '  ', ' - ', '\u00a0']))
  const failed = chance(0.08)
  return { text, library: failed ? null : lib(artists, albums, songs), failed, artistList, folders, personal, yourAlbums, yourArtists, ready }
}

function cases() {
  const out = FIXED.map(webCase)
  for (let number = 0; number < 220; number++) out.push(webCase(seededCase(number)))
  return out
}

/* ===== whose ===== */

function whose() {
  const folders = FOLDER_LISTS[2]
  const index = O.buildOwnedIndex(folders)
  const albums = [
    dummy, third, selfTitled, boxer, homogenic,
    { id: 'nd-bare' }, { id: 'nd-mbid-case', musicBrainzId: ' REL-DUMMY ' }, { id: 'nd-empty-star', starred: '', musicBrainzId: 'rel-third' },
  ]
  const known = new Map([[homogenic.id, { ...homogenic, starred: STAR }], ['nd-bare', { id: 'nd-bare', musicBrainzId: 'rel-dummy' }]])
  const marksList = [
    { personal: false },
    { personal: true },
    { personal: true, index: true },
    { personal: true, index: true, yourAlbums: ['nd-third', 'nd-dummy'], yourArtists: [['ar-p', 2], ['ar-n', 0]] },
    { personal: true, index: true, known: true },
    { personal: true, yourAlbums: [], yourArtists: [] },
  ]
  const songs = [roads, machine, fake, joga, loose, { id: 's-empty-album', title: 'x', albumId: '' }, { id: 's-bare', title: 'y', albumId: 'nd-bare' }]
  const artists = [P, N, B, { id: 'ar-none' }]
  return marksList.map((given) => {
    const marks = {
      personal: given.personal,
      index: given.index ? index : null,
      yourAlbums: given.yourAlbums ? new Set(given.yourAlbums) : null,
      yourArtists: given.yourArtists ? new Map(given.yourArtists) : null,
      albumOf: (id) => (given.known ? known.get(id) ?? null : null),
    }
    return {
      marks: given,
      albums: albums.map((album) => ({ album, yours: L.albumYours(album, marks), navidrome: W.navidromeYours(album, marks.index), place: W.libraryPlace(marks.personal, L.albumYours(album, marks)) })),
      songs: songs.map((each) => ({ song: each, yours: L.songYours(each, marks) })),
      artists: artists.map((artist) => ({ artist, yours: L.artistYours(artist, marks) })),
    }
  }).map((each) => ({ ...each, folders, known: [...known.values()] }))
}

/* ===== the prefetch ===== */

function prefetch() {
  const lists = [
    [[], []],
    [[roads, glory, sour], []],
    [[roads, glory, sour, machine, fake, joga, roadsLive], [joga]],
    [[loose, { ...loose, albumId: '' }, roads], [loose]],
    [[roads, machine, fake, joga, roadsLive, strayArtist, { id: 'x', albumId: 'nd-7' }], [strayArtist, roads]],
  ]
  return {
    albums: lists.flatMap(([songs, preferred]) => [1, 5, 0].map((count) => ({ songs: songs.map((each) => each.albumId ?? null), preferred: preferred.map((each) => each.albumId ?? null), count, ids: R.albumsToPrefetch(songs, preferred, count) }))),
    index: [[[roads, glory], 's-glory'], [[roads, glory], 's-none'], [[], 's-roads'], [null, 's-roads']].map(([songs, id]) => ({ songs: songs ? songs.map((each) => each.id) : null, id, at: R.songIndex(songs ?? undefined, id) })),
  }
}

/* ===== out ===== */

function vectors() {
  return {
    numbers: numbers(),
    words: words(),
    fold: fold(),
    names: names(),
    readings: readings(),
    owned: ownedVectors(),
    whose: whose(),
    prefetch: prefetch(),
    cases: cases(),
  }
}

/** JSON with every character outside ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[\u0080-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-search-vectors.cjs, then port the change to DeadwaxCore's SearchList.swift and see SearchVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
