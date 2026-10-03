/**
 * Artist credits, and the two names that come out of one.
 *
 * A script for the same reason as the other sims: there is no JS test runner here. The rule for an
 * album's current-name credit lives twice in the browser. ui/src/lib/release.ts's currentName()
 * names a download's FOLDER (through lib/releasePayload.ts, the one payload builder, since
 * 2.0.0-player.15) and seeds the metadata editor's - one function, so a download and a correction
 * can't part. interface/scripts/credits.mjs's getCurrentArtistNames() is the main page's copy, which
 * since 2.0.0-player.15 only DRAWS: it is a name the card's "in your library" match tries, so a
 * drift would mark a card wrong. Every case below is still asked of BOTH, and a disagreement fails
 * even where each answer looks reasonable.
 *
 * Run it with:  node ui/test/credits.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { pathToFileURL } = require('url');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-credits-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/release.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

//? under lib/ because the type-only imports pull src/api into the program, which roots it at src/
const release = require(path.join(OUT, 'lib/release.js'));
const MODULE = pathToFileURL(path.resolve(UI, '../interface/scripts/credits.mjs')).href;

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

//? Real credits, as MusicBrainz returns them: `name` is what the sleeve said, `artist.name` is what
//? the artist is called now.
const YE_ID = '164f0d73-1234-4e2c-8743-d77bf2191051';
const DONDA = [{ name: 'Kanye West', joinphrase: '', artist: { id: YE_ID, name: 'Ye' } }];
const BULLY = [{ name: 'Ye', joinphrase: '', artist: { id: YE_ID, name: 'Ye' } }];
const WATCH_THE_THRONE = [
  { name: 'Jay‐Z', joinphrase: ' & ', artist: { id: 'jz', name: 'JAŸ‐Z' } },
  { name: 'Kanye West', joinphrase: '', artist: { id: YE_ID, name: 'Ye' } },
];
const NO_ARTIST_OBJECT = [{ name: 'Somebody', joinphrase: '' }];

(async () => {
  const credits = await import(MODULE);

  //? every case, asked of both copies, which must agree
  function both(label, credit, expected) {
    check(`${label} (the main page's card, credits.mjs)`, credits.getCurrentArtistNames(credit), expected);
    check(`${label} (a download and the editor, release.ts)`, release.currentName(credit), expected);
  }

  console.log('\none artist, one folder, whatever the sleeve said');
  both('Donda, credited to Kanye West, is filed under Ye', DONDA, 'Ye');
  both('BULLY, credited to Ye, is filed under Ye', BULLY, 'Ye');

  console.log('\nthe join phrases survive; only the names are brought up to date');
  both('a collaboration stays a collaboration', WATCH_THE_THRONE, 'JAŸ‐Z & Ye');

  console.log('\nwhat the credit ALONE can say');
  both('no artist object: the credited name is all there is', NO_ARTIST_OBJECT, 'Somebody');
  both('nothing credited is nothing - the caller falls back rather than filing under "N/A"',
       undefined, '');

  console.log('\nthe credit itself is untouched - it is what Soulseek folders are called');
  check('the download still searches Soulseek for "Kanye West"', credits.getArtistNames(DONDA), 'Kanye West');
  check('...and the editor agrees on the credit too', release.creditName(DONDA), 'Kanye West');
  check('the ids are the same whichever name is used', release.creditIds(WATCH_THE_THRONE), ['jz', YE_ID]);
  //? only the payload builders took ids, and they are one, in TypeScript, since 2.0.0-player.15
  check('...and credits.mjs keeps no copy of that rule - nothing on the main page reads one', 'getArtistIds' in credits, false);

  console.log('\nthe editor can still find an album filed under the current name');
  const query = release.fieldedAlbumQuery('Donda', 'Ye');
  //? `artist:` on a release group is the CREDIT only - measured, `artist:"Ye"` misses the Donda
  //? credited to Kanye West. `artistname:` is what finds it.
  check('it asks for the credit OR the current name', query,
        'releasegroup:"Donda" AND (artist:"Ye" OR artistname:"Ye")');
  check('a quote in a name stays inside its phrase',
        release.fieldedAlbumQuery('The "Blue" Album', 'A').split('"').length % 2, 1);

  console.log('\na track that never arrives as audio - one rule, for a download and the editor alike');
  //? what the "already have it" checks leave out (store_index.audio_tracks). Since 2.0.0-player.15 a
  //? download's payload is built by lib/releasePayload.ts, which marks tracks with release.ts's
  //? isVideoTrack, as the editor's does - credits.mjs's twin went with main.js's two builders
  const VIDEO_CASES = [
    ['a CD track', { format: 'CD' }, { recording: { video: false } }, false],
    ['a track on a DVD-Video', { format: 'DVD-Video' }, { recording: {} }, true],
    ['a track on a Blu-ray', { format: 'Blu-ray' }, {}, true],
    ['a plain "DVD" may be DVD-Audio - only its recording says', { format: 'DVD' }, { recording: { video: false } }, false],
    ['...and when the recording is a video, it is', { format: 'DVD' }, { recording: { video: true } }, true],
    ['a video recording on a CD (an enhanced CD\'s clip)', { format: 'CD' }, { recording: { video: true } }, true],
    ['Blu-spec CD is a CD, whatever its name', { format: 'Blu-spec CD' }, {}, false],
    ['no medium format and no recording', {}, undefined, false],
  ];
  check('credits.mjs keeps no copy of it - one rule, not two', 'isVideoTrack' in credits, false);
  for (const [label, medium, track, expected] of VIDEO_CASES) {
    check(label, release.isVideoTrack(medium, track), expected);
  }

  console.log(failures ? `\n${failures} FAILED\n` : '\nall passed\n');
  process.exit(failures ? 1 : 0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
