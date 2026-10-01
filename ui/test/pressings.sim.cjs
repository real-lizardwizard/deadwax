/**
 * The album you don't have (2.0.0-player.13): its pressing dropdown, the chosen pressing's
 * tracklist and the line above it (ui/src/lib/pressings.ts), against real MusicBrainz groups as
 * MusicBrainz answered them (tests/fixtures/pressings/).
 *
 * What a wrong answer would hide: the page opening on another pressing than Get will get; a bonus
 * track, a single mix or a missing track not shown; the dropdown burying the pressing you chose
 * under "N more"; disc headings without MusicBrainz's medium titles; a pressing called "the usual
 * tracklist" that isn't - or the page reading backwards because MusicBrainz listed a single mix
 * first (every pressing is compared at the DEFAULT pressing's lengths, so no order changes a
 * word); and a cold link claiming "not in your library" before the library has said.
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
  japanRows.filter((row) => row.mark).map((row) => [row.number, row.title, row.length, row.mark]), [['13', 'Patience', '4:53', { kind: 'bonus', chip: 'Bonus', note: 'Only on this pressing' }]])
check('...and the other twelve are plain, numbered and timed', japanRows.slice(0, 3).map((row) => [row.number, row.title, row.length, row.mark]),
  [['1', 'One More Year', '5:22', null], ['2', 'Instant Destiny', '3:14', null], ['3', 'Borderline', '3:58', null]])
const mix = byPrefix(slowRush, '3a12923d')
check('the single mix: Borderline at 4:34 is another version, against the usual 3:58',
  P.trackRows(mix, P.pressingsView(slowRush.releases, mix.id).diffs.get(mix.id)).filter((row) => row.mark).map((row) => [row.title, row.length, row.mark]),
  [['Borderline', '4:34', { kind: 'version', chip: 'Other version', note: 'The usual version is 3:58' }]])
const tenTrack = byPrefix(dummy, '87888070')
const tenDiff = P.pressingsView(dummy.releases, tenTrack.id).diffs.get(tenTrack.id)
//? the usual length is the DEFAULT pressing's (76df3287: 3:49), not the first-listed one's (3:48)
check('a pressing\'s left-out tracks are listed with the usual length', P.leftOut(tenDiff), [{ title: 'It’s a Fire', length: '3:49' }])
check('...nothing left out, nothing listed', P.leftOut(null), [])
const renamedRelease = { id: 'renamed', media: [{ position: 1, tracks: [{ title: 'One', length: 200000 }, { title: 'Two (Remix)', length: 201000 }] }] }
const renamedDiff = T.diffTracklists(T.releaseTracks({ media: [{ tracks: [{ title: 'One', length: 200000 }, { title: 'Two', length: 200000 }] }] }), T.releaseTracks(renamedRelease))
check('a renamed track says what it is usually called', P.trackRows(renamedRelease, renamedDiff)[1].mark, { kind: 'renamed', chip: 'Renamed', note: 'Usually “Two”' })
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

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
