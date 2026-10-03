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
 * Run it with:  node ui/test/artist.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-artist-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/artistPage.ts', 'src/lib/idBridge.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const A = require(path.join(OUT, 'lib/artistPage.js'))
const B = require(path.join(OUT, 'lib/idBridge.js'))
const O = require(path.join(OUT, 'lib/owned.js'))

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
  check('by name: Navidrome\'s own order, untouched', A.sortArtists(artists, 'name').map((a) => a.name), ['Massive Attack', 'Portishead', 'The Beatles', 'Tricky'])
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

/* ===== the page itself: app/ArtistPage.tsx, rendered with every answer given by hand ===== */

const PAGE = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-artist-page-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/ArtistPage.tsx', '--rootDir', 'src', '--outDir', PAGE,
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
write('app/useSheet.js', `exports.takeOpener = (event) => event?.currentTarget ?? null\n`)
write('app/useOwned.js', `
exports.ownedNow = () => globalThis.__page.owned
exports.useOwned = () => globalThis.__page.owned
exports.whenOwned = () => globalThis.__page.owned ? Promise.resolve() : new Promise((resolve) => globalThis.__page.ownedWaiting.push(resolve))
`)

const W = globalThis.__page = {
  asks: [], open: [], owned: null, ownedWaiting: [], indexAge: 0, plays: [], remembered: [],
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
  W.asks.length = 0; W.open.length = 0; W.owned = null; W.ownedWaiting.length = 0; W.indexAge = 0; W.plays.length = 0; W.remembered.length = 0
  W.pins = { pins: [], known: true, canSave: true, problem: null }; W.pinned.length = 0; W.said.length = 0
}

//? the albums' wait (ROWS_WAIT_MS): a timer the test fires by hand
const timers = []
globalThis.setTimeout = (fn) => { const timer = { fn, live: true }; timers.push(timer); return timer }
globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
const waitOver = () => { for (const timer of timers.splice(0)) if (timer.live) timer.fn() }

const hooks = require(path.join(PAGE, 'node_modules/preact/hooks.js'))
const { ArtistPage, PREFETCH_AT_ONCE } = require(path.join(PAGE, 'app/ArtistPage.js'))
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

;(async () => {
  while (later.length) {
    await settle()
    later.shift()()
  }
  await page()
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()

