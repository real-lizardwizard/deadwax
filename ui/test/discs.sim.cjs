/**
 * The disc headings on the app's album page (2.0.0-player.9) - lib/discTitles.ts, fed by
 * Navidrome's own getAlbum answer.
 *
 * James: "make sure the disc titles get picked up from navidrome". deadwax writes each disc's
 * MusicBrainz medium title as `discsubtitle`; Navidrome reads it and answers getAlbum with
 * OpenSubsonic `discTitles: [{disc, title}]`, which deadwax's route passes through untouched.
 *
 * What it pins:
 *  - "Disc 4 · <title>" for a disc with a title, "Disc 4" for one without.
 *  - Headings show when the album has more than one disc, OR when any of its discs has a title;
 *    an ordinary one-disc album has none, as before.
 *  - A song with no disc number is on disc 1; blank titles, and titles for a disc with no songs,
 *    are ignored; a disc number sent as a string still matches.
 *  - The page wires it: AlbumPage draws discHeadings() from the album's discTitles, and the album
 *    type declares them.
 *
 * Run it with:  node ui/test/discs.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-discs-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/discTitles.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const { discHeadings, discHeading, discTitleMap } = require(path.join(OUT, 'discTitles.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const songs = (...discs) => discs.map((discNumber) => (discNumber === undefined ? {} : { discNumber }))
const WEMBLEY = 'TDSOTM - Live at Wembley - From Pre-FM Master Tape'
const DOT = String.fromCharCode(0xb7)

console.log('\nwhat a heading says')
check('a disc with a title', discHeading(4, discTitleMap([{ disc: 4, title: WEMBLEY }])), `Disc 4 ${DOT} ${WEMBLEY}`)
check('a disc without one', discHeading(2, discTitleMap([{ disc: 4, title: WEMBLEY }])), 'Disc 2')

console.log('\nthe bootleg James named: four discs, the fourth titled')
{
  const album = songs(1, 1, 2, 2, 3, 4, 4)
  check('a heading at each disc\'s first song, the fourth with its title',
    discHeadings(album, [{ disc: 4, title: WEMBLEY }]),
    ['Disc 1', null, 'Disc 2', null, 'Disc 3', `Disc 4 ${DOT} ${WEMBLEY}`, null])
}

console.log('\nwhen headings show at all')
check('an ordinary one-disc album: none, as before', discHeadings(songs(1, 1, 1), undefined), [null, null, null])
check('...and none with discTitles empty', discHeadings(songs(1, 1), []), [null, null])
check('a one-disc album whose disc HAS a title: its heading', discHeadings(songs(1, 1), [{ disc: 1, title: 'Remastered' }]),
  [`Disc 1 ${DOT} Remastered`, null])
// What deadwax's own one-disc albums look like to Navidrome: files with a discsubtitle and NO disc
// number (deadwax writes none for a one-disc release). Navidrome records a disc's title only for a
// disc number above 0 (model/mediafile.go), so its answer carries no discTitles, and there is no
// heading - which is why the guide says a one-disc album shows its title only when its files carry
// a disc number (Picard's "1/1", or one set in the tag editor).
check('...but deadwax\'s own one-disc files carry no disc number, so Navidrome sends none: no heading',
  discHeadings(songs(undefined, undefined), undefined), [null, null])
check('two discs, no titles: "Disc 1", "Disc 2"', discHeadings(songs(1, 2), undefined), ['Disc 1', 'Disc 2'])
check('the Experience edition, both titled',
  discHeadings(songs(1, 1, 2), [{ disc: 1, title: '2011 Remaster' }, { disc: 2, title: 'Unreleased Tracks' }]),
  [`Disc 1 ${DOT} 2011 Remaster`, null, `Disc 2 ${DOT} Unreleased Tracks`])

console.log('\nwhat the answer may hold')
check('no disc number is disc 1', discHeadings(songs(undefined, 2), [{ disc: 1, title: 'Side one' }]),
  [`Disc 1 ${DOT} Side one`, 'Disc 2'])
check('a blank title is no title', discHeadings(songs(1, 1), [{ disc: 1, title: '   ' }]), [null, null])
check('a title for a disc with no songs is ignored', discHeadings(songs(1, 1), [{ disc: 2, title: 'Bonus' }]), [null, null])
check('a disc number sent as a string still matches', discHeadings(songs(1, 2), [{ disc: '2', title: 'Live' }]),
  ['Disc 1', `Disc 2 ${DOT} Live`])
check('a title is trimmed', discHeadings(songs(2, 3), [{ disc: 2, title: '  Live  ' }])[0], `Disc 2 ${DOT} Live`)
check('the first title given for a disc wins', discTitleMap([{ disc: 1, title: 'A' }, { disc: 1, title: 'B' }]).get(1), 'A')
check('nonsense entries are left out', [...discTitleMap([null, { disc: 0, title: 'x' }, { disc: 'two', title: 'y' }, { title: 'z' }]).keys()], [])

console.log('\nthe guide promises only what Navidrome sends')
{
  const guide = fs.readFileSync(path.join(UI, '..', 'docs/player.md'), 'utf8')
  const bullet = /- \*\*An album\*\*:[\s\S]*?(?=\n- \*\*)/.exec(guide)?.[0] ?? ''
  check('the album bullet ties a one-disc album\'s heading to its files carrying a disc number',
    /one-disc album[^.]*only when its files carry a disc number/.test(bullet.replace(/\s+/g, ' ')), true)
}

console.log('\nthe page draws it from Navidrome\'s answer')
{
  const page = fs.readFileSync(path.join(UI, 'src/player/AlbumPage.tsx'), 'utf8')
  const api = fs.readFileSync(path.join(UI, 'src/player/api.ts'), 'utf8')
  check('AlbumPage takes its headings from discHeadings(songs, album.discTitles)',
    /discHeadings\(\s*songs\s*,\s*album\?\.discTitles\s*\)/.test(page), true)
  check('...and draws each one as a disc row', /<li class="pl-disc">\{heading\}<\/li>/.test(page), true)
  check('the album type declares discTitles as OpenSubsonic sends them',
    /discTitles\?:\s*DiscTitle\[\]/.test(api) && /interface DiscTitle \{\s*disc: number\s*title: string\s*\}/.test(api), true)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
