/**
 * The Library's shelves (2.0.0-player.59, a better Library) - lib/shelves.ts, pure, pinned:
 *
 *  - THE SEVEN ALBUM SORTS on a fixture with the awkward names ("The Beatles" and "Beatles Tribute", "Björk", "&",
 *    digit-led "10cc" and "2Pac", a non-Latin name, an empty artist), undated and 0-year albums, unplayed ones, ties
 *    (Navidrome's order kept) and a `created` that won't parse: the `#` group last, Artist each artist's albums oldest
 *    first, Recently played and Most played leaving out the unplayed;
 *  - the headers' labels: letters, years with "No year" last, months with "Date unknown" last, none for the played
 *    sorts; the artists' two orders and their headers;
 *  - the index: all 27 entries for the letters, one with no group pointing at the next (or the last), the decades in
 *    the sort's direction, none under 50 items or while Find narrows; fitIndex thinning at 13 slots, the finger's
 *    entry the drawn slot under it - every drawn letter landing on itself at every slot count, a dot's letters reached
 *    by a drag across it;
 *  - Find: words in any order, accents and case folded, on the title or the artist, the bracketed edition and a "The"
 *    findable; the count's and the no-match words exactly;
 *  - blocks of 0, 1, 60, 61 and 3,000 items - the head only on a labelled group's first block, a headerless sort one
 *    unlabelled group cut the same way - and which of them a new list draws before the page says what is near the
 *    view (blocksNear);
 *  - keys made once per album: foldName counted through a stand-in, at most 2 x 3,000 calls for a sort and its groups;
 *  - a sort read from storage: the four old ids kept, anything else the default (Artist); the artists' order likewise;
 *  - (2.0.11) Recently added over YOUR albums by when you added each (`starred`), the stars SAME_MOMENT_MS apart one
 *    moment in the collection's order then the star's (the first admin's seed), its month headers the moment's - the whole
 *    list's, whatever Find leaves; the collection's by
 *    `created` even where some albums carry a star.
 *
 * Run it with:  node ui/test/shelves.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-shelves-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/shelves.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck',
  '--moduleResolution', 'node', '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

const owned = require(path.join(OUT, 'lib/owned.js'))
const S = require(path.join(OUT, 'lib/shelves.js'))

let failures = 0
function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}: ${JSON.stringify(actual)}${ok ? '' : `  (expected ${JSON.stringify(expected)})`}`)
}

//? a fresh copy each time, so the per-album keys (a WeakMap by object) are made anew where a test counts them
const ALBUMS = () => [
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
]
const ids = (list) => list.map((album) => album.id)

console.log('\nthe seven album sorts')
{
  const albums = ALBUMS()
  const sorted = (sort) => ids(S.sortAlbums(albums, sort))
  check('the sorts offered, in the select\'s order, the four old ids kept',
    S.ALBUM_SORTS.map((sort) => [sort.id, sort.label]),
    [['alphabeticalByArtist', 'Artist'], ['alphabeticalByName', 'Title'], ['newest', 'Recently added'], ['byYearDesc', 'Year, newest first'],
      ['byYearAsc', 'Year, oldest first'], ['recent', 'Recently played'], ['frequent', 'Most played']])
  check('Artist: folded ("The Beatles" as Beatles, Björk as bjork), each artist oldest first, a tie in Navidrome\'s order, `#` last (no name first in it)',
    sorted('alphabeticalByArtist'), ['help', 'abbey', 'tribute', 'debut', 'debut2', 'post', 'simon', 'nobody', 'cc', 'pac', 'sakamoto'])
  check('Title: by the title folded, then the artist - digits and "async"\'s lower case as letters are, `#` last',
    sorted('alphabeticalByName'), ['abbey', 'sakamoto', 'simon', 'debut', 'debut2', 'help', 'pac', 'post', 'cc', 'tribute', 'nobody'])
  check('Recently added: newest first, the undated (and the unreadable, and a float) last in Navidrome\'s order',
    sorted('newest'), ['pac', 'post', 'tribute', 'simon', 'help', 'abbey', 'cc', 'debut', 'sakamoto', 'nobody', 'debut2'])
  check('Year, newest first: no year (and 0) last, a year\'s albums by artist then title',
    sorted('byYearDesc'), ['sakamoto', 'tribute', 'nobody', 'debut', 'debut2', 'cc', 'abbey', 'simon', 'help', 'post', 'pac'])
  check('Year, oldest first: no year last still', sorted('byYearAsc'), ['help', 'simon', 'abbey', 'cc', 'debut', 'debut2', 'nobody', 'tribute', 'sakamoto', 'post', 'pac'])
  check('Recently played: only the played, latest first', sorted('recent'), ['tribute', 'cc', 'abbey'])
  check('Most played: only with a play count, most first, a tie by latest played', sorted('frequent'), ['cc', 'abbey', 'tribute'])
  check('nothing left out or doubled by the others, and the list handed in untouched',
    [sorted('alphabeticalByArtist').length, sorted('newest').length, ids(albums)[0]], [11, 11, 'abbey'])
}

console.log('\nthe headers each sort groups by')
{
  const albums = ALBUMS()
  const heads = (sort) => S.groupAlbums(S.sortAlbums(albums, sort), sort).map((group) => [group.label, group.items.length])
  check('Artist: the artist\'s first letter, `#` last', heads('alphabeticalByArtist'), [['B', 6], ['S', 1], ['#', 4]])
  check('Title: the title\'s', heads('alphabeticalByName'), [['A', 2], ['B', 1], ['D', 2], ['H', 1], ['M', 1], ['P', 1], ['S', 1], ['T', 1], ['U', 1]])
  check('Recently added: the month added in English, "Date unknown" last', heads('newest'),
    [['October 2026', 5], ['September 2026', 1], ['August 2026', 1], ['Date unknown', 4]])
  check('Year: the year, "No year" last', heads('byYearDesc'),
    [['2017', 1], ['2001', 1], ['1999', 1], ['1993', 2], ['1974', 1], ['1969', 1], ['1968', 1], ['1965', 1], ['No year', 2]])
  check('the played sorts: one running list, no header', [heads('recent'), heads('frequent')], [[[null, 3]], [[null, 3]]])
  check('no albums, no groups', S.groupAlbums([], 'alphabeticalByArtist'), [])
  check('a month from UTC, never the device\'s zone or language', [S.monthLabel('2026-10-31T23:30:00-05:00'), S.monthLabel('2026-01-01T00:00:00Z'), S.monthLabel(''), S.monthLabel(undefined), S.monthLabel(1729000000.5)],
    ['November 2026', 'January 2026', 'Date unknown', 'Date unknown', 'Date unknown'])
  check('initials: a-z a capital, anything else `#`', ['beatles', 'zz', '10cc', '', 'ß', '坂本'].map(S.initialOf), ['B', 'Z', '#', '#', '#', '#'])
}

console.log('\nRecently added over YOUR albums: when you added each (2.0.11)')
{
  //? James (2026-10-24): "Recently added should be for the user's library, not deadwax's" - your list (Navidrome's
  //? `starred`, its own order starred-first) ordered by the star; the collection's by `created`, stars or none
  const yours = [
    { id: 'late', name: 'Old in the collection, new to you', artist: 'a', starred: '2026-10-20T10:00:00Z', created: '2024-01-01T00:00:00Z' },
    { id: 'tA', name: 'Starred together A', artist: 'a', starred: '2026-10-10T00:00:00Z', created: '2026-03-01T00:00:00Z' },
    { id: 'tB', name: 'Starred together B', artist: 'a', starred: '2026-10-10T00:00:00Z', created: '2026-05-01T00:00:00Z' },
    { id: 'amperfy', name: 'Starred in Amperfy', artist: 'a', starred: '2026-10-05T09:00:00Z', created: '2026-10-04T00:00:00Z' },
    { id: 'noStar', name: 'No star (never in your list)', artist: 'a', created: '2026-09-15T00:00:00Z' },
    { id: 'far', name: 'A minute after the seed', artist: 'a', starred: '2026-09-01T12:01:00Z', created: '2020-01-01T00:00:00Z' },
    //? the first admin's seed: starred one after another, seconds apart - 38 s end to end, no gap over SAME_MOMENT_MS
    { id: 's3', name: 'Seed 3', artist: 'a', starred: '2026-09-01T12:00:03Z', created: '2026-08-15T00:00:00Z' },
    { id: 's4', name: 'Seed 4', artist: 'a', starred: '2026-09-01T12:00:03.000Z' },
    { id: 's2', name: 'Seed 2', artist: 'a', starred: '2026-09-01T11:59:50Z', created: '2026-06-01T00:00:00Z' },
    { id: 's1', name: 'Seed 1', artist: 'a', starred: '2026-09-01T11:59:25Z', created: '2026-08-01T00:00:00Z' },
    { id: 'none', name: 'No date at all', artist: 'a' },
  ]
  check('the seed\'s window: thirty seconds between one star and the next', S.SAME_MOMENT_MS, 30000)
  check('yours: by when it entered your library (its star) - an album the collection has had for years first when you just added it; a moment (a seed, stars together) in the collection\'s order; no date last',
    ids(S.sortAlbums(yours, 'newest', 'you')), ['late', 'tB', 'tA', 'amperfy', 'noStar', 'far', 's3', 's1', 's2', 's4', 'none'])
  check('...the same list as the collection\'s: by created, the stars passed over', ids(S.sortAlbums(yours, 'newest')),
    ['amperfy', 'noStar', 's3', 's1', 's2', 'tB', 'tA', 'late', 'far', 's4', 'none'])
  check('...and the other sorts don\'t care whose list it is', ['alphabeticalByArtist', 'alphabeticalByName', 'byYearDesc'].map((sort) => ids(S.sortAlbums(yours, sort, 'you')).join() === ids(S.sortAlbums(yours, sort)).join()),
    [true, true, true])
  check('...nothing left out or doubled, the list handed in untouched', [S.sortAlbums(yours, 'newest', 'you').length, ids(yours)[0]], [11, 'late'])
  const heads = S.groupAlbums(S.sortAlbums(yours, 'newest', 'you'), 'newest', 'you').map((group) => [group.label, group.items.length])
  check('...its month headers the month you added it ("Date unknown" last)', heads, [['October 2026', 4], ['September 2026', 6], ['Date unknown', 1]])
  //? a moment over midnight at a month's end: headed by its newest star, never split - the album created first leading
  const over = [
    { id: 'm2', name: 'm2', artist: 'a', starred: '2026-09-01T00:00:05Z', created: '2025-01-01T00:00:00Z' },
    { id: 'm1', name: 'm1', artist: 'a', starred: '2026-08-31T23:59:50Z', created: '2026-01-01T00:00:00Z' },
    { id: 'aug', name: 'aug', artist: 'a', starred: '2026-08-20T00:00:00Z', created: '2026-01-02T00:00:00Z' },
  ]
  check('...one moment across a month\'s end under one header, its newest star\'s month',
    S.groupAlbums(S.sortAlbums(over, 'newest', 'you'), 'newest', 'you').map((group) => [group.label, group.items.map((album) => album.id)]),
    [['September 2026', ['m1', 'm2']], ['August 2026', ['aug']]])
  //? (review) Find narrowing that moment: its headers from the WHOLE list's moments - taking an album out of a run of
  //? stars widens its gaps, and a moment cut again from what Find left would split over the month's end, out of order
  const seed = [
    { id: 'a', name: 'Alpha', artist: 'x', starred: '2026-09-01T00:00:10Z', created: '2025-01-01T00:00:00Z' },
    { id: 'b', name: 'Beta', artist: 'x', starred: '2026-08-31T23:59:50Z', created: '2026-03-01T00:00:00Z' },
    { id: 'c', name: 'Gamma', artist: 'x', starred: '2026-08-31T23:59:30Z', created: '2026-06-01T00:00:00Z' },
    { id: 'd', name: 'Delta', artist: 'x', starred: '2026-08-20T00:00:00Z', created: '2026-01-02T00:00:00Z' },
  ]
  const seedSorted = S.sortAlbums(seed, 'newest', 'you')
  const seedFound = seedSorted.filter((album) => album.id !== 'b')
  check('...Find leaving out its middle album: still one header, the whole list\'s month, the album under the same header as unfound',
    [S.groupAlbums(seedFound, 'newest', 'you', seedSorted).map((group) => [group.label, group.items.map((album) => album.id)]),
      S.groupAlbums(seedSorted, 'newest', 'you').map((group) => [group.label, group.items.map((album) => album.id)])],
    [[['September 2026', ['c', 'a']], ['August 2026', ['d']]], [['September 2026', ['c', 'b', 'a']], ['August 2026', ['d']]]])
  //? (review) inside a moment, `created` the same (or missing on both): the newer star first, whatever order they came in
  const tied = [
    { id: 'older', name: 'older', artist: 'a', starred: '2026-09-01T12:00:00Z', created: '2026-01-01T00:00:00Z' },
    { id: 'newer', name: 'newer', artist: 'a', starred: '2026-09-01T12:00:05Z', created: '2026-01-01T00:00:00Z' },
    { id: 'olderBare', name: 'olderBare', artist: 'a', starred: '2026-09-01T11:59:50Z' },
    { id: 'newerBare', name: 'newerBare', artist: 'a', starred: '2026-09-01T11:59:55Z' },
  ]
  check('...inside a moment, the same created (or none): then the star, newest first, not the order handed in',
    ids(S.sortAlbums(tied, 'newest', 'you')), ['newer', 'older', 'newerBare', 'olderBare'])
  //? the store's list: a few albums carry `starred` (the asker's) - never the order
  const store = [
    { id: 'c1', name: 'c1', artist: 'a', created: '2026-10-01T00:00:00Z', starred: '2026-10-20T00:00:00Z' },
    { id: 'c2', name: 'c2', artist: 'a', created: '2026-10-10T00:00:00Z' },
    { id: 'c3', name: 'c3', artist: 'a', created: '2026-09-01T00:00:00Z', starred: '2026-10-22T00:00:00Z' },
  ]
  check('the collection\'s list: by created even where some albums carry your star (the default, and said)',
    [ids(S.sortAlbums(store, 'newest')), ids(S.sortAlbums(store, 'newest', 'collection'))], [['c2', 'c1', 'c3'], ['c2', 'c1', 'c3']])
  check('...its month headers by created too', S.groupAlbums(S.sortAlbums(store, 'newest', 'collection'), 'newest', 'collection').map((group) => [group.label, group.items.length]),
    [['October 2026', 2], ['September 2026', 1]])
  check('...which as yours would have read the stars', ids(S.sortAlbums(store, 'newest', 'you')), ['c3', 'c1', 'c2'])
}

console.log('\nthe artists\' two orders')
{
  const artists = [{ id: 'm', name: 'Massive Attack', albumCount: 2 }, { id: 't', name: 'The Beatles', albumCount: 3 }, { id: 'n', name: '10cc', albumCount: 3 },
    { id: 'l', name: 'La Dispute', albumCount: 1 }, { id: 'b', name: 'Björk' }]
  check('Name: folded ("The" set aside, "La" kept - under L here, D in Navidrome), `#` last', S.sortArtistsBy(artists, 'name').map((a) => a.name),
    ['The Beatles', 'Björk', 'La Dispute', 'Massive Attack', '10cc'])
  check('...its letter headers', S.groupArtists(S.sortArtistsBy(artists, 'name'), 'name').map((group) => [group.label, group.items.length]), [['B', 2], ['L', 1], ['M', 1], ['#', 1]])
  check('Most albums: most first, a tie in the order handed in, none counted last - one running list',
    [S.sortArtistsBy(artists, 'albums').map((a) => a.id), S.groupArtists(S.sortArtistsBy(artists, 'albums'), 'albums').map((group) => group.label)],
    [['t', 'n', 'm', 'l', 'b'], [null]])
  check('read from storage: Most albums only when it says so', ['albums', 'name', null, 'Albums', 'x'].map(S.artistOrderFrom), ['albums', 'name', 'name', 'name', 'name'])
}

console.log('\nthe index down the right edge')
{
  const albums = ALBUMS()
  const byArtist = S.groupAlbums(S.sortAlbums(albums, 'alphabeticalByArtist'), 'alphabeticalByArtist')
  const letters = S.indexEntries(byArtist, 'alphabeticalByArtist')
  check('letters: all 27, A-Z then #', [letters.length, letters.map((entry) => entry.label).join('')], [27, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'])
  check('...each to its own group, a letter with none to the next group after it, past the last group the last',
    letters.map((entry) => entry.group).join(','), '0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2')
  check('...said where they go', [letters[0].aria, letters[26].aria], ['Jump to A', 'Jump to numbers and symbols'])
  const onlyZ = [{ key: 'Z', label: 'Z', items: [1] }]
  check('a list all under Z: every letter to it, # too (the last)', S.indexEntries(onlyZ, 'name').map((entry) => entry.group), Array(27).fill(0))
  const years = S.groupAlbums(S.sortAlbums(albums, 'byYearDesc'), 'byYearDesc')
  check('Year, newest first: one entry per decade present, in that direction, no entry for No year',
    S.indexEntries(years, 'byYearDesc').map((entry) => [entry.label, entry.aria, entry.group]),
    [['2010', 'Jump to the 2010s', 0], ['2000', 'Jump to the 2000s', 1], ['1990', 'Jump to the 1990s', 2], ['1970', 'Jump to the 1970s', 4], ['1960', 'Jump to the 1960s', 5]])
  const up = S.groupAlbums(S.sortAlbums(albums, 'byYearAsc'), 'byYearAsc')
  check('...oldest first, the other way', S.indexEntries(up, 'byYearAsc').map((entry) => entry.label), ['1960', '1970', '1990', '2000', '2010'])
  check('no index for Recently added, the played sorts, Most albums', ['newest', 'recent', 'frequent', 'albums'].map((sort) => S.indexEntries(byArtist, sort).length), [0, 0, 0, 0])
  check('drawn with 50 items or more, nothing typed into Find, a sort that has one',
    [S.showsIndex('alphabeticalByArtist', 50, ''), S.showsIndex('alphabeticalByArtist', 49, ''), S.showsIndex('alphabeticalByArtist', 3000, 'dum'),
      S.showsIndex('alphabeticalByArtist', 3000, '   '), S.showsIndex('newest', 3000, ''), S.showsIndex('byYearAsc', 50, ''), S.showsIndex('name', 50, ''), S.showsIndex('albums', 500, ''), S.INDEX_MIN],
    [true, false, false, true, false, true, true, false, 50])
  //? 320x568: 27 don't fit - as many as fit with a dot between each two, the first and the last kept
  const thin = S.fitIndex(letters, 13)
  check('fitIndex at 13 slots: 7 letters and 6 dots, A and # kept, the rest spread', [thin.length, thin.map((slot) => (slot.kind === 'dot' ? '•' : slot.entry.label)).join('')],
    [13, 'A•E•J•N•R•W•#'])
  check('...all of them when they fit', [S.fitIndex(letters, 27).length, S.fitIndex(letters, 40).every((slot) => slot.kind === 'entry')], [27, true])
  //? the full strip: 27 slots of 10 px from 100
  const full = S.fitIndex(letters, 27)
  check('...the finger\'s entry is the drawn slot under it: the full strip, its edges, beyond its ends, inside a slot',
    [S.entryAt(full, 100, 100, 270), S.entryAt(full, 110, 100, 270), S.entryAt(full, 120, 100, 270), S.entryAt(full, 369, 100, 270), S.entryAt(full, 9999, 100, 270), S.entryAt(full, 0, 100, 270), S.entryAt([], 5, 0, 10),
      S.entryAt(full, 5, 0, 0),
      //? (review) inside a slot, not only on its edges: the lower half of A is still A
      S.entryAt(full, 106, 100, 270), S.entryAt(full, 109.9, 100, 270), S.entryAt(full, 115.5, 100, 270)],
    [0, 1, 2, 26, 26, 0, null, null, 0, 0, 1])
  //? (review) a thinned strip: the finger was taken over the full list, which agreed with fitIndex's spread only mid-strip -
  //? at 13 slots A went to B, E to F, W to V and # to Z; at 18, U to T
  const lands = []
  for (let count = 1; count <= 27; count++) {
    const drawn = S.fitIndex(letters, count)
    drawn.forEach((slot, place) => {
      if (slot.kind !== 'entry') return
      for (const part of [0.05, 0.5, 0.95]) {
        const got = S.entryAt(drawn, 100 + (place + part) * 15, 100, drawn.length * 15)
        if (got !== slot.at) lands.push(`${count} slots: ${slot.entry.label} -> ${got === null ? null : letters[got].label}`)
      }
    })
  }
  check('...every drawn letter lands on itself, top, middle and foot of its slot, at every slot count from 1 to 27', lands, [])
  const thinPlace = (label) => thin.findIndex((slot) => slot.kind === 'entry' && slot.entry.label === label)
  const across = []
  for (let y = 100 + (thinPlace('A') + 1) * 15; y < 100 + thinPlace('E') * 15; y += 1) across.push(letters[S.entryAt(thin, y, 100, 13 * 15)].label)
  check('...a drag across a dot reaches each letter it stands for, in order (A•E: B, C, D)', [...new Set(across)], ['B', 'C', 'D'])
  const swept = new Set()
  for (const count of [3, 7, 13, 18, 26]) {
    const drawn = S.fitIndex(letters, count)
    swept.clear()
    for (let y = 100; y < 100 + drawn.length * 15; y += 0.25) swept.add(S.entryAt(drawn, y, 100, drawn.length * 15))
    check(`...a drag down the whole strip at ${count} slots reaches all 27`, swept.size, 27)
  }
}

console.log('\nFind')
{
  const albums = ALBUMS()
  const found = (typed) => ids(S.filterAlbums(albums, typed))
  check('every word, in any order, on the title or the artist', [found('beatles road'), found('road BEATLES'), found('help'), found('beatles')], [['abbey'], ['abbey'], ['help'], ['abbey', 'help', 'tribute']])
  check('accents and case folded either way, "&" read as "and"', [found('bjork'), found('BJÖRK post'), found('simon and'), found('&')], [['debut', 'post', 'debut2'], ['post'], ['simon'], ['simon']])
  check('"The" and a bracketed edition findable', [ids(S.filterAlbums([...albums, { id: 'dlx', name: 'Dummy (Deluxe Edition)', artist: 'Portishead' }], 'deluxe')), found('the beatles abbey')], [['dlx'], ['abbey']])
  check('nothing typed, or spaces: everything', [found('').length, found('   ').length, S.finding('  '), S.finding('a')], [11, 11, false, true])
  check('artists by name', S.filterArtists([{ id: 'b', name: 'Björk' }, { id: 'p', name: 'Portishead' }], 'BJO').map((a) => a.id), ['b'])
  check('the count while narrowing, and the words when nothing matches',
    [S.filteredCountText(12, 3012, 'album', 'albums'), S.filteredCountText(1, 1, 'album', 'albums'), S.filteredCountText(0, 2, 'artist', 'artists'), S.noMatchText('albums', ' dumy '), S.noMatchText('artists', 'x')],
    ['12 of 3012 albums', '1 of 1 album', '0 of 2 artists', 'No albums match “dumy”.', 'No artists match “x”.'])
}

console.log('\nblocks: what the shelf draws')
{
  const group = (key, label, count) => ({ key, label, items: Array.from({ length: count }, (_, n) => n) })
  const shape = (groups) => S.blocks(groups).map((block) => [block.key, block.head, block.group, block.items.length])
  check('none for nothing', shape([]), [])
  check('1 item: one block with its head', shape([group('A', 'A', 1)]), [['A:0', 'A', 0, 1]])
  check('60: one block', shape([group('A', 'A', 60)]), [['A:0', 'A', 0, 60]])
  check('61: two, the head on the first only', shape([group('A', 'A', 61)]), [['A:0', 'A', 0, 60], ['A:1', null, 0, 1]])
  check('two groups, each its own blocks, each headed', shape([group('A', 'A', 61), group('B', 'B', 2)]), [['A:0', 'A', 0, 60], ['A:1', null, 0, 1], ['B:0', 'B', 1, 2]])
  const many = S.blocks([group('all', null, 3000)])
  check('a headerless sort: one unlabelled group, cut the same - 3,000 in 50 blocks of 60, no head anywhere',
    [many.length, many.every((block) => block.items.length === 60 && block.head === null), S.BLOCK_SIZE], [50, true, 60])
  check('60 divides by the columns the app draws', [2, 3, 4, 5, 6].map((columns) => S.BLOCK_SIZE % columns), [0, 0, 0, 0, 0])
}

console.log('\nwhich blocks a new list draws before the page says (blocksNear)')
{
  const heights = [100, 100, 100, 100, 100]
  check('the window from the top: the blocks it touches', [S.blocksNear(heights, 0, 250), S.blocksNear(heights, -500, 100), S.blocksNear(heights, 150, 351)], [[0, 3], [0, 1], [1, 4]])
  check('a block ending at the window\'s start, or starting at its end, is out', [S.blocksNear(heights, 100, 200), S.blocksNear(heights, 99, 201)], [[1, 2], [0, 3]])
  check('past the end the last; before the shelf the first; none for none', [S.blocksNear(heights, 900, 1200), S.blocksNear(heights, -900, -100), S.blocksNear([], 0, 100)], [[4, 5], [0, 1], [0, 0]])
}

console.log('\nkeys made once per album')
{
  const real = owned.foldName
  let calls = 0
  owned.foldName = (name) => {
    calls++
    return real(name)
  }
  const names = ['The Beatles', 'Björk', 'Portishead', '10cc', 'Massive Attack', 'Tricky']
  const albums = Array.from({ length: 3000 }, (_, n) => ({ id: `al-${n}`, name: `Album ${n % 97}`, artist: names[n % names.length], year: 1960 + (n % 60), created: `2026-${String(1 + (n % 12)).padStart(2, '0')}-01T00:00:00Z` }))
  for (const sort of ['alphabeticalByArtist', 'alphabeticalByName']) S.groupAlbums(S.sortAlbums(albums, sort), sort)
  check('two sorts and their groups over 3,000 albums: foldName twice an album, the artist and the title, at most', [calls, calls <= 2 * 3000], [6000, true])
  S.groupAlbums(S.sortAlbums(albums, 'byYearDesc'), 'byYearDesc')
  check('...and no more for another sort of the same albums', calls, 6000)
  owned.foldName = real
}

console.log('\na sort read from storage')
check('the four old ids mean what they did; the three new ones kept; anything else Artist, the default',
  ['newest', 'recent', 'alphabeticalByArtist', 'alphabeticalByName', 'byYearDesc', 'byYearAsc', 'frequent', 'starred', 'random', '', null, undefined].map(S.albumSortFrom),
  ['newest', 'recent', 'alphabeticalByArtist', 'alphabeticalByName', 'byYearDesc', 'byYearAsc', 'frequent', 'alphabeticalByArtist', 'alphabeticalByArtist', 'alphabeticalByArtist', 'alphabeticalByArtist', 'alphabeticalByArtist'])
check('...the default itself', S.DEFAULT_ALBUM_SORT, 'alphabeticalByArtist')

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
