#!/usr/bin/env node
/**
 * The Last.fm match vectors (2.1.36, notes/lastfm.md; the design's 2.4): match-vectors.json beside this, the one
 * contract for how a Last.fm title or name meets a library song or artist - src/lastfm.py's match_key, name_key and
 * first_credit are held to it by tests/test_lastfm_vectors.py, and the iPhone app's Core will be held to a copy of it.
 *
 * Each title's `stripped` (steps 1-3: the features and the dash takes dropped) and each name's `first` are written by
 * hand, below. Each `key` is what the web's own TypeScript answers - ui/src/lib/songs.ts titleKey of `stripped`,
 * ui/src/lib/owned.ts foldName of the name - compiled as the sims compile it, so Python can't drift from the web.
 * Never edit the JSON by hand: change the cases here, then run this.
 *
 *   node tests/fixtures/lastfm/export-vectors.cjs           write match-vectors.json
 *   node tests/fixtures/lastfm/export-vectors.cjs --check   write nothing; exit 1 when it differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do. The JSON is plain ASCII (anything else as a
 * \\u escape), so any machine writes the same bytes.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const ROOT = path.resolve(__dirname, '..', '..', '..')
const UI = path.join(ROOT, 'ui')
const FILE = path.join(__dirname, 'match-vectors.json')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-lastfm-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/songs.ts', 'src/lib/owned.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const { titleKey } = require(path.join(OUT, 'lib/songs.js'))
const { foldName } = require(path.join(OUT, 'lib/owned.js'))

//? [title as Last.fm might write it, the title once steps 1-3 have dropped its features and dash takes]
const TITLES = [
  ['Let It Happen', 'Let It Happen'],
  ['Let It Happen - 2015 Remaster', 'Let It Happen'],
  ['The Less I Know the Better', 'The Less I Know the Better'],
  ['Roads - Live', 'Roads'],
  ['Roads (Live)', 'Roads (Live)'],
  ['Roads (live version)', 'Roads (live version)'],
  ['Roads [Live]', 'Roads [Live]'],
  ['Roads (Max Cooper remix)', 'Roads (Max Cooper remix)'],
  ['Sour Times - Radio Edit', 'Sour Times - Radio Edit'],
  ['Glory Box - Acoustic', 'Glory Box - Acoustic'],
  ['Mysterons - Demo', 'Mysterons - Demo'],
  ['Glory Box (Remastered 2015)', 'Glory Box (Remastered 2015)'],
  ['Lost in Yesterday (feat. Someone Else)', 'Lost in Yesterday'],
  ['Borderline [feat. Someone Else]', 'Borderline'],
  ['Is It True (with Thundercat)', 'Is It True'],
  ['Dancing with Myself', 'Dancing with Myself'],
  ['Song with Strings', 'Song with Strings'],
  ['One More Hour feat. Another Band', 'One More Hour'],
  ['One More Hour ft. Another Band', 'One More Hour'],
  ['One More Hour featuring Another Band', 'One More Hour'],
  ['One More Hour Feat. Another Band', 'One More Hour'],
  ['One More Hour (Ft. Another Band)', 'One More Hour'],
  ['One More Hour (FEATURING Another Band)', 'One More Hour'],
  ['One More Hour (feat.Another Band)', 'One More Hour'],
  ['One More Hour [ft Another Band]', 'One More Hour'],
  ['Hey Jude - Remastered 2009', 'Hey Jude'],
  ['Hey Jude - 2015 Mix', 'Hey Jude - 2015 Mix'],
  ['Paperback Writer - Mono', 'Paperback Writer'],
  ['Paperback Writer - Stereo Mix', 'Paperback Writer'],
  ['Live Forever - Remastered', 'Live Forever'],
  ['Live Forever', 'Live Forever'],
  ['Mono', 'Mono'],
  ['Stereo - Love', 'Stereo - Love'],
  ['Deliver - Deliverance', 'Deliver - Deliverance'],
  ['Elephant - Live at Wembley - 2011 Remaster', 'Elephant'],
  ['Elephant - Part 2 - Live', 'Elephant - Part 2'],
  ['Elephant – Live', 'Elephant'],
  ['Elephant—Live', 'Elephant—Live'],
  ['Elephant - Live Version', 'Elephant'],
  ['Elephant - Recorded Live from KEXP', 'Elephant'],
  ['Elephant (Live) (feat. Someone Else)', 'Elephant (Live)'],
  ['Elephant (feat. Someone Else) - Live', 'Elephant'],
  ['Elephant (Remix feat. Someone Else)', 'Elephant (Remix feat. Someone Else)'],
  ['Elephant (Edit)', 'Elephant (Edit)'],
  ['Elephant (A - Live)', 'Elephant (A - Live)'],
  ['Feels Like We Only Go Backwards feat. Someone (Live)', 'Feels Like We Only Go Backwards'],
  ['Feels Like We Only Go Backwards (feat. A & B) [Remastered]', 'Feels Like We Only Go Backwards [Remastered]'],
  ['1979 - Remastered 2012', '1979'],
  ['Bohemian Rhapsody - Remastered 2011', 'Bohemian Rhapsody'],
  ['Café del Mar', 'Café del Mar'],
  ['Don’t Stop Me Now', 'Don’t Stop Me Now'],
  ["Ain't No Sunshine", "Ain't No Sunshine"],
  ['Rhythm & Blues', 'Rhythm & Blues'],
  ['Ünïcödé Song!', 'Ünïcödé Song!'],
  ['  Spaced   Out  ', 'Spaced   Out'],
  ['Untitled #3', 'Untitled #3'],
  ['Song (Live UK 1998)', 'Song (Live UK 1998)'],
  //? (2.1.43) the dotted and the dotless i: titleKey's /iu folds neither into an i - in a take word, or as a word
  //? letter beside one - so neither aside is dropped. Python's re.IGNORECASE folded both, and keyed these apart
  ['Roads (L' + String.fromCharCode(0x130) + 'VE)', 'Roads (L' + String.fromCharCode(0x130) + 'VE)'],
  ['Roads (l' + String.fromCharCode(0x131) + 've)', 'Roads (l' + String.fromCharCode(0x131) + 've)'],
  ['Glory Box (L' + String.fromCharCode(0x130) + 've at Roseland)', 'Glory Box (L' + String.fromCharCode(0x130) + 've at Roseland)'],
  ['Numb (Remastered' + String.fromCharCode(0x130) + ')', 'Numb (Remastered' + String.fromCharCode(0x130) + ')'],
  ['Numb (Remastered' + String.fromCharCode(0x131) + ')', 'Numb (Remastered' + String.fromCharCode(0x131) + ')'],
  //? what /iu does fold: the long s into an s, and the Kelvin sign, a word letter, beside a take word
  ['Mysterons (Rema' + String.fromCharCode(0x17f) + 'tered)', 'Mysterons (Rema' + String.fromCharCode(0x17f) + 'tered)'],
  ['Roads (Live' + String.fromCharCode(0x212a) + ')', 'Roads (Live' + String.fromCharCode(0x212a) + ')'],
  //? steps 1-3 are Python's own, as the app's port has them: there re.IGNORECASE's dotted and dotless i are an i
  ['Roads - L' + String.fromCharCode(0x130) + 've', 'Roads'],
  ['Glory Box (Featur' + String.fromCharCode(0x131) + 'ng Someone Else)', 'Glory Box'],
]

//? [an artist credit as Last.fm might write it, its first name]
const NAMES = [
  ['Tame Impala', 'Tame Impala'],
  ['The Beatles', 'The Beatles'],
  ['Beatles', 'Beatles'],
  ['The The', 'The The'],
  ['Theatre of Tragedy', 'Theatre of Tragedy'],
  ['Simon & Garfunkel', 'Simon & Garfunkel'],
  ['Simon and Garfunkel', 'Simon and Garfunkel'],
  ['Earth, Wind & Fire', 'Earth, Wind & Fire'],
  ['Crosby, Stills, Nash & Young', 'Crosby, Stills, Nash & Young'],
  ['Tame Impala feat. Kanye West', 'Tame Impala'],
  ['Portishead ft. Someone Else', 'Portishead'],
  ['Mumford & Sons ft. Baaba Maal', 'Mumford & Sons'],
  ['Kendrick Lamar FEATURING SZA', 'Kendrick Lamar'],
  ['Beyoncé Feat. JAY-Z', 'Beyoncé'],
  ['Daft Punk • Pharrell Williams', 'Daft Punk'],
  ['Björk', 'Björk'],
  ['Sigur Rós', 'Sigur Rós'],
  ['Motörhead', 'Motörhead'],
  ['Guns N’ Roses', 'Guns N’ Roses'],
  ['Wu-Tang Clan', 'Wu-Tang Clan'],
  ['AC/DC', 'AC/DC'],
  ['Florence + the Machine', 'Florence + the Machine'],
  ['Portishead (UK band)', 'Portishead (UK band)'],
  ['Dance Gavin Dance', 'Dance Gavin Dance'],
  ['Various Artists', 'Various Artists'],
  ['  Tame   Impala  ', 'Tame   Impala'],
  ['Featherweight', 'Featherweight'],
]

function ascii(text) {
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i)
    out += code < 0x7f ? text[i] : '\\u' + code.toString(16).padStart(4, '0')
  }
  return out
}

const vectors = {
  _note: 'Written by tests/fixtures/lastfm/export-vectors.cjs - never by hand. `stripped` and `first` are its hand-written cases; '
    + '`key` is the web TypeScript\'s own: songs.ts titleKey of `stripped`, owned.ts foldName of the name. src/lastfm.py match_key, '
    + 'name_key and first_credit are held to it by tests/test_lastfm_vectors.py.',
  titles: TITLES.map(([title, stripped]) => ({ title, stripped, key: titleKey(stripped) })),
  names: NAMES.map(([name, first]) => ({ name, key: foldName(name), first })),
}

const text = ascii(JSON.stringify(vectors, null, 1)) + '\n'
fs.rmSync(OUT, { recursive: true, force: true })

if (CHECK) {
  const now = fs.existsSync(FILE) ? fs.readFileSync(FILE, 'utf8') : ''
  if (now !== text) {
    console.error('match-vectors.json is not what the TypeScript answers now: run node tests/fixtures/lastfm/export-vectors.cjs')
    process.exit(1)
  }
  console.log('match-vectors.json is current')
} else {
  fs.writeFileSync(FILE, text)
  console.log(`wrote ${path.relative(ROOT, FILE)}: ${vectors.titles.length} titles, ${vectors.names.length} names`)
}
