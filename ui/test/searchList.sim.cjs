/**
 * Search like Apple Music (2.0.0-player.55): lib/searchList.ts - what the Search tab's one list is made of - on
 * real answers: MusicBrainz's artist searches as deadwax's /search_musicbrainz/artists answers them
 * (tests/fixtures/artists/*.route.json, recorded 2026-10-15, matched by the server's own artist_match), Portishead's
 * release groups unfiltered and with the studio clause (tests/fixtures/search/), and the song search's recordings
 * (tests/fixtures/songs/).
 *
 * What it pins:
 *  - THE TIER (matchTier): exact by foldName (a leading "the" folded away), a MusicBrainz artist exact by its
 *    name-or-alias match too (Ye for "kanye west"); the artist reading's title rule (the self-titled album is by
 *    the artist, never exact); album-by-artist's credit rule; "starts with" only from three characters; song titles
 *    folded by titleKey ("Roads (live)" is Roads).
 *  - THE RANK: tier, then source (yours, the store's, MusicBrainz's - what MusicBrainz BROUGHT in ranks as
 *    MusicBrainz's), then kind, then position.
 *  - TOP RESULTS (topResults): the best, then its family (a library song's album and artist, a library album's
 *    artist, a MusicBrainz song's named album - the albums answer's group when it holds it - and its sole artist,
 *    resolved to the library's when it knows them; a MusicBrainz album's sole credit), then round by round; n 3 and
 *    6; a fixed prefix continued. The slice's worked examples, each.
 *  - DECIDING EARLY (decidedTop): one phantom per kind still out, at the best tier its kind can reach under the
 *    reading (no artist phantom under album-by-artist, no song one under the artist reading); the picks before the
 *    first phantom; and - a property check over the fixtures - a decided prefix never changes when the real answers
 *    replace the phantoms.
 *  - ONE THING ONCE: newArtists (by id, by the name owned folders are filed under, two Nirvanas staying two, Ye),
 *    newSongs, heldUnlisted; studioOrder on the measured studio answer; allAlbumsQuery per reading (never for
 *    Various Artists).
 *  - THE SECTIONS: yours, the store's, MusicBrainz's, each capped on its own per frame; a late kind's rows held ones
 *    first; the logins-on order with a whose not yet known ranking as yours.
 *  - THE MOMENTS: sectionsReady, lateKinds, drawInOrFold, nextBehind.
 *  - THE WORDS: every row's line and place, logins on and off; the region's, the slots', the foot's.
 *
 * Run it with:  node ui/test/searchList.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURES = path.resolve(__dirname, '../../tests/fixtures')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-searchlist-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchList.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/searchList.js'))
const { groupSongs } = require(path.join(OUT, 'lib/songs.js'))
const { buildOwnedIndex } = require(path.join(OUT, 'lib/owned.js'))
const { searchQuery } = require(path.join(OUT, 'lib/searchQuery.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const load = (name) => JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'))
const artistsOf = (name) => load(`artists/${name}.route`).matches
const kanye = artistsOf('kanye-west'), nirvana = artistsOf('nirvana'), portisheadMb = artistsOf('portishead'), radiohead = artistsOf('radiohead')
const studio = load('search/rg-artist-portishead-studio')['release-groups']
const unfiltered = load('search/rg-artist-portishead')['release-groups']
const roadsSongs = groupSongs(load('songs/roads-portishead').recordings)

const PORTISHEAD = '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'
const YE = kanye[0].mbid
const DUMMY = studio.find((group) => group.title === 'Dummy')
const THIRD = studio.find((group) => group.title === 'Third')
const SELF = studio.find((group) => group.title === 'Portishead')

//? the library, as Navidrome's search3 answers it
const P = { id: 'ar-p', name: 'Portishead', albumCount: 3, musicBrainzId: PORTISHEAD, coverArt: 'ar-p' }
const dummy = { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', artistId: 'ar-p', year: 1994, musicBrainzId: 'rel-dummy', coverArt: 'al-dummy' }
const selfTitled = { id: 'nd-self', name: 'Portishead', artist: 'Portishead', artistId: 'ar-p', year: 1997, musicBrainzId: 'rel-self' }
const song = (id, title, album = dummy) => ({ id, title, artist: 'Portishead', artistId: 'ar-p', album: album.name, albumId: album.id, coverArt: album.coverArt })
const roads = song('s-roads', 'Roads'), glory = song('s-glory', 'Glory Box'), sour = song('s-sour', 'Sour Times')
const lib = (artists = [], albums = [], songs = []) => ({ artists, albums, songs })
const index = buildOwnedIndex([
  { path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: 'rel-dummy', albumartist_mbids: [PORTISHEAD] },
])
const off = { personal: false, index, yourAlbums: null, yourArtists: null }
//? a Dummy held with no release id - held by its group, as every screen holds it - which says it has the song
const songIndex = buildOwnedIndex([{ path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, albumartist_mbids: [PORTISHEAD] }])
const family = (library, groups = [], artistList = null) => ({ library, artistList, index, groups })
const free = (text) => searchQuery(text, ['Portishead'])
const keys = (rows) => rows.map((row) => row.key)
const picks = (candidates) => candidates.map((each) => each.phantom ? 'PHANTOM' : each.key)

console.log('the tier: deadwax\'s exactness test')
{
  const reading = (text) => searchQuery(text, ['Portishead', 'The National'])
  const artist = (name) => L.artistRow({ id: name, name })
  check('an artist whose name folds to the box is exact - a leading "the" folded away, case and accents too',
    [L.matchTier(artist('The National'), 'national', reading('national')), L.matchTier(artist('Björk'), 'bjork', reading('bjork')), L.matchTier(artist('Portishead Tribute'), 'zzz', reading('zzz'))],
    [0, 0, 3])
  check('a MusicBrainz artist is exact by its name-or-alias match: Ye for "kanye west" (matched as Kanye West) - and by foldName where matched_as is empty',
    [L.matchTier(L.mbArtistRow(kanye[0]), 'kanye west', reading('kanye west')), L.matchTier(L.mbArtistRow(kanye[2]), 'kanye west', reading('kanye west')),
      L.matchTier(L.mbArtistRow({ ...radiohead[0], matched_as: '' }), 'radiohead', reading('radiohead'))],
    [0, 2, 0])
  check('...MusicBrainz\'s The National exact for "national" as the library\'s is, though answers_to keeps the "the" (foldName drops it)',
    L.matchTier(L.mbArtistRow({ mbid: 'x', name: 'The National', disambiguation: '', country: '', type: '', matched_as: '' }), 'national', reading('national')), 0)
  check('the artist reading: the self-titled album and every album of theirs by the artist (1), never exact',
    [L.matchTier(L.albumRow(selfTitled), 'portishead', reading('portishead')), L.matchTier(L.albumRow(dummy), 'portishead', reading('portishead')),
      L.matchTier(L.artistRow(P), 'portishead', reading('portishead'))],
    [1, 1, 0])
  check('album-by-artist: titled as read and credited to the artist exact; another of theirs by the artist; the artist themselves by the artist',
    [L.matchTier(L.groupRow(THIRD), 'portishead third', reading('portishead third')), L.matchTier(L.groupRow(DUMMY), 'portishead third', reading('portishead third')),
      L.matchTier(L.artistRow(P), 'portishead third', reading('portishead third')), L.matchTier(L.songRow(roads), 'roads portishead', reading('roads portishead'))],
    [0, 1, 1, 0])
  check('"starts with" only from three characters', [L.matchTier(L.artistRow(P), 'por', reading('por')), L.matchTier(L.artistRow(P), 'po', reading('po'))], [2, 3])
  check('a song\'s title folded by titleKey - "Roads (live)" is Roads; an album\'s by foldName',
    [L.matchTier(L.songRow({ ...roads, title: 'Roads (live)' }), 'roads', reading('roads')), L.matchTier(L.albumRow({ ...dummy, name: 'Dummy (Remastered)' }), 'dummy', reading('dummy'))],
    [0, 0])
  check('...free text titles exact', [L.matchTier(L.songRow(glory), 'glory box', reading('glory box')), L.matchTier(L.albumRow(dummy), 'dummy', reading('dummy'))], [0, 0])
}

console.log('\nthe rank: tier, source, kind, position')
{
  const c = (key, tier, source, kind, position) => ({ row: L.artistRow({ id: key, name: key }), key, kind, tier, source, position, phantom: false })
  const sorted = (list) => [...list].sort(L.rank).map((each) => each.key)
  check('tier first', sorted([c('a', 1, 0, 'artists', 0), c('b', 0, 2, 'songs', 9)]), ['b', 'a'])
  check('...then source (yours, the store\'s, MusicBrainz\'s)', sorted([c('mb', 0, 2, 'artists', 0), c('store', 0, 1, 'artists', 0), c('yours', 0, 0, 'songs', 5)]), ['yours', 'store', 'mb'])
  check('...then kind (artists, albums, songs)', sorted([c('song', 0, 0, 'songs', 0), c('album', 0, 0, 'albums', 0), c('artist', 0, 0, 'artists', 3)]), ['artist', 'album', 'song'])
  check('...then position', sorted([c('second', 0, 0, 'albums', 1), c('first', 0, 0, 'albums', 0)]), ['first', 'second'])
  //? the source-2 rule: an album you hold that search3 didn't list, brought in by MusicBrainz's answer, ranks as MusicBrainz's
  const plan = free('dummy')
  const rows = L.pool({ reading: plan, library: lib([], [], [sour]), artistList: null, index, marks: off, artists: [], albums: { groups: [DUMMY], shown: [] }, songs: [] })
  const brought = L.candidatesOf(rows, 'dummy', plan).find((each) => each.key === `group:${DUMMY.id}`)
  check('a held album search3 didn\'t list, brought in through MusicBrainz\'s answer: in the yours block, but ranked as MusicBrainz\'s (source 2)',
    [rows.albums.brought.map((each) => [each.row.key, each.holder]), brought.source, brought.tier], [[[`group:${DUMMY.id}`, 'yours']], 2, 0])
}

console.log('\nTop results: the best, its family, then round by round')
{
  //? "portishead", held: the mock
  const plan = free('portishead')
  const library = lib([P], [dummy], [roads, glory])
  const rows = L.pool({ reading: plan, library, artistList: [P], index, marks: off, artists: portisheadMb, albums: { groups: studio, shown: studio.filter((g) => g.id !== DUMMY.id) }, songs: null })
  const top = L.topResults(L.candidatesOf(rows, 'portishead', plan), 3, family(library, studio, [P]))
  check('"portishead", held: Portishead (exact, yours), Dummy (by the artist), Roads (by the artist) - the mock', picks(top), ['artist:ar-p', 'album:nd-dummy', 'song:s-roads'])
  check('...MusicBrainz\'s Portishead is the library\'s (by id): no second Portishead row', [rows.artists.musicbrainz.length, rows.artists.brought.length], [0, 0])
  const six = L.topResults(L.candidatesOf(rows, 'portishead', plan), 6, family(library, studio, [P]))
  check('...six on a desktop: round two takes each kind\'s next - MusicBrainz\'s studio albums by them, then the next song', picks(six),
    ['artist:ar-p', 'album:nd-dummy', 'song:s-roads', `group:${studio[0].id}`, 'song:s-glory', `group:${studio[1].id}`])

  //? "roads", Dummy held: the song, then what it belongs to
  const roadsLib = lib([], [], [roads])
  const roadsRows = L.pool({ reading: free('roads'), library: roadsLib, artistList: [P], index, marks: off, artists: null, albums: null, songs: null })
  check('"roads", Dummy held: Roads (exact, yours), then its album and artist - its family, built from the song (no album row in search3)',
    keys(L.topResults(L.candidatesOf(roadsRows, 'roads', free('roads')), 3, family(roadsLib, [], [P])).map((each) => each.row)), ['song:s-roads', 'album:nd-dummy', 'artist:ar-p'])
  const built = L.topResults(L.candidatesOf(roadsRows, 'roads', free('roads')), 3, family(roadsLib, [], null))
  check('...the family\'s album made of the song\'s own fields, its artist with the song\'s artist id (the round placeholder: no picture known)',
    [built[1].row.album, built[2].row.artist], [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', coverArt: 'al-dummy' }, { id: 'ar-p', name: 'Portishead' }])
  const gloryLib = lib([P], [dummy], [glory])
  const gloryRows = L.pool({ reading: free('glory box'), library: gloryLib, artistList: [P], index, marks: off, artists: null, albums: null, songs: null })
  check('"glory box", Dummy held: Glory Box, Dummy, Portishead - Apple\'s own order (search3\'s rows for the family when it has them)',
    picks(L.topResults(L.candidatesOf(gloryRows, 'glory box', free('glory box')), 3, family(gloryLib, [], [P]))), ['song:s-glory', 'album:nd-dummy', 'artist:ar-p'])
  check('...a library album\'s family: its artist', keys(L.familyOf(L.albumRow(dummy), family(gloryLib, [], [P]))), ['artist:ar-p'])

  //? a MusicBrainz song: its named album, then its sole artist - the library's when the library knows them
  const mbSong = L.mbSongRow(roadsSongs[0])
  check('a MusicBrainz song\'s family: its named album (made of the song\'s own album - the albums answer hasn\'t it), its sole artist resolved to the library\'s',
    [keys(L.familyOf(mbSong, family(null, [], [P]))), L.familyOf(mbSong, family(null, [], [P]))[0].type], [[`group:${roadsSongs[0].albums[0].id}`, 'artist:ar-p'], 'song-album'])
  check('...the albums answer\'s own group when it holds the same id - then it is a MusicBrainz album row', L.familyOf(mbSong, family(null, [DUMMY], [P]))[0].type, 'group')
  check('...an artist the library doesn\'t know: MusicBrainz\'s, made of the credit - no disambiguation, so its line is "Artist" alone',
    [L.familyOf(mbSong, family(null, [], []))[1].key, L.rowLine(L.familyOf(mbSong, family(null, [], []))[1], { marks: off }, true).line], [`mb-artist:${PORTISHEAD}`, 'Artist'])
  check('a MusicBrainz album\'s family: its sole credited artist', keys(L.familyOf(L.groupRow(THIRD), family(null, [], [P]))), ['artist:ar-p'])
  check('...a collaboration has none', L.familyOf(L.groupRow({ ...THIRD, 'artist-credit': [...THIRD['artist-credit'], { name: 'Someone', artist: { id: YE, name: 'Ye' } }] }), family(null, [], [P])).length, 0)
  check('...an artist has no family', L.familyOf(L.artistRow(P), family(null)).length, 0)

  //? fixed: a prefix already drawn is continued
  const all = L.candidatesOf(rows, 'portishead', plan)
  const continued = L.topResults(all, 6, family(library, studio, [P]), top.map((each) => each.row))
  check('a prefix already drawn (fixed) is continued, never re-picked: the same six, its three first', picks(continued), picks(six))
  check('fewer candidates, fewer picks; a kind with none skipped', picks(L.topResults(L.candidatesOf(L.pool({ reading: free('zz'), library: lib([P]), artistList: null, index, marks: off, artists: null, albums: null, songs: null }), 'zz', free('zz')), 6, family(lib([P])))), ['artist:ar-p'])
}

console.log('\nthe worked examples, and deciding early')
{
  const decide = (text, library, out, extra = {}) => {
    const plan = searchQuery(text, ['Portishead', 'Third Eye Blind'])
    const rows = L.pool({ reading: plan, library, artistList: [P], index, marks: off, artists: null, albums: null, songs: null, ...extra })
    const phantoms = out.map((kind) => L.phantom(kind, plan)).filter(Boolean)
    return L.decidedTop(L.candidatesOf(rows, text, plan), phantoms, 3, family(library, [], [P]))
  }
  const portishead = decide('portishead', lib([P], [dummy], [roads]), ['artists', 'albums'])
  check('"portishead": all three at the library\'s moment - MusicBrainz\'s phantoms (artists 0, albums 1) can\'t beat yours', [keys(portishead.prefix), portishead.place],
    [['artist:ar-p', 'album:nd-dummy', 'song:s-roads'], false])
  const roadsTop = decide('roads', lib([], [], [roads]), ['artists', 'albums', 'songs'])
  check('"roads": all three at the library\'s moment', [keys(roadsTop.prefix), roadsTop.place], [['song:s-roads', 'album:nd-dummy', 'artist:ar-p'], false])
  const gloryTop = decide('glory box', lib([], [dummy], [glory]), ['artists', 'albums', 'songs'])
  check('"glory box": all three at the library\'s moment', [keys(gloryTop.prefix), gloryTop.place], [['song:s-glory', 'album:nd-dummy', 'artist:ar-p'], false])
  //? "dummy": Dummy and Portishead, then the place - MusicBrainz's exact song "Dummy" could beat a song of yours that matched only through its album
  const dummyLib = lib([], [dummy], [sour])
  const dummyTop = decide('dummy', dummyLib, ['artists', 'albums', 'songs'])
  check('"dummy": Dummy, Portishead, then the place', [keys(dummyTop.prefix), dummyTop.place], [['album:nd-dummy', 'artist:ar-p'], true])
  const dummySong = groupSongs([{ id: 'r-dummy', title: 'Dummy', 'artist-credit': [{ name: 'Somebody', artist: { id: YE, name: 'Somebody' } }],
    releases: [{ id: 'rel-x', 'release-group': { id: 'g-x', title: 'Somebody\'s Album', 'primary-type': 'Album' } }] }])
  const plan = free('dummy')
  const later = L.pool({ reading: plan, library: dummyLib, artistList: [P], index, marks: off, artists: [], albums: { groups: [], shown: [] }, songs: dummySong })
  const filled = L.topResults(L.candidatesOf(later, 'dummy', plan), 3, family(dummyLib, [], [P]), dummyTop.prefix)
  check('...at moment 2 MusicBrainz\'s exact song "Dummy" fills it, ahead of Sour Times', picks(filled), ['album:nd-dummy', 'artist:ar-p', `mb-song:${dummySong[0].key}`])
  const thirdEye = { id: 'ar-teb', name: 'Third Eye Blind' }
  const third = decide('third', lib([thirdEye]), ['artists', 'albums', 'songs'])
  check('"third", only Third Eye Blind held: nothing early - MusicBrainz\'s exact "Third" could be best', [third.prefix.length, third.place], [0, true])
  const radio = L.pool({ reading: free('radiohead'), library: lib(), artistList: [], index, marks: off, artists: radiohead,
    albums: { groups: [{ id: 'g-okc', title: 'OK Computer', 'primary-type': 'Album', 'artist-credit': [{ name: 'Radiohead', artist: { id: radiohead[0].mbid, name: 'Radiohead' } }] }], shown: [] },
    songs: [] })
  radio.albums.musicbrainz = [{ row: L.groupRow({ id: 'g-okc', title: 'OK Computer', 'primary-type': 'Album' }), holder: 'yours', position: 0 }]
  check('"radiohead", nothing held: Radiohead (MusicBrainz\'s, exact), then the best album', picks(L.topResults(L.candidatesOf(radio, 'radiohead', free('radiohead')), 3, family(lib(), [], []))).slice(0, 2),
    [`mb-artist:${radiohead[0].mbid}`, 'group:g-okc'])
  //? "por": rows that start with it, yours first - when MusicBrainz isn't to be asked; with its phantoms (asked at the pause) nothing is decided early
  const por = L.pool({ reading: free('por'), library: lib([P], [dummy]), artistList: [P], index, marks: off, artists: null, albums: null, songs: null })
  check('"por" without MusicBrainz\'s phantoms: Portishead (starts with it), then Dummy', picks(L.topResults(L.candidatesOf(por, 'por', free('por')), 3, family(lib([P], [dummy]), [], [P]))),
    ['artist:ar-p', 'album:nd-dummy'])
  check('...with them: nothing decided early (MusicBrainz could have an exact "Por")', decide('por', lib([P], [dummy]), ['artists', 'albums', 'songs']).prefix.length, 0)

  check('the phantoms\' tiers by reading: free text 0/0/0; the artist reading 0/1/none; album-by-artist none/0/0',
    [['portishead', 'artist'], ['third portishead', 'album-by-artist'], ['zzz', 'free']].map(([text]) => L.KINDS.map((kind) => L.bestTier(searchQuery(text, ['Portishead']), kind))),
    [[0, 1, null], [null, 0, 0], [0, 0, 0]])
  check('...no phantom for a kind a reading doesn\'t ask', [L.phantom('artists', searchQuery('third portishead', ['Portishead'])), L.phantom('songs', searchQuery('portishead', ['Portishead']))], [null, null])

  //? the property: a decided prefix never changes when real answers replace the phantoms - over every text and answer
  const texts = ['portishead', 'roads', 'glory box', 'dummy', 'third', 'radiohead', 'nirvana', 'kanye west', 'roads portishead', 'portishead third']
  const libraries = [lib(), lib([P], [dummy], [roads, glory, sour]), lib([], [dummy], [sour]), lib([thirdEye]), lib([P], [selfTitled])]
  const answers = [
    { artists: [], albums: { groups: [], shown: [] }, songs: [] },
    { artists: portisheadMb, albums: { groups: studio, shown: studio }, songs: roadsSongs },
    { artists: nirvana, albums: { groups: unfiltered, shown: unfiltered }, songs: dummySong },
    { artists: kanye, albums: { groups: [THIRD, DUMMY], shown: [THIRD] }, songs: roadsSongs.slice(0, 1) },
    { artists: radiohead, albums: { groups: [SELF], shown: [SELF] }, songs: [] },
  ]
  let held = 0, tried = 0
  for (const text of texts) {
    const reading = searchQuery(text, ['Portishead'])
    for (const library of libraries) {
      const early = L.pool({ reading, library, artistList: [P], index, marks: off, artists: null, albums: null, songs: null })
      const asked = L.KINDS.filter((kind) => L.bestTier(reading, kind) !== null)
      for (const n of [3, 6]) {
        const { prefix } = L.decidedTop(L.candidatesOf(early, text, reading), asked.map((kind) => L.phantom(kind, reading)), n, family(library, [], [P]))
        for (const answer of answers) {
          tried++
          const real = L.pool({ reading, library, artistList: [P], index, marks: off, ...answer })
          const groups = answer.albums.groups
          const whole = L.topResults(L.candidatesOf(real, text, reading), n, family(library, groups, [P])).map((each) => each.key)
          if (JSON.stringify(whole.slice(0, prefix.length)) === JSON.stringify(keys(prefix))) held++
        }
      }
    }
  }
  check(`the property: a decided prefix is the real answers' Top results' prefix, every time (${tried} combinations)`, held, tried)
}

console.log('\none thing, shown once')
{
  //? newArtists: by id
  check('a MusicBrainz artist the library has, by id: dropped - the library\'s instead (listed, so not brought)',
    L.newArtists(portisheadMb, [P], index, [P]), { musicbrainz: [], brought: [] })
  check('...search3 didn\'t list them: brought in, at MusicBrainz\'s position', L.newArtists(portisheadMb, [P], index, []).brought.map((each) => [each.artist.id, each.position]), [['ar-p', 0]])
  //? by the name owned folders with that id are filed under: Kanye West, no id in Navidrome, folders tagged with Ye's id
  const kanyeLib = { id: 'ar-k', name: 'Kanye West', albumCount: 2 }
  const kanyeIndex = buildOwnedIndex([{ path: 'Kanye West/Graduation', artist: 'Kanye West', album: 'Graduation', release_mbid: 'rel-g', albumartist_mbids: [YE] }])
  const kanyeSplit = L.newArtists(kanye, [kanyeLib], kanyeIndex, [kanyeLib])
  check('"kanye west": your Kanye West (by the name the folders tagged Ye are filed under) - and no "Ye" row',
    [kanyeSplit.musicbrainz.map((each) => each.match.name), kanyeSplit.brought.length], [['¥$', 'Kanye West Tribute Band', 'Kanye West & Hatsune Miku'], 0])
  //? two Nirvanas: a library Nirvana with no id - MusicBrainz's name step finds it, but many MusicBrainz artists answer to "Nirvana"
  const nirvanaLib = { id: 'ar-n', name: 'Nirvana', albumCount: 1 }
  const nirvanaSplit = L.newArtists(nirvana, [nirvanaLib], null, [nirvanaLib])
  check('two Nirvanas stay two rows (the name step believed only when one MusicBrainz artist answers to it), each with its disambiguation',
    [nirvanaSplit.musicbrainz.length, nirvanaSplit.musicbrainz.slice(0, 3).map((each) => L.rowLine(L.mbArtistRow(each.match), { marks: off }).line)],
    [nirvana.length, ['1980s–1990s US grunge band · Group · US', 'as Nirvana · Swedish death metal band · Group · SE', '60s band from the UK · Group · GB']])
  check('...but one MusicBrainz artist answering to a library name with no id: believed', L.newArtists(portisheadMb, [{ id: 'ar-p2', name: 'Portishead' }], null, []).brought.map((each) => each.artist.id), ['ar-p2'])

  //? newSongs
  const songs = L.newSongs(roadsSongs, [roads], index)
  check('a MusicBrainz song a library song of the answer already is (its title and its credit): dropped', [songs.musicbrainz.length + songs.brought.length, roadsSongs.length], [0, 1])
  const heldSong = L.newSongs(roadsSongs, [], songIndex)
  check('...one held with an album it is on (Dummy, by group) that search3 didn\'t list: brought in, yours', heldSong.brought.map((each) => [each.song.title, each.yours]), [['Roads', true]])
  check('...a pressing held that nothing says has the song isn\'t holding it (step 7\'s rule): MusicBrainz\'s', L.newSongs(roadsSongs, [], index).musicbrainz.length, 1)
  check('...one nothing holds: MusicBrainz\'s', L.newSongs(roadsSongs, [], null).musicbrainz.map((each) => each.song.title), ['Roads'])
  check('...another artist\'s song of that title isn\'t it', L.newSongs(roadsSongs, [{ ...roads, artist: 'Someone Else' }], null).musicbrainz.length, 1)

  //? heldUnlisted
  check('a held album search3 didn\'t list: brought in', L.heldUnlisted([DUMMY, THIRD], index, []).map((group) => group.title), ['Dummy'])
  check('...one search3 listed (its release is one held of the group): not', L.heldUnlisted([DUMMY, THIRD], index, [dummy]).length, 0)
  check('...nothing without the library\'s answer, nor an album not held', [L.heldUnlisted([DUMMY], null, []).length, L.heldUnlisted([THIRD], index, []).length], [0, 0])
  check('the named artist under album-by-artist: by foldName, only when exactly one answers',
    [L.namedArtist(searchQuery('roads portishead', ['Portishead']), [P])?.id, L.namedArtist(searchQuery('roads portishead', ['Portishead']), [P, { id: 'x', name: 'The Portishead' }]), L.namedArtist(searchQuery('portishead', ['Portishead']), [P])],
    ['ar-p', null, null])
  const roadsPool = L.pool({ reading: searchQuery('roads portishead', ['Portishead']), library: lib([], [], [roads]), artistList: [P], index, marks: off, artists: null, albums: null, songs: null })
  check('...and it leads the Artists section\'s library rows (Navidrome needs every word, so search3 found no artist)', keys(L.sectionRows(roadsPool.artists)), ['artist:ar-p'])
}

console.log('\nthe studio clause, and what is asked')
{
  check('the studio answer read as an artist\'s albums: Album before EP, plain first, earliest first',
    L.studioOrder(studio).map((group) => group.title), ['Dummy', 'Portishead', 'Third', 'R.A.R.E (Reliving a Real Experience)', 'All Mine', 'Magic Doors'])
  check('...the unfiltered first page holds no Dummy and no Third (measured) - why All asks the clause', unfiltered.some((group) => ['Dummy', 'Third'].includes(group.title)), false)
  check('All\'s albums for an artist read: their studio albums and EPs, named on screen',
    L.allAlbumsQuery(searchQuery('portishead', ['Portishead'])),
    { query: '(artist:"Portishead") AND (primarytype:"Album" OR primarytype:"EP") AND -secondarytype:"Live" AND -secondarytype:"Compilation" AND -secondarytype:"Interview" AND -secondarytype:"Demo" AND -secondarytype:"Remix" AND -secondarytype:"DJ-mix"', studio: true })
  check('...never for Various Artists ("va"): today\'s query, unfiltered', L.allAlbumsQuery(searchQuery('va', [])), { query: 'artist:"Various Artists"', studio: false })
  check('...free text and album-by-artist as read', [L.allAlbumsQuery(searchQuery('dummy', [])).query, L.allAlbumsQuery(searchQuery('portishead third', ['Portishead'])).studio],
    ['dummy', false])
  check('the constants: Top results 3 and 6, the waits 1.5 s, ten artists a page, the chips\' counts inside the route\'s bounds',
    [L.TOP_RESULTS, L.RESULTS_WAIT_MS, L.LIBRARY_LATE_MS, L.ARTIST_SEARCH_LIMIT, L.CHIP_LIBRARY_COUNTS.artists.artistCount, L.CHIP_LIBRARY_COUNTS.albums.albumCount, L.CHIP_LIBRARY_COUNTS.songs.songCount],
    [{ phone: 3, desktop: 6 }, 1500, 1500, 10, 50, 50, 100])
}

console.log('\nthe sections: yours, the store\'s, MusicBrainz\'s - each capped on its own')
{
  const plan = free('portishead')
  const rows = L.pool({ reading: plan, library: lib([P], [dummy, selfTitled], [roads, glory, sour]), artistList: [P], index, marks: off,
    artists: radiohead, albums: { groups: studio, shown: studio.filter((g) => g.id !== DUMMY.id) }, songs: roadsSongs })
  check('the phone\'s preview: artists 2+2, albums 3+3, songs 3+3; the desktop\'s 3+3, 4+4, 4+4', [L.previewRows('phone'), L.previewRows('desktop')],
    [{ artists: [2, 2], albums: [3, 3], songs: [3, 3] }, { artists: [3, 3], albums: [4, 4], songs: [4, 4] }])
  check('albums on a phone: your two, then three of MusicBrainz\'s - MusicBrainz shows even beside many of yours',
    keys(L.sectionRows(rows.albums, L.PREVIEW.phone.albums)), ['album:nd-dummy', 'album:nd-self', ...studio.filter((g) => g.id !== DUMMY.id).slice(0, 3).map((g) => `group:${g.id}`)])
  check('songs: yours capped at three on a phone (the MusicBrainz Roads dropped - yours is it)', keys(L.sectionRows(rows.songs, L.PREVIEW.phone.songs)), ['song:s-roads', 'song:s-glory', 'song:s-sour'])
  check('everything, for a kind view', L.sectionRows(rows.albums).length, 2 + studio.length - 1)
  //? logins on: yours, then the store's - a whose not yet known ranks as yours
  const third = { id: 'nd-third', name: 'Third', artist: 'Portishead', artistId: 'ar-p', year: 2008, musicBrainzId: 'rel-third' }
  const storeIndex = buildOwnedIndex([
    { path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_mbid: 'rel-dummy', yours: true },
    { path: 'Portishead/Third', artist: 'Portishead', album: 'Third', release_mbid: 'rel-third', yours: false },
  ])
  const albumsKnown = new Map([['nd-third', third], ['nd-dummy', dummy]])
  const on = { personal: true, index: storeIndex, yourAlbums: new Set(['nd-dummy']), yourArtists: new Map([['ar-p', 1]]), albumOf: (id) => albumsKnown.get(id) ?? null }
  const onThird = song('s-machine', 'Machine Gun', third), unknown = song('s-rose', 'Humming', { id: 'nd-unknown', name: 'Roseland' }), onDummy = song('s-mys', 'Mysterons')
  const store = L.pool({ reading: plan, library: lib([], [third, dummy], [onThird, unknown, onDummy]), artistList: null, index: storeIndex, marks: on, artists: null, albums: null, songs: null })
  check('logins on: yours before the store\'s - Third (the store\'s) after Dummy (yours by your albums\' ids)', keys(L.sectionRows(store.albums)), ['album:nd-dummy', 'album:nd-third'])
  check('...a song whose album isn\'t known yet ranks as yours: Humming and Mysterons, then Machine Gun (on Third, the store\'s)', keys(L.sectionRows(store.songs)),
    ['song:s-rose', 'song:s-mys', 'song:s-machine'])
  check('...its whose known later reads "in the store" in place, never re-sorted (rows decided at the draw)',
    [L.rowLine(L.songRow(unknown), { marks: on }).place, L.rowLine(L.songRow(unknown), { marks: { ...on, albumOf: (id) => (id === 'nd-unknown' ? { musicBrainzId: 'rel-third' } : null) } }).place],
    ['', 'in the store'])
  check('...an album among your albums\' ids is yours whatever search3\'s starred said (asked before an Add)', L.albumYours({ id: 'nd-third', musicBrainzId: 'rel-third' }, { ...on, yourAlbums: new Set(['nd-third']) }), true)
  //? a late kind's rows: held ones first
  const late = L.pool({ reading: plan, library: lib(), artistList: null, index, marks: off, artists: null, albums: { groups: [THIRD, DUMMY], shown: [THIRD] }, songs: null })
  check('a late kind\'s rows land in its slot held ones first, then MusicBrainz\'s', keys(L.lateRows(late.albums)), [`group:${DUMMY.id}`, `group:${THIRD.id}`])
}

console.log('\nthe moments')
{
  check('sections wait for the library', L.sectionsReady({ librarySettled: false, musicBrainz: true, asked: true, out: [], capPassed: true }), false)
  check('...MusicBrainz not to be asked: at once', L.sectionsReady({ librarySettled: true, musicBrainz: false, asked: false, out: [], capPassed: false }), true)
  check('...to be asked, not yet: wait', L.sectionsReady({ librarySettled: true, musicBrainz: true, asked: false, out: ['albums'], capPassed: false }), false)
  check('...every kind in: now; one out: at the cap', [L.sectionsReady({ librarySettled: true, musicBrainz: true, asked: true, out: [], capPassed: false }),
    L.sectionsReady({ librarySettled: true, musicBrainz: true, asked: true, out: ['songs'], capPassed: false }), L.sectionsReady({ librarySettled: true, musicBrainz: true, asked: true, out: ['songs'], capPassed: true })],
    [true, false, true])
  check('late kinds: those still out', L.lateKinds(['artists', 'albums', 'songs'], (kind) => kind === 'albums'), ['artists', 'songs'])
  check('a late kind lands IN when its section is the last drawn (nothing tappable below - every section has See all), else FOLDS',
    [L.drawInOrFold('songs', ['artists', 'albums', 'songs']), L.drawInOrFold('albums', ['artists', 'albums', 'songs']), L.drawInOrFold('albums', ['albums']), L.drawInOrFold('songs', ['songs'], true)],
    ['in', 'fold', 'in', 'fold'])
  check('Behind: on after a late or failed search, off after one in time, unchanged by one superseded or refused',
    [L.nextBehind(false, 'late'), L.nextBehind(false, 'failed'), L.nextBehind(true, 'in-time'), L.nextBehind(true, 'superseded'), L.nextBehind(false, 'superseded'), L.nextBehind(true, 'refused')],
    [true, true, false, true, false, true])
}

console.log('\nthe words: lines and places, logins off and on')
{
  const on = { personal: true, index, yourAlbums: new Set(), yourArtists: new Map([['ar-p', 2]]) }
  const line = (row, marks = off, top = false) => L.rowLine(row, { marks }, top)
  check('a library artist: the count in a section, "Artist · " + it in Top results', [line(L.artistRow(P)), line(L.artistRow(P), off, true)],
    [{ line: '', place: '3 albums in your library' }, { line: 'Artist', place: '3 albums in your library' }])
  check('...with a library of your own, your count when you have any, else the store\'s', [line(L.artistRow(P), on).place, line(L.artistRow({ ...P, id: 'ar-x' }), { ...on }).place],
    ['2 albums in your library', '3 albums in the store'])
  check('a MusicBrainz artist: matchLine ("as Kanye West · formerly Kanye West · Person · US"), "Artist · " first in Top results',
    [line(L.mbArtistRow(kanye[0])).line, line(L.mbArtistRow(kanye[0]), off, true).line], ['as Kanye West · formerly Kanye West · Person · US', 'Artist · as Kanye West · formerly Kanye West · Person · US'])
  check('a library album: "Portishead · 1994" + "in your library" with logins off (new: no half title says it any more)', [line(L.albumRow(dummy)), line(L.albumRow(dummy), off, true).line],
    [{ line: 'Portishead · 1994', place: 'in your library' }, 'Album · Portishead · 1994'])
  check('a MusicBrainz album: "Portishead · 2008"; a live one says so; a held one ends with where it is held',
    [line(L.groupRow(THIRD)), line(L.groupRow(unfiltered[1])).line, line(L.groupRow(DUMMY)), line(L.groupRow(THIRD), off, true).line],
    [{ line: 'Portishead · 2008', place: '' }, 'Live album · Portishead · 2008', { line: 'Portishead · 1994', place: 'in your library' }, 'Album · Portishead · 2008'])
  check('a library song: "Portishead · Dummy" + place; "Song · " first in Top results', [line(L.songRow(roads)), line(L.songRow(roads), off, true).line],
    [{ line: 'Portishead · Dummy', place: 'in your library' }, 'Song · Portishead · Dummy'])
  check('a MusicBrainz song: step 7\'s line, its held words its place; "Song · Portishead · Dummy" in Top results',
    [line(L.mbSongRow(roadsSongs[0]), { ...off, index: songIndex }), line(L.mbSongRow(roadsSongs[0]), off, true).line], [{ line: 'Portishead · 4:56 · Dummy', place: 'in your library' }, 'Song · Portishead · Dummy'])
  check('a tile\'s third line: "In your library", "On MusicBrainz"; with logins on "In the store", blank while unknown',
    [L.placeLabel(L.albumRow(dummy), off), L.placeLabel(L.groupRow(THIRD), off), L.placeLabel(L.albumRow({ ...dummy, musicBrainzId: 'rel-none' }), { ...on, index: buildOwnedIndex([]) }),
      L.placeLabel(L.albumRow(dummy), { ...on, index: null })],
    ['In your library', 'On MusicBrainz', 'In the store', ''])
  check('the region: "In your library: 1 artist, 2 albums, 11 songs." ("In the store" with logins on); MusicBrainz\'s, or that it isn\'t answering',
    [L.libraryWords({ artists: 1, albums: 2, songs: 11 }, false), L.libraryWords({ albums: 1 }, true), L.libraryWords({}, false),
      L.musicBrainzWords({ artists: 2, albums: 3, songs: 3 }, true), L.musicBrainzWords({}, false)],
    ['In your library: 1 artist, 2 albums, 11 songs.', 'In the store: 1 album.', '', 'From MusicBrainz: 2 artists, 3 albums, 3 songs.', "MusicBrainz isn't answering."])
  check('a fold: "Show 3 albums from MusicBrainz", said "3 albums from MusicBrainz - Show them to see them."', L.foldWords('albums', 3),
    { button: 'Show 3 albums from MusicBrainz', said: '3 albums from MusicBrainz - Show them to see them.' })
  check('an empty late kind, a chip, no results', [L.emptyWords('artists', 'zz'), L.viewWords('albums'), L.viewWords('all'), L.nothingWords('all', 'zz'), L.nothingWords('songs', 'zz')],
    ['No artists on MusicBrainz for “zz”.', 'Showing albums.', 'Showing everything.', 'No results for “zz”', 'No songs for “zz”.'])
  check('a failure: refused says its words; busy and away their own', [L.failureWords({ refused: true, busy: false, unavailable: false, message: "MusicBrainz couldn't read that search - try other words" }),
    L.failureWords({ refused: false, busy: true, unavailable: true, message: 'x' }), L.failureWords({ refused: false, busy: false, unavailable: true, message: 'x' }, true)],
    ["MusicBrainz couldn't read that search - try other words", 'MusicBrainz is busy just now - try again in a moment.', "MusicBrainz isn't answering."])
  check('the library\'s late place: how many, with Show them - or that it found nothing', [L.libraryLateWords({ artists: 1, albums: 2 }, false, 'x').button, L.libraryLateWords({}, true, 'x').line],
    ['3 in your library - Show them', 'Nothing in the store for “x”.'])
}

console.log('\nmore of each rule, one case at a time')
{
  const reading = (text) => searchQuery(text, ['Portishead'])
  const on = { personal: true, index, yourAlbums: new Set(['nd-dummy']), yourArtists: new Map([['ar-p', 1]]) }
  //? tiers, one kind at a time
  check('an album titled the box exactly, free text: 0; a song titled it: 0; an artist starting with it: 2', [
    L.matchTier(L.groupRow({ id: 'g', title: 'Glory Box', 'artist-credit': [] }), 'glory box', reading('glory box')),
    L.matchTier(L.mbSongRow({ key: 'k', title: 'Glory Box', credit: 'X', artists: [], recordings: [], albums: [] }), 'glory box', reading('glory box')),
    L.matchTier(L.artistRow({ id: 'x', name: 'Glory Boxes' }), 'glory box', reading('glory box'))], [0, 0, 2])
  check('album-by-artist: a song by another artist with the title is not exact (the credit rule)', L.matchTier(L.songRow({ ...roads, artist: 'Someone' }), 'roads portishead', reading('roads portishead')), 3)
  check('album-by-artist: a MusicBrainz artist named as the box\'s artist: by the artist (1), not exact', L.matchTier(L.mbArtistRow(portisheadMb[0]), 'roads portishead', reading('roads portishead')), 1)
  check('a song-album relative is read by its own album\'s title and credit', L.matchTier(L.songAlbumRow(roadsSongs[0], roadsSongs[0].albums[0]), 'portishead', reading('portishead')), 1)
  check('...an empty box, every row the rest', L.matchTier(L.artistRow(P), '', reading('x')), 3)
  //? the rank keeps MusicBrainz's order among its own
  const mb = (n) => ({ row: null, key: `k${n}`, kind: 'albums', tier: 1, source: 2, position: n, phantom: false })
  check('MusicBrainz\'s own order kept within a tier (its position)', [mb(2), mb(0), mb(1)].sort(L.rank).map((each) => each.key), ['k0', 'k1', 'k2'])
  check('a phantom (position -Infinity) before every real candidate of its tier and source', [mb(0), L.phantom('albums', reading('portishead'))].sort(L.rank).map((each) => each.key), ['phantom:albums', 'k0'])
  //? the family: search3's album row when it has one; skipped when already picked; the round placeholder for an unknown artist
  const withAlbum = lib([P], [dummy], [roads])
  check('a library song\'s album: search3\'s row when present (its year and cover), its artist search3\'s', L.familyOf(L.songRow(roads), family(withAlbum, [], null)).map((row) => row.type === 'album' ? row.album : row.artist),
    [dummy, P])
  check('...a song with no album or artist id: nothing pulled in', L.familyOf(L.songRow({ id: 's', title: 'X' }), family(lib(), [], null)).length, 0)
  check('...a relative already picked is skipped, never twice', picks(L.topResults([{ row: L.songRow(roads), key: 'song:s-roads', kind: 'songs', tier: 0, source: 0, position: 0, phantom: false },
    { row: L.albumRow(dummy), key: 'album:nd-dummy', kind: 'albums', tier: 0, source: 0, position: 0, phantom: false }], 3, family(withAlbum, [], [P]))), ['album:nd-dummy', 'artist:ar-p', 'song:s-roads'])
  //? n and the rounds
  const many = L.pool({ reading: reading('zz'), library: lib([P, { id: 'a2', name: 'Zz Top' }], [dummy, selfTitled], [roads, glory, sour]), artistList: null, index, marks: off, artists: null, albums: null, songs: null })
  check('round by round over the kinds: an artist, an album and a song each round', picks(L.topResults(L.candidatesOf(many, 'zz', reading('zz')), 6, family(lib(), [], null))).slice(3),
    ['artist:a2', 'album:nd-self', 'song:s-glory'])
  check('...n is the most: three on a phone, six on a desktop', [L.topResults(L.candidatesOf(many, 'zz', reading('zz')), 3, family(lib(), [], null)).length, L.topResults(L.candidatesOf(many, 'zz', reading('zz')), 6, family(lib(), [], null)).length], [3, 6])
  //? decidedTop with nothing out: everything decided, no place
  check('nothing out: every pick decided, no place', [L.decidedTop(L.candidatesOf(many, 'zz', reading('zz')), [], 3, family(lib(), [], null)).prefix.length, L.decidedTop(L.candidatesOf(many, 'zz', reading('zz')), [], 3, family(lib(), [], null)).place], [3, false])
  //? lines with a library of your own, each row type
  check('logins on: a library album yours, the store\'s, not known', [L.rowLine(L.albumRow(dummy), { marks: on }).place, L.rowLine(L.albumRow({ ...dummy, id: 'x', musicBrainzId: 'rel-x' }), { marks: on }).place,
    L.rowLine(L.albumRow({ ...dummy, id: 'x', musicBrainzId: 'rel-x' }), { marks: { ...on, index: null } }).place], ['in your library', 'in the store', ''])
  check('...a song by its album\'s whose: among your albums yours, its album unknown nothing', [L.rowLine(L.songRow(roads), { marks: on }).place, L.rowLine(L.songRow({ ...roads, albumId: 'nd-x' }), { marks: on }).place], ['in your library', ''])
  check('...an artist with none of yours: the store\'s count, true either way', L.rowLine(L.artistRow({ ...P, id: 'other' }), { marks: on }).place, '3 albums in the store')
  check('...an artist before your albums have answered: the store\'s count too', L.rowLine(L.artistRow(P), { marks: { ...on, yourArtists: null } }).place, '3 albums in the store')
  check('...whose is "yours" for every library row with logins off', [L.rowYours(L.albumRow({ ...dummy, musicBrainzId: 'rel-x' }), off), L.rowYours(L.songRow(roads), off), L.rowYours(L.artistRow(P), off)], [true, true, true])
  check('a MusicBrainz album held: its place groupPlace\'s; a tile says "In your library"', [L.rowLine(L.groupRow(DUMMY), { marks: off }).place, L.placeLabel(L.groupRow(DUMMY), off)], ['in your library', 'In your library'])
  check('a song-album relative: its kind first in Top results, its year; Get-able when not held', [L.rowLine(L.songAlbumRow(roadsSongs[0], roadsSongs[0].albums[0]), { marks: { ...off, index: null } }, true)],
    [{ line: 'Album · Portishead · 1994', place: '' }])
  check('a MusicBrainz artist with no facts: "Artist" alone in Top results, nothing in a section', [L.rowLine(L.mbArtistRow(L.creditArtist({ mbid: PORTISHEAD, name: 'Portishead' })), { marks: off }, true).line,
    L.rowLine(L.mbArtistRow(L.creditArtist({ mbid: PORTISHEAD, name: 'Portishead' })), { marks: off }).line], ['Artist', ''])
  check('an EP from MusicBrainz says so in its section line; a plain album doesn\'t', [L.rowLine(L.groupRow(studio[0]), { marks: off }).line, L.rowLine(L.groupRow(THIRD), { marks: off }).line],
    ['EP · Portishead · 2008', 'Portishead · 2008'])
  //? the kinds and keys
  check('every row\'s key the thing it is: an artist\'s and album\'s Navidrome id, a group\'s and an MusicBrainz artist\'s MusicBrainz id, a song-album its group\'s',
    [L.artistRow(P).key, L.albumRow(dummy).key, L.groupRow(THIRD).key, L.mbArtistRow(portisheadMb[0]).key, L.songAlbumRow(roadsSongs[0], roadsSongs[0].albums[0]).key],
    ['artist:ar-p', 'album:nd-dummy', `group:${THIRD.id}`, `mb-artist:${PORTISHEAD}`, `group:${roadsSongs[0].albums[0].id}`])
  check('...and its kind', [L.kindOf(L.mbArtistRow(portisheadMb[0])), L.kindOf(L.songAlbumRow(roadsSongs[0], roadsSongs[0].albums[0])), L.kindOf(L.mbSongRow(roadsSongs[0]))], ['artists', 'albums', 'songs'])
  //? the known artists: the full list and search3's, each once
  check('the artists looked among: getArtists\' and search3\'s together, each once by id', L.knownArtists([P, { id: 'a2', name: 'B' }], [{ ...P, name: 'Portishead (search3)' }, { id: 'a3', name: 'C' }]).map((artist) => artist.id),
    ['ar-p', 'a2', 'a3'])
  check('...search3\'s alone before getArtists has answered', L.knownArtists(null, [P]).map((artist) => artist.id), ['ar-p'])
  //? a late kind's rows capped as a preview
  const late = L.pool({ reading: reading('x'), library: lib(), artistList: null, index, marks: off, artists: null, albums: { groups: studio, shown: studio }, songs: null })
  check('a late kind\'s rows capped as the section\'s preview would be', L.lateRows(late.albums, [0, 3]).length, 3)
  check('the region says nothing of a kind with none', L.countWords({ artists: 0, albums: 2 }), '2 albums')
  check('nothing at all from MusicBrainz said as that', L.musicBrainzWords({}, true), 'Nothing from MusicBrainz.')
  check('the songs\' words for an artist alone; the foot line', [L.SONGS_NEED_A_TITLE, L.TYPE_MORE],
    ["Type a song's title with the artist (“roads portishead”) to find their songs on MusicBrainz.", 'Type a little more, or press Search, to ask MusicBrainz too.'])
}

console.log('\nafter review: an album made of a song\'s fields, a held named album\'s tile, a group held since its answer landed, the library not searched')
{
  const { notInLibrary } = require(path.join(OUT, 'lib/searchResults.js'))
  const on = { personal: true, index, yourAlbums: null, yourArtists: null }
  //? Top results' family for a library song search3 listed without its album: Dummy built from the song's own fields
  const built = L.familyOf(L.songRow(roads), family(lib([], [], [roads])))[0]
  check('(the album built from the song\'s fields: no star, no release id)', [built.key, 'starred' in built.album, 'musicBrainzId' in built.album], ['album:nd-dummy', false, false])
  check('logins on, your albums not in yet, neither search3 nor `ready` holding it: unknown - never "in the store" on a guess',
    [L.rowLine(built, { marks: { ...on, albumOf: () => null } }, true).place, L.placeLabel(built, { ...on, albumOf: () => null })], ['', ''])
  check('...read as `ready` has it once it lands: held by a folder of yours, "in your library"',
    L.rowLine(built, { marks: { ...on, albumOf: (id) => (id === 'nd-dummy' ? dummy : null) } }, true).place, 'in your library')
  check('...a search3 album with no release id is in albumOf itself: its whose as before', [L.albumYours({ id: 'nd-x', name: 'X' }, { ...on, albumOf: (id) => (id === 'nd-x' ? { id: 'nd-x', name: 'X' } : null) }),
    L.albumYours({ id: 'nd-x', name: 'X' }, on)], [false, false])
  //? a MusicBrainz song's named album built from the song (its group not in the albums answer), held with the song
  const songAlbum = L.familyOf(L.mbSongRow(roadsSongs[0]), { library: null, artistList: null, index: songIndex, groups: [] })[0]
  check('(a MusicBrainz song\'s named album built from the song)', [songAlbum.type, songAlbum.album.title], ['song-album', 'Dummy'])
  check('...held with the song: a desktop tile\'s third line says "In your library", as its row\'s place does - never "On MusicBrainz"',
    [L.placeLabel(songAlbum, { ...off, index: songIndex }), L.rowLine(songAlbum, { marks: { ...off, index: songIndex } }, true).place, L.rowYours(songAlbum, { ...off, index: songIndex })],
    ['In your library', 'in your library', true])
  check('...not held: "On MusicBrainz"', L.placeLabel(songAlbum, { ...off, index: buildOwnedIndex([]) }), 'On MusicBrainz')
  //? a group held only since MusicBrainz's answer landed (filed meanwhile, or /library/owned answering late)
  const groups = [THIRD, DUMMY, SELF]
  const shownThen = notInLibrary(groups, index)
  const heldNow = buildOwnedIndex([
    { path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: 'rel-dummy', albumartist_mbids: [PORTISHEAD] },
    { path: 'Portishead/Third', artist: 'Portishead', album: 'Third', release_group_mbid: THIRD.id, release_mbid: 'rel-third', albumartist_mbids: [PORTISHEAD] },
  ])
  const pooled = L.pool({ reading: free('bristol trip'), library: lib(), artistList: null, index: heldNow, marks: { ...off, index: heldNow }, artists: null, albums: { groups, shown: shownThen }, songs: null })
  check('a group held only since MusicBrainz\'s answer landed: kept in MusicBrainz\'s block, marked there - never brought in as well (it was drawn twice)',
    [keys(L.sectionRows(pooled.albums)), keys(L.lateRows(pooled.albums))], [[`group:${DUMMY.id}`, `group:${THIRD.id}`, `group:${SELF.id}`], [`group:${DUMMY.id}`, `group:${THIRD.id}`, `group:${SELF.id}`]])
  check('...and the first answer\'s own nulls: /library/owned still out as it landed, every group MusicBrainz\'s, none twice once it answers',
    keys(L.sectionRows(L.pool({ reading: free('bristol trip'), library: lib(), artistList: null, index: heldNow, marks: { ...off, index: heldNow }, artists: null, albums: { groups, shown: notInLibrary(groups, null) }, songs: null }).albums)),
    [`group:${THIRD.id}`, `group:${DUMMY.id}`, `group:${SELF.id}`])
  check('the library\'s place when Navidrome turned out not reachable: it wasn\'t searched, and says so', [L.librarySkippedWords(false), L.librarySkippedWords(true)],
    ["Your library can't be searched just now.", "The store can't be searched just now."])
}

console.log('\nsearch what\'s saved (2.0.0-player.56): saved rows lead MusicBrainz\'s, ranked between the store\'s and MusicBrainz\'s')
{
  const { notInLibrary } = require(path.join(OUT, 'lib/searchResults.js'))
  const LIVE = { id: '00000000-0000-4000-8000-00000000live', title: 'Roseland NYC Live', 'primary-type': 'Album', 'secondary-types': ['Live'], 'artist-credit': DUMMY['artist-credit'] }
  const OTHERS = { id: '00000000-0000-4000-8000-0000000other', title: 'Welcome to Portishead', 'primary-type': 'Album', 'artist-credit': [{ name: 'Somebody', artist: { id: YE, name: 'Somebody' } }] }
  const savedOf = (groups, matches = [], songs = []) => ({ matches, groups, shown: notInLibrary(groups, index), songs })
  const everything = savedOf([LIVE, THIRD, OTHERS, DUMMY], portisheadMb, roadsSongs)
  const reading = (text) => searchQuery(text, ['Portishead'])
  check('savedFor, free text: everything saved, for every kind asked', ((s) => [s.matches.length, keys(s.groups.map(L.groupRow)), s.songs.length])(L.savedFor(reading('bristol'), everything, L.KINDS, false, index)),
    [1, [`group:${LIVE.id}`, `group:${THIRD.id}`, `group:${OTHERS.id}`, `group:${DUMMY.id}`], roadsSongs.length])
  check('...the artist reading: only albums credited to them - the studio ones under the studio clause - in the studio order an artist\'s albums are read in, and no songs (none asked)',
    [((s) => [keys(s.groups.map(L.groupRow)), keys(s.shown.map(L.groupRow)), s.songs.length, s.matches.length])(L.savedFor(reading('portishead'), everything, ['artists', 'albums'], true, index)),
      keys(L.savedFor(reading('portishead'), everything, ['albums'], false, index).groups.map(L.groupRow))],
    [[[`group:${DUMMY.id}`, `group:${THIRD.id}`], [`group:${THIRD.id}`], 0, 1], [`group:${DUMMY.id}`, `group:${THIRD.id}`, `group:${LIVE.id}`]])
  check('...album-by-artist: no artists (none asked)', L.savedFor(reading('roads portishead'), everything, ['albums', 'songs'], false, index).matches.length, 0)
  //? (after review) the artist reading draws from `credited` - all of theirs saved, not the twelve the words found, which
  //? titles naming them fill first - studio-ordered, MusicBrainz's page of them at most
  const theirs = Array.from({ length: 16 }, (_, n) => ({ id: `00000000-0000-4000-8000-0000000000${String(n).padStart(2, '0')}`, title: `Record ${n}`, 'primary-type': 'Album',
    'first-release-date': String(2015 - n), 'artist-credit': DUMMY['artist-credit'] }))
  const titled = { ...everything, groups: [OTHERS], credited: [LIVE, ...theirs] }
  check('...the artist reading, from `credited`: theirs whatever the words found, earliest first, SAVED_ARTIST_ALBUMS (12) at most - the live one after the studio ones (not drawn at all under the studio clause)',
    [keys(L.savedFor(reading('portishead'), titled, ['albums'], false, index).groups.map(L.groupRow)), L.savedFor(reading('portishead'), titled, ['albums'], true, index).groups.some((group) => group.id === LIVE.id), L.SAVED_ARTIST_ALBUMS],
    [keys(theirs.slice(4).reverse().map(L.groupRow)), false, 12])
  check('...a free reading draws the albums the words found, never `credited`', keys(L.savedFor(reading('bristol'), titled, ['albums'], false, index).groups.map(L.groupRow)), [`group:${OTHERS.id}`])
  //? (after review) what isn't held is worked out as it is DRAWN, from the index then - none drawn before it is in hand
  //? (an album you have, drawn twice: yours, and the saved one among MusicBrainz's)
  check('savedFor: `shown` from the index as drawn - nothing shown while the library\'s index isn\'t in hand; the held left out once it is',
    [keys(L.savedFor(reading('bristol'), everything, L.KINDS, false, null).shown.map(L.groupRow)), keys(L.savedFor(reading('bristol'), everything, L.KINDS, false, index).shown.map(L.groupRow))],
    [[], keys(notInLibrary([LIVE, THIRD, OTHERS, DUMMY], index).map(L.groupRow))])
  const unknown = L.pool({ reading: reading('bristol'), library: lib([], [dummy]), artistList: null, index: null, marks: off, artists: null, albums: null, songs: null,
    saved: L.savedFor(reading('bristol'), everything, L.KINDS, false, null) })
  check('...so the pool draws no saved album before the index: Dummy (yours) once', [keys(L.sectionRows(unknown.albums)).filter((key) => key.includes(DUMMY.id) || key === `album:${dummy.id}`)],
    [[`album:${dummy.id}`]])

  //? (after review) a kind view's rows below its library's: kept where they were drawn as later answers land
  const r = (group, saved = false) => (saved ? L.savedRow(L.groupRow(group)) : L.groupRow(group))
  const drewFirst = L.kindArea(null, [], [r(SELF), r(THIRD)], new Set())
  const late = L.kindArea(drewFirst.area, [r(THIRD, true), r(LIVE, true)], [r(SELF), r(THIRD)], new Set())
  check('kindArea: MusicBrainz\'s rows drawn, then what\'s saved lands - nothing drawn moves or changes: Third stays MusicBrainz\'s row, in its place; the new saved row at the foot',
    [keys(drewFirst.rest), keys(late.lead), keys(late.rest), late.rest.map((row) => row.saved === true)],
    [[`group:${SELF.id}`, `group:${THIRD.id}`], [], [`group:${SELF.id}`, `group:${THIRD.id}`, `group:${LIVE.id}`], [false, false, true]])
  const savedFirst = L.kindArea(null, [r(THIRD, true)], [], new Set())
  const thenAnswer = L.kindArea(savedFirst.area, [r(THIRD, true)], [r(THIRD), r(SELF)], new Set())
  const thenMore = L.kindArea(thenAnswer.area, [r(THIRD, true), r(LIVE, true)], [r(THIRD), r(SELF)], new Set())
  check('...what\'s saved first leads, MusicBrainz\'s answer below it less what\'s saved (by key); anything saved after that goes below too',
    [keys(savedFirst.lead), keys(thenAnswer.lead), keys(thenAnswer.rest), thenAnswer.lead[0].saved === true, keys(thenMore.lead), keys(thenMore.rest)],
    [[`group:${THIRD.id}`], [`group:${THIRD.id}`], [`group:${SELF.id}`], true, [`group:${THIRD.id}`], [`group:${SELF.id}`, `group:${LIVE.id}`]])
  const { foldName } = require(path.join(OUT, 'lib/owned.js'))
  check('foldName folds as src/saved_index.py name_key does (tests/test_saved_search.py, the same names): the route\'s `credited` and savedFor agree on whose an album is',
    ['Björk', 'The Beatles', 'Simon & Garfunkel', 'Sigur Rós (band)', 'AC/DC', 'Guns N\u2019 Roses', '  '].map(foldName), ['bjork', 'beatles', 'simon and garfunkel', 'sigur ros', 'ac dc', 'guns n roses', ''])
  check('...a key the library\'s rows draw above is never drawn below', keys(L.kindArea(null, [r(THIRD, true)], [r(SELF)], new Set([`group:${THIRD.id}`])).lead), [])
  //? (second review) MusicBrainz's failure drawn takes below as its rows do - and keeps it while it is asked again
  const failed = L.kindArea(null, [], [], new Set(), true)
  const askedAgain = L.kindArea(failed.area, [], [], new Set(), false)
  const savedLate = L.kindArea(askedAgain.area, [r(THIRD, true)], [], new Set(), false)
  check('kindArea: a failure drawn, asked again (Try again), then what\'s saved lands - at the foot, below where the failure was, never above it',
    [failed.area.problem, askedAgain.area.problem, keys(savedLate.lead), keys(savedLate.rest)], [true, true, [], [`group:${THIRD.id}`]])
  check('...with no failure drawn, what\'s saved still leads', keys(L.kindArea(L.kindArea(null, [], [], new Set()).area, [r(THIRD, true)], [], new Set()).lead), [`group:${THIRD.id}`])
  check('studioGroup: an Album or EP with no noisy secondary type', [L.studioGroup(THIRD), L.studioGroup(LIVE), L.studioGroup({ id: 'x', 'primary-type': 'Single' }), L.studioGroup({ id: 'x', 'primary-type': 'EP', 'secondary-types': ['Soundtrack'] })],
    [true, false, false, true])

  const saved = savedOf([THIRD, SELF], [], roadsSongs.slice(0, 1))
  const rows = L.pool({ reading: reading('bristol'), library: lib(), artistList: null, index, marks: off, artists: null, albums: { groups: [SELF, LIVE], shown: [SELF, LIVE] }, songs: roadsSongs, saved })
  check('the pool: what\'s saved its own block, marked; MusicBrainz\'s answer less it, by key - Portishead (self-titled) once',
    [keys(rows.albums.saved.map((each) => each.row)), rows.albums.saved.every((each) => each.row.saved === true && each.saved), keys(rows.albums.musicbrainz.map((each) => each.row)), rows.albums.musicbrainz.some((each) => each.row.saved)],
    [[`group:${THIRD.id}`, `group:${SELF.id}`], true, [`group:${LIVE.id}`], false])
  check('...a section: what\'s saved first among MusicBrainz\'s rows, the preview\'s cap taking both', [keys(L.sectionRows(rows.albums)), keys(L.sectionRows(rows.albums, [3, 2]))],
    [[`group:${THIRD.id}`, `group:${SELF.id}`, `group:${LIVE.id}`], [`group:${THIRD.id}`, `group:${SELF.id}`]])
  check('...songs too: MusicBrainz\'s take of a saved song (the same key) left out', [keys(rows.songs.saved.map((each) => each.row)), rows.songs.musicbrainz.some((each) => each.row.key === rows.songs.saved[0].row.key)],
    [[`mb-song:${roadsSongs[0].key}`], false])
  check('a late kind\'s rows: what isn\'t drawn - drawnCounts says how many of each part are', [keys(L.lateRows(rows.albums, [3, 3], new Set([`group:${THIRD.id}`, `group:${SELF.id}`]))), L.drawnCounts(rows.albums, [L.groupRow(THIRD), L.groupRow(SELF)])],
    [[`group:${LIVE.id}`], [0, 2]])
  const sources = L.candidatesOf(rows, 'bristol', reading('bristol'))
  check('candidates: what\'s saved at SOURCE.saved (1.5) - after yours (0) and the store\'s (1), before MusicBrainz\'s (2)',
    [L.SOURCE, sources.find((each) => each.key === `group:${THIRD.id}`).source, sources.find((each) => each.key === `group:${LIVE.id}`).source], [{ yours: 0, store: 1, saved: 1.5, musicbrainz: 2 }, 1.5, 2])
  //? the held album what's saved holds that search3 didn't list: brought in, ranked as what's saved
  const heldSaved = L.pool({ reading: reading('bristol'), library: lib(), artistList: null, index, marks: off, artists: null, albums: null, songs: null, saved: savedOf([DUMMY, THIRD]) })
  check('...a held album only what\'s saved holds: brought into the yours block (no Get), ranked as what\'s saved',
    [keys(heldSaved.albums.brought.map((each) => each.row)), L.candidatesOf(heldSaved, 'bristol', reading('bristol')).find((each) => each.key === `group:${DUMMY.id}`).source],
    [[`group:${DUMMY.id}`], 1.5])
  //? artists: one list for the dedupe - two Nirvanas, one saved and one MusicBrainz's, stay two
  const nirvanas = L.pool({ reading: reading('nirvana'), library: lib(), artistList: [], index, marks: off, artists: nirvana, albums: null, songs: null, saved: savedOf([], nirvana.slice(0, 1)) })
  check('artists: the saved one first, MusicBrainz\'s less it (by id) after - each Nirvana once', [nirvanas.artists.saved.map((each) => each.row.key), nirvanas.artists.musicbrainz.length, nirvanas.artists.musicbrainz.some((each) => each.row.key === `mb-artist:${nirvana[0].mbid}`)],
    [[`mb-artist:${nirvana[0].mbid}`], nirvana.length - 1, false])
  const brought = L.pool({ reading: reading('portishead'), library: lib(), artistList: [P], index, marks: off, artists: portisheadMb, albums: null, songs: null, saved: savedOf([], portisheadMb) })
  check('...the library\'s Portishead (by id) brought in once, from what\'s saved, ranked as saved', [keys(brought.artists.brought.map((each) => each.row)), brought.artists.brought[0].saved, brought.artists.musicbrainz.length],
    [['artist:ar-p'], true, 0])

  //? Top results: a saved song beats MusicBrainz's phantoms at its tier - decided at the library's moment
  const glorySaved = groupSongs(load('songs/roads-portishead').recordings).slice(0, 1)
  const early = L.pool({ reading: reading('roads'), library: lib(), artistList: [P], index: buildOwnedIndex([]), marks: { ...off, index: buildOwnedIndex([]) }, artists: null, albums: null, songs: null, saved: savedOf([], [], glorySaved) })
  const phantoms = L.KINDS.map((kind) => L.phantom(kind, reading('roads')))
  check('"roads", nothing of the library, a saved Roads: Top results decided at the library\'s moment - the song, its album, its artist - no place kept',
    ((d) => [keys(d.prefix), d.place])(L.decidedTop(L.candidatesOf(early, 'roads', reading('roads')), phantoms, 3, { library: lib(), artistList: [P], index: buildOwnedIndex([]), groups: [] })),
    [[`mb-song:${glorySaved[0].key}`, `group:${glorySaved[0].albums[0].id}`, 'artist:ar-p'], false])

  //? a relative made of what's saved is marked saved too - a library artist never
  const savedSong = L.savedRow(L.mbSongRow(glorySaved[0]))
  const relatives = L.familyOf(savedSong, { library: lib(), artistList: [], index: buildOwnedIndex([]), groups: [] })
  const yoursToo = L.familyOf(savedSong, { library: lib(), artistList: [P], index: buildOwnedIndex([]), groups: [] })
  check('Top results\' family of a saved song: its album and its MusicBrainz artist marked saved; the library\'s artist as ever',
    [relatives.map((row) => [row.type, row.saved === true]), yoursToo.map((row) => [row.type, row.saved === true]), L.rowLine(relatives[0], { marks: { ...off, index: buildOwnedIndex([]) } }, true).place],
    [[['song-album', true], ['mb-artist', true]], [['song-album', true], ['artist', false]], 'saved'])
  check('...a saved group in the family\'s groups marks its relative even under a MusicBrainz song', ((row) => [row.type, row.saved === true])(L.familyOf(L.mbSongRow(glorySaved[0]),
    { library: lib(), artistList: [], index: buildOwnedIndex([]), groups: [DUMMY], saved: new Set([DUMMY.id]) })[0]), ['group', true])

  //? the property, with what's saved in hand as the library settles: still sound
  const texts = ['portishead', 'roads', 'glory box', 'dummy', 'third', 'radiohead', 'nirvana', 'kanye west', 'roads portishead', 'portishead third']
  const thirdEye = { id: 'ar-teb', name: 'Third Eye Blind' }
  const libraries = [lib(), lib([P], [dummy], [roads, glory, sour]), lib([], [dummy], [sour]), lib([thirdEye]), lib([P], [selfTitled])]
  const saves = [savedOf([THIRD, LIVE], radiohead.slice(0, 2), roadsSongs.slice(0, 1)), savedOf([DUMMY, SELF], kanye.slice(0, 1), []), savedOf([], nirvana, roadsSongs)]
  const answers = [
    { artists: [], albums: { groups: [], shown: [] }, songs: [] },
    { artists: portisheadMb, albums: { groups: studio, shown: studio }, songs: roadsSongs },
    { artists: nirvana, albums: { groups: unfiltered, shown: unfiltered }, songs: roadsSongs.slice(1) },
    { artists: radiohead, albums: { groups: [SELF], shown: [SELF] }, songs: [] },
  ]
  let held = 0, tried = 0
  for (const text of texts) {
    const read = reading(text)
    const asked = L.KINDS.filter((kind) => L.bestTier(read, kind) !== null)
    for (const library of libraries) {
      for (const each of saves) {
        const kept = L.savedFor(read, each, asked, false, index)
        const early = L.pool({ reading: read, library, artistList: [P], index, marks: off, artists: null, albums: null, songs: null, saved: kept })
        for (const n of [3, 6]) {
          const { prefix } = L.decidedTop(L.candidatesOf(early, text, read), asked.map((kind) => L.phantom(kind, read)), n, family(library, [...kept.groups], [P]))
          for (const answer of answers) {
            tried++
            //? MusicBrainz answers only the kinds it is asked for (the artist reading asks no songs) - as the app asks it
            const real = L.pool({ reading: read, library, artistList: [P], index, marks: off, saved: kept,
              artists: asked.includes('artists') ? answer.artists : null, albums: asked.includes('albums') ? answer.albums : null, songs: asked.includes('songs') ? answer.songs : null })
            const whole = L.topResults(L.candidatesOf(real, text, read), n, family(library, [...kept.groups, ...answer.albums.groups], [P])).map((one) => one.key)
            if (JSON.stringify(whole.slice(0, prefix.length)) === JSON.stringify(keys(prefix))) held++
          }
        }
      }
    }
  }
  check(`the property with what's saved in hand: a decided prefix is the real answers' Top results' prefix, every time (${tried} combinations)`, held, tried)

  //? the words
  const savedThird = L.savedRow(L.groupRow(THIRD))
  const savedDummy = L.savedRow(L.groupRow(DUMMY))
  check('a saved row\'s place says "saved" - unless it says where you hold it; a tile\'s third line "Saved from MusicBrainz"',
    [L.rowLine(savedThird, { marks: off }).place, L.rowLine(savedDummy, { marks: off }).place, L.placeLabel(savedThird, off), L.placeLabel(L.groupRow(THIRD), off), L.rowLine(L.groupRow(THIRD), { marks: off }).place],
    ['saved', 'in your library', 'Saved from MusicBrainz', 'On MusicBrainz', ''])
  check('...its facts MusicBrainz\'s row\'s own', L.rowLine(savedThird, { marks: off }).line, L.rowLine(L.groupRow(THIRD), { marks: off }).line)
  check('the region\'s words: what\'s saved; MusicBrainz\'s as more; away, what is drawn is what\'s saved',
    [L.savedWords({ albums: 1, songs: 2 }), L.musicBrainzWords({ albums: 1 }, true, true), L.musicBrainzWords({}, true, true), L.musicBrainzWords({}, false, true), L.musicBrainzWords({}, true)],
    ['Saved from MusicBrainz: 1 album, 2 songs.', 'More from MusicBrainz: 1 album.', 'Nothing more from MusicBrainz.', "MusicBrainz isn't answering - these are what deadwax has saved.", 'Nothing from MusicBrainz.'])
  const away = { refused: false, busy: false, message: 'x', unavailable: true }
  check('...a failure under what\'s saved: one line, MusicBrainz away and these saved; busy said as busy; a refusal its words',
    [L.savedAwayWords(away), L.savedAwayWords(away, true), L.savedAwayWords({ ...away, busy: true }, true), L.savedAwayWords({ ...away, refused: true, message: 'MusicBrainz couldn\'t read that search - try other words' })],
    ["MusicBrainz isn't answering just now - these are what deadwax has saved from it.", 'Saved - MusicBrainz is away.', 'Saved - MusicBrainz is busy.', 'MusicBrainz couldn\'t read that search - try other words'])
  check('...a late kind adding nothing new under saved rows', L.nothingMoreWords('albums', 'third'), 'No more albums on MusicBrainz for “third”.')
  check('SAVED_WAIT_MS: the library\'s moment waits for what\'s saved at most this long', L.SAVED_WAIT_MS, 400)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
