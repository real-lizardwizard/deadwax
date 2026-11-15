#!/usr/bin/env node
/**
 * What's saved, the kept answers and More from MusicBrainz, for the iPhone app's Search (Phase 5, slice 4 -
 * notes/ios-specs/phase5-search.md 5.1 and 6.4): what the web app's own TypeScript answers, written as a fourth fixture
 * beside search-vectors.json, search-albums-vectors.json and search-songs-vectors.json for the Swift ports in
 * ios/DeadwaxKit/Sources/DeadwaxCore (SearchSaved.swift, and slice 4's half of SearchList.swift) to replay
 * (Tests/DeadwaxCoreTests/SearchSavedVectorTests.swift) - so the phone draws what's saved at the library's moment and
 * lets MusicBrainz's answer add only what isn't there, keeps a kind view's rows where they were drawn, keeps the last
 * answers as the web keeps them, and pages More from MusicBrainz as the web does.
 *
 * Compiles lib/searchList.ts, lib/songs.ts, lib/searchResults.ts and app/searchAnswers.ts with what they import, and
 * reads the few words that live in a component (Search.tsx's More button and its note past the furthest page) from its
 * source. Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-saved-vectors.json:
 *
 *   numbers     SAVED_WAIT_MS, SAVED_ARTIST_ALBUMS, SEARCH_ANSWERS_KEPT, MUSICBRAINZ_OFFSET_MAX and SOURCE
 *   words       savedWords, musicBrainzWords (with and without what's saved), savedAwayWords beside failureWords,
 *               nothingMoreWords, morePageWords, moreSongsWords, and More's button and note
 *   groups      the release groups every other vector names by id; `lists` the folder lists they are read against
 *   recordings  every recording search in tests/fixtures/songs/ (embedded)
 *   studio      studioGroup over every group
 *   saved       savedFor over readings, what's saved, the kinds asked, the studio clause and folder lists
 *   areas       kindArea over seeded runs of draws, each from the one before
 *   pages       morePages over next offsets, counts, last pages and limits
 *   append      appendPage over the groups got, a page and a folder list
 *   songPages   appendSongs over runs of pages, each drawn from the one before, with moreSongsWords
 *   kept        keepAnswer and keptAnswer over seeded runs of asks
 *   cases       whole searches with what's saved and MusicBrainz's answers in hand: savedFor, the pool (its saved
 *               block), the candidates, Top results decided at the library's moment and completed, the sections, the
 *               rows MusicBrainz's answer adds to what's saved drawn (lateRows, drawnCounts), and every MusicBrainz
 *               row's relatives with their marks
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-search-saved-vectors.cjs           write the fixture
 *   node ios/scripts/export-search-saved-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'search', 'search-saved-vectors.json')
const SONG_FIXTURES = path.join(REPO, 'tests', 'fixtures', 'songs')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-saved-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchList.ts', 'src/lib/songs.ts', 'src/lib/searchResults.ts', 'src/app/searchAnswers.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/searchList.js'))
const Q = require(path.join(OUT, 'lib/searchQuery.js'))
const R = require(path.join(OUT, 'lib/searchResults.js'))
const S = require(path.join(OUT, 'lib/songs.js'))
const O = require(path.join(OUT, 'lib/owned.js'))
const K = require(path.join(OUT, 'app/searchAnswers.js'))

/** A component's source, which the exporter can't compile without Preact - every group of the first match. */
function sourceMatches(file, pattern) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(pattern)
  if (!found) throw new Error(`${file} no longer has ${pattern}`)
  return found.slice(1)
}

/* ===== seeded randomness ===== */

let seed = 5454
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const chance = (p) => rand() < p
const some = (list, p) => list.filter(() => chance(p))
const shuffled = (list) => {
  const out = [...list]
  for (let at = out.length - 1; at > 0; at--) {
    const other = Math.floor(rand() * (at + 1))
    ;[out[at], out[other]] = [out[other], out[at]]
  }
  return out
}

/* ===== the recording searches ===== */

const NAMES = ['roads-portishead', 'roads-portishead-free', 'patience-tame-impala', 'hey-jude-beatles', 'hey-jude-free',
  'miss-misery-elliott-smith', 'bohemian-rhapsody-queen']
const FIX = Object.fromEntries(NAMES.map((name) => [name, JSON.parse(fs.readFileSync(path.join(SONG_FIXTURES, `${name}.json`), 'utf8'))]))
const RECORDINGS = Object.fromEntries(NAMES.map((name) => [name, FIX[name].recordings]))
const SONGS = Object.fromEntries(NAMES.map((name) => [name, S.groupSongs(RECORDINGS[name])]))

//? a made search, beside the recorded ones (never among NAMES, so no seeded choice moves): a song whose first take is
//? on no release, so never drawn, then a take of it on one - it comes after the songs drawn, not in its first take's
//? place (songs.ts' review) - and a page after that, where only what was DRAWN, not groupSongs of the recordings so far,
//? keeps the order (mutation 14 of slice 4)
const MADE = 'made-a-first-take-on-no-release'
RECORDINGS[MADE] = (() => {
  const credit = [{ name: 'Portishead', artist: { id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' } }]
  const take = (n, title, onRelease) => ({
    id: `00000000-0000-4000-8000-0000000000${n}0`, title, 'artist-credit': credit,
    releases: onRelease ? [{
      id: `00000000-0000-4000-8000-0000000000${n}1`, title, status: 'Official', 'artist-credit': credit,
      'release-group': { id: `00000000-0000-4000-8000-0000000000${n}2`, title, 'primary-type': 'Album', 'secondary-types': [] },
    }] : [],
  })
  return [take(1, 'Beta', false), take(2, 'Alpha', true), take(3, 'Beta', true), take(4, 'Gamma', true), take(5, 'Alpha', true)]
})()

/* ===== the numbers and the words ===== */

function numbers() {
  return {
    savedWaitMs: L.SAVED_WAIT_MS,
    savedArtistAlbums: L.SAVED_ARTIST_ALBUMS,
    answersKept: K.SEARCH_ANSWERS_KEPT,
    offsetMax: R.MUSICBRAINZ_OFFSET_MAX,
    sources: L.SOURCE,
  }
}

const COUNTS = [{}, { artists: 1 }, { albums: 2 }, { songs: 1 }, { artists: 2, albums: 1, songs: 11 }, { artists: 0, albums: 0 },
  { albums: 1, songs: 0 }, { artists: 1, albums: 1, songs: 1 }, { songs: 25 }, { artists: 10, albums: 12 }]
const FAILURES = [
  { refused: true, busy: false, message: 'Type fewer words to search for.', unavailable: false },
  { refused: false, busy: true, message: 'MusicBrainz is busy.', unavailable: false },
  { refused: false, busy: false, message: "MusicBrainz couldn't be reached.", unavailable: true },
  { refused: false, busy: false, message: 'Something else went wrong.', unavailable: false },
]
const TEXTS = ['roads', 'glory box', '“quoted”', 'Björk', 'hey jude']

function words() {
  const [loading, tryAgain, songs, artists, albums] = sourceMatches('src/app/Search.tsx',
    /more\?\.state === 'asking' \? '([^']*)' : more\?\.state === 'failed' \? '([^']*)' : kind === 'songs' \? '([^']*)' : kind === 'artists' \? '([^']*)' : '([^']*)'/)
  const [far] = sourceMatches('src/app/Search.tsx', /app-search-more-note" tabIndex=\{-1\}>\{"([^"]*)"\}/)
  const flags = [false, true]
  return {
    saved: COUNTS.map((counts) => ({ counts, said: L.savedWords(counts) })),
    musicBrainz: COUNTS.flatMap((counts) => flags.flatMap((answered) => flags.map((saved) => ({ counts, answered, saved, said: L.musicBrainzWords(counts, answered, saved) })))),
    savedAway: FAILURES.flatMap((failure) => flags.map((short) => ({ failure, short, said: L.savedAwayWords(failure, short), plain: L.failureWords(failure, short) }))),
    nothingMore: L.KINDS.flatMap((kind) => TEXTS.map((text) => ({ kind, text, said: L.nothingMoreWords(kind, text) }))),
    morePage: [0, 1, 2, 3, 12].flatMap((added) => [0, 1, 2, 7].flatMap((held) => flags.map((personal) => ({ added, held, personal, ...R.morePageWords(added, held, personal) })))),
    moreSongs: [0, 1, 2, 9].flatMap((added) => [0, 1, 2, 5].map((grown) => ({ added, grown, ...S.moreSongsWords(added, grown) }))),
    buttons: { albums, artists, songs, loading, tryAgain },
    far,
  }
}

/* ===== the groups and the folder lists ===== */

const MBID = {
  portishead: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11',
  portisheadTribute: '1d2c3b4a-0000-4000-8000-00000000aa01',
  tame: '63aa26c3-d59b-4da4-84ac-716b54f1ef4d',
  beatles: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
  queen: '0383dadf-2a4e-4d10-a46a-e9e041da8eb3',
  queenLambert: '1d2c3b4a-0000-4000-8000-00000000aa02',
  elliott: '03ad1736-b7c9-412a-b442-82536d63a5c4',
  beth: '1d2c3b4a-0000-4000-8000-00000000aa03',
}
const credited = (mbid, name) => [{ name, joinphrase: '', artist: { id: mbid, name } }]
const groupOf = (id, title, date, primary, secondary, credit) => ({ id, title, 'first-release-date': date, 'primary-type': primary, 'secondary-types': secondary, 'artist-credit': credit })
const gid = (n) => `a4a5b1c6-0b43-3d1a-8e0b-${String(n).padStart(12, '0')}`
const P = credited(MBID.portishead, 'Portishead')
const G = {
  dummy: groupOf('48140466-cff6-3222-bd55-63c27e43190d', 'Dummy', '1994-08-22', 'Album', [], P),
  third: groupOf(gid(1), 'Third', '2008-04-28', 'Album', [], P),
  self: groupOf(gid(2), 'Portishead', '1997-09-29', 'Album', [], P),
  roseland: groupOf(gid(3), 'Roseland NYC Live', '1998-11-02', 'Album', ['Live'], P),
  remix: groupOf(gid(4), 'Dummy Remixed', '1995-06', 'Album', ['Remix'], P),
  sour: groupOf(gid(5), 'Sour Times', '1994-08', 'Single', [], P),
  ep: groupOf(gid(6), 'Glory Box EP', '1995-01', 'EP', [], P),
  liveEp: groupOf(gid(7), 'Live at Roseland EP', '1998', 'EP', ['Live'], P),
  soundtrack: groupOf(gid(8), 'To Kill a Dead Man', '1994', 'Album', ['Soundtrack'], P),
  undated: groupOf(gid(9), 'Untitled', '', 'Album', [], P),
  lower: groupOf(gid(10), 'Machine Gun', '2007-11', 'album', [], credited(MBID.portishead, 'portishead')),
  beth: groupOf(gid(11), 'Out of Season', '2002-10-28', 'Album', [], [{ name: 'Beth Gibbons', joinphrase: ' & ', artist: { id: MBID.beth, name: 'Beth Gibbons' } }, { name: 'Rustin Man', joinphrase: '', artist: { id: '1d2c3b4a-0000-4000-8000-00000000aa04', name: 'Rustin Man' } }]),
  tribute: groupOf(gid(12), 'A Tribute to Portishead', '2004', 'Album', ['Compilation'], credited(MBID.portisheadTribute, 'Portishead')),
  rush: groupOf(gid(13), 'The Slow Rush', '2020-02-14', 'Album', [], credited(MBID.tame, 'Tame Impala')),
  currents: groupOf(gid(14), 'Currents', '2015-07-17', 'Album', [], credited(MBID.tame, 'Tame Impala')),
  opera: groupOf(gid(15), 'A Night at the Opera', '1975-11-21', 'Album', [], credited(MBID.queen, 'Queen')),
  hits: groupOf(gid(16), 'Greatest Hits', '1981-10-26', 'Album', ['Compilation'], credited(MBID.queen, 'Queen')),
  abbey: groupOf(gid(17), 'Abbey Road', '1969-09-26', 'Album', [], credited(MBID.beatles, 'The Beatles')),
  either: groupOf(gid(18), 'Either/Or', '1997-02-25', 'Album', [], credited(MBID.elliott, 'Elliott Smith')),
  noType: { id: gid(19), title: 'No type', 'first-release-date': '2001', 'artist-credit': P },
  noCredit: { id: gid(20), title: 'Nobody', 'first-release-date': '2003', 'primary-type': 'Album' },
}
const GROUPS = Object.values(G)

/** A song search's own albums as groups, so a saved group can be a song's named album. */
function songGroups(name, take) {
  const [first] = SONGS[name]
  if (!first) return []
  return first.albums.slice(0, take).map((album) => groupOf(album.id, album.title, album.date, album.primaryType ?? undefined, album.secondaryTypes, credited(first.artists[0]?.id ?? MBID.portishead, first.credit)))
}
const SONG_GROUPS = Object.fromEntries(NAMES.map((name) => [name, songGroups(name, 4)]))
const ALL_GROUPS = [...GROUPS, ...[...new Map(Object.values(SONG_GROUPS).flat().map((group) => [group.id, group])).values()].filter((group) => !GROUPS.some((each) => each.id === group.id))]
const BY_ID = new Map(ALL_GROUPS.map((group) => [group.id, group]))
const ids = (groups) => groups.map((group) => group.id)
const groupsOf = (list) => list.map((id) => BY_ID.get(id))

const folder = (path, artist, album, extra = {}) => ({ path, artist, album, ...extra })
const madeId = (n) => `0000000${n % 10}-aaaa-4bbb-8ccc-${String(n).padStart(12, '0')}`
const REL = { dummy: '76df3287-6cda-33eb-8e9a-044b5e15ffdd', third: '930345b1-a970-3495-a1dd-55147bea7741' }

/** Folder lists: none answered, nothing held, Dummy yours, a mix of Portishead's (one by name alone), and every song
 *  search's first album held - so what's saved has albums the library holds left out, and brought in. */
function folderLists() {
  const firsts = NAMES.map((name) => SONGS[name][0]).filter(Boolean)
  return [
    null,
    [],
    [folder('Portishead/Dummy', 'Portishead', 'Dummy', { release_mbid: REL.dummy, release_group_mbid: G.dummy.id, yours: true })],
    [
      folder('Portishead/Dummy', 'Portishead', 'Dummy', { release_mbid: REL.dummy, release_group_mbid: G.dummy.id, yours: false }),
      folder('Portishead/Third', 'Portishead', 'Third', { release_mbid: REL.third, release_group_mbid: G.third.id, yours: true }),
      folder('Portishead/Roseland', 'Portishead', 'Roseland NYC Live', { release_group_mbid: G.roseland.id }),
      folder('Portishead/Glory Box', 'Portishead', 'Glory Box EP'),
      folder('Tame Impala/Currents', 'Tame Impala', 'Currents', { release_mbid: madeId(4), release_group_mbid: G.currents.id, yours: false }),
    ],
    firsts.map((song, at) => folder(`${song.credit}/${song.albums[0].title}`, song.credit, song.albums[0].title,
      { release_mbid: song.albums[0].releases[0], release_group_mbid: song.albums[0].id, yours: at % 2 === 0 })),
  ]
}
const LISTS = folderLists()
const indexOf = (list) => (LISTS[list] ? O.buildOwnedIndex(LISTS[list]) : null)

/* ===== studioGroup and savedFor ===== */

function studio() {
  return ALL_GROUPS.map((group) => ({ group: group.id, studio: L.studioGroup(group) }))
}

const match = (mbid, name, extra = {}) => ({ mbid, name, disambiguation: '', country: '', type: '', matched_as: '', ...extra })
const MATCHES = {
  portishead: [match(MBID.portishead, 'Portishead', { type: 'Group', country: 'GB' }), match(MBID.portisheadTribute, 'Portishead', { disambiguation: 'tribute band', type: 'Group' })],
  portisheadAlone: [match(MBID.portishead, 'Portishead', { type: 'Group', country: 'GB', score: 100 })],
  tame: [match(MBID.tame, 'Tame Impala', { type: 'Group', country: 'AU' })],
  beatles: [match(MBID.beatles, 'The Beatles', { type: 'Group', country: 'GB' }), match(MBID.queenLambert, 'Beatles Revival', { matched_as: 'The Beatles' })],
  queen: [match(MBID.queen, 'Queen', { type: 'Group', country: 'GB' }), match(MBID.queenLambert, 'Queen + Adam Lambert', { type: 'Group', matched_as: 'Queen' })],
  elliott: [match(MBID.elliott, 'Elliott Smith', { type: 'Person', country: 'US' })],
  beth: [match(MBID.beth, 'Beth Gibbons', { type: 'Person', country: 'GB' })],
}
const ALL_MATCHES = [...new Map(Object.values(MATCHES).flat().map((each) => [each.mbid, each])).values()]

const READ_NAMES = [[], ['Portishead'], ['Portishead', 'Tame Impala', 'Queen', 'The Beatles', 'Elliott Smith']]
const SAVED_TEXTS = ['portishead', 'Portishead', 'PORTISHEAD', 'dummy portishead', 'roads portishead', 'portishead dummy', 'glory box',
  'tame impala', 'queen', 'bohemian rhapsody queen', 'the beatles', 'hey jude', 'elliott smith', 'beth gibbons', 'third', 'roads']

/** What the web's Search hands savedFor (Search.tsx `savedOf`): the kinds a view asks (wantedKinds), the studio clause
 *  in All, the index as it is drawn. */
function wantedKinds(term, plan, view) {
  return L.KINDS.filter((kind) => (view === 'all' || view === kind)
    && (kind === 'artists' ? plan.kind !== 'album-by-artist' : kind === 'albums' ? true : !!Q.songSearchQuery(term, plan)))
}

function savedFound({ matches, groups, credited, songs }) {
  return {
    matches,
    groups: groupsOf(groups),
    ...(credited ? { credited: groupsOf(credited) } : {}),
    songs: songs ? S.groupSongs(RECORDINGS[songs.name].slice(0, songs.take)) : [],
  }
}

const answerOut = (answer) => answer && {
  matches: answer.matches.map((each) => each.mbid), groups: ids(answer.groups), shown: ids(answer.shown), songs: answer.songs.map((song) => song.key),
}

function savedCase({ text, names, found, view, list, kinds = null, studio = null }) {
  const term = text.trim()
  const plan = Q.searchQuery(term, Q.artistNames(names))
  const out = { text, names, found, view, list, plan, given: kinds !== null }
  if (!plan) return out
  const asked = kinds ?? wantedKinds(term, plan, view)
  const clause = studio ?? (view === 'all' && L.allAlbumsQuery(plan).studio)
  out.kinds = asked
  out.studio = clause
  out.answer = answerOut(L.savedFor(plan, found ? savedFound(found) : null, asked, clause, indexOf(list)))
  return out
}

function saved() {
  const out = []
  const P_ALL = ids([G.dummy, G.third, G.self, G.roseland, G.remix, G.sour, G.ep, G.liveEp, G.soundtrack, G.undated, G.lower, G.beth, G.tribute, G.noType, G.noCredit])
  const fixed = [
    //? the artist reading: their albums from `credited`, studio ones in studio order, at most SAVED_ARTIST_ALBUMS
    { text: 'portishead', names: ['Portishead'], view: 'all', list: 0, found: { matches: MATCHES.portishead, groups: [G.dummy.id], credited: P_ALL, songs: null } },
    { text: 'portishead', names: ['Portishead'], view: 'albums', list: 3, found: { matches: MATCHES.portishead, groups: [G.dummy.id], credited: P_ALL, songs: null } },
    { text: 'portishead', names: ['Portishead'], view: 'all', list: 2, found: { matches: [], groups: P_ALL, songs: null } },
    { text: 'portishead', names: ['Portishead'], view: 'all', list: 1, found: { matches: [], groups: [...P_ALL, ...P_ALL.map((id) => id)], credited: [...P_ALL, ...P_ALL], songs: null } },
    { text: 'portishead', names: ['Portishead'], view: 'artists', list: 3, found: { matches: MATCHES.portishead, groups: P_ALL, credited: P_ALL, songs: { name: 'roads-portishead', take: 12 } } },
    { text: 'portishead', names: ['Portishead'], view: 'songs', list: 3, found: { matches: MATCHES.portishead, groups: P_ALL, songs: { name: 'roads-portishead', take: 12 } } },
    //? free words and a title by an artist: every group the words found, songs and artists as the kinds ask
    { text: 'roads portishead', names: ['Portishead'], view: 'all', list: 4, found: { matches: MATCHES.portishead, groups: ids(SONG_GROUPS['roads-portishead']), songs: { name: 'roads-portishead', take: 12 } } },
    { text: 'dummy portishead', names: ['Portishead'], view: 'all', list: 3, found: { matches: MATCHES.portishead, groups: P_ALL, songs: { name: 'roads-portishead', take: 4 } } },
    { text: 'glory box', names: [], view: 'all', list: 0, found: { matches: [], groups: [G.ep.id, G.sour.id], songs: null } },
    { text: 'glory box', names: [], view: 'all', list: 3, found: null },
    { text: 'roads', names: [], view: 'songs', list: 4, found: { matches: MATCHES.portisheadAlone, groups: [], songs: { name: 'roads-portishead-free', take: 12 } } },
    { text: 'Portishead', names: ['portishead'], view: 'all', list: 3, found: { matches: [], groups: [G.lower.id, G.tribute.id, G.self.id], credited: [G.lower.id, G.tribute.id, G.self.id], songs: null } },
    //? kinds and the studio clause given as the web might hand them
    { text: 'portishead', names: ['Portishead'], view: 'all', list: 3, kinds: [], studio: true, found: { matches: MATCHES.portishead, groups: P_ALL, songs: { name: 'roads-portishead', take: 3 } } },
    { text: 'portishead', names: ['Portishead'], view: 'all', list: 3, kinds: ['albums'], studio: false, found: { matches: [], groups: P_ALL, credited: P_ALL, songs: null } },
    { text: 'third', names: [], view: 'all', list: 3, kinds: ['albums', 'songs'], studio: true, found: { matches: [], groups: P_ALL, songs: null } },
  ]
  for (const each of fixed) out.push(savedCase(each))
  for (let number = 0; number < 120; number++) {
    const groups = some(ALL_GROUPS, 0.25).map((group) => group.id)
    out.push(savedCase({
      text: pick(SAVED_TEXTS),
      names: pick(READ_NAMES),
      view: pick(['all', 'all', 'albums', 'artists', 'songs']),
      list: Math.floor(rand() * LISTS.length),
      found: chance(0.08) ? null : {
        matches: some(ALL_MATCHES, 0.3),
        groups: shuffled(groups),
        ...(chance(0.6) ? { credited: shuffled(some(ALL_GROUPS, 0.35).map((group) => group.id)) } : {}),
        songs: chance(0.3) ? null : { name: pick(NAMES), take: Math.floor(rand() * 13) },
      },
    }))
  }
  return out
}

/* ===== a kind view's rows, kept in place ===== */

/** Runs of a kind view's draws: what's saved and MusicBrainz's rows as each draw has them (keys, some held above),
 *  MusicBrainz's failure drawn or not - each arranged from the one before (Search.tsx's kindView). */
function areas() {
  const KEYS = Array.from({ length: 9 }, (_, n) => `group:k${n}`)
  const out = []
  for (let run = 0; run < 70; run++) {
    let before = null
    const steps = []
    const length = 1 + Math.floor(rand() * 6)
    for (let step = 0; step < length; step++) {
      const saved = shuffled(some(KEYS, 0.35))
      //? a first draw often what's saved alone, MusicBrainz's answer landing after it
      const musicbrainz = step === 0 && chance(0.5) ? [] : shuffled(some(KEYS, 0.4))
      if (chance(0.15) && saved.length) saved.push(pick(saved))
      if (chance(0.15) && musicbrainz.length) musicbrainz.push(pick(musicbrainz))
      const above = some(KEYS, 0.1)
      const problem = chance(0.2)
      const rowsOf = (keys, isSaved) => keys.map((key) => (isSaved ? L.savedRow(L.groupRow({ id: key.slice(6) })) : L.groupRow({ id: key.slice(6) })))
      const made = L.kindArea(before, rowsOf(saved, true), rowsOf(musicbrainz, false), new Set(above), problem)
      steps.push({
        saved, musicbrainz, above, problem,
        lead: made.lead.map((row) => [row.key, L.isSaved(row)]),
        rest: made.rest.map((row) => [row.key, L.isSaved(row)]),
        area: made.area,
      })
      before = made.area
    }
    out.push({ steps })
  }
  return out
}

/* ===== More from MusicBrainz ===== */

function pages() {
  const out = []
  for (const next of [0, 1, 11, 12, 24, 25, 999, 1000, 1001, 1012, 1500])
    for (const count of [null, 0, 12, 24, 25, 30, 1000, 1001, 5000])
      for (const last of [0, 1, 11, 12, 25])
        for (const limit of [10, 12, 25]) out.push({ next, count, last, limit, pages: R.morePages(next, count, last, limit) })
  return out
}

function append() {
  const out = []
  for (let number = 0; number < 90; number++) {
    const list = Math.floor(rand() * LISTS.length)
    const index = indexOf(list)
    const got = some(ALL_GROUPS, 0.2)
    const shown = R.notInLibrary(got, index)
    const page = shuffled([...some(ALL_GROUPS, 0.2), ...(chance(0.4) ? some(got, 0.5) : [])])
    if (chance(0.15) && page.length) page.push(pick(page))
    //? now and then a page that brought nothing
    const given = chance(0.08) ? [] : page
    const made = R.appendPage(got, shown, given, index)
    out.push({
      groups: ids(got), shown: ids(shown), page: ids(given), list,
      out: { groups: ids(made.groups), shown: ids(made.shown), added: made.added, held: made.held, ...R.morePageWords(made.added, made.held, list % 2 === 1) },
    })
  }
  return out
}

/** One page of songs merged, as a vector: the page, what it made of the recordings and songs, and its words. */
function songStep(page, merged) {
  return {
    page,
    recordings: merged.recordings.length,
    songs: merged.songs.map((song) => [song.key, song.albums.map((album) => album.id).join(',')]),
    added: merged.added,
    grown: merged.grown,
    ...S.moreSongsWords(merged.added, merged.grown),
  }
}

/** Runs of More songs: a first page, then pages after it - the same search's next recordings, a page of repeats, another
 *  search's, nothing - each merged into what the one before drew (Search.tsx's askMoreSongs). */
function songPages() {
  const out = []
  const recording = ([name, at]) => RECORDINGS[name][at]
  for (let run = 0; run < 40; run++) {
    const name = pick(NAMES)
    const size = 1 + Math.floor(rand() * 6)
    const first = Array.from({ length: Math.min(size, RECORDINGS[name].length) }, (_, at) => [name, at])
    let at = first.length
    let recordings = first.map(recording)
    let songs = S.groupSongs(recordings)
    const steps = []
    const length = 1 + Math.floor(rand() * 4)
    for (let step = 0; step < length; step++) {
      const roll = rand()
      let page
      if (roll < 0.5) {
        page = Array.from({ length: Math.max(0, Math.min(size, RECORDINGS[name].length - at)) }, (_, n) => [name, at + n])
        at += page.length
      } else if (roll < 0.65) {
        page = first.slice(0, 1 + Math.floor(rand() * first.length))
      } else if (roll < 0.9) {
        const other = pick(NAMES)
        page = shuffled(RECORDINGS[other].map((_, n) => [other, n])).slice(0, size)
      } else {
        page = []
      }
      const merged = S.appendSongs(recordings, page.map(recording), songs)
      steps.push(songStep(page, merged))
      recordings = merged.recordings
      songs = merged.songs
    }
    out.push({ first, firstSongs: S.groupSongs(first.map(recording)).map((song) => song.key), steps })
  }
  //? the made run: Alpha drawn (Beta's first take on no release); Beta's take on one after it; then Gamma, and Alpha's
  //? second album added in place - Alpha and Beta kept as drawn; then nothing
  {
    const first = [[MADE, 0], [MADE, 1]]
    let recordings = first.map(recording)
    let songs = S.groupSongs(recordings)
    const steps = []
    for (const page of [[[MADE, 2]], [[MADE, 3], [MADE, 4]], []]) {
      const merged = S.appendSongs(recordings, page.map(recording), songs)
      steps.push(songStep(page, merged))
      recordings = merged.recordings
      songs = merged.songs
    }
    out.push({ first, firstSongs: S.groupSongs(first.map(recording)).map((song) => song.key), steps })
  }
  //? appendSongs' own default for what was drawn: groupSongs of the recordings so far
  const defaults = NAMES.map((name) => {
    const recordings = RECORDINGS[name]
    const made = S.appendSongs(recordings.slice(0, 5), recordings.slice(5))
    return { name, split: 5, songs: made.songs.map((song) => song.key), added: made.added, grown: made.grown }
  })
  return { runs: out, defaults }
}

/* ===== the kept answers ===== */

/** Runs of asks against the kept answers (app/searchAnswers.ts): keep a success, look one up - `present` the keys of
 *  POOL kept after each step, in POOL's order. */
function kept() {
  const POOL = Array.from({ length: 36 }, (_, n) => `ask-${n}`)
  const out = []
  let value = 0
  for (let run = 0; run < 6; run++) {
    K.forgetAnswers()
    const steps = []
    const length = 40 + Math.floor(rand() * 60)
    for (let step = 0; step < length; step++) {
      const key = run === 0 ? POOL[step % POOL.length] : pick(POOL)
      if (chance(0.6)) {
        value++
        K.keepAnswer(key, value)
        steps.push({ keep: key, value, present: POOL.filter((each) => K.keptAnswer(each) !== null) })
      } else {
        steps.push({ look: key, found: K.keptAnswer(key) })
      }
    }
    out.push({ steps })
  }
  K.forgetAnswers()
  return out
}

/* ===== whole searches with what's saved ===== */

const PA = { id: 'ar-p', name: 'Portishead', albumCount: 3, musicBrainzId: MBID.portishead }
const PB = { id: 'ar-p', name: 'Portishead', albumCount: 3 }
const TI = { id: 'ar-t', name: 'Tame Impala', albumCount: 4 }
const QU = { id: 'ar-q', name: 'Queen', albumCount: 12, musicBrainzId: ` ${MBID.queen.toUpperCase()} ` }
const BE = { id: 'ar-b', name: 'The Beatles', albumCount: 13 }
const ES = { id: 'ar-e', name: 'Elliott Smith', albumCount: 6, musicBrainzId: MBID.elliott }
const ARTISTS = [PA, TI, QU, BE, ES]

const dummy = { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', artistId: 'ar-p', year: 1994, coverArt: 'al-dummy', musicBrainzId: REL.dummy }
const third = { id: 'nd-third', name: 'Third', artist: 'Portishead', artistId: 'ar-p', year: 2008 }
const rush = { id: 'nd-rush', name: 'The Slow Rush', artist: 'Tame Impala', artistId: 'ar-t', year: 2020 }
const opera = { id: 'nd-opera', name: 'A Night at the Opera', artist: 'Queen', artistId: 'ar-q', year: 1975 }
const libSong = (id, title, album) => ({ id, title, artist: album.artist, artistId: album.artistId, album: album.name, albumId: album.id, coverArt: album.coverArt })
const roads = libSong('s-roads', 'Roads', dummy)
const patienceSong = libSong('s-patience', 'Patience', rush)
const rhapsody = libSong('s-bohemian', 'Bohemian Rhapsody', opera)
const lib = (artists = [], albums = [], songs = []) => ({ artists, albums, songs })

/** What the web's Search hands the rules for one search with what's saved in hand, and then MusicBrainz's answers too
 *  (Search.tsx's savedOf, rows, familyFor, decided and the late kinds' rows). */
function webCase({ text, library, failed = false, artistList = null, list = 0, matches = null, groups = null, songs = null, saved = null, personal = false, yourAlbums = null, yourArtists = null }) {
  const folders = LISTS[list]
  const index = folders ? O.buildOwnedIndex(folders) : null
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
  const evidence = { heard: results?.songs ?? null, pressings: () => null }
  const term = text.trim()
  const plan = Q.searchQuery(term, Q.artistNames([...ownedArtists, ...(results?.artists ?? []).map((artist) => artist.name)]))
  const out = { text, library, failed, artistList, list, matches, groups, songs, saved, personal, yourAlbums, yourArtists, plan }
  if (!plan) return out
  const kinds = wantedKinds(term, plan, 'all')
  const studio = L.allAlbumsQuery(plan).studio
  const answer = saved ? L.savedFor(plan, savedFound(saved), kinds, studio, index) : null
  const found = songs ? S.groupSongs(RECORDINGS[songs.name].slice(0, songs.take)) : null
  const mbGroups = groups ? groupsOf(groups) : null
  const albums = mbGroups ? { groups: mbGroups, shown: R.notInLibrary(mbGroups, index) } : null
  const input = { reading: plan, library: results, artistList, index, marks, evidence }
  const atMoment = L.pool({ ...input, artists: null, albums: null, songs: null, saved: answer })
  const rows = L.pool({ ...input, artists: matches, albums, songs: found, saved: answer })
  const keptGroups = answer?.groups ?? []
  const savedIds = new Set(keptGroups.map((group) => group.id))
  const familyAtMoment = { library: results, artistList, index, evidence, groups: [...keptGroups], saved: savedIds }
  const family = { ...familyAtMoment, groups: [...keptGroups, ...(mbGroups ?? [])] }
  const momentCandidates = L.candidatesOf(atMoment, term, plan)
  const candidates = L.candidatesOf(rows, term, plan)
  const n = L.TOP_RESULTS.phone
  const flagged = (row) => [row.key, L.isSaved(row)]
  const decided = [kinds, ['albums'], []].map((out_) => {
    const made = L.decidedTop(momentCandidates, out_.map((kind) => L.phantom(kind, plan)).filter(Boolean), n, familyAtMoment)
    return { kinds: out_, prefix: made.prefix.map(flagged), place: made.place }
  })
  const prefix = L.decidedTop(momentCandidates, kinds.map((kind) => L.phantom(kind, plan)).filter(Boolean), n, familyAtMoment).prefix
  const placed = (list_) => list_.map((each) => [each.row.key, each.holder, each.position, !!each.saved, L.isSaved(each.row)])
  out.kinds = kinds
  out.studio = studio
  out.answer = answerOut(answer)
  out.pool = Object.fromEntries(L.KINDS.map((kind) => [kind, { library: placed(rows[kind].library), brought: placed(rows[kind].brought), saved: placed(rows[kind].saved), musicbrainz: placed(rows[kind].musicbrainz) }]))
  out.moment = Object.fromEntries(L.KINDS.map((kind) => [kind, { brought: placed(atMoment[kind].brought), saved: placed(atMoment[kind].saved) }]))
  out.candidates = candidates.map((each) => [each.key, each.tier, each.source, each.position, L.isSaved(each.row)])
  out.decided = decided
  out.top = L.topResults(candidates, n, family).map((each) => flagged(each.row))
  out.topFixed = L.topResults(candidates, n, family, prefix).map((each) => flagged(each.row))
  out.sections = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind], L.PREVIEW.phone[kind]).map((row) => row.key)]))
  out.full = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind]).map((row) => row.key)]))
  //? what's saved drawn at the library's moment, then what MusicBrainz's answer adds to it - only what isn't there
  out.late = Object.fromEntries(L.KINDS.map((kind) => {
    const drawn = L.sectionRows(atMoment[kind], L.PREVIEW.phone[kind])
    const keys = new Set(drawn.map((row) => row.key))
    return [kind, {
      drawn: drawn.map((row) => row.key),
      counts: L.drawnCounts(rows[kind], drawn),
      capped: L.lateRows(rows[kind], L.PREVIEW.phone[kind], keys).map((row) => row.key),
      all: L.lateRows(rows[kind], null, keys).map((row) => row.key),
    }]
  }))
  const every = L.KINDS.flatMap((kind) => [...rows[kind].library, ...rows[kind].brought, ...rows[kind].saved, ...rows[kind].musicbrainz])
  out.families = every.filter((each) => each.row.type === 'mb-song' || each.row.type === 'group')
    .map((each) => ({ key: each.row.key, saved: L.isSaved(each.row), family: L.familyOf(each.row, family).map(flagged) }))
  return out
}

const P_STUDIO = ids([G.dummy, G.third, G.self, G.roseland, G.remix, G.ep, G.sour])
const FIXED = [
  //? an artist's name alone: their saved studio albums lead, MusicBrainz's answer adds only what isn't there
  { text: 'portishead', library: lib([PA], [dummy], []), artistList: [PA], list: 2, matches: MATCHES.portishead, groups: ids([G.dummy, G.third, G.ep]), saved: { matches: MATCHES.portisheadAlone, groups: [G.self.id], credited: P_STUDIO, songs: null } },
  { text: 'portishead', library: lib([PA], [dummy], []), artistList: [PA], list: 3, matches: null, groups: null, saved: { matches: MATCHES.portishead, groups: [], credited: P_STUDIO, songs: null } },
  { text: 'portishead', library: lib([], [], []), artistList: [PB], list: 3, matches: MATCHES.portishead, groups: P_STUDIO, saved: { matches: MATCHES.portishead, groups: P_STUDIO, credited: P_STUDIO, songs: null }, personal: true, yourAlbums: [], yourArtists: [] },
  //? a song by an artist: saved songs first, MusicBrainz's takes of the same songs not drawn twice
  { text: 'roads portishead', library: lib([PA], [], []), artistList: [PA], list: 0, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 }, groups: ids(SONG_GROUPS['roads-portishead']), saved: { matches: MATCHES.portisheadAlone, groups: ids(SONG_GROUPS['roads-portishead'].slice(0, 2)), songs: { name: 'roads-portishead', take: 5 } } },
  { text: 'roads portishead', library: lib([PA], [dummy], [roads]), artistList: [PA], list: 4, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 }, saved: { matches: [], groups: ids(SONG_GROUPS['roads-portishead']), songs: { name: 'roads-portishead', take: 12 } } },
  { text: 'roads portishead', library: lib([], [], []), artistList: null, list: 4, matches: null, songs: null, saved: { matches: MATCHES.portishead, groups: ids(SONG_GROUPS['roads-portishead']), songs: { name: 'roads-portishead', take: 12 } }, personal: true, yourAlbums: [], yourArtists: [] },
  //? what's saved alone, every MusicBrainz kind failed
  { text: 'patience tame impala', library: lib([TI], [rush], [patienceSong]), artistList: [TI], list: 4, saved: { matches: MATCHES.tame, groups: ids(SONG_GROUPS['patience-tame-impala']), songs: { name: 'patience-tame-impala', take: 4 } } },
  { text: 'bohemian rhapsody queen', library: lib([QU], [opera], [rhapsody]), artistList: [QU], list: 3, matches: MATCHES.queen, songs: { name: 'bohemian-rhapsody-queen', take: 12 }, saved: { matches: MATCHES.queen.slice(1), groups: ids([G.opera, G.hits]), songs: { name: 'bohemian-rhapsody-queen', take: 3 } } },
  //? a library artist MusicBrainz's answer and what's saved both name: brought in once
  { text: 'elliott smith', library: lib([], [], []), artistList: [ES], list: 1, matches: MATCHES.elliott, groups: [G.either.id], saved: { matches: MATCHES.elliott, groups: [G.either.id], credited: [G.either.id], songs: null } },
  { text: 'the beatles', library: lib([BE], [], []), artistList: [BE], list: 1, matches: MATCHES.beatles, saved: { matches: MATCHES.beatles.slice(1), groups: [G.abbey.id], credited: [G.abbey.id], songs: null } },
  //? the library failed: what's saved and MusicBrainz's answer alone
  { text: 'roads portishead', library: null, failed: true, artistList: [PA], list: 4, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 }, saved: { matches: MATCHES.portishead, groups: [], songs: { name: 'roads-portishead', take: 6 } } },
  { text: 'hey jude', library: lib(), artistList: [BE], list: 4, matches: [], songs: { name: 'hey-jude-free', take: 12 }, saved: { matches: [], groups: ids(SONG_GROUPS['hey-jude-free']), songs: { name: 'hey-jude-beatles', take: 12 } } },
]

const WORDS = ['roads', 'portishead', 'patience', 'tame', 'impala', 'hey', 'jude', 'beatles', 'queen', 'bohemian', 'rhapsody', 'miss',
  'misery', 'elliott', 'smith', 'dummy', 'the', 'third', 'glory', 'box']

function seededCase() {
  const songsOf = pick(NAMES)
  const artists = some(ARTISTS, 0.3)
  const albums = some([dummy, third, rush, opera], 0.35)
  const library = [roads, patienceSong, rhapsody].filter((each) => albums.some((album) => album.id === each.albumId) && chance(0.5))
  const artistList = chance(0.75) ? some(ARTISTS, 0.5).concat(chance(0.2) ? [PB] : []) : null
  const unique = artistList ? [...new Map(artistList.map((artist) => [artist.id, artist])).values()] : null
  const pool = [...SONG_GROUPS[songsOf], ...GROUPS]
  const matches = chance(0.15) ? null : chance(0.3) ? [] : some(pick(Object.values(MATCHES)), 0.85)
  const songs = chance(0.15) ? null : { name: chance(0.8) ? songsOf : pick(NAMES), take: Math.floor(rand() * 13) }
  const groups = chance(0.3) ? null : shuffled(some(pool, 0.3)).map((group) => group.id)
  const saved = chance(0.1) ? null : {
    matches: chance(0.5) && matches ? some(matches, 0.6) : some(ALL_MATCHES, 0.2),
    groups: shuffled([...some(pool, 0.25), ...(groups && chance(0.5) ? some(groupsOf(groups), 0.5) : [])].map((group) => group.id)),
    ...(chance(0.5) ? { credited: shuffled(some(GROUPS, 0.4)).map((group) => group.id) } : {}),
    songs: chance(0.25) ? null : { name: chance(0.8) ? songsOf : pick(NAMES), take: Math.floor(rand() * 13) },
  }
  const personal = chance(0.5)
  const yourAlbums = personal && chance(0.7) ? some(albums, 0.5).map((album) => album.id) : null
  const yourArtists = personal && chance(0.6) ? some(artists, 0.5).map((artist) => [artist.id, Math.floor(rand() * 3)]) : null
  const first = SONGS[songsOf][0]
  const roll = rand()
  const text = roll < 0.35 && first ? `${first.title} ${first.credit}`
    : roll < 0.5 && first ? first.title
    : roll < 0.7 ? pick(ARTISTS).name
    : Array.from({ length: 1 + Math.floor(rand() * 2) }, () => pick(WORDS)).join(' ')
  const failed = chance(0.08)
  return {
    text, library: failed ? null : lib(artists, albums, library), failed, artistList: unique, list: Math.floor(rand() * LISTS.length),
    matches, groups, songs, saved, personal, yourAlbums, yourArtists,
  }
}

function cases() {
  const out = FIXED.map(webCase)
  for (let number = 0; number < 70; number++) out.push(webCase(seededCase()))
  return out
}

/* ===== out ===== */

function vectors() {
  return {
    numbers: numbers(),
    words: words(),
    groups: ALL_GROUPS,
    lists: LISTS,
    recordings: RECORDINGS,
    studio: studio(),
    saved: saved(),
    areas: areas(),
    pages: pages(),
    append: append(),
    songPages: songPages(),
    kept: kept(),
    cases: cases(),
  }
}

/** JSON with every character outside printable ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[^\n -~]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-search-saved-vectors.cjs, then port the change to DeadwaxCore and see SearchSavedVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
