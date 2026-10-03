/**
 * The ONE download payload builder (ui/src/lib/releasePayload.ts, 2.0.0-player.15), held to what the
 * main page's two Find buttons sent BEFORE they were moved onto it.
 *
 * tests/fixtures/payloads/find-buttons.json is the old page's own output: interface/scripts/main.js
 * at 2.0.0-player.14, driven in headless Brave against live MusicBrainz, with
 * window.deadwax.openCandidates wrapped to record exactly what each Find handed the candidates
 * panel - the body and the panel's label - beside the release group and pressings it was built from.
 * Eight cases, each a thing that went wrong once or could:
 *
 *  - dummy-card / dummy-row-gb-cd: a card's Find (representativeRelease over every pressing) and a
 *    row's (its own pressing);
 *  - wish-you-were-here-experience-row: two discs, each with its own title (DISCSUBTITLE), and the
 *    album's year (1975) apart from the pressing's (2011);
 *  - donda-card / bully-card: credited "Kanye West" but filed under "Ye" - the search's name and the
 *    folder's are different on purpose - and credited Ye;
 *  - undated-group-card: a bootleg with no first-release-date, so year and original_year are null,
 *    never "N/A";
 *  - cd-dvd-row: a CD+DVD, every DVD track marked video (the "already have it" checks leave them out);
 *  - instrumental-row: an instrumental release, tagged INSTRUMENTAL so it never files into the
 *    ordinary album's folder.
 *
 * Every body must come out DEEP-EQUAL (key order aside), and every label equal - a row from (its
 * release, the group's context), a card through representativeRelease(pressings). The orchestrator
 * re-captures the changed old page and diffs it with the same file, so main.js's Finds are held to
 * this as well as the app's Get.
 *
 * In all eight the pressing is credited as its group is and each track as its recording, so they
 * can't tell which credit a field is taken from; one synthetic release where every one differs
 * (review) holds the album artist and its ids to the PRESSING's credit, each track to its OWN, the
 * year to the first release event, and the disc position to MusicBrainz's number.
 *
 * Run it with:  node ui/test/payload.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURE = path.resolve(__dirname, '../../tests/fixtures/payloads/find-buttons.json')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-payload-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/releasePayload.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const R = require(path.join(OUT, 'lib/releasePayload.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/** JSON with every object's keys sorted, so two bodies compare whatever order their keys came in. */
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical)
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]))
  return value
}

/** Where two bodies part, for a failure that says what, not just that. */
function differences(actual, expected, at = '') {
  if (JSON.stringify(canonical(actual)) === JSON.stringify(canonical(expected))) return []
  if (actual && expected && typeof actual === 'object' && typeof expected === 'object') {
    const keys = [...new Set([...Object.keys(actual), ...Object.keys(expected)])]
    return keys.flatMap((key) => differences(actual[key], expected[key], `${at}.${key}`))
  }
  return [`${at || '(top)'}: ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`]
}

const { cases } = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'))

console.log('the fixture: eight captured Finds, rows and cards')
check('the cases, by name', cases.map((c) => c.name), [
  'dummy-card', 'dummy-row-gb-cd', 'wish-you-were-here-experience-row', 'donda-card', 'bully-card',
  'undated-group-card', 'cd-dvd-row', 'instrumental-row',
])
check('...four of each button', ['card', 'row'].map((kind) => cases.filter((c) => c.kind === kind).length), [4, 4])

console.log('\nevery body deep-equal, and every label, as the old page sent them')
for (const c of cases) {
  //? a row Finds its own pressing; a card the one representativeRelease picks from every pressing
  const pressing = c.kind === 'row'
    ? c.pressings.find((release) => release.id === c.release_id)
    : R.usualPressing(c.pressings)
  check(`${c.name}: the pressing is the one the old page chose`, pressing && pressing.id, c.release_id)
  const built = R.buildDownloadRelease(c.group, pressing)
  check(`${c.name}: the body, deep-equal`, differences(built.release, c.expected), [])
  check(`${c.name}: the label`, built.label, c.label)
}

console.log('\nwhat each case is there for')
const byName = Object.fromEntries(cases.map((c) => [c.name, c]))
const built = (name) => {
  const c = byName[name]
  const pressing = c.kind === 'row' ? c.pressings.find((release) => release.id === c.release_id) : R.usualPressing(c.pressings)
  return R.buildDownloadRelease(c.group, pressing).release
}
const wywh = built('wish-you-were-here-experience-row')
check('Wish You Were Here: each disc carries its own title', [...new Set(wywh.tracks.map((t) => `${t.disc}:${t.disc_title}`))], ['1:2011 Remaster', '2:Unreleased Tracks'])
check('...the pressing\'s year and the album\'s apart', [wywh.year, wywh.original_year], ['2011', '1975'])
check('...numbered per disc and running across both', [wywh.tracks[5].disc, wywh.tracks[5].disc_position, wywh.tracks[5].position], [2, 1, 6])
const donda = built('donda-card')
check('Donda: searched as credited, filed under the name he goes by now', [donda.artist, donda.album_artist], ['Kanye West', 'Ye'])
check('...a deluxe pressing says so', donda.edition_tags, ['DELUXE'])
check('BULLY: credited Ye, filed under Ye', [built('bully-card').artist, built('bully-card').album_artist], ['Ye', 'Ye'])
const undated = built('undated-group-card')
check('an album with no first-release-date: no year at all - never "N/A"', [undated.year, undated.original_year], [null, null])
const haarp = built('cd-dvd-row')
check('a CD+DVD: the DVD\'s tracks are video, the CD\'s are not',
  [haarp.tracks.filter((t) => t.video).length, haarp.tracks.filter((t) => !t.video).length, haarp.media_format], [20, 14, 'CD + DVD-Video'])
check('an instrumental release is tagged so', built('instrumental-row').edition_tags, ['INSTRUMENTAL'])
check('a worldwide pressing keeps the raw ISO code, not the flag\'s', [built('dummy-card').country, donda.country], ['XE', 'XW'])

console.log('\nthe album as a whole, when MusicBrainz can\'t say which pressings it has')
{
  const dummy = byName['dummy-card']
  const whole = R.buildDownloadRelease(dummy.group, null)
  check('no release, no tracklist, the group named, filed under the current name', whole.release, {
    artist: 'Portishead', album_artist: 'Portishead', artist_mbids: ['8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'],
    album: 'Dummy', year: '1994', original_year: '1994', release_mbid: null,
    release_group_mbid: '48140466-cff6-3222-bd55-63c27e43190d', edition_tags: [], tracks: [],
  })
  check('...headed as the card headed it', whole.label, 'Portishead - Dummy')
  const donda = byName['donda-card']
  check('Donda as a whole: still searched as credited and filed under Ye',
    [R.buildDownloadRelease(donda.group, null).release.artist, R.buildDownloadRelease(donda.group, null).release.album_artist], ['Kanye West', 'Ye'])
}

console.log('\nmain.js\'s quirks, kept')
{
  const group = { id: 'g', title: '', 'first-release-date': 'N/A', 'artist-credit': [] }
  const context = R.groupContext(group)
  check('a credit naming nobody is "N/A"; a group with no title is "N/A"', [context.artist, context.album], ['N/A', 'N/A'])
  check('...and its album artist falls back to the credit', context.albumArtist, 'N/A')
  const release = { id: 'r', media: [{ format: 'CD', tracks: [{ title: 'A', 'artist-credit': [] }, { title: 'B' }] }] }
  const payload = R.releasePayload(release, context)
  check('a track with an empty credit is "N/A" (a credit all the same); one with none is null', payload.tracks.map((t) => t.artist), ['N/A', null])
  check('a year that isn\'t four digits is none', [payload.year, payload.original_year], [null, null])
  const titled = R.releasePayload({ id: 'r', media: [{ format: 'CD', title: '  ', tracks: [{ title: 'A' }] }, { format: 'CD', title: ' Live at Wembley ', tracks: [{ title: 'B' }] }] }, context)
  check('a disc\'s title is trimmed, and a blank one is none', titled.tracks.map((t) => t.disc_title), [null, 'Live at Wembley'])
  check('an empty ISO code falls through to the release\'s country',
    R.releasePayload({ id: 'r', country: 'GB', 'release-events': [{ area: { 'iso-3166-1-codes': [''] } }] }, context).country, 'GB')

  //? Every captured case has the pressing credited as its group is, and each track as its recording -
  //? so none of them can tell which credit a field is taken from (review). One that differs
  //? everywhere: a compilation's group, a pressing credited to one artist, a track credited apart
  //? from its recording, a date apart from the first release event's, a track numbered apart from
  //? its place on the disc.
  const credit = (name, id, now) => [{ name, joinphrase: '', artist: { id, name: now } }]
  const various = { id: 'gv', title: 'Late Orchestration', 'first-release-date': '2006-04-24', 'artist-credit': credit('Various Artists', 'va', 'Various Artists') }
  const own = R.releasePayload({
    id: 'rk', title: 'Late Orchestration', date: '2006-04-24', 'release-events': [{ date: '2005-12-01' }],
    'artist-credit': credit('Kanye West', 'ye', 'Ye'),
    media: [{ format: 'CD', position: 1, tracks: [
      { title: 'Heard ’Em Say', position: 7, 'artist-credit': credit('Kanye West', 'ye', 'Ye'),
        recording: { title: 'Heard ’Em Say', 'artist-credit': credit('Various Artists', 'va', 'Various Artists') } },
    ] }],
  }, R.groupContext(various))
  check('the album artist and its ids are the PRESSING\'s, in its current name - never the group\'s',
    [own.album_artist, own.artist_mbids], ['Ye', ['ye']])
  check('...while the search is still the group\'s credit, as the stranger typed it', own.artist, 'Various Artists')
  check('a track keeps its OWN credit and ids, over its recording\'s', [own.tracks[0].artist, own.tracks[0].artist_mbids], ['Kanye West', ['ye']])
  check('the pressing\'s year is its first release event\'s, over its own date', own.year, '2005')
  check('a track\'s place on its disc is MusicBrainz\'s number, not its index', [own.tracks[0].position, own.tracks[0].disc_position], [1, 7])
}

console.log('\nmain.js reaches the builder through the bridge, and has no builder of its own')
{
  const main = fs.readFileSync(path.resolve(UI, '../interface/scripts/main.js'), 'utf8')
  check('its two builders are gone', [/function buildExpectedFromRelease\b/.test(main), /function buildExpectedFromReleaseGroup\b/.test(main)], [false, false])
  check('...and both Finds call the bridge\'s', (main.match(/window\.deadwax\?\.buildDownloadRelease\?\.\(/g) ?? []).length, 1)
  const entry = fs.readFileSync(path.resolve(UI, 'src/main.tsx'), 'utf8')
  check('the main page\'s bundle sets it', /bridge\(\)\.buildDownloadRelease = buildDownloadRelease/.test(entry), true)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
