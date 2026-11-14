#!/usr/bin/env node
/**
 * Search's albums you don't have, for the iPhone app (Phase 5, slice 2 - notes/ios-specs/phase5-search.md 6.2): what
 * the web app's own TypeScript answers, written as a second fixture beside search-vectors.json (slice 1's, already
 * 1.4 MB) for the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore (SearchAlbums.swift, SearchList.swift's albums,
 * Top results with MusicBrainz's and the moments, SearchReading.swift's typing rules, Pressings.swift) to replay
 * (Tests/DeadwaxCoreTests/SearchAlbumsVectorTests.swift) - so the phone draws MusicBrainz's albums, decides Top results
 * before they land, and draws the album you don't have exactly as the web does.
 *
 * Compiles lib/searchList.ts, lib/pressings.ts, lib/idBridge.ts and lib/artistPage.ts with what they import, and reads
 * the few numbers and words that live in Search.tsx (MUSICBRAINZ_LIMIT, OWNED_WAIT_MS, the all-failed foot's words)
 * from its source. Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-albums-vectors.json:
 *
 *   numbers    the limit, the waits, the previews' MusicBrainz caps, the pressing filter's threshold, the pressing
 *              lists kept
 *   words      the hint and the asking words, the all-held line, TYPE_MORE, STUDIO_NOTE, musicBrainzWords,
 *              failureWords, foldWords, emptyWords, libraryLateWords, librarySkippedWords
 *   typing     typeFilter, asksMusicBrainzBySettling, musicBrainzOnTyping, allAlbumsQuery over readings
 *   groups     groupYear, groupKind, a section's word, Credits' name, soleCredit
 *   holding    over folder lists: groupHeld, groupPlace, groupMaybe, notInLibrary, heldUnlisted, heldReleases,
 *              heldInOrder, libraryArtistFor, studioOrder
 *   moments    sectionsReady, lateKinds, drawInOrFold and nextBehind over every combination
 *   cases      whole searches with MusicBrainz's albums in hand: the pool (each row's key, holder and position, every
 *              block), every candidate, the phantoms, decidedTop over the library alone, Top results with and without
 *              the decided prefix fixed, the sections as a phone caps them and in full, a late answer's rows and the
 *              drawn counts, every row's line in a section and in Top results
 *   pressings  real MusicBrainz groups (tests/fixtures/pressings/) and a made one: each release's format, year,
 *              label and facts; the base and the default; the view (asked, held, yours); its summary; the tracklist,
 *              what it leaves out and the summary with each pressing chosen; the filter; the header and the meta line
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-search-albums-vectors.cjs           write the fixture
 *   node ios/scripts/export-search-albums-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'search', 'search-albums-vectors.json')
const PRESSINGS = path.join(REPO, 'tests', 'fixtures', 'pressings')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-albums-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchList.ts', 'src/lib/pressings.ts', 'src/lib/idBridge.ts', 'src/lib/artistPage.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/searchList.js'))
const Q = require(path.join(OUT, 'lib/searchQuery.js'))
const R = require(path.join(OUT, 'lib/searchResults.js'))
const O = require(path.join(OUT, 'lib/owned.js'))
const P = require(path.join(OUT, 'lib/pressings.js'))
const T = require(path.join(OUT, 'lib/tracklistDiff.js'))
const B = require(path.join(OUT, 'lib/idBridge.js'))
const A = require(path.join(OUT, 'lib/artistPage.js'))
const C = require(path.join(OUT, 'lib/release.js'))

/** A line of a component's source, which the exporter can't compile without Preact - the first match's group. */
function sourceMatch(file, pattern) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(pattern)
  if (!found) throw new Error(`${file} no longer has ${pattern}`)
  return found[1]
}

/* ===== seeded randomness ===== */

let seed = 6262
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== the numbers and the words ===== */

function numbers() {
  return {
    musicBrainzLimit: Number(sourceMatch('src/app/Search.tsx', /export const MUSICBRAINZ_LIMIT = (\d+)/)),
    ownedWaitMs: Number(sourceMatch('src/app/Search.tsx', /export const OWNED_WAIT_MS = (\d+)/)),
    resultsWaitMs: L.RESULTS_WAIT_MS,
    libraryLateMs: L.LIBRARY_LATE_MS,
    previewMusicBrainz: Object.fromEntries(L.KINDS.map((kind) => [kind, L.PREVIEW.phone[kind][1]])),
    pressingFilterMin: P.PRESSING_FILTER_MIN,
    pressingsKept: Number(sourceMatch('src/app/pressingLists.ts', /export const PRESSINGS_KEPT = (\d+)/)),
  }
}

const COUNTS = [{}, { albums: 1 }, { albums: 2 }, { artists: 1, albums: 3 }, { artists: 2, albums: 1, songs: 11 }, { albums: 0, songs: 0 }, { songs: 1 }]
const TEXTS = ['dummy', 'glory box', '“quoted”', 'Björk']
const FAILURES = [
  { message: 'MusicBrainz is busy.', refused: false, busy: true, unavailable: true },
  { message: 'MusicBrainz is away.', refused: false, busy: false, unavailable: true },
  { message: 'That search is too long.', refused: true, busy: false, unavailable: false },
  { message: 'The connection was lost - try again.', refused: false, busy: false, unavailable: false },
  { message: 'Refused and busy at once.', refused: true, busy: true, unavailable: true },
]

function words() {
  const personal = R.searchWords(true), plain = R.searchWords(false)
  return {
    hint: plain.hint,
    hintPersonal: personal.hint,
    searching: plain.searching(true),
    searchingPersonal: personal.searching(true),
    searchingLibrary: plain.searching(false),
    searchingLibraryPersonal: personal.searching(false),
    allHeld: plain.allHeld,
    allHeldPersonal: personal.allHeld,
    typeMore: L.TYPE_MORE,
    studioNote: L.STUDIO_NOTE,
    libraryAbove: sourceMatch('src/app/Search.tsx', /personal \? "What's in the collection is above\." : "(What's in your library is above\.)"/),
    libraryAbovePersonal: sourceMatch('src/app/Search.tsx', /personal \? "(What's in the collection is above\.)"/),
    musicBrainz: COUNTS.flatMap((counts) => [true, false].map((answered) => ({ counts, answered, said: L.musicBrainzWords(counts, answered) }))),
    failure: FAILURES.flatMap((failure) => [false, true].map((short) => ({ failure, short, said: L.failureWords(failure, short) }))),
    fold: L.KINDS.flatMap((kind) => [1, 2, 7].map((count) => ({ kind, count, ...L.foldWords(kind, count) }))),
    empty: L.KINDS.flatMap((kind) => TEXTS.map((text) => ({ kind, text, said: L.emptyWords(kind, text) }))),
    libraryLate: COUNTS.flatMap((counts) => [false, true].flatMap((personal) => TEXTS.slice(0, 2).map((text) => ({ counts, personal, text, ...L.libraryLateWords(counts, personal, text) })))),
    librarySkipped: [false, true].map((personal) => ({ personal, said: L.librarySkippedWords(personal) })),
  }
}

/* ===== typing and the queries ===== */

const TYPED = ['', 'p', 'po', 'por', 'port', 'portishead', '  po  ', 'ab', 'abc', 'a b', 'ab ', 'été', 'ye', 'va', 'u2', 'ac/dc',
  '!!!', 'roads portishead', '  ', 'xx', 'xxx']

function typing() {
  const filters = [
    {}, { primary: ['Album'] }, { primary: ['Album', 'EP'] }, { studioOnly: true }, { primary: ['Album', 'EP'], studioOnly: true },
    { primary: ['Single'], studioOnly: true },
  ]
  const asked = [null, '', 'por', 'portishead', 'po', 'abc', 'roads portishead']
  const names = [[], ['Portishead'], ['Portishead', 'The National', 'Various Artists'], ['Björk', 'Ye']]
  const plans = []
  for (const list of names) {
    for (const text of ['portishead', 'portishead dummy', 'dummy portishead', 'various artists', 'va', 'the national', 'national boxer', 'bjork', 'ye', 'dummy', 'portishead - third']) {
      const plan = Q.searchQuery(text, Q.artistNames(list))
      if (plan) plans.push({ names: list, text, plan, all: L.allAlbumsQuery(plan) })
    }
  }
  return {
    typeFilter: filters.map((given) => ({ given, filter: Q.typeFilter(given) })),
    settling: TYPED.map((text) => ({ text, settles: Q.asksMusicBrainzBySettling(text) })),
    onTyping: TYPED.flatMap((text) => asked.map((was) => ({ text, asked: was, then: Q.musicBrainzOnTyping(text, was) }))),
    allAlbums: plans,
  }
}

/* ===== MusicBrainz's albums ===== */

const MB = {
  portishead: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11',
  national: '664c3e0e-42d8-48c1-b209-1efca19c0325',
  bjork: '87c5dedd-371d-4a53-9f7f-80522fb7f3cb',
  barrow: '5e8e1d2e-3c0b-4f52-a0ef-3f4b5e1c9a10',
  various: '89ad4ac3-39f7-470e-963a-56509c546377',
  gibbons: '0c0a9f1c-6a2a-4b9c-9a5b-2f3d1e4c5b6a',
}
const credit = (name, id, joinphrase = '', credited = name) => ({ name: credited, joinphrase, artist: { id, name } })
const by = (key, name) => [credit(name, MB[key])]
const group = (id, title, date, primary, secondary, credits) => {
  const out = { id, title }
  if (date !== undefined) out['first-release-date'] = date
  if (primary !== undefined) out['primary-type'] = primary
  if (secondary !== undefined) out['secondary-types'] = secondary
  if (credits !== undefined) out['artist-credit'] = credits
  return out
}
const G = {
  dummy: group('48140466-cff6-3222-bd55-63c27e43190d', 'Dummy', '1994-08-22', 'Album', [], by('portishead', 'Portishead')),
  third: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e01', 'Third', '2008-04-28', 'Album', [], by('portishead', 'Portishead')),
  self: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e02', 'Portishead', '1997-09-29', 'Album', [], by('portishead', 'Portishead')),
  roseland: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03', 'Roseland NYC Live', '1998-11-02', 'Album', ['Live'], by('portishead', 'Portishead')),
  glory: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e04', 'Glory Box', '1995-01-09', 'Single', [], by('portishead', 'Portishead')),
  sour: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e05', 'Sour Times', '1994', 'EP', [], by('portishead', 'Portishead')),
  remix: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e06', 'Dummy Remixed', '1995-06', 'Album', ['Remix'], by('portishead', 'Portishead')),
  friends: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e07', 'Bristol Sound', '2001', 'Album', ['Compilation'], by('various', 'Various Artists')),
  collab: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e08', 'Drawn & Quartered', '2012-03-01', 'Album', [],
    [credit('Portishead', MB.portishead, ' & '), credit('Geoff Barrow', MB.barrow)]),
  undated: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e09', 'Untitled', undefined, undefined, undefined, by('portishead', 'Portishead')),
  badDate: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e10', 'Glory Times', '19xx', 'Other', ['DJ-mix'], by('portishead', 'Portishead')),
  boxer: group('b1b2b3b4-0b43-3d1a-8e0b-3b0f9a1d0e11', 'Boxer', '2007-05-22', 'Album', [], by('national', 'The National')),
  homogenic: group('c1c2c3c4-0b43-3d1a-8e0b-3b0f9a1d0e12', 'Homogenic', '1997-09-22', 'Album', [], [credit('Björk', MB.bjork, '', 'Bjork')]),
  interview: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e13', 'In Conversation', '1998', 'Other', ['Interview'], by('portishead', 'Portishead')),
  soundtrack: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e14', 'To Kill a Dead Man', '1994', 'Album', ['Soundtrack', 'Live'], by('portishead', 'Portishead')),
  liveComp: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e15', 'Live Collection', '2009', 'EP', ['Live', 'Compilation'], by('portishead', 'Portishead')),
  noCredit: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e16', 'Nobody’s', '2003', 'Broadcast', [], []),
  badCredit: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e17', 'Mistagged', '2004', 'Album', [], [{ name: 'Portishead', joinphrase: '', artist: { id: 'not-an-mbid', name: 'Portishead' } }]),
  barrowEP: group('d1d2d3d4-0b43-3d1a-8e0b-3b0f9a1d0e18', 'Quakers', '2012', 'EP', ['Mixtape/Street'], by('barrow', 'Geoff Barrow')),
  gibbons: group('e1e2e3e4-0b43-3d1a-8e0b-3b0f9a1d0e19', 'Out of Season', '2002-10-28', 'Album', [], [credit('Beth Gibbons', MB.gibbons, ' & '), credit('Rustin Man', MB.barrow)]),
  spoken: group('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e20', 'Words', '2010', '', ['Spokenword'], by('portishead', 'Portishead')),
}
const GROUPS = Object.values(G)

function groups() {
  return GROUPS.map((each) => ({
    group: each,
    year: R.groupYear(each),
    kind: R.groupKind(each),
    //? a section's word: its kind, but none for an Album (searchList.ts groupWord, which isn't exported)
    word: R.groupKind(each) === 'Album' ? '' : R.groupKind(each),
    credit: C.creditName(each['artist-credit']),
    current: C.currentName(each['artist-credit']),
    sole: A.soleCredit(each['artist-credit']),
  }))
}

/* ===== what is held ===== */

const folder = (path, artist, album, extra = {}) => ({ path, artist, album, ...extra })
const REL = {
  dummy: '76df3287-6cda-33eb-8e9a-044b5e15ffdd', dummyUS: '00163fb1-5ab7-4fec-b0dd-a915e2722340', third: '930345b1-a970-3495-a1dd-55147bea7741',
  boxer: 'f1f2f3f4-1111-4222-8333-944455556666', self: 'f1f2f3f4-1111-4222-8333-944455557777',
}
const FOLDER_LISTS = [
  null,
  [],
  [folder('Portishead/Dummy', 'Portishead', 'Dummy', { release_mbid: REL.dummy, release_group_mbid: G.dummy.id, albumartist_mbids: [MB.portishead], yours: true })],
  [
    folder('Portishead/Dummy', 'Portishead', 'Dummy', { release_mbid: REL.dummy, release_group_mbid: G.dummy.id, albumartist_mbids: [MB.portishead], yours: true, year: '1994' }),
    folder('Portishead/Dummy (US)', 'Portishead', 'Dummy', { release_mbid: REL.dummyUS, release_group_mbid: G.dummy.id, edition: 'US', yours: false, year: '1995' }),
    folder('Portishead/Dummy (Standard)', 'Portishead', 'Dummy', { release_mbid: ` ${REL.dummyUS.toUpperCase()} `, release_group_mbid: G.dummy.id, edition: 'Standard', yours: false, year: '' }),
    folder('Portishead/Third', 'Portishead', 'Third', { release_mbid: REL.third, release_group_mbid: G.third.id, yours: false, year: '2008' }),
    folder('Unknown/Homogenic', 'Björk', 'Homogenic', { yours: true }),
    folder('Unknown/Boxer', 'The National', 'Boxer', { yours: false }),
  ],
  [
    folder('A/Third', 'Portishead', 'Third', { release_group_mbid: G.third.id }),
    folder('A/Portishead', 'Portishead', 'Portishead', { release_mbid: REL.self, albumartist_mbids: [MB.portishead, MB.barrow] }),
    folder('B/Quakers', 'Quakers', 'Quakers', { albumartist_mbids: [MB.barrow] }),
    folder('C/Out of Season', 'Beth Gibbons', 'Out of Season'),
    folder('C/Boxer', 'The National', 'Boxer', { release_mbid: REL.boxer, release_group_mbid: G.boxer.id, edition: 'Deluxe', year: '2008-01' }),
    folder('C/Boxer (2007)', 'The National', 'Boxer', { release_mbid: REL.boxer, release_group_mbid: G.boxer.id, year: '2007' }),
  ],
]

const ARTIST_LISTS = [
  [],
  [{ id: 'ar-p', name: 'Portishead', musicBrainzId: MB.portishead, albumCount: 3 }],
  [{ id: 'ar-p', name: 'Portishead', albumCount: 3 }, { id: 'ar-n', name: 'The National' }, { id: 'ar-q', name: 'Quakers' }],
  [{ id: 'ar-p', name: 'Portishead' }, { id: 'ar-p2', name: 'portishead' }, { id: 'ar-b', name: 'Bjork', musicBrainzId: ` ${MB.bjork.toUpperCase()} ` }],
  [{ id: 'ar-p', name: 'Portishead', musicBrainzId: MB.portishead }, { id: 'ar-p3', name: 'Portishead (2)', musicBrainzId: MB.portishead }],
]

function holding() {
  return FOLDER_LISTS.map((folders) => {
    const index = folders ? O.buildOwnedIndex(folders) : null
    const libraryAlbums = [{ musicBrainzId: REL.dummy }, { musicBrainzId: ` ${REL.third.toUpperCase()} ` }, {}]
    return {
      folders,
      groups: GROUPS.map((each) => ({
        id: each.id,
        held: R.groupHeld(index, each.id),
        place: R.groupPlace(index, each.id, false),
        placePersonal: R.groupPlace(index, each.id, true),
        maybe: L.groupMaybe(each, { index, personal: false }),
        maybePersonal: L.groupMaybe(each, { index, personal: true }),
        releases: B.heldReleases(index, each.id),
      })),
      notInLibrary: R.notInLibrary(GROUPS, index).map((each) => each.id),
      heldUnlisted: L.heldUnlisted(GROUPS, index, []).map((each) => each.id),
      heldUnlistedListed: L.heldUnlisted(GROUPS, index, libraryAlbums).map((each) => each.id),
      inOrder: folders ? B.heldInOrder(folders).map((each) => each.path) : [],
      artists: ARTIST_LISTS.map((list) => ({
        list,
        found: [
          [MB.portishead, 'Portishead'], [MB.portishead, null], [MB.barrow, 'Geoff Barrow'], [MB.bjork, 'Björk'], [MB.national, 'the national'],
          [MB.gibbons, 'Beth Gibbons'], ['not-an-mbid', 'Portishead'], [null, 'Portishead'], [` ${MB.national.toUpperCase()} `, 'The National'],
        ].map(([mbid, name]) => ({ mbid, name, artist: A.libraryArtistFor(list, mbid, index, name)?.id ?? null })),
      })),
    }
  })
}

function studio() {
  const lists = [
    GROUPS,
    [G.sour, G.dummy, G.glory, G.third, G.self],
    [G.undated, G.badDate, G.dummy, group('x1', 'Same day A', '1994-08-22', 'Album', [], []), group('x2', 'Same day B', '1994-08-22', 'album', [], [])],
    [group('y1', 'EP first', '1990', 'ep', [], []), group('y2', 'No type', '1980'), group('y3', 'Album later', '2000', 'Album', ['Live'], []), group('y4', 'Album', '', 'Album', [], [])],
    [],
  ]
  return lists.map((list) => ({ ids: list.map((each) => each.id), ordered: L.studioOrder(list).map((each) => each.id), groups: list }))
}

/* ===== the moments ===== */

function moments() {
  const ready = []
  for (const librarySettled of [false, true]) for (const musicBrainz of [false, true]) for (const asked of [false, true])
    for (const out of [[], ['albums'], ['artists', 'songs']]) for (const capPassed of [false, true]) {
      ready.push({ librarySettled, musicBrainz, asked, out, capPassed, ready: L.sectionsReady({ librarySettled, musicBrainz, asked, out, capPassed }) })
    }
  const wanted = [[], ['albums'], ['artists', 'albums', 'songs'], ['songs', 'albums']]
  const hands = [[], ['albums'], ['artists', 'songs'], ['artists', 'albums', 'songs']]
  const late = wanted.flatMap((list) => hands.map((inHand) => ({ wanted: list, inHand, late: L.lateKinds(list, (kind) => inHand.includes(kind)) })))
  const drawnLists = [[], ['albums'], ['artists', 'albums'], ['albums', 'songs'], ['artists', 'albums', 'songs'], ['songs']]
  const landing = L.KINDS.flatMap((kind) => drawnLists.flatMap((drawn) => [false, true].map((footTappable) => ({ kind, drawn, footTappable, landing: L.drawInOrFold(kind, drawn, footTappable) }))))
  const behind = [false, true].flatMap((was) => ['in-time', 'late', 'failed', 'superseded', 'refused'].map((outcome) => ({ was, outcome, behind: L.nextBehind(was, outcome) })))
  return { ready, late, landing, behind }
}

/* ===== whole searches ===== */

const STAR = '2026-01-02T03:04:05Z'
const PA = { id: 'ar-p', name: 'Portishead', albumCount: 3, coverArt: 'ar-p', musicBrainzId: MB.portishead }
const PB = { id: 'ar-p', name: 'Portishead', albumCount: 3 }
const NA = { id: 'ar-n', name: 'The National', albumCount: 8 }
const BA = { id: 'ar-b', name: 'Björk', albumCount: 1, musicBrainzId: MB.bjork }
const QA = { id: 'ar-q', name: 'Quakers', albumCount: 1 }
const dummy = { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', artistId: 'ar-p', year: 1994, musicBrainzId: REL.dummy, coverArt: 'al-dummy' }
const third = { id: 'nd-third', name: 'Third', artist: 'Portishead', artistId: 'ar-p', year: 2008, musicBrainzId: REL.third }
const boxer = { id: 'nd-boxer', name: 'Boxer', artist: 'The National', artistId: 'ar-n', year: 2007, starred: STAR, musicBrainzId: REL.boxer }
const song = (id, title, album) => ({ id, title, artist: album.artist, artistId: album.artistId, album: album.name, albumId: album.id, coverArt: album.coverArt })
const roads = song('s-roads', 'Roads', dummy), glorySong = song('s-glory', 'Glory Box', dummy), rip = song('s-rip', 'The Rip', third)
const lib = (artists = [], albums = [], songs = []) => ({ artists, albums, songs })

/** What the web's Search hands the rules for one search with MusicBrainz's albums in hand (Search.tsx's marksNow, rows,
 *  familyFor, decided, the late landing). `landed`: the folders /library/owned had said when the albums' answer landed
 *  (its block, notInLibrary, worked out then and kept) - `folders` by default; null for none. */
function webCase({ text, library, failed = false, artistList = null, folders = null, landed, groups = null, personal = false, yourAlbums = null, yourArtists = null }) {
  const index = folders ? O.buildOwnedIndex(folders) : null
  const landedIndex = landed === undefined ? index : landed ? O.buildOwnedIndex(landed) : null
  const ownedArtists = [...new Set((folders ?? []).map((album) => (album.artist ?? '').trim()).filter(Boolean))]
  const results = failed ? null : library
  const known = new Map()
  for (const album of results?.albums ?? []) known.set(album.id, album)
  const marks = {
    personal, index,
    yourAlbums: personal && yourAlbums ? new Set(yourAlbums) : null,
    yourArtists: personal && yourArtists ? new Map(yourArtists) : null,
    albumOf: (id) => known.get(id) ?? null,
    artists: artistList,
  }
  const term = text.trim()
  const plan = Q.searchQuery(term, Q.artistNames([...ownedArtists, ...(results?.artists ?? []).map((artist) => artist.name)]))
  //? the folder lists by their place in FOLDER_LISTS (the holding vectors carry them), the groups by id (the groups')
  const out = {
    text, library, failed, artistList, folders: FOLDER_LISTS.indexOf(folders), landed: FOLDER_LISTS.indexOf(landed === undefined ? folders : landed),
    groups: groups ? groups.map((each) => each.id) : null, personal, yourAlbums, yourArtists, plan,
  }
  if (!plan) return out
  const albums = groups ? { groups, shown: R.notInLibrary(groups, landedIndex) } : null
  const bare = L.pool({ reading: plan, library: results, artistList, index, marks, artists: null, albums: null, songs: null })
  const rows = L.pool({ reading: plan, library: results, artistList, index, marks, artists: null, albums, songs: null })
  const family = { library: results, artistList, index, groups: groups ?? [] }
  const bareCandidates = L.candidatesOf(bare, term, plan)
  const candidates = L.candidatesOf(rows, term, plan)
  const phantoms = Object.fromEntries(L.KINDS.map((kind) => [kind, L.phantom(kind, plan)?.tier ?? null]))
  const decided = [['albums'], ['artists', 'albums', 'songs'], []].map((kinds) => {
    const made = L.decidedTop(bareCandidates, kinds.map((kind) => L.phantom(kind, plan)).filter(Boolean), L.TOP_RESULTS.phone, family)
    return { kinds, prefix: made.prefix.map((row) => row.key), place: made.place }
  })
  const prefix = L.decidedTop(bareCandidates, [L.phantom('albums', plan)].filter(Boolean), L.TOP_RESULTS.phone, family).prefix
  const line = (row, isTop) => {
    const { line, place } = L.rowLine(row, { marks }, isTop)
    return [row.key, line, place]
  }
  const placed = (list) => list.map((each) => [each.row.key, each.holder, each.position])
  out.shown = albums ? albums.shown.map((each) => each.id) : null
  out.pool = Object.fromEntries(L.KINDS.map((kind) => [kind, { library: placed(rows[kind].library), brought: placed(rows[kind].brought), musicbrainz: placed(rows[kind].musicbrainz) }]))
  out.candidates = candidates.map((each) => [each.key, each.tier, each.source, each.position])
  out.phantoms = phantoms
  out.decided = decided
  out.top = L.topResults(candidates, L.TOP_RESULTS.phone, family).map((each) => line(each.row, true))
  out.topFixed = L.topResults(candidates, L.TOP_RESULTS.phone, family, prefix).map((each) => each.row.key)
  out.sections = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind], L.PREVIEW.phone[kind]).map((row) => row.key)]))
  out.full = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind]).map((row) => row.key)]))
  //? the albums late: their section drawn at moment 2 from the library alone, the answer landing in its slot after
  const cap = L.PREVIEW.phone.albums
  const drawn = L.sectionRows(bare.albums, cap)
  const [libraryDrawn, musicBrainzDrawn] = L.drawnCounts(rows.albums, drawn)
  out.late = {
    drawn: drawn.map((row) => row.key),
    counts: [libraryDrawn, musicBrainzDrawn],
    rows: L.lateRows(rows.albums, [Math.max(0, cap[0] - libraryDrawn), Math.max(0, cap[1] - musicBrainzDrawn)], new Set(drawn.map((row) => row.key))).map((row) => row.key),
    uncapped: L.lateRows(rows.albums).map((row) => row.key),
  }
  out.lines = L.KINDS.flatMap((kind) => [...rows[kind].library, ...rows[kind].brought, ...rows[kind].musicbrainz])
    .map((each) => [...line(each.row, false), ...line(each.row, true).slice(1)])
  //? Top results' relatives: every MusicBrainz album's family, made from its own credit
  out.families = (groups ?? []).map((each) => ({ id: each.id, family: L.familyOf(L.groupRow(each), family).map((row) => line(row, true)) }))
  return out
}

const F = FOLDER_LISTS
const FIXED = [
  //? an artist you have alone: the studio clause's answer, your Dummy held (not drawn twice), Third brought in
  { text: 'portishead', library: lib([PA], [dummy], [roads]), artistList: [PA], folders: F[2], groups: [G.dummy, G.third, G.self, G.sour] },
  { text: 'portishead', library: lib([PA], [dummy], [roads]), artistList: [PA], folders: F[3], groups: [G.dummy, G.third, G.self, G.roseland, G.glory] },
  //? an album nobody here has: MusicBrainz's group first in Top results, its credited artist after it
  { text: 'roseland', library: lib(), artistList: [PA], folders: F[2], groups: [G.roseland] },
  { text: 'roseland', library: lib(), artistList: [PB], folders: F[2], groups: [G.roseland] },
  { text: 'roseland', library: lib(), artistList: null, folders: F[2], groups: [G.roseland] },
  { text: 'roseland', library: lib(), artistList: [], folders: null, groups: [G.roseland] },
  { text: 'out of season', library: lib(), artistList: [PA], folders: F[4], groups: [G.gibbons] },
  { text: 'quakers', library: lib([QA], [], []), artistList: [QA, PB], folders: F[4], groups: [G.barrowEP] },
  { text: 'drawn', library: lib(), artistList: [PA], folders: F[2], groups: [G.collab, G.noCredit, G.badCredit] },
  //? held since the answer landed: kept in MusicBrainz's block, marked in place - never brought in as well
  { text: 'third', library: lib(), artistList: [PA], folders: F[3], landed: null, groups: [G.third, G.dummy] },
  { text: 'third', library: lib(), artistList: [PA], folders: F[3], landed: F[2], groups: [G.third, G.dummy, G.self] },
  //? held but not listed by search3: brought in under yours / the collection's
  { text: 'portishead third', library: lib([], [], []), artistList: [PA], folders: F[3], groups: [G.third] },
  { text: 'portishead third', library: lib([], [third], []), artistList: [PA], folders: F[3], groups: [G.third], personal: true, yourAlbums: [], yourArtists: [] },
  { text: 'dummy', library: lib([], [dummy], [roads]), artistList: [PA], folders: F[3], groups: [G.dummy, G.remix], personal: true, yourAlbums: ['nd-dummy'], yourArtists: [['ar-p', 1]] },
  //? maybe: an untagged folder by the name
  { text: 'homogenic', library: lib(), artistList: [BA], folders: F[3], groups: [G.homogenic] },
  { text: 'homogenic', library: lib(), artistList: [BA], folders: F[3], groups: [G.homogenic], personal: true, yourAlbums: [], yourArtists: [] },
  { text: 'boxer', library: lib([NA], [], []), artistList: [NA], folders: F[3], groups: [G.boxer], personal: true, yourAlbums: [], yourArtists: [] },
  { text: 'boxer', library: lib([NA], [boxer], []), artistList: [NA], folders: F[4], groups: [G.boxer] },
  //? the library failed, MusicBrainz answered
  { text: 'portishead dummy', library: null, failed: true, artistList: [PA], folders: F[2], groups: [G.dummy, G.remix] },
  //? nothing from MusicBrainz, and no answer at all
  { text: 'glory box', library: lib([], [], [glorySong]), artistList: [PA], folders: F[2], groups: [] },
  { text: 'glory box', library: lib([], [], [glorySong]), artistList: [PA], folders: F[2], groups: null },
  { text: 'glory', library: lib([], [], [glorySong]), artistList: [PA], folders: F[2], groups: [G.glory, G.badDate] },
  //? every kind of group, in one answer
  { text: 'portishead', library: lib([PA], [], []), artistList: [PA], folders: F[1], groups: GROUPS },
  { text: 'portishead', library: lib([PA], [dummy, third], [roads, rip]), artistList: [PA], folders: F[3], groups: GROUPS, personal: true, yourAlbums: ['nd-third'], yourArtists: [['ar-p', 1]] },
  { text: 'various artists', library: lib(), artistList: [], folders: F[1], groups: [G.friends] },
]

const WORDS = ['portishead', 'dummy', 'third', 'roseland', 'glory', 'box', 'boxer', 'national', 'homogenic', 'bjork', 'quakers', 'sour',
  'times', 'live', 'out', 'season', 'drawn', 'po', 'the', '-']

function seededCase(number) {
  const artists = [PA, PB, NA, BA, QA].filter(() => chance(0.3))
  const unique = [...new Map(artists.map((artist) => [artist.id, artist])).values()]
  const albums = [dummy, third, boxer].filter(() => chance(0.35))
  const songs = [roads, glorySong, rip].filter((each) => albums.some((album) => album.id === each.albumId) && chance(0.5))
  const artistList = chance(0.75) ? [PA, NA, BA, QA, PB].filter(() => chance(0.5)).filter((artist, at, all) => all.findIndex((each) => each.id === artist.id) === at) : null
  const folders = pick(FOLDER_LISTS)
  const landed = chance(0.2) ? pick(FOLDER_LISTS) : undefined
  const answer = chance(0.12) ? null : GROUPS.filter(() => chance(0.3)).sort(() => rand() - 0.5)
  const personal = chance(0.5)
  const yourAlbums = personal && chance(0.7) ? albums.filter(() => chance(0.5)).map((album) => album.id) : null
  const yourArtists = personal && chance(0.6) ? unique.filter(() => chance(0.5)).map((artist) => [artist.id, between(0, 3)]) : null
  const named = (list) => (list.length ? pick(list) : pick(WORDS))
  const roll = rand()
  const text = roll < 0.25 ? named((answer ?? []).map((each) => each.title))
    : roll < 0.4 ? named(unique.map((artist) => artist.name))
    : roll < 0.6 ? `${named(unique.map((artist) => artist.name))} ${named((answer ?? []).map((each) => each.title))}`
    : roll < 0.7 ? named(albums.map((album) => album.name))
    : Array.from({ length: between(1, 2) }, () => pick(WORDS)).join(' ')
  const failed = chance(0.08)
  return { text, library: failed ? null : lib(unique, albums, songs), failed, artistList, folders, landed, groups: answer, personal, yourAlbums, yourArtists }
}

function cases() {
  const out = FIXED.map(webCase)
  for (let number = 0; number < 70; number++) out.push(webCase(seededCase(number)))
  return out
}

/* ===== the album you don't have ===== */

const load = (name) => JSON.parse(fs.readFileSync(path.join(PRESSINGS, `${name}.json`), 'utf8'))

/** A made group: a pressing with no media, one with an empty tracklist, medium titles, formats run together, labels
 *  and numbers of every shape, Worldwide and Europe, a renamed track and a bonus disc. */
function madeGroup() {
  const track = (title, ms, extra = {}) => ({ title, length: ms, recording: { title, length: ms }, ...extra })
  const usual = [track('Mysterons', 306000), track('Sour Times', 254000), track('Strangers', 238000), track('Roads', 310000)]
  const media = (format, tracks, title) => ({ position: 1, format, title, tracks })
  return {
    group: { id: 'f0f0f0f0-0b43-3d1a-8e0b-3b0f9a1d0e99', title: 'Made', 'first-release-date': '1994-08-22', 'primary-type': 'Album', 'secondary-types': [], 'artist-credit': by('portishead', 'Portishead') },
    releases: [
      { id: 'r-usual-cd', title: 'Made', status: 'Official', date: '1994-08-22', country: 'GB', barcode: '042282855329', 'label-info': [{ label: { name: 'Go! Beat' }, 'catalog-number': '828 553-2' }, { label: { name: 'Go! Beat' }, 'catalog-number': '828 553-2' }], media: [media('CD', usual)] },
      { id: 'r-usual-vinyl', title: 'Made', status: 'Official', date: '1994', country: 'XE', barcode: '', 'label-info': [{ label: { name: 'Go! Beat' }, 'catalog-number': '[none]' }, { label: { name: 'London' }, 'catalog-number': 'LP 1' }], media: [media('12" Vinyl', usual.slice(0, 2)), { ...media('12" Vinyl', usual.slice(2)), position: 2 }] },
      { id: 'r-digital', title: 'Made', status: 'Official', 'release-events': [{ date: '2014-01-01' }], country: 'XW', barcode: null, 'label-info': [], media: [media('Digital Media', usual)] },
      { id: 'r-renamed', title: 'Made', status: 'Promotion', date: '1994-07', country: 'US', disambiguation: 'promo', 'label-info': [{ label: { name: 'London' }, 'catalog-number': 'PRO 9' }], media: [media('CD', [track('Mysterons', 306000), track('Sour Times (Nobody Loves Me)', 255000), track('Strangers', 238000), track('Roads', 310000)])] },
      { id: 'r-bonus', title: 'Made (deluxe)', status: 'Official', date: '2014-10-20', country: 'GB', 'label-info': [{ label: { name: 'Island' } }], media: [media('CD', usual, ''), { position: 2, format: 'CD', title: 'Unreleased Tracks', tracks: [track('Airbus', 300000), track('Roads (live)', 380000)] }] },
      { id: 'r-short', title: 'Made', date: '', country: '', media: [media('Cassette', [track('Mysterons', 306000), track('Strangers', 238000), track('Roads', 250000)])] },
      { id: 'r-none', title: 'Made', status: 'Bootleg', media: [] },
      { id: 'r-empty', title: 'Made', media: [media('CD', [])] },
      { id: 'r-mixed', title: 'Made', media: [media('USB Flash Drive', usual), { position: 2, format: '12" Vinyl', tracks: usual }, { position: 3, format: '12" Vinyl', tracks: usual }, { position: 4, format: '', tracks: [] }] },
    ],
  }
}

function pressings() {
  const real = ['dummy', 'third', 'slow-rush', 'wish-you-were-here-experience'].map((name) => {
    const fixture = load(name)
    const first = fixture.releases[0]
    return {
      name,
      group: { id: fixture.group.id, title: fixture.group.title, 'first-release-date': first?.date ?? '', 'primary-type': 'Album', 'secondary-types': [], 'artist-credit': first?.['artist-credit'] ?? [] },
      releases: fixture.releases,
    }
  })
  const made = { name: 'made', ...madeGroup() }
  return [...real, made].map(({ name, group: preview, releases }) => {
    const ids = releases.map((release) => release.id)
    const typed = ['', 'cd', 'vinyl', 'jp', 'island', '828553', '828 553', 'bonus', 'in your library', 'usual', 'zzz', '  CD  ', 'Go!', 'official 1994']
    const asks = [null, ids[1] ?? null, ids[ids.length - 1] ?? null, 'not-in-this-group', ids[0] ? ids[0].toUpperCase() : null]
    const held = [new Set(), new Set(ids.slice(2, 4)), new Set(ids.slice(-1))]
    const rowOf = (row) => ({ id: row.id, label: row.label, facts: row.facts, note: row.note, kind: row.kind, isDefault: row.isDefault, held: row.held, inStore: !!row.inStore })
    const diffOf = (diff) => (diff ? { added: diff.added, removed: diff.removed, renamed: diff.renamed, versions: diff.versions, lengths: diff.lengths, same: diff.same } : null)
    //? the view: every ask with nothing held, then what is held (and yours) with none asked - the rows, the summary
    const combos = [
      ...asks.map((asked) => [asked, held[0], null]),
      [null, held[1], null], [null, held[1], new Set()], [null, held[1], new Set([...held[1]].slice(0, 1))], [ids[1] ?? null, held[2], new Set(held[2])],
    ]
    const views = combos.map(([asked, set, yours]) => {
      const view = P.pressingsView(releases, asked, set, yours)
      return {
        asked, held: [...set], yours: yours ? [...yours] : null,
        defaultId: view.defaultId, chosenId: view.chosenId,
        shown: view.shown.map(rowOf), more: view.more.map(rowOf),
        summary: P.summaryLine(view, releases.length),
      }
    })
    //? each pressing as the page draws it chosen: its tracklist against the usual one, what it leaves out, the header
    const usual = P.pressingsView(releases)
    const pages = releases.map((chosen) => {
      const diff = usual.diffs.get(chosen.id) ?? null
      return {
        id: chosen.id,
        tracks: P.trackRows(chosen, diff).map((row) => [row.key, row.heading, row.number, row.title, row.length, row.mark ? [row.mark.kind, row.mark.chip, row.mark.note] : null]),
        missing: P.leftOut(diff),
        //? the line above the tracklist with this pressing chosen - every clause of it (adds, leaves out, renames,
        //? another version) met somewhere among the pressings
        summary: P.summaryLine(P.pressingsView(releases, chosen.id), releases.length),
        header: P.pageHeader(releases, chosen, null),
        headerPreview: P.pageHeader(releases, chosen, preview),
      }
    })
    const base = T.chooseBase(releases)
    const all = P.pressingsView(releases, null, held[1], null)
    const rows = [...all.shown, ...all.more]
    return {
      name, preview, releases,
      each: releases.map((release) => ({ id: release.id, format: P.pressingFormat(release), year: P.pressingYear(release), label: P.pressingLabel(release), facts: P.pressingFacts(release) })),
      base: base ? { index: base.index, count: base.count, total: base.total, key: T.tracklistKey(base.tracks), sharedBy: P.sharedBy(base) } : null,
      representative: T.representativeRelease(releases)?.id ?? null,
      chosen: asks.map((asked) => ({ asked, id: P.chosenPressingId(releases, asked) })),
      diffs: Object.fromEntries([...usual.diffs.entries()].map(([id, diff]) => [id, diffOf(diff)])),
      views,
      pages,
      filter: typed.map((words) => {
        const found = P.filterPressings(rows, words)
        return { typed: words, ids: found.map((row) => row.id), said: P.pressingFilterWords(found.length, words) }
      }),
    }
  })
}

function pageWords() {
  const headers = [{ year: '1994', kind: 'Album' }, { year: '', kind: 'Live album' }, { year: '2008', kind: '' }, { year: '', kind: '' }]
  return {
    meta: headers.flatMap((header) => [null, true, false].flatMap((held) => [undefined, 'in the collection', 'another pressing in your library'].map((place) => ({
      header, held, place: place ?? null, said: place === undefined ? P.metaLine(header, held) : P.metaLine(header, held, place),
    })))),
    discHeading: [[1, null], [2, 'Unreleased Tracks'], [3, '  '], [1, ' Live ']].map(([position, title]) => ({ position, title, said: P.discHeading(position, title) })),
    holding: [null, { held: [], guessed: [] }, { held: [1], guessed: [] }, { held: [], guessed: [1] }, { held: [1], guessed: [1] }].map((given) => ({
      given: given ? { held: given.held.length, guessed: given.guessed.length } : null, holding: P.holdingOf(given),
    })),
    covers: [[null, 'g-1'], ['r-1', 'g-1'], ['r-1', '']].map(([release, groupId]) => ({ release, group: groupId, addresses: P.coverAddresses(release, groupId, 250) })),
  }
}

/* ===== out ===== */

function vectors() {
  return {
    numbers: numbers(),
    words: words(),
    typing: typing(),
    groups: groups(),
    holding: holding(),
    studio: studio(),
    moments: moments(),
    cases: cases(),
    pressings: pressings(),
    page: pageWords(),
  }
}

/** JSON with every character outside ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[\u0080-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-search-albums-vectors.cjs, then port the change to DeadwaxCore and see SearchAlbumsVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
