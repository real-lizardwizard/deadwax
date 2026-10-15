/**
 * The album you don't have (2.0.0-player.13): its pressing dropdown, the chosen pressing's
 * tracklist and the line above it (ui/src/lib/pressings.ts), against real MusicBrainz groups as
 * MusicBrainz answered them (tests/fixtures/pressings/).
 *
 * What a wrong answer would hide: the page opening on another pressing than Get will get; a bonus
 * track, a single mix or a missing track not shown; the dropdown burying the pressing you chose (and,
 * since 2.0.0-player.41, a pressing you hold - each marked by release id, never folded away)
 * under "N more"; disc headings without MusicBrainz's medium titles; a pressing called "the usual
 * tracklist" that isn't - or the page reading backwards because MusicBrainz listed a single mix
 * first (every pressing is compared at the DEFAULT pressing's lengths, so no order changes a
 * word); and a cold link claiming "not in your library" before the library has said. And
 * (2.0.0-player.50) each pressing's facts - status, full date, labels beside a disambiguation, catalogue
 * numbers once, the barcode, "Worldwide" - never repeating the label line and never made up, a label
 * said once whatever numbers it carries; the dropdown's filter over labels, facts and notes, accents
 * folded and a catalogue number found with its dash, a space or nothing between its parts; the meta
 * line's held / maybe / not; the album's page.
 *
 * Run it with:  node ui/test/pressings.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURES = path.resolve(__dirname, '../../tests/fixtures/pressings')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-pressings-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/pressings.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const P = require(path.join(OUT, 'lib/pressings.js'))
const T = require(path.join(OUT, 'lib/tracklistDiff.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const load = (name) => JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'))
const slowRush = load('slow-rush'), dummy = load('dummy'), third = load('third'), wywh = load('wish-you-were-here-experience')
const byPrefix = (fixture, prefix) => fixture.releases.find((release) => release.id.startsWith(prefix))

console.log('the default pressing: the one representativeRelease picks - the one Get will get')
for (const fixture of [slowRush, dummy, third]) {
  const view = P.pressingsView(fixture.releases)
  check(`${fixture.group.title}: the default is the representative, and it is shown`,
    [view.defaultId, view.chosenId, view.shown[0].id, view.shown[0].isDefault], [fixture.expected.representative, fixture.expected.representative, fixture.expected.representative, true])
}
check('The Slow Rush opens on the 2020 Australian CD', P.pressingLabel(byPrefix(slowRush, '1cf564b9')), 'CD · 2020 · AU · Caroline International')
check('...as the usual tracklist, and says how usual', P.pressingsView(slowRush.releases).shown[0].note, 'The usual tracklist · shared by 9 of 10 pressings')
check('an address naming a pressing of the group opens on it', P.pressingsView(slowRush.releases, byPrefix(slowRush, '452ccdb4').id).chosenId, byPrefix(slowRush, '452ccdb4').id)
check('...one naming something else opens on the default', P.pressingsView(slowRush.releases, 'not-in-this-group').chosenId, slowRush.expected.representative)

console.log('\nthe dropdown')
const slow = P.pressingsView(slowRush.releases)
check('The Slow Rush: the default, one of each other format with the usual tracklist, then each that differs',
  slow.shown.map((row) => [row.kind, row.label, row.note]), [
    ['usual', 'CD · 2020 · AU · Caroline International', 'The usual tracklist · shared by 9 of 10 pressings'],
    ['usual', '2×12" Vinyl · 2020 · Caroline International', 'Same tracklist as the usual one'],
    ['usual', 'Digital · 2020 · Borderline “album mix” version', 'Same tracklist as the usual one'],
    ['differs', 'CD · 2020 · JP · Caroline International', '+1 bonus track: Patience'],
    ['differs', 'Digital · 2020 · AI · Borderline “single mix” version', '1 other version: Borderline, 4:34'],
  ])
check('...and the five other pressings with the usual tracklist folded under "N more"', [slow.more.length, slow.more.every((row) => row.kind === 'usual')], [5, true])
check('every pressing is in one list or the other, once', [...slow.shown, ...slow.more].map((row) => row.id).sort(), slowRush.releases.map((release) => release.id).sort())
const folded = slow.more[0].id
const picked = P.pressingsView(slowRush.releases, folded)
check('a pressing chosen from under "N more" stays in view, and leaves the fold', [picked.shown.some((row) => row.id === folded), picked.more.some((row) => row.id === folded), picked.more.length], [true, false, 4])

console.log('\nthe pressings you hold (2.0.0-player.41): each marked, none folded away')
{
  const [first, second] = slow.more
  const held = new Set([first.id, second.id, slowRush.expected.representative])
  const marked = P.pressingsView(slowRush.releases, null, held)
  const all = [...marked.shown, ...marked.more]
  check('every pressing held marked, by release id - and only those', all.filter((row) => row.held).map((row) => row.id).sort(), [...held].sort())
  check('...two that were folded under "N more" now in view, in the fold\'s order, the fold two shorter',
    [marked.shown.filter((row) => row.id === first.id || row.id === second.id).length, marked.more.some((row) => row.held), marked.more.length], [2, false, slow.more.length - 2])
  check('...still every pressing once, and the order of the rest as it was',
    [all.map((row) => row.id).sort().join() === slowRush.releases.map((release) => release.id).sort().join(), marked.shown.filter((row) => !row.held).map((row) => row.id).join() === slow.shown.filter((row) => !held.has(row.id)).map((row) => row.id).join()],
    [true, true])
  const capitals = slowRush.releases.map((release) => (release.id === first.id ? { ...release, id: release.id.toUpperCase() } : release))
  check('...a pressing whose id MusicBrainz wrote in capitals still matches', P.pressingsView(capitals, null, new Set([first.id])).shown.some((row) => row.id === first.id.toUpperCase() && row.held), true)
  check('nothing held: nothing marked, the fold as it was', [P.pressingsView(slowRush.releases).shown.some((row) => row.held), P.pressingsView(slowRush.releases).more.length], [false, slow.more.length])
}

const dum = P.pressingsView(dummy.releases)
check('Dummy: the ten-track CDs say what they leave out; the vinyl, its 30s-short Biscuit too', [
  dum.shown.find((row) => row.id.startsWith('87888070')).note,
  dum.shown.find((row) => row.id.startsWith('f5804905')).note,
], ['Without It’s a Fire', 'Without It’s a Fire · 1 other version: Biscuit, 4:34'])
check('...a twelfth track is a bonus, named', dum.shown.find((row) => row.id.startsWith('cac64a87')).note, '+1 bonus track: Sour Sour Times / To Kill a Dead Man')
check('...a few seconds\' difference in a length is still the usual tracklist', dum.shown.find((row) => row.id.startsWith('eca6d001')).kind, 'usual')
check('...a disambiguation tells a pressing apart where a label would not', P.pressingLabel(byPrefix(dummy, 'f5804905')), '12" Vinyl · 2014 · GB · 20th Anniversary Reissue 180gram')
const thr = P.pressingsView(third.releases)
check('Third: many bonus tracks named two at a time', thr.shown.find((row) => row.id.startsWith('18256dad')).note, '+12 bonus tracks: Silence, Hunter and 10 more')
check('...thirteen alike, the rest folded', [thr.shown.filter((row) => row.kind === 'usual').length + thr.more.length, thr.base.count], [13, 13])

console.log('\nthe line above the tracklist')
check('the default: the usual tracklist, and how many share it', P.summaryLine(slow, 10), { text: 'The usual tracklist, shared by 9 of 10 pressings', differs: false })
check('another with the same tracklist', P.summaryLine(P.pressingsView(slowRush.releases, folded), 10), { text: 'Same tracklist as the usual one', differs: false })
check('the Japanese CD adds a track - drawn amber', P.summaryLine(P.pressingsView(slowRush.releases, byPrefix(slowRush, '452ccdb4').id), 10), { text: 'This pressing adds 1 track', differs: true })
check('the single mix', P.summaryLine(P.pressingsView(slowRush.releases, byPrefix(slowRush, '3a12923d').id), 10).text, 'This pressing has another version of 1 track')
check('Dummy\'s vinyl: two things, joined', P.summaryLine(P.pressingsView(dummy.releases, byPrefix(dummy, 'f5804905').id), 20).text, 'This pressing leaves out 1 track and has another version of 1 track')
check('all alike says "all"', P.sharedBy({ count: 4, total: 4 }), 'shared by all 4 pressings')
check('the one pressing there is', P.summaryLine(P.pressingsView(wywh.releases), 1), { text: 'The only pressing MusicBrainz lists', differs: false })
const noTracks = { id: 'empty', title: 'Third', media: [{ position: 1, format: 'CD', tracks: [] }] }
check('a pressing MusicBrainz lists no tracks for', [P.pressingsView([...third.releases, noTracks], 'empty').shown.at(-1).note,
  P.summaryLine(P.pressingsView([...third.releases, noTracks], 'empty'), 18).text], ['No tracklist on MusicBrainz', 'MusicBrainz lists no tracks for this pressing'])

console.log('\nthe tracklist, and what differs in it')
const japan = byPrefix(slowRush, '452ccdb4')
const japanRows = P.trackRows(japan, P.pressingsView(slowRush.releases, japan.id).diffs.get(japan.id))
check('the Japanese CD\'s thirteenth track is a Bonus row, only on this pressing',
  japanRows.filter((row) => row.mark).map((row) => [row.number, row.title, row.length, row.mark]), [['13', 'Patience', '4:53', { kind: 'bonus', chip: 'Bonus', note: 'Only on this pressing', brief: 'only on this pressing' }]])
check('...and the other twelve are plain, numbered and timed', japanRows.slice(0, 3).map((row) => [row.number, row.title, row.length, row.mark]),
  [['1', 'One More Year', '5:22', null], ['2', 'Instant Destiny', '3:14', null], ['3', 'Borderline', '3:58', null]])
const mix = byPrefix(slowRush, '3a12923d')
check('the single mix: Borderline at 4:34 is another version, against the usual 3:58',
  P.trackRows(mix, P.pressingsView(slowRush.releases, mix.id).diffs.get(mix.id)).filter((row) => row.mark).map((row) => [row.title, row.length, row.mark]),
  [['Borderline', '4:34', { kind: 'version', chip: 'Other version', note: 'The usual version is 3:58', brief: 'usually 3:58' }]])
const tenTrack = byPrefix(dummy, '87888070')
const tenDiff = P.pressingsView(dummy.releases, tenTrack.id).diffs.get(tenTrack.id)
//? the usual length is the DEFAULT pressing's (76df3287: 3:49), not the first-listed one's (3:48)
check('a pressing\'s left-out tracks are listed with the usual length', P.leftOut(tenDiff), [{ title: 'It’s a Fire', length: '3:49' }])
check('...nothing left out, nothing listed', P.leftOut(null), [])
const renamedRelease = { id: 'renamed', media: [{ position: 1, tracks: [{ title: 'One', length: 200000 }, { title: 'Two (Remix)', length: 201000 }] }] }
const renamedDiff = T.diffTracklists(T.releaseTracks({ media: [{ tracks: [{ title: 'One', length: 200000 }, { title: 'Two', length: 200000 }] }] }), T.releaseTracks(renamedRelease))
check('a renamed track says what it is usually called', P.trackRows(renamedRelease, renamedDiff)[1].mark, { kind: 'renamed', chip: 'Renamed', note: 'Usually “Two”', brief: 'usually “Two”' })
check('no differences to mark, nothing marked', P.trackRows(japan, null).some((row) => row.mark), false)
check('no pressing, no rows', P.trackRows(null, null), [])

console.log('\ndisc headings: MusicBrainz\'s medium titles, by the album page\'s rule')
const wywhRows = P.trackRows(wywh.releases[0], null)
check('the Experience edition: "Disc 1 · 2011 Remaster" and "Disc 2 · Unreleased Tracks", each over its first track',
  wywhRows.filter((row) => row.heading).map((row) => [row.heading, row.number, row.title]),
  [['Disc 1 · 2011 Remaster', '1', 'Shine On You Crazy Diamond, Parts 1–5'], ['Disc 2 · Unreleased Tracks', '1', 'Shine On You Crazy Diamond (live at Wembley 1974)']])
check('...numbered on their own disc', wywhRows.map((row) => row.number).join(' '), '1 2 3 4 5 1 2 3 4 5 6')
check('two discs without titles: "Disc 1", "Disc 2"', P.trackRows(byPrefix(slowRush, 'e20385dc'), null).filter((row) => row.heading).map((row) => row.heading), ['Disc 1', 'Disc 2'])
check('one disc without a title: no heading at all', P.trackRows(japan, null).some((row) => row.heading), false)
const oneTitled = { id: 'one', media: [{ position: 1, title: 'Live at Wembley', tracks: [{ title: 'Speak to Me' }] }] }
check('one disc WITH a title: its heading', P.trackRows(oneTitled, null).map((row) => [row.heading, row.length]), [['Disc 1 · Live at Wembley', '']])
check('a blank title is no title', P.discHeading(3, '  '), 'Disc 3')

console.log('\nMusicBrainz\'s order changes nothing: every pressing is compared at the default\'s lengths')
{
  const mix = byPrefix(slowRush, '3a12923d')
  const mixFirst = [mix, ...slowRush.releases.filter((release) => release !== mix)]
  const view = P.pressingsView(mixFirst)
  check('the single mix listed first: still the AU CD by default, "the usual tracklist"', [view.defaultId, view.shown[0].kind, view.shown[0].note],
    [slowRush.expected.representative, 'usual', 'The usual tracklist · shared by 9 of 10 pressings'])
  check('...its line above the tracklist not amber', P.summaryLine(view, 10), { text: 'The usual tracklist, shared by 9 of 10 pressings', differs: false })
  check('...the single mix still the one with another version, 4:34 against 3:58', [...view.shown, ...view.more].find((row) => row.id === mix.id).note,
    '1 other version: Borderline, 4:34')
  const defaultRows = P.trackRows(byPrefix(slowRush, '1cf564b9'), view.diffs.get(view.defaultId))
  check('...and nothing marked on the default\'s own tracklist', defaultRows.some((row) => row.mark), false)
  check('...five usual pressings still folded', view.more.length, 5)
  //? every pressing's kind and note, whichever pressing MusicBrainz lists first
  const said = (releases) => {
    const v = P.pressingsView(releases)
    return JSON.stringify([...v.shown, ...v.more].map((row) => [row.id, row.kind, row.note]).sort())
  }
  for (const fixture of [slowRush, dummy, third]) {
    const as = said(fixture.releases)
    const moved = fixture.releases.filter((release) => said([release, ...fixture.releases.filter((other) => other !== release)]) !== as)
    check(`${fixture.group.title}: every pressing put first, the same words for every pressing`, moved.map((release) => release.id), [])
  }
}

console.log('\nthe header')
const preview = { id: slowRush.group.id, title: 'The Slow Rush', 'primary-type': 'Album', 'first-release-date': '2020-02-14', 'artist-credit': [{ name: 'Tame Impala', artist: { name: 'Tame Impala' } }] }
check('from the group Search handed over', P.pageHeader(slowRush.releases, japan, preview), { title: 'The Slow Rush', artist: 'Tame Impala', year: '2020', kind: 'Album' })
check('a cold link: from the pressings - the chosen one\'s title and credit, the earliest year, no kind',
  P.pageHeader(dummy.releases, byPrefix(dummy, 'f5804905'), null), { title: 'Dummy', artist: 'Portishead', year: '1994', kind: '' })
//? /release_group asks MusicBrainz for each pressing's group (inc=release-groups): a reload says "Album"
const instrumental = { ...byPrefix(dummy, 'f5804905'), title: 'Dummy (instrumental)' }
const withGroup = dummy.releases.map((release) => ({ ...release, 'release-group': { id: dummy.group.id, title: 'Dummy', 'primary-type': 'Album', 'first-release-date': '1994-08-22' } }))
check('a cold link with the pressings\' group: its title, kind and year - not the pressing\'s own title',
  P.pageHeader(withGroup, { ...instrumental, 'release-group': withGroup[0]['release-group'] }, null), { title: 'Dummy', artist: 'Portishead', year: '1994', kind: 'Album' })
check('the meta line', [P.metaLine({ year: '2008', kind: 'Album' }, false), P.metaLine({ year: '1994', kind: '' }, false), P.metaLine({ year: '', kind: 'EP' }, true)],
  ['2008 · Album · not in your library', '1994 · not in your library', 'EP · in your library'])
check('...says neither until the library has answered', P.metaLine({ year: '2008', kind: 'Album' }, null), '2008 · Album')
check('a group id from an address: lowercased, or null when it isn\'t one',
  [P.groupMbid('C6FC678E-E987-45C5-811C-E2BD09C8B902'), P.groupMbid(` ${slowRush.group.id} `), P.groupMbid('not-an-id'), P.groupMbid(`${slowRush.group.id}x`), P.groupMbid('')],
  ['c6fc678e-e987-45c5-811c-e2bd09c8b902', slowRush.group.id, null, null, null])
check('the cover: this pressing\'s front, then the album\'s', P.coverAddresses('r-1', 'g-1'),
  ['https://coverartarchive.org/release/r-1/front-500', 'https://coverartarchive.org/release-group/g-1/front-500'])
check('...the album\'s alone with no pressing', P.coverAddresses(null, 'g-1', 250), ['https://coverartarchive.org/release-group/g-1/front-250'])

console.log('\na pressing\'s label')
check('formats run together, digital in a word', [P.pressingFormat(byPrefix(slowRush, 'e20385dc')), P.pressingFormat(byPrefix(slowRush, '2912c9db')), P.pressingFormat(byPrefix(third, '18256dad'))],
  ['2×12" Vinyl', 'Digital', 'USB Flash Drive + 3×12" Vinyl'])
check('a worldwide release says no country; Europe in a word', [P.pressingLabel(byPrefix(slowRush, '2912c9db')), P.pressingLabel(byPrefix(dummy, '76df3287'))],
  ['Digital · 2020 · Universal Music Australia Pty Ltd.', 'CD · 1994 · Europe · Go! Beat'])
check('nothing to say: its title', P.pressingLabel({ id: 'x', title: 'Dummy' }), 'Dummy')

console.log('\neach pressing\'s facts (2.0.0-player.50): what else tells it apart, as MusicBrainz gives it')
check('Third\'s German-made CD: its labels beside the disambiguation the label line shows, its catalogue number once',
  [P.pressingLabel(byPrefix(third, '064fa38d')), P.pressingFacts(byPrefix(third, '064fa38d'))],
  ['CD · 2008 · Europe · Made in Germany by EDC', 'Official · Go! Discs / Island / Island Records Group · Cat. no. 1764013'])
check('...the Japanese CD: the full date, never the label its line already says, its catalogue number',
  [P.pressingLabel(byPrefix(third, 'cae2ac10')), P.pressingFacts(byPrefix(third, 'cae2ac10'))], ['Enhanced CD · 2008 · JP · Island', 'Official · 2008-04-30 · Cat. no. UICI-1069'])
check('...two labels with no disambiguation: the second beside the one the line shows; a catalogue number they share said once',
  P.pressingFacts(byPrefix(third, 'daa9710c')), 'Official · 2008-04-25 · Island Records Group · Cat. no. 1766401')
check('...a month alone is more than the year, and said', P.pressingFacts(byPrefix(third, '18256dad')), 'Official · 2008-04 · Cat. no. 1766390')
check('...no catalogue number entered: none said', P.pressingFacts(byPrefix(third, '5add188d')), 'Official · 2008-04-28')
check('the barcode, a promo, MusicBrainz\'s "[none]" (no catalogue number) left out, and the worldwide release its line leaves the country off',
  [P.pressingFacts({ id: 'a', status: 'Official', date: '1994-10-17', country: 'US', barcode: '042282855320', 'label-info': [{ 'catalog-number': '422-828 553-2', label: { name: 'Go! Discs' } }, { 'catalog-number': '422-828 553-2', label: { name: 'London Records' } }] }),
    P.pressingFacts({ id: 'b', status: 'Promotion', date: '1994', 'label-info': [{ 'catalog-number': '[none]', label: { name: 'Go! Discs' } }] }),
    P.pressingFacts({ id: 'c', status: 'Official', country: 'XW', barcode: '', 'release-events': [{ date: '2020-02-14' }] })],
  ['Official · 1994-10-17 · London Records · Cat. no. 422-828 553-2 · Barcode 042282855320', 'Promotion', 'Official · 2020-02-14 · Worldwide'])
check('...nothing more to say: nothing made up', [P.pressingFacts({ id: 'd' }), P.pressingFacts({ id: 'e', status: null, barcode: null, date: '2008' })], ['', ''])
//? (review: only the catalogue numbers' once was pinned) a disambiguation beside one label under three numbers
check('...one label under three catalogue numbers, beside a disambiguation: the label said once, every number',
  [P.pressingLabel(byPrefix(wywh, '588ca0a5')), P.pressingFacts(byPrefix(wywh, '588ca0a5'))],
  ['2×CD · 2011 · Europe · Experience edition', 'Official · 2011-11-04 · EMI · Cat. no. 50999 029450 2 6 / 50999 029451 2 5 / 50999 029452 2 4'])
check('...and every row of the dropdown carries its facts', P.pressingsView(third.releases).shown.map((row) => typeof row.facts === 'string' && row.facts.startsWith('Official')).every(Boolean), true)

console.log('\nthe dropdown\'s filter (2.0.0-player.50), for an album of many pressings')
{
  const view = P.pressingsView(third.releases)
  const all = [...view.shown, ...view.more]
  const ids = (rows) => rows.map((row) => row.id.slice(0, 8))
  check('more than 30 pressings gets one', P.PRESSING_FILTER_MIN, 30)
  check('nothing typed: every pressing, in the dropdown\'s order', ids(P.filterPressings(all, '  ')), ids(all))
  check('a country and a format, any order and case', [ids(P.filterPressings(all, 'jp cd')), ids(P.filterPressings(all, 'CD JP'))], [['cae2ac10'], ['cae2ac10']])
  //? (review: the check above typed no accent) accents folded both ways
  const spanish = [{ id: 'es000001', label: 'CD · 1999 · ES · Sony Music España', facts: '', note: '' }, { id: 'pt000001', label: 'CD · 1999 · PT · Edição', facts: '', note: '' },
    { id: 'gb000001', label: 'CD · 1999 · GB · Harvest', facts: '', note: '' }]
  check('...accents aside, typed or not: "espana" and "ESPAÑA" find España, "edicao" finds Edição', [ids(P.filterPressings(spanish, 'espana')), ids(P.filterPressings(spanish, 'ESPAÑA')), ids(P.filterPressings(spanish, 'edicao'))],
    [['es000001'], ['es000001'], ['pt000001']])
  check('...a catalogue number as written, with spaces for its dashes - or with nothing for them (review)',
    [ids(P.filterPressings(all, 'UICI-1069')), ids(P.filterPressings(all, 'uici 1069')), ids(P.filterPressings(all, 'UICI1069'))], [['cae2ac10'], ['cae2ac10'], ['cae2ac10']])
  //? (review: "magic doors" was in 7da10d5d's label too, its disambiguation, so nothing tested the note) a word
  //? only a note holds - 5add188d's bonus track, said in neither its label nor its facts
  const machine = all.find((row) => row.id.startsWith('5add188d'))
  check('...a word only its note holds: its bonus track',
    [ids(P.filterPressings(all, 'machine gun')), /machine gun/i.test(`${machine?.label} ${machine?.facts}`), /machine gun/i.test(machine?.note ?? '')], [['5add188d'], false, true])
  check('...a label beside a disambiguation', ids(P.filterPressings(all, 'go discs')), ['064fa38d'])
  check('...every word must match', P.filterPressings(all, 'jp mercury').length, 0)
  check('...a pressing you hold, by "in your library"', ids(P.filterPressings(P.pressingsView(third.releases, null, new Set([byPrefix(third, 'e4f5a41f').id])).shown, 'in your library')), ['e4f5a41f'])
  //? (review: nothing said how many matched, and "none" only by a region made with its words)
  check('what the filter says as it narrows: nothing for nothing typed, how many match, or that none does',
    [P.pressingFilterWords(40, ''), P.pressingFilterWords(40, '   '), P.pressingFilterWords(4, 'jp'), P.pressingFilterWords(1, ' jp cd '), P.pressingFilterWords(0, ' jp vinyl ')],
    ['', '', '4 pressings match.', '1 pressing matches.', 'No pressing matches \u201cjp vinyl\u201d.'])
}

console.log('\nthe meta line\'s word for the library, and MusicBrainz\'s pages (2.0.0-player.50)')
check('held by an id, a maybe by name alone, not held, or nothing until the library answers',
  [P.holdingOf({ held: [1], guessed: [] }), P.holdingOf({ held: [], guessed: [1] }), P.holdingOf({ held: [1], guessed: [1] }), P.holdingOf({ held: [], guessed: [] }), P.holdingOf(null)],
  ['held', 'maybe', 'held', 'not', null])
check('the album\'s page on musicbrainz.org, its id encoded', P.releaseGroupUrl('163339ab-813b-3d29-bba8-e1d5acf63cab'), 'https://musicbrainz.org/release-group/163339ab-813b-3d29-bba8-e1d5acf63cab')

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
