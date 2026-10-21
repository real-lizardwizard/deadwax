/**
 * "In your library" meaning YOURS, and the Library as yours with Browse for the store (2.0.0-player.52, step 6
 * of the multi-user plan) - the pure rules, pinned:
 *
 *  - lib/whose.ts: the words ("in your library" / "in the store"), whose a Navidrome album is (starred by you,
 *    or held by your library), and the album page's badge and what it offers (Add, Remove, a line saying why
 *    neither) - logins off as it always was;
 *  - THE CONTRADICTION step 5 saw on the real page never again: an album page's meta line saying "in your
 *    library" above a store line saying "In the store, not in your library" - with one pressing in the store
 *    (none yours: "in the store") and with two (review: one yours, the store's on screen: "another pressing in
 *    your library"), the page passing the meta line that place (read off ReleaseGroupPage.tsx) - and (second
 *    review) a library answer kept from earlier in the session never outvoting the store line's fresh word
 *    (withStoreLine; group.sim renders it, logins on);
 *  - Search's words and rows, the pressing picker's marks and its filter, the artist page's rows and its play
 *    line, "The store also has another pressing", Info's count - each "in the store" for what isn't yours, and
 *    each as it was with logins off - except (2.0.0-player.55) Search's library rows, which say "in your library"
 *    with logins off too (libraryPlace): the half titles that said it are gone;
 *  - lib/yourLibrary.ts and lib/shelves.ts: your albums in the orders that existed (2.0.0-player.59: shelves.sim
 *    holds all seven), and your artists;
 *  - lib/appFrame.ts: the Library's views and Browse's with a library of your own, and with logins off exactly
 *    the views and titles it always had;
 *  - (second review) the WIRING, read off each component, element by element: every page takes `personal` from
 *    hasLibrary() and hands it to the rule that needs it - the album page's albumMine and Add, the Library's
 *    three views of yours and Browse's two, the sidebar's Browse group, Search's words, counts and places, the
 *    artist page's heading, rows, ticks and Play line, Info's - so a page quietly drawn as logins-off fails here;
 *  - your albums asked again after an Add or a Remove, and NOT after a filing (second review: it emptied the
 *    grid and lost its place for nothing) - run against the real module, which since 2.0.0-player.59 is
 *    app/albumIndex.ts's `yours` list (one /album_index ask), the list it had kept to draw while a new one comes.
 *
 * Run it with:  node ui/test/whose.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-whose-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/whose.ts', 'src/lib/yourLibrary.ts', 'src/lib/searchResults.ts', 'src/lib/pressings.ts', 'src/lib/artistPage.ts',
  'src/lib/candidates.ts', 'src/lib/perPerson.ts', 'src/lib/appFrame.ts', 'src/lib/aboutRows.ts', 'src/lib/owned.ts',
  'src/app/useYourAlbums.ts', 'src/app/albumIndex.ts', 'src/lib/shelves.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

//? your albums' module runs here as it is (the end of this sim): Preact's hooks and the player's API stood in
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `exports.useState = (v) => [v, () => {}]\nexports.useEffect = () => {}\n`)
fs.writeFileSync(path.join(OUT, 'player/api.js'), `
exports.albumIndexOf = (scope) => {
  globalThis.__whose.asks.push(scope)
  const albums = globalThis.__whose.albums
  //? each ask lands when the test says - the oldest first (land), or the newest (landNewest)
  //? (review) failNext: the next ask fails as it lands (Navidrome briefly away)
  const fail = globalThis.__whose.failNext
  globalThis.__whose.failNext = false
  return new Promise((resolve, reject) => { globalThis.__whose.lands.push(() => (fail ? reject(new Error('Navidrome is away')) : resolve({ albums, truncated: false }))) })
}
`)
globalThis.__whose = { asks: [], albums: [], lands: [], land: () => globalThis.__whose.lands.shift()(), landNewest: () => globalThis.__whose.lands.pop()() }

const load = (file) => require(path.join(OUT, file))
const W = load('lib/whose.js'), Y = load('lib/yourLibrary.js'), S = load('lib/searchResults.js'), P = load('lib/pressings.js')
const A = load('lib/artistPage.js'), C = load('lib/candidates.js'), PP = load('lib/perPerson.js'), F = load('lib/appFrame.js')
const O = load('lib/owned.js'), SH = load('lib/shelves.js')
const read = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

//? the store: Dummy (yours), Third (the store's), and a folder deadwax couldn't say of (logins off: no `yours`)
const REL_DUMMY = '11111111-1111-4111-8111-111111111111', REL_THIRD = '22222222-2222-4222-8222-222222222222'
const DUMMY = { path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_mbid: REL_DUMMY, release_group_mbid: 'rg-dummy', yours: true }
const THIRD = { path: 'Portishead/Third (2008)', artist: 'Portishead', album: 'Third', release_mbid: REL_THIRD, release_group_mbid: 'rg-third', yours: false }
const index = O.buildOwnedIndex([DUMMY, THIRD])
const offIndex = O.buildOwnedIndex([{ ...DUMMY, yours: undefined }, { ...THIRD, yours: undefined }])

console.log('the words: yours, the store - and with logins off, your library as ever')
check('a held album not yours, with a library of your own, is in the store; yours, in your library',
  [W.heldPhrase(true, false), W.heldPhrase(true, true), W.heldLabel(true, false), W.heldLabel(true, true)],
  ['in the store', 'in your library', 'In the store', 'In your library'])
check('...with logins off (or break-glass) everything the store has is in your library',
  [W.heldPhrase(false, false), W.heldPhrase(false, true), W.heldLabel(false, false)], ['in your library', 'in your library', 'In your library'])
check('...and a `yours` the server left out (it couldn\'t read your library) never reads "not yours"',
  [W.heldPhrase(true, undefined), W.isYours({}), W.anyYours([{ yours: false }, {}]), W.anyYours([{ yours: false }])], ['in your library', true, true, false])
//? (2.0.0-player.53, review) a song's album held only as a pressing nothing says has the song or hasn't: "a pressing", in the same words
check('a pressing held that nothing says has a song\'s song or hasn\'t: "a pressing in your library", the store\'s with a library of your own - never "another" (second review)',
  [W.pressingHeldPhrase(true, false), W.pressingHeldPhrase(true, true), W.pressingHeldPhrase(false, false), W.pressingHeldPhrase(true, undefined)],
  ['a pressing in the store', 'a pressing in your library', 'a pressing in your library', 'a pressing in your library'])

console.log('\nwhose an album as Navidrome answers it is: starred by you, or held by your library')
check('starred by you is yours, whatever the library says - Amperfy\'s star before deadwax reads it back',
  W.navidromeYours({ starred: '2026-10-15T09:00:00Z', musicBrainzId: REL_THIRD }, index), true)
check('held by your library is yours; held by the store alone is not; not held at all is not',
  [W.navidromeYours({ musicBrainzId: REL_DUMMY }, index), W.navidromeYours({ musicBrainzId: REL_THIRD }, index), W.navidromeYours({ musicBrainzId: 'rel-x' }, index)],
  [true, false, false])
check('...nothing said while the library hasn\'t answered - and a folder whose `yours` wasn\'t sent counts as yours',
  [W.navidromeYours({ musicBrainzId: REL_THIRD }, null), W.navidromeYours({ musicBrainzId: REL_THIRD }, offIndex)], [null, true])
check('a row\'s place: said only with a library of your own, and only once it can be told',
  [W.navidromePlace(true, true), W.navidromePlace(true, false), W.navidromePlace(true, null), W.navidromePlace(false, false)],
  ['in your library', 'in the store', '', ''])

console.log('\nthe album page: whose it is, and Add or Remove')
const page = (over) => W.albumMine({ personal: true, starred: false, storeDone: true, bridgeFailed: false, bridgeYours: false, present: 1,
  release: 'rel-third', releaseSaid: 'rel-third', changed: null, ...over })
const mine = (yours, badge, action, note, pending = false) => ({ yours, badge, action, note, pending })
check('logins off: "In your library", nothing offered - as it always was',
  W.albumMine({ personal: false, starred: null, storeDone: false, bridgeYours: undefined, present: 1, release: 'r', changed: null }),
  mine(true, 'In your library', null, null))
check('the store\'s, not yours: "In the store" and Add to my library, with what Add does',
  page({}), mine(false, 'In the store', 'add', W.ADD_FROM_PAGE))
check('yours by the bridge, or starred by you: "In your library" and Remove',
  [page({ bridgeYours: true }), page({ starred: true })].map((m) => [m.badge, m.action]), [['In your library', 'remove'], ['In your library', 'remove']])
check('...starred by the album\'s own answer even before the bridge has answered', page({ starred: true, storeDone: false, bridgeYours: undefined }),
  mine(true, 'In your library', 'remove', null))
check('not yours with no release id to keep it by: no Add, and the line says why',
  page({ release: null, releaseSaid: '', present: 0, bridgeYours: undefined }), mine(false, 'In the store', null, W.NO_RELEASE_TO_ADD))
check('...nor with a release the store has no folder of - and the line says that, never "no release id" (review)',
  [page({ present: 0, bridgeYours: undefined }), page({ present: 0, bridgeYours: false })],
  [mine(false, 'In the store', null, W.NOT_FOUND_TO_ADD), mine(false, 'In the store', null, W.NOT_FOUND_TO_ADD)])
check('the bridge unable to say (a folder, no `yours`): "In the store" - true either way - and nothing offered',
  page({ bridgeYours: undefined }), mine(null, 'In the store', null, null))
check('...nor once the bridge has FAILED - never the "no release id" line for a check that couldn\'t be made (review)',
  [page({ bridgeFailed: true, release: null, present: 0, bridgeYours: undefined }), page({ bridgeFailed: true, release: null, releaseSaid: null, present: 0, bridgeYours: undefined }),
    page({ bridgeFailed: true, release: null, releaseSaid: '', present: 0, bridgeYours: undefined })],
  [mine(null, 'In the store', null, null), mine(null, 'In the store', null, null), mine(null, 'In the store', null, null)])
check('...nor when the bridge found no release where Navidrome names one',
  page({ release: null, releaseSaid: 'rel-third', present: 0, bridgeYours: undefined }), mine(null, 'In the store', null, null))
check('...nor before the bridge has answered - said to be on its way, so its place is held',
  page({ storeDone: false, bridgeYours: undefined }), mine(null, 'In the store', null, null, true))
check('...nor before the album\'s own answer - a list\'s tile is never read for `starred` (review: one from before a Remove)',
  [page({ starred: null }), page({ starred: null, bridgeYours: false, storeDone: true })], [mine(null, 'In the store', null, null, true), mine(null, 'In the store', null, null, true)])
{
  const album = read('player/AlbumPage.tsx')
  check('the page passes the album\'s own answer\'s `starred`, the failed bridge and Navidrome\'s release - no preview',
    [/starred: album \? !!album\.starred : error \? false : null,/.test(album), /bridgeFailed: storeFailed,/.test(album),
      /releaseSaid: album \? album\.musicBrainzId \?\? '' : null,/.test(album), /shown\?\.starred/.test(album)], [true, true, true, false])
  check('...and holds the line\'s place while it is pending under songs already drawn, unseen',
    [/\{mine\.pending && album && !mineRefused && \(\s*<div class="app-album-mine is-waiting" aria-hidden="true">/.test(album),
      /<div class=\{`app-album-chips\$\{storeDone && !mine\.pending \? '' : ' is-waiting'\}`\}>/.test(album)], [true, true])
  const css = fs.readFileSync(path.join(UI, '..', 'interface', 'player', 'app.css'), 'utf8')
  check('...the held place unseen; "In the store" no box - and beside an Also chip it gives way whole, never an empty box',
    [/\.app-album-mine\.is-waiting \{ visibility: hidden; \}/.test(css), /\.app-held-badge\.is-store \{\s*padding: 0;\s*border-color: transparent;\s*background: transparent;/.test(css),
      /\.app-held-badge:not\(\.is-store\) \.app-held-badge-text \{/.test(css), /:has\(\.app-other-pressings\) \.app-held-badge\.is-store \{\s*position: absolute;/.test(css)],
    [true, true, true, true])
}
check('an Add just taken: "In your library", the added words, Remove to undo it',
  page({ changed: 'added' }), mine(true, 'In your library', 'remove', W.ADDED_FROM_PAGE))
check('a Remove just taken: "In the store", saying nothing was deleted, Add to undo it - even over a stale `starred`',
  page({ changed: 'removed', starred: true, bridgeYours: true }), mine(false, 'In the store', 'add', W.REMOVED_FROM_PAGE))
check('...but no Add after removing an album deadwax can\'t keep - and the line says how to have it back (review)',
  [page({ changed: 'removed', release: null, releaseSaid: '', present: 0, bridgeYours: undefined, starred: true }), page({ changed: 'removed', present: 0, bridgeYours: undefined, starred: true })],
  [mine(false, 'In the store', null, W.REMOVED_STAR_TO_RETURN), mine(false, 'In the store', null, W.REMOVED_STAR_TO_RETURN)])
check('Remove\'s words say it deletes nothing, and the way back names Amperfy',
  [/still in the store, and nothing was deleted/.test(W.REMOVED_FROM_PAGE), W.REMOVED_STAR_TO_RETURN.startsWith(W.REMOVED_FROM_PAGE), /star it in a Subsonic app such as Amperfy/.test(W.REMOVED_STAR_TO_RETURN)],
  [true, true, true])

console.log('\nTHE CONTRADICTION, never again: "in your library" above "In the store, not in your library"')
{
  //? Third: the store holds it whole, ethan doesn't - the store line and the meta line read the same folders
  const holding = O.ownedForGroup(index, { groupId: 'rg-third' }).held
  const held = { path: THIRD.path, paths: [THIRD.path], artist: 'Portishead', album: 'Third', edition: '', track_count: 11, expected_tracks: 11,
    formats: ['flac'], complete: true, fills_gaps: false, filed_to: null, yours: false }
  const store = PP.storeStatusFor({ held, downloading: null })
  const meta = P.metaLine({ year: '2008', kind: 'Album' }, holding.length > 0, W.heldPhrase(true, W.anyYours(holding)))
  check('the store line says "In the store, not in your library" and offers Add', [store.title, store.add], ['In the store, not in your library', true])
  check('...and the meta line above it says "in the store" - never "in your library"', [meta, meta.includes('in your library')], ['2008 · Album · in the store', false])
  const page = read('app/ReleaseGroupPage.tsx')
  check('...the page passes its meta line the place of the folders it holds, and the pressing on screen',
    [/const place = groupPagePlace\(personal, holding \?\? \[\], view\?\.chosenId\)/.test(page), /metaLine\(header, held, place\)/.test(page)], [true, true])
  //? and the album you have, by its own badge: an album the store has that isn't yours says "In the store"
  check('the album page\'s badge is albumMine\'s, never the words alone', /<span class="app-held-badge-text">\{mine\.badge\}<\/span>/.test(read('player/AlbumPage.tsx')), true)
  const off = P.metaLine({ year: '2008', kind: 'Album' }, true, W.heldPhrase(false, W.anyYours(O.ownedForGroup(offIndex, { groupId: 'rg-third' }).held)))
  check('logins off: the meta line says "in your library", and the store line "Already in your library", as ever',
    [off, PP.storeStatusFor({ held: { ...held, yours: undefined }, downloading: null }).title], ['2008 · Album · in your library', 'Already in your library'])
}
{
  //? (review) two pressings of Dummy in the store: the CD yours, the remaster the store's - the remaster on screen
  const CD = { path: 'Portishead/Dummy (1994)', release_mbid: 'rel-cd', release_group_mbid: 'rg-dummy', yours: true }
  const REMASTER = { path: 'Portishead/Dummy (2014)', release_mbid: 'rel-remaster', release_group_mbid: 'rg-dummy', yours: false }
  const two = O.buildOwnedIndex([CD, REMASTER])
  const holding = O.ownedForGroup(two, { groupId: 'rg-dummy' }).held
  const held = { path: REMASTER.path, paths: [REMASTER.path], artist: 'Portishead', album: 'Dummy', edition: 'Remaster', track_count: 11, expected_tracks: 11,
    formats: ['flac'], complete: true, fills_gaps: false, filed_to: null, yours: false }
  const store = PP.storeStatusFor({ held, downloading: null })
  const meta = (chosen) => P.metaLine({ year: '1994', kind: 'Album' }, true, W.groupPagePlace(true, holding, chosen))
  check('two pressings, the store\'s on screen: the store line "In the store, not in your library"...', store.title, 'In the store, not in your library')
  check('...and the meta line "another pressing in your library" - never a bare "in your library" over it',
    [meta('rel-remaster'), meta('REL-REMASTER'), / · in your library$/.test(meta('rel-remaster'))],
    ['1994 · Album · another pressing in your library', '1994 · Album · another pressing in your library', false])
  check('...yours on screen, or a pressing the store doesn\'t hold, "in your library" - the album is',
    [meta('rel-cd'), meta('rel-vinyl'), meta(null)], ['1994 · Album · in your library', '1994 · Album · in your library', '1994 · Album · in your library'])
  check('...none of them yours: "in the store"; logins off: "in your library", whichever is on screen',
    [W.groupPagePlace(true, [REMASTER], 'rel-remaster'), W.groupPagePlace(false, holding, 'rel-remaster'), W.groupPagePlace(false, [REMASTER], 'rel-remaster')],
    ['in the store', 'in your library', 'in your library'])
}

{
  //? (second review) the library's answer kept from earlier in the session - Dummy's CD yours then - and the store
  //? line asked as the page showed, after an unstar in Amperfy was read back: the CD the store's now
  const CD = { path: 'Portishead/Dummy (1994)', release_mbid: 'rel-cd', release_group_mbid: 'rg-dummy', yours: true }
  const REMASTER = { path: 'Portishead/Dummy (2014)', release_mbid: 'rel-remaster', release_group_mbid: 'rg-dummy', yours: false }
  const line = (paths, yours, others = []) => ({ held: { paths, yours }, other_pressings: others })
  const place = (holding, said, chosen) => W.groupPagePlace(true, W.withStoreLine(holding, said), chosen)
  check('a kept "yours" outvoted by the store line\'s fresh word: the meta line "in the store" under "In the store, not in your library"',
    [place([CD], line([CD.path], false), 'rel-cd'), PP.storeStatusFor({ held: { path: CD.path, paths: [CD.path], track_count: 11, expected_tracks: 11, formats: ['flac'], complete: true, yours: false }, downloading: null }).title],
    ['in the store', 'In the store, not in your library'])
  check('...and the other way: starred in Amperfy since, "in your library" under "Already in your library"',
    place([{ ...CD, yours: false }], line([CD.path], true), 'rel-cd'), 'in your library')
  check('...an other pressing the line names takes its word too; one it doesn\'t name keeps the library\'s',
    [place([CD, REMASTER], line([REMASTER.path], false, [{ path: CD.path, yours: false }]), 'rel-remaster'),
      place([CD, REMASTER], line([REMASTER.path], false), 'rel-remaster')],
    ['in the store', 'another pressing in your library'])
  check('...a line that says nothing of whose (logins off, the ledger unread), or no line yet: the library\'s answer as it was',
    [W.withStoreLine([CD], line([CD.path], undefined, [{ path: CD.path }])), W.withStoreLine([CD], null), W.withStoreLine([CD], { held: null, other_pressings: [] })],
    [[CD], [CD], [CD]])
  check('...and the folders themselves untouched - the same objects where nothing changed, the library\'s answer never written to',
    [W.withStoreLine([CD], line([CD.path], true))[0] === CD, CD.yours, W.withStoreLine([CD], line([CD.path], false))[0] === CD], [true, true, false])
  check('the pressing the line is about is the page\'s own - the one asked for, else the default - as the view chooses it',
    [P.chosenPressingId([{ id: 'a' }, { id: 'b' }], 'b', 'a'), P.chosenPressingId([{ id: 'a' }, { id: 'b' }], 'x', 'a'), P.chosenPressingId([{ id: 'a' }], null, 'a'), P.chosenPressingId([], null)],
    ['b', 'a', 'a', null])
  const page = read('app/ReleaseGroupPage.tsx')
  check('...the page lays the store line\'s answer for the pressing on screen over its folders, the marks and the place from them',
    [/const said = store && store\.id === shownId \? store\.state : null\s+const holding = ownership \? withStoreLine\(ownership\.held, said\) : null/.test(page),
      //? (2.0.0-player.53) the pressing on screen: the address's, else - opened from a song - one with the song
      /const shownId = useMemo\(\(\) => chosenPressingId\(releases, asked\), \[answer, asked\]\)/.test(page), /const known = said\n/.test(page),
      /const yoursKey = personal \? releaseIds\(\(holding \?\? \[\]\)\.filter\(isYours\)\) : null/.test(page)],
    [true, true, true, true])
  check('...and asks the library again every time it shows, as the store line is asked',
    [/const owned = useOwned\(false\)\s+useEffect\(\(\) => \{\s+if \(shown\) void refreshOwned\(\)\s+\}, \[shown\]\)/.test(page)], [true])
}

console.log('\nSearch: the store first, its rows marked; MusicBrainz for what the store doesn\'t have')
//? (2.0.0-player.55) one list, no half titles: the hint, the field's label, the asking line, the all-held words
check('the words with a library of your own: yours, then the store\'s, then MusicBrainz\'s',
  (({ hint, allHeld, label, searching }) => [hint, allHeld, label, searching(true), searching(false)])(S.searchWords(true)),
  ["Artists, albums and songs: yours first, then the store's, then MusicBrainz's.", 'Everything MusicBrainz found is in the store already.', 'Search the store and MusicBrainz',
    'Searching the store and MusicBrainz…', 'Searching the store…'])
check('...and with logins off, yours then MusicBrainz\'s - the field\'s label as it was',
  (({ hint, allHeld, label, searching }) => [hint, allHeld, label, searching(true), searching(false)])(S.searchWords(false)),
  ["Artists, albums and songs: yours first, then MusicBrainz's.", 'Everything MusicBrainz found is in your library already.', 'Search your library and MusicBrainz',
    'Searching your library and MusicBrainz…', 'Searching your library…'])
check('...the half titles gone', Object.keys(S.searchWords(true)).sort(), ['allHeld', 'hint', 'label', 'searching'])
//? (2.0.0-player.55) a library row's place in Search: said in both modes now - the half titles that said it are gone
check('a library row\'s place in Search (libraryPlace): "in your library" with logins off too - reversing navidromePlace\'s silence there; with a library of your own whose it is, nothing while unknown',
  [W.libraryPlace(false, null), W.libraryPlace(false, false), W.libraryPlace(true, true), W.libraryPlace(true, false), W.libraryPlace(true, null)],
  ['in your library', 'in your library', 'in your library', 'in the store', ''])
const group = { id: 'rg-third', title: 'Third', 'primary-type': 'Album', 'first-release-date': '2008-04-28', 'artist-credit': [{ name: 'Portishead' }] }
check('a MusicBrainz row the store turns out to hold says whose it is',
  [S.groupLine(group, true, S.groupPlace(index, 'rg-third', true)), S.groupLine({ ...group, id: 'rg-dummy' }, true, S.groupPlace(index, 'rg-dummy', true)),
    S.groupLine(group, true, S.groupPlace(index, 'rg-third', false)), S.groupLine(group, true)],
  ['Album · Portishead · 2008 · in the store', 'Album · Portishead · 2008 · in your library', 'Album · Portishead · 2008 · in your library', 'Album · Portishead · 2008 · in your library'])
check('an artist\'s count is the store\'s with a library of your own', [S.artistLine(2, true), S.artistLine(1, false), S.artistLine(0, true), S.artistLine(2, true, true)],
  ['2 albums in the store', '1 album in your library', '', 'Artist · 2 albums in the store'])
check('"More from MusicBrainz" says the store has them', [S.morePageWords(0, 2, true).note, S.morePageWords(0, 1, false).note],
  ['The next 2 albums MusicBrainz found are all in the store already.', 'The next album MusicBrainz found is in your library already.'])
{
  const list = read('lib/searchList.ts')
  //? (2.0.0-player.55) replaces the half-titles pin: every library row says its place, by libraryPlace over whose it is - an
  //? album row made of a song's own fields read as search3 or `ready` has it, unknown without (review: "in the store" on a guess)
  check('Search\'s library rows carry their place - albums and songs by libraryPlace, over your albums\' ids and the one /library/owned answer',
    [/line: join\(top \? 'Album' : '', row\.album\.artist, year\), place: libraryPlace\(marks\.personal, albumYours\(row\.album, marks\)\)/.test(list),
      /place: libraryPlace\(marks\.personal, songYours\(row\.song, marks\)\)/.test(list),
      /if \(marks\.yourAlbums\?\.has\(album\.id\)\) return true\s*if \(!album\.starred && !album\.musicBrainzId && marks\.albumOf\) \{\s*const known = marks\.albumOf\(album\.id\)\s*return known \? navidromeYours\(known, marks\.index\) : null\s*\}\s*return navidromeYours\(album, marks\.index\)/.test(list)],
    [true, true, true])
}

console.log('\nthe pressing picker: yours marked "In your library", the store\'s "In the store"')
{
  const releases = [
    { id: 'rel-dummy', title: 'Dummy', date: '1994-08-22', media: [{ format: 'CD', tracks: [{ title: 'Mysterons', length: 300000 }] }] },
    { id: 'rel-vinyl', title: 'Dummy', date: '1994-08-22', media: [{ format: '12" Vinyl', tracks: [{ title: 'Mysterons', length: 300000 }] }] },
  ]
  const both = new Set(['rel-dummy', 'rel-vinyl'])
  const view = P.pressingsView(releases, null, both, new Set(['rel-dummy']))
  const marks = Object.fromEntries([...view.shown, ...view.more].map((row) => [row.id, [row.held, !!row.inStore]]))
  check('held and yours: no store mark; held and not yours: "In the store"', marks, { 'rel-dummy': [true, false], 'rel-vinyl': [true, true] })
  const off = P.pressingsView(releases, null, both, null)
  check('...with logins off (no `yours` set) nothing is marked the store\'s', [...off.shown, ...off.more].some((row) => row.inStore), false)
  check('the picker\'s filter finds "in the store" and "in your library" as they are marked',
    [P.filterPressings([...view.shown, ...view.more], 'in the store').map((row) => row.id), P.filterPressings([...view.shown, ...view.more], 'your library').map((row) => row.id)],
    [['rel-vinyl'], ['rel-dummy']])
}

console.log('\nthe artist page: a row the store holds that isn\'t yours says so')
{
  const groups = [{ id: 'rg-dummy', title: 'Dummy', 'primary-type': 'Album', 'first-release-date': '1994' }, { id: 'rg-third', title: 'Third', 'primary-type': 'Album', 'first-release-date': '2008' }]
  const navidrome = [{ id: 'nd-dummy', name: 'Dummy', musicBrainzId: REL_DUMMY, year: 1994 }, { id: 'nd-third', name: 'Third', musicBrainzId: REL_THIRD, year: 2008 }]
  const rows = A.artistRows(navidrome, groups, index)
  check('Dummy is yours, Third the store\'s', rows.map((row) => [row.title, row.yours]), [['Dummy', true], ['Third', false]])
  check('...in the rows\' words with a library of your own', rows.map((row) => A.rowLine(row, true)), ['1994 · in your library', '2008 · in the store'])
  check('...and with logins off both in your library', rows.map((row) => A.rowLine(row)), ['1994 · in your library', '2008 · in your library'])
  const starred = A.artistRows([navidrome[0], { ...navidrome[1], starred: '2026-10-15T09:00:00Z' }], groups, index)
  check('an album of it you starred makes a row yours before deadwax reads the star back', starred[1].yours, true)
  check('Play says the store\'s albums with a library of your own', [A.playsLine(2, 2, true, 'done', true), A.playsLine(1, 1, true, 'done', false), A.playsLine(0, 0, false, 'asking', true)],
    ['Plays the 2 albums in the store', 'Plays the album you have', 'Looking for their albums in the store…'])
  check('...a store\'s count of their albums, as Browse\'s artists and Info say it', [A.albumCountLine(3, W.storeCountPlace(true)), A.albumCountLine(1)],
    ['3 albums in the store', '1 album in your library'])
}

console.log('\n"The store also has another pressing"')
{
  const pressing = (yours) => ({ path: 'Portishead/Dummy (2014)', release_mbid: 'r2', edition: 'Remaster', year: '2014', track_count: 11, formats: ['flac'], ...(yours === undefined ? {} : { yours }) })
  check('one not yours is the store\'s; one yours, and one with logins off, yours',
    [C.storeNotes({ held: null, downloading_part: null, other_pressings: [pressing(false)] })[0], C.storeNotes({ held: null, downloading_part: null, other_pressings: [pressing(true)] })[0],
      C.storeNotes({ held: null, downloading_part: null, other_pressings: [pressing()] })[0]].map((note) => note.split(':')[0]),
    ['The store also has another pressing', 'You also have another pressing', 'You also have another pressing'])
}

console.log('\nyour library: your starred albums, in the order chosen')
{
  const albums = [
    { id: 'a', name: 'The Slow Rush', artist: 'Tame Impala', year: 2020, created: '2026-10-01T00:00:00Z', played: '2026-10-14T00:00:00Z' },
    { id: 'b', name: 'Dummy', artist: 'Portishead', year: 1994, created: '2026-10-10T00:00:00Z' },
    { id: 'c', name: 'Third', artist: 'Portishead', year: 2008, created: '2026-09-01T00:00:00Z', played: '2026-10-15T00:00:00Z' },
    { id: 'd', name: 'Abbey Road', artist: 'The Beatles', year: 1969 },
  ]
  //? (2.0.0-player.59) the four orders that existed, now lib/shelves.ts sortAlbums - the same answers, Artist's year rule
  //? included (the other three, and the headers, in shelves.sim)
  const order = (name) => SH.sortAlbums(albums, name).map((album) => album.id)
  check('Recently added: newest first, the undated last', order('newest'), ['b', 'a', 'c', 'd'])
  check('Recently played: only what you played, latest first', order('recent'), ['c', 'a'])
  check('Artist: by name folded ("The Beatles" as Beatles), then year', order('alphabeticalByArtist'), ['d', 'b', 'c', 'a'])
  check('Title: by title folded ("The Slow Rush" as Slow Rush)', order('alphabeticalByName'), ['d', 'b', 'a', 'c'])
  check('nothing left out or doubled, Navidrome\'s list untouched', [order('newest').length, albums[0].id], [4, 'a'])
  const artists = [{ id: 'ar-p', name: 'Portishead', albumCount: 3 }, { id: 'ar-t', name: 'Tame Impala', albumCount: 4 }, { id: 'ar-b', name: 'Boards of Canada', albumCount: 2 }]
  const mine = [{ id: 'x', name: 'Dummy', artistId: 'ar-p' }, { id: 'y', name: 'Third', artistId: 'ar-p' }, { id: 'z', name: 'Currents', artistId: 'ar-t' }]
  check('your artists: the artists of your albums, counting YOUR albums of theirs, in Navidrome\'s order',
    Y.yourArtists(artists, mine).map((artist) => [artist.name, artist.albumCount]), [['Portishead', 2], ['Tame Impala', 1]])
  check('an empty library says so, and what to do: browse the store, or search', [Y.EMPTY_LIBRARY, /Browse the store, or search/.test(Y.EMPTY_LIBRARY_HOW)],
    ['Nothing in your library yet.', true])
  check('...in ANY order, Recently played too (review: the order is the device\'s, shared with Browse); "nothing played" only over albums - Most played too',
    [Y.yourEmptyNotice('recent', 0), Y.yourEmptyNotice('newest', 0), Y.yourEmptyNotice('alphabeticalByName', 0), Y.yourEmptyNotice('recent', 3), Y.yourEmptyNotice('recent', null),
      Y.yourEmptyNotice('frequent', 3), Y.yourEmptyNotice('byYearDesc', 3), Y.yourEmptyNotice('frequent', 0)],
    ['empty', 'empty', 'empty', 'unplayed', null, 'unplayed', null, 'empty'])
  //? (2.0.0-player.59) the sections (app/LibrarySection.tsx) and the root (app/LibraryHome.tsx) draw it now, from the whole list
  const library = read('player/Library.tsx'), section = read('app/LibrarySection.tsx'), home = read('app/LibraryHome.tsx')
  check('...a section counts your albums from the one list it has in hand, and draws the notice it says',
    [/const notice = scope === 'yours' && albums && !sorted\.length \? yourEmptyNotice\(sort, albums\.length\) : null/.test(section),
      /notice === 'empty' \? <EmptyLibrary lead=\{EMPTY_LIBRARY\} onBrowse=\{onBrowse\} \/>/.test(section),
      /personal \? <EmptyLibrary lead=\{EMPTY_LIBRARY\} onBrowse=\{\(\) => onOpenSection\('store'\)\} \/>/.test(home)], [true, true, true])
  check('...and Your artists, empty, says how to fill it with Browse the store too',
    [/yours \? <EmptyLibrary lead=\{NO_ARTISTS_OF_YOURS\} onBrowse=\{onBrowse\} \/>/.test(section), /onBrowse=\{browse\}/.test(library), /onBrowse=\{browseStore\}/.test(read('app/App.tsx'))], [true, true, true])
  check('Browse the store hands its focus on - a page\'s title as it mounts, a desktop\'s store title - only when it was lost',
    [/if \(active && active !== document\.body && !active\.closest\('\[hidden\]'\)\) return\s*page\.current\?\.querySelector<HTMLElement>\('\[data-section="store"\] \.pl-large-title'\)\?\.focus\(\{ preventScroll: true \}\)/.test(library),
      /if \(!page\) return\s*const active = document\.activeElement as HTMLElement \| null\s*if \(active && active !== document\.body && !active\.closest\('\[hidden\]'\)\) return\s*title\.current\?\.focus\(\{ preventScroll: true \}\)/.test(section),
      /<h1 class="pl-large-title" ref=\{titleRef\} tabIndex=\{-1\}>/.test(section)], [true, true, true])
}

console.log('\nthe Library\'s views: yours and Browse with a library of your own, as ever with logins off')
check('logins off: the sidebar lists the Library as it always did, and no Browse',
  [F.libraryItems(true).map((item) => item.id), F.browseItems(true).length, F.libraryItems(true, false).map((item) => item.id)],
  [['recent', 'albums', 'artists', 'songs'], 0, ['recent', 'albums', 'artists', 'songs']])
check('...titles as they were', ['recent', 'albums', 'artists', 'songs'].map((pick) => F.libraryTitle(pick)), ['Recently added', 'Albums', 'Artists', 'Songs'])
check('...and Browse\'s views, kept on a device, show as the albums and the artists',
  [F.shownPick('store', true, 'phone'), F.shownPick('storeArtists', true, 'desktop'), F.sidebarCurrent('library', 'store', true)], ['albums', 'artists', 'albums'])
check('a library of your own: yours in the Library group, the store\'s in Browse - Songs is Browse\'s',
  [F.libraryItems(true, true).map((item) => item.id), F.browseItems(true, true).map((item) => [item.id, item.label]), F.browseItems(false, true).map((item) => item.id)],
  [['recent', 'albums', 'artists'], [['store', 'Albums'], ['storeArtists', 'Artists'], ['songs', 'Songs']], ['store', 'storeArtists']])
check('...titled yours and the store\'s', ['recent', 'albums', 'artists', 'store', 'storeArtists', 'songs'].map((pick) => F.libraryTitle(pick, true)),
  ['Recently added', 'Your albums', 'Your artists', 'Albums in the store', 'Artists in the store', 'Songs in the store'])
check('...Browse\'s picks stay Browse\'s, Songs falling back to the store\'s albums, a phone\'s Recently added to yours',
  [F.shownPick('store', true, 'phone', true), F.shownPick('songs', false, 'phone', true), F.shownPick('recent', true, 'phone', true), F.isBrowse('store', true), F.isBrowse('store', false), F.isBrowse('albums', true)],
  ['store', 'store', 'albums', true, false, false])
check('...and the sidebar moves to them, current when showing',
  [F.sidebarMove('store', 'albums', true, true), F.sidebarMove('store', 'store', true, true), F.sidebarCurrent('library', 'storeArtists', true, null, true)],
  [{ how: 'view', tab: 'library', pick: 'store' }, { how: 'tab', tab: 'library' }, 'storeArtists'])
{
  //? (2.0.0-player.59, on purpose) the phone's scope chips went: Browse is a group of rows on the root, the sidebar's own
  const home = read('app/LibraryHome.tsx')
  check('the Library: Browse\'s group on the root with a library of your own only - the sidebar\'s Browse items - and the Playlists row the first row of its first group',
    [/const browse = browseItems\(hasSongs, personal\)/.test(home), /\{browse\.length > 0 && \(\s*<section class="app-library-browse"/.test(home),
      home.indexOf('<div class="app-group app-library-group">') < home.indexOf('app-library-playlists') && home.indexOf('app-library-playlists') < home.indexOf('{yours.map(row)}'),
      /app-library-views|app-library-scope/.test(home + read('player/Library.tsx'))], [true, true, true, false])
}

console.log('\nthe wiring: every page takes `personal` from hasLibrary() and hands it on (second review)')
{
  const personalFrom = (file) => /\n {2}const personal = hasLibrary\(\)\n/.test(read(file))
  check('the album you don\'t have, Search, the artist page and the Library each say "a library of your own" from hasLibrary() alone',
    ['app/ReleaseGroupPage.tsx', 'app/Search.tsx', 'app/ArtistPage.tsx', 'player/Library.tsx'].map(personalFrom), [true, true, true, true])
  const album = read('player/AlbumPage.tsx')
  check('the album page hands albumMine every input from where it is known - hasLibrary(), the album\'s own answer, the bridge',
    [/const mine = albumMine\(\{\s*personal: hasLibrary\(\),\s*starred: album \? !!album\.starred : error \? false : null,\s*storeDone,\s*bridgeFailed: storeFailed,\s*bridgeYours: store\?\.yours,\s*present: store\?\.present\.length \?\? 0,\s*release,\s*releaseSaid: album \? album\.musicBrainzId \?\? '' : null,\s*changed,\s*\}\)/.test(album),
      /const release = store\?\.release_mbid \?\? null\n/.test(album), /const storeDone = store !== null \|\| storeFailed\n/.test(album)],
    [true, true, true])
  check('...and Add asks for the bridge\'s release - the one deadwax keeps your library by - and its album',
    /addToMyLibrary\(\{[^}]*\brelease_mbid: release,[^}]*release_group_mbid: store\?\.release_group_mbid \?\? null,\s*\}\)/.test(album), true)
  //? (2.0.0-player.59) one section component for every view, `personal` handed it by the Library (a desktop's) and App
  //? (a page's), each view's scope decided there
  const library = read('player/Library.tsx'), section = read('app/LibrarySection.tsx'), app = read('app/App.tsx')
  check('the Library: each of your three views yours, on its own - Albums, Recently added, Artists',
    [/const scope: Scope = id === 'store' \|\| !personal \? 'store' : 'yours'/.test(section), /const yours = personal && id === 'artists'/.test(section),
      /personal=\{personal\}/.test(library), /personal=\{hasLibrary\(\)\}/.test(app), /id=\{shownPick\(page\.id as LibraryPick, hasSongs, 'desktop', hasLibrary\(\)\)\}/.test(app)],
    [true, true, true, true, true])
  check('...and Browse\'s two the store\'s: every album, and artists counted "in the store"',
    [/const inStore = personal && id === 'storeArtists'/.test(section), /<ArtistRow artist=\{artist\} inStore=\{inStore\} onOpenArtist=\{onOpenArtist\} \/>/.test(section),
      /\{albumCountLine\(artist\.albumCount, inStore \? IN_THE_STORE : undefined\) && \(\s*<span class="app-result-line">\{albumCountLine\(artist\.albumCount, inStore \? IN_THE_STORE : undefined\)\}<\/span>/.test(read('app/LibraryViews.tsx'))],
    [true, true, true])
  const sidebar = read('app/Sidebar.tsx')
  check('a desktop\'s sidebar: a Browse group whenever App gives it Browse\'s views, and App gives them - and the Library\'s - by hasLibrary()',
    [/\{browse\.length > 0 && \(\s*<section class="app-side-group" aria-labelledby="app-side-browse">\s*<h2 id="app-side-browse" class="app-side-label">\s*Browse\s*<\/h2>\s*<ul class="app-side-list">\{browse\.map\(item\)\}<\/ul>/.test(sidebar),
      /library=\{libraryItems\(hasSongs, hasLibrary\(\)\)\}\s*browse=\{browseItems\(hasSongs, hasLibrary\(\)\)\}\s*personal=\{hasLibrary\(\)\}/.test(app),
      /sidebarMove\(item, libraryPick\(\), librarySongs\(\), hasLibrary\(\), router\.nav\.stacks\.library\[0\] \?\? null\)\s*if \(move\.how === 'tab'\) \{\s*(?:\/\/[^\n]*\n\s*)?if \(move\.pick\) chooseLibrary\(move\.pick\)\s*chooseTab\(move\.tab\)/.test(app), /aria-label=\{searchWords\(personal\)\.label\}/.test(sidebar)],
    [true, true, true, true])
  const search = read('app/Search.tsx')
  const list = read('lib/searchList.ts')
  check('Search: its words, its artists\' counts, More\'s note and its MusicBrainz rows\' places, each by `personal`',
    [/const personal = hasLibrary\(\)\n {2}const words = searchWords\(personal\)\n/.test(search), /artistLine\(row\.artist\.albumCount, marks\.personal\)/.test(list),
      /morePageWords\(more\.added, more\.held, personal\)/.test(search),
      /place: savedPlace\(row, held \? groupPlace\(marks\.index, row\.group\.id, marks\.personal\) : ''\)/.test(list)],
    [true, true, true, true])
  check('...and no half titles any more (2.0.0-player.55): one list in sections', [/words\.libraryTitle|words\.musicbrainzTitle/.test(search), /<h2 id="app-search-top"/.test(search)], [false, true])
  const artist = read('app/ArtistPage.tsx')
  check('the artist page: its facts headed, its waits and empties said, its rows worded and ticked, Play\'s line - each by `personal`',
    [/<h2 id="app-artist-library-title" class="app-section-title">\{personal \? 'In the store' : 'In your library'\}<\/h2>/.test(artist),
      /const where = personal \? 'the store' : 'your library'\n/.test(artist), /Looking in \{where\}…/.test(artist), /Nothing of theirs in \{where\}\./.test(artist),
      /\{row\.held === true && \(!personal \|\| row\.yours !== false\) && <CheckIcon class="app-artist-held" \/>\}/.test(artist),
      /<span class="app-artist-line-text">\{rowLine\(row, personal\)\}<\/span>/.test(artist),
      /\{playsLine\(playing\.length, inHand\.length, settled, library\.state, personal\)\}/.test(artist)],
    [true, true, true, true, true, true, true])
  const info = read('app/InfoSheet.tsx')
  check('Info: the album\'s rows by hasLibrary(), and its folder headed "In the store" with a library of your own',
    [/aboutRows\(track, album, details, hasLibrary\(\)\)/.test(info), /<h3 id="app-info-where" class="app-section-title">[\s\S]{0,200}?\{hasLibrary\(\) \? 'In the store' : 'In your library'\}\s*<\/h3>/.test(info)],
    [true, true])
}

console.log('\nyour albums are asked again whenever they can have changed - and not for a filing (second review)')
{
  const yours = read('app/useYourAlbums.ts')
  check('an Add and a Remove each forget them; a filing doesn\'t (it is starred later, the count moving then)',
    [/onAddedToLibrary\(forgetYourAlbums\)/.test(yours), /onRemovedFromLibrary\(forgetYourAlbums\)/.test(yours), /onAlbumsFiled/.test(yours)], [true, true, false])
  //? (2.0.0-player.59) the whole list in one ask - routes/navidrome.py reads Navidrome's pages of 500 as you
  check('...asked as you: the album index\'s `yours`, through the player\'s route', [/albumIndex\('yours'\)/.test(yours), /album_index\?scope=\$\{scope\}/.test(read('player/api.ts'))], [true, true])
  const library = read('player/Library.tsx')
  check('...and your library\'s count moving (the worker, a star read back) forgets them too, in the Library',
    /if \(seenCount\.current !== null && seenCount\.current !== starredCount\) forgetYourAlbums\(\)/.test(library), true)
  const section = read('app/LibrarySection.tsx')
  check('the grid of your albums is keyed on their generation, so it asks again',
    [/const generation = scope === 'yours' \? yoursGeneration : storeGeneration/.test(section), /useEffect\(load, \[scope, generation\]\)/.test(section)], [true, true])
  const owned = read('app/useOwned.ts')
  check('the owned marks are asked again after an Add or a Remove - whose it is changed', [/onAddedToLibrary\(whose\)/.test(owned), /onRemovedFromLibrary\(whose\)/.test(owned)], [true, true])
  const album = read('player/AlbumPage.tsx')
  check('the album page says an Add or a Remove it made, so your library, your albums and the marks follow',
    [/if \(action === 'add'\) announceAddedToLibrary\(\)\s*else announceRemovedFromLibrary\(\)/.test(album), /removeFromMyLibrary\(id\)/.test(album)], [true, true])
}

//? the real module: your albums asked for once and shared, asked again after an Add or a Remove - and a filing
//? (anybody's download an admin watches, an Edit panel write, Rescan) leaving the list and its grid as they were
async function yoursAskedAgain() {
  console.log('\nyour albums, the module itself: what asks them again')
  const YA = load('app/useYourAlbums.js'), LE = load('lib/libraryEvents.js'), AI = load('app/albumIndex.js')
  globalThis.__whose.albums = [{ id: 'b', name: 'Dummy', artist: 'Portishead', year: 1994, created: '2026-10-10T00:00:00Z' }]
  const asks = () => globalThis.__whose.asks.length
  //? an ask lands when the test says (the stub's `land`)
  const landed = async (promise) => {
    globalThis.__whose.land()
    return promise
  }
  const asking = YA.yourAlbums()
  const also = YA.yourAlbums()
  check('nothing kept before the first list lands', AI.keptIndex('yours'), null)
  const first = await landed(asking)
  check('asked once - /album_index?scope=yours, the whole list - and shared by every view', [asks(), globalThis.__whose.asks[0], first.map((album) => album.id), (await also) === first],
    [1, 'yours', ['b'], true])
  const generation = YA.useYourAlbumsGeneration()
  LE.announceAlbumsFiled()
  await YA.yourAlbums()
  check('an album filed: nothing asked again, the generation the grid is keyed on unmoved - its tiles and its place kept',
    [asks(), YA.useYourAlbumsGeneration() === generation], [1, true])
  LE.announceAddedToLibrary()
  globalThis.__whose.albums = [{ id: 'c', name: 'Third', artist: 'Portishead' }, ...globalThis.__whose.albums]
  const again = YA.yourAlbums()
  check('an Add: asked again, under a new generation - the list kept drawn meanwhile (never emptied for the ask)',
    [asks(), YA.useYourAlbumsGeneration() === generation + 1, AI.keptIndex('yours').albums.map((album) => album.id)], [2, true, ['b']])
  await landed(again)
  check('...the new one swapped in as it lands', AI.keptIndex('yours').albums.map((album) => album.id), ['c', 'b'])
  LE.announceRemovedFromLibrary()
  await landed(YA.yourAlbums())
  check('a Remove: asked again too', [asks(), YA.useYourAlbumsGeneration() === generation + 2], [3, true])
  //? refreshIfOld: a list under a minute old stays; one older is asked again at the next look
  AI.refreshIfOld('yours')
  check('a list under a minute old is not asked again', [asks(), YA.useYourAlbumsGeneration() === generation + 2], [3, true])
  AI.keptIndex('yours').at = Date.now() - AI.INDEX_FRESH_MS - 1
  AI.refreshIfOld('yours')
  const old = YA.yourAlbums()
  check('...one older than INDEX_FRESH_MS is', [asks(), YA.useYourAlbumsGeneration() === generation + 3, AI.INDEX_FRESH_MS], [4, true, 60000])
  AI.refreshIfOld('yours')
  check('...and one on its way is left alone, whatever the age of the one in hand', [asks(), YA.useYourAlbumsGeneration() === generation + 3], [4, true])
  await landed(old)
  //? two asks out at once, the newer landing first: the older one, landing late, never replaces it
  globalThis.__whose.albums = [{ id: 'older', name: 'Older' }]
  AI.forgetIndex('yours')
  const older = YA.yourAlbums()
  AI.forgetIndex('yours')
  globalThis.__whose.albums = [{ id: 'newer', name: 'Newer' }]
  const newer = YA.yourAlbums()
  globalThis.__whose.landNewest()
  await newer
  globalThis.__whose.land()
  await older
  check('an older ask landing after a newer one keeps nothing: the newer list is the one kept to draw', AI.keptIndex('yours').albums.map((album) => album.id), ['newer'])
  //? (review) a failed ask isn't kept: the next look - the section's Try again - asks again, and gets the list
  globalThis.__whose.failNext = true
  const before = asks()
  const failing = AI.albumIndex('store')
  globalThis.__whose.land()
  const failed = await failing.then(() => 'landed', (reason) => reason.message)
  const retry = AI.albumIndex('store')
  check('a failed ask rejects, and is let go: the next look asks again (Try again works)', [failed, asks() - before, globalThis.__whose.asks.slice(-2)], ['Navidrome is away', 2, ['store', 'store']])
  globalThis.__whose.land()
  check('...and that ask\'s list lands, and is kept', [(await retry).albums.map((album) => album.id), AI.keptIndex('store').albums.map((album) => album.id)], [['newer'], ['newer']])
}

yoursAskedAgain().catch((caught) => {
  failures++
  console.log(`  FAIL  your albums' module threw: ${caught && caught.stack}`)
}).finally(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})
