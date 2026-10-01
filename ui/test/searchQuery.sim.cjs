/**
 * The app's one search box (2.0.0-player.13): how it is read as a MusicBrainz query
 * (ui/src/lib/searchQuery.ts), and what the Search tab draws of the two answers
 * (ui/src/lib/searchResults.ts).
 *
 * The cases a wrong answer would hide: an artist you have at either end of the box, read as the
 * album by them; the longest name winning; an artist alone; anything else left as typed; `va`; a
 * dash between artist and title; and the query ALWAYS in brackets before a type filter is ANDed on
 * - without them `AND` binds to the last word of free text alone (CLAUDE.md's type filter decision).
 * Then the halves: a held album left out of "Not in your library yet" by its group id, never by a
 * name; the kind and line of a row; which albums are asked for so a song's tap plays.
 *
 * Run it with:  node ui/test/searchQuery.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchQuery.ts', 'src/lib/searchResults.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const Q = require(path.join(OUT, 'lib/searchQuery.js'))
const R = require(path.join(OUT, 'lib/searchResults.js'))
const O = require(path.join(OUT, 'lib/owned.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

//? the library's artists, as /library/owned names them
const ARTISTS = ['Portishead', 'Pink Floyd', 'Pink', 'Tame Impala', 'The Beatles', 'JAŸ‐Z', 'Motörhead']
const read = (text, filter = '') => {
  const plan = Q.searchQuery(text, ARTISTS, filter)
  return plan && [plan.kind, plan.query]
}

console.log('an artist you have, at either end, and the album by them')
check('at the start', read('portishead third'),
  ['album-by-artist', 'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")'])
check('at the end', read('third portishead'),
  ['album-by-artist', 'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")'])
check('the longest name that fits: Pink Floyd, not Pink', read('pink floyd the wall'),
  ['album-by-artist', 'releasegroup:"the wall" AND (artist:"Pink Floyd" OR artistname:"Pink Floyd")'])
check('...at the end too', read('the wall pink floyd'),
  ['album-by-artist', 'releasegroup:"the wall" AND (artist:"Pink Floyd" OR artistname:"Pink Floyd")'])
check('a shorter name still fits where the longer one does not', read('pink missundaztood'),
  ['album-by-artist', 'releasegroup:"missundaztood" AND (artist:"Pink" OR artistname:"Pink")'])
check('the title keeps what was typed, word for word', Q.searchQuery('Tame Impala  The Slow  Rush', ARTISTS).title, 'The Slow Rush')
check('the artist in the library\'s spelling', Q.searchQuery('tame impala currents', ARTISTS).artist, 'Tame Impala')
check('a name typed without its "The", accents or the proper dash', [read('beatles abbey road')[1], read('motorhead ace of spades')[1], read('jay-z the blueprint')[1]], [
  'releasegroup:"abbey road" AND (artist:"The Beatles" OR artistname:"The Beatles")',
  'releasegroup:"ace of spades" AND (artist:"Motörhead" OR artistname:"Motörhead")',
  'releasegroup:"the blueprint" AND (artist:"JAŸ‐Z" OR artistname:"JAŸ‐Z")',
])
check('a dash, a colon or a slash between them is dropped', [read('portishead - third')[1], read('portishead: dummy')[1], read('third / portishead')[1]], [
  'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")',
  //? "portishead:" folds to the name, as every name is compared
  'releasegroup:"dummy" AND (artist:"Portishead" OR artistname:"Portishead")',
  'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")',
])
check('...and a name with only a dash after it is the artist alone', read('portishead -'), ['artist', 'artist:"Portishead"'])
check('a stray dash at either end of the title is dropped', [read('portishead third -')[1], read('- third portishead')[1]], [
  'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")',
  'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")',
])

console.log('\nan artist alone')
check('is artist:"A"', read('portishead'), ['artist', 'artist:"Portishead"'])
check('...whatever its case or accents', read('MOTORHEAD'), ['artist', 'artist:"Motörhead"'])
check('...the two-word one too', read('pink floyd'), ['artist', 'artist:"Pink Floyd"'])

console.log('\nva')
check('alone, it is Various Artists', read('va'), ['artist', 'artist:"Various Artists"'])
check('at the start, the album by Various Artists', read('VA Now That\'s What I Call Music'),
  ['album-by-artist', 'releasegroup:"Now That\'s What I Call Music" AND (artist:"Various Artists" OR artistname:"Various Artists")'])
check('at the end too', read('pure moods va')[1],
  'releasegroup:"pure moods" AND (artist:"Various Artists" OR artistname:"Various Artists")')
check('"various artists" typed in full', read('various artists'), ['artist', 'artist:"Various Artists"'])
check('...but va inside a title is just a word', read('viva la vida'), ['free', 'viva la vida'])

console.log('\nanything else, as typed')
check('free text', read('dark side of the moon'), ['free', 'dark side of the moon'])
check('spaces tidied, nothing else touched', read('  S&M2   AC/DC  '), ['free', 'S&M2 AC/DC'])
check('an artist you DON\'T have is free text', read('radiohead ok computer'), ['free', 'radiohead ok computer'])
check('nothing at all is no search', [Q.searchQuery('', ARTISTS), Q.searchQuery('   ', ARTISTS)], [null, null])
check('quotes in a title are escaped, not ended', read('portishead "roads" live')[1],
  'releasegroup:"\\"roads\\" live" AND (artist:"Portishead" OR artistname:"Portishead")')
check('...and a backslash', Q.quoteTerm('a\\b'), '"a\\\\b"')

console.log('\nthe type filter: the query in brackets first, ALWAYS')
const studio = Q.typeFilter({ studioOnly: true })
check('studio only excludes the noisy types by name', studio,
  '-secondarytype:"Live" AND -secondarytype:"Compilation" AND -secondarytype:"Interview" AND -secondarytype:"Demo" AND -secondarytype:"Remix" AND -secondarytype:"DJ-mix"')
check('free text is bracketed, so AND binds to all of it', read('dark side of the moon', 'primarytype:"Album"')[1],
  '(dark side of the moon) AND primarytype:"Album"')
check('a fielded query too', read('portishead third', 'primarytype:"Album"')[1],
  '(releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")) AND primarytype:"Album"')
check('an artist alone too', read('portishead', studio)[1], `(artist:"Portishead") AND ${studio}`)
check('several primary types OR together in their own brackets', Q.typeFilter({ primary: ['Album', 'EP'] }), '(primarytype:"Album" OR primarytype:"EP")')
check('no filter, no brackets', [Q.typeFilter({}), Q.withTypeFilter('dummy', '')], ['', 'dummy'])
check('the main page\'s list of noisy types', Q.NOISY_SECONDARY_TYPES, ['Live', 'Compilation', 'Interview', 'Demo', 'Remix', 'DJ-mix'])
const mainJs = fs.readFileSync(path.resolve(__dirname, '../../interface/scripts/main.js'), 'utf8')
check('...is the one main.js excludes', /const NOISY_SECONDARY_TYPES = \['Live', 'Compilation', 'Interview', 'Demo', 'Remix', 'DJ-mix'\];/.test(mainJs), true)

console.log('\npacing')
check('MusicBrainz waits for three characters before asking unasked', ['ab', ' ab ', 'abc'].map(Q.asksMusicBrainzBySettling), [false, false, true])
check('the two halves\' pauses: 200ms for the library, 700ms for MusicBrainz', [Q.LIBRARY_SETTLE_MS, Q.MUSICBRAINZ_SETTLE_MS, Q.MUSICBRAINZ_MIN_CHARS], [200, 700, 3])

console.log('\nthe MusicBrainz half: held albums left out, by group id only')
const owned = O.buildOwnedIndex([
  { path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_mbid: 'r1', release_group_mbid: 'dummy' },
  { path: 'Old Rips/Portishead - Third', artist: 'Portishead', album: 'Third', release_mbid: '', release_group_mbid: '' },
])
const groups = [
  { id: 'third', title: 'Third', 'primary-type': 'Album', 'first-release-date': '2008-04-08', 'artist-credit': [{ name: 'Portishead', artist: { name: 'Portishead' } }] },
  { id: 'dummy', title: 'Dummy', 'primary-type': 'Album', 'first-release-date': '1994-08-22' },
  { id: 'roseland', title: 'Roseland NYC Live', 'primary-type': 'Album', 'secondary-types': ['Live'], 'first-release-date': '1998-11-02' },
]
check('a held Dummy is left out; an untagged "Third" folder is only a maybe, so Third stays', R.notInLibrary(groups, owned).map((g) => g.id), ['third', 'roseland'])
check('...in MusicBrainz\'s order', R.notInLibrary([...groups].reverse(), owned).map((g) => g.id), ['roseland', 'third'])
check('no library answer yet: nothing left out', R.notInLibrary(groups, null).length, 3)

console.log('\nthe rows')
check('kind', groups.map(R.groupKind), ['Album', 'Album', 'Live album'])
check('...an EP, a compilation, a soundtrack, nothing at all', [
  R.groupKind({ 'primary-type': 'EP' }), R.groupKind({ 'primary-type': 'Album', 'secondary-types': ['Compilation'] }),
  R.groupKind({ 'primary-type': 'Album', 'secondary-types': ['Soundtrack', 'Live'] }), R.groupKind({}),
], ['EP', 'Compilation', 'Soundtrack', 'Release'])
check('line: kind, artist, year', R.groupLine(groups[0]), 'Album · Portishead · 2008')
check('...what MusicBrainz doesn\'t say is left out', [R.groupLine({ id: 'x', 'primary-type': 'Single' }), R.groupYear({ 'first-release-date': '' })], ['Single', null])
check('an artist\'s line', [R.artistLine(2), R.artistLine(1), R.artistLine(0), R.artistLine(undefined)],
  ['Artist · 2 albums in your library', 'Artist · 1 album in your library', 'Artist', 'Artist'])
check('the top result is an artist whose name IS what was typed', [
  R.topArtist([{ name: 'Portishead' }, { name: 'Portishead Tribute' }], 'portishead')?.name,
  R.topArtist([{ name: 'The Beatles' }], 'beatles')?.name,
  R.topArtist([{ name: 'Portishead' }], 'portishead third'),
  R.topArtist([{ name: 'Portishead' }], ''),
], ['Portishead', 'The Beatles', null, null])

console.log('\na song plays within its album, once that album is in hand')
const songs = [
  { id: 's1', albumId: 'a' }, { id: 's2', albumId: 'a' }, { id: 's3', albumId: 'b' }, { id: 's4' },
  { id: 's5', albumId: 'c' }, { id: 's6', albumId: 'd' }, { id: 's7', albumId: 'e' }, { id: 's8', albumId: 'f' },
]
check('the first five DISTINCT albums of the songs found are asked for', R.albumsToPrefetch(songs), ['a', 'b', 'c', 'd', 'e'])
check('...fewer when there are fewer', R.albumsToPrefetch(songs.slice(0, 3)), ['a', 'b'])
check('a song\'s place in its album\'s own answer', [R.songIndex([{ id: 'x' }, { id: 's2' }], 's2'), R.songIndex([{ id: 'x' }], 's9'), R.songIndex(undefined, 's1')], [1, -1, -1])

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
