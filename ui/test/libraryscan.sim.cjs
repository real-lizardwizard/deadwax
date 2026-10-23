/**
 * The library scan as the app reads it: tracks arrive compact (api/library.ts's expandTracks, which
 * hooks/useLibrary.ts runs over every answer) and are put back together, and a disc's own title read
 * from the scan (lib/libraryTree.ts's discTitle, which the track inspector says).
 *
 * This was tree.sim.cjs, the main page's library explorer's tree, windowing and field choices, until
 * the main page retired in 2.0.0-player.66; what is left is what the app still runs.
 *
 * Run it with:  node ui/test/libraryscan.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-libraryscan-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/libraryTree.ts', 'src/api/library.ts',
  '--outDir', OUT, '--module', 'commonjs',
  '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

//? under lib/ because the type-only imports pull src/api into the program, which roots it at src/
const tree = require(path.join(OUT, 'lib/libraryTree.js'));
const libraryApi = require(path.join(OUT, 'api/library.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

console.log('\ntracks arrive compact and are put back together (v0.9.20, filled in place since v0.9.25)');
{
  const response = { albums: [{
    path: 'A/B', tracks: [
      { filename: '01.flac', title: 'One' },
      { filename: '02.flac', title: 'Two', artist: 'A Guest' },
      { filename: '03.flac', title: '03', has_title_tag: false },
    ],
    track_defaults: { artist: 'A', album: 'B', date: '1994' },
  }] };
  const [album] = libraryApi.expandTracks(response).albums;
  check('a track takes the album\'s shared values', [album.tracks[0].artist, album.tracks[0].album, album.tracks[0].date], ['A', 'B', '1994']);
  check('but its OWN value wins where it differs', album.tracks[1].artist, 'A Guest');
  check('has_title_tag is true unless the track said otherwise', album.tracks.map((t) => t.has_title_tag), [true, true, false]);
  check('the defaults are gone once used', 'track_defaults' in album, false);
  const titled = libraryApi.expandTracks({ albums: [{ ...response.albums[0], disc_titles: { '1': 'Side A' },
    track_defaults: { artist: 'A' } }] }).albums[0];
  check('an album\'s disc titles come through untouched (v1.1.0)', titled.disc_titles, { '1': 'Side A' });
}

console.log('\na disc\'s own title, from the scan (v1.1.0)');
{
  //? keyed by the disc as a string, as JSON hands it over; an untitled disc carries ''
  const wall = { path: 'Pink Floyd/The Wall (1979)', disc_titles: { '2': 'Live at Wembley' } };
  check('a titled disc carries its title, an untitled one none', [tree.discTitle(wall, 1), tree.discTitle(wall, 2)], ['', 'Live at Wembley']);
  check('an album the scan gave no titles to has none', [tree.discTitle({ path: 'x' }, 1), tree.discTitle({ path: 'x' }, 2)], ['', '']);
}

console.log(failures ? `\n${failures} FAILED\n` : '\nall passed\n');
process.exit(failures ? 1 : 0);
