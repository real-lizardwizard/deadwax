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
 * name; the kind and line of a row; which albums are asked for so a song's tap plays. And (2.0.0-player.50)
 * More from MusicBrainz: a page appended below by the first page's held rule, a group got twice drawn
 * once, and whether another page is there - by MusicBrainz's count, a full page without one, never past
 * the route's bound; what a page brought said in words, a page of repeats or none never "in your library"
 * (review). And (2.0.0-player.55) an artist's line in its two forms, Top results' songs' albums asked first, and what
 * All's Albums asks by the reading (the studio clause for an artist alone, never for Various Artists). And
 * (2.0.0-player.53) the song search's reading of the same box: a title beside an artist you
 * have as that song by them (credited then or called now), falling back to the words typed as one title
 * (review), the words typed otherwise - never a type filter - and nothing at all for an artist's name alone.
 *
 * Run it with:  node ui/test/searchQuery.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/searchQuery.ts', 'src/lib/searchResults.ts', 'src/lib/searchList.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const Q = require(path.join(OUT, 'lib/searchQuery.js'))
const R = require(path.join(OUT, 'lib/searchResults.js'))
const L = require(path.join(OUT, 'lib/searchList.js'))
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
//? the main page's list, as its main.js had it until it retired (2.0.0-player.66): a literal now
check('the list of noisy types, as the main page excluded them', Q.NOISY_SECONDARY_TYPES, ['Live', 'Compilation', 'Interview', 'Demo', 'Remix', 'DJ-mix'])

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
//? (2.0.0-player.55) two forms: a section's (the heading says it is an artist) and Top results' (the kind word first)
check('an artist\'s line in a section: the count alone - nothing when Navidrome counted none', [R.artistLine(2), R.artistLine(1), R.artistLine(0), R.artistLine(undefined)],
  ['2 albums in your library', '1 album in your library', '', ''])
check('...in Top results, "Artist" first - alone when there is no count', [R.artistLine(2, false, true), R.artistLine(1, true, true), R.artistLine(0, false, true)],
  ['Artist · 2 albums in your library', 'Artist · 1 album in the store', 'Artist'])
check('(the top result as an artist alone went: Top results rank every kind - lib/searchList.ts)', R.topArtist, undefined)

console.log('\na song plays within its album, once that album is in hand')
const songs = [
  { id: 's1', albumId: 'a' }, { id: 's2', albumId: 'a' }, { id: 's3', albumId: 'b' }, { id: 's4' },
  { id: 's5', albumId: 'c' }, { id: 's6', albumId: 'd' }, { id: 's7', albumId: 'e' }, { id: 's8', albumId: 'f' },
]
check('the first five DISTINCT albums of the songs found are asked for', R.albumsToPrefetch(songs), ['a', 'b', 'c', 'd', 'e'])
check('...fewer when there are fewer', R.albumsToPrefetch(songs.slice(0, 3)), ['a', 'b'])
check('(2.0.0-player.55) the library songs in Top results\' decided picks first, then the first songs\' - five distinct in all',
  [R.albumsToPrefetch(songs, [{ albumId: 'f' }, { albumId: 'a' }]), R.albumsToPrefetch(songs, [{ albumId: 'z' }, {}])], [['f', 'a', 'b', 'c', 'd'], ['z', 'a', 'b', 'c', 'd']])
check('a song\'s place in its album\'s own answer', [R.songIndex([{ id: 'x' }, { id: 's2' }], 's2'), R.songIndex([{ id: 'x' }], 's9'), R.songIndex(undefined, 's1')], [1, -1, -1])

console.log('\nMore from MusicBrainz (2.0.0-player.50): the next page appended, and whether there is one')
{
  const owned = O.buildOwnedIndex([{ path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: 'g-held' }])
  const first = [{ id: 'g1' }, { id: 'g2' }]
  const page = [{ id: 'g2' }, { id: 'g-held' }, { id: 'g3' }, { id: 'g3' }]
  const appended = R.appendPage(first, first, page, owned)
  check('a page appended below: the groups not already got, the held one left out as the first page leaves it - and counted as held',
    [appended.groups.map((g) => g.id), appended.shown.map((g) => g.id), appended.added, appended.held], [['g1', 'g2', 'g-held', 'g3'], ['g1', 'g2', 'g3'], 1, 1])
  check('...what was drawn kept, in its order and whole - nothing above moves', appended.shown.slice(0, 2), first)
  check('...no library answer yet: nothing left out (it claims nothing)', R.appendPage(first, first, page, null).shown.map((g) => g.id), ['g1', 'g2', 'g-held', 'g3'])
  check('...a page all held: nothing added, the list as it was', [R.appendPage(first, first, [{ id: 'g-held' }], owned).added, R.appendPage(first, first, [{ id: 'g-held' }], owned).shown.length], [0, 2])
  //? (review) a page of repeats, or none, is not a page of albums you have
  const counts = (got) => [got.added, got.held]
  check('...held counts only NEW albums the library holds: none for a page of repeats, an empty page, or repeats with no library answer',
    [counts(R.appendPage(first, first, [{ id: 'g2' }], owned)), counts(R.appendPage(first, first, [], owned)), counts(R.appendPage(first, first, [{ id: 'g1' }], null))],
    [[0, 0], [0, 0], [0, 0]])
  check('...a held album with a repeat beside it: the one held, the repeat not counted', counts(R.appendPage(first, first, [{ id: 'g-held' }, { id: 'g1' }], owned)), [0, 1])
  check('what a page brought, in words: rows only to VoiceOver; every new album held, said by how many; nothing new said as that',
    [R.morePageWords(10, 2), R.morePageWords(1, 0), R.morePageWords(0, 1), R.morePageWords(0, 12), R.morePageWords(0, 0)],
    [{ note: null, said: '10 more albums from MusicBrainz' }, { note: null, said: '1 more album from MusicBrainz' },
      { note: 'The next album MusicBrainz found is in your library already.', said: 'The next album is in your library already' },
      { note: 'The next 12 albums MusicBrainz found are all in your library already.', said: 'The next 12 albums are all in your library already' },
      { note: 'MusicBrainz sent nothing new.', said: 'MusicBrainz sent nothing new' }])
  check('more to ask for by MusicBrainz\'s count; none once every answer is in', [R.morePages(12, 30, 12, 12), R.morePages(24, 30, 12, 12), R.morePages(30, 30, 6, 12)], ['more', 'more', 'end'])
  check('...no count from the server: a full last page may have more, a short one hasn\'t', [R.morePages(12, null, 12, 12), R.morePages(7, null, 7, 12), R.morePages(12, undefined, 12, 12)], ['more', 'end', 'more'])
  check('...a page that brought nothing ends it, whatever the count says', R.morePages(12, 500, 0, 12), 'end')
  check('...past the route\'s bound, "far": narrow the search', [R.morePages(R.MUSICBRAINZ_OFFSET_MAX, 5000, 12, 12), R.morePages(R.MUSICBRAINZ_OFFSET_MAX + 8, 5000, 12, 12)], ['more', 'far'])
  check('...the bound the route\'s own (FULLY_SEARCH_OFFSET_MAX)', R.MUSICBRAINZ_OFFSET_MAX, 1000)
}

console.log('\nthe song search (2.0.0-player.53): the box read as the album half reads it')
{
  const artists = ['Portishead', 'Pink Floyd', 'Ye']
  const song = (text) => Q.songSearchQuery(text, Q.searchQuery(text, artists))
  check('a title beside an artist you have: that song by them, credited then or called now',
    [song('roads portishead'), song('Portishead - Roads')], ['recording:"roads" AND (artist:"Portishead" OR artistname:"Portishead")', 'recording:"Roads" AND (artist:"Portishead" OR artistname:"Portishead")'])
  check('...the longest name, as the albums read it', song('pink floyd money'), 'recording:"money" AND (artist:"Pink Floyd" OR artistname:"Pink Floyd")')
  check('...its quotes and backslashes escaped', Q.fieldedSongQuery('Say "Hi" \\o/', 'Ye'), 'recording:"Say \\"Hi\\" \\\\o/" AND (artist:"Ye" OR artistname:"Ye")')
  check('anything else: the words typed, spaces closed up', song('  hey   jude '), 'hey jude')
  check('...never with a type filter - that is about albums', Q.songSearchQuery('hey jude', Q.searchQuery('hey jude', artists, Q.typeFilter({ primary: ['Album'] }))), 'hey jude')
  check('an artist\'s name alone: nothing asked', [song('portishead'), song('PINK FLOYD')], [null, null])
  check('...nor for nothing typed', [Q.songSearchQuery('', null), Q.songSearchQuery('   ', Q.searchQuery('   ', artists))], [null, null])
  //? (review) what a title beside an artist falls back to, finding no song by them: the words typed as ONE title -
  //? never loose, which matched strangers' songs titled after the artist ("Tame Impala") above an album's words
  check('the fallback: the words typed as one title, spaces closed up, quotes escaped; nothing for nothing',
    [Q.songTitleQuery('  the slow rush   tame impala '), Q.songTitleQuery('prince charming'), Q.songTitleQuery('Say "Hi"'), Q.songTitleQuery('   ')],
    ['recording:"the slow rush tame impala"', 'recording:"prince charming"', 'recording:"Say \\"Hi\\""', null])
}

console.log('\nwhat All\'s Albums asks, by the reading (2.0.0-player.55, lib/searchList.ts allAlbumsQuery)')
{
  const artists = ['Portishead']
  const studio = '(artist:"Portishead") AND (primarytype:"Album" OR primarytype:"EP") AND -secondarytype:"Live" AND -secondarytype:"Compilation" AND -secondarytype:"Interview" AND -secondarytype:"Demo" AND -secondarytype:"Remix" AND -secondarytype:"DJ-mix"'
  check('an artist you have alone: their studio albums and EPs - the query bracketed before the clauses are ANDed on', L.allAlbumsQuery(Q.searchQuery('portishead', artists)), { query: studio, studio: true })
  check('...Various Artists ("va", "various artists"): today\'s query, unfiltered - its records are compilations by nature',
    [L.allAlbumsQuery(Q.searchQuery('va', artists)), L.allAlbumsQuery(Q.searchQuery('various artists', artists))],
    [{ query: 'artist:"Various Artists"', studio: false }, { query: 'artist:"Various Artists"', studio: false }])
  check('...a title by an artist you have: fielded, as read', L.allAlbumsQuery(Q.searchQuery('portishead third', artists)),
    { query: 'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")', studio: false })
  check('...free text: the words', L.allAlbumsQuery(Q.searchQuery('dark side of the moon', artists)), { query: 'dark side of the moon', studio: false })
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
