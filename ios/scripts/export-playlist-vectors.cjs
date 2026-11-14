#!/usr/bin/env node
/**
 * The iPhone app's playlist rules, as the web app's own TypeScript answers them (Phase 4, notes/ios-specs/phase4-library.md
 * 2.1-2.3 and 7): ui/src/lib/playlists.ts and ui/src/lib/playedAlbums.ts compiled with the repo's TypeScript and run
 * over every case below - the words and limits, each playlist's group, row line, whose line and why it has no Edit, the
 * groups, the counts and lengths, the hidden line, the album stubs a playlist's songs are remembered under and what is
 * held over them, and the store of albums played from driven through its bounds. Written to
 *
 *   ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/playlists/playlist-vectors.json
 *
 * which DeadwaxCoreTests' PlaylistVectorTests replays against DeadwaxCore's Playlists.swift, PlaylistPlay.swift and
 * PlayedAlbums.swift - the ports - so a rule changed on the web and not in the app (or the other way about) fails a test.
 *
 *   node ios/scripts/export-playlist-vectors.cjs           writes the fixture
 *   node ios/scripts/export-playlist-vectors.cjs --check   fails when the fixture isn't what the TypeScript says now
 *                                                          (ui/test/iosplaylists.sim.cjs runs this in CI)
 *
 * Slice 1's rules only: Edit's, the picker's and the drag's (startEdit ... duplicateQuestion, edgeScroll) come with
 * slice 2. Every playlist and song here is invented. Needs ui/node_modules (npm install in ui/) and a writable TMPDIR.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/playlists/playlist-vectors.json')
const CHECK = process.argv.includes('--check')

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-ios-playlists-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/playlists.ts', 'src/lib/playedAlbums.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const P = require(path.join(OUT, 'lib/playlists.js'))
const PA = require(path.join(OUT, 'lib/playedAlbums.js'))
fs.rmSync(OUT, { recursive: true, force: true })

/* ===== playlists ================================================================================= */

const playlist = (id, over) => ({
  id, name: `Playlist ${id}`, comment: '', songCount: 12, duration: 2880, created: '2026-10-01T10:00:00Z',
  changed: '2026-11-01T10:00:00Z', owner: 'james', public: false, coverArt: `pl-${id}_abc`, mine: true, editable: true,
  ...over,
})

/** Each a shape a rule turns on: whose, shared or not, the owner named or not, the counts and lengths. */
const PLAYLISTS = [
  playlist('yours'),
  playlist('yours-public', { public: true }),
  playlist('yours-one', { songCount: 1, duration: 251 }),
  playlist('yours-empty', { songCount: 0, duration: 0, coverArt: null }),
  playlist('yours-long', { songCount: 340, duration: 81_000 }),
  playlist('yours-hour', { songCount: 15, duration: 3600 }),
  playlist('yours-just-under', { songCount: 14, duration: 3569 }),
  playlist('yours-rounds-up', { songCount: 14, duration: 3570 }),
  playlist('shared', { owner: 'sam', mine: false, editable: false, public: true }),
  playlist('shared-no-owner', { owner: '', mine: false, editable: false, public: true }),
  playlist('shared-short', { owner: 'Ana Lu\u00eds', mine: false, editable: false, public: true, songCount: 2, duration: 29 }),
  playlist('shared-silent', { owner: 'sam', mine: false, editable: false, public: true, songCount: 3, duration: 0 }),
  playlist('file', { editable: false }),
  playlist('file-public', { editable: false, public: true, songCount: 1, duration: 61 }),
  playlist('file-empty', { editable: false, songCount: 0, duration: 0 }),
  playlist('odd-owner', { owner: 'SAM', mine: false, editable: true, public: true }),
]

const SONG_COUNTS = [0, 1, 12, 2000, 2001]

function playlistVectors() {
  return PLAYLISTS.map((one) => ({
    playlist: one,
    group: P.groupOf(one),
    rowLine: P.rowLine(one),
    ownerLine: P.ownerLine(one),
    readOnly: SONG_COUNTS.map((songs) => ({ songs, words: P.readOnlyWords(one, songs), canEdit: P.canEdit(one, songs) })),
  }))
}

function groupVectors() {
  const order = (list) => {
    const groups = P.groupPlaylists(list)
    return { yours: groups.yours.map((p) => p.id), shared: groups.shared.map((p) => p.id), files: groups.files.map((p) => p.id) }
  }
  const lists = {
    'none': [],
    'all of them': PLAYLISTS,
    'reversed': [...PLAYLISTS].reverse(),
    'only shared': PLAYLISTS.filter((p) => !p.mine),
    'yours and files, interleaved': PLAYLISTS.filter((p) => p.mine).sort((a, b) => (a.id < b.id ? -1 : 1)),
  }
  return Object.entries(lists).map(([name, list]) => ({ name, ids: list.map((p) => p.id), groups: order(list) }))
}

/* ===== the counts and lengths ===================================================================== */

const COUNTS = [0, 1, 2, 12, 999, 2000, 2001]
const SECONDS = [0, 0.4, 1, 29, 29.9, 30, 59, 89, 90, 251, 2880, 3569, 3570, 3599, 3600, 3629, 3630, 3900, 5399, 36_000, 81_000,
  360_000, -1, -29, -31, -90]

/* ===== the album stubs ============================================================================ */

const song = (id, over) => ({ id, title: `Song ${id}`, ...over })

const STUB_CASES = [
  { name: 'none', songs: [] },
  {
    name: 'two albums interleaved, a song twice',
    songs: [
      song('a1', { album: 'Dummy', albumId: 'al-d', artist: 'Portishead', coverArt: 'al-d', year: 1994, displayAlbumArtist: 'Portishead' }),
      song('b1', { album: 'Mezzanine', albumId: 'al-m', artist: 'Massive Attack', coverArt: 'al-m', year: 1998 }),
      song('a2', { album: 'Dummy', albumId: 'al-d', artist: 'Portishead', coverArt: 'al-d-2', year: 1995 }),
      song('a1', { album: 'Dummy', albumId: 'al-d', artist: 'Portishead', coverArt: 'al-d', year: 1994 }),
    ],
  },
  {
    name: 'no album id, an empty one, no album name',
    songs: [
      song('x1', { album: 'Loose', artist: 'Someone' }),
      song('x2', { albumId: '', album: 'Empty id' }),
      song('x3', { albumId: 'al-n', artist: 'Nameless' }),
    ],
  },
  {
    name: 'the album artist over the song artist, empties dropped',
    songs: [
      song('c1', { album: 'Split', albumId: 'al-s', artist: 'Guest', displayAlbumArtist: 'Various Artists', coverArt: '', year: 0 }),
      song('c2', { album: 'Blank artist', albumId: 'al-b', artist: '', displayAlbumArtist: '' }),
      song('c3', { album: 'Only artist', albumId: 'al-o', artist: 'Solo', displayAlbumArtist: '' }),
      song('c4', { album: 'No artist', albumId: 'al-x' }),
    ],
  },
]

/** A stub as the fixture holds it: what Swift's Album compares, the songs by id. */
const stubOf = (album) => ({
  id: album.id,
  name: album.name ?? null,
  artist: album.artist ?? null,
  coverArt: album.coverArt ?? null,
  year: album.year ?? null,
  songs: (album.song ?? []).map((s) => s.id),
  partial: album.partial === true,
})

function stubVectors() {
  return STUB_CASES.map(({ name, songs }) => ({
    name,
    songs,
    albums: P.playlistAlbums(songs).map(stubOf),
    stubFor: songs.map((one) => stubOf(P.stubFor(one))),
  }))
}

const whole = (id, songIds) => ({ id, name: `Whole ${id}`, artist: 'Whole artist', coverArt: `cover-${id}`, year: 2001, song: songIds.map((s) => song(s, { albumId: id })) })
const partialAlbum = (id, songIds) => ({ ...whole(id, songIds), name: `Stub ${id}`, partial: true })

const HELD_CASES = [
  { name: 'nothing held', songs: STUB_CASES[1].songs, held: [] },
  { name: 'the whole album held', songs: STUB_CASES[1].songs, held: [whole('al-d', ['a1', 'a2', 'a3', 'a4'])] },
  { name: 'an earlier stub held, its songs overlapping', songs: STUB_CASES[1].songs, held: [partialAlbum('al-m', ['b0', 'b1', 'b2'])] },
  { name: 'both, and one held of another album', songs: STUB_CASES[1].songs,
    held: [whole('al-m', ['b1']), partialAlbum('al-d', ['a2', 'a9']), whole('al-other', ['z1'])] },
]

function heldVectors() {
  return HELD_CASES.map(({ name, songs, held }) => {
    const byId = new Map(held.map((album) => [album.id, album]))
    const stubs = P.playlistAlbums(songs)
    return {
      name,
      songs,
      held: held.map((album) => ({ ...stubOf(album), partial: album.partial === true })),
      albums: P.withHeld(stubs, (id) => byId.get(id) ?? null).map(stubOf),
    }
  })
}

/* ===== the albums played from ===================================================================== */

/** A run of operations on one store, each step what `get` finds of every id the run names: which answer, by the
 *  step that put it (`tag` - "s3", or "s3.1" for a queue's second album), so a put that left an older answer in place
 *  fails as surely as one that let the album go. */
function playedRun(name, kept, queueKept, steps) {
  const store = kept === null ? PA.createPlayedAlbums() : PA.createPlayedAlbums(kept, queueKept)
  const ids = [...new Set(steps.flatMap(([, list]) => list))].sort()
  return {
    name, kept, queueKept,
    steps: steps.map(([op, list], step) => {
      const albums = list.map((id, at) => ({ id, tag: at === 0 ? `s${step}` : `s${step}.${at}` }))
      if (op === 'remember') store.remember(albums[0])
      else if (op === 'queue') store.rememberQueue(albums)
      else if (op === 'also') store.also(albums[0])
      const held = ids.flatMap((id) => {
        const found = store.get(id)
        return found === null ? [] : [{ id, tag: found.tag }]
      })
      return { op, ids: list, held }
    }),
  }
}

const range = (from, to) => Array.from({ length: to - from }, (_, i) => `a${String(from + i).padStart(3, '0')}`)

function playedVectors() {
  return [
    playedRun('remember past eight', null, null, [
      ...range(0, 10).map((id) => ['remember', [id]]),
      ['remember', ['a003']], ['remember', ['a010']],
    ]),
    playedRun('a queue of twelve, then one played', null, null, [
      ['remember', ['a900']],
      ['queue', range(0, 12)],
      ['also', ['a100']],
      ['also', ['a001']],
      ['remember', ['a200']],
    ]),
    playedRun('a queue past the bound', null, null, [
      ['queue', range(0, 70)],
      ['also', ['a500']],
      ['queue', [...range(0, 3), 'a001', 'a002']],
    ]),
    playedRun('also grows, then a queue', 3, 5, [
      ['remember', ['a050']], ['remember', ['a051']], ['remember', ['a052']],
      ['also', ['a053']], ['also', ['a054']], ['also', ['a055']], ['also', ['a056']], ['also', ['a053']],
      ['queue', ['a060', 'a061']],
      ['remember', ['a070']], ['remember', ['a071']], ['remember', ['a072']],
    ]),
    playedRun('bounds of one', 1, 1, [
      ['remember', ['a001']], ['remember', ['a002']], ['queue', ['a003', 'a004']], ['also', ['a005']], ['also', ['a005']],
    ]),
    playedRun('bounds of nought', 0, 0, [
      ['queue', ['a001', 'a002']], ['also', ['a003']], ['remember', ['a004']],
    ]),
    playedRun('a queue with an album twice', null, null, [
      ['queue', ['a001', 'a002', 'a001', 'a003']],
      ...range(10, 18).map((id) => ['remember', [id]]),
    ]),
    playedRun('an empty queue', null, null, [
      ['queue', range(0, 12)],
      ['queue', []],
      ['also', ['a100']],
      ['remember', ['a101']],
      ['queue', []],
    ]),
    playedRun('the same album put again', 2, 3, [
      ['remember', ['a001']], ['also', ['a001']], ['queue', ['a002', 'a001']], ['also', ['a002']], ['remember', ['a001']],
    ]),
  ]
}

function vectors() {
  return {
    made_from: 'ui/src/lib/playlists.ts and ui/src/lib/playedAlbums.ts (compiled)',
    words: {
      PLAYLISTS_EMPTY: P.PLAYLISTS_EMPTY, PLAYLISTS_EMPTY_HOW: P.PLAYLISTS_EMPTY_HOW, PLAYLIST_EMPTY: P.PLAYLIST_EMPTY,
      PLAYLIST_GONE: P.PLAYLIST_GONE, listFailed: P.listFailed('Why it failed.'),
    },
    constants: {
      PLAYLIST_NAME_MAX: P.PLAYLIST_NAME_MAX, PLAYLIST_COMMENT_MAX: P.PLAYLIST_COMMENT_MAX, PLAYLIST_SONGS_MAX: P.PLAYLIST_SONGS_MAX,
      PLAYLISTS_FRESH_MS: P.PLAYLISTS_FRESH_MS, PLAYLISTS_KEPT: P.PLAYLISTS_KEPT,
      PLAYED_KEPT: PA.PLAYED_KEPT, QUEUE_ALBUMS_KEPT: PA.QUEUE_ALBUMS_KEPT,
    },
    playlists: playlistVectors(),
    groups: groupVectors(),
    songCount: COUNTS.map((n) => ({ n, text: P.songCount(n) })),
    lengthText: SECONDS.map((seconds) => ({ seconds, text: P.lengthText(seconds) })),
    songsLine: COUNTS.flatMap((n) => [0, 59, 2880, 3900].map((seconds) => ({ n, seconds, text: P.songsLine(n, seconds) }))),
    hiddenWords: [-1, 0, 1, 2, 10].map((hidden) => ({ hidden, text: P.hiddenWords(hidden) })),
    stubs: stubVectors(),
    withHeld: heldVectors(),
    played: playedVectors(),
  }
}

/* ===== writing =================================================================================== */

/** JSON with every character outside ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[\u0080-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-playlist-vectors.cjs, then port the change to DeadwaxCore's Playlists.swift, PlaylistPlay.swift or PlayedAlbums.swift and see PlaylistVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
