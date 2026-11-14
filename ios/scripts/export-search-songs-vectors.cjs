#!/usr/bin/env node
/**
 * Search's MusicBrainz artists and songs, and a MusicBrainz artist's page, for the iPhone app (Phase 5, slice 3 -
 * notes/ios-specs/phase5-search.md 6.3): what the web app's own TypeScript answers, written as a third fixture beside
 * search-vectors.json and search-albums-vectors.json for the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore
 * (SongSearch.swift, MBArtist.swift, SearchList.swift's artists and songs, Pressings.swift's song marks) to replay
 * (Tests/DeadwaxCoreTests/SearchSongsVectorTests.swift) - so the phone groups a song search's takes into songs, says
 * what is held of each album a song is on, brings a library artist or song in rather than drawing it twice, marks the
 * song on the album it opens, and lists a MusicBrainz artist's albums exactly as the web does.
 *
 * Compiles lib/searchList.ts, lib/songs.ts, lib/artistPage.ts, lib/pressings.ts and lib/idBridge.ts with what they
 * import, and reads the few words that live in components (Search.tsx's noReleaseWords, ReleaseGroupPage.tsx's
 * SONG_WORDS, ArtistPage.tsx's discography words) from their source. Writes
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-songs-vectors.json:
 *
 *   numbers    the song search's limit, the artist search's, the songs a section shows, the ids an address keeps, the
 *              artist pages the session keeps (ArtistPage.tsx's ARTISTS_KEPT)
 *   words      SONGS_NEED_A_TITLE, noReleaseWords, SONG_WORDS, foldLabel, the artist page's discography words
 *   queries    songSearchQuery, songTitleQuery and fieldedSongQuery over readings
 *   titles     titleKey and songBand
 *   songs      every recording search in tests/fixtures/songs/ (embedded): each recording's songKey, groupSongs' songs
 *              in full, each song's bands and its fold's words
 *   holding    over folder lists and evidence (the library half's songs, an album's kept pressings): every album's
 *              holding, the releases the id bridge is asked about, its words and its line; each song's named album
 *              and its row's line
 *   pressings  The Slow Rush's pressings with recording ids (tests/fixtures/songs/slow-rush-pressings.json): songIds,
 *              songMatcher's tracks, songPressing, and trackRows with the song marked
 *   cases      whole searches with MusicBrainz's artists, albums and songs in hand: the pool, the candidates, Top results
 *              decided and completed, the sections, every row's line, every MusicBrainz row's relatives, and each
 *              MusicBrainz song's disclosure (its bands, the fold, each album's line and what its tap asks)
 *   artist     a MusicBrainz artist's page: artistRows([], groups, index) over folder lists, each row's line, and
 *              factsLine
 *   collation  localeCompare (ICU's collation) over every title the recorded answers carry and made ones: their order,
 *              and the sign of seeded pairs
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-search-songs-vectors.cjs           write the fixture
 *   node ios/scripts/export-search-songs-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'search', 'search-songs-vectors.json')
const SONG_FIXTURES = path.join(REPO, 'tests', 'fixtures', 'songs')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-songs-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchList.ts', 'src/lib/songs.ts', 'src/lib/artistPage.ts', 'src/lib/pressings.ts', 'src/lib/idBridge.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/searchList.js'))
const Q = require(path.join(OUT, 'lib/searchQuery.js'))
const R = require(path.join(OUT, 'lib/searchResults.js'))
const S = require(path.join(OUT, 'lib/songs.js'))
const O = require(path.join(OUT, 'lib/owned.js'))
const P = require(path.join(OUT, 'lib/pressings.js'))
const T = require(path.join(OUT, 'lib/tracklistDiff.js'))
const A = require(path.join(OUT, 'lib/artistPage.js'))

/** A component's source, which the exporter can't compile without Preact - every group of the first match. */
function sourceMatches(file, pattern) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(pattern)
  if (!found) throw new Error(`${file} no longer has ${pattern}`)
  return found.slice(1)
}
const sourceMatch = (file, pattern) => sourceMatches(file, pattern)[0]

/* ===== seeded randomness ===== */

let seed = 5353
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const chance = (p) => rand() < p

/* ===== the recording searches ===== */

const NAMES = ['roads-portishead', 'roads-portishead-free', 'patience-tame-impala', 'hey-jude-beatles', 'hey-jude-free',
  'miss-misery-elliott-smith', 'bohemian-rhapsody-queen']
const FIX = Object.fromEntries(NAMES.map((name) => [name, JSON.parse(fs.readFileSync(path.join(SONG_FIXTURES, `${name}.json`), 'utf8'))]))
const SONGS = Object.fromEntries(NAMES.map((name) => [name, S.groupSongs(FIX[name].recordings)]))
const SLOW_RUSH = JSON.parse(fs.readFileSync(path.join(SONG_FIXTURES, 'slow-rush-pressings.json'), 'utf8'))

/* ===== the numbers and the words ===== */

function numbers() {
  return {
    songSearchLimit: S.SONG_SEARCH_LIMIT,
    artistSearchLimit: L.ARTIST_SEARCH_LIMIT,
    songRowsShown: S.SONG_ROWS_SHOWN,
    songIdsKept: S.SONG_IDS_KEPT,
    artistsKept: Number(sourceMatch('src/app/ArtistPage.tsx', /export const ARTISTS_KEPT = (\d+)/)),
  }
}

const TEXTS = ['roads', 'glory box', '“quoted”', 'Björk', 'hey jude']

/** A made album under a song, for the fold's words: its types alone matter. */
const folded = (primaryType, secondaryTypes) => ({
  id: `f-${primaryType}-${secondaryTypes.join('-')}`, title: 'x', primaryType, secondaryTypes, kind: '', band: 'other', status: '', date: '',
  credit: '', releases: [], recordings: [], length: null,
})

function words() {
  const noRelease = sourceMatch('src/app/Search.tsx', /const noReleaseWords = \(term: string\) => `([^`]*)`/)
  const [studio, plain] = sourceMatches('src/app/ArtistPage.tsx', /\{studioOnly \? '(No studio albums[^']*)' : '([^']*)'\}/)
  const kinds = [
    folded('Album', ['Compilation']), folded('Album', ['Live']), folded(null, ['Live']), folded('EP', ['Live']), folded('Album', ['Soundtrack']),
    folded('Broadcast', []), folded('Broadcast', ['Live']), folded('Other', []), folded('Album', ['Remix']), folded('Single', ['Live']),
    folded('Album', ['Compilation', 'Live']), folded('album', ['live']), folded('', ['DJ-mix']),
  ]
  const lists = [[]]
  for (const each of kinds) lists.push([each], [each, each])
  for (let n = 0; n < 24; n++) lists.push(kinds.filter(() => chance(0.3)))
  return {
    needATitle: L.SONGS_NEED_A_TITLE,
    songWords: sourceMatch('src/app/ReleaseGroupPage.tsx', /export const SONG_WORDS = '([^']*)'/),
    noRelease: TEXTS.map((text) => ({ text, said: noRelease.replace('${term}', text) })),
    fold: lists.map((list) => ({ albums: list.map((album) => [album.primaryType, album.secondaryTypes]), said: S.foldLabel(list) })),
    studioOnly: sourceMatch('src/app/ArtistPage.tsx', /\n\s*(Studio only)\n/),
    loading: sourceMatch('src/app/ArtistPage.tsx', /'(Loading their albums…)'/),
    away: sourceMatch('src/app/ArtistPage.tsx', /\n\s*(Their other albums can't be shown right now - try again in a few minutes\.)\n/),
    truncated: sourceMatch('src/app/ArtistPage.tsx', /"app-search-empty">(Showing their first \d+ albums\.)</),
    noneStudio: studio,
    none: plain,
  }
}

/* ===== the queries ===== */

function queries() {
  const names = [[], ['Portishead'], ['Portishead', 'Tame Impala', 'The Beatles'], ['Queen', 'Björk']]
  const texts = ['', '   ', 'roads', 'roads portishead', 'portishead roads', 'portishead', 'portishead - roads', 'patience tame impala',
    'tame impala', 'the slow rush tame impala', 'hey jude the beatles', 'bohemian rhapsody queen', 'queen', '  roads   portishead  ',
    'roads "portishead"', 'björk joga', 'joga bjork', 'a\\b portishead', 'portishead "roads"']
  const readings = []
  for (const list of names) {
    for (const text of texts) {
      const plan = Q.searchQuery(text.trim(), Q.artistNames(list))
      readings.push({ names: list, text, plan, song: Q.songSearchQuery(text, plan), title: Q.songTitleQuery(text) })
    }
  }
  const fielded = [['Roads', 'Portishead'], ['Say "Hi"', 'A\\B'], ['', ''], ['Hey Jude', 'The Beatles'], ['Été', 'Björk']]
    .map(([title, artist]) => ({ title, artist, said: Q.fieldedSongQuery(title, artist) }))
  return { readings, fielded }
}

/* ===== titles ===== */

function titles() {
  const made = ['Roads (live)', 'Roads (Live at Roseland)', 'Roads - 2014 Remaster', 'Hey Jude (Remastered 2015)', 'Hey Jude [Remastered]',
    '', '  ', 'Roads (Max Cooper remix)', 'Sour Times (Airbus Reconstruction)', 'Song (mono)', 'Song [stereo]', 'Rock & Roll',
    'Don’t Stop', 'Café del Mar', '(Untitled)', 'Ｆｕｌｌ　Ｗｉｄｔｈ', 'Roads (LIVE)', 'Roads ( live )', 'A (live) (live)', 'x [live, 1998]',
    'Remastered', '(remastered)', 'Hey Jude (Live / Remastered)', 'Bohemian Rhapsody - Remastered 2011', 'Glory Box', 'Teardrop`s']
  const all = [...new Set([...made, ...NAMES.flatMap((name) => FIX[name].recordings.map((recording) => recording.title ?? ''))])]
  const types = [null, '', 'Album', 'album', 'EP', 'ep', 'Single', 'single', 'Broadcast', 'Other']
  const seconds = [null, [], ['Live'], ['Compilation'], ['Remix', 'Live']]
  return {
    titles: all.map((title) => ({ title, key: S.titleKey(title) })),
    bands: types.flatMap((primary) => seconds.map((secondary) => ({ primary, secondary, band: S.songBand(primary, secondary) }))),
  }
}

/* ===== localeCompare ===== */

/** How the web orders titles that tie on everything before them (sortAlbums, artistRows): localeCompare - ICU's
 *  collation, which the phone approximates (WebCollation.swift). Every title the recorded answers carry and some made
 *  ones, sorted; and the sign of seeded pairs. Last among the vectors, so its random draws move no others. */
function collation() {
  const recorded = NAMES.flatMap((name) => FIX[name].recordings.flatMap((recording) => [recording.title,
    ...(recording.releases ?? []).flatMap((release) => [release.title, release['release-group']?.title])]))
  const made = ['', ' ', 'a', ' a', 'a ', 'A', 'á', 'Á', 'à', 'â', 'ä', 'å', 'ã', 'ā', 'æ', 'Æ', 'ae', 'AE', 'Ae', 'áe', 'af', 'b', 'œ', 'Œ', 'oe', 'OE', 'ø', 'Ø',
    'o', 'ö', 'ő', 'ß', 'ss', 'SS', 'st', 'đ', 'ð', 'd', 'ł', 'l', 'ı', 'i', 'j', 'ŋ', 'n', 'þ', 'z', 'a-b', 'a‐b', 'a–b', 'a—b',
    'a b', 'a_b', 'a.b', 'a,b', 'a;b', 'a:b', 'a!b', 'a?b', "a'b", 'a’b', 'a"b', 'a“b', 'a(b', 'a[b', 'a{b', 'a@b', 'a*b', 'a/b',
    'a\\b', 'a&b', 'a#b', 'a%b', 'a`b', 'a^b', 'a+b', 'a<b', 'a=b', 'a>b', 'a|b', 'a~b', 'a$b', 'a1b', 'a…', 'a...', 'ａ', 'Ａ',
    'ﬁ', 'fi', '²', '2', '10', '9', '١', 'α', 'а', 'א', '一', 'あ', 'ア', '가', '½', 'Ⅰ', 'I', 'ª', 'º', '™', 'tm', 'µ', 'ʼ',
    '1984-09-24: Deutchlandhalle', '1984‐09‐15: The Jewels', 'Live (1977)', 'Live 1977', 'Live: 1977', 'Live - 1977', 'Live, 1977']
  const all = [...new Set([...recorded, ...made].filter((title) => typeof title === 'string'))]
  const pairs = []
  for (let n = 0; n < 600; n++) {
    const a = pick(all), b = pick(all)
    pairs.push([a, b, Math.sign(a.localeCompare(b))])
  }
  return { all, sorted: [...all].sort((a, b) => a.localeCompare(b)), pairs }
}

/* ===== the songs ===== */

function songs() {
  return NAMES.map((name) => {
    const fixture = FIX[name]
    const found = SONGS[name]
    return {
      name,
      query: fixture.query,
      recordings: fixture.recordings,
      keys: fixture.recordings.map((recording) => S.songKey(recording)),
      songs: found,
      bands: found.map((song) => {
        const bands = S.songAlbumBands(song)
        return { listed: bands.listed.map((album) => album.id), folded: bands.folded.map((album) => album.id), label: S.foldLabel(bands.folded) }
      }),
    }
  })
}

/* ===== what is held of a song's albums ===== */

const folder = (path, artist, album, extra = {}) => ({ path, artist, album, ...extra })
const madeId = (n) => `0000000${n % 10}-aaaa-4bbb-8ccc-${String(n).padStart(12, '0')}`

/** The folder lists a recording search is read against: none answered, nothing held, one of the first song's albums
 *  by a release it was found on, another pressing of it and one with no release id, a mix with an untagged copy -
 *  and, last, its first album held by the collection alone and a later one by you (namedAlbum names yours). */
function folderLists(name) {
  const [first, second] = SONGS[name]
  if (!first) return [null, []]
  const albums = first.albums
  const [a0, a1 = albums[0], a2 = albums[0]] = albums
  const by = first.credit
  const lists = [
    null,
    [],
    [folder(`${by}/${a0.title}`, by, a0.title, { release_mbid: a0.releases[0], release_group_mbid: a0.id, yours: true })],
    [
      folder(`${by}/${a0.title} (other)`, by, a0.title, { release_mbid: madeId(1), release_group_mbid: a0.id, yours: false }),
      folder(`${by}/${a1.title}`, by, a1.title, { release_group_mbid: a1.id, yours: true }),
      ...(second ? [folder(`${second.credit}/${second.albums[0].title}`, second.credit, second.albums[0].title, { release_mbid: second.albums[0].releases[0], yours: false })] : []),
    ],
    [
      folder(`${by}/${a0.title}`, by, a0.title, { release_mbid: ` ${(a0.releases[0] ?? '').toUpperCase()} `, yours: false }),
      folder(`${by}/${a1.title} (other)`, by, a1.title, { release_mbid: madeId(2), release_group_mbid: a1.id, yours: true }),
      folder(`${by}/${a2.title} (other)`, by, a2.title, { release_mbid: madeId(3), release_group_mbid: a2.id, yours: false }),
      folder(`Unknown/${a0.title}`, by, a0.title),
    ],
  ]
  //? The Slow Rush held as each of its pressings - Patience is on the Japanese CD's alone
  if (name === 'patience-tame-impala') {
    lists.push(SLOW_RUSH.releases.slice(0, 4).map((release, at) =>
      folder(`Tame Impala/The Slow Rush (${release.country})`, 'Tame Impala', 'The Slow Rush', { release_mbid: release.id, release_group_mbid: SLOW_RUSH.group, yours: at % 2 === 0 })))
  }
  //? after the cases' own lists, so none of them reads another: the song held on its first album by the collection
  //? alone, and on a later one by you - the row names yours
  if (albums.length > 1) {
    lists.push([
      folder(`${by}/${a0.title} (theirs)`, by, a0.title, { release_mbid: a0.releases[0], release_group_mbid: a0.id, yours: false }),
      folder(`${by}/${a1.title} (mine)`, by, a1.title, { release_mbid: a1.releases[0], release_group_mbid: a1.id, yours: true }),
    ])
  }
  return lists
}

/** A made pressing: one disc with these tracks. */
const pressing = (id, tracks) => ({ id, title: 'Made', media: [{ position: 1, format: 'CD', tracks }] })
const pressedTrack = (number, title, recording, length = 296000) => ({ number: String(number), position: number, title, length, recording: { id: recording, title, length } })

/** What else says a pressing held has the song: nothing; the library half's songs; an album's kept pressings; both. */
function evidenceFor(name) {
  const [first] = SONGS[name]
  if (!first) return [{ heard: null, pressings: {} }]
  const albums = first.albums
  const [, a1 = albums[0], a2 = albums[0]] = albums
  const heard = [
    { id: 's-h1', title: `${first.title} (Live)`, artist: first.credit, album: a1.title, albumId: 'nd-h1' },
    { id: 's-h2', title: first.title, artist: first.credit, album: a2.title, albumId: 'nd-h2' },
    { id: 's-h3', title: first.title, artist: first.credit, album: a2.title },
    { id: 's-h4', title: 'Something Else', artist: first.credit, album: a1.title, albumId: 'nd-h4' },
  ]
  const pressings = {
    [a1.id]: [pressing(madeId(2), [pressedTrack(1, first.title, first.recordings[0])])],
    [a2.id]: [pressing(madeId(3), [pressedTrack(1, 'Unrelated', madeId(7))]), pressing(madeId(9), [pressedTrack(1, first.title, first.recordings[0])])],
  }
  if (name === 'patience-tame-impala') pressings[SLOW_RUSH.group] = SLOW_RUSH.releases
  return [{ heard: null, pressings: {} }, { heard, pressings: {} }, { heard: null, pressings }, { heard, pressings }]
}

const evidenceOf = (given) => ({ heard: given.heard, pressings: (id) => given.pressings[id] ?? null })
const paths = (list) => list.map((each) => each.path)

function holding() {
  return NAMES.map((name) => {
    const lists = folderLists(name)
    const evidence = evidenceFor(name)
    return {
      name,
      lists,
      evidence,
      read: lists.flatMap((folders, list) => evidence.map((given, ev) => {
        const index = folders ? O.buildOwnedIndex(folders) : null
        const said = evidenceOf(given)
        return {
          list, evidence: ev,
          songs: SONGS[name].slice(0, 3).map((song) => {
            const named = S.namedAlbum(song, index, said)
            return {
              key: song.key,
              named: named.album.id,
              held: paths(named.held),
              line: [false, true].map((personal) => [L.rowLine(L.mbSongRow(song), { marks: { personal, index }, evidence: said }, false),
                L.rowLine(L.mbSongRow(song), { marks: { personal, index }, evidence: said }, true)].map((made) => [made.line, made.place])),
              albums: song.albums.slice(0, 8).map((album) => {
                const held = S.songAlbumHolding(index, album, song, said)
                return {
                  id: album.id,
                  song: paths(held.song), heard: paths(held.heard), other: paths(held.other), albums: held.albums,
                  bare: paths(S.songAlbumHeld(index, album, null, said)),
                  releases: S.songAlbumHeldReleases(index, album, song, said),
                  words: [S.songAlbumWords(held, false), S.songAlbumWords(held, true)],
                  line: [S.songAlbumLine(album, song, index, false, said), S.songAlbumLine(album, song, index, true, said)],
                }
              }),
            }
          }),
        }
      })),
    }
  })
}

/* ===== the album opened from a song ===== */

function pressings() {
  const releases = SLOW_RUSH.releases
  const patience = SONGS['patience-tame-impala'].find((song) => S.titleKey(song.title) === 'patience')
  const tracks = releases.flatMap((release) => (release.media ?? []).flatMap((medium) => medium.tracks ?? []))
  const one = tracks.find((track) => track.title === 'One More Year')
  const asks = [
    { what: 'patience', ids: patience ? patience.recordings : [] },
    { what: 'one more year', ids: [one.recording.id] },
    { what: 'one more year, uppercase and spaced', ids: [` ${one.recording.id.toUpperCase()} `] },
    { what: 'nothing', ids: [] },
    { what: 'not on it', ids: [madeId(4)] },
    { what: 'not an id', ids: ['patience'] },
    { what: 'patience and a stranger', ids: [madeId(5), ...(patience ? patience.recordings : [])] },
  ]
  const usual = P.pressingsView(releases)
  return {
    group: SLOW_RUSH.group,
    releases,
    ids: [
      '', ',', 'abc', madeId(1), `${madeId(1)},${madeId(1).toUpperCase()}`, ` ${madeId(2)} , ${madeId(3)},junk`,
      Array.from({ length: 11 }, (_, n) => madeId(n + 10)).join(','),
    ].map((text) => ({ text, ids: S.songIds(text) })),
    idLists: [[], [madeId(1), madeId(1)], [madeId(1), 'nope', ` ${madeId(2).toUpperCase()} `], Array.from({ length: 9 }, (_, n) => madeId(n))]
      .map((list) => ({ list, ids: S.songIds(list) })),
    asks: asks.map(({ what, ids }) => {
      const matches = S.songMatcher(releases, ids)
      const picked = S.songPressing(releases, ids)
      const chosen = P.pressingsView(releases, picked)
      const release = releases.find((each) => each.id === chosen.chosenId) ?? null
      return {
        what, ids,
        matches: matches ? releases.map((each) => (each.media ?? []).flatMap((medium, disc) => (medium.tracks ?? []).map((track, at) => (matches(track) ? `${disc}:${at}` : null))).filter(Boolean)) : null,
        pressing: picked,
        chosen: chosen.chosenId,
        tracks: P.trackRows(release, usual.diffs.get(chosen.chosenId) ?? null, matches).map((row) => [row.key, row.title, row.song]),
      }
    }),
  }
}

/* ===== whole searches ===== */

const MBID = {
  portishead: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11',
  portisheadTribute: '1d2c3b4a-0000-4000-8000-00000000aa01',
  tame: '63aa26c3-d59b-4da4-84ac-716b54f1ef4d',
  beatles: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
  queen: '0383dadf-2a4e-4d10-a46a-e9e041da8eb3',
  queenLambert: '1d2c3b4a-0000-4000-8000-00000000aa02',
  elliott: '03ad1736-b7c9-412a-b442-82536d63a5c4',
  ye: '164f0d73-1234-4e2c-8743-d77bf2191051',
  nirvanaUS: '5b11f4ce-a62d-471e-81fc-a69a8278c7da',
  nirvanaUK: 'f8c5a1cb-0a35-4bfd-9e5e-0d1e1c8c2e2d',
}
const match = (mbid, name, extra = {}) => ({ mbid, name, disambiguation: '', country: '', type: '', matched_as: '', ...extra })
const MATCHES = {
  portishead: [match(MBID.portishead, 'Portishead', { type: 'Group', country: 'GB' }), match(MBID.portisheadTribute, 'Portishead', { disambiguation: 'tribute band', type: 'Group' })],
  portisheadAlone: [match(MBID.portishead, 'Portishead', { type: 'Group', country: 'GB', score: 100 })],
  tame: [match(MBID.tame, 'Tame Impala', { type: 'Group', country: 'AU' })],
  beatles: [match(MBID.beatles, 'The Beatles', { type: 'Group', country: 'GB' }), match(MBID.queenLambert, 'Beatles Revival', { matched_as: 'The Beatles' })],
  queen: [match(MBID.queen, 'Queen', { type: 'Group', country: 'GB' }), match(MBID.queenLambert, 'Queen + Adam Lambert', { type: 'Group', matched_as: 'Queen' })],
  ye: [match(MBID.ye, 'Ye', { matched_as: 'Kanye West', type: 'Person', country: 'US' })],
  nirvana: [match(MBID.nirvanaUS, 'Nirvana', { disambiguation: '90s US grunge band', type: 'Group', country: 'US' }), match(MBID.nirvanaUK, 'Nirvana', { disambiguation: '60s band from the UK', type: 'Group', country: 'GB' })],
  elliott: [match(MBID.elliott, 'Elliott Smith', { type: 'Person', country: 'US' })],
}

const PA = { id: 'ar-p', name: 'Portishead', albumCount: 3, musicBrainzId: MBID.portishead }
const PB = { id: 'ar-p', name: 'Portishead', albumCount: 3 }
const TI = { id: 'ar-t', name: 'Tame Impala', albumCount: 4 }
const QU = { id: 'ar-q', name: 'Queen', albumCount: 12, musicBrainzId: ` ${MBID.queen.toUpperCase()} ` }
const BE = { id: 'ar-b', name: 'The Beatles', albumCount: 13 }
const KW = { id: 'ar-k', name: 'Kanye West', albumCount: 9 }
const NV = { id: 'ar-n', name: 'Nirvana', albumCount: 3 }
const ES = { id: 'ar-e', name: 'Elliott Smith', albumCount: 6, musicBrainzId: MBID.elliott }
const ARTISTS = [PA, TI, QU, BE, KW, NV, ES]

const dummy = { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', artistId: 'ar-p', year: 1994, coverArt: 'al-dummy' }
const rush = { id: 'nd-rush', name: 'The Slow Rush', artist: 'Tame Impala', artistId: 'ar-t', year: 2020 }
const opera = { id: 'nd-opera', name: 'A Night at the Opera', artist: 'Queen', artistId: 'ar-q', year: 1975 }
const libSong = (id, title, album) => ({ id, title, artist: album.artist, artistId: album.artistId, album: album.name, albumId: album.id, coverArt: album.coverArt })
const roads = libSong('s-roads', 'Roads', dummy)
const roadsLive = libSong('s-roads-live', 'Roads (Live)', dummy)
const patienceSong = libSong('s-patience', 'Patience', rush)
const rhapsody = libSong('s-bohemian', 'Bohemian Rhapsody', opera)
const lib = (artists = [], albums = [], songs = []) => ({ artists, albums, songs })

const groupOf = (id, title, date, primary, secondary, credit) => ({ id, title, 'first-release-date': date, 'primary-type': primary, 'secondary-types': secondary, 'artist-credit': credit })
const credited = (mbid, name) => [{ name, joinphrase: '', artist: { id: mbid, name } }]

/** The albums answer for a song search's words, made of the song's own albums (a group the albums half would find
 *  too), so a song's named album can be the answer's own group. */
function groupsFrom(name, take) {
  const [first] = SONGS[name]
  if (!first) return []
  return first.albums.slice(0, take).map((album) => groupOf(album.id, album.title, album.date, album.primaryType ?? undefined, album.secondaryTypes, credited(first.artists[0]?.id ?? MBID.portishead, first.credit)))
}

/** What the web's Search hands the rules for one search with MusicBrainz's artists, albums and songs in hand
 *  (Search.tsx's marksNow, evidence, rows, familyFor, decided) and each MusicBrainz song's disclosure (SearchRows.tsx). */
function webCase({ text, library, failed = false, artistList = null, songsOf = null, list = 0, ev = 0, matches = null, groups = null, songs = null, personal = false, yourAlbums = null, yourArtists = null }) {
  const lists = songsOf ? folderLists(songsOf) : [null]
  const folders = lists[Math.min(list, lists.length - 1)]
  const given = songsOf ? evidenceFor(songsOf)[ev] : { heard: null, pressings: {} }
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
  //? the library half's songs and the album pressings kept, as Search.tsx's `evidence`
  const evidence = { heard: results?.songs ?? null, pressings: (id) => given.pressings[id] ?? null }
  const term = text.trim()
  const plan = Q.searchQuery(term, Q.artistNames([...ownedArtists, ...(results?.artists ?? []).map((artist) => artist.name)]))
  const out = {
    text, library, failed, artistList, songsOf, list, ev, matches, groups, songs, personal, yourAlbums, yourArtists, plan,
    song: plan ? Q.songSearchQuery(term, plan) : null,
  }
  if (!plan) return out
  const found = songs ? S.groupSongs(FIX[songs.name].recordings.slice(0, songs.take)) : null
  const albums = groups ? { groups, shown: R.notInLibrary(groups, index) } : null
  const input = { reading: plan, library: results, artistList, index, marks, evidence }
  const bare = L.pool({ ...input, artists: null, albums: null, songs: null })
  const rows = L.pool({ ...input, artists: matches, albums, songs: found })
  const family = { library: results, artistList, index, evidence, groups: groups ?? [] }
  const bareCandidates = L.candidatesOf(bare, term, plan)
  const candidates = L.candidatesOf(rows, term, plan)
  const decided = [['albums'], ['artists', 'albums', 'songs'], []].map((kinds) => {
    const made = L.decidedTop(bareCandidates, kinds.map((kind) => L.phantom(kind, plan)).filter(Boolean), L.TOP_RESULTS.phone, family)
    return { kinds, prefix: made.prefix.map((row) => row.key), place: made.place }
  })
  const prefix = L.decidedTop(bareCandidates, L.KINDS.map((kind) => L.phantom(kind, plan)).filter(Boolean), L.TOP_RESULTS.phone, family).prefix
  const line = (row, isTop) => {
    const { line, place } = L.rowLine(row, { marks, evidence }, isTop)
    return [row.key, line, place]
  }
  const placed = (list) => list.map((each) => [each.row.key, each.holder, each.position])
  const every = L.KINDS.flatMap((kind) => [...rows[kind].library, ...rows[kind].brought, ...rows[kind].musicbrainz])
  out.pool = Object.fromEntries(L.KINDS.map((kind) => [kind, { library: placed(rows[kind].library), brought: placed(rows[kind].brought), musicbrainz: placed(rows[kind].musicbrainz) }]))
  out.candidates = candidates.map((each) => [each.key, each.tier, each.source, each.position])
  out.decided = decided
  out.top = L.topResults(candidates, L.TOP_RESULTS.phone, family).map((each) => line(each.row, true))
  out.topFixed = L.topResults(candidates, L.TOP_RESULTS.phone, family, prefix).map((each) => each.row.key)
  out.sections = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind], L.PREVIEW.phone[kind]).map((row) => row.key)]))
  out.full = Object.fromEntries(L.KINDS.map((kind) => [kind, L.sectionRows(rows[kind]).map((row) => row.key)]))
  out.lines = every.map((each) => [...line(each.row, false), ...line(each.row, true).slice(1)])
  out.families = every.filter((each) => each.row.type === 'mb-song' || each.row.type === 'group')
    .map((each) => ({ key: each.row.key, family: L.familyOf(each.row, family).map((row) => line(row, true)) }))
  //? a MusicBrainz song's disclosure: its listed albums, then the fold - each album's line, and what its tap asks
  out.disclosures = every.filter((each) => each.row.type === 'mb-song').map(({ row }) => {
    const bands = S.songAlbumBands(row.song)
    return {
      key: row.key,
      listed: bands.listed.map((album) => album.id),
      folded: bands.folded.map((album) => album.id),
      fold: bands.folded.length ? S.foldLabel(bands.folded) : null,
      named: S.namedAlbum(row.song, index, evidence).album.id,
      albums: row.song.albums.map((album) => {
        const holding = S.songAlbumHolding(index, album, row.song, evidence)
        return [album.id, S.songAlbumLine(album, row.song, index, personal, evidence), S.songAlbumHeldReleases(index, album, row.song, evidence), holding.albums, holding.other.length > 0]
      }),
    }
  })
  return out
}

const FIXED = [
  //? a song nobody here has: its take on Dummy named, the artist answering by id brought in, the tribute band kept
  { text: 'roads portishead', library: lib([PA], [], []), artistList: [PA], songsOf: 'roads-portishead', list: 1, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 }, groups: groupsFrom('roads-portishead', 3) },
  { text: 'roads portishead', library: lib([PA], [dummy], [roads]), artistList: [PA], songsOf: 'roads-portishead', list: 2, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 } },
  { text: 'roads portishead', library: lib([PA], [dummy], [roadsLive]), artistList: [PA], songsOf: 'roads-portishead', list: 3, ev: 1, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 } },
  { text: 'roads portishead', library: lib([], [], []), artistList: [PB], songsOf: 'roads-portishead', list: 4, ev: 3, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 }, personal: true, yourAlbums: [], yourArtists: [] },
  //? the free-text search: strangers' songs titled after the band
  { text: 'roads portishead', library: lib(), artistList: [], songsOf: 'roads-portishead-free', list: 2, matches: MATCHES.portisheadAlone, songs: { name: 'roads-portishead-free', take: 12 } },
  //? Patience: a bonus track on the Japanese CD - held as the usual CD, it is "a pressing in your library"
  { text: 'patience tame impala', library: lib([TI], [rush], []), artistList: [TI], songsOf: 'patience-tame-impala', list: 5, matches: MATCHES.tame, songs: { name: 'patience-tame-impala', take: 4 } },
  { text: 'patience tame impala', library: lib([TI], [rush], [patienceSong]), artistList: [TI], songsOf: 'patience-tame-impala', list: 5, ev: 3, matches: MATCHES.tame, songs: { name: 'patience-tame-impala', take: 4 }, personal: true, yourAlbums: ['nd-rush'], yourArtists: [['ar-t', 1]] },
  { text: 'patience', library: lib(), artistList: null, songsOf: 'patience-tame-impala', list: 0, songs: { name: 'patience-tame-impala', take: 4 } },
  //? Hey Jude: compilations and bootlegs, every album folded
  { text: 'hey jude the beatles', library: lib([BE], [], []), artistList: [BE], songsOf: 'hey-jude-beatles', list: 2, matches: MATCHES.beatles, songs: { name: 'hey-jude-beatles', take: 12 } },
  { text: 'hey jude', library: lib(), artistList: [BE], songsOf: 'hey-jude-free', list: 1, matches: [], songs: { name: 'hey-jude-free', take: 12 } },
  //? Miss Misery: on no album or EP, one take on no release
  { text: 'miss misery elliott smith', library: lib([ES], [], []), artistList: [ES], songsOf: 'miss-misery-elliott-smith', list: 3, matches: MATCHES.elliott, songs: { name: 'miss-misery-elliott-smith', take: 12 } },
  { text: 'miss misery', library: lib(), artistList: [ES], songsOf: 'miss-misery-elliott-smith', list: 1, songs: { name: 'miss-misery-elliott-smith', take: 1 } },
  //? Bohemian Rhapsody: one take on 133 albums
  { text: 'bohemian rhapsody queen', library: lib([QU], [opera], [rhapsody]), artistList: [QU], songsOf: 'bohemian-rhapsody-queen', list: 2, matches: MATCHES.queen, songs: { name: 'bohemian-rhapsody-queen', take: 12 } },
  { text: 'bohemian rhapsody queen', library: lib([QU], [], []), artistList: [QU], songsOf: 'bohemian-rhapsody-queen', list: 4, ev: 2, matches: MATCHES.queen, songs: { name: 'bohemian-rhapsody-queen', take: 12 } },
  //? artists alone: Ye for Kanye West, two Nirvanas, a name a folder is filed under
  { text: 'kanye west', library: lib([KW], [], []), artistList: [KW], matches: MATCHES.ye },
  { text: 'kanye west', library: lib(), artistList: [KW], matches: MATCHES.ye },
  { text: 'nirvana', library: lib([NV], [], []), artistList: [NV], matches: MATCHES.nirvana },
  { text: 'nirvana', library: lib(), artistList: [NV], matches: MATCHES.nirvana },
  { text: 'queen', library: lib(), artistList: [QU, BE], matches: MATCHES.queen, songs: { name: 'bohemian-rhapsody-queen', take: 0 } },
  { text: 'portishead', library: lib([], [dummy], []), artistList: [PB], songsOf: 'roads-portishead', list: 2, matches: MATCHES.portisheadAlone },
  { text: 'portishead', library: lib(), artistList: null, songsOf: 'roads-portishead', list: 2, matches: MATCHES.portishead },
  //? the library failed, MusicBrainz answered
  { text: 'roads portishead', library: null, failed: true, artistList: [PA], songsOf: 'roads-portishead', list: 3, matches: MATCHES.portishead, songs: { name: 'roads-portishead', take: 12 } },
  { text: 'patience', library: null, failed: true, artistList: null, songsOf: 'patience-tame-impala', list: 5, ev: 2, songs: { name: 'patience-tame-impala', take: 4 } },
]

const WORDS = ['roads', 'portishead', 'patience', 'tame', 'impala', 'hey', 'jude', 'beatles', 'queen', 'bohemian', 'rhapsody', 'miss',
  'misery', 'elliott', 'smith', 'dummy', 'the', 'nirvana', 'kanye', 'west']

function seededCase() {
  const songsOf = pick(NAMES)
  const lists = folderLists(songsOf)
  const artists = ARTISTS.filter(() => chance(0.3))
  const albums = [dummy, rush, opera].filter(() => chance(0.35))
  const library = [roads, roadsLive, patienceSong, rhapsody].filter((each) => albums.some((album) => album.id === each.albumId) && chance(0.5))
  const artistList = chance(0.75) ? ARTISTS.filter(() => chance(0.5)).concat(chance(0.2) ? [PB] : []) : null
  const unique = artistList ? [...new Map(artistList.map((artist) => [artist.id, artist])).values()] : null
  const matches = chance(0.15) ? null : chance(0.3) ? [] : pick(Object.values(MATCHES)).filter(() => chance(0.85))
  const songs = chance(0.12) ? null : { name: chance(0.8) ? songsOf : pick(NAMES), take: Math.floor(rand() * 13) }
  const groups = chance(0.4) ? groupsFrom(songsOf, 1 + Math.floor(rand() * 4)) : null
  const personal = chance(0.5)
  const yourAlbums = personal && chance(0.7) ? albums.filter(() => chance(0.5)).map((album) => album.id) : null
  const yourArtists = personal && chance(0.6) ? artists.filter(() => chance(0.5)).map((artist) => [artist.id, Math.floor(rand() * 3)]) : null
  const first = SONGS[songsOf][0]
  const roll = rand()
  const text = roll < 0.35 && first ? `${first.title} ${first.credit}`
    : roll < 0.5 && first ? first.title
    : roll < 0.65 ? pick(ARTISTS).name
    : Array.from({ length: 1 + Math.floor(rand() * 2) }, () => pick(WORDS)).join(' ')
  const failed = chance(0.08)
  return {
    text, library: failed ? null : lib(artists, albums, library), failed, artistList: unique, songsOf, list: Math.floor(rand() * lists.length),
    ev: Math.floor(rand() * 4), matches, groups, songs, personal, yourAlbums, yourArtists,
  }
}

function cases() {
  const out = FIXED.map(webCase)
  for (let number = 0; number < 45; number++) out.push(webCase(seededCase()))
  return out
}

/* ===== a MusicBrainz artist's page ===== */

const P_GROUPS = {
  dummy: groupOf('48140466-cff6-3222-bd55-63c27e43190d', 'Dummy', '1994-08-22', 'Album', [], credited(MBID.portishead, 'Portishead')),
  third: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e01', 'Third', '2008-04-28', 'Album', [], credited(MBID.portishead, 'Portishead')),
  self: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e02', 'Portishead', '1997-09-29', 'Album', [], credited(MBID.portishead, 'Portishead')),
  roseland: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03', 'Roseland NYC Live', '1998-11-02', 'Album', ['Live'], credited(MBID.portishead, 'Portishead')),
  remix: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e06', 'Dummy Remixed', '1995-06', 'Album', ['Remix'], credited(MBID.portishead, 'Portishead')),
  undated: { id: 'a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e09', title: 'Untitled', 'primary-type': 'Album' },
  undatedB: { id: 'a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e19', title: 'another Untitled', 'first-release-date': '', 'primary-type': 'Album' },
  badDate: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e10', 'Glory Times', '19xx', 'Album', [], []),
  ete: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e21', 'Été', '1997', 'Album', [], []),
  ete2: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e22', 'ete', '1997', 'Album', [], []),
  zebra: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e23', 'Zebra', '1997-01', 'Album', [], []),
  apple: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e24', 'apple', '1997-12-31', 'Album', [], []),
  compilation: groupOf('a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e25', 'Bristol', '2001', 'Album', ['Compilation'], []),
  noTitle: { id: 'a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e26', 'first-release-date': '2003' },
  noId: { id: '', title: 'No id', 'first-release-date': '2004' },
}
const REL = { dummy: '76df3287-6cda-33eb-8e9a-044b5e15ffdd', dummyUS: '00163fb1-5ab7-4fec-b0dd-a915e2722340', third: '930345b1-a970-3495-a1dd-55147bea7741' }

function artistPage() {
  const G = P_GROUPS
  const lists = [
    null,
    [],
    [folder('Portishead/Dummy', 'Portishead', 'Dummy', { release_mbid: REL.dummy, release_group_mbid: G.dummy.id, yours: true })],
    [
      folder('Portishead/Dummy', 'Portishead', 'Dummy', { release_mbid: REL.dummy, release_group_mbid: G.dummy.id, yours: false, year: '1994' }),
      folder('Portishead/Dummy (US)', 'Portishead', 'Dummy', { release_mbid: REL.dummyUS, release_group_mbid: G.dummy.id, edition: 'US', yours: false }),
      folder('Portishead/Dummy (rip)', 'Portishead', 'Dummy', { release_group_mbid: G.dummy.id, yours: true }),
      folder('Portishead/Third', 'Portishead', 'Third', { release_mbid: REL.third, release_group_mbid: G.third.id, yours: false }),
      folder('Portishead/Third (again)', 'Portishead', 'Third', { release_mbid: ` ${REL.third.toUpperCase()} `, release_group_mbid: G.third.id, yours: false }),
      folder('Portishead/Roseland', 'Portishead', 'Roseland NYC Live', { release_group_mbid: G.roseland.id }),
    ],
  ]
  const groupLists = [
    [],
    Object.values(G),
    [G.dummy, G.third, G.dummy, G.self, G.roseland],
    [G.ete, G.ete2, G.zebra, G.apple, G.undated, G.undatedB, G.badDate, G.noTitle, G.noId],
  ]
  const rowOf = (row) => ({ key: row.key, title: row.title, year: row.year, group: row.group?.id ?? null, held: row.held, yours: row.yours ?? null, editions: row.editions, releases: row.releases, kind: row.kind, line: A.rowLine(row, false), linePersonal: A.rowLine(row, true) })
  const facts = [
    null,
    {},
    { type: 'Group', area: 'United Kingdom', begin_area: 'Bristol', country: 'GB', began: '1991', ended: false },
    { type: 'Group', area: 'United Kingdom', country: 'GB', began: '1960-08', ended_on: '1970-04-10', ended: true },
    { type: 'Person', country: 'US', began: '1969-08-06', ended: true },
    { area: '', country: 'XW', ended_on: '2003-10-21', ended: true },
    { type: '', began: '', ended_on: '', disambiguation: 'the tribute band' },
    { type: 'Orchestra', begin_area: 'Wien', area: 'Austria', began: '18', ended: false },
  ]
  return {
    groups: Object.values(G),
    lists,
    pages: lists.flatMap((folders, list) => groupLists.map((groups, at) => ({
      list, groups: groups.map((each) => each.id), rows: A.artistRows([], groups, folders ? O.buildOwnedIndex(folders) : null).map(rowOf),
    }))),
    facts: facts.map((given) => ({ facts: given, line: A.factsLine(given) })),
  }
}

/* ===== out ===== */

function vectors() {
  return {
    numbers: numbers(),
    words: words(),
    queries: queries(),
    titles: titles(),
    songs: songs(),
    holding: holding(),
    pressings: pressings(),
    cases: cases(),
    artist: artistPage(),
    collation: collation(),
  }
}

/** JSON with every character outside printable ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[^\n -~]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-search-songs-vectors.cjs, then port the change to DeadwaxCore and see SearchSongsVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
