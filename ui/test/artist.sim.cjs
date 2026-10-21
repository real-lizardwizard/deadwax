/**
 * The artist page and the id bridge (2.0.0-player.17) - the pure rules in lib/artistPage.ts and
 * lib/idBridge.ts, compiled with the repo's TypeScript.
 *
 * What it pins:
 *
 *  - The page's id: Navidrome's artist id, or `mb:<mbid>` for one known only by MusicBrainz - and
 *    nothing else taken for a MusicBrainz id.
 *  - THE ORDER of the albums (`artistRows`): MusicBrainz's albums with what the library holds of each
 *    - by the store's word (/library/owned's folders, by group id), opened as the Navidrome album
 *    holding one of those releases, "2 editions" past one - and every album Navidrome has that no
 *    row claimed as a row of its own; oldest first, the undated last whichever kind, then by title,
 *    then steady. An untagged rip claimed only by the ONE album of its exact title. Studio only never
 *    hides an album you have. MusicBrainz down: the albums you have are the whole list. A renamed
 *    artist's albums under either name, together.
 *  - What Play and Shuffle play: one copy of each album you have, in the page's order - MusicBrainz
 *    answered or not: what Navidrome has that no MusicBrainz row claims is one row per album the
 *    library's folders say it is, keyed as MusicBrainz's row will be, so its answer changes no key.
 *    "2 editions" counts releases, not folders. The copy opened and played: the plain edition (none,
 *    or the scan's "Standard") first, then the oldest - the same for Search's held row.
 *  - Until /library/owned answers, no row Navidrome doesn't claim says held or not.
 *  - Who the artist is on the other side: Navidrome's artist -> MusicBrainz id (its own, else every
 *    folder's agreeing word, a collaboration's ids never), MusicBrainz id -> Navidrome's artist (the
 *    one carrying it, else the folders' name, else MusicBrainz's name for an artist with no id - each
 *    only when ONE answers); and the one artist an album is credited to.
 *  - The lines: a row's, "Plays the 2 albums you have", the facts, "4 albums in your library".
 *  - The bridge's chips and lines: "Also: <edition>" for each other pressing Navidrome has (never the
 *    album showing, never one it hasn't found, at most three), "This pressing: …", the folder, and
 *    the releases of a MusicBrainz album you hold.
 *  - Starting things a few at a time (inTurns), in order, stopping when superseded.
 *  - (2.0.0-player.41) The album page's "Other pressings" chip opens the group the album's folders
 *    carry - an id as MusicBrainz writes one, lowercased - and none without one.
 *
 * And the page itself (app/ArtistPage.tsx), compiled and rendered by the small stand-in for Preact the
 * other component sims use, with Navidrome, MusicBrainz, the bridge and /library/owned answering when
 * the test says (review, 2.0.0-player.17):
 *
 *  - the albums wait for every answer (or ROWS_WAIT_MS) and are then drawn once; MusicBrainz's answer
 *    landing later keeps every key, and the copy each row opens; a Studio only re-browse keeps the
 *    rows on screen, busy, until its answer lands; nothing says "not in your library", and no Get
 *    chip is drawn, until /library/owned has answered;
 *  - Play and Shuffle drawn from the first frame wherever albums could be had, disabled until every
 *    album is in hand and the library has said which are copies of one; the albums asked for a few
 *    at a time; Play remembering every album it queues; Dummy once, MusicBrainz answering or not;
 *  - an artist opened from MusicBrainz: looked for in a fresh list of artists when an old one hasn't
 *    them; a failed look with Try again; Navidrome having none of theirs said under the buttons;
 *  - a row's lookup that answers after the page stopped showing opens nothing, and the row fades
 *    while it looks; "MusicBrainz doesn't know who this is" only once the library has had its say;
 *  - the session's answers draw a page come back to on its first frame;
 *  - the pin in the hero (2.0.0-player.18): drawn from the first frame, live only once who they are
 *    is settled - their MusicBrainz id known, or Navidrome and the library both having answered
 *    without one - and the pins have answered (or failed to), so it never reads "Pin" of an artist who
 *    is pinned; pinning them by that id (else by name and Navidrome's id), pressed when pinned by
 *    their id whatever Navidrome's id was, and not live while deadwax can't keep pins - a tap then
 *    saying why in the app's notice.
 *
 * And the artist page as the main page had it (2.0.0-player.45): lib/artistManage.ts's rules - which
 * names the library files an artist under (a collaboration's folder never theirs), In your library
 * over them, where their pictures go, About's rows (Born/Founded, dates in words), the folds, the
 * picker's and the move's rules, Needs a look's hint naming the page's button - and the page's new
 * sections, hero and managing rendered, and app/ArtistPanel.tsx's three bodies and its frame.
 *
 * Run it with:  node ui/test/artist.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-artist-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/artistPage.ts', 'src/lib/idBridge.ts', 'src/lib/artistManage.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const A = require(path.join(OUT, 'lib/artistPage.js'))
const B = require(path.join(OUT, 'lib/idBridge.js'))
const O = require(path.join(OUT, 'lib/owned.js'))
const M = require(path.join(OUT, 'lib/artistManage.js'))

//? checks that wait for promises to settle: run in turn, after what came before has settled
const later = []
const await_ = (fn) => later.push(fn)
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const PORTISHEAD = '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'
const YE = '164f0d73-1234-4e2c-8743-d77bf2191051'
const CD = '11111111-1111-4111-8111-111111111111'
const VINYL = 'f5804905-0000-4000-8000-000000000000'
const SELFTITLED = '22222222-2222-4222-8222-222222222222'
const ROSELAND = '33333333-3333-4333-8333-333333333333'
const DONDA = '44444444-4444-4444-8444-444444444444'
const BULLY = '55555555-5555-4555-8555-555555555555'

const group = (id, title, date, more = {}) => ({ id, title, 'first-release-date': date, 'primary-type': 'Album', ...more })
const DUMMY_G = group('rg-dummy', 'Dummy', '1994-08-22')
const PORTISHEAD_G = group('rg-portishead', 'Portishead', '1997-09-29')
const THIRD_G = group('rg-third', 'Third', '2008-04-28')
const ROSELAND_G = group('rg-roseland', 'Roseland NYC Live', '1998-11-02', { 'secondary-types': ['Live'] })

const owned = (path, release, group, more = {}) => ({ path, artist: 'Portishead', album: path.split('/')[1], release_mbid: release, release_group_mbid: group, albumartist_mbids: [PORTISHEAD], ...more })
const LIBRARY = O.buildOwnedIndex([
  owned('Portishead/Dummy (1994)', CD, 'rg-dummy'),
  owned('Portishead/Dummy (1994) [20th Anniversary Reissue 180gram]', VINYL, 'rg-dummy'),
  owned('Portishead/Portishead (1997)', SELFTITLED, 'rg-portishead'),
])
const nd = (id, name, year, release, more = {}) => ({ id, name, year, coverArt: `al-${id}`, ...(release ? { musicBrainzId: release } : {}), ...more })
const HELD = [nd('nd-vinyl', 'Dummy', 2014, VINYL), nd('nd-cd', 'Dummy', 1994, CD), nd('nd-self', 'Portishead', 1997, SELFTITLED)]

const summary = (rows) => rows.map((row) => [row.title, row.year, row.albumId, row.held, row.editions])

console.log('\nthe page\'s id')
{
  check('Navidrome\'s artist', A.artistRef('ar-1'), { navidrome: 'ar-1', mbid: null })
  check('one known only by MusicBrainz', A.artistRef(`mb:${PORTISHEAD}`), { navidrome: null, mbid: PORTISHEAD })
  check('...in capitals, read as MusicBrainz writes it', A.artistRef(`mb:${PORTISHEAD.toUpperCase()}`).mbid, PORTISHEAD)
  check('...and nothing else taken for one', [A.artistRef('mb:portishead').mbid, A.artistRef(`mb:${PORTISHEAD}x`).mbid, A.artistRef('mb:').mbid], [null, null, null])
  check('the id for an artist: Navidrome\'s first, then mb:, then none',
    [A.artistPageId({ navidrome: 'ar-1', mbid: PORTISHEAD }), A.artistPageId({ mbid: PORTISHEAD }), A.artistPageId({ mbid: 'nope' }), A.artistPageId({})],
    ['ar-1', `mb:${PORTISHEAD}`, null, null])
}

console.log('\nthe albums, in order')
{
  const rows = A.artistRows(HELD, [THIRD_G, DUMMY_G, PORTISHEAD_G], LIBRARY)
  check('oldest first; what you have marked, opened as the album you have; what you don\'t, not',
    summary(rows), [['Dummy', '1994', 'nd-cd', true, 2], ['Portishead', '1997', 'nd-self', true, 1], ['Third', '2008', null, false, 0]])
  check('...each Navidrome album claimed once - neither copy of Dummy listed again',
    rows.map((row) => row.key), ['group:rg-dummy', 'group:rg-portishead', 'group:rg-third'])
  check('...the releases you hold of each, for the bridge', rows.map((row) => row.releases), [[CD, VINYL], [SELFTITLED], []])
  check('the lines, as the board has them', rows.map(A.rowLine), ['1994 · in your library · 2 editions', '1997 · in your library', '2008 · not in your library'])
  check('Play plays one copy of each album you have, in the page\'s order - the plain edition', A.playOrder(rows), ['nd-cd', 'nd-self'])
  const plainLater = O.buildOwnedIndex([owned('Portishead/Dummy (1994) [Deluxe]', CD, 'rg-dummy', { edition: 'Deluxe', year: '1994' }), owned('Portishead/Dummy plain', VINYL, 'rg-dummy', { edition: '', year: '2016' })])
  check('...the plain edition, whatever its year or its folder\'s name', A.artistRows(HELD, [DUMMY_G], plainLater)[0].albumId, 'nd-vinyl')
  const labelled = O.buildOwnedIndex([owned('Portishead/Dummy (1994) [Anniversary]', VINYL, 'rg-dummy', { edition: 'Anniversary', year: '2014' }), owned('Portishead/Dummy (1994) [Original]', CD, 'rg-dummy', { edition: 'Original', year: '1994' })])
  check('...two editions with labels: the older, whatever its folder\'s name', A.artistRows(HELD, [DUMMY_G], labelled)[0].albumId, 'nd-cd')

  const undated = A.artistRows([nd('nd-x', 'Demo Tape', 0)], [group('rg-u', 'Unknown Date', ''), THIRD_G, DUMMY_G], LIBRARY)
  check('the undated sink to the end, whichever kind - MusicBrainz\'s or one you have', undated.map((row) => row.title), ['Dummy', 'Third', 'Demo Tape', 'Unknown Date'])
  const ties = A.artistRows([], [group('rg-b', 'B side', '2001'), group('rg-a', 'a side', '2001'), group('rg-a2', 'A Side', '2001')], null)
  check('a year\'s albums by title, folded, then steadily', ties.map((row) => row.key), ['group:rg-a', 'group:rg-a2', 'group:rg-b'])

  const rip = nd('nd-rip', 'Dummy', 1994)
  const NONE = O.buildOwnedIndex([])
  check('an untagged rip claimed by the one album of its exact title',
    summary(A.artistRows([rip], [DUMMY_G, THIRD_G], NONE)), [['Dummy', '1994', 'nd-rip', true, 1], ['Third', '2008', null, false, 0]])
  check('...the library not having answered: Navidrome\'s claim stands, every other row says neither',
    [summary(A.artistRows([rip], [DUMMY_G, THIRD_G], null)), A.artistRows([rip], [DUMMY_G, THIRD_G], null).map(A.rowLine)],
    [[['Dummy', '1994', 'nd-rip', true, 1], ['Third', '2008', null, null, 0]], ['1994 · in your library', '2008']])
  check('...never by an album sharing its title with another - its own row then',
    A.artistRows([rip], [DUMMY_G, group('rg-dummy-2', 'Dummy', '2010')], null).map((row) => row.key).sort(),
    ['album:nd-rip', 'group:rg-dummy', 'group:rg-dummy-2'])
  check('...nor one tied to ANOTHER group by its folder\'s ids - a row of its own, as the group its folders say',
    A.artistRows([nd('nd-cd', 'Dummy', 1994, CD)], [group('rg-other', 'Dummy', '1994')], LIBRARY).map((row) => [row.key, row.albumId]).sort(),
    [['group:rg-dummy', 'nd-cd'], ['group:rg-other', null]])
  const m4a = O.buildOwnedIndex([owned('Portishead/Third (2008)', '66666666-6666-4666-8666-666666666666', '')])
  check('...but one whose folder carries no group id (an .m4a deadwax filed) is',
    summary(A.artistRows([nd('nd-third', 'Third', 2008, '66666666-6666-4666-8666-666666666666')], [THIRD_G], m4a)), [['Third', '2008', 'nd-third', true, 1]])

  check('Studio only never hides an album you have: a live album held is its own row',
    summary(A.artistRows([...HELD, nd('nd-rose', 'Roseland NYC Live', 1998, ROSELAND)], [DUMMY_G, PORTISHEAD_G, THIRD_G],
      O.buildOwnedIndex([...LIBRARY.byRelease.values()].flat().concat(owned('Portishead/Roseland NYC Live (1998)', ROSELAND, 'rg-roseland'))))),
    [['Dummy', '1994', 'nd-cd', true, 2], ['Portishead', '1997', 'nd-self', true, 1], ['Roseland NYC Live', '1998', 'nd-rose', true, 1], ['Third', '2008', null, false, 0]])
  check('...and with it off, a live album says so', A.rowLine(A.artistRows([], [ROSELAND_G], NONE)[0]), '1998 · Live album · not in your library')

  const down = A.artistRows(HELD, null, LIBRARY)
  check('MusicBrainz down (or not knowing who this is): the albums you have are the whole list - one row per album the folders say',
    summary(down), [['Dummy', '1994', 'nd-cd', true, 2], ['Portishead', '1997', 'nd-self', true, 1]])
  check('...keyed as MusicBrainz\'s rows will be, opening the same copy: its answer moves no key',
    [down.map((row) => [row.key, row.albumId]), A.artistRows(HELD, [THIRD_G, DUMMY_G, PORTISHEAD_G], LIBRARY).filter((row) => row.held).map((row) => [row.key, row.albumId])],
    [[['group:rg-dummy', 'nd-cd'], ['group:rg-portishead', 'nd-self']], [['group:rg-dummy', 'nd-cd'], ['group:rg-portishead', 'nd-self']]])
  check('...and Play plays Dummy once', A.playOrder(down), ['nd-cd', 'nd-self'])
  check('...an album the folders say nothing of is a row of its own',
    A.artistRows([nd('nd-rip', 'Old Rip', 1990)], null, LIBRARY).map((row) => row.key), ['album:nd-rip'])
  check('...before the library answers, Navidrome\'s copies of one album claimed by title stay apart, oldest first',
    summary(A.artistRows(HELD, null, null)).map((row) => row[2]), ['nd-cd', 'nd-self', 'nd-vinyl'])
  check('...and MusicBrainz\'s row claims both by title, the older opened', A.artistRows(HELD, [DUMMY_G], null)[0].albumId, 'nd-cd')
  check('held by the store\'s word, not found by Navidrome: in your library, opened by the bridge',
    A.artistRows([], [DUMMY_G], LIBRARY).map((row) => [row.held, row.albumId, row.releases.length, row.editions]), [[true, null, 2, 2]])
  check('...and Play has nothing of it to play', A.playOrder(A.artistRows([], [DUMMY_G], LIBRARY)), [])

  const ye = O.buildOwnedIndex([
    { path: 'Ye/Donda (2021)', artist: 'Ye', album: 'Donda', release_mbid: DONDA, release_group_mbid: 'rg-donda', albumartist_mbids: [YE] },
    { path: 'Ye/BULLY (2025)', artist: 'Ye', album: 'BULLY', release_mbid: BULLY, release_group_mbid: 'rg-bully', albumartist_mbids: [YE] },
  ])
  const credited = (name) => [{ name, artist: { id: YE, name: 'Ye' } }]
  check('a renamed artist: the albums credited to their old name and their new, together, in order',
    summary(A.artistRows([nd('nd-bully', 'BULLY', 2025, BULLY), nd('nd-donda', 'Donda', 2021, DONDA)],
      [group('rg-bully', 'BULLY', '2025-03-28', { 'artist-credit': credited('Ye') }), group('rg-donda', 'Donda', '2021-08-29', { 'artist-credit': credited('Kanye West') })], ye)),
    [['Donda', '2021', 'nd-donda', true, 1], ['BULLY', '2025', 'nd-bully', true, 1]])
  check('a group twice in MusicBrainz\'s answer is one row', A.artistRows([], [THIRD_G, THIRD_G], null).length, 1)

  const split = O.buildOwnedIndex([owned('Portishead/Dummy (1994) (Disc 1)', CD, 'rg-dummy'), owned('Portishead/Dummy (1994) (Disc 2)', CD, 'rg-dummy')])
  const twice = O.buildOwnedIndex([owned('Portishead/Dummy (1994) [FLAC]', CD, 'rg-dummy'), owned('Portishead/Dummy (1994) [MP3]', CD, 'rg-dummy')])
  check('"2 editions" counts releases: a set kept one folder per disc, or one release twice, is one',
    [A.artistRows([nd('nd-cd', 'Dummy', 1994, CD)], [DUMMY_G], split)[0].editions, A.artistRows([], [DUMMY_G], twice)[0].editions, A.artistRows(HELD, [DUMMY_G], LIBRARY)[0].editions],
    [1, 1, 2])
  const untaggedToo = O.buildOwnedIndex([owned('Portishead/Dummy (1994)', CD, 'rg-dummy'), owned('Portishead/Dummy rip', '', 'rg-dummy')])
  check('...a folder naming no release counts once of its own', A.artistRows([], [DUMMY_G], untaggedToo)[0].editions, 2)
  const asScanned = O.buildOwnedIndex([
    owned('Portishead/Dummy (1994) [20th Anniversary Reissue 180gram]', VINYL, 'rg-dummy', { edition: '20th Anniversary Reissue 180gram', year: '2014' }),
    owned('Portishead/Dummy (1994)', CD, 'rg-dummy', { edition: 'Standard', year: '1994' }),
  ])
  check('the scan names the plain copy "Standard" beside another, and lists it after: still the plain edition, for the page and for Search',
    [A.artistRows(HELD, [DUMMY_G], asScanned)[0].albumId, B.heldReleases(asScanned, 'rg-dummy')], ['nd-cd', [CD, VINYL]])
  check('the copies in order: plain, then oldest, a year nobody wrote last, then by folder',
    B.heldInOrder([{ path: 'c', edition: 'Deluxe', year: '1990' }, { path: 'b', edition: '', year: '' }, { path: 'a', edition: 'standard', year: '2001' }, { path: 'd', edition: '', year: '2001' }]).map((x) => x.path),
    ['a', 'd', 'b', 'c'])
}

console.log('\nstarting things a few at a time')
{
  const started = []
  const ends = []
  A.inTurns(['a', 'b', 'c', 'd', 'e'], 2, (item) => { started.push(item); return new Promise((resolve) => ends.push(resolve)) })
  check('at most two out, in order', started, ['a', 'b'])
  ends.shift()()
  await_(() => {
    check('...the next as one settles', started, ['a', 'b', 'c'])
    let going = true
    const more = []
    A.inTurns(['x', 'y', 'z'], 1, (item) => { more.push(item); return Promise.resolve().then(() => { going = false }) }, () => going)
    await_(() => check('...and none once superseded', more, ['x']))
  })
}

console.log('\nwho the artist is, on the other side')
{
  check('Navidrome\'s own MusicBrainz id first', A.artistMbid({ id: 'ar-1', name: 'Portishead', musicBrainzId: PORTISHEAD.toUpperCase() }, [], null), PORTISHEAD)
  check('...else what the folders of the albums Navidrome has say', A.artistMbid({ id: 'ar-1', name: 'Portishead' }, HELD, LIBRARY), PORTISHEAD)
  const split = O.buildOwnedIndex([owned('Portishead/Dummy (1994)', CD, 'rg-dummy'), owned('Portishead/Third (2008)', SELFTITLED, 'rg-p', { albumartist_mbids: [YE] })])
  check('...only when they agree', A.artistMbid({ id: 'ar-1', name: 'Portishead' }, HELD, split), null)
  const collab = O.buildOwnedIndex([owned('Portishead/Dummy (1994)', CD, 'rg-dummy', { albumartist_mbids: [PORTISHEAD, YE] })])
  check('...never a collaboration\'s ids', A.artistMbid({ id: 'ar-1', name: 'Portishead' }, [nd('nd-cd', 'Dummy', 1994, CD)], collab), null)
  const untagged = O.buildOwnedIndex([{ path: 'The Portishead/Dummy', artist: 'The Portishead', album: 'Dummy', release_mbid: '', release_group_mbid: '', albumartist_mbids: [PORTISHEAD] }])
  check('...by the artist\'s name, folded, when Navidrome\'s albums carry no release ids', A.artistMbid({ id: 'ar-1', name: 'Portishead' }, [nd('nd-rip', 'Dummy', 1994)], untagged), PORTISHEAD)
  check('...and none from nothing', [A.artistMbid({ id: 'ar-1', name: 'Portishead' }, HELD, null), A.artistMbid(null, HELD, LIBRARY)], [null, null])

  const artists = [{ id: 'ar-p', name: 'Portishead' }, { id: 'ar-n1', name: 'Nirvana' }, { id: 'ar-n2', name: 'Nirvana' }, { id: 'ar-ye', name: 'Ye', musicBrainzId: YE }]
  check('Navidrome\'s artist carrying the id', A.libraryArtistFor(artists, YE, null)?.id, 'ar-ye')
  check('...two carrying it: neither', A.libraryArtistFor([...artists, { id: 'ar-ye2', name: 'Kanye West', musicBrainzId: YE }], YE, null), null)
  check('...else the name the library\'s folders by that id are filed under', A.libraryArtistFor(artists, PORTISHEAD, LIBRARY)?.id, 'ar-p')
  check('...else MusicBrainz\'s name for them - only for an artist Navidrome has no id for', A.libraryArtistFor(artists, PORTISHEAD, null, 'Portishead')?.id, 'ar-p')
  check('...never a name two artists answer to', A.libraryArtistFor(artists, '99999999-9999-4999-8999-999999999999', null, 'Nirvana'), null)
  check('...never one carrying another id', A.libraryArtistFor(artists, PORTISHEAD, null, 'Ye'), null)
  check('...and nothing for no id', A.libraryArtistFor(artists, 'portishead', LIBRARY, 'Portishead'), null)

  check('the one artist an album is credited to', A.soleCredit([{ name: 'Portishead', artist: { id: PORTISHEAD, name: 'Portishead' } }]), { mbid: PORTISHEAD, name: 'Portishead' })
  check('...as credited: Kanye West, for Ye\'s id', A.soleCredit([{ name: 'Kanye West', artist: { id: YE, name: 'Ye' } }]), { mbid: YE, name: 'Kanye West' })
  check('...never a collaboration, or a credit with no id',
    [A.soleCredit([{ name: 'JAY-Z', joinphrase: ' & ', artist: { id: YE } }, { name: 'Ye', artist: { id: YE } }]), A.soleCredit([{ name: 'Someone' }]), A.soleCredit([])], [null, null, null])
}

console.log('\nthe lines')
{
  check('Plays the 2 albums you have', A.playsLine(2, 2, true), 'Plays the 2 albums you have')
  check('...the one album', A.playsLine(1, 1, true), 'Plays the album you have')
  check('...while their songs are asked for', A.playsLine(2, 1, false), 'Getting the songs of the 2 albums you have…')
  check('...some not sent', A.playsLine(3, 2, true), "Plays 2 of the 3 albums you have - Navidrome didn't send the rest")
  check('...none sent', A.playsLine(2, 0, true), "Navidrome didn't send the songs")
  check('...nothing to play: what Navidrome said - still looking, none of theirs, or nothing when it failed',
    [A.playsLine(0, 0, true, 'asking'), A.playsLine(0, 0, true), A.playsLine(0, 0, true, 'failed')],
    ['Looking for their albums in your library…', 'Navidrome has none of their albums to play', ''])
  const facts = { type: 'Group', area: 'United Kingdom', begin_area: 'Bristol', country: 'GB', began: '1991', ended_on: '', ended: false, disambiguation: '' }
  check('who they are: type, where from, since when', A.factsLine(facts), 'Group · Bristol · since 1991')
  check('...ended, with its dates', A.factsLine({ ...facts, begin_area: 'London', began: '1965-01-01', ended: true, ended_on: '2014-11-10' }), 'Group · London · 1965 to 2014')
  check('...ended, its end not known', A.factsLine({ ...facts, ended: true }), 'Group · Bristol · 1991, ended')
  check('...a place from the area or the country when there is no birthplace', [A.factsLine({ ...facts, begin_area: '' }), A.factsLine({ ...facts, begin_area: '', area: '' })],
    ['Group · United Kingdom · since 1991', 'Group · GB · since 1991'])
  check('...nothing known: nothing said', [A.factsLine({ type: '', area: '', begin_area: '', country: '', began: '', ended_on: '', ended: false, disambiguation: '' }), A.factsLine(null)], ['', ''])
  check('4 albums in your library', [A.albumCountLine(4), A.albumCountLine(1), A.albumCountLine(0), A.albumCountLine(undefined)], ['4 albums in your library', '1 album in your library', '', ''])
}

console.log('\nLibrary > Artists, and the count')
{
  const artists = [{ name: 'Massive Attack', albumCount: 2 }, { name: 'Portishead', albumCount: 3 }, { name: 'The Beatles', albumCount: 3 }, { name: 'Tricky' }]
  //? (2.0.0-player.59, on purpose) by deadwax's own fold key, no longer Navidrome's order: "The Beatles" under B, and a
  //? name no letter heads (digits, symbols, another script) after Z, so the Library's letter headers run unbroken
  check('by name: folded, "The" set aside', A.sortArtists(artists, 'name').map((a) => a.name), ['The Beatles', 'Massive Attack', 'Portishead', 'Tricky'])
  check('...names no letter heads after Z, a tie in Navidrome\'s order', A.sortArtists([{ name: '10cc' }, { name: 'Björk' }, { name: 'ABBA' }, { name: '坂本龍一' }, { name: 'abba' }], 'name').map((a) => a.name),
    ['ABBA', 'abba', 'Björk', '10cc', '坂本龍一'])
  check('most albums first, a tie in Navidrome\'s order, none counted last', A.sortArtists(artists, 'albums').map((a) => a.name), ['Portishead', 'The Beatles', 'Massive Attack', 'Tricky'])
  check('...never the list it was handed, rearranged', artists.map((a) => a.name), ['Massive Attack', 'Portishead', 'The Beatles', 'Tricky'])
  check('the orders offered', A.ARTIST_ORDERS.map((o) => o.label), ['Name', 'Most albums'])
  check('the count, once known', [A.countText(114, 'album', 'albums'), A.countText(1, 'artist', 'artists'), A.countText(0, 'song', 'songs'), A.countText(null, 'album', 'albums')],
    ['114 albums', '1 artist', '0 songs', ''])
}

console.log('\nthe id bridge: Also, This pressing, the folder')
{
  const row = (navidrome_id, edition, year) => ({ id: 1, path: `p/${edition}`, release_mbid: null, artist: '', album: '', edition, year, formats: ['flac'], track_count: 11, navidrome_id })
  const answer = { release_mbid: CD, release_group_mbid: 'rg-dummy', navidrome_id: 'nd-cd', present: [], other_pressings: [
    row('nd-vinyl', '20th Anniversary Reissue 180gram', '2014'), row(null, 'Remaster', '2017'), row('nd-cd', '', '1994'), row('nd-vinyl', 'again', '2014'),
    row('nd-a', '', '2001'), row('nd-b', '', 'x'), row('nd-c', 'Fourth', ''),
  ] }
  check('a chip for each other pressing Navidrome has - not one it hasn\'t found, not the album showing, each once, three at most',
    B.alsoChips(answer, 'nd-cd'), [
      { navidromeId: 'nd-vinyl', label: 'Also: 20th Anniversary Reissue 180gram' },
      { navidromeId: 'nd-a', label: 'Also: the 2001 pressing' },
      { navidromeId: 'nd-b', label: 'Also: another pressing' },
    ])
  check('...none without an answer', B.alsoChips(null, 'nd-cd'), [])
  //? "Other pressings ›" (2.0.0-player.41): the group the album's folders carry, as MusicBrainz writes an id
  const RG = 'e9aff11d-e3a0-3f7b-8d7c-1a0ef7a48a57'
  check('"Other pressings" opens the group its folders carry - lowercased, only an id as MusicBrainz writes one, none without',
    [B.otherPressingsGroup({ release_group_mbid: RG }), B.otherPressingsGroup({ release_group_mbid: ` ${RG.toUpperCase()} ` }), B.otherPressingsGroup({ release_group_mbid: 'rg-dummy' }),
      B.otherPressingsGroup({ release_group_mbid: null }), B.otherPressingsGroup({ release_group_mbid: `${RG}&inc=x` }), B.otherPressingsGroup(null)],
    [RG, RG, null, null, null, null])
  check('This pressing: its edition, year and formats', B.pressingLine([{ edition: '20th Anniversary Reissue 180gram', year: '2014', formats: ['flac'] }]),
    'This pressing: 20th Anniversary Reissue 180gram · 2014 · FLAC')
  check('...a set kept one folder per disc: the formats of all of them', B.pressingLine([{ edition: '', year: '1994', formats: ['flac'] }, { edition: '', year: '1994', formats: ['mp3'] }]),
    'This pressing: 1994 · FLAC/MP3')
  check('...not held: no line', [B.pressingLine([]), B.pressingLine([{ edition: '', year: '', formats: [] }])], [null, null])
  check('the folder, each of a set on its own line', [B.folderLine([{ path: 'Portishead/Dummy (1994)' }]), B.folderLine([{ path: 'A (Disc 1)' }, { path: 'A (Disc 2)' }]), B.folderLine([])],
    ['Portishead/Dummy (1994)', 'A (Disc 1)\nA (Disc 2)', null])
  check('the releases of a MusicBrainz album you hold, by its group', [B.heldReleases(LIBRARY, 'rg-dummy'), B.heldReleases(LIBRARY, 'rg-third'), B.heldReleases(null, 'rg-dummy'), B.heldReleases(LIBRARY, null)],
    [[CD, VINYL], [], [], []])
}

/* ===== the artist page, as the main page had it (2.0.0-player.45): lib/artistManage.ts ===== */

const JAYZ = '66666666-6666-4666-8666-666666666666'
const NIRVANA_US = '77777777-7777-4777-8777-777777777777'
const NIRVANA_UK = '88888888-8888-4888-8888-888888888888'
const YE_LIBRARY = O.buildOwnedIndex([
  { path: 'Kanye West/Donda (2021)', artist: 'Kanye West', album: 'Donda', release_mbid: DONDA, release_group_mbid: 'rg-donda', albumartist_mbids: [YE] },
  { path: 'Ye/BULLY (2025)', artist: 'Ye', album: 'BULLY', release_mbid: BULLY, release_group_mbid: 'rg-bully', albumartist_mbids: [YE] },
  //? a collaboration's folder is its own, whoever is in it
  { path: 'JAY-Z & Ye/Watch the Throne (2011)', artist: 'JAY‐Z & Ye', album: 'Watch the Throne', release_mbid: SELFTITLED, albumartist_mbids: [JAYZ, YE] },
  //? an untagged rip that goes by their name, and one Navidrome lists under them by its release
  { path: 'Ye/Tapes (2003)', artist: 'Ye', album: 'Tapes', release_mbid: null, albumartist_mbids: [] },
  { path: 'Misc/Graduation (2007)', artist: 'Kanye', album: 'Graduation', release_mbid: ROSELAND, albumartist_mbids: [] },
  //? somebody else's, tagged so
  { path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_mbid: CD, albumartist_mbids: [PORTISHEAD] },
])
const NIRVANAS = O.buildOwnedIndex([
  { path: 'Nirvana/Nevermind (1991)', artist: 'Nirvana', album: 'Nevermind', release_mbid: null, albumartist_mbids: [NIRVANA_US] },
  { path: 'Nirvana (UK)/Local Anaesthetic (1971)', artist: 'Nirvana', album: 'Local Anaesthetic', release_mbid: null, albumartist_mbids: [NIRVANA_UK] },
  { path: 'Nirvana/Bleach (1989)', artist: 'nirvana', album: 'Bleach', release_mbid: null, albumartist_mbids: [] },
])
const summaryOf = (artist, path, more = {}) => ({ artist, path, folder_problem: null, album_count: 1, track_count: 10, total_size: 400 * 1024 * 1024, first_year: '2021', last_year: '2021', albums: [], art: {}, ...more })

console.log('\nthe artist page as the main page had it: which names the library files them under')
{
  check('Ye: every folder tagged with their one id (both names), an untagged one by their name, one Navidrome lists by its release - never a collaboration, never another artist',
    M.libraryNames(YE_LIBRARY, { mbid: YE, name: 'Ye', releases: [ROSELAND] }), ['Kanye', 'Kanye West', 'Ye'])
  check('...Navidrome\'s "Kanye West" page, who MusicBrainz says is Ye: the same albums, the untagged one by that name',
    M.libraryNames(YE_LIBRARY, { mbid: YE, name: 'Kanye West', releases: [] }), ['Kanye West', 'Ye'])
  check('...a folder tagged as somebody else never theirs by name', M.libraryNames(YE_LIBRARY, { mbid: YE, name: 'Portishead', releases: [CD] }), ['Kanye West', 'Ye'])
  check('...nor a collaboration, even one Navidrome lists under them - by its release or by the name it goes by',
    [M.libraryNames(YE_LIBRARY, { mbid: YE, name: 'Ye', releases: [SELFTITLED] }), M.libraryNames(YE_LIBRARY, { mbid: YE, name: 'JAY‐Z & Ye', releases: [] }),
      M.libraryNames(YE_LIBRARY, { mbid: null, name: 'JAY‐Z & Ye', releases: [SELFTITLED] })],
    [['Kanye West', 'Ye'], ['Kanye West', 'Ye'], []])
  check('nobody can say who they are (two Nirvanas tagged apart): every folder going by the name, as Navidrome shows them',
    M.libraryNames(NIRVANAS, { mbid: null, name: 'Nirvana', releases: [] }), ['nirvana', 'Nirvana'])
  //? NAMES, not folders (review): the library's routes take a name, so a name two acts share answers
  //? for both - "Nirvana" here is the US band's Nevermind and the UK band's Local Anaesthetic alike, as
  //? on the main page, which groups by name too
  check('...the US band\'s page: the name of its own folder, and the untagged one\'s by name - the UK band\'s folder giving no name of its own',
    M.libraryNames(NIRVANAS, { mbid: NIRVANA_US, name: 'Nirvana', releases: [] }), ['nirvana', 'Nirvana'])
  check('...the UK band\'s, by the name of the folder only it carries the id of - and the untagged folder\'s by name (its aside folded away), which nobody can say is not theirs',
    M.libraryNames(NIRVANAS, { mbid: NIRVANA_UK, name: 'Nirvana (UK)', releases: [] }), ['nirvana', 'Nirvana'])
  check('...a folder tagged as the other band never theirs, by name or not', M.libraryNames(O.buildOwnedIndex([
    { path: 'Nirvana/Nevermind (1991)', artist: 'Nirvana', album: 'Nevermind', release_mbid: null, albumartist_mbids: [NIRVANA_US] }]), { mbid: NIRVANA_UK, name: 'Nirvana', releases: [] }), [])
  check('no library answer, or nothing of theirs: no names', [M.libraryNames(null, { mbid: YE, name: 'Ye', releases: [] }), M.libraryNames(LIBRARY, { mbid: YE, name: 'Ye', releases: [] })], [[], []])
  check('Move albums to <name>: the names that aren\'t MusicBrainz\'s for them now - the main page\'s test, the names differing as written',
    [M.namesToMove(['Kanye West', 'Ye'], 'Ye'), M.namesToMove(['Ye'], 'Ye'), M.namesToMove(['Kanye West'], null), M.namesToMove(['JAY-Z'], 'JAY‐Z')],
    [['Kanye West'], [], [], ['JAY-Z']])
}

console.log('\n...what the library holds of them, and where their pictures go')
{
  check('one name: its albums, tracks, size, years and folder - or why there is no one folder',
    [M.libraryFacts([summaryOf('Portishead', 'Portishead', { album_count: 3, track_count: 33, first_year: '1994', last_year: '2008' })]),
      M.libraryFacts([summaryOf('Portishead', null, { folder_problem: 'this artist\'s albums are in 2 different folders, so there is no one folder to put their pictures in' })]).problem],
    [{ albums: 3, tracks: 33, size: '400 MB', years: '1994–2008', folders: ['Portishead'], problem: null },
      'this artist\'s albums are in 2 different folders, so there is no one folder to put their pictures in'])
  check('two names: added up, the years across both, each folder - and why there is no one',
    M.libraryFacts([summaryOf('Kanye West', 'Kanye West', { total_size: 1024 ** 3 }), summaryOf('Ye', 'Ye', { first_year: '2025', last_year: '2025', total_size: 1024 ** 3 })]),
    { albums: 2, tracks: 20, size: '2.0 GB', years: '2021–2025', folders: ['Kanye West', 'Ye'], problem: 'Their albums are filed under 2 names - Kanye West and Ye' })
  check('...none: nothing to say', M.libraryFacts([]), null)
  check('...the years across names in any order: the earliest to the latest (Prince, filed after The Artist)',
    M.libraryFacts([summaryOf('The Artist', 'The Artist', { first_year: '1994', last_year: '1999' }), summaryOf('Prince', 'Prince', { first_year: '1978', last_year: '2016' })]).years, '1978–2016')
  check('the years: one, a span, or none', [M.yearsText('1994', '1994'), M.yearsText('1994', '2008'), M.yearsText('', ''), M.yearsText('', '2008')], ['1994', '1994–2008', '', '2008'])
  const both = new Map([['Kanye West', summaryOf('Kanye West', 'Kanye West')], ['Ye', summaryOf('Ye', 'Ye')]])
  check('their pictures go into the current name\'s folder where the library has it, else the only name\'s',
    [M.imagesFolder(['Kanye West', 'Ye'], 'Ye', both), M.imagesFolder(['Kanye West'], 'Ye', both), M.imagesFolder(['Ye'], null, both)],
    [{ name: 'Ye', reason: null }, { name: 'Kanye West', reason: null }, { name: 'Ye', reason: null }])
  check('...under several names, none of them current: none, until they are moved',
    [M.imagesFolder(['Kanye', 'Kanye West'], 'Ye', both), M.imagesFolder(['Kanye', 'Kanye West'], null, both)],
    [{ name: null, reason: 'Their albums are filed under 2 names - move them under Ye first, so their pictures have one folder' },
      { name: null, reason: "Their albums are filed under 2 names, so there's no one folder for their pictures" }])
  check('...a name whose albums share no folder says why (the main page\'s words); one deadwax couldn\'t read says so; not yet answered, no reason',
    [M.imagesFolder(['Ye'], 'Ye', new Map([['Ye', summaryOf('Ye', null, { folder_problem: 'an album by this artist sits at the top of the library' })]])),
      M.imagesFolder(['Ye'], 'Ye', new Map([['Ye', null]])), M.imagesFolder(['Ye'], 'Ye', new Map()), M.imagesFolder([], 'Ye', both)],
    [{ name: 'Ye', reason: 'An album by this artist sits at the top of the library' }, { name: 'Ye', reason: "deadwax couldn't read their folder just now" },
      { name: 'Ye', reason: null }, { name: null, reason: null }])
}

console.log('\n...who they are, in full')
{
  check('a date as MusicBrainz writes one, in words', ['1991', '1977-06', '1977-06-08', '2008-04-00', '', 'circa 1990'].map(M.factDate),
    ['1991', 'June 1977', '8 June 1977', 'April 2008', '', 'circa 1990'])
  check('a person is Born and Died, a group Founded and Dissolved, anything else Began and Ended - an end with no date said so',
    [M.lifeRows({ type: 'Person', began: '1977-06-08', ended: false, ended_on: '' }), M.lifeRows({ type: 'Group', began: '1991', ended: true, ended_on: '2014-05' }),
      M.lifeRows({ type: 'Orchestra', began: '', ended: true, ended_on: '' }), M.lifeRows({ type: 'Character', began: '1990', ended: false, ended_on: '' }), M.lifeRows(null),
      //? review: a choir is a group too, and was unpinned
      M.lifeRows({ type: 'Choir', began: '1950-03', ended: false, ended_on: '' })],
    [[{ label: 'Born', value: '8 June 1977' }], [{ label: 'Founded', value: '1991' }, { label: 'Dissolved', value: 'May 2014' }],
      [{ label: 'Dissolved', value: 'yes, date not known' }], [{ label: 'Began', value: '1990' }], [], [{ label: 'Founded', value: 'March 1950' }]])
  const facts = { name: 'Portishead', type: 'Group', begin_area: 'Bristol', area: 'United Kingdom', country: 'GB', began: '1991', ended: false, ended_on: '', aliases: ['Portis Head', 'ポーティスヘッド'], genres: [], links: [], members: [], disambiguation: '', sort_name: '' }
  check('the About rows: type, where from (where they began, else their area, else country), when, their other names',
    [M.aboutRows(facts), M.aboutRows({ ...facts, begin_area: '', area: '', aliases: [], type: '' }).map((row) => row.label), M.aboutRows(null)],
    [[{ label: 'Type', value: 'Group' }, { label: 'From', value: 'Bristol' }, { label: 'Founded', value: '1991' }, { label: 'Other names', value: 'Portis Head, ポーティスヘッド' }],
      ['From', 'Began'], []])
  check('a member\'s years and first three roles', [M.memberYears({ began: '1991-04', ended: null, current: true }), M.memberYears({ began: null, ended: '1999', current: false }),
    M.memberYears({ began: '1991', ended: '1999-01-01', current: false }), M.memberRoles({ roles: ['lead vocals', 'guitar', 'bass', 'drums'] })],
    ['1991–', '?–1999', '1991–1999', 'lead vocals, guitar, bass'])
  check('a long list folded: what shows, and how many wait behind "N more" - none once opened', [M.folded([1, 2, 3, 4], 3, false), M.folded([1, 2, 3, 4], 3, true), M.folded([1, 2], 3, false)],
    [{ items: [1, 2, 3], more: 1 }, { items: [1, 2, 3, 4], more: 0 }, { items: [1, 2], more: 0 }])
  check('ten members and eight links before the fold, as the main page showed them', [M.MEMBERS_SHOWN, M.LINKS_SHOWN], [10, 8])
}

console.log('\n...Artist images…, the main page\'s picker\'s rules')
{
  const thumb = { kind: 'thumb', url: 'https://commons/a.jpg', preview: 'https://commons/a.jpg?w=600', source: 'wikidata', label: 'Wikidata image' }
  const banner = { kind: 'banner', url: 'https://fanart/b.jpg', preview: 'https://fanart/b.jpg', source: 'fanarttv', label: 'fanart.tv Banner' }
  check('everything, best source first, to start with', M.bestUrls({ best: { thumb, banner } }), { thumb: thumb.url, banner: banner.url })
  check('a picture chosen for a slot - again, and that slot is left as it is - any picture in any slot',
    [M.toggleChoice({ thumb: thumb.url }, 'thumb', thumb.url), M.toggleChoice({}, 'fanart', thumb.url), M.toggleChoice({ thumb: 'x' }, 'thumb', thumb.url)],
    [{}, { fanart: thumb.url }, { thumb: thumb.url }])
  check('the pictures by slot', Object.keys(M.byKind([thumb, banner, { ...thumb, url: 'u2' }])).map((kind) => [kind, M.byKind([thumb, banner, { ...thumb, url: 'u2' }])[kind].length]), [['thumb', 2], ['banner', 1]])
  check('a slot\'s line: the file on disk, nothing found, or nothing to say', [M.slotLine('artist.jpg', 2), M.slotLine(null, 0), M.slotLine(undefined, 3)], ['artist.jpg on disk', 'none found for this', ''])
  check('the notes on keys not set: neither, fanart.tv\'s, none', [M.imageNotes({ has_key: false, sources: { fanarttv: false, theaudiodb: false } }).length,
    M.imageNotes({ has_key: true, sources: { fanarttv: false, theaudiodb: true } })[0].startsWith('fanart.tv isn\'t set up'), M.imageNotes({ has_key: true, sources: { fanarttv: true, theaudiodb: false } })],
    [1, true, []])
  check('...and where the keys go said as deadwax\'s settings has them (Connections)', M.imageNotes({ has_key: false, sources: {} })[0].includes('under Connections'), true)
  check('what a save says', [M.savedLine({ written: ['artist.jpg', 'banner.png'], problems: [] }), M.savedLine({ written: [], problems: ['the banner could not be fetched'] }), M.savedLine({ written: [], problems: [] })],
    ['Saved artist.jpg, banner.png.', 'the banner could not be fetched', 'Nothing needed writing.'])
  check('an artist found: the name they matched as, what tells them apart',
    [M.matchLine({ name: 'Ye', matched_as: 'Kanye West', disambiguation: 'US rapper', type: 'Person', country: 'US' }), M.matchLine({ name: 'Nirvana', matched_as: 'Nirvana', disambiguation: '', type: 'Group', country: 'GB' }), M.matchLine({ name: 'X', matched_as: '', disambiguation: '', type: '', country: '' })],
    ['as Kanye West · US rapper · Person · US', 'Group · GB', ''])
}

console.log('\n...Move albums to …, across every name')
{
  const plan = (moves, refused = [], problems = []) => ({ current_name: 'Ye', to_folder: 'Ye', artist_mbid: YE, moves, refused, problems, empty: !moves.length })
  const move = (path, target, files, retagged) => ({ album: path, path, target_path: target, files, retag: Array.from({ length: retagged }, (_, n) => ({ filename: `${n}.flac`, changes: {} })) })
  const view = M.refileView([{ name: 'Kanye West', plan: plan([move('Kanye West/Donda (2021)', 'Ye/Donda (2021)', 2, 2)]) },
    { name: 'Kanye', plan: plan([], [{ album: 'Graduation', path: 'Misc/Graduation (2007)', reason: 'tagged as a different artist' }]) }])
  check('every name\'s plan as one: each move and refusal, empty only when no name has anything to move',
    [view.moves.map((one) => one.path), view.refused.map((one) => one.reason), view.empty, view.currentName, view.toFolder],
    [['Kanye West/Donda (2021)'], ['tagged as a different artist'], false, 'Ye', 'Ye'])
  //? review: two names each holding a folder of one name - each name's plan is the route's for it alone,
  //? so both planned the move to Ye/Graduation (2007), and the button said "Move 2 albums"
  const twice = M.refileView([{ name: 'Kanye', plan: plan([move('Kanye/Graduation (2007)', 'Ye/Graduation (2007)', 3, 3)]) },
    { name: 'Kanye West', plan: plan([move('Kanye West/Graduation (2007)', 'Ye/Graduation (2007)', 3, 3), move('Kanye West/Donda (2021)', 'Ye/Donda (2021)', 2, 2)]) }])
  check('two names moving folders to one place: the later shown staying, and why - the button counting what can move',
    [twice.moves.map((one) => one.path), twice.refused, M.moveButton(twice.moves.length)],
    [['Kanye/Graduation (2007)', 'Kanye West/Donda (2021)'], [{ album: 'Kanye West/Graduation (2007)', path: 'Kanye West/Graduation (2007)', reason: "another album moves to 'Ye/Graduation (2007)'" }], 'Move 2 albums'])
  const result = (moved, failed = []) => ({ moved: moved.map((from) => ({ from, to: `Ye/${from.split('/')[1]}` })), failed, pictures_moved: [], removed_folders: [] })
  const previewed = [{ name: 'Kanye', plan: plan([move('Kanye/Graduation (2007)', 'Ye/Graduation (2007)', 3, 3)]) },
    { name: 'Kanye West', plan: plan([move('Kanye West/Graduation (2007)', 'Ye/Graduation (2007)', 3, 3), move('Kanye West/Donda (2021)', 'Ye/Donda (2021)', 2, 2)]) }]
  check('after the applies: each album the preview showed moving that the apply\'s own plan kept is said, never dropped; the names every album of which moved',
    M.refileAfter(previewed, [{ name: 'Kanye', plan: plan([move('x', 'y', 1, 0)]), results: result(['Kanye/Graduation (2007)']) },
      { name: 'Kanye West', plan: plan([move('Kanye West/Donda (2021)', 'Ye/Donda (2021)', 2, 2)], [{ album: 'Graduation', path: 'Kanye West/Graduation (2007)', reason: "'Ye/Graduation (2007)' is already there" },
        { album: 'Donda', path: 'Kanye West/Donda (2021)', reason: "'Ye/Donda (2021)' is already there" }]), results: result([]) }], twice),
    { stayed: ["Donda: stays - 'Ye/Donda (2021)' is already there"], emptied: ['Kanye'] })
  const one = [{ name: 'Kanye West', plan: plan([move('Kanye West/Donda (2021)', 'Ye/Donda (2021)', 2, 2)]) }]
  const oneView = M.refileView(one)
  check('...a name is empty only when every album of it moved: none refused at the preview or the apply, none failed - and not one never applied',
    [M.refileAfter(one, [{ name: 'Kanye West', plan: plan([]), results: result(['Kanye West/Donda (2021)']) }], oneView).emptied,
      M.refileAfter(one, [{ name: 'Kanye West', plan: plan([]), results: result([], [{ album: 'Donda', reason: "a tag wouldn't write" }]) }], oneView).emptied,
      M.refileAfter([{ name: 'Kanye West', plan: plan([move('Kanye West/Donda (2021)', 'Ye/Donda (2021)', 2, 2)], [{ album: 'X', path: 'Kanye West/X', reason: 'tagged as a different artist' }]) }],
        [{ name: 'Kanye West', plan: plan([]), results: result(['Kanye West/Donda (2021)']) }], oneView).emptied,
      M.refileAfter(one, [], oneView).emptied,
      //? an album filed under the name since the preview, its tag refusing at the apply: as many moved as
      //? were previewed, and still the name isn't empty
      M.refileAfter(one, [{ name: 'Kanye West', plan: plan([]), results: result(['Kanye West/Donda (2021)'], [{ album: 'Late Orchestration', reason: "a tag wouldn't write" }]) }], oneView).emptied,
      //? review: an album filed under the name since the preview, REFUSED by the apply's own plan (a
      //? collaboration): every album the preview showed moved, nothing failed - and the name still holds one
      M.refileAfter(one, [{ name: 'Kanye West', plan: plan([], [{ album: 'X', path: 'Kanye West/X', reason: 'a collaboration - its folder is its own' }]), results: result(['Kanye West/Donda (2021)']) }], oneView).emptied],
    [['Kanye West'], [], [], [], [], []])
  check('names listed: "a", "a and b", "a, b and c"', [M.listed(['a']), M.listed(['a', 'b']), M.listed(['a', 'b', 'c']), M.listed([])], ['a', 'a and b', 'a, b and c', ''])
  check('Move only with something to move and no problem', [M.canMove(view), M.canMove(M.refileView([{ name: 'x', plan: plan([]) }])), M.canMove(M.refileView([{ name: 'x', plan: plan([move('a', 'b', 1, 0)], [], ['MusicBrainz could not be reached just now']) }])), M.canMove(null)],
    [true, false, false, false])
  //? review: each name's plan says MusicBrainz's problem of its own - said once, not once a name
  check('...the problems every name\'s plan has, said once',
    M.refileView([{ name: 'Kanye', plan: plan([move('Kanye/Graduation (2007)', 'Ye/Graduation (2007)', 3, 3)], [], ['MusicBrainz could not be reached just now']) },
      { name: 'Kanye West', plan: plan([], [], ['MusicBrainz could not be reached just now', 'another problem']) }]).problems,
    ['MusicBrainz could not be reached just now', 'another problem'])
  check('a move\'s line and the button', [M.moveLine({ files: 2, retag: [1, 2] }), M.moveLine({ files: 1, retag: [] }), M.moveButton(1), M.moveButton(3)],
    ['2 tracks, 2 retagged', '1 track', 'Move 1 album', 'Move 3 albums'])
  check('what became of it, every name\'s results joined',
    [M.refileOutcome([{ moved: [{ from: 'a', to: 'b' }], failed: [], pictures_moved: ['artist.jpg'], removed_folders: ['Kanye West'] }], 'Ye'),
      M.refileOutcome([{ moved: [], failed: [{ album: 'Donda', reason: "a tag wouldn't write" }], pictures_moved: [], removed_folders: [] }], 'Ye')],
    [{ moved: 1, text: 'Moved 1 album into Ye/. Their pictures came too: artist.jpg. Kanye West/ was left empty and removed.', failures: [] },
      { moved: 0, text: 'Nothing was moved.', failures: ["Donda: a tag wouldn't write"] }])
  //? Needs a look's "Artist under two names" says how to fix it - in words the artist page's button carries
  const hint = /"artist_split": \{[\s\S]*?"hint": ([\s\S]*?),\n\s*"severity"/.exec(fs.readFileSync(path.join(UI, '..', 'src/metadata_health.py'), 'utf8'))?.[1].replace(/"\s*\n\s*"/g, '') ?? ''
  check('Needs a look\'s "Artist under two names" hint names the button the artist page draws',
    [hint.includes('Move albums to … on the artist\'s page'), /Move albums to \{facts\.name\}/.test(fs.readFileSync(path.join(UI, 'src/app/ArtistPage.tsx'), 'utf8'))], [true, true])
}

/* ===== the page itself: app/ArtistPage.tsx, rendered with every answer given by hand ===== */

const PAGE = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-artist-page-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/ArtistPage.tsx', 'src/app/ArtistPanel.tsx', '--rootDir', 'src', '--outDir', PAGE,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - group.sim.cjs's stand-in
fs.mkdirSync(path.join(PAGE, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(PAGE, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(PAGE, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(PAGE, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => {
    const outer = current; current = root; root.cursor = 0
    try { return component(props) } finally { current = outer }
  }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

//? Navidrome, MusicBrainz, the bridge and /library/owned: every ask kept, each answered when the test says
const write = (file, body) => fs.writeFileSync(path.join(PAGE, file), body)
write('api/musicbrainz.js', `
exports.getArtistFacts = (mbid) => globalThis.__page.ask('facts', mbid)
exports.getDiscography = (mbid, studioOnly) => globalThis.__page.ask('discography', mbid, studioOnly)
exports.getReleaseGroup = (id) => globalThis.__page.ask('releaseGroup', id)
`)
write('api/store.js', `exports.navidromeAlbumFor = (releases) => globalThis.__page.ask('bridge', releases)\n`)
write('player/api.js', `
exports.artistAlbums = (id) => globalThis.__page.ask('artistAlbums', id)
exports.libraryArtists = (fresh) => globalThis.__page.ask('libraryArtists', !!fresh)
exports.artistIndexAge = () => globalThis.__page.indexAge
exports.prefetchAlbum = (id) => globalThis.__page.ask('prefetch', id)
exports.rememberQueue = (albums) => globalThis.__page.remembered.push(albums.map((album) => album.id))
exports.toQueueTrack = (song, album) => ({ id: song.id, albumId: album.id })
`)
write('player/Cover.js', `exports.Cover = function Cover() { return null }\n`)
write('player/icons.js', `exports.CheckIcon = exports.ChevronLeftIcon = exports.PlayIcon = exports.ShuffleIcon = exports.PinIcon = function Icon() { return null }\n`)
//? the app's one store of pins (2.0.0-player.18): what is pinned, given by the test, and every pin asked for kept
write('app/usePins.js', `
exports.usePins = () => globalThis.__page.pins
exports.setPinned = (target, on) => { globalThis.__page.pinned.push([target, on]); return Promise.resolve() }
exports.sayPins = (text) => globalThis.__page.said.push(text)
`)
write('app/ArchiveCover.js', `exports.ArchiveCover = function ArchiveCover() { return null }\n`)
write('app/context.js', `exports.usePlayerActions = () => ({ playTracks: (...args) => globalThis.__page.plays.push(args) })\n`)
write('app/pressingLists.js', `exports.keep = () => {}\nexports.kept = () => null\nexports.usualGet = (group) => ({ release: { title: group.title }, subtitle: group.title })\n`)
write('app/useSheet.js', `exports.takeOpener = (event) => event?.currentTarget ?? null
exports.useSheet = (options) => { globalThis.__page.sheets.push(options) }
`)
//? the library's routes the artist page and its panel ask (2.0.0-player.45), each answered when the test says
write('api/library.js', `
exports.fetchArtist = (name, signal) => globalThis.__page.ask('summary', name, !!signal)
exports.previewArtistRefile = (name, mbid, signal) => globalThis.__page.ask('refilePreview', name, mbid, !!signal)
exports.applyArtistRefile = (name, mbid) => globalThis.__page.ask('refileApply', name, mbid)
exports.previewArtistImages = (name, options, signal) => globalThis.__page.ask('imagesPreview', name, options.artistMbid ?? null, !!signal)
exports.applyArtistImages = (name, choices, options) => globalThis.__page.ask('imagesApply', name, choices, options)
exports.searchArtists = (query, signal) => globalThis.__page.ask('artistSearch', query, !!signal)
`)
write('app/useOwned.js', `
exports.ownedNow = () => globalThis.__page.owned
exports.useOwned = () => globalThis.__page.owned
exports.whenOwned = () => globalThis.__page.owned ? Promise.resolve() : new Promise((resolve) => globalThis.__page.ownedWaiting.push(resolve))
`)

const W = globalThis.__page = {
  asks: [], open: [], owned: null, ownedWaiting: [], indexAge: 0, plays: [], remembered: [], sheets: [],
  pins: { pins: [], known: true, canSave: true, problem: null }, pinned: [], said: [],
  ask(name, ...args) {
    W.asks.push([name, ...args])
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    W.open.push({ name, args, resolve, reject })
    return promise
  },
}
const asked = (name) => W.asks.filter((one) => one[0] === name).map((one) => one.slice(1))
const outstanding = (name) => W.open.filter((one) => one.name === name)
function answer(name, value, which = () => true) {
  const at = W.open.findIndex((one) => one.name === name && which(...one.args))
  if (at < 0) throw new Error(`nothing asked of ${name}`)
  const [one] = W.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(typeof value === 'function' ? value(...one.args) : value)
}
function ownedAnswers(index) {
  W.owned = index ? { index, artists: [] } : { index: O.buildOwnedIndex([]), artists: [] }
  for (const resolve of W.ownedWaiting.splice(0)) resolve()
}
function reset() {
  W.asks.length = 0; W.open.length = 0; W.owned = null; W.ownedWaiting.length = 0; W.indexAge = 0; W.plays.length = 0; W.remembered.length = 0; W.sheets.length = 0
  W.pins = { pins: [], known: true, canSave: true, problem: null }; W.pinned.length = 0; W.said.length = 0
}

//? the albums' wait (ROWS_WAIT_MS) and the sections' (ABOUT_WAIT_MS): timers the test fires by hand -
//? every one at once, or (review) only those of one delay
const timers = []
globalThis.setTimeout = (fn, ms) => { const timer = { fn, ms, live: true }; timers.push(timer); return timer }
globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
const waitOver = () => { for (const timer of timers.splice(0)) if (timer.live) timer.fn() }
const fire = (ms) => {
  const due = timers.filter((timer) => timer.ms === ms)
  for (const timer of due) timers.splice(timers.indexOf(timer), 1)
  for (const timer of due) if (timer.live) timer.fn()
  return due.length
}

const hooks = require(path.join(PAGE, 'node_modules/preact/hooks.js'))
const { ArtistPage, PREFETCH_AT_ONCE, forgetKeptArtist } = require(path.join(PAGE, 'app/ArtistPage.js'))
const { PINS_UNSAVED: P_UNSAVED } = require(path.join(PAGE, 'app/PinToggle.js'))

let tree = null
function find(test, within = tree) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name) => find(byClass(name))
const rowKeys = () => find((node) => node.type === 'li' && byClass('app-artist-row')(node)).map((node) => node.key)
const rowLines = () => classed('app-artist-line-text').map(words)
const getChips = () => classed('app-result-get').map((node) => node.props['aria-label'])
const pills = () => classed('pl-pill').map((node) => [words(node), node.props.disabled])
const playsWords = () => words(classed('app-artist-plays')[0])

/** A page, mounted: draw it (effects and all), and again after answers land. */
function mount(props = {}) {
  const render = hooks.root(ArtistPage)
  const opened = [], groups = [], gets = []
  const all = {
    id: 'ar-portishead', preview: null, navidromeOk: true, shown: true, onBack() {}, backLabel: 'Library',
    onOpenAlbum: (album) => opened.push(album), onOpenGroup: (group) => groups.push(group), onGet: (request) => gets.push(request), ...props,
  }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = render(all)
    render.commit()
    return tree
  }
  //? drawn, its effects not yet run - as Preact does, which runs them after the browser paints
  const drawOnly = (more = {}) => {
    Object.assign(all, more)
    tree = render(all)
    return { commit: () => render.commit() }
  }
  const settled = async (more = {}) => {
    for (let round = 0; round < 4; round++) {
      draw(more)
      await settle()
    }
    return draw(more)
  }
  return { draw, drawOnly, settled, opened, groups, gets }
}

const PORTISHEAD_ARTIST = { id: 'ar-portishead', name: 'Portishead', musicBrainzId: PORTISHEAD, coverArt: 'ar-p', albumCount: 3, album: HELD }
const DISCOGRAPHY = { 'release-groups': [THIRD_G, DUMMY_G, PORTISHEAD_G], truncated: false }
const songsOf = (id) => ({ id, name: id, song: [{ id: `${id}-1` }, { id: `${id}-2` }] })

async function page() {
  console.log('\nthe page: the albums wait for every answer, then draw once, and keep their keys')
  {
    reset()
    const one = mount()
    one.draw()
    check('first frame: no rows yet, the sweep saying what it waits for', [rowKeys(), words(classed('app-asking')[0])], [[], 'Looking in your library…'])
    check('...Play and Shuffle there from the first frame, disabled, and the line saying so', [pills(), playsWords()],
      [[['Play', true], ['Shuffle', true]], 'Looking for their albums in your library…'])
    answer('artistAlbums', PORTISHEAD_ARTIST)
    await one.settled()
    check('Navidrome answered: MusicBrainz asked for the artist\'s albums, Studio only', asked('discography'), [[PORTISHEAD, true]])
    check('...still no rows: MusicBrainz and the library haven\'t answered', rowKeys(), [])
    answer('discography', DISCOGRAPHY)
    await one.settled()
    check('MusicBrainz answered, the library not: still waiting', rowKeys(), [])
    waitOver()
    await one.settled()
    check('the wait over: drawn - every row MusicBrainz has, Navidrome\'s albums claimed by title', rowKeys(), ['group:rg-dummy', 'group:rg-portishead', 'group:rg-third'])
    check('...and no verdict, and no Get, where only the library could say', [rowLines(), getChips()], [['1994 · in your library · 2 editions', '1997 · in your library', '2008'], []])
    check('...Play still disabled: which copies are one album is the library\'s to say', pills().map((pill) => pill[1]), [true, true])
    ownedAnswers(LIBRARY)
    await one.settled()
    check('the library answered: the same rows, the same keys, Third "not in your library" with its Get',
      [rowKeys(), rowLines()[2], getChips()], [['group:rg-dummy', 'group:rg-portishead', 'group:rg-third'], '2008 · not in your library', ['Get Third']])
    check('the albums Play plays asked for, one copy of Dummy', asked('prefetch').map((one) => one[0]).sort(), ['nd-cd', 'nd-self'])
    while (outstanding('prefetch').length) answer('prefetch', songsOf)
    await one.settled()
    check('every album in hand: Play and Shuffle live', [pills(), playsWords()], [[['Play', false], ['Shuffle', false]], 'Plays the 2 albums you have'])
    classed('pl-pill')[0].props.onClick()
    check('Play: every album remembered for Info and the turntable, then the queue - Dummy once', [W.remembered, W.plays.map((p) => [p[0].map((t) => t.id), p[1], p[2]])],
      [[['nd-cd', 'nd-self']], [[['nd-cd-1', 'nd-cd-2', 'nd-self-1', 'nd-self-2'], 0, false]]])

    find((node) => node.type === 'button' && words(node) === 'Studio only')[0].props.onClick()
    one.draw()
    one.draw()
    check('Studio only off: asked again - the rows on screen meanwhile, busy', [asked('discography').slice(-1), rowKeys(), classed('app-artist-albums')[0].props['aria-busy']],
      [[[PORTISHEAD, false]], ['group:rg-dummy', 'group:rg-portishead', 'group:rg-third'], true])
    answer('discography', { 'release-groups': [...DISCOGRAPHY['release-groups'], ROSELAND_G] })
    await one.settled()
    check('...its answer drawn', rowKeys(), ['group:rg-dummy', 'group:rg-portishead', 'group:rg-roseland', 'group:rg-third'])

    const again = mount()
    again.draw()
    check('the page come back to (Back): its rows on the first frame, from the session', rowKeys(), ['group:rg-dummy', 'group:rg-portishead', 'group:rg-roseland', 'group:rg-third'])
    check('...asking MusicBrainz nothing again', asked('discography').length, 2)
  }

  console.log('\nthe page: MusicBrainz slow - what you have drawn, keyed as its rows will be')
  {
    reset()
    ownedAnswers(LIBRARY)
    const one = mount({ id: 'ar-portishead-2' })
    one.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-2' })
    await one.settled()
    waitOver()
    await one.settled()
    check('the wait over, MusicBrainz still out: one row per album you have, Dummy once', [rowKeys(), rowLines()],
      [['group:rg-dummy', 'group:rg-portishead'], ['1994 · in your library · 2 editions', '1997 · in your library']])
    check('...and Play asks for one copy of Dummy', asked('prefetch').map((one) => one[0]).sort(), ['nd-cd', 'nd-self'])
    answer('discography', DISCOGRAPHY)
    await one.settled()
    check('MusicBrainz answering adds what you don\'t have and moves no key', rowKeys(), ['group:rg-dummy', 'group:rg-portishead', 'group:rg-third'])
  }

  console.log('\nthe page: a few albums asked for at a time')
  {
    reset()
    ownedAnswers(O.buildOwnedIndex([]))
    const many = Array.from({ length: 9 }, (_, n) => nd(`nd-${n}`, `Album ${n}`, 2000 + n))
    const one = mount({ id: 'ar-many' })
    one.draw()
    answer('artistAlbums', { id: 'ar-many', name: 'Many', album: many })
    await one.settled()
    check(`at most ${PREFETCH_AT_ONCE} out at once, in the page's order`, outstanding('prefetch').map((one) => one.args[0]), ['nd-0', 'nd-1', 'nd-2', 'nd-3'])
    answer('prefetch', songsOf)
    await one.settled()
    check('...the next as one answers', outstanding('prefetch').map((one) => one.args[0]), ['nd-1', 'nd-2', 'nd-3', 'nd-4'])
    while (outstanding('prefetch').length) { answer('prefetch', songsOf); await one.settled() }
    classed('pl-pill')[1].props.onClick()
    check('Shuffle: all nine remembered, every song queued, shuffled', [W.remembered[0]?.length, W.plays[0]?.[0].length, W.plays[0]?.[1], W.plays[0]?.[2]], [9, 18, null, true])
  }

  console.log('\nthe page: an artist opened from MusicBrainz')
  {
    reset()
    ownedAnswers(O.buildOwnedIndex([]))
    W.indexAge = 60_000
    const one = mount({ id: `mb:${YE}` })
    one.draw()
    check('Play and Shuffle there from the first frame, Navidrome being up', [pills().length, playsWords()], [2, 'Looking for their albums in your library…'])
    answer('libraryArtists', [{ id: 'ar-x', name: 'Someone else' }])
    await one.settled()
    check('not in a list kept a while: asked for afresh', asked('libraryArtists'), [[false], [true]])
    answer('libraryArtists', [{ id: 'ar-x', name: 'Someone else' }, { id: 'ar-ye', name: 'Ye', musicBrainzId: YE }])
    await one.settled()
    check('...and found there: their albums asked for', asked('artistAlbums'), [['ar-ye']])

    reset()
    ownedAnswers(O.buildOwnedIndex([]))
    const none = mount({ id: 'mb:aaaaaaaa-0000-4000-8000-000000000001' })
    none.draw()
    answer('libraryArtists', [])
    await none.settled()
    check('nobody of theirs in Navidrome (a list just asked for): said under the buttons, which stay', [asked('libraryArtists'), pills().length, playsWords()],
      [[[false]], 2, 'Navidrome has none of their albums to play'])

    reset()
    ownedAnswers(O.buildOwnedIndex([]))
    const failing = mount({ id: 'mb:aaaaaaaa-0000-4000-8000-000000000002' })
    failing.draw()
    answer('libraryArtists', new Error('Navidrome is restarting'))
    await failing.settled()
    const retry = find((node) => node.type === 'button' && words(node) === 'Try again' && byClass('pl-text-button')(node))
    check('the look failing: why, and Try again', [words(classed('pl-notice')[0]).startsWith('Navidrome is restarting'), retry.length], [true, 1])
    retry[0].props.onClick()
    await failing.settled()
    check('...which looks again', asked('libraryArtists').length, 2)

    reset()
    const away = mount({ id: 'mb:aaaaaaaa-0000-4000-8000-000000000003', navidromeOk: false })
    away.draw()
    check('Navidrome not answering: no Play to draw at all', pills().length, 0)
  }

  console.log('\nthe page: a row\'s lookup that lands after the page stopped showing opens nothing')
  {
    reset()
    ownedAnswers(LIBRARY)
    const one = mount({ id: `mb:${PORTISHEAD}` })  // the one page of theirs opened from MusicBrainz
    one.draw()
    answer('libraryArtists', [])
    await one.settled()
    answer('discography', { 'release-groups': [DUMMY_G] })
    await one.settled()
    check('held by the store\'s word, Navidrome having no artist for them: in your library', rowLines(), ['1994 · in your library · 2 editions'])
    find((node) => byClass('app-artist-album')(node))[0].props.onClick()
    one.draw()
    check('the tap asks the bridge, the row faded while it looks', [asked('bridge'), classed('app-artist-album')[0].props.class], [[[[CD, VINYL]]], 'app-artist-album is-busy'])
    const hidden = one.drawOnly({ shown: false })
    answer('bridge', 'nd-cd')
    await settle()
    check('...gone to another tab, its answer landing before the effects ran: nothing opened there', [one.opened, one.groups], [[], []])
    hidden.commit()
    await one.settled()
    check('...nor after', [one.opened, one.groups], [[], []])
    one.draw({ shown: true })
    find((node) => byClass('app-artist-album')(node))[0].props.onClick()
    answer('bridge', 'nd-cd')
    await one.settled()
    check('...a tap with the page showing opens the album you have', one.opened.map((album) => album.id), ['nd-cd'])
    ownedAnswers(LIBRARY)
    await one.settled()
    answer('libraryArtists', [{ id: 'ar-p2', name: 'Portishead', musicBrainzId: PORTISHEAD }])
    await one.settled()
    check('Navidrome\'s artist found later (the library answered again): their albums asked for, the rows staying on screen meanwhile',
      [asked('artistAlbums').slice(-1), rowKeys()], [[['ar-p2']], ['group:rg-dummy']])
  }

  console.log('\nthe page: "MusicBrainz doesn\'t know who this is" only once the library has had its say')
  {
    reset()
    const one = mount({ id: 'ar-anon' })
    one.draw()
    answer('artistAlbums', { id: 'ar-anon', name: 'Anon', album: [nd('nd-a', 'Tape', 1990)] })
    await one.settled()
    waitOver()
    await one.settled()
    check('Navidrome has no id for them, the library hasn\'t answered: nothing claimed', words(classed('app-search-empty')[0]), '')
    ownedAnswers(O.buildOwnedIndex([]))
    await one.settled()
    check('...it has, and can\'t say either: said', words(classed('app-search-empty')[0]), "MusicBrainz doesn't know who this is from your files, so only the albums you have are here.")
  }

  console.log('\nthe page: the pin (2.0.0-player.18)')
  {
    reset()
    const one = mount({ id: 'ar-pinme' })
    one.draw()
    //? the PinToggle element, drawn as it draws itself (a leaf with no hooks of its own)
    const pin = () => {
      const element = find((node) => typeof node.type === 'function' && node.type.name === 'PinToggle')[0]
      return element ? element.type(element.props) : undefined
    }
    check('drawn in the hero\'s top row from the first frame - not live while who they are isn\'t settled', [!!pin(), pin().props['aria-disabled'], words(pin())], [true, true, 'Pin'])
    pin().props.onClick()
    check('...its tap doing nothing then', W.pinned, [])
    //? the pins not answered yet: whether they are pinned isn't known, so "Pin" can't be claimed
    W.pins = { pins: null, known: false, canSave: true, problem: null }
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-pinme' })
    await one.settled()
    check('Navidrome named their MusicBrainz id, the pins not in yet: still not live', pin().props['aria-disabled'], true)
    W.pins = { pins: [], known: true, canSave: true, problem: null }
    one.draw()
    check('Navidrome named their MusicBrainz id: live', pin().props['aria-disabled'], false)
    pin().props.onClick()
    check('...a tap pins them by it, with Navidrome\'s id, their name and picture', W.pinned,
      [[{ kind: 'artist', mbid: PORTISHEAD, navidrome_id: 'ar-pinme', name: 'Portishead', cover: 'ar-p' }, true]])
    W.pins = { pins: [{ kind: 'artist', ref: `mb:${PORTISHEAD}`, label: 'Portishead', sub: '', state: 'present', navidrome_id: 'ar-other', cover: null, mbid: PORTISHEAD }], known: true, canSave: true, problem: null }
    one.draw()
    check('pinned (by their MusicBrainz id, whatever Navidrome\'s id was then): pressed, "Pinned"', [pin().props['aria-pressed'], words(pin())], [true, 'Pinned'])
    pin().props.onClick()
    check('...a tap unpins them', W.pinned.slice(-1).map((one) => one[1]), [false])
    W.pins = { pins: [], known: true, canSave: false, problem: null }
    one.draw()
    check('deadwax can\'t keep pins: not live', pin().props['aria-disabled'], true)
    pin().props.onClick()
    check('...a tap says why in the app\'s notice, and pins nothing', [W.said, W.pinned.length], [[P_UNSAVED], 2])
    W.pins = { pins: null, known: true, canSave: true, problem: "Couldn't get your pins: Failed to fetch" }
    one.draw()
    check('the pins couldn\'t be had: live all the same (not held for ever), reading "Pin"', [pin().props['aria-disabled'], words(pin())], [false, 'Pin'])

    reset()
    const anon = mount({ id: 'ar-anon-pin' })
    anon.draw()
    answer('artistAlbums', { id: 'ar-anon-pin', name: 'Anon', album: [nd('nd-a', 'Tape', 1990)] })
    await anon.settled()
    check('no MusicBrainz id from Navidrome, the library not answered: still not live', pin().props['aria-disabled'], true)
    ownedAnswers(O.buildOwnedIndex([]))
    await anon.settled()
    pin().props.onClick()
    check('...nobody can say one: live, pinning them by name and Navidrome\'s id', [pin().props['aria-disabled'], W.pinned],
      [false, [[{ kind: 'artist', mbid: null, navidrome_id: 'ar-anon-pin', name: 'Anon', cover: null }, true]]])
  }
}

async function manage() {
  const { RefileBody, ImagesBody, WhoBody, ArtistPanel } = require(path.join(PAGE, 'app/ArtistPanel.js'))
  const link = (n) => ({ label: `Link ${n}`, url: `https://example.org/${n}` })
  const member = (n, current) => ({ name: `Member ${n}`, mbid: `m${n}`, began: '1991', ended: current ? null : '1999', current, roles: n === 1 ? ['lead vocals', 'guitar'] : [] })
  const FULL = {
    mbid: PORTISHEAD, name: 'Portishead', sort_name: 'Portishead', type: 'Group', disambiguation: 'Bristol trip hop band', country: 'GB', area: 'United Kingdom',
    begin_area: 'Bristol', began: '1991', ended_on: '', ended: false, genres: ['trip hop', 'electronic'], aliases: ['Portis Head'],
    links: Array.from({ length: 10 }, (_, n) => link(n + 1)), members: [...Array.from({ length: 3 }, (_, n) => member(n + 1, true)), ...Array.from({ length: 9 }, (_, n) => member(n + 4, false))],
  }
  const titles = () => find((node) => node.type === 'h2' && byClass('app-section-title')(node)).map(words)
  const manageButtons = () => classed('app-artist-manage-button').map((node) => [words(node), node.props['aria-disabled'] ?? null])
  const factRows = () => classed('app-artist-fact').map((node) => [words(find((one) => one.type === 'dt', node)[0]), words(find((one) => one.type === 'dd', node)[0])])
  //? MusicBrainz's artists for a name: MatchList, a leaf with no hooks, drawn as it draws itself
  const matchRows = () => find((node) => typeof node.type === 'function' && node.type.name === 'MatchList')
    .flatMap((element) => find(byClass('app-artist-match'), element.type(element.props)))

  console.log('\nas the main page had it: the page\'s In your library, About and Line-up - drawn under the albums, in one go')
  {
    reset()
    const managed = [], followed = []
    const drawn = []
    const one = mount({ id: 'ar-portishead-full', admin: true, onManage: (request, opener) => managed.push([request, opener]), onMoved: (...args) => followed.push(args), onDrawn: (all) => drawn.push(all) })
    one.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-full' })
    await one.settled()
    check('who they are asked of MusicBrainz once their id is known - one request, the full facts', asked('facts'), [[PORTISHEAD]])
    check('...nothing drawn under the albums before they are', classed('app-artist-more').length, 0)
    ownedAnswers(LIBRARY)
    await one.settled()
    check('the library answered: each name it files them under asked of /library/artist, through a latestOnly (a signal)', asked('summary'), [['Portishead', true]])
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    await one.settled()
    check('...the albums drawn, the library\'s word still out: In your library and the rest wait for it', [rowKeys().length, classed('app-artist-more').length], [3, 0])
    answer('summary', summaryOf('Portishead', 'Portishead', { album_count: 3, track_count: 33, first_year: '1994', last_year: '2008', art: { fanart: 'fanart.jpg', logo: 'logo.png', thumb: 'artist.jpg' } }))
    await one.settled()
    check('everything answered: drawn, under the albums - In your library, About, Line-up', titles(), ['Albums', 'In your library', 'About', 'Line-up'])
    check('In your library: albums, tracks, size, years, the folder', factRows().slice(0, 5),
      [['Albums', '3'], ['Tracks', '33'], ['Size', '400 MB'], ['Years', '1994–2008'], ['Folder', 'Portishead']])
    check('About: what tells them apart, then type, where from, founded, other names - no "Now" (the library files them as MusicBrainz names them)',
      [words(classed('app-artist-disambiguation')[0]), factRows().slice(5)],
      ['Bristol trip hop band', [['Type', 'Group'], ['From', 'Bristol'], ['Founded', '1991'], ['Other names', 'Portis Head']]])
    check('their genres, as tags', classed('app-artist-genre').map(words), ['trip hop', 'electronic'])
    const links = () => classed('app-artist-link')
    check('the links: eight, then a fold for the rest - each opening beside the app, its address in its tooltip',
      [links().length, links().every((a) => a.type === 'a' && a.props.target === '_blank' && a.props.rel === 'noopener' && a.props.title === a.props.href),
        words(classed('app-artist-fold')[0]), classed('app-artist-fold')[0].props['aria-expanded']],
      [8, true, '2 more links', false])
    classed('app-artist-fold')[0].props.onClick()
    one.draw()
    check('...opened: all ten, the fold saying Fewer', [links().length, words(classed('app-artist-fold')[0]), classed('app-artist-fold')[0].props['aria-expanded']], [10, 'Fewer links', true])
    const members = () => classed('app-artist-member')
    check('the line-up: the first ten (the current ones first), a past member stepped back, roles and years - "2 earlier members" behind a fold',
      [members().length, members()[0].props.class, words(members()[0]), members()[3].props.class, words(classed('app-artist-fold')[1])],
      [10, 'app-row app-artist-member', 'Member 1lead vocals, guitar1991–', 'app-row app-artist-member is-past', '2 earlier members'])
    //? review: the links' fold was pinned both ways, the line-up's only shut
    classed('app-artist-fold')[1].props.onClick()
    one.draw()
    check('...opened: all twelve, the fold saying Fewer members', [members().length, words(classed('app-artist-fold')[1]), classed('app-artist-fold')[1]?.props['aria-expanded']],
      [12, 'Fewer members', true])
    const hero = classed('app-artist-picture')[0]
    check('the hero: their background on disk, and their logo in their name\'s place (named as the name)',
      [hero.type, hero.props.src, find((node) => node.type === 'img' && byClass('app-artist-logo')(node))[0]?.props.alt,
        find((node) => node.type === 'img' && byClass('app-artist-logo')(node))[0]?.props.src],
      ['img', '/deadwax/library/artist/art?artist=Portishead&kind=fanart', 'Portishead', '/deadwax/library/artist/art?artist=Portishead&kind=logo'])
    check('an admin\'s: Artist images…, live - their one folder', manageButtons(), [['Artist images…', null]])
    classed('app-artist-manage-button')[0].props.onClick({ currentTarget: 'images-button' })
    const [request, opener] = managed[0]
    check('...its tap opens the panel for the pictures, for the folder of the name the library files them under',
      [request.mode, request.page, request.mbid, request.currentName, request.moveNames, request.imagesName, request.version, opener],
      ['images', 'ar-portishead-full', PORTISHEAD, 'Portishead', [], 'Portishead', 0, 'images-button'])
    one.draw({ managing: 'images' })
    check('...pressed while the panel shows it', classed('app-artist-manage-button')[0].props['aria-pressed'], true)
    request.onSaved()
    await one.settled()
    check('pictures saved: the library asked again, and the pictures on disk asked past the browser\'s cache',
      [asked('summary').length, classed('app-artist-picture')[0].props.src], [2, '/deadwax/library/artist/art?artist=Portishead&kind=fanart&v=1'])
    check('App told as the albums were drawn, then the sections under them - what it puts a scroll back on (review: a page a move made of another drew nothing on its first frame)',
      drawn, [false, true])
    answer('summary', summaryOf('Portishead', 'Portishead', { album_count: 3, track_count: 33, first_year: '1994', last_year: '2008', art: { fanart: 'fanart.jpg', logo: 'logo.png', thumb: 'artist.jpg' } }))
    await one.settled()
    //? review: the re-ask after a move was pinned only as wiring
    const albumsAsked = asked('artistAlbums').length, summariesAsked = asked('summary').length
    await one.settled({ refresh: 1 })
    check('App\'s refresh (a move Navidrome has had time to scan): Navidrome\'s albums and the library\'s word on their names asked again',
      [asked('artistAlbums').length - albumsAsked, asked('summary').length - summariesAsked], [1, 1])
    await one.settled({ refresh: 1 })
    check('...once for each new number, never again for the same one', [asked('artistAlbums').length - albumsAsked, asked('summary').length - summariesAsked], [1, 1])

    reset()
    ownedAnswers(LIBRARY)
    const plain = mount({ id: 'ar-portishead-full', admin: false, onManage: () => {} })
    plain.draw()
    check('not an admin: the same sections, no managing (the session\'s answers drawn at once)', [titles(), manageButtons()], [['Albums', 'In your library', 'About', 'Line-up'], []])
  }

  console.log('\n...a renamed artist: "Now: Ye", Move albums to Ye, and the page following them')
  {
    reset()
    ownedAnswers(YE_LIBRARY)
    const managed = [], followed = []
    const one = mount({ id: 'ar-kanye', admin: true, onManage: (request) => managed.push(request), onMoved: (...args) => followed.push(args) })
    one.draw()
    answer('artistAlbums', { id: 'ar-kanye', name: 'Kanye West', album: [nd('nd-donda', 'Donda', 2021, DONDA)] })
    await one.settled()
    check('Navidrome\'s "Kanye West", whose folder says Ye\'s id: both names the library files them under asked', asked('summary').map((one) => one[0]), ['Kanye West', 'Ye'])
    answer('discography', { 'release-groups': [group('rg-donda', 'Donda', '2021-08-29'), group('rg-bully', 'BULLY', '2025-03-01')] })
    answer('facts', { ...FULL, mbid: YE, name: 'Ye', type: 'Person', disambiguation: 'US rapper', began: '1977-06-08', begin_area: 'Atlanta', links: [], members: [], genres: [], aliases: ['Kanye West'] })
    answer('summary', summaryOf('Kanye West', 'Kanye West'), (name) => name === 'Kanye West')
    answer('summary', summaryOf('Ye', 'Ye', { first_year: '2025', last_year: '2025', art: { thumb: 'artist.jpg' } }), (name) => name === 'Ye')
    await one.settled()
    check('In your library: both names added up, each folder, and why there is no one folder',
      [factRows().slice(0, 1), words(classed('is-folder')[0])],
      [[['Albums', '2']], 'FoldersKanye West\nYeTheir albums are filed under 2 names - Kanye West and Ye'])
    check('About: "Now: Ye" first - Move albums to Ye on its row - then type and where from', [factRows().slice(5, 8).map((row) => row.join(': ')), words(classed('is-now')[0])],
      [['Now: Ye', 'Type: Person', 'From: Atlanta'], 'NowYeMove albums to Ye'])
    check('...and Born', factRows().find((row) => row[0] === 'Born'), ['Born', '8 June 1977'])
    check('an admin\'s: Artist images… (their pictures into Ye\'s folder) and Move albums to Ye', manageButtons().map((one) => one[0]), ['Artist images…', 'Move albums to Ye'])
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Move albums to Ye')[0].props.onClick({ currentTarget: null })
    check('...Move opens the panel for the names that aren\'t Ye, Ye\'s folder kept for the pictures',
      [managed[0].mode, managed[0].moveNames, managed[0].currentName, managed[0].imagesName, managed[0].mbid], ['refile', ['Kanye West'], 'Ye', 'Ye', YE])
    //? review: followed only from a page of a name every album of which moved
    managed[0].onMoved({ mbid: YE, name: 'Ye', moved: 1, emptied: [] })
    managed[0].onMoved({ mbid: YE, name: 'Ye', moved: 1, emptied: ['Kanye'] })
    managed[0].onMoved({ mbid: YE, name: 'Ye', moved: 1, emptied: ['kanye west'] })
    check('moved: the page told - to follow them by their MusicBrainz id, under their name now, only when its own name (Navidrome\'s "Kanye West") has no album left',
      followed, [['ar-kanye', { mbid: YE, name: 'Ye' }, false], ['ar-kanye', { mbid: YE, name: 'Ye' }, false], ['ar-kanye', { mbid: YE, name: 'Ye' }, true]])
    const back = mount({ id: 'ar-kanye', admin: true })
    back.draw()
    check('...and what the session kept of the page forgotten (its folders have moved): nothing drawn from it', [rowKeys(), classed('app-artist-more').length], [[], 0])
  }

  console.log('\n...their page by the name they have now: the other names still in use, Move albums to Ye - and the page stays')
  {
    reset()
    ownedAnswers(YE_LIBRARY)
    const managed = [], followed = []
    const one = mount({ id: 'ar-ye', admin: true, onManage: (request) => managed.push(request), onMoved: (...args) => followed.push(args) })
    one.draw()
    answer('artistAlbums', { id: 'ar-ye', name: 'Ye', musicBrainzId: YE, album: [nd('nd-bully', 'BULLY', 2025, BULLY)] })
    await one.settled()
    answer('discography', { 'release-groups': [group('rg-donda', 'Donda', '2021-08-29'), group('rg-bully', 'BULLY', '2025-03-01')] })
    answer('facts', { ...FULL, mbid: YE, name: 'Ye', type: 'Person', disambiguation: 'US rapper', began: '1977-06-08', begin_area: 'Atlanta', links: [], members: [], genres: [], aliases: ['Kanye West'] })
    answer('summary', summaryOf('Kanye West', 'Kanye West'), (name) => name === 'Kanye West')
    answer('summary', summaryOf('Ye', 'Ye', { first_year: '2025', last_year: '2025' }), (name) => name === 'Ye')
    await one.settled()
    check('Navidrome\'s "Ye", Donda still filed as Kanye West: never "Now: Ye" on Ye\'s own page - the name still in use, with Move albums to Ye',
      [words(classed('is-now')[0]), manageButtons().map((one) => one[0])], ['Also filed asKanye WestMove albums to Ye', ['Artist images…', 'Move albums to Ye']])
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Move albums to Ye')[0].props.onClick({ currentTarget: null })
    check('...Move moves the other name\'s albums, from this page', [managed[0].page, managed[0].name, managed[0].moveNames, managed[0].currentName], ['ar-ye', 'Ye', ['Kanye West'], 'Ye'])
    managed[0].onMoved({ mbid: YE, name: 'Ye', moved: 1, emptied: ['Kanye West'] })
    check('...moved, every album of Kanye West\'s included: this page - still Navidrome\'s Ye - stays where it is', followed, [['ar-ye', { mbid: YE, name: 'Ye' }, false]])
    managed[0].onMoved({ mbid: YE, name: 'Ye', moved: 1, emptied: [] })
    const mbPage = mount({ id: `mb:${YE}`, admin: true, onManage: (request) => managed.push(request), onMoved: (...args) => followed.push(args) })
    mbPage.draw()
    answer('libraryArtists', [{ id: 'ar-ye', name: 'Ye', musicBrainzId: YE }])
    answer('facts', { ...FULL, mbid: YE, name: 'Ye', links: [], members: [], genres: [], aliases: [] })
    answer('discography', { 'release-groups': [group('rg-bully', 'BULLY', '2025-03-01')] })
    await mbPage.settled()
    answer('artistAlbums', { id: 'ar-ye', name: 'Ye', musicBrainzId: YE, album: [nd('nd-bully', 'BULLY', 2025, BULLY)] })
    await mbPage.settled()
    while (outstanding('summary').length) answer('summary', (name) => summaryOf(name, name))
    await mbPage.settled()
    managed.length = 0
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Move albums to Ye')[0]?.props.onClick({ currentTarget: null })
    managed[0]?.onMoved({ mbid: YE, name: 'Ye', moved: 1, emptied: [] })
    check('...their page by MusicBrainz id is already where a move would take it (App changes nothing for it)', followed.slice(-1), [[`mb:${YE}`, { mbid: YE, name: 'Ye' }, true]])
    const findsBefore = asked('libraryArtists').length, albumsBefore = asked('artistAlbums').length
    await mbPage.settled({ refresh: 1 })
    check('App\'s refresh on a page by MusicBrainz id: Navidrome\'s artist for them found in a FRESH list (the scan may have made a new one), their albums asked again',
      [asked('libraryArtists').slice(findsBefore), asked('artistAlbums').length - albumsBefore], [[[true]], 1])
  }

  console.log('\n...MusicBrainz doesn\'t know who this is: Which artist is this?')
  {
    reset()
    ownedAnswers(O.buildOwnedIndex([{ path: 'Nirvana/Bleach (1989)', artist: 'Nirvana', album: 'Bleach', release_mbid: null, albumartist_mbids: [] }]))
    const managed = []
    const one = mount({ id: 'ar-nirvana', admin: true, onManage: (request) => managed.push(request) })
    one.draw()
    answer('artistAlbums', { id: 'ar-nirvana', name: 'Nirvana', album: [nd('nd-bleach', 'Bleach', 1989)] })
    await one.settled()
    waitOver()
    await one.settled()
    check('said, and for an admin, Which artist is this?', [words(classed('app-search-empty')[0]).startsWith("MusicBrainz doesn't know who this is"), manageButtons().map((one) => one[0]).includes('Which artist is this?')],
      [true, true])
    find((node) => words(node) === 'Which artist is this?' && node.type === 'button')[0].props.onClick({ currentTarget: null })
    check('...its tap opens the panel to choose, with the page\'s name to search for', [managed[0].mode, managed[0].name, managed[0].mbid], ['who', 'Nirvana', null])
    managed[0].onChosen({ mbid: NIRVANA_US, name: 'Nirvana', disambiguation: '90s US grunge band' })
    await one.settled()
    check('chosen: the page is theirs - who they are and their albums asked by that id', [asked('facts'), asked('discography')], [[[NIRVANA_US]], [[NIRVANA_US, true]]])
    answer('facts', { ...FULL, mbid: NIRVANA_US, name: 'Nirvana', disambiguation: '90s US grunge band', links: [], members: [] })
    answer('discography', { 'release-groups': [group('rg-bleach', 'Bleach', '1989-06-15')] })
    if (outstanding('summary').length) answer('summary', summaryOf('Nirvana', 'Nirvana'))
    await one.settled()
    check('...the page says it was chosen here, with Change', [words(classed('app-artist-chosen')[0]), find((node) => byClass('app-artist-change')(node)).length],
      ['You chose who this is, for this visit. Change', 1])
    //? review: this was `asked('discography').length >= 1 && rowKeys().length > 0`, true whether the
    //? choice was kept or not - Navidrome's own Bleach drew a row either way
    const discAsked = asked('discography').length
    const again = mount({ id: 'ar-nirvana', admin: true })
    again.draw()
    check('...kept for the visit: the page come back to is theirs at once - their album (MusicBrainz\'s row) drawn from what was kept, nothing asked again',
      [rowKeys(), asked('discography').length - discAsked], [['group:rg-bleach'], 0])

    //? review: choosing another left the first one's facts up - for good, if MusicBrainz failed for the new one
    tree = null
    one.draw({ managing: null })
    find((node) => byClass('app-artist-change')(node))[0].props.onClick({ currentTarget: null })
    managed[1].onChosen({ mbid: NIRVANA_UK, name: 'Nirvana', disambiguation: '60s UK band' })
    await one.settled()
    const aboutOf = () => find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-about-title')[0]
    check('another chosen (Change): asked for by its id - and meanwhile nothing of the last one\'s said as theirs, Change still there',
      [asked('facts').slice(-1), classed('app-artist-disambiguation').length, classed('app-artist-facts').length, words(find(byClass('app-asking-text'), aboutOf())[0]),
        find((node) => byClass('app-artist-change')(node)).length],
      [[[NIRVANA_UK]], 0, 0, 'Asking MusicBrainz…', 1])
    answer('facts', new Error('MusicBrainz is unreachable right now'), (mbid) => mbid === NIRVANA_UK)
    await one.settled()
    check('...MusicBrainz failing for them: said, with Try again - and Change, the way to another', [words(find(byClass('app-search-empty'), aboutOf())[0]),
      find((node) => node.type === 'button' && words(node) === 'Try again', aboutOf()).length, find((node) => byClass('app-artist-change')(node)).length, classed('app-artist-disambiguation').length],
      ["MusicBrainz isn't answering just now, so who they are isn't here.", 1, 1, 0])

    reset()
    ownedAnswers(O.buildOwnedIndex([]))
    const plain = mount({ id: 'ar-nirvana-2', admin: false, onManage: () => {} })
    plain.draw()
    answer('artistAlbums', { id: 'ar-nirvana-2', name: 'Nirvana', album: [nd('nd-bleach', 'Bleach', 1989)] })
    await plain.settled()
    check('not an admin: said, and no way to choose', [words(classed('app-search-empty')[0]).startsWith("MusicBrainz doesn't know"), manageButtons()], [true, []])
  }

  console.log('\n...MusicBrainz not answering for who they are')
  {
    reset()
    ownedAnswers(LIBRARY)
    const one = mount({ id: 'ar-portishead-down' })
    one.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-down' })
    await one.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', new Error('MusicBrainz is unreachable right now'))
    answer('summary', summaryOf('Portishead', 'Portishead'))
    await one.settled()
    const about = find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-about-title')[0]
    check('About says so, with Try again - the albums and the library half drawn all the same',
      [words(find((node) => byClass('app-search-empty')(node), about)[0]), titles()], ["MusicBrainz isn't answering just now, so who they are isn't here.", ['Albums', 'In your library', 'About']])
    find((node) => node.type === 'button' && words(node) === 'Try again', about)[0].props.onClick()
    await one.settled()
    //? review: only the second ask was pinned - the failure could have stayed on screen while it asked
    const aboutNow = find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-about-title')[0]
    check('...which asks again - the failure giving way to "Asking MusicBrainz…" while it does',
      [asked('facts').length, words(find(byClass('app-asking-text'), aboutNow)[0]), find(byClass('app-search-empty'), aboutNow).length], [2, 'Asking MusicBrainz…', 0])
  }

  console.log('\n...the sections\' wait: under the albums once they are drawn, for MusicBrainz and the library, or ABOUT_WAIT_MS (review: none of it was pinned)')
  {
    const PORTISHEAD_SUMMARY = summaryOf('Portishead', 'Portishead', { album_count: 3, track_count: 33, first_year: '1994', last_year: '2008' })
    reset()
    ownedAnswers(LIBRARY)
    const norows = mount({ id: 'ar-portishead-norows' })
    norows.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-norows' })
    await norows.settled()
    answer('facts', FULL)
    answer('summary', PORTISHEAD_SUMMARY)
    await norows.settled()
    check('the library and MusicBrainz answered, MusicBrainz\'s albums still out: no albums yet, so nothing under them', [rowKeys().length, classed('app-artist-more').length], [0, 0])
    check('...not even once ABOUT_WAIT_MS is over - never drawn above albums still to come', [fire(3000) > 0, await norows.settled() && classed('app-artist-more').length], [true, 0])
    fire(1500)
    await norows.settled()
    check('...the albums drawn (ROWS_WAIT_MS): then the sections, in one go', [rowKeys().length > 0, titles()], [true, ['Albums', 'In your library', 'About', 'Line-up']])

    reset()
    ownedAnswers(LIBRARY)
    const slowmb = mount({ id: 'ar-portishead-slowmb' })
    slowmb.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-slowmb' })
    await slowmb.settled()
    answer('discography', DISCOGRAPHY)
    answer('summary', PORTISHEAD_SUMMARY)
    await slowmb.settled()
    check('the albums drawn and the library answered, MusicBrainz\'s facts still out: the sections wait for them', [rowKeys().length, classed('app-artist-more').length], [3, 0])
    fire(1500)
    await slowmb.settled()
    check('...past ROWS_WAIT_MS, still', classed('app-artist-more').length, 0)
    fire(3000)
    await slowmb.settled()
    check('...ABOUT_WAIT_MS over: drawn with what has answered - In your library first, About saying it is asking',
      [titles(), words(find(byClass('app-asking-text'), find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-about-title')[0])[0])],
      [['Albums', 'In your library', 'About'], 'Asking MusicBrainz…'])
    //? the names change once drawn (a folder of theirs filed under another name): what it said stays while it is asked
    W.owned = { index: O.buildOwnedIndex([...A.everyOwned(LIBRARY), { path: 'Portishead Live/Roseland (1998)', artist: 'Portishead Live', album: 'Roseland', release_mbid: ROSELAND, albumartist_mbids: [PORTISHEAD] }]), artists: [] }
    await slowmb.settled()
    check('...their names changing once drawn: what In your library said stays, in its place, while the library is asked again',
      [titles(), factRows()[0], asked('summary').slice(-2).map((one) => one[0])], [['Albums', 'In your library', 'About'], ['Albums', '3'], ['Portishead', 'Portishead Live']])

    reset()
    const late = mount({ id: 'ar-portishead-late' })
    late.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-late' })
    await late.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    await late.settled()
    fire(1500)
    await late.settled()
    check('/library/owned slow (a restart walking a spun-down array): the albums drawn at ROWS_WAIT_MS, the sections waiting for the library', [rowKeys().length, classed('app-artist-more').length], [3, 0])
    fire(3000)
    await late.settled()
    check('...ABOUT_WAIT_MS over: drawn - In your library LAST, saying it is looking, so it can\'t land above About (review)',
      [titles(), words(find(byClass('app-asking-text'), find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-library-title')[0])[0])],
      [['Albums', 'About', 'Line-up', 'In your library'], 'Looking in your library…'])
    ownedAnswers(LIBRARY)
    await late.settled()
    answer('summary', PORTISHEAD_SUMMARY)
    await late.settled()
    check('...the library answering: filled in where it is, under what was already on screen', [titles(), factRows().slice(-5, -4)], [['Albums', 'About', 'Line-up', 'In your library'], [['Albums', '3']]])

    reset()
    const nothing = mount({ id: `mb:${NIRVANA_UK}` })
    nothing.draw()
    answer('libraryArtists', [])
    answer('facts', { ...FULL, mbid: NIRVANA_UK, name: 'Nirvana', links: [], members: [] })
    answer('discography', { 'release-groups': [group('rg-anaesthetic', 'Local Anaesthetic', '1971-01-01')] })
    await nothing.settled()
    fire(1500)
    fire(3000)
    await nothing.settled()
    ownedAnswers(LIBRARY)
    await nothing.settled()
    check('...drawn last and the library having nothing of theirs: said so, in its place', [titles(), words(find(byClass('app-search-empty'), find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-library-title')[0])[0])],
      [['Albums', 'About', 'In your library'], 'Nothing of theirs in your library.'])
  }

  console.log('\n...Artist images…: why it can\'t be used, a tap then refused, and the square on disk only once saved here')
  {
    reset()
    ownedAnswers(YE_LIBRARY)
    const managed = []
    const one = mount({ id: 'ar-kanye-unread', admin: true, onManage: (request) => managed.push(request) })
    one.draw()
    answer('artistAlbums', { id: 'ar-kanye-unread', name: 'Kanye West', album: [nd('nd-donda', 'Donda', 2021, DONDA)] })
    await one.settled()
    answer('discography', { 'release-groups': [group('rg-donda', 'Donda', '2021-08-29')] })
    answer('facts', { ...FULL, mbid: YE, name: 'Ye', links: [], members: [], genres: [], aliases: [] })
    answer('summary', summaryOf('Kanye West', 'Kanye West'), (name) => name === 'Kanye West')
    answer('summary', new Error('deadwax is unreachable'), (name) => name === 'Ye')
    await one.settled()
    check('the library couldn\'t say of the name their pictures go under: In your library from the rest, and Artist images… stepped back, saying why',
      [factRows()[0], manageButtons(), words(classed('app-artist-why')[0])],
      [['Albums', '1'], [['Artist images…', 'true'], ['Move albums to Ye', null]], "deadwax couldn't read their folder just now"])
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Artist images…')[0].props.onClick({ currentTarget: null })
    check('...a tap on it, while it can\'t be used, opens nothing', managed.length, 0)

    reset()
    ownedAnswers(LIBRARY)
    const thumbs = []
    const square = mount({ id: 'ar-portishead-square', admin: true, onManage: (request) => thumbs.push(request) })
    square.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-square' })
    await square.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    answer('summary', summaryOf('Portishead', 'Portishead', { art: { thumb: 'artist.jpg' } }))
    await square.settled()
    check('their square on disk and Navidrome\'s picture: Navidrome\'s shown (its own copy of that square)', typeof classed('app-artist-picture')[0].type, 'function')
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Artist images…')[0].props.onClick({ currentTarget: null })
    thumbs[0].onSaved()
    await square.settled()
    check('...pictures saved here: the square on disk, past the browser\'s cache - Navidrome\'s copy is cached', [classed('app-artist-picture')[0].type, classed('app-artist-picture')[0].props.src],
      ['img', '/deadwax/library/artist/art?artist=Portishead&kind=thumb&v=1'])
  }

  //? review (2.0.0-player.45): a failed /library/artist read drew "nothing of theirs" - or nothing at all
  console.log('\n...the library not answering for their names: said so, with Try again - never "nothing of theirs", never gone')
  {
    const PORTISHEAD_SUMMARY = summaryOf('Portishead', 'Portishead', { album_count: 3, track_count: 33, first_year: '1994', last_year: '2008', art: { fanart: 'fanart.jpg' } })
    const librarySection = () => find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-artist-library-title')[0]
    const retry = () => find(byClass('app-artist-retry'), librarySection())[0]
    reset()
    ownedAnswers(LIBRARY)
    const managed = []
    const one = mount({ id: 'ar-portishead-unread-1', admin: true, onManage: (request) => managed.push(request) })
    one.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-unread-1' })
    await one.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    answer('summary', new Error('deadwax is unreachable'))
    await one.settled()
    check('the library couldn\'t say a word of their one name: In your library drawn all the same, in its place - saying so, with Try again',
      [titles(), words(find(byClass('app-search-empty'), librarySection())[0]), words(retry())],
      [['Albums', 'In your library', 'About', 'Line-up'], "deadwax couldn't read your library just now.", 'Try again'])
    check('...Artist images… still drawn, stepped back, saying why',
      [manageButtons(), words(classed('app-artist-why')[0])], [[['Artist images…', 'true']], "deadwax couldn't read their folder just now"])
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Artist images…')[0].props.onClick({ currentTarget: null })
    check('...a tap on it opening nothing', managed.length, 0)
    const back = mount({ id: 'ar-portishead-unread-1' })
    back.draw()
    check('...and the failure not kept: the page come back to asks the library again rather than drawing it', [rowKeys().length, classed('app-artist-more').length, outstanding('summary').length], [3, 0, 1])
    answer('summary', PORTISHEAD_SUMMARY)
    await back.settled()
    one.draw()
    retry().props.onClick()
    await one.settled()
    check('Try again: the library asked again, the button busy while it is',
      [outstanding('summary').length, retry().props['aria-busy']], [1, true])
    retry().props.onClick()
    await one.settled()
    check('...a second tap meanwhile asking nothing more', outstanding('summary').length, 1)
    answer('summary', PORTISHEAD_SUMMARY)
    await one.settled()
    check('...answered: what the library holds, where the failure was - Artist images… live', [titles(), factRows()[0], manageButtons()],
      [['Albums', 'In your library', 'About', 'Line-up'], ['Albums', '3'], [['Artist images…', null]]])

    reset()
    ownedAnswers(LIBRARY)
    const saved = []
    const two = mount({ id: 'ar-portishead-unread-2', admin: true, onManage: (request) => saved.push(request) })
    two.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-unread-2' })
    await two.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    answer('summary', PORTISHEAD_SUMMARY)
    await two.settled()
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Artist images…')[0].props.onClick({ currentTarget: null })
    saved[0].onSaved()
    await two.settled()
    answer('summary', new Error('deadwax is unreachable'))
    await two.settled()
    check('pictures saved, the library\'s word asked again and not had: what In your library said stays, in its place, saying so - About doesn\'t move up',
      [titles(), factRows()[0], words(classed('app-artist-stale')[0])],
      [['Albums', 'In your library', 'About', 'Line-up'], ['Albums', '3'], "deadwax couldn't read your library just now - this is what it said before. Try again"])
    check('...the hero keeping their picture on disk (asked past the cache), and Artist images… its folder as the library last said',
      [classed('app-artist-picture')[0].props.src, manageButtons()], ['/deadwax/library/artist/art?artist=Portishead&kind=fanart&v=1', [['Artist images…', null]]])
    retry().props.onClick()
    await two.settled()
    answer('summary', PORTISHEAD_SUMMARY)
    await two.settled()
    check('...Try again answered: the note gone', [classed('app-artist-stale').length, factRows()[0]], [0, ['Albums', '3']])
    //? their names changing (a folder of theirs filed under another), and the library answering for none of them
    W.owned = { index: O.buildOwnedIndex([...A.everyOwned(LIBRARY), { path: 'Portishead Live/Roseland (1998)', artist: 'Portishead Live', album: 'Roseland', release_mbid: ROSELAND, albumartist_mbids: [PORTISHEAD] }]), artists: [] }
    await two.settled()
    while (outstanding('summary').length) answer('summary', new Error('deadwax is unreachable'))
    await two.settled()
    check('...their names changing and the library answering for none of them: what it said of the old ones stays, saying so',
      [titles(), factRows()[0], classed('app-artist-stale').length], [['Albums', 'In your library', 'About', 'Line-up'], ['Albums', '3'], 1])

    reset()
    const three = mount({ id: 'ar-portishead-unread-3' })
    three.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-unread-3' })
    await three.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    await three.settled()
    fire(1500)
    fire(3000)
    await three.settled()
    ownedAnswers(LIBRARY)
    await three.settled()
    answer('summary', new Error('deadwax is unreachable'))
    await three.settled()
    check('drawn last (/library/owned slow) and then not answering for them: said so, where it is - never "Nothing of theirs" under their albums',
      [titles(), words(find(byClass('app-search-empty'), librarySection())[0])], [['Albums', 'About', 'Line-up', 'In your library'], "deadwax couldn't read your library just now."])
  }

  //? review: these rules were stated in the notes, and nothing held them there
  console.log('\n...the rules under them: who wins, what the sections wait for, a picture that won\'t load')
  {
    reset()
    const BLEACH = { path: 'Nirvana/Bleach (1989)', artist: 'Nirvana', album: 'Bleach', release_mbid: null, albumartist_mbids: [] }
    ownedAnswers(O.buildOwnedIndex([BLEACH]))
    const managed = []
    const one = mount({ id: 'ar-nirvana-tagged', admin: true, onManage: (request) => managed.push(request) })
    one.draw()
    answer('artistAlbums', { id: 'ar-nirvana-tagged', name: 'Nirvana', album: [nd('nd-bleach', 'Bleach', 1989)] })
    await one.settled()
    while (outstanding('summary').length) answer('summary', summaryOf('Nirvana', 'Nirvana'))
    waitOver()
    await one.settled()
    find((node) => words(node) === 'Which artist is this?' && node.type === 'button')[0].props.onClick({ currentTarget: null })
    managed[0].onChosen({ mbid: NIRVANA_UK, name: 'Nirvana', disambiguation: '60s UK band' })
    await one.settled()
    answer('facts', { ...FULL, mbid: NIRVANA_UK, name: 'Nirvana', disambiguation: '60s UK band', links: [], members: [] })
    await one.settled()
    check('an artist chosen: the page is theirs', [asked('facts').slice(-1), classed('app-artist-chosen').length], [[[NIRVANA_UK]], 1])
    //? an Edit panel apply writes the US band's id into the folder
    W.owned = { index: O.buildOwnedIndex([{ ...BLEACH, albumartist_mbids: [NIRVANA_US] }]), artists: [] }
    await one.settled()
    check('...the files then saying who they are: their word wins over the choice - asked by their id, "You chose" gone',
      [asked('facts').slice(-1), classed('app-artist-chosen').length], [[[NIRVANA_US]], 0])

    reset()
    ownedAnswers(LIBRARY)
    forgetKeptArtist(`mb:${PORTISHEAD}`)
    const slow = mount({ id: `mb:${PORTISHEAD}` })
    slow.draw()
    answer('facts', FULL)
    answer('discography', DISCOGRAPHY)
    await slow.settled()
    while (outstanding('summary').length) answer('summary', summaryOf('Portishead', 'Portishead'))
    await slow.settled()
    fire(1500)
    await slow.settled()
    check('opened from MusicBrainz, Navidrome still looking for them: the albums drawn at ROWS_WAIT_MS, the sections still waiting - Navidrome is the library\'s word too',
      [rowKeys().length, classed('app-artist-more').length, outstanding('libraryArtists').length > 0], [3, 0, true])
    while (outstanding('libraryArtists').length) answer('libraryArtists', [])
    await slow.settled()
    check('...Navidrome answered: drawn', titles(), ['Albums', 'In your library', 'About', 'Line-up'])

    reset()
    ownedAnswers(LIBRARY)
    const pics = []
    const broken = mount({ id: 'ar-portishead-broken', admin: true, onManage: (request) => pics.push(request) })
    broken.draw()
    answer('artistAlbums', { ...PORTISHEAD_ARTIST, id: 'ar-portishead-broken' })
    await broken.settled()
    answer('discography', DISCOGRAPHY)
    answer('facts', FULL)
    answer('summary', summaryOf('Portishead', 'Portishead', { art: { fanart: 'fanart.jpg', logo: 'logo.png' } }))
    await broken.settled()
    const logo = () => find((node) => node.type === 'img' && byClass('app-artist-logo')(node))[0]
    const heroWords = () => words(find((node) => node.type === 'h1' && byClass('app-artist-name')(node))[0])
    check('their background and logo on disk drawn', [classed('app-artist-picture')[0].props.src, logo()?.props.src],
      ['/deadwax/library/artist/art?artist=Portishead&kind=fanart', '/deadwax/library/artist/art?artist=Portishead&kind=logo'])
    classed('app-artist-picture')[0].props.onError()
    logo().props.onError()
    broken.draw()
    check('...neither loading: the hero falls back past them - to Navidrome\'s picture - and their name written out in the logo\'s place',
      [typeof classed('app-artist-picture')[0].type, logo(), heroWords()], ['function', undefined, 'Portishead'])
    find((node) => byClass('app-artist-manage-button')(node) && words(node) === 'Artist images…')[0].props.onClick({ currentTarget: null })
    pics[0].onSaved()
    await broken.settled()
    check('...pictures saved: asked for again, past the cache', classed('app-artist-picture')[0].props.src, '/deadwax/library/artist/art?artist=Portishead&kind=fanart&v=1')
  }

  console.log('\nthe artist page\'s panel: Move albums to …, across every name')
  {
    reset()
    const moved = [], settled = [], closed = []
    const request = { key: 1, mode: 'refile', page: 'ar-kanye', name: 'Kanye West', mbid: YE, currentName: 'Ye', moveNames: ['Kanye West', 'Kanye'], imagesName: 'Ye', version: 0,
      onMoved: (outcome) => moved.push(outcome) }
    const render = hooks.root(RefileBody)
    const props = { request, live: true, onClose: () => closed.push(1), onSettle: (mbid) => settled.push(mbid) }
    const draw = () => { tree = render(props); render.commit(); return tree }
    const drawn = async () => { for (let n = 0; n < 4; n++) { draw(); await settle() } }
    draw()
    check('each name\'s plan asked of the refile route\'s preview, by the artist\'s id, through a latestOnly', asked('refilePreview'), [['Kanye West', YE, true], ['Kanye', YE, true]])
    check('...meanwhile it says so, and Move can\'t be pressed', [words(classed('app-asking-text')[0]), classed('app-artist-panel-primary')[0].props.disabled], ['Working out the moves…', true])
    const plan = (moves, refused = [], problems = []) => ({ current_name: 'Ye', to_folder: 'Ye', artist_mbid: YE, moves, refused, problems, empty: !moves.length })
    answer('refilePreview', plan([{ album: 'Donda', path: 'Kanye West/Donda (2021)', target_path: 'Ye/Donda (2021)', files: 2, retag: [{}, {}] }]), (name) => name === 'Kanye West')
    answer('refilePreview', plan([], [{ album: 'Graduation', path: 'Misc/Graduation (2007)', reason: 'tagged as a different artist' }]), (name) => name === 'Kanye')
    await drawn()
    check('drawn as one: each move (where it is, where it goes, its tracks) and each album that stays, and why',
      [classed('app-artist-move').map((li) => classed('app-artist-move-path').length && words(li)), words(classed('app-artist-panel-primary')[0]), classed('app-artist-panel-primary')[0].props.disabled],
      [['Kanye West/Donda (2021)→ Ye/Donda (2021)2 tracks, 2 retagged', 'Misc/Graduation (2007)stays - tagged as a different artist'], 'Move 1 album', false])
    classed('app-artist-panel-primary')[0].props.onClick()
    draw()
    check('Move: the apply for each name with something to move - the route recomputing its plan - and none for a name with nothing',
      [asked('refileApply'), words(classed('app-artist-panel-primary')[0]), classed('app-artist-panel-primary')[0].props['aria-disabled']],
      [[['Kanye West', YE]], 'Moving…', 'true'])
    answer('refileApply', { plan: {}, results: { moved: [{ from: 'Kanye West/Donda (2021)', to: 'Ye/Donda (2021)' }], failed: [], pictures_moved: [], removed_folders: ['Kanye West'] } })
    await drawn()
    check('moved: the page told (by the artist\'s id, under their name now, the names left empty), the wait for Navidrome begun for the page moved from, and what happened said with Done',
      [moved, settled, words(classed('app-artist-panel-outcome')[0]), words(classed('app-artist-panel-primary')[0])],
      [[{ mbid: YE, name: 'Ye', moved: 1, emptied: ['Kanye West'] }], ['ar-kanye'], 'Moved 1 album into Ye/. Kanye West/ was left empty and removed.', 'Done'])
    classed('app-artist-panel-primary')[0].props.onClick()
    check('...Done closes the panel', closed.length, 1)

    reset()
    const told = []
    const two = hooks.root(RefileBody)
    const twoProps = { request: { ...request, moveNames: ['Kanye West', 'Kanye'], onMoved: (outcome) => told.push(outcome) }, live: true, onClose: () => {} }
    const drawTwo = async () => { for (let n = 0; n < 4; n++) { tree = two(twoProps); two.commit(); await settle() } }
    await drawTwo()
    answer('refilePreview', plan([{ album: 'Donda', path: 'Kanye West/Donda (2021)', target_path: 'Ye/Donda (2021)', files: 2, retag: [] }]), (name) => name === 'Kanye West')
    answer('refilePreview', plan([{ album: 'Graduation', path: 'Kanye/Graduation (2007)', target_path: 'Ye/Graduation (2007)', files: 3, retag: [] }]), (name) => name === 'Kanye')
    await drawTwo()
    classed('app-artist-panel-primary')[0].props.onClick()
    await drawTwo()
    check('two names to move: one at a time - the second only once the first has answered', asked('refileApply'), [['Kanye West', YE]])
    answer('refileApply', { plan: {}, results: { moved: [{ from: 'a', to: 'b' }], failed: [], pictures_moved: [], removed_folders: [] } })
    await drawTwo()
    check('...then the second', asked('refileApply'), [['Kanye West', YE], ['Kanye', YE]])
    twoProps.live = false
    await drawTwo()
    answer('refileApply', { plan: {}, results: { moved: [], failed: [{ album: 'Graduation', reason: "a tag wouldn't write" }], pictures_moved: [], removed_folders: [] } })
    await drawTwo()
    check('closed while the move was out: the page still told what moved - the outcome not drawn into a closed panel - and Kanye, whose album didn\'t, not left empty',
      [told, classed('app-artist-panel-outcome').length], [[{ mbid: YE, name: 'Ye', moved: 1, emptied: ['Kanye West'] }], 0])

    reset()
    const stuck = hooks.root(RefileBody)
    const stuckProps = { request: { ...request, moveNames: ['Kanye West'] }, live: true, onClose: () => {} }
    tree = stuck(stuckProps); stuck.commit()
    answer('refilePreview', plan([{ album: 'Donda', path: 'Kanye West/Donda (2021)', target_path: 'Ye/Donda (2021)', files: 2, retag: [] }], [], ['MusicBrainz could not be reached just now']))
    for (let n = 0; n < 4; n++) { tree = stuck(stuckProps); stuck.commit(); await settle() }
    check('a problem: said, and Move can\'t be pressed', [classed('is-warning').map(words), classed('app-artist-panel-primary')[0].props.disabled], [['MusicBrainz could not be reached just now'], true])

    //? review: what the loop does when nothing moved, when an apply fails, and what an apply's own plan refuses
    const body = (moveNames, more = {}) => {
      const told = [], waits = []
      const root = hooks.root(RefileBody)
      const props = { request: { ...request, moveNames, onMoved: (outcome) => told.push(outcome) }, live: true, onClose: () => {}, onSettle: (page) => waits.push(page), ...more }
      const drawn = async () => { for (let n = 0; n < 4; n++) { tree = root(props); root.commit(); await settle() } }
      return { told, waits, drawn }
    }
    const donda = { album: 'Donda', path: 'Kanye West/Donda (2021)', target_path: 'Ye/Donda (2021)', files: 2, retag: [] }
    const failures = () => classed('app-artist-panel-outcome').flatMap((node) => find(byClass('is-warning'), node)).map(words)

    reset()
    const none = body(['Kanye West'])
    await none.drawn()
    answer('refilePreview', plan([donda]))
    await none.drawn()
    classed('app-artist-panel-primary')[0].props.onClick()
    await none.drawn()
    answer('refileApply', { plan: plan([donda]), results: { moved: [], failed: [{ album: 'Donda', reason: "a tag wouldn't write: Permission denied" }], pictures_moved: [], removed_folders: [] } })
    await none.drawn()
    check('nothing moved (every tag refused): the page not told and no wait begun - nothing changed - and why said',
      [none.told, none.waits, words(find(byClass('app-artist-panel-note'), classed('app-artist-panel-outcome')[0])[0]), failures()],
      [[], [], 'Nothing was moved.', ["Donda: a tag wouldn't write: Permission denied"]])

    reset()
    const broke = body(['Kanye West', 'Kanye'])
    await broke.drawn()
    answer('refilePreview', plan([donda]), (name) => name === 'Kanye West')
    answer('refilePreview', plan([{ album: 'Graduation', path: 'Kanye/Graduation (2007)', target_path: 'Ye/Graduation (2007)', files: 3, retag: [] }]), (name) => name === 'Kanye')
    await broke.drawn()
    classed('app-artist-panel-primary')[0].props.onClick()
    await broke.drawn()
    answer('refileApply', new Error('deadwax is unreachable'))
    await broke.drawn()
    check('an apply that fails: none after it (what the preview said is no longer what is on disk), and the failure said',
      [asked('refileApply').map((one) => one[0]), broke.told, failures()], [['Kanye West'], [], ['deadwax is unreachable']])

    reset()
    const same = body(['Kanye', 'Kanye West'])
    await same.drawn()
    answer('refilePreview', plan([{ album: 'Graduation', path: 'Kanye/Graduation (2007)', target_path: 'Ye/Graduation (2007)', files: 3, retag: [] }]), (name) => name === 'Kanye')
    answer('refilePreview', plan([{ album: 'Graduation', path: 'Kanye West/Graduation (2007)', target_path: 'Ye/Graduation (2007)', files: 3, retag: [] }]), (name) => name === 'Kanye West')
    await same.drawn()
    check('two names moving folders of one name to one place: one move shown, the other staying and why - "Move 1 album"',
      [classed('app-artist-move').map(words), words(classed('app-artist-panel-primary')[0])],
      [['Kanye/Graduation (2007)→ Ye/Graduation (2007)3 tracks', "Kanye West/Graduation (2007)stays - another album moves to 'Ye/Graduation (2007)'"], 'Move 1 album'])
    classed('app-artist-panel-primary')[0].props.onClick()
    await same.drawn()
    answer('refileApply', { plan: plan([]), results: { moved: [{ from: 'Kanye/Graduation (2007)', to: 'Ye/Graduation (2007)' }], failed: [], pictures_moved: [], removed_folders: ['Kanye'] } })
    await same.drawn()
    check('...only the name with a move applied; the page told Kanye is empty, Kanye West not', [asked('refileApply').map((one) => one[0]), same.told.map((one) => one.emptied), same.waits],
      [['Kanye'], [['Kanye']], ['ar-kanye']])

    reset()
    const raced = body(['Kanye West'])
    await raced.drawn()
    answer('refilePreview', plan([donda]))
    await raced.drawn()
    classed('app-artist-panel-primary')[0].props.onClick()
    await raced.drawn()
    answer('refileApply', { plan: plan([], [{ album: 'Donda', path: 'Kanye West/Donda (2021)', reason: "'Ye/Donda (2021)' is already there" }]), results: { moved: [], failed: [], pictures_moved: [], removed_folders: [] } })
    await raced.drawn()
    check('an album the preview showed moving that the apply\'s own plan kept where it is: said, never dropped',
      [raced.told, failures()], [[], ["Donda: stays - 'Ye/Donda (2021)' is already there"]])

    reset()
    const stays = body(['Kanye West'])
    await stays.drawn()
    answer('refilePreview', plan([], [{ album: 'Donda', path: 'Kanye West/Donda (2021)', reason: "'03 Three.flac' can't be read, so its tags can't be written" }]))
    await stays.drawn()
    check('every album staying: each said with why, nothing to press - never "every album is already filed under Ye"',
      [classed('app-artist-move').map(words), classed('app-artist-panel-note').map(words).slice(-1), classed('app-artist-panel-primary')[0].props.disabled],
      [["Kanye West/Donda (2021)stays - '03 Three.flac' can't be read, so its tags can't be written"], ['Nothing can move - every album stays where it is, for the reason beside it.'], true])
    reset()
    const none2 = body(['Kanye West'])
    await none2.drawn()
    answer('refilePreview', plan([]))
    await none2.drawn()
    check('...and with nothing left under the old name at all, that it is all filed under Ye', classed('app-artist-panel-note').map(words).slice(-1), ['Nothing to move - every album is already filed under Ye.'])
  }

  console.log('\nthe artist page\'s panel: Artist images…')
  {
    reset()
    const saved = []
    const request = { key: 2, mode: 'images', page: 'ar-ye', name: 'Ye', mbid: YE, currentName: 'Ye', moveNames: [], imagesName: 'Ye', version: 0, onSaved: () => saved.push(1) }
    const render = hooks.root(ImagesBody)
    const props = { request, live: true }
    const drawn = async () => { for (let n = 0; n < 4; n++) { tree = render(props); render.commit(); await settle() } }
    await drawn()
    check('the pictures asked for, of the folder\'s name, by the artist\'s id, through a latestOnly', asked('imagesPreview'), [['Ye', YE, true]])
    const thumb = { kind: 'thumb', url: 'https://c/a.jpg', preview: 'https://c/a.jpg?w=600', source: 'wikidata', label: 'Wikidata image' }
    const banner = { kind: 'banner', url: 'https://f/b.jpg', preview: 'https://f/b.jpg', source: 'theaudiodb', label: 'TheAudioDB Banner' }
    const preview = {
      artist: 'Ye', path: 'Ye', folder_problem: null, album_count: 1, track_count: 2, total_size: 1, first_year: '2025', last_year: '2025', albums: [], art: { thumb: 'artist.jpg' },
      mbid: YE, mbid_source: 'given', matches: [], facts: { name: 'Ye', disambiguation: 'US rapper' }, candidates: [thumb, banner], best: { thumb, banner },
      kinds: [{ kind: 'thumb', label: 'Square image' }, { kind: 'banner', label: 'Banner' }, { kind: 'fanart', label: 'Background' }], plan: null,
      sources: { fanarttv: false, theaudiodb: true }, has_key: true, problems: [],
    }
    answer('imagesPreview', preview)
    await drawn()
    check('who the pictures are of, with Not them?', words(classed('app-artist-panel-who')[0]), 'Showing Ye (US rapper) Not them?')
    check('the note on the key not set', classed('app-artist-panel-note').map(words).some((text) => text.startsWith('fanart.tv isn\'t set up')), true)
    check('each slot: its name, the file on disk or none found, and Use another picture',
      classed('app-artist-slot').map((slot) => [words(find((node) => node.type === 'h3', slot)[0]), words(find((node) => byClass('app-artist-slot-line')(node), slot)[0] ?? ''), words(find((node) => byClass('app-artist-slot-more')(node), slot)[0] ?? '')]),
      [['Square image', 'artist.jpg on disk', 'Use another picture (1)'], ['Banner', '', 'Use another picture (1)'], ['Background', 'none found for this', 'Use another picture (2)']])
    const options = () => classed('app-artist-option').map((node) => [node.props['aria-label'], node.props['aria-pressed']])
    check('the best of each chosen to start with', options(), [['Wikidata image, from wikidata', true], ['TheAudioDB Banner, from theaudiodb', true]])
    classed('app-artist-option')[0].props.onClick()
    find((node) => byClass('app-artist-slot-more')(node))[2].props.onClick()
    await drawn()
    check('a tap on a chosen picture leaves its slot as it is; Use another picture puts any picture in any slot',
      [options(), find((node) => byClass('app-artist-slot-more')(node))[2].props['aria-expanded']],
      [[['Wikidata image, from wikidata', false], ['TheAudioDB Banner, from theaudiodb', true], ['Wikidata image, from wikidata', false], ['TheAudioDB Banner, from theaudiodb', false]], true])
    classed('app-artist-option')[2].props.onClick()
    find((node) => byClass('app-artist-replace-box')(node))[0].props.onChange({ currentTarget: { checked: true } })
    await drawn()
    classed('app-artist-panel-primary')[0].props.onClick()
    await drawn()
    check('Save: the pictures chosen, by slot, the artist\'s id and Replace - the route honours only what their sources offered',
      asked('imagesApply'), [['Ye', { banner: banner.url, fanart: thumb.url }, { artistMbid: YE, replace: true }]])
    answer('imagesApply', { artist: 'Ye', path: 'Ye', results: { mode: 'apply', dry_run: false, written: ['banner.jpg', 'fanart.jpg'], skipped: [], problems: [] }, art: { thumb: 'artist.jpg', banner: 'banner.jpg', fanart: 'fanart.jpg' } })
    await drawn()
    check('saved: said, the page told, and the slots now say the files are on disk',
      [words(classed('app-artist-panel-said')[0]), saved.length, words(find((node) => byClass('app-artist-slot-line')(node))[1])],
      ['Saved banner.jpg, fanart.jpg.', 1, 'banner.jpg on disk'])
    check('each picture in a box of its slot\'s shape - square for the square, wide for the rest, whatever the picture - so one loading moves nothing',
      classed('app-artist-slot').map((slot) => [...new Set(find((node) => node.type === 'img', slot).map((node) => node.props.class))]),
      [['app-artist-option-image is-square'], ['app-artist-option-image'], ['app-artist-option-image']])

    //? review: Save, while another artist's pictures were coming or after that look failed, wrote the last artist's
    find((node) => byClass('app-artist-panel-inline')(node))[0].props.onClick()
    await drawn()
    find((node) => node.type === 'form' && byClass('app-artist-search')(node))[0].props.onSubmit({ preventDefault() {} })
    await drawn()
    check('Not them?: a search for the name, its button busy while it is out - Save still live, the pictures still the ones shown',
      [asked('artistSearch').slice(-1), find((node) => node.type === 'button' && node.props.type === 'submit')[0].props['aria-busy'], classed('app-artist-panel-primary')[0].props.disabled],
      [[['Ye', true]], true, false])
    answer('artistSearch', { query: 'Ye', matches: [{ mbid: NIRVANA_UK, name: 'Nirvana', disambiguation: '60s UK band', country: 'GB', type: 'Group', matched_as: 'Nirvana' }] })
    await drawn()
    matchRows()[0].props.onClick()
    await drawn()
    check('another artist picked: their pictures asked for - and meanwhile Save can\'t be pressed, the slots giving way to saying whose pictures are coming',
      [asked('imagesPreview').slice(-1), classed('app-artist-panel-primary')[0].props.disabled, words(classed('app-asking-text')[0]), classed('app-artist-slot').length, classed('app-artist-panel-who').length],
      [[['Ye', NIRVANA_UK, true]], true, 'Looking for pictures of Nirvana…', 0, 0])
    classed('app-artist-panel-primary')[0].props.onClick()
    await drawn()
    check('...a press on it then sends nothing', asked('imagesApply').length, 1)
    answer('imagesPreview', new Error('fanart.tv is unreachable'))
    await drawn()
    check('...the look failing: said, with Try again - and Save still can\'t be pressed, nothing it would write on screen',
      [classed('is-warning').map(words), classed('app-artist-panel-primary')[0].props.disabled], [['fanart.tv is unreachable'], true])
    find((node) => node.type === 'button' && words(node) === 'Try again')[0].props.onClick()
    check('...Try again asks again for the artist last picked, not the page\'s', asked('imagesPreview').slice(-1), [['Ye', NIRVANA_UK, true]])

    reset()
    const shut = hooks.root(ImagesBody)
    const shutProps = { request: { ...request, onSaved: () => saved.push(2) }, live: true }
    const drawShut = async () => { for (let n = 0; n < 4; n++) { tree = shut(shutProps); shut.commit(); await settle() } }
    await drawShut()
    answer('imagesPreview', preview)
    await drawShut()
    classed('app-artist-panel-primary')[0].props.onClick()
    shutProps.live = false
    await drawShut()
    answer('imagesApply', { artist: 'Ye', path: 'Ye', results: { mode: 'apply', dry_run: false, written: ['artist.jpg'], skipped: [], problems: [] }, art: { thumb: 'artist.jpg' } })
    await drawShut()
    check('closed while a save was out: the page still told - what it says not drawn into a closed panel', [saved.slice(-1), words(classed('app-artist-panel-said')[0])], [[2], ''])

    reset()
    const ambiguous = hooks.root(ImagesBody)
    const ambiguousProps = { request: { ...request, mbid: null, name: 'Nirvana', imagesName: 'Nirvana' }, live: true }
    const drawAmbiguous = async () => { for (let n = 0; n < 4; n++) { tree = ambiguous(ambiguousProps); ambiguous.commit(); await settle() } }
    await drawAmbiguous()
    const m1 = { mbid: NIRVANA_US, name: 'Nirvana', disambiguation: '90s US grunge band', country: 'US', type: 'Group', matched_as: 'Nirvana' }
    const m2 = { mbid: NIRVANA_UK, name: 'Nirvana', disambiguation: '60s UK band', country: 'GB', type: 'Group', matched_as: 'Nirvana' }
    answer('imagesPreview', { ...preview, mbid: null, facts: null, candidates: [], best: {}, matches: [m1, m2], problems: ['more than one artist in MusicBrainz goes by this name'] })
    await drawAmbiguous()
    check('nobody can say who: said, the search open, MusicBrainz\'s artists of the name to choose from - Save not live',
      [classed('is-warning').map(words), matchRows().map(words), classed('app-artist-panel-primary')[0].props.disabled],
      [['more than one artist in MusicBrainz goes by this name'], ['Nirvana90s US grunge band · Group · US', 'Nirvana60s UK band · Group · GB'], true])
    matchRows()[1].props.onClick()
    await drawAmbiguous()
    check('...one chosen: their pictures asked for by its id', asked('imagesPreview').slice(-1), [['Nirvana', NIRVANA_UK, true]])
  }

  console.log('\nthe artist page\'s panel: Which artist is this?')
  {
    reset()
    const chosen = [], closed = []
    const render = hooks.root(WhoBody)
    const props = { request: { key: 3, mode: 'who', page: 'ar-nirvana', name: 'Nirvana', mbid: null, currentName: null, moveNames: [], imagesName: null, version: 0, onChosen: (match) => chosen.push(match) }, live: true, onClose: () => closed.push(1) }
    const drawn = async () => { for (let n = 0; n < 4; n++) { tree = render(props); render.commit(); await settle() } }
    await drawn()
    check('the page\'s name searched as it opens, through a latestOnly', asked('artistSearch'), [['Nirvana', true]])
    answer('artistSearch', { query: 'Nirvana', matches: [
      { mbid: NIRVANA_US, name: 'Nirvana', disambiguation: '90s US grunge band', country: 'US', type: 'Group', matched_as: 'Nirvana' },
      { mbid: YE, name: 'Ye', disambiguation: 'US rapper', country: 'US', type: 'Person', matched_as: 'Kanye West' }] })
    await drawn()
    check('each with what tells them apart - and the name an alias matched', matchRows().map(words),
      ['Nirvana90s US grunge band · Group · US', 'Yeas Kanye West · US rapper · Person · US'])
    matchRows()[0].props.onClick()
    check('one chosen: the page told, and the panel closed', [chosen, closed.length], [[{ mbid: NIRVANA_US, name: 'Nirvana', disambiguation: '90s US grunge band' }], 1])

    reset()
    const shut = hooks.root(WhoBody)
    const shutProps = { ...props, live: true }
    const drawShut = async () => { for (let n = 0; n < 4; n++) { tree = shut(shutProps); shut.commit(); await settle() } }
    await drawShut()
    shutProps.live = false
    await drawShut()
    answer('artistSearch', { query: 'Nirvana', matches: [{ mbid: NIRVANA_US, name: 'Nirvana', disambiguation: '', country: 'US', type: 'Group', matched_as: 'Nirvana' }] })
    await drawShut()
    check('closed while its search was out: the answer not drawn into a closed panel', matchRows().length, 0)
  }

  console.log('\nthe artist page\'s panel itself: a sheet on a phone, a side panel on a desktop')
  {
    reset()
    const request = { key: 4, mode: 'refile', page: 'ar-kanye', name: 'Kanye West', mbid: YE, currentName: 'Ye', moveNames: ['Kanye West'], imagesName: 'Ye', version: 0 }
    //? each drawn by a root of its own (it has hooks: useRef, and useSheet's stand-in, which notes what it was asked)
    const drawPanel = (props) => hooks.root(ArtistPanel)(props)
    const sheet = drawPanel({ open: true, request, opener: { current: null }, onClose: () => {}, panel: 'sheet' })
    const box = (tree) => find((node) => byClass('app-artist-panel')(node), tree)[0]
    check('a phone\'s: modal, its own scroll lock, focus to its close button', [W.sheets[0].modal, W.sheets[0].lockClass, sheet.props.class, box(sheet).props['aria-modal'], box(sheet).props.tabIndex],
      [true, 'app-artist-panel-open', 'app-layer app-artist-panel-layer is-open', 'true', undefined])
    check('...titled for its job, and for whom', [words(find((node) => node.type === 'h2', sheet)[0]), words(find((node) => node.type === 'p', sheet)[0])], ['Move albums', 'Kanye West → Ye'])
    const panel = drawPanel({ open: true, request: { ...request, mode: 'images' }, opener: { current: null }, onClose: () => {}, panel: 'column' })
    check('a desktop\'s: a panel beside the page - not modal, its box a tab stop', [W.sheets[1].modal, panel.props.class, box(panel).props['aria-modal'], box(panel).props.tabIndex],
      [false, 'app-layer app-artist-panel-layer is-open is-panel is-column', 'false', -1])
    const shut = drawPanel({ open: false, request, opener: { current: null }, onClose: () => {}, panel: 'drawer', covered: false })
    const under = drawPanel({ open: true, request, opener: { current: null }, onClose: () => {}, panel: 'drawer', covered: true })
    check('inert while closed, and under the visualizer', [shut.props.inert, under.props.inert, W.sheets[3].covered], [true, true, true])
    const subtitle = (more) => words(find((node) => byClass('app-artist-panel-subtitle')(node), drawPanel({ open: true, request: { ...request, ...more }, opener: { current: null }, onClose: () => {}, panel: 'sheet' }))[0])
    check('...the names whose albums move, never the page\'s own (review: "Ye → Ye" on Ye\'s page)',
      [subtitle({ name: 'Ye', moveNames: ['Kanye West'] }), subtitle({ name: 'Ye', moveNames: ['Kanye', 'Kanye West'] }), subtitle({ mode: 'images', name: 'Ye' })],
      ['Kanye West → Ye', 'Kanye and Kanye West → Ye', 'Ye'])
  }
}

;(async () => {
  while (later.length) {
    await settle()
    later.shift()()
  }
  await page()
  await manage()
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()

