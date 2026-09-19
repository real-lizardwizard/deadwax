/**
 * Artist credits, and the two names that come out of one.
 *
 * A script for the same reason as the other sims: there is no JS test runner here. This one
 * exists because the rule for what an album's FOLDER is called lives twice in the browser -
 * interface/scripts/credits.mjs names a download's folder, ui/src/lib/release.ts seeds the
 * metadata editor's - and if they drift, the same album goes to one folder when downloaded and
 * another when corrected, which is the exact split this code was written to end. So every case
 * below is asked of BOTH, and a disagreement fails even where each answer looks reasonable.
 *
 * Run it with:  node ui/test/credits.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { pathToFileURL } = require('url');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'jimbrainz-credits-'));

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
    check(`${label} (download, credits.mjs)`, credits.getCurrentArtistNames(credit), expected);
    check(`${label} (editor, release.ts)`, release.currentName(credit), expected);
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
  check('the ids are the same whichever name is used', credits.getArtistIds(WATCH_THE_THRONE), ['jz', YE_ID]);
  check('...in both copies', release.creditIds(WATCH_THE_THRONE), ['jz', YE_ID]);

  console.log('\nthe editor can still find an album filed under the current name');
  const query = release.fieldedAlbumQuery('Donda', 'Ye');
  //? `artist:` on a release group is the CREDIT only - measured, `artist:"Ye"` misses the Donda
  //? credited to Kanye West. `artistname:` is what finds it.
  check('it asks for the credit OR the current name', query,
        'releasegroup:"Donda" AND (artist:"Ye" OR artistname:"Ye")');
  check('a quote in a name stays inside its phrase',
        release.fieldedAlbumQuery('The "Blue" Album', 'A').split('"').length % 2, 1);

  console.log(failures ? `\n${failures} FAILED\n` : '\nall passed\n');
  process.exit(failures ? 1 : 0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
