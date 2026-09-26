/**
 * Which search results are already in the library.
 *
 * Loads interface/scripts/owned.mjs straight into Node, like sort.sim.cjs. The cases that
 * matter are the ones a wrong answer would hide: a pressing claimed by the wrong id, an untagged
 * folder claimed over a tagged one, a folder named the way the sleeve credited the artist.
 *
 * Run it with:  node ui/test/owned.sim.cjs
 */

const path = require('path');
const { pathToFileURL } = require('url');

const MODULE = pathToFileURL(
  path.resolve(__dirname, '../../interface/scripts/owned.mjs')
).href;

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

const album = (path, fields = {}) => ({
  path, artist: '', album: '', year: '', edition: '', release_mbid: '', release_group_mbid: '',
  formats: ['flac'], track_count: 10, ...fields,
});

const LIBRARY = [
  album('Portishead/Dummy (1994)', { artist: 'Portishead', album: 'Dummy', release_mbid: 'gb-cd', release_group_mbid: 'dummy' }),
  album('Portishead/Dummy (1994) [20th Anniversary Reissue 180gram]', {
    artist: 'Portishead', album: 'Dummy', edition: '20th Anniversary Reissue 180gram',
    release_mbid: 'vinyl-2014', release_group_mbid: 'dummy', formats: ['flac'],
  }),
  album('Tame Impala/Currents (2015)', { artist: 'Tame Impala', album: 'Currents', release_mbid: 'currents-cd', formats: ['m4a'] }),
  album('Old Rips/Pink Floyd - Wish You Were Here', { artist: 'Pink Floyd', album: 'Wish You Were Here (Remastered)' }),
  album('Kanye West/Donda', { artist: 'Kanye West', album: 'Donda' }),
  album('Somebody Else/Third', { artist: 'Portishead', album: 'Third', release_mbid: 'not-this-group', release_group_mbid: 'other' }),
];

(async () => {
  const O = await import(MODULE);
  const index = O.buildOwnedIndex(LIBRARY);

  console.log('names');
  check('bracketed asides, a leading The, accents and & fold away',
    [O.foldName('Wish You Were Here (Remastered)'), O.foldName('The Motörhead & Friends')],
    ['wish you were here', 'motorhead and friends']);

  console.log('\nby pressing');
  check('a pressing you hold', O.ownedForRelease(index, 'vinyl-2014').map((a) => a.edition), ['20th Anniversary Reissue 180gram']);
  check('a pressing you do not', O.ownedForRelease(index, 'jp-cd'), []);

  console.log('\nby album');
  const dummy = O.ownedForGroup(index, { groupId: 'dummy', title: 'Dummy', artists: ['Portishead'] });
  check('both editions of Dummy, by group id', dummy.held.map((a) => a.path).sort(), [
    'Portishead/Dummy (1994)', 'Portishead/Dummy (1994) [20th Anniversary Reissue 180gram]']);
  check('the card says how many', O.describeGroupOwnership(dummy).label, 'In your library · 2 editions');
  const currents = O.ownedForGroup(index, { groupId: 'currents', releaseIds: ['currents-cd', 'currents-lp'], title: 'Currents', artists: ['Tame Impala'] });
  check('an m4a album with no group id is found through its pressing', currents.held.map((a) => a.path), ['Tame Impala/Currents (2015)']);
  check('...once the group\'s pressings are known', O.ownedForGroup(index, { groupId: 'currents', title: 'Currents', artists: ['Tame Impala'] }).held.length, 0);

  console.log('\nby name, only for untagged folders');
  const wywh = O.ownedForGroup(index, { groupId: 'wywh', title: 'Wish You Were Here', artists: ['Pink Floyd'] });
  check('an untagged rip is a "maybe"', [wywh.held.length, wywh.guessed.map((a) => a.path), O.describeGroupOwnership(wywh).kind],
    [0, ['Old Rips/Pink Floyd - Wish You Were Here'], 'maybe']);
  const donda = O.ownedForGroup(index, { groupId: 'donda', title: 'Donda', artists: ['Kanye West', 'Ye'] });
  check('a folder named for the credit, not the artist\'s current name', donda.guessed.map((a) => a.path), ['Kanye West/Donda']);
  const third = O.ownedForGroup(index, { groupId: 'third', title: 'Third', artists: ['Portishead'] });
  check('a TAGGED folder of another album is never claimed by its name', [third.held.length, third.guessed.length], [0, 0]);
  check('nothing held, no chip', O.describeGroupOwnership(third), null);

  console.log('\ntooltips');
  check('an edition the folder name already carries is not said twice',
    O.describeFolders(O.ownedForRelease(index, 'vinyl-2014')),
    'Portishead/Dummy (1994) [20th Anniversary Reissue 180gram] (FLAC)');
  check('one it does not carry is', O.describeFolders([album('Rips/Dummy', { edition: 'Standard', formats: ['mp3'] })]),
    'Rips/Dummy (Standard, MP3)');

  console.log('\nwithout a library');
  check('no index answers nothing', O.ownedForGroup(null, { groupId: 'dummy' }), { held: [], guessed: [] });

  console.log(failures ? `\n${failures} FAILED` : '\nall passed');
  process.exit(failures ? 1 : 0);
})();
